using UsageMonitoring.App.Models;

namespace UsageMonitoring.App.Services;

public interface IRateLimitStore
{
    event EventHandler<CodexQuotaSnapshot>? SnapshotUpdated;

    CodexQuotaSnapshot Snapshot { get; }

    DateTimeOffset? LastUpdatedAtUtc { get; }

    void ReplaceSnapshot(CodexQuotaSnapshot snapshot);
}
