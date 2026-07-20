using System.Text.Json.Serialization;

namespace UsageMonitoring.App.Models;

public sealed record CodexQuotaSnapshot(
    IReadOnlyList<RateLimitBucket> Limits,
    CreditStatus? Credits,
    string? PlanType,
    DateTimeOffset SyncedAtUtc)
{
    public static CodexQuotaSnapshot Empty { get; } = new(
        Array.Empty<RateLimitBucket>(),
        Credits: null,
        PlanType: null,
        SyncedAtUtc: DateTimeOffset.MinValue);

    [JsonIgnore]
    public bool HasDisplayableData =>
        Limits.Count > 0 ||
        Credits is { Unlimited: true } ||
        Credits is { HasCredits: true };
}
