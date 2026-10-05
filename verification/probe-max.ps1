# Probe: does SC_MAXIMIZE inside big screen leave the window stuck maximized after Esc?
param(
    [string]$Exe = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verify-dist\FluentPomodoro.exe',
    [string]$OutDir = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verification'
)
. (Join-Path $OutDir 'lib.ps1')
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function State([IntPtr]$h) {
    $vis = '?'
    try {
        $el = [System.Windows.Automation.AutomationElement]::FromHandle($h)
        $vis = ($el.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)).Current.WindowVisualState.ToString()
    } catch { $vis = "err:$($_.Exception.Message)" }
    return ("rect={0} IsZoomed={1} IsIconic={2} UIA.WindowVisualState={3}" -f (Format-Rect $h), [VU]::IsZoomed($h), [VU]::IsIconic($h), $vis)
}
function Post-Key([IntPtr]$h, [int]$vk) {
    [void][VU]::PostMessage($h, 0x0100, [IntPtr]$vk, [IntPtr](0x00000001 -bor ($vk -shl 16)))
    Start-Sleep -Milliseconds 60
    [void][VU]::PostMessage($h, 0x0101, [IntPtr]$vk, [IntPtr](0xC0000001 -bor ($vk -shl 16)))
}

Assert-NoAppRunning
Write-Settings @{ AutoBigScreenOnFocus = $false; BigScreen = 'Mega'; AlwaysOnTop = $false; HasWindowBounds = $false }
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 3
Write-Host "windowed:        $(State $h)"
Send-Keys '{F11}' 1500
Write-Host "after F11:       $(State $h)"
[void][VU]::SendMessage($h, 0x0112, [IntPtr]0xF030, [IntPtr]::Zero)   # SC_MAXIMIZE
Start-Sleep -Milliseconds 1200
Write-Host "after SC_MAXIMIZE: $(State $h)"
Post-Key $h 0x1B                                                      # VK_ESCAPE
Start-Sleep -Milliseconds 1600
Write-Host "after Esc:       $(State $h)"
Save-Screen (Join-Path $OutDir 'probe-max-after-esc.png')

Write-Host "--- recovery attempts ---"
[void][VU]::ShowWindow($h, 9)   # SW_RESTORE
Start-Sleep -Milliseconds 1200
Write-Host "after SW_RESTORE: $(State $h)"
[void][VU]::PostMessage($h, 0x0112, [IntPtr]0xF120, [IntPtr]::Zero)  # SC_RESTORE
Start-Sleep -Milliseconds 800
Write-Host "after SC_RESTORE: $(State $h)"
# and now a second Esc (should be a no-op if already out of big screen)
Post-Key $h 0x1B
Start-Sleep -Milliseconds 900
Write-Host "after 2nd Esc:   $(State $h)"

Write-Host "--- same thing without SC_MAXIMIZE, for comparison ---"
$proc2 = $null
Send-Keys '^+q' 1200
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 3
Send-Keys '{F11}' 1500
Write-Host "F11 only:        $(State $h)"
Post-Key $h 0x1B
Start-Sleep -Milliseconds 1600
Write-Host "after Esc:       $(State $h)"
Send-Keys '^+q' 1200
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning
