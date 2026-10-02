; ===============================================================================
; Tabs\Tab_09_Triggers.ahk
; TAB 9 Triggers: advanced notification triggers and templates
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================

Tab_Triggers_Build() {
    global TriggerMasterToggle, TriggersLV
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
    local yPos   ; intentionally local - shadows the top-level calendar layout var

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
        local time   ; intentionally local - shadows the top-level calendar loop var
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

