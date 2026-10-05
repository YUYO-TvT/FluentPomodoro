using System.Windows;
using System.Windows.Media;

namespace FluentPomodoro.Controls;

/// <summary>
/// Fluent 风格的圆环进度控件：底环 + 圆头强调色圆弧（可带柔光），
/// 纯 <see cref="OnRender"/> 绘制，任意尺寸下都不失真，适合大屏放大显示。
/// </summary>
public sealed class ProgressRing : FrameworkElement
{
    public static readonly DependencyProperty ProgressProperty = DependencyProperty.Register(
        nameof(Progress), typeof(double), typeof(ProgressRing),
        new FrameworkPropertyMetadata(0d, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty TrackBrushProperty = DependencyProperty.Register(
        nameof(TrackBrush), typeof(Brush), typeof(ProgressRing),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty IndicatorBrushProperty = DependencyProperty.Register(
        nameof(IndicatorBrush), typeof(Brush), typeof(ProgressRing),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty GlowBrushProperty = DependencyProperty.Register(
        nameof(GlowBrush), typeof(Brush), typeof(ProgressRing),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty RingThicknessProperty = DependencyProperty.Register(
        nameof(RingThickness), typeof(double), typeof(ProgressRing),
        new FrameworkPropertyMetadata(14d, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty StartAngleProperty = DependencyProperty.Register(
        nameof(StartAngle), typeof(double), typeof(ProgressRing),
        new FrameworkPropertyMetadata(-90d, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty ShowTrackProperty = DependencyProperty.Register(
        nameof(ShowTrack), typeof(bool), typeof(ProgressRing),
        new FrameworkPropertyMetadata(true, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty ShowGlowProperty = DependencyProperty.Register(
        nameof(ShowGlow), typeof(bool), typeof(ProgressRing),
        new FrameworkPropertyMetadata(true, FrameworkPropertyMetadataOptions.AffectsRender));

    /// <summary>0 ~ 1</summary>
    public double Progress
    {
        get => (double)GetValue(ProgressProperty);
        set => SetValue(ProgressProperty, value);
    }

    public Brush? TrackBrush
    {
        get => (Brush?)GetValue(TrackBrushProperty);
        set => SetValue(TrackBrushProperty, value);
    }

    public Brush? IndicatorBrush
    {
        get => (Brush?)GetValue(IndicatorBrushProperty);
        set => SetValue(IndicatorBrushProperty, value);
    }

    public Brush? GlowBrush
    {
        get => (Brush?)GetValue(GlowBrushProperty);
        set => SetValue(GlowBrushProperty, value);
    }

    public double RingThickness
    {
        get => (double)GetValue(RingThicknessProperty);
        set => SetValue(RingThicknessProperty, value);
    }

    public double StartAngle
    {
        get => (double)GetValue(StartAngleProperty);
        set => SetValue(StartAngleProperty, value);
    }

    public bool ShowTrack
    {
        get => (bool)GetValue(ShowTrackProperty);
        set => SetValue(ShowTrackProperty, value);
    }

    public bool ShowGlow
    {
        get => (bool)GetValue(ShowGlowProperty);
        set => SetValue(ShowGlowProperty, value);
    }

    protected override void OnRender(DrawingContext dc)
    {
        double w = RenderSize.Width;
        double h = RenderSize.Height;
        if (w <= 2 || h <= 2) return;

        double thickness = Math.Max(2, RingThickness);
        double radius = Math.Min(w, h) / 2.0 - thickness / 2.0 - 2.0;
        if (radius <= 0) return;

        var center = new Point(w / 2.0, h / 2.0);
        dc.DrawEllipse(null, new Pen(Brushes.Transparent, 0), center, radius, radius);

        if (ShowTrack && TrackBrush is { } track)
            dc.DrawEllipse(null, new Pen(track, thickness), center, radius, radius);

        double progress = Math.Clamp(Progress, 0d, 1d);
        if (progress <= 0.0001 || IndicatorBrush is null) return;

        if (progress >= 0.9999)
        {
            if (ShowGlow && GlowBrush is { } glowFull)
                dc.DrawEllipse(null, new Pen(glowFull, thickness * 1.9), center, radius, radius);
            dc.DrawEllipse(null, new Pen(IndicatorBrush, thickness), center, radius, radius);
            return;
        }

        double sweep = progress * 360.0;
        var start = PointOnCircle(center, radius, StartAngle);
        var end = PointOnCircle(center, radius, StartAngle + sweep);

        var geometry = new StreamGeometry();
        using (var ctx = geometry.Open())
        {
            ctx.BeginFigure(start, false, false);
            ctx.ArcTo(end, new Size(radius, radius), 0.0,
                sweep > 180.0, SweepDirection.Clockwise, true, false);
        }
        geometry.Freeze();

        if (ShowGlow && GlowBrush is { } glow)
        {
            var glowPen = new Pen(glow, thickness * 1.9)
            {
                StartLineCap = PenLineCap.Round,
                EndLineCap = PenLineCap.Round
            };
            glowPen.Freeze();
            dc.DrawGeometry(null, glowPen, geometry);
        }

        var pen = new Pen(IndicatorBrush, thickness)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        pen.Freeze();
        dc.DrawGeometry(null, pen, geometry);
    }

    private static Point PointOnCircle(Point center, double radius, double angleDegrees)
    {
        double rad = angleDegrees * Math.PI / 180.0;
        return new Point(center.X + radius * Math.Cos(rad), center.Y + radius * Math.Sin(rad));
    }
}
