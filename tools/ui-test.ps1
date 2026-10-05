# 端到端 UI 验收测试：拖动窗口 / 设置面板 / 强制大屏 / 计时 / 退出
# 用法: pwsh -NoProfile -File tools\ui-test.ps1
param(
    [string]$Exe = (Join-Path $PSScriptRoot '..\bin\Release\net8.0-windows\win-x64\FluentPomodoro.exe'),
    [string]$Artifacts = (Join-Path $PSScriptRoot '..\artifacts')
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Ui {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr wp, IntPtr lp);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
  public struct RECT { public int L,T,R,B; }
}
"@

$script:results = @()
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    $script:results += [pscustomobject]@{ 检查项 = $name; 结果 = $(if ($ok) { '通过' } else { '未通过' }); 说明 = $detail }
    Write-Host ("[{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $detail)
}

function Get-Rect([IntPtr]$h) {
    $r = New-Object Ui+RECT
    [Ui]::GetWindowRect($h, [ref]$r) | Out-Null
    return $r
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
        $cb = [Ui+EnumProc]{
            param($w, $l)
            $owner = 0
            [Ui]::GetWindowThreadProcessId($w, [ref]$owner) | Out-Null
            if ($owner -eq $procId -and [Ui]::IsWindowVisible($w)) {
                $rr = New-Object Ui+RECT
                [Ui]::GetWindowRect($w, [ref]$rr) | Out-Null
                $area = [int64]($rr.R - $rr.L) * [int64]($rr.B - $rr.T)
                if ($area -gt $script:bestArea) { $script:bestArea = $area; $script:bestHwnd = $w }
            }
            return $true
        }
        [Ui]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
    }
    return $script:bestHwnd
}

function Get-Title([IntPtr]$h) {
    $sb = New-Object System.Text.StringBuilder 512
    [Ui]::GetWindowTextW($h, $sb, 512) | Out-Null
    return $sb.ToString()
}

