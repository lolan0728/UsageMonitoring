using Microsoft.Win32;
using System.ComponentModel;
using System.Windows;
using System.Windows.Input;
using UsageMonitoring.App.Models;
using UsageMonitoring.App.Services;
using UsageMonitoring.App.ViewModels;

namespace UsageMonitoring.App;

public partial class MainWindow : Window
{
    private readonly MainViewModel _viewModel;
    private readonly AppSettings _settings;
    private readonly SettingsService _settingsService;
    private readonly WindowMaterialService _windowMaterialService;
    private bool _allowClose;
    private bool _startupPositionApplied;

    public MainWindow(
        MainViewModel viewModel,
        AppSettings settings,
        SettingsService settingsService,
        WindowMaterialService windowMaterialService)
    {
        InitializeComponent();
        _viewModel = viewModel;
        _settings = settings;
        _settingsService = settingsService;
        _windowMaterialService = windowMaterialService;
        DataContext = viewModel;

        _viewModel.ClickThroughChanged += OnClickThroughChanged;
    }

    public void ShowPanel()
    {
        Show();
        if (WindowState == WindowState.Minimized)
        {
            WindowState = WindowState.Normal;
        }

        Activate();
    }

    public void HidePanel() => Hide();

    public void PrepareForShutdown() => _allowClose = true;

    public void BrowseForCodexExecutable()
    {
        var dialog = new OpenFileDialog
        {
            Title = "Locate codex.exe",
            Filter = "Codex executable|codex.exe|Executable files|*.exe|All files|*.*",
            FileName = "codex.exe",
            CheckFileExists = true
        };

        if (dialog.ShowDialog(this) == true)
        {
            _viewModel.SetCodexExecutablePath(dialog.FileName);
        }
    }

    private void Window_SourceInitialized(object? sender, EventArgs e)
    {
        _windowMaterialService.SetClickThrough(this, _viewModel.ClickThrough);
        ApplyStartupPosition();
    }

    private void Window_Closing(object? sender, CancelEventArgs e)
    {
        if (_allowClose || ((App)Application.Current).IsShuttingDown)
        {
            PersistWindowPosition();
            return;
        }

        e.Cancel = true;
        HidePanel();
    }

    private void Window_LocationChanged(object? sender, EventArgs e)
    {
        if (_startupPositionApplied)
        {
            PersistWindowPosition();
        }
    }

    private void Window_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (_startupPositionApplied && e.HeightChanged)
        {
            SnapToWorkArea();
        }
    }

    private void DragHandle_OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState != MouseButtonState.Pressed || _viewModel.ClickThrough)
        {
            return;
        }

        DragMove();
        SnapToWorkArea();
        PersistWindowPosition();
    }

    private void OnClickThroughChanged(object? sender, bool enabled)
    {
        _windowMaterialService.SetClickThrough(this, enabled);
    }

    private void ApplyStartupPosition()
    {
        if (_settings.WindowLeft is double left && _settings.WindowTop is double top)
        {
            Left = left;
            Top = top;
        }
        else
        {
            var workArea = SystemParameters.WorkArea;
            Left = workArea.Right - Width - 28;
            Top = workArea.Top + 28;
        }

        _startupPositionApplied = true;
        SnapToWorkArea();
    }

    private void SnapToWorkArea()
    {
        var workArea = SystemParameters.WorkArea;
        const double threshold = 36;
        const double margin = 16;

        if (Math.Abs(Left - workArea.Left) <= threshold)
        {
            Left = workArea.Left + margin;
        }
        else if (Math.Abs((Left + Width) - workArea.Right) <= threshold)
        {
            Left = workArea.Right - Width - margin;
        }

        if (Math.Abs(Top - workArea.Top) <= threshold)
        {
            Top = workArea.Top + margin;
        }
        else if (Math.Abs((Top + Height) - workArea.Bottom) <= threshold)
        {
            Top = workArea.Bottom - Height - margin;
        }

        Left = Math.Clamp(Left, workArea.Left + margin, workArea.Right - Width - margin);
        Top = Math.Clamp(Top, workArea.Top + margin, workArea.Bottom - Height - margin);
    }

    private void PersistWindowPosition()
    {
        _settings.WindowLeft = Left;
        _settings.WindowTop = Top;
        _settingsService.Save(_settings);
    }
}
