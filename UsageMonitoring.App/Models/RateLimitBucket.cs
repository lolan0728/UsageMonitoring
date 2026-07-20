namespace UsageMonitoring.App.Models;

public sealed record RateLimitBucket(
    string Label,
    int? WindowDurationMins,
    double UsedPercent,
    double RemainingPercent,
    DateTimeOffset? ResetsAtUtc,
    DateTimeOffset SyncedAtUtc,
    string? LimitId = null,
    string? LimitName = null,
    string? WindowRole = null);
