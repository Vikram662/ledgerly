# Rebuild the vector masters and PNG assets with Windows System.Drawing.
# Name-independent ledger/check mark; the launcher supplies the outer mask.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$shapes = @(
    @{ Color = '#F8FAFC'; Points = @(156,112, 304,112, 304,156, 176,156, 176,356, 256,356, 256,400, 132,400, 132,136) },
    @{ Color = '#94A3B8'; Points = @(200,192, 304,192, 304,216, 200,216) },
    @{ Color = '#94A3B8'; Points = @(200,244, 272,244, 272,268, 200,268) },
    @{ Color = '#5EEAD4'; Points = @(222,306, 254,274, 300,320, 380,240, 412,272, 300,384) }
)
function Write-Mark([string]$path, [int]$size, [bool]$background, [double]$scale = 1) {
    $bitmap = [System.Drawing.Bitmap]::new($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)
    if ($background) { $graphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#0F172A')) }
    $factor = $size / 512.0 * $scale
    $offset = $size * (1 - $scale) / 2
    foreach ($shape in $shapes) {
        $points = [System.Drawing.PointF[]]::new($shape.Points.Count / 2)
        for ($i = 0; $i -lt $points.Count; $i++) {
            $points[$i] = [System.Drawing.PointF]::new($offset + $shape.Points[2*$i]*$factor, $offset + $shape.Points[2*$i+1]*$factor)
        }
        $brush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($shape.Color))
        $graphics.FillPolygon($brush, $points)
        $brush.Dispose()
    }
    $stream = [System.IO.MemoryStream]::new()
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    [System.IO.File]::WriteAllBytes((Join-Path $root $path), $stream.ToArray())
    $stream.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}
$polygons = foreach ($shape in $shapes) {
    $pairs = for ($i = 0; $i -lt $shape.Points.Count; $i += 2) { '{0},{1}' -f $shape.Points[$i], $shape.Points[$i+1] }
    '<polygon fill="{0}" points="{1}" />' -f $shape.Color, ($pairs -join ' ')
}
foreach ($variant in @('app_icon', 'app_icon_foreground')) {
    $background = if ($variant -eq 'app_icon') { '<rect width="512" height="512" fill="#0F172A" />' } else { '' }
    $svg = '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">' + "`n" + $background + "`n" + ($polygons -join "`n") + "`n</svg>"
    [System.IO.File]::WriteAllText((Join-Path $root "assets/icon/$variant.svg"), $svg)
}
Write-Mark 'assets/icon/app_icon.png' 1024 $true
Write-Mark 'assets/icon/app_icon_foreground.png' 1024 $false
Write-Mark 'assets/logo/app_icon.png' 1024 $true
Write-Mark 'assets/icon/splash_logo.png' 512 $false
# Android 12 masks its splash icon; keep the mark inside the safe circle.
Write-Mark 'assets/icon/splash_android12.png' 960 $false 0.65
Write-Output 'Brand SVG and PNG assets regenerated.'
