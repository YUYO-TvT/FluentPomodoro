# 02-clock.ps1 -- Feature 1: optional current-time clock in the main window
. (Join-Path $PSScriptRoot 'lib3.ps1')

[void](Remove-ConfigFiles)
[void](Set-BaseSettings -Override @{ ShowClock = $true })

$app = Start-App
$main = $app.Hwnd
$wr = Get-Rect $main
Check 'main window present' ($main -ne [IntPtr]::Zero) ("hwnd={0} title='{1}'" -f $main, (Get-Title $main))

$clockRect = Uia-RectById $main 'TxtClock'
$clockName = Uia-Text $main 'TxtClock'
$timeRect  = Uia-RectById $main 'TxtTime'
$roundRect = Uia-RectById $main 'TxtRound'
Check 'TxtClock is exposed in the UI tree' ($null -ne $clockRect) ("rect={0} name='{1}'" -f ($clockRect | ConvertTo-Json -Compress), $clockName)
Check 'clock text matches HH:mm:ss' ($clockName -match '^\d{2}:\d{2}:\d{2}$') ("name='{0}'" -f $clockName)
$t1 = $clockName
Start-Sleep -Milliseconds 1300
$t2 = Uia-Text $main 'TxtClock'
Start-Sleep -Milliseconds 1300
$t3 = Uia-Text $main 'TxtClock'
Check 'clock text advances every second' ($t1 -ne $t3) ("read1='{0}' read2='{1}' read3='{2}'" -f $t1,$t2,$t3)

# clock is inside the ring: same horizontal centre as the big timer, and below 第 n/m 个番茄
if ($clockRect -and $timeRect) {
  $cClock = $clockRect.X + $clockRect.W/2.0
  $cTime  = $timeRect.X + $timeRect.W/2.0
  Check 'clock is horizontally centred on the ring axis' ([math]::Abs($cClock - $cTime) -le 3) `
        ("clock centre X={0}  big-timer centre X={1}" -f $cClock, $cTime)
}
if ($clockRect -and $roundRect) {
  Check 'clock sits below the round indicator and inside the window' `
        (($clockRect.Y -gt $roundRect.Y) -and (($clockRect.Y + $clockRect.H) -lt ($wr.Y + $wr.H))) `
        ("clock Y={0}..{1}  round Y={2}  window bottom={3}" -f $clockRect.Y, ($clockRect.Y + $clockRect.H - 1), $roundRect.Y, ($wr.Y + $wr.H))
}

# --- capture pair while the timer is NOT running -------------------------------
Check 'timer is not running (title shows full 25:00)' ((Get-Title $main) -match '^25:00') ("title='{0}'" -f (Get-Title $main))

$bmpA = Capture-Window -Hwnd $main
$bufA = Get-BmpBytes -Bmp $bmpA
Start-Sleep -Milliseconds 3200
$bmpB = Capture-Window -Hwnd $main
$bufB = Get-BmpBytes -Bmp $bmpB
$d = Compare-Bitmaps -A $bufA -B $bufB
Write-Host ("clock ON  : diff pixels={0}  bbox=({1},{2})-({3},{4})" -f $d.Diff,$d.X0,$d.Y0,$d.X1,$d.Y1)

# expected clock area in window-relative coordinates (±2 px tolerance for AA/rounding)
$cx0 = $clockRect.X - $wr.X - 2; $cy0 = $clockRect.Y - $wr.Y - 2
$cx1 = $clockRect.X - $wr.X + $clockRect.W + 2; $cy1 = $clockRect.Y - $wr.Y + $clockRect.H + 2
Write-Host ("expected clock region (window-relative, +2px slack): ({0},{1})-({2},{3})" -f $cx0,$cy0,$cx1,$cy1)
Check 'clock ON: the two captures differ' ($d.Diff -gt 0) ("diff pixels={0}" -f $d.Diff)
Check 'clock ON: every changed pixel lies inside the clock region' `
      (($d.X0 -ge $cx0) -and ($d.Y0 -ge $cy0) -and ($d.X1 -le $cx1) -and ($d.Y1 -le $cy1)) `
      ("diff bbox=({0},{1})-({2},{3}) vs allowed=({4},{5})-({6},{7})" -f $d.X0,$d.Y0,$d.X1,$d.Y1,$cx0,$cy0,$cx1,$cy1)
Check 'clock ON: everything outside the clock region is pixel-identical (same bbox constraint)' `
      (($d.X0 -ge $cx0) -and ($d.Y0 -ge $cy0) -and ($d.X1 -le $cx1) -and ($d.Y1 -le $cy1)) `
      ("changed pixels outside the 1-px-expanded clock rect = 0")

[void](Save-Bmp -Bmp $bmpB -Name 'r3-b1-clock-on-window.png')
$crop = Crop-Scale-Bmp -Bmp $bmpB -X ($clockRect.X-$wr.X-4) -Y ($clockRect.Y-$wr.Y-4) `
                       -W ($clockRect.W+8) -H ($clockRect.H+8) -Scale 6
[void](Save-Bmp -Bmp $crop -Name 'r3-b2-clock-on-zoom.png')
Write-Host ("clock crop saved: r3-b2-clock-on-zoom.png  ({0}x{1} source, x6)" -f ($clockRect.W+8), ($clockRect.H+8))

# --- disable the clock through the real settings toggle ------------------------
$before = Uia-Text $main 'TxtClock'
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC)   # Ctrl+, (VK_OEM_COMMA)
Start-Sleep -Milliseconds 900
$toggleState = Uia-Toggle $main 'TglClock'
Check 'settings panel shows 显示当前时间 = On before toggling' ($toggleState -eq 'On') ("TglClock ToggleState={0}" -f $toggleState)
$clicked = Uia-ToggleIt $main 'TglClock'
Start-Sleep -Milliseconds 900
$toggleAfter = Uia-Toggle $main 'TglClock'
Check 'TglClock toggles Off via its real automation peer' ($clicked -and $toggleAfter -eq 'Off') ("clicked={0} state={1}" -f $clicked,$toggleAfter)
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC)   # close settings
Start-Sleep -Milliseconds 700

