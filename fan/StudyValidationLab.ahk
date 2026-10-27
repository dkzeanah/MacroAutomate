; Isolated live validation using the production perception, provider and controller.
; Separate SQLite database; leaves the user's running MacroAutomator/data alone.
#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off
CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
global APP_ROOT := A_ScriptDir . "\.."
global validationDb := 0
global validationBusy := false
DirCreate(A_ScriptDir . "\tests\runtime")
TrackDB() {
    global validationDb
    if !validationDb
        validationDb := TrackSQLite(A_ScriptDir . "\tests\runtime\validation.db")
    return validationDb
}
Qa_Schema() => false
Qa_OpenBank() => 0
Qa_OpenCount() => 0
Study_ReadAlong_PickRegion() => 0
Study_ReadAlong_Toggle() => 0
Study_TempDir() => A_ScriptDir . "\tests\runtime"
ShowStatus(text, mode := "") => 0
ShowTooltipTimed(text, ms := 0) => 0
LogDiagnostic(args*) => 0
Track_WriteFile(path, value) => FileAppend(value, path, "UTF-8")
TrackLogError(where, err) => LogErrorToFile(err, "", where)
LogErrorToFile(err, mode := "", where := "") {
    FileAppend(where . ": " . err.Message . "`n", A_ScriptDir . "\tests\runtime\errors.log", "UTF-8")
}
GetWindowUnderMouse() {
    MouseGetPos(,, &hwnd)
    return Map("hwnd", hwnd, "title", WinGetTitle(hwnd), "exe", WinGetProcessName(hwnd))
}
#Include ..\OCR.ahk
#Include ..\lib\Acc.ahk
#Include Core\_Gdip.ahk
#Include Actions\_Engine.ahk
#Include ..\lib\TrackSQLite.ahk
#Include ..\lib\TrackUtil.ahk
#Include ..\lib\SnapshotRecovery.ahk
#Include ..\lib\SnipStudio.ahk
#Include ..\lib\StudyDB.ahk
#Include ..\lib\StudyConsole.ahk
#Include ..\lib\StudyLLM.ahk
#Include ..\lib\StudyAutomation.ahk
#Include ..\lib\StudyPortal.ahk
#Include ..\lib\StudyComposer.ahk
#Include ..\lib\StudyLive.ahk
#Include ..\lib\StudyTools.ahk
#Include ..\lib\StudyMath.ahk
#Include ..\lib\StudyDemo.ahk
#Include ..\lib\DeepSeekBridge.ahk
#Include ..\lib\FanBridgeVision.ahk
#Include ..\lib\FanBridgeAPI.ahk

