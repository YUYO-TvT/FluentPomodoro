# Exploratory: dump the WPF UI Automation tree of the settings panel.
param(
    [string]$Exe = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verify-dist\FluentPomodoro.exe',
    [string]$OutDir = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verification'
)
. (Join-Path $OutDir 'lib.ps1')
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Assert-NoAppRunning
Write-Settings @{ FocusMinutes = 7; ShortBreakMinutes = 3; LongBreakMinutes = 9; LongBreakInterval = 7
    AutoStartNext = $false; SoundEnabled = $false; KeepScreenAwake = $false; AlwaysOnTop = $false
    NotifyOnPhaseEnd = $false; AutoBigScreenOnFocus = $false; Theme = 'Dark'; UseMicaBackdrop = $false
    BigScreen = 'Full'; BigScreenTopmost = $false; HasWindowBounds = $true
    WindowLeft = 200; WindowTop = 150; WindowWidth = 600; WindowHeight = 700 }

$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 4
Send-Keys '^,' 1200

$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
Write-Host "root: $($root.Current.Name) / $($root.Current.ControlType.ProgrammaticName)"
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
function Dump($el, $depth) {
    if ($depth -gt 8) { return }
    $pad = ' ' * ($depth * 2)
    $ct = $el.Current.ControlType.ProgrammaticName -replace 'ControlType\.', ''
    $extra = ''
    try {
        $p = $el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        $extra = " Toggle=$($p.Current.ToggleState)"
    } catch {}
    try {
        $p = $el.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
        $extra = " Range=$($p.Current.Value) (min $($p.Current.Minimum) max $($p.Current.Maximum))"
    } catch {}
    try {
        $p = $el.GetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern)
        $sel = ($p.Current.GetSelection() | ForEach-Object { $_.Current.Name }) -join '|'
        $extra = " Selection=$sel"
    } catch {}
    Write-Host ("{0}{1} [{2}] Id='{3}' Name='{4}'{5}" -f $pad, $ct, $el.Current.IsOffscreen, $el.Current.AutomationId, $el.Current.Name, $extra)
    $c = $walker.GetFirstChild($el)
    while ($c -ne $null) { Dump $c ($depth + 1); $c = $walker.GetNextSibling($c) }
}
Dump $root 0

Send-Keys '^+q' 1200
Assert-NoAppRunning
