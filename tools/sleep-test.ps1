# 仅针对「专注时限制系统休眠」这一功能的专项验证
# 用 powercfg /requests 观察进程对系统睡眠/显示的实际电源请求
# 用法: pwsh -NoProfile -File tools\sleep-test.ps1
param(
    [string]$Exe = (Join-Path $PSScriptRoot '..\bin\Release\net8.0-windows\win-x64\FluentPomodoro.exe'),
    [string]$Artifacts = (Join-Path $PSScriptRoot '..\artifacts')
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices; using System.Text;
public class Sl {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, int m, IntPtr w, IntPtr l);
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
$script:bestHwnd = [IntPtr]::Zero; $script:bestArea = -1
function Get-AppWindow {
    $procs = @(Get-Process -Name FluentPomodoro -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return [IntPtr]::Zero }
    $script:bestHwnd = [IntPtr]::Zero; $script:bestArea = -1
    foreach ($p in $procs) {
        $procId = $p.Id
        $cb = [Sl+EnumProc]{
            param($w, $l)
            $owner = 0; [Sl]::GetWindowThreadProcessId($w, [ref]$owner) | Out-Null
            if ($owner -eq $procId -and [Sl]::IsWindowVisible($w)) {
                $rr = New-Object Sl+RECT; [Sl]::GetWindowRect($w, [ref]$rr) | Out-Null
                $a = [int64]($rr.R - $rr.L) * [int64]($rr.B - $rr.T)
                if ($a -gt $script:bestArea) { $script:bestArea = $a; $script:bestHwnd = $w }
            }
            return $true
        }
        [Sl]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
    }
    return $script:bestHwnd
}
function Get-Title([IntPtr]$h) {
    $sb = New-Object System.Text.StringBuilder 512
    [Sl]::GetWindowTextW($h, $sb, 512) | Out-Null
    return $sb.ToString()
}
function EnsureForeground([IntPtr]$h) {
    for ($i = 0; $i -lt 4; $i++) {
        [Sl]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 300
        if ([Sl]::GetForegroundWindow() -eq $h) { return $true }
        $r = New-Object Sl+RECT; [Sl]::GetWindowRect($h, [ref]$r) | Out-Null
        [Sl]::SetCursorPos([int]($r.L + 320), [int]($r.T + 18)) | Out-Null; Start-Sleep -Milliseconds 150
        [Sl]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80
        [Sl]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 400
        if ([Sl]::GetForegroundWindow() -eq $h) { return $true }
    }
    return $false
}
function Send-Keys([string]$keys) {
    $w = Get-AppWindow
    if ($w -ne [IntPtr]::Zero) { EnsureForeground $w | Out-Null }
    Start-Sleep -Milliseconds 200
    [System.Windows.Forms.SendKeys]::SendWait($keys)
    Start-Sleep -Milliseconds 900
}
# powercfg /requests 解析：小节标题保持英文，内容为本地化文本
function Get-PowerRequests {
    $text = (& powercfg /requests 2>&1 | Out-String)
    $sections = @{}
    $current = $null
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '^\s*(DISPLAY|SYSTEM|AWAYMODE|EXECUTION)\s*:') {
            $current = $matches[1]
            $sections[$current] = @()
            continue
        }
        if ($current -and $line.Trim().Length -gt 0) { $sections[$current] += $line.Trim() }
    }
    return $sections
}
function Has-AppRequest([hashtable]$sections, [string]$name) {
    if (-not $sections.ContainsKey($name)) { return $false }
    $hit = @($sections[$name] | Where-Object { $_ -match 'FluentPomodoro' })
    return $hit.Count -gt 0
}
function Dump-Requests([hashtable]$sections) {
    return (($sections.Keys | Sort-Object | ForEach-Object { "$_=[$((($sections[$_] | Where-Object { $_ -match 'FluentPomodoro' }) -join ';'))]" }) -join ' ')
}
function Stop-App {
    Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 700
}
function Start-App([int]$wait = 7) {
    Stop-App
    Start-Process -FilePath $Exe | Out-Null
    Start-Sleep -Seconds $wait
}
$settingsPath = Join-Path $env:APPDATA 'FluentPomodoro\settings.json'
$settingsDir = Split-Path -Parent $settingsPath
if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null }
$today = (Get-Date).ToString('yyyy-MM-dd')

