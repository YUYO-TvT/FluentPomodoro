# Supplementary test 8: theme combo (live switch + restart), and SetThreadExecutionState pairing via powercfg /requests.
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
function Center-Pixel([string]$png) {
    $bmp = [System.Drawing.Bitmap]::FromFile($png)
    $c = $bmp.GetPixel([int]($bmp.Width * 0.06), [int]($bmp.Height * 0.5))
    $bmp.Dispose(); return "R=$($c.R) G=$($c.G) B=$($c.B)"
}
function Is-Dark([string]$px) { return ($px -match '^R=(\d+) G=(\d+) B=(\d+)$' -and [int]$Matches[1] -lt 80) }

Write-Host "=== TEST 8A: pick 深色 through the UI, then restart  ($(Get-Date -Format o)) ==="
Assert-NoAppRunning
Write-Settings @{ Theme = 'System'; UseMicaBackdrop = $false; HasWindowBounds = $false; AutoBigScreenOnFocus = $false; AlwaysOnTop = $false; KeepScreenAwake = $true }
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 3
Save-Shot (Join-Path $OutDir '28-before-theme-change.png') $h
$pxBefore = Center-Pixel (Join-Path $OutDir '28-before-theme-change.png')
Send-Keys '^,' 1300
$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
$cmp = Uia-ById $root 'CmbTheme'
$pt = $null
try { $pt = $cmp.GetClickablePoint() } catch { Write-Host "  GetClickablePoint failed: $($_.Exception.Message)" }
$clicked = $false
if ($pt) {
    Click-At ([int]$pt.X) ([int]$pt.Y)
    Start-Sleep -Milliseconds 900
    $cond = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)),
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, '深色')),
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc.Id)))
    $item = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if ($item) {
        $ip = $item.GetClickablePoint()
        Click-At ([int]$ip.X) ([int]$ip.Y)
        $clicked = $true
    } else { Write-Host "  combo item '深色' not found in the popup" }
} else { Write-Host "  combo has no clickable point" }
Start-Sleep -Seconds 2
Save-Shot (Join-Path $OutDir '29-after-theme-change.png') $h
$pxAfter = Center-Pixel (Join-Path $OutDir '29-after-theme-change.png')
Add-Check 'clicking 深色 in the combo switches the theme live' ($clicked -and (Is-Dark $pxAfter)) "clicked=$clicked before=$pxBefore after=$pxAfter"
Add-Check 'choosing 深色 is persisted to settings.json' ((Read-Settings).Theme -eq 'Dark') "Theme=$((Read-Settings).Theme)"
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 4
Save-Shot (Join-Path $OutDir '30-restart-after-dark.png') $h
$pxRestart = Center-Pixel (Join-Path $OutDir '30-restart-after-dark.png')
Add-Check 'BUG-CONFIRMED: after choosing 深色 in the UI and restarting, the window is light again (settings.json still Theme=Dark)' ((Read-Settings).Theme -eq 'Dark' -and -not (Is-Dark $pxRestart)) "saved Theme=$((Read-Settings).Theme) pixel=$pxRestart"
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning

Write-Host ''
Write-Host "=== TEST 8B: SetThreadExecutionState observed through powercfg /requests  ($(Get-Date -Format o)) ==="
Write-Settings @{ KeepScreenAwake = $true; AutoBigScreenOnFocus = $false; AutoStartNext = $false; AlwaysOnTop = $false; HasWindowBounds = $false }
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 3
$idle = (powercfg /requests 2>&1 | Out-String)
Add-Check 'no display request while the timer is idle' ($idle -notmatch 'FluentPomodoro') ($idle.Trim() -replace "`r?`n", ' | ')
Send-Keys ' ' 2500
$running = (powercfg /requests 2>&1 | Out-String)
Write-Host "  powercfg /requests while running:"
$running -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { "    $_" }
Add-Check 'focus running holds a DISPLAY request (screen kept awake)' ($running -match 'FluentPomodoro') (($running -split "`r?`n" | Where-Object { $_ -match 'FluentPomodoro' }) -join ' | ')
Send-Keys ' ' 2500
$paused = (powercfg /requests 2>&1 | Out-String)
Add-Check 'pausing releases the display request (ES_CONTINUOUS reset)' ($paused -notmatch 'FluentPomodoro') (($paused -split "`r?`n" | Where-Object { $_ -match 'FluentPomodoro' }) -join ' | ')
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning
Write-Host ''
Get-VerifyResults | Format-Table -AutoSize
$failed = @(Get-VerifyResults | Where-Object { -not $_.Pass }).Count
Write-Host ("TEST8: {0} passed / {1}" -f (@(Get-VerifyResults).Count - $failed), @(Get-VerifyResults).Count)
exit 0
