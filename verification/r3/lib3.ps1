# lib3.ps1 -- Round-3 independent verification helpers (written from scratch for this round).
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$script:ProjRoot     = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro'
$script:Exe          = Join-Path $script:ProjRoot 'verify-dist-r3\FluentPomodoro.exe'
$script:AssetsDir    = Join-Path $script:ProjRoot 'artifacts\test-assets'
$script:SettingsDir  = Join-Path $env:APPDATA 'FluentPomodoro'
$script:SettingsPath = Join-Path $script:SettingsDir 'settings.json'
$script:HistoryPath  = Join-Path $script:SettingsDir 'history.json'
$script:ShotDir      = Join-Path $script:ProjRoot 'verification\r3'
$script:Results      = New-Object System.Collections.ArrayList

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

if (-not ('R3.Native' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace R3 {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public static class Native {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr p);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowLongW(IntPtr h, int i);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr ins, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr SetActiveWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr h);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("gdi32.dll")] public static extern uint GetPixel(IntPtr dc, int x, int y);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, uint data, IntPtr extra);
    [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr h, bool altTab);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr res);
    [DllImport("user32.dll")] public static extern IntPtr GetKeyboardLayout(uint tid);
  }

  // fast pixel math on 32bppArgb LockBits buffers (PowerShell pixel loops are far too slow)
  public static class Img {
    // returns {count,x0,y0,x1,y1}
    public static int[] Diff(byte[] a, byte[] b, int stride, int w, int h) {
      int n=0, x0=int.MaxValue, y0=int.MaxValue, x1=-1, y1=-1;
      for (int y=0; y<h; y++) {
        int row = y*stride;
        for (int x=0; x<w; x++) {
          int i = row + x*4;
          if (a[i]!=b[i] || a[i+1]!=b[i+1] || a[i+2]!=b[i+2]) {
            n++;
            if (x<x0) x0=x; if (x>x1) x1=x; if (y<y0) y0=y; if (y>y1) y1=y;
          }
        }
      }
      return new int[]{ n, x0, y0, x1, y1 };
    }
    // region stats: {n, sumR, sumG, sumB, modalR, modalG, modalB, modalCount, distinct}
    public static long[] Stats(byte[] px, int stride, int x, int y, int w, int h) {
      long n=0, sr=0, sg=0, sb=0; int mr=0, mg=0, mb=0, mc=0, distinct=0;
      var hist = new System.Collections.Generic.Dictionary<int,int>();
      for (int yy=y; yy<y+h; yy++) {
        if (yy<0) continue;
        int row = yy*stride;
        for (int xx=x; xx<x+w; xx++) {
          int i = row + xx*4;
          int r=px[i+2], g=px[i+1], bl=px[i];
          n++; sr+=r; sg+=g; sb+=bl;
          int key = (r<<16)|(g<<8)|bl;
          int c; hist.TryGetValue(key, out c); hist[key]=c+1;
          if (c+1 > mc) { mc=c+1; mr=r; mg=g; mb=bl; }
        }
      }
      distinct = hist.Count;
      return new long[]{ n, sr, sg, sb, mr, mg, mb, mc, distinct };
    }
    // count pixels exactly equal to a colour inside a region
    public static long CountColor(byte[] px, int stride, int x, int y, int w, int h, int r, int g, int b) {
      long n=0;
      for (int yy=y; yy<y+h; yy++) {
        int row = yy*stride;
        for (int xx=x; xx<x+w; xx++) {
          int i = row + xx*4;
          if (px[i]==b && px[i+1]==g && px[i+2]==r) n++;
        }
      }
      return n;
    }
    // bounding box of all pixels exactly equal to a colour across the whole bitmap
    // returns {count,x0,y0,x1,y1}
    public static int[] ColorBox(byte[] px, int stride, int w, int h, int r, int g, int b) {
      int n=0, x0=int.MaxValue, y0=int.MaxValue, x1=-1, y1=-1;
      for (int y=0; y<h; y++) {
        int row=y*stride;
        for (int x=0; x<w; x++) {
          int i=row+x*4;
          if (px[i]==b && px[i+1]==g && px[i+2]==r) {
            n++;
            if (x<x0) x0=x; if (x>x1) x1=x; if (y<y0) y0=y; if (y>y1) y1=y;
          }
        }
      }
      return new int[]{ n, x0, y0, x1, y1 };
    }
  }
}
'@
}

