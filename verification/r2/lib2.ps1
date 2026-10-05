# lib2.ps1 -- Round-2 independent verification helpers (written from scratch, no author code reused)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$script:ProjRoot = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro'
$script:Exe      = if ($env:R2_EXE) { $env:R2_EXE } else { Join-Path $script:ProjRoot 'verify-dist-r2\FluentPomodoro.exe' }
$script:SettingsDir = Join-Path $env:APPDATA 'FluentPomodoro'
$script:SettingsPath = Join-Path $script:SettingsDir 'settings.json'
$script:ShotDir  = Join-Path $script:ProjRoot 'verification\r2'
$script:Results  = New-Object System.Collections.ArrayList

if (-not ('R2.Native' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace R2 {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public static class Native {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr p);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowLongW(IntPtr h, int i);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr ins, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr SetActiveWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetFocus();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("gdi32.dll")] public static extern uint GetPixel(IntPtr dc, int x, int y);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
    [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] public static extern IntPtr GetKeyboardLayout(uint tid);
    [DllImport("user32.dll")] public static extern IntPtr ActivateKeyboardLayout(IntPtr hkl, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr LoadKeyboardLayoutW(string id, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr GetProp(IntPtr h, string name);
    [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr h, bool altTab);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, uint data, IntPtr extra);
    [DllImport("imm32.dll")] public static extern IntPtr ImmGetDefaultIMEWnd(IntPtr h);
  }
}
'@
}

function Get-Sha16([string]$Path) { (Get-FileHash $Path -Algorithm SHA256).Hash.Substring(0,16) }

function Assert-NoApp {
  Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 600
}

function Start-App {
  param([string[]]$CliArgs = @(), [int]$TimeoutSec = 25)
  Assert-NoApp
  $p = Start-Process -FilePath $script:Exe -ArgumentList $CliArgs -PassThru
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
    Start-Sleep -Milliseconds 250
    if ($p.HasExited) { return @{ Proc = $p; Hwnd = [IntPtr]::Zero; Exited = $true } }
    $h = Get-AppWindow -ProcId $p.Id
    if ($h -ne [IntPtr]::Zero) { return @{ Proc = $p; Hwnd = $h; Exited = $false } }
  }
  return @{ Proc = $p; Hwnd = [IntPtr]::Zero; Exited = $false }
}

# largest visible top-level window owned by the process
function Get-AppWindow {
  param([int]$ProcId)
  $best = [IntPtr]::Zero; $bestArea = -1
  $cb = [R2.EnumWindowsProc]{
    param($h, $l)
    $pid2 = 0
    [void][R2.Native]::GetWindowThreadProcessId($h, [ref]$pid2)
    if ($pid2 -eq $ProcId -and [R2.Native]::IsWindowVisible($h)) {
      $r = New-Object R2.RECT
      [void][R2.Native]::GetWindowRect($h, [ref]$r)
      $a = ($r.Right - $r.Left) * ($r.Bottom - $r.Top)
      if ($a -gt $script:bestArea) { $script:bestArea = $a; $script:best = $h }
    }
    return $true
  }
  $script:bestArea = -1; $script:best = [IntPtr]::Zero
  [void][R2.Native]::EnumWindows($cb, [IntPtr]::Zero)
  return $script:best
}

function Get-Rect {
  param([IntPtr]$Hwnd)
  $r = New-Object R2.RECT
  [void][R2.Native]::GetWindowRect($Hwnd, [ref]$r)
  return @{ X = $r.Left; Y = $r.Top; W = ($r.Right - $r.Left); H = ($r.Bottom - $r.Top) }
}

function Get-Title {
  param([IntPtr]$Hwnd)
  $sb = New-Object System.Text.StringBuilder 512
  [void][R2.Native]::GetWindowText($Hwnd, $sb, 512)
  return $sb.ToString()
}

