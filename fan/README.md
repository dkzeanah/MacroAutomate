# fan — Combined Multi-File Build of Macro Automator v9

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
- Vision Scout accepts an armed offer with `Win+CapsLock`; Usage Predictor uses
  `Win+Shift+CapsLock` so both can run together without overwriting a hotkey.
- The current DeepSeek branch's native tray-menu icons are included, along with
  the Usage Predictor tray submenu and the AutoFlow capture diagnostic.

## Run it

```
fan\MacroAutomator.ahk
```

That file is the entry point — run it with AutoHotkey v2 (e.g. double-click it,
or: `AutoHotkey64.exe fan\MacroAutomator.ahk`). It `#Include`s everything else.

There is also `Run_MacroAutomator_Logged.cmd`, a launcher in the same style as
the project root's `Run_macroautomerv8_Logged.cmd`: it starts the entry file
with `/ErrorStdOut` and appends all startup output (warnings included) to
`data\logs\macroautomaterv9_fan_startup.log`.

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
   copied or lost. If you move the `fan` folder somewhere standalone, it falls
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
