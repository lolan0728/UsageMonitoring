namespace UsageMonitoring.App.Models;

public sealed class AppSettings
{
    public double? WindowLeft { get; set; }

    public double? WindowTop { get; set; }

    public bool AlwaysOnTop { get; set; } = true;

    public bool LaunchOnStartup { get; set; }

    public bool ClickThrough { get; set; }

    public bool UseSystemProxyForCodex { get; set; } = true;

    public string? CodexExecutablePath { get; set; }
}
