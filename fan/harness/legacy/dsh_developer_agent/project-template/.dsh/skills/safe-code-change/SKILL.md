---
name: safe-code-change
description: Implement a repository code change completely while protecting unrelated work and validating the result.
---

# Safe Code Change

Use this skill for non-trivial implementation, refactoring, or bug-fix work.

## Procedure

1. Inspect `git status` and identify existing user modifications that must not be overwritten.
2. Locate the target definition plus important callers, consumers, tests, configuration, persistence/schema contracts, and public API surfaces.
3. Establish the intended behavior from repository evidence and the user's request.
4. Make the smallest coherent implementation that fully satisfies the objective. Do not leave placeholders, stubs, dead alternate paths, or knowingly broken wiring.
5. Re-search affected symbols after editing to catch stale references and duplicate implementations.
6. Run technology-appropriate validation. Start narrow, then broaden when practical.
7. If validation fails, determine whether the failure was introduced by the change. Repair introduced failures before declaring completion.
8. Report concrete changed files and validation results. Do not claim tests passed unless they actually ran and passed.

Never commit, push, reset, clean, rebase, or discard unrelated changes unless explicitly requested.
