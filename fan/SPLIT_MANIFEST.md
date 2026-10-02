# SPLIT MANIFEST

How `macroautomaterv9-deepseek.ahk` (20,840 lines) maps onto the multi-file project.
Line numbers refer to `_original_macroautomaterv9-deepseek.ahk`, the pristine copy kept in this folder.
Each listed range was copied verbatim into the target file (function code is byte-identical; only the GUI blocks were re-indented inside their builder functions).

## MacroAutomator.ahk (entry point) - kept in place

| Original lines | What they are |
|---|---|
| 34-36 | `#Requires` / `#SingleInstance` / `#Warn` |
| 39-42 | working dir + CoordMode (SetWorkingDir now uses `APP_ROOT`) |
| 44-114 | external `#Include`s (now prefixed `..\\`) |
| 149 | duplicate `#Include FindText.ahk` (kept) |
| 506-528 | data/log dir creation, `OnError`, GDI+ startup, `OnExit` hooks |
| 6263-6291 | `MainGui` creation, toolbar, `TabCtrl` (Tab3) |
| 7149-7157 | `TabCtrl.UseTab(0)`, StatusBar, Calendar comment |
| 7229 | final `TabCtrl.UseTab(0)` |
| 7231-7258 | initial `OnActionChange()` + AutoFlow capture |
| 7260-7268 | `MainGui.Show(...)` + AutoFlow first-pass timer |
| 17817-17880 | `SetTimer(UpdateDefinitionMode)` + `#HotIf` block + global hotkeys |
| 18065-18080 | clipboard revolver / tracking hotkeys |
| 18089-18091 | `try Snip_RestoreState()` |
| 18101-18143 | startup sequence (`InitDB`, `LoadAll`, refresh calls, auto-start) |
| 18159-18163 | `StatusBar.SetText(...)` |
| 18288-18292 | `InitializeInstructions()` call |

## Per-tab files

Each tab file contains its `Tab_xxx_Build()` function (the original GUI lines, with a `global` declaration for every control variable) plus the functions that tab uses.

### Actions\_Engine.ahk
2719-2866, 7405-7476, 16249-17326

### Core\_Db.ahk
3028-3414, 6190-6208, 6230-6254

### Core\_Gdip.ahk
20658-20840

### Core\_Globals.ahk
152-504

### Core\_Helpers.ahk
543-901, 922-1124, 2524-2703, 2876-3022, 8682-8721, 18166-18286, 19121-19130

### Core\_Notifications.ahk
7783-7957, 18295-18421, 18536-18747

### Tabs\Tab_01_Workflow.ahk
2315-2363, 8730-8806, 9000-9139, 9141-9144, 9146-9227, 9244-9461, 9470-9499, 10796-11436, 14590-15068, 15074-15707, 15709-16022, 16025-16091, 18145-18150, 19396-19562

### Tabs\Tab_01_Workflow_Forms.ahk
11438-11470, 11476-11591, 11601-13921, 14412-14585, 19135-19389

### Tabs\Tab_02_Patterns.ahk
1354-1670, 1680-2306, 8809-8830, 8833-8997, 9508-9565, 9704-10361, 10364-10392, 18503-18534

### Tabs\Tab_03_LiveOCR.ahk
1127-1353, 4174-5105, 5106-5127, 6094-6122, 6212-6228, 7480-7664, 17388-17750, 17881-18063, 18423-18499

### Tabs\Tab_04_Spools.ahk
3418-4165, 5131-5553, 5657-6090

### Tabs\Tab_05_Analytics.ahk
2372-2515, 10394-10447

### Tabs\Tab_06_Clipboard.ahk
6161-6188, 7958-8328, 10461-10787, 16100-16163, 17328-17378, 18152-18157

### Tabs\Tab_07_Hotkeys.ahk
6124-6145, 16172-16238

### Tabs\Tab_08_Hotstrings.ahk
18754-19114

### Tabs\Tab_09_Triggers.ahk
19569-20573

### Tabs\Tab_10_Settings.ahk
6147-6159, 17761-17808, 20576-20649

### Tabs\Tab_11_Notepad.ahk
8332-8675

### Tabs\Tab_12_Calendar.ahk
5554-5656, 7270-7391, 9566-9703, 13923-14408

### Tabs\Tab_13_Tracking.ahk
530-534, 7677-7780, 18082-18087, 18093-18099

### Tabs\Tab_14_AppLearner.ahk
GUI builder only.

### Tabs\Tab_15_SnapshotRecovery.ahk
GUI builder only.

### Tabs\Tab_16_VisionScout.ahk
GUI builder only.

### Tabs\Tab_17_UsagePredictor.ahk
Integration glue added from `macroautomaterv9-chatgpt.ahk`. The full subsystem
remains in the shared `lib\UsagePatternPredictor.ahk` module.

## Intentional changes (everything else is byte-identical)

- Dropped: old banner comments and the duplicate `#Requires/#SingleInstance/SetWorkingDir/CoordMode` block (lines 1-33, 115-148, 150-151).
- `DATA_DIR` / `INSTRUCTIONS_FILE` now build from `APP_ROOT` (the original project root) so the fan build keeps using the same `data\\` folder and database.
- `A_ScriptDir . "\\Data\\appointments.ini"` -> `DATA_DIR . "\\appointments.ini"` (Calendar file).
- `A_ScriptDir . "\\data\\trigger_log.txt"` -> `DATA_DIR . "\\trigger_log.txt"` (Triggers file).
- Calendar tab loop variable `time` renamed to `slotTime` (it becomes function-local inside `Tab_Calendar_Build()`).

## Combined-branch additions

The split originally targeted the DeepSeek file. The `/fan` entry point now
also carries every behavior unique to the ChatGPT v9 branch and the later
DeepSeek v9.1 delta:

- Includes `lib\UsagePatternPredictor.ahk`, builds it as tab 17, initializes it
  after tracking startup, stops it before the shared tracking DB closes, and
  installs its tray submenu.
- Keeps Vision Scout as tab 16 with its full review/certification workflow.
- Resolves the two learners' `Win+CapsLock` collision by assigning Usage
  Predictor `Win+Shift+CapsLock`; its button, tooltip, and tray label all show
  the revised shortcut.
- Adds native tray-menu icons from the newer DeepSeek file.
- Logs the AutoFlow capture report supplied by the ChatGPT file.

