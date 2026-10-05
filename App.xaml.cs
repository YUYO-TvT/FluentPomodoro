using System.Threading;
using System.Windows;
using FluentPomodoro.Services;

namespace FluentPomodoro;

public partial class App : Application
{
    private Mutex? _singleInstanceMutex;

    /// <summary>启动参数：--bigscreen / -b / --fullscreen / --mega</summary>
    public static LaunchOptions Options { get; private set; } = new();

    protected override void OnStartup(StartupEventArgs e)
    {
        Options = LaunchOptions.Parse(e.Args);

        _singleInstanceMutex = new Mutex(true, @"Local\FluentPomodoro.SingleInstance", out bool isNew);
        if (!isNew)
        {
            MessageBox.Show("番茄钟已经在运行了。", "微软风格番茄钟",
                MessageBoxButton.OK, MessageBoxImage.Information);
            Shutdown();
            return;
        }

        ThemeManager.Initialize(Options.ForceLightDark);
        DispatcherUnhandledException += (_, args) =>
        {
            MessageBox.Show(args.Exception.Message, "番茄钟遇到问题",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            args.Handled = true;
        };

        var window = new MainWindow();
        MainWindow = window;
        window.Show();

        base.OnStartup(e);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _singleInstanceMutex?.Dispose();
        base.OnExit(e);
    }
}

public sealed class LaunchOptions
{
    public bool StartBigScreen { get; private set; }
    public bool ForceMega { get; private set; }
    public bool AutoStartTimer { get; private set; }
    public int? FocusMinutes { get; private set; }
    public ThemePreference? ForceLightDark { get; private set; }

    public static LaunchOptions Parse(string[] args)
    {
        var o = new LaunchOptions();
        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i].Trim().ToLowerInvariant())
            {
                case "--bigscreen":
                case "-b":
                case "--fullscreen":
                    o.StartBigScreen = true;
                    break;
                case "--mega":
                case "--span":
                    o.StartBigScreen = true;
                    o.ForceMega = true;
                    break;
                case "--start":
                case "-s":
                    o.AutoStartTimer = true;
                    break;
                case "--focus":
                    if (i + 1 < args.Length && int.TryParse(args[++i], out int minutes))
                        o.FocusMinutes = Math.Clamp(minutes, 1, 120);
                    break;
                case "--dark":
                    o.ForceLightDark = ThemePreference.Dark;
                    break;
                case "--light":
                    o.ForceLightDark = ThemePreference.Light;
                    break;
            }
        }
        return o;
    }
}