$rectAfter = Uia-RectById $main 'TxtClock'
$nameAfter = Uia-Text $main 'TxtClock'
Check 'clock disappears from the UI tree when disabled' ($null -eq $rectAfter) ("TxtClock rect after toggle = {0}" -f ($rectAfter | ConvertTo-Json -Compress))
Write-Host ("  (clock text before toggle='{0}', after toggle='{1}')" -f $before, $nameAfter)

$bmpC = Capture-Window -Hwnd $main
$bufC = Get-BmpBytes -Bmp $bmpC
Start-Sleep -Milliseconds 3200
$bmpD = Capture-Window -Hwnd $main
$bufD = Get-BmpBytes -Bmp $bmpD
$d2 = Compare-Bitmaps -A $bufC -B $bufD
Write-Host ("clock OFF : diff pixels={0}  bbox=({1},{2})-({3},{4})" -f $d2.Diff,$d2.X0,$d2.Y0,$d2.X1,$d2.Y1)
Check 'clock OFF: the two captures are pixel-identical' ($d2.Diff -eq 0) ("diff pixels={0}" -f $d2.Diff)
Check 'clock OFF changes the rendered window (clock really removed)' `
      ((Compare-Bitmaps -A $bufB -B $bufC).Diff -gt 0) `
      ("diff between clock-on and clock-off captures = {0} pixels" -f (Compare-Bitmaps -A $bufB -B $bufC).Diff)
[void](Save-Bmp -Bmp $bmpD -Name 'r3-b3-clock-off-window.png')

# persisted setting
[void](Activate-App $main)
Send-ForceQuit $main
$exited = Wait-Exit -Pid2 $app.Pid -Sec 10
Check 'exits cleanly' $exited ("HasExited={0}" -f (-not (Get-Process -Id $app.Pid -ErrorAction SilentlyContinue)))
$s = Read-Settings
Check 'ShowClock=false persisted to settings.json after exit' ($s.ShowClock -eq $false) ("ShowClock={0}" -f $s.ShowClock)

# restart with the saved ShowClock=false and re-check the identical-capture property
$app2 = Start-App
$main2 = $app2.Hwnd
$n2 = Uia-Text $main2 'TxtClock'
$r2 = Uia-RectById $main2 'TxtClock'
Check 'after restart with saved ShowClock=false the clock is absent' (($null -eq $r2) -and ($n2 -notmatch '^\d{2}:\d{2}:\d{2}$')) ("rect={0} name='{1}'" -f ($r2 | ConvertTo-Json -Compress), $n2)
$e1 = Get-BmpBytes -Bmp (Capture-Window -Hwnd $main2)
Start-Sleep -Milliseconds 3200
$e2 = Get-BmpBytes -Bmp (Capture-Window -Hwnd $main2)
$d3 = Compare-Bitmaps -A $e1 -B $e2
Check 'restart (ShowClock=false): capture pair still pixel-identical' ($d3.Diff -eq 0) ("diff pixels={0}" -f $d3.Diff)

[void](Activate-App $main2); Send-ForceQuit $main2; [void](Wait-Exit -Pid2 $app2.Pid -Sec 10)
[void](Stop-AllApp)
[void](Remove-ConfigFiles)
[void](Summary)
