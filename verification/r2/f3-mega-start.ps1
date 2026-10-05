# f3-mega-start.ps1 -- F3: --start must not be ignored when combined with --bigscreen/--mega
. (Join-Path $PSScriptRoot 'lib2.ps1')
$today = (Get-Date).ToString('yyyy-MM-dd')
$vd = Get-VirtualDesktop
Write-Host "virtual desktop = $($vd.W)x$($vd.H) @ ($($vd.X),$($vd.Y))"

function BaseSettings([string]$bigScreen) {
  [ordered]@{
    FocusMinutes = 25; ShortBreakMinutes = 5; LongBreakMinutes = 15; LongBreakInterval = 4
    AutoStartNext = $false; SoundEnabled = $false; KeepScreenAwake = $false; AlwaysOnTop = $false
    NotifyOnPhaseEnd = $false; FocusLock = $false; AutoBigScreenOnFocus = $false
    Theme = 'Light'; UseMicaBackdrop = $false
    BigScreen = $bigScreen; BigScreenTopmost = $true
    HasWindowBounds = $false; WindowLeft = 0; WindowTop = 0; WindowWidth = 640; WindowHeight = 780
    StatsDate = $today; CompletedToday = 0; FocusMinutesToday = 0; TotalCompleted = 0; StreakDays = 0
    LastCompletedDate = ''
  } | ConvertTo-Json
}

function Run-Cli([string]$label, [string[]]$CliArgs, [bool]$expectBigScreen, [bool]$expectCounting) {
  Write-Settings (BaseSettings 'Mega')
  $r = Start-App -CliArgs $CliArgs
  Start-Sleep -Seconds 3
  $rect3 = Get-Rect $r.Hwnd
  Start-Sleep -Seconds 5   # total ~8s
  $rect = Get-Rect $r.Hwnd
  $t1 = Get-Title $r.Hwnd
  Start-Sleep -Seconds 3
  $t2 = Get-Title $r.Hwnd
  $secs = if ($t2 -match '^(\d+):(\d\d)') { [int]$Matches[1]*60 + [int]$Matches[2] } else { -1 }
  Write-Host "`n[$label] args='$($CliArgs -join ' ')'"
  Write-Host "   rect@3s = $($rect3.W)x$($rect3.H) @ ($($rect3.X),$($rect3.Y))"
  Write-Host "   rect@8s = $($rect.W)x$($rect.H) @ ($($rect.X),$($rect.Y))"
  Write-Host "   title@8s= '$t1'   title@11s= '$t2'   seconds=$secs"
  Save-Shot -Name "r2-f3-$label.png" -Hwnd $r.Hwnd | Out-Null
  $covers = ($rect.X -eq $vd.X -and $rect.Y -eq $vd.Y -and $rect.W -ge $vd.W -and $rect.H -ge $vd.H)
  Check "$label : window covers the whole virtual desktop" ($covers -eq $expectBigScreen) "rect=$($rect.W)x$($rect.H) @ ($($rect.X),$($rect.Y)) covers=$covers expected=$expectBigScreen"
  $counting = ($t1 -match '^2[34]:\d\d' -and $secs -lt 1500 -and $secs -gt 1380)
  Check "$label : countdown starts immediately" ($counting -eq $expectCounting) "title@8s='$t1' title@11s='$t2'"
  Send-Esc
  Start-Sleep -Milliseconds 800
  $rect2 = Get-Rect $r.Hwnd
  Check "$label : Esc returns to 640x780" ($rect2.W -eq 640 -and $rect2.H -eq 780) "$($rect2.W)x$($rect2.H) @ ($($rect2.X),$($rect2.Y))"
  Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 600
}

Run-Cli 'mega-start'  @('--mega','--start')        $true  $true
Run-Cli 'bigscreen-start' @('--bigscreen','--start') $true $true
Run-Cli 'mega-only'   @('--mega')                  $true  $false
Run-Cli 'start-only'  @('--start')                 $false $true

Summary | Out-Null
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
