# f6-focus-override.ps1 -- F6: --focus 7 applies for the session but is never written back
. (Join-Path $PSScriptRoot 'lib2.ps1')
$today = (Get-Date).ToString('yyyy-MM-dd')

Write-Settings (@{
  FocusMinutes = 33; ShortBreakMinutes = 5; LongBreakMinutes = 15; LongBreakInterval = 4
  AutoStartNext = $false; SoundEnabled = $false; KeepScreenAwake = $false; AlwaysOnTop = $false
  NotifyOnPhaseEnd = $false; FocusLock = $false; AutoBigScreenOnFocus = $false
  Theme = 'Light'; UseMicaBackdrop = $false
  BigScreen = 'Mega'; BigScreenTopmost = $true
  HasWindowBounds = $false; WindowLeft = 0; WindowTop = 0; WindowWidth = 640; WindowHeight = 780
  StatsDate = $today; CompletedToday = 0; FocusMinutesToday = 0; TotalCompleted = 0; StreakDays = 0
  LastCompletedDate = ''
} | ConvertTo-Json)
$pre = (Read-Settings).FocusMinutes
Write-Host "pre-existing FocusMinutes = $pre"

# --- part 1: --focus 7 applies to the session ---
$r = Start-App -CliArgs @('--focus','7')
Start-Sleep -Seconds 7
$t = Get-Title $r.Hwnd
Check '--focus 7 shows 07:00 for this session' ($t -match '^07:00') "title='$t' (file still says $pre)"
Send-ForceQuit -Hwnd $r.Hwnd
[void](Wait-Exit -Pid2 $r.Proc.Id -Sec 10); Start-Sleep -Milliseconds 600
$post = (Read-Settings).FocusMinutes
Check '--focus 7 not written back on exit' ($post -eq $pre) "before=$pre after=$post"

# --- part 2: --focus 1 runs a real completion; the +1 minute lands in today's stats but the file keeps 33 ---
Write-Settings ((Read-SettingsRaw | ConvertFrom-Json | ForEach-Object {
  $_.CompletedToday = 0; $_.FocusMinutesToday = 0; $_.TotalCompleted = 0; $_.StreakDays = 0
  $_.LastCompletedDate = ''; $_.StatsDate = $today; $_.FocusMinutes = 33
  $_ } ) | ConvertTo-Json)
$r2 = Start-App -CliArgs @('--focus','1','--start')
Start-Sleep -Seconds 5
$t2 = Get-Title $r2.Hwnd
Write-Host "running with --focus 1 --start : title='$t2'"
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt 90) {
  Start-Sleep -Seconds 2
  $tt = Get-Title $r2.Hwnd
  if ($tt -match '短休息|长休息') { break }
}
Write-Host "phase switched after $([math]::Round($sw.Elapsed.TotalSeconds,1))s : title='$tt'"
Check '--focus 1 session actually completes into a break' ($tt -match '短休息|长休息') "title='$tt' elapsed=$([math]::Round($sw.Elapsed.TotalSeconds,1))s"
Save-Shot -Name 'r2-f6-focus1-completed.png' -Hwnd $r2.Hwnd | Out-Null
Send-ForceQuit -Hwnd $r2.Hwnd
[void](Wait-Exit -Pid2 $r2.Proc.Id -Sec 10); Start-Sleep -Milliseconds 800
$s = Read-Settings
Check '--focus 1: FocusMinutesToday records 1 minute' ($s.FocusMinutesToday -eq 1) "FocusMinutesToday=$($s.FocusMinutesToday)"
Check '--focus 1: CompletedToday=1' ($s.CompletedToday -eq 1) "CompletedToday=$($s.CompletedToday)"
Check '--focus 1: TotalCompleted=1' ($s.TotalCompleted -eq 1) "TotalCompleted=$($s.TotalCompleted)"
Check '--focus 1: StreakDays=1' ($s.StreakDays -eq 1) "StreakDays=$($s.StreakDays)"
Check '--focus 1: FocusMinutes in the file is still 33 after a completed session' ($s.FocusMinutes -eq 33) "FocusMinutes=$($s.FocusMinutes)"

Summary | Out-Null
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
