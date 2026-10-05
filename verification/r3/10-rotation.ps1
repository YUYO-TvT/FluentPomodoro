# 10-rotation.ps1 -- Feature 3: the periodic background rotation timer (5-minute interval)
. (Join-Path $PSScriptRoot 'lib3.ps1')
$assets = $script:AssetsDir

[void](Stop-AllApp); [void](Remove-ConfigFiles)
Set-BaseSettings -Override @{ ShowClock = $false; BackgroundFolder = $assets; BackgroundImagePath = ''
                             BackgroundRotateMinutes = 5; BackgroundRotateOnFocus = $false
                             BackgroundOpacity = 1.0; BackgroundUseImageAccent = $false } | Out-Null
$app = Start-App; $main = $app.Hwnd
Start-Sleep -Seconds 3
Check 'rotation test: main window present' ($main -ne [IntPtr]::Zero) ("hwnd={0}" -f $main)
Check 'rotation test: the focus timer is NOT running (rotation must be independent of the timer)' ((Get-Title $main) -match '^25:00') ("title='{0}'" -f (Get-Title $main))
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$first = Uia-Text $main 'TxtBgInfo'
Write-Host ("t=0s TxtBgInfo='{0}'" -f ($first -replace "`n",' | '))
Check 'rotation test: folder loaded with the 5-minute interval shown' `
      (($first -like '*文件夹内共 3 张*每 5 分钟轮换*') -and ($first -like '*当前：*')) ("TxtBgInfo='{0}'" -f ($first -replace "`n",' | '))

$sw = [Diagnostics.Stopwatch]::StartNew()
$changes = @()
$prev = $first
$lastT = 0.0
while ($sw.Elapsed.TotalSeconds -lt 400) {
  Start-Sleep -Seconds 10
  $now = Uia-Text $main 'TxtBgInfo'
  if ($now -ne $prev) {
    $changes += [pscustomobject]@{ T=[math]::Round($sw.Elapsed.TotalSeconds,1); Text=$now }
    Write-Host ("t={0:N1}s CHANGED -> '{1}'" -f $sw.Elapsed.TotalSeconds, ($now -replace "`n",' | '))
    $prev = $now
  }
  if ([math]::Floor($sw.Elapsed.TotalSeconds/30) -gt [math]::Floor($lastT/30)) {
    $lastT = $sw.Elapsed.TotalSeconds
    Write-Host ("t={0:N0}s current: {1}" -f $sw.Elapsed.TotalSeconds, ([regex]::Match($now,'当前：([^\n·]+)').Groups[1].Value.Trim()))
  }
}
Check 'rotation test: the background image rotated on the 5-minute timer' ($changes.Count -ge 1) `
      ("{0} change(s) observed; first at t={1}s" -f $changes.Count, $(if ($changes.Count) { $changes[0].T } else { '-' }))
Check 'rotation test: the rotation happened at ~5 minutes, not immediately and not never' `
      (($changes.Count -ge 1) -and ($changes[0].T -ge 280) -and ($changes[0].T -le 360)) `
      ("first change at t={0}s (timer interval 20s, target 300s, sampler period 10s)" -f $(if ($changes.Count) { $changes[0].T } else { '-' }))
foreach ($c in $changes) { Write-Host ("   change at t={0}s: {1}" -f $c.T, ($c.Text -replace "`n",' | ')) }
[void](Save-Shot -Name 'r3-h1-rotation-after.png' -Hwnd $main)
[void](Activate-App $main); Send-ForceQuit $main; [void](Wait-Exit -Pid2 $app.Pid -Sec 10)
Check 'rotation test: exits cleanly' ((Get-Process FluentPomodoro -ErrorAction SilentlyContinue) -eq $null) ("processes={0}" -f @(Get-Process FluentPomodoro -ErrorAction SilentlyContinue).Count)
[void](Stop-AllApp); [void](Remove-ConfigFiles)
[void](Summary)
