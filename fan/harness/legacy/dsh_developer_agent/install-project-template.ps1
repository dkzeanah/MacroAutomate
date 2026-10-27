[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BundleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TemplateRoot = Join-Path $BundleRoot 'project-template'
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Project root does not exist: $ProjectRoot"
}

$AgentsTarget = Join-Path $ProjectRoot 'AGENTS.md'
$SkillsTarget = Join-Path $ProjectRoot '.dsh\skills'

if (Test-Path -LiteralPath $AgentsTarget) {
    $Backup = "$AgentsTarget.developer-memory-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $AgentsTarget -Destination $Backup
    Write-Host "Existing AGENTS.md left unchanged. Backup: $Backup"
}
else {
    Copy-Item -LiteralPath (Join-Path $TemplateRoot 'AGENTS.md') -Destination $AgentsTarget
    Write-Host "Installed: $AgentsTarget"
}

New-Item -ItemType Directory -Force -Path $SkillsTarget | Out-Null
Get-ChildItem -LiteralPath (Join-Path $TemplateRoot '.dsh\skills') -Directory | ForEach-Object {
    $Destination = Join-Path $SkillsTarget $_.Name
    if (Test-Path -LiteralPath $Destination) {
        Write-Host "Left existing skill unchanged: $Destination"
    }
    else {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse
        Write-Host "Installed skill: $($_.Name)"
    }
}
