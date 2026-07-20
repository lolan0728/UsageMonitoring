namespace UsageMonitoring.App.Models;

public sealed record CreditStatus(
    bool HasCredits,
    bool Unlimited,
    string? Balance);
