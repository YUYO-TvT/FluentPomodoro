using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace FluentPomodoro.Services;

/// <summary>应用设置与统计（保存到 %APPDATA%\FluentPomodoro\settings.json）</summary>
public sealed class AppSettings
{
    // ---- 计时 ----
    public int FocusMinutes { get; set; } = 25;
    public int ShortBreakMinutes { get; set; } = 5;
    public int LongBreakMinutes { get; set; } = 15;
    public int LongBreakInterval { get; set; } = 4;

    // ---- 行为 ----
    public bool AutoStartNext { get; set; } = true;
    public bool SoundEnabled { get; set; } = true;

    /// <summary>专注进行中阻止系统休眠（睡眠 / 休眠），仅让系统保持运行。</summary>
    public bool PreventSystemSleep { get; set; } = true;

    /// <summary>专注进行中同时保持屏幕常亮（额外点亮显示器）。</summary>
    public bool KeepScreenAwake { get; set; } = true;
    public bool AlwaysOnTop { get; set; } = true;
    public bool NotifyOnPhaseEnd { get; set; } = true;
    public bool FocusLock { get; set; }
    public bool AutoBigScreenOnFocus { get; set; } = true;

    // ---- 外观 ----
    public ThemePreference Theme { get; set; } = ThemePreference.System;
    public bool UseMicaBackdrop { get; set; } = true;

    // ---- 显示 ----
    /// <summary>是否显示当前时间（时钟）。</summary>
    public bool ShowClock { get; set; } = true;

    /// <summary>时钟是否只在专注阶段显示（休息时隐藏）。</summary>
    public bool ClockOnlyDuringFocus { get; set; }

    // ---- 背景图片 ----
    public string BackgroundImagePath { get; set; } = string.Empty;
    public string BackgroundFolder { get; set; } = string.Empty;
    /// <summary>自动轮换间隔（分钟），0 表示不轮换。</summary>
    public int BackgroundRotateMinutes { get; set; }
    /// <summary>每次开始专注时换一张。</summary>
    public bool BackgroundRotateOnFocus { get; set; } = true;
    /// <summary>背景图片不透明度 0.15 ~ 1.0。</summary>
    public double BackgroundOpacity { get; set; } = 0.95;
    /// <summary>用背景图片的主色调作为主题强调色。</summary>
    public bool BackgroundUseImageAccent { get; set; } = true;

    // ---- 白噪音 ----
    public List<string> NoiseTracks { get; set; } = new();
    public int NoiseVolume { get; set; } = 70;
    public bool NoiseAutoPlayOnFocus { get; set; }
    public bool NoiseOnlyDuringFocus { get; set; } = true;
    public bool NoiseShuffle { get; set; } = true;

    // ---- 大屏 ----
    public BigScreenMode BigScreen { get; set; } = BigScreenMode.Mega;
    public bool BigScreenTopmost { get; set; } = true;

    // ---- 窗口位置（窗口模式下记忆） ----
    public bool HasWindowBounds { get; set; }
    public double WindowLeft { get; set; }
    public double WindowTop { get; set; }
    public double WindowWidth { get; set; } = 640;
    public double WindowHeight { get; set; } = 780;

    // ---- 统计 ----
    public string StatsDate { get; set; } = string.Empty;
    public int CompletedToday { get; set; }
    public int FocusMinutesToday { get; set; }
    public int TotalCompleted { get; set; }
    public int StreakDays { get; set; }
    public string LastCompletedDate { get; set; } = string.Empty;

    public TimeSpan DurationFor(PhaseKind phase) => phase switch
    {
        PhaseKind.Focus => TimeSpan.FromMinutes(FocusMinutes),
        PhaseKind.ShortBreak => TimeSpan.FromMinutes(ShortBreakMinutes),
        _ => TimeSpan.FromMinutes(LongBreakMinutes)
    };

