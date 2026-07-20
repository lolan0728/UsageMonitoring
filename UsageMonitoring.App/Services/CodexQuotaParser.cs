using System.Text.Json;
using UsageMonitoring.App.Models;

namespace UsageMonitoring.App.Services;

public static class CodexQuotaParser
{
    public static CodexQuotaSnapshot ParseReadResponse(JsonElement result, DateTimeOffset syncedAtUtc)
    {
        if (result.ValueKind != JsonValueKind.Object)
        {
            return EmptyAt(syncedAtUtc);
        }

        if (result.TryGetProperty("rateLimitsByLimitId", out var limitsById) &&
            limitsById.ValueKind == JsonValueKind.Object)
        {
            var snapshots = limitsById
                .EnumerateObject()
                .Select(property => ParseRateLimitSnapshot(property.Value, syncedAtUtc, property.Name))
                .ToArray();

            if (snapshots.Length > 0)
            {
                return Combine(snapshots, syncedAtUtc);
            }
        }

        if (result.TryGetProperty("rateLimits", out var legacyRateLimits) &&
            legacyRateLimits.ValueKind == JsonValueKind.Object)
        {
            return ParseRateLimitSnapshot(legacyRateLimits, syncedAtUtc);
        }

        return EmptyAt(syncedAtUtc);
    }

