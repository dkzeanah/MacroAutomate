# Repository Engineering Instructions

## Mission

Develop, debug, refactor, and explain this repository using evidence from the repository itself. Build a durable architectural model before making broad changes. Prefer complete, executable implementations over placeholders, stubs, pseudocode, or partially wired features.

## Repository Discovery

At the beginning of unfamiliar work:

1. Identify the repository root, tracked files, build files, package manifests, solution/project files, test projects, configuration, migrations, scripts, and documentation.
2. Use filesystem search (`glob`/`grep`) before recursively reading large directory trees.
3. Identify entry points, dependency-injection composition, persistence boundaries, public APIs, domain models, UI boundaries, background workers, external integrations, and tests relevant to the task.
4. Read dependency-critical files and representative implementations. Do not load generated output, dependency caches, build artifacts, virtual environments, package stores, or vendor trees unless specifically relevant.
5. If the repository is large, delegate independent architectural areas to subagents and consolidate their reports into one coherent model.
6. When earlier work in this same workspace may matter, search prior Harness sessions for previous decisions, errors, attempted fixes, and known constraints before repeating investigation.

## Change Discipline

Before editing code:

- Locate the definition and meaningful usages of every symbol being changed.
- Determine whether the change affects public APIs, schemas, serialized data, migrations, configuration, command-line interfaces, UI contracts, tests, or deployment behavior.
- Prefer existing repository patterns and abstractions over introducing parallel mechanisms.
- Keep changes scoped to the requested objective. Do not reformat or rewrite unrelated code.
- Preserve backward compatibility unless the requested outcome requires an intentional breaking change.
- Never silently discard user data, migrations, configuration, or existing behavior.

After editing code:

- Re-read the changed region for syntactic and logical consistency.
- Search for stale references, renamed identifiers, duplicated code paths, and affected tests.
- Run the narrowest useful validation first, then broader validation when practical.
- Do not claim success when builds/tests/checks fail. Fix failures caused by the change; clearly distinguish pre-existing failures when they can be demonstrated.

## Validation by Technology

Detect the repository technology from its files and use the applicable validation:

### .NET / C#

- Prefer repository solution files (`*.sln`, `*.slnx`) when present.
- Inspect `*.csproj`, `Directory.Build.*`, `global.json`, EF Core configuration, and test projects as relevant.
- Use `dotnet build` for compilation validation.
- Use `dotnet test` when tests exist.
- For Entity Framework Core changes, identify the intended `DbContext` explicitly before running migration/database commands when multiple contexts exist.
- Preserve nullable-reference-type correctness and async database/API patterns already used by the repository.

### Python

- Identify `pyproject.toml`, `requirements*.txt`, lock files, virtual environments, package layout, and test configuration.
- Use the repository's configured test runner; prefer `python -m pytest` when pytest is configured.
- Run configured linters/type checkers when the change falls in their scope.
- Do not add dependencies when the standard library or an existing project dependency already solves the requirement cleanly.

### AutoHotkey

- Treat AutoHotkey scripts as **AutoHotkey v2** unless the repository explicitly establishes another version.
- Do not introduce AutoHotkey v1 command syntax into v2 code.
- Preserve v2 function-call syntax, object semantics, scoping rules, GUI APIs, and hotkey syntax.
- When changing Windows API/DllCall code, preserve pointer sizes, buffer lifetime, encoding, and x64 compatibility.

### Node / TypeScript / JavaScript

- Respect the existing package manager and lockfile (`pnpm`, `npm`, `yarn`, or `bun`).
- Inspect `package.json` scripts and use repository-defined build/test/typecheck/lint commands when available.
- Do not switch package managers or regenerate unrelated lockfiles.

## Git Safety

- Inspect `git status` and relevant diffs before broad edits.
- Never overwrite or revert unrelated uncommitted user changes.
- Do not commit, push, reset, clean, rebase, or force-update branches unless explicitly requested.
- Before reporting completion, summarize files materially changed and validation performed.

## Deep-Understanding Mode

When asked to understand, audit, map, or explain the whole project:

1. Inventory the repository structure and technologies.
2. Build module/subsystem boundaries.
3. Trace startup/entry points and main runtime flows.
4. Map persistence and data flow.
5. Map important interfaces and dependency edges.
6. Map tests to the production areas they validate.
7. Search for TODO/FIXME/HACK markers and suspicious dead or duplicate paths.
8. Inspect build, packaging, CI, deployment, and environment assumptions.
9. Delegate independent subsystems to subagents when useful.
10. Produce a consolidated architecture map that distinguishes verified facts from unresolved questions.

## Context Efficiency

- Search first; read selectively.
- Prefer symbol- or pattern-targeted reads over dumping entire large files.
- Use background jobs for long-running builds/tests when useful.
- Use compaction when a session becomes long, but retain file paths, identifiers, commands, errors, decisions, and unresolved work.
- Store durable repository rules in this `AGENTS.md`; use skills for reusable procedures; use session history for prior engineering experience rather than duplicating all history here.