function Write-Settings([bool]$noSleep, [bool]$screenOn, [bool]$autoNext = $false) {
    $ns = if ($noSleep) { 'true' } else { 'false' }
    $so = if ($screenOn) { 'true' } else { 'false' }
    $an = if ($autoNext) { 'true' } else { 'false' }
@"
{
  "FocusMinutes": 25, "ShortBreakMinutes": 5, "LongBreakMinutes": 15, "LongBreakInterval": 4,
  "AutoStartNext": $an, "SoundEnabled": false, "PreventSystemSleep": $ns, "KeepScreenAwake": $so,
  "AlwaysOnTop": true, "NotifyOnPhaseEnd": false, "FocusLock": false, "AutoBigScreenOnFocus": false,
  "Theme": "Light", "UseMicaBackdrop": false, "BigScreen": "Full", "BigScreenTopmost": true,
  "ShowClock": false, "ClockOnlyDuringFocus": false,
  "BackgroundImagePath": "", "BackgroundFolder": "", "BackgroundRotateMinutes": 0,
  "BackgroundRotateOnFocus": false, "BackgroundOpacity": 0.95, "BackgroundUseImageAccent": false,
  "NoiseTracks": [], "NoiseVolume": 70, "NoiseAutoPlayOnFocus": false, "NoiseOnlyDuringFocus": true, "NoiseShuffle": false,
  "HasWindowBounds": false, "WindowLeft": 0, "WindowTop": 0, "WindowWidth": 640, "WindowHeight": 780,
  "StatsDate": "$today", "CompletedToday": 0, "FocusMinutesToday": 0, "TotalCompleted": 0,
  "StreakDays": 0, "LastCompletedDate": ""
}
"@ | Set-Content -Path $settingsPath -Encoding UTF8
}

Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item $settingsPath -Force -ErrorAction SilentlyContinue
if (-not (Test-Path $Artifacts)) { New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null }

# ============ A. 只开「阻止系统休眠」============
Write-Settings $true $false
Start-App
$w = Get-AppWindow
$idle = Get-PowerRequests
Check 'A1 未开始计时时不做任何电源请求' ((-not (Has-AppRequest $idle 'SYSTEM')) -and (-not (Has-AppRequest $idle 'DISPLAY'))) (Dump-Requests $idle)

Send-Keys ' '                      # 开始专注
Start-Sleep -Seconds 2
$running = Get-PowerRequests
Check 'A2 专注中阻止系统休眠：SYSTEM 出现本进程请求' (Has-AppRequest $running 'SYSTEM') (Dump-Requests $running)
Check 'A3 未开启屏幕常亮：DISPLAY 无请求' (-not (Has-AppRequest $running 'DISPLAY')) (Dump-Requests $running)

Send-Keys ' '                      # 暂停
Start-Sleep -Seconds 2
$paused = Get-PowerRequests
Check 'A4 暂停后释放休眠请求' (-not (Has-AppRequest $paused 'SYSTEM')) (Dump-Requests $paused)

Send-Keys ' '                      # 继续
Start-Sleep -Seconds 2
$resumed = Get-PowerRequests
Check 'A5 继续后重新申请休眠请求' (Has-AppRequest $resumed 'SYSTEM') (Dump-Requests $resumed)

Send-Keys 's'                      # 跳过 → 进入休息（不自动开始）
Start-Sleep -Seconds 2
$break = Get-PowerRequests
Check 'A6 进入休息阶段后不再阻止休眠' (-not (Has-AppRequest $break 'SYSTEM')) (Dump-Requests $break)

