# Shared helpers for independent verification of FluentPomodoro.
# Read-only w.r.t. app sources; only writes to verification\ and %APPDATA%\FluentPomodoro.

$script:VerifyResults = @()

function Add-Check([string]$name, [bool]$ok, [string]$detail = '') {
    $script:VerifyResults += [pscustomobject]@{ Check = $name; Pass = $ok; Detail = $detail }
    $tag = if ($ok) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1} :: {2}" -f $tag, $name, $detail)
}

function Get-VerifyResults { $script:VerifyResults }

function Assert-NoAppRunning {
    $p = Get-Process FluentPomodoro -ErrorAction SilentlyContinue
    if ($p) {
        Write-Host "Killing leftover FluentPomodoro processes: $($p.Id -join ',')"
        $p | Stop-Process -Force
        Start-Sleep -Milliseconds 800
    }
}

function Get-SettingsPath { Join-Path $env:APPDATA 'FluentPomodoro\settings.json' }

function Write-Settings([System.Collections.IDictionary]$overrides) {
    $defaults = [ordered]@{
        FocusMinutes = 25; ShortBreakMinutes = 5; LongBreakMinutes = 15; LongBreakInterval = 4
        AutoStartNext = $true; SoundEnabled = $true; KeepScreenAwake = $true; AlwaysOnTop = $true
        NotifyOnPhaseEnd = $true; FocusLock = $false; AutoBigScreenOnFocus = $true
        Theme = 'System'; UseMicaBackdrop = $true
        BigScreen = 'Mega'; BigScreenTopmost = $true
        HasWindowBounds = $false; WindowLeft = 0; WindowTop = 0; WindowWidth = 640; WindowHeight = 780
        StatsDate = ''; CompletedToday = 0; FocusMinutesToday = 0; TotalCompleted = 0
        StreakDays = 0; LastCompletedDate = ''
    }
    foreach ($k in $overrides.Keys) { $defaults[$k] = $overrides[$k] }
    $dir = Split-Path -Parent (Get-SettingsPath)
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    ($defaults | ConvertTo-Json -Depth 4) | Set-Content -Path (Get-SettingsPath) -Encoding UTF8
}

function Read-Settings {
    $p = Get-SettingsPath
    if (-not (Test-Path $p)) { return $null }
    return (Get-Content $p -Raw | ConvertFrom-Json)
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class VU {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr wp, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, int msg, IntPtr wp, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  // Process.MainWindowHandle returns 0 for windows owned by a hidden owner (WPF ShowInTaskbar=false),
  // so fall back to enumerating the process's own visible HwndWrapper windows.
  public static IntPtr FindAppWindow(uint pid) {
    IntPtr best = IntPtr.Zero; int bestArea = 0;
    EnumWindows((h, l) => {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p == pid && IsWindowVisible(h)) {
        var c = new StringBuilder(256); GetClassNameW(h, c, 256);
        if (c.ToString().StartsWith("HwndWrapper[FluentPomodoro")) {
          RECT r; GetWindowRect(h, out r);
          int area = (r.R - r.L) * (r.B - r.T);
          if (area > bestArea) { bestArea = area; best = h; }
        }
      }
      return true;
    }, IntPtr.Zero);
    return best;
  }
  public struct RECT { public int L,T,R,B; }
  public struct POINT { public int X,Y; }
}
"@

function Get-AppHwnd {
    $p = Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { return [IntPtr]::Zero }
    $h = $p.MainWindowHandle
    if ($h -ne [IntPtr]::Zero) {
        $root = [VU]::GetAncestor($h, 2)
        if ($root -ne [IntPtr]::Zero) { return $root }
        return $h
    }
    return [VU]::FindAppWindow([uint32]$p.Id)
}

function Get-Rect([IntPtr]$h) {
    $r = New-Object VU+RECT
    [void][VU]::GetWindowRect($h, [ref]$r)
    return $r
}

function Get-Title([IntPtr]$h) {
    $sb = New-Object System.Text.StringBuilder 512
    [void][VU]::GetWindowTextW($h, $sb, 512)
    return $sb.ToString()
}

function Format-Rect([IntPtr]$h) {
    $r = Get-Rect $h
    return ("{0}x{1} @ ({2},{3})" -f ($r.R - $r.L), ($r.B - $r.T), $r.L, $r.T)
}

function Save-Shot([string]$file, [IntPtr]$h) {
    $r = Get-Rect $h
    $w = $r.R - $r.L; $ht = $r.B - $r.T
    if ($w -le 0 -or $ht -le 0) { return }
    $bmp = [System.Drawing.Bitmap]::new($w, $ht, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [void][VU]::PrintWindow($h, $hdc, 2)
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Host "  screenshot: $file ($w x $ht)"
}

function Save-Crop([string]$file, [IntPtr]$h, [int]$x, [int]$y, [int]$w, [int]$h2) {
    $r = Get-Rect $h
    $full = [System.Drawing.Bitmap]::new(($r.R - $r.L), ($r.B - $r.T), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($full)
    $hdc = $g.GetHdc()
    [void][VU]::PrintWindow($h, $hdc, 2)
    $g.ReleaseHdc($hdc); $g.Dispose()
    $rect = [System.Drawing.Rectangle]::new($x, $y, [Math]::Min($w, $full.Width - $x), [Math]::Min($h2, $full.Height - $y))
    $crop = $full.Clone($rect, $full.PixelFormat)
    $crop.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $crop.Dispose(); $full.Dispose()
    Write-Host "  screenshot(crop ${w}x${h2}@${x},${y}): $file"
}

function Get-ExStyle([IntPtr]$h) { return [VU]::GetWindowLong($h, -20) }
function Test-Topmost([IntPtr]$h) { return (([VU]::GetWindowLong($h, -20)) -band 0x8) -ne 0 }
function Test-ToolWindow([IntPtr]$h) { return (([VU]::GetWindowLong($h, -20)) -band 0x80) -ne 0 }

function Save-Screen([string]$file) {
    $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = [System.Drawing.Bitmap]::new($vs.Width, $vs.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($vs.Left, $vs.Top, 0, 0, $bmp.Size); $g.Dispose()
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Host "  screenshot: $file ($($vs.Width) x $($vs.Height))"
}

function Focus-App {
    $h = Get-AppHwnd
    if ($h -eq [IntPtr]::Zero) { return $false }
    [void][VU]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 400
    return ([VU]::GetForegroundWindow() -eq $h)
}

function Click-At([int]$x, [int]$y) {
    [void][VU]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 200
    [VU]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80
    [VU]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 450
}

function Send-Keys([string]$keys, [int]$settleMs = 500) {
    [void](Focus-App)
    [System.Windows.Forms.SendKeys]::SendWait($keys)
    Start-Sleep -Milliseconds $settleMs
}

function Wait-AppWindow([int]$timeoutSec = 20) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        $h = Get-AppHwnd
        if ($h -ne [IntPtr]::Zero) { return $h }
        Start-Sleep -Milliseconds 300
    }
    return [IntPtr]::Zero
}
