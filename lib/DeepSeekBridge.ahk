#Include DeepSeekPane.ahk
#Include AgentWorkbench.ahk
#Include DeepSeekImages.ahk
; Dedicated interface for the supplied DeepSeek AHK bridge project.
; Services inherit the existing Credential Manager key; it is never saved in .env.
global g_DeepBridge := Map("root", A_ScriptDir . "\DeepSeekBridge", "ui", Map(), "pid", 0,
    "key", "", "task", "", "cursor", 0, "busy", false, "polling", false,
    "history", [], "text", "", "reply", "", "thinking", "", "log", "", "prompt", "",
    "status", "idle", "detail", "Ready", "started", 0, "requests", [], "viewOnly", false, "restored", false, "restarting", false, "scripts", [], "images", [])

DeepBridge_BuildTab(gui) {
    global TabCtrl
    ui := g_DeepBridge["ui"]
    before := Map()
    for control in gui
        before[control.Hwnd] := true
    gui.SetFont("s14 Bold", "Segoe UI")
    gui.Add("Text", "x20 y85 w720 h25", "DeepSeek Bridge — Agent, Tools & Automations")
    gui.SetFont("s9 Norm", "Segoe UI")
    gui.Add("Button", "x20 y116 w115 h25", "Start services").OnEvent("Click", (*) => DeepBridge_Start())
    gui.Add("Button", "x143 y116 w115 h25", "Stop services").OnEvent("Click", (*) => DeepBridge_Stop())
    gui.Add("Button", "x266 y116 w115 h25", "Live workbench").OnEvent("Click", (*) => AgentWorkbench_Open())
    gui.Add("Button", "x389 y116 w120 h25", "Code / Tools").OnEvent("Click", (*) => FanHarness_Open("index"))
    gui.Add("Button", "x517 y116 w105 h25", "Save API key").OnEvent("Click", (*) => DeepBridge_SaveKey())
    gui.Add("Button", "x630 y116 w105 h25", "Service logs").OnEvent("Click", (*) => DeepBridge_OpenLogs())
    gui.Add("Button", "x743 y116 w125 h25", "MCP setup file").OnEvent("Click", (*) => DeepBridge_OpenPatch())
    ui["services"] := gui.Add("Text", "x20 y147 w850 h32", "Services starting on program launch…")
    ui["conversationTitle"] := gui.Add("Text", "x20 y182 w535 h20", "Conversation")
    ui["thinkingTitle"] := gui.Add("Text", "x578 y182 w295 h20", "Model-provided thinking")
    ui["panel"] := gui.Add("DropDownList","x20 y180 w210 Choose2",["Conversation","Thinking","Tool activity"])
    ui["panel"].OnEvent("Change",(*)=>DeepBridge_ChangePanel(gui))
    ui["output"] := gui.Add("Edit", "x20 y205 w542 h327 ReadOnly Multi +Wrap +VScroll")
    ui["thinking"] := gui.Add("Edit", "x578 y205 w295 h133 ReadOnly Multi +Wrap +VScroll")
    ui["activityTitle"] := gui.Add("Text", "x578 y348 w295 h20", "Tool calls, results & activity")
    ui["activity"] := gui.Add("Edit", "x578 y372 w295 h160 ReadOnly Multi +Wrap +VScroll")
    ui["status"] := gui.Add("Text", "x20 y540 w850 h26", "Ready — one agent can chat, inspect Fan, compose tools and run scripts.")
    ui["catalog"] := gui.Add("Button", "x20 y569 w112 h25", "Saved tools / API")
    ui["catalog"].OnEvent("Click", (*) => DeepBridge_OpenCatalog())
    ui["paste"] := gui.Add("Button","x144 y569 w96 h25","Paste image")
    ui["paste"].OnEvent("Click",DeepBridge_PasteImage)
    ui["preview"] := gui.Add("Button","x247 y569 w70 h25","Preview")
    ui["preview"].OnEvent("Click",DeepBridge_PreviewImage)
    ui["clearImages"] := gui.Add("Button","x324 y569 w65 h25","Remove")
    ui["clearImages"].OnEvent("Click",DeepBridge_ClearImages)
    ui["attachment"] := gui.Add("Text","x397 y569 w240 h32","Paste a snip into the message box · Ctrl+V")
    ui["effortTitle"] := gui.Add("Text", "x650 y573 w58 h20", "Thinking")
    ui["effort"] := gui.Add("DropDownList", "x718 y569 w140 Choose4", ["none", "low", "high", "max"])
    ui["effort"].OnEvent("Change", (*) => DeepBridge_ConfigChanged())
    ui["input"] := gui.Add("Edit", "x20 y603 w682 h85 Multi +Wrap +VScroll")
    ui["send"] := gui.Add("Button", "x714 y603 w158 h32", "Send message")
    ui["send"].OnEvent("Click", (*) => DeepBridge_Send())
    ui["cancel"] := gui.Add("Button", "x714 y644 w158 h32 Disabled", "Stop request")
    ui["cancel"].OnEvent("Click", (*) => DeepBridge_Cancel())
    ui["new"] := gui.Add("Button", "x20 y700 w100 h26", "New chat")
    ui["new"].OnEvent("Click", (*) => DeepBridge_Clear())
    ui["load"] := gui.Add("Button", "x132 y700 w100 h26", "Load history")
    ui["load"].OnEvent("Click", (*) => DeepBridge_LoadHistory())
    ui["tasks"] := gui.Add("DropDownList", "x244 y700 w480")
    ui["view"] := gui.Add("Button", "x736 y700 w137 h26", "View request")
    ui["view"].OnEvent("Click", (*) => DeepBridge_View())
    HotIf((*) => WinActive("ahk_id " . gui.Hwnd) && DeepBridge_InputFocused())
    Hotkey("^Enter", (*) => DeepBridge_Send(), "On")
    HotIf()
    HotIf((*) => WinActive("ahk_id " . gui.Hwnd) && DeepBridge_InputFocused() && DeepBridge_HasClipboardImage())
    Hotkey("$^v",DeepBridge_PasteImage,"On")
    HotIf()
    OnMessage(0x0302,DeepBridge_OnPaste)
    g_DeepBridge["controls"] := []
    for control in gui
        if !before.Has(control.Hwnd)
            g_DeepBridge["controls"].Push(control)
    gui.OnEvent("Size", DeepBridge_Resize)
    TabCtrl.OnEvent("Change", (*)=>DeepBridge_Render())
    DeepBridge_Restore()
    DeepBridge_Render()
    DeepBridge_ChangePanel(gui)
}

