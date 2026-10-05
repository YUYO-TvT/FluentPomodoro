# probe-windows.ps1 -- diagnose window enumeration for the app process
. (Join-Path $PSScriptRoot 'lib3.ps1')

[void](Stop-AllApp)
$p = Start-Process -FilePath $script:Exe -PassThru
Write-Host ("started pid={0}" -f $p.Id)
Start-Sleep -Seconds 8
Write-Host ("HasExited={0}" -f $p.HasExited)
if ($p.HasExited) { Write-Host ("exit code={0}" -f $p.ExitCode); exit 1 }

Write-Host ("MainWindowHandle from .NET = {0}" -f $p.MainWindowHandle)
Write-Host ("Threads={0}  Responding={1}" -f $p.Threads.Count, $p.Responding)

# raw enumeration: ALL top-level windows of that pid, visible or not
$script:raw = New-Object System.Collections.ArrayList
$cb = [R3.EnumWindowsProc]{
  param($h, $l)
  $owner = 0
  [void][R3.Native]::GetWindowThreadProcessId($h, [ref]$owner)
  if ($owner -eq $p.Id) {
    $r = New-Object R3.RECT
    [void][R3.Native]::GetWindowRect($h, [ref]$r)
    $sb = New-Object System.Text.StringBuilder 512
    [void][R3.Native]::GetWindowText($h, $sb, 512)
    $cn = New-Object System.Text.StringBuilder 256
    [void][R3.Native]::GetClassName($h, $cn, 256)
    [void]$script:raw.Add([pscustomobject]@{
      Hwnd=$h; Title=$sb.ToString(); Class=$cn.ToString()
      Vis=[R3.Native]::IsWindowVisible($h); W=($r.Right-$r.Left); H=($r.Bottom-$r.Top)
      X=$r.Left; Y=$r.Top })
  }
  return $true
}
[void][R3.Native]::EnumWindows($cb, [IntPtr]::Zero)
Write-Host ("raw top-level windows for pid {0}: {1}" -f $p.Id, @($script:raw).Count)
foreach ($w in $script:raw) {
  Write-Host ("   hwnd={0,-10} vis={1,-6} {2,5}x{3,-5} @({4},{5}) title='{6}' class='{7}'" -f $w.Hwnd,$w.Vis,$w.W,$w.H,$w.X,$w.Y,$w.Title,$w.Class)
}
Write-Host "--- via Get-WindowsForPid (visible only) ---"
foreach ($w in (Get-WindowsForPid -ProcId $p.Id)) {
  Write-Host ("   hwnd={0,-10} {1,5}x{2,-5} title='{3}'" -f $w.Hwnd,$w.W,$w.H,$w.Title)
}
Write-Host ("Get-MainWindow = {0}" -f (Get-MainWindow -ProcId $p.Id))
Write-Host ("Get-WindowByTitle('') = {0}" -f (Get-WindowByTitle -ProcId $p.Id))
[void](Stop-AllApp)
