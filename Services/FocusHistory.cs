using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace FluentPomodoro.Services;

/// <summary>某一天的专注统计</summary>
public sealed class DayStat
{
    public int Minutes { get; set; }
    public int Pomodoros { get; set; }
}

/// <summary>
/// 每日专注历史，保存到 %APPDATA%\FluentPomodoro\history.json。
/// 用于统计窗口的 GitHub 式绿点矩阵。
/// </summary>
public sealed class FocusHistory
{
    public Dictionary<string, DayStat> Days { get; set; } = new();

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public static string FolderPath => SettingsStore.FolderPath;

    public static string FilePath => Path.Combine(FolderPath, "history.json");

    private static string Key(DateTime day) => day.ToString("yyyy-MM-dd");

    public static FocusHistory Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var json = File.ReadAllText(FilePath);
                var history = JsonSerializer.Deserialize<FocusHistory>(json, Options);
                if (history?.Days is not null)
                {
                    history.Prune();
                    return history;
                }
            }
        }
        catch
        {
            // 损坏时退化为逐条容错读取
        }

        try
        {
            if (!File.Exists(FilePath)) return new FocusHistory();
            using var document = JsonDocument.Parse(File.ReadAllText(FilePath));
            var history = new FocusHistory();
            foreach (var property in document.RootElement.EnumerateObject())
            {
                if (!DateTime.TryParse(property.Name, out var day)) continue;
                if (property.Value.ValueKind != JsonValueKind.Object) continue;

                int minutes = 0, pomodoros = 0;
                if (property.Value.TryGetProperty("Minutes", out var m))
                {
                    if (m.ValueKind == JsonValueKind.Number && m.TryGetInt32(out int mv)) minutes = mv;
                    else if (m.ValueKind == JsonValueKind.String && int.TryParse(m.GetString(), out int ms)) minutes = ms;
                }
                if (property.Value.TryGetProperty("Pomodoros", out var p))
                {
                    if (p.ValueKind == JsonValueKind.Number && p.TryGetInt32(out int pv)) pomodoros = pv;
                    else if (p.ValueKind == JsonValueKind.String && int.TryParse(p.GetString(), out int ps)) pomodoros = ps;
                }
                history.Days[Key(day)] = new DayStat { Minutes = Math.Max(0, minutes), Pomodoros = Math.Max(0, pomodoros) };
            }
            return history;
        }
        catch
        {
            return new FocusHistory();
        }
    }

    public bool Save()
    {
        try
        {
            Directory.CreateDirectory(FolderPath);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, Options));
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>记录一次完成的专注。</summary>
    public void Add(DateTime day, int minutes, int pomodoros = 1)
    {
        var key = Key(day);
        if (!Days.TryGetValue(key, out var stat))
        {
            stat = new DayStat();
            Days[key] = stat;
        }
        stat.Minutes += Math.Max(0, minutes);
        stat.Pomodoros += Math.Max(0, pomodoros);
    }

    public int MinutesOn(DateTime day) => Days.TryGetValue(Key(day), out var s) ? s.Minutes : 0;

    public int PomodorosOn(DateTime day) => Days.TryGetValue(Key(day), out var s) ? s.Pomodoros : 0;

    public int MinutesBetween(DateTime from, DateTime to)
    {
        int sum = 0;
        for (var day = from.Date; day <= to.Date; day = day.AddDays(1)) sum += MinutesOn(day);
        return sum;
    }

    public int PomodorosBetween(DateTime from, DateTime to)
    {
        int sum = 0;
        for (var day = from.Date; day <= to.Date; day = day.AddDays(1)) sum += PomodorosOn(day);
        return sum;
    }

    public int TotalMinutes => Days.Values.Sum(d => d.Minutes);

    public int TotalPomodoros => Days.Values.Sum(d => d.Pomodoros);

    /// <summary>当前连续专注天数（今天没有则从昨天往前数）。</summary>
    public int CurrentStreak
    {
        get
        {
            var day = DateTime.Today;
            if (MinutesOn(day) == 0) day = day.AddDays(-1);
            int streak = 0;
            while (MinutesOn(day) > 0)
            {
                streak++;
                day = day.AddDays(-1);
            }
            return streak;
        }
    }

    /// <summary>历史最佳一天。</summary>
    public (DateTime Day, int Minutes) BestDay()
    {
        DateTime bestDay = default;
        int best = 0;
        foreach (var pair in Days)
        {
            if (pair.Value.Minutes <= best) continue;
            if (!DateTime.TryParse(pair.Key, out var day)) continue;
            best = pair.Value.Minutes;
            bestDay = day;
        }
        return (bestDay, best);
    }

    /// <summary>从 start 到 end 的每日分钟数视图（含 0）。</summary>
    public Dictionary<DateTime, int> DailyMinutes(DateTime start, DateTime end)
    {
        var map = new Dictionary<DateTime, int>();
        for (var day = start.Date; day <= end.Date; day = day.AddDays(1)) map[day] = MinutesOn(day);
        return map;
    }

    private void Prune()
    {
        // 去掉无法解析的键，防止脏数据污染统计
        foreach (var key in Days.Keys.Where(k => !DateTime.TryParse(k, out _)).ToList()) Days.Remove(key);
    }
}
