# Probe: why did the bare 'S' key not reach the app? Compare PostMessage vs SendKeys vs UIA button invoke.
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
function WinCount($p) {
    return ([System.Windows.Automation.AutomationElement]::RootElement.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p)))).Count
}
function Post-Key([IntPtr]$h, [int]$vk) {
    $down = [IntPtr](0x00000001 -bor ($vk -shl 16))
    $up = [IntPtr](0xC0000001 -bor ($vk -shl 16))
    [void][VU]::PostMessage($h, 0x0100, [IntPtr]$vk, $down)   # WM_KEYDOWN
    Start-Sleep -Milliseconds 60
    [void][VU]::PostMessage($h, 0x0101, [IntPtr]$vk, $up)     # WM_KEYUP
}

Assert-NoAppRunning
Write-Settings @{ FocusMinutes = 1; ShortBreakMinutes = 1; LongBreakMinutes = 1; LongBreakInterval = 4
                 AutoStartNext = $false; AutoBigScreenOnFocus = $false; AlwaysOnTop = $false; UseMicaBackdrop = $false
                 HasWindowBounds = $false }
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 3
$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
Write-Host "start:   title='$(Get-Title $h)' round='$((Uia-ById $root 'TxtRound').Current.Name)' windows=$(WinCount $proc.Id)"

Write-Host "--- 1) PostMessage VK_S (0x53) directly to the window ---"
Post-Key $h 0x53
Start-Sleep -Milliseconds 900
$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
Write-Host "after:   title='$(Get-Title $h)' round='$((Uia-ById $root 'TxtRound').Current.Name)' windows=$(WinCount $proc.Id)"

Write-Host "--- 2) SendKeys 's' (as a user would type) ---"
$fg = Focus-App
Write-Host "  Focus-App returned (foreground==app): $fg"
[System.Windows.Forms.SendKeys]::SendWait('s')
Start-Sleep -Milliseconds 900
$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
Write-Host "after:   title='$(Get-Title $h)' round='$((Uia-ById $root 'TxtRound').Current.Name)' windows=$(WinCount $proc.Id)"

Write-Host "--- 3) UIA InvokePattern on the 跳过 button ---"
$btn = Uia-ById $root 'BtnSkip'
$inv = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
$inv.Invoke()
Start-Sleep -Milliseconds 900
$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
Write-Host "after:   title='$(Get-Title $h)' round='$((Uia-ById $root 'TxtRound').Current.Name)' windows=$(WinCount $proc.Id)"

Write-Host "--- 4) UIA InvokePattern on 重置 (R) and 开始 (space equivalent) ---"
$null = (Uia-ById $root 'BtnReset').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Start-Sleep -Milliseconds 700
Write-Host "after reset: title='$(Get-Title $h)'"
$null = (Uia-ById $root 'BtnPlay').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Start-Sleep -Milliseconds 2500
Write-Host "after play:  title='$(Get-Title $h)'"
Send-Keys '^+q' 1200
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning
