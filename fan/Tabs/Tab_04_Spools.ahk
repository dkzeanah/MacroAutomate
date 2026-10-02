; ===============================================================================
; Tabs\Tab_04_Spools.ahk
; TAB 4 Spools: spool engine, form, import/export .mas, notifications list
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================


; --- Spool UI Functions ---

ToggleSpoolMaster(*) {
    global g_SpoolMasterEnabled, SpoolMasterToggle, g_Settings
    g_SpoolMasterEnabled := SpoolMasterToggle.Value
    g_Settings["SpoolMasterEnabled"] := g_SpoolMasterEnabled
    SaveSettings()
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
    global g_SpoolMasterEnabled, SpoolMasterToggle, g_Settings
    g_SpoolMasterEnabled := true
    SpoolMasterToggle.Value := 1
    g_Settings["SpoolMasterEnabled"] := true
    SaveSettings()
    StartEnabledSpools()
    UpdateSpoolMasterStatus()
    SpoolLogAdd("All spools started")
}

StopAllSpools(*) {
    global g_ActiveSpools, g_SpoolMasterEnabled, SpoolMasterToggle, g_Settings, g_SpoolStartedAt

    for name, timer in g_ActiveSpools {
        SetTimer(timer, 0)
    }
    g_ActiveSpools := Map()
    g_SpoolStartedAt := Map()
    g_SpoolMasterEnabled := false
    try SpoolMasterToggle.Value := 0
    g_Settings["SpoolMasterEnabled"] := false
    SaveSettings()

    UpdateSpoolMasterStatus()
    RefreshSpoolLV()
    SpoolLogAdd("All spools stopped")
}

RestoreSpoolMasterState() {
    global g_SpoolMasterEnabled, SpoolMasterToggle, g_Settings
    g_SpoolMasterEnabled := g_Settings.Has("SpoolMasterEnabled") && g_Settings["SpoolMasterEnabled"]
    try SpoolMasterToggle.Value := g_SpoolMasterEnabled
    if g_SpoolMasterEnabled
        StartEnabledSpools()
    else
        UpdateSpoolMasterStatus()
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
    global g_Spools, g_ActiveSpools, g_SpoolMasterEnabled, SpoolMasterToggle, g_Settings, g_SpoolStartedAt

    ; Starting an individual Spool is an explicit request, so also enable the
    ; persisted master switch. This removes the old silent "Start did nothing"
    ; failure when the master checkbox was off.
    if !g_SpoolMasterEnabled {
        g_SpoolMasterEnabled := true
        try SpoolMasterToggle.Value := 1
        g_Settings["SpoolMasterEnabled"] := true
        SaveSettings()
    }

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
    g_SpoolStartedAt[name] := A_TickCount

    ; Start timer
    interval := Max(100, Integer(spool["interval"]))
    SetTimer(timerFunc, interval)

    SpoolLogAdd("Started: " . name)
    SpoolSetRuntimeStatus(name, "Waiting")
    RefreshSpoolLV()
    UpdateSpoolMasterStatus()
}

StopSpool(name) {
    global g_ActiveSpools, g_SpoolStartedAt

    if g_ActiveSpools.Has(name) {
        SetTimer(g_ActiveSpools[name], 0)
        g_ActiveSpools.Delete(name)
        if g_SpoolStartedAt.Has(name)
            g_SpoolStartedAt.Delete(name)
        SpoolLogAdd("Stopped: " . name)
        SpoolSetRuntimeStatus(name, "Stopped")
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

    if !forceTest && SpoolCompletionReached(name, spool) {
        SpoolLogAdd("AUTO-STOP COMPLETE: " . name)
        SpoolSetRuntimeStatus(name, "Completed")
        StopSpool(name)
        return
    }

    ; Check if spool is in cooldown (unless force testing)
    if !forceTest && IsSpoolInCooldown(name) {
        return  ; Skip this check, in cooldown
    }

    detectedValue := ""
    detected := SpoolEvaluateDetection(spool, name, &detectedValue)

    ; If detected, execute action
    if detected {
        SpoolLogAdd("TRIGGERED: " . name)

        ; Extract OCR to variable if requested
        if spool["extractOCR"] && spool["ocrVar"] != "" && detectedValue != "" {
            g_SpoolVariables[spool["ocrVar"]] := detectedValue
            RefreshOCRVarsLV()
        }

        ; Execute action (pass spool name for cooldown tracking). Action errors
        ; are contained and logged so a timer cannot die silently.
        actionSucceeded := false
        try actionSucceeded := ExecuteSpoolAction(spool, name)
        catch as err {
            LogErrorToFile(err, "caught", "Spool action: " . name)
            SpoolLogAdd("ERROR: " . name . " - " . err.Message)
        }
        SpoolSetRuntimeStatus(name, actionSucceeded ? "Action OK" : "Action failed")

        ; A manual Test Trigger executes the response but never changes the
        ; saved monitor's running/stopped/cooldown state.
        if !forceTest {
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
                    ; Timer interval controls immediate repetition.
            }
        }

    }
}

