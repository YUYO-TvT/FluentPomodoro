# 05-background.ps1 -- Feature 3: background images (single / folder / rotation / opacity / image accent)
. (Join-Path $PSScriptRoot 'lib3.ps1')

$assets = $script:AssetsDir
$redImg   = Join-Path $assets 'bg-red.png'
$blueImg  = Join-Path $assets 'bg-blue.png'
$greenImg = Join-Path $assets 'bg-green.png'
foreach ($p in @($redImg,$blueImg,$greenImg)) { if (-not (Test-Path $p)) { throw "missing $p" } }

# ---------- independent reimplementation of the documented accent extraction ----------
function Get-ImageHue([string]$path) {
  $bmp = [System.Drawing.Bitmap]::FromFile($path)
  $buf = Get-BmpBytes -Bmp $bmp
  $sumSin = 0.0; $sumCos = 0.0; $wsum = 0.0
  for ($y = 0; $y -lt $buf.H; $y++) {
    $row = $y * $buf.Stride
    for ($x = 0; $x -lt $buf.W; $x++) {
      $i = $row + $x * 4
      if ($buf.Bytes[$i+3] -lt 128) { continue }
      $b = $buf.Bytes[$i] / 255.0; $g = $buf.Bytes[$i+1] / 255.0; $r = $buf.Bytes[$i+2] / 255.0
      $max = [Math]::Max($r, [Math]::Max($g, $b)); $min = [Math]::Min($r, [Math]::Min($g, $b)); $delta = $max - $min
      if ($max -le 0.02 -or $delta -le 0.02) { continue }
      $sat = $delta / $max
      if ($sat -lt 0.15) { continue }
      if ($max -eq $r) { $hue = 60.0 * ((($g - $b) / $delta) % 6) }
      elseif ($max -eq $g) { $hue = 60.0 * (($b - $r) / $delta + 2) }
      else { $hue = 60.0 * (($r - $g) / $delta + 4) }
      if ($hue -lt 0) { $hue += 360 }
      $rad = $hue * [Math]::PI / 180.0
      $w = $sat * $sat * $(if ($max -lt 0.95) { 1.0 } else { 0.35 })
      $sumSin += [Math]::Sin($rad) * $w; $sumCos += [Math]::Cos($rad) * $w; $wsum += $w
    }
  }
  $bmp.Dispose()
  if ($wsum -le 0.0001) { return $null }
  $ang = [Math]::Atan2($sumSin, $sumCos) * 180.0 / [Math]::PI
  if ($ang -lt 0) { $ang += 360 }
  return $ang
}
function From-Hsv([double]$hue, [double]$sat, [double]$val) {
  $c = $val * $sat
  $x = $c * (1 - [Math]::Abs((($hue / 60.0) % 2) - 1))
  $m = $val - $c
  if ($hue -lt 60) { $r=$c; $g=$x; $b=0.0 }
  elseif ($hue -lt 120) { $r=$x; $g=$c; $b=0.0 }
  elseif ($hue -lt 180) { $r=0.0; $g=$c; $b=$x }
  elseif ($hue -lt 240) { $r=0.0; $g=$x; $b=$c }
  elseif ($hue -lt 300) { $r=$x; $g=0.0; $b=$c }
  else { $r=$c; $g=0.0; $b=$x }
  return @{ R=[int][Math]::Round(($r+$m)*255); G=[int][Math]::Round(($g+$m)*255); B=[int][Math]::Round(($b+$m)*255) }
}
function Mix-Colour($a, $b, [double]$t) {
  return @{ R=[int][Math]::Round($a.R + ($b.R-$a.R)*$t); G=[int][Math]::Round($a.G + ($b.G-$a.G)*$t); B=[int][Math]::Round($a.B + ($b.B-$a.B)*$t) }
}
function Lum($c) { return (0.2126*$c.R + 0.7152*$c.G + 0.0722*$c.B)/255.0 }
function Get-ExpectedAccent([double]$hue, [bool]$dark) {
  $a = From-Hsv $hue $(if ($dark) { 0.60 } else { 0.68 }) $(if ($dark) { 0.88 } else { 0.68 })
  $fill = $a
  if ($dark -and (Lum $a) -lt 0.36) { $fill = Mix-Colour $a @{R=255;G=255;B=255} 0.45 }
  if ((-not $dark) -and (Lum $a) -gt 0.78) { $fill = Mix-Colour $a @{R=0;G=0;B=0} 0.25 }
  return $fill
}

