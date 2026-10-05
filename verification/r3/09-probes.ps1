# 09-probes.ps1 -- extra probes beyond the required list (rotation mapping, volume slider, missing file, shuffle, corrupt history)
. (Join-Path $PSScriptRoot 'lib3.ps1')

$tone440 = Join-Path $script:AssetsDir 'tone-440.wav'
$assets  = $script:AssetsDir
$missing = Join-Path $script:ShotDir 'does-not-exist.wav'

function Ensure-SettingsClosed([IntPtr]$Hwnd) {
  for ($i=0; $i -lt 3; $i++) {
    if ($null -eq (Uia-ById $Hwnd 'SldNoiseVolume')) { return $true }
    [void](Activate-App $Hwnd); Send-VKey -Vk 0x1B; Start-Sleep -Milliseconds 900
  }
  return ($null -eq (Uia-ById $Hwnd 'SldNoiseVolume'))
}
# same detector as 06-noise.ps1: stopped avg(B-R) ~ -0.1, playing avg(B-R) ~ +35
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
  $avg = if ($n) { $sum/$n } else { 0 }
  $st = if ($avg -ge 15) { 'PLAYING' } elseif ($avg -le 5) { 'STOPPED' } else { 'UNKNOWN' }
  return [pscustomobject]@{ State=$st; BlueTint=$blue; Neutral=$neutral; GlyphPixels=$n; AvgBMinusR=[Math]::Round($avg,1) }
}
function Wait-NoiseState([IntPtr]$Hwnd, [string]$Expected, [int]$Sec = 20) {
  $sw = [Diagnostics.Stopwatch]::StartNew(); $last = $null
  while ($sw.Elapsed.TotalSeconds -lt $Sec) {
    $last = Get-NoiseButtonState $Hwnd
    if ($null -ne $last -and $last.State -eq $Expected) { return $last }
    Start-Sleep -Milliseconds 700
  }
  return $last
}