SpoolCompletionReached(name, spool) {
    global g_SpoolStartedAt, g_SpoolVariables
    if !spool["autoComplete"]
        return false
    completion := spool["completion"]
    target := Trim(spool["completionTarget"])
    region := GetSpoolRegion(spool)
    switch completion {
        case "Timeout":
            timeout := spool.Has("timeout") ? Integer(spool["timeout"]) : 0
            return timeout > 0 && g_SpoolStartedAt.Has(name)
                && A_TickCount - g_SpoolStartedAt[name] >= timeout * 1000
        case "Pattern Found":
            return target != "" && SpoolFindPattern(target, region, &x, &y)
        case "Pattern Gone":
            return target != "" && !SpoolFindPattern(target, region, &x, &y)
        case "OCR Contains":
            return target != "" && SpoolDetectOCRWindows(region, target, false)["found"]
        case "Variable Set":
            return target != "" && (g_SpoolVariables.Has(target) || g_SpoolVariables.Has("$" . target))
    }
    return false
}

SpoolEvaluateDetection(spool, spoolName, &detectedValue) {
    detectedValue := ""
    region := GetSpoolRegion(spool)
    detected := false

    switch spool["detectType"] {
        case "Pattern Match":
            detected := SpoolDetectPattern(spool["target"], region, spool["condition"])
        case "Pattern Sequence":
            detected := SpoolDetectPatternSequence(spool["target"], region)
            if spool["condition"] = "Not Found"
                detected := !detected
        case "OCR Contains":
            result := SpoolDetectOCRWindows(region, spool["target"], false)
            detectedValue := result["text"]
            detected := result["found"]
            if spool["condition"] = "Not Found"
                detected := !detected
        case "OCR Regex":
            result := SpoolDetectOCRWindows(region, spool["target"], true)
            detectedValue := result["text"]
            detected := result["found"]
            if spool["condition"] = "Not Found"
                detected := !detected
        case "Pixel Change", "Screen Changed":
            detected := SpoolDetectScreenChange(spoolName, region)
        case "Window Title":
            activeTitle := ""
            try activeTitle := WinGetTitle("A")
            detected := InStr(activeTitle, spool["target"])
            if spool["condition"] = "Not Found"
                detected := !detected
    }
    return !!detected
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
    found := SpoolFindPattern(patternName, region, &outX, &outY)

    if condition = "Not Found"
        return !found
    return found
}

SpoolFindPattern(patternName, region, &outX, &outY) {
    global g_Patterns, g_Settings
    outX := 0, outY := 0
    if !g_Patterns.Has(patternName)
        return false
    code := g_Patterns[patternName]["text"]
    tolerance := g_Settings["FindTextTolerance"]
    ok := FindText(&outX, &outY, region["x1"], region["y1"], region["x2"], region["y2"],
        tolerance, tolerance, code)
    return !!(ok && ok.Length > 0)
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
    global g_Sequences, g_SpoolVariables, g_SpoolWorkflowActive

    switch spool["action"] {
        case "Run Workflow":
            workflowName := Trim(spool["actionTarget"])
            if !g_Sequences.Has(workflowName) {
                SpoolLogAdd("FAILED: " . spoolName . " - workflow not found: " . workflowName)
                ShowStatus("Spool workflow not found: " . workflowName, "fail")
                return false
            }
            if g_SpoolWorkflowActive {
                SpoolLogAdd("SKIPPED: " . spoolName . " - another Spool workflow is running")
                return false
            }
            g_SpoolWorkflowActive := true
            try {
                sequence := g_Sequences[workflowName]
                speed := sequence.Has("speed") ? sequence["speed"] : 1.0
                SpoolLogAdd("WORKFLOW START: " . workflowName . " (from " . spoolName . ")")
                ExecuteSequenceVerified(sequence["steps"], speed)
                SpoolLogAdd("WORKFLOW DONE: " . workflowName)
                return true
            } finally {
                g_SpoolWorkflowActive := false
            }

        case "Click Detected Pattern":
            if spool["detectType"] != "Pattern Match" || spool["condition"] != "Found" {
                SpoolLogAdd("FAILED: " . spoolName . " - direct click requires Pattern Match + Found")
                return false
            }
            patternName := Trim(spool["actionTarget"])
            if patternName = "" || patternName = "(use detected pattern)"
                patternName := spool["target"]
            region := GetSpoolRegion(spool)
            if !SpoolFindPattern(patternName, region, &clickX, &clickY) {
                SpoolLogAdd("FAILED: " . spoolName . " - pattern vanished before click: " . patternName)
                return false
            }
            FlashClickPosition(clickX, clickY)
            clicked := ClickVerified(clickX, clickY)
            if clicked
                SpoolLogAdd("CLICKED: " . patternName . " at " . clickX . "," . clickY)
            return clicked

        case "Show Notification":
            ; Pass spool name for cooldown tracking
            ShowSpoolNotification(spool["actionTarget"], spool, spoolName)
            return true

        case "Start Spool":
            StartSpool(spool["actionTarget"])
            return true

        case "Stop Spool":
            StopSpool(spool["actionTarget"])
            return true

        case "Extract OCR":
            ; OCR extraction handled in ExecuteSpoolCheck
            return true

        case "Set Variable":
            ; Parse "varName=value"
            if InStr(spool["actionTarget"], "=") {
                parts := StrSplit(spool["actionTarget"], "=", , 2)
                g_SpoolVariables[parts[1]] := parts[2]
                RefreshOCRVarsLV()
                return true
            }
            return false

        case "Key Chord":
            return ExecuteKeyChord(spool["actionTarget"])

        case "Run Program":
            try {
                Run(spool["actionTarget"])
                return true
            }
            return false
    }
    SpoolLogAdd("FAILED: " . spoolName . " - unknown action: " . spool["action"])
    return false
}

