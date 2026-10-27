# fan — Combined Multi-File Build of Macro Automator v9

The [Learning Workbench guide](EVIDENCE_LEARNING.md) explains evidence-backed
claims, generated lessons and sequence rehearsals, randomized background replay,
and Ctrl+right-drag movement for secondary windows. Open it from the tray or
**Live Portal → Explain learning**.

Read the [comprehensive automation guide](AUTOMATION_USER_GUIDE.md) for all 66
Workflow actions, Patterns/FindText, OCR and Watch Words, spools, common sequences,
window/menu/shortcut learning, the 20 tabs, DeepSeek input simulation, visual math,
logs, and current implementation limits. The [searchable browser edition](AUTOMATION_USER_GUIDE.html)
also opens from **Workflow → Action Guide** after reloading the app. To rebuild
the browser edition after documentation edits, run `pwsh -File fan/Build_Automation_Guide.ps1`
from the project root.

This folder combines the features of `macroautomaterv9-deepseek.ahk` and
`macroautomaterv9-chatgpt.ahk` in a multi-file project. The GUI tabs are the
primary organizing unit: each tab's controls and the functions it uses live in
one file under `Tabs\`, so you can open just the file for the tab you are
working on without wading through the whole ~20k-line script.

Both v9 learners are present rather than choosing one branch over the other:

- **Vision Scout** keeps the DeepSeek branch's candidate review, movable scan
  overlays, FindText testing, certify/reject/reset gates, certified-only Pattern
  export, guide, and learned sequence offers.
- **Usage Predictor** keeps the ChatGPT branch's coarse virtual-desktop scan,
  promoted elements, app/click/key/type event model, and n-gram continuations.
- **Tracking > Key History > ALL** interleaves typed runs and clipboard
  captures in capture order, labels each event by type, and numbers the
  sequence. Existing pre-v5 history is carried forward in a best-effort legacy
  view because old minute snapshots did not timestamp each individual typed
  run; new activity has exact event order.
- Vision Scout accepts an armed offer with `Win+CapsLock`; Usage Predictor uses
  `Win+Shift+CapsLock` so both can run together without overwriting a hotkey.
- The current DeepSeek branch's native tray-menu icons are included, along with
  the Usage Predictor tray submenu and the AutoFlow capture diagnostic.

## Learning, database archives and photos

### Single-file storage

Fan now uses `data/fan.sqlite` for tracking, patterns/workflows/spools, App
Learner, bridge events/tasks, the tool catalog, images, settings, notes,
calendar records and app logs. The tracking `app` and learner `appmap_app`
tables are separate identities in this same database. A small machine-local
`fan/storage_paths.json` contains only the database pointer and initialization
marker; program files, OS credentials and disposable runtime caches remain
outside the data store.

If the active database is missing, startup atomically creates the complete
empty schema. It never silently reimports the old five databases, loose
settings, notes or photos. Close Fan and its bridge before manually moving
the database, so SQLite checkpoints its temporary WAL/SHM sidecars. A nonempty
orphan journal blocks seeding rather than replaying or discarding old history.

Both database Export and Offload archive **one** database and then reset that
active file to an empty schema. Image files are materialized only for viewing,
API consumers, or explicit image exports; persistent images are Base64 TEXT.

For the existing external-drive archive, **Consolidate old archive...** merges
the remaining legacy stores and app documents into the moved tracking DB,
then embeds only photos that have no embedded payload. Relocated snapshot
paths are resolved against the selected folder. Existing embedded images
are skipped using SQLite byte-length metadata, not reencoded. Small-store
IDs, views, indexes, triggers and auto-increment counters are retained and
imported rows are verified. Originals remain available for verification.
The move must finish first; a queued merge waits for original source names
to disappear and for exclusive access before opening the external archive.

Native schema generation (new fixture path only):

```powershell
AutoHotkey64.exe /ErrorStdOut=UTF-8 fan/MacroAutomator.ahk --seed-db C:/temp/fresh-schema.db
```

Explicit historical consolidation, after the Explorer move completes:

```powershell
fan/DeepSeekBridge/.venv/Scripts/python.exe -m fan.data_maintenance.unified consolidate . K:/tracking.db --snapshots K:/snapshots
```

**Settings → Learning insights and storage** provides:

- **Consolidate insights** for a 7/30/90-day view of learner aggregates and
  recent metadata. **View insights** opens the compact report. Observed counts,
  source IDs, time windows, module associations and coverage are retained;
  recommendations remain candidates requiring live verification.
- **Export databases / Offload databases** both archive and start fresh.
  Fan saves and closes, imports existing capture photos into SQLite, creates
  WAL-aware verified backups at the selected destination, then deletes each
  original database and installs an empty copy of its schema at the original
  active path. Tables, indexes, views, triggers and schema versions are retained;
  historical rows and ID counters are reset. Old INIs are not reimported.
  Each empty schema is staged before replacement. An interrupted reset is
  recovered before startup opens any store; cancellation precedes replacement.
- **Export snapshots** decodes database photos into verified image files.
- **Import stored photos** migrates existing file-backed captures into SQLite
  and removes unchanged app-owned file copies after their references commit.
  Photo import/export saves, closes and reopens Fan to refresh in-memory references.
  Source images outside managed capture folders remain in place. Existing-photo
  migration is explicit; it does not run automatically at startup.
- **Automatic discovery** passively inspects the active window while input is
  idle, saving bounded accessibility observations, names, roles, shortcuts and
  locator paths. Claude/ChatGPT topics and development contexts are tagged from
  window titles, process names and available browser URLs. Automatic targets
  enter App Learner and require an exact live window/name/role match.
- **Live validation** shows target previews, colored boxes, evidence stages and
  timestamps on a secondary display. Select monitor 2 or 3, or use automatic
  selection. Display 1 and the primary display are excluded, including on
  mixed-DPI setups. If no eligible display is connected, floating feedback is
  hidden. Observed/stored evidence is distinguished from live verified matches.

Destination selection lists **all mounted drive letters**, including external
USB disks reported by Windows as fixed disks, with labels and free/capacity
figures. Use **Refresh** after connecting a drive, **Use drive root** to select
it directly, or **Browse**/paste an existing folder. Database selections check
available space before Fan closes for offload.

The managed databases are tracking/learning, workflow/patterns, App Learner,
DeepSeek request history and the saved-tool index. Manager/GlobalCoder stores
remain outside this transfer. Other processes holding a managed database open
must close before offload; source guards prevent reopening it during cutover.

Database routes live in machine-local `fan/storage_paths.json`, outside the
archived data. Archives never become active database routes. A disconnected
configured database drive is reported as unavailable; reconnect it to resume.

New snapshots, element crops, pattern photos and retained study/bridge images
store Base64 strings in SQLite. Built-in viewers decode them on demand; temporary
processing/view files use a bounded session cache removed at exit. Snapshot
Recovery searches the database, so photos remain discoverable without disk files.

Reports are in `data/learning_insights`; bounded analysis avoids reading image
blobs, raw keystrokes, clipboards and page bodies. DeepSeek receives the compact
reference in its refreshed prompt and can query `fan_learning_insights` or
`FanBridge.Insights()`. `fan_discovered_targets` / `FanBridge.DiscoveredTargets()`
also expose fresh passive semantic observations. It can use recurrent sequences, certified targets,
semantic App Learner locators and verification gaps to improve proposed
automations. Frequency is distinguished from successful execution, and
cross-store numeric IDs are not treated as interchangeable.

Maintenance jobs, progress, manifests and recovery journals are under
`fan/.maintenance` and the selected export/offload bundle. Large transfers run
in a background worker rather than loading whole databases or snapshot trees
into the GUI. The first report is a bounded analysis, not a deletion/compaction
of historical source rows.

## Launch

```
fan\MacroAutomator.ahk
```

That file is the entry point — run it with AutoHotkey v2 (e.g. double-click it,
or: `AutoHotkey64.exe fan\MacroAutomator.ahk`). It `#Include`s everything else.