    public static CodexQuotaSnapshot ParseRateLimitSnapshot(
        JsonElement element,
        DateTimeOffset syncedAtUtc,
        string? fallbackLimitId = null)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            return EmptyAt(syncedAtUtc);
        }

        var limitId = GetOptionalString(element, "limitId") ?? fallbackLimitId;
        var limitName = GetOptionalString(element, "limitName");
        var limits = new List<RateLimitBucket>(2);

        AddWindow(limits, element, "primary", syncedAtUtc, limitId, limitName);
        AddWindow(limits, element, "secondary", syncedAtUtc, limitId, limitName);

        var credits = element.TryGetProperty("credits", out var creditsElement) &&
                      creditsElement.ValueKind == JsonValueKind.Object
            ? new CreditStatus(
                HasCredits: GetOptionalBoolean(creditsElement, "hasCredits"),
                Unlimited: GetOptionalBoolean(creditsElement, "unlimited"),
                Balance: GetOptionalString(creditsElement, "balance"))
            : null;

        return new CodexQuotaSnapshot(
            NormalizeLimits(limits),
            credits,
            GetOptionalString(element, "planType"),
            syncedAtUtc);
    }

    public static CodexQuotaSnapshot Merge(
        CodexQuotaSnapshot current,
        CodexQuotaSnapshot update,
        string? updatedLimitId = null)
    {
        IReadOnlyList<RateLimitBucket> mergedLimits;
        var updatedLimitIds = update.Limits
            .Select(limit => limit.LimitId)
            .Where(limitId => !string.IsNullOrWhiteSpace(limitId))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (!string.IsNullOrWhiteSpace(updatedLimitId))
        {
            updatedLimitIds.Add(updatedLimitId);
        }

        if (updatedLimitIds.Count > 0)
        {
            mergedLimits = NormalizeLimits(
                current.Limits
                    .Where(limit => limit.LimitId is null || !updatedLimitIds.Contains(limit.LimitId))
                    .Concat(update.Limits));
        }
        else if (update.Limits.Count > 0)
        {
            mergedLimits = NormalizeLimits(update.Limits);
        }
        else
        {
            mergedLimits = current.Limits;
        }

        return new CodexQuotaSnapshot(
            mergedLimits,
            update.Credits ?? current.Credits,
            update.PlanType ?? current.PlanType,
            update.SyncedAtUtc);
    }

    public static string? GetLimitId(JsonElement element, string? fallbackLimitId = null) =>
        element.ValueKind == JsonValueKind.Object
            ? GetOptionalString(element, "limitId") ?? fallbackLimitId
            : fallbackLimitId;

    public static string BuildWindowLabel(
        int? windowDurationMins,
        string? limitName = null,
        string? limitId = null,
        string? windowRole = null)
    {
        if (windowDurationMins is int duration)
        {
            return duration switch
            {
                43200 => "1mo",
                >= 10080 when duration % 10080 == 0 => $"{duration / 10080}w",
                >= 1440 when duration % 1440 == 0 => $"{duration / 1440}d",
                >= 60 when duration % 60 == 0 => $"{duration / 60}h",
                _ => $"{duration}m"
            };
        }

        var fallback = !string.IsNullOrWhiteSpace(limitName)
            ? limitName
            : !string.IsNullOrWhiteSpace(limitId)
                ? limitId
                : "Usage";

        return string.Equals(windowRole, "secondary", StringComparison.OrdinalIgnoreCase)
            ? $"{fallback} 2"
            : fallback;
    }

    private static CodexQuotaSnapshot Combine(
        IReadOnlyList<CodexQuotaSnapshot> snapshots,
        DateTimeOffset syncedAtUtc)
    {
        var credits = snapshots
            .Select(snapshot => snapshot.Credits)
            .Where(creditStatus => creditStatus is not null)
            .OrderByDescending(creditStatus => creditStatus!.Unlimited)
            .ThenByDescending(creditStatus => creditStatus!.HasCredits)
            .ThenByDescending(creditStatus => !string.IsNullOrWhiteSpace(creditStatus!.Balance))
            .FirstOrDefault();

        return new CodexQuotaSnapshot(
            NormalizeLimits(snapshots.SelectMany(snapshot => snapshot.Limits)),
            credits,
            snapshots.Select(snapshot => snapshot.PlanType).FirstOrDefault(plan => !string.IsNullOrWhiteSpace(plan)),
            syncedAtUtc);
    }

    private static void AddWindow(
        ICollection<RateLimitBucket> limits,
        JsonElement snapshot,
        string windowRole,
        DateTimeOffset syncedAtUtc,
        string? limitId,
        string? limitName)
    {
        if (!snapshot.TryGetProperty(windowRole, out var window) ||
            window.ValueKind != JsonValueKind.Object ||
            !TryGetDouble(window, "usedPercent", out var usedPercent))
        {
            return;
        }

        var duration = GetOptionalInt32(window, "windowDurationMins");
        if (duration <= 0)
        {
            duration = null;
        }

        var clampedUsedPercent = Math.Clamp(usedPercent, 0, 100);
        limits.Add(new RateLimitBucket(
            Label: BuildWindowLabel(duration, limitName, limitId, windowRole),
            WindowDurationMins: duration,
            UsedPercent: clampedUsedPercent,
            RemainingPercent: 100 - clampedUsedPercent,
            ResetsAtUtc: GetResetTime(window),
            SyncedAtUtc: syncedAtUtc,
            LimitId: limitId,
            LimitName: limitName,
            WindowRole: windowRole));
    }

    private static IReadOnlyList<RateLimitBucket> NormalizeLimits(IEnumerable<RateLimitBucket> limits) =>
        limits
            .GroupBy(
                limit => $"{limit.LimitId}\u001f{limit.WindowRole}\u001f{limit.WindowDurationMins}\u001f{limit.Label}",
                StringComparer.OrdinalIgnoreCase)
            .Select(group => group.OrderByDescending(limit => limit.SyncedAtUtc).First())
            .OrderBy(limit => limit.WindowDurationMins ?? int.MaxValue)
            .ThenBy(limit => limit.LimitName ?? limit.LimitId ?? limit.Label, StringComparer.OrdinalIgnoreCase)
            .ToArray();

    private static CodexQuotaSnapshot EmptyAt(DateTimeOffset syncedAtUtc) =>
        new(Array.Empty<RateLimitBucket>(), null, null, syncedAtUtc);

    private static DateTimeOffset? GetResetTime(JsonElement window)
    {
        var unixTime = GetOptionalInt64(window, "resetsAt");
        if (unixTime is null)
        {
            return null;
        }

        try
        {
            return DateTimeOffset.FromUnixTimeSeconds(unixTime.Value);
        }
        catch (ArgumentOutOfRangeException)
        {
            return null;
        }
    }

    private static int? GetOptionalInt32(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var property) ||
            property.ValueKind != JsonValueKind.Number)
        {
            return null;
        }

        if (property.TryGetInt32(out var value))
        {
            return value;
        }

        if (property.TryGetInt64(out var longValue) &&
            longValue is >= int.MinValue and <= int.MaxValue)
        {
            return (int)longValue;
        }

        return null;
    }

    private static long? GetOptionalInt64(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property) &&
        property.ValueKind == JsonValueKind.Number &&
        property.TryGetInt64(out var value)
            ? value
            : null;

    private static bool GetOptionalBoolean(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property) &&
        property.ValueKind is JsonValueKind.True or JsonValueKind.False &&
        property.GetBoolean();

    private static bool TryGetDouble(JsonElement element, string propertyName, out double value)
    {
        value = 0;
        return element.TryGetProperty(propertyName, out var property) &&
               property.ValueKind == JsonValueKind.Number &&
               property.TryGetDouble(out value);
    }

    private static string? GetOptionalString(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property) &&
        property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;
}
