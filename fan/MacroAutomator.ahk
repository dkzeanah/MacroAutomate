; ===============================================================================
; MACRO AUTOMATOR v9.0 DEEPSEEK - SELF-LEARNING VISION SCOUT  (MULTI-FILE BUILD)
; ===============================================================================
; ENTRY POINT of the refactored project. Run THIS file, not
; _original_macroautomaterv9-deepseek.ahk (that copy is kept only as a
; pristine reference).
;
;   Core\     globals, shared helpers, database, notifications, GDI+
;   Actions\  the workflow execution engine
;   Tabs\     one file per GUI tab (tab controls + their event handlers)
;
; See SPLIT_MANIFEST.md (which original line ranges live where) and README.md.
; ===============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, StdOut  ; Never block startup with warning popups; logged launcher captures stdout.

; The multi-file project lives one folder below the original project root
; (fan\). APP_ROOT points back to that root when its data\ folder exists, so
; the refactored build uses the SAME working directory, data\ folder and
; database as the single-file original. Moved elsewhere, it falls back to
; this folder and creates its own data\ there.
global APP_ROOT := DirExist(A_ScriptDir . "\..\data") ? A_ScriptDir . "\.." : A_ScriptDir

SetWorkingDir(APP_ROOT)  ; same working directory the original used
CoordMode("Mouse", "Screen") ; Mouse coordinates relative to screen
CoordMode("Pixel", "Screen") ; Pixel coordinates relative to screen
CoordMode("ToolTip", "Screen") ; Tooltip positioning relative to screen

; ═══════════════════════════════════════════════════════════════════════════════
; EXTERNAL LIBRARY INCLUDES
; ═══════════════════════════════════════════════════════════════════════════════
; FindText.ahk: Visual pattern recognition for UI element detection
; OCR.ahk: Optical Character Recognition for text extraction from screen
; ═══════════════════════════════════════════════════════════════════════════════

#Include ..\FindText.ahk
#Include ..\OCR.ahk  ; Windows.Media.Ocr wrapper used by all OCR actions
#Include ..\SQLiteDB.ahk

; ═══════════════════════════════════════════════════════════════════════════════
; TRACKING SUBSYSTEM (window time / mouse / keys / snapshots / elements / research)
; ═══════════════════════════════════════════════════════════════════════════════
; Order matters: utilities and the DB layer first, then the trackers that use
; them, then the UI/automation modules that use the trackers.
;
; NOTE: lib\TrackSQLite.ahk is the tracking subsystem's own SQLite wrapper. It is
; deliberately NOT named SQLiteDB - that class name already belongs to the
; SQLiteDB.ahk included above, which this script's g_DB uses. Two classes with
; the same name in one script is a load-time error, so the tracking store keeps
; its own connection under its own name.
#Include ..\lib\TrackSQLite.ahk
#Include ..\lib\TrackUtil.ahk
#Include ..\lib\TrackingDB.ahk
#Include ..\lib\PixelCanvas.ahk
#Include ..\lib\WindowTracker.ahk
#Include ..\lib\MouseTracker.ahk
#Include ..\lib\KeyTracker.ahk
#Include ..\lib\SnapshotEngine.ahk
#Include ..\lib\ElementAutomation.ahk
#Include ..\lib\ElementViewer.ahk
#Include ..\lib\ResearchPipeline.ahk
#Include ..\lib\TrackingDashboard.ahk

; ═══════════════════════════════════════════════════════════════════════════════
; APP LEARNER (v8): learn whole program interfaces into an object model, drive
; them from a text DSL or a local LLM (Ollama). Acc.ahk supplies the MSAA
; accessibility tree the learner walks.
; ═══════════════════════════════════════════════════════════════════════════════
#Include ..\lib\Acc.ahk
#Include ..\lib\AppLearner.ahk

; ═══════════════════════════════════════════════════════════════════════════════
; VISION SCOUT (v9): self-learning visual scraper + usage sequencer. Segments the
; screen into elements (FindText patterns), tracks clicks/typing/window switches,
; promotes frequently-used elements, and offers to auto-complete repeated
; sequences (Win+CapsLock). See lib\VisionScout.ahk.
; ═══════════════════════════════════════════════════════════════════════════════
#Include ..\lib\VisionScout.ahk