StudyHuman_Load()
g_StudyMode := "fill"
if (A_Args.Length && A_Args[1] = "/bridge-layout") {
    try {
        layoutGui := Gui()
        DeepBridge_BuildTab(layoutGui)
        for , size in [[900, 780], [1536, 793], [1920, 1030]] {
            DeepBridge_Resize(layoutGui, 0, size[1], size[2])
            ui := g_DeepBridge["ui"]
            ui["output"].GetPos(&ox, &oy, &ow, &oh)
            ui["thinking"].GetPos(&tx, &ty, &tw, &th)
            ui["activity"].GetPos(&ax, &ay, &aw, &ah)
            ui["status"].GetPos(, &sy, , &sh)
            ui["input"].GetPos(&ix, &iy, &iw, &ih)
            ui["new"].GetPos(, &ny)
            ui["send"].GetPos(&sx, &sendY)
            if ox+ow >= tx || ty+th >= ay || oy+oh >= sy || ay+ah >= sy
                || sy+sh >= iy || ix+iw >= sx || iy+ih >= ny || ny+26 > size[2]-47
                throw Error("Bridge panes/composer/history overlap at " . size[1] . "x" . size[2])
            FileAppend("PASS Bridge layout fits " . size[1] . "x" . size[2] . " without overlap`n", "*")
        }
        ExitApp(0)
    } catch as err {
        FileAppend("FAIL " . err.Message . "`n", "*")
        ExitApp(1)
    }
}
if (A_Args.Length && A_Args[1] = "/bridge-ui") {
    try {
        fixture := A_ScriptDir . "\tests\runtime\bridge-ui"
        DirCreate(fixture)
        DirCopy(A_ScriptDir . "\DeepSeekBridge\bridge", fixture . "\bridge", 1)
        DirCreate(fixture . "\ahk")
        FileCopy(A_ScriptDir . "\DeepSeekBridge\ahk\Worker.ahk", fixture . "\ahk\Worker.ahk", 1)
        envPath := fixture . "\.env"
        if FileExist(envPath)
            FileDelete(envPath)
        FileAppend("BRIDGE_TOKEN=synthetic-ui-token`nBRIDGE_PORT=18767`nMONITOR_PORT=18768`nALLOW_AGENT_SCRIPTS=1`n", envPath, "UTF-8-RAW")
        g_DeepBridge["root"] := fixture
        g_DeepBridge["python"] := A_ScriptDir . "\DeepSeekBridge\.venv\Scripts\python.exe"
        EnvSet("DEEPSEEK_API_KEY", "synthetic-loopback-ui-fixture")
        g_StudyLLM_Endpoint := "http://127.0.0.1:18766"
        Study_SetSetting("bridge_chat_history", "[]")
        bridgeGui := Gui()
        DeepBridge_BuildTab(bridgeGui)
        DeepBridge_AutoStart()
        ui := g_DeepBridge["ui"]
        ui["effort"].Choose(1)
        ui["input"].Value := "Bridge custom message"
        if !DeepBridge_Send()
            throw Error("Bridge did not accept a custom message")
        if !InStr(ui["status"].Value, "QUEUED") || ui["send"].Enabled || !ui["cancel"].Enabled
            throw Error("Accepted bridge message has no visible queue/stop state")
        FileAppend("PASS Bridge accepts messages with visible progress and Stop`n", "*")
        deadline := A_TickCount + 80000
        while g_DeepBridge["busy"] && A_TickCount < deadline
            Sleep(25)
        if g_DeepBridge["busy"] || g_DeepBridge["status"] != "complete" || !InStr(ui["output"].Value, "café α → Bridge custom message")
            throw Error("Bridge UI did not complete its gateway → agent → streamed answer: " . ui["status"].Value)
        FileAppend("PASS Bridge gateway/daemon stream Unicode answer into its own tab`n", "*")
        if g_DeepBridge["history"].Length != 2 || !InStr(ui["activity"].Value, "agent_request")
            throw Error("Bridge lost conversation context or request activity")
        Sleep(600)
        if StrReplace(ui["output"].Value, "`r", "") != StrReplace(g_DeepBridge["text"], "`r", "")
            throw Error("Bridge repeated streamed content after completion")
        FileAppend("PASS Bridge retains context/activity without duplicate output`n", "*")
        health := DeepBridge_Request("GET", "/health")
        if !health["windows_worker"] || !health["services"]["children"]["agent"]["alive"]
            throw Error("Bridge worker or agent is disconnected")
        FileAppend("PASS Gateway, API agent and AHK worker report connected`n", "*")
        ; Read-only real worker tool; never types or clicks into the user's apps.
        windows := DeepBridge_Request("POST", "/tools/window_list", Map())
        if !windows.Get("ok", false) || !(windows.Get("windows", 0) is Array)
            throw Error("Real AHK window-list tool failed")
        FileAppend("PASS Read-only AHK window-list roundtrip succeeds`n", "*")
        DeepBridge_LoadHistory()
        DeepBridge_View()
        if !g_DeepBridge["viewOnly"] || !InStr(ui["output"].Value, "Bridge custom message")
            throw Error("Request history did not display in the interface")
        FileAppend("PASS Bridge request history opens in the interface`n", "*")
        DeepBridge_Clear()
        if ui["output"].Value != "" || g_DeepBridge["history"].Length
            throw Error("New chat did not reset the Bridge conversation")
        scriptSource := "#Requires AutoHotkey v2.0`nPersistent(true)`n"
        created := DeepBridge_Request("POST", "/tools/ahk_script_write", Map("name", "ui_owned_lifetime.ahk", "source", scriptSource, "overwrite", true))
        if !created.Get("ok", false)
            throw Error("Could not create isolated managed-lifetime fixture")
        managed := DeepBridge_Request("POST", "/tools/ahk_script_run", Map("name", "ui_owned_lifetime.ahk", "wait", false))
        if !managed.Get("ok", false) || managed.Get("status", "") != "running"
            throw Error("Managed lifetime fixture did not start")
        DeepBridge_Poll()
        if g_DeepBridge["busy"] || !ui["cancel"].Enabled || !g_DeepBridge["scripts"].Length
            throw Error("Stop is unavailable for scripts after the parent reply finishes")
        DeepBridge_Cancel()
        stopped := DeepBridge_Request("POST", "/tools/ahk_script_status", Map("run_id", managed["run_id"]))
        if stopped.Get("status", "") != "cancelled" || ProcessExist(managed["pid"])
            throw Error("Stop did not cancel the owned persistent script")
        FileAppend("PASS Stop remains available after a reply and stops its persistent script`n", "*")
        ui["input"].Value := "Cancel before request"
        DeepBridge_Send()
        DeepBridge_Cancel()
        if g_DeepBridge["busy"] || g_DeepBridge["status"] != "cancelled"
            throw Error("Pending Bridge cancellation failed")
        FileAppend("PASS Bridge New chat and pending cancellation work`n", "*")
        g_StudyLLM_Endpoint := "http://127.0.0.1:18766/streamslow"
        DeepBridge_Restart()
        ui["input"].Value := "Cancel active stream"
        DeepBridge_Send()
        deadline := A_TickCount + 80000
        while g_DeepBridge["task"] = "" && g_DeepBridge["busy"] && A_TickCount < deadline
            Sleep(25)
        if !g_DeepBridge["busy"] || g_DeepBridge["task"] = ""
            throw Error("Slow test request was not active before cancellation")
        cancelledTask := g_DeepBridge["task"]
        oldAgent := DeepBridge_Request("GET", "/health")["services"]["children"]["agent"]["pid"]
        DeepBridge_Cancel()
        replaced := false, deadline := A_TickCount + 30000
        while A_TickCount < deadline {
            Sleep(100)
            try {
                nowAgent := DeepBridge_Request("GET", "/health")["services"]["children"]["agent"]
                if nowAgent["pid"] != oldAgent && nowAgent["alive"] {
                    replaced := true
                    break
                }
            }
        }
        if !replaced || DeepBridge_Request("GET", "/tasks/" . cancelledTask)["status"] != "cancelled"
            throw Error("Stop did not interrupt and replace the owned API agent")
        FileAppend("PASS Stop interrupts an active request and replaces its owned agent`n", "*")
        g_StudyLLM_Endpoint := "http://127.0.0.1:18766"
        DeepBridge_Restart()
        ui["input"].Value := "After cancellation"
        DeepBridge_Send()
        deadline := A_TickCount + 80000
        while g_DeepBridge["busy"] && A_TickCount < deadline
            Sleep(25)
        if g_DeepBridge["busy"] || g_DeepBridge["status"] != "complete" || !InStr(ui["output"].Value, "café α → After cancellation")
            throw Error("Sending immediately after restart/cancel failed: " . ui["status"].Value)
        FileAppend("PASS New messages wait for restart then stream successfully`n", "*")
        remaining := DeepBridge_Request("POST", "/tools/ahk_script_run", Map("name", "ui_owned_lifetime.ahk", "wait", false))
        if remaining.Get("status", "") != "running"
            throw Error("Shutdown lifetime fixture did not start")
        DeepBridge_Stop()
        servicePid := g_DeepBridge["pid"]
        deadline := A_TickCount + 10000
        while ProcessExist(servicePid) && A_TickCount < deadline
            Sleep(50)
        if ProcessExist(servicePid)
            throw Error("Owned bridge services did not shut down")
        if ProcessExist(remaining["pid"])
            throw Error("Service shutdown left an orphan generated script")
        FileAppend("PASS Owned services shut down cleanly`n", "*")
        ExitApp(0)
    } catch as err {
        DeepBridge_Stop()
        FileAppend("FAIL " . err.Message . " at " . err.Line . "`n", "*")
        ExitApp(1)
    }
}
if (A_Args.Length && A_Args[1] = "/portal-ui") {
    try {
        global g_StudyReadAlongOn := false, g_StudyReadAlongPage := 0
        global g_TrackTooltipsDisabled := true
        EnvSet("DEEPSEEK_API_KEY", "synthetic-loopback-ui-fixture")
        g_StudyLLM_Endpoint := "http://127.0.0.1:18766"
        Study_SetSetting("mode", "observe")
        Study_SetSetting("sess_on", "0")
        Study_SetSetting("resume_session", "0")
        Study_SetSetting("poll_ms", "60000")
        portalGui := Gui()
        StudyLive_BuildTab(portalGui)
        StudyLive_AutoStart()
        if !g_StudySessOn || !IsObject(g_StudyConsole["gui"])
            throw Error("Portal/console did not start with legacy resume flags off")
        SetTimer(StudyLive_Tick, 0)
        FileAppend("PASS automatic startup ignores legacy resume opt-in`n", "*")
        ui := g_StudyConsole["ui"]
        if ui["chatinput"].ClassNN = ""
            throw Error("Chat input cannot be addressed by its scoped send hotkey")
        StudyConsole_Resize(g_StudyConsole["gui"], 0, 850, 520)
        ui["chatoutput"].GetPos(, &outputY, , &outputH)
        ui["chatinput"].GetPos(, &inputY, , &inputH)
        ui["status"].GetPos(, &statusY)
        if outputY + outputH >= inputY || inputY + inputH >= statusY
            throw Error("Console chat controls overlap at minimum window size")
        FileAppend("PASS console chat and activity panes fit at minimum size`n", "*")
        StudyChat_Clear()
        g_StudySessBusy := true
        g_StudyUi["chatinput"].Value := "Queued message"
        StudyChat_Send(g_StudyUi["chatinput"])
        Sleep(180)
        if g_StudyChat["state"] != "queued" || !InStr(g_StudyUi["chatstatus"].Value, "QUEUED")
            throw Error("Busy study work did not show the accepted message queue in Live Portal")
        StudyChat_Cancel()
        g_StudySessBusy := false
        if g_StudyChat["busy"] || g_StudyChat["pending"] != "" || g_StudyChat["state"] != "cancelled"
            throw Error("Queued chat cancellation did not stop dispatch")
        FileAppend("PASS busy study work queues chat visibly and permits cancellation`n", "*")
        StudyChat_Clear()
        g_StudyUi["chatinput"].Value := "UI custom message"
        if !StudyChat_Send(g_StudyUi["chatinput"])
            throw Error("Live Portal chat Send did not queue the custom message")
        deadline := A_TickCount + 12000
        while g_StudyChat["busy"] && A_TickCount < deadline
            Sleep(25)
        if g_StudyChat["busy"] || g_StudyChat["history"].Length != 2
            || !InStr(ui["chatoutput"].Value, "café α → UI custom message")
            throw Error("Custom chat did not stream into the console and retain the conversation")
        FileAppend("PASS Live Portal custom message streams into console and retains conversation`n", "*")
        chatUi := g_StudyChat["ui"]
        if !InStr(chatUi["chatoutput"].Value, "café α → UI custom message")
            || !InStr(chatUi["chatstatus"].Value, "COMPLETE") || !InStr(g_StudyUi["chatoutput"].Value, "UI custom message")
            throw Error("Dedicated chat/embedded preview did not visibly show the completed response")
        StudyChat_Resize(g_StudyChat["gui"], 0, 720, 560)
        chatUi["chatoutput"].GetPos(, &chatY, , &chatH)
        chatUi["chatstatus"].GetPos(, &chatStatusY, , &chatStatusH)
        chatUi["input"].GetPos(, &chatInputY)
        if chatY + chatH >= chatStatusY || chatStatusY + chatStatusH >= chatInputY
            throw Error("Full chat controls overlap at minimum size")
        FileAppend("PASS full chat shows reply/status without overlap at minimum size`n", "*")
        savedReply := g_StudyChat["text"]
        g_StudyChat["history"] := [], g_StudyChat["text"] := ""
        StudyChat_Restore()
        if g_StudyChat["history"].Length != 2 || !InStr(g_StudyChat["text"], "UI custom message")
            throw Error("Completed conversation did not restore from study settings")
        FileAppend("PASS completed chat history restores across restarts`n", "*")
        StudyChat_Clear()
        if g_StudyChat["history"].Length || ui["chatoutput"].Value != ""
            throw Error("New chat did not clear the transcript and history")
        FileAppend("PASS New chat resets conversation and console transcript`n", "*")
        StudyLive_Stop()
        portalGui.Destroy()
        g_StudyConsole["gui"].Destroy()
        g_StudyChat["gui"].Destroy()
        ExitApp(0)
    } catch as err {
        FileAppend("FAIL " . err.Message . " at " . err.Line . "`n", "*")
        ExitApp(1)
    }
}
if (A_Args.Length && A_Args[1] = "/monitors") {
    FileAppend(TrackJsonEncode(StudyAuto_Monitors()) . "`n", "*")
    ExitApp()
}
if (A_Args.Length && A_Args[1] = "/diagnose") {
    FileAppend("Starting geometry diagnostics`n", "*")
    candidates := WinGetList("Macro Automator Practice Portal ahk_exe chrome.exe")
    if (candidates.Length != 1)
        ExitApp(1)
    FileAppend("Pin`n", "*")
    diagPin := StudyAuto_Pin(candidates[1])
    FileAppend(diagPin["detail"] . "`n" . StudyAuto_MonitorText() . "`n", "*")
    FileAppend("Client region`n", "*")
    FileAppend(TrackJsonEncode(StudyAuto_RegionFromWindow(candidates[1])) . "`n", "*")
    FileAppend("Document region`n", "*")
    FileAppend(TrackJsonEncode(StudyAuto_Region()) . "`n", "*")
    FileAppend("Walk`n", "*")
    for , control in StudyPercept_Walk()
        FileAppend(control["kind"] . " " . control["name"] . " " . control["x"] . "," . control["y"] . "`n", "*")
    FileAppend("Done`n", "*")
    ExitApp()
}
StudyTools_Open()
g_StudyToolGui.OnEvent("Close", (*) => ExitApp())
g_StudyToolGui.Add("Button", "x16 y654 w185", "Pin Practice Chrome").OnEvent("Click", (*) => ValidationPin())
g_StudyToolGui.Add("Button", "x210 y654 w185", "Use Practice Test Tool").OnEvent("Click", (*) => ValidationTool())
g_StudyToolGui.Add("Button", "x405 y654 w185", "Arm Cancel Test").OnEvent("Click", (*) => ValidationCancel())
g_StudyToolGui.Show("h720")
g_StudyToolGui.Add("Button", "x600 y654 w210", "Run Full Validation").OnEvent("Click", (*) => SetTimer(ValidationFull, -3000))
g_StudyToolGui.Add("Button", "x600 y688 w210", "Run DeepSeek Validation").OnEvent("Click", (*) => SetTimer(() => ValidationFull(true), -3000))
if (A_Args.Length && A_Args[1] = "/selftest")
    SetTimer(ValidationFull, -3000)