There is also `Run_MacroAutomator_Logged.cmd`, a launcher in the same style as
the project root's `Run_macroautomerv8_Logged.cmd`: it starts the entry file
with `/ErrorStdOut` and appends all startup output (warnings included) to
`data\logs\macroautomaterv9_fan_startup.log`.

**Git Bash note:** do not type `AutoHotkey64.exe /ErrorStdOut ...` inside a Git
Bash terminal - its MSYS layer rewrites `/ErrorStdOut` into
`C:/Program Files/Git/ErrorStd...` and AutoHotkey reports
"Script file not found". Use the dedicated launcher instead:

```
sh fan/run_fan.sh
```

`run_fan.sh` disables that path conversion for the launch
(`MSYS2_ARG_CONV_EXCL='*'` and explicit Windows paths) and writes a
timestamped startup log per launch (the running instance holds its own log
open, so a fixed name would hit a Windows file lock). Alternatively launch
without the switch entirely:
`"/c/Program Files/AutoHotkey/v2/AutoHotkey64.exe" fan/MacroAutomator.ahk` -
`/ErrorStdOut` only controls where startup warnings are printed, never
behavior.

Note: startup takes a few seconds on this machine (tracking-DB init) before the
main window appears — the single-file original behaves exactly the same way.

- `_original_macroautomaterv9-deepseek.ahk` is the pristine copy of the old
  single file, kept for reference/diffing. It is NOT run.
