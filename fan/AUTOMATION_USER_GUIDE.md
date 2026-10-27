# Macro Automator: comprehensive automation guide

Code audit: **6 October 2026**. Entry point: **`fan/MacroAutomator.ahk`**, AutoHotkey v2. This guide describes the combined `fan` build, including all 19 tabs and the study/DeepSeek extensions. Older single-file builds and older v7 guides have different capabilities.

For easy reading, open the [searchable browser edition](AUTOMATION_USER_GUIDE.html) or click **Workflow → Action Guide** after reloading the app. Search filters whole chapters; Clear restores them; Print / PDF includes the complete guide. This Markdown file is the authoritative editable source.

The main working surface is **Workflow (tab 1)** plus **Patterns (tab 2)**. A workflow says what to do; patterns identify what to act on. OCR supplies readable values; spools decide when to act; tracking and learners supply reusable context. The program can perform substantial automation today, but general desktop autonomy is still assembled from these separate engines.

## Contents

1. [Start here and run your first automation](#1-start-here-and-run-your-first-automation)
2. [Choose an automation approach](#2-choose-an-automation-approach)
3. [Workflow tab: building, checking, saving, and running](#3-workflow-tab-building-checking-saving-and-running)
4. [Patterns tab: visual identification with FindText](#4-patterns-tab-visual-identification-with-findtext)
5. [Every Workflow action: complete reference](#5-every-workflow-action-complete-reference)
6. [OCR, Watch Words, and variable memory](#6-ocr-watch-words-and-variable-memory)
7. [Spools: detect, respond, repeat, and stop](#7-spools-detect-respond-repeat-and-stop)
8. [Common sequences and practical recipes](#8-common-sequences-and-practical-recipes)
9. [Learning windows, features, menus, and key combinations](#9-learning-windows-features-menus-and-key-combinations)
10. [Learning repeated behavior and offering continuations](#10-learning-repeated-behavior-and-offering-continuations)
11. [DeepSeek, internal input simulation, and visual algebra](#11-deepseek-internal-input-simulation-and-visual-algebra)
12. [All tabs and supporting panels](#12-all-tabs-and-supporting-panels)
13. [Logs, evidence, storage, and recovery](#13-logs-evidence-storage-and-recovery)
14. [Keyboard shortcuts](#14-keyboard-shortcuts)
15. [Libraries and code integration examples](#15-libraries-and-code-integration-examples)
16. [Troubleshooting and current boundaries](#16-troubleshooting-and-current-boundaries)
17. [Demonstrations and validation evidence](#17-demonstrations-and-validation-evidence)

## 1. Start here and run your first automation

### Launch the right build

Run `fan/MacroAutomator.ahk` using AutoHotkey **v2**. The Windows launcher [Run_MacroAutomator_Logged.cmd](Run_MacroAutomator_Logged.cmd) records startup diagnostics. Git Bash users can use [run_fan.sh](run_fan.sh). The application needs its included libraries and the SQLite DLL; keep the project folder together.

The main application stores its settings and workflows under the project's `data` directory. A running AHK process holds the code it loaded at startup: **reload/relaunch after a code update** to get new controls. Reloading interrupts an active automation, so finish or stop the current run first.

### First demonstration: visible typing inside the built-in lab

1. Open **Workflow**. Name the workflow `My First Lab Automation` before adding steps; named workflows autosave after edits.
2. Click **Demo Lab**. It contains a text area, click targets, a menu, drag targets, destination fields, and a visible event log.
3. Return to Workflow and add these steps using the action dropdown and **Add Step**. The guided form opens for each action; the table below shows the resulting Target and Parameter values.

| Step | Action | Target | Parameter |
|---|---|---|---|
| 1 | Run Program | blank | `demo:lab` |
| 2 | Click | `demo:notepadedit` | `1` |
| 3 | Type Text | blank | `Hello from my automation.` |
| 4 | Show Notification | blank | `Demo complete,Check the lab text area,3` |

4. Click **Simulate** to see the intended order and target locations without executing the steps.
5. Click **Run Workflow**. Watch the lab text area receive the text. The final notification reports completion; the text area is the actual evidence that entry happened.
6. Click **Save Now**. Find the workflow in the saved library. Load, run, export, or duplicate it from there.

For the next lesson, replace the Click step with **OCR Click**, Target `window:MacroAutomator Demo Lab`, Parameter `Notepad`. The lab's Notepad button focuses its text area when clicked. This demonstrates **read visible text → identify the button → click → type**.

**Stopping:** Escape aborts a running standard workflow; Ctrl+Shift+X sets its abort flag; Ctrl+Shift+P pauses/resumes it. The Live Portal controller has a separate emergency stop, Ctrl+Shift+Escape. Spools and learners have their own Stop controls; stopping a workflow does not disable their timers.

## 2. Choose an automation approach

### The reusable cycle

```text
Observe the current window/page
  → identify a target or read a value
  → choose/build a small action sequence
  → execute native input or a direct control operation
  → check the resulting state
  → save useful targets, evidence, and sequences
  → repeat only while the expected context still holds
```

| Need | Start with | Why / boundary |
|---|---|---|
| Repeat known steps | Workflow | Broadest manual action palette: 66 action names, ordering, waits, variables, loops, saved sequences. |
| Find an icon/button despite its position moving | Patterns + FindText actions | Match distinctive pixels instead of a fixed coordinate. Appearance changes still require recapture or tolerance tuning. |
| Read a name, status, number, or label | Live OCR / workflow OCR | Windows OCR returns text and word boxes; recognition must be checked. |
| React automatically to a screen/window condition | Spools | Polls conditions and runs a saved workflow or other response. |
| Discover a program's menus, controls, and shortcuts | App Learner | Builds a persistent app catalog and runs AppDSL; optional Ollama generation. |
| Learn likely next actions from repeated use | Vision Scout / Usage Predictor | Offers learned continuations for explicit acceptance; statistical repetition is not task reasoning. |
| Track activity and turn observed regions into targets | Tracking + Snapshot Viewer | Named element registry, heatmaps, traces, keystroke history, and data exports. |
| Generate a guarded page-entry tool from a goal | Live Portal → Workflow Lab | DeepSeek generates a bounded script against a fresh accessibility/OCR catalog. |
| Solve equations displayed as an image | Workflow Lab → Solve Visual Algebra | Vision transcription followed by fixed SymPy verification and visible results. |
| Recover something previously seen | Snapshot Recovery | Search captures/phrases and recover recorded URLs, files, or history clues. |

### Pick targets deliberately

Use a fresh accessible control when the page provides a reliable name, role, and bounds. Use a learned menu/shortcut when the application exposes one. Use a distinctive FindText pattern for icons or stable visual shapes. Use OCR for readable text whose appearance varies. Use named coordinates for a stable layout, and relative offsets when the prior click is a trustworthy anchor.

These options are available across the project, but **one universal fallback engine does not connect every option automatically**. App Learner has its own resolver; tracked elements use another; the Study controller has stricter control validation. Choose the runner that matches the task.

## 3. Workflow tab: building, checking, saving, and running

### The five areas

1. **Define Workflow:** name, playback speed, optional hotkey and hotstring, Action Guide, Error Log. Speed choices are 0.25x, 0.5x, 0.75x, 1x, 1.5x, 2x, and 3x.
2. **Pick an Action:** category filter, action list, contextual Target/Parameter fields, guided Add Step form, suggestions, Templates, Pos. Tools, and Advanced fields. OCR Area and Pick Window appear where relevant. Quick Add uses the raw fields directly.
3. **Review and Arrange:** checked rows are enabled; Up/Down reorder; Edit/Delete/Enable/Clear manage rows. Test Selected executes the step; Sim Selected and Simulate All only preview it. Right-click opens additional step options, including failsafe settings and notification controls.
4. **Save and Run:** Save Now, Run Workflow, Simulate, Step-through, and Manage Library.
5. **Saved Workflow Library:** Load/Edit, Delete, Run, Simulate, Import `.maw`, Export `.maw`, Write `.maw`, and Demo Lab. Double-click loads a workflow into the editor.

### A good workflow is a sequence of state changes

Prefer `Activate Window → wait for recognizable content → act → verify recognizable content` at each handoff. A fixed delay can let a dialog render, but a pattern/OCR/window wait gives better evidence that the program is ready. A wait for window **existence** does not prove that it has keyboard focus: activate it before sending keys.

The editor's **Advanced** fields expose a pattern qualifier, a window qualifier, and close-button blocking. Per-step failsafe settings can require an active-window title fragment, a required pattern, additional delay, and abort-on-failure. Legacy window qualifiers check the window under the pointer; they are not the same as a foreground-window guard. Review the saved step's failsafe configuration for the protection you intend.

`ClickVerified` confirms pointer arrival and checks the close-button restriction; `TypeTextVerified` sends text with delays. Their names do **not** mean the destination application accepted the action. Add a result check after input.

### Playback, simulation, and failures

- Playback speed scales the engine's general action/pre/post delays. Explicit Wait values and many helper-internal waits retain their own timing. It does not set a typing WPM profile for tab 1.
- Simulation displays locations and step descriptions. It does not execute branches, repeated loop bodies, text entry, or result verification. A completed simulation is a preview, not a successful live test.
- Step-through pauses between steps until Tab. Use it to inspect each result; while active, Tab is the workflow's advance key.
- A failed standard step can prompt **Continue?**. A run that continues past failures can still show a sequence-complete message. Verify the required output rather than relying on that message alone.
- Loops belong to the top-level sequence runner. **Run Sequence** shares variable memory and blocks recursive calls, but its current sub-sequence executor does not run a nested sequence's Loop Start/Loop End jump logic. Put repeated control flow in the top-level workflow.

### Portable tools

`.maw` is the portable workflow format. Export from the library, or use **Write .maw** to build a separate file before importing it. Inspect its actions and targets on import. Window names, external programs, screen coordinates, tracking-registry entries, and other machine-specific resources may still need adjustment.

`.mas` is the portable spool format. A spool with **Run Workflow** can embed its linked workflow so both arrive together. It is a different format from AppDSL scripts and the Live Portal tool language.

Templates append predefined steps to the current editor. Available template descriptions include OCR → Variable → Clipboard, full-screen OCR with yellow boxes and notification, pattern wait/click, OCR data entry, and debug sequences. **Replace example regions and targets before using them in another application.**

## 4. Patterns tab: visual identification with FindText

### What a pattern means

A FindText pattern is an encoded image of pixels, such as a button label or icon. Its stored text is an image-search representation, not an OCR reading or an intelligent description of function.

Patterns have a **name**, **description**, pattern **code**, optional **qualifier**, and captured-location/window/preview information. Name targets for their purpose and context, for example `Inventory_RefreshButton` or `Invoice_SavedBanner`. Write descriptions such as “refreshes the inventory list; use only on the inventory page.” This makes a visual target understandable to a person or planner.

### Capture and certify a visual target

1. Put the target in the visible state you want to recognize.
2. In Patterns, click **Quick Capture**, drag a small distinctive region, and review the generated code and preview.
3. Name it, add a description, and save. For advanced capture/threshold choices, use **FindText GUI** or Ctrl+Shift+F, then paste the resulting pattern code.
4. Click **Test Pattern** or select it and click **Test**. Check the located target; full view shows ASCII pixels, screenshot, coordinates, window, qualifier, and code.
5. Move the target window and test again. If recognition fails, recapture at the intended scale/theme or carefully adjust FindText tolerance in Settings.
6. Add **Wait for Pattern → Find & Click → verify the expected result** in Workflow.

Capture a stable interior shape; avoid changing counts, clocks, blinking carets, or oversized background areas. Gray2Two can suit text; Color2Two can suit colored buttons. The advanced FindText GUI exposes further modes; match quality depends on what was captured.

### Qualifiers and search scope

A pattern qualifier requires another saved pattern to be visible before the click/drag helper acts. For example, a generic Submit pattern can require a page-heading pattern. This reduces ambiguity, but it does not tie two matches to the same pane or browser tab. Pattern testing/highlighting and basic wait helpers do not provide all click-helper qualifier checks. Spool pattern detection also searches its own region independently.

Many basic pattern actions search broadly. Spools provide an explicit region; **Find & Click Loop** can search a chosen window. Use a distinctive target and restrict scope where possible. A successful visual match does not establish that a button is enabled or that clicking it is the right next action.

### Definition Mode: quickly sketch a workflow

CapsLock ON enables global definition keys. Point at a target, then:

| Key | Captured step |
|---|---|
| C | Click at the pointer; optional automatic pattern capture |
| D, then D | Drag start and end |
| R | Right Click |
| T | Triple Click |
| P | Pattern capture |
| W | Wait, initially 200 ms |
| K | Send Keys input |
| M | Menu Select input |
| Escape | Cancel definition activity / dismiss its help |

These keys add steps to the current workflow. **Turn CapsLock OFF before ordinary typing**, since these letter keys are intercepted globally while Definition Mode is active. Captured coordinates/window titles and auto-pattern metadata do not automatically turn every recorded click into a Find & Click action; review the resulting rows and guards.

## 5. Every Workflow action: complete reference

There are **66 selectable action names** in `GetWorkflowActionNames()`. The following tables cover all of them. “Blank” means no value is needed in that field. Prefer the guided forms over typing raw syntax.

### Mouse actions

| Action | Target | Parameter | Behavior / common use |
|---|---|---|---|
| Click | coordinate name, `x,y`, or `demo:key` | click count, e.g. `1` | Focus a field or press a known target. An unresolved/empty target can fall back to the current pointer: supply a valid target. |
| Double Click | same | blank | Open/select a target using two clicks. |
| Triple Click | same | blank | Three clicks, often for text selection. |
| Right Click | same | blank | Open a context menu. |
| Drag | saved drag name, or blank | raw `x1,y1->x2,y2` | Move a selection/handle to a destination. |
| Relative Click | saved relative offset | blank; legacy raw `dx,dy` supported | Offset from the **last click**, not the window origin. |
| Menu Select | blank | number of Down presses | Down repeated, then Enter; assumes the intended menu is already open. |
| Scroll | blank | positive up / negative down, e.g. `-3` | Wheel notches sent at the current pointer location. |
| Idle Mouse | blank | seconds; `0` indefinite | Actually **waits while monitoring pointer movement**; exits on sufficient manual movement or duration. It does not generate idle motion. |
| Hover Mouse | coordinate name or `x,y` | blank | Move onto a target without clicking; use Wait afterward to reveal a tooltip. |

**Pos. Tools** opens the coordinate manager for click points, drags, arrow-key positioning, relative offsets, tests, and deletion. Absolute coordinates depend on monitor layout, DPI, window position, and scroll state.

### Keyboard and windows

| Action | Target | Parameter | Behavior / common use |
|---|---|---|---|
| Send Keys | blank | `^c`, `^v`, `{Enter}`, `^+s`, etc. | AHK key syntax, interpreted as keys. |
| Type Text | blank | literal text, optionally `$var.name` | Literal entry via SendText; standard runner has no per-character typo/WPM model. |
| Key Chord | blank | `modifier,key,count`, e.g. `^,{Tab},2` | Hold modifier while repeatedly sending the key. |
| Paste | blank | blank | Ctrl+V using the current clipboard. |
| Activate Window | blank | window title/identifier | Activate an existing window and check foreground state; helper also handles executable identifiers. |
| Taskbar Activate | blank | `position,count`, e.g. `5,2` | Win+number, repeated while Win is held; 0/10 represent the tenth item. Taskbar order must match. |
| Run Program | blank | executable, file, URL, command line, or `demo:lab` | Launch the specified resource; wait/activate separately when needed. |
| Wait for Window | blank | `title=Save As; timeout=5000` | Wait for existence; does not activate it. |
| Wait Window Closed | blank | same option syntax | Wait until that window disappears. |

AHK modifiers: `^` Ctrl, `+` Shift, `!` Alt, `#` Win. Use **Type Text** for literal braces/symbols; use **Send Keys** for functional keys and chords. For browser tabs, a deliberate `^{Tab}` or `^l` can be part of a workflow, followed by a page-specific pattern/OCR check. There is no universal browser-tab identity guard in tab 1.

### FindText and loop actions

| Action | Target | Parameter | Behavior |
|---|---|---|---|
| Find & Click | pattern name | blank | Find and left-click the saved pattern. |
| Find & DblClick | pattern name | blank | Find and double-click. |
| Find & TplClick | pattern name | blank | Find and triple-click. |
| Find & RClick | pattern name | blank | Find and right-click. |
| Find & Drag | pattern name | destination `x,y` | Find the start visually and drag to the destination. |
| Wait for Pattern | pattern name | timeout ms | Wait for visibility. |
| Wait Until Gone | pattern name | timeout ms | Wait for disappearance. |
| Loop Start | blank | `count=3; var=i` or `count=forever; var=i` | Open a loop, initialize `$var.i=1`; variables survive between passes. |
| Loop End | blank | blank | End the body and repeat until count is reached. |
| Loop Break | blank | blank | Exit the current loop and continue afterward. |
| Find & Click Loop | pattern name | options below | Re-find, click, settle, scroll when absent, repeat with limits. |
| Popup Detect | region or blank | options below | Compare sampled pixels with a remembered baseline; report a change and optionally skip/break/stop. |

Use simple paired loops. Nested starts are stacked, but early break searches for the next Loop End rather than fully matching nested blocks; avoid complex nested break flows.

**Find & Click Loop** example:

```text
win=Inventory; scroll=-3; settle=800; scrollSettle=1000; maxClicks=10; maxScrolls=4; button=Left; clicks=1; top=home; focus=center
```

`win` activates/restricts search to a window; `scroll` is signed notches; `settle` follows clicks; `scrollSettle` follows scrolling; `maxScrolls` counts **consecutive empty scrolls** and resets after a successful click. `top=home` sends Ctrl+Home; a numeric top value scrolls upward that many notches. Optional `popup=Save` and `popupDo=enter`, `send:!s`, or `pattern:SaveBtn` handle an expected popup. Use explicit limits. A target that stays visible can be clicked repeatedly. This helper has its own timing and does not perform full Live Portal-style context checks. Its `tol` override currently passes through an integer option helper; tune the global decimal tolerance rather than relying on a fractional override here.

**Popup Detect** example:

```text
win=Inventory; sensitivity=medium; on=var; mode=now; timeout=5000; var=popupChanged
```

Choose `win=Title` or a raw `region=x1,y1,x2,y2`. Sensitivity accepts high/medium/low/strict. `on=var` sets 1/0; `skip` skips the next step; `break` requests loop exit; `stop` aborts. `mode=now` checks once; `mode=wait` polls for a change until timeout. The first use stores the baseline; repeated uses of that step compare it. **A change is not proof of a popup**: scrolling, animation, or moved content can also trigger it.

### OCR actions

| Action | Target | Parameter | Behavior |
|---|---|---|---|
| OCR Region | region / `window:Title` / `demo:lab` | `copy`, `var:name`, `split:line`, or `regex:...` | Read text and route its output. |
| OCR Click | region or dynamic window | text to find | Fresh OCR; click the first matching word/line. |
| OCR Wait | region or dynamic window | `text:READY,5000` or timeout ms | Wait for specified text, or any readable text. |
| Grab OCR to Var | region or dynamic window | plain variable name | Read a named value and store several compatible key forms. |
| OCR Full Screen to Var | blank | plain variable name | Read the **primary screen**, store text, and draw word boxes for 10 seconds. |
| Load OCR Revolver | blank | `tab`, `line`, count, or one-character separator | Split the most recent OCR text into sequential values. |
| Fire OCR Revolver | blank | blank | Paste the next split value; wraps to the beginning after the last. |

**Raw rectangle formats differ:** OCR Region, OCR Click, OCR Wait, Popup Detect, and spool Custom Region ultimately use **`x1,y1,x2,y2`** corners. Grab OCR to Var uses **`x,y,width,height`** when given a raw rectangle. Some UI help calls all rectangles “width/height”; that is inaccurate for the corner-based parser. Use the region picker or `window:Title` to avoid mistakes. Full-screen fallbacks in these older workflow paths usually mean the primary monitor, not the entire virtual desktop.

### Clipboard and text actions

| Action | Target | Parameter | Behavior |
|---|---|---|---|
| Set Clipboard | blank | text with optional variables | Replace clipboard text. |
| Insert Field | blank | extracted field name, e.g. `LastName` | Type that field from the Clipboard parser's extracted data. |
| Insert Date | blank | blank | Type current date using Settings → Date Format. |
| Parse Clipboard | blank | blank | Apply extraction rules to the current clipboard. |
| Load Revolver | blank | blank | Load available parsed fields in configured field order. |
| Fire Revolver | blank | blank | Fire the loaded standard revolver sequence with field navigation. |
| Fire Revolver+Enter | blank | blank | Fire the sequence with its Enter option. |
| Format Clipboard | blank | format name or template | `invoice`, `receipt`, `uppercase`, `lowercase`, `titlecase`, `trim`, `date_iso`, or `Record: {clip}`. |
| Append to Clipboard | blank | suffix text | Append after variable substitution. |
| Prepend to Clipboard | blank | prefix text | Prepend after variable substitution. |
| Extract from Clipboard | blank | saved rule name | Apply one extraction rule. |

The standard Clipboard Revolver is a **field-order batch**. The OCR Revolver is a **next-item carousel**. Smart bins hold separately selected clipboard items. Do not treat all three as the same queue.

### Variables, logic, tracking, and notices

| Action | Target | Parameter | Behavior |
|---|---|---|---|
| Set Variable | plain variable name | value | Set workflow and spool variable memory. |
| Grab Clipboard | plain variable name | blank | Save the current clipboard into variable memory. |
| If Contains | variable name | substring | If false/missing, skip **exactly the next enabled step**. |
| If Variable | variable name | `=,READY`, `>=,3`, etc. | Compare; false/missing skips the next enabled step. Numeric ordering requires numbers. |
| Use Var Paste | blank | text containing variables | Substitute then SendText. Despite its name, this is not a clipboard Ctrl+V action. |
| Stop Execution | blank | blank | Set the standard workflow abort flag. |
| Run Sequence | blank | saved workflow name | Execute a sub-sequence with shared memory; see loop limitation above. |
| Click Element | registry element name | `Left`, `Right`, `Middle`, optionally `,count` | Resolve a Tracking/Snapshot Viewer element and click. |
| Hover Element | registry element name | blank | Resolve and hover. |
| Wait Element | registry element name | timeout ms | Wait for a registered element to locate. Relative fallback can report a location even if its content is absent. |
| Replay Window Mouse | normalized tracked window name | speed, optionally `,clicks` | Replay that window's latest mouse snapshot; clicks are off unless requested. |
| Research Search | blank | query | Store a research query and open browser search. |
| Research Capture Links | blank | `screen` or `clip` | Harvest visible/clipboard URL text into that query. |
| Research Launch Next | blank | blank | Open the next pending stored link. |
| Research Add Insight | blank | note / variable text | Store an insight associated with the current query. |
| Wait | blank | milliseconds | Fixed pause. |
| Show Notification | blank | `Title,Message,timeoutSeconds` | Show a notification; `3` means three seconds, while `0` uses the app's default dismissal/timeout behavior. Guided form handles its fields. |

Conditions are **one-step gates**, not If/Else blocks. To gate an entire action group, place it in a saved sub-sequence and gate the Run Sequence step. To stop on a detected problem, gate a Stop Execution step.

## 6. OCR, Watch Words, and variable memory

### Live OCR workflow

In **Live OCR (tab 3)**, select the capture region, choose language/scale options, and click **Capture Once**. Examine both the text and Word list. Highlight a selected word to verify its box before clicking it or making a Watch Word. Recording captures repeatedly; View/Clear/Export manage OCR history.

Useful outputs are Copy, Load Rev, → Var, Click Text, Regex, and Split. The tab also provides text search/highlights, Watch Word definition and management, and OCR Revolver controls. Ctrl+Shift+Q opens an independent quick drag-box OCR capture spanning the virtual desktop, copies its result, and displays it; it can work while the main window is hidden.

**OCR Click uses permissive substring matching in both directions and returns the first matching word before trying lines.** A search like “Submit invoice” may match just “Submit.” Crop tightly, test the highlighted text, and prefer a distinctive pattern or accessible named control when multiple matches are possible.

### Variable namespaces and lifetime

| Form | Source | Example |
|---|---|---|
| `$var.name` | Set Variable, clipboard/OCR capture, or spool memory | `Order: $var.orderID` |
| `$word.name` | Saved Watch Word definition | `$word.CustomerName` |
| bare `$name` | Older spool/extracted-data compatibility | Prefer `$var.name` in new workflows. |
| `$ocr` | AppDSL's own OCR variable | Separate from tab 1 variable memory. |

Variable substitution occurs in the standard workflow **Parameter**, not every Target field. Use plain names such as `orderID`; letters, digits, and underscores are appropriate. Missing `$var.name`/`$word.name` substitutions can become empty strings. Inspect captured values before using them.

Top-level workflow execution resets its workflow-variable map. Shared spool/extracted-data maps may retain values from previous work, so initialize values that must be fresh. Loop passes and sub-sequences share the current memory. This is runtime value memory, distinct from saved workflows or the persistent study answer bank.

### Watch Words

A Watch Word stores a screen region, optional word index, optional regex, latest value, coordinates, and update time. When a parameter contains `$word.name`, substitution refreshes the Watch Word readings. A whole-region watch is often more stable than a word index when the line length changes.

Use **Define from OCR** or the word-list **Watch** control, give it a descriptive name, update it, show its value, and highlight it. Then type or set clipboard text containing `$word.name` in Workflow. Watch definitions persist through the app's saved OCR-word data. The definition uses screen rectangles, so moving its source can make it stale. A failed refresh can leave an old value; inspect it and reselect the region when context changes.

### Clipboard extraction and form filling

In **Clipboard (tab 6)**, grab sample text, define named regex extraction rules, and Parse. Verify the extracted fields, arrange their field order, then Load Revolver. Focus the first destination field before Fire All. Tab order and any empty/missing fields must match the target form.

For a value that has a clear prefix, a rule can use a capture group, for example `Order ID:\s*(\d+)`. Test the rule against representative clipboard samples, including a missing value. The guided rule UI and parsed results are the evidence; a regex that matches one sample is not a semantic parser for every document.

## 7. Spools: detect, respond, repeat, and stop

A spool is a **timer-driven condition monitor**. It can operate while the main GUI is hidden. It connects observation to a response; the response can be a complete workflow from tab 1.

### Detection choices

| Detect | Target / condition | Actual meaning |
|---|---|---|
| Pattern Match | saved pattern, Found/Not Found | FindText presence in the spool region. |
| Pattern Sequence | comma-separated saved patterns | **All patterns present in the same check**; not an ordered history of screens. |
| OCR Contains | text, Found/Not Found | Windows OCR text includes the requested substring. |
| OCR Regex | expression, Found/Not Found | Windows OCR text matches the expression. Extracted value is the recognized region text, not necessarily one regex group. |
| Pixel Change | region | Compare 16 sampled pixels with the previous check; first check seeds memory. Not every changed pixel is observed. |
| Window Title | title fragment, Found/Not Found | Match the **active** window's title. It does not wait for an inactive window. |

Region choices: Full Screen (primary screen in this engine), Custom Region (corner coordinates), and Active Window. Active Window follows whichever window currently has focus. The “Changed” condition label does not make pattern/OCR detection an edge-trigger: Found/Not Found are the meaningful presence conditions for those detectors.

### Responses

Run Workflow, Click Detected Pattern, Show Notification, Start Spool, Stop Spool, Extract OCR, Set Variable (`name=value`), Key Chord, and Run Program are wired responses. **Click Detected Pattern requires Pattern Match + Found** and re-finds the target in the spool region before clicking.

The **Also extract OCR to** option stores detected OCR text under the supplied variable name before the response. Extract OCR alone relies on that extraction option; it does not independently perform a second capture for every detection type. A Pixel Change or Window Title detection does not supply readable OCR text automatically.

### Build a spool that runs a workflow

1. Finish, test, and save a named workflow in tab 1.
2. In Spools, name the monitor; choose its region, detector, target, condition, and interval (default form value 500 ms).
3. Set **Do = Run Workflow** and select the saved workflow. Refresh the response choices if it is missing.
4. Start with **One-Shot** for a single attempt, or **Cooldown** with a few seconds between repeat attempts.
5. Save it. **Test Trigger performs detection and the actual response** when detected; it is not a dry run. It does not change that spool's saved running/cooldown state.
6. Check Activity Log and the destination output. Click Start when the definition works.
7. Stop it afterward, or set an Auto-stop completion condition.

### Repeat and completion semantics

- **One-Shot:** after a detected trigger attempt, stop the spool. This happens even if its response failed; it is not “retry until success.”
- **Cooldown:** after a trigger attempt, suppress checks for the chosen delay, then recheck. A condition that stays present can fire again. It is not a rising-edge detector.
- **Continuous:** check/respond every interval; a stable Found condition can repeatedly click or launch work.
- **Auto-stop:** Timeout (seconds since start), Pattern Found, Pattern Gone, OCR Contains, or Variable Set. Variable Set checks key existence, not its truthiness; a stale key can stop the spool immediately.
- **Master Enable:** saved across launches. Enabled spools can restart when it was left on. Start on an individual spool also enables the master.
- **Concurrency:** a shared flag prevents two **spool-launched workflows** from running together. It is not a universal input lock across manual workflows, AppDSL, learners, and Live Portal.

Use **Stop All / Master Enable off** when changing destinations or debugging. A standard workflow abort does not stop a continuing spool from launching another run.

Activity Log records starts, triggers, clicks, workflow starts/done, cooldowns, and failures. Its workflow DONE event means the sequence runner returned, not that every required application result passed verification. Pair it with your output check.

## 8. Common sequences and practical recipes

The following tables are actual tab-1 Action/Target/Parameter examples. Replace example window titles, pattern names, and registry names with items you have captured. Use guided forms to build them.

### A. Copy visible text into a note

Use case: move a visible order summary from a browser/PDF to a text editor.

| Action | Target | Parameter |
|---|---|---|
| Activate Window | blank | `Order Summary` |
| OCR Region | `window:Order Summary` | `var:summary` |
| Activate Window | blank | `Notepad` |
| Send Keys | blank | `^{End}` |
| Type Text | blank | `Captured summary: $var.summary` |
| Show Notification | blank | `Capture complete,Review the pasted summary,3` |

Verify the captured OCR text and destination content. Narrow the source area when the whole window contains unrelated text.

### B. Wait for a page, click a visual target, verify success

| Action | Target | Parameter |
|---|---|---|
| Activate Window | blank | `Inventory` |
| Wait for Pattern | `Inventory_PageHeading` | `8000` |
| Find & Click | `Inventory_RefreshButton` | blank |
| OCR Wait | `window:Inventory` | `text:Updated,8000` |

Make the refresh pattern's qualifier the page heading. If “Updated” is already visible before the click, this check does not prove a new update; choose feedback that changes, clear the old state, or inspect a freshly captured value.

### C. React to a ready banner with a spool

Capture `Export_ReadyBanner` in tab 2. Save and test a workflow that activates the export window, clicks the download target, waits for the expected dialog/result, and reports it. Configure a spool:

```text
Detect: Pattern Match
Target: Export_ReadyBanner
When: Found
Region: tight Custom Region
Do: Run Workflow
Response target: your saved export workflow
Repeat: One-Shot
```

For repeated work, use Cooldown plus an explicit completed-state check. A persistent ready banner by itself does not distinguish new items from the previous one.

### D. OCR a status, then gate a group of actions

Create a saved sequence named `Handle Ready Record`, containing the actions for one record.

| Action | Target | Parameter |
|---|---|---|
| OCR Region | `window:Record Queue` | `var:status` |
| If Contains | `status` | `READY` |
| Run Sequence | blank | `Handle Ready Record` |

Only the Run Sequence row is gated. Put a separate verification inside the sub-sequence. The substring `NOT READY` also contains `READY`: use a more precise extraction/comparison if both states exist.

### E. Repeat numbered data entry three times

| Action | Target | Parameter |
|---|---|---|
| Activate Window | blank | `MacroAutomator Demo Lab` |
| Click | `demo:notepadedit` | `1` |
| Loop Start | blank | `count=3; var=i` |
| Type Text | blank | `Record $var.i of $var.loopCount` |
| Send Keys | blank | `{Enter}` |
| Loop End | blank | blank |

The loop counter becomes 1, 2, 3. A real form workflow should locate the next record and verify each entry rather than assuming Tab or screen position still matches.

### F. Extract several fields and fill a form

1. Copy a representative record. In Clipboard, define/test fields such as LastName, FirstName, and OrderID.
2. Arrange the field order to match the destination's Tab order.
3. Build `Parse Clipboard → Load Revolver → Activate Window → Click first field → Fire Revolver`.
4. Inspect every destination field after firing. Missing fields, disabled controls, extra Tab stops, or modal dialogs can shift the rest of the entry.

For a fixed three-value OCR sample, use `OCR Region → Load OCR Revolver (line) → Click first field → Fire OCR Revolver → Send Keys {Tab} → Fire OCR Revolver → ...`. Numeric split rules divide **characters into equal-length pieces**; they do not identify semantic fields.

### G. Hover to reveal information, then capture it

`Activate Window → Hover Mouse (HelpIcon) → Wait (800) → OCR Region (tooltip area, var:helpText) → Show Notification`.

Use this for tooltips or transient descriptions. Hover Mouse itself does not vary dwell time; add Wait in tab 1. The Live Portal input profile provides randomized hover behavior separately.

### H. Operate repeated visual rows while scrolling

Use **Find & Click Loop** with a distinctive per-row pattern, `win=Queue`, explicit maxClicks/maxScrolls, and sufficient settle time. Verify that the clicked row disappears/changes or advances. If the same pattern remains at the same location, the helper can keep clicking it. For rows requiring different typed values, prefer a counted top-level loop with capture, condition, entry, and verification steps.

### I. Stop a loop when the expected view changes

Put Popup Detect at the loop top, with `win=Queue; mode=now; on=break; var=queueChanged`, then the loop's actions. The first pass seeds its visual baseline; later checks can break on substantial change. Test a known change and a harmless animation. For a specific named dialog, Wait for Window/Wait Window Closed gives clearer meaning than pixel change alone.

### J. Work across browser tabs or applications

Use `Activate Window → page-heading check → capture value → Activate destination → destination check → type/paste → result check`. Within a browser, Send Keys `^{Tab}` changes tabs; follow it with a distinctive page check before continuing. Repeatedly pressing Ctrl+Tab assumes tab order, so it is less stable than separate windows or an explicitly identified destination.

AppDSL can switch learned applications with `use`, or learn a newly activated window with `learn`. Its `focuswin` handoff both waits and activates. DeepSeek's standard Study tool language intentionally has no general tab-switching/navigation command; its four-page demo has dedicated, scoped navigation.

### K. Turn observed usage into a named target

Start Tracking for a sample task → open Mouse Heat / Trace → Extract Features → review the candidate hotspots → open Snapshot Viewer → define/name a target → test its live location → use Wait Element / Click Element in Workflow. Mouse hotspots show frequent interaction, not automatically the correct business function. Add a meaningful description and validate the target.

### L. Keep a research trail

`Research Search → wait for visible results → Research Capture Links (screen or clip) → Research Launch Next → OCR Region (var:researchText) → Research Add Insight ($var.researchText)`.

Research Pipeline stores queries, URLs, and insights and produces reports. Screen harvesting recognizes URL text; many search pages display shortened URLs or link labels, so it cannot recover every hidden hyperlink. The pipeline does not automatically read, fact-check, or summarize every launched page.

### M. Learn an unfamiliar application and generate a script

App Learner → Refresh List → select its visible window → Learn Selected → review catalog/shortcuts → Highlight/Test Click → enter a clear goal → Generate Script with Ollama → review the AppDSL → Run Script. Use Generate Script first while discovering the application; Generate + Run executes the generated script immediately.

### N. Let DeepSeek build a page-entry tool

Live Portal → pin the practice Chrome window → Workflow Lab → Capture in 3 sec → inspect OCR and identified controls → describe the desired field values/selections → Generate with DeepSeek → Preview → Run in 3 sec → inspect field readback and live log → Save Tool.

The application performs the native input. The model proposes commands; the internal compiler and controller validate and execute them. ChatGPT/Codex does not need to move the pointer or type each step of this demonstration.

### O. Solve and enter a visual math exercise

Workflow Lab → Solve Visual Algebra → inspect the captured equation/transcription, roots, and exact checks → Generate with DeepSeek for the reviewed answer goal → Preview → Run. For a full end-to-end demonstration, use **Run 4-page Math Demo**, described below.

## 9. Learning windows, features, menus, and key combinations

### App Learner builds an application catalog

**App Learner (tab 14)** can collect:

- Win32 controls: ClassNN, text, position, and dimensions.
- Accessibility elements: names, roles, values, paths, exposed KeyboardShortcut properties, and positions.
- Win32 menu items: complete menu path, accelerators, Alt access keys, command IDs, and item order.
- Alt+OCR menu scans for applications without a normal Win32 menu bar. This actively opens menus and uses keyboard navigation; let it finish without competing input.
- Visible OCR lines and FindText visual captures for learned elements.

The UI offers Controls, Acc tree, Menus (Win32), Alt+OCR menus, FindText visuals, and OCR text scan options. Learn Selected or Learn ALL Windows saves an app model by executable/class into `data/appmap.db`; relearning replaces that app's element rows. Learn the relevant page/state, and relearn after substantial UI changes.

Filter the learned elements by name/kind. Use **Highlight** to inspect location, **Test Click** to execute an action, **Copy Ref** for the selected element reference, **View Catalog**, **Export JSON**, and **LLM Instructions**. References can be a name, complete menu path, or `#id`. A short ambiguous name can resolve to the wrong item; use the full menu path or current catalog ID.

The live locator tries accessibility path, Win32 control identity, saved FindText pattern, then window-relative coordinates, with stored absolute coordinates as a final fallback. This supports movement/resizing but does not guarantee that a rearranged interface still matches. Coordinate fallbacks need a result check.

### Discovering context-specific shortcuts

There are three distinct evidence sources:

1. **Declared shortcuts:** App Learner reads accessibility KeyboardShortcut values and menu accelerators/access keys. This can reveal previously unfamiliar combinations without guessing keys.
2. **Observed shortcuts:** Tracking → Key History → Top Hotkeys shows combinations actually used, including per-window views. It tells you usage frequency, not the command's semantic effect.
3. **Repeated context:** Vision Scout/Usage Predictor associate key events with windows/elements and repeated surrounding actions. Their offers are learned continuations, not proof that a combination works on every page.

For a discovered shortcut, record the app, menu path/function, current state, key sequence, expected effect, and verified result. Test it in the intended window and add an Activate Window plus a page/content guard to a saved workflow. The code does not systematically brute-force new combinations or automatically infer reliable function descriptions for all observed keys.

### Menu invocation paths

AppDSL `menu File > Save` can choose among known invocation paths. Force a path with `@cmd`, `@altletter`, `@keys`, `@mouse`, or `@random`. Here `@keys` means learned menu navigation via keys, rather than assuming an arbitrary shortcut string. `@cmd` posts a known menu command directly; it is not visible mouse/keyboard engagement. Randomize varies visible menu navigation paths; it is not a global human-typing profile.

### AppDSL reference

AppDSL is a separate line-oriented runner, not the Workflow action table and not the Study tool language.

| Command | Purpose |
|---|---|
| `focus` | Activate the selected learned app. |
| `use notepad` | Target another already learned app by name/executable. |
| `learn` | Learn the active window and switch targeting to it. |
| `menu File > Save @mouse` | Invoke a learned menu path. |
| `alt f s` | Raw Alt+F then S navigation. |
| `click TARGET`, `dblclick TARGET`, `rightclick TARGET`, `hover TARGET` | Resolve a learned target and act. |
| `clickat 100 200 win` | Raw coordinates; optional `win` adds live window origin. |
| `type Literal text` | Literal text entry; `%ENVVAR%` expansion supported. |
| `ctrltext Edit1`\|`Some text` | Set a native control's text directly. |
| `keys ^s` | AHK key syntax sent to the active window. |
| `wait 500` | Delay, capped at 60 seconds per call. |
| `waitwin Save 8000` | Wait for a window. |
| `focuswin Save 8000` | Wait, activate, and confirm focus. |
| `ocr` / `ocr 100 200 300 100` | Read a window/region into `$ocr`. |
| `ocrclick Text`, `ocrrightclick Text` | Read and click visible text; `@scroll` searches successive views. |
| `waitocr Expected text 8000` | Wait for text on the active window. |
| `menupick Properties` | OCR the currently open menu/context menu and click the item. |
| `run notepad.exe` | Launch a resource; supports `%ENVVAR%` paths. |
| `setclip line one\nline two` | Set clipboard; `\n` and `\t` become newline/tab. |
| `say A status message` | Display status. |

Lines starting with `;` or `#` are comments. Prefix `try` to continue on failure. Prefix `retry 10000` to repeat a command about every 0.8 seconds until it succeeds or times out. These combine: `try retry 5000 menupick Open with`.

AppDSL saves OCR in its internal `$ocr` entry, but the current text-expansion helper only expands environment variables. `type $ocr` does **not** automatically insert that OCR result. Use tab 1's OCR/variable actions for a working capture-to-entry sequence, or add an explicit bridge when extending AppDSL.

Example, after learning Notepad and confirming its Edit > Select All menu exists:

```text
focus
type A visible automation sample
menu Edit > Select All @keys
keys ^c
say Text selected and copied; inspect the clipboard
```

The runner's built-in Load Demo choices include a Notepad → saved Python file → VS Code chain, menu-pathway certification, Explorer context-menu use, and a Calculator + Notepad + Explorer chain. These can launch applications, create files, and run commands. Review the script and prerequisites before launching them; they are examples, not all newly live-certified by this guide audit.

### Window Model: structural insight

Ctrl+Shift+7 opens the learned-window structure panel. `WindowModel.ahk` groups stored elements into spatial regions and classifies them using geometry and role/name clues. Rebuild after learning an app; inspect regions and elements; export the map. This supplies a useful structural description of a window but does not itself plan or execute a complete task.

## 10. Learning repeated behavior and offering continuations

### Vision Scout: visual candidates plus sequence learning

In **Vision Scout (tab 16)**, start the scout and scan a window or screen. It segments visible pixels into candidate regions, captures patterns, and associates mouse/key/window activity with them. Review overlays can be selected and moved. Use **Test Find → Certify**, or Reject/Reset, then **Export**.

**Only human-certified candidates with patterns export to tab 2.** Promote Use concerns frequency; it is distinct from certification. A visual candidate is not automatically a meaningful control. Name and review its function.

Mine Seqs learns repeated event sequences and can arm an offer after a matching prefix. **Win+CapsLock** accepts an armed continuation. Clicks can use visual, relative, then absolute fallback; key/window events replay. Freeform typing is not automatically filled. The continuation executor can continue past failed individual tokens, so inspect its done/total result and application state.

Vision Scout's name does not imply that it calls DeepSeek. Its current core is visual segmentation, event capture, and repeated-sequence mining.

### Usage Predictor: context-based event transitions

**Usage Predictor (tab 17)** records APP, CLICK, KEY, and TYPE events, performs coarse virtual-desktop visual scans, and learns next-action transitions from recent event prefixes. Current defaults require at least three observations and confidence at least 0.72. “Confidence” here is the observed transition proportion, not a calibrated probability of task success.

Repeated practice can yield a proposed chain of up to six actions. Use its accept button or **Win+Shift+CapsLock**. It replays only after acceptance and stops when a replay action fails. Click localization uses a saved pattern or relative window coordinates.

Literal typing capture is optional; a TYPE event without captured text stops replay at that point. Review text-capture/privacy settings before recording a task. Promoted visual patterns can be copied for use in the Patterns tab. The predictor is a separate learner; it does not automatically export every learned continuation into a tab-1 workflow.

### Teach a reusable engagement sequence

Choose a short task with a stable context: focus a sample editor → select text → copy → focus another sample editor → paste. Start one learner, perform several consistent repetitions, review candidate targets and the resulting offer, then accept it in the same prepared context. Verify every destination. Keep a repeatable deterministic workflow for tasks that need explicit state/error handling; use learned offers to assist common repeated engagement.

## 11. DeepSeek, internal input simulation, and visual algebra

### Which provider controls which feature?

- **App Learner's copilot:** local/configured **Ollama** endpoint. Its catalog/prompt can also be copied to another LLM, but it has no direct DeepSeek UI bridge in that tab.
- **Study Assistant / Live Portal / Workflow Lab / visual math:** `StudyLLM.ahk` uses the **DeepSeek API**. Model selection, availability probing, cost accounting, retries, and cancellation live here.
- **Vision Scout / Usage Predictor:** local visual/statistical learners, not external LLM services.

DeepSeek setup: use Study Assistant's Save API key or Live Portal's Save API Key, or supply `DEEPSEEK_API_KEY` in the environment before launch. Saved keys use Windows Credential Manager (`MacroAutomator/DeepSeek`). Probe the account with Test / probe or Probe API. The current code defaults to `deepseek-v4-pro` for text and `deepseek-flash` for vision; these are **code defaults as audited**, and the account probe should confirm current availability. Configure the cost cap and apply the engine settings.

### Study Assistant's intelligence layer

Import text/Markdown, PDF through OCR, or pasted notes. Select/exclude sources; capture read-along regions when enabled. PDF import is bounded (default first 60 pages); reimport starts from page 1. Word files need export to PDF/text first.

The answer engine tries verified exact memory, compatible near matches, source passages/concepts, local deduction, then optional DeepSeek fallback. It keeps provenance and answer versions. Near matching and confidence are heuristic, not an embedding-based or statistically calibrated understanding engine.

Use **Confirm**, **Dispute**, **Mark wrong**, and **Edit answer** to maintain the bank. A model suggestion alone remains a candidate. Export a study guide, flashcards, missed list, or concepts; use Review due/Queue all for spaced review.

### Live Portal modes and context

Pin a visible Chrome window with **Pin Chrome Window** or Ctrl+Shift+U while pointing at it. Choose the capture region, then Start. A session never starts merely because the application launches.

| Mode | Behavior |
|---|---|
| observe | Capture/identify without answer entry. |
| suggest | Retrieve/generate a reviewable answer. Default behavior. |
| fill | Enter an acceptable answer without final submission. |
| submit | Fill and submit; also requires the Auto-submit setting. Restored submit mode downgrades to suggest at startup. |

The default confidence floor is 0.75. Model-only candidates receive a provisional score of 0.5, so **a successful DeepSeek response alone does not normally trigger automatic entry**. Confirm evidence or use the explicitly reviewed Workflow Lab goal path; changing a confidence threshold is not proof that an answer is correct.

The controller checks pinned window/title/URL, foreground state, region/monitor availability, page/question fingerprint, fresh target identity/bounds, protected fields, and readback. Focus loss or a changed/obscured target pauses/refuses input. Accessibility must expose a usable control; OCR text by itself is not permission to guess a click coordinate in this runner.

### Feature names and function descriptions

Each gathered control has a session ID, kind/role, name, value or checked state, bounds, and inferred purpose/allowed commands. Feature descriptions can be remembered by **exact URL plus stable kind/name identity** and included in later planner prompts. A name such as `AllRoots` plus a description such as “enter every verified real root” gives the planner usable context. IDs can change across captures; the fresh catalog is authoritative.

Descriptions are model/heuristic interpretations, not executable guarantees. The final compiled actions still need structural validation, context guards, and readback.

### Workflow Lab and its bounded tool language

Open **Live Portal → Workflow Lab**. Capture in 3 sec gives time to focus the pinned page. Review the gathered OCR/catalog, describe the goal, Generate with DeepSeek, Preview, then Run in 3 sec. Save Tool/Load Tool stores one reusable tool slot and checks URL/catalog compatibility; this is not a general self-writing code repository.

| Command | Meaning |
|---|---|
| `TYPE controlId literal text` | Enter text into the identified field. |
| `SET controlId 0` / `SET controlId 1` | Set a checkbox off/on; radio SET uses 1. |
| `CHOOSE controlId Exact option` | Select an accessible dropdown value via guarded keys and readback. |
| `HOVER controlId 250` | Hover for the specified milliseconds. |
| `WAIT 300` | Bounded delay. |
| `CLICK controlId` | Focus an edit/dropdown, or activate a recognized answer-submit button. Buttons require submit mode and auto-submit. |

**Do not wrap TYPE/CHOOSE values in quotation marks**: the remaining text is literal. Scripts are capped at 12,000 characters, 50 underlying steps, 2,000 characters per text value, and 3,000 ms per wait/hover with a 15-second aggregate explicit-wait budget. No arbitrary AHK/Python, shell execution, raw screen coordinates, freeform key commands, or general links/navigation are exposed to this language.

DeepSeek proposes the script. The application compiles it, rejects unknown IDs/unsupported operations, can ask for one bounded repair using rejection feedback, and executes through its own native input layer. Structural validity alone cannot prove the model fulfilled a freeform goal; the general lab's goal/output needs review. The math demo adds a trusted exact-goal validator.

### Human input profiles

**Input Settings** controls the Study controller's human-paced input, separately from tab 1's delays and App Learner's menu randomization.

| Setting | Supported range / purpose |
|---|---|
| Typing WPM | 5–250; randomized per-character timing around the profile. |
| Typo chance | 0–0.3 per character; plausible neighboring-key mistakes followed by Backspace and correction. |
| Hover duration | 0–3000 ms. |
| Wobble | 0–3; curved-path variation. |
| Overshoot maximum | 0–30 px; bounded movement beyond a target followed by return. |
| Overshoot chance | 0–1. |
| Target jitter | 0–8 px. |
| Pause chance | 0–0.5. |
| Paste long text | Optional faster long-field entry instead of character typing. |

The controller uses curved paths, hover pauses, click variation, and corrected typing. It checks cancellation/context along pointer waypoints and characters, relocates targets, and verifies final field/selection values. There is no claim of invisibility or perfect imitation of a person. These effects are application-generated input, not Codex remote desktop gestures.

### Visual algebra and a four-page demonstration

**Solve Visual Algebra** captures the pinned page, sends the image for transcription and a proposed educational solution, then runs a **fixed local Python/SymPy verifier**. It displays the source image, transcribed equations, real roots, worked steps, and exact residual/domain checks.

Supported verifier scope: finite real solutions to equations/systems with up to three variables (`x,y,z`), arithmetic, integer powers from −8 to 8, and square roots. It handles supported implicit multiplication and common visual Unicode operators. It checks original denominator/radical constraints and the complete proposed solution set. Unsupported, ambiguous, infinite, or parametric cases require review. A bounded repair may correct the proposed solution using CAS feedback, but cannot silently replace the transcribed equations.

**CAS proves the solution to the transcription, not that the transcription is visually correct.** Inspect the image against the equation. Worked prose is educational output; every intermediate prose step is not independently proved.

Prerequisites: DeepSeek vision access, Chrome, and a Python interpreter with SymPy. The code searches installed interpreters; `math_python` is the study setting for an explicit interpreter. The fixed helper is [algebra_solver.py](tests/algebra_solver.py).

Click **Run 4-page Math Demo** to see the coordinated pipeline:

```text
Open local canvas-equation practice portal
 → capture visible page and accessible controls
 → log identified names, roles, function descriptions, OCR, and image
 → request a visual solve and verify all roots locally
 → ask DeepSeek for a field-entry tool
 → validate exact values / selection goals
 → native mouse paths, dropdown keys, checkboxes, typo-and-correct text
 → exact control readback
 → Check Answer, OCR the feedback
 → authorize the demo's specific Next/Finish control
 → verify the expected next local URL and recapture
 → repeat across four distinct pages
```

The exercises cover a fractional linear equation (`x=7`), a quadratic (roots `2,3`), a two-variable system (`x=4,y=3`), and a radical equation (`x=4`). The first page includes a longer verification note to make corrections visible. The page displays actual native key/backspace/pointer/click counters and completion state. Equation text is rendered on canvas, so the solve uses the screenshot rather than hidden DOM equation text.

The demo grants special navigation authority only to its exact local practice URLs and named Check/Next/Finish controls while it runs. That authority does not become general navigation permission for ordinary model-generated tools.

## 12. All tabs and supporting panels

| Tab | Main capabilities | Role in an automation |
|---|---|---|
| 1 Workflow | Guided actions, conditions, loops, failsafes, templates, saved library, `.maw`, Demo Lab | Build and run known engagement sequences. |
| 2 Patterns | Quick/advanced capture, names/descriptions, qualifiers, preview, tests | Maintain reusable visual targets. |
| 3 Live OCR | Capture/record, word boxes, search, Watch Words, regex/splitting, variables, OCR revolver | Gather values and identify visible text. |
| 4 Spools | Conditions, timed checks, responses, repeat modes, completion, `.mas`, activity log | Launch work when context matches. |
| 5 Analytics | Click event recording, mouse-position hotspots, CSV export, taskbar index | Discover likely interactions and map taskbar order. “Full Recording” currently records click events and mouse hotspot samples, not a complete keyboard/action replay. |
| 6 Clipboard | Extraction rules, fields/order, standard revolver, smart bins | Turn structured text into repeatable entry. |
| 7 Hotkeys | Assign/manage workflow hotkeys | Launch a saved sequence using AHK key syntax. |
| 8 Hotstrings | Text expansion, options, enabled/master state, tests | Insert repeated text; workflow hotstrings are also available through Workflow metadata. |
| 9 Triggers | Time and window-activation notification/logging paths, templates | **Partial implementation:** see boundaries below; use Spools for an actual condition-launched workflow. |
| 10 Settings | Delays, retries, FindText tolerance/timeout, close-button protection, capture options, notifications | Tune standard workflow behavior. |
| 11 Notepad | Save/load notes, popup, clipboard and text sending, note-to-sequence helper | Store reusable text and demonstrate entry. |
| 12 Calendar | Daily slots, booking types, patient profiles, local appointments | Organize local scheduling data; not an automatic external calendar/clinical-system connector. |
| 13 Tracking | Window time, mouse traces/heatmaps, key/clipboard history, snapshots, registry, research, exports/pruning | Gather per-window evidence and reusable targets. |
| 14 App Learner | Controls/accessibility/menus/OCR/pattern catalog, AppDSL, Ollama, built-in demos | Learn and operate a new application. |
| 15 Snapshot Recovery | Phrase/image search, OCR, recorded URL/file recovery, Chrome history matching, exclusions | Return to previously seen material. |
| 16 Vision Scout | Visual region discovery, review/certification/export, event sequence mining, accepted offers | Grow a visual target library and learned continuations. |
| 17 Usage Predictor | Visual scans, promoted targets, APP/CLICK/KEY/TYPE history and transition offers | Assist repeated engagement sequences. |
| 18 Study Assistant | Sources, concept/passages, answer bank, verification/correction, reviews/exports | Build reusable evidence-backed study memory. |
| 19 Live Portal | Chrome pinning, modes, perception, answer bridge, internal input profiles, Workflow Lab | Execute bounded, validated entry against live page controls. |

Supporting panels:

- **Attention panel (Ctrl+Shift+A):** measured focus/prominence and media watch-time information. Use it to understand actual engagement, not to generate actions automatically.
- **Snip Studio (Ctrl+Shift+1..4):** saved-region capture, OCR confirmation/correction, multiple representations, settings and question parsing.
- **Question bank / roulette (Ctrl+Shift+5..6):** retain parsed questions and surface unanswered items. Distinct from automated portal submission.
- **Window Model (Ctrl+Shift+7):** inspect/rebuild/export a learned app's structural map.
- **Snapshot Viewer:** image/binary/OCR representations and drag-to-define named elements with role/description and relative coordinates.
- **Mouse Heat / Trace:** inspect snapshots, extract hotspots/features, replay movement, export generated feature representations.
- **Key History:** per-window/all activity, ordered typed runs and clipboard captures, top hotkeys, privacy/exclusion controls.

## 13. Logs, evidence, storage, and recovery

### Match the log to the runner

| Evidence | Location / access | What it shows |
|---|---|---|
| Startup output | Logged launcher; `data/logs` | Load errors/warnings. |
| Runtime error log | `data/logs/MacroAutomator_errors.log`; Workflow → Error Log | Caught/unhandled errors with context. |
| Spool activity | `data/logs/spool_activity.log`; Spools → Activity Log | Trigger/response/cooldown/failure history; UI retains latest 100 entries. |
| Live OCR history | Live OCR → View/Export; `data/ocr_log.txt` | Captured OCR content/history. |
| Analytics click recording | `data/recording.csv` | Recorded click events and their window/method metadata. |
| Tracking | `data/tracking.db`, `data/tracking` outputs | Window activity, mouse/key snapshots, captures, elements, learner events, research and study records. |
| App Learner console | App Learner → Console → Copy All | Narrated controls, accessibility/menu/OCR/pattern learning. It is a UI transcript, not the Study JSONL audit. |
| Standard workflow debug | Settings → Debug Mode; per-step notifications/status | Step starts/results. Not a complete persistent action-by-action JSONL audit. |
| Study / DeepSeek live audit | Workflow Lab → Live Console; `fan/logs/study/*.jsonl` | Structured capture, identification, lookup, provider, solve, plan, input, readback, navigation, and error events. |
| Visual math images | Run-specific image directory under `fan/logs/study` | Screenshot used for transcription/verification review. |

The Study console filters CAPTURE, IDENTIFY, LOOKUP, LLM, MATH, PLAN, ACTION, INPUT, VERIFY, NAV, and ERROR, or shows ALL. Follow live keeps it updating; turn it off to inspect a section. It shows the newest 1,500 events; all emitted events remain in the JSONL file. Open log folder and Abort are built in.

Provider audit events include purpose, model, prompt/context, image path, request attempts/status, rejection/repair feedback, tokens, cost estimate, completion, and errors. Image base64 and authorization headers are excluded; registered keys/token forms are redacted. Input logs include pointer waypoints, overshoots, typing attempts, typos/corrections, target relocation, and verified final state. No log is an unrestricted transcript of hidden model reasoning.

**Captured content and entered answers are retained.** Credential redaction is not general personal-data redaction. Tracking privacy controls and snapshot exclusions apply to their own subsystems; there is no single retention/privacy policy automatically covering every log and learner. Use sample content for demonstrations and export only the evidence you intend to share.

### Main persistent stores

- `data/macroauto.sqlite`: core patterns, workflows, spools, and related application data through the core SQLite wrapper.
- `data/appmap.db`: App Learner application/control/menu catalog and its settings.
- `data/tracking.db`: tracking, learner, research, question-bank, and Study tables through TrackSQLite.
- Other data files include coordinate/extraction/configuration and preview/screenshot outputs. Some paths are legacy import or subsystem files; do not assume every INI is the authoritative database.

Use the UI's export functions where available. Close/stop the application before manually backing up database files so SQLite/WAL state is consistent. Prune/exclusion controls are subsystem-specific; they are not a global delete-all operation.

### Recover prior material

Enable snapshots and optional OCR in Tracking for material you want to recover. In Snapshot Recovery, search a phrase/preset; inspect the evidence and image; OCR the selected image if necessary; open its recorded URL/file or use Chrome-history title/time matching. History and filename clues are candidates, not proof of an exact source match. Everything integration can assist indexed-file search when its required installation/DLL is available.

## 14. Keyboard shortcuts

These are the bindings in the audited entry point. User-assigned workflow hotkeys/hotstrings and other application shortcuts can conflict with them.

| Shortcut | Action |
|---|---|
| Ctrl+Shift+G | Show/hide main GUI |
| Ctrl+Shift+P | Pause/resume standard workflow flag |
| Ctrl+Shift+X | Abort standard workflow flag |
| Escape | Abort running standard workflow/simulation; contextual definition/capture behavior also exists |
| Tab | Advance standard step-through while enabled |
| Ctrl+Shift+C | Clear notifications |
| Ctrl+Shift+F | FindText GUI |
| Ctrl+Shift+Q | Quick drag-box OCR |
| Ctrl+B | Copy selection, parse, load standard revolver |
| Ctrl+Shift+B | Fire standard revolver batch |
| Ctrl+Alt+B | Load clipboard into smart bins / selector |
| Ctrl+Alt+Shift+B | Paste from bins |
| Win+B | Open bin selector (overrides the usual Windows binding while this app owns it) |
| Ctrl+Alt+N | Popup notepad |
| Ctrl+Alt+I | Idle Mouse wait, indefinite until its movement/stop condition |
| Ctrl+Alt+T | Toggle all trackers |
| Ctrl+Alt+Shift+S | Snapshot Viewer |
| Ctrl+Alt+Shift+C | Capture snapshot cycle now |
| Ctrl+Shift+A | Attention panel |
| Ctrl+Shift+1 | Snip saved region / choose first region |
| Ctrl+Shift+2 | View last snip |
| Ctrl+Shift+3 | Redraw snip region |
| Ctrl+Shift+4 | Snip settings |
| Ctrl+Shift+5 | Question bank |
| Ctrl+Shift+6 | Surface an unanswered question |
| Ctrl+Shift+7 | Window Model |
| Ctrl+Shift+8 | Next due Study review |
| Ctrl+Shift+U | Pin Chrome window under pointer |
| Ctrl+Shift+Y | Toggle Live Portal session |
| Ctrl+Shift+Escape | Abort Study controller input / waits / API receive |
| Win+CapsLock | Accept armed Vision Scout continuation |
| Win+Shift+CapsLock | Accept Usage Predictor continuation |
| CapsLock ON + C/D/R/T/P/W/K/M | Definition Mode step capture |

AHK owns some keys globally while running. If Ctrl+B should bold text in another application, this program's revolver binding may intercept it. Stop/reconfigure the conflicting automation instead of assuming the destination received that key.

## 15. Libraries and code integration examples

This section is for extending the project or giving an LLM an accurate tool inventory. Most UI users can follow the recipes without writing AHK.

### Runtime map

| Library / module | Used in `fan` | Coordination |
|---|---|---|
| Root `FindText.ahk` | Yes | Pattern capture/search, visual target relocation, snapshot binaries/learner visual templates. |
| Root `OCR.ahk` | Yes | Windows OCR over regions/windows/files/PDF workflows; text/word/line evidence. |
| Root `SQLiteDB.ahk` | Yes | Core app database. |
| `Acc.ahk` | Yes | MSAA accessibility/control context for App Learner and Study perception. This is not a separate comprehensive UIA-library controller. |
| `TrackSQLite`, `TrackingDB`, `TrackUtil` | Yes | Shared tracking/study/learner database, JSON and context utilities. |
| `WindowTracker`, `MouseTracker`, `KeyTracker` | Yes | Contextual event capture, traces, key histories. |
| `SnapshotEngine`, `PixelCanvas`, `ElementViewer`, `ElementAutomation` | Yes | Capture/render/name/find targets; heat/feature visualizations. |
| `ResearchPipeline` | Yes | Queries, URL queue, insights and reports. |
| `AppLearner`, `WindowModel` | Yes | App catalog, menu pathways, AppDSL/Ollama prompts, spatial regions. |
| `VisionScout`, `UsagePatternPredictor` | Yes | Local visual candidates and learned continuations. |
| `Everything3Client`, `SnapshotRecovery` | Yes, optional external search support | Indexed files and source recovery. |
| `AttentionEngine`, `SnipStudio`, `SnipParse` | Yes | Engagement context, confirmed captures, parsed question bank. |
| `StudyDB`, `StudyIngest`, `StudyAssistant` | Yes | Persistent sources/concepts/answers/reviews. |
| `StudyLLM`, `StudyAutomation`, `StudyComposer`, `StudyLive`, `StudyTools` | Yes | Provider, guarded perception/input, live bridge, bounded tool generation. |
| `StudyConsole`, `StudyMath`, `StudyDemo` | Yes | Structured audit, visual solve/CAS, sequential demonstration. |
| Core `_Gdip.ahk` | Yes | GDI+ screen capture for project paths. |
| Additional `ImagePut`, `JSON`, screenshot tools, `Gdip_All` copies | Bundled; not all included in entry | Extension utilities, not automatically enabled features. Check version/API before including. |
| `Vis2.ahk` | **Not included; v1 library** | Legacy Tesseract/Google Vision path. Do not include a v1 script into the v2 process. |

See the broader [library reference](../lib/LIBRARY_GUIDE.md) for bundled APIs. Its older main-script references are historical; the current `fan/MacroAutomator.ahk` includes are the authority for what loads here. The two SQLite classes have different APIs; core data uses SQLiteDB, tracking/study code uses `TrackDB()` / TrackSQLite.

### A. Capture text and store it for a standard workflow

Inside the already initialized app:

```ahk
result := OCR.FromRect(100, 200, 400, 120) ; x, y, width, height
g_SpoolVariables["orderText"] := Trim(result.Text)
; A later Type Text Parameter can contain: Order: $var.orderText
```

The library's FromRect takes width/height; that does not change the tab-1 corner-parser formats described earlier.

### B. Search a saved visual target

```ahk
match := FindPatternOnScreen("Inventory_RefreshButton")
if match["found"] {
    ; Choose the right action only after checking current context.
    ClickVerified(match["mx"], match["my"])
}
```

FindPatternOnScreen is a project helper, not a semantic object detector. Add window/page constraints and a result check for a production action.

### C. Learn a window and expose the catalog to a planner

```ahk
hwnd := WinExist("Notepad")
if hwnd {
    learned := AppMap_LearnWindow(hwnd, Map("controls", true, "acc", true,
        "menus", true, "ocrtext", true, "altocr", false, "visuals", true))
    if learned.Has("id") {
        prompt := AppMap_BuildLLMPrompt(learned["id"], "Select all text and copy it")
        ; Ollama_GenerateScript performs this tab's configured provider call.
        ; Review the returned AppDSL before AppExec_Run(learned["id"], script).
    }
}
```

Learning is a snapshot of the available interface; it does not discover hidden pages without visiting them. The prompt includes DSL grammar and the catalog. Generated scripts still operate through AppDSL, not executable model-written AHK source.

### D. Use a named tracked element

```ahk
location := Element_WaitByName("InventorySearch", 5000)
if IsObject(location) && location.Count
    Element_ClickByName("InventorySearch", "Left", 1)
```

This registry is created through Snapshot Viewer/Tracking. It is different from App Learner's app element rows and Study's session control IDs. Relative-coordinate fallback can yield a location without proving visual presence; test it on the real window.

### E. Coordinate the DeepSeek system

```text
StudyPercept_* capture
  + StudyFeatures_* names/descriptions
  + Study_Answer retrieval/evidence (when answering a study question)
  + StudyLLM_* text/image provider request
  → StudyTools_* bounded script compile / preview / repair
  → StudyMacro_* guarded native execution and readback
  → StudyConsole_Log stage events
  → StudyDB settings/answer provenance for later reuse
```

For visual math, insert StudyMath plus the fixed SymPy helper before generating entry actions. For the sequential demonstration, StudyDemo supplies the exact-goal validator and scoped navigation. These examples describe the real module coordination; there is no existing tool that automatically turns every bundled library function into an unrestricted DeepSeek-callable operation.

### Extending toward a broader automation engine

A useful new capability should have: a named target/operation, clear inputs, live context requirements, bounded execution, a success check, an abort path, and structured logging. Add it to the appropriate runner rather than assuming the action exists because a library is installed. For tab 1, keep the action list, guided forms/help, validation, engine dispatch, serialization, and simulation consistent. For Study tools, extend the compiler and guarded executor together, with a trusted validation rule for the new command.

This is an extension pattern, **not a claim that a universal tool registry or arbitrary autonomous desktop planner already exists**. Current saved workflows, AppDSL, prediction offers, and DeepSeek tools have distinct storage, IDs, permissions, and verification behavior.

## 16. Troubleshooting and current boundaries

| Symptom | Check / next step |
|---|---|
| Wrong build or missing new controls | Launch `fan/MacroAutomator.ahk`; reload the loaded AHK instance after updates. |
| Script fails before GUI appears | Use logged launcher and inspect startup/error output; use AHK v2 and intact include paths/DLL. |
| Click lands in the wrong place | Inspect Target, window, DPI, monitor, scroll state, and whether resolver fell back to coordinates. Simulate is not sufficient evidence. |
| Pattern not found | Make it visible/unobscured; compare scale/theme/state; test preview; recapture or adjust tolerance. |
| OCR is empty or wrong | Verify the rectangle format, installed OCR language, text size/scale, contrast, and capture contents. |
| OCR clicked the wrong word | Crop tightly; use a unique term/pattern; account for permissive first substring matching. |
| Variable is blank/stale | Confirm source capture, name/namespace, and current value. Initialize fresh values; Watch Word refresh failure may retain old data. |
| Spool fires repeatedly | Found condition remains true; use One-Shot/Cooldown and explicit completion/reset logic. |
| Spool stopped without a successful response | One-Shot stops after the trigger attempt, including failures. Check activity and actual output. |
| Spool restarts next launch | Master Enable and enabled spool state persist. Stop All/master off before leaving if desired. |
| Nested workflow loop does nothing | Run Sequence currently uses direct action execution; keep loop control in the top-level workflow. |
| Keys go to wrong app | Wait for existence is not activation. Add Activate Window / AppDSL focuswin, then verify the target. |
| Ordinary letter keys add workflow rows | CapsLock Definition Mode is ON. Turn it OFF. |
| Ctrl+B / Win+B does unexpected work | Global app bindings conflict with standard destination/Windows behavior. |
| DeepSeek response but no automatic entry | Candidate confidence below the configured floor, wrong mode, or a context/target guard blocked entry; inspect log. |
| Study run stops after a page/tab change | Re-pin/recapture the intended page. Standard Study tools do not authorize arbitrary navigation. |
| Visual solver rejects a result | Compare screenshot/transcription, CAS/domain feedback, supported scope, and Python/SymPy availability. |
| Learned offer does not replay typing | Vision Scout does not fill arbitrary text; Usage Predictor requires literal typing capture. |
| Direct control operation is invisible | AppDSL @cmd/ctrltext can use messages/control APIs. Choose visible pathways for an engagement demonstration. |
| Multiple engines compete for input | Stop spools/learners/other runners, then run one controller. No global exclusive-input arbiter exists. |

### Known unfinished or weaker paths

1. **Triggers tab:** the active checker evaluates Time-Based and Window Activation. The extra OCR/action/error/variable/combination/sequence/debug types shown in its dropdown are not generally wired to that checker. Its live `ExecuteTriggerAction` supports notification/logging; “Run Sequence” displays **“Would execute sequence”** instead of running one. The separate `ExecuteTriggerAction2` contains more code but is not the live dispatcher. Set Variable, Execute Command, and Play Sound UI choices are not implemented by that live dispatcher. Use Spools → Run Workflow for working condition-driven sequences. Notification timeout units also vary between old templates and live parsing; inspect actual behavior.
2. **Idle Mouse:** currently waits for movement/duration rather than generating motion, and its indefinite loop does not inspect the standard workflow abort flag. Use a finite duration or its movement exit; do not rely on Escape to end this specific wait.
3. **Older coordinate/visual runners:** relative or absolute fallbacks, broad searches, and “verified” helper names do not provide the Study controller's window/URL/field-readback guarantees. Some older blocking waits/replays do not respond promptly to the standard abort flag.
4. **Application learning:** catalogs and geometry provide useful context, but not full semantic knowledge, unseen-state exploration, or automatic reliability after every UI redesign.
5. **Browser identity:** standard workflows use titles/keys/pixels. Study adds pinned URL/title checks, but two identical same-URL/title tabs are not uniquely distinguished by those signals.
6. **Unsupported Study interactions:** arbitrary navigation, custom/inaccessible widgets, general drag/drop/order/matching interfaces, and unrestricted desktop operations require additional engineering/review.
7. **Math scope:** this verifier is not a general theorem prover or every Algebra course problem type. It validates supported finite real solutions to the captured transcription.
8. **Complete auditing:** Study JSONL is detailed; older workflow, learner, trigger, and tracking paths retain different evidence. “Verbose everything” is not yet one consistent project-wide event stream.

These limits matter when combining features. The program is a broad automation toolkit, with several working paths toward context-aware engagement; reliable autonomy comes from explicit context, bounded action, and measured results in the selected runner.

## 17. Demonstrations and validation evidence

### Available demonstration surfaces

| Demo | What to inspect | Status / prerequisites |
|---|---|---|
| Workflow → Demo Lab | Text, clicks, menu selection, drags, relative targets, FindText/OCR, revolver destination fields and event log | Built into the tab-1 code; use individual steps to learn the action palette. |
| Workflow → Templates | Appended example sequence, captured variable, notification | Replace sample targets/regions; template insertion alone is not validation. |
| Spool certification `.mas` | Trigger → embedded workflow → visible output/log | See [spool quick guide](../SPOOL_WORKFLOW_GUIDE.txt); import examples only after reviewing their contents. |
| App Learner → Load Demo | Script, learning console, visible app state at each handoff | Examples exist; external apps/files/commands vary by demo and machine. |
| Vision Scout review | Candidate box → Test Find → Certify → Patterns export | Certify live matches, then test exported pattern separately. |
| Usage Predictor repeated task | Event chain, support/confidence, accepted replay result | Requires repeated observations; text replay depends on capture choice. |
| Live Portal → Dry-run Fixtures | Classified questions/plans and rejection cases | Offline fixture checks; no proof of a particular real portal's compatibility. |
| Workflow Lab → practice / math demo | OCR, feature catalog, real provider requests, exact solutions, native input/readback, four page transitions | End-to-end visual math run completed on this machine; current source includes further unit-checked navigation restrictions. |

The successful recorded four-page visual math run used the **internal AHK controller and real DeepSeek calls**. It retained 1,321 audit events, nine corrected typing mistakes, 30 overshoot events, and all four correct result pages. The estimated API cost for that specific run was about $0.0165; it is historical run metadata, not a price promise. The page's native counters showed keyboard/backspace/click engagement.

Validation artifacts:

- [Visual math validation record](tests/visual_math_validation.json)
- [Practice-page completion image](tests/math_demo_validation.jpg)
- [Visible solver image](tests/math_solver_validation.jpg)
- [Live console image](tests/math_console_validation.jpg)
- [Implementation and verification notes](IMPLEMENTATION_VALIDATION.md)
- [Study specification and feature ledger](REALTIME_STUDY_ASSISTANT_SPEC.md)
- [Automation subsystem specification](AUTOMATION_SUBSYSTEM_SPEC.md)

The recorded validation included 132 checks across controller, memory, provider, intelligence, and Python math tests. It does not certify all 19 tabs, every legacy action, or an arbitrary external portal. Subsequent exact-local-navigation restrictions were checked with targeted tests after the full live run; do not misread the artifacts as a newer live run of every final-source path.

### How to validate your own sequence

1. Use a lab or sample destination. Establish the expected starting window/page/state.
2. Test identification alone: pattern location, OCR text/box, catalog control, or learned menu reference.
3. Simulate the standard workflow or Preview the Study tool to inspect intended actions.
4. Run one action and inspect its measurable effect, then run the sequence step-through.
5. Test a representative alternate state: moved window, slower load, changed text, missing target, or extra dialog. Confirm it stops/skips as designed.
6. Run the whole sequence and record the actual result plus the appropriate log. Save/export only once its context and outcome are understood.
7. Enable spool repetition or accept learned continuations after the deterministic action path works.

### Code sources behind this guide

The action count/names, forms, loops, simulation, and execution behavior were checked against [Workflow](Tabs/Tab_01_Workflow.ahk), [guided forms](Tabs/Tab_01_Workflow_Forms.ahk), [action engine](Actions/_Engine.ahk), and [core helpers](Core/_Helpers.ahk). Pattern/OCR/spool behavior comes from [Patterns](Tabs/Tab_02_Patterns.ahk), [Live OCR](Tabs/Tab_03_LiveOCR.ahk), and [Spools](Tabs/Tab_04_Spools.ahk). Learning/provider/controller details come from the included modules named above; the [entry point](MacroAutomator.ahk) determines tab order and loaded libraries. This is a code-backed guide, not a claim that every old UI label or specification checkbox is a verified capability.
