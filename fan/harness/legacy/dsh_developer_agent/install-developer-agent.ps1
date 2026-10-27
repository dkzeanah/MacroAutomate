[CmdletBinding()]
param(
    [string]$HarnessRoot = 'C:\Users\Don\Desktop\deepseek-harness',
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }),
    [switch]$InstallProjectTemplate,
    [string]$ProjectRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "[Developer Memory] $Message"
}

$BundleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$HarnessRoot = [System.IO.Path]::GetFullPath($HarnessRoot)
$DshHome = [System.IO.Path]::GetFullPath($DshHome)

if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    throw 'pnpm is not available on PATH. DeepSeek Harness source checkout requires pnpm before this installer can validate the Web profile.'
}

$StandardPreset = Join-Path $HarnessRoot 'apps\cli\config\agent-presets\standard\agent.cordis.yml'
$SessionToolPackage = Join-Path $HarnessRoot 'packages\session-query\tool-session-query\package.json'

if (-not (Test-Path -LiteralPath $StandardPreset)) {
    throw "DeepSeek Harness standard preset was not found at: $StandardPreset`nPass -HarnessRoot with the root of your deepseek-harness source checkout."
}

if (-not (Test-Path -LiteralPath $SessionToolPackage)) {
    throw "The current Harness checkout does not contain packages\session-query\tool-session-query. Update the checkout before installing Developer Memory."
}

$PresetRoot = Join-Path $DshHome '.agent-presets\developer-memory'
$SessionIndexDir = Join-Path $DshHome 'session-query'
$SessionIndexPath = Join-Path $SessionIndexDir 'developer-memory.sqlite'
$PatchPath = Join-Path $DshHome 'developer-memory.patch.yml'

New-Item -ItemType Directory -Force -Path $PresetRoot | Out-Null
New-Item -ItemType Directory -Force -Path $SessionIndexDir | Out-Null

# Start from the Harness version currently installed on this machine so the
# custom preset stays aligned with the shipped Standard preset's tool roster.
$PresetText = Get-Content -LiteralPath $StandardPreset -Raw
$OriginalPersona = 'You are a coding agent powered by the {{model}} model. Your working directory is {{cwd}}.'
$DeveloperPersona = 'You are Developer Memory, an autonomous coding agent powered by the {{model}} model. Your working directory is {{cwd}}. Build a grounded model of the repository before making broad changes. Search before reading large trees; read dependency-critical files selectively; inspect callers, callees, tests, configuration, build files, and persistence boundaries before editing. Use subagents for independent architectural domains and consolidate their findings. Prefer complete implementations over placeholders or stubs. Preserve existing public behavior unless the task requires a deliberate change. Before declaring a code change complete, run the most relevant available build, tests, static checks, or executable validation and report any validation that could not be performed. When prior work in the same workspace may matter, use session-history tools to recover earlier decisions, failures, and discoveries instead of guessing.'

if (-not $PresetText.Contains($OriginalPersona)) {
    throw 'The current Standard preset persona format changed and could not be patched safely. Review the current Harness preset before retrying.'
}

$PresetText = $PresetText.Replace($OriginalPersona, $DeveloperPersona)

$MemoryToolBlock = @'

# ── cross-session engineering memory ───────────────────────────────────────
# Host-plane `session-query-sqlite` supplies the workspace-authorized search
# service. This preset only exposes the model-facing query tools to this agent.
- id: tool-session-query
  name: '@deepseek-ai/dsh-tool-session-query'
  config:
    maxSearchResults: 100
    searchTimeoutMs: 30000
'@

if (-not $PresetText.Contains("id: tool-session-query")) {
    $PresetText = $PresetText.TrimEnd() + "`n" + $MemoryToolBlock.TrimStart() + "`n"
}

$PresetCordisPath = Join-Path $PresetRoot 'agent.cordis.yml'
$PresetMetadataPath = Join-Path $PresetRoot 'preset.yml'
Set-Content -LiteralPath $PresetCordisPath -Value $PresetText -Encoding utf8

$PresetMetadata = @'
name: Developer Memory
description: Windows coding agent with repository tools, subagents, workflows, Ralph, validation discipline, and workspace-scoped cross-session engineering search.
'@
Set-Content -LiteralPath $PresetMetadataPath -Value $PresetMetadata -Encoding utf8

