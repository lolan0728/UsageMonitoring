namespace UsageMonitoring.App.Models;

public sealed record RateLimitCardDisplay(
    string Label,
    string RemainingText,
    string ResetText,
    string SyncedText,
    string StatusText,
    double RingPercentage,
    bool IsLive,
    QuotaCardAccent Accent)
{
    public static RateLimitCardDisplay Placeholder(string statusText = "Usage unavailable") =>
        new(
            Label: "Status",
            RemainingText: "--",
            ResetText: statusText,
            SyncedText: "Never",
            StatusText: statusText,
            RingPercentage: 0,
            IsLive: false,
            Accent: QuotaCardAccent.Muted);
}

public enum QuotaCardAccent
{
    Green,
    Cyan,
    Amber,
    Muted
}