# ------------------------------------------------------------------ basics
function Get-Sha16([string]$Path) { (Get-FileHash $Path -Algorithm SHA256).Hash.Substring(0,16) }

function Stop-AllApp {
  Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 700
  $left = @(Get-Process FluentPomodoro -ErrorAction SilentlyContinue).Count
  return ($left -eq 0)
}

function Start-App {
  param([string[]]$CliArgs = @(), [int]$TimeoutSec = 25)
  [void](Stop-AllApp)
  $p = Start-Process -FilePath $script:Exe -ArgumentList $CliArgs -PassThru
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
    Start-Sleep -Milliseconds 250
    if ($p.HasExited) { return [pscustomobject]@{ Proc=$p; Pid=$p.Id; Hwnd=[IntPtr]::Zero; Exited=$true } }
    $h = Get-MainWindow -ProcId $p.Id
    if ($h -ne [IntPtr]::Zero) { return [pscustomobject]@{ Proc=$p; Pid=$p.Id; Hwnd=$h; Exited=$false } }
  }
  return [pscustomobject]@{ Proc=$p; Pid=$p.Id; Hwnd=[IntPtr]::Zero; Exited=$false }
}

# all visible top-level windows owned by the process, largest first
function Get-WindowsForPid {
  param([int]$ProcId)
  $script:_wins = New-Object System.Collections.ArrayList
  $cb = [R3.EnumWindowsProc]{
    param($h, $l)
    $owner = 0
    [void][R3.Native]::GetWindowThreadProcessId($h, [ref]$owner)
    if ($owner -eq $ProcId -and [R3.Native]::IsWindowVisible($h)) {
      $r = New-Object R3.RECT
      [void][R3.Native]::GetWindowRect($h, [ref]$r)
      $sb = New-Object System.Text.StringBuilder 512
      [void][R3.Native]::GetWindowText($h, $sb, 512)
      $cb2 = New-Object System.Text.StringBuilder 256
      [void][R3.Native]::GetClassName($h, $cb2, 256)
      $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
      [void]$script:_wins.Add([pscustomobject]@{
        Hwnd=$h; Title=$sb.ToString(); Class=$cb2.ToString()
        X=$r.Left; Y=$r.Top; W=$w; H=$ht; Area=($w*$ht)
      })
    }
    return $true
  }
  [void][R3.Native]::EnumWindows($cb, [IntPtr]::Zero)
  return @($script:_wins | Sort-Object -Property Area -Descending)
}

# largest visible top-level window whose title matches the regex ('' = any)
function Get-WindowByTitle {
  param([int]$ProcId, [string]$Pattern = '')
  $w = Get-WindowsForPid -ProcId $ProcId
  if ($Pattern -ne '') { $w = @($w | Where-Object { $_.Title -match $Pattern }) }
  if (@($w).Count -eq 0) { return [IntPtr]::Zero }
  return $w[0].Hwnd
}

# main window title is "<mm:ss> · <phase> · 微软风格番茄钟"; stats window title is exactly 专注统计
function Get-MainWindow   { param([int]$ProcId) Get-WindowByTitle -ProcId $ProcId -Pattern '微软风格番茄钟' }
function Get-StatsWindow  { param([int]$ProcId) Get-WindowByTitle -ProcId $ProcId -Pattern '^专注统计' }

# visible top-level windows that are neither main nor stats (i.e. WPF Popup / native dialog / toast)
function Get-OtherWindows {
  param([int]$ProcId)
  return @(Get-WindowsForPid -ProcId $ProcId |
    Where-Object { $_.Title -notmatch '微软风格番茄钟' -and $_.Title -notmatch '^专注统计' })
}

