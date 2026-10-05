# 04-history.ps1 -- Feature 2 (data path): a real 1-minute focus must append exactly one day entry
. (Join-Path $PSScriptRoot 'lib3.ps1')

$T = [datetime]::Today
$yesterday = $T.AddDays(-1)
Write-Host ("harness date = {0:yyyy-MM-dd} {1:HH:mm:ss}" -f $T, (Get-Date))

# baseline: three consecutive days already have data ending yesterday (so that the settings-side
# StreakDays counter and the history-derived streak in the stats window agree), today has none
$baseDays = [ordered]@{
  ($yesterday.ToString('yyyy-MM-dd'))     = @{ Minutes = 25; Pomodoros = 1 }
  ($T.AddDays(-2).ToString('yyyy-MM-dd')) = @{ Minutes = 30; Pomodoros = 1 }
  ($T.AddDays(-3).ToString('yyyy-MM-dd')) = @{ Minutes = 15; Pomodoros = 1 }
  ($T.AddDays(-5).ToString('yyyy-MM-dd')) = @{ Minutes = 60; Pomodoros = 2 }
}
[void](Stop-AllApp)
[void](Remove-ConfigFiles)
Set-BaseSettings -Override @{
  FocusMinutes = 1; AutoStartNext = $false; ShowClock = $false
  StatsDate = $T.ToString('yyyy-MM-dd'); CompletedToday = 0; FocusMinutesToday = 0
  TotalCompleted = 7; StreakDays = 3; LastCompletedDate = $yesterday.ToString('yyyy-MM-dd')
} | Out-Null
Write-HistoryRaw (([ordered]@{ Days = $baseDays } | ConvertTo-Json -Depth 5))
Write-Host "baseline history.json:"; Write-Host ((Read-HistoryRaw) -replace "`r`n","`n")
Write-Host ("baseline settings: CompletedToday=0 FocusMinutesToday=0 TotalCompleted=7 StreakDays=3 LastCompletedDate={0:yyyy-MM-dd}" -f $yesterday)

$app = Start-App
$main = $app.Hwnd
Check 'main window present' ($main -ne [IntPtr]::Zero) ("hwnd={0} title='{1}'" -f $main,(Get-Title $main))
Check 'timer shows 01:00 (FocusMinutes=1 took effect)' ((Get-Title $main) -match '^01:00') ("title='{0}'" -f (Get-Title $main))

# start the focus phase with a real Space keystroke
$fg = Activate-App $main
Check 'app owns the keyboard focus before the keystroke' $fg ("foreground==main : {0}" -f $fg)
Send-VKey -Vk 0x20
Start-Sleep -Milliseconds 1500
$title = Get-Title $main
Check 'Space starts the focus phase' ($title -match '专注' -and $title -notmatch '^01:00') ("title='{0}'" -f $title)

# wait for the phase to complete (poll the title for the break phase)
$sw = [Diagnostics.Stopwatch]::StartNew(); $done = $false
while ($sw.Elapsed.TotalSeconds -lt 95) {
  Start-Sleep -Milliseconds 700
  $title = Get-Title $main
  if ($title -match '休息') { $done = $true; break }
}
Check 'the 1-minute focus phase runs to completion and advances to the break' $done `
      ("after {0:N1}s title='{1}'" -f $sw.Elapsed.TotalSeconds, (Get-Title $main))

# history.json immediately after completion
$h1 = (Read-HistoryRaw | ConvertFrom-Json)
$todayKey = $T.ToString('yyyy-MM-dd')
$todayMin = [int]$h1.Days.$todayKey.Minutes
$todayPom = [int]$h1.Days.$todayKey.Pomodoros
Check 'history.json gained today with exactly +1 minute' ($todayMin -eq 1) ("today Minutes={0}" -f $todayMin)
Check 'history.json gained today with exactly +1 pomodoro' ($todayPom -eq 1) ("today Pomodoros={0}" -f $todayPom)
Check 'the pre-existing day is unchanged (25 min / 1 pomodoro)' `
      (([int]$h1.Days.$($yesterday.ToString('yyyy-MM-dd')).Minutes -eq 25) -and ([int]$h1.Days.$($yesterday.ToString('yyyy-MM-dd')).Pomodoros -eq 1)) `
      ("yesterday = {0} min / {1} pom" -f $h1.Days.$($yesterday.ToString('yyyy-MM-dd')).Minutes, $h1.Days.$($yesterday.ToString('yyyy-MM-dd')).Pomodoros)
Check 'history.json now holds exactly 5 days' (@($h1.Days.PSObject.Properties).Count -eq 5) `
      ("days = {0}" -f ((@($h1.Days.PSObject.Properties) | ForEach-Object { $_.Name }) -join ', '))