function Get-Pixel {
  param([int]$X, [int]$Y)
  $dc = [R2.Native]::GetDC([IntPtr]::Zero)
  try { $c = [R2.Native]::GetPixel($dc, $X, $Y) } finally { [void][R2.Native]::ReleaseDC([IntPtr]::Zero, $dc) }
  if ($c -eq 0xFFFFFFFF) { return $null }
  return @{ R = [int]($c -band 0xFF); G = [int](($c -shr 8) -band 0xFF); B = [int](($c -shr 16) -band 0xFF) }
}

# sample a grid inside the window, return the modal colour + all distinct colours
function Get-WindowColorProfile {
  param([IntPtr]$Hwnd, [int]$Inset = 30, [int]$Step = 40)
  $r = Get-Rect $Hwnd
  $hist = @{}
  for ($x = $r.X + $Inset; $x -lt ($r.X + $r.W - $Inset); $x += $Step) {
    for ($y = $r.Y + $Inset; $y -lt ($r.Y + $r.H - $Inset); $y += $Step) {
      $c = Get-Pixel -X $x -Y $y
      if ($null -eq $c) { continue }
      $k = '{0},{1},{2}' -f $c.R, $c.G, $c.B
      if ($hist.ContainsKey($k)) { $hist[$k]++ } else { $hist[$k] = 1 }
    }
  }
  $mode = ($hist.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 1)
  $grey = 0; $n = 0
  foreach ($k in $hist.Keys) { $p = $k -split ','; $grey += [int]$p[0]; $n += $hist[$k] }
  return [pscustomobject]@{
    Modal = $mode.Key; ModalCount = $mode.Value; Total = $n
    Distinct = $hist.Count
    AvgR = if ($n) { [math]::Round((($hist.GetEnumerator() | ForEach-Object { [int](($_.Key -split ',')[0]) * $_.Value } | Measure-Object -Sum).Sum) / $n, 1) } else { 0 }
    Hist = $hist
  }
}

function Save-Shot {
  param([string]$Name, [IntPtr]$Hwnd = [IntPtr]::Zero)
  Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
  $r = if ($Hwnd -eq [IntPtr]::Zero) { @{ X=0; Y=0; W=[R2.Native]::GetSystemMetrics(0); H=[R2.Native]::GetSystemMetrics(1) } } else { Get-Rect $Hwnd }
  if ($r.W -le 0 -or $r.H -le 0) { Write-Host "  (Save-Shot skipped: window has no size)"; return $null }
  $bmp = New-Object System.Drawing.Bitmap($r.W, $r.H)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.X, $r.Y, 0, 0, (New-Object System.Drawing.Size($r.W, $r.H)))
  $path = Join-Path $script:ShotDir $Name
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  return $path
}

function Write-Settings([string]$Json) {
  if (-not (Test-Path $script:SettingsDir)) { New-Item -ItemType Directory -Force -Path $script:SettingsDir | Out-Null }
  [IO.File]::WriteAllText($script:SettingsPath, $Json, (New-Object System.Text.UTF8Encoding($false)))
}
function Write-SettingsObj($Obj) { Write-Settings ($Obj | ConvertTo-Json -Depth 6) }
function Read-SettingsRaw { if (Test-Path $script:SettingsPath) { [IO.File]::ReadAllText($script:SettingsPath) } else { $null } }
function Read-Settings { (Read-SettingsRaw) | ConvertFrom-Json }
function Remove-Settings { if (Test-Path $script:SettingsPath) { Remove-Item -Force $script:SettingsPath } }