DeepBridge_ChangePanel(gui) {
    gui.GetClientPos(,,&width,&height)
    DeepBridge_Resize(gui,0,width,height)
}

DeepBridge_Resize(gui, state, width, height) {
    global TabCtrl
    if state = -1 || !g_DeepBridge["ui"].Count
        return
    ui := g_DeepBridge["ui"], width := Max(900, width), height := Max(780, height)
    content := width-40, paneHeight := Max(180,height-482)
    ui["services"].Move(,,content)
    for name in ["conversationTitle","thinkingTitle","activityTitle"]
        ui[name].Visible := false
    for index,name in ["output","thinking","activity"] {
        ui[name].Move(20,215,content,paneHeight)
        ui[name].SetFont("s10","Segoe UI")
        ui[name].Visible := TabCtrl.Value=20 && ui["panel"].Value=index
    }
    ui["status"].Move(20,height-264,content,26)
    for , name in ["catalog", "effort", "paste", "preview", "clearImages", "attachment"]
        ui[name].Move(,height-232)
    for , name in ["effortTitle"]
        ui[name].Move(,height-228)
    ui["input"].Move(20,height-197,content-170,85)
    ui["send"].Move(width-178,height-197)
    ui["cancel"].Move(width-178,height-156)
    for , name in ["new", "load", "tasks", "view"]
        ui[name].Move(,height-100)
    ui["tasks"].Move(,,width-420)
    ui["view"].Move(width-164)
}

DeepBridge_InputFocused() {
    try return ControlGetFocus("A") = g_DeepBridge["ui"]["input"].ClassNN
    return false
}

DeepBridge_AutoStart() {
    OnExit(DeepBridge_OnExit)
    OnExit(DeepActivity_Shutdown)
    SetTimer(DeepBridge_Start, -600)
}