- `sqlite3.dll` must sit in this folder (it does): `SQLiteDB.ahk` looks for it
  next to the running script, and the entry script lives here. The tracking
  subsystem (`lib\TrackSQLite.ahk`) tries `fan\lib\sqlite3.dll` first and then
  `fan\sqlite3.dll`, so the copy in this folder covers both.

## Layout

```
fan\
  MacroAutomator.ahk            entry point: directives, includes, globals,
                                main window shell, global hotkeys, startup
                                sequence
  _original_macroautomaterv9-deepseek.ahk   pristine copy of the old file
  sqlite3.dll                   SQLite native library
  SPLIT_MANIFEST.md             exact original-line -> file mapping
  Core\
    _Globals.ahk                every g_* global, file-path constants, settings
    _Helpers.ahk                logging, overlays, taskbar index, tray menu,
                                verified click/type/window helpers, GUI resize
    _Db.ahk                     SQLite open/migrate, patterns/sequences/spools
                                persistence, SaveAll / LoadAll
    _Notifications.ahk          stackable notification windows, schedules,
                                action/error reporting
    _Gdip.ahk                   GDI+ screenshot core
  Actions\
    _Engine.ahk                 workflow execution engine (ExecuteSequenceVerified,
                                ExecuteActionVerified, all Execute* helpers)
  Tabs\
    Tab_01_Workflow.ahk         tab 1 GUI + step editor, library, .maw manager,
                                demo lab, sequence triggers, run/simulate
    Tab_01_Workflow_Forms.ahk   tab 1 guided action forms, choices, coordinate
                                manager
    Tab_02_Patterns.ahk         tab 2 GUI + definition mode, capture, preview
    Tab_03_LiveOCR.ahk          tab 3 GUI + OCR capture, watch words, OCR
                                revolver, Quick OCR (Ctrl+Shift+Q), OCR actions
    Tab_04_Spools.ahk           tab 4 GUI + spool engine, .mas import/export,
                                notification list
    Tab_05_Analytics.ahk        tab 5 GUI + full recording, hotspots, taskbar
    Tab_06_Clipboard.ahk        tab 6 GUI + extraction rules, revolver, bins
    Tab_07_Hotkeys.ahk          tab 7 GUI + sequence hotkey assignments
    Tab_08_Hotstrings.ahk       tab 8 GUI + hotstring management
    Tab_09_Triggers.ahk         tab 9 GUI + notification triggers, templates
    Tab_10_Settings.ahk         tab 10 GUI + settings persistence
    Tab_11_Notepad.ahk          tab 11 GUI + notes, popup notepad
    Tab_12_Calendar.ahk         tab 12 GUI + appointment scheduler, patients
    Tab_13_Tracking.ahk         tab 13 glue + element workflow actions
                                (its UI comes from lib\TrackingDashboard.ahk)
    Tab_14_AppLearner.ahk       tab 14 glue (UI from lib\AppLearner.ahk)
    Tab_15_SnapshotRecovery.ahk tab 15 glue (UI from lib\SnapshotRecovery.ahk)
    Tab_16_VisionScout.ahk      tab 16 glue (UI from lib\VisionScout.ahk)
    Tab_17_UsagePredictor.ahk   tab 17 glue
                                (UI from lib\UsagePatternPredictor.ahk)
```

