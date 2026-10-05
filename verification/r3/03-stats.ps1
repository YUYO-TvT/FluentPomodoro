# 03-stats.ps1 -- Feature 2: 专注统计 window (contribution matrix, summary cards, CSV export)
#
# The matrix geometry is NOT assumed: the origin is measured from the captured pixels, and the
# app's own calendar day is identified from the 今日 card with three deliberately distinct
# fixture values, so a midnight rollover cannot silently invalidate the expectations.
. (Join-Path $PSScriptRoot 'lib3.ps1')

$T = [datetime]::Today
Write-Host ("harness date = {0:yyyy-MM-dd} ({1}) {2:HH:mm:ss}" -f $T, $T.DayOfWeek, (Get-Date))

function Get-Level([int]$m) {
  if ($m -le 0) { return 0 }
  if ($m -lt 25) { return 1 }
  if ($m -lt 50) { return 2 }
  if ($m -lt 100) { return 3 }
  if ($m -lt 200) { return 4 }
  return 5
}
function Format-Duration([int]$minutes) {
  if ($minutes -le 0) { return '0 分钟' }
  if ($minutes -lt 60) { return "$minutes 分钟" }
  $h = [int]($minutes / 60); $r = $minutes % 60
  if ($r -eq 0) { return "$h 小时" }
  return "$h 小时 $r 分"
}
function Get-Monday([datetime]$d) { $d.Date.AddDays(-((([int]$d.DayOfWeek) + 6) % 7)) }
function Write-Days($days) { Write-HistoryRaw (([ordered]@{ Days = $days } | ConvertTo-Json -Depth 5)) }

# palette read straight out of the frozen source
$lightXaml = Get-Content (Join-Path $script:ProjRoot 'Themes\Palette.Light.xaml') -Raw
$heat = @{}
for ($i = 0; $i -le 5; $i++) {
  $m = [regex]::Match($lightXaml, ('Heat{0}Brush"\s+Color="#([0-9A-Fa-f]{{6}})"' -f $i))
  if (-not $m.Success) { throw "cannot read Heat$i from Palette.Light.xaml" }
  $hex = $m.Groups[1].Value
  $heat[$i] = @{ Hex = ('#' + $hex.ToUpper()); R = [Convert]::ToInt32($hex.Substring(0,2),16)
                 G = [Convert]::ToInt32($hex.Substring(2,2),16); B = [Convert]::ToInt32($hex.Substring(4,2),16) }
}
Write-Host ("palette (Themes\Palette.Light.xaml): " + (($heat.Keys | ForEach-Object { "H{0}={1}" -f $_,$heat[$_].Hex }) -join '  '))

# ---- measure the matrix geometry from pixels -------------------------------------------
function Get-GridOrigin {
  param($Buf, $Heat)
  $rows = New-Object System.Collections.Generic.List[int]
  for ($y = 0; $y -lt $Buf.H; $y++) {
    $n = 0
    foreach ($i in 0..5) { $n += (Count-BufColor -Buf $Buf -R $Heat[$i].R -G $Heat[$i].G -B $Heat[$i].B -X 0 -Y $y -W $Buf.W -H 1) }
    if ($n -gt 0) { $rows.Add($y) }
  }
  if ($rows.Count -eq 0) { return $null }
  $y0 = $rows[0]; $y1 = $rows[0]
  for ($k = 1; $k -lt $rows.Count; $k++) {
    if ($rows[$k] - $y1 -gt 8) { break }   # 16px row pitch -> 3px gap; legend is >16px below
    $y1 = $rows[$k]
  }
  $x0 = [int]::MaxValue; $x1 = -1
  foreach ($i in 0..5) {
    $b = Get-BufColorBox -Buf $Buf -R $Heat[$i].R -G $Heat[$i].G -B $Heat[$i].B -Y $y0 -H ($y1 - $y0 + 1)
    if ($b.Count -eq 0) { continue }
    if ($b.X0 -lt $x0) { $x0 = $b.X0 }
    if ($b.X1 -gt $x1) { $x1 = $b.X1 }
  }
  return [pscustomobject]@{ X = $x0 - 30; Y = $y0 - 20; W = ($x1 - $x0 + 1); H = ($y1 - $y0 + 1)
                            RawX0 = $x0; RawY0 = $y0; RawX1 = $x1; RawY1 = $y1 }
}

