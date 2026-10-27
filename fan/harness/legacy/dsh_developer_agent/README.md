# DeepSeek Harness — Developer Memory setup (Windows/Web)

This bundle creates a user-owned DeepSeek Harness coding preset and enables workspace-scoped cross-session session search without modifying the shipped `standard` preset.

## Files installed under DSH_HOME

By default, `DSH_HOME` is `$HOME\.dsh`.

- `.agent-presets\developer-memory\agent.cordis.yml`
- `.agent-presets\developer-memory\preset.yml`
- `developer-memory.patch.yml`
- `start-developer-memory.ps1`
- `install-developer-project.ps1`
- `developer-memory-project-template\AGENTS.md`
- `developer-memory-project-template\.dsh\skills\*`

The installer copies the **current Standard preset from the local Harness checkout** and adds the Developer Memory persona plus `@deepseek-ai/dsh-tool-session-query`. Rerunning it after a Harness update rebuilds the custom preset from the newly shipped Standard roster.

## Install the agent

Extract this bundle, open PowerShell inside the extracted `deepseek-harness-developer-agent` directory, then run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-developer-agent.ps1
```

The installer already targets the Harness checkout used on this machine:

```text
C:\Users\Don\Desktop\deepseek-harness
```

It also validates the generated host patch with Harness's own `--dump-config` parser before reporting success.

## Start Harness

```powershell
& (Join-Path $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }) 'start-developer-memory.ps1')
```

In the Web interface, create a **new session** and select **Developer Memory** as the Agent Preset.

## Initialize a repository for deep project understanding

Change into the repository root first. For example:

```powershell
Set-Location 'C:\Users\Don\Desktop\Projs\PawnShopApp'
& (Join-Path $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }) 'install-developer-project.ps1')
```

The initializer installs:

- `AGENTS.md`
- `.dsh\skills\repo-deep-scan\SKILL.md`
- `.dsh\skills\safe-code-change\SKILL.md`
- `.dsh\skills\debug-build-test\SKILL.md`
- `.dsh\skills\project-memory-refresh\SKILL.md`

Existing skill directories are left unchanged. If the repository already has `AGENTS.md`, the initializer creates a timestamped backup but **does not overwrite the original**; merge the supplied engineering rules into the repository's existing instructions deliberately.

## Session-memory architecture

The launcher applies this host overlay with the resolved absolute `DSH_HOME` path:

```yaml
- id: session-query-sqlite
  config:
    path: 'C:/Users/Don/.dsh/session-query/developer-memory.sqlite'
    openAt: first-search
```

The SQLite file is a derived full-text-search index and remains separate from authoritative Harness session persistence.

The Developer Memory agent preset adds:

```yaml
- id: tool-session-query
  name: '@deepseek-ai/dsh-tool-session-query'
  config:
    maxSearchResults: 100
    searchTimeoutMs: 30000
```

This provides the model-facing session-history search/read tools. Keep the repository root consistent as the Web workspace so historical searches stay associated with the same project workspace.

## Included skills

### `repo-deep-scan`
Maps a large repository through targeted search, selective reads, safe inspection, parallel subagents, and consolidation.

### `safe-code-change`
Implements complete changes while protecting unrelated work and requiring validation.

### `debug-build-test`
Reproduces failures, follows the first meaningful root cause, fixes it, and reruns validation.

### `project-memory-refresh`
Reconciles newly verified architectural facts into durable project instructions without turning `AGENTS.md` into a transient session log.

## Recommended first prompt in an existing project

```text
Build a grounded architectural model of this repository before changing anything. Use the repo-deep-scan skill. Search before reading large trees, delegate independent subsystems to subagents, recover relevant prior workspace sessions when available, identify startup/runtime flow, persistence, APIs, dependency boundaries, tests, build/deployment assumptions, and unresolved risks. Then give me the consolidated project map and recommend what durable facts belong in AGENTS.md.
```

## After updating DeepSeek Harness

Open PowerShell in this bundle directory and rerun:

```powershell
.\install-developer-agent.ps1
```

The custom preset is rebuilt from the current checkout's Standard preset so your developer agent inherits changes to the shipped tool roster instead of freezing an old copy.

## Windows PowerShell 5.1 note

The installer is compatible with Windows PowerShell 5.1. During `--dump-config`
validation, pnpm/Node may write normal diagnostic text to stderr. Windows
PowerShell 5.1 represents redirected native stderr as `ErrorRecord` objects;
the installer temporarily uses `ErrorActionPreference = Continue` only for that
capture, preserves the native exit code, normalizes the output, and restores
strict `Stop` behavior immediately afterward.
