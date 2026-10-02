; ===============================================================================
; Actions\_Engine.ahk
; Workflow execution engine: ExecuteSequenceVerified, ExecuteActionVerified, execute helpers
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================



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

    if StrLower(Trim(param)) = "demo:lab" {
        ShowWorkflowDemoLab(false)
        WinActivate("MacroAutomator Demo Lab")
        DemoLabLog("Taskbar Activate demonstrated through the safe internal lab target.")
        ShowStatus("Activated built-in Demo Lab", "ok")
        return true
    }

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
    global g_Settings

    if params = "" {
        ShowStatus("HoverMouse requires coordinates", "fail")
        return false
    }

    if !ResolveWorkflowPoint(params, &x, &y) {
        ShowStatus("HoverMouse target was not found: " . params, "fail")
        return false
    }

    ; Move mouse
    MouseMove(x, y, 5)
    Sleep(g_Settings["PostActionDelay"])

    ShowStatus("Mouse hovering at " . x . "," . y, "ok")
    return true
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
    global g_WorkflowVariables, g_SkipNextAction, g_SequenceCallStack, g_SpoolVariables
    global g_LoopBreakRequested, g_ActiveLoopDepth
    g_AbortSequence := false
    g_WorkflowVariables := Map()
    g_SkipNextAction := false
    g_SequenceCallStack := []
    g_LoopBreakRequested := false
    g_ActiveLoopDepth := 0

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

    ; ── Loop support: Loop Start / Loop End / Loop Break are handled here so
    ; the body in between re-runs. Each stack entry remembers where the body
    ; starts, how many passes remain (-1 = forever) and the counter variable.
    loopStack := []

    i := 1
    while i <= total {
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
            ShowStatus("[" . i . "/" . total . "] Skipped by previous condition: " . enabled[i]["action"], "info")
            i++
            continue
        }

        s := enabled[i]
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

        jumpTo := 0   ; >0 = jump to this enabled index instead of i+1 (loop back)

        if s["action"] = "Loop Start" {
            opt := ParseLoopOptions(s["param"])
            countText := LoopOptStr(opt, "count", "5")
            loopVar := LoopOptStr(opt, "var", "i")
            lower := StrLower(countText)
            repeat := (lower = "forever" || lower = "infinite") ? -1
                    : (IsNumber(countText) ? Max(Integer(countText), 1) : 5)
            loopStack.Push(Map("start", i + 1, "remaining", repeat, "total", repeat, "var", loopVar))
            g_ActiveLoopDepth := loopStack.Length
            if loopVar != "" {
                g_WorkflowVariables[loopVar] := 1
                g_SpoolVariables[loopVar] := 1
                g_WorkflowVariables["loopCount"] := repeat = -1 ? "forever" : repeat
                g_SpoolVariables["loopCount"] := repeat = -1 ? "forever" : repeat
            }
            ShowStatus("Loop started: " . (repeat = -1 ? "forever (ESC to stop)" : repeat . " passes")
                . "  -  $var." . loopVar . " = 1, memory kept between passes", "info")
        } else if s["action"] = "Loop End" {
            if loopStack.Length > 0 {
                top := loopStack[loopStack.Length]
                if g_LoopBreakRequested {
                    g_LoopBreakRequested := false
                    loopStack.Pop()
                    ShowStatus("Loop left early", "info")
                } else if top["remaining"] = -1 {
                    WorkflowLoopIncrement(top)
                    jumpTo := top["start"]
                } else {
                    top["remaining"] -= 1
                    if top["remaining"] > 0 {
                        WorkflowLoopIncrement(top)
                        jumpTo := top["start"]
                    } else {
                        loopStack.Pop()
                        ShowStatus("Loop finished after " . top["total"] . " passes", "ok")
                    }
                }
                g_ActiveLoopDepth := loopStack.Length
            }
        } else if s["action"] = "Loop Break" {
            ShowStatus("Loop Break: leaving the current loop", "info")
            if loopStack.Length > 0 {
                loopStack.Pop()
                g_ActiveLoopDepth := loopStack.Length
            }
            j := i + 1
            while j <= total {
                if enabled[j]["action"] = "Loop End" {
                    i := j
                    break
                }
                j++
            }
        } else {
            success := ExecuteActionVerified(s["action"], s["target"], s["param"], s, speedMultiplier)

            ; Popup Detect (and friends) may request a break: leave the current
            ; loop now and skip the rest of the body by jumping to its Loop End.
            if success && g_LoopBreakRequested && loopStack.Length > 0 {
                g_LoopBreakRequested := false
                loopStack.Pop()
                g_ActiveLoopDepth := loopStack.Length
                ShowStatus("Popup detected - leaving the loop early", "info")
                j := i + 1
                found := 0
                while j <= total {
                    if enabled[j]["action"] = "Loop End" {
                        found := j
                        break
                    }
                    j++
                }
                if found > 0
                    i := found
            }

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
        } else if jumpTo = 0 {
            Sleep(adjustedDelay)
        }

        if jumpTo > 0 && jumpTo <= total
            i := jumpTo
        else
            i++
    }

    if loopStack.Length > 0
        ShowStatus("Finished with " . loopStack.Length . " unclosed loop(s) - check Loop Start/Loop End pairing", "info")

    ; Disable hotkeys
    try Hotkey("Escape", "Off")
    if g_StepThroughMode
        try Hotkey("Tab", "Off")

    ShowStatus("Complete (" . total . " steps @ " . speedText . ")", "ok")
    ShowNotificationBasic("Sequence Complete", total . " steps executed successfully", 0, "success")
    Sleep(500)
    ToolTip()
}

