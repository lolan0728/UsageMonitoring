namespace UsageMonitoring.App.Models;

public sealed record RateLimitCardDisplay(
    string Label,
    string RemainingText,
    string ResetText,
    string SyncedText,
    string StatusText,
    double RemainingPercent,
    double UsedPercent)
{
    public static RateLimitCardDisplay Placeholder(string label, string statusText, string resetText = "Waiting for sync") =>
        new(
            Label: label,
            RemainingText: "--",
            ResetText: resetText,
            SyncedText: "Never",
            StatusText: statusText,
            RemainingPercent: 0,
            UsedPercent: 0);
}
