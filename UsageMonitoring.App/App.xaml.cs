using System.Windows;
using System.Windows.Controls;
using H.NotifyIcon;
using UsageMonitoring.App.Models;
using UsageMonitoring.App.Services;
using UsageMonitoring.App.ViewModels;

namespace UsageMonitoring.App;

public partial class App : Application
{
    private Mutex? _singleInstanceMutex;
    private SettingsService? _settingsService;
    private AppSettings? _settings;
    private AutostartService? _autostartService;
    private RateLimitSnapshotService? _rateLimitSnapshotService;
    private RateLimitStore? _rateLimitStore;
    private CodexAppServerClient? _codexClient;
    private MemoryFootprintService? _memoryFootprintService;
    private MainViewModel? _mainViewModel;
    private MainWindow? _mainWindow;
    private TaskbarIcon? _trayIcon;

    public bool IsShuttingDown { get; private set; }

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        ShutdownMode = ShutdownMode.OnExplicitShutdown;
        _singleInstanceMutex = new Mutex(initiallyOwned: true, @"Global\UsageMonitoring.Singleton", out var createdNew);
        if (!createdNew)
        {
            Shutdown();
            return;
        }

        _settingsService = new SettingsService();
        _settings = _settingsService.Load();
        _autostartService = new AutostartService();
        _rateLimitSnapshotService = new RateLimitSnapshotService();
        _rateLimitStore = new RateLimitStore();
        _memoryFootprintService = new MemoryFootprintService(TimeSpan.FromMinutes(5));
        _memoryFootprintService.Start();

        var cachedBuckets = _rateLimitSnapshotService.Load();
        if (cachedBuckets.Count > 0)
        {
            _rateLimitStore.ReplaceBuckets(cachedBuckets);
        }

        _rateLimitStore.BucketsUpdated += OnRateLimitStoreBucketsUpdated;

        var locator = new CodexExecutableLocator();
        _codexClient = new CodexAppServerClient(locator, _settings.CodexExecutablePath)
        {
            PreferredExecutablePath = _settings.CodexExecutablePath
        };

        _mainViewModel = new MainViewModel(
            _settings,
            _settingsService,
            _autostartService,
            _rateLimitStore,
            _codexClient);
        _mainViewModel.HideRequested += (_, _) => HidePanel();
        _mainViewModel.ExitRequested += (_, _) => Shutdown();
        _mainViewModel.BrowseCodexExecutableRequested += (_, _) => _mainWindow?.BrowseForCodexExecutable();

        _mainWindow = new MainWindow(_mainViewModel, _settings, _settingsService, new WindowMaterialService());
        MainWindow = _mainWindow;

        _trayIcon = (TaskbarIcon)FindResource("TrayIcon");
        _trayIcon.ForceCreate();

        _mainWindow.Show();
        await _mainViewModel.InitializeAsync();
    }

    protected override async void OnExit(ExitEventArgs e)
    {
        IsShuttingDown = true;

        if (_mainWindow is not null)
        {
            _mainWindow.PrepareForShutdown();
        }

        _trayIcon?.Dispose();

        if (_codexClient is not null)
        {
            await _codexClient.DisposeAsync();
        }

        if (_memoryFootprintService is not null)
        {
            await _memoryFootprintService.DisposeAsync();
        }

        if (_singleInstanceMutex is not null)
        {
            _singleInstanceMutex.ReleaseMutex();
            _singleInstanceMutex.Dispose();
        }

        base.OnExit(e);
    }

    private void TrayIcon_OnTrayLeftMouseUp(object sender, RoutedEventArgs e) => TogglePanelVisibility();

    private void TrayContextMenu_OnOpened(object sender, RoutedEventArgs e)
    {
        if (sender is not ContextMenu contextMenu)
        {
            return;
        }

        var isWindowVisible = _mainWindow?.IsVisible == true;
        var isClickThroughEnabled = _mainViewModel?.ClickThrough == true;
        foreach (var item in contextMenu.Items)
        {
            if (item is not MenuItem menuItem)
            {
                continue;
            }

            if (Equals(menuItem.Tag, "ShowItem"))
            {
                menuItem.Visibility = isWindowVisible ? Visibility.Collapsed : Visibility.Visible;
            }
            else if (Equals(menuItem.Tag, "HideItem"))
            {
                menuItem.Visibility = isWindowVisible ? Visibility.Visible : Visibility.Collapsed;
            }
            else if (Equals(menuItem.Tag, "LocateCodexItem"))
            {
                menuItem.Visibility = Visibility.Visible;
            }
            else if (Equals(menuItem.Tag, "ToggleClickThroughItem"))
            {
                menuItem.Visibility = Visibility.Visible;
                menuItem.Header = isClickThroughEnabled
                    ? "Disable Click-through"
                    : "Enable Click-through";
            }
        }
    }

    private void ShowPanelMenuItem_OnClick(object sender, RoutedEventArgs e) => ShowPanel();

    private void HidePanelMenuItem_OnClick(object sender, RoutedEventArgs e) => HidePanel();

    private async void LocateCodexMenuItem_OnClick(object sender, RoutedEventArgs e)
    {
        if (_mainWindow is null || _mainViewModel is null)
        {
            return;
        }

        ShowPanel();
        _mainWindow.BrowseForCodexExecutable();
        await _mainViewModel.TryConnectToCodexAsync();
    }

    private void ToggleClickThroughMenuItem_OnClick(object sender, RoutedEventArgs e)
    {
        if (_mainViewModel is null)
        {
            return;
        }

        _mainViewModel.ClickThrough = !_mainViewModel.ClickThrough;
    }

    private void ExitMenuItem_OnClick(object sender, RoutedEventArgs e) => Shutdown();

    private void TogglePanelVisibility()
    {
        if (_mainWindow is null)
        {
            return;
        }

        if (_mainWindow.IsVisible)
        {
            HidePanel();
        }
        else
        {
            ShowPanel();
        }
    }

    private void ShowPanel() => _mainWindow?.ShowPanel();

    private void HidePanel()
    {
        _mainWindow?.HidePanel();
        _memoryFootprintService?.TrimNow(forceGc: true);
    }

    private void OnRateLimitStoreBucketsUpdated(object? sender, IReadOnlyList<RateLimitBucket> buckets)
    {
        _rateLimitSnapshotService?.Save(buckets);
    }
}
