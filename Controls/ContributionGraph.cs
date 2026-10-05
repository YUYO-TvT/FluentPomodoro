using System.Globalization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;

namespace FluentPomodoro.Controls;

public sealed class ContributionDayEventArgs : EventArgs
{
    public ContributionDayEventArgs(DateTime day, int minutes)
    {
        Day = day;
        Minutes = minutes;
    }

    public DateTime Day { get; }

    public int Minutes { get; }
}

/// <summary>
/// GitHub 贡献图风格的「每日专注时间」绿点矩阵。
/// 一周一列（周一到周日），共 <see cref="Weeks"/> 列；当天专注越久，格子颜色越深。
/// </summary>
public sealed class ContributionGraph : FrameworkElement
{
    public const int Weeks = 53;

    public static readonly DependencyProperty DailyMinutesProperty = DependencyProperty.Register(
        nameof(DailyMinutes), typeof(IDictionary<DateTime, int>), typeof(ContributionGraph),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsMeasure | FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty CellSizeProperty = DependencyProperty.Register(
        nameof(CellSize), typeof(double), typeof(ContributionGraph),
        new FrameworkPropertyMetadata(13.0, FrameworkPropertyMetadataOptions.AffectsMeasure | FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty CellGapProperty = DependencyProperty.Register(
        nameof(CellGap), typeof(double), typeof(ContributionGraph),
        new FrameworkPropertyMetadata(3.0, FrameworkPropertyMetadataOptions.AffectsMeasure | FrameworkPropertyMetadataOptions.AffectsRender));

    /// <summary>结束日期，默认今天。</summary>
    public static readonly DependencyProperty EndDateProperty = DependencyProperty.Register(
        nameof(EndDate), typeof(DateTime), typeof(ContributionGraph),
        new FrameworkPropertyMetadata(DateTime.Today, FrameworkPropertyMetadataOptions.AffectsMeasure | FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty HoverKeyProperty = DependencyProperty.Register(
        nameof(HoverKey), typeof(string), typeof(ContributionGraph),
        new FrameworkPropertyMetadata(string.Empty, FrameworkPropertyMetadataOptions.AffectsRender));

    public IDictionary<DateTime, int>? DailyMinutes
    {
        get => (IDictionary<DateTime, int>?)GetValue(DailyMinutesProperty);
        set => SetValue(DailyMinutesProperty, value);
    }

    public double CellSize
    {
        get => (double)GetValue(CellSizeProperty);
        set => SetValue(CellSizeProperty, value);
    }

    public double CellGap
    {
        get => (double)GetValue(CellGapProperty);
        set => SetValue(CellGapProperty, value);
    }

    public DateTime EndDate
    {
        get => (DateTime)GetValue(EndDateProperty);
        set => SetValue(EndDateProperty, value);
    }

    public string HoverKey
    {
        get => (string)GetValue(HoverKeyProperty);
        set => SetValue(HoverKeyProperty, value);
    }

    /// <summary>鼠标移到某个格子上（分钟数随事件返回）。</summary>
    public event EventHandler<ContributionDayEventArgs>? DayHovered;

    /// <summary>鼠标离开矩阵。</summary>
    public event EventHandler? DayUnhovered;

    private const double WeekdayLabelWidth = 30;
    private const double MonthLabelHeight = 20;

    /// <summary>当日专注分钟数 → 等级（0 无记录，1~5 越深表示越久）。</summary>
    public static int LevelFor(int minutes) => minutes switch
    {
        <= 0 => 0,
        < 25 => 1,
        < 50 => 2,
        < 100 => 3,
        < 200 => 4,
        _ => 5
    };

    public static string LevelDescription(int level) => level switch
    {
        1 => "少于 25 分钟",
        2 => "25 – 49 分钟",
        3 => "50 – 99 分钟",
        4 => "100 – 199 分钟",
        _ => "200 分钟以上"
    };

    private DateTime GridStart
    {
        get
        {
            var end = EndDate.Date;
            // 本周一
            var thisMonday = end.AddDays(-(((int)end.DayOfWeek + 6) % 7));
            return thisMonday.AddDays(-7 * (Weeks - 1));
        }
    }

    protected override Size MeasureOverride(Size availableSize)
    {
        double step = CellSize + CellGap;
        return new Size(WeekdayLabelWidth + Weeks * step - CellGap, MonthLabelHeight + 7 * step - CellGap);
    }

    protected override void OnRender(DrawingContext dc)
    {
        double step = CellSize + CellGap;
        var start = GridStart;
        var map = DailyMinutes;
        double dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;

        var labelBrush = TryFindResource("TextTertiaryBrush") as Brush ?? Brushes.Gray;
        var todayBrush = TryFindResource("AccentBrush") as Brush ?? Brushes.DodgerBlue;
        var typeface = new Typeface(
            (FontFamily)(TryFindResource("AppFontFamily") ?? new FontFamily("Segoe UI")),
            FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);

        // 星期标签（周一 / 周三 / 周五）
        for (int row = 0; row < 7; row += 2)
        {
            string text = row switch { 0 => "一", 2 => "三", 4 => "五", _ => "日" };
            var formatted = new FormattedText(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
                typeface, 11, labelBrush, dpi);
            dc.DrawText(formatted, new Point(WeekdayLabelWidth - 8 - formatted.Width, MonthLabelHeight + row * step + 1));
        }

        int lastMonth = -1;
        double lastLabelRight = double.NegativeInfinity;
        for (int week = 0; week < Weeks; week++)
        {
            var weekStart = start.AddDays(week * 7);
            if (weekStart.Month != lastMonth)
            {
                lastMonth = weekStart.Month;
                var monthText = new FormattedText($"{weekStart.Month}月", CultureInfo.CurrentUICulture,
                    FlowDirection.LeftToRight, typeface, 11, labelBrush, dpi);
                double x = WeekdayLabelWidth + week * step;
                // 与上一个月份标签保持间距，避免相邻月份文字重叠
                if (x > lastLabelRight + 8 && x + monthText.Width <= WeekdayLabelWidth + Weeks * step)
                {
                    dc.DrawText(monthText, new Point(x, 0));
                    lastLabelRight = x + monthText.Width;
                }
            }

            for (int row = 0; row < 7; row++)
            {
                var day = weekStart.AddDays(row);
                if (day > EndDate.Date) continue;

                int minutes = 0;
                map?.TryGetValue(day, out minutes);
                int level = LevelFor(minutes);
                var brush = TryFindResource($"Heat{level}Brush") as Brush ?? Brushes.LightGray;

                double x = WeekdayLabelWidth + week * step;
                double y = MonthLabelHeight + row * step;
                var rect = new Rect(x, y, CellSize, CellSize);
                dc.DrawRoundedRectangle(brush, null, rect, 2.5, 2.5);

                bool hovered = !string.IsNullOrEmpty(HoverKey) && HoverKey == KeyOf(day);
                if (hovered)
                {
                    var pen = new Pen(todayBrush, 1.6);
                    dc.DrawRoundedRectangle(null, pen, rect, 2.5, 2.5);
                }
                else if (day == EndDate.Date)
                {
                    var pen = new Pen(todayBrush, 1.2);
                    dc.DrawRoundedRectangle(null, pen, rect, 2.5, 2.5);
                }
            }
        }
    }

    private static string KeyOf(DateTime day) => day.ToString("yyyy-MM-dd");

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);

        var point = e.GetPosition(this);
        double step = CellSize + CellGap;
        int week = (int)Math.Floor((point.X - WeekdayLabelWidth) / step);
        int row = (int)Math.Floor((point.Y - MonthLabelHeight) / step);

        if (week < 0 || week >= Weeks || row < 0 || row >= 7)
        {
            ClearHover();
            return;
        }

        var day = GridStart.AddDays(week * 7 + row);
        if (day > EndDate.Date)
        {
            ClearHover();
            return;
        }

        int minutes = 0;
        DailyMinutes?.TryGetValue(day, out minutes);
        HoverKey = KeyOf(day);
        DayHovered?.Invoke(this, new ContributionDayEventArgs(day, minutes));
    }

    protected override void OnMouseLeave(MouseEventArgs e)
    {
        base.OnMouseLeave(e);
        ClearHover();
    }

    private void ClearHover()
    {
        if (string.IsNullOrEmpty(HoverKey)) return;
        HoverKey = string.Empty;
        DayUnhovered?.Invoke(this, EventArgs.Empty);
    }
}
