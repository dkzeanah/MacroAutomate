# Witness the bridge working

Open **DeepSeek Bridge** in Macro Automator. Keep **Live activity** visible so you can compare requested tools, returned observations and the final answer. Atlas opens separately through **Code / Tools**, or by double-clicking `fan/OpenCodeIndex.cmd`. Macro Automator does not need to be open to browse Atlas.

## First: prove reuse without a model

Send this exact message as a separate request:

```text
rehearse Learned rehearsal 38-6e3bf715
```

Expected: a local rehearsal window demonstrates **40 → 515 → 40**, with yellow borders and a three-step trace. The answer reports **DeepSeek calls: 0**. This dispatch reads the stored native workflow; it does not compile or generate it again. The real chat test is recorded as task `9a15557de6924332b252bb30798cbec3`.

This is an observed interaction pattern from Triangle Infill 3-D, recorded eight times. It has no verified original-app success. The rehearsal verifies the order in its own fixture; it does not click Triangle Infill or certify the controls' meaning.

## Then: exercise the breadth of the bridge

Paste the following as one message. This uses the model for investigation and explanation, so these requests are different from the zero-model dispatch above.

```text
Give me a visible, evidence-backed tour of the Fan learning and automation system. Complete the stages below, using the real advertised tools and actual retained data. Narrate each stage briefly in the chat before doing it. Keep underlying applications untouched; perform demonstrations only in the owned lesson/rehearsal window or a new local demo window. Inspect existing artifacts before writing anything.

1. Discover fan_capabilities and read current input settings. Explain the available native workflow actions, reusable libraries, and the difference between observations, model inferences, syntax proofs, and verified effects.
2. Query fan_learning_insights, fan_discovered_targets, knowledge_search and automation_knowledge_search. Pick real examples, identify their source IDs and contexts, and say what each lets me do. Show missing evidence, failures and possible confounds as well as support. Do not turn frequency into proof of correctness or causality.
3. Read fan_taskbar_list and a small sample of retained patterns. Explain the saved names, visual encodings, capture provenance and verification counts. Do not activate any application during this tour.
4. Inspect claim 38 by opening fan_learning_lesson(claim_id=38). Explain source evidence 65 and usage_transition:1086, the observed sequence 40 -> 515 -> 40, eight historical continuations, zero accepted automations, and the incomplete target pattern. Explain how the lesson is assembled from that evidence and what would be needed to validate real application execution.
5. Search the tool catalog and saved workflow library for "Learned rehearsal 38-6e3bf715". Read its steps and revision, then preview it. If that saved workflow exists, do not compile or rewrite it. If missing, compile claim 38 once and inspect the returned name. Run fan_learning_rehearse twice using the saved name. Compare both returned traces. Report only fixture verification; leave original-app verification unchanged. Show how I can reuse it from Run saved or with the exact standalone message "rehearse Learned rehearsal 38-6e3bf715" without a model call.
6. Use context_map_find for render_dome_video, then context_map_get on the returned DomeSim VoiceStudioApp method address. Explain the exact slice and caller/callee edges. Use fan_code_index with query render_dome_video to open the separate Python Atlas application. Tell me how to select a result, inspect its source, copy its stable address, and filter by project. A map MISS applies only to indexed scope.
7. Search the native AHK library for FanBridgeClient and inspect its real signatures. Search saved scripts for a suitable existing local demonstration before authoring anything. Reuse one if it already satisfies the next stage.
8. Demonstrate the script toolchain using a small parameterized AHK v2 tool named LearningTourDemo. Its input is a lesson title. It should create only its own local GUI, showing the supplied title, the three recorded token labels, and a statement that original-app execution is unverified. Do not send keys, click other windows, launch external apps, read credentials, or change system settings. Save a clear description, tags, usage, example and input schema. Validate syntax before running. Run it with wait=false, inspect the real run status, and report only what the tool observations prove. If the exact script already exists, read and reuse it instead of writing it again. Do not overwrite an unrelated tool with the same name. Leave its window available for me to inspect and tell me how to close it.
9. Re-read the catalog/revision and empirical memory for that exact artifact. Distinguish parser validity, a running process and an observed GUI effect. Save a clearly labelled inference note describing possible next validations, with evidence references; do not store imagined successes as observations.
10. Finish with a compact table: capability demonstrated, actual tool/artifact/evidence ID, observed outcome, remaining uncertainty, and the exact next command or GUI button I can use. State which steps reused stored artifacts and which actually required model planning. Continue through all stages; if a stage is unavailable, report the returned reason and proceed with the independent stages. Do not repeat uncertain input actions or invent missing results.
```

## What to watch

- **Activity:** actual tool requests/results; provider reasoning when supplied; local reuse events; history checkpoint events on long runs.
- **Workbench:** source evidence, uncertainty, ten lesson steps, **Save rehearsal** and **Run saved**. Rehearsal results remain separate from original-app evidence.
- **Atlas / Index:** project filter, symbol search, exact source slice and call edges. Python projects are indexed; use native library search/read for AHK signatures.
- **Catalog:** saved workflow/script descriptions, source revisions, usage and actual execution evidence. Indexing a runner does not prove it works.

There is no default eight-round cutoff anymore. The agent continues until an answer, cancellation or a real error. Older exchanges are checkpointed locally while the full activity remains retained. Use **Stop** to cancel. Network failures, incomplete provider responses and missing live targets still produce real errors; removing a round limit does not make those successful.
