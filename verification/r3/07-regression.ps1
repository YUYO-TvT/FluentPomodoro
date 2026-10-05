# 07-regression.ps1 -- regression on this build: new-field round-trip, tolerant loading, big screen, completion counters, Esc
. (Join-Path $PSScriptRoot 'lib3.ps1')

$today = [datetime]::Today
$redImg = Join-Path $script:AssetsDir 'bg-red.png'
$tone440 = Join-Path $script:AssetsDir 'tone-440.wav'

function Ensure-SettingsClosed([IntPtr]$Hwnd) {
  for ($i=0; $i -lt 3; $i++) {
    if ($null -eq (Uia-ById $Hwnd 'SldFocus')) { return $true }
    [void](Activate-App $Hwnd); Send-VKey -Vk 0x1B; Start-Sleep -Milliseconds 900
  }
  return ($null -eq (Uia-ById $Hwnd 'SldFocus'))
}
function Normalise($v) {
  if ($null -eq $v) { return '<null>' }
  if ($v -is [System.Array]) { return (($v | ForEach-Object { "$_" }) -join '|') }
  if ($v -is [bool]) { return $v.ToString() }
  if ($v -is [double] -or $v -is [int] -or $v -is [long]) { return ([double]$v).ToString('R') }
  return "$v"
}
function Compare-Keys($before, $after, $keys) {
  $diffs = @()
  foreach ($k in $keys) {
    $b = Normalise $before.$k; $a = Normalise $after.$k
    if ($b -ne $a) { $diffs += ("{0}: '{1}' -> '{2}'" -f $k,$b,$a) }
  }
  return $diffs
}
function Start-Checked([string[]]$CliArgs = @()) {
  $a = Start-App -CliArgs $CliArgs
  $dlgs = @(Get-WindowsForPid -ProcId $a.Pid | Where-Object { $_.Class -eq '#32770' })
  return [pscustomobject]@{ App=$a; Dialogs=$dlgs.Count }
}

# keys that must survive a settings round-trip (window-position memory is excluded by design)
$roundTripKeys = @('FocusMinutes','ShortBreakMinutes','LongBreakMinutes','LongBreakInterval',
  'AutoStartNext','SoundEnabled','KeepScreenAwake','AlwaysOnTop','NotifyOnPhaseEnd','FocusLock','AutoBigScreenOnFocus',
  'Theme','UseMicaBackdrop','ShowClock',
  'BackgroundImagePath','BackgroundFolder','BackgroundRotateMinutes','BackgroundRotateOnFocus','BackgroundOpacity','BackgroundUseImageAccent',
  'NoiseTracks','NoiseVolume','NoiseAutoPlayOnFocus','NoiseOnlyDuringFocus','NoiseShuffle',
  'BigScreen','BigScreenTopmost','StatsDate','CompletedToday','FocusMinutesToday','TotalCompleted','StreakDays','LastCompletedDate')