; Bump the loop counter variable for the next pass ($var.<name> = 2, 3, ...).
WorkflowLoopIncrement(top) {
    global g_WorkflowVariables, g_SpoolVariables
    varName := top["var"]
    if varName = ""
        return
    n := 1
    if g_WorkflowVariables.Has(varName) && IsNumber(g_WorkflowVariables[varName])
        n := Integer(g_WorkflowVariables[varName]) + 1
    g_WorkflowVariables[varName] := n
    g_SpoolVariables[varName] := n
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
    global g_WorkflowVariables, g_SkipNextAction, g_DemoClipboardActive

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
            if target != "" && target != "(none)" && ResolveWorkflowPoint(target, &pointX, &pointY) {
                g_LastClickX := pointX
                g_LastClickY := pointY
                FlashClickPosition(pointX, pointY)
                return ClickVerified(pointX, pointY, "Left", param != "" ? Integer(param) : 1)
            } else if param != "" && InStr(param, ",") {
                ; Backward compatibility with workflows that stored x,y in Param.
                if ResolveWorkflowPoint(param, &pointX, &pointY)
                    return ClickVerified(pointX, pointY)
            }
            MouseGetPos(&g_LastClickX, &g_LastClickY)
            FlashClickPosition(g_LastClickX, g_LastClickY)
            Click()
            return true

        case "Double Click":
            if target != "" && ResolveWorkflowPoint(target, &pointX, &pointY) {
                g_LastClickX := pointX, g_LastClickY := pointY
                return ClickVerified(pointX, pointY, "Left", 2)
            }
            MouseGetPos(&g_LastClickX, &g_LastClickY)
            Click(, , , 2)
            return true

        case "Triple Click":
            if target != "" && ResolveWorkflowPoint(target, &pointX, &pointY) {
                g_LastClickX := pointX, g_LastClickY := pointY
                return ClickVerified(pointX, pointY, "Left", 3)
            }
            MouseGetPos(&g_LastClickX, &g_LastClickY)
            Click(, , , 3)
            return true

        case "Right Click":
            if target != "" && ResolveWorkflowPoint(target, &pointX, &pointY) {
                g_LastClickX := pointX, g_LastClickY := pointY
                return ClickVerified(pointX, pointY, "Right")
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
                if parts.Length < 2
                    return false
                if !ResolveWorkflowPoint(Trim(parts[1]), &startX, &startY)
                    || !ResolveWorkflowPoint(Trim(parts[2]), &endX, &endY)
                    return false
                MoveMouseVerified(startX, startY)
                Sleep(g_Settings["PreActionDelay"])
                MouseClickDrag("Left", startX, startY, endX, endY, g_Settings["DefaultDragTime"] / 100)
                g_LastClickX := endX
                g_LastClickY := endY
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

        case "Find & Click Loop":
            return FindClickScrollLoop(target, param)

        case "Find & DblClick":
            return FindAndClickPattern(target, "Left", 2)

        case "Find & TplClick":
            return FindAndClickPattern(target, "Left", 3)

        case "Find & RClick":
            return FindAndClickPattern(target, "Right", 1)

        case "Find & Drag":
            if param != "" && ResolveWorkflowPoint(param, &endX, &endY)
                return FindAndDragPattern(target, endX, endY)
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
            if StrLower(Trim(param)) = "demo:lab"
                return ShowWorkflowDemoLab(true)
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
            if TryParseDemoClipboard()
                return true
            g_DemoClipboardActive := false
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
            if target != "" && !InStr(param, ",")
                return ExecuteGrabOCRToVar(param, target)
            return ExecuteGrabOCRToVar(param)

        case "OCR Full Screen to Var":
            return ExecuteFullScreenOCRToVar(param)

        case "Use Var Paste":
            return ExecuteUseVarPaste(param)

        case "Show Notification":
            return ExecuteShowNotification(param)

        ; ─── Looping family (jump control lives in ExecuteSequenceVerified) ──
        case "Loop Start":
            ; Direct single-step test: just seed the counter variables.
            opt := ParseLoopOptions(param)
            varName := LoopOptStr(opt, "var", "i")
            if varName != "" {
                g_WorkflowVariables[varName] := 1
                g_SpoolVariables[varName] := 1
            }
            return true
        case "Loop End", "Loop Break":
            return true

        ; ─── Window waiting / popup detection ────────────────────────────────
        case "Wait for Window":
            return ExecuteWaitForWindow(param, false)
        case "Wait Window Closed":
            return ExecuteWaitForWindow(param, true)
        case "Popup Detect":
            return ExecutePopupDetect(target, param, stepData)

        ; ─── Tracking-powered actions ────────────────────────────────────────
        case "Click Element":
            return ExecuteClickElement(target, param)

        case "Hover Element":
            return Element_HoverByName(target != "" && target != "(none)" ? target : param)

        case "Wait Element":
            return ExecuteWaitElement(target, param)

        case "Replay Window Mouse":
            return ExecuteReplayWindowMouse(target, param)

        case "Research Search":
            return Research_Search(param != "" ? param : target) != 0

        case "Research Capture Links":
            return ExecuteResearchCaptureLinks(param)

        case "Research Launch Next":
            return Research_LaunchNext() != 0

        case "Research Add Insight":
            return Research_AddInsight(param) != 0

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

; ─── Wait for Window / Wait Window Closed ─────────────────────────────────────
; param: "title=Save As; timeout=5000" (key=value pairs, see ParseLoopOptions)
ExecuteWaitForWindow(param, waitGone) {
    global g_AbortSequence
    opt := ParseLoopOptions(param)
    title := LoopOptStr(opt, "title", "")
    if title = "" {
        ShowStatus((waitGone ? "Wait Window Closed" : "Wait for Window") . " needs a window title", "fail")
        return false
    }
    timeout := LoopOptInt(opt, "timeout", 5000)
    start := A_TickCount
    while !g_AbortSequence {
        exists := WinExist(title) != 0
        if (waitGone ? !exists : exists) {
            ShowStatus(waitGone ? "Window closed: " . title : "Window found: " . title, "ok")
            return true
        }
        if A_TickCount - start > timeout {
            ShowStatus("Timed out waiting for window: " . title, "fail")
            return false
        }
        Sleep(150)
    }
    return false
}

; ─── Popup Detect: region/window change detection with loop-top memory ────────
; param: "win=Title; region=x,y,w,h; sensitivity=high|medium|low|strict;
;         on=var|skip|break|stop; mode=now|wait; timeout=ms; var=popupChanged"
; The baseline snapshot is remembered on the step object itself, so inside a
; loop every pass compares against the state captured at the top of the loop.
ExecutePopupDetect(target, param, stepData := "") {
    global g_AbortSequence, g_WorkflowVariables, g_SpoolVariables
    global g_SkipNextAction, g_LoopBreakRequested, g_ActiveLoopDepth

    opt := ParseLoopOptions(param)
    mode := LoopOptStr(opt, "mode", "now")
    onAction := LoopOptStr(opt, "on", "var")
    varName := LoopOptStr(opt, "var", "popupChanged")
    sens := StrLower(LoopOptStr(opt, "sensitivity", "medium"))
    thresholds := Map("high", 0.02, "medium", 0.05, "low", 0.15, "strict", 0.25)
    threshold := thresholds.Has(sens) ? thresholds[sens] : 0.05

    ; Resolve the watched area: a whole window (win=) or a rectangle (region=).
    x1 := 0, y1 := 0, x2 := 0, y2 := 0
    if opt.Has("win") && Trim(opt["win"]) != "" {
        hwnd := FindWorkflowWindow(Trim(opt["win"]))
        if !hwnd {
            ShowStatus("Popup Detect: window not found - " . opt["win"], "fail")
            return false
        }
        try WinGetPos(&x1, &y1, &w, &h, "ahk_id " . hwnd)
        x2 := x1 + w
        y2 := y1 + h
    } else {
        regionSource := opt.Has("region") && Trim(opt["region"]) != "" ? opt["region"] : target
        region := ParseRegionCoords(regionSource)
        if !region {
            ShowStatus("Popup Detect needs a window or a screen region", "fail")
            return false
        }
        x1 := region["x1"], y1 := region["y1"], x2 := region["x2"], y2 := region["y2"]
    }
    if x2 <= x1 || y2 <= y1 {
        ShowStatus("Popup Detect: watched area is empty", "fail")
        return false
    }

    ; Loop-top memory: first pass captures the baseline; later passes compare.
    baseline := (IsObject(stepData) && stepData.Has("popupBaseline")) ? stepData["popupBaseline"] : ""
    timeout := LoopOptInt(opt, "timeout", 5000)
    start := A_TickCount
    changed := false
    changedFrac := 0.0

    while true {
        if g_AbortSequence
            return false
        capture := SampleRegionPixels(x1, y1, x2 - x1, y2 - y1, 8)
        if baseline = "" {
            baseline := capture
            if IsObject(stepData)
                stepData["popupBaseline"] := baseline
            ShowStatus("Popup Detect: remembered the starting state", "info")
        } else {
            changedFrac := ComparePixelSamples(baseline, capture)
            changed := changedFrac >= threshold
            ; Track slow drift only while the area is still "clean", so the
            ; baseline keeps meaning the state without a popup.
            if !changed && IsObject(stepData)
                stepData["popupBaseline"] := capture
        }
        if mode = "wait" && !changed {
            if A_TickCount - start > timeout
                break
            Sleep(200)
            continue
        }
        break
    }

    if varName != "" {
        g_WorkflowVariables[varName] := changed ? 1 : 0
        g_SpoolVariables[varName] := changed ? 1 : 0
    }

    if changed {
        ShowStatus("Popup Detect: CHANGE detected (" . Round(changedFrac * 100, 1) . "% of the area)", "info")
        switch onAction {
            case "skip":
                g_SkipNextAction := true
            case "break":
                if g_ActiveLoopDepth > 0
                    g_LoopBreakRequested := true
                else
                    g_SkipNextAction := true
            case "stop":
                g_AbortSequence := true
                ShowStatus("Workflow stopped by Popup Detect", "info")
            default:
                ; "var" (default): just remember the result.
        }
        return true
    }

    ShowStatus("Popup Detect: no change", "info")
    return true
}

; ─── Screen sampling for change detection ─────────────────────────────────────
; Captures the region and keeps one average byte per sampled pixel. Fast and
; small enough to store on the step as the remembered baseline.
SampleRegionPixels(x, y, w, h, step := 8) {
    x := Max(0, x), y := Max(0, y)
    w := Min(w, A_ScreenWidth - x), h := Min(h, A_ScreenHeight - y)
    if w < 4 || h < 4
        return Buffer(2, 0)
    hdc := GetDC()
    chdc := CreateCompatibleDC()
    hbm := CreateDIBSection(w, h, chdc, 32, &pvBits)
    old := SelectObject(chdc, hbm)
    BitBlt(chdc, 0, 0, w, h, hdc, x, y)
    SelectObject(chdc, old)
    stride := w * 4
    cols := (w + step - 1) // step
    rows := (h + step - 1) // step
    buf := Buffer(cols * rows + 2, 0)
    NumPut("UShort", cols, buf, 0)
    NumPut("UShort", rows, buf, 2)
    idx := 2
    row := 0
    while row < rows {
        py := row * step * stride
        col := 0
        while col < cols {
            off := py + col * step * 4
            b := NumGet(pvBits, off, "UChar")
            g := NumGet(pvBits, off + 1, "UChar")
            r := NumGet(pvBits, off + 2, "UChar")
            NumPut("UChar", (r + g + b) // 3, buf, idx)
            idx++
            col++
        }
        row++
    }
    DeleteObject(hbm)
    DeleteDC(chdc)
    ReleaseDC(hdc)
    return buf
}

; Fraction of sampled pixels that differ noticeably between two snapshots.
ComparePixelSamples(bufA, bufB) {
    if bufA.Size != bufB.Size || bufA.Size < 2
        return 1.0
    total := bufA.Size - 2
    if total <= 0
        return 0.0
    diff := 0
    i := 2
    while i < bufA.Size {
        a := NumGet(bufA, i, "UChar")
        b := NumGet(bufB, i, "UChar")
        if Abs(a - b) > 24
            diff++
        i++
    }
    return diff / total
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

