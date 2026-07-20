using UsageMonitoring.App.Models;

namespace UsageMonitoring.App.Services;

public sealed class RateLimitStore : IRateLimitStore
{
    private readonly object _gate = new();
    private CodexQuotaSnapshot _snapshot = CodexQuotaSnapshot.Empty;

    public event EventHandler<CodexQuotaSnapshot>? SnapshotUpdated;

    public CodexQuotaSnapshot Snapshot
    {
        get
        {
            lock (_gate)
            {
                return _snapshot;
            }
        }
    }

    public DateTimeOffset? LastUpdatedAtUtc { get; private set; }

    public void ReplaceSnapshot(CodexQuotaSnapshot snapshot)
    {
        var normalizedLimits = snapshot.Limits
            .GroupBy(
                bucket => $"{bucket.LimitId}\u001f{bucket.WindowRole}\u001f{bucket.WindowDurationMins}\u001f{bucket.Label}",
                StringComparer.OrdinalIgnoreCase)
            .Select(group => group.OrderByDescending(bucket => bucket.SyncedAtUtc).First())
            .OrderBy(bucket => bucket.WindowDurationMins ?? int.MaxValue)
            .ThenBy(bucket => bucket.Label, StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var normalized = snapshot with { Limits = normalizedLimits };

        lock (_gate)
        {
            _snapshot = normalized;
            LastUpdatedAtUtc = normalized.SyncedAtUtc == DateTimeOffset.MinValue
                ? LastUpdatedAtUtc
                : normalized.SyncedAtUtc;
        }

        SnapshotUpdated?.Invoke(this, normalized);
    }
}
