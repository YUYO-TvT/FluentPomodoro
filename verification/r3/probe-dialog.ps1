# probe-dialog.ps1 -- find how to drive the app's native OpenFileDialog / OpenFolderDialog reliably
. (Join-Path $PSScriptRoot 'lib3.ps1')

[void](Stop-AllApp); [void](Remove-ConfigFiles)
Set-BaseSettings -Override @{ ShowClock = $false } | Out-Null
$app = Start-App; $main = $app.Hwnd
Start-Sleep -Seconds 2
Write-Host ("main hwnd={0}" -f $main)
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC)
Start-Sleep -Milliseconds 1000
Write-Host "--- settings panel control ids (main window) ---"
foreach ($e in (Uia-Dump $main)) {
  if ($e.Id -or $e.Type -match 'Button|Edit|Combo') { Write-Host ("   {0,-14} {1,-28} name='{2}'" -f $e.Id,$e.Type,$e.Name) }
}

function Dump-Dialog {
  param([IntPtr]$Dlg)
  Write-Host ("--- dialog hwnd={0} title='{1}' ---" -f $Dlg, (Get-Title $Dlg))
  $root = Uia-Root $Dlg
  if ($null -eq $root) { Write-Host '   <no UIA root>'; return }
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  foreach ($e in $all) {
    try {
      $r = $e.Current.BoundingRectangle
      Write-Host ("   id='{0}' type={1,-22} name='{2}' rect=({3},{4},{5},{6})" -f `
        $e.Current.AutomationId, $e.Current.ControlType.ProgrammaticName, $e.Current.Name,
        [int]$r.X,[int]$r.Y,[int]$r.Width,[int]$r.Height)
    } catch { }
  }
}

# --- OpenFileDialog ---
[void](Activate-App $main)
[void](Uia-ClickName $main '选择图片')
Start-Sleep -Milliseconds 1800
$dlg = [IntPtr]::Zero
foreach ($w in (Get-WindowsForPid -ProcId $app.Pid)) { if ($w.Class -eq '#32770') { $dlg = $w.Hwnd; break } }
Write-Host ("file dialog hwnd={0}" -f $dlg)
if ($dlg -ne [IntPtr]::Zero) {
  Dump-Dialog $dlg
  Write-Host ("foreground = {0}" -f [R3.Native]::GetForegroundWindow())
  Write-Host ("focused element = {0}" -f ([System.Windows.Automation.AutomationElement]::FocusedElement.Current | ForEach-Object { "id='$($_.AutomationId)' type=$($_.ControlType.ProgrammaticName) name='$($_.Name)'" }))
  # try the UIA route: set the filename Edit's value, then invoke the 打开 button
  $root = Uia-Root $dlg
  $editCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
  $edits = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $editCond)
  Write-Host ("edits found: {0}" -f $edits.Count)
  $target = $null
  foreach ($e in $edits) {
    if ($e.Current.IsEnabled) {
      try {
        $vp = $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        Write-Host ("   edit id='{0}' name='{1}' value='{2}'" -f $e.Current.AutomationId, $e.Current.Name, $vp.Current.Value)
        if ($e.Current.AutomationId -like '*1148*' -or $e.Current.AutomationId -eq '1001' -or $e.Current.Name -like '*文件名*') { $target = $e }
      } catch { }
    }
  }
  if ($null -eq $target -and $edits.Count -gt 0) { $target = $edits[$edits.Count-1] }
  if ($null -ne $target) {
    Write-Host ("-> setting value on id='{0}' name='{1}'" -f $target.Current.AutomationId, $target.Current.Name)
    try { $target.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue((Join-Path $script:AssetsDir 'bg-red.png')); Write-Host '   SetValue ok' } catch { Write-Host ("   SetValue failed: {0}" -f $_.Exception.Message) }
    Start-Sleep -Milliseconds 500
    $btnCond = New-Object System.Windows.Automation.AndCondition(
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)),
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::IsEnabledProperty, $true)))
    $btns = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
    $open = $null
    foreach ($b in $btns) { Write-Host ("   button id='{0}' name='{1}'" -f $b.Current.AutomationId, $b.Current.Name); if ($b.Current.Name -like '打开*') { $open = $b } }
    if ($null -ne $open) { try { $open.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Write-Host '   invoked 打开' } catch { Write-Host ("   invoke failed: {0}" -f $_.Exception.Message) } }
  }
  Start-Sleep -Milliseconds 2000
  $still = @(Get-WindowsForPid -ProcId $app.Pid | Where-Object { $_.Class -eq '#32770' })
  Write-Host ("dialog still open: {0}" -f $still.Count)
  foreach ($w in $still) { [void](Focus-Window $w.Hwnd); Send-VKey -Vk 0x1B; Start-Sleep -Milliseconds 600 }
  Write-Host ("BackgroundImagePath now = '{0}'" -f (Read-Settings).BackgroundImagePath)
}
# close settings panel
[void](Activate-App $main); Send-VKey -Vk 0x1B; Start-Sleep -Milliseconds 800
Write-Host ("settings panel closed? SldBgOpacity found = {0}" -f ($null -ne (Uia-ById $main 'SldBgOpacity')))

# --- OpenFolderDialog ---
[void](Send-CtrlKey -Hwnd $main -Vk 0xBC); Start-Sleep -Milliseconds 900
[void](Activate-App $main)
[void](Uia-ClickName $main '选择文件夹')
Start-Sleep -Milliseconds 1800
$fdlg = [IntPtr]::Zero
foreach ($w in (Get-WindowsForPid -ProcId $app.Pid)) { if ($w.Class -eq '#32770') { $fdlg = $w.Hwnd; break } }
Write-Host ("folder dialog hwnd={0}" -f $fdlg)
if ($fdlg -ne [IntPtr]::Zero) { Dump-Dialog $fdlg; [void](Focus-Window $fdlg); Send-VKey -Vk 0x1B; Start-Sleep -Milliseconds 600 }

[void](Stop-AllApp); [void](Remove-ConfigFiles)
