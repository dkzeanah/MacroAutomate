
#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir(A_ScriptDir)  ; Set working directory to script location
CoordMode("Mouse", "Screen") ; Mouse coordinates relative to screen
CoordMode("Pixel", "Screen") ; Pixel coordinates relative to screen
CoordMode("ToolTip", "Screen")
#Include FindText.ahk
#Include *i OCR.ahk
#Requires AutoHotkey v2.0
#SingleInstance Force

SetWorkingDir(A_ScriptDir)
CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

#Include FindText.ahk
global g_TaskPresets := Map()


global g_AppointmentTypes := Map()


global g_Patients := Map()
global g_NextPatientID := 1

global g_Coordinates := Map()
global g_Sequences := Map()
global g_ExtractedData := Map()
global g_HotkeyBindings := Map()
global g_Settings := Map()
global g_ExtractionRules := []
global g_Patterns := Map()

global g_IsCapturing := false
global g_IsPaused := false
global g_DragMode := false
global g_DragStartX := 0, g_DragStartY := 0
global g_IsRecording := false
global g_RecordedActions := []
global g_IsCalibrating := false
global g_CurrentSequenceSteps := []
global g_CurrentSequenceSpeed := 1.0  ; Speed multiplier (1.0 = normal)
global g_SimulationTooltipIndex := 1  ; For stacking tooltips (1-20)
global g_AbortSequence := false

global g_GuiVisible := true
global g_AlwaysOnTop := false
global g_ClickThrough := false
global g_Transparency := 255
global g_ActionCounter := 0
global g_TotalActions := 0
global g_PointCounter := 1
global g_DragCounter := 1
global g_RelCounter := 1
global g_LastClickX := 0, g_LastClickY := 0
global g_DefinitionMode := false
global g_FullRecording := false
global g_FullRecordLog := []
global g_Analytics := Map()
global g_WindowHotspots := Map()
global g_ActionFrequency := Map()
global g_DefModeStartX := 0
global g_DefModeStartY := 0
global g_DefModeDragging := false
global g_TaskbarApps := []
global g_RevolverLoaded := false
global g_RevolverChamber := []      ; Array of field values in paste order
global g_RevolverPosition := 1      ; Current chamber position
global g_RevolverFieldOrder := []   ; Configurable field order
global g_RevolverActive := false    ; Is revolver mode active (intercept Ctrl+V)
global g_Spools := Map()            ; All defined spools
global g_ActiveSpools := Map()      ; Currently running spool timers
global g_SpoolMasterEnabled := false ; Master on/off switch
global g_SpoolVariables := Map()    ; OCR-extracted variables
global g_SpoolNotifications := []   ; Active notification windows
global g_SpoolLog := []             ; Activity log entries
global g_SpoolRegions := Map()      ; Custom monitor regions
global g_NotificationCounter := 0   ; Unique notification IDs
global g_SpoolCooldown := Map()     ; Cooldown timestamps per spool
global g_NotificationDefaults := Map(
    "timeout", 5,                   ; Default auto-dismiss seconds
    "pauseSpools", true,            ; Pause spools while notification showing
    "stackDirection", "up"          ; Stack direction: up or down
)
global g_OCRLog := []               ; Live OCR recording log
global g_OCRRecording := false      ; Is live OCR recording active
global g_OCRSettings := Map(
    "language", "en-us",
    "scale", 1.0,
    "grayscale", false,
    "interval", 500                 ; Live OCR refresh rate
)
global g_OCRHighlight := ""
global g_Overlays := Map()          ; Active overlay GUIs by ID
global g_OverlayCounter := 0        ; Unique overlay IDs
global g_OverlayStyles := Map(
    "highlight", Map("color", "FF0000", "thickness", 3, "fill", false),
    "selection", Map("color", "00FF00", "thickness", 2, "fill", true, "fillAlpha", 80),
    "match", Map("color", "FFFF00", "thickness", 2, "fill", false),
    "error", Map("color", "FF0000", "thickness", 4, "fill", false),
    "info", Map("color", "00AAFF", "thickness", 2, "fill", false),
    "word", Map("color", "00FF00", "thickness", 2, "fill", false),
    "pattern", Map("color", "FF00FF", "thickness", 3, "fill", false)
)
global g_WatchWords := Map()        ; Words being monitored: name -> {pattern, region, lastValue, lastCoords}
global g_DetectedWords := []        ; Current OCR detection results with coords
global g_WordVariables := Map()     ; Extracted word values: $word.PatientName, etc.
global g_OCRRevolver := []          ; Array of text parts to paste
global g_OCRRevolverIndex := 0      ; Current position in revolver (0-based)
global g_LastOCRText := ""          ; Last captured OCR text (for re-use)
global g_LastOCRRegion := Map()     ; Last OCR region coords

global DATA_DIR := A_ScriptDir . "\data"
global COORDS_FILE := DATA_DIR . "\coordinates.csv"
global SEQUENCES_FILE := DATA_DIR . "\sequences.ini"
global HOTKEYS_FILE := DATA_DIR . "\hotkeys.ini"
global SETTINGS_FILE := DATA_DIR . "\settings.ini"
global RULES_FILE := DATA_DIR . "\extraction_rules.csv"
global PATTERNS_FILE := DATA_DIR . "\patterns.ini"
global SPOOLS_FILE := DATA_DIR . "\spools.ini"
global OCR_LOG_FILE := DATA_DIR . "\ocr_log.txt"
global OCR_WORDS_FILE := DATA_DIR . "\ocr_words.ini"
global ANALYTICS_FILE := DATA_DIR . "\analytics.ini"
global RECORDING_FILE := DATA_DIR . "\recording.csv"
global PREVIEW_DIR := DATA_DIR . "\previews"
global SCREENSHOTS_DIR := DATA_DIR . "\screenshots"
global g_GdipToken := 0
global g_NotepadPopupGui := 0          ; Popup notepad window reference
global g_NotepadContent := ""          ; Current notepad content
global NOTES_DIR := DATA_DIR . "\notes"
global g_NotificationSnoozeTimers := Map()  ; Notification ID -> snooze sequence
global g_NotificationData := Map()
global g_RevolverBins := Map()         ; Bin name -> {items: [], formatRules: [], notifyBlock: true}
global g_RevolverCurrentBin := ""      ; Current active bin for pasting
global g_RevolverBinOrder := []        ; Order to process bins (top bin first)
global g_RevolverBinSelector := 0     ; Bin selection GUI reference
global g_RevolverBinNotifications := Map()
global g_MouseIdleTimer := 0           ; Timer for mouse idle monitoring
global g_MouseIdleActive := false      ; Is idle mode active?
global g_MouseIdleDuration := 0        ; How long to idle (0 = indefinite)
global g_MouseLastX := 0               ; Last known mouse X position
global g_MouseLastY := 0               ; Last known mouse Y position
global g_MouseHarshThreshold := 50
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
global g_Hotstrings := Map()            ; All defined hotstrings
global g_HotstringActive := true        ; Master on/off
global g_HotstringOptions := Map(
    "caseSensitive", false,
    "endChars", " `t",
    "reset", false,
    "autoBackspace", true
)
global g_ActionErrors := Map()          ; Track errors per action type
global g_LastActionError := ""
global INSTRUCTIONS_FILE := DATA_DIR . "\instructions.txt"
global HOTSTRINGS_FILE := DATA_DIR . "\hotstrings.txt"
global SCHEDULE_FILE := DATA_DIR . "\notification_schedule.txt"
global g_NotificationStack := []        ; Array of active notification GUIs
global g_NotificationY := 0             ; Current Y position for next notification
global g_DebugMode := true              ; Show step-by-step execution notifications
global g_NotificationDismissible := true ; Notifications stay until dismissed
global g_NotificationTimeout := 0
global g_StepThroughMode := false       ; Pause after each step
global g_StepThroughWaiting := false    ; Currently waiting for Tab key
global g_StepThroughContinue := false
global g_SequenceHotkeys := Map()      ; Map of hotkey -> sequence name
global g_SequenceHotstrings := Map()   ; Map of hotstring -> sequence name
global g_RegisteredHotkeys := []       ; Track registered hotkeys for cleanup
global g_RegisteredHotstrings := []
global g_ParamValidators := Map()      ; Validators per action type
global g_ParamHints := Map()           ; Live hints for parameters
global g_ValidationErrors := []
global g_ActionTemplates := Map()      ; Pre-built workflow templates
global TEMPLATES_FILE := DATA_DIR . "\templates.json"
global g_NotificationTriggers := Map() ; All notification triggers
global g_TriggerMonitorTimer := ""     ; Timer function for trigger monitoring
global g_TriggerActions := Map()       ; Actions to execute per trigger
global g_TriggerConditions := Map()   ; Conditions for triggers
global g_TriggerLog := []              ; Trigger execution history
global g_ActiveMonitors := Map()       ; Active monitoring tasks
global TRIGGERS_FILE := DATA_DIR . "\notification_triggers.json"

global g_Screenshots := Map()
global g_NextScreenshotID := 1
global g_SelectedScreenshotID := 0
global g_ScreenshotSettings := Map(
    "SaveFolder", A_ScriptDir "\Screenshots",
    "Format", "PNG",
    "AutoSave", true,
    "ShowPreview", true
)
global g_Appointments := Map()
global g_CalendarDate := FormatTime(, "yyyy-MM-dd")
global g_TimeSlotButtons := Map()
global g_DateDisplayText := ""

global MarkerGui := ""

global g_OCRRegion := Map("x1", 0, "y1", 0, "x2", 0, "y2", 0)  ; Custom OCR region
global g_LastOCRResult := ""
global g_OCRAvailable := false
global g_WorkflowVariables := Map()  ; Variables created during workflow execution
global g_SkipNextAction := falseA_TrayMenu.Add("Show/Hide", TrayShowHide)
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

global TASKBAR_FILE := DATA_DIR . "\taskbar.ini"

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
if !DirExist(PREVIEW_DIR)
    DirCreate(PREVIEW_DIR)
if !DirExist(SCREENSHOTS_DIR)
    DirCreate(SCREENSHOTS_DIR)
if !DirExist(NOTES_DIR)
    DirCreate(NOTES_DIR)
g_GdipToken := Gdip_Startup()
OnExit(ShutdownGdip)

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
IsNearCloseButton(x, y, tolerance := 50) {
    taskbarHeight := 48  ; Standard Windows 11 taskbar height
    if y > A_ScreenHeight - taskbarHeight
        return false    
        if x < 100 || y < 50
        return false

    try {
        hwnd := DllCall("WindowFromPoint", "Int64", (y << 32) | (x & 0xFFFFFFFF), "Ptr")
        if !hwnd
            return false
        WinGetPos(&wx, &wy, &ww, &wh, hwnd)
        winClass := WinGetClass(hwnd)
        if InStr(winClass, "Shell_") || InStr(winClass, "Taskbar") || InStr(winClass, "Tray")
            return false
        closeX := wx + ww - 25
        closeY := wy + 15
        if Abs(x - closeX) < tolerance && Abs(y - closeY) < tolerance
            return true
    }
    return false
}


IndexTaskbarManual() {
    global g_TaskbarApps, MainGui, TASKBAR_FILE
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
    MainGui.Hide()
    Sleep(500)

    g_TaskbarApps := []
    originalHwnd := WinExist("A")
    Loop 10 {
        keyNum := A_Index = 10 ? "0" : String(A_Index)

        ShowTooltipTimed("Indexing Win+" . keyNum . "...", 800)
        Send("#" . keyNum)
        Sleep(400)        activeHwnd := 0
        activeTitle := ""
        activeExe := ""
        activeClass := ""

        try {
            activeHwnd := WinExist("A")
            activeTitle := WinGetTitle(activeHwnd)
            activeExe := WinGetProcessName(activeHwnd)
            activeClass := WinGetClass(activeHwnd)
        }
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
    if originalHwnd
        try WinActivate(originalHwnd)

    Sleep(300)
    MainGui.Show()
    SaveTaskbarIndex()
    RefreshTaskbarLV()
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
CreateOverlay(x, y, w, h, style := "highlight", duration := 0, label := "") {
    global g_Overlays, g_OverlayCounter, g_OverlayStyles

    g_OverlayCounter++
    id := g_OverlayCounter
    if !g_OverlayStyles.Has(style)
        style := "highlight"
    s := g_OverlayStyles[style]

    color := s["color"]
    thick := s["thickness"]
    fill := s.Has("fill") ? s["fill"] : false
    fillAlpha := s.Has("fillAlpha") ? s["fillAlpha"] : 50
    if fill {
        overlayGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "Overlay" . id)
        overlayGui.BackColor := color
        overlayGui.Show("x" . x . " y" . y . " w" . w . " h" . h . " NoActivate")
        WinSetTransparent(fillAlpha, overlayGui)

        g_Overlays[id] := Map("type", "filled", "gui", overlayGui, "x", x, "y", y, "w", w, "h", h)
    } else {
        borders := []
        topGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "OverlayTop" . id)
        topGui.BackColor := color
        topGui.Show("x" . x . " y" . y . " w" . w . " h" . thick . " NoActivate")
        borders.Push(topGui)
        bottomGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "OverlayBottom" . id)
        bottomGui.BackColor := color
        bottomGui.Show("x" . x . " y" . (y + h - thick) . " w" . w . " h" . thick . " NoActivate")
        borders.Push(bottomGui)
        leftGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "OverlayLeft" . id)
        leftGui.BackColor := color
        leftGui.Show("x" . x . " y" . y . " w" . thick . " h" . h . " NoActivate")
        borders.Push(leftGui)
        rightGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "OverlayRight" . id)
        rightGui.BackColor := color
        rightGui.Show("x" . (x + w - thick) . " y" . y . " w" . thick . " h" . h . " NoActivate")
        borders.Push(rightGui)

        g_Overlays[id] := Map("type", "border", "borders", borders, "x", x, "y", y, "w", w, "h", h)
    }
    if label != "" {
        labelGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "OverlayLabel" . id)
        labelGui.BackColor := "1a1a2e"
        labelGui.SetFont("s9 cWhite", "Consolas")
        labelGui.Add("Text", "x2 y1 c" . color, label)
        labelGui.Show("x" . x . " y" . (y - 18) . " NoActivate AutoSize")
        WinSetTransparent(220, labelGui)
        g_Overlays[id]["label"] := labelGui
    }
    if duration > 0 {
        removeFunc := (*) => RemoveOverlay(id)
        SetTimer(removeFunc, -duration)
    }

    return id
}
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
    if overlay.Has("label")
        try overlay["label"].Destroy()

    g_Overlays.Delete(id)
}
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
HighlightRegion(x, y, w, h, duration := 2000, style := "highlight", label := "") {
    return CreateOverlay(x, y, w, h, style, duration, label)
}
HighlightOCRWords(words, duration := 2000, style := "word") {
    ids := []
    for word in words {
        id := CreateOverlay(word.x, word.y, word.w, word.h, style, duration, word.Text)
        ids.Push(id)
    }
    return ids
}
FlashHighlight(x, y, w, h, times := 3, interval := 200, style := "highlight") {
    flashFunc := FlashHighlightWorker.Bind(x, y, w, h, times, interval, style, 0, 0)
    flashFunc()
}

FlashHighlightWorker(x, y, w, h, times, interval, style, count, overlayId) {
    global g_Overlays

    if count >= times * 2
        return

    if Mod(count, 2) = 0 {
        overlayId := CreateOverlay(x, y, w, h, style, 0)
    } else {
        RemoveOverlay(overlayId)
        overlayId := 0
    }

    nextFunc := FlashHighlightWorker.Bind(x, y, w, h, times, interval, style, count + 1, overlayId)
    SetTimer(nextFunc, -interval)
}
ShowCoordTooltip(x, y, text := "", duration := 2000) {
    if text = ""
        text := "X: " . x . " Y: " . y
    ToolTip(text, x + 15, y + 15)
    if duration > 0
        SetTimer(() => ToolTip(), -duration)
}
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
        if watch["labelIndex"] = 0 {
            value := result.Text
            coords := Map("x", region["x1"], "y", region["y1"], "w", w, "h", h)
        } else if watch["labelIndex"] <= result.Words.Length {
            word := result.Words[watch["labelIndex"]]
            value := word.Text
            coords := Map("x", word.x, "y", word.y, "w", word.w, "h", word.h)
        } else {
            return false
        }
        if watch["pattern"] != "" {
            if RegExMatch(value, watch["pattern"], &match)
                value := match[0]
        }
        watch["lastValue"] := value
        watch["lastCoords"] := coords
        watch["lastUpdate"] := A_TickCount
        g_WordVariables["$word." . name] := value
        g_SpoolVariables["$word." . name] := value

        return true
    } catch {
        return false
    }
}
UpdateAllWatchWords() {
    global g_WatchWords

    for name, watch in g_WatchWords {
        UpdateWatchWord(name)
    }
}
GetWatchWordValue(name) {
    global g_WatchWords

    if !g_WatchWords.Has(name)
        return ""

    return g_WatchWords[name]["lastValue"]
}
GetWatchWordCoords(name) {
    global g_WatchWords

    if !g_WatchWords.Has(name)
        return Map("x", 0, "y", 0, "w", 0, "h", 0)

    return g_WatchWords[name]["lastCoords"]
}
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
HighlightWatchWord(name, duration := 2000) {
    global g_WatchWords

    if !g_WatchWords.Has(name)
        return 0

    coords := g_WatchWords[name]["lastCoords"]
    if coords["w"] = 0
        return 0

    return HighlightRegion(coords["x"], coords["y"], coords["w"], coords["h"], duration, "word", name . ": " . g_WatchWords[name]["lastValue"])
}
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
    if currentName != "" && currentWatch.Has("region") {
        g_WatchWords[currentName] := currentWatch
    }
}
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
            px := ok[1].x
            py := ok[1].y
            pw := ok[1].w
            ph := ok[1].h
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
        "target", "",
        "param", x . "," . y,
        "enabled", 1,
        "window", win["title"],
        "pattern", patternName,
        "failsafe", "close_button"
    )
    g_CurrentSequenceSteps.Push(step)
    RefreshStepsLV()
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
        "target", "",
        "param", x . "," . y,
        "enabled", 1,
        "window", win["title"],
        "pattern", patternName
    )
    g_CurrentSequenceSteps.Push(step)
    RefreshStepsLV()
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
        "target", "",
        "param", x . "," . y,
        "enabled", 1,
        "window", win["title"]
    )
    g_CurrentSequenceSteps.Push(step)
    RefreshStepsLV()
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
        ShowStatus("Added Send Keys: " . res["Value"], "ok")
    }
}