function Open-Stats {
  param([IntPtr]$Main, [int]$ProcId)
  $s = Get-StatsWindow -ProcId $ProcId
  if ($s -eq [IntPtr]::Zero) { [void](Send-CtrlKey -Hwnd $Main -Vk 0x49); Start-Sleep -Milliseconds 1600; $s = Get-StatsWindow -ProcId $ProcId }
  return $s
}
function Read-TipAt {
  param($StatHwnd, $Sr, $Origin, [int]$Week, [int]$Row, [int]$ProcId)
  $x = [int]($Sr.X + $Origin.X + 30 + $Week * 16 + 6)
  $y = [int]($Sr.Y + $Origin.Y + 20 + $Row * 16 + 6)
  [void][R3.Native]::SetCursorPos($x, $y)
  Start-Sleep -Milliseconds 900
  $txt = '<no tooltip>'
  foreach ($p in (Get-OtherWindows -ProcId $ProcId)) {
    $names = @()
    try {
      $root = Uia-Root $p.Hwnd
      if ($null -ne $root) {
        foreach ($e in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
          try { if ($e.Current.Name) { $names += $e.Current.Name } } catch { }
        }
      }
    } catch { }
    if ($names.Count -gt 0) { $txt = ($names -join ' || '); break }
  }
  return $txt
}

# =========================================================================================
# PHASE 1 -- identify the app's own "today" from the 今日 card using 3 distinct fixtures
# =========================================================================================
[void](Stop-AllApp)
[void](Remove-ConfigFiles)
Set-BaseSettings -Override @{ ShowClock = $false } | Out-Null
$idDays = [ordered]@{}
$idDays[$T.AddDays(-1).ToString('yyyy-MM-dd')] = @{ Minutes = 111; Pomodoros = 2 }
$idDays[$T.ToString('yyyy-MM-dd')]           = @{ Minutes = 222; Pomodoros = 3 }
$idDays[$T.AddDays(1).ToString('yyyy-MM-dd')] = @{ Minutes = 333; Pomodoros = 4 }
Write-Days $idDays

$app = Start-App
$main = $app.Hwnd
Check 'main window present' ($main -ne [IntPtr]::Zero) ("hwnd={0}" -f $main)
$stats = Open-Stats -Main $main -ProcId $app.Pid
Check 'Ctrl+I opens the 专注统计 window' ($stats -ne [IntPtr]::Zero) ("stats hwnd={0} rect={1}" -f $stats, ((Get-Rect $stats) | ConvertTo-Json -Compress))
$vt = Uia-Text $stats 'ValToday'
$appT = switch ($vt) { '1 小时 51 分' { $T.AddDays(-1) } '3 小时 42 分' { $T } '5 小时 33 分' { $T.AddDays(1) } default { $null } }
Check 'app calendar day identified from the 今日 card (within 1 day of my clock)' ($null -ne $appT) `
      ("ValToday='{0}' -> app today = {1:yyyy-MM-dd}; my clock = {2:yyyy-MM-dd}" -f $vt, $(if ($appT) { $appT } else { [datetime]::MinValue }), $T)
if ($null -eq $appT) { [void](Stop-AllApp); [void](Remove-ConfigFiles); [void](Summary); exit 1 }

$monday    = Get-Monday $appT
$gridStart = $monday.AddDays(-7 * 52)
$visibleCells = ($appT - $gridStart).Days + 1
Write-Host ("app today={0:yyyy-MM-dd} ({1})  monday={2:yyyy-MM-dd}  gridStart={3:yyyy-MM-dd}  visible cells={4}" -f `
            $appT, $appT.DayOfWeek, $monday, $gridStart, $visibleCells)

# =========================================================================================
# PHASE 2 -- write the boundary fixture set anchored to the app's calendar day
# =========================================================================================
$plan = @(
  @{ off = 0;  min = 500; pom = 3 },   # grid (0,0) and the best day
  @{ off = 1;  min = 0;   pom = 2 },   # level 0 with a record
  @{ off = 7;  min = 1;   pom = 1 },
  @{ off = 8;  min = 24;  pom = 1 },
  @{ off = 14; min = 25;  pom = 2 },
  @{ off = 15; min = 49;  pom = 2 },
  @{ off = 21; min = 50;  pom = 3 },
  @{ off = 22; min = 99;  pom = 4 },
  @{ off = 28; min = 100; pom = 5 },
  @{ off = 29; min = 199; pom = 6 },
  @{ off = 36; min = 200; pom = 7 }
)
$days = [ordered]@{}
foreach ($p in $plan) { $days[$gridStart.AddDays($p.off).ToString('yyyy-MM-dd')] = @{ Minutes = $p.min; Pomodoros = $p.pom } }
$extra = @(
  @{ d = $appT;               min = 30;  pom = 1 },
  @{ d = $appT.AddDays(-1);   min = 45;  pom = 2 },
  @{ d = $appT.AddDays(-2);   min = 10;  pom = 1 },
  @{ d = $appT.AddDays(-20);  min = 120; pom = 3 },
  @{ d = $appT.AddDays(-400); min = 130; pom = 4 }    # outside the 53-week window: totals only
)
foreach ($p in $extra) { $k = $p.d.ToString('yyyy-MM-dd'); if (-not $days.Contains($k)) { $days[$k] = @{ Minutes = $p.min; Pomodoros = $p.pom } } }
Write-Days $days

