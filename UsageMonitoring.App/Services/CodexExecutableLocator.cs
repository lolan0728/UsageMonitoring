using System.IO;

namespace UsageMonitoring.App.Services;

public sealed class CodexExecutableLocator
{
    private readonly IEnumerable<string?> _automaticCandidates;
    private readonly string _legacySandboxPath;

    public CodexExecutableLocator()
        : this(EnumerateCandidates(), Path.Combine(AppPaths.CodexHome, ".sandbox-bin", "codex.exe"))
    {
    }

    internal CodexExecutableLocator(IEnumerable<string?> automaticCandidates, string legacySandboxPath)
    {
        _automaticCandidates = automaticCandidates;
        _legacySandboxPath = legacySandboxPath;
    }

    public string? Locate(string? preferredPath = null)
    {
        // Older releases persisted this automatically detected copy as a preference.
        // Let the installed desktop runtime supersede that stale sandbox copy.
        if (!string.Equals(preferredPath, _legacySandboxPath, StringComparison.OrdinalIgnoreCase) &&
            File.Exists(preferredPath))
        {
            return preferredPath;
        }

        foreach (var candidate in _automaticCandidates)
        {
            if (!string.IsNullOrWhiteSpace(candidate) && File.Exists(candidate))
            {
                return candidate;
            }
        }

        return File.Exists(preferredPath) ? preferredPath : null;
    }

    private static IEnumerable<string?> EnumerateCandidates()
    {
        yield return Environment.GetEnvironmentVariable("CODEX_APP_RUNTIME_CLI_PATH");
        foreach (var candidate in EnumerateDesktopRuntimes())
        {
            yield return candidate;
        }

        yield return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Microsoft",
            "WindowsApps",
            "codex.exe");

        var pathEnv = Environment.GetEnvironmentVariable("PATH");
        foreach (var path in (pathEnv ?? "").Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            yield return Path.Combine(path.Trim().Trim('"'), "codex.exe");
        }

        yield return Path.Combine(AppPaths.CodexHome, ".sandbox-bin", "codex.exe");
    }

    private static IEnumerable<string> EnumerateDesktopRuntimes()
    {
        var binDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OpenAI", "Codex", "bin");
        try
        {
            return Directory.Exists(binDirectory)
                ? new DirectoryInfo(binDirectory).GetDirectories()
                    .OrderByDescending(directory => directory.LastWriteTimeUtc)
                    .Select(directory => Path.Combine(directory.FullName, "codex.exe"))
                    .ToArray()
                : [];
        }
        catch (IOException)
        {
            return [];
        }
        catch (UnauthorizedAccessException)
        {
            return [];
        }
    }
}
