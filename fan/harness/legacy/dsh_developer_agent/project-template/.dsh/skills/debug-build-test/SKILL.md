---
name: debug-build-test
description: Diagnose build, test, runtime, or tooling failures by reproducing them, tracing the first meaningful cause, applying a complete fix, and rerunning validation.
---

# Debug, Build, Test

## Procedure

1. Reproduce the failure with the repository's own command when practical.
2. Capture the earliest meaningful error and enough surrounding output to identify its source; avoid flooding context with repeated downstream errors.
3. Search the repository for the failing symbol, path, configuration key, project reference, migration, command, or stack-frame location.
4. Trace causality rather than patching only the last visible symptom.
5. Check recent/local uncommitted changes and prior workspace session history when they may explain the regression.
6. Implement the complete fix using existing repository patterns.
7. Rerun the failed command.
8. Run adjacent tests/checks that exercise the repaired area.
9. If failures remain, continue from the new first meaningful failure instead of assuming the original fix completed the task.
10. Report the root cause, exact change, and commands/results used to verify it.
