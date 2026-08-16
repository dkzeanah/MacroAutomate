; ═══════════════════════════════════════════════════════════════════════════════
; █▀▄▀█ ▄▀█ █▀▀ █▀█ █▀█   ▄▀█ █ █ ▀█▀ █▀█ █▀▄▀█ ▄▀█ ▀█▀ █▀█ █▀█
; █ ▀ █ █▀█ █▄▄ █▀▄ █▄█   █▀█ █▄█  █  █▄█ █ ▀ █ █▀█  █  █▄█ █▀▄
; ═══════════════════════════════════════════════════════════════════════════════
; VERSION: 7.0 MERGED EDITION
; Stable v6.1 COMPLETE base plus the usable v6.9 workflow, scheduler,
; patient-management, template, and .maw exchange features.
; v2.9.6 → v4.0 → v5.0 | LINES: 12,000+ | FUNCTIONS: 380+
; ═══════════════════════════════════════════════════════════════════════════════
;
; V5.0 ENHANCEMENTS:
; ├─ Advanced notification system with error details & parameter examples
; ├─ Time-based notification scheduling (9AM-6AM, 5-min increments)
; ├─ Comprehensive instructions.txt for all action types with examples
; ├─ Fixed hotkey assignment GUI for saved sequences
; ├─ New Hotstring Management tab with full configuration options
; ├─ Enhanced OCR/Image error reporting with specific failure reasons
; ├─ Real-time parameterization examples in workflow notifications
; ├─ Robust error handling with actionable user feedback
; └─ ALL v4.0 features preserved + new enhancements (ZERO loss)
;
; KEYBOARD MODIFIERS:
; ^ = Ctrl  | + = Shift | ! = Alt | # = Win
; ═══════════════════════════════════════════════════════════════════════════════

#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, StdOut  ; Never block startup with warning popups; logged launcher captures stdout.

; Configure coordinate systems for consistent screen-relative positioning
SetWorkingDir(A_ScriptDir)  ; Set working directory to script location
CoordMode("Mouse", "Screen") ; Mouse coordinates relative to screen
CoordMode("Pixel", "Screen") ; Pixel coordinates relative to screen
CoordMode("ToolTip", "Screen") ; Tooltip positioning relative to screen

; ═══════════════════════════════════════════════════════════════════════════════
; EXTERNAL LIBRARY INCLUDES
; ═══════════════════════════════════════════════════════════════════════════════
; FindText.ahk: Visual pattern recognition for UI element detection
; OCR.ahk: Optical Character Recognition for text extraction from screen
; ═══════════════════════════════════════════════════════════════════════════════

#Include FindText.ahk
#Include OCR.ahk  ; Windows.Media.Ocr wrapper used by all OCR actions
#Include SQLiteDB.ahk



; ═══════════════════════════════════════════════════════════════════════════════
; MACRO AUTOMATOR V2.9.6 - AUTOHOTKEY V2
; ═══════════════════════════════════════════════════════════════════════════════
; MACRO AUTOMATOR v2.9.6 - AutoHotkey v2

; ═══════════════════════════════════════════════════════════════════════════════
; V2.9.6: STANDARDIZED VISUAL OVERLAY + WATCH WORDS
; ═══════════════════════════════════════════════════════════════════════════════
; v2.9.6: STANDARDIZED VISUAL OVERLAY + WATCH WORDS
; - Unified visual overlay system for all highlights/markers/regions
; - Watch Words: Define dynamic text regions that update automatically
; - OCR words clickable, usable as variables in workflows
; - Pattern test highlighting uses standardized overlays
; - Fixed OCR word highlighting with proper border boxes
; Modifiers: ^ = Ctrl, + = Shift, ! = Alt, # = Win

#Requires AutoHotkey v2.0
#SingleInstance Force

SetWorkingDir(A_ScriptDir)
CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")


; ═══════════════════════════════════════════════════════════════════════════════
; INCLUDE FINDTEXT AND OCR LIBRARIES
; ═══════════════════════════════════════════════════════════════════════════════
; INCLUDE FINDTEXT AND OCR LIBRARIES
; =============================================================================

#Include FindText.ahk


; ═══════════════════════════════════════════════════════════════════════════════
; GLOBALS
; ═══════════════════════════════════════════════════════════════════════════════
; GLOBALS
; =============================================================================
global g_TaskPresets := Map()


global g_AppointmentTypes := Map()


global g_Patients := Map()
global g_NextPatientID := 1

global g_Coordinates := Map()
    ; g_Coordinates: Key-value storage map
global g_Sequences := Map()
    ; g_Sequences: Key-value storage map
global g_WorkflowAutoSavePending := false
global g_LastWorkflowSaveError := ""
global g_LoadingWorkflow := false
global g_ExtractedData := Map()
    ; g_ExtractedData: Key-value storage map
global g_HotkeyBindings := Map()
    ; g_HotkeyBindings: Key-value storage map
global g_Settings := Map()
    ; g_Settings: Key-value storage map
global g_ExtractionRules := []
    ; g_ExtractionRules: Array/list storage
global g_Patterns := Map()
    ; g_Patterns: Key-value storage map

global g_IsCapturing := false
    ; g_IsCapturing: Boolean flag for state tracking
global g_IsPaused := false
    ; g_IsPaused: Boolean flag for state tracking
global g_DragMode := false
    ; g_DragMode: Boolean flag for state tracking
global g_DragStartX := 0, g_DragStartY := 0
global g_IsRecording := false
    ; g_IsRecording: Boolean flag for state tracking
global g_RecordedActions := []
    ; g_RecordedActions: Array/list storage
global g_IsCalibrating := false
    ; g_IsCalibrating: Boolean flag for state tracking
global g_CurrentSequenceSteps := []
    ; g_CurrentSequenceSteps: Array/list storage
global g_CurrentSequenceSpeed := 1.0  ; Speed multiplier (1.0 = normal)
global g_WorkflowVariables := Map()   ; Variables created during a workflow run
global g_SkipNextAction := false      ; Set by one-step conditional actions
global g_SequenceCallStack := []      ; Prevent recursive Run Sequence loops
global g_CoordManagerGui := 0
global g_CoordManagerNameEdit := 0
global g_SimulationTooltipIndex := 1  ; For stacking tooltips (1-20)
global g_AbortSequence := false
    ; g_AbortSequence: Boolean flag for state tracking

global g_GuiVisible := true
    ; g_GuiVisible: Boolean flag for state tracking
global g_AlwaysOnTop := false
    ; g_AlwaysOnTop: Boolean flag for state tracking
global g_ClickThrough := false
    ; g_ClickThrough: Boolean flag for state tracking
global g_Transparency := 255
global g_ActionCounter := 0
global g_TotalActions := 0
global g_PointCounter := 1
global g_DragCounter := 1
global g_RelCounter := 1
global g_LastClickX := 0, g_LastClickY := 0

; v2.9 globals
global g_DefinitionMode := false
    ; g_DefinitionMode: Boolean flag for state tracking
global g_FullRecording := false
    ; g_FullRecording: Boolean flag for state tracking
global g_FullRecordLog := []
    ; g_FullRecordLog: Array/list storage
global g_Analytics := Map()
    ; g_Analytics: Key-value storage map
global g_WindowHotspots := Map()
    ; g_WindowHotspots: Key-value storage map
global g_ActionFrequency := Map()
    ; g_ActionFrequency: Key-value storage map
global g_DefModeStartX := 0
global g_DefModeStartY := 0
global g_DefModeDragging := false
    ; g_DefModeDragging: Boolean flag for state tracking

; v2.9.1 NEW: Taskbar apps indexed
global g_TaskbarApps := []
    ; g_TaskbarApps: Array/list storage

; v2.9.1 NEW: Clipboard Revolver
global g_RevolverLoaded := false
    ; g_RevolverLoaded: Boolean flag for state tracking
global g_RevolverChamber := []      ; Array of field values in paste order
    ; g_RevolverChamber: Array/list storage
global g_RevolverPosition := 1      ; Current chamber position
global g_RevolverFieldOrder := []   ; Configurable field order
    ; g_RevolverFieldOrder: Array/list storage
global g_RevolverActive := false    ; Is revolver mode active (intercept Ctrl+V)
    ; g_RevolverActive: Boolean flag for state tracking

; v2.9.2 NEW: Spool System (Event-Driven Automation)
global g_Spools := Map()            ; All defined spools
    ; g_Spools: Key-value storage map
global g_ActiveSpools := Map()      ; Currently running spool timers
    ; g_ActiveSpools: Key-value storage map
global g_SpoolMasterEnabled := false ; Master on/off switch
    ; g_SpoolMasterEnabled: Boolean flag for state tracking
global g_SpoolVariables := Map()    ; OCR-extracted variables
    ; g_SpoolVariables: Key-value storage map
global g_SpoolNotifications := []   ; Active notification windows
    ; g_SpoolNotifications: Array/list storage
global g_SpoolLog := []             ; Activity log entries
    ; g_SpoolLog: Array/list storage
global g_SpoolRegions := Map()      ; Custom monitor regions
    ; g_SpoolRegions: Key-value storage map
global g_NotificationCounter := 0   ; Unique notification IDs
global g_SpoolCooldown := Map()     ; Cooldown timestamps per spool
    ; g_SpoolCooldown: Key-value storage map
global g_NotificationDefaults := Map(
    "timeout", 5,                   ; Default auto-dismiss seconds
    "pauseSpools", true,            ; Pause spools while notification showing
    "stackDirection", "up"          ; Stack direction: up or down
)

; v2.9.3 NEW: OCR Integration
global g_OCRLog := []               ; Live OCR recording log
    ; g_OCRLog: Array/list storage
global g_OCRRecording := false      ; Is live OCR recording active
    ; g_OCRRecording: Boolean flag for state tracking
global g_OCRSettings := Map(
    "language", "en-us",
    "scale", 1.0,
    "grayscale", false,
    "interval", 500                 ; Live OCR refresh rate
)
global g_OCRHighlight := ""  ; Persistent OCR region highlight overlay

; v2.9.6 NEW: Visual Overlay System (standardized highlights, markers, regions)
global g_Overlays := Map()          ; Active overlay GUIs by ID
    ; g_Overlays: Key-value storage map
global g_OverlayCounter := 0        ; Unique overlay IDs
global g_OCRYellowOverlayIds := []  ; Yellow OCR word boxes from the most recent capture
global g_OverlayStyles := Map(
    "highlight", Map("color", "FF0000", "thickness", 3, "fill", false),
    "selection", Map("color", "00FF00", "thickness", 2, "fill", true, "fillAlpha", 80),
    "match", Map("color", "FFFF00", "thickness", 2, "fill", false),
    "error", Map("color", "FF0000", "thickness", 4, "fill", false),
    "info", Map("color", "00AAFF", "thickness", 2, "fill", false),
    "word", Map("color", "00FF00", "thickness", 2, "fill", false),
    "ocrYellow", Map("color", "FFFF00", "thickness", 3, "fill", false),
    "pattern", Map("color", "FF00FF", "thickness", 3, "fill", false)
)

; v2.9.6 NEW: OCR Word Tracking (dynamic text capture for automations)
global g_WatchWords := Map()        ; Words being monitored: name -> {pattern, region, lastValue, lastCoords}
    ; g_WatchWords: Key-value storage map
global g_DetectedWords := []        ; Current OCR detection results with coords
    ; g_DetectedWords: Array/list storage
global g_WordVariables := Map()     ; Extracted word values: $word.PatientName, etc.
    ; g_WordVariables: Key-value storage map

; v2.9.6 NEW: OCR Revolver (split captured text into paste-able parts)
global g_OCRRevolver := []          ; Array of text parts to paste
    ; g_OCRRevolver: Array/list storage
global g_OCRRevolverIndex := 0      ; Current position in revolver (0-based)
global g_LastOCRText := ""          ; Last captured OCR text (for re-use)
global g_LastOCRRegion := Map()     ; Last OCR region coords
    ; g_LastOCRRegion: Key-value storage map

global DATA_DIR := A_ScriptDir . "\data"
global LOG_DIR := A_ScriptDir . "\logs"
global ERROR_LOG_FILE := LOG_DIR . "\MacroAutomator_errors.log"
global COORDS_FILE := DATA_DIR . "\coordinates.csv"
global SEQUENCES_FILE := DATA_DIR . "\sequences.ini"
global HOTKEYS_FILE := DATA_DIR . "\hotkeys.ini"
global SETTINGS_FILE := DATA_DIR . "\settings.ini"
global RULES_FILE := DATA_DIR . "\extraction_rules.csv"
global PATTERNS_FILE := DATA_DIR . "\patterns.ini"
global SPOOLS_FILE := DATA_DIR . "\spools.ini"
global OCR_LOG_FILE := DATA_DIR . "\ocr_log.txt"
global OCR_WORDS_FILE := DATA_DIR . "\ocr_words.ini"
global DB_FILE := DATA_DIR . "\macroauto.sqlite"
global g_DB := 0
global ANALYTICS_FILE := DATA_DIR . "\analytics.ini"
global RECORDING_FILE := DATA_DIR . "\recording.csv"
global PREVIEW_DIR := DATA_DIR . "\previews"
global SCREENSHOTS_DIR := DATA_DIR . "\screenshots"

; GDI+ token for screenshot capture
global g_GdipToken := 0


; v4.1 NEW: Notepad System
global g_NotepadPopupGui := 0          ; Popup notepad window reference
global g_NotepadContent := ""          ; Current notepad content
global NOTES_DIR := DATA_DIR . "\notes"  ; Notes storage directory

; v4.1 NEW: Enhanced Notification System
global g_NotificationSnoozeTimers := Map()  ; Notification ID -> snooze sequence
global g_NotificationData := Map()          ; Notification ID -> {message, time, snoozeTimes}

; v4.1 NEW: Smart Clipboard Revolver with Bins
global g_RevolverBins := Map()         ; Bin name -> {items: [], formatRules: [], notifyBlock: true}
global g_RevolverCurrentBin := ""      ; Current active bin for pasting
global g_RevolverBinOrder := []        ; Order to process bins (top bin first)
global g_RevolverBinSelector := 0     ; Bin selection GUI reference
global g_RevolverBinNotifications := Map()  ; Bin -> notification GUI for visual feedback

; v4.1 NEW: Mouse Idle System
global g_MouseIdleTimer := 0           ; Timer for mouse idle monitoring
global g_MouseIdleActive := false      ; Is idle mode active?
global g_MouseIdleDuration := 0        ; How long to idle (0 = indefinite)
global g_MouseLastX := 0               ; Last known mouse X position
global g_MouseLastY := 0               ; Last known mouse Y position
global g_MouseHarshThreshold := 50     ; Pixels of movement to consider "harsh"

; V5.0 NEW: Enhanced Notification System
global g_NotificationSchedule := Map()  ; Time-based notification schedules
global g_NotificationHistory := []      ; History of all notifications
global g_NotificationSettings := Map(
    "startTime", "09:00",
    "endTime", "18:00",
    "blockSize", 5,
    "showErrors", true,
    "showParams", true,
    "showInstructions", true
)

; V5.0 NEW: Hotstring Management
global g_Hotstrings := Map()            ; All defined hotstrings
global g_HotstringActive := true        ; Master on/off
global g_HotstringOptions := Map(
    "caseSensitive", false,
    "endChars", " `t",
    "reset", false,
    "autoBackspace", true
)

; V5.0 NEW: Action Error Tracking
global g_ActionErrors := Map()          ; Track errors per action type
global g_LastActionError := ""          ; Most recent error details

; V5.0 NEW: Additional file paths
global INSTRUCTIONS_FILE := A_ScriptDir . "\MacroAutomator_v7_Feature_Guide.txt"
global HOTSTRINGS_FILE := DATA_DIR . "\hotstrings.txt"
global SCHEDULE_FILE := DATA_DIR . "\notification_schedule.txt"

; V5.2 NEW: Stackable Notification System
global g_NotificationStack := []        ; Array of active notification GUIs
global g_NotificationY := 0             ; Current Y position for next notification
global g_DebugMode := true              ; Show step-by-step execution notifications
global g_NotificationDismissible := true ; Notifications stay until dismissed
global g_NotificationTimeout := 0       ; 0 = never auto-dismiss

; V5.3 NEW: Step-Through Execution Mode
global g_StepThroughMode := false       ; Pause after each step
global g_StepThroughWaiting := false    ; Currently waiting for Tab key
global g_StepThroughContinue := false   ; Tab was pressed, continue to next step

; V5.3 NEW: Sequence Hotkey/Hotstring Support
global g_SequenceHotkeys := Map()      ; Map of hotkey -> sequence name
global g_SequenceHotstrings := Map()   ; Map of hotstring -> sequence name
global g_RegisteredHotkeys := []       ; Track registered hotkeys for cleanup
global g_RegisteredHotstrings := []    ; Track registered hotstrings for cleanup

; V5.1 NEW: Parameter Validation System
global g_ParamValidators := Map()      ; Validators per action type
global g_ParamHints := Map()           ; Live hints for parameters
global g_ValidationErrors := []        ; Validation error log

; V5.1 NEW: Action Templates Library
global g_ActionTemplates := Map()      ; Pre-built workflow templates
global TEMPLATES_FILE := DATA_DIR . "\templates.json"

; V5.1 NEW: Advanced Notification Manager
global g_NotificationTriggers := Map() ; All notification triggers
global g_TriggerMonitorTimer := ""     ; Timer function for trigger monitoring
global g_TriggerActions := Map()       ; Actions to execute per trigger
global g_TriggerConditions := Map()   ; Conditions for triggers
global g_TriggerLog := []              ; Trigger execution history
global g_ActiveMonitors := Map()       ; Active monitoring tasks
global TRIGGERS_FILE := DATA_DIR . "\notification_triggers.json"

global g_Screenshots := Map()

; Counter for generating unique IDs
global g_NextScreenshotID := 1

; Current selection (which screenshot is selected in GUI)
global g_SelectedScreenshotID := 0

; User settings for this tab
global g_ScreenshotSettings := Map(
    "SaveFolder", A_ScriptDir "\Screenshots",
    "Format", "PNG",
    "AutoSave", true,
    "ShowPreview", true
)
global g_Appointments := Map()
global g_CalendarDate := FormatTime(, "yyyyMMdd")
global g_CalendarSlotButtons := Map()

g_Settings := Map(
    "ClickDelay", 100,
    "TypeDelay", 50,
    "ActionDelay", 150,
    "DefaultDragTime", 300,
    "DateFormat", "MM/dd/yyyy",
    "ShowActionTooltips", true,
    "TooltipDuration", 1500,
    "MarkerOffsetX", -12,
    "MarkerOffsetY", -15,
    "MaxRetries", 3,
    "VerifyTimeout", 2000,
    "VerifyInterval", 100,
    "PreActionDelay", 50,
    "PostActionDelay", 100,
    "WindowActivateTimeout", 3000,
    "FindTextTolerance", 0.1,
    "FindTextTimeout", 5000,
    "AutoCapturePattern", true,
    "FailsafeCheckCloseButton", true,
    "DefinitionModeAutoPattern", true,
    "PreviewTooltipDuration", 3000
)

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


; Initialize GDI+ for screenshot capture
OnError(LogUnhandledError)
g_GdipToken := Gdip_Startup()
OnExit(ShutdownGdip)
OnExit(SaveAllOnExit)


; ═══════════════════════════════════════════════════════════════════════════════
; HELPERS
; ═══════════════════════════════════════════════════════════════════════════════
; HELPERS
; =============================================================================

MsgBoxTop(text, title := "", options := "") {
    return MsgBox(text, title, options . " 262144")
}

InputBoxTop(prompt, title := "", default := "") {
    global MainGui
    inputGui := Gui("+AlwaysOnTop +Owner" . MainGui.Hwnd, title)
    inputGui.SetFont("s9", "Segoe UI")
    inputGui.Add("Text",, prompt)
    inputEdit := inputGui.Add("Edit", "w300", default)
    resultValue := ""
    resultOK := false
    inputGui.Add("Button", "x100 y+10 w80 Default", "OK").OnEvent("Click", (*) => (resultValue := inputEdit.Value, resultOK := true, inputGui.Hide()))
    inputGui.Add("Button", "x+10 w80", "Cancel").OnEvent("Click", (*) => inputGui.Hide())
    inputGui.Show()
    WinWaitClose(inputGui)
    inputGui.Destroy()
    return Map("Result", resultOK ? "OK" : "Cancel", "Value", resultValue)
}

; Write runtime exceptions and caught operation errors to one shareable log.
LogErrorToFile(thrown, mode := "", context := "") {
    global ERROR_LOG_FILE
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    entry := "`r`n============================================================`r`n"
    entry .= "Time: " . timestamp . "`r`n"
    if context != ""
        entry .= "Context: " . context . "`r`n"
    if mode != ""
        entry .= "Mode: " . mode . "`r`n"

    if IsObject(thrown) {
        try entry .= "Message: " . thrown.Message . "`r`n"
        try entry .= "What: " . thrown.What . "`r`n"
        try entry .= "Extra: " . thrown.Extra . "`r`n"
        try entry .= "File: " . thrown.File . "`r`n"
        try entry .= "Line: " . thrown.Line . "`r`n"
        try entry .= "Stack:`r`n" . thrown.Stack . "`r`n"
    } else {
        entry .= "Message: " . String(thrown) . "`r`n"
    }

    try FileAppend(entry, ERROR_LOG_FILE, "UTF-8")
    return entry
}

LogDiagnostic(message, context := "", level := "ERROR") {
    return LogErrorToFile(message, level, context)
}

LogUnhandledError(thrown, mode) {
    global ERROR_LOG_FILE
    LogErrorToFile(thrown, mode, "Unhandled AutoHotkey runtime error")
    try ShowNotificationBasic("Macro Automator Error",
        "The error was written to:`n" . ERROR_LOG_FILE . "`n`nUse Open Error Log to review or share it.",
        0, "error")
    return true
}

OpenErrorLog(*) {
    global ERROR_LOG_FILE
    if !FileExist(ERROR_LOG_FILE)
        FileAppend("Macro Automator runtime error log`r`nCreated: " . FormatTime(, "yyyy-MM-dd HH:mm:ss") . "`r`n", ERROR_LOG_FILE, "UTF-8")
    Run('notepad.exe "' . ERROR_LOG_FILE . '"')
}

GenerateCoordName(type := "Point") {
    global g_Coordinates, g_PointCounter, g_DragCounter, g_RelCounter
    if type = "Drag" {
        while g_Coordinates.Has("Drag_" . g_DragCounter)
            g_DragCounter++
        return "Drag_" . g_DragCounter++
    }
    if type = "Relative" {
        while g_Coordinates.Has("Rel_" . g_RelCounter)
            g_RelCounter++
        return "Rel_" . g_RelCounter++
    }
    while g_Coordinates.Has("Point_" . g_PointCounter)
        g_PointCounter++
    return "Point_" . g_PointCounter++
}

; Standardized tooltip with configurable duration
ShowTooltipTimed(text, duration := 0, x := "", y := "") {
    global g_Settings
    if duration = 0
        duration := g_Settings["TooltipDuration"]
    if x != "" && y != ""
        ToolTip(text, x, y)
    else
        ToolTip(text)
    SetTimer(() => ToolTip(), -duration)
}

; Get window under mouse
GetWindowUnderMouse() {
    MouseGetPos(,, &hwnd)
    if !hwnd
        return Map("title", "", "class", "", "exe", "", "hwnd", 0)
    title := ""
    class := ""
    exe := ""
    try title := WinGetTitle(hwnd)
    try class := WinGetClass(hwnd)
    try exe := WinGetProcessName(hwnd)
    return Map("title", title, "class", class, "exe", exe, "hwnd", hwnd)
}

; Check if position is near a window close button
IsNearCloseButton(x, y, tolerance := 50) {
    ; Skip check if in taskbar area (bottom of screen)
    taskbarHeight := 48  ; Standard Windows 11 taskbar height
    if y > A_ScreenHeight - taskbarHeight
        return false  ; Taskbar doesn't have close buttons

    ; Skip check if near edges (likely system UI, not window close buttons)
    if x < 100 || y < 50
        return false

    try {
        hwnd := DllCall("WindowFromPoint", "Int64", (y << 32) | (x & 0xFFFFFFFF), "Ptr")
        if !hwnd
            return false

        ; Get window info
        WinGetPos(&wx, &wy, &ww, &wh, hwnd)

        ; Skip if this looks like taskbar or system window
        winClass := WinGetClass(hwnd)
        if InStr(winClass, "Shell_") || InStr(winClass, "Taskbar") || InStr(winClass, "Tray")
            return false

        ; Check if near top-right close button area (typical X button location)
        closeX := wx + ww - 25
        closeY := wy + 15

        ; Only flag if BOTH x and y are close to the close button
        if Abs(x - closeX) < tolerance && Abs(y - closeY) < tolerance
            return true
    }
    return false
}


; ═══════════════════════════════════════════════════════════════════════════════
; TASKBAR INDEXING (WIN+1, WIN+2, ETC.)
; ═══════════════════════════════════════════════════════════════════════════════
; TASKBAR INDEXING (Win+1, Win+2, etc.)

; ═══════════════════════════════════════════════════════════════════════════════
; THIS MANUALLY INDEXES BY PRESSING WIN+1 THROUGH WIN+0 AND CAPTURING RESULTS
; ═══════════════════════════════════════════════════════════════════════════════
; This MANUALLY indexes by pressing Win+1 through Win+0 and capturing results
; Must be triggered by user since it will activate windows

global TASKBAR_FILE := DATA_DIR . "\taskbar.ini"

IndexTaskbarManual() {
    global g_TaskbarApps, MainGui, TASKBAR_FILE

    ; Confirm with user - this will cycle through apps
    result := MsgBoxTop(
        "This will index your taskbar by pressing Win+1 through Win+0.`n`n" .
        "Each pinned app will be activated briefly.`n`n" .
        "Make sure your taskbar is visible and ready.`n`n" .
        "Continue?",
        "Index Taskbar Apps",
        "YesNo"
    )
    if result != "Yes"
        return

    ; Minimize our GUI temporarily
    MainGui.Hide()
    Sleep(500)

    g_TaskbarApps := []

    ; Remember current active window to restore later
    originalHwnd := WinExist("A")

    ; Cycle through Win+1 to Win+0 (0 = 10th position)
    Loop 10 {
        keyNum := A_Index = 10 ? "0" : String(A_Index)

        ShowTooltipTimed("Indexing Win+" . keyNum . "...", 800)

        ; Send the Windows hotkey
        Send("#" . keyNum)
        Sleep(400)  ; Wait for window to activate

        ; Capture what's now active
        activeHwnd := 0
        activeTitle := ""
        activeExe := ""
        activeClass := ""

        try {
            activeHwnd := WinExist("A")
            activeTitle := WinGetTitle(activeHwnd)
            activeExe := WinGetProcessName(activeHwnd)
            activeClass := WinGetClass(activeHwnd)
        }

        ; Check if something actually activated (not desktop, not our app)
        if activeTitle != "" && activeTitle != "Program Manager" && activeExe != "AutoHotkey64.exe" && activeExe != "AutoHotkey32.exe" && activeExe != "AutoHotkey.exe" {
            g_TaskbarApps.Push(Map(
                "position", A_Index,
                "hotkey", "#" . keyNum,
                "hotkeyDisplay", "Win+" . keyNum,
                "hwnd", activeHwnd,
                "title", activeTitle,
                "exe", activeExe,
                "class", activeClass
            ))
        } else {
            ; No app at this position, or it's empty
            g_TaskbarApps.Push(Map(
                "position", A_Index,
                "hotkey", "#" . keyNum,
                "hotkeyDisplay", "Win+" . keyNum,
                "hwnd", 0,
                "title", "(empty)",
                "exe", "",
                "class", ""
            ))
        }

        Sleep(200)
    }

    ; Restore original window
    if originalHwnd
        try WinActivate(originalHwnd)

    Sleep(300)
    MainGui.Show()

    ; Save to file
    SaveTaskbarIndex()

    ; Refresh display
    RefreshTaskbarLV()

    ; Count valid entries
    validCount := 0
    for app in g_TaskbarApps
        if app["exe"] != ""
            validCount++

    ShowStatus("Indexed " . validCount . " taskbar apps", "ok")
    MsgBoxTop("Indexed " . validCount . " taskbar applications.`n`nThese are now available in Activate Window choices.", "Indexing Complete")
}

SaveTaskbarIndex() {
    global g_TaskbarApps, TASKBAR_FILE
    try {
        if FileExist(TASKBAR_FILE)
            FileDelete(TASKBAR_FILE)

        for i, app in g_TaskbarApps {
            IniWrite(app["position"], TASKBAR_FILE, "App" . i, "Position")
            IniWrite(app["hotkey"], TASKBAR_FILE, "App" . i, "Hotkey")
            IniWrite(app["hotkeyDisplay"], TASKBAR_FILE, "App" . i, "HotkeyDisplay")
            IniWrite(app["title"], TASKBAR_FILE, "App" . i, "Title")
            IniWrite(app["exe"], TASKBAR_FILE, "App" . i, "Exe")
            IniWrite(app["class"], TASKBAR_FILE, "App" . i, "Class")
        }
        IniWrite(g_TaskbarApps.Length, TASKBAR_FILE, "Meta", "Count")
    }
}

LoadTaskbarIndex() {
    global g_TaskbarApps, TASKBAR_FILE
    g_TaskbarApps := []

    if !FileExist(TASKBAR_FILE)
        return

    count := IniRead(TASKBAR_FILE, "Meta", "Count", 0)

    Loop count {
        pos := IniRead(TASKBAR_FILE, "App" . A_Index, "Position", A_Index)
        hotkey := IniRead(TASKBAR_FILE, "App" . A_Index, "Hotkey", "")
        hotkeyDisplay := IniRead(TASKBAR_FILE, "App" . A_Index, "HotkeyDisplay", "")
        title := IniRead(TASKBAR_FILE, "App" . A_Index, "Title", "")
        exe := IniRead(TASKBAR_FILE, "App" . A_Index, "Exe", "")
        class := IniRead(TASKBAR_FILE, "App" . A_Index, "Class", "")

        g_TaskbarApps.Push(Map(
            "position", pos,
            "hotkey", hotkey,
            "hotkeyDisplay", hotkeyDisplay,
            "hwnd", 0,  ; hwnd won't persist across sessions
            "title", title,
            "exe", exe,
            "class", class
        ))
    }
}

; Get taskbar apps as choices for Activate Window
GetTaskbarChoices() {
    global g_TaskbarApps
    choices := []
    for app in g_TaskbarApps {
        if app["exe"] = ""  ; Skip empty slots
            continue
        shortTitle := StrLen(app["title"]) > 30 ? SubStr(app["title"], 1, 27) . "..." : app["title"]
        choices.Push(app["hotkeyDisplay"] . ": " . shortTitle . "  [" . app["exe"] . "]")
    }
    return choices
}


; ═══════════════════════════════════════════════════════════════════════════════
; STATUS DISPLAY (STANDARDIZED)
; ═══════════════════════════════════════════════════════════════════════════════
; STATUS DISPLAY (Standardized)
; =============================================================================

ShowStatus(msg, type := "info") {
    global g_Settings
    prefix := ""
    switch type {
        case "ok": prefix := "[OK] "
        case "wait": prefix := "[...] "
        case "retry": prefix := "[RETRY] "
        case "fail": prefix := "[FAIL] "
    }
    ToolTip(prefix . msg)
    duration := g_Settings["TooltipDuration"]
    if type = "wait"
        duration := 10000  ; Wait messages stay longer
    else if type = "ok" || type = "fail"
        duration := g_Settings["TooltipDuration"]
    SetTimer(() => ToolTip(), -duration)
}


; ═══════════════════════════════════════════════════════════════════════════════
; VISUAL OVERLAY SYSTEM - STANDARDIZED HIGHLIGHTS, MARKERS, REGIONS
; ═══════════════════════════════════════════════════════════════════════════════
; VISUAL OVERLAY SYSTEM - Standardized highlights, markers, regions

; ═══════════════════════════════════════════════════════════════════════════════
; ALL VISUAL FEEDBACK USES THIS UNIFIED SYSTEM FOR CONSISTENCY:
; ═══════════════════════════════════════════════════════════════════════════════
; All visual feedback uses this unified system for consistency:
; - Pattern match highlights (magenta)
; - OCR word highlights (green/yellow)
; - Selection regions (green fill)
; - Error indicators (red)
; - Info markers (blue)

; Create a highlight overlay at specified coordinates
; style: "highlight", "selection", "match", "error", "info", "word", "pattern"
; Returns: overlay ID for later removal
CreateOverlay(x, y, w, h, style := "highlight", duration := 0, label := "") {
    global g_Overlays, g_OverlayCounter, g_OverlayStyles

    g_OverlayCounter++
    id := g_OverlayCounter

    ; Get style settings
    if !g_OverlayStyles.Has(style)
        style := "highlight"
    s := g_OverlayStyles[style]

    color := s["color"]
    thick := s["thickness"]
    fill := s.Has("fill") ? s["fill"] : false
    fillAlpha := s.Has("fillAlpha") ? s["fillAlpha"] : 50

    ; Create the overlay GUI with 4 border lines (no fill) or filled box
    if fill {
        ; Single filled overlay
        overlayGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "Overlay" . id)
        overlayGui.BackColor := color
        overlayGui.Show("x" . x . " y" . y . " w" . w . " h" . h . " NoActivate")
        WinSetTransparent(fillAlpha, overlayGui)

        g_Overlays[id] := Map("type", "filled", "gui", overlayGui, "x", x, "y", y, "w", w, "h", h)
    } else {
        ; Four border lines for a hollow rectangle
        borders := []

        ; Top border
        topGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "OverlayTop" . id)
        topGui.BackColor := color
        topGui.Show("x" . x . " y" . y . " w" . w . " h" . thick . " NoActivate")
        borders.Push(topGui)

        ; Bottom border
        bottomGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "OverlayBottom" . id)
        bottomGui.BackColor := color
        bottomGui.Show("x" . x . " y" . (y + h - thick) . " w" . w . " h" . thick . " NoActivate")
        borders.Push(bottomGui)

        ; Left border
        leftGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "OverlayLeft" . id)
        leftGui.BackColor := color
        leftGui.Show("x" . x . " y" . y . " w" . thick . " h" . h . " NoActivate")
        borders.Push(leftGui)

        ; Right border
        rightGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "OverlayRight" . id)
        rightGui.BackColor := color
        rightGui.Show("x" . (x + w - thick) . " y" . y . " w" . thick . " h" . h . " NoActivate")
        borders.Push(rightGui)

        g_Overlays[id] := Map("type", "border", "borders", borders, "x", x, "y", y, "w", w, "h", h)
    }

    ; Add label if provided
    if label != "" {
        labelGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "OverlayLabel" . id)
        labelGui.BackColor := "1a1a2e"
        labelGui.SetFont("s9 cWhite", "Consolas")
        labelGui.Add("Text", "x2 y1 c" . color, label)
        labelGui.Show("x" . x . " y" . (y - 18) . " NoActivate AutoSize")
        WinSetTransparent(220, labelGui)
        g_Overlays[id]["label"] := labelGui
    }

    ; Auto-remove after duration (if specified)
    if duration > 0 {
        removeFunc := (*) => RemoveOverlay(id)
        SetTimer(removeFunc, -duration)
    }

    return id
}

; Remove a specific overlay
RemoveOverlay(id) {
    global g_Overlays

    if !g_Overlays.Has(id)
        return

    overlay := g_Overlays[id]

    if overlay["type"] = "filled" {
        try overlay["gui"].Destroy()
    } else if overlay["type"] = "border" {
        for border in overlay["borders"]
            try border.Destroy()
    }

    ; Remove label if exists
    if overlay.Has("label")
        try overlay["label"].Destroy()

    g_Overlays.Delete(id)
}

; Remove all overlays
ClearAllOverlays() {
    global g_Overlays

    for id, overlay in g_Overlays {
        if overlay["type"] = "filled" {
            try overlay["gui"].Destroy()
        } else if overlay["type"] = "border" {
            for border in overlay["borders"]
                try border.Destroy()
        }
        if overlay.Has("label")
            try overlay["label"].Destroy()
    }

    g_Overlays := Map()
}

; Highlight a word/region temporarily (convenience function)
HighlightRegion(x, y, w, h, duration := 2000, style := "highlight", label := "") {
    return CreateOverlay(x, y, w, h, style, duration, label)
}

; Highlight multiple words from OCR results
HighlightOCRWords(words, duration := 2000, style := "word") {
    ids := []
    for word in words {
        id := CreateOverlay(word.x, word.y, word.w, word.h, style, duration, word.Text)
        ids.Push(id)
    }
    return ids
}

; Draw clean yellow boxes around every OCR word without adding label windows.
HighlightOCRWordsYellow(words, originX := 0, originY := 0, duration := 10000) {
    global g_OCRYellowOverlayIds
    for id in g_OCRYellowOverlayIds
        try RemoveOverlay(id)
    g_OCRYellowOverlayIds := []

    for word in words {
        if word.w < 1 || word.h < 1
            continue
        id := CreateOverlay(originX + word.x, originY + word.y, word.w, word.h,
                            "ocrYellow", duration)
        g_OCRYellowOverlayIds.Push(id)
    }
    return g_OCRYellowOverlayIds
}

; Flash highlight (blink effect)
FlashHighlight(x, y, w, h, times := 3, interval := 200, style := "highlight") {
    flashFunc := FlashHighlightWorker.Bind(x, y, w, h, times, interval, style, 0, 0)
    flashFunc()
}

FlashHighlightWorker(x, y, w, h, times, interval, style, count, overlayId) {
    global g_Overlays

    if count >= times * 2
        return

    if Mod(count, 2) = 0 {
        ; Show
        overlayId := CreateOverlay(x, y, w, h, style, 0)
    } else {
        ; Hide
        RemoveOverlay(overlayId)
        overlayId := 0
    }

    nextFunc := FlashHighlightWorker.Bind(x, y, w, h, times, interval, style, count + 1, overlayId)
    SetTimer(nextFunc, -interval)
}

; Show coordinates tooltip at position
ShowCoordTooltip(x, y, text := "", duration := 2000) {
    if text = ""
        text := "X: " . x . " Y: " . y
    ToolTip(text, x + 15, y + 15)
    if duration > 0
        SetTimer(() => ToolTip(), -duration)
}


; ═══════════════════════════════════════════════════════════════════════════════
; OCR WORD TRACKING SYSTEM - DYNAMIC TEXT CAPTURE FOR AUTOMATIONS
; ═══════════════════════════════════════════════════════════════════════════════
; OCR WORD TRACKING SYSTEM - Dynamic text capture for automations

; ═══════════════════════════════════════════════════════════════════════════════
; CAPTURES TEXT FROM SCREEN REGIONS AND MAKES THEM AVAILABLE AS VARIABLES
; ═══════════════════════════════════════════════════════════════════════════════
; Captures text from screen regions and makes them available as variables
; for use in workflows, spools, and other automations.
;
; Use cases:
; - Patient name from header → $word.PatientName
; - Phone number from Weave popup → $word.PhoneNumber
; - Current date from form → $word.CurrentDate

; Define a watch word pattern
; name: Variable name (e.g., "PatientName")
; region: Map with x1,y1,x2,y2 coordinates
; pattern: Optional regex to extract specific text
; labelIndex: Which word index in region (0 = all, 1 = first word, etc.)
DefineWatchWord(name, region, pattern := "", labelIndex := 0) {
    global g_WatchWords

    g_WatchWords[name] := Map(
        "region", region,
        "pattern", pattern,
        "labelIndex", labelIndex,
        "lastValue", "",
        "lastCoords", Map("x", 0, "y", 0, "w", 0, "h", 0),
        "lastUpdate", 0
    )

    SaveWatchWords()
    return true
}

; Update a watch word by running OCR on its region
UpdateWatchWord(name) {
    global g_WatchWords, g_WordVariables

    if !g_WatchWords.Has(name)
        return false

    watch := g_WatchWords[name]
    region := watch["region"]

    try {
        w := region["x2"] - region["x1"]
        h := region["y2"] - region["y1"]

        if w < 10 || h < 10
            return false

        result := OCR.FromRect(region["x1"], region["y1"], w, h)

        if result.Words.Length = 0
            return false

        ; Get text based on labelIndex
        if watch["labelIndex"] = 0 {
            ; All text
            value := result.Text
            coords := Map("x", region["x1"], "y", region["y1"], "w", w, "h", h)
        } else if watch["labelIndex"] <= result.Words.Length {
            ; Specific word
            word := result.Words[watch["labelIndex"]]
            value := word.Text
            coords := Map("x", word.x, "y", word.y, "w", word.w, "h", word.h)
        } else {
            return false
        }

        ; Apply regex pattern if specified
        if watch["pattern"] != "" {
            if RegExMatch(value, watch["pattern"], &match)
                value := match[0]
        }

        ; Update watch word
        watch["lastValue"] := value
        watch["lastCoords"] := coords
        watch["lastUpdate"] := A_TickCount

        ; Store in variables for workflow use
        g_WordVariables["$word." . name] := value
        g_SpoolVariables["$word." . name] := value

        return true
    } catch {
        return false
    }
}

; Update all watch words
UpdateAllWatchWords() {
    global g_WatchWords

    for name, watch in g_WatchWords {
        UpdateWatchWord(name)
    }
}

; Get watch word value
GetWatchWordValue(name) {
    global g_WatchWords

    if !g_WatchWords.Has(name)
        return ""

    return g_WatchWords[name]["lastValue"]
}

; Get watch word coordinates
GetWatchWordCoords(name) {
    global g_WatchWords

    if !g_WatchWords.Has(name)
        return Map("x", 0, "y", 0, "w", 0, "h", 0)

    return g_WatchWords[name]["lastCoords"]
}

; Click on a watch word (uses last known coordinates)
ClickWatchWord(name, clickType := "Click") {
    global g_WatchWords

    if !g_WatchWords.Has(name)
        return false

    coords := g_WatchWords[name]["lastCoords"]
    if coords["w"] = 0
        return false

    x := coords["x"] + coords["w"] // 2
    y := coords["y"] + coords["h"] // 2

    switch clickType {
        case "Click": Click(x, y)
        case "DblClick": Click(x, y, 2)
        case "RClick": Click(x, y, "Right")
    }

    return true
}

; Highlight a watch word on screen
HighlightWatchWord(name, duration := 2000) {
    global g_WatchWords

    if !g_WatchWords.Has(name)
        return 0

    coords := g_WatchWords[name]["lastCoords"]
    if coords["w"] = 0
        return 0

    return HighlightRegion(coords["x"], coords["y"], coords["w"], coords["h"], duration, "word", name . ": " . g_WatchWords[name]["lastValue"])
}

; Save watch words to file
SaveWatchWords() {
    global g_WatchWords, OCR_WORDS_FILE

    try FileDelete(OCR_WORDS_FILE)

    for name, watch in g_WatchWords {
        section := "[" . name . "]`n"
        section .= "x1=" . watch["region"]["x1"] . "`n"
        section .= "y1=" . watch["region"]["y1"] . "`n"
        section .= "x2=" . watch["region"]["x2"] . "`n"
        section .= "y2=" . watch["region"]["y2"] . "`n"
        section .= "pattern=" . watch["pattern"] . "`n"
        section .= "labelIndex=" . watch["labelIndex"] . "`n"

        FileAppend(section . "`n", OCR_WORDS_FILE)
    }
}

; Load watch words from file
LoadWatchWords() {
    global g_WatchWords, OCR_WORDS_FILE

    if !FileExist(OCR_WORDS_FILE)
        return

    try {
        content := FileRead(OCR_WORDS_FILE)
    } catch {
        return  ; File read failed, just return
    }

    if content = ""
        return

    currentName := ""
    currentWatch := Map()

    for line in StrSplit(content, "`n") {
        line := Trim(line)
        if line = ""
            continue

        if SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]" {
            ; Save previous watch if exists
            if currentName != "" && currentWatch.Has("region") {
                g_WatchWords[currentName] := currentWatch
            }

            currentName := SubStr(line, 2, -1)
            currentWatch := Map(
                "region", Map("x1", 0, "y1", 0, "x2", 0, "y2", 0),
                "pattern", "",
                "labelIndex", 0,
                "lastValue", "",
                "lastCoords", Map("x", 0, "y", 0, "w", 0, "h", 0),
                "lastUpdate", 0
            )
        } else if InStr(line, "=") {
            parts := StrSplit(line, "=", , 2)
            key := parts[1]
            val := parts.Length > 1 ? parts[2] : ""

            switch key {
                case "x1": currentWatch["region"]["x1"] := Integer(val)
                case "y1": currentWatch["region"]["y1"] := Integer(val)
                case "x2": currentWatch["region"]["x2"] := Integer(val)
                case "y2": currentWatch["region"]["y2"] := Integer(val)
                case "pattern": currentWatch["pattern"] := val
                case "labelIndex": currentWatch["labelIndex"] := Integer(val)
            }
        }
    }

    ; Save last watch
    if currentName != "" && currentWatch.Has("region") {
        g_WatchWords[currentName] := currentWatch
    }
}


; ═══════════════════════════════════════════════════════════════════════════════
; PATTERN TEST HIGHLIGHTING - USES STANDARDIZED OVERLAY SYSTEM
; ═══════════════════════════════════════════════════════════════════════════════
; PATTERN TEST HIGHLIGHTING - Uses standardized overlay system
; =============================================================================

; Test a FindText pattern and highlight the result
TestPatternHighlight(patternName, duration := 3000) {
    global g_Patterns

    if !g_Patterns.Has(patternName) {
        ShowStatus("Pattern not found: " . patternName, "fail")
        return false
    }

    pattern := g_Patterns[patternName]
    text := pattern["text"]

    try {
        if ok := FindText(&x, &y, 0, 0, 0, 0, 0, 0, text) {
            ; Get pattern dimensions from the result
            px := ok[1].x
            py := ok[1].y
            pw := ok[1].w
            ph := ok[1].h

            ; Create highlight with label
            id := CreateOverlay(px, py, pw, ph, "pattern", duration, patternName)
            ShowStatus("Found: " . patternName . " at " . px . "," . py, "ok")
            return true
        } else {
            ShowStatus("Pattern not found on screen: " . patternName, "fail")
            return false
        }
    } catch as err {
        ShowStatus("Pattern test error: " . err.Message, "fail")
        return false
    }
}

; Test all patterns and highlight matches
TestAllPatternsHighlight(duration := 2000) {
    global g_Patterns

    found := 0
    for name, pattern in g_Patterns {
        text := pattern["text"]
        try {
            if ok := FindText(&x, &y, 0, 0, 0, 0, 0, 0, text) {
                CreateOverlay(ok[1].x, ok[1].y, ok[1].w, ok[1].h, "pattern", duration, name)
                found++
            }
        }
    }

    ShowStatus("Found " . found . " of " . g_Patterns.Count . " patterns", found > 0 ? "ok" : "info")
    return found
}

UpdateDefinitionMode() {
    global g_DefinitionMode, DefModeIndicator
    newState := GetKeyState("CapsLock", "T")
    if newState != g_DefinitionMode {
        g_DefinitionMode := newState
        try {
            if g_DefinitionMode {
                DefModeIndicator.Value := "DEFINITION MODE ON"
                DefModeIndicator.Opt("cGreen Background")
                ShowDefModeTooltip()
            } else {
                DefModeIndicator.Value := "Definition Mode OFF"
                DefModeIndicator.Opt("cGray BackgroundDefault")
                ToolTip()
            }
        }
    }
}

ShowDefModeTooltip() {
    global g_DefinitionMode, g_Settings
    if !g_DefinitionMode
        return
    MouseGetPos(&x, &y)
    tip := "=== DEFINITION MODE ===`n"
    tip .= "C = Click here`n"
    tip .= "D = Drag (press twice)`n"
    tip .= "R = Right Click`n"
    tip .= "T = Triple Click`n"
    tip .= "P = Capture Pattern`n"
    tip .= "W = Wait (200ms)`n"
    tip .= "K = Send Keys`n"
    tip .= "M = Menu Select`n"
    tip .= "ESC = Cancel/Hide"
    ToolTip(tip, x + 20, y + 20)
    SetTimer(() => ToolTip(), -g_Settings["PreviewTooltipDuration"])
}

; Definition mode handlers
DefModeClick() {
    global g_DefinitionMode, g_CurrentSequenceSteps, g_Settings
    if !g_DefinitionMode
        return

    MouseGetPos(&x, &y)
    win := GetWindowUnderMouse()

    if g_Settings["FailsafeCheckCloseButton"] && IsNearCloseButton(x, y) {
        ShowStatus("Blocked: Near close button!", "fail")
        return
    }

    patternName := ""
    if g_Settings["DefinitionModeAutoPattern"]
        patternName := AutoCapturePatternAt(x, y)

    step := Map(
        "action", "Click",
        "target", x . "," . y,
        "param", "1",
        "enabled", 1,
        "window", win["title"],
        "pattern", patternName,
        "failsafe", Map("checkCloseBtn", 1)
    )
    g_CurrentSequenceSteps.Push(step)
    RefreshStepsLV()
    ScheduleWorkflowAutosave()
    ShowMarker(x, y, 1000, "Green")
    ShowStatus("Added Click @ " . x . "," . y, "ok")
}

DefModeRightClick() {
    global g_DefinitionMode, g_CurrentSequenceSteps, g_Settings
    if !g_DefinitionMode
        return

    MouseGetPos(&x, &y)
    win := GetWindowUnderMouse()

    if g_Settings["FailsafeCheckCloseButton"] && IsNearCloseButton(x, y) {
        ShowStatus("Blocked: Near close button!", "fail")
        return
    }

    patternName := ""
    if g_Settings["DefinitionModeAutoPattern"]
        patternName := AutoCapturePatternAt(x, y)

    step := Map(
        "action", "Right Click",
        "target", x . "," . y,
        "param", "",
        "enabled", 1,
        "window", win["title"],
        "pattern", patternName
    )
    g_CurrentSequenceSteps.Push(step)
    RefreshStepsLV()
    ScheduleWorkflowAutosave()
    ShowMarker(x, y, 1000, "Blue")
    ShowStatus("Added Right Click @ " . x . "," . y, "ok")
}

DefModeTripleClick() {
    global g_DefinitionMode, g_CurrentSequenceSteps
    if !g_DefinitionMode
        return

    MouseGetPos(&x, &y)
    win := GetWindowUnderMouse()

    step := Map(
        "action", "Triple Click",
        "target", x . "," . y,
        "param", "",
        "enabled", 1,
        "window", win["title"]
    )
    g_CurrentSequenceSteps.Push(step)
    RefreshStepsLV()
    ScheduleWorkflowAutosave()
    ShowMarker(x, y, 1000, "Purple")
    ShowStatus("Added Triple Click @ " . x . "," . y, "ok")
}

DefModeDragStart() {
    global g_DefinitionMode, g_DefModeStartX, g_DefModeStartY, g_DefModeDragging
    if !g_DefinitionMode
        return

    if !g_DefModeDragging {
        MouseGetPos(&g_DefModeStartX, &g_DefModeStartY)
        g_DefModeDragging := true
        ShowMarker(g_DefModeStartX, g_DefModeStartY, 10000, "Blue")
        ShowStatus("Drag START. Press D again at end.", "wait")
    } else {
        DefModeDragEnd()
    }
}

DefModeDragEnd() {
    global g_DefinitionMode, g_DefModeStartX, g_DefModeStartY, g_DefModeDragging
    global g_CurrentSequenceSteps
    if !g_DefinitionMode || !g_DefModeDragging
        return

    MouseGetPos(&endX, &endY)
    g_DefModeDragging := false

    step := Map(
        "action", "Drag",
        "target", "",
        "param", g_DefModeStartX . "," . g_DefModeStartY . "->" . endX . "," . endY,
        "enabled", 1
    )
    g_CurrentSequenceSteps.Push(step)
    RefreshStepsLV()
    ScheduleWorkflowAutosave()
    HideMarker()
    ShowMarker(endX, endY, 1000, "Green")
    ShowStatus("Added Drag: " . g_DefModeStartX . "," . g_DefModeStartY . " -> " . endX . "," . endY, "ok")
}

DefModePattern() {
    global g_DefinitionMode
    if !g_DefinitionMode
        return

    MouseGetPos(&x, &y)
    patternName := AutoCapturePatternAt(x, y)
    if patternName != "" {
        ShowStatus("Captured pattern: " . patternName, "ok")
    } else {
        ShowStatus("Pattern capture failed", "fail")
    }
}

DefModeWait() {
    global g_DefinitionMode, g_CurrentSequenceSteps
    if !g_DefinitionMode
        return

    step := Map("action", "Wait", "target", "", "param", "200", "enabled", 1)
    g_CurrentSequenceSteps.Push(step)
    RefreshStepsLV()
    ScheduleWorkflowAutosave()
    ShowStatus("Added Wait 200ms", "ok")
}

DefModeMenuSelect() {
    global g_DefinitionMode, g_CurrentSequenceSteps
    if !g_DefinitionMode
        return

    res := InputBoxTop("Menu item position (1=first, 2=second):", "Menu Select", "1")
    if res["Result"] = "OK" {
        step := Map("action", "Menu Select", "target", "", "param", res["Value"], "enabled", 1)
        g_CurrentSequenceSteps.Push(step)
        RefreshStepsLV()
        ScheduleWorkflowAutosave()
        ShowStatus("Added Menu Select: " . res["Value"], "ok")
    }
}

DefModeSendKeys() {
    global g_DefinitionMode, g_CurrentSequenceSteps
    if !g_DefinitionMode
        return

    res := InputBoxTop("Keys to send (^c=Ctrl+C):", "Send Keys", "^c")
    if res["Result"] = "OK" {
        step := Map("action", "Send Keys", "target", "", "param", res["Value"], "enabled", 1)
        g_CurrentSequenceSteps.Push(step)
        RefreshStepsLV()
        ScheduleWorkflowAutosave()
        ShowStatus("Added Send Keys: " . res["Value"], "ok")
    }
}

DefModeCancel() {
    global g_DefModeDragging
    g_DefModeDragging := false
    HideMarker()
    ToolTip()
}

; Auto-capture pattern at coordinates
AutoCapturePatternAt(x, y, size := 30) {
    global g_Patterns, g_Settings, PREVIEW_DIR, SCREENSHOTS_DIR

    try {
        x1 := x - size
        y1 := y - size
        x2 := x + size
        y2 := y + size

        ; Use FindText to capture
        text := FindText().GetTextFromScreen(x1, y1, x2, y2, "**50")

        if text = "" || StrLen(text) < 10
            return ""

        patternNum := 1
        while g_Patterns.Has("Auto_" . patternNum)
            patternNum++
        name := "Auto_" . patternNum

        patternText := "|<" . name . ">" . text

        ; Also capture a 100x100 screenshot centered on the point
        screenshotPath := CapturePatternScreenshot(name)

        g_Patterns[name] := Map("text", patternText, "desc", "Auto @ " . x . "," . y, "screenshot", screenshotPath)

        SavePatterns()
        RefreshPatternLV()
        UpdateTargetDD()
AddWorkflowTooltips()
        UpdateQualPatternDD()

        return name
    }
    return ""
}


; ═══════════════════════════════════════════════════════════════════════════════
; PATTERN PREVIEW SYSTEM (VISUAL)
; ═══════════════════════════════════════════════════════════════════════════════
; PATTERN PREVIEW SYSTEM (Visual)
; =============================================================================

; Save a screenshot of the pattern area
SavePatternPreview(name, x1, y1, x2, y2) {
    global PREVIEW_DIR
    try {
        ; Use FindText's screenshot capability
        FindText().ScreenShot(x1, y1, x2, y2)

        ; Save to file using GDI+
        previewPath := PREVIEW_DIR . "\" . name . ".bmp"
        ; Note: FindText doesn't have direct save, so we'll use a workaround
        ; For now, just record the coordinates for live preview
    }
}

; Show pattern preview in tooltip (visual representation)
ShowPatternPreviewTooltip(patternName, x := "", y := "") {
    global g_Patterns, g_Settings

    if !g_Patterns.Has(patternName)
        return

    patternData := g_Patterns[patternName]
    code := patternData["text"]
    desc := patternData.Has("desc") ? patternData["desc"] : ""

    ; Build preview tooltip
    tip := "=== " . patternName . " ===`n"
    if desc != ""
        tip .= desc . "`n"
    tip .= "-------------------`n"
    tip .= PatternToVisualPreview(code)
    tip .= "`n-------------------`n"
    tip .= "Click to show full preview"

    if x = ""
        MouseGetPos(&x, &y)

    ToolTip(tip, x + 20, y + 20)
    SetTimer(() => ToolTip(), -g_Settings["PreviewTooltipDuration"])
}

; Convert pattern to compact visual preview (improved)
PatternToVisualPreview(patternText, maxWidth := 40, maxHeight := 15) {
    if patternText = "" || !InStr(patternText, "$")
        return "[Invalid pattern]"

    if !RegExMatch(patternText, "\$(\d+)\.(.+)", &m)
        return "[Parse error]"

    width := Integer(m[1])
    data := m[2]

    ; Character map for base64-like encoding
    charMap := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/"

    ; Calculate scale factor
    scaleX := width > maxWidth ? Ceil(width / maxWidth) : 1

    result := ""
    row := ""
    pixelCount := 0
    rowCount := 0

    for i, char in StrSplit(data) {
        pos := InStr(charMap, char) - 1
        if pos < 0
            pos := 0

        ; Each char represents 6 bits (pixels)
        bits := ""
        Loop 6 {
            bit := (pos >> (5 - A_Index + 1)) & 1
            bits .= bit ? "#" : " "
        }

        ; Add to row (with scaling)
        if Mod(pixelCount, scaleX) = 0 {
            for j, b in StrSplit(bits) {
                if Mod(j - 1, scaleX) = 0
                    row .= b
            }
        }

        pixelCount += 6

        ; Check if row complete
        if pixelCount >= width {
            if Mod(rowCount, scaleX) = 0 {
                result .= row . "`n"
                if StrLen(result) / (maxWidth + 1) >= maxHeight {
                    result .= "... (truncated)`n"
                    break
                }
            }
            row := ""
            pixelCount := 0
            rowCount++
        }
    }

    if row != "" && rowCount < maxHeight * scaleX
        result .= row

    return result
}

; Popout full preview window
ShowFullPatternPreview(patternName) {
    global g_Patterns, g_Settings

    if !g_Patterns.Has(patternName)
        return

    patternData := g_Patterns[patternName]
    code := patternData["text"]
    desc := patternData.Has("desc") ? patternData["desc"] : ""
    screenshotPath := patternData.Has("screenshot") ? patternData["screenshot"] : ""
    captureX := patternData.Has("captureX") ? patternData["captureX"] : 0
    captureY := patternData.Has("captureY") ? patternData["captureY"] : 0
    captureWindow := patternData.Has("captureWindow") ? patternData["captureWindow"] : ""
    qualifier := patternData.Has("qualifier") ? patternData["qualifier"] : ""

    ; Create preview GUI
    previewGui := Gui("+AlwaysOnTop +ToolWindow", "Pattern: " . patternName)
    previewGui.SetFont("s9", "Segoe UI")

    ; Pattern info section
    previewGui.Add("GroupBox", "w630 h90 Section", "Pattern Information")
    previewGui.Add("Text", "xp+10 yp+18 w150", "Name: " . patternName)
    previewGui.Add("Text", "x+10 w450", "Description: " . (desc != "" ? desc : "(none)"))

    previewGui.Add("Text", "xs+10 y+5 w150", "Location: " . captureX . ", " . captureY)
    previewGui.Add("Text", "x+10 w450", "Window: " . (captureWindow != "" ? captureWindow : "(none)"))

    previewGui.Add("Text", "xs+10 y+5 w150", "Qualifier: " . (qualifier != "" ? qualifier : "(none)"))
    if qualifier != "" {
        ; Show qualifier status
        qualOK := CheckPatternQualifier(qualifier)
        previewGui.Add("Text", "x+10 w100 " . (qualOK ? "cGreen" : "cRed"), qualOK ? "✓ Found" : "✗ Not found")
    }

    ; Layout: ASCII on left, Screenshot + Info on right
    previewGui.Add("GroupBox", "xs y+15 w420 h340 Section", "ASCII Preview")
    previewGui.SetFont("s6", "Consolas")
    preview := PatternToVisualPreview(code, 65, 30)
    previewGui.Add("Edit", "xp+10 yp+18 w400 h310 ReadOnly Multi", preview)

    ; Right side: Screenshot and info
    previewGui.SetFont("s9", "Segoe UI")
    previewGui.Add("GroupBox", "ys x440 w200 h170", "Screenshot")

    if screenshotPath != "" && FileExist(screenshotPath) {
        previewGui.Add("Picture", "xp+50 yp+20 w100 h100 Border", screenshotPath)
        previewGui.Add("Button", "xp-25 y+10 w150 h22", "Open Image").OnEvent("Click", (*) => Run(screenshotPath))
    } else {
        previewGui.Add("Text", "xp+10 yp+40 w180 h60 Center", "(No screenshot)`n`nUse 📷 Find to capture")
    }

    ; Capture info box
    previewGui.Add("GroupBox", "x440 y+20 w200 h150", "Capture Data")
    previewGui.Add("Text", "xp+10 yp+20", "Coordinates:")
    previewGui.Add("Text", "xp+10 y+2 w170 cBlue", captureX . ", " . captureY)
    previewGui.Add("Text", "xp-10 y+10", "Window Title:")
    previewGui.Add("Text", "xp+10 y+2 w170 cBlue", captureWindow != "" ? SubStr(captureWindow, 1, 25) : "(none)")
    previewGui.Add("Text", "xp-10 y+10", "Qualifier Pattern:")
    previewGui.Add("Text", "xp+10 y+2 w170 cBlue", qualifier != "" ? qualifier : "(none)")

    ; Code display at bottom
    previewGui.SetFont("s7", "Consolas")
    previewGui.Add("Text", "x10 y+20", "Pattern Code:")
    previewGui.Add("Edit", "w630 h45 ReadOnly", code)

    ; Buttons
    previewGui.SetFont("s9", "Segoe UI")
    previewGui.Add("Button", "y+10 w100", "Test").OnEvent("Click", (*) => TestPatternByName(patternName))
    previewGui.Add("Button", "x+10 w100", "Close").OnEvent("Click", (*) => previewGui.Destroy())

    previewGui.Show()
}


; ═══════════════════════════════════════════════════════════════════════════════
; FINDTEXT PATTERN FUNCTIONS
; ═══════════════════════════════════════════════════════════════════════════════
; FINDTEXT PATTERN FUNCTIONS
; =============================================================================

FindPatternOnScreen(patternName, tolerance := "") {
    global g_Patterns, g_Settings

    if !g_Patterns.Has(patternName)
        return Map("found", false)

    patternData := g_Patterns[patternName]
    patternText := patternData["text"]

    if tolerance = ""
        tolerance := g_Settings["FindTextTolerance"]

    ok := FindText(&outX, &outY, , , , , tolerance, tolerance, patternText)

    if ok && ok.Length > 0 {
        return Map(
            "found", true,
            "x", ok[1].x,
            "y", ok[1].y,
            "mx", ok[1].mx,
            "my", ok[1].my,
            "w", ok[1].w,
            "h", ok[1].h
        )
    }

    return Map("found", false)
}

TestPatternByName(patternName) {
    global g_Patterns, g_Settings

    if !g_Patterns.Has(patternName) {
        ShowStatus("Pattern not found: " . patternName, "fail")
        return false
    }

    code := g_Patterns[patternName]["text"]
    tolerance := g_Settings["FindTextTolerance"]

    ShowStatus("Searching: " . patternName, "wait")
    ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)

    if ok && ok.Length > 0 {
        FindText().MouseTip(ok[1].mx, ok[1].my)
        ShowStatus("FOUND: " . patternName . " @ " . ok[1].mx . "," . ok[1].my, "ok")
        return true
    }

    ShowStatus("NOT FOUND: " . patternName, "fail")
    return false
}

WaitForPattern(patternName, timeout := 0, tolerance := "") {
    global g_Settings, g_AbortSequence

    if timeout = 0
        timeout := g_Settings["FindTextTimeout"]

    startTime := A_TickCount

    while (A_TickCount - startTime) < timeout {
        if g_AbortSequence
            return false

        result := FindPatternOnScreen(patternName, tolerance)
        if result["found"]
            return result

        Sleep(100)
    }

    return false
}

WaitForPatternGone(patternName, timeout := 0, tolerance := "") {
    global g_Settings, g_AbortSequence

    if timeout = 0
        timeout := g_Settings["FindTextTimeout"]

    startTime := A_TickCount

    while (A_TickCount - startTime) < timeout {
        if g_AbortSequence
            return false

        result := FindPatternOnScreen(patternName, tolerance)
        if !result["found"]
            return true

        Sleep(100)
    }

    return false
}

FindAndClickPattern(patternName, button := "Left", clickCount := 1, tolerance := "") {
    global g_Settings, g_AbortSequence, g_LastClickX, g_LastClickY, g_Patterns

    ; Strip [P] prefix if present
    patternName := StrReplace(patternName, "[P] ", "")

    ; Check qualifier first if pattern has one
    if g_Patterns.Has(patternName) {
        qualifier := g_Patterns[patternName].Has("qualifier") ? g_Patterns[patternName]["qualifier"] : ""
        if qualifier != "" {
            if !CheckPatternQualifier(qualifier) {
                ShowStatus("Qualifier not found: " . qualifier, "fail")
                return false
            }
            ShowStatus("Qualifier OK: " . qualifier, "ok")
        }
    }

    ShowStatus("Finding: " . patternName, "wait")

    Loop g_Settings["MaxRetries"] {
        if g_AbortSequence
            return false

        result := FindPatternOnScreen(patternName, tolerance)

        if result["found"] {
            x := result["mx"]
            y := result["my"]

            if g_Settings["FailsafeCheckCloseButton"] && IsNearCloseButton(x, y) {
                ShowStatus("Failsafe: Near close button", "fail")
                return false
            }

            Sleep(g_Settings["PreActionDelay"])
            MouseMove(x, y, 5)
            Sleep(50)

            MouseGetPos(&actualX, &actualY)
            if Abs(actualX - x) > 5 || Abs(actualY - y) > 5 {
                ShowStatus("Position verify failed", "retry")
                continue
            }

            Click(x, y, button, clickCount)
            g_LastClickX := x
            g_LastClickY := y
            Sleep(g_Settings["PostActionDelay"])

            ShowStatus("Clicked: " . patternName . " @ " . x . "," . y, "ok")
            return true
        }

        if A_Index < g_Settings["MaxRetries"] {
            ShowStatus("Retry " . A_Index . "/" . g_Settings["MaxRetries"], "retry")
            Sleep(200)
        }
    }

    ShowStatus("Not found: " . patternName, "fail")
    return false
}

; Check if a qualifier pattern is visible on screen
CheckPatternQualifier(qualifierName) {
    global g_Patterns, g_Settings

    if qualifierName = "" || qualifierName = "(none)"
        return true  ; No qualifier = always OK

    if !g_Patterns.Has(qualifierName)
        return false

    code := g_Patterns[qualifierName]["text"]
    tolerance := g_Settings["FindTextTolerance"]

    ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)

    return (ok && ok.Length > 0)
}

FindAndDragPattern(patternName, endX, endY, tolerance := "") {
    global g_Settings, g_AbortSequence, g_LastClickX, g_LastClickY, g_Patterns

    ; Strip [P] prefix if present
    patternName := StrReplace(patternName, "[P] ", "")

    ; Check qualifier first if pattern has one
    if g_Patterns.Has(patternName) {
        qualifier := g_Patterns[patternName].Has("qualifier") ? g_Patterns[patternName]["qualifier"] : ""
        if qualifier != "" {
            if !CheckPatternQualifier(qualifier) {
                ShowStatus("Qualifier not found: " . qualifier, "fail")
                return false
            }
            ShowStatus("Qualifier OK: " . qualifier, "ok")
        }
    }

    ShowStatus("Finding for drag: " . patternName, "wait")

    result := FindPatternOnScreen(patternName, tolerance)

    if result["found"] {
        startX := result["mx"]
        startY := result["my"]

        Sleep(g_Settings["PreActionDelay"])
        MouseMove(startX, startY, 5)
        Sleep(50)

        MouseClickDrag("Left", startX, startY, endX, endY, g_Settings["DefaultDragTime"] / 100)
        g_LastClickX := endX
        g_LastClickY := endY
        Sleep(g_Settings["PostActionDelay"])

        ShowStatus("Dragged: " . patternName . " -> " . endX . "," . endY, "ok")
        return true
    }

    ShowStatus("Not found for drag: " . patternName, "fail")
    return false
}


; ═══════════════════════════════════════════════════════════════════════════════
; STEP PREVIEW ON SELECTION
; ═══════════════════════════════════════════════════════════════════════════════
; STEP PREVIEW ON SELECTION
; =============================================================================

ShowStepPreview(stepData) {
    global g_Coordinates, g_Patterns, g_Settings

    action := stepData["action"]
    target := stepData["target"]
    param := stepData["param"]

    tip := "=== STEP PREVIEW ===`n"
    tip .= "Action: " . action . "`n"

    ; Show coordinates
    if param != "" && InStr(param, ",") {
        if InStr(param, "->") {
            ; Drag format
            parts := StrSplit(param, "->")
            tip .= "From: " . parts[1] . "`n"
            tip .= "To: " . parts[2] . "`n"
        } else {
            tip .= "Position: " . param . "`n"
        }
    }

    ; Show target info
    if target != "" && target != "(none)" {
        tip .= "Target: " . target . "`n"

        ; If it's a pattern, show preview
        if g_Patterns.Has(target) {
            tip .= "---Pattern---`n"
            tip .= PatternToVisualPreview(g_Patterns[target]["text"], 30, 8)
        }
        ; If it's a coordinate
        else if g_Coordinates.Has(target) {
            c := g_Coordinates[target]
            tip .= "Coord: " . c["x"] . "," . c["y"]
            if c["endX"] != ""
                tip .= " -> " . c["endX"] . "," . c["endY"]
            tip .= "`n"
        }
    }

    ; Show window qualifier if set
    if stepData.Has("qualWindow") && stepData["qualWindow"] != ""
        tip .= "Window: " . stepData["qualWindow"] . "`n"

    MouseGetPos(&mx, &my)
    ToolTip(tip, mx + 20, my + 20)
    SetTimer(() => ToolTip(), -g_Settings["PreviewTooltipDuration"])
}


; ═══════════════════════════════════════════════════════════════════════════════
; FULL RECORDING SYSTEM
; ═══════════════════════════════════════════════════════════════════════════════
; FULL RECORDING SYSTEM
; =============================================================================

StartFullRecording() {
    global g_FullRecording, g_FullRecordLog
    g_FullRecording := true
    g_FullRecordLog := []

    SetTimer(RecordMousePosition, 100)
    Hotkey("~LButton", RecordLeftClick, "On")
    Hotkey("~RButton", RecordRightClick, "On")
    Hotkey("~MButton", RecordMiddleClick, "On")

    ShowStatus("Recording started", "ok")
}

StopFullRecording() {
    global g_FullRecording
    g_FullRecording := false

    SetTimer(RecordMousePosition, 0)
    try {
        Hotkey("~LButton", "Off")
        Hotkey("~RButton", "Off")
        Hotkey("~MButton", "Off")
    }

    SaveRecordingLog()
    ShowStatus("Recording stopped. " . g_FullRecordLog.Length . " events.", "ok")
}

RecordMousePosition() {
    global g_FullRecording, g_WindowHotspots
    if !g_FullRecording
        return

    MouseGetPos(&x, &y, &hwnd)
    win := GetWindowUnderMouse()

    winKey := win["exe"] . "|" . win["class"]
    if !g_WindowHotspots.Has(winKey)
        g_WindowHotspots[winKey] := Map()

    gridX := Floor(x / 50) * 50
    gridY := Floor(y / 50) * 50
    gridKey := gridX . "," . gridY

    if !g_WindowHotspots[winKey].Has(gridKey)
        g_WindowHotspots[winKey][gridKey] := 0
    g_WindowHotspots[winKey][gridKey]++
}

RecordLeftClick(*) {
    global g_FullRecording, g_FullRecordLog, g_Settings
    if !g_FullRecording
        return

    MouseGetPos(&x, &y)
    win := GetWindowUnderMouse()

    patternName := ""
    if g_Settings["AutoCapturePattern"]
        patternName := AutoCapturePatternAt(x, y, 20)

    entry := Map(
        "time", A_Now,
        "action", "LeftClick",
        "x", x,
        "y", y,
        "window", win["title"],
        "exe", win["exe"],
        "class", win["class"],
        "pattern", patternName,
        "method", "mouse"
    )
    g_FullRecordLog.Push(entry)
    UpdateAnalyticsDisplay()
}

RecordRightClick(*) {
    global g_FullRecording, g_FullRecordLog
    if !g_FullRecording
        return

    MouseGetPos(&x, &y)
    win := GetWindowUnderMouse()

    entry := Map(
        "time", A_Now,
        "action", "RightClick",
        "x", x,
        "y", y,
        "window", win["title"],
        "exe", win["exe"],
        "method", "mouse"
    )
    g_FullRecordLog.Push(entry)
    UpdateAnalyticsDisplay()
}

RecordMiddleClick(*) {
    global g_FullRecording, g_FullRecordLog
    if !g_FullRecording
        return

    MouseGetPos(&x, &y)
    win := GetWindowUnderMouse()

    entry := Map(
        "time", A_Now,
        "action", "MiddleClick",
        "x", x,
        "y", y,
        "window", win["title"],
        "exe", win["exe"]
    )
    g_FullRecordLog.Push(entry)
}

SaveRecordingLog() {
    global g_FullRecordLog, RECORDING_FILE

    try {
        file := FileOpen(RECORDING_FILE, "w", "UTF-8")
        file.WriteLine("Time,Action,X,Y,Window,Exe,Pattern,Method")
        for entry in g_FullRecordLog {
            line := entry["time"] . ","
            line .= entry["action"] . ","
            line .= entry["x"] . ","
            line .= entry["y"] . ","
            line .= StrReplace(entry["window"], ",", ";") . ","
            line .= entry["exe"] . ","
            line .= (entry.Has("pattern") ? entry["pattern"] : "") . ","
            line .= (entry.Has("method") ? entry["method"] : "")
            file.WriteLine(line)
        }
        file.Close()
    }
}

UpdateAnalyticsDisplay() {
    global g_FullRecordLog, AnalyticsText
    try {
        count := g_FullRecordLog.Length
        AnalyticsText.Value := "Events: " . count
    }
}


; ═══════════════════════════════════════════════════════════════════════════════
; WINDOW/MOUSE HELPERS
; ═══════════════════════════════════════════════════════════════════════════════
; WINDOW/MOUSE HELPERS
; =============================================================================

GetWindowList() {
    windows := []
    for hwnd in WinGetList() {
        title := ""
        try title := WinGetTitle(hwnd)
        if title != "" && title != "Program Manager" {
            if StrLen(title) > 50
                title := SubStr(title, 1, 47) . "..."
            exe := ""
            try exe := WinGetProcessName(hwnd)
            if exe != ""
                windows.Push(title . "  [" . exe . "]")
            else
                windows.Push(title)
        }
    }
    return windows
}

GetCommonPrograms() {
    return ["notepad.exe", "calc.exe", "mspaint.exe", "explorer.exe", "cmd.exe",
            "powershell.exe", "chrome.exe", "firefox.exe", "msedge.exe", "code.exe"]
}

ActivateWindowRobust(windowIdentifier, maxRetries := 0, timeout := 0) {
    global g_Settings, g_TaskbarApps
    if maxRetries = 0
        maxRetries := g_Settings["MaxRetries"]
    if timeout = 0
        timeout := g_Settings["WindowActivateTimeout"]

    ShowStatus("Activating: " . windowIdentifier, "wait")

    ; Check if it's a taskbar hotkey (Win+1, Win+2, etc.)
    if RegExMatch(windowIdentifier, "^Win\+(\d):", &m) {
        key := m[1]
        Send("#" . key)
        Sleep(200)
        ShowStatus("Sent Win+" . key, "ok")
        return true
    }

    Loop maxRetries {
        if WinExist(windowIdentifier) {
            WinActivate(windowIdentifier)
            Sleep(100)
            if WinActive(windowIdentifier) {
                ShowStatus("Window active", "ok")
                return true
            }
        }
        for hwnd in WinGetList() {
            title := ""
            try title := WinGetTitle(hwnd)
            if title != "" && InStr(title, windowIdentifier) {
                try {
                    WinActivate(hwnd)
                    Sleep(100)
                    if WinActive("ahk_id " . hwnd) {
                        ShowStatus("Window active: " . title, "ok")
                        return true
                    }
                }
            }
        }
        if WinExist("ahk_exe " . windowIdentifier) {
            WinActivate("ahk_exe " . windowIdentifier)
            Sleep(100)
            if WinActive("ahk_exe " . windowIdentifier) {
                ShowStatus("Window active (exe)", "ok")
                return true
            }
        }
        if A_Index < maxRetries {
            ShowStatus("Retry " . A_Index, "retry")
            Sleep(200)
        }
    }
    ShowStatus("FAILED: " . windowIdentifier, "fail")
    return false
}

MoveMouseVerified(x, y, speed := 5, maxRetries := 3) {
    Loop maxRetries {
        MouseMove(x, y, speed)
        Sleep(50)
        MouseGetPos(&ax, &ay)
        if Abs(ax - x) <= 3 && Abs(ay - y) <= 3
            return true
        Sleep(100)
    }
    return false
}

ClickVerified(x, y, button := "Left", count := 1) {
    global g_Settings, g_LastClickX, g_LastClickY

    if g_Settings["FailsafeCheckCloseButton"] && IsNearCloseButton(x, y) {
        ShowStatus("Failsafe blocked: Near close button", "fail")
        return false
    }

    if !MoveMouseVerified(x, y)
        return false
    Sleep(g_Settings["PreActionDelay"])
    Click(x, y, button, count)
    g_LastClickX := x
    g_LastClickY := y
    Sleep(g_Settings["PostActionDelay"])
    return true
}

SendKeysVerified(keys) {
    global g_Settings
    Sleep(g_Settings["PreActionDelay"])
    Send(keys)
    Sleep(g_Settings["PostActionDelay"])
    ShowStatus("Sent: " . keys, "ok")
    return true
}

TypeTextVerified(text) {
    global g_Settings
    Sleep(g_Settings["PreActionDelay"])
    SendText(text)
    Sleep(g_Settings["PostActionDelay"])
    return true
}

SetClipboardVerified(text) {
    global g_ExtractedData

    ; Substitute variables in text
    for varName, value in g_ExtractedData {
        if InStr(text, varName) {
            text := StrReplace(text, varName, value)
        }
    }

    A_Clipboard := ""
    Sleep(50)
    A_Clipboard := text
    ClipWait(1, 0)

    ; Show notification of what was copied with copy button
    if A_Clipboard = text {
        ShowNotificationBasic("Clipboard Set", "Copied to clipboard:`n`n" . SubStr(text, 1, 200) . (StrLen(text) > 200 ? "..." : ""), 0, "success", text)
        return true
    }

    return false
}


; ═══════════════════════════════════════════════════════════════════════════════
; KEY CHORD - HOLD MODIFIER AND PRESS KEY MULTIPLE TIMES
; ═══════════════════════════════════════════════════════════════════════════════
; KEY CHORD - Hold modifier and press key multiple times

; ═══════════════════════════════════════════════════════════════════════════════
; FORMAT: MODIFIER,KEY,REPEATCOUNT
; ═══════════════════════════════════════════════════════════════════════════════
; Format: modifier,key,repeatCount
; modifier: ^ (Ctrl), + (Shift), ! (Alt), # (Win), or combinations like ^+ (Ctrl+Shift)
; key: any key like "5", "a", "{Tab}", etc.
; repeatCount: how many times to press the key while holding modifier

ExecuteKeyChord(param) {
    global g_Settings

    if param = "" || !InStr(param, ",") {
        ShowStatus("Key Chord format: modifier,key,count (e.g. #,5,2)", "fail")
        return false
    }

    ; Strip any description text (e.g. "#,5,2  (Win+5 twice)" -> "#,5,2")
    if InStr(param, "  ")
        param := Trim(SubStr(param, 1, InStr(param, "  ") - 1))

    parts := StrSplit(param, ",")
    if parts.Length < 3 {
        ShowStatus("Key Chord needs: modifier,key,count", "fail")
        return false
    }

    modifier := Trim(parts[1])
    key := Trim(parts[2])
    repeatCount := Integer(Trim(parts[3]))

    ; Validate modifier
    validMods := ["^", "+", "!", "#", "^+", "^!", "+!", "^+!", "#^", "#!", "#+"]
    isValidMod := false
    for m in validMods {
        if modifier = m {
            isValidMod := true
            break
        }
    }
    if !isValidMod && modifier != "" {
        ShowStatus("Invalid modifier: " . modifier, "fail")
        return false
    }

    ; Build display string for status
    modDisplay := ""
    if InStr(modifier, "#") modDisplay .= "Win+"
    if InStr(modifier, "^") modDisplay .= "Ctrl+"
    if InStr(modifier, "+") modDisplay .= "Shift+"
    if InStr(modifier, "!") modDisplay .= "Alt+"

    ShowStatus("Key Chord: " . modDisplay . key . " x" . repeatCount, "wait")

    Sleep(g_Settings["PreActionDelay"])

    ; Press modifier down
    if InStr(modifier, "#") Send("{LWin down}")
    if InStr(modifier, "^") Send("{Ctrl down}")
    if InStr(modifier, "+") Send("{Shift down}")
    if InStr(modifier, "!") Send("{Alt down}")

    Sleep(50)  ; Small delay after pressing modifier

    ; Press the key repeatedly
    Loop repeatCount {
        Send(key)
        if A_Index < repeatCount
            Sleep(100)  ; Delay between presses
    }

    Sleep(50)  ; Small delay before releasing

    ; Release modifier (reverse order)
    if InStr(modifier, "!") Send("{Alt up}")
    if InStr(modifier, "+") Send("{Shift up}")
    if InStr(modifier, "^") Send("{Ctrl up}")
    if InStr(modifier, "#") Send("{LWin up}")

    Sleep(g_Settings["PostActionDelay"])

    ShowStatus("Sent: " . modDisplay . key . " x" . repeatCount, "ok")
    return true
}


; ═══════════════════════════════════════════════════════════════════════════════
; TASKBAR ACTIVATE - WIN+N WITH REPEAT FOR MULTIPLE WINDOWS
; ═══════════════════════════════════════════════════════════════════════════════
; TASKBAR ACTIVATE - Win+N with repeat for multiple windows

; ═══════════════════════════════════════════════════════════════════════════════
; FORMAT: POSITION,REPEATCOUNT
; ═══════════════════════════════════════════════════════════════════════════════
; Format: position,repeatCount
; position: 1-9, 0 (where 0 = 10th position)
; repeatCount: how many times to press (1 = first window, 2 = second window of same app)

ExecuteTaskbarActivate(param) {
    global g_Settings

    if param = "" || !InStr(param, ",") {
        ShowStatus("Taskbar format: position,count (e.g. 5,2)", "fail")
        return false
    }

    ; Strip any description text
    if InStr(param, "  ")
        param := Trim(SubStr(param, 1, InStr(param, "  ") - 1))

    parts := StrSplit(param, ",")
    if parts.Length < 2 {
        ShowStatus("Taskbar needs: position,count", "fail")
        return false
    }

    position := Integer(Trim(parts[1]))
    repeatCount := Integer(Trim(parts[2]))

    if position < 0 || position > 10 {
        ShowStatus("Position must be 0-10", "fail")
        return false
    }

    ; Convert position to key (0 = 10th position)
    keyNum := position = 10 ? "0" : String(position)

    ShowStatus("Taskbar: Win+" . keyNum . " x" . repeatCount, "wait")

    Sleep(g_Settings["PreActionDelay"])

    ; Press Win+N repeatedly
    Send("{LWin down}")
    Sleep(50)

    Loop repeatCount {
        Send(keyNum)
        if A_Index < repeatCount
            Sleep(150)  ; Delay between presses to allow window switching
    }

    Sleep(50)
    Send("{LWin up}")

    Sleep(g_Settings["PostActionDelay"])

    ShowStatus("Activated: Win+" . keyNum . " x" . repeatCount, "ok")
    return true
}


; ═══════════════════════════════════════════════════════════════════════════════
; TRAY MENU
; ═══════════════════════════════════════════════════════════════════════════════
; TRAY MENU
; =============================================================================

;A_TrayMenu.Delete()
A_TrayMenu.Add("Show/Hide", TrayShowHide)
A_TrayMenu.Add()
A_TrayMenu.Add("Definition Mode Help", (*) => MsgBoxTop("CAPSLOCK toggles Definition Mode`n`nWhen ON, use keyboard to add steps:`nC=Click, D=Drag (2x), R=Right Click`nT=Triple, P=Pattern, W=Wait`nK=Keys, M=Menu, ESC=Cancel", "Definition Mode"))
A_TrayMenu.Add()
A_TrayMenu.Add("Always On Top", TrayToggleOnTop)
A_TrayMenu.Add()
A_TrayMenu.Add("ABORT", AbortSequence)
A_TrayMenu.Add("Reload", (*) => Reload())
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Show/Hide"
A_IconTip := "Macro Automator v2.9.6"

TrayShowHide(*) {
    global g_GuiVisible, MainGui
    g_GuiVisible := !g_GuiVisible
    g_GuiVisible ? MainGui.Show() : MainGui.Hide()
}

TrayToggleOnTop(*) {
    global g_AlwaysOnTop, MainGui, OnTopCheck
    g_AlwaysOnTop := !g_AlwaysOnTop
    WinSetAlwaysOnTop(g_AlwaysOnTop, MainGui)
    try OnTopCheck.Value := g_AlwaysOnTop
    g_AlwaysOnTop ? A_TrayMenu.Check("Always On Top") : A_TrayMenu.Uncheck("Always On Top")
}

AbortSequence(*) {
    global g_AbortSequence
    g_AbortSequence := true
    ShowTooltipTimed("ABORTED!", 2000)
}


; ═══════════════════════════════════════════════════════════════════════════════
; MARKER
; ═══════════════════════════════════════════════════════════════════════════════
; MARKER
; =============================================================================

global MarkerGui := ""

ShowMarker(x, y, duration := 1500, color := "Red") {
    global MarkerGui, g_Settings

    ; Clean up any existing marker
    try {
        if IsObject(MarkerGui)
            MarkerGui.Destroy()
    }
    MarkerGui := ""

    ; Create new marker GUI with error handling
    try {
        MarkerGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
        MarkerGui.BackColor := "FFFFFF"
        WinSetTransColor("FFFFFF", MarkerGui)
        MarkerGui.SetFont("s20 bold", "Arial")
        MarkerGui.Add("Text", "c" . color . " Center", "X")

        ; Calculate position with settings
        posX := x + (g_Settings.Has("MarkerOffsetX") ? g_Settings["MarkerOffsetX"] : 0) - 8
        posY := y + (g_Settings.Has("MarkerOffsetY") ? g_Settings["MarkerOffsetY"] : 0) - 10

        MarkerGui.Show("x" . posX . " y" . posY . " NA")
        SetTimer(HideMarker, -duration)
    } catch as err {
        ; Silently fail if marker can't be shown
        MarkerGui := ""
    }
}

HideMarker() {
    global MarkerGui
    try {
        if IsObject(MarkerGui)
            MarkerGui.Destroy()
    }
    MarkerGui := ""
}


; ═══════════════════════════════════════════════════════════════════════════════
; DATA PERSISTENCE
; ═══════════════════════════════════════════════════════════════════════════════
; DATA PERSISTENCE
; =============================================================================

SaveCoordinates() {
    global g_Coordinates, COORDS_FILE
    try {
        file := FileOpen(COORDS_FILE, "w", "UTF-8")
        file.WriteLine("Name,X,Y,EndX,EndY,Type")
        for name, c in g_Coordinates
            file.WriteLine(name . "," . c["x"] . "," . c["y"] . "," . c["endX"] . "," . c["endY"] . "," . c["type"])
        file.Close()
    }
}

LoadCoordinates() {
    global g_Coordinates, COORDS_FILE
    if !FileExist(COORDS_FILE)
        return
    g_Coordinates := Map()
    lineNum := 0
    Loop Read COORDS_FILE {
        lineNum++
        if lineNum = 1 || A_LoopReadLine = ""
            continue
        p := StrSplit(A_LoopReadLine, ",")
        if p.Length >= 6
            g_Coordinates[p[1]] := Map("x", Integer(p[2]), "y", Integer(p[3]), "endX", p[4] = "" ? "" : Integer(p[4]), "endY", p[5] = "" ? "" : Integer(p[5]), "type", p[6])
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; SQLITE PERSISTENCE (patterns, sequences, spools, OCR log)
; ═══════════════════════════════════════════════════════════════════════════════

InitDB() {
    global g_DB, DB_FILE, DATA_DIR

    if !DirExist(DATA_DIR)
        DirCreate(DATA_DIR)

    g_DB := SQLiteDB()
    if !g_DB.OpenDB(DB_FILE) {
        MsgBoxTop("Failed to open database:`n" . g_DB.ErrorMsg . "`n`nData will not be saved this session.", "Database Error")
        return
    }

    if !g_DB.Exec("CREATE TABLE IF NOT EXISTS patterns (name TEXT PRIMARY KEY, text TEXT, desc TEXT, screenshot TEXT, captureX INTEGER, captureY INTEGER, captureWindow TEXT, qualifier TEXT);")
        MsgBoxTop("Failed to create patterns table:`n" . g_DB.ErrorMsg, "Database Error")
    if !g_DB.Exec("CREATE TABLE IF NOT EXISTS sequences (name TEXT PRIMARY KEY, speed REAL);")
        MsgBoxTop("Failed to create sequences table:`n" . g_DB.ErrorMsg, "Database Error")
    if !g_DB.Exec("CREATE TABLE IF NOT EXISTS sequence_steps (seq_name TEXT, step_index INTEGER, action TEXT, target TEXT, param TEXT, enabled INTEGER, failsafe TEXT, PRIMARY KEY (seq_name, step_index));")
        MsgBoxTop("Failed to create sequence_steps table:`n" . g_DB.ErrorMsg, "Database Error")
    if !g_DB.Exec("CREATE TABLE IF NOT EXISTS spools (name TEXT PRIMARY KEY, enabled INTEGER, region TEXT, regionCoords TEXT, detectType TEXT, target TEXT, interval INTEGER, condition TEXT, action TEXT, actionTarget TEXT, extractOCR INTEGER, ocrVar TEXT, autoComplete INTEGER, completion TEXT, completionTarget TEXT, timeout INTEGER, mode TEXT, cooldown INTEGER, notifTime INTEGER);")
        MsgBoxTop("Failed to create spools table:`n" . g_DB.ErrorMsg, "Database Error")
    if !g_DB.Exec("CREATE TABLE IF NOT EXISTS ocr_log (id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT, text TEXT, word_count INTEGER);")
        MsgBoxTop("Failed to create ocr_log table:`n" . g_DB.ErrorMsg, "Database Error")

    ; Migrate older databases without discarding any saved workflows.
    EnsureDBColumn("sequences", "hotkey", "TEXT")
    EnsureDBColumn("sequences", "hotstring", "TEXT")
    EnsureDBColumn("sequence_steps", "qual_pattern", "TEXT")
    EnsureDBColumn("sequence_steps", "qual_window", "TEXT")

    ; One-time import from legacy .ini files if the DB tables are still empty,
    ; so existing pattern/sequence/spool data isn't lost on upgrade.
    ImportLegacyIniIfEmpty()
}

; Escapes a value for safe inline use in a single-quoted SQLite string literal.
SQLQuote(val) {
    return "'" . StrReplace(String(val), "'", "''") . "'"
}

EnsureDBColumn(tableName, columnName, columnDefinition) {
    global g_DB
    if !IsObject(g_DB)
        return false
    if !g_DB.GetTable("PRAGMA table_info(" . tableName . ");", &tb)
        return false
    row := ""
    Loop tb.RowCount {
        tb.GetRow(A_Index, &row)
        if row[2] = columnName
            return true
    }
    if !g_DB.Exec("ALTER TABLE " . tableName . " ADD COLUMN " . columnName . " " . columnDefinition . ";") {
        MsgBoxTop("Failed to update database column " . tableName . "." . columnName . ":`n" . g_DB.ErrorMsg, "Database Migration Error")
        return false
    }
    return true
}

ImportLegacyIniIfEmpty() {
    global g_DB, PATTERNS_FILE, SEQUENCES_FILE, SPOOLS_FILE

    if !IsObject(g_DB)
        return

    patternCount := 0
    if g_DB.GetTable("SELECT COUNT(*) FROM patterns;", &tb) && tb.RowCount
        patternCount := Integer(tb.Rows[1][1])
    if patternCount = 0 && FileExist(PATTERNS_FILE) {
        for section in StrSplit(IniRead(PATTERNS_FILE), "`n") {
            if section = ""
                continue
            text := IniRead(PATTERNS_FILE, section, "Text", "")
            if text = ""
                continue
            g_DB.Exec("INSERT OR REPLACE INTO patterns (name, text, desc, screenshot, captureX, captureY, captureWindow, qualifier) VALUES ("
                . SQLQuote(section) . ", " . SQLQuote(text) . ", "
                . SQLQuote(IniRead(PATTERNS_FILE, section, "Desc", "")) . ", "
                . SQLQuote(IniRead(PATTERNS_FILE, section, "Screenshot", "")) . ", "
                . Integer(IniRead(PATTERNS_FILE, section, "CaptureX", 0)) . ", "
                . Integer(IniRead(PATTERNS_FILE, section, "CaptureY", 0)) . ", "
                . SQLQuote(IniRead(PATTERNS_FILE, section, "CaptureWindow", "")) . ", "
                . SQLQuote(IniRead(PATTERNS_FILE, section, "Qualifier", "")) . ");")
        }
    }

    seqCount := 0
    if g_DB.GetTable("SELECT COUNT(*) FROM sequences;", &tb) && tb.RowCount
        seqCount := Integer(tb.Rows[1][1])
    if seqCount = 0 && FileExist(SEQUENCES_FILE) {
        for section in StrSplit(IniRead(SEQUENCES_FILE), "`n") {
            if section = ""
                continue
            count := IniRead(SEQUENCES_FILE, section, "_Count", 0)
            if count = 0
                continue
            speed := IniRead(SEQUENCES_FILE, section, "_Speed", 1.0)
            g_DB.Exec("INSERT OR REPLACE INTO sequences (name, speed) VALUES (" . SQLQuote(section) . ", " . Float(speed) . ");")
            Loop count {
                data := IniRead(SEQUENCES_FILE, section, "Step" . A_Index, "")
                if data = ""
                    continue
                p := StrSplit(data, "|")
                fsData := IniRead(SEQUENCES_FILE, section, "Failsafe" . A_Index, "")
                g_DB.Exec("INSERT OR REPLACE INTO sequence_steps (seq_name, step_index, action, target, param, enabled, failsafe) VALUES ("
                    . SQLQuote(section) . ", " . A_Index . ", "
                    . SQLQuote(p[1]) . ", " . SQLQuote(p.Length >= 2 ? p[2] : "") . ", " . SQLQuote(p.Length >= 3 ? p[3] : "") . ", "
                    . (p.Length >= 4 ? Integer(p[4]) : 1) . ", " . SQLQuote(fsData) . ");")
            }
        }
    }

    spoolCount := 0
    if g_DB.GetTable("SELECT COUNT(*) FROM spools;", &tb) && tb.RowCount
        spoolCount := Integer(tb.Rows[1][1])
    if spoolCount = 0 && FileExist(SPOOLS_FILE) {
        for section in StrSplit(IniRead(SPOOLS_FILE), "`n") {
            if section = ""
                continue
            g_DB.Exec("INSERT OR REPLACE INTO spools (name, enabled, region, regionCoords, detectType, target, interval, condition, action, actionTarget, extractOCR, ocrVar, autoComplete, completion, completionTarget, timeout, mode, cooldown, notifTime) VALUES ("
                . SQLQuote(section) . ", "
                . Integer(IniRead(SPOOLS_FILE, section, "Enabled", 1)) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "Region", "Full Screen")) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "RegionCoords", "")) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "DetectType", "Pattern Match")) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "Target", "")) . ", "
                . Integer(IniRead(SPOOLS_FILE, section, "Interval", 500)) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "Condition", "Found")) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "Action", "Show Notification")) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "ActionTarget", "")) . ", "
                . Integer(IniRead(SPOOLS_FILE, section, "ExtractOCR", 0)) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "OCRVar", "")) . ", "
                . Integer(IniRead(SPOOLS_FILE, section, "AutoComplete", 0)) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "Completion", "Pattern Found")) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "CompletionTarget", "")) . ", "
                . Integer(IniRead(SPOOLS_FILE, section, "Timeout", 0)) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "Mode", "Continuous")) . ", "
                . Integer(IniRead(SPOOLS_FILE, section, "Cooldown", 5)) . ", "
                . Integer(IniRead(SPOOLS_FILE, section, "NotifTime", 5)) . ");")
        }
    }
}

SavePatterns() {
    global g_Patterns, g_DB
    if !IsObject(g_DB)
        return
    g_DB.Exec("DELETE FROM patterns;")
    for name, data in g_Patterns {
        g_DB.Exec("INSERT OR REPLACE INTO patterns (name, text, desc, screenshot, captureX, captureY, captureWindow, qualifier) VALUES ("
            . SQLQuote(name) . ", "
            . SQLQuote(data["text"]) . ", "
            . SQLQuote(data.Has("desc") ? data["desc"] : "") . ", "
            . SQLQuote(data.Has("screenshot") ? data["screenshot"] : "") . ", "
            . Integer(data.Has("captureX") ? data["captureX"] : 0) . ", "
            . Integer(data.Has("captureY") ? data["captureY"] : 0) . ", "
            . SQLQuote(data.Has("captureWindow") ? data["captureWindow"] : "") . ", "
            . SQLQuote(data.Has("qualifier") ? data["qualifier"] : "") . ");")
    }
}

LoadPatterns() {
    global g_Patterns, g_DB
    g_Patterns := Map()
    if !IsObject(g_DB)
        return
    if !g_DB.GetTable("SELECT name, text, desc, screenshot, captureX, captureY, captureWindow, qualifier FROM patterns;", &tb)
        return
    row := ""
    Loop tb.RowCount {
        tb.GetRow(A_Index, &row)
        if row[2] != ""
            g_Patterns[row[1]] := Map(
                "text", row[2],
                "desc", row[3],
                "screenshot", row[4],
                "captureX", Integer(row[5]),
                "captureY", Integer(row[6]),
                "captureWindow", row[7],
                "qualifier", row[8]
            )
    }
}

SaveSequences(showError := false) {
    global g_Sequences, g_DB, g_LastWorkflowSaveError
    g_LastWorkflowSaveError := ""
    if !IsObject(g_DB) {
        g_LastWorkflowSaveError := "The workflow database is not open."
        return false
    }

    try {
        DBExecOrThrow("BEGIN IMMEDIATE;")
        ; Delete children first. The transaction guarantees the old data survives
        ; if any serialization or insert fails.
        DBExecOrThrow("DELETE FROM sequence_steps;")
        DBExecOrThrow("DELETE FROM sequences;")

        for seqName, seqData in g_Sequences {
            speed := seqData.Has("speed") ? seqData["speed"] : 1.0
            hotkey := seqData.Has("hotkey") ? seqData["hotkey"] : ""
            hotstring := seqData.Has("hotstring") ? seqData["hotstring"] : ""
            DBExecOrThrow("INSERT INTO sequences (name, speed, hotkey, hotstring) VALUES ("
                . SQLQuote(seqName) . ", " . Float(speed) . ", " . SQLQuote(hotkey) . ", " . SQLQuote(hotstring) . ");")

            steps := seqData.Has("steps") ? seqData["steps"] : []
            for i, step in steps {
                fs := step.Has("failsafe") ? NormalizeStepFailsafe(step["failsafe"]) : Map()
                fsStr := fs.Count > 0 ? SerializeFailsafe(fs) : ""
                qualPattern := step.Has("qualPattern") ? step["qualPattern"] : ""
                qualWindow := step.Has("qualWindow") ? step["qualWindow"] : ""
                DBExecOrThrow("INSERT INTO sequence_steps (seq_name, step_index, action, target, param, enabled, failsafe, qual_pattern, qual_window) VALUES ("
                    . SQLQuote(seqName) . ", " . i . ", "
                    . SQLQuote(step.Has("action") ? step["action"] : "") . ", "
                    . SQLQuote(step.Has("target") ? step["target"] : "") . ", "
                    . SQLQuote(step.Has("param") ? step["param"] : "") . ", "
                    . (step.Has("enabled") ? Integer(step["enabled"]) : 1) . ", "
                    . SQLQuote(fsStr) . ", " . SQLQuote(qualPattern) . ", " . SQLQuote(qualWindow) . ");")
            }
        }
        DBExecOrThrow("COMMIT;")
        return true
    } catch as err {
        try g_DB.Exec("ROLLBACK;")
        g_LastWorkflowSaveError := err.Message
        if showError
            MsgBoxTop("Workflows could not be saved. Your previous database contents were kept intact.`n`n" . err.Message, "Workflow Save Error")
        return false
    }
}

DBExecOrThrow(sql) {
    global g_DB
    if !g_DB.Exec(sql)
        throw Error(g_DB.ErrorMsg != "" ? g_DB.ErrorMsg : "SQLite operation failed.")
}

; Serialize failsafe map to string
SerializeFailsafe(fs) {
    parts := []
    for key, val in fs {
        if val != "" && val != 0
            parts.Push(key . "=" . String(val))
    }
    return StrJoin(parts, ";")
}

; Deserialize failsafe string to map
DeserializeFailsafe(str) {
    fs := Map()
    if str = ""
        return fs
    for part in StrSplit(str, ";") {
        eq := InStr(part, "=")
        if eq > 0 {
            key := SubStr(part, 1, eq - 1)
            val := SubStr(part, eq + 1)
            ; Try to convert to number
            if IsNumber(val)
                fs[key] := Number(val)
            else
                fs[key] := val
        }
    }
    return fs
}

NormalizeStepFailsafe(value) {
    if value is Map
        return value
    if Type(value) = "String" {
        if value = "close_button"
            return Map("checkCloseBtn", 1)
        return DeserializeFailsafe(value)
    }
    return Map()
}

LoadSequences() {
    global g_Sequences, g_DB
    g_Sequences := Map()
    if !IsObject(g_DB)
        return
    if !g_DB.GetTable("SELECT name, speed, hotkey, hotstring FROM sequences ORDER BY name;", &tbSeq)
        return
    row := ""
    Loop tbSeq.RowCount {
        tbSeq.GetRow(A_Index, &row)
        seqName := row[1]
        speed := row[2]
        steps := []
        if g_DB.GetTable("SELECT action, target, param, enabled, failsafe, qual_pattern, qual_window FROM sequence_steps WHERE seq_name = " . SQLQuote(seqName) . " ORDER BY step_index;", &tbSteps) {
            stepRow := ""
            Loop tbSteps.RowCount {
                tbSteps.GetRow(A_Index, &stepRow)
                step := Map("action", stepRow[1], "target", stepRow[2], "param", stepRow[3], "enabled", Integer(stepRow[4]))
                if stepRow[5] != ""
                    step["failsafe"] := DeserializeFailsafe(stepRow[5])
                if stepRow[6] != ""
                    step["qualPattern"] := stepRow[6]
                if stepRow[7] != ""
                    step["qualWindow"] := stepRow[7]
                steps.Push(step)
            }
        }
        seqData := Map("steps", steps, "speed", Float(speed))
        if row[3] != ""
            seqData["hotkey"] := row[3]
        if row[4] != ""
            seqData["hotstring"] := row[4]
        g_Sequences[seqName] := seqData
    }
}


; ═══════════════════════════════════════════════════════════════════════════════
; SPOOL SYSTEM - EVENT-DRIVEN AUTOMATION
; ═══════════════════════════════════════════════════════════════════════════════
; SPOOL SYSTEM - Event-Driven Automation

; ═══════════════════════════════════════════════════════════════════════════════
; SPOOLS CONTINUOUSLY MONITOR SCREEN REGIONS AND TRIGGER WORKFLOWS/ACTIONS
; ═══════════════════════════════════════════════════════════════════════════════
; Spools continuously monitor screen regions and trigger workflows/actions
; when specific conditions are detected (patterns, OCR text, pixel changes)

SaveSpools() {
    global g_Spools, g_DB
    if !IsObject(g_DB)
        return
    g_DB.Exec("DELETE FROM spools;")
    for name, spool in g_Spools {
        g_DB.Exec("INSERT OR REPLACE INTO spools (name, enabled, region, regionCoords, detectType, target, interval, condition, action, actionTarget, extractOCR, ocrVar, autoComplete, completion, completionTarget, timeout, mode, cooldown, notifTime) VALUES ("
            . SQLQuote(name) . ", "
            . Integer(spool["enabled"]) . ", "
            . SQLQuote(spool["region"]) . ", "
            . SQLQuote(spool["regionCoords"]) . ", "
            . SQLQuote(spool["detectType"]) . ", "
            . SQLQuote(spool["target"]) . ", "
            . Integer(spool["interval"]) . ", "
            . SQLQuote(spool["condition"]) . ", "
            . SQLQuote(spool["action"]) . ", "
            . SQLQuote(spool["actionTarget"]) . ", "
            . Integer(spool["extractOCR"]) . ", "
            . SQLQuote(spool["ocrVar"]) . ", "
            . Integer(spool["autoComplete"]) . ", "
            . SQLQuote(spool["completion"]) . ", "
            . SQLQuote(spool["completionTarget"]) . ", "
            . Integer(spool["timeout"]) . ", "
            . SQLQuote(spool.Has("mode") ? spool["mode"] : "Continuous") . ", "
            . Integer(spool.Has("cooldown") ? spool["cooldown"] : 5) . ", "
            . Integer(spool.Has("notifTime") ? spool["notifTime"] : 5) . ");")
    }
}

LoadSpools() {
    global g_Spools, g_DB
    g_Spools := Map()
    if !IsObject(g_DB)
        return
    if !g_DB.GetTable("SELECT name, enabled, region, regionCoords, detectType, target, interval, condition, action, actionTarget, extractOCR, ocrVar, autoComplete, completion, completionTarget, timeout, mode, cooldown, notifTime FROM spools;", &tb)
        return
    row := ""
    Loop tb.RowCount {
        tb.GetRow(A_Index, &row)
        g_Spools[row[1]] := Map(
            "enabled", Integer(row[2]),
            "region", row[3],
            "regionCoords", row[4],
            "detectType", row[5],
            "target", row[6],
            "interval", Integer(row[7]),
            "condition", row[8],
            "action", row[9],
            "actionTarget", row[10],
            "extractOCR", Integer(row[11]),
            "ocrVar", row[12],
            "autoComplete", Integer(row[13]),
            "completion", row[14],
            "completionTarget", row[15],
            "timeout", Integer(row[16]),
            "mode", row[17],
            "cooldown", Integer(row[18]),
            "notifTime", Integer(row[19])
        )
    }
}

; --- Spool UI Functions ---

ToggleSpoolMaster(*) {
    global g_SpoolMasterEnabled, SpoolMasterToggle
    g_SpoolMasterEnabled := SpoolMasterToggle.Value
    UpdateSpoolMasterStatus()

    if g_SpoolMasterEnabled {
        StartEnabledSpools()
    } else {
        StopAllSpools()
    }
}

UpdateSpoolMasterStatus() {
    global g_SpoolMasterEnabled, g_ActiveSpools
    try {
        ctrl := MainGui["SpoolMasterStatus"]
        if g_SpoolMasterEnabled {
            ctrl.Value := "RUNNING"
            ctrl.Opt("cGreen")
        } else {
            ctrl.Value := "STOPPED"
            ctrl.Opt("cRed")
        }

        MainGui["ActiveSpoolCount"].Value := "Active: " . g_ActiveSpools.Count
    }
}

StartAllSpools(*) {
    global g_SpoolMasterEnabled, SpoolMasterToggle
    g_SpoolMasterEnabled := true
    SpoolMasterToggle.Value := 1
    StartEnabledSpools()
    UpdateSpoolMasterStatus()
    SpoolLogAdd("All spools started")
}

StopAllSpools(*) {
    global g_ActiveSpools, g_SpoolMasterEnabled

    for name, timer in g_ActiveSpools {
        SetTimer(timer, 0)
    }
    g_ActiveSpools := Map()

    UpdateSpoolMasterStatus()
    RefreshSpoolLV()
    SpoolLogAdd("All spools stopped")
}

StartEnabledSpools() {
    global g_Spools, g_SpoolMasterEnabled

    if !g_SpoolMasterEnabled
        return

    for name, spool in g_Spools {
        if spool["enabled"]
            StartSpool(name)
    }
}

StartSpool(name) {
    global g_Spools, g_ActiveSpools, g_SpoolMasterEnabled

    if !g_SpoolMasterEnabled
        return

    if !g_Spools.Has(name)
        return

    spool := g_Spools[name]

    ; Stop if already running
    if g_ActiveSpools.Has(name) {
        SetTimer(g_ActiveSpools[name], 0)
    }

    ; Create timer function for this spool
    timerFunc := SpoolTimerFactory(name)
    g_ActiveSpools[name] := timerFunc

    ; Start timer
    SetTimer(timerFunc, spool["interval"])

    SpoolLogAdd("Started: " . name)
    RefreshSpoolLV()
    UpdateSpoolMasterStatus()
}

StopSpool(name) {
    global g_ActiveSpools

    if g_ActiveSpools.Has(name) {
        SetTimer(g_ActiveSpools[name], 0)
        g_ActiveSpools.Delete(name)
        SpoolLogAdd("Stopped: " . name)
        RefreshSpoolLV()
        UpdateSpoolMasterStatus()
    }
}

; Factory to create timer function for each spool
SpoolTimerFactory(spoolName) {
    return (*) => ExecuteSpoolCheck(spoolName)
}

; Main spool check function - runs on timer
ExecuteSpoolCheck(name, forceTest := false) {
    global g_Spools, g_SpoolVariables, g_Settings, g_SpoolScreenCache, g_SpoolCooldown, g_ActiveSpools
    static screenCache := Map()  ; Cache for screen change detection

    if !g_Spools.Has(name)
        return

    spool := g_Spools[name]

    ; Check if spool is in cooldown (unless force testing)
    if !forceTest && IsSpoolInCooldown(name) {
        return  ; Skip this check, in cooldown
    }

    ; Get search region
    region := GetSpoolRegion(spool)

    ; Perform detection based on type
    detected := false
    detectedValue := ""

    switch spool["detectType"] {
        case "Pattern Match":
            detected := SpoolDetectPattern(spool["target"], region, spool["condition"])

        case "Pattern Sequence":
            ; All patterns in comma-separated list must be found
            detected := SpoolDetectPatternSequence(spool["target"], region)
            if spool["condition"] = "Not Found"
                detected := !detected

        case "OCR Contains":
            ; Use Windows UWP OCR library
            result := SpoolDetectOCRWindows(region, spool["target"], false)
            if result["text"] != "" {
                detectedValue := result["text"]
                detected := result["found"]
                if spool["condition"] = "Not Found"
                    detected := !detected
            }

        case "OCR Regex":
            ; Use Windows UWP OCR library with regex
            result := SpoolDetectOCRWindows(region, spool["target"], true)
            if result["text"] != "" {
                detectedValue := result["text"]
                detected := result["found"]
                if spool["condition"] = "Not Found"
                    detected := !detected
            }

        case "Pixel Change", "Screen Changed":
            ; Detect if screen region has changed since last check
            detected := SpoolDetectScreenChange(name, region)

        case "Window Title":
            activeTitle := ""
            try activeTitle := WinGetTitle("A")
            detected := InStr(activeTitle, spool["target"])
            if spool["condition"] = "Not Found"
                detected := !detected
    }

    ; If detected, execute action
    if detected {
        SpoolLogAdd("TRIGGERED: " . name)

        ; Extract OCR to variable if requested
        if spool["extractOCR"] && spool["ocrVar"] != "" && detectedValue != "" {
            g_SpoolVariables[spool["ocrVar"]] := detectedValue
            RefreshOCRVarsLV()
        }

        ; Execute action (pass spool name for cooldown tracking)
        ExecuteSpoolAction(spool, name)

        ; Handle behavior mode
        mode := spool.Has("mode") ? spool["mode"] : "Continuous"
        cooldown := spool.Has("cooldown") ? spool["cooldown"] : 5

        switch mode {
            case "One-Shot":
                ; Stop this spool after first trigger
                SpoolLogAdd("One-Shot complete, stopping: " . name)
                StopSpool(name)

            case "Cooldown":
                ; Set cooldown period before re-triggering
                g_SpoolCooldown[name] := A_TickCount + (cooldown * 1000)
                SpoolLogAdd("Cooldown " . cooldown . "s: " . name)

            case "Continuous":
                ; No special handling - just keeps running
                ; But if action was Show Notification, we already set cooldown there
        }

        ; Check auto-completion conditions
        if spool["autoComplete"] {
            timeout := spool.Has("timeout") ? spool["timeout"] : 0
            if timeout > 0 {
                ; Set up auto-stop timer
                stopFunc := (*) => StopSpool(name)
                SetTimer(stopFunc, -timeout * 1000)
                SpoolLogAdd("Auto-stop in " . timeout . "s: " . name)
            }
        }
    }
}

; Get region coordinates for spool
GetSpoolRegion(spool) {
    region := Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)

    switch spool["region"] {
        case "Custom Region":
            if spool["regionCoords"] != "" {
                coords := StrSplit(spool["regionCoords"], ",")
                if coords.Length >= 4 {
                    region["x1"] := Integer(coords[1])
                    region["y1"] := Integer(coords[2])
                    region["x2"] := Integer(coords[3])
                    region["y2"] := Integer(coords[4])
                }
            }
        case "Active Window":
            try {
                hwnd := WinExist("A")
                WinGetPos(&x, &y, &w, &h, hwnd)
                region["x1"] := x
                region["y1"] := y
                region["x2"] := x + w
                region["y2"] := y + h
            }
    }

    return region
}

; Detect pattern in region
SpoolDetectPattern(patternName, region, condition) {
    global g_Patterns, g_Settings

    if !g_Patterns.Has(patternName)
        return false

    code := g_Patterns[patternName]["text"]
    tolerance := g_Settings["FindTextTolerance"]

    ok := FindText(&outX, &outY, region["x1"], region["y1"], region["x2"], region["y2"],
                   tolerance, tolerance, code)

    found := (ok && ok.Length > 0)

    if condition = "Not Found"
        return !found
    return found
}

; Perform OCR on region
SpoolDetectOCR(region) {
    result := Map("success", false, "text", "")

    try {
        ; Use FindText's OCR capability
        ; This captures the region and converts to text
        text := FindText().OCR(region["x1"], region["y1"], region["x2"], region["y2"])
        if text != "" {
            result["success"] := true
            result["text"] := text
        }
    }

    return result
}

; Detect multiple patterns (all must be present)
; Target format: "Pattern1,Pattern2,Pattern3"
SpoolDetectPatternSequence(targetPatterns, region) {
    global g_Patterns, g_Settings

    ; Split comma-separated pattern names
    patternList := StrSplit(targetPatterns, ",")

    ; Each pattern must be found
    for patternName in patternList {
        patternName := Trim(patternName)
        if patternName = "" || patternName = "(Enter comma-separated patterns)"
            continue

        if !g_Patterns.Has(patternName)
            return false  ; Unknown pattern

        code := g_Patterns[patternName]["text"]
        tolerance := g_Settings["FindTextTolerance"]

        ok := FindText(&outX, &outY, region["x1"], region["y1"], region["x2"], region["y2"],
                       tolerance, tolerance, code)

        if !ok || ok.Length = 0
            return false  ; Pattern not found, sequence fails
    }

    return true  ; All patterns found
}

; Detect if screen region has changed since last check
; Uses a simple hash of pixel samples to detect changes
SpoolDetectScreenChange(spoolName, region) {
    static screenCache := Map()

    ; Sample pixels from region to create a simple hash
    ; We sample 16 points in a 4x4 grid
    currentHash := ""

    stepX := (region["x2"] - region["x1"]) // 5
    stepY := (region["y2"] - region["y1"]) // 5

    if stepX < 1
        stepX := 1
    if stepY < 1
        stepY := 1

    Loop 4 {
        y := region["y1"] + (A_Index * stepY)
        Loop 4 {
            x := region["x1"] + (A_Index * stepX)
            try {
                color := PixelGetColor(x, y)
                currentHash .= color . "|"
            }
        }
    }

    ; Compare with cached hash
    if screenCache.Has(spoolName) {
        previousHash := screenCache[spoolName]
        screenCache[spoolName] := currentHash  ; Update cache

        ; If hash changed, screen changed
        if previousHash != currentHash
            return true
    } else {
        ; First run, just cache the hash
        screenCache[spoolName] := currentHash
    }

    return false
}

; Execute spool action
ExecuteSpoolAction(spool, spoolName := "") {
    global g_Sequences, g_SpoolVariables

    switch spool["action"] {
        case "Run Workflow":
            if g_Sequences.Has(spool["actionTarget"]) {
                speed := g_Sequences[spool["actionTarget"]].Has("speed") ? g_Sequences[spool["actionTarget"]]["speed"] : 1.0
                ExecuteSequenceVerified(g_Sequences[spool["actionTarget"]]["steps"], speed)
            }

        case "Show Notification":
            ; Pass spool name for cooldown tracking
            ShowSpoolNotification(spool["actionTarget"], spool, spoolName)

        case "Start Spool":
            StartSpool(spool["actionTarget"])

        case "Stop Spool":
            StopSpool(spool["actionTarget"])

        case "Extract OCR":
            ; OCR extraction handled in ExecuteSpoolCheck

        case "Set Variable":
            ; Parse "varName=value"
            if InStr(spool["actionTarget"], "=") {
                parts := StrSplit(spool["actionTarget"], "=", , 2)
                g_SpoolVariables[parts[1]] := parts[2]
                RefreshOCRVarsLV()
            }

        case "Key Chord":
            ExecuteKeyChord(spool["actionTarget"])

        case "Run Program":
            try Run(spool["actionTarget"])
    }
}

; Show always-on-top notification
ShowSpoolNotification(title, spool := "", spoolName := "") {
    global g_SpoolNotifications, g_NotificationCounter, g_NotificationDefaults, g_SpoolCooldown

    g_NotificationCounter++
    id := g_NotificationCounter

    ; Get display time from spool's notifTime field, then timeout, then default
    timeout := g_NotificationDefaults["timeout"]  ; Default 5 seconds
    if IsObject(spool) {
        if spool.Has("notifTime") && spool["notifTime"] > 0
            timeout := spool["notifTime"]
        else if spool.Has("timeout") && spool["timeout"] > 0
            timeout := spool["timeout"]
    }

    ; Create notification GUI
    notifGui := Gui("+AlwaysOnTop +ToolWindow -Caption", "SpoolNotif" . id)
    notifGui.BackColor := "1a1a2e"
    notifGui.SetFont("s10 cWhite", "Segoe UI")

    ; Position in lower right, stack upwards
    x := A_ScreenWidth - 320
    y := A_ScreenHeight - 120 - (g_SpoolNotifications.Length * 95)

    notifGui.Add("Text", "x10 y10 w250 cYellow", "🔔 " . title)

    ; Show spool name if available
    sourceText := spoolName != "" ? "From: " . spoolName : "Triggered by spool detection"
    notifGui.Add("Text", "x10 y32 w250 c16c79a", sourceText)

    ; Show countdown timer
    timeText := notifGui.Add("Text", "x10 y52 w100 cGray", FormatTime(, "HH:mm:ss"))
    countdownText := notifGui.Add("Text", "x200 y52 w60 cFF8800 Right", timeout . "s")

    closeBtn := notifGui.Add("Button", "x265 y5 w25 h20", "X")
    closeBtn.OnEvent("Click", (*) => DismissNotification(id, notifGui))

    notifGui.Show("x" . x . " y" . y . " w300 h75 NoActivate")
    WinSetTransparent(230, notifGui)

    ; Store reference
    notifData := Map(
        "id", id,
        "gui", notifGui,
        "title", title,
        "time", A_Now,
        "timeout", timeout,
        "spoolName", spoolName,
        "countdownCtrl", countdownText,
        "remaining", timeout
    )
    g_SpoolNotifications.Push(notifData)

    ; Set cooldown for the spool ONLY if in Continuous mode and pauseSpools is enabled
    ; (Other modes handle their own cooldown logic in ExecuteSpoolCheck)
    if spoolName != "" && g_NotificationDefaults["pauseSpools"] {
        if IsObject(spool) && (!spool.Has("mode") || spool["mode"] = "Continuous") {
            g_SpoolCooldown[spoolName] := A_TickCount + (timeout * 1000)
        }
    }

    RefreshNotificationLV()

    ; Start countdown timer (updates display every second)
    countdownFunc := NotificationCountdownFactory(id)
    SetTimer(countdownFunc, 1000)

    ; Auto-dismiss after timeout - this ALWAYS fires
    dismissFunc := (*) => DismissNotification(id, notifGui)
    SetTimer(dismissFunc, -timeout * 1000)

    SpoolLogAdd("Notification: " . title . " (" . timeout . "s)")

    return id
}

; Factory to create countdown function for each notification
NotificationCountdownFactory(notifId) {
    return (*) => UpdateNotificationCountdown(notifId)
}

; Update countdown display on notification
UpdateNotificationCountdown(id) {
    global g_SpoolNotifications

    foundNotif := ""
    for notif in g_SpoolNotifications {
        if notif["id"] = id {
            foundNotif := notif
            break
        }
    }

    if !IsObject(foundNotif) {
        ; Notification was dismissed - stop this timer
        SetTimer(NotificationCountdownFactory(id), 0)
        return
    }

    foundNotif["remaining"]--

    if foundNotif["remaining"] >= 0 {
        try foundNotif["countdownCtrl"].Value := foundNotif["remaining"] . "s"
    }

    if foundNotif["remaining"] <= 0 {
        ; Stop countdown timer (dismiss timer will handle cleanup)
        SetTimer(NotificationCountdownFactory(id), 0)
    }
}

; DismissNotification(id) {
;     global g_SpoolNotifications, g_SpoolCooldown

;     ; Stop the countdown timer for this notification
;     SetTimer(NotificationCountdownFactory(id), 0)

;     ; Find and remove the notification
;     foundIndex := 0
;     foundNotif := ""

;     for i, notif in g_SpoolNotifications {
;         if notif["id"] = id {
;             foundIndex := i
;             foundNotif := notif
;             break
;         }
;     }

;     if foundIndex = 0
;         return  ; Already dismissed

;     ; Clear cooldown for this spool so it can continue checking
;     if IsObject(foundNotif) && foundNotif.Has("spoolName") && foundNotif["spoolName"] != "" {
;         g_SpoolCooldown.Delete(foundNotif["spoolName"])
;         SpoolLogAdd("Resumed: " . foundNotif["spoolName"])
;     }

;     ; Destroy GUI
;     try foundNotif["gui"].Destroy()

;     ; Remove from array
;     g_SpoolNotifications.RemoveAt(foundIndex)

;     ; Reposition remaining notifications
;     RepositionNotifications()

;     RefreshNotificationLV()
; }


DismissAllNotifications(*) {
    global g_SpoolNotifications, g_SpoolCooldown

    for notif in g_SpoolNotifications {
        try notif["gui"].Destroy()
    }
    g_SpoolNotifications := []
    g_SpoolCooldown := Map()  ; Clear all cooldowns

    RefreshNotificationLV()
    SpoolLogAdd("All notifications dismissed")
}

; Reposition notifications after one is dismissed
; RepositionNotifications() {
;     global g_SpoolNotifications

;     x := A_ScreenWidth - 320
;     baseY := A_ScreenHeight - 120

;     for i, notif in g_SpoolNotifications {
;         y := baseY - ((i - 1) * 95)
;         try {
;             notif["gui"].Move(x, y)
;         }
;     }
; }

; Refresh notification list view
RefreshNotificationLV() {
    global NotificationLV, g_SpoolNotifications

    try {
        NotificationLV.Delete()

        for notif in g_SpoolNotifications {
            remaining := notif.Has("remaining") ? notif["remaining"] : "?"
            spoolName := notif.Has("spoolName") ? notif["spoolName"] : ""
            NotificationLV.Add("", notif["id"], notif["title"], remaining . "s", spoolName)
        }
    }
}

; Check if spool is in cooldown (notification still showing)
IsSpoolInCooldown(spoolName) {
    global g_SpoolCooldown

    if !g_SpoolCooldown.Has(spoolName)
        return false

    if A_TickCount > g_SpoolCooldown[spoolName] {
        g_SpoolCooldown.Delete(spoolName)
        return false
    }

    return true
}

ViewNotification(*) {
    global NotificationLV, g_SpoolNotifications

    row := NotificationLV.GetNext(0, "Focused")
    if row = 0 || row > g_SpoolNotifications.Length
        return

    notif := g_SpoolNotifications[row]
    MsgBoxTop("Notification: " . notif["title"] . "`nCreated: " . FormatTime(notif["time"], "yyyy-MM-dd HH:mm:ss"), "Notification Details")
}

; Log spool activity
SpoolLogAdd(message) {
    global g_SpoolLog, SpoolLogEdit

    timestamp := FormatTime(, "HH:mm:ss")
    entry := "[" . timestamp . "] " . message
    g_SpoolLog.Push(entry)

    ; Keep last 100 entries
    while g_SpoolLog.Length > 100
        g_SpoolLog.RemoveAt(1)

    ; Update log display
    try {
        logText := ""
        for entry in g_SpoolLog
            logText := entry . "`n" . logText  ; Newest first
        SpoolLogEdit.Value := logText
    }
}

ClearSpoolLog(*) {
    global g_SpoolLog, SpoolLogEdit
    g_SpoolLog := []
    SpoolLogEdit.Value := ""
}


; ═══════════════════════════════════════════════════════════════════════════════
; LIVE OCR FUNCTIONS (TAB 3)
; ═══════════════════════════════════════════════════════════════════════════════
; LIVE OCR FUNCTIONS (Tab 3)
; =============================================================================

global g_OCRRegion := Map("x1", 0, "y1", 0, "x2", 0, "y2", 0)  ; Custom OCR region
global g_LastOCRResult := ""  ; Store last OCR result object

ToggleOCRRecording(*) {
    global g_OCRRecording, OCRRecordingToggle, g_OCRSettings

    g_OCRRecording := OCRRecordingToggle.Value
    UpdateOCRRecordingStatus()

    if g_OCRRecording {
        interval := Integer(MainGui["OCRInterval"].Value)
        if interval < 100
            interval := 100
        SetTimer(LiveOCRCapture, interval)
        SpoolLogAdd("Live OCR started (interval: " . interval . "ms)")
    } else {
        SetTimer(LiveOCRCapture, 0)
        SpoolLogAdd("Live OCR stopped")
    }
}

UpdateOCRRecordingStatus() {
    global g_OCRRecording
    try {
        ctrl := MainGui["OCRRecordingStatus"]
        if g_OCRRecording {
            ctrl.Value := "RECORDING"
            ctrl.Opt("cRed")
        } else {
            ctrl.Value := "STOPPED"
            ctrl.Opt("cGray")
        }
    }
}

; Continuous OCR capture function
LiveOCRCapture() {
    global g_OCRRegion, g_OCRLog, g_LastOCRResult, OCR_LOG_FILE, g_DB

    try {
        startTime := A_TickCount

        ; Get OCR options
        scale := 1.0
        try scale := Float(MainGui["OCRScale"].Value)
        grayscale := MainGui["OCRGrayscale"].Value
        lang := MainGui["OCRLang"].Text

        opts := {lang: lang, scale: scale, grayscale: grayscale}

        ; Perform OCR based on region
        if g_OCRRegion["x2"] > 0 && g_OCRRegion["y2"] > 0 {
            ; Custom region
            w := g_OCRRegion["x2"] - g_OCRRegion["x1"]
            h := g_OCRRegion["y2"] - g_OCRRegion["y1"]
            result := OCR.FromRect(g_OCRRegion["x1"], g_OCRRegion["y1"], w, h, opts)
        } else {
            ; Full screen
            result := OCR.FromDesktop(opts)
        }

        g_LastOCRResult := result

        captureTime := A_TickCount - startTime

        ; Update display
        MainGui["OCROutput"].Value := result.Text
        MainGui["OCRWordCount"].Value := result.Words.Length
        MainGui["OCRLineCount"].Value := result.Lines.Length
        MainGui["OCRTextAngle"].Value := Round(result.TextAngle, 1) . "°"
        MainGui["OCRCaptureTime"].Value := captureTime . " ms"

        ; Update word list
        RefreshOCRWordLV(result)

        ; Log to file if recording
        if g_OCRRecording && result.Text != "" {
            timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
            cleanText := StrReplace(result.Text, "`n", " ")
            logEntry := timestamp . "|" . cleanText . "|" . result.Words.Length
            g_OCRLog.Push(logEntry)
            MainGui["OCRLogCount"].Value := g_OCRLog.Length

            ; Persist full history to SQLite (durable across restarts, no size cap)
            if IsObject(g_DB)
                g_DB.Exec("INSERT INTO ocr_log (ts, text, word_count) VALUES (" . SQLQuote(timestamp) . ", " . SQLQuote(cleanText) . ", " . result.Words.Length . ");")

            ; Append to file
            try FileAppend(logEntry . "`n", OCR_LOG_FILE)
        }
    } catch as err {
        MainGui["OCROutput"].Value := "OCR Error: " . err.Message
    }
}

CaptureOCROnce(*) {
    LiveOCRCapture()
    ShowStatus("OCR capture complete", "ok")
}

SelectOCRRegion(*) {
    global g_OCRRegion, MainGui

    MainGui.Hide()
    Sleep(100)

    ; Create overlay
    overlayGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "OCRRegionOverlay")
    overlayGui.BackColor := "000000"
    overlayGui.Show("x0 y0 w" . A_ScreenWidth . " h" . A_ScreenHeight . " NoActivate")
    WinSetTransparent(1, overlayGui)

    ToolTip("🎯 Drag to select OCR region`nESC to cancel`nRight-click for Full Screen", A_ScreenWidth//2 - 150, 50)

    x1 := 0, y1 := 0, x2 := 0, y2 := 0
    cancelled := false
    fullScreen := false

    selBox := ""

    ; Wait for input
    while !GetKeyState("LButton", "P") && !GetKeyState("RButton", "P") && !GetKeyState("Escape", "P") {
        Sleep(10)
    }

    if GetKeyState("Escape", "P") {
        cancelled := true
    } else if GetKeyState("RButton", "P") {
        fullScreen := true
    }

    if !cancelled && !fullScreen {
        MouseGetPos(&x1, &y1)

        selBox := Gui("+AlwaysOnTop -Caption +ToolWindow", "OCRSelectBox")
        selBox.BackColor := "00FF00"

        while GetKeyState("LButton", "P") {
            MouseGetPos(&x2, &y2)
            left := Min(x1, x2)
            top := Min(y1, y2)
            w := Abs(x2 - x1)
            h := Abs(y2 - y1)

            if w > 5 && h > 5 {
                selBox.Show("x" . left . " y" . top . " w" . w . " h" . h . " NoActivate")
                WinSetTransparent(80, selBox)
                ToolTip("Region: " . w . " x " . h, x2 + 20, y2 + 20)
            }
            Sleep(16)
        }
    }

    ToolTip()
    try selBox.Destroy()
    overlayGui.Destroy()

    if cancelled {
        MainGui.Show()
        return
    }

    if fullScreen {
        g_OCRRegion["x1"] := 0
        g_OCRRegion["y1"] := 0
        g_OCRRegion["x2"] := 0
        g_OCRRegion["y2"] := 0
        MainGui["OCRRegionDisplay"].Value := "Region: Full Screen"
        MainGui["OCRRegionPreview"].Value := "Full Screen`n" . A_ScreenWidth . " x " . A_ScreenHeight
    } else {
        g_OCRRegion["x1"] := Min(x1, x2)
        g_OCRRegion["y1"] := Min(y1, y2)
        g_OCRRegion["x2"] := Max(x1, x2)
        g_OCRRegion["y2"] := Max(y1, y2)

        w := g_OCRRegion["x2"] - g_OCRRegion["x1"]
        h := g_OCRRegion["y2"] - g_OCRRegion["y1"]

        MainGui["OCRRegionDisplay"].Value := "Region: " . w . "x" . h
        MainGui["OCRRegionPreview"].Value := "Custom Region`n" . g_OCRRegion["x1"] . "," . g_OCRRegion["y1"] . " to " . g_OCRRegion["x2"] . "," . g_OCRRegion["y2"] . "`n" . w . " x " . h . " pixels"
    }

    MainGui.Show()
}

GetOCRLanguages(*) {
    try {
        langs := OCR.GetAvailableLanguages()
        langList := ""
        for lang in langs
            langList .= lang . "`n"
        MsgBoxTop("Available OCR Languages:`n`n" . langList, "OCR Languages")
    } catch as err {
        MsgBoxTop("Error getting languages: " . err.Message, "Error")
    }
}

RefreshOCRWordLV(result) {
    global OCRLV

    OCRLV.Delete()

    ; Only show Word, X, Y (w/h available via click)
    for word in result.Words {
        OCRLV.Add("", word.Text, word.x, word.y)
    }
}

OnOCRWordSelect(LV, RowNumber, *) {
    global g_LastOCRResult

    if RowNumber = 0 || !IsObject(g_LastOCRResult)
        return

    ; Get word and highlight it using standardized overlay
    if RowNumber <= g_LastOCRResult.Words.Length {
        word := g_LastOCRResult.Words[RowNumber]
        ; Use our standardized overlay system instead of OCR library
        HighlightRegion(word.x, word.y, word.w, word.h, 2000, "word", word.Text)
    }
}

FindInOCR(*) {
    global g_LastOCRResult, OCRSearchEdit

    if !IsObject(g_LastOCRResult) {
        ShowStatus("No OCR result to search", "fail")
        return
    }

    needle := MainGui["OCRSearch"].Value
    if needle = "" {
        ShowStatus("Enter search text", "fail")
        return
    }

    caseSense := MainGui["OCRCaseSense"].Value

    ; Search through words manually for more reliable results
    foundWords := []
    for word in g_LastOCRResult.Words {
        if caseSense {
            if InStr(word.Text, needle, true)
                foundWords.Push(word)
        } else {
            if InStr(word.Text, needle)
                foundWords.Push(word)
        }
    }

    if foundWords.Length > 0 {
        ; Highlight first match
        w := foundWords[1]
        HighlightRegion(w.x, w.y, w.w, w.h, 3000, "match", needle)
        ShowStatus("Found: '" . needle . "' at " . w.x . "," . w.y . " (" . foundWords.Length . " total)", "ok")
    } else {
        ; Try finding in full text
        if InStr(g_LastOCRResult.Text, needle, caseSense) {
            ShowStatus("Found in text but not as separate word", "info")
        } else {
            ShowStatus("'" . needle . "' not found", "info")
        }
    }
}

HighlightOCRMatch(*) {
    global g_LastOCRResult

    if !IsObject(g_LastOCRResult) {
        ShowStatus("No OCR result", "fail")
        return
    }

    needle := MainGui["OCRSearch"].Value
    if needle = "" {
        ShowStatus("Enter search text", "fail")
        return
    }

    caseSense := MainGui["OCRCaseSense"].Value

    ; Find and highlight ALL matching words
    foundCount := 0
    for word in g_LastOCRResult.Words {
        match := caseSense ? InStr(word.Text, needle, true) : InStr(word.Text, needle)
        if match {
            HighlightRegion(word.x, word.y, word.w, word.h, 5000, "match", "")
            foundCount++
        }
    }

    if foundCount > 0 {
        ShowStatus("Highlighted " . foundCount . " matches", "ok")
    } else {
        ShowStatus("No word matches found", "info")
    }
}

ClearOCRHighlights(*) {
    ; Use our standardized overlay clearing
    ClearAllOverlays()
    ShowStatus("Highlights cleared", "ok")
}


; ═══════════════════════════════════════════════════════════════════════════════
; WATCH WORD UI HANDLERS
; ═══════════════════════════════════════════════════════════════════════════════
; WATCH WORD UI HANDLERS
; =============================================================================

; Double-click on OCR word - highlight and show info
OnOCRWordDblClick(LV, RowNumber, *) {
    global g_LastOCRResult

    if RowNumber = 0 || !IsObject(g_LastOCRResult)
        return

    if RowNumber <= g_LastOCRResult.Words.Length {
        word := g_LastOCRResult.Words[RowNumber]
        FlashHighlight(word.x, word.y, word.w, word.h, 3, 300, "word")
        ShowCoordTooltip(word.x, word.y, "Word: " . word.Text . "`nX:" . word.x . " Y:" . word.y . " W:" . word.w . " H:" . word.h, 3000)
    }
}

; Highlight selected OCR word
HighlightSelectedOCRWord(*) {
    global g_LastOCRResult, OCRLV

    row := OCRLV.GetNext(0, "Focused")
    if row = 0 || !IsObject(g_LastOCRResult)
        return

    if row <= g_LastOCRResult.Words.Length {
        word := g_LastOCRResult.Words[row]
        HighlightRegion(word.x, word.y, word.w, word.h, 3000, "word", word.Text)
    }
}

; Add selected OCR word as watch word
AddSelectedWordAsWatch(*) {
    global g_LastOCRResult, OCRLV, g_OCRRegion

    row := OCRLV.GetNext(0, "Focused")
    if row = 0 || !IsObject(g_LastOCRResult) {
        ShowStatus("Select a word first", "fail")
        return
    }

    ; Get watch word name from input
    name := MainGui["WatchWordName"].Value
    if name = "" {
        ShowStatus("Enter a name for the watch word", "fail")
        return
    }

    ; Get word coords
    word := g_LastOCRResult.Words[row]

    ; Create region around word with some padding
    padding := 5
    region := Map(
        "x1", word.x - padding,
        "y1", word.y - padding,
        "x2", word.x + word.w + padding,
        "y2", word.y + word.h + padding
    )

    ; Define watch word
    DefineWatchWord(name, region, "", 1)  ; labelIndex 1 = first word

    ; Update immediately
    UpdateWatchWord(name)
    RefreshWatchWordLV()

    ShowStatus("Watch word '" . name . "' created: " . word.Text, "ok")
    HighlightRegion(region["x1"], region["y1"], region["x2"] - region["x1"], region["y2"] - region["y1"], 2000, "selection", name)
}

; Click on selected OCR word
ClickSelectedOCRWord(*) {
    global g_LastOCRResult, OCRLV

    row := OCRLV.GetNext(0, "Focused")
    if row = 0 || !IsObject(g_LastOCRResult) {
        ShowStatus("Select a word first", "fail")
        return
    }

    word := g_LastOCRResult.Words[row]
    x := word.x + word.w // 2
    y := word.y + word.h // 2

    ; Brief highlight then click
    HighlightRegion(word.x, word.y, word.w, word.h, 500, "highlight", "")
    Sleep(200)
    Click(x, y)
    ShowStatus("Clicked: " . word.Text, "ok")
}

; Define watch word from current OCR region
DefineWatchWordFromOCR(*) {
    global g_OCRRegion

    name := MainGui["WatchWordName"].Value
    if name = "" {
        ShowStatus("Enter a name for the watch word", "fail")
        return
    }

    ; Use current OCR region
    if g_OCRRegion["x2"] = 0 && g_OCRRegion["y2"] = 0 {
        ShowStatus("Select a region first (use Select Region button)", "fail")
        return
    }

    region := Map(
        "x1", g_OCRRegion["x1"],
        "y1", g_OCRRegion["y1"],
        "x2", g_OCRRegion["x2"],
        "y2", g_OCRRegion["y2"]
    )

    DefineWatchWord(name, region, "", 0)  ; 0 = all text in region
    UpdateWatchWord(name)
    RefreshWatchWordLV()

    ShowStatus("Watch word '" . name . "' created from region", "ok")
}

; Show all watch word values
ShowWatchWordValues(*) {
    global g_WatchWords, g_WordVariables

    ; Update all first
    UpdateAllWatchWords()
    RefreshWatchWordLV()

    ; Build summary
    summary := "Watch Word Values:`n`n"
    for name, watch in g_WatchWords {
        summary .= "$word." . name . " = " . watch["lastValue"] . "`n"
        summary .= "  Coords: " . watch["lastCoords"]["x"] . "," . watch["lastCoords"]["y"] . "`n"
    }

    if g_WatchWords.Count = 0
        summary := "No watch words defined.`n`nDefine watch words to capture dynamic text like patient names, dates, IDs, etc."

    MsgBoxTop(summary, "Watch Word Values")
}

; Manage watch words dialog
ManageWatchWords(*) {
    global g_WatchWords

    manageGui := Gui("+AlwaysOnTop", "Manage Watch Words")
    manageGui.SetFont("s9", "Consolas")

    manageGui.Add("Text", "w400", "Watch words capture dynamic text from specific screen regions.")
    manageGui.Add("Text", "w400 cGray", "Use $word.Name in workflows to reference captured values.")

    ; List view of watch words
    lv := manageGui.Add("ListView", "w400 h200 Grid", ["Name", "Region", "Last Value"])
    lv.ModifyCol(1, 100)
    lv.ModifyCol(2, 150)
    lv.ModifyCol(3, 140)

    for name, watch in g_WatchWords {
        r := watch["region"]
        regionStr := r["x1"] . "," . r["y1"] . " → " . r["x2"] . "," . r["y2"]
        lv.Add("", name, regionStr, watch["lastValue"])
    }

    manageGui.Add("Button", "w80", "Update All").OnEvent("Click", (*) => (UpdateAllWatchWords(), manageGui.Destroy(), ManageWatchWords()))
    manageGui.Add("Button", "x+10 w80", "Highlight").OnEvent("Click", (*) => HighlightAllWatchWords())
    manageGui.Add("Button", "x+10 w80", "Delete").OnEvent("Click", (*) => DeleteSelectedWatchWordFromList(lv))
    manageGui.Add("Button", "x+10 w80", "Close").OnEvent("Click", (*) => manageGui.Destroy())

    manageGui.Show()
}

; Highlight all watch words on screen
HighlightAllWatchWords() {
    global g_WatchWords

    UpdateAllWatchWords()

    for name, watch in g_WatchWords {
        coords := watch["lastCoords"]
        if coords["w"] > 0 {
            HighlightRegion(coords["x"], coords["y"], coords["w"], coords["h"], 3000, "word", name)
        }
    }
}

; Delete watch word from manage list
DeleteSelectedWatchWordFromList(lv) {
    global g_WatchWords

    row := lv.GetNext(0, "Focused")
    if row = 0
        return

    name := lv.GetText(row, 1)
    g_WatchWords.Delete(name)
    SaveWatchWords()
    lv.Delete(row)
}

; Refresh watch word list view
RefreshWatchWordLV() {
    global g_WatchWords, WatchWordLV

    try {
        WatchWordLV.Delete()
        for name, watch in g_WatchWords {
            WatchWordLV.Add("", name, watch["lastValue"])
        }
    }
}

; Watch word LV selection handler
OnWatchWordSelect(LV, RowNumber, *) {
    ; Just update UI state if needed
}

; Double-click watch word - highlight on screen
OnWatchWordDblClick(LV, RowNumber, *) {
    global g_WatchWords

    if RowNumber = 0
        return

    name := LV.GetText(RowNumber, 1)
    if g_WatchWords.Has(name) {
        HighlightWatchWord(name, 3000)
    }
}

; Highlight selected watch word
HighlightSelectedWatchWord(*) {
    global g_WatchWords, WatchWordLV

    row := WatchWordLV.GetNext(0, "Focused")
    if row = 0
        return

    name := WatchWordLV.GetText(row, 1)
    if g_WatchWords.Has(name) {
        UpdateWatchWord(name)  ; Refresh value first
        HighlightWatchWord(name, 3000)
        ShowStatus(name . " = " . g_WatchWords[name]["lastValue"], "ok")
    }
}

; Use selected watch word (insert into clipboard or show value)
UseSelectedWatchWord(*) {
    global g_WatchWords, WatchWordLV

    row := WatchWordLV.GetNext(0, "Focused")
    if row = 0
        return

    name := WatchWordLV.GetText(row, 1)
    if g_WatchWords.Has(name) {
        UpdateWatchWord(name)
        value := g_WatchWords[name]["lastValue"]

        ; Copy value to clipboard
        A_Clipboard := value
        ShowStatus("Copied to clipboard: " . value, "ok")
    }
}

; Delete selected watch word
DeleteSelectedWatchWord(*) {
    global g_WatchWords, WatchWordLV

    row := WatchWordLV.GetNext(0, "Focused")
    if row = 0
        return

    name := WatchWordLV.GetText(row, 1)

    if MsgBox("Delete watch word '" . name . "'?", "Confirm", "YesNo") = "Yes" {
        g_WatchWords.Delete(name)
        SaveWatchWords()
        RefreshWatchWordLV()
        ShowStatus("Deleted: " . name, "ok")
    }
}

; Test all patterns and overlay system
TestAllOverlays(*) {
    global g_Patterns, g_WatchWords

    ; Clear existing
    ClearAllOverlays()

    ; Test patterns
    patternCount := TestAllPatternsHighlight(3000)

    ; Test watch words
    watchCount := 0
    for name, watch in g_WatchWords {
        UpdateWatchWord(name)
        coords := watch["lastCoords"]
        if coords["w"] > 0 {
            HighlightRegion(coords["x"], coords["y"], coords["w"], coords["h"], 3000, "word", name . ": " . watch["lastValue"])
            watchCount++
        }
    }

    ShowStatus("Patterns: " . patternCount . " | Watch Words: " . watchCount, "ok")
}

ViewOCRLog(*) {
    global g_DB

    logText := ""
    if IsObject(g_DB) && g_DB.GetTable("SELECT ts, text, word_count FROM ocr_log ORDER BY id DESC LIMIT 2000;", &tb) {
        row := ""
        Loop tb.RowCount {
            tb.GetRow(A_Index, &row)
            logText .= row[1] . "|" . row[2] . "|" . row[3] . "`n"
        }
    }

    ; Show in popup
    logGui := Gui("+AlwaysOnTop", "OCR Log (most recent 2000 - full history kept in DB)")
    logGui.Add("Edit", "w600 h400 ReadOnly Multi VScroll", logText)
    logGui.Add("Button", "w100", "Close").OnEvent("Click", (*) => logGui.Destroy())
    logGui.Show()
}

ClearOCRLog(*) {
    global g_OCRLog, OCR_LOG_FILE, g_DB
    g_OCRLog := []
    MainGui["OCRLogCount"].Value := "0"
    try FileDelete(OCR_LOG_FILE)
    if IsObject(g_DB)
        g_DB.Exec("DELETE FROM ocr_log;")
    ShowStatus("OCR log cleared", "ok")
}

ExportOCRLog(*) {
    global g_DB, DATA_DIR

    exportFile := DATA_DIR . "\ocr_export_" . FormatTime(, "yyyyMMdd_HHmmss") . ".csv"

    content := "Timestamp,Text,WordCount`n"
    if IsObject(g_DB) && g_DB.GetTable("SELECT ts, text, word_count FROM ocr_log ORDER BY id;", &tb) {
        row := ""
        Loop tb.RowCount {
            tb.GetRow(A_Index, &row)
            content .= row[1] . "|" . row[2] . "|" . row[3] . "`n"
        }
    }

    try {
        FileAppend(content, exportFile)
        ShowStatus("Exported to: " . exportFile, "ok")
        Run("explorer.exe /select," . exportFile)
    } catch as err {
        ShowStatus("Export error: " . err.Message, "fail")
    }
}


; ═══════════════════════════════════════════════════════════════════════════════
; OCR TEXT MANIPULATION FUNCTIONS
; ═══════════════════════════════════════════════════════════════════════════════
; OCR TEXT MANIPULATION FUNCTIONS
; =============================================================================

; Copy OCR text to clipboard
CopyOCRToClipboard(*) {
    global OCROutputEdit, g_LastOCRText

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to copy", "fail")
        return
    }

    A_Clipboard := text
    g_LastOCRText := text
    ShowStatus("Copied " . StrLen(text) . " chars to clipboard", "ok")
}

; Load OCR text into revolver (using dropdown selection)
LoadOCRToRevolverDD(*) {
    global OCROutputEdit, OCRSplitDD, g_LastOCRText

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to load", "fail")
        return
    }

    g_LastOCRText := text

    ; Get split mode from dropdown
    mode := OCRSplitDD.Text

    switch mode {
        case "Tab": LoadOCRRevolver("tab")
        case "Line": LoadOCRRevolver("line")
        case "Space": LoadOCRRevolver(" ")
        case "Comma": LoadOCRRevolver(",")
        case "2 parts": LoadOCRRevolver("2")
        case "3 parts": LoadOCRRevolver("3")
        case "4 parts": LoadOCRRevolver("4")
        case "5 parts": LoadOCRRevolver("5")
        default: LoadOCRRevolver("4")
    }

    UpdateOCRRevolverStatus()
}

; Load OCR to revolver (simple button version)
LoadOCRToRevolver(*) {
    global OCROutputEdit, g_LastOCRText

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to load", "fail")
        return
    }

    g_LastOCRText := text

    ; Default: split into 4 parts
    LoadOCRRevolver("4")
    UpdateOCRRevolverStatus()
}

; Fire OCR revolver from UI button
FireOCRRevolverUI(*) {
    FireOCRRevolver()
    UpdateOCRRevolverStatus()
}

; Update revolver status display
UpdateOCRRevolverStatus() {
    global g_OCRRevolver, g_OCRRevolverIndex

    try {
        if g_OCRRevolver.Length = 0 {
            MainGui["OCRRevolverStatus"].Value := "Empty"
        } else {
            MainGui["OCRRevolverStatus"].Value := g_OCRRevolverIndex . "/" . g_OCRRevolver.Length . " parts"
        }
    }
}

; Save OCR text to variable
SaveOCRToVariable(*) {
    global OCROutputEdit, g_SpoolVariables, g_WordVariables

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to save", "fail")
        return
    }

    ; Ask for variable name
    varGui := Gui("+AlwaysOnTop", "Save to Variable")
    varGui.Add("Text", , "Variable name:")
    varNameEdit := varGui.Add("Edit", "w200", "ocrText")
    varGui.Add("Button", "Default w100", "Save").OnEvent("Click", (*) => (
        g_SpoolVariables[varNameEdit.Value] := text,
        g_WordVariables["$var." . varNameEdit.Value] := text,
        RefreshOCRVarsLV(),
        ShowStatus("Saved to $var." . varNameEdit.Value, "ok"),
        varGui.Destroy()
    ))
    varGui.Add("Button", "x+10 w100", "Cancel").OnEvent("Click", (*) => varGui.Destroy())
    varGui.Show()
}

; Click on text found in OCR
ClickTextInOCR(*) {
    global OCROutputEdit, OCRSearchEdit, g_OCRSettings, g_LastOCRRegion

    searchText := OCRSearchEdit.Value
    if searchText = "" {
        ShowStatus("Enter text to find and click", "fail")
        return
    }

    ; Use last captured region or full screen
    region := g_LastOCRRegion.Count > 0 ? g_LastOCRRegion : Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)

    ExecuteOCRClick(region["x1"] . "," . region["y1"] . "," . region["x2"] . "," . region["y2"], searchText)
}

; Extract text using regex
ExtractOCRRegex(*) {
    global OCROutputEdit, g_LastOCRText

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to extract from", "fail")
        return
    }

    ; Ask for regex pattern
    regGui := Gui("+AlwaysOnTop", "Extract with Regex")
    regGui.Add("Text", , "Regex pattern:")
    patternEdit := regGui.Add("Edit", "w300", "\d+")
    regGui.Add("Text", , "Common patterns:")
    regGui.Add("Text", "cGray", "\d+ = numbers | [A-Z]+ = uppercase | \d{3}-\d{4} = phone")

    extractBtn := regGui.Add("Button", "Default w100", "Extract")
    extractBtn.OnEvent("Click", (*) => ExtractRegexAndShow(text, patternEdit.Value, regGui))
    regGui.Add("Button", "x+10 w100", "Cancel").OnEvent("Click", (*) => regGui.Destroy())
    regGui.Show()
}

; Helper for regex extraction
ExtractRegexAndShow(text, pattern, parentGui) {
    global g_LastOCRText

    matches := []
    pos := 1

    while pos := RegExMatch(text, pattern, &match, pos) {
        matches.Push(match[0])
        pos += StrLen(match[0])
    }

    if matches.Length = 0 {
        ShowStatus("No matches found", "fail")
        return
    }

    ; Join matches and copy to clipboard
    result := ""
    for m in matches
        result .= m . "`n"
    result := RTrim(result, "`n")

    A_Clipboard := result
    g_LastOCRText := result

    parentGui.Destroy()
    ShowStatus("Extracted " . matches.Length . " matches to clipboard", "ok")
}

; Split OCR text dialog
SplitOCRText(*) {
    global OCROutputEdit, g_LastOCRText

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to split", "fail")
        return
    }

    g_LastOCRText := text

    ; Show split options dialog
    splitGui := Gui("+AlwaysOnTop", "Split OCR Text")
    splitGui.Add("Text", , "Split by:")
    splitDD := splitGui.Add("DropDownList", "w150", ["4 equal parts", "Tab characters", "Newlines", "Spaces", "Commas", "Custom delimiter"])
    splitDD.Choose(1)

    splitGui.Add("Text", , "Custom delimiter:")
    delimEdit := splitGui.Add("Edit", "w150", "|")

    splitGui.Add("Button", "Default w100", "Split & Load").OnEvent("Click", (*) => (
        DoSplitOCR(splitDD.Text, delimEdit.Value, splitGui)
    ))
    splitGui.Add("Button", "x+10 w100", "Cancel").OnEvent("Click", (*) => splitGui.Destroy())
    splitGui.Show()
}

; Perform the split
DoSplitOCR(mode, customDelim, parentGui) {
    switch mode {
        case "4 equal parts": LoadOCRRevolver("4")
        case "Tab characters": LoadOCRRevolver("tab")
        case "Newlines": LoadOCRRevolver("line")
        case "Spaces": LoadOCRRevolver(" ")
        case "Commas": LoadOCRRevolver(",")
        case "Custom delimiter": LoadOCRRevolver(customDelim)
        default: LoadOCRRevolver("4")
    }

    parentGui.Destroy()
    UpdateOCRRevolverStatus()
}

; Show OCR help
ShowOCRHelp(*) {
    helpText := "
    (
OCR Text Operations Help:

📋 Copy: Copy all OCR text to clipboard

🔫 Load Rev: Split text into parts for sequential pasting
   - Choose split mode (4 parts, Tab, Line, etc.)
   - Use Fire Rev to paste each part in order

→ Var: Save OCR text to a variable ($var.name)
   - Use in workflows: Type Text → $var.ocrText

Click Text: Click on specific text found via OCR
   - Enter search text in Find field first

Regex: Extract matching text using regex patterns
   - Common: \d+ (numbers), [A-Z]+ (caps)

Split: Choose how to split text for revolver

WORKFLOW ACTIONS:
- OCR Region: Capture text from screen area
- OCR Click: Find and click on text
- OCR Wait: Wait for text to appear
- Load OCR Revolver: Split captured text
- Fire OCR Revolver: Paste next part
    )"

    MsgBoxTop(helpText, "OCR Operations Help")
}


; ═══════════════════════════════════════════════════════════════════════════════
; OCR-ENHANCED SPOOL DETECTION
; ═══════════════════════════════════════════════════════════════════════════════
; OCR-ENHANCED SPOOL DETECTION
; =============================================================================

; Use Windows OCR for text detection in spools
SpoolDetectOCRWindows(region, searchText, useRegex := false) {
    try {
        w := region["x2"] - region["x1"]
        h := region["y2"] - region["y1"]

        if w < 40 || h < 40 {
            ; Region too small, use full screen
            result := OCR.FromDesktop()
        } else {
            result := OCR.FromRect(region["x1"], region["y1"], w, h)
        }

        if useRegex {
            return Map("found", RegExMatch(result.Text, searchText), "text", result.Text)
        } else {
            return Map("found", InStr(result.Text, searchText), "text", result.Text)
        }
    } catch {
        return Map("found", false, "text", "")
    }
}

; --- Spool UI Event Handlers ---

SaveSpool(*) {
    global g_Spools, SpoolNameEdit, SpoolRegionDD, SpoolRegionText
    global SpoolDetectDD, SpoolTargetCombo, SpoolIntervalEdit, SpoolConditionDD
    global SpoolActionDD, SpoolActionTargetCombo, SpoolExtractOCRChk, SpoolOCRVarEdit
    global SpoolAutoCompleteChk, SpoolCompletionDD, SpoolCompletionTargetCombo
    global SpoolEnabledChk, SpoolTimeoutEdit, SpoolModeDD, SpoolCooldownEdit, SpoolNotifTimeEdit

    name := SpoolNameEdit.Value
    if name = "" {
        MsgBoxTop("Enter a name!", "Required")
        return
    }

    ; Build spool data with new behavior fields
    spool := Map(
        "enabled", SpoolEnabledChk.Value,
        "region", SpoolRegionDD.Text,
        "regionCoords", SpoolRegionText.Value,
        "detectType", SpoolDetectDD.Text,
        "target", SpoolTargetCombo.Text,
        "interval", Integer(SpoolIntervalEdit.Value),
        "condition", SpoolConditionDD.Text,
        "action", SpoolActionDD.Text,
        "actionTarget", SpoolActionTargetCombo.Text,
        "extractOCR", SpoolExtractOCRChk.Value,
        "ocrVar", SpoolOCRVarEdit.Value,
        "autoComplete", SpoolAutoCompleteChk.Value,
        "completion", SpoolCompletionDD.Text,
        "completionTarget", SpoolCompletionTargetCombo.Text,
        "timeout", Integer(SpoolTimeoutEdit.Value),
        ; NEW behavior fields
        "mode", SpoolModeDD.Text,                     ; Continuous, One-Shot, Cooldown
        "cooldown", Integer(SpoolCooldownEdit.Value), ; Cooldown seconds
        "notifTime", Integer(SpoolNotifTimeEdit.Value) ; Notification display time
    )

    g_Spools[name] := spool
    SaveSpools()
    RefreshSpoolLV()
    ClearSpoolForm()
    SpoolLogAdd("Saved: " . name)
    ShowStatus("Spool saved: " . name, "ok")
}

ClearSpoolForm(*) {
    global SpoolNameEdit, SpoolRegionDD, SpoolRegionText, SpoolDetectDD
    global SpoolTargetCombo, SpoolIntervalEdit, SpoolConditionDD, SpoolActionDD
    global SpoolActionTargetCombo, SpoolExtractOCRChk, SpoolOCRVarEdit
    global SpoolAutoCompleteChk, SpoolCompletionDD, SpoolCompletionTargetCombo
    global SpoolEnabledChk, SpoolTimeoutEdit, SpoolModeDD, SpoolCooldownEdit
    global SpoolNotifTimeEdit, SpoolSeqHelp

    SpoolNameEdit.Value := ""
    SpoolRegionDD.Choose(1)
    SpoolRegionText.Value := ""
    SpoolDetectDD.Choose(1)
    SpoolTargetCombo.Text := ""
    SpoolIntervalEdit.Value := "500"
    SpoolConditionDD.Choose(1)
    SpoolActionDD.Choose(1)
    SpoolActionTargetCombo.Text := ""
    SpoolExtractOCRChk.Value := 0
    SpoolOCRVarEdit.Value := ""
    SpoolAutoCompleteChk.Value := 0
    SpoolCompletionDD.Choose(1)
    SpoolCompletionTargetCombo.Text := ""
    SpoolTimeoutEdit.Value := "0"
    SpoolEnabledChk.Value := 1
    ; New fields
    SpoolModeDD.Choose(1)  ; Continuous
    SpoolCooldownEdit.Value := "5"
    SpoolNotifTimeEdit.Value := "5"
    try SpoolSeqHelp.Value := ""
}

TestSpoolOnce(*) {
    global g_Spools, SpoolNameEdit, SpoolDetectDD, SpoolTargetCombo, SpoolRegionDD, SpoolRegionText

    name := SpoolNameEdit.Value

    ; If no name but has detection info, build temporary spool for testing
    if name = "" || !g_Spools.Has(name) {
        ; Build temp spool from current form values
        tempSpool := Map(
            "detectType", SpoolDetectDD.Text,
            "target", SpoolTargetCombo.Text,
            "region", SpoolRegionDD.Text,
            "regionCoords", SpoolRegionText.Value,
            "condition", MainGui["SpoolCondition"].Text
        )

        ShowStatus("Testing detection...", "wait")
        region := GetSpoolRegion(tempSpool)
        detected := false

        switch tempSpool["detectType"] {
            case "Pattern Match":
                detected := SpoolDetectPattern(tempSpool["target"], region, tempSpool["condition"])
            case "Pattern Sequence":
                detected := SpoolDetectPatternSequence(tempSpool["target"], region)
            case "OCR Contains", "OCR Regex":
                result := SpoolDetectOCRWindows(region, tempSpool["target"], tempSpool["detectType"] = "OCR Regex")
                detected := result["found"]
                if result["text"] != ""
                    ShowStatus("OCR text: " . SubStr(result["text"], 1, 50) . "...", "info")
        }

        if detected {
            ShowStatus("✓ Detection PASSED: " . tempSpool["detectType"], "ok")
        } else {
            ShowStatus("✗ Detection FAILED: " . tempSpool["detectType"], "fail")
        }
        return
    }

    ShowStatus("Testing spool: " . name, "wait")
    ExecuteSpoolCheck(name, true)  ; true = force test, ignore cooldown
    ShowStatus("Spool test complete", "ok")
}

; Test current pattern visually
TestSpoolPattern(*) {
    global SpoolDetectDD, SpoolTargetCombo, g_Patterns

    detectType := SpoolDetectDD.Text
    target := SpoolTargetCombo.Text

    if target = "" {
        ShowStatus("Enter a target pattern", "fail")
        return
    }

    if detectType = "Pattern Match" {
        ; Test single pattern with highlight
        TestPatternHighlight(target, 3000)

    } else if detectType = "Pattern Sequence" {
        ; Test all patterns in sequence
        patterns := StrSplit(target, ",")
        found := 0
        total := patterns.Length

        for pat in patterns {
            pat := Trim(pat)
            if pat = ""
                continue
            if TestPatternHighlight(pat, 3000)
                found++
        }

        if found = total {
            ShowStatus("✓ ALL " . total . " patterns found!", "ok")
        } else {
            ShowStatus("✗ Found " . found . "/" . total . " patterns", "fail")
        }
    } else {
        ShowStatus("Use Test Once for OCR detection", "info")
    }
}

; Handler for behavior mode dropdown
OnSpoolModeChange(*) {
    global SpoolModeDD, SpoolCooldownEdit

    mode := SpoolModeDD.Text

    ; Update help text based on mode
    try {
        helpCtrl := MainGui["SpoolModeHelp"]
        switch mode {
            case "Continuous":
                helpCtrl.Value := "(keeps checking)"
            case "One-Shot":
                helpCtrl.Value := "(stops after 1 trigger)"
            case "Cooldown":
                helpCtrl.Value := "(re-check after delay)"
        }
    }
}

SelectSpoolRegion(*) {
    global SpoolRegionText, SpoolRegionDD, MainGui

    if SpoolRegionDD.Text != "Custom Region" {
        SpoolRegionDD.Choose(2)  ; Custom Region
    }

    MainGui.Hide()
    Sleep(100)

    ; Create full-screen transparent overlay
    overlayGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "RegionOverlay")
    overlayGui.BackColor := "000000"
    overlayGui.Show("x0 y0 w" . A_ScreenWidth . " h" . A_ScreenHeight . " NoActivate")
    WinSetTransparent(1, overlayGui)  ; Nearly transparent but captures input

    ; Create instruction tooltip
    ToolTip("🎯 Drag to select monitor region`nESC to cancel", A_ScreenWidth//2 - 150, 50)

    ; Track drag state
    x1 := 0, y1 := 0, x2 := 0, y2 := 0
    selecting := false
    cancelled := false

    ; Selection box GUI (red border)
    selBox := ""

    ; Hotkey to cancel
    escHotkey := Hotkey("Escape", (*) => (cancelled := true), "On")

    ; Wait for mouse down
    while !GetKeyState("LButton", "P") && !cancelled {
        Sleep(10)
    }

    if cancelled {
        ToolTip()
        overlayGui.Destroy()
        Hotkey("Escape", "Off")
        MainGui.Show()
        return
    }

    MouseGetPos(&x1, &y1)
    selecting := true

    ; Create selection rectangle GUI
    selBox := Gui("+AlwaysOnTop -Caption +ToolWindow", "SelectBox")
    selBox.BackColor := "FF0000"

    ; Draw selection while dragging
    while GetKeyState("LButton", "P") && !cancelled {
        MouseGetPos(&x2, &y2)

        ; Calculate rectangle
        left := Min(x1, x2)
        top := Min(y1, y2)
        w := Abs(x2 - x1)
        h := Abs(y2 - y1)

        if w > 5 && h > 5 {
            ; Show selection box (border only effect via region)
            selBox.Show("x" . left . " y" . top . " w" . w . " h" . h . " NoActivate")
            WinSetTransparent(100, selBox)

            ; Update tooltip with dimensions
            ToolTip("Region: " . w . " x " . h . "`n(" . left . "," . top . ") to (" . (left+w) . "," . (top+h) . ")", x2 + 20, y2 + 20)
        }

        Sleep(16)  ; ~60fps
    }

    ToolTip()
    Hotkey("Escape", "Off")

    try selBox.Destroy()
    overlayGui.Destroy()

    if cancelled {
        MainGui.Show()
        ShowStatus("Region selection cancelled", "info")
        return
    }

    ; Normalize coordinates
    left := Min(x1, x2)
    top := Min(y1, y2)
    right := Max(x1, x2)
    bottom := Max(y1, y2)

    ; Validate minimum size
    if (right - left) < 10 || (bottom - top) < 10 {
        MainGui.Show()
        ShowStatus("Region too small - try again", "fail")
        return
    }

    SpoolRegionText.Value := left . "," . top . "," . right . "," . bottom

    MainGui.Show()
    ShowStatus("Region: " . (right-left) . "x" . (bottom-top) . " at " . left . "," . top, "ok")
}

OnSpoolDetectChange(*) {
    global SpoolDetectDD, SpoolTargetCombo, g_Patterns, SpoolSeqHelp

    SpoolTargetCombo.Delete()

    ; Update helper text
    try SpoolSeqHelp.Value := ""

    switch SpoolDetectDD.Text {
        case "Pattern Match":
            items := []
            for name, _ in g_Patterns
                items.Push(name)
            if items.Length > 0
                SpoolTargetCombo.Add(items)

        case "Pattern Sequence":
            ; For pattern sequence, show hint text
            ; Target format: "Pattern1,Pattern2,Pattern3" (all must match)
            items := []
            for name, _ in g_Patterns
                items.Push(name)
            if items.Length > 0
                SpoolTargetCombo.Add(items)

            ; Show helper text explaining format
            try SpoolSeqHelp.Value := "Format: Pattern1,Pattern2,Pattern3 (ALL must match to trigger)"

        case "Window Title":
            items := GetWindowList()
            if items.Length > 0
                SpoolTargetCombo.Add(items)

        case "Screen Changed", "Pixel Change":
            ; No target needed - just monitors for changes
            SpoolTargetCombo.Add(["(monitors for any change)"])

        case "OCR Contains":
            try SpoolSeqHelp.Value := "Enter text to search for in the region (case-insensitive)"

        case "OCR Regex":
            try SpoolSeqHelp.Value := "Enter regex pattern, e.g.: \\d{3}-\\d{4} for phone numbers"
    }
}

OnSpoolActionChange(*) {
    global SpoolActionDD, SpoolActionTargetCombo, g_Sequences, g_Spools

    SpoolActionTargetCombo.Delete()

    switch SpoolActionDD.Text {
        case "Run Workflow":
            items := []
            for name, _ in g_Sequences
                items.Push(name)
            if items.Length > 0
                SpoolActionTargetCombo.Add(items)

        case "Start Spool", "Stop Spool":
            items := []
            for name, _ in g_Spools
                items.Push(name)
            if items.Length > 0
                SpoolActionTargetCombo.Add(items)

        case "Show Notification":
            ; Default notification messages
            SpoolActionTargetCombo.Add(["Pattern detected!", "Action required", "Check this now"])
    }
}

OnSpoolSelect(LV, RowNumber, *) {
    if RowNumber = 0
        return

    ; Could show spool details or populate form
}

OnSpoolCheck(LV, RowNumber, Checked) {
    global g_Spools, SpoolLV

    if RowNumber = 0
        return

    name := SpoolLV.GetText(RowNumber, 1)
    if !g_Spools.Has(name)
        return

    g_Spools[name]["enabled"] := Checked
    SaveSpools()

    ; Start/stop based on checkbox
    if Checked && g_SpoolMasterEnabled
        StartSpool(name)
    else
        StopSpool(name)
}
ClickTimeSlot(time, *) {
    global g_CalendarDate, g_Appointments

    appointment := GetAppointment(g_CalendarDate, time)
    if appointment.Count > 0 {
        choice := MsgBox(
            CalendarAppointmentText(appointment) . "`n`nYes = edit/rebook`nNo = cancel appointment`nCancel = keep it",
            "Appointment at " . FormatTimeSlot(time),
            "YesNoCancel Icon?"
        )
        if choice = "No" {
            CancelAppointment(g_CalendarDate, time)
            return
        }
        if choice != "Yes"
            return
    }
    OpenBookingDialog(time, appointment)
}

CalendarAppointmentText(appointment) {
    if !IsObject(appointment)
        return String(appointment)
    if appointment is Map {
        patient := appointment.Has("patientName") ? appointment["patientName"]
            : (appointment.Has("patient") ? appointment["patient"] : "Appointment")
        typeName := appointment.Has("typeName") ? appointment["typeName"]
            : (appointment.Has("type") ? appointment["type"] : "")
        return patient . (typeName != "" ? " - " . typeName : "")
    }
    return "Appointment"
}

PrevDay(*) {
    global g_CalendarDate
    g_CalendarDate := DateAdd(g_CalendarDate, -1, "Days")
    RefreshCalendar()
}

NextDay(*) {
    global g_CalendarDate
    g_CalendarDate := DateAdd(g_CalendarDate, 1, "Days")
    RefreshCalendar()
}

GoToToday(*) {
    global g_CalendarDate
    g_CalendarDate := FormatTime(, "yyyyMMdd")
    RefreshCalendar()
}

RefreshCalendar(*) {
    global g_CalendarDate, g_CalendarSlotButtons, g_Appointments, DateText
    DateText.Text := FormatTime(g_CalendarDate, "dddd, MMMM d, yyyy")
    for time, button in g_CalendarSlotButtons {
        key := GetAppointmentKey(g_CalendarDate, time)
        button.Text := g_Appointments.Has(key)
            ? CalendarAppointmentText(g_Appointments[key])
            : "[Empty]"
    }
}

UpdateTaskPreview(typeDD, presetCheckboxes, taskPreviewEdit) {
    ; Combine appointment type tasks + selected preset tasks
    allTasks := []

    ; Get appointment type tasks
    typeName := typeDD.Text
    for key, typeInfo in g_AppointmentTypes {
        if (typeInfo["name"] = typeName) {
            for task in typeInfo["tasks"] {
                allTasks.Push(task)
            }
            break
        }
    }

    ; Get selected preset tasks
    for presetInfo in presetCheckboxes {
        if (presetInfo["control"].Value) {  ; If checked
            presetKey := presetInfo["key"]
            preset := g_TaskPresets[presetKey]
            for task in preset["tasks"] {
                allTasks.Push(task)
            }
        }
    }

    ; Sort by time
    ; (Sort allTasks by notifyBefore in descending order)

    ; Display
    preview := ""
    for task in allTasks {
        minutes := task["notifyBefore"]
        if (minutes > 0) {
            preview .= "⏰ " . minutes . " min before: " . task["task"] . "`n"
        } else {
            preview .= "⏰ At appointment: " . task["task"] . "`n"
        }
    }
    taskPreviewEdit.Value := preview
}
OnSpoolContextMenu(LV, RowNumber, IsRightClick, X, Y) {
    global g_Spools, SpoolLV, g_ActiveSpools

    if RowNumber = 0
        return

    name := SpoolLV.GetText(RowNumber, 1)
    if !g_Spools.Has(name)
        return

    isRunning := g_ActiveSpools.Has(name)

    spoolMenu := Menu()
    spoolMenu.Add(isRunning ? "⏹ Stop" : "▶ Start", (*) => (isRunning ? StopSpool(name) : StartSpool(name)))
    spoolMenu.Add("🔍 Test Once", (*) => ExecuteSpoolCheck(name))
    spoolMenu.Add()
    spoolMenu.Add("✏ Edit", (*) => EditSpoolByName(name))
    spoolMenu.Add("📋 Duplicate", (*) => DuplicateSpool(name))
    spoolMenu.Add()
    spoolMenu.Add("🗑 Delete", (*) => DeleteSpoolByName(name))

    spoolMenu.Show(X, Y)
}

EditSpool(*) {
    global SpoolLV
    row := SpoolLV.GetNext(0, "Focused")
    if row = 0
        return
    name := SpoolLV.GetText(row, 1)
    EditSpoolByName(name)
}

EditSpoolByName(name) {
    global g_Spools, SpoolNameEdit, SpoolRegionDD, SpoolRegionText, SpoolDetectDD
    global SpoolTargetCombo, SpoolIntervalEdit, SpoolConditionDD, SpoolActionDD
    global SpoolActionTargetCombo, SpoolExtractOCRChk, SpoolOCRVarEdit
    global SpoolAutoCompleteChk, SpoolCompletionDD, SpoolCompletionTargetCombo
    global SpoolEnabledChk, SpoolTimeoutEdit, SpoolModeDD, SpoolCooldownEdit
    global SpoolNotifTimeEdit, SpoolSeqHelp

    if !g_Spools.Has(name)
        return

    spool := g_Spools[name]

    SpoolNameEdit.Value := name
    SpoolEnabledChk.Value := spool["enabled"]

    ; Set region dropdown
    regions := ["Full Screen", "Custom Region", "Active Window"]
    for i, r in regions {
        if r = spool["region"] {
            SpoolRegionDD.Choose(i)
            break
        }
    }
    SpoolRegionText.Value := spool["regionCoords"]

    ; Set detect type
    detectTypes := ["Pattern Match", "Pattern Sequence", "OCR Contains", "OCR Regex", "Pixel Change", "Window Title"]
    for i, d in detectTypes {
        if d = spool["detectType"] {
            SpoolDetectDD.Choose(i)
            break
        }
    }

    OnSpoolDetectChange()  ; Populate target dropdown
    SpoolTargetCombo.Text := spool["target"]

    SpoolIntervalEdit.Value := spool["interval"]

    ; Set condition
    conditions := ["Found", "Not Found", "Changed"]
    for i, c in conditions {
        if c = spool["condition"] {
            SpoolConditionDD.Choose(i)
            break
        }
    }

    ; Set behavior mode (NEW)
    modes := ["Continuous", "One-Shot", "Cooldown"]
    modeVal := spool.Has("mode") ? spool["mode"] : "Continuous"
    for i, m in modes {
        if m = modeVal {
            SpoolModeDD.Choose(i)
            break
        }
    }
    SpoolCooldownEdit.Value := spool.Has("cooldown") ? spool["cooldown"] : 5
    OnSpoolModeChange()  ; Update help text

    ; Set action
    actions := ["Show Notification", "Run Workflow", "Start Spool", "Stop Spool", "Extract OCR", "Set Variable", "Key Chord", "Run Program"]
    for i, a in actions {
        if a = spool["action"] {
            SpoolActionDD.Choose(i)
            break
        }
    }

    OnSpoolActionChange()  ; Populate action target dropdown
    SpoolActionTargetCombo.Text := spool["actionTarget"]
    SpoolNotifTimeEdit.Value := spool.Has("notifTime") ? spool["notifTime"] : 5

    SpoolExtractOCRChk.Value := spool["extractOCR"]
    SpoolOCRVarEdit.Value := spool["ocrVar"]
    SpoolAutoCompleteChk.Value := spool["autoComplete"]

    ; Set completion type
    completions := ["Pattern Found", "Pattern Gone", "OCR Contains", "Timeout", "Variable Set"]
    for i, c in completions {
        if c = spool["completion"] {
            SpoolCompletionDD.Choose(i)
            break
        }
    }
    SpoolCompletionTargetCombo.Text := spool["completionTarget"]
    SpoolTimeoutEdit.Value := spool["timeout"]

    ShowStatus("Editing: " . name, "ok")
}

DeleteSpool(*) {
    global SpoolLV
    row := SpoolLV.GetNext(0, "Focused")
    if row = 0
        return
    name := SpoolLV.GetText(row, 1)
    DeleteSpoolByName(name)
}

DeleteSpoolByName(name) {
    global g_Spools, g_ActiveSpools

    if !g_Spools.Has(name)
        return

    result := MsgBoxTop("Delete spool '" . name . "'?", "Confirm", "YesNo")
    if result != "Yes"
        return

    StopSpool(name)
    g_Spools.Delete(name)
    SaveSpools()
    RefreshSpoolLV()
    SpoolLogAdd("Deleted: " . name)
}

DuplicateSpool(*) {
    global SpoolLV, g_Spools
    row := SpoolLV.GetNext(0, "Focused")
    if row = 0 {
        ShowStatus("Select a spool to duplicate", "fail")
        return
    }
    name := SpoolLV.GetText(row, 1)
    DuplicateSpoolByName(name)
}

DuplicateSpoolByName(name) {
    global g_Spools

    if !g_Spools.Has(name)
        return

    newName := name . "_copy"
    counter := 1
    while g_Spools.Has(newName) {
        newName := name . "_copy" . counter
        counter++
    }

    g_Spools[newName] := Map()
    for key, val in g_Spools[name]
        g_Spools[newName][key] := val

    SaveSpools()
    RefreshSpoolLV()
    SpoolLogAdd("Duplicated: " . newName)
    ShowStatus("Created: " . newName, "ok")
}

StartSelectedSpool(*) {
    global SpoolLV
    row := SpoolLV.GetNext(0, "Focused")
    if row = 0
        return
    name := SpoolLV.GetText(row, 1)
    StartSpool(name)
}

StopSelectedSpool(*) {
    global SpoolLV
    row := SpoolLV.GetNext(0, "Focused")
    if row = 0
        return
    name := SpoolLV.GetText(row, 1)
    StopSpool(name)
}

RefreshSpoolLV() {
    global g_Spools, g_ActiveSpools, SpoolLV

    SpoolLV.Delete()
    for name, spool in g_Spools {
        status := g_ActiveSpools.Has(name) ? "Running" : "Stopped"
        mode := spool.Has("mode") ? spool["mode"] : "Cont."
        ; Shorten mode names for display
        if mode = "Continuous"
            mode := "Cont."
        else if mode = "One-Shot"
            mode := "1-Shot"
        else if mode = "Cooldown"
            mode := "Cool."
        SpoolLV.Add(spool["enabled"] ? "Check" : "", name, spool["detectType"], spool["action"], mode, status)
    }
}

; Note: RefreshNotificationLV is defined above with the notification functions

RefreshOCRVarsLV() {
    global g_SpoolVariables, OCRVarsLV

    try {
        OCRVarsLV.Delete()
        for name, val in g_SpoolVariables {
            OCRVarsLV.Add("", name, SubStr(val, 1, 30))
        }
    }
}

ClearOCRVars(*) {
    global g_SpoolVariables
    g_SpoolVariables := Map()
    RefreshOCRVarsLV()
}

UseOCRVar(*) {
    global OCRVarsLV, g_SpoolVariables, ParamCombo

    row := OCRVarsLV.GetNext(0, "Focused")
    if row = 0
        return

    varName := OCRVarsLV.GetText(row, 1)
    if g_SpoolVariables.Has(varName) {
        try ParamCombo.Text := g_SpoolVariables[varName]
    }
}

SaveHotkeys() {
    global g_HotkeyBindings, HOTKEYS_FILE
    try {
        if FileExist(HOTKEYS_FILE)
            FileDelete(HOTKEYS_FILE)
        for hk, seq in g_HotkeyBindings
            IniWrite(seq, HOTKEYS_FILE, "Hotkeys", hk)
    }
}

LoadHotkeys() {
    global g_HotkeyBindings, HOTKEYS_FILE
    if !FileExist(HOTKEYS_FILE)
        return
    g_HotkeyBindings := Map()
    allKeys := IniRead(HOTKEYS_FILE, "Hotkeys", , "")
    for line in StrSplit(allKeys, "`n") {
        eq := InStr(line, "=")
        if eq > 0
            g_HotkeyBindings[SubStr(line, 1, eq - 1)] := SubStr(line, eq + 1)
    }
}

SaveSettings() {
    global g_Settings, SETTINGS_FILE
    for k, v in g_Settings
        IniWrite(v, SETTINGS_FILE, "Settings", k)
}

LoadSettings() {
    global g_Settings, SETTINGS_FILE
    if !FileExist(SETTINGS_FILE)
        return
    for k, def in g_Settings.Clone()
        g_Settings[k] := IsNumber(def) ? Number(IniRead(SETTINGS_FILE, "Settings", k, def)) : IniRead(SETTINGS_FILE, "Settings", k, def)
}

SaveExtractionRules() {
    global g_ExtractionRules, RULES_FILE
    try {
        file := FileOpen(RULES_FILE, "w", "UTF-8")
        file.WriteLine("Name,Pattern")
        for r in g_ExtractionRules
            file.WriteLine(r["name"] . "," . r["pattern"])
        file.Close()
    }
}

LoadExtractionRules() {
    global g_ExtractionRules, RULES_FILE
    if !FileExist(RULES_FILE) {
        g_ExtractionRules := [Map("name", "LastName", "pattern", "^([^,]+)"), Map("name", "FirstName", "pattern", ",\s*([^#\s]+)"), Map("name", "DOB", "pattern", "(\d{1,2}/\d{1,2}/\d{2,4})")]
        return
    }
    g_ExtractionRules := []
    lineNum := 0
    Loop Read RULES_FILE {
        lineNum++
        if lineNum = 1 || A_LoopReadLine = ""
            continue
        p := StrSplit(A_LoopReadLine, ",", , 2)
        if p.Length >= 2
            g_ExtractionRules.Push(Map("name", p[1], "pattern", p[2]))
    }
}

SaveAll() {
    SaveCoordinates()
    SavePatterns()
    SaveSequences()
    SaveSpools()
    SaveHotkeys()
    SaveSettings()
    SaveExtractionRules()
}

; Registered via OnExit so in-progress edits are never lost just by closing the window.
SaveAllOnExit(ExitReason, ExitCode) {
    global g_DB
    try AutoSaveCurrentWorkflow()
    try SaveAll()
    if IsObject(g_DB)
        g_DB.CloseDB()
    return 0
}


; Test if OCR is available
global g_OCRAvailable := false

TestOCRAvailability() {
    global g_OCRAvailable
    try {
        if !IsSet(OCR) {
            g_OCRAvailable := false
            return false
        }
        testResult := OCR.FromRect(0, 0, 100, 100, "en-US", 1)
        g_OCRAvailable := true
        return true
    } catch {
        g_OCRAvailable := false
        return false
    }
}

LoadAll() {
    LoadCoordinates()
    LoadPatterns()
    LoadSequences()
    LoadHotkeys()
    LoadSettings()
    LoadExtractionRules()
    LoadHotstrings()
    LoadNotificationTriggers()
    StartNotificationTimer()
    InitializeParameterValidators()
    InitializeActionTemplates()

    ; Apply notification settings from saved settings
    global g_DebugMode, g_NotificationDismissible, g_NotificationTimeout
    if g_Settings.Has("DebugMode")
        g_DebugMode := g_Settings["DebugMode"]
    if g_Settings.Has("NotificationDismissible")
        g_NotificationDismissible := g_Settings["NotificationDismissible"]
    if g_Settings.Has("NotificationTimeout")
        g_NotificationTimeout := Integer(g_Settings["NotificationTimeout"]) * 1000

    ; Register all sequence hotkeys/hotstrings
    RegisterAllSequenceTriggers()
}


; ═══════════════════════════════════════════════════════════════════════════════
; MAIN GUI
; ═══════════════════════════════════════════════════════════════════════════════
; MAIN GUI
; =============================================================================

MainGui := Gui("+Resize +MinSize900x820", "Macro Automator v7 - Workflow Automator")
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

TabCtrl := MainGui.Add("Tab3", "x5 y28 w890 h730 vTabs", ["Workflow", "Patterns", "Live OCR", "Spools", "Analytics", "Clipboard", "Hotkeys", "Hotstrings", "Triggers", "Settings", "Notepad"])

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 1: WORKFLOW
; ═══════════════════════════════════════════════════════════════════════════════
; TAB 1: WORKFLOW
; =============================================================================
TabCtrl.UseTab(1)

; Coordinate capture remains available without occupying the workflow canvas.
CoordNameEdit := MainGui.Add("Edit", "x-1000 y-1000 w1 h1 Hidden vCoordName")
CoordLV := MainGui.Add("ListView", "x-1000 y-1000 w1 h1 Hidden vCoordLV", ["Name", "X", "Y", "EndX", "EndY", "Type"])
g_HiddenCoordNameEdit := CoordNameEdit
g_HiddenCoordLV := CoordLV

; STEP 1 - workflow identity and playback settings
MainGui.Add("GroupBox", "x15 y50 w860 h78", "1. Define Workflow")
MainGui.Add("Text", "x30 y73", "Name:")
SeqNameEdit := MainGui.Add("Edit", "x75 y70 w180 vSeqName")
SeqNameEdit.OnEvent("Change", ScheduleWorkflowAutosave)
MainGui.Add("Text", "x270 y73", "Speed:")
SpeedDD := MainGui.Add("DropDownList", "x315 y70 w70 vPlaybackSpeed", ["0.25x", "0.5x", "0.75x", "1x", "1.5x", "2x", "3x"])
SpeedDD.Choose(4)
SpeedDD.OnEvent("Change", ScheduleWorkflowAutosave)
MainGui.Add("Text", "x400 y73", "Hotkey:")
SeqHotkeyEdit := MainGui.Add("Edit", "x450 y70 w75 vSeqHotkey")
SeqHotkeyEdit.OnEvent("Change", ScheduleWorkflowAutosave)
MainGui.Add("Text", "x540 y73", "Hotstring:")
SeqHotstringEdit := MainGui.Add("Edit", "x605 y70 w75 vSeqHotstring")
SeqHotstringEdit.OnEvent("Change", ScheduleWorkflowAutosave)
SeqGuideBtn := MainGui.Add("Button", "x690 y68 w80 h24", "Action Guide")
SeqGuideBtn.OnEvent("Click", ShowInstructionsFile)
SeqErrorLogBtn := MainGui.Add("Button", "x780 y68 w80 h24", "Error Log")
SeqErrorLogBtn.OnEvent("Click", OpenErrorLog)
MainGui.Add("Text", "x30 y103 w820 cGray", "Give the workflow a name first. Named workflows autosave after each edit. Hotkey example: ^!s   Hotstring example: ::seq")

; STEP 2 - one contextual action at a time
MainGui.Add("GroupBox", "x15 y135 w860 h160", "2. Configure and Add One Action")
MainGui.Add("Text", "x30 y158", "Action:")
ActionDD := MainGui.Add("DropDownList", "x85 y155 w180 vActionType", GetWorkflowActionNames())
ActionDD.Choose(1)
ActionDD.OnEvent("Change", OnActionChange)
MainGui.Add("Button", "x275 y154 w85 h24 cGreen", "Templates").OnEvent("Click", ShowTemplateLibrary)
MainGui.Add("Button", "x370 y154 w105 h24", "Position Tools").OnEvent("Click", ShowCoordinateManager)

TargetFieldLabel := MainGui.Add("Text", "x30 y188 w90", "Position:")
TargetFieldHint := MainGui.Add("Text", "x120 y188 w165 cGray", "(required)")
TargetDD := MainGui.Add("ComboBox", "x30 y205 w255 vTargetCoord")
TargetDD.OnEvent("Change", OnTargetChange)
ParamFieldLabel := MainGui.Add("Text", "x300 y188 w105", "Click count:")
ParamFieldHint := MainGui.Add("Text", "x405 y188 w160 cGray", "(optional)")
ParamCombo := MainGui.Add("ComboBox", "x300 y205 w265 vActionParam")
ParamCombo.OnEvent("Focus", UpdateLiveParamHints)
ParamCombo.OnEvent("Change", OnParamChange)
ParamEdit := ParamCombo
MainGui.Add("Button", "x575 y204 w65 h24 Default", "Add Step").OnEvent("Click", AddStep)
OCRRegionBtn := MainGui.Add("Button", "x575 y232 w65 h22", "OCR Area")
OCRRegionBtn.OnEvent("Click", SelectOCRRegionForWorkflow)

ChoicesLabel := MainGui.Add("Text", "x30 y243", "Suggestions:")
ChoicesDD := MainGui.Add("DropDownList", "x105 y240 w350 vChoices")
UseChoiceBtn := MainGui.Add("Button", "x465 y239 w45 h22", "Use")
UseChoiceBtn.OnEvent("Click", UseChoice)
RefreshChoicesBtn := MainGui.Add("Button", "x515 y239 w50 h22", "Refresh")
RefreshChoicesBtn.OnEvent("Click", RefreshChoices)
AdvancedStepCheck := MainGui.Add("CheckBox", "x575 y267 vAdvancedStep", "Advanced")
AdvancedStepCheck.OnEvent("Click", ToggleAdvancedStepFields)

QualPatternLabel := MainGui.Add("Text", "x30 y272", "Pattern:")
QualPatternDD := MainGui.Add("DropDownList", "x85 y269 w125 vQualPattern", ["(none)"])
QualWindowLabel := MainGui.Add("Text", "x220 y272", "Window:")
QualWindowEdit := MainGui.Add("Edit", "x270 y269 w145 vQualWindow")
FailsafeCloseCheck := MainGui.Add("CheckBox", "x425 y272 vFailsafeClose", "Block window close")

MainGui.Add("GroupBox", "x650 y147 w215 h138", "Action Help")
global ActionHelpTitle := MainGui.Add("Text", "x660 y164 w195 cBlue", "Select action")
global ActionHelpText := MainGui.Add("Edit", "x660 y184 w195 h92 ReadOnly Multi VScroll", "Select an action to see the exact fields and an example.")

; STEP 3 - review and arrange the execution order
MainGui.Add("GroupBox", "x15 y305 w860 h215", "3. Review and Arrange Steps (top to bottom)")
StepsLV := MainGui.Add("ListView", "x25 y327 w720 h178 Grid Checked NoSortHdr vStepsLV", ["#", "Action", "Target", "Parameter", "Failsafe"])
StepsLV.ModifyCol(1, 25)
StepsLV.ModifyCol(2, 120)
StepsLV.ModifyCol(3, 150)
StepsLV.ModifyCol(4, 280)
StepsLV.ModifyCol(5, 125)
StepsLV.OnEvent("ItemSelect", OnStepSelect)
StepsLV.OnEvent("ContextMenu", OnStepsContextMenu)
StepsLV.OnEvent("ItemCheck", OnStepCheck)
MainGui.Add("Button", "x755 y327 w50 h24", "Up").OnEvent("Click", StepUp)
MainGui.Add("Button", "x810 y327 w50 h24", "Down").OnEvent("Click", StepDown)
MainGui.Add("Button", "x755 y357 w50 h24", "Edit").OnEvent("Click", EditStep)
MainGui.Add("Button", "x810 y357 w50 h24", "Delete").OnEvent("Click", DelStep)
MainGui.Add("Button", "x755 y387 w50 h24", "Enable").OnEvent("Click", ToggleStep)
MainGui.Add("Button", "x810 y387 w50 h24", "Clear").OnEvent("Click", ClearSteps)
MainGui.Add("Button", "x755 y427 w105 h24 cGreen", "Test Selected").OnEvent("Click", TestSingleStep)
MainGui.Add("Button", "x755 y457 w105 h24 cBlue", "Sim Selected").OnEvent("Click", SimulateSingleStep)
MainGui.Add("Button", "x755 y487 w105 h24 cBlue", "Simulate All").OnEvent("Click", SimulateSeq)

; STEP 4 - save and execute
MainGui.Add("GroupBox", "x15 y530 w860 h65", "4. Save and Run")
MainGui.Add("Button", "x30 y550 w90 h28", "Save Now").OnEvent("Click", SaveSeq)
MainGui.Add("Button", "x130 y550 w90 h28 cGreen", "Run Workflow").OnEvent("Click", TestSeq)
MainGui.Add("Button", "x230 y550 w90 h28 cBlue", "Simulate").OnEvent("Click", SimulateSeq)
MainGui.Add("CheckBox", "x335 y556 vStepThroughCheck", "Step-through (Tab advances)").OnEvent("Click", ToggleStepThrough)
SeqManageBtn := MainGui.Add("Button", "x585 y550 w120 h28", "Manage Library")
SeqManageBtn.OnEvent("Click", ShowWorkflowManager)
WorkflowSaveStatus := MainGui.Add("Text", "x30 y580 w820 cGray", "Enter a workflow name; changes then autosave after each edit.")

; STEP 5 - persistent library and portable .maw files
SavedLibraryGroup := MainGui.Add("GroupBox", "x15 y605 w860 h150", "5. Saved Workflow Library and Portable .maw Files")
SavedWorkflowsLabel := MainGui.Add("Text", "x25 y623 w640", "Double-click a workflow to load it. Import, export, or build a .maw file using the buttons at right.")
SeqLV := MainGui.Add("ListView", "x25 y640 w650 h103 r5 Grid NoSortHdr vSeqLV", ["Name", "Steps", "Speed", "Hotkey", "Hotstring"])
SeqLV.Opt("-LV0x2000 +0x00200000 +LV0x20")
SeqLV.ModifyCol(1, 330)
SeqLV.ModifyCol(2, 70)
SeqLV.ModifyCol(3, 65)
SeqLV.ModifyCol(4, 85)
SeqLV.ModifyCol(5, 95)
SeqLV.OnEvent("ContextMenu", OnSeqContextMenu)
SeqLV.OnEvent("DoubleClick", (*) => LoadSeq())
SeqLoadBtn := MainGui.Add("Button", "x685 y640 w85 h24", "Load / Edit")
SeqLoadBtn.OnEvent("Click", LoadSeq)
SeqDeleteBtn := MainGui.Add("Button", "x775 y640 w85 h24", "Delete")
SeqDeleteBtn.OnEvent("Click", DelSeq)
SeqRunBtn := MainGui.Add("Button", "x685 y668 w85 h24 cGreen", "Run")
SeqRunBtn.OnEvent("Click", RunSeq)
SeqSimBtn := MainGui.Add("Button", "x775 y668 w85 h24 cBlue", "Simulate")
SeqSimBtn.OnEvent("Click", SimulateSavedSeq)
SeqImportBtn := MainGui.Add("Button", "x685 y696 w85 h24", "Import .maw")
SeqImportBtn.OnEvent("Click", ImportWorkflow)
SeqExportBtn := MainGui.Add("Button", "x775 y696 w85 h24", "Export .maw")
SeqExportBtn.OnEvent("Click", ExportWorkflowFromMain)
SeqMawWriterBtn := MainGui.Add("Button", "x685 y724 w175 h24", "Build / Write .maw")
SeqMawWriterBtn.OnEvent("Click", ShowMawWriter)


; ═══════════════════════════════════════════════════════════════════════════════
; TAB 2: PATTERNS
; ═══════════════════════════════════════════════════════════════════════════════
; TAB 2: PATTERNS
; =============================================================================
TabCtrl.UseTab(2)

; --- LEFT SIDE: Pattern Input ---
MainGui.Add("GroupBox", "x15 y50 w430 h220", "Pattern Definition")

; Capture buttons row
MainGui.Add("Button", "x25 y70 w100 h24", "📷 Quick Capture").OnEvent("Click", QuickCapturePattern)
MainGui.Add("Button", "x130 y70 w100 h24", "FindText GUI").OnEvent("Click", OpenFindTextGUI)
MainGui.Add("Text", "x240 y75 w200 cGray", "Quick: drag region | FindText: advanced")

; Name and description
MainGui.Add("Text", "x25 y100", "Name:")
PatternNameEdit := MainGui.Add("Edit", "x65 yp-3 w120 vPatternName")
MainGui.Add("Text", "x195 yp+3", "Desc:")
PatternDescEdit := MainGui.Add("Edit", "x225 yp-3 w205 vPatternDesc")

; Qualifier dropdown
MainGui.Add("Text", "x25 y127", "Qualifier:")
PatternQualifierDD := MainGui.Add("DropDownList", "x80 yp-3 w150 vPatternQualifier", ["(none)"])
PatternQualifierDD.Choose(1)
MainGui.Add("Text", "x240 y127 w190 cGray", "Pattern that must exist first")

; Code area
MainGui.Add("Text", "x25 y152", "Code:")
PatternCodeEdit := MainGui.Add("Edit", "x25 y167 w320 h50 Multi vPatternCode", "")
PatternCodeEdit.OnEvent("Change", UpdatePatternPreview)

MainGui.Add("Button", "x350 y167 w80 h22", "Paste").OnEvent("Click", PastePatternCode)
MainGui.Add("Button", "x350 y192 w80 h22", "Clear").OnEvent("Click", ClearPatternCode)

; Save/Test row
MainGui.Add("Button", "x25 y225 w90 h22", "Save Pattern").OnEvent("Click", SavePattern)
MainGui.Add("Button", "x120 yp w90 h22", "Test Pattern").OnEvent("Click", TestPattern)
MainGui.Add("Button", "x215 yp w70 h22", "📷 Find").OnEvent("Click", CaptureScreenshotNow)
ExtractStatus := MainGui.Add("Text", "x290 y228 w150 cGreen vExtractStatus", "")

; --- RIGHT SIDE: Preview ---
MainGui.Add("GroupBox", "x455 y50 w420 h220", "Preview & Capture Info")

; ASCII preview (smaller)
MainGui.SetFont("s6", "Consolas")
PatternPreviewEdit := MainGui.Add("Edit", "x465 y68 w180 h120 ReadOnly Multi vPatternPreview", "Paste code or capture...")
MainGui.SetFont("s9", "Segoe UI")
MainGui.Add("Button", "x555 y190 w90 h18", "↗ Popout").OnEvent("Click", PopoutPatternPreview)
MainGui.SetFont("s9", "Segoe UI")

; Screenshot
MainGui.Add("Text", "x655 y68 w100 h12 Center cGray", "Screenshot:")
PatternImageBox := MainGui.Add("Picture", "x655 y82 w100 h100 Border vPatternImage", "")
MainGui.Add("Button", "x655 y185 w48 h20", "View").OnEvent("Click", ViewPatternImage)
MainGui.Add("Button", "x707 y185 w48 h20", "📷").OnEvent("Click", RecaptureScreenshot)

; Capture info display
MainGui.Add("Text", "x765 y68 w100", "Capture Info:")
PatternCaptureInfo := MainGui.Add("Edit", "x765 y82 w100 h123 ReadOnly Multi vPatternCaptureInfo", "No data")

; --- SAVED PATTERNS ---
MainGui.Add("Text", "x15 y280", "Saved Patterns: (Right-click for options)")
PatternLV := MainGui.Add("ListView", "x15 y295 w750 h110 Grid NoSortHdr vPatternLV",
    ["Name", "Qualifier", "Location", "Window", "Code"])
PatternLV.ModifyCol(1, 110)
PatternLV.ModifyCol(2, 90)
PatternLV.ModifyCol(3, 80)
PatternLV.ModifyCol(4, 160)
PatternLV.ModifyCol(5, 290)
PatternLV.OnEvent("ItemSelect", PreviewSelectedPattern)
PatternLV.OnEvent("DoubleClick", (*) => PopoutSelectedPattern())
PatternLV.OnEvent("ContextMenu", OnPatternContextMenu)

; Buttons for saved patterns
MainGui.Add("Button", "x775 y295 w90 h22", "Test").OnEvent("Click", TestSelectedPattern)
MainGui.Add("Button", "x775 y320 w90 h22", "Edit").OnEvent("Click", EditPattern)
MainGui.Add("Button", "x775 y345 w90 h22", "Delete").OnEvent("Click", DeletePattern)
MainGui.Add("Button", "x775 y370 w90 h22", "Full View").OnEvent("Click", PopoutSelectedPattern)

; --- QUICK REFERENCE ---
MainGui.Add("GroupBox", "x15 y415 w860 h65", "Pattern System Reference")
MainGui.Add("Text", "x25 y432", "QUICK CAPTURE: Drag region → auto-generate pattern  |  QUALIFIER: Pattern that must exist first")
MainGui.Add("Text", "x25 y447", "ACTIONS: Find & Click/DblClick/TplClick/RClick/Drag  |  WAITS: Wait for Pattern, Wait Until Gone")
MainGui.Add("Text", "x25 y462 cGray", "Tips: Gray2Two for text, Color2Two for colored buttons  |  Use qualifiers for generic buttons like 'Submit'")


; ═══════════════════════════════════════════════════════════════════════════════
; TAB 3: LIVE OCR (CONTINUOUS TEXT RECOGNITION)
; ═══════════════════════════════════════════════════════════════════════════════
; TAB 3: LIVE OCR (Continuous Text Recognition)
; =============================================================================
TabCtrl.UseTab(3)

; --- LIVE OCR CONTROLS ---
MainGui.Add("GroupBox", "x15 y50 w860 h85", "Live OCR Monitor - Windows UWP Text Recognition")
MainGui.Add("Text", "x25 y68 w700", "Continuously captures and recognizes text from a screen region. Use to verify OCR is working correctly.")
MainGui.Add("Text", "x25 y83 w700 cGray", "OCR Library: Windows.Media.Ocr (UWP) | Supports multiple languages | Auto-detects text orientation")

OCRRecordingToggle := MainGui.Add("CheckBox", "x25 y103 w150 vOCRRecordingToggle", "🔴 Live Recording")
OCRRecordingToggle.OnEvent("Click", ToggleOCRRecording)
MainGui.Add("Text", "x180 y104 w100 cRed vOCRRecordingStatus", "STOPPED")
MainGui.Add("Button", "x290 y100 w90 h22", "Capture Once").OnEvent("Click", CaptureOCROnce)
MainGui.Add("Button", "x385 y100 w90 h22", "Select Region").OnEvent("Click", SelectOCRRegion)
MainGui.Add("Text", "x480 y104 w200 vOCRRegionDisplay cGray", "Region: Full Screen")
MainGui.Add("Button", "x700 y100 w80 h22", "Test All").OnEvent("Click", TestAllOverlays)
MainGui.Add("Button", "x785 y100 w80 h22", "Clear All").OnEvent("Click", (*) => ClearAllOverlays())

; --- OCR SETTINGS ---
MainGui.Add("GroupBox", "x15 y140 w200 h100", "OCR Settings")
MainGui.Add("Text", "x25 y160", "Language:")
OCRLangDD := MainGui.Add("DropDownList", "x85 y157 w100 vOCRLang", ["en-us", "es", "fr", "de", "it", "pt", "zh-Hans", "ja", "ko"])
OCRLangDD.Choose(1)
MainGui.Add("Text", "x25 y188", "Scale:")
OCRScaleEdit := MainGui.Add("Edit", "x65 y185 w40 vOCRScale", "1.0")
MainGui.Add("CheckBox", "x115 y188 vOCRGrayscale", "Gray")
MainGui.Add("Text", "x25 y215", "Interval:")
OCRIntervalEdit := MainGui.Add("Edit", "x75 y212 w45 vOCRInterval Number", "500")
MainGui.Add("Text", "x125 y215", "ms")

; --- CAPTURE REGION PREVIEW ---
MainGui.Add("GroupBox", "x225 y140 w180 h100", "Capture Region")
OCRRegionPreview := MainGui.Add("Text", "x235 y160 w160 h70 Border vOCRRegionPreview cGray Center", "Full Screen`n(Select Region)")

; --- OCR RESULT DISPLAY ---
MainGui.Add("GroupBox", "x415 y140 w170 h100", "Last Capture Info")
MainGui.Add("Text", "x425 y158", "Words:")
MainGui.Add("Text", "x470 y158 w50 vOCRWordCount cBlue", "0")
MainGui.Add("Text", "x425 y175", "Lines:")
MainGui.Add("Text", "x470 y175 w50 vOCRLineCount cBlue", "0")
MainGui.Add("Text", "x425 y192", "Angle:")
MainGui.Add("Text", "x470 y192 w50 vOCRTextAngle cBlue", "0°")
MainGui.Add("Text", "x425 y209", "Time:")
MainGui.Add("Text", "x470 y209 w50 vOCRCaptureTime cBlue", "0ms")

; --- WATCH WORDS (Dynamic Text Variables) ---
MainGui.Add("GroupBox", "x595 y140 w280 h100", "Watch Words (Dynamic Variables)")
MainGui.Add("Text", "x605 y158 w260 cGray", "Define regions to auto-capture text into variables")
MainGui.Add("Text", "x605 y175", "Name:")
WatchWordNameEdit := MainGui.Add("Edit", "x650 y172 w100 vWatchWordName")
MainGui.Add("Button", "x755 y172 w110 h20", "Define from OCR").OnEvent("Click", DefineWatchWordFromOCR)
MainGui.Add("Button", "x605 y198 w80 h20", "Update All").OnEvent("Click", (*) => UpdateAllWatchWords())
MainGui.Add("Button", "x690 y198 w80 h20", "Show Values").OnEvent("Click", ShowWatchWordValues)
MainGui.Add("Button", "x775 y198 w90 h20", "Manage...").OnEvent("Click", ManageWatchWords)

; --- LIVE OCR OUTPUT ---
MainGui.Add("GroupBox", "x15 y245 w430 h205", "Live OCR Text Output")
OCROutputEdit := MainGui.Add("Edit", "x25 y263 w410 h165 ReadOnly Multi VScroll vOCROutput", "")
; Text manipulation buttons
MainGui.Add("Button", "x25 y432 w60 h18", "📋 Copy").OnEvent("Click", CopyOCRToClipboard)
MainGui.Add("Button", "x90 y432 w80 h18", "🔫 Load Rev").OnEvent("Click", LoadOCRToRevolver)
MainGui.Add("Button", "x175 y432 w60 h18", "→ Var").OnEvent("Click", SaveOCRToVariable)
MainGui.Add("Button", "x240 y432 w80 h18", "Click Text").OnEvent("Click", ClickTextInOCR)
MainGui.Add("Button", "x325 y432 w55 h18", "Regex").OnEvent("Click", ExtractOCRRegex)
MainGui.Add("Button", "x385 y432 w50 h18", "Split").OnEvent("Click", SplitOCRText)

; --- WORD LIST ---
MainGui.Add("GroupBox", "x455 y245 w200 h205", "Detected Words")
OCRLV := MainGui.Add("ListView", "x465 y263 w180 h145 Grid NoSortHdr vOCRLV", ["Word", "X", "Y"])
OCRLV.ModifyCol(1, 90)
OCRLV.ModifyCol(2, 40)
OCRLV.ModifyCol(3, 40)
OCRLV.OnEvent("ItemSelect", OnOCRWordSelect)
OCRLV.OnEvent("DoubleClick", OnOCRWordDblClick)
MainGui.Add("Button", "x465 y413 w60 h20", "Highlight").OnEvent("Click", HighlightSelectedOCRWord)
MainGui.Add("Button", "x530 y413 w60 h20", "Watch").OnEvent("Click", AddSelectedWordAsWatch)
MainGui.Add("Button", "x595 y413 w50 h20", "Click").OnEvent("Click", ClickSelectedOCRWord)

; --- WATCH WORD VALUES ---
MainGui.Add("GroupBox", "x665 y245 w210 h205", "Watch Word Values")
WatchWordLV := MainGui.Add("ListView", "x675 y263 w190 h145 Grid NoSortHdr vWatchWordLV", ["Name", "Value"])
WatchWordLV.ModifyCol(1, 70)
WatchWordLV.ModifyCol(2, 110)
WatchWordLV.OnEvent("ItemSelect", OnWatchWordSelect)
WatchWordLV.OnEvent("DoubleClick", OnWatchWordDblClick)
MainGui.Add("Button", "x675 y413 w60 h20", "Highlight").OnEvent("Click", HighlightSelectedWatchWord)
MainGui.Add("Button", "x740 y413 w60 h20", "Use").OnEvent("Click", UseSelectedWatchWord)
MainGui.Add("Button", "x805 y413 w60 h20", "Delete").OnEvent("Click", DeleteSelectedWatchWord)

; --- SEARCH IN OCR ---
MainGui.Add("GroupBox", "x15 y455 w430 h85", "Search & Text Operations")
MainGui.Add("Text", "x25 y473", "Find:")
OCRSearchEdit := MainGui.Add("Edit", "x60 y470 w150 vOCRSearch")
MainGui.Add("Button", "x215 y470 w50 h22", "Find").OnEvent("Click", FindInOCR)
MainGui.Add("Button", "x270 y470 w65 h22", "Highlight").OnEvent("Click", HighlightOCRMatch)
MainGui.Add("Button", "x340 y470 w55 h22", "Clear").OnEvent("Click", ClearOCRHighlights)
MainGui.Add("CheckBox", "x400 y473 vOCRCaseSense", "Case")
; Revolver loading options
MainGui.Add("Text", "x25 y500", "Revolver:")
OCRSplitDD := MainGui.Add("DropDownList", "x75 y497 w80 vOCRSplitMode", ["4 parts", "Tab", "Line", "Space", "Comma", "2 parts", "3 parts", "5 parts"])
OCRSplitDD.Choose(1)
MainGui.Add("Button", "x160 y497 w75 h22", "Load Rev").OnEvent("Click", LoadOCRToRevolverDD)
MainGui.Add("Button", "x240 y497 w75 h22", "Fire Rev").OnEvent("Click", FireOCRRevolverUI)
MainGui.Add("Text", "x320 y500 w100 vOCRRevolverStatus cGray", "Ready")

; --- OCR LOG ---
MainGui.Add("GroupBox", "x455 y455 w420 h85", "OCR Recording Log & Info")
MainGui.Add("Button", "x465 y473 w60 h22", "View").OnEvent("Click", ViewOCRLog)
MainGui.Add("Button", "x530 y473 w60 h22", "Clear").OnEvent("Click", ClearOCRLog)
MainGui.Add("Button", "x595 y473 w60 h22", "Export").OnEvent("Click", ExportOCRLog)
MainGui.Add("Text", "x660 y478 w40 vOCRLogCount cGray", "0")
MainGui.Add("Text", "x700 y478 w50 cGray", "entries")
MainGui.Add("Button", "x755 y473 w60 h22", "Languages").OnEvent("Click", GetOCRLanguages)
MainGui.Add("Button", "x820 y473 w50 h22", "Help").OnEvent("Click", ShowOCRHelp)
; Info row
MainGui.Add("Text", "x465 y500 w380 cGray", "OCR Revolver: paste captured text in parts. Load splits text, Fire pastes sequentially.")


; ═══════════════════════════════════════════════════════════════════════════════
; TAB 4: SPOOLS (EVENT-DRIVEN AUTOMATION / WEAVERS)
; ═══════════════════════════════════════════════════════════════════════════════
; TAB 4: SPOOLS (Event-Driven Automation / Weavers)
; =============================================================================
TabCtrl.UseTab(4)

; --- SPOOL MANAGER HEADER ---
MainGui.Add("GroupBox", "x15 y50 w860 h85", "Spool Manager - Continuous Event-Driven Automation")
MainGui.Add("Text", "x25 y68 w700", "Spools continuously monitor screen regions and trigger workflows when conditions are detected.")
MainGui.Add("Text", "x25 y83 w700 cGray", "Use cases: Weave notifications → update RevolutionHR, Coding tree → schedule reminder, Auto-capitalize names")

SpoolMasterToggle := MainGui.Add("CheckBox", "x25 y103 w150 vSpoolMasterToggle", "🔄 Master Enable")
SpoolMasterToggle.OnEvent("Click", ToggleSpoolMaster)
MainGui.Add("Text", "x180 y104 w100 cGreen vSpoolMasterStatus", "STOPPED")
MainGui.Add("Button", "x290 y100 w80 h22", "Start All").OnEvent("Click", StartAllSpools)
MainGui.Add("Button", "x375 y100 w80 h22", "Stop All").OnEvent("Click", StopAllSpools)
MainGui.Add("Text", "x480 y104 w100 vActiveSpoolCount", "Active: 0")
MainGui.Add("Button", "x600 y100 w80 h22", "Refresh").OnEvent("Click", (*) => RefreshSpoolLV())

; --- DEFINE NEW SPOOL ---
MainGui.Add("GroupBox", "x15 y140 w430 h335", "Define Spool")

MainGui.Add("Text", "x25 y158", "Name:")
SpoolNameEdit := MainGui.Add("Edit", "x70 yp-3 w130 vSpoolName")
SpoolEnabledChk := MainGui.Add("CheckBox", "x210 y158 vSpoolEnabled Checked", "Enabled")

; Monitor Region
MainGui.Add("Text", "x25 y188", "Region:")
SpoolRegionDD := MainGui.Add("DropDownList", "x70 yp-3 w100 vSpoolRegion", ["Full Screen", "Custom Region", "Active Window"])
SpoolRegionDD.Choose(1)
MainGui.Add("Button", "x175 yp w55 h22", "Select").OnEvent("Click", SelectSpoolRegion)
SpoolRegionText := MainGui.Add("Text", "x235 y188 w190 cGray vSpoolRegionText", "")

; Detection Type
MainGui.Add("Text", "x25 y218", "Detect:")
SpoolDetectDD := MainGui.Add("DropDownList", "x65 yp-3 w105 vSpoolDetect",
    ["Pattern Match", "Pattern Sequence", "OCR Contains", "OCR Regex", "Pixel Change", "Window Title"])
SpoolDetectDD.Choose(1)
SpoolDetectDD.OnEvent("Change", OnSpoolDetectChange)

; Detection Target (pattern name, OCR text, etc.)
MainGui.Add("Text", "x175 y218", "Target:")
SpoolTargetCombo := MainGui.Add("ComboBox", "x215 yp-3 w215 vSpoolTarget")

; Pattern Sequence helper text
SpoolSeqHelp := MainGui.Add("Text", "x25 y240 w400 cGray vSpoolSeqHelp", "")

; Detection Interval and Condition on same row
MainGui.Add("Text", "x25 y258", "Interval:")
SpoolIntervalEdit := MainGui.Add("Edit", "x70 yp-3 w45 vSpoolInterval Number", "500")
MainGui.Add("Text", "x120 y258", "ms")

MainGui.Add("Text", "x160 y258", "When:")
SpoolConditionDD := MainGui.Add("DropDownList", "x195 yp-3 w90 vSpoolCondition",
    ["Found", "Not Found", "Changed"])
SpoolConditionDD.Choose(1)

; === BEHAVIOR MODE (NEW) ===
MainGui.Add("GroupBox", "x25 y280 w405 h50", "Behavior After Trigger")
SpoolModeDD := MainGui.Add("DropDownList", "x35 y298 w100 vSpoolMode",
    ["Continuous", "One-Shot", "Cooldown"])
SpoolModeDD.Choose(1)
SpoolModeDD.OnEvent("Change", OnSpoolModeChange)

MainGui.Add("Text", "x145 y301 vSpoolCooldownLabel", "Cooldown:")
SpoolCooldownEdit := MainGui.Add("Edit", "x200 y298 w40 vSpoolCooldown Number", "5")
MainGui.Add("Text", "x245 y301", "sec")
MainGui.Add("Text", "x280 y301 w140 cGray vSpoolModeHelp", "(re-check after delay)")

; === ACTION WHEN TRIGGERED ===
MainGui.Add("GroupBox", "x25 y335 w405 h60", "Action When Triggered")
MainGui.Add("Text", "x35 y353", "Do:")
SpoolActionDD := MainGui.Add("DropDownList", "x55 yp-3 w105 vSpoolAction",
    ["Show Notification", "Run Workflow", "Start Spool", "Stop Spool", "Extract OCR", "Set Variable", "Key Chord", "Run Program"])
SpoolActionDD.Choose(1)
SpoolActionDD.OnEvent("Change", OnSpoolActionChange)

MainGui.Add("Text", "x165 y353", "Target:")
SpoolActionTargetCombo := MainGui.Add("ComboBox", "x200 yp-3 w160 vSpoolActionTarget")

; Notification timeout (shows when action is Show Notification)
MainGui.Add("Text", "x365 y353 vSpoolNotifLabel", "Time:")
SpoolNotifTimeEdit := MainGui.Add("Edit", "x395 y350 w30 vSpoolNotifTime Number", "5")

; OCR extraction checkbox
SpoolExtractOCRChk := MainGui.Add("CheckBox", "x35 y375 vSpoolExtractOCR", "Also extract OCR to:")
SpoolOCRVarEdit := MainGui.Add("Edit", "x160 y372 w70 vSpoolOCRVar", "")

; === AUTO-STOP CONDITION ===
MainGui.Add("GroupBox", "x25 y400 w405 h65", "Auto-Stop Condition (Optional)")
SpoolAutoCompleteChk := MainGui.Add("CheckBox", "x35 y418 vSpoolAutoComplete", "Stop spool when:")
SpoolCompletionDD := MainGui.Add("DropDownList", "x145 y415 w90 vSpoolCompletion",
    ["Pattern Found", "Pattern Gone", "OCR Contains", "Timeout", "Variable Set"])
SpoolCompletionDD.Choose(1)
SpoolCompletionTargetCombo := MainGui.Add("ComboBox", "x240 y415 w115 vSpoolCompletionTarget")
MainGui.Add("Text", "x360 y418", "or")
SpoolTimeoutEdit := MainGui.Add("Edit", "x380 y415 w35 vSpoolTimeout Number", "0")
MainGui.Add("Text", "x35 y440 cGray", "Timeout: 0 = no auto-stop")

; Spool Buttons
MainGui.Add("Button", "x25 y470 w80 h24", "Save Spool").OnEvent("Click", SaveSpool)
MainGui.Add("Button", "x110 y470 w70 h24", "Clear").OnEvent("Click", ClearSpoolForm)
MainGui.Add("Button", "x185 y470 w80 h24", "Test Once").OnEvent("Click", TestSpoolOnce)
MainGui.Add("Button", "x270 y470 w80 h24 cBlue", "Test Pattern").OnEvent("Click", TestSpoolPattern)

; --- SAVED SPOOLS LIST ---
MainGui.Add("GroupBox", "x455 y140 w420 h160", "Saved Spools (Right-click for options)")
SpoolLV := MainGui.Add("ListView", "x465 y158 w400 h115 Grid Checked NoSortHdr vSpoolLV",
    ["Name", "Detect", "Action", "Mode", "Status"])
SpoolLV.ModifyCol(1, 95)
SpoolLV.ModifyCol(2, 90)
SpoolLV.ModifyCol(3, 80)
SpoolLV.ModifyCol(4, 65)
SpoolLV.ModifyCol(5, 55)
SpoolLV.OnEvent("ItemSelect", OnSpoolSelect)
SpoolLV.OnEvent("ContextMenu", OnSpoolContextMenu)
SpoolLV.OnEvent("ItemCheck", OnSpoolCheck)

MainGui.Add("Button", "x465 y277 w55 h22", "Edit").OnEvent("Click", EditSpool)
MainGui.Add("Button", "x525 y277 w55 h22", "Delete").OnEvent("Click", DeleteSpool)
MainGui.Add("Button", "x585 y277 w55 h22", "Start").OnEvent("Click", StartSelectedSpool)
MainGui.Add("Button", "x645 y277 w55 h22", "Stop").OnEvent("Click", StopSelectedSpool)
MainGui.Add("Button", "x705 y277 w70 h22", "Duplicate").OnEvent("Click", DuplicateSpool)

; --- ACTIVE NOTIFICATIONS ---
MainGui.Add("GroupBox", "x455 y305 w420 h90", "Active Notifications")
NotificationLV := MainGui.Add("ListView", "x465 y323 w400 h45 Grid NoSortHdr vNotificationLV",
    ["ID", "Title", "Remaining", "Spool"])
NotificationLV.ModifyCol(1, 35)
NotificationLV.ModifyCol(2, 180)
NotificationLV.ModifyCol(3, 65)
NotificationLV.ModifyCol(4, 100)

MainGui.Add("Button", "x465 y372 w70 h20", "Dismiss All").OnEvent("Click", DismissAllNotifications)
MainGui.Add("Button", "x540 y372 w50 h20", "View").OnEvent("Click", ViewNotification)
MainGui.Add("Text", "x600 y375 w200 cGray", "Notifications auto-dismiss after timeout")

; --- OCR VARIABLES ---
MainGui.Add("GroupBox", "x455 y400 w200 h95", "Extracted Variables")
OCRVarsLV := MainGui.Add("ListView", "x465 y418 w180 h55 Grid NoSortHdr vOCRVarsLV",
    ["Variable", "Value"])
OCRVarsLV.ModifyCol(1, 70)
OCRVarsLV.ModifyCol(2, 100)

MainGui.Add("Button", "x465 y476 w50 h18", "Clear").OnEvent("Click", ClearOCRVars)
MainGui.Add("Button", "x520 y476 w50 h18", "Use").OnEvent("Click", UseOCRVar)
MainGui.Add("Button", "x575 y476 w60 h18", "Refresh").OnEvent("Click", (*) => RefreshOCRVarsLV())

; --- SPOOL LOG ---
MainGui.Add("GroupBox", "x665 y400 w210 h95", "Activity Log")
SpoolLogEdit := MainGui.Add("Edit", "x675 y418 w190 h55 ReadOnly Multi vSpoolLog", "")
MainGui.Add("Button", "x815 y476 w50 h18", "Clear").OnEvent("Click", ClearSpoolLog)


; ═══════════════════════════════════════════════════════════════════════════════
; TAB 5: ANALYTICS
; ═══════════════════════════════════════════════════════════════════════════════
; TAB 5: ANALYTICS
; =============================================================================
TabCtrl.UseTab(5)

MainGui.Add("GroupBox", "x15 y50 w860 h180", "Full Recording - Workflow Discovery")

MainGui.Add("Text", "x25 y68 w800", "Record ALL user actions for workflow analysis and pattern discovery.")

MainGui.Add("Button", "x25 y90 w120 h26", "Start Recording").OnEvent("Click", (*) => StartFullRecording())
MainGui.Add("Button", "x150 y90 w120 h26", "Stop Recording").OnEvent("Click", (*) => StopFullRecording())
AnalyticsText := MainGui.Add("Text", "x280 y95 w150", "Events: 0")

MainGui.Add("Text", "x25 y125", "Recording captures:")
MainGui.Add("Text", "x25 y140 w400", "- Clicks with coordinates, window context, auto-pattern")
MainGui.Add("Text", "x25 y155 w400", "- Mouse hotspots per window (grid-based)")
MainGui.Add("Text", "x25 y170 w400", "- Action methodology (keyboard vs mouse)")
MainGui.Add("Text", "x25 y185 w400", "- Window focus and timing data")

MainGui.Add("Text", "x430 y125", "Taskbar Apps (Win+N shortcuts):")
MainGui.Add("Text", "x565 y125 cGray", "Click 'Index Taskbar' to scan")
TaskbarLV := MainGui.Add("ListView", "x430 y140 w430 h75 Grid NoSortHdr", ["#", "Application", "Hotkey"])
TaskbarLV.ModifyCol(1, 25)
TaskbarLV.ModifyCol(2, 335)
TaskbarLV.ModifyCol(3, 60)

MainGui.Add("Button", "x25 y205 w100 h22", "View Log").OnEvent("Click", ViewRecordingLog)
MainGui.Add("Button", "x130 y205 w100 h22", "Clear Log").OnEvent("Click", ClearRecordingLog)
MainGui.Add("Button", "x235 y205 w100 h22", "Export CSV").OnEvent("Click", ExportRecording)
MainGui.Add("Button", "x430 y205 w130 h22", "Index Taskbar").OnEvent("Click", (*) => IndexTaskbarManual())

; Hotspots display
MainGui.Add("GroupBox", "x15 y240 w860 h100", "Window Hotspots")
HotspotsLV := MainGui.Add("ListView", "x25 y258 w840 h75 Grid NoSortHdr", ["Window/App", "Top Hotspot", "Click Count"])
HotspotsLV.ModifyCol(1, 350)
HotspotsLV.ModifyCol(2, 300)
HotspotsLV.ModifyCol(3, 150)


; ═══════════════════════════════════════════════════════════════════════════════
; TAB 6: CLIPBOARD & REVOLVER
; ═══════════════════════════════════════════════════════════════════════════════
; TAB 6: CLIPBOARD & REVOLVER
; =============================================================================
TabCtrl.UseTab(6)

; --- CLIPBOARD INPUT ---
MainGui.Add("Text", "x15 y55", "Clipboard:")
ClipEdit := MainGui.Add("Edit", "x15 y70 w400 h70 Multi vClipContent")
MainGui.Add("Button", "x420 y70 w70 h22", "Grab").OnEvent("Click", GrabClip)
MainGui.Add("Button", "x420 y95 w70 h22", "Parse").OnEvent("Click", ParseClip)
MainGui.Add("Button", "x420 y120 w70 h22", "Clear").OnEvent("Click", ClearClip)

; --- EXTRACTION RULES ---
MainGui.Add("Text", "x15 y150", "Rules:")
RulesLV := MainGui.Add("ListView", "x15 y165 w350 h65 Grid NoSortHdr", ["Name", "Pattern", "Result"])
RulesLV.ModifyCol(1, 80)
RulesLV.ModifyCol(2, 170)
RulesLV.ModifyCol(3, 90)

MainGui.Add("Text", "x15 y235", "Name:")
MainGui.Add("Edit", "x55 yp-3 w70 vPatternNameClip")
MainGui.Add("Text", "x130 yp+3", "Regex:")
MainGui.Add("Edit", "x170 yp-3 w150 vPatternRegex")
MainGui.Add("Button", "x325 yp w40 h22", "Add").OnEvent("Click", AddRule)
MainGui.Add("Button", "x370 yp w40 h22", "Del").OnEvent("Click", DelRule)

; --- EXTRACTED DATA ---
MainGui.Add("Text", "x15 y265", "Extracted:")
ExtractLV := MainGui.Add("ListView", "x15 y280 w350 h70 Grid NoSortHdr", ["Field", "Value"])
ExtractLV.ModifyCol(1, 100)
ExtractLV.ModifyCol(2, 240)

; --- REVOLVER SYSTEM ---
MainGui.Add("GroupBox", "x380 y145 w490 h205", "Clipboard Revolver (Sequential Paste)")

MainGui.Add("Text", "x390 y163", "Field Order (paste sequence):")
FieldOrderLV := MainGui.Add("ListView", "x390 y178 w180 h80 Grid NoSortHdr", ["#", "Field"])
FieldOrderLV.ModifyCol(1, 25)
FieldOrderLV.ModifyCol(2, 145)

MainGui.Add("Button", "x575 y178 w40 h22", "▲").OnEvent("Click", MoveFieldUp)
MainGui.Add("Button", "x575 y203 w40 h22", "▼").OnEvent("Click", MoveFieldDown)
MainGui.Add("Button", "x575 y228 w40 h22", "+").OnEvent("Click", AddFieldToOrder)
MainGui.Add("Button", "x575 y253 w40 h22", "-").OnEvent("Click", RemoveFieldFromOrder)

MainGui.Add("Text", "x630 y163", "Loaded Chambers:")
RevolverLV := MainGui.Add("ListView", "x630 y178 w235 h80 Grid NoSortHdr", ["#", "Field", "Value", "Status"])
RevolverLV.ModifyCol(1, 20)
RevolverLV.ModifyCol(2, 70)
RevolverLV.ModifyCol(3, 95)
RevolverLV.ModifyCol(4, 45)

RevolverStatus := MainGui.Add("Text", "x390 y268 w220 cGray", "Revolver: Empty")

MainGui.Add("Button", "x390 y290 w100 h28", "Load Revolver").OnEvent("Click", (*) => LoadRevolver())
MainGui.Add("Button", "x495 y290 w100 h28", "Unload").OnEvent("Click", (*) => UnloadRevolver())
MainGui.Add("Button", "x600 y290 w130 h28 cGreen", "▶ Fire All").OnEvent("Click", (*) => FireAllShots())

MainGui.Add("Text", "x390 y325 w470 cBlue", "Ctrl+B = Load revolver  |  Ctrl+Shift+B = Fire all shots")

; --- QUICK REFERENCE ---
MainGui.Add("GroupBox", "x15 y360 w855 h125", "Revolver Quick Reference")
MainGui.Add("Text", "x25 y378", "HOTKEY MODE:")
MainGui.Add("Text", "x25 y393 cGreen", "  Ctrl+B      = Copy + Parse + Load")
MainGui.Add("Text", "x25 y408 cGreen", "  Ctrl+Shift+B = Fire all shots (paste+Tab...)")
MainGui.Add("Text", "x25 y428", "  (Navigate to target between load and fire)")

MainGui.Add("Text", "x280 y378", "WORKFLOW ACTIONS (for sequences):")
MainGui.Add("Text", "x280 y393", "  Parse Clipboard  → extract from A_Clipboard")
MainGui.Add("Text", "x280 y408", "  Load Revolver    → load extracted fields")
MainGui.Add("Text", "x280 y423", "  Fire Revolver    → paste + Tab each field")
MainGui.Add("Text", "x280 y438", "  Fire Revolver+Enter → same + Enter")

MainGui.Add("Text", "x600 y378", "TYPICAL USE:")
MainGui.Add("Text", "x600 y393 cBlue", "  1. Select patient text")
MainGui.Add("Text", "x600 y408 cBlue", "  2. Ctrl+B (chirp = loaded)")
MainGui.Add("Text", "x600 y423 cBlue", "  3. Navigate to form fields")
MainGui.Add("Text", "x600 y438 cBlue", "  4. Click first field")
MainGui.Add("Text", "x600 y453 cBlue", "  5. Ctrl+Shift+B (fires all)")
MainGui.Add("Text", "x600 y468 cBlue", "  6. Double-beep = done")


; ═══════════════════════════════════════════════════════════════════════════════
; TAB 7: HOTKEYS
; ═══════════════════════════════════════════════════════════════════════════════
; TAB 7: HOTKEYS
; =============================================================================
TabCtrl.UseTab(7)

MainGui.Add("Text", "x15 y55", "Assigned:")
HotkeyLV := MainGui.Add("ListView", "x15 y70 w500 h150 Grid NoSortHdr", ["Hotkey", "Sequence"])
HotkeyLV.ModifyCol(1, 150)
HotkeyLV.ModifyCol(2, 340)

MainGui.Add("Text", "x15 y230", "Mod:")
ModDD := MainGui.Add("DropDownList", "x50 yp-3 w90 vModifier", ["(none)", "Ctrl", "Alt", "Shift", "Ctrl+Alt", "Ctrl+Shift"])
ModDD.Choose(2)
MainGui.Add("Text", "x145 yp+3", "Key:")
KeyEditHK := MainGui.Add("Edit", "x175 yp-3 w50 vHotkeyKey", "1")
MainGui.Add("Text", "x230 yp+3", "Seq:")
SeqDDHK := MainGui.Add("DropDownList", "x260 yp-3 w150 vHotkeySeq")

MainGui.Add("Button", "x15 y260 w70 h24", "Add").OnEvent("Click", AddHotkey)
MainGui.Add("Button", "x90 yp w70 h24", "Remove").OnEvent("Click", RemoveHotkey)
MainGui.Add("Button", "x165 yp w70 h24", "Apply").OnEvent("Click", ApplyHotkeys)


; ═══════════════════════════════════════════════════════════════════════════════
; TAB 8: HOTSTRINGS (V5.0 NEW)
; ═══════════════════════════════════════════════════════════════════════════════
TabCtrl.UseTab(8)

MainGui.Add("GroupBox", "x15 y50 w860 h50", "Hotstring Management - Text Expansion & Auto-Replacement")
MainGui.Add("Text", "x25 y68 w840", "Define text shortcuts that automatically expand when typed. Example: typing 'btw' expands to 'by the way'")

MainGui.Add("GroupBox", "x15 y105 w860 h40", "Master Control")
HotstringMasterToggle := MainGui.Add("CheckBox", "x25 y120 Checked", "Enable All Hotstrings")
HotstringMasterToggle.OnEvent("Click", ToggleAllHotstrings)

global HotstringLV := MainGui.Add("ListView", "x15 y150 w860 h300", ["Enabled", "Trigger", "Replacement", "Options"])
HotstringLV.ModifyCol(1, 60)
HotstringLV.ModifyCol(2, 150)
HotstringLV.ModifyCol(3, 450)
HotstringLV.ModifyCol(4, 180)
HotstringLV.OnEvent("DoubleClick", EditHotstring)

MainGui.Add("Button", "x15 y460 w100 h24", "Add New").OnEvent("Click", AddHotstring)
MainGui.Add("Button", "x120 y460 w100 h24", "Edit").OnEvent("Click", EditHotstringFromBtn)
MainGui.Add("Button", "x225 y460 w100 h24", "Delete").OnEvent("Click", DeleteHotstring)
MainGui.Add("Button", "x330 y460 w120 h24", "Enable/Disable").OnEvent("Click", ToggleHotstring)
MainGui.Add("Button", "x455 y460 w100 h24", "Test").OnEvent("Click", TestHotstring)
MainGui.Add("Button", "x560 y460 w100 h24", "Refresh").OnEvent("Click", (*) => RefreshHotstringList())

MainGui.Add("GroupBox", "x15 y490 w860 h120", "Hotstring Options Reference")
MainGui.Add("Text", "x25 y510 w840", "Options control how hotstrings behave when triggered:")
MainGui.Add("Text", "x25 y530 w840", "C = Case Sensitive  |  * = No end character required  |  ? = Trigger inside words")
MainGui.Add("Text", "x25 y550 w840", "B = No auto-backspace  |  O = Omit end character  |  T = Send as text mode")
MainGui.Add("Text", "x25 y570 w840", "Example: C* means case-sensitive and no end character needed")
MainGui.Add("Text", "x25 y590 w840", "Leave blank for default behavior (case-insensitive, requires space/tab after trigger)")


; ═══════════════════════════════════════════════════════════════════════════════
; TAB 9: TRIGGERS (V5.1 NEW - Advanced Notification Manager)
; ═══════════════════════════════════════════════════════════════════════════════
TabCtrl.UseTab(9)

MainGui.Add("GroupBox", "x15 y50 w860 h60", "Advanced Notification & Automation Trigger System")
MainGui.Add("Text", "x25 y68 w840", "Create triggers that fire notifications or run sequences based on time, OCR detection, action results, variable values, and more.")
MainGui.Add("Text", "x25 y88 w840 cBlue", "Hyper-flexible: Combine multiple conditions, chain actions, monitor in real-time, and debug your workflows.")

MainGui.Add("GroupBox", "x15 y115 w420 h50", "Master Control")
TriggerMasterToggle := MainGui.Add("CheckBox", "x25 y135 Checked", "Enable All Triggers")
TriggerMasterToggle.OnEvent("Click", ToggleAllTriggers)
MainGui.Add("Button", "x200 y132 w80 h24", "Start Monitor").OnEvent("Click", StartTriggerMonitoring)
MainGui.Add("Button", "x285 y132 w80 h24", "Stop Monitor").OnEvent("Click", StopTriggerMonitoring)

MainGui.Add("GroupBox", "x445 y115 w430 h50", "Quick Actions")
MainGui.Add("Button", "x455 y132 w100 h24", "Test Trigger").OnEvent("Click", TestSelectedTrigger)
MainGui.Add("Button", "x560 y132 w100 h24", "View Log").OnEvent("Click", ViewTriggerLog)
MainGui.Add("Button", "x665 y132 w100 h24", "Clear Log").OnEvent("Click", ClearTriggerLog)
MainGui.Add("Button", "x770 y132 w95 h24 cGreen", "Templates").OnEvent("Click", ShowTriggerTemplates)

global TriggersLV := MainGui.Add("ListView", "x15 y170 w860 h250", ["✓", "Name", "Type", "Condition", "Action", "Last Fired"])
TriggersLV.ModifyCol(1, 30)
TriggersLV.ModifyCol(2, 150)
TriggersLV.ModifyCol(3, 100)
TriggersLV.ModifyCol(4, 250)
TriggersLV.ModifyCol(5, 180)
TriggersLV.ModifyCol(6, 130)
TriggersLV.OnEvent("DoubleClick", EditTrigger)

MainGui.Add("Button", "x15 y430 w100 h24", "Add Trigger").OnEvent("Click", AddTrigger)
MainGui.Add("Button", "x120 y430 w100 h24", "Edit").OnEvent("Click", EditTriggerFromBtn)
MainGui.Add("Button", "x225 y430 w100 h24", "Delete").OnEvent("Click", DeleteTrigger)
MainGui.Add("Button", "x330 y430 w120 h24", "Enable/Disable").OnEvent("Click", ToggleTrigger)
MainGui.Add("Button", "x455 y430 w100 h24", "Duplicate").OnEvent("Click", DuplicateTrigger)
MainGui.Add("Button", "x560 y430 w100 h24", "Export").OnEvent("Click", ExportTrigger)
MainGui.Add("Button", "x665 y430 w100 h24", "Import").OnEvent("Click", ImportTrigger)

MainGui.Add("GroupBox", "x15 y460 w860 h150", "Trigger Types & Capabilities")
MainGui.Add("Text", "x25 y480 w840", "⏰ TIME-BASED: Fire at specific times, intervals, or schedules")
MainGui.Add("Text", "x25 y500 w840", "🔍 OCR-BASED: Trigger when specific text appears/disappears on screen")
MainGui.Add("Text", "x25 y520 w840", "⚡ ACTION-BASED: Fire before/after specific actions or sequences complete")
MainGui.Add("Text", "x25 y540 w840", "📊 VARIABLE-BASED: Monitor variable values and trigger on changes or thresholds")
MainGui.Add("Text", "x25 y560 w840", "🐛 DEBUG-BASED: Log action execution, errors, timing, and performance metrics")
MainGui.Add("Text", "x25 y580 w840", "🔗 CHAINED: Combine multiple conditions with AND/OR logic, execute multiple actions")


; ═══════════════════════════════════════════════════════════════════════════════
; TAB 10: SETTINGS
; ═══════════════════════════════════════════════════════════════════════════════
; TAB 10: SETTINGS
; =============================================================================
TabCtrl.UseTab(10)

MainGui.Add("GroupBox", "x15 y50 w350 h100", "Timing (ms)")
MainGui.Add("Text", "x25 y70", "Click:")
MainGui.Add("Edit", "x65 yp-3 w45 vClickDelay Number", g_Settings["ClickDelay"])
MainGui.Add("Text", "x115 yp+3", "Type:")
MainGui.Add("Edit", "x150 yp-3 w45 vTypeDelay Number", g_Settings["TypeDelay"])
MainGui.Add("Text", "x200 yp+3", "Action:")
MainGui.Add("Edit", "x245 yp-3 w45 vActionDelay Number", g_Settings["ActionDelay"])
MainGui.Add("Text", "x25 y100", "Pre:")
MainGui.Add("Edit", "x55 yp-3 w45 vPreActionDelay Number", g_Settings["PreActionDelay"])
MainGui.Add("Text", "x105 yp+3", "Post:")
MainGui.Add("Edit", "x140 yp-3 w45 vPostActionDelay Number", g_Settings["PostActionDelay"])
MainGui.Add("Text", "x190 yp+3", "Drag:")
MainGui.Add("Edit", "x225 yp-3 w45 vDragTime Number", g_Settings["DefaultDragTime"])

MainGui.Add("GroupBox", "x15 y155 w350 h70", "Tooltips")
MainGui.Add("Text", "x25 y175", "Status Duration:")
MainGui.Add("Edit", "x115 yp-3 w50 vTooltipDuration Number", g_Settings["TooltipDuration"])
MainGui.Add("Text", "x170 yp+3", "ms")
MainGui.Add("Text", "x25 y200", "Preview Duration:")
MainGui.Add("Edit", "x115 yp-3 w50 vPreviewTooltipDuration Number", g_Settings["PreviewTooltipDuration"])
MainGui.Add("Text", "x170 yp+3", "ms")

MainGui.Add("GroupBox", "x15 y230 w350 h70", "Verification")
MainGui.Add("Text", "x25 y250", "Max Retries:")
MainGui.Add("Edit", "x95 yp-3 w40 vMaxRetries Number", g_Settings["MaxRetries"])
MainGui.Add("Text", "x145 yp+3", "Win Timeout:")
MainGui.Add("Edit", "x220 yp-3 w50 vWindowActivateTimeout Number", g_Settings["WindowActivateTimeout"])

MainGui.Add("GroupBox", "x15 y305 w350 h70", "FindText")
MainGui.Add("Text", "x25 y325", "Tolerance:")
MainGui.Add("Edit", "x80 yp-3 w50 vFindTextTolerance", g_Settings["FindTextTolerance"])
MainGui.Add("Text", "x135 yp+3", "(0-1)")
MainGui.Add("Text", "x180 yp", "Timeout:")
MainGui.Add("Edit", "x230 yp-3 w50 vFindTextTimeout Number", g_Settings["FindTextTimeout"])

MainGui.Add("GroupBox", "x15 y380 w350 h75", "Failsafes")
MainGui.Add("CheckBox", "x25 y398 vFailsafeCheckCloseButton Checked", "Block clicks near window close buttons")
MainGui.Add("CheckBox", "x25 y418 vAutoCapPattern Checked", "Auto-capture patterns on recording")
MainGui.Add("CheckBox", "x25 y438 vDefModeAutoPattern Checked", "Definition Mode auto-pattern capture")

; Notification Settings
MainGui.Add("GroupBox", "x380 y380 w200 h95", "Notifications")
MainGui.Add("CheckBox", "x390 y400 vDebugMode Checked", "Debug Mode (show all steps)")
MainGui.Add("CheckBox", "x390 y420 vNotifDismissible Checked", "Dismissible (stay until clicked)")
MainGui.Add("Text", "x390 y440", "Auto-dismiss:")
MainGui.Add("Edit", "x465 y437 w40 vNotifTimeout Number", "5")
MainGui.Add("Text", "x510 y440", "sec")

MainGui.Add("Button", "x15 y465 w80 h24", "Save").OnEvent("Click", SaveSettingsGUI)
MainGui.Add("Button", "x100 yp w80 h24", "Reset").OnEvent("Click", ResetSettingsGUI)
MainGui.Add("Button", "x185 yp w100 h24", "Open Folder").OnEvent("Click", (*) => Run(DATA_DIR))

; Reference
MainGui.Add("GroupBox", "x380 y50 w490 h405", "Reference")
MainGui.Add("Text", "x390 y70", "DEFINITION MODE (CAPSLOCK ON):")
MainGui.Add("Text", "x390 y85 cBlue", "  C=Click  D=Drag(2x)  R=RightClick  T=Triple")
MainGui.Add("Text", "x390 y100 cBlue", "  P=Pattern  W=Wait  K=SendKeys  M=MenuSelect")
MainGui.Add("Text", "x390 y115 cBlue", "  ESC=Cancel/Hide tooltip")
MainGui.Add("Text", "x390 y140", "SEND KEYS: ^=Ctrl +=Shift !=Alt #=Win")
MainGui.Add("Text", "x390 y155", "  ^c=Ctrl+C  ^v=Ctrl+V  !d=Alt+D  #1=Win+1")
MainGui.Add("Text", "x390 y180", "FIND ACTIONS:")
MainGui.Add("Text", "x390 y195", "  Find & Click/DblClick/TplClick/RClick/Drag")
MainGui.Add("Text", "x390 y210", "  Wait for Pattern / Wait Until Gone")
MainGui.Add("Text", "x390 y235", "GLOBAL HOTKEYS:")
MainGui.Add("Text", "x390 y250", "  Ctrl+Shift+G - Toggle window")
MainGui.Add("Text", "x390 y265", "  Ctrl+Shift+P - Pause/Resume")
MainGui.Add("Text", "x390 y280", "  Ctrl+Shift+X - Abort sequence")
MainGui.Add("Text", "x390 y295", "  Ctrl+Shift+C - Clear notifications")
MainGui.Add("Text", "x390 y310", "  Ctrl+Shift+F - FindText GUI")
MainGui.Add("Text", "x390 y325", "  Ctrl+B - Load revolver (copy+parse)")
MainGui.Add("Text", "x390 y340", "  Ctrl+Shift+B - Fire all shots")
MainGui.Add("Text", "x390 y360", "TASKBAR:")
MainGui.Add("Text", "x390 y375", "  Analytics tab -> Index Taskbar button")
MainGui.Add("Text", "x390 y390", "  Saved to data/taskbar.ini")
MainGui.Add("Text", "x390 y410", "REVOLVER (Clipboard tab):")
MainGui.Add("Text", "x390 y425", "  Configure field order with ▲▼ buttons")
MainGui.Add("Text", "x390 y445", "VISUAL: Green=OK, Blue=Progress, Red=Fail")


; TAB 11: NOTEPAD
; ═══════════════════════════════════════════════════════════════════════════════
TabCtrl.UseTab(11)

MainGui.Add("Text", "x20 y55", "Quick Notepad for Testing & Automation")
MainGui.Add("Text", "x20 y75 c888888", "Use this to test text entry, write notes, or prepare automation content")

notepadEdit := MainGui.Add("Edit", "x20 y95 w760 h400 vNotepadEdit Multi WantTab", "")
notepadEdit.Name := "NotepadEdit"

MainGui.Add("Button", "x20 y505 w120", "Save Note").OnEvent("Click", SaveNotepadContent)
MainGui.Add("Button", "x145 y505 w120", "Load Note").OnEvent("Click", LoadNotepadContent)
MainGui.Add("Button", "x270 y505 w120", "Clear").OnEvent("Click", ClearNotepadContent)
MainGui.Add("Button", "x395 y505 w120", "Open Popup").OnEvent("Click", OpenNotepadPopup)
MainGui.Add("Button", "x520 y505 w150", "Copy to Clipboard").OnEvent("Click", (*) => CopyNotepadToClipboard())

MainGui.Add("Text", "x20 y535", "Saved Notes:")
noteListLV := MainGui.Add("ListView", "x20 y555 w760 h60", ["Filename", "Modified", "Size"])
noteListLV.Name := "NoteListLV"
noteListLV.OnEvent("DoubleClick", LoadSelectedNote)

; ═══════════════════════════════════════════════════════════════════════════════
; STATUS BAR
; ═══════════════════════════════════════════════════════════════════════════════
; STATUS BAR
; =============================================================================
TabCtrl.UseTab(0)
StatusBar := MainGui.Add("StatusBar",, "Ready | CAPSLOCK = Definition Mode | Ctrl+Shift+G: Toggle")

; Calendar view
TabCtrl.UseTab(12)

MainGui.Add("Text", "x15 y50", "📅 Appointment Scheduler")
MainGui.Add("Button", "x150 y50 w60 h25", "◄ Prev").OnEvent("Click", PrevDay)
global DateText := MainGui.Add("Text", "x215 y55 w200 Center", FormatTime(g_CalendarDate, "dddd, MMMM d, yyyy"))
MainGui.Add("Button", "x420 y50 w60 h25", "Next ►").OnEvent("Click", NextDay)
MainGui.Add("Button", "x490 y50 w60 h25", "Today").OnEvent("Click", GoToToday)
MainGui.Add("Button", "x560 y50 w85 h25", "Patients").OnEvent("Click", OpenPatientList)

; Time slots (create one button per slot)
yPos := 90
slots := GenerateTimeSlots()

for time in slots {
    ; Time label
    MainGui.Add("Text", "x15 y" . yPos, time)

    ; Appointment slot button
    btn := MainGui.Add("Button", "x70 y" . (yPos-3) . " w650 h28", "[Empty]")
    btn.OnEvent("Click", ClickTimeSlot.Bind(time))
    g_CalendarSlotButtons[time] := btn

    yPos += 30
}

; Calendar data is optional and must never prevent core workflow/template startup.
try InitializeAppointmentScheduler()
catch as err
    LogErrorToFile(err, "caught", "Optional appointment scheduler initialization")
try RefreshCalendar()
catch as err
    LogErrorToFile(err, "caught", "Optional appointment calendar refresh")

MainGui.Show("w1050 h820")

ClickTimeSlot2(time) {
    ; Show input box for patient name and appointment type
    result := InputBox("Enter: Patient Name | Appointment Type",
                       "Book Appointment at " . time,
                       "w400 h150")

    if (result.Result = "OK") {
        ; Save appointment
        key := g_CalendarDate . "_" . StrReplace(time, ":", "")
        g_Appointments[key] := result.Value

        ; Create notification
        CreateSimpleNotification(g_CalendarDate, time, result.Value)

        ; Refresh display
        RefreshCalendar()
        SaveAppointments()
    }
}
CreateSimpleNotification(date, time, appointmentInfo) {
    ; Schedule notification at appointment time
    triggerTime := date . " " . time

    ; Add to existing notification system
    title := "Appointment"
    message := appointmentInfo

    ; Store for monitoring
    ; (Use existing notification system from Tab 4)
}

SaveAppointments() {
    global g_Appointments, DATA_DIR
    iniFile := A_ScriptDir . "\Data\appointments.ini"
    if !DirExist(DATA_DIR)
        DirCreate(DATA_DIR)
    if FileExist(iniFile)
        FileDelete(iniFile)

    IniWrite(7, iniFile, "Meta", "Version")
    for key, appointment in g_Appointments {
        section := "Appointment_" . key
        if IsObject(appointment) && appointment is Map {
            IniWrite(appointment.Has("date") ? appointment["date"] : SubStr(key, 1, 8), iniFile, section, "Date")
            IniWrite(appointment.Has("time") ? appointment["time"] : "", iniFile, section, "Time")
            IniWrite(appointment.Has("patientID") ? appointment["patientID"] : 0, iniFile, section, "PatientID")
            IniWrite(appointment.Has("patientName") ? appointment["patientName"] : CalendarAppointmentText(appointment), iniFile, section, "PatientName")
            IniWrite(appointment.Has("appointmentType") ? appointment["appointmentType"] : "", iniFile, section, "AppointmentType")
            IniWrite(appointment.Has("typeName") ? appointment["typeName"] : "", iniFile, section, "TypeName")
            IniWrite(appointment.Has("status") ? appointment["status"] : "Scheduled", iniFile, section, "Status")
        } else {
            IniWrite(SubStr(key, 1, 8), iniFile, section, "Date")
            IniWrite("", iniFile, section, "Time")
            IniWrite(String(appointment), iniFile, section, "PatientName")
            IniWrite("Legacy", iniFile, section, "Status")
        }
    }
}

LoadAppointments() {
    global g_Appointments, g_AppointmentTypes
    iniFile := A_ScriptDir . "\Data\appointments.ini"
    if !FileExist(iniFile)
        return

    g_Appointments := Map()
    sections := ""
    try sections := IniRead(iniFile)
    for section in StrSplit(sections, "`n", "`r") {
        section := Trim(section)
        if InStr(section, "Appointment_") != 1
            continue
        date := IniRead(iniFile, section, "Date", "")
        time := IniRead(iniFile, section, "Time", "")
        patientIDText := IniRead(iniFile, section, "PatientID", "0")
        patientName := IniRead(iniFile, section, "PatientName", "")
        appointmentType := IniRead(iniFile, section, "AppointmentType", "")
        typeName := IniRead(iniFile, section, "TypeName", "")
        status := IniRead(iniFile, section, "Status", "Scheduled")
        if date = "" {
            keyFromSection := SubStr(section, 13)
            date := SubStr(keyFromSection, 1, 8)
        }
        if time = "" {
            keyFromSection := SubStr(section, 13)
            cleanTime := SubStr(keyFromSection, 10, 4)
            if StrLen(cleanTime) = 4
                time := SubStr(cleanTime, 1, 2) . ":" . SubStr(cleanTime, 3, 2)
        }
        if date = "" || time = ""
            continue
        typeInfo := g_AppointmentTypes.Has(appointmentType) ? g_AppointmentTypes[appointmentType] : Map("duration", 30, "tasks", [])
        key := GetAppointmentKey(date, time)
        g_Appointments[key] := Map(
            "date", date, "time", time,
            "patientID", IsNumber(patientIDText) ? Integer(patientIDText) : 0,
            "patientName", patientName,
            "appointmentType", appointmentType,
            "typeName", typeName,
            "duration", typeInfo["duration"],
            "tasks", typeInfo["tasks"],
            "status", status
        )
    }

    ; Backward compatibility with the repaired v6.1 single-section format.
    if g_Appointments.Count = 0 {
        try sectionText := IniRead(iniFile, "Appointments")
        catch
            sectionText := ""
        Loop Parse, sectionText, "`n", "`r" {
            line := Trim(A_LoopField)
            separator := InStr(line, "=")
            if separator {
                key := Trim(SubStr(line, 1, separator - 1))
                info := SubStr(line, separator + 1)
                if key != ""
                    g_Appointments[key] := info
            }
        }
    }
}
; ═══════════════════════════════════════════════════════════════════════════════
; GUI FUNCTIONS
; ═══════════════════════════════════════════════════════════════════════════════
; GUI FUNCTIONS
; =============================================================================
; ═══════════════════════════════════════════════════════════════════════════════
; SECTION 3: NEW WORKFLOW ACTIONS
; ═══════════════════════════════════════════════════════════════════════════════
; Add these to the ExecuteAction() function's switch statement
; ═══════════════════════════════════════════════════════════════════════════════

; IDLE MOUSE - Wait for X seconds or until harsh mouse movement
; Format: "IdleMouse,duration" where duration in seconds (0 = indefinite)
ExecuteIdleMouse(params) {
    global g_MouseIdleActive, g_MouseIdleDuration, g_MouseLastX, g_MouseLastY
    global g_MouseHarshThreshold, g_Settings

    ; Parse duration
    duration := params != "" ? Integer(params) : 0  ; 0 = indefinite

    g_MouseIdleDuration := duration
    g_MouseIdleActive := true

    ; Get initial position
    MouseGetPos(&g_MouseLastX, &g_MouseLastY)

    ShowStatus("Mouse idle: " . (duration = 0 ? "indefinite" : duration . "s"), "wait")

    ; Calculate end time
    endTime := duration > 0 ? A_TickCount + (duration * 1000) : 0

    ; Monitor mouse movement
    Loop {
        if !g_MouseIdleActive
            break

        ; Check if duration expired
        if endTime > 0 && A_TickCount >= endTime {
            ShowStatus("Mouse idle complete (timeout)", "ok")
            break
        }

        ; Check for harsh movement
        MouseGetPos(&currentX, &currentY)
        deltaX := Abs(currentX - g_MouseLastX)
        deltaY := Abs(currentY - g_MouseLastY)

        if deltaX >= g_MouseHarshThreshold || deltaY >= g_MouseHarshThreshold {
            ShowStatus("Mouse idle ended (harsh movement detected)", "ok")
            break
        }

        ; Update last position for next check
        g_MouseLastX := currentX
        g_MouseLastY := currentY

        Sleep(g_Settings["VerifyInterval"])
    }

    g_MouseIdleActive := false
    return true
}

; HOVER MOUSE - Move mouse to coordinate and leave it there
; Format: "HoverMouse,x,y" or "HoverMouse,CoordName"
ExecuteHoverMouse(params) {
    global g_Coordinates, g_Settings

    if params = "" {
        ShowStatus("HoverMouse requires coordinates", "fail")
        return false
    }

    ; Check if it's a coordinate name
    if g_Coordinates.Has(params) {
        coord := g_Coordinates[params]
        x := coord["x"]
        y := coord["y"]
    } else {
        ; Parse x,y
        parts := StrSplit(params, ",")
        if parts.Length < 2 {
            ShowStatus("HoverMouse format: x,y or CoordName", "fail")
            return false
        }
        x := Integer(parts[1])
        y := Integer(parts[2])
    }

    ; Move mouse
    MouseMove(x, y, 5)
    Sleep(g_Settings["PostActionDelay"])

    ShowStatus("Mouse hovering at " . x . "," . y, "ok")
    return true
}

; GRAB OCR TEXT TO VARIABLE - Capture OCR text and store in variable
; Format: "GrabOCRToVar,variableName,x1,y1,x2,y2" or "GrabOCRToVar,variableName,RegionName"
ExecuteGrabOCRToVar(params) {
    global g_ExtractedData, g_SpoolVariables, g_SpoolRegions, g_WordVariables

    parts := StrSplit(params, ",")
    if parts.Length < 5 {
        ShowStatus("GrabOCRToVar format: varName,x,y,width,height", "fail")
        ShowNotificationBasic("Invalid Format", "Grab OCR to Var requires:`nvarName,x,y,width,height`n`nExample:`npatientID,100,100,400,200", 0, "error")
        return false
    }

    varName := Trim(parts[1])

    ; Parse coordinates as x,y,width,height
    x := Integer(parts[2])
    y := Integer(parts[3])
    w := Integer(parts[4])
    h := Integer(parts[5])

    ; Flash the region being captured
    FlashOCRRegion(x, y, w, h)

    ; Perform OCR
    try {
        result := OCR.FromRect(x, y, w, h)
        text := Trim(result.Text)

        ; Store in variables with both formats
        g_ExtractedData["$" . varName] := text
        g_ExtractedData["$var." . varName] := text
        g_ExtractedData[varName] := text
        g_SpoolVariables["$" . varName] := text
        g_SpoolVariables["$var." . varName] := text
        g_SpoolVariables[varName] := text
        g_WordVariables["$var." . varName] := text

        ShowStatus("OCR captured to $" . varName . ": " . text, "ok")

        ; Show notification with captured text and copy button
        ShowNotificationBasic("OCR Captured", "Variable: $" . varName . "`n`nText Captured:`n" . text, 0, "success", text)

        return true
    } catch as err {
        LogErrorToFile(err, "caught", "Grab OCR to Var")
        ShowStatus("OCR capture failed: " . err.Message, "fail")
        ShowNotificationBasic("OCR Failed", "Could not capture text`n`nRegion: " . x . "," . y . "," . w . "," . h . "`n`nError: " . err.Message, 0, "error")
        return false
    }
}

; Capture the primary screen, save recognized text, and outline every word.
; The notification is intentionally a separate workflow step so it proves that
; $var.name substitution is working rather than displaying a local value.
ExecuteFullScreenOCRToVar(varName) {
    global g_ExtractedData, g_SpoolVariables, g_WordVariables
    global g_LastOCRResult, g_LastOCRText, g_LastOCRRegion, g_OCRSettings

    varName := Trim(varName)
    if !RegExMatch(varName, "^[A-Za-z_][A-Za-z0-9_]*$") {
        ShowActionNotification("Full Screen OCR", "error", "Invalid variable name",
            "Use a plain name such as fullScreenOCR (letters, numbers, and underscores only).")
        return false
    }

    try {
        ShowStatus("Full-screen OCR in progress...", "wait")
        result := OCR.FromRect(0, 0, A_ScreenWidth, A_ScreenHeight,
                               g_OCRSettings["language"], g_OCRSettings["scale"])
        text := Trim(result.Text)
        if text = ""
            throw Error("Windows OCR completed but did not find readable text on the screen.")

        g_LastOCRResult := result
        g_LastOCRText := text
        g_LastOCRRegion := Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)

        ; Store every supported key form. $var.name is the preferred workflow form.
        g_ExtractedData[varName] := text
        g_ExtractedData["$" . varName] := text
        g_ExtractedData["$var." . varName] := text
        g_SpoolVariables[varName] := text
        g_SpoolVariables["$" . varName] := text
        g_SpoolVariables["$var." . varName] := text
        g_WordVariables["$var." . varName] := text

        HighlightOCRWordsYellow(result.Words, 0, 0, 10000)
        ShowStatus("OCR stored " . StrLen(text) . " characters in $var." . varName
            . " (" . result.Words.Length . " yellow boxes)", "ok")
        try RefreshOCRVarsLV()
        return true
    } catch as err {
        LogErrorToFile(err, "caught", "OCR Full Screen to Var")
        ShowActionNotification("Full Screen OCR", "error", "OCR capture failed",
            err.Message . "`n`nThe full details were written to the error log.")
        return false
    }
}

FlashOCRRegion(x, y, w, h, duration := 300) {
    ; Create a highlighted overlay to show OCR capture region
    flashGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    flashGui.BackColor := "Yellow"
    WinSetTransparent(100, flashGui.Hwnd)

    ; Show flash
    flashGui.Show("x" . x . " y" . y . " w" . w . " h" . h . " NoActivate")

    ; Remove after duration
    SetTimer(() => flashGui.Destroy(), -duration)
}

FlashClickPosition(x, y, duration := 200) {
    ; Create a crosshair flash at click position
    size := 30
    thickness := 4

    ; Horizontal line
    flashH := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    flashH.BackColor := "Red"
    WinSetTransparent(150, flashH.Hwnd)
    flashH.Show("x" . (x - size) . " y" . (y - thickness//2) . " w" . (size*2) . " h" . thickness . " NoActivate")

    ; Vertical line
    flashV := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    flashV.BackColor := "Red"
    WinSetTransparent(150, flashV.Hwnd)
    flashV.Show("x" . (x - thickness//2) . " y" . (y - size) . " w" . thickness . " h" . (size*2) . " NoActivate")

    ; Remove after duration
    SetTimer(() => (flashH.Destroy(), flashV.Destroy()), -duration)
}

; USE VARIABLE IN PASTE - Paste text that includes variables
; Format: "UseVarPaste,Hello $name, your ID is $id"
ExecuteUseVarPaste(params) {
    global g_ExtractedData, g_Settings

    if params = "" {
        ShowStatus("UseVarPaste requires text with variables", "fail")
        return false
    }

    ; Replace all variables in the text
    text := params

    ; Find all $variable references
    for varName, value in g_ExtractedData {
        if InStr(text, varName) {
            text := StrReplace(text, varName, value)
        }
    }

    ; Type the text
    Sleep(g_Settings["PreActionDelay"])
    SendText(text)
    Sleep(g_Settings["PostActionDelay"])

    ShowStatus("Pasted with variables: " . text, "ok")
    return true
}

; SHOW NOTIFICATION - Display notification (dismissable, snoozeable)
; Format: "ShowNotification,Title,Message[,Timeout]"
ExecuteShowNotification(params) {
    global g_ExtractedData

    parts := StrSplit(params, ",")
    if parts.Length < 2 {
        ShowStatus("ShowNotification format: Title,Message[,Timeout]", "fail")
        return false
    }

    title := parts[1]

    ; The last value is the timeout when numeric. Everything between the title
    ; and timeout is the message, so OCR text containing commas is not cut off.
    messageEnd := parts.Length
    timeout := 0
    if parts.Length >= 3 && IsNumber(Trim(parts[parts.Length])) {
        timeout := Integer(Trim(parts[parts.Length])) * 1000
        messageEnd--
    }
    message := ""
    Loop messageEnd - 1 {
        if A_Index > 1
            message .= ","
        message .= parts[A_Index + 1]
    }

    ; Substitute variables in message
    for varName, value in g_ExtractedData {
        if InStr(message, varName) {
            message := StrReplace(message, varName, value)
        }
    }

    ShowEnhancedNotification(title, message, timeout)
    return true
}

; ═══════════════════════════════════════════════════════════════════════════════
; SECTION 4: ENHANCED NOTIFICATION SYSTEM
; ═══════════════════════════════════════════════════════════════════════════════
; FEATURES:
;   • Right-click = Snooze (30min, 15min, 10min, 5min sequence)
;   • Double-click = Mark as "Done" and dismiss
;   • Clicks don't bleed through (proper GUI event handling)
;   • Visual feedback for snooze/done actions
; ═══════════════════════════════════════════════════════════════════════════════

ShowEnhancedNotification(title, message, timeout := 0) {
    ; Use the unified notification system
    ShowNotificationBasic(title, message, timeout, "info")
}

; Snooze notification (right-click)
SnoozeNotification(notifID) {
    global g_NotificationData

    if !g_NotificationData.Has(notifID)
        return

    data := g_NotificationData[notifID]

    ; Get next snooze duration
    if data["snoozeIndex"] >= data["snoozeSequence"].Length {
        snoozeMin := 5  ; Default to 5 min after sequence exhausted
    } else {
        snoozeMin := data["snoozeSequence"][data["snoozeIndex"] + 1]
        data["snoozeIndex"]++
    }

    ; Show snooze feedback
    ShowStatus("Notification snoozed for " . snoozeMin . " minutes", "ok")

    ; Hide notification
    try data["gui"].Hide()

    ; Set timer to re-show
    SetTimer(() => ReshowNotification(notifID), -snoozeMin * 60 * 1000)
}

; Re-show snoozed notification
ReshowNotification(notifID) {
    global g_NotificationData

    if !g_NotificationData.Has(notifID)
        return

    data := g_NotificationData[notifID]

    ; Re-show the notification
    try {
        data["gui"].Show("NoActivate")
        ShowStatus("Notification reminder: " . data["title"], "info")
    }
}

; Mark notification as done (double-click)
MarkNotificationDone(notifID) {
    global g_NotificationData, g_SpoolNotifications

    if !g_NotificationData.Has(notifID)
        return

    data := g_NotificationData[notifID]

    ; Visual feedback
    try {
        data["gui"].BackColor := "228B22"  ; Green
        Sleep(200)
    }

    ; Dismiss
    DismissNotification(notifID, data["gui"])

    ShowStatus("Notification marked as done", "ok")
}

; Dismiss notification permanently
DismissNotification(notifID, notifGui) {
    global g_NotificationData, g_SpoolNotifications

    ; Destroy GUI
    try notifGui.Destroy()

    ; Remove from tracking
    g_NotificationData.Delete(notifID)

    ; Remove from active list
    for i, notif in g_SpoolNotifications {
        if notif["id"] = notifID {
            g_SpoolNotifications.RemoveAt(i)
            break
        }
    }

    ; Reposition remaining notifications
    RepositionSpoolNotifications()
}

; Reposition all notifications after one is removed
RepositionSpoolNotifications() {
    global g_SpoolNotifications

    screenW := A_ScreenWidth
    screenH := A_ScreenHeight
    notifW := 400
    notifH := 120

    for i, notif in g_SpoolNotifications {
        stackOffset := (i - 1) * (notifH + 10)
        notifX := screenW - notifW - 20
        notifY := screenH - notifH - 50 - stackOffset

        try notif["gui"].Move(notifX, notifY)
    }
}

; Handle single click (do nothing, just prevent bleed-through)
NotificationSingleClick(notifID, *) {
    ; Just consume the click event to prevent bleed-through
    return
}

; ═══════════════════════════════════════════════════════════════════════════════
; SECTION 5: SMART CLIPBOARD REVOLVER WITH BINS
; ═══════════════════════════════════════════════════════════════════════════════
; FEATURES:
;   • Multiple bins for different formatting rules
;   • OCR-based routing (VSP vs EyeMed, etc.)
;   • Visual bin selection GUI when loading
;   • Format rules per bin (swap names, add date, etc.)
;   • Notification blocks during paste for verification
;   • Top bin processes first
; ═══════════════════════════════════════════════════════════════════════════════

; Initialize bins (call this during startup)
InitializeRevolverBins() {
    global g_RevolverBins, g_RevolverBinOrder

    ; Load saved bins from file
    LoadRevolverBins()

    ; If no bins, create defaults
    if g_RevolverBins.Count = 0 {
        ; Create default bins for insurance example
        CreateRevolverBin("VSP", ["lastName", "firstName", "DOB", "memberID"], [
            "swapNames",  ; Last, First -> First Last
            "addDate"     ; Include today's date
        ])

        CreateRevolverBin("EyeMed", ["firstName", "lastName", "memberID", "DOB"], [
            "upperCase",  ; ALL CAPS
            "removeSpaces"  ; Remove spaces
        ])
    }
}

; Create a new revolver bin
CreateRevolverBin(binName, fieldOrder, formatRules) {
    global g_RevolverBins, g_RevolverBinOrder

    g_RevolverBins[binName] := Map(
        "items", [],
        "fieldOrder", fieldOrder,
        "formatRules", formatRules,
        "notifyBlock", true,
        "position", 0
    )

    ; Add to order if not already there
    if !HasValue(g_RevolverBinOrder, binName) {
        g_RevolverBinOrder.Push(binName)
    }

    ShowStatus("Bin created: " . binName, "ok")
}

; Load revolver item with bin selection
LoadRevolverItem(itemString) {
    global g_RevolverBins, g_RevolverBinSelector

    ; Parse item string (e.g., "Smith,John,01/15/1985,12345")
    ; This is the raw data before formatting

    ; Show bin selection GUI
    ShowBinSelector(itemString)
}

; Show GUI to select which bin to load item into
ShowBinSelector(itemString) {
    global g_RevolverBins, g_RevolverBinSelector

    ; Close existing selector if open
    if g_RevolverBinSelector && WinExist("ahk_id " . g_RevolverBinSelector.Hwnd) {
        try g_RevolverBinSelector.Destroy()
    }

    ; Create selector GUI
    g_RevolverBinSelector := Gui("+AlwaysOnTop", "Select Bin for Item")
    g_RevolverBinSelector.SetFont("s10", "Segoe UI")

    ; Show preview of item
    g_RevolverBinSelector.Add("Text", "x20 y15", "Item to load:")
    g_RevolverBinSelector.Add("Edit", "x20 y+5 w460 ReadOnly", itemString)

    ; Instructions
    g_RevolverBinSelector.Add("Text", "x20 y+15", "Select bin to load this item into:")

    ; Create button for each bin
    yPos := 120
    for binName in g_RevolverBins {
        bin := g_RevolverBins[binName]
        btnText := binName . " (" . bin["items"].Length . " items)"

        btn := g_RevolverBinSelector.Add("Button", "x20 y" . yPos . " w460 h40", btnText)
        btn.OnEvent("Click", LoadItemIntoBin.Bind(binName, itemString))

        yPos += 50
    }

    ; Cancel button
    g_RevolverBinSelector.Add("Button", "x20 y" . yPos . " w460", "Cancel").OnEvent("Click", (*) => g_RevolverBinSelector.Hide())

    ; Show GUI
    g_RevolverBinSelector.Show("w500 h" . (yPos + 60))
}

; Load item into selected bin
LoadItemIntoBin(binName, itemString, *) {
    global g_RevolverBins, g_RevolverBinSelector

    if !g_RevolverBins.Has(binName)
        return

    bin := g_RevolverBins[binName]

    ; Parse item string based on bin's field order
    parts := StrSplit(itemString, ",")
    itemData := Map()

    for i, fieldName in bin["fieldOrder"] {
        if i <= parts.Length {
            itemData[fieldName] := Trim(parts[i])
        }
    }

    ; Apply format rules
    formattedData := ApplyFormatRules(itemData, bin["formatRules"])

    ; Add to bin
    bin["items"].Push(formattedData)

    ; Close selector
    try g_RevolverBinSelector.Hide()

    ShowStatus("Item loaded into " . binName . " (" . bin["items"].Length . " total)", "ok")

    ; Update bin notification if visible
    UpdateBinNotification(binName)
}

; Apply formatting rules to item data
ApplyFormatRules(itemData, formatRules) {
    formattedData := itemData.Clone()

    for rule in formatRules {
        switch rule {
            case "swapNames":
                ; Swap lastName and firstName
                if formattedData.Has("lastName") && formattedData.Has("firstName") {
                    temp := formattedData["lastName"]
                    formattedData["lastName"] := formattedData["firstName"]
                    formattedData["firstName"] := temp
                }

            case "addDate":
                ; Add today's date
                formattedData["date"] := FormatTime(A_Now, "MM/dd/yyyy")

            case "upperCase":
                ; Convert all to uppercase
                for field, value in formattedData {
                    formattedData[field] := StrUpper(value)
                }

            case "removeSpaces":
                ; Remove all spaces
                for field, value in formattedData {
                    formattedData[field] := StrReplace(value, " ", "")
                }

            case "formatPhone":
                ; Format phone as (XXX) XXX-XXXX
                if formattedData.Has("phone") {
                    phone := formattedData["phone"]
                    phone := RegExReplace(phone, "[^0-9]", "")  ; Remove non-digits
                    if StrLen(phone) = 10 {
                        formattedData["phone"] := "(" . SubStr(phone, 1, 3) . ") " . SubStr(phone, 4, 3) . "-" . SubStr(phone, 7, 4)
                    }
                }
        }
    }

    return formattedData
}

; Paste from bins (processes top bin first)
PasteFromBins() {
    global g_RevolverBinOrder, g_RevolverBins, g_Settings

    ; Find first non-empty bin
    for binName in g_RevolverBinOrder {
        if !g_RevolverBins.Has(binName)
            continue

        bin := g_RevolverBins[binName]
        if bin["items"].Length = 0
            continue

        ; Get next item from this bin
        item := bin["items"][1]
        bin["items"].RemoveAt(1)

        ; Show notification block if enabled
        if bin["notifyBlock"] {
            ShowBinNotification(binName, item)
        }

        ; Format for pasting (concatenate fields in order)
        pasteText := ""
        for fieldName in bin["fieldOrder"] {
            if item.Has(fieldName) {
                if pasteText != ""
                    pasteText .= " "  ; Space separator
                pasteText .= item[fieldName]
            }
        }

        ; Paste
        Sleep(g_Settings["PreActionDelay"])
        SendText(pasteText)
        Sleep(g_Settings["PostActionDelay"])

        ShowStatus("Pasted from " . binName . ": " . pasteText, "ok")

        ; Update bin notification
        UpdateBinNotification(binName)

        return true
    }

    ShowStatus("All bins empty!", "fail")
    return false
}

; Show bin notification block during paste
ShowBinNotification(binName, item) {
    global g_RevolverBinNotifications

    ; Create notification
    notif := Gui("+AlwaysOnTop +ToolWindow", "Revolver: " . binName)
    notif.SetFont("s9", "Segoe UI")
    notif.BackColor := "2C3E50"

    ; Bin name
    notif.Add("Text", "x10 y10 w280 cWhite", "BIN: " . binName).SetFont("s10 bold")

    ; Item details
    yPos := 40
    for field, value in item {
        notif.Add("Text", "x10 y" . yPos . " w280 cWhite", field . ": " . value)
        yPos += 20
    }

    ; Show at top-right
    notif.Show("x" . (A_ScreenWidth - 320) . " y20 w300 h" . (yPos + 20) . " NoActivate")

    ; Store reference
    g_RevolverBinNotifications[binName] := notif

    ; Auto-hide after 2 seconds
    SetTimer(() => HideBinNotification(binName), -2000)
}

; Update bin notification
UpdateBinNotification(binName) {
    global g_RevolverBinNotifications, g_RevolverBins

    if !g_RevolverBinNotifications.Has(binName)
        return

    bin := g_RevolverBins[binName]
    notif := g_RevolverBinNotifications[binName]

    try {
        notif.Title := binName . " (" . bin["items"].Length . " remaining)"
    }
}

; Hide bin notification
HideBinNotification(binName) {
    global g_RevolverBinNotifications

    if !g_RevolverBinNotifications.Has(binName)
        return

    try g_RevolverBinNotifications[binName].Hide()
}

; Save bins to file
SaveRevolverBins() {
    global g_RevolverBins, g_RevolverBinOrder, DATA_DIR

    filepath := DATA_DIR . "\revolver_bins.ini"

    try FileDelete(filepath)

    ; Save bin order
    FileAppend("[BinOrder]`n", filepath)
    FileAppend("order=" . ArrayJoin(g_RevolverBinOrder, "|") . "`n`n", filepath)

    ; Save each bin
    for binName, bin in g_RevolverBins {
        FileAppend("[" . binName . "]`n", filepath)
        FileAppend("fieldOrder=" . ArrayJoin(bin["fieldOrder"], "|") . "`n", filepath)
        FileAppend("formatRules=" . ArrayJoin(bin["formatRules"], "|") . "`n", filepath)
        FileAppend("notifyBlock=" . bin["notifyBlock"] . "`n", filepath)
        FileAppend("`n", filepath)
    }
}

; Load bins from file
LoadRevolverBins() {
    global g_RevolverBins, g_RevolverBinOrder, DATA_DIR

    filepath := DATA_DIR . "\revolver_bins.ini"

    if !FileExist(filepath)
        return

    ; Parse INI file
    currentSection := ""
    currentBin := ""

    try {
        content := FileRead(filepath)

        for line in StrSplit(content, "`n") {
            line := Trim(line)
            if line = ""
                continue

            if SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]" {
                currentSection := SubStr(line, 2, -1)
                if currentSection != "BinOrder" {
                    currentBin := currentSection
                    g_RevolverBins[currentBin] := Map(
                        "items", [],
                        "fieldOrder", [],
                        "formatRules", [],
                        "notifyBlock", true,
                        "position", 0
                    )
                }
            } else if InStr(line, "=") {
                parts := StrSplit(line, "=", , 2)
                key := parts[1]
                value := parts.Length > 1 ? parts[2] : ""

                if currentSection = "BinOrder" {
                    if key = "order" {
                        g_RevolverBinOrder := StrSplit(value, "|")
                    }
                } else if currentBin != "" {
                    switch key {
                        case "fieldOrder":
                            g_RevolverBins[currentBin]["fieldOrder"] := StrSplit(value, "|")
                        case "formatRules":
                            g_RevolverBins[currentBin]["formatRules"] := StrSplit(value, "|")
                        case "notifyBlock":
                            g_RevolverBins[currentBin]["notifyBlock"] := value = "1" || value = "true"
                    }
                }
            }
        }
    }
}

; Helper: Join array with delimiter
; ArrayJoin(arr, delimiter) {
;     result := ""
;     for item in arr {
;         if result != ""
;             result .= delimiter
;         result .= item
;     }
;     return result
; }

; Helper: Check if value in array
HasValue(arr, value) {
    for item in arr {
        if item = value
            return true
    }
    return false
}



CreateNotepadTab() {
    global MainGui, g_NotepadContent

    ; Create Notepad tab
    notepadTab := MainGui.Add("Tab3", "Choose1", ["Notepad"])

    ; Title and instructions
    MainGui.Add("Text", "x20 y+15", "Quick Notepad for Testing & Automation")
    MainGui.Add("Text", "x20 y+5 c888888", "Use this to test text entry, write notes, or prepare automation content")

    ; Main notepad edit control
    notepadEdit := MainGui.Add("Edit", "x20 y+10 w760 h400 vNotepadEdit Multi WantTab", g_NotepadContent)

    ; Buttons row
    MainGui.Add("Button", "x20 y+10 w120", "Save Note").OnEvent("Click", SaveNotepadContent)
    MainGui.Add("Button", "x+10 w120", "Load Note").OnEvent("Click", LoadNotepadContent)
    MainGui.Add("Button", "x+10 w120", "Clear").OnEvent("Click", ClearNotepadContent)
    MainGui.Add("Button", "x+10 w120", "Open Popup").OnEvent("Click", OpenNotepadPopup)
    MainGui.Add("Button", "x+10 w150", "Copy to Clipboard").OnEvent("Click", (*) => CopyNotepadToClipboard())

    ; Quick action buttons
    MainGui.Add("Text", "x20 y+20", "Quick Actions:")
    MainGui.Add("Button", "x20 y+5 w120", "Auto-Type This").OnEvent("Click", AutoTypeNotepad)
    MainGui.Add("Button", "x+10 w150", "Send to Active Window").OnEvent("Click", SendNotepadToWindow)
    MainGui.Add("Button", "x+10 w120", "New Sequence").OnEvent("Click", NewSequenceFromNotepad)

    ; Note list
    MainGui.Add("Text", "x20 y+20", "Saved Notes:")
    noteListLV := MainGui.Add("ListView", "x20 y+5 w760 h100", ["Filename", "Modified", "Size"])
    noteListLV.Name := "NoteListLV"
    noteListLV.OnEvent("DoubleClick", LoadSelectedNote)
    RefreshNoteList()

    return notepadTab
}

; Open popup notepad window (can be targeted with WinActivate)
OpenNotepadPopup(*) {
    global g_NotepadPopupGui, g_NotepadContent

    ; Close existing popup if open
    if g_NotepadPopupGui && WinExist("ahk_id " . g_NotepadPopupGui.Hwnd) {
        try g_NotepadPopupGui.Destroy()
    }

    ; Create popup window
    g_NotepadPopupGui := Gui("+Resize", "MacroAutomator Notepad - Target with WinActivate")
    g_NotepadPopupGui.SetFont("s10", "Consolas")

    ; Instructions
    g_NotepadPopupGui.Add("Text", "x10 y10", "This window can be targeted: WinActivate('MacroAutomator Notepad')")

    ; Large text area
    noteEdit := g_NotepadPopupGui.Add("Edit", "x10 y+10 w780 h500 Multi WantTab", g_NotepadContent)
    noteEdit.Name := "PopupNoteEdit"

    ; Buttons
    g_NotepadPopupGui.Add("Button", "x10 y+10 w100", "Save").OnEvent("Click", SavePopupNotepad)
    g_NotepadPopupGui.Add("Button", "x+10 w100", "Copy All").OnEvent("Click", (*) => CopyPopupToClipboard())
    g_NotepadPopupGui.Add("Button", "x+10 w120", "Clear").OnEvent("Click", ClearPopupNotepad)
    g_NotepadPopupGui.Add("Button", "x+10 w150", "Close").OnEvent("Click", (*) => g_NotepadPopupGui.Hide())

    ; Status bar
    g_NotepadPopupGui.Add("Text", "x10 y+10 w760 cGray", "Autosaves every 30 seconds • Ctrl+S to save manually")

    ; Set up auto-save timer
    SetTimer(AutoSavePopupNotepad, 30000)

    ; Show window
    g_NotepadPopupGui.Show("w800 h600")

    ShowStatus("Notepad popup opened - Window title: 'MacroAutomator Notepad'", "ok")
}

; Save notepad content to file
SaveNotepadContent(*) {
    global g_NotepadContent, NOTES_DIR, MainGui

    ; Get current content
    try {
        g_NotepadContent := MainGui["NotepadEdit"].Value
    }

    ; Generate filename with timestamp
    timestamp := FormatTime(A_Now, "yyyyMMdd_HHmmss")
    filename := "note_" . timestamp . ".txt"
    filepath := NOTES_DIR . "\" . filename

    ; Prompt for custom filename
    result := InputBoxTop("Save note as:", "Save Note", filename)
    if result["Result"] = "OK" && result["Value"] != "" {
        filename := result["Value"]
        if !InStr(filename, ".txt")
            filename .= ".txt"
        filepath := NOTES_DIR . "\" . filename
    } else if result["Result"] = "Cancel" {
        return
    }

    ; Save file
    try {
        FileDelete(filepath)  ; Delete if exists
        FileAppend(g_NotepadContent, filepath, "UTF-8")
        ShowStatus("Note saved: " . filename, "ok")
        RefreshNoteList()
    } catch as err {
        MsgBoxTop("Error saving note: " . err.Message, "Save Error")
    }
}

; Load note from file
LoadNotepadContent(*) {
    global g_NotepadContent, NOTES_DIR, MainGui

    ; Get list of notes
    notes := []
    loop files NOTES_DIR . "\*.txt" {
        notes.Push(A_LoopFileName)
    }

    if notes.Length = 0 {
        MsgBoxTop("No saved notes found.", "Load Note")
        return
    }

    ; Let user choose
    result := InputBoxTop("Enter note filename to load:", "Load Note", notes[1])
    if result["Result"] = "OK" && result["Value"] != "" {
        filepath := NOTES_DIR . "\" . result["Value"]
        if FileExist(filepath) {
            try {
                g_NotepadContent := FileRead(filepath, "UTF-8")
                MainGui["NotepadEdit"].Value := g_NotepadContent
                ShowStatus("Note loaded: " . result["Value"], "ok")
            } catch as err {
                MsgBoxTop("Error loading note: " . err.Message, "Load Error")
            }
        } else {
            MsgBoxTop("File not found: " . result["Value"], "Load Error")
        }
    }
}

; Load selected note from list
LoadSelectedNote(*) {
    global NOTES_DIR, MainGui, g_NotepadContent

    ; Get selected row
    row := MainGui["NoteListLV"].GetNext()
    if !row
        return

    ; Get filename
    filename := MainGui["NoteListLV"].GetText(row, 1)
    filepath := NOTES_DIR . "\" . filename

    ; Load content
    try {
        g_NotepadContent := FileRead(filepath, "UTF-8")
        MainGui["NotepadEdit"].Value := g_NotepadContent
        ShowStatus("Loaded: " . filename, "ok")
    } catch as err {
        MsgBoxTop("Error loading note: " . err.Message, "Load Error")
    }
}

; Clear notepad content
ClearNotepadContent(*) {
    global g_NotepadContent, MainGui

    result := MsgBoxTop("Clear notepad content?", "Confirm", "YesNo")
    if result = "Yes" {
        g_NotepadContent := ""
        MainGui["NotepadEdit"].Value := ""
        ShowStatus("Notepad cleared", "ok")
    }
}

; Copy notepad to clipboard
CopyNotepadToClipboard() {
    global MainGui

    try {
        content := MainGui["NotepadEdit"].Value
        A_Clipboard := content
        ShowStatus("Copied to clipboard: " . StrLen(content) . " characters", "ok")
    } catch as err {
        ShowStatus("Error copying to clipboard", "fail")
    }
}

; Auto-type notepad content
AutoTypeNotepad(*) {
    global MainGui, g_Settings

    content := MainGui["NotepadEdit"].Value
    if content = "" {
        MsgBoxTop("Notepad is empty!", "Auto-Type")
        return
    }

    ; Minimize our GUI
    MainGui.Hide()
    Sleep(500)

    ; Type content
    SendText(content)
    Sleep(500)

    ; Show GUI again
    MainGui.Show()
    ShowStatus("Auto-typed " . StrLen(content) . " characters", "ok")
}

; Send notepad to active window
SendNotepadToWindow(*) {
    global MainGui

    content := MainGui["NotepadEdit"].Value
    if content = "" {
        MsgBoxTop("Notepad is empty!", "Send to Window")
        return
    }

    MsgBoxTop("Click OK, then click in the target window.`nContent will be typed in 2 seconds.", "Send to Window")

    Sleep(2000)
    SendText(content)
    ShowStatus("Content sent to window", "ok")
}

; Create new sequence from notepad content
NewSequenceFromNotepad(*) {
    global MainGui, g_CurrentSequenceSteps

    content := MainGui["NotepadEdit"].Value
    if content = "" {
        MsgBoxTop("Notepad is empty!", "New Sequence")
        return
    }

    ; Clear current sequence
    g_CurrentSequenceSteps := []

    ; Add type action
    g_CurrentSequenceSteps.Push(Map(
        "action", "Type Text",
        "target", "",
        "param", content,
        "enabled", true
    ))

    ; Switch to Workflow tab and refresh
    try {
        MainGui["Tabs"].Choose(1)  ; Workflow tab
        ;RefreshSeqStepsLV()
        RefreshStepsLV()
        ScheduleWorkflowAutosave()

        ShowStatus("Sequence created from notepad content", "ok")
    }
}

; Refresh note list
RefreshNoteList() {
    global NOTES_DIR, MainGui

    try {
        lv := MainGui["NoteListLV"]
        lv.Delete()

        loop files NOTES_DIR . "\*.txt" {
            modTime := FormatTime(A_LoopFileTimeModified, "yyyy-MM-dd HH:mm:ss")
            size := Round(A_LoopFileSize / 1024, 1) . " KB"
            lv.Add("", A_LoopFileName, modTime, size)
        }

        ; Auto-size columns
        lv.ModifyCol()
        lv.ModifyCol(1, "AutoHdr")
        lv.ModifyCol(2, "AutoHdr")
        lv.ModifyCol(3, "AutoHdr")
    }
}

; Popup notepad save
SavePopupNotepad(*) {
    global g_NotepadPopupGui, g_NotepadContent, NOTES_DIR

    try {
        g_NotepadContent := g_NotepadPopupGui["PopupNoteEdit"].Value

        ; Generate filename
        timestamp := FormatTime(A_Now, "yyyyMMdd_HHmmss")
        filename := "popup_note_" . timestamp . ".txt"
        filepath := NOTES_DIR . "\" . filename

        ; Save
        FileDelete(filepath)
        FileAppend(g_NotepadContent, filepath, "UTF-8")
        ShowStatus("Popup note saved: " . filename, "ok")
    }
}

; Copy popup to clipboard
CopyPopupToClipboard() {
    global g_NotepadPopupGui

    try {
        content := g_NotepadPopupGui["PopupNoteEdit"].Value
        A_Clipboard := content
        ShowStatus("Copied: " . StrLen(content) . " characters", "ok")
    }
}

; Clear popup notepad
ClearPopupNotepad(*) {
    global g_NotepadPopupGui

    result := MsgBoxTop("Clear popup notepad?", "Confirm", "YesNo")
    if result = "Yes" {
        try g_NotepadPopupGui["PopupNoteEdit"].Value := ""
    }
}

; Auto-save popup notepad
AutoSavePopupNotepad() {
    global g_NotepadPopupGui, g_NotepadContent, NOTES_DIR

    ; Check if window still exists
    if !g_NotepadPopupGui || !WinExist("ahk_id " . g_NotepadPopupGui.Hwnd) {
        SetTimer(AutoSavePopupNotepad, 0)  ; Stop timer
        return
    }

    try {
        g_NotepadContent := g_NotepadPopupGui["PopupNoteEdit"].Value

        ; Auto-save to temp file
        filepath := NOTES_DIR . "\autosave_popup.txt"
        FileDelete(filepath)
        FileAppend(g_NotepadContent, filepath, "UTF-8")
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; END OF NEW FEATURES v4.1
; ═══════════════════════════════════════════════════════════════════════════════


GuiResize(thisGui, minMax, w, h) {
    if minMax = -1
        return
    try TabCtrl.Move(, , w - 10, h - 75)
    try {
        listW := Max(650, w - 250)
        listH := 103
        SeqLV.Move(, , listW, listH)
        WorkflowSaveStatus.Move(, , Max(400, w - 60))
        SavedLibraryGroup.Move(, , Max(860, w - 40))
        SavedWorkflowsLabel.Move(, , Max(640, w - 250))

        leftBtnX := w - 215
        rightBtnX := w - 125
        SeqLoadBtn.Move(leftBtnX)
        SeqDeleteBtn.Move(rightBtnX)
        SeqRunBtn.Move(leftBtnX)
        SeqSimBtn.Move(rightBtnX)
        SeqImportBtn.Move(leftBtnX)
        SeqExportBtn.Move(rightBtnX)
        SeqMawWriterBtn.Move(leftBtnX, , 175)
    }
}

ToggleOnTop(ctrl, *) {
    global g_AlwaysOnTop, MainGui
    g_AlwaysOnTop := ctrl.Value
    WinSetAlwaysOnTop(g_AlwaysOnTop, MainGui)
}

UpdateMousePos() {
    global MousePosText
    MouseGetPos(&x, &y)
    MousePosText.Value := x . ", " . y
    UpdateDefinitionMode()
}


; ═══════════════════════════════════════════════════════════════════════════════
; STEP SELECTION HANDLER
; ═══════════════════════════════════════════════════════════════════════════════
; STEP SELECTION HANDLER
; =============================================================================

OnStepSelect(LV, RowNumber, *) {
    global g_CurrentSequenceSteps, g_Settings

    if RowNumber = 0
        return

    if RowNumber > g_CurrentSequenceSteps.Length
        return

    step := g_CurrentSequenceSteps[RowNumber]
    ShowStepPreview(step)
}

OnStepCheck(LV, RowNumber, IsChecked) {
    global g_CurrentSequenceSteps

    if RowNumber = 0 || RowNumber > g_CurrentSequenceSteps.Length
        return

    ; Sync the enabled state with the checkbox
    g_CurrentSequenceSteps[RowNumber]["enabled"] := IsChecked
    ScheduleWorkflowAutosave()
}


; ═══════════════════════════════════════════════════════════════════════════════
; STEPS CONTEXT MENU (RIGHT-CLICK)
; ═══════════════════════════════════════════════════════════════════════════════
; STEPS CONTEXT MENU (Right-click)
; =============================================================================

OnStepsContextMenu(LV, RowNumber, IsRightClick, X, Y) {
    if RowNumber = 0
        return

    ; Create context menu
    stepMenu := Menu()
    stepMenu.Add("▶ Test This Step", (*) => TestSingleStepByRow(RowNumber))
    stepMenu.Add("🔍 Simulate This Step", (*) => SimulateSingleStepByRow(RowNumber))
    stepMenu.Add()
    stepMenu.Add("✓ Toggle This Step", (*) => ToggleStepByRow(RowNumber))
    stepMenu.Add("✓ Toggle All OFF Except This", (*) => ToggleAllOffExcept(RowNumber))
    stepMenu.Add("✓ Enable All Steps", (*) => EnableAllSteps())
    stepMenu.Add()
    stepMenu.Add("🛡 Edit Failsafe...", (*) => EditStepFailsafeByRow(RowNumber))
    stepMenu.Add("✏ Edit Step...", (*) => EditStepByRow(RowNumber))
    stepMenu.Add("🗑 Delete Step", (*) => DeleteStepByRow(RowNumber))
    stepMenu.Add()
    stepMenu.Add("⬆ Move Up", (*) => MoveStepUp(RowNumber))
    stepMenu.Add("⬇ Move Down", (*) => MoveStepDown(RowNumber))
    stepMenu.Add()
    stepMenu.Add("📋 Duplicate Step", (*) => DuplicateStep(RowNumber))

    stepMenu.Show(X, Y)
}

; Context menu for saved sequences
OnSeqContextMenu(LV, RowNumber, IsRightClick, X, Y) {
    global g_Sequences, SeqLV

    if RowNumber = 0
        return

    name := SeqLV.GetText(RowNumber, 1)
    if !g_Sequences.Has(name)
        return

    seqMenu := Menu()
    seqMenu.Add("▶ Run: " . name, (*) => RunSeqByName(name))
    seqMenu.Add("🔍 Simulate", (*) => SimulateSavedSeqByName(name))
    seqMenu.Add()
    seqMenu.Add("📂 Load into Editor", (*) => LoadSeqByName(name))
    seqMenu.Add("📋 Duplicate", (*) => DuplicateSequence(name))
    seqMenu.Add("✏ Rename...", (*) => RenameSequence(name))
    seqMenu.Add()
    seqMenu.Add("🗑 Delete", (*) => DeleteSeqByName(name))

    seqMenu.Show(X, Y)
}

; Context menu for saved patterns
OnPatternContextMenu(LV, RowNumber, IsRightClick, X, Y) {
    global g_Patterns, PatternLV

    if RowNumber = 0
        return

    name := PatternLV.GetText(RowNumber, 1)
    if !g_Patterns.Has(name)
        return

    patternMenu := Menu()
    patternMenu.Add("🔍 Test: " . name, (*) => TestPatternByName(name))
    patternMenu.Add("👁 Full View", (*) => ShowFullPatternPreview(name))
    patternMenu.Add()
    patternMenu.Add("✏ Edit Pattern", (*) => EditPatternByName(name))
    patternMenu.Add("📋 Duplicate", (*) => DuplicatePattern(name))
    patternMenu.Add("✏ Rename...", (*) => RenamePattern(name))
    patternMenu.Add()
    patternMenu.Add("📷 Recapture Screenshot", (*) => RecapturePatternScreenshot(name))
    patternMenu.Add("📍 Update Location", (*) => UpdatePatternLocation(name))
    patternMenu.Add()
    patternMenu.Add("🗑 Delete", (*) => DeletePatternByName(name))

    patternMenu.Show(X, Y)
}

; Pattern context menu handlers
EditPatternByName(name) {
    global g_Patterns, PatternNameEdit, PatternDescEdit, PatternCodeEdit, PatternQualifierDD

    if !g_Patterns.Has(name)
        return

    patternData := g_Patterns[name]
    PatternNameEdit.Value := name
    PatternDescEdit.Value := patternData.Has("desc") ? patternData["desc"] : ""
    PatternCodeEdit.Value := patternData["text"]

    ; Set qualifier dropdown
    if patternData.Has("qualifier") && patternData["qualifier"] != "" {
        try {
            items := ControlGetItems(PatternQualifierDD)
            for i, item in items {
                if item = patternData["qualifier"] {
                    PatternQualifierDD.Choose(i)
                    break
                }
            }
        }
    } else {
        PatternQualifierDD.Choose(1)
    }

    UpdatePatternPreview()
    ShowStatus("Editing: " . name, "ok")
}

DuplicatePattern(name) {
    global g_Patterns

    if !g_Patterns.Has(name)
        return

    newName := name . "_copy"
    counter := 1
    while g_Patterns.Has(newName) {
        newName := name . "_copy" . counter
        counter++
    }

    ; Deep copy
    g_Patterns[newName] := Map()
    for key, val in g_Patterns[name]
        g_Patterns[newName][key] := val

    SavePatterns()
    RefreshPatternLV()
    UpdateTargetDD()
    UpdatePatternQualifierDD()
    ShowStatus("Duplicated as: " . newName, "ok")
}

RenamePattern(oldName) {
    global g_Patterns

    newName := InputBox("Enter new name:", "Rename Pattern", "", oldName)
    if newName.Result != "OK" || newName.Value = ""
        return

    newName := newName.Value
    if newName = oldName
        return

    if g_Patterns.Has(newName) {
        MsgBoxTop("Name already exists!", "Error")
        return
    }

    g_Patterns[newName] := g_Patterns[oldName]
    g_Patterns.Delete(oldName)
    SavePatterns()
    RefreshPatternLV()
    UpdateTargetDD()
    UpdatePatternQualifierDD()
    ShowStatus("Renamed to: " . newName, "ok")
}

RecapturePatternScreenshot(name) {
    global g_Patterns, g_Settings

    if !g_Patterns.Has(name)
        return

    patternData := g_Patterns[name]
    code := patternData["text"]

    ; Find pattern on screen
    tolerance := g_Settings["FindTextTolerance"]
    ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)

    if !ok || ok.Length = 0 {
        ShowStatus("Pattern not found on screen", "fail")
        return
    }

    ; Get center position
    x := ok[1].mx
    y := ok[1].my

    ; Capture screenshot
    screenshotPath := CapturePatternScreenshot(x, y, name)
    if screenshotPath != "" {
        patternData["screenshot"] := screenshotPath
        patternData["captureX"] := x
        patternData["captureY"] := y
        SavePatterns()
        RefreshPatternLV()
        ShowStatus("Screenshot updated: " . name, "ok")
    }
}

UpdatePatternLocation(name) {
    global g_Patterns, g_Settings

    if !g_Patterns.Has(name)
        return

    patternData := g_Patterns[name]
    code := patternData["text"]

    ; Find pattern on screen
    tolerance := g_Settings["FindTextTolerance"]
    ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)

    if !ok || ok.Length = 0 {
        ShowStatus("Pattern not found on screen", "fail")
        return
    }

    ; Update location
    x := ok[1].mx
    y := ok[1].my
    patternData["captureX"] := x
    patternData["captureY"] := y

    ; Get window title
    hwnd := DllCall("WindowFromPoint", "Int64", (y << 32) | (x & 0xFFFFFFFF), "Ptr")
    if hwnd
        patternData["captureWindow"] := WinGetTitle(hwnd)

    SavePatterns()
    RefreshPatternLV()
    ShowStatus("Location updated: " . x . "," . y, "ok")
}

DeletePatternByName(name) {
    global g_Patterns

    if !g_Patterns.Has(name)
        return

    result := MsgBoxTop("Delete pattern '" . name . "'?", "Confirm", "YesNo")
    if result != "Yes"
        return

    g_Patterns.Delete(name)
    SavePatterns()
    RefreshPatternLV()
    UpdateTargetDD()
    UpdatePatternQualifierDD()
    ShowStatus("Deleted: " . name, "ok")
}

; Context menu action handlers
TestSingleStepByRow(row) {
    global g_CurrentSequenceSteps, g_AbortSequence

    if row > g_CurrentSequenceSteps.Length
        return

    step := g_CurrentSequenceSteps[row]
    g_AbortSequence := false
    speed := GetSpeedMultiplier()

    ShowStatus("Testing step " . row . ": " . step["action"], "wait")
    success := ExecuteActionVerified(step["action"], step["target"], step["param"], step, speed)
    ShowStatus(success ? "Step " . row . " completed" : "Step " . row . " failed", success ? "ok" : "fail")
}

SimulateSingleStepByRow(row) {
    global g_CurrentSequenceSteps, g_Settings

    if row > g_CurrentSequenceSteps.Length
        return

    step := g_CurrentSequenceSteps[row]
    coords := GetStepCoordinates(step)

    tipText := "[Step " . row . "] " . step["action"]
    if step["target"] != "" && step["target"] != "(none)"
        tipText .= "`n→ " . step["target"]
    if step["param"] != ""
        tipText .= "`n  (" . step["param"] . ")"

    ShowTooltipTimed(tipText, 3000, coords["x"], coords["y"])
    ShowStatus("Simulated step " . row, "ok")
}

ToggleStepByRow(row) {
    global g_CurrentSequenceSteps, StepsLV

    if row > g_CurrentSequenceSteps.Length
        return

    g_CurrentSequenceSteps[row]["enabled"] := !g_CurrentSequenceSteps[row]["enabled"]
    RefreshStepsLV()
    ScheduleWorkflowAutosave()
}

ToggleAllOffExcept(exceptRow) {
    global g_CurrentSequenceSteps, StepsLV

    for i, step in g_CurrentSequenceSteps {
        step["enabled"] := (i = exceptRow)
    }
    RefreshStepsLV()
    ShowStatus("All OFF except step " . exceptRow, "ok")
    ScheduleWorkflowAutosave()
}

EnableAllSteps() {
    global g_CurrentSequenceSteps

    for step in g_CurrentSequenceSteps
        step["enabled"] := true
    RefreshStepsLV()
    ShowStatus("All steps enabled", "ok")
    ScheduleWorkflowAutosave()
}

EditStepByRow(row) {
    global StepsLV
    StepsLV.Modify(row, "Select Focus")
    EditStep()
}

DeleteStepByRow(row) {
    global g_CurrentSequenceSteps

    if row > g_CurrentSequenceSteps.Length
        return

    g_CurrentSequenceSteps.RemoveAt(row)
    RefreshStepsLV()
    ShowStatus("Deleted step " . row, "ok")
    ScheduleWorkflowAutosave()
}

MoveStepUp(row) {
    global g_CurrentSequenceSteps

    if row <= 1 || row > g_CurrentSequenceSteps.Length
        return

    temp := g_CurrentSequenceSteps[row]
    g_CurrentSequenceSteps[row] := g_CurrentSequenceSteps[row - 1]
    g_CurrentSequenceSteps[row - 1] := temp
    RefreshStepsLV()
    ScheduleWorkflowAutosave()
}

MoveStepDown(row) {
    global g_CurrentSequenceSteps

    if row < 1 || row >= g_CurrentSequenceSteps.Length
        return

    temp := g_CurrentSequenceSteps[row]
    g_CurrentSequenceSteps[row] := g_CurrentSequenceSteps[row + 1]
    g_CurrentSequenceSteps[row + 1] := temp
    RefreshStepsLV()
    ScheduleWorkflowAutosave()
}

DuplicateStep(row) {
    global g_CurrentSequenceSteps

    if row > g_CurrentSequenceSteps.Length
        return

    ; Deep copy the step
    original := g_CurrentSequenceSteps[row]
    copy := Map()
    for key, val in original
        copy[key] := val

    ; Insert after current position
    g_CurrentSequenceSteps.InsertAt(row + 1, copy)
    RefreshStepsLV()
    ShowStatus("Duplicated step " . row, "ok")
    ScheduleWorkflowAutosave()
}

; Sequence context menu handlers
SimulateSavedSeqByName(name) {
    global g_Sequences, g_AbortSequence

    if !g_Sequences.Has(name)
        return

    g_AbortSequence := false
    speed := g_Sequences[name].Has("speed") ? g_Sequences[name]["speed"] : 1.0
    SimulateSequence(g_Sequences[name]["steps"], speed)
}

LoadSeqByName(name) {
    if LoadWorkflowByName(name)
        ShowStatus("Loaded: " . name, "ok")
}

DuplicateSequence(name) {
    global g_Sequences

    if !g_Sequences.Has(name)
        return

    newName := name . "_copy"
    counter := 1
    while g_Sequences.Has(newName) {
        newName := name . "_copy" . counter
        counter++
    }

    ; Deep copy
    g_Sequences[newName] := Map("steps", [], "speed", g_Sequences[name].Has("speed") ? g_Sequences[name]["speed"] : 1.0)
    for step in g_Sequences[name]["steps"] {
        copy := Map()
        for key, val in step
            copy[key] := val
        g_Sequences[newName]["steps"].Push(copy)
    }

    if SaveSequences(true) {
        RefreshSeqLV()
        ShowStatus("Duplicated as: " . newName, "ok")
    } else {
        g_Sequences.Delete(newName)
    }
}

RenameSequence(oldName) {
    global g_Sequences

    newName := InputBox("Enter new name:", "Rename Sequence", "", oldName)
    if newName.Result != "OK" || newName.Value = ""
        return

    newName := newName.Value
    if newName = oldName
        return

    if g_Sequences.Has(newName) {
        MsgBoxTop("Name already exists!", "Error")
        return
    }

    renamedSequence := g_Sequences[oldName]
    UnregisterSequenceTriggers(oldName)
    g_Sequences[newName] := renamedSequence
    g_Sequences.Delete(oldName)
    if SaveSequences(true) {
        RegisterSequenceTriggers(newName)
        RefreshSeqLV()
        ShowStatus("Renamed to: " . newName, "ok")
    } else {
        g_Sequences.Delete(newName)
        g_Sequences[oldName] := renamedSequence
        RegisterSequenceTriggers(oldName)
    }
}

DeleteSeqByName(name) {
    global g_Sequences

    if !g_Sequences.Has(name)
        return

    result := MsgBoxTop("Delete sequence '" . name . "'?", "Confirm", "YesNo")
    if result != "Yes"
        return

    deletedSequence := g_Sequences[name]
    UnregisterSequenceTriggers(name)
    g_Sequences.Delete(name)
    if SaveSequences(true) {
        RefreshSeqLV()
        ShowStatus("Deleted: " . name, "ok")
    } else {
        g_Sequences[name] := deletedSequence
        RegisterSequenceTriggers(name)
    }
}


; ═══════════════════════════════════════════════════════════════════════════════
; PER-STEP FAILSAFE SYSTEM
; ═══════════════════════════════════════════════════════════════════════════════
; PER-STEP FAILSAFE SYSTEM

; ═══════════════════════════════════════════════════════════════════════════════
; EACH STEP CAN HAVE ACTION-SPECIFIC FAILSAFE CONDITIONS:
; ═══════════════════════════════════════════════════════════════════════════════
; Each step can have action-specific failsafe conditions:
; - Click actions: Check for close button pattern, require window match
; - Keyboard actions: Require specific window to be active
; - Pattern actions: Already have qualifier system
; - All actions: Optional pre-delay, max retries

EditStepFailsafe(*) {
    global StepsLV
    row := StepsLV.GetNext(0, "Focused")
    if row = 0 {
        ShowStatus("Select a step first", "fail")
        return
    }
    EditStepFailsafeByRow(row)
}

EditStepFailsafeByRow(row) {
    global g_CurrentSequenceSteps, g_Patterns

    if row > g_CurrentSequenceSteps.Length
        return

    step := g_CurrentSequenceSteps[row]
    action := step["action"]

    ; Build failsafe dialog based on action type
    fsGui := Gui("+AlwaysOnTop", "Step " . row . " Failsafe: " . action)
    fsGui.SetFont("s9", "Segoe UI")

    ; Get current failsafe settings
    fs := step.Has("failsafe") ? NormalizeStepFailsafe(step["failsafe"]) : Map()
    if step.Has("failsafe")
        step["failsafe"] := fs

    ; Common failsafes for all actions
    fsGui.Add("GroupBox", "w450 h80 Section", "Common Failsafes")
    fsGui.Add("Text", "xs+10 ys+20", "Required Window Title:")
    fsWindowEdit := fsGui.Add("Edit", "x+5 w250 vFsWindow", fs.Has("window") ? fs["window"] : "")
    fsGui.Add("Button", "x+5 w60 h22", "Get").OnEvent("Click", (*) => (fsWindowEdit.Value := WinGetTitle("A")))

    fsGui.Add("CheckBox", "xs+10 y+10 vFsAbortOnFail", "Abort sequence if this step fails").Value := fs.Has("abortOnFail") ? fs["abortOnFail"] : 0

    ; Action-specific failsafes
    if InStr(action, "Click") || action = "Drag" {
        ; Click-specific failsafes
        fsGui.Add("GroupBox", "xs y+20 w450 h100", "Click/Position Failsafes")

        fsGui.Add("CheckBox", "xp+10 yp+20 vFsCheckCloseBtn", "Block clicks near window close button").Value := fs.Has("checkCloseBtn") ? fs["checkCloseBtn"] : 1

        fsGui.Add("CheckBox", "y+8 vFsRequirePattern", "Require pattern visible before clicking:").Value := fs.Has("requirePattern") ? fs["requirePattern"] : 0

        ; Pattern dropdown
        patternChoices := ["(none)"]
        for name, _ in g_Patterns
            patternChoices.Push(name)
        fsPatternDD := fsGui.Add("DropDownList", "x+5 w200 vFsPattern", patternChoices)
        if fs.Has("pattern") && fs["pattern"] != "" {
            for i, p in patternChoices {
                if p = fs["pattern"] {
                    fsPatternDD.Choose(i)
                    break
                }
            }
        } else {
            fsPatternDD.Choose(1)
        }

        fsGui.Add("CheckBox", "xs+10 y+10 vFsVerifyPosition", "Verify mouse position after move").Value := fs.Has("verifyPosition") ? fs["verifyPosition"] : 1

    } else if InStr(action, "Key") || action = "Send Keys" || action = "Type Text" {
        ; Keyboard-specific failsafes
        fsGui.Add("GroupBox", "xs y+20 w450 h80", "Keyboard Failsafes")

        fsGui.Add("CheckBox", "xp+10 yp+20 vFsWaitForIdle", "Wait for window to be idle before sending").Value := fs.Has("waitForIdle") ? fs["waitForIdle"] : 0

        fsGui.Add("Text", "y+10", "Delay before sending (ms):")
        fsGui.Add("Edit", "x+5 w60 vFsPreDelay Number", fs.Has("preDelay") ? fs["preDelay"] : "0")

    } else if InStr(action, "Activate") || InStr(action, "Taskbar") {
        ; Window activation failsafes
        fsGui.Add("GroupBox", "xs y+20 w450 h80", "Activation Failsafes")

        fsGui.Add("Text", "xp+10 yp+20", "Max wait time (ms):")
        fsGui.Add("Edit", "x+5 w60 vFsMaxWait Number", fs.Has("maxWait") ? fs["maxWait"] : "3000")

        fsGui.Add("CheckBox", "xs+10 y+10 vFsRetryIfHidden", "Retry if window doesn't appear").Value := fs.Has("retryIfHidden") ? fs["retryIfHidden"] : 1

    } else if InStr(action, "Wait") {
        ; Wait action failsafes
        fsGui.Add("GroupBox", "xs y+20 w450 h60", "Wait Failsafes")

        fsGui.Add("CheckBox", "xp+10 yp+20 vFsContinueOnTimeout", "Continue sequence even if wait times out").Value := fs.Has("continueOnTimeout") ? fs["continueOnTimeout"] : 0
    }

    ; Retry settings
    fsGui.Add("GroupBox", "xs y+20 w450 h60", "Retry Settings")
    fsGui.Add("Text", "xp+10 yp+20", "Max retries:")
    fsGui.Add("Edit", "x+5 w50 vFsMaxRetries Number", fs.Has("maxRetries") ? fs["maxRetries"] : "3")
    fsGui.Add("Text", "x+20", "Retry delay (ms):")
    fsGui.Add("Edit", "x+5 w60 vFsRetryDelay Number", fs.Has("retryDelay") ? fs["retryDelay"] : "200")

    ; Buttons
    fsGui.Add("Button", "xs y+20 w100 h28", "Save").OnEvent("Click", (*) => SaveStepFailsafe(fsGui, row))
    fsGui.Add("Button", "x+10 w100 h28", "Clear All").OnEvent("Click", (*) => (ClearStepFailsafe(row), fsGui.Destroy()))
    fsGui.Add("Button", "x+10 w100 h28", "Cancel").OnEvent("Click", (*) => fsGui.Destroy())

    fsGui.Show()
}

SaveStepFailsafe(fsGui, row) {
    global g_CurrentSequenceSteps

    if row > g_CurrentSequenceSteps.Length
        return

    step := g_CurrentSequenceSteps[row]
    fs := Map()

    ; Get all values from GUI
    try {
        ; Common
        fs["window"] := fsGui["FsWindow"].Value
        fs["abortOnFail"] := fsGui["FsAbortOnFail"].Value

        ; Action-specific (check if controls exist)
        try fs["checkCloseBtn"] := fsGui["FsCheckCloseBtn"].Value
        try fs["requirePattern"] := fsGui["FsRequirePattern"].Value
        try fs["pattern"] := fsGui["FsPattern"].Text != "(none)" ? fsGui["FsPattern"].Text : ""
        try fs["verifyPosition"] := fsGui["FsVerifyPosition"].Value
        try fs["waitForIdle"] := fsGui["FsWaitForIdle"].Value
        try fs["preDelay"] := Integer(fsGui["FsPreDelay"].Value)
        try fs["maxWait"] := Integer(fsGui["FsMaxWait"].Value)
        try fs["retryIfHidden"] := fsGui["FsRetryIfHidden"].Value
        try fs["continueOnTimeout"] := fsGui["FsContinueOnTimeout"].Value

        ; Retry settings
        fs["maxRetries"] := Integer(fsGui["FsMaxRetries"].Value)
        fs["retryDelay"] := Integer(fsGui["FsRetryDelay"].Value)
    }

    step["failsafe"] := fs
    fsGui.Destroy()
    RefreshStepsLV()
    ShowStatus("Failsafe saved for step " . row, "ok")
    ScheduleWorkflowAutosave()
}

ClearStepFailsafe(row) {
    global g_CurrentSequenceSteps

    if row > g_CurrentSequenceSteps.Length
        return

    if g_CurrentSequenceSteps[row].Has("failsafe")
        g_CurrentSequenceSteps[row].Delete("failsafe")

    RefreshStepsLV()
    ShowStatus("Failsafe cleared for step " . row, "ok")
    ScheduleWorkflowAutosave()
}

; Get failsafe summary for ListView display
; GetFailsafeSummary(step) {
;     if !step.Has("failsafe")
;         return "-"

;     fs := step["failsafe"]
;     parts := []

;     if fs.Has("window") && fs["window"] != ""
;         parts.Push("Win")
;     if fs.Has("pattern") && fs["pattern"] != ""
;         parts.Push("Pat")
;     if fs.Has("checkCloseBtn") && fs["checkCloseBtn"]
;         parts.Push("NoX")
;     if fs.Has("abortOnFail") && fs["abortOnFail"]
;         parts.Push("Abort")

;     return parts.Length > 0 ? StrJoin(parts, ",") : "-"
; }
GetFailsafeSummary(step) {
    if !step.Has("failsafe")
        return "-"

    fs := step["failsafe"]

    ; Check if fs is a Map (not a string from old data)
    if !IsObject(fs) || !(fs is Map)
        return "-"

    parts := []

    if fs.Has("window") && fs["window"] != ""
        parts.Push("Win")
    if fs.Has("pattern") && fs["pattern"] != ""
        parts.Push("Pat")
    if fs.Has("checkCloseBtn") && fs["checkCloseBtn"]
        parts.Push("NoX")
    if fs.Has("abortOnFail") && fs["abortOnFail"]
        parts.Push("Abort")

    return parts.Length > 0 ? StrJoin(parts, ",") : "-"
}

; Helper to join array with separator
StrJoin(arr, sep) {
    result := ""
    for i, item in arr {
        if i > 1
            result .= sep
        result .= item
    }
    return result
}

SimulateSingleStep(*) {
    global StepsLV
    row := StepsLV.GetNext(0, "Focused")
    if row = 0 {
        ShowStatus("Select a step first", "fail")
        return
    }
    SimulateSingleStepByRow(row)
}


; ═══════════════════════════════════════════════════════════════════════════════
; TEST SINGLE STEP
; ═══════════════════════════════════════════════════════════════════════════════
; TEST SINGLE STEP
; =============================================================================

TestSingleStep(*) {
    global g_CurrentSequenceSteps, StepsLV, g_AbortSequence

    row := StepsLV.GetNext(0, "Focused")
    if row = 0 {
        ShowStatus("Select a step first", "fail")
        return
    }

    if row > g_CurrentSequenceSteps.Length
        return

    step := g_CurrentSequenceSteps[row]
    if !step["enabled"] {
        ShowStatus("Step is disabled", "fail")
        return
    }

    g_AbortSequence := false
    speed := GetSpeedMultiplier()
    ShowStatus("Testing step " . row . ": " . step["action"] . " @ " . speed . "x", "wait")

    success := ExecuteActionVerified(step["action"], step["target"], step["param"], step, speed)

    if success {
        ShowStatus("Step " . row . " completed", "ok")
    } else {
        ShowStatus("Step " . row . " failed", "fail")
    }
}


; ═══════════════════════════════════════════════════════════════════════════════
; PATTERN FUNCTIONS
; ═══════════════════════════════════════════════════════════════════════════════
; PATTERN FUNCTIONS
; =============================================================================

OpenFindTextGUI(*) {
    FindText().Gui("Show")
    StatusBar.SetText("FindText GUI opened - F1 to capture")
}

PastePatternCode(*) {
    global PatternCodeEdit
    PatternCodeEdit.Value := A_Clipboard
    UpdatePatternPreview()
    StatusBar.SetText("Pasted from clipboard")
}

ClearPatternCode(*) {
    global PatternCodeEdit, PatternPreviewEdit
    PatternCodeEdit.Value := ""
    PatternPreviewEdit.Value := "Paste pattern code to see preview..."
}

ExtractPatternFromCode(rawCode) {
    code := ""
    if RegExMatch(rawCode, 'Text\s*[:.]?=\s*"(\|[^"]+)"', &m)
        code := m[1]
    else if RegExMatch(rawCode, '"(\|<[^>]*>[^"]+\$[^"]+)"', &m)
        code := m[1]
    else if RegExMatch(rawCode, '(\|<[^>]*>[^\s|]+\$[^\s|"]+)', &m)
        code := m[1]
    else if RegExMatch(rawCode, '^\|<[^>]*>') && InStr(rawCode, "$")
        code := rawCode
    if code != "" && SubStr(code, 1, 1) != "|"
        code := "|" . code
    return code
}

UpdatePatternPreview(*) {
    global PatternCodeEdit, PatternPreviewEdit, MainGui
    saved := MainGui.Submit(false)
    rawCode := Trim(saved.PatternCode)

    if rawCode = "" {
        PatternPreviewEdit.Value := "Paste pattern code to see preview..."
        return
    }

    code := ExtractPatternFromCode(rawCode)
    if code = "" || !InStr(code, "$") {
        PatternPreviewEdit.Value := "No valid pattern found`nExpected: |<id>*NNN$WW.data"
        return
    }

    preview := "Pattern extracted successfully`n"
    preview .= "Code: " . SubStr(code, 1, 35) . "...`n"
    preview .= "================================`n"
    preview .= PatternToVisualPreview(code, 45, 18)
    preview .= "`n================================`n"
    preview .= "Click here for full-size view"

    PatternPreviewEdit.Value := preview
}
BookAppointmentWithTasks(date, time, patientID, appointmentType) {
    ; Get patient name
    patient := g_Patients[patientID]
    patientName := patient["name"]

    ; Get appointment type details
    typeInfo := g_AppointmentTypes[appointmentType]

    ; Create appointment
    key := date . "_" . StrReplace(time, ":", "")
    appointmentInfo := patientName . " - " . typeInfo["name"]
    g_Appointments[key] := Map(
        "patient", patientName,
        "type", appointmentType,
        "tasks", typeInfo["tasks"]
    )

    ; Generate notification for each task
    appointmentDateTime := date . StrReplace(time, ":", "") . "00"

    for task in typeInfo["tasks"] {
        notifyMinutes := task["notifyBefore"]

        ; Calculate trigger time
        triggerTime := DateAdd(appointmentDateTime, -notifyMinutes, "Minutes")

        ; Create notification
        message := patientName . " - " . task["task"]
        CreateScheduledNotification(triggerTime, "Appointment Task", message)
    }

    SaveAppointments()
    RefreshCalendar()
}

CreateScheduledNotification(triggerTime, title, message) {
    secondsUntil := DateDiff(triggerTime, A_Now, "Seconds")
    if secondsUntil <= 0 {
        ShowNotificationBasic(title, message, 0, "info")
        return true
    }

    ; AutoHotkey timer periods are practical up to about 24 days in milliseconds.
    if secondsUntil <= 2147483 {
        SetTimer((*) => ShowNotificationBasic(title, message, 0, "info"),
                 -(secondsUntil * 1000))
        return true
    }

    LogDiagnostic("Scheduled notification is more than 24 days away: " . triggerTime,
                  "Appointment notification", "INFO")
    return false
}

ConfirmBooking(time, patientDD, typeDD, bookGui, *) {
    return BookAppointment(time, patientDD, typeDD, bookGui)
}
ClickTimeSlot3(time) {
    BookGui := Gui("+OwnerMainGui", "Book Appointment at " . time)

    ; Patient selection
    BookGui.Add("Text", "x10 y10", "Patient:")
    patientNames := GetPatientNames()
    patientDD := BookGui.Add("DropDownList", "x70 y10 w200", patientNames)

    ; Appointment type selection
    BookGui.Add("Text", "x10 y40", "Type:")
    typeNames := []
    for key, typeInfo in g_AppointmentTypes {
        typeNames.Push(typeInfo["name"])
    }
    typeDD := BookGui.Add("DropDownList", "x70 y40 w200", typeNames)
    typeDD.OnEvent("Change", (*) => ShowTaskPreview(typeDD, taskPreviewEdit))

    ; Task preview
    BookGui.Add("Text", "x10 y70", "Tasks that will be scheduled:")
    taskPreviewEdit := BookGui.Add("Edit", "x10 y90 w350 h150 ReadOnly Multi")

    ; Buttons
    BookGui.Add("Button", "x70 y250 w100 h25", "Book").OnEvent("Click", (*) => ConfirmBooking(time, patientDD, typeDD, BookGui))
    BookGui.Add("Button", "x180 y250 w100 h25", "Cancel").OnEvent("Click", (*) => BookGui.Destroy())

    BookGui.Show("w370 h290")
}

ShowTaskPreview(typeDD, taskPreviewEdit) {
    ; Get selected appointment type
    selectedIndex := typeDD.Value
    typeName := typeDD.Text

    ; Find matching type
    for key, typeInfo in g_AppointmentTypes {
        if (typeInfo["name"] = typeName) {
            ; Build task preview text
            preview := ""
            for task in typeInfo["tasks"] {
                minutes := task["notifyBefore"]
                if (minutes > 0) {
                    preview .= "⏰ " . minutes . " min before: " . task["task"] . "`n"
                } else {
                    preview .= "⏰ At appointment: " . task["task"] . "`n"
                }
            }
            taskPreviewEdit.Value := preview
            break
        }
    }
}
InitializeTaskPresets() {
    ; New Patient Setup
    g_TaskPresets["NewPatientSetup"] := Map(
        "name", "New Patient Setup",
        "tasks", [
            Map("task", "Scan insurance card", "notifyBefore", 15),
            Map("task", "Enter into web app", "notifyBefore", 10),
            Map("task", "Verify name ALL CAPS", "notifyBefore", 5)
        ]
    )

    ; Payment Processing
    g_TaskPresets["Payment"] := Map(
        "name", "Payment Processing",
        "tasks", [
            Map("task", "Get credit card on file", "notifyBefore", 10),
            Map("task", "Sign authorization", "notifyBefore", 5),
            Map("task", "Calculate co-pay", "notifyBefore", 5)
        ]
    )

    ; Insurance Verification
    g_TaskPresets["Insurance"] := Map(
        "name", "Insurance Verification",
        "tasks", [
            Map("task", "Verify insurance active", "notifyBefore", 10),
            Map("task", "Check coverage", "notifyBefore", 10)
        ]
    )
}
PopoutPatternPreview(*) {
    global PatternCodeEdit, MainGui
    saved := MainGui.Submit(false)
    rawCode := Trim(saved.PatternCode)

    if rawCode = ""
        return

    code := ExtractPatternFromCode(rawCode)
    if code = ""
        return

    ; Create popout window
    previewGui := Gui("+AlwaysOnTop +ToolWindow", "Pattern Full Preview")
    previewGui.SetFont("s8", "Consolas")

    preview := PatternToVisualPreview(code, 100, 50)
    previewGui.Add("Edit", "w600 h400 ReadOnly Multi", preview)
    previewGui.Add("Button", "w100", "Close").OnEvent("Click", (*) => previewGui.Destroy())

    previewGui.Show()
}

PreviewSelectedPattern(*) {
    global PatternLV, g_Patterns, PatternPreviewEdit, PatternImageBox, PatternCaptureInfo
    row := PatternLV.GetNext(0, "Focused")
    if row = 0 {
        PatternPreviewEdit.Value := "Select a pattern to preview"
        try PatternImageBox.Value := ""
        try PatternCaptureInfo.Value := "No data"
        return
    }
    name := PatternLV.GetText(row, 1)
    if !g_Patterns.Has(name)
        return

    data := g_Patterns[name]
    code := data["text"]
    desc := data.Has("desc") ? data["desc"] : ""
    screenshotPath := data.Has("screenshot") ? data["screenshot"] : ""
    captureX := data.Has("captureX") ? data["captureX"] : 0
    captureY := data.Has("captureY") ? data["captureY"] : 0
    captureWindow := data.Has("captureWindow") ? data["captureWindow"] : ""
    qualifier := data.Has("qualifier") ? data["qualifier"] : ""

    ; ASCII preview
    preview := "Pattern: " . name . "`n"
    if desc != ""
        preview .= "Desc: " . desc . "`n"
    preview .= "========================`n"
    preview .= PatternToVisualPreview(code, 30, 12)
    preview .= "`n========================"

    PatternPreviewEdit.Value := preview

    ; Image preview
    if screenshotPath != "" && FileExist(screenshotPath) {
        try PatternImageBox.Value := screenshotPath
    } else {
        try PatternImageBox.Value := ""
    }

    ; Capture info
    info := "Location:`n" . captureX . ", " . captureY . "`n`n"
    info .= "Window:`n" . (captureWindow != "" ? SubStr(captureWindow, 1, 15) : "(none)") . "`n`n"
    info .= "Qualifier:`n" . (qualifier != "" ? qualifier : "(none)")

    try PatternCaptureInfo.Value := info
}

PopoutSelectedPattern(*) {
    global PatternLV, g_Patterns
    row := PatternLV.GetNext(0, "Focused")
    if row = 0
        return
    name := PatternLV.GetText(row, 1)
    if g_Patterns.Has(name)
        ShowFullPatternPreview(name)
}

SavePattern(*) {
    global g_Patterns, PatternNameEdit, PatternDescEdit, PatternCodeEdit, PatternLV, MainGui, ExtractStatus, g_Settings
    global PatternQualifierDD, PatternCaptureInfo
    saved := MainGui.Submit(false)
    name := Trim(saved.PatternName)
    rawCode := Trim(saved.PatternCode)
    desc := Trim(saved.PatternDesc)
    qualifier := saved.PatternQualifier
    if qualifier = "(none)"
        qualifier := ""

    if name = "" {
        MsgBoxTop("Enter pattern name!", "Required")
        return
    }
    if rawCode = "" {
        MsgBoxTop("Paste FindText code!", "Empty")
        return
    }
    code := ExtractPatternFromCode(rawCode)
    if code = "" || !InStr(code, "$") {
        MsgBoxTop("Invalid pattern!`n`nExpected: |<>*137$71.zzz...", "Invalid")
        return
    }

    ; Try to find pattern on screen and capture screenshot + location
    screenshotPath := ""
    captureX := 0
    captureY := 0
    captureWindow := ""

    result := MsgBoxTop(
        "Pattern code valid!`n`n" .
        "Capture screenshot & location? (Pattern must be visible)`n`n" .
        "Yes = Find pattern, capture coords & window`n" .
        "No = Save without location data",
        "Capture Location?",
        "YesNoCancel"
    )

    if result = "Cancel"
        return

    if result = "Yes" {
        ; Search for pattern on screen
        StatusBar.SetText("Finding pattern on screen...")
        tolerance := g_Settings["FindTextTolerance"]
        ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)

        if ok && ok.Length > 0 {
            ; Found! Get coordinates and window
            captureX := ok[1].mx
            captureY := ok[1].my
            FindText().MouseTip(captureX, captureY)

            ; Get window under that point
            hwnd := DllCall("WindowFromPoint", "Int64", (captureY << 32) | (captureX & 0xFFFFFFFF), "Ptr")
            if hwnd {
                captureWindow := WinGetTitle("ahk_id " . hwnd)
            }

            screenshotPath := CapturePatternScreenshot(name, captureX, captureY)
        } else {
            MsgBoxTop("Pattern not found on screen.`nSaving without location data.", "Not Found")
        }
    }

    try ExtractStatus.Value := "Saved: " . SubStr(code, 1, 25) . "..."
    g_Patterns[name] := Map(
        "text", code,
        "desc", desc,
        "screenshot", screenshotPath,
        "captureX", captureX,
        "captureY", captureY,
        "captureWindow", captureWindow,
        "qualifier", qualifier
    )
    RefreshPatternLV()
    SavePatterns()
    UpdateTargetDD()
    UpdateQualPatternDD()
    UpdatePatternQualifierDD()
    PatternNameEdit.Value := ""
    PatternCodeEdit.Value := ""
    PatternDescEdit.Value := ""
    PatternQualifierDD.Choose(1)
    StatusBar.SetText("Saved pattern: " . name . (screenshotPath != "" ? " @ " . captureX . "," . captureY : ""))
}

; Save pattern without screenshot prompt (for auto-capture)
SavePatternSilent(name, code, desc := "", screenshotPath := "") {
    global g_Patterns
    g_Patterns[name] := Map("text", code, "desc", desc, "screenshot", screenshotPath)
    SavePatterns()
    UpdateTargetDD()
    UpdateQualPatternDD()
}

TestPattern(*) {
    global PatternCodeEdit, g_Settings, MainGui
    saved := MainGui.Submit(false)
    rawCode := Trim(saved.PatternCode)
    if rawCode = "" {
        MsgBoxTop("Paste code first!", "Empty")
        return
    }
    code := ExtractPatternFromCode(rawCode)
    if code = "" {
        MsgBoxTop("Invalid pattern!", "Invalid")
        return
    }
    StatusBar.SetText("Searching...")
    tolerance := g_Settings["FindTextTolerance"]
    ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)
    if ok && ok.Length > 0 {
        FindText().MouseTip(ok[1].mx, ok[1].my)
        StatusBar.SetText("FOUND at " . ok[1].mx . "," . ok[1].my)
    } else {
        MsgBoxTop("Pattern NOT FOUND!`n`nTry: Adjust tolerance or recapture.", "Not Found")
        StatusBar.SetText("Not found")
    }
}

TestSelectedPattern(*) {
    global PatternLV, g_Patterns, g_Settings
    row := PatternLV.GetNext(0, "Focused")
    if row = 0
        return
    name := PatternLV.GetText(row, 1)
    TestPatternByName(name)
}

DeletePattern(*) {
    global PatternLV, g_Patterns
    row := PatternLV.GetNext(0, "Focused")
    if row = 0
        return
    name := PatternLV.GetText(row, 1)
    if MsgBoxTop("Delete '" . name . "'?", "Confirm", "YesNo") = "Yes" {
        g_Patterns.Delete(name)
        RefreshPatternLV()
        SavePatterns()
        UpdateTargetDD()
        UpdateQualPatternDD()
        StatusBar.SetText("Deleted: " . name)
    }
}

EditPattern(*) {
    global PatternLV, g_Patterns, PatternNameEdit, PatternCodeEdit, PatternDescEdit
    global PatternImageBox, PatternQualifierDD, PatternCaptureInfo
    row := PatternLV.GetNext(0, "Focused")
    if row = 0
        return
    name := PatternLV.GetText(row, 1)
    if !g_Patterns.Has(name)
        return

    data := g_Patterns[name]

    PatternNameEdit.Value := name
    PatternCodeEdit.Value := data["text"]
    PatternDescEdit.Value := data.Has("desc") ? data["desc"] : ""

    ; Load image preview if exists
    screenshotPath := data.Has("screenshot") ? data["screenshot"] : ""
    if screenshotPath != "" && FileExist(screenshotPath) {
        try PatternImageBox.Value := screenshotPath
    } else {
        try PatternImageBox.Value := ""
    }

    ; Load capture info
    captureX := data.Has("captureX") ? data["captureX"] : 0
    captureY := data.Has("captureY") ? data["captureY"] : 0
    captureWindow := data.Has("captureWindow") ? data["captureWindow"] : ""
    qualifier := data.Has("qualifier") ? data["qualifier"] : ""

    info := "Location:`n" . captureX . ", " . captureY . "`n`n"
    info .= "Window:`n" . (captureWindow != "" ? SubStr(captureWindow, 1, 15) : "(none)") . "`n`n"
    info .= "Qualifier:`n" . (qualifier != "" ? qualifier : "(none)")
    try PatternCaptureInfo.Value := info

    ; Set qualifier dropdown
    UpdatePatternQualifierDD()
    if qualifier != "" {
        ; Find and select the qualifier
        Loop PatternQualifierDD.Length {
            if PatternQualifierDD.List[A_Index] = qualifier {
                PatternQualifierDD.Choose(A_Index)
                break
            }
        }
    } else {
        PatternQualifierDD.Choose(1)  ; (none)
    }

    UpdatePatternPreview()
    StatusBar.SetText("Editing: " . name)
}

RefreshPatternLV() {
    global g_Patterns, PatternLV
    PatternLV.Delete()
    for name, data in g_Patterns {
        qualifier := data.Has("qualifier") && data["qualifier"] != "" ? data["qualifier"] : "-"
        captureX := data.Has("captureX") ? data["captureX"] : 0
        captureY := data.Has("captureY") ? data["captureY"] : 0
        location := (captureX > 0 || captureY > 0) ? captureX . "," . captureY : "-"
        window := data.Has("captureWindow") && data["captureWindow"] != "" ? SubStr(data["captureWindow"], 1, 25) : "-"
        code := SubStr(data["text"], 1, 40) . "..."
        PatternLV.Add(, name, qualifier, location, window, code)
    }
}

; Update the pattern qualifier dropdown with available patterns
UpdatePatternQualifierDD() {
    global g_Patterns, PatternQualifierDD
    choices := ["(none)"]
    for name, _ in g_Patterns
        choices.Push(name)
    PatternQualifierDD.Delete()
    PatternQualifierDD.Add(choices)
    PatternQualifierDD.Choose(1)
}

; Capture screenshot by finding pattern on screen first (like Test Pattern)
CaptureScreenshotNow(*) {
    global PatternNameEdit, PatternCodeEdit, PatternImageBox, g_Settings, MainGui

    saved := MainGui.Submit(false)
    name := Trim(saved.PatternName)
    rawCode := Trim(saved.PatternCode)

    if name = "" {
        MsgBoxTop("Enter pattern name first!", "Name Required")
        return
    }

    if rawCode = "" {
        MsgBoxTop("Paste FindText code first!", "Code Required")
        return
    }

    ; Extract and validate pattern code
    code := ExtractPatternFromCode(rawCode)
    if code = "" {
        MsgBoxTop("Invalid pattern code!", "Invalid")
        return
    }

    ; Search for pattern on screen (like TestPattern does)
    StatusBar.SetText("Finding pattern on screen...")
    tolerance := g_Settings["FindTextTolerance"]
    ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)

    if !ok || ok.Length = 0 {
        MsgBoxTop("Pattern not found on screen!`n`nMake sure the pattern is visible.", "Not Found")
        StatusBar.SetText("Pattern not found")
        return
    }

    ; Found! Get center coordinates
    foundX := ok[1].mx
    foundY := ok[1].my

    ; Flash the location briefly
    FindText().MouseTip(foundX, foundY)

    ; Capture screenshot at found location
    path := CapturePatternScreenshot(name, foundX, foundY)

    if path != "" && FileExist(path) {
        try PatternImageBox.Value := path
        StatusBar.SetText("Screenshot captured at " . foundX . "," . foundY)
    }
}

; View the image for selected pattern
ViewPatternImage(*) {
    global PatternLV, g_Patterns

    row := PatternLV.GetNext(0, "Focused")
    if row = 0 {
        ; Try current name field
        saved := MainGui.Submit(false)
        name := Trim(saved.PatternName)
        if name = "" || !g_Patterns.Has(name) {
            MsgBoxTop("Select a pattern first!", "No Selection")
            return
        }
    } else {
        name := PatternLV.GetText(row, 1)
    }

    if !g_Patterns.Has(name)
        return

    screenshotPath := g_Patterns[name].Has("screenshot") ? g_Patterns[name]["screenshot"] : ""

    if screenshotPath = "" || !FileExist(screenshotPath) {
        MsgBoxTop("No screenshot for this pattern.`n`nUse '📷 Find' or 'Add Screenshot' to capture one.`n(Pattern must be visible on screen)", "No Image")
        return
    }

    ; Open image in default viewer
    Run(screenshotPath)
}

; Recapture screenshot by finding pattern on screen
RecaptureScreenshot(*) {
    global PatternNameEdit, PatternCodeEdit, PatternImageBox, g_Patterns, g_Settings, MainGui

    saved := MainGui.Submit(false)
    name := Trim(saved.PatternName)
    rawCode := Trim(saved.PatternCode)

    if name = "" {
        MsgBoxTop("Enter pattern name first!", "Name Required")
        return
    }

    if rawCode = "" {
        MsgBoxTop("Paste FindText code first!", "Code Required")
        return
    }

    ; Extract and validate pattern code
    code := ExtractPatternFromCode(rawCode)
    if code = "" {
        MsgBoxTop("Invalid pattern code!", "Invalid")
        return
    }

    ; Search for pattern on screen
    StatusBar.SetText("Finding pattern on screen...")
    tolerance := g_Settings["FindTextTolerance"]
    ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)

    if !ok || ok.Length = 0 {
        MsgBoxTop("Pattern not found on screen!`n`nMake sure the pattern is visible.", "Not Found")
        StatusBar.SetText("Pattern not found")
        return
    }

    ; Found! Get center coordinates
    foundX := ok[1].mx
    foundY := ok[1].my

    ; Flash the location
    FindText().MouseTip(foundX, foundY)

    ; Capture screenshot at found location
    path := CapturePatternScreenshot(name, foundX, foundY)

    if path != "" && FileExist(path) {
        try PatternImageBox.Value := path

        ; Update existing pattern if it exists
        if g_Patterns.Has(name) {
            g_Patterns[name]["screenshot"] := path
            SavePatterns()
            RefreshPatternLV()
        }

        StatusBar.SetText("Screenshot recaptured at " . foundX . "," . foundY)
    }
}

; Add screenshot to existing saved pattern by finding it on screen
AddScreenshotToPattern(*) {
    global PatternLV, g_Patterns, g_Settings

    row := PatternLV.GetNext(0, "Focused")
    if row = 0 {
        MsgBoxTop("Select a pattern first!", "No Selection")
        return
    }

    name := PatternLV.GetText(row, 1)

    if !g_Patterns.Has(name)
        return

    code := g_Patterns[name]["text"]

    ; Search for pattern on screen
    StatusBar.SetText("Finding pattern on screen...")
    tolerance := g_Settings["FindTextTolerance"]
    ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)

    if !ok || ok.Length = 0 {
        MsgBoxTop("Pattern '" . name . "' not found on screen!`n`nMake sure it's visible.", "Not Found")
        StatusBar.SetText("Pattern not found")
        return
    }

    ; Found! Get center coordinates
    foundX := ok[1].mx
    foundY := ok[1].my

    ; Flash the location
    FindText().MouseTip(foundX, foundY)

    ; Capture screenshot at found location
    path := CapturePatternScreenshot(name, foundX, foundY)

    if path != "" && FileExist(path) {
        g_Patterns[name]["screenshot"] := path
        ; Also update capture coordinates
        g_Patterns[name]["captureX"] := foundX
        g_Patterns[name]["captureY"] := foundY
        ; Get window title
        hwnd := DllCall("WindowFromPoint", "Int64", (foundY << 32) | (foundX & 0xFFFFFFFF), "Ptr")
        if hwnd
            g_Patterns[name]["captureWindow"] := WinGetTitle("ahk_id " . hwnd)
        SavePatterns()
        RefreshPatternLV()
        StatusBar.SetText("Screenshot added at " . foundX . "," . foundY)
    }
}


; ═══════════════════════════════════════════════════════════════════════════════
; QUICK CAPTURE - BUILT-IN PATTERN CAPTURE TOOL
; ═══════════════════════════════════════════════════════════════════════════════
; QUICK CAPTURE - Built-in Pattern Capture Tool

; ═══════════════════════════════════════════════════════════════════════════════
; SIMPLIFIED PATTERN CAPTURE WITHOUT NEEDING FINDTEXT GUI
; ═══════════════════════════════════════════════════════════════════════════════
; Simplified pattern capture without needing FindText GUI

QuickCapturePattern(*) {
    global MainGui, PatternNameEdit, PatternCodeEdit, PatternDescEdit, PatternCaptureInfo
    global g_QuickCaptureActive, g_QuickCaptureStart, g_QuickCaptureOverlay

    ; Hide main GUI temporarily
    MainGui.Hide()
    Sleep(200)

    ; Show instructions
    ToolTip("QUICK CAPTURE`n`nDrag to select region...`nESC to cancel", A_ScreenWidth // 2 - 100, 50)

    ; Wait for mouse down
    g_QuickCaptureActive := true

    ; Install keyboard hook for ESC
    Hotkey("Escape", CancelQuickCapture, "On")

    ; Wait for left button down
    KeyWait("LButton", "D")

    if !g_QuickCaptureActive {
        ToolTip()
        MainGui.Show()
        return
    }

    ; Get start position
    MouseGetPos(&startX, &startY)

    ; Create selection overlay
    g_QuickCaptureOverlay := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    g_QuickCaptureOverlay.BackColor := "Red"
    WinSetTransparent(80, g_QuickCaptureOverlay)

    ; Track selection while dragging
    while GetKeyState("LButton", "P") && g_QuickCaptureActive {
        MouseGetPos(&currentX, &currentY)

        ; Calculate rectangle
        x := Min(startX, currentX)
        y := Min(startY, currentY)
        w := Abs(currentX - startX)
        h := Abs(currentY - startY)

        if w > 5 && h > 5 {
            g_QuickCaptureOverlay.Show("x" . x . " y" . y . " w" . w . " h" . h . " NoActivate")
        }

        ToolTip("Selecting: " . w . " x " . h, currentX + 15, currentY + 15)
        Sleep(16)
    }

    ; Get end position
    MouseGetPos(&endX, &endY)

    ; Clean up overlay
    try g_QuickCaptureOverlay.Destroy()
    ToolTip()

    ; Remove ESC hotkey
    try Hotkey("Escape", "Off")

    if !g_QuickCaptureActive {
        MainGui.Show()
        return
    }

    g_QuickCaptureActive := false

    ; Calculate final rectangle
    x1 := Min(startX, endX)
    y1 := Min(startY, endY)
    x2 := Max(startX, endX)
    y2 := Max(startY, endY)
    w := x2 - x1
    h := y2 - y1

    if w < 5 || h < 5 {
        MsgBoxTop("Selection too small!`n`nDrag a larger region.", "Too Small")
        MainGui.Show()
        return
    }

    ; Get window under center of selection
    centerX := x1 + w // 2
    centerY := y1 + h // 2
    hwnd := DllCall("WindowFromPoint", "Int64", (centerY << 32) | (centerX & 0xFFFFFFFF), "Ptr")
    windowTitle := ""
    if hwnd
        windowTitle := WinGetTitle("ahk_id " . hwnd)

    ; Use FindText to capture the region as a pattern
    StatusBar.SetText("Generating pattern...")

    ; Try Gray2Two first (good for text)
    patternText := FindText().GetTextFromScreen(x1, y1, x2, y2, "**50")

    if patternText = "" || StrLen(patternText) < 10 {
        MsgBoxTop("Could not generate pattern from selection.`n`nTry selecting a more distinct region.", "Capture Failed")
        MainGui.Show()
        return
    }

    ; Generate a name
    patternNum := 1
    while g_Patterns.Has("Capture_" . patternNum)
        patternNum++
    suggestedName := "Capture_" . patternNum

    ; Build the pattern code
    patternCode := "|<" . suggestedName . ">" . patternText

    ; Show main GUI and fill in fields
    MainGui.Show()

    PatternNameEdit.Value := suggestedName
    PatternCodeEdit.Value := patternCode
    PatternDescEdit.Value := "Captured " . w . "x" . h . " @ " . centerX . "," . centerY

    ; Update capture info display
    info := "Location:`n" . centerX . ", " . centerY . "`n`n"
    info .= "Window:`n" . (windowTitle != "" ? SubStr(windowTitle, 1, 15) : "(none)") . "`n`n"
    info .= "Size: " . w . "x" . h
    try PatternCaptureInfo.Value := info

    ; Update preview
    UpdatePatternPreview()

    ; Capture screenshot
    screenshotPath := CapturePatternScreenshot(suggestedName, centerX, centerY)
    if screenshotPath != "" && FileExist(screenshotPath) {
        try PatternImageBox.Value := screenshotPath
    }

    StatusBar.SetText("Pattern captured! Edit name and click Save.")
    SoundBeep(800, 50)
}

CancelQuickCapture(*) {
    global g_QuickCaptureActive, g_QuickCaptureOverlay
    g_QuickCaptureActive := false
    try g_QuickCaptureOverlay.Destroy()
    try Hotkey("Escape", "Off")
    ToolTip()
}

; Global for quick capture
global g_QuickCaptureActive := false
    ; g_QuickCaptureActive: Boolean flag for state tracking
global g_QuickCaptureOverlay := ""

; Update the image preview when pattern is selected
UpdatePatternImagePreview(name) {
    global g_Patterns, PatternImageBox

    if !g_Patterns.Has(name)
        return

    screenshotPath := g_Patterns[name].Has("screenshot") ? g_Patterns[name]["screenshot"] : ""

    if screenshotPath != "" && FileExist(screenshotPath) {
        try PatternImageBox.Value := screenshotPath
    } else {
        try PatternImageBox.Value := ""  ; Clear image
    }
}

UpdateQualPatternDD() {
    global g_Patterns, QualPatternDD
    items := ["(none)"]
    for name, _ in g_Patterns
        items.Push(name)
    QualPatternDD.Delete()
    QualPatternDD.Add(items)
    QualPatternDD.Choose(1)
}

RefreshTaskbarLV() {
    global g_TaskbarApps, TaskbarLV
    TaskbarLV.Delete()
    for app in g_TaskbarApps {
        if app["exe"] = "" {
            TaskbarLV.Add(, app["position"], "(not assigned)", app["hotkeyDisplay"])
        } else {
            shortTitle := StrLen(app["title"]) > 40 ? SubStr(app["title"], 1, 37) . "..." : app["title"]
            TaskbarLV.Add(, app["position"], shortTitle . " [" . app["exe"] . "]", app["hotkeyDisplay"])
        }
    }
}


; ═══════════════════════════════════════════════════════════════════════════════
; ANALYTICS FUNCTIONS
; ═══════════════════════════════════════════════════════════════════════════════
; ANALYTICS FUNCTIONS
; =============================================================================

ViewRecordingLog(*) {
    global g_FullRecordLog
    if g_FullRecordLog.Length = 0 {
        MsgBoxTop("No recording data.", "Empty")
        return
    }
    text := "Recording Log (" . g_FullRecordLog.Length . " events)`n`n"
    for i, entry in g_FullRecordLog {
        if i > 50 {
            text .= "`n... and " . (g_FullRecordLog.Length - 50) . " more"
            break
        }
        text .= entry["action"] . " @ " . entry["x"] . "," . entry["y"]
        text .= " [" . entry["window"] . "]`n"
    }
    MsgBoxTop(text, "Recording Log")
}

ClearRecordingLog(*) {
    global g_FullRecordLog, g_WindowHotspots, AnalyticsText
    g_FullRecordLog := []
    g_WindowHotspots := Map()
    AnalyticsText.Value := "Events: 0"
    StatusBar.SetText("Recording log cleared")
}

ExportRecording(*) {
    global RECORDING_FILE
    SaveRecordingLog()
    if FileExist(RECORDING_FILE)
        Run(RECORDING_FILE)
    else
        MsgBoxTop("No recording to export.", "Empty")
}


; ═══════════════════════════════════════════════════════════════════════════════
; CLIPBOARD REVOLVER SYSTEM
; ═══════════════════════════════════════════════════════════════════════════════
; CLIPBOARD REVOLVER SYSTEM

; ═══════════════════════════════════════════════════════════════════════════════
; LOADS PARSED CLIPBOARD FIELDS INTO A "REVOLVER" FOR SEQUENTIAL PASTING
; ═══════════════════════════════════════════════════════════════════════════════
; Loads parsed clipboard fields into a "revolver" for sequential pasting
; Each Ctrl+V fires the next field, then Tab, until all fields exhausted

LoadRevolver() {
    global g_ExtractedData

    ; Check we have extracted data
    if g_ExtractedData.Count = 0 {
        ShowStatus("No fields extracted! Parse clipboard first.", "fail")
        return false
    }

    ; Use the silent loader
    if LoadRevolverSilent() {
        SoundBeep(800, 50)  ; Chirp = loaded
        ShowStatus("Revolver loaded: " . g_RevolverChamber.Length . " shots", "ok")
        return true
    }
    return false
}

UnloadRevolver() {
    global g_RevolverLoaded, g_RevolverActive, g_RevolverChamber, g_RevolverPosition

    g_RevolverLoaded := false
    g_RevolverActive := false
    g_RevolverChamber := []
    g_RevolverPosition := 1

    ShowStatus("Revolver unloaded", "ok")
    UpdateRevolverDisplay()
}

; Full workflow: Copy, Parse, Load (silent - just loads the gun)
LoadRevolverFromSelection() {
    global g_ExtractedData, g_RevolverFieldOrder, g_Settings, ClipEdit
    global g_RevolverChamber, g_RevolverLoaded

    ; Step 1: Copy current selection
    A_Clipboard := ""
    Send("^c")
    ClipWait(1)

    if A_Clipboard = "" {
        ShowStatus("Nothing copied!", "fail")
        SoundBeep(300, 100)
        return false
    }

    ; Step 2: Store and parse
    ClipEdit.Value := A_Clipboard
    ParseClipboardForRevolver()

    ; Step 3: Load revolver silently
    if !LoadRevolverSilent() {
        SoundBeep(300, 100)
        return false
    }

    ; Feedback: loaded and ready
    SoundBeep(800, 50)  ; Quick chirp = loaded
    ShowStatus("Revolver loaded: " . g_RevolverChamber.Length . " shots ready", "ok")
    return true
}

; Fire all shots: paste + Tab + paste + Tab... (no Enter at end by default)
FireAllShots() {
    global g_RevolverChamber, g_RevolverLoaded, g_Settings

    if !g_RevolverLoaded || g_RevolverChamber.Length = 0 {
        ShowStatus("Revolver empty! Ctrl+B to load", "fail")
        SoundBeep(300, 100)
        return false
    }

    ; Fire each chamber
    Loop g_RevolverChamber.Length {
        chamber := g_RevolverChamber[A_Index]

        ShowStatus("[" . A_Index . "/" . g_RevolverChamber.Length . "] " . chamber["name"], "wait")

        ; Brief pause, type value, brief pause
        Sleep(g_Settings["PreActionDelay"])
        SendText(chamber["value"])
        Sleep(g_Settings["PostActionDelay"])

        ; Tab to next field (except after last)
        if A_Index < g_RevolverChamber.Length {
            Send("{Tab}")
            Sleep(50)
        }
    }

    ; Clear revolver
    shotsFired := g_RevolverChamber.Length
    g_RevolverChamber := []
    g_RevolverLoaded := false
    UpdateRevolverDisplay()

    ; Done!
    SoundBeep(600, 50)
    SoundBeep(800, 50)
    ShowStatus("Fired " . shotsFired . " shots!", "ok")
    return true
}

; Load revolver without any UI interaction (for workflow use)
LoadRevolverSilent() {
    global g_ExtractedData, g_RevolverChamber, g_RevolverPosition
    global g_RevolverFieldOrder, g_RevolverLoaded, g_RevolverActive

    if g_ExtractedData.Count = 0 {
        ShowStatus("No fields extracted!", "fail")
        return false
    }

    g_RevolverChamber := []
    g_RevolverPosition := 1

    for fieldName in g_RevolverFieldOrder {
        if g_ExtractedData.Has(fieldName) {
            g_RevolverChamber.Push(Map(
                "name", fieldName,
                "value", g_ExtractedData[fieldName]
            ))
        }
    }

    if g_RevolverChamber.Length = 0 {
        ShowStatus("No matching fields!", "fail")
        return false
    }

    g_RevolverLoaded := true
    g_RevolverActive := false  ; Don't intercept Ctrl+V

    UpdateRevolverDisplay()
    return true
}

; Preview revolver contents for confirmation dialog
PreviewRevolverContents() {
    global g_RevolverChamber
    preview := ""
    for i, chamber in g_RevolverChamber {
        preview .= i . ". " . chamber["name"] . ": " . chamber["value"] . "`n"
    }
    return preview
}

; Fire revolver as a sequence step (for workflow integration)
FireRevolverSequence(tabBetween := true, enterAtEnd := false) {
    global g_RevolverChamber, g_RevolverLoaded, g_Settings

    if !g_RevolverLoaded || g_RevolverChamber.Length = 0 {
        ShowStatus("Revolver empty!", "fail")
        return false
    }

    Loop g_RevolverChamber.Length {
        chamber := g_RevolverChamber[A_Index]

        ShowStatus("[" . A_Index . "/" . g_RevolverChamber.Length . "] " . chamber["name"], "wait")

        Sleep(g_Settings["PreActionDelay"])
        SendText(chamber["value"])
        Sleep(g_Settings["PostActionDelay"])

        ; Tab to next field (except after last, unless enterAtEnd is false)
        if tabBetween && A_Index < g_RevolverChamber.Length {
            Send("{Tab}")
            Sleep(50)
        }
    }

    if enterAtEnd {
        Sleep(50)
        Send("{Enter}")
    }

    ; Clear revolver
    g_RevolverChamber := []
    g_RevolverLoaded := false
    UpdateRevolverDisplay()

    ShowStatus("Revolver fired!", "ok")
    return true
}

ParseClipboardForRevolver() {
    global g_ExtractionRules, g_ExtractedData, ClipEdit, ExtractLV, RulesLV, g_Settings
    text := ClipEdit.Value
    if text = ""
        return
    g_ExtractedData := Map()
    ExtractLV.Delete()
    RulesLV.Delete()
    for r in g_ExtractionRules {
        if RegExMatch(text, r["pattern"], &m) {
            val := Trim(m.Count > 0 ? m[1] : m[0])
            g_ExtractedData[r["name"]] := val
            ExtractLV.Add(, r["name"], val)
            RulesLV.Add(, r["name"], r["pattern"], val)
        } else {
            RulesLV.Add(, r["name"], r["pattern"], "(no match)")
        }
    }
    ; Always add CurrentDate
    g_ExtractedData["CurrentDate"] := FormatTime(, g_Settings["DateFormat"])
    ExtractLV.Add(, "CurrentDate", g_ExtractedData["CurrentDate"])
}

UpdateRevolverDisplay() {
    global g_RevolverChamber, g_RevolverPosition, g_RevolverActive, RevolverStatus, RevolverLV

    try {
        if !g_RevolverActive {
            RevolverStatus.Value := "Revolver: Empty"
            RevolverStatus.Opt("cGray")
        } else {
            remaining := g_RevolverChamber.Length - g_RevolverPosition + 1
            RevolverStatus.Value := "Revolver: " . remaining . " rounds loaded"
            RevolverStatus.Opt("cGreen")
        }

        ; Update ListView
        RevolverLV.Delete()
        for i, chamber in g_RevolverChamber {
            status := ""
            if i < g_RevolverPosition
                status := "✓ Fired"
            else if i = g_RevolverPosition
                status := "► Next"
            else
                status := "○ Ready"
            RevolverLV.Add(, i, chamber["name"], chamber["value"], status)
        }
    }
}

MoveFieldUp(*) {
    global FieldOrderLV, g_RevolverFieldOrder
    row := FieldOrderLV.GetNext(0, "Focused")
    if row < 2
        return
    ; Swap in array
    temp := g_RevolverFieldOrder[row]
    g_RevolverFieldOrder[row] := g_RevolverFieldOrder[row - 1]
    g_RevolverFieldOrder[row - 1] := temp
    RefreshFieldOrderLV()
    FieldOrderLV.Modify(row - 1, "Select Focus")
    SaveFieldOrder()
}

MoveFieldDown(*) {
    global FieldOrderLV, g_RevolverFieldOrder
    row := FieldOrderLV.GetNext(0, "Focused")
    if row = 0 || row >= g_RevolverFieldOrder.Length
        return
    ; Swap in array
    temp := g_RevolverFieldOrder[row]
    g_RevolverFieldOrder[row] := g_RevolverFieldOrder[row + 1]
    g_RevolverFieldOrder[row + 1] := temp
    RefreshFieldOrderLV()
    FieldOrderLV.Modify(row + 1, "Select Focus")
    SaveFieldOrder()
}

AddFieldToOrder(*) {
    global g_RevolverFieldOrder, g_ExtractionRules
    ; Show available fields
    available := ["CurrentDate"]
    for r in g_ExtractionRules
        available.Push(r["name"])

    ; Simple input
    res := InputBoxTop("Field name to add:`n(Available: " . ArrayJoin(available, ", ") . ")", "Add Field", "")
    if res["Result"] = "OK" && res["Value"] != "" {
        g_RevolverFieldOrder.Push(res["Value"])
        RefreshFieldOrderLV()
        SaveFieldOrder()
    }
}

RemoveFieldFromOrder(*) {
    global FieldOrderLV, g_RevolverFieldOrder
    row := FieldOrderLV.GetNext(0, "Focused")
    if row = 0
        return
    g_RevolverFieldOrder.RemoveAt(row)
    RefreshFieldOrderLV()
    SaveFieldOrder()
}

RefreshFieldOrderLV() {
    global FieldOrderLV, g_RevolverFieldOrder
    FieldOrderLV.Delete()
    for i, name in g_RevolverFieldOrder
        FieldOrderLV.Add(, i, name)
}

ArrayJoin(arr, sep := ", ") {
    result := ""
    for i, v in arr
        result .= (i > 1 ? sep : "") . v
    return result
}
;ArrayJoin(arr, delimiter) {
;     result := ""
;     for item in arr {
;         if result != ""
;             result .= delimiter
;         result .= item
;     }
;     return result
; }

SaveFieldOrder() {
    global g_RevolverFieldOrder, SETTINGS_FILE
    orderStr := ArrayJoin(g_RevolverFieldOrder, "|")
    IniWrite(orderStr, SETTINGS_FILE, "Revolver", "FieldOrder")
}

LoadFieldOrder() {
    global g_RevolverFieldOrder, SETTINGS_FILE
    orderStr := IniRead(SETTINGS_FILE, "Revolver", "FieldOrder", "LastName|FirstName|DOB|CurrentDate")
    g_RevolverFieldOrder := StrSplit(orderStr, "|")
}

GetWorkflowActionNames() {
    return [
        "Click", "Double Click", "Triple Click", "Right Click",
        "Drag", "Relative Click", "Menu Select",
        "Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick", "Find & Drag",
        "Wait for Pattern", "Wait Until Gone",
        "Send Keys", "Type Text", "Key Chord", "Paste", "Set Clipboard",
        "Wait", "Activate Window", "Taskbar Activate", "Run Program",
        "Insert Field", "Insert Date", "Scroll",
        "Parse Clipboard", "Load Revolver", "Fire Revolver", "Fire Revolver+Enter",
        "OCR Region", "OCR Click", "OCR Wait", "OCR Full Screen to Var", "Load OCR Revolver", "Fire OCR Revolver",
        "Idle Mouse", "Hover Mouse", "Grab OCR to Var", "Use Var Paste", "Show Notification",
        "Set Variable", "Grab Clipboard", "If Contains", "If Variable", "Stop Execution", "Run Sequence",
        "Format Clipboard", "Append to Clipboard", "Prepend to Clipboard", "Extract from Clipboard"
    ]
}

MakeActionSpec(targetLabel, targetHint, paramLabel, paramHint, example, helpText,
               targetRequired := false, paramRequired := false,
               targetUsed := true, paramUsed := true, choiceField := "") {
    return Map(
        "targetLabel", targetLabel, "targetHint", targetHint,
        "paramLabel", paramLabel, "paramHint", paramHint,
        "example", example, "help", helpText,
        "targetRequired", targetRequired, "paramRequired", paramRequired,
        "targetUsed", targetUsed, "paramUsed", paramUsed,
        "choiceField", choiceField
    )
}

GetWorkflowActionSpec(action) {
    switch action {
        case "Click":
            return MakeActionSpec("Position", "name or x,y", "Click count", "optional", "Position=SaveButton; count=1", "Uses a saved coordinate or raw screen coordinates.", true, false, true, true, "target")
        case "Double Click", "Triple Click", "Right Click":
            return MakeActionSpec("Position", "name or x,y", "", "", "Position=PatientRow", "Uses a saved coordinate or raw screen coordinates.", true, false, true, false, "target")
        case "Drag":
            return MakeActionSpec("Saved drag", "or leave blank", "Raw drag", "x1,y1->x2,y2", "Saved drag=MoveCard", "Use a captured drag name, or put a raw start/end pair in Raw drag.", false, false, true, true, "target")
        case "Relative Click":
            return MakeActionSpec("Saved offset", "required", "", "", "Saved offset=RightOfField", "Select a relative coordinate captured with the Rel. button.", true, false, true, false, "target")
        case "Menu Select":
            return MakeActionSpec("", "", "Down presses", "required", "Down presses=3", "Moves down through a menu, then presses Enter.", false, true, false, true, "param")
        case "Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick":
            return MakeActionSpec("Pattern", "required", "", "", "Pattern=SubmitButton", "Finds the saved FindText pattern and performs the selected click.", true, false, true, false, "target")
        case "Find & Drag":
            return MakeActionSpec("Pattern", "required", "Destination", "endX,endY", "Pattern=Handle; Destination=800,500", "Finds the pattern, then drags from it to the destination.", true, true, true, true, "target")
        case "Wait for Pattern", "Wait Until Gone":
            return MakeActionSpec("Pattern", "required", "Timeout", "milliseconds", "Pattern=Loading; Timeout=5000", "Waits for the saved pattern to appear or disappear.", true, false, true, true, "target")
        case "Send Keys":
            return MakeActionSpec("", "", "Keys", "required", "Keys=^c or {Enter}", "AutoHotkey key syntax: ^=Ctrl, +=Shift, !=Alt, #=Win.", false, true, false, true, "param")
        case "Type Text":
            return MakeActionSpec("", "", "Text", "required", "Text=Hello world", "Types the supplied text literally.", false, true, false, true, "param")
        case "Key Chord":
            return MakeActionSpec("", "", "Chord", "modifier,key,count", "Chord=#,5,2", "Sends a modifier/key chord the requested number of times.", false, true, false, true, "param")
        case "Paste":
            return MakeActionSpec("", "", "", "", "No fields", "Pastes the current clipboard contents.", false, false, false, false)
        case "Set Clipboard":
            return MakeActionSpec("", "", "Clipboard text", "required", "Clipboard text=ID: $var.patientID", "Sets the clipboard; workflow variables are supported.", false, true, false, true, "param")
        case "Wait":
            return MakeActionSpec("", "", "Duration", "milliseconds", "Duration=1000", "Pauses the workflow for the specified time.", false, true, false, true, "param")
        case "Activate Window":
            return MakeActionSpec("", "", "Window title", "required", "Window title=Notepad", "Activates a window whose title contains this text.", false, true, false, true, "param")
        case "Taskbar Activate":
            return MakeActionSpec("", "", "Position,count", "required", "Position,count=5,2", "Uses Win+number to activate a taskbar item.", false, true, false, true, "param")
        case "Run Program":
            return MakeActionSpec("", "", "Program/command", "required", "Program/command=notepad.exe", "Runs an executable, document, URL, or command line.", false, true, false, true, "param")
        case "Insert Field":
            return MakeActionSpec("", "", "Field name", "required", "Field name=LastName", "Inserts a named extracted-data field.", false, true, false, true, "param")
        case "Insert Date":
            return MakeActionSpec("", "", "", "", "No fields", "Inserts the current date.", false, false, false, false)
        case "Scroll":
            return MakeActionSpec("", "", "Scroll amount", "+up / -down", "Scroll amount=-5", "Positive values scroll up; negative values scroll down.", false, true, false, true, "param")
        case "Parse Clipboard", "Load Revolver", "Fire Revolver", "Fire Revolver+Enter":
            return MakeActionSpec("", "", "", "", "No fields", "Uses the current clipboard/revolver state; no step input is needed.", false, false, false, false)
        case "OCR Region":
            return MakeActionSpec("OCR area", "x1,y1,x2,y2", "Output", "copy / var:name / split", "Area=100,100,600,300; Output=var:result", "Reads the selected screen rectangle and copies or stores the text.", true, false, true, true, "param")
        case "OCR Click":
            return MakeActionSpec("OCR area", "x1,y1,x2,y2", "Text to click", "required", "Area=0,0,1920,1080; Text=Submit", "Reads the area, finds matching text, and clicks its center.", true, true, true, true, "param")
        case "OCR Wait":
            return MakeActionSpec("OCR area", "x1,y1,x2,y2", "Condition", "timeout or text:...,ms", "Condition=text:Ready,5000", "Waits for OCR text, or simply for OCR to return text before timeout.", true, true, true, true, "param")
        case "OCR Full Screen to Var":
            return MakeActionSpec("", "", "Variable name", "required", "Variable name=fullScreenOCR", "Reads the full primary screen, stores all recognized text, and draws yellow boxes around every recognized word for 10 seconds.", false, true, false, true, "param")
        case "Load OCR Revolver":
            return MakeActionSpec("", "", "Split rule", "tab / line / count / char", "Split rule=tab", "Splits the latest OCR text and loads the OCR revolver.", false, false, false, true, "param")
        case "Fire OCR Revolver":
            return MakeActionSpec("", "", "", "", "No fields", "Pastes the next OCR revolver value.", false, false, false, false)
        case "Idle Mouse":
            return MakeActionSpec("", "", "Seconds", "0 = until stopped", "Seconds=30", "Gently moves the mouse for a duration; zero runs indefinitely.", false, false, false, true, "param")
        case "Hover Mouse":
            return MakeActionSpec("Position", "name or x,y", "", "", "Position=HelpIcon", "Moves the mouse to a saved coordinate without clicking.", true, false, true, false, "target")
        case "Grab OCR to Var":
            return MakeActionSpec("OCR area", "x,y,width,height", "Variable name", "required", "Area=100,100,500,200; Variable=patientID", "Captures an area and stores its text as a workflow variable.", true, true, true, true, "param")
        case "Use Var Paste":
            return MakeActionSpec("", "", "Text/template", "required", "Text/template=Patient: $var.patientID", "Expands workflow variables and pastes the result.", false, true, false, true, "param")
        case "Show Notification":
            return MakeActionSpec("", "", "Title,message,seconds", "required", "Done,Workflow complete,3", "Shows a desktop notification; variables are supported.", false, true, false, true, "param")
        case "Set Variable":
            return MakeActionSpec("Variable name", "letters/numbers/_", "Value", "text or $var.name", "Variable name=counter; Value=0", "Creates or replaces a workflow variable. Use it later as $var.counter.", true, false, true, true, "param")
        case "Grab Clipboard":
            return MakeActionSpec("Variable name", "letters/numbers/_", "", "", "Variable name=clipboardText", "Stores the current clipboard text in a workflow variable.", true, false, true, false, "target")
        case "If Contains":
            return MakeActionSpec("Variable name", "value to inspect", "Search text", "case-insensitive", "Variable name=ocrText; Search text=invoice", "Runs the next enabled step only when the variable contains the search text; otherwise that one step is skipped.", true, true, true, true, "target")
        case "If Variable":
            return MakeActionSpec("Variable name", "value to compare", "Comparison", "operator,value", "Variable name=count; Comparison=>=,5", "Compares a variable. Operators: =, !=, >, <, >=, <=. A false result skips the next enabled step.", true, true, true, true, "param")
        case "Stop Execution":
            return MakeActionSpec("", "", "", "", "No fields", "Stops the current workflow immediately without reporting an action failure.", false, false, false, false)
        case "Run Sequence":
            return MakeActionSpec("", "", "Workflow name", "required", "Workflow name=EnterPatient", "Runs another saved workflow as a sub-workflow. Variables remain available to it, and recursive calls are blocked.", false, true, false, true, "param")
        case "Format Clipboard":
            return MakeActionSpec("", "", "Format", "preset or {clip} template", "Format=uppercase", "Transforms the clipboard. Presets: invoice, receipt, uppercase, lowercase, titlecase, trim, date_iso. Custom templates use {clip}.", false, true, false, true, "param")
        case "Append to Clipboard":
            return MakeActionSpec("", "", "Text to append", "variables allowed", "Text to append= - reviewed", "Adds text to the end of the current clipboard.", false, true, false, true, "param")
        case "Prepend to Clipboard":
            return MakeActionSpec("", "", "Text to prepend", "variables allowed", "Text to prepend=INV-", "Adds text to the beginning of the current clipboard.", false, true, false, true, "param")
        case "Extract from Clipboard":
            return MakeActionSpec("", "", "Extraction rule", "between:/field:/regex:", "Extraction rule=field:,|2", "Replaces the clipboard with extracted text. Rules: between:start|end, field:delimiter|index, or regex:pattern.", false, true, false, true, "param")
        default:
            return MakeActionSpec("Target", "optional", "Value", "optional", "", "See the action guide for details.")
    }
}

ToggleAdvancedStepFields(*) {
    global AdvancedStepCheck, QualPatternLabel, QualPatternDD, QualWindowLabel, QualWindowEdit, FailsafeCloseCheck
    showAdvanced := AdvancedStepCheck.Value = 1
    for ctrl in [QualPatternLabel, QualPatternDD, QualWindowLabel, QualWindowEdit, FailsafeCloseCheck]
        ctrl.Visible := showAdvanced
}

ApplyActionFieldLayout(*) {
    global ActionDD, TargetFieldLabel, TargetFieldHint, TargetDD
    global ParamFieldLabel, ParamFieldHint, ParamCombo, ChoicesLabel, ChoicesDD, UseChoiceBtn, RefreshChoicesBtn, OCRRegionBtn

    action := ActionDD.Text
    spec := GetWorkflowActionSpec(action)
    TargetFieldLabel.Text := spec["targetLabel"] != "" ? spec["targetLabel"] . ":" : ""
    TargetFieldHint.Text := spec["targetHint"] != "" ? "(" . spec["targetHint"] . ")" : ""
    ParamFieldLabel.Text := spec["paramLabel"] != "" ? spec["paramLabel"] . ":" : ""
    ParamFieldHint.Text := spec["paramHint"] != "" ? "(" . spec["paramHint"] . ")" : ""

    for ctrl in [TargetFieldLabel, TargetFieldHint, TargetDD]
        ctrl.Visible := spec["targetUsed"]
    for ctrl in [ParamFieldLabel, ParamFieldHint, ParamCombo]
        ctrl.Visible := spec["paramUsed"]

    hasSuggestions := spec["choiceField"] != ""
    for ctrl in [ChoicesLabel, ChoicesDD, UseChoiceBtn, RefreshChoicesBtn]
        ctrl.Visible := hasSuggestions
    OCRRegionBtn.Visible := action = "OCR Region" || action = "OCR Click" || action = "OCR Wait" || action = "Grab OCR to Var"
    TargetDD.ToolTip := spec["targetHint"]
    ParamCombo.ToolTip := spec["paramHint"]
}

OnActionChange(*) {
    global ActionDD, TargetDD, ParamCombo, ChoicesDD, ActionHelpTitle, ActionHelpText
    global QualPatternDD, QualWindowEdit, FailsafeCloseCheck, AdvancedStepCheck

    ; Never carry values from a previous action into an unrelated action.
    TargetDD.Text := ""
    ParamCombo.Text := ""
    try QualPatternDD.Choose(1)
    QualWindowEdit.Value := ""
    FailsafeCloseCheck.Value := 0
    AdvancedStepCheck.Value := 0
    ToggleAdvancedStepFields()

    UpdateHints()
    UpdateTargetDD()
    UpdateParamSuggestions()
    PopulateChoices()
    UpdateActionHelp()  ; V5.0: Update real-time help panel

    ; Auto-set smart defaults based on action
    action := ActionDD.Text

    ; OCR actions default to full screen
    if InStr(action, "OCR") || InStr(action, "Grab OCR") {
        screenW := A_ScreenWidth
        screenH := A_ScreenHeight
        fullScreen := "0,0," . screenW . "," . screenH

        ; Set Target for OCR Region/Click/Wait
        if action = "OCR Region" || action = "OCR Click" || action = "OCR Wait" {
            TargetDD.Text := fullScreen
        }

        ; Set Param defaults
        if action = "OCR Region" && ParamCombo.Text = "" {
            ParamCombo.Text := "var:ocrText"  ; Default: save to variable with clear name
        } else if action = "Grab OCR to Var" {
            TargetDD.Text := fullScreen
            ParamCombo.Text := "varName"
        } else if action = "OCR Full Screen to Var" {
            ParamCombo.Text := "fullScreenOCR"
        } else if action = "OCR Click" && ParamCombo.Text = "" {
            ParamCombo.Text := "Button"
        } else if action = "OCR Wait" && ParamCombo.Text = "" {
            ParamCombo.Text := "5000"
        }
    }

    ; Wait actions default to 1000ms
    if action = "Wait" && ParamCombo.Text = "" {
        ParamCombo.Text := "1000"
    }

    ; Idle Mouse default to 0 (indefinite)
    if action = "Idle Mouse" && ParamCombo.Text = "" {
        ParamCombo.Text := "0"
    }

    ; Show Notification default format
    if action = "Show Notification" && ParamCombo.Text = "" {
        ParamCombo.Text := "Title,Message,3"
    }

    if action = "Set Variable" {
        TargetDD.Text := "variableName"
        ParamCombo.Text := "value"
    } else if action = "Grab Clipboard" {
        TargetDD.Text := "clipboardText"
    } else if action = "If Contains" {
        TargetDD.Text := "variableName"
        ParamCombo.Text := "text to find"
    } else if action = "If Variable" {
        TargetDD.Text := "variableName"
        ParamCombo.Text := "=,value"
    } else if action = "Format Clipboard" {
        ParamCombo.Text := "uppercase"
    } else if action = "Extract from Clipboard" {
        ParamCombo.Text := "field:,|1"
    }

    ; Pattern actions - show patterns in Choices
    ApplyActionFieldLayout()
    PopulateChoices()
    UpdateActionHelp()
}



; Refresh choices button handler

AddWorkflowTooltips() {
    global ActionDD, TargetDD, ParamCombo, ChoicesDD

    ActionDD.ToolTip := "Select the action type you want to perform"
    TargetDD.ToolTip := "Where to perform the action (position, pattern, region, etc.)"
    ParamCombo.ToolTip := "Additional parameters for the action (see hint below)"
    ChoicesDD.ToolTip := "Quick selection - click < to copy to Target/Param, Refresh to update list"
}


; ═══════════════════════════════════════════════════════════════════════════════
; DROPDOWN HELPER FUNCTIONS (AutoHotkey v2 compatible)
; ═══════════════════════════════════════════════════════════════════════════════

DDL_GetCount(ctrl) {
    count := 0
    Loop {
        try {
            ctrl.GetText(A_Index)
            count := A_Index
        } catch {
            break
        }
    }
    return count
}

DDL_AddAndSelect(ctrl, text) {
    ctrl.Add([text])
    ctrl.Text := text
}

DDL_FindAndSelect(ctrl, text) {
    Loop {
        try {
            if ctrl.GetText(A_Index) = text {
                ctrl.Choose(A_Index)
                return true
            }
        } catch {
            break
        }
    }
    return false
}


RefreshChoices(*) {
    PopulateChoices()
    ShowStatus("Choices refreshed", "ok")
}

; Copy from choices to appropriate field
UseChoice(*) {
    global ActionDD, TargetDD, ParamCombo, ChoicesDD

    if ChoicesDD.Value = 0
        return

    selected := ChoicesDD.Text
    action := ActionDD.Text

    ; Determine where to copy based on action type
    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click", "Hover Mouse", "Drag", "Relative Click":
            ; Extract coordinate name from "Name (x,y)" format
            if InStr(selected, " (") {
                coordName := SubStr(selected, 1, InStr(selected, " (") - 1)
                TargetDD.Text := coordName
            } else {
                TargetDD.Text := selected
            }
            ShowStatus("Copied to Target", "ok")

        case "Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick", "Find & Drag", "Wait for Pattern", "Wait Until Gone":
            TargetDD.Text := selected
            ShowStatus("Copied to Target (Pattern)", "ok")

        case "OCR Region":
            ; V5.1: Handle variable format or region
            if InStr(selected, "var:") {
                ; Variable creation format
                varName := StrReplace(selected, " (existing)", "")
                varName := StrReplace(varName, " (create new)", "")
                ParamCombo.Text := varName
                ShowStatus("Variable format copied to Param", "ok")
            } else if InStr(selected, "copy") {
                ParamCombo.Text := "copy"
                ShowStatus("Copy mode set", "ok")
            } else if InStr(selected, "(") {
                ; Region coordinates
                coords := SubStr(selected, InStr(selected, "(") + 1)
                coords := SubStr(coords, 1, InStr(coords, ")") - 1)
                TargetDD.Text := coords
                ShowStatus("Copied to Target (Region)", "ok")
            }

        case "OCR Click", "OCR Wait":
            ; Extract coordinates from region description
            if InStr(selected, "(") {
                coords := SubStr(selected, InStr(selected, "(") + 1)
                coords := SubStr(coords, 1, InStr(coords, ")") - 1)
                TargetDD.Text := coords
                ShowStatus("Copied to Target (Region)", "ok")
            }

        case "Grab OCR to Var", "OCR Full Screen to Var":
            cleanSelected := StrReplace(selected, " (existing)", "")
            cleanSelected := StrReplace(cleanSelected, " (create new)", "")
            ; Accept old combined suggestions but copy only the variable name.
            if InStr(cleanSelected, ",")
                cleanSelected := StrSplit(cleanSelected, ",")[1]
            ParamCombo.Text := cleanSelected
            ShowStatus("Copied variable name", "ok")

        case "Grab Clipboard", "If Contains", "If Variable":
            TargetDD.Text := selected
            ShowStatus("Copied variable name to Target", "ok")

        case "Set Clipboard", "Use Var Paste", "Show Notification", "Set Variable", "Append to Clipboard", "Prepend to Clipboard":
            ; V5.1: Insert variable or text
            if InStr(selected, "$var.") {
                ; It's a variable
                current := ParamCombo.Text
                if current = "" || current = "(type text or variable)"
                    ParamCombo.Text := selected
                else
                    ParamCombo.Text := current . selected
                ShowStatus("Variable inserted: " . selected, "ok")
            } else if selected != "(type text or variable)" {
                ParamCombo.Text := selected
                ShowStatus("Copied to Param", "ok")
            }

        case "Run Sequence", "Format Clipboard", "Extract from Clipboard":
            ParamCombo.Text := selected
            ShowStatus("Copied to Param", "ok")

        case "Send Keys", "Key Chord", "Taskbar Activate", "Type Text", "Scroll", "Wait", "Menu Select":
            ; These go to Param
            ParamCombo.Text := selected
            ShowStatus("Copied to Param", "ok")

        case "Activate Window", "Run Program":
            ; These go to Param
            ParamCombo.Text := selected
            ShowStatus("Copied to Param", "ok")

        case "Insert Field":
            ; Field name goes to Param
            ParamCombo.Text := selected
            ShowStatus("Copied to Param (Field)", "ok")

        default:
            ; Default to Param
            ParamCombo.Text := selected
            ShowStatus("Copied to Param", "ok")
    }
}


; Show OCR region preview overlay
global g_OCRPreview := ""

ShowOCRPreview(coords) {
    global g_OCRPreview, ActionDD

    ; Only show for OCR actions
    action := ActionDD.Text
    if !InStr(action, "OCR") && !InStr(action, "Grab OCR")
        return

    ; Parse coordinates
    parts := StrSplit(coords, ",")
    if parts.Length != 4
        return

    x1 := Integer(parts[1])
    y1 := Integer(parts[2])
    if InStr(action, "Grab OCR") {
        x2 := x1 + Integer(parts[3])
        y2 := y1 + Integer(parts[4])
    } else {
        x2 := Integer(parts[3])
        y2 := Integer(parts[4])
    }

    ; Validate
    if x2 <= x1 || y2 <= y1
        return

    w := x2 - x1
    h := y2 - y1

    ; Destroy old preview
    if g_OCRPreview != "" {
        try g_OCRPreview.Destroy()
    }

    ; Create new preview overlay
    g_OCRPreview := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "OCRPreview")
    g_OCRPreview.BackColor := "00FF00"  ; Green
    g_OCRPreview.Show("x" . x1 . " y" . y1 . " w" . w . " h" . h . " NoActivate")
    WinSetTransparent(100, g_OCRPreview)

    ; Create hollow region (border only, 4px thick)
    innerX := 4
    innerY := 4
    innerW := w - 8
    innerH := h - 8

    if innerW > 0 && innerH > 0 {
        try WinSetRegion("0-0 " . w . "-0 " . w . "-" . h . " 0-" . h . " 0-0 "
            . innerX . "-" . innerY . " " . (innerX + innerW) . "-" . innerY . " "
            . (innerX + innerW) . "-" . (innerY + innerH) . " " . innerX . "-" . (innerY + innerH)
            . " " . innerX . "-" . innerY, g_OCRPreview)
    }

    ; Add label
    try g_OCRPreview.SetFont("s10 bold", "Arial")
    try g_OCRPreview.Add("Text", "x5 y2 cLime BackgroundTrans", "OCR Preview")

    ; Add close button
    try {
        closeBtn := g_OCRPreview.Add("Button", "x" . (w - 22) . " y2 w20 h20", "✕")
        closeBtn.SetFont("s10 bold")
        closeBtn.OnEvent("Click", (*) => HideOCRPreview())
    }

    ; Auto-hide after 3 seconds
    SetTimer(() => HideOCRPreview(), -3000)
}

HideOCRPreview(*) {
    global g_OCRPreview
    if g_OCRPreview != "" {
        try g_OCRPreview.Destroy()
        g_OCRPreview := ""
    }
}

; Monitor Target field changes for OCR actions
OnTargetChange(*) {
    global TargetDD, ActionDD

    action := ActionDD.Text
    coords := TargetDD.Text

    ; Show preview for OCR actions
    if (InStr(action, "OCR") || InStr(action, "Grab OCR")) && InStr(coords, ",") {
        ; Check if it's a valid coordinate string (x1,y1,x2,y2)
        parts := StrSplit(coords, ",")
        if parts.Length = 4 {
            ShowOCRPreview(coords)
        }
    }
}

; Monitor Param field changes for Grab OCR to Var
OnParamChange(*) {
    global ParamCombo, ActionDD

    action := ActionDD.Text
    param := ParamCombo.Text

    ; For Grab OCR to Var, extract coordinates from param
    if InStr(action, "Grab OCR") {
        ; Format: varName,x1,y1,x2,y2
        parts := StrSplit(param, ",")
        if parts.Length >= 5 {
            coords := parts[2] . "," . parts[3] . "," . parts[4] . "," . parts[5]
            ShowOCRPreview(coords)
        }
    }
}

UpdateHints(*) {
    ; This function is now deprecated in favor of UpdateActionHelp()
    ; Kept for backward compatibility but does nothing
    return
}

; Context-sensitive help uses the same specification as validation and field layout.
UpdateActionHelp(*) {
    global ActionDD, ActionHelpTitle, ActionHelpText
    action := ActionDD.Text
    spec := GetWorkflowActionSpec(action)
    ActionHelpTitle.Text := action
    details := ""
    if spec["targetUsed"]
        details .= spec["targetLabel"] . ": " . spec["targetHint"] . "`n"
    if spec["paramUsed"]
        details .= spec["paramLabel"] . ": " . spec["paramHint"] . "`n"
    if spec["example"] != ""
        details .= "Example: " . spec["example"] . "`n"
    ActionHelpText.Text := details . spec["help"]
}

; Retained only as source history for older detailed help text.
UpdateActionHelpLegacy(*) {
    global ActionDD, ActionHelpTitle, ActionHelpText

    action := ActionDD.Text

    ; Comprehensive help for each action type
    helpData := Map(
        "Click", Map(
            "title", "Click - Mouse click at position",
            "text", "TARGET: Position name or x,y`nPARAM: Click count (1, 2, 3)`nExample: Target=MyButton, Param=1`nCommon error: Position not found - check name spelling"
        ),
        "OCR Region", Map(
            "title", "OCR Region - Extract text from screen area",
            "text", "TARGET: x,y,WIDTH,HEIGHT (not x1,y1,x2,y2!)`nPARAM: var:variableName (creates $var.variableName)`n`n⚠ CRITICAL: Format is x,y,WIDTH,HEIGHT`nExample: 100,100,400,200 means:`n  Start at (100,100), capture 400 wide × 200 tall`n`nUse 📷 OCR button for auto-calculation!`n`nVariable format:`n• Creating: var:myVar`n• Using later: $var.myVar"
        ),
        "OCR Click", Map(
            "title", "OCR Click - Find text via OCR and click it",
            "text", "TARGET: Search region x,y,width,height`nPARAM: Text to find`nExample: Target=0,0,1920,1080, Param=Submit`n⚠ Text must be visible and readable`n⚠ Increase scale if text not detected"
        ),
        "Grab OCR to Var", Map(
            "title", "Grab OCR to Var - OCR region and store to variable",
            "text", "PARAM: variableName,x,y,width,height`n`nFormat Rules:`n• Creating: variableName,x,y,w,h (no $ or var:)`n• Using later: $var.variableName`n`nExample:`n1. Grab OCR to Var → Param: patientID,100,100,200,50`n   Result: Creates $var.patientID`n2. Use Var Paste → Param: Patient: $var.patientID`n`n⚠ Check Choices dropdown for existing variables"
        ),
        "Use Var Paste", Map(
            "title", "Use Var Paste - Paste text with variables",
            "text", "PARAM: Text with $var.variableName placeholders`n`nChoices dropdown shows available variables!`n`nExamples:`n• Single variable: $var.patientID`n• Mixed text: Patient: $var.patientID, Date: $var.date`n• Multiple vars: $var.firstName $var.lastName`n`n⚠ Variables must be created first (OCR Region or Grab OCR to Var)`n⚠ Use exact format: $var.name"
        ),
        "Set Clipboard", Map(
            "title", "Set Clipboard - Copy text to clipboard",
            "text", "PARAM: Text or $var.variableName`n`nChoices dropdown shows available variables!`nClick '<' button to insert selected variable`n`nExamples:`n• Plain text: Hello World`n• Using variable: $var.ocrText`n• Mixed: Patient ID: $var.patientID`n`nWorkflow: OCR Region → Set Clipboard → Paste`n⚠ Use Choices dropdown - don't type variable manually"
        ),
        "Find & Click", Map(
            "title", "Find & Click - Find image pattern and click",
            "text", "TARGET: Pattern name`nPARAM: Search region (optional)`nExample: Target=SubmitButton`n⚠ Pattern not found? Recapture or increase variation`n⚠ Use Patterns tab to capture patterns"
        ),
        "Send Keys", Map(
            "title", "Send Keys - Send keyboard input",
            "text", "PARAM: Keys to send`nSpecial keys: {Enter} {Tab} {Esc}`nModifiers: ^ = Ctrl, + = Shift, ! = Alt`nExample: Param=^c (Ctrl+C)`nExample: Param=Hello{Enter}`n⚠ Use raw Send Keys if special chars don't work"
        ),
        "Wait", Map(
            "title", "Wait - Pause execution",
            "text", "PARAM: Milliseconds`nExample: Param=1000 (wait 1 second)`nExample: Param=500 (wait 0.5 seconds)`n⚠ Use between actions to allow UI to load"
        ),
        "Drag", Map(
            "title", "Drag - Click and drag between positions",
            "text", "TARGET: Drag position name`nPARAM: Duration in ms (default 300)`nExample: Target=MyDrag, Param=500`n⚠ Capture drag with 'Drag' button in capture row"
        ),
        "Type Text", Map(
            "title", "Type Text - Type text literally",
            "text", "PARAM: Text to type`nSupports $variables from OCR`nExample: Param=user@email.com`nExample: Param=$patientName`n⚠ Slower than Send Keys but more reliable"
        )
    )

    if helpData.Has(action) {
        data := helpData[action]
        ActionHelpTitle.Text := data["title"]
        ActionHelpText.Text := data["text"]
    } else {
        ActionHelpTitle.Text := action
        ActionHelpText.Text := "No detailed help available for this action yet.`nRefer to the action dropdown selection and parameter fields."
    }
}




PopulateChoices() {
    global ActionDD, ChoicesDD, g_ExtractedData, g_Coordinates, g_Patterns, g_TaskbarApps, g_Sequences, g_CurrentSequenceSteps

    action := ActionDD.Text
    choices := []

    ; V5.1: Check for variables created in current sequence
    sequenceVars := GetSequenceVariables()

    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click", "Hover Mouse":
            ; Show all saved coordinates
            for name, coord in g_Coordinates
                choices.Push(name . " (" . coord["x"] . "," . coord["y"] . ")")

        case "Drag":
            ; Show drag coordinates
            for name, coord in g_Coordinates {
                if coord.Has("endX")
                    choices.Push(name . " (" . coord["x"] . "," . coord["y"] . "→" . coord["endX"] . "," . coord["endY"] . ")")
            }

        case "Relative Click":
            ; Show relative coordinates
            for name, coord in g_Coordinates {
                if coord.Has("relative") && coord["relative"]
                    choices.Push(name . " (+" . coord["x"] . ",+" . coord["y"] . ")")
            }

        case "Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick", "Find & Drag":
            ; Show all patterns
            for name, _ in g_Patterns
                choices.Push(name)

        case "Wait for Pattern", "Wait Until Gone":
            ; Show all patterns
            for name, _ in g_Patterns
                choices.Push(name)

        case "OCR Region":
            ; V5.1: Show variable creation suggestions
            if sequenceVars.Length > 0 {
                for varName in sequenceVars
                    choices.Push("var:" . varName . " (existing)")
            }
            choices.Push("var:newVariable (create new)")
            choices.Push("copy (to clipboard)")

        case "Set Clipboard", "Use Var Paste", "Show Notification":
            ; V5.1: Show available variables from sequence
            if sequenceVars.Length > 0 {
                for varName in sequenceVars
                    choices.Push("$var." . varName)
            }
            choices.Push("(type text or variable)")

        case "Set Variable", "Append to Clipboard", "Prepend to Clipboard":
            for varName in sequenceVars
                choices.Push("$var." . varName)
            choices.Push("(type text or variable)")

        case "Grab Clipboard", "If Contains", "If Variable":
            for varName in sequenceVars
                choices.Push(varName)
            choices.Push("newVariable")

        case "Run Sequence":
            for name, _ in g_Sequences
                choices.Push(name)

        case "Format Clipboard":
            choices := ["invoice", "receipt", "uppercase", "lowercase", "titlecase", "trim", "date_iso", "[{clip}]"]

        case "Extract from Clipboard":
            choices := ["between:start|end", "field:,|1", "regex:\\d+"]

        case "Grab OCR to Var", "OCR Full Screen to Var":
            ; Variable and region are separate contextual fields.
            if sequenceVars.Length > 0 {
                for varName in sequenceVars
                    choices.Push(varName . " (existing)")
            }
            choices.Push("newVariable (create new)")

        case "OCR Click", "OCR Wait":
            ; Show common screen regions (for Target field)
            choices := [
                "0,0," . A_ScreenWidth . "," . A_ScreenHeight,
                "0,0," . A_ScreenWidth . "," . A_ScreenHeight//2,
                "0," . A_ScreenHeight//2 . "," . A_ScreenWidth . "," . A_ScreenHeight,
                "0,0," . A_ScreenWidth//2 . "," . A_ScreenHeight,
                A_ScreenWidth//2 . ",0," . A_ScreenWidth . "," . A_ScreenHeight
            ]

        case "Send Keys":
            choices := [
                "^c  (Ctrl+C)", "^v  (Ctrl+V)", "^x  (Ctrl+X)", "^a  (Ctrl+A)",
                "^s  (Ctrl+S)", "^z  (Ctrl+Z)", "^t  (Ctrl+T)", "^w  (Ctrl+W)",
                "{Enter}", "{Tab}", "{Escape}", "{Space}",
                "{Backspace}", "{Delete}", "{Home}", "{End}",
                "{Up}", "{Down}", "{Left}", "{Right}", "{F5}"
            ]

        case "Key Chord":
            choices := [
                "#,5,2  (Win+5 twice)",
                "#,1,1  (Win+1)",
                "^,c,1  (Ctrl+C)",
                "^,{Tab},3  (Ctrl+Tab x3)",
                "!,{Tab},2  (Alt+Tab x2)"
            ]

        case "Taskbar Activate":
            ; Show taskbar positions with app names if known
            for i in [1,2,3,4,5,6,7,8,9,0] {
                appName := g_TaskbarApps.Has(i) ? g_TaskbarApps[i] : ""
                if appName != ""
                    choices.Push(i . ",1  (" . appName . ")")
                else
                    choices.Push(i . ",1  (Position " . i . ")")
            }

        case "Activate Window":
            ; Show common window titles
            choices := GetWindowList()

        case "Run Program":
            ; Show common programs
            choices := GetCommonPrograms()

        case "Insert Field":
            ; Show extracted fields
            for name, _ in g_ExtractedData
                choices.Push(name)
            if choices.Length = 0
                choices.Push("(no fields extracted yet)")

        case "Type Text", "Use Var Paste":
            ; Show extracted fields as variables
            for name, _ in g_ExtractedData
                choices.Push("$" . name)
            if choices.Length = 0
                choices.Push("(no variables available)")

        case "Scroll":
            choices := ["-10 (down fast)", "-5 (down)", "-3 (down slow)", "-1 (down tiny)",
                       "1 (up tiny)", "3 (up slow)", "5 (up)", "10 (up fast)"]

        case "Wait":
            choices := ["100", "200", "500", "1000", "2000", "3000", "5000"]

        case "Menu Select":
            choices := ["File>Save", "File>Open", "Edit>Copy", "Edit>Paste", "View>Zoom"]

        default:
            choices := []
    }

    ; Update dropdown
    ChoicesDD.Delete()
    if choices.Length > 0
        ChoicesDD.Add(choices)




    choice := ChoicesDD.Text
    if choice = ""
        return
    action := ActionDD.Text

    ; For Key Chord and Taskbar Activate, strip description but keep the values
    if action = "Key Chord" || action = "Taskbar Activate" {
        if InStr(choice, "  ")
            choice := Trim(SubStr(choice, 1, InStr(choice, "  ") - 1))
        ParamCombo.Text := choice
        return
    }

    ; Strip common suffixes
    if InStr(choice, "  (")
        choice := Trim(SubStr(choice, 1, InStr(choice, "  (") - 1))
    if InStr(choice, "  [")
        choice := Trim(SubStr(choice, 1, InStr(choice, "  [") - 1))
    if InStr(choice, "[Pattern] ")
        choice := SubStr(choice, 11)
    if InStr(choice, "[P] ")
        choice := SubStr(choice, 5)
    if InStr(choice, "[Rel] ")
        choice := SubStr(choice, 7)
    if InStr(action, "Find &") {
        try {
            items := ControlGetItems(TargetDD)
            for i, item in items {
                if item = choice || item = "[P] " . choice || InStr(item, choice) {
                    TargetDD.Choose(i)
                    return
                }
            }
        }
    }
    ParamCombo.Text := choice


    StatusBar.SetText("Choices refreshed")
}


; ═══════════════════════════════════════════════════════════════════════════════
; TARGET DROPDOWN
; ═══════════════════════════════════════════════════════════════════════════════
; TARGET DROPDOWN
; =============================================================================


UpdateParamSuggestions() {
    global ActionDD, ParamCombo, g_ExtractedData, g_TaskbarApps, g_Sequences
    action := ActionDD.Text
    suggestions := []

    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click":
            suggestions := ["1", "2", "3"]

        case "Wait", "Wait for Pattern", "Wait Until Gone":
            suggestions := ["100", "200", "500", "1000", "2000", "3000", "5000", "10000"]

        case "Menu Select":
            suggestions := ["File>Save", "File>Open", "Edit>Copy", "Edit>Paste"]

        case "Send Keys":
            suggestions := [
                "^c", "^v", "^x", "^a", "^s", "^z",
                "{Enter}", "{Tab}", "{Escape}", "{Space}",
                "{Up}", "{Down}", "{Left}", "{Right}",
                "{Home}", "{End}", "{Delete}", "{Backspace}"
            ]

        case "Key Chord":
            suggestions := [
                "#,5,2  (Win+5 x2)",
                "#,1,1  (Win+1)",
                "^,c,1  (Ctrl+C)",
                "^,{Tab},3  (Ctrl+Tab x3)",
                "!,{Tab},2  (Alt+Tab x2)"
            ]

        case "Taskbar Activate":
            suggestions := [
                "1,1", "2,1", "3,1", "4,1", "5,1",
                "6,1", "7,1", "8,1", "9,1", "0,1"
            ]
            if g_TaskbarApps.Length > 0 {
                for i, app in g_TaskbarApps {
                    if app != ""
                        suggestions.Push(i . ",1  (" . SubStr(app, 1, 15) . ")")
                }
            }

        case "Activate Window":
            suggestions := GetWindowList()

        case "Run Program":
            suggestions := GetCommonPrograms()

        case "Insert Field":
            for name, _ in g_ExtractedData
                suggestions.Push(name)

        case "Scroll":
            suggestions := ["-10", "-5", "-3", "-1", "1", "3", "5", "10"]

        case "Type Text", "Use Var Paste":
            for name, _ in g_ExtractedData
                suggestions.Push("$" . name)
            if suggestions.Length = 0
                suggestions := ["$variableName", "Hello $name"]

        case "Set Clipboard":
            suggestions := ["Text to copy"]

        case "Find & Drag":
            suggestions := ["500,500", "0,100", "100,0"]

        case "Drag":
            suggestions := ["300 (duration ms)"]

        case "Relative Click":
            suggestions := ["10,0", "-10,0", "0,10", "0,-10"]

        case "OCR Region":
            suggestions := [
                "copy",
                "var:variableName",
                "split:4",
                "split:tab",
                "split:line",
                "regex:\\d+"
            ]

        case "OCR Click":
            suggestions := [
                "Submit", "OK", "Cancel", "Save", "Next", "Button"
            ]

        case "OCR Wait":
            suggestions := [
                "5000",
                "10000",
                "appear,text,5000"
            ]

        case "Load OCR Revolver":
            suggestions := [
                "space",
                "tab",
                "line",
                "comma"
            ]

        case "Idle Mouse":
            suggestions := ["0", "5", "10", "30"]

        case "Hover Mouse":
            suggestions := ["(position name from Fixed Positions)"]

        case "Grab OCR to Var", "OCR Full Screen to Var":
            suggestions := ["capturedText", "fullScreenOCR", "patientName"]

        case "Show Notification":
            suggestions := [
                "Title,Message,3",
                "Complete,Task finished,5"
            ]

        case "If Variable":
            suggestions := ["=,value", "!=,value", ">,0", ">=,5", "<,10", "<=,100"]

        case "Run Sequence":
            for name, _ in g_Sequences
                suggestions.Push(name)

        case "Format Clipboard":
            suggestions := ["invoice", "receipt", "uppercase", "lowercase", "titlecase", "trim", "date_iso", "[{clip}]"]

        case "Extract from Clipboard":
            suggestions := ["between:start|end", "field:,|1", "regex:\\d+"]
    }

    ; Update combobox
    ParamCombo.Delete()
    if suggestions.Length > 0
        ParamCombo.Add(suggestions)
}

UpdateTargetDD() {
    global ActionDD, TargetDD, g_Coordinates, g_Patterns

    action := ActionDD.Text
    items := []

    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click":
            ; Show click coordinates
            for name, coord in g_Coordinates {
                if !coord.Has("endX") && (!coord.Has("relative") || !coord["relative"])
                    items.Push(name)
            }

        case "Drag":
            ; Show drag coordinates
            for name, coord in g_Coordinates {
                if coord.Has("endX")
                    items.Push(name)
            }

        case "Relative Click":
            ; Show relative coordinates
            for name, coord in g_Coordinates {
                if coord.Has("relative") && coord["relative"]
                    items.Push(name)
            }

        case "Hover Mouse":
            ; Show all coordinates
            for name, coord in g_Coordinates {
                if !coord.Has("endX")
                    items.Push(name)
            }

        case "Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick", "Find & Drag", "Wait for Pattern", "Wait Until Gone":
            ; Show patterns
            for name, _ in g_Patterns
                items.Push(name)

        case "OCR Region", "OCR Click", "OCR Wait":
            ; Show common regions + saved coordinates
            items := [
                "0,0," . A_ScreenWidth . "," . A_ScreenHeight,  ; Full screen
                "0,0," . A_ScreenWidth . "," . A_ScreenHeight//2,  ; Top half
                "0," . A_ScreenHeight//2 . "," . A_ScreenWidth . "," . A_ScreenHeight  ; Bottom half
            ]

        case "Grab OCR to Var":
            items := ["0,0," . A_ScreenWidth . "," . A_ScreenHeight]

        case "Set Variable", "Grab Clipboard", "If Contains", "If Variable":
            items := GetSequenceVariables()
            if action = "Set Variable" || action = "Grab Clipboard"
                items.Push("newVariable")

        case "Activate Window":
            ; Show active windows
            items := GetWindowList()

        default:
            items := ["(not applicable)"]
    }

    ; Update dropdown
    currentText := TargetDD.Text
    TargetDD.Delete()

    if items.Length > 0 {
        TargetDD.Add(items)
        ; Try to restore previous selection
        if currentText != "" {
            Loop TargetDD.GetItemCount() {
                if TargetDD.GetText(A_Index) = currentText {
                    TargetDD.Choose(A_Index)
                    break
                }
            }
        }
    }
}




; ═══════════════════════════════════════════════════════════════════════════════
; COORDINATE CAPTURE
; ═══════════════════════════════════════════════════════════════════════════════
; COORDINATE CAPTURE
; =============================================================================

ShowCoordinateManager(*) {
    global MainGui, CoordLV, g_HiddenCoordLV, g_CoordManagerGui, g_CoordManagerNameEdit
    if IsObject(g_CoordManagerGui) {
        try {
            g_CoordManagerGui.Show()
            return
        }
    }

    manager := Gui("+Owner" . MainGui.Hwnd . " +Resize +MinSize620x390", "Workflow Position Tools")
    manager.SetFont("s9", "Segoe UI")
    manager.Add("Text", "x12 y12 w590", "Capture reusable click, drag, arrow-adjusted, or relative positions. These appear in action Suggestions.")
    manager.Add("Text", "x12 y45", "Position name (optional):")
    g_CoordManagerNameEdit := manager.Add("Edit", "x145 y42 w190")
    manager.Add("Button", "x345 y40 w60 h25", "Click").OnEvent("Click", CoordinateManagerStartCapture.Bind(manager, StartClickCapture))
    manager.Add("Button", "x410 y40 w60 h25", "Drag").OnEvent("Click", CoordinateManagerStartCapture.Bind(manager, StartDragCapture))
    manager.Add("Button", "x475 y40 w60 h25", "Arrow").OnEvent("Click", CoordinateManagerStartCapture.Bind(manager, StartArrowCapture))
    manager.Add("Button", "x540 y40 w65 h25", "Relative").OnEvent("Click", CoordinateManagerStartCapture.Bind(manager, StartRelativeCapture))

    managerLV := manager.Add("ListView", "x12 y78 w595 h255 Grid NoSortHdr", ["Name", "X", "Y", "End X", "End Y", "Type"])
    managerLV.ModifyCol(1, 170)
    managerLV.ModifyCol(2, 70)
    managerLV.ModifyCol(3, 70)
    managerLV.ModifyCol(4, 70)
    managerLV.ModifyCol(5, 70)
    managerLV.ModifyCol(6, 110)
    CoordLV := managerLV
    RefreshCoordLV()

    manager.Add("Button", "x12 y342 w80 h28", "Test").OnEvent("Click", TestCoord)
    manager.Add("Button", "x102 y342 w80 h28", "Delete").OnEvent("Click", DelCoord)
    manager.Add("Button", "x192 y342 w100 h28", "Refresh").OnEvent("Click", (*) => RefreshCoordLV())
    manager.Add("Button", "x527 y342 w80 h28", "Close").OnEvent("Click", (*) => CloseCoordinateManager())
    manager.OnEvent("Close", (*) => CloseCoordinateManager())
    g_CoordManagerGui := manager
    manager.Show("w620 h385")
}

CoordinateManagerStartCapture(manager, captureFunction, *) {
    global g_HiddenCoordNameEdit, g_CoordManagerNameEdit
    g_HiddenCoordNameEdit.Value := Trim(g_CoordManagerNameEdit.Value)
    manager.Hide()
    captureFunction.Call()
}

CoordinateManagerCaptureFinished() {
    global g_CoordManagerGui, g_CoordManagerNameEdit
    if IsObject(g_CoordManagerNameEdit)
        try g_CoordManagerNameEdit.Value := ""
    if IsObject(g_CoordManagerGui)
        try g_CoordManagerGui.Show()
}

CloseCoordinateManager(*) {
    global CoordLV, CoordNameEdit, g_HiddenCoordLV, g_HiddenCoordNameEdit
    global g_CoordManagerGui, g_CoordManagerNameEdit
    manager := g_CoordManagerGui
    CoordLV := g_HiddenCoordLV
    CoordNameEdit := g_HiddenCoordNameEdit
    g_CoordManagerGui := 0
    g_CoordManagerNameEdit := 0
    if IsObject(manager)
        try manager.Destroy()
}

StartClickCapture(*) {
    global g_IsCapturing, g_DragMode
    g_IsCapturing := true
    g_DragMode := false
    StatusBar.SetText("Click to capture. ESC cancel.")
    Hotkey("~LButton", CaptureClick, "On")
    Hotkey("Escape", CancelCap, "On")
}

StartDragCapture(*) {
    global g_IsCapturing, g_DragMode, g_DragStartX, g_DragStartY
    g_IsCapturing := true
    g_DragMode := true
    g_DragStartX := g_DragStartY := 0
    StatusBar.SetText("Click+drag, release. ESC cancel.")
    Hotkey("~LButton", CapDragStart, "On")
    Hotkey("~LButton Up", CapDragEnd, "On")
    Hotkey("Escape", CancelCap, "On")
}

CaptureClick(*) {
    global g_IsCapturing, g_Coordinates, CoordLV, CoordNameEdit
    if !g_IsCapturing
        return
    MouseGetPos(&x, &y)
    saved := MainGui.Submit(false)
    name := saved.CoordName != "" ? saved.CoordName : GenerateCoordName("Point")
    g_Coordinates[name] := Map("x", x, "y", y, "endX", "", "endY", "", "type", "Click")
    CoordLV.Add(, name, x, y, "", "", "Click")
    EndCapture()
    CoordNameEdit.Value := ""
    ShowMarker(x, y, 1000, "Green")
    SaveCoordinates()
    UpdateTargetDD()
    StatusBar.SetText("Saved: " . name)
}

CapDragStart(*) {
    global g_IsCapturing, g_DragStartX, g_DragStartY
    if !g_IsCapturing
        return
    MouseGetPos(&g_DragStartX, &g_DragStartY)
    ShowMarker(g_DragStartX, g_DragStartY, 5000, "Blue")
}

CapDragEnd(*) {
    global g_IsCapturing, g_DragMode, g_DragStartX, g_DragStartY, g_Coordinates, CoordLV, CoordNameEdit
    if !g_IsCapturing || !g_DragMode
        return
    MouseGetPos(&endX, &endY)
    saved := MainGui.Submit(false)
    name := saved.CoordName != "" ? saved.CoordName : GenerateCoordName("Drag")
    g_Coordinates[name] := Map("x", g_DragStartX, "y", g_DragStartY, "endX", endX, "endY", endY, "type", "Drag")
    CoordLV.Add(, name, g_DragStartX, g_DragStartY, endX, endY, "Drag")
    EndCapture()
    CoordNameEdit.Value := ""
    ShowMarker(endX, endY, 1000, "Green")
    SaveCoordinates()
    UpdateTargetDD()
    StatusBar.SetText("Saved drag: " . name)
}

CancelCap(*) {
    EndCapture()
    StatusBar.SetText("Cancelled")
}

EndCapture() {
    global g_IsCapturing, g_DragMode
    g_IsCapturing := false
    g_DragMode := false
    try Hotkey("~LButton", "Off")
    try Hotkey("~LButton Up", "Off")
    try Hotkey("Escape", "Off")
    CoordinateManagerCaptureFinished()
}

StartArrowCapture(*) {
    global g_IsCalibrating
    g_IsCalibrating := true
    MouseGetPos(&x, &y)
    ShowMarker(x, y, 99999, "Blue")
    Hotkey("Up", (*) => MoveBy(0, -1), "On")
    Hotkey("Down", (*) => MoveBy(0, 1), "On")
    Hotkey("Left", (*) => MoveBy(-1, 0), "On")
    Hotkey("Right", (*) => MoveBy(1, 0), "On")
    Hotkey("+Up", (*) => MoveBy(0, -10), "On")
    Hotkey("+Down", (*) => MoveBy(0, 10), "On")
    Hotkey("+Left", (*) => MoveBy(-10, 0), "On")
    Hotkey("+Right", (*) => MoveBy(10, 0), "On")
    Hotkey("Enter", FinishArrow, "On")
    Hotkey("Escape", CancelArrow, "On")
    StatusBar.SetText("Arrows=1px, Shift+Arrows=10px, Enter=save")
}

MoveBy(dx, dy) {
    global g_IsCalibrating
    if !g_IsCalibrating
        return
    MouseGetPos(&x, &y)
    MouseMove(x + dx, y + dy, 0)
    ShowMarker(x + dx, y + dy, 99999, "Blue")
}

FinishArrow(*) {
    global g_IsCalibrating, g_Coordinates, CoordLV
    if !g_IsCalibrating
        return
    MouseGetPos(&x, &y)
    EndArrow()
    name := GenerateCoordName("Point")
    g_Coordinates[name] := Map("x", x, "y", y, "endX", "", "endY", "", "type", "Click")
    CoordLV.Add(, name, x, y, "", "", "Click")
    SaveCoordinates()
    UpdateTargetDD()
    ShowMarker(x, y, 1500, "Green")
    StatusBar.SetText("Saved: " . name)
}

CancelArrow(*) {
    EndArrow()
    StatusBar.SetText("Cancelled")
}

EndArrow() {
    global g_IsCalibrating
    g_IsCalibrating := false
    for k in ["Up", "Down", "Left", "Right", "+Up", "+Down", "+Left", "+Right", "Enter", "Escape"]
        try Hotkey(k, "Off")
    HideMarker()
    CoordinateManagerCaptureFinished()
}

; Relative Capture
global g_RelCaptureStage := 0
global g_RelRefX := 0, g_RelRefY := 0

StartRelativeCapture(*) {
    global g_IsCapturing, g_RelCaptureStage
    g_IsCapturing := true
    g_RelCaptureStage := 1
    StatusBar.SetText("STEP 1: Click REFERENCE point. ESC cancel.")
    Hotkey("~LButton", CaptureRelativeClick, "On")
    Hotkey("Escape", CancelRelCap, "On")
}

CaptureRelativeClick(*) {
    global g_IsCapturing, g_RelCaptureStage, g_RelRefX, g_RelRefY
    global g_Coordinates, CoordLV, CoordNameEdit
    if !g_IsCapturing
        return
    MouseGetPos(&x, &y)
    if g_RelCaptureStage = 1 {
        g_RelRefX := x
        g_RelRefY := y
        g_RelCaptureStage := 2
        ShowMarker(x, y, 10000, "Blue")
        StatusBar.SetText("STEP 2: Click TARGET.")
    } else if g_RelCaptureStage = 2 {
        offsetX := x - g_RelRefX
        offsetY := y - g_RelRefY
        saved := MainGui.Submit(false)
        name := saved.CoordName != "" ? saved.CoordName : GenerateCoordName("Relative")
        g_Coordinates[name] := Map("x", offsetX, "y", offsetY, "endX", g_RelRefX, "endY", g_RelRefY, "type", "Relative")
        CoordLV.Add(, name, offsetX, offsetY, g_RelRefX, g_RelRefY, "Relative")
        EndRelCapture()
        CoordNameEdit.Value := ""
        ShowMarker(x, y, 1500, "Green")
        SaveCoordinates()
        UpdateTargetDD()
        StatusBar.SetText("Saved: " . name . " (offset: " . offsetX . "," . offsetY . ")")
    }
}

CancelRelCap(*) {
    EndRelCapture()
    StatusBar.SetText("Cancelled")
}

EndRelCapture() {
    global g_IsCapturing, g_RelCaptureStage
    g_IsCapturing := false
    g_RelCaptureStage := 0
    try Hotkey("~LButton", "Off")
    try Hotkey("Escape", "Off")
    HideMarker()
    CoordinateManagerCaptureFinished()
}

TestCoord(*) {
    global CoordLV, g_Coordinates
    row := CoordLV.GetNext(0, "Focused")
    if row = 0
        return
    name := CoordLV.GetText(row, 1)
    c := g_Coordinates[name]
    MouseMove(c["x"], c["y"], 5)
    ShowMarker(c["x"], c["y"], 1500, "Green")
}

DelCoord(*) {
    global CoordLV, g_Coordinates
    row := CoordLV.GetNext(0, "Focused")
    if row = 0
        return
    name := CoordLV.GetText(row, 1)
    g_Coordinates.Delete(name)
    CoordLV.Delete(row)
    SaveCoordinates()
    UpdateTargetDD()
}

CreatePatient(name, phone := "", email := "", notes := "") {
    global g_NextPatientID, g_Patients
    id := g_NextPatientID++
    g_Patients[id] := Map(
        "id", id,
        "name", name,
        "phone", phone,
        "email", email,
        "notes", notes,
        "visitHistory", []
    )
    SavePatients()
    return id
}

SavePatients() {
    global g_Patients, g_NextPatientID, DATA_DIR
    patientFile := DATA_DIR . "\patients.ini"
    if FileExist(patientFile)
        FileDelete(patientFile)

    IniWrite(g_NextPatientID, patientFile, "Settings", "NextID")
    for id, patient in g_Patients {
        section := "Patient_" . id
        IniWrite(patient["name"], patientFile, section, "Name")
        IniWrite(patient["phone"], patientFile, section, "Phone")
        IniWrite(patient["email"], patientFile, section, "Email")
        IniWrite(patient["notes"], patientFile, section, "Notes")
        history := patient.Has("visitHistory") ? StrJoin(patient["visitHistory"], "|") : ""
        IniWrite(history, patientFile, section, "VisitHistory")
    }
}

LoadPatients() {
    global g_Patients, g_NextPatientID, DATA_DIR
    patientFile := DATA_DIR . "\patients.ini"
    g_Patients := Map()
    g_NextPatientID := 1
    if !FileExist(patientFile)
        return

    sections := IniRead(patientFile)
    highestID := 0
    for section in StrSplit(sections, "`n", "`r") {
        section := Trim(section)
        if InStr(section, "Patient_") = 1
            idText := SubStr(section, 9)
        else if InStr(section, "Patient") = 1
            idText := SubStr(section, 8)
        else
            continue
        if !IsNumber(idText)
            continue
        id := Integer(idText)
        history := []
        historyText := IniRead(patientFile, section, "VisitHistory", "")
        if historyText != ""
            for visitDate in StrSplit(historyText, "|")
                history.Push(visitDate)
        g_Patients[id] := Map(
            "id", id,
            "name", IniRead(patientFile, section, "Name", ""),
            "phone", IniRead(patientFile, section, "Phone", ""),
            "email", IniRead(patientFile, section, "Email", ""),
            "notes", IniRead(patientFile, section, "Notes", ""),
            "visitHistory", history
        )
        highestID := Max(highestID, id)
    }
    nextText := IniRead(patientFile, "Settings", "NextID", IniRead(patientFile, "Meta", "NextID", highestID + 1))
    g_NextPatientID := IsNumber(nextText) ? Max(Integer(nextText), highestID + 1) : highestID + 1
}

OpenNewPatientDialog(*) {
    OpenPatientProfileEditor(0)
}

SavePatientProfile(patientID, nameEdit, phoneEdit, emailEdit, notesEdit, profileGui, *) {
    global g_Patients, g_NextPatientID
    name := Trim(nameEdit.Value)
    if name = "" {
        MsgBox("Patient name is required.", "Patient Profile", "Icon!")
        return false
    }

    if patientID <= 0 {
        patientID := g_NextPatientID++
    }
    visitHistory := []
    if g_Patients.Has(patientID) && g_Patients[patientID].Has("visitHistory")
        visitHistory := g_Patients[patientID]["visitHistory"]
    g_Patients[patientID] := Map(
        "id", patientID,
        "name", name,
        "phone", phoneEdit.Value,
        "email", emailEdit.Value,
        "notes", notesEdit.Value,
        "visitHistory", visitHistory
    )
    SavePatients()
    profileGui.Destroy()
    ShowStatus("Patient profile saved: " . name, "ok")
    return true
}

BookAppointment(time, patientDD, typeDD, bookGui, *) {
    global g_CalendarDate, g_Appointments
    patientName := Trim(patientDD.Text)
    typeName := Trim(typeDD.Text)
    if patientName = "" || typeName = "" {
        MsgBox("Select both a patient and an appointment type.", "Book Appointment", "Icon!")
        return false
    }

    key := g_CalendarDate . "_" . StrReplace(time, ":", "")
    g_Appointments[key] := patientName . " - " . typeName
    SaveAppointments()
    RefreshCalendar()
    bookGui.Destroy()
    ShowStatus("Appointment booked for " . patientName . " at " . time, "ok")
    return true
}
ClickTimeSlot4(time) {
    ; Create dialog GUI
    BookGui := Gui("+OwnerMainGui", "Book Appointment")

    BookGui.Add("Text", "x10 y10", "Patient:")
    patientNames := GetPatientNames()
    patientDD := BookGui.Add("DropDownList", "x70 y10 w200", patientNames)
    BookGui.Add("Button", "x275 y10 w80 h25", "New Patient").OnEvent("Click", (*) => OpenNewPatientDialog())

    BookGui.Add("Text", "x10 y40", "Type:")
    typeDD := BookGui.Add("DropDownList", "x70 y40 w200", [
        "Contact Lens Exam",
        "Regular Eye Exam",
        "New Patient",
        "Medical Visit"
    ])

    BookGui.Add("Button", "x70 y80 w80 h25", "Book").OnEvent("Click", (*) => BookAppointment(time, patientDD, typeDD, BookGui))
    BookGui.Add("Button", "x160 y80 w80 h25", "Cancel").OnEvent("Click", (*) => BookGui.Destroy())

    BookGui.Show()
}
OpenPatientProfileEditor(patientID := 0) {
    ProfileGui := Gui("+OwnerMainGui", "Patient Profile")

    ; Load existing patient or create blank
    if (patientID > 0) {
        patient := g_Patients[patientID]
        name := patient["name"]
        phone := patient["phone"]
        email := patient["email"]
        notes := patient["notes"]
    } else {
        name := ""
        phone := ""
        email := ""
        notes := ""
    }

    ProfileGui.Add("Text", "x10 y10", "Name:")
    nameEdit := ProfileGui.Add("Edit", "x70 y10 w250", name)

    ProfileGui.Add("Text", "x10 y40", "Phone:")
    phoneEdit := ProfileGui.Add("Edit", "x70 y40 w250", phone)

    ProfileGui.Add("Text", "x10 y70", "Email:")
    emailEdit := ProfileGui.Add("Edit", "x70 y70 w250", email)

    ProfileGui.Add("Text", "x10 y100", "Notes:")
    notesEdit := ProfileGui.Add("Edit", "x70 y100 w250 h80 Multi", notes)

    ProfileGui.Add("Button", "x70 y190 w80 h25", "Save").OnEvent("Click", (*) => SavePatientProfile(patientID, nameEdit, phoneEdit, emailEdit, notesEdit, ProfileGui))
    ProfileGui.Add("Button", "x160 y190 w80 h25", "Cancel").OnEvent("Click", (*) => ProfileGui.Destroy())

    ProfileGui.Show()
}
InitializeAppointmentTypes() {
    global g_AppointmentTypes
    g_AppointmentTypes := Map()
    g_AppointmentTypes["ContactLens"] := Map(
        "name", "Contact Lens Exam",
        "duration", 30,
        "color", "Green",
        "tasks", [
            Map("task", "Verify contact lens prescription", "notifyBefore", 5),
            Map("task", "Prepare trial lenses", "notifyBefore", 10),
            Map("task", "Check lens fit and comfort", "notifyBefore", 0),
            Map("task", "Provide care instructions", "notifyBefore", 0),
            Map("task", "Order new supply if needed", "notifyBefore", 0)
        ]
    )
    g_AppointmentTypes["RegularExam"] := Map(
        "name", "Regular Eye Exam",
        "duration", 45,
        "color", "Blue",
        "tasks", [
            Map("task", "Pull previous records", "notifyBefore", 10),
            Map("task", "Dilate pupils if needed", "notifyBefore", 5),
            Map("task", "Perform vision tests", "notifyBefore", 0),
            Map("task", "Check eye health", "notifyBefore", 0),
            Map("task", "Discuss prescription changes", "notifyBefore", 0)
        ]
    )
    g_AppointmentTypes["NewPatient"] := Map(
        "name", "New Patient Intake",
        "duration", 60,
        "color", "Red",
        "tasks", [
            Map("task", "Scan insurance information", "notifyBefore", 15),
            Map("task", "Enter insurance into web app profile", "notifyBefore", 10),
            Map("task", "Verify all data is correct", "notifyBefore", 5),
            Map("task", "Ensure name is ALL CAPS in system", "notifyBefore", 5),
            Map("task", "Complete medical history form", "notifyBefore", 0),
            Map("task", "Take patient photos", "notifyBefore", 0),
            Map("task", "Create patient folder", "notifyBefore", 0)
        ]
    )
    g_AppointmentTypes["Medical"] := Map(
        "name", "Medical Visit",
        "duration", 30,
        "color", "Maroon",
        "tasks", [
            Map("task", "Get credit card on file", "notifyBefore", 10),
            Map("task", "Have patient sign payment authorization", "notifyBefore", 5),
            Map("task", "Determine co-pay amount", "notifyBefore", 5),
            Map("task", "Verify insurance is active", "notifyBefore", 5),
            Map("task", "Review chief complaint", "notifyBefore", 0),
            Map("task", "Document visit in EMR", "notifyBefore", 0),
            Map("task", "Process payment", "notifyBefore", 0)
        ]
    )
    g_AppointmentTypes["FollowUp"] := Map(
        "name", "Follow-Up Visit",
        "duration", 15,
        "color", "Purple",
        "tasks", [
            Map("task", "Review previous visit notes", "notifyBefore", 5),
            Map("task", "Check on prescribed treatment", "notifyBefore", 0),
            Map("task", "Update treatment plan", "notifyBefore", 0)
        ]
    )
}

InitializeAppointmentScheduler() {
    InitializeAppointmentTypes()
    LoadPatients()
    LoadAppointments()
}

FormatTimeSlot(time24) {
    parts := StrSplit(time24, ":")
    if parts.Length < 2
        return time24
    hour := Integer(parts[1])
    displayHour := hour > 12 ? hour - 12 : (hour = 0 ? 12 : hour)
    return displayHour . ":" . parts[2] . (hour >= 12 ? " PM" : " AM")
}

GetAppointmentKey(date, time) {
    return StrReplace(date, "-", "") . "_" . StrReplace(time, ":", "")
}

GetAppointment(date, time) {
    global g_Appointments
    key := GetAppointmentKey(date, time)
    return g_Appointments.Has(key) && IsObject(g_Appointments[key]) ? g_Appointments[key] : Map()
}

CancelAppointment(date, time) {
    global g_Appointments
    key := GetAppointmentKey(date, time)
    if !g_Appointments.Has(key)
        return false
    g_Appointments.Delete(key)
    SaveAppointments()
    RefreshCalendar()
    ShowStatus("Appointment canceled", "ok")
    return true
}

RefreshCalendarDisplay(*) {
    RefreshCalendar()
}

CalculateNotificationTime(appointmentDateTime, minutesBefore) {
    compact := StrReplace(StrReplace(StrReplace(appointmentDateTime, "-", ""), ":", ""), " ", "")
    if StrLen(compact) = 12
        compact .= "00"
    return FormatTime(DateAdd(compact, -minutesBefore, "Minutes"), "yyyy-MM-dd HH:mm")
}

GetPatient(patientID) {
    global g_Patients
    return g_Patients.Has(patientID) ? g_Patients[patientID] : Map()
}

GetPatientNamesList() {
    return GetPatientNames()
}

GetPatientIDByName(name) {
    global g_Patients
    for id, patient in g_Patients
        if patient["name"] = name
            return id
    return 0
}

OpenBookingDialog(time, existingAppointment := "") {
    global g_CalendarDate, g_AppointmentTypes, MainGui
    bookingGui := Gui("+Owner" . MainGui.Hwnd, "Book Appointment")
    bookingGui.SetFont("s9", "Segoe UI")
    bookingGui.Add("Text", "x12 y12 w370", FormatTime(g_CalendarDate, "dddd, MMMM d, yyyy") . " at " . FormatTimeSlot(time))

    bookingGui.Add("Text", "x12 y48", "Patient:")
    patientNames := GetPatientNamesList()
    if patientNames.Length = 0
        patientNames.Push("(Create a patient first)")
    patientDD := bookingGui.Add("DropDownList", "x95 y45 w220", patientNames)
    patientDD.Choose(1)
    bookingGui.Add("Button", "x322 y44 w65 h24", "New").OnEvent("Click", (*) => OpenNewPatientForBooking(bookingGui, patientDD))

    bookingGui.Add("Text", "x12 y82", "Type:")
    typeNames := []
    for _, typeInfo in g_AppointmentTypes
        typeNames.Push(typeInfo["name"])
    typeDD := bookingGui.Add("DropDownList", "x95 y79 w292", typeNames)
    typeDD.Choose(1)

    bookingGui.Add("Text", "x12 y116", "Scheduled tasks:")
    taskPreview := bookingGui.Add("Edit", "x12 y136 w375 h160 ReadOnly Multi VScroll")
    typeDD.OnEvent("Change", (*) => ShowTaskPreview(typeDD, taskPreview))
    ShowTaskPreview(typeDD, taskPreview)

    if IsObject(existingAppointment) && existingAppointment is Map && existingAppointment.Count > 0 {
        if existingAppointment.Has("patientName")
            patientDD.Text := existingAppointment["patientName"]
        if existingAppointment.Has("typeName")
            typeDD.Text := existingAppointment["typeName"]
    }

    bookingGui.Add("Button", "x95 y310 w100 h30 Default", "Save Booking").OnEvent("Click", (*) => ConfirmAppointmentBooking(time, patientDD, typeDD, bookingGui))
    bookingGui.Add("Button", "x205 y310 w90 h30", "Close").OnEvent("Click", (*) => bookingGui.Destroy())
    bookingGui.Show("w400 h355")
}

OpenNewPatientForBooking(parentGui, patientDD) {
    patientGui := Gui("+Owner" . parentGui.Hwnd, "New Patient")
    patientGui.SetFont("s9", "Segoe UI")
    patientGui.Add("Text", "x10 y12", "Name:")
    nameEdit := patientGui.Add("Edit", "x75 y10 w250")
    patientGui.Add("Text", "x10 y47", "Phone:")
    phoneEdit := patientGui.Add("Edit", "x75 y45 w250")
    patientGui.Add("Text", "x10 y82", "Email:")
    emailEdit := patientGui.Add("Edit", "x75 y80 w250")
    patientGui.Add("Text", "x10 y117", "Notes:")
    notesEdit := patientGui.Add("Edit", "x75 y115 w250 h70 Multi")
    patientGui.Add("Button", "x75 y200 w100 h30 Default", "Create").OnEvent("Click", (*) => SaveNewPatient(nameEdit, phoneEdit, emailEdit, notesEdit, patientGui, patientDD))
    patientGui.Add("Button", "x185 y200 w90 h30", "Cancel").OnEvent("Click", (*) => patientGui.Destroy())
    patientGui.Show("w340 h245")
}

SaveNewPatient(nameEdit, phoneEdit, emailEdit, notesEdit, patientGui, patientDD, *) {
    name := Trim(nameEdit.Value)
    if name = "" {
        MsgBox("Patient name is required.", "New Patient", "Icon!")
        return
    }
    CreatePatient(name, Trim(phoneEdit.Value), Trim(emailEdit.Value), Trim(notesEdit.Value))
    names := GetPatientNamesList()
    patientDD.Delete()
    patientDD.Add(names)
    patientDD.Text := name
    patientGui.Destroy()
    ShowStatus("Patient created: " . name, "ok")
}

ConfirmAppointmentBooking(time, patientDD, typeDD, bookingGui, *) {
    global g_CalendarDate, g_AppointmentTypes
    patientName := patientDD.Text
    patientID := GetPatientIDByName(patientName)
    if !patientID {
        MsgBox("Select or create a patient first.", "Book Appointment", "Icon!")
        return
    }
    appointmentType := ""
    for typeKey, typeInfo in g_AppointmentTypes
        if typeInfo["name"] = typeDD.Text {
            appointmentType := typeKey
            break
        }
    if appointmentType = "" {
        MsgBox("Select an appointment type.", "Book Appointment", "Icon!")
        return
    }
    if BookAppointmentV7(g_CalendarDate, time, patientID, appointmentType) {
        bookingGui.Destroy()
        ShowStatus("Appointment saved for " . patientName . " at " . FormatTimeSlot(time), "ok")
    }
}

BookAppointmentV7(date, time, patientID, appointmentType) {
    global g_Appointments, g_Patients, g_AppointmentTypes
    if !g_Patients.Has(patientID) || !g_AppointmentTypes.Has(appointmentType)
        return false
    patient := g_Patients[patientID]
    typeInfo := g_AppointmentTypes[appointmentType]
    key := GetAppointmentKey(date, time)
    g_Appointments[key] := Map(
        "date", StrReplace(date, "-", ""),
        "time", time,
        "patientID", patientID,
        "patientName", patient["name"],
        "appointmentType", appointmentType,
        "typeName", typeInfo["name"],
        "duration", typeInfo["duration"],
        "tasks", typeInfo["tasks"],
        "status", "Scheduled"
    )

    if !patient.Has("visitHistory")
        patient["visitHistory"] := []
    visitRecorded := false
    for visitDate in patient["visitHistory"]
        if visitDate = StrReplace(date, "-", "")
            visitRecorded := true
    if !visitRecorded
        patient["visitHistory"].Push(StrReplace(date, "-", ""))

    appointmentStamp := StrReplace(date, "-", "") . StrReplace(time, ":", "") . "00"
    for task in typeInfo["tasks"] {
        triggerTime := DateAdd(appointmentStamp, -task["notifyBefore"], "Minutes")
        if DateDiff(triggerTime, A_Now, "Seconds") > 0
            CreateScheduledNotification(triggerTime, "Appointment Task", patient["name"] . " - " . task["task"])
    }
    SaveAppointments()
    SavePatients()
    RefreshCalendar()
    return true
}

OpenPatientList(*) {
    global MainGui
    listGui := Gui("+Owner" . MainGui.Hwnd . " +Resize +MinSize620x350", "Patients")
    listGui.SetFont("s9", "Segoe UI")
    patientLV := listGui.Add("ListView", "x10 y10 w680 h300 Grid", ["ID", "Name", "Phone", "Email", "Last Visit"])
    patientLV.ModifyCol(1, 45)
    patientLV.ModifyCol(2, 175)
    patientLV.ModifyCol(3, 120)
    patientLV.ModifyCol(4, 210)
    patientLV.ModifyCol(5, 100)
    RefreshPatientListLV(patientLV)
    listGui.Add("Button", "x10 y320 w90 h28", "New Patient").OnEvent("Click", (*) => OpenPatientProfileEditor(0))
    listGui.Add("Button", "x110 y320 w90 h28", "Edit").OnEvent("Click", (*) => EditSelectedPatient(patientLV))
    listGui.Add("Button", "x210 y320 w90 h28", "Refresh").OnEvent("Click", (*) => RefreshPatientListLV(patientLV))
    listGui.Add("Button", "x600 y320 w90 h28", "Close").OnEvent("Click", (*) => listGui.Destroy())
    patientLV.OnEvent("DoubleClick", (*) => EditSelectedPatient(patientLV))
    listGui.Show("w700 h365")
}

RefreshPatientListLV(lv) {
    global g_Patients
    lv.Delete()
    for id, patient in g_Patients {
        lastVisit := ""
        if patient.Has("visitHistory") && patient["visitHistory"].Length > 0
            lastVisit := patient["visitHistory"][patient["visitHistory"].Length]
        lv.Add(, id, patient["name"], patient["phone"], patient["email"], lastVisit)
    }
}

EditSelectedPatient(lv) {
    row := lv.GetNext(0, "Focused")
    if row > 0
        OpenPatientProfileEditor(Integer(lv.GetText(row, 1)))
}

GetPatientNames() {
    names := []
    for id, patient in g_Patients {
        names.Push(patient["name"])
    }
    return names
}
; SEQUENCE BUILDER


SelectOCRRegionForWorkflow(*) {
    global MainGui, ActionDD, TargetDD, ParamCombo, g_LastOCRRegion, g_OCRHighlight

    ; Switch action to OCR Region if not already an OCR action
    action := ActionDD.Text
    if !InStr(action, "OCR") && !InStr(action, "Grab OCR") {
        ; Find and select OCR Region
        Loop ActionDD.GetItemCount() {
            if ActionDD.GetText(A_Index) = "OCR Region" {
                ActionDD.Choose(A_Index)
                break
            }
        }
        OnActionChange()
    }

    MainGui.Hide()
    Sleep(200)

    ; Show instruction tooltip
    ToolTip("📷 Drag to select OCR region`nESC to cancel`nHighlight will persist after selection", A_ScreenWidth//2 - 150, 50)

    ; Track drag state
    x1 := 0, y1 := 0, x2 := 0, y2 := 0
    cancelled := false
    selBox := ""
    boxW := 0, boxH := 0  ; Declare outside loop so they persist

    ; Cancel hotkey
    Hotkey("Escape", (*) => (cancelled := true), "On")

    ; Wait for mouse down
    while !GetKeyState("LButton", "P") && !cancelled {
        Sleep(10)
    }

    if cancelled {
        ToolTip()
        Hotkey("Escape", "Off")
        MainGui.Show()
        return
    }

    MouseGetPos(&x1, &y1)

    ; Create selection box (border only, click-through)
    selBox := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "SelBox")
    selBox.BackColor := "00FF00"

    ; Draw selection while dragging
    while GetKeyState("LButton", "P") && !cancelled {
        MouseGetPos(&x2, &y2)

        ; Update selection box
        boxX := Min(x1, x2)
        boxY := Min(y1, y2)
        boxW := Max(Abs(x2 - x1), 10)
        boxH := Max(Abs(y2 - y1), 10)

        if boxW > 5 && boxH > 5 {
            ; Show as border frame only (hollow rectangle)
            selBox.Show("x" . boxX . " y" . boxY . " w" . boxW . " h" . boxH . " NoActivate")
            WinSetTransparent(180, selBox)

            ; Create hollow region (border only, 3px thick)
            innerX := 3
            innerY := 3
            innerW := boxW - 6
            innerH := boxH - 6

            if innerW > 0 && innerH > 0 {
                try WinSetRegion("0-0 " . boxW . "-0 " . boxW . "-" . boxH . " 0-" . boxH . " 0-0 "
                    . innerX . "-" . innerY . " " . (innerX + innerW) . "-" . innerY . " "
                    . (innerX + innerW) . "-" . (innerY + innerH) . " " . innerX . "-" . (innerY + innerH)
                    . " " . innerX . "-" . innerY, selBox)
            }
        }

        Sleep(16)
    }

    ; Don't destroy the box yet - keep it as persistent highlight
    ToolTip()
    Hotkey("Escape", "Off")

    if cancelled || Abs(x2 - x1) < 10 || Abs(y2 - y1) < 10 {
        try selBox.Destroy()
        MainGui.Show()
        return
    }

    ; Normalize coordinates
    finalX1 := Min(x1, x2)
    finalY1 := Min(y1, y2)
    finalX2 := Max(x1, x2)
    finalY2 := Max(y1, y2)

    ; OCR Region/Click/Wait use corner coordinates. Grab OCR's underlying
    ; implementation uses x,y,width,height, so present the format it expects.
    currentAction := ActionDD.Text
    if InStr(currentAction, "Grab OCR")
        coordStr := finalX1 . "," . finalY1 . "," . (finalX2 - finalX1) . "," . (finalY2 - finalY1)
    else
        coordStr := finalX1 . "," . finalY1 . "," . finalX2 . "," . finalY2

    ; Store for reference
    g_LastOCRRegion := Map("x1", finalX1, "y1", finalY1, "x2", finalX2, "y2", finalY2)

    ; Destroy old highlight if exists
    if g_OCRHighlight != "" {
        try g_OCRHighlight.Destroy()
    }

    ; Create persistent highlight overlay (green border)
    g_OCRHighlight := selBox  ; Keep the selection box as persistent highlight
    WinSetTransparent(120, g_OCRHighlight)  ; Make it semi-transparent

    ; Add label to highlight
    try g_OCRHighlight.SetFont("s12 bold", "Arial")
    try g_OCRHighlight.Add("Text", "x5 y-2 cLime BackgroundTrans", "OCR Region")

    ; Add coordinates to TargetDD dropdown
    found := false
    Loop TargetDD.GetItemCount() {
        if TargetDD.GetText(A_Index) = coordStr {
            TargetDD.Choose(A_Index)
            found := true
            break
        }
    }

    if !found {
        TargetDD.Add([coordStr])
        DDL_AddAndSelect(TargetDD, coordStr)
    }

    ; Pre-fill param based on action type
    if ParamCombo.Text = "" {
        if InStr(currentAction, "Grab OCR") {
            ParamCombo.Text := "varName"
        } else if currentAction = "OCR Region" {
            ParamCombo.Text := "copy"
        } else if currentAction = "OCR Click" {
            ParamCombo.Text := "Button"
        } else if currentAction = "OCR Wait" {
            ParamCombo.Text := "appear,Complete,5000"
        }
    }

    MainGui.Show()
    ShowStatus("OCR Region: " . coordStr . " (highlight persists - click X to dismiss)", "ok")

    ; Add dismiss button to highlight (boxW now available)
    try {
        dismissBtn := g_OCRHighlight.Add("Button", "x" . (boxW - 25) . " y2 w20 h20", "X")
        dismissBtn.SetFont("s8 bold")
        dismissBtn.OnEvent("Click", (*) => DismissOCRHighlight())
    }
}


DismissOCRHighlight(*) {
    global g_OCRHighlight
    if g_OCRHighlight != "" {
        try g_OCRHighlight.Destroy()
        g_OCRHighlight := ""
        ShowStatus("OCR highlight dismissed", "ok")
    }




    return false
}

AddStep(*) {
    global g_CurrentSequenceSteps, ActionDD, TargetDD, ParamEdit, ParamCombo, QualPatternDD, QualWindowEdit, FailsafeCloseCheck
    ; Validate action is selected
    if ActionDD.Text = "" {
        ShowStatus("Please select an action", "fail")
        return
    }

    action := ActionDD.Text

    spec := GetWorkflowActionSpec(action)
    if spec["targetRequired"] && Trim(TargetDD.Text) = "" {
        ShowStatus(spec["targetLabel"] . " is required for " . action, "fail")
        return
    }
    if spec["paramRequired"] && Trim(ParamCombo.Text) = "" {
        ShowStatus(spec["paramLabel"] . " is required for " . action, "fail")
        return
    }
    if action = "Drag" && Trim(TargetDD.Text) = "" && Trim(ParamCombo.Text) = "" {
        ShowStatus("Drag requires either a saved drag or raw x1,y1->x2,y2", "fail")
        return
    }

    ; V5.1: Parameter validation before adding step
    if !ShowParameterValidation(action, TargetDD.Text, ParamCombo.Text) {
        return
    }

    saved := MainGui.Submit(false)
    target := TargetDD.Text
    if SubStr(target, 1, 4) = "[P] "
        target := SubStr(target, 5)
    if InStr(target, " (") && InStr(target, ",")
        target := Trim(SubStr(target, 1, InStr(target, " (") - 1))

    step := Map(
        "action", ActionDD.Text,
        "target", target,
        "param", saved.ActionParam,
        "enabled", true
    )

    if QualPatternDD.Text != "(none)"
        step["qualPattern"] := QualPatternDD.Text
    if saved.QualWindow != ""
        step["qualWindow"] := saved.QualWindow
    if saved.FailsafeClose
        step["failsafe"] := Map("checkCloseBtn", 1)

    g_CurrentSequenceSteps.Push(step)
    RefreshStepsLV()
    ParamEdit.Value := ""
    PopulateChoices()  ; V5.1: Refresh choices to show any new variables
    StatusBar.SetText("Added step " . g_CurrentSequenceSteps.Length)
    ScheduleWorkflowAutosave()
}

StepUp(*) {
    global g_CurrentSequenceSteps, StepsLV
    row := StepsLV.GetNext(0, "Focused")
    if row < 2
        return
    temp := g_CurrentSequenceSteps[row]
    g_CurrentSequenceSteps[row] := g_CurrentSequenceSteps[row - 1]
    g_CurrentSequenceSteps[row - 1] := temp
    RefreshStepsLV()
    StepsLV.Modify(row - 1, "Select Focus")
    ScheduleWorkflowAutosave()
}

StepDown(*) {
    global g_CurrentSequenceSteps, StepsLV
    row := StepsLV.GetNext(0, "Focused")
    if row = 0 || row >= g_CurrentSequenceSteps.Length
        return
    temp := g_CurrentSequenceSteps[row]
    g_CurrentSequenceSteps[row] := g_CurrentSequenceSteps[row + 1]
    g_CurrentSequenceSteps[row + 1] := temp
    RefreshStepsLV()
    StepsLV.Modify(row + 1, "Select Focus")
    ScheduleWorkflowAutosave()
}

EditStep(*) {
    global g_CurrentSequenceSteps, StepsLV, g_Coordinates, g_Patterns, g_ExtractedData, g_TaskbarApps
    row := StepsLV.GetNext(0, "Focused")
    if row = 0 || row > g_CurrentSequenceSteps.Length
        return

    step := g_CurrentSequenceSteps[row]
    action := step["action"]
    target := step["target"]
    param := step["param"]

    ; Create smart edit dialog
    editGui := Gui("+AlwaysOnTop", "Edit Step " . row . ": " . action)
    editGui.SetFont("s9", "Segoe UI")

    ; Action type (read-only display)
    editGui.Add("Text", "w400", "Action: " . action)
    editGui.Add("Text", "", "(To change action, delete and re-add step)")

    ; Target section (if applicable)
    editGui.Add("GroupBox", "y+15 w420 h75 Section", "Target")
    editGui.Add("Text", "xs+10 ys+20", "Current:")
    editGui.Add("Edit", "x+5 w300 ReadOnly", target)

    ; Target dropdown for changing
    editGui.Add("Text", "xs+10 y+8", "Change to:")
    targetChoices := ["(none)"]

    ; Build target choices based on action
    if InStr(action, "Find &") || InStr(action, "Pattern") {
        for name, _ in g_Patterns
            targetChoices.Push("[P] " . name)
    } else if action = "Relative Click" {
        for name, c in g_Coordinates
            if c["type"] = "Relative"
                targetChoices.Push(name)
    } else {
        for name, _ in g_Coordinates
            targetChoices.Push(name)
    }

    editTargetDD := editGui.Add("ComboBox", "x+5 w300 vNewTarget", targetChoices)
    editTargetDD.Choose(1)

    ; Parameter section with templates
    editGui.Add("GroupBox", "xs y+20 w420 h130", "Parameter")
    editGui.Add("Text", "xp+10 yp+20", "Current value:")
    editParamEdit := editGui.Add("Edit", "w390 h22 vNewParam", param)

    ; Get action-specific suggestions
    editGui.Add("Text", "y+10", "Suggestions for " . action . ":")
    suggestions := GetActionParamSuggestions(action)
    editSuggestDD := editGui.Add("DropDownList", "w300 vSuggestion", suggestions)
    editGui.Add("Button", "x+5 w80 h22", "Use").OnEvent("Click", (*) => (editParamEdit.Value := CleanSuggestion(editSuggestDD.Text)))

    ; Quick templates/info
    editGui.Add("Text", "xs+10 y+8 w400 cGray", GetActionParamHelp(action))

    ; Failsafe button
    editGui.Add("Button", "xs y+20 w120 h26", "🛡 Edit Failsafe...").OnEvent("Click", (*) => (editGui.Destroy(), EditStepFailsafeByRow(row)))

    ; Save/Cancel buttons
    editGui.Add("Button", "x+120 w80 h26", "Save").OnEvent("Click", (*) => SaveEditedStep(editGui, row))
    editGui.Add("Button", "x+10 w80 h26", "Cancel").OnEvent("Click", (*) => editGui.Destroy())

    editGui.Show()
}

; Get param suggestions based on action type
GetActionParamSuggestions(action) {
    global g_ExtractedData, g_TaskbarApps, g_Sequences

    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click":
            return ["1", "2", "3"]
        case "Wait", "Wait for Pattern", "Wait Until Gone":
            return ["100", "200", "500", "1000", "2000", "3000", "5000", "10000"]
        case "Menu Select":
            return ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
        case "Send Keys":
            return ["^c", "^v", "^x", "^a", "^s", "^z", "{Enter}", "{Tab}", "{Escape}",
                    "{Up}", "{Down}", "{Left}", "{Right}", "!{Tab}", "!{F4}", "#r"]
        case "Key Chord":
            return ["#,5,2  (Win+5 x2)", "#,1,1  (Win+1)", "^,{Tab},3  (Ctrl+Tab x3)",
                    "!,{Tab},2  (Alt+Tab x2)", "^+,{Tab},1  (Ctrl+Shift+Tab)"]
        case "Taskbar Activate":
            choices := ["1,1", "2,1", "3,1", "4,1", "5,1", "5,2", "6,1", "7,1", "8,1", "9,1", "0,1"]
            return choices
        case "Activate Window":
            return GetWindowList()
        case "Run Program":
            return ["notepad.exe", "calc.exe", "chrome.exe", "cmd.exe", "explorer.exe", "code.exe"]
        case "Scroll":
            return ["-10", "-5", "-3", "-1", "1", "3", "5", "10"]
        case "Insert Field":
            choices := []
            for name, _ in g_ExtractedData
                choices.Push(name)
            choices.Push("CurrentDate")
            return choices
        case "Find & Drag":
            return ["500,500", "0,100", "100,0", "-100,0", "0,-100"]
        case "Drag":
            return ["100,100->200,200", "0,0->100,100"]
        case "Relative Click":
            return ["10,0", "-10,0", "0,10", "0,-10", "50,50", "100,0"]
        case "If Variable":
            return ["=,value", "!=,value", ">,0", ">=,5", "<,10", "<=,100"]
        case "Run Sequence":
            choices := []
            for name, _ in g_Sequences
                choices.Push(name)
            return choices
        case "Format Clipboard":
            return ["invoice", "receipt", "uppercase", "lowercase", "titlecase", "trim", "date_iso", "[{clip}]"]
        case "Extract from Clipboard":
            return ["between:start|end", "field:,|1", "regex:\\d+"]
        default:
            return [""]
    }
}

; Get help text for action parameter
GetActionParamHelp(action) {
    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click":
            return "Leave empty for default (1 click), or enter click count"
        case "Wait":
            return "Enter milliseconds to wait"
        case "Wait for Pattern", "Wait Until Gone":
            return "Enter timeout in ms (default 5000)"
        case "Send Keys":
            return "^ = Ctrl, + = Shift, ! = Alt, # = Win. Use {Key} for special keys"
        case "Key Chord":
            return "Format: modifier,key,count (e.g. #,5,2 for Win+5 twice)"
        case "Taskbar Activate":
            return "Format: position,count (e.g. 5,2 for Win+5 twice)"
        case "Activate Window":
            return "Partial window title match"
        case "Type Text":
            return "Text to type character by character"
        case "Find & Drag":
            return "Format: endX,endY"
        case "Drag":
            return "Format: startX,startY->endX,endY"
        case "Scroll":
            return "Positive = up, Negative = down"
        case "Set Variable":
            return "Target is the variable name; Param is its value"
        case "If Contains":
            return "Target is a variable; a false test skips the next enabled step"
        case "If Variable":
            return "Format: operator,value (for example >=,5)"
        case "Run Sequence":
            return "Exact saved workflow name; recursive calls are blocked"
        case "Format Clipboard":
            return "Use a preset or a custom template containing {clip}"
        case "Extract from Clipboard":
            return "between:start|end, field:delimiter|index, or regex:pattern"
        default:
            return ""
    }
}

; Clean suggestion text (remove descriptions)
CleanSuggestion(text) {
    if InStr(text, "  (")
        return Trim(SubStr(text, 1, InStr(text, "  (") - 1))
    if InStr(text, "  [")
        return Trim(SubStr(text, 1, InStr(text, "  [") - 1))
    return text
}

; Save edited step
SaveEditedStep(editGui, row) {
    global g_CurrentSequenceSteps

    if row > g_CurrentSequenceSteps.Length
        return

    saved := editGui.Submit(false)

    ; Update target if changed
    if saved.NewTarget != "(none)"
        g_CurrentSequenceSteps[row]["target"] := saved.NewTarget

    ; Update parameter
    g_CurrentSequenceSteps[row]["param"] := saved.NewParam

    editGui.Destroy()
    RefreshStepsLV()
    ShowStatus("Step " . row . " updated", "ok")
    ScheduleWorkflowAutosave()
}

DelStep(*) {
    global g_CurrentSequenceSteps, StepsLV
    row := StepsLV.GetNext(0, "Focused")
    if row = 0
        return
    g_CurrentSequenceSteps.RemoveAt(row)
    RefreshStepsLV()
    ScheduleWorkflowAutosave()
}

ToggleStep(*) {
    global g_CurrentSequenceSteps, StepsLV
    row := StepsLV.GetNext(0, "Focused")
    if row = 0
        return

    ; Ensure enabled property exists before toggling
    if !g_CurrentSequenceSteps[row].Has("enabled")
        g_CurrentSequenceSteps[row]["enabled"] := true

    g_CurrentSequenceSteps[row]["enabled"] := !g_CurrentSequenceSteps[row]["enabled"]
    RefreshStepsLV()
    StepsLV.Modify(row, "Select Focus")
    ScheduleWorkflowAutosave()
}

ClearSteps(*) {
    global g_CurrentSequenceSteps
    g_CurrentSequenceSteps := []
    RefreshStepsLV()
    ScheduleWorkflowAutosave()
}

RefreshStepsLV() {
    global g_CurrentSequenceSteps, StepsLV
    StepsLV.Delete()
    for i, s in g_CurrentSequenceSteps {
        ; Default enabled to true if not set
        if !s.Has("enabled")
            s["enabled"] := true

        failsafeSummary := GetFailsafeSummary(s)
        StepsLV.Add(s["enabled"] ? "Check" : "", i, s["action"], s["target"], s["param"], failsafeSummary)
    }
}

CloneWorkflowSteps(steps) {
    cloned := []
    for step in steps {
        newStep := Map()
        for key, value in step {
            if key = "failsafe" && value is Map {
                fsCopy := Map()
                for fsKey, fsValue in value
                    fsCopy[fsKey] := fsValue
                newStep[key] := fsCopy
            } else {
                newStep[key] := value
            }
        }
        cloned.Push(newStep)
    }
    return cloned
}

BuildCurrentWorkflowData() {
    global g_CurrentSequenceSteps, SpeedDD, SeqHotkeyEdit, SeqHotstringEdit
    speedText := SpeedDD.Text != "" ? SpeedDD.Text : "1x"
    seqData := Map("steps", CloneWorkflowSteps(g_CurrentSequenceSteps), "speed", Float(StrReplace(speedText, "x", "")))
    if Trim(SeqHotkeyEdit.Value) != ""
        seqData["hotkey"] := Trim(SeqHotkeyEdit.Value)
    if Trim(SeqHotstringEdit.Value) != ""
        seqData["hotstring"] := Trim(SeqHotstringEdit.Value)
    return seqData
}

ScheduleWorkflowAutosave(*) {
    global g_LoadingWorkflow, g_WorkflowAutoSavePending
    if g_LoadingWorkflow
        return
    g_WorkflowAutoSavePending := true
    SetTimer(AutoSaveCurrentWorkflow, -650)
}

AutoSaveCurrentWorkflow() {
    global g_LoadingWorkflow, g_WorkflowAutoSavePending, g_CurrentSequenceSteps
    global g_Sequences, SeqNameEdit, WorkflowSaveStatus, g_LastWorkflowSaveError
    g_WorkflowAutoSavePending := false
    if g_LoadingWorkflow
        return

    name := Trim(SeqNameEdit.Value)
    if name = ""
        return
    if g_CurrentSequenceSteps.Length = 0 && !g_Sequences.Has(name)
        return

    g_Sequences[name] := BuildCurrentWorkflowData()
    if SaveSequences() {
        RegisterSequenceTriggers(name)
        RefreshSeqLV()
        WorkflowSaveStatus.Text := "Autosaved: " . name . " at " . FormatTime(, "h:mm:ss tt")
        WorkflowSaveStatus.SetFont("c008000")
    } else {
        WorkflowSaveStatus.Text := "Autosave failed: " . g_LastWorkflowSaveError
        WorkflowSaveStatus.SetFont("cRed")
    }
}

SaveSeq(*) {
    global g_CurrentSequenceSteps, g_Sequences, SeqNameEdit, SpeedDD, SeqHotkeyEdit, SeqHotstringEdit
    saved := MainGui.Submit(false)
    if saved.SeqName = "" {
        MsgBoxTop("Enter name!", "Required")
        return
    }
    if g_CurrentSequenceSteps.Length = 0 {
        MsgBoxTop("Add steps!", "Empty")
        return
    }
    steps := CloneWorkflowSteps(g_CurrentSequenceSteps)
    speedText := SpeedDD.Text
    seqData := BuildCurrentWorkflowData()
    g_Sequences[saved.SeqName] := seqData

    ; Persist before clearing the editor. A failed save leaves the work visible
    ; and the database transaction keeps the previous saved copy intact.
    if !SaveSequences(true) {
        WorkflowSaveStatus.Text := "Save failed - workflow remains open for retry."
        WorkflowSaveStatus.SetFont("cRed")
        return
    }

    ; Register hotkey/hotstring
    RegisterSequenceTriggers(saved.SeqName)

    RefreshSeqLV()
    g_CurrentSequenceSteps := []
    RefreshStepsLV()
    SeqNameEdit.Value := ""
    SeqHotkeyEdit.Value := ""
    SeqHotstringEdit.Value := ""
    StatusBar.SetText("Saved: " . saved.SeqName . " @ " . speedText)
    WorkflowSaveStatus.Text := "Saved: " . saved.SeqName
    WorkflowSaveStatus.SetFont("c008000")

    triggerInfo := ""
    if saved.SeqHotkey != ""
        triggerInfo .= "`nHotkey: " . saved.SeqHotkey
    if saved.SeqHotstring != ""
        triggerInfo .= "`nHotstring: " . saved.SeqHotstring

    ShowNotificationBasic("Sequence Saved", saved.SeqName . " with " . steps.Length . " steps @ " . speedText . triggerInfo, 3000, "success")
}

RefreshSeqLV() {
    global g_Sequences, SeqLV
    SeqLV.Delete()
    for name, seq in g_Sequences {
        speed := seq.Has("speed") ? seq["speed"] . "x" : "1x"
        hotkey := seq.Has("hotkey") ? seq["hotkey"] : ""
        hotstring := seq.Has("hotstring") ? seq["hotstring"] : ""
        SeqLV.Add(, name, seq["steps"].Length, speed, hotkey, hotstring)
    }
}

LoadSeq(*) {
    global g_Sequences, g_CurrentSequenceSteps, SeqLV, SeqNameEdit, SeqHotkeyEdit, SeqHotstringEdit
    row := SeqLV.GetNext(0, "Focused")
    if row = 0
        return
    name := SeqLV.GetText(row, 1)
    if !g_Sequences.Has(name)
        return
    LoadWorkflowByName(name)
}

LoadWorkflowByName(name) {
    global g_Sequences, g_CurrentSequenceSteps, SeqNameEdit, SeqHotkeyEdit, SeqHotstringEdit, g_LoadingWorkflow, WorkflowSaveStatus
    if !g_Sequences.Has(name)
        return false
    g_LoadingWorkflow := true
    try {
        g_CurrentSequenceSteps := CloneWorkflowSteps(g_Sequences[name]["steps"])
        for step in g_CurrentSequenceSteps
            if !step.Has("enabled")
                step["enabled"] := true
        SeqNameEdit.Value := name
        speed := g_Sequences[name].Has("speed") ? g_Sequences[name]["speed"] : 1.0
        SetSpeedDropdown(speed)
        seq := g_Sequences[name]
        SeqHotkeyEdit.Value := seq.Has("hotkey") ? seq["hotkey"] : ""
        SeqHotstringEdit.Value := seq.Has("hotstring") ? seq["hotstring"] : ""
        RefreshStepsLV()
        WorkflowSaveStatus.Text := "Loaded: " . name . " (changes autosave)"
        WorkflowSaveStatus.SetFont("cBlue")
    } finally {
        g_LoadingWorkflow := false
    }
    return true
}

; ═══════════════════════════════════════════════════════════════════════════════
; HOTKEY/HOTSTRING TRIGGER REGISTRATION
; ═══════════════════════════════════════════════════════════════════════════════

MawEncode(value) {
    value := String(value)
    value := StrReplace(value, "%", "%25")
    value := StrReplace(value, "|", "%7C")
    value := StrReplace(value, "`r", "%0D")
    value := StrReplace(value, "`n", "%0A")
    value := StrReplace(value, "=", "%3D")
    return value
}

MawDecode(value) {
    value := StrReplace(value, "%7C", "|")
    value := StrReplace(value, "%0D", "`r")
    value := StrReplace(value, "%0A", "`n")
    value := StrReplace(value, "%3D", "=")
    value := StrReplace(value, "%25", "%")
    return value
}

ExportWorkflow(*) {
    global SeqNameEdit, g_CurrentSequenceSteps
    name := Trim(SeqNameEdit.Value)
    if name = "" {
        MsgBox("Enter a workflow name in Step 1 before exporting.", "Export Workflow", "Icon!")
        return false
    }
    if g_CurrentSequenceSteps.Length = 0 {
        MsgBox("Add at least one step before exporting.", "Export Workflow", "Icon!")
        return false
    }
    return ExportWorkflowData(name, BuildCurrentWorkflowData())
}

ExportWorkflowFromMain(*) {
    global SeqLV
    row := SeqLV.GetNext(0, "Focused")
    if row > 0
        return ExportWorkflowByName(SeqLV.GetText(row, 1))
    return ExportWorkflow()
}

ExportWorkflowByName(name) {
    global g_Sequences
    if !g_Sequences.Has(name)
        return false
    return ExportWorkflowData(name, g_Sequences[name])
}

ExportWorkflowData(name, seq) {
    selectedFile := FileSelect("S", name . ".maw", "Export Workflow", "Workflow Files (*.maw)")
    if selectedFile = ""
        return false
    if !RegExMatch(selectedFile, "i)\.maw$")
        selectedFile .= ".maw"

    output := "[WORKFLOW]`r`n"
    output .= "format=2`r`n"
    output .= "name=" . MawEncode(name) . "`r`n"
    output .= "speed=" . (seq.Has("speed") ? seq["speed"] : 1.0) . "`r`n"
    output .= "hotkey=" . MawEncode(seq.Has("hotkey") ? seq["hotkey"] : "") . "`r`n"
    output .= "hotstring=" . MawEncode(seq.Has("hotstring") ? seq["hotstring"] : "") . "`r`n"
    output .= "`r`n[STEPS]`r`n"

    for index, step in seq["steps"] {
        fs := step.Has("failsafe") ? NormalizeStepFailsafe(step["failsafe"]) : Map()
        fsText := fs.Count > 0 ? SerializeFailsafe(fs) : ""
        output .= index . "|"
            . MawEncode(step.Has("action") ? step["action"] : "") . "|"
            . MawEncode(step.Has("target") ? step["target"] : "") . "|"
            . MawEncode(step.Has("param") ? step["param"] : "") . "|"
            . (step.Has("enabled") ? Integer(step["enabled"]) : 1) . "|"
            . MawEncode(fsText) . "|"
            . MawEncode(step.Has("qualPattern") ? step["qualPattern"] : "") . "|"
            . MawEncode(step.Has("qualWindow") ? step["qualWindow"] : "") . "`r`n"
    }
    output .= "`r`n[END]`r`n"

    try {
        if FileExist(selectedFile)
            FileDelete(selectedFile)
        FileAppend(output, selectedFile, "UTF-8")
        ShowStatus("Exported workflow: " . name, "ok")
        MsgBox("Workflow exported successfully.`n`n" . selectedFile, "Export Complete", "Iconi")
        return true
    } catch as err {
        LogErrorToFile(err, "caught", "Export workflow " . name)
        MsgBox("Workflow export failed.`n`n" . err.Message, "Export Failed", "Iconx")
        return false
    }
}

ShowMawWriter(*) {
    global MainGui, SeqNameEdit, SpeedDD, SeqHotkeyEdit, SeqHotstringEdit, g_CurrentSequenceSteps
    writer := Gui("+Owner" . MainGui.Hwnd . " +Resize +MinSize820x600", "Build / Write Portable .maw Workflow")
    writer.SetFont("s9", "Segoe UI")
    state := Map("steps", CloneWorkflowSteps(g_CurrentSequenceSteps))

    writer.Add("GroupBox", "x12 y10 w895 h75", "1. Portable Workflow Metadata")
    writer.Add("Text", "x25 y35", "Name:")
    nameEdit := writer.Add("Edit", "x70 y32 w200", Trim(SeqNameEdit.Value))
    writer.Add("Text", "x285 y35", "Speed:")
    writerSpeedDD := writer.Add("DropDownList", "x330 y32 w75", ["0.25x", "0.5x", "0.75x", "1x", "1.5x", "2x", "3x"])
    writerSpeedDD.Text := SpeedDD.Text != "" ? SpeedDD.Text : "1x"
    writer.Add("Text", "x420 y35", "Hotkey:")
    hotkeyEdit := writer.Add("Edit", "x470 y32 w100", SeqHotkeyEdit.Value)
    writer.Add("Text", "x585 y35", "Hotstring:")
    hotstringEdit := writer.Add("Edit", "x650 y32 w110", SeqHotstringEdit.Value)
    writer.Add("Text", "x25 y62 w850 cGray", "This builder writes every action supported by v7. The .maw file remains separate until you import it or send it to the editor.")

    writer.Add("GroupBox", "x12 y95 w895 h170", "2. Add or Update a Step")
    writer.Add("Text", "x25 y120", "Action:")
    writerActionDD := writer.Add("DropDownList", "x80 y117 w190", GetWorkflowActionNames())
    writerActionDD.Choose(1)
    targetLabel := writer.Add("Text", "x25 y155 w240", "Position:")
    targetEdit := writer.Add("Edit", "x25 y174 w270")
    paramLabel := writer.Add("Text", "x310 y155 w270", "Click count:")
    writerParamEdit := writer.Add("Edit", "x310 y174 w280")
    enabledCheck := writer.Add("CheckBox", "x25 y211 Checked", "Step enabled")
    addBtn := writer.Add("Button", "x310 y208 w90 h28 Default", "Add Step")
    updateBtn := writer.Add("Button", "x410 y208 w120 h28", "Update Selected")
    clearBtn := writer.Add("Button", "x540 y208 w50 h28", "Clear")
    helpEdit := writer.Add("Edit", "x610 y116 w282 h125 ReadOnly Multi VScroll")

    writer.Add("GroupBox", "x12 y275 w895 h255", "3. Confirm Execution Order")
    stepLV := writer.Add("ListView", "x25 y298 w760 h215 Grid NoSortHdr", ["#", "On", "Action", "Target", "Parameter"])
    stepLV.ModifyCol(1, 35)
    stepLV.ModifyCol(2, 40)
    stepLV.ModifyCol(3, 165)
    stepLV.ModifyCol(4, 210)
    stepLV.ModifyCol(5, 300)
    writer.Add("Button", "x798 y298 w90 h26", "Move Up").OnEvent("Click", (*) => MawWriterMoveStep(state, stepLV, -1))
    writer.Add("Button", "x798 y330 w90 h26", "Move Down").OnEvent("Click", (*) => MawWriterMoveStep(state, stepLV, 1))
    writer.Add("Button", "x798 y372 w90 h26", "Edit Step").OnEvent("Click", (*) => MawWriterLoadSelectedStep(state, stepLV, writerActionDD, targetLabel, targetEdit, paramLabel, writerParamEdit, enabledCheck, helpEdit))
    writer.Add("Button", "x798 y404 w90 h26", "Delete").OnEvent("Click", (*) => MawWriterDeleteStep(state, stepLV))
    writer.Add("Button", "x798 y446 w90 h26", "Validate All").OnEvent("Click", (*) => MawWriterValidateAll(state))

    writer.Add("GroupBox", "x12 y540 w895 h62", "4. Write, Open, or Continue Editing")
    writer.Add("Button", "x25 y558 w100 h30", "Open .maw").OnEvent("Click", (*) => MawWriterOpenFile(state, stepLV, nameEdit, writerSpeedDD, hotkeyEdit, hotstringEdit))
    writer.Add("Button", "x135 y558 w110 h30 cGreen", "Save .maw").OnEvent("Click", (*) => MawWriterSaveFile(state, nameEdit, writerSpeedDD, hotkeyEdit, hotstringEdit))
    writer.Add("Button", "x255 y558 w130 h30 cBlue", "Send to Editor").OnEvent("Click", (*) => MawWriterSendToEditor(state, nameEdit, writerSpeedDD, hotkeyEdit, hotstringEdit, writer))
    writer.Add("Button", "x397 y558 w110 h30", "Action Guide").OnEvent("Click", ShowInstructionsFile)
    writer.Add("Button", "x797 y558 w90 h30", "Close").OnEvent("Click", (*) => writer.Destroy())

    writerActionDD.OnEvent("Change", (*) => MawWriterActionChanged(writerActionDD, targetLabel, targetEdit, paramLabel, writerParamEdit, helpEdit))
    addBtn.OnEvent("Click", (*) => MawWriterAddStep(state, stepLV, writerActionDD, targetEdit, writerParamEdit, enabledCheck))
    updateBtn.OnEvent("Click", (*) => MawWriterUpdateStep(state, stepLV, writerActionDD, targetEdit, writerParamEdit, enabledCheck))
    clearBtn.OnEvent("Click", (*) => (targetEdit.Value := "", writerParamEdit.Value := "", enabledCheck.Value := 1))
    stepLV.OnEvent("DoubleClick", (*) => MawWriterLoadSelectedStep(state, stepLV, writerActionDD, targetLabel, targetEdit, paramLabel, writerParamEdit, enabledCheck, helpEdit))
    MawWriterActionChanged(writerActionDD, targetLabel, targetEdit, paramLabel, writerParamEdit, helpEdit)
    MawWriterRefreshLV(state, stepLV)
    writer.Show("w920 h615")
}

MawWriterActionChanged(actionDD, targetLabel, targetEdit, paramLabel, paramEdit, helpEdit) {
    spec := GetWorkflowActionSpec(actionDD.Text)
    targetLabel.Text := spec["targetUsed"] ? spec["targetLabel"] . " — " . spec["targetHint"] : "Target — not used"
    paramLabel.Text := spec["paramUsed"] ? spec["paramLabel"] . " — " . spec["paramHint"] : "Parameter — not used"
    targetEdit.Enabled := spec["targetUsed"]
    paramEdit.Enabled := spec["paramUsed"]
    if !spec["targetUsed"]
        targetEdit.Value := ""
    if !spec["paramUsed"]
        paramEdit.Value := ""
    helpEdit.Value := actionDD.Text . "`r`n`r`n" . spec["help"] . (spec["example"] != "" ? "`r`n`r`nExample: " . spec["example"] : "")
}

MawWriterRefreshLV(state, lv, selectRow := 0) {
    lv.Delete()
    for index, step in state["steps"]
        lv.Add(, index, step.Has("enabled") && !step["enabled"] ? "No" : "Yes", step["action"], step["target"], step["param"])
    if selectRow > 0 && selectRow <= state["steps"].Length
        lv.Modify(selectRow, "Select Focus Vis")
}

MawWriterSelectedRow(lv) {
    return lv.GetNext(0, "Focused")
}

MawWriterAddStep(state, lv, actionDD, targetEdit, paramEdit, enabledCheck) {
    action := actionDD.Text
    target := targetEdit.Value
    param := paramEdit.Value
    if !ShowParameterValidation(action, target, param)
        return
    state["steps"].Push(Map("action", action, "target", target, "param", param, "enabled", enabledCheck.Value = 1))
    MawWriterRefreshLV(state, lv, state["steps"].Length)
}

MawWriterUpdateStep(state, lv, actionDD, targetEdit, paramEdit, enabledCheck) {
    row := MawWriterSelectedRow(lv)
    if row = 0 || row > state["steps"].Length {
        MsgBox("Select a step to update.", "MAW Writer", "Icon!")
        return
    }
    action := actionDD.Text
    if !ShowParameterValidation(action, targetEdit.Value, paramEdit.Value)
        return
    oldStep := state["steps"][row]
    oldStep["action"] := action
    oldStep["target"] := targetEdit.Value
    oldStep["param"] := paramEdit.Value
    oldStep["enabled"] := enabledCheck.Value = 1
    MawWriterRefreshLV(state, lv, row)
}

MawWriterLoadSelectedStep(state, lv, actionDD, targetLabel, targetEdit, paramLabel, paramEdit, enabledCheck, helpEdit) {
    row := MawWriterSelectedRow(lv)
    if row = 0 || row > state["steps"].Length
        return
    step := state["steps"][row]
    DDL_FindAndSelect(actionDD, step["action"])
    MawWriterActionChanged(actionDD, targetLabel, targetEdit, paramLabel, paramEdit, helpEdit)
    targetEdit.Value := step["target"]
    paramEdit.Value := step["param"]
    enabledCheck.Value := step.Has("enabled") ? step["enabled"] : 1
}

MawWriterDeleteStep(state, lv) {
    row := MawWriterSelectedRow(lv)
    if row = 0 || row > state["steps"].Length
        return
    state["steps"].RemoveAt(row)
    MawWriterRefreshLV(state, lv, Min(row, state["steps"].Length))
}

MawWriterMoveStep(state, lv, direction) {
    row := MawWriterSelectedRow(lv)
    destination := row + direction
    if row = 0 || destination < 1 || destination > state["steps"].Length
        return
    temp := state["steps"][row]
    state["steps"][row] := state["steps"][destination]
    state["steps"][destination] := temp
    MawWriterRefreshLV(state, lv, destination)
}

MawWriterValidateAll(state) {
    errors := []
    for index, step in state["steps"] {
        for message in ValidateStepParameters(step["action"], step["target"], step["param"])
            errors.Push("Step " . index . " (" . step["action"] . "): " . message)
    }
    if errors.Length = 0 {
        MsgBox("All " . state["steps"].Length . " steps passed validation.", "MAW Validation", "Iconi")
        return true
    }
    report := ""
    for message in errors
        report .= "• " . message . "`n"
    MsgBox(report, "MAW Validation Issues", "Icon!")
    return false
}

MawWriterBuildSequence(state, speedDD, hotkeyEdit, hotstringEdit) {
    speedText := StrReplace(speedDD.Text != "" ? speedDD.Text : "1x", "x", "")
    seq := Map("steps", CloneWorkflowSteps(state["steps"]), "speed", IsNumber(speedText) ? Float(speedText) : 1.0)
    if Trim(hotkeyEdit.Value) != ""
        seq["hotkey"] := Trim(hotkeyEdit.Value)
    if Trim(hotstringEdit.Value) != ""
        seq["hotstring"] := Trim(hotstringEdit.Value)
    return seq
}

MawWriterSaveFile(state, nameEdit, speedDD, hotkeyEdit, hotstringEdit) {
    name := Trim(nameEdit.Value)
    if name = "" || state["steps"].Length = 0 {
        MsgBox("Enter a workflow name and add at least one step.", "MAW Writer", "Icon!")
        return false
    }
    return ExportWorkflowData(name, MawWriterBuildSequence(state, speedDD, hotkeyEdit, hotstringEdit))
}

MawWriterSendToEditor(state, nameEdit, writerSpeedControl, hotkeyEdit, hotstringEdit, writer) {
    global g_CurrentSequenceSteps, SeqNameEdit, SpeedDD, SeqHotkeyEdit, SeqHotstringEdit, g_LoadingWorkflow, WorkflowSaveStatus
    name := Trim(nameEdit.Value)
    if name = "" || state["steps"].Length = 0 {
        MsgBox("Enter a workflow name and add at least one step.", "MAW Writer", "Icon!")
        return
    }
    g_LoadingWorkflow := true
    try {
        g_CurrentSequenceSteps := CloneWorkflowSteps(state["steps"])
        SeqNameEdit.Value := name
        SetSpeedDropdown(Float(StrReplace(writerSpeedControl.Text, "x", "")))
        SeqHotkeyEdit.Value := hotkeyEdit.Value
        SeqHotstringEdit.Value := hotstringEdit.Value
        RefreshStepsLV()
        WorkflowSaveStatus.Text := "Loaded from .maw writer: " . name . " — click Save Now to add it to the library."
        WorkflowSaveStatus.SetFont("cBlue")
    } finally {
        g_LoadingWorkflow := false
    }
    writer.Destroy()
    MainGui.Show()
}

MawWriterOpenFile(state, lv, nameEdit, speedDD, hotkeyEdit, hotstringEdit) {
    selectedFile := FileSelect(, , "Open Portable Workflow", "Workflow Files (*.maw)")
    if selectedFile = ""
        return
    if !ReadMawWorkflowFile(selectedFile, &workflowName, &seqData, &errorMessage) {
        MsgBox(errorMessage, "Open .maw Failed", "Iconx")
        return
    }
    state["steps"] := CloneWorkflowSteps(seqData["steps"])
    nameEdit.Value := workflowName
    speedDD.Text := (seqData.Has("speed") ? seqData["speed"] : 1.0) . "x"
    hotkeyEdit.Value := seqData.Has("hotkey") ? seqData["hotkey"] : ""
    hotstringEdit.Value := seqData.Has("hotstring") ? seqData["hotstring"] : ""
    MawWriterRefreshLV(state, lv)
}

ReadMawWorkflowFile(selectedFile, &workflowName, &seqData, &errorMessage) {
    workflowName := ""
    seqData := Map()
    errorMessage := ""
    try content := FileRead(selectedFile, "UTF-8")
    catch as err {
        errorMessage := "Could not read the selected file.`n`n" . err.Message
        return false
    }
    section := ""
    formatVersion := 1
    speed := 1.0
    hotkey := ""
    hotstring := ""
    steps := []
    for rawLine in StrSplit(content, "`n") {
        rawLine := StrReplace(rawLine, "`r")
        marker := Trim(rawLine)
        if marker = "" || SubStr(marker, 1, 1) = ";"
            continue
        if marker = "[WORKFLOW]" {
            section := "workflow"
            continue
        } else if marker = "[STEPS]" {
            section := "steps"
            continue
        } else if marker = "[END]" {
            break
        }
        if section = "workflow" {
            equalsPos := InStr(rawLine, "=")
            if !equalsPos
                continue
            key := Trim(SubStr(rawLine, 1, equalsPos - 1))
            value := SubStr(rawLine, equalsPos + 1)
            if key = "format"
                formatVersion := IsNumber(value) ? Integer(value) : 1
            else if key = "name"
                workflowName := formatVersion >= 2 ? MawDecode(value) : value
            else if key = "speed"
                speed := IsNumber(value) ? Float(value) : 1.0
            else if key = "hotkey"
                hotkey := formatVersion >= 2 ? MawDecode(value) : value
            else if key = "hotstring"
                hotstring := formatVersion >= 2 ? MawDecode(value) : value
        } else if section = "steps" {
            parts := StrSplit(rawLine, "|")
            if parts.Length < 4
                continue
            step := Map(
                "action", formatVersion >= 2 ? MawDecode(parts[2]) : parts[2],
                "target", formatVersion >= 2 ? MawDecode(parts[3]) : parts[3],
                "param", formatVersion >= 2 ? MawDecode(parts[4]) : parts[4],
                "enabled", parts.Length >= 5 && IsNumber(parts[5]) ? Integer(parts[5]) != 0 : true
            )
            if formatVersion >= 2 && parts.Length >= 6 {
                fsText := MawDecode(parts[6])
                if fsText != ""
                    step["failsafe"] := DeserializeFailsafe(fsText)
                if parts.Length >= 7 && MawDecode(parts[7]) != ""
                    step["qualPattern"] := MawDecode(parts[7])
                if parts.Length >= 8 && MawDecode(parts[8]) != ""
                    step["qualWindow"] := MawDecode(parts[8])
            }
            steps.Push(step)
        }
    }
    workflowName := Trim(workflowName)
    if workflowName = "" || steps.Length = 0 {
        errorMessage := "The file does not contain a workflow name and at least one valid step."
        return false
    }
    seqData := Map("steps", steps, "speed", speed)
    if hotkey != ""
        seqData["hotkey"] := hotkey
    if hotstring != ""
        seqData["hotstring"] := hotstring
    return true
}

ImportWorkflow(*) {
    global g_Sequences
    selectedFile := FileSelect(, , "Import Workflow", "Workflow Files (*.maw)")
    if selectedFile = ""
        return ""

    try content := FileRead(selectedFile, "UTF-8")
    catch as err {
        LogErrorToFile(err, "caught", "Read imported workflow")
        MsgBox("Could not read the selected workflow.`n`n" . err.Message, "Import Failed", "Iconx")
        return ""
    }

    section := ""
    formatVersion := 1
    workflowName := ""
    speed := 1.0
    hotkey := ""
    hotstring := ""
    steps := []

    for rawLine in StrSplit(content, "`n") {
        rawLine := StrReplace(rawLine, "`r")
        marker := Trim(rawLine)
        if marker = "" || SubStr(marker, 1, 1) = ";"
            continue
        if marker = "[WORKFLOW]" {
            section := "workflow"
            continue
        }
        if marker = "[STEPS]" {
            section := "steps"
            continue
        }
        if marker = "[END]"
            break

        if section = "workflow" {
            equalsPos := InStr(rawLine, "=")
            if !equalsPos
                continue
            key := Trim(SubStr(rawLine, 1, equalsPos - 1))
            value := SubStr(rawLine, equalsPos + 1)
            if key = "format"
                formatVersion := IsNumber(value) ? Integer(value) : 1
            else if key = "name"
                workflowName := formatVersion >= 2 ? MawDecode(value) : value
            else if key = "speed"
                speed := IsNumber(value) ? Float(value) : 1.0
            else if key = "hotkey"
                hotkey := formatVersion >= 2 ? MawDecode(value) : value
            else if key = "hotstring"
                hotstring := formatVersion >= 2 ? MawDecode(value) : value
        } else if section = "steps" {
            parts := StrSplit(rawLine, "|")
            if parts.Length < 4
                continue
            step := Map(
                "action", formatVersion >= 2 ? MawDecode(parts[2]) : parts[2],
                "target", formatVersion >= 2 ? MawDecode(parts[3]) : parts[3],
                "param", formatVersion >= 2 ? MawDecode(parts[4]) : parts[4],
                "enabled", parts.Length >= 5 && IsNumber(parts[5]) ? Integer(parts[5]) != 0 : true
            )
            if formatVersion >= 2 && parts.Length >= 6 {
                fsText := MawDecode(parts[6])
                if fsText != ""
                    step["failsafe"] := DeserializeFailsafe(fsText)
                if parts.Length >= 7 && MawDecode(parts[7]) != ""
                    step["qualPattern"] := MawDecode(parts[7])
                if parts.Length >= 8 && MawDecode(parts[8]) != ""
                    step["qualWindow"] := MawDecode(parts[8])
            } else {
                step["failsafe"] := Map()
            }
            steps.Push(step)
        }
    }

    if Trim(workflowName) = "" || steps.Length = 0 {
        MsgBox("This is not a valid .maw workflow: a name and at least one step are required.", "Import Failed", "Icon!")
        return ""
    }
    workflowName := Trim(workflowName)
    existed := g_Sequences.Has(workflowName)
    oldSequence := existed ? g_Sequences[workflowName] : ""
    if existed && MsgBox("Workflow '" . workflowName . "' already exists.`n`nOverwrite it?", "Workflow Exists", "YesNo Icon!") != "Yes"
        return ""

    seqData := Map("steps", steps, "speed", speed)
    if hotkey != ""
        seqData["hotkey"] := hotkey
    if hotstring != ""
        seqData["hotstring"] := hotstring
    if existed
        UnregisterSequenceTriggers(workflowName)
    g_Sequences[workflowName] := seqData

    if !SaveSequences(true) {
        if existed
            g_Sequences[workflowName] := oldSequence
        else
            g_Sequences.Delete(workflowName)
        if existed
            RegisterSequenceTriggers(workflowName)
        return ""
    }

    RegisterSequenceTriggers(workflowName)
    RefreshSeqLV()
    RefreshHKDropdowns()
    LoadWorkflowByName(workflowName)
    ShowStatus("Imported workflow: " . workflowName, "ok")
    MsgBox("Workflow imported successfully.`n`nName: " . workflowName . "`nSteps: " . steps.Length, "Import Complete", "Iconi")
    return workflowName
}

WorkflowManagerImport(lv) {
    importedName := ImportWorkflow()
    if importedName != ""
        RefreshWorkflowManagerLV(lv)
}

WorkflowManagerExport(lv) {
    name := WorkflowManagerSelectedName(lv)
    if name = "" {
        MsgBox("Select a workflow to export.", "Export Workflow", "Icon!")
        return
    }
    ExportWorkflowByName(name)
}

ShowWorkflowManager(*) {
    manager := Gui("+Resize +MinSize900x440", "Saved Workflow Manager")
    manager.SetFont("s9", "Segoe UI")
    manager.Add("Text", "x15 y12 w700", "All workflows - scroll the list, double-click to load, or use the buttons below.")
    managerLV := manager.Add("ListView", "x15 y35 w870 h485 Grid NoSortHdr", ["Name", "Steps", "Speed", "Hotkey", "Hotstring", "First action"])
    managerLV.ModifyCol(1, 300)
    managerLV.ModifyCol(2, 65)
    managerLV.ModifyCol(3, 70)
    managerLV.ModifyCol(4, 100)
    managerLV.ModifyCol(5, 110)
    managerLV.ModifyCol(6, 190)
    managerLV.Opt("-LV0x2000 +0x00200000 +LV0x20")

    loadBtn := manager.Add("Button", "x15 y530 w80 h28 Default", "Load/Edit")
    runBtn := manager.Add("Button", "x105 y530 w70 h28", "Run")
    simBtn := manager.Add("Button", "x185 y530 w80 h28", "Simulate")
    deleteBtn := manager.Add("Button", "x275 y530 w70 h28", "Delete")
    refreshBtn := manager.Add("Button", "x355 y530 w70 h28", "Refresh")
    guideBtn := manager.Add("Button", "x435 y530 w90 h28", "Action Guide")
    importBtn := manager.Add("Button", "x535 y530 w80 h28", "Import .maw")
    exportBtn := manager.Add("Button", "x625 y530 w80 h28", "Export .maw")
    closeBtn := manager.Add("Button", "x805 y530 w80 h28", "Close")

    loadBtn.OnEvent("Click", (*) => WorkflowManagerLoad(manager, managerLV))
    runBtn.OnEvent("Click", (*) => WorkflowManagerRun(managerLV, false))
    simBtn.OnEvent("Click", (*) => WorkflowManagerRun(managerLV, true))
    deleteBtn.OnEvent("Click", (*) => WorkflowManagerDelete(managerLV))
    refreshBtn.OnEvent("Click", (*) => RefreshWorkflowManagerLV(managerLV))
    guideBtn.OnEvent("Click", ShowInstructionsFile)
    importBtn.OnEvent("Click", (*) => WorkflowManagerImport(managerLV))
    exportBtn.OnEvent("Click", (*) => WorkflowManagerExport(managerLV))
    closeBtn.OnEvent("Click", (*) => manager.Destroy())
    managerLV.OnEvent("DoubleClick", (*) => WorkflowManagerLoad(manager, managerLV))
    manager.OnEvent("Size", WorkflowManagerResize.Bind(managerLV, loadBtn, runBtn, simBtn, deleteBtn, refreshBtn, guideBtn, importBtn, exportBtn, closeBtn))

    RefreshWorkflowManagerLV(managerLV)
    manager.Show("w900 h575")
}

WorkflowManagerResize(lv, loadBtn, runBtn, simBtn, deleteBtn, refreshBtn, guideBtn, importBtn, exportBtn, closeBtn, gui, minMax, w, h) {
    if minMax = -1
        return
    lv.Move(, , Max(650, w - 30), Max(300, h - 90))
    buttonY := h - 38
    for btn in [loadBtn, runBtn, simBtn, deleteBtn, refreshBtn, guideBtn, importBtn, exportBtn]
        btn.Move(, buttonY)
    closeBtn.Move(w - 95, buttonY)
}

RefreshWorkflowManagerLV(lv) {
    global g_Sequences
    lv.Delete()
    for name, seq in g_Sequences {
        speed := seq.Has("speed") ? seq["speed"] . "x" : "1x"
        hotkey := seq.Has("hotkey") ? seq["hotkey"] : ""
        hotstring := seq.Has("hotstring") ? seq["hotstring"] : ""
        firstAction := seq["steps"].Length > 0 ? seq["steps"][1]["action"] : "(empty)"
        lv.Add(, name, seq["steps"].Length, speed, hotkey, hotstring, firstAction)
    }
}

WorkflowManagerSelectedName(lv) {
    row := lv.GetNext(0, "Focused")
    return row > 0 ? lv.GetText(row, 1) : ""
}

WorkflowManagerLoad(manager, lv) {
    name := WorkflowManagerSelectedName(lv)
    if name = ""
        return
    if LoadWorkflowByName(name) {
        manager.Destroy()
        MainGui.Show()
    }
}

WorkflowManagerRun(lv, simulate := false) {
    global g_Sequences, g_AbortSequence
    name := WorkflowManagerSelectedName(lv)
    if name = "" || !g_Sequences.Has(name)
        return
    g_AbortSequence := false
    seq := g_Sequences[name]
    speed := seq.Has("speed") ? seq["speed"] : 1.0
    if simulate
        SimulateSequence(seq["steps"], speed)
    else
        ExecuteSequenceVerified(seq["steps"], speed)
}

WorkflowManagerDelete(lv) {
    global g_Sequences
    name := WorkflowManagerSelectedName(lv)
    if name = ""
        return
    if MsgBoxTop("Delete '" . name . "'?", "Confirm", "YesNo") != "Yes"
        return
    UnregisterSequenceTriggers(name)
    deletedSequence := g_Sequences[name]
    g_Sequences.Delete(name)
    if SaveSequences(true) {
        RefreshSeqLV()
        RefreshWorkflowManagerLV(lv)
        RefreshHKDropdowns()
    } else {
        g_Sequences[name] := deletedSequence
        RegisterSequenceTriggers(name)
        RefreshSeqLV()
        RefreshWorkflowManagerLV(lv)
    }
}

RegisterSequenceTriggers(seqName) {
    global g_Sequences, g_SequenceHotkeys, g_SequenceHotstrings

    if !g_Sequences.Has(seqName)
        return

    seq := g_Sequences[seqName]

    ; Unregister old triggers for this sequence first
    UnregisterSequenceTriggers(seqName)

    ; Register hotkey
    if seq.Has("hotkey") && seq["hotkey"] != "" {
        hk := seq["hotkey"]
        try {
            Hotkey(hk, (*) => ExecuteSequenceByHotkey(seqName))
            g_SequenceHotkeys[hk] := seqName
            g_RegisteredHotkeys.Push(hk)
        } catch as err {
            ShowNotificationBasic("Hotkey Error", "Failed to register: " . hk . "`n" . err.Message, 5000, "error")
        }
    }

    ; Register hotstring
    if seq.Has("hotstring") && seq["hotstring"] != "" {
        hs := seq["hotstring"]
        try {
            ; Hotstrings with auto-replace (backspace trigger text)
            Hotstring(hs, (*) => ExecuteSequenceByHotstring(seqName, StrLen(hs) - 2))
            g_SequenceHotstrings[hs] := seqName
            g_RegisteredHotstrings.Push(hs)
        } catch as err {
            ShowNotificationBasic("Hotstring Error", "Failed to register: " . hs . "`n" . err.Message, 5000, "error")
        }
    }
}

UnregisterSequenceTriggers(seqName) {
    global g_Sequences, g_SequenceHotkeys, g_SequenceHotstrings

    if !g_Sequences.Has(seqName)
        return

    seq := g_Sequences[seqName]

    ; Unregister hotkey
    if seq.Has("hotkey") && seq["hotkey"] != "" {
        hk := seq["hotkey"]
        try {
            Hotkey(hk, "Off")
            g_SequenceHotkeys.Delete(hk)
        }
    }

    ; Unregister hotstring
    if seq.Has("hotstring") && seq["hotstring"] != "" {
        hs := seq["hotstring"]
        try {
            Hotstring(hs, "Off")
            g_SequenceHotstrings.Delete(hs)
        }
    }
}

ExecuteSequenceByHotkey(seqName) {
    global g_Sequences

    if !g_Sequences.Has(seqName) {
        ShowStatus("Sequence not found: " . seqName, "fail")
        return
    }

    seq := g_Sequences[seqName]
    speed := seq.Has("speed") ? seq["speed"] : 1.0

    ShowStatus("Running sequence: " . seqName, "info")
    ExecuteSequenceVerified(seq["steps"], speed)
}

ExecuteSequenceByHotstring(seqName, triggerLength) {
    global g_Sequences

    ; Delete the trigger text
    if triggerLength > 0 {
        Send("{Backspace " . triggerLength . "}")
        Sleep(50)
    }

    if !g_Sequences.Has(seqName) {
        ShowStatus("Sequence not found: " . seqName, "fail")
        return
    }

    seq := g_Sequences[seqName]
    speed := seq.Has("speed") ? seq["speed"] : 1.0

    ShowStatus("Running sequence: " . seqName, "info")
    ExecuteSequenceVerified(seq["steps"], speed)
}

RegisterAllSequenceTriggers() {
    global g_Sequences

    for seqName, seq in g_Sequences {
        RegisterSequenceTriggers(seqName)
    }
}

; Helper to set speed dropdown to match value
SetSpeedDropdown(speed) {
    global SpeedDD
    speedOptions := ["0.25x", "0.5x", "0.75x", "1x", "1.5x", "2x", "3x"]
    speedValues := [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0]

    ; Find closest match
    bestIdx := 4  ; Default to 1x
    for i, v in speedValues {
        if Abs(v - speed) < 0.01 {
            bestIdx := i
            break
        }
    }
    SpeedDD.Choose(bestIdx)
}

; Get current speed multiplier from dropdown
GetSpeedMultiplier() {
    global SpeedDD
    speedText := SpeedDD.Text
    return Float(StrReplace(speedText, "x", ""))
}

DelSeq(*) {
    global g_Sequences, SeqLV
    row := SeqLV.GetNext(0, "Focused")
    if row = 0
        return
    name := SeqLV.GetText(row, 1)
    if MsgBoxTop("Delete '" . name . "'?", "Confirm", "YesNo") = "Yes" {
        ; Unregister hotkey/hotstring before deleting
        UnregisterSequenceTriggers(name)
        deletedSequence := g_Sequences[name]
        g_Sequences.Delete(name)
        if SaveSequences(true) {
            RefreshSeqLV()
            RefreshHKDropdowns()
        } else {
            g_Sequences[name] := deletedSequence
            RegisterSequenceTriggers(name)
            RefreshSeqLV()
        }
    }
}

RunSeq(*) {
    global g_Sequences, SeqLV, g_AbortSequence
    row := SeqLV.GetNext(0, "Focused")
    if row = 0
        return
    name := SeqLV.GetText(row, 1)
    if g_Sequences.Has(name) {
        g_AbortSequence := false
        speed := g_Sequences[name].Has("speed") ? g_Sequences[name]["speed"] : 1.0
        ExecuteSequenceVerified(g_Sequences[name]["steps"], speed)
    }
}

ToggleStepThrough(*) {
    global g_StepThroughMode
    saved := MainGui.Submit(false)
    g_StepThroughMode := saved.StepThroughCheck

    if g_StepThroughMode {
        ShowStatus("Step-Through Mode ON - Press Tab to advance each step", "ok")
        ShowNotificationBasic("Step-Through Mode", "Enabled: Press Tab to advance to next step`nESC to abort sequence", 3000, "info")
    } else {
        ShowStatus("Step-Through Mode OFF - Normal speed execution", "ok")
    }
}

TestSeq(*) {
    global g_CurrentSequenceSteps, g_AbortSequence
    if g_CurrentSequenceSteps.Length = 0 {
        MsgBoxTop("No steps!", "Empty")
        return
    }
    g_AbortSequence := false
    speed := GetSpeedMultiplier()
    ExecuteSequenceVerified(g_CurrentSequenceSteps, speed)
}

; Simulate current steps without executing - show tooltips at each location
SimulateSeq(*) {
    global g_CurrentSequenceSteps, g_AbortSequence
    if g_CurrentSequenceSteps.Length = 0 {
        MsgBoxTop("No steps!", "Empty")
        return
    }
    g_AbortSequence := false
    speed := GetSpeedMultiplier()
    SimulateSequence(g_CurrentSequenceSteps, speed)
}

; Simulate saved sequence
SimulateSavedSeq(*) {
    global g_Sequences, SeqLV, g_AbortSequence
    row := SeqLV.GetNext(0, "Focused")
    if row = 0
        return
    name := SeqLV.GetText(row, 1)
    if g_Sequences.Has(name) {
        g_AbortSequence := false
        speed := g_Sequences[name].Has("speed") ? g_Sequences[name]["speed"] : 1.0
        SimulateSequence(g_Sequences[name]["steps"], speed)
    }
}

; Simulate sequence execution - shows stacking tooltips without performing actions
SimulateSequence(steps, speedMultiplier := 1.0) {
    global g_Settings, g_AbortSequence, g_Coordinates, g_Patterns, g_SimulationTooltipIndex

    g_AbortSequence := false

    ; Enable ESC to abort
    try Hotkey("Escape", AbortSequenceHandler, "On")

    ; Clear any existing tooltips
    Loop 20
        ToolTip(, , , A_Index)

    g_SimulationTooltipIndex := 1

    enabled := []
    for s in steps
        if s.Has("enabled") && s["enabled"]
            enabled.Push(s)

    total := enabled.Length

    ; Base delay between steps, adjusted for speed
    baseDelay := g_Settings["ActionDelay"]
    adjustedDelay := Round(baseDelay / speedMultiplier)

    ShowStatus("SIMULATING " . total . " steps @ " . speedMultiplier . "x [ESC to abort]", "wait")

    for i, s in enabled {
        if g_AbortSequence {
            ShowStatus("SIMULATION ABORTED", "fail")
            ClearAllSimTooltips()
            try Hotkey("Escape", "Off")
            return
        }

        ; Get coordinates for this step
        coords := GetStepCoordinates(s)

        ; Build tooltip text
        tipText := "[" . i . "/" . total . "] " . s["action"]
        if s["target"] != "" && s["target"] != "(none)"
            tipText .= "`n→ " . s["target"]
        if s["param"] != ""
            tipText .= "`n  (" . s["param"] . ")"

        ; Show tooltip at the action location (stacking)
        ShowSimulationTooltip(tipText, coords["x"], coords["y"], 3000)

        ; Wait between steps
        Sleep(adjustedDelay)
    }

    ; Disable ESC hotkey
    try Hotkey("Escape", "Off")

    ShowStatus("SIMULATION COMPLETE (" . total . " steps)", "ok")

    ; Clear all tooltips after 3 seconds
    SetTimer(ClearAllSimTooltips, -3000)
}

; Show a simulation tooltip that auto-clears after duration (stacking)
ShowSimulationTooltip(text, x, y, duration := 3000) {
    global g_SimulationTooltipIndex

    ; Use tooltip index 2-20 (1 is reserved for status)
    tipIndex := g_SimulationTooltipIndex + 1
    if tipIndex > 20
        tipIndex := 2

    ; Offset slightly so tooltips don't overlap completely
    offsetX := Mod(g_SimulationTooltipIndex - 1, 5) * 10
    offsetY := (g_SimulationTooltipIndex - 1) * 18

    ToolTip(text, x + 15 + offsetX, y + 15 + offsetY, tipIndex)

    ; Schedule this specific tooltip to clear
    clearFunc := ClearSpecificTooltip.Bind(tipIndex)
    SetTimer(clearFunc, -duration)

    ; Advance index
    g_SimulationTooltipIndex++
    if g_SimulationTooltipIndex > 19
        g_SimulationTooltipIndex := 1
}

; Clear a specific tooltip by index
ClearSpecificTooltip(index) {
    ToolTip(, , , index)
}

; Clear all simulation tooltips
ClearAllSimTooltips() {
    Loop 20
        ToolTip(, , , A_Index)
}

; Get coordinates for a step (for simulation display)
GetStepCoordinates(step) {
    global g_Coordinates, g_Patterns, g_Settings

    action := step["action"]
    target := step["target"]
    param := step["param"]

    ; Default to screen center
    x := A_ScreenWidth // 2
    y := A_ScreenHeight // 2

    ; Try to get coordinates based on action type
    try {
        if InStr(action, "Click") || action = "Drag" {
            ; Coordinate-based action
            if target != "" && target != "(none)" && g_Coordinates.Has(target) {
                c := g_Coordinates[target]
                x := c["x"]
                y := c["y"]
            } else if param != "" && InStr(param, ",") {
                ; Handle drag format: "startX,startY->endX,endY"
                if InStr(param, "->") {
                    ; Extract just the start coordinates
                    startPart := Trim(SubStr(param, 1, InStr(param, "->") - 1))
                    p := StrSplit(startPart, ",")
                    if p.Length >= 2 && IsNumber(Trim(p[1])) && IsNumber(Trim(p[2])) {
                        x := Integer(Trim(p[1]))
                        y := Integer(Trim(p[2]))
                    }
                } else {
                    ; Simple "x,y" format
                    p := StrSplit(param, ",")
                    if p.Length >= 2 && IsNumber(Trim(p[1])) && IsNumber(Trim(p[2])) {
                        x := Integer(Trim(p[1]))
                        y := Integer(Trim(p[2]))
                    }
                }
            }
        } else if InStr(action, "Find &") || action = "Wait for Pattern" || action = "Wait Until Gone" {
            ; Pattern-based action - try to find pattern on screen
            patternName := StrReplace(target, "[P] ", "")
            if g_Patterns.Has(patternName) {
                code := g_Patterns[patternName]["text"]
                tolerance := g_Settings["FindTextTolerance"]
                ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)
                if ok && ok.Length > 0 {
                    x := ok[1].mx
                    y := ok[1].my
                }
            }
        } else if action = "Activate Window" || action = "Taskbar Activate" {
            ; Window/taskbar activation - show at top center
            x := A_ScreenWidth // 2
            y := 100
        } else if action = "Key Chord" || action = "Send Keys" || action = "Type Text" {
            ; Keyboard actions - show near center but offset
            x := A_ScreenWidth // 2
            y := A_ScreenHeight // 2 + 50
        } else if InStr(action, "Revolver") || InStr(action, "Clipboard") {
            ; Clipboard/revolver actions - show at mouse position
            MouseGetPos(&x, &y)
        }
    }
    ; If any error occurred, we already have screen center as default

    return Map("x", x, "y", y)
}


; ═══════════════════════════════════════════════════════════════════════════════
; CLIPBOARD
; ═══════════════════════════════════════════════════════════════════════════════
; CLIPBOARD
; =============================================================================

GrabClip(*) {
    global ClipEdit
    ClipEdit.Value := A_Clipboard
}

ParseClip(*) {
    global g_ExtractionRules, g_ExtractedData, ClipEdit, ExtractLV, RulesLV, g_Settings
    text := ClipEdit.Value
    if text = ""
        return
    g_ExtractedData := Map()
    ExtractLV.Delete()
    RulesLV.Delete()
    for r in g_ExtractionRules {
        if RegExMatch(text, r["pattern"], &m) {
            val := Trim(m.Count > 0 ? m[1] : m[0])
            g_ExtractedData[r["name"]] := val
            ExtractLV.Add(, r["name"], val)
            RulesLV.Add(, r["name"], r["pattern"], val)
        } else {
            RulesLV.Add(, r["name"], r["pattern"], "(no match)")
        }
    }
    g_ExtractedData["CurrentDate"] := FormatTime(, g_Settings["DateFormat"])
    PopulateChoices()
}

ClearClip(*) {
    global ClipEdit, ExtractLV, g_ExtractedData
    ClipEdit.Value := ""
    ExtractLV.Delete()
    g_ExtractedData := Map()
}

AddRule(*) {
    global g_ExtractionRules, RulesLV
    saved := MainGui.Submit(false)
    if saved.PatternNameClip = "" || saved.PatternRegex = ""
        return
    try {
        RegExMatch("test", saved.PatternRegex)
    } catch {
        MsgBoxTop("Invalid regex!", "Error")
        return
    }
    g_ExtractionRules.Push(Map("name", saved.PatternNameClip, "pattern", saved.PatternRegex))
    RulesLV.Add(, saved.PatternNameClip, saved.PatternRegex, "")
    SaveExtractionRules()
}

DelRule(*) {
    global g_ExtractionRules, RulesLV
    row := RulesLV.GetNext(0, "Focused")
    if row = 0
        return
    name := RulesLV.GetText(row, 1)
    for i, r in g_ExtractionRules
        if r["name"] = name {
            g_ExtractionRules.RemoveAt(i)
            break
        }
    RulesLV.Delete(row)
    SaveExtractionRules()
}


; ═══════════════════════════════════════════════════════════════════════════════
; HOTKEYS
; ═══════════════════════════════════════════════════════════════════════════════
; HOTKEYS
; =============================================================================

RefreshHKDropdowns(*) {
    global g_Sequences, SeqDDHK, HotkeyLV, g_HotkeyBindings
    items := ["(none)"]
    for n, _ in g_Sequences
        items.Push(n)
    SeqDDHK.Delete()
    SeqDDHK.Add(items)
    SeqDDHK.Choose(items.Length > 1 ? 2 : 1)
    HotkeyLV.Delete()
    for hk, seq in g_HotkeyBindings
        HotkeyLV.Add(, hk, seq)
}

AddHotkey(*) {
    global g_HotkeyBindings, SeqDDHK
    saved := MainGui.Submit(false)
    if saved.HotkeyKey = "" || SeqDDHK.Text = "(none)"
        return
    hk := ""
    switch saved.Modifier {
        case "Ctrl": hk := "^"
        case "Alt": hk := "!"
        case "Shift": hk := "+"
        case "Ctrl+Alt": hk := "^!"
        case "Ctrl+Shift": hk := "^+"
    }
    hk .= saved.HotkeyKey
    g_HotkeyBindings[hk] := SeqDDHK.Text
    RefreshHKDropdowns()
    SaveHotkeys()
}

RemoveHotkey(*) {
    global g_HotkeyBindings, HotkeyLV
    row := HotkeyLV.GetNext(0, "Focused")
    if row = 0
        return
    hk := HotkeyLV.GetText(row, 1)
    try Hotkey(hk, "Off")
    g_HotkeyBindings.Delete(hk)
    RefreshHKDropdowns()
    SaveHotkeys()
}

ApplyHotkeys(*) {
    global g_HotkeyBindings
    for hk, _ in g_HotkeyBindings
        try Hotkey(hk, "Off")
    count := 0
    for hk, seq in g_HotkeyBindings {
        try {
            Hotkey(hk, RunSeqByName.Bind(seq), "On")
            count++
        }
    }
    StatusBar.SetText("Applied " . count . " hotkeys")
}

RunSeqByName(seqName, *) {
    global g_Sequences, g_IsPaused, g_AbortSequence
    if !g_Sequences.Has(seqName)
        return
    g_IsPaused := false
    g_AbortSequence := false
    speed := g_Sequences[seqName].Has("speed") ? g_Sequences[seqName]["speed"] : 1.0
    ExecuteSequenceVerified(g_Sequences[seqName]["steps"], speed)
}


; ═══════════════════════════════════════════════════════════════════════════════
; EXECUTION
; ═══════════════════════════════════════════════════════════════════════════════
; EXECUTION
; =============================================================================

; Substitute $word.xxx and $var.xxx variables in workflow parameters
; This enables dynamic text from Watch Words and Spool Variables
SubstituteWorkflowVariables(text) {
    global g_SpoolVariables, g_WordVariables, g_WatchWords, g_WorkflowVariables

    if text = "" || !InStr(text, "$")
        return text

    ; First update all watch words to get fresh values
    if InStr(text, "$word.")
        UpdateAllWatchWords()

    ; Substitute $word.xxx patterns
    ; Format: $word.PatientName → actual captured text value
    while RegExMatch(text, "\$word\.(\w+)", &match) {
        varName := match[1]
        value := ""

        ; Check g_WordVariables first
        if g_WordVariables.Has("$word." . varName) {
            value := g_WordVariables["$word." . varName]
        } else if g_SpoolVariables.Has("$word." . varName) {
            value := g_SpoolVariables["$word." . varName]
        } else if g_WatchWords.Has(varName) {
            value := g_WatchWords[varName]["lastValue"]
        }

        text := StrReplace(text, match[0], value)
    }

    ; Substitute $var.xxx patterns (from spool variables)
    ; Format: $var.PhoneNumber → extracted OCR value
    while RegExMatch(text, "\$var\.(\w+)", &match) {
        varName := match[1]
        value := ""

        if g_WorkflowVariables.Has(varName) {
            value := g_WorkflowVariables[varName]
        } else if g_SpoolVariables.Has(varName) {
            value := g_SpoolVariables[varName]
        } else if g_SpoolVariables.Has("$" . varName) {
            value := g_SpoolVariables["$" . varName]
        }

        text := StrReplace(text, match[0], value)
    }

    ; Also handle bare $xxx for backward compatibility with spool variables
    while RegExMatch(text, "\$(\w+)(?!\.)(?!word)(?!var)", &match) {
        varName := match[1]
        if varName = "word" || varName = "var"
            continue

        value := ""
        if g_SpoolVariables.Has("$" . varName) {
            value := g_SpoolVariables["$" . varName]
        } else if g_SpoolVariables.Has(varName) {
            value := g_SpoolVariables[varName]
        }

        if value != ""
            text := StrReplace(text, match[0], value)
        else
            break  ; Avoid infinite loop if variable not found
    }

    return text
}

ExecuteSequenceVerified(steps, speedMultiplier := 1.0) {
    global g_Settings, g_IsPaused, g_AbortSequence, g_DebugMode, g_StepThroughMode, g_StepThroughWaiting, g_StepThroughContinue
    global g_WorkflowVariables, g_SkipNextAction, g_SequenceCallStack
    g_AbortSequence := false
    g_WorkflowVariables := Map()
    g_SkipNextAction := false
    g_SequenceCallStack := []

    ; Enable ESC to abort and Tab for step-through
    try Hotkey("Escape", AbortSequenceHandler, "On")
    if g_StepThroughMode
        try Hotkey("Tab", StepThroughAdvance, "On")

    enabled := []
    for s in steps
        if s.Has("enabled") && s["enabled"]
            enabled.Push(s)
    total := enabled.Length

    ; Calculate adjusted delay (lower speed = longer delays)
    baseDelay := g_Settings["ActionDelay"]
    adjustedDelay := Round(baseDelay / speedMultiplier)

    speedText := speedMultiplier . "x"
    modeText := g_StepThroughMode ? " [STEP-THROUGH: Press Tab]" : " [ESC to abort]"

    ShowStatus("Running " . total . " steps @ " . speedText . modeText, "wait")

    for i, s in enabled {
        if g_AbortSequence {
            ShowStatus("ABORTED by ESC", "fail")
            try Hotkey("Escape", "Off")
            if g_StepThroughMode
                try Hotkey("Tab", "Off")
            SoundBeep(300, 100)
            return
        }
        while g_IsPaused {
            ToolTip("PAUSED [" . i . "/" . total . "] - ESC to abort")
            Sleep(100)
            if g_AbortSequence {
                try Hotkey("Escape", "Off")
                if g_StepThroughMode
                    try Hotkey("Tab", "Off")
                return
            }
        }

        if g_SkipNextAction {
            g_SkipNextAction := false
            ShowStatus("[" . i . "/" . total . "] Skipped by previous condition: " . s["action"], "info")
            continue
        }

        ShowStatus("[" . i . "/" . total . "] " . s["action"] . " @ " . speedText . modeText, "wait")

        ; Check if notifications are muted for this step
        stepMuted := s.Has("notificationMuted") && s["notificationMuted"]

        ; Show step start notification in debug mode
        if g_DebugMode && !stepMuted {
            stepInfo := "[" . i . "/" . total . "] " . s["action"]
            if s["target"] != ""
                stepInfo .= "`nTarget: " . s["target"]
            if s["param"] != ""
                stepInfo .= "`nParam: " . s["param"]
            ShowNotificationBasic("Executing", stepInfo, 0, "info", "", i)
        }

        success := ExecuteActionVerified(s["action"], s["target"], s["param"], s, speedMultiplier)

        ; Show step result notification
        if success {
            if g_DebugMode && !stepMuted {
                ShowNotificationBasic("Step " . i . " Success", s["action"] . " completed", 0, "success", "", i)
            }
        } else {
            if !stepMuted {
                ShowNotificationBasic("Step " . i . " Failed", s["action"] . "`nTarget: " . s["target"], 0, "error", "", i)
            }
            if !g_AbortSequence {
                result := MsgBoxTop("Step " . i . " failed: " . s["action"] . "`nTarget: " . s["target"] . "`n`nContinue?", "Failed", "YesNo")
                if result = "No" {
                    try Hotkey("Escape", "Off")
                    if g_StepThroughMode
                        try Hotkey("Tab", "Off")
                    return
                }
            }
        }

        ; Step-through mode: Wait for Tab key before continuing
        if g_StepThroughMode && i < total {
            g_StepThroughWaiting := true
            g_StepThroughContinue := false

            ShowStatus("[WAITING] Press Tab for next step, ESC to abort", "info")

            ; Wait for Tab key or abort
            while !g_StepThroughContinue && !g_AbortSequence {
                Sleep(50)
            }

            g_StepThroughWaiting := false

            if g_AbortSequence {
                try Hotkey("Escape", "Off")
                try Hotkey("Tab", "Off")
                return
            }
        } else {
            Sleep(adjustedDelay)
        }
    }

    ; Disable hotkeys
    try Hotkey("Escape", "Off")
    if g_StepThroughMode
        try Hotkey("Tab", "Off")

    ShowStatus("Complete (" . total . " steps @ " . speedText . ")", "ok")
    ShowNotificationBasic("Sequence Complete", total . " steps executed successfully", 0, "success")
    Sleep(500)
    ToolTip()
}

StepThroughAdvance(*) {
    global g_StepThroughContinue, g_StepThroughWaiting
    if g_StepThroughWaiting {
        g_StepThroughContinue := true
        ShowStatus("Advancing to next step...", "ok")
    }
}

; Handler for ESC abort
AbortSequenceHandler(*) {
    global g_AbortSequence
    g_AbortSequence := true
    ToolTip("ABORTING...")
}

ExecuteActionVerified(action, target, param, stepData := "", speedMultiplier := 1.0) {
    global g_Coordinates, g_Patterns, g_ExtractedData, g_Settings, g_AbortSequence
    global g_LastClickX, g_LastClickY, g_SpoolVariables, g_WordVariables
    global g_WorkflowVariables, g_SkipNextAction

    if g_AbortSequence
        return false

    ; VARIABLE SUBSTITUTION: Replace $word.xxx and $var.xxx in param
    ; This allows dynamic text from Watch Words and Spool Variables to be used
    ; in workflows. Example: Type Text with param "$word.PatientName"
    param := SubstituteWorkflowVariables(param)

    ; Calculate speed-adjusted delays
    preDelay := Round(g_Settings["PreActionDelay"] / speedMultiplier)
    postDelay := Round(g_Settings["PostActionDelay"] / speedMultiplier)

    ; PER-STEP FAILSAFE CHECKS
    if IsObject(stepData) && stepData.Has("failsafe") {
        fs := stepData["failsafe"]

        ; Only process failsafe if it's a Map (not a string from old data)
        if IsObject(fs) && (fs is Map) {
            ; Check required window
            if fs.Has("window") && fs["window"] != "" {
                activeTitle := ""
                try activeTitle := WinGetTitle("A")
                if !InStr(activeTitle, fs["window"]) {
                    ShowStatus("Failsafe: Window not active - " . fs["window"], "fail")
                    if fs.Has("abortOnFail") && fs["abortOnFail"] {
                        g_AbortSequence := true
                    }
                    return false
                }
            }

            ; Check required pattern (for click actions)
            if fs.Has("requirePattern") && fs["requirePattern"] && fs.Has("pattern") && fs["pattern"] != "" {
                if !CheckPatternQualifier(fs["pattern"]) {
                    ShowStatus("Failsafe: Pattern not found - " . fs["pattern"], "fail")
                    if fs.Has("abortOnFail") && fs["abortOnFail"] {
                        g_AbortSequence := true
                    }
                    return false
                }
            }

            ; Apply custom pre-delay if set
            if fs.Has("preDelay") && fs["preDelay"] > 0 {
                Sleep(fs["preDelay"])
            }

            ; Wait for window idle (keyboard actions)
            if fs.Has("waitForIdle") && fs["waitForIdle"] {
                try WinWaitActive("A", , 2)
            }
        }
    }

    ; Legacy qualifier window check (backward compatibility)
    if IsObject(stepData) && stepData.Has("qualWindow") && stepData["qualWindow"] != "" {
        win := GetWindowUnderMouse()
        if !InStr(win["title"], stepData["qualWindow"]) {
            ShowStatus("Window mismatch: " . stepData["qualWindow"], "fail")
            return false
        }
    }

    ; Apply pre-action delay
    if preDelay > 0
        Sleep(preDelay)

    switch action {
        case "Click":
            if target != "" && target != "(none)" && g_Coordinates.Has(target) {
                c := g_Coordinates[target]
                g_LastClickX := c["x"]
                g_LastClickY := c["y"]
                FlashClickPosition(c["x"], c["y"])
                return ClickVerified(c["x"], c["y"], "Left", param != "" ? Integer(param) : 1)
            } else if target != "" && InStr(target, ",") {
                p := StrSplit(target, ",")
                g_LastClickX := Integer(p[1])
                g_LastClickY := Integer(p[2])
                FlashClickPosition(Integer(p[1]), Integer(p[2]))
                return ClickVerified(Integer(p[1]), Integer(p[2]), "Left", param != "" ? Integer(param) : 1)
            } else if param != "" && InStr(param, ",") {
                ; Backward compatibility with workflows that stored x,y in Param.
                p := StrSplit(param, ",")
                return ClickVerified(Integer(p[1]), Integer(p[2]))
            }
            MouseGetPos(&g_LastClickX, &g_LastClickY)
            FlashClickPosition(g_LastClickX, g_LastClickY)
            Click()
            return true

        case "Double Click":
            if target != "" && target != "(none)" && g_Coordinates.Has(target) {
                c := g_Coordinates[target]
                g_LastClickX := c["x"]
                g_LastClickY := c["y"]
                return ClickVerified(c["x"], c["y"], "Left", 2)
            } else if target != "" && InStr(target, ",") {
                p := StrSplit(target, ",")
                g_LastClickX := Integer(p[1]), g_LastClickY := Integer(p[2])
                return ClickVerified(g_LastClickX, g_LastClickY, "Left", 2)
            }
            MouseGetPos(&g_LastClickX, &g_LastClickY)
            Click(, , , 2)
            return true

        case "Triple Click":
            if target != "" && target != "(none)" && g_Coordinates.Has(target) {
                c := g_Coordinates[target]
                g_LastClickX := c["x"]
                g_LastClickY := c["y"]
                return ClickVerified(c["x"], c["y"], "Left", 3)
            } else if target != "" && InStr(target, ",") {
                p := StrSplit(target, ",")
                g_LastClickX := Integer(p[1]), g_LastClickY := Integer(p[2])
                return ClickVerified(g_LastClickX, g_LastClickY, "Left", 3)
            }
            MouseGetPos(&g_LastClickX, &g_LastClickY)
            Click(, , , 3)
            return true

        case "Right Click":
            if target != "" && target != "(none)" && g_Coordinates.Has(target) {
                c := g_Coordinates[target]
                g_LastClickX := c["x"]
                g_LastClickY := c["y"]
                return ClickVerified(c["x"], c["y"], "Right")
            } else if target != "" && InStr(target, ",") {
                p := StrSplit(target, ",")
                g_LastClickX := Integer(p[1]), g_LastClickY := Integer(p[2])
                return ClickVerified(g_LastClickX, g_LastClickY, "Right")
            }
            MouseGetPos(&g_LastClickX, &g_LastClickY)
            Click(, , "Right")
            return true

        case "Drag":
            if target != "" && target != "(none)" && g_Coordinates.Has(target) {
                c := g_Coordinates[target]
                if c["endX"] != "" {
                    MoveMouseVerified(c["x"], c["y"])
                    Sleep(g_Settings["PreActionDelay"])
                    MouseClickDrag("Left", c["x"], c["y"], c["endX"], c["endY"], g_Settings["DefaultDragTime"] / 100)
                    g_LastClickX := c["endX"]
                    g_LastClickY := c["endY"]
                    Sleep(g_Settings["PostActionDelay"])
                    return true
                }
            }
            if param != "" && InStr(param, "->") {
                parts := StrSplit(param, "->")
                startParts := StrSplit(parts[1], ",")
                endParts := StrSplit(parts[2], ",")
                MoveMouseVerified(Integer(startParts[1]), Integer(startParts[2]))
                Sleep(g_Settings["PreActionDelay"])
                MouseClickDrag("Left", Integer(startParts[1]), Integer(startParts[2]), Integer(endParts[1]), Integer(endParts[2]), g_Settings["DefaultDragTime"] / 100)
                g_LastClickX := Integer(endParts[1])
                g_LastClickY := Integer(endParts[2])
                Sleep(g_Settings["PostActionDelay"])
                return true
            }
            return false

        case "Relative Click":
            if target != "" && target != "(none)" && g_Coordinates.Has(target) {
                c := g_Coordinates[target]
                if c["type"] = "Relative" {
                    newX := g_LastClickX + c["x"]
                    newY := g_LastClickY + c["y"]
                    g_LastClickX := newX
                    g_LastClickY := newY
                    return ClickVerified(newX, newY, "Left", 1)
                }
            }
            if param != "" && InStr(param, ",") {
                p := StrSplit(param, ",")
                newX := g_LastClickX + Integer(p[1])
                newY := g_LastClickY + Integer(p[2])
                g_LastClickX := newX
                g_LastClickY := newY
                return ClickVerified(newX, newY, "Left", 1)
            }
            return false

        case "Menu Select":
            downCount := param != "" ? Integer(param) : 1
            ShowStatus("Menu: " . downCount . " down + Enter", "wait")
            Sleep(g_Settings["PreActionDelay"])
            Loop downCount {
                Send("{Down}")
                Sleep(50)
            }
            Sleep(50)
            Send("{Enter}")
            Sleep(g_Settings["PostActionDelay"])
            ShowStatus("Menu selected", "ok")
            return true

        case "Find & Click":
            return FindAndClickPattern(target, "Left", 1)

        case "Find & DblClick":
            return FindAndClickPattern(target, "Left", 2)

        case "Find & TplClick":
            return FindAndClickPattern(target, "Left", 3)

        case "Find & RClick":
            return FindAndClickPattern(target, "Right", 1)

        case "Find & Drag":
            if param != "" && InStr(param, ",") {
                p := StrSplit(param, ",")
                return FindAndDragPattern(target, Integer(p[1]), Integer(p[2]))
            }
            ShowStatus("Find & Drag needs end coords", "fail")
            return false

        case "Wait for Pattern":
            timeout := param != "" ? Integer(param) : g_Settings["FindTextTimeout"]
            ShowStatus("Waiting for: " . target, "wait")
            result := WaitForPattern(target, timeout)
            if result {
                ShowStatus("Found: " . target, "ok")
                return true
            }
            ShowStatus("Timeout: " . target, "fail")
            return false

        case "Wait Until Gone":
            timeout := param != "" ? Integer(param) : g_Settings["FindTextTimeout"]
            ShowStatus("Waiting until gone: " . target, "wait")
            result := WaitForPatternGone(target, timeout)
            if result {
                ShowStatus("Gone: " . target, "ok")
                return true
            }
            ShowStatus("Still visible: " . target, "fail")
            return false

        case "Send Keys":
            return SendKeysVerified(param)

        case "Type Text":
            return TypeTextVerified(param)

        case "Key Chord":
            return ExecuteKeyChord(param)

        case "Paste":
            Sleep(g_Settings["PreActionDelay"])
            Send("^v")
            Sleep(g_Settings["PostActionDelay"])
            return true

        case "Set Clipboard":
            return SetClipboardVerified(param)

        case "Wait":
            Sleep(param != "" ? Integer(param) : g_Settings["ActionDelay"])
            return true

        case "Activate Window":
            return ActivateWindowRobust(param)

        case "Taskbar Activate":
            return ExecuteTaskbarActivate(param)

        case "Run Program":
            try {
                Run(param)
                Sleep(g_Settings["ActionDelay"])
                return true
            }
            return false

        case "Insert Field":
            if param != "" && g_ExtractedData.Has(param)
                return TypeTextVerified(g_ExtractedData[param])
            return false

        case "Insert Date":
            return TypeTextVerified(FormatTime(, g_Settings["DateFormat"]))

        case "Scroll":
            amt := param != "" ? Integer(param) : 3
            Click(amt > 0 ? "WheelUp" : "WheelDown", , , Abs(amt))
            return true

        case "Parse Clipboard":
            ShowStatus("Parsing clipboard...", "wait")
            ClipEdit.Value := A_Clipboard
            ParseClipboardForRevolver()
            if g_ExtractedData.Count > 0 {
                ShowStatus("Parsed " . g_ExtractedData.Count . " fields", "ok")
                return true
            }
            ShowStatus("No fields extracted", "fail")
            return false

        case "Load Revolver":
            return LoadRevolverSilent()

        case "Fire Revolver":
            return FireRevolverSequence(true, false)

        case "Fire Revolver+Enter":
            return FireRevolverSequence(true, true)

        case "OCR Region":
            return ExecuteOCRRegion(target, param)

        case "OCR Click":
            return ExecuteOCRClick(target, param)

        case "OCR Wait":
            return ExecuteOCRWait(target, param)

        case "Load OCR Revolver":
            return LoadOCRRevolver(param)

        case "Fire OCR Revolver":
            return FireOCRRevolver()

        case "Idle Mouse":
            duration := param != "" ? Integer(param) : 0
            return ExecuteIdleMouse(duration)

        case "Hover Mouse":
            return ExecuteHoverMouse(target != "" ? target : param)

        case "Grab OCR to Var":
            ; New editor: Target is x,y,width,height and Param is the variable.
            ; Combined legacy Param strings continue to work.
            grabParams := target != "" && !InStr(param, ",") ? param . "," . target : param
            return ExecuteGrabOCRToVar(grabParams)

        case "OCR Full Screen to Var":
            return ExecuteFullScreenOCRToVar(param)

        case "Use Var Paste":
            return ExecuteUseVarPaste(param)

        case "Show Notification":
            return ExecuteShowNotification(param)

        case "Set Variable":
            varName := NormalizeWorkflowVariableName(target)
            if varName = "" {
                ShowStatus("Set Variable needs a valid variable name", "fail")
                return false
            }
            g_WorkflowVariables[varName] := param
            g_SpoolVariables[varName] := param
            ShowStatus("Variable set: $var." . varName, "ok")
            return true

        case "Grab Clipboard":
            varName := NormalizeWorkflowVariableName(target)
            if varName = "" {
                ShowStatus("Grab Clipboard needs a valid variable name", "fail")
                return false
            }
            g_WorkflowVariables[varName] := A_Clipboard
            g_SpoolVariables[varName] := A_Clipboard
            ShowStatus("Clipboard stored as $var." . varName, "ok")
            return true

        case "If Contains":
            varName := NormalizeWorkflowVariableName(target)
            if !TryGetWorkflowVariable(varName, &variableValue) {
                g_SkipNextAction := true
                ShowStatus("If Contains: $var." . varName . " was not found; next step will be skipped", "info")
                return true
            }
            g_SkipNextAction := !InStr(String(variableValue), param)
            ShowStatus(g_SkipNextAction ? "If Contains: false; next step will be skipped" : "If Contains: true", "info")
            return true

        case "If Variable":
            varName := NormalizeWorkflowVariableName(target)
            if !TryGetWorkflowVariable(varName, &variableValue) {
                g_SkipNextAction := true
                ShowStatus("If Variable: $var." . varName . " was not found; next step will be skipped", "info")
                return true
            }
            if !EvaluateWorkflowComparison(variableValue, param, &comparisonText) {
                ShowStatus("If Variable: " . comparisonText, "fail")
                return false
            }
            g_SkipNextAction := !comparisonText
            ShowStatus(g_SkipNextAction ? "If Variable: false; next step will be skipped" : "If Variable: true", "info")
            return true

        case "Stop Execution":
            g_AbortSequence := true
            ShowStatus("Workflow stopped by Stop Execution", "info")
            return true

        case "Run Sequence":
            return ExecuteSubSequenceByName(Trim(param), speedMultiplier)

        case "Format Clipboard":
            formatName := Trim(param)
            clipText := A_Clipboard
            switch StrLower(formatName) {
                case "invoice": result := "INV-" . clipText
                case "receipt": result := "RCP-" . clipText
                case "uppercase": result := StrUpper(clipText)
                case "lowercase": result := StrLower(clipText)
                case "titlecase": result := StrTitle(clipText)
                case "trim": result := Trim(clipText)
                case "date_iso": result := FormatTime(, "yyyy-MM-dd")
                default: result := StrReplace(formatName, "{clip}", clipText)
            }
            A_Clipboard := result
            ShowStatus("Clipboard formatted", "ok")
            return true

        case "Append to Clipboard":
            A_Clipboard := A_Clipboard . param
            ShowStatus("Text appended to clipboard", "ok")
            return true

        case "Prepend to Clipboard":
            A_Clipboard := param . A_Clipboard
            ShowStatus("Text prepended to clipboard", "ok")
            return true

        case "Extract from Clipboard":
            return ExtractClipboardByRule(param)

    }

    return false
}

NormalizeWorkflowVariableName(name) {
    name := Trim(name)
    if SubStr(name, 1, 5) = "$var."
        name := SubStr(name, 6)
    else if SubStr(name, 1, 1) = "$"
        name := SubStr(name, 2)
    return RegExMatch(name, "^[A-Za-z_][A-Za-z0-9_]*$") ? name : ""
}

TryGetWorkflowVariable(name, &value) {
    global g_WorkflowVariables, g_SpoolVariables
    value := ""
    if name = ""
        return false
    if g_WorkflowVariables.Has(name) {
        value := g_WorkflowVariables[name]
        return true
    }
    if g_SpoolVariables.Has(name) {
        value := g_SpoolVariables[name]
        return true
    }
    if g_SpoolVariables.Has("$" . name) {
        value := g_SpoolVariables["$" . name]
        return true
    }
    return false
}

EvaluateWorkflowComparison(variableValue, expression, &result) {
    result := false
    commaPos := InStr(expression, ",")
    if !commaPos {
        result := "Comparison must use operator,value"
        return false
    }
    operator := Trim(SubStr(expression, 1, commaPos - 1))
    compareValue := Trim(SubStr(expression, commaPos + 1))
    numeric := IsNumber(variableValue) && IsNumber(compareValue)
    left := numeric ? Number(variableValue) : String(variableValue)
    right := numeric ? Number(compareValue) : compareValue
    switch operator {
        case "=", "==": result := (left = right)
        case "!=", "<>": result := (left != right)
        case ">": result := numeric && left > right
        case "<": result := numeric && left < right
        case ">=": result := numeric && left >= right
        case "<=": result := numeric && left <= right
        default:
            result := "Unknown comparison operator: " . operator
            return false
    }
    return true
}

ExecuteSubSequenceByName(sequenceName, speedMultiplier := 1.0) {
    global g_Sequences, g_SequenceCallStack, g_SkipNextAction, g_AbortSequence
    if sequenceName = "" || !g_Sequences.Has(sequenceName) {
        ShowStatus("Run Sequence: workflow not found - " . sequenceName, "fail")
        return false
    }
    for activeName in g_SequenceCallStack {
        if activeName = sequenceName {
            ShowStatus("Run Sequence blocked a recursive call to " . sequenceName, "fail")
            return false
        }
    }

    g_SequenceCallStack.Push(sequenceName)
    g_SkipNextAction := false
    seq := g_Sequences[sequenceName]
    completed := true
    try {
        for step in seq["steps"] {
            if g_AbortSequence
                break
            if step.Has("enabled") && !step["enabled"]
                continue
            if g_SkipNextAction {
                g_SkipNextAction := false
                ShowStatus("Sub-workflow skipped: " . step["action"], "info")
                continue
            }
            stepOK := ExecuteActionVerified(step["action"], step["target"], step["param"], step, speedMultiplier)
            if !stepOK {
                completed := false
                if seq.Has("abortOnFail") && seq["abortOnFail"]
                    break
            }
        }
    } finally {
        ; A condition at the end of a sub-workflow must not skip a caller step.
        g_SkipNextAction := false
        g_SequenceCallStack.Pop()
    }
    return completed
}

ExtractClipboardByRule(rule) {
    source := A_Clipboard
    rule := Trim(rule)
    extracted := ""

    if InStr(rule, "between:") = 1 {
        payload := SubStr(rule, 9)
        separator := InStr(payload, "|")
        if separator {
            startText := SubStr(payload, 1, separator - 1)
            endText := SubStr(payload, separator + 1)
            startPos := InStr(source, startText)
            if startPos {
                contentStart := startPos + StrLen(startText)
                endPos := InStr(source, endText, , contentStart)
                if endPos
                    extracted := SubStr(source, contentStart, endPos - contentStart)
            }
        }
    } else if InStr(rule, "field:") = 1 {
        payload := SubStr(rule, 7)
        separator := InStr(payload, "|", , -1)
        if separator {
            delimiter := SubStr(payload, 1, separator - 1)
            indexText := Trim(SubStr(payload, separator + 1))
            if delimiter != "" && IsNumber(indexText) {
                fields := StrSplit(source, delimiter)
                index := Integer(indexText)
                if index >= 1 && index <= fields.Length
                    extracted := Trim(fields[index])
            }
        }
    } else if InStr(rule, "regex:") = 1 {
        pattern := SubStr(rule, 7)
        try {
            if RegExMatch(source, pattern, &match)
                extracted := match[0]
        } catch as err {
            ShowStatus("Invalid extraction regex: " . err.Message, "fail")
            return false
        }
    }

    if extracted = "" {
        ShowStatus("Extract from Clipboard: rule did not match", "fail")
        return false
    }
    A_Clipboard := extracted
    ShowStatus("Clipboard extraction complete", "ok")
    return true
}


; ═══════════════════════════════════════════════════════════════════════════════
; OCR WORKFLOW ACTIONS
; ═══════════════════════════════════════════════════════════════════════════════
; OCR WORKFLOW ACTIONS
; =============================================================================

; Execute OCR Region action - capture and process text from screen region
ExecuteOCRRegion(target, param) {
    global g_LastOCRText, g_LastOCRRegion, g_SpoolVariables, g_WordVariables, g_OCRSettings

    ; Parse region from target
    region := ParseRegionCoords(target)
    if !region {
        ShowActionNotification("OCR Region", "error",
            "Invalid region coordinates",
            "Could not parse region from target: " . target . "`n`nExpected format: x,y,width,height`nExample: 100,100,400,200")
        return false
    }

    ; Store for later use
    g_LastOCRRegion := region

    ; Check if OCR is available
    if !IsOCRAvailable() {
        return ReportOCRError("Extract", region, "OCR.ahk library not found or not loaded. Ensure OCR.ahk is in the script directory.")
    }

    ; Perform OCR on region using Windows UWP
    text := ""
    try {
        ocrResult := OCR.FromRect(region["x1"], region["y1"],
                                  region["x2"] - region["x1"],
                                  region["y2"] - region["y1"],
                                  g_OCRSettings["language"],
                                  g_OCRSettings["scale"])
        text := ocrResult.Text
    } catch as e {
        return ReportOCRError("Extract", region, e.Message)
    }

    if text = "" {
        return ReportOCRError("Extract", region, "No text detected in specified region. Text may be too small, obscured, or region may be incorrect.")
    }

    ; Store the captured text
    g_LastOCRText := text

    ; Process based on param
    param := Trim(param)

    if param = "" || param = "copy" {
        ; Copy to clipboard
        A_Clipboard := text
        ShowStatus("OCR: Copied " . StrLen(text) . " chars to clipboard", "ok")
        return true
    }

    if SubStr(param, 1, 4) = "var:" {
        ; Store in variable
        varName := SubStr(param, 5)
        g_SpoolVariables[varName] := text
        g_WordVariables["$var." . varName] := text
        ShowActionNotification("OCR Region", "success",
            "Extracted " . StrLen(text) . " characters`nStored in variable: $var." . varName . "`n`nPreview: " . SubStr(text, 1, 50) . (StrLen(text) > 50 ? "..." : ""))
        try RefreshOCRVarsLV()
        return true
    }

    if SubStr(param, 1, 6) = "split:" {
        ; Split and load into revolver
        splitParam := SubStr(param, 7)
        LoadOCRRevolver(splitParam)
        return true
    }

    if SubStr(param, 1, 6) = "regex:" {
        ; Extract using regex
        pattern := SubStr(param, 7)
        if RegExMatch(text, pattern, &match) {
            extractedText := match[0]
            A_Clipboard := extractedText
            g_LastOCRText := extractedText
            ShowStatus("OCR regex: " . SubStr(extractedText, 1, 30), "ok")
            return true
        } else {
            ShowStatus("OCR: Regex no match", "fail")
            return false
        }
    }

    ; Default: copy to clipboard
    A_Clipboard := text
    ShowStatus("OCR captured: " . SubStr(text, 1, 30) . "...", "ok")
    return true
}





; Execute OCR Click - find text and click on it
ExecuteOCRClick(target, param) {
    global g_OCRSettings

    ; Parse region
    region := ParseRegionCoords(target)
    if !region {
        ; Use full screen
        region := Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)
    }

    ; Perform OCR
    searchText := Trim(param)
    if searchText = "" {
        ShowActionNotification("OCR Click", "error", "No search text specified", "PARAM must contain the text to find and click")
        return false
    }

    if !IsOCRAvailable() {
        return ReportOCRError("Click", region, "OCR.ahk library not found or not loaded")
    }

    try {
        ocrResult := OCR.FromRect(region["x1"], region["y1"],
                                  region["x2"] - region["x1"],
                                  region["y2"] - region["y1"],
                                  g_OCRSettings["language"],
                                  g_OCRSettings["scale"])

        ; Search for the text
        for word in ocrResult.Words {
            if InStr(word.Text, searchText) || InStr(searchText, word.Text) {
                ; Found it - click on center
                clickX := region["x1"] + word.x + (word.w // 2)
                clickY := region["y1"] + word.y + (word.h // 2)

                ; Highlight briefly
                HighlightRegion(clickX - 5, clickY - 5, 10, 10, 500, "match", searchText)

                Click(clickX, clickY)
                ShowActionNotification("OCR Click", "success", "Clicked on '" . searchText . "' at " . clickX . "," . clickY)
                return true
            }
        }

        ; Try partial match on full text lines
        for line in ocrResult.Lines {
            if InStr(line.Text, searchText) {
                ; Click center of line
                clickX := region["x1"] + line.x + (line.w // 2)
                clickY := region["y1"] + line.y + (line.h // 2)

                HighlightRegion(clickX - 20, clickY - 5, 40, 10, 500, "match", searchText)

                Click(clickX, clickY)
                ShowActionNotification("OCR Click", "success", "Clicked on line containing '" . searchText . "'")
                return true
            }
        }

    } catch as e {
        return ReportOCRError("Click", region, e.Message)
    }

    ShowActionNotification("OCR Click", "error",
        "Text not found: '" . searchText . "'",
        "Possible causes:`n• Text is not visible in region`n• Text is too small or blurry`n• Wrong search text`n`nSolutions:`n• Verify text exists and is readable`n• Increase scale in OCR settings`n• Try broader search region`n• Check spelling of search text")
    return false
}

; Execute OCR Wait - wait for text to appear
ExecuteOCRWait(target, param) {
    global g_OCRSettings, g_AbortSequence

    ; Parse region
    region := ParseRegionCoords(target)
    if !region {
        region := Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)
    }

    ; Parse param: timeout or "text:searchText,timeout"
    timeout := 5000
    searchText := ""

    param := Trim(param)
    if SubStr(param, 1, 5) = "text:" {
        ; Extract search text and optional timeout
        rest := SubStr(param, 6)
        if InStr(rest, ",") {
            parts := StrSplit(rest, ",")
            searchText := Trim(parts[1])
            timeout := Integer(Trim(parts[2]))
        } else {
            searchText := rest
        }
    } else if param != "" {
        timeout := Integer(param)
    }

    ShowStatus("OCR Wait: " . (searchText != "" ? searchText : "any text") . " (" . timeout . "ms)", "wait")

    startTime := A_TickCount
    while (A_TickCount - startTime) < timeout {
        if g_AbortSequence
            return false

        try {
            ocrResult := OCR.FromRect(region["x1"], region["y1"],
                                      region["x2"] - region["x1"],
                                      region["y2"] - region["y1"],
                                      g_OCRSettings["language"])

            if searchText = "" {
                ; Wait for any text
                if ocrResult.Text != "" {
                    ShowStatus("OCR Wait: Text detected", "ok")
                    return true
                }
            } else {
                ; Wait for specific text
                if InStr(ocrResult.Text, searchText) {
                    ShowStatus("OCR Wait: Found '" . searchText . "'", "ok")
                    return true
                }
            }
        }

        Sleep(200)
    }

    ShowStatus("OCR Wait: Timeout", "fail")
    return false
}

; Load OCR text into revolver for sequential pasting
LoadOCRRevolver(param) {
    global g_LastOCRText, g_OCRRevolver, g_OCRRevolverIndex

    if g_LastOCRText = "" {
        ShowStatus("No OCR text to load", "fail")
        return false
    }

    text := g_LastOCRText
    param := Trim(param)
    parts := []

    ; Determine split method
    if param = "tab" {
        ; Split by tabs
        parts := StrSplit(text, "`t")
    } else if param = "line" || param = "lines" {
        ; Split by newlines
        parts := StrSplit(text, "`n")
    } else if IsNumber(param) {
        ; Split into N equal parts
        n := Integer(param)
        if n < 2
            n := 2
        partLen := Ceil(StrLen(text) / n)
        loop n {
            startPos := (A_Index - 1) * partLen + 1
            if startPos <= StrLen(text)
                parts.Push(SubStr(text, startPos, partLen))
        }
    } else if StrLen(param) = 1 {
        ; Split by delimiter character
        parts := StrSplit(text, param)
    } else {
        ; Default: split by spaces into words
        parts := StrSplit(text, " ")
    }

    ; Clean up empty parts
    g_OCRRevolver := []
    for part in parts {
        part := Trim(part)
        if part != ""
            g_OCRRevolver.Push(part)
    }

    g_OCRRevolverIndex := 0

    ShowStatus("OCR Revolver loaded: " . g_OCRRevolver.Length . " parts", "ok")
    return true
}

; Fire next part from OCR revolver
FireOCRRevolver() {
    global g_OCRRevolver, g_OCRRevolverIndex

    if g_OCRRevolver.Length = 0 {
        ShowStatus("OCR Revolver empty", "fail")
        return false
    }

    ; Get next part (cycle around)
    g_OCRRevolverIndex++
    if g_OCRRevolverIndex > g_OCRRevolver.Length
        g_OCRRevolverIndex := 1

    text := g_OCRRevolver[g_OCRRevolverIndex]

    ; Type or paste the text
    A_Clipboard := text
    Sleep(50)
    Send("^v")

    remaining := g_OCRRevolver.Length - g_OCRRevolverIndex
    ShowStatus("OCR Revolver " . g_OCRRevolverIndex . "/" . g_OCRRevolver.Length . ": " . SubStr(text, 1, 20), "ok")

    return true
}

; Parse region coordinates from string "x1,y1,x2,y2" or use saved region

; Check if OCR is available
CheckOCRAvailable() {
    try {
        testResult := OCR.FromRect(0, 0, 100, 100)
        return true
    } catch {
        MsgBox("OCR functionality requires Windows 10 version 1903 or later.`n`nPlease ensure:`n1. Windows is updated`n2. OCR.ahk is in the same folder`n3. You're running Windows 10/11", "OCR Not Available", "Icon!")
        return false
    }
}

ParseRegionCoords(target) {
    target := Trim(target)

    ; Empty or shortcuts
    if target = "" || target = "full" || target = "screen" {
        return Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)
    }

    ; Last/current
    if target = "current" || target = "last" {
        global g_LastOCRRegion
        if IsSet(g_LastOCRRegion) && g_LastOCRRegion.Count > 0
            return g_LastOCRRegion
        return Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)
    }

    ; Parse "x1,y1,x2,y2" format
    parts := StrSplit(target, ",")
    if parts.Length >= 4 {
        try {
            x1 := Integer(Trim(parts[1]))
            y1 := Integer(Trim(parts[2]))
            x2 := Integer(Trim(parts[3]))
            y2 := Integer(Trim(parts[4]))

            ; Validate
            if x2 <= x1 || y2 <= y1 {
                return false
            }

            return Map("x1", x1, "y1", y1, "x2", x2, "y2", y2)
        } catch {
            return false
        }
    }

    return false
}




; ═══════════════════════════════════════════════════════════════════════════════
; SETTINGS
; ═══════════════════════════════════════════════════════════════════════════════
; SETTINGS
; =============================================================================

SaveSettingsGUI(*) {
    global g_Settings, g_NotificationDefaults
    saved := MainGui.Submit(false)
    g_Settings["ClickDelay"] := Integer(saved.ClickDelay)
    g_Settings["TypeDelay"] := Integer(saved.TypeDelay)
    g_Settings["ActionDelay"] := Integer(saved.ActionDelay)
    g_Settings["PreActionDelay"] := Integer(saved.PreActionDelay)
    g_Settings["PostActionDelay"] := Integer(saved.PostActionDelay)
    g_Settings["DefaultDragTime"] := Integer(saved.DragTime)
    g_Settings["MaxRetries"] := Integer(saved.MaxRetries)
    g_Settings["WindowActivateTimeout"] := Integer(saved.WindowActivateTimeout)
    g_Settings["FindTextTolerance"] := Number(saved.FindTextTolerance)
    g_Settings["FindTextTimeout"] := Integer(saved.FindTextTimeout)
    g_Settings["TooltipDuration"] := Integer(saved.TooltipDuration)
    g_Settings["PreviewTooltipDuration"] := Integer(saved.PreviewTooltipDuration)
    g_Settings["FailsafeCheckCloseButton"] := saved.FailsafeCheckCloseButton
    g_Settings["AutoCapturePattern"] := saved.AutoCapPattern
    g_Settings["DefinitionModeAutoPattern"] := saved.DefModeAutoPattern

    ; Save notification settings
    global g_DebugMode, g_NotificationDismissible, g_NotificationTimeout
    g_DebugMode := saved.DebugMode
    g_NotificationDismissible := saved.NotifDismissible
    g_NotificationTimeout := Integer(saved.NotifTimeout) * 1000
    g_NotificationDefaults["timeout"] := Integer(saved.NotifTimeout)
    g_Settings["DebugMode"] := saved.DebugMode
    g_Settings["NotificationDismissible"] := saved.NotifDismissible
    g_Settings["NotificationTimeout"] := Integer(saved.NotifTimeout)

    SaveSettings()
    StatusBar.SetText("Settings saved!")
    ShowNotificationBasic("Settings Saved", "All settings have been updated", 2000, "success")
}

ResetSettingsGUI(*) {
    global g_Settings
    g_Settings := Map(
        "ClickDelay", 100, "TypeDelay", 50, "ActionDelay", 150, "DefaultDragTime", 300,
        "DateFormat", "MM/dd/yyyy", "ShowActionTooltips", true, "TooltipDuration", 1500,
        "MarkerOffsetX", -12, "MarkerOffsetY", -15, "MaxRetries", 3, "VerifyTimeout", 2000,
        "VerifyInterval", 100, "PreActionDelay", 50, "PostActionDelay", 100,
        "WindowActivateTimeout", 3000, "FindTextTolerance", 0.1, "FindTextTimeout", 5000,
        "AutoCapturePattern", true, "FailsafeCheckCloseButton", true, "DefinitionModeAutoPattern", true,
        "PreviewTooltipDuration", 3000
    )
    SaveSettings()
    StatusBar.SetText("Reset - restart to apply")
}


; ═══════════════════════════════════════════════════════════════════════════════
; GLOBAL HOTKEYS
; ═══════════════════════════════════════════════════════════════════════════════
; GLOBAL HOTKEYS
; =============================================================================

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

; Clipboard Revolver hotkeys
^b::LoadRevolverFromSelection()   ; Copy + Parse + Load
^+b::FireAllShots()               ; Fire all shots (paste + Tab...)
; Smart Clipboard Revolver with Bins (NEW v4.1)
^!b::LoadRevolverItem(A_Clipboard)  ; Ctrl+Alt+B = Load to smart bins (shows selector)
^!+b::PasteFromBins()               ; Ctrl+Alt+Shift+B = Paste from bins (top bin first)

^!n::OpenNotepadPopup()  ; Ctrl+Alt+N = Open notepad popup
#b::ShowBinSelector("")  ; Ctrl+Alt+B = Open bin selector
^!i::ExecuteIdleMouse("0")  ; Ctrl+Alt+I = Idle mouse indefinitely

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
UpdateSpoolMasterStatus()  ; Update spool status display
RefreshHotstringList()  ; V5.0: Populate hotstring list
RefreshTriggersLV()  ; V5.1: Populate triggers list

RefreshCoordLV() {
    global g_Coordinates, CoordLV
    CoordLV.Delete()
    for n, c in g_Coordinates
        CoordLV.Add(, n, c["x"], c["y"], c["endX"], c["endY"], c["type"])
}

RefreshRulesLV() {
    global g_ExtractionRules, RulesLV
    RulesLV.Delete()
    for r in g_ExtractionRules
        RulesLV.Add(, r["name"], r["pattern"], "")
}

StatusBar.SetText("Ready | CAPSLOCK=Definition Mode | Ctrl+B=Load | Ctrl+Shift+B=Fire | ESC=Abort")


; ═══════════════════════════════════════════════════════════════════════════════
; V5.0: INITIALIZE INSTRUCTIONS FILE
; ═══════════════════════════════════════════════════════════════════════════════

InitializeInstructions() {
    global INSTRUCTIONS_FILE
    if FileExist(INSTRUCTIONS_FILE)
        return

    instructions := "
(
═══════════════════════════════════════════════════════════════════════════════
MACRO AUTOMATOR v5.0 - ACTION INSTRUCTIONS & EXAMPLES
═══════════════════════════════════════════════════════════════════════════════

This file provides detailed instructions for all action types available in
MacroAutomator. Each action includes description, parameters, examples, and
common error solutions.

═══════════════════════════════════════════════════════════════════════════════
CLICK ACTIONS
═══════════════════════════════════════════════════════════════════════════════

Click - Mouse click at coordinate
  Required: coord (name or x,y)
  Optional: button (left|right|middle), count (1-10)
  Example: coord=MyButton, button=left, count=1
  Errors: Coordinate not found - check name exists

ClickImage - Find and click image pattern
  Required: pattern (saved pattern name)
  Optional: button, variation (0-100 tolerance)
  Example: pattern=SubmitBtn, variation=15
  Errors: Pattern not found - increase variation or recapture

Drag - Click and drag between points
  Required: from, to (coordinate names)
  Optional: button, speed (1-100)
  Example: from=Start, to=End, speed=5

═══════════════════════════════════════════════════════════════════════════════
KEYBOARD ACTIONS
═══════════════════════════════════════════════════════════════════════════════

Send - Send keyboard input
  Required: text (text or key codes)
  Optional: raw (true/false)
  Example: text=Hello{Enter}, text=^c (Ctrl+C)
  Keys: {Enter} {Tab} {Esc} {Space} {Up} {Down} {F1}-{F12}
  Modifiers: ^ = Ctrl, + = Shift, ! = Alt, # = Win

Type - Type text with delays
  Required: text
  Optional: speed (ms between chars, default 10)
  Example: text=user@email.com, speed=50

═══════════════════════════════════════════════════════════════════════════════
OCR ACTIONS
═══════════════════════════════════════════════════════════════════════════════

OCR - Extract text from screen region
  Required: region (coordinate name with width/height)
  Optional: language (en-us), scale (1.0-3.0), variable (name to store)
  Example: region=TextArea, scale=1.5, variable=ExtractedText
  Errors: No text detected - increase scale, check region has text
         OCR library not found - ensure OCR.ahk in script folder

OCRClick - Find and click text via OCR
  Required: text, region
  Optional: button, partial (true/false), caseSensitive
  Example: text=Submit, region=ButtonArea, partial=true
  Errors: Text not found - verify text visible and readable
         Multiple matches - use more specific text

WaitForText - Wait until text appears
  Required: text, region
  Optional: timeout (seconds, default 30), interval (ms, default 500)
  Example: text=Complete, region=StatusArea, timeout=60

═══════════════════════════════════════════════════════════════════════════════
WAIT & TIMING
═══════════════════════════════════════════════════════════════════════════════

Wait - Pause execution
  Required: duration (milliseconds)
  Example: duration=1000 (1 second)

WaitForImage - Wait for pattern to appear
  Required: pattern
  Optional: timeout (seconds), variation
  Example: pattern=LoadingComplete, timeout=60

WaitForPixel - Wait for pixel color
  Required: coord, color (0xRRGGBB format)
  Optional: timeout, variation (color tolerance)
  Example: coord=StatusLight, color=0x00FF00, variation=10

═══════════════════════════════════════════════════════════════════════════════
COMMON ERROR SOLUTIONS
═══════════════════════════════════════════════════════════════════════════════

'Coordinate not found' - Verify coordinate name spelling, check it exists
'OCR failed' - Increase scale to 1.5-2.0, ensure text is visible
'Pattern not found' - Recapture pattern, increase variation tolerance
'Timeout exceeded' - Increase timeout value, verify expected state occurs
'OCR library not available' - Place OCR.ahk in script directory
'Invalid parameter' - Check parameter spelling and value format

═══════════════════════════════════════════════════════════════════════════════
PARAMETER FORMATS
═══════════════════════════════════════════════════════════════════════════════

Coordinates: 'MyCoord' (name) or '500,300' (x,y) or '100,100,400,300' (x,y,w,h)
Colors: '0xRRGGBB' (hex format, e.g. 0xFF0000 for red)
Time: milliseconds as number (1000 = 1 second)
Boolean: true/false or 1/0 or yes/no
Variables: Letters, numbers, underscores only (no spaces or special chars)
)"

    try {
        FileAppend(instructions, INSTRUCTIONS_FILE, "UTF-8")
    } catch as err {
        MsgBox("Failed to create instructions file: " . err.Message)
    }
}

InitializeInstructions()


; ═══════════════════════════════════════════════════════════════════════════════
; V5.0: ENHANCED NOTIFICATION SYSTEM
; ═══════════════════════════════════════════════════════════════════════════════

LoadNotificationSchedule() {
    global g_NotificationSchedule, SCHEDULE_FILE

    if !FileExist(SCHEDULE_FILE)
        return

    try {
        content := FileRead(SCHEDULE_FILE, "UTF-8")
        for line in StrSplit(content, "`n", "`r") {
            if line = "" || SubStr(line, 1, 1) = ";"
                continue

            parts := StrSplit(line, "|")
            if parts.Length >= 3 {
                timeSlot := parts[1]
                message := parts[2]
                enabled := (parts[3] = "1")

                g_NotificationSchedule[timeSlot] := Map(
                    "message", message,
                    "enabled", enabled,
                    "lastShown", ""
                )
            }
        }
    }
}

SaveNotificationSchedule() {
    global g_NotificationSchedule, SCHEDULE_FILE

    output := "; Notification Schedule (TimeSlot|Message|Enabled)`n"

    for timeSlot, data in g_NotificationSchedule {
        output .= timeSlot . "|" . data["message"] . "|" . (data["enabled"] ? "1" : "0") . "`n"
    }

    try {
        if FileExist(SCHEDULE_FILE)
            FileDelete(SCHEDULE_FILE)
        FileAppend(output, SCHEDULE_FILE, "UTF-8")
    }
}

CheckScheduledNotifications() {
    global g_NotificationSchedule, g_NotificationSettings

    currentTime := FormatTime(A_Now, "HH:mm")
    startTime := g_NotificationSettings["startTime"]
    endTime := g_NotificationSettings["endTime"]

    ; Convert times to minutes for proper comparison
    currentParts := StrSplit(currentTime, ":")
    currentMinutes := currentParts[1] * 60 + currentParts[2]

    startParts := StrSplit(startTime, ":")
    startMinutes := startParts[1] * 60 + startParts[2]

    endParts := StrSplit(endTime, ":")
    endMinutes := endParts[1] * 60 + endParts[2]

    if currentMinutes < startMinutes || currentMinutes > endMinutes
        return

    blockSize := g_NotificationSettings["blockSize"]
    currentParts := StrSplit(currentTime, ":")
    currentMinutes := currentParts[1] * 60 + currentParts[2]

    roundedMinutes := Floor(currentMinutes / blockSize) * blockSize
    roundedHour := Floor(roundedMinutes / 60)
    roundedMin := Mod(roundedMinutes, 60)
    roundedTime := Format("{:02d}:{:02d}", roundedHour, roundedMin)

    if g_NotificationSchedule.Has(roundedTime) {
        schedule := g_NotificationSchedule[roundedTime]
        if schedule["enabled"] && schedule["lastShown"] != A_YYYY A_MM A_DD {
            ShowScheduledNotification(schedule["message"])
            schedule["lastShown"] := A_YYYY A_MM A_DD
        }
    }
}

ShowScheduledNotification(message) {
    ShowNotificationBasic("Scheduled Reminder", message, 8000)
}

ShowActionNotification(actionType, status, details := "", errorInfo := "") {
    global g_NotificationSettings, g_ActionErrors, g_NotificationHistory, g_DebugMode

    ; In debug mode, show all notifications; otherwise respect settings
    if !g_DebugMode && !g_NotificationSettings["showErrors"] && status = "error"
        return

    title := "Step: " . actionType

    message := ""
    if status = "error" {
        message .= details
        if errorInfo != ""
            message .= "`n`nError: " . errorInfo

        if !g_ActionErrors.Has(actionType)
            g_ActionErrors[actionType] := []
        g_ActionErrors[actionType].Push(Map(
            "time", A_Now,
            "details", details,
            "error", errorInfo
        ))
    }
    else if status = "success" {
        message .= details
    }
    else if status = "warning" {
        message .= details
    }

    g_NotificationHistory.Push(Map(
        "time", A_Now,
        "action", actionType,
        "status", status,
        "message", message
    ))

    ; All notifications dismissible by default, success can auto-dismiss in 3 seconds if not in debug mode
    timeout := (status = "success" && !g_DebugMode) ? 3000 : 0
    ShowNotificationBasic(title, message, timeout, status)
}

GetActionExamples(actionType) {
    examples := Map()

    examples["Click"] := "Example: coord=MyButton, button=left, count=1"
    examples["ClickImage"] := "Example: pattern=SubmitBtn, variation=15"
    examples["OCR"] := "Example: region=TextArea, language=en-us, scale=1.5"
    examples["OCRClick"] := "Example: text=Submit, region=ButtonArea, partial=true"
    examples["Send"] := "Example: text=Hello{Enter}, raw=false"
    examples["Wait"] := "Example: duration=1000"
    examples["Drag"] := "Example: from=Start, to=End, speed=5"
    examples["WaitForText"] := "Example: text=Complete, region=Status, timeout=60"
    examples["WaitForImage"] := "Example: pattern=Loading, timeout=30"
    examples["SetVariable"] := "Example: name=MyVar, value=test"

    if examples.Has(actionType)
        return "📝 Example usage:`n   " . examples[actionType]

    return ""
}

ReportOCRError(operation, region, details := "") {
    errorMsg := "OCR Operation: " . operation . "`n"
    if IsObject(region) && region.Has("x1") {
        regionText := region["x1"] . "," . region["y1"] . "," . region["x2"] . "," . region["y2"]
    } else if IsObject(region) && region.Has("x") {
        regionText := region["x"] . "," . region["y"] . "," . region["w"] . "," . region["h"]
    } else {
        regionText := String(region)
    }
    errorMsg .= "Region: " . regionText . "`n"

    reasons := []

    if !IsOCRAvailable()
        reasons.Push("OCR.ahk library not found or not loaded")

    if IsObject(region) {
        if region.Has("w") && region.Has("h") && (region["w"] <= 0 || region["h"] <= 0)
            reasons.Push("Invalid region dimensions (width/height must be > 0)")
        else if region.Has("x1") && region.Has("x2") && (region["x2"] <= region["x1"] || region["y2"] <= region["y1"])
            reasons.Push("Invalid region dimensions (width/height must be > 0)")
    }

    if details != ""
        reasons.Push(details)

    if reasons.Length = 0
        reasons.Push("No text detected in specified region")

    errorMsg .= "`nPossible causes:`n"
    for reason in reasons
        errorMsg .= "  • " . reason . "`n"

    errorMsg .= "`nSolutions:`n"
    errorMsg .= "  • Verify OCR.ahk is in script directory`n"
    errorMsg .= "  • Increase scale parameter (try 1.5-2.0)`n"
    errorMsg .= "  • Ensure region contains visible text`n"
    errorMsg .= "  • Check region coordinates are correct`n"
    errorMsg .= "  • Verify text is not obscured or too small"

    ShowActionNotification("OCR", "error", "OCR failed", errorMsg)
    LogDiagnostic(errorMsg, "OCR " . operation)

    global g_LastActionError := errorMsg
    return false
}

; IsOCRAvailable() {
;     try {
;         return IsFunc("OCR") || IsSet(OCR)
;     }
;     return false
; }
IsOCRAvailable() {
    try return FileExist(OCR.HelperPath) != ""
    return false
}



ReportImageError(operation, patternName, details := "") {
    errorMsg := "Image Operation: " . operation . "`n"
    errorMsg .= "Pattern: " . patternName . "`n"

    reasons := []

    global g_Patterns
    if !g_Patterns.Has(patternName)
        reasons.Push("Pattern '" . patternName . "' not found in saved patterns")

    if details != ""
        reasons.Push(details)

    if reasons.Length = 0
        reasons.Push("Pattern not found on screen")

    errorMsg .= "`nPossible causes:`n"
    for reason in reasons
        errorMsg .= "  • " . reason . "`n"

    errorMsg .= "`nSolutions:`n"
    errorMsg .= "  • Verify pattern name is spelled correctly`n"
    errorMsg .= "  • Recapture pattern with current screen state`n"
    errorMsg .= "  • Increase variation tolerance`n"
    errorMsg .= "  • Ensure target is visible on screen`n"
    errorMsg .= "  • Check pattern file exists in data\patterns\"

    ShowActionNotification("Image Search", "error", "Pattern search failed", errorMsg)

    global g_LastActionError := errorMsg
    return false
}

ShowNotificationBasic(title, message, timeout := 0, status := "info", copyData := "", stepIndex := 0) {
    global g_NotificationStack, g_NotificationDismissible, g_NotificationTimeout, g_CurrentSequenceSteps

    ; Use global settings if timeout not specified
    if timeout = 0 && !g_NotificationDismissible
        timeout := g_NotificationTimeout

    ; Create notification GUI with proper drag capability
    notifGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "Notification")

    ; Color based on status
    bgColor := "0x1a1a1a"
    topBarColor := "0x2a2a2a"  ; Lighter for top bar
    if status = "success" {
        bgColor := "0x0d3d0d"  ; Dark green
        topBarColor := "0x1d5d1d"  ; Lighter green for top bar
    } else if status = "error" {
        bgColor := "0x3d0d0d"  ; Dark red
        topBarColor := "0x5d1d1d"  ; Lighter red for top bar
    } else if status = "warning" {
        bgColor := "0x3d3d0d"  ; Dark yellow
        topBarColor := "0x5d5d1d"  ; Lighter yellow for top bar
    }

    notifGui.BackColor := bgColor

    ; Status icon
    statusIcon := "⬤"
    if status = "success"
        statusIcon := "✓"
    else if status = "error"
        statusIcon := "✗"
    else if status = "warning"
        statusIcon := "⚠"

    ; Top bar with lighter background (draggable area)
    notifGui.SetFont("s10 cWhite Bold", "Segoe UI")
    topBar := notifGui.Add("Text", "x0 y0 w320 h30 Background" . topBarColor . " Center", "")

    ; Title on top bar
    titleCtrl := notifGui.Add("Text", "x10 y7 w250 cWhite Background" . topBarColor, statusIcon . " " . title)

    ; Add mute/unmute toggle button if this is a step notification
    if stepIndex > 0 {
        notifGui.SetFont("s9 Bold", "Segoe UI")
        muteBtn := notifGui.Add("Text", "x270 y5 w40 h20 cWhite Background" . topBarColor . " Center Border", "🔔")
        muteBtn.stepIndex := stepIndex
        muteBtn.notifGui := notifGui

        ; Check if this step is muted
        if stepIndex <= g_CurrentSequenceSteps.Length {
            step := g_CurrentSequenceSteps[stepIndex]
            if step.Has("notificationMuted") && step["notificationMuted"] {
                muteBtn.Text := "🔕"
            }
        }

        muteBtn.OnEvent("Click", ToggleStepNotification)
    }

    ; Add scrollable message (use Edit for scrolling)
    notifGui.SetFont("s9 cWhite Norm", "Segoe UI")
    messageLines := StrSplit(message, "`n")
    messageHeight := Min(messageLines.Length * 18, 200)  ; Max 200px height
    msgCtrl := notifGui.Add("Edit", "x10 y35 w300 h" . messageHeight . " cWhite Background" . bgColor . " ReadOnly -E0x200 Multi", message)

    yPos := 35 + messageHeight + 5

    ; Add copy button if copyData is provided
    if copyData != "" {
        notifGui.SetFont("s8", "Segoe UI")
        copyBtn := notifGui.Add("Button", "x10 y" . yPos . " w80 h22", "📋 Copy")
        copyBtn.OnEvent("Click", (*) => CopyNotificationData(copyData))
        yPos += 27
    }

    ; Add dismiss instruction
    notifGui.SetFont("s8 c808080", "Segoe UI")
    dismissCtrl := notifGui.Add("Text", "x10 y" . yPos . " w300 Background" . bgColor, "Drag top bar to move | Right-click to dismiss")

    ; Enable dragging on top bar
    topBar.OnEvent("Click", (*) => PostMessage(0xA1, 2, 0, , notifGui.Hwnd))
    titleCtrl.OnEvent("Click", (*) => PostMessage(0xA1, 2, 0, , notifGui.Hwnd))

    ; Right-click or double-click to dismiss
    for ctrl in notifGui {
        try ctrl.OnEvent("DoubleClick", (*) => RemoveNotification(notifGui))
        try ctrl.OnEvent("ContextMenu", (*) => RemoveNotification(notifGui))
    }

    notifGui.OnEvent("Close", (*) => RemoveNotification(notifGui))

    ; Add to stack
    g_NotificationStack.Push(notifGui)
    RepositionNotifications()

    ; Auto-dismiss timer
    if timeout > 0
        SetTimer(() => RemoveNotification(notifGui), -timeout)

    return notifGui
}

ToggleStepNotification(ctrl, *) {
    global g_CurrentSequenceSteps

    stepIndex := ctrl.stepIndex
    if stepIndex <= 0 || stepIndex > g_CurrentSequenceSteps.Length
        return

    step := g_CurrentSequenceSteps[stepIndex]

    ; Toggle muted state
    if step.Has("notificationMuted") && step["notificationMuted"] {
        step["notificationMuted"] := false
        ctrl.Text := "🔔"
        ShowStatus("Step " . stepIndex . " notifications enabled", "ok")
    } else {
        step["notificationMuted"] := true
        ctrl.Text := "🔕"
        ShowStatus("Step " . stepIndex . " notifications muted", "ok")
    }

    ; Close this notification
    try ctrl.notifGui.Destroy()
}

CopyNotificationData(data) {
    A_Clipboard := data
    ShowStatus("Copied to clipboard: " . SubStr(data, 1, 50) . (StrLen(data) > 50 ? "..." : ""), "ok")
}

; Drag notification is no longer needed - handled by title click

RemoveNotification(notifGui) {
    global g_NotificationStack

    try {
        if !notifGui
            return

        ; Remove from stack
        for i, gui in g_NotificationStack {
            if gui = notifGui {
                g_NotificationStack.RemoveAt(i)
                break
            }
        }

        notifGui.Destroy()
        RepositionNotifications()
    }
}

RepositionNotifications() {
    global g_NotificationStack

    if g_NotificationStack.Length = 0
        return

    screenW := A_ScreenWidth
    screenH := A_ScreenHeight
    guiW := 320
    spacing := 10
    bottomMargin := 60

    currentY := screenH - bottomMargin

    ; Stack from bottom up (newest at bottom)
    i := g_NotificationStack.Length
    while i >= 1 {
        try {
            notifGui := g_NotificationStack[i]

            ; Get actual GUI height
            notifGui.GetPos(,, &actualW, &actualH)
            guiH := actualH > 0 ? actualH : 180

            xPos := screenW - guiW - 20
            currentY -= guiH

            ; Ensure notification stays on screen
            if currentY < 10 {
                ; If we run out of vertical space, start a new column to the left
                xPos -= (guiW + spacing)
                currentY := screenH - bottomMargin - guiH
            }

            notifGui.Show("x" . xPos . " y" . currentY . " w" . guiW . " NoActivate")
            currentY -= spacing
        }
        i--
    }
}

ClearAllNotifications(*) {
    global g_NotificationStack

    for notifGui in g_NotificationStack {
        try notifGui.Destroy()
    }

    g_NotificationStack := []
}

; Global variable for notification GUI
global g_NotificationGui := ""

StartNotificationTimer() {
    LoadNotificationSchedule()
    SetTimer(CheckScheduledNotifications, 60000)
}


; ═══════════════════════════════════════════════════════════════════════════════
; V5.0: HOTSTRING MANAGEMENT
; ═══════════════════════════════════════════════════════════════════════════════

LoadHotstrings() {
    global g_Hotstrings, HOTSTRINGS_FILE

    if !FileExist(HOTSTRINGS_FILE)
        return

    try {
        content := FileRead(HOTSTRINGS_FILE, "UTF-8")
        for line in StrSplit(content, "`n", "`r") {
            if line = "" || SubStr(line, 1, 1) = ";"
                continue

            parts := StrSplit(line, "|")
            if parts.Length >= 3 {
                trigger := parts[1]
                replacement := parts[2]
                options := parts[3]
                enabled := parts.Length >= 4 ? (parts[4] = "1") : true

                g_Hotstrings[trigger] := Map(
                    "replacement", replacement,
                    "options", options,
                    "enabled", enabled
                )

                if enabled && g_HotstringActive
                    ActivateHotstring(trigger, replacement, options)
            }
        }
    }
}

SaveHotstrings() {
    global g_Hotstrings, HOTSTRINGS_FILE

    output := "; Hotstring definitions (Trigger|Replacement|Options|Enabled)`n"
    output .= "; Options: C=CaseSensitive, *=NoEndChar, ?=TriggerInWord, B=NoBackspace, O=OmitEndChar`n`n"

    for trigger, data in g_Hotstrings {
        output .= trigger . "|" . data["replacement"] . "|" . data["options"] . "|" . (data["enabled"] ? "1" : "0") . "`n"
    }

    try {
        if FileExist(HOTSTRINGS_FILE)
            FileDelete(HOTSTRINGS_FILE)
        FileAppend(output, HOTSTRINGS_FILE, "UTF-8")
    }
}

ActivateHotstring(trigger, replacement, options := "") {
    try {
        Hotstring("::" . trigger, replacement, options)
        return true
    } catch as err {
        ShowActionNotification("Hotstring", "error", "Failed to activate: " . trigger, err.Message)
        return false
    }
}

DeactivateHotstring(trigger) {
    try {
        Hotstring("::" . trigger, "Off")
        return true
    } catch {
        return false
    }
}

ToggleAllHotstrings(*) {
    global g_Hotstrings, g_HotstringActive, HotstringMasterToggle

    g_HotstringActive := HotstringMasterToggle.Value

    for trigger, data in g_Hotstrings {
        if data["enabled"] {
            if g_HotstringActive
                ActivateHotstring(trigger, data["replacement"], data["options"])
            else
                DeactivateHotstring(trigger)
        }
    }
}

RefreshHotstringList() {
    global g_Hotstrings, HotstringLV

    HotstringLV.Delete()

    for trigger, data in g_Hotstrings {
        HotstringLV.Add("",
            data["enabled"] ? "✓" : "",
            trigger,
            data["replacement"],
            data["options"]
        )
    }
}

AddHotstring(*) {
    global g_Hotstrings, MainGui

    hsGui := Gui("+Owner" . MainGui.Hwnd, "Add Hotstring")
    hsGui.SetFont("s9", "Segoe UI")

    hsGui.Add("Text", "x10 y10", "Trigger Text (what you type):")
    triggerEdit := hsGui.Add("Edit", "x10 y30 w400")

    hsGui.Add("Text", "x10 y60", "Replacement Text (what appears):")
    replacementEdit := hsGui.Add("Edit", "x10 y80 w400 h100 +Multi")

    hsGui.Add("GroupBox", "x10 y190 w400 h120", "Options")

    caseSensCheck := hsGui.Add("CheckBox", "x20 y210", "Case Sensitive (C)")
    noEndCharCheck := hsGui.Add("CheckBox", "x20 y235", "No end character required (*)")
    triggerInWordCheck := hsGui.Add("CheckBox", "x20 y260", "Trigger inside words (?)")
    noBackspaceCheck := hsGui.Add("CheckBox", "x220 y210", "No auto-backspace (B)")
    omitEndCharCheck := hsGui.Add("CheckBox", "x220 y235", "Omit end character (O)")
    textModeCheck := hsGui.Add("CheckBox", "x220 y260", "Text mode (T)")

    enableCheck := hsGui.Add("CheckBox", "x10 y320 Checked", "Enable immediately")

    hsGui.Add("Button", "x10 y350 w100", "Save").OnEvent("Click", SaveNewHotstring)
    hsGui.Add("Button", "x120 y350 w100", "Cancel").OnEvent("Click", (*) => hsGui.Destroy())

    SaveNewHotstring(*) {
        trigger := triggerEdit.Value
        replacement := replacementEdit.Value

        if trigger = "" || replacement = "" {
            MsgBox("Both trigger and replacement are required")
            return
        }

        opts := ""
        if caseSensCheck.Value
            opts .= "C"
        if noEndCharCheck.Value
            opts .= "*"
        if triggerInWordCheck.Value
            opts .= "?"
        if noBackspaceCheck.Value
            opts .= "B"
        if omitEndCharCheck.Value
            opts .= "O"
        if textModeCheck.Value
            opts .= "T"

        enabled := enableCheck.Value

        g_Hotstrings[trigger] := Map(
            "replacement", replacement,
            "options", opts,
            "enabled", enabled
        )

        if enabled && g_HotstringActive
            ActivateHotstring(trigger, replacement, opts)

        SaveHotstrings()
        RefreshHotstringList()
        hsGui.Destroy()

        ShowNotificationBasic("Hotstring Added", "Hotstring '" . trigger . "' has been created", 3000)
    }

    hsGui.Show("w420 h390")
}

EditHotstring(lv, row) {
    global g_Hotstrings, MainGui

    if !row
        row := lv.GetNext()

    if !row {
        MsgBox("Please select a hotstring to edit")
        return
    }

    trigger := lv.GetText(row, 2)

    if !g_Hotstrings.Has(trigger) {
        MsgBox("Hotstring not found")
        return
    }

    data := g_Hotstrings[trigger]

    hsGui := Gui("+Owner" . MainGui.Hwnd, "Edit Hotstring")
    hsGui.SetFont("s9", "Segoe UI")

    hsGui.Add("Text", "x10 y10", "Trigger Text: " . trigger)

    hsGui.Add("Text", "x10 y40", "Replacement Text:")
    replacementEdit := hsGui.Add("Edit", "x10 y60 w400 h100 +Multi", data["replacement"])

    hsGui.Add("GroupBox", "x10 y170 w400 h120", "Options")

    opts := data["options"]
    caseSensCheck := hsGui.Add("CheckBox", "x20 y190", "Case Sensitive (C)")
    if InStr(opts, "C")
        caseSensCheck.Value := true

    noEndCharCheck := hsGui.Add("CheckBox", "x20 y215", "No end character required (*)")
    if InStr(opts, "*")
        noEndCharCheck.Value := true

    triggerInWordCheck := hsGui.Add("CheckBox", "x20 y240", "Trigger inside words (?)")
    if InStr(opts, "?")
        triggerInWordCheck.Value := true

    noBackspaceCheck := hsGui.Add("CheckBox", "x220 y190", "No auto-backspace (B)")
    if InStr(opts, "B")
        noBackspaceCheck.Value := true

    omitEndCharCheck := hsGui.Add("CheckBox", "x220 y215", "Omit end character (O)")
    if InStr(opts, "O")
        omitEndCharCheck.Value := true

    textModeCheck := hsGui.Add("CheckBox", "x220 y240", "Text mode (T)")
    if InStr(opts, "T")
        textModeCheck.Value := true

    enableCheck := hsGui.Add("CheckBox", "x10 y300", "Enabled")
    enableCheck.Value := data["enabled"]

    hsGui.Add("Button", "x10 y330 w100", "Save").OnEvent("Click", SaveEditedHotstring)
    hsGui.Add("Button", "x120 y330 w100", "Cancel").OnEvent("Click", (*) => hsGui.Destroy())

    SaveEditedHotstring(*) {
        replacement := replacementEdit.Value

        if replacement = "" {
            MsgBox("Replacement text is required")
            return
        }

        if data["enabled"] && g_HotstringActive
            DeactivateHotstring(trigger)

        newOpts := ""
        if caseSensCheck.Value
            newOpts .= "C"
        if noEndCharCheck.Value
            newOpts .= "*"
        if triggerInWordCheck.Value
            newOpts .= "?"
        if noBackspaceCheck.Value
            newOpts .= "B"
        if omitEndCharCheck.Value
            newOpts .= "O"
        if textModeCheck.Value
            newOpts .= "T"

        enabled := enableCheck.Value

        g_Hotstrings[trigger] := Map(
            "replacement", replacement,
            "options", newOpts,
            "enabled", enabled
        )

        if enabled && g_HotstringActive
            ActivateHotstring(trigger, replacement, newOpts)

        SaveHotstrings()
        RefreshHotstringList()
        hsGui.Destroy()

        ShowNotificationBasic("Hotstring Updated", "Hotstring '" . trigger . "' has been updated", 3000)
    }

    hsGui.Show("w420 h370")
}

EditHotstringFromBtn(*) {
    global HotstringLV
    row := HotstringLV.GetNext()
    if row
        EditHotstring(HotstringLV, row)
    else
        MsgBox("Please select a hotstring to edit")
}

DeleteHotstring(*) {
    global g_Hotstrings, HotstringLV

    row := HotstringLV.GetNext()
    if !row {
        MsgBox("Please select a hotstring to delete")
        return
    }

    trigger := HotstringLV.GetText(row, 2)

    result := MsgBox("Delete hotstring '" . trigger . "'?", "Confirm Delete", "YesNo Icon?")
    if result != "Yes"
        return

    if g_Hotstrings.Has(trigger) {
        if g_Hotstrings[trigger]["enabled"]
            DeactivateHotstring(trigger)

        g_Hotstrings.Delete(trigger)
        SaveHotstrings()
        RefreshHotstringList()

        ShowNotificationBasic("Hotstring Deleted", "Hotstring '" . trigger . "' has been removed", 3000)
    }
}

ToggleHotstring(*) {
    global g_Hotstrings, HotstringLV, g_HotstringActive

    row := HotstringLV.GetNext()
    if !row {
        MsgBox("Please select a hotstring")
        return
    }

    trigger := HotstringLV.GetText(row, 2)

    if g_Hotstrings.Has(trigger) {
        data := g_Hotstrings[trigger]
        data["enabled"] := !data["enabled"]

        if data["enabled"] && g_HotstringActive
            ActivateHotstring(trigger, data["replacement"], data["options"])
        else
            DeactivateHotstring(trigger)

        SaveHotstrings()
        RefreshHotstringList()
    }
}

TestHotstring(*) {
    global HotstringLV

    row := HotstringLV.GetNext()
    if !row {
        MsgBox("Please select a hotstring to test")
        return
    }

    trigger := HotstringLV.GetText(row, 2)
    replacement := HotstringLV.GetText(row, 3)

    testGui := Gui("+AlwaysOnTop", "Hotstring Test")
    testGui.SetFont("s9", "Segoe UI")

    testGui.Add("Text", "x10 y10", "Type the trigger text in the box below to test:")
    testGui.Add("Text", "x10 y30", "Trigger: " . trigger)
    testGui.Add("Text", "x10 y50", "Replacement: " . replacement)

    testEdit := testGui.Add("Edit", "x10 y80 w400 h100 +Multi")

    testGui.Add("Button", "x10 y190 w100", "Close").OnEvent("Click", (*) => testGui.Destroy())

    testGui.Show("w420 h230")
}


; ═══════════════════════════════════════════════════════════════════════════════
; V5.0: SHOW INSTRUCTIONS FILE
; ═══════════════════════════════════════════════════════════════════════════════

ShowInstructionsFile(*) {
    global INSTRUCTIONS_FILE
    if FileExist(INSTRUCTIONS_FILE) {
        Run(INSTRUCTIONS_FILE)
    } else {
        MsgBox("Instructions file not found. Recreating...")
        InitializeInstructions()
        Run(INSTRUCTIONS_FILE)
    }
}


; ═══════════════════════════════════════════════════════════════════════════════
; V5.1: Extract all variables created in current sequence
GetSequenceVariables() {
    global g_CurrentSequenceSteps

    vars := []
    varSet := Map()  ; Use map to avoid duplicates

    for step in g_CurrentSequenceSteps {
        action := step["action"]
        target := step.Has("target") ? step["target"] : ""
        param := step.Has("param") ? step["param"] : ""

        ; v7 variable actions create their variable in the Target field.
        if (action = "Set Variable" || action = "Grab Clipboard") && Trim(target) != "" {
            varName := Trim(target)
            if RegExMatch(varName, "^[A-Za-z_][A-Za-z0-9_]*$") && !varSet.Has(varName) {
                vars.Push(varName)
                varSet[varName] := true
            }
        }

        ; Check OCR Region creating variables with var:name
        if action = "OCR Region" && InStr(param, "var:") {
            varName := Trim(SubStr(param, InStr(param, "var:") + 4))
            ; Remove any additional parameters after the variable name
            if InStr(varName, " ")
                varName := SubStr(varName, 1, InStr(varName, " ") - 1)
            if InStr(varName, ",")
                varName := SubStr(varName, 1, InStr(varName, ",") - 1)
            if varName != "" && !varSet.Has(varName) {
                vars.Push(varName)
                varSet[varName] := true
            }
        }

        ; Check OCR variable actions (new separate field or legacy combined format)
        if (action = "Grab OCR to Var" || action = "OCR Full Screen to Var") && Trim(param) != "" {
            parts := StrSplit(param, ",")
            if parts.Length >= 1 {
                varName := Trim(parts[1])
                ; Remove $ if present
                if SubStr(varName, 1, 1) = "$"
                    varName := SubStr(varName, 2)
                ; Remove $var. prefix if present
                if SubStr(varName, 1, 5) = "var."
                    varName := SubStr(varName, 6)
                if varName != "" && !varSet.Has(varName) {
                    vars.Push(varName)
                    varSet[varName] := true
                }
            }
        }
    }

    return vars
}


; V5.1: PARAMETER VALIDATION & LIVE HINTS
; ═══════════════════════════════════════════════════════════════════════════════

InitializeParameterValidators() {
    global g_ParamValidators, g_ParamHints

    g_ParamHints["Click"] := "1-10 for click count"
    g_ParamHints["OCR Region"] := "var:name to create variable | copy for clipboard | Check Choices for existing vars"
    g_ParamHints["OCR Click"] := "Text to find and click"
    g_ParamHints["Set Clipboard"] := "Text or $var.name | Check Choices dropdown for available variables!"
    g_ParamHints["Wait"] := "Milliseconds (1000 = 1 second)"
    g_ParamHints["Grab OCR to Var"] := "Variable name only; choose the OCR area in the Position field"
    g_ParamHints["OCR Full Screen to Var"] := "Plain variable name; captures the whole primary screen and draws yellow word boxes"
    g_ParamHints["Use Var Paste"] := "Text with $var.name | Check Choices dropdown for variables!"
    g_ParamHints["Send Keys"] := "^c={Ctrl+C}, +a={Shift+A}, !f={Alt+F}"
    g_ParamHints["Show Notification"] := "Title,Message,Timeout | Use $var.name for variables"
    g_ParamHints["Set Variable"] := "Value to store; $var.name substitutions are supported"
    g_ParamHints["If Contains"] := "Text to find; false skips the next enabled step"
    g_ParamHints["If Variable"] := "operator,value (examples: =,ready or >=,5)"
    g_ParamHints["Run Sequence"] := "Exact name of a saved workflow"
    g_ParamHints["Format Clipboard"] := "Preset name or a custom template containing {clip}"
    g_ParamHints["Extract from Clipboard"] := "between:start|end, field:delimiter|index, or regex:pattern"
}

ValidateStepParameters(action, target, param) {
    errors := []
    spec := GetWorkflowActionSpec(action)

    if spec["targetRequired"] && Trim(target) = ""
        errors.Push(spec["targetLabel"] . " is required")
    if spec["paramRequired"] && Trim(param) = ""
        errors.Push(spec["paramLabel"] . " is required")

    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click":
            if target != "" && InStr(target, ",") && StrSplit(target, ",").Length != 2
                errors.Push("Position must be a saved name or x,y")
            if action = "Click" && param != "" && !IsNumber(param)
                errors.Push("Click count must be a number")

        case "Drag":
            if target = "" && param != "" && !RegExMatch(param, "^-?\d+\s*,\s*-?\d+\s*->\s*-?\d+\s*,\s*-?\d+$")
                errors.Push("Raw drag must be x1,y1->x2,y2")

        case "Find & Drag":
            if param != "" && !RegExMatch(param, "^-?\d+\s*,\s*-?\d+$")
                errors.Push("Destination must be endX,endY")

        case "OCR Region", "OCR Click", "OCR Wait":
            if target != "" {
                parts := StrSplit(target, ",")
                if parts.Length != 4
                    errors.Push("OCR area must contain exactly four comma-separated numbers")
                else {
                    for value in parts
                        if !IsNumber(Trim(value)) {
                            errors.Push("Every OCR area value must be numeric")
                            break
                        }
                }
            }

        case "Wait":
            if param = ""
                errors.Push("PARAM required: duration in milliseconds")
            else if !IsNumber(param)
                errors.Push("Duration must be a number of milliseconds")
            else {
                duration := Integer(param)
                if duration < 0
                    errors.Push("PARAM must be positive number")
                if duration > 300000
                    errors.Push("PARAM > 5 minutes - are you sure?")
            }

        case "Grab OCR to Var", "OCR Full Screen to Var":
            if action = "Grab OCR to Var" && target != "" {
                parts := StrSplit(target, ",")
                if parts.Length != 4
                    errors.Push("OCR area must contain exactly four comma-separated numbers")
                else {
                    for value in parts
                        if !IsNumber(Trim(value)) {
                            errors.Push("Every OCR area value must be numeric")
                            break
                        }
                }
            }
            if InStr(param, ",")
                errors.Push("Variable name should not contain commas; the OCR area now has its own field")
            else if param != "" && !RegExMatch(param, "^[A-Za-z_][A-Za-z0-9_]*$")
                errors.Push("Variable name must start with a letter/underscore and contain only letters, numbers, or underscores")

        case "Menu Select", "Scroll", "Idle Mouse":
            if param != "" && !IsNumber(param)
                errors.Push(spec["paramLabel"] . " must be numeric")

        case "Taskbar Activate":
            if param != "" && !RegExMatch(param, "^\d+\s*,\s*\d+$")
                errors.Push("Taskbar value must be position,count")

        case "Key Chord":
            if param != "" && StrSplit(param, ",").Length != 3
                errors.Push("Key chord must be modifier,key,count")

        case "Set Variable", "Grab Clipboard", "If Contains", "If Variable":
            if target != "" && !RegExMatch(target, "^[A-Za-z_][A-Za-z0-9_]*$")
                errors.Push("Variable name must start with a letter/underscore and contain only letters, numbers, or underscores")
            if action = "If Variable" && param != "" && !RegExMatch(param, "^(==?|!=|<>|>=|<=|>|<),.+$")
                errors.Push("Comparison must use operator,value (for example >=,5)")

        case "Extract from Clipboard":
            if param != "" && !(InStr(param, "between:") = 1 || InStr(param, "field:") = 1 || InStr(param, "regex:") = 1)
                errors.Push("Extraction rule must start with between:, field:, or regex:")
    }

    return errors
}

ShowParameterValidation(action, target, param) {
    errors := ValidateStepParameters(action, target, param)

    if errors.Length > 0 {
        msg := "⚠ Parameter Validation Warnings:`n`n"
        for error in errors {
            msg .= "  • " . error . "`n"
        }
        msg .= "`nContinue anyway?"

        result := MsgBox(msg, "Parameter Validation", "YesNo Icon!")
        return result = "Yes"
    }

    return true
}

UpdateLiveParamHints(*) {
    global ActionDD, ParamCombo, g_ParamHints

    action := ActionDD.Text

    if g_ParamHints.Has(action) {
        hint := g_ParamHints[action]

        try {
            ParamCombo.ToolTip := hint
        }
    }
}


; ═══════════════════════════════════════════════════════════════════════════════
; V5.1: ACTION TEMPLATES LIBRARY
; ═══════════════════════════════════════════════════════════════════════════════

InitializeActionTemplates() {
    global g_ActionTemplates

    g_ActionTemplates["OCR → Variable → Clipboard"] := [
        Map("action", "OCR Region", "target", "100,100,1000,1000", "param", "var:ocrText", "pattern", "", "window", ""),
        Map("action", "Set Clipboard", "target", "", "param", "$var.ocrText", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "OCR Complete,Text copied to clipboard", "pattern", "", "window", "")
    ]

    g_ActionTemplates["Grab OCR → Variable → Notification"] := [
        Map("action", "Grab OCR to Var", "target", "0,0," . A_ScreenWidth . "," . A_ScreenHeight, "param", "capturedText", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "OCR Captured,$var.capturedText,10", "pattern", "", "window", "")
    ]

    g_ActionTemplates["Full Screen OCR → Yellow Boxes → Notification"] := [
        Map("action", "OCR Full Screen to Var", "target", "", "param", "fullScreenOCR", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "Full Screen OCR,$var.fullScreenOCR,10", "pattern", "", "window", "")
    ]

    g_ActionTemplates["OCR Conditional Check"] := [
        Map("action", "OCR Full Screen to Var", "target", "", "param", "screenText", "pattern", "", "window", ""),
        Map("action", "If Contains", "target", "screenText", "param", "KEYWORD", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "OCR Match,KEYWORD was found,5", "pattern", "", "window", "")
    ]

    g_ActionTemplates["Clipboard Formatter"] := [
        Map("action", "Grab Clipboard", "target", "originalClipboard", "param", "", "pattern", "", "window", ""),
        Map("action", "Format Clipboard", "target", "", "param", "trim", "pattern", "", "window", ""),
        Map("action", "Prepend to Clipboard", "target", "", "param", "DOC-", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "Clipboard,Formatted clipboard is ready,3", "pattern", "", "window", "")
    ]

    g_ActionTemplates["Variable Comparison"] := [
        Map("action", "Set Variable", "target", "status", "param", "ready", "pattern", "", "window", ""),
        Map("action", "If Variable", "target", "status", "param", "=,ready", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "Condition,The status variable is ready,3", "pattern", "", "window", "")
    ]

    g_ActionTemplates["Pattern Click with Retry"] := [
        Map("action", "Wait for Pattern", "target", "MyPattern", "param", "5000", "pattern", "", "window", ""),
        Map("action", "Find & Click", "target", "MyPattern", "param", "", "pattern", "", "window", ""),
        Map("action", "Wait", "target", "", "param", "500", "pattern", "", "window", "")
    ]

    g_ActionTemplates["Data Entry (OCR + Type)"] := [
        Map("action", "Click", "target", "FieldStart", "param", "1", "pattern", "", "window", ""),
        Map("action", "Grab OCR to Var", "target", "100,100,500,200", "param", "fieldValue", "pattern", "", "window", ""),
        Map("action", "Use Var Paste", "target", "", "param", "$var.fieldValue", "pattern", "", "window", ""),
        Map("action", "Send Keys", "target", "", "param", "{Tab}", "pattern", "", "window", "")
    ]

    g_ActionTemplates["Debug Step-by-Step"] := [
        Map("action", "Show Notification", "target", "", "param", "Debug,Starting workflow...", "pattern", "", "window", ""),
        Map("action", "Wait", "target", "", "param", "1000", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "Debug,Step 1 complete", "pattern", "", "window", "")
    ]
}

ShowTemplateLibrary(*) {
    global g_ActionTemplates, MainGui

    templateGui := Gui("+Owner" . MainGui.Hwnd, "Action Templates Library")
    templateGui.SetFont("s9", "Segoe UI")

    templateGui.Add("Text", "x10 y10", "Select a pre-built workflow template to insert:")

    templateLV := templateGui.Add("ListView", "x10 y35 w600 h300", ["Template Name", "Steps", "Description"])
    templateLV.ModifyCol(1, 250)
    templateLV.ModifyCol(2, 60)
    templateLV.ModifyCol(3, 270)

    for name, steps in g_ActionTemplates {
        desc := GetTemplateDescription(name)
        templateLV.Add("", name, steps.Length, desc)
    }

    templateGui.Add("Button", "x10 y345 w150 h30", "Insert Template").OnEvent("Click", InsertSelectedTemplate)
    templateGui.Add("Button", "x170 y345 w150 h30", "Preview Steps").OnEvent("Click", PreviewTemplate)
    templateGui.Add("Button", "x330 y345 w150 h30", "Close").OnEvent("Click", (*) => templateGui.Destroy())

    InsertSelectedTemplate(*) {
        row := templateLV.GetNext()
        if !row {
            MsgBox("Please select a template")
            return
        }

        templateName := templateLV.GetText(row, 1)
        InsertTemplate(templateName)
        templateGui.Destroy()
    }

    PreviewTemplate(*) {
        row := templateLV.GetNext()
        if !row {
            MsgBox("Please select a template")
            return
        }

        templateName := templateLV.GetText(row, 1)
        steps := g_ActionTemplates[templateName]

        preview := "Template: " . templateName . "`n`nSteps:`n"
        for i, step in steps {
            preview .= i . ". " . step["action"]
            if step["target"] != ""
                preview .= " → " . step["target"]
            if step["param"] != ""
                preview .= " (" . step["param"] . ")"
            preview .= "`n"
        }

        MsgBox(preview, "Template Preview", "Iconi")
    }

    templateGui.Show("w620 h390")
}

GetTemplateDescription(name) {
    descriptions := Map()
    descriptions["OCR → Variable → Clipboard"] := "Capture text via OCR, store in variable, copy to clipboard"
    descriptions["Grab OCR → Variable → Notification"] := "Capture a full-screen OCR variable and display its value"
    descriptions["Full Screen OCR → Yellow Boxes → Notification"] := "OCR the full screen, box every word in yellow, then display the captured variable"
    descriptions["Pattern Click with Retry"] := "Wait for visual pattern, then click with retry logic"
    descriptions["Data Entry (OCR + Type)"] := "OCR field value and auto-type into form"
    descriptions["Debug Step-by-Step"] := "Workflow with debug notifications at each step"

    return descriptions.Has(name) ? descriptions[name] : "Custom workflow template"
}

InsertTemplate(templateName) {
    global g_ActionTemplates, g_CurrentSequenceSteps

    if !g_ActionTemplates.Has(templateName) {
        MsgBox("Template not found: " . templateName)
        return
    }

    steps := g_ActionTemplates[templateName]

    for step in steps {
        ; Create a copy of the step and ensure it has enabled property
        newStep := Map()
        for key, value in step {
            newStep[key] := value
        }

        ; Ensure enabled is set (default to true)
        if !newStep.Has("enabled")
            newStep["enabled"] := true

        g_CurrentSequenceSteps.Push(newStep)
    }

    RefreshStepsLV()
    ScheduleWorkflowAutosave()
    ShowNotificationBasic("Template Inserted", steps.Length . " steps added from '" . templateName . "' template", 3000, "success")
}


; ═══════════════════════════════════════════════════════════════════════════════
; V5.1: ADVANCED NOTIFICATION TRIGGER SYSTEM
; ═══════════════════════════════════════════════════════════════════════════════

LoadNotificationTriggers() {
    global g_NotificationTriggers, TRIGGERS_FILE

    if !FileExist(TRIGGERS_FILE)
        return

    try {
        content := FileRead(TRIGGERS_FILE, "UTF-8")

        for line in StrSplit(content, "`n", "`r") {
            if line = "" || SubStr(line, 1, 1) = ";"
                continue

            parts := StrSplit(line, "|")
            if parts.Length >= 6 {
                trigger := Map()
                trigger["name"] := parts[1]
                trigger["type"] := parts[2]
                trigger["condition"] := parts[3]
                trigger["action"] := parts[4]
                trigger["params"] := parts[5]
                trigger["enabled"] := (parts[6] = "1")
                trigger["lastFired"] := parts.Length >= 7 ? parts[7] : ""
                trigger["fireCount"] := parts.Length >= 8 ? Integer(parts[8]) : 0

                g_NotificationTriggers[parts[1]] := trigger
            }
        }
    }
}

SaveNotificationTriggers() {
    global g_NotificationTriggers, TRIGGERS_FILE

    output := "; Notification Triggers (Name|Type|Condition|Action|Params|Enabled|LastFired|Count)`n"

    for name, trigger in g_NotificationTriggers {
        output .= trigger["name"] . "|"
        output .= trigger["type"] . "|"
        output .= trigger["condition"] . "|"
        output .= trigger["action"] . "|"
        output .= trigger["params"] . "|"
        output .= (trigger["enabled"] ? "1" : "0") . "|"
        output .= trigger["lastFired"] . "|"
        output .= trigger["fireCount"] . "`n"
    }

    try {
        if FileExist(TRIGGERS_FILE)
            FileDelete(TRIGGERS_FILE)
        FileAppend(output, TRIGGERS_FILE, "UTF-8")
    }
}
GenerateTimeSlots() {
    slots := []
    hour := 9
    minute := 0

    Loop 19 {  ; 9:00 to 18:00
        timeStr := Format("{:02}:{:02}", hour, minute)
        slots.Push(timeStr)
        minute += 30
        if (minute >= 60) {
            minute := 0
            hour++
        }
    }
    return slots
}
AddTrigger(*) {
    global g_NotificationTriggers, MainGui

    triggerGui := Gui("+Owner" . MainGui.Hwnd, "Add Notification Trigger")
    triggerGui.SetFont("s9", "Segoe UI")

    triggerGui.Add("Text", "x10 y10", "Trigger Name:")
    nameEdit := triggerGui.Add("Edit", "x10 y30 w400")

    triggerGui.Add("Text", "x10 y60", "Trigger Type:")
    typeDD := triggerGui.Add("DropDownList", "x10 y80 w400", [
        "Time-Based",
        "Window Activation",
        "Combination",
        "OCR Text Detection",
        "Action Complete",
        "Action Error",
        "Variable Change",
        "Variable Threshold",
        "Sequence Start",
        "Sequence Complete",
        "Debug Log"
    ])
    typeDD.Choose(1)

    triggerGui.Add("Text", "x10 y110", "Condition:")
    conditionEdit := triggerGui.Add("Edit", "x10 y130 w400 h60 +Multi")

    triggerGui.Add("Text", "x420 y10 w350", "Condition Examples:")
    triggerGui.Add("Text", "x420 y30 w350 h100", "Time: time:09:00 or interval:30m`nWindow: window:Chrome|process:chrome.exe`nCombination: combo_type|description`nOCR: region=0,0,100,100 text=Submit`nVariable: var=ocrText contains=Patient`nAction: action=OCR Region result=success")

    triggerGui.Add("Text", "x10 y200", "Action to Execute:")
    actionDD := triggerGui.Add("DropDownList", "x10 y220 w400", [
        "Show Notification",
        "Run Sequence",
        "Set Variable",
        "Write to Log",
        "Execute Command",
        "Play Sound"
    ])
    actionDD.Choose(1)

    triggerGui.Add("Text", "x10 y250", "Action Parameters:")
    paramEdit := triggerGui.Add("Edit", "x10 y270 w400 h60 +Multi")

    triggerGui.Add("Text", "x420 y200 w350", "Parameter Examples:")
    triggerGui.Add("Text", "x420 y220 w350 h100", "Notification: Title,Message,Timeout`nSequence: SequenceName`nVariable: varName=value`nLog: logfile.txt`nCommand: notepad.exe")

    enableCheck := triggerGui.Add("CheckBox", "x10 y340 Checked", "Enable Immediately")

    triggerGui.Add("Button", "x10 y370 w150 h30", "Create Trigger").OnEvent("Click", CreateTrigger)
    triggerGui.Add("Button", "x170 y370 w150 h30", "Cancel").OnEvent("Click", (*) => triggerGui.Destroy())

    CreateTrigger(*) {
        name := nameEdit.Value
        if name = "" {
            MsgBox("Trigger name is required")
            return
        }

        if g_NotificationTriggers.Has(name) {
            result := MsgBox("Trigger '" . name . "' already exists. Overwrite?", "Confirm", "YesNo Icon?")
            if result != "Yes"
                return
        }

        trigger := Map()
        trigger["name"] := name
        trigger["type"] := typeDD.Text
        trigger["condition"] := conditionEdit.Value
        trigger["action"] := actionDD.Text
        trigger["params"] := paramEdit.Value
        trigger["enabled"] := enableCheck.Value
        trigger["created"] := A_Now
        trigger["lastFired"] := ""
        trigger["fireCount"] := 0

        g_NotificationTriggers[name] := trigger
        SaveNotificationTriggers()
        RefreshTriggersLV()
        triggerGui.Destroy()

        ShowNotificationBasic("Trigger Created", "Trigger '" . name . "' has been created", 3000)
    }

    triggerGui.Show("w780 h415")
}

RefreshTriggersLV() {
    global g_NotificationTriggers, TriggersLV

    TriggersLV.Delete()

    for name, trigger in g_NotificationTriggers {
        TriggersLV.Add("",
            trigger["enabled"] ? "✓" : "",
            name,
            trigger["type"],
            SubStr(trigger["condition"], 1, 40),
            trigger["action"],
            trigger["lastFired"] != "" ? FormatTime(trigger["lastFired"], "MM/dd HH:mm") : "Never"
        )
    }
}

EditTrigger(lv, row) {
    MsgBox("Edit trigger functionality - will reopen Add GUI with values pre-filled")
}

EditTriggerFromBtn(*) {
    global TriggersLV
    row := TriggersLV.GetNext()
    if row
        EditTrigger(TriggersLV, row)
    else
        MsgBox("Please select a trigger to edit")
}

DeleteTrigger(*) {
    global g_NotificationTriggers, TriggersLV

    row := TriggersLV.GetNext()
    if !row {
        MsgBox("Please select a trigger to delete")
        return
    }

    name := TriggersLV.GetText(row, 2)

    result := MsgBox("Delete trigger '" . name . "'?", "Confirm Delete", "YesNo Icon?")
    if result != "Yes"
        return

    g_NotificationTriggers.Delete(name)
    SaveNotificationTriggers()
    RefreshTriggersLV()
}

ToggleTrigger(*) {
    global g_NotificationTriggers, TriggersLV

    row := TriggersLV.GetNext()
    if !row {
        MsgBox("Please select a trigger")
        return
    }

    name := TriggersLV.GetText(row, 2)

    if g_NotificationTriggers.Has(name) {
        trigger := g_NotificationTriggers[name]
        trigger["enabled"] := !trigger["enabled"]
        SaveNotificationTriggers()
        RefreshTriggersLV()
    }
}

ToggleAllTriggers(*) {
    global g_NotificationTriggers, TriggerMasterToggle

    enabled := TriggerMasterToggle.Value

    for name, trigger in g_NotificationTriggers {
        trigger["enabled"] := enabled
    }

    SaveNotificationTriggers()
    RefreshTriggersLV()
}

StartTriggerMonitoring(*) {
    global g_TriggerMonitorTimer, g_NotificationTriggers

    ; Stop existing timer if running
    if g_TriggerMonitorTimer
        SetTimer(g_TriggerMonitorTimer, 0)

    ; Create monitoring timer - check every 30 seconds
    g_TriggerMonitorTimer := CheckTriggers
    SetTimer(g_TriggerMonitorTimer, 30000)

    ShowNotificationBasic("Trigger Monitor", "Real-time trigger monitoring started`nChecking every 30 seconds", 2000, "success")
}

StopTriggerMonitoring(*) {
    global g_TriggerMonitorTimer

    if g_TriggerMonitorTimer {
        SetTimer(g_TriggerMonitorTimer, 0)
        g_TriggerMonitorTimer := ""
    }

    ShowNotificationBasic("Trigger Monitor", "Real-time trigger monitoring stopped", 2000, "info")
}

; Main trigger checking function
CheckTriggers() {
    global g_NotificationTriggers

    currentTime := A_Now
    currentTimeFormatted := FormatTime(currentTime, "HH:mm")

    ; Get current active window
    try {
        activeTitle := WinGetTitle("A")
        activeProcess := ProcessGetName(WinGetPID("A"))
    } catch {
        activeTitle := ""
        activeProcess := ""
    }

    for name, trigger in g_NotificationTriggers {
        if !trigger["enabled"]
            continue

        ; Check trigger type and condition
        switch trigger["type"] {
            case "Time-Based":
                ProcessTimeTrigger(trigger, currentTime, currentTimeFormatted)

            case "Window Activation":
                ProcessWindowTrigger(trigger, activeTitle, activeProcess)
        }
    }
}

; Process window activation triggers
ProcessWindowTrigger(trigger, activeTitle, activeProcess) {
    condition := trigger["condition"]

    ; Parse condition: "window:Chrome|process:chrome.exe"
    windowMatch := ""
    processMatch := ""

    if InStr(condition, "window:") {
        parts := StrSplit(condition, "|")
        windowPart := parts[1]
        windowMatch := SubStr(windowPart, 8)  ; Remove "window:"

        if parts.Length > 1 && InStr(parts[2], "process:") {
            processMatch := SubStr(parts[2], 9)  ; Remove "process:"
        }
    }

    ; Check if window title matches (supports multiple titles with |)
    titleMatches := false
    if windowMatch != "" {
        for title in StrSplit(windowMatch, "|") {
            if InStr(activeTitle, title) {
                titleMatches := true
                break
            }
        }
    }

    ; Check process if specified
    processMatches := true
    if processMatch != "" && activeProcess != "" {
        processMatches := InStr(activeProcess, processMatch)
    }

    ; Trigger if window matches (and process matches if specified)
    if titleMatches && processMatches {
        ; Check if this is a new activation (prevent spam)
        lastWindow := trigger.Has("lastWindow") ? trigger["lastWindow"] : ""

        if lastWindow != activeTitle {
            ; Fire the trigger
            ExecuteTriggerAction(trigger)
            trigger["lastFired"] := A_Now
            trigger["lastWindow"] := activeTitle
            trigger["fireCount"] := trigger["fireCount"] + 1
            SaveNotificationTriggers()
            RefreshTriggersLV()
        }
    } else {
        ; Window is not active - reset lastWindow
        if trigger.Has("lastWindow")
            trigger["lastWindow"] := ""
    }
}

; Process time-based triggers
ProcessTimeTrigger(trigger, currentTime, currentTimeFormatted) {
    condition := trigger["condition"]

    ; Parse condition type
    if InStr(condition, "time:") {
        ; Specific time trigger (e.g., "time:09:00")
        targetTime := SubStr(condition, 6)

        if currentTimeFormatted = targetTime {
            ; Check if already fired today
            lastFired := trigger["lastFired"]
            if lastFired != "" {
                lastFiredDate := FormatTime(lastFired, "yyyy-MM-dd")
                currentDate := FormatTime(currentTime, "yyyy-MM-dd")

                if lastFiredDate = currentDate
                    return  ; Already fired today
            }

            ; Fire the trigger
            ExecuteTriggerAction(trigger)
            trigger["lastFired"] := currentTime
            trigger["fireCount"] := trigger["fireCount"] + 1
            SaveNotificationTriggers()
            RefreshTriggersLV()
        }
    }
    else if InStr(condition, "interval:") {
        ; Interval trigger (e.g., "interval:300s" or "interval:5m")
        intervalStr := SubStr(condition, 10)

        ; Parse interval
        if InStr(intervalStr, "s") {
            intervalSeconds := Integer(StrReplace(intervalStr, "s", ""))
        } else if InStr(intervalStr, "m") {
            intervalSeconds := Integer(StrReplace(intervalStr, "m", "")) * 60
        } else if InStr(intervalStr, "h") {
            intervalSeconds := Integer(StrReplace(intervalStr, "h", "")) * 3600
        } else {
            intervalSeconds := Integer(intervalStr)
        }

        ; Check if enough time has passed since last fire
        lastFired := trigger["lastFired"]
        if lastFired = "" {
            ; Never fired, fire now
            ExecuteTriggerAction(trigger)
            trigger["lastFired"] := currentTime
            trigger["fireCount"] := trigger["fireCount"] + 1
            SaveNotificationTriggers()
            RefreshTriggersLV()
        } else {
            ; Check if interval has elapsed
            lastFiredTime := DateDiff(lastFired, currentTime, "Seconds")
            if Abs(lastFiredTime) >= intervalSeconds {
                ExecuteTriggerAction(trigger)
                trigger["lastFired"] := currentTime
                trigger["fireCount"] := trigger["fireCount"] + 1
                SaveNotificationTriggers()
                RefreshTriggersLV()
            }
        }
    }
}

; Execute the trigger's action
ExecuteTriggerAction2(trigger) {
    action := trigger["action"]
    params := trigger["params"]

    switch action {
        case "Show Notification":
            ; Parse params: Title,Message,Timeout
            parts := StrSplit(params, ",", , 3)
            title := parts.Length >= 1 ? parts[1] : "Trigger Notification"
            message := parts.Length >= 2 ? parts[2] : "Trigger fired"
            timeout := parts.Length >= 3 ? Integer(parts[3]) : 5000

            ShowNotificationBasic(title, message, timeout, "info")

        case "Run Sequence":
            ; Execute a saved sequence
            if g_Sequences.Has(params) {
                ExecuteSequenceByHotkey(params)
            } else {
                ShowNotificationBasic("Trigger Error", "Sequence '" . params . "' not found", 3000, "error")
            }

        case "Play Sound":
            ; Play a sound file or system beep
            try {
                if FileExist(params) {
                    SoundPlay(params)
                } else {
                    ; Parse as frequency,duration
                    soundParts := StrSplit(params, ",")
                    freq := soundParts.Length >= 1 ? Integer(soundParts[1]) : 800
                    duration := soundParts.Length >= 2 ? Integer(soundParts[2]) : 200
                    SoundBeep(freq, duration)
                }
            }

        case "Write to Log":
            ; Write to log file
            try {
                logFile := params != "" ? params : "trigger_log.txt"
                timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
                logEntry := timestamp . " - Trigger: " . trigger["name"] . "`n"
                FileAppend(logEntry, logFile)
            }
    }
}

TestSelectedTrigger(*) {
    global TriggersLV, g_NotificationTriggers

    row := TriggersLV.GetNext()
    if !row {
        MsgBox("Please select a trigger to test")
        return
    }

    name := TriggersLV.GetText(row, 2)

    if g_NotificationTriggers.Has(name) {
        trigger := g_NotificationTriggers[name]
        ExecuteTriggerAction(trigger)
    }
}

ExecuteTriggerAction(trigger) {
    switch trigger["action"] {
        case "Show Notification":
            params := StrSplit(trigger["params"], ",")
            title := params.Length >= 1 ? Trim(params[1]) : "Trigger Fired"
            message := params.Length >= 2 ? Trim(params[2]) : trigger["name"]
            timeout := params.Length >= 3 ? Integer(params[3]) : 5
            ShowNotificationBasic(title, message, timeout * 1000)

        case "Run Sequence":
            seqName := Trim(trigger["params"])
            ShowNotificationBasic("Trigger Action", "Would execute sequence: " . seqName, 3000)

        case "Write to Log":
            logFile := A_ScriptDir . "\data\trigger_log.txt"
            entry := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") . " | " . trigger["name"] . " | " . trigger["params"] . "`n"
            FileAppend(entry, logFile, "UTF-8")
            ShowNotificationBasic("Trigger Action", "Written to log", 2000)
    }

    trigger["lastFired"] := A_Now
    trigger["fireCount"]++
    SaveNotificationTriggers()
    RefreshTriggersLV()
}

ViewTriggerLog(*) {
    global g_TriggerLog

    logFile := A_ScriptDir . "\data\trigger_log.txt"

    if FileExist(logFile) {
        Run(logFile)
    } else {
        MsgBox("Trigger log file does not exist yet", "Trigger Log", "Iconi")
    }
}

ClearTriggerLog(*) {
    logFile := A_ScriptDir . "\data\trigger_log.txt"

    result := MsgBox("Clear trigger log file?", "Confirm", "YesNo Icon?")
    if result = "Yes" {
        if FileExist(logFile)
            FileDelete(logFile)
        MsgBox("Trigger log cleared", "Success", "Iconi")
    }
}

DuplicateTrigger(*) {
    global TriggersLV, g_NotificationTriggers

    row := TriggersLV.GetNext()
    if !row {
        MsgBox("Please select a trigger to duplicate")
        return
    }

    name := TriggersLV.GetText(row, 2)

    if !g_NotificationTriggers.Has(name)
        return

    original := g_NotificationTriggers[name]
    newName := name . " (Copy)"
    counter := 2

    while g_NotificationTriggers.Has(newName) {
        newName := name . " (Copy " . counter . ")"
        counter++
    }

    duplicate := Map()
    for key, value in original {
        duplicate[key] := value
    }
    duplicate["name"] := newName
    duplicate["created"] := A_Now
    duplicate["lastFired"] := ""
    duplicate["fireCount"] := 0

    g_NotificationTriggers[newName] := duplicate
    SaveNotificationTriggers()
    RefreshTriggersLV()

    ShowNotificationBasic("Trigger Duplicated", "Created: " . newName, 2000)
}

ExportTrigger(*) {
    MsgBox("Export trigger to file - Coming in future update")
}

ImportTrigger(*) {
    MsgBox("Import trigger from file - Coming in future update")
}

ShowTriggerTemplates(*) {
    global g_NotificationTriggers

    ; Create template selection GUI
    templateGui := Gui("+AlwaysOnTop", "Trigger Templates")
    templateGui.SetFont("s9", "Segoe UI")

    ; Create tabbed interface for different template categories
    templateTabs := templateGui.Add("Tab3", "x10 y10 w780 h580", ["Time-Based", "Window/App", "Combinations", "Settings"])

    ; ═══════════════════════════════════════════════════════════════════════════
    ; TAB 1: TIME-BASED TRIGGERS
    ; ═══════════════════════════════════════════════════════════════════════════
    templateTabs.UseTab(1)

    templateGui.Add("GroupBox", "x20 y40 w750 h100", "Interval Templates - Recurring Notifications")
    templateGui.Add("Button", "x30 y60 w100 h22", "Every 1 Min").OnEvent("Click", (*) => CreateIntervalTrigger(1))
    templateGui.Add("Button", "x135 y60 w100 h22", "Every 5 Min").OnEvent("Click", (*) => CreateIntervalTrigger(5))
    templateGui.Add("Button", "x240 y60 w100 h22", "Every 15 Min").OnEvent("Click", (*) => CreateIntervalTrigger(15))
    templateGui.Add("Button", "x345 y60 w100 h22", "Every 30 Min").OnEvent("Click", (*) => CreateIntervalTrigger(30))
    templateGui.Add("Button", "x450 y60 w100 h22", "Every 60 Min").OnEvent("Click", (*) => CreateIntervalTrigger(60))
    templateGui.Add("Button", "x555 y60 w100 h22", "Every 2 Hours").OnEvent("Click", (*) => CreateIntervalTrigger(120))
    templateGui.Add("Button", "x660 y60 w100 h22", "Every 4 Hours").OnEvent("Click", (*) => CreateIntervalTrigger(240))

    templateGui.Add("Text", "x30 y90 w730", "⏱️ Perfect for: Hydration reminders, posture checks, eye rest, task switching, status updates")
    templateGui.Add("Text", "x30 y110 w730 c888888", "Note: Intervals start from when trigger is created or last fired")

    templateGui.Add("GroupBox", "x20 y150 w750 h300", "Daily Schedule Templates - Specific Times")
    templateGui.Add("Text", "x30 y170 w730", "📅 Click a template to create, or use Custom Time below:")

    ; Work schedule templates
    templateGui.Add("Text", "x30 y195 w730 cBlue Bold", "Work Schedule:")
    yPos := 215
    workTemplates := [
        ["Morning Start", "08:00", "☀️ Start your workday"],
        ["Coffee Break", "10:30", "☕ Mid-morning break"],
        ["Lunch Time", "12:00", "🍽️ Clock out for lunch"],
        ["Back from Lunch", "13:00", "💼 Resume work"],
        ["Afternoon Break", "15:00", "🧘 Stretch and refresh"],
        ["End of Day", "17:00", "🏠 Clock out for the day"]
    ]

    for template in workTemplates {
        templateGui.Add("Button", "x30 y" . yPos . " w130 h22", template[1]).OnEvent("Click", (*) => CreateTimeTrigger(template[1], template[2], template[3]))
        templateGui.Add("Text", "x165 y" . (yPos + 3) . " w60", template[2])
        templateGui.Add("Text", "x230 y" . (yPos + 3) . " w530 c888888", template[3])
        yPos += 28
    }

    ; Health & wellness templates
    templateGui.Add("Text", "x30 y" . yPos . " w730 cGreen Bold", "Health & Wellness:")
    yPos += 20
    healthTemplates := [
        ["Morning Hydration", "09:00", "💧 Drink water - start hydrated"],
        ["Midday Eye Rest", "14:00", "👁️ 20-20-20 rule: Look 20ft away for 20sec"],
        ["Evening Wind Down", "20:00", "🌙 Start relaxing routine"]
    ]

    for template in healthTemplates {
        templateGui.Add("Button", "x30 y" . yPos . " w130 h22", template[1]).OnEvent("Click", (*) => CreateTimeTrigger(template[1], template[2], template[3]))
        templateGui.Add("Text", "x165 y" . (yPos + 3) . " w60", template[2])
        templateGui.Add("Text", "x230 y" . (yPos + 3) . " w530 c888888", template[3])
        yPos += 28
    }

    templateGui.Add("GroupBox", "x20 y460 w750 h90", "Custom Time Trigger")
    templateGui.Add("Text", "x30 y480", "Time (HH:MM):")
    timeEdit := templateGui.Add("Edit", "x120 y477 w60", "09:00")
    templateGui.Add("Text", "x190 y480", "Name:")
    nameEdit := templateGui.Add("Edit", "x235 y477 w150", "")
    templateGui.Add("Text", "x395 y480", "Message:")
    msgEdit := templateGui.Add("Edit", "x30 y505 w350", "")
    templateGui.Add("Button", "x390 y505 w120 h22", "Create Custom").OnEvent("Click", CreateCustomTime)

    ; ═══════════════════════════════════════════════════════════════════════════
    ; TAB 2: WINDOW/APPLICATION TRIGGERS
    ; ═══════════════════════════════════════════════════════════════════════════
    templateTabs.UseTab(2)

    templateGui.Add("GroupBox", "x20 y40 w750 h250", "Window Activation Triggers")
    templateGui.Add("Text", "x30 y60 w730", "🪟 Fire notifications or run sequences when specific windows become active")

    templateGui.Add("Text", "x30 y85 w730 cBlue Bold", "Browser Templates:")

    appTemplates := [
        ["Chrome New Tab", "Chrome", "chrome.exe", "🌐 New Chrome tab - ready to search"],
        ["Firefox Active", "Firefox", "firefox.exe", "🦊 Firefox window activated"],
        ["Edge Browser", "Edge", "msedge.exe", "🌊 Microsoft Edge activated"],
        ["Browser Focus", "Chrome|Firefox|Edge", "", "🔍 Any browser window activated"]
    ]

    yPos := 105
    for template in appTemplates {
        templateGui.Add("Button", "x30 y" . yPos . " w150 h22", template[1]).OnEvent("Click", (*) => CreateWindowTrigger(template[1], template[2], template[3], template[4]))
        templateGui.Add("Text", "x185 y" . (yPos + 3) . " w580 c888888", template[4])
        yPos += 28
    }

    templateGui.Add("Text", "x30 y" . yPos . " w730 cGreen Bold", "Productivity Apps:")
    yPos += 20

    prodTemplates := [
        ["Excel Activated", "Excel", "EXCEL.EXE", "📊 Excel spreadsheet opened"],
        ["Word Document", "Word", "WINWORD.EXE", "📝 Word document opened"],
        ["VS Code Active", "Code", "Code.exe", "💻 Coding session started"],
        ["Notepad++ Open", "Notepad++", "notepad++.exe", "📄 Text editor activated"]
    ]

    for template in prodTemplates {
        templateGui.Add("Button", "x30 y" . yPos . " w150 h22", template[1]).OnEvent("Click", (*) => CreateWindowTrigger(template[1], template[2], template[3], template[4]))
        templateGui.Add("Text", "x185 y" . (yPos + 3) . " w580 c888888", template[4])
        yPos += 28
    }

    templateGui.Add("GroupBox", "x20 y305 w750 h120", "Custom Window Trigger")
    templateGui.Add("Text", "x30 y325", "Window Title Contains:")
    winTitleEdit := templateGui.Add("Edit", "x160 y322 w200", "")
    templateGui.Add("Text", "x370 y325", "(e.g., 'Chrome', 'Untitled')")

    templateGui.Add("Text", "x30 y355", "Process Name:")
    winProcEdit := templateGui.Add("Edit", "x160 y352 w200", "")
    templateGui.Add("Text", "x370 y355", "(e.g., 'chrome.exe') - Optional")

    templateGui.Add("Text", "x30 y385", "Action Message:")
    winMsgEdit := templateGui.Add("Edit", "x160 y382 w400", "")
    templateGui.Add("Button", "x570 y382 w180 h22", "Create Window Trigger").OnEvent("Click", CreateCustomWindow)

    templateGui.Add("GroupBox", "x20 y435 w750 h115", "Window State Triggers")
    templateGui.Add("Text", "x30 y455 w730", "⚡ Advanced: Trigger based on window states or counts")

    stateTemplates := [
        ["Too Many Windows", "Monitor window count > 10", "🪟 Minimize clutter - too many windows open!"],
        ["Browser Tab Overload", "Chrome tabs > 20", "🔥 Tab hoarding detected - time to clean up!"],
        ["Focus Mode Broken", "Window switched", "🎯 Focus interrupted - minimize distractions"]
    ]

    yPos := 475
    for template in stateTemplates {
        templateGui.Add("Button", "x30 y" . yPos . " w180 h22", template[1]).OnEvent("Click", (*) => CreateAdvancedTrigger(template[1], template[2], template[3]))
        templateGui.Add("Text", "x215 y" . (yPos + 3) . " w540 c888888", template[3])
        yPos += 25
    }

    ; ═══════════════════════════════════════════════════════════════════════════
    ; TAB 3: COMBINATION TRIGGERS
    ; ═══════════════════════════════════════════════════════════════════════════
    templateTabs.UseTab(3)

    templateGui.Add("GroupBox", "x20 y40 w750 h480", "Smart Combination Triggers")
    templateGui.Add("Text", "x30 y60 w730", "🔗 Combine multiple conditions for intelligent automation")

    templateGui.Add("Text", "x30 y85 w730 cBlue Bold", "Work-Life Balance:")

    comboTemplates := [
        ["After Hours Alert",
         "Time > 18:00 AND Excel active",
         "⏰ It's after 6 PM - Consider wrapping up work!",
         "combo_afterhours"],

        ["Lunch Break Enforcer",
         "Time 12:00-13:00 AND Work app active",
         "🍽️ Lunch time! Step away from work applications",
         "combo_lunch"],

        ["Focus Time Protector",
         "Time 09:00-11:00 AND Email/Chat active",
         "🎯 Focus hours - minimize communications!",
         "combo_focus"],

        ["Meeting Reminder",
         "Time = 10min before AND Calendar event",
         "📅 Meeting in 10 minutes - prepare to join",
         "combo_meeting"]
    ]

    yPos := 105
    for template in comboTemplates {
        templateGui.Add("Button", "x30 y" . yPos . " w200 h22", template[1]).OnEvent("Click", (*) => CreateComboTrigger(template[1], template[2], template[3], template[4]))
        templateGui.Add("Text", "x235 y" . (yPos + 3) . " w520 c888888", template[2])
        templateGui.Add("Text", "x235 y" . (yPos + 18) . " w520", template[3])
        yPos += 40
    }

    templateGui.Add("Text", "x30 y" . (yPos + 10) . " w730 cGreen Bold", "Productivity Boosters:")
    yPos += 30

    prodComboTemplates := [
        ["Distraction Detector",
         "Social media active > 5 min during work hours",
         "⚠️ Focus check - you've been on social media for 5 minutes",
         "combo_distraction"],

        ["Deep Work Encourager",
         "Same window active for 45 min",
         "🎉 Great focus! 45 minutes of deep work completed",
         "combo_deepwork"],

        ["Context Switch Helper",
         "Chrome new tab AND time is work hours",
         "💡 Quick Tip: Use search shortcuts to stay productive",
         "combo_context"],

        ["Break Reminder Smart",
         "No mouse movement for 30 min during work hours",
         "🧘 Take a break - you've been still for 30 minutes!",
         "combo_breaktime"]
    ]

    for template in prodComboTemplates {
        templateGui.Add("Button", "x30 y" . yPos . " w200 h22", template[1]).OnEvent("Click", (*) => CreateComboTrigger(template[1], template[2], template[3], template[4]))
        templateGui.Add("Text", "x235 y" . (yPos + 3) . " w520 c888888", template[2])
        templateGui.Add("Text", "x235 y" . (yPos + 18) . " w520", template[3])
        yPos += 40
    }

    templateGui.Add("Text", "x30 y" . (yPos + 10) . " w730 cRed Bold", "Health & Wellness:")
    yPos += 30

    healthComboTemplates := [
        ["Posture Check",
         "Every 20 min during active work",
         "🪑 Posture check - sit up straight, shoulders back!",
         "combo_posture"],

        ["Eye Strain Prevention",
         "Screen time > 2 hours continuous",
         "👁️ Eye break - look away from screen for 20 seconds",
         "combo_eyes"],

        ["Hydration Tracker",
         "Every 45 min if no water break detected",
         "💧 Drink water - staying hydrated improves focus",
         "combo_hydrate"]
    ]

    for template in healthComboTemplates {
        templateGui.Add("Button", "x30 y" . yPos . " w200 h22", template[1]).OnEvent("Click", (*) => CreateComboTrigger(template[1], template[2], template[3], template[4]))
        templateGui.Add("Text", "x235 y" . (yPos + 3) . " w520 c888888", template[2])
        templateGui.Add("Text", "x235 y" . (yPos + 18) . " w520", template[3])
        yPos += 40
    }

    ; ═══════════════════════════════════════════════════════════════════════════
    ; TAB 4: NOTIFICATION SETTINGS
    ; ═══════════════════════════════════════════════════════════════════════════
    templateTabs.UseTab(4)

    templateGui.Add("GroupBox", "x20 y40 w750 h100", "Quick Access")
    templateGui.Add("Button", "x30 y60 w300 h30", "📋 Notification Preferences").OnEvent("Click", ShowNotificationSettings)
    templateGui.Add("Text", "x340 y70 w420", "Configure notification appearance, colors, position, and behavior")

    templateGui.Add("GroupBox", "x20 y150 w750 h250", "Trigger Management Tips")
    templateGui.Add("Text", "x30 y170 w730", "💡 Best Practices:")
    templateGui.Add("Text", "x30 y195 w730", "• Start with a few triggers and add more as needed")
    templateGui.Add("Text", "x30 y220 w730", "• Use specific time triggers for fixed events (meetings, breaks)")
    templateGui.Add("Text", "x30 y245 w730", "• Use interval triggers for recurring reminders (hydration, posture)")
    templateGui.Add("Text", "x30 y270 w730", "• Combine window triggers with time constraints for smart automation")
    templateGui.Add("Text", "x30 y295 w730", "• Test triggers before enabling to ensure they work as expected")
    templateGui.Add("Text", "x30 y320 w730", "• Use the 'Last Fired' column to verify triggers are working")
    templateGui.Add("Text", "x30 y345 w730", "• Disable triggers you're not using to reduce monitoring overhead")

    templateGui.Add("GroupBox", "x20 y410 w750 h130", "Template Statistics")
    templateGui.Add("Text", "x30 y430 w730 Bold", "Available Templates:")
    templateGui.Add("Text", "x30 y455 w730", "⏱️ Time-Based: 15 templates (7 intervals + 8 daily schedules)")
    templateGui.Add("Text", "x30 y480 w730", "🪟 Window/App: 12 templates (8 app-specific + 4 custom builders)")
    templateGui.Add("Text", "x30 y505 w730", "🔗 Combinations: 10 smart templates (work-life, productivity, health)")
    templateGui.Add("Text", "x30 y525 w730 cBlue", "Total: 37+ pre-built templates ready to use!")

    templateGui.Add("Button", "x670 y555 w100 h30", "Close").OnEvent("Click", (*) => templateGui.Destroy())

    ; ═══════════════════════════════════════════════════════════════════════════
    ; TEMPLATE CREATION FUNCTIONS
    ; ═══════════════════════════════════════════════════════════════════════════

    ; Interval trigger creation
    CreateIntervalTrigger(minutes) {
        name := "Reminder Every " . minutes . " Minute" . (minutes > 1 ? "s" : "")

        trigger := Map()
        trigger["name"] := name
        trigger["type"] := "Time-Based"
        trigger["condition"] := "interval:" . (minutes * 60) . "s"
        trigger["action"] := "Show Notification"
        trigger["params"] := name . ",Time for a " . minutes . " minute check-in!,5000"
        trigger["enabled"] := true
        trigger["created"] := A_Now
        trigger["lastFired"] := ""
        trigger["fireCount"] := 0
        trigger["nextFire"] := DateAdd(A_Now, minutes, "Minutes")

        g_NotificationTriggers[name] := trigger
        SaveNotificationTriggers()
        RefreshTriggersLV()

        ShowNotificationBasic("Template Created", name . " trigger created", 2000, "success")
        templateGui.Destroy()
    }

    ; Time-based trigger creation
    CreateTimeTrigger(name, time, message) {
        trigger := Map()
        trigger["name"] := name
        trigger["type"] := "Time-Based"
        trigger["condition"] := "time:" . time
        trigger["action"] := "Show Notification"
        trigger["params"] := name . "," . message . ",10000"
        trigger["enabled"] := true
        trigger["created"] := A_Now
        trigger["lastFired"] := ""
        trigger["fireCount"] := 0

        g_NotificationTriggers[name] := trigger
        SaveNotificationTriggers()
        RefreshTriggersLV()

        ShowNotificationBasic("Template Created", name . " trigger created for " . time, 2000, "success")
        templateGui.Destroy()
    }

    ; Window activation trigger
    CreateWindowTrigger(name, windowTitle, processName, message) {
        trigger := Map()
        trigger["name"] := name
        trigger["type"] := "Window Activation"
        trigger["condition"] := "window:" . windowTitle . (processName != "" ? "|process:" . processName : "")
        trigger["action"] := "Show Notification"
        trigger["params"] := name . "," . message . ",3000"
        trigger["enabled"] := true
        trigger["created"] := A_Now
        trigger["lastFired"] := ""
        trigger["fireCount"] := 0
        trigger["lastWindow"] := ""

        g_NotificationTriggers[name] := trigger
        SaveNotificationTriggers()
        RefreshTriggersLV()

        ShowNotificationBasic("Template Created", name . " window trigger created", 2000, "success")
        templateGui.Destroy()
    }

    ; Advanced trigger (placeholder for future)
    CreateAdvancedTrigger(name, condition, message) {
        trigger := Map()
        trigger["name"] := name
        trigger["type"] := "Advanced"
        trigger["condition"] := condition
        trigger["action"] := "Show Notification"
        trigger["params"] := name . "," . message . ",5000"
        trigger["enabled"] := false  ; Disabled by default - needs implementation
        trigger["created"] := A_Now
        trigger["lastFired"] := ""
        trigger["fireCount"] := 0

        g_NotificationTriggers[name] := trigger
        SaveNotificationTriggers()
        RefreshTriggersLV()

        ShowNotificationBasic("Template Created", name . " created (disabled - needs configuration)", 3000, "warning")
        templateGui.Destroy()
    }

    ; Combination trigger
    CreateComboTrigger(name, condition, message, comboType) {
        trigger := Map()
        trigger["name"] := name
        trigger["type"] := "Combination"
        trigger["condition"] := comboType . "|" . condition
        trigger["action"] := "Show Notification"
        trigger["params"] := name . "," . message . ",5000"
        trigger["enabled"] := false  ; Disabled by default - needs implementation
        trigger["created"] := A_Now
        trigger["lastFired"] := ""
        trigger["fireCount"] := 0

        g_NotificationTriggers[name] := trigger
        SaveNotificationTriggers()
        RefreshTriggersLV()

        ShowNotificationBasic("Template Created", name . " created (disabled - future feature)", 3000, "warning")
        templateGui.Destroy()
    }

    ; Custom time trigger
    CreateCustomTime(*) {
        time := timeEdit.Value
        name := nameEdit.Value
        msg := msgEdit.Value

        if name = "" {
            MsgBox("Please enter a name for the trigger")
            return
        }

        if !RegExMatch(time, "^\d{1,2}:\d{2}$") {
            MsgBox("Time must be in HH:MM format (e.g., 09:00 or 14:30)")
            return
        }

        if msg = ""
            msg := "Time trigger: " . name

        CreateTimeTrigger(name, time, msg)
    }

    ; Custom window trigger
    CreateCustomWindow(*) {
        winTitle := winTitleEdit.Value
        winProc := winProcEdit.Value
        msg := winMsgEdit.Value

        if winTitle = "" {
            MsgBox("Please enter a window title to monitor")
            return
        }

        name := "Window: " . winTitle
        if msg = ""
            msg := winTitle . " window activated"

        CreateWindowTrigger(name, winTitle, winProc, msg)
    }

    templateGui.Show("w800 h630")
}

; Notification Settings GUI
ShowNotificationSettings(*) {
    global g_NotificationDefaults

    settingsGui := Gui("+AlwaysOnTop", "Notification Settings")
    settingsGui.SetFont("s9", "Segoe UI")

    settingsGui.Add("GroupBox", "x10 y10 w400 h120", "Default Notification Behavior")

    settingsGui.Add("Text", "x20 y30", "Default Duration:")
    durationEdit := settingsGui.Add("Edit", "x120 y27 w60", g_NotificationDefaults["timeout"])
    settingsGui.Add("Text", "x185 y30", "ms (0 = manual dismiss)")

    settingsGui.Add("CheckBox", "x20 y55 vDismissible " . (g_NotificationDefaults["dismissible"] ? "Checked" : ""), "Notifications stay until dismissed")
    settingsGui.Add("CheckBox", "x20 y80 vStackNotifications " . (g_NotificationDefaults["stack"] ? "Checked" : ""), "Stack multiple notifications")
    settingsGui.Add("CheckBox", "x20 y105 vSoundEnabled " . (g_NotificationDefaults["sound"] ? "Checked" : ""), "Play sound on notification")

    settingsGui.Add("GroupBox", "x10 y140 w400 h140", "Notification Position")
    settingsGui.Add("Radio", "x20 y160 vPosBottomRight " . (g_NotificationDefaults["position"] = "bottom-right" ? "Checked" : ""), "Bottom Right (default)")
    settingsGui.Add("Radio", "x20 y185 vPosBottomLeft", "Bottom Left")
    settingsGui.Add("Radio", "x20 y210 vPosTopRight", "Top Right")
    settingsGui.Add("Radio", "x20 y235 vPosTopLeft", "Top Left")
    settingsGui.Add("Radio", "x20 y260 vPosCenter", "Center")

    settingsGui.Add("GroupBox", "x10 y290 w400 h100", "Color Scheme")
    settingsGui.Add("Text", "x20 y310", "Success:")
    settingsGui.Add("Edit", "x75 y307 w80", g_NotificationDefaults.Has("color_success") ? g_NotificationDefaults["color_success"] : "0x0d3d0d")
    settingsGui.Add("Text", "x20 y340", "Error:")
    settingsGui.Add("Edit", "x75 y337 w80", g_NotificationDefaults.Has("color_error") ? g_NotificationDefaults["color_error"] : "0x3d0d0d")
    settingsGui.Add("Text", "x20 y370", "Warning:")
    settingsGui.Add("Edit", "x75 y367 w80", g_NotificationDefaults.Has("color_warning") ? g_NotificationDefaults["color_warning"] : "0x3d3d0d")

    settingsGui.Add("Text", "x220 y310", "Info:")
    settingsGui.Add("Edit", "x260 y307 w80", g_NotificationDefaults.Has("color_info") ? g_NotificationDefaults["color_info"] : "0x1a1a1a")

    settingsGui.Add("Button", "x10 y400 w150 h30", "Save Settings").OnEvent("Click", SaveNotifSettings)
    settingsGui.Add("Button", "x170 y400 w150 h30", "Reset to Defaults").OnEvent("Click", ResetNotifSettings)
    settingsGui.Add("Button", "x260 y440 w150 h30", "Close").OnEvent("Click", (*) => settingsGui.Destroy())

    SaveNotifSettings(*) {
        saved := settingsGui.Submit(false)

        g_NotificationDefaults["timeout"] := Integer(durationEdit.Value)
        g_NotificationDefaults["dismissible"] := saved.Dismissible
        g_NotificationDefaults["stack"] := saved.StackNotifications
        g_NotificationDefaults["sound"] := saved.SoundEnabled

        ; Determine position
        if saved.PosBottomRight
            g_NotificationDefaults["position"] := "bottom-right"
        else if saved.PosBottomLeft
            g_NotificationDefaults["position"] := "bottom-left"
        else if saved.PosTopRight
            g_NotificationDefaults["position"] := "top-right"
        else if saved.PosTopLeft
            g_NotificationDefaults["position"] := "top-left"
        else if saved.PosCenter
            g_NotificationDefaults["position"] := "center"

        ShowNotificationBasic("Settings Saved", "Notification preferences updated", 2000, "success")
    }

    ResetNotifSettings(*) {
        g_NotificationDefaults["timeout"] := 5000
        g_NotificationDefaults["dismissible"] := true
        g_NotificationDefaults["stack"] := true
        g_NotificationDefaults["sound"] := false
        g_NotificationDefaults["position"] := "bottom-right"

        ShowNotificationBasic("Settings Reset", "Notification preferences reset to defaults", 2000, "success")
        settingsGui.Destroy()
    }

    settingsGui.Show("w420 h485")
}


; ═══════════════════════════════════════════════════════════════════════════════
; GDI+ SCREENSHOT FUNCTIONS
; ═══════════════════════════════════════════════════════════════════════════════
; GDI+ SCREENSHOT FUNCTIONS
; =============================================================================

ShutdownGdip(ExitReason, ExitCode) {
    global g_GdipToken
    if g_GdipToken
        Gdip_Shutdown(g_GdipToken)
    return 0
}

; Capture 100x100 region, save to screenshots folder
; If x,y provided, captures at those coords. Otherwise uses mouse position.
CapturePatternScreenshot(patternName, x := "", y := "") {
    global SCREENSHOTS_DIR

    ; If no coords provided, use mouse position
    if x = "" || y = "" {
        MouseGetPos(&x, &y)
    }

    ; 100x100 box centered on point
    regionX := x - 50
    regionY := y - 50
    regionW := 100
    regionH := 100

    ; Capture without cursor
    pBitmap := Gdip_BitmapFromScreen(regionX "|" regionY "|" regionW "|" regionH)

    if !pBitmap {
        ShowStatus("Screenshot capture failed", "fail")
        return ""
    }

    ; Clean filename (remove special chars)
    safeName := RegExReplace(patternName, "[^\w\-]", "_")
    fileName := safeName . ".png"
    savePath := SCREENSHOTS_DIR . "\" . fileName

    result := Gdip_SaveBitmapToFile(pBitmap, savePath)
    Gdip_DisposeImage(pBitmap)

    if result = 0 {
        ShowStatus("Screenshot saved: " . fileName, "ok")
        return savePath
    }

    ShowStatus("Screenshot save failed", "fail")
    return ""
}

; GDI+ Core Functions
Gdip_Startup() {
    if !DllCall("LoadLibrary", "str", "gdiplus", "UPtr")
        return 0
    si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("UInt", 1, si)
    DllCall("gdiplus\GdiplusStartup", "UPtr*", &pToken:=0, "UPtr", si.Ptr, "UPtr", 0)
    return pToken
}

Gdip_Shutdown(pToken) {
    DllCall("gdiplus\GdiplusShutdown", "UPtr", pToken)
    hModule := DllCall("GetModuleHandle", "str", "gdiplus", "UPtr")
    if hModule
        DllCall("FreeLibrary", "UPtr", hModule)
}

Gdip_BitmapFromScreen(Screen:=0, Raster:="") {
    hhdc := 0
    if (Screen = 0) {
        _x := DllCall("GetSystemMetrics", "Int", 76)
        _y := DllCall("GetSystemMetrics", "Int", 77)
        _w := DllCall("GetSystemMetrics", "Int", 78)
        _h := DllCall("GetSystemMetrics", "Int", 79)
    } else if IsInteger(Screen) {
        return 0  ; Monitor enum not implemented here
    } else {
        S := StrSplit(Screen, "|")
        _x := S[1], _y := S[2], _w := S[3], _h := S[4]
    }

    if (_x = "") || (_y = "") || (_w = "") || (_h = "")
        return 0

    chdc := CreateCompatibleDC()
    hbm := CreateDIBSection(_w, _h, chdc)
    obm := SelectObject(chdc, hbm)
    hhdc := GetDC()
    BitBlt(chdc, 0, 0, _w, _h, hhdc, _x, _y, Raster)
    ReleaseDC(hhdc)
    pBitmap := Gdip_CreateBitmapFromHBITMAP(hbm)
    SelectObject(chdc, obm)
    DeleteObject(hbm)
    DeleteDC(chdc)
    return pBitmap
}

Gdip_SaveBitmapToFile(pBitmap, sOutput, Quality:=75) {
    SplitPath(sOutput,,, &extension)
    if !RegExMatch(extension, "^(?i:BMP|DIB|RLE|JPG|JPEG|JPE|JFIF|GIF|TIF|TIFF|PNG)$")
        return -1
    extension := "." . extension
    DllCall("gdiplus\GdipGetImageEncodersSize", "uint*", &nCount:=0, "uint*", &nSize:=0)
    ci := Buffer(nSize)
    DllCall("gdiplus\GdipGetImageEncoders", "UInt", nCount, "UInt", nSize, "UPtr", ci.Ptr)
    if !(nCount && nSize)
        return -2
    pCodec := 0
    loop nCount {
        address := NumGet(ci, (idx := (48+7*A_PtrSize)*(A_Index-1))+32+3*A_PtrSize, "UPtr")
        sString := StrGet(address, "UTF-16")
        if !InStr(sString, "*" . extension)
            continue
        pCodec := ci.Ptr+idx
        break
    }
    if !pCodec
        return -3
    _p := 0
        if RegExMatch(extension, "^\.(?i:JPG|JPEG|JPE|JFIF)$") {
            DllCall("gdiplus\GdipGetEncoderParameterListSize", "UPtr", pBitmap, "UPtr", pCodec, "uint*", &nSize)
            EncoderParameters := Buffer(nSize, 0)
            DllCall("gdiplus\GdipGetEncoderParameterList", "UPtr", pBitmap, "UPtr", pCodec, "UInt", nSize, "UPtr", EncoderParameters.Ptr)
            nCount := NumGet(EncoderParameters, "UInt")
            loop nCount {
                elem := (24+(A_PtrSize ? A_PtrSize : 4))*(A_Index-1) + 4 + (pad := A_PtrSize = 8 ? 4 : 0)
                if (NumGet(EncoderParameters, elem+16, "UInt") = 1) && (NumGet(EncoderParameters, elem+20, "UInt") = 6) {
                    _p := elem + EncoderParameters.Ptr - pad - 4
                    NumPut("UInt", Quality, NumGet(NumPut("UInt", 4, NumPut("UInt", 1, _p+0)+20), "UInt"))
                    break
                }
            }
        }

    return DllCall("gdiplus\GdipSaveImageToFile", "UPtr", pBitmap, "UPtr", StrPtr(sOutput), "UPtr", pCodec, "UInt", _p ? _p : 0) ? -5 : 0
}

Gdip_CreateBitmapFromHBITMAP(hBitmap, Palette:=0) {
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "UPtr", hBitmap, "UPtr", Palette, "UPtr*", &pBitmap:=0)
    return pBitmap
}

Gdip_DisposeImage(pBitmap) {
    return DllCall("gdiplus\GdipDisposeImage", "UPtr", pBitmap)
}

CreateDIBSection(w, h, hdc:="", bpp:=32, &ppvBits:=0) {
    hdc2 := hdc ? hdc : GetDC()
    bi := Buffer(40, 0)
    NumPut("UInt", 40, "UInt", w, "UInt", h, "ushort", 1, "ushort", bpp, "UInt", 0, bi)
    hbm := DllCall("CreateDIBSection", "UPtr", hdc2, "UPtr", bi.Ptr, "UInt", 0, "UPtr*", &ppvBits, "UPtr", 0, "UInt", 0, "UPtr")
    if !hdc
        ReleaseDC(hdc2)
    return hbm
}

CreateCompatibleDC(hdc:=0) {
    return DllCall("CreateCompatibleDC", "UPtr", hdc)
}

SelectObject(hdc, hgdiobj) {
    return DllCall("SelectObject", "UPtr", hdc, "UPtr", hgdiobj)
}

DeleteObject(hObject) {
    return DllCall("DeleteObject", "UPtr", hObject)
}

GetDC(hwnd:=0) {
    return DllCall("GetDC", "UPtr", hwnd)
}

ReleaseDC(hdc, hwnd:=0) {
    return DllCall("ReleaseDC", "UPtr", hwnd, "UPtr", hdc)
}

DeleteDC(hdc) {
    return DllCall("DeleteDC", "UPtr", hdc)
}

BitBlt(ddc, dx, dy, dw, dh, sdc, sx, sy, Raster:="") {
    return DllCall("gdi32\BitBlt", "UPtr", ddc, "Int", dx, "Int", dy, "Int", dw, "Int", dh, "UPtr", sdc, "Int", sx, "Int", sy, "UInt", Raster ? Raster : 0x00CC0020)
}
