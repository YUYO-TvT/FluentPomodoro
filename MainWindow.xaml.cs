using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Shell;
using System.Windows.Threading;
using FluentPomodoro.Interop;
using FluentPomodoro.Services;
using Microsoft.Win32;

namespace FluentPomodoro;

public partial class MainWindow : Window
{
    private readonly AppSettings _settings;

    private readonly DispatcherTimer _tickTimer = new() { Interval = TimeSpan.FromMilliseconds(200) };
    private readonly DispatcherTimer _toastTimer = new() { Interval = TimeSpan.FromSeconds(2.4) };
    private readonly DispatcherTimer _idleTimer = new() { Interval = TimeSpan.FromSeconds(3.5) };
    private readonly DispatcherTimer _themeWatchTimer = new() { Interval = TimeSpan.FromSeconds(4) };
    private readonly DispatcherTimer _clockTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly DispatcherTimer _backgroundTimer = new() { Interval = TimeSpan.FromSeconds(20) };

    private readonly List<Ellipse> _dots = new();
    private readonly ObservableCollection<string> _noiseTracks = new();
    private readonly BackgroundService _background = new();
    private readonly NoisePlayer _noise = new();
    private FocusHistory _history = new();

    private StatsWindow? _statsWindow;
    private TimeSpan _backgroundElapsed;

    // ---- 计时状态 ----
    private PhaseKind _phase = PhaseKind.Focus;
    private int _roundInCycle = 1;
    private TimeSpan _remaining;
    private TimeSpan _deadline;          // 相对单调时钟（Stopwatch）的截止点
    private bool _running;

    /// <summary>单调时钟：不受系统时间调整/校时影响，长时间计时不跳变。</summary>
    private static readonly Stopwatch Clock = Stopwatch.StartNew();

    // ---- 界面状态 ----
    private bool _ready;
    private bool _suspendSettingsWrite;
    private bool _forceExit;
    private bool _suppressModeEvents;
    private bool _chromeShown = true;
    private bool _settingsOpen;
    private bool _focusOverrideActive;
    private int _originalFocusMinutes;
    private int _overrideFocusMinutes;
    private bool _themeOverrideActive;
    private ThemePreference _originalTheme;
    private bool _saveErrorReported;
    private bool _sleepInterrupted;
    private EventHandler? _themeChangedHandler;

    // ---- 大屏状态 ----
    private BigScreenMode _bigScreen = BigScreenMode.None;
    private Rect _windowedBounds;
    private bool _hasWindowedBounds;
    private Rect _enforcedRectPx;
    private bool _enforceBounds;
    private bool _reapplyScheduled;
    private IntPtr _hwnd;
    private bool _micaActive;

    public MainWindow()
    {
        _settings = SettingsStore.Load();
        _history = FocusHistory.Load();

        // 主题优先级：命令行 > 配置文件 > 跟随系统（必须在创建界面之前生效）
        // 命令行强制主题属于「仅本次会话」的覆盖，退出时不会写回配置文件；
        // 用户在设置面板里自己选主题时会解除该覆盖（见 OnThemeSelectionChanged）。
        if (App.Options.ForceLightDark is { } cliTheme)
        {
            _originalTheme = _settings.Theme;
            _themeOverrideActive = true;
            _settings.Theme = cliTheme;
            ThemeManager.SetPreference(cliTheme);
        }
        else
        {
            _originalTheme = _settings.Theme;
            ThemeManager.SetPreference(_settings.Theme);
        }

        // 命令行可临时覆盖本次专注时长：--focus 5（仅本次会话，不写回配置文件）
        if (App.Options.FocusMinutes is { } minutes)
        {
            _originalFocusMinutes = _settings.FocusMinutes;
            _settings.FocusMinutes = minutes;
            _overrideFocusMinutes = minutes;
            _focusOverrideActive = true;
        }

        InitializeComponent();
        _ready = true;

        // 本程序没有任何文本输入，直接关闭输入法，避免中文 IME 吞掉 R/S/F 等裸字母快捷键
        InputMethod.SetIsInputMethodEnabled(this, false);

        Title = "微软风格番茄钟";
        TxtVersion.Text = $"Fluent Pomodoro · 版本 {Assembly.GetExecutingAssembly().GetName().Version?.ToString(3)} · " +
                          $"{RuntimeInformation.FrameworkDescription} · 单文件自包含 EXE";

        HookTimers();
        ChimePlayer.Prepare();
        InitializeBackground();
        InitializeNoise();
        ApplySettingsToUi();
        ResetPhaseTimers();
        UpdatePhaseVisuals();
        UpdateUi();
        UpdateClock();
        _clockTimer.Start();
        _backgroundTimer.Start();
    }

    // ==================================================================
    //  初始化
    // ==================================================================

    private void HookTimers()
    {
        _tickTimer.Tick += (_, _) => OnTick();
        _toastTimer.Tick += (_, _) =>
        {
            _toastTimer.Stop();
            HideToast();
        };
        _idleTimer.Tick += (_, _) =>
        {
            _idleTimer.Stop();
            if (_bigScreen != BigScreenMode.None && _running) SetChromeVisible(false);
        };
        _themeWatchTimer.Tick += OnThemeWatch;
        _themeWatchTimer.Start();

        _clockTimer.Tick += (_, _) => UpdateClock();
        _backgroundTimer.Tick += OnBackgroundTimerTick;

        _themeChangedHandler = (_, _) =>
        {
            ApplyBackdrop();
            ApplyDwmTheme();
            ApplyImageAccent();
            UpdatePhaseVisuals();
            UpdateUi();
        };
        ThemeManager.ThemeChanged += _themeChangedHandler;
    }

    protected override void OnClosed(EventArgs e)
    {
        // 解除静态事件订阅，避免窗口对象无法回收
        if (_themeChangedHandler is not null) ThemeManager.ThemeChanged -= _themeChangedHandler;
        _themeWatchTimer.Stop();
        _clockTimer.Stop();
        _backgroundTimer.Stop();
        _statsWindow?.Close();
        _noise.Dispose();
        ChimePlayer.Release();
        base.OnClosed(e);
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);

        _hwnd = new WindowInteropHelper(this).Handle;
        HwndSource.FromHwnd(_hwnd)?.AddHook(WndProc);

        RestoreWindowBounds();
        ApplyBackdrop();
        ApplyDwmTheme();
        SetDwmCorners(true);

        Topmost = _settings.AlwaysOnTop;
        UpdateModeChips();
        UpdateScreenInfo();

