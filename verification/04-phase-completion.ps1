# Independent behavior test 4: real 1-minute focus completion -> phase switch + statistics + persistence.
param(
    [string]$Exe = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verify-dist\FluentPomodoro.exe',
    [string]$OutDir = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verification'
)
. (Join-Path $OutDir 'lib.ps1')

Write-Host "=== TEST 4: 1-minute phase completion + statistics  ($(Get-Date -Format o)) ==="
Assert-NoAppRunning
Write-Settings @{
    FocusMinutes = 1; ShortBreakMinutes = 5; LongBreakMinutes = 15; LongBreakInterval = 4
    AutoStartNext = $false; SoundEnabled = $true; KeepScreenAwake = $true; AlwaysOnTop = $true
    NotifyOnPhaseEnd = $true; FocusLock = $false; AutoBigScreenOnFocus = $false
    Theme = 'System'; UseMicaBackdrop = $true; BigScreen = 'Full'; BigScreenTopmost = $true
    HasWindowBounds = $false
}
Write-Host "  pre-written settings.json:"; Get-Content (Get-SettingsPath) | ForEach-Object { "    $_" }

$proc = Start-Process -FilePath $Exe -ArgumentList '--start' -PassThru
$h = Wait-AppWindow 20
if ($h -eq [IntPtr]::Zero) { Add-Check 'window created' $false; Assert-NoAppRunning; exit 1 }
Start-Sleep -Seconds 5
$t0 = Get-Title $h
Add-Check '--start begins the 1-minute focus (title 00:5x)' (($t0 -match '00:5') -and ($t0 -match '专注')) $t0
Add-Check 'did not auto-enter big screen (AutoBigScreenOnFocus=false)' ((Get-Rect $h).R - (Get-Rect $h).L -eq 640) (Format-Rect $h)
Save-Shot (Join-Path $OutDir '12-phase1-running.png') $h

# wait for the phase transition, polling the title
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$toastShot = $false
while ($sw.Elapsed.TotalSeconds -lt 85) {
    $t = Get-Title $h
    if ($t -match '短休息') { break }
    if (-not $toastShot -and $sw.Elapsed.TotalSeconds -gt 55 -and $t -match '00:0') {
        Save-Shot (Join-Path $OutDir '13-phase1-before-end.png') $h; $toastShot = $true
    }
    Start-Sleep -Milliseconds 500
}
$elapsed = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
$tAfter = Get-Title $h
Write-Host "  phase switched after ~$elapsed s of polling; title='$tAfter'"
Add-Check 'title switched to 短休息 within 85s' ($tAfter -match '短休息') $tAfter
Add-Check 'break countdown shows 5 minutes' ($tAfter -match '0[45]:\d\d') $tAfter
Save-Shot (Join-Path $OutDir '14-phase2-break.png') $h
Save-Crop (Join-Path $OutDir '15-break-bottom-stats.png') $h 0 620 640 160

Start-Sleep -Seconds 2
$j = Read-Settings
Write-Host "  settings.json after completion:"; Get-Content (Get-SettingsPath) | ForEach-Object { "    $_" }
Add-Check 'CompletedToday == 1' ($j.CompletedToday -eq 1) "CompletedToday=$($j.CompletedToday)"
Add-Check 'FocusMinutesToday == 1' ($j.FocusMinutesToday -eq 1) "FocusMinutesToday=$($j.FocusMinutesToday)"
Add-Check 'TotalCompleted == 1' ($j.TotalCompleted -eq 1) "TotalCompleted=$($j.TotalCompleted)"
Add-Check 'StreakDays == 1' ($j.StreakDays -eq 1) "StreakDays=$($j.StreakDays)"
Add-Check 'LastCompletedDate == today' ($j.LastCompletedDate -eq (Get-Date -Format 'yyyy-MM-dd')) "LastCompletedDate=$($j.LastCompletedDate)"
Add-Check 'StatsDate == today' ($j.StatsDate -eq (Get-Date -Format 'yyyy-MM-dd')) "StatsDate=$($j.StatsDate)"

# no double counting while idling in the break
Start-Sleep -Seconds 10
$j2 = Read-Settings
Add-Check 'no double counting after phase completion (10s later)' (($j2.CompletedToday -eq 1) -and ($j2.TotalCompleted -eq 1) -and ($j2.FocusMinutesToday -eq 1)) "CompletedToday=$($j2.CompletedToday) TotalCompleted=$($j2.TotalCompleted) FocusMinutesToday=$($j2.FocusMinutesToday)"
$tIdle = Get-Title $h
Add-Check 'break phase does not auto-start (AutoStartNext=false)' ($tIdle -match '短休息') $tIdle

# ---- exit + restart persistence ----
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(12)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Add-Check 'exits normally' $proc.HasExited "HasExited=$($proc.HasExited)"
$j3 = Read-Settings
Add-Check 'FocusMinutes=1 persisted across exit' ($j3.FocusMinutes -eq 1) "FocusMinutes=$($j3.FocusMinutes)"
Add-Check 'statistics persisted across exit' (($j3.CompletedToday -eq 1) -and ($j3.TotalCompleted -eq 1)) "CompletedToday=$($j3.CompletedToday) TotalCompleted=$($j3.TotalCompleted)"
Assert-NoAppRunning

$proc2 = Start-Process -FilePath $Exe -PassThru
$h2 = Wait-AppWindow 20
Start-Sleep -Seconds 4
$t2 = Get-Title $h2
Add-Check 'restart restores custom 1-minute focus duration (title 01:00)' (($t2 -match '01:00') -and ($t2 -match '专注')) $t2
Add-Check 'restart window is 640x780' (((Get-Rect $h2).R - (Get-Rect $h2).L -eq 640) -and ((Get-Rect $h2).B - (Get-Rect $h2).T -eq 780)) (Format-Rect $h2)
Save-Shot (Join-Path $OutDir '16-restart-1min.png') $h2
Save-Crop (Join-Path $OutDir '17-restart-stats.png') $h2 130 700 510 80
Send-Keys '^+q' 1500
Start-Sleep -Seconds 1
Assert-NoAppRunning

Write-Host ''
Get-VerifyResults | Format-Table -AutoSize
$failed = @(Get-VerifyResults | Where-Object { -not $_.Pass }).Count
Write-Host ("TEST4: {0} passed / {1}" -f (@(Get-VerifyResults).Count - $failed), @(Get-VerifyResults).Count)
exit $failed
