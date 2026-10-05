# probe-keys.ps1 -- diagnose key-delivery reliability with AlwaysOnTop=false
. (Join-Path $PSScriptRoot 'lib2.ps1')
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
$today = (Get-Date).ToString('yyyy-MM-dd')
Write-Settings (@{
  FocusMinutes = 25; ShortBreakMinutes = 5; LongBreakMinutes = 15; LongBreakInterval = 4
  AutoStartNext = $false; SoundEnabled = $false; KeepScreenAwake = $false; AlwaysOnTop = $false
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
Write-Host "title before = '$(Get-Title $h)'  fg=$([R2.Native]::GetForegroundWindow())  app=$h"

Focus-Window $h
Write-Host "after Focus-Window: fg=$([R2.Native]::GetForegroundWindow())"
Send-VKey -Vk 0x20
Start-Sleep -Seconds 3
Write-Host "after hardware SPACE: title='$(Get-Title $h)'  fg=$([R2.Native]::GetForegroundWindow())"

Post-Key -Hwnd $h -Vk 0x20
Start-Sleep -Seconds 3
Write-Host "after PostMessage SPACE: title='$(Get-Title $h)'"

Post-Key -Hwnd $h -Vk 0x20
Start-Sleep -Milliseconds 1200
Write-Host "after PostMessage SPACE (pause): title='$(Get-Title $h)'"

# now check WM_CLOSE refusal while running
Post-Key -Hwnd $h -Vk 0x20
Start-Sleep -Seconds 2
Write-Host "running again: title='$(Get-Title $h)'"
[void][R2.Native]::PostMessageW($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Milliseconds 1500
Write-Host "after WM_CLOSE: HasExited=$($r.Proc.HasExited) title='$(if (-not $r.Proc.HasExited) { Get-Title $h } else { 'n/a' })'"
if (-not $r.Proc.HasExited) { Send-ForceQuit -Hwnd $h; [void](Wait-Exit -Pid2 $r.Proc.Id -Sec 8) }
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