DefModeCancel() {
    global g_DefModeDragging
    g_DefModeDragging := false
    HideMarker()
    ToolTip()
}
AutoCapturePatternAt(x, y, size := 30) {
    global g_Patterns, g_Settings, PREVIEW_DIR, SCREENSHOTS_DIR

    try {
        x1 := x - size
        y1 := y - size
        x2 := x + size
        y2 := y + size
        text := FindText().GetTextFromScreen(x1, y1, x2, y2, "**50")

        if text = "" || StrLen(text) < 10
            return ""

        patternNum := 1
        while g_Patterns.Has("Auto_" . patternNum)
            patternNum++
        name := "Auto_" . patternNum

        patternText := "|<" . name . ">" . text
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
SavePatternPreview(name, x1, y1, x2, y2) {
    global PREVIEW_DIR
    try {
        FindText().ScreenShot(x1, y1, x2, y2)
        previewPath := PREVIEW_DIR . "\" . name . ".bmp"
    }
}
ShowPatternPreviewTooltip(patternName, x := "", y := "") {
    global g_Patterns, g_Settings

    if !g_Patterns.Has(patternName)
        return

    patternData := g_Patterns[patternName]
    code := patternData["text"]
    desc := patternData.Has("desc") ? patternData["desc"] : ""
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
PatternToVisualPreview(patternText, maxWidth := 40, maxHeight := 15) {
    if patternText = "" || !InStr(patternText, "$")
        return "[Invalid pattern]"

    if !RegExMatch(patternText, "\$(\d+)\.(.+)", &m)
        return "[Parse error]"

    width := Integer(m[1])
    data := m[2]
    charMap := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/"
    scaleX := width > maxWidth ? Ceil(width / maxWidth) : 1

    result := ""
    row := ""
    pixelCount := 0
    rowCount := 0

    for i, char in StrSplit(data) {
        pos := InStr(charMap, char) - 1
        if pos < 0
            pos := 0
        bits := ""
        Loop 6 {
            bit := (pos >> (5 - A_Index + 1)) & 1
            bits .= bit ? "#" : " "
        }
        if Mod(pixelCount, scaleX) = 0 {
            for j, b in StrSplit(bits) {
                if Mod(j - 1, scaleX) = 0
                    row .= b
            }
        }

        pixelCount += 6
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
    previewGui := Gui("+AlwaysOnTop +ToolWindow", "Pattern: " . patternName)
    previewGui.SetFont("s9", "Segoe UI")
    previewGui.Add("GroupBox", "w630 h90 Section", "Pattern Information")
    previewGui.Add("Text", "xp+10 yp+18 w150", "Name: " . patternName)
    previewGui.Add("Text", "x+10 w450", "Description: " . (desc != "" ? desc : "(none)"))

    previewGui.Add("Text", "xs+10 y+5 w150", "Location: " . captureX . ", " . captureY)
    previewGui.Add("Text", "x+10 w450", "Window: " . (captureWindow != "" ? captureWindow : "(none)"))

    previewGui.Add("Text", "xs+10 y+5 w150", "Qualifier: " . (qualifier != "" ? qualifier : "(none)"))
    if qualifier != "" {
        qualOK := CheckPatternQualifier(qualifier)
        previewGui.Add("Text", "x+10 w100 " . (qualOK ? "cGreen" : "cRed"), qualOK ? "✓ Found" : "✗ Not found")
    }
    previewGui.Add("GroupBox", "xs y+15 w420 h340 Section", "ASCII Preview")
    previewGui.SetFont("s6", "Consolas")
    preview := PatternToVisualPreview(code, 65, 30)
    previewGui.Add("Edit", "xp+10 yp+18 w400 h310 ReadOnly Multi", preview)
    previewGui.SetFont("s9", "Segoe UI")
    previewGui.Add("GroupBox", "ys x440 w200 h170", "Screenshot")

    if screenshotPath != "" && FileExist(screenshotPath) {
        previewGui.Add("Picture", "xp+50 yp+20 w100 h100 Border", screenshotPath)
        previewGui.Add("Button", "xp-25 y+10 w150 h22", "Open Image").OnEvent("Click", (*) => Run(screenshotPath))
    } else {
        previewGui.Add("Text", "xp+10 yp+40 w180 h60 Center", "(No screenshot)`n`nUse 📷 Find to capture")
    }
    previewGui.Add("GroupBox", "x440 y+20 w200 h150", "Capture Data")
    previewGui.Add("Text", "xp+10 yp+20", "Coordinates:")
    previewGui.Add("Text", "xp+10 y+2 w170 cBlue", captureX . ", " . captureY)
    previewGui.Add("Text", "xp-10 y+10", "Window Title:")
    previewGui.Add("Text", "xp+10 y+2 w170 cBlue", captureWindow != "" ? SubStr(captureWindow, 1, 25) : "(none)")
    previewGui.Add("Text", "xp-10 y+10", "Qualifier Pattern:")
    previewGui.Add("Text", "xp+10 y+2 w170 cBlue", qualifier != "" ? qualifier : "(none)")
    previewGui.SetFont("s7", "Consolas")
    previewGui.Add("Text", "x10 y+20", "Pattern Code:")
    previewGui.Add("Edit", "w630 h45 ReadOnly", code)
    previewGui.SetFont("s9", "Segoe UI")
    previewGui.Add("Button", "y+10 w100", "Test").OnEvent("Click", (*) => TestPatternByName(patternName))
    previewGui.Add("Button", "x+10 w100", "Close").OnEvent("Click", (*) => previewGui.Destroy())

    previewGui.Show()
}

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
    patternName := StrReplace(patternName, "[P] ", "")
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
CheckPatternQualifier(qualifierName) {
    global g_Patterns, g_Settings

    if qualifierName = "" || qualifierName = "(none)"
        return true    
        if !g_Patterns.Has(qualifierName)
        return false

    code := g_Patterns[qualifierName]["text"]
    tolerance := g_Settings["FindTextTolerance"]

    ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)

    return (ok && ok.Length > 0)
}

FindAndDragPattern(patternName, endX, endY, tolerance := "") {
    global g_Settings, g_AbortSequence, g_LastClickX, g_LastClickY, g_Patterns
    patternName := StrReplace(patternName, "[P] ", "")
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

ShowStepPreview(stepData) {
    global g_Coordinates, g_Patterns, g_Settings

    action := stepData["action"]
    target := stepData["target"]
    param := stepData["param"]

    tip := "=== STEP PREVIEW ===`n"
    tip .= "Action: " . action . "`n"
    if param != "" && InStr(param, ",") {
        if InStr(param, "->") {
            parts := StrSplit(param, "->")
            tip .= "From: " . parts[1] . "`n"
            tip .= "To: " . parts[2] . "`n"
        } else {
            tip .= "Position: " . param . "`n"
        }
    }
    if target != "" && target != "(none)" {
        tip .= "Target: " . target . "`n"
        if g_Patterns.Has(target) {
            tip .= "---Pattern---`n"
            tip .= PatternToVisualPreview(g_Patterns[target]["text"], 30, 8)
        }
        else if g_Coordinates.Has(target) {
            c := g_Coordinates[target]
            tip .= "Coord: " . c["x"] . "," . c["y"]
            if c["endX"] != ""
                tip .= " -> " . c["endX"] . "," . c["endY"]
            tip .= "`n"
        }
    }
    if stepData.Has("qualWindow") && stepData["qualWindow"] != ""
        tip .= "Window: " . stepData["qualWindow"] . "`n"

    MouseGetPos(&mx, &my)
    ToolTip(tip, mx + 20, my + 20)
    SetTimer(() => ToolTip(), -g_Settings["PreviewTooltipDuration"])
}

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
    for varName, value in g_ExtractedData {
        if InStr(text, varName) {
            text := StrReplace(text, varName, value)
        }
    }
    
    A_Clipboard := ""
    Sleep(50)
    A_Clipboard := text
    ClipWait(1, 0)
    if A_Clipboard = text {
        ShowNotificationBasic("Clipboard Set", "Copied to clipboard:`n`n" . SubStr(text, 1, 200) . (StrLen(text) > 200 ? "..." : ""), 0, "success", text)
        return true
    }
    
    return false
}

ExecuteKeyChord(param) {
    global g_Settings

    if param = "" || !InStr(param, ",") {
        ShowStatus("Key Chord format: modifier,key,count (e.g. #,5,2)", "fail")
        return false
    }
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
    modDisplay := ""
    if InStr(modifier, "#") modDisplay .= "Win+"
    if InStr(modifier, "^") modDisplay .= "Ctrl+"
    if InStr(modifier, "+") modDisplay .= "Shift+"
    if InStr(modifier, "!") modDisplay .= "Alt+"

    ShowStatus("Key Chord: " . modDisplay . key . " x" . repeatCount, "wait")

    Sleep(g_Settings["PreActionDelay"])
    if InStr(modifier, "#") Send("{LWin down}")
    if InStr(modifier, "^") Send("{Ctrl down}")
    if InStr(modifier, "+") Send("{Shift down}")
    if InStr(modifier, "!") Send("{Alt down}")

    Sleep(50)    
    Loop repeatCount {
        Send(key)
        if A_Index < repeatCount
            Sleep(100)  ; Delay between presses
    }

    Sleep(50)    
    if InStr(modifier, "!") Send("{Alt up}")
    if InStr(modifier, "+") Send("{Shift up}")
    if InStr(modifier, "^") Send("{Ctrl up}")
    if InStr(modifier, "#") Send("{LWin up}")

    Sleep(g_Settings["PostActionDelay"])

    ShowStatus("Sent: " . modDisplay . key . " x" . repeatCount, "ok")
    return true
}

ExecuteTaskbarActivate(param) {
    global g_Settings

    if param = "" || !InStr(param, ",") {
        ShowStatus("Taskbar format: position,count (e.g. 5,2)", "fail")
        return false
    }
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
    keyNum := position = 10 ? "0" : String(position)

    ShowStatus("Taskbar: Win+" . keyNum . " x" . repeatCount, "wait")

    Sleep(g_Settings["PreActionDelay"])
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

ShowMarker(x, y, duration := 1500, color := "Red") {
    global MarkerGui, g_Settings
    try {
        if IsObject(MarkerGui)
            MarkerGui.Destroy()
    }
    MarkerGui := ""
    try {
        MarkerGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
        MarkerGui.BackColor := "FFFFFF"
        WinSetTransColor("FFFFFF", MarkerGui)
        MarkerGui.SetFont("s20 bold", "Arial")
        MarkerGui.Add("Text", "c" . color . " Center", "X")
        posX := x + (g_Settings.Has("MarkerOffsetX") ? g_Settings["MarkerOffsetX"] : 0) - 8
        posY := y + (g_Settings.Has("MarkerOffsetY") ? g_Settings["MarkerOffsetY"] : 0) - 10

        MarkerGui.Show("x" . posX . " y" . posY . " NA")
        SetTimer(HideMarker, -duration)
    } catch as err {
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

SavePatterns() {
    global g_Patterns, PATTERNS_FILE
    try {
        if FileExist(PATTERNS_FILE)
            FileDelete(PATTERNS_FILE)
        for name, data in g_Patterns {
            IniWrite(data["text"], PATTERNS_FILE, name, "Text")
            IniWrite(data.Has("desc") ? data["desc"] : "", PATTERNS_FILE, name, "Desc")
            IniWrite(data.Has("screenshot") ? data["screenshot"] : "", PATTERNS_FILE, name, "Screenshot")
            IniWrite(data.Has("captureX") ? data["captureX"] : 0, PATTERNS_FILE, name, "CaptureX")
            IniWrite(data.Has("captureY") ? data["captureY"] : 0, PATTERNS_FILE, name, "CaptureY")
            IniWrite(data.Has("captureWindow") ? data["captureWindow"] : "", PATTERNS_FILE, name, "CaptureWindow")
            IniWrite(data.Has("qualifier") ? data["qualifier"] : "", PATTERNS_FILE, name, "Qualifier")
        }
    }
}

LoadPatterns() {
    global g_Patterns, PATTERNS_FILE
    if !FileExist(PATTERNS_FILE)
        return
    g_Patterns := Map()
    sections := IniRead(PATTERNS_FILE)
    for section in StrSplit(sections, "`n") {
        if section = ""
            continue
        text := IniRead(PATTERNS_FILE, section, "Text", "")
        desc := IniRead(PATTERNS_FILE, section, "Desc", "")
        screenshot := IniRead(PATTERNS_FILE, section, "Screenshot", "")
        captureX := IniRead(PATTERNS_FILE, section, "CaptureX", 0)
        captureY := IniRead(PATTERNS_FILE, section, "CaptureY", 0)
        captureWindow := IniRead(PATTERNS_FILE, section, "CaptureWindow", "")
        qualifier := IniRead(PATTERNS_FILE, section, "Qualifier", "")
        if text != ""
            g_Patterns[section] := Map(
                "text", text,
                "desc", desc,
                "screenshot", screenshot,
                "captureX", Integer(captureX),
                "captureY", Integer(captureY),
                "captureWindow", captureWindow,
                "qualifier", qualifier
            )
    }
}

SaveSequences() {
    global g_Sequences, SEQUENCES_FILE
    try {
        if FileExist(SEQUENCES_FILE)
            FileDelete(SEQUENCES_FILE)
        for seqName, seqData in g_Sequences {
            for i, step in seqData["steps"] {
                IniWrite(step["action"] . "|" . step["target"] . "|" . step["param"] . "|" . (step.Has("enabled") ? step["enabled"] : 1), SEQUENCES_FILE, seqName, "Step" . i)
                if step.Has("failsafe") && step["failsafe"].Count > 0 {
                    fsStr := SerializeFailsafe(step["failsafe"])
                    IniWrite(fsStr, SEQUENCES_FILE, seqName, "Failsafe" . i)
                }
            }
            IniWrite(seqData["steps"].Length, SEQUENCES_FILE, seqName, "_Count")
            speed := seqData.Has("speed") ? seqData["speed"] : 1.0
            IniWrite(speed, SEQUENCES_FILE, seqName, "_Speed")
        }
    }
}
SerializeFailsafe(fs) {
    parts := []
    for key, val in fs {
        if val != "" && val != 0
            parts.Push(key . "=" . String(val))
    }
    return StrJoin(parts, ";")
}
DeserializeFailsafe(str) {
    fs := Map()
    if str = ""
        return fs
    for part in StrSplit(str, ";") {
        eq := InStr(part, "=")
        if eq > 0 {
            key := SubStr(part, 1, eq - 1)
            val := SubStr(part, eq + 1)
            if IsNumber(val)
                fs[key] := Number(val)
            else
                fs[key] := val
        }
    }
    return fs
}

LoadSequences() {
    global g_Sequences, SEQUENCES_FILE
    if !FileExist(SEQUENCES_FILE)
        return
    g_Sequences := Map()
    sections := IniRead(SEQUENCES_FILE)
    for section in StrSplit(sections, "`n") {
        if section = ""
            continue
        count := IniRead(SEQUENCES_FILE, section, "_Count", 0)
        speed := IniRead(SEQUENCES_FILE, section, "_Speed", 1.0)
        steps := []
        Loop count {
            data := IniRead(SEQUENCES_FILE, section, "Step" . A_Index, "")
            if data = ""
                continue
            p := StrSplit(data, "|")
            step := Map("action", p[1], "target", p.Length >= 2 ? p[2] : "", "param", p.Length >= 3 ? p[3] : "", "enabled", p.Length >= 4 ? Integer(p[4]) : 1)
            fsData := IniRead(SEQUENCES_FILE, section, "Failsafe" . A_Index, "")
            if fsData != ""
                step["failsafe"] := DeserializeFailsafe(fsData)

            steps.Push(step)
        }
        if steps.Length > 0
            g_Sequences[section] := Map("steps", steps, "speed", Float(speed))
    }
}

SaveSpools() {
    global g_Spools, SPOOLS_FILE
    try {
        if FileExist(SPOOLS_FILE)
            FileDelete(SPOOLS_FILE)
        for name, spool in g_Spools {
            IniWrite(spool["enabled"], SPOOLS_FILE, name, "Enabled")
            IniWrite(spool["region"], SPOOLS_FILE, name, "Region")
            IniWrite(spool["regionCoords"], SPOOLS_FILE, name, "RegionCoords")
            IniWrite(spool["detectType"], SPOOLS_FILE, name, "DetectType")
            IniWrite(spool["target"], SPOOLS_FILE, name, "Target")
            IniWrite(spool["interval"], SPOOLS_FILE, name, "Interval")
            IniWrite(spool["condition"], SPOOLS_FILE, name, "Condition")
            IniWrite(spool["action"], SPOOLS_FILE, name, "Action")
            IniWrite(spool["actionTarget"], SPOOLS_FILE, name, "ActionTarget")
            IniWrite(spool["extractOCR"], SPOOLS_FILE, name, "ExtractOCR")
            IniWrite(spool["ocrVar"], SPOOLS_FILE, name, "OCRVar")
            IniWrite(spool["autoComplete"], SPOOLS_FILE, name, "AutoComplete")
            IniWrite(spool["completion"], SPOOLS_FILE, name, "Completion")
            IniWrite(spool["completionTarget"], SPOOLS_FILE, name, "CompletionTarget")
            IniWrite(spool["timeout"], SPOOLS_FILE, name, "Timeout")
            IniWrite(spool.Has("mode") ? spool["mode"] : "Continuous", SPOOLS_FILE, name, "Mode")
            IniWrite(spool.Has("cooldown") ? spool["cooldown"] : 5, SPOOLS_FILE, name, "Cooldown")
            IniWrite(spool.Has("notifTime") ? spool["notifTime"] : 5, SPOOLS_FILE, name, "NotifTime")
        }
    }
}

LoadSpools() {
    global g_Spools, SPOOLS_FILE
    if !FileExist(SPOOLS_FILE)
        return
    g_Spools := Map()
    sections := IniRead(SPOOLS_FILE)
    for section in StrSplit(sections, "`n") {
        if section = ""
            continue
        g_Spools[section] := Map(
            "enabled", Integer(IniRead(SPOOLS_FILE, section, "Enabled", 1)),
            "region", IniRead(SPOOLS_FILE, section, "Region", "Full Screen"),
            "regionCoords", IniRead(SPOOLS_FILE, section, "RegionCoords", ""),
            "detectType", IniRead(SPOOLS_FILE, section, "DetectType", "Pattern Match"),
            "target", IniRead(SPOOLS_FILE, section, "Target", ""),
            "interval", Integer(IniRead(SPOOLS_FILE, section, "Interval", 500)),
            "condition", IniRead(SPOOLS_FILE, section, "Condition", "Found"),
            "action", IniRead(SPOOLS_FILE, section, "Action", "Show Notification"),
            "actionTarget", IniRead(SPOOLS_FILE, section, "ActionTarget", ""),
            "extractOCR", Integer(IniRead(SPOOLS_FILE, section, "ExtractOCR", 0)),
            "ocrVar", IniRead(SPOOLS_FILE, section, "OCRVar", ""),
            "autoComplete", Integer(IniRead(SPOOLS_FILE, section, "AutoComplete", 0)),
            "completion", IniRead(SPOOLS_FILE, section, "Completion", "Pattern Found"),
            "completionTarget", IniRead(SPOOLS_FILE, section, "CompletionTarget", ""),
            "timeout", Integer(IniRead(SPOOLS_FILE, section, "Timeout", 0)),
            "mode", IniRead(SPOOLS_FILE, section, "Mode", "Continuous"),
            "cooldown", Integer(IniRead(SPOOLS_FILE, section, "Cooldown", 5)),
            "notifTime", Integer(IniRead(SPOOLS_FILE, section, "NotifTime", 5))
        )
    }
}

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
    if g_ActiveSpools.Has(name) {
        SetTimer(g_ActiveSpools[name], 0)
    }
    timerFunc := SpoolTimerFactory(name)
    g_ActiveSpools[name] := timerFunc
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
SpoolTimerFactory(spoolName) {
    return (*) => ExecuteSpoolCheck(spoolName)
}
ExecuteSpoolCheck(name, forceTest := false) {
    global g_Spools, g_SpoolVariables, g_Settings, g_SpoolScreenCache, g_SpoolCooldown, g_ActiveSpools
    static screenCache := Map()    
    if !g_Spools.Has(name)
        return

    spool := g_Spools[name]
    if !forceTest && IsSpoolInCooldown(name) {
        return  ; Skip this check, in cooldown
    }
    region := GetSpoolRegion(spool)
    detected := false
    detectedValue := ""

    switch spool["detectType"] {
        case "Pattern Match":
            detected := SpoolDetectPattern(spool["target"], region, spool["condition"])

        case "Pattern Sequence":
            detected := SpoolDetectPatternSequence(spool["target"], region)
            if spool["condition"] = "Not Found"
                detected := !detected

        case "OCR Contains":
            result := SpoolDetectOCRWindows(region, spool["target"], false)
            if result["text"] != "" {
                detectedValue := result["text"]
                detected := result["found"]
                if spool["condition"] = "Not Found"
                    detected := !detected
            }

        case "OCR Regex":
            result := SpoolDetectOCRWindows(region, spool["target"], true)
            if result["text"] != "" {
                detectedValue := result["text"]
                detected := result["found"]
                if spool["condition"] = "Not Found"
                    detected := !detected
            }

        case "Pixel Change", "Screen Changed":
            detected := SpoolDetectScreenChange(name, region)

        case "Window Title":
            activeTitle := ""
            try activeTitle := WinGetTitle("A")
            detected := InStr(activeTitle, spool["target"])
            if spool["condition"] = "Not Found"
                detected := !detected
    }
    if detected {
        SpoolLogAdd("TRIGGERED: " . name)
        if spool["extractOCR"] && spool["ocrVar"] != "" && detectedValue != "" {
            g_SpoolVariables[spool["ocrVar"]] := detectedValue
            RefreshOCRVarsLV()
        }
        ExecuteSpoolAction(spool, name)
        mode := spool.Has("mode") ? spool["mode"] : "Continuous"
        cooldown := spool.Has("cooldown") ? spool["cooldown"] : 5

        switch mode {
            case "One-Shot":
                SpoolLogAdd("One-Shot complete, stopping: " . name)
                StopSpool(name)

            case "Cooldown":
                g_SpoolCooldown[name] := A_TickCount + (cooldown * 1000)
                SpoolLogAdd("Cooldown " . cooldown . "s: " . name)

            case "Continuous":
        }
        if spool["autoComplete"] {
            timeout := spool.Has("timeout") ? spool["timeout"] : 0
            if timeout > 0 {
                stopFunc := (*) => StopSpool(name)
                SetTimer(stopFunc, -timeout * 1000)
                SpoolLogAdd("Auto-stop in " . timeout . "s: " . name)
            }
        }
    }
}
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
SpoolDetectOCR(region) {
    result := Map("success", false, "text", "")

    try {
        text := FindText().OCR(region["x1"], region["y1"], region["x2"], region["y2"])
        if text != "" {
            result["success"] := true
            result["text"] := text
        }
    }

    return result
}
SpoolDetectPatternSequence(targetPatterns, region) {
    global g_Patterns, g_Settings
    patternList := StrSplit(targetPatterns, ",")
    for patternName in patternList {
        patternName := Trim(patternName)
        if patternName = "" || patternName = "(Enter comma-separated patterns)"
            continue

        if !g_Patterns.Has(patternName)
            return false        code := g_Patterns[patternName]["text"]
        tolerance := g_Settings["FindTextTolerance"]

        ok := FindText(&outX, &outY, region["x1"], region["y1"], region["x2"], region["y2"],
                       tolerance, tolerance, code)

        if !ok || ok.Length = 0
            return false  ; Pattern not found, sequence fails
    }

    return true  ; All patterns found
}
SpoolDetectScreenChange(spoolName, region) {
    static screenCache := Map()
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
    if screenCache.Has(spoolName) {
        previousHash := screenCache[spoolName]
        screenCache[spoolName] := currentHash        
        if previousHash != currentHash
            return true
    } else {
        screenCache[spoolName] := currentHash
    }

    return false
}
ExecuteSpoolAction(spool, spoolName := "") {
    global g_Sequences, g_SpoolVariables

    switch spool["action"] {
        case "Run Workflow":
            if g_Sequences.Has(spool["actionTarget"]) {
                speed := g_Sequences[spool["actionTarget"]].Has("speed") ? g_Sequences[spool["actionTarget"]]["speed"] : 1.0
                ExecuteSequenceVerified(g_Sequences[spool["actionTarget"]]["steps"], speed)
            }

        case "Show Notification":
            ShowSpoolNotification(spool["actionTarget"], spool, spoolName)

        case "Start Spool":
            StartSpool(spool["actionTarget"])

        case "Stop Spool":
            StopSpool(spool["actionTarget"])

        case "Extract OCR":

        case "Set Variable":
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
ShowSpoolNotification(title, spool := "", spoolName := "") {
    global g_SpoolNotifications, g_NotificationCounter, g_NotificationDefaults, g_SpoolCooldown

    g_NotificationCounter++
    id := g_NotificationCounter
    timeout := g_NotificationDefaults["timeout"]  ; Default 5 seconds
    if IsObject(spool) {
        if spool.Has("notifTime") && spool["notifTime"] > 0
            timeout := spool["notifTime"]
        else if spool.Has("timeout") && spool["timeout"] > 0
            timeout := spool["timeout"]
    }
    notifGui := Gui("+AlwaysOnTop +ToolWindow -Caption", "SpoolNotif" . id)
    notifGui.BackColor := "1a1a2e"
    notifGui.SetFont("s10 cWhite", "Segoe UI")
    x := A_ScreenWidth - 320
    y := A_ScreenHeight - 120 - (g_SpoolNotifications.Length * 95)

    notifGui.Add("Text", "x10 y10 w250 cYellow", "🔔 " . title)
    sourceText := spoolName != "" ? "From: " . spoolName : "Triggered by spool detection"
    notifGui.Add("Text", "x10 y32 w250 c16c79a", sourceText)
    timeText := notifGui.Add("Text", "x10 y52 w100 cGray", FormatTime(, "HH:mm:ss"))
    countdownText := notifGui.Add("Text", "x200 y52 w60 cFF8800 Right", timeout . "s")

    closeBtn := notifGui.Add("Button", "x265 y5 w25 h20", "X")
    closeBtn.OnEvent("Click", (*) => DismissNotification(id, notifGui))

    notifGui.Show("x" . x . " y" . y . " w300 h75 NoActivate")
    WinSetTransparent(230, notifGui)
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
    if spoolName != "" && g_NotificationDefaults["pauseSpools"] {
        if IsObject(spool) && (!spool.Has("mode") || spool["mode"] = "Continuous") {
            g_SpoolCooldown[spoolName] := A_TickCount + (timeout * 1000)
        }
    }

    RefreshNotificationLV()
    countdownFunc := NotificationCountdownFactory(id)
    SetTimer(countdownFunc, 1000)
    dismissFunc := (*) => DismissNotification(id, notifGui)
    SetTimer(dismissFunc, -timeout * 1000)

    SpoolLogAdd("Notification: " . title . " (" . timeout . "s)")

    return id
}
NotificationCountdownFactory(notifId) {
    return (*) => UpdateNotificationCountdown(notifId)
}
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
        SetTimer(NotificationCountdownFactory(id), 0)
        return
    }

    foundNotif["remaining"]--

    if foundNotif["remaining"] >= 0 {
        try foundNotif["countdownCtrl"].Value := foundNotif["remaining"] . "s"
    }

    if foundNotif["remaining"] <= 0 {
        SetTimer(NotificationCountdownFactory(id), 0)
    }
}


DismissAllNotifications(*) {
    global g_SpoolNotifications, g_SpoolCooldown

    for notif in g_SpoolNotifications {
        try notif["gui"].Destroy()
    }
    g_SpoolNotifications := []
    g_SpoolCooldown := Map()    RefreshNotificationLV()
    SpoolLogAdd("All notifications dismissed")
}
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
SpoolLogAdd(message) {
    global g_SpoolLog, SpoolLogEdit

    timestamp := FormatTime(, "HH:mm:ss")
    entry := "[" . timestamp . "] " . message
    g_SpoolLog.Push(entry)
    while g_SpoolLog.Length > 100
        g_SpoolLog.RemoveAt(1)
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
LiveOCRCapture() {
    global g_OCRRegion, g_OCRLog, g_LastOCRResult, OCR_LOG_FILE

    try {
        startTime := A_TickCount
        scale := 1.0
        try scale := Float(MainGui["OCRScale"].Value)
        grayscale := MainGui["OCRGrayscale"].Value
        lang := MainGui["OCRLang"].Text

        opts := {lang: lang, scale: scale, grayscale: grayscale}
        if g_OCRRegion["x2"] > 0 && g_OCRRegion["y2"] > 0 {
            w := g_OCRRegion["x2"] - g_OCRRegion["x1"]
            h := g_OCRRegion["y2"] - g_OCRRegion["y1"]
            result := OCR.FromRect(g_OCRRegion["x1"], g_OCRRegion["y1"], w, h, opts)
        } else {
            result := OCR.FromDesktop(opts)
        }

        g_LastOCRResult := result

        captureTime := A_TickCount - startTime
        MainGui["OCROutput"].Value := result.Text
        MainGui["OCRWordCount"].Value := result.Words.Length
        MainGui["OCRLineCount"].Value := result.Lines.Length
        MainGui["OCRTextAngle"].Value := Round(result.TextAngle, 1) . "°"
        MainGui["OCRCaptureTime"].Value := captureTime . " ms"
        RefreshOCRWordLV(result)
        if g_OCRRecording && result.Text != "" {
            timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
            logEntry := timestamp . "|" . StrReplace(result.Text, "`n", " ") . "|" . result.Words.Length
            g_OCRLog.Push(logEntry)
            while g_OCRLog.Length > 1000
                g_OCRLog.RemoveAt(1)

            MainGui["OCRLogCount"].Value := g_OCRLog.Length
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
    overlayGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "OCRRegionOverlay")
    overlayGui.BackColor := "000000"
    overlayGui.Show("x0 y0 w" . A_ScreenWidth . " h" . A_ScreenHeight . " NoActivate")
    WinSetTransparent(1, overlayGui)

    ToolTip("🎯 Drag to select OCR region`nESC to cancel`nRight-click for Full Screen", A_ScreenWidth//2 - 150, 50)

    x1 := 0, y1 := 0, x2 := 0, y2 := 0
    cancelled := false
    fullScreen := false

    selBox := ""
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
    for word in result.Words {
        OCRLV.Add("", word.Text, word.x, word.y)
    }
}

OnOCRWordSelect(LV, RowNumber, *) {
    global g_LastOCRResult

    if RowNumber = 0 || !IsObject(g_LastOCRResult)
        return
    if RowNumber <= g_LastOCRResult.Words.Length {
        word := g_LastOCRResult.Words[RowNumber]
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
        w := foundWords[1]
        HighlightRegion(w.x, w.y, w.w, w.h, 3000, "match", needle)
        ShowStatus("Found: '" . needle . "' at " . w.x . "," . w.y . " (" . foundWords.Length . " total)", "ok")
    } else {
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
    ClearAllOverlays()
    ShowStatus("Highlights cleared", "ok")
}
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
AddSelectedWordAsWatch(*) {
    global g_LastOCRResult, OCRLV, g_OCRRegion

    row := OCRLV.GetNext(0, "Focused")
    if row = 0 || !IsObject(g_LastOCRResult) {
        ShowStatus("Select a word first", "fail")
        return
    }
    name := MainGui["WatchWordName"].Value
    if name = "" {
        ShowStatus("Enter a name for the watch word", "fail")
        return
    }
    word := g_LastOCRResult.Words[row]
    padding := 5
    region := Map(
        "x1", word.x - padding,
        "y1", word.y - padding,
        "x2", word.x + word.w + padding,
        "y2", word.y + word.h + padding
    )
    DefineWatchWord(name, region, "", 1)    UpdateWatchWord(name)
    RefreshWatchWordLV()

    ShowStatus("Watch word '" . name . "' created: " . word.Text, "ok")
    HighlightRegion(region["x1"], region["y1"], region["x2"] - region["x1"], region["y2"] - region["y1"], 2000, "selection", name)
}
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
    HighlightRegion(word.x, word.y, word.w, word.h, 500, "highlight", "")
    Sleep(200)
    Click(x, y)
    ShowStatus("Clicked: " . word.Text, "ok")
}
DefineWatchWordFromOCR(*) {
    global g_OCRRegion

    name := MainGui["WatchWordName"].Value
    if name = "" {
        ShowStatus("Enter a name for the watch word", "fail")
        return
    }
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
ShowWatchWordValues(*) {
    global g_WatchWords, g_WordVariables
    UpdateAllWatchWords()
    RefreshWatchWordLV()
    summary := "Watch Word Values:`n`n"
    for name, watch in g_WatchWords {
        summary .= "$word." . name . " = " . watch["lastValue"] . "`n"
        summary .= "  Coords: " . watch["lastCoords"]["x"] . "," . watch["lastCoords"]["y"] . "`n"
    }

    if g_WatchWords.Count = 0
        summary := "No watch words defined.`n`nDefine watch words to capture dynamic text like patient names, dates, IDs, etc."

    MsgBoxTop(summary, "Watch Word Values")
}
ManageWatchWords(*) {
    global g_WatchWords

    manageGui := Gui("+AlwaysOnTop", "Manage Watch Words")
    manageGui.SetFont("s9", "Consolas")

    manageGui.Add("Text", "w400", "Watch words capture dynamic text from specific screen regions.")
    manageGui.Add("Text", "w400 cGray", "Use $word.Name in workflows to reference captured values.")
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
RefreshWatchWordLV() {
    global g_WatchWords, WatchWordLV

    try {
        WatchWordLV.Delete()
        for name, watch in g_WatchWords {
            WatchWordLV.Add("", name, watch["lastValue"])
        }
    }
}
OnWatchWordSelect(LV, RowNumber, *) {
}
OnWatchWordDblClick(LV, RowNumber, *) {
    global g_WatchWords

    if RowNumber = 0
        return

    name := LV.GetText(RowNumber, 1)
    if g_WatchWords.Has(name) {
        HighlightWatchWord(name, 3000)
    }
}
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
UseSelectedWatchWord(*) {
    global g_WatchWords, WatchWordLV

    row := WatchWordLV.GetNext(0, "Focused")
    if row = 0
        return

    name := WatchWordLV.GetText(row, 1)
    if g_WatchWords.Has(name) {
        UpdateWatchWord(name)
        value := g_WatchWords[name]["lastValue"]
        A_Clipboard := value
        ShowStatus("Copied to clipboard: " . value, "ok")
    }
}
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
TestAllOverlays(*) {
    global g_Patterns, g_WatchWords
    ClearAllOverlays()
    patternCount := TestAllPatternsHighlight(3000)
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
    global g_OCRLog

    logText := ""
    for entry in g_OCRLog
        logText .= entry . "`n"
    logGui := Gui("+AlwaysOnTop", "OCR Log")
    logGui.Add("Edit", "w600 h400 ReadOnly Multi VScroll", logText)
    logGui.Add("Button", "w100", "Close").OnEvent("Click", (*) => logGui.Destroy())
    logGui.Show()
}

ClearOCRLog(*) {
    global g_OCRLog, OCR_LOG_FILE
    g_OCRLog := []
    MainGui["OCRLogCount"].Value := "0"
    try FileDelete(OCR_LOG_FILE)
    ShowStatus("OCR log cleared", "ok")
}

ExportOCRLog(*) {
    global g_OCRLog, DATA_DIR

    exportFile := DATA_DIR . "\ocr_export_" . FormatTime(, "yyyyMMdd_HHmmss") . ".csv"

    content := "Timestamp,Text,WordCount`n"
    for entry in g_OCRLog
        content .= entry . "`n"

    try {
        FileAppend(content, exportFile)
        ShowStatus("Exported to: " . exportFile, "ok")
        Run("explorer.exe /select," . exportFile)
    } catch as err {
        ShowStatus("Export error: " . err.Message, "fail")
    }
}
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
LoadOCRToRevolverDD(*) {
    global OCROutputEdit, OCRSplitDD, g_LastOCRText

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to load", "fail")
        return
    }

    g_LastOCRText := text
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
LoadOCRToRevolver(*) {
    global OCROutputEdit, g_LastOCRText

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to load", "fail")
        return
    }

    g_LastOCRText := text
    LoadOCRRevolver("4")
    UpdateOCRRevolverStatus()
}
FireOCRRevolverUI(*) {
    FireOCRRevolver()
    UpdateOCRRevolverStatus()
}
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
SaveOCRToVariable(*) {
    global OCROutputEdit, g_SpoolVariables, g_WordVariables

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to save", "fail")
        return
    }
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
ClickTextInOCR(*) {
    global OCROutputEdit, OCRSearchEdit, g_OCRSettings, g_LastOCRRegion

    searchText := OCRSearchEdit.Value
    if searchText = "" {
        ShowStatus("Enter text to find and click", "fail")
        return
    }
    region := g_LastOCRRegion.Count > 0 ? g_LastOCRRegion : Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)

    ExecuteOCRClick(region["x1"] . "," . region["y1"] . "," . region["x2"] . "," . region["y2"], searchText)
}
ExtractOCRRegex(*) {
    global OCROutputEdit, g_LastOCRText

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to extract from", "fail")
        return
    }
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
    result := ""
    for m in matches
        result .= m . "`n"
    result := RTrim(result, "`n")

    A_Clipboard := result
    g_LastOCRText := result

    parentGui.Destroy()
    ShowStatus("Extracted " . matches.Length . " matches to clipboard", "ok")
}
SplitOCRText(*) {
    global OCROutputEdit, g_LastOCRText

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to split", "fail")
        return
    }

    g_LastOCRText := text
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
SpoolDetectOCRWindows(region, searchText, useRegex := false) {
    try {
        w := region["x2"] - region["x1"]
        h := region["y2"] - region["y1"]

        if w < 40 || h < 40 {
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
    SpoolModeDD.Choose(1)  ; Continuous
    SpoolCooldownEdit.Value := "5"
    SpoolNotifTimeEdit.Value := "5"
    try SpoolSeqHelp.Value := ""
}

TestSpoolOnce(*) {
    global g_Spools, SpoolNameEdit, SpoolDetectDD, SpoolTargetCombo, SpoolRegionDD, SpoolRegionText

    name := SpoolNameEdit.Value
    if name = "" || !g_Spools.Has(name) {
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
TestSpoolPattern(*) {
    global SpoolDetectDD, SpoolTargetCombo, g_Patterns

    detectType := SpoolDetectDD.Text
    target := SpoolTargetCombo.Text

    if target = "" {
        ShowStatus("Enter a target pattern", "fail")
        return
    }

    if detectType = "Pattern Match" {
        TestPatternHighlight(target, 3000)

    } else if detectType = "Pattern Sequence" {
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
OnSpoolModeChange(*) {
    global SpoolModeDD, SpoolCooldownEdit

    mode := SpoolModeDD.Text
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
    overlayGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "RegionOverlay")
    overlayGui.BackColor := "000000"
    overlayGui.Show("x0 y0 w" . A_ScreenWidth . " h" . A_ScreenHeight . " NoActivate")
    WinSetTransparent(1, overlayGui)    ToolTip("🎯 Drag to select monitor region`nESC to cancel", A_ScreenWidth//2 - 150, 50)
    x1 := 0, y1 := 0, x2 := 0, y2 := 0
    selecting := false
    cancelled := false
    selBox := ""
    escHotkey := Hotkey("Escape", (*) => (cancelled := true), "On")
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
    selBox := Gui("+AlwaysOnTop -Caption +ToolWindow", "SelectBox")
    selBox.BackColor := "FF0000"
    while GetKeyState("LButton", "P") && !cancelled {
        MouseGetPos(&x2, &y2)
        left := Min(x1, x2)
        top := Min(y1, y2)
        w := Abs(x2 - x1)
        h := Abs(y2 - y1)

        if w > 5 && h > 5 {
            selBox.Show("x" . left . " y" . top . " w" . w . " h" . h . " NoActivate")
            WinSetTransparent(100, selBox)
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
    left := Min(x1, x2)
    top := Min(y1, y2)
    right := Max(x1, x2)
    bottom := Max(y1, y2)
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
    try SpoolSeqHelp.Value := ""

    switch SpoolDetectDD.Text {
        case "Pattern Match":
            items := []
            for name, _ in g_Patterns
                items.Push(name)
            if items.Length > 0
                SpoolTargetCombo.Add(items)

        case "Pattern Sequence":
            items := []
            for name, _ in g_Patterns
                items.Push(name)
            if items.Length > 0
                SpoolTargetCombo.Add(items)
            try SpoolSeqHelp.Value := "Format: Pattern1,Pattern2,Pattern3 (ALL must match to trigger)"

        case "Window Title":
            items := GetWindowList()
            if items.Length > 0
                SpoolTargetCombo.Add(items)

        case "Screen Changed", "Pixel Change":
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
            SpoolActionTargetCombo.Add(["Pattern detected!", "Action required", "Check this now"])
    }
}

OnSpoolSelect(LV, RowNumber, *) {
    if RowNumber = 0
        return
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
    if Checked && g_SpoolMasterEnabled
        StartSpool(name)
    else
        StopSpool(name)
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
    regions := ["Full Screen", "Custom Region", "Active Window"]
    for i, r in regions {
        if r = spool["region"] {
            SpoolRegionDD.Choose(i)
            break
        }
    }
    SpoolRegionText.Value := spool["regionCoords"]
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
    conditions := ["Found", "Not Found", "Changed"]
    for i, c in conditions {
        if c = spool["condition"] {
            SpoolConditionDD.Choose(i)
            break
        }
    }
    modes := ["Continuous", "One-Shot", "Cooldown"]
    modeVal := spool.Has("mode") ? spool["mode"] : "Continuous"
    for i, m in modes {
        if m = modeVal {
            SpoolModeDD.Choose(i)
            break
        }
    }
    SpoolCooldownEdit.Value := spool.Has("cooldown") ? spool["cooldown"] : 5
    OnSpoolModeChange()    actions := ["Show Notification", "Run Workflow", "Start Spool", "Stop Spool", "Extract OCR", "Set Variable", "Key Chord", "Run Program"]
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
        if mode = "Continuous"
            mode := "Cont."
        else if mode = "One-Shot"
            mode := "1-Shot"
        else if mode = "Cooldown"
            mode := "Cool."
        SpoolLV.Add(spool["enabled"] ? "Check" : "", name, spool["detectType"], spool["action"], mode, status)
    }
}

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
    SaveHotkeys()
    SaveSettings()
    SaveExtractionRules()
    SaveAppointments()
    SavePatients()
}

TestOCRAvailability() {
    global g_OCRAvailable
    try {
        if !IsSet(OCR) {
            g_OCRAvailable := false
            return false
        }
        testResult := OCR.FromRect(0, 0, 100, 100, "en-US")
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
    InitializeAppointmentScheduler()
    RefreshCalendarDisplay()
    global g_DebugMode, g_NotificationDismissible, g_NotificationTimeout
    if g_Settings.Has("DebugMode")
        g_DebugMode := g_Settings["DebugMode"]
    if g_Settings.Has("NotificationDismissible")
        g_NotificationDismissible := g_Settings["NotificationDismissible"]
    if g_Settings.Has("NotificationTimeout")
        g_NotificationTimeout := Integer(g_Settings["NotificationTimeout"]) * 1000
    RegisterAllSequenceTriggers()
}
FormatTimeSlot(time24) {
    parts := StrSplit(time24, ":")
    hour := Integer(parts[1])
    minute := parts[2]
    
    ampm := (hour >= 12) ? "PM" : "AM"
    displayHour := (hour > 12) ? hour - 12 : (hour = 0 ? 12 : hour)
    
    return displayHour . ":" . minute . " " . ampm
}
GetAppointmentKey(date, time) {
    timeClean := StrReplace(time, ":", "")
    return date . "_" . timeClean
}
CalculateNotificationTime(appointmentDateTime, minutesBefore) {
    parts := StrSplit(appointmentDateTime, " ")
    dateStr := parts[1]
    timeStr := parts[2]
    timestamp := dateStr . " " . timeStr
    timestamp := StrReplace(timestamp, "-", "")
    timestamp := StrReplace(timestamp, ":", "")
    timestamp := StrReplace(timestamp, " ", "")
    resultTime := DateAdd(FormatTime(timestamp, "yyyyMMddHHmmss"), -minutesBefore, "Minutes")
    return FormatTime(resultTime, "yyyy-MM-dd HH:mm")
}
CreatePatient(name, phone := "", email := "", notes := "") {
    global g_Patients, g_NextPatientID
    
    patientID := g_NextPatientID
    g_NextPatientID++
    
    g_Patients[patientID] := Map(
        "id", patientID,
        "name", name,
        "phone", phone,
        "email", email,
        "notes", notes,
        "visitHistory", []
    )
    
    SavePatients()
    return patientID
}
GetPatient(patientID) {
    global g_Patients
    
    if g_Patients.Has(patientID) {
        return g_Patients[patientID]
    }
    return Map()
}
GetPatientNamesList() {
    global g_Patients
    
    names := []
    for id, patient in g_Patients {
        names.Push(patient["name"])
    }
    return names
}
GetPatientIDByName(name) {
    global g_Patients
    
    for id, patient in g_Patients {
        if (patient["name"] = name) {
            return id
        }
    }
    return 0
}
BookAppointment(date, time, patientID, appointmentType) {
    global g_Appointments, g_Patients, g_AppointmentTypes
    patient := GetPatient(patientID)
    if (patient.Count = 0) {
        MsgBox("Patient not found!")
        return false
    }
    
    patientName := patient["name"]
    if !g_AppointmentTypes.Has(appointmentType) {
        MsgBox("Invalid appointment type!")
        return false
    }
    
    typeInfo := g_AppointmentTypes[appointmentType]
    key := GetAppointmentKey(date, time)
    g_Appointments[key] := Map(
        "date", date,
        "time", time,
        "patientID", patientID,
        "patientName", patientName,
        "appointmentType", appointmentType,
        "typeName", typeInfo["name"],
        "duration", typeInfo["duration"],
        "tasks", typeInfo["tasks"],
        "status", "Scheduled"
    )
    appointmentDateTime := date . " " . time
    
    for task in typeInfo["tasks"] {
        notifyMinutes := task["notifyBefore"]
        
        if (notifyMinutes > 0) {
            triggerTime := CalculateNotificationTime(appointmentDateTime, notifyMinutes)
            message := patientName . " - " . task["task"] . "`n" . notifyMinutes . " minutes before appointment"
        } else {
            triggerTime := appointmentDateTime
            message := patientName . " - " . task["task"] . "`nAt appointment time"
        }
        ShowEnhancedNotification("Appointment Task", message, 0)
    }
    patient["visitHistory"].Push(date)
    SaveAppointments()
    SavePatients()
    RefreshCalendarDisplay()
    
    return true
}
GetAppointment(date, time) {
    global g_Appointments
    
    key := GetAppointmentKey(date, time)
    if g_Appointments.Has(key) {
        return g_Appointments[key]
    }
    return Map()
}
CancelAppointment(date, time) {
    global g_Appointments
    
    key := GetAppointmentKey(date, time)
    if g_Appointments.Has(key) {
        g_Appointments.Delete(key)
        SaveAppointments()
        RefreshCalendarDisplay()
        return true
    }
    return false
}

SaveAppointments() {
    global g_Appointments
    
    iniFile := A_ScriptDir . "\Data\appointments.ini"
    if !DirExist(A_ScriptDir . "\Data") {
        DirCreate(A_ScriptDir . "\Data")
    }
    if FileExist(iniFile) {
        FileDelete(iniFile)
    }
    for key, appt in g_Appointments {
        section := "Appt_" . key
        
        IniWrite(appt["date"], iniFile, section, "Date")
        IniWrite(appt["time"], iniFile, section, "Time")
        IniWrite(appt["patientID"], iniFile, section, "PatientID")
        IniWrite(appt["patientName"], iniFile, section, "PatientName")
        IniWrite(appt["appointmentType"], iniFile, section, "AppointmentType")
        IniWrite(appt["typeName"], iniFile, section, "TypeName")
        IniWrite(appt["status"], iniFile, section, "Status")
    }
}

LoadAppointments() {
    global g_Appointments, g_AppointmentTypes
    
    iniFile := A_ScriptDir . "\Data\appointments.ini"
    
    if !FileExist(iniFile) {
        return
    }
    sections := IniRead(iniFile)
    
    Loop Parse, sections, "`n" {
        section := Trim(A_LoopField)
        
        if (section = "") {
            continue
        }
        date := IniRead(iniFile, section, "Date", "")
        time := IniRead(iniFile, section, "Time", "")
        patientID := IniRead(iniFile, section, "PatientID", 0)
        patientName := IniRead(iniFile, section, "PatientName", "")
        appointmentType := IniRead(iniFile, section, "AppointmentType", "")
        typeName := IniRead(iniFile, section, "TypeName", "")
        status := IniRead(iniFile, section, "Status", "Scheduled")
        tasks := []
        duration := 30
        if g_AppointmentTypes.Has(appointmentType) {
            typeInfo := g_AppointmentTypes[appointmentType]
            tasks := typeInfo["tasks"]
            duration := typeInfo["duration"]
        }
        key := GetAppointmentKey(date, time)
        g_Appointments[key] := Map(
            "date", date,
            "time", time,
            "patientID", Integer(patientID),
            "patientName", patientName,
            "appointmentType", appointmentType,
            "typeName", typeName,
            "duration", duration,
            "tasks", tasks,
            "status", status
        )
    }
}

SavePatients() {
    global g_Patients, g_NextPatientID
    
    iniFile := A_ScriptDir . "\Data\patients.ini"
    
    if !DirExist(A_ScriptDir . "\Data") {
        DirCreate(A_ScriptDir . "\Data")
    }
    
    if FileExist(iniFile) {
        FileDelete(iniFile)
    }
    
    for id, patient in g_Patients {
        section := "Patient_" . id
        
        IniWrite(patient["name"], iniFile, section, "Name")
        IniWrite(patient["phone"], iniFile, section, "Phone")
        IniWrite(patient["email"], iniFile, section, "Email")
        IniWrite(patient["notes"], iniFile, section, "Notes")
    }
    
    IniWrite(g_NextPatientID, iniFile, "Settings", "NextID")
}

LoadPatients() {
    global g_Patients, g_NextPatientID
    
    iniFile := A_ScriptDir . "\Data\patients.ini"
    
    if !FileExist(iniFile) {
        return
    }
    
    sections := IniRead(iniFile)
    
    Loop Parse, sections, "`n" {
        section := Trim(A_LoopField)
        
        if (section = "" || section = "Settings") {
            continue
        }
        idStr := StrReplace(section, "Patient_", "")
        id := Integer(idStr)
        name := IniRead(iniFile, section, "Name", "")
        phone := IniRead(iniFile, section, "Phone", "")
        email := IniRead(iniFile, section, "Email", "")
        notes := IniRead(iniFile, section, "Notes", "")
        
        g_Patients[id] := Map(
            "id", id,
            "name", name,
            "phone", phone,
            "email", email,
            "notes", notes,
            "visitHistory", []
        )
    }
    g_NextPatientID := IniRead(iniFile, "Settings", "NextID", 1)
}
RefreshCalendarDisplay() {
    global g_CalendarDate, g_DateDisplayText, g_TimeSlotButtons, g_Appointments, g_AppointmentTypes
    g_DateDisplayText.Value := FormatTime(g_CalendarDate, "dddd, MMMM dd, yyyy")
    for time, button in g_TimeSlotButtons {
        appt := GetAppointment(g_CalendarDate, time)
        
        if (appt.Count > 0) {
            displayText := appt["patientName"] . " - " . appt["typeName"]
            button.Text := displayText
            if g_AppointmentTypes.Has(appt["appointmentType"]) {
                typeInfo := g_AppointmentTypes[appt["appointmentType"]]
                if typeInfo.Has("color") {
                    button.Opt(typeInfo["color"])
                }
            }
        } else {
            button.Text := "[Empty]"
            button.Opt("cDefault")
        }
    }
}
PrevDay(*) {
    global g_CalendarDate
    
    g_CalendarDate := FormatTime(DateAdd(g_CalendarDate, -1, "Days"), "yyyy-MM-dd")
    RefreshCalendarDisplay()
}
NextDay(*) {
    global g_CalendarDate
    
    g_CalendarDate := FormatTime(DateAdd(g_CalendarDate, 1, "Days"), "yyyy-MM-dd")
    RefreshCalendarDisplay()
}
GoToToday(*) {
    global g_CalendarDate
    
    g_CalendarDate := FormatTime(, "yyyy-MM-dd")
    RefreshCalendarDisplay()
}
ClickTimeSlot(time) {
    global g_CalendarDate
    appt := GetAppointment(g_CalendarDate, time)
    
    if (appt.Count > 0) {
        result := MsgBox("Slot already booked for " . appt["patientName"] . "`n`nCancel this appointment?", "Appointment Exists", "YesNo")
        if (result = "Yes") {
            CancelAppointment(g_CalendarDate, time)
        }
        return
    }
    OpenBookingDialog(time)
}
OpenBookingDialog(time) {
    global g_CalendarDate, g_Patients, g_AppointmentTypes, MainGui
    BookGui := Gui("+Owner" . MainGui.Hwnd, "Book Appointment")
    BookGui.SetFont("s9", "Segoe UI")
    dateDisplay := FormatTime(g_CalendarDate, "MM/dd/yyyy")
    timeDisplay := FormatTimeSlot(time)
    
    BookGui.Add("Text", "x10 y10", "Date:")
    BookGui.Add("Text", "x100 y10 w150", dateDisplay)
    
    BookGui.Add("Text", "x10 y35", "Time:")
    BookGui.Add("Text", "x100 y35 w150", timeDisplay)
    BookGui.Add("Text", "x10 y65", "Patient:")
    patientNames := GetPatientNamesList()
    
    if (patientNames.Length = 0) {
        patientNames := ["(No patients - create one first)"]
    }
    
    patientDD := BookGui.Add("DropDownList", "x100 y65 w200", patientNames)
    BookGui.Add("Button", "x305 y65 w80 h25", "New").OnEvent("Click", (*) => OpenNewPatientDialog(BookGui, patientDD))
    BookGui.Add("Text", "x10 y100", "Type:")
    
    typeNames := []
    for key, typeInfo in g_AppointmentTypes {
        typeNames.Push(typeInfo["name"])
    }
    
    if (typeNames.Length = 0) {
        typeNames := ["Contact Lens Exam"]
    }
    
    typeDD := BookGui.Add("DropDownList", "x100 y100 w285", typeNames)
    typeDD.OnEvent("Change", (*) => ShowTaskPreview(typeDD, taskPreview))
    BookGui.Add("Text", "x10 y135", "Tasks:")
    taskPreview := BookGui.Add("Edit", "x10 y155 w375 h150 ReadOnly Multi")
    BookGui.Add("Button", "x100 y320 w100 h30", "Book").OnEvent("Click", (*) => ConfirmBooking(time, patientDD, typeDD, BookGui))
    BookGui.Add("Button", "x210 y320 w100 h30", "Cancel").OnEvent("Click", (*) => BookGui.Destroy())
    
    BookGui.Show("w395 h365")
}
ShowTaskPreview(typeDD, taskPreview) {
    global g_AppointmentTypes
    
    selectedType := typeDD.Text
    for key, typeInfo in g_AppointmentTypes {
        if (typeInfo["name"] = selectedType) {
            preview := ""
            for task in typeInfo["tasks"] {
                minutes := task["notifyBefore"]
                if (minutes > 0) {
                    preview .= "⏰ " . minutes . " min before: " . task["task"] . "`n"
                } else {
                    preview .= "⏰ During visit: " . task["task"] . "`n"
                }
            }
            taskPreview.Value := preview
            break
        }
    }
}
ConfirmBooking(time, patientDD, typeDD, BookGui) {
    global g_CalendarDate, g_AppointmentTypes
    if (patientDD.Value = 0) {
        MsgBox("Please select a patient")
        return
    }
    
    if (typeDD.Value = 0) {
        MsgBox("Please select appointment type")
        return
    }
    patientName := patientDD.Text
    
    if (patientName = "(No patients - create one first)") {
        MsgBox("Please create a patient first")
        return
    }
    
    patientID := GetPatientIDByName(patientName)
    
    if (patientID = 0) {
        MsgBox("Patient not found!")
        return
    }
    selectedTypeName := typeDD.Text
    appointmentType := ""
    
    for key, typeInfo in g_AppointmentTypes {
        if (typeInfo["name"] = selectedTypeName) {
            appointmentType := key
            break
        }
    }
    
    if (appointmentType = "") {
        MsgBox("Invalid appointment type!")
        return
    }
    result := BookAppointment(g_CalendarDate, time, patientID, appointmentType)
    
    if (result) {
        MsgBox("Appointment booked successfully!`n`nNotifications will appear at scheduled times.")
        BookGui.Destroy()
    }
}
OpenNewPatientDialog(parentGui, patientDD) {
    PatientGui := Gui("+Owner" . parentGui.Hwnd, "New Patient")
    PatientGui.SetFont("s9", "Segoe UI")
    
    PatientGui.Add("Text", "x10 y10", "Name:")
    nameEdit := PatientGui.Add("Edit", "x70 y10 w250")
    
    PatientGui.Add("Text", "x10 y40", "Phone:")
    phoneEdit := PatientGui.Add("Edit", "x70 y40 w250")
    
    PatientGui.Add("Text", "x10 y70", "Email:")
    emailEdit := PatientGui.Add("Edit", "x70 y70 w250")
    
    PatientGui.Add("Text", "x10 y100", "Notes:")
    notesEdit := PatientGui.Add("Edit", "x70 y100 w250 h60 Multi")
    
    PatientGui.Add("Button", "x70 y175 w100 h30", "Create").OnEvent("Click", (*) => SaveNewPatient(nameEdit, phoneEdit, emailEdit, notesEdit, PatientGui, patientDD))
    PatientGui.Add("Button", "x180 y175 w100 h30", "Cancel").OnEvent("Click", (*) => PatientGui.Destroy())
    
    PatientGui.Show("w330 h220")
}
SaveNewPatient(nameEdit, phoneEdit, emailEdit, notesEdit, PatientGui, patientDD) {
    name := Trim(nameEdit.Value)
    
    if (name = "") {
        MsgBox("Name is required")
        return
    }
    
    phone := Trim(phoneEdit.Value)
    email := Trim(emailEdit.Value)
    notes := Trim(notesEdit.Value)
    patientID := CreatePatient(name, phone, email, notes)
    patientNames := GetPatientNamesList()
    patientDD.Delete()
    patientDD.Add(patientNames)
    patientDD.Choose(patientNames.Length)  ; Select newly added patient
    
    MsgBox("Patient created: " . name)
    PatientGui.Destroy()
}
OpenPatientList() {
    global g_Patients, MainGui
    
    ListGui := Gui("+Owner" . MainGui.Hwnd, "Patient List")
    ListGui.SetFont("s9", "Segoe UI")
    patientLV := ListGui.Add("ListView", "x10 y10 w400 h300", ["Name", "Phone", "Email"])
    patientLV.ModifyCol(1, 150)
    patientLV.ModifyCol(2, 120)
    patientLV.ModifyCol(3, 120)
    for id, patient in g_Patients {
        patientLV.Add("", patient["name"], patient["phone"], patient["email"])
    }
    ListGui.Add("Button", "x10 y320 w100 h30", "New Patient").OnEvent("Click", (*) => OpenNewPatientDialog(ListGui, ""))
    ListGui.Add("Button", "x320 y320 w90 h30", "Close").OnEvent("Click", (*) => ListGui.Destroy())
    
    ListGui.Show("w420 h365")
}
InitializeAppointmentScheduler() {
    global g_AppointmentTypes
    g_AppointmentTypes["ContactLens"] := Map(
        "name", "Contact Lens Exam",
        "duration", 30,
        "color", "cGreen",
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
        "color", "cBlue",
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
        "color", "cRed",
        "tasks", [
            Map("task", "Scan insurance information", "notifyBefore", 15),
            Map("task", "Enter insurance into web app profile", "notifyBefore", 10),
            Map("task", "Verify all data correct", "notifyBefore", 5),
            Map("task", "Ensure name is ALL CAPS in system", "notifyBefore", 5),
            Map("task", "Complete medical history form", "notifyBefore", 0),
            Map("task", "Take patient photos", "notifyBefore", 0),
            Map("task", "Create patient folder", "notifyBefore", 0)
        ]
    )
    g_AppointmentTypes["Medical"] := Map(
        "name", "Medical Visit",
        "duration", 30,
        "color", "cMaroon",
        "tasks", [
            Map("task", "Get credit card on file", "notifyBefore", 10),
            Map("task", "Have patient sign payment authorization", "notifyBefore", 5),
            Map("task", "Determine co-pay amount", "notifyBefore", 5),
            Map("task", "Verify insurance active", "notifyBefore", 5),
            Map("task", "Review chief complaint", "notifyBefore", 0),
            Map("task", "Document visit in EMR", "notifyBefore", 0),
            Map("task", "Process payment", "notifyBefore", 0)
        ]
    )
    g_AppointmentTypes["FollowUp"] := Map(
        "name", "Follow-Up Visit",
        "duration", 15,
        "color", "cPurple",
        "tasks", [
            Map("task", "Review previous visit notes", "notifyBefore", 5),
            Map("task", "Check on prescribed treatment", "notifyBefore", 0),
            Map("task", "Update treatment plan", "notifyBefore", 0)
        ]
    )
    LoadPatients()
    LoadAppointments()
}
ExecuteIdleMouse(params) {
    global g_MouseIdleActive, g_MouseIdleDuration, g_MouseLastX, g_MouseLastY
    global g_MouseHarshThreshold, g_Settings
    duration := params != "" ? Integer(params) : 0  ; 0 = indefinite
    
    g_MouseIdleDuration := duration
    g_MouseIdleActive := true
    MouseGetPos(&g_MouseLastX, &g_MouseLastY)
    
    ShowStatus("Mouse idle: " . (duration = 0 ? "indefinite" : duration . "s"), "wait")
    endTime := duration > 0 ? A_TickCount + (duration * 1000) : 0
    Loop {
        if !g_MouseIdleActive
            break
        if endTime > 0 && A_TickCount >= endTime {
            ShowStatus("Mouse idle complete (timeout)", "ok")
            break
        }
        MouseGetPos(&currentX, &currentY)
        deltaX := Abs(currentX - g_MouseLastX)
        deltaY := Abs(currentY - g_MouseLastY)
        
        if deltaX >= g_MouseHarshThreshold || deltaY >= g_MouseHarshThreshold {
            ShowStatus("Mouse idle ended (harsh movement detected)", "ok")
            break
        }
        g_MouseLastX := currentX
        g_MouseLastY := currentY
        
        Sleep(g_Settings["VerifyInterval"])
    }
    
    g_MouseIdleActive := false
    return true
}
ExecuteHoverMouse(params) {
    global g_Coordinates, g_Settings
    
    if params = "" {
        ShowStatus("HoverMouse requires coordinates", "fail")
        return false
    }
    if g_Coordinates.Has(params) {
        coord := g_Coordinates[params]
        x := coord["x"]
        y := coord["y"]
    } else {
        parts := StrSplit(params, ",")
        if parts.Length < 2 {
            ShowStatus("HoverMouse format: x,y or CoordName", "fail")
            return false
        }
        x := Integer(parts[1])
        y := Integer(parts[2])
    }
    MouseMove(x, y, 5)
    Sleep(g_Settings["PostActionDelay"])
    
    ShowStatus("Mouse hovering at " . x . "," . y, "ok")
    return true
}
ExecuteGrabOCRToVar(params) {
    global g_ExtractedData, g_SpoolVariables, g_SpoolRegions
    
    parts := StrSplit(params, ",")
    if parts.Length < 5 {
        ShowStatus("GrabOCRToVar format: varName,x,y,width,height", "fail")
        ShowNotificationBasic("Invalid Format", "Grab OCR to Var requires:`nvarName,x,y,width,height`n`nExample:`npatientID,100,100,400,200", 0, "error")
        return false
    }
    
    varName := Trim(parts[1])
    x := Integer(parts[2])
    y := Integer(parts[3])
    w := Integer(parts[4])
    h := Integer(parts[5])
    FlashOCRRegion(x, y, w, h)
    try {
        result := OCR.FromRect(x, y, w, h)
        text := result.Text
        g_ExtractedData["$" . varName] := text
        g_ExtractedData["$var." . varName] := text
        g_SpoolVariables["$" . varName] := text
        g_SpoolVariables["$var." . varName] := text
        
        ShowStatus("OCR captured to $" . varName . ": " . text, "ok")
        ShowNotificationBasic("OCR Captured", "Variable: $" . varName . "`n`nText Captured:`n" . text, 0, "success", text)
        
        return true
    } catch as err {
        ShowStatus("OCR capture failed: " . err.Message, "fail")
        ShowNotificationBasic("OCR Failed", "Could not capture text`n`nRegion: " . x . "," . y . "," . w . "," . h . "`n`nError: " . err.Message, 0, "error")
        return false
    }
}

FlashOCRRegion(x, y, w, h, duration := 300) {
    flashGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    flashGui.BackColor := "Yellow"
    WinSetTransparent(100, flashGui.Hwnd)
    flashGui.Show("x" . x . " y" . y . " w" . w . " h" . h . " NoActivate")
    SetTimer(() => flashGui.Destroy(), -duration)
}

FlashClickPosition(x, y, duration := 200) {
    size := 30
    thickness := 4
    flashH := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    flashH.BackColor := "Red"
    WinSetTransparent(150, flashH.Hwnd)
    flashH.Show("x" . (x - size) . " y" . (y - thickness//2) . " w" . (size*2) . " h" . thickness . " NoActivate")
    flashV := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    flashV.BackColor := "Red"
    WinSetTransparent(150, flashV.Hwnd)
    flashV.Show("x" . (x - thickness//2) . " y" . (y - size) . " w" . thickness . " h" . (size*2) . " NoActivate")
    SetTimer(() => (flashH.Destroy(), flashV.Destroy()), -duration)
}
ExecuteUseVarPaste(params) {
    global g_ExtractedData, g_Settings
    
    if params = "" {
        ShowStatus("UseVarPaste requires text with variables", "fail")
        return false
    }
    text := params
    for varName, value in g_ExtractedData {
        if InStr(text, varName) {
            text := StrReplace(text, varName, value)
        }
    }
    Sleep(g_Settings["PreActionDelay"])
    SendText(text)
    Sleep(g_Settings["PostActionDelay"])
    
    ShowStatus("Pasted with variables: " . text, "ok")
    return true
}
ExecuteShowNotification(params) {
    global g_ExtractedData
    
    parts := StrSplit(params, ",")
    if parts.Length < 2 {
        ShowStatus("ShowNotification format: Title,Message[,Timeout]", "fail")
        return false
    }
    
    title := parts[1]
    message := parts[2]
    for varName, value in g_ExtractedData {
        if InStr(message, varName) {
            message := StrReplace(message, varName, value)
        }
    }
    timeout := 0
    if parts.Length >= 3 {
        timeoutStr := Trim(parts[3])
        if IsNumber(timeoutStr)
            timeout := Integer(timeoutStr) * 1000  ; Convert seconds to milliseconds
    }
    
    ShowEnhancedNotification(title, message, timeout)
    return true
}

ShowEnhancedNotification(title, message, timeout := 0) {
    ShowNotificationBasic(title, message, timeout, "info")
}
SnoozeNotification(notifID) {
    global g_NotificationData
    
    if !g_NotificationData.Has(notifID)
        return
    
    data := g_NotificationData[notifID]
    if data["snoozeIndex"] >= data["snoozeSequence"].Length {
        snoozeMin := 5  ; Default to 5 min after sequence exhausted
    } else {
        snoozeMin := data["snoozeSequence"][data["snoozeIndex"] + 1]
        data["snoozeIndex"]++
    }
    ShowStatus("Notification snoozed for " . snoozeMin . " minutes", "ok")
    try data["gui"].Hide()
    SetTimer(() => ReshowNotification(notifID), -snoozeMin * 60 * 1000)
}
ReshowNotification(notifID) {
    global g_NotificationData
    
    if !g_NotificationData.Has(notifID)
        return
    
    data := g_NotificationData[notifID]
    try {
        data["gui"].Show("NoActivate")
        ShowStatus("Notification reminder: " . data["title"], "info")
    }
}
MarkNotificationDone(notifID) {
    global g_NotificationData, g_SpoolNotifications
    
    if !g_NotificationData.Has(notifID)
        return
    
    data := g_NotificationData[notifID]
    try {
        data["gui"].BackColor := "228B22"  ; Green
        Sleep(200)
    }
    DismissNotification(notifID, data["gui"])
    
    ShowStatus("Notification marked as done", "ok")
}
DismissNotification(notifID, notifGui) {
    global g_NotificationData, g_SpoolNotifications
    try notifGui.Destroy()
    g_NotificationData.Delete(notifID)
    for i, notif in g_SpoolNotifications {
        if notif["id"] = notifID {
            g_SpoolNotifications.RemoveAt(i)
            break
        }
    }
    RepositionSpoolNotifications()
}
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
NotificationSingleClick(notifID, *) {
    return
}
InitializeRevolverBins() {
    global g_RevolverBins, g_RevolverBinOrder
    LoadRevolverBins()
    if g_RevolverBins.Count = 0 {
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
CreateRevolverBin(binName, fieldOrder, formatRules) {
    global g_RevolverBins, g_RevolverBinOrder
    
    g_RevolverBins[binName] := Map(
        "items", [],
        "fieldOrder", fieldOrder,
        "formatRules", formatRules,
        "notifyBlock", true,
        "position", 0
    )
    if !HasValue(g_RevolverBinOrder, binName) {
        g_RevolverBinOrder.Push(binName)
    }
    
    ShowStatus("Bin created: " . binName, "ok")
}
LoadRevolverItem(itemString) {
    global g_RevolverBins, g_RevolverBinSelector
    ShowBinSelector(itemString)
}
ShowBinSelector(itemString) {
    global g_RevolverBins, g_RevolverBinSelector
    if g_RevolverBinSelector && WinExist("ahk_id " . g_RevolverBinSelector.Hwnd) {
        try g_RevolverBinSelector.Destroy()
    }
    g_RevolverBinSelector := Gui("+AlwaysOnTop", "Select Bin for Item")
    g_RevolverBinSelector.SetFont("s10", "Segoe UI")
    g_RevolverBinSelector.Add("Text", "x20 y15", "Item to load:")
    g_RevolverBinSelector.Add("Edit", "x20 y+5 w460 ReadOnly", itemString)
    g_RevolverBinSelector.Add("Text", "x20 y+15", "Select bin to load this item into:")
    yPos := 120
    for binName in g_RevolverBins {
        bin := g_RevolverBins[binName]
        btnText := binName . " (" . bin["items"].Length . " items)"
        
        btn := g_RevolverBinSelector.Add("Button", "x20 y" . yPos . " w460 h40", btnText)
        btn.OnEvent("Click", LoadItemIntoBin.Bind(binName, itemString))
        
        yPos += 50
    }
    g_RevolverBinSelector.Add("Button", "x20 y" . yPos . " w460", "Cancel").OnEvent("Click", (*) => g_RevolverBinSelector.Hide())
    g_RevolverBinSelector.Show("w500 h" . (yPos + 60))
}
LoadItemIntoBin(binName, itemString, *) {
    global g_RevolverBins, g_RevolverBinSelector
    
    if !g_RevolverBins.Has(binName)
        return
    
    bin := g_RevolverBins[binName]
    parts := StrSplit(itemString, ",")
    itemData := Map()
    
    for i, fieldName in bin["fieldOrder"] {
        if i <= parts.Length {
            itemData[fieldName] := Trim(parts[i])
        }
    }
    formattedData := ApplyFormatRules(itemData, bin["formatRules"])
    bin["items"].Push(formattedData)
    try g_RevolverBinSelector.Hide()
    
    ShowStatus("Item loaded into " . binName . " (" . bin["items"].Length . " total)", "ok")
    UpdateBinNotification(binName)
}
ApplyFormatRules(itemData, formatRules) {
    formattedData := itemData.Clone()
    
    for rule in formatRules {
        switch rule {
            case "swapNames":
                if formattedData.Has("lastName") && formattedData.Has("firstName") {
                    temp := formattedData["lastName"]
                    formattedData["lastName"] := formattedData["firstName"]
                    formattedData["firstName"] := temp
                }
            
            case "addDate":
                formattedData["date"] := FormatTime(A_Now, "MM/dd/yyyy")
            
            case "upperCase":
                for field, value in formattedData {
                    formattedData[field] := StrUpper(value)
                }
            
            case "removeSpaces":
                for field, value in formattedData {
                    formattedData[field] := StrReplace(value, " ", "")
                }
            
            case "formatPhone":
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
PasteFromBins() {
    global g_RevolverBinOrder, g_RevolverBins, g_Settings
    for binName in g_RevolverBinOrder {
        if !g_RevolverBins.Has(binName)
            continue
        
        bin := g_RevolverBins[binName]
        if bin["items"].Length = 0
            continue
        item := bin["items"][1]
        bin["items"].RemoveAt(1)
        if bin["notifyBlock"] {
            ShowBinNotification(binName, item)
        }
        pasteText := ""
        for fieldName in bin["fieldOrder"] {
            if item.Has(fieldName) {
                if pasteText != ""
                    pasteText .= " "  ; Space separator
                pasteText .= item[fieldName]
            }
        }
        Sleep(g_Settings["PreActionDelay"])
        SendText(pasteText)
        Sleep(g_Settings["PostActionDelay"])
        
        ShowStatus("Pasted from " . binName . ": " . pasteText, "ok")
        UpdateBinNotification(binName)
        
        return true
    }
    
    ShowStatus("All bins empty!", "fail")
    return false
}
ShowBinNotification(binName, item) {
    global g_RevolverBinNotifications
    notif := Gui("+AlwaysOnTop +ToolWindow", "Revolver: " . binName)
    notif.SetFont("s9", "Segoe UI")
    notif.BackColor := "2C3E50"
    notif.Add("Text", "x10 y10 w280 cWhite", "BIN: " . binName).SetFont("s10 bold")
    yPos := 40
    for field, value in item {
        notif.Add("Text", "x10 y" . yPos . " w280 cWhite", field . ": " . value)
        yPos += 20
    }
    notif.Show("x" . (A_ScreenWidth - 320) . " y20 w300 h" . (yPos + 20) . " NoActivate")
    g_RevolverBinNotifications[binName] := notif
    SetTimer(() => HideBinNotification(binName), -2000)
}
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
HideBinNotification(binName) {
    global g_RevolverBinNotifications
    
    if !g_RevolverBinNotifications.Has(binName)
        return
    
    try g_RevolverBinNotifications[binName].Hide()
}
SaveRevolverBins() {
    global g_RevolverBins, g_RevolverBinOrder, DATA_DIR
    
    filepath := DATA_DIR . "\revolver_bins.ini"
    
    try FileDelete(filepath)
    FileAppend("[BinOrder]`n", filepath)
    FileAppend("order=" . ArrayJoin(g_RevolverBinOrder, "|") . "`n`n", filepath)
    for binName, bin in g_RevolverBins {
        FileAppend("[" . binName . "]`n", filepath)
        FileAppend("fieldOrder=" . ArrayJoin(bin["fieldOrder"], "|") . "`n", filepath)
        FileAppend("formatRules=" . ArrayJoin(bin["formatRules"], "|") . "`n", filepath)
        FileAppend("notifyBlock=" . bin["notifyBlock"] . "`n", filepath)
        FileAppend("`n", filepath)
    }
}
LoadRevolverBins() {
    global g_RevolverBins, g_RevolverBinOrder, DATA_DIR
    
    filepath := DATA_DIR . "\revolver_bins.ini"
    
    if !FileExist(filepath)
        return
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
HasValue(arr, value) {
    for item in arr {
        if item = value
            return true
    }
    return false
}



CreateNotepadTab() {
    global MainGui, g_NotepadContent
    notepadTab := MainGui.Add("Tab3", "Choose1", ["Notepad"])
    MainGui.Add("Text", "x20 y+15", "Quick Notepad for Testing & Automation")
    MainGui.Add("Text", "x20 y+5 c888888", "Use this to test text entry, write notes, or prepare automation content")
    notepadEdit := MainGui.Add("Edit", "x20 y+10 w760 h400 vNotepadEdit Multi WantTab", g_NotepadContent)
    MainGui.Add("Button", "x20 y+10 w120", "Save Note").OnEvent("Click", SaveNotepadContent)
    MainGui.Add("Button", "x+10 w120", "Load Note").OnEvent("Click", LoadNotepadContent)
    MainGui.Add("Button", "x+10 w120", "Clear").OnEvent("Click", ClearNotepadContent)
    MainGui.Add("Button", "x+10 w120", "Open Popup").OnEvent("Click", OpenNotepadPopup)
    MainGui.Add("Button", "x+10 w150", "Copy to Clipboard").OnEvent("Click", (*) => CopyNotepadToClipboard())
    MainGui.Add("Text", "x20 y+20", "Quick Actions:")
    MainGui.Add("Button", "x20 y+5 w120", "Auto-Type This").OnEvent("Click", AutoTypeNotepad)
    MainGui.Add("Button", "x+10 w150", "Send to Active Window").OnEvent("Click", SendNotepadToWindow)
    MainGui.Add("Button", "x+10 w120", "New Sequence").OnEvent("Click", NewSequenceFromNotepad)
    MainGui.Add("Text", "x20 y+20", "Saved Notes:")
    noteListLV := MainGui.Add("ListView", "x20 y+5 w760 h100", ["Filename", "Modified", "Size"])
    noteListLV.Name := "NoteListLV"
    noteListLV.OnEvent("DoubleClick", LoadSelectedNote)
    RefreshNoteList()
    
    return notepadTab
}
OpenNotepadPopup(*) {
    global g_NotepadPopupGui, g_NotepadContent
    if g_NotepadPopupGui && WinExist("ahk_id " . g_NotepadPopupGui.Hwnd) {
        try g_NotepadPopupGui.Destroy()
    }
    g_NotepadPopupGui := Gui("+Resize", "MacroAutomator Notepad - Target with WinActivate")
    g_NotepadPopupGui.SetFont("s10", "Consolas")
    g_NotepadPopupGui.Add("Text", "x10 y10", "This window can be targeted: WinActivate('MacroAutomator Notepad')")
    noteEdit := g_NotepadPopupGui.Add("Edit", "x10 y+10 w780 h500 Multi WantTab", g_NotepadContent)
    noteEdit.Name := "PopupNoteEdit"
    g_NotepadPopupGui.Add("Button", "x10 y+10 w100", "Save").OnEvent("Click", SavePopupNotepad)
    g_NotepadPopupGui.Add("Button", "x+10 w100", "Copy All").OnEvent("Click", (*) => CopyPopupToClipboard())
    g_NotepadPopupGui.Add("Button", "x+10 w120", "Clear").OnEvent("Click", ClearPopupNotepad)
    g_NotepadPopupGui.Add("Button", "x+10 w150", "Close").OnEvent("Click", (*) => g_NotepadPopupGui.Hide())
    g_NotepadPopupGui.Add("Text", "x10 y+10 w760 cGray", "Autosaves every 30 seconds • Ctrl+S to save manually")
    SetTimer(AutoSavePopupNotepad, 30000)
    g_NotepadPopupGui.Show("w800 h600")
    
    ShowStatus("Notepad popup opened - Window title: 'MacroAutomator Notepad'", "ok")
}
SaveNotepadContent(*) {
    global g_NotepadContent, NOTES_DIR, MainGui
    try {
        g_NotepadContent := MainGui["NotepadEdit"].Value
    }
    timestamp := FormatTime(A_Now, "yyyyMMdd_HHmmss")
    filename := "note_" . timestamp . ".txt"
    filepath := NOTES_DIR . "\" . filename
    result := InputBoxTop("Save note as:", "Save Note", filename)
    if result["Result"] = "OK" && result["Value"] != "" {
        filename := result["Value"]
        if !InStr(filename, ".txt")
            filename .= ".txt"
        filepath := NOTES_DIR . "\" . filename
    } else if result["Result"] = "Cancel" {
        return
    }
    try {
        FileDelete(filepath)  ; Delete if exists
        FileAppend(g_NotepadContent, filepath, "UTF-8")
        ShowStatus("Note saved: " . filename, "ok")
        RefreshNoteList()
    } catch as err {
        MsgBoxTop("Error saving note: " . err.Message, "Save Error")
    }
}
LoadNotepadContent(*) {
    global g_NotepadContent, NOTES_DIR, MainGui
    notes := []
    loop files NOTES_DIR . "\*.txt" {
        notes.Push(A_LoopFileName)
    }
    
    if notes.Length = 0 {
        MsgBoxTop("No saved notes found.", "Load Note")
        return
    }
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
LoadSelectedNote(*) {
    global NOTES_DIR, MainGui, g_NotepadContent
    row := MainGui["NoteListLV"].GetNext()
    if !row
        return
    filename := MainGui["NoteListLV"].GetText(row, 1)
    filepath := NOTES_DIR . "\" . filename
    try {
        g_NotepadContent := FileRead(filepath, "UTF-8")
        MainGui["NotepadEdit"].Value := g_NotepadContent
        ShowStatus("Loaded: " . filename, "ok")
    } catch as err {
        MsgBoxTop("Error loading note: " . err.Message, "Load Error")
    }
}
ClearNotepadContent(*) {
    global g_NotepadContent, MainGui
    
    result := MsgBoxTop("Clear notepad content?", "Confirm", "YesNo")
    if result = "Yes" {
        g_NotepadContent := ""
        MainGui["NotepadEdit"].Value := ""
        ShowStatus("Notepad cleared", "ok")
    }
}
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
AutoTypeNotepad(*) {
    global MainGui, g_Settings
    
    content := MainGui["NotepadEdit"].Value
    if content = "" {
        MsgBoxTop("Notepad is empty!", "Auto-Type")
        return
    }
    MainGui.Hide()
    Sleep(500)
    SendText(content)
    Sleep(500)
    MainGui.Show()
    ShowStatus("Auto-typed " . StrLen(content) . " characters", "ok")
}
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
NewSequenceFromNotepad(*) {
    global MainGui, g_CurrentSequenceSteps
    
    content := MainGui["NotepadEdit"].Value
    if content = "" {
        MsgBoxTop("Notepad is empty!", "New Sequence")
        return
    }
    g_CurrentSequenceSteps := []
    g_CurrentSequenceSteps.Push(Map(
        "action", "Type",
        "params", content,
        "description", "Type notepad content"
    ))
    try {
        MainGui["Tabs"].Choose(1)  ; Workflow tab
        RefreshStepsLV()

        ShowStatus("Sequence created from notepad content", "ok")
    }
}
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
        lv.ModifyCol()
        lv.ModifyCol(1, "AutoHdr")
        lv.ModifyCol(2, "AutoHdr")
        lv.ModifyCol(3, "AutoHdr")
    }
}
SavePopupNotepad(*) {
    global g_NotepadPopupGui, g_NotepadContent, NOTES_DIR
    
    try {
        g_NotepadContent := g_NotepadPopupGui["PopupNoteEdit"].Value
        timestamp := FormatTime(A_Now, "yyyyMMdd_HHmmss")
        filename := "popup_note_" . timestamp . ".txt"
        filepath := NOTES_DIR . "\" . filename
        FileDelete(filepath)
        FileAppend(g_NotepadContent, filepath, "UTF-8")
        ShowStatus("Popup note saved: " . filename, "ok")
    }
}
CopyPopupToClipboard() {
    global g_NotepadPopupGui
    
    try {
        content := g_NotepadPopupGui["PopupNoteEdit"].Value
        A_Clipboard := content
        ShowStatus("Copied: " . StrLen(content) . " characters", "ok")
    }
}
ClearPopupNotepad(*) {
    global g_NotepadPopupGui
    
    result := MsgBoxTop("Clear popup notepad?", "Confirm", "YesNo")
    if result = "Yes" {
        try g_NotepadPopupGui["PopupNoteEdit"].Value := ""
    }
}
AutoSavePopupNotepad() {
    global g_NotepadPopupGui, g_NotepadContent, NOTES_DIR
    if !g_NotepadPopupGui || !WinExist("ahk_id " . g_NotepadPopupGui.Hwnd) {
        SetTimer(AutoSavePopupNotepad, 0)  ; Stop timer
        return
    }
    
    try {
        g_NotepadContent := g_NotepadPopupGui["PopupNoteEdit"].Value
        filepath := NOTES_DIR . "\autosave_popup.txt"
        FileDelete(filepath)
        FileAppend(g_NotepadContent, filepath, "UTF-8")
    }
}


GuiResize(thisGui, minMax, w, h) {
    if minMax = -1
        return
    try TabCtrl.Move(, , w - 10, h - 75)
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
    g_CurrentSequenceSteps[RowNumber]["enabled"] := IsChecked
}

OnStepsContextMenu(LV, RowNumber, IsRightClick, X, Y) {
    if RowNumber = 0
        return
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
EditPatternByName(name) {
    global g_Patterns, PatternNameEdit, PatternDescEdit, PatternCodeEdit, PatternQualifierDD

    if !g_Patterns.Has(name)
        return

    patternData := g_Patterns[name]
    PatternNameEdit.Value := name
    PatternDescEdit.Value := patternData.Has("desc") ? patternData["desc"] : ""
    PatternCodeEdit.Value := patternData["text"]
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
    tolerance := g_Settings["FindTextTolerance"]
    ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)

    if !ok || ok.Length = 0 {
        ShowStatus("Pattern not found on screen", "fail")
        return
    }
    x := ok[1].mx
    y := ok[1].my
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
    tolerance := g_Settings["FindTextTolerance"]
    ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)

    if !ok || ok.Length = 0 {
        ShowStatus("Pattern not found on screen", "fail")
        return
    }
    x := ok[1].mx
    y := ok[1].my
    patternData["captureX"] := x
    patternData["captureY"] := y
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
}

ToggleAllOffExcept(exceptRow) {
    global g_CurrentSequenceSteps, StepsLV

    for i, step in g_CurrentSequenceSteps {
        step["enabled"] := (i = exceptRow)
    }
    RefreshStepsLV()
    ShowStatus("All OFF except step " . exceptRow, "ok")
}

EnableAllSteps() {
    global g_CurrentSequenceSteps

    for step in g_CurrentSequenceSteps
        step["enabled"] := true
    RefreshStepsLV()
    ShowStatus("All steps enabled", "ok")
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
}

MoveStepUp(row) {
    global g_CurrentSequenceSteps

    if row <= 1 || row > g_CurrentSequenceSteps.Length
        return

    temp := g_CurrentSequenceSteps[row]
    g_CurrentSequenceSteps[row] := g_CurrentSequenceSteps[row - 1]
    g_CurrentSequenceSteps[row - 1] := temp
    RefreshStepsLV()
}

MoveStepDown(row) {
    global g_CurrentSequenceSteps

    if row < 1 || row >= g_CurrentSequenceSteps.Length
        return

    temp := g_CurrentSequenceSteps[row]
    g_CurrentSequenceSteps[row] := g_CurrentSequenceSteps[row + 1]
    g_CurrentSequenceSteps[row + 1] := temp
    RefreshStepsLV()
}

DuplicateStep(row) {
    global g_CurrentSequenceSteps

    if row > g_CurrentSequenceSteps.Length
        return
    original := g_CurrentSequenceSteps[row]
    copy := Map()
    for key, val in original
        copy[key] := val
    g_CurrentSequenceSteps.InsertAt(row + 1, copy)
    RefreshStepsLV()
    ShowStatus("Duplicated step " . row, "ok")
}
SimulateSavedSeqByName(name) {
    global g_Sequences, g_AbortSequence

    if !g_Sequences.Has(name)
        return

    g_AbortSequence := false
    speed := g_Sequences[name].Has("speed") ? g_Sequences[name]["speed"] : 1.0
    SimulateSequence(g_Sequences[name]["steps"], speed)
}

LoadSeqByName(name) {
    global g_Sequences, g_CurrentSequenceSteps, SeqNameEdit, SpeedDD

    if !g_Sequences.Has(name)
        return

    g_CurrentSequenceSteps := []
    for step in g_Sequences[name]["steps"] {
        copy := Map()
        for key, val in step
            copy[key] := val
        g_CurrentSequenceSteps.Push(copy)
    }

    SeqNameEdit.Value := name
    speed := g_Sequences[name].Has("speed") ? g_Sequences[name]["speed"] : 1.0
    SetSpeedDropdown(speed)
    RefreshStepsLV()
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
    g_Sequences[newName] := Map("steps", [], "speed", g_Sequences[name].Has("speed") ? g_Sequences[name]["speed"] : 1.0)
    for step in g_Sequences[name]["steps"] {
        copy := Map()
        for key, val in step
            copy[key] := val
        g_Sequences[newName]["steps"].Push(copy)
    }

    SaveSequences()
    RefreshSeqLV()
    ShowStatus("Duplicated as: " . newName, "ok")
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

    g_Sequences[newName] := g_Sequences[oldName]
    g_Sequences.Delete(oldName)
    SaveSequences()
    RefreshSeqLV()
    ShowStatus("Renamed to: " . newName, "ok")
}

DeleteSeqByName(name) {
    global g_Sequences

    if !g_Sequences.Has(name)
        return

    result := MsgBoxTop("Delete sequence '" . name . "'?", "Confirm", "YesNo")
    if result != "Yes"
        return

    g_Sequences.Delete(name)
    SaveSequences()
    RefreshSeqLV()
    ShowStatus("Deleted: " . name, "ok")
}

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
    fsGui := Gui("+AlwaysOnTop", "Step " . row . " Failsafe: " . action)
    fsGui.SetFont("s9", "Segoe UI")
    fs := step.Has("failsafe") ? step["failsafe"] : Map()
    fsGui.Add("GroupBox", "w450 h80 Section", "Common Failsafes")
    fsGui.Add("Text", "xs+10 ys+20", "Required Window Title:")
    fsWindowEdit := fsGui.Add("Edit", "x+5 w250 vFsWindow", fs.Has("window") ? fs["window"] : "")
    fsGui.Add("Button", "x+5 w60 h22", "Get").OnEvent("Click", (*) => (fsWindowEdit.Value := WinGetTitle("A")))

    fsGui.Add("CheckBox", "xs+10 y+10 vFsAbortOnFail", "Abort sequence if this step fails").Value := fs.Has("abortOnFail") ? fs["abortOnFail"] : 0
    if InStr(action, "Click") || action = "Drag" {
        fsGui.Add("GroupBox", "xs y+20 w450 h100", "Click/Position Failsafes")

        fsGui.Add("CheckBox", "xp+10 yp+20 vFsCheckCloseBtn", "Block clicks near window close button").Value := fs.Has("checkCloseBtn") ? fs["checkCloseBtn"] : 1

        fsGui.Add("CheckBox", "y+8 vFsRequirePattern", "Require pattern visible before clicking:").Value := fs.Has("requirePattern") ? fs["requirePattern"] : 0
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
        fsGui.Add("GroupBox", "xs y+20 w450 h80", "Keyboard Failsafes")

        fsGui.Add("CheckBox", "xp+10 yp+20 vFsWaitForIdle", "Wait for window to be idle before sending").Value := fs.Has("waitForIdle") ? fs["waitForIdle"] : 0

        fsGui.Add("Text", "y+10", "Delay before sending (ms):")
        fsGui.Add("Edit", "x+5 w60 vFsPreDelay Number", fs.Has("preDelay") ? fs["preDelay"] : "0")

    } else if InStr(action, "Activate") || InStr(action, "Taskbar") {
        fsGui.Add("GroupBox", "xs y+20 w450 h80", "Activation Failsafes")

        fsGui.Add("Text", "xp+10 yp+20", "Max wait time (ms):")
        fsGui.Add("Edit", "x+5 w60 vFsMaxWait Number", fs.Has("maxWait") ? fs["maxWait"] : "3000")

        fsGui.Add("CheckBox", "xs+10 y+10 vFsRetryIfHidden", "Retry if window doesn't appear").Value := fs.Has("retryIfHidden") ? fs["retryIfHidden"] : 1

    } else if InStr(action, "Wait") {
        fsGui.Add("GroupBox", "xs y+20 w450 h60", "Wait Failsafes")

        fsGui.Add("CheckBox", "xp+10 yp+20 vFsContinueOnTimeout", "Continue sequence even if wait times out").Value := fs.Has("continueOnTimeout") ? fs["continueOnTimeout"] : 0
    }
    fsGui.Add("GroupBox", "xs y+20 w450 h60", "Retry Settings")
    fsGui.Add("Text", "xp+10 yp+20", "Max retries:")
    fsGui.Add("Edit", "x+5 w50 vFsMaxRetries Number", fs.Has("maxRetries") ? fs["maxRetries"] : "3")
    fsGui.Add("Text", "x+20", "Retry delay (ms):")
    fsGui.Add("Edit", "x+5 w60 vFsRetryDelay Number", fs.Has("retryDelay") ? fs["retryDelay"] : "200")
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
    try {
        fs["window"] := fsGui["FsWindow"].Value
        fs["abortOnFail"] := fsGui["FsAbortOnFail"].Value
        try fs["checkCloseBtn"] := fsGui["FsCheckCloseBtn"].Value
        try fs["requirePattern"] := fsGui["FsRequirePattern"].Value
        try fs["pattern"] := fsGui["FsPattern"].Text != "(none)" ? fsGui["FsPattern"].Text : ""
        try fs["verifyPosition"] := fsGui["FsVerifyPosition"].Value
        try fs["waitForIdle"] := fsGui["FsWaitForIdle"].Value
        try fs["preDelay"] := Integer(fsGui["FsPreDelay"].Value)
        try fs["maxWait"] := Integer(fsGui["FsMaxWait"].Value)
        try fs["retryIfHidden"] := fsGui["FsRetryIfHidden"].Value
        try fs["continueOnTimeout"] := fsGui["FsContinueOnTimeout"].Value
        fs["maxRetries"] := Integer(fsGui["FsMaxRetries"].Value)
        fs["retryDelay"] := Integer(fsGui["FsRetryDelay"].Value)
    }

    step["failsafe"] := fs
    fsGui.Destroy()
    RefreshStepsLV()
    ShowStatus("Failsafe saved for step " . row, "ok")
}

ClearStepFailsafe(row) {
    global g_CurrentSequenceSteps

    if row > g_CurrentSequenceSteps.Length
        return

    if g_CurrentSequenceSteps[row].Has("failsafe")
        g_CurrentSequenceSteps[row].Delete("failsafe")

    RefreshStepsLV()
    ShowStatus("Failsafe cleared for step " . row, "ok")
}
GetFailsafeSummary(step) {
    if !step.Has("failsafe")
        return "-"
    
    fs := step["failsafe"]
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
    patient := g_Patients[patientID]
    patientName := patient["name"]
    typeInfo := g_AppointmentTypes[appointmentType]
    key := date . "_" . StrReplace(time, ":", "")
    appointmentInfo := patientName . " - " . typeInfo["name"]
    g_Appointments[key] := Map(
        "patient", patientName,
        "type", appointmentType,
        "tasks", typeInfo["tasks"]
    )
    appointmentDateTime := date . " " . time
    
    for task in typeInfo["tasks"] {
        notifyMinutes := task["notifyBefore"]
        triggerTime := DateAdd(appointmentDateTime, -notifyMinutes, "Minutes")
        message := patientName . " - " . task["task"]
        CreateScheduledNotification(triggerTime, "Appointment Task", message)
    }
    
    SaveAppointments()
    RefreshCalendar()
}
ClickTimeSlot3(time) {
    BookGui := Gui("+OwnerMainGui", "Book Appointment at " . time)
    BookGui.Add("Text", "x10 y10", "Patient:")
    patientNames := GetPatientNames()
    patientDD := BookGui.Add("DropDownList", "x70 y10 w200", patientNames)
    BookGui.Add("Text", "x10 y40", "Type:")
    typeNames := []
    for key, typeInfo in g_AppointmentTypes {
        typeNames.Push(typeInfo["name"])
    }
    typeDD := BookGui.Add("DropDownList", "x70 y40 w200", typeNames)
    typeDD.OnEvent("Change", (*) => ShowTaskPreview(typeDD, taskPreviewEdit))
    BookGui.Add("Text", "x10 y70", "Tasks that will be scheduled:")
    taskPreviewEdit := BookGui.Add("Edit", "x10 y90 w350 h150 ReadOnly Multi")
    BookGui.Add("Button", "x70 y250 w100 h25", "Book").OnEvent("Click", (*) => ConfirmBooking(time, patientDD, typeDD, BookGui))
    BookGui.Add("Button", "x180 y250 w100 h25", "Cancel").OnEvent("Click", (*) => BookGui.Destroy())
    
    BookGui.Show("w370 h290")
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
    preview := "Pattern: " . name . "`n"
    if desc != ""
        preview .= "Desc: " . desc . "`n"
    preview .= "========================`n"
    preview .= PatternToVisualPreview(code, 30, 12)
    preview .= "`n========================"

    PatternPreviewEdit.Value := preview
    if screenshotPath != "" && FileExist(screenshotPath) {
        try PatternImageBox.Value := screenshotPath
    } else {
        try PatternImageBox.Value := ""
    }
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
        StatusBar.SetText("Finding pattern on screen...")
        tolerance := g_Settings["FindTextTolerance"]
        ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)

        if ok && ok.Length > 0 {
            captureX := ok[1].mx
            captureY := ok[1].my
            FindText().MouseTip(captureX, captureY)
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
    screenshotPath := data.Has("screenshot") ? data["screenshot"] : ""
    if screenshotPath != "" && FileExist(screenshotPath) {
        try PatternImageBox.Value := screenshotPath
    } else {
        try PatternImageBox.Value := ""
    }
    captureX := data.Has("captureX") ? data["captureX"] : 0
    captureY := data.Has("captureY") ? data["captureY"] : 0
    captureWindow := data.Has("captureWindow") ? data["captureWindow"] : ""
    qualifier := data.Has("qualifier") ? data["qualifier"] : ""

    info := "Location:`n" . captureX . ", " . captureY . "`n`n"
    info .= "Window:`n" . (captureWindow != "" ? SubStr(captureWindow, 1, 15) : "(none)") . "`n`n"
    info .= "Qualifier:`n" . (qualifier != "" ? qualifier : "(none)")
    try PatternCaptureInfo.Value := info
    UpdatePatternQualifierDD()
    if qualifier != "" {
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
UpdatePatternQualifierDD() {
    global g_Patterns, PatternQualifierDD
    choices := ["(none)"]
    for name, _ in g_Patterns
        choices.Push(name)
    PatternQualifierDD.Delete()
    PatternQualifierDD.Add(choices)
    PatternQualifierDD.Choose(1)
}
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
    code := ExtractPatternFromCode(rawCode)
    if code = "" {
        MsgBoxTop("Invalid pattern code!", "Invalid")
        return
    }
    StatusBar.SetText("Finding pattern on screen...")
    tolerance := g_Settings["FindTextTolerance"]
    ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)

    if !ok || ok.Length = 0 {
        MsgBoxTop("Pattern not found on screen!`n`nMake sure the pattern is visible.", "Not Found")
        StatusBar.SetText("Pattern not found")
        return
    }
    foundX := ok[1].mx
    foundY := ok[1].my
    FindText().MouseTip(foundX, foundY)
    path := CapturePatternScreenshot(name, foundX, foundY)

    if path != "" && FileExist(path) {
        try PatternImageBox.Value := path
        StatusBar.SetText("Screenshot captured at " . foundX . "," . foundY)
    }
}
ViewPatternImage(*) {
    global PatternLV, g_Patterns

    row := PatternLV.GetNext(0, "Focused")
    if row = 0 {
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
    Run(screenshotPath)
}
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
    code := ExtractPatternFromCode(rawCode)
    if code = "" {
        MsgBoxTop("Invalid pattern code!", "Invalid")
        return
    }
    StatusBar.SetText("Finding pattern on screen...")
    tolerance := g_Settings["FindTextTolerance"]
    ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)

    if !ok || ok.Length = 0 {
        MsgBoxTop("Pattern not found on screen!`n`nMake sure the pattern is visible.", "Not Found")
        StatusBar.SetText("Pattern not found")
        return
    }
    foundX := ok[1].mx
    foundY := ok[1].my
    FindText().MouseTip(foundX, foundY)
    path := CapturePatternScreenshot(name, foundX, foundY)

    if path != "" && FileExist(path) {
        try PatternImageBox.Value := path
        if g_Patterns.Has(name) {
            g_Patterns[name]["screenshot"] := path
            SavePatterns()
            RefreshPatternLV()
        }

        StatusBar.SetText("Screenshot recaptured at " . foundX . "," . foundY)
    }
}
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
    StatusBar.SetText("Finding pattern on screen...")
    tolerance := g_Settings["FindTextTolerance"]
    ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)

    if !ok || ok.Length = 0 {
        MsgBoxTop("Pattern '" . name . "' not found on screen!`n`nMake sure it's visible.", "Not Found")
        StatusBar.SetText("Pattern not found")
        return
    }
    foundX := ok[1].mx
    foundY := ok[1].my
    FindText().MouseTip(foundX, foundY)
    path := CapturePatternScreenshot(name, foundX, foundY)

    if path != "" && FileExist(path) {
        g_Patterns[name]["screenshot"] := path
        g_Patterns[name]["captureX"] := foundX
        g_Patterns[name]["captureY"] := foundY
        hwnd := DllCall("WindowFromPoint", "Int64", (foundY << 32) | (foundX & 0xFFFFFFFF), "Ptr")
        if hwnd
            g_Patterns[name]["captureWindow"] := WinGetTitle("ahk_id " . hwnd)
        SavePatterns()
        RefreshPatternLV()
        StatusBar.SetText("Screenshot added at " . foundX . "," . foundY)
    }
}

QuickCapturePattern(*) {
    global MainGui, PatternNameEdit, PatternCodeEdit, PatternDescEdit, PatternCaptureInfo
    global g_QuickCaptureActive, g_QuickCaptureStart, g_QuickCaptureOverlay
    MainGui.Hide()
    Sleep(200)
    ToolTip("QUICK CAPTURE`n`nDrag to select region...`nESC to cancel", A_ScreenWidth // 2 - 100, 50)
    g_QuickCaptureActive := true
    Hotkey("Escape", CancelQuickCapture, "On")
    KeyWait("LButton", "D")

    if !g_QuickCaptureActive {
        ToolTip()
        MainGui.Show()
        return
    }
    MouseGetPos(&startX, &startY)
    g_QuickCaptureOverlay := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    g_QuickCaptureOverlay.BackColor := "Red"
    WinSetTransparent(80, g_QuickCaptureOverlay)
    while GetKeyState("LButton", "P") && g_QuickCaptureActive {
        MouseGetPos(&currentX, &currentY)
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
    MouseGetPos(&endX, &endY)
    try g_QuickCaptureOverlay.Destroy()
    ToolTip()
    try Hotkey("Escape", "Off")

    if !g_QuickCaptureActive {
        MainGui.Show()
        return
    }

    g_QuickCaptureActive := false
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
    centerX := x1 + w // 2
    centerY := y1 + h // 2
    hwnd := DllCall("WindowFromPoint", "Int64", (centerY << 32) | (centerX & 0xFFFFFFFF), "Ptr")
    windowTitle := ""
    if hwnd
        windowTitle := WinGetTitle("ahk_id " . hwnd)
    StatusBar.SetText("Generating pattern...")
    patternText := FindText().GetTextFromScreen(x1, y1, x2, y2, "**50")

    if patternText = "" || StrLen(patternText) < 10 {
        MsgBoxTop("Could not generate pattern from selection.`n`nTry selecting a more distinct region.", "Capture Failed")
        MainGui.Show()
        return
    }
    patternNum := 1
    while g_Patterns.Has("Capture_" . patternNum)
        patternNum++
    suggestedName := "Capture_" . patternNum
    patternCode := "|<" . suggestedName . ">" . patternText
    MainGui.Show()

    PatternNameEdit.Value := suggestedName
    PatternCodeEdit.Value := patternCode
    PatternDescEdit.Value := "Captured " . w . "x" . h . " @ " . centerX . "," . centerY
    info := "Location:`n" . centerX . ", " . centerY . "`n`n"
    info .= "Window:`n" . (windowTitle != "" ? SubStr(windowTitle, 1, 15) : "(none)") . "`n`n"
    info .= "Size: " . w . "x" . h
    try PatternCaptureInfo.Value := info
    UpdatePatternPreview()
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
global g_QuickCaptureActive := false
global g_QuickCaptureOverlay := ""
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

LoadRevolver() {
    global g_ExtractedData
    if g_ExtractedData.Count = 0 {
        ShowStatus("No fields extracted! Parse clipboard first.", "fail")
        return false
    }
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
LoadRevolverFromSelection() {
    global g_ExtractedData, g_RevolverFieldOrder, g_Settings, ClipEdit
    global g_RevolverChamber, g_RevolverLoaded
    A_Clipboard := ""
    Send("^c")
    ClipWait(1)

    if A_Clipboard = "" {
        ShowStatus("Nothing copied!", "fail")
        SoundBeep(300, 100)
        return false
    }
    ClipEdit.Value := A_Clipboard
    ParseClipboardForRevolver()
    if !LoadRevolverSilent() {
        SoundBeep(300, 100)
        return false
    }
    SoundBeep(800, 50)  ; Quick chirp = loaded
    ShowStatus("Revolver loaded: " . g_RevolverChamber.Length . " shots ready", "ok")
    return true
}
FireAllShots() {
    global g_RevolverChamber, g_RevolverLoaded, g_Settings

    if !g_RevolverLoaded || g_RevolverChamber.Length = 0 {
        ShowStatus("Revolver empty! Ctrl+B to load", "fail")
        SoundBeep(300, 100)
        return false
    }
    Loop g_RevolverChamber.Length {
        chamber := g_RevolverChamber[A_Index]

        ShowStatus("[" . A_Index . "/" . g_RevolverChamber.Length . "] " . chamber["name"], "wait")
        Sleep(g_Settings["PreActionDelay"])
        SendText(chamber["value"])
        Sleep(g_Settings["PostActionDelay"])
        if A_Index < g_RevolverChamber.Length {
            Send("{Tab}")
            Sleep(50)
        }
    }
    shotsFired := g_RevolverChamber.Length
    g_RevolverChamber := []
    g_RevolverLoaded := false
    UpdateRevolverDisplay()
    SoundBeep(600, 50)
    SoundBeep(800, 50)
    ShowStatus("Fired " . shotsFired . " shots!", "ok")
    return true
}
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
    g_RevolverActive := false    UpdateRevolverDisplay()
    return true
}
PreviewRevolverContents() {
    global g_RevolverChamber
    preview := ""
    for i, chamber in g_RevolverChamber {
        preview .= i . ". " . chamber["name"] . ": " . chamber["value"] . "`n"
    }
    return preview
}
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
        if tabBetween && A_Index < g_RevolverChamber.Length {
            Send("{Tab}")
            Sleep(50)
        }
    }

    if enterAtEnd {
        Sleep(50)
        Send("{Enter}")
    }
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
    temp := g_RevolverFieldOrder[row]
    g_RevolverFieldOrder[row] := g_RevolverFieldOrder[row + 1]
    g_RevolverFieldOrder[row + 1] := temp
    RefreshFieldOrderLV()
    FieldOrderLV.Modify(row + 1, "Select Focus")
    SaveFieldOrder()
}

AddFieldToOrder(*) {
    global g_RevolverFieldOrder, g_ExtractionRules
    available := ["CurrentDate"]
    for r in g_ExtractionRules
        available.Push(r["name"])
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

OnActionChange(*) {
    global ActionDD, TargetDD, ParamCombo, ChoicesDD, ActionHelpTitle, ActionHelpText
    
    UpdateHints()
    UpdateTargetDD()
    UpdateParamSuggestions()
    PopulateChoices()
    UpdateActionHelp()  ; V5.0: Update real-time help panel
    action := ActionDD.Text
    if InStr(action, "OCR") || InStr(action, "Grab OCR") {
        screenW := A_ScreenWidth
        screenH := A_ScreenHeight
        fullScreen := "0,0," . screenW . "," . screenH
        if action = "OCR Region" || action = "OCR Click" || action = "OCR Wait" {
            TargetDD.Text := fullScreen
        }
        if action = "OCR Region" && ParamCombo.Text = "" {
            ParamCombo.Text := "var:ocrText"  ; Default: save to variable with clear name
        } else if action = "Grab OCR to Var" && ParamCombo.Text = "" {
            ParamCombo.Text := "varName," . fullScreen
        } else if action = "OCR Click" && ParamCombo.Text = "" {
            ParamCombo.Text := "Button"
        } else if action = "OCR Wait" && ParamCombo.Text = "" {
            ParamCombo.Text := "5000"
        }
    }
    if action = "Wait" && ParamCombo.Text = "" {
        ParamCombo.Text := "1000"
    }
    if action = "Idle Mouse" && ParamCombo.Text = "" {
        ParamCombo.Text := "0"
    }
    if action = "Show Notification" && ParamCombo.Text = "" {
        ParamCombo.Text := "Title,Message,3"
    }
    if InStr(action, "Find &") || InStr(action, "Wait for Pattern") || InStr(action, "Wait Until Gone") {
    }
}

AddWorkflowTooltips() {
    global ActionDD, TargetDD, ParamCombo, ChoicesDD
    
    ActionDD.ToolTip := "Select the action type you want to perform"
    TargetDD.ToolTip := "Where to perform the action (position, pattern, region, etc.)"
    ParamCombo.ToolTip := "Additional parameters for the action (see hint below)"
    ChoicesDD.ToolTip := "Quick selection - click < to copy to Target/Param, Refresh to update list"
}

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
UseChoice(*) {
    global ActionDD, TargetDD, ParamCombo, ChoicesDD
    
    if ChoicesDD.Value = 0
        return
    
    selected := ChoicesDD.Text
    action := ActionDD.Text
    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click", "Hover Mouse", "Drag", "Relative Click":
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
            if InStr(selected, "var:") {
                varName := StrReplace(selected, " (existing)", "")
                varName := StrReplace(varName, " (create new)", "")
                ParamCombo.Text := varName
                ShowStatus("Variable format copied to Param", "ok")
            } else if InStr(selected, "copy") {
                ParamCombo.Text := "copy"
                ShowStatus("Copy mode set", "ok")
            } else if InStr(selected, "(") {
                coords := SubStr(selected, InStr(selected, "(") + 1)
                coords := SubStr(coords, 1, InStr(coords, ")") - 1)
                TargetDD.Text := coords
                ShowStatus("Copied to Target (Region)", "ok")
            }
        
        case "OCR Click", "OCR Wait":
            if InStr(selected, "(") {
                coords := SubStr(selected, InStr(selected, "(") + 1)
                coords := SubStr(coords, 1, InStr(coords, ")") - 1)
                TargetDD.Text := coords
                ShowStatus("Copied to Target (Region)", "ok")
            }
        
        case "Grab OCR to Var":
            if InStr(selected, ",") {
                cleanSelected := StrReplace(selected, " (existing)", "")
                cleanSelected := StrReplace(cleanSelected, " (create new)", "")
                ParamCombo.Text := cleanSelected
                ShowStatus("Copied to Param - adjust coordinates as needed", "ok")
            } else if InStr(selected, "(") {
                coords := SubStr(selected, InStr(selected, "(") + 1)
                coords := SubStr(coords, 1, InStr(coords, ")") - 1)
                ParamCombo.Text := "varName," . coords
                ShowStatus("Copied to Param (change varName)", "ok")
            }
        
        case "Set Clipboard", "Use Var Paste", "Show Notification":
            if InStr(selected, "$var.") {
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
        
        case "Send Keys", "Key Chord", "Taskbar Activate", "Type Text", "Scroll", "Wait", "Menu Select":
            ParamCombo.Text := selected
            ShowStatus("Copied to Param", "ok")
        
        case "Activate Window", "Run Program":
            ParamCombo.Text := selected
            ShowStatus("Copied to Param", "ok")
        
        case "Insert Field":
            ParamCombo.Text := selected
            ShowStatus("Copied to Param (Field)", "ok")
        
        default:
            ParamCombo.Text := selected
            ShowStatus("Copied to Param", "ok")
    }
}
global g_OCRPreview := ""

ShowOCRPreview(coords) {
    global g_OCRPreview, ActionDD
    action := ActionDD.Text
    if !InStr(action, "OCR") && !InStr(action, "Grab OCR")
        return
    parts := StrSplit(coords, ",")
    if parts.Length != 4
        return
    
    x1 := Integer(parts[1])
    y1 := Integer(parts[2])
    x2 := Integer(parts[3])
    y2 := Integer(parts[4])
    if x2 <= x1 || y2 <= y1
        return
    
    w := x2 - x1
    h := y2 - y1
    if g_OCRPreview != "" {
        try g_OCRPreview.Destroy()
    }
    g_OCRPreview := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "OCRPreview")
    g_OCRPreview.BackColor := "00FF00"  ; Green
    g_OCRPreview.Show("x" . x1 . " y" . y1 . " w" . w . " h" . h . " NoActivate")
    WinSetTransparent(100, g_OCRPreview)
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
    try g_OCRPreview.SetFont("s10 bold", "Arial")
    try g_OCRPreview.Add("Text", "x5 y2 cLime BackgroundTrans", "OCR Preview")
    try {
        closeBtn := g_OCRPreview.Add("Button", "x" . (w - 22) . " y2 w20 h20", "✕")
        closeBtn.SetFont("s10 bold")
        closeBtn.OnEvent("Click", (*) => HideOCRPreview())
    }
    SetTimer(() => HideOCRPreview(), -3000)
}

HideOCRPreview(*) {
    global g_OCRPreview
    if g_OCRPreview != "" {
        try g_OCRPreview.Destroy()
        g_OCRPreview := ""
    }
}
OnTargetChange(*) {
    global TargetDD, ActionDD
    
    action := ActionDD.Text
    coords := TargetDD.Text
    if (InStr(action, "OCR") || InStr(action, "Grab OCR")) && InStr(coords, ",") {
        parts := StrSplit(coords, ",")
        if parts.Length = 4 {
            ShowOCRPreview(coords)
        }
    }
}
OnParamChange(*) {
    global ParamCombo, ActionDD
    
    action := ActionDD.Text
    param := ParamCombo.Text
    if InStr(action, "Grab OCR") {
        parts := StrSplit(param, ",")
        if parts.Length >= 5 {
            coords := parts[2] . "," . parts[3] . "," . parts[4] . "," . parts[5]
            ShowOCRPreview(coords)
        }
    }
}

UpdateHints(*) {
    return
}
UpdateActionHelp(*){
    global ActionDD, ActionHelpTitle, ActionHelpText
    
    action := ActionDD.Text
    helpData := Map()
    helpData["Click"] := Map(
        "title", "Click - Single mouse click",
        "text", "TARGET: Position name or x,y coordinates`nPARAM: (optional) Click count`n`n"
            . "Examples:`n"
            . "• Target=SubmitButton`n"
            . "• Target=500,300`n"
            . "• Param=1 (single click, default)`n`n"
            . "💡 TIP: Capture positions in Patterns tab first`n"
            . "⚠️ ERROR: 'Position not found' = Check spelling"
    )
    
    helpData["Double Click"] := Map(
        "title", "Double Click - Rapid two clicks",
        "text", "TARGET: Position name or coordinates`nPARAM: (not used)`n`n"
            . "Common uses:`n"
            . "• Open files/folders`n"
            . "• Select words in text fields`n`n"
            . "💡 Equivalent to Click with Param=2"
    )
    
    helpData["Right Click"] := Map(
        "title", "Right Click - Context menu",
        "text", "TARGET: Position name or coordinates`nPARAM: (not used)`n`n"
            . "Opens right-click context menu at position"
    )
    
    helpData["Drag"] := Map(
        "title", "Drag - Click and drag",
        "text", "TARGET: Drag position name (must have start+end)`nPARAM: Duration in ms (default 300)`n`n"
            . "How to capture drag:`n"
            . "1. Patterns tab → Drag button`n"
            . "2. Click start position`n"
            . "3. Drag to end position`n"
            . "4. Release`n`n"
            . "Example: Target=ScrollDrag, Param=500"
    )
    helpData["Find & Click"] := Map(
        "title", "Find & Click - Find image and click",
        "text", "TARGET: Pattern name`nPARAM: (optional) Search region x,y,width,height`n`n"
            . "How it works:`n"
            . "1. Searches screen for pattern image`n"
            . "2. Clicks center of found pattern`n`n"
            . "Example:`n"
            . "• Target=SubmitButton`n"
            . "• Param=0,0,1920,1080 (search full screen)`n`n"
            . "⚠️ Pattern not found?`n"
            . "→ Recapture pattern`n"
            . "→ Increase variation tolerance`n"
            . "→ Check if button visible"
    )
    
    helpData["Find & DblClick"] := Map(
        "title", "Find & DblClick - Find and double-click",
        "text", "TARGET: Pattern name`nPARAM: (optional) Search region`n`n"
            . "Same as Find & Click but double-clicks"
    )
    
    helpData["Wait for Pattern"] := Map(
        "title", "Wait for Pattern - Pause until pattern appears",
        "text", "TARGET: Pattern name`nPARAM: Timeout in ms (0 = infinite)`n`n"
            . "Workflow pauses until pattern found on screen.`n"
            . "INTERRUPTIBLE - can be stopped during wait.`n`n"
            . "Example:`n"
            . "• Target=LoadingComplete`n"
            . "• Param=30000 (wait up to 30 sec)`n`n"
            . "Use cases:`n"
            . "→ Wait for app to load`n"
            . "→ Wait for processing to complete`n"
            . "→ Wait for dialog to appear"
    )
    helpData["OCR Region"] := Map(
        "title", "OCR Region - Extract text from screen area",
        "text", "TARGET: x,y,width,height`nPARAM: var:variableName`n`n"
            . "⚠️ CRITICAL FORMAT:`n"
            . "TARGET uses x,y,WIDTH,HEIGHT (not x2,y2!)`n`n"
            . "Example: 100,100,400,200 means:`n"
            . "• Start at coordinates (100, 100)`n"
            . "• Capture area 400 pixels wide`n"
            . "• Capture area 200 pixels tall`n`n"
            . "Variable format:`n"
            . "• PARAM: var:patientID`n"
            . "• Creates: `$var.patientID`n"
            . "• Use later in Type Text or Set Clipboard`n`n"
            . "💡 Use 📷 OCR button for auto-calculation!"
    )
    
    helpData["Grab OCR to Var"] := Map(
        "title", "Grab OCR to Var - OCR and store in variable",
        "text", "PARAM: variableName,x,y,width,height`n`n"
            . "Format: NO `$var. prefix!`n"
            . "Example: docType,100,50,400,150`n`n"
            . "Creates variable: `$var.docType`n"
            . "Use later:`n"
            . "• If Contains → Target: docType`n"
            . "• Type Text → Param: `$var.docType`n`n"
            . "💡 Check Choices dropdown for existing vars"
    )
    
    helpData["OCR Click"] := Map(
        "title", "OCR Click - Find text via OCR and click",
        "text", "TARGET: Search region x,y,width,height`nPARAM: Text to find`n`n"
            . "Example:`n"
            . "• Target=0,0,1920,1080`n"
            . "• Param=Submit`n`n"
            . "⚠️ Text must be clearly visible`n"
            . "⚠️ Increase OCR scale if detection fails"
    )
    
    helpData["OCR Wait"] := Map(
        "title", "OCR Wait - Wait for text to appear/disappear",
        "text", "PARAM: appear/disappear,Text,Timeout,x,y,w,h`n`n"
            . "INTERRUPTIBLE - workflow pauses during wait`n`n"
            . "Example (wait for 'Complete'):`n"
            . "appear,Complete,5000,100,100,300,200`n`n"
            . "Example (wait for 'Loading' to disappear):`n"
            . "disappear,Loading...,10000,0,0,500,100`n`n"
            . "Use cases:`n"
            . "→ Wait for processing to finish`n"
            . "→ Wait for status to change"
    )
    helpData["Send Keys"] := Map(
        "title", "Send Keys - Send keyboard input (fast)",
        "text", "PARAM: Keys to send`n`n"
            . "Special keys:`n"
            . "• {Enter} {Tab} {Esc} {Space}`n"
            . "• {Up} {Down} {Left} {Right}`n"
            . "• {F1} through {F12}`n"
            . "• {Home} {End} {PgUp} {PgDn}`n`n"
            . "Modifiers:`n"
            . "• ^ = Ctrl`n"
            . "• + = Shift`n"
            . "• ! = Alt`n"
            . "• # = Win`n`n"
            . "Examples:`n"
            . "• ^c (Ctrl+C to copy)`n"
            . "• +{Tab} (Shift+Tab)`n"
            . "• !{F4} (Alt+F4 to close)`n"
            . "• Hello{Enter} (type and press Enter)"
    )
    
    helpData["Type Text"] := Map(
        "title", "Type Text - Type text character by character",
        "text", "PARAM: Text to type (literal)`n`n"
            . "Supports variables:`n"
            . "• `$var.patientName`n"
            . "• `$var.dateOfBirth`n`n"
            . "Examples:`n"
            . "• john.doe@email.com`n"
            . "• Patient: `$var.lastName`n`n"
            . "💡 Slower than Send Keys but more reliable`n"
            . "💡 Use for special characters that fail in Send Keys"
    )
    
    helpData["Paste"] := Map(
        "title", "Paste - Send Ctrl+V",
        "text", "No TARGET or PARAM needed`n`n"
            . "Pastes current clipboard content`n`n"
            . "Workflow:`n"
            . "1. Set Clipboard`n"
            . "2. Click → Target=TextField`n"
            . "3. Paste"
    )
    helpData["Set Clipboard"] := Map(
        "title", "Set Clipboard - Copy text to clipboard",
        "text", "PARAM: Text or variable`n`n"
            . "Examples:`n"
            . "• Static: Hello World`n"
            . "• Variable: `$var.ocrText`n"
            . "• Mixed: Patient: `$var.patientID`n`n"
            . "💡 Choices dropdown shows available variables`n"
            . "💡 Click '<' to insert selected variable"
    )
    helpData["Set Variable"] := Map(
        "title", "Set Variable - Create or update variable",
        "text", "TARGET: Variable name (no `$ prefix)`nPARAM: Value`n`n"
            . "Examples:`n"
            . "• Target=counter, Param=0`n"
            . "• Target=fullName, Param=John Smith`n"
            . "• Target=formatted, Param=INV-`$var.id`n`n"
            . "Use later:`n"
            . "• Type Text → `$var.counter`n"
            . "• If Variable → Target: counter`n`n"
            . "💡 Variables persist within workflow"
    )
    
    helpData["Grab Clipboard"] := Map(
        "title", "Grab Clipboard - Store clipboard to variable",
        "text", "TARGET: Variable name (no `$ prefix)`nPARAM: (not used)`n`n"
            . "Example:`n"
            . "• Target=clipData`n"
            . "Creates: `$var.clipData`n`n"
            . "Workflow:`n"
            . "1. User copies data (Ctrl+C)`n"
            . "2. Grab Clipboard → Target=rawData`n"
            . "3. Format Clipboard → modify it`n"
            . "4. Set Clipboard → paste formatted version"
    )
    
    helpData["If Contains"] := Map(
        "title", "If Contains - Conditional execution",
        "text", "TARGET: Variable name to check`nPARAM: Text to look for`n`n"
            . "If variable contains text → Execute next action`n"
            . "If NOT found → Skip next action`n`n"
            . "Example:`n"
            . "1. Grab OCR to Var → docType,100,50,400,150`n"
            . "2. If Contains → Target: docType, Param: INVOICE`n"
            . "3. MsgBox → 'Found invoice'`n`n"
            . "💡 IMPORTANT: Add 'Stop Execution' after each branch!`n`n"
            . "Pattern:`n"
            . "• If Contains → word1`n"
            . "• [actions for word1]`n"
            . "• Stop Execution ← CRITICAL!`n"
            . "• If Contains → word2`n"
            . "• [actions for word2]`n"
            . "• Stop Execution"
    )
    
    helpData["If Variable"] := Map(
        "title", "If Variable - Compare variable value",
        "text", "TARGET: Variable name`nPARAM: Operator,Value`n`n"
            . "Operators:`n"
            . "• = (equals)`n"
            . "• != (not equals)`n"
            . "• > (greater than)`n"
            . "• < (less than)`n"
            . "• >= (greater or equal)`n"
            . "• <= (less or equal)`n`n"
            . "Examples:`n"
            . "• Target=counter, Param==,10`n"
            . "• Target=status, Param=!=,error`n"
            . "• Target=count, Param=>,5"
    )
    
    helpData["Stop Execution"] := Map(
        "title", "Stop Execution - Stop workflow immediately",
        "text", "No TARGET or PARAM needed`n`n"
            . "Stops workflow at this step.`n"
            . "Steps after this will NOT execute.`n`n"
            . "Use after conditional branches:`n"
            . "1. If Contains → INVOICE`n"
            . "2. [process invoice]`n"
            . "3. Stop Execution ← Prevents checking RECEIPT`n"
            . "4. If Contains → RECEIPT`n"
            . "5. [process receipt]"
    )
    
    helpData["Run Sequence"] := Map(
        "title", "Run Sequence - Trigger another workflow",
        "text", "PARAM: Workflow name`n`n"
            . "Calls another saved workflow.`n"
            . "Variables pass through to called workflow.`n`n"
            . "Examples:`n"
            . "• Param=ReceiptLogger`n"
            . "• Param=FormatInvoice`n"
            . "• Param=ErrorHandler`n`n"
            . "Use cases:`n"
            . "→ Modular workflows (main + sub-tasks)`n"
            . "→ Reusable components`n"
            . "→ Error handling`n`n"
            . "⚠️ Workflow must exist and be saved first"
    )
    helpData["Format Clipboard"] := Map(
        "title", "Format Clipboard - Transform clipboard data",
        "text", "PARAM: Template name or format string`n`n"
            . "Built-in templates:`n"
            . "• invoice → Prefix with 'INV-'`n"
            . "• receipt → Prefix with 'RCP-'`n"
            . "• uppercase → ALL CAPS`n"
            . "• lowercase → all lowercase`n"
            . "• titlecase → Title Case`n"
            . "• trim → Remove extra spaces`n"
            . "• date_iso → Format as YYYY-MM-DD`n`n"
            . "Custom format:`n"
            . "Use {clip} for clipboard content`n"
            . "Example: Patient: {clip} - Active`n`n"
            . "Variables supported:`n"
            . "{clip} → current clipboard`n"
            . "`$var.name → any variable"
    )
    
    helpData["Append to Clipboard"] := Map(
        "title", "Append to Clipboard - Add to end",
        "text", "PARAM: Text to append`n`n"
            . "Adds text to END of clipboard.`n`n"
            . "Example:`n"
            . "• Clipboard: 'John'`n"
            . "• Param=  Smith`n"
            . "• Result: 'John Smith'"
    )
    
    helpData["Prepend to Clipboard"] := Map(
        "title", "Prepend to Clipboard - Add to start",
        "text", "PARAM: Text to prepend`n`n"
            . "Adds text to START of clipboard.`n`n"
            . "Example:`n"
            . "• Clipboard: '12345'`n"
            . "• Param=INV-`n"
            . "• Result: 'INV-12345'"
    )
    
    helpData["Extract from Clipboard"] := Map(
        "title", "Extract from Clipboard - Parse data",
        "text", "PARAM: Extraction rule`n`n"
            . "Patterns:`n"
            . "• between:|start|end → Extract between delimiters`n"
            . "• regex:|pattern → Use regex pattern`n"
            . "• field:|delimiter|index → Split and get field`n`n"
            . "Examples:`n"
            . "• between:|Name:|,DOB: → Get name`n"
            . "• field:|||,|2 → Split by comma, get 2nd field`n"
            . "• regex:|\d{5} → Extract 5-digit number"
    )
    helpData["Wait"] := Map(
        "title", "Wait - Pause execution",
        "text", "PARAM: Milliseconds`n`n"
            . "Examples:`n"
            . "• 1000 = 1 second`n"
            . "• 500 = 0.5 seconds`n"
            . "• 2000 = 2 seconds`n`n"
            . "💡 Add after:`n"
            . "→ Opening windows`n"
            . "→ Clicking buttons`n"
            . "→ Before OCR (let text render)"
    )
    
    helpData["Show Notification"] := Map(
        "title", "Show Notification - Display popup",
        "text", "PARAM: Title,Message,Duration`n`n"
            . "Example:`n"
            . "Task Complete,Processing finished!,3`n`n"
            . "Duration in seconds (0 = manual dismiss)"
    )
    if InStr(action, "---") {
        ActionHelpTitle.Text := action
        ActionHelpText.Text := "Section divider - select an action from this section."
        return
    }
    if helpData.Has(action) {
        data := helpData[action]
        ActionHelpTitle.Text := data["title"]
        ActionHelpText.Text := data["text"]
    } else {
        ActionHelpTitle.Text := action
        ActionHelpText.Text := "This action doesn't have detailed help yet.`n`n"
            . "Check the action name and parameter fields for basic usage.`n`n"
            . "💡 Refer to workflow examples in documentation."
    }
}







PopulateChoices() {
    global ActionDD, ChoicesDD, g_ExtractedData, g_Coordinates, g_Patterns, g_TaskbarApps, g_Sequences, g_CurrentSequenceSteps
    
    action := ActionDD.Text
    choices := []
    sequenceVars := GetSequenceVariables()
    
    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click", "Hover Mouse":
            for name, coord in g_Coordinates
                choices.Push(name . " (" . coord["x"] . "," . coord["y"] . ")")
        
        case "Drag":
            for name, coord in g_Coordinates {
                if coord.Has("endX")
                    choices.Push(name . " (" . coord["x"] . "," . coord["y"] . "→" . coord["endX"] . "," . coord["endY"] . ")")
            }
        
        case "Relative Click":
            for name, coord in g_Coordinates {
                if coord.Has("relative") && coord["relative"]
                    choices.Push(name . " (+" . coord["x"] . ",+" . coord["y"] . ")")
            }
        
        case "Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick", "Find & Drag":
            for name, _ in g_Patterns
                choices.Push(name)
        
        case "Wait for Pattern", "Wait Until Gone":
            for name, _ in g_Patterns
                choices.Push(name)
        
        case "OCR Region":
            if sequenceVars.Length > 0 {
                for varName in sequenceVars
                    choices.Push("var:" . varName . " (existing)")
            }
            choices.Push("var:newVariable (create new)")
            choices.Push("copy (to clipboard)")
        
        case "Set Clipboard", "Use Var Paste", "Show Notification":
            if sequenceVars.Length > 0 {
                for varName in sequenceVars
                    choices.Push("$var." . varName)
            }
            choices.Push("(type text or variable)")
        
        case "Grab OCR to Var":
            if sequenceVars.Length > 0 {
                for varName in sequenceVars
                    choices.Push(varName . ",x,y,w,h (existing)")
            }
            choices.Push("newVariable,x,y,w,h (create new)")
        
        case "OCR Click", "OCR Wait":
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
            for i in [1,2,3,4,5,6,7,8,9,0] {
                appName := g_TaskbarApps.Has(i) ? g_TaskbarApps[i] : ""
                if appName != ""
                    choices.Push(i . ",1  (" . appName . ")")
                else
                    choices.Push(i . ",1  (Position " . i . ")")
            }
        
        case "Activate Window":
            choices := GetWindowList()
        
        case "Run Program":
            choices := GetCommonPrograms()
        
        case "Insert Field":
            for name, _ in g_ExtractedData
                choices.Push(name)
            if choices.Length = 0
                choices.Push("(no fields extracted yet)")
        
        case "Type Text", "Use Var Paste":
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
    ChoicesDD.Delete()
    if choices.Length > 0
        ChoicesDD.Add(choices)




    choice := ChoicesDD.Text
    if choice = ""
        return
    action := ActionDD.Text
    if action = "Key Chord" || action = "Taskbar Activate" {
        if InStr(choice, "  ")
            choice := Trim(SubStr(choice, 1, InStr(choice, "  ") - 1))
        ParamCombo.Text := choice
        return
    }
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


UpdateParamSuggestions() {
    global ActionDD, ParamCombo, g_ExtractedData, g_TaskbarApps
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
        
        case "Grab OCR to Var":
            suggestions := [
                "patientName,0,0,1920,1080",
                "varName,x1,y1,x2,y2"
            ]
        
        case "Show Notification":
            suggestions := [
                "Title,Message,3",
                "Complete,Task finished,5"
            ]
    }
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
            for name, coord in g_Coordinates {
                if !coord.Has("endX") && (!coord.Has("relative") || !coord["relative"])
                    items.Push(name)
            }
        
        case "Drag":
            for name, coord in g_Coordinates {
                if coord.Has("endX")
                    items.Push(name)
            }
        
        case "Relative Click":
            for name, coord in g_Coordinates {
                if coord.Has("relative") && coord["relative"]
                    items.Push(name)
            }
        
        case "Hover Mouse":
            for name, coord in g_Coordinates {
                if !coord.Has("endX")
                    items.Push(name)
            }
        
        case "Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick", "Find & Drag", "Wait for Pattern", "Wait Until Gone":
            for name, _ in g_Patterns
                items.Push(name)
        
        case "OCR Region", "OCR Click", "OCR Wait":
            items := [
                "0,0," . A_ScreenWidth . "," . A_ScreenHeight,  ; Full screen
                "0,0," . A_ScreenWidth . "," . A_ScreenHeight//2,  ; Top half
                "0," . A_ScreenHeight//2 . "," . A_ScreenWidth . "," . A_ScreenHeight  ; Bottom half
            ]
        
        case "Grab OCR to Var":
            items := ["(leave blank - use Param field)"]
        
        case "Activate Window":
            items := GetWindowList()
        
        default:
            items := ["(not applicable)"]
    }
    currentText := TargetDD.Text
    TargetDD.Delete()
    
    if items.Length > 0 {
        TargetDD.Add(items)
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
}
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

CreatePatient2(name, phone := "", email := "", notes := "") {
    id := g_NextPatientID++
    g_Patients[id] := Map(
        "id", id,
        "name", name,
        "phone", phone,
        "email", email,
        "notes", notes
    )
    SavePatients()
    return id
}
OpenPatientProfileEditor(patientID := 0) {
    ProfileGui := Gui("+OwnerMainGui", "Patient Profile")
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


SelectOCRRegionForWorkflow(*) {
    global MainGui, ActionDD, TargetDD, ParamCombo, g_LastOCRRegion, g_OCRHighlight
    action := ActionDD.Text
    if !InStr(action, "OCR") && !InStr(action, "Grab OCR") {
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
    ToolTip("📷 Drag to select OCR region`nESC to cancel`nHighlight will persist after selection", A_ScreenWidth//2 - 150, 50)
    x1 := 0, y1 := 0, x2 := 0, y2 := 0
    cancelled := false
    selBox := ""
    boxW := 0, boxH := 0    Hotkey("Escape", (*) => (cancelled := true), "On")
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
    selBox := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "SelBox")
    selBox.BackColor := "00FF00"
    while GetKeyState("LButton", "P") && !cancelled {
        MouseGetPos(&x2, &y2)
        boxX := Min(x1, x2)
        boxY := Min(y1, y2)
        boxW := Max(Abs(x2 - x1), 10)
        boxH := Max(Abs(y2 - y1), 10)

        if boxW > 5 && boxH > 5 {
            selBox.Show("x" . boxX . " y" . boxY . " w" . boxW . " h" . boxH . " NoActivate")
            WinSetTransparent(180, selBox)
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
    ToolTip()
    Hotkey("Escape", "Off")

    if cancelled || Abs(x2 - x1) < 10 || Abs(y2 - y1) < 10 {
        try selBox.Destroy()
        MainGui.Show()
        return
    }
    finalX1 := Min(x1, x2)
    finalY1 := Min(y1, y2)
    finalX2 := Max(x1, x2)
    finalY2 := Max(y1, y2)
    coordStr := finalX1 . "," . finalY1 . "," . finalX2 . "," . finalY2
    g_LastOCRRegion := Map("x1", finalX1, "y1", finalY1, "x2", finalX2, "y2", finalY2)
    if g_OCRHighlight != "" {
        try g_OCRHighlight.Destroy()
    }
    g_OCRHighlight := selBox  ; Keep the selection box as persistent highlight
    WinSetTransparent(120, g_OCRHighlight)  ; Make it semi-transparent
    try g_OCRHighlight.SetFont("s12 bold", "Arial")
    try g_OCRHighlight.Add("Text", "x5 y-2 cLime BackgroundTrans", "OCR Region")
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
    currentAction := ActionDD.Text
    if ParamCombo.Text = "" {
        if InStr(currentAction, "Grab OCR") {
            ParamCombo.Text := "varName," . coordStr
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
    if ActionDD.Text = "" {
        ShowStatus("Please select an action", "fail")
        return
    }
    
    action := ActionDD.Text
    requiresTarget := ["Click", "Double Click", "Triple Click", "Right Click", "Drag", "Hover Mouse",
                       "Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick", "Find & Drag",
                       "Wait for Pattern", "Wait Until Gone", "OCR Region", "OCR Click", "OCR Wait"]
    
    if HasValue(requiresTarget, action) && TargetDD.Text = "" {
        ShowStatus("This action requires a Target value", "fail")
        return
    }
    if action = "Grab OCR to Var" {
        if ParamCombo.Text = "" || !InStr(ParamCombo.Text, ",") {
            ShowStatus("Grab OCR format: varName,x1,y1,x2,y2", "fail")
            return
        }
        parts := StrSplit(ParamCombo.Text, ",")
        if parts.Length < 5 {
            ShowStatus("Grab OCR needs: varName,x1,y1,x2,y2", "fail")
            return
        }
    }
    if !ShowParameterValidation(action, TargetDD.Text, ParamCombo.Text) {
        return
    }
    
    global g_CurrentSequenceSteps, ActionDD, TargetDD, ParamEdit, QualPatternDD, QualWindowEdit
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
        step["failsafe"] := "close_button"

    g_CurrentSequenceSteps.Push(step)
    RefreshStepsLV()
    ParamEdit.Value := ""
    PopulateChoices()  ; V5.1: Refresh choices to show any new variables
    StatusBar.SetText("Added step " . g_CurrentSequenceSteps.Length)
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
    editGui := Gui("+AlwaysOnTop", "Edit Step " . row . ": " . action)
    editGui.SetFont("s9", "Segoe UI")
    editGui.Add("Text", "w400", "Action: " . action)
    editGui.Add("Text", "", "(To change action, delete and re-add step)")
    editGui.Add("GroupBox", "y+15 w420 h75 Section", "Target")
    editGui.Add("Text", "xs+10 ys+20", "Current:")
    editGui.Add("Edit", "x+5 w300 ReadOnly", target)
    editGui.Add("Text", "xs+10 y+8", "Change to:")
    targetChoices := ["(none)"]
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
    editGui.Add("GroupBox", "xs y+20 w420 h130", "Parameter")
    editGui.Add("Text", "xp+10 yp+20", "Current value:")
    editParamEdit := editGui.Add("Edit", "w390 h22 vNewParam", param)
    editGui.Add("Text", "y+10", "Suggestions for " . action . ":")
    suggestions := GetActionParamSuggestions(action)
    editSuggestDD := editGui.Add("DropDownList", "w300 vSuggestion", suggestions)
    editGui.Add("Button", "x+5 w80 h22", "Use").OnEvent("Click", (*) => (editParamEdit.Value := CleanSuggestion(editSuggestDD.Text)))
    editGui.Add("Text", "xs+10 y+8 w400 cGray", GetActionParamHelp(action))
    editGui.Add("Button", "xs y+20 w120 h26", "🛡 Edit Failsafe...").OnEvent("Click", (*) => (editGui.Destroy(), EditStepFailsafeByRow(row)))
    editGui.Add("Button", "x+120 w80 h26", "Save").OnEvent("Click", (*) => SaveEditedStep(editGui, row))
    editGui.Add("Button", "x+10 w80 h26", "Cancel").OnEvent("Click", (*) => editGui.Destroy())

    editGui.Show()
}
GetActionParamSuggestions(action) {
    global g_ExtractedData, g_TaskbarApps

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
        default:
            return [""]
    }
}
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
        default:
            return ""
    }
}
CleanSuggestion(text) {
    if InStr(text, "  (")
        return Trim(SubStr(text, 1, InStr(text, "  (") - 1))
    if InStr(text, "  [")
        return Trim(SubStr(text, 1, InStr(text, "  [") - 1))
    return text
}
SaveEditedStep(editGui, row) {
    global g_CurrentSequenceSteps

    if row > g_CurrentSequenceSteps.Length
        return

    saved := editGui.Submit(false)
    if saved.NewTarget != "(none)"
        g_CurrentSequenceSteps[row]["target"] := saved.NewTarget
    g_CurrentSequenceSteps[row]["param"] := saved.NewParam

    editGui.Destroy()
    RefreshStepsLV()
    ShowStatus("Step " . row . " updated", "ok")
}

DelStep(*) {
    global g_CurrentSequenceSteps, StepsLV
    row := StepsLV.GetNext(0, "Focused")
    if row = 0
        return
    g_CurrentSequenceSteps.RemoveAt(row)
    RefreshStepsLV()
}

ToggleStep(*) {
    global g_CurrentSequenceSteps, StepsLV
    row := StepsLV.GetNext(0, "Focused")
    if row = 0
        return
    if !g_CurrentSequenceSteps[row].Has("enabled")
        g_CurrentSequenceSteps[row]["enabled"] := true
    
    g_CurrentSequenceSteps[row]["enabled"] := !g_CurrentSequenceSteps[row]["enabled"]
    RefreshStepsLV()
    StepsLV.Modify(row, "Select Focus")
}

ClearSteps(*) {
    global g_CurrentSequenceSteps
    g_CurrentSequenceSteps := []
    RefreshStepsLV()
}

RefreshStepsLV() {
    global g_CurrentSequenceSteps, StepsLV
    StepsLV.Delete()
    for i, s in g_CurrentSequenceSteps {
        if !s.Has("enabled")
            s["enabled"] := true
        
        failsafeSummary := GetFailsafeSummary(s)
        StepsLV.Add(s["enabled"] ? "Check" : "", i, s["action"], s["target"], s["param"], failsafeSummary)
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
    steps := []
    for s in g_CurrentSequenceSteps {
        ns := Map()
        for k, v in s
            ns[k] := v
        steps.Push(ns)
    }
    speedText := SpeedDD.Text
    speedMultiplier := Float(StrReplace(speedText, "x", ""))
    seqData := Map("steps", steps, "speed", speedMultiplier)
    
    if saved.SeqHotkey != ""
        seqData["hotkey"] := saved.SeqHotkey
    
    if saved.SeqHotstring != ""
        seqData["hotstring"] := saved.SeqHotstring

    g_Sequences[saved.SeqName] := seqData
    RegisterSequenceTriggers(saved.SeqName)
    
    RefreshSeqLV()
    g_CurrentSequenceSteps := []
    RefreshStepsLV()
    SeqNameEdit.Value := ""
    SeqHotkeyEdit.Value := ""
    SeqHotstringEdit.Value := ""
    SaveSequences()
    StatusBar.SetText("Saved: " . saved.SeqName . " @ " . speedText)
    
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
        SeqLV.Add(, name, seq["steps"].Length, speed)
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
    g_CurrentSequenceSteps := []
    for s in g_Sequences[name]["steps"] {
        ns := Map()
        for k, v in s
            ns[k] := v
        if !ns.Has("enabled")
            ns["enabled"] := true
        
        g_CurrentSequenceSteps.Push(ns)
    }
    SeqNameEdit.Value := name
    speed := g_Sequences[name].Has("speed") ? g_Sequences[name]["speed"] : 1.0
    SetSpeedDropdown(speed)
    seq := g_Sequences[name]
    SeqHotkeyEdit.Value := seq.Has("hotkey") ? seq["hotkey"] : ""
    SeqHotstringEdit.Value := seq.Has("hotstring") ? seq["hotstring"] : ""

    RefreshStepsLV()
}

RegisterSequenceTriggers(seqName) {
    global g_Sequences, g_SequenceHotkeys, g_SequenceHotstrings
    
    if !g_Sequences.Has(seqName)
        return
    
    seq := g_Sequences[seqName]
    UnregisterSequenceTriggers(seqName)
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
    if seq.Has("hotstring") && seq["hotstring"] != "" {
        hs := seq["hotstring"]
        try {
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
    if seq.Has("hotkey") && seq["hotkey"] != "" {
        hk := seq["hotkey"]
        try {
            Hotkey(hk, "Off")
            g_SequenceHotkeys.Delete(hk)
        }
    }
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
SetSpeedDropdown(speed) {
    global SpeedDD
    speedOptions := ["0.25x", "0.5x", "0.75x", "1x", "1.5x", "2x", "3x"]
    speedValues := [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0]
    bestIdx := 4  ; Default to 1x
    for i, v in speedValues {
        if Abs(v - speed) < 0.01 {
            bestIdx := i
            break
        }
    }
    SpeedDD.Choose(bestIdx)
}
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
        UnregisterSequenceTriggers(name)
        
        g_Sequences.Delete(name)
        SeqLV.Delete(row)
        SaveSequences()
        RefreshHKDropdowns()
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
SimulateSequence(steps, speedMultiplier := 1.0) {
    global g_Settings, g_AbortSequence, g_Coordinates, g_Patterns, g_SimulationTooltipIndex

    g_AbortSequence := false
    try Hotkey("Escape", AbortSequenceHandler, "On")
    Loop 20
        ToolTip(, , , A_Index)

    g_SimulationTooltipIndex := 1

    enabled := []
    for s in steps
        if s.Has("enabled") && s["enabled"]
            enabled.Push(s)

    total := enabled.Length
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
        coords := GetStepCoordinates(s)
        tipText := "[" . i . "/" . total . "] " . s["action"]
        if s["target"] != "" && s["target"] != "(none)"
            tipText .= "`n→ " . s["target"]
        if s["param"] != ""
            tipText .= "`n  (" . s["param"] . ")"
        ShowSimulationTooltip(tipText, coords["x"], coords["y"], 3000)
        Sleep(adjustedDelay)
    }
    try Hotkey("Escape", "Off")

    ShowStatus("SIMULATION COMPLETE (" . total . " steps)", "ok")
    SetTimer(ClearAllSimTooltips, -3000)
}
ShowSimulationTooltip(text, x, y, duration := 3000) {
    global g_SimulationTooltipIndex
    tipIndex := g_SimulationTooltipIndex + 1
    if tipIndex > 20
        tipIndex := 2
    offsetX := Mod(g_SimulationTooltipIndex - 1, 5) * 10
    offsetY := (g_SimulationTooltipIndex - 1) * 18

    ToolTip(text, x + 15 + offsetX, y + 15 + offsetY, tipIndex)
    clearFunc := ClearSpecificTooltip.Bind(tipIndex)
    SetTimer(clearFunc, -duration)
    g_SimulationTooltipIndex++
    if g_SimulationTooltipIndex > 19
        g_SimulationTooltipIndex := 1
}
ClearSpecificTooltip(index) {
    ToolTip(, , , index)
}
ClearAllSimTooltips() {
    Loop 20
        ToolTip(, , , A_Index)
}
GetStepCoordinates(step) {
    global g_Coordinates, g_Patterns, g_Settings

    action := step["action"]
    target := step["target"]
    param := step["param"]
    x := A_ScreenWidth // 2
    y := A_ScreenHeight // 2
    try {
        if InStr(action, "Click") || action = "Drag" {
            if target != "" && target != "(none)" && g_Coordinates.Has(target) {
                c := g_Coordinates[target]
                x := c["x"]
                y := c["y"]
            } else if param != "" && InStr(param, ",") {
                if InStr(param, "->") {
                    startPart := Trim(SubStr(param, 1, InStr(param, "->") - 1))
                    p := StrSplit(startPart, ",")
                    if p.Length >= 2 && IsNumber(Trim(p[1])) && IsNumber(Trim(p[2])) {
                        x := Integer(Trim(p[1]))
                        y := Integer(Trim(p[2]))
                    }
                } else {
                    p := StrSplit(param, ",")
                    if p.Length >= 2 && IsNumber(Trim(p[1])) && IsNumber(Trim(p[2])) {
                        x := Integer(Trim(p[1]))
                        y := Integer(Trim(p[2]))
                    }
                }
            }
        } else if InStr(action, "Find &") || action = "Wait for Pattern" || action = "Wait Until Gone" {
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
            x := A_ScreenWidth // 2
            y := 100
        } else if action = "Key Chord" || action = "Send Keys" || action = "Type Text" {
            x := A_ScreenWidth // 2
            y := A_ScreenHeight // 2 + 50
        } else if InStr(action, "Revolver") || InStr(action, "Clipboard") {
            MouseGetPos(&x, &y)
        }
    }

    return Map("x", x, "y", y)
}

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
SubstituteWorkflowVariables(text) {
    global g_SpoolVariables, g_WordVariables, g_WorkflowVariables
    
    if !IsSet(g_WorkflowVariables)
        g_WorkflowVariables := Map()
    
    result := text
    for varName, value in g_WorkflowVariables {
        result := StrReplace(result, "$var." . varName, value)
    }
    if IsSet(g_WordVariables) {
        for wordName, value in g_WordVariables {
            result := StrReplace(result, "$word." . wordName, value)
        }
    }
    if IsSet(g_SpoolVariables) {
        for spoolName, value in g_SpoolVariables {
            result := StrReplace(result, "$spool." . spoolName, value)
        }
    }
    
    return result
}

SubstituteWorkflowVariables2(text) {
    global g_SpoolVariables, g_WordVariables, g_WatchWords

    if text = "" || !InStr(text, "$")
        return text
    if InStr(text, "$word.")
        UpdateAllWatchWords()
    while RegExMatch(text, "\$word\.(\w+)", &match) {
        varName := match[1]
        value := ""
        if g_WordVariables.Has("$word." . varName) {
            value := g_WordVariables["$word." . varName]
        } else if g_SpoolVariables.Has("$word." . varName) {
            value := g_SpoolVariables["$word." . varName]
        } else if g_WatchWords.Has(varName) {
            value := g_WatchWords[varName]["lastValue"]
        }

        text := StrReplace(text, match[0], value)
    }
    while RegExMatch(text, "\$var\.(\w+)", &match) {
        varName := match[1]
        value := ""

        if g_SpoolVariables.Has(varName) {
            value := g_SpoolVariables[varName]
        } else if g_SpoolVariables.Has("$" . varName) {
            value := g_SpoolVariables["$" . varName]
        }

        text := StrReplace(text, match[0], value)
    }
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
    g_AbortSequence := false
    try Hotkey("Escape", AbortSequenceHandler, "On")
    if g_StepThroughMode
        try Hotkey("Tab", StepThroughAdvance, "On")

    enabled := []
    for s in steps
        if s.Has("enabled") && s["enabled"]
            enabled.Push(s)
    total := enabled.Length
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
        
        ShowStatus("[" . i . "/" . total . "] " . s["action"] . " @ " . speedText . modeText, "wait")
        stepMuted := s.Has("notificationMuted") && s["notificationMuted"]
        if g_DebugMode && !stepMuted {
            stepInfo := "[" . i . "/" . total . "] " . s["action"]
            if s["target"] != ""
                stepInfo .= "`nTarget: " . s["target"]
            if s["param"] != ""
                stepInfo .= "`nParam: " . s["param"]
            ShowNotificationBasic("Executing", stepInfo, 0, "info", "", i)
        }
        global g_SkipNextAction
            if IsSet(g_SkipNextAction) && g_SkipNextAction {
                g_SkipNextAction := false  ; Reset for next step
                continue  ; Skip this action
            }
        success := ExecuteActionVerified(s["action"], s["target"], s["param"], s, speedMultiplier)
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
        if g_StepThroughMode && i < total {
            g_StepThroughWaiting := true
            g_StepThroughContinue := false
            
            ShowStatus("[WAITING] Press Tab for next step, ESC to abort", "info")
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
AbortSequenceHandler(*) {
    global g_AbortSequence
    g_AbortSequence := true
    ToolTip("ABORTING...")
}

ExecuteActionVerified(action, target, param, stepData := "", speedMultiplier := 1.0) {
    global g_Coordinates, g_Patterns, g_ExtractedData, g_Settings, g_AbortSequence
    global g_LastClickX, g_LastClickY, g_SpoolVariables, g_WordVariables

    if g_AbortSequence
        return false
    param := SubstituteWorkflowVariables(param)
    preDelay := Round(g_Settings["PreActionDelay"] / speedMultiplier)
    postDelay := Round(g_Settings["PostActionDelay"] / speedMultiplier)
    if IsObject(stepData) && stepData.Has("failsafe") {
        fs := stepData["failsafe"]
        if IsObject(fs) && (fs is Map) {
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
            if fs.Has("requirePattern") && fs["requirePattern"] && fs.Has("pattern") && fs["pattern"] != "" {
                if !CheckPatternQualifier(fs["pattern"]) {
                    ShowStatus("Failsafe: Pattern not found - " . fs["pattern"], "fail")
                    if fs.Has("abortOnFail") && fs["abortOnFail"] {
                        g_AbortSequence := true
                    }
                    return false
                }
            }
            if fs.Has("preDelay") && fs["preDelay"] > 0 {
                Sleep(fs["preDelay"])
            }
            if fs.Has("waitForIdle") && fs["waitForIdle"] {
                try WinWaitActive("A", , 2)
            }
        }
    }
    if IsObject(stepData) && stepData.Has("qualWindow") && stepData["qualWindow"] != "" {
        win := GetWindowUnderMouse()
        if !InStr(win["title"], stepData["qualWindow"]) {
            ShowStatus("Window mismatch: " . stepData["qualWindow"], "fail")
            return false
        }
    }
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
            } else if param != "" && InStr(param, ",") {
                p := StrSplit(param, ",")
                g_LastClickX := Integer(p[1])
                g_LastClickY := Integer(p[2])
                FlashClickPosition(Integer(p[1]), Integer(p[2]))
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
            return ExecuteHoverMouse(param)

        case "Grab OCR to Var":
            return ExecuteGrabOCRToVar(param)

        case "Use Var Paste":
            return ExecuteUseVarPaste(param)

        case "Show Notification":
            return ExecuteShowNotification(param)

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
            return ExecuteHoverMouse(param)
        
        case "Grab OCR to Var":
            return ExecuteGrabOCRToVar(param)
        
        case "Use Var Paste":
            return ExecuteUseVarPaste(param)
        
        case "Show Notification":
            return ExecuteShowNotification(param)

        case "Set Variable":
            global g_WorkflowVariables
            
            if !IsSet(g_WorkflowVariables)
                g_WorkflowVariables := Map()
            
            varName := Trim(target)
            value := Trim(param)
            
            if varName = "" {
                ShowStatus("Set Variable: No variable name specified", "fail")
                return false
            }
            
            g_WorkflowVariables[varName] := value
            ShowStatus("Variable set: `$var." . varName . " = " . value, "ok")
            return true
        
        case "Grab Clipboard":
            global g_WorkflowVariables
            
            if !IsSet(g_WorkflowVariables)
                g_WorkflowVariables := Map()
            
            varName := Trim(target)
            
            if varName = "" {
                ShowStatus("Grab Clipboard: No variable name specified", "fail")
                return false
            }
            
            clipContent := A_Clipboard
            g_WorkflowVariables[varName] := clipContent
            ShowStatus("Clipboard grabbed to `$var." . varName, "ok")
            return true
        
        case "If Contains":
            global g_WorkflowVariables, g_SkipNextAction
            
            if !IsSet(g_WorkflowVariables)
                g_WorkflowVariables := Map()
            
            if !IsSet(g_SkipNextAction)
                g_SkipNextAction := false
            
            varName := Trim(target)
            searchText := Trim(param)
            
            if varName = "" {
                ShowStatus("If Contains: No variable specified", "fail")
                return false
            }
            
            if !g_WorkflowVariables.Has(varName) {
                ShowStatus("If Contains: Variable `$var." . varName . " not found", "fail")
                g_SkipNextAction := true  ; Variable doesn't exist = condition false
                return true  ; Don't fail the workflow, just skip
            }
            
            varValue := g_WorkflowVariables[varName]
            
            if InStr(varValue, searchText) {
                ShowStatus("If Contains: MATCH - '" . searchText . "' found in `$var." . varName, "ok")
                g_SkipNextAction := false  ; Condition true = execute next
            } else {
                ShowStatus("If Contains: NO MATCH - '" . searchText . "' not in `$var." . varName, "info")
                g_SkipNextAction := true  ; Condition false = skip next
            }
            return true
        
        case "If Variable":
            global g_WorkflowVariables, g_SkipNextAction
            
            if !IsSet(g_WorkflowVariables)
                g_WorkflowVariables := Map()
            
            if !IsSet(g_SkipNextAction)
                g_SkipNextAction := false
            
            varName := Trim(target)
            
            if !g_WorkflowVariables.Has(varName) {
                ShowStatus("If Variable: Variable `$var." . varName . " not found", "fail")
                g_SkipNextAction := true
                return true
            }
            
            varValue := g_WorkflowVariables[varName]
            parts := StrSplit(param, ",", " ", 2)
            if parts.Length < 2 {
                ShowStatus("If Variable: Invalid format - use operator,value", "fail")
                return false
            }
            
            operator := Trim(parts[1])
            compareValue := Trim(parts[2])
            isNumeric := false
            if IsNumber(varValue) && IsNumber(compareValue) {
                varValue := Number(varValue)
                compareValue := Number(compareValue)
                isNumeric := true
            }
            
            result := false
            switch operator {
                case "=", "==":
                    result := (varValue = compareValue)
                case "!=", "<>":
                    result := (varValue != compareValue)
                case ">":
                    result := isNumeric ? (varValue > compareValue) : false
                case "<":
                    result := isNumeric ? (varValue < compareValue) : false
                case ">=":
                    result := isNumeric ? (varValue >= compareValue) : false
                case "<=":
                    result := isNumeric ? (varValue <= compareValue) : false
                default:
                    ShowStatus("If Variable: Unknown operator '" . operator . "'", "fail")
                    return false
            }
            
            if result {
                ShowStatus("If Variable: TRUE - `$var." . varName . " " . operator . " " . compareValue, "ok")
                g_SkipNextAction := false
            } else {
                ShowStatus("If Variable: FALSE - `$var." . varName . " " . operator . " " . compareValue, "info")
                g_SkipNextAction := true
            }
            return true
        
        case "Stop Execution":
            global g_AbortSequence
            g_AbortSequence := true
            ShowStatus("Workflow stopped by Stop Execution", "info")
            return true
        
        case "Run Sequence":
            global g_Sequences
            
            seqName := Trim(param)
            
            if seqName = "" {
                ShowStatus("Run Sequence: No sequence name specified", "fail")
                return false
            }
            
            if !g_Sequences.Has(seqName) {
                ShowStatus("Run Sequence: Workflow '" . seqName . "' not found", "fail")
                return false
            }
            
            ShowStatus("Running sequence: " . seqName, "progress")
            seq := g_Sequences[seqName]
            for step in seq["steps"] {
                if g_AbortSequence
                    break
                
                success := ExecuteActionVerified(step["action"], step["target"], step["param"], step, 1.0)
                if !success && seq.Has("abortOnFail") && seq["abortOnFail"]
                    break
            }
            
            return true
        
        case "Format Clipboard":
            clipContent := A_Clipboard
            
            template := Trim(param)
            result := ""
            switch template {
                case "invoice":
                    result := "INV-" . clipContent
                case "receipt":
                    result := "RCP-" . clipContent
                case "uppercase":
                    result := StrUpper(clipContent)
                case "lowercase":
                    result := StrLower(clipContent)
                case "titlecase":
                    result := StrTitle(clipContent)
                case "trim":
                    result := Trim(clipContent)
                case "date_iso":
                    result := FormatTime(, "yyyy-MM-dd")
                default:
                    result := StrReplace(template, "{clip}", clipContent)
                    result := SubstituteWorkflowVariables(result)
            }
            
            A_Clipboard := result
            ShowStatus("Clipboard formatted: " . template, "ok")
            return true
        
        case "Append to Clipboard":
            A_Clipboard := A_Clipboard . param
            ShowStatus("Appended to clipboard", "ok")
            return true
        
        case "Prepend to Clipboard":
            A_Clipboard := param . A_Clipboard
            ShowStatus("Prepended to clipboard", "ok")
            return true
        
        case "Extract from Clipboard":
            clipContent := A_Clipboard
            pattern := Trim(param)
            
            if InStr(pattern, "between:") = 1 {
                parts := StrSplit(SubStr(pattern, 9), "|")
                if parts.Length >= 2 {
                    startDelim := parts[1]
                    endDelim := parts[2]
                    
                    startPos := InStr(clipContent, startDelim)
                    if startPos {
                        startPos += StrLen(startDelim)
                        endPos := InStr(clipContent, endDelim, , startPos)
                        if endPos {
                            A_Clipboard := SubStr(clipContent, startPos, endPos - startPos)
                            ShowStatus("Extracted between delimiters", "ok")
                            return true
                        }
                    }
                }
            } else if InStr(pattern, "field:") = 1 {
                parts := StrSplit(SubStr(pattern, 7), "|")
                if parts.Length >= 2 {
                    delimiter := parts[1]
                    index := Integer(parts[2])
                    
                    fields := StrSplit(clipContent, delimiter)
                    if index > 0 && index <= fields.Length {
                        A_Clipboard := Trim(fields[index])
                        ShowStatus("Extracted field " . index, "ok")
                        return true
                    }
                }
            } else if InStr(pattern, "regex:") = 1 {
                regexPattern := SubStr(pattern, 7)
                if RegExMatch(clipContent, regexPattern, &match) {
                    A_Clipboard := match[0]
                    ShowStatus("Extracted via regex", "ok")
                    return true
                }
            }
            
            ShowStatus("Extract from Clipboard: Pattern not matched", "fail")
            return false
    }

    return false
}
ExecuteOCRRegion(target, param) {
    global g_LastOCRText, g_LastOCRRegion, g_SpoolVariables, g_WordVariables, g_OCRSettings
    region := ParseRegionCoords(target)
    if !region {
        ShowActionNotification("OCR Region", "error", 
            "Invalid region coordinates", 
            "Could not parse region from target: " . target . "`n`nExpected format: x,y,width,height`nExample: 100,100,400,200")
        return false
    }
    g_LastOCRRegion := region
    if !IsOCRAvailable() {
        return ReportOCRError("Extract", region, "OCR.ahk library not found or not loaded. Ensure OCR.ahk is in the script directory.")
    }
    text := ""
    try {
        ocrResult := OCR.FromRect(region["x1"], region["y1"],
                                  region["x2"] - region["x1"],
                                  region["y2"] - region["y1"],
                                  g_OCRSettings["language"])
        text := ocrResult.Text
    } catch as e {
        return ReportOCRError("Extract", region, e.Message)
    }

    if text = "" {
        return ReportOCRError("Extract", region, "No text detected in specified region. Text may be too small, obscured, or region may be incorrect.")
    }
    g_LastOCRText := text
    param := Trim(param)

    if param = "" || param = "copy" {
        A_Clipboard := text
        ShowStatus("OCR: Copied " . StrLen(text) . " chars to clipboard", "ok")
        return true
    }

    if SubStr(param, 1, 4) = "var:" {
        varName := SubStr(param, 5)
        g_SpoolVariables[varName] := text
        g_WordVariables["$var." . varName] := text
        ShowActionNotification("OCR Region", "success", 
            "Extracted " . StrLen(text) . " characters`nStored in variable: $var." . varName . "`n`nPreview: " . SubStr(text, 1, 50) . (StrLen(text) > 50 ? "..." : ""))
        try RefreshOCRVarsLV()
        return true
    }

    if SubStr(param, 1, 6) = "split:" {
        splitParam := SubStr(param, 7)
        LoadOCRRevolver(splitParam)
        return true
    }

    if SubStr(param, 1, 6) = "regex:" {
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
    A_Clipboard := text
    ShowStatus("OCR captured: " . SubStr(text, 1, 30) . "...", "ok")
    return true
}
ExecuteOCRClick(target, param) {
    global g_OCRSettings
    region := ParseRegionCoords(target)
    if !region {
        region := Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)
    }
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
                                  g_OCRSettings["language"])
                                  errorMsg .= "Region: "
        . region.Get("x", "?") ","
        . region.Get("y", "?") ","
        . region.Get("w", "?") ","
        . region.Get("h", "?") "`n"
        for word in ocrResult.Words {
            if InStr(word.Text, searchText) || InStr(searchText, word.Text) {
                clickX := region["x1"] + word.x + (word.w // 2)
                clickY := region["y1"] + word.y + (word.h // 2)
                HighlightRegion(clickX - 5, clickY - 5, 10, 10, 500, "match", searchText)

                Click(clickX, clickY)
                ShowActionNotification("OCR Click", "success", "Clicked on '" . searchText . "' at " . clickX . "," . clickY)
                return true
            }
        }
        for line in ocrResult.Lines {
            if InStr(line.Text, searchText) {
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
ExecuteOCRWait(target, param) {
    global g_OCRSettings, g_AbortSequence
    region := ParseRegionCoords(target)
    if !region {
        region := Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)
    }
    timeout := 5000
    searchText := ""

    param := Trim(param)
    if SubStr(param, 1, 5) = "text:" {
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
                if ocrResult.Text != "" {
                    ShowStatus("OCR Wait: Text detected", "ok")
                    return true
                }
            } else {
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
LoadOCRRevolver(param) {
    global g_LastOCRText, g_OCRRevolver, g_OCRRevolverIndex

    if g_LastOCRText = "" {
        ShowStatus("No OCR text to load", "fail")
        return false
    }

    text := g_LastOCRText
    param := Trim(param)
    parts := []
    if param = "tab" {
        parts := StrSplit(text, "`t")
    } else if param = "line" || param = "lines" {
        parts := StrSplit(text, "`n")
    } else if IsNumber(param) {
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
        parts := StrSplit(text, param)
    } else {
        parts := StrSplit(text, " ")
    }
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
FireOCRRevolver() {
    global g_OCRRevolver, g_OCRRevolverIndex

    if g_OCRRevolver.Length = 0 {
        ShowStatus("OCR Revolver empty", "fail")
        return false
    }
    g_OCRRevolverIndex++
    if g_OCRRevolverIndex > g_OCRRevolver.Length
        g_OCRRevolverIndex := 1

    text := g_OCRRevolver[g_OCRRevolverIndex]
    A_Clipboard := text
    Sleep(50)
    Send("^v")

    remaining := g_OCRRevolver.Length - g_OCRRevolverIndex
    ShowStatus("OCR Revolver " . g_OCRRevolverIndex . "/" . g_OCRRevolver.Length . ": " . SubStr(text, 1, 20), "ok")

    return true
}
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
    if target = "" || target = "full" || target = "screen" {
        return Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)
    }
    if target = "current" || target = "last" {
        global g_LastOCRRegion
        if IsSet(g_LastOCRRegion) && g_LastOCRRegion.Count > 0
            return g_LastOCRRegion
        return Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)
    }
    parts := StrSplit(target, ",")
    if parts.Length >= 4 {
        try {
            x1 := Integer(Trim(parts[1]))
            y1 := Integer(Trim(parts[2]))
            x2 := Integer(Trim(parts[3]))
            y2 := Integer(Trim(parts[4]))
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
; RefreshTriggersLV() {
;     global g_Triggers, TriggersLV
;     TriggersLV.Delete()
;     for n, t in g_Triggers
;         TriggersLV.Add(, n, t["type"], t["pattern"])
; }

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
    errorMsg .= "Region: " . (IsObject(region) ? region["x"] "," region["y"] "," region["w"] "," region["h"] : region) . "`n"
    
    reasons := []
    
    if !IsOCRAvailable()
        reasons.Push("OCR.ahk library not found or not loaded")
    
    if IsObject(region) {
        if !region.Has("w") || !region.Has("h") || region["w"] <= 0 || region["h"] <= 0
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
    
    global g_LastActionError := errorMsg
    return false
}
IsOCRAvailable() {
    if IsSet(OCR) && IsFunc(OCR)
        return true
    return IsSet(OCR)
    
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
    if timeout = 0 && !g_NotificationDismissible
        timeout := g_NotificationTimeout
    notifGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "Notification")
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
    statusIcon := "⬤"
    if status = "success"
        statusIcon := "✓"
    else if status = "error"
        statusIcon := "✗"
    else if status = "warning"
        statusIcon := "⚠"
    notifGui.SetFont("s10 cWhite Bold", "Segoe UI")
    topBar := notifGui.Add("Text", "x0 y0 w320 h30 Background" . topBarColor . " Center", "")
    titleCtrl := notifGui.Add("Text", "x10 y7 w250 cWhite Background" . topBarColor, statusIcon . " " . title)
    if stepIndex > 0 {
        notifGui.SetFont("s9 Bold", "Segoe UI")
        muteBtn := notifGui.Add("Text", "x270 y5 w40 h20 cWhite Background" . topBarColor . " Center Border", "🔔")
        muteBtn.stepIndex := stepIndex
        muteBtn.notifGui := notifGui
        if stepIndex <= g_CurrentSequenceSteps.Length {
            step := g_CurrentSequenceSteps[stepIndex]
            if step.Has("notificationMuted") && step["notificationMuted"] {
                muteBtn.Text := "🔕"
            }
        }
        
        muteBtn.OnEvent("Click", ToggleStepNotification)
    }
    notifGui.SetFont("s9 cWhite Norm", "Segoe UI")
    messageLines := StrSplit(message, "`n")
    messageHeight := Min(messageLines.Length * 18, 200)  ; Max 200px height
    msgCtrl := notifGui.Add("Edit", "x10 y35 w300 h" . messageHeight . " cWhite Background" . bgColor . " ReadOnly -E0x200 Multi", message)
    
    yPos := 35 + messageHeight + 5
    if copyData != "" {
        notifGui.SetFont("s8", "Segoe UI")
        copyBtn := notifGui.Add("Button", "x10 y" . yPos . " w80 h22", "📋 Copy")
        copyBtn.OnEvent("Click", (*) => CopyNotificationData(copyData))
        yPos += 27
    }
    notifGui.SetFont("s8 c808080", "Segoe UI")
    dismissCtrl := notifGui.Add("Text", "x10 y" . yPos . " w300 Background" . bgColor, "Drag top bar to move | Right-click to dismiss")
    topBar.OnEvent("Click", (*) => PostMessage(0xA1, 2, 0, , notifGui.Hwnd))
    titleCtrl.OnEvent("Click", (*) => PostMessage(0xA1, 2, 0, , notifGui.Hwnd))
    for ctrl in notifGui {
        try ctrl.OnEvent("DoubleClick", (*) => RemoveNotification(notifGui))
        try ctrl.OnEvent("ContextMenu", (*) => RemoveNotification(notifGui))
    }
    
    notifGui.OnEvent("Close", (*) => RemoveNotification(notifGui))
    g_NotificationStack.Push(notifGui)
    RepositionNotifications()
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
    if step.Has("notificationMuted") && step["notificationMuted"] {
        step["notificationMuted"] := false
        ctrl.Text := "🔔"
        ShowStatus("Step " . stepIndex . " notifications enabled", "ok")
    } else {
        step["notificationMuted"] := true
        ctrl.Text := "🔕"
        ShowStatus("Step " . stepIndex . " notifications muted", "ok")
    }
    try ctrl.notifGui.Destroy()
}

CopyNotificationData(data) {
    A_Clipboard := data
    ShowStatus("Copied to clipboard: " . SubStr(data, 1, 50) . (StrLen(data) > 50 ? "..." : ""), "ok")
}

RemoveNotification(notifGui) {
    global g_NotificationStack
    
    try {
        if !notifGui
            return
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
    i := g_NotificationStack.Length
    while i >= 1 {
        try {
            notifGui := g_NotificationStack[i]
            notifGui.GetPos(,, &actualW, &actualH)
            guiH := actualH > 0 ? actualH : 180
            
            xPos := screenW - guiW - 20
            currentY -= guiH
            if currentY < 10 {
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
global g_NotificationGui := ""

StartNotificationTimer() {
    LoadNotificationSchedule()
    SetTimer(CheckScheduledNotifications, 60000)
}

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
GetSequenceVariables() {
    global g_CurrentSequenceSteps
    
    vars := []
    varSet := Map()  ; Use map to avoid duplicates
    
    for step in g_CurrentSequenceSteps {
        action := step["action"]
        param := step.Has("param") ? step["param"] : ""
        if action = "OCR Region" && InStr(param, "var:") {
            varName := Trim(SubStr(param, InStr(param, "var:") + 4))
            if InStr(varName, " ")
                varName := SubStr(varName, 1, InStr(varName, " ") - 1)
            if InStr(varName, ",")
                varName := SubStr(varName, 1, InStr(varName, ",") - 1)
            if varName != "" && !varSet.Has(varName) {
                vars.Push(varName)
                varSet[varName] := true
            }
        }
        if action = "Grab OCR to Var" && InStr(param, ",") {
            parts := StrSplit(param, ",")
            if parts.Length >= 1 {
                varName := Trim(parts[1])
                if SubStr(varName, 1, 1) = "$"
                    varName := SubStr(varName, 2)
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

InitializeParameterValidators() {
    global g_ParamValidators, g_ParamHints
    
    g_ParamHints["Click"] := "1-10 for click count"
    g_ParamHints["OCR Region"] := "var:name to create variable | copy for clipboard | Check Choices for existing vars"
    g_ParamHints["OCR Click"] := "Text to find and click"
    g_ParamHints["Set Clipboard"] := "Text or $var.name | Check Choices dropdown for available variables!"
    g_ParamHints["Wait"] := "Milliseconds (1000 = 1 second)"
    g_ParamHints["Grab OCR to Var"] := "variableName,x,y,width,height | Check Choices for existing vars"
    g_ParamHints["Use Var Paste"] := "Text with $var.name | Check Choices dropdown for variables!"
    g_ParamHints["Send Keys"] := "^c={Ctrl+C}, +a={Shift+A}, !f={Alt+F}"
    g_ParamHints["Show Notification"] := "Title,Message,Timeout | Use $var.name for variables"
}

ValidateStepParameters(action, target, param) {
    errors := []
    
    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click":
            if target = ""
                errors.Push("TARGET required: coordinate name or x,y")
        
        case "OCR Region":
            if target = ""
                errors.Push("TARGET required: x,y,width,height region")
            else if InStr(target, ",") {
                parts := StrSplit(target, ",")
                if parts.Length != 4
                    errors.Push("TARGET must be x,y,width,height (4 values)")
            }
        
        case "Wait":
            if param = ""
                errors.Push("PARAM required: duration in milliseconds")
            else {
                duration := Integer(param)
                if duration < 0
                    errors.Push("PARAM must be positive number")
                if duration > 300000
                    errors.Push("PARAM > 5 minutes - are you sure?")
            }
        
        case "Send Keys":
            if param = ""
                errors.Push("PARAM required: keys to send")
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

InitializeActionTemplates() {
    global g_ActionTemplates
    
    g_ActionTemplates["OCR → Variable → Clipboard"] := [
        Map("action", "OCR Region", "target", "100,100,1000,1000", "param", "var:ocrText", "pattern", "", "window", ""),
        Map("action", "Set Clipboard", "target", "", "param", "$var.ocrText", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "OCR Complete,Text copied to clipboard", "pattern", "", "window", "")
    ]
    
    g_ActionTemplates["Grab OCR → Variable → Notification"] := [
        Map("action", "Grab OCR to Var", "target", "", "param", "capturedText,100,100,500,500", "pattern", "", "window", ""),
        Map("action", "Set Clipboard", "target", "", "param", "$capturedText", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "OCR Captured,$var.capturedText", "pattern", "", "window", "")
    ]
    
    g_ActionTemplates["Pattern Click with Retry"] := [
        Map("action", "Wait for Pattern", "target", "MyPattern", "param", "5000", "pattern", "", "window", ""),
        Map("action", "Find & Click", "target", "MyPattern", "param", "", "pattern", "", "window", ""),
        Map("action", "Wait", "target", "", "param", "500", "pattern", "", "window", "")
    ]
    
    g_ActionTemplates["Data Entry (OCR + Type)"] := [
        Map("action", "Click", "target", "FieldStart", "param", "1", "pattern", "", "window", ""),
        Map("action", "Grab OCR to Var", "target", "", "param", "fieldValue,100,100,500,200", "pattern", "", "window", ""),
        Map("action", "Use Var Paste", "target", "", "param", "$fieldValue", "pattern", "", "window", ""),
        Map("action", "Send Keys", "target", "", "param", "{Tab}", "pattern", "", "window", "")
    ]
    
    g_ActionTemplates["Debug Step-by-Step"] := [
        Map("action", "Show Notification", "target", "", "param", "Debug,Starting workflow...", "pattern", "", "window", ""),
        Map("action", "Wait", "target", "", "param", "1000", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "Debug,Step 1 complete", "pattern", "", "window", "")
    ]
}

ShowTemplateLibrary2(*) {
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
ShowTemplateLibrary(*) {
    global MainGui
    
    TemplateGui := Gui("+Owner" . MainGui.Hwnd, "Workflow Template Library")
    TemplateGui.SetFont("s9", "Segoe UI")
    
    TemplateGui.Add("Text", "x10 y10", "Select a template to import:")
    
    templates := [
        "OCR_Conditional_Template|OCR-based IF-ELSE workflow",
        "Clipboard_Formatter|Format clipboard with prefix/suffix",
        "Variable_Demo|Set and use variables",
        "Simple_Notification|Basic notification example"
    ]
    
    templateLV := TemplateGui.Add("ListView", "x10 y30 w500 h200", ["Template", "Description"])
    templateLV.ModifyCol(1, 200)
    templateLV.ModifyCol(2, 280)
    
    for template in templates {
        parts := StrSplit(template, "|")
        templateLV.Add(, parts[1], parts[2])
    }
    
    TemplateGui.Add("Button", "x10 y240 w100 h25", "Import").OnEvent("Click", ImportTemplate.Bind(templateLV, TemplateGui))
    TemplateGui.Add("Button", "x120 y240 w100 h25", "View Code").OnEvent("Click", ViewTemplateCode.Bind(templateLV))
    TemplateGui.Add("Button", "x410 y240 w100 h25", "Close").OnEvent("Click", (*) => TemplateGui.Destroy())
    
    TemplateGui.Show()
}

ImportTemplate(lv, gui, *) {
    if lv.GetNext() = 0 {
        MsgBox("Please select a template first!", "No Selection", 48)
        return
    }
    
    templateName := lv.GetText(lv.GetNext(), 1)
    mawContent := GetTemplateContent(templateName)
    
    if mawContent = "" {
        MsgBox("Template not found!", "Error", 16)
        return
    }
    tempFile := A_Temp . "\" . templateName . ".maw"
    FileDelete(tempFile)
    FileAppend(mawContent, tempFile, "UTF-8")
    
    gui.Destroy()
    MsgBox("Template will be imported. Click OK to select the temporary file.", "Import Template", 64)
    ImportWorkflow()
}

GetTemplateContent(templateName) {
    
    switch templateName {
        case "OCR_Conditional_Template":
            return "[WORKFLOW]`nname=OCR_Conditional_Template`ndescription=Template for OCR-based conditional workflows`n`n[STEPS]`n1|Grab OCR to Var||variable,100,50,400,150|`n2|If Contains|variable|KEYWORD1|`n3|Show Notification||Found KEYWORD1,2|`n4|Stop Execution|||`n5|If Contains|variable|KEYWORD2|`n6|Show Notification||Found KEYWORD2,2|`n7|Stop Execution|||`n8|Show Notification||No match,3|`n`n[END]"
        
        case "Clipboard_Formatter":
            return "[WORKFLOW]`nname=Clipboard_Formatter`ndescription=Format clipboard with prefix`nhotkey=^+f`n`n[STEPS]`n1|Grab Clipboard|clipData||`n2|Prepend to Clipboard||DOC-|`n3|Show Notification||Formatted,2|`n`n[END]"
        
        default:
            return ""
    }
}


GetTemplateDescription(name) {
    descriptions := Map()
    descriptions["OCR → Variable → Clipboard"] := "Capture text via OCR, store in variable, copy to clipboard"
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
        newStep := Map()
        for key, value in step {
            newStep[key] := value
        }
        if !newStep.Has("enabled")
            newStep["enabled"] := true
        
        g_CurrentSequenceSteps.Push(newStep)
    }
    
    RefreshStepsLV()
    ShowNotificationBasic("Template Inserted", steps.Length . " steps added from '" . templateName . "' template", 3000, "success")
}

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
    if g_TriggerMonitorTimer
        SetTimer(g_TriggerMonitorTimer, 0)
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
CheckTriggers() {
    global g_NotificationTriggers
    
    currentTime := A_Now
    currentTimeFormatted := FormatTime(currentTime, "HH:mm")
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
        switch trigger["type"] {
            case "Time-Based":
                ProcessTimeTrigger(trigger, currentTime, currentTimeFormatted)
            
            case "Window Activation":
                ProcessWindowTrigger(trigger, activeTitle, activeProcess)
        }
    }
}
ProcessWindowTrigger(trigger, activeTitle, activeProcess) {
    condition := trigger["condition"]
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
    titleMatches := false
    if windowMatch != "" {
        for title in StrSplit(windowMatch, "|") {
            if InStr(activeTitle, title) {
                titleMatches := true
                break
            }
        }
    }
    processMatches := true
    if processMatch != "" && activeProcess != "" {
        processMatches := InStr(activeProcess, processMatch)
    }
    if titleMatches && processMatches {
        lastWindow := trigger.Has("lastWindow") ? trigger["lastWindow"] : ""
        
        if lastWindow != activeTitle {
            ExecuteTriggerAction(trigger)
            trigger["lastFired"] := A_Now
            trigger["lastWindow"] := activeTitle
            trigger["fireCount"] := trigger["fireCount"] + 1
            SaveNotificationTriggers()
            RefreshTriggersLV()
        }
    } else {
        if trigger.Has("lastWindow")
            trigger["lastWindow"] := ""
    }
}
ProcessTimeTrigger(trigger, currentTime, currentTimeFormatted) {
    condition := trigger["condition"]
    if InStr(condition, "time:") {
        targetTime := SubStr(condition, 6)
        
        if currentTimeFormatted = targetTime {
            lastFired := trigger["lastFired"]
            if lastFired != "" {
                lastFiredDate := FormatTime(lastFired, "yyyy-MM-dd")
                currentDate := FormatTime(currentTime, "yyyy-MM-dd")
                
                if lastFiredDate = currentDate
                    return  ; Already fired today
            }
            ExecuteTriggerAction(trigger)
            trigger["lastFired"] := currentTime
            trigger["fireCount"] := trigger["fireCount"] + 1
            SaveNotificationTriggers()
            RefreshTriggersLV()
        }
    }
    else if InStr(condition, "interval:") {
        intervalStr := SubStr(condition, 10)
        if InStr(intervalStr, "s") {
            intervalSeconds := Integer(StrReplace(intervalStr, "s", ""))
        } else if InStr(intervalStr, "m") {
            intervalSeconds := Integer(StrReplace(intervalStr, "m", "")) * 60
        } else if InStr(intervalStr, "h") {
            intervalSeconds := Integer(StrReplace(intervalStr, "h", "")) * 3600
        } else {
            intervalSeconds := Integer(intervalStr)
        }
        lastFired := trigger["lastFired"]
        if lastFired = "" {
            ExecuteTriggerAction(trigger)
            trigger["lastFired"] := currentTime
            trigger["fireCount"] := trigger["fireCount"] + 1
            SaveNotificationTriggers()
            RefreshTriggersLV()
        } else {
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
ExecuteTriggerAction2(trigger) {
    action := trigger["action"]
    params := trigger["params"]
    
    switch action {
        case "Show Notification":
            parts := StrSplit(params, ",", , 3)
            title := parts.Length >= 1 ? parts[1] : "Trigger Notification"
            message := parts.Length >= 2 ? parts[2] : "Trigger fired"
            timeout := parts.Length >= 3 ? Integer(parts[3]) : 5000
            
            ShowNotificationBasic(title, message, timeout, "info")
            
        case "Run Sequence":
            if g_Sequences.Has(params) {
                ExecuteSequenceByHotkey(params)
            } else {
                ShowNotificationBasic("Trigger Error", "Sequence '" . params . "' not found", 3000, "error")
            }
            
        case "Play Sound":
            try {
                if FileExist(params) {
                    SoundPlay(params)
                } else {
                    soundParts := StrSplit(params, ",")
                    freq := soundParts.Length >= 1 ? Integer(soundParts[1]) : 800
                    duration := soundParts.Length >= 2 ? Integer(soundParts[2]) : 200
                    SoundBeep(freq, duration)
                }
            }
            
        case "Write to Log":
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
    templateGui := Gui("+AlwaysOnTop", "Trigger Templates")
    templateGui.SetFont("s9", "Segoe UI")
    templateTabs := templateGui.Add("Tab3", "x10 y10 w780 h580", ["Time-Based", "Window/App", "Combinations", "Settings"])
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

ShutdownGdip(ExitReason, ExitCode) {
    global g_GdipToken
    if g_GdipToken
        Gdip_Shutdown(g_GdipToken)
    return 0
}
CapturePatternScreenshot(patternName, x := "", y := "") {
    global SCREENSHOTS_DIR
    if x = "" || y = "" {
        MouseGetPos(&x, &y)
    }
    regionX := x - 50
    regionY := y - 50
    regionW := 100
    regionH := 100
    pBitmap := Gdip_BitmapFromScreen(regionX "|" regionY "|" regionW "|" regionH)

    if !pBitmap {
        ShowStatus("Screenshot capture failed", "fail")
        return ""
    }
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

ExportWorkflow(*) {
    global g_CurrentSequence, g_CurrentSequenceSteps, g_Sequences
    
    if g_CurrentSequence = "" {
        MsgBox("No workflow selected to export!", "Export Workflow", 48)
        return
    }
    seq := g_Sequences[g_CurrentSequence]
    selectedFile := FileSelect("S", g_CurrentSequence . ".maw", "Export Workflow", "Workflow Files (*.maw)")
    if selectedFile = ""
        return
    if !InStr(selectedFile, ".maw")
        selectedFile .= ".maw"
    output := "[WORKFLOW]`n"
    output .= "name=" . g_CurrentSequence . "`n"
    
    if seq.Has("description")
        output .= "description=" . seq["description"] . "`n"
    
    if seq.Has("hotkey") && seq["hotkey"] != ""
        output .= "hotkey=" . seq["hotkey"] . "`n"
    
    if seq.Has("abortOnFail")
        output .= "abortOnFail=" . (seq["abortOnFail"] ? "true" : "false") . "`n"
    
    output .= "`n[STEPS]`n"
    stepNum := 1
    for step in g_CurrentSequenceSteps {
        output .= stepNum . "|"
        output .= step["action"] . "|"
        output .= step["target"] . "|"
        output .= step["param"] . "|"
        if IsObject(step["failsafe"]) && step["failsafe"] is Map {
            output .= "enabled"
        }
        
        output .= "`n"
        stepNum++
    }
    
    output .= "`n[END]"
    try {
        FileDelete(selectedFile)
        FileAppend(output, selectedFile, "UTF-8")
        MsgBox("Workflow exported successfully!`n`nFile: " . selectedFile, "Export Complete", 64)
    } catch as err {
        MsgBox("Failed to export workflow!`n`nError: " . err.Message, "Export Failed", 16)
    }
}
ImportWorkflow(*) {
    global g_Sequences, g_CurrentSequence, g_CurrentSequenceSteps, SeqLV
    selectedFile := FileSelect(, , "Import Workflow", "Workflow Files (*.maw)")
    if selectedFile = ""
        return
    try {
        content := FileRead(selectedFile, "UTF-8")
    } catch as err {
        MsgBox("Failed to read file!`n`nError: " . err.Message, "Import Failed", 16)
        return
    }
    lines := StrSplit(content, "`n", "`r")
    
    section := ""
    workflowName := ""
    workflowDesc := ""
    workflowHotkey := ""
    workflowAbortOnFail := false
    steps := []
    
    for line in lines {
        line := Trim(line)
        
        if line = "" || InStr(line, ";") = 1  ; Skip empty lines and comments
            continue
        if line = "[WORKFLOW]" {
            section := "workflow"
            continue
        } else if line = "[STEPS]" {
            section := "steps"
            continue
        } else if line = "[END]" {
            break
        }
        if section = "workflow" {
            if InStr(line, "name=") = 1 {
                workflowName := SubStr(line, 6)
            } else if InStr(line, "description=") = 1 {
                workflowDesc := SubStr(line, 13)
            } else if InStr(line, "hotkey=") = 1 {
                workflowHotkey := SubStr(line, 8)
            } else if InStr(line, "abortOnFail=") = 1 {
                workflowAbortOnFail := (SubStr(line, 13) = "true")
            }
        } else if section = "steps" {
            parts := StrSplit(line, "|")
            
            if parts.Length >= 4 {
                step := Map(
                    "action", parts[2],
                    "target", parts[3],
                    "param", parts[4],
                    "failsafe", Map()
                )
                
                steps.Push(step)
            }
        }
    }
    if workflowName = "" {
        MsgBox("Invalid .maw file: No workflow name found!", "Import Failed", 48)
        return
    }
    
    if steps.Length = 0 {
        MsgBox("Invalid .maw file: No steps found!", "Import Failed", 48)
        return
    }
    if g_Sequences.Has(workflowName) {
        result := MsgBox("Workflow '" . workflowName . "' already exists!`n`nOverwrite?", "Workflow Exists", 4+32)
        if result = "No"
            return
    }
    g_Sequences[workflowName] := Map(
        "name", workflowName,
        "description", workflowDesc,
        "hotkey", workflowHotkey,
        "abortOnFail", workflowAbortOnFail,
        "steps", steps
    )
    g_CurrentSequence := workflowName
    g_CurrentSequenceSteps := steps
    RefreshSeqLV()
    RefreshWorkflowSteps()
    SaveSequences()
    
    MsgBox("Workflow imported successfully!`n`nName: " . workflowName . "`nSteps: " . steps.Length, "Import Complete", 64)
}
RefreshWorkflowSteps() {
    global StepsLV, g_CurrentSequenceSteps
    
    StepsLV.Delete()
    
    for step in g_CurrentSequenceSteps {
        failsafeText := ""
        if IsObject(step["failsafe"]) && step["failsafe"] is Map && step["failsafe"].Count > 0
            failsafeText := "✓"
        
        StepsLV.Add(, "", step["action"], step["target"], step["param"], failsafeText)
    }
    Loop StepsLV.GetCount() {
        StepsLV.Modify(A_Index, "Col1", A_Index)
    }
}



MainGui := Gui("+Resize +MinSize850x680", "Macro Automator v5.0 Enhanced")
MainGui.SetFont("s9", "Segoe UI")
MainGui.OnEvent("Close", (*) => (MainGui.Hide(), g_GuiVisible := false))
MainGui.OnEvent("Size", GuiResize)
OnTopCheck := MainGui.Add("CheckBox", "x10 y5 vOnTop", "On Top")
OnTopCheck.OnEvent("Click", ToggleOnTop)
DefModeIndicator := MainGui.Add("Text", "x80 y5 w160 h18 Center Border cGray", "Definition Mode OFF")

MousePosText := MainGui.Add("Text", "x250 y6 w80", "")
LiveCheck := MainGui.Add("CheckBox", "x335 y5", "Live")
LiveCheck.OnEvent("Click", (c,*) => SetTimer(UpdateMousePos, c.Value ? 100 : 0))

MainGui.Add("Button", "x400 y2 w50 h20 cRed", "ABORT").OnEvent("Click", AbortSequence)

TabCtrl := MainGui.Add("Tab3", "x5 y28 w890 h600 vTabs", ["Workflow", "Patterns", "Live OCR", "Spools", "Analytics", "Clipboard", "Hotkeys", "Hotstrings", "Triggers", "Settings", "Notepad"])
TabCtrl.UseTab(1)
MainGui.Add("GroupBox", "x15 y50 w860 h35", "Quick Capture (CAPSLOCK ON)")
MainGui.Add("Text", "x25 y63 w840 cBlue", "C=Click  D=Drag  R=RightClick  T=Triple  P=Pattern  ESC=Cancel")
MainGui.Add("Text", "x15 y90", "Name:")
CoordNameEdit := MainGui.Add("Edit", "x55 yp-3 w100 vCoordName")
MainGui.Add("Button", "x160 yp w50 h22", "Click").OnEvent("Click", StartClickCapture)
MainGui.Add("Button", "x215 yp w50 h22", "Drag").OnEvent("Click", StartDragCapture)
MainGui.Add("Button", "x270 yp w50 h22", "Arrow").OnEvent("Click", StartArrowCapture)
MainGui.Add("Button", "x325 yp w45 h22", "Rel.").OnEvent("Click", StartRelativeCapture)
MainGui.Add("Text", "x15 y115", "Saved Coordinates:")
CoordLV := MainGui.Add("ListView", "x15 y130 w350 h60 Grid NoSortHdr vCoordLV", ["Name", "X", "Y", "EndX", "EndY", "Type"])
CoordLV.ModifyCol(1, 90)
CoordLV.ModifyCol(2, 45)
CoordLV.ModifyCol(3, 45)
CoordLV.ModifyCol(4, 45)
CoordLV.ModifyCol(5, 45)
CoordLV.ModifyCol(6, 50)

MainGui.Add("Button", "x370 y130 w55 h22", "Test").OnEvent("Click", TestCoord)
MainGui.Add("Button", "x370 y155 w55 h22", "Delete").OnEvent("Click", DelCoord)

MainGui.Add("Button", "x570 y288 w85 h22 cBlue", "Import .maw").OnEvent("Click", ImportWorkflow)
MainGui.Add("Button", "x665 y288 w85 h22 cGreen", "Export .maw").OnEvent("Click", ExportWorkflow)
MainGui.Add("GroupBox", "x15 y195 w860 h135", "Build Sequence Step")
ActionDD := MainGui.Add("DropDownList", "x70 yp-3 w140 vActionType", [
    "Click", "Double Click", "Triple Click", "Right Click",
    "Drag", "Relative Click", "Menu Select",
    "Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick", "Find & Drag",
    "Wait for Pattern", "Wait Until Gone",
    "Send Keys", "Type Text", "Key Chord", "Paste", "Set Clipboard",
    "Wait", "Activate Window", "Taskbar Activate", "Run Program",
    "Insert Field", "Insert Date", "Scroll",
    "Parse Clipboard", "Load Revolver", "Fire Revolver", "Fire Revolver+Enter",
    "OCR Region", "OCR Click", "OCR Wait", "Load OCR Revolver", "Fire OCR Revolver",
    "Idle Mouse", "Hover Mouse", "Grab OCR to Var", "Use Var Paste", "Show Notification",
    "--- VARIABLES & LOGIC ---",
    "Set Variable", "Grab Clipboard", "If Contains", "If Variable", "Stop Execution", "Run Sequence",
    "--- CLIPBOARD FORMATTING ---",
    "Format Clipboard", "Append to Clipboard", "Prepend to Clipboard", "Extract from Clipboard"
])

ActionDD.Choose(1)
ActionDD.OnEvent("Change", OnActionChange)
MainGui.Add("Text", "x25 y243 w40", "Target:")
MainGui.Add("Text", "x70 y243 w140 cGray", "(WHERE to act)")
TargetDD := MainGui.Add("ComboBox", "x25 y258 w185 vTargetCoord")
MainGui.Add("Text", "x220 y243 w40", "Param:")
MainGui.Add("Text", "x270 y243 w160 cGray", "(HOW or WHAT data)")
ParamCombo := MainGui.Add("ComboBox", "x220 y258 w210 vActionParam")
ParamCombo.OnEvent("Focus", UpdateLiveParamHints)
ParamEdit := ParamCombo
MainGui.Add("Button", "x440 y258 w50 h22", "Add").OnEvent("Click", AddStep)
MainGui.Add("Button", "x495 y258 w70 h22", "📷 OCR").OnEvent("Click", SelectOCRRegionForWorkflow)
MainGui.Add("Button", "x570 y258 w85 h22 cGreen", "Templates").OnEvent("Click", ShowTemplateLibrary)

MainGui.Add("Button", "x570 y310 w85 h22 cBlue", "Import .maw").OnEvent("Click", ImportWorkflow)
MainGui.Add("Button", "x665 y310 w85 h22 cGreen", "Export .maw").OnEvent("Click", ExportWorkflow)
MainGui.Add("Text", "x25 y288", "Pattern:")
QualPatternDD := MainGui.Add("DropDownList", "x80 yp-3 w120 vQualPattern", ["(none)"])
MainGui.Add("Text", "x210 yp+3", "Window:")
QualWindowEdit := MainGui.Add("Edit", "x260 yp-3 w120 vQualWindow")
MainGui.Add("CheckBox", "x390 yp+3 vFailsafeClose Checked", "Failsafe: Block close")
MainGui.Add("Text", "x25 y308", "Choices:")
ChoicesDD := MainGui.Add("DropDownList", "x80 yp-3 w350 vChoices")
MainGui.Add("Button", "x435 yp w25 h22", "<").OnEvent("Click", UseChoice)
MainGui.Add("Button", "x465 yp w50 h22", "Refresh").OnEvent("Click", RefreshChoices)
MainGui.Add("GroupBox", "x670 y195 w205 h290", "Action Help")
global ActionHelpTitle := MainGui.Add("Text", "x680 y210 w185 cBlue", "Select action")
global ActionHelpText := MainGui.Add("Edit", "x680 y230 w185 h245 ReadOnly Multi VScroll", "Select an action to see detailed usage instructions, TARGET/PARAM explanations, and examples.")
MainGui.Add("Text", "x15 y335", "Sequence Steps: (Right-click for options)")
StepsLV := MainGui.Add("ListView", "x15 y350 w720 h135 Grid Checked NoSortHdr vStepsLV", ["#", "Action", "Target", "Parameter", "Failsafe"])
StepsLV.ModifyCol(1, 25)
StepsLV.ModifyCol(2, 120)
StepsLV.ModifyCol(3, 150)
StepsLV.ModifyCol(4, 280)
StepsLV.ModifyCol(5, 125)
StepsLV.OnEvent("ItemSelect", OnStepSelect)
StepsLV.OnEvent("ContextMenu", OnStepsContextMenu)
StepsLV.OnEvent("ItemCheck", OnStepCheck)
MainGui.Add("Button", "x740 y350 w50 h22", "Up").OnEvent("Click", StepUp)
MainGui.Add("Button", "x740 y375 w50 h22", "Down").OnEvent("Click", StepDown)
MainGui.Add("Button", "x795 y350 w75 h22", "Edit").OnEvent("Click", EditStep)
MainGui.Add("Button", "x795 y375 w75 h22", "Delete").OnEvent("Click", DelStep)

MainGui.Add("Button", "x740 y405 w65 h22", "Toggle").OnEvent("Click", ToggleStep)
MainGui.Add("Button", "x810 y405 w60 h22", "Clear").OnEvent("Click", ClearSteps)

MainGui.Add("Button", "x740 y435 w65 h22 cGreen", "Test Step").OnEvent("Click", TestSingleStep)
MainGui.Add("Button", "x810 y435 w60 h22 cBlue", "Sim Step").OnEvent("Click", SimulateSingleStep)
MainGui.Add("Button", "x740 y460 w130 h22 cBlue", "Simulate All").OnEvent("Click", SimulateSeq)
MainGui.Add("Text", "x15 y490", "Save As:")
SeqNameEdit := MainGui.Add("Edit", "x70 yp-3 w140 vSeqName")
MainGui.Add("Button", "x215 yp w60 h22", "Save").OnEvent("Click", SaveSeq)
MainGui.Add("Button", "x280 yp w80 h22 cGreen", "Run All").OnEvent("Click", TestSeq)
MainGui.Add("CheckBox", "x365 yp+3 vStepThroughCheck", "Step-Through (Tab to advance)").OnEvent("Click", ToggleStepThrough)
MainGui.Add("Text", "x15 y515", "Speed:")
SpeedDD := MainGui.Add("DropDownList", "x55 yp-3 w70 vPlaybackSpeed", ["0.25x", "0.5x", "0.75x", "1x", "1.5x", "2x", "3x"])
SpeedDD.Choose(4)
MainGui.Add("Text", "x130 yp+3 w200 cGray", "(affects delays, ignored in Step-Through)")
MainGui.Add("Text", "x365 y515", "Hotkey:")
SeqHotkeyEdit := MainGui.Add("Edit", "x415 yp-3 w80 vSeqHotkey")
MainGui.Add("Text", "x500 yp+3 c888888", "^!s")

MainGui.Add("Text", "x550 y515", "Hotstring:")
SeqHotstringEdit := MainGui.Add("Edit", "x615 yp-3 w90 vSeqHotstring")
MainGui.Add("Text", "x710 yp+3 c888888", "::seq")
MainGui.Add("Text", "x15 y545", "Saved Workflows:")
SeqLV := MainGui.Add("ListView", "x15 y560 w720 h150 r5 Grid NoSortHdr vSeqLV", ["Name", "Steps", "Speed"])
SeqLV.Opt("-LV0x2000")       ; remove LVS_NOSCROLL (prevents scrolling)
SeqLV.Opt("+0x00200000") SeqLV.Opt("+LV0x1000")
SeqLV.ModifyCol(1, 550)
SeqLV.ModifyCol(2, 70)
SeqLV.ModifyCol(3, 80)
SeqLV.OnEvent("ContextMenu", OnSeqContextMenu)

MainGui.Add("Button", "x740 y560 w65 h22", "Load").OnEvent("Click", LoadSeq)
MainGui.Add("Button", "x810 y560 w60 h22", "Delete").OnEvent("Click", DelSeq)
MainGui.Add("Button", "x740 y585 w65 h22 cGreen", "Run").OnEvent("Click", RunSeq)
MainGui.Add("Button", "x810 y585 w60 h22 cBlue", "Sim").OnEvent("Click", SimulateSavedSeq)
MainGui.Add("Button", "x740 y610 w130 h22", "📖 Instructions").OnEvent("Click", ShowInstructionsFile)
TabCtrl.UseTab(2)
MainGui.Add("GroupBox", "x15 y50 w430 h220", "Pattern Definition")
MainGui.Add("Button", "x25 y70 w100 h24", "📷 Quick Capture").OnEvent("Click", QuickCapturePattern)
MainGui.Add("Button", "x130 y70 w100 h24", "FindText GUI").OnEvent("Click", OpenFindTextGUI)
MainGui.Add("Text", "x240 y75 w200 cGray", "Quick: drag region | FindText: advanced")
MainGui.Add("Text", "x25 y100", "Name:")
PatternNameEdit := MainGui.Add("Edit", "x65 yp-3 w120 vPatternName")
MainGui.Add("Text", "x195 yp+3", "Desc:")
PatternDescEdit := MainGui.Add("Edit", "x225 yp-3 w205 vPatternDesc")
MainGui.Add("Text", "x25 y127", "Qualifier:")
PatternQualifierDD := MainGui.Add("DropDownList", "x80 yp-3 w150 vPatternQualifier", ["(none)"])
PatternQualifierDD.Choose(1)
MainGui.Add("Text", "x240 y127 w190 cGray", "Pattern that must exist first")
MainGui.Add("Text", "x25 y152", "Code:")
PatternCodeEdit := MainGui.Add("Edit", "x25 y167 w320 h50 Multi vPatternCode", "")
PatternCodeEdit.OnEvent("Change", UpdatePatternPreview)

MainGui.Add("Button", "x350 y167 w80 h22", "Paste").OnEvent("Click", PastePatternCode)
MainGui.Add("Button", "x350 y192 w80 h22", "Clear").OnEvent("Click", ClearPatternCode)
MainGui.Add("Button", "x25 y225 w90 h22", "Save Pattern").OnEvent("Click", SavePattern)
MainGui.Add("Button", "x120 yp w90 h22", "Test Pattern").OnEvent("Click", TestPattern)
MainGui.Add("Button", "x215 yp w70 h22", "📷 Find").OnEvent("Click", CaptureScreenshotNow)
ExtractStatus := MainGui.Add("Text", "x290 y228 w150 cGreen vExtractStatus", "")
MainGui.Add("GroupBox", "x455 y50 w420 h220", "Preview & Capture Info")
MainGui.SetFont("s6", "Consolas")
PatternPreviewEdit := MainGui.Add("Edit", "x465 y68 w180 h120 ReadOnly Multi vPatternPreview", "Paste code or capture...")
MainGui.SetFont("s9", "Segoe UI")
MainGui.Add("Button", "x555 y190 w90 h18", "↗ Popout").OnEvent("Click", PopoutPatternPreview)
MainGui.SetFont("s9", "Segoe UI")
MainGui.Add("Text", "x655 y68 w100 h12 Center cGray", "Screenshot:")
PatternImageBox := MainGui.Add("Picture", "x655 y82 w100 h100 Border vPatternImage", "")
MainGui.Add("Button", "x655 y185 w48 h20", "View").OnEvent("Click", ViewPatternImage)
MainGui.Add("Button", "x707 y185 w48 h20", "📷").OnEvent("Click", RecaptureScreenshot)
MainGui.Add("Text", "x765 y68 w100", "Capture Info:")
PatternCaptureInfo := MainGui.Add("Edit", "x765 y82 w100 h123 ReadOnly Multi vPatternCaptureInfo", "No data")
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
MainGui.Add("Button", "x775 y295 w90 h22", "Test").OnEvent("Click", TestSelectedPattern)
MainGui.Add("Button", "x775 y320 w90 h22", "Edit").OnEvent("Click", EditPattern)
MainGui.Add("Button", "x775 y345 w90 h22", "Delete").OnEvent("Click", DeletePattern)
MainGui.Add("Button", "x775 y370 w90 h22", "Full View").OnEvent("Click", PopoutSelectedPattern)
MainGui.Add("GroupBox", "x15 y415 w860 h65", "Pattern System Reference")
MainGui.Add("Text", "x25 y432", "QUICK CAPTURE: Drag region → auto-generate pattern  |  QUALIFIER: Pattern that must exist first")
MainGui.Add("Text", "x25 y447", "ACTIONS: Find & Click/DblClick/TplClick/RClick/Drag  |  WAITS: Wait for Pattern, Wait Until Gone")
MainGui.Add("Text", "x25 y462 cGray", "Tips: Gray2Two for text, Color2Two for colored buttons  |  Use qualifiers for generic buttons like 'Submit'")
TabCtrl.UseTab(3)
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
MainGui.Add("GroupBox", "x225 y140 w180 h100", "Capture Region")
OCRRegionPreview := MainGui.Add("Text", "x235 y160 w160 h70 Border vOCRRegionPreview cGray Center", "Full Screen`n(Select Region)")
MainGui.Add("GroupBox", "x415 y140 w170 h100", "Last Capture Info")
MainGui.Add("Text", "x425 y158", "Words:")
MainGui.Add("Text", "x470 y158 w50 vOCRWordCount cBlue", "0")
MainGui.Add("Text", "x425 y175", "Lines:")
MainGui.Add("Text", "x470 y175 w50 vOCRLineCount cBlue", "0")
MainGui.Add("Text", "x425 y192", "Angle:")
MainGui.Add("Text", "x470 y192 w50 vOCRTextAngle cBlue", "0°")
MainGui.Add("Text", "x425 y209", "Time:")
MainGui.Add("Text", "x470 y209 w50 vOCRCaptureTime cBlue", "0ms")
MainGui.Add("GroupBox", "x595 y140 w280 h100", "Watch Words (Dynamic Variables)")
MainGui.Add("Text", "x605 y158 w260 cGray", "Define regions to auto-capture text into variables")
MainGui.Add("Text", "x605 y175", "Name:")
WatchWordNameEdit := MainGui.Add("Edit", "x650 y172 w100 vWatchWordName")
MainGui.Add("Button", "x755 y172 w110 h20", "Define from OCR").OnEvent("Click", DefineWatchWordFromOCR)
MainGui.Add("Button", "x605 y198 w80 h20", "Update All").OnEvent("Click", (*) => UpdateAllWatchWords())
MainGui.Add("Button", "x690 y198 w80 h20", "Show Values").OnEvent("Click", ShowWatchWordValues)
MainGui.Add("Button", "x775 y198 w90 h20", "Manage...").OnEvent("Click", ManageWatchWords)
MainGui.Add("GroupBox", "x15 y245 w430 h205", "Live OCR Text Output")
OCROutputEdit := MainGui.Add("Edit", "x25 y263 w410 h165 ReadOnly Multi VScroll vOCROutput", "")
MainGui.Add("Button", "x25 y432 w60 h18", "📋 Copy").OnEvent("Click", CopyOCRToClipboard)
MainGui.Add("Button", "x90 y432 w80 h18", "🔫 Load Rev").OnEvent("Click", LoadOCRToRevolver)
MainGui.Add("Button", "x175 y432 w60 h18", "→ Var").OnEvent("Click", SaveOCRToVariable)
MainGui.Add("Button", "x240 y432 w80 h18", "Click Text").OnEvent("Click", ClickTextInOCR)
MainGui.Add("Button", "x325 y432 w55 h18", "Regex").OnEvent("Click", ExtractOCRRegex)
MainGui.Add("Button", "x385 y432 w50 h18", "Split").OnEvent("Click", SplitOCRText)
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
MainGui.Add("GroupBox", "x665 y245 w210 h205", "Watch Word Values")
WatchWordLV := MainGui.Add("ListView", "x675 y263 w190 h145 Grid NoSortHdr vWatchWordLV", ["Name", "Value"])
WatchWordLV.ModifyCol(1, 70)
WatchWordLV.ModifyCol(2, 110)
WatchWordLV.OnEvent("ItemSelect", OnWatchWordSelect)
WatchWordLV.OnEvent("DoubleClick", OnWatchWordDblClick)
MainGui.Add("Button", "x675 y413 w60 h20", "Highlight").OnEvent("Click", HighlightSelectedWatchWord)
MainGui.Add("Button", "x740 y413 w60 h20", "Use").OnEvent("Click", UseSelectedWatchWord)
MainGui.Add("Button", "x805 y413 w60 h20", "Delete").OnEvent("Click", DeleteSelectedWatchWord)
MainGui.Add("GroupBox", "x15 y455 w430 h85", "Search & Text Operations")
MainGui.Add("Text", "x25 y473", "Find:")
OCRSearchEdit := MainGui.Add("Edit", "x60 y470 w150 vOCRSearch")
MainGui.Add("Button", "x215 y470 w50 h22", "Find").OnEvent("Click", FindInOCR)
MainGui.Add("Button", "x270 y470 w65 h22", "Highlight").OnEvent("Click", HighlightOCRMatch)
MainGui.Add("Button", "x340 y470 w55 h22", "Clear").OnEvent("Click", ClearOCRHighlights)
MainGui.Add("CheckBox", "x400 y473 vOCRCaseSense", "Case")
MainGui.Add("Text", "x25 y500", "Revolver:")
OCRSplitDD := MainGui.Add("DropDownList", "x75 y497 w80 vOCRSplitMode", ["4 parts", "Tab", "Line", "Space", "Comma", "2 parts", "3 parts", "5 parts"])
OCRSplitDD.Choose(1)
MainGui.Add("Button", "x160 y497 w75 h22", "Load Rev").OnEvent("Click", LoadOCRToRevolverDD)
MainGui.Add("Button", "x240 y497 w75 h22", "Fire Rev").OnEvent("Click", FireOCRRevolverUI)
MainGui.Add("Text", "x320 y500 w100 vOCRRevolverStatus cGray", "Ready")
MainGui.Add("GroupBox", "x455 y455 w420 h85", "OCR Recording Log & Info")
MainGui.Add("Button", "x465 y473 w60 h22", "View").OnEvent("Click", ViewOCRLog)
MainGui.Add("Button", "x530 y473 w60 h22", "Clear").OnEvent("Click", ClearOCRLog)
MainGui.Add("Button", "x595 y473 w60 h22", "Export").OnEvent("Click", ExportOCRLog)
MainGui.Add("Text", "x660 y478 w40 vOCRLogCount cGray", "0")
MainGui.Add("Text", "x700 y478 w50 cGray", "entries")
MainGui.Add("Button", "x755 y473 w60 h22", "Languages").OnEvent("Click", GetOCRLanguages)
MainGui.Add("Button", "x820 y473 w50 h22", "Help").OnEvent("Click", ShowOCRHelp)
MainGui.Add("Text", "x465 y500 w380 cGray", "OCR Revolver: paste captured text in parts. Load splits text, Fire pastes sequentially.")
TabCtrl.UseTab(4)
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
MainGui.Add("GroupBox", "x15 y140 w430 h335", "Define Spool")

MainGui.Add("Text", "x25 y158", "Name:")
SpoolNameEdit := MainGui.Add("Edit", "x70 yp-3 w130 vSpoolName")
SpoolEnabledChk := MainGui.Add("CheckBox", "x210 y158 vSpoolEnabled Checked", "Enabled")
MainGui.Add("Text", "x25 y188", "Region:")
SpoolRegionDD := MainGui.Add("DropDownList", "x70 yp-3 w100 vSpoolRegion", ["Full Screen", "Custom Region", "Active Window"])
SpoolRegionDD.Choose(1)
MainGui.Add("Button", "x175 yp w55 h22", "Select").OnEvent("Click", SelectSpoolRegion)
SpoolRegionText := MainGui.Add("Text", "x235 y188 w190 cGray vSpoolRegionText", "")
MainGui.Add("Text", "x25 y218", "Detect:")
SpoolDetectDD := MainGui.Add("DropDownList", "x65 yp-3 w105 vSpoolDetect",
    ["Pattern Match", "Pattern Sequence", "OCR Contains", "OCR Regex", "Pixel Change", "Window Title"])
SpoolDetectDD.Choose(1)
SpoolDetectDD.OnEvent("Change", OnSpoolDetectChange)
MainGui.Add("Text", "x175 y218", "Target:")
SpoolTargetCombo := MainGui.Add("ComboBox", "x215 yp-3 w215 vSpoolTarget")
SpoolSeqHelp := MainGui.Add("Text", "x25 y240 w400 cGray vSpoolSeqHelp", "")
MainGui.Add("Text", "x25 y258", "Interval:")
SpoolIntervalEdit := MainGui.Add("Edit", "x70 yp-3 w45 vSpoolInterval Number", "500")
MainGui.Add("Text", "x120 y258", "ms")

MainGui.Add("Text", "x160 y258", "When:")
SpoolConditionDD := MainGui.Add("DropDownList", "x195 yp-3 w90 vSpoolCondition",
    ["Found", "Not Found", "Changed"])
SpoolConditionDD.Choose(1)
MainGui.Add("GroupBox", "x25 y280 w405 h50", "Behavior After Trigger")
SpoolModeDD := MainGui.Add("DropDownList", "x35 y298 w100 vSpoolMode",
    ["Continuous", "One-Shot", "Cooldown"])
SpoolModeDD.Choose(1)
SpoolModeDD.OnEvent("Change", OnSpoolModeChange)

MainGui.Add("Text", "x145 y301 vSpoolCooldownLabel", "Cooldown:")
SpoolCooldownEdit := MainGui.Add("Edit", "x200 y298 w40 vSpoolCooldown Number", "5")
MainGui.Add("Text", "x245 y301", "sec")
MainGui.Add("Text", "x280 y301 w140 cGray vSpoolModeHelp", "(re-check after delay)")
MainGui.Add("GroupBox", "x25 y335 w405 h60", "Action When Triggered")
MainGui.Add("Text", "x35 y353", "Do:")
SpoolActionDD := MainGui.Add("DropDownList", "x55 yp-3 w105 vSpoolAction",
    ["Show Notification", "Run Workflow", "Start Spool", "Stop Spool", "Extract OCR", "Set Variable", "Key Chord", "Run Program"])
SpoolActionDD.Choose(1)
SpoolActionDD.OnEvent("Change", OnSpoolActionChange)

MainGui.Add("Text", "x165 y353", "Target:")
SpoolActionTargetCombo := MainGui.Add("ComboBox", "x200 yp-3 w160 vSpoolActionTarget")
MainGui.Add("Text", "x365 y353 vSpoolNotifLabel", "Time:")
SpoolNotifTimeEdit := MainGui.Add("Edit", "x395 y350 w30 vSpoolNotifTime Number", "5")
SpoolExtractOCRChk := MainGui.Add("CheckBox", "x35 y375 vSpoolExtractOCR", "Also extract OCR to:")
SpoolOCRVarEdit := MainGui.Add("Edit", "x160 y372 w70 vSpoolOCRVar", "")
MainGui.Add("GroupBox", "x25 y400 w405 h65", "Auto-Stop Condition (Optional)")
SpoolAutoCompleteChk := MainGui.Add("CheckBox", "x35 y418 vSpoolAutoComplete", "Stop spool when:")
SpoolCompletionDD := MainGui.Add("DropDownList", "x145 y415 w90 vSpoolCompletion",
    ["Pattern Found", "Pattern Gone", "OCR Contains", "Timeout", "Variable Set"])
SpoolCompletionDD.Choose(1)
SpoolCompletionTargetCombo := MainGui.Add("ComboBox", "x240 y415 w115 vSpoolCompletionTarget")
MainGui.Add("Text", "x360 y418", "or")
SpoolTimeoutEdit := MainGui.Add("Edit", "x380 y415 w35 vSpoolTimeout Number", "0")
MainGui.Add("Text", "x35 y440 cGray", "Timeout: 0 = no auto-stop")
MainGui.Add("Button", "x25 y470 w80 h24", "Save Spool").OnEvent("Click", SaveSpool)
MainGui.Add("Button", "x110 y470 w70 h24", "Clear").OnEvent("Click", ClearSpoolForm)
MainGui.Add("Button", "x185 y470 w80 h24", "Test Once").OnEvent("Click", TestSpoolOnce)
MainGui.Add("Button", "x270 y470 w80 h24 cBlue", "Test Pattern").OnEvent("Click", TestSpoolPattern)
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
MainGui.Add("GroupBox", "x455 y400 w200 h95", "Extracted Variables")
OCRVarsLV := MainGui.Add("ListView", "x465 y418 w180 h55 Grid NoSortHdr vOCRVarsLV",
    ["Variable", "Value"])
OCRVarsLV.ModifyCol(1, 70)
OCRVarsLV.ModifyCol(2, 100)

MainGui.Add("Button", "x465 y476 w50 h18", "Clear").OnEvent("Click", ClearOCRVars)
MainGui.Add("Button", "x520 y476 w50 h18", "Use").OnEvent("Click", UseOCRVar)
MainGui.Add("Button", "x575 y476 w60 h18", "Refresh").OnEvent("Click", (*) => RefreshOCRVarsLV())
MainGui.Add("GroupBox", "x665 y400 w210 h95", "Activity Log")
SpoolLogEdit := MainGui.Add("Edit", "x675 y418 w190 h55 ReadOnly Multi vSpoolLog", "")
MainGui.Add("Button", "x815 y476 w50 h18", "Clear").OnEvent("Click", ClearSpoolLog)
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
MainGui.Add("GroupBox", "x15 y240 w860 h100", "Window Hotspots")
HotspotsLV := MainGui.Add("ListView", "x25 y258 w840 h75 Grid NoSortHdr", ["Window/App", "Top Hotspot", "Click Count"])
HotspotsLV.ModifyCol(1, 350)
HotspotsLV.ModifyCol(2, 300)
HotspotsLV.ModifyCol(3, 150)
TabCtrl.UseTab(6)
MainGui.Add("Text", "x15 y55", "Clipboard:")
ClipEdit := MainGui.Add("Edit", "x15 y70 w400 h70 Multi vClipContent")
MainGui.Add("Button", "x420 y70 w70 h22", "Grab").OnEvent("Click", GrabClip)
MainGui.Add("Button", "x420 y95 w70 h22", "Parse").OnEvent("Click", ParseClip)
MainGui.Add("Button", "x420 y120 w70 h22", "Clear").OnEvent("Click", ClearClip)
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
MainGui.Add("Text", "x15 y265", "Extracted:")
ExtractLV := MainGui.Add("ListView", "x15 y280 w350 h70 Grid NoSortHdr", ["Field", "Value"])
ExtractLV.ModifyCol(1, 100)
ExtractLV.ModifyCol(2, 240)
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
MainGui.Add("GroupBox", "x380 y380 w200 h95", "Notifications")
MainGui.Add("CheckBox", "x390 y400 vDebugMode Checked", "Debug Mode (show all steps)")
MainGui.Add("CheckBox", "x390 y420 vNotifDismissible Checked", "Dismissible (stay until clicked)")
MainGui.Add("Text", "x390 y440", "Auto-dismiss:")
MainGui.Add("Edit", "x465 y437 w40 vNotifTimeout Number", "5")
MainGui.Add("Text", "x510 y440", "sec")

MainGui.Add("Button", "x15 y465 w80 h24", "Save").OnEvent("Click", SaveSettingsGUI)
MainGui.Add("Button", "x100 yp w80 h24", "Reset").OnEvent("Click", ResetSettingsGUI)
MainGui.Add("Button", "x185 yp w100 h24", "Open Folder").OnEvent("Click", (*) => Run(DATA_DIR))
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
TabCtrl.UseTab(0)
StatusBar := MainGui.Add("StatusBar",, "Ready | CAPSLOCK = Definition Mode | Ctrl+Shift+G: Toggle")
TabCtrl.UseTab(12)

MainGui.Add("Text", "x15 y50 cBlue", "📅 Appointment Scheduler")
MainGui.Add("Button", "x150 y50 w60 h25", "◄ Prev").OnEvent("Click", PrevDay)
global g_DateDisplayText := MainGui.Add("Text", "x215 y55 w250 Center", FormatTime(g_CalendarDate, "dddd, MMMM dd, yyyy"))
MainGui.Add("Button", "x470 y50 w60 h25", "Next ►").OnEvent("Click", NextDay)
MainGui.Add("Button", "x535 y50 w60 h25", "Today").OnEvent("Click", GoToToday)
MainGui.Add("Button", "x650 y50 w100 h25", "Patients").OnEvent("Click", (*) => OpenPatientList())
yPos := 90
slots := GenerateTimeSlots()

for time in slots {
    displayTime := FormatTimeSlot(time)
    MainGui.Add("Text", "x15 y" . (yPos+5), displayTime)
    btn := MainGui.Add("Button", "x85 y" . yPos . " w600 h28", "[Empty]")
    btn.OnEvent("Click", (*) => ClickTimeSlot(time))
    g_TimeSlotButtons[time] := btn
    
    yPos += 30
}


SetTimer(UpdateDefinitionMode, 100)
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

^+c::ClearAllNotifications()
^+f::FindText().Gui("Show")
^b::LoadRevolverFromSelection()   ; Copy + Parse + Load
^+b::FireAllShots()               ; Fire all shots (paste + Tab...)
^!b::LoadRevolverItem(A_Clipboard)  ; Ctrl+Alt+B = Load to smart bins (shows selector)
^!+b::PasteFromBins()
^!n::OpenNotepadPopup()  ; Ctrl+Alt+N = Open notepad popup
#b::ShowBinSelector("")  ; Ctrl+Alt+B = Open bin selector
^!i::ExecuteIdleMouse("0")
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
ApplyHotkeys()
UpdateSpoolMasterStatus()  ; Update spool status display
RefreshHotstringList()  ; V5.0: Populate hotstring list