if (A_Args.Length && A_Args[1] = "/selftest-deepseek")
    SetTimer(() => ValidationFull(true), -3000)
if (A_Args.Length && A_Args[1] = "/inspect")
    SetTimer(ValidationInspect, -500)
if (A_Args.Length && A_Args[1] = "/demo-math")
    SetTimer(StudyDemo_Start, -1000)
^+u::StudyLive_HotPin()
^+Esc::StudyLive_Abort()
ValidationPin() {
    windows := WinGetList("Macro Automator Practice Portal ahk_exe chrome.exe")
    if (windows.Length != 1) {
        g_StudyToolUi["status"].Value := "Open exactly one Practice Portal window in Chrome."
        return
    }
    result := StudyAuto_Pin(windows[1])
    g_StudyToolUi["status"].Value := result["detail"] . "`n" . StudyAuto_MonitorText()
}
ValidationTool() {
    if !g_StudyToolContext.Count
        return
    script := ""
    for id, c in g_StudyToolContext["catalog"] {
        switch c["name"] {
            case "Practice answer": script .= "TYPE " . id . " Mitochondria`n"
            case "Apple", "Carrot": script .= "SET " . id . " 1`n"
            case "Banana": script .= "SET " . id . " 0`n"
            case "Capital": script .= "CHOOSE " . id . " Paris`n"
        }
    }
    g_StudyToolUi["script"].Value := script
    StudyTools_Preview()
}
ValidationCancel() {
    ; Starts when Run is pressed, then aborts during the first typing step.
    g_StudyHuman["wpm"] := 25
    SetTimer(ValidationCancelCheck, 30)
    g_StudyToolUi["status"].Value := "Cancel test armed. Click Run and focus Chrome. Stops after first text appears."
}
ValidationCancelCheck() {
    if !g_StudyMacroRunning
        return
    for , c in StudyMacro_FreshControls()
        if (c["name"] = "Practice answer" && StrLen(c["value"]) > 0) {
            SetTimer(ValidationCancelCheck, 0)
            StudyLive_Abort()
            return
        }
}