# ============ B. 只开「屏幕常亮」============
Write-Settings $false $true
Start-App
$w = Get-AppWindow
Send-Keys ' '
Start-Sleep -Seconds 2
$screenOnly = Get-PowerRequests
Check 'B1 只开屏幕常亮：DISPLAY 出现请求' (Has-AppRequest $screenOnly 'DISPLAY') (Dump-Requests $screenOnly)
Check 'B2 只开屏幕常亮：SYSTEM 无请求（未开阻止休眠）' (-not (Has-AppRequest $screenOnly 'SYSTEM')) (Dump-Requests $screenOnly)

# ============ C. 两个都关 ============
Write-Settings $false $false
Start-App
$w = Get-AppWindow
Send-Keys ' '
Start-Sleep -Seconds 2
$none = Get-PowerRequests
Check 'C1 两个开关都关：专注中无任何电源请求' ((-not (Has-AppRequest $none 'SYSTEM')) -and (-not (Has-AppRequest $none 'DISPLAY'))) (Dump-Requests $none)

# ============ D. 默认（都开）+ 睡眠/恢复消息处理 ============
Write-Settings $true $true
Start-App
$w = Get-AppWindow
Send-Keys ' '
Start-Sleep -Seconds 2
$both = Get-PowerRequests
Check 'D1 默认设置：SYSTEM 与 DISPLAY 同时有请求' ((Has-AppRequest $both 'SYSTEM') -and (Has-AppRequest $both 'DISPLAY')) (Dump-Requests $both)

# 模拟系统睡眠广播（与真实 WM_POWERBROADCAST 相同）
[Sl]::PostMessage($w, 0x0218, [IntPtr]4, [IntPtr]::Zero) | Out-Null   # PBT_APMSUSPEND
Start-Sleep -Seconds 2
$t1 = Get-Title $w
Start-Sleep -Seconds 3
$t2 = Get-Title $w
Check 'D2 收到睡眠广播后专注被暂停（倒计时冻结）' ($t1 -eq $t2 -and $t1 -notmatch '25:00$') "$t1 / $t2"
$afterSuspend = Get-PowerRequests
Check 'D3 睡眠暂停后释放电源请求' ((-not (Has-AppRequest $afterSuspend 'SYSTEM')) -and (-not (Has-AppRequest $afterSuspend 'DISPLAY'))) (Dump-Requests $afterSuspend)

[Sl]::PostMessage($w, 0x0218, [IntPtr]18, [IntPtr]::Zero) | Out-Null  # PBT_APMRESUMEAUTOMATIC
Start-Sleep -Seconds 2
Check 'D4 收到恢复广播后进程正常存活' ($null -ne (Get-Process FluentPomodoro -ErrorAction SilentlyContinue)) ''
Send-Keys ' '                       # 按空格继续
Start-Sleep -Seconds 2
$afterResume = Get-PowerRequests
Check 'D5 恢复后继续专注会重新申请 SYSTEM+DISPLAY' ((Has-AppRequest $afterResume 'SYSTEM') -and (Has-AppRequest $afterResume 'DISPLAY')) (Dump-Requests $afterResume)

$bmp = [System.Drawing.Bitmap]::new(640, 780)
$r = New-Object Sl+RECT; [Sl]::GetWindowRect($w, [ref]$r) | Out-Null
$g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $g.Dispose()
$bmp.Save((Join-Path $Artifacts 'sleep-feature.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Stop-App
Remove-Item $settingsPath -Force -ErrorAction SilentlyContinue

Write-Host ''
$script:results | Format-Table -AutoSize
$failed = @($script:results | Where-Object { $_.结果 -ne '通过' }).Count
Write-Host ("通过 {0} / {1} 项" -f ($script:results.Count - $failed), $script:results.Count)
exit $failed
