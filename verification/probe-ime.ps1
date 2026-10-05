# Probe: identify the extra top-level window and whether bare-letter shortcuts are swallowed by the IME.
param(
    [string]$Exe = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verify-dist\FluentPomodoro.exe',
    [string]$OutDir = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\verification'
)
. (Join-Path $OutDir 'lib.ps1')
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class Wins {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public static List<string> ForPid(uint want) {
    var list = new List<string>();
    EnumWindows((h, l) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid == want) {
        var c = new StringBuilder(256); GetClassNameW(h, c, 256);
        var t = new StringBuilder(256); GetWindowTextW(h, t, 256);
        list.Add("hwnd=0x" + h.ToInt64().ToString("X") + " class='" + c + "' visible=" + IsWindowVisible(h) + " title='" + t + "'");
      }
      return true;
    }, IntPtr.Zero);
    return list;
  }
  [DllImport("user32.dll")] public static extern IntPtr GetKeyboardLayout(uint tid);
}
"@

function Show-Windows([string]$tag, [int]$p) {
    Write-Host "  [$tag] top-level windows of pid ${p}:"
    [Wins]::ForPid([uint32]$p) | ForEach-Object { "      $_" }
}
function Post-Key([IntPtr]$h, [int]$vk) {
    [void][VU]::PostMessage($h, 0x0100, [IntPtr]$vk, [IntPtr](0x00000001 -bor ($vk -shl 16)))
    Start-Sleep -Milliseconds 60
    [void][VU]::PostMessage($h, 0x0101, [IntPtr]$vk, [IntPtr](0xC0000001 -bor ($vk -shl 16)))
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
function Uia-ById($root, [string]$id) {
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id)
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
}

Write-Host "=== keyboard layout (current thread, 0x0804=zh-CN, 0x0409=en-US) ==="
$layout = [Wins]::GetKeyboardLayout(0)
Write-Host ("  HKL=0x{0:X8} langid=0x{1:X4}" -f $layout.ToInt64(), ($layout.ToInt64() -band 0xFFFF))

Assert-NoAppRunning
Write-Settings @{ FocusMinutes = 1; ShortBreakMinutes = 1; LongBreakMinutes = 1; LongBreakInterval = 4
                 AutoStartNext = $false; AutoBigScreenOnFocus = $false; AlwaysOnTop = $false; UseMicaBackdrop = $false
                 HasWindowBounds = $false }
$proc = Start-Process -FilePath $Exe -PassThru
$h = Wait-AppWindow 20
Start-Sleep -Seconds 3
$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
Show-Windows 'after launch' $proc.Id

Write-Host "=== SendKeys 's' (bare letter) ==="
[void](Focus-App)
[System.Windows.Forms.SendKeys]::SendWait('s')
Start-Sleep -Milliseconds 1000
Write-Host "  title='$(Get-Title $h)'"
Show-Windows 'after SendKeys s' $proc.Id

Write-Host "=== SendKeys 'r' and 'f' (bare letters) ==="
[System.Windows.Forms.SendKeys]::SendWait('r'); Start-Sleep -Milliseconds 600
[System.Windows.Forms.SendKeys]::SendWait('f'); Start-Sleep -Milliseconds 1200
$r = Get-Rect $h
Write-Host "  after r/f: title='$(Get-Title $h)' rect=$(Format-Rect $h)"
Show-Windows 'after SendKeys r+f' $proc.Id

Write-Host "=== PostMessage VK_F (0x46) cycle big screen ==="
Post-Key $h 0x46
Start-Sleep -Milliseconds 1200
Write-Host "  after PostMessage F: title='$(Get-Title $h)' rect=$(Format-Rect $h)"
Post-Key $h 0x46
Start-Sleep -Milliseconds 1200
Write-Host "  after 2nd PostMessage F: rect=$(Format-Rect $h)"
Post-Key $h 0x46
Start-Sleep -Milliseconds 1200
Write-Host "  after 3rd PostMessage F: rect=$(Format-Rect $h)"

Write-Host "=== PostMessage VK_S (0x53) ==="
Post-Key $h 0x53
Start-Sleep -Milliseconds 900
Write-Host "  after PostMessage S: title='$(Get-Title $h)'"
Write-Host "=== PostMessage VK_R (0x52) ==="
[void][VU]::PostMessage($h, 0x0112, [IntPtr]0xF120, [IntPtr]::Zero)
Start-Sleep -Milliseconds 500
Post-Key $h 0x52
Start-Sleep -Milliseconds 900
Write-Host "  after PostMessage R: title='$(Get-Title $h)'"
Send-Keys '^+q' 1200
$deadline = (Get-Date).AddSeconds(10)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
Assert-NoAppRunning
