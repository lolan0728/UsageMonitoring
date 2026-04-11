using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.Json;
using UsageMonitoring.App.Models;

namespace UsageMonitoring.App.Services;

public sealed class CodexAppServerClient : ICodexAppServerClient
{
    private readonly CodexExecutableLocator _locator;
    private readonly SemaphoreSlim _writeGate = new(1, 1);
    private readonly ConcurrentDictionary<long, TaskCompletionSource<JsonElement>> _pending = new();
    private readonly CancellationTokenSource _lifetimeCts = new();
    private Process? _process;
    private PeriodicTimer? _pollTimer;
    private Task? _stdoutTask;
    private Task? _stderrTask;
    private Task? _pollTask;
    private long _requestId;

    public CodexAppServerClient(CodexExecutableLocator locator, string? preferredExecutablePath = null)
    {
        _locator = locator;
        PreferredExecutablePath = preferredExecutablePath;
        ConnectionState = AppServerConnectionState.Disconnected;
    }

    public event EventHandler<IReadOnlyList<RateLimitBucket>>? RateLimitsUpdated;

    public event EventHandler<AppServerConnectionState>? ConnectionStateChanged;

    public DateTimeOffset? LastSyncedAtUtc { get; private set; }

    public AppServerConnectionState ConnectionState { get; private set; }

    public string? ExecutablePath { get; private set; }

    public string? PreferredExecutablePath { get; set; }

    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        if (_process is not null && !_process.HasExited)
        {
            return;
        }

        UpdateConnectionState(AppServerConnectionState.Connecting);
        ExecutablePath = _locator.Locate(PreferredExecutablePath);

        if (string.IsNullOrWhiteSpace(ExecutablePath))
        {
            ExecutablePath = null;
            UpdateConnectionState(AppServerConnectionState.MissingExecutable);
            return;
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = ExecutablePath,
            Arguments = "app-server --analytics-default-enabled",
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        _process = new Process
        {
            StartInfo = startInfo,
            EnableRaisingEvents = true
        };
        _process.Exited += OnProcessExited;

        try
        {
            _process.Start();
        }
        catch
        {
            UpdateConnectionState(AppServerConnectionState.Degraded);
            return;
        }

        _stdoutTask = Task.Run(() => ReadOutputLoopAsync(_lifetimeCts.Token), _lifetimeCts.Token);
        _stderrTask = Task.Run(() => ReadErrorLoopAsync(_lifetimeCts.Token), _lifetimeCts.Token);

        await InitializeAsync(cancellationToken);
        await RefreshRateLimitsAsync(cancellationToken);

        _pollTimer = new PeriodicTimer(TimeSpan.FromMinutes(1));
        _pollTask = Task.Run(() => PollLoopAsync(_lifetimeCts.Token), _lifetimeCts.Token);
    }

    public async Task RefreshRateLimitsAsync(CancellationToken cancellationToken = default)
    {
        if (_process is null || _process.HasExited)
        {
            return;
        }

        try
        {
            var result = await SendRequestAsync("account/rateLimits/read", null, cancellationToken);
            if (!result.TryGetProperty("rateLimits", out var rateLimitsElement))
            {
                UpdateConnectionState(AppServerConnectionState.Degraded);
                return;
            }

            PublishRateLimits(ToRateLimitBuckets(rateLimitsElement));
        }
        catch
        {
            UpdateConnectionState(AppServerConnectionState.Degraded);
        }
    }

    public async ValueTask DisposeAsync()
    {
        _lifetimeCts.Cancel();

        if (_pollTimer is not null)
        {
            _pollTimer.Dispose();
        }

        if (_process is not null && !_process.HasExited)
        {
            try
            {
                _process.Kill(entireProcessTree: true);
            }
            catch
            {
            }
        }

        if (_stdoutTask is not null)
        {
            await IgnoreFailuresAsync(_stdoutTask);
        }

        if (_stderrTask is not null)
        {
            await IgnoreFailuresAsync(_stderrTask);
        }

        if (_pollTask is not null)
        {
            await IgnoreFailuresAsync(_pollTask);
        }

        _writeGate.Dispose();
        _lifetimeCts.Dispose();
        _process?.Dispose();
    }

    private async Task InitializeAsync(CancellationToken cancellationToken)
    {
        await SendRequestAsync(
            "initialize",
            new
            {
                clientInfo = new
                {
                    name = "UsageMonitoring",
                    title = "Usage Monitoring",
                    version = "0.1.0"
                },
                capabilities = new
                {
                    experimentalApi = true
                }
            },
            cancellationToken);

        UpdateConnectionState(AppServerConnectionState.Connected);
    }