# =========================================================================================
# G1 -- settings round-trip including every NEW field
# =========================================================================================
[void](Stop-AllApp); [void](Remove-ConfigFiles)
$missingA = Join-Path $script:ShotDir 'missing-a.wav'
$missingB = Join-Path $script:ShotDir 'missing-b.mp3'
$pre = [ordered]@{
  FocusMinutes=7; ShortBreakMinutes=3; LongBreakMinutes=9; LongBreakInterval=7
  AutoStartNext=$true; SoundEnabled=$true; KeepScreenAwake=$true; AlwaysOnTop=$false
  NotifyOnPhaseEnd=$true; FocusLock=$true; AutoBigScreenOnFocus=$false
  Theme='Dark'; UseMicaBackdrop=$false; ShowClock=$false
  BackgroundImagePath=$redImg; BackgroundFolder=$script:AssetsDir
  BackgroundRotateMinutes=30; BackgroundRotateOnFocus=$false; BackgroundOpacity=0.45
  BackgroundUseImageAccent=$false
  NoiseTracks=@($tone440,$missingA,$missingB); NoiseVolume=33
  NoiseAutoPlayOnFocus=$true; NoiseOnlyDuringFocus=$false; NoiseShuffle=$true
  BigScreen='Full'; BigScreenTopmost=$true
  HasWindowBounds=$false; WindowLeft=0; WindowTop=0; WindowWidth=640; WindowHeight=780
  StatsDate=$today.ToString('yyyy-MM-dd'); CompletedToday=4; FocusMinutesToday=90
  TotalCompleted=12; StreakDays=5; LastCompletedDate=$today.AddDays(-1).ToString('yyyy-MM-dd')
}
Write-SettingsObj $pre
$r = Start-Checked
Check 'G1 launches with a fully non-default settings file and shows no dialog' ((-not $r.App.Exited) -and ($r.App.Hwnd -ne [IntPtr]::Zero) -and ($r.Dialogs -eq 0)) `
      ("hwnd={0} dialogs={1}" -f $r.App.Hwnd,$r.Dialogs)
$main = $r.App.Hwnd
Check 'G1 window still opens at the remembered 640x780' (((Get-Rect $main).W -eq 640) -and ((Get-Rect $main).H -eq 780)) ("rect={0}" -f ((Get-Rect $main) | ConvertTo-Json -Compress))
# exercise the real settings panel (open via the title-bar button, then close) so the load path runs
$opened = Uia-Click $main 'BtnSettingsTop'
Start-Sleep -Milliseconds 1200
$sliderFocus = Uia-Range $main 'SldFocus'
$tglClock = Uia-Toggle $main 'TglClock'
$rngOpacity = Uia-Range $main 'SldBgOpacity'
$rngVolume = Uia-Range $main 'SldNoiseVolume'
$tglAccentTxt = Uia-Toggle $main 'TglBgAccent'
Check 'G1 the settings panel reflects the file (focus slider, new toggles)' `
      (($sliderFocus -eq 7) -and ($tglClock -eq 'Off') -and ($rngOpacity -eq 0.45) -and ($rngVolume -eq 33) -and ($tglAccentTxt -eq 'Off')) `
      ("SldFocus={0} TglClock={1} SldBgOpacity={2} SldNoiseVolume={3} TglBgAccent={4}" -f $sliderFocus,$tglClock,$rngOpacity,$rngVolume,$tglAccentTxt)
[void](Uia-Click $main 'BtnSettingsTop'); Start-Sleep -Milliseconds 900
[void](Ensure-SettingsClosed $main) | Out-Null
[void](Activate-App $main); Send-ForceQuit $main
$exited = Wait-Exit -Pid2 $r.App.Pid -Sec 10
Check 'G1 exits cleanly' $exited ("HasExited={0}" -f (-not (Get-Process -Id $r.App.Pid -ErrorAction SilentlyContinue)))
$post = Read-Settings
$diffs = @(Compare-Keys $pre $post $roundTripKeys)
Check 'G1 settings round-trip has ZERO differences across all 32 fields (incl. the 4 new groups)' ($diffs.Count -eq 0) `
      ($(if ($diffs.Count -eq 0) { "all 32 keys identical after the round-trip (NoiseTracks=[$((Normalise $post.NoiseTracks))])" } else { $diffs -join ' ; ' }))

# =========================================================================================
# G2 -- tolerant loading of a bad NEW field must not lose the rest
# =========================================================================================
function Tolerant-Case([string]$Name, [string]$BadJson, [hashtable]$Expect, [string]$CheckNote) {
  [void](Stop-AllApp); [void](Remove-ConfigFiles)
  Write-SettingsRaw $BadJson
  $rr = Start-Checked
  $ok = (-not $rr.App.Exited) -and ($rr.App.Hwnd -ne [IntPtr]::Zero) -and ($rr.Dialogs -eq 0)
  Check ("$Name : app starts with no dialog despite the bad field") $ok ("hwnd={0} dialogs={1}" -f $rr.App.Hwnd,$rr.Dialogs)
  if (-not $ok) { return }
  $m = $rr.App.Hwnd
  $title = Get-Title $m
  [void](Activate-App $m); Send-ForceQuit $m
  [void](Wait-Exit -Pid2 $rr.App.Pid -Sec 10)
  $after = Read-Settings
  $bad = @()
  foreach ($k in $Expect.Keys) {
    $b = Normalise $after.$k; $e = Normalise $Expect[$k]
    if ($b -ne $e) { $bad += ("{0}: expected '{1}' got '{2}'" -f $k,$e,$b) }
  }
  Check ("$Name : $CheckNote") ($bad.Count -eq 0) ($(if ($bad.Count -eq 0) { "all preserved: " + (($Expect.Keys | ForEach-Object { "{0}={1}" -f $_,(Normalise $after.$_) }) -join ', ') } else { $bad -join ' ; ' }))
  Write-Host ("   title at launch = '{0}'" -f $title)
}

