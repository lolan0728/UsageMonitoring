using System.Text.Json;
using UsageMonitoring.App.Models;
using UsageMonitoring.App.Services;

namespace UsageMonitoring.App.Tests;

public sealed class CodexQuotaParserTests
{
    private static readonly DateTimeOffset SyncedAt = new(2026, 7, 20, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void ParseReadResponse_PrefersMultiBucketPayload()
    {
        using var document = JsonDocument.Parse("""
            {
              "rateLimits": {
                "primary": { "usedPercent": 90, "windowDurationMins": 300 }
              },
              "rateLimitsByLimitId": {
                "codex": {
                  "limitId": "codex",
                  "limitName": "Codex",
                  "planType": "plus",
                  "primary": {
                    "usedPercent": 20,
                    "windowDurationMins": 10080,
                    "resetsAt": 1785153600
                  },
                  "secondary": null,
                  "credits": {
                    "hasCredits": true,
                    "unlimited": false,
                    "balance": "250.5"
                  }
                }
              }
            }
            """);

        var snapshot = CodexQuotaParser.ParseReadResponse(document.RootElement, SyncedAt);

        var limit = Assert.Single(snapshot.Limits);
        Assert.Equal("1w", limit.Label);
        Assert.Equal(10080, limit.WindowDurationMins);
        Assert.Equal(80, limit.RemainingPercent);
        Assert.Equal("codex", limit.LimitId);
        Assert.Equal("plus", snapshot.PlanType);
        Assert.Equal("250.5", snapshot.Credits?.Balance);
    }

    [Fact]
    public void ParseReadResponse_FallsBackToLegacyAndKeepsUnknownDuration()
    {
        using var document = JsonDocument.Parse("""
            {
              "rateLimits": {
                "limitName": "Codex",
                "primary": { "usedPercent": 25, "windowDurationMins": 300 },
                "secondary": { "usedPercent": 40, "windowDurationMins": null }
              }
            }
            """);

        var snapshot = CodexQuotaParser.ParseReadResponse(document.RootElement, SyncedAt);

        Assert.Collection(
            snapshot.Limits,
            primary =>
            {
                Assert.Equal("5h", primary.Label);
                Assert.Equal(300, primary.WindowDurationMins);
            },
            secondary =>
            {
                Assert.Equal("Codex 2", secondary.Label);
                Assert.Null(secondary.WindowDurationMins);
                Assert.Equal(60, secondary.RemainingPercent);
            });
    }

    [Fact]
    public void Merge_ReplacesRemovedWindowForTheUpdatedLimit()
    {
        var current = new CodexQuotaSnapshot(
            [
                Bucket("5h", 300, "codex", "primary"),
                Bucket("1w", 10080, "codex", "secondary")
            ],
            null,
            "plus",
            SyncedAt.AddMinutes(-1));
        var update = new CodexQuotaSnapshot(
            [Bucket("1w", 10080, "codex", "primary")],
            null,
            "plus",
            SyncedAt);

        var merged = CodexQuotaParser.Merge(current, update);

        var limit = Assert.Single(merged.Limits);
        Assert.Equal("1w", limit.Label);
    }

    [Fact]
    public void ParseRateLimitSnapshot_RecognizesUnlimitedCreditsWithoutWindows()
    {
        using var document = JsonDocument.Parse("""
            {
              "planType": "business",
              "primary": null,
              "secondary": null,
              "credits": {
                "hasCredits": false,
                "unlimited": true,
                "balance": null
              }
            }
            """);

        var snapshot = CodexQuotaParser.ParseRateLimitSnapshot(document.RootElement, SyncedAt);

        Assert.Empty(snapshot.Limits);
        Assert.True(snapshot.HasDisplayableData);
        Assert.True(snapshot.Credits?.Unlimited);
    }

    [Fact]
    public void ParseRateLimitSnapshot_DoesNotTreatZeroUnavailableCreditsAsDisplayable()
    {
        using var document = JsonDocument.Parse("""
            {
              "primary": null,
              "secondary": null,
              "credits": {
                "hasCredits": false,
                "unlimited": false,
                "balance": "0"
              }
            }
            """);

        var snapshot = CodexQuotaParser.ParseRateLimitSnapshot(document.RootElement, SyncedAt);

        Assert.False(snapshot.HasDisplayableData);
    }

    [Fact]
    public void Merge_RemovesOldWindowsWhenLimitBecomesUnlimited()
    {
        var current = new CodexQuotaSnapshot(
            [Bucket("1w", 10080, "codex", "primary")],
            null,
            "business",
            SyncedAt.AddMinutes(-1));
        var update = new CodexQuotaSnapshot(
            Array.Empty<RateLimitBucket>(),
            new CreditStatus(false, true, null),
            "business",
            SyncedAt);

        var merged = CodexQuotaParser.Merge(current, update, updatedLimitId: "codex");

        Assert.Empty(merged.Limits);
        Assert.True(merged.Credits?.Unlimited);
    }

    private static RateLimitBucket Bucket(string label, int duration, string limitId, string role) =>
        new(
            label,
            duration,
            UsedPercent: 20,
            RemainingPercent: 80,
            ResetsAtUtc: null,
            SyncedAtUtc: SyncedAt,
            LimitId: limitId,
            LimitName: "Codex",
            WindowRole: role);
}