    private async Task PollLoopAsync(CancellationToken cancellationToken)
    {
        if (_pollTimer is null)
        {
            return;
        }

        try
        {
            while (await _pollTimer.WaitForNextTickAsync(cancellationToken))
            {
                await RefreshRateLimitsAsync(cancellationToken);
            }
        }
        catch (OperationCanceledException)
        {
        }
    }

    private async Task ReadOutputLoopAsync(CancellationToken cancellationToken)
    {
        if (_process is null)
        {
            return;
        }

        try
        {
            while (!cancellationToken.IsCancellationRequested && !_process.HasExited)
            {
                var line = await _process.StandardOutput.ReadLineAsync();
                if (string.IsNullOrWhiteSpace(line))
                {
                    if (_process.HasExited)
                    {
                        break;
                    }

                    continue;
                }

                HandleIncomingLine(line);
            }
        }
        catch (ObjectDisposedException)
        {
        }
        catch (InvalidOperationException)
        {
        }
    }

    private async Task ReadErrorLoopAsync(CancellationToken cancellationToken)
    {
        if (_process is null)
        {
            return;
        }

        try
        {
            while (!cancellationToken.IsCancellationRequested && !_process.HasExited)
            {
                _ = await _process.StandardError.ReadLineAsync();
            }
        }
        catch (ObjectDisposedException)
        {
        }
        catch (InvalidOperationException)
        {
        }
    }

    private void HandleIncomingLine(string line)
    {
        using var document = JsonDocument.Parse(line);
        var root = document.RootElement;

        if (root.TryGetProperty("id", out var idElement))
        {
            var id = idElement.ValueKind == JsonValueKind.Number ? idElement.GetInt64() : 0;
            if (_pending.TryRemove(id, out var pending))
            {
                if (root.TryGetProperty("result", out var resultElement))
                {
                    pending.TrySetResult(resultElement.Clone());
                    return;
                }

                if (root.TryGetProperty("error", out var errorElement))
                {
                    pending.TrySetException(new InvalidOperationException(errorElement.ToString()));
                    return;
                }
            }
        }

        if (!root.TryGetProperty("method", out var methodElement))
        {
            return;
        }

        var method = methodElement.GetString();
        if (string.IsNullOrWhiteSpace(method))
        {
            return;
        }

        var parameters = root.TryGetProperty("params", out var paramsElement) ? paramsElement : default;

        switch (method)
        {
            case "account/rateLimits/updated":
                if (parameters.ValueKind == JsonValueKind.Object &&
                    parameters.TryGetProperty("rateLimits", out var rateLimitsElement))
                {
                    PublishRateLimits(ToRateLimitBuckets(rateLimitsElement));
                }
                break;
        }
    }

    private async Task<JsonElement> SendRequestAsync(
        string method,
        object? parameters,
        CancellationToken cancellationToken)
    {
        if (_process is null || _process.HasExited)
        {
            throw new InvalidOperationException("Codex app-server is not running.");
        }

        var requestId = Interlocked.Increment(ref _requestId);
        var tcs = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
        _pending[requestId] = tcs;

        await _writeGate.WaitAsync(cancellationToken);
        try
        {
            var payload = new Dictionary<string, object?>
            {
                ["jsonrpc"] = "2.0",
                ["id"] = requestId,
                ["method"] = method
            };

            if (parameters is not null)
            {
                payload["params"] = parameters;
            }

            var line = JsonSerializer.Serialize(payload);
            await _process.StandardInput.WriteLineAsync(line);
            await _process.StandardInput.FlushAsync();
        }
        finally
        {
            _writeGate.Release();
        }

        return await tcs.Task.WaitAsync(TimeSpan.FromSeconds(15), cancellationToken);
    }

    private void PublishRateLimits(IReadOnlyList<RateLimitBucket> buckets)
    {
        if (buckets.Count == 0)
        {
            return;
        }

        LastSyncedAtUtc = buckets.Max(bucket => bucket.SyncedAtUtc);
        UpdateConnectionState(AppServerConnectionState.Connected);
        RateLimitsUpdated?.Invoke(this, buckets);
    }

