# reg-c-bigscreen.ps1 -- regression: forced big screen (attacks) + DWM attribute readback
. (Join-Path $PSScriptRoot 'lib2.ps1')
$today = (Get-Date).ToString('yyyy-MM-dd')

if (-not ('R2.Dwm' -as [type])) {
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
namespace R2 { public static class Dwm {
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int size);
} }
'@
}
$DWMWA_USE_IMMERSIVE_DARK_MODE = 20
$DWMWA_WINDOW_CORNER_PREFERENCE = 33
$DWMWA_SYSTEMBACKDROP_TYPE = 38
function Dwm-Get([IntPtr]$h, [int]$attr) { $v = 0; $hr = [R2.Dwm]::DwmGetWindowAttribute($h, $attr, [ref]$v, 4); return [pscustomobject]@{ Hr = $hr; Value = $v } }

function BaseSettings([bool]$mica) {
  [ordered]@{
    FocusMinutes = 25; ShortBreakMinutes = 5; LongBreakMinutes = 15; LongBreakInterval = 4
    AutoStartNext = $false; SoundEnabled = $false; KeepScreenAwake = $false; AlwaysOnTop = $false
    NotifyOnPhaseEnd = $false; FocusLock = $false; AutoBigScreenOnFocus = $false
    Theme = 'Light'; UseMicaBackdrop = $mica
    BigScreen = 'Mega'; BigScreenTopmost = $true
    HasWindowBounds = $false; WindowLeft = 0; WindowTop = 0; WindowWidth = 640; WindowHeight = 780
    StatsDate = $today; CompletedToday = 0; FocusMinutesToday = 0; TotalCompleted = 0; StreakDays = 0
    LastCompletedDate = ''
  } | ConvertTo-Json
}
$vd = Get-VirtualDesktop
$GW_EXSTYLE = -20; $WS_EX_TOPMOST = 0x8

# ================= part 1: Mica ON -> DWM readback =================
Write-Host "`n=== DWM readback (UseMicaBackdrop=true) ==="
Write-Settings (BaseSettings $true)
$r = Start-App
$h = $r.Hwnd
Start-Sleep -Seconds 7
$bd = Dwm-Get $h $DWMWA_SYSTEMBACKDROP_TYPE
$cn = Dwm-Get $h $DWMWA_WINDOW_CORNER_PREFERENCE
$dm = Dwm-Get $h $DWMWA_USE_IMMERSIVE_DARK_MODE
Write-Host "[Mica ON, windowed]  SYSTEMBACKDROP_TYPE=$($bd.Value) (hr=$($bd.Hr))  CORNER_PREFERENCE=$($cn.Value)  IMMERSIVE_DARK_MODE=$($dm.Value)"
Check 'Mica on -> SYSTEMBACKDROP_TYPE == 2 (Mica)' ($bd.Value -eq 2) "value=$($bd.Value)"
Check 'windowed -> CORNER_PREFERENCE == 2 (Round)' ($cn.Value -eq 2) "value=$($cn.Value)"
Check 'light theme -> IMMERSIVE_DARK_MODE == 0' ($dm.Value -eq 0) "value=$($dm.Value)"

Send-VKey -Vk 0x7A   # F11
Start-Sleep -Milliseconds 1400
$rect = Get-Rect $h
$cn2 = Dwm-Get $h $DWMWA_WINDOW_CORNER_PREFERENCE
$ex = [R2.Native]::GetWindowLongW($h, $GW_EXSTYLE)
Write-Host "[Mica ON, big screen] CORNER_PREFERENCE=$($cn2.Value)  rect=$($rect.W)x$($rect.H) @ ($($rect.X),$($rect.Y))  exstyle=0x$('{0:X}' -f $ex)"
Check 'big screen -> CORNER_PREFERENCE == 1 (DoNotRound)' ($cn2.Value -eq 1) "value=$($cn2.Value)"
Check 'F11 fills the whole virtual desktop' ($rect.X -eq $vd.X -and $rect.Y -eq $vd.Y -and $rect.W -ge $vd.W -and $rect.H -ge $vd.H) "$($rect.W)x$($rect.H) @ ($($rect.X),$($rect.Y))"
Check 'big screen window is topmost (WS_EX_TOPMOST)' (($ex -band $WS_EX_TOPMOST) -ne 0) "exstyle=0x$('{0:X}' -f $ex)"

# --- external SetWindowPos must be rejected ---
[void][R2.Native]::SetWindowPos($h, [IntPtr]::Zero, 100, 100, 800, 600, 0x0004 -bor 0x0010)  # NOZORDER|NOACTIVATE
Start-Sleep -Milliseconds 900
$r2 = Get-Rect $h
Check 'external SetWindowPos(800x600@100,100) is rejected' ($r2.W -eq $rect.W -and $r2.H -eq $rect.H -and $r2.X -eq $rect.X -and $r2.Y -eq $rect.Y) "before=$($rect.W)x$($rect.H)@($($rect.X),$($rect.Y)) after=$($r2.W)x$($r2.H)@($($r2.X),$($r2.Y))"

