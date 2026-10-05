namespace FluentPomodoro.Services;

/// <summary>番茄钟阶段</summary>
public enum PhaseKind
{
    Focus,
    ShortBreak,
    LongBreak
}

/// <summary>大屏方式</summary>
public enum BigScreenMode
{
    /// <summary>普通窗口</summary>
    None,

    /// <summary>全屏（铺满当前主显示器，盖住任务栏）</summary>
    Full,

    /// <summary>巨幕（横跨全部显示器，合成一块大屏）</summary>
    Mega
}

/// <summary>主题偏好</summary>
public enum ThemePreference
{
    System,
    Light,
    Dark
}

public static class PhaseExtensions
{
    public static string DisplayName(this PhaseKind phase) => phase switch
    {
        PhaseKind.Focus => "专注",
        PhaseKind.ShortBreak => "短休息",
        PhaseKind.LongBreak => "长休息",
        _ => "专注"
    };

    public static string ResourceKey(this PhaseKind phase) => phase switch
    {
        PhaseKind.Focus => "PhaseFocusBrush",
        PhaseKind.ShortBreak => "PhaseShortBrush",
        _ => "PhaseLongBrush"
    };
}
