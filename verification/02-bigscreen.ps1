# Independent behavior test 2: forced big screen (F11 / chips), WM_WINDOWPOSCHANGING enforcement,
# minimize blocking, Esc restore, and close-while-fullscreen bound restoration.
param(
    [string]$Exe = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verify-dist\FluentPomodoro.exe',
    [string]$OutDir = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verification'
)
. (Join-Path $OutDir 'lib.ps1')

Write-Host "=== TEST 2: forced big screen  ($(Get-Date -Format o)) ==="
Assert-NoAppRunning
Write-Settings @{ AutoBigScreenOnFocus = $false; BigScreen = 'Mega'; BigScreenTopmost = $true; AlwaysOnTop = $true; HasWindowBounds = $false }

$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
Write-Host "  virtual desktop: $($vs.Width)x$($vs.Height) @ ($($vs.Left),$($vs.Top)); monitors=$((Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction SilentlyContinue | Measure-Object).Count)"

$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
if ($h -eq [IntPtr]::Zero) { Add-Check 'window created' $false; Assert-NoAppRunning; exit 1 }
Start-Sleep -Seconds 3
$r0 = Get-Rect $h
Add-Check 'starts windowed 640x780 (AutoBigScreenOnFocus=false)' ((($r0.R - $r0.L) -eq 640) -and (($r0.B - $r0.T) -eq 780)) (Format-Rect $h)

# ---------- F11 ----------
Send-Keys '{F11}' 1500
$r1 = Get-Rect $h
$fullByRect = (($r1.R - $r1.L) -ge $vs.Width) -and (($r1.B - $r1.T) -ge $vs.Height) -and ($r1.L -le $vs.Left) -and ($r1.T -le $vs.Top)
Add-Check 'F11 makes window cover the whole virtual desktop' $fullByRect ("rect=$(Format-Rect $h) vs virtual $($vs.Width)x$($vs.Height)")
Add-Check 'big screen window is topmost (WS_EX_TOPMOST)' (Test-Topmost $h) "exstyle=0x$('{0:X}' -f (Get-ExStyle $h))"
Write-Host "  WS_EX_TOOLWINDOW (ShowInTaskbar=false): $(Test-ToolWindow $h)"
Save-Screen (Join-Path $OutDir '05-mega-fullscreen.png')

# ---------- external resize/move attack ----------
$s1 = Format-Rect $h
$before = Get-Rect $h
[void][VU]::SetWindowPos($h, [IntPtr]::Zero, 100, 100, 800, 600, 0x0004 -bor 0x0010)   # SWP_NOZORDER|SWP_NOACTIVATE
Start-Sleep -Milliseconds 900
$after = Get-Rect $h
$s2 = Format-Rect $h
Add-Check 'WM_WINDOWPOSCHANGING blocks external move/resize' ((($after.L -eq $before.L) -and ($after.T -eq $before.T) -and (($after.R - $after.L) -eq ($before.R - $before.L)))) "requested 800x600 @ (100,100); before=$s1 after=$s2"

# ---------- minimize blocking (WM_SYSCOMMAND) ----------
[void][VU]::SendMessage($h, 0x0112, [IntPtr]0xF020, [IntPtr]::Zero)
Start-Sleep -Milliseconds 900
Add-Check 'WM_SYSCOMMAND SC_MINIMIZE blocked in big screen' (-not [VU]::IsIconic($h)) "IsIconic=$([VU]::IsIconic($h))"
$r2 = Get-Rect $h
Add-Check 'still fullscreen after minimize attempt' ((($r2.R - $r2.L) -ge $vs.Width) -and (($r2.B - $r2.T) -ge $vs.Height)) (Format-Rect $h)

