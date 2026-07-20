using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.Json;
using UsageMonitoring.App.Models;

namespace UsageMonitoring.App.Services;

public sealed class CodexAppServerClient : ICodexAppServerClient
{
    private readonly CodexExecutableLocator _locator;
    private readonly WindowsSystemProxyService _proxyService = new();
    private readonly SemaphoreSlim _writeGate = new(1, 1);
    private readonly ConcurrentDictionary<long, TaskCompletionSource<JsonElement>> _pending = new();
    private readonly CancellationTokenSource _lifetimeCts = new();
    private readonly object _snapshotGate = new();
    private CancellationTokenSource? _sessionCts;
    private Process? _process;
    private PeriodicTimer? _pollTimer;
    private Task? _stdoutTask;
    private Task? _stderrTask;
    private Task? _pollTask;
    private long _requestId;
    private CodexQuotaSnapshot _latestSnapshot = CodexQuotaSnapshot.Empty;

    public CodexAppServerClient(CodexExecutableLocator locator, string? preferredExecutablePath = null)
    {
        _locator = locator;
        PreferredExecutablePath = preferredExecutablePath;
        ConnectionState = AppServerConnectionState.Disconnected;
    }

    public event EventHandler<CodexQuotaSnapshot>? QuotaUpdated;

    public event EventHandler<AppServerConnectionState>? ConnectionStateChanged;

    public DateTimeOffset? LastSyncedAtUtc { get; private set; }

    public AppServerConnectionState ConnectionState { get; private set; }

    public string? ExecutablePath { get; private set; }

    public string? PreferredExecutablePath { get; set; }

    public bool UseSystemProxy { get; set; } = true;

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
        ApplyProxyEnvironment(startInfo);

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

        _sessionCts = CancellationTokenSource.CreateLinkedTokenSource(_lifetimeCts.Token);
        _stdoutTask = Task.Run(() => ReadOutputLoopAsync(_sessionCts.Token), _sessionCts.Token);
        _stderrTask = Task.Run(() => ReadErrorLoopAsync(_sessionCts.Token), _sessionCts.Token);

