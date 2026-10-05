# Independent behavior test 3: timer accuracy - pause must not lose/gain time; countdown monotonic.
param(
    [string]$Exe = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verify-dist\FluentPomodoro.exe',
    [string]$OutDir = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verification'
)
. (Join-Path $OutDir 'lib.ps1')

function Title-Seconds([string]$t) {
    if ($t -match '(\d+):(\d\d)') { return ([int]$Matches[1]) * 60 + [int]$Matches[2] }
    return -1
}

Write-Host "=== TEST 3: pause/resume time accounting  ($(Get-Date -Format o)) ==="
Assert-NoAppRunning
Write-Settings @{ FocusMinutes = 25; AutoBigScreenOnFocus = $false; AutoStartNext = $false; AlwaysOnTop = $false; HasWindowBounds = $false }

$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
if ($h -eq [IntPtr]::Zero) { Add-Check 'window created' $false; Assert-NoAppRunning; exit 1 }
Start-Sleep -Seconds 3
Write-Host "  title at rest: '$(Get-Title $h)'  rect=$(Format-Rect $h)"

# monotonic decrease over 5 samples
[void](Focus-App)
Send-Keys ' ' 300
$samples = @()
for ($i = 0; $i -lt 5; $i++) { $samples += (Title-Seconds (Get-Title $h)); Start-Sleep -Seconds 1 }
$mono = $true
for ($i = 1; $i -lt $samples.Count; $i++) { if ($samples[$i] -gt $samples[$i - 1]) { $mono = $false } }
Add-Check 'countdown decreases monotonically while running' ($mono -and ($samples[0] -gt $samples[-1])) ("samples: " + ($samples -join ','))

# run for 10s from start of the run
Start-Sleep -Seconds 5
$tRun1 = Get-Title $h
$r1 = Title-Seconds $tRun1
Send-Keys ' ' 600            # pause
$tPause1 = Get-Title $h
$p1 = Title-Seconds $tPause1
Start-Sleep -Seconds 8
$tPause2 = Get-Title $h
$p2 = Title-Seconds $tPause2
Add-Check 'paused remaining time is frozen (8s wall clock)' ($tPause1 -eq $tPause2) "$tPause1 | $tPause2"
Save-Shot (Join-Path $OutDir '11-paused.png') $h

Send-Keys ' ' 600            # resume
Start-Sleep -Seconds 10
$tRun2 = Get-Title $h
$r2 = Title-Seconds $tRun2
$elapsedRunning = 1500 - $r2
Add-Check 'resume continues from the frozen value (no reset)' ($r2 -lt $p2) "paused $p2 s -> after 10s resume $r2 s"
Add-Check 'no time lost or gained across pause/resume (within 2s tick/SendKeys slack)' ([Math]::Abs($r2 - ($p1 - 10)) -le 2) "frozen=$($p1)s, expected≈$($p1 - 10)s, actual=$($r2)s"
Write-Host "  title running: '$tRun1' (t=$r1 s) -> paused '$tPause1' -> resumed '$tRun2'"

# Ctrl+Shift+Q while paused: no stats must be recorded
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Add-Check 'app exits cleanly after pause/resume cycles' $proc.HasExited "HasExited=$($proc.HasExited)"
$j = Read-Settings
Add-Check 'aborted focus adds no statistics' (($j.CompletedToday -eq 0) -and ($j.TotalCompleted -eq 0) -and ($j.FocusMinutesToday -eq 0)) "CompletedToday=$($j.CompletedToday) TotalCompleted=$($j.TotalCompleted) FocusMinutesToday=$($j.FocusMinutesToday)"
Assert-NoAppRunning

Write-Host ''
Get-VerifyResults | Format-Table -AutoSize
$failed = @(Get-VerifyResults | Where-Object { -not $_.Pass }).Count
Write-Host ("TEST3: {0} passed / {1}" -f (@(Get-VerifyResults).Count - $failed), @(Get-VerifyResults).Count)
exit $failed