; ═══════════════════════════════════════════════════════════════════════════════
; SNAPSHOT RECOVERY (v8): trace a snapshot back to the page it came from -
; live URL capture, filename clue extraction, Chrome history cross-reference,
; searched with Everything 1.5 query syntax.
; ═══════════════════════════════════════════════════════════════════════════════
#Include ..\lib\Everything3Client.ahk
#Include ..\lib\SnapshotRecovery.ahk
; Attention/prominence measurement: which windows actually held focus,
; watch time for media, and the learned adult-content filter.
#Include ..\lib\AttentionEngine.ahk
; Repeatable region snips with OCR and a correction memory (Ctrl+Shift+1/2/3).
#Include ..\lib\SnipStudio.ahk
; Smart parsing of a capture into individual questions, plus the review
; roulette that resurfaces the ones still unanswered.
#Include ..\lib\SnipParse.ahk
; Semantic layout: cluster a learned app's elements into panes and name them
; (sidebar, editor, status bar) so automation can address regions, not pixels.
#Include ..\lib\WindowModel.ahk
; Generic reflow for the tabs that were laid out with absolute coordinates.
#Include ..\lib\AutoFlow.ahk
; Independent local visual learner from the ChatGPT v9 branch. It complements
; Vision Scout with coarse full-desktop scanning and n-gram continuations.
#Include ..\lib\UsagePatternPredictor.ahk

; (kept from the original file, which includes FindText twice)
#Include ..\FindText.ahk

; ===============================================================================
; GLOBALS
; ===============================================================================
#Include Core\_Globals.ahk

if !DirExist(DATA_DIR)
    DirCreate(DATA_DIR)
if !DirExist(LOG_DIR)
    DirCreate(LOG_DIR)
if !DirExist(PREVIEW_DIR)
    DirCreate(PREVIEW_DIR)
if !DirExist(SCREENSHOTS_DIR)
    DirCreate(SCREENSHOTS_DIR)
; Create notes directory
if !DirExist(NOTES_DIR)
    DirCreate(NOTES_DIR)
; Create tracking output directory
if !DirExist(TRACKING_DIR)
    DirCreate(TRACKING_DIR)


; Initialize GDI+ for screenshot capture
OnError(LogUnhandledError)
g_GdipToken := Gdip_Startup()
OnExit(ShutdownGdip)
OnExit(SaveAllOnExit)
; Flush open tracking buckets/sessions and close the tracking DB cleanly.
OnExit(TrackingOnExit)

; ===============================================================================
; CORE FUNCTION LIBRARIES (definitions only - order-independent in AHK v2)
; ===============================================================================
#Include Core\_Helpers.ahk
#Include Core\_Db.ahk
#Include Core\_Notifications.ahk
#Include Core\_Gdip.ahk
#Include Actions\_Engine.ahk

; ===============================================================================
; TAB FILES (GUI builders + event handlers, one file per tab)
; ===============================================================================
#Include Tabs\Tab_01_Workflow.ahk
#Include Tabs\Tab_01_Workflow_Forms.ahk
#Include Tabs\Tab_02_Patterns.ahk
#Include Tabs\Tab_03_LiveOCR.ahk
#Include Tabs\Tab_04_Spools.ahk
#Include Tabs\Tab_05_Analytics.ahk
#Include Tabs\Tab_06_Clipboard.ahk
#Include Tabs\Tab_07_Hotkeys.ahk
#Include Tabs\Tab_08_Hotstrings.ahk
#Include Tabs\Tab_09_Triggers.ahk
#Include Tabs\Tab_10_Settings.ahk
#Include Tabs\Tab_11_Notepad.ahk
#Include Tabs\Tab_12_Calendar.ahk
#Include Tabs\Tab_13_Tracking.ahk
#Include Tabs\Tab_14_AppLearner.ahk
#Include Tabs\Tab_15_SnapshotRecovery.ahk
#Include Tabs\Tab_16_VisionScout.ahk
#Include Tabs\Tab_17_UsagePredictor.ahk

