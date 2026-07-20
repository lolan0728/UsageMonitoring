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
    private readonly string _snapshotPath;

    public RateLimitSnapshotService(string? snapshotPath = null)
    {
        _snapshotPath = snapshotPath ?? AppPaths.RateLimitSnapshotPath;
    }

    public CodexQuotaSnapshot Load()
    {
        EnsureSnapshotDirectory();
        if (!File.Exists(_snapshotPath))
        {
            return CodexQuotaSnapshot.Empty;
        }

        try
        {
            var json = File.ReadAllText(_snapshotPath);
            var document = JsonSerializer.Deserialize<RateLimitSnapshotDocument>(json, JsonOptions);
            if (document?.Snapshot is CodexQuotaSnapshot snapshot)
            {
                return Normalize(snapshot);
            }

            var legacyBuckets = document?.Buckets ?? [];
            if (legacyBuckets.Length == 0)
            {
                return CodexQuotaSnapshot.Empty;
            }

            var syncedAtUtc = legacyBuckets.Max(bucket => bucket.SyncedAtUtc);
            return Normalize(new CodexQuotaSnapshot(
                legacyBuckets,
                Credits: null,
                PlanType: null,
                SyncedAtUtc: syncedAtUtc));
        }
        catch
        {
            return CodexQuotaSnapshot.Empty;
        }
    }

    public void Save(CodexQuotaSnapshot snapshot)
    {
        if (!snapshot.HasDisplayableData)
        {
            return;
        }

        EnsureSnapshotDirectory();
        var document = new RateLimitSnapshotDocument
        {
            Version = 2,
            SavedAtUtc = DateTimeOffset.UtcNow,
            Snapshot = Normalize(snapshot)
        };

        var json = JsonSerializer.Serialize(document, JsonOptions);
        File.WriteAllText(_snapshotPath, json);
    }

    private sealed class RateLimitSnapshotDocument
    {
        public int Version { get; init; }

        public DateTimeOffset SavedAtUtc { get; init; }

        public CodexQuotaSnapshot? Snapshot { get; init; }

        // Kept for one-way migration of v1 cache files.
        public RateLimitBucket[] Buckets { get; init; } = [];
    }

    private static CodexQuotaSnapshot Normalize(CodexQuotaSnapshot snapshot) =>
        snapshot with
        {
            Limits = snapshot.Limits
                .OrderBy(bucket => bucket.WindowDurationMins ?? int.MaxValue)
                .ThenBy(bucket => bucket.Label, StringComparer.OrdinalIgnoreCase)
                .ToArray()
        };

    private void EnsureSnapshotDirectory()
    {
        var directory = Path.GetDirectoryName(_snapshotPath);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }
    }
}