# force the stats window to reload by bouncing activation (it reloads on Activated)
[void](Activate-App $main); Start-Sleep -Milliseconds 500
[void](Activate-App $stats); Start-Sleep -Milliseconds 1000
$rangeTxt = Uia-Text $stats 'TxtRange'
if ($rangeTxt -ne "共 $($days.Count) 天有记录") {
  Write-Host ("  reload via activation did not take ('{0}'); closing and reopening the window" -f $rangeTxt)
  [void](Activate-App $stats); Send-VKey -Vk 0x1B; Start-Sleep -Milliseconds 800
  $stats = Open-Stats -Main $main -ProcId $app.Pid
}
Check 'statistics window picked up the rewritten history.json' ((Uia-Text $stats 'TxtRange') -eq "共 $($days.Count) 天有记录") `
      ("TxtRange='{0}' expected='共 {1} 天有记录'" -f (Uia-Text $stats 'TxtRange'), $days.Count)

# ---- expectations computed by me from the JSON I wrote ----
$expCount = @{ 0 = $visibleCells; 1 = 0; 2 = 0; 3 = 0; 4 = 0; 5 = 0 }
foreach ($k in $days.Keys) {
  $d = [datetime]::ParseExact($k, 'yyyy-MM-dd', $null)
  if ($d -lt $gridStart -or $d -gt $appT) { continue }
  $lvl = Get-Level ([int]$days[$k].Minutes)
  if ($lvl -gt 0) { $expCount[0]--; $expCount[$lvl]++ }   # level-0 cells stay part of the initial total
}
$todayMin = [int]$days[$appT.ToString('yyyy-MM-dd')].Minutes
$todayPom = [int]$days[$appT.ToString('yyyy-MM-dd')].Pomodoros
$monthStart = New-Object datetime($appT.Year, $appT.Month, 1)
$weekMin = 0; $monthMin = 0; $totalMin = 0; $totalPom = 0; $bestDay = $null; $bestMin = 0
foreach ($k in $days.Keys) {
  $d = [datetime]::ParseExact($k, 'yyyy-MM-dd', $null); $m = [int]$days[$k].Minutes
  $totalMin += $m; $totalPom += [int]$days[$k].Pomodoros
  if ($d -ge $monday -and $d -le $appT) { $weekMin += $m }
  if ($d -ge $monthStart -and $d -le $appT) { $monthMin += $m }
  if ($m -gt $bestMin) { $bestMin = $m; $bestDay = $d }
}
$streak = 0; $cur = $appT
if (-not $days.Contains($cur.ToString('yyyy-MM-dd'))) { $cur = $cur.AddDays(-1) }
while ($days.Contains($cur.ToString('yyyy-MM-dd')) -and [int]$days[$cur.ToString('yyyy-MM-dd')].Minutes -gt 0) { $streak++; $cur = $cur.AddDays(-1) }
$expToday = Format-Duration $todayMin; $expWeek = Format-Duration $weekMin; $expMonth = Format-Duration $monthMin
$expTotal = Format-Duration $totalMin;  $expBest = Format-Duration $bestMin
Write-Host ("my expectations: today='{0}'/{1}pom  week='{2}'  month='{3}'  total='{4}'/{5}pom  streak={6}  best='{7}' on {8:yyyy-MM-dd}" -f `
            $expToday,$todayPom,$expWeek,$expMonth,$expTotal,$totalPom,$streak,$expBest,$bestDay)
