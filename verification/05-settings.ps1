# Independent behavior test 5: settings round-trip / UI-init clobber / invalid values / slider mismatch.
param(
    [string]$Exe = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verify-dist\FluentPomodoro.exe',
    [string]$OutDir = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verification'
)
. (Join-Path $OutDir 'lib.ps1')
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function Uia-ById($root, [string]$id) {
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id)
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
}
function Uia-Range($el) { return ($el.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)).Current.Value }
function Uia-Toggle($el) { return ($el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)).Current.ToggleState.ToString() }
function Uia-Text($el) { return $el.Current.Name }
function Uia-WindowTitle($h) { return ([System.Windows.Automation.AutomationElement]::FromHandle($h)).Current.Name }
function Get-WindowCount([int]$pid_) {
    $all = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $pid_)))
    return $all.Count
}
function Center-Pixel([string]$png) {
    $bmp = [System.Drawing.Bitmap]::FromFile($png)
    $c = $bmp.GetPixel([int]($bmp.Width * 0.06), [int]($bmp.Height * 0.5))
    $bmp.Dispose()
    return "R=$($c.R) G=$($c.G) B=$($c.B)"
}

Write-Host "=== TEST 5A: settings round-trip, UI-init must not clobber  ($(Get-Date -Format o)) ==="
Assert-NoAppRunning
$expected = [ordered]@{
    FocusMinutes = 7; ShortBreakMinutes = 3; LongBreakMinutes = 9; LongBreakInterval = 7
    AutoStartNext = $false; SoundEnabled = $false; KeepScreenAwake = $true; AlwaysOnTop = $false
    NotifyOnPhaseEnd = $false; FocusLock = $true; AutoBigScreenOnFocus = $true
    Theme = 'Dark'; UseMicaBackdrop = $false; BigScreen = 'Full'; BigScreenTopmost = $false
    HasWindowBounds = $true; WindowLeft = 200; WindowTop = 150; WindowWidth = 600; WindowHeight = 700
}
Write-Settings $expected
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 4
$r = Get-Rect $h
Add-Check 'saved window bounds restored (600x700 @ 200,150)' ((($r.R - $r.L) -eq 600) -and (($r.B - $r.T) -eq 700) -and ($r.L -eq 200) -and ($r.T -eq 150)) (Format-Rect $h)
Add-Check 'saved FocusMinutes used (title 07:00)' ((Get-Title $h) -match '07:00') (Get-Title $h)
Save-Shot (Join-Path $OutDir '18-saved-dark-theme.png') $h
$px = Center-Pixel (Join-Path $OutDir '18-saved-dark-theme.png')
Add-Check 'BUG-CONFIRMED: saved Theme=Dark renders a LIGHT window (pixel not dark)' ($px -notmatch '^R=3\d G=3\d B=3\d$') $px