; ===============================================================================
; MAIN GUI - window shell, toolbar and the tab control itself
; ===============================================================================
MainGui := Gui("+Resize +MinSize900x820", "Macro Automator v9 - Vision Scout + Usage Predictor")
MainGui.SetFont("s9", "Segoe UI")
MainGui.OnEvent("Close", (*) => (MainGui.Hide(), g_GuiVisible := false))
MainGui.OnEvent("Size", GuiResize)

; Top toolbar
OnTopCheck := MainGui.Add("CheckBox", "x10 y5 vOnTop", "On Top")
OnTopCheck.OnEvent("Click", ToggleOnTop)

; Definition Mode Indicator (more visible)
DefModeIndicator := MainGui.Add("Text", "x80 y5 w160 h18 Center Border cGray", "Definition Mode OFF")

MousePosText := MainGui.Add("Text", "x250 y6 w80", "")
LiveCheck := MainGui.Add("CheckBox", "x335 y5", "Live")
LiveCheck.OnEvent("Click", (c,*) => SetTimer(UpdateMousePos, c.Value ? 100 : 0))

MainGui.Add("Button", "x400 y2 w50 h20 cRed", "ABORT").OnEvent("Click", AbortSequence)

; NOTE: "Calendar" (tab 12) was previously missing from this list while the
; calendar section below already called TabCtrl.UseTab(12) - which left that UI
; attached to a tab that did not exist, so it never rendered. Declaring it here
; restores it. "Tracking" (tab 13) is the behavior-tracking subsystem.
TabCtrl := MainGui.Add("Tab3", "x5 y28 w890 h730 vTabs", ["Workflow", "Patterns", "Live OCR", "Spools", "Analytics", "Clipboard", "Hotkeys", "Hotstrings", "Triggers", "Settings", "Notepad", "Calendar", "Tracking", "App Learner", "Snapshot Recovery", "Vision Scout", "Usage Predictor"])

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 1: WORKFLOW
; ═══════════════════════════════════════════════════════════════════════════════
; TAB 1: WORKFLOW
; =============================================================================

; -- tab contents (original TabCtrl.UseTab order) --
Tab_Workflow_Build()
Tab_Patterns_Build()
Tab_LiveOCR_Build()
Tab_Spools_Build()
Tab_Analytics_Build()
Tab_Clipboard_Build()
Tab_Hotkeys_Build()
Tab_Hotstrings_Build()
Tab_Triggers_Build()
Tab_Settings_Build()
Tab_Notepad_Build()

; ═══════════════════════════════════════════════════════════════════════════════
; STATUS BAR
; ═══════════════════════════════════════════════════════════════════════════════
; STATUS BAR
; =============================================================================
TabCtrl.UseTab(0)
StatusBar := MainGui.Add("StatusBar",, "Ready | CAPSLOCK = Definition Mode | Ctrl+Shift+G: Toggle")

; Calendar view

Tab_Calendar_Build()
Tab_Tracking_Build()
Tab_AppLearner_Build()
Tab_SnapshotRecovery_Build()
Tab_VisionScout_Build()
Tab_UsagePredictor_Build()
TabCtrl.UseTab(0)

; Initialize the workflow tab for the first action (button visibility, hints,
; choices and smart defaults) instead of waiting for the first user change.
try OnActionChange()
catch as err
    LogErrorToFile(err, "caught", "Workflow tab initial layout")