function Get-Rect {
  param([IntPtr]$Hwnd)
  $r = New-Object R3.RECT
  [void][R3.Native]::GetWindowRect($Hwnd, [ref]$r)
  return @{ X=$r.Left; Y=$r.Top; W=($r.Right-$r.Left); H=($r.Bottom-$r.Top) }
}
function Get-Title {
  param([IntPtr]$Hwnd)
  $sb = New-Object System.Text.StringBuilder 512
  [void][R3.Native]::GetWindowText($Hwnd, $sb, 512); return $sb.ToString()
}
function Get-Class {
  param([IntPtr]$Hwnd)
  $sb = New-Object System.Text.StringBuilder 256
  [void][R3.Native]::GetClassName($Hwnd, $sb, 256); return $sb.ToString()
}
function Get-Pixel {
  param([int]$X, [int]$Y)
  $dc = [R3.Native]::GetDC([IntPtr]::Zero)
  try { $c = [R3.Native]::GetPixel($dc, $X, $Y) } finally { [void][R3.Native]::ReleaseDC([IntPtr]::Zero, $dc) }
  if ($c -eq 0xFFFFFFFF) { return $null }
  return @{ R=[int]($c -band 0xFF); G=[int](($c -shr 8) -band 0xFF); B=[int](($c -shr 16) -band 0xFF) }
}
function Get-VirtualDesktop {
  @{ X=[R3.Native]::GetSystemMetrics(76); Y=[R3.Native]::GetSystemMetrics(77)
     W=[R3.Native]::GetSystemMetrics(78); H=[R3.Native]::GetSystemMetrics(79) }
}
function Test-Responsive {
  param([IntPtr]$Hwnd, [int]$TimeoutMs = 2000)
  $res = [IntPtr]::Zero
  $r = [R3.Native]::SendMessageTimeout($Hwnd, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero, 2, [uint32]$TimeoutMs, [ref]$res)
  return ($r -ne [IntPtr]::Zero)
}

