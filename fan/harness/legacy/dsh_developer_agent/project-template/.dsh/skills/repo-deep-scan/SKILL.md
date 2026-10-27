---
name: repo-deep-scan
description: Build a grounded architecture model of an unfamiliar or large repository using search, selective reads, validation, and parallel subagents.
---

# Repository Deep Scan

Use this skill when asked to understand, map, audit, onboard to, or reason broadly about a repository.

## Procedure

1. Confirm the workspace/repository root using non-mutating inspection.
2. Inventory source/build/test/config/documentation files with `glob`; exclude generated/vendor/build/cache trees unless relevant.
3. Detect languages, frameworks, package managers, solution/project boundaries, and executable entry points.
4. Search for startup/bootstrap code, dependency-injection registration, persistence contexts, routes/controllers/handlers, core domain types, and test fixtures.
5. Divide large repositories into independent subsystems. Spawn subagents for areas that can be analyzed independently; give each a precise scope and require evidence with file paths/symbols.
6. Read the files that define boundaries and runtime flow. Follow important calls/references outward only as needed.
7. Run safe, non-mutating repository/build inspection commands when they clarify actual behavior.
8. Consolidate findings into:
   - technology/build map;
   - module boundaries;
   - startup/runtime flow;
   - persistence/data flow;
   - important interfaces/dependency edges;
   - test map;
   - risks/technical debt;
   - unresolved questions.
9. Clearly label inference versus verified repository evidence.
10. If prior work may matter, use workspace-scoped session search to recover earlier findings before duplicating investigation.

Do not attempt to understand a large repository by reading every file sequentially.
