# Real-Time Screen Study Assistant — Feature Ledger

**Target:** `fan/MacroAutomator.ahk` on Windows 11, with Chrome's selected portal tab on the main monitor and optional study material on the left and right monitors.  
**Status:** implementation audited and extended on 2026-10-06. The native controller and DeepSeek workflow path have passed live practice-page validation. Checkboxes describe implementation scope, not proof that every acceptance check has passed. See [IMPLEMENTATION_VALIDATION.md](IMPLEMENTATION_VALIDATION.md) for tested behavior, repaired defects and remaining limits.  
**Legend:** `[x]` implemented/reusable capability, `[ ]` not implemented, `[~]` implemented with known limits.

## Formal project statement

Extend the `/fan` MacroAutomator build into a real-time study assistant that observes a user-selected Chrome question portal and optionally reads lesson plans, books, PDFs, and selected screen regions. It should identify the current question and its answer controls, retrieve relevant evidence from previously ingested material and verified question history, reason over that evidence, and use DeepSeek only when local evidence is insufficient. It should record each question, answer, source, confidence, and subsequent correction so the same knowledge can be recalled and refined later. In an enabled automation mode, it should enter supported answers through the pinned Chrome window while that tab remains in the foreground. It should also produce reviewable study material from captured questions and learned concepts.

“Dedicated language model” means a **topic-specific evidence and reasoning layer** over the chosen LLM: local retrieval, concept relationships, verified question-answer memory, decision rules, and feedback. It does not require training a new foundation model. “You only learn once” means reusing a verified answer or fact without paying for a new model call; contradictory evidence or corrections must still reopen that record.

## Existing `/fan` assets to reuse

- [x] `fan/Tabs/Tab_03_LiveOCR.ahk` and `OCR.ahk`: Windows OCR, screen-region selection, word bounds, and OCR actions.
- [x] `fan/Core/_Gdip.ahk`: GDI+ region/desktop screenshots. Its integer monitor selector is **not implemented**, so monitor handling uses explicit coordinates.
- [x] `FindText.ahk`, Patterns, and Vision Scout: visual element matching and review/certification.
- [x] `lib/SnipStudio.ahk` and `lib/SnipParse.ahk`: captured snips, OCR correction memory, and an initial parser for multiple choice and blank questions.
- [x] `lib/TrackSQLite.ahk`, `lib/TrackingDB.ahk`: SQLite persistence and tracking infrastructure.
- [x] `lib/SnapshotRecovery.ahk`: browser URL detection through accessibility; used to verify the selected Chrome window and tab.
- [x] `lib/AppLearner.ahk` and `lib/Acc.ahk`: accessibility discovery; Acc.ahk drives the live control perception (Chromium a11y tree).
- [~] `lib/ResearchPipeline.ahk`: query/insight storage, but its current search workflow opens browser tabs and therefore is not used during focus-locked answering.
- [x] Existing workflow, mouse, and keyboard actions: the answer-entry plan is composed in the engine's own action vocabulary (Click / Send Keys / Type Text / Paste / Wait) and executed with the portal-target guard and per-step verification.

## Feature sets and acceptance checks

### 1. Session, display, and focus control

- [x] Select and pin one Chrome window, tab, and portal origin; detect navigation or a tab change before every action (`StudyAuto_Pin` / `StudyAuto_CheckPin`).
- [x] Enumerate all three monitors at runtime, including negative coordinates, mixed DPI, scaling, resolution changes, and left/main/right placement (`StudyAuto_Monitors`). Allow explicit capture regions for each (window client area or dragged rectangle).
- [x] Read only selected study regions on side monitors (read-along). The main monitor's pinned portal is the only answer target (guard + pin).
- [x] Keep Chrome's selected tab foreground throughout an answering session. Research, OCR processing, database work, and LLM requests happen in-process/API without opening or switching browser tabs.
- [x] If focus moves, the target changes, a dialog obscures the answer, or coordinates become stale, pause input and re-identify the page. Provide start, pause, stop, and emergency-stop controls (Start/Stop/ABORT ALL buttons, Ctrl+Shift+Y toggle, guard-driven auto-pause).
- [x] Bound capture rate (configurable poll ms) and detect changed content (pixel signature + question fingerprint) before reprocessing.