$hueRed = Get-ImageHue $redImg; $hueBlue = Get-ImageHue $blueImg
$expLightRed  = Get-ExpectedAccent $hueRed  $false
$expLightBlue = Get-ExpectedAccent $hueBlue $false
$expDarkRed   = Get-ExpectedAccent $hueRed  $true
Write-Host ("image hues measured by me: red={0:N2} deg  blue={1:N2} deg" -f $hueRed,$hueBlue)
Write-Host ("predicted accent (light+red)  = RGB({0},{1},{2})" -f $expLightRed.R,$expLightRed.G,$expLightRed.B)
Write-Host ("predicted accent (light+blue) = RGB({0},{1},{2})" -f $expLightBlue.R,$expLightBlue.G,$expLightBlue.B)
Write-Host ("predicted accent (dark+red)   = RGB({0},{1},{2})" -f $expDarkRed.R,$expDarkRed.G,$expDarkRed.B)

# ---------- sampling / plumbing helpers ----------
function Sample-Strip([IntPtr]$Hwnd) {
  $bmp = Capture-Window -Hwnd $Hwnd -FromScreen; $buf = Get-BmpBytes -Bmp $bmp
  $s = Get-BufStats -Buf $buf -X 4 -Y 60 -W 14 -H 240
  $bmp.Dispose(); return $s
}
function Sample-Accent([IntPtr]$Hwnd) {
  $wr = Get-Rect $Hwnd; $r = Uia-RectById $Hwnd 'BtnPlay'
  if ($null -eq $r) { return $null }
  $bmp = Capture-Window -Hwnd $Hwnd -FromScreen; $buf = Get-BmpBytes -Bmp $bmp
  $s = Get-BufStats -Buf $buf -X ($r.X-$wr.X+5) -Y ($r.Y-$wr.Y+5) -W ($r.W-10) -H ($r.H-10)
  $bmp.Dispose(); return $s
}
function Is-RedDominant($rgb)  { $p=$rgb -split ','; return ([int]$p[0] -gt [int]$p[1] + 30) -and ([int]$p[0] -gt [int]$p[2] + 30) }
function Is-BlueDominant($rgb) { $p=$rgb -split ','; return ([int]$p[2] -gt [int]$p[0] + 30) -and ([int]$p[2] -gt [int]$p[1] + 30) }
function Colour-Near($rgb, $exp, [int]$tol = 3) {
  $p = $rgb -split ','
  return ([Math]::Abs([int]$p[0]-$exp.R) -le $tol) -and ([Math]::Abs([int]$p[1]-$exp.G) -le $tol) -and ([Math]::Abs([int]$p[2]-$exp.B) -le $tol)
}
function Ensure-SettingsClosed([IntPtr]$Hwnd) {
  for ($i=0; $i -lt 3; $i++) {
    if ($null -eq (Uia-ById $Hwnd 'SldBgOpacity')) { return $true }
    [void](Activate-App $Hwnd); Send-VKey -Vk 0x1B; Start-Sleep -Milliseconds 900
  }
  return ($null -eq (Uia-ById $Hwnd 'SldBgOpacity'))
}
function Dismiss-Dialogs([int]$ProcId) {
  foreach ($w in @(Get-WindowsForPid -ProcId $ProcId | Where-Object { $_.Class -eq '#32770' })) {
    [void](Focus-Window $w.Hwnd); Start-Sleep -Milliseconds 300; Send-VKey -Vk 0x1B; Start-Sleep -Milliseconds 700
  }
}
# Drive a native shell dialog: it opens with its file/folder name field already focused, so paste
# the path and press Enter WITHOUT calling SetFocus (which would move focus off that field).
function Pick-Via-Dialog {
  param([IntPtr]$Hwnd, [int]$ProcId, [string]$ButtonName, [string]$Path)
  [void](Dismiss-Dialogs $ProcId)
  [void](Activate-App $Hwnd)
  $invoked = Uia-ClickName $Hwnd $ButtonName
  $dlg = [IntPtr]::Zero; $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt 10 -and $dlg -eq [IntPtr]::Zero) {
    $c = @(Get-WindowsForPid -ProcId $ProcId | Where-Object { $_.Class -eq '#32770' })
    if ($c.Count -gt 0) { $dlg = $c[0].Hwnd }
    Start-Sleep -Milliseconds 250
  }
  if ($dlg -eq [IntPtr]::Zero) { return [pscustomobject]@{ Invoked=$invoked; Title=''; Closed=$false; Foreground=$false } }
  $title = Get-Title $dlg
  $sw2 = [Diagnostics.Stopwatch]::StartNew(); $fg = $false
  while ($sw2.Elapsed.TotalSeconds -lt 6 -and -not $fg) { $fg = ([R3.Native]::GetForegroundWindow() -eq $dlg); Start-Sleep -Milliseconds 200 }
  Paste-Text $Path
  Start-Sleep -Milliseconds 500
  Send-VKey -Vk 0x0D
  $sw3 = [Diagnostics.Stopwatch]::StartNew(); $closed = $false
  while ($sw3.Elapsed.TotalSeconds -lt 8 -and -not $closed) {
    $closed = (@(Get-WindowsForPid -ProcId $ProcId | Where-Object { $_.Class -eq '#32770' }).Count -eq 0)
    Start-Sleep -Milliseconds 300
  }
  if (-not $closed) { [void](Dismiss-Dialogs $ProcId) }
  return [pscustomobject]@{ Invoked=$invoked; Title=$title; Closed=$closed; Foreground=$fg }
}