; The application itself operates the practice page through production input
; code. Desktop tooling only launches this harness and observes its result.
ValidationWrite(message) {
    FileAppend(message . "`n", A_ScriptDir . "\tests\live_results.log", "UTF-8")
    g_StudyToolUi["status"].Value := message
}

ValidationCapture() {
    global g_StudyToolContext
    cap := StudyPercept_Capture()
    if !cap["ok"]
        throw Error(cap["err"])
    g_StudyToolContext := StudyTools_Context(cap)
    g_StudyToolUi["capture"].Value := "OCR: " . (cap["ocr"]["ok"] ? "OK" : "FAILED")
        . " | " . g_StudyToolContext["catalog"].Count . " named controls"
        . "`nCONTROL CATALOG:`n" . g_StudyToolContext["text"] . "`nCAPTURED OCR TEXT:`n" . cap["ocr"]["text"]
    ValidationWrite("GATHERED " . g_StudyToolContext["catalog"].Count . " named controls; question type " . cap["question"]["qtype"])
    FileAppend(g_StudyToolUi["capture"].Value . "`n", A_ScriptDir . "\tests\live_results.log", "UTF-8")
    StudyPercept_Dispose(cap["imagePath"])
    return cap["question"]
}

ValidationRun(script, q, label) {
    plan := StudyTools_Compile(script, g_StudyToolContext, "fill")
    if !plan["ok"]
        throw Error(label . ": " . plan["detail"])
    result := StudyMacro_Run(q, plan["steps"])
    trace := StudyPercept_Join(g_StudyMacroTrace)
    g_StudyToolUi["trace"].Value := trace
    FileAppend(label . "`n" . trace . "`n", A_ScriptDir . "\tests\live_results.log", "UTF-8")
    ValidationWrite((result["ok"] ? "PASS " : "STOPPED ") . label . " / " . result["done"] . " steps / " . result["detail"])
    return result
}

