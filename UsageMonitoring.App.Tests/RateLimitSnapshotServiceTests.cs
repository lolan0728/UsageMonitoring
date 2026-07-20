using UsageMonitoring.App.Models;
using UsageMonitoring.App.Services;

namespace UsageMonitoring.App.Tests;

public sealed class RateLimitSnapshotServiceTests
{
    [Fact]
    public void Load_MigratesLegacyBucketDocument()
    {
        var directory = CreateTemporaryDirectory();
        try
        {
            var path = Path.Combine(directory, "rate-limits.json");
            File.WriteAllText(path, """
                {
                  "SavedAtUtc": "2026-07-20T12:00:00+00:00",
                  "Buckets": [
                    {
                      "Label": "1w",
                      "WindowDurationMins": 10080,
                      "UsedPercent": 20,
                      "RemainingPercent": 80,
                      "ResetsAtUtc": "2026-07-27T12:00:00+00:00",
                      "SyncedAtUtc": "2026-07-20T12:00:00+00:00",
                      "LimitId": "codex",
                      "LimitName": "Codex"
                    }
                  ]
                }
                """);

            var snapshot = new RateLimitSnapshotService(path).Load();

            var limit = Assert.Single(snapshot.Limits);
            Assert.Equal("1w", limit.Label);
            Assert.Equal(80, limit.RemainingPercent);
            Assert.Null(snapshot.Credits);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void SaveAndLoad_RoundTripsCreditsAndPlanType()
    {
        var directory = CreateTemporaryDirectory();
        try
        {
            var path = Path.Combine(directory, "rate-limits.json");
            var syncedAt = new DateTimeOffset(2026, 7, 20, 12, 0, 0, TimeSpan.Zero);
            var expected = new CodexQuotaSnapshot(
                Array.Empty<RateLimitBucket>(),
                new CreditStatus(true, false, "123.45"),
                "pro",
                syncedAt);
            var service = new RateLimitSnapshotService(path);

            service.Save(expected);
            var actual = service.Load();

            Assert.Equal("123.45", actual.Credits?.Balance);
            Assert.Equal("pro", actual.PlanType);
            Assert.Equal(syncedAt, actual.SyncedAtUtc);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    private static string CreateTemporaryDirectory()
    {
        var path = Path.Combine(Path.GetTempPath(), $"UsageMonitoring.Tests.{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }
}
