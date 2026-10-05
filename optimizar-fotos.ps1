# Genera versiones ligeras de las imagenes para la web.
#   Fotografia/...      -> Fotografia_web/thumb/...  (miniaturas, 600 px)
#                       -> Fotografia_web/full/...   (visor, 1800 px)
#   Imagenes de la raiz -> img_web/...               (figuras 3D, previews, avatar, 1000 px)
# Uso:  powershell -ExecutionPolicy Bypass -File .\optimizar-fotos.ps1
# Solo procesa imagenes nuevas o modificadas, asi que se puede volver a ejecutar al anadir fotos.

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationCore
$root = $PSScriptRoot
$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }

function Save-Resized([string]$src, [string]$dst, [int]$maxSide, [long]$quality) {
    if ((Test-Path -LiteralPath $dst) -and ((Get-Item -LiteralPath $dst).LastWriteTime -ge (Get-Item -LiteralPath $src).LastWriteTime)) { return }
    
    $img = $null
    try {
        $img = [System.Drawing.Image]::FromFile($src)
    } catch {
        # Fallback para imagenes HEIC / HEIF codificadas que System.Drawing no abre directamente
        try {
            $fs = [System.IO.File]::OpenRead($src)
            $dec = [System.Windows.Media.Imaging.BitmapDecoder]::Create($fs, [System.Windows.Media.Imaging.BitmapCreateOptions]::None, [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
            $fs.Close()
            $ms = New-Object System.IO.MemoryStream
            $enc = New-Object System.Windows.Media.Imaging.JpegBitmapEncoder
            $enc.Frames.Add($dec.Frames[0])
            $enc.Save($ms)
            $ms.Position = 0
            $img = [System.Drawing.Image]::FromStream($ms)
        } catch {
            Write-Host "No se pudo procesar $src : $_"
            return
        }
    }

    try {
        # Respetar la orientacion EXIF de la camara/movil
        if ($img.PropertyIdList -contains 0x0112) {
            switch ($img.GetPropertyItem(0x0112).Value[0]) {
                3 { $img.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipNone) }
                6 { $img.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone) }
                8 { $img.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipNone) }
            }
        }
        $scale = [Math]::Min(1.0, $maxSide / [double][Math]::Max($img.Width, $img.Height))
        $w = [Math]::Max(1, [int]($img.Width * $scale))
        $h = [Math]::Max(1, [int]($img.Height * $scale))

        $bmp = New-Object System.Drawing.Bitmap $w, $h
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.DrawImage($img, 0, 0, $w, $h)
        $g.Dispose()

        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
        if ($dst -match '\.png$') {
            $bmp.Save($dst, [System.Drawing.Imaging.ImageFormat]::Png)
        } else {
            $ep = New-Object System.Drawing.Imaging.EncoderParameters 1
            $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), $quality
            $bmp.Save($dst, $jpegCodec, $ep)
        }
        $bmp.Dispose()
    } finally {
        if ($null -ne $img) { $img.Dispose() }
    }
}

# 1) Fotografia -> miniaturas + version visor
$photoRoot = Join-Path $root 'Fotografia'
$files = Get-ChildItem -LiteralPath $photoRoot -Recurse -File | Where-Object { $_.Extension -match '^\.(jpe?g|png)$' }
$i = 0
foreach ($f in $files) {
    $i++
    $rel = $f.FullName.Substring($photoRoot.Length + 1)
    Write-Host ("[{0}/{1}] {2}" -f $i, $files.Count, $rel)
    Save-Resized $f.FullName (Join-Path $root ('Fotografia_web\thumb\' + $rel)) 600 78
    Save-Resized $f.FullName (Join-Path $root ('Fotografia_web\full\' + $rel)) 1800 82
}

# 2) Imagenes de la raiz (figuras 3D, previews de proyectos, avatar)
$rootImgs = Get-ChildItem -LiteralPath $root -File | Where-Object { $_.Extension -match '^\.(jpe?g|png)$' }
foreach ($f in $rootImgs) {
    Write-Host ("[raiz] {0}" -f $f.Name)
    Save-Resized $f.FullName (Join-Path $root ('img_web\' + $f.Name)) 1000 82
}

Write-Host "Listo."
