using System.IO;

namespace UsageMonitoring.App.Services;

public sealed class CodexExecutableLocator
{
    public string? Locate(string? preferredPath = null)
    {
        foreach (var candidate in EnumerateCandidates(preferredPath))
        {
            if (!string.IsNullOrWhiteSpace(candidate) && File.Exists(candidate))
            {
                return candidate;
            }
        }

        return null;
    }

    private static IEnumerable<string?> EnumerateCandidates(string? preferredPath)
    {
        yield return preferredPath;
        yield return Path.Combine(AppPaths.CodexHome, ".sandbox-bin", "codex.exe");
        yield return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Microsoft",
            "WindowsApps",
            "codex.exe");

        var pathEnv = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathEnv))
        {
            yield break;
        }

        foreach (var path in pathEnv.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            yield return Path.Combine(path.Trim(), "codex.exe");
        }
    }
}