        try
        {
            await InitializeAsync(cancellationToken);
            await RefreshRateLimitsAsync(cancellationToken);

            _pollTimer = new PeriodicTimer(TimeSpan.FromMinutes(1));
            _pollTask = Task.Run(() => PollLoopAsync(_sessionCts.Token), _sessionCts.Token);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            UpdateConnectionState(AppServerConnectionState.Disconnected);
        }
        catch
        {
            UpdateConnectionState(AppServerConnectionState.Degraded);
        }
    }

    public async Task RestartAsync(CancellationToken cancellationToken = default)
    {
        await StopProcessAsync();
        await StartAsync(cancellationToken);
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
            var snapshot = CodexQuotaParser.ParseReadResponse(result, DateTimeOffset.UtcNow);
            SetLatestSnapshot(snapshot);
            PublishQuota(snapshot);
        }
        catch
        {
            UpdateConnectionState(AppServerConnectionState.Degraded);
        }
    }

    public async ValueTask DisposeAsync()
    {
        _lifetimeCts.Cancel();
        await StopProcessAsync();

        _writeGate.Dispose();
        _lifetimeCts.Dispose();
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

        await SendNotificationAsync("initialized", null, cancellationToken);

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
                    var update = CodexQuotaParser.ParseRateLimitSnapshot(
                        rateLimitsElement,
                        DateTimeOffset.UtcNow);
                    var merged = MergeLatestSnapshot(
                        update,
                        CodexQuotaParser.GetLimitId(rateLimitsElement));
                    PublishQuota(merged);
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

    private async Task SendNotificationAsync(
        string method,
        object? parameters,
        CancellationToken cancellationToken)
    {
        if (_process is null || _process.HasExited)
        {
            throw new InvalidOperationException("Codex app-server is not running.");
        }

        await _writeGate.WaitAsync(cancellationToken);
        try
        {
            var payload = new Dictionary<string, object?>
            {
                ["jsonrpc"] = "2.0",
                ["method"] = method
            };

            if (parameters is not null)
            {
                payload["params"] = parameters;
            }

            await _process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(payload));
            await _process.StandardInput.FlushAsync();
        }
        finally
        {
            _writeGate.Release();
        }
    }

    private void PublishQuota(CodexQuotaSnapshot snapshot)
    {
        LastSyncedAtUtc = snapshot.SyncedAtUtc;
        UpdateConnectionState(AppServerConnectionState.Connected);
        QuotaUpdated?.Invoke(this, snapshot);
    }

    private void SetLatestSnapshot(CodexQuotaSnapshot snapshot)
    {
        lock (_snapshotGate)
        {
            _latestSnapshot = snapshot;
        }
    }

    private CodexQuotaSnapshot MergeLatestSnapshot(
        CodexQuotaSnapshot update,
        string? updatedLimitId)
    {
        lock (_snapshotGate)
        {
            _latestSnapshot = CodexQuotaParser.Merge(_latestSnapshot, update, updatedLimitId);
            return _latestSnapshot;
        }
    }

    private void OnProcessExited(object? sender, EventArgs e)
    {
        foreach (var pending in _pending.Values)
        {
            pending.TrySetCanceled();
        }

        _sessionCts?.Cancel();
        UpdateConnectionState(LastSyncedAtUtc is null
            ? AppServerConnectionState.Disconnected
            : AppServerConnectionState.Degraded);
    }

    private void ApplyProxyEnvironment(ProcessStartInfo startInfo)
    {
        RemoveProxyVariables(startInfo);
        if (!UseSystemProxy)
        {
            return;
        }

        var proxyEnvironment = _proxyService.GetProxyEnvironment();
        if (!proxyEnvironment.IsEnabled)
        {
            return;
        }

        SetProxyVariable(startInfo, "HTTP_PROXY", proxyEnvironment.HttpProxy);
        SetProxyVariable(startInfo, "HTTPS_PROXY", proxyEnvironment.HttpsProxy);
        SetProxyVariable(startInfo, "ALL_PROXY", proxyEnvironment.AllProxy);
        SetProxyVariable(startInfo, "http_proxy", proxyEnvironment.HttpProxy);
        SetProxyVariable(startInfo, "https_proxy", proxyEnvironment.HttpsProxy);
        SetProxyVariable(startInfo, "all_proxy", proxyEnvironment.AllProxy);
        startInfo.Environment["NO_PROXY"] = "127.0.0.1,localhost";
        startInfo.Environment["no_proxy"] = "127.0.0.1,localhost";
    }

    private static void RemoveProxyVariables(ProcessStartInfo startInfo)
    {
        var keys = new[]
        {
            "HTTP_PROXY",
            "HTTPS_PROXY",
            "ALL_PROXY",
            "NO_PROXY",
            "http_proxy",
            "https_proxy",
            "all_proxy",
            "no_proxy"
        };

        foreach (var key in keys)
        {
            startInfo.Environment.Remove(key);
        }
    }

    private static void SetProxyVariable(ProcessStartInfo startInfo, string key, string? value)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            startInfo.Environment[key] = value;
        }
    }

    private async Task StopProcessAsync()
    {
        _pollTimer?.Dispose();
        _pollTimer = null;

        _sessionCts?.Cancel();

        foreach (var pending in _pending.Values)
        {
            pending.TrySetCanceled();
        }
        _pending.Clear();

        if (_process is not null)
        {
            _process.Exited -= OnProcessExited;

            if (!_process.HasExited)
            {
                try
                {
                    _process.Kill(entireProcessTree: true);
                }
                catch
                {
                }
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

        _sessionCts?.Dispose();
        _sessionCts = null;

        _stdoutTask = null;
        _stderrTask = null;
        _pollTask = null;

        _process?.Dispose();
        _process = null;
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
