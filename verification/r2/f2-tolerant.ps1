# f2-tolerant.ps1 -- F2: one invalid value must not discard the whole config + stats
. (Join-Path $PSScriptRoot 'lib2.ps1')

$today = (Get-Date).ToString('yyyy-MM-dd')
$KEYS = @('FocusMinutes','ShortBreakMinutes','LongBreakMinutes','LongBreakInterval','AutoStartNext',
 'SoundEnabled','KeepScreenAwake','AlwaysOnTop','NotifyOnPhaseEnd','FocusLock','AutoBigScreenOnFocus',
 'Theme','UseMicaBackdrop','BigScreen','BigScreenTopmost','HasWindowBounds','WindowLeft','WindowTop',
 'WindowWidth','WindowHeight','StatsDate','CompletedToday','FocusMinutesToday','TotalCompleted',
 'StreakDays','LastCompletedDate')

function Get-Val($obj, [string]$key) {
  if ($null -eq $obj) { return '<no file>' }
  $p = $obj.PSObject.Properties[$key]
  if ($null -eq $p) { return '<missing>' }
  return $p.Value
}

function Show-Case([string]$title, [string]$json, [string[]]$track) {
  Write-Settings $json
  $before = try { Read-Settings } catch { $null }
  Write-Host "`n=== $title ==="
  Write-Host "--- before (raw file) ---"
  Write-Host $json
  $r = Start-App
  Start-Sleep -Seconds 7
  Check "$title : started with a visible window (no crash / no dialog)" ($r.Hwnd -ne [IntPtr]::Zero) "hwnd=$($r.Hwnd) exited=$($r.Proc.HasExited)"
  $title2 = Get-Title $r.Hwnd
  Write-Host "  window title = '$title2'"
  Send-ForceQuit -Hwnd $r.Hwnd
  $ok = Wait-Exit -Pid2 $r.Proc.Id -Sec 10
  Start-Sleep -Milliseconds 600
  $after = Read-Settings
  Write-Host "--- key-by-key (before -> after) ---"
  foreach ($k in $KEYS) {
    $b = Get-Val $before $k; $a = Get-Val $after $k
    $mark = if ("$b" -eq "$a") { '  ' } else { ' *' }
    Write-Host ("{0} {1,-22} {2,-28} -> {3}" -f $mark, $k, "$b", "$a")
  }
  Check "$title : exit was clean and settings.json rewritten" $ok "exited=$ok file exists=$(Test-Path $script:SettingsPath)"
  return [pscustomobject]@{ Title=$title; Before=$before; After=$after; ExitOk=$ok }
}

# -------- case A: invalid enum, everything else valid & non-default --------
$jsonA = @"
{
  "FocusMinutes": 45,
  "ShortBreakMinutes": 7,
  "LongBreakMinutes": 20,
  "LongBreakInterval": 3,
  "AutoStartNext": false,
  "SoundEnabled": false,
  "KeepScreenAwake": false,
  "AlwaysOnTop": false,
  "NotifyOnPhaseEnd": false,
  "FocusLock": false,
  "AutoBigScreenOnFocus": false,
  "Theme": "Bogus",
  "UseMicaBackdrop": false,
  "BigScreen": "Full",
  "BigScreenTopmost": false,
  "HasWindowBounds": false,
  "WindowLeft": 0,
  "WindowTop": 0,
  "WindowWidth": 640,
  "WindowHeight": 780,
  "StatsDate": "$today",
  "CompletedToday": 5,
  "FocusMinutesToday": 150,
  "TotalCompleted": 42,
  "StreakDays": 7,
  "LastCompletedDate": "$today"
}
"@
$a = Show-Case 'A-invalid-enum' $jsonA