; Start maximised: the Snapshot Recovery and App Learner tabs carry wide
; tables that are far more usable with the whole screen behind them.
; Record every tab's designed geometry before the window is shown, so the
; reflow has a baseline to scale from. Snapshot Recovery lays itself out and
; is passed in as exempt.
try {
    ; Controls the hand-written GuiResize already repositions must be exempt,
    ; or they get moved twice and end up on top of one another.
    flowSkip := []
    ; Only the controls GuiResize REPOSITIONS need exempting. The ones it merely
    ; resizes (SeqLV, the status label, the group box) are fine to leave to the
    ; reflow - exempting those pinned the status label on top of its buttons.
    for , c in [SeqLoadBtn, SeqDeleteBtn, SeqRunBtn, SeqSimBtn
              , SeqImportBtn, SeqExportBtn, SeqMawWriterBtn] {
        try flowSkip.Push(c)
    }
    for , c in g_SnapRecCtl
        flowSkip.Push(c)
    AutoFlow_Init(MainGui, 0, 0, flowSkip)
    LogDiagnostic("AutoFlow captured " . AutoFlow_Report()
                . "  design base " . g_FlowBaseW . "x" . g_FlowBaseH, "AutoFlow", "INFO")
}
catch as err
    LogErrorToFile(err, "caught", "AutoFlow capture")

MainGui.Show("w1050 h820 Maximize")

; Show("...Maximize") applies the maximised state without raising a Size event,
; so the first reflow never sees the real window and every tab stays laid out
; for 1040px. Drive one pass explicitly from the actual client size.
; Deferred: immediately after Show the window has not finished maximising, so
; reading its client size then reports an intermediate value and the tabs are
; laid out for a window narrower than the one on screen.
SetTimer(AutoFlow_FirstPass, -250)

; ===============================================================================
; GLOBAL HOTKEYS
; ===============================================================================
SetTimer(UpdateDefinitionMode, 100)

; Definition mode keys (CAPSLOCK must be ON)
#HotIf GetKeyState("CapsLock", "T")
c::DefModeClick
d::DefModeDragStart
r::DefModeRightClick
t::DefModeTripleClick
p::DefModePattern
w::DefModeWait
k::DefModeSendKeys
m::DefModeMenuSelect
Escape::DefModeCancel
#HotIf

^+g:: {
    global g_GuiVisible, MainGui
    g_GuiVisible := !g_GuiVisible
    g_GuiVisible ? MainGui.Show() : MainGui.Hide()
}

^+p:: {
    global g_IsPaused
    g_IsPaused := !g_IsPaused
    ShowTooltipTimed(g_IsPaused ? "PAUSED" : "RESUMED", 1500)
}

^+x:: {
    global g_AbortSequence
    g_AbortSequence := true
    ShowTooltipTimed("ABORTING...", 1000)
}

^+c::ClearAllNotifications()  ; Ctrl+Shift+C = Clear all notifications

^+f::FindText().Gui("Show")

^+q::QuickOCRCapture()  ; Ctrl+Shift+Q = drag a box anywhere, OCR it, copy the text

; Ctrl+Shift+A = the attention panel: which windows actually held focus,
; watch time for media, ranked by measured prominence rather than by count.
^+a::Attn_OpenPanel()

; Ctrl+Shift+1 = snip the saved region, OCR it, confirm or correct the reading.
;               The first press (no region yet) just asks you to drag one.
; Ctrl+Shift+2 = view the last snip and every representation of it.
; Ctrl+Shift+3 = redraw the region.
^+1::Snip_Hotkey()
^+2::Snip_ViewLast()
^+3::Snip_PickRegion(false)
^+4::Snip_OpenSettings()   ; capture/flash/parsing toggles and roulette timing
^+5::Qa_OpenBank()         ; every parsed question, answered or not
^+6::Qa_AskNow()           ; pull one unanswered question right now
^+7::WinModel_OpenPanel()  ; window structure map for a learned app

; ═══════════════════════════════════════════════════════════════════════════════
; QUICK SCREEN OCR (Ctrl+Shift+Q)
; ═══════════════════════════════════════════════════════════════════════════════
; Press the hotkey anywhere, drag a box over any text on screen, and its text is
; recognised, copied to the clipboard and shown in a small result window.
;
; Independent of the Live OCR tab - it works with the main window hidden - but it
; reuses that tab's language/scale/grayscale settings when they are available.
; Spans every monitor (the overlay covers the virtual desktop, not just the
; primary screen).
; The Quick OCR functions themselves live in Tabs\Tab_03_LiveOCR.ahk.

