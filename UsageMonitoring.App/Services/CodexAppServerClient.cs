using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using UsageMonitoring.App.Models;

namespace UsageMonitoring.App.Services;

public sealed class CodexAppServerClient : ICodexAppServerClient
{
    private readonly CodexExecutableLocator _locator;
    private readonly WindowsSystemProxyService _proxyService = new();
    private readonly SemaphoreSlim _operationGate = new(1, 1);
    private readonly SemaphoreSlim _writeGate = new(1, 1);
    private readonly ConcurrentDictionary<long, TaskCompletionSource<JsonElement>> _pending = new();
    private readonly CancellationTokenSource _lifetimeCts = new();
    private readonly object _snapshotGate = new();
    private CancellationTokenSource? _sessionCts;
    private Process? _process;
    private Task? _stdoutTask;
    private Task? _stderrTask;
    private Task? _pollTask;
    private long _requestId;
    private bool _initialized;
    private readonly TimeSpan _pollInterval;
    private readonly TimeSpan _retryInterval;
    private readonly TimeSpan _requestTimeout;
    private readonly Func<string, ProcessStartInfo> _startInfoFactory;
    private CodexQuotaSnapshot _latestSnapshot = CodexQuotaSnapshot.Empty;

    public CodexAppServerClient(CodexExecutableLocator locator, string? preferredExecutablePath = null)
        : this(locator, preferredExecutablePath, TimeSpan.FromMinutes(1),
            TimeSpan.FromSeconds(15), TimeSpan.FromSeconds(15))
    {
    }

    internal CodexAppServerClient(
        CodexExecutableLocator locator,
        string? preferredExecutablePath,
        TimeSpan pollInterval,
        TimeSpan retryInterval,
        TimeSpan requestTimeout,
        Func<string, ProcessStartInfo>? startInfoFactory = null)
    {
        _locator = locator;
        _pollInterval = pollInterval;
        _retryInterval = retryInterval;
        _requestTimeout = requestTimeout;
        _startInfoFactory = startInfoFactory ?? (path => new ProcessStartInfo
        {
            FileName = path,
            Arguments = "app-server --analytics-default-enabled",
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        });
        PreferredExecutablePath = preferredExecutablePath;
        ConnectionState = AppServerConnectionState.Disconnected;
    }

    public event EventHandler<CodexQuotaSnapshot>? QuotaUpdated;

    public event EventHandler<AppServerConnectionState>? ConnectionStateChanged;

    public DateTimeOffset? LastSyncedAtUtc { get; private set; }

    public AppServerConnectionState ConnectionState { get; private set; }

    public string? ExecutablePath { get; private set; }

    public string? LastError { get; private set; }

    public string? PreferredExecutablePath { get; set; }

    public bool UseSystemProxy { get; set; } = true;

    public Task StartAsync(CancellationToken cancellationToken = default) =>
        RunOperationAsync(restart: false, cancellationToken);

    public Task RestartAsync(CancellationToken cancellationToken = default) =>
        RunOperationAsync(restart: true, cancellationToken);

    public Task RefreshRateLimitsAsync(CancellationToken cancellationToken = default) =>
        RunOperationAsync(restart: false, cancellationToken);

