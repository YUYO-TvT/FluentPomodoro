using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace FluentPomodoro.Services;

/// <summary>
/// 背景图片：支持单张图片或整个文件夹，可随机轮换，并能从图片中提取主色调作为主题强调色。
/// </summary>
public sealed class BackgroundService
{
    private static readonly string[] SupportedExtensions =
    {
        ".jpg", ".jpeg", ".png", ".bmp", ".gif", ".tif", ".tiff", ".jfif"
    };

    private readonly List<string> _images = new();
    private readonly Random _random = new();

    public string? CurrentPath { get; private set; }

    public BitmapSource? CurrentImage { get; private set; }

    public Color? CurrentAccent { get; private set; }

    public bool HasImages => _images.Count > 0;

    public int ImageCount => _images.Count;

    public event EventHandler? Changed;

    public static bool IsSupported(string path) =>
        SupportedExtensions.Contains(Path.GetExtension(path).ToLowerInvariant());

    public void SetSingle(string path)
    {
        _images.Clear();
        if (!string.IsNullOrWhiteSpace(path) && File.Exists(path)) _images.Add(path);
        Load(0);
    }

    public void SetFolder(string folder)
    {
        _images.Clear();
        try
        {
            if (!string.IsNullOrWhiteSpace(folder) && Directory.Exists(folder))
            {
                foreach (var file in Directory.EnumerateFiles(folder)
                             .Where(IsSupported)
                             .OrderBy(f => f, StringComparer.OrdinalIgnoreCase)
                             .Take(1000))
                {
                    _images.Add(file);
                }
            }
        }
        catch
        {
            // 目录不可读时按空处理
        }
        Load(0);
    }

    public void Clear()
    {
        _images.Clear();
        CurrentPath = null;
        CurrentImage = null;
        CurrentAccent = null;
        Changed?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>切换到下一张（多张时随机挑选，避免连续重复）。</summary>
    public bool Next()
    {
        if (_images.Count == 0) return false;

        int index;
        if (_images.Count == 1)
        {
            index = 0;
        }
        else
        {
            do
            {
                index = _random.Next(_images.Count);
            } while (_images[index] == CurrentPath);
        }

        return Load(index);
    }

    private bool Load(int index)
    {
        if (index < 0 || index >= _images.Count)
        {
            CurrentPath = null;
            CurrentImage = null;
            CurrentAccent = null;
            Changed?.Invoke(this, EventArgs.Empty);
            return false;
        }

        var path = _images[index];
        try
        {
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.UriSource = new Uri(path, UriKind.Absolute);
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.CreateOptions = BitmapCreateOptions.IgnoreColorProfile;
            // 限制解码尺寸，避免 4K/8K 图片占用过多内存
            bitmap.DecodePixelWidth = 1920;
            bitmap.EndInit();
            bitmap.Freeze();

            CurrentPath = path;
            CurrentImage = bitmap;
            CurrentAccent = ExtractAccent(bitmap, ThemeManager.IsDark);
            Changed?.Invoke(this, EventArgs.Empty);
            return true;
        }
        catch
        {
            // 图片损坏或格式不支持：移除并尝试下一张
            _images.RemoveAt(index);
            return _images.Count > 0 && Load(0);
        }
    }

    /// <summary>
    /// 从图片中提取一个适合做强调色的主色调：按饱和度平方加权做色相向量平均，
    /// 忽略近灰度像素，最后按主题调整明度/饱和度。
    /// </summary>
    public static Color? ExtractAccent(BitmapSource source, bool dark)
    {
        try
        {
            int target = 32;
            double scale = Math.Min(1.0, (double)target / Math.Max(1, Math.Max(source.PixelWidth, source.PixelHeight)));
            BitmapSource scaled = source;
            if (scale < 1.0)
            {
                scaled = new TransformedBitmap(source, new ScaleTransform(scale, scale));
            }

            var converted = new FormatConvertedBitmap(scaled, PixelFormats.Bgra32, null, 0);
            int width = converted.PixelWidth;
            int height = converted.PixelHeight;
            if (width <= 0 || height <= 0) return null;

            int stride = width * 4;
            var pixels = new byte[stride * height];
            converted.CopyPixels(pixels, stride, 0);

            double sumSin = 0, sumCos = 0, weightSum = 0;
            for (int i = 0; i + 3 < pixels.Length; i += 4)
            {
                if (pixels[i + 3] < 128) continue;

                double b = pixels[i] / 255.0;
                double g = pixels[i + 1] / 255.0;
                double r = pixels[i + 2] / 255.0;

                double max = Math.Max(r, Math.Max(g, b));
                double min = Math.Min(r, Math.Min(g, b));
                double delta = max - min;
                if (max <= 0.02 || delta <= 0.02) continue;

                double saturation = delta / max;
                double value = max;
                if (saturation < 0.15) continue;

                double hue;
                if (max == r) hue = 60 * (((g - b) / delta) % 6);
                else if (max == g) hue = 60 * ((b - r) / delta + 2);
                else hue = 60 * ((r - g) / delta + 4);
                if (hue < 0) hue += 360;

                double rad = hue * Math.PI / 180.0;
                double weight = saturation * saturation * (value < 0.95 ? 1.0 : 0.35);
                sumSin += Math.Sin(rad) * weight;
                sumCos += Math.Cos(rad) * weight;
                weightSum += weight;
            }

            if (weightSum <= 0.0001) return null;

            double angle = Math.Atan2(sumSin, sumCos) * 180.0 / Math.PI;
            if (angle < 0) angle += 360;

            // 强调色需要在浅色/深色主题下都清晰可读
            double outSaturation = dark ? 0.60 : 0.68;
            double outValue = dark ? 0.88 : 0.68;
            return FromHsv(angle, outSaturation, outValue);
        }
        catch
        {
            return null;
        }
    }

    private static Color FromHsv(double hue, double saturation, double value)
    {
        double c = value * saturation;
        double x = c * (1 - Math.Abs((hue / 60.0) % 2 - 1));
        double m = value - c;

        (double r, double g, double b) = hue switch
        {
            < 60 => (c, x, 0.0),
            < 120 => (x, c, 0.0),
            < 180 => (0.0, c, x),
            < 240 => (0.0, x, c),
            < 300 => (x, 0.0, c),
            _ => (c, 0.0, x)
        };

        return Color.FromRgb(
            (byte)Math.Round((r + m) * 255),
            (byte)Math.Round((g + m) * 255),
            (byte)Math.Round((b + m) * 255));
    }
}
