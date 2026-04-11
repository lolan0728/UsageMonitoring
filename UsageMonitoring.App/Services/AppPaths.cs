using System.IO;

namespace UsageMonitoring.App.Services;

public static class AppPaths
{
    public static string CodexHome => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".codex");

    public static string AppDataDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "Usage Monitoring");

    public static string SettingsPath => Path.Combine(AppDataDirectory, "settings.json");

    public static string RateLimitSnapshotPath => Path.Combine(AppDataDirectory, "rate-limits.json");
}