SpoolSetRuntimeStatus(name, status) {
    global g_SpoolLastStatus
    if name != ""
        g_SpoolLastStatus[name] := status
    try RefreshSpoolLV()
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
    global g_SpoolLog, SpoolLogEdit, SPOOL_ACTIVITY_LOG_FILE

    timestamp := FormatTime(, "HH:mm:ss")
    entry := "[" . timestamp . "] " . message
    g_SpoolLog.Push(entry)
    try FileAppend(FormatTime(, "yyyy-MM-dd ") . entry . "`r`n", SPOOL_ACTIVITY_LOG_FILE, "UTF-8")

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


; --- Spool UI Event Handlers ---

SaveSpool(*) {
    global g_Spools, g_ActiveSpools, SpoolNameEdit

    name := Trim(SpoolNameEdit.Value)
    if name = "" {
        MsgBoxTop("Enter a name!", "Required")
        return
    }

    if !BuildSpoolFromForm(&spool, &errorMessage) {
        MsgBoxTop(errorMessage, "Spool Needs Attention", "Icon!")
        return
    }

    wasRunning := g_ActiveSpools.Has(name)
    g_Spools[name] := spool
    SaveSpools()
    if wasRunning
        StartSpool(name)
    RefreshSpoolLV()
    ClearSpoolForm()
    SpoolLogAdd("Saved: " . name)
    ShowStatus("Spool saved: " . name, "ok")
}

SpoolInteger(value, defaultValue := 0, minimum := 0) {
    value := Trim(String(value))
    number := IsNumber(value) ? Integer(value) : defaultValue
    return Max(minimum, number)
}

BuildSpoolFromForm(&spool, &errorMessage) {
    global SpoolRegionDD, SpoolRegionText, SpoolDetectDD, SpoolTargetCombo
    global SpoolIntervalEdit, SpoolConditionDD, SpoolActionDD, SpoolActionTargetCombo
    global SpoolExtractOCRChk, SpoolOCRVarEdit, SpoolAutoCompleteChk
    global SpoolCompletionDD, SpoolCompletionTargetCombo, SpoolEnabledChk
    global SpoolTimeoutEdit, SpoolModeDD, SpoolCooldownEdit, SpoolNotifTimeEdit
    spool := Map(
        "enabled", SpoolEnabledChk.Value,
        "region", SpoolRegionDD.Text,
        "regionCoords", SpoolRegionText.Value,
        "detectType", SpoolDetectDD.Text,
        "target", Trim(SpoolTargetCombo.Text),
        "interval", SpoolInteger(SpoolIntervalEdit.Value, 500, 100),
        "condition", SpoolConditionDD.Text,
        "action", SpoolActionDD.Text,
        "actionTarget", Trim(SpoolActionTargetCombo.Text),
        "extractOCR", SpoolExtractOCRChk.Value,
        "ocrVar", Trim(SpoolOCRVarEdit.Value),
        "autoComplete", SpoolAutoCompleteChk.Value,
        "completion", SpoolCompletionDD.Text,
        "completionTarget", Trim(SpoolCompletionTargetCombo.Text),
        "timeout", SpoolInteger(SpoolTimeoutEdit.Value, 0, 0),
        "mode", SpoolModeDD.Text,
        "cooldown", SpoolInteger(SpoolCooldownEdit.Value, 5, 1),
        "notifTime", SpoolInteger(SpoolNotifTimeEdit.Value, 5, 1)
    )
    return ValidateSpoolDefinition(spool, &errorMessage)
}

ValidateSpoolDefinition(spool, &errorMessage, requireExistingWorkflow := true) {
    global g_Sequences, g_Patterns
    errorMessage := ""
    if spool["detectType"] != "Pixel Change" && spool["target"] = "" {
        errorMessage := "Choose what the Spool should detect."
        return false
    }
    if spool["detectType"] = "Pattern Match" && !g_Patterns.Has(spool["target"]) {
        errorMessage := "The detection pattern does not exist: " . spool["target"]
        return false
    }
    if spool["action"] = "Run Workflow" {
        if spool["actionTarget"] = "" {
            errorMessage := "Select a workflow from the Workflow tab."
            return false
        }
        if requireExistingWorkflow && !g_Sequences.Has(spool["actionTarget"]) {
            errorMessage := "The selected workflow does not exist: " . spool["actionTarget"]
            return false
        }
    }
    if spool["action"] = "Click Detected Pattern"
        && (spool["detectType"] != "Pattern Match" || spool["condition"] != "Found") {
        errorMessage := "Click Detected Pattern requires Detect = Pattern Match and When = Found."
        return false
    }
    return true
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
    SpoolModeDD.Choose(3)  ; Cooldown is the safe repeat default
    SpoolCooldownEdit.Value := "5"
    SpoolNotifTimeEdit.Value := "5"
    try SpoolSeqHelp.Value := ""
}

TestSpoolOnce(*) {
    global SpoolNameEdit
    if !BuildSpoolFromForm(&tempSpool, &errorMessage) {
        MsgBoxTop(errorMessage, "Cannot Test Spool", "Icon!")
        return
    }
    name := Trim(SpoolNameEdit.Value)
    if name = ""
        name := "Unsaved Spool"
    ShowStatus("Testing detection + response: " . name, "wait")
    detectedValue := ""
    if !SpoolEvaluateDetection(tempSpool, "__form_test__", &detectedValue) {
        SpoolLogAdd("TEST NOT FOUND: " . name)
        ShowStatus("Test: condition was not detected", "fail")
        return
    }
    SpoolLogAdd("TEST DETECTED: " . name)
    succeeded := ExecuteSpoolAction(tempSpool, name . " [test]")
    ShowStatus(succeeded ? "Test passed: response executed" : "Test detected, but response failed", succeeded ? "ok" : "fail")
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
    global SpoolActionDD, SpoolActionTargetCombo, g_Sequences, g_Spools, g_Patterns, SpoolActionHelp

    SpoolActionTargetCombo.Delete()

    switch SpoolActionDD.Text {
        case "Run Workflow":
            items := []
            for name, _ in g_Sequences
                items.Push(name)
            if items.Length > 0
                SpoolActionTargetCombo.Add(items)
            try SpoolActionHelp.Value := "Runs the selected Workflow-tab workflow. Repetition is controlled in Step 3 below."

        case "Click Detected Pattern":
            SpoolActionTargetCombo.Add(["(use detected pattern)"])
            items := []
            for name, _ in g_Patterns
                items.Push(name)
            if items.Length > 0
                SpoolActionTargetCombo.Add(items)
            SpoolActionTargetCombo.Text := "(use detected pattern)"
            try SpoolActionHelp.Value := "Re-finds and left-clicks the detected pattern. Use Cooldown to prevent rapid repeat clicks."

        case "Start Spool", "Stop Spool":
            items := []
            for name, _ in g_Spools
                items.Push(name)
            if items.Length > 0
                SpoolActionTargetCombo.Add(items)

        case "Show Notification":
            ; Default notification messages
            SpoolActionTargetCombo.Add(["Pattern detected!", "Action required", "Check this now"])
            try SpoolActionHelp.Value := "Shows a timed notification when detection succeeds."
        default:
            try SpoolActionHelp.Value := "Runs this response whenever the detection condition succeeds."
    }
}

RefreshSpoolWorkflowChoices() {
    global SpoolActionDD, SpoolActionTargetCombo
    try {
        if SpoolActionDD.Text != "Run Workflow"
            return
        current := SpoolActionTargetCombo.Text
        OnSpoolActionChange()
        SpoolActionTargetCombo.Text := current
    }
}

OnSpoolSelect(LV, RowNumber, *) {
    if RowNumber = 0
        return

    ; Could show spool details or populate form
}

OnSpoolCheck(LV, RowNumber, Checked) {
    global g_Spools
    if !TryGetListViewText(LV, RowNumber, 1, &name)
        return
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

OnSpoolContextMenu(LV, RowNumber, IsRightClick, X, Y) {
    global g_Spools, g_ActiveSpools
    if !TryGetListViewText(LV, RowNumber, 1, &name)
        return
    if !g_Spools.Has(name)
        return

    isRunning := g_ActiveSpools.Has(name)

    spoolMenu := Menu()
    spoolMenu.Add(isRunning ? "⏹ Stop" : "▶ Start", (*) => (isRunning ? StopSpool(name) : StartSpool(name)))
    spoolMenu.Add("Test Trigger", (*) => ExecuteSpoolCheck(name, true))
    spoolMenu.Add()
    spoolMenu.Add("✏ Edit", (*) => EditSpoolByName(name))
    spoolMenu.Add("📋 Duplicate", (*) => DuplicateSpool(name))
    spoolMenu.Add("Export .mas", (*) => ExportSpoolByName(name))
    spoolMenu.Add()
    spoolMenu.Add("🗑 Delete", (*) => DeleteSpoolByName(name))

    spoolMenu.Show(X, Y)
}

EditSpool(*) {
    global SpoolLV
    row := SpoolLV.GetNext(0, "Focused")
    if !TryGetListViewText(SpoolLV, row, 1, &name)
        return
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
    actions := ["Show Notification", "Run Workflow", "Click Detected Pattern", "Start Spool", "Stop Spool", "Extract OCR", "Set Variable", "Key Chord", "Run Program"]
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
    if !TryGetListViewText(SpoolLV, row, 1, &name)
        return
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
    if !TryGetListViewText(SpoolLV, row, 1, &name) {
        ShowStatus("Select a spool to duplicate", "fail")
        return
    }
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

ExportSelectedSpool(*) {
    global SpoolLV
    row := SpoolLV.GetNext(0, "Focused")
    if !TryGetListViewText(SpoolLV, row, 1, &name) {
        ShowStatus("Select a saved Spool to export", "fail")
        return false
    }
    return ExportSpoolByName(name)
}

ExportSpoolByName(name) {
    global g_Spools
    if !g_Spools.Has(name)
        return false
    selectedFile := FileSelect("S", name . ".mas", "Export Portable Spool", "Macro Automator Spools (*.mas)")
    if selectedFile = ""
        return false
    if !RegExMatch(selectedFile, "i)\.mas$")
        selectedFile .= ".mas"
    output := BuildPortableSpoolText(name, g_Spools[name])
    try {
        if FileExist(selectedFile)
            FileDelete(selectedFile)
        FileAppend(output, selectedFile, "UTF-8")
        SpoolLogAdd("Exported: " . name)
        MsgBox("Spool exported successfully.`n`n" . selectedFile, "Export Complete", "Iconi")
        return true
    } catch as err {
        LogErrorToFile(err, "caught", "Export Spool " . name)
        MsgBox("Spool export failed.`n`n" . err.Message, "Export Failed", "Iconx")
        return false
    }
}

BuildPortableSpoolText(name, spool) {
    global g_Sequences
    fields := ["enabled", "region", "regionCoords", "detectType", "target", "interval", "condition",
        "action", "actionTarget", "extractOCR", "ocrVar", "autoComplete", "completion",
        "completionTarget", "timeout", "mode", "cooldown", "notifTime"]
    output := "; Macro Automator portable Spool. Import from the Spools tab.`r`n[MASPOOL]`r`nformat=1`r`n"
    output .= "name=" . MawEncode(name) . "`r`n"
    for field in fields
        output .= field . "=" . MawEncode(spool.Has(field) ? spool[field] : "") . "`r`n"

    workflowName := spool["action"] = "Run Workflow" ? Trim(spool["actionTarget"]) : ""
    includeWorkflow := workflowName != "" && g_Sequences.Has(workflowName)
    output .= "`r`n[WORKFLOW]`r`nincluded=" . Integer(includeWorkflow) . "`r`n"
    if includeWorkflow {
        seq := g_Sequences[workflowName]
        output .= "name=" . MawEncode(workflowName) . "`r`n"
        output .= "speed=" . (seq.Has("speed") ? seq["speed"] : 1.0) . "`r`n"
        output .= "hotkey=" . MawEncode(seq.Has("hotkey") ? seq["hotkey"] : "") . "`r`n"
        output .= "hotstring=" . MawEncode(seq.Has("hotstring") ? seq["hotstring"] : "") . "`r`n"
        output .= "`r`n[STEPS]`r`n"
        for index, step in seq["steps"] {
            fs := step.Has("failsafe") ? NormalizeStepFailsafe(step["failsafe"]) : Map()
            fsText := fs.Count > 0 ? SerializeFailsafe(fs) : ""
            output .= index . "|" . MawEncode(step["action"]) . "|"
                . MawEncode(step["target"]) . "|" . MawEncode(step["param"]) . "|"
                . (step.Has("enabled") ? Integer(step["enabled"]) : 1) . "|"
                . MawEncode(fsText) . "|"
                . MawEncode(step.Has("qualPattern") ? step["qualPattern"] : "") . "|"
                . MawEncode(step.Has("qualWindow") ? step["qualWindow"] : "") . "`r`n"
        }
    }
    return output . "`r`n[END]`r`n"
}

ImportSpool(*) {
    selectedFile := FileSelect(, , "Import Portable Spool", "Macro Automator Spools (*.mas)")
    if selectedFile = ""
        return ""
    return ImportSpoolFile(selectedFile, true)
}

ImportSpoolFile(selectedFile, showSuccess := true) {
    global g_Spools, g_Sequences, g_SpoolMasterEnabled
    try content := FileRead(selectedFile, "UTF-8")
    catch as err {
        LogErrorToFile(err, "caught", "Read imported Spool")
        MsgBox("Could not read the Spool file.`n`n" . err.Message, "Import Failed", "Iconx")
        return ""
    }

    section := "", spoolName := "", spoolRaw := Map(), workflowRaw := Map(), steps := []
    for rawLine in StrSplit(content, "`n") {
        rawLine := StrReplace(rawLine, "`r")
        marker := Trim(rawLine)
        if marker = "" || SubStr(marker, 1, 1) = ";"
            continue
        if marker = "[MASPOOL]" {
            section := "spool"
            continue
        } else if marker = "[WORKFLOW]" {
            section := "workflow"
            continue
        } else if marker = "[STEPS]" {
            section := "steps"
            continue
        } else if marker = "[END]"
            break

        if section = "steps" {
            parts := StrSplit(rawLine, "|")
            if parts.Length < 4
                continue
            step := Map("action", MawDecode(parts[2]), "target", MawDecode(parts[3]),
                "param", MawDecode(parts[4]),
                "enabled", parts.Length >= 5 && IsNumber(parts[5]) ? Integer(parts[5]) != 0 : true)
            if parts.Length >= 6 && MawDecode(parts[6]) != ""
                step["failsafe"] := DeserializeFailsafe(MawDecode(parts[6]))
            if parts.Length >= 7 && MawDecode(parts[7]) != ""
                step["qualPattern"] := MawDecode(parts[7])
            if parts.Length >= 8 && MawDecode(parts[8]) != ""
                step["qualWindow"] := MawDecode(parts[8])
            steps.Push(step)
            continue
        }

        equalsPos := InStr(rawLine, "=")
        if !equalsPos
            continue
        key := Trim(SubStr(rawLine, 1, equalsPos - 1))
        value := MawDecode(SubStr(rawLine, equalsPos + 1))
        if section = "spool" {
            if key = "name"
                spoolName := Trim(value)
            else if key != "format"
                spoolRaw[key] := value
        } else if section = "workflow"
            workflowRaw[key] := value
    }

    if spoolName = "" {
        MsgBox("This is not a valid .mas Spool file: [MASPOOL] and name are required.", "Import Failed", "Icon!")
        return ""
    }
    spool := Map(
        "enabled", SpoolInteger(spoolRaw.Has("enabled") ? spoolRaw["enabled"] : 1, 1),
        "region", spoolRaw.Has("region") ? spoolRaw["region"] : "Full Screen",
        "regionCoords", spoolRaw.Has("regionCoords") ? spoolRaw["regionCoords"] : "",
        "detectType", spoolRaw.Has("detectType") ? spoolRaw["detectType"] : "Pattern Match",
        "target", spoolRaw.Has("target") ? spoolRaw["target"] : "",
        "interval", SpoolInteger(spoolRaw.Has("interval") ? spoolRaw["interval"] : 500, 500, 100),
        "condition", spoolRaw.Has("condition") ? spoolRaw["condition"] : "Found",
        "action", spoolRaw.Has("action") ? spoolRaw["action"] : "Show Notification",
        "actionTarget", spoolRaw.Has("actionTarget") ? spoolRaw["actionTarget"] : "",
        "extractOCR", SpoolInteger(spoolRaw.Has("extractOCR") ? spoolRaw["extractOCR"] : 0),
        "ocrVar", spoolRaw.Has("ocrVar") ? spoolRaw["ocrVar"] : "",
        "autoComplete", SpoolInteger(spoolRaw.Has("autoComplete") ? spoolRaw["autoComplete"] : 0),
        "completion", spoolRaw.Has("completion") ? spoolRaw["completion"] : "Timeout",
        "completionTarget", spoolRaw.Has("completionTarget") ? spoolRaw["completionTarget"] : "",
        "timeout", SpoolInteger(spoolRaw.Has("timeout") ? spoolRaw["timeout"] : 0),
        "mode", spoolRaw.Has("mode") ? spoolRaw["mode"] : "Cooldown",
        "cooldown", SpoolInteger(spoolRaw.Has("cooldown") ? spoolRaw["cooldown"] : 5, 5, 1),
        "notifTime", SpoolInteger(spoolRaw.Has("notifTime") ? spoolRaw["notifTime"] : 5, 5, 1)
    )

    embeddedWorkflow := workflowRaw.Has("included") && SpoolInteger(workflowRaw["included"], 0) && steps.Length > 0
    if embeddedWorkflow {
        workflowName := workflowRaw.Has("name") ? Trim(workflowRaw["name"]) : spool["actionTarget"]
        if workflowName = "" {
            MsgBox("The embedded workflow has no name.", "Import Failed", "Icon!")
            return ""
        }
        if g_Sequences.Has(workflowName)
            && MsgBox("Workflow '" . workflowName . "' already exists.`n`nOverwrite it with the embedded copy?", "Workflow Exists", "YesNo Icon!") = "Yes"
            UnregisterSequenceTriggers(workflowName)
        else if g_Sequences.Has(workflowName) {
            ; Keep the existing workflow and still import the Spool reference.
            embeddedWorkflow := false
        }
        if embeddedWorkflow {
            seq := Map("steps", steps, "speed", workflowRaw.Has("speed") && IsNumber(workflowRaw["speed"]) ? Float(workflowRaw["speed"]) : 1.0)
            if workflowRaw.Has("hotkey") && workflowRaw["hotkey"] != ""
                seq["hotkey"] := workflowRaw["hotkey"]
            if workflowRaw.Has("hotstring") && workflowRaw["hotstring"] != ""
                seq["hotstring"] := workflowRaw["hotstring"]
            g_Sequences[workflowName] := seq
            if !SaveSequences(true)
                return ""
            RegisterSequenceTriggers(workflowName)
            RefreshSeqLV()
        }
    }

    if !ValidateSpoolDefinition(spool, &errorMessage) {
        MsgBox(errorMessage, "Import Failed", "Icon!")
        return ""
    }
    if g_Spools.Has(spoolName)
        && MsgBox("Spool '" . spoolName . "' already exists.`n`nOverwrite it?", "Spool Exists", "YesNo Icon!") != "Yes"
        return ""
    if g_Spools.Has(spoolName)
        StopSpool(spoolName)
    g_Spools[spoolName] := spool
    SaveSpools()
    RefreshSpoolLV()
    EditSpoolByName(spoolName)
    if spool["enabled"] && g_SpoolMasterEnabled
        StartSpool(spoolName)
    SpoolLogAdd("Imported: " . spoolName . (embeddedWorkflow ? " + workflow" : ""))
    if showSuccess
        MsgBox("Spool imported successfully.`n`nSpool: " . spoolName
            . (workflowRaw.Has("included") && SpoolInteger(workflowRaw["included"], 0) ? "`nWorkflow: " . spool["actionTarget"] : "")
            . "`n`nUse Test Trigger for an immediate end-to-end check, or Start to begin monitoring.", "Import Complete", "Iconi")
    return spoolName
}

StartSelectedSpool(*) {
    global SpoolLV
    row := SpoolLV.GetNext(0, "Focused")
    if !TryGetListViewText(SpoolLV, row, 1, &name)
        return
    StartSpool(name)
}

TestSelectedSpool(*) {
    global SpoolLV
    row := SpoolLV.GetNext(0, "Focused")
    if !TryGetListViewText(SpoolLV, row, 1, &name) {
        ShowStatus("Select a saved Spool to test", "fail")
        return
    }
    ExecuteSpoolCheck(name, true)
}

StopSelectedSpool(*) {
    global SpoolLV
    row := SpoolLV.GetNext(0, "Focused")
    if !TryGetListViewText(SpoolLV, row, 1, &name)
        return
    StopSpool(name)
}

RefreshSpoolLV() {
    global g_Spools, g_ActiveSpools, g_SpoolLastStatus, SpoolLV

    SpoolLV.Delete()
    for name, spool in g_Spools {
        status := g_ActiveSpools.Has(name) ? "Running" : "Stopped"
        if g_SpoolLastStatus.Has(name) && g_SpoolLastStatus[name] != status
            status .= ": " . g_SpoolLastStatus[name]
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

Tab_Spools_Build() {
    global NotificationLV, OCRVarsLV, SpoolActionDD, SpoolActionHelp, SpoolActionTargetCombo, SpoolAutoCompleteChk, SpoolCompletionDD, SpoolCompletionTargetCombo, SpoolConditionDD, SpoolCooldownEdit, SpoolDetectDD, SpoolEnabledChk, SpoolExtractOCRChk, SpoolIntervalEdit, SpoolLogEdit, SpoolLV, SpoolMasterToggle, SpoolModeDD, SpoolNameEdit, SpoolNotifTimeEdit, SpoolOCRVarEdit, SpoolRegionDD, SpoolRegionText, SpoolSeqHelp, SpoolTargetCombo, SpoolTimeoutEdit
    TabCtrl.UseTab(4)

    ; --- SPOOL MANAGER HEADER ---
    MainGui.Add("GroupBox", "x15 y50 w860 h85", "Spool Manager - Detect -> Respond -> Repeat")
    MainGui.Add("Text", "x25 y68 w820", "Spools monitor the screen, then click the detected pattern or launch a saved Workflow-tab workflow.")
    MainGui.Add("Text", "x25 y83 w700 cGray", "Use cases: Weave notifications → update RevolutionHR, Coding tree → schedule reminder, Auto-capitalize names")

    SpoolMasterToggle := MainGui.Add("CheckBox", "x25 y103 w150 vSpoolMasterToggle", "🔄 Master Enable")
    SpoolMasterToggle.OnEvent("Click", ToggleSpoolMaster)
    MainGui.Add("Text", "x180 y104 w100 cGreen vSpoolMasterStatus", "STOPPED")
    MainGui.Add("Button", "x290 y100 w80 h22", "Start All").OnEvent("Click", StartAllSpools)
    MainGui.Add("Button", "x375 y100 w80 h22", "Stop All").OnEvent("Click", StopAllSpools)
    MainGui.Add("Text", "x480 y104 w100 vActiveSpoolCount", "Active: 0")
    MainGui.Add("Button", "x600 y100 w80 h22", "Refresh").OnEvent("Click", (*) => RefreshSpoolLV())

    ; --- DEFINE NEW SPOOL ---
    MainGui.Add("GroupBox", "x15 y140 w430 h380", "1. Name and detection -> 2. Response -> 3. Repetition")

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
    MainGui.Add("GroupBox", "x25 y370 w405 h50", "3. Repeat behavior after a successful trigger")
    SpoolModeDD := MainGui.Add("DropDownList", "x35 y388 w100 vSpoolMode",
        ["Continuous", "One-Shot", "Cooldown"])
    SpoolModeDD.Choose(3)
    SpoolModeDD.OnEvent("Change", OnSpoolModeChange)

    MainGui.Add("Text", "x145 y391 vSpoolCooldownLabel", "Cooldown:")
    SpoolCooldownEdit := MainGui.Add("Edit", "x200 y388 w40 vSpoolCooldown Number", "5")
    MainGui.Add("Text", "x245 y391", "sec")
    MainGui.Add("Text", "x280 y391 w140 cGray vSpoolModeHelp", "(re-check after delay)")

    ; === ACTION WHEN TRIGGERED ===
    MainGui.Add("GroupBox", "x25 y280 w405 h85", "2. Response when detected")
    MainGui.Add("Text", "x35 y298", "Do:")
    SpoolActionDD := MainGui.Add("DropDownList", "x55 yp-3 w165 vSpoolAction",
        ["Show Notification", "Run Workflow", "Click Detected Pattern", "Start Spool", "Stop Spool", "Extract OCR", "Set Variable", "Key Chord", "Run Program"])
    SpoolActionDD.Choose(1)
    SpoolActionDD.OnEvent("Change", OnSpoolActionChange)

    MainGui.Add("Text", "x225 y298", "Target:")
    SpoolActionTargetCombo := MainGui.Add("ComboBox", "x265 yp-3 w125 vSpoolActionTarget")
    MainGui.Add("Button", "x395 y295 w28 h22", "↻").OnEvent("Click", (*) => OnSpoolActionChange())
    SpoolActionHelp := MainGui.Add("Text", "x35 y320 w385 cGray vSpoolActionHelp", "Select a response; workflows come directly from the first tab.")

    ; Notification timeout (shows when action is Show Notification)
    MainGui.Add("Text", "x330 y343 vSpoolNotifLabel", "Notice sec:")
    SpoolNotifTimeEdit := MainGui.Add("Edit", "x395 y340 w30 vSpoolNotifTime Number", "5")

    ; OCR extraction checkbox
    SpoolExtractOCRChk := MainGui.Add("CheckBox", "x35 y342 vSpoolExtractOCR", "Also extract OCR to:")
    SpoolOCRVarEdit := MainGui.Add("Edit", "x160 y339 w70 vSpoolOCRVar", "")

    ; === AUTO-STOP CONDITION ===
    MainGui.Add("GroupBox", "x25 y425 w405 h65", "Optional auto-stop")
    SpoolAutoCompleteChk := MainGui.Add("CheckBox", "x35 y443 vSpoolAutoComplete", "Stop spool when:")
    SpoolCompletionDD := MainGui.Add("DropDownList", "x145 y440 w90 vSpoolCompletion",
        ["Pattern Found", "Pattern Gone", "OCR Contains", "Timeout", "Variable Set"])
    SpoolCompletionDD.Choose(1)
    SpoolCompletionTargetCombo := MainGui.Add("ComboBox", "x240 y440 w115 vSpoolCompletionTarget")
    MainGui.Add("Text", "x360 y443", "sec:")
    SpoolTimeoutEdit := MainGui.Add("Edit", "x390 y440 w30 vSpoolTimeout Number", "0")
    MainGui.Add("Text", "x35 y465 cGray", "Use One-Shot for one run, or Cooldown to loop safely while detection remains true.")

    ; Spool Buttons
    MainGui.Add("Button", "x25 y495 w80 h24", "Save Spool").OnEvent("Click", SaveSpool)
    MainGui.Add("Button", "x110 y495 w60 h24", "Clear").OnEvent("Click", ClearSpoolForm)
    MainGui.Add("Button", "x175 y495 w95 h24 cGreen", "Test Trigger").OnEvent("Click", TestSpoolOnce)
    MainGui.Add("Button", "x275 y495 w90 h24 cBlue", "Show Match").OnEvent("Click", TestSpoolPattern)

    ; --- SAVED SPOOLS LIST ---
    MainGui.Add("GroupBox", "x455 y140 w420 h255", "Saved Spools (select one, then Start or Test Trigger)")
    SpoolLV := MainGui.Add("ListView", "x465 y158 w400 h190 Grid Checked NoSortHdr vSpoolLV",
        ["Name", "Detect", "Action", "Mode", "Status"])
    SpoolLV.ModifyCol(1, 110)
    SpoolLV.ModifyCol(2, 80)
    SpoolLV.ModifyCol(3, 95)
    SpoolLV.ModifyCol(4, 55)
    SpoolLV.ModifyCol(5, 110)
    SpoolLV.OnEvent("ItemSelect", OnSpoolSelect)
    SpoolLV.OnEvent("ContextMenu", OnSpoolContextMenu)
    SpoolLV.OnEvent("ItemCheck", OnSpoolCheck)

    MainGui.Add("Button", "x465 y355 w45 h22", "Edit").OnEvent("Click", EditSpool)
    MainGui.Add("Button", "x515 y355 w50 h22", "Start").OnEvent("Click", StartSelectedSpool)
    MainGui.Add("Button", "x570 y355 w45 h22", "Stop").OnEvent("Click", StopSelectedSpool)
    MainGui.Add("Button", "x620 y355 w75 h22", "Test Trigger").OnEvent("Click", TestSelectedSpool)
    MainGui.Add("Button", "x700 y355 w55 h22", "Delete").OnEvent("Click", DeleteSpool)
    MainGui.Add("Button", "x760 y355 w50 h22", "Copy").OnEvent("Click", DuplicateSpool)
    MainGui.Add("Button", "x465 y378 w82 h22", "Import .mas").OnEvent("Click", ImportSpool)
    MainGui.Add("Button", "x552 y378 w82 h22", "Export .mas").OnEvent("Click", ExportSelectedSpool)
    MainGui.Add("Text", "x640 y381 w225 cGray", ".mas includes its linked workflow")

    ; --- ACTIVE NOTIFICATIONS ---
    MainGui.Add("GroupBox", "x455 y405 w420 h85", "Active Notifications")
    NotificationLV := MainGui.Add("ListView", "x465 y423 w400 h38 Grid NoSortHdr vNotificationLV",
        ["ID", "Title", "Remaining", "Spool"])
    NotificationLV.ModifyCol(1, 35)
    NotificationLV.ModifyCol(2, 180)
    NotificationLV.ModifyCol(3, 65)
    NotificationLV.ModifyCol(4, 100)

    MainGui.Add("Button", "x465 y466 w70 h20", "Dismiss All").OnEvent("Click", DismissAllNotifications)
    MainGui.Add("Button", "x540 y466 w50 h20", "View").OnEvent("Click", ViewNotification)
    MainGui.Add("Text", "x600 y469 w200 cGray", "Notifications auto-dismiss")

    ; --- OCR VARIABLES ---
    MainGui.Add("GroupBox", "x455 y495 w200 h95", "Extracted Variables")
    OCRVarsLV := MainGui.Add("ListView", "x465 y513 w180 h50 Grid NoSortHdr vOCRVarsLV",
        ["Variable", "Value"])
    OCRVarsLV.ModifyCol(1, 70)
    OCRVarsLV.ModifyCol(2, 100)

    MainGui.Add("Button", "x465 y568 w50 h18", "Clear").OnEvent("Click", ClearOCRVars)
    MainGui.Add("Button", "x520 y568 w50 h18", "Use").OnEvent("Click", UseOCRVar)
    MainGui.Add("Button", "x575 y568 w60 h18", "Refresh").OnEvent("Click", (*) => RefreshOCRVarsLV())

    ; --- SPOOL LOG ---
    MainGui.Add("GroupBox", "x665 y495 w210 h95", "Activity Log (also saved to file)")
    SpoolLogEdit := MainGui.Add("Edit", "x675 y513 w190 h50 ReadOnly Multi VScroll vSpoolLog", "")
    MainGui.Add("Button", "x815 y568 w50 h18", "Clear").OnEvent("Click", ClearSpoolLog)
    MainGui.Add("GroupBox", "x455 y595 w420 h75", "How workflow looping works")
    MainGui.Add("Text", "x465 y613 w400 h50", "Run Workflow + One-Shot = run once and stop.`nRun Workflow + Cooldown = run again while detected, after the delay.`nContinuous = run every interval; use carefully for clicking.")


}

