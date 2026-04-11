using UsageMonitoring.App.Models;

namespace UsageMonitoring.App.Services;

public sealed class RateLimitStore : IRateLimitStore
{
    private readonly object _gate = new();
    private IReadOnlyList<RateLimitBucket> _buckets = Array.Empty<RateLimitBucket>();

    public event EventHandler<IReadOnlyList<RateLimitBucket>>? BucketsUpdated;

    public IReadOnlyList<RateLimitBucket> Buckets
    {
        get
        {
            lock (_gate)
            {
                return _buckets;
            }
        }
    }

    public DateTimeOffset? LastUpdatedAtUtc { get; private set; }

    public void ReplaceBuckets(IEnumerable<RateLimitBucket> buckets)
    {
        var normalized = buckets
            .OrderBy(bucket => bucket.WindowDurationMins)
            .ToArray();

        lock (_gate)
        {
            _buckets = normalized;
            LastUpdatedAtUtc = normalized.Length == 0
                ? LastUpdatedAtUtc
                : normalized.Max(bucket => bucket.SyncedAtUtc);
        }

        BucketsUpdated?.Invoke(this, normalized);
    }
}
