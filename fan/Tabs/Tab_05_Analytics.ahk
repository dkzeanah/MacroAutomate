; ===============================================================================
; Tabs\Tab_05_Analytics.ahk
; TAB 5 Analytics: full recording, hotspots, taskbar index, logs
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================



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

Tab_Analytics_Build() {
    global AnalyticsText, HotspotsLV, TaskbarLV
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

