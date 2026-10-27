---
name: project-memory-refresh
description: Reconcile durable project instructions with newly verified architecture facts without polluting AGENTS.md with transient task history.
---

# Project Memory Refresh

Use this skill when the user asks to update durable project knowledge after substantial architecture work.

## Procedure

1. Read the current project `AGENTS.md` and any applicable local overlays.
2. Review verified findings from the current work and, when relevant, workspace-scoped prior sessions.
3. Separate durable facts from transient debugging history.
4. Add only durable information that will change future engineering behavior, such as:
   - authoritative project/module roles;
   - required build/test commands;
   - database/context ownership;
   - important invariants;
   - public compatibility constraints;
   - generated-code boundaries;
   - deployment/environment requirements.
5. Do not turn `AGENTS.md` into a session log, changelog, or dump of speculative architecture notes.
6. Preserve existing user-written constraints unless the user explicitly changes them.
7. Show the resulting diff and validate that instructions remain concise and internally consistent.
