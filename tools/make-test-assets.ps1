# 生成功能测试所需的素材：三张不同主色调的背景图 + 一段测试音频
# 用法: pwsh -NoProfile -File tools\make-test-assets.ps1
param([string]$Output = (Join-Path $PSScriptRoot '..\artifacts\test-assets'))

Add-Type -AssemblyName System.Drawing
if (-not (Test-Path $Output)) { New-Item -ItemType Directory -Force -Path $Output | Out-Null }

function New-HueImage([string]$path, [int]$r1, [int]$g1, [int]$b1, [string]$name) {
    $bmp = [System.Drawing.Bitmap]::new(320, 240, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    # 同色系渐变（上浅下深），保证主色提取结果确定且色相明确
    $top = [System.Drawing.Color]::FromArgb(255, $r1, $g1, $b1)
    $bottom = [System.Drawing.Color]::FromArgb(255, [int]($r1 * 0.5), [int]($g1 * 0.5), [int]($b1 * 0.5))
    $rect = [System.Drawing.Rectangle]::new(0, 0, 320, 240)
    $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $top, $bottom, 90.0)
    $g.FillRectangle($brush, $rect)
    $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host ("生成 {0}: 主色 RGB({1},{2},{3})" -f $name, $top.R, $top.G, $top.B)
}

New-HueImage (Join-Path $Output 'bg-blue.png')  38 110 214 'bg-blue.png'
New-HueImage (Join-Path $Output 'bg-red.png')   212 56 48  'bg-red.png'
New-HueImage (Join-Path $Output 'bg-green.png') 46 168 84  'bg-green.png'

# 2 秒 440Hz 测试音（16bit 单声道 44.1kHz）
$wavPath = Join-Path $Output 'tone-440.wav'
$sampleRate = 44100
$seconds = 2.0
$count = [int]($sampleRate * $seconds)
$data = [byte[]]::new($count * 2)
for ($i = 0; $i -lt $count; $i++) {
    $v = [int16]([math]::Sin(2 * [math]::PI * 440.0 * $i / $sampleRate) * 0.25 * 32767)
    $data[$i * 2] = [byte]($v -band 0xFF)
    $data[$i * 2 + 1] = [byte](($v -shr 8) -band 0xFF)
}

$fs = [System.IO.File]::Create($wavPath)
$bw = [System.IO.BinaryWriter]::new($fs)
$bw.Write([byte[]][char[]]'RIFF')
$bw.Write([int](36 + $data.Length))
$bw.Write([byte[]][char[]]'WAVE')
$bw.Write([byte[]][char[]]'fmt ')
$bw.Write([int]16)
$bw.Write([int16]1)
$bw.Write([int16]1)
$bw.Write([int]$sampleRate)
$bw.Write([int]($sampleRate * 2))
$bw.Write([int16]2)
$bw.Write([int16]16)
$bw.Write([byte[]][char[]]'data')
$bw.Write([int]$data.Length)
$bw.Write($data)
$bw.Flush(); $bw.Dispose(); $fs.Dispose()
Write-Host ("生成 {0}: {1} 字节" -f (Split-Path -Leaf $wavPath), (Get-Item $wavPath).Length)

Get-ChildItem $Output | Select-Object Name, Length
