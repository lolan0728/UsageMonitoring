using UsageMonitoring.App.Services;

namespace UsageMonitoring.App.Tests;

public sealed class CodexExecutableLocatorTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), $"quota-locator-{Guid.NewGuid():N}");

    public CodexExecutableLocatorTests() => Directory.CreateDirectory(_directory);

    [Fact]
    public void Locate_UpgradesPersistedSandboxCopyToInstalledRuntime()
    {
        var legacy = CreateFile("sandbox.exe");
        var installed = CreateFile("installed.exe");
        var locator = new CodexExecutableLocator([installed, legacy], legacy);

        Assert.Equal(installed, locator.Locate(legacy));
    }

    [Fact]
    public void Locate_HonorsExplicitCustomExecutable()
    {
        var installed = CreateFile("installed.exe");
        var custom = CreateFile("custom.exe");
        var locator = new CodexExecutableLocator([installed], Path.Combine(_directory, "sandbox.exe"));

        Assert.Equal(custom, locator.Locate(custom));
    }

    [Fact]
    public void Locate_FallsBackWhenInstalledRuntimeIsMissing()
    {
        var legacy = CreateFile("sandbox.exe");
        var locator = new CodexExecutableLocator([Path.Combine(_directory, "missing.exe"), legacy], legacy);

        Assert.Equal(legacy, locator.Locate(legacy));
    }

    private string CreateFile(string name)
    {
        var path = Path.Combine(_directory, name);
        File.WriteAllText(path, "");
        return path;
    }

    public void Dispose() => Directory.Delete(_directory, recursive: true);
}
