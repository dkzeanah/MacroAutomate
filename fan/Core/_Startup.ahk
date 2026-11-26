; Entry lifecycle: startup. Included by MacroAutomator.ahk.
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
try ExplorerKnowledge_Start(APP_ROOT . "\fan\DeepSeekBridge")
catch as err
    LogErrorToFile(err,"caught","Explorer path observer startup")
; Vision Scout (v9): resume the learner if it was running at last shutdown.
try VisionScout_AutoStart()
catch as err
    LogErrorToFile(err, "caught", "Vision Scout auto-start")
try UpdateElementActionChoices()
catch as err
    LogErrorToFile(err, "caught", "Tracking element name cache")
; The second local learner has an independent model and database schema. Its
; acceptance shortcut is Win+Shift+CapsLock so Vision Scout can keep Win+CapsLock.
try AutoDiscovery_Start()
catch as discoveryError
    LogErrorToFile(discoveryError, "caught", "Automatic discovery startup")
try LearningLab_Start()
catch as learningError
    LogErrorToFile(learningError, "caught", "Learning Workbench startup")
try UsagePredictor_Init()
catch as err
    LogErrorToFile(err, "caught", "Usage Predictor initialization")
; Study Assistant: create/extend its schema and resume read-along if it was on.
; Never block startup.
try Study_Init()
catch as err
    LogErrorToFile(err, "caught", "Study Assistant initialization")
; Typed-question capture switch, and the last-external-window tracker so the
; "Map window" button targets the window you were using, not this app.
try QCap_Restore()
catch as err
    LogErrorToFile(err, "caught", "QuestionCapture restore")
try Env_TrackStart()
catch as err
    LogErrorToFile(err, "caught", "Env window tracker start")
; Live Portal: restore the browser-window pin and start the console/session
; automatically. Startup uses observe/suggest until an input mode is selected.
try StudyLive_AutoStart()
catch as err
    LogErrorToFile(err, "caught", "Live Portal initialization")
try DeepBridge_AutoStart()
catch as err
    LogErrorToFile(err, "caught", "DeepSeek Bridge initialization")
try FanAPI_Start(g_DeepBridge["root"])
catch as apiStartupError
    LogErrorToFile(apiStartupError, "caught", "Fan internal agent API initialization")
; Autopilot: schema, background routine discovery (idle-only), self-heal ledger,
; the Ctrl+Alt+F9 procedure recorder, and the knowledge-base inbox watcher.
try Autopilot_Start()
catch as autopilotError
    LogErrorToFile(autopilotError, "caught", "Autopilot initialization")
try KB_Start()
catch as knowledgeError
    LogErrorToFile(knowledgeError, "caught", "Knowledge base initialization")

StatusBar.SetText("Ready | CAPSLOCK=Definition Mode | Ctrl+B=Load | Ctrl+Shift+B=Fire | ESC=Abort")


; ═══════════════════════════════════════════════════════════════════════════════
; V5.0: INITIALIZE INSTRUCTIONS FILE

InitializeInstructions()
FanHome_Refresh()
SetTimer(LearningHub_State, 1500)
ChromeLearning_Start()
; An explicit startup view for a local, non-interfering demonstration using
; the actual stored learner inventory. Normal startup stays quiet.
if A_Args.Length && A_Args[1] = "--learning-workbench"
    SetTimer(LearningWorkbench_Open,-1500)
if A_Args.Length && A_Args[1] = "--live-workbench"
    SetTimer(AgentWorkbench_Open,-1500)
if A_Args.Length>=2 && A_Args[1]="--bridge-prompt"
    SetTimer(DeepBridge_LoadPrompt.Bind(A_Args[2],A_Args.Length>=3 && A_Args[3]="--send"),-1500)
if A_Args.Length>=2 && A_Args[1]="--bridge-results"
    SetTimer(DeepBridge_ShowResults.Bind(A_Args[2]),-1500)



; ═══════════════════════════════════════════════════════════════════════════════
; V5.0: ENHANCED NOTIFICATION SYSTEM

; -- end of the auto-execute section; everything else is function definitions --