DeepBridge_Start(*) {
    if g_DeepBridge["restarting"]
        return true
    root := g_DeepBridge["root"]
    if g_DeepBridge["pid"] && ProcessExist(g_DeepBridge["pid"])
        return true
    python := g_DeepBridge.Get("python", root . "\.venv\Scripts\python.exe")
    if !FileExist(python) {
        DeepBridge_SetStatus("error", "Bridge dependencies are missing. Run fan\DeepSeekBridge\install.bat once.")
        return false
    }
    settings := Map("DEEPSEEK_API_KEY", StudyLLM_Key(), "AUTOHOTKEY_EXE", A_AhkPath,
        "DEEPSEEK_MODEL", g_StudyLLM_TextModel, "DEEPSEEK_VISION_MODEL", "deepseek-flash", "ALLOW_AGENT_SCRIPTS", "1",
        "DEEPSEEK_REASONING_EFFORT", g_DeepBridge["ui"]["effort"].Text,
        "DEEPSEEK_BASE_URL", g_StudyLLM_Endpoint, "FAN_PROJECT_ROOT", FanAPI_Repository())
    saved := Map()
    ; Run inherits environment synchronously. Restore it immediately afterwards.
    try {
        settings["BRIDGE_DB"] := FanData_DbAvailable("bridge", FanData_DbPath("bridge", root . "\bridge.sqlite3"))
        settings["FAN_TOOL_INDEX"] := FanData_DbAvailable("catalog", FanData_DbPath("catalog", root . "\.runtime\tool_catalog.sqlite3"))
        for name, value in settings {
            saved[name] := EnvGet(name)
            EnvSet(name, value)
        }
        Run('"' . python . '" -m bridge.desktop --parent ' . DllCall("GetCurrentProcessId", "uint"), root, "Hide", &pid)
        g_DeepBridge["pid"] := pid
        g_DeepBridge["key"] := settings["DEEPSEEK_API_KEY"]
        DeepBridge_SetStatus(g_DeepBridge["busy"] ? "queued" : "starting", "Starting gateway, agent, worker and observatory…")
        SetTimer(DeepBridge_Poll, 350)
        return true
    } catch as err {
        DeepBridge_SetStatus("error", "Could not start bridge: " . err.Message)
        return false
    } finally {
        for name, value in saved
            EnvSet(name, value)
    }
}

DeepBridge_Stop(*) {
    DeepActivity_Shutdown()
    SetTimer(DeepBridge_Start, 0)
    SetTimer(DeepBridge_RestartWhenStopped, 0)
    g_DeepBridge["restarting"] := false
    if g_DeepBridge["busy"]
        DeepBridge_Cancel()
    if g_DeepBridge["busy"]
        DeepBridge_Finish("cancelled", "Bridge services stopped")
    if g_DeepBridge["pid"] && ProcessExist(g_DeepBridge["pid"]) {
        runtime := g_DeepBridge["root"] . "\.runtime"
        DirCreate(runtime)
        try FileAppend("stop", runtime . "\stop", "UTF-8")
    }
    g_DeepBridge["status"] := "stopping"
    DeepBridge_SetStatus("stopping", "Stopping this tab's bridge services…")
}

DeepBridge_OnExit(*) {
    ; Exit handlers must also work after the interface has already been destroyed.
    if g_DeepBridge["busy"] && g_DeepBridge["task"] != ""
        try DeepBridge_Request("POST", "/tasks/" . g_DeepBridge["task"] . "/cancel")
    if g_DeepBridge["pid"] && ProcessExist(g_DeepBridge["pid"])
        try FileAppend("stop", g_DeepBridge["root"] . "\.runtime\stop", "UTF-8")
}

DeepBridge_ConfigChanged() {
    if g_DeepBridge["busy"]
        return
    DeepBridge_Restart()
}

DeepBridge_Restart() {
    DeepBridge_Stop()
    g_DeepBridge["restarting"] := true
    SetTimer(DeepBridge_RestartWhenStopped, 250)
}

DeepBridge_RestartWhenStopped() {
    if g_DeepBridge["pid"] && ProcessExist(g_DeepBridge["pid"])
        return
    SetTimer(DeepBridge_RestartWhenStopped, 0)
    g_DeepBridge["pid"] := 0
    g_DeepBridge["restarting"] := false
    DeepBridge_Start()
}

DeepBridge_Token() {
    try {
        config := FileRead(g_DeepBridge["root"] . "\.env", "UTF-8")
        if RegExMatch(config, "m)^BRIDGE_TOKEN=([^\r\n]+)", &match)
            return Trim(match[1])
    }
    return ""
}

DeepBridge_Port(name := "BRIDGE_PORT", fallback := 8765) {
    try {
        config := FileRead(g_DeepBridge["root"] . "\.env", "UTF-8")
        if RegExMatch(config, "m)^" . name . "=(\d+)", &match)
            return Integer(match[1])
    }
    return fallback
}

DeepBridge_Request(method, path, data := 0) {
    token := DeepBridge_Token()
    if token = ""
        throw Error("Bridge is still starting; please wait for services to be ready.")
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.SetProxy(1) ; Loopback traffic never needs the system proxy.
    req.SetTimeouts(1000, 1000, 3000, 5000)
    req.Open(method, "http://127.0.0.1:" . DeepBridge_Port() . path, false)
    req.SetRequestHeader("X-Bridge-Token", token)
    req.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
    req.Send(IsObject(data) ? TrackJsonEncode(data) : "")
    doc := TrackJsonDecode(req.ResponseText)
    if req.Status < 200 || req.Status >= 300
        throw Error("Bridge HTTP " . req.Status . ": " . doc.Get("detail", "request failed"))
    return doc
}