function Focus-Window([IntPtr]$Hwnd) {
  # attach to the foreground thread so SetForegroundWindow is permitted
  $fg = [R2.Native]::GetForegroundWindow()
  $fgTid = [R2.Native]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
  $myTid = [R2.Native]::GetCurrentThreadId()
  [void][R2.Native]::AttachThreadInput($myTid, $fgTid, $true)
  [void][R2.Native]::SetForegroundWindow($Hwnd)
  [void][R2.Native]::SetActiveWindow($Hwnd)
  [void][R2.Native]::SetFocus($Hwnd)
  [void][R2.Native]::AttachThreadInput($myTid, $fgTid, $false)
  Start-Sleep -Milliseconds 200
  if ([R2.Native]::GetForegroundWindow() -ne $Hwnd) {
    try {
      $ws = New-Object -ComObject WScript.Shell
      $pid2 = 0
      [void][R2.Native]::GetWindowThreadProcessId($Hwnd, [ref]$pid2)
      [void]$ws.AppActivate($pid2)
    } catch { }
    Start-Sleep -Milliseconds 300
  }
  if ([R2.Native]::GetForegroundWindow() -ne $Hwnd) {
    [void][R2.Native]::SwitchToThisWindow($Hwnd, $true)
    Start-Sleep -Milliseconds 300
  }
  return ([R2.Native]::GetForegroundWindow() -eq $Hwnd)
}
function Assert-Foreground([IntPtr]$Hwnd) { return ([R2.Native]::GetForegroundWindow() -eq $Hwnd) }

# Real mouse click on a harmless spot inside the window (centre = the big timer text),
# used to hand keyboard focus to the app exactly like a user would.
function Click-Window([IntPtr]$Hwnd) {
  $r = Get-Rect $Hwnd
  $x = $r.X + [int]($r.W / 2)
  $y = $r.Y + [int]($r.H * 0.62)          # below the ring, above the bottom bar
  [void][R2.Native]::SetCursorPos($x, $y)
  Start-Sleep -Milliseconds 150
  [R2.Native]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 60
  [R2.Native]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 500
  return ([R2.Native]::GetForegroundWindow() -eq $Hwnd)
}
function Get-FgPid {
  $fg = [R2.Native]::GetForegroundWindow()
  $p = 0
  [void][R2.Native]::GetWindowThreadProcessId($fg, [ref]$p)
  return $p
}
# Try hard to give the app the keyboard focus; returns $true when the app owns it.
function Activate-App([IntPtr]$Hwnd) {
  if ([R2.Native]::GetForegroundWindow() -eq $Hwnd) { return $true }
  [void](Focus-Window $Hwnd)
  if ([R2.Native]::GetForegroundWindow() -eq $Hwnd) { return $true }
  [void](Click-Window $Hwnd)
  return ([R2.Native]::GetForegroundWindow() -eq $Hwnd)
}

function Send-Keys {
  param([string]$Keys)
  [System.Windows.Forms.SendKeys]::SendWait($Keys)
  Start-Sleep -Milliseconds 250
}

function Send-VKey {
  param([int]$Vk, [int]$Times = 1)
  for ($i = 0; $i -lt $Times; $i++) {
    [R2.Native]::keybd_event([byte]$Vk, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 40
    [R2.Native]::keybd_event([byte]$Vk, 0, 2, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 120
  }
}

function Post-Key {
  param([IntPtr]$Hwnd, [int]$Vk, [int]$Times = 1)
  for ($i = 0; $i -lt $Times; $i++) {
    [void][R2.Native]::PostMessageW($Hwnd, 0x0100, [IntPtr]$Vk, [IntPtr]0)
    Start-Sleep -Milliseconds 60
    [void][R2.Native]::PostMessageW($Hwnd, 0x0101, [IntPtr]$Vk, [IntPtr]0)
    Start-Sleep -Milliseconds 150
  }
}

function Send-Esc { Send-VKey -Vk 0x1B; Start-Sleep -Milliseconds 700 }
function Force-Quit {
  $p = Get-Process FluentPomodoro -ErrorAction SilentlyContinue
  if ($p) {
    $h = Get-AppWindow -ProcId $p[0].Id
    if ($h -ne [IntPtr]::Zero) { Focus-Window $h; Send-VKey -Vk 0x51 -Times 1 }  # need ctrl+shift
  }
}

# Ctrl+Shift+Q via keybd_event with modifiers
function Send-ForceQuit {
  param([IntPtr]$Hwnd)
  [void](Activate-App $Hwnd)
  [R2.Native]::keybd_event(0x11, 0, 0, [IntPtr]::Zero)   # ctrl down
  [R2.Native]::keybd_event(0x10, 0, 0, [IntPtr]::Zero)   # shift down
  Start-Sleep -Milliseconds 80
  [R2.Native]::keybd_event(0x51, 0, 0, [IntPtr]::Zero)   # Q down
  Start-Sleep -Milliseconds 60
  [R2.Native]::keybd_event(0x51, 0, 2, [IntPtr]::Zero)
  [R2.Native]::keybd_event(0x10, 0, 2, [IntPtr]::Zero)
  [R2.Native]::keybd_event(0x11, 0, 2, [IntPtr]::Zero)
}

function Wait-Exit([int]$Pid2, [int]$Sec = 8) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $Sec) {
    if (-not (Get-Process -Id $Pid2 -ErrorAction SilentlyContinue)) { return $true }
    Start-Sleep -Milliseconds 200
  }
  return $false
}