    /// <summary>把数值收敛到合法范围，避免手工编辑配置文件导致异常（范围与设置界面滑块一致）。</summary>
    public void Normalize()
    {
        FocusMinutes = Math.Clamp(FocusMinutes, 1, 120);
        ShortBreakMinutes = Math.Clamp(ShortBreakMinutes, 1, 30);
        LongBreakMinutes = Math.Clamp(LongBreakMinutes, 5, 60);
        LongBreakInterval = Math.Clamp(LongBreakInterval, 2, 12);
        if (WindowWidth < 480) WindowWidth = 480;   // 与窗口 MinWidth / MinHeight 保持一致
        if (WindowHeight < 560) WindowHeight = 560;
        BackgroundOpacity = Math.Clamp(BackgroundOpacity, 0.15, 1.0);
        BackgroundRotateMinutes = Math.Clamp(BackgroundRotateMinutes, 0, 1440);
        NoiseVolume = Math.Clamp(NoiseVolume, 0, 100);
        if (NoiseTracks is null) NoiseTracks = new List<string>();
        NoiseTracks = NoiseTracks.Where(p => !string.IsNullOrWhiteSpace(p)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        if (BackgroundImagePath is null) BackgroundImagePath = string.Empty;
        if (BackgroundFolder is null) BackgroundFolder = string.Empty;
        if (!Enum.IsDefined(Theme)) Theme = ThemePreference.System;
        // BigScreen 语义是“大屏偏好方式”，窗口模式不参与记忆
        if (!Enum.IsDefined(BigScreen) || BigScreen == BigScreenMode.None) BigScreen = BigScreenMode.Mega;
        if (CompletedToday < 0) CompletedToday = 0;
        if (FocusMinutesToday < 0) FocusMinutesToday = 0;
        if (TotalCompleted < 0) TotalCompleted = 0;
        if (StreakDays < 0) StreakDays = 0;
    }

    private static string Today => DateTime.Today.ToString("yyyy-MM-dd");

    /// <summary>跨天时把“今日”统计归零。</summary>
    public void RollDaily()
    {
        if (StatsDate != Today)
        {
            StatsDate = Today;
            CompletedToday = 0;
            FocusMinutesToday = 0;
        }
    }

    /// <summary>完成一个专注番茄，更新今日统计与连续天数。</summary>
    public void RecordFocusCompletion()
    {
        RollDaily();
        CompletedToday++;
        FocusMinutesToday += FocusMinutes;
        TotalCompleted++;

        var today = DateTime.Today;
        var last = DateTime.TryParse(LastCompletedDate, out var parsed) ? parsed.Date : DateTime.MinValue;
        if (last != today)
        {
            StreakDays = last == today.AddDays(-1) ? StreakDays + 1 : 1;
            LastCompletedDate = Today;
        }
    }

    public void ResetStatistics()
    {
        StatsDate = Today;
        CompletedToday = 0;
        FocusMinutesToday = 0;
        TotalCompleted = 0;
        StreakDays = 0;
        LastCompletedDate = string.Empty;
    }
}

public static class SettingsStore
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    /// <summary>最近一次保存失败的原因（null 表示成功）。</summary>
    public static string? LastSaveError { get; private set; }