DeepBridge_Send(*) {
    if g_DeepBridge["busy"]
        return false
    ui := g_DeepBridge["ui"], prompt := Trim(ui["input"].Value)
    if prompt = "" {
        if !g_DeepBridge["images"].Length
            return false
        prompt := "Analyze the attached image and explain what is visible."
    }
    if StrLen(prompt) > 12000 {
        DeepBridge_SetStatus("error", "Message exceeds 12,000 characters. Shorten it and resend.")
        return false
    }
    key := StudyLLM_Key()
    if key = "" {
        DeepBridge_SetStatus("error", "Save a DeepSeek API key, then send your message. Your draft is preserved.")
        return false
    }
    restarting := key != g_DeepBridge["key"] && g_DeepBridge["pid"] && ProcessExist(g_DeepBridge["pid"])
    if restarting
        DeepBridge_Restart()
    if g_DeepBridge["viewOnly"] {
        g_DeepBridge["viewOnly"] := false
        DeepBridge_RestoreText()
    }
    g_DeepBridge["prompt"] := prompt
    g_DeepBridge["reply"] := "", g_DeepBridge["thinking"] := "", g_DeepBridge["log"] := ""
    g_DeepBridge["task"] := "", g_DeepBridge["cursor"] := 0
    g_DeepBridge["busy"] := true, g_DeepBridge["started"] := A_TickCount
    g_DeepBridge["text"] .= (g_DeepBridge["text"] != "" ? "`r`n`r`n" : "") . "You: " . prompt . "`r`n`r`nDeepSeek: "
    ui["input"].Value := ""
    DeepBridge_SetStatus("queued", "Message accepted — waiting for bridge services")
    if !restarting && !DeepBridge_Start() {
        g_DeepBridge["busy"] := false
        ui["input"].Value := prompt
        DeepBridge_Render()
        return false
    }
    SetTimer(DeepBridge_Poll, 350)
    return true
}

; Explicit CLI entry: load a local prompt as a draft; --send opts into execution.
DeepBridge_LoadPrompt(path, send := false) {
    global MainGui, TabCtrl
    try {
        prompt := FileRead(path,"UTF-8")
        if StrLen(prompt)>12000 || Trim(prompt)=""
            throw Error("Prompt must contain 1..12000 characters")
        TabCtrl.Choose(20)
        MainGui.Show()
        g_DeepBridge["ui"]["input"].Value := prompt
        if send
            DeepBridge_Send()
    } catch as err
        DeepBridge_SetStatus("error","Could not load prompt: " . err.Message)
}

; Reopen a completed run with its retained stream and the actual AHK inventory.
DeepBridge_ShowResults(taskId, attempt := 0) {
    global MainGui, TabCtrl
    if !RegExMatch(taskId,"^[a-f0-9]{32}$")
        return
    try {
        DeepBridge_LoadHistory()
        found := 0
        for index, item in g_DeepBridge["requests"]
            if item["id"] = taskId
                found := index
        if !found
            throw Error("Waiting for saved run history")
        g_DeepBridge["ui"]["tasks"].Choose(found)
        DeepBridge_View()
        TabCtrl.Choose(20)
        MainGui.Show()
        DeepBridge_OpenCatalog()
        DeepBridge_CatalogRefresh(true)
    } catch as err {
        if attempt<20
            SetTimer(DeepBridge_ShowResults.Bind(taskId,attempt+1),-1500)
        else
            DeepBridge_SetStatus("error",err.Message)
    }
}

