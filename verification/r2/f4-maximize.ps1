# f4-maximize.ps1 -- F4: Esc from big screen after a maximize attempt must return to 640x780, not stay maximized
. (Join-Path $PSScriptRoot 'lib2.ps1')
$today = (Get-Date).ToString('yyyy-MM-dd')
$vd = Get-VirtualDesktop
$WM_SYSCOMMAND = 0x0112; $SC_MAXIMIZE = 0xF030; $SC_RESTORE = 0xF120; $SW_MAXIMIZE = 3; $SW_RESTORE = 9

Write-Settings (@{
  FocusMinutes = 25; ShortBreakMinutes = 5; LongBreakMinutes = 15; LongBreakInterval = 4
  AutoStartNext = $false; SoundEnabled = $false; KeepScreenAwake = $false; AlwaysOnTop = $false
  NotifyOnPhaseEnd = $false; FocusLock = $false; AutoBigScreenOnFocus = $false
  Theme = 'Light'; UseMicaBackdrop = $false
  BigScreen = 'Mega'; BigScreenTopmost = $true
  HasWindowBounds = $false; WindowLeft = 0; WindowTop = 0; WindowWidth = 640; WindowHeight = 780
  StatsDate = $today; CompletedToday = 0; FocusMinutesToday = 0; TotalCompleted = 0; StreakDays = 0
  LastCompletedDate = ''
} | ConvertTo-Json)

$r = Start-App
$h = $r.Hwnd; Start-Sleep -Seconds 7
$w0 = Get-Rect $h
Check 'starts windowed 640x780' ($w0.W -eq 640 -and $w0.H -eq 780) "$($w0.W)x$($w0.H) @ ($($w0.X),$($w0.Y)) IsZoomed=$([R2.Native]::IsZoomed($h))"

# --- path 1: F11 into big screen, then WM_SYSCOMMAND SC_MAXIMIZE ---
Send-VKey -Vk 0x7A   # F11
Start-Sleep -Milliseconds 1200
$b1 = Get-Rect $h
Check 'F11 enters big screen' ($b1.W -ge $vd.W -and $b1.H -ge $vd.H) "$($b1.W)x$($b1.H) @ ($($b1.X),$($b1.Y)) IsZoomed=$([R2.Native]::IsZoomed($h))"

[void][R2.Native]::PostMessageW($h, $WM_SYSCOMMAND, [IntPtr]$SC_MAXIMIZE, [IntPtr]0)
Start-Sleep -Milliseconds 1200
$b2 = Get-Rect $h
$z2 = [R2.Native]::IsZoomed($h)
Write-Host "after SC_MAXIMIZE: $($b2.W)x$($b2.H) @ ($($b2.X),$($b2.Y)) IsZoomed=$z2"
Check 'SC_MAXIMIZE does not leave the big-screen window maximized' (-not $z2) "IsZoomed=$z2 rect=$($b2.W)x$($b2.H)"
Check 'SC_MAXIMIZE does not change the big-screen rect' ($b2.W -eq $b1.W -and $b2.H -eq $b1.H) "before=$($b1.W)x$($b1.H) after=$($b2.W)x$($b2.H)"
Save-Shot -Name 'r2-f4-after-sc-maximize.png' -Hwnd $h | Out-Null

Send-Esc
Start-Sleep -Milliseconds 1000
$e1 = Get-Rect $h; $z3 = [R2.Native]::IsZoomed($h)
Check 'Esc after SC_MAXIMIZE returns exactly 640x780' ($e1.W -eq 640 -and $e1.H -eq 780) "$($e1.W)x$($e1.H) @ ($($e1.X),$($e1.Y))"
Check 'Esc after SC_MAXIMIZE leaves IsZoomed false' (-not $z3) "IsZoomed=$z3"
Save-Shot -Name 'r2-f4-after-esc.png' -Hwnd $h | Out-Null

# --- path 2: bypass WndProc entirely with ShowWindow(SW_MAXIMIZE) ---
Send-VKey -Vk 0x7A
Start-Sleep -Milliseconds 1200
$b3 = Get-Rect $h
[void][R2.Native]::ShowWindow($h, $SW_MAXIMIZE)
Start-Sleep -Milliseconds 1200
$b4 = Get-Rect $h; $z4 = [R2.Native]::IsZoomed($h)
Write-Host "after ShowWindow(SW_MAXIMIZE): $($b4.W)x$($b4.H) @ ($($b4.X),$($b4.Y)) IsZoomed=$z4"
Send-Esc
Start-Sleep -Milliseconds 1200
$e2 = Get-Rect $h; $z5 = [R2.Native]::IsZoomed($h)
Write-Host "after Esc: $($e2.W)x$($e2.H) @ ($($e2.X),$($e2.Y)) IsZoomed=$z5"
Check 'Esc after ShowWindow(SW_MAXIMIZE) returns to 640x780 (WindowState resync)' ($e2.W -eq 640 -and $e2.H -eq 780) "$($e2.W)x$($e2.H) @ ($($e2.X),$($e2.Y))"
Check 'Esc after ShowWindow(SW_MAXIMIZE) leaves IsZoomed false' (-not $z5) "IsZoomed=$z5"
if ($z5 -or $e2.W -ne 640) {
  Write-Host "  -> recovering with SW_RESTORE"
  [void][R2.Native]::ShowWindow($h, $SW_RESTORE); Start-Sleep -Milliseconds 600
}

# --- path 3: maximize while windowed (not big screen), then check normal state intact ---
$w2 = Get-Rect $h
Check 'window back to 640x780 at the end' ($w2.W -eq 640 -and $w2.H -eq 780) "$($w2.W)x$($w2.H) @ ($($w2.X),$($w2.Y)) IsZoomed=$([R2.Native]::IsZoomed($h))"

Summary | Out-Null
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
