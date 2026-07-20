using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using UsageMonitoring.App.Models;
using UsageMonitoring.App.Services;

namespace UsageMonitoring.App.ViewModels;

public partial class MainViewModel : ObservableObject
{
    private const double CardDesignHeight = 146;
    private const double CardDesignGap = 8;
    private const double TwoCardWindowHeight = 190;
    private const double TwoCardDesignHeight = (CardDesignHeight * 2) + CardDesignGap;

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

        QuotaCards.Add(RateLimitCardDisplay.Placeholder());
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

    public ObservableCollection<RateLimitCardDisplay> QuotaCards { get; } = [];

    [ObservableProperty]
    private double panelHeight = 95;

    [ObservableProperty]
    private double panelDesignHeight = CardDesignHeight;

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
        _rateLimitStore.SnapshotUpdated += OnSnapshotUpdated;
        _codexAppServerClient.QuotaUpdated += OnClientQuotaUpdated;
        _codexAppServerClient.ConnectionStateChanged += OnConnectionStateChanged;
        UpdateConnectionStatus(_codexAppServerClient.ConnectionState);
        ApplySnapshot(_rateLimitStore.Snapshot, isLive: false);

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

    private async void OnSnapshotUpdated(object? sender, CodexQuotaSnapshot snapshot)
    {
        await RunOnUiAsync(() => ApplySnapshot(snapshot, IsQuotaLive));
    }

    private async void OnClientQuotaUpdated(object? sender, CodexQuotaSnapshot snapshot)
    {
        await RunOnUiAsync(() =>
        {
            IsQuotaLive = true;
            _rateLimitStore.ReplaceSnapshot(snapshot);
        });
    }

    private async void OnConnectionStateChanged(object? sender, AppServerConnectionState state)
    {
        await RunOnUiAsync(() =>
        {
            UpdateConnectionStatus(state);
            if (state != AppServerConnectionState.Connected)
            {
                IsQuotaLive = false;
                ApplySnapshot(_rateLimitStore.Snapshot, isLive: false);
            }

            if (!string.IsNullOrWhiteSpace(_codexAppServerClient.ExecutablePath))
            {
                CodexExecutablePath = _codexAppServerClient.ExecutablePath;
            }
        });
    }

    private void ApplySnapshot(CodexQuotaSnapshot snapshot, bool isLive)
    {
        var cards = snapshot.Limits
            .Select((limit, index) => BuildLimitCard(limit, isLive, index))
            .ToList();

        if (ShouldDisplayCredits(snapshot.Credits))
        {
            cards.Add(BuildCreditsCard(snapshot.Credits!, snapshot, isLive));
        }

        if (cards.Count == 0)
        {
            cards.Add(RateLimitCardDisplay.Placeholder());
        }

        QuotaCards.Clear();
        foreach (var card in cards)
        {
            QuotaCards.Add(card);
        }

        UpdatePanelDimensions(cards.Count);

        if (isLive && snapshot.SyncedAtUtc != DateTimeOffset.MinValue)
        {
            ConnectionStatusText = $"Connected | synced {snapshot.SyncedAtUtc.ToLocalTime():HH:mm:ss}";
        }
    }

    private static RateLimitCardDisplay BuildLimitCard(
        RateLimitBucket bucket,
        bool isLive,
        int index)
    {
        var resetText = bucket.ResetsAtUtc is DateTimeOffset resetsAt
            ? $"Until {FormatRefreshTime(resetsAt, bucket.WindowDurationMins)}"
            : "Until --";

        return new RateLimitCardDisplay(
            Label: bucket.Label,
            RemainingText: $"{bucket.RemainingPercent:0}%",
            ResetText: resetText,
            SyncedText: bucket.SyncedAtUtc.ToLocalTime().ToString("HH:mm:ss"),
            StatusText: $"{bucket.UsedPercent:0}% used",
            RingPercentage: bucket.RemainingPercent,
            IsLive: isLive,
            Accent: GetLimitAccent(bucket, index));
    }

    private static RateLimitCardDisplay BuildCreditsCard(
        CreditStatus credits,
        CodexQuotaSnapshot snapshot,
        bool isLive)
    {
        string primaryText;
        string secondaryText;

        if (credits.Unlimited)
        {
            primaryText = "∞";
            secondaryText = "Unlimited";
        }
        else if (!string.IsNullOrWhiteSpace(credits.Balance))
        {
            primaryText = credits.Balance.Trim();
            secondaryText = "Credits";
        }
        else
        {
            primaryText = "Ready";
            secondaryText = "Credits available";
        }

        return new RateLimitCardDisplay(
            Label: "Credits",
            RemainingText: primaryText,
            ResetText: secondaryText,
            SyncedText: snapshot.SyncedAtUtc.ToLocalTime().ToString("HH:mm:ss"),
            StatusText: snapshot.PlanType ?? "Credit balance",
            RingPercentage: 100,
            IsLive: isLive,
            Accent: QuotaCardAccent.Amber);
    }

    private static bool ShouldDisplayCredits(CreditStatus? credits) =>
        credits is { Unlimited: true } ||
        credits is { HasCredits: true };

    private static QuotaCardAccent GetLimitAccent(RateLimitBucket bucket, int index)
    {
        if (bucket.WindowDurationMins == 10080)
        {
            return QuotaCardAccent.Cyan;
        }

        return index % 2 == 0
            ? QuotaCardAccent.Green
            : QuotaCardAccent.Cyan;
    }

    private void UpdatePanelDimensions(int cardCount)
    {
        var normalizedCount = Math.Max(1, cardCount);
        PanelDesignHeight = (CardDesignHeight * normalizedCount) +
                            (CardDesignGap * (normalizedCount - 1));
        PanelHeight = Math.Max(
            95,
            Math.Round(PanelDesignHeight * (TwoCardWindowHeight / TwoCardDesignHeight)));
    }

    private void UpdateConnectionStatus(AppServerConnectionState state)
    {
        ConnectionStatusText = state switch
        {
            AppServerConnectionState.Connected => "Connected to Codex app-server, syncing latest quota...",
            AppServerConnectionState.Connecting => "Connecting to Codex app-server...",
            AppServerConnectionState.MissingExecutable => "Codex not installed or codex.exe not found",
            AppServerConnectionState.Degraded => "Codex app-server unavailable, showing cached usage",
            _ => "Codex app-server offline, showing cached usage"
        };
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

    private static string FormatRefreshTime(DateTimeOffset resetAtUtc, int? windowDurationMins)
    {
        var local = resetAtUtc.ToLocalTime();
        if (windowDurationMins is > 0 and < 1440)
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
