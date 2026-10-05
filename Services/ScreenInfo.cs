using FluentPomodoro.Interop;

namespace FluentPomodoro.Services;

/// <summary>屏幕几何信息（物理像素）。用于“强制大屏”定位。</summary>
internal static class ScreenInfo
{
    /// <summary>主显示器工作区与整屏区域（物理像素）</summary>
    public static (int Left, int Top, int Width, int Height) PrimaryMonitorBounds()
    {
        try
        {
            var monitor = Native.MonitorFromWindow(IntPtr.Zero, Native.MONITOR_DEFAULTTOPRIMARY);
            if (monitor != IntPtr.Zero)
            {
                var info = new Native.MONITORINFO { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<Native.MONITORINFO>() };
                if (Native.GetMonitorInfo(monitor, ref info))
                    return (info.rcMonitor.Left, info.rcMonitor.Top, info.rcMonitor.Width, info.rcMonitor.Height);
            }
        }
        catch
        {
            // 忽略，退回系统度量
        }

        return (0, 0,
            Math.Max(1, Native.GetSystemMetrics(Native.SM_CXVIRTUALSCREEN)),
            Math.Max(1, Native.GetSystemMetrics(Native.SM_CYVIRTUALSCREEN)));
    }

    /// <summary>整个虚拟桌面（所有显示器合成的巨幕）区域，物理像素</summary>
    public static (int Left, int Top, int Width, int Height) VirtualScreenBounds()
    {
        int left = Native.GetSystemMetrics(Native.SM_XVIRTUALSCREEN);
        int top = Native.GetSystemMetrics(Native.SM_YVIRTUALSCREEN);
        int width = Native.GetSystemMetrics(Native.SM_CXVIRTUALSCREEN);
        int height = Native.GetSystemMetrics(Native.SM_CYVIRTUALSCREEN);
        if (width <= 0 || height <= 0) return PrimaryMonitorBounds();
        return (left, top, width, height);
    }

    /// <summary>显示器数量</summary>
    public static int MonitorCount()
    {
        int count = 0;
        try
        {
            Native.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero,
                (IntPtr h, IntPtr hdc, ref Native.RECT r, IntPtr data) => { count++; return true; }, IntPtr.Zero);
        }
        catch
        {
            count = 1;
        }
        return Math.Max(1, count);
    }
}
