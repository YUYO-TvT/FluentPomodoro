# probe-grid.ps1 -- offline analysis of a saved 专注统计 capture: where exactly is the matrix?
. (Join-Path $PSScriptRoot 'lib3.ps1')

$png = Join-Path $script:ShotDir 'r3-c1-stats-window.png'
$bmp = [System.Drawing.Bitmap]::FromFile($png)
$buf = Get-BmpBytes -Bmp $bmp
Write-Host ("image {0}x{1} stride={2}" -f $buf.W, $buf.H, $buf.Stride)

$lightXaml = Get-Content (Join-Path $script:ProjRoot 'Themes\Palette.Light.xaml') -Raw
$heat = @{}
for ($i = 0; $i -le 5; $i++) {
  $m = [regex]::Match($lightXaml, ('Heat{0}Brush"\s+Color="#([0-9A-Fa-f]{{6}})"' -f $i))
  $hex = $m.Groups[1].Value
  $heat[$i] = @{ R=[Convert]::ToInt32($hex.Substring(0,2),16); G=[Convert]::ToInt32($hex.Substring(2,2),16); B=[Convert]::ToInt32($hex.Substring(4,2),16) }
}
foreach ($i in 0..5) {
  $b = Get-BufColorBox -Buf $buf -R $heat[$i].R -G $heat[$i].G -B $heat[$i].B
  Write-Host ("Heat{0}  count={1,-7} bbox=({2},{3})-({4},{5})" -f $i,$b.Count,$b.X0,$b.Y0,$b.X1,$b.Y1)
}

# union of all heat colours, row profile
$rows = @{}
for ($y = 0; $y -lt $buf.H; $y++) {
  $n = 0
  foreach ($i in 0..5) { $n += (Count-BufColor -Buf $buf -R $heat[$i].R -G $heat[$i].G -B $heat[$i].B -X 0 -Y $y -W $buf.W -H 1) }
  if ($n -gt 0) { $rows[$y] = $n }
}
$ys = @($rows.Keys | Sort-Object)
Write-Host ("heat rows: {0}..{1}  ({2} rows with heat pixels)" -f $ys[0], $ys[-1], $ys.Count)
$prev = $null; $start = $null
foreach ($y in $ys) {
  if ($null -eq $prev -or $y -ne $prev + 1) {
    if ($null -ne $start) { Write-Host ("  band y={0}..{1}" -f $start, $prev) }
    $start = $y
  }
  $prev = $y
}
Write-Host ("  band y={0}..{1}" -f $start, $prev)

# leftmost heat column profile per row-band of the grid
$minX = [int]::MaxValue; $minXy = 0
for ($y = 0; $y -lt $buf.H; $y++) {
  for ($x = 0; $x -lt 200; $x++) {
    $c = Get-BufPixel -Buf $buf -X $x -Y $y
    $hit = $false
    foreach ($i in 0..5) { if ($c.R -eq $heat[$i].R -and $c.G -eq $heat[$i].G -and $c.B -eq $heat[$i].B) { $hit = $true; break } }
    if ($hit) { if ($x -lt $minX) { $minX = $x; $minXy = $y }; break }
  }
}
Write-Host ("leftmost heat pixel = x={0} at y={1}" -f $minX, $minXy)

# column occupancy on the first grid row that has heat pixels
$topRow = $ys[0]
$cols = @{}
for ($x = 0; $x -lt $buf.W; $x++) {
  $n = 0
  foreach ($i in 0..5) { $n += (Count-BufColor -Buf $buf -R $heat[$i].R -G $heat[$i].G -B $heat[$i].B -X $x -Y $topRow -W 1 -H 13) }
  $cols[$x] = $n
}
$runs = @(); $inRun = $false; $rs = 0
for ($x = 0; $x -lt $buf.W; $x++) {
  $on = $cols[$x] -gt 0
  if ($on -and -not $inRun) { $inRun = $true; $rs = $x }
  if (-not $on -and $inRun) { $inRun = $false; $runs += ("{0}-{1}" -f $rs, ($x-1)) }
}
Write-Host ("heat runs in row band y={0}..{1}: {2}" -f $topRow, ($topRow+12), ($runs -join ' '))
$bmp.Dispose()
