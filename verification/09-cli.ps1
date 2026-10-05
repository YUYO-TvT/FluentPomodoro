# Supplementary test 9: command-line options.
param(
    [string]$Exe = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verify-dist\FluentPomodoro.exe',
    [string]$OutDir = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verification'
)
. (Join-Path $OutDir 'lib.ps1')
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen

Write-Host "=== TEST 9A: --focus is documented as temporary; does it persist?  ($(Get-Date -Format o)) ==="
Assert-NoAppRunning
Write-Settings @{ FocusMinutes = 25; AutoBigScreenOnFocus = $false; AutoStartNext = $false; AlwaysOnTop = $false; HasWindowBounds = $false }
$proc = Start-Process -FilePath $Exe -ArgumentList '--focus', '10' -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 3
Add-Check '--focus 10 overrides the duration for this run (title 10:00)' ((Get-Title $h) -match '10:00') (Get-Title $h)
Save-Shot (Join-Path $OutDir '31-cli-focus10.png') $h
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
$j = Read-Settings
Add-Check 'BUG-CONFIRMED: the "temporary" --focus override is written back to settings.json on exit' ($j.FocusMinutes -eq 10) "settings.json FocusMinutes=$($j.FocusMinutes) (was 25 before launch)"
Assert-NoAppRunning

Write-Host ''
Write-Host "=== TEST 9B: --focus clamping  ($(Get-Date -Format o)) ==="
Write-Settings @{ FocusMinutes = 25; AutoBigScreenOnFocus = $false; AutoStartNext = $false; AlwaysOnTop = $false; HasWindowBounds = $false }
$proc = Start-Process -FilePath $Exe -ArgumentList '--focus', '999' -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 3
Add-Check '--focus 999 clamps to 120 minutes (title 2:00:00)' ((Get-Title $h) -match '2:00:00') (Get-Title $h)
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning

Write-Host ''
Write-Host "=== TEST 9C: --bigscreen / --mega / --start  ($(Get-Date -Format o)) ==="
Assert-NoAppRunning
Write-Settings @{ FocusMinutes = 25; AutoBigScreenOnFocus = $false; AutoStartNext = $false; AlwaysOnTop = $false; HasWindowBounds = $false; BigScreen = 'Full' }
$proc = Start-Process -FilePath $Exe -ArgumentList '--bigscreen' -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 5
$r = Get-Rect $h
Write-Host "  --bigscreen: $(Format-Rect $h)  title='$(Get-Title $h)'"
Add-Check '--bigscreen enters the remembered 全屏 mode at startup' ((($r.R - $r.L) -ge $vs.Width) -and (($r.B - $r.T) -ge $vs.Height)) (Format-Rect $h)
Save-Screen (Join-Path $OutDir '32-cli-bigscreen.png')
Send-Keys '{ESC}' 1600
Add-Check 'Esc returns to a 640x780 window' (((Get-Rect $h).R - (Get-Rect $h).L -eq 640) -and ((Get-Rect $h).B - (Get-Rect $h).T -eq 780)) (Format-Rect $h)
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning

Write-Settings @{ FocusMinutes = 25; AutoBigScreenOnFocus = $false; AutoStartNext = $false; AlwaysOnTop = $false; HasWindowBounds = $false; BigScreen = 'Full' }
$proc = Start-Process -FilePath $Exe -ArgumentList '--start' -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 5
$t = Get-Title $h
Write-Host "  --start alone: title='$t' rect=$(Format-Rect $h)"
Add-Check 'control: --start alone starts the countdown' ($t -match '24:5') "title='$t'"
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning

Write-Settings @{ FocusMinutes = 25; AutoBigScreenOnFocus = $false; AutoStartNext = $false; AlwaysOnTop = $false; HasWindowBounds = $false; BigScreen = 'Mega' }
$proc = Start-Process -FilePath $Exe -ArgumentList '--mega', '--start' -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 5
$r = Get-Rect $h
$t = Get-Title $h
Write-Host "  --mega --start: rect=$(Format-Rect $h) title='$t'"
Add-Check '--mega makes the window fullscreen' ((($r.R - $r.L) -ge $vs.Width) -and (($r.B - $r.T) -ge $vs.Height)) (Format-Rect $h)
Add-Check 'BUG-CONFIRMED: --start is ignored when combined with --mega/--bigscreen (README advertises this combination)' ($t -match '25:00') "title='$t' (README example: --mega --start --focus 10 => 巨幕大屏、立刻开始)"
Save-Screen (Join-Path $OutDir '33-cli-mega-start.png')
Send-Keys ' ' 2600
$t2 = Get-Title $h
Add-Check 'Space still starts the timer afterwards' ($t2 -match '24:5') "title='$t2'"
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning

Write-Host ''
Get-VerifyResults | Format-Table -AutoSize
$failed = @(Get-VerifyResults | Where-Object { -not $_.Pass }).Count
Write-Host ("TEST9: {0} passed / {1}" -f (@(Get-VerifyResults).Count - $failed), @(Get-VerifyResults).Count)
exit 0
