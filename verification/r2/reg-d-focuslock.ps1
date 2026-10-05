# reg-d-focuslock.ps1 -- regression: focus lock refuses close / WM_CLOSE / minimize, Ctrl+Shift+Q still exits
. (Join-Path $PSScriptRoot 'lib2.ps1')
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
$today = (Get-Date).ToString('yyyy-MM-dd')

Write-Settings (@{
  FocusMinutes = 25; ShortBreakMinutes = 5; LongBreakMinutes = 15; LongBreakInterval = 4
  AutoStartNext = $false; SoundEnabled = $false; KeepScreenAwake = $false; AlwaysOnTop = $true
  NotifyOnPhaseEnd = $false; FocusLock = $true; AutoBigScreenOnFocus = $false
  Theme = 'Light'; UseMicaBackdrop = $false
  BigScreen = 'Mega'; BigScreenTopmost = $true
  HasWindowBounds = $false; WindowLeft = 0; WindowTop = 0; WindowWidth = 640; WindowHeight = 780
  StatsDate = $today; CompletedToday = 0; FocusMinutesToday = 0; TotalCompleted = 0; StreakDays = 0
  LastCompletedDate = ''
} | ConvertTo-Json)

$r = Start-App
$h = $r.Hwnd
Start-Sleep -Seconds 7
$act = Activate-App $h
Send-VKey -Vk 0x20
Start-Sleep -Seconds 3
$t = Get-Title $h
Check 'focus running' ($t -match '^2[45]:\d\d') "activated=$act title='$t' fg pid=$(Get-FgPid) app pid=$($r.Proc.Id)"

# 1) WM_CLOSE
[void][R2.Native]::PostMessageW($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Milliseconds 1500
Check 'WM_CLOSE refused during focus lock' (-not $r.Proc.HasExited) "HasExited=$($r.Proc.HasExited)"

# 2) SC_CLOSE via WM_SYSCOMMAND
[void][R2.Native]::PostMessageW($h, 0x0112, [IntPtr]0xF060, [IntPtr]::Zero)
Start-Sleep -Milliseconds 1500
Check 'WM_SYSCOMMAND SC_CLOSE refused during focus lock' (-not $r.Proc.HasExited) "HasExited=$($r.Proc.HasExited)"

# 3) the real title-bar close button (same code path as a mouse click)
$clicked = Uia-Click $h 'BtnClose'
Start-Sleep -Milliseconds 1500
Check 'title-bar close button refused during focus lock' ((-not $r.Proc.HasExited) -and $clicked) "clicked=$clicked HasExited=$($r.Proc.HasExited)"
Save-Shot -Name 'r2-reg-focuslock.png' -Hwnd $h | Out-Null

# 4) minimize blocked
[void][R2.Native]::PostMessageW($h, 0x0112, [IntPtr]0xF020, [IntPtr]::Zero)
Start-Sleep -Milliseconds 900
Check 'minimize blocked during focus lock' (-not [R2.Native]::IsIconic($h)) "IsIconic=$([R2.Native]::IsIconic($h))"

# 5) Ctrl+Shift+Q must exit
Send-ForceQuit -Hwnd $h
$exited = Wait-Exit -Pid2 $r.Proc.Id -Sec 10
Check 'Ctrl+Shift+Q force-exits during focus lock' $exited "HasExited=$(-not (Get-Process -Id $r.Proc.Id -ErrorAction SilentlyContinue))"
Start-Sleep -Milliseconds 600

# 6) when NOT running, the close button works normally
$r2 = Start-App
$h2 = $r2.Hwnd
Start-Sleep -Seconds 7
$clicked2 = Uia-Click $h2 'BtnClose'
$exited2 = Wait-Exit -Pid2 $r2.Proc.Id -Sec 8
Check 'close button still works when no focus is running' ($clicked2 -and $exited2) "clicked=$clicked2 exited=$exited2"

Summary | Out-Null
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
