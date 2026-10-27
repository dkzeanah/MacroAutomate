; ===============================================================================
; Core\_Globals.ahk
; Globals: every g_* global, file-path constants, default settings map
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================



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
global g_LoopBreakRequested := false  ; Set by Loop Break / Popup Detect to leave a loop
global g_ActionFormGui := ""          ; The guided Action Form dialog, when open
global g_FormPickMap := Map()         ; Button hwnd -> {combo, mode, gui} for form picker helpers
global g_FormFieldMap := Map()        ; Field key -> control refs inside the Action Form
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
global g_SpoolLastStatus := Map()   ; Last detection/action result shown in the Spool list
global g_SpoolWorkflowActive := false ; Prevent overlapping timer-launched workflows
global g_SpoolStartedAt := Map()    ; Timer start ticks for optional completion rules
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

; Built-in, non-destructive workflow demonstration sandbox.
global g_DemoLabGui := 0
global g_DemoLabControls := Map()
global g_DemoLabLogEdit := 0
global g_DemoLabStatusText := 0
global g_DemoClipboardActive := false
global g_DemoLabStateSaved := false
global g_DemoLabSavedClipboard := 0
global g_DemoLabSavedMouseX := 0
global g_DemoLabSavedMouseY := 0

global DATA_DIR := APP_ROOT . "\data"
global LOG_DIR := DATA_DIR . "\logs"
global ERROR_LOG_FILE := LOG_DIR . "\MacroAutomator_errors.log"
global COORDS_FILE := DATA_DIR . "\coordinates.csv"
global SEQUENCES_FILE := DATA_DIR . "\sequences.ini"
global HOTKEYS_FILE := DATA_DIR . "\hotkeys.ini"
global SETTINGS_FILE := DATA_DIR . "\settings.ini"
global RULES_FILE := DATA_DIR . "\extraction_rules.csv"
global PATTERNS_FILE := DATA_DIR . "\patterns.ini"
global SPOOLS_FILE := DATA_DIR . "\spools.ini"
global SPOOL_ACTIVITY_LOG_FILE := LOG_DIR . "\spool_activity.log"
global OCR_LOG_FILE := DATA_DIR . "\ocr_log.txt"
global OCR_WORDS_FILE := DATA_DIR . "\ocr_words.ini"
global DB_FILE := FanData_DbPath("macro", DATA_DIR . "\macroauto.sqlite")
global g_DB := 0
global ANALYTICS_FILE := DATA_DIR . "\analytics.ini"
global RECORDING_FILE := DATA_DIR . "\recording.csv"
global PREVIEW_DIR := DATA_DIR . "\previews"
global SCREENSHOTS_DIR := DATA_DIR . "\screenshots"
global TRACKING_DIR := DATA_DIR . "\tracking"   ; tracking subsystem output root

; Cached list of registered element names (for workflow action dropdowns).
global g_ElementNames := []

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
global INSTRUCTIONS_FILE := APP_ROOT . "\MacroAutomator_v7_Feature_Guide.txt"
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
    "SaveFolder", DATA_DIR "\screenshots",
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
    "PreviewTooltipDuration", 3000,
    "SpoolMasterEnabled", false
)