# ------------------------------------------------------------------ bitmap capture
# capture the window into a Bitmap via PrintWindow (no cursor / no occlusion effects)
function Capture-Window {
  param([IntPtr]$Hwnd, [switch]$FromScreen)
  $r = Get-Rect $Hwnd
  if ($r.W -le 0 -or $r.H -le 0) { return $null }
  $bmp = New-Object System.Drawing.Bitmap($r.W, $r.H)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  if ($FromScreen) {
    $g.CopyFromScreen($r.X, $r.Y, 0, 0, (New-Object System.Drawing.Size($r.W, $r.H)))
  } else {
    $hdc = $g.GetHdc()
    try { $ok = [R3.Native]::PrintWindow($Hwnd, $hdc, 2) } finally { $g.ReleaseHdc($hdc) }
    if (-not $ok) { $g.CopyFromScreen($r.X, $r.Y, 0, 0, (New-Object System.Drawing.Size($r.W, $r.H))) }
  }
  $g.Dispose()
  return $bmp
}
function Save-Bmp {
  param($Bmp, [string]$Name)
  $path = Join-Path $script:ShotDir $Name
  $Bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  return $path
}
# screenshot of the on-screen window rect (for eyeballing), avoids PrintWindow quirks
function Save-Shot {
  param([string]$Name, [IntPtr]$Hwnd = [IntPtr]::Zero, [switch]$FullScreen)
  if ($FullScreen) { $r = @{ X=0; Y=0; W=[R3.Native]::GetSystemMetrics(0); H=[R3.Native]::GetSystemMetrics(1) } }
  else { $r = Get-Rect $Hwnd }
  if ($r.W -le 0 -or $r.H -le 0) { return $null }
  $bmp = New-Object System.Drawing.Bitmap($r.W, $r.H)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.X, $r.Y, 0, 0, (New-Object System.Drawing.Size($r.W, $r.H)))
  $g.Dispose()
  return (Save-Bmp -Bmp $bmp -Name $Name)
}
function Get-BmpPixel {
  param($Bmp, [int]$X, [int]$Y)
  if ($X -lt 0 -or $Y -lt 0 -or $X -ge $Bmp.Width -or $Y -ge $Bmp.Height) { return $null }
  $c = $Bmp.GetPixel($X, $Y)
  return @{ R=[int]$c.R; G=[int]$c.G; B=[int]$c.B }
}
# pull the whole bitmap into a 32bppArgb byte buffer for fast C#-side math
function Get-BmpBytes {
  param($Bmp)
  $rect = New-Object System.Drawing.Rectangle(0,0,$Bmp.Width,$Bmp.Height)
  $d = $Bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  try {
    $buf = New-Object byte[] ($d.Stride * $Bmp.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($d.Scan0, $buf, 0, $buf.Length)
    return [pscustomobject]@{ Bytes=$buf; Stride=$d.Stride; W=$Bmp.Width; H=$Bmp.Height }
  } finally { $Bmp.UnlockBits($d) }
}
function Get-BufPixel {
  param($Buf, [int]$X, [int]$Y)
  if ($X -lt 0 -or $Y -lt 0 -or $X -ge $Buf.W -or $Y -ge $Buf.H) { return $null }
  $i = $Y*$Buf.Stride + $X*4
  return @{ R=[int]$Buf.Bytes[$i+2]; G=[int]$Buf.Bytes[$i+1]; B=[int]$Buf.Bytes[$i] }
}
function Get-BmpStats {
  param($Bmp, [int]$X, [int]$Y, [int]$W, [int]$H)
  $buf = Get-BmpBytes -Bmp $Bmp
  return Get-BufStats -Buf $buf -X $X -Y $Y -W $W -H $H
}
function Get-BufStats {
  param($Buf, [int]$X, [int]$Y, [int]$W, [int]$H)
  $s = [R3.Img]::Stats($Buf.Bytes, $Buf.Stride, $X, $Y, $W, $H)
  if ($s[0] -eq 0) { return $null }
  $avgR = $s[1]/$s[0]; $avgG = $s[2]/$s[0]; $avgB = $s[3]/$s[0]
  return [pscustomobject]@{
    Total=$s[0]; Modal=('{0},{1},{2}' -f $s[4],$s[5],$s[6]); ModalCount=$s[7]; Distinct=$s[8]
    AvgR=[math]::Round($avgR,1); AvgG=[math]::Round($avgG,1); AvgB=[math]::Round($avgB,1)
    Lum=[math]::Round((0.2126*$avgR + 0.7152*$avgG + 0.0722*$avgB)/255.0, 4)
  }
}
# compare two bitmaps (or two byte buffers) of identical size -> diff count + bbox
function Compare-Bitmaps {
  param($A, $B)
  $ba = if ($A.PSObject.Properties.Name -contains 'Bytes') { $A } else { Get-BmpBytes -Bmp $A }
  $bb = if ($B.PSObject.Properties.Name -contains 'Bytes') { $B } else { Get-BmpBytes -Bmp $B }
  if ($ba.W -ne $bb.W -or $ba.H -ne $bb.H -or $ba.Stride -ne $bb.Stride) {
    return [pscustomobject]@{ Same=$false; SizeMismatch=$true; Diff=-1; X0=0;Y0=0;X1=0;Y1=0 }
  }
  $d = [R3.Img]::Diff($ba.Bytes, $bb.Bytes, $ba.Stride, $ba.W, $ba.H)
  return [pscustomobject]@{ Same=($d[0] -eq 0); SizeMismatch=$false; Diff=$d[0]; X0=$d[1];Y0=$d[2];X1=$d[3];Y1=$d[4] }
}
# bounding box of pixels exactly equal to a colour, over a region of a buffer
function Get-BufColorBox {
  param($Buf, [int]$R, [int]$G, [int]$B, [int]$X = 0, [int]$Y = 0, [int]$W = -1, [int]$H = -1)
  if ($W -lt 0) { $W = $Buf.W - $X }
  if ($H -lt 0) { $H = $Buf.H - $Y }
  # restrict by blanking an offset: reuse ColorBox on a sub-region by scanning manually
  $x0=[int]::MaxValue; $y0=[int]::MaxValue; $x1=-1; $y1=-1; $n=0
  for ($yy=$Y; $yy -lt ($Y+$H); $yy++) {
    $row = $yy*$Buf.Stride
    for ($xx=$X; $xx -lt ($X+$W); $xx++) {
      $i = $row + $xx*4
      if ($Buf.Bytes[$i] -eq $B -and $Buf.Bytes[$i+1] -eq $G -and $Buf.Bytes[$i+2] -eq $R) {
        $n++
        if ($xx -lt $x0) { $x0=$xx }; if ($xx -gt $x1) { $x1=$xx }
        if ($yy -lt $y0) { $y0=$yy }; if ($yy -gt $y1) { $y1=$yy }
      }
    }
  }
  return [pscustomobject]@{ Count=$n; X0=$x0; Y0=$y0; X1=$x1; Y1=$y1 }
}
function Count-BufColor {
  param($Buf, [int]$R, [int]$G, [int]$B, [int]$X, [int]$Y, [int]$W, [int]$H)
  return [R3.Img]::CountColor($Buf.Bytes, $Buf.Stride, $X, $Y, $W, $H, $R, $G, $B)
}
function Crop-Scale-Bmp {
  param($Bmp, [int]$X, [int]$Y, [int]$W, [int]$H, [int]$Scale = 1)
  $out = New-Object System.Drawing.Bitmap(($W*$Scale), ($H*$Scale))
  $g = [System.Drawing.Graphics]::FromImage($out)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
  $src = New-Object System.Drawing.Rectangle($X,$Y,$W,$H)
  $dst = New-Object System.Drawing.Rectangle(0,0,($W*$Scale),($H*$Scale))
  $g.DrawImage($Bmp, $dst, $src, [System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose()
  return $out
}

# ------------------------------------------------------------------ config files
function Ensure-ConfigDir { if (-not (Test-Path $script:SettingsDir)) { New-Item -ItemType Directory -Force -Path $script:SettingsDir | Out-Null } }
function Write-SettingsRaw([string]$Json) { Ensure-ConfigDir; [IO.File]::WriteAllText($script:SettingsPath, $Json, (New-Object System.Text.UTF8Encoding($false))) }
function Write-SettingsObj($Obj) { Write-SettingsRaw ($Obj | ConvertTo-Json -Depth 8) }
function Read-SettingsRaw { if (Test-Path $script:SettingsPath) { [IO.File]::ReadAllText($script:SettingsPath) } else { $null } }
function Read-Settings { (Read-SettingsRaw) | ConvertFrom-Json }
function Write-HistoryRaw([string]$Json) { Ensure-ConfigDir; [IO.File]::WriteAllText($script:HistoryPath, $Json, (New-Object System.Text.UTF8Encoding($false))) }
function Read-HistoryRaw { if (Test-Path $script:HistoryPath) { [IO.File]::ReadAllText($script:HistoryPath) } else { $null } }
function Remove-ConfigFiles {
  foreach ($f in @($script:SettingsPath, $script:HistoryPath)) { if (Test-Path $f) { Remove-Item -Force $f } }
}

# deterministic baseline settings: light theme, no Mica, no auto big screen, no sound,
# no auto-start, window at the default 640x780. Tests override individual keys.
function Get-BaseSettings {
  return [ordered]@{
    FocusMinutes=25; ShortBreakMinutes=5; LongBreakMinutes=15; LongBreakInterval=4
    AutoStartNext=$false; SoundEnabled=$false; KeepScreenAwake=$false; AlwaysOnTop=$false
    NotifyOnPhaseEnd=$false; FocusLock=$false; AutoBigScreenOnFocus=$false
    Theme='Light'; UseMicaBackdrop=$false
    ShowClock=$true
    BackgroundImagePath=''; BackgroundFolder=''; BackgroundRotateMinutes=0
    BackgroundRotateOnFocus=$true; BackgroundOpacity=0.95; BackgroundUseImageAccent=$true
    NoiseTracks=@(); NoiseVolume=70; NoiseAutoPlayOnFocus=$false; NoiseOnlyDuringFocus=$true; NoiseShuffle=$false
    BigScreen='Mega'; BigScreenTopmost=$false
    HasWindowBounds=$false; WindowLeft=0; WindowTop=0; WindowWidth=640; WindowHeight=780
    StatsDate=''; CompletedToday=0; FocusMinutesToday=0; TotalCompleted=0; StreakDays=0; LastCompletedDate=''
  }
}
function Set-BaseSettings {
  param([hashtable]$Override = @{}, [string[]]$Remove = @())
  $s = Get-BaseSettings
  foreach ($k in $Override.Keys) { $s[$k] = $Override[$k] }
  foreach ($k in $Remove) { [void]$s.Remove($k) }
  Write-SettingsObj $s
  return $s
}

# ------------------------------------------------------------------ input
function Focus-Window([IntPtr]$Hwnd) {
  $fg = [R3.Native]::GetForegroundWindow()
  $fgTid = [R3.Native]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
  $myTid = [R3.Native]::GetCurrentThreadId()
  [void][R3.Native]::AttachThreadInput($myTid, $fgTid, $true)
  [void][R3.Native]::SetForegroundWindow($Hwnd)
  [void][R3.Native]::SetActiveWindow($Hwnd)
  [void][R3.Native]::SetFocus($Hwnd)
  [void][R3.Native]::AttachThreadInput($myTid, $fgTid, $false)
  Start-Sleep -Milliseconds 250
  if ([R3.Native]::GetForegroundWindow() -ne $Hwnd) {
    try { $ws = New-Object -ComObject WScript.Shell; $pid2=0
          [void][R3.Native]::GetWindowThreadProcessId($Hwnd, [ref]$pid2); [void]$ws.AppActivate($pid2) } catch { }
    Start-Sleep -Milliseconds 350
  }
  if ([R3.Native]::GetForegroundWindow() -ne $Hwnd) { [R3.Native]::SwitchToThisWindow($Hwnd, $true); Start-Sleep -Milliseconds 350 }
  return ([R3.Native]::GetForegroundWindow() -eq $Hwnd)
}
function Assert-Foreground([IntPtr]$Hwnd) { return ([R3.Native]::GetForegroundWindow() -eq $Hwnd) }
function Click-Window([IntPtr]$Hwnd, [double]$Frac = 0.62) {
  $r = Get-Rect $Hwnd
  $x = $r.X + [int]($r.W/2); $y = $r.Y + [int]($r.H*$Frac)
  [void][R3.Native]::SetCursorPos($x,$y); Start-Sleep -Milliseconds 150
  [R3.Native]::mouse_event(0x0002,0,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 60
  [R3.Native]::mouse_event(0x0004,0,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 500
  return ([R3.Native]::GetForegroundWindow() -eq $Hwnd)
}
function Activate-App([IntPtr]$Hwnd) {
  if ([R3.Native]::GetForegroundWindow() -eq $Hwnd) { return $true }
  [void](Focus-Window $Hwnd)
  if ([R3.Native]::GetForegroundWindow() -eq $Hwnd) { return $true }
  [void](Click-Window $Hwnd)
  return ([R3.Native]::GetForegroundWindow() -eq $Hwnd)
}
function Send-VKey { param([int]$Vk, [int]$Times = 1)
  for ($i=0; $i -lt $Times; $i++) {
    [R3.Native]::keybd_event([byte]$Vk,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 45
    [R3.Native]::keybd_event([byte]$Vk,0,2,[IntPtr]::Zero); Start-Sleep -Milliseconds 130
  }
}
function Send-CtrlKey { param([IntPtr]$Hwnd, [int]$Vk)
  [void](Activate-App $Hwnd)
  [R3.Native]::keybd_event(0x11,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 70
  [R3.Native]::keybd_event([byte]$Vk,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 60
  [R3.Native]::keybd_event([byte]$Vk,0,2,[IntPtr]::Zero); Start-Sleep -Milliseconds 40
  [R3.Native]::keybd_event(0x11,0,2,[IntPtr]::Zero); Start-Sleep -Milliseconds 250
}
function Post-Key { param([IntPtr]$Hwnd, [int]$Vk, [int]$Times = 1)
  for ($i=0; $i -lt $Times; $i++) {
    [void][R3.Native]::PostMessageW($Hwnd,0x0100,[IntPtr]$Vk,[IntPtr]0); Start-Sleep -Milliseconds 60
    [void][R3.Native]::PostMessageW($Hwnd,0x0101,[IntPtr]$Vk,[IntPtr]0); Start-Sleep -Milliseconds 160
  }
}
function Send-ForceQuit([IntPtr]$Hwnd) {
  [void](Activate-App $Hwnd)
  [R3.Native]::keybd_event(0x11,0,0,[IntPtr]::Zero)
  [R3.Native]::keybd_event(0x10,0,0,[IntPtr]::Zero)
  Start-Sleep -Milliseconds 90
  [R3.Native]::keybd_event(0x51,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 60
  [R3.Native]::keybd_event(0x51,0,2,[IntPtr]::Zero)
  [R3.Native]::keybd_event(0x10,0,2,[IntPtr]::Zero)
  [R3.Native]::keybd_event(0x11,0,2,[IntPtr]::Zero)
}
function Paste-Text { param([string]$Text)
  Set-Clipboard -Value $Text
  Start-Sleep -Milliseconds 250
  [R3.Native]::keybd_event(0x11,0,0,[IntPtr]::Zero)
  [R3.Native]::keybd_event(0x56,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 70
  [R3.Native]::keybd_event(0x56,0,2,[IntPtr]::Zero)
  [R3.Native]::keybd_event(0x11,0,2,[IntPtr]::Zero)
  Start-Sleep -Milliseconds 350
}
function Wait-Exit { param([int]$Pid2, [int]$Sec = 8)
  $sw=[Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $Sec) {
    if (-not (Get-Process -Id $Pid2 -ErrorAction SilentlyContinue)) { return $true }
    Start-Sleep -Milliseconds 200
  }
  return $false
}

# ------------------------------------------------------------------ checks
function Check { param([string]$Name, [bool]$Ok, [string]$Observed)
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  [void]$script:Results.Add([pscustomobject]@{ Check=$Name; Ok=$Ok; Observed=$Observed })
  Write-Host ("[{0}] {1} :: {2}" -f $tag,$Name,$Observed)
}
function Summary {
  $f = @($script:Results | Where-Object { -not $_.Ok }).Count
  Write-Host ("=" * 78)
  Write-Host ("TOTAL {0} / {1} passed, {2} failed" -f (@($script:Results).Count - $f), @($script:Results).Count, $f)
  Write-Host ("=" * 78)
  return @($script:Results)
}

# ------------------------------------------------------------------ UI Automation
$script:UiaLoaded = $false
function Ensure-Uia {
  if (-not $script:UiaLoaded) {
    Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
    Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
    $script:UiaLoaded = $true
  }
}
function Uia-Root([IntPtr]$Hwnd) {
  Ensure-Uia
  try { return [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd) } catch { return $null }
}
function Uia-ById([IntPtr]$Hwnd, [string]$Id) {
  $root = Uia-Root $Hwnd; if ($null -eq $root) { return $null }
  try {
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $Id)
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
  } catch { return $null }
}
function Uia-ByName([IntPtr]$Hwnd, [string]$Name) {
  $root = Uia-Root $Hwnd; if ($null -eq $root) { return $null }
  try {
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name)
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
  } catch { return $null }
}
function Uia-Text([IntPtr]$Hwnd, [string]$Id) {
  $e = Uia-ById $Hwnd $Id; if ($null -eq $e) { return '<not found>' }
  try { return $e.Current.Name } catch { return '<error>' }
}
function Uia-Click([IntPtr]$Hwnd, [string]$Id) {
  $e = Uia-ById $Hwnd $Id; if ($null -eq $e) { return $false }
  try { $e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); return $true } catch { return $false }
}
function Uia-ClickName([IntPtr]$Hwnd, [string]$Name) {
  $e = Uia-ByName $Hwnd $Name; if ($null -eq $e) { return $false }
  try { $e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); return $true } catch { return $false }
}
function Uia-SetRange([IntPtr]$Hwnd, [string]$Id, [double]$Value) {
  $e = Uia-ById $Hwnd $Id; if ($null -eq $e) { return $false }
  try { $e.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern).SetValue($Value); return $true } catch { return $false }
}
function Uia-Range([IntPtr]$Hwnd, [string]$Id) {
  $e = Uia-ById $Hwnd $Id; if ($null -eq $e) { return $null }
  try { return $e.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern).Current.Value } catch { return $null }
}
function Uia-Toggle([IntPtr]$Hwnd, [string]$Id) {
  $e = Uia-ById $Hwnd $Id; if ($null -eq $e) { return '<not found>' }
  try { return $e.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState.ToString() } catch { return '<error>' }
}
# flip a CheckBox/ToggleSwitch through its real automation peer (TogglePattern)
function Uia-ToggleIt([IntPtr]$Hwnd, [string]$Id) {
  $e = Uia-ById $Hwnd $Id; if ($null -eq $e) { return $false }
  try { $e.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle(); return $true } catch { return $false }
}
# screen-space bounding rectangle of an element by AutomationId
function Uia-RectById([IntPtr]$Hwnd, [string]$Id) {
  $e = Uia-ById $Hwnd $Id; if ($null -eq $e) { return $null }
  try {
    $r = $e.Current.BoundingRectangle
    if ($r.IsEmpty) { return $null }
    return @{ X=[int]$r.X; Y=[int]$r.Y; W=[int]$r.Width; H=[int]$r.Height }
  } catch { return $null }
}
function Uia-RectByName([IntPtr]$Hwnd, [string]$Name) {
  $e = Uia-ByName $Hwnd $Name; if ($null -eq $e) { return $null }
  try {
    $r = $e.Current.BoundingRectangle
    if ($r.IsEmpty) { return $null }
    return @{ X=[int]$r.X; Y=[int]$r.Y; W=[int]$r.Width; H=[int]$r.Height }
  } catch { return $null }
}
function Uia-Dump([IntPtr]$Hwnd) {
  $root = Uia-Root $Hwnd; if ($null -eq $root) { return @() }
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $out = @()
  foreach ($e in $all) {
    try { $out += [pscustomobject]@{ Id=$e.Current.AutomationId; Type=$e.Current.ControlType.ProgrammaticName; Name=$e.Current.Name } } catch { }
  }
  return $out
}
