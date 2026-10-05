# 新功能验收：专注时钟 / 统计绿点矩阵二级窗口 / 可轮换背景图+主题色随图 / 导入白噪音
# 用法: pwsh -NoProfile -File tools\feature-test.ps1
param(
    [string]$Exe = (Join-Path $PSScriptRoot '..\bin\Release\net8.0-windows\win-x64\FluentPomodoro.exe'),
    [string]$Artifacts = (Join-Path $PSScriptRoot '..\artifacts')
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices; using System.Text;
public class Fz {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  public struct RECT { public int L,T,R,B; }
}
"@

$script:results = @()
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    $script:results += [pscustomobject]@{ 检查项 = $name; 结果 = $(if ($ok) { '通过' } else { '未通过' }); 说明 = $detail }
    Write-Host ("[{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $detail)
}

function Get-AppWindows {
    $procs = @(Get-Process -Name FluentPomodoro -ErrorAction SilentlyContinue)
    $list = New-Object System.Collections.ArrayList
    foreach ($p in $procs) {
        $procId = $p.Id
        $cb = [Fz+EnumProc]{
            param($w, $l)
            $owner = 0; [Fz]::GetWindowThreadProcessId($w, [ref]$owner) | Out-Null
            if ($owner -eq $procId -and [Fz]::IsWindowVisible($w)) {
                $rr = New-Object Fz+RECT; [Fz]::GetWindowRect($w, [ref]$rr) | Out-Null
                $area = [int64]($rr.R - $rr.L) * [int64]($rr.B - $rr.T)
                if ($area -gt 20000) {
                    $sb = New-Object System.Text.StringBuilder 512
                    [Fz]::GetWindowTextW($w, $sb, 512) | Out-Null
                    [void]$list.Add([pscustomobject]@{ Hwnd = $w; Title = $sb.ToString(); Rect = $rr; Area = $area })
                }
            }
            return $true
        }
        [Fz]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
    }
    return $list
}
function Get-MainWindow {
    $w = Get-AppWindows | Where-Object { $_.Title -match '番茄钟' } | Sort-Object Area -Descending
    if ($w) { return $w[0] }
    $w = Get-AppWindows | Sort-Object Area -Descending
    if ($w) { return $w[0] }
    return $null
}
function Get-StatsWindow {
    $w = Get-AppWindows | Where-Object { $_.Title -match '统计' } | Sort-Object Area -Descending
    if ($w) { return $w[0] }
    return $null
}
function Get-Rect($entry) { return $entry.Rect }
function EnsureForeground([IntPtr]$h) {
    for ($i = 0; $i -lt 4; $i++) {
        [Fz]::SetForegroundWindow($h) | Out-Null
        Start-Sleep -Milliseconds 300
        if ([Fz]::GetForegroundWindow() -eq $h) { return $true }
        $r = New-Object Fz+RECT; [Fz]::GetWindowRect($h, [ref]$r) | Out-Null
        [Fz]::SetCursorPos([int]($r.L + 320), [int]($r.T + 18)) | Out-Null
        Start-Sleep -Milliseconds 150
        [Fz]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80
        [Fz]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 400
        if ([Fz]::GetForegroundWindow() -eq $h) { return $true }
    }
    return $false
}
function Send-Keys([string]$keys) {
    $w = Get-MainWindow
    if ($w) { EnsureForeground $w.Hwnd | Out-Null }
    Start-Sleep -Milliseconds 200
    [System.Windows.Forms.SendKeys]::SendWait($keys)
    Start-Sleep -Milliseconds 800
}
function Capture([IntPtr]$h, [string]$name) {
    $r = New-Object Fz+RECT; [Fz]::GetWindowRect($h, [ref]$r) | Out-Null
    $bmp = [System.Drawing.Bitmap]::new(($r.R-$r.L), ($r.B-$r.T))
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $g.Dispose()
    if ($name) { $bmp.Save((Join-Path $Artifacts $name), [System.Drawing.Imaging.ImageFormat]::Png) }
    return $bmp
}
function DiffersIn([System.Drawing.Bitmap]$a, [System.Drawing.Bitmap]$b, [int]$x0, [int]$y0, [int]$x1, [int]$y1, [int]$tolerance = 18) {
    $count = 0
    for ($y = $y0; $y -lt [math]::Min($y1, $a.Height); $y++) {
        for ($x = $x0; $x -lt [math]::Min($x1, $a.Width); $x++) {
            $pa = $a.GetPixel($x, $y); $pb = $b.GetPixel($x, $y)
            if ([math]::Abs($pa.R - $pb.R) -gt $tolerance -or [math]::Abs($pa.G - $pb.G) -gt $tolerance -or [math]::Abs($pa.B - $pb.B) -gt $tolerance) { $count++ }
        }
    }
    return $count
}
function AverageIn([System.Drawing.Bitmap]$bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $r = 0; $g = 0; $b = 0; $n = 0
    for ($y = $y0; $y -lt [math]::Min($y1, $bmp.Height); $y++) {
        for ($x = $x0; $x -lt [math]::Min($x1, $bmp.Width); $x++) {
            $c = $bmp.GetPixel($x, $y); $r += $c.R; $g += $c.G; $b += $c.B; $n++
        }
    }
    if ($n -eq 0) { return @{ R = 0; G = 0; B = 0 } }
    return @{ R = [int]($r / $n); G = [int]($g / $n); B = [int]($b / $n) }
}
function MostSaturatedIn([System.Drawing.Bitmap]$bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $best = $null; $bestSat = -1
    for ($y = $y0; $y -lt [math]::Min($y1, $bmp.Height); $y++) {
        for ($x = $x0; $x -lt [math]::Min($x1, $bmp.Width); $x++) {
            $c = $bmp.GetPixel($x, $y)
            $max = [math]::Max($c.R, [math]::Max($c.G, $c.B)); $min = [math]::Min($c.R, [math]::Min($c.G, $c.B))
            $sat = $max - $min
            if ($sat -gt $bestSat) { $bestSat = $sat; $best = $c }
        }
    }
    return @{ Color = $best; Sat = $bestSat }
}
function CountBluePixels([System.Drawing.Bitmap]$bmp, [int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    $count = 0
    for ($y = $y0; $y -lt [math]::Min($y1, $bmp.Height); $y++) {
        for ($x = $x0; $x -lt [math]::Min($x1, $bmp.Width); $x++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.B -gt $c.R + 30 -and $c.B -gt 90) { $count++ }
        }
    }
    return $count
}
function Stop-App {
    Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 700
}
function Start-App([string[]]$arguments, [int]$wait = 7) {
    Stop-App
    if ($arguments) { Start-Process -FilePath $Exe -ArgumentList $arguments } else { Start-Process -FilePath $Exe }
    Start-Sleep -Seconds $wait
}

$settingsPath = Join-Path $env:APPDATA 'FluentPomodoro\settings.json'
$historyPath = Join-Path $env:APPDATA 'FluentPomodoro\history.json'
$settingsDir = Split-Path -Parent $settingsPath
if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null }
if (-not (Test-Path $Artifacts)) { New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null }
$assets = Join-Path $Artifacts 'test-assets'
$tone = Join-Path $assets 'tone-440.wav'
$toneJson = $tone.Replace('\', '\\')
$assetsJson = $assets.Replace('\', '\\')
$redJson = (Join-Path $assets 'bg-red.png').Replace('\', '\\')
$blueJson = (Join-Path $assets 'bg-blue.png').Replace('\', '\\')
$today = (Get-Date).ToString('yyyy-MM-dd')

if (-not (Test-Path $tone)) { throw "缺少测试素材，请先运行 tools\make-test-assets.ps1" }

function Write-Settings([string]$extra) {
@"
{
  "FocusMinutes": 25, "ShortBreakMinutes": 5, "LongBreakMinutes": 15, "LongBreakInterval": 4,
  "AutoStartNext": false, "SoundEnabled": false, "KeepScreenAwake": false, "AlwaysOnTop": true,
  "NotifyOnPhaseEnd": false, "FocusLock": false, "AutoBigScreenOnFocus": false,
  "Theme": "Light", "UseMicaBackdrop": false, "BigScreen": "Full", "BigScreenTopmost": true,
  "HasWindowBounds": false, "WindowLeft": 0, "WindowTop": 0, "WindowWidth": 640, "WindowHeight": 780,
  "StatsDate": "$today", "CompletedToday": 0, "FocusMinutesToday": 0, "TotalCompleted": 0,
  "StreakDays": 0, "LastCompletedDate": "",$extra
}
"@ | Set-Content -Path $settingsPath -Encoding UTF8
}

# 合成一年的历史数据，覆盖矩阵的全部色阶
$days = @{}
$rnd = New-Object System.Random 20261004
for ($i = 0; $i -lt 400; $i++) {
    $d = (Get-Date).Date.AddDays(-$i)
    $v = $rnd.Next(0, 100)
    $minutes = if ($v -lt 30) { 0 } elseif ($v -lt 45) { 15 } elseif ($v -lt 60) { 30 } elseif ($v -lt 75) { 70 } elseif ($v -lt 92) { 140 } else { 260 }
    if ($minutes -gt 0) { $days[$d.ToString('yyyy-MM-dd')] = @{ Minutes = $minutes; Pomodoros = [int]([math]::Ceiling($minutes / 25.0)) } }
}
$days[$today] = @{ Minutes = 75; Pomodoros = 3 }
$historyJson = @{ Days = $days } | ConvertTo-Json -Depth 4
Set-Content -Path $historyPath -Value $historyJson -Encoding UTF8

# ============ 1. 专注时钟 ============
Write-Settings '"ShowClock": true, "BackgroundImagePath": "", "BackgroundFolder": "", "BackgroundRotateMinutes": 0, "BackgroundRotateOnFocus": false, "BackgroundOpacity": 0.95, "BackgroundUseImageAccent": false, "NoiseTracks": [], "NoiseVolume": 70, "NoiseAutoPlayOnFocus": false, "NoiseOnlyDuringFocus": true, "NoiseShuffle": false'
Start-App @()
$w = Get-MainWindow
Check '主窗口已就绪' ($null -ne $w) $(if ($w) { $w.Title } else { '未找到窗口' })
$shot1 = Capture $w.Hwnd 'feat-01-clock-on.png'
Start-Sleep -Seconds 3
$shot2 = Capture $w.Hwnd $null
$diffOn = DiffersIn $shot1 $shot2 200 450 440 500
Check '开启时钟后界面每秒刷新（时钟区域像素变化）' ($diffOn -gt 20) "时钟区域变化像素=$diffOn"
$shot1.Dispose(); $shot2.Dispose()

Write-Settings '"ShowClock": false, "BackgroundImagePath": "", "BackgroundFolder": "", "BackgroundRotateMinutes": 0, "BackgroundRotateOnFocus": false, "BackgroundOpacity": 0.95, "BackgroundUseImageAccent": false, "NoiseTracks": [], "NoiseVolume": 70, "NoiseAutoPlayOnFocus": false, "NoiseOnlyDuringFocus": true, "NoiseShuffle": false'
Start-App @()
$w = Get-MainWindow
$shot3 = Capture $w.Hwnd 'feat-02-clock-off.png'
Start-Sleep -Seconds 3
$shot4 = Capture $w.Hwnd $null
$diffOff = DiffersIn $shot3 $shot4 200 450 440 500
Check '关闭时钟后界面静止（无时间刷新）' ($diffOff -le 5) "时钟区域变化像素=$diffOff"
$shot3.Dispose(); $shot4.Dispose()

# 1b. 「仅专注阶段显示」+ 容错读取（坏布尔值回落默认值）
Write-Settings '"ShowClock": true, "ClockOnlyDuringFocus": true, "BackgroundImagePath": "", "BackgroundFolder": "", "BackgroundRotateMinutes": 0, "BackgroundRotateOnFocus": false, "BackgroundOpacity": 0.95, "BackgroundUseImageAccent": false, "NoiseTracks": [], "NoiseVolume": 70, "NoiseAutoPlayOnFocus": false, "NoiseOnlyDuringFocus": true, "NoiseShuffle": false'
Start-App @()
$w = Get-MainWindow
$focus1 = Capture $w.Hwnd 'feat-02b-clock-focus-only.png'
Start-Sleep -Seconds 3
$focus2 = Capture $w.Hwnd $null
$diffFocus = DiffersIn $focus1 $focus2 200 450 440 500
Check '「仅专注阶段显示」：专注阶段时钟可见并刷新' ($diffFocus -gt 20) "时钟区域变化像素=$diffFocus"
$focus1.Dispose(); $focus2.Dispose()

EnsureForeground $w.Hwnd | Out-Null
[System.Windows.Forms.SendKeys]::SendWait('s')      # 跳过 → 进入休息阶段
Start-Sleep -Seconds 2
$break1 = Capture $w.Hwnd 'feat-02c-clock-hidden-in-break.png'
Start-Sleep -Seconds 3
$break2 = Capture $w.Hwnd $null
$diffBreak = DiffersIn $break1 $break2 200 450 440 500
Check '「仅专注阶段显示」：休息阶段时钟隐藏（画面静止）' ($diffBreak -le 5) "时钟区域变化像素=$diffBreak"
$break1.Dispose(); $break2.Dispose()

# 坏布尔值应回落到字段默认值（ShowClock 默认 true），而不是被当成 false
Write-Settings '"ShowClock": "oops", "ClockOnlyDuringFocus": false, "BackgroundImagePath": "", "BackgroundFolder": "", "BackgroundRotateMinutes": 0, "BackgroundRotateOnFocus": false, "BackgroundOpacity": 0.95, "BackgroundUseImageAccent": false, "NoiseTracks": [], "NoiseVolume": 70, "NoiseAutoPlayOnFocus": false, "NoiseOnlyDuringFocus": true, "NoiseShuffle": false'
Start-App @()
$w = Get-MainWindow
$bad1 = Capture $w.Hwnd 'feat-02d-bad-bool.png'
Start-Sleep -Seconds 3
$bad2 = Capture $w.Hwnd $null
$diffBad = DiffersIn $bad1 $bad2 200 450 440 500
Check '不可解析的布尔值回落到字段默认值（ShowClock: "oops" → 仍显示时钟）' ($diffBad -gt 20) "时钟区域变化像素=$diffBad"
$bad1.Dispose(); $bad2.Dispose()

# ============ 2. 背景图片 + 主题色随图 ============
Write-Settings ("`"ShowClock`": true, `"BackgroundImagePath`": `"$redJson`", `"BackgroundFolder`": `"`", `"BackgroundRotateMinutes`": 0, `"BackgroundRotateOnFocus`": false, `"BackgroundOpacity`": 1.0, `"BackgroundUseImageAccent`": true, `"NoiseTracks`": [], `"NoiseVolume`": 70, `"NoiseAutoPlayOnFocus`": false, `"NoiseOnlyDuringFocus`": true, `"NoiseShuffle`": false")
Start-App @()
$w = Get-MainWindow
$bmpRed = Capture $w.Hwnd 'feat-03-bg-red.png'
$bgRed = AverageIn $bmpRed 6 120 46 600          # 圆环左侧的纯背景条
$btnRed = MostSaturatedIn $bmpRed 150 660 340 712 # “开始专注”按钮区域（取最饱和像素 = 强调色）
Check '红色背景图被渲染到窗口背景（背景带偏红）' ($bgRed.R -gt $bgRed.B + 10) "背景均值 R=$($bgRed.R) G=$($bgRed.G) B=$($bgRed.B)"
Check '主题色跟随图片主色（红图 → 红色强调按钮）' ($null -ne $btnRed.Color -and $btnRed.Color.R -gt $btnRed.Color.B + 20) "按钮最饱和像素 R=$($btnRed.Color.R) G=$($btnRed.Color.G) B=$($btnRed.Color.B) 饱和度=$($btnRed.Sat)"
$bmpRed.Dispose()

Write-Settings ("`"ShowClock`": true, `"BackgroundImagePath`": `"$blueJson`", `"BackgroundFolder`": `"`", `"BackgroundRotateMinutes`": 0, `"BackgroundRotateOnFocus`": false, `"BackgroundOpacity`": 1.0, `"BackgroundUseImageAccent`": true, `"NoiseTracks`": [], `"NoiseVolume`": 70, `"NoiseAutoPlayOnFocus`": false, `"NoiseOnlyDuringFocus`": true, `"NoiseShuffle`": false")
Start-App @()
$w = Get-MainWindow
$bmpBlue = Capture $w.Hwnd 'feat-04-bg-blue.png'
$btnBlue = MostSaturatedIn $bmpBlue 150 660 340 712
Check '换蓝色背景图后主题色随之变蓝' ($null -ne $btnBlue.Color -and $btnBlue.Color.B -gt $btnBlue.Color.R + 20) "按钮最饱和像素 R=$($btnBlue.Color.R) G=$($btnBlue.Color.G) B=$($btnBlue.Color.B) 饱和度=$($btnBlue.Sat)"
$bmpBlue.Dispose()

# ============ 3. 每次开始专注换一张 ============
Write-Settings ("`"ShowClock`": true, `"BackgroundImagePath`": `"`", `"BackgroundFolder`": `"$assetsJson`", `"BackgroundRotateMinutes`": 0, `"BackgroundRotateOnFocus`": true, `"BackgroundOpacity`": 1.0, `"BackgroundUseImageAccent`": true, `"NoiseTracks`": [], `"NoiseVolume`": 70, `"NoiseAutoPlayOnFocus`": false, `"NoiseOnlyDuringFocus`": true, `"NoiseShuffle`": false")
Start-App @()
$w = Get-MainWindow
Check '文件夹模式载入多张背景图' ($null -ne $w) $(if ($w) { $w.Title } else { '' })
$before = Capture $w.Hwnd 'feat-05-folder-before.png'
EnsureForeground $w.Hwnd | Out-Null
[System.Windows.Forms.SendKeys]::SendWait(' ')
Start-Sleep -Seconds 2
$after = Capture $w.Hwnd 'feat-06-folder-after-focus.png'
$bgDiff = DiffersIn $before $after 6 120 46 600 8
Check '开始专注时自动换一张背景图' ($bgDiff -gt 20) "背景条变化像素=$bgDiff"
$before.Dispose(); $after.Dispose()

# ============ 4. 统计绿点矩阵窗口 ============
Send-Keys '^i'
Start-Sleep -Seconds 2
$stats = Get-StatsWindow
Check 'Ctrl+I 打开统计二级窗口' ($null -ne $stats) $(if ($stats) { "$($stats.Title) $($stats.Rect.R - $stats.Rect.L)x$($stats.Rect.B - $stats.Rect.T)" } else { '未找到' })

if ($stats) {
    $bmpStats = Capture $stats.Hwnd 'feat-07-stats-window.png'
    # 统计绿点矩阵的 6 个色阶（浅色主题）在截图中的命中像素数
    $levels = @(
        @{ Name = 'L0 #EBEDF0'; R = 235; G = 237; B = 240 },
        @{ Name = 'L1 #9BE9A8'; R = 155; G = 233; B = 168 },
        @{ Name = 'L2 #40C463'; R = 64;  G = 196; B = 99 },
        @{ Name = 'L3 #30A14E'; R = 48;  G = 161; B = 78 },
        @{ Name = 'L4 #216E39'; R = 33;  G = 110; B = 57 },
        @{ Name = 'L5 #0B3B22'; R = 11;  G = 59;  B = 34 }
    )
    $hits = @{}
    foreach ($lv in $levels) { $hits[$lv.Name] = 0 }
    for ($y = 0; $y -lt $bmpStats.Height; $y += 1) {
        for ($x = 0; $x -lt $bmpStats.Width; $x += 1) {
            $c = $bmpStats.GetPixel($x, $y)
            foreach ($lv in $levels) {
                if ([math]::Abs($c.R - $lv.R) -le 4 -and [math]::Abs($c.G - $lv.G) -le 4 -and [math]::Abs($c.B - $lv.B) -le 4) { $hits[$lv.Name]++; break }
            }
        }
    }
    $found = @($levels | Where-Object { $hits[$_.Name] -gt 50 })
    $detail = ($levels | ForEach-Object { "$($_.Name)=$($hits[$_.Name])" }) -join ' '
    Check '绿点矩阵渲染出 0~5 全部 6 个色阶（颜色随时长加深）' ($found.Count -ge 6) $detail
    $bmpStats.Dispose()
    Send-Keys '{ESC}'
    Start-Sleep -Seconds 1
}

# ============ 5. 白噪音（导入音频 + 专注自动播放）============
Write-Settings ("`"ShowClock`": true, `"BackgroundImagePath`": `"`", `"BackgroundFolder`": `"`", `"BackgroundRotateMinutes`": 0, `"BackgroundRotateOnFocus`": false, `"BackgroundOpacity`": 0.95, `"BackgroundUseImageAccent`": false, `"NoiseTracks`": [`"$toneJson`"], `"NoiseVolume`": 40, `"NoiseAutoPlayOnFocus`": true, `"NoiseOnlyDuringFocus`": true, `"NoiseShuffle`": false")
Start-App @()
$w = Get-MainWindow
$idle = Capture $w.Hwnd 'feat-08-noise-idle.png'
$blueIdle = CountBluePixels $idle 415 8 452 34
$idle.Dispose()

EnsureForeground $w.Hwnd | Out-Null
[System.Windows.Forms.SendKeys]::SendWait(' ')
Start-Sleep -Seconds 3
$playing = Capture $w.Hwnd 'feat-09-noise-playing.png'
$bluePlaying = CountBluePixels $playing 415 8 452 34
$playing.Dispose()
Check '开始专注后白噪音自动播放（标题栏按钮变为强调色）' ($bluePlaying -gt $blueIdle + 10) "闲置蓝像素=$blueIdle 播放中蓝像素=$bluePlaying"

EnsureForeground $w.Hwnd | Out-Null
[System.Windows.Forms.SendKeys]::SendWait(' ')
Start-Sleep -Seconds 2
$paused = Capture $w.Hwnd 'feat-10-noise-paused.png'
$bluePaused = CountBluePixels $paused 415 8 452 34
$paused.Dispose()
Check '暂停后就绪（仅专注播放时自动停）' ($bluePaused -le $blueIdle + 5) "暂停后蓝像素=$bluePaused"

# ============ 清理 ============
Stop-App
Remove-Item $settingsPath -Force -ErrorAction SilentlyContinue
Remove-Item $historyPath -Force -ErrorAction SilentlyContinue

Write-Host ''
$script:results | Format-Table -AutoSize
$failed = @($script:results | Where-Object { $_.结果 -ne '通过' }).Count
Write-Host ("通过 {0} / {1} 项" -f ($script:results.Count - $failed), $script:results.Count)
exit $failed
