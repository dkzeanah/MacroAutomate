; ===============================================================================
; Core\_Helpers.ahk
; Shared helpers: logging, overlays, taskbar index, tray menu, verified input, window list, GUI resize
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================



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

; ListView context-menu events can report -1/0 for the header or blank space.
; Centralize validation so no GUI event calls GetText with an invalid row.
TryGetListViewText(LV, rowNumber, columnNumber, &value) {
    value := ""
    if !IsNumber(rowNumber)
        return false
    rowNumber := Integer(rowNumber)
    if rowNumber < 1
        return false
    try {
        if rowNumber > LV.GetCount()
            return false
        value := LV.GetText(rowNumber, columnNumber)
    } catch {
        value := ""
        return false
    }
    return value != ""
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

    try FanFileAppend(entry, ERROR_LOG_FILE, "UTF-8")
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
    if !FanFileExist(ERROR_LOG_FILE)
        FanFileAppend("Macro Automator runtime error log`r`nCreated: " . FormatTime(, "yyyy-MM-dd HH:mm:ss") . "`r`n", ERROR_LOG_FILE, "UTF-8")
    FanFile_View(ERROR_LOG_FILE)
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
        TrackToolTip(text, x, y)
    else
        TrackToolTip(text)
    SetTimer(() => TrackToolTip(), -duration)
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
    try {
        result := TaskbarKnowledge_Learn()
        ShowStatus("Learned " . result["count"] . " taskbar targets without activating applications. Open Explain learning to inspect them.","ok")
        LearningLab_Open()
    } catch as taskbarError
        ShowStatus("Taskbar capture failed: " . taskbarError.Message,"fail")
}

; Retained for old integrations; the normal Index Taskbar button uses the passive learner.
IndexTaskbarLegacy() {
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
        if FanFileExist(TASKBAR_FILE)
            FanFileDelete(TASKBAR_FILE)

        for i, app in g_TaskbarApps {
            FanIniWrite(app["position"], TASKBAR_FILE, "App" . i, "Position")
            FanIniWrite(app["hotkey"], TASKBAR_FILE, "App" . i, "Hotkey")
            FanIniWrite(app["hotkeyDisplay"], TASKBAR_FILE, "App" . i, "HotkeyDisplay")
            FanIniWrite(app["title"], TASKBAR_FILE, "App" . i, "Title")
            FanIniWrite(app["exe"], TASKBAR_FILE, "App" . i, "Exe")
            FanIniWrite(app["class"], TASKBAR_FILE, "App" . i, "Class")
        }
        FanIniWrite(g_TaskbarApps.Length, TASKBAR_FILE, "Meta", "Count")
    }
}

