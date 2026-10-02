[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Root = (Get-Location).Path,

    [bool]$Recurse = $true,

    [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'

$includeLine = '#Include "%A_AppData%\AHKScriptHub\ScriptHubClient.ahk"'
$clientSource = Join-Path $PSScriptRoot 'ScriptHubClient.ahk'
$hubSource = Join-Path $PSScriptRoot 'AHK_Script_Hub_v2_FULL.ahk'
$appDataHub = Join-Path $env:APPDATA 'AHKScriptHub'
$clientDestination = Join-Path $appDataHub 'ScriptHubClient.ahk'

if (-not (Test-Path -LiteralPath $clientSource)) {
    throw "ScriptHubClient.ahk was not found next to this installer: $clientSource"
}

if (-not $WhatIfOnly) {
    New-Item -ItemType Directory -Force -Path $appDataHub | Out-Null
    Copy-Item -LiteralPath $clientSource -Destination $clientDestination -Force
}

$rootItem = Get-Item -LiteralPath $Root
if ($rootItem.PSIsContainer) {
    $files = if ($Recurse) {
        Get-ChildItem -LiteralPath $rootItem.FullName -Filter '*.ahk' -File -Recurse
    } else {
        Get-ChildItem -LiteralPath $rootItem.FullName -Filter '*.ahk' -File
    }
} else {
    $files = @($rootItem)
}

$patched = 0
$skipped = 0

foreach ($file in $files) {
    if ($file.Name -in @('ScriptHubClient.ahk', 'AHK_Script_Hub_v2_FULL.ahk') -or
        $file.FullName -match '\\Lib\\') {
        $skipped++
        continue
    }

    $text = Get-Content -LiteralPath $file.FullName -Raw

    if ($text -match '(?im)^\s*#Requires\s+AutoHotkey\s+v1') {
        Write-Host "SKIP V1: $($file.FullName)"
        $skipped++
        continue
    }

    if ($text -match '(?im)^\s*#Include\s+.*ScriptHubClient\.ahk') {
        Write-Host "ALREADY ENABLED: $($file.FullName)"
        $skipped++
        continue
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [regex]::Split($text, "\r?\n")) {
        $lines.Add($line)
    }

    # Keep #Requires/#SingleInstance/#Warn/etc. together, then place the bridge
    # before the first executable statement. Leading comments/blanks are retained.
    $insertAt = 0
    $seenDirectiveBlock = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trim = $lines[$i].Trim()

        if ($trim -eq '' -or $trim.StartsWith(';')) {
            $insertAt = $i + 1
            continue
        }

        if ($trim.StartsWith('#')) {
            $seenDirectiveBlock = $true
            $insertAt = $i + 1
            continue
        }

        break
    }

    $lines.Insert($insertAt, $includeLine)
    $newText = [string]::Join("`r`n", $lines)

    if ($WhatIfOnly) {
        Write-Host "WOULD PATCH: $($file.FullName)"
        $patched++
        continue
    }

    $backup = "$($file.FullName).pre-scripthub.bak"
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $file.FullName -Destination $backup
    }

    [System.IO.File]::WriteAllText(
        $file.FullName,
        $newText,
        [System.Text.UTF8Encoding]::new($false)
    )

    Write-Host "PATCHED: $($file.FullName)"
    $patched++
}

Write-Host ""
Write-Host "ScriptHub client installed to: $clientDestination"
Write-Host "Patched: $patched   Skipped: $skipped"
Write-Host "Restart patched AutoHotkey scripts so their full tray menus register with the Hub."