# This SQLite file is a derived FTS/search index only. It is intentionally
# separate from Harness's authoritative session persistence.
$SqliteYamlPath = $SessionIndexPath.Replace('\', '/').Replace("'", "''")
$Patch = @"
- id: session-query-sqlite
  config:
    path: '$SqliteYamlPath'
    openAt: first-search
"@
Set-Content -LiteralPath $PatchPath -Value $Patch -Encoding utf8

# Install a launcher next to the patch. It always boots the Web profile with
# the durable session-search overlay applied.
$LauncherPath = Join-Path $DshHome 'start-developer-memory.ps1'
$EscapedHarnessRoot = $HarnessRoot.Replace("'", "''")
$EscapedPatchPath = $PatchPath.Replace("'", "''")
$Launcher = @"
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath '$EscapedHarnessRoot'
& pnpm dsh --profile web --patch '$EscapedPatchPath'
exit `$LASTEXITCODE
"@
Set-Content -LiteralPath $LauncherPath -Value $Launcher -Encoding utf8

# Keep a reusable project-template installer under DSH_HOME so future repositories
# can be initialized without keeping this downloaded bundle around.
$InstalledTemplateRoot = Join-Path $DshHome 'developer-memory-project-template'
$InstalledProjectInstaller = Join-Path $DshHome 'install-developer-project.ps1'
if (Test-Path -LiteralPath $InstalledTemplateRoot) {
    Remove-Item -LiteralPath $InstalledTemplateRoot -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $BundleRoot 'project-template') -Destination $InstalledTemplateRoot -Recurse

$ProjectInstaller = @'
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$DshHome = [System.IO.Path]::GetFullPath($DshHome)
$TemplateRoot = Join-Path $DshHome 'developer-memory-project-template'

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Project root does not exist: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $TemplateRoot -PathType Container)) {
    throw "Developer Memory project template is missing: $TemplateRoot. Rerun install-developer-agent.ps1."
}

$AgentsTarget = Join-Path $ProjectRoot 'AGENTS.md'
$SkillsTarget = Join-Path $ProjectRoot '.dsh\skills'

if (Test-Path -LiteralPath $AgentsTarget) {
    $Backup = "$AgentsTarget.developer-memory-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $AgentsTarget -Destination $Backup
    Write-Host "Existing AGENTS.md left unchanged. Backup created at: $Backup"
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
'@
Set-Content -LiteralPath $InstalledProjectInstaller -Value $ProjectInstaller -Encoding utf8

# Validate the host overlay using Harness's own composition parser without
# starting the Web server.
#
# Windows PowerShell 5.1 converts native stderr captured with 2>&1 into
# ErrorRecord objects. With the installer-wide ErrorActionPreference=Stop,
# pnpm's normal `$ node ...` banner can therefore terminate the script even
# when the underlying dsh command succeeds. Temporarily use Continue only for
# this native-command capture, save the actual process exit code immediately,
# normalize the captured records to strings, and then restore strict behavior.
Push-Location $HarnessRoot
try {
    $SavedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $DumpRecords = @(& pnpm dsh --profile web --patch $PatchPath --dump-config 2>&1)
        $DumpExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $SavedErrorActionPreference
    }

    $DumpOutput = ($DumpRecords | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $_.Exception.Message
        }
        else {
            [string]$_
        }
    }) -join [Environment]::NewLine

    if ($DumpExitCode -ne 0) {
        throw "Harness rejected the generated patch (exit code $DumpExitCode):`n$DumpOutput"
    }
    if ($DumpOutput -notmatch 'session-query-sqlite' -or $DumpOutput -notmatch 'first-search') {
        throw "Harness parsed the configuration, but the session-query override was not visible in --dump-config output.`n$DumpOutput"
    }
}
finally {
    Pop-Location
}

if ($InstallProjectTemplate) {
    $ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        throw "Project root does not exist: $ProjectRoot"
    }

    $TemplateRoot = Join-Path $BundleRoot 'project-template'
    $TargetAgents = Join-Path $ProjectRoot 'AGENTS.md'
    $TargetSkills = Join-Path $ProjectRoot '.dsh\skills'

    if (Test-Path -LiteralPath $TargetAgents) {
        $Backup = "$TargetAgents.developer-memory-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $TargetAgents -Destination $Backup
        Write-Step "Existing AGENTS.md preserved and backed up at $Backup; template was NOT allowed to overwrite it."
    }
    else {
        Copy-Item -LiteralPath (Join-Path $TemplateRoot 'AGENTS.md') -Destination $TargetAgents
        Write-Step "Installed $TargetAgents"
    }

    New-Item -ItemType Directory -Force -Path $TargetSkills | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $TemplateRoot '.dsh\skills') -Directory | ForEach-Object {
        $Destination = Join-Path $TargetSkills $_.Name
        if (Test-Path -LiteralPath $Destination) {
            Write-Step "Skill already exists; left unchanged: $Destination"
        }
        else {
            Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse
            Write-Step "Installed skill: $($_.Name)"
        }
    }
}

Write-Step "Installed user preset: $PresetRoot"
Write-Step "Installed session-search patch: $PatchPath"
Write-Step "Installed launcher: $LauncherPath"
Write-Step "Installed reusable project initializer: $InstalledProjectInstaller"
Write-Step 'Validated the Web session-query patch with Harness --dump-config.'
Write-Step 'Start Harness with the launcher, then create a new Web session and choose the Developer Memory agent preset.'