function Save-WindowShot([string]$name) {
    $h = Get-AppWindow
    if ($h -eq [IntPtr]::Zero) { return }
    Start-Sleep -Milliseconds 250
    $r = Get-Rect $h
    $w = $r.R - $r.L; $ht = $r.B - $r.T
    $bmp = [System.Drawing.Bitmap]::new($w, $ht)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
    $g.Dispose()
    $bmp.Save((Join-Path $Artifacts $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

function Save-ScreenShot([string]$name) {
    $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = [System.Drawing.Bitmap]::new($vs.Width, $vs.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($vs.Left, $vs.Top, 0, 0, $bmp.Size)
    $g.Dispose()
    $bmp.Save((Join-Path $Artifacts $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

function Click-At([int]$x, [int]$y) {
    [Ui]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 180
    [Ui]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [Ui]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 420
}

function Drag([int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    [Ui]::SetCursorPos($x1, $y1) | Out-Null
    Start-Sleep -Milliseconds 200
    [Ui]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        $nx = [int]($x1 + ($x2 - $x1) * $i / 12)
        $ny = [int]($y1 + ($y2 - $y1) * $i / 12)
        [Ui]::SetCursorPos($nx, $ny) | Out-Null
        Start-Sleep -Milliseconds 25
    }
    [Ui]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 400
}

function Send-Keys([string]$keys) {
    [Ui]::SetForegroundWindow((Get-AppWindow)) | Out-Null
    Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait($keys)
    Start-Sleep -Milliseconds 500
}

if (-not (Test-Path $Artifacts)) { New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null }

# ---------- 启动 ----------
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
Start-Process -FilePath $Exe
Start-Sleep -Seconds 6

$h = Get-AppWindow
Check '程序启动并创建主窗口' ($h -ne [IntPtr]::Zero) "hwnd=$h"
if ($h -eq [IntPtr]::Zero) { $script:results | Format-Table -AutoSize; exit 1 }

$title = Get-Title $h
Check '窗口标题包含倒计时信息' ($title -match '25:00') $title

$r0 = Get-Rect $h
Check '默认窗口尺寸为 640x780' (($r0.R - $r0.L) -eq 640 -and ($r0.B - $r0.T) -eq 780) "$($r0.R-$r0.L)x$($r0.B-$r0.T)"
Save-WindowShot 'ui-01-window.png'

# ---------- 标题栏拖动 ----------
[Ui]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 400
Drag ($r0.L + 300) ($r0.T + 18) ($r0.L + 400) ($r0.T + 70)
$r1 = Get-Rect $h
Check '窗口可被标题栏拖动（WindowChrome 命中测试正常）' ([math]::Abs($r1.L - $r0.L) -gt 50) "新位置 $($r1.L),$($r1.T)"

# ---------- 设置面板 ----------
Send-Keys '^,'
Start-Sleep -Milliseconds 700
Save-WindowShot 'ui-02-settings.png'

# 关闭设置（Esc）
Send-Keys '{ESC}'
Start-Sleep -Milliseconds 700
Save-WindowShot 'ui-03-settings-closed.png'

# ---------- 强制大屏：巨幕跨屏 ----------
$visible = Get-Rect $h
Click-At ($visible.L + 158) ($visible.B - 40)
Start-Sleep -Milliseconds 1200
$r2 = Get-Rect $h
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$mega = ($r2.L -le $vs.Left + 1) -and ($r2.T -le $vs.Top + 1) -and
        (($r2.R - $r2.L) -ge $vs.Width - 2) -and (($r2.B - $r2.T) -ge $vs.Height - 2)
Check '「巨幕跨屏」铺满整个虚拟桌面' $mega "$($r2.R-$r2.L)x$($r2.B-$r2.T) @ $($r2.L),$($r2.T)（虚拟桌面 $($vs.Width)x$($vs.Height)）"
Save-ScreenShot 'ui-04-megascreen.png'

# 大屏时最小化应被拦截
[Ui]::SendMessage($h, 0x0112, [IntPtr]0xF020, [IntPtr]::Zero) | Out-Null
Start-Sleep -Milliseconds 700
Check '大屏模式下最小化被拦截' (-not [Ui]::IsIconic($h)) "IsIconic=$([Ui]::IsIconic($h))"

# 大屏时窗口位置被强制锁定（尝试移动无效）
$before = Get-Rect $h
[Ui]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 300
Drag ($before.L + 300) ($before.T + 18) ($before.L + 500) ($before.T + 260)
$after = Get-Rect $h
Check '大屏模式下位置被强制锁定' (($after.L -eq $before.L) -and ($after.T -eq $before.T)) "锁定于 $($after.L),$($after.T)"

# ---------- 退出大屏 ----------
Send-Keys '{ESC}'
Start-Sleep -Milliseconds 1200
$r3 = Get-Rect $h
Check 'Esc 退出大屏并恢复窗口模式' ((($r3.R - $r3.L) -eq 640) -and (($r3.B - $r3.T) -eq 780)) "$($r3.R-$r3.L)x$($r3.B-$r3.T) @ $($r3.L),$($r3.T)"
Save-WindowShot 'ui-05-after-exit-bigscreen.png'

# ---------- 计时启动 ----------
$titleBefore = Get-Title $h
Send-Keys ' '
Start-Sleep -Milliseconds 2600
$titleRunning = Get-Title $h
Check '空格启动计时（标题倒计时递减）' ($titleRunning -match '24:5' -and $titleRunning -ne $titleBefore) "$titleBefore -> $titleRunning"
Save-WindowShot 'ui-06-running.png'

# 暂停
Send-Keys ' '
Start-Sleep -Milliseconds 800
$paused1 = Get-Title $h
Start-Sleep -Seconds 3
$paused2 = Get-Title $h
Check '空格再次按下进入暂停（倒计时停住）' ($paused1 -match '专注' -and $paused1 -eq $paused2) "$paused1 / $paused2"

# ---------- 关闭 ----------
Send-Keys '^+q'
Start-Sleep -Seconds 3
$alive = [bool](Get-Process FluentPomodoro -ErrorAction SilentlyContinue)
Check 'Ctrl+Shift+Q 正常退出进程' (-not $alive)

$settingsPath = Join-Path $env:APPDATA 'FluentPomodoro\settings.json'
Check '退出时写入 settings.json' (Test-Path $settingsPath) $settingsPath

Write-Host ''
$script:results | Format-Table -AutoSize
$failed = @($script:results | Where-Object { $_.结果 -ne '通过' }).Count
Write-Host ("通过 {0} / {1} 项" -f ($script:results.Count - $failed), $script:results.Count)
exit $failed

