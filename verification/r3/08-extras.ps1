# 08-extras.ps1 -- (B) clock diff using real screen captures + (probe) non-tick BackgroundOpacity
. (Join-Path $PSScriptRoot 'lib3.ps1')

$redImg = Join-Path $script:AssetsDir 'bg-red.png'

function Ensure-SettingsClosed([IntPtr]$Hwnd) {
  for ($i=0; $i -lt 3; $i++) {
    if ($null -eq (Uia-ById $Hwnd 'SldBgOpacity')) { return $true }
    [void](Activate-App $Hwnd); Send-VKey -Vk 0x1B; Start-Sleep -Milliseconds 900
  }
  return ($null -eq (Uia-ById $Hwnd 'SldBgOpacity'))
}

# =========================================================================================
# Part 1 -- clock: two SCREEN captures while the timer is not running
# =========================================================================================
Write-Host '=== Part 1: clock diff from real screen captures (CopyFromScreen) ==='
[void](Stop-AllApp); [void](Remove-ConfigFiles)
Set-BaseSettings -Override @{ ShowClock = $true; UseMicaBackdrop = $false } | Out-Null
$app = Start-App; $main = $app.Hwnd
Start-Sleep -Seconds 3
$wr = Get-Rect $main
$clockRect = Uia-RectById $main 'TxtClock'
Check 'clock is present with ShowClock=true' ($null -ne $clockRect) ("TxtClock='{0}' rect={1}" -f (Uia-Text $main 'TxtClock'), ($clockRect | ConvertTo-Json -Compress))
Check 'the timer is not running (title shows the full 25:00)' ((Get-Title $main) -match '^25:00') ("title='{0}'" -f (Get-Title $main))
# park the mouse outside the window so the cursor cannot appear in the capture
[void][R3.Native]::SetCursorPos(1900, 1070)
Start-Sleep -Milliseconds 800
$bmpA = Capture-Window -Hwnd $main -FromScreen
$bufA = Get-BmpBytes -Bmp $bmpA
Start-Sleep -Milliseconds 3200
$bmpB = Capture-Window -Hwnd $main -FromScreen
$bufB = Get-BmpBytes -Bmp $bmpB
$d = Compare-Bitmaps -A $bufA -B $bufB
$cx0 = $clockRect.X - $wr.X - 2; $cy0 = $clockRect.Y - $wr.Y - 2
$cx1 = $clockRect.X - $wr.X + $clockRect.W + 2; $cy1 = $clockRect.Y - $wr.Y + $clockRect.H + 2
Write-Host ("screen captures: diff pixels={0} bbox=({1},{2})-({3},{4}); clock region (window-relative) = ({5},{6})-({7},{8})" -f `
  $d.Diff,$d.X0,$d.Y0,$d.X1,$d.Y1,$cx0,$cy0,$cx1,$cy1)
Check 'screen-capture pair with the clock ON differs' ($d.Diff -gt 0) ("diff pixels={0}" -f $d.Diff)
Check 'screen captures: every changed pixel lies inside the clock region' `
      (($d.X0 -ge $cx0) -and ($d.Y0 -ge $cy0) -and ($d.X1 -le $cx1) -and ($d.Y1 -le $cy1)) `
      ("changed bbox=({0},{1})-({2},{3}) inside allowed=({4},{5})-({6},{7})" -f $d.X0,$d.Y0,$d.X1,$d.Y1,$cx0,$cy0,$cx1,$cy1)

# disable the clock through the settings toggle and repeat with screen captures
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 900
[void](Uia-ToggleIt $main 'TglClock'); Start-Sleep -Milliseconds 900
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Milliseconds 900
Check 'the clock is gone from the UI tree after disabling' ($null -eq (Uia-RectById $main 'TxtClock')) ("TxtClock rect={0}" -f (Uia-RectById $main 'TxtClock'))
[void][R3.Native]::SetCursorPos(1900, 1070)
Start-Sleep -Milliseconds 800
$cA = Get-BmpBytes -Bmp (Capture-Window -Hwnd $main -FromScreen)
Start-Sleep -Milliseconds 3200
$cB = Get-BmpBytes -Bmp (Capture-Window -Hwnd $main -FromScreen)
$d2 = Compare-Bitmaps -A $cA -B $cB
Check 'screen-capture pair with the clock OFF is pixel-identical' ($d2.Diff -eq 0) ("diff pixels={0} bbox=({1},{2})-({3},{4})" -f $d2.Diff,$d2.X0,$d2.Y0,$d2.X1,$d2.Y1)
[void](Activate-App $main); Send-ForceQuit $main; [void](Wait-Exit -Pid2 $app.Pid -Sec 10)

# =========================================================================================
# Part 2 -- probe: a non-tick BackgroundOpacity value written by hand
# =========================================================================================
Write-Host ''
Write-Host '=== Part 2: probe BackgroundOpacity=0.42 (not a multiple of the slider tick 0.05) ==='
[void](Stop-AllApp); [void](Remove-ConfigFiles)
Set-BaseSettings -Override @{ ShowClock = $false; BackgroundImagePath = $redImg; BackgroundOpacity = 0.42 } | Out-Null
Write-Host ("file before launch: BackgroundOpacity={0}" -f (Read-Settings).BackgroundOpacity)
$app = Start-App; $main = $app.Hwnd
Start-Sleep -Seconds 3
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$lbl = Uia-Text $main 'LblBgOpacity'
$sliderVal = Uia-Range $main 'SldBgOpacity'
Write-Host ("in-session: LblBgOpacity='{0}'  SldBgOpacity={1}" -f $lbl,$sliderVal)
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Milliseconds 700
[void](Activate-App $main); Send-ForceQuit $main; [void](Wait-Exit -Pid2 $app.Pid -Sec 10)
$after = (Read-Settings).BackgroundOpacity
Write-Host ("file after exit : BackgroundOpacity={0}" -f $after)
Check 'a hand-written non-tick opacity is not silently changed on a load/exit round-trip' ([double]$after -eq 0.42) `
      ("0.42 -> slider shows '{0}' (value {1}) -> file {2}" -f $lbl,$sliderVal,$after)
Check 'the opacity label is close to the requested value' (([double]($lbl -replace '%','')) -ge 40 -and ([double]($lbl -replace '%','')) -le 42) ("label='{0}'" -f $lbl)

[void](Stop-AllApp)
[void](Remove-ConfigFiles)
[void](Summary)