DeepBridge_Poll() {
    if g_DeepBridge["polling"] || !g_DeepBridge["ui"].Count
        return
    g_DeepBridge["polling"] := true
    try {
        if g_DeepBridge["restarting"] {
            DeepBridge_Render()
            return
        }
        state := Map()
        try state := TrackJsonDecode(FileRead(g_DeepBridge["root"] . "\.runtime\services.json", "UTF-8"))
        alive := g_DeepBridge["pid"] && ProcessExist(g_DeepBridge["pid"])
        if !alive {
            DeepActivity_Set(false)
            DeepActivity_Clear()
            if g_DeepBridge["status"] = "stopping"
                DeepBridge_SetStatus("stopped", "Bridge services stopped. Send starts them automatically.")
            else if state.Get("error", "") != "" {
                DeepBridge_SetStatus("error", state["error"])
                if g_DeepBridge["busy"]
                    DeepBridge_Finish("error", state["error"])
            } else if g_DeepBridge["busy"] && A_TickCount-g_DeepBridge["started"] > 10000 {
                DeepBridge_Finish("error", "Bridge supervisor exited before services were ready. Open Service logs and retry.")
            } else if g_DeepBridge["status"] = "starting" && g_DeepBridge["pid"] {
                DeepBridge_SetStatus("error", "Bridge services could not start. Open Service logs.")
            }
            return
        }
        health := DeepBridge_Request("GET", "/health")
        g_DeepBridge["scripts"] := health.Get("managed_scripts", [])
        activity := health.Get("activity", Map()), calls := activity.Get("tools", [])
        active := activity.Get("running_tasks", 0) || calls.Length || g_DeepBridge["scripts"].Length || activity.Get("application_runs", 0)
        label := calls.Length ? "Tool · " . calls[1] : g_DeepBridge["scripts"].Length ? "Running script" : activity.Get("application_runs", 0) ? "Job application runner" : "Agent running"
        DeepActivity_Set(active, label)
        services := health.Get("services", Map()), children := services.Get("children", Map())
        ready := health.Get("windows_worker", false) && children.Has("agent") && children["agent"].Get("alive", false)
        g_DeepBridge["ui"]["services"].Value := "Gateway " . DeepBridge_Port() . " · Agent " . (children.Has("agent") ? "running" : "starting")
            . " · AHK worker " . (health.Get("windows_worker", false) ? "connected" : "connecting")
            . " · Fan APIs " . (health.Get("fan_connected", false) ? "connected" : "connecting")
            . " · Observatory " . DeepBridge_Port("MONITOR_PORT", 8766)
            . " · " . (services.Get("key_loaded", false) ? "API key configured" : "Save API key to chat")
            . " · Running scripts " . g_DeepBridge["scripts"].Length
        if g_DeepBridge["busy"] && g_DeepBridge["task"] = "" && ready {
            images := DeepBridge_PrepareImages()
            queued := DeepBridge_Request("POST", "/tasks", Map("prompt", g_DeepBridge["prompt"], "history", g_DeepBridge["history"], "images", images))
            g_DeepBridge["task"] := queued["id"]
            g_DeepBridge["images"] := []
            DeepBridge_ImageStatus()
            DeepBridge_SetStatus("queued", "Queued for DeepSeek · Fan tools and script execution available")
        }
        if g_DeepBridge["task"] != "" {
            page := DeepBridge_Request("GET", "/tasks/" . g_DeepBridge["task"] . "/events?after=" . g_DeepBridge["cursor"])
            for , event in page["events"]
                DeepBridge_Event(event)
            g_DeepBridge["cursor"] := page["cursor"]
            task := DeepBridge_Request("GET", "/tasks/" . g_DeepBridge["task"])
            if g_DeepBridge["busy"] {
                if RegExMatch(task["status"], "^(complete|error|cancelled)$")
                    DeepBridge_Finish(task["status"], task["response"])
                else if task["status"] = "running" && g_DeepBridge["status"] = "queued"
                    DeepBridge_SetStatus("connecting", "DeepSeek request running — waiting for first token")
            }
        } else if !g_DeepBridge["busy"] && g_DeepBridge["status"] = "starting" && ready
            DeepBridge_SetStatus("idle", "Ready — type a message. Ctrl+Enter sends from the composer.")
        DeepBridge_Render()
    } catch as err {
        ; A lost heartbeat must not leave a stale red control indicator.
        DeepActivity_Set(false)
        DeepActivity_Clear()
        if g_DeepBridge["busy"] && A_TickCount - g_DeepBridge["started"] > 60000 && g_DeepBridge["task"] = ""
            DeepBridge_Finish("error", "Services did not become ready. Open Service logs. " . err.Message)
        else if g_DeepBridge["busy"]
            g_DeepBridge["ui"]["status"].Value := "RECONNECTING · " . Round((A_TickCount-g_DeepBridge["started"])/1000) . "s · " . err.Message
    } finally {
        g_DeepBridge["polling"] := false
    }
}

DeepBridge_Event(event) {
    kind := event["kind"], payload := event["payload"]
    if kind = "agent_text" {
        if g_DeepBridge["busy"] {
            g_DeepBridge["reply"] .= payload.Get("text", "")
            DeepBridge_SetStatus("streaming", "Receiving answer · " . StrLen(g_DeepBridge["reply"]) . " characters")
        }
    } else if kind = "reasoning" {
        g_DeepBridge["thinking"] .= payload.Get("text", "")
        if g_DeepBridge["busy"]
            DeepBridge_SetStatus("thinking", "DeepSeek is thinking · " . StrLen(g_DeepBridge["thinking"]) . " characters")
    } else {
        if kind = "agent_tool_call" && g_DeepBridge["busy"]
            DeepBridge_SetStatus("tool", "Using " . payload.Get("name", "desktop tool"))
        detail := kind . ": " . payload.Get("name",payload.Get("method",""))
        if kind="agent_tool_result" {
            result := payload.Get("result",Map())
            detail .= " · " . (result.Get("ok",true) ? "returned" : "failed")
            if result.Has("error")
                detail .= " · " . result["error"]
            if result.Has("name")
                detail .= " · " . result["name"]
            if result.Has("completed")
                detail .= " · " . result["completed"] . " steps completed"
        } else if payload.Has("text")
            detail .= " · " . SubStr(payload["text"],1,500)
        g_DeepBridge["log"] .= (g_DeepBridge["log"] != "" ? "`r`n" : "") . detail
        if StrLen(g_DeepBridge["log"]) > 48000
            g_DeepBridge["log"] := SubStr(g_DeepBridge["log"], -40000)
    }
}

