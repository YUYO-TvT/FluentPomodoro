# reg-b-cycle.ps1 -- regression: phase / long-break cycle driven by the real 跳过 button (UIA invoke)
. (Join-Path $PSScriptRoot 'lib2.ps1')
$today = (Get-Date).ToString('yyyy-MM-dd')

function BaseSettings([int]$interval) {
  [ordered]@{
    FocusMinutes = 25; ShortBreakMinutes = 5; LongBreakMinutes = 15; LongBreakInterval = $interval
    AutoStartNext = $false; SoundEnabled = $false; KeepScreenAwake = $false; AlwaysOnTop = $true
    NotifyOnPhaseEnd = $false; FocusLock = $false; AutoBigScreenOnFocus = $false
    Theme = 'Light'; UseMicaBackdrop = $false
    BigScreen = 'Mega'; BigScreenTopmost = $true
    HasWindowBounds = $false; WindowLeft = 0; WindowTop = 0; WindowWidth = 640; WindowHeight = 780
    StatsDate = $today; CompletedToday = 0; FocusMinutesToday = 0; TotalCompleted = 0; StreakDays = 0
    LastCompletedDate = ''
  } | ConvertTo-Json
}

function Read-Phase([IntPtr]$h) {
  $t = Get-Title $h
  $phase = if ($t -match '短休息') { 'S' } elseif ($t -match '长休息') { 'L' } elseif ($t -match '专注') { 'F' } else { '?' }
  $round = Uia-Text $h 'TxtRound'
  return [pscustomobject]@{ Phase = $phase; Title = ($t -split ' · ')[0]; Round = $round }
}

function Run-Cycle([int]$interval, [int]$steps) {
  Write-Settings (BaseSettings $interval)
  $r = Start-App
  $h = $r.Hwnd
  Start-Sleep -Seconds 7
  $seq = @()
  $snap = Read-Phase $h
  $seq += "$($snap.Phase)[$($snap.Round)]"
  $clicked = 0
  for ($i = 0; $i -lt $steps; $i++) {
    $ok = Uia-ClickName $h '跳过'
    if (-not $ok) { Write-Host "  ！could not invoke 跳过 (step $i)"; break }
    $clicked++
    Start-Sleep -Milliseconds 550
    $snap = Read-Phase $h
    $seq += "$($snap.Phase)[$($snap.Round)]"
  }
  Write-Host "`ninterval=$interval  sequence (init + $clicked skips):"
  Write-Host ("   " + ($seq -join ' -> '))
  Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 600
  return @{ Seq = $seq; Clicked = $clicked }
}

$x4 = Run-Cycle 4 12
$expected4 = @('F[第 1 / 4 个番茄]','S[短休息 · 放松一下]','F[第 2 / 4 个番茄]','S[短休息 · 放松一下]',
               'F[第 3 / 4 个番茄]','S[短休息 · 放松一下]','F[第 4 / 4 个番茄]','L[长休息 · 本轮已完成]',
               'F[第 1 / 4 个番茄]','S[短休息 · 放松一下]','F[第 2 / 4 个番茄]','S[短休息 · 放松一下]',
               'F[第 3 / 4 个番茄]')
Check 'interval=4 cycle is F S F S F S F L F S F S F' ($x4.Clicked -eq 12 -and ($x4.Seq -join '|') -eq ($expected4 -join '|')) "got: $($x4.Seq -join ' -> ')"

$x2 = Run-Cycle 2 9
$expected2 = @('F[第 1 / 2 个番茄]','S[短休息 · 放松一下]','F[第 2 / 2 个番茄]','L[长休息 · 本轮已完成]',
               'F[第 1 / 2 个番茄]','S[短休息 · 放松一下]','F[第 2 / 2 个番茄]','L[长休息 · 本轮已完成]',
               'F[第 1 / 2 个番茄]','S[短休息 · 放松一下]')
Check 'interval=2 cycle is F S F L F S F L F S' ($x2.Clicked -eq 9 -and ($x2.Seq -join '|') -eq ($expected2 -join '|')) "got: $($x2.Seq -join ' -> ')"

Summary | Out-Null
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