**Acceptance:** a three-monitor session can capture the chosen regions while Chrome stays foreground; simulated focus loss or monitor reconfiguration prevents further input until recovery. *(guard code paths implemented; live three-monitor run pending — see release checks)*

### 2. Question and control perception

- [~] Windows accessibility plus OCR provide text, roles, values and bounds. Captured images go to DeepSeek Flash; the visual algebra demo has been live-validated. FindText is available to the wider app but is not a fallback for the live answer controller. No DOM/Chrome extension (`StudyPercept_*`).
- [x] Fuse text, screen coordinates, accessibility roles, and image evidence into one structured `Question` record. Preserve both raw capture and normalized wording.
- [x] Detect single-select multiple choice, multi-select checkboxes, true/false, yes/no, dropdowns, fill-in-one-or-many-blanks, short text, long-form text, numeric answers with units, and image/chart/table-based questions.
- [~] Identify compound questions, instructions, negation (“except,” “not”), option shuffling, required fields, feedback, and submit/next controls. (negation handled by the local deduction scorer; submit/next located by role+name; compound multi-part questions are treated as one stem; option shuffling is handled by meaning — choice letters are mapped from the live capture, never cached by position.)
- [x] Route unsupported widgets, ambiguous OCR, cross-origin/inaccessible frames, and unrecognized question types to an `unknown/review` state rather than guessing a click target (planner refuses to build a plan).
- [x] Dedupe repeated frames and recognize when a new question appears without confusing a minor animation with a new prompt.

**Acceptance:** fixtures for every listed type produce a question record with its controls and bounds, or an explicit `unknown/review` result (Live Portal tab → “Dry-run Fixtures”). A changed option order retains the answer by meaning rather than by letter or position.

### 3. Study-material ingestion and concept memory

- [~] Import PDF, text and Markdown through `StudyIngest.ahk`; OCR PDF pages. Word/other document formats require export to PDF or text. PDF import is bounded by `pdf_max_pages` and re-import restarts from page 1.
- [x] Observe selected book/PDF windows on side monitors when enabled, with page-change detection and source/page metadata (read-along).
- [x] Extract concepts, definitions, relationships, exceptions, procedures, and examples; store concise derived notes and searchable passages with source references rather than only verbatim page dumps.
- [x] Index material by course/topic, source, page, version, and timestamp. Allow reindexing, deletion, and source-level exclusion (`StudyDB.ahk`, Study Assistant tab).
- [x] Build a relational concept layer connecting facts to questions, related concepts, prerequisites, conflicting claims, and supporting evidence.

**Acceptance:** an uploaded lesson plan and later-viewed PDF page can both be retrieved for a related question with a traceable source and location.

### 4. Layered answer engine

- [x] Normalize the question and choices while retaining exact original text and visual context.
- [x] Search, in order: verified exact question-answer pairs; near-duplicate/history matches; ingested source passages and concept relationships; local deduction over retrieved evidence; DeepSeek fallback; optional later provider adapters (`Study_Answer` in `StudyAssistant.ahk`).
- [~] Give answers an explanation, local source references and heuristic confidence. Confidence is not statistically calibrated. Distinguish verified memory, provisional history, local deduction and model suggestions.
- [x] Use a text model for difficult text reasoning and a vision model when an image, diagram, chart, visual arrangement, or uncertain OCR affects the answer (`Study_QuestionNeedsVision` + `imagePath`).
- [x] Recheck the proposed answer against the current choices, required units, multiple-selection count, and any contradiction before input (`StudyLive_Recheck` + composer parse).
- [x] Abstain or request review when confidence is below a configured threshold or evidence conflicts. Never silently promote an unverified model response to a fact (candidate state; confidence floor blocks entry below it).

