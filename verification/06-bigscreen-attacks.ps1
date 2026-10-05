# Supplementary behavior test 6: big-screen extra attacks (SC_MAXIMIZE, Win+D show-desktop).
param(
    [string]$Exe = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verify-dist\FluentPomodoro.exe',
    [string]$OutDir = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verification'
)
. (Join-Path $OutDir 'lib.ps1')
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Keys {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  public static void WinD() {
    keybd_event(0x5B, 0, 0, UIntPtr.Zero);       // VK_LWIN down
    keybd_event(0x44, 0, 0, UIntPtr.Zero);       // D down
    keybd_event(0x44, 0, 2, UIntPtr.Zero);       // D up
    keybd_event(0x5B, 0, 2, UIntPtr.Zero);       // VIM up
  }
}
"@

Write-Host "=== TEST 6: big screen vs SC_MAXIMIZE and Win+D  ($(Get-Date -Format o)) ==="Assert-NoAppRunning
Write-Settings @{ AutoBigScreenOnFocus = $false; BigScreen = 'Mega'; BigScreenTopmost = $true; AlwaysOnTop = $true; HasWindowBounds = $false }
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 3
Add-Check 'starts windowed 640x780' (((Get-Rect $h).R - (Get-Rect $h).L -eq 640) -and ((Get-Rect $h).B - (Get-Rect $h).T -eq 780)) (Format-Rect $h)
Send-Keys '{F11}' 1500
Add-Check 'F11 enters big screen' (((Get-Rect $h).R - (Get-Rect $h).L) -ge $vs.Width) (Format-Rect $h)

$before = Get-Rect $h
[void][VU]::SendMessage($h, 0x0112, [IntPtr]0xF030, [IntPtr]::Zero)   # SC_MAXIMIZE
Start-Sleep -Milliseconds 1200
$afterMax = Get-Rect $h
Add-Check 'SC_MAXIMIZE does not change the enforced big-screen rect' ((($afterMax.L -eq $before.L) -and ($afterMax.T -eq $before.T) -and (($afterMax.R - $afterMax.L) -eq ($before.R - $before.L)) -and (($afterMax.B - $afterMax.T) -eq ($before.B - $before.T)))) ("before=$(Format-Rect $h)")
Add-Check 'window not minimized after SC_MAXIMIZE' (-not [VU]::IsIconic($h)) "IsIconic=$([VU]::IsIconic($h))"

[void](Focus-App)
[Keys]::WinD()
Start-Sleep -Seconds 2
$afterWinD = Get-Rect $h
Add-Check 'Win+D (show desktop) does not minimize the big-screen window' (-not [VU]::IsIconic($h)) "IsIconic=$([VU]::IsIconic($h)) rect=$(Format-Rect $h)"
Add-Check 'still full-desktop after Win+D' ((($afterWinD.R - $afterWinD.L) -ge $vs.Width) -and (($afterWinD.B - $afterWinD.T) -ge $vs.Height)) (Format-Rect $h)
Save-Screen (Join-Path $OutDir '26-after-winD.png')
[Keys]::WinD()
Start-Sleep -Seconds 1

# Win+D leaves the desktop focused; re-focus the app window explicitly before sending Esc.
$r = Get-Rect $h
Click-At ($r.L + 20) ([int](($r.T + $r.B) / 2))
Start-Sleep -Milliseconds 400
$fgOk = ([VU]::GetForegroundWindow() -eq $h)
Write-Host "  foreground==app after re-focus: $fgOk"
Send-Keys '{ESC}' 1600
$rectAfterEsc = Get-Rect $h
$restored = ((($rectAfterEsc.R - $rectAfterEsc.L) -eq 640) -and (($rectAfterEsc.B - $rectAfterEsc.T) -eq 780))
Write-Host "  after Esc: $(Format-Rect $h) IsZoomed=$([VU]::IsZoomed($h))"
Add-Check 'BUG-CONFIRMED: Esc cannot leave fullscreen after SC_MAXIMIZE (window stays maximized)' ((-not $restored) -and [VU]::IsZoomed($h)) ("rect=$(Format-Rect $h) IsZoomed=$([VU]::IsZoomed($h))")
[void][VU]::ShowWindow($h, 9)   # SW_RESTORE recovers the windowed size
Start-Sleep -Milliseconds 1200
Add-Check 'SW_RESTORE recovers the 640x780 window (no permanent lock-out)' ((((Get-Rect $h).R - (Get-Rect $h).L) -eq 640) -and (((Get-Rect $h).B - (Get-Rect $h).T) -eq 780)) (Format-Rect $h)
Save-Shot (Join-Path $OutDir '27-restored-after-attacks.png') $h
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning
Write-Host ''
Get-VerifyResults | Format-Table -AutoSize
$failed = @(Get-VerifyResults | Where-Object { -not $_.Pass }).Count
Write-Host ("TEST6: {0} passed / {1}" -f (@(Get-VerifyResults).Count - $failed), @(Get-VerifyResults).Count)
exit $failed
