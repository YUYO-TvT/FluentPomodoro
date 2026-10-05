# Supplementary test 10: FocusLock blocks close/minimize but Ctrl+Shift+Q always escapes.
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

Write-Host "=== TEST 10: 专注锁定 (FocusLock) vs close/minimize/force-exit  ($(Get-Date -Format o)) ==="
Assert-NoAppRunning
Write-Settings @{ FocusMinutes = 25; FocusLock = $true; AutoStartNext = $false; AutoBigScreenOnFocus = $false
                 AlwaysOnTop = $false; HasWindowBounds = $false }
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 3
Send-Keys ' ' 2600
Add-Check 'focus lock run started (title 24:5x, 专注)' ((Get-Title $h) -match '24:5') (Get-Title $h)

# 1) minimize is intercepted
[void][VU]::SendMessage($h, 0x0112, [IntPtr]0xF020, [IntPtr]::Zero)   # SC_MINIMIZE
Start-Sleep -Milliseconds 900
Add-Check 'minimize blocked while locked focus is running' (-not [VU]::IsIconic($h)) "IsIconic=$([VU]::IsIconic($h))"

# 2) the window close button is vetoed
$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
$null = (Uia-ById $root 'BtnClose').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Start-Sleep -Seconds 1
Add-Check 'close button vetoed during locked focus' (-not $proc.HasExited) "HasExited=$($proc.HasExited)"
Save-Shot (Join-Path $OutDir '34-focuslock-close-blocked.png') $h

# 3) WM_CLOSE also vetoed
[void][VU]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 1
Add-Check 'WM_CLOSE vetoed during locked focus' (-not $proc.HasExited) "HasExited=$($proc.HasExited)"

# 4) Ctrl+Shift+Q must always escape
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(12)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Add-Check 'Ctrl+Shift+Q forces exit even while locked' $proc.HasExited "HasExited=$($proc.HasExited)"
Assert-NoAppRunning

Write-Host ''
Get-VerifyResults | Format-Table -AutoSize
$failed = @(Get-VerifyResults | Where-Object { -not $_.Pass }).Count
Write-Host ("TEST10: {0} passed / {1}" -f (@(Get-VerifyResults).Count - $failed), @(Get-VerifyResults).Count)
exit $failed
