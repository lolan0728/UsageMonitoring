using System.Windows;
using System.Windows.Media;

namespace UsageMonitoring.App.Controls;

public sealed class QuotaRing : FrameworkElement
{
    public static readonly DependencyProperty PercentageProperty =
        DependencyProperty.Register(
            nameof(Percentage),
            typeof(double),
            typeof(QuotaRing),
            new FrameworkPropertyMetadata(0d, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty RingBrushProperty =
        DependencyProperty.Register(
            nameof(RingBrush),
            typeof(Brush),
            typeof(QuotaRing),
            new FrameworkPropertyMetadata(Brushes.LimeGreen, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty TrackBrushProperty =
        DependencyProperty.Register(
            nameof(TrackBrush),
            typeof(Brush),
            typeof(QuotaRing),
            new FrameworkPropertyMetadata(new SolidColorBrush(Color.FromArgb(70, 255, 255, 255)), FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty ThicknessProperty =
        DependencyProperty.Register(
            nameof(Thickness),
            typeof(double),
            typeof(QuotaRing),
            new FrameworkPropertyMetadata(7d, FrameworkPropertyMetadataOptions.AffectsRender));

    public double Percentage
    {
        get => (double)GetValue(PercentageProperty);
        set => SetValue(PercentageProperty, value);
    }

    public Brush RingBrush
    {
        get => (Brush)GetValue(RingBrushProperty);
        set => SetValue(RingBrushProperty, value);
    }

    public Brush TrackBrush
    {
        get => (Brush)GetValue(TrackBrushProperty);
        set => SetValue(TrackBrushProperty, value);
    }

    public double Thickness
    {
        get => (double)GetValue(ThicknessProperty);
        set => SetValue(ThicknessProperty, value);
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);

        var size = Math.Min(ActualWidth, ActualHeight);
        if (size <= 0)
        {
            return;
        }

        var thickness = Math.Max(2, Thickness);
        var glowThickness = thickness + 5;
        var maxStroke = Math.Max(thickness, glowThickness);
        var radius = Math.Max(0, ((size - maxStroke) / 2) - 1);
        var center = new Point(ActualWidth / 2, ActualHeight / 2);
        var startAngle = -90d;
        var sweep = Math.Clamp(Percentage, 0, 100) / 100d * 359.999d;

        var trackPen = new Pen(TrackBrush, thickness)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        drawingContext.DrawEllipse(null, trackPen, center, radius, radius);

        if (sweep <= 0.01)
        {
            return;
        }

        var ringPen = new Pen(RingBrush, thickness)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };

        var geometry = new StreamGeometry();
        using (var context = geometry.Open())
        {
            var start = PointOnCircle(center, radius, startAngle);
            var end = PointOnCircle(center, radius, startAngle + sweep);
            context.BeginFigure(start, isFilled: false, isClosed: false);
            context.ArcTo(
                end,
                new Size(radius, radius),
                rotationAngle: 0,
                isLargeArc: sweep > 180,
                sweepDirection: SweepDirection.Clockwise,
                isStroked: true,
                isSmoothJoin: true);
        }

        geometry.Freeze();
        if (RingBrush is SolidColorBrush solidBrush)
        {
            var glowBrush = new SolidColorBrush(Color.FromArgb(95, solidBrush.Color.R, solidBrush.Color.G, solidBrush.Color.B));
            glowBrush.Freeze();
            var glowPen = new Pen(glowBrush, glowThickness)
            {
                StartLineCap = PenLineCap.Round,
                EndLineCap = PenLineCap.Round
            };
            drawingContext.DrawGeometry(null, glowPen, geometry);
        }

        drawingContext.DrawGeometry(null, ringPen, geometry);
    }

    private static Point PointOnCircle(Point center, double radius, double angleDegrees)
    {
        var radians = angleDegrees * Math.PI / 180d;
        return new Point(
            center.X + radius * Math.Cos(radians),
            center.Y + radius * Math.Sin(radians));
    }
}
