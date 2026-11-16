# Fan task workspace

Run `fan/MacroAutomator.ahk` using the normal launcher. The original tabbed
interface opens on Workflow by default. **Settings > Interface** switches between
**Original tabs** and **Clean task workspace**, immediately and without rebuilding
the tools. Your choice is remembered across launches. `/settings`, `/bridge` and
the workbench launch arguments still open their requested pages. Existing
hotkeys and native IPC page IDs remain compatible.

The tabbed interface retains all 23 original tools under 20 visible tabs. Only
closely related pages are combined: **App Learning** contains App Learner, Vision
Scout and Usage Predictor; **Study** contains Study Assistant and Live Portal.
Use the **View** selector in the top toolbar to choose the page within a combined
tab. Each combined tab remembers its last selected page during the session.
Other tabs retain their original names and contents. The tab strip scrolls at
narrow window widths and expands with the window.

While the main MacroAutomate window is active, **Tab** selects the next tab and
**Shift+Tab** selects the previous one, wrapping at either end. In the clean view,
they move through its tool pages. This takes precedence over moving between
fields in the main window; separate dialogs and other apps keep normal Tab use.

The Desktop **MacroAutomate** shortcut uses **Ctrl+Shift+G** to launch the app
when closed. The app's existing shortcut shows/hides the window while running.
`Build_Executable.ps1 -InstallShortcut` builds the executable beside the entry
script and assigns the Desktop shortcut. Keep the executable in `fan`; the
Python bridge, streaming helper and data remain external runtime dependencies.
On machines where Application Control blocks unsigned compiled applications,
use `-InstallShortcut -UseInterpreter` to target the installed AutoHotkey runtime
and the same source instead. No application-control settings are changed.

In Clean task workspace, the first selector chooses a task group; the second
chooses a tool. **How to use this** explains that tool's purpose and next action.
**Review evidence** always returns to the common review destination. Switching
interfaces preserves the current tool and unsaved control values; leaving the
clean Start page for Original tabs returns to Workflow.

| Group | Tools |
| --- | --- |
| Start | Guided routes and inventory overview |
| Automate | Workflow, Scribe, scheduled workflows, hotkeys, hotstrings, triggers, agent workbench |
| Capture & learn | Activity tracking, app interface learner, visual learner, usage predictions, OCR, media analysis, capture-source recovery |
| Review & apply | Evidence and knowledge, linked evidence ledger and saved rehearsals |
| Study | Study library and live study session |
| Organize | Clipboard, notes, calendar and workflow analytics |
| Settings | Settings and reusable visual patterns |

## A useful collection session

1. Choose a concrete outcome, such as exporting a report from one application.
2. Open the relevant collection tool. Enable the recorder or learner needed for
   that outcome. Each tool retains its existing individual switches.
3. Perform one representative task, then stop the recorder you enabled.
4. Open Review & apply. Choose a category and search its loaded recent records.
   Search matches item, detail, timestamp and complete retained content, within
   the latest 300 records in that category. It is not a whole-database search.
5. Select a record. Read its source, recorded time, content and recommended use.
   Missing timestamps are explicitly identified. Selection does not flash the
   desktop; **Show remembered bounds** is an explicit location preview.
6. For claims, evidence or rehearsals, use **Review claim** to open the exact
   claim's existing evidence ledger. Review negative checks, environment coverage
   and limitations before using it in a workflow or study answer.

**Claims with negative checks** is a review queue. A negative check can reflect
a changed application or environment; inspect the evidence rather than deleting
the claim. **Saved rehearsals** opens saved review material with a link back to
the claim that produced it.

## What the numbers mean

Inventory records overlap: one interaction may contribute a target, claim,
evidence record and rehearsal. Summing categories does not count unique skills.
The overview separately reports claims, evidence records, claims with eligible
negative checks and saved rehearsals. Negative checks remain visible even if a
claim also has positive checks.

Claim states use the existing evidence rules: observation only, tentative
verification, supported in observed contexts, or contradicted / review. Support
requires spaced checks across contexts and sessions; repeated scans and replay
do not establish independent verification. Rehearsal counts do not imply that
the original application was successfully automated.

**Check window / bounds** checks window availability and retained screen bounds.
It does not check control identity, meaning, visual match or action success.
**DeepSeek insights (API)** uses the existing provider and cost controls.
**Export inventory** exports category counts and their interpretation, not a
complete export of the underlying evidence. Automatic refresh updates counts
without replacing the record you are reading; Refresh reloads category records.

## Refactor boundaries

The entry point now lists seven lifecycle fragments in execution order:
`_Bootstrap`, `_Dependencies`, `_Runtime`, `_Modules`, `_Shell`, `_Hotkeys`, and
`_Startup` under `fan/Core`. `_Navigation` owns task routes and page guidance.
Extraction preserves the original initialization order and uses explicit include
paths. The existing tab modules still own the specialist controls and handlers.

The optional clean shell organizes all 23 existing tools under seven task groups
with a shared review workflow; Original tabs is the default interface. Engines,
individual collection switches and database
schemas remain in their existing modules. This is a navigation and evidence
review refactor, not a replacement of the learner algorithms or proof that
previously collected data is relevant to a particular task.

The natural next engine changes are to attach task/session identity to captures,
measure usefulness against explicit task outcomes, unify collector lifecycle
controls, and split perception, evidence assessment and execution services away
from tab builders. Those require migrations and outcome tests; they are not
silently approximated by category counts.

## Development checks

`FanWorkspace_Test.ahk` uses a temporary SQLite fixture to check every page route,
claim/evidence identity, negative evidence, content search, refresh behavior,
both interfaces, combined-tab navigation, persistence and preservation of review
state when switching interfaces. This test never shows its placeholder pages.
`FanGui_Test.ahk /background` separately constructs the real original tool GUIs
against a fresh temporary SQLite store, verifies each page's actual controls and
checks for caught construction errors. It does not start the app's collectors.
The Git checkout needs the native `sqlite3.dll` in `fan` for this check; the DLL
is a runtime dependency excluded from Git. The existing
`LearningWorkbench_Test.ahk` checks the evidence grading and rehearsal behavior.
Validate the complete entry point with AutoHotkey v2 `/validate`.

The shared Atlas workspace was consulted, but its CLI attempted to write its
read-only database and the advertised per-project index files were absent.
Changes were therefore based on scoped reads of the actual entry point,
navigation, evidence and dashboard code. The Atlas engine was not modified.