DeepBridge_Finish(status, response) {
    if status = "cancelled" || status = "error" {
        DeepActivity_Set(false)
        DeepActivity_Clear()
    }
    if status = "complete" {
        g_DeepBridge["reply"] := response
        detail := "Reply complete · " . StrLen(response) . " characters"
    } else {
        g_DeepBridge["reply"] .= "`r`n[" . StrUpper(status) . "] " . response
        if status = "error"
            g_DeepBridge["ui"]["input"].Value := g_DeepBridge["prompt"]
        detail := response != "" ? response : "Stopped by user"
    }
    if g_DeepBridge["prompt"]!="" {
        checkpoint := status="complete" ? response : "Previous run " . status . "; task " . g_DeepBridge["task"] . ". Outcomes are incomplete; verify live state and saved evidence before repeating input. " . response
        g_DeepBridge["history"].Push(Map("role","user","content",g_DeepBridge["prompt"]))
        g_DeepBridge["history"].Push(Map("role","assistant","content",SubStr(checkpoint,1,16000)))
        while g_DeepBridge["history"].Length>20
            g_DeepBridge["history"].RemoveAt(1)
        try Study_SetSetting("bridge_chat_history",StudyConsole_Redact(TrackJsonEncode(g_DeepBridge["history"])))
    }
    g_DeepBridge["text"] .= g_DeepBridge["reply"]
    g_DeepBridge["reply"] := "", g_DeepBridge["busy"] := false
    DeepBridge_SetStatus(status, detail)
}

DeepBridge_Cancel(*) {
    if !g_DeepBridge["busy"] && !g_DeepBridge["scripts"].Length
        return
    ; Async scripts can still be running after the agent has answered.
    pending := []
    for , script in g_DeepBridge["scripts"] {
        try {
            result := DeepBridge_Request("POST", "/tools/ahk_script_cancel", Map("run_id", script["run_id"]))
            if result.Get("status", "running") = "running"
                pending.Push(script)
        } catch
            pending.Push(script)
    }
    g_DeepBridge["scripts"] := pending
    if !g_DeepBridge["busy"] {
        DeepBridge_SetStatus(pending.Length ? "error" : "stopped", pending.Length ? "Some script runs could not be stopped; retry or Stop services." : "Owned script runs stopped")
        return
    }
    if g_DeepBridge["task"] != "" {
        try DeepBridge_Request("POST", "/tasks/" . g_DeepBridge["task"] . "/cancel")
        catch as err {
            DeepBridge_SetStatus("error", "Stop could not reach the gateway: " . err.Message)
            return
        }
        ; Interrupt the owned agent's HTTP receive, including a first-token wait.
        signal := g_DeepBridge["root"] . "\.runtime\cancel-agent"
        try {
            if FileExist(signal)
                FileDelete(signal)
            FileAppend(g_DeepBridge["task"], signal, "UTF-8-RAW")
        }
    }
    DeepBridge_Finish("cancelled", "Stopped by user")
}

DeepBridge_SetStatus(state, detail) {
    g_DeepBridge["status"] := state
    g_DeepBridge["detail"] := detail
    DeepBridge_Render()
}

DeepBridge_Render() {
    global TabCtrl
    ui := g_DeepBridge["ui"]
    if !ui.Count
        return
    ui["status"].Value := StrUpper(g_DeepBridge["status"]) . (g_DeepBridge["busy"] ? " · " . Round((A_TickCount-g_DeepBridge["started"])/1000) . "s" : "") . " · " . g_DeepBridge["detail"]
    DeepBridge_Pane(ui["output"], g_DeepBridge["text"] . g_DeepBridge["reply"])
    DeepBridge_Pane(ui["thinking"], g_DeepBridge["thinking"])
    DeepBridge_Pane(ui["activity"], g_DeepBridge["log"])
    for index,name in ["output","thinking","activity"]
        ui[name].Visible := TabCtrl.Value=20 && ui["panel"].Value=index
    for , name in ["send", "new", "effort", "view", "paste", "clearImages"]
        ui[name].Enabled := !g_DeepBridge["busy"]
    ui["cancel"].Enabled := g_DeepBridge["busy"] || g_DeepBridge["scripts"].Length > 0
}

