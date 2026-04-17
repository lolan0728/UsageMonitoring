using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using UsageMonitoring.App.Models;
using UsageMonitoring.App.Services;

namespace UsageMonitoring.App.ViewModels;

public partial class MainViewModel : ObservableObject
{
    private readonly AppSettings _settings;
    private readonly SettingsService _settingsService;
    private readonly AutostartService _autostartService;
    private readonly IRateLimitStore _rateLimitStore;
    private readonly ICodexAppServerClient _codexAppServerClient;
    private bool _suspendPersistence = true;

    public MainViewModel(
        AppSettings settings,
        SettingsService settingsService,
        AutostartService autostartService,
        IRateLimitStore rateLimitStore,
        ICodexAppServerClient codexAppServerClient)
    {
        _settings = settings;
        _settingsService = settingsService;
        _autostartService = autostartService;
        _rateLimitStore = rateLimitStore;
        _codexAppServerClient = codexAppServerClient;

        FiveHourCard = RateLimitCardDisplay.Placeholder("5h", "Offline");
        WeeklyCard = RateLimitCardDisplay.Placeholder("1w", "Offline");
        AlwaysOnTop = settings.AlwaysOnTop;
        LaunchOnStartup = autostartService.IsEnabled() || settings.LaunchOnStartup;
        ClickThrough = settings.ClickThrough;
        UseSystemProxyForCodex = settings.UseSystemProxyForCodex;
        _codexAppServerClient.UseSystemProxy = UseSystemProxyForCodex;
        RefreshEffectiveAlwaysOnTop();
        CodexExecutablePath = settings.CodexExecutablePath ?? "Auto detect";
        ConnectionStatusText = "Waiting for Codex app-server";
    }

    public event EventHandler? HideRequested;

    public event EventHandler? ExitRequested;

    public event EventHandler? BrowseCodexExecutableRequested;

    public event EventHandler<bool>? TopmostChanged;

    public event EventHandler<bool>? ClickThroughChanged;

    [ObservableProperty]
    private RateLimitCardDisplay fiveHourCard;

    [ObservableProperty]
    private RateLimitCardDisplay weeklyCard;

    [ObservableProperty]
    private bool isSettingsOpen;

    [ObservableProperty]
    private bool alwaysOnTop;

    [ObservableProperty]
    private bool effectiveAlwaysOnTop;

    [ObservableProperty]
    private bool launchOnStartup;

    [ObservableProperty]
    private bool clickThrough;

    [ObservableProperty]
    private bool useSystemProxyForCodex;

    [ObservableProperty]
    private string connectionStatusText;

    [ObservableProperty]
    private string codexExecutablePath;

    [ObservableProperty]
    private bool isQuotaLive;

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        _rateLimitStore.BucketsUpdated += OnBucketsUpdated;
        _codexAppServerClient.RateLimitsUpdated += OnClientRateLimitsUpdated;
        _codexAppServerClient.ConnectionStateChanged += OnConnectionStateChanged;
        UpdateConnectionStatus(_codexAppServerClient.ConnectionState);
        ApplyBuckets(_rateLimitStore.Buckets);

        await _codexAppServerClient.StartAsync(cancellationToken);

        if (!string.IsNullOrWhiteSpace(_codexAppServerClient.ExecutablePath))
        {
            CodexExecutablePath = _codexAppServerClient.ExecutablePath;
        }

