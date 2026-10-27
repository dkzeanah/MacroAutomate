# Study controller implementation and validation

## Storage and passive learning validation (2026-10-12)

Database Export and Offload now both archive, remove the originals, and install
empty verified schemas at their active paths. Reset journals recover interrupted
replacement before startup. Legacy INI import is suppressed after an archive.
Photos persist as Base64 in SQLite; viewers and image exports decode on demand.
Existing-photo migration uses an explicit Settings action and controlled restart.
Automatic discovery records bounded semantic targets and Claude/ChatGPT/development
contexts, with exact live name/role/window checks before automatic target reuse.

Validated using isolated temporary databases and synthetic native windows:

- 46 Python maintenance checks, including archive integrity, FTS/trigger/view/index
  preservation, ID reset, cancellation, interrupted replacement, and image byte equality.
- 14 bridge contract, MCP inventory, learning-prompt and image-provenance checks.
- 42 native Settings/storage/crypto/monitor-selection checks.
- 9 native live-panel checks, including real preview pixels, visible green boxes,
  unchanged focus, and the entire frame staying off display 1 and the primary display.
- 31 native OCR/MSAA/FindText/snapshot/semantic-target checks, including scratch-file
  removal and refusal to reuse a changed control.

Git Bash launcher validation succeeds using `sh fan/run_fan.sh --validate` with
native argument conversion disabled. Existing variable-shadowing warnings remain.
The live application and personal databases were not reset by these tests.

Audited and extended on **2026-10-06**. The native controller and the
DeepSeek-to-workflow path work on the disposable Chrome practice page. This is
a working first layer of environment-based automation; the whole feature ledger
is not a completed acceptance suite.

## What is available

Run MacroAutomator.ahk and open **Live Portal → Workflow Lab**. Select **fill**
in the lab, pin Chrome, and capture. Named controls, IDs, roles, physical bounds
and OCR are shown before planning. **Input Settings** configures WPM, typo chance,
typing pauses, hover, pointer curvature, bounded overshoot and click variation.

**Generate with DeepSeek** sends the goal and captured environment to the
configured provider. It generates a bounded command workflow, receives compiler
feedback for one repair if necessary, and presents the proposal for preview.
**Run** executes it through production AHK input code. ChatGPT desktop control is
not a runtime dependency. The controller checks focus throughout input, refreshes
control identity and bounds before clicks, and reads back exact values/states.
One validated tool can be saved locally and re-bound to a matching new capture.

