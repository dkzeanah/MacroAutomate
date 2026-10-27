; Shared FindText pattern resolution and workflow input, including unattended guards.

FindPatternOnScreen(patternName, tolerance := "", hwnd := 0) {
    global g_Patterns, g_Settings
    global g_FanVisionObserver
    if IsSet(g_FanVisionObserver) && IsObject(g_FanVisionObserver)
        try g_FanVisionObserver.Call("FindText","FindText","start",Map("name",patternName,"hwnd",hwnd))

    if !g_Patterns.Has(patternName)
        return Map("found", false)

    patternData := g_Patterns[patternName]
    patternText := patternData["text"]

    if tolerance = ""
        tolerance := g_Settings["FindTextTolerance"]

    if hwnd {
        WinGetPos(&sx,&sy,&sw,&sh,hwnd)
        ok := FindText(&outX,&outY,sx,sy,sx+sw-1,sy+sh-1,tolerance,tolerance,patternText)
    } else
        ok := FindText(&outX, &outY, , , , , tolerance, tolerance, patternText)

    if ok && ok.Length > 0 {
        return Map(
            "found", true,
            "match_count", ok.Length,
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

FindAndClickPattern(patternName, button := "Left", clickCount := 1, tolerance := "") {
    global g_Settings, g_AbortSequence, g_LastClickX, g_LastClickY, g_Patterns
    global g_WorkflowExecutionOptions, g_LastActionError
    CoordMode("Mouse","Screen")
    strict := IsSet(g_WorkflowExecutionOptions) && g_WorkflowExecutionOptions is Map && !g_WorkflowExecutionOptions.Get("interactive",true)
    hwnd := strict ? WinExist("A") : 0

    ; Strip [P] prefix if present
    patternName := StrReplace(patternName, "[P] ", "")
    if strict {
        if !hwnd
            return false
        context := g_Patterns.Has(patternName) ? g_Patterns[patternName].Get("captureWindow","") : ""
        if context!="" && !InStr(WinGetTitle(hwnd),context) {
            g_LastActionError := "Pattern belongs to a different window: " . context
            return false
        }
        WinGetPos(&wx,&wy,&ww,&wh,hwnd)
    }

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

        result := FindPatternOnScreen(patternName, tolerance, hwnd)

        if result["found"] {
            if strict && result["match_count"]!=1 {
                g_LastActionError := "Pattern is ambiguous in the active window"
                return false
            }
            x := result["mx"]
            y := result["my"]

            DeepActivity_Target(Map("x",result["x"],"y",result["y"],"w",result["w"],"h",result["h"]),"About to click " . patternName,300)

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

            if strict {
                WinGetPos(&nx,&ny,&nw,&nh,hwnd)
                point := (x & 0xFFFFFFFF) | ((y & 0xFFFFFFFF) << 32)
                hit := DllCall("WindowFromPoint","Int64",point,"Ptr")
                if WinExist("A")!=hwnd || nx!=wx || ny!=wy || nw!=ww || nh!=wh || DllCall("GetAncestor","Ptr",hit,"UInt",2,"Ptr")!=hwnd {
                    g_LastActionError := "Target window changed or is covered; no click sent"
                    return false
                }
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