Check 'A: stats survive (CompletedToday 5)' ($a.After.CompletedToday -eq 5) "before=$($a.Before.CompletedToday) after=$($a.After.CompletedToday)"
Check 'A: stats survive (FocusMinutesToday 150)' ($a.After.FocusMinutesToday -eq 150) "before=$($a.Before.FocusMinutesToday) after=$($a.After.FocusMinutesToday)"
Check 'A: stats survive (TotalCompleted 42)' ($a.After.TotalCompleted -eq 42) "before=$($a.Before.TotalCompleted) after=$($a.After.TotalCompleted)"
Check 'A: stats survive (StreakDays 7)' ($a.After.StreakDays -eq 7) "before=$($a.Before.StreakDays) after=$($a.After.StreakDays)"
Check 'A: StatsDate kept (today)' ($a.After.StatsDate -eq $today) "before=$($a.Before.StatsDate) after=$($a.After.StatsDate)"
Check 'A: only the bad field fell back (Theme Bogus -> System)' ($a.After.Theme -eq 'System') "after=$($a.After.Theme)"
foreach ($pair in @(@('FocusMinutes',45),@('ShortBreakMinutes',7),@('LongBreakMinutes',20),@('LongBreakInterval',3),
                    @('BigScreen','Full'),@('AutoStartNext',$false),@('UseMicaBackdrop',$false),@('TopmostBool',$false))) { }
Check 'A: FocusMinutes kept 45' ($a.After.FocusMinutes -eq 45) "after=$($a.After.FocusMinutes)"
Check 'A: ShortBreakMinutes kept 7' ($a.After.ShortBreakMinutes -eq 7) "after=$($a.After.ShortBreakMinutes)"
Check 'A: LongBreakMinutes kept 20' ($a.After.LongBreakMinutes -eq 20) "after=$($a.After.LongBreakMinutes)"
Check 'A: LongBreakInterval kept 3' ($a.After.LongBreakInterval -eq 3) "after=$($a.After.LongBreakInterval)"
Check 'A: BigScreen kept Full' ($a.After.BigScreen -eq 'Full') "after=$($a.After.BigScreen)"
Check 'A: bool false values kept false' (-not $a.After.AutoStartNext -and -not $a.After.UseMicaBackdrop -and -not $a.After.AlwaysOnTop -and -not $a.After.SoundEnabled) "AutoStart=$($a.After.AutoStartNext) Mica=$($a.After.UseMicaBackdrop) Topmost=$($a.After.AlwaysOnTop) Sound=$($a.After.SoundEnabled)"
Check 'A: LastCompletedDate kept' ($a.After.LastCompletedDate -eq $today) "after=$($a.After.LastCompletedDate)"

# -------- case B: type error on an int --------
$jsonB = @"
{
  "FocusMinutes": "abc",
  "StatsDate": "$today",
  "CompletedToday": 2,
  "FocusMinutesToday": 30,
  "TotalCompleted": 9,
  "StreakDays": 1,
  "AutoBigScreenOnFocus": false,
  "AutoStartNext": false,
  "Theme": "Light",
  "UseMicaBackdrop": false
}
"@
$b = Show-Case 'B-type-error' $jsonB
Check 'B: TotalCompleted kept 9' ($b.After.TotalCompleted -eq 9) "before=$($b.Before.TotalCompleted) after=$($b.After.TotalCompleted)"
Check 'B: CompletedToday kept 2' ($b.After.CompletedToday -eq 2) "before=$($b.Before.CompletedToday) after=$($b.After.CompletedToday)"
Check 'B: FocusMinutesToday kept 30' ($b.After.FocusMinutesToday -eq 30) "before=$($b.Before.FocusMinutesToday) after=$($b.After.FocusMinutesToday)"
Check 'B: StreakDays kept 1' ($b.After.StreakDays -eq 1) "before=$($b.Before.StreakDays) after=$($b.After.StreakDays)"
Check 'B: bad FocusMinutes fell back to default 25' ($b.After.FocusMinutes -eq 25) "before=$($b.Before.FocusMinutes) after=$($b.After.FocusMinutes)"
Check 'B: valid Theme Light kept' ($b.After.Theme -eq 'Light') "after=$($b.After.Theme)"

# -------- case C: truncated JSON (control: total fallback is acceptable here) --------
$jsonC = '{"FocusMinutes":25,"StatsDate":"' + $today + '","TotalCompleted":11,'
$c = Show-Case 'C-truncated' $jsonC
Check 'C: truncated file does not crash and is rewritten valid' ($null -ne $c.After) "after=$($c.After | ConvertTo-Json -Compress)"

Summary | Out-Null
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