LoadTaskbarIndex() {
    global g_TaskbarApps, TASKBAR_FILE
    g_TaskbarApps := []

    if !FanFileExist(TASKBAR_FILE)
        return

    count := FanIniRead(TASKBAR_FILE, "Meta", "Count", 0)

    Loop count {
        pos := FanIniRead(TASKBAR_FILE, "App" . A_Index, "Position", A_Index)
        hotkey := FanIniRead(TASKBAR_FILE, "App" . A_Index, "Hotkey", "")
        hotkeyDisplay := FanIniRead(TASKBAR_FILE, "App" . A_Index, "HotkeyDisplay", "")
        title := FanIniRead(TASKBAR_FILE, "App" . A_Index, "Title", "")
        exe := FanIniRead(TASKBAR_FILE, "App" . A_Index, "Exe", "")
        class := FanIniRead(TASKBAR_FILE, "App" . A_Index, "Class", "")

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
    TrackToolTip(prefix . msg)
    duration := g_Settings["TooltipDuration"]
    if type = "wait"
        duration := 10000  ; Wait messages stay longer
    else if type = "ok" || type = "fail"
        duration := g_Settings["TooltipDuration"]
    SetTimer(() => TrackToolTip(), -duration)
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
    if LearningValidation_PrimaryRegion(x, y, w, h) {
        ; Explicit live validation uses hollow click-through targets on every
        ; display; the secondary panel still retains the evidence explanation.
        DeepActivity_Target(Map("x",x,"y",y,"w",w,"h",h),label != "" ? label : "Automation target")
        LearningValidation_Event("Target", style = "error" ? "error" : "observed", label != "" ? label : style,
            Map("x",x,"y",y,"w",w,"h",h))
        return 0
    }

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
    TrackToolTip(text, x + 15, y + 15)
    if duration > 0
        SetTimer(() => TrackToolTip(), -duration)
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
    return ["demo:lab", "notepad.exe", "calc.exe", "mspaint.exe", "explorer.exe", "cmd.exe",
            "powershell.exe", "chrome.exe", "firefox.exe", "msedge.exe", "code.exe"]
}

; Full, untruncated window titles (no exe suffix), de-duplicated. Suitable for
; direct WinActivate / window: matching without any post-processing.
GetWindowTitlesFull() {
    titles := []
    seen := Map()
    for hwnd in WinGetList() {
        title := ""
        try title := WinGetTitle(hwnd)
        if (title = "" || title = "Program Manager" || seen.Has(title))
            continue
        seen[title] := true
        titles.Push(title)
    }
    return titles
}

; Strip the "  [exe.exe]" suffix that GetWindowList appends for display, leaving
; just the window title suitable for WinActivate / window: matching.
CleanWindowTitle(displayText) {
    p := InStr(displayText, "  [")
    if p
        displayText := SubStr(displayText, 1, p - 1)
    return Trim(displayText)
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
        DeepActivity_Before("window_activate","ahk_class Shell_TrayWnd")
        Send("#" . key)
        Sleep(200)
        ShowStatus("Sent Win+" . key, "ok")
        return true
    }

    Loop maxRetries {
        if WinExist(windowIdentifier) {
            DeepActivity_Before("window_activate",windowIdentifier)
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
                    DeepActivity_Before("window_activate","ahk_id " . hwnd)
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
            DeepActivity_Before("window_activate","ahk_exe " . windowIdentifier)
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

MoveMouseVerified(x, y, speed := 5, maxRetries := 3, feedback := true) {
    if feedback
        DeepActivity_Before("mouse_move",x . "," . y)
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

    DeepActivity_Before("mouse_click",x . "," . y)
    if !MoveMouseVerified(x, y,5,3,false)
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
    DeepActivity_Before("key_send")
    Sleep(g_Settings["PreActionDelay"])
    Send(keys)
    Sleep(g_Settings["PostActionDelay"])
    ShowStatus("Sent: " . keys, "ok")
    return true
}

TypeTextVerified(text) {
    global g_Settings
    DeepActivity_Before("text_type")
    Sleep(g_Settings["PreActionDelay"])
    SendText(text)
    Sleep(g_Settings["PostActionDelay"])
    return true
}

SetClipboardVerified(text) {
    global g_ExtractedData

    if StrLower(Trim(text)) = "demo:restore"
        return RestoreWorkflowDemoState()

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
A_TrayMenu.Add("⚙ Pin to Taskbar (Always Show)", OpenTrayPinningSettings)
A_TrayMenu.Add()
A_TrayMenu.Add("ABORT", AbortSequence)
UsagePredictor_AddTrayMenu()
A_TrayMenu.Add("Reload", (*) => Reload())
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Show/Hide"
SetTrayMenuItemIcons()
A_IconHidden := false   ; never auto-hide the tray icon
A_IconTip := "Macro Automator v9 - Vision Scout + Usage Predictor"
try SetTrayIcon()

; Native AHK menus support a per-item icon but not a per-item text/background
; color. Windows' own icon library keeps these crisp at the user's DPI and
; avoids shipping a loose set of .ico files with the script.
SetTrayMenuItemIcons() {
    shellIcons := A_WinDir . "\System32\Shell32.dll"
    try A_TrayMenu.SetIcon("Show/Hide", shellIcons, 14)              ; globe/app
    try A_TrayMenu.SetIcon("Definition Mode Help", shellIcons, 24)  ; help
    try A_TrayMenu.SetIcon("Always On Top", shellIcons, 44)         ; marker
    try A_TrayMenu.SetIcon("⚙ Pin to Taskbar (Always Show)", shellIcons, 46)
    try A_TrayMenu.SetIcon("ABORT", shellIcons, 110)                ; warning/stop
    try A_TrayMenu.SetIcon("Reload", shellIcons, 239)               ; refresh
    try A_TrayMenu.SetIcon("Exit", shellIcons, 28)                  ; power/exit
}

; Same proven approach as globalcoder-v7 (which uses Shell32.dll index 14, the
; globe): load an icon straight out of a system DLL. Index 43 is the bright
; YELLOW LIGHTBULB - unique and instantly visible among the tray's usual
; white/blue icons, and checked at runtime so older Windows builds that lack it
; simply keep the default icon instead of showing nothing.
SetTrayIcon() {
    iconPath := A_WinDir . "\System32\Shell32.dll"
    hIcon := 0
    n := DllCall("shell32\ExtractIconExW", "Str", iconPath, "Int", 43, "Ptr", 0, "Ptr*", &hIcon, "Int", 1, "Int")
    if n > 0 && hIcon {
        DllCall("DestroyIcon", "UPtr", hIcon)
        try TraySetIcon(iconPath, 43, true)   ; freeze so later updates keep it
    }
}

; Opens the Windows page where this app can be pinned into the visible corner
; of the taskbar instead of the hidden-arrow overflow menu.
OpenTrayPinningSettings(*) {
    ver := StrSplit(A_OSVersion, ".")
    build := ver.Length >= 3 ? Integer(ver[3]) : 0
    if build >= 22000 {
        ; Windows 11: Settings > Personalization > Taskbar > Other system tray icons
        try Run("ms-settings:taskbar")
    } else {
        ; Windows 10: classic "Notification Area Icons" list
        try Run("rundll32.exe shell32.dll,Options_RunDLL 5")
    }
    MsgBoxTop("Find `"Macro Automator v9`" in the list and switch it ON.`n`nWindows decides which icons sit in the corner vs the hidden-arrow menu. Once ON here, the yellow lightbulb icon stays front and center permanently.", "Pin the bulb to the taskbar")
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
        file := FanFileOpen(COORDS_FILE, "w", "UTF-8")
        file.WriteLine("Name,X,Y,EndX,EndY,Type")
        for name, c in g_Coordinates
            file.WriteLine(name . "," . c["x"] . "," . c["y"] . "," . c["endX"] . "," . c["endY"] . "," . c["type"])
        file.Close()
    }
}

LoadCoordinates() {
    global g_Coordinates, COORDS_FILE
    if !FanFileExist(COORDS_FILE)
        return
    g_Coordinates := Map()
    lineNum := 0
    for line in FanFile_Lines(COORDS_FILE) {
        lineNum++
        if lineNum = 1 || line = ""
            continue
        p := StrSplit(line, ",")
        if p.Length >= 6
            g_Coordinates[p[1]] := Map("x", Integer(p[2]), "y", Integer(p[3]), "endX", p[4] = "" ? "" : Integer(p[4]), "endY", p[5] = "" ? "" : Integer(p[5]), "type", p[6])
    }
}


; ═══════════════════════════════════════════════════════════════════════════════
; END OF NEW FEATURES v4.1
; ═══════════════════════════════════════════════════════════════════════════════


GuiResize(thisGui, minMax, w, h) {
    if minMax = -1
        return
    try TabCtrl.Move(, , w - 10, h - 75)
    ; Tabs that lay themselves out dynamically get told the new size.
    try SnapRec_Layout(w - 20, h - 110)
    ; Tabs that were laid out by hand get the inferred anchor treatment.
    try AutoFlow_Resize(w - 10, h - 75)
    try DeepBridge_Resize(thisGui, minMax, w, h)
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

InitializeInstructions() {
    global INSTRUCTIONS_FILE
    if FanFileExist(INSTRUCTIONS_FILE)
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
        FanFileAppend(instructions, INSTRUCTIONS_FILE, "UTF-8")
    } catch as err {
        MsgBox("Failed to create instructions file: " . err.Message)
    }
}



; ═══════════════════════════════════════════════════════════════════════════════
; V5.0: SHOW INSTRUCTIONS FILE
; ═══════════════════════════════════════════════════════════════════════════════

ShowInstructionsFile(*) {
    global INSTRUCTIONS_FILE, APP_ROOT
    ; Prefer the current fan guide; keep the legacy instructions as a fallback.
    for guideDir in [A_ScriptDir, APP_ROOT . "\fan"] {
        for extension in ["html", "md"] {
            guidePath := guideDir . "\AUTOMATION_USER_GUIDE." . extension
            if FanFileExist(guidePath) {
                try Run(guidePath)
                catch
                    Run('notepad.exe "' . guidePath . '"')
                return
            }
        }
    }
    if FanFileExist(INSTRUCTIONS_FILE) {
        Run(INSTRUCTIONS_FILE)
    } else {
        MsgBox("Instructions file not found. Recreating...")
        InitializeInstructions()
        Run(INSTRUCTIONS_FILE)
    }
}