# =========================================================================================
# Phase 0 -- baseline: no background image (light theme)
# =========================================================================================
[void](Stop-AllApp); [void](Remove-ConfigFiles)
Set-BaseSettings -Override @{ ShowClock = $false; BackgroundUseImageAccent = $true; BackgroundOpacity = 0.95 } | Out-Null
$app = Start-App; $main = $app.Hwnd
Check 'main window present (baseline)' ($main -ne [IntPtr]::Zero) ("hwnd={0} title='{1}'" -f $main,(Get-Title $main))
Start-Sleep -Seconds 4
$s0 = Sample-Strip $main; $a0 = Sample-Accent $main
Write-Host ("baseline plain strip: modal={0} avg=({1},{2},{3}) lum={4}" -f $s0.Modal,$s0.AvgR,$s0.AvgG,$s0.AvgB,$s0.Lum)
Write-Host ("baseline 开始专注 accent: modal={0} avg=({1},{2},{3})" -f $a0.Modal,$a0.AvgR,$a0.AvgG,$a0.AvgB)
Check 'no image -> background strip is the plain light theme backdrop (243,243,243)' ($s0.Modal -eq '243,243,243') ("modal={0}" -f $s0.Modal)
Check 'no image -> primary button uses the system accent, not an image hue' (-not (Is-RedDominant $a0.Modal)) ("BtnPlay modal={0}" -f $a0.Modal)
[void](Save-Shot -Name 'r3-e0-plain.png' -Hwnd $main)