Write-Host ("my expected level counts: L0={0} L1={1} L2={2} L3={3} L4={4} L5={5}" -f `
            $expCount[0],$expCount[1],$expCount[2],$expCount[3],$expCount[4],$expCount[5])

# ---- (i) open from the title-bar button as well ----
$clicked = Uia-Click $main 'BtnStats'
Start-Sleep -Milliseconds 900
Check 'title-bar 统计 button activates the window (real Click handler)' $clicked ("BtnStats InvokePattern invoked={0}" -f $clicked)

# ---- capture and measure geometry ----
[void][R3.Native]::SetCursorPos(1900, 1070)
Start-Sleep -Milliseconds 800
$sr = Get-Rect $stats
$shot = Capture-Window -Hwnd $stats -FromScreen
$buf = Get-BmpBytes -Bmp $shot
[void](Save-Shot -Name 'r3-c1-stats-window.png' -Hwnd $stats)
$orig = Get-GridOrigin -Buf $buf -Heat $heat
Check 'the contribution matrix was located in the capture' ($null -ne $orig) `
      ("measured heat-pixel bbox=({0},{1})-({2},{3}) -> matrix origin ({4},{5}) drawn size {6}x{7}" -f `
       $orig.RawX0,$orig.RawY0,$orig.RawX1,$orig.RawY1,$orig.X,$orig.Y,$orig.W,$orig.H)
# structural check: the drawn cells must form exactly 53 column runs and 7 row runs
$colHit = New-Object bool[] $buf.W
for ($x = 0; $x -lt $buf.W; $x++) {
  $n = 0
  foreach ($i in 0..5) { $n += (Count-BufColor -Buf $buf -R $heat[$i].R -G $heat[$i].G -B $heat[$i].B -X $x -Y $orig.RawY0 -W 1 -H ($orig.H)) }
  $colHit[$x] = ($n -gt 0)
}
$colRuns = 0; $wasHit = $false
for ($x = 0; $x -lt $buf.W; $x++) { if ($colHit[$x] -and -not $wasHit) { $colRuns++ }; $wasHit = $colHit[$x] }
$rowHit = New-Object bool[] $buf.H
for ($y = 0; $y -lt $buf.H; $y++) {
  $n = 0
  foreach ($i in 0..5) { $n += (Count-BufColor -Buf $buf -R $heat[$i].R -G $heat[$i].G -B $heat[$i].B -X 0 -Y $y -W $buf.W -H 1) }
  $rowHit[$y] = ($n -gt 0)
}
$rowRuns = 0; $wasHit = $false
for ($y = $orig.RawY0; $y -le $orig.RawY1; $y++) { if ($rowHit[$y] -and -not $wasHit) { $rowRuns++ }; $wasHit = $rowHit[$y] }
Check 'the matrix is drawn as exactly 53 weekly columns' ($colRuns -eq 53) ("column runs with heat pixels = {0}" -f $colRuns)
Check 'the matrix is drawn as exactly 7 weekday rows' ($rowRuns -eq 7) ("row runs with heat pixels = {0}" -f $rowRuns)
Check 'drawn cell block is 53x16-3 wide and 7x16-3 tall' `
      (($orig.W -ge 843) -and ($orig.W -le 845) -and ($orig.H -eq 109)) `
      ("drawn {0}x{1}; 53 columns x 16px pitch - 3px gap = 845, 7 rows x 16 - 3 = 109" -f $orig.W,$orig.H)
$oX = $orig.X; $oY = $orig.Y
Write-Host ("today cell should be week {0} row {1} -> window-relative ({2},{3})" -f `
            ([int](($appT - $gridStart).Days / 7)), (($appT - $gridStart).Days % 7), `
            ([int]($oX + 30 + [int](($appT-$gridStart).Days/7)*16)), ([int]($oY + 20 + (($appT-$gridStart).Days%7)*16)))

# ---- (ii)+(iii) classify every visible cell by its palette colour ----
$gotCount = @{ 0 = 0; 1 = 0; 2 = 0; 3 = 0; 4 = 0; 5 = 0 }
$unknown = 0; $sampled = 0; $firstUnknown = ''
for ($week = 0; $week -lt 53; $week++) {
  for ($row = 0; $row -lt 7; $row++) {
    $day = $gridStart.AddDays($week * 7 + $row)
    if ($day -gt $appT) { continue }
    $px = [int]($oX + 30 + $week * 16 + 6); $py = [int]($oY + 20 + $row * 16 + 6)
    $c = Get-BufPixel -Buf $buf -X $px -Y $py
    $sampled++
    $lvl = -1
    foreach ($i in 0..5) { if ($c.R -eq $heat[$i].R -and $c.G -eq $heat[$i].G -and $c.B -eq $heat[$i].B) { $lvl = $i; break } }
    if ($lvl -lt 0) { $unknown++; if ($firstUnknown -eq '') { $firstUnknown = "{0:yyyy-MM-dd} ({1},{2}) RGB({3},{4},{5})" -f $day,$px,$py,$c.R,$c.G,$c.B } }
    else { $gotCount[$lvl]++ }
  }
}
Write-Host ("sampled {0} cells (expected {1}); unclassified={2}{3}" -f $sampled,$visibleCells,$unknown, $(if ($firstUnknown) { " first: $firstUnknown" } else { '' }))
Check 'every sampled cell centre is exactly one of the 6 palette colours' ($unknown -eq 0) ("unclassified={0} {1}" -f $unknown,$firstUnknown)
Check 'sampled cell count equals the number of days in the 53-week window' ($sampled -eq $visibleCells) ("sampled={0} expected={1}" -f $sampled,$visibleCells)
Check 'all 6 level colours are rendered in the matrix' (@(0..5 | Where-Object { $gotCount[$_] -eq 0 }).Count -eq 0) `
      ("L0={0} L1={1} L2={2} L3={3} L4={4} L5={5}" -f $gotCount[0],$gotCount[1],$gotCount[2],$gotCount[3],$gotCount[4],$gotCount[5])
foreach ($i in 0..5) {
  Check ("cells at level {0} ({1}) == my own bucket count for that boundary set" -f $i, $heat[$i].Hex) `
        ($gotCount[$i] -eq $expCount[$i]) ("rendered={0} expected={1}" -f $gotCount[$i], $expCount[$i])
}
for ($i = 0; $i -le 5; $i++) {
  $n = Count-BufColor -Buf $buf -R $heat[$i].R -G $heat[$i].G -B $heat[$i].B -X $oX -Y $oY -W 878 -H 129
  Check ("independent whole-region pixel count for level {0} is non-zero" -f $i) ($n -gt 0) ("pixels={0}" -f $n)
}

# ---- (iv) hover one specific cell and read the tooltip ----
$hoverOff = 29
$hoverDay = $gridStart.AddDays($hoverOff)
$hw = [int]($hoverOff / 7); $hr = $hoverOff % 7
$tip = Read-TipAt -StatHwnd $stats -Sr $sr -Origin $orig -Week $hw -Row $hr -ProcId $app.Pid
[void](Save-Shot -Name 'r3-c2-hover-tooltip.png' -Hwnd $stats)
$tipCrop = Crop-Scale-Bmp -Bmp (Capture-Window -Hwnd $stats -FromScreen) -X ([math]::Max(0, 30)) -Y ([math]::Max(0, $hr*16 + 20 + $oY - 40)) -W 420 -H 120 -Scale 2
[void](Save-Bmp -Bmp $tipCrop -Name 'r3-c3-hover-zoom.png')
$hoverPom = [int]$days[$hoverDay.ToString('yyyy-MM-dd')].Pomodoros
$wdCn = @('周日','周一','周二','周三','周四','周五','周六')[[int]$hoverDay.DayOfWeek]
Write-Host ("hover cell = grid week {0} row {1} -> {2:yyyy-MM-dd}; tooltip='{3}'" -f $hw,$hr,$hoverDay,($tip -replace "`n",'\n'))
Check 'tooltip reports exactly the date of the hovered cell' ($tip -like ("*{0:yyyy-MM-dd} {1}*" -f $hoverDay,$wdCn)) `
      ("expected date '{0:yyyy-MM-dd} {1}' tooltip='{2}'" -f $hoverDay,$wdCn,($tip -replace "`n",'\n'))
Check 'tooltip focus minutes match history.json for that day' ($tip -like ("*专注 {0}*" -f (Format-Duration 199))) `
      ("expected '专注 {0}' tooltip='{1}'" -f (Format-Duration 199), ($tip -replace "`n",'\n'))
Check 'tooltip pomodoro count matches history.json for that day' ($tip -like ("*{0} 个番茄*" -f $hoverPom)) `
      ("expected '{0} 个番茄' tooltip='{1}'" -f $hoverPom, ($tip -replace "`n",'\n'))
[void][R3.Native]::SetCursorPos(1900, 1070); Start-Sleep -Milliseconds 700

# ---- (v) summary cards ----
$checks = [ordered]@{
  ValToday = $expToday; ValWeek = $expWeek; ValMonth = $expMonth
  ValTotal = $expTotal; ValStreak = "$streak"; ValBest = $expBest
  SubToday = "$todayPom 个番茄"; SubTotal = "$totalPom 个番茄"
  SubBest = $bestDay.ToString('yyyy-MM-dd'); TxtRange = "共 $($days.Count) 天有记录"
}
foreach ($k in $checks.Keys) {
  $got = Uia-Text $stats $k
  Check ("summary field {0} equals my own computation from history.json" -f $k) ($got -eq $checks[$k]) `
        ("rendered='{0}' expected='{1}'" -f $got, $checks[$k])
}

# ---- (vi) CSV export through the real SaveFileDialog ----
$csvPath = Join-Path $script:ShotDir 'r3-export.csv'
if (Test-Path $csvPath) { Remove-Item -Force $csvPath }
[void](Activate-App $stats)
$invoked = Uia-ClickName $stats '导出 CSV'
Start-Sleep -Milliseconds 1500
$dlg = [IntPtr]::Zero; $sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt 8 -and $dlg -eq [IntPtr]::Zero) {
  $cand = @(Get-WindowsForPid -ProcId $app.Pid | Where-Object { $_.Class -eq '#32770' })
  if ($cand.Count -gt 0) { $dlg = $cand[0].Hwnd }
  Start-Sleep -Milliseconds 300
}
Check '导出 CSV opens a native save dialog' ($invoked -and $dlg -ne [IntPtr]::Zero) ("invoked={0} dialog={1} title='{2}'" -f $invoked,$dlg,$(if ($dlg -ne [IntPtr]::Zero) { Get-Title $dlg } else { '-' }))
if ($dlg -ne [IntPtr]::Zero) {
  [void](Focus-Window $dlg); Start-Sleep -Milliseconds 400
  Paste-Text $csvPath; Start-Sleep -Milliseconds 500
  Send-VKey -Vk 0x0D; Start-Sleep -Milliseconds 1800
  $boxes = @(Get-WindowsForPid -ProcId $app.Pid | Where-Object { $_.Class -eq '#32770' })
  if ($boxes.Count -gt 0) { [void](Focus-Window $boxes[0].Hwnd); Start-Sleep -Milliseconds 300; Send-VKey -Vk 0x0D; Start-Sleep -Milliseconds 800 }
}
Check 'CSV file written to the path I typed into the dialog' (Test-Path $csvPath) ("path={0}" -f $csvPath)
if (Test-Path $csvPath) {
  $csvLines = @(Get-Content $csvPath -Encoding UTF8)
  $expLines = @('日期,专注分钟,番茄数')
  foreach ($k in ($days.Keys | Sort-Object)) { $expLines += ('{0},{1},{2}' -f $k, $days[$k].Minutes, $days[$k].Pomodoros) }
  Check 'CSV rows == history.json days (+1 header row)' ($csvLines.Count -eq $expLines.Count) ("csv={0} expected={1} header='{2}'" -f $csvLines.Count,$expLines.Count,$csvLines[0])
  $bad = @()
  for ($i = 0; $i -lt [math]::Min($csvLines.Count,$expLines.Count); $i++) { if ($csvLines[$i].Trim() -ne $expLines[$i]) { $bad += ("line {0}: '{1}' vs '{2}'" -f ($i+1),$csvLines[$i],$expLines[$i]) } }
  Check 'every CSV row matches my own derivation' ($bad.Count -eq 0) ($(if ($bad.Count -eq 0) { "all $($csvLines.Count) lines identical" } else { $bad -join ' ; ' }))
}

# ---- (i) Esc closes the statistics window ----
[void](Activate-App $stats); Send-VKey -Vk 0x1B; Start-Sleep -Milliseconds 900
Check 'Esc closes the statistics window' ((Get-StatsWindow -ProcId $app.Pid) -eq [IntPtr]::Zero) ("stats hwnd after Esc={0}" -f (Get-StatsWindow -ProcId $app.Pid))
$reopen = Open-Stats -Main $main -ProcId $app.Pid
Check 'Ctrl+I reopens the statistics window after it was closed' ($reopen -ne [IntPtr]::Zero) ("hwnd={0}" -f $reopen)

[void](Activate-App $main); Send-ForceQuit $main
[void](Wait-Exit -Pid2 $app.Pid -Sec 10)
[void](Stop-AllApp)
[void](Remove-ConfigFiles)
[void](Summary)
