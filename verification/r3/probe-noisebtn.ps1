# probe-noisebtn.ps1 -- what colours are actually rendered in the title-bar noise button?
. (Join-Path $PSScriptRoot 'lib3.ps1')

$tone440 = Join-Path $script:AssetsDir 'tone-440.wav'
[void](Stop-AllApp); [void](Remove-ConfigFiles)
Set-BaseSettings -Override @{ ShowClock = $false; NoiseTracks = @($tone440); NoiseShuffle = $false
                             NoiseAutoPlayOnFocus = $false; NoiseOnlyDuringFocus = $true } | Out-Null
$app = Start-App; $main = $app.Hwnd
Start-Sleep -Seconds 3

function Show-Button {
  param([IntPtr]$Hwnd, [string]$Label)
  $wr = Get-Rect $Hwnd
  $r = Uia-RectById $Hwnd 'BtnNoise'
  Write-Host ("[{0}] window @({1},{2}) {3}x{4}; BtnNoise rect={5}" -f $Label,$wr.X,$wr.Y,$wr.W,$wr.H,($r | ConvertTo-Json -Compress))
  if ($null -eq $r) { return }
  $bmp = Capture-Window -Hwnd $Hwnd -FromScreen
  $buf = Get-BmpBytes -Bmp $bmp
  $x = $r.X - $wr.X; $y = $r.Y - $wr.Y
  $hist = @{}
  for ($yy = $y; $yy -lt ($y+$r.H); $yy++) {
    for ($xx = $x; $xx -lt ($x+$r.W); $xx++) {
      $i = $yy*$buf.Stride + $xx*4
      $k = '{0},{1},{2}' -f $buf.Bytes[$i+2],$buf.Bytes[$i+1],$buf.Bytes[$i]
      if ($hist.ContainsKey($k)) { $hist[$k]++ } else { $hist[$k]=1 }
    }
  }
  $top = $hist.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 8
  Write-Host ("   distinct colours={0}; top:" -f $hist.Count)
  foreach ($h in $top) { Write-Host ("      {0,-16} x{1}" -f $h.Key, $h.Value) }
  Write-Host ("   TxtNoiseInfo = '{0}'" -f (Uia-Text $Hwnd 'TxtNoiseInfo'))
  $bmp.Dispose()
}

Show-Button $main 'idle'
[void](Activate-App $main)
[void](Uia-Click $main 'BtnNoise')
Start-Sleep -Seconds 3
Show-Button $main 'after BtnNoise click (should be playing)'
[void](Uia-Click $main 'BtnNoise')
Start-Sleep -Seconds 2
Show-Button $main 'after second click (should be stopped)'

# also dump what AccentBrush / TextPrimaryBrush resolve to by sampling the BtnStats glyph
$wr = Get-Rect $main
$r = Uia-RectById $main 'BtnStats'
if ($r) {
  $bmp = Capture-Window -Hwnd $main -FromScreen; $buf = Get-BmpBytes -Bmp $bmp
  $hist = @{}
  for ($yy = $r.Y-$wr.Y; $yy -lt ($r.Y-$wr.Y+$r.H); $yy++) {
    for ($xx = $r.X-$wr.X; $xx -lt ($r.X-$wr.X+$r.W); $xx++) {
      $i = $yy*$buf.Stride + $xx*4
      $k = '{0},{1},{2}' -f $buf.Bytes[$i+2],$buf.Bytes[$i+1],$buf.Bytes[$i]
      if ($hist.ContainsKey($k)) { $hist[$k]++ } else { $hist[$k]=1 }
    }
  }
  Write-Host ("[BtnStats reference] rect={0} distinct={1}; top:" -f (($r|ConvertTo-Json -Compress)),$hist.Count)
  foreach ($h in ($hist.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 6)) { Write-Host ("      {0,-16} x{1}" -f $h.Key,$h.Value) }
  $bmp.Dispose()
}
[void](Stop-AllApp); [void](Remove-ConfigFiles)
