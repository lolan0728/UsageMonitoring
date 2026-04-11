using UsageMonitoring.App.Models;

namespace UsageMonitoring.App.Services;

public interface IRateLimitStore
{
    event EventHandler<IReadOnlyList<RateLimitBucket>>? BucketsUpdated;

    IReadOnlyList<RateLimitBucket> Buckets { get; }

    DateTimeOffset? LastUpdatedAtUtc { get; }

    void ReplaceBuckets(IEnumerable<RateLimitBucket> buckets);
}
