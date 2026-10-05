# 00-smoke.ps1 -- task 1: launch the independently published single EXE, confirm 640x780 window + title
. (Join-Path $PSScriptRoot 'lib2.ps1')
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

Write-Host "EXE   : $script:Exe"
Write-Host "SHA256: $((Get-FileHash $script:Exe -Algorithm SHA256).Hash)"
Write-Host "SIZE  : $((Get-Item $script:Exe).Length) bytes"
Remove-Settings
Remove-Item (Join-Path $script:SettingsDir 'settings.json') -Force -ErrorAction SilentlyContinue

$r = Start-App
$p = $r.Proc; $h = $r.Hwnd
Start-Sleep -Seconds 8
Check 'process alive 10s after launch' (-not $p.HasExited) "HasExited=$($p.HasExited)"
Check 'owns a visible top-level window' ($h -ne [IntPtr]::Zero) "hwnd=$h"
if ($h -eq [IntPtr]::Zero) { Summary | Out-Null; exit 1 }

$rect = Get-Rect $h
Check 'window opens at 640x780' ($rect.W -eq 640 -and $rect.H -eq 780) "$($rect.W)x$($rect.H) @ ($($rect.X),$($rect.Y))"
$title = Get-Title $h
Check 'title is 25:00 / 专注 / 微软风格番茄钟' ($title -match '^25:00 · 专注 · 微软风格番茄钟$') "title='$title'"
$vd = Get-VirtualDesktop
Write-Host "virtual desktop = $($vd.W)x$($vd.H) @ ($($vd.X),$($vd.Y))  monitor count=$([R2.Native]::GetSystemMetrics(80))"
$prof = Get-WindowColorProfile -Hwnd $h
Write-Host "window colour profile: modal=$($prof.Modal) ($($prof.ModalCount)/$($prof.Total)) distinct=$($prof.Distinct) avgR=$($prof.AvgR)"
$shot = Save-Shot -Name 'r2-01-launch-640x780.png' -Hwnd $h
Write-Host "screenshot: $shot"

# also verify the exe is genuinely single-file self-contained
$files = @(Get-ChildItem (Split-Path $script:Exe))
Check 'output dir contains exactly one file' ($files.Count -eq 1) ("$($files.Count) files: " + (($files | Select-Object -ExpandProperty Name) -join ','))

Summary | Out-Null
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
