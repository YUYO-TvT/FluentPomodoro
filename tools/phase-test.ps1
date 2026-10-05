# 阶段完成 / 统计落盘 / 提示音 验收测试（使用 1 分钟专注时长加速验证）
# 用法: pwsh -NoProfile -File tools\phase-test.ps1
param(
    [string]$Exe = (Join-Path $PSScriptRoot '..\bin\Release\net8.0-windows\win-x64\FluentPomodoro.exe'),
    [string]$Artifacts = (Join-Path $PSScriptRoot '..\artifacts')
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class P {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
  public struct RECT { public int L,T,R,B; }
}
"@

$script:results = @()
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    $script:results += [pscustomobject]@{ 检查项 = $name; 结果 = $(if ($ok) { '通过' } else { '未通过' }); 说明 = $detail }
    Write-Host ("[{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $detail)
}
function Get-AppWindow {
    $p = Get-Process -Name FluentPomodoro -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { return [IntPtr]::Zero }
    return [P]::GetAncestor($p.MainWindowHandle, 2)
}
function Get-Title([IntPtr]$h) {
    $sb = New-Object System.Text.StringBuilder 512
    [P]::GetWindowTextW($h, $sb, 512) | Out-Null
    return $sb.ToString()
}
function Save-WindowShot([string]$name) {
    $h = Get-AppWindow
    if ($h -eq [IntPtr]::Zero) { return }
    $r = New-Object P+RECT; [P]::GetWindowRect($h, [ref]$r) | Out-Null
    $bmp = [System.Drawing.Bitmap]::new(($r.R-$r.L), ($r.B-$r.T))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $g.Dispose()
    $bmp.Save((Join-Path $Artifacts $name), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
function Click-At([int]$x, [int]$y) {
    [P]::SetCursorPos($x, $y) | Out-Null; Start-Sleep -Milliseconds 180
    [P]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [P]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 500
}
function Send-Keys([string]$keys) {
    [P]::SetForegroundWindow((Get-AppWindow)) | Out-Null; Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait($keys); Start-Sleep -Milliseconds 500
}

if (-not (Test-Path $Artifacts)) { New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null }

# ---------- 准备：1 分钟专注、不自动进入大屏、不自动开始下一阶段 ----------
$settingsPath = Join-Path $env:APPDATA 'FluentPomodoro\settings.json'
$dir = Split-Path -Parent $settingsPath
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
@'
{
  "FocusMinutes": 1,
  "ShortBreakMinutes": 5,
  "LongBreakMinutes": 15,
  "LongBreakInterval": 4,
  "AutoStartNext": false,
  "SoundEnabled": true,
  "KeepScreenAwake": true,
  "AlwaysOnTop": true,
  "NotifyOnPhaseEnd": true,
  "FocusLock": false,
  "AutoBigScreenOnFocus": false,
  "Theme": "System",
  "UseMicaBackdrop": true,
  "BigScreen": "Full",
  "BigScreenTopmost": true,
  "HasWindowBounds": false,
  "WindowLeft": 0,
  "WindowTop": 0,
  "WindowWidth": 640,
  "WindowHeight": 780,
  "StatsDate": "",
  "CompletedToday": 0,
  "FocusMinutesToday": 0,
  "TotalCompleted": 0,
  "StreakDays": 0,
  "LastCompletedDate": ""
}
'@ | Set-Content -Path $settingsPath -Encoding UTF8

Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
Start-Process -FilePath $Exe -ArgumentList '--start','--light'
Start-Sleep -Seconds 5

$h = Get-AppWindow
Check '程序以 --start --light 启动' ($h -ne [IntPtr]::Zero) "hwnd=$h"
$title0 = Get-Title $h
Check '读取到 1 分钟专注配置且已自动开始' ($title0 -match '00:5' -and $title0 -match '专注') $title0
Save-WindowShot 'phase-01-running.png'

# ---------- 等待阶段完成，抓取提示浮层 ----------
Write-Host '等待专注阶段结束（约 60 秒）…'
Start-Sleep -Seconds 52
Save-WindowShot 'phase-02-before-end.png'
Start-Sleep -Seconds 5
$t = Get-Title $h
Write-Host "阶段结束前标题: $t"
Start-Sleep -Seconds 2
Save-WindowShot 'phase-03-toast.png'
$titleAfter = Get-Title $h
Check '专注结束后自动切换到短休息' ($titleAfter -match '短休息') $titleAfter
Save-WindowShot 'phase-04-break.png'

# ---------- 统计落盘 ----------
$json = Get-Content $settingsPath -Raw | ConvertFrom-Json
Check '今日完成番茄数 +1' ($json.CompletedToday -eq 1) "CompletedToday=$($json.CompletedToday)"
Check '今日专注分钟数 +1' ($json.FocusMinutesToday -eq 1) "FocusMinutesToday=$($json.FocusMinutesToday)"
Check '累计完成番茄数 +1' ($json.TotalCompleted -eq 1) "TotalCompleted=$($json.TotalCompleted)"
Check '连续专注天数 = 1' ($json.StreakDays -eq 1) "StreakDays=$($json.StreakDays)"

# 窗口内统计文案（截图人工确认）
Check '窗口标题显示休息倒计时' ($titleAfter -match '05:00|04:5') $titleAfter

# ---------- 试听提示音 ----------
Send-Keys '^,'
Start-Sleep -Milliseconds 900
$r = New-Object P+RECT; [P]::GetWindowRect($h, [ref]$r) | Out-Null
Click-At ($r.L + 262) ($r.T + 452)   # “试听提示音”按钮
Start-Sleep -Milliseconds 900
Save-WindowShot 'phase-05-sound-preview.png'

Send-Keys '^+q'
Start-Sleep -Seconds 3
Check '测试结束进程已退出' (-not [bool](Get-Process FluentPomodoro -ErrorAction SilentlyContinue))

Write-Host ''
$script:results | Format-Table -AutoSize
$failed = @($script:results | Where-Object { $_.结果 -ne '通过' }).Count
Write-Host ("通过 {0} / {1} 项" -f ($script:results.Count - $failed), $script:results.Count)
exit $failed
