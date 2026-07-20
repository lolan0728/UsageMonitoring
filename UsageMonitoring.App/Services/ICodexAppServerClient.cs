using UsageMonitoring.App.Models;

namespace UsageMonitoring.App.Services;

public interface ICodexAppServerClient : IAsyncDisposable
{
    event EventHandler<CodexQuotaSnapshot>? QuotaUpdated;

    event EventHandler<AppServerConnectionState>? ConnectionStateChanged;

    DateTimeOffset? LastSyncedAtUtc { get; }

    AppServerConnectionState ConnectionState { get; }

    string? ExecutablePath { get; }

    string? PreferredExecutablePath { get; set; }

    bool UseSystemProxy { get; set; }

    Task StartAsync(CancellationToken cancellationToken = default);

    Task RestartAsync(CancellationToken cancellationToken = default);

    Task RefreshRateLimitsAsync(CancellationToken cancellationToken = default);
}
