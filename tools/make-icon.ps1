# 生成应用图标 Assets\app.ico（无需外部素材，纯 System.Drawing 绘制）
# 用法: pwsh -NoProfile -File tools\make-icon.ps1
param(
    [string]$Output = (Join-Path $PSScriptRoot '..\Assets\app.ico')
)

Add-Type -AssemblyName System.Drawing

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$master = 256.0

function New-RoundedPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$radius) {
    $rect = [System.Drawing.RectangleF]::new($x, $y, $w, $h)
    $d = $radius * 2.0
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
    $path.AddArc($rect.Right - $d, $rect.Y, $d, $d, 270, 90)
    $path.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
    $path.AddArc($rect.X, $rect.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

$inset = 8.0
$bodySize = $master - (2.0 * $inset)
$glossHeight = $bodySize * 0.46
$center = [System.Drawing.PointF]::new(128.0, 134.0)
$radius = 72.0
$thickness = 21.0
$white = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)

$bmp = [System.Drawing.Bitmap]::new(256, 256, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.Clear([System.Drawing.Color]::Transparent)

# 圆角方块 + 番茄红渐变
$body = [System.Drawing.RectangleF]::new([single]$inset, [single]$inset, [single]$bodySize, [single]$bodySize)
$bodyPath = New-RoundedPath $inset $inset $bodySize $bodySize 54.0
$bodyBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    $body,
    [System.Drawing.Color]::FromArgb(255, 255, 106, 92),
    [System.Drawing.Color]::FromArgb(255, 196, 43, 28),
    55.0)
$g.FillPath($bodyBrush, $bodyPath)

# 顶部高光
$gloss = [System.Drawing.RectangleF]::new([single]$inset, [single]$inset, [single]$bodySize, [single]$glossHeight)
$glossPath = New-RoundedPath $inset $inset $bodySize $glossHeight 50.0
$glossBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    $gloss,
    [System.Drawing.Color]::FromArgb(64, 255, 255, 255),
    [System.Drawing.Color]::FromArgb(0, 255, 255, 255),
    90.0)
$g.FillPath($glossBrush, $glossPath)

# 表盘圆环（右上留缺口表示进度）
$pen = [System.Drawing.Pen]::new($white, [single]$thickness)
$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawArc($pen, [single]($center.X - $radius), [single]($center.Y - $radius),
    [single]($radius * 2), [single]($radius * 2), -60.0, 300.0)

# 顶部旋钮
$knobR = 17.0
$knobBrush = [System.Drawing.SolidBrush]::new($white)
$g.FillEllipse($knobBrush,
    [single]($center.X - $knobR),
    [single]($center.Y - $radius - $knobR + 6),
    [single]($knobR * 2), [single]($knobR * 2))
$knobPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 226, 69, 58), 7.0)
$g.DrawEllipse($knobPen,
    [single]($center.X - $knobR + 5),
    [single]($center.Y - $radius - $knobR + 11),
    [single](($knobR - 5) * 2), [single](($knobR - 5) * 2))

# 中央指针
$handPen = [System.Drawing.Pen]::new($white, 15.0)
$handPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$handPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawLine($handPen, $center, [System.Drawing.PointF]::new($center.X + 34.0, $center.Y - 34.0))

$g.Dispose()

$frames = @()
foreach ($size in $sizes) {
    $small = [System.Drawing.Bitmap]::new([int]$size, [int]$size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $sg = [System.Drawing.Graphics]::FromImage($small)
    $sg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $sg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $dest = [System.Drawing.Rectangle]::new(0, 0, [int]$size, [int]$size)
    $sg.DrawImage($bmp, $dest, 0, 0, 256, 256, [System.Drawing.GraphicsUnit]::Pixel)
    $sg.Dispose()

    $ms = [System.IO.MemoryStream]::new()
    $small.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $frames += , @{ Size = [int]$size; Bytes = $ms.ToArray() }
    $ms.Dispose()
    $small.Dispose()
}
$bmp.Dispose()

$outDir = Split-Path -Parent $Output
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

$fs = [System.IO.File]::Create($Output)
$bw = [System.IO.BinaryWriter]::new($fs)
$bw.Write([uint16]0)
$bw.Write([uint16]1)
$bw.Write([uint16]$frames.Count)

$offset = 6 + 16 * $frames.Count
foreach ($frame in $frames) {
    $dim = if ($frame.Size -ge 256) { 0 } else { $frame.Size }
    $bw.Write([byte]$dim)
    $bw.Write([byte]$dim)
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bw.Write([uint16]1)
    $bw.Write([uint16]32)
    $bw.Write([uint32]$frame.Bytes.Length)
    $bw.Write([uint32]$offset)
    $offset += $frame.Bytes.Length
}
foreach ($frame in $frames) { $bw.Write($frame.Bytes) }

$bw.Flush(); $bw.Dispose(); $fs.Dispose()
Write-Host ("已生成图标: {0} ({1} 字节, {2} 个尺寸)" -f (Resolve-Path $Output), (Get-Item $Output).Length, $frames.Count)
