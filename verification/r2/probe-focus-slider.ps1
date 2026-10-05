# probe-focus-slider.ps1 -- edge case of the F6 fix: does an explicit UI change persist while --focus is active?
. (Join-Path $PSScriptRoot 'lib2.ps1')
$today = (Get-Date).ToString('yyyy-MM-dd')
Write-Settings (@{
  FocusMinutes = 33; ShortBreakMinutes = 5; LongBreakMinutes = 15; LongBreakInterval = 4
  AutoStartNext = $false; SoundEnabled = $false; KeepScreenAwake = $false; AlwaysOnTop = $true
  NotifyOnPhaseEnd = $false; FocusLock = $false; AutoBigScreenOnFocus = $false
  Theme = 'Light'; UseMicaBackdrop = $false
  BigScreen = 'Mega'; BigScreenTopmost = $true
  HasWindowBounds = $false; WindowLeft = 0; WindowTop = 0; WindowWidth = 640; WindowHeight = 780
  StatsDate = $today; CompletedToday = 0; FocusMinutesToday = 0; TotalCompleted = 0; StreakDays = 0
  LastCompletedDate = ''
} | ConvertTo-Json)

$r = Start-App -CliArgs @('--focus','7')
$h = $r.Hwnd
Start-Sleep -Seconds 7
Write-Host "session start: title='$(Get-Title $h)' (file FocusMinutes=33)"
Write-Host "settings panel opened: $(Uia-Click $h 'BtnSettings')"
Start-Sleep -Milliseconds 1500
$sld = Uia-ById $h 'SldFocus'
$rv = $sld.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
$rv.SetValue(20)
Start-Sleep -Milliseconds 1200
Write-Host "after setting the 专注时长 slider to 20:"
Write-Host "  slider reads      = $(Uia-Value $h 'SldFocus')"
Write-Host "  title             = '$(Get-Title $h)'"
Write-Host "  label             = '$(Uia-Text $h 'LblFocus')'"
Post-Key -Hwnd $h -Vk 0x1B
Start-Sleep -Milliseconds 800
Send-ForceQuit -Hwnd $h
$ok = Wait-Exit -Pid2 $r.Proc.Id -Sec 10
Start-Sleep -Milliseconds 700
$s = Read-Settings
Write-Host "exited=$ok   settings.json FocusMinutes = $($s.FocusMinutes)   (session used 20; original was 33)"
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
