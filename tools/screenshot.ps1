# 截取当前虚拟桌面（用于验证界面）
param([string]$Output = (Join-Path $PSScriptRoot '..\artifacts\screen.png'), [int]$Delay = 0)
Add-Type -AssemblyName System.Drawing
if ($Delay -gt 0) { Start-Sleep -Seconds $Delay }
Add-Type -AssemblyName System.Windows.Forms
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = [System.Drawing.Bitmap]::new($vs.Width, $vs.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($vs.Left, $vs.Top, 0, 0, [System.Drawing.Size]::new($vs.Width, $vs.Height))
$g.Dispose()
$dir = Split-Path -Parent $Output
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$bmp.Save($Output, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host ("截图完成: {0} ({1}x{2})" -f (Resolve-Path $Output), $vs.Width, $vs.Height)
