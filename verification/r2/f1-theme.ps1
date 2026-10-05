# f1-theme.ps1 -- F1: saved Theme in settings.json must be honoured on plain launch; CLI still overrides
. (Join-Path $PSScriptRoot 'lib2.ps1')
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

$today = (Get-Date).ToString('yyyy-MM-dd')

function New-FullSettings([string]$theme, [bool]$mica) {
  [ordered]@{
    FocusMinutes = 25; ShortBreakMinutes = 5; LongBreakMinutes = 15; LongBreakInterval = 4
    AutoStartNext = $true; SoundEnabled = $false; KeepScreenAwake = $true; AlwaysOnTop = $true
    NotifyOnPhaseEnd = $true; FocusLock = $false; AutoBigScreenOnFocus = $false
    Theme = $theme; UseMicaBackdrop = $mica
    BigScreen = 'Mega'; BigScreenTopmost = $true
    HasWindowBounds = $false; WindowLeft = 0; WindowTop = 0; WindowWidth = 640; WindowHeight = 780
    StatsDate = $today; CompletedToday = 0; FocusMinutesToday = 0; TotalCompleted = 0; StreakDays = 0
    LastCompletedDate = ''
  } | ConvertTo-Json
}

function Run-Case([string]$label, [string]$theme, [string[]]$CliArgs, [string]$expect) {
  Write-Settings (New-FullSettings -theme $theme -mica $false)
  $before = (Read-Settings).Theme
  $r = Start-App -CliArgs $CliArgs
  Start-Sleep -Seconds 7
  if ($r.Hwnd -eq [IntPtr]::Zero) { Check "$label - window" $false "no window"; return }
  $prof = Get-WindowColorProfile -Hwnd $r.Hwnd
  $pts = @()
  $rect = Get-Rect $r.Hwnd
  foreach ($dy in 120, 200, 300, 520) {
    $c = Get-Pixel -X ($rect.X + 18) -Y ($rect.Y + $dy)
    if ($c) { $pts += "$($c.R),$($c.G),$($c.B)" }
  }
  Write-Host "  [$label] theme-in-file=$theme args='$($CliArgs -join ' ')' modal=$($prof.Modal) avgR=$($prof.AvgR) leftEdge=[$($pts -join ' | ')]"
  Save-Shot -Name "r2-f1-$label.png" -Hwnd $r.Hwnd | Out-Null
  # clean exit so the app rewrites settings.json
  Send-ForceQuit -Hwnd $r.Hwnd
  $exited = Wait-Exit -Pid2 $r.Proc.Id -Sec 10
  Start-Sleep -Milliseconds 600
  $after = (Read-Settings).Theme
  $dark = [int](($prof.Modal -split ',')[0])
  $isDark = $dark -lt 90
  $ok = if ($expect -eq 'dark') { $isDark } else { -not $isDark }
  Check "$label renders $expect UI" $ok "modal=$($prof.Modal) avgR=$($prof.AvgR) (dark<90, light>=90)"
  return [pscustomobject]@{ Label=$label; Exited=$exited; ThemeBefore=$before; ThemeAfter=$after; Modal=$prof.Modal; AvgR=$prof.AvgR; Dark=$isDark; Pts=($pts -join '|') }
}

$rows = @()
$rows += Run-Case 'saved-dark-plain'    'Dark'  @()                'dark'
$rows += Run-Case 'saved-light-plain'   'Light' @()                'light'
$rows += Run-Case 'saved-dark-forcelight' 'Dark' @('--light')       'light'
$rows += Run-Case 'saved-light-forcedark' 'Light' @('--dark')       'dark'
$rows += Run-Case 'saved-dark-forcedark'  'Dark' @('--dark')        'dark'
$rows += Run-Case 'saved-system-plain'  'System' @()               'light'

Write-Host "`n--- F1 table ---"
$rows | Format-Table -AutoSize | Out-String | Write-Host

# saved Theme must survive a clean exit
foreach ($row in $rows) {
  if ($row.Label -like 'saved-*') {
    $expected = $row.Label -replace '^saved-([a-z]+)-.*$', '$1'
    $expected = (Get-Culture).TextInfo.ToTitleCase($expected)
    Check "$($row.Label): Theme in settings.json unchanged by plain/forced launch" ($row.ThemeAfter -eq $expected) "before=$($row.ThemeBefore) after=$($row.ThemeAfter) expected=$expected"
  }
}
Check 'all launches exited cleanly' (@($rows | Where-Object { -not $_.Exited }).Count -eq 0) (($rows | ForEach-Object { "$($_.Label)=$($_.Exited)" }) -join ' ')

Summary | Out-Null
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
