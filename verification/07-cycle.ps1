# Independent behavior test 7: phase / round / long-break cycle across many cycles (real app, S = skip).
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
# NOTE: bare-letter SendKeys ('s') is swallowed by the active Chinese IME in this session
# (see verification/probe-ime.ps1), so skip is driven through the 跳过 button's UI Automation
# InvokePattern, which is the same code path as a real mouse click (OnSkip -> SkipPhase).
function Invoke-Skip([IntPtr]$h) {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
    $btn = Uia-ById $root 'BtnSkip'
    $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Milliseconds 900
}

function Get-Phase([string]$title) {
    if ($title -match '短休息') { return 'Short' }
    if ($title -match '长休息') { return 'Long' }
    if ($title -match '专注') { return 'Focus' }
    return "?($title)"
}

Write-Host "=== TEST 7: phase/round cycle via skip  ($(Get-Date -Format o)) ==="
foreach ($interval in 4, 2) {
    Write-Host "--- LongBreakInterval = $interval ---"
    Assert-NoAppRunning
    Write-Settings @{ FocusMinutes = 1; ShortBreakMinutes = 1; LongBreakMinutes = 1; LongBreakInterval = $interval
                     AutoStartNext = $false; AutoBigScreenOnFocus = $false; AlwaysOnTop = $false; UseMicaBackdrop = $false
                     HasWindowBounds = $false }
    $proc = Start-Process -FilePath $Exe -PassThru
    $h = Wait-AppWindow 20
    Start-Sleep -Seconds 2
    $seq = @()
    $rounds = @()
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
    $seq += (Get-Phase (Get-Title $h)); $rounds += (Uia-ById $root 'TxtRound').Current.Name
    for ($i = 1; $i -le 12; $i++) {
        Invoke-Skip $h
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
        $seq += (Get-Phase (Get-Title $h))
        $rounds += (Uia-ById $root 'TxtRound').Current.Name
    }
    Write-Host ("  phases: " + ($seq -join ' -> '))
    for ($i = 0; $i -lt $seq.Count; $i++) { Write-Host ("    step {0,2}: {1,-6} {2}" -f $i, $seq[$i], $rounds[$i]) }
    if ($interval -eq 4) {
        $expect = @('Focus','Short','Focus','Short','Focus','Short','Focus','Long','Focus','Short','Focus','Short','Focus')
        Add-Check 'interval=4 cycle is F S F S F S F L F S F S F (13 steps)' (($seq -join ',') -eq ($expect -join ',')) ($seq -join ' -> ')
        Add-Check 'round counter resets to 1 after the long break' ($rounds[8] -match '第 1 / 4') $rounds[8]
        Add-Check 'round counter reaches 4 before the long break' ($rounds[6] -match '第 4 / 4') $rounds[6]
        Add-Check 'no long break before the 4th pomodoro' (-not (($seq[0..6]) -contains 'Long')) ($seq[0..6] -join ' -> ')
    } else {
        $expect = @('Focus','Short','Focus','Long','Focus','Short','Focus','Long','Focus','Short','Focus','Long','Focus')
        Add-Check 'interval=2 cycle is F S F L F S F L F S F L F (13 steps)' (($seq -join ',') -eq ($expect -join ',')) ($seq -join ' -> ')
        Add-Check 'long break every 2nd focus pomodoro' (($seq[3] -eq 'Long') -and ($seq[7] -eq 'Long') -and ($seq[11] -eq 'Long')) ($seq -join ' -> ')
    }
    Send-Keys '^+q' 1200
    $deadline = (Get-Date).AddSeconds(10)
    while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
}
Assert-NoAppRunning
Write-Host ''
Get-VerifyResults | Format-Table -AutoSize
$failed = @(Get-VerifyResults | Where-Object { -not $_.Pass }).Count
Write-Host ("TEST7: {0} passed / {1}" -f (@(Get-VerifyResults).Count - $failed), @(Get-VerifyResults).Count)
exit $failed
