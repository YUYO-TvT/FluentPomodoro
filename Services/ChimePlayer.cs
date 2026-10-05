using System.IO;
using System.Runtime.InteropServices;
using FluentPomodoro.Interop;

namespace FluentPomodoro.Services;

/// <summary>
/// 阶段结束提示音：运行时合成一小段带谐波衰减的“叮”声 WAV，
/// 通过 winmm!PlaySound 异步播放（内存指针常驻固定，避免 GC 移动）。
/// </summary>
internal static class ChimePlayer
{
    private const int SampleRate = 44100;

    private static GCHandle _focusHandle;
    private static GCHandle _breakHandle;
    private static bool _ready;

    public static bool IsReady => _ready;

    public static void Prepare()
    {
        if (_ready) return;
        try
        {
            var focus = Synthesize(new[]
            {
                (880.00, 0.00, 0.34),   // A5
                (1108.73, 0.16, 0.34),  // C#6
                (1318.51, 0.32, 0.70)   // E6
            });
            var rest = Synthesize(new[]
            {
                (1318.51, 0.00, 0.30),  // E6
                (987.77, 0.17, 0.34),   // B5
                (659.25, 0.36, 0.78)    // E5
            });

            _focusHandle = GCHandle.Alloc(focus, GCHandleType.Pinned);
            _breakHandle = GCHandle.Alloc(rest, GCHandleType.Pinned);
            _ready = true;
        }
        catch
        {
            _ready = false;
        }
    }

    /// <summary>播放提示音：专注结束用上行音，休息结束用下行音。返回是否成功提交播放。</summary>
    public static bool PlayPhaseEnd(PhaseKind finishedPhase)
    {
        if (!_ready) return false;
        try
        {
            var handle = finishedPhase == PhaseKind.Focus ? _focusHandle : _breakHandle;
            if (!handle.IsAllocated) return false;
            return Native.PlaySound(handle.AddrOfPinnedObject(), IntPtr.Zero,
                Native.SND_MEMORY | Native.SND_ASYNC | Native.SND_NODEFAULT);
        }
        catch
        {
            // 播放失败不影响功能
            return false;
        }
    }

    /// <summary>试听（专注结束提示音）。</summary>
    public static bool Preview()
    {
        Prepare();
        return PlayPhaseEnd(PhaseKind.Focus);
    }

    public static void Stop()
    {
        try
        {
            Native.PlaySound(IntPtr.Zero, IntPtr.Zero, 0);
        }
        catch
        {
            // ignore
        }
    }

    /// <summary>退出时释放固定住的内存句柄（播放期间不可释放，故只在窗口关闭时调用）。</summary>
    public static void Release()
    {
        Stop();
        try
        {
            if (_focusHandle.IsAllocated) _focusHandle.Free();
            if (_breakHandle.IsAllocated) _breakHandle.Free();
        }
        catch
        {
            // ignore
        }
        finally
        {
            _ready = false;
        }
    }

    private static byte[] Synthesize((double Frequency, double Start, double Length)[] notes)
    {
        double total = notes.Max(n => n.Start + n.Length) + 0.08;
        int sampleCount = (int)(total * SampleRate);
        var buffer = new double[sampleCount];

        foreach (var (frequency, start, length) in notes)
        {
            int offset = (int)(start * SampleRate);
            int count = (int)(length * SampleRate);
            for (int i = 0; i < count && offset + i < sampleCount; i++)
            {
                double t = (double)i / SampleRate;
                double attack = Math.Min(1.0, t / 0.006);
                double decay = Math.Exp(-t / (length * 0.42));
                double wave =
                    Math.Sin(2 * Math.PI * frequency * t) +
                    0.30 * Math.Sin(2 * Math.PI * frequency * 2 * t) +
                    0.10 * Math.Sin(2 * Math.PI * frequency * 3 * t);
                buffer[offset + i] += wave * attack * decay * 0.30;
            }
        }

        double peak = 0;
        foreach (double v in buffer) peak = Math.Max(peak, Math.Abs(v));
        double gain = peak > 0.98 ? 0.98 / peak : 1.0;

        int dataBytes = sampleCount * 2;
        using var stream = new MemoryStream(44 + dataBytes);
        using var writer = new BinaryWriter(stream);

        writer.Write(new byte[] { (byte)'R', (byte)'I', (byte)'F', (byte)'F' });
        writer.Write(36 + dataBytes);
        writer.Write(new byte[] { (byte)'W', (byte)'A', (byte)'V', (byte)'E' });
        writer.Write(new byte[] { (byte)'f', (byte)'m', (byte)'t', (byte)' ' });
        writer.Write(16);
        writer.Write((short)1);              // PCM
        writer.Write((short)1);              // 单声道
        writer.Write(SampleRate);
        writer.Write(SampleRate * 2);        // byte rate
        writer.Write((short)2);              // block align
        writer.Write((short)16);             // 位深
        writer.Write(new byte[] { (byte)'d', (byte)'a', (byte)'t', (byte)'a' });
        writer.Write(dataBytes);

        foreach (double v in buffer)
        {
            short sample = (short)Math.Round(Math.Clamp(v * gain, -1.0, 1.0) * short.MaxValue);
            writer.Write(sample);
        }

        writer.Flush();
        return stream.ToArray();
    }
}