ValidationControl(name) {
    for , c in StudyMacro_FreshControls()
        if (c["name"] = name)
            return c
    throw Error("Missing control: " . name)
}

ValidationClick(name, q) {
    ValidationWrite("Starting native click: " . name)
    c := ValidationControl(name)
    ValidationWrite("Located: " . name)
    s := StudyMacro_StepClick(q, c)
    context := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try {
        if !StudyMacro_ExecStep(q, s, StudyAuto_Region())
            throw Error("Practice button failed: " . name . " / " . g_StudyInputFailure)
    } finally {
        DllCall("SetThreadDpiAwarenessContext", "Ptr", context, "Ptr")
    }
    ValidationWrite("Completed native click: " . name)
    Sleep(200)
}

ValidationInterrupt(kind) {
    if !g_StudyMacroRunning
        return
    c := ValidationControl("Practice answer")
    if (c["value"] = "" || c["value"] = "Mitochondria")
        return
    SetTimer(ValidationInterruptTimer, 0)
    if (kind = "cancel")
        StudyMacro_Abort()
    else
        WinActivate("ahk_id " . g_StudyToolGui.Hwnd)
}
global ValidationInterruptTimer := 0

ValidationInspect() {
    try {
        ValidationPin()
        WinActivate("ahk_id " . g_StudyPin["hwnd"])
        WinWaitActive("ahk_id " . g_StudyPin["hwnd"],, 3)
        ValidationCapture()
        text := FileRead(A_ScriptDir . "\tests\deepseek_live_validation.txt", "UTF-8")
        script := "", trace := ""
        for , line in StrSplit(text, "`n", "`r") {
            if RegExMatch(line, "^(TYPE|SET|CHOOSE|HOVER|WAIT) ")
                script .= line . "`n"
            if RegExMatch(line, "^(PASS |STOPPED |DeepSeek proposal received:|LIVE VALIDATION COMPLETE:)")
                trace .= line . "`n"
        }
        g_StudyToolUi["script"].Value := script
        g_StudyToolUi["trace"].Value := trace
        g_StudyToolUi["goal"].Value := "Type Mitochondria into Practice answer. Select Apple and Carrot. Deselect Banana. Choose Paris in Capital."
        g_StudyToolUi["status"].Value := "DeepSeek + native controller validation passed. Fresh controls are shown above. Preview and Run reuse the displayed workflow; no new API call is needed."
    } catch as err {
        g_StudyToolUi["status"].Value := err.Message
    }
    g_StudyToolGui.Show()
}