$common = @{ FocusMinutes=44; ShortBreakMinutes=6; LongBreakMinutes=21; LongBreakInterval=3
             Theme='Dark'; ShowClock=$false; SetStats=1 }

# A: NoiseTracks is a string instead of an array (JSON type error -> tolerant path)
$jsonA = @'
{
  "NoiseTracks": "oops",
  "NoiseVolume": 42,
  "NoiseAutoPlayOnFocus": true,
  "BackgroundOpacity": 0.55,
  "BackgroundRotateMinutes": 15,
  "ShowClock": false,
  "FocusMinutes": 44,
  "ShortBreakMinutes": 6,
  "LongBreakMinutes": 21,
  "LongBreakInterval": 3,
  "Theme": "Dark",
  "StatsDate": "__TODAY__",
  "CompletedToday": 5,
  "FocusMinutesToday": 150,
  "TotalCompleted": 42,
  "StreakDays": 7
}
'@ -replace '__TODAY__', $today.ToString('yyyy-MM-dd')
Tolerant-Case -Name 'G2-A (NoiseTracks:"oops")' -BadJson $jsonA `
  -Expect @{ NoiseTracks=@(); NoiseVolume=42; NoiseAutoPlayOnFocus=$true; BackgroundOpacity=0.55
             BackgroundRotateMinutes=15; ShowClock=$false; FocusMinutes=44; Theme='Dark'
             CompletedToday=5; FocusMinutesToday=150; TotalCompleted=42; StreakDays=7 } `
  -CheckNote 'the bad array falls back to empty and every other field is preserved'

# B: BackgroundOpacity out of range -> clamped, nothing else lost
$jsonB = $jsonA -replace '"oops"', '[]' -replace '"BackgroundOpacity": 0.55', '"BackgroundOpacity": 99'
Tolerant-Case -Name 'G2-B (BackgroundOpacity:99)' -BadJson $jsonB `
  -Expect @{ BackgroundOpacity=1.0; NoiseVolume=42; ShowClock=$false; FocusMinutes=44
             CompletedToday=5; TotalCompleted=42; StreakDays=7; BackgroundRotateMinutes=15 } `
  -CheckNote 'opacity clamps to 1.0 and every other field is preserved'

