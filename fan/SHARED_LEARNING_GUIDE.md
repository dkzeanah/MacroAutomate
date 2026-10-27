# Shared learning and context workbench

The requested design is an **evidence-driven procedural memory**. Observations become named, scoped hypotheses. Successful checks reinforce the particular claim they tested; counterexamples remain in the record. A request first searches retained tools and source references, obtains fresh observations when needed, then uses a model for unresolved work. New results return to memory with their provenance. Memory never grants permission to act.

This implementation connects that memory to the existing Atlas context engine and shared harness. It does not train a new language model or establish causality from repetition. The Learning Workbench retains the existing bounded, passive trials and lesson previews; changing real applications requires an explicit action.

## Open the shared interface

Run `fan\harness\Harness.bat` and select **Learning & Automation**. This is a separate Python application under `/fan`; Atlas is not an AHK tab. It owns its runtime and database. Start Macro Automator if its local bridge is offline.

To view indexed code directly, run `fan\OpenCodeIndex.cmd`. In **Index**, choose a project (or all projects), search a symbol such as `render_dome_video`, and click a result. **Slice** shows the exact source; **Edges** shows callers and callees. **Copy address** gives a stable address for `context_map_get`. The Atlas tab lists project classifications and priorities. The existing desktop projects remain indexed in place.

1. **List taskbar** shows retained app labels, FindText bit counts and verified opens.
2. **Learn visible taskbar** captures accessible buttons on every visible taskbar without switching programs. A large multi-monitor scan can take a few minutes. Screenshots, binary patterns, shortcut identity and timestamps go into unified storage. Overflow, hidden and unlabelled buttons remain unknown. Several monitors may show the same app.
3. Enter `scite4ahk`, then **Open named app**. The program resolves the live accessibility label and stored pixel pattern, shows a yellow border before input, rechecks the target, and checks the foreground executable. An app already in the foreground is left there. An uncertain click is not automatically repeated.
4. Enter `SciTE` and select **Evidence** to inspect recorded support and failures. A successful foreground check establishes which application opened, not whether an arbitrary action inside it worked.
   Select **Show learned lesson** with the same query to open that actual retained claim in the Learning Workbench. Its lesson plays without sending input to underlying windows.
5. **Saved tools** retrieves scripts and workflows already authored. **Find code** searches the shared map; paste a returned address and select **Read exact address** to retrieve a bounded source slice and its call edges.

The Macro Automator's **Learning Workbench** shows evidence groups, lessons, context maps and counterexamples. Its taskbar groups now contain real captures and foreground-check evidence. Yellow borders are click-through, do not activate their own windows, and are excluded from perception captures. Ctrl+right-drag moves the program's registered secondary windows.

## Before and after the model

The bridge injects relevant saved-tool descriptions and scoped evidence before model planning. Explicit requests such as `open scite4ahk` use the native learned-taskbar operation without a model call. A missing target or timeout returns its status without a model fallback or automatic retry. Other requests retain the normal DeepSeek tool loop.

`automation_knowledge_search` returns execution counts, verification counts, failures, artifact identity and observed contexts. Changed workflow/script revisions receive different identities. A process starting, a process exiting, a pixel match and a successful foreground check are different claims. Repeated polls and observations are not independent experiments.

`ahk_script_validate` uses the installed AutoHotkey v2 parser without running the script. Exact standalone sources can reuse a stored parser proof. Changed source, a changed interpreter, or external includes require another check. Parser validity does not prove runtime behavior or the requested UI effect. A syntax error is not enough evidence to identify a different language.

## Project context, tools and runners

The first desktop pass indexes projects **in place**. Originals stay at their existing paths. The harness supplies twenty classification buckets; uncertain classifications need review. aAutomateMacro, DomeSim and the harness are pinned for current work. Capability discovery registers launchers and callable surfaces without running them or installing their dependencies. A detected runner is not a certified working runner.

Use **Atlas** for classification and priority, **Index** for symbols and caller/callee edges, **Write Gate** before adding code, **Harness** to select and run a registered capability, and **Ingest** for ZIPs or a hot folder. Registration alone executes nothing. Existing Ingest backups and working-state checks remain available; executing an incoming project is a deliberate step.

Versioned `classes.py` and `functions.py` in the harness's `condensed` folder are reference compilations with source addresses. They are not a replacement runtime: flattening independent projects can collide names, imports and dependencies. Original projects remain the runnable source of truth. Rebuild indexes after changes; stale slices are refused by their body hash.

The Atlas symbol scanner covers Python. A missing symbol means absent from the indexed Python scope, not absent from AHK, JavaScript or unindexed files. Native AHK library search/read tools supply signatures for the automater. Desktop scans and capability discovery have file limits; inspect the integration report for truncation and parse errors. Bundled compiler runtimes are excluded from future source walks.

Raw arbitrary scripts cannot be assumed to have targeting feedback. Use native workflows or the FanBridgeClient SDK for instrumented input. Keyboard feedback identifies the receiving control/window; a border shows the intended target, while the subsequent verification supplies evidence of the effect.


## Real sequence: observe, teach, save, reuse

Claim **38** records a Triangle Infill 3-D interaction: visual region **40 → 515 → 40**, eight historical continuations, zero accepted original-app automations. Source evidence **65**, provenance `usage_transition:1086`, supplies the exact tokens. The program has not learned the controls' semantic purpose. Region 40's visual pattern is incomplete, so replay in the original application remains blocked.

Open the Learning Workbench through `fan_learning_lesson` with `claim_id=38`. Its ten-step lesson is built from retained evidence, scope, uncertainty, the three tokens, and saved-reuse instructions. **Save rehearsal** compiles this evidence into native structured steps once. The existing saved workflow is **Learned rehearsal 38-6e3bf715**. **Run saved** loads those same steps and rehearses them in a separate local window with yellow targeting feedback. It sends no input to underlying applications.

In the DeepSeek Bridge enter exactly:

```
rehearse Learned rehearsal 38-6e3bf715
```

That request is resolved locally without constructing a model client, recompiling the recipe, or asking DeepSeek for code. The live chat test completed all three steps with **zero model requests**. Rehearsal verifies the stored order inside the fixture; it does not reinforce the original-app claim. Source changes and edited workflow steps are refused.

The bridge now has no default tool-round ceiling. Longer requests continue until an answer, cancellation, or a real failure. Older completed exchanges become a bounded local checkpoint while full event records remain available. Checkpointing does not rerun tools. **Stop** still cancels the task. An explicit programmatic `max_turns` remains available for bounded callers.

See `DEEPSEEK_DEMONSTRATION.md` for a broad capabilities prompt and the evidence to look for.