# =========================================================================================
# P1 -- BackgroundRotateMinutes <-> combo index mapping round-trip
# =========================================================================================
Write-Host '=== P1: rotation interval combo mapping and round-trip ==='
$expectDesc = @{ 5='每 5 分钟轮换'; 15='每 15 分钟轮换'; 30='每 30 分钟轮换'; 60='每 1 小时轮换'; 1440='每天轮换' }
foreach ($mins in 5,15,30,60,1440) {
  [void](Stop-AllApp); [void](Remove-ConfigFiles)
  Set-BaseSettings -Override @{ ShowClock = $false; BackgroundFolder = $assets; BackgroundRotateMinutes = $mins } | Out-Null
  $app = Start-App; $main = $app.Hwnd
  Start-Sleep -Seconds 3
  [void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
  $info = Uia-Text $main 'TxtBgInfo'
  [void](Ensure-SettingsClosed $main) | Out-Null
  Start-Sleep -Milliseconds 600
  [void](Activate-App $main); Send-ForceQuit $main; [void](Wait-Exit -Pid2 $app.Pid -Sec 10)
  $back = [int](Read-Settings).BackgroundRotateMinutes
  Check ("P1 BackgroundRotateMinutes={0}: panel text and persisted value agree" -f $mins) `
        (($info -like ("*" + $expectDesc[$mins] + "*")) -and ($back -eq $mins)) `
        ("TxtBgInfo='{0}'  persisted={1} (expected {2})" -f ($info -replace "`n",' | '),$back,$mins)
}

# =========================================================================================
# P2 -- noise volume slider
# =========================================================================================
Write-Host ''
Write-Host '=== P2: noise volume slider ==='
[void](Stop-AllApp); [void](Remove-ConfigFiles)
Set-BaseSettings -Override @{ ShowClock = $false; NoiseTracks = @($tone440); NoiseVolume = 70 } | Out-Null
$app = Start-App; $main = $app.Hwnd
Start-Sleep -Seconds 3
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$setOk = Uia-SetRange $main 'SldNoiseVolume' 25
Start-Sleep -Milliseconds 900
$vlbl = Uia-Text $main 'LblNoiseVolume'
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Milliseconds 700
[void](Activate-App $main); Send-ForceQuit $main; [void](Wait-Exit -Pid2 $app.Pid -Sec 10)
$vol = [int](Read-Settings).NoiseVolume
Check 'P2 the volume slider updates its label and persists the new volume' ($setOk -and ($vlbl -eq '25%') -and ($vol -eq 25)) `
      ("SetValue(25) ok={0} label='{1}' persisted NoiseVolume={2}" -f $setOk,$vlbl,$vol)

# =========================================================================================
# P3 -- a missing file in NoiseTracks must be reported and skipped gracefully
# =========================================================================================
Write-Host ''
Write-Host '=== P3: missing noise file handling ==='
[void](Stop-AllApp); [void](Remove-ConfigFiles)
Set-BaseSettings -Override @{ ShowClock = $false; NoiseTracks = @($missing,$tone440); NoiseShuffle = $false
                             NoiseVolume = 70; NoiseAutoPlayOnFocus = $false; NoiseOnlyDuringFocus = $true } | Out-Null
$app = Start-App; $main = $app.Hwnd
Start-Sleep -Seconds 3
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$infoMiss = Uia-Text $main 'TxtNoiseInfo'
Check 'P3 the panel reports 2 imported files with only 1 usable' ($infoMiss -like '*已导入 2 个文件*1 个可用*') ("TxtNoiseInfo='{0}'" -f $infoMiss)
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Milliseconds 700
[void](Activate-App $main)
[void](Uia-Click $main 'BtnNoise')
Start-Sleep -Seconds 3
$stMiss = Wait-NoiseState $main 'PLAYING' 10
Check 'P3 playback still starts even though the first track is a missing file' ($stMiss.State -eq 'PLAYING') `
      ("button state={0} blue-tinted px={1}" -f $stMiss.State,$stMiss.BlueTint)
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$playName = [regex]::Match((Uia-Text $main 'TxtNoiseInfo'), '正在播放：([^·]+)').Groups[1].Value.Trim()
Check 'P3 the track actually playing is the one that exists' ($playName -eq 'tone-440.wav') ("playing='{0}'" -f $playName)
[void](Ensure-SettingsClosed $main) | Out-Null
Start-Sleep -Milliseconds 700
[void](Activate-App $main); Send-ForceQuit $main; [void](Wait-Exit -Pid2 $app.Pid -Sec 10)
$kept = @((Read-Settings).NoiseTracks)
Check 'P3 the missing path is still listed in settings.json (the list is not silently rewritten)' ($kept.Count -eq 2) ("NoiseTracks=[{0}]" -f ($kept -join ', '))

# =========================================================================================
# P4 -- shuffle with two tracks must not repeat the same file
# =========================================================================================
Write-Host ''
Write-Host '=== P4: shuffle across two tracks ==='
$tone880 = Join-Path $script:ShotDir 'r3-tone-880b.wav'
$n = 44100; $data = New-Object byte[] ($n*2)
for ($i=0; $i -lt $n; $i++) { $v=[int16](9000*[Math]::Sin(2*[Math]::PI*660*$i/$n)); $data[2*$i]=[byte]($v -band 0xFF); $data[2*$i+1]=[byte](($v -shr 8) -band 0xFF) }
$ms2 = New-Object System.IO.MemoryStream; $w = New-Object System.IO.BinaryWriter($ms2)
$w.Write([char[]]'RIFF'); $w.Write([int](36+$data.Length)); $w.Write([char[]]'WAVE')
$w.Write([char[]]'fmt '); $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1)
$w.Write([int]44100); $w.Write([int]88200); $w.Write([int16]2); $w.Write([int16]16)
$w.Write([char[]]'data'); $w.Write([int]$data.Length); $w.Write($data)
$w.Flush(); [IO.File]::WriteAllBytes($tone880,$ms2.ToArray()); $w.Dispose()

