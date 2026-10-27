# Hidden streaming worker. Credentials and request data arrive only on stdin;
# the command line, source and filesystem never contain an API key.
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$client = $null
$response = $null
$reader = $null
try {
    $inputRequest = [Console]::In.ReadLine() | ConvertFrom-Json
    Add-Type -AssemblyName System.Net.Http
    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromSeconds(120)
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $inputRequest.url)
    $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $inputRequest.key)
    $request.Content = [System.Net.Http.StringContent]::new($inputRequest.body, [System.Text.Encoding]::UTF8, 'application/json')
    $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    [Console]::Out.WriteLine('status: ' + [int]$response.StatusCode)
    [Console]::Out.Flush()
    if (-not $response.IsSuccessStatusCode) {
        [Console]::Out.WriteLine('error: DeepSeek HTTP ' + [int]$response.StatusCode)
        exit 1
    }
    $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
    while ($null -ne ($streamLine = $reader.ReadLine())) {
        [Console]::Out.WriteLine($streamLine)
        [Console]::Out.Flush()
    }
} catch {
    [Console]::Out.WriteLine('error: Streaming transport failed: ' + $_.Exception.Message)
    [Console]::Out.Flush()
    exit 1
} finally {
    if ($null -ne $reader) { $reader.Dispose() }
    if ($null -ne $response) { $response.Dispose() }
    if ($null -ne $client) { $client.Dispose() }
}
