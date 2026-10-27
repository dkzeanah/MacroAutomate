# Separate Python harness under Fan — 2026-10-18

Atlas, Studio and SideLearner live at `C:\Users\Don\Desktop\aAutomateMacro\fan\harness`, with their own Python environment and `.atlas/atlas.sqlite3`. Their GUI is a separate Python process. Macro Automator has no Atlas/Code Index tab. Its optional launch button starts that application; bounded `context_map_find/get` calls use a local subprocess, and the Python learning tab uses the authenticated local Fan bridge for native operations.

Open `fan/OpenCodeIndex.cmd` for the **Index** view, or `fan/harness/Harness.bat` for the complete toolkit. Choose a project, search a symbol, and select its row to see source and edges. The demo search is `render_dome_video` in DomeSim.

The old Desktop harness remains untouched. Source, retained state, archive/history, reference compilations and consistent database snapshots were copied into this project. Active project roots, backup directories and runtime ownership were rebased. Installed editable bindings to the old folder were excluded. Existing desktop source projects remain indexed in place; they were not all copied into the harness.

An audit denied reads beneath the old harness folder: Atlas still retrieved an exact slice and Studio constructed all twelve tabs from the new location. The original Desktop harness is therefore not required by the relocated runtime. `FAN_INTEGRATION.json` records its provenance. Explicit environment overrides such as `FAN_CONTEXT_WORKSPACE` still select their configured workspace.

## Actual learned sequence and reuse

- Claim **38**; evidence **65**; source `usage_transition:1086`.
- Tokens: `CLICK:E40:L`, `CLICK:E515:L`, `CLICK:E40:L`.
- Historical support: eight continuations; accepted original-app automations: zero.
- Saved native workflow: **Learned rehearsal 38-6e3bf715**. Compilation retains the evidence and exact plan; later runs load the existing native workflow.
- Live native execution completed all three steps. A second run through the real chat agent also completed all three, with zero `agent_request` events and zero model calls. Task `9a15557de6924332b252bb30798cbec3`.
- Scope is `isolated_fixture_only`; original-app verification remains false. Missing/changed evidence and edited steps are refused. A short pattern for region 40 blocks original-app replay.
- The lesson has ten steps, including provenance, uncertainties, recorded tokens and reuse instructions. Rehearsals do not manufacture positive evidence for the original application.

## Validation

The main AHK parser passed. Ten native procedure checks passed, including preserved foreground focus, unchanged original-app evidence, idempotent compilation and refusal of tampered steps. The nine standalone GUI regression tests passed after settling initial Windows layout before timing event delivery. The bridge suite passed 108 tests, including continuation past eight rounds, valid history checkpoints, cancellation and zero-model reuse.

The supported harness suite is `python -m pytest tests/ -q`, matching `Harness.bat test`: **197 passed**. The root-level legacy `test_creator_ops.py` is outside that suite and currently fails collection because it imports the retired top-level `ollama_preprompt` module. It has not been silently skipped or represented as a passing test. After the final checkpoint refinement, 22 relevant bridge tests passed, including preservation of the current request alongside prior chat history and large tool results.

The first cold native workflow run exposed uninitialized engine state; engine globals now initialize before execution. A later live run succeeded through the actual native engine, not only the isolated unit-test runner.

For the full user-facing demonstration prompt, open `DEEPSEEK_DEMONSTRATION.md`.