**Acceptance:** a repeated verified question is answered from local memory without an API call; a novel unsupported question invokes the configured fallback and remains provisional until verified.

### 5. DeepSeek provider (first external LLM)

- [x] Read `DEEPSEEK_API_KEY` from the user's environment or an OS-protected credential store. Never save or log the key in source, settings, SQLite, screenshots, reports, or request diagnostics (`StudyLLM.ahk`).
- [x] Use `https://api.deepseek.com` and probe `GET /models` at setup so model availability and modality can be checked against the account.
- [x] Default vision requests to `deepseek-flash`. The requested `deepseek-v4-flash-vision-exp` name is a retired compatibility alias that currently routes to Flash. Use `deepseek-v4-pro` for optional text-only escalation; it does not support vision.
- [x] Send cropped screenshots only when image context is needed, with relevant text and source snippets. Record model ID, response metadata, cost estimate, and reason for escalation, without credentials.
- [x] Add timeouts, rate-limit handling, retry/backoff, cancellation, cost limits, and offline behavior.
- [x] Keep a provider interface so Ollama or other LLMs can later be added without changing question storage or answer policy.

**Acceptance:** a text fixture and an image fixture each return a parsed answer with model provenance; unavailable API or exhausted budget leaves the portal untouched and reports a recoverable status.

### 6. Verification, “learn once,” and study bank

- [x] Store question, options, normalized answer, question type, source evidence, confidence, model version, portal context, timestamps, and action/feedback outcome (`qa_item` extension + `study_answer_log`).
- [x] Separate `candidate`, `user-confirmed`, `portal-confirmed`, `disputed`, and `rejected` answer states. A model response alone is only a candidate. `portal-confirmed` (captured from on-page feedback after an auto-submit) joins `user-confirmed`/`source-confirmed` as reusable “learn once” memory.
- [x] Observe portal feedback where available and permit explicit user correction (Study Assistant tab: Confirm / Dispute / Mark wrong / Edit answer). Version records rather than overwriting the evidence trail.
- [~] Match paraphrases and reshuffled options semantically, but require stronger evidence before transferring a memorized answer to materially different wording. (keyword-overlap near-dup matching; not embedding-based)
- [x] Generate exportable study notes, flashcards, missed-question lists, concept summaries, and spaced-review queues with source links.

**Acceptance:** correcting a wrong answer changes future retrieval, preserves the earlier failed attempt, and places the topic in review material.

### 7. Answer entry and browser interaction