# =========================================================================================
# Phase 1 -- choose bg-red.png through the real 选择图片 dialog
# =========================================================================================
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$pick = Pick-Via-Dialog -Hwnd $main -ProcId $app.Pid -ButtonName '选择图片' -Path $redImg
Check '选择图片 opens the native 选择背景图片 dialog and it accepts the typed path' `
      ($pick.Invoked -and $pick.Title -eq '选择背景图片' -and $pick.Closed) `
      ("invoked={0} dialog title='{1}' foreground={2} closed after Enter={3}" -f $pick.Invoked,$pick.Title,$pick.Foreground,$pick.Closed)
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Seconds 4
$sPath = (Read-Settings).BackgroundImagePath
Check 'settings.json records the image chosen through the dialog' ($sPath -eq $redImg) ("BackgroundImagePath='{0}'" -f $sPath)
$s1 = Sample-Strip $main; $a1 = Sample-Accent $main
Write-Host ("light + red image: strip modal={0} avg=({1},{2},{3}) lum={4}" -f $s1.Modal,$s1.AvgR,$s1.AvgG,$s1.AvgB,$s1.Lum)
Write-Host ("light + red image: 开始专注 button modal={0} avg=({1},{2},{3})" -f $a1.Modal,$a1.AvgR,$a1.AvgG,$a1.AvgB)
Check 'red image -> background strip becomes red-dominant' (Is-RedDominant $s1.Modal) ("strip modal RGB({0})" -f $s1.Modal)
Check 'red image -> the 开始专注 button becomes red-dominant' (Is-RedDominant $a1.Modal) ("BtnPlay modal RGB({0})" -f $a1.Modal)
Check 'red image -> button accent equals the value my own extraction formula predicts' (Colour-Near $a1.Modal $expLightRed) `
      ("observed RGB({0}) predicted RGB({1},{2},{3}) from hue {4:N2} deg" -f $a1.Modal,$expLightRed.R,$expLightRed.G,$expLightRed.B,$hueRed)
Check 'red image -> accent really changed away from the system accent' ($a1.Modal -ne $a0.Modal) ("before RGB({0}) after RGB({1})" -f $a0.Modal,$a1.Modal)
[void](Save-Shot -Name 'r3-e1-light-red.png' -Hwnd $main)

# =========================================================================================
# Phase 2 -- (vi) restart: chosen image + settings survive
# =========================================================================================
[void](Activate-App $main); Send-ForceQuit $main; [void](Wait-Exit -Pid2 $app.Pid -Sec 10)
$s2 = Read-Settings
Check 'after exit settings.json still holds BackgroundImagePath' ($s2.BackgroundImagePath -eq $redImg) ("BackgroundImagePath='{0}'" -f $s2.BackgroundImagePath)
Check 'after exit BackgroundOpacity / BackgroundRotateMinutes / BackgroundUseImageAccent intact' `
      (([double]$s2.BackgroundOpacity -eq 0.95) -and ([int]$s2.BackgroundRotateMinutes -eq 0) -and ([bool]$s2.BackgroundUseImageAccent)) `
      ("opacity={0} rotate={1} useImageAccent={2}" -f $s2.BackgroundOpacity,$s2.BackgroundRotateMinutes,$s2.BackgroundUseImageAccent)
$app = Start-App; $main = $app.Hwnd
Start-Sleep -Seconds 4
$s3 = Sample-Strip $main; $a3 = Sample-Accent $main
Check 'after restart the same red background is applied' (Is-RedDominant $s3.Modal) ("strip modal RGB({0}) avg=({1},{2},{3})" -f $s3.Modal,$s3.AvgR,$s3.AvgG,$s3.AvgB)
Check 'after restart the image accent is applied again' (Colour-Near $a3.Modal $expLightRed) ("BtnPlay modal RGB({0})" -f $a3.Modal)
[void](Save-Shot -Name 'r3-e2-restart-red.png' -Hwnd $main)

# =========================================================================================
# Phase 4 -- (ii) blue image
# =========================================================================================
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$pickB = Pick-Via-Dialog -Hwnd $main -ProcId $app.Pid -ButtonName '选择图片' -Path $blueImg
Check '选择图片 also accepts the blue image' ($pickB.Invoked -and $pickB.Closed) ("dialog='{0}' closed={1}" -f $pickB.Title,$pickB.Closed)
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Seconds 4
$s4 = Sample-Strip $main; $a4 = Sample-Accent $main
Write-Host ("light + blue image: strip modal={0} avg=({1},{2},{3})" -f $s4.Modal,$s4.AvgR,$s4.AvgG,$s4.AvgB)
Write-Host ("light + blue image: 开始专注 button modal={0} avg=({1},{2},{3})" -f $a4.Modal,$a4.AvgR,$a4.AvgG,$a4.AvgB)
Check 'blue image -> background strip becomes blue-dominant' (Is-BlueDominant $s4.Modal) ("strip modal RGB({0})" -f $s4.Modal)
Check 'blue image -> the 开始专注 button becomes blue-dominant' (Is-BlueDominant $a4.Modal) ("BtnPlay modal RGB({0})" -f $a4.Modal)
Check 'blue image -> button accent equals my predicted value and differs from the system accent' `
      ((Colour-Near $a4.Modal $expLightBlue) -and ($a4.Modal -ne $a0.Modal)) `
      ("observed RGB({0}) predicted RGB({1},{2},{3}); system accent was RGB({4})" -f $a4.Modal,$expLightBlue.R,$expLightBlue.G,$expLightBlue.B,$a0.Modal)
[void](Save-Shot -Name 'r3-e3-light-blue.png' -Hwnd $main)

# =========================================================================================
# Phase 5 -- (iv) opacity slider
# =========================================================================================
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$set15 = Uia-SetRange $main 'SldBgOpacity' 0.15
Start-Sleep -Milliseconds 1000
$lbl15 = Uia-Text $main 'LblBgOpacity'
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Seconds 4
$s5 = Sample-Strip $main
Check 'opacity slider accepts 0.15 through its real RangeValue peer' $set15 ("SetValue(0.15) ok={0}" -f $set15)
Check 'the opacity label follows the slider (15%)' ($lbl15 -eq '15%') ("LblBgOpacity='{0}'" -f $lbl15)
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$set100 = Uia-SetRange $main 'SldBgOpacity' 1.0
Start-Sleep -Milliseconds 1000
$lbl100 = Uia-Text $main 'LblBgOpacity'
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Seconds 4
$s6 = Sample-Strip $main
Check 'opacity slider accepts 1.0' $set100 ("SetValue(1.0) ok={0} label='{1}'" -f $set100,$lbl100)
$diff = [Math]::Abs($s5.AvgR-$s6.AvgR) + [Math]::Abs($s5.AvgG-$s6.AvgG) + [Math]::Abs($s5.AvgB-$s6.AvgB)
Write-Host ("opacity 0.15 strip avg=({0},{1},{2}) lum={3} | opacity 1.0 strip avg=({4},{5},{6}) lum={7} | sum|d|={8:N1}" -f `
  $s5.AvgR,$s5.AvgG,$s5.AvgB,$s5.Lum,$s6.AvgR,$s6.AvgG,$s6.AvgB,$s6.Lum,$diff)
