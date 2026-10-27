[CmdletBinding()]
param(
    [string]$HarnessRoot = 'C:\Users\Don\Desktop\deepseek-harness',
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PatchPath = Join-Path ([System.IO.Path]::GetFullPath($DshHome)) 'developer-memory.patch.yml'

if (-not (Test-Path -LiteralPath $PatchPath)) {
    throw "Developer Memory patch not found at $PatchPath. Run install-developer-agent.ps1 first."
}

Set-Location -LiteralPath ([System.IO.Path]::GetFullPath($HarnessRoot))
& pnpm dsh --profile web --patch $PatchPath
exit $LASTEXITCODE
