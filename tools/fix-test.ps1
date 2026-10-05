# 针对独立验收发现的问题（F1–F7）的回归测试
# 用法: pwsh -NoProfile -File tools\fix-test.ps1
param(
    [string]$Exe = (Join-Path $PSScriptRoot '..\bin\Release\net8.0-windows\win-x64\FluentPomodoro.exe'),
    [string]$Artifacts = (Join-Path $PSScriptRoot '..\artifacts')
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices; using System.Text;
public class Fx {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  public struct RECT { public int L,T,R,B; }
}
"@

$script:results = @()
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    $script:results += [pscustomobject]@{ 检查项 = $name; 结果 = $(if ($ok) { '通过' } else { '未通过' }); 说明 = $detail }
    Write-Host ("[{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $detail)
}
$script:bestHwnd = [IntPtr]::Zero
$script:bestArea = -1
function Get-AppWindow {
    $procs = @(Get-Process -Name FluentPomodoro -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return [IntPtr]::Zero }
    $script:bestHwnd = [IntPtr]::Zero
    $script:bestArea = -1
    foreach ($p in $procs) {
        $procId = $p.Id
        $cb = [Fx+EnumProc]{
            param($w, $l)
            $owner = 0
            [Fx]::GetWindowThreadProcessId($w, [ref]$owner) | Out-Null
            if ($owner -eq $procId -and [Fx]::IsWindowVisible($w)) {
                $rr = New-Object Fx+RECT
                [Fx]::GetWindowRect($w, [ref]$rr) | Out-Null
                $area = [int64]($rr.R - $rr.L) * [int64]($rr.B - $rr.T)
                if ($area -gt $script:bestArea) { $script:bestArea = $area; $script:bestHwnd = $w }
            }
            return $true
        }
        [Fx]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
    }
    return $script:bestHwnd
}
function Get-Title([IntPtr]$h) {
    $sb = New-Object System.Text.StringBuilder 512
    [Fx]::GetWindowTextW($h, $sb, 512) | Out-Null
    return $sb.ToString()
}
function Get-Rect([IntPtr]$h) { $r = New-Object Fx+RECT; [Fx]::GetWindowRect($h, [ref]$r) | Out-Null; return $r }
function Save-WindowShot([string]$name) {
    $h = Get-AppWindow; if ($h -eq [IntPtr]::Zero) { return }
    $r = Get-Rect $h
    $bmp = [System.Drawing.Bitmap]::new(($r.R-$r.L), ($r.B-$r.T))
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $g.Dispose()
    $bmp.Save((Join-Path $Artifacts $name), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
function Send-Keys([string]$keys) {
    [Fx]::SetForegroundWindow((Get-AppWindow)) | Out-Null; Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait($keys); Start-Sleep -Milliseconds 500
}
function Click([int]$x, [int]$y) {
    [Fx]::SetCursorPos($x, $y) | Out-Null; Start-Sleep -Milliseconds 220
    [Fx]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80
    [Fx]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 500
}
function AverageBackground([IntPtr]$h) {
    $r = Get-Rect $h
    $bmp = [System.Drawing.Bitmap]::new(($r.R-$r.L), ($r.B-$r.T))
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $g.Dispose()
    $sum = 0; $n = 0
    foreach ($y in 200, 400, 600) { foreach ($x in 8, 16, 24) { $c = $bmp.GetPixel($x, $y); $sum += ($c.R + $c.G + $c.B) / 3; $n++ } }
    $bmp.Dispose()
    return [math]::Round($sum / $n, 1)
}
function Start-App([string[]]$arguments, [int]$wait = 6) {
    Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 600
    if ($arguments) { Start-Process -FilePath $Exe -ArgumentList $arguments }
    else { Start-Process -FilePath $Exe }
    Start-Sleep -Seconds $wait
}
function Stop-App {
    $h = Get-AppWindow
    if ($h -ne [IntPtr]::Zero) { Send-Keys '^+q' }
    Start-Sleep -Seconds 2
    Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500
}

$settingsPath = Join-Path $env:APPDATA 'FluentPomodoro\settings.json'
$settingsDir = Split-Path -Parent $settingsPath
if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null }
$today = (Get-Date).ToString('yyyy-MM-dd')
if (-not (Test-Path $Artifacts)) { New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null }

function Write-Settings([string]$json) { Set-Content -Path $settingsPath -Value $json -Encoding UTF8 }

# ============ F1：配置文件里的主题必须生效 ============
Write-Settings (@"
{
  "FocusMinutes": 25, "ShortBreakMinutes": 5, "LongBreakMinutes": 15, "LongBreakInterval": 4,
  "AutoStartNext": true, "SoundEnabled": true, "KeepScreenAwake": true, "AlwaysOnTop": true,
  "NotifyOnPhaseEnd": true, "FocusLock": false, "AutoBigScreenOnFocus": false,
  "Theme": "Dark", "UseMicaBackdrop": true, "BigScreen": "Full", "BigScreenTopmost": true,
  "HasWindowBounds": false, "WindowLeft": 0, "WindowTop": 0, "WindowWidth": 640, "WindowHeight": 780,
  "StatsDate": "$today", "CompletedToday": 0, "FocusMinutesToday": 0, "TotalCompleted": 0,
  "StreakDays": 0, "LastCompletedDate": ""
}
"@)
Start-App @() 6
$h = Get-AppWindow
$r = Get-Rect $h
$bmp = [System.Drawing.Bitmap]::new(($r.R-$r.L), ($r.B-$r.T))
$g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $g.Dispose()
$px = $bmp.GetPixel(40, 400)
$dark = ($px.R + $px.G + $px.B) / 3 -lt 80
$bmp.Save((Join-Path $Artifacts 'fix-01-saved-dark-theme.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Check 'F1 配置文件 Theme=Dark 启动即为深色' $dark "背景像素 R=$($px.R) G=$($px.G) B=$($px.B)"
Stop-App

# ============ F2：非法值不能丢掉整份配置与统计 ============
Write-Settings (@"
{
  "FocusMinutes": 30, "ShortBreakMinutes": 5, "LongBreakMinutes": 15, "LongBreakInterval": 4,
  "AutoStartNext": false, "SoundEnabled": true, "KeepScreenAwake": true, "AlwaysOnTop": true,
  "NotifyOnPhaseEnd": true, "FocusLock": false, "AutoBigScreenOnFocus": false,
  "Theme": "Bogus", "UseMicaBackdrop": true, "BigScreen": "Full", "BigScreenTopmost": true,
  "HasWindowBounds": true, "WindowLeft": 200, "WindowTop": 150, "WindowWidth": 600, "WindowHeight": 700,
  "StatsDate": "$today", "CompletedToday": 5, "FocusMinutesToday": 150, "TotalCompleted": 42,
  "StreakDays": 7, "LastCompletedDate": "$today"
}
"@)
Start-App @() 6
$title = Get-Title (Get-AppWindow)
Check 'F2-a 非法枚举不阻止启动且其余字段生效（专注 30 分钟）' ($title -match '30:00') $title
Stop-App
$json = Get-Content $settingsPath -Raw | ConvertFrom-Json
Check 'F2-b 统计在非法枚举下完整保留' (($json.CompletedToday -eq 5) -and ($json.TotalCompleted -eq 42) -and ($json.FocusMinutesToday -eq 150) -and ($json.StreakDays -eq 7)) "CompletedToday=$($json.CompletedToday) TotalCompleted=$($json.TotalCompleted) FocusMinutesToday=$($json.FocusMinutesToday) StreakDays=$($json.StreakDays)"
Check 'F2-c 非法枚举被修正为默认（System）' ($json.Theme -eq 'System') "Theme=$($json.Theme)"
Check 'F2-d 其余设置未被清空（FocusMinutes=30 / AutoStartNext=false / 窗口 600x700）' (($json.FocusMinutes -eq 30) -and (-not $json.AutoStartNext) -and ($json.WindowWidth -eq 600) -and ($json.WindowHeight -eq 700)) "FocusMinutes=$($json.FocusMinutes) WindowWidth=$($json.WindowWidth)"

# 类型错误
Write-Settings (@"
{ "FocusMinutes": "abc", "TotalCompleted": 9, "StatsDate": "$today", "CompletedToday": 2, "Theme": "Light", "ShortBreakMinutes": 5, "LongBreakMinutes": 15, "LongBreakInterval": 4 }
"@)
Start-App @() 6
$title = Get-Title (Get-AppWindow)
Stop-App
$json = Get-Content $settingsPath -Raw | ConvertFrom-Json
Check 'F2-e 类型错误时统计保留、坏字段回默认' (($json.TotalCompleted -eq 9) -and ($json.CompletedToday -eq 2) -and ($json.FocusMinutes -eq 25)) "TotalCompleted=$($json.TotalCompleted) CompletedToday=$($json.CompletedToday) FocusMinutes=$($json.FocusMinutes)"

# ============ F3：--mega 与 --start 可同时生效 ============
Remove-Item $settingsPath -Force -ErrorAction SilentlyContinue
Start-App @('--mega', '--start') 7
$h = Get-AppWindow
$r = Get-Rect $h
$title = Get-Title $h
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$megaOk = (($r.R - $r.L) -ge $vs.Width - 2) -and (($r.B - $r.T) -ge $vs.Height - 2)
$running = $title -match '24:|23:|22:|21:'
Check 'F3 --mega --start 同时生效（大屏 + 倒计时）' ($megaOk -and $running) "$($r.R-$r.L)x$($r.B-$r.T), 标题=$title"
# F4：大屏中最大化请求被拦截
[Fx]::SendMessage($h, 0x0112, [IntPtr]0xF030, [IntPtr]::Zero) | Out-Null
Start-Sleep -Milliseconds 800
$r2 = Get-Rect $h
Check 'F4-a 大屏中 SC_MAXIMIZE 被拦截（矩形与最大化状态不变）' ((-not [Fx]::IsZoomed($h)) -and (($r2.R - $r2.L) -ge $vs.Width - 2)) "IsZoomed=$([Fx]::IsZoomed($h)) 尺寸=$($r2.R-$r2.L)x$($r2.B-$r2.T)"
Save-WindowShot 'fix-02-mega-running.png'
Send-Keys '{ESC}'
Start-Sleep -Milliseconds 1200
$r3 = Get-Rect $h
Check 'F4-b Esc 退出大屏后回到 640x780 且未处于最大化' ((($r3.R - $r3.L) -eq 640) -and (($r3.B - $r3.T) -eq 780) -and (-not [Fx]::IsZoomed($h))) "$($r3.R-$r3.L)x$($r3.B-$r3.T) IsZoomed=$([Fx]::IsZoomed($h))"
Save-WindowShot 'fix-03-after-esc.png'
Stop-App

# ============ F6：--focus 仅本次会话，不写回配置 ============
Remove-Item $settingsPath -Force -ErrorAction SilentlyContinue
Start-App @('--focus', '7', '--light') 6
$title = Get-Title (Get-AppWindow)
Check 'F6-a --focus 7 生效' ($title -match '07:00') $title
Stop-App
$json = Get-Content $settingsPath -Raw | ConvertFrom-Json
Check 'F6-b --focus 不写回配置文件（仍为 25）' ($json.FocusMinutes -eq 25) "FocusMinutes=$($json.FocusMinutes)"

# ============ 计时精度（20 秒）============
Start-App @('--light') 6
$h = Get-AppWindow
$t1 = Get-Title $h
Send-Keys ' '
Start-Sleep -Seconds 21
$t2 = Get-Title $h
Send-Keys ' '
Stop-App
$s1 = [int]($t1 -replace '^(\d+):(\d+).*', '$1') * 60 + [int]($t1 -replace '^(\d+):(\d+).*', '$2')
$s2 = [int]($t2 -replace '^(\d+):(\d+).*', '$1') * 60 + [int]($t2 -replace '^(\d+):(\d+).*', '$2')
$delta = $s1 - $s2
Check '计时精度：21 秒实际流逝对应标题递减 20–22 秒' ($delta -ge 20 -and $delta -le 22) "$t1 -> $t2 (递减 ${delta}s)"

# ============ 设置面板中的主题下拉（真实鼠标路径）============
Remove-Item $settingsPath -Force -ErrorAction SilentlyContinue
Start-App @('--light') 6
$h = Get-AppWindow
Send-Keys '^,'
Start-Sleep -Milliseconds 900
$r = Get-Rect $h
# 面板内容滚到底部附近，露出“外观”区块
[Fx]::SetCursorPos([int]($r.L + 420), [int]($r.T + 400)) | Out-Null
for ($i = 0; $i -lt 6; $i++) { [Fx]::mouse_event(0x0800, 0, 0, [uint32]::MaxValue - 119, [UIntPtr]::Zero); Start-Sleep -Milliseconds 120 }
Start-Sleep -Milliseconds 600
Save-WindowShot 'fix-04-settings-scrolled.png'
Write-Host '已保存设置面板滚动后的截图，用于确定外观区块坐标。'
Stop-App

# ============ N1：命令行 --light/--dark 不应被写回配置 ============
Write-Settings (@"
{
  "FocusMinutes": 25, "ShortBreakMinutes": 5, "LongBreakMinutes": 15, "LongBreakInterval": 4,
  "AutoStartNext": true, "SoundEnabled": true, "KeepScreenAwake": true, "AlwaysOnTop": true,
  "NotifyOnPhaseEnd": true, "FocusLock": false, "AutoBigScreenOnFocus": false,
  "Theme": "Dark", "UseMicaBackdrop": true, "BigScreen": "Full", "BigScreenTopmost": true,
  "HasWindowBounds": false, "WindowLeft": 0, "WindowTop": 0, "WindowWidth": 640, "WindowHeight": 780,
  "StatsDate": "$today", "CompletedToday": 0, "FocusMinutesToday": 0, "TotalCompleted": 0,
  "StreakDays": 0, "LastCompletedDate": ""
}
"@)
Start-App @('--light') 6
$lightness = AverageBackground (Get-AppWindow)
Check 'N1-a --light 覆盖生效（界面为浅色）' ($lightness -gt 180) "背景亮度=$lightness"
Stop-App
$json = Get-Content $settingsPath -Raw | ConvertFrom-Json
Check 'N1-b --light 不被写回配置（配置文件仍为 Dark）' ($json.Theme -eq 'Dark') "Theme=$($json.Theme)"

# ============ N2：--focus 激活时，用户在设置面板里改时长应当持久化 ============
Write-Settings (@"
{
  "FocusMinutes": 33, "ShortBreakMinutes": 5, "LongBreakMinutes": 15, "LongBreakInterval": 4,
  "AutoStartNext": true, "SoundEnabled": true, "KeepScreenAwake": true, "AlwaysOnTop": true,
  "NotifyOnPhaseEnd": true, "FocusLock": false, "AutoBigScreenOnFocus": false,
  "Theme": "Light", "UseMicaBackdrop": true, "BigScreen": "Full", "BigScreenTopmost": true,
  "HasWindowBounds": false, "WindowLeft": 0, "WindowTop": 0, "WindowWidth": 640, "WindowHeight": 780,
  "StatsDate": "$today", "CompletedToday": 0, "FocusMinutesToday": 0, "TotalCompleted": 0,
  "StreakDays": 0, "LastCompletedDate": ""
}
"@)
Start-App @('--focus', '7') 6
$h = Get-AppWindow
$t = Get-Title $h
Check 'N2-a --focus 7 生效' ($t -match '07:00') $t
$r = Get-Rect $h
Click ($r.L + 320) ($r.T + 500)      # 主界面空白处，确保窗口在前台
Click ($r.L + 585) ($r.T + 736)      # 打开设置
Start-Sleep -Milliseconds 900
Click ($r.L + 400) ($r.T + 118)      # 把“专注时长”滑块点到约 55 分钟
Start-Sleep -Milliseconds 700
$t2 = Get-Title $h
Check 'N2-b 拖动滑块后本次会话即时生效' ($t2 -notmatch '07:00') "标题=$t2"
Stop-App
$json = Get-Content $settingsPath -Raw | ConvertFrom-Json
$persisted = [int]$json.FocusMinutes
Check 'N2-c 用户显式修改的时长被持久化（不再是 33 / 7）' (($persisted -ne 33) -and ($persisted -ne 7) -and ($persisted -ge 40) -and ($persisted -le 70)) "FocusMinutes=$persisted"

Write-Host ''
$script:results | Format-Table -AutoSize
$failed = @($script:results | Where-Object { $_.结果 -ne '通过' }).Count
Write-Host ("通过 {0} / {1} 项" -f ($script:results.Count - $failed), $script:results.Count)
exit $failed
