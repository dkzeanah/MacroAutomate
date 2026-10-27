; Bounded four-page local demo. All actual input uses the production controller.
; Navigation is an explicit capability scoped to this one local practice file.
global g_StudyDemoBusy := false
global g_StudyDemoUrl := ""

StudyDemo_Start() {
    global g_StudyDemoBusy, g_StudyToolBusy, g_StudyMacroCancelled
    if g_StudyDemoBusy || g_StudyToolBusy || g_StudySessBusy || g_StudyMacroRunning || g_StudyLLM_Busy
        return
    g_StudyDemoBusy := true
    g_StudyToolBusy := true
    g_StudyMacroCancelled := false
    StudyConsole_Open()
    g_StudyToolUi["status"].Value := "Starting four local visual-algebra pages. Ctrl+Shift+Esc aborts. Watch the side-monitor console."
    SetTimer(StudyDemo_Work, -100)
}

StudyDemo_Checkpoint() {
    if !g_StudyDemoBusy || g_StudyMacroCancelled || g_StudyLLM_Cancel
        throw Error("Demo cancelled")
    pin := StudyAuto_CheckPin()
    if !pin["ok"]
        throw Error(pin["reason"])
}

StudyDemo_Capture() {
    global g_StudyToolContext
    StudyDemo_Checkpoint()
    cap := StudyPercept_Capture()
    if !cap["ok"]
        throw Error(cap["err"])
    g_StudyToolContext := StudyTools_Context(cap)
    g_StudyToolUi["capture"].Value := g_StudyToolContext["text"] . "`nOCR:`n" . cap["ocr"]["text"]
    return cap
}

StudyDemo_SolutionGoal(math) {
    cas := math["verified"], doc := math["document"], goal := "Fill the practice controls with these exactly verified values:`n"
    for , variable in cas["variables"] {
        values := []
        for , solution in cas["solutions"]
            if !StudyMacro_Has(values, solution[variable])
                values.Push(solution[variable])
        goal .= "Solution " . variable . " = " . TrackArrayJoin(values, ", ") . "`n"
    }
    goal .= "Choose Equation family = " . StrTitle(doc["topic"]) . ". Set All real solutions to 1; Domain checked to 1; Guess without verification to 0. "
        . "Do not click buttons. Use captured IDs and match their roles."
    for , control in g_StudyToolContext["catalog"]
        if control["name"] = "Verification note"
            goal .= "`nVerification note = All roots verified by substitution"
    StudyConsole_Log("PLAN", "goal.from.verified.math", goal)
    return goal
}

StudyDemo_Button(name) {
    matches := []
    for , c in g_StudyToolContext["catalog"]
        if c["kind"] = "button" && c["name"] = name
            matches.Push(c)
    if matches.Length != 1
        throw Error("Expected one enabled named button: " . name)
    return matches[1]
}

StudyDemo_Click(name) {
    StudyDemo_Checkpoint()
    c := StudyDemo_Button(name)
    step := StudyMacro_StepClick(g_StudyToolContext["q"], c)
    ; Only our local disposable practice file grants these navigation effects.
    if !StudyDemo_CanActivate(name, g_StudyPin["url"])
        throw Error("Demo button permission does not apply to this URL")
    StudyConsole_Log("NAV", "button.authorized", Map("name", name, "url", g_StudyPin["url"], "scope", "local four-page practice demo"))
    if !StudyMacro_QuestionCurrent(g_StudyToolContext["q"])
        throw Error("Question changed before button activation")
    ; A navigation changes URL on mouse-up. The same controller checks every
    ; waypoint/key up to that click; subsequent input waits for re-identification.
    step["transition"] := true
    dpiContext := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try {
        if !StudyMacro_ExecStep(g_StudyToolContext["q"], step, StudyAuto_Region())
            throw Error("Practice button activation failed: " . name)
    } finally
        DllCall("SetThreadDpiAwarenessContext", "Ptr", dpiContext, "Ptr")
}

StudyDemo_CanActivate(name, url) {
    if !g_StudyDemoBusy || g_StudyDemoUrl = "" || !StudyMacro_Has(["Check answer", "Next problem", "Finish demo"], name)
        return false
    Loop 4
        if url = g_StudyDemoUrl . "#stage" . A_Index
            return true
    return false
}