# exactly once: nothing further changes while sitting in the break
Start-Sleep -Seconds 12
$h2 = (Read-HistoryRaw | ConvertFrom-Json)
Check 'no second increment while the break is running (counted exactly once)' `
      (([int]$h2.Days.$todayKey.Minutes -eq 1) -and ([int]$h2.Days.$todayKey.Pomodoros -eq 1)) `
      ("12s later today = {0} min / {1} pom" -f $h2.Days.$todayKey.Minutes, $h2.Days.$todayKey.Pomodoros)

$s = Read-Settings
Check 'settings: CompletedToday incremented to exactly 1' ([int]$s.CompletedToday -eq 1) ("CompletedToday={0}" -f $s.CompletedToday)
Check 'settings: FocusMinutesToday incremented to exactly 1' ([int]$s.FocusMinutesToday -eq 1) ("FocusMinutesToday={0}" -f $s.FocusMinutesToday)
Check 'settings: TotalCompleted 7 -> 8' ([int]$s.TotalCompleted -eq 8) ("TotalCompleted={0}" -f $s.TotalCompleted)
Check 'settings: StreakDays 3 -> 4 (yesterday was the last completion day)' ([int]$s.StreakDays -eq 4) ("StreakDays={0}" -f $s.StreakDays)
Check 'settings: LastCompletedDate == today' ($s.LastCompletedDate -eq $todayKey) ("LastCompletedDate={0}" -f $s.LastCompletedDate)

# the statistics window must show 今日 = 1 分钟 / 1 个番茄
[void](Send-CtrlKey -Hwnd $main -Vk 0x49)
Start-Sleep -Milliseconds 1600
$stats = Get-StatsWindow -ProcId $app.Pid
Check 'statistics window opens after the focus run' ($stats -ne [IntPtr]::Zero) ("hwnd={0}" -f $stats)
$vt = Uia-Text $stats 'ValToday'; $st = Uia-Text $stats 'SubToday'
Check '今日 card reads exactly 1 分钟' ($vt -eq '1 分钟') ("ValToday='{0}'" -f $vt)
Check '今日 card sub-label reads 1 个番茄' ($st -eq '1 个番茄') ("SubToday='{0}'" -f $st)
$vTotal = Uia-Text $stats 'ValTotal'; $vBest = Uia-Text $stats 'ValBest'; $vStreak = Uia-Text $stats 'ValStreak'
Check '累计专注 card = 1+25+30+15+60 = 131 分钟' ($vTotal -eq '2 小时 11 分') ("ValTotal='{0}' expected='2 小时 11 分'" -f $vTotal)
Check '最佳一天 card = 60 分钟 on the day 5 days ago' ($vBest -eq '1 小时') ("ValBest='{0}' expected='1 小时'" -f $vBest)
Check '连续专注 card = 4 天 (history-derived, 4 consecutive days)' ($vStreak -eq '4') ("ValStreak='{0}' expected='4'" -f $vStreak)
[void](Save-Shot -Name 'r3-d1-stats-after-focus.png' -Hwnd $stats)

[void](Activate-App $main); Send-ForceQuit $main
[void](Wait-Exit -Pid2 $app.Pid -Sec 10)
[void](Stop-AllApp)
[void](Remove-ConfigFiles)
[void](Summary)
