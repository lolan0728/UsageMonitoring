using System.Diagnostics;
using System.Runtime.InteropServices;

namespace UsageMonitoring.App.Services;

public sealed class MemoryFootprintService : IAsyncDisposable
{
    private readonly TimeSpan _trimInterval;
    private readonly CancellationTokenSource _cts = new();
    private PeriodicTimer? _trimTimer;
    private Task? _loopTask;

    public MemoryFootprintService(TimeSpan? trimInterval = null)
    {
        _trimInterval = trimInterval ?? TimeSpan.FromMinutes(5);
    }

    public void Start()
    {
        if (_loopTask is not null)
        {
            return;
        }

        _trimTimer = new PeriodicTimer(_trimInterval);
        _loopTask = Task.Run(() => TrimLoopAsync(_cts.Token), _cts.Token);
    }

    public void TrimNow(bool forceGc = false)
    {
        if (forceGc)
        {
            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
        }

        using var process = Process.GetCurrentProcess();
        _ = EmptyWorkingSet(process.Handle);
    }

    public async ValueTask DisposeAsync()
    {
        _cts.Cancel();
        _trimTimer?.Dispose();

        if (_loopTask is not null)
        {
            try
            {
                await _loopTask;
            }
            catch
            {
            }
        }

        _cts.Dispose();
    }

    private async Task TrimLoopAsync(CancellationToken cancellationToken)
    {
        if (_trimTimer is null)
        {
            return;
        }

        try
        {
            while (await _trimTimer.WaitForNextTickAsync(cancellationToken))
            {
                TrimNow(forceGc: false);
            }
        }
        catch (OperationCanceledException)
        {
        }
    }

    [DllImport("psapi.dll", SetLastError = true)]
    private static extern bool EmptyWorkingSet(IntPtr hProcess);
}
