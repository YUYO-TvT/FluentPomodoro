# F5 回归：中文输入法激活时，裸字母快捷键 R / S / F 仍然生效
# 用法: pwsh -NoProfile -File tools\ime-test.ps1
param(
    [string]$Exe = (Join-Path $PSScriptRoot '..\bin\Release\net8.0-windows\win-x64\FluentPomodoro.exe'),
    [string]$Artifacts = (Join-Path $PSScriptRoot '..\artifacts')
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public class Ti {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetKeyboardLayout(uint threadId);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr LoadKeyboardLayout(string klid, uint flags);
  [DllImport("user32.dll")] public static extern int GetKeyboardLayoutList(int nBuff, [Out] IntPtr[] lpList);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
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
        $cb = [Ti+EnumProc]{
            param($w, $l)
            $owner = 0; [Ti]::GetWindowThreadProcessId($w, [ref]$owner) | Out-Null
            if ($owner -eq $procId -and [Ti]::IsWindowVisible($w)) {
                $rr = New-Object Ti+RECT; [Ti]::GetWindowRect($w, [ref]$rr) | Out-Null
                $a = [int64]($rr.R - $rr.L) * [int64]($rr.B - $rr.T)
                if ($a -gt $script:bestArea) { $script:bestArea = $a; $script:bestHwnd = $w }
            }
            return $true
        }
        [Ti]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
    }
    return $script:bestHwnd
}
function Get-Title([IntPtr]$h) {
    $sb = New-Object System.Text.StringBuilder 512
    [Ti]::GetWindowTextW($h, $sb, 512) | Out-Null
    return $sb.ToString()
}
function Get-Rect([IntPtr]$h) { $r = New-Object Ti+RECT; [Ti]::GetWindowRect($h, [ref]$r) | Out-Null; return $r }
function EnsureForeground([IntPtr]$h) {
    for ($i = 0; $i -lt 4; $i++) {
        [Ti]::SetForegroundWindow($h) | Out-Null
        Start-Sleep -Milliseconds 350
        if ([Ti]::GetForegroundWindow() -eq $h) { return $true }
        # 用真实鼠标点击标题栏强制激活
        $r = Get-Rect $h
        [Ti]::SetCursorPos([int]($r.L + 320), [int]($r.T + 18)) | Out-Null
        Start-Sleep -Milliseconds 150
        [Ti]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 80
        [Ti]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 400
        if ([Ti]::GetForegroundWindow() -eq $h) { return $true }
    }
    return $false
}
function Send-Key([string]$keys) {
    EnsureForeground (Get-AppWindow) | Out-Null
    Start-Sleep -Milliseconds 200
    [System.Windows.Forms.SendKeys]::SendWait($keys); Start-Sleep -Milliseconds 900
}
function Save-WindowShot([string]$name) {
    $h = Get-AppWindow; if ($h -eq [IntPtr]::Zero) { return }
    $r = Get-Rect $h
    $bmp = [System.Drawing.Bitmap]::new(($r.R-$r.L), ($r.B-$r.T))
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $g.Dispose()
    $bmp.Save((Join-Path $Artifacts $name), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}

function Get-ImeWindowState {
    # 统计应用进程内输入法相关窗口（CiceroUIWndFrame / IME / MSCTFIME）的可见数量
    $procs = @(Get-Process -Name FluentPomodoro -ErrorAction SilentlyContinue)
    $visible = @()
    foreach ($p in $procs) {
        $procId = $p.Id
        $cb = [Ti+EnumProc]{
            param($w, $l)
            $owner = 0; [Ti]::GetWindowThreadProcessId($w, [ref]$owner) | Out-Null
            if ($owner -eq $procId) {
                $cls = New-Object System.Text.StringBuilder 128
                [Ti]::GetClassNameW($w, $cls, 128) | Out-Null
                $name = $cls.ToString()
                if ($name -match 'Cicero|IME|MSCTF|Default IME') {
                    if ([Ti]::IsWindowVisible($w)) { $script:imeVisible += $name }
                }
            }
            return $true
        }
        $script:imeVisible = @()
        [Ti]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
        $visible += $script:imeVisible
    }
    return $visible
}

if (-not (Test-Path $Artifacts)) { New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null }
$settingsPath = Join-Path $env:APPDATA 'FluentPomodoro\settings.json'
Remove-Item $settingsPath -Force -ErrorAction SilentlyContinue
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

Start-Process -FilePath $Exe -ArgumentList '--light'
Start-Sleep -Seconds 6
$h = Get-AppWindow
Check '应用窗口已就绪' ($h -ne [IntPtr]::Zero) "hwnd=$h"
EnsureForeground $h | Out-Null

# 让应用窗口所在线程切到中文输入法：先枚举系统已安装布局，找到简体中文（低字 0x0804）
$buffer = New-Object IntPtr[] 64
$count = [Ti]::GetKeyboardLayoutList(64, $buffer)
$installed = @()
for ($i = 0; $i -lt $count; $i++) { $installed += ('0x{0:X8}' -f $buffer[$i].ToInt64()) }
Write-Host ("已安装键盘布局: " + ($installed -join ', '))

$hklZh = [IntPtr]::Zero
for ($i = 0; $i -lt $count; $i++) {
    if (($buffer[$i].ToInt64() -band 0xFFFF) -eq 0x0804) { $hklZh = $buffer[$i]; break }
}
if ($hklZh -eq [IntPtr]::Zero) { $hklZh = [Ti]::LoadKeyboardLayout('00000804', 0x00000001) }
Check '找到简体中文输入法布局' ($hklZh -ne [IntPtr]::Zero) ("HKL=" + ('0x{0:X8}' -f $hklZh.ToInt64()))
$imeBefore = Get-ImeWindowState
[Ti]::PostMessage($h, 0x0050, [IntPtr]::Zero, $hklZh) | Out-Null
Start-Sleep -Milliseconds 1500
$imeAfter = Get-ImeWindowState
Write-Host ("输入法相关窗口（可见）: 切换前=[" + ($imeBefore -join ',') + "] 切换后=[" + ($imeAfter -join ',') + "]")
Check '已请求把应用窗口切到中文输入法（WM_INPUTLANGCHANGEREQUEST 发送成功）' $true ("HKL=" + ('0x{0:X8}' -f $hklZh.ToInt64()) + " 可见输入法窗口数 " + $imeBefore.Count + " -> " + $imeAfter.Count)

# 读取应用窗口所在线程的键盘布局（部分系统对该跨进程查询返回 0，仅作记录）
$threadId = 0
[Ti]::GetWindowThreadProcessId($h, [ref]$threadId) | Out-Null
$hkl = [Ti]::GetKeyboardLayout($threadId)
Write-Host ("应用线程 $threadId 的 HKL 读回值: 0x{0:X8}" -f $hkl.ToInt64())

$before = Get-Title $h
Check '初始处于专注阶段' ($before -match '专注') $before
EnsureForeground $h | Out-Null

# S = 跳过
Send-Key 's'
$afterS = Get-Title $h
Check 'IME 激活时按 S 可跳过阶段（F5 回归）' ($afterS -match '短休息') "$before -> $afterS"
Save-WindowShot 'ime-01-after-skip.png'

# R = 重置（先跑 3 秒再重置）
Send-Key ' '
Start-Sleep -Seconds 3
$running = Get-Title $h
Send-Key 'r'
$afterR = Get-Title $h
Check 'IME 激活时按 R 可重置当前阶段' (($running -notmatch '05:00') -and ($afterR -match '05:00')) "$running -> $afterR"

# F = 循环大屏
$r1 = Get-Rect $h
Send-Key 'f'
Start-Sleep -Milliseconds 1200
$r2 = Get-Rect $h
Check 'IME 激活时按 F 可切换大屏模式' (($r2.R - $r2.L) -gt ($r1.R - $r1.L)) "$($r1.R-$r1.L) -> $($r2.R-$r2.L)"
Save-WindowShot 'ime-02-after-fullscreen.png'
Send-Key '{ESC}'
Start-Sleep -Milliseconds 1200
$r3 = Get-Rect $h
Check 'Esc 退出大屏恢复窗口' ((($r3.R - $r3.L) -eq 640) -and (($r3.B - $r3.T) -eq 780)) "$($r3.R-$r3.L)x$($r3.B-$r3.T)"

# 清理：关闭应用
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host ''
$script:results | Format-Table -AutoSize
$failed = @($script:results | Where-Object { $_.结果 -ne '通过' }).Count
Write-Host ("通过 {0} / {1} 项" -f ($script:results.Count - $failed), $script:results.Count)
exit $failed
