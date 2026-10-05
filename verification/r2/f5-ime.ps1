# f5-ime.ps1 -- F5: bare-letter shortcuts R/S/F while a Chinese IME is active
. (Join-Path $PSScriptRoot 'lib2.ps1')
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

if (-not ('R2.Native2' -as [type])) {
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices;
namespace R2 {
  public static class Native2 {
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern IntPtr GetKeyboardLayout(uint tid);
    [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetKeyboardLayoutList(int n, IntPtr[] list);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr LoadKeyboardLayoutW(string id, uint flags);
    [DllImport("imm32.dll")] public static extern bool ImmIsIME(IntPtr hkl);
  }
}
'@
}
$WM_INPUTLANGCHANGEREQUEST = 0x0050

function Get-Class([IntPtr]$h) { $sb = New-Object System.Text.StringBuilder 256; [void][R2.Native2]::GetClassNameW($h, $sb, 256); $sb.ToString() }

function Get-FgInfo {
  $fg = [R2.Native]::GetForegroundWindow()
  $fpid = 0
  [void][R2.Native]::GetWindowThreadProcessId($fg, [ref]$fpid)
  return [pscustomobject]@{ Hwnd = $fg; Pid = $fpid; Class = (Get-Class $fg) }
}

function Get-ProcWindows([int]$ProcId) {
  $out = @()
  $cb = [R2.EnumWindowsProc]{
    param($h, $l)
    $pid2 = 0
    [void][R2.Native]::GetWindowThreadProcessId($h, [ref]$pid2)
    if ($pid2 -eq $ProcId) {
      $cls = Get-Class $h
      $r = New-Object R2.RECT; [void][R2.Native]::GetWindowRect($h, [ref]$r)
      $script:winOut += [pscustomobject]@{ Hwnd=$h; Class=$cls; Visible=[R2.Native]::IsWindowVisible($h); W=($r.Right-$r.Left); H=($r.Bottom-$r.Top) }
    }
    return $true
  }
  $script:winOut = @()
  [void][R2.Native]::EnumWindows($cb, [IntPtr]::Zero)
  return $script:winOut
}

$today = (Get-Date).ToString('yyyy-MM-dd')
Write-Settings (@{
  FocusMinutes = 25; ShortBreakMinutes = 5; LongBreakMinutes = 15; LongBreakInterval = 4
  AutoStartNext = $false; SoundEnabled = $false; KeepScreenAwake = $false; AlwaysOnTop = $true
  NotifyOnPhaseEnd = $false; FocusLock = $false; AutoBigScreenOnFocus = $false
  Theme = 'Light'; UseMicaBackdrop = $false
  BigScreen = 'Mega'; BigScreenTopmost = $true
  HasWindowBounds = $false; WindowLeft = 0; WindowTop = 0; WindowWidth = 640; WindowHeight = 780
  StatsDate = $today; CompletedToday = 0; FocusMinutesToday = 0; TotalCompleted = 0; StreakDays = 0
  LastCompletedDate = ''
} | ConvertTo-Json)

Write-Host "=== keyboard layouts installed on this machine ==="
$list = New-Object 'IntPtr[]' 16
$n = [R2.Native2]::GetKeyboardLayoutList(16, $list)
for ($i = 0; $i -lt $n; $i++) { Write-Host ("  HKL[{0}] = 0x{1:X8}  IsIME={2}" -f $i, [int64]$list[$i], [R2.Native2]::ImmIsIME($list[$i])) }

$r = Start-App
$h = $r.Hwnd; $pid2 = $r.Proc.Id
Start-Sleep -Seconds 7
$tid = [R2.Native]::GetWindowThreadProcessId($h, [IntPtr]::Zero)
$hklBefore = [R2.Native2]::GetKeyboardLayout($tid)
Write-Host "`napp thread id = $tid   HKL(app thread) = 0x$(([int64]$hklBefore).ToString('X8'))"

# force the Chinese (Simplified, PRC) layout onto the app's thread, exactly like a real Chinese IME user
$hklCN = [R2.Native2]::LoadKeyboardLayoutW('00000804', 1)
[void][R2.Native2]::PostMessageW($h, $WM_INPUTLANGCHANGEREQUEST, [IntPtr]::Zero, $hklCN)
Start-Sleep -Milliseconds 1200
$hklAfter = [R2.Native2]::GetKeyboardLayout($tid)
Write-Host "requested HKL 0x$(([int64]$hklCN).ToString('X8'))  -> HKL(app thread) now = 0x$(([int64]$hklAfter).ToString('X8'))"
$imeActive = ([int64]$hklAfter -eq 0x08040804)
Check 'test condition: app thread is on the Chinese (08040804) layout' $imeActive "HKL=0x$(([int64]$hklAfter).ToString('X8')) (round-1 recorded 0x08040804)"

Write-Host "`n=== windows owned by the process (IME composition windows included) ==="
$wins = Get-ProcWindows $pid2
$wins | Format-Table -AutoSize | Out-String | Write-Host

$activated = Activate-App $h
Start-Sleep -Milliseconds 500
$fg = Get-FgInfo
Write-Host "Activate-App returned $activated"
Write-Host "foreground window: hwnd=$($fg.Hwnd) pid=$($fg.Pid) class='$($fg.Class)'   app hwnd=$h app pid=$pid2"
$appForeground = ($fg.Pid -eq $pid2)
Check 'the app really owns the keyboard focus when SendKeys is used' $appForeground "fg pid=$($fg.Pid) app pid=$pid2 fg class='$($fg.Class)'"
$t0 = Get-Title $h
Write-Host "`nbaseline title = '$t0'"

# ---- S : skip phase ----
Send-Keys 's'
Start-Sleep -Milliseconds 700
$t1 = Get-Title $h
Check "SendKeys 's' switches phase (skip)" ($t1 -match '短休息|长休息') "title='$t1'"
Save-Shot -Name 'r2-f5-after-skip-s.png' -Hwnd $h | Out-Null

# ---- S again : short break -> focus ----
Send-Keys 's'
Start-Sleep -Milliseconds 700
$t2 = Get-Title $h
Check "SendKeys 's' again returns to 专注" ($t2 -match '专注') "title='$t2'"

# ---- R : reset current phase ----
Send-VKey -Vk 0x20   # space -> start
Start-Sleep -Seconds 3
$t3 = Get-Title $h
Send-Keys 'r'
Start-Sleep -Milliseconds 900
$t4 = Get-Title $h
Check "SendKeys 'r' resets the phase to full duration" ($t4 -match '^25:00' -and $t3 -notmatch '^25:00') "after space='$t3' after r='$t4'"
Check "SendKeys 'r' also pauses the running timer" ($t4 -notmatch '24:|23:') "title='$t4'"

# ---- F : cycle window -> full -> mega -> window ----
$rectA = Get-Rect $h
Send-Keys 'f'
Start-Sleep -Milliseconds 1000
$rectB = Get-Rect $h
Send-Keys 'f'
Start-Sleep -Milliseconds 1000
$rectC = Get-Rect $h
Send-Keys 'f'
Start-Sleep -Milliseconds 1200
$rectD = Get-Rect $h
Write-Host "F cycle rects: start=$($rectA.W)x$($rectA.H) -> $($rectB.W)x$($rectB.H) -> $($rectC.W)x$($rectC.H) -> $($rectD.W)x$($rectD.H)"
Check "SendKeys 'f' cycles window->fullscreen" ($rectB.W -ge 1920 -and $rectB.H -ge 1080) "$($rectB.W)x$($rectB.H)"
Check "SendKeys 'f' cycles fullscreen->mega" ($rectC.W -ge 1920 -and $rectC.H -ge 1080) "$($rectC.W)x$($rectC.H)"
Check "SendKeys 'f' cycles mega->window (640x780)" ($rectD.W -eq 640 -and $rectD.H -eq 780) "$($rectD.W)x$($rectD.H)"

# ---- R / S / F must also work through the raw keybd_event path (hardware-like, IME in the loop) ----
Send-VKey -Vk 0x53   # S
Start-Sleep -Milliseconds 800
$t5 = Get-Title $h
Check "hardware-path 'S' also switches phase" ($t5 -match '短休息|长休息') "title='$t5'"

Write-Host "`n=== IME windows after the test ==="
Get-ProcWindows $pid2 | Format-Table -AutoSize | Out-String | Write-Host

$hklEnd = [R2.Native2]::GetKeyboardLayout($tid)
Write-Host "HKL(app thread) at end = 0x$(([int64]$hklEnd).ToString('X8'))"

Summary | Out-Null
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
