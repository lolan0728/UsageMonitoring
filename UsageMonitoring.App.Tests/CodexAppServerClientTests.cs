using System.Collections.Concurrent;
using System.Diagnostics;
using UsageMonitoring.App.Models;
using UsageMonitoring.App.Services;

namespace UsageMonitoring.App.Tests;

public sealed class CodexAppServerClientTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), $"quota-server-{Guid.NewGuid():N}");
    private readonly ConcurrentQueue<AppServerConnectionState> _states = new();

    public CodexAppServerClientTests()
    {
        Directory.CreateDirectory(_directory);
        File.WriteAllText(Path.Combine(_directory, "server.ps1"), """
            param([string]$StateDirectory, [string]$Scenario)
            $ErrorActionPreference = 'Stop'
            $countPath = Join-Path $StateDirectory 'starts.txt'
            $instance = 1
            if ([IO.File]::Exists($countPath)) { $instance = [int][IO.File]::ReadAllText($countPath) + 1 }
            [IO.File]::WriteAllText($countPath, [string]$instance)
            $reads = 0
            while ($null -ne ($line = [Console]::ReadLine())) {
                $request = $line | ConvertFrom-Json
                if ($request.method -eq 'initialize') {
                    if ($Scenario -eq 'handshake-timeout' -and $instance -eq 1) { continue }
                    if ($Scenario -eq 'diagnostic-line') { [Console]::WriteLine('Starting app-server...') }
                    [Console]::WriteLine((@{id=$request.id; result=@{}} | ConvertTo-Json -Compress))
                }
                if ($request.method -eq 'account/rateLimits/read') {
                    $reads++
                    if ($Scenario -eq 'read-error' -and $reads -eq 1) {
                        [Console]::WriteLine((@{id=$request.id; error=@{code=-32000; message='Temporary quota failure'}} | ConvertTo-Json -Depth 10 -Compress))
                        continue
                    }
                    if ($Scenario -eq 'empty-second-read' -and $reads -eq 2) {
                        [Console]::WriteLine((@{id=$request.id; result=@{rateLimits=$null}} | ConvertTo-Json -Compress))
                        continue
                    }
                    $result = @{rateLimits=@{limitId='codex'; primary=@{usedPercent=8; windowDurationMins=300}}}
                    [Console]::WriteLine((@{id=$request.id; result=$result} | ConvertTo-Json -Depth 10 -Compress))
                    if ($Scenario -eq 'exit-after-read' -and $instance -eq 1) { exit 1 }
                }
            }
            """);
    }

    [Fact]
    public async Task StartAsync_RetriesAfterInitialHandshakeTimeout()
    {
        await using var client = CreateClient("handshake-timeout");
        var recovered = NextQuota(client);

        await client.StartAsync();

        Assert.Equal(AppServerConnectionState.Degraded, client.ConnectionState);
        Assert.NotNull(client.LastError);
        Assert.Null(client.LastSyncedAtUtc);
        Assert.Equal(92, Assert.Single((await recovered.WaitAsync(TimeSpan.FromSeconds(20))).Limits).RemainingPercent);
        Assert.Equal(2, StartCount);
        Assert.Null(client.LastError);
    }

    [Fact]
    public async Task PollLoop_RestartsExitedProcess()
    {
        await using var client = CreateClient("exit-after-read");
        var recovered = NextQuota(client, count: 2);

        await client.StartAsync();
        await recovered.WaitAsync(TimeSpan.FromSeconds(20));

        Assert.Equal(2, StartCount);
        Assert.Contains(AppServerConnectionState.Degraded, _states);
        Assert.Equal(AppServerConnectionState.Connected, client.ConnectionState);
    }

    [Fact]
    public async Task PollLoop_RetriesFailedQuotaReadOnExistingProcess()
    {
        await using var client = CreateClient("read-error");
        var recovered = NextQuota(client);

        await client.StartAsync();

        Assert.Equal("Temporary quota failure", client.LastError);
        await recovered.WaitAsync(TimeSpan.FromSeconds(20));
        Assert.Equal(1, StartCount);
        Assert.Equal(AppServerConnectionState.Connected, client.ConnectionState);
        Assert.Null(client.LastError);
    }

    [Fact]
    public async Task RefreshAsync_DoesNotPublishEmptyDataOverValidQuota()
    {
        await using var client = CreateClient("empty-second-read", pollInterval: TimeSpan.FromMinutes(1));
        var snapshots = new ConcurrentQueue<CodexQuotaSnapshot>();
        client.QuotaUpdated += (_, snapshot) => snapshots.Enqueue(snapshot);
        await client.StartAsync();
        var syncedAt = client.LastSyncedAtUtc;

        await client.RefreshRateLimitsAsync();

        Assert.Single(snapshots);
        Assert.Equal(syncedAt, client.LastSyncedAtUtc);
        Assert.Equal(AppServerConnectionState.Degraded, client.ConnectionState);
        Assert.Contains("no displayable quota", client.LastError);

        await client.RefreshRateLimitsAsync();
        Assert.Equal(2, snapshots.Count);
        Assert.Equal(AppServerConnectionState.Connected, client.ConnectionState);
    }

    [Fact]
    public async Task ReadOutputLoop_ContinuesAfterDiagnosticLine()
    {
        await using var client = CreateClient("diagnostic-line");
        var quota = NextQuota(client);

        await client.StartAsync();

        Assert.Equal(92, Assert.Single((await quota.WaitAsync(TimeSpan.FromSeconds(20))).Limits).RemainingPercent);
        Assert.Equal(1, StartCount);
    }

    [Fact]
    public async Task RestartAsync_SerializesConcurrentReconnects()
    {
        await using var client = CreateClient("normal", pollInterval: TimeSpan.FromMinutes(1));
        await client.StartAsync();

        await Task.WhenAll(client.RestartAsync(), client.RestartAsync());

        Assert.Equal(3, StartCount);
        Assert.Equal(AppServerConnectionState.Connected, client.ConnectionState);
    }

    private int StartCount => int.Parse(File.ReadAllText(Path.Combine(_directory, "starts.txt")));

    private CodexAppServerClient CreateClient(string scenario, TimeSpan? pollInterval = null)
    {
        var powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
            "WindowsPowerShell", "v1.0", "powershell.exe");
        var client = new CodexAppServerClient(
            new CodexExecutableLocator([], "unused"), powershell,
            pollInterval ?? TimeSpan.FromMilliseconds(300), TimeSpan.FromMilliseconds(200),
            TimeSpan.FromSeconds(3), path =>
            {
                var startInfo = new ProcessStartInfo(path)
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardInput = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                foreach (var argument in new[] { "-NoProfile", "-NonInteractive", "-File",
                    Path.Combine(_directory, "server.ps1"), _directory, scenario })
                {
                    startInfo.ArgumentList.Add(argument);
                }
                return startInfo;
            });
        client.ConnectionStateChanged += (_, state) => _states.Enqueue(state);
        return client;
    }

    private static Task<CodexQuotaSnapshot> NextQuota(CodexAppServerClient client, int count = 1)
    {
        var completion = new TaskCompletionSource<CodexQuotaSnapshot>(TaskCreationOptions.RunContinuationsAsynchronously);
        var remaining = count;
        client.QuotaUpdated += (_, snapshot) =>
        {
            if (Interlocked.Decrement(ref remaining) == 0)
            {
                completion.TrySetResult(snapshot);
            }
        };
        return completion.Task;
    }

    public void Dispose() => Directory.Delete(_directory, recursive: true);
}