[void](Stop-AllApp); [void](Remove-ConfigFiles)
Set-BaseSettings -Override @{ ShowClock = $false; NoiseTracks = @($tone440,$tone880); NoiseShuffle = $true
                             NoiseVolume = 70; NoiseAutoPlayOnFocus = $false; NoiseOnlyDuringFocus = $true } | Out-Null
$app = Start-App; $main = $app.Hwnd
Start-Sleep -Seconds 3
[void](Activate-App $main)
[void](Uia-Click $main 'BtnNoise')
Start-Sleep -Seconds 3
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 1000
$seq = @()
$seq += [regex]::Match((Uia-Text $main 'TxtNoiseInfo'), '正在播放：([^·]+)').Groups[1].Value.Trim()
for ($i=1; $i -le 5; $i++) {
  [void](Uia-ClickName $main '下一首'); Start-Sleep -Milliseconds 900
  $seq += [regex]::Match((Uia-Text $main 'TxtNoiseInfo'), '正在播放：([^·]+)').Groups[1].Value.Trim()
}
$repeats = 0
for ($i=1; $i -lt $seq.Count; $i++) { if ($seq[$i] -eq $seq[$i-1]) { $repeats++ } }
Write-Host ("shuffle sequence over 5 下一首 presses: {0}" -f ($seq -join ' -> '))
Check 'P4 shuffle never stays on the same file across 下一首 presses' ($repeats -eq 0 -and (@($seq | Where-Object { $_ -ne '' }).Count -eq 6)) `
      ("sequence={0}; consecutive repeats={1}" -f ($seq -join ' -> '),$repeats)
[void](Ensure-SettingsClosed $main) | Out-Null
[void](Activate-App $main); Send-ForceQuit $main; [void](Wait-Exit -Pid2 $app.Pid -Sec 10)

# =========================================================================================
# P5 -- corrupt history.json must not break the statistics window
# =========================================================================================
Write-Host ''
Write-Host '=== P5: corrupt history.json ==='
[void](Stop-AllApp); [void](Remove-ConfigFiles)
Set-BaseSettings -Override @{ ShowClock = $false } | Out-Null
Write-HistoryRaw '{ "Days": { "2026-10-05": { "Minutes": 30, '
$app = Start-App; $main = $app.Hwnd
Start-Sleep -Seconds 3
Check 'P5 the app still starts with a truncated history.json' (($main -ne [IntPtr]::Zero) -and (-not $app.Proc.HasExited)) ("hwnd={0}" -f $main)
[void](Send-CtrlKey -Hwnd $main -Vk 0x49); Start-Sleep -Milliseconds 1600
$stats = Get-StatsWindow -ProcId $app.Pid
Check 'P5 the statistics window still opens' ($stats -ne [IntPtr]::Zero) ("stats hwnd={0}" -f $stats)
if ($stats -ne [IntPtr]::Zero) {
  $val = Uia-Text $stats 'ValToday'; $rng = Uia-Text $stats 'TxtRange'; $tot = Uia-Text $stats 'ValTotal'
  Check 'P5 the corrupt history degrades to zeros instead of crashing' (($val -eq '0 分钟') -and ($rng -eq '共 0 天有记录') -and ($tot -eq '0 分钟')) `
        ("ValToday='{0}' TxtRange='{1}' ValTotal='{2}'" -f $val,$rng,$tot)
  [void](Activate-App $stats); Send-VKey -Vk 0x1B; Start-Sleep -Milliseconds 700
}
[void](Activate-App $main)
Check 'P5 the main window is still responsive' (Test-Responsive $main 2000) ("WM_NULL ping after the corrupt history = ok")
Send-ForceQuit $main; [void](Wait-Exit -Pid2 $app.Pid -Sec 10)

[void](Stop-AllApp)
[void](Remove-ConfigFiles)
Remove-Item -Force $tone880 -ErrorAction SilentlyContinue
[void](Summary)
