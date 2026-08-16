param(
    [Parameter(Mandatory = $true)][int]$X,
    [Parameter(Mandatory = $true)][int]$Y,
    [Parameter(Mandatory = $true)][int]$Width,
    [Parameter(Mandatory = $true)][int]$Height,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$Language = "",
    [double]$Scale = 1.0,
    [int]$Grayscale = 0,
    [string]$InputPath = ""
)

$ErrorActionPreference = "Stop"
$temporaryPng = Join-Path ([System.IO.Path]::GetTempPath()) ("MacroAutomator_OCR_{0}.png" -f [guid]::NewGuid().ToString("N"))

function Convert-ToBase64([string]$Text) {
    if ($null -eq $Text) {
        $Text = ""
    }
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
}

function Await-WinRT($AsyncOperation, [Type]$ResultType) {
    $asTaskMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq "AsTask" -and $_.IsGenericMethod -and
            $_.GetParameters().Count -eq 1
        } |
        Select-Object -First 1

    $task = $asTaskMethod.MakeGenericMethod($ResultType).Invoke($null, @($AsyncOperation))
    return $task.GetAwaiter().GetResult()
}

try {
    if ($Width -lt 1 -or $Height -lt 1) {
        throw "OCR capture width and height must both be greater than zero."
    }

    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Runtime.WindowsRuntime

    [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
    [Windows.Storage.FileAccessMode, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
    [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime] | Out-Null
    [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime] | Out-Null
    [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType = WindowsRuntime] | Out-Null
    [Windows.Graphics.Imaging.BitmapPixelFormat, Windows.Graphics.Imaging, ContentType = WindowsRuntime] | Out-Null
    [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
    [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
    [Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null

    $engine = $null
    if (-not [string]::IsNullOrWhiteSpace($Language)) {
        try {
            $languageObject = New-Object Windows.Globalization.Language($Language)
            $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($languageObject)
        }
        catch {
            $engine = $null
        }
    }
    if ($null -eq $engine) {
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    }
    if ($null -eq $engine) {
        throw "Windows could not create an OCR engine. Install a Windows language OCR pack and try again."
    }

    if ($Scale -le 0) {
        $Scale = 1.0
    }
    $sourceImage = $null
    $inputImageWidth = 0
    $inputImageHeight = 0
    if (-not [string]::IsNullOrWhiteSpace($InputPath)) {
        if (-not (Test-Path -LiteralPath $InputPath)) {
            throw "OCR input image not found: $InputPath"
        }
        $sourceImage = [Drawing.Image]::FromFile($InputPath)
        $inputImageWidth = [int]$sourceImage.Width
        $inputImageHeight = [int]$sourceImage.Height
        $Width = $inputImageWidth
        $Height = $inputImageHeight
    }

    $maximumDimension = [double][Windows.Media.Ocr.OcrEngine]::MaxImageDimension
    if ($maximumDimension -le 0) {
        $maximumDimension = 2600.0
    }
    $requestedWidth = [Math]::Max(1, [int][Math]::Round($Width * $Scale))
    $requestedHeight = [Math]::Max(1, [int][Math]::Round($Height * $Scale))
    $limitScale = [Math]::Min(1.0, $maximumDimension / [Math]::Max($requestedWidth, $requestedHeight))
    $effectiveScale = $Scale * $limitScale
    $ocrWidth = [Math]::Max(1, [int][Math]::Round($Width * $effectiveScale))
    $ocrHeight = [Math]::Max(1, [int][Math]::Round($Height * $effectiveScale))

    if ($null -ne $sourceImage) {
        try {
            $capturedBitmap = New-Object System.Drawing.Bitmap($sourceImage)
        }
        finally {
            $sourceImage.Dispose()
        }
    }
    else {
        $capturedBitmap = New-Object System.Drawing.Bitmap($Width, $Height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $captureGraphics = [Drawing.Graphics]::FromImage($capturedBitmap)
        try {
            $captureGraphics.CopyFromScreen($X, $Y, 0, 0, $capturedBitmap.Size, [Drawing.CopyPixelOperation]::SourceCopy)
        }
        finally {
            $captureGraphics.Dispose()
        }
    }

    $ocrBitmap = $capturedBitmap
    if ($ocrWidth -ne $Width -or $ocrHeight -ne $Height) {
        $ocrBitmap = New-Object System.Drawing.Bitmap($ocrWidth, $ocrHeight, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $resizeGraphics = [Drawing.Graphics]::FromImage($ocrBitmap)
        try {
            $resizeGraphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $resizeGraphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $resizeGraphics.DrawImage($capturedBitmap, 0, 0, $ocrWidth, $ocrHeight)
        }
        finally {
            $resizeGraphics.Dispose()
            $capturedBitmap.Dispose()
        }
    }

    if ($Grayscale -ne 0) {
        $grayBitmap = New-Object System.Drawing.Bitmap($ocrWidth, $ocrHeight, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $grayGraphics = [Drawing.Graphics]::FromImage($grayBitmap)
        try {
            $matrix = New-Object Drawing.Imaging.ColorMatrix
            $matrix.Matrix00 = 0.299; $matrix.Matrix01 = 0.299; $matrix.Matrix02 = 0.299
            $matrix.Matrix10 = 0.587; $matrix.Matrix11 = 0.587; $matrix.Matrix12 = 0.587
            $matrix.Matrix20 = 0.114; $matrix.Matrix21 = 0.114; $matrix.Matrix22 = 0.114
            $matrix.Matrix33 = 1.0; $matrix.Matrix44 = 1.0
            $attributes = New-Object Drawing.Imaging.ImageAttributes
            try {
                $attributes.SetColorMatrix($matrix)
                $destination = New-Object Drawing.Rectangle(0, 0, $ocrWidth, $ocrHeight)
                $grayGraphics.DrawImage($ocrBitmap, $destination, 0, 0, $ocrWidth, $ocrHeight, [Drawing.GraphicsUnit]::Pixel, $attributes)
            }
            finally {
                $attributes.Dispose()
            }
        }
        finally {
            $grayGraphics.Dispose()
            $ocrBitmap.Dispose()
        }
        $ocrBitmap = $grayBitmap
    }

    try {
        $ocrBitmap.Save($temporaryPng, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $ocrBitmap.Dispose()
    }

    $storageFile = Await-WinRT ([Windows.Storage.StorageFile]::GetFileFromPathAsync($temporaryPng)) ([Windows.Storage.StorageFile])
    $randomAccessStream = Await-WinRT ($storageFile.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    try {
        $decoder = Await-WinRT ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($randomAccessStream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $softwareBitmap = Await-WinRT ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        try {
            $ocrBitmapForEngine = [Windows.Graphics.Imaging.SoftwareBitmap]::Convert(
                $softwareBitmap, [Windows.Graphics.Imaging.BitmapPixelFormat]::Gray8)
            try {
                $ocrResult = Await-WinRT ($engine.RecognizeAsync($ocrBitmapForEngine)) ([Windows.Media.Ocr.OcrResult])
            }
            finally {
                $ocrBitmapForEngine.Dispose()
            }
        }
        finally {
            $softwareBitmap.Dispose()
        }
    }
    finally {
        $randomAccessStream.Dispose()
    }

    $coordinateFactor = 1.0 / $effectiveScale
    $output = New-Object System.Collections.Generic.List[string]
    $output.Add("TEXT`t$(Convert-ToBase64 $ocrResult.Text)")

    $angle = 0.0
    try {
        if ($null -ne $ocrResult.TextAngle) {
            $angle = [double]$ocrResult.TextAngle
        }
    }
    catch { }
    $output.Add("ANGLE`t$angle")

    foreach ($line in $ocrResult.Lines) {
        $lineLeft = [double]::PositiveInfinity
        $lineTop = [double]::PositiveInfinity
        $lineRight = [double]::NegativeInfinity
        $lineBottom = [double]::NegativeInfinity

        foreach ($word in $line.Words) {
            $bounds = $word.BoundingRect
            $wordX = [int][Math]::Round($bounds.X * $coordinateFactor)
            $wordY = [int][Math]::Round($bounds.Y * $coordinateFactor)
            $wordWidth = [Math]::Max(1, [int][Math]::Round($bounds.Width * $coordinateFactor))
            $wordHeight = [Math]::Max(1, [int][Math]::Round($bounds.Height * $coordinateFactor))
            $output.Add("WORD`t$(Convert-ToBase64 $word.Text)`t$wordX`t$wordY`t$wordWidth`t$wordHeight")

            $lineLeft = [Math]::Min($lineLeft, $wordX)
            $lineTop = [Math]::Min($lineTop, $wordY)
            $lineRight = [Math]::Max($lineRight, $wordX + $wordWidth)
            $lineBottom = [Math]::Max($lineBottom, $wordY + $wordHeight)
        }

        if (-not [double]::IsInfinity($lineLeft)) {
            $lineWidth = [Math]::Max(1, [int]($lineRight - $lineLeft))
            $lineHeight = [Math]::Max(1, [int]($lineBottom - $lineTop))
            $output.Add("LINE`t$(Convert-ToBase64 $line.Text)`t$([int]$lineLeft)`t$([int]$lineTop)`t$lineWidth`t$lineHeight")
        }
    }

    [IO.File]::WriteAllLines($OutputPath, $output, (New-Object Text.UTF8Encoding($false)))
    exit 0
}
catch {
    $message = $_.Exception.Message
    try {
        [IO.File]::WriteAllText($OutputPath, "ERROR`t$(Convert-ToBase64 $message)", (New-Object Text.UTF8Encoding($false)))
    }
    catch { }
    exit 1
}
finally {
    Remove-Item -LiteralPath $temporaryPng -Force -ErrorAction SilentlyContinue
}
