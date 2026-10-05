# 00-smoke.ps1 -- launch my own artifact, locate windows, validate capture path
. (Join-Path $PSScriptRoot 'lib3.ps1')

Write-Host "EXE   : $script:Exe"
Write-Host ("SHA256: {0}" -f (Get-FileHash $script:Exe -Algorithm SHA256).Hash)
Write-Host ("BYTES : {0}" -f (Get-Item $script:Exe).Length)
$dirFiles = @(Get-ChildItem (Split-Path $script:Exe) -File)
Check 'publish dir contains exactly one file' ($dirFiles.Count -eq 1) ("{0} file(s): {1}" -f $dirFiles.Count, ($dirFiles.Name -join ', '))

# app must not be running before we start (single-instance mutex)
Check 'no FluentPomodoro process before launch' (@(Get-Process FluentPomodoro -ErrorAction SilentlyContinue).Count -eq 0) `
      ("count={0}" -f @(Get-Process FluentPomodoro -ErrorAction SilentlyContinue).Count)

[void](Remove-ConfigFiles)
$app = Start-App
Check 'process alive after launch' (-not $app.Exited -and -not $app.Proc.HasExited) ("pid={0} HasExited={1}" -f $app.Pid, $app.Proc.HasExited)
Check 'owns a visible top-level window' ($app.Hwnd -ne [IntPtr]::Zero) ("hwnd={0}" -f $app.Hwnd)

$r = Get-Rect $app.Hwnd
Check 'window opens at 640x780' ($r.W -eq 640 -and $r.H -eq 780) ("{0}x{1} @ ({2},{3})" -f $r.W,$r.H,$r.X,$r.Y)
$t = Get-Title $app.Hwnd
Check 'title looks like <time> · 专注 · 微软风格番茄钟' ($t -match '^\d{1,2}:\d{2} · 专注 · 微软风格番茄钟$') ("title='{0}'" -f $t)

$vd = Get-VirtualDesktop
Write-Host ("virtual desktop = {0}x{1} @ ({2},{3})  monitor count={4}" -f $vd.W,$vd.H,$vd.X,$vd.Y, `
   ([System.Windows.Forms.Screen]::AllScreens.Count))

# capture path validation: PrintWindow vs screen
$bmp = Capture-Window -Hwnd $app.Hwnd
Write-Host ("PrintWindow bitmap = {0}x{1}" -f $bmp.Width, $bmp.Height)
$st = Get-BmpStats -Bmp $bmp -X 0 -Y 0 -W $bmp.Width -H $bmp.Height
Write-Host ("printwindow full-window stats: modal={0} distinct={1} lum={2}" -f $st.Modal, $st.Distinct, $st.Lum)
Check 'PrintWindow capture is not blank/dummy' ($st.Distinct -gt 5) ("distinct colours={0}, modal={1}" -f $st.Distinct, $st.Modal)
[void](Save-Shot -Name 'r3-00-launch.png' -Hwnd $app.Hwnd)
[void](Save-Bmp -Bmp $bmp -Name 'r3-00-printwindow.png')

# two windows: main + stats
[void](Send-CtrlKey -Hwnd $app.Hwnd -Vk 0x49)   # Ctrl+I
Start-Sleep -Milliseconds 1200
$stats = Get-StatsWindow -ProcId $app.Pid
Check 'Ctrl+I opens the 专注统计 window' ($stats -ne [IntPtr]::Zero) ("stats hwnd={0}" -f $stats)
$all = Get-WindowsForPid -ProcId $app.Pid
Write-Host "visible top-level windows owned by pid:"
foreach ($w in $all) { Write-Host ("   hwnd={0,-10} {1,5}x{2,-5} @({3},{4})  title='{5}'  class='{6}'" -f $w.Hwnd,$w.W,$w.H,$w.X,$w.Y,$w.Title,$w.Class) }
Check 'main window still largest visible window' ((Get-MainWindow -ProcId $app.Pid) -eq $app.Hwnd) ("main={0}" -f (Get-MainWindow -ProcId $app.Pid))

[void](Save-Shot -Name 'r3-00-stats.png' -Hwnd $stats)

# clean exit
[void](Activate-App $app.Hwnd)
Send-ForceQuit $app.Hwnd
$ok = Wait-Exit -Pid2 $app.Pid -Sec 10
Check 'exits cleanly via Ctrl+Shift+Q' $ok ("HasExited={0}" -f (-not (Get-Process -Id $app.Pid -ErrorAction SilentlyContinue)))
[void](Stop-AllApp)
Check 'no leftover FluentPomodoro process' (@(Get-Process FluentPomodoro -ErrorAction SilentlyContinue).Count -eq 0) ("count={0}" -f @(Get-Process FluentPomodoro -ErrorAction SilentlyContinue).Count)
[void](Remove-ConfigFiles)

[void](Summary)