    private static IReadOnlyList<RateLimitBucket> ToRateLimitBuckets(JsonElement rateLimitsElement)
    {
        var syncedAt = DateTimeOffset.UtcNow;
        var limitId = GetOptionalString(rateLimitsElement, "limitId");
        var limitName = GetOptionalString(rateLimitsElement, "limitName");

        var items = new List<RateLimitBucket>();
        if (rateLimitsElement.TryGetProperty("primary", out var primary) && primary.ValueKind == JsonValueKind.Object)
        {
            var primaryBucket = ToRateLimitBucket(primary, syncedAt, limitId, limitName);
            if (primaryBucket is not null)
            {
                items.Add(primaryBucket with
                {
                    Label = BuildWindowLabel(primaryBucket.WindowDurationMins)
                });
            }
        }

        if (rateLimitsElement.TryGetProperty("secondary", out var secondary) && secondary.ValueKind == JsonValueKind.Object)
        {
            var secondaryBucket = ToRateLimitBucket(secondary, syncedAt, limitId, limitName);
            if (secondaryBucket is not null)
            {
                items.Add(secondaryBucket with
                {
                    Label = BuildWindowLabel(secondaryBucket.WindowDurationMins)
                });
            }
        }

        return items;
    }

    private static RateLimitBucket? ToRateLimitBucket(
        JsonElement element,
        DateTimeOffset syncedAt,
        string? limitId,
        string? limitName)
    {
        var windowDurationMins = GetOptionalInt32(element, "windowDurationMins");
        if (windowDurationMins <= 0)
        {
            return null;
        }

        var usedPercent = Math.Clamp(GetOptionalInt32(element, "usedPercent"), 0, 100);
        var remainingPercent = Math.Clamp(100 - usedPercent, 0, 100);
        var resetsAtUnix = GetOptionalInt64(element, "resetsAt");

        return new RateLimitBucket(
            Label: BuildWindowLabel(windowDurationMins),
            WindowDurationMins: windowDurationMins,
            UsedPercent: usedPercent,
            RemainingPercent: remainingPercent,
            ResetsAtUtc: resetsAtUnix is long value ? DateTimeOffset.FromUnixTimeSeconds(value) : null,
            SyncedAtUtc: syncedAt,
            LimitId: limitId,
            LimitName: limitName);
    }

    private void OnProcessExited(object? sender, EventArgs e)
    {
        foreach (var pending in _pending.Values)
        {
            pending.TrySetCanceled();
        }

        UpdateConnectionState(LastSyncedAtUtc is null
            ? AppServerConnectionState.Disconnected
            : AppServerConnectionState.Degraded);
    }

    private void UpdateConnectionState(AppServerConnectionState state)
    {
        if (ConnectionState == state)
        {
            return;
        }

        ConnectionState = state;
        ConnectionStateChanged?.Invoke(this, state);
    }

    private static string BuildWindowLabel(int windowDurationMins) => windowDurationMins switch
    {
        300 => "5h",
        10080 => "1w",
        >= 1440 when windowDurationMins % 1440 == 0 => $"{windowDurationMins / 1440}d",
        >= 60 when windowDurationMins % 60 == 0 => $"{windowDurationMins / 60}h",
        _ => $"{windowDurationMins}m"
    };

    private static int GetOptionalInt32(JsonElement element, string propertyName)
    {
        if (element.ValueKind != JsonValueKind.Object ||
            !element.TryGetProperty(propertyName, out var property))
        {
            return 0;
        }

        return property.ValueKind switch
        {
            JsonValueKind.Number when property.TryGetInt32(out var value) => value,
            JsonValueKind.Number when property.TryGetInt64(out var longValue) => (int)longValue,
            _ => 0
        };
    }

    private static long? GetOptionalInt64(JsonElement element, string propertyName)
    {
        if (element.ValueKind != JsonValueKind.Object ||
            !element.TryGetProperty(propertyName, out var property))
        {
            return null;
        }

        if (property.ValueKind == JsonValueKind.Number && property.TryGetInt64(out var value))
        {
            return value;
        }

        return null;
    }

    private static string? GetOptionalString(JsonElement element, string propertyName)
    {
        if (element.ValueKind != JsonValueKind.Object ||
            !element.TryGetProperty(propertyName, out var property))
        {
            return null;
        }

        return property.ValueKind == JsonValueKind.String ? property.GetString() : null;
    }

    private static async Task IgnoreFailuresAsync(Task task)
    {
        try
        {
            await task;
        }
        catch
        {
        }
    }
}