# --- SC_MINIMIZE blocked ---
[void][R2.Native]::PostMessageW($h, 0x0112, [IntPtr]0xF020, [IntPtr]0)
Start-Sleep -Milliseconds 900
$r3 = Get-Rect $h
Check 'WM_SYSCOMMAND SC_MINIMIZE blocked' ((-not [R2.Native]::IsIconic($h)) -and $r3.W -eq $rect.W) "IsIconic=$([R2.Native]::IsIconic($h)) rect=$($r3.W)x$($r3.H)"

# --- ShowWindow(SW_MINIMIZE) blocked ---
[void][R2.Native]::ShowWindow($h, 6)
Start-Sleep -Milliseconds 900
[void][R2.Native]::ShowWindow($h, 9)
Start-Sleep -Milliseconds 900
$r4 = Get-Rect $h
Check 'ShowWindow(SW_MINIMIZE) blocked' ((-not [R2.Native]::IsIconic($h)) -and $r4.W -eq $rect.W) "IsIconic=$([R2.Native]::IsIconic($h)) rect=$($r4.W)x$($r4.H)"

# --- Win+D (show desktop) must not minimize ---
Focus-Window $h
Start-Sleep -Milliseconds 300
[R2.Native]::keybd_event(0x5B, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 120
[R2.Native]::keybd_event(0x44, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 80
[R2.Native]::keybd_event(0x44, 0, 2, [IntPtr]::Zero)
[R2.Native]::keybd_event(0x5B, 0, 2, [IntPtr]::Zero)
Start-Sleep -Milliseconds 1200
$r5 = Get-Rect $h
Write-Host "after Win+D: rect=$($r5.W)x$($r5.H) IsIconic=$([R2.Native]::IsIconic($h)) visible=$([R2.Native]::IsWindowVisible($h))"
Check 'Win+D does not minimize the big-screen window' (-not [R2.Native]::IsIconic($h)) "IsIconic=$([R2.Native]::IsIconic($h))"
Check 'Win+D leaves the big-screen rect intact' ($r5.W -eq $rect.W -and $r5.H -eq $rect.H) "$($r5.W)x$($r5.H) @ ($($r5.X),$($r5.Y))"
Save-Shot -Name 'r2-reg-winD.png' -Hwnd $h | Out-Null
[R2.Native]::keybd_event(0x5B, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 120
[R2.Native]::keybd_event(0x44, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 80
[R2.Native]::keybd_event(0x44, 0, 2, [IntPtr]::Zero); [R2.Native]::keybd_event(0x5B, 0, 2, [IntPtr]::Zero)
Start-Sleep -Milliseconds 900

# --- Esc restores 640x780 ---
Send-Esc
Start-Sleep -Milliseconds 1000
$r6 = Get-Rect $h
$cn3 = Dwm-Get $h $DWMWA_WINDOW_CORNER_PREFERENCE
Check 'Esc restores 640x780' ($r6.W -eq 640 -and $r6.H -eq 780) "$($r6.W)x$($r6.H) @ ($($r6.X),$($r6.Y))"
Check 'back in window mode CORNER_PREFERENCE back to 2' ($cn3.Value -eq 2) "value=$($cn3.Value)"
Check 'window bounds not polluted by big screen (still 640x780)' ($r6.W -eq 640 -and $r6.H -eq 780) "$($r6.W)x$($r6.H)"
Save-Shot -Name 'r2-reg-restored.png' -Hwnd $h | Out-Null
Send-ForceQuit -Hwnd $h
[void](Wait-Exit -Pid2 $r.Proc.Id -Sec 10); Start-Sleep -Milliseconds 700

# ================= part 2: Mica OFF -> backdrop 0 =================
Write-Host "`n=== DWM readback (UseMicaBackdrop=false) ==="
Write-Settings (BaseSettings $false)
$r = Start-App
$h = $r.Hwnd
Start-Sleep -Seconds 7
$bd2 = Dwm-Get $h $DWMWA_SYSTEMBACKDROP_TYPE
Write-Host "[Mica OFF, windowed] SYSTEMBACKDROP_TYPE=$($bd2.Value)"
Check 'Mica off -> SYSTEMBACKDROP_TYPE == 0' ($bd2.Value -eq 0) "value=$($bd2.Value)"

# dark theme readback
Send-ForceQuit -Hwnd $h
[void](Wait-Exit -Pid2 $r.Proc.Id -Sec 10); Start-Sleep -Milliseconds 700
$json = (Read-SettingsRaw | ConvertFrom-Json); $json.Theme = 'Dark'; Write-Settings ($json | ConvertTo-Json)
$r = Start-App
$h = $r.Hwnd
Start-Sleep -Seconds 7
$dm2 = Dwm-Get $h $DWMWA_USE_IMMERSIVE_DARK_MODE
Write-Host "[saved Theme=Dark] IMMERSIVE_DARK_MODE=$($dm2.Value)"
Check 'dark theme -> IMMERSIVE_DARK_MODE == 1' ($dm2.Value -eq 1) "value=$($dm2.Value)"

Summary | Out-Null
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