ValidationFull(useLLM := false) {
    global g_StudySessOn, g_StudyMacroCancelled, ValidationInterruptTimer, g_StudyControllerDebug, validationBusy, g_StudyToolBusy
    if validationBusy
        return
    validationBusy := true
    g_StudyToolBusy := true
    saved := g_StudyHuman.Clone()
    try {
        FileAppend("`n=== Native controller live validation " . A_Now . " ===`n", A_ScriptDir . "\tests\live_results.log", "UTF-8")
        ValidationPin()
        if !g_StudyPin["hwnd"]
            throw Error("Open the Practice Portal in Chrome first")
        WinActivate("ahk_id " . g_StudyPin["hwnd"])
        WinWaitActive("ahk_id " . g_StudyPin["hwnd"],, 3)
        g_StudySessOn := true
        g_StudyMacroCancelled := false
        g_StudyHuman["wpm"] := 100
        g_StudyHuman["typoRate"] := 0.3
        g_StudyHuman["overshootRate"] := 1
        g_StudyControllerDebug := 0
        q := ValidationCapture()
        ValidationClick("Reset demo", q)
        Sleep(600)
        q := ValidationCapture()
        ValidationTool()
        script := g_StudyToolUi["script"].Value
        ValidationWrite("DeepSeek key source: " . (StudyLLM_HasKey() ? StudyLLM_KeySource() : "not configured"))
        if useLLM {
            if !StudyLLM_HasKey()
                throw Error("DeepSeek key is not configured. Save it in the main app or set DEEPSEEK_API_KEY, then rerun.")
            goal := "Type Mitochondria into Practice answer. Select Apple and Carrot. Deselect Banana. Choose Paris in Capital. Do not press any buttons or submit."
            g_StudyToolUi["goal"].Value := goal
            ValidationWrite("Requesting a workflow from DeepSeek using the captured practice controls")
            proposal := StudyTools_RequestPlan(g_StudyToolContext, goal)
            if !proposal["ok"]
                throw Error(proposal["error"])
            script := proposal["answer"]
            g_StudyToolUi["script"].Value := script
            ValidationWrite("DeepSeek proposal received: " . proposal["model"] . " / estimated $" . Round(proposal["costUSD"], 6))
            FileAppend(script . "`n", A_ScriptDir . "\tests\live_results.log", "UTF-8")
            proposedPlan := StudyTools_Compile(script, g_StudyToolContext, "fill")
            if !proposedPlan["ok"]
                throw Error("Provider workflow rejected: " . proposedPlan["detail"])
            g_StudyToolUi["trace"].Value := StudyMacro_Preview(proposedPlan["steps"])
        }
        result := ValidationRun(script, q, "text / checkboxes / dropdown")
        if !result["ok"]
            throw Error(result["detail"])
        if (ValidationControl("Practice answer")["value"] != "Mitochondria"
            || !ValidationControl("Apple")["checked"] || ValidationControl("Banana")["checked"]
            || !ValidationControl("Carrot")["checked"] || ValidationControl("Capital")["value"] != "Paris")
            throw Error("Final accessible values do not match the workflow")
        ValidationWrite("PASS final values: Mitochondria / Apple+Carrot / Banana cleared / Paris")
        oldX := ValidationControl("Practice answer")["x"]
        ValidationClick("Move answer field", q)
        if (ValidationControl("Practice answer")["x"] = oldX)
            throw Error("Practice relocation did not happen")
        result := ValidationRun(script, q, "stale bounds relocate / repeated SET idempotence")
        if !result["ok"]
            throw Error(result["detail"])
        g_StudyHuman["typoRate"] := 0
        g_StudyHuman["wpm"] := 25
        textId := ""
        for id, c in g_StudyToolContext["catalog"]
            if (c["name"] = "Practice answer")
                textId := id
        for , kind in ["focus", "cancel"] {
            WinActivate("ahk_id " . g_StudyPin["hwnd"])
            WinWaitActive("ahk_id " . g_StudyPin["hwnd"],, 3)
            q := ValidationCapture()
            g_StudyHuman["wpm"] := 100
            restored := ValidationRun("TYPE " . textId . " Mitochondria", q, "prepare " . kind . " baseline")
            if !restored["ok"]
                throw Error("Could not prepare interruption baseline")
            g_StudyHuman["wpm"] := 25
            ValidationInterruptTimer := ValidationInterrupt.Bind(kind)
            SetTimer(ValidationInterruptTimer, 30)
            result := ValidationRun("TYPE " . textId . " Interrupted typing must stop immediately", q, kind . " interruption")
            SetTimer(ValidationInterruptTimer, 0)
            interrupted := ValidationControl("Practice answer")["value"]
            Sleep(500)
            if (result["ok"] || interrupted = "" || interrupted = "Interrupted typing must stop immediately"
                || ValidationControl("Practice answer")["value"] != interrupted)
                throw Error(kind . " interruption did not stop partial typing")
            ValidationWrite("PASS " . kind . " stopped partial input at: " . interrupted)
            g_StudyMacroCancelled := false
        }
        WinActivate("ahk_id " . g_StudyPin["hwnd"])
        WinWaitActive("ahk_id " . g_StudyPin["hwnd"],, 3)
        q := ValidationCapture()
        g_StudyHuman["wpm"] := 100
        result := ValidationRun(script, q, "final demonstration")
        if !result["ok"]
            throw Error(result["detail"])
        ValidationClick("Check answer", q)
        ValidationWrite("LIVE VALIDATION COMPLETE: values, relocation, idempotence, focus loss and ABORT passed. The page shows the gathered values and input counters.")
    } catch as err {
        ValidationWrite("LIVE VALIDATION FAILED: " . err.Message . " at " . err.File . ":" . err.Line . "`n" . err.Stack)
    } finally {
        if IsObject(ValidationInterruptTimer)
            SetTimer(ValidationInterruptTimer, 0)
        for key, value in saved
            g_StudyHuman[key] := value
        g_StudySessOn := false
        validationBusy := false
        g_StudyToolBusy := false
        log := FileRead(A_ScriptDir . "\tests\live_results.log", "UTF-8")
        last := InStr(log, "=== Native controller live validation", true, -1)
        if last {
            output := FileOpen(A_ScriptDir . "\tests\last_live_validation.txt", "w", "UTF-8")
            output.Write(SubStr(log, last))
            output.Close()
        }
    }
}
