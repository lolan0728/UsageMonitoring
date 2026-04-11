using System.IO;
using System.Text.Json;
using UsageMonitoring.App.Models;

namespace UsageMonitoring.App.Services;

public sealed class RateLimitSnapshotService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true
    };

    public IReadOnlyList<RateLimitBucket> Load()
    {
        Directory.CreateDirectory(AppPaths.AppDataDirectory);
        if (!File.Exists(AppPaths.RateLimitSnapshotPath))
        {
            return Array.Empty<RateLimitBucket>();
        }

        try
        {
            var json = File.ReadAllText(AppPaths.RateLimitSnapshotPath);
            var document = JsonSerializer.Deserialize<RateLimitSnapshotDocument>(json, JsonOptions);
            return document?.Buckets?
                .OrderBy(bucket => bucket.WindowDurationMins)
                .ToArray() ?? Array.Empty<RateLimitBucket>();
        }
        catch
        {
            return Array.Empty<RateLimitBucket>();
        }
    }

    public void Save(IReadOnlyList<RateLimitBucket> buckets)
    {
        if (buckets.Count == 0)
        {
            return;
        }

        Directory.CreateDirectory(AppPaths.AppDataDirectory);
        var document = new RateLimitSnapshotDocument
        {
            SavedAtUtc = DateTimeOffset.UtcNow,
            Buckets = buckets.OrderBy(bucket => bucket.WindowDurationMins).ToArray()
        };

        var json = JsonSerializer.Serialize(document, JsonOptions);
        File.WriteAllText(AppPaths.RateLimitSnapshotPath, json);
    }

    private sealed class RateLimitSnapshotDocument
    {
        public DateTimeOffset SavedAtUtc { get; init; }

        public RateLimitBucket[] Buckets { get; init; } = [];
    }
}
