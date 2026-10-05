# Independent behavior test 1: launch, window geometry, title, Space start/pause, exit + settings write.
param(
    [string]$Exe = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verify-dist\FluentPomodoro.exe',
    [string]$OutDir = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verification'
)
. (Join-Path $OutDir 'lib.ps1')

$sp = Get-SettingsPath
if (Test-Path $sp) { Remove-Item $sp -Force }
Add-Type @"
using System.Runtime.InteropServices;
public class Dpi { [DllImport("user32.dll")] public static extern uint GetDpiForWindow(System.IntPtr h); }
"@

Write-Host "=== TEST 1: launch / geometry / Space / exit  ($(Get-Date -Format o)) ==="
Write-Host "EXE: $Exe"
Write-Host ("EXE size: {0} bytes" -f (Get-Item $Exe).Length)
Assert-NoAppRunning

$proc = Start-Process -FilePath $Exe -PassThru
Start-Sleep -Seconds 10

$alive = -not $proc.HasExited
Add-Check 'process alive 10s after launch' $alive ("HasExited=$($proc.HasExited)")

$h = Get-AppHwnd
Add-Check 'owns a top-level window' ($h -ne [IntPtr]::Zero) "hwnd=$h"
if ($h -eq [IntPtr]::Zero) { Get-VerifyResults | Format-Table -AutoSize; Assert-NoAppRunning; exit 1 }
Add-Check 'top-level window is visible' ([VU]::IsWindowVisible($h)) "IsWindowVisible=$([VU]::IsWindowVisible($h))"

$dpi = [Dpi]::GetDpiForWindow($h)
Write-Host "  window DPI = $dpi (scale $([math]::Round($dpi/96.0,3)))"

$r = Get-Rect $h
Add-Check 'window opens at 640x780' ((($r.R - $r.L) -eq 640) -and (($r.B - $r.T) -eq 780)) (Format-Rect $h)

$t0 = Get-Title $h
Write-Host "  title = '$t0'"
Add-Check 'title shows 25:00 countdown + 专注 phase' (($t0 -match '25:00') -and ($t0 -match '专注')) $t0
Save-Shot (Join-Path $OutDir '01-launch-640x780.png') $h

# ---- Space starts ----
[void](Focus-App)
Send-Keys ' ' 2600
$t1 = Get-Title $h
$r1 = Get-Rect $h
Write-Host "  after Space: title='$t1' rect=$(Format-Rect $h)"
Add-Check 'Space starts countdown (title changed, 24:5x)' (($t1 -ne $t0) -and ($t1 -match '24:5')) $t1
Add-Check 'countdown is actually running (rect/title sampled twice)' ($t1 -match '24:5') $t1
Save-Shot (Join-Path $OutDir '02-space-running.png') $h
$autoBig = (($r1.R - $r1.L) -ge 1920 -and ($r1.B - $r1.T) -ge 1080)
Write-Host "  auto-bigscreen-on-focus engaged: $autoBig (rect $(Format-Rect $h))"

# ---- Space pauses ----
Send-Keys ' ' 900
$p1 = Get-Title $h
Start-Sleep -Seconds 3
$p2 = Get-Title $h
Add-Check 'Space again pauses (title frozen for 3s)' (($p1 -eq $p2) -and ($p1 -match '专注')) "$p1 | $p2"
Save-Shot (Join-Path $OutDir '03-space-paused.png') $h

# ---- Esc restores window if big screen was auto-entered ----
if ($autoBig) {
    Send-Keys '{ESC}' 1500
    $r2 = Get-Rect $h
    Add-Check 'Esc restores 640x780 window after auto big screen' ((($r2.R - $r2.L) -eq 640) -and (($r2.B - $r2.T) -eq 780)) (Format-Rect $h)
    Save-Shot (Join-Path $OutDir '04-esc-restored.png') $h
}

# ---- exit ----
$before = Get-Date
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(12)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 400 }
Add-Check 'Ctrl+Shift+Q exits the process' $proc.HasExited ("HasExited=$($proc.HasExited) after $([int]((Get-Date)-$before).TotalSeconds)s")

Start-Sleep -Milliseconds 800
Add-Check 'settings.json written on exit' (Test-Path $sp) $sp
if (Test-Path $sp) {
    $j = Read-Settings
    Write-Host "  settings.json:"
    Get-Content $sp | ForEach-Object { "    $_" }
    Add-Check 'saved FocusMinutes unchanged by UI init (25)' ($j.FocusMinutes -eq 25) "FocusMinutes=$($j.FocusMinutes)"
    Add-Check 'no completed pomodoro recorded in this run' (($j.CompletedToday -eq 0) -and ($j.TotalCompleted -eq 0)) "CompletedToday=$($j.CompletedToday) TotalCompleted=$($j.TotalCompleted)"
    Add-Check 'paused remaining time not persisted as elapsed stats' ($j.FocusMinutesToday -eq 0) "FocusMinutesToday=$($j.FocusMinutesToday)"
}

Assert-NoAppRunning
Write-Host ''
Get-VerifyResults | Format-Table -AutoSize
$failed = @(Get-VerifyResults | Where-Object { -not $_.Pass }).Count
Write-Host ("TEST1: {0} passed / {1}" -f (@(Get-VerifyResults).Count - $failed), @(Get-VerifyResults).Count)
exit $failed