function Check {
  param([string]$Name, [bool]$Ok, [string]$Observed)
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  [void]$script:Results.Add([pscustomobject]@{ Check = $Name; Ok = $Ok; Observed = $Observed })
  Write-Host ("[{0}] {1} :: {2}" -f $tag, $Name, $Observed)
}

function Summary {
  $f = @($script:Results | Where-Object { -not $_.Ok }).Count
  Write-Host ("=" * 70)
  Write-Host ("TOTAL {0} / {1} passed, {2} failed" -f (@($script:Results).Count - $f), @($script:Results).Count, $f)
  Write-Host ("=" * 70)
  return @($script:Results)
}

function Get-VirtualDesktop {
  @{ X = [R2.Native]::GetSystemMetrics(76); Y = [R2.Native]::GetSystemMetrics(77);
     W = [R2.Native]::GetSystemMetrics(78); H = [R2.Native]::GetSystemMetrics(79) }
}

# ---------- UI Automation helpers ----------
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
function Uia-ById([IntPtr]$Hwnd, [string]$AutomationId) {
  $root = Uia-Root $Hwnd
  if ($null -eq $root) { return $null }
  try {
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $AutomationId)
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
  } catch { return $null }
}
function Uia-ByName([IntPtr]$Hwnd, [string]$Name) {
  $root = Uia-Root $Hwnd
  if ($null -eq $root) { return $null }
  try {
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name)
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
  } catch { return $null }
}
function Uia-Text([IntPtr]$Hwnd, [string]$AutomationId) {
  $e = Uia-ById $Hwnd $AutomationId
  if ($null -eq $e) { return '<not found>' }
  try { return $e.Current.Name } catch { return '<error>' }
}
function Uia-Click([IntPtr]$Hwnd, [string]$AutomationId) {
  $e = Uia-ById $Hwnd $AutomationId
  if ($null -eq $e) { return $false }
  try {
    $p = $e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $p.Invoke()
    return $true
  } catch { return $false }
}
function Uia-ClickName([IntPtr]$Hwnd, [string]$Name) {
  $e = Uia-ByName $Hwnd $Name
  if ($null -eq $e) { return $false }
  try { $p = $e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern); $p.Invoke(); return $true }
  catch { return $false }
}
function Uia-Value([IntPtr]$Hwnd, [string]$AutomationId) {
  $e = Uia-ById $Hwnd $AutomationId
  if ($null -eq $e) { return $null }
  try { return [int]$e.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern).Current.Value } catch { return $null }
}
function Uia-Toggle([IntPtr]$Hwnd, [string]$AutomationId) {
  $e = Uia-ById $Hwnd $AutomationId
  if ($null -eq $e) { return '<not found>' }
  try { return $e.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState.ToString() } catch { return '<error>' }
}
function Uia-Dump([IntPtr]$Hwnd) {
  $root = Uia-Root $Hwnd
  if ($null -eq $root) { return @() }
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $out = @()
  foreach ($e in $all) {
    try { $out += [pscustomobject]@{ Id = $e.Current.AutomationId; Type = $e.Current.ControlType.ProgrammaticName; Name = $e.Current.Name } } catch { }
  }
  return $out
}