        _suspendPersistence = false;
        PersistSettings();
    }

    public void SetCodexExecutablePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        CodexExecutablePath = path;
        _codexAppServerClient.PreferredExecutablePath = path;
        PersistSettings();
    }

    public async Task TryConnectToCodexAsync(CancellationToken cancellationToken = default)
    {
        await _codexAppServerClient.StartAsync(cancellationToken);

        if (!string.IsNullOrWhiteSpace(_codexAppServerClient.ExecutablePath))
        {
            CodexExecutablePath = _codexAppServerClient.ExecutablePath;
        }
    }

    public Task ReconnectAsync(CancellationToken cancellationToken = default) =>
        _codexAppServerClient.RestartAsync(cancellationToken);

    [RelayCommand]
    private void ToggleSettings() => IsSettingsOpen = !IsSettingsOpen;

    [RelayCommand]
    private void HideToTray() => HideRequested?.Invoke(this, EventArgs.Empty);

    [RelayCommand]
    private void ExitApplication() => ExitRequested?.Invoke(this, EventArgs.Empty);

    [RelayCommand]
    private void BrowseCodexExecutable() => BrowseCodexExecutableRequested?.Invoke(this, EventArgs.Empty);

    partial void OnAlwaysOnTopChanged(bool value)
    {
        RefreshEffectiveAlwaysOnTop();

        if (_suspendPersistence)
        {
            return;
        }

        PersistSettings();
        TopmostChanged?.Invoke(this, value);
    }

    partial void OnLaunchOnStartupChanged(bool value)
    {
        if (_suspendPersistence)
        {
            return;
        }

        _autostartService.SetEnabled(value);
        PersistSettings();
    }

    partial void OnClickThroughChanged(bool value)
    {
        RefreshEffectiveAlwaysOnTop();

        if (_suspendPersistence)
        {
            return;
        }

        PersistSettings();
        ClickThroughChanged?.Invoke(this, value);
    }

    partial void OnCodexExecutablePathChanged(string value)
    {
        if (_suspendPersistence)
        {
            return;
        }

        _codexAppServerClient.PreferredExecutablePath = value;
        PersistSettings();
    }

    partial void OnUseSystemProxyForCodexChanged(bool value)
    {
        _codexAppServerClient.UseSystemProxy = value;

        if (_suspendPersistence)
        {
            return;
        }

        PersistSettings();
        _ = ReconnectAsync();
    }

    private async void OnBucketsUpdated(object? sender, IReadOnlyList<RateLimitBucket> buckets)
    {
        await RunOnUiAsync(() => ApplyBuckets(buckets));
    }

    private async void OnClientRateLimitsUpdated(object? sender, IReadOnlyList<RateLimitBucket> buckets)
    {
        await RunOnUiAsync(() =>
        {
            IsQuotaLive = true;
            _rateLimitStore.ReplaceBuckets(buckets);
        });
    }

    private async void OnConnectionStateChanged(object? sender, AppServerConnectionState state)
    {
        await RunOnUiAsync(() =>
        {
            UpdateConnectionStatus(state);
            ApplyConnectionStateCards(state);

            if (!string.IsNullOrWhiteSpace(_codexAppServerClient.ExecutablePath))
            {
                CodexExecutablePath = _codexAppServerClient.ExecutablePath;
            }
        });
    }

    private void ApplyBuckets(IReadOnlyList<RateLimitBucket> buckets)
    {
        FiveHourCard = BuildCard(buckets.FirstOrDefault(bucket => bucket.WindowDurationMins == 300), "5h");
        WeeklyCard = BuildCard(buckets.FirstOrDefault(bucket => bucket.WindowDurationMins == 10080), "1w");

        if (IsQuotaLive && _rateLimitStore.LastUpdatedAtUtc is DateTimeOffset lastUpdated)
        {
            ConnectionStatusText = $"Connected | synced {lastUpdated.ToLocalTime():HH:mm:ss}";
        }
    }

    private static RateLimitCardDisplay BuildCard(RateLimitBucket? bucket, string fallbackLabel)
    {
        if (bucket is null)
        {
            return RateLimitCardDisplay.Placeholder(fallbackLabel, "Unavailable");
        }

        var resetText = bucket.ResetsAtUtc is DateTimeOffset resetsAt
            ? $"Until {FormatRefreshTime(resetsAt, bucket.WindowDurationMins == 300)}"
            : "Until --";

        return new RateLimitCardDisplay(
            Label: bucket.Label,
            RemainingText: $"{bucket.RemainingPercent:0}%",
            ResetText: resetText,
            SyncedText: bucket.SyncedAtUtc.ToLocalTime().ToString("HH:mm:ss"),
            StatusText: $"{bucket.UsedPercent:0}% used",
            RemainingPercent: bucket.RemainingPercent,
            UsedPercent: bucket.UsedPercent);
    }

    private void UpdateConnectionStatus(AppServerConnectionState state)
    {
        if (state != AppServerConnectionState.Connected)
        {
            IsQuotaLive = false;
        }

        ConnectionStatusText = state switch
        {
            AppServerConnectionState.Connected => "Connected to Codex app-server, syncing latest quota...",
            AppServerConnectionState.Connecting => "Connecting to Codex app-server...",
            AppServerConnectionState.MissingExecutable => "Codex not installed or codex.exe not found",
            AppServerConnectionState.Degraded => "Codex app-server unavailable, showing cached history",
            _ => "Codex app-server offline, showing cached history"
        };
    }

    private void ApplyConnectionStateCards(AppServerConnectionState state)
    {
        if (_rateLimitStore.Buckets.Count > 0 && state != AppServerConnectionState.MissingExecutable)
        {
            return;
        }

        switch (state)
        {
            case AppServerConnectionState.MissingExecutable:
                FiveHourCard = RateLimitCardDisplay.Placeholder("5h", "Codex missing", "Install Codex");
                WeeklyCard = RateLimitCardDisplay.Placeholder("1w", "Codex missing", "Install Codex");
                break;
            case AppServerConnectionState.Connecting:
                FiveHourCard = RateLimitCardDisplay.Placeholder("5h", "Connecting");
                WeeklyCard = RateLimitCardDisplay.Placeholder("1w", "Connecting");
                break;
            case AppServerConnectionState.Disconnected:
                FiveHourCard = RateLimitCardDisplay.Placeholder("5h", "Offline", "Unavailable");
                WeeklyCard = RateLimitCardDisplay.Placeholder("1w", "Offline", "Unavailable");
                break;
            case AppServerConnectionState.Degraded when _rateLimitStore.Buckets.Count == 0:
                FiveHourCard = RateLimitCardDisplay.Placeholder("5h", "Unavailable", "Unavailable");
                WeeklyCard = RateLimitCardDisplay.Placeholder("1w", "Unavailable", "Unavailable");
                break;
        }
    }

    private void PersistSettings()
    {
        _settings.AlwaysOnTop = AlwaysOnTop;
        _settings.LaunchOnStartup = LaunchOnStartup;
        _settings.ClickThrough = ClickThrough;
        _settings.UseSystemProxyForCodex = UseSystemProxyForCodex;
        _settings.CodexExecutablePath = CodexExecutablePath;
        _settingsService.Save(_settings);
    }

    private void RefreshEffectiveAlwaysOnTop()
    {
        EffectiveAlwaysOnTop = AlwaysOnTop && !ClickThrough;
    }

    private static string FormatRefreshTime(DateTimeOffset resetAtUtc, bool timeOnly = false)
    {
        var local = resetAtUtc.ToLocalTime();
        if (timeOnly)
        {
            return local.ToString("HH:mm");
        }

        var now = DateTimeOffset.Now;
        return local.Date == now.Date
            ? local.ToString("HH:mm")
            : local.ToString("MM-dd HH:mm");
    }

    private static Task RunOnUiAsync(Action action)
    {
        if (App.Current.Dispatcher.CheckAccess())
        {
            action();
            return Task.CompletedTask;
        }

        return App.Current.Dispatcher.InvokeAsync(action).Task;
    }
}