See [README.md](README.md#start-with-the-built-in-workflow-lab) for the walkthrough.
The isolated StudyValidationLab.ahk also has **Run Full Validation** and
**Run DeepSeek Validation** buttons. It uses its own SQLite database and leaves
the existing main application process and user database alone. Relaunch the main
MacroAutomator.ahk when you want its process to load the edited modules.

## Defects found in the earlier implementation

| Finding | Repair |
|---|---|
| ABORT did not interrupt an in-flight typing/movement loop | Cancellation checked at each key/waypoint and in short sleep slices; pending HTTP requests abort too |
| Text steps lost the control identity; partial/case-insensitive matches could count as verified | Identity retained; exact fresh values compared, preserving case and whitespace |
| A selected checkbox could be toggled off on a repeated run; unwanted selections remained | Desired-state SET actions are idempotent and clear unwanted choices |
| Cached letters could become wrong after option shuffling | Re-map the entire unchanged choice set by text; invalidate changed/ambiguous sets; version question/choice snapshots |
| Near-duplicate history ignored negation, quantities and option meaning | Qualifier/quantity checks and complete choice remapping before provisional reuse |
| Three-monitor DPI virtualization distorted capture/input coordinates | Physical per-monitor geometry; window-relative custom regions; virtual-desktop pixel sampling including negative coordinates |
| Native timing helper shadowed AHK's Min function and failed at runtime | Renamed its parameters; live movement/typing now exercise the actual helper |
| Full Chrome accessibility walks repeated on nearly every waypoint | Cache the document/address-bar objects while reading their current properties; refresh target observations before input |
| A hidden zero-size Chrome renderer could become the capture target | Bind the largest visible page document and reject invalid geometry |
| Chromium hit tests returned a button's text child | Resolve its actual control ancestor and require matching identity/bounds |
| Native dropdown focus belongs to its selected list item | Guard that focus, navigate with Home/Down/Enter, then verify the committed dropdown value |
| JSON decoding failed on nested numbers; credential buffers used incorrect sizes | Fixed parsing and UTF-8/UTF-16 buffer allocation; tested with synthetic credentials |
| Provider calls blocked cancellation and did not account for truncated responses | Async receive, cancellation, usage accounting before completion rejection, request budget estimate and one active request |
| Observe mode could invoke the answer engine/API | Observe now captures only |
| Feedback detection could match ordinary question wording or an old result | Explicit result phrases, new feedback relative to baseline, same-question/URL association, timeout and ambiguity abstention |
| Numeric rechecking removed units | Preserve numeric values with units |
| The ledger implied binary document formats and PDF continuation were supported | Unsupported formats refused clearly; documented actual PDF page limit/re-import behavior |

## Completed checks

**84 automated checks passed:**

- **59** native parser/planner/controller fixture checks: classification,
  exact verification, prose/multiple-choice parsing, protected targets,
  blank counts, desired checkbox states, strict workflow validation/limits,
  negative-coordinate bounds, cancellation, JSON and synthetic credential I/O.
- **16** production SQLite integration checks: empty-schema setup, exact
  question deduplication, confirmed memory reuse without API access, option
  shuffle remapping, changed-choice invalidation, preserved snapshots,
  portal-confirmed memory, negation/quantity checks, history remapping and units.
- **9** loopback provider checks using a process-local synthetic key: UTF-8,
  usage/cost parsing, malformed/truncated response refusal, cost accounting,
  cancellation in under 1.5 seconds, budget/concurrency refusal and one compiler
  feedback repair. The fixture server was stopped after testing.

The full main entry point passed AutoHotkey v2 /validate with exit **0**.
Existing unrelated warnings remain; the main application was not restarted as
part of this audit.

### Actual desktop and provider run

The app enumerated three physical 1920×1080 monitors at **-1920,0**, **0,0**
and **1920,0**. The live input test ran on the primary monitor's Chrome practice
window, with mixed-DPI coordinate handling.

The successful real DeepSeek deepseek-v4-pro proposal was:

~~~text
TYPE 1 Mitochondria
SET 2 1
SET 4 1
SET 3 0
CHOOSE 5 Paris
~~~

The app compiled and ran all seven underlying actions. Final fresh read-back
confirmed **Mitochondria**, **Apple + Carrot**, **Banana cleared** and **Paris**.
It moved the field, executed the same stale-bound plan successfully, and kept
the already selected checkbox states on the repeated run. Separate focus-loss
and ABORT tests stopped typing at **“I”**, then checked that no further text
appeared after 500 ms. The final demonstration restored the correct values.

The page reported **42 key events, 7 backspaces and 114 pointer moves** after
the run, showing the controller's real input and typo corrections. The real
successful proposal's recorded token-cost estimate was **$0.000697**. Earlier
invalid provider proposals were rejected before input. The key came from the
environment and was never displayed or copied into the transcript.

Inspect [the saved DeepSeek/live transcript](tests/deepseek_live_validation.txt),
[the controller lab screenshot](tests/workflow_validation.jpg), or
[the practice-page result](tests/practice_validation.jpg). The full live_results.log
also retains failed diagnostic attempts and their subsequent fixes.

## Visual algebra and verbose automation extension

The real four-page visual run completed with DeepSeek Flash image input and
DeepSeek Pro command generation. Equations were drawn on a canvas; no equation
text was exposed as accessible page content. Exact SymPy verification found
`x=7`, `x=2,3`, `x=4; y=3`, and `x=4`. Every page's values, dropdown and checkbox
states passed fresh read-back and the local page's correct-feedback check before
the next authorized URL transition. The controller itself supplied all mouse
and keyboard input.

Earlier run audits retained incorrect model answers; the final audit also
records a quoted-literal tool rejection and repair.
CAS feedback repaired a contradictory answer without altering the transcription;
the semantic tool validator prevents wrong values, quotes, omitted controls and
later contradictory writes from reaching input. Feature descriptions carry model
provenance, persist by URL/kind/name, and are provided to subsequent planning.
Structured logs include prompts/replies, cost estimates, local retrieval, exact
algebra checks, target relocation, pointer paths/hover/overshoot, key attempts,
typing corrections and page transitions. Math screenshots remain available for
comparison with the displayed transcription.

New checks: **27 Python algebra tests**, **18 native intelligence/logging tests**,
and semantic-repair/missing-image provider fixtures (**12 provider tests** total).
The prior **59 controller** and **16 memory** regressions still pass. Together
these are **132 checks**; the live demonstrations are additional evidence.
The main AHK entry point parses successfully; unrelated pre-existing warnings
remain. A previously uninitialized status-overlay global was fixed so focus loss
reports a normal stopped run even before the overlay has been opened.
The solver readout now selects the monitor by actual left/right placement rather
than assuming monitor 1 is a side display. Algebra notation such as `5x`,
`3(x-1)` and superscript squares is normalized before the restricted AST parse.

The final three-monitor run recorded **1,321 audit events**, **9 corrected
typos**, **30 bounded overshoots**, and **443 planned pointer waypoints**.
The final page showed **72 key events, 9 backspaces and 34 clicks**, with all
four PASS results visible. Nine real provider attempts cost an estimated
**$0.01652916**. The actual configured provider key was checked absent from the
saved audit. [Full JSONL audit](logs/study/20261006-172236-58087140.jsonl),
[practice proof](tests/math_demo_validation.jpg),
[solver proof](tests/math_solver_validation.jpg), and
[console proof](tests/math_console_validation.jpg) remain local for review.

Use **Workflow Lab → Run 4-page Math Demo** to repeat; **Demo Guide** provides
the built-in instructions. See [README.md](README.md#visual-algebra-100-and-the-four-page-demonstration)
for supported algebra and library coordination examples.

## Remaining limits

- Plans operate on named accessible controls in a pinned browser page. General
  desktop app control, arbitrary code/shortcuts, general autonomous multi-page planning,
  tool selection across a library, drag/drop, ordering/matching and custom
  inaccessible widgets are not implemented by this controller.
- Pinning uses window identity, full URL, title and prompt. Two identical tabs
  with the same URL/title/prompt cannot be distinguished without another tab ID.
- OCR can be noisy; compound forms are not fully segmented. The workflow lab
  can explicitly target different controls on one form. OCR-only clicks with
  no readable selected state are refused. Dropdowns are limited to 64 options.
- Exact answer memory and complete option shuffles are tested. Retrieval,
  concept extraction and confidence scoring are heuristic, not a trained or
  statistically calibrated reasoning system. Unverified model/history/deduction
  suggestions remain candidates. Default confidence gates can therefore leave
  the page untouched; review or confirm the answer instead of assuming entry.
- Imports support PDF, text and Markdown. Other documents need export first.
  PDF processing defaults to the first 60 pages; re-import starts at page 1.
- Side-monitor read-along, monitor hot-plug, input on each
  monitor, provider throttling/backoff and scored-portal auto-submission were
  not live-tested. Feedback attribution is conservative and requires manual
  review when it cannot associate a new explicit result with the same question.
- Protected controls are refused as targets. General PII/payment-field redaction
  is absent: inspect the selected capture before sending it to a provider.
  Frame deletion is implemented; a general retention scheduler is not.
- The visual algebra path supports finite real equations/systems in x/y/z,
  rational operations, bounded integer powers and square roots. It refuses
  unsupported/unresolved expressions. Exact verification checks the transcribed
  equation; inspect the retained screenshot for misread signs/fractions. Worked
  explanations are model-generated; individual explanation steps are not CAS proofs.
- The sequential demo authorizes navigation only on its exact local practice
  file. General portal navigation and arbitrary button effects are not inferred
  or auto-enabled by feature descriptions. Verbose audit files and math images
  retain study content locally; there is no automatic expiry policy yet.
- Provider costs are estimates using configured rates and an input/output
  allowance, not a guarantee of the account's final bill. The official
  [Chat Completions reference](https://api-docs.deepseek.com/api/create-chat-completion/)
  was checked for response options; bounded workflow requests disable
  thinking mode so the token budget produces usable commands.

## Unified DeepSeek bridge validation — 2026-10-12

The **DeepSeek Bridge** tab now uses one tool-enabled agent for conversation,
native inspection, workflow composition and managed AHK script execution.
Scripts, source revisions, input schemas, descriptions, usage examples and
observed/inferred knowledge are indexed locally and retrieved in the refreshed
system prompt. Generated scripts can call Fan through `FanBridgeClient.ahk`.

The running Fan bridge was verified through its actual loopback gateway, worker
and internal API. It reported **35 tools** and **66 native workflow action
definitions**. The gateway authored and indexed `fan_api_diagnostic.ahk`, ran it
with installed AutoHotkey v2, and captured successful output from calls into
the live Fan capabilities and input settings APIs. No model API request was
needed for this live execution check.

Completed checks:

- **45 Python bridge tests**: unified tool advertisement, source/metadata
  revisions, input schemas, managed execution/cancellation, authenticated native
  FIFO calls, completed-parent script lifetimes, SSE streaming and automatic
  Pro → Flash → Pro image routing with retained native geometry/provenance.
- **39 native API assertions** and **11 standalone SDK assertions**: real
  action schemas, workflow validation/rollback, source bounds, settings, UTF-8,
  optional crop handling and generated-script API calls.
- **24 native perception checks** using real OCR, accessibility, GDI+ and
  FindText, including numbered/grid captures, exact matching, query filtering,
  crop validation and hidden-window refusal without changing focus.
- **11 interface checks** with a loopback mock provider: visible queue/Stop,
  streamed Unicode replies, history, cancellation/restart, persistent script
  Stop after a completed reply, and shutdown without orphan scripts.
- OCR and workflow regression modules passed, including absolute OCR centers,
  nested child loops, fail-fast propagation, recursion, responsive cancellation
  and unresolved-target refusal before unattended clicks.
- Layout passed at **900×780**, **1536×793** and **1920×1030**. Full Fan
  AutoHotkey `/validate` exited **0**; existing unrelated warnings remain.

The final build was reloaded. One live DeepSeek task then called the actual
`ahk_script_run` tool on the existing read-only diagnostic, received successful
native SDK output and reported exit code **0**. Automatic image routing was
verified separately with synthetic model responses and real native captures.
The actual Pearson page still requires live layout/accessibility verification;
its earlier local replica checks do not establish live Pearson compatibility.

## Learning consolidation and storage maintenance — 2026-10-12

Settings now contains local consolidation, export and offload controls for the
five managed Fan stores and snapshots. The actual tracking file measured
**113,990,627,328 bytes**, approximately **106.2 GiB**. No production offload was
performed without a destination selected by the user.

The first read-only consolidation completed in **2.49 seconds**, examining
**41,254** bounded metadata/aggregate rows and producing **8 findings**.
Its report distinguishes full current-table coverage from sampled history;
it does not extrapolate the entire database from the latest snapshot rows.
The compact brief was published to the saved-tool index and made available in
the agent prompt and `fan_learning_insights` API.

Examples from that report: **19** repeatedly clicked mouse candidates need
validated reusable targets; **3,535 of 4,074** inspected App Learner elements
already have semantic locators; and **64** sampled snapshot rows recorded
**24,514,194 bytes** of image files alongside **32,685,660** embedded Base64
characters. A recurrent Scout sequence and missing demo-pattern references
are review candidates, rather than verified automation or deletion decisions.

Verification used disposable stores and image fixtures:

- **41 Python maintenance checks** passed for bounded evidence analysis,
  WAL-aware exports, schema/index/trigger/version preservation, integrity and
  hashes, space/preflight guards, interruption/resumption, source locks,
  coordinator route commits, rollback, cancellation and actual Windows junction
  cutover/cleanup/recovery.
- **25 native Settings checks** passed for the real controls, Unicode routes,
  missing-store refusal, on-demand/legacy Base64, worker failure status, actual
  junction identity, and refusal to capture into a missing/wrong snapshot alias.
- **45 bridge regression checks** passed with the new insight API and routed
  tool index. The full Fan and standalone helper passed AHK syntax validation.

Legacy snapshot image hashes are prefix/path fingerprints; transfer verification
uses full file SHA-256 instead. Source data is removed only after verified
cutover, and source DB handles remain guarded until cleanup finishes. Offload
preserves historical snapshot paths and avoids moving unrelated application
databases. Configured drive unavailability never creates an empty replacement.

The destination picker was then replaced with an explicit mounted-drive list
after the default folder dialog failed to expose external disks. The native
Settings/drive harness passed **36 checks**, including all mounted letters,
fixed/removable drives, label/free-space metadata, pasted Unicode paths,
invalid/missing locations and network snapshot restrictions. The picker checks
database transfer space before closing Fan. Full Fan syntax passed, and the
updated app was reloaded in Settings with healthy bridge services.

## Single-file storage and fresh starts - 2026-10-12

The later user request supersedes the five-store routing above. Fan now routes
tracking, macros, App Learner, bridge and catalog to `data/fan.sqlite`.
App settings, notes, calendar documents, persistent logs, insight reports and
generated-script source/revisions also live in this database. Viewer images,
Chrome history copies and study/solver intermediates use private session
caches; explicit exports remain physical files. The small bootstrap JSON holds
only the active path and initialization marker.

Missing active storage seeds the complete empty schema atomically, without
legacy reimports. Nonempty orphan journals block seeding rather than replaying
or deleting historical data. Both Settings database actions archive one file
and reset its schema. The two distinct app identity tables retain their IDs.

Verification: **57 maintenance tests**, **50 bridge tests**, and **103 native
checks** passed. Coverage includes missing-file restart, no legacy refill,
shared database routing, INI/document/empty-text persistence, generated scripts
without required source files, relocated images, skipping embedded photos,
row/ID/index/view/trigger preservation, repeatable migration and archive/reset.
Native tests verify actual Base64 image rendering and secondary-monitor preview
pixels, target-box color and nonactivation. Git Bash full Fan validation and
`git diff --check` passed, with existing variable-shadow/line-ending warnings.

The production C: file was seeded and Fan restarted. All five routes resolve
to that file and `PRAGMA quick_check` returns `ok`; no old snapshots were
reimported. Historical consolidation is queued in
`fan/.maintenance/unified_archive_20261012_065731`. At verification time,
Explorer was still moving the original database and snapshot folder to K:.
The worker reported `waiting` and had not opened the external archive. It will
merge only after source names disappear and exclusive-access probes succeed.
Legacy image files and small source stores remain for verification; a missing
image or interrupted migration is surfaced rather than silently discarded.
