# 06-noise.ps1 -- Feature 4: white noise (import / volume / shuffle / next / auto-play / only-during-focus / corrupt / loop)
. (Join-Path $PSScriptRoot 'lib3.ps1')

$tone440 = Join-Path $script:AssetsDir 'tone-440.wav'
$tone880 = Join-Path $script:ShotDir 'r3-tone-880.wav'
$corrupt = Join-Path $script:ShotDir 'r3-corrupt.wav'

function New-ToneWav([string]$path, [int]$freq, [int]$ms = 1000, [int]$rate = 44100) {
  $n = [int]($rate * $ms / 1000)
  $data = New-Object byte[] ($n * 2)
  for ($i = 0; $i -lt $n; $i++) {
    $v = [int16](12000 * [Math]::Sin(2 * [Math]::PI * $freq * $i / $rate))
    $data[2*$i] = [byte]($v -band 0xFF); $data[2*$i+1] = [byte](($v -shr 8) -band 0xFF)
  }
  $ms2 = New-Object System.IO.MemoryStream
  $w = New-Object System.IO.BinaryWriter($ms2)
  $w.Write([char[]]'RIFF'); $w.Write([int](36 + $data.Length)); $w.Write([char[]]'WAVE')
  $w.Write([char[]]'fmt '); $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1)
  $w.Write([int]$rate); $w.Write([int]($rate*2)); $w.Write([int16]2); $w.Write([int16]16)
  $w.Write([char[]]'data'); $w.Write([int]$data.Length); $w.Write($data)
  $w.Flush(); [IO.File]::WriteAllBytes($path, $ms2.ToArray()); $w.Dispose()
}
New-ToneWav $tone880 880
$rnd = New-Object System.Random(1234)
$junk = New-Object byte[] 3000; $rnd.NextBytes($junk)
[IO.File]::WriteAllBytes($corrupt, $junk)
Write-Host ("test audio: tone-440={0}B (2s, shipped)  tone-880={1}B (1s, mine)  corrupt={2}B (garbage, mine)" -f `
  (Get-Item $tone440).Length,(Get-Item $tone880).Length,(Get-Item $corrupt).Length)

function Ensure-SettingsClosed([IntPtr]$Hwnd) {
  for ($i=0; $i -lt 3; $i++) {
    if ($null -eq (Uia-ById $Hwnd 'SldNoiseVolume')) { return $true }
    [void](Activate-App $Hwnd); Send-VKey -Vk 0x1B; Start-Sleep -Milliseconds 900
  }
  return ($null -eq (Uia-ById $Hwnd 'SldNoiseVolume'))
}
function Dismiss-Dialogs([int]$ProcId) {
  foreach ($w in @(Get-WindowsForPid -ProcId $ProcId | Where-Object { $_.Class -eq '#32770' })) {
    [void](Focus-Window $w.Hwnd); Start-Sleep -Milliseconds 300; Send-VKey -Vk 0x1B; Start-Sleep -Milliseconds 700
  }
}
function Pick-Via-Dialog {
  param([IntPtr]$Hwnd, [int]$ProcId, [string]$ButtonName, [string]$Path)
  [void](Dismiss-Dialogs $ProcId); [void](Activate-App $Hwnd)
  $invoked = Uia-ClickName $Hwnd $ButtonName
  $dlg = [IntPtr]::Zero; $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt 10 -and $dlg -eq [IntPtr]::Zero) {
    $c = @(Get-WindowsForPid -ProcId $ProcId | Where-Object { $_.Class -eq '#32770' })
    if ($c.Count -gt 0) { $dlg = $c[0].Hwnd }
    Start-Sleep -Milliseconds 250
  }
  if ($dlg -eq [IntPtr]::Zero) { return [pscustomobject]@{ Invoked=$invoked; Title=''; Closed=$false } }
  $title = Get-Title $dlg
  $sw2 = [Diagnostics.Stopwatch]::StartNew()
  while ($sw2.Elapsed.TotalSeconds -lt 6 -and [R3.Native]::GetForegroundWindow() -ne $dlg) { Start-Sleep -Milliseconds 200 }
  Paste-Text $Path; Start-Sleep -Milliseconds 500; Send-VKey -Vk 0x0D
  $sw3 = [Diagnostics.Stopwatch]::StartNew(); $closed = $false
  while ($sw3.Elapsed.TotalSeconds -lt 8 -and -not $closed) {
    $closed = (@(Get-WindowsForPid -ProcId $ProcId | Where-Object { $_.Class -eq '#32770' }).Count -eq 0)
    Start-Sleep -Milliseconds 300
  }
  if (-not $closed) { [void](Dismiss-Dialogs $ProcId) }
  return [pscustomobject]@{ Invoked=$invoked; Title=$title; Closed=$closed }
}
# The title-bar noise button's glyph is a thin icon-font stroke, so ClearType antialiasing means it
# never reaches the full brush colour. Measured behaviour (probe-noisebtn.ps1):
#   stopped -> neutral/magenta-grey fringes, e.g. RGB(166,149,166)  => B-R ~ 0
#   playing -> blue fringes,              e.g. RGB(170,169,221)  => B-R ~ +51
# so classify by the blue-red channel difference of the non-background pixels.
function Get-NoiseButtonState([IntPtr]$Hwnd) {
  $wrect = Get-Rect $Hwnd; $rect = Uia-RectById $Hwnd 'BtnNoise'
  if ($null -eq $rect) { return $null }
  $bmp = Capture-Window -Hwnd $Hwnd -FromScreen; $buf = Get-BmpBytes -Bmp $bmp
  $x = $rect.X - $wrect.X; $y = $rect.Y - $wrect.Y
  $blue = 0; $neutral = 0; $n = 0; $sum = 0
  for ($yy=$y; $yy -lt ($y+$rect.H); $yy++) {
    $row = $yy*$buf.Stride
    for ($xx=$x; $xx -lt ($x+$rect.W); $xx++) {
      $i = $row + $xx*4
      $cr=[int]$buf.Bytes[$i+2]; $cg=[int]$buf.Bytes[$i+1]; $cb=[int]$buf.Bytes[$i]
      if ($cr -ge 235 -and $cg -ge 235 -and $cb -ge 235) { continue }
      $n++; $d = $cb - $cr; $sum += $d
      if ($d -ge 20) { $blue++ } elseif ([Math]::Abs($d) -le 8) { $neutral++ }
    }
  }
  $bmp.Dispose()
  # measured signatures: stopped avg(B-R) ~ -0.1, playing avg(B-R) ~ +35 -> wide margin
  $avg = if ($n) { $sum/$n } else { 0 }
  $st = if ($avg -ge 15) { 'PLAYING' } elseif ($avg -le 5) { 'STOPPED' } else { 'UNKNOWN' }
  return [pscustomobject]@{ State=$st; BlueTint=$blue; Neutral=$neutral; GlyphPixels=$n
                            AvgBMinusR=[Math]::Round($avg,1) }
}
# poll the rendered button state until it matches, so an asynchronous MediaFailed transition
# cannot race the sample
function Wait-NoiseState([IntPtr]$Hwnd, [string]$Expected, [int]$Sec = 20) {
  $sw = [Diagnostics.Stopwatch]::StartNew(); $last = $null
  while ($sw.Elapsed.TotalSeconds -lt $Sec) {
    $last = Get-NoiseButtonState $Hwnd
    if ($null -ne $last -and $last.State -eq $Expected) { return $last }
    Start-Sleep -Milliseconds 700
  }
  return $last
}
function Measure-IdleCpu([int]$ProcId, [int]$Sec = 8) {
  $a = (Get-Process -Id $ProcId).TotalProcessorTime
  Start-Sleep -Seconds $Sec
  $b = (Get-Process -Id $ProcId).TotalProcessorTime
  return [Math]::Round(($b - $a).TotalSeconds, 2)
}
function Get-NoiseList([IntPtr]$Hwnd) {
  $e = Uia-ById $Hwnd 'NoiseList'; if ($null -eq $e) { return @() }
  $out = @()
  foreach ($c in $e.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
    try { if ($c.Current.Name) { $out += $c.Current.Name } } catch { }
  }
  return $out
}
function Wait-Toast([IntPtr]$Hwnd, [int]$Sec = 4) {
  $sw = [Diagnostics.Stopwatch]::StartNew(); $seen = @()
  while ($sw.Elapsed.TotalSeconds -lt $Sec) {
    $t = Uia-Text $Hwnd 'ToastText'
    if ($t -notin @('<not found>','','<error>')) { if ($seen -notcontains $t) { $seen += $t } }
    Start-Sleep -Milliseconds 250
  }
  return ($seen -join ' | ')
}
function Save-ButtonCrop([IntPtr]$Hwnd, [string]$Name) {
  $wrect = Get-Rect $Hwnd; $rect = Uia-RectById $Hwnd 'BtnNoise'
  if ($null -eq $rect) { return }
  $bmp = Capture-Window -Hwnd $Hwnd -FromScreen
  $crop = Crop-Scale-Bmp -Bmp $bmp -X ($rect.X-$wrect.X) -Y ($rect.Y-$wrect.Y) -W $rect.W -H $rect.H -Scale 6
  [void](Save-Bmp -Bmp $crop -Name $Name); $bmp.Dispose()
}

# =========================================================================================
[void](Stop-AllApp); [void](Remove-ConfigFiles)
Set-BaseSettings -Override @{
  ShowClock = $false; FocusMinutes = 25; AutoStartNext = $false
  NoiseAutoPlayOnFocus = $false; NoiseOnlyDuringFocus = $true; NoiseShuffle = $false; NoiseVolume = 70
} | Out-Null
$app = Start-App; $main = $app.Hwnd
Start-Sleep -Seconds 3
Check 'main window present' ($main -ne [IntPtr]::Zero) ("hwnd={0}" -f $main)
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 900
Check 'with no tracks the settings panel says 尚未导入' ((Uia-Text $main 'TxtNoiseInfo') -like '*尚未导入*') ("TxtNoiseInfo='{0}'" -f (Uia-Text $main 'TxtNoiseInfo'))
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Milliseconds 700
$ns0 = Get-NoiseButtonState $main
Check 'with no tracks the noise button is in the stopped state' ($ns0.State -eq 'STOPPED') `
      ("state={0} blue-tinted px={1} neutral px={2} avg(B-R)={3}" -f $ns0.State,$ns0.BlueTint,$ns0.Neutral,$ns0.AvgBMinusR)
[void](Save-ButtonCrop $main 'r3-f0-btn-stopped.png')

# =========================================================================================
# (i) import a track through 添加音频
# =========================================================================================
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$imp1 = Pick-Via-Dialog -Hwnd $main -ProcId $app.Pid -ButtonName '添加音频' -Path $tone440
Check '添加音频 opens the native 添加白噪音音频 dialog and accepts the path' `
      ($imp1.Invoked -and $imp1.Title -eq '添加白噪音音频' -and $imp1.Closed) ("title='{0}' closed={1}" -f $imp1.Title,$imp1.Closed)
Start-Sleep -Milliseconds 1200
$tinfo1 = Uia-Text $main 'TxtNoiseInfo'
$list1 = Get-NoiseList $main
Check 'the settings panel reports the imported track' ($tinfo1 -like '*已导入 1 个文件*1 个可用*已停止*') ("TxtNoiseInfo='{0}'" -f $tinfo1)
Check 'the track list control shows the imported file' (@($list1 | Where-Object { $_ -like '*tone-440.wav*' }).Count -gt 0) ("list items: {0}" -f (($list1 | Where-Object { $_ -like '*.wav' }) -join ' | '))
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Seconds 3
$sTracks = @((Read-Settings).NoiseTracks)
Check 'settings.json persists NoiseTracks as an array holding exactly the imported file' `
      (($sTracks.Count -eq 1) -and ($sTracks[0] -eq $tone440)) ("NoiseTracks=[{0}]" -f ($sTracks -join ', '))

# =========================================================================================
# (ii) auto-play on focus + only-during-focus
# =========================================================================================
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$auto0 = Uia-Toggle $main 'TglNoiseAuto'; $tgl1 = Uia-ToggleIt $main 'TglNoiseAuto'
Start-Sleep -Milliseconds 600
$auto1 = Uia-Toggle $main 'TglNoiseAuto'
$only0 = Uia-Toggle $main 'TglNoiseOnlyFocus'; $tgl2 = Uia-ToggleIt $main 'TglNoiseOnlyFocus'
Start-Sleep -Milliseconds 600
$only1 = Uia-Toggle $main 'TglNoiseOnlyFocus'
Check '开始专注时自动播放 toggles Off->On through its real automation peer' (($auto0 -eq 'Off') -and $tgl1 -and ($auto1 -eq 'On')) ("state {0} -> {1}" -f $auto0,$auto1)
Check '仅在专注阶段播放 toggles through its real automation peer' ($tgl2 -and ($only0 -ne $only1)) ("state {0} -> {1}" -f $only0,$only1)
if ($only1 -ne 'On') { [void](Uia-ToggleIt $main 'TglNoiseOnlyFocus'); Start-Sleep -Milliseconds 600 }
Check '仅在专注阶段播放 is On for the auto-play test' ((Uia-Toggle $main 'TglNoiseOnlyFocus') -eq 'On') ("state={0}" -f (Uia-Toggle $main 'TglNoiseOnlyFocus'))
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Seconds 3
$sN = Read-Settings
Check 'both noise toggles persisted to settings.json' (([bool]$sN.NoiseAutoPlayOnFocus) -and ([bool]$sN.NoiseOnlyDuringFocus)) `
      ("NoiseAutoPlayOnFocus={0} NoiseOnlyDuringFocus={1}" -f $sN.NoiseAutoPlayOnFocus,$sN.NoiseOnlyDuringFocus)

$st0 = Wait-NoiseState $main 'STOPPED' 6
Check 'before starting the focus phase the noise button is stopped' ($st0.State -eq 'STOPPED') ("state={0} avg(B-R)={1} blue-tinted px={2}" -f $st0.State,$st0.AvgBMinusR,$st0.BlueTint)
$fgOk = Activate-App $main
Send-VKey -Vk 0x20
Start-Sleep -Seconds 3
$titleRun = Get-Title $main
$stPlay = Wait-NoiseState $main 'PLAYING' 12
Check 'starting the focus phase auto-plays the noise (button turns accent/blue-tinted)' `
      (($titleRun -match '专注') -and ($stPlay.State -eq 'PLAYING')) `
      ("title='{0}' state={1} blue-tinted px={2} avg(B-R)={3}" -f $titleRun,$stPlay.State,$stPlay.BlueTint,$stPlay.AvgBMinusR)
[void](Save-ButtonCrop $main 'r3-f1-btn-playing.png')
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$tinfoPlay = Uia-Text $main 'TxtNoiseInfo'
Check 'the 白噪音 status text shows 正在播放 during the focus phase' ($tinfoPlay -like '*正在播放*tone-440.wav*') ("TxtNoiseInfo='{0}'" -f $tinfoPlay)
[void](Save-Shot -Name 'r3-f2-noise-playing.png' -Hwnd $main)
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Milliseconds 800
$fgOk2 = Activate-App $main
Send-VKey -Vk 0x20
Start-Sleep -Seconds 2
$titlePause = Get-Title $main
$stPause = Wait-NoiseState $main 'STOPPED' 12
Check 'pausing the focus phase returns the noise to stopped' `
      (($titlePause -match '专注') -and ($stPause.State -eq 'STOPPED')) `
      ("title='{0}' state={1} blue-tinted px={2} avg(B-R)={3}" -f $titlePause,$stPause.State,$stPause.BlueTint,$stPause.AvgBMinusR)
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$tinfoStop = Uia-Text $main 'TxtNoiseInfo'
Check 'the 白噪音 status text shows 已停止 after pausing' ($tinfoStop -like '*已停止*') ("TxtNoiseInfo='{0}'" -f $tinfoStop)
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Milliseconds 800
[void](Activate-App $main)
$inv = Uia-Click $main 'BtnNoise'; Start-Sleep -Seconds 2
$stBtn = Wait-NoiseState $main 'PLAYING' 12
Check 'the title-bar noise button starts playback when invoked' ($inv -and $stBtn.State -eq 'PLAYING') ("invoked={0} state={1}" -f $inv,$stBtn.State)
[void](Uia-Click $main 'BtnNoise'); Start-Sleep -Seconds 2
$stBtn2 = Wait-NoiseState $main 'STOPPED' 12
Check 'the title-bar noise button pauses playback when invoked again' ($stBtn2.State -eq 'STOPPED') ("state={0}" -f $stBtn2.State)

# =========================================================================================
# (iii) 下一首 with ONE track, then TWO tracks
# =========================================================================================
[void](Uia-Click $main 'BtnNoise'); Start-Sleep -Seconds 2
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$infoBefore = Uia-Text $main 'TxtNoiseInfo'
$nextOk1 = Uia-ClickName $main '下一首'
Start-Sleep -Milliseconds 1800
$infoAfter = Uia-Text $main 'TxtNoiseInfo'
Check '下一首 with a single track keeps the same track playing' ($nextOk1 -and ($infoAfter -like '*正在播放*tone-440.wav*')) `
      ("before='{0}' after='{1}'" -f $infoBefore,$infoAfter)
$imp2 = Pick-Via-Dialog -Hwnd $main -ProcId $app.Pid -ButtonName '添加音频' -Path $tone880
Start-Sleep -Milliseconds 1200
$infoTwo = Uia-Text $main 'TxtNoiseInfo'
Check 'a second track can be imported' ($imp2.Invoked -and ($infoTwo -like '*已导入 2 个文件*2 个可用*')) ("TxtNoiseInfo='{0}'" -f $infoTwo)
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Seconds 2
$sTwo = @((Read-Settings).NoiseTracks)
Check 'settings.json lists both tracks' ($sTwo.Count -eq 2) ("NoiseTracks=[{0}]" -f ($sTwo -join ', '))
# ensure playback is running using the pixel state (never blind-toggle), then hit 下一首
if ((Wait-NoiseState $main 'PLAYING' 3).State -ne 'PLAYING') { [void](Activate-App $main); [void](Uia-Click $main 'BtnNoise'); Start-Sleep -Seconds 2 }
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$cur1 = Uia-Text $main 'TxtNoiseInfo'
$nextOk2 = Uia-ClickName $main '下一首'
Start-Sleep -Milliseconds 2000
$cur2 = Uia-Text $main 'TxtNoiseInfo'
$name1 = [regex]::Match($cur1, '正在播放：([^·]+)').Groups[1].Value.Trim()
$name2 = [regex]::Match($cur2, '正在播放：([^·]+)').Groups[1].Value.Trim()
Check '下一首 with two tracks switches to the other file' ($nextOk2 -and $name1 -ne '' -and $name2 -ne '' -and $name1 -ne $name2) `
      ("playing '{0}' -> '{1}'  (before='{2}' after='{3}')" -f $name1,$name2,$cur1,$cur2)
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Milliseconds 800

# =========================================================================================
# (iv) corrupt file alongside a good one: no hang, no spin, failure reported
# =========================================================================================
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
[void](Uia-ClickName $main '清空列表'); Start-Sleep -Milliseconds 1000
Check '清空列表 empties the list' ((Uia-Text $main 'TxtNoiseInfo') -like '*尚未导入*') ("TxtNoiseInfo='{0}'" -f (Uia-Text $main 'TxtNoiseInfo'))
[void](Pick-Via-Dialog -Hwnd $main -ProcId $app.Pid -ButtonName '添加音频' -Path $corrupt) | Out-Null
Start-Sleep -Milliseconds 1000
[void](Pick-Via-Dialog -Hwnd $main -ProcId $app.Pid -ButtonName '添加音频' -Path $tone440) | Out-Null
Start-Sleep -Milliseconds 1000
$infoCG = Uia-Text $main 'TxtNoiseInfo'
Check 'the corrupt file and a good file are both imported' ($infoCG -like '*已导入 2 个文件*2 个可用*') ("TxtNoiseInfo='{0}'" -f $infoCG)
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Seconds 2
$listCG = @((Read-Settings).NoiseTracks)
Check 'the corrupt file is tracked first in settings.json' `
      (($listCG.Count -eq 2) -and ($listCG[0] -eq $corrupt) -and ($listCG[1] -eq $tone440)) ("NoiseTracks=[{0}]" -f ($listCG -join ', '))

$cpuIdle = Measure-IdleCpu $app.Pid 8
Write-Host ("quiet idle CPU (nothing playing, no UIA traffic) over 8s = {0}s" -f $cpuIdle)
[void](Activate-App $main)
$playInv = Uia-Click $main 'BtnNoise'     # index 0 == the corrupt file
$toast = Wait-Toast $main 5
Start-Sleep -Seconds 4
$cpuAfter = Measure-IdleCpu $app.Pid 8
$stAfterCorrupt = Wait-NoiseState $main 'PLAYING' 15
$resp = Test-Responsive $main 2000
Write-Host ("corrupt-then-good: toast='{0}'; idle CPU after the failure over 8s = {1}s (baseline {2}s); button={3}; responsive={4}" -f `
  $toast,$cpuAfter,$cpuIdle,$stAfterCorrupt.State,$resp)
Check 'playing a corrupt file does not spin the CPU (no retry loop)' (($cpuAfter - $cpuIdle) -lt 1.5) `
      ("idle CPU {0}s after the failure vs {1}s baseline over the same 8s window" -f $cpuAfter,$cpuIdle)
Check 'the window stays responsive while the corrupt file is handled' $resp ("SendMessageTimeout(WM_NULL, 2000ms) non-zero = {0}" -f $resp)
Check 'the failure is reported to the user (toast) instead of looping silently' ($toast -like '*失败*') ("toast = '{0}'" -f $toast)
Check 'the player falls through to the good track rather than retrying the corrupt one' ($stAfterCorrupt.State -eq 'PLAYING') `
      ("button state={0} blue-tinted px={1}" -f $stAfterCorrupt.State,$stAfterCorrupt.BlueTint)
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
Check 'the status text names the good track after the fall-through' ((Uia-Text $main 'TxtNoiseInfo') -like '*正在播放*tone-440.wav*') ("TxtNoiseInfo='{0}'" -f (Uia-Text $main 'TxtNoiseInfo'))
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Milliseconds 700

# =========================================================================================
# (v) corrupt file alone: must stop, not loop
# =========================================================================================
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
[void](Uia-ClickName $main '清空列表'); Start-Sleep -Milliseconds 900
[void](Pick-Via-Dialog -Hwnd $main -ProcId $app.Pid -ButtonName '添加音频' -Path $corrupt) | Out-Null
Start-Sleep -Milliseconds 1000
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Seconds 2
$cpuIdle2 = Measure-IdleCpu $app.Pid 8
[void](Activate-App $main)
[void](Uia-Click $main 'BtnNoise')
$toast2 = Wait-Toast $main 4
Start-Sleep -Seconds 4
$cpuAfter2 = Measure-IdleCpu $app.Pid 8
$stCorruptOnly = Wait-NoiseState $main 'STOPPED' 25
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$infoCorruptOnly = Uia-Text $main 'TxtNoiseInfo'
[void](Ensure-SettingsClosed $main) | Out-Null
Write-Host ("corrupt-only: toast='{0}'; idle CPU after failure={1}s (baseline {2}s); button={3}; TxtNoiseInfo='{4}'" -f `
  $toast2,$cpuAfter2,$cpuIdle2,$stCorruptOnly.State,$infoCorruptOnly)
Check 'a lone corrupt file stops the player instead of looping' (($stCorruptOnly.State -eq 'STOPPED') -and ($infoCorruptOnly -like '*已停止*')) `
      ("button state={0}; TxtNoiseInfo='{1}'" -f $stCorruptOnly.State,$infoCorruptOnly)
Check 'a lone corrupt file does not spin the CPU' (($cpuAfter2 - $cpuIdle2) -lt 1.5) `
      ("idle CPU {0}s vs {1}s baseline over the same 8s window" -f $cpuAfter2,$cpuIdle2)
Check 'the lone-corrupt failure is reported' (($toast2 -like '*失败*') -or ($infoCorruptOnly -like '*已停止*')) ("toast='{0}'" -f $toast2)
[void](Save-Shot -Name 'r3-f3-noise-corrupt.png' -Hwnd $main)

# =========================================================================================
# (vi) single short track must loop (MediaEnded -> replay)
# =========================================================================================
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
[void](Uia-ClickName $main '清空列表'); Start-Sleep -Milliseconds 900
[void](Pick-Via-Dialog -Hwnd $main -ProcId $app.Pid -ButtonName '添加音频' -Path $tone880) | Out-Null
Start-Sleep -Milliseconds 1000
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Seconds 2
Check 'only the 1-second track is loaded' ((@((Read-Settings).NoiseTracks).Count -eq 1) -and ((Read-Settings).NoiseTracks[0] -eq $tone880)) `
      ("NoiseTracks=[{0}]" -f (@((Read-Settings).NoiseTracks) -join ', '))
[void](Activate-App $main)
[void](Uia-Click $main 'BtnNoise')
Start-Sleep -Seconds 3
$loop1 = Wait-NoiseState $main 'PLAYING' 8
Start-Sleep -Seconds 4
$loop2 = Get-NoiseButtonState $main
Check 'a single 1-second track keeps looping (still playing 7s later, i.e. >=6 repeats)' `
      (($loop1.State -eq 'PLAYING') -and ($loop2.State -eq 'PLAYING')) `
      ("t=3s state={0} (blue px={1});  t=7s state={2} (blue px={3})" -f $loop1.State,$loop1.BlueTint,$loop2.State,$loop2.BlueTint)

# =========================================================================================
# (vii) clean exit with a track loaded and playing
# =========================================================================================
[void](Activate-App $main)
Send-ForceQuit $main
$exited = Wait-Exit -Pid2 $app.Pid -Sec 10
Check 'the app exits cleanly while a track is loaded and playing' $exited `
      ("HasExited={0}" -f (-not (Get-Process -Id $app.Pid -ErrorAction SilentlyContinue)))
$sFinal = Read-Settings
Check 'noise settings survived the exit' ((@($sFinal.NoiseTracks).Count -eq 1) -and ((Read-SettingsRaw) -match 'NoiseTracks')) `
      ("NoiseTracks=[{0}] volume={1} shuffle={2} auto={3} onlyFocus={4}" -f (@($sFinal.NoiseTracks) -join ', '),$sFinal.NoiseVolume,$sFinal.NoiseShuffle,$sFinal.NoiseAutoPlayOnFocus,$sFinal.NoiseOnlyDuringFocus)

[void](Stop-AllApp)
[void](Remove-ConfigFiles)
Remove-Item -Force $tone880,$corrupt -ErrorAction SilentlyContinue
[void](Summary)