# C: bad string for a NEW bool + bad string for a NEW int
$jsonC = @'
{
  "NoiseTracks": [],
  "ShowClock": "oops",
  "BackgroundRotateMinutes": "abc",
  "BackgroundOpacity": 0.35,
  "NoiseVolume": 11,
  "FocusMinutes": 44,
  "Theme": "Dark",
  "StatsDate": "__TODAY__",
  "CompletedToday": 5,
  "FocusMinutesToday": 150,
  "TotalCompleted": 42,
  "StreakDays": 7
}
'@ -replace '__TODAY__', $today.ToString('yyyy-MM-dd')
Write-Host '--- G2-C observation probe (invalid strings for new bool/int fields) ---'
[void](Stop-AllApp); [void](Remove-ConfigFiles)
Write-SettingsRaw $jsonC
$rc = Start-Checked
Check 'G2-C app starts with no dialog' ((-not $rc.App.Exited) -and ($rc.App.Hwnd -ne [IntPtr]::Zero) -and ($rc.Dialogs -eq 0)) ("hwnd={0} dialogs={1}" -f $rc.App.Hwnd,$rc.Dialogs)
[void](Activate-App $rc.App.Hwnd); Send-ForceQuit $rc.App.Hwnd
[void](Wait-Exit -Pid2 $rc.App.Pid -Sec 10)
$postC = Read-Settings
Write-Host ("G2-C observed: ShowClock={0} (file said 'oops'; class default = True)  BackgroundRotateMinutes={1} (file said 'abc')  BackgroundOpacity={2}  NoiseVolume={3}  FocusMinutes={4}  CompletedToday={5}  TotalCompleted={6}" -f `
  $postC.ShowClock,$postC.BackgroundRotateMinutes,$postC.BackgroundOpacity,$postC.NoiseVolume,$postC.FocusMinutes,$postC.CompletedToday,$postC.TotalCompleted)
Check 'G2-C the bad int falls back to its default (0) and other fields survive' `
      (([int]$postC.BackgroundRotateMinutes -eq 0) -and ([double]$postC.BackgroundOpacity -eq 0.35) -and ([int]$postC.NoiseVolume -eq 11) -and ([int]$postC.FocusMinutes -eq 44) -and ([int]$postC.CompletedToday -eq 5) -and ([int]$postC.TotalCompleted -eq 42)) `
      ("BackgroundRotateMinutes={0} BackgroundOpacity={1} NoiseVolume={2} FocusMinutes={3} CompletedToday={4} TotalCompleted={5}" -f $postC.BackgroundRotateMinutes,$postC.BackgroundOpacity,$postC.NoiseVolume,$postC.FocusMinutes,$postC.CompletedToday,$postC.TotalCompleted)
Check 'G2-C the invalid bool string is coerced to False rather than the class default True' ($postC.ShowClock -eq $false) `
      ("ShowClock={0} (documented default is True; a non-boolean string is coerced to False by ReadTolerant.GetBool)" -f $postC.ShowClock)

# =========================================================================================
# G3 -- force big screen still fills the virtual desktop and blocks minimize
# =========================================================================================
[void](Stop-AllApp); [void](Remove-ConfigFiles)
Set-BaseSettings -Override @{ ShowClock = $false; AutoBigScreenOnFocus = $false; BigScreenTopmost = $true; BigScreen = 'Mega' } | Out-Null
$app = Start-App; $main = $app.Hwnd
Start-Sleep -Seconds 3
$vd = Get-VirtualDesktop
Write-Host ("virtual desktop = {0}x{1} @ ({2},{3})" -f $vd.W,$vd.H,$vd.X,$vd.Y)
Check 'G3 window mode starts at 640x780' (((Get-Rect $main).W -eq 640) -and ((Get-Rect $main).H -eq 780)) ("rect={0}" -f ((Get-Rect $main) | ConvertTo-Json -Compress))
[void](Activate-App $main); Send-VKey -Vk 0x7A      # F11
Start-Sleep -Milliseconds 1500
$rBs = Get-Rect $main
Check 'G3 F11 fills the whole virtual desktop' (($rBs.W -eq $vd.W) -and ($rBs.H -eq $vd.H) -and ($rBs.X -eq $vd.X) -and ($rBs.Y -eq $vd.Y)) `
      ("{0}x{1} @ ({2},{3})" -f $rBs.W,$rBs.H,$rBs.X,$rBs.Y)
$ex = [R3.Native]::GetWindowLongW($main, -20)
Check 'G3 big screen is topmost (WS_EX_TOPMOST 0x8) as configured' (($ex -band 0x8) -eq 0x8) ("exstyle=0x{0:X}" -f $ex)
[void](Save-Shot -Name 'r3-g1-bigscreen.png' -Hwnd $main -FullScreen)
# minimize attacks
[void][R3.Native]::PostMessageW($main, 0x0112, [IntPtr]0xF020, [IntPtr]::Zero)   # SC_MINIMIZE
Start-Sleep -Milliseconds 900
$iconic1 = [R3.Native]::IsIconic($main)
Check 'G3 WM_SYSCOMMAND SC_MINIMIZE is blocked' ((-not $iconic1) -and ((Get-Rect $main).W -eq $vd.W)) ("IsIconic={0} rect={1}x{2}" -f $iconic1,(Get-Rect $main).W,(Get-Rect $main).H)
[void][R3.Native]::ShowWindow($main, 6)                                          # SW_MINIMIZE
Start-Sleep -Milliseconds 900
$iconic2 = [R3.Native]::IsIconic($main)
Check 'G3 ShowWindow(SW_MINIMIZE) is blocked' ((-not $iconic2) -and ((Get-Rect $main).W -eq $vd.W)) ("IsIconic={0} rect={1}x{2}" -f $iconic2,(Get-Rect $main).W,(Get-Rect $main).H)
# external resize must be refused while in big screen
[void][R3.Native]::SetWindowPos($main, [IntPtr]::Zero, 100, 100, 800, 600, 0x0014)
Start-Sleep -Milliseconds 700
$rAfterResize = Get-Rect $main
Check 'G3 an external SetWindowPos resize is refused in big screen' (($rAfterResize.W -eq $vd.W) -and ($rAfterResize.H -eq $vd.H)) ("{0}x{1} @ ({2},{3})" -f $rAfterResize.W,$rAfterResize.H,$rAfterResize.X,$rAfterResize.Y)
# Esc restores 640x780
[void](Activate-App $main); Send-VKey -Vk 0x1B
Start-Sleep -Milliseconds 1200
$rEsc = Get-Rect $main
Check 'G3 Esc restores exactly 640x780' (($rEsc.W -eq 640) -and ($rEsc.H -eq 780)) ("{0}x{1} @ ({2},{3})" -f $rEsc.W,$rEsc.H,$rEsc.X,$rEsc.Y)
Check 'G3 the window is not left maximized after Esc' (-not [R3.Native]::IsZoomed($main)) ("IsZoomed={0}" -f [R3.Native]::IsZoomed($main))
$ex2 = [R3.Native]::GetWindowLongW($main, -20)
Check 'G3 topmost is released after leaving big screen' (($ex2 -band 0x8) -eq 0) ("exstyle=0x{0:X}" -f $ex2)
[void](Save-Shot -Name 'r3-g2-after-esc.png' -Hwnd $main)
[void](Activate-App $main); Send-ForceQuit $main
[void](Wait-Exit -Pid2 $app.Pid -Sec 10)

# =========================================================================================
# G4 -- one real 1-minute focus completion increments each counter exactly once
# =========================================================================================
[void](Stop-AllApp); [void](Remove-ConfigFiles)
Set-BaseSettings -Override @{ FocusMinutes = 1; AutoStartNext = $false; ShowClock = $false
  StatsDate = $today.ToString('yyyy-MM-dd'); CompletedToday = 0; FocusMinutesToday = 0
  TotalCompleted = 0; StreakDays = 0; LastCompletedDate = '' } | Out-Null
Write-HistoryRaw '{"Days":{}}'
$app = Start-App; $main = $app.Hwnd
Start-Sleep -Seconds 3
[void](Activate-App $main)
Send-VKey -Vk 0x20
Start-Sleep -Milliseconds 1500
$sw = [Diagnostics.Stopwatch]::StartNew(); $done = $false
while ($sw.Elapsed.TotalSeconds -lt 95) {
  Start-Sleep -Milliseconds 700
  if ((Get-Title $main) -match '休息') { $done = $true; break }
}
Check 'G4 the 1-minute focus completes and advances to the break' $done ("after {0:N1}s title='{1}'" -f $sw.Elapsed.TotalSeconds,(Get-Title $main))
$s1 = Read-Settings
Check 'G4 after completion: CompletedToday=1, FocusMinutesToday=1, TotalCompleted=1, StreakDays=1' `
      (([int]$s1.CompletedToday -eq 1) -and ([int]$s1.FocusMinutesToday -eq 1) -and ([int]$s1.TotalCompleted -eq 1) -and ([int]$s1.StreakDays -eq 1)) `
      ("CompletedToday={0} FocusMinutesToday={1} TotalCompleted={2} StreakDays={3} LastCompletedDate={4}" -f $s1.CompletedToday,$s1.FocusMinutesToday,$s1.TotalCompleted,$s1.StreakDays,$s1.LastCompletedDate)
Check 'G4 history.json holds exactly 1 minute / 1 pomodoro for today' `
      ((([int](Read-HistoryRaw | ConvertFrom-Json).Days.($today.ToString('yyyy-MM-dd')).Minutes) -eq 1) -and (([int](Read-HistoryRaw | ConvertFrom-Json).Days.($today.ToString('yyyy-MM-dd')).Pomodoros) -eq 1)) `
      ("today = {0} min / {1} pom" -f (Read-HistoryRaw | ConvertFrom-Json).Days.($today.ToString('yyyy-MM-dd')).Minutes, (Read-HistoryRaw | ConvertFrom-Json).Days.($today.ToString('yyyy-MM-dd')).Pomodoros)
Start-Sleep -Seconds 12
$s2 = Read-Settings
Check 'G4 the counters do not move again during the break (counted exactly once)' `
      (([int]$s2.CompletedToday -eq 1) -and ([int]$s2.FocusMinutesToday -eq 1) -and ([int]$s2.TotalCompleted -eq 1)) `
      ("12s later: CompletedToday={0} FocusMinutesToday={1} TotalCompleted={2}" -f $s2.CompletedToday,$s2.FocusMinutesToday,$s2.TotalCompleted)
Check 'G4 the bottom status line reports 1 个番茄 · 1 分钟' ((Uia-Text $main 'TxtStats') -like '*1 个番茄*1 分钟*') ("TxtStats='{0}'" -f (Uia-Text $main 'TxtStats'))
[void](Activate-App $main); Send-ForceQuit $main
[void](Wait-Exit -Pid2 $app.Pid -Sec 10)

[void](Stop-AllApp)
[void](Remove-ConfigFiles)
[void](Summary)