- [x] Support `observe`, `suggest`, `fill`, and `submit` modes. `fill` enters an answer without final submission; `submit` requires its own explicit setting (auto-submit checkbox), and a restored submit mode downgrades to suggest at startup.
- [x] Resolve the intended control from the current structured question, then revalidate target window, page identity, control bounds, and visible prompt immediately before each input (guard + fresh Acc relocation + mid-run pixel check).
- [x] Use the existing AHK mouse/keyboard primitives for input (the plan is composed in the workflow engine's action vocabulary). Add configurable human-paced timing, bounded pointer-path variation (bezier with wobble), hover pauses, and optional typo-and-correction behavior that always verifies the final field value before proceeding (`StudyComposer.ahk`).
- [~] Handle accessible text fields, radio groups, checkboxes and native dropdowns with exact selected-state/value verification. Ordering, matching, drag-and-drop, custom widgets and inaccessible controls require review. Dropdown selection uses guarded Home/Down/Enter and supports up to 64 options.
- [x] Never click `Next`, `Submit`, or irreversible controls based solely on coordinates from an old screenshot. Stop on uncertain target state (safe stop). [~] CAPTCHA/proctoring detection: password-shaped fields are refused and unknown widgets abstain, but visual CAPTCHA recognition is not attempted.

**Acceptance:** input goes only to the pinned Chrome tab, final values match the proposed answer, and a stale or obscured target causes a safe stop rather than an unintended click.

### 8. Privacy, observability, and release checks

- [~] Capture a selected pinned page/region and refuse protected fields as input targets. General PII/payment-field redaction is not implemented; OCR and screenshots may contain any visible content inside the selected region. Inspect the captured material before requesting a provider proposal.
- [~] Configurable retention for screenshots, source text, question history, and logs; export/delete controls. (frames auto-delete unless “Keep debug frames”; sources deletable; a global retention scheduler is not built)
- [x] Activity panel on a side monitor or non-activating overlay showing current question, source, confidence, mode, API status, and last action without taking Chrome focus.
- [~] Native fixtures cover classification, parsing, strict compilation, memory shuffling, feedback ambiguity, provider cancellation, feature memory and exact algebra validation. Real vision requests passed the four-page math demo; rate-limit/backoff remains unverified.
- [~] Windows live practice-page test passed on the primary monitor of the actual three-monitor desktop, including negative-coordinate monitor enumeration, moved controls, focus loss and ABORT during typing. Side-monitor reading, monitor hot-plug and live input on every monitor remain unverified.

### 9. Environment-based workflow tools (2026-10-06 extension)

- [x] Workflow Lab displays gathered OCR and a catalog of named controls with IDs, roles and fresh bounds.
- [x] DeepSeek composes TYPE / SET / CHOOSE / HOVER / WAIT commands from a user goal and the observed environment. The compiler provides feedback for one bounded repair attempt. A complete invalid proposal is rejected before input.
- [x] Preview before Run; reuse one saved local tool without a new API request when its URL and control catalog match a new capture.
- [x] Native AHK controls mouse paths, overshoot, hover, WPM, pauses, typing corrections and keyboard selection. ChatGPT desktop control is not part of the application's execution path.
- [~] Workflows are bounded plans on a pinned browser page. Unrestricted generated code, arbitrary keyboard shortcuts, general desktop app control, autonomous multi-page goal loops and a multi-tool library are future work.

**Acceptance:** a dry run yields a complete trace of perception → evidence → proposed answer → verification, with no credential leakage or focus change.

### 10. Visual algebra, descriptive features and verbose demonstrations

- [x] Read equations drawn as pixels through DeepSeek Flash image input; display the transcription and short educational worked steps.
- [x] Check finite real algebra with installed SymPy through a fixed helper and a restricted AST parser. Validate all roots by substitution and preserve rational/radical domains. Refuse executable expressions, unresolved/infinite results and unsupported syntax.
- [x] If model roots disagree with exact verification, give the model one repair with CAS feedback. Keep the original transcription unchanged; unresolved disagreement stops input.
- [x] Associate captured IDs with names, kinds, descriptions, supported commands, bounds, values and provenance. Persist DeepSeek descriptions by exact URL and stable role/name identity; include them as inferred data in planning prompts.
- [x] Generate and validate a fresh command tool on each of four sequential local practice pages. Check all required values/states before execution, observe correct feedback and re-pin only the explicit expected next local URL.
- [x] Live console and persistent JSONL log show captures/OCR, finds, description associations, local lookups, API prompts/replies/usage/cost, rejections/repairs, input attempts including waypoints/typos, exact read-back and transitions. Credentials and image base64 are excluded.
- [x] Retain math screenshots, generated scripts and feature catalogs; provide in-app Demo Guide, solver readout, console filters and emergency abort.
- [~] Math verification applies to the transcription, not a guarantee that the original screenshot was read correctly. General desktop navigation and unrestricted autonomous tool creation remain outside this bounded controller.

## Implementation map (what lives where)

| Layer | File | Role |
|---|---|---|
| Study persistence | `lib/StudyDB.ahk` | sources, passages, concepts, links, answer trail, review queue, qa_item evidence columns |
| LLM provider | `lib/StudyLLM.ahk` | DeepSeek adapter (text + vision), credential store, probe, cost cap, retry/backoff |
| Ingestion | `lib/StudyIngest.ahk` | file/PDF/notes import, concept extraction, side-monitor read-along |
| Study engine + bank UI | `lib/StudyAssistant.ahk` | `Study_Answer()` layered engine, verification states, spaced review, exports, “Study Assistant” tab (18) |
| Session + perception | `lib/StudyAutomation.ahk` | monitor geometry, pin/URL-origin guard, frame signatures, Acc+OCR fusion, question model, feedback detection, status overlay |
| Human input + plans | `lib/StudyComposer.ahk` | self-composed entry plans in engine vocabulary; curved paths, hover, typos, per-step relocation + verification |
| Live orchestrator | `lib/StudyLive.ahk` | session loop, live answer bridge to `Study_Answer`, confidence floor, portal feedback learning, “Live Portal” tab (19), hotkeys |
| Workflow tools | `lib/StudyTools.ahk` | captured control catalog, DeepSeek proposals/repair, strict compilation, preview/run/save and controller settings |
| Verbose audit + features | `lib/StudyConsole.ahk` | JSONL stream, live console, role/function descriptions, credential redaction and descriptive feature memory |
| Visual algebra | `lib/StudyMath.ahk`, `fan/tests/algebra_solver.py` | screenshot transcription, worked explanation, exact real-domain verification and bounded model repair |
| Sequential demo | `lib/StudyDemo.ahk`, `fan/tests/algebra_portal.html` | four page captures, self-composed tools, native input, feedback and scoped navigation |
| Tab glue | `fan/Tabs/Tab_18_StudyAssistant.ahk`, `fan/Tabs/Tab_19_PortalAssist.ahk` | tab registration |
| Entry wiring | `fan/MacroAutomator.ahk` | includes, tab list, hotkeys (`Ctrl+Shift+Y` toggle, `Ctrl+Shift+U` pin), startup restore |

## Proposed build order (as delivered)

1. Session pinning, monitor geometry, capture regions, and focus guard. ✅
2. Structured question/control extractor plus fixture corpus. ✅
3. Study-material ingestion, indexed evidence, and question bank. ✅
4. DeepSeek adapter and layered answer selection. ✅
5. Suggest mode, then verified fill mode, then separately enabled submit mode. ✅
6. Feedback learning, study-material export, privacy controls, and live validation. ✅ (live three-monitor validation pending — see below)

## Design decisions (settled during implementation)

- Portal-specific access: **no extension/DOM** — accessibility (Acc on Chromium's a11y tree), Windows OCR word boxes, and vision screenshots are the only perception sources, per the original request.
- Exact capture boundaries: rendered page document by default, client area when unavailable, or a window-relative dragged rectangle. Physical coordinates are used across mixed-DPI monitors.
- Confidence thresholds: entry floor defaults to 0.75; the local deduction engine has its own stricter internal gates; portal feedback marks `portal-confirmed` (reused without API calls), wrong feedback marks `disputed` and sends the pair to review.
- Automatic submission: only in `submit` mode AND with the auto-submit setting on; startup always restores submit mode as `suggest`. Mode changes stop the current session and require Start again.
- Model mapping: `deepseek-flash` for vision, `deepseek-v4-pro` for text (the requested `deepseek-v4-flash-vision-exp` alias retires to Flash).

## DeepSeek references checked for this spec (2026-10-05)

- [Models and pricing](https://api-docs.deepseek.com/quick_start/pricing/) — current model IDs and vision support.
- [Vision guide](https://api-docs.deepseek.com/guides/vision/) — image input format and legacy alias behavior.
- [List models API](https://api-docs.deepseek.com/api/list-models/) — runtime model discovery.

**Credential note:** the key shared in chat should be rotated in DeepSeek's console because it has been disclosed in a message. The replacement should be supplied to the application through a secret store or `DEEPSEEK_API_KEY`, never committed to this repository. The Live Portal and Study Assistant tabs both offer “Save API Key” (Windows Credential Manager, DPAPI-backed).