DeepBridge_Clear(*) {
    if g_DeepBridge["busy"]
        return
    for , field in ["text", "reply", "thinking", "log", "task", "prompt"]
        g_DeepBridge[field] := ""
    g_DeepBridge["history"] := [], g_DeepBridge["viewOnly"] := false
    g_DeepBridge["images"] := []
    DeepBridge_ImageStatus()
    try Study_SetSetting("bridge_chat_history", "[]")
    DeepBridge_SetStatus("idle", "New conversation ready. Request history remains available.")
}

DeepBridge_Restore() {
    if g_DeepBridge["restored"]
        return
    g_DeepBridge["restored"] := true
    try {
        prior := TrackJsonDecode(Study_GetSetting("bridge_chat_history", "[]"))
        if prior is Array
            for , message in prior
                if IsObject(message) && RegExMatch(message.Get("role", ""), "^(user|assistant)$") && message.Has("content")
                    g_DeepBridge["history"].Push(message)
    }
    DeepBridge_RestoreText()
}

DeepBridge_RestoreText() {
    g_DeepBridge["text"] := ""
    for , message in g_DeepBridge["history"]
        g_DeepBridge["text"] .= (g_DeepBridge["text"] != "" ? "`r`n`r`n" : "") . (message["role"] = "user" ? "You: " : "DeepSeek: ") . message["content"]
}

DeepBridge_LoadHistory(*) {
    try {
        tasks := DeepBridge_Request("GET", "/history")["tasks"]
        items := []
        for , task in tasks
            items.Push(task["status"] . " · " . SubStr(StrReplace(task["prompt"], "`n", " "), 1, 65))
        g_DeepBridge["requests"] := tasks
        g_DeepBridge["ui"]["tasks"].Delete()
        g_DeepBridge["ui"]["tasks"].Add(items)
        if items.Length
            g_DeepBridge["ui"]["tasks"].Choose(1)
    } catch as err
        DeepBridge_SetStatus("error", "Could not load request history: " . err.Message)
}

DeepBridge_View(*) {
    if g_DeepBridge["busy"]
        return
    index := g_DeepBridge["ui"]["tasks"].Value
    if index < 1 || index > g_DeepBridge["requests"].Length
        return
    task := g_DeepBridge["requests"][index]
    g_DeepBridge["history"] := [Map("role","user","content",task["prompt"]),Map("role","assistant","content",
        "Selected recorded run " . task["id"] . " has status " . task["status"] . ". This is historical context; verify current state before resuming actions. " . SubStr(task["response"],1,15000))]
    g_DeepBridge["viewOnly"] := true
    g_DeepBridge["text"] := "You: " . task["prompt"] . "`r`n`r`nDeepSeek: " . task["response"]
    g_DeepBridge["reply"] := "", g_DeepBridge["thinking"] := "", g_DeepBridge["log"] := ""
    g_DeepBridge["task"] := task["id"], g_DeepBridge["cursor"] := 0
    DeepBridge_SetStatus("history", "Viewing " . task["status"] . " request · " . task["created_at"])
}

DeepBridge_SaveKey() {
    ib := InputBox("Paste the DeepSeek API key. Saved in Windows Credential Manager, shared with Live Portal.", "DeepSeek Bridge API key", "Password w420")
    if ib.Result != "OK" || Trim(ib.Value) = ""
        return
    if !StudyLLM_SaveKey(Trim(ib.Value)) {
        DeepBridge_SetStatus("error", "Could not save the API key")
        return
    }
    ib := ""
    DeepBridge_Restart()
}

DeepBridge_OpenMonitor() {
    AgentWorkbench_Open()
}

DeepBridge_OpenLogs() {
    path := g_DeepBridge["root"] . "\.runtime"
    DirCreate(path)
    Run(path)
}

