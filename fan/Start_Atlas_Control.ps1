param([int]$Port = 8790, [switch]$NoOpen)
$ErrorActionPreference = 'Stop'
$bridgeRoot = Join-Path $PSScriptRoot 'DeepSeekBridge'
$pythonExe = Join-Path $bridgeRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $pythonExe)) { throw "Bridge Python environment is missing: $pythonExe" }
Push-Location -LiteralPath $bridgeRoot
try {
    $controllerArguments = @('-m', 'bridge.controller', '--port', "$Port")
    if ($NoOpen) { $controllerArguments += '--no-open' }
    & $pythonExe @controllerArguments
} finally { Pop-Location }