External libraries (`FindText.ahk`, `OCR.ahk`, `SQLiteDB.ahk`, everything in
the project root's `lib\` folder) are still included from the original project
root via `..\`-relative `#Include` paths — they were already separate files and
are shared, not copied.

## Real-Time Study Assistant

Two new tabs implement `REALTIME_STUDY_ASSISTANT_SPEC.md` (see that file for the
full feature ledger and acceptance checks):

- **Study Assistant (tab 18)** — the study layer: import lesson plans/PDFs/notes,
  read along with a book on a side monitor, build concept memory, answer banked
  questions with the layered engine (verified memory → material → DeepSeek),
  verify/correct answers, spaced review, and exports (study guide, flashcards,
  missed list, concepts). Handled by `lib\StudyDB.ahk`, `lib\StudyLLM.ahk`,
  `lib\StudyIngest.ahk`, `lib\StudyAssistant.ahk`.

- **Live Portal (tab 19)** — the automation layer: use the last activated Chrome
  tab automatically (Ctrl+Shift+Y toggles the session), perceive each question
  through Windows accessibility + OCR + vision,
  answer it via the study layer, then self-compose and run a human-paced entry
  plan (curved mouse paths, hover pauses, typo-and-correct typing, per-step
  verification) made of the workflow engine's own action vocabulary. Modes:
  observe → suggest → fill → submit (submit also needs the Auto-submit setting).
  The session follows activated Chrome windows and their selected tabs. Tab changes
  discard cached controls/questions and cancel entry for the previous page.
  The window and current page are re-verified before every action;
  portal feedback is read back and pairs are learned as
  portal-confirmed/disputed. Handled by `lib\StudyAutomation.ahk`,
  `lib\StudyComposer.ahk`, `lib\StudyLive.ahk`.

The session and Live Console start automatically on program launch in observe
or suggest mode. Fan suppresses tooltips throughout the desktop; its optional
status overlay uses a secondary monitor. Restored fill/submit modes downgrade
to suggest, answers below the confidence floor are never entered, and the
DeepSeek key lives only in Windows Credential Manager or the
`DEEPSEEK_API_KEY` environment variable.

### Start with the built-in workflow lab

1. Run `fan/MacroAutomator.ahk`, open **Live Portal**, select **fill**, and click
   **Workflow Lab**. **Quick Guide** explains the session modes and hotkeys.
2. Open and activate **Practice Page** in Chrome. It becomes the learning base.
3. Click **Capture in 3 sec**. The app brings the last activated Chrome tab forward,
   gathers OCR plus named accessible controls, and shows their IDs, roles and
   bounds in the lab. Capture makes no provider request.
4. Return to the lab, write your goal, and click **Generate with DeepSeek**.
   DeepSeek proposes commands using the captured IDs. The compiler checks their
   roles and limits and allows one model repair from its feedback. Inspect the
   proposal and **Preview**, then click **Run in 3 sec**.
5. Watch Chrome as **the app's own AHK controller** moves, hovers, types and
   corrects optional typos. The lab records PASS/FAIL and exact value/selection
   checks. **Ctrl+Shift+Esc** or **ABORT ALL** stops input during a movement,
   typing burst, wait or pending provider request.

**Input Settings** sets typing WPM, typo chance, hover duration, curve variation,
overshoot amount/chance, click-point variation and typing pauses. Overshoot and
click variation stay within the current control. Dropdowns use guarded keyboard
selection and exact read-back. Long answers can use clipboard paste; the previous
clipboard is restored unless it changed during entry.

Commands refer to the IDs in your own capture (these example IDs are illustrative):

```text
TYPE 1 Mitochondria
SET 2 1
SET 3 0
CHOOSE 5 Paris
HOVER 1 250
WAIT 100
```

`TYPE` replaces an edit value; `SET` ensures a checkbox/radio's desired state;
`CHOOSE` selects a dropdown label; `HOVER` and `WAIT` take milliseconds. Unknown
IDs, wrong roles, arbitrary code/keys/coordinates and oversized scripts are
rejected before execution. Plans are bound to the captured URL, question and
control catalog; targets are located again immediately before input. **Save Tool**
stores one local reusable workflow; **Load Tool** requires a matching capture.

### Repeat the native practice validation

Open `fan/tests/practice_portal.html` in exactly one Chrome window, then run
`fan/StudyValidationLab.ahk` and click **Run Full Validation**. The isolated lab
uses the production controller and its own database. It shows gathered OCR and
controls, enters text, corrects typos, sets/clears checkboxes, selects Paris,
relocates a moved field, and tests focus loss and ABORT while typing. Leave input
idle during the sequence. The practice page shows final values and input counters.

**Run DeepSeek Validation** asks the configured provider to compose the practice
workflow first; it then validates and executes that proposal on this disposable
page. No provider key is displayed or copied into reports. The latest transcript
is `fan/tests/last_live_validation.txt`; implementation findings and verified
limits are in [IMPLEMENTATION_VALIDATION.md](IMPLEMENTATION_VALIDATION.md).

The independent native harnesses are `StudyHarness_Test.ahk` (pure planning),
`StudyMemory_Test.ahk` (SQLite memory), and `StudyProvider_Test.ahk` (loopback
provider fixture, paired with `tests/provider_mock.py`). These scripts do not
replace or restart your running main app.

### Visual Algebra 100 and the four-page demonstration

Open **Live Portal → Workflow Lab → Run 4-page Math Demo**. The isolated lab
`fan/StudyValidationLab.ahk` has the same button; launching it with `/demo-math`
starts the demonstration automatically. **Demo Guide** contains the complete
instructions inside the application. A configured DeepSeek key, Chrome and
Python with SymPy are required. This workspace already has SymPy 1.14.0; no
new dependency was installed.

The app opens its own disposable practice window and completes four pages:

| Page | Equation drawn in the image | Verified real solution |
|---|---|---|
| Fractions | `(3x − 2)/4 − (x + 1)/3 = 25/12` | `x = 7` |
| Quadratic | `x² − 5x + 6 = 0` | `x = 2, 3` |
| System | `2x + y = 11; x − y = 1` | `x = 4; y = 3` |
| Radical | `√(x + 5) = x − 1` | `x = 4` |

The equation canvas exposes only an image label to accessibility. The engine
reads its screenshot with DeepSeek Flash, checks every root with SymPy, asks
DeepSeek Pro to compose a new command tool from the captured controls, and
checks every proposed value against the verified goal before input. An invalid
model solution or tool gets one repair using the actual verifier's feedback.
The native controller fills text, selects the equation family, sets and clears
checkboxes, checks the practice answer and advances only to the expected next
local page. It captures and identifies the new environment again on every page.
Page one includes a longer verification note to demonstrate typo correction.

Keep the practice Chrome window foreground while it runs. The **Visual Algebra**
window shows the transcription, worked steps, exact roots and substitution
checks. The **Live Console** appears on a side monitor without taking focus.
**Ctrl+Shift+Esc** / **ABORT ALL** stops input and provider requests. The demo
temporarily uses 115 WPM, a 25% typo chance and a 100% bounded overshoot chance;
it restores your input settings after the run.

For your own last activated Chrome page, click **Solve Visual Algebra**. Review the equation
transcription against the retained image and inspect the short worked solution.
The lab prepares a goal containing the exact solutions; use **Generate with
DeepSeek → Preview → Run** to create and execute an answer-entry tool.
The exact solver supports finite real solutions of equations/systems in up to
three variables (`x`, `y`, `z`), rational expressions, integer powers and `sqrt`.
Unsupported syntax, unresolved/infinite solutions and uncertain images require
review. Verification proves the transcribed equation, so visually checking a
misread sign or fraction remains necessary.

### Live console, feature descriptions and library coordination

**Chat with DeepSeek** in Live Portal accepts a custom multiline message.
**Send to DeepSeek** opens a full conversation window and streams the reply into
the window, portal preview and console. **Full Chat Window** also opens it.
Queued/connecting/thinking/streaming/complete/error states and elapsed time make
progress visible. The composer supports **Ctrl+Enter**, **Stop reply** and **New
chat**. Messages wait visibly when study work is busy. The latest ten completed
exchanges provide conversation context and restore after restart.
Chat uses the configured API key and session budget. The hidden `StudyStream.ps1`
worker receives credentials through an anonymous pipe and uses .NET HttpClient
to read SSE progressively; credentials are absent from its command line/files.

### DeepSeek Bridge (tab 20)

The supplied `deepseek_ahk_bridge_agent_tools_v2` project lives in
`fan/DeepSeekBridge`. Its separate interface has a conversation, multiline
composer, provider thinking pane, tool call/result log, thinking selector,
Stop, New chat and saved request history. One agent can converse, inspect the
interface, compose native workflows and write/edit/run its own AHK v2 scripts.
Tools and script execution are available throughout the conversation.

The system prompt includes exact tool signatures and a searchable persistent
index of scripts, patterns, workflows and learned evidence. Source revisions,
descriptions, tags, usage examples and typed inputs survive restarts. **Saved
tools / API** opens the index and live Fan action catalog.

Native `fan_*` APIs reuse Fan's actual FindText, OCR, accessibility, GDI+,
Patterns database, manual workflow action schemas and execution engine. Frame
metadata and OCR/control bounds use absolute physical screen coordinates,
including negative monitor positions. Captures include numbered controls and a
grid burned into a saved image; they never draw tooltips or screen overlays.
Current image evidence automatically routes to `deepseek-flash`, while text
planning uses Pro. Model interpretations are stored separately from observed
geometry. Recapture after scrolling, navigation or layout changes.

Generated scripts can include `lib/FanBridgeClient.ahk` to call the running app:
`FanBridge.Inspect`, `OCR`, `FindPattern`, `LearnPattern`, `SaveWorkflow`,
`RunWorkflow`, or `Call` with an advertised API name. Read library signatures
using `fan_library_search/read` rather than copying the whole app entry point.
Parameterized scripts decode `FAN_TOOL_INPUT` with `FanBridgeJsonDecode`.
`ahk_script_run(wait=false)` keeps dialogs/persistent scripts running and returns
a process/run ID; `ahk_script_status/cancel` verifies or stops that exact run.

Gateway, API agent, AHK worker and observatory start automatically with Fan.
**Send message** also starts them when stopped. **Stop services** only stops the
processes owned by this tab. The existing Live Portal key is shared from Windows
Credential Manager through child-process environment variables; it is not saved
in bridge configuration or command lines. Service ports and connection state
are shown in the tab. On first setup, occupied ports are skipped so an existing
bridge can continue running. Dependencies are isolated in `.venv`; on a different
computer run `fan/DeepSeekBridge/install.bat` once.

**Observatory** opens the project's local activity viewer. **Local Harness**
opens `http://127.0.0.1:3080/`. **MCP setup file** generates a Harness registration
with the actual interpreter and project paths; it does not change the running
Harness profile automatically. Tasks, partial responses and tool outcomes are
retained in local SQLite history. Cancellation blocks queued desktop actions;
already executing input cannot be undone.

The supplied Pearson screenshots are modeled as assignment overview, question
player and feedback views. Recognition distinguishes sidebar question links,
navigation, Save, Help, Check answer, inline fields and the success modal. Mixed
radio/input answers use `A || 10`; selecting the radio precedes filling its
disabled inline field. The exact local solver verifies `100^(1/2) = 10` without
a provider call. A synthetic browser fixture exercises the same visible flow;
live Pearson accessibility/layout still needs capture on the actual page.

**Live Console** records every capture, identified control, name/function
association, local search, math-rule lookup, provider request/reply, compiler
rejection/repair, pointer waypoint, typo/correction, action, read-back and page
transition. Use its stage filter or disable **Follow live output** to inspect a
fixed view. **Open log folder** opens `fan/logs/study`. Each run has a timestamped
JSONL audit with monotonic sequence numbers. The UI retains the newest 1,500
events; the file retains all events. Math screenshots are retained in the run's
`-images` directory. Logs contain study content and should be treated accordingly;
credentials, Authorization headers and image base64 are excluded.

Each feature has an ephemeral command ID plus a stable `kind|name` identity,
role-derived function, supported commands, live value/state and physical bounds.
DeepSeek adds page-specific descriptions. Those descriptions are stored in the
study database under the exact page URL and identity, then supplied to future
planning requests. A stored description remains an inference: every action still
revalidates the live role, name, bounds and focus. The demo also saves its four
generated scripts and feature catalogs in study settings for inspection.

| Library / module | Coordinated example |
|---|---|
| GDI+ (`_Gdip`) | Capture the current rendered equation as pixels for the vision request |
| Windows OCR (`OCR.ahk`) | Gather text/instructions and independently observe correct feedback |
| Acc + SnapshotRecovery | Identify controls by name/role/state/bounds and verify the selected URL |
| WinHTTP + Crypt32 (`StudyLLM`) | Send UTF-8 prompts and base64 image input; expose attempts, cancellation, usage and estimated cost |
| DeepSeek Flash / Pro | Read visual algebra, describe captured features, compose tools and repair rejected proposals |
| SymPy + fixed AST parser | Solve exactly, preserve denominator/radical domains and substitute roots; model expressions never execute as code |
| TrackSQLite + TrackUtil | Persist descriptive memory and tool artifacts; encode/decode the structured audit and provider data |
| StudyComposer | Re-find each target, move/hover/overshoot, type with corrections, select options and read back outcomes |
| StudyDemo | Run the bounded capture → solve → tool → input → feedback → next-page sequence |

FindText/Vision Scout remain available elsewhere in MacroAutomator. This demo
uses accessible controls for input targets and stops if they cannot be identified.
It does not claim general autonomous navigation outside the local practice file.

Regression helpers: `StudyIntelligence_Test.ahk` validates descriptive memory,
credential redaction and exact-goal checks; `tests/test_algebra_solver.py` checks
algebra domains, all-root completeness and rejection of executable expressions.

## How the split was done (and why it is safe)

- Every function was moved **verbatim** to the file of the tab that uses it
  (see `SPLIT_MANIFEST.md` for the exact original line ranges).
- AHK v2 collects all function definitions before the auto-execute section
  runs, so moving definitions into `#Include`d files cannot change behavior.
- The order-sensitive parts — global setup, the main-window shell, global
  hotkeys and the startup sequence — stayed in `MacroAutomator.ahk` in their
  original order.
- Each tab's original GUI-construction lines were wrapped in a
  `Tab_xxx_Build()` function (called in the original tab order from the entry
  file). Every control variable is declared `global` inside its builder, so
  the event handlers work exactly as before.
- Verified during the split:
  - every one of the original 20,840 lines is accounted for exactly once,
  - an assembly of the split files matches the original line-for-line except
    the intentional changes listed below,
  - all top-level statements run in the same order as the original,
  - `/validate` passes (exit 0) with the same warning set as the original,
  - a live run shows the same main window and startup logs as the original.

## Intentional changes vs. the original

1. **`APP_ROOT` / working directory.** Because the entry script lives in
   `fan\`, it sets `APP_ROOT` to the original project root (one level up, when
   its `data\` folder exists) and points `SetWorkingDir`, `DATA_DIR` and
   `INSTRUCTIONS_FILE` there. The refactored build therefore uses the **same
   `data\` folder and database** as the single-file original — no data is
   copied or lost, and every existing workflow, setting, capture, and tracking
   row is immediately available to the `fan` build. This shared source of truth
   also avoids an 86+ GB duplicate tracking database drifting out of sync. If
   you move the `fan` folder somewhere standalone, it falls
   back to the folder itself and creates its own `data\` there.
2. **External `#Include` paths** are prefixed with `..\` (the libraries still
   live in the project root).
3. **Calendar tab loop variable** `time` was renamed to `slotTime` because the
   tab's GUI code now lives inside `Tab_Calendar_Build()` where the loop
   variable is function-local.
4. Dropped the old header banners and a duplicated
   `#Requires/#SingleInstance/SetWorkingDir/CoordMode` block.

The original DeepSeek split remains byte-identical apart from the intentional
path/layout changes above. The combined build then layers on the newer DeepSeek
tray icons and the ChatGPT Usage Predictor integration documented in this file
and `SPLIT_MANIFEST.md`.