StudyDemo_Advance(stage, baseUrl) {
    global g_StudyPin
    expected := baseUrl . "#stage" . (stage+1), hwnd := g_StudyPin["hwnd"]
    StudyDemo_Click("Next problem")
    started := A_TickCount
    loop {
        if g_StudyMacroCancelled || !g_StudyDemoBusy || !WinActive("ahk_id " . hwnd)
            throw Error("Navigation interrupted; no further input")
        observed := BrowserUrl_FromWindow(hwnd)
        url := observed["url"]
        if url = expected
            break
        if url != baseUrl . "#stage" . stage
            throw Error("Unexpected navigation: " . url)
        if A_TickCount-started > 6000
            throw Error("Expected next practice page did not appear")
        Sleep(80)
    }
    result := StudyAuto_Pin(hwnd)
    if !result["ok"] || g_StudyPin["url"] != expected
        throw Error("Could not re-pin expected next practice page")
    StudyMacro_InvalidateWalk()
    StudyConsole_Log("NAV", "transition.verified", Map("expected", expected, "observed", url, "next", "fresh screenshot and catalog required"))
    Sleep(400)
}

StudyDemo_Work() {
    global g_StudyDemoBusy, g_StudyToolBusy, g_StudySessOn, g_StudyMode, g_StudyLLM_Cancel
    global g_StudyMacroCancelled, g_StudyHuman
    global g_StudyDemoUrl
    oldSession := g_StudySessOn, oldMode := g_StudyMode, oldHuman := g_StudyHuman.Clone(), cap := Map()
    try {
        if !g_StudyDemoBusy
            return
        g_StudySessOn := true
        g_StudyMode := "fill"
        g_StudyLLM_Cancel := false
        g_StudyHuman["wpm"] := 115
        g_StudyHuman["typoRate"] := 0.25
        g_StudyHuman["overshootRate"] := 1
        rawPath := APP_ROOT . "\fan\tests\algebra_portal.html"
        pathBuffer := Buffer(32768*2)
        DllCall("GetFullPathNameW", "Str", rawPath, "UInt", 32768, "Ptr", pathBuffer, "Ptr", 0)
        path := StrGet(pathBuffer)
        baseUrl := "file:///" . StrReplace(path, "\", "/")
        g_StudyDemoUrl := baseUrl
        chrome := EnvGet("PROGRAMFILES") . "\Google\Chrome\Application\chrome.exe"
        if !FileExist(chrome)
            throw Error("Chrome executable not found at " . chrome)
        previous := WinGetList("Algebra 100 Practice Portal ahk_exe chrome.exe")
        StudyConsole_Log("DEMO", "start", Map("pages", 4, "url", baseUrl, "input_profile", g_StudyHuman,
            "monitors", StudyAuto_Monitors(), "libraries", ["GDI+", "Windows OCR", "Acc", "WinHTTP", "DeepSeek Flash/Pro", "SymPy", "TrackSQLite", "guarded AHK controller"]))
        Run(Chr(34) . chrome . Chr(34) . " --new-window " . Chr(34) . baseUrl . "#stage1" . Chr(34))
        hwnd := 0, started := A_TickCount
        while !hwnd {
            if g_StudyMacroCancelled || !g_StudyDemoBusy
                throw Error("Demo cancelled during browser launch")
            for , candidate in WinGetList("Algebra 100 Practice Portal ahk_exe chrome.exe")
                if !StudyMacro_Has(previous, candidate)
                    hwnd := candidate
            if A_TickCount-started > 12000
                throw Error("New Algebra practice window did not open")
            Sleep(100)
        }
        dpiContext := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
        try {
            MonitorGetWorkArea(MonitorGetPrimary(), &left, &top, &right, &bottom)
            WinRestore("ahk_id " . hwnd)
            WinMove(left+15, top+10, Min(1650,right-left-30), Min(1015,bottom-top-25), "ahk_id " . hwnd)
        } finally
            DllCall("SetThreadDpiAwarenessContext", "Ptr", dpiContext, "Ptr")
        WinActivate("ahk_id " . hwnd)
        Sleep(1000)
        pin := StudyAuto_Pin(hwnd)
        if !pin["ok"] || g_StudyPin["url"] != baseUrl . "#stage1"
            throw Error("Practice page URL did not match the authorized file: " . g_StudyPin["url"])
        Loop 4 {
            stage := A_Index
            StudyConsole_Log("DEMO", "page.start", Map("stage", stage, "url", g_StudyPin["url"]))
            cap := StudyDemo_Capture()
            math := StudyMath_Solve(cap, g_StudyToolContext)
            StudyDemo_Checkpoint()
            goal := StudyDemo_SolutionGoal(math)
            g_StudyToolUi["goal"].Value := goal
            proposal := StudyTools_RequestPlan(g_StudyToolContext, goal,
                (candidate) => StudyDemo_ValidatePlan(candidate, math, g_StudyToolContext))
            StudyDemo_Checkpoint()
            if !proposal["ok"] || !proposal["planValid"]
                throw Error("Generated workflow rejected: " . proposal.Get("planError", proposal["error"]))
            g_StudyToolUi["script"].Value := proposal["answer"]
            plan := StudyTools_Compile(proposal["answer"], g_StudyToolContext, "fill")
            StudyDemo_ValidatePlan(plan, math, g_StudyToolContext)
            result := StudyMacro_Run(g_StudyToolContext["q"], plan["steps"])
            g_StudyToolUi["trace"].Value := StudyPercept_Join(g_StudyMacroTrace)
            if !result["ok"]
                throw Error(result["detail"])
            StudyPercept_Dispose(cap["imagePath"])
            cap := StudyDemo_Capture()
            StudyDemo_Click("Check answer")
            Sleep(350)
            StudyPercept_Dispose(cap["imagePath"])
            cap := StudyDemo_Capture()
            if !InStr(cap["ocr"]["text"], "Correct answer")
                throw Error("On-page correct feedback was not observed")
            StudyConsole_Log("VERIFY", "page.correct", Map("stage", stage, "feedback", cap["ocr"]["text"], "solutions", math["verified"]["solutions"]))
            Study_SetSetting("demo_last_tool_" . stage, proposal["answer"])
            Study_SetSetting("demo_last_features_" . stage, TrackJsonEncode(g_StudyToolContext["features"]))
            if stage < 4
                StudyDemo_Advance(stage, baseUrl)
            else
                StudyDemo_Click("Finish demo")
            StudyPercept_Dispose(cap["imagePath"])
            cap := Map()
        }
        StudyConsole_Log("DEMO", "complete", Map("verified_pages", 4, "cost_usd", g_StudyLLM_SpentUSD))
        g_StudyToolUi["status"].Value := "PASS: four visual algebra problems, generated tools, control states and page transitions verified. See live console and JSONL."
        StudyConsole_Flush()
    } catch as err {
        StudyConsole_Log("ERROR", "demo.stopped", Map("message", err.Message, "stack", err.Stack), "ERROR")
        g_StudyToolUi["status"].Value := "Demo stopped: " . err.Message . " | See the live console."
    } finally {
        if cap.Has("imagePath")
            StudyPercept_Dispose(cap["imagePath"])
        g_StudyHuman := oldHuman
        g_StudySessOn := oldSession && !g_StudyMacroCancelled
        g_StudyMode := oldMode
        g_StudyDemoBusy := false
        g_StudyDemoUrl := ""
        g_StudyToolBusy := false
    }
}

StudyDemo_ValidatePlan(plan, math, ctx) {
    ; The model can compose commands, but cannot alter the exact solution or
    ; omit a required field. Validate its final writes before any input starts.
    if !plan["ok"]
        throw Error(plan["detail"])
    expected := Map("Equation family", StrTitle(math["document"]["topic"]), "All real solutions", 1,
        "Domain checked", 1, "Guess without verification", 0)
    for , control in ctx["catalog"]
        if control["name"] = "Verification note"
            expected["Verification note"] := "All roots verified by substitution"
    for , variable in math["verified"]["variables"] {
        values := []
        for , solution in math["verified"]["solutions"]
            if !StudyMacro_Has(values, solution[variable])
                values.Push(solution[variable])
        expected["Solution " . variable] := TrackArrayJoin(values, ", ")
    }
    found := Map()
    for , step in plan["steps"] {
        if IsObject(step["verify"]) && IsObject(step["acc"]) {
            name := step["acc"]["name"]
            if !expected.Has(name) || !StudyMacro_ValueEqual(String(step["verify"]["expect"]), String(expected[name]))
                throw Error("Generated tool attempts a value different from the verified goal: " . name)
            found[name] := true
        }
    }
    for name in expected
        if !found.Has(name)
            throw Error("Generated tool omitted required control: " . name)
    StudyConsole_Log("PLAN", "goal.checked", Map("expected", expected, "result", "PASS"))
}
