# Focused probe: what happens to an out-of-slider-range FocusMinutes value?
param(
    [string]$Exe = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verify-dist\FluentPomodoro.exe',
    [string]$OutDir = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verification',
    [int]$Focus = 999
)
. (Join-Path $OutDir 'lib.ps1')
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function Uia-ById($root, [string]$id) {
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id)
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
}

Assert-NoAppRunning
Write-Settings @{ FocusMinutes = $Focus; AutoBigScreenOnFocus = $false; AlwaysOnTop = $false; UseMicaBackdrop = $false
                 ShortBreakMinutes = 5; LongBreakMinutes = 15; LongBreakInterval = 4 }
$sp = Get-SettingsPath
$mt0 = (Get-Item $sp).LastWriteTimeUtc
Write-Host "probe FocusMinutes=$Focus : file wrote FocusMinutes=$((Read-Settings).FocusMinutes) mtime=$mt0"
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 6
Write-Host ("  +6s  title='{0}'" -f (Get-Title $h))
Write-Host ("  +6s  file: FocusMinutes={0} mtime={1} (changed={2})" -f (Read-Settings).FocusMinutes, (Get-Item $sp).LastWriteTimeUtc, ((Get-Item $sp).LastWriteTimeUtc -ne $mt0))
$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
$slF = Uia-ById $root 'SldFocus'; $lblF = Uia-ById $root 'LblFocus'
Write-Host ("  panel(closed): SldFocus={0} (max {1}) LblFocus='{2}'" -f `
    ($slF.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)).Current.Value, `
    ($slF.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)).Current.Maximum, $lblF.Current.Name)
Send-Keys '^,' 1200
$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
$slF = Uia-ById $root 'SldFocus'; $lblF = Uia-ById $root 'LblFocus'
Write-Host ("  panel(open):   SldFocus={0} LblFocus='{1}'" -f ($slF.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)).Current.Value, $lblF.Current.Name)
# count top-level windows of the process (a MessageBox would show up here)
$cnt = ([System.Windows.Automation.AutomationElement]::RootElement.FindAll(
    [System.Windows.Automation.TreeScope]::Children,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc.Id)))).Count
Write-Host "  top-level windows of pid $($proc.Id): $cnt"
Save-Shot (Join-Path $OutDir 'probe-focus.png') $h
$t = Get-Title $h
Start-Sleep -Seconds 4
Write-Host ("  +10s title='{0}' (changed={1})" -f (Get-Title $h), ((Get-Title $h) -ne $t))
Write-Host ("  +10s file: FocusMinutes={0} mtime={1}" -f (Read-Settings).FocusMinutes, (Get-Item $sp).LastWriteTimeUtc)
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Write-Host ("  after exit: file FocusMinutes={0}" -f (Read-Settings).FocusMinutes)
Assert-NoAppRunning
