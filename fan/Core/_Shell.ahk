; Entry lifecycle: shell. Included by MacroAutomator.ahk.
; ===============================================================================
; MAIN GUI - window shell, toolbar and the tab control itself
; ===============================================================================
MainGui := Gui("+Resize +MinSize900x820", "Macro Automator - task workspace")
MainGui.SetFont("s9", "Segoe UI")
SecondaryWindows_Start()
g_DeepActivityPlacement := SecondaryWindows_ShowAt
A_TrayMenu.Add("Learning Workbench", LearningWorkbench_Open)
A_TrayMenu.Add("Stored evidence / lessons", LearningLab_Open)
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

MainGui.Add("Button", "x400 y2 w50 h20 cRed", "ABORT").OnEvent("Click", (*) => (AbortSequence(), StudyLive_Abort(), DeepBridge_Cancel()))

; NOTE: "Calendar" (tab 12) was previously missing from this list while the
; calendar section below already called TabCtrl.UseTab(12) - which left that UI
; attached to a tab that did not exist, so it never rendered. Declaring it here
; restores it. "Tracking" (tab 13) is the behavior-tracking subsystem.
TabCtrl := MainGui.Add("Tab3", "-Wrap +0x500 x5 y28 w890 h730 vTabs", ["Workflow", "Patterns", "Live OCR", "Spools", "Analytics", "Clipboard", "Hotkeys", "Hotstrings", "Triggers", "Settings", "Notepad", "Calendar", "Tracking", "Learning", "Snapshot Recovery", "Vision Scout", "Usage Predictor", "Study Assistant", "Live Portal", "DeepSeek Bridge", "Media Intel", "Knowledge", "Scribe", "Start here", "Chrome Learning", "Routine finder", "Describe it", "Portals", "Reliability", "Knowledge base", "Document inbox", "Record & SOP"])
SendMessage(0x1329, 0, 0x10001, TabCtrl)

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
Tab_StudyAssistant_Build()
Tab_PortalAssist_Build()
Tab_DeepSeekBridge_Build()
Tab_MediaIntel_Build()
Tab_Knowledge_Build()
Tab_Scribe_Build()
ChromeLearning_Build()
; Autopilot (26-29, 32) and the knowledge base (30-31). Each builder is isolated
; so a failure in one page never prevents the main window from opening.
try AutopilotUI_Build()
catch as err
    LogErrorToFile(err, "caught", "Autopilot pages")
try KB_BuildPages()
catch as err
    LogErrorToFile(err, "caught", "Knowledge base pages")
try Recorder_BuildPage()
catch as err
    LogErrorToFile(err, "caught", "Record & SOP page")
FanHome_Build()
FanNav_Init()
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
    flowSkip := g_FanNav["controls"].Clone()
    for ctl in g_LearnHub["controls"]
        flowSkip.Push(ctl)
    for ctl in g_ChromeLearn["controls"]
        flowSkip.Push(ctl)
    ; Only the controls GuiResize REPOSITIONS need exempting. The ones it merely
    ; resizes (SeqLV, the status label, the group box) are fine to leave to the
    ; reflow - exempting those pinned the status label on top of its buttons.
    for , c in [SeqLoadBtn, SeqDeleteBtn, SeqRunBtn, SeqSimBtn
              , SeqImportBtn, SeqExportBtn, SeqMawWriterBtn] {
        try flowSkip.Push(c)
    }
    for , c in g_SnapRecCtl
        flowSkip.Push(c)
    for , c in g_DeepBridge.Get("controls", [])
        flowSkip.Push(c)
    AutoFlow_Init(MainGui, 0, 0, flowSkip)
    LogDiagnostic("AutoFlow captured " . AutoFlow_Report()
                . "  design base " . g_FlowBaseW . "x" . g_FlowBaseH, "AutoFlow", "INFO")
}
catch as err
    LogErrorToFile(err, "caught", "AutoFlow capture")

; A service reload during an automation run should not cover the user's Chrome.
; Normal launches retain the existing maximized UI; /background keeps it hidden.
if A_Args.Length && A_Args[1] = "/background" {
    MainGui.Show("w1050 h820 Hide")
    g_GuiVisible := false
} else
    MainGui.Show("w1050 h820 Maximize")
if A_Args.Length && (A_Args[1] = "/bridge" || A_Args[1] = "--live-workbench" || A_Args[1] = "--learning-workbench")
    TabCtrl.Choose(20)
if A_Args.Length && A_Args[1] = "/settings"
    TabCtrl.Choose(10)

; Show("...Maximize") applies the maximised state without raising a Size event,
; so the first reflow never sees the real window and every tab stays laid out
; for 1040px. Drive one pass explicitly from the actual client size.
; Deferred: immediately after Show the window has not finished maximising, so
; reading its client size then reports an intermediate value and the tabs are
; laid out for a window narrower than the one on screen.
SetTimer(AutoFlow_FirstPass, -250)