        if (App.Options.StartBigScreen)
        {
            var mode = App.Options.ForceMega ? BigScreenMode.Mega : _settings.BigScreen;
            Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() => SetBigScreen(mode)));
        }

        // 与 --bigscreen / --mega 可以同时使用（两者互不排斥）
        if (App.Options.AutoStartTimer)
        {
            Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(StartTimer));
        }
    }

    protected override void OnDpiChanged(DpiScale oldDpi, DpiScale newDpi)
    {
        base.OnDpiChanged(oldDpi, newDpi);
        if (_bigScreen != BigScreenMode.None) ApplyEnforcedBounds();
    }

    protected override void OnStateChanged(EventArgs e)
    {
        base.OnStateChanged(e);

        if (_bigScreen != BigScreenMode.None && WindowState == WindowState.Minimized)
        {
            WindowState = WindowState.Normal;
            ApplyEnforcedBounds();
            ShowToast("大屏模式已阻止最小化（Esc 退出大屏）", "\uE72E");
        }
    }

    // ==================================================================
    //  计时核心
    // ==================================================================

    private void ResetPhaseTimers()
    {
        _remaining = _settings.DurationFor(_phase);
        _deadline = Clock.Elapsed + _remaining;
    }

    private void StartTimer()
    {
        if (_running) return;

        if (_remaining <= TimeSpan.Zero) ResetPhaseTimers();

        if (_phase == PhaseKind.Focus && _bigScreen == BigScreenMode.None && _settings.AutoBigScreenOnFocus)
        {
            EnterBigScreen(_settings.BigScreen);
        }

        _deadline = Clock.Elapsed + _remaining;
        _running = true;
        _tickTimer.Start();
        ApplyKeepAwake();
        UpdateUi();

        if (_phase == PhaseKind.Focus)
        {
            if (_settings.BackgroundRotateOnFocus) RotateBackground();
            if (_settings.NoiseAutoPlayOnFocus && !_noise.IsPlaying) _noise.Play();
        }
    }

    private void PauseTimer()
    {
        if (_running) _remaining = _deadline - Clock.Elapsed;
        if (_remaining < TimeSpan.Zero) _remaining = TimeSpan.Zero;
        _running = false;
        _tickTimer.Stop();
        ReleaseKeepAwake();
        if (_settings.NoiseOnlyDuringFocus) _noise.Pause();
        UpdateUi();
    }

    private void ToggleStartPause()
    {
        if (_running) PauseTimer();
        else StartTimer();
    }

    private void OnTick()
    {
        if (!_running) return;

        var left = _deadline - Clock.Elapsed;
        if (left <= TimeSpan.Zero)
        {
            _remaining = TimeSpan.Zero;
            _running = false;
            _tickTimer.Stop();
            UpdateUi();
            CompletePhase();
            return;
        }

        _remaining = left;
        UpdateUi();
    }

    /// <summary>当前阶段自然结束。</summary>
    private void CompletePhase()
    {
        var finished = _phase;
        _running = false;
        _tickTimer.Stop();
        ReleaseKeepAwake();

        if (finished == PhaseKind.Focus)
        {
            _settings.RecordFocusCompletion();
            _history.Add(DateTime.Today, _settings.FocusMinutes);
            _history.Save();
        }

        if (_settings.NoiseOnlyDuringFocus) _noise.Pause();

        if (_settings.SoundEnabled) ChimePlayer.PlayPhaseEnd(finished);
        if (_settings.NotifyOnPhaseEnd) FlashTaskbar();

        ShowToast(
            finished == PhaseKind.Focus ? "专注完成，休息一下吧" : "休息结束，继续加油",
            finished == PhaseKind.Focus ? "\uE73E" : "\uE768");

        AdvanceAfter(finished);
        ResetPhaseTimers();
        UpdateUi();

        if (_settings.AutoStartNext) StartTimer();
        SaveSettings();
    }

    /// <summary>
    /// 保存设置。带 --focus / --light / --dark 的会话级覆盖不会被写回配置文件；
    /// 写盘失败时给出一次提示而不是静默丢失。
    /// </summary>
    private void SaveSettings()
    {
        int currentFocus = _settings.FocusMinutes;
        var currentTheme = _settings.Theme;
        if (_focusOverrideActive) _settings.FocusMinutes = _originalFocusMinutes;
        if (_themeOverrideActive) _settings.Theme = _originalTheme;

        bool ok = SettingsStore.Save(_settings);

        if (_focusOverrideActive) _settings.FocusMinutes = currentFocus;
        if (_themeOverrideActive) _settings.Theme = currentTheme;

        if (!ok && !_saveErrorReported)
        {
            _saveErrorReported = true;
            ShowToast($"设置保存失败：{SettingsStore.LastSaveError}", "\uE7BA");
        }
    }

    /// <summary>跳过当前阶段（不计入统计）。</summary>
    private void SkipPhase()
    {
        var finished = _phase;
        _running = false;
        _tickTimer.Stop();
        ReleaseKeepAwake();

        AdvanceAfter(finished);
        ResetPhaseTimers();
        UpdateUi();
        ShowToast($"已跳过{finished.DisplayName()}", "\uE893");

        if (_settings.AutoStartNext) StartTimer();
    }

    private void ResetCurrentPhase()
    {
        _running = false;
        _tickTimer.Stop();
        ReleaseKeepAwake();
        ResetPhaseTimers();
        UpdateUi();
        ShowToast($"已重置{_phase.DisplayName()}", "\uE72C");
    }

    /// <summary>决定下一个阶段（长休息按间隔轮换）。</summary>
    private void AdvanceAfter(PhaseKind finished)
    {
        if (finished == PhaseKind.Focus)
        {
            _phase = _roundInCycle >= _settings.LongBreakInterval ? PhaseKind.LongBreak : PhaseKind.ShortBreak;
        }
        else
        {
            if (_phase == PhaseKind.LongBreak) _roundInCycle = 1;
            else _roundInCycle = Math.Min(_roundInCycle + 1, _settings.LongBreakInterval);
            _phase = PhaseKind.Focus;
        }
    }

    // ==================================================================
    //  界面刷新
    // ==================================================================

    private void UpdateUi()
    {
        int seconds = (int)Math.Ceiling(Math.Max(0, _remaining.TotalSeconds));
        TxtTime.Text = seconds >= 3600
            ? $"{seconds / 3600}:{(seconds % 3600) / 60:00}:{seconds % 60:00}"
            : $"{seconds / 60:00}:{seconds % 60:00}";

        TxtPhase.Text = _phase.DisplayName();
        TxtTitlePhase.Text = _phase.DisplayName();

        double total = _settings.DurationFor(_phase).TotalSeconds;
        Ring.Progress = total <= 0 ? 0 : 1.0 - Math.Clamp(_remaining.TotalSeconds / total, 0, 1);

        var phaseDuration = _settings.DurationFor(_phase);
        PlayLabel.Text = _running
            ? "暂停"
            : _remaining < phaseDuration
                ? "继续"
                : _phase == PhaseKind.Focus ? "开始专注" : "开始休息";
        PlayGlyph.Text = _running ? "\uE769" : "\uE768";

        TxtRound.Text = _phase switch
        {
            PhaseKind.Focus => $"第 {_roundInCycle} / {_settings.LongBreakInterval} 个番茄",
            PhaseKind.LongBreak => "长休息 · 本轮已完成",
            _ => "短休息 · 放松一下"
        };

        _settings.RollDaily();
        TxtStats.Text = $"今日 {_settings.CompletedToday} 个番茄 · {_settings.FocusMinutesToday} 分钟 · 连续 {_settings.StreakDays} 天";
        TxtStatsDetail.Text =
            $"今日完成：{_settings.CompletedToday} 个番茄（{_settings.FocusMinutesToday} 分钟）\n" +
            $"累计完成：{_settings.TotalCompleted} 个番茄\n" +
            $"连续专注：{_settings.StreakDays} 天\n" +
            $"历史记录：{(File.Exists(FocusHistory.FilePath) ? FocusHistory.FilePath : "尚无（完成第一个番茄后生成）")}\n" +
            $"配置文件：{SettingsStore.FilePath}";

        Title = $"{TxtTime.Text} · {_phase.DisplayName()} · 微软风格番茄钟";

        UpdateRoundDots();
        UpdateClock();
    }

    private void UpdateRoundDots()
    {
        int count = _settings.LongBreakInterval;
        if (_dots.Count != count)
        {
            RoundDots.Children.Clear();
            _dots.Clear();
            for (int i = 0; i < count; i++)
            {
                var dot = new Ellipse { Width = 8, Height = 8, Margin = new Thickness(0, 0, 7, 0) };
                _dots.Add(dot);
                RoundDots.Children.Add(dot);
            }
        }

        var activeBrush = TryFindResource(_phase.ResourceKey()) as Brush;
        var idleBrush = TryFindResource("TrackBrush") as Brush;

        int done = _phase == PhaseKind.Focus ? _roundInCycle - 1 : _roundInCycle;
        for (int i = 0; i < _dots.Count; i++)
            _dots[i].Fill = i < done ? activeBrush : idleBrush;
    }

    private void UpdatePhaseVisuals()
    {
        if (TryFindResource(_phase.ResourceKey()) is not SolidColorBrush brush) return;
        Ring.IndicatorBrush = brush;
        var glow = new SolidColorBrush(Color.FromArgb(0x22, brush.Color.R, brush.Color.G, brush.Color.B));
        glow.Freeze();
        Ring.GlowBrush = glow;
    }

    private void UpdateLayoutMetrics()
    {
        double width = RingHost.ActualWidth;
        double height = RingHost.ActualHeight;
        if (width <= 0 || height <= 0) return;

        double size = Math.Min(width, height) * (_bigScreen == BigScreenMode.None ? 0.92 : 0.80);
        size = Math.Clamp(size, 180, 920);

        Ring.Width = size;
        Ring.Height = size;
        Ring.RingThickness = Math.Clamp(size * 0.055, 8, 34);
        TxtTime.FontSize = Math.Clamp(size * 0.245, 34, 190);
        TxtPhase.FontSize = Math.Clamp(size * 0.065, 13, 46);
        TxtRound.FontSize = Math.Clamp(size * 0.052, 11, 34);
        TxtClock.FontSize = Math.Clamp(size * 0.062, 12, 42);
    }

    // ==================================================================
    //  “强制大屏”
    // ==================================================================

    private void SetBigScreen(BigScreenMode mode)
    {
        if (mode == BigScreenMode.None) ExitBigScreen();
        else EnterBigScreen(mode);
    }

    private void ToggleBigScreen()
    {
        if (_bigScreen != BigScreenMode.None) ExitBigScreen();
        else EnterBigScreen(_settings.BigScreen == BigScreenMode.None ? BigScreenMode.Mega : _settings.BigScreen);
    }

    private void CycleBigScreen()
    {
        var next = _bigScreen switch
        {
            BigScreenMode.None => BigScreenMode.Full,
            BigScreenMode.Full => BigScreenMode.Mega,
            _ => BigScreenMode.None
        };
        SetBigScreen(next);
    }

    private void EnterBigScreen(BigScreenMode mode)
    {
        if (mode == BigScreenMode.None)
        {
            ExitBigScreen();
            return;
        }

        if (_bigScreen == BigScreenMode.None) SaveWindowedBounds();

        _bigScreen = mode;
        _settings.BigScreen = mode;

        _enforceBounds = false;
        WindowState = WindowState.Normal;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        if (_settings.BigScreenTopmost) Topmost = true;

        var chrome = WindowChrome.GetWindowChrome(this);
        if (chrome is not null)
        {
            chrome.CaptionHeight = 0;
            chrome.ResizeBorderThickness = new Thickness(0);
            chrome.CornerRadius = new CornerRadius(0);
        }
        RootBorder.CornerRadius = new CornerRadius(0);
        MainArea.Margin = new Thickness(48, 8, 48, 8);
        SetDwmCorners(false);

        ApplyEnforcedBounds();
        UpdateModeChips();
        UpdateLayoutMetrics();
        SetChromeVisible(true);
        UpdateScreenInfo();
        SaveSettings();

        ShowToast($"已进入{Describe(mode)}，尺寸已锁定，Esc 或 F11 退出", "\uE740");
    }

    private void ExitBigScreen()
    {
        if (_bigScreen == BigScreenMode.None) return;

        _bigScreen = BigScreenMode.None;
        _enforceBounds = false;

        // 大屏期间若被 Win+↑ 之类置为最大化，必须先还原，否则 Left/Top/Width/Height 不生效
        if (WindowState != WindowState.Normal) WindowState = WindowState.Normal;

        ResizeMode = ResizeMode.CanResize;
        ShowInTaskbar = true;
        Topmost = _settings.AlwaysOnTop;

        var chrome = WindowChrome.GetWindowChrome(this);
        if (chrome is not null)
        {
            chrome.CaptionHeight = 40;
            chrome.ResizeBorderThickness = new Thickness(6);
            chrome.CornerRadius = new CornerRadius(8);
        }
        RootBorder.CornerRadius = new CornerRadius(8);
        MainArea.Margin = new Thickness(24, 2, 24, 2);
        SetDwmCorners(true);

        RestoreWindowedBounds();
        UpdateModeChips();
        UpdateLayoutMetrics();
        SetChromeVisible(true);
        UpdateScreenInfo();

        ShowToast("已退出大屏，回到窗口模式", "\uE73F");
    }

    private void ApplyEnforcedBounds()
    {
        if (_bigScreen == BigScreenMode.None) return;

        var (left, top, width, height) = _bigScreen == BigScreenMode.Mega
            ? ScreenInfo.VirtualScreenBounds()
            : ScreenInfo.PrimaryMonitorBounds();

        var dpi = VisualTreeHelper.GetDpi(this);
        _enforcedRectPx = new Rect(left, top, width, height);

        _enforceBounds = false;
        Left = left / dpi.DpiScaleX;
        Top = top / dpi.DpiScaleY;
        Width = width / dpi.DpiScaleX;
        Height = height / dpi.DpiScaleY;
        _enforceBounds = true;

        // 跨屏移动后 DPI 可能变化，稍后再校正一次
        if (_reapplyScheduled) return;
        _reapplyScheduled = true;
        Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() =>
        {
            _reapplyScheduled = false;
            if (_bigScreen == BigScreenMode.None) return;
            var dpi2 = VisualTreeHelper.GetDpi(this);
            if (Math.Abs(dpi2.DpiScaleX - dpi.DpiScaleX) > 0.001 || Math.Abs(ActualWidth - Width) > 1)
            {
                _enforceBounds = false;
                Left = _enforcedRectPx.Left / dpi2.DpiScaleX;
                Top = _enforcedRectPx.Top / dpi2.DpiScaleY;
                Width = _enforcedRectPx.Width / dpi2.DpiScaleX;
                Height = _enforcedRectPx.Height / dpi2.DpiScaleY;
                _enforceBounds = true;
            }
            UpdateLayoutMetrics();
        }));
    }

    private void SaveWindowedBounds()
    {
        if (WindowState != WindowState.Normal) return;
        _windowedBounds = new Rect(Left, Top, Math.Max(MinWidth, Width), Math.Max(MinHeight, Height));
        _hasWindowedBounds = true;
    }

    private void RestoreWindowedBounds()
    {
        if (_hasWindowedBounds)
        {
            Left = _windowedBounds.Left;
            Top = _windowedBounds.Top;
            Width = _windowedBounds.Width;
            Height = _windowedBounds.Height;
            return;
        }

        var (left, top, width, height) = ScreenInfo.PrimaryMonitorBounds();
        var dpi = VisualTreeHelper.GetDpi(this);
        Width = Math.Max(MinWidth, Math.Min(680, width / dpi.DpiScaleX));
        Height = Math.Max(MinHeight, Math.Min(820, height / dpi.DpiScaleY));
        Left = left / dpi.DpiScaleX + (width / dpi.DpiScaleX - Width) / 2;
        Top = top / dpi.DpiScaleY + (height / dpi.DpiScaleY - Height) / 2;
    }

    private void RestoreWindowBounds()
    {
        if (!_settings.HasWindowBounds) return;

        var (vx, vy, vw, vh) = ScreenInfo.VirtualScreenBounds();
        var dpi = VisualTreeHelper.GetDpi(this);

        double w = Math.Min(Math.Max(_settings.WindowWidth, MinWidth), vw / dpi.DpiScaleX);
        double h = Math.Min(Math.Max(_settings.WindowHeight, MinHeight), vh / dpi.DpiScaleY);
        double l = Math.Clamp(_settings.WindowLeft, vx / dpi.DpiScaleX - 40, (vx + vw) / dpi.DpiScaleX - 80);
        double t = Math.Clamp(_settings.WindowTop, vy / dpi.DpiScaleY, (vy + vh) / dpi.DpiScaleY - 80);

        WindowStartupLocation = WindowStartupLocation.Manual;
        Left = l;
        Top = t;
        Width = w;
        Height = h;

        _windowedBounds = new Rect(l, t, w, h);
        _hasWindowedBounds = true;
    }

    private static string Describe(BigScreenMode mode) => mode switch
    {
        BigScreenMode.Full => "全屏",
        BigScreenMode.Mega => "巨幕跨屏",
        _ => "窗口"
    };

    private void UpdateModeChips()
    {
        _suppressModeEvents = true;
        RbWindow.IsChecked = _bigScreen == BigScreenMode.None;
        RbFull.IsChecked = _bigScreen == BigScreenMode.Full;
        RbMega.IsChecked = _bigScreen == BigScreenMode.Mega;
        BtnBig.Content = _bigScreen == BigScreenMode.None ? "\uE740" : "\uE73F";
        _suppressModeEvents = false;
    }

    private void UpdateScreenInfo()
    {
        var (l, t, w, h) = ScreenInfo.VirtualScreenBounds();
        TxtScreenInfo.Text =
            $"显示器：{ScreenInfo.MonitorCount()} 台 · 虚拟桌面：{w} × {h} @ ({l},{t}) 物理像素\n" +
            $"当前方式：{Describe(_bigScreen)} · 置顶：{(_settings.BigScreenTopmost ? "是" : "否")}";
    }

    // ==================================================================
    //  窗口外观 / DWM
    // ==================================================================

    private void ApplyBackdrop()
    {
        bool wantMica = _settings.UseMicaBackdrop && Environment.OSVersion.Version.Build >= 22621;
        _micaActive = false;

        if (wantMica && _hwnd != IntPtr.Zero)
        {
            int backdrop = Native.DWMSBT_MAINWINDOW;
            int result = Native.DwmSetWindowAttribute(_hwnd, Native.DWMWA_SYSTEMBACKDROP_TYPE,
                ref backdrop, sizeof(int));

            // 让 DWM 把整块客户区当作材质区域，否则只有边框有云母效果
            var margins = new Native.MARGINS { Left = -1, Right = -1, Top = -1, Bottom = -1 };
            int extend = Native.DwmExtendFrameIntoClientArea(_hwnd, ref margins);

            _micaActive = result == 0 && extend == 0;
        }

        if (_micaActive)
        {
            Background = Brushes.Transparent;
            if (PresentationSource.FromVisual(this) is HwndSource source && source.CompositionTarget is not null)
                source.CompositionTarget.BackgroundColor = Colors.Transparent;
        }
        else
        {
            var margins = new Native.MARGINS();
            if (_hwnd != IntPtr.Zero) Native.DwmExtendFrameIntoClientArea(_hwnd, ref margins);
            SetResourceReference(BackgroundProperty, "WindowBackdropBrush");
            if (PresentationSource.FromVisual(this) is HwndSource source && source.CompositionTarget is not null)
                source.CompositionTarget.BackgroundColor = Colors.Black;
        }
    }

    private void ApplyDwmTheme()
    {
        if (_hwnd == IntPtr.Zero) return;
        int dark = ThemeManager.IsDark ? 1 : 0;
        Native.DwmSetWindowAttribute(_hwnd, Native.DWMWA_USE_IMMERSIVE_DARK_MODE, ref dark, sizeof(int));

        // 扩展玻璃框后 DWM 会在顶部绘制一条标题栏玻璃带，用与主题一致的标题栏颜色覆盖它，
        // 否则该区域会透出桌面壁纸的配色，与窗口主体不一致。
        if (TryFindResource("WindowBackdropBrush") is SolidColorBrush backdrop)
        {
            int caption = backdrop.Color.R | (backdrop.Color.G << 8) | (backdrop.Color.B << 16);
            Native.DwmSetWindowAttribute(_hwnd, Native.DWMWA_CAPTION_COLOR, ref caption, sizeof(int));
        }
    }

    private void SetDwmCorners(bool round)
    {
        if (_hwnd == IntPtr.Zero) return;
        int preference = round ? Native.DWMWCP_ROUND : Native.DWMWCP_DONOTROUND;
        Native.DwmSetWindowAttribute(_hwnd, Native.DWMWA_WINDOW_CORNER_PREFERENCE, ref preference, sizeof(int));
    }

    private void SetChromeVisible(bool visible)
    {
        if (visible)
        {
            if (!_chromeShown)
            {
                _chromeShown = true;
                FadeChrome(1);
            }
            _idleTimer.Stop();
            _idleTimer.Start();
            return;
        }

        if (!_chromeShown) return;
        _chromeShown = false;
        _idleTimer.Stop();
        FadeChrome(0);
    }

    private void FadeChrome(double target)
    {
        var duration = TimeSpan.FromMilliseconds(260);
        var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
        TitleBar.BeginAnimation(OpacityProperty, new DoubleAnimation(target, duration) { EasingFunction = ease });
        BottomBar.BeginAnimation(OpacityProperty, new DoubleAnimation(target, duration) { EasingFunction = ease });
        bool hit = target > 0.5;
        TitleBar.IsHitTestVisible = hit;
        BottomBar.IsHitTestVisible = hit;
    }

    // ==================================================================
    //  系统集成
    // ==================================================================

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        switch (msg)
        {
            case Native.WM_WINDOWPOSCHANGING:
                if (_enforceBounds)
                {
                    var pos = Marshal.PtrToStructure<Native.WINDOWPOS>(lParam);
                    pos.x = (int)_enforcedRectPx.X;
                    pos.y = (int)_enforcedRectPx.Y;
                    pos.cx = (int)_enforcedRectPx.Width;
                    pos.cy = (int)_enforcedRectPx.Height;
                    Marshal.StructureToPtr(pos, lParam, false);
                }
                break;

            case Native.WM_SYSCOMMAND:
                int command = (int)(wParam.ToInt64() & 0xFFF0);
                bool lockActive = _settings.FocusLock && _phase == PhaseKind.Focus && _running;

                if (command == Native.SC_MINIMIZE && (lockActive || _bigScreen != BigScreenMode.None))
                {
                    handled = true;
                    ShowToast(lockActive ? "专注锁定中，已拦截最小化" : "大屏模式，已拦截最小化（Esc 退出大屏）", "\uE72E");
                }
                else if ((command == Native.SC_MAXIMIZE || command == Native.SC_RESTORE) &&
                         _bigScreen != BigScreenMode.None)
                {
                    // 大屏期间禁止 Win+↑ / 双击标题栏等最大化，避免退出大屏后停在最大化状态
                    handled = true;
                }
                break;

            case Native.WM_DISPLAYCHANGE:
                // 显示器分辨率 / 数量变化后重新适配大屏矩形
                if (_bigScreen != BigScreenMode.None)
                {
                    Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() =>
                    {
                        ApplyEnforcedBounds();
                        UpdateScreenInfo();
                    }));
                }
                break;

            case Native.WM_POWERBROADCAST:
                int powerEvent = wParam.ToInt32();
                if (powerEvent == Native.PBT_APMSUSPEND)
                {
                    // 系统即将睡眠：专注计时不应把睡眠时间算成专注时间，主动暂停并说明
                    if (_running && _phase == PhaseKind.Focus)
                    {
                        PauseTimer();
                        _sleepInterrupted = true;
                        ShowToast("系统即将睡眠，已暂停本次专注（恢复后按空格继续）", "\uE7BA");
                    }
                    handled = true;
                }
                else if (powerEvent is Native.PBT_APMRESUMEAUTOMATIC or Native.PBT_APMRESUMESUSPEND)
                {
                    // 睡眠会清空线程执行状态请求，恢复后按当前设置重新申请
                    ApplyKeepAwake();
                    if (_sleepInterrupted)
                    {
                        _sleepInterrupted = false;
                        ShowToast("已从睡眠恢复，专注保持暂停状态", "\uE7C4");
                    }
                    handled = true;
                }
                break;
        }

        return IntPtr.Zero;
    }

    /// <summary>
    /// 专注进行中阻止系统休眠 / 保持屏幕常亮（SetThreadExecutionState 作用于调用线程，始终在 UI 线程调用）。
    /// 只开「阻止休眠」→ ES_SYSTEM_REQUIRED；再开「屏幕常亮」→ 追加 ES_DISPLAY_REQUIRED。
    /// </summary>
    private void ApplyKeepAwake()
    {
        if (!_running || _phase != PhaseKind.Focus)
        {
            ReleaseKeepAwake();
            return;
        }

        uint flags = Native.ES_CONTINUOUS;
        if (_settings.PreventSystemSleep) flags |= Native.ES_SYSTEM_REQUIRED;
        if (_settings.KeepScreenAwake) flags |= Native.ES_DISPLAY_REQUIRED;

        if (flags == Native.ES_CONTINUOUS)
        {
            ReleaseKeepAwake();
            return;
        }

        Native.SetThreadExecutionState(flags);
    }

    private void ReleaseKeepAwake()
    {
        Native.SetThreadExecutionState(Native.ES_CONTINUOUS);
    }

    private void FlashTaskbar()
    {
        if (_hwnd == IntPtr.Zero) return;
        var info = new Native.FLASHWINFO
        {
            cbSize = (uint)Marshal.SizeOf<Native.FLASHWINFO>(),
            hwnd = _hwnd,
            dwFlags = Native.FLASHW_ALL | Native.FLASHW_TIMERNOFG,
            uCount = 8,
            dwTimeout = 0
        };
        Native.FlashWindowEx(ref info);
    }

    private void OnThemeWatch(object? sender, EventArgs e)
    {
        if (ThemeManager.Preference != ThemePreference.System) return;
        if (ThemeManager.IsSystemDark() != ThemeManager.IsDark) ThemeManager.Apply();
    }

    // ==================================================================
    //  设置面板
    // ==================================================================

    private void ApplySettingsToUi()
    {
        // 初始化控件值期间禁止回写设置，否则未赋值的控件会把默认值覆盖到配置上
        _suspendSettingsWrite = true;
        try
        {
            SldFocus.Value = _settings.FocusMinutes;
            SldShort.Value = _settings.ShortBreakMinutes;
            SldLong.Value = _settings.LongBreakMinutes;
            SldInterval.Value = _settings.LongBreakInterval;

            TglAutoStart.IsChecked = _settings.AutoStartNext;
            TglSound.IsChecked = _settings.SoundEnabled;
            TglKeepAwake.IsChecked = _settings.KeepScreenAwake;
            TglNoSleep.IsChecked = _settings.PreventSystemSleep;
            TglNotify.IsChecked = _settings.NotifyOnPhaseEnd;
            TglTopmost.IsChecked = _settings.AlwaysOnTop;
            TglLock.IsChecked = _settings.FocusLock;
            TglAutoBig.IsChecked = _settings.AutoBigScreenOnFocus;
            TglBigTopmost.IsChecked = _settings.BigScreenTopmost;
            TglMica.IsChecked = _settings.UseMicaBackdrop;

            TglClock.IsChecked = _settings.ShowClock;
            TglClockFocusOnly.IsChecked = _settings.ClockOnlyDuringFocus;
            TglBgOnFocus.IsChecked = _settings.BackgroundRotateOnFocus;
            TglBgAccent.IsChecked = _settings.BackgroundUseImageAccent;
            SldBgOpacity.Value = _settings.BackgroundOpacity;
            CmbBgRotate.SelectedIndex = RotateIndexFromMinutes(_settings.BackgroundRotateMinutes);

            TglNoiseAuto.IsChecked = _settings.NoiseAutoPlayOnFocus;
            TglNoiseOnlyFocus.IsChecked = _settings.NoiseOnlyDuringFocus;
            TglNoiseShuffle.IsChecked = _settings.NoiseShuffle;
            SldNoiseVolume.Value = _settings.NoiseVolume;

            CmbTheme.SelectedIndex = (int)_settings.Theme;
        }
        finally
        {
            _suspendSettingsWrite = false;
        }

        UpdateDurationLabels();
        UpdateBackgroundInfo();
        UpdateNoiseInfo();
    }

    private void UpdateDurationLabels()
    {
        LblFocus.Text = $"{_settings.FocusMinutes} 分钟";
        LblShort.Text = $"{_settings.ShortBreakMinutes} 分钟";
        LblLong.Text = $"{_settings.LongBreakMinutes} 分钟";
        LblInterval.Text = $"{_settings.LongBreakInterval} 个";
    }

    private void OpenSettings()
    {
        if (_settingsOpen) return;
        _settingsOpen = true;

        SettingsOverlay.Visibility = Visibility.Visible;
        var animation = new DoubleAnimation(SettingsPanel.Width, 0, TimeSpan.FromMilliseconds(240))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        PanelSlide.BeginAnimation(TranslateTransform.XProperty, animation);
        Scrim.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(200)));
    }

    private void CloseSettings()
    {
        if (!_settingsOpen) return;
        _settingsOpen = false;

        var animation = new DoubleAnimation(0, SettingsPanel.Width, TimeSpan.FromMilliseconds(200))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseIn }
        };
        animation.Completed += (_, _) => SettingsOverlay.Visibility = Visibility.Collapsed;
        PanelSlide.BeginAnimation(TranslateTransform.XProperty, animation);
        Scrim.BeginAnimation(OpacityProperty, new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(180)));
    }

    // ==================================================================
    //  事件处理
    // ==================================================================

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        bool ctrl = (Keyboard.Modifiers & ModifierKeys.Control) != 0;
        bool shift = (Keyboard.Modifiers & ModifierKeys.Shift) != 0;

        // 中文输入法激活时字母键会以 ImeProcessed 形式到达，需要用 ImeProcessedKey 还原真实按键
        var key = e.Key == Key.ImeProcessed ? e.ImeProcessedKey : e.Key;

        if (ctrl && shift && key == Key.Q)
        {
            _forceExit = true;
            Close();
            e.Handled = true;
            return;
        }

        if (ctrl && key == Key.OemComma)
        {
            if (_settingsOpen) CloseSettings();
            else OpenSettings();
            e.Handled = true;
            return;
        }

        if (ctrl && key is Key.D1 or Key.NumPad1)
        {
            SetBigScreen(BigScreenMode.None);
            e.Handled = true;
            return;
        }

        if (ctrl && key is Key.D2 or Key.NumPad2)
        {
            SetBigScreen(BigScreenMode.Full);
            e.Handled = true;
            return;
        }

        if (ctrl && key is Key.D3 or Key.NumPad3)
        {
            SetBigScreen(BigScreenMode.Mega);
            e.Handled = true;
            return;
        }

        if (ctrl && key == Key.I)
        {
            OpenStatsWindow();
            e.Handled = true;
            return;
        }

        switch (key)
        {
            case Key.Space when !_settingsOpen:
                ToggleStartPause();
                e.Handled = true;
                break;

            case Key.R when !_settingsOpen:
                ResetCurrentPhase();
                e.Handled = true;
                break;

            case Key.S when !_settingsOpen:
                SkipPhase();
                e.Handled = true;
                break;

            case Key.F11:
                ToggleBigScreen();
                e.Handled = true;
                break;

            case Key.F when !_settingsOpen:
                CycleBigScreen();
                e.Handled = true;
                break;

            case Key.Escape:
                if (_settingsOpen) CloseSettings();
                else if (_bigScreen != BigScreenMode.None) ExitBigScreen();
                e.Handled = true;
                break;
        }
    }

    private void OnPreviewMouseMove(object sender, MouseEventArgs e) => SetChromeVisible(true);

    private void OnWindowSizeChanged(object sender, SizeChangedEventArgs e) => UpdateLayoutMetrics();

    private void OnToggleStartPause(object sender, RoutedEventArgs e) => ToggleStartPause();

    private void OnReset(object sender, RoutedEventArgs e) => ResetCurrentPhase();

    private void OnSkip(object sender, RoutedEventArgs e) => SkipPhase();

    private void OnMinimize(object sender, RoutedEventArgs e)
    {
        if (_bigScreen != BigScreenMode.None || (_settings.FocusLock && _phase == PhaseKind.Focus && _running))
        {
            ShowToast("当前状态已阻止最小化（Esc 退出大屏 / Ctrl+Shift+Q 退出）", "\uE72E");
            return;
        }
        WindowState = WindowState.Minimized;
    }

    private void OnToggleBigScreen(object sender, RoutedEventArgs e) => ToggleBigScreen();

    private void OnFullScreenNow(object sender, RoutedEventArgs e) => SetBigScreen(BigScreenMode.Full);

    private void OnMegaNow(object sender, RoutedEventArgs e) => SetBigScreen(BigScreenMode.Mega);

    private void OnCloseClick(object sender, RoutedEventArgs e) => Close();

    private void OnOpenSettings(object sender, RoutedEventArgs e) => OpenSettings();

    private void OnCloseSettings(object sender, RoutedEventArgs e) => CloseSettings();

    private void OnScrimClick(object sender, MouseButtonEventArgs e) => CloseSettings();

    private void OnModeChecked(object sender, RoutedEventArgs e)
    {
        if (!_ready || _suppressModeEvents || sender is not RadioButton radio) return;
        var mode = (radio.Tag as string) switch
        {
            "Full" => BigScreenMode.Full,
            "Mega" => BigScreenMode.Mega,
            _ => BigScreenMode.None
        };
        SetBigScreen(mode);
    }

    private void OnDurationChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!_ready || _suspendSettingsWrite) return;

        int focusFromUi = (int)Math.Round(SldFocus.Value);

        // 用户在设置面板里显式改了「专注时长」→ 结束 --focus 的会话级覆盖，按用户设置持久化
        if (_focusOverrideActive && focusFromUi != _overrideFocusMinutes) _focusOverrideActive = false;

        _settings.FocusMinutes = focusFromUi;
        _settings.ShortBreakMinutes = (int)Math.Round(SldShort.Value);
        _settings.LongBreakMinutes = (int)Math.Round(SldLong.Value);
        _settings.LongBreakInterval = (int)Math.Round(SldInterval.Value);
        _settings.Normalize();

        UpdateDurationLabels();
        if (!_running) ResetPhaseTimers();

        UpdateLayoutMetrics();
        UpdateUi();
        SaveSettings();
    }

    private void OnSettingToggled(object sender, RoutedEventArgs e)
    {
        if (!_ready || _suspendSettingsWrite) return;

        _settings.AutoStartNext = TglAutoStart.IsChecked == true;
        _settings.SoundEnabled = TglSound.IsChecked == true;
        _settings.KeepScreenAwake = TglKeepAwake.IsChecked == true;
        _settings.PreventSystemSleep = TglNoSleep.IsChecked == true;
        _settings.NotifyOnPhaseEnd = TglNotify.IsChecked == true;
        _settings.AlwaysOnTop = TglTopmost.IsChecked == true;
        _settings.FocusLock = TglLock.IsChecked == true;
        _settings.AutoBigScreenOnFocus = TglAutoBig.IsChecked == true;
        _settings.BigScreenTopmost = TglBigTopmost.IsChecked == true;
        _settings.UseMicaBackdrop = TglMica.IsChecked == true;
        _settings.ShowClock = TglClock.IsChecked == true;
        _settings.ClockOnlyDuringFocus = TglClockFocusOnly.IsChecked == true;
        _settings.NoiseAutoPlayOnFocus = TglNoiseAuto.IsChecked == true;
        _settings.NoiseOnlyDuringFocus = TglNoiseOnlyFocus.IsChecked == true;
        _settings.NoiseShuffle = TglNoiseShuffle.IsChecked == true;
        _noise.Shuffle = _settings.NoiseShuffle;

        if (ReferenceEquals(sender, TglClock) || ReferenceEquals(sender, TglClockFocusOnly)) UpdateClock();

        if (ReferenceEquals(sender, TglKeepAwake) || ReferenceEquals(sender, TglNoSleep))
        {
            // 两个开关共同决定执行状态请求：任一开启都需重新申请，全关则释放
            ApplyKeepAwake();
        }

        if (ReferenceEquals(sender, TglTopmost) && _bigScreen == BigScreenMode.None)
            Topmost = _settings.AlwaysOnTop;

        if (ReferenceEquals(sender, TglBigTopmost) && _bigScreen != BigScreenMode.None)
            Topmost = _settings.BigScreenTopmost;

        if (ReferenceEquals(sender, TglMica)) ApplyBackdrop();

        UpdateScreenInfo();
        SaveSettings();
    }

    private void OnThemeSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_ready || _suspendSettingsWrite) return;
        var preference = CmbTheme.SelectedIndex switch
        {
            1 => ThemePreference.Light,
            2 => ThemePreference.Dark,
            _ => ThemePreference.System
        };
        // 用户自己选了主题 → 解除命令行 --light/--dark 的会话级覆盖，此后正常持久化
        _themeOverrideActive = false;
        _settings.Theme = preference;
        ThemeManager.SetPreference(preference);
        SaveSettings();
    }

    private void OnResetStats(object sender, RoutedEventArgs e)
    {
        _settings.ResetStatistics();
        SaveSettings();
        UpdateUi();
        ShowToast("统计已重置", "\uE72C");
    }

    private void OnPreviewSound(object sender, RoutedEventArgs e)
    {
        if (ChimePlayer.Preview()) ShowToast("已播放提示音", "\uE767");
        else ShowToast("提示音播放失败，请检查系统声音与音量设置", "\uE7BA");
    }

    private void OnWindowClosing(object? sender, CancelEventArgs e)
    {
        if (!_forceExit && _settings.FocusLock && _phase == PhaseKind.Focus && _running)
        {
            e.Cancel = true;
            ShowToast("专注锁定中，完成后才能关闭（Ctrl + Shift + Q 强制退出）", "\uE72E");
            FlashTaskbar();
            return;
        }

        ReleaseKeepAwake();
        ChimePlayer.Stop();

        if (_bigScreen == BigScreenMode.None && WindowState == WindowState.Normal)
        {
            _settings.HasWindowBounds = true;
            _settings.WindowLeft = Left;
            _settings.WindowTop = Top;
            _settings.WindowWidth = Width;
            _settings.WindowHeight = Height;
        }

        SaveSettings();
    }

    // ==================================================================
    //  当前时间 / 背景图片 / 白噪音 / 统计窗口
    // ==================================================================

    private void UpdateClock()
    {
        // 开启「仅专注阶段显示」时，休息阶段隐藏时钟
        bool visible = _settings.ShowClock && (!_settings.ClockOnlyDuringFocus || _phase == PhaseKind.Focus);
        TxtClock.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        if (visible) TxtClock.Text = DateTime.Now.ToString("HH:mm:ss");
    }

    private static int RotateIndexFromMinutes(int minutes) => minutes switch
    {
        <= 0 => 0,
        <= 5 => 1,
        <= 15 => 2,
        <= 30 => 3,
        <= 60 => 4,
        _ => 5
    };

    private static int RotateMinutesFromIndex(int index) => index switch
    {
        1 => 5,
        2 => 15,
        3 => 30,
        4 => 60,
        5 => 1440,
        _ => 0
    };

    private static string DescribeRotate(int minutes) => minutes switch
    {
        <= 0 => "不轮换",
        5 => "每 5 分钟",
        15 => "每 15 分钟",
        30 => "每 30 分钟",
        60 => "每 1 小时",
        _ => "每天"
    };

    // ---- 背景图片 ----

    private void InitializeBackground()
    {
        _background.Changed += (_, _) => ApplyBackgroundVisual();

        if (!string.IsNullOrWhiteSpace(_settings.BackgroundFolder) && Directory.Exists(_settings.BackgroundFolder))
            _background.SetFolder(_settings.BackgroundFolder);
        else if (!string.IsNullOrWhiteSpace(_settings.BackgroundImagePath) && File.Exists(_settings.BackgroundImagePath))
            _background.SetSingle(_settings.BackgroundImagePath);

        ApplyBackgroundVisual();
    }

    private void ApplyBackgroundVisual()
    {
        bool hasImage = _background.CurrentImage is not null;

        BackgroundImage.Source = _background.CurrentImage;
        BackgroundImage.Opacity = _settings.BackgroundOpacity;
        BackgroundImage.Visibility = hasImage ? Visibility.Visible : Visibility.Collapsed;
        ImageScrim.Visibility = hasImage ? Visibility.Visible : Visibility.Collapsed;

        // 有背景图时窗口本体透明，让图片完整显示；否则回到主题底色
        if (hasImage) RootBorder.Background = Brushes.Transparent;
        else RootBorder.SetResourceReference(Border.BackgroundProperty, "WindowOverlayBrush");

        ApplyImageAccent();
        UpdateBackgroundInfo();
    }

    /// <summary>主题色跟随背景图片主色（可在设置里关闭）。</summary>
    private void ApplyImageAccent()
    {
        if (_settings.BackgroundUseImageAccent && _background.CurrentImage is { } image)
            ThemeManager.SetAccentOverride(BackgroundService.ExtractAccent(image, ThemeManager.IsDark));
        else
            ThemeManager.SetAccentOverride(null);
    }

    private void RotateBackground()
    {
        if (!_background.HasImages) return;
        _background.Next();
        _backgroundElapsed = TimeSpan.Zero;
    }

    private void OnBackgroundTimerTick(object? sender, EventArgs e)
    {
        if (_settings.BackgroundRotateMinutes <= 0 || !_background.HasImages) return;

        _backgroundElapsed += _backgroundTimer.Interval;
        if (_backgroundElapsed.TotalMinutes < _settings.BackgroundRotateMinutes) return;

        _backgroundElapsed = TimeSpan.Zero;
        _background.Next();
    }

    private void UpdateBackgroundInfo()
    {
        LblBgOpacity.Text = $"{_settings.BackgroundOpacity * 100:0}%";

        if (!_background.HasImages)
        {
            TxtBgInfo.Text = "未设置背景图片（可选一张图片，或选一个文件夹在其中的图片间轮换）";
            return;
        }

        string name = System.IO.Path.GetFileName(_background.CurrentPath ?? string.Empty);
        string rotate = _settings.BackgroundRotateMinutes > 0
            ? $"{DescribeRotate(_settings.BackgroundRotateMinutes)}轮换"
            : "不自动轮换";
        TxtBgInfo.Text = $"当前：{name}\n文件夹内共 {_background.ImageCount} 张 · {rotate}";
    }

    private void OnPickBackgroundImage(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "选择背景图片",
            Filter = "图片文件|*.jpg;*.jpeg;*.png;*.bmp;*.gif;*.tif;*.tiff;*.jfif|所有文件 (*.*)|*.*"
        };
        if (dialog.ShowDialog(this) != true) return;

        _settings.BackgroundImagePath = dialog.FileName;
        _settings.BackgroundFolder = string.Empty;
        _background.SetSingle(dialog.FileName);
        ApplyBackgroundVisual();
        SaveSettings();
        ShowToast("已设置背景图片", "\uE91B");
    }

    private void OnPickBackgroundFolder(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "选择背景图片文件夹", Multiselect = false };
        if (dialog.ShowDialog(this) != true) return;

        _settings.BackgroundFolder = dialog.FolderName;
        _settings.BackgroundImagePath = string.Empty;
        _background.SetFolder(dialog.FolderName);
        ApplyBackgroundVisual();
        SaveSettings();

        if (_background.HasImages) ShowToast($"已载入 {_background.ImageCount} 张背景图片", "\uE91B");
        else ShowToast("该文件夹里没有可用的图片", "\uE7BA");
    }

    private void OnNextBackground(object sender, RoutedEventArgs e)
    {
        if (!_background.HasImages)
        {
            ShowToast("还没有设置背景图片", "\uE7BA");
            return;
        }
        RotateBackground();
    }

    private void OnClearBackground(object sender, RoutedEventArgs e)
    {
        _settings.BackgroundImagePath = string.Empty;
        _settings.BackgroundFolder = string.Empty;
        _background.Clear();
        ApplyBackgroundVisual();
        SaveSettings();
        ShowToast("已清除背景图片", "\uE894");
    }

    private void OnBackgroundOpacityChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!_ready || _suspendSettingsWrite) return;
        _settings.BackgroundOpacity = Math.Round(SldBgOpacity.Value, 2);
        ApplyBackgroundVisual();
        SaveSettings();
    }

    private void OnBackgroundOptionChanged(object sender, RoutedEventArgs e)
    {
        if (!_ready || _suspendSettingsWrite) return;
        _settings.BackgroundRotateOnFocus = TglBgOnFocus.IsChecked == true;
        _settings.BackgroundUseImageAccent = TglBgAccent.IsChecked == true;
        ApplyBackgroundVisual();
        SaveSettings();
    }

    private void OnBackgroundRotateChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_ready || _suspendSettingsWrite) return;
        _settings.BackgroundRotateMinutes = RotateMinutesFromIndex(CmbBgRotate.SelectedIndex);
        _backgroundElapsed = TimeSpan.Zero;
        UpdateBackgroundInfo();
        SaveSettings();
    }

    // ---- 白噪音 ----

    private void InitializeNoise()
    {
        NoiseList.ItemsSource = _noiseTracks;
        _noise.Volume = _settings.NoiseVolume;
        _noise.Shuffle = _settings.NoiseShuffle;

        _noise.TrackFailed += (_, message) => ShowToast("白噪音播放失败：" + message, "\uE7BA");
        _noise.StateChanged += (_, _) => UpdateNoiseInfo();

        foreach (var track in _settings.NoiseTracks) _noiseTracks.Add(track);
        _noise.SetTracks(_settings.NoiseTracks);
        UpdateNoiseInfo();
    }

    private void UpdateNoiseInfo()
    {
        LblNoiseVolume.Text = $"{_settings.NoiseVolume}%";
        BtnNoise.SetResourceReference(ForegroundProperty, _noise.IsPlaying ? "AccentBrush" : "TextPrimaryBrush");

        int available = _settings.NoiseTracks.Count(File.Exists);
        if (_settings.NoiseTracks.Count == 0)
        {
            TxtNoiseInfo.Text = "尚未导入音频文件（支持 mp3 / wav / wma / m4a 等）";
            return;
        }

        string state = _noise.IsPlaying
            ? $"正在播放：{System.IO.Path.GetFileName(_noise.CurrentTrack ?? string.Empty)}"
            : "已停止";
        TxtNoiseInfo.Text = $"已导入 {_settings.NoiseTracks.Count} 个文件（{available} 个可用）· {state}";
    }

    private void OnAddNoiseTracks(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "添加白噪音音频",
            Multiselect = true,
            Filter = "音频文件|*.mp3;*.wav;*.wma;*.m4a;*.aac;*.flac;*.ogg|所有文件 (*.*)|*.*"
        };
        if (dialog.ShowDialog(this) != true) return;

        int added = 0;
        foreach (var file in dialog.FileNames)
        {
            if (_settings.NoiseTracks.Any(p => string.Equals(p, file, StringComparison.OrdinalIgnoreCase))) continue;
            _settings.NoiseTracks.Add(file);
            _noiseTracks.Add(file);
            added++;
        }

        _noise.SetTracks(_settings.NoiseTracks);
        UpdateNoiseInfo();
        SaveSettings();
        ShowToast(added > 0 ? $"已导入 {added} 个音频文件" : "所选文件已在列表中", "\uE767");
    }

    private void OnRemoveNoiseTrack(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not string path) return;

        _settings.NoiseTracks.RemoveAll(p => string.Equals(p, path, StringComparison.OrdinalIgnoreCase));
        for (int i = _noiseTracks.Count - 1; i >= 0; i--)
        {
            if (string.Equals(_noiseTracks[i], path, StringComparison.OrdinalIgnoreCase)) _noiseTracks.RemoveAt(i);
        }

        _noise.SetTracks(_settings.NoiseTracks);
        UpdateNoiseInfo();
        SaveSettings();
    }

    private void OnClearNoiseTracks(object sender, RoutedEventArgs e)
    {
        _noise.Stop();
        _settings.NoiseTracks.Clear();
        _noiseTracks.Clear();
        _noise.SetTracks(Array.Empty<string>());
        UpdateNoiseInfo();
        SaveSettings();
        ShowToast("已清空白噪音列表", "\uE894");
    }

    private void OnToggleNoise(object sender, RoutedEventArgs e)
    {
        if (_settings.NoiseTracks.Count == 0)
        {
            ShowToast("请先在设置里导入白噪音音频", "\uE7BA");
            return;
        }

        if (_noise.IsPlaying) _noise.Pause();
        else if (!_noise.Play()) ShowToast(_noise.LastError ?? "白噪音播放失败", "\uE7BA");

        UpdateNoiseInfo();
    }

    private void OnNextNoise(object sender, RoutedEventArgs e)
    {
        if (_settings.NoiseTracks.Count == 0) return;
        _noise.Next();
        UpdateNoiseInfo();
    }

    private void OnNoiseVolumeChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!_ready || _suspendSettingsWrite) return;
        _settings.NoiseVolume = (int)Math.Round(SldNoiseVolume.Value);
        _noise.Volume = _settings.NoiseVolume;
        UpdateNoiseInfo();
        SaveSettings();
    }

    // ---- 统计窗口 ----

    private void OnOpenStats(object sender, RoutedEventArgs e) => OpenStatsWindow();

    private void OpenStatsWindow()
    {
        if (_statsWindow is { IsLoaded: true })
        {
            _statsWindow.Activate();
            return;
        }

        _statsWindow = new StatsWindow
        {
            Owner = this,
            Topmost = _bigScreen != BigScreenMode.None && _settings.BigScreenTopmost
        };
        _statsWindow.Closed += (_, _) => _statsWindow = null;
        _statsWindow.Show();
    }

    // ==================================================================
    //  浮出提示
    // ==================================================================

    private void ShowToast(string message, string glyph)
    {
        ToastText.Text = message;
        ToastGlyph.Text = glyph;
        ToastHost.Visibility = Visibility.Visible;
        ToastHost.BeginAnimation(OpacityProperty,
            new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(160)));

        _toastTimer.Stop();
        _toastTimer.Start();
    }

    private void HideToast()
    {
        var fade = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(280));
        fade.Completed += (_, _) => ToastHost.Visibility = Visibility.Collapsed;
        ToastHost.BeginAnimation(OpacityProperty, fade);
    }
}
