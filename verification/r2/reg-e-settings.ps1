# reg-e-settings.ps1 -- regression: settings round-trip (20 non-default values) + out-of-range clamping
. (Join-Path $PSScriptRoot 'lib2.ps1')
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
$today = (Get-Date).ToString('yyyy-MM-dd')

$nonDefault = [ordered]@{
  FocusMinutes = 7; ShortBreakMinutes = 3; LongBreakMinutes = 9; LongBreakInterval = 7
  AutoStartNext = $false; SoundEnabled = $false; KeepScreenAwake = $false; NotifyOnPhaseEnd = $false
  AlwaysOnTop = $false; FocusLock = $false; AutoBigScreenOnFocus = $false; BigScreenTopmost = $false
  UseMicaBackdrop = $false; Theme = 'Dark'; BigScreen = 'Full'
  HasWindowBounds = $true; WindowLeft = 200; WindowTop = 150; WindowWidth = 600; WindowHeight = 700
  StatsDate = $today; CompletedToday = 0; FocusMinutesToday = 0; TotalCompleted = 0; StreakDays = 0
  LastCompletedDate = ''
}
$track = @('FocusMinutes','ShortBreakMinutes','LongBreakMinutes','LongBreakInterval','AutoStartNext',
 'SoundEnabled','KeepScreenAwake','NotifyOnPhaseEnd','AlwaysOnTop','FocusLock','AutoBigScreenOnFocus',
 'BigScreenTopmost','UseMicaBackdrop','Theme','BigScreen','WindowLeft','WindowTop','WindowWidth','WindowHeight')
Write-Settings ($nonDefault | ConvertTo-Json)

$r = Start-App
$h = $r.Hwnd
Start-Sleep -Seconds 8
$rect = Get-Rect $h
Check 'window restores saved bounds 600x700 @ (200,150)' ($rect.W -eq 600 -and $rect.H -eq 700 -and $rect.X -eq 200 -and $rect.Y -eq 150) "$($rect.W)x$($rect.H) @ ($($rect.X),$($rect.Y))"

# open the settings panel and close it again (this is where round 1's overwrite bug lived)
$opened = Uia-Click $h 'BtnSettings'
Start-Sleep -Milliseconds 1200
$sld = Uia-ById $h 'SldFocus'
$br = if ($sld) { $sld.Current.BoundingRectangle } else { $null }
$inside = $null -ne $br -and $br.Width -gt 10 -and $br.Height -gt 0 -and $br.X -ge $rect.X -and ($br.X + $br.Width) -le ($rect.X + $rect.W)
Write-Host "settings panel: BtnSettings invoked=$opened  SldFocus rect=$br  inside window=$inside"
Check 'settings panel opens via the real button' ($opened -and $inside) "invoked=$opened SldFocus bounding=$br"
Save-Shot -Name 'r2-reg-settings-open.png' -Hwnd $h | Out-Null

