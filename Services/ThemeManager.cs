using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace FluentPomodoro.Services;

/// <summary>浅色/深色主题管理，调色板来自 Themes 目录，强调色取自 Windows 个性化设置。</summary>
public static class ThemeManager
{
    private const string LightUri = "/FluentPomodoro;component/Themes/Palette.Light.xaml";
    private const string DarkUri = "/FluentPomodoro;component/Themes/Palette.Dark.xaml";

    /// <summary>主题切换后触发，界面需要重设的颜色在此时刷新。</summary>
    public static event EventHandler? ThemeChanged;

    public static ThemePreference Preference { get; private set; } = ThemePreference.System;

    public static bool IsDark { get; private set; }

    public static Color AccentColor { get; private set; } = Color.FromRgb(0x00, 0x67, 0xC0);

    public static void Initialize(ThemePreference? force = null)
    {
        Preference = force ?? ThemePreference.System;
        Apply();
    }

    public static void SetPreference(ThemePreference preference)
    {
        Preference = preference;
        Apply();
    }

    /// <summary>
    /// 强调色覆盖（例如取自背景图片主色）。设为 null 则回到系统强调色。
    /// </summary>
    public static Color? AccentOverride { get; private set; }

    public static void SetAccentOverride(Color? color)
    {
        if (AccentOverride == color) return;
        AccentOverride = color;
        Apply();
    }

    public static void Apply()
    {
        var app = Application.Current;
        if (app is null) return;

        bool dark = Preference switch
        {
            ThemePreference.Dark => true,
            ThemePreference.Light => false,
            _ => IsSystemDark()
        };
        IsDark = dark;

        var palette = new ResourceDictionary
        {
            Source = new Uri(dark ? DarkUri : LightUri, UriKind.Relative)
        };
        var accent = AccentService.Build(dark, AccentOverride);
        AccentColor = accent.Accent;

        var dicts = app.Resources.MergedDictionaries;
        if (dicts.Count >= 3)
        {
            dicts[0] = palette;
            dicts[1] = accent.Dictionary;
        }
        else
        {
            if (dicts.Count > 0) dicts[0] = palette;
            else dicts.Add(palette);
            dicts.Insert(1, accent.Dictionary);
        }

        ThemeChanged?.Invoke(null, EventArgs.Empty);
    }

    /// <summary>读取系统“应用模式”设置：深色返回 true。</summary>
    public static bool IsSystemDark()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            if (key?.GetValue("AppsUseLightTheme") is int v) return v == 0;
        }
        catch
        {
            // 读取失败按浅色处理
        }
        return false;
    }

    /// <summary>读取 Windows 个性化强调色（AccentColor 为 0xAABBGGRR）。</summary>
    public static Color? GetSystemAccent()
    {
        foreach (var (path, name) in new[]
        {
            (@"Software\Microsoft\Windows\DWM", "AccentColor"),
            (@"Software\Microsoft\Windows\CurrentVersion\Explorer\Accent", "AccentColorMenu")
        })
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(path);
                if (key?.GetValue(name) is int raw)
                {
                    var color = Color.FromRgb((byte)(raw & 0xFF), (byte)((raw >> 8) & 0xFF), (byte)((raw >> 16) & 0xFF));
                    int alpha = (raw >> 24) & 0xFF;
                    if (alpha == 0) alpha = 0xFF;
                    if (color.R + color.G + color.B > 24) return color;
                }
            }
            catch
            {
                // 继续尝试下一个来源
            }
        }
        return null;
    }
}

internal readonly record struct AccentResult(ResourceDictionary Dictionary, Color Accent);

/// <summary>根据主题与系统强调色生成 Fluent 强调色变体。</summary>
internal static class AccentService
{
    public static AccentResult Build(bool dark, Color? overrideColor = null)
    {
        var accent = overrideColor
                     ?? ThemeManager.GetSystemAccent()
                     ?? (dark ? Color.FromRgb(0x60, 0xCD, 0xFF) : Color.FromRgb(0x00, 0x67, 0xC0));

        double luminance = Luminance(accent);
        Color fill = accent;
        if (dark && luminance < 0.36) fill = Mix(accent, Colors.White, 0.45);
        if (!dark && luminance > 0.78) fill = Mix(accent, Colors.Black, 0.25);

        var dict = new ResourceDictionary
        {
            ["AccentFillBrush"] = Brush(fill),
            ["AccentHoverBrush"] = Brush(Mix(fill, Colors.White, 0.14)),
            ["AccentPressBrush"] = Brush(Mix(fill, Colors.White, 0.30)),
            ["AccentBrush"] = Brush(fill),
            ["AccentSubtleBrush"] = Brush(Mix(fill, dark ? Colors.Black : Colors.White, 0.86)),
            ["AccentGlowBrush"] = Brush(Color.FromArgb(0x38, fill.R, fill.G, fill.B)),
            ["PhaseFocusBrush"] = Brush(fill),
            ["TextOnAccentBrush"] = Brush(Luminance(fill) > 0.6 ? Color.FromRgb(0x0A, 0x0A, 0x0A) : Colors.White)
        };

        return new AccentResult(dict, fill);
    }

    private static SolidColorBrush Brush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private static double Luminance(Color c) => (0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B) / 255.0;

    private static Color Mix(Color a, Color b, double t)
    {
        t = Math.Clamp(t, 0, 1);
        return Color.FromRgb(
            (byte)Math.Round(a.R + (b.R - a.R) * t),
            (byte)Math.Round(a.G + (b.G - a.G) * t),
            (byte)Math.Round(a.B + (b.B - a.B) * t));
    }
}