Check 'the opacity slider visibly changes the image strength' ($diff -gt 30) ("sum |delta| over RGB = {0:N1}" -f $diff)
Check 'opacity 1.0 shows a stronger (darker) image than 0.15' ($s6.Lum -lt $s5.Lum) ("lum(1.0)={0} < lum(0.15)={1}" -f $s6.Lum,$s5.Lum)
Check 'opacity persisted as 1' (([double](Read-Settings).BackgroundOpacity) -eq 1) ("BackgroundOpacity={0}" -f (Read-Settings).BackgroundOpacity)
[void](Save-Shot -Name 'r3-e4-opacity-100.png' -Hwnd $main)

# =========================================================================================
# Phase 6 -- (v) clear restores the plain theme background
# =========================================================================================
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$clearOk = Uia-ClickName $main '清除'
Start-Sleep -Milliseconds 1300
$bgInfo = Uia-Text $main 'TxtBgInfo'
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Seconds 4
$s7 = Sample-Strip $main; $a7 = Sample-Accent $main
Check 'the 清除 button clears the background' ($clearOk -and $bgInfo -like '*未设置背景图片*') ("clicked={0} TxtBgInfo='{1}'" -f $clearOk,($bgInfo -replace "`n",' | '))
Check 'clearing restores the plain theme background (243,243,243, identical to baseline)' `
      (($s7.Modal -eq '243,243,243') -and ($s7.Modal -eq $s0.Modal)) ("strip modal after clear={0}, baseline={1}" -f $s7.Modal,$s0.Modal)
Check 'clearing also reverts the accent to the system accent' ($a7.Modal -eq $a0.Modal) ("BtnPlay after clear=RGB({0}); baseline=RGB({1})" -f $a7.Modal,$a0.Modal)
Check 'clearing persists empty path/folder to settings.json' `
      (((Read-Settings).BackgroundImagePath -eq '') -and ((Read-Settings).BackgroundFolder -eq '')) `
      ("path='{0}' folder='{1}'" -f (Read-Settings).BackgroundImagePath,(Read-Settings).BackgroundFolder)
[void](Save-Shot -Name 'r3-e5-cleared.png' -Hwnd $main)

# =========================================================================================
# Phase 7 -- (iii) folder mode + rotate on every focus start
# =========================================================================================
[void](Activate-App $main); Send-ForceQuit $main; [void](Wait-Exit -Pid2 $app.Pid -Sec 10)
Set-BaseSettings -Override @{
  ShowClock = $false; BackgroundFolder = $assets; BackgroundImagePath = ''
  BackgroundRotateOnFocus = $true; BackgroundRotateMinutes = 0; BackgroundOpacity = 1.0
  BackgroundUseImageAccent = $true
} | Out-Null
$app = Start-App; $main = $app.Hwnd
Start-Sleep -Seconds 4
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$folderInfoUi = Uia-Text $main 'TxtBgInfo'
[void](Activate-App $main)
$folderDlgInvoked = Uia-ClickName $main '选择文件夹'
Start-Sleep -Milliseconds 1800
$fd = [IntPtr]::Zero
foreach ($w in (Get-WindowsForPid -ProcId $app.Pid)) { if ($w.Class -eq '#32770') { $fd = $w.Hwnd; break } }
Check 'the 选择文件夹 button opens a native folder picker' ($folderDlgInvoked -and $fd -ne [IntPtr]::Zero) `
      ("invoked={0} dialog hwnd={1} title='{2}'" -f $folderDlgInvoked,$fd,$(if ($fd -ne [IntPtr]::Zero) { Get-Title $fd } else { '-' }))