# UI controls must show the saved values
$sliders = @{}
foreach ($id in 'SldFocus','SldShort','SldLong','SldInterval') {
  $e = Uia-ById $h $id
  if ($e) { $sliders[$id] = [int]$e.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern).Current.Value } else { $sliders[$id] = -1 }
}
$togg = @{}
foreach ($id in 'TglAutoStart','TglSound','TglKeepAwake','TglNotify','TglTopmost','TglLock','TglAutoBig','TglBigTopmost','TglMica') {
  $e = Uia-ById $h $id
  if ($e) { $togg[$id] = $e.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState.ToString() } else { $togg[$id] = '?' }
}
Write-Host ("UIA sliders: " + (($sliders.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '))
Write-Host ("UIA toggles: " + (($togg.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '))
Check 'UIA slider values match settings.json' ($sliders['SldFocus'] -eq 7 -and $sliders['SldShort'] -eq 3 -and $sliders['SldLong'] -eq 9 -and $sliders['SldInterval'] -eq 7) "focus=$($sliders['SldFocus']) short=$($sliders['SldShort']) long=$($sliders['SldLong']) interval=$($sliders['SldInterval'])"
Check 'UIA toggles show Off for the 6 false booleans' ($togg['TglAutoStart'] -eq 'Off' -and $togg['TglSound'] -eq 'Off' -and $togg['TglKeepAwake'] -eq 'Off' -and $togg['TglNotify'] -eq 'Off' -and $togg['TglTopmost'] -eq 'Off' -and $togg['TglBigTopmost'] -eq 'Off' -and $togg['TglMica'] -eq 'Off') (($togg.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')

Post-Key -Hwnd $h -Vk 0x1B   # Esc closes the settings panel (PostMessage: no focus needed)
Start-Sleep -Milliseconds 1200
Send-ForceQuit -Hwnd $h
[void](Wait-Exit -Pid2 $r.Proc.Id -Sec 10); Start-Sleep -Milliseconds 800
$after = Read-Settings
Write-Host "`n--- settings round-trip (written -> read back) ---"
$diff = 0
foreach ($k in $track) {
  $b = $nonDefault[$k]; $a = $after.$k
  $same = "$b" -eq "$a"
  if (-not $same) { $diff++ }
  Write-Host ("{0} {1,-22} {2,-10} -> {3}" -f $(if ($same) { '  ' } else { ' *' }), $k, "$b", "$a")
}
Check 'all 19 non-default values survive launch + settings open/close + exit' ($diff -eq 0) "$diff differences"
Check 'window bounds written back unchanged' ($after.WindowWidth -eq 600 -and $after.WindowHeight -eq 700 -and $after.WindowLeft -eq 200 -and $after.WindowTop -eq 150) "W=$($after.WindowWidth) H=$($after.WindowHeight) L=$($after.WindowLeft) T=$($after.WindowTop)"

# ---------------- out-of-range clamping ----------------
Write-Host "`n=== out-of-range values ==="
$range = [ordered]@{
  FocusMinutes = 999; ShortBreakMinutes = 0; LongBreakMinutes = -5; LongBreakInterval = 99
  AutoStartNext = $false; SoundEnabled = $false; KeepScreenAwake = $false; NotifyOnPhaseEnd = $false
  AlwaysOnTop = $false; FocusLock = $false; AutoBigScreenOnFocus = $false; BigScreenTopmost = $false
  UseMicaBackdrop = $false; Theme = 'Light'; BigScreen = 'Mega'
  HasWindowBounds = $false; WindowLeft = 0; WindowTop = 0; WindowWidth = 640; WindowHeight = 780
  StatsDate = $today; CompletedToday = 0; FocusMinutesToday = 0; TotalCompleted = 0; StreakDays = 0
  LastCompletedDate = ''
}
Write-Settings ($range | ConvertTo-Json)
$r = Start-App
$h = $r.Hwnd
Start-Sleep -Seconds 7
$t = Get-Title $h
Check 'FocusMinutes 999 -> 120 (title 2:00:00)' ($t -match '^2:00:00') "title='$t'"
Save-Shot -Name 'r2-reg-range.png' -Hwnd $h | Out-Null
Send-ForceQuit -Hwnd $h
[void](Wait-Exit -Pid2 $r.Proc.Id -Sec 10); Start-Sleep -Milliseconds 700
$after2 = Read-Settings
Check 'FocusMinutes clamped to 120' ($after2.FocusMinutes -eq 120) "value=$($after2.FocusMinutes)"
Check 'ShortBreakMinutes 0 -> 1' ($after2.ShortBreakMinutes -eq 1) "value=$($after2.ShortBreakMinutes)"
Check 'LongBreakMinutes -5 -> 5' ($after2.LongBreakMinutes -eq 5) "value=$($after2.LongBreakMinutes)"
Check 'LongBreakInterval 99 -> 12' ($after2.LongBreakInterval -eq 12) "value=$($after2.LongBreakInterval)"

Summary | Out-Null
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