    public static string FolderPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "FluentPomodoro");

    public static string FilePath => Path.Combine(FolderPath, "settings.json");

    /// <summary>
    /// 读取配置。先按正常反序列化；只要出现非法枚举、类型不符等任何问题，
    /// 就退化为逐字段容错读取 —— 坏字段用默认值，其余字段（尤其是统计）全部保留，
    /// 不会因为一个非法值丢掉整份配置。
    /// </summary>
    public static AppSettings Load()
    {
        AppSettings? settings = null;
        string? json = null;

        try
        {
            if (File.Exists(FilePath)) json = File.ReadAllText(FilePath);
        }
        catch
        {
            json = null;
        }

        if (!string.IsNullOrWhiteSpace(json))
        {
            try
            {
                settings = JsonSerializer.Deserialize<AppSettings>(json, Options);
            }
            catch
            {
                settings = null;
            }

            settings ??= ReadTolerant(json);
        }

        settings ??= new AppSettings();
        settings.Normalize();
        settings.RollDaily();
        return settings;
    }

    public static bool Save(AppSettings settings)
    {
        try
        {
            Directory.CreateDirectory(FolderPath);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(settings, Options));
            LastSaveError = null;
            return true;
        }
        catch (Exception ex)
        {
            // 写盘失败（权限、磁盘满等）不阻断计时，但记录下来供界面提示
            LastSaveError = ex.Message;
            return false;
        }
    }

    /// <summary>逐字段容错解析：无法识别的字段忽略，能识别的字段一律保留。</summary>
    private static AppSettings? ReadTolerant(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json, new JsonDocumentOptions
            {
                AllowTrailingCommas = true,
                CommentHandling = JsonCommentHandling.Skip
            });

            if (document.RootElement.ValueKind != JsonValueKind.Object) return null;
            var root = document.RootElement;
            var s = new AppSettings();

            s.FocusMinutes = GetInt(root, nameof(AppSettings.FocusMinutes), s.FocusMinutes);
            s.ShortBreakMinutes = GetInt(root, nameof(AppSettings.ShortBreakMinutes), s.ShortBreakMinutes);
            s.LongBreakMinutes = GetInt(root, nameof(AppSettings.LongBreakMinutes), s.LongBreakMinutes);
            s.LongBreakInterval = GetInt(root, nameof(AppSettings.LongBreakInterval), s.LongBreakInterval);

            s.AutoStartNext = GetBool(root, nameof(AppSettings.AutoStartNext), s.AutoStartNext);
            s.SoundEnabled = GetBool(root, nameof(AppSettings.SoundEnabled), s.SoundEnabled);
            s.KeepScreenAwake = GetBool(root, nameof(AppSettings.KeepScreenAwake), s.KeepScreenAwake);
            s.PreventSystemSleep = GetBool(root, nameof(AppSettings.PreventSystemSleep), s.PreventSystemSleep);
            s.AlwaysOnTop = GetBool(root, nameof(AppSettings.AlwaysOnTop), s.AlwaysOnTop);
            s.NotifyOnPhaseEnd = GetBool(root, nameof(AppSettings.NotifyOnPhaseEnd), s.NotifyOnPhaseEnd);
            s.FocusLock = GetBool(root, nameof(AppSettings.FocusLock), s.FocusLock);
            s.AutoBigScreenOnFocus = GetBool(root, nameof(AppSettings.AutoBigScreenOnFocus), s.AutoBigScreenOnFocus);
            s.BigScreenTopmost = GetBool(root, nameof(AppSettings.BigScreenTopmost), s.BigScreenTopmost);
            s.UseMicaBackdrop = GetBool(root, nameof(AppSettings.UseMicaBackdrop), s.UseMicaBackdrop);

            s.Theme = GetEnum(root, nameof(AppSettings.Theme), s.Theme);
            s.BigScreen = GetEnum(root, nameof(AppSettings.BigScreen), s.BigScreen);
            s.UseMicaBackdrop = GetBool(root, nameof(AppSettings.UseMicaBackdrop), s.UseMicaBackdrop);

            s.ShowClock = GetBool(root, nameof(AppSettings.ShowClock), s.ShowClock);
            s.ClockOnlyDuringFocus = GetBool(root, nameof(AppSettings.ClockOnlyDuringFocus), s.ClockOnlyDuringFocus);

            s.BackgroundImagePath = GetString(root, nameof(AppSettings.BackgroundImagePath), s.BackgroundImagePath);
            s.BackgroundFolder = GetString(root, nameof(AppSettings.BackgroundFolder), s.BackgroundFolder);
            s.BackgroundRotateMinutes = GetInt(root, nameof(AppSettings.BackgroundRotateMinutes), s.BackgroundRotateMinutes);
            s.BackgroundRotateOnFocus = GetBool(root, nameof(AppSettings.BackgroundRotateOnFocus), s.BackgroundRotateOnFocus);
            s.BackgroundOpacity = GetDouble(root, nameof(AppSettings.BackgroundOpacity), s.BackgroundOpacity);
            s.BackgroundUseImageAccent = GetBool(root, nameof(AppSettings.BackgroundUseImageAccent), s.BackgroundUseImageAccent);

            s.NoiseTracks = GetStringList(root, nameof(AppSettings.NoiseTracks), s.NoiseTracks);
            s.NoiseVolume = GetInt(root, nameof(AppSettings.NoiseVolume), s.NoiseVolume);
            s.NoiseAutoPlayOnFocus = GetBool(root, nameof(AppSettings.NoiseAutoPlayOnFocus), s.NoiseAutoPlayOnFocus);
            s.NoiseOnlyDuringFocus = GetBool(root, nameof(AppSettings.NoiseOnlyDuringFocus), s.NoiseOnlyDuringFocus);
            s.NoiseShuffle = GetBool(root, nameof(AppSettings.NoiseShuffle), s.NoiseShuffle);

            s.HasWindowBounds = GetBool(root, nameof(AppSettings.HasWindowBounds), s.HasWindowBounds);
            s.WindowLeft = GetDouble(root, nameof(AppSettings.WindowLeft), s.WindowLeft);
            s.WindowTop = GetDouble(root, nameof(AppSettings.WindowTop), s.WindowTop);
            s.WindowWidth = GetDouble(root, nameof(AppSettings.WindowWidth), s.WindowWidth);
            s.WindowHeight = GetDouble(root, nameof(AppSettings.WindowHeight), s.WindowHeight);

            s.StatsDate = GetString(root, nameof(AppSettings.StatsDate), s.StatsDate);
            s.CompletedToday = GetInt(root, nameof(AppSettings.CompletedToday), s.CompletedToday);
            s.FocusMinutesToday = GetInt(root, nameof(AppSettings.FocusMinutesToday), s.FocusMinutesToday);
            s.TotalCompleted = GetInt(root, nameof(AppSettings.TotalCompleted), s.TotalCompleted);
            s.StreakDays = GetInt(root, nameof(AppSettings.StreakDays), s.StreakDays);
            s.LastCompletedDate = GetString(root, nameof(AppSettings.LastCompletedDate), s.LastCompletedDate);

            return s;
        }
        catch
        {
            return null;
        }
    }

    private static bool TryGet(JsonElement root, string name, out JsonElement value)
    {
        if (root.TryGetProperty(name, out value)) return true;
        // 兼容大小写差异
        foreach (var property in root.EnumerateObject())
        {
            if (string.Equals(property.Name, name, StringComparison.OrdinalIgnoreCase))
            {
                value = property.Value;
                return true;
            }
        }
        value = default;
        return false;
    }

    private static int GetInt(JsonElement root, string name, int fallback)
    {
        if (!TryGet(root, name, out var value)) return fallback;
        if (value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out int number)) return number;
        if (value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out double d)) return (int)Math.Round(d);
        if (value.ValueKind == JsonValueKind.String && int.TryParse(value.GetString(), out int parsed)) return parsed;
        return fallback;
    }

    private static double GetDouble(JsonElement root, string name, double fallback)
    {
        if (!TryGet(root, name, out var value)) return fallback;
        if (value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out double number)) return number;
        if (value.ValueKind == JsonValueKind.String && double.TryParse(value.GetString(), out double parsed)) return parsed;
        return fallback;
    }

    private static bool GetBool(JsonElement root, string name, bool fallback)
    {
        if (!TryGet(root, name, out var value)) return fallback;
        return value.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.Number => value.TryGetDouble(out double d) && Math.Abs(d) > double.Epsilon,
            JsonValueKind.String => ParseBoolText(value.GetString(), fallback),
            _ => fallback
        };
    }

    /// <summary>字符串转布尔：无法识别时回落到字段默认值，而不是一律当作 false。</summary>
    private static bool ParseBoolText(string? text, bool fallback)
    {
        if (string.IsNullOrWhiteSpace(text)) return fallback;
        if (bool.TryParse(text, out bool parsed)) return parsed;
        return text.Trim().ToLowerInvariant() switch
        {
            "1" or "yes" or "y" or "on" => true,
            "0" or "no" or "n" or "off" => false,
            _ => fallback
        };
    }

    private static string GetString(JsonElement root, string name, string fallback)
    {
        if (!TryGet(root, name, out var value)) return fallback;
        if (value.ValueKind == JsonValueKind.String) return value.GetString() ?? fallback;
        return fallback;
    }

    private static List<string> GetStringList(JsonElement root, string name, List<string> fallback)
    {
        if (!TryGet(root, name, out var value)) return fallback;
        if (value.ValueKind != JsonValueKind.Array) return fallback;
        var list = new List<string>();
        foreach (var item in value.EnumerateArray())
        {
            if (item.ValueKind == JsonValueKind.String && item.GetString() is { Length: > 0 } text) list.Add(text);
        }
        return list;
    }

    private static TEnum GetEnum<TEnum>(JsonElement root, string name, TEnum fallback) where TEnum : struct, Enum
    {
        if (!TryGet(root, name, out var value)) return fallback;
        if (value.ValueKind == JsonValueKind.String &&
            Enum.TryParse(value.GetString(), ignoreCase: true, out TEnum parsed) &&
            Enum.IsDefined(parsed))
        {
            return parsed;
        }
        if (value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out int number) &&
            Enum.IsDefined(typeof(TEnum), number))
        {
            return (TEnum)Enum.ToObject(typeof(TEnum), number);
        }
        return fallback;
    }
}