# ---------- minimize blocking (ShowWindow, bypasses WM_SYSCOMMAND) ----------
[void][VU]::ShowWindow($h, 6)   # SW_MINIMIZE
Start-Sleep -Milliseconds 1200
Add-Check 'ShowWindow(SW_MINIMIZE) also ends up non-minimized' (-not [VU]::IsIconic($h)) "IsIconic=$([VU]::IsIconic($h))"
$r3 = Get-Rect $h
Add-Check 'restored to fullscreen after ShowWindow minimize' ((($r3.R - $r3.L) -ge $vs.Width) -and (($r3.B - $r3.T) -ge $vs.Height)) (Format-Rect $h)
Save-Screen (Join-Path $OutDir '06-mega-after-minimize-attempt.png')

# ---------- Esc ----------
Send-Keys '{ESC}' 1600
$r4 = Get-Rect $h
Add-Check 'Esc restores exactly 640x780' ((($r4.R - $r4.L) -eq 640) -and (($r4.B - $r4.T) -eq 780)) (Format-Rect $h)

# ---------- chip click: 全屏 ----------
$L = $r4.L; $T = $r4.T
Click-At ($L + 96) ($T + 743)
Start-Sleep -Milliseconds 900
$r5 = Get-Rect $h
Add-Check 'clicking the 全屏 chip enters fullscreen' ((($r5.R - $r5.L) -ge $vs.Width) -and (($r5.B - $r5.T) -ge $vs.Height)) (Format-Rect $h)
Save-Screen (Join-Path $OutDir '07-chip-full.png')
Send-Keys '{ESC}' 1600
$r6 = Get-Rect $h
Add-Check 'Esc restores 640x780 after 全屏 chip' ((($r6.R - $r6.L) -eq 640) -and (($r6.B - $r6.T) -eq 780)) (Format-Rect $h)

# ---------- chip click: 巨幕跨屏 ----------
$L = $r6.L; $T = $r6.T
Click-At ($L + 150) ($T + 743)
Start-Sleep -Milliseconds 900
$r7 = Get-Rect $h
Add-Check 'clicking the 巨幕跨屏 chip enters fullscreen' ((($r7.R - $r7.L) -ge $vs.Width) -and (($r7.B - $r7.T) -ge $vs.Height)) (Format-Rect $h)
Save-Screen (Join-Path $OutDir '08-chip-mega.png')
Save-Crop (Join-Path $OutDir '09-chip-state.png') $h 0 ($r7.B - $r7.T - 70) 400 70

# ---------- close while still in big screen ----------
Send-Keys '^+q' 1500
$deadline = (Get-Date).AddSeconds(12)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 400 }
Add-Check 'force quit works from big screen' $proc.HasExited "HasExited=$($proc.HasExited)"
$j = Read-Settings
if ($j) {
    Add-Check 'fullscreen size not persisted as windowed bounds' (($j.WindowWidth -eq 640) -and ($j.WindowHeight -eq 780)) "WindowWidth=$($j.WindowWidth) WindowHeight=$($j.WindowHeight) HasWindowBounds=$($j.HasWindowBounds)"
}
Assert-NoAppRunning

# ---------- relaunch: must not come back fullscreen ----------
$proc2 = Start-Process -FilePath $Exe -PassThru
$h2 = Wait-AppWindow 20
Start-Sleep -Seconds 3
$r8 = Get-Rect $h2
Add-Check 'relaunch after fullscreen-close returns to 640x780 window' ((($h2 -ne [IntPtr]::Zero)) -and (($r8.R - $r8.L) -eq 640) -and (($r8.B - $r8.T) -eq 780)) (Format-Rect $h2)
Add-Check 'relaunch window is not fullscreen-sized' (-not ((($r8.R - $r8.L) -ge $vs.Width) -or (($r8.B - $r8.T) -ge $vs.Height))) (Format-Rect $h2)
Save-Shot (Join-Path $OutDir '10-relaunch-windowed.png') $h2
Send-Keys '^+q' 1500
Start-Sleep -Seconds 1
Assert-NoAppRunning

Write-Host ''
Get-VerifyResults | Format-Table -AutoSize
$failed = @(Get-VerifyResults | Where-Object { -not $_.Pass }).Count
Write-Host ("TEST2: {0} passed / {1}" -f (@(Get-VerifyResults).Count - $failed), @(Get-VerifyResults).Count)
exit $failed