Send-Keys '^,' 1200
Save-Shot (Join-Path $OutDir '19-dark-settings.png') $h
$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
$slF = Uia-ById $root 'SldFocus'; $slS = Uia-ById $root 'SldShort'; $slL = Uia-ById $root 'SldLong'; $slI = Uia-ById $root 'SldInterval'
$lblF = Uia-ById $root 'LblFocus'; $lblI = Uia-ById $root 'LblInterval'
Add-Check 'settings panel shows saved durations (7/3/9/7)' (((Uia-Range $slF) -eq 7) -and ((Uia-Range $slS) -eq 3) -and ((Uia-Range $slL) -eq 9) -and ((Uia-Range $slI) -eq 7)) "focus=$(Uia-Range $slF) short=$(Uia-Range $slS) long=$(Uia-Range $slL) interval=$(Uia-Range $slI)"
Write-Host "  labels: LblFocus='$(Uia-Text $lblF)' LblInterval='$(Uia-Text $lblI)'"
$toggles = @{}
foreach ($id in 'TglAutoStart','TglSound','TglKeepAwake','TglNotify','TglTopmost','TglLock','TglAutoBig','TglBigTopmost','TglMica') {
    $toggles[$id] = Uia-Toggle (Uia-ById $root $id)
}
Write-Host ("  toggles: " + (($toggles.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '))
Add-Check 'toggles show saved values (AutoStart Off / KeepAwake On / Topmost Off / Lock On / AutoBig On / BigTopmost Off / Mica Off)' (
    $toggles['TglAutoStart'] -eq 'Off' -and $toggles['TglSound'] -eq 'Off' -and $toggles['TglKeepAwake'] -eq 'On' -and
    $toggles['TglNotify'] -eq 'Off' -and $toggles['TglTopmost'] -eq 'Off' -and $toggles['TglLock'] -eq 'On' -and
    $toggles['TglAutoBig'] -eq 'On' -and $toggles['TglBigTopmost'] -eq 'Off' -and $toggles['TglMica'] -eq 'Off') ($toggles | ConvertTo-Json -Compress)
$cmb = Uia-ById $root 'CmbTheme'
$sel = ($cmb.GetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern)).Current.GetSelection()[0].Current.Name
Add-Check 'theme combo shows saved Dark' ($sel -eq '深色') "selection=$sel"

Send-Keys '{ESC}' 900
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
$j = Read-Settings
$diff = @()
foreach ($k in $expected.Keys) { if ("$($j.$k)" -ne "$($expected[$k])") { $diff += "${k}: wrote=$($expected[$k]) read=$($j.$k)" } }
Add-Check 'ALL saved settings survive a UI-initialised launch+exit unchanged' ($diff.Count -eq 0) $(if ($diff.Count) { $diff -join '; ' } else { 'no differences' })
Assert-NoAppRunning

Write-Host ''
Write-Host "=== TEST 5B: invalid enum value in settings.json  ($(Get-Date -Format o)) ==="
Write-Settings @{ FocusMinutes = 1; Theme = 'Bogus'; CompletedToday = 5; TotalCompleted = 42; FocusMinutesToday = 5; StreakDays = 3; LastCompletedDate = '2026-10-01' }
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 4
Add-Check 'app still starts with an invalid enum (no crash)' ($h -ne [IntPtr]::Zero) "hwnd=$h title='$(Get-Title $h)'"
Add-Check 'no error dialog window (only the main window belongs to the process)' ((Get-WindowCount $proc.Id) -eq 1) "top-level windows of pid $($proc.Id) = $(Get-WindowCount $proc.Id)"
$titleBad = Get-Title $h
Write-Host "  title with Theme='Bogus' + FocusMinutes=1: '$titleBad'"
Save-Shot (Join-Path $OutDir '20-invalid-enum.png') $h
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
$j = Read-Settings
Write-Host ("  after exit: FocusMinutes={0} CompletedToday={1} TotalCompleted={2} StreakDays={3} Theme={4}" -f $j.FocusMinutes, $j.CompletedToday, $j.TotalCompleted, $j.StreakDays, $j.Theme)
Add-Check 'BUG-CONFIRMED: one bad enum string discards the whole file (stats reset to 0)' (($j.CompletedToday -eq 0) -and ($j.TotalCompleted -eq 0) -and ($j.FocusMinutes -eq 25)) "FocusMinutes=$($j.FocusMinutes) CompletedToday=$($j.CompletedToday) TotalCompleted=$($j.TotalCompleted)"
Assert-NoAppRunning

Write-Host ''
Write-Host "=== TEST 5C: out-of-range numbers (valid enums)  ($(Get-Date -Format o)) ==="
Write-Host "  current Normalize(): Focus 1-120, Short 1-30, Long 5-60, Interval 2-12, Window >= 420"
Write-Settings @{ FocusMinutes = 999; ShortBreakMinutes = 0; LongBreakMinutes = -5; LongBreakInterval = 99
                 WindowWidth = 10; WindowHeight = 10; HasWindowBounds = $true; WindowLeft = 50; WindowTop = 50
                 AutoBigScreenOnFocus = $false; AlwaysOnTop = $false; UseMicaBackdrop = $false }
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 4
Add-Check 'app survives absurd numbers (no crash)' ($h -ne [IntPtr]::Zero) "hwnd=$h"
$r = Get-Rect $h
Write-Host "  title='$(Get-Title $h)' rect=$(Format-Rect $h)"
Add-Check 'FocusMinutes 999 clamped to 120 by Normalize (title 2:00:00)' ((Get-Title $h) -match '2:00:00') (Get-Title $h)
Add-Check 'window clamped to MinWidth/MinHeight (480x560)' ((($r.R - $r.L) -eq 480) -and (($r.B - $r.T) -eq 560)) (Format-Rect $h)
Send-Keys '^,' 1200
$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
$slF = Uia-ById $root 'SldFocus'; $lblF = Uia-ById $root 'LblFocus'
$slI = Uia-ById $root 'SldInterval'; $lblI = Uia-ById $root 'LblInterval'
$slL = Uia-ById $root 'SldLong'; $slS = Uia-ById $root 'SldShort'
Write-Host "  sliders: focus=$(Uia-Range $slF) short=$(Uia-Range $slS) long=$(Uia-Range $slL) interval=$(Uia-Range $slI); labels: '$(Uia-Text $lblF)' '$(Uia-Text $lblI)'"
Add-Check 'clamped values match the slider ranges (120 / 1 / 5 / 12)' (((Uia-Range $slF) -eq 120) -and ((Uia-Range $slS) -eq 1) -and ((Uia-Range $slL) -eq 5) -and ((Uia-Range $slI) -eq 12)) "focus=$(Uia-Range $slF) short=$(Uia-Range $slS) long=$(Uia-Range $slL) interval=$(Uia-Range $slI)"
Add-Check 'label and slider agree (no 120-vs-999 mismatch)' (((Uia-Text $lblF) -match '120') -and ((Uia-Text $lblI) -match '12')) "'$(Uia-Text $lblF)' / '$(Uia-Text $lblI)'"
Save-Shot (Join-Path $OutDir '21-clamped-settings.png') $h
$before = Read-Settings
$pat = $slI.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
$pat.SetValue(6.0)
Start-Sleep -Seconds 1
$after = Read-Settings
$lblF2 = Uia-Text (Uia-ById ([System.Windows.Automation.AutomationElement]::FromHandle($h)) 'LblFocus')
Add-Check 'editing the interval slider keeps FocusMinutes consistent (no silent rewrite)' (($before.FocusMinutes -eq 999) -and ($after.FocusMinutes -eq 120) -and ($after.LongBreakInterval -eq 6)) "file before=$($before.FocusMinutes)/$($before.LongBreakInterval) after=$($after.FocusMinutes)/$($after.LongBreakInterval) label '$lblF2'"
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
$j = Read-Settings
Add-Check 'exit persists the clamped, valid ranges' (($j.FocusMinutes -eq 120) -and ($j.ShortBreakMinutes -eq 1) -and ($j.LongBreakMinutes -eq 5) -and ($j.LongBreakInterval -eq 6)) "focus=$($j.FocusMinutes) short=$($j.ShortBreakMinutes) long=$($j.LongBreakMinutes) interval=$($j.LongBreakInterval)"
Assert-NoAppRunning

Write-Host ''
Write-Host "=== TEST 5D: malformed / wrong-typed settings.json  ($(Get-Date -Format o)) ==="
Set-Content -Path (Get-SettingsPath) -Value '{ "FocusMinutes": 1, "Theme": ' -Encoding UTF8
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 3
Add-Check 'app starts with truncated JSON (no crash)' ($h -ne [IntPtr]::Zero) "hwnd=$h title='$(Get-Title $h)'"
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
$j = Read-Settings
Add-Check 'truncated JSON falls back to defaults and rewrites a valid file' (($j.FocusMinutes -eq 25) -and ($j.CompletedToday -eq 0)) "FocusMinutes=$($j.FocusMinutes)"
Assert-NoAppRunning

Set-Content -Path (Get-SettingsPath) -Value '{ "FocusMinutes": "abc", "TotalCompleted": 9 }' -Encoding UTF8
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 3
Add-Check 'app starts with wrong-typed value (no crash)' ($h -ne [IntPtr]::Zero) "hwnd=$h title='$(Get-Title $h)'"
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
$j = Read-Settings
Add-Check 'wrong-typed value also discards the whole file (TotalCompleted 9 -> 0)' ($j.TotalCompleted -eq 0) "TotalCompleted=$($j.TotalCompleted) FocusMinutes=$($j.FocusMinutes)"
Assert-NoAppRunning

Write-Host ''
Write-Host "=== TEST 5E: is the saved theme preference applied at startup?  ($(Get-Date -Format o)) ==="
Write-Settings @{ Theme = 'Dark'; UseMicaBackdrop = $false; HasWindowBounds = $false; AutoBigScreenOnFocus = $false; AlwaysOnTop = $false; FocusMinutes = 25 }
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 4
Save-Shot (Join-Path $OutDir '22-theme-dark-in-settings.png') $h
$pxNoCli = Center-Pixel (Join-Path $OutDir '22-theme-dark-in-settings.png')
$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
Send-Keys '^,' 1000
$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
$sel = ($((Uia-ById $root 'CmbTheme')).GetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern)).Current.GetSelection()[0].Current.Name
Add-Check 'saved Theme=Dark is shown in the combo' ($sel -eq '深色') "combo=$sel"
Add-Check 'BUG-CONFIRMED: saved Theme=Dark is NOT applied at startup (window renders light)' ($pxNoCli -notmatch '^R=3\d G=3\d B=3\d$') "background pixel $pxNoCli (dark theme would be ~R=32 G=32 B=32)"
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning

$proc = Start-Process -FilePath $Exe -ArgumentList '--dark' -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 4
Save-Shot (Join-Path $OutDir '23-forced-dark-cli.png') $h
$pxCli = Center-Pixel (Join-Path $OutDir '23-forced-dark-cli.png')
Add-Check '--dark CLI flag does render the dark palette (rendering path works)' ($pxCli -match '^R=(\d+) G=(\d+) B=(\d+)$' -and [int]$Matches[1] -lt 80) "background pixel $pxCli"
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning

# UI flow: pick 深色 in the combo, then restart
Write-Settings @{ Theme = 'System'; UseMicaBackdrop = $false; HasWindowBounds = $false; AutoBigScreenOnFocus = $false; AlwaysOnTop = $false }
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 4
Send-Keys '^,' 1200
$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
$cmp = Uia-ById $root 'CmbTheme'
$ok = $false
try {
    ($cmp.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)).Expand()
    Start-Sleep -Milliseconds 900
    $cond = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)),
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, '深色')))
    $item = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if ($item) { ($item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)).Select(); $ok = $true }
} catch { Write-Host "  combo selection failed: $($_.Exception.Message)" }
Start-Sleep -Seconds 2
Save-Shot (Join-Path $OutDir '24-live-dark-selected.png') $h
$pxLive = Center-Pixel (Join-Path $OutDir '24-live-dark-selected.png')
Add-Check 'selecting 深色 in the combo switches the theme live' ($ok -and ($pxLive -match '^R=(\d+) G=(\d+) B=(\d+)$') -and ([int]$Matches[1] -lt 80)) "selected=$ok pixel=$pxLive"
$j = Read-Settings
Add-Check 'choosing 深色 is persisted to settings.json' ($j.Theme -eq 'Dark') "Theme=$($j.Theme)"
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning

$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 4
Save-Shot (Join-Path $OutDir '25-restart-after-dark-choice.png') $h
$pxRestart = Center-Pixel (Join-Path $OutDir '25-restart-after-dark-choice.png')
Add-Check 'BUG-CONFIRMED: after choosing 深色 and restarting, the window is light again' ($pxRestart -notmatch '^R=3\d G=3\d B=3\d$') "background pixel $pxRestart (settings.json Theme=$((Read-Settings).Theme))"
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning

Write-Host ''
Get-VerifyResults | Format-Table -AutoSize
$failed = @(Get-VerifyResults | Where-Object { -not $_.Pass }).Count
Write-Host ("TEST5: {0} passed / {1}; lines named BUG-CONFIRMED PASS when the defect reproduced (they are findings, not app failures)" -f (@(Get-VerifyResults).Count - $failed), @(Get-VerifyResults).Count)
exit 0
