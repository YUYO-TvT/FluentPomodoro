using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using FluentPomodoro.Controls;
using FluentPomodoro.Interop;
using FluentPomodoro.Services;
using Microsoft.Win32;

namespace FluentPomodoro;

public partial class StatsWindow : Window
{
    private FocusHistory _history = new();
    private IntPtr _hwnd;
    private EventHandler? _themeChangedHandler;

    public StatsWindow()
    {
        InitializeComponent();
        Reload();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);

        _hwnd = new WindowInteropHelper(this).Handle;
        ApplyDwmTheme();

        _themeChangedHandler = (_, _) =>
        {
            ApplyDwmTheme();
            RenderHeat();
        };
        ThemeManager.ThemeChanged += _themeChangedHandler;

        RenderHeat();
    }

    protected override void OnClosed(EventArgs e)
    {
        if (_themeChangedHandler is not null) ThemeManager.ThemeChanged -= _themeChangedHandler;
        base.OnClosed(e);
    }

    private void OnWindowActivated(object? sender, EventArgs e) => Reload();

    private void OnWindowClosing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        // 关闭时不做任何持久化，统计窗口是只读视图
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        bool ctrl = (Keyboard.Modifiers & ModifierKeys.Control) != 0;
        if (e.Key == Key.Escape || (ctrl && e.Key == Key.W))
        {
            Close();
            e.Handled = true;
        }
    }

    private void OnCloseClick(object sender, RoutedEventArgs e) => Close();

    private void Reload()
    {
        _history = FocusHistory.Load();
        RenderSummary();
        RenderHeat();
    }

    private void RenderSummary()
    {
        var today = DateTime.Today;
        int todayMinutes = _history.MinutesOn(today);
        int todayPomodoros = _history.PomodorosOn(today);

        var weekStart = today.AddDays(-(((int)today.DayOfWeek + 6) % 7));
        var monthStart = new DateTime(today.Year, today.Month, 1);

        int weekMinutes = _history.MinutesBetween(weekStart, today);
        int monthMinutes = _history.MinutesBetween(monthStart, today);
        int totalMinutes = _history.TotalMinutes;
        int totalPomodoros = _history.TotalPomodoros;
        int streak = _history.CurrentStreak;
        var (bestDay, bestMinutes) = _history.BestDay();

        ValToday.Text = FormatDuration(todayMinutes);
        SubToday.Text = $"{todayPomodoros} 个番茄";

        ValWeek.Text = FormatDuration(weekMinutes);
        SubWeek.Text = $"{FormatDate(weekStart)} 起";

        ValMonth.Text = FormatDuration(monthMinutes);
        SubMonth.Text = $"{today.Month} 月";

        ValTotal.Text = FormatDuration(totalMinutes);
        SubTotal.Text = $"{totalPomodoros} 个番茄";

        ValStreak.Text = $"{streak}";
        ValBest.Text = bestMinutes > 0 ? FormatDuration(bestMinutes) : "—";
        SubBest.Text = bestMinutes > 0 ? FormatDate(bestDay) : "暂无记录";

        TxtRange.Text = $"共 {_history.Days.Count} 天有记录";
        TxtSummaryLine.Text =
            $"统计自本机数据文件：{FocusHistory.FilePath}\n" +
            $"累计专注 {FormatDuration(totalMinutes)}，完成 {totalPomodoros} 个番茄。";
    }

    private void RenderHeat()
    {
        var today = DateTime.Today;
        var start = today.AddDays(-(ContributionGraph.Weeks * 7 + 7));
        Heat.EndDate = today;
        Heat.DailyMinutes = _history.DailyMinutes(start, today);
    }

    private static string FormatDuration(int minutes)
    {
        if (minutes <= 0) return "0 分钟";
        if (minutes < 60) return $"{minutes} 分钟";
        int hours = minutes / 60;
        int rest = minutes % 60;
        return rest == 0 ? $"{hours} 小时" : $"{hours} 小时 {rest} 分";
    }

    private static string FormatDate(DateTime day) => day.ToString("yyyy-MM-dd");

    private void OnHeatHovered(object sender, ContributionDayEventArgs e)
    {
        var weekday = e.Day.DayOfWeek switch
        {
            DayOfWeek.Monday => "周一",
            DayOfWeek.Tuesday => "周二",
            DayOfWeek.Wednesday => "周三",
            DayOfWeek.Thursday => "周四",
            DayOfWeek.Friday => "周五",
            DayOfWeek.Saturday => "周六",
            _ => "周日"
        };

        int pomodoros = _history.PomodorosOn(e.Day);
        string detail = e.Minutes > 0
            ? $"专注 {FormatDuration(e.Minutes)} · {pomodoros} 个番茄"
            : "没有专注记录";

        HeatTipText.Text = $"{e.Day:yyyy-MM-dd} {weekday}\n{detail}";
        HeatTip.IsOpen = true;
    }

    private void OnHeatUnhovered(object sender, EventArgs e) => HeatTip.IsOpen = false;

    private void OnExportCsv(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog
        {
            Title = "导出专注统计",
            FileName = $"番茄钟统计-{DateTime.Today:yyyyMMdd}.csv",
            Filter = "CSV 文件 (*.csv)|*.csv|所有文件 (*.*)|*.*"
        };
        if (dialog.ShowDialog(this) != true) return;

        try
        {
            var builder = new StringBuilder();
            builder.AppendLine("日期,专注分钟,番茄数");
            foreach (var pair in _history.Days.OrderBy(p => p.Key, StringComparer.Ordinal))
            {
                builder.AppendLine($"{pair.Key},{pair.Value.Minutes},{pair.Value.Pomodoros}");
            }
            File.WriteAllText(dialog.FileName, builder.ToString(), new UTF8Encoding(true));
            MessageBox.Show(this, "已导出到：\n" + dialog.FileName, "专注统计",
                MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, "导出失败：" + ex.Message, "专注统计",
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void ApplyDwmTheme()
    {
        if (_hwnd == IntPtr.Zero) return;
        int dark = ThemeManager.IsDark ? 1 : 0;
        Native.DwmSetWindowAttribute(_hwnd, Native.DWMWA_USE_IMMERSIVE_DARK_MODE, ref dark, sizeof(int));

        if (TryFindResource("WindowBackdropBrush") is SolidColorBrush backdrop)
        {
            int caption = backdrop.Color.R | (backdrop.Color.G << 8) | (backdrop.Color.B << 16);
            Native.DwmSetWindowAttribute(_hwnd, Native.DWMWA_CAPTION_COLOR, ref caption, sizeof(int));
        }

        int round = Native.DWMWCP_ROUND;
        Native.DwmSetWindowAttribute(_hwnd, Native.DWMWA_WINDOW_CORNER_PREFERENCE, ref round, sizeof(int));
    }
}
