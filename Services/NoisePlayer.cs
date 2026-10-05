using System.IO;
using System.Windows.Media;

namespace FluentPomodoro.Services;

/// <summary>
/// 白噪音播放器：播放用户导入的音频文件（MediaPlayer 支持 mp3 / wav / wma / m4a 等系统解码格式），
/// 单曲循环、多曲顺序或随机、可调音量，并支持「仅专注时播放」。
/// </summary>
public sealed class NoisePlayer : IDisposable
{
    private readonly MediaPlayer _player = new();
    private readonly Random _random = new();
    private readonly List<string> _tracks = new();

    private int _index = -1;
    private bool _playing;
    private bool _advancing;
    private int _volume = 70;
    private bool _shuffle = true;

    public NoisePlayer()
    {
        _player.MediaEnded += (_, _) => Next(auto: true);
        _player.MediaFailed += (_, args) =>
        {
            LastError = args.ErrorException?.Message ?? "无法播放该音频文件";
            TrackFailed?.Invoke(this, LastError);
            _failedCount++;

            // 单曲或连续失败已达曲目数：停止，避免无限重试
            if (_tracks.Count <= 1 || _failedCount >= _tracks.Count)
            {
                Stop();
                return;
            }
            Next(auto: true);
        };
    }

    private int _failedCount;

    public event EventHandler<string>? TrackFailed;

    public event EventHandler? StateChanged;

    public string? LastError { get; private set; }

    public IReadOnlyList<string> Tracks => _tracks;

    public bool IsPlaying => _playing;

    public string? CurrentTrack => _index >= 0 && _index < _tracks.Count ? _tracks[_index] : null;

    public int Volume
    {
        get => _volume;
        set
        {
            _volume = Math.Clamp(value, 0, 100);
            _player.Volume = _volume / 100.0;
        }
    }

    public bool Shuffle
    {
        get => _shuffle;
        set => _shuffle = value;
    }

    public void SetTracks(IEnumerable<string> tracks)
    {
        var wasPlaying = _playing;
        _tracks.Clear();
        foreach (var track in tracks)
        {
            if (!string.IsNullOrWhiteSpace(track) && File.Exists(track)) _tracks.Add(track);
        }

        _index = -1;
        if (_tracks.Count == 0)
        {
            Stop();
            return;
        }

        if (wasPlaying) Next(auto: true);
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public bool Play()
    {
        if (_tracks.Count == 0)
        {
            LastError = "还没有导入白噪音音频";
            return false;
        }

        if (_index < 0) _index = _shuffle && _tracks.Count > 1 ? _random.Next(_tracks.Count) : 0;

        try
        {
            if (_player.Source is null) OpenCurrent();
            _player.Play();
            _playing = true;
            StateChanged?.Invoke(this, EventArgs.Empty);
            return true;
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
            return false;
        }
    }

    public void Pause()
    {
        try
        {
            _player.Pause();
        }
        catch
        {
            // ignore
        }
        _playing = false;
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Stop()
    {
        try
        {
            _player.Stop();
            _player.Close();
        }
        catch
        {
            // ignore
        }
        _playing = false;
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Toggle()
    {
        if (_playing) Pause();
        else Play();
    }

    /// <summary>下一首；auto 表示由播放结束/失败自动触发。</summary>
    public bool Next(bool auto = false)
    {
        if (_tracks.Count == 0) return false;
        if (_advancing) return false;

        _advancing = true;
        try
        {
            if (_tracks.Count == 1)
            {
                _index = 0;
            }
            else if (_shuffle)
            {
                do
                {
                    _index = _random.Next(_tracks.Count);
                } while (_index == PreviousIndex);
            }
            else
            {
                _index = (_index + 1) % _tracks.Count;
            }

            PreviousIndex = _index;
            OpenCurrent();
            if (_playing || auto)
            {
                _player.Play();
                _playing = true;
            }
            StateChanged?.Invoke(this, EventArgs.Empty);
            return true;
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
            return false;
        }
        finally
        {
            _advancing = false;
        }
    }

    private int PreviousIndex { get; set; } = -1;

    private void OpenCurrent()
    {
        _player.Close();
        _player.Open(new Uri(_tracks[_index], UriKind.Absolute));
        _player.Volume = _volume / 100.0;
        _failedCount = 0;
    }

    public void Dispose()
    {
        try
        {
            _player.Close();
        }
        catch
        {
            // ignore
        }
    }
}