; Clipboard Revolver hotkeys
^b::LoadRevolverFromSelection()   ; Copy + Parse + Load
^+b::FireAllShots()               ; Fire all shots (paste + Tab...)
; Smart Clipboard Revolver with Bins (NEW v4.1)
^!b::LoadRevolverItem(A_Clipboard)  ; Ctrl+Alt+B = Load to smart bins (shows selector)
^!+b::PasteFromBins()               ; Ctrl+Alt+Shift+B = Paste from bins (top bin first)

^!n::OpenNotepadPopup()  ; Ctrl+Alt+N = Open notepad popup
#b::ShowBinSelector("")  ; Ctrl+Alt+B = Open bin selector
^!i::ExecuteIdleMouse("0")  ; Ctrl+Alt+I = Idle mouse indefinitely

; ─── Tracking subsystem hotkeys ──────────────────────────────────────────────
^!t::Track_ToggleAllHotkey()   ; Ctrl+Alt+T = toggle all trackers on/off
^!+s::Snap_OpenViewer()        ; Ctrl+Alt+Shift+S = open the snapshot viewer
^!+c::Track_SnapNow()          ; Ctrl+Alt+Shift+C = capture a snapshot cycle now


try Snip_RestoreState()   ; resume the question roulette if it was left on
catch as err
    LogErrorToFile(err, "caught", "Snip roulette restore")

; ===============================================================================
; STARTUP SEQUENCE (runs once, in this exact order)
; ===============================================================================
InitDB()            ; Open/create SQLite DB, create tables, import legacy .ini data if needed
LoadAll()
LoadTaskbarIndex()  ; Load saved taskbar mapping (use Index Taskbar button to update)
LoadFieldOrder()    ; Load revolver field order
LoadSpools()        ; Load spool definitions
LoadWatchWords()    ; Load OCR watch words
InitializeRevolverBins()  ;← ADD THIS LINE
LoadPatterns()      ; Load saved patterns
RefreshCoordLV()
RefreshPatternLV()
RefreshSeqLV()
RefreshSpoolLV()    ; Populate spool list
RefreshWatchWordLV() ; Populate watch word list
RefreshRulesLV()
RefreshTaskbarLV()
RefreshFieldOrderLV()
UpdateRevolverDisplay()
UpdateTargetDD()
UpdateQualPatternDD()
UpdatePatternQualifierDD()  ; Populate qualifier dropdown
RefreshHKDropdowns()
UpdateHints()
PopulateChoices()
UpdateParamSuggestions()  ; Populate parameter suggestions
ToggleAdvancedStepFields()
ApplyActionFieldLayout()
UpdateActionHelp()
ApplyHotkeys()
RestoreSpoolMasterState() ; Restore persisted master switch and auto-start enabled Spools
RefreshHotstringList()  ; V5.0: Populate hotstring list
RefreshTriggersLV()  ; V5.1: Populate triggers list
; Tracking subsystem: resume trackers that were running at last shutdown and
; cache element names for the workflow dropdowns. Never block startup.
try Track_AutoStart()
catch as err
    LogErrorToFile(err, "caught", "Tracking auto-start")
; Vision Scout (v9): resume the learner if it was running at last shutdown.
try VisionScout_AutoStart()
catch as err
    LogErrorToFile(err, "caught", "Vision Scout auto-start")
try UpdateElementActionChoices()
catch as err
    LogErrorToFile(err, "caught", "Tracking element name cache")
; The second local learner has an independent model and database schema. Its
; acceptance shortcut is Win+Shift+CapsLock so Vision Scout can keep Win+CapsLock.
try UsagePredictor_Init()
catch as err
    LogErrorToFile(err, "caught", "Usage Predictor initialization")

StatusBar.SetText("Ready | CAPSLOCK=Definition Mode | Ctrl+B=Load | Ctrl+Shift+B=Fire | ESC=Abort")


; ═══════════════════════════════════════════════════════════════════════════════
; V5.0: INITIALIZE INSTRUCTIONS FILE

InitializeInstructions()


; ═══════════════════════════════════════════════════════════════════════════════
; V5.0: ENHANCED NOTIFICATION SYSTEM

; -- end of the auto-execute section; everything else is function definitions --
