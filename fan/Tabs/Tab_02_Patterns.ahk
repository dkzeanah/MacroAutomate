#Include %A_LineFile%\..\..\..\lib\WorkflowPatterns.ahk
; ===============================================================================
; Tabs\Tab_02_Patterns.ahk
; TAB 2 Patterns: definition mode, capture, preview, FindText helpers
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================

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
                TrackToolTip()
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
    TrackToolTip(tip, x + 20, y + 20)
    SetTimer(() => TrackToolTip(), -g_Settings["PreviewTooltipDuration"])
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
    TrackToolTip()
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

    TrackToolTip(tip, x + 20, y + 20)
    SetTimer(() => TrackToolTip(), -g_Settings["PreviewTooltipDuration"])
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
    screenshotPath := Photo_Path(patternData.Get("screenshot", ""))
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

    if screenshotPath != "" && FanFileExist(screenshotPath) {
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

; FindPatternOnScreen is shared with native fixtures in lib/WorkflowPatterns.ahk.


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
        LearningValidation_Match(ok[1].mx, ok[1].my)
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

; FindAndClickPattern is shared with native fixtures in lib/WorkflowPatterns.ahk.


; ─────────────────────────────────────────────────────────────────────────────
; FindClickScrollLoop - repeatedly find a pattern and click every instance,
; scrolling down to reveal more, until the list is exhausted or a cap is hit.
;
; Designed for "click all N buttons" pages where each click changes the clicked
; button's own appearance, so a fresh full-search always lands on the next
; un-clicked button. Stops when either:
;   * maxScrolls empty scrolls happen in a row (reached the bottom), or
;   * maxClicks clicks have been performed, or
;   * ESC is pressed (g_AbortSequence).
;
; optionsStr is a semicolon list of key=value pairs. All are optional:
;   win=Title       lock to this window (activate + search only inside it + scroll into it)
;   scroll=-3       wheel notches per scroll; negative = down, positive = up
;   settle=600      ms to wait AFTER each click before searching again
;   scrollSettle=   ms to wait after each scroll (defaults to settle)
;   maxClicks=90    hard cap on total clicks
;   maxScrolls=6    consecutive empty scrolls that mean "end of list"
;   button=Left     Left / Right for the click
;   clicks=1        click count per find (1=single, 2=double, ...)
;   top=            home = Ctrl+Home to jump to top first; or a number = that many wheel-ups first
;   focus=          x,y (or "center") to click once at the start to focus the window
;   tol=            FindText tolerance override (default = Settings tolerance)
; ─────────────────────────────────────────────────────────────────────────────
FindClickScrollLoop(patternName, optionsStr := "") {
    global g_Settings, g_AbortSequence, g_LastClickX, g_LastClickY, g_Patterns

    CoordMode("Mouse", "Screen")
    CoordMode("Pixel", "Screen")

    patternName := Trim(StrReplace(patternName, "[P] ", ""))
    if !g_Patterns.Has(patternName) {
        ShowStatus("Find & Click Loop: unknown pattern '" . patternName . "'", "fail")
        return false
    }
    patternText := g_Patterns[patternName]["text"]

    ; ---- Parse options with defaults ----
    ; Blank placeholders (e.g. "scrollSettle=") count as "not set" and fall back
    ; to the default, so the pre-filled options string never causes an error.
    opt := ParseLoopOptions(optionsStr)
    winTitle    := LoopOptStr(opt, "win", "")
    scrollAmt   := LoopOptInt(opt, "scroll", -3)
    settleMs    := LoopOptInt(opt, "settle", 600)
    scrollMs    := LoopOptInt(opt, "scrollsettle", settleMs)
    maxClicks   := LoopOptInt(opt, "maxclicks", 90)
    maxScrolls  := LoopOptInt(opt, "maxscrolls", 6)
    button      := LoopOptStr(opt, "button", "Left")
    clickCount  := LoopOptInt(opt, "clicks", 1)
    topOpt      := LoopOptStr(opt, "top", "")
    focusOpt    := LoopOptStr(opt, "focus", "")
    tol         := LoopOptInt(opt, "tol", g_Settings["FindTextTolerance"])
    popupTitle  := LoopOptStr(opt, "popup", "")
    popupDo     := LoopOptStr(opt, "popupdo", "enter")

    ; ---- Resolve search region (window rect, or full screen) ----
    if winTitle != "" {
        if !WinExist(winTitle) {
            ShowStatus("Find & Click Loop: window not found '" . winTitle . "'", "fail")
            return false
        }
        try WinActivate(winTitle)
        try WinWaitActive(winTitle, , 2)
        WinGetPos(&wx, &wy, &ww, &wh, winTitle)
        rx1 := wx, ry1 := wy, rx2 := wx + ww, ry2 := wy + wh
    } else {
        rx1 := 0, ry1 := 0, rx2 := A_ScreenWidth, ry2 := A_ScreenHeight
    }
    centerX := (rx1 + rx2) // 2
    centerY := (ry1 + ry2) // 2

    ; ---- Optional: jump to the top of the list first ----
    if topOpt != "" {
        MouseMove(centerX, centerY, 2)
        Sleep(120)
        if (StrLower(topOpt) = "home") {
            Send("^{Home}")
        } else if IsNumber(topOpt) {
            Loop Integer(topOpt)
                Click("WheelUp", , , 1)
        }
        Sleep(scrollMs)
    }

    ; ---- Optional: click once to focus the window/page ----
    if focusOpt != "" {
        fx := centerX, fy := centerY
        if (StrLower(focusOpt) != "center") && InStr(focusOpt, ",") {
            parts := StrSplit(focusOpt, ",")
            fx := Integer(Trim(parts[1])), fy := Integer(Trim(parts[2]))
        }
        Click(fx, fy)
        Sleep(settleMs)
    }

    clicksDone := 0
    dryScrolls := 0
    ShowStatus("Find & Click Loop: '" . patternName . "' (max " . maxClicks . ")", "wait")

    Loop {
        if g_AbortSequence {
            ShowStatus("Find & Click Loop: aborted at " . clicksDone . " clicks", "info")
            return true
        }

        ; If the interrupting popup (e.g. a Save dialog) is up, deal with it first
        ; and restart this iteration so the flow is not thrown off.
        if popupTitle != "" && HandleLoopPopup(popupTitle, popupDo) {
            if winTitle != ""
                try WinActivate(winTitle)
            Sleep(settleMs)
            continue
        }

        ok := FindText(&fx, &fy, rx1, ry1, rx2, ry2, tol, tol, patternText)
        found := (ok && ok.Length > 0)

        if found {
            cx := ok[1].mx, cy := ok[1].my

            if g_Settings["FailsafeCheckCloseButton"] && IsNearCloseButton(cx, cy) {
                ShowStatus("Find & Click Loop: skipped match near close button", "retry")
                ; treat as an empty view so we scroll past it instead of clicking
                found := false
            } else {
                Sleep(g_Settings["PreActionDelay"])
                MouseMove(cx, cy, 5)
                Sleep(40)
                Click(cx, cy, button, clickCount)
                g_LastClickX := cx, g_LastClickY := cy
                clicksDone += 1
                dryScrolls := 0
                ShowStatus("Find & Click Loop: clicked " . clicksDone . "/" . maxClicks . " @ " . cx . "," . cy, "ok")
                Sleep(settleMs)
                if clicksDone >= maxClicks {
                    ShowStatus("Find & Click Loop: reached maxClicks (" . maxClicks . ")", "ok")
                    return true
                }
                continue
            }
        }

        ; Nothing clickable in the current view -> scroll to reveal more
        if dryScrolls >= maxScrolls {
            ShowStatus("Find & Click Loop: done - " . clicksDone . " clicked, list exhausted", "ok")
            return true
        }
        MouseMove(centerX, centerY, 2)   ; ensure the wheel targets the intended window
        Sleep(40)
        Click(scrollAmt > 0 ? "WheelUp" : "WheelDown", , , Abs(scrollAmt))
        dryScrolls += 1
        ShowStatus("Find & Click Loop: scrolling (" . dryScrolls . "/" . maxScrolls . "), " . clicksDone . " clicked", "wait")
        Sleep(scrollMs)
    }
}

; Parse "key=value; key=value" into a Map with lowercased keys. Tolerant of
; spaces and of a trailing semicolon.
ParseLoopOptions(optionsStr) {
    result := Map()
    for pair in StrSplit(optionsStr, ";") {
        pair := Trim(pair)
        if pair = ""
            continue
        eq := InStr(pair, "=")
        if !eq
            continue
        key := StrLower(Trim(SubStr(pair, 1, eq - 1)))
        val := Trim(SubStr(pair, eq + 1))
        if key != ""
            result[key] := val
    }
    return result
}

; Read a string option, treating missing OR blank as "use the default".
LoopOptStr(opt, key, default) {
    return (opt.Has(key) && Trim(opt[key]) != "") ? opt[key] : default
}

; Read an integer option, treating missing OR blank (or non-numeric) as default.
LoopOptInt(opt, key, default) {
    if !opt.Has(key)
        return default
    v := Trim(opt[key])
    return (v != "" && IsNumber(v)) ? Integer(v) : default
}

; If an interrupting window (a Save dialog, a confirmation prompt, ...) is open,
; bring it to the front and dispatch it. Returns true if it was found+handled.
;   popupDo values:
;     enter            press Enter (the usual default button) - the default
;     send:<keys>      send AutoHotkey keys to it, e.g. send:!s for Alt+S
;     pattern:<name>   find & click a saved FindText pattern (a Save button image)
HandleLoopPopup(popupTitle, popupDo) {
    if popupTitle = "" || !WinExist(popupTitle)
        return false

    try WinActivate(popupTitle)
    try WinWaitActive(popupTitle, , 1)
    ShowStatus("Find & Click Loop: handling popup '" . popupTitle . "'", "info")

    action := Trim(popupDo)
    if action = "" || StrLower(action) = "enter" {
        Send("{Enter}")
    } else if InStr(action, "send:") = 1 {
        keys := SubStr(action, 6)
        if keys != ""
            Send(keys)
    } else if InStr(action, "pattern:") = 1 || InStr(action, "click:") = 1 {
        name := Trim(SubStr(action, InStr(action, ":") + 1))
        if name != ""
            FindAndClickPattern(name)
    } else {
        ; Bare value given: treat it as literal keys to send.
        Send(action)
    }
    return true
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

Tab_Patterns_Build() {
    global ExtractStatus, PatternCaptureInfo, PatternCodeEdit, PatternDescEdit, PatternImageBox, PatternLV, PatternNameEdit, PatternPreviewEdit, PatternQualifierDD
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

}


; Context menu for saved patterns
OnPatternContextMenu(LV, RowNumber, IsRightClick, X, Y) {
    global g_Patterns
    if !TryGetListViewText(LV, RowNumber, 1, &name)
        return
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
    screenshotPath := CapturePatternScreenshot(name, x, y)
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
    screenshotPath := Photo_Path(data.Get("screenshot", ""))
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
    if screenshotPath != "" && FanFileExist(screenshotPath) {
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
            LearningValidation_Match(captureX, captureY)

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
        LearningValidation_Match(ok[1].mx, ok[1].my)
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
    screenshotPath := Photo_Path(data.Get("screenshot", ""))
    if screenshotPath != "" && FanFileExist(screenshotPath) {
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
    LearningValidation_Match(foundX, foundY)

    ; Capture screenshot at found location
    path := CapturePatternScreenshot(name, foundX, foundY)

    if path != "" && Photo_Path(path) != "" {
        try PatternImageBox.Value := Photo_Path(path)
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

    screenshotPath := Photo_Path(g_Patterns[name].Get("screenshot", ""))

    if screenshotPath = "" || !FanFileExist(screenshotPath) {
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
    LearningValidation_Match(foundX, foundY)

    ; Capture screenshot at found location
    path := CapturePatternScreenshot(name, foundX, foundY)

    if path != "" && Photo_Path(path) != "" {
        try PatternImageBox.Value := Photo_Path(path)

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
    LearningValidation_Match(foundX, foundY)

    ; Capture screenshot at found location
    path := CapturePatternScreenshot(name, foundX, foundY)

    if path != "" && Photo_Path(path) != "" {
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
    TrackToolTip("QUICK CAPTURE`n`nDrag to select region...`nESC to cancel", A_ScreenWidth // 2 - 100, 50)

    ; Wait for mouse down
    g_QuickCaptureActive := true

    ; Install keyboard hook for ESC
    Hotkey("Escape", CancelQuickCapture, "On")

    ; Wait for left button down
    KeyWait("LButton", "D")

    if !g_QuickCaptureActive {
        TrackToolTip()
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

        TrackToolTip("Selecting: " . w . " x " . h, currentX + 15, currentY + 15)
        Sleep(16)
    }

    ; Get end position
    MouseGetPos(&endX, &endY)

    ; Clean up overlay
    try g_QuickCaptureOverlay.Destroy()
    TrackToolTip()

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
    if screenshotPath != "" && FanFileExist(screenshotPath) {
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
    TrackToolTip()
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

    screenshotPath := Photo_Path(g_Patterns[name].Get("screenshot", ""))

    if screenshotPath != "" && FanFileExist(screenshotPath) {
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

