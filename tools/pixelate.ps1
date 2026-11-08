<#
.SYNOPSIS
    Готовит скриншот для README: обрезает до области формы и пикселизирует названия расширений.

.DESCRIPTION
    Репозиторий публичный, а тестовые базы — клиентские: перед публикацией скриншота имена
    и синонимы расширений клиентов (и другие узнаваемые данные) нужно закрыть.

.PARAMETER Crop
    Область обрезки: x, y, ширина, высота (в пикселях исходного снимка).

.PARAMETER Blur
    Области пикселизации в координатах исходного снимка: "x,y,w,h;x,y,w,h;...".

.EXAMPLE
    tools\pixelate.ps1 -Src build\shots\s3.png -Dst docs\images\devtoolsenterprise-start.png -Crop 280,85,1250,170
#>
param(
    [Parameter(Mandatory)] [string]$Src,
    [Parameter(Mandatory)] [string]$Dst,
    [int[]]$Crop,
    [string]$Blur = '',
    [int]$Cell = 6
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Pixelate($bmp, [int]$x, [int]$y, [int]$w, [int]$h) {
    for ($i = $x; $i -lt $x + $w; $i += $Cell) {
        for ($j = $y; $j -lt $y + $h; $j += $Cell) {
            $x2 = [Math]::Min($i + $Cell, $x + $w); $y2 = [Math]::Min($j + $Cell, $y + $h)
            $r = 0; $g = 0; $b = 0; $n = 0
            for ($a = $i; $a -lt $x2; $a++) { for ($k = $j; $k -lt $y2; $k++) { $px = $bmp.GetPixel($a, $k); $r += $px.R; $g += $px.G; $b += $px.B; $n++ } }
            $avg = [Drawing.Color]::FromArgb([int]($r / $n), [int]($g / $n), [int]($b / $n))
            for ($a = $i; $a -lt $x2; $a++) { for ($k = $j; $k -lt $y2; $k++) { $bmp.SetPixel($a, $k, $avg) } }
        }
    }
}

$img = [Drawing.Bitmap]::FromFile((Resolve-Path $Src).Path)
$bmp = New-Object Drawing.Bitmap $img
$img.Dispose()
foreach ($area in ($Blur -split ';' | Where-Object { $_.Trim() })) {
    $v = [int[]]($area -split ',')
    Pixelate $bmp $v[0] $v[1] $v[2] $v[3]
}
$rect = if ($Crop) { New-Object Drawing.Rectangle $Crop[0], $Crop[1], $Crop[2], $Crop[3] } else { New-Object Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height }
$out = $bmp.Clone($rect, $bmp.PixelFormat)
$dir = Split-Path -Parent $Dst
if ($dir) { New-Item -ItemType Directory -Force $dir | Out-Null }
$out.Save([IO.Path]::GetFullPath($Dst), [Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose(); $out.Dispose()
"$Dst : $($rect.Width)x$($rect.Height)"
