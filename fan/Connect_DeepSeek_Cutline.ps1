[CmdletBinding()]
param([string]$Profile = "$env:USERPROFILE\.dsh\profiles\web")
$ErrorActionPreference = 'Stop'
$bridgeDir = Join-Path $PSScriptRoot 'DeepSeekBridge'
$bridgePython = Join-Path $bridgeDir '.venv\Scripts\python.exe'
Push-Location -LiteralPath $bridgeDir
try { & $bridgePython -m bridge.connect_studio --profile $Profile }
finally { Pop-Location }
