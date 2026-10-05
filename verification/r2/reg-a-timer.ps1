# reg-a-timer.ps1 -- regression: space start/pause, keep-awake, 1-min focus completion + stats (exactly once)
. (Join-Path $PSScriptRoot 'lib2.ps1')
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
$today = (Get-Date).ToString('yyyy-MM-dd')

function PowerRequestsContains([string]$needle) {
  $o = (powercfg /requests 2>&1 | Out-String)
  return ($o -match [regex]::Escape($needle)), $o
}

Write-Settings (@{
  FocusMinutes = 1; ShortBreakMinutes = 5; LongBreakMinutes = 15; LongBreakInterval = 4
  AutoStartNext = $false; SoundEnabled = $false; KeepScreenAwake = $true; AlwaysOnTop = $true
  NotifyOnPhaseEnd = $false; FocusLock = $false; AutoBigScreenOnFocus = $false
  Theme = 'Light'; UseMicaBackdrop = $false
  BigScreen = 'Mega'; BigScreenTopmost = $true
  HasWindowBounds = $false; WindowLeft = 0; WindowTop = 0; WindowWidth = 640; WindowHeight = 780
  StatsDate = $today; CompletedToday = 0; FocusMinutesToday = 0; TotalCompleted = 0; StreakDays = 0
  LastCompletedDate = ''
} | ConvertTo-Json)

$r = Start-App
$h = $r.Hwnd
Start-Sleep -Seconds 7
$t0 = Get-Title $h
Check 'starts at 01:00 专注' ($t0 -match '^01:00') "title='$t0'"
$a = PowerRequestsContains 'FluentPomodoro'
Check 'keep-awake NOT held while idle' (-not $a[0]) "powercfg /requests mentions FluentPomodoro = $($a[0])"

# --- space starts ---
Focus-Window $h
Send-VKey -Vk 0x20
Start-Sleep -Seconds 3
$t1 = Get-Title $h
Check 'Space starts the countdown' ($t1 -match '^00:5') "title='$t1'"
$b = PowerRequestsContains 'FluentPomodoro'
Write-Host "powercfg /requests while focusing:"
Write-Host ($b[1].Trim())
Check 'keep-awake held while focusing' $b[0] "powercfg mentions FluentPomodoro = $($b[0])"

# --- pause freezes the countdown ---
Send-VKey -Vk 0x20
Start-Sleep -Milliseconds 900
$p1 = Get-Title $h
Start-Sleep -Seconds 6
$p2 = Get-Title $h
Check 'pause freezes the countdown (6s)' ($p1 -eq $p2) "'$p1' | '$p2'"
$c = PowerRequestsContains 'FluentPomodoro'
Check 'keep-awake released on pause' (-not $c[0]) "powercfg mentions FluentPomodoro = $($c[0])"
Save-Shot -Name 'r2-reg-paused.png' -Hwnd $h | Out-Null

# --- resume ---
$secBefore = if ($p2 -match '^(\d+):(\d\d)') { [int]$Matches[1]*60 + [int]$Matches[2] } else { -1 }
Send-VKey -Vk 0x20
$swR = [Diagnostics.Stopwatch]::StartNew()
Start-Sleep -Seconds 12
$rst = Get-Title $h
$secAfter = if ($rst -match '^(\d+):(\d\d)') { [int]$Matches[1]*60 + [int]$Matches[2] } else { -1 }
$elapsed = $swR.Elapsed.TotalSeconds
Check 'resume continues from the frozen value (12s -> ~12s less)' ([math]::Abs(($secBefore - $secAfter) - $elapsed) -le 2.0) "before=$secBefore after=$secAfter delta=$($secBefore-$secAfter) wallclock=$([math]::Round($elapsed,1))s title='$rst'"

# --- let the 1-minute focus finish ---
$sw = [Diagnostics.Stopwatch]::StartNew()
$tt = $rst
while ($sw.Elapsed.TotalSeconds -lt 90) {
  Start-Sleep -Seconds 2
  $tt = Get-Title $h
  if ($tt -match '短休息|长休息') { break }
}
Write-Host "phase switched after $([math]::Round($sw.Elapsed.TotalSeconds,1))s : '$tt'"
Check '1-minute focus completes into 短休息' ($tt -match '短休息') "title='$tt'"
$d = PowerRequestsContains 'FluentPomodoro'
Check 'keep-awake released when the focus phase ends' (-not $d[0]) "powercfg mentions FluentPomodoro = $($d[0])"
Save-Shot -Name 'r2-reg-break.png' -Hwnd $h | Out-Null
$stats = Uia-Text $h 'TxtStats'
$detail = Uia-Text $h 'TxtStatsDetail'
Write-Host "TxtStats = '$stats'"
Write-Host "TxtStatsDetail = $($detail -replace "`n", ' | ')"

Start-Sleep -Seconds 10
$s2 = Read-Settings
Check 'stats increment exactly once (CompletedToday=1 after +10s)' ($s2.CompletedToday -eq 1) "CompletedToday=$($s2.CompletedToday)"
Check 'FocusMinutesToday=1' ($s2.FocusMinutesToday -eq 1) "FocusMinutesToday=$($s2.FocusMinutesToday)"
Check 'TotalCompleted=1' ($s2.TotalCompleted -eq 1) "TotalCompleted=$($s2.TotalCompleted)"
Check 'StreakDays=1' ($s2.StreakDays -eq 1) "StreakDays=$($s2.StreakDays)"
Check 'StatsDate/LastCompletedDate = today' ($s2.StatsDate -eq $today -and $s2.LastCompletedDate -eq $today) "StatsDate=$($s2.StatsDate) LastCompletedDate=$($s2.LastCompletedDate)"
Check 'break does not auto-start (AutoStartNext=false)' ($tt -match '05:0') "title='$tt'"

Send-ForceQuit -Hwnd $h
[void](Wait-Exit -Pid2 $r.Proc.Id -Sec 10); Start-Sleep -Milliseconds 600
$s3 = Read-Settings
Check 'stats persisted across exit' ($s3.CompletedToday -eq 1 -and $s3.TotalCompleted -eq 1) "CompletedToday=$($s3.CompletedToday) TotalCompleted=$($s3.TotalCompleted)"
Check 'FocusMinutes still 1 after exit' ($s3.FocusMinutes -eq 1) "FocusMinutes=$($s3.FocusMinutes)"

Summary | Out-Null
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