DeepBridge_OpenCatalog() {
    if g_DeepBridge.Has("catalogGui") && IsObject(g_DeepBridge["catalogGui"]) {
        g_DeepBridge["catalogGui"].Show()
        return
    }
    window := Gui("+Resize +MinSize820x640", "DeepSeek Tools — Saved Scripts, Patterns, Workflows & API")
    window.SetFont("s9", "Segoe UI")
    window.Add("Text", "x14 y12 w790 h32", "The agent can search, write, edit and run these tools. Saved descriptions, usage and revisions provide its persistent tool memory.")
    query := window.Add("Edit", "x14 y52 w490 h25")
    window.Add("Button", "x516 y52 w110 h25", "Search / Refresh").OnEvent("Click", (*) => DeepBridge_CatalogRefresh())
    window.Add("Button", "x638 y52 w165 h25", "Live Fan API catalog").OnEvent("Click", (*) => DeepBridge_CatalogCapabilities())
    list := window.Add("ListView", "x14 y90 w790 h220", ["Kind", "Name", "Description", "Revision"])
    list.ModifyCol(1, 90), list.ModifyCol(2, 220), list.ModifyCol(3, 395), list.ModifyCol(4, 60)
    details := window.Add("Edit", "x14 y323 w790 h278 ReadOnly Multi +Wrap +VScroll")
    pageButton := window.Add("Button", "x14 y606 w190 h26", "Local Chrome Page Learner")
    pageButton.OnEvent("Click", (*) => Run('"' . A_AhkPath . '" "' . A_ScriptDir . '\ChromePageLearner.ahk"'))
    jobsButton := window.Add("Button", "x220 y606 w200 h26", "Application Preparation Queue")
    jobsButton.OnEvent("Click", (*) => Run('"' . A_AhkPath . '" "' . A_ScriptDir . '\ApplicationQueue.ahk"'))
    scriptButton := window.Add("Button", "x436 y606 w180 h26", "Written .ahk files")
    scriptButton.OnEvent("Click", (*) => DeepBridge_CatalogRefresh(true))
    list.OnEvent("ItemSelect", (control, row, selected) => selected ? DeepBridge_CatalogSelect(row) : 0)
    g_DeepBridge["catalogGui"] := window
    g_DeepBridge["catalogUi"] := Map("query", query, "list", list, "details", details, "records", [], "pageButton", pageButton, "jobsButton", jobsButton,"scriptButton",scriptButton)
    window.OnEvent("Close", (*) => window.Hide())
    window.OnEvent("Size", (g, state, width, height) => state=-1 ? 0 : DeepBridge_CatalogResize(width, height))
    window.Show("w820 h640")
    DeepBridge_CatalogRefresh()
}

DeepBridge_CatalogResize(width, height) {
    ui := g_DeepBridge["catalogUi"]
    ui["list"].Move(,,width-28,220)
    ui["details"].Move(14,323,width-28,height-380)
    ui["pageButton"].Move(14,height-36)
    ui["jobsButton"].Move(220,height-36)
    ui["scriptButton"].Move(436,height-36)
}

DeepBridge_CatalogRefresh(scriptsOnly := false) {
    ui := g_DeepBridge["catalogUi"]
    try {
        reply := scriptsOnly ? DeepBridge_Request("POST","/tools/ahk_script_list",Map())
            : DeepBridge_Request("POST", "/tools/tool_catalog_search", Map("query", ui["query"].Value, "limit", 50))
        if !reply.Get("ok", false)
            throw Error(reply.Get("error", "Could not read saved tools"))
        records := scriptsOnly ? reply["indexed"] : reply["records"]
        ui["records"] := records, ui["list"].Delete()
        inventory := ""
        for , record in records {
            ui["list"].Add(,record["kind"],record["name"],record["description"],record["revision"])
            if scriptsOnly {
                path := g_DeepBridge["root"] . "\agent_scripts\" . record["name"]
                inventory .= record["name"] . " | revision " . record["revision"] . " | " . (FileExist(path) ? "local file" : "stored in database; materializes on validate/run") . "`r`n" . path . "`r`n`r`n"
            }
        }
        ui["details"].Value := (scriptsOnly ? "Written .ahk tools: " : "Indexed tools: ") . records.Length . "`r`nSelect a record to see source, usage and metadata.`r`n`r`n" . inventory
    } catch as catalogError
        ui["details"].Value := catalogError.Message
}

DeepBridge_CatalogSelect(row) {
    ui := g_DeepBridge["catalogUi"]
    if row < 1 || row > ui["records"].Length
        return
    record := ui["records"][row]
    try {
        reply := DeepBridge_Request("POST", "/tools/tool_catalog_get", Map("name", record["name"]))
        ui["details"].Value := StudyConsole_Redact(TrackJsonEncode(reply, 2))
    } catch as catalogError
        ui["details"].Value := catalogError.Message
}

DeepBridge_CatalogCapabilities() {
    ui := g_DeepBridge["catalogUi"]
    try {
        reply := DeepBridge_Request("POST", "/tools/fan_capabilities", Map())
        ui["details"].Value := StudyConsole_Redact(TrackJsonEncode(reply, 2))
    } catch as catalogError
        ui["details"].Value := catalogError.Message
}

DeepBridge_OpenPatch() {
    root := g_DeepBridge["root"], patch := root . "\harness\fan.cordis.patch.yml"
    source := "# Merge this entry into the active DeepSeek Harness profile patch.`n- insert:`n"
        . "    - id: mcp-fan-ahk-windows`n      name: '@deepseek-ai/dsh-mcp-client'`n      config:`n"
        . "        serverName: fan-ahk-windows`n        transport: stdio`n        command: '" . root . "\.venv\Scripts\python.exe'`n"
        . "        args: ['-m', 'bridge.mcp_server']`n        env: {}`n        cwd: '" . root . "'`n"
    if FileExist(patch)
        FileDelete(patch)
    FileAppend(source, patch, "UTF-8")
    Run('notepad.exe "' . patch . '"')
}
