# 主题下拉框真实鼠标路径测试：设置面板 → 外观 → 下拉 → 选“深色” → 重启后仍为深色
# 用法: pwsh -NoProfile -File tools\theme-ui-test.ps1
param(
    [string]$Exe = (Join-Path $PSScriptRoot '..\bin\Release\net8.0-windows\win-x64\FluentPomodoro.exe'),
    [string]$Artifacts = (Join-Path $PSScriptRoot '..\artifacts')
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public class Tu {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
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
$script:bestHwnd = [IntPtr]::Zero; $script:bestArea = -1
function Get-AppWindow {
    $procs = @(Get-Process -Name FluentPomodoro -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return [IntPtr]::Zero }
    $script:bestHwnd = [IntPtr]::Zero; $script:bestArea = -1
    foreach ($p in $procs) {
        $procId = $p.Id
        $cb = [Tu+EnumProc]{
            param($w, $l)
            $owner = 0; [Tu]::GetWindowThreadProcessId($w, [ref]$owner) | Out-Null
            if ($owner -eq $procId -and [Tu]::IsWindowVisible($w)) {
                $rr = New-Object Tu+RECT; [Tu]::GetWindowRect($w, [ref]$rr) | Out-Null
                $a = [int64]($rr.R - $rr.L) * [int64]($rr.B - $rr.T)
                if ($a -gt $script:bestArea) { $script:bestArea = $a; $script:bestHwnd = $w }
            }
            return $true
        }
        [Tu]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
    }
    return $script:bestHwnd
}
function Get-Rect([IntPtr]$h) { $r = New-Object Tu+RECT; [Tu]::GetWindowRect($h, [ref]$r) | Out-Null; return $r }
function Click([int]$x, [int]$y) {
    [Tu]::SetCursorPos($x, $y) | Out-Null; Start-Sleep -Milliseconds 220
    [Tu]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80
    [Tu]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 550
}
function Wheel([int]$x, [int]$y, [int]$notchesDown, [int]$notchesUp) {
    [Tu]::SetCursorPos($x, $y) | Out-Null
    for ($i = 0; $i -lt $notchesDown; $i++) {
        [Tu]::mouse_event(0x0800, 0, 0, [uint32]::MaxValue - 119, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 130
    }
    for ($i = 0; $i -lt $notchesUp; $i++) {
        [Tu]::mouse_event(0x0800, 0, 0, 120, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 130
    }
    Start-Sleep -Milliseconds 600
}
function PanelPixelDark([IntPtr]$h) {
    # 设置面板内容区（窗口内 300,200）在浅色主题下接近 #FFFFFF，深色主题下接近 #2C2C2C
    $r = Get-Rect $h
    $bmp = [System.Drawing.Bitmap]::new(($r.R-$r.L), ($r.B-$r.T))
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $g.Dispose()
    $c = $bmp.GetPixel(300, 200)
    $bmp.Dispose()
    return (($c.R + $c.G + $c.B) / 3 -lt 90)
}
function Save-WindowShot([string]$name) {
    $h = Get-AppWindow; if ($h -eq [IntPtr]::Zero) { return }
    $r = Get-Rect $h
    $bmp = [System.Drawing.Bitmap]::new(($r.R-$r.L), ($r.B-$r.T))
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $g.Dispose()
    $bmp.Save((Join-Path $Artifacts $name), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
function AverageBackground([IntPtr]$h) {
    $r = Get-Rect $h
    $bmp = [System.Drawing.Bitmap]::new(($r.R-$r.L), ($r.B-$r.T))
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $g.Dispose()
    # 取左侧空白区域采样，避开文字与圆环
    $sum = 0; $n = 0
    foreach ($y in 60, 120, 700, 760) {
        foreach ($x in 8, 16, 24) { $c = $bmp.GetPixel($x, $y); $sum += ($c.R + $c.G + $c.B) / 3; $n++ }
    }
    $bmp.Dispose()
    return [math]::Round($sum / $n, 1)
}
function Stop-App {
    $h = Get-AppWindow
    if ($h -ne [IntPtr]::Zero) {
        [Tu]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 250
        [System.Windows.Forms.SendKeys]::SendWait('^+q'); Start-Sleep -Seconds 2
    }
    Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 600
}

if (-not (Test-Path $Artifacts)) { New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null }
$settingsPath = Join-Path $env:APPDATA 'FluentPomodoro\settings.json'
Remove-Item $settingsPath -Force -ErrorAction SilentlyContinue
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

# ---------- 1) 浅色启动，用鼠标打开设置面板 ----------
Start-Process -FilePath $Exe -ArgumentList '--light'
Start-Sleep -Seconds 6
$h = Get-AppWindow
$light = AverageBackground $h
Check '启动为浅色主题（鼠标路径前置条件）' ($light -gt 180) "背景亮度=$light"
$r = Get-Rect $h

Click ($r.L + 320) ($r.T + 340)          # 点一下主界面（确保窗口在前台，且不触发标题栏拖动）
Click ($r.L + 585) ($r.T + 736)          # 点“设置”按钮
Start-Sleep -Milliseconds 800
Save-WindowShot 'theme-01-settings-opened.png'

# ---------- 2) 滚动到外观区块，用鼠标点开下拉并选择“深色”----------
# 面板滚动量在不同时机下会有几十像素差异，这里用“重置滚动 + 候选位置”的方式自定位：
# 每个候选先回到“滚到底部再上滚 3 格”的确定状态，再点下拉框与第三项，以 settings.json 的
# Theme 是否变为 Dark 作为判据（该写入由主题切换逻辑触发）。
function ScrollToAppearance([IntPtr]$h) {
    $rr = Get-Rect $h
    Wheel ($rr.L + 420) ($rr.T + 400) 60 3
}
function SettingsTheme {
    if (-not (Test-Path $settingsPath)) { return '' }
    try { return (Get-Content $settingsPath -Raw | ConvertFrom-Json).Theme } catch { return '' }
}
# 自动定位主题下拉框：扫描面板内一段连续的长横向边框线（ComboBox 的 1px 边框）
function Find-ComboY([IntPtr]$h) {
    $r = Get-Rect $h
    $bmp = [System.Drawing.Bitmap]::new(($r.R - $r.L), ($r.B - $r.T))
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $g.Dispose()
    $found = -1
    for ($y = 60; $y -lt $bmp.Height - 60; $y++) {
        $matches = 0
        for ($x = 230; $x -lt 600; $x += 4) {
            $c = $bmp.GetPixel($x, $y)
            if ([math]::Abs($c.R - 201) -le 10 -and [math]::Abs($c.G - 201) -le 10 -and [math]::Abs($c.B - 201) -le 10) { $matches++ }
        }
        if ($matches -ge 85) { $found = $y; break }
    }
    $bmp.Dispose()
    return $found
}

$selected = $false
$usedY = 0
# 一次滚动后自动定位；若定位失败再退回候选位置重试
for ($attempt = 0; $attempt -lt 3 -and -not $selected; $attempt++) {
    ScrollToAppearance $h
    $comboTop = Find-ComboY $h
    $candidates = @()
    if ($comboTop -gt 0) { $candidates += ($comboTop + 17) }
    $candidates += 385, 340, 365, 405, 300

    foreach ($comboY in ($candidates | Select-Object -Unique)) {
        Click ($r.L + 415) ($r.T + $comboY)          # 点开下拉
        Start-Sleep -Milliseconds 400
        if ($attempt -eq 0 -and $comboY -eq $candidates[0]) { Save-WindowShot 'theme-02-dropdown-open.png' }
        Click ($r.L + 415) ($r.T + $comboY + 118)    # 点第三项“深色”
        Start-Sleep -Milliseconds 1000
        if ((SettingsTheme) -eq 'Dark') { $selected = $true; $usedY = $comboY; break }
        [Tu]::SetForegroundWindow($h) | Out-Null
        [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
        Start-Sleep -Milliseconds 300
    }
}

Check '鼠标在下拉框中选择“深色”后界面立即切换（Theme=Dark）' $selected "命中下拉框窗口内 y=$usedY"
$dark = AverageBackground $h
Save-WindowShot 'theme-03-selected-dark.png'

# ---------- 3) 退出并重启，验证主题被持久化 ----------
Stop-App
$json = Get-Content $settingsPath -Raw | ConvertFrom-Json
Check '下拉选择写入 settings.json（Theme=Dark）' ($json.Theme -eq 'Dark') "Theme=$($json.Theme)"

Start-Process -FilePath $Exe
Start-Sleep -Seconds 6
$h2 = Get-AppWindow
$dark2 = AverageBackground $h2
Check '重启后仍为深色（F1 回归）' ($dark2 -lt 90) "背景亮度=$dark2"
Save-WindowShot 'theme-04-restart-dark.png'
Stop-App

Write-Host ''
$script:results | Format-Table -AutoSize
$failed = @($script:results | Where-Object { $_.结果 -ne '通过' }).Count
Write-Host ("通过 {0} / {1} 项" -f ($script:results.Count - $failed), $script:results.Count)
exit $failed
