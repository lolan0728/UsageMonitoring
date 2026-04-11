using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace UsageMonitoring.App.Services;

public sealed class WindowMaterialService
{
    private const int DwmUseImmersiveDarkMode = 20;
    private const int DwmWindowCornerPreference = 33;
    private const int DwmSystemBackdropType = 38;
    private const int WsExLayered = 0x00080000;
    private const int WsExTransparent = 0x00000020;
    private const int GwlExStyle = -20;

    public void Apply(Window window)
    {
        var handle = new WindowInteropHelper(window).EnsureHandle();
        var enabled = 1;
        var sharpCorners = 1;
        var acrylicBackdrop = 3;
        var margins = new Margins(-1);

        DwmSetWindowAttribute(handle, DwmUseImmersiveDarkMode, ref enabled, Marshal.SizeOf<int>());
        DwmSetWindowAttribute(handle, DwmWindowCornerPreference, ref sharpCorners, Marshal.SizeOf<int>());
        DwmSetWindowAttribute(handle, DwmSystemBackdropType, ref acrylicBackdrop, Marshal.SizeOf<int>());
        DwmExtendFrameIntoClientArea(handle, ref margins);
    }

    public void SetClickThrough(Window window, bool enabled)
    {
        var handle = new WindowInteropHelper(window).EnsureHandle();
        var current = GetWindowLong(handle, GwlExStyle);
        var next = enabled
            ? current | WsExLayered | WsExTransparent
            : current & ~WsExTransparent;

        SetWindowLong(handle, GwlExStyle, next);
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int pvAttribute, int cbAttribute);

    [DllImport("dwmapi.dll")]
    private static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref Margins margins);

    [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [StructLayout(LayoutKind.Sequential)]
    private struct Margins
    {
        public Margins(int uniformMargin)
        {
            Left = uniformMargin;
            Right = uniformMargin;
            Top = uniformMargin;
            Bottom = uniformMargin;
        }

        public int Left;
        public int Right;
        public int Top;
        public int Bottom;
    }
}
