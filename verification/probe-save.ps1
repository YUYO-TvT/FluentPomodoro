# Decisive probe: does OnDurationChanged run at launch, and does mid-run Save work?
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

Assert-NoAppRunning
Write-Settings @{ FocusMinutes = 150; ShortBreakMinutes = 5; LongBreakMinutes = 15; LongBreakInterval = 4
                 AutoBigScreenOnFocus = $false; AlwaysOnTop = $false; UseMicaBackdrop = $false; SoundEnabled = $true }
$sp = Get-SettingsPath
Write-Host "wrote FocusMinutes=150; on disk now: $((Read-Settings).FocusMinutes)"
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
# poll the file while the app initialises
for ($i = 0; $i -lt 20; $i++) {
    $j = Read-Settings
    Write-Host ("  t={0,4:N1}s file.FocusMinutes={1} mtime={2:HH:mm:ss.fff}" -f ($i * 0.3), $j.FocusMinutes, (Get-Item $sp).LastWriteTime)
    Start-Sleep -Milliseconds 300
}
Write-Host "  title now: '$(Get-Title $h)'"
Send-Keys '^,' 1200
$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
$slF = Uia-ById $root 'SldFocus'
$lblF = Uia-ById $root 'LblFocus'
$tgl = Uia-ById $root 'TglSound'
Write-Host ("  panel: SldFocus={0} LblFocus='{1}'" -f ($slF.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)).Current.Value, $lblF.Current.Name)
# force a mid-run Save through OnSettingToggled
$tp = $tgl.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
$tp.Toggle(); Start-Sleep -Milliseconds 900
Write-Host ("  after TglSound toggle -> file.FocusMinutes={0} SoundEnabled={1} mtime={2:HH:mm:ss.fff}" -f (Read-Settings).FocusMinutes, (Read-Settings).SoundEnabled, (Get-Item $sp).LastWriteTime)
Write-Host "  title after toggle: '$(Get-Title $h)'"
Save-Shot (Join-Path $OutDir 'probe-save.png') $h
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Write-Host ("  after exit: file.FocusMinutes={0}" -f (Read-Settings).FocusMinutes)
Assert-NoAppRunning