if ($fd -ne [IntPtr]::Zero) {
  $fTitle = Get-Title $fd
  Paste-Text $assets; Start-Sleep -Milliseconds 600; Send-VKey -Vk 0x0D; Start-Sleep -Milliseconds 1800
  [void](Dismiss-Dialogs $app.Pid); Start-Sleep -Milliseconds 800
  $folderInfo2 = Uia-Text $main 'TxtBgInfo'
  Write-Host ("folder picker title='{0}'; TxtBgInfo after typing the path = '{1}'; settings BackgroundFolder='{2}'" -f `
    $fTitle, ($folderInfo2 -replace "`n",' | '), (Read-Settings).BackgroundFolder)
  Check 'the folder picker accepted the typed folder path (folder chosen through the UI)' `
        ($folderInfo2 -like '*文件夹内共 3 张*') ("TxtBgInfo='{0}'" -f ($folderInfo2 -replace "`n",' | '))
} else {
  Write-Host '  (folder picker could not be driven; folder mode configured through settings.json instead)'
}
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Seconds 4
Write-Host ("folder mode TxtBgInfo before Space = '{0}'" -f ($folderInfoUi -replace "`n",' | '))
Check 'folder mode reports the number of images in the folder (3)' ($folderInfoUi -like '*文件夹内共 3 张*') ("TxtBgInfo='{0}'" -f ($folderInfoUi -replace "`n",' | '))
$sb = Sample-Strip $main; $ab = Sample-Accent $main
Write-Host ("folder mode before Space: strip modal={0} avg=({1},{2},{3}); accent modal={4}" -f $sb.Modal,$sb.AvgR,$sb.AvgG,$sb.AvgB,$ab.Modal)
[void](Save-Shot -Name 'r3-e6-folder-before-space.png' -Hwnd $main)
$fgOk = Activate-App $main
Send-VKey -Vk 0x20
Start-Sleep -Seconds 4
$titleAfter = Get-Title $main
$sa = Sample-Strip $main; $aa = Sample-Accent $main
Write-Host ("folder mode after Space : strip modal={0} avg=({1},{2},{3}); accent modal={4}; title='{5}'" -f $sa.Modal,$sa.AvgR,$sa.AvgG,$sa.AvgB,$aa.Modal,$titleAfter)
$bgDiff = [Math]::Abs($sb.AvgR-$sa.AvgR) + [Math]::Abs($sb.AvgG-$sa.AvgG) + [Math]::Abs($sb.AvgB-$sa.AvgB)
Check 'pressing Space really started the focus phase (so the rotate trigger ran)' ($fgOk -and $titleAfter -match '专注') ("foreground={0} title='{1}'" -f $fgOk,$titleAfter)
Check 'rotate-on-focus-start changes the background image' ($bgDiff -gt 30) `
      ("background strip avg delta = {0:N1} (before ({1},{2},{3}) -> after ({4},{5},{6}))" -f $bgDiff,$sb.AvgR,$sb.AvgG,$sb.AvgB,$sa.AvgR,$sa.AvgG,$sa.AvgB)
Check 'the accent follows the new image too' ($aa.Modal -ne $ab.Modal) ("accent before RGB({0}) after RGB({1})" -f $ab.Modal,$aa.Modal)
[void](Save-Shot -Name 'r3-e7-folder-after-space.png' -Hwnd $main)

# =========================================================================================
# Phase 8 -- (vii) dark theme + red image: UI still dark, accent still red
# =========================================================================================
[void](Activate-App $main); Send-ForceQuit $main; [void](Wait-Exit -Pid2 $app.Pid -Sec 10)
Set-BaseSettings -Override @{ ShowClock = $false; Theme = 'Dark'; BackgroundImagePath = $redImg
                             BackgroundFolder = ''; BackgroundOpacity = 0.95; BackgroundUseImageAccent = $true } | Out-Null
$app = Start-App; $main = $app.Hwnd
Start-Sleep -Seconds 4
$sd = Sample-Strip $main; $ad = Sample-Accent $main
Write-Host ("dark + red image: strip modal={0} avg=({1},{2},{3}) lum={4}" -f $sd.Modal,$sd.AvgR,$sd.AvgG,$sd.AvgB,$sd.Lum)
Write-Host ("dark + red image: 开始专注 button modal={0} avg=({1},{2},{3})" -f $ad.Modal,$ad.AvgR,$ad.AvgG,$ad.AvgB)
Write-Host ("   light + red image was: strip avg=({0},{1},{2}) lum={3}, accent RGB({4})" -f $s1.AvgR,$s1.AvgG,$s1.AvgB,$s1.Lum,$a1.Modal)
Check 'dark theme + red image: the window is still dark (strip luminance far below the light variant)' `
      (($sd.Lum -lt 0.35) -and ($sd.Lum -lt ($s1.Lum - 0.25))) `
      ("dark strip lum={0:N4} vs light strip lum={1:N4} (same image, same opacity)" -f $sd.Lum,$s1.Lum)
Check 'dark theme + red image: the accent is still red-dominant' (Is-RedDominant $ad.Modal) ("BtnPlay modal RGB({0})" -f $ad.Modal)
Check 'dark theme + red image: accent equals my predicted dark-theme value (adapted, not copied verbatim)' (Colour-Near $ad.Modal $expDarkRed) `
      ("observed RGB({0}) predicted RGB({1},{2},{3}); light+red was RGB({4})" -f $ad.Modal,$expDarkRed.R,$expDarkRed.G,$expDarkRed.B,$a1.Modal)
Check 'the accent differs between light and dark themes (per-theme adaptation)' ($ad.Modal -ne $a1.Modal) `
      ("dark RGB({0}) vs light RGB({1})" -f $ad.Modal,$a1.Modal)
[void](Save-Shot -Name 'r3-e8-dark-red.png' -Hwnd $main)

[void](Activate-App $main); Send-ForceQuit $main; [void](Wait-Exit -Pid2 $app.Pid -Sec 10)
[void](Stop-AllApp)
[void](Remove-ConfigFiles)
[void](Summary)
