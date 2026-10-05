# Probe: read back the DWM attributes the app sets (backdrop type, corner preference, dark mode, caption colour).
param(
    [string]$Exe = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verify-dist\FluentPomodoro.exe',
    [string]$OutDir = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verification'
)
. (Join-Path $OutDir 'lib.ps1')
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Dwm {
  [DllImport("dwmapi.dll", PreserveSig=true)] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int size);
  [DllImport("dwmapi.dll", PreserveSig=true)] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT val, int size);
  public struct RECT { public int L,T,R,B; }
  public static string Get(IntPtr h, int attr, string name) {
    int v; int hr = DwmGetWindowAttribute(h, attr, out v, 4);
    return name + "=" + (hr == 0 ? v.ToString() : "hr=0x" + hr.ToString("X8"));
  }
  public static string Frame(IntPtr h) {
    RECT r; int hr = DwmGetWindowAttribute(h, 37, out r, Marshal.SizeOf(typeof(RECT))); // DWMWA_EXTENDED_FRAME_BOUNDS
    return hr == 0 ? ("frame=" + (r.R-r.L) + "x" + (r.B-r.T) + " @ " + r.L + "," + r.T) : ("frame hr=0x" + hr.ToString("X8"));
  }
}
"@
function Dump-Dwm([string]$tag, [IntPtr]$h) {
    Write-Host "  [$tag] $([Dwm]::Get($h,38,'SYSTEMBACKDROP_TYPE')) $([Dwm]::Get($h,33,'CORNER_PREFERENCE')) $([Dwm]::Get($h,20,'IMMERSIVE_DARK_MODE')) $([Dwm]::Get($h,35,'CAPTION_COLOR')) $([Dwm]::Frame($h))"
}

Write-Host "=== DWM attribute read-back  ($(Get-Date -Format o)) ==="
Write-Host "  (SYSTEMBACKDROP_TYPE: 0=Auto 1=None 2=Mica 3=Acrylic 4=MicaAlt | CORNER: 0=Default 1=DoNotRound 2=Round)"
Assert-NoAppRunning
Write-Settings @{ UseMicaBackdrop = $true; AutoBigScreenOnFocus = $false; AlwaysOnTop = $false; HasWindowBounds = $false; Theme = 'System'; BigScreen = 'Mega' }
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 4
Dump-Dwm 'Mica ON, windowed' $h
Send-Keys '{F11}' 1600
Dump-Dwm 'Mica ON, big screen' $h
Send-Keys '{ESC}' 1600
Dump-Dwm 'Mica ON, back to window' $h
Send-Keys '^+q' 1200
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning

Write-Settings @{ UseMicaBackdrop = $false; AutoBigScreenOnFocus = $false; AlwaysOnTop = $false; HasWindowBounds = $false; Theme = 'System' }
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 4
Dump-Dwm 'Mica OFF, windowed' $h
Send-Keys '^+q' 1200
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning

Write-Host "--- dark theme forced via CLI ---"
Write-Settings @{ UseMicaBackdrop = $false; AutoBigScreenOnFocus = $false; AlwaysOnTop = $false; HasWindowBounds = $false; Theme = 'System' }
$proc = Start-Process -FilePath $Exe -ArgumentList '--dark' -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 4
Dump-Dwm '--dark, windowed' $h
Send-Keys '^+q' 1200
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning
