# Renders each PDF page with Windows.Data.Pdf and reads it with Windows.Media.Ocr.
# Output: one line per page, "<page number><TAB><base64 UTF-8 text>".
param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [int]$MaxPages = 60,
    [string]$Language = ""
)

$ErrorActionPreference = "Stop"

function Await-WinRT($AsyncOperation, [Type]$ResultType) {
    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object { $_.Name -eq "AsTask" -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 } |
        Select-Object -First 1
    $task = $method.MakeGenericMethod($ResultType).Invoke($null, @($AsyncOperation))
    return $task.GetAwaiter().GetResult()
}

function Await-Action($AsyncAction) {
    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object { $_.Name -eq "AsTask" -and -not $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq "IAsyncAction" } |
        Select-Object -First 1
    $method.Invoke($null, @($AsyncAction)).GetAwaiter().GetResult() | Out-Null
}

Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Pdf.PdfPageRenderOptions, Windows.Data.Pdf, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null

$engine = $null
if ($Language) {
    try { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language($Language))) } catch { }
}
if ($null -eq $engine) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
if ($null -eq $engine) { throw "Windows could not create an OCR engine. Install a Windows OCR language pack." }

$file = Await-WinRT ([Windows.Storage.StorageFile]::GetFileFromPathAsync($InputPath)) ([Windows.Storage.StorageFile])
$document = Await-WinRT ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($file)) ([Windows.Data.Pdf.PdfDocument])
$count = [Math]::Min([int]$document.PageCount, $MaxPages)
$lines = New-Object System.Collections.Generic.List[string]
$limit = [double][Windows.Media.Ocr.OcrEngine]::MaxImageDimension
if ($limit -le 0) { $limit = 2600 }

for ($index = 0; $index -lt $count; $index++) {
    $page = $document.GetPage([uint32]$index)
    try {
        $options = New-Object Windows.Data.Pdf.PdfPageRenderOptions
        $scale = [Math]::Min(2.0, $limit / [Math]::Max($page.Size.Width, $page.Size.Height))
        $options.DestinationWidth = [uint32][Math]::Max(1, [Math]::Round($page.Size.Width * $scale))
        $options.DestinationHeight = [uint32][Math]::Max(1, [Math]::Round($page.Size.Height * $scale))
        $stream = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
        Await-Action ($page.RenderToStreamAsync($stream, $options))
        $decoder = Await-WinRT ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $bitmap = Await-WinRT ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        $gray = [Windows.Graphics.Imaging.SoftwareBitmap]::Convert($bitmap, [Windows.Graphics.Imaging.BitmapPixelFormat]::Gray8)
        $result = Await-WinRT ($engine.RecognizeAsync($gray)) ([Windows.Media.Ocr.OcrResult])
        $text = ($result.Lines | ForEach-Object { $_.Text }) -join "`n"
        $lines.Add("$($index + 1)`t$([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text)))")
        $gray.Dispose(); $bitmap.Dispose(); $stream.Dispose()
    }
    finally {
        $page.Dispose()
    }
}
[IO.File]::WriteAllLines($OutputPath, $lines)