    private async Task RunOperationAsync(bool restart, CancellationToken cancellationToken)
    {
        using var operationCts = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken, _lifetimeCts.Token);
        await _operationGate.WaitAsync(operationCts.Token);
        try
        {
            if (restart)
            {
                await StopProcessAsync();
            }

            await ConnectAndRefreshAsync(operationCts.Token);
        }
        finally
        {
            // The supervisor must outlive a failed handshake or an exited child process.
            _pollTask ??= Task.Run(() => PollLoopAsync(_lifetimeCts.Token));
            _operationGate.Release();
        }
    }

    private async Task ConnectAndRefreshAsync(CancellationToken cancellationToken)
    {
        try
        {
            if (_process is null || _process.HasExited || !_initialized)
            {
                await StopProcessAsync();
                UpdateConnectionState(AppServerConnectionState.Connecting);
                ExecutablePath = _locator.Locate(PreferredExecutablePath);

                if (string.IsNullOrWhiteSpace(ExecutablePath))
                {
                    ExecutablePath = null;
                    UpdateConnectionState(AppServerConnectionState.MissingExecutable);
                    return;
                }

                var startInfo = _startInfoFactory(ExecutablePath);
                ApplyProxyEnvironment(startInfo);
                var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
                try
                {
                    process.Start();
                }
                catch
                {
                    process.Dispose();
                    throw;
                }
                _process = process;
                process.Exited += OnProcessExited;
                _sessionCts = CancellationTokenSource.CreateLinkedTokenSource(_lifetimeCts.Token);
                var sessionToken = _sessionCts.Token;
                _stdoutTask = ReadOutputLoopAsync(process, sessionToken);
                _stderrTask = ReadErrorLoopAsync(process, sessionToken);
                await InitializeAsync(cancellationToken);
                _initialized = true;
            }

            var result = await SendRequestAsync("account/rateLimits/read", null, cancellationToken);
            var snapshot = CodexQuotaParser.ParseReadResponse(result, DateTimeOffset.UtcNow);
            if (!snapshot.HasDisplayableData)
            {
                throw new InvalidOperationException("Codex returned no displayable quota data.");
            }

            SetLatestSnapshot(snapshot);
            PublishQuota(snapshot);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            await StopProcessAsync();
            throw;
        }
        catch (Exception error)
        {
            LastError = error.Message;
            UpdateConnectionState(AppServerConnectionState.Degraded, force: true);
            if (!_initialized)
            {
                await StopProcessAsync();
            }
        }
    }

    public async ValueTask DisposeAsync()
    {
        _lifetimeCts.Cancel();
        if (_pollTask is not null)
        {
            await IgnoreFailuresAsync(_pollTask);
        }

        await _operationGate.WaitAsync();
        try
        {
            await StopProcessAsync();
        }
        finally
        {
            _operationGate.Release();
        }

        _operationGate.Dispose();
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
    }

    private async Task PollLoopAsync(CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                await Task.Delay(ConnectionState == AppServerConnectionState.Connected
                    ? _pollInterval : _retryInterval, cancellationToken);
                await RefreshRateLimitsAsync(cancellationToken);
            }
        }
        catch (OperationCanceledException)
        {
        }
    }

    private async Task ReadOutputLoopAsync(Process process, CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var line = await process.StandardOutput.ReadLineAsync(cancellationToken);
                if (line is null)
                {
                    throw new EndOfStreamException("Codex app-server closed its output stream.");
                }

                if (string.IsNullOrWhiteSpace(line))
                {
                    continue;
                }

                try
                {
                    HandleIncomingLine(line);
                }
                catch (JsonException)
                {
                    // A diagnostic line must not permanently stop the RPC reader.
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception error)
        {
            FailSession(error);
        }
    }

    private static async Task ReadErrorLoopAsync(Process process, CancellationToken cancellationToken)
    {
        try
        {
            while (await process.StandardError.ReadLineAsync(cancellationToken) is not null)
            {
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
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
        if (root.ValueKind != JsonValueKind.Object)
        {
            return;
        }

        if (root.TryGetProperty("id", out var idElement))
        {
            var id = idElement.ValueKind == JsonValueKind.Number && idElement.TryGetInt64(out var value)
                ? value : 0;
            if (_pending.TryRemove(id, out var pending))
            {
                if (root.TryGetProperty("result", out var resultElement))
                {
                    pending.TrySetResult(resultElement.Clone());
                    return;
                }

                if (root.TryGetProperty("error", out var errorElement))
                {
                    var message = errorElement.ValueKind == JsonValueKind.Object &&
                                  errorElement.TryGetProperty("message", out var messageElement)
                        ? messageElement.GetString() : "Codex app-server request failed.";
                    pending.TrySetException(new InvalidOperationException(message));
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

        try
        {
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

            return await tcs.Task.WaitAsync(_requestTimeout, cancellationToken);
        }
        finally
        {
            _pending.TryRemove(requestId, out _);
        }
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
        LastError = null;
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
        if (ReferenceEquals(sender, _process))
        {
            FailSession(new InvalidOperationException("Codex app-server exited; reconnecting automatically."));
        }
    }

    private void FailSession(Exception error)
    {
        _initialized = false;
        foreach (var pending in _pending.Values)
        {
            pending.TrySetException(error);
        }

        _sessionCts?.Cancel();
        LastError = error.Message;
        UpdateConnectionState(AppServerConnectionState.Degraded, force: true);
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
        _initialized = false;
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

        _sessionCts?.Dispose();
        _sessionCts = null;

        _stdoutTask = null;
        _stderrTask = null;

        _process?.Dispose();
        _process = null;
    }

    private void UpdateConnectionState(AppServerConnectionState state, bool force = false)
    {
        if (ConnectionState == state && !force)
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
