; Persistent, structured audit stream shared by perception, providers and input.
; Never pass COM elements, request headers, image base64 or credentials here.
global g_StudyConsole := Map("seq", 0, "run", "", "path", "", "lines", [], "dirty", false,
    "gui", 0, "ui", Map(), "secrets", [], "failure", "")
global g_StudyChat := Map("history", [], "busy", false, "text", "", "reply", "", "dirty", false,
    "state", "idle", "detail", "Ready — type a message to DeepSeek", "started", 0,
    "pending", "", "lastMessage", "", "gui", 0, "ui", Map())

StudyConsole_Secret(value) {
    for , existing in g_StudyConsole["secrets"]
        if existing = value
            return
    if value != ""
        g_StudyConsole["secrets"].Push(value)
}

StudyConsole_Redact(text) {
    for , secret in g_StudyConsole["secrets"] {
        text := StrReplace(text, TrackJsonEscape(secret), "[CREDENTIAL REDACTED]")
        text := StrReplace(text, secret, "[CREDENTIAL REDACTED]")
    }
    text := RegExReplace(text, "i)sk-[a-z0-9_-]{12,}", "[CREDENTIAL REDACTED]")
    return RegExReplace(text, "i)Bearer\s+[^\s" . Chr(34) . "]+", "Bearer [REDACTED]")
}

StudyConsole_Log(stage, event, data := "", level := "INFO") {
    global g_StudyConsole
    try {
        if g_StudyConsole["path"] = "" {
            StudyConsole_Secret(Trim(EnvGet("DEEPSEEK_API_KEY")))
            root := IsSet(APP_ROOT) ? APP_ROOT : A_ScriptDir . "\.."
            dir := root . "\fan\logs\study"
            DirCreate(dir)
            g_StudyConsole["run"] := FormatTime(A_Now, "yyyyMMdd-HHmmss") . "-" . A_TickCount
            g_StudyConsole["path"] := dir . "\" . g_StudyConsole["run"] . ".jsonl"
        }
        g_StudyConsole["seq"]++
        record := Map("seq", g_StudyConsole["seq"], "run", g_StudyConsole["run"],
            "time", FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") . "." . Format("{:03}", A_MSec),
            "tick", A_TickCount, "stage", stage, "event", event, "level", level, "data", data)
        encoded := StudyConsole_Redact(TrackJsonEncode(record))
        FanFileAppend(encoded . "`n", g_StudyConsole["path"], "UTF-8-RAW")
        summary := Format("{:05}", record["seq"]) . " " . record["time"] . " [" . stage . "] "
            . event . " " . StudyConsole_Redact(IsObject(data) ? TrackJsonEncode(data) : String(data))
        g_StudyConsole["lines"].Push(Map("stage", stage, "text", summary))
        while g_StudyConsole["lines"].Length > 1500
            g_StudyConsole["lines"].RemoveAt(1)
        g_StudyConsole["dirty"] := true
        if (event = "deduction.choice" || event = "deduction.open") && data is Map {
            answer := data.Get("answer", "")
            if answer != ""
                LearningLab_Record("Study deductions", TrackHash(answer), "Proposed local answer: " . SubStr(answer,1,180), "observed", Map("scope","local retrieval"),
                    "Candidate only. " . data.Get("evidence", "No source evidence attached."), "study console:" . record["run"] . ":" . record["seq"], "Inspect the source passages in Study Assistant, then confirm or dispute the answer. Repetition alone does not validate it.")
        }
        LearningValidation_Event("Study " . stage, level = "ERROR" ? "error" : "observed", event)
        return true
    } catch as err {
        g_StudyConsole["failure"] := "Logging failed: " . err.Message
        return false
    }
}

StudyConsole_Open() {
    if IsObject(g_StudyConsole["gui"]) {
        g_StudyConsole["gui"].Show("NoActivate")
        return
    }
    StudyConsole_Log("CONSOLE", "opened", "All events are retained in JSONL; view shows the latest 1,500 events.")
    g := Gui("+Resize +MinSize850x520", "Study Live Console - Identification / DeepSeek / Math / Input")
    g.SetFont("s10", "Consolas")
    g.OnEvent("Close", (*) => g.Hide())
    g_StudyConsole["gui"] := g
    ui := g_StudyConsole["ui"]
    ui["filter"] := g.Add("DropDownList", "x12 y12 w170", ["ALL", "CHAT", "CAPTURE", "IDENTIFY", "LOOKUP", "LLM", "MATH", "PLAN", "ACTION", "INPUT", "VERIFY", "NAV", "ERROR"])
    ui["filter"].Choose(1)
    ui["filter"].OnEvent("Change", (*) => g_StudyConsole["dirty"] := true)
    ui["follow"] := g.Add("Checkbox", "x200 y14 w160 Checked", "Follow live output")
    g.Add("Button", "x365 y10 w125", "Open log folder").OnEvent("Click", (*) => StudyConsole_Folder())
    g.Add("Button", "x500 y10 w125", "ABORT ALL").OnEvent("Click", (*) => StudyLive_Abort())
    g.Add("Button", "x640 y10 w170", "Explain learning").OnEvent("Click", LearningLab_Open)
    ui["log"] := g.Add("Edit", "x12 y50 w1025 h545 ReadOnly Multi -Wrap", "")
    ui["status"] := g.Add("Text", "x12 y607 w1025 h48", "")
    ui["chatlabel"] := g.Add("Text", "x12 y350 w1025", "DeepSeek chat — replies stream below; Ctrl+Enter sends")
    ui["chatoutput"] := g.Add("Edit", "x12 y375 w1025 h150 ReadOnly Multi -Wrap", g_StudyChat["text"])
    ui["chatinput"] := g.Add("Edit", "x12 y545 w770 h65 Multi WantReturn", "")
    ui["chatsend"] := g.Add("Button", "x800 y545 w110 h28", "Send to DeepSeek")
    ui["chatsend"].OnEvent("Click", (*) => StudyChat_Send(ui["chatinput"]))
    ui["chatcancel"] := g.Add("Button", "x920 y545 w100 h28", "Cancel reply")
    ui["chatcancel"].OnEvent("Click", (*) => StudyChat_Cancel())
    ui["chatclear"] := g.Add("Button", "x800 y580 w110 h28", "New chat")
    ui["chatclear"].OnEvent("Click", (*) => StudyChat_Clear())
    HotIf((*) => WinActive("ahk_id " . g.Hwnd) && ControlGetFocus(g) = ui["chatinput"].ClassNN)
    Hotkey("^Enter", (*) => StudyChat_Send(ui["chatinput"]))
    HotIf()
    g.OnEvent("Size", StudyConsole_Resize)
    StudyConsole_ShowOnSide(g, "right", 1050, 670)
    WinGetClientPos(,, &width, &height, g)
    StudyConsole_Resize(g, 0, width, height)
    SetTimer(StudyConsole_Flush, 200)
    StudyConsole_Flush()
}

StudyConsole_ShowOnSide(gui, side, width, height) {
    monitor := LearningValidation_Monitor()
    if !monitor
        return gui.Hide()
    dpiContext := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try {
        MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
        SecondaryWindows_Place(gui, "NoActivate x" . left+15 . " y" . top+30 . " w" . Min(width,right-left-30) . " h" . Min(height,bottom-top-60))
        WinGetPos(&x,&y,&w,&h,"ahk_id " . gui.Hwnd)
        StudyConsole_Log("CONSOLE", "window.placed", Map("side", side, "monitor", monitor, "bounds", [x,y,w,h]))
    } finally
        DllCall("SetThreadDpiAwarenessContext", "Ptr", dpiContext, "Ptr")
}

StudyConsole_Resize(g, state, w, h) {
    if state = -1
        return
    ui := g_StudyConsole["ui"]
    chatTop := Max(185, h - 320)
    ui["log"].Move(12, 50, w-24, chatTop-60)
    ui["chatlabel"].Move(12, chatTop, w-24, 24)
    ui["chatoutput"].Move(12, chatTop+26, w-24, h-chatTop-160)
    ui["chatinput"].Move(12, h-125, w-265, 65)
    ui["chatsend"].Move(w-240, h-125, 115, 28)
    ui["chatcancel"].Move(w-115, h-125, 100, 28)
    ui["chatclear"].Move(w-240, h-90, 115, 28)
    ui["status"].Move(12, h-52, w-24, 44)
}

StudyConsole_Flush() {
    StudyChat_Flush()
    if !g_StudyConsole["dirty"] || !IsObject(g_StudyConsole["gui"])
        return
    ui := g_StudyConsole["ui"]
    if !ui["follow"].Value
        return
    output := "", filter := ui["filter"].Text
    for , line in g_StudyConsole["lines"]
        if filter = "ALL" || line["stage"] = filter
            output .= line["text"] . "`r`n"
    ui["log"].Value := output
    PostMessage(0x115, 7, 0, ui["log"].Hwnd)
    ui["status"].Value := g_StudyConsole["seq"] . " recorded events | " . g_StudyConsole["path"]
        . "`n" . g_StudyConsole["failure"]
    g_StudyConsole["dirty"] := false
}

StudyChat_Send(input) {
    global g_StudyChat
    message := Trim(input.Value)
    if message = ""
        return false
    StudyChat_Open()
    if g_StudyChat["busy"] {
        StudyChat_State(g_StudyChat["state"], "A message is already queued or streaming. Cancel it or wait; your draft is preserved.")
        return false
    }
    if !StudyLLM_HasKey() {
        StudyChat_State("error", "No API key. Click Save API Key above, then send your message again.")
        g_StudyChat["ui"]["input"].Value := message
        return false
    }
    g_StudyChat["busy"] := true
    g_StudyChat["reply"] := ""
    g_StudyChat["text"] .= (g_StudyChat["text"] != "" ? "`r`n`r`n" : "") . "You: " . message . "`r`nDeepSeek: "
    g_StudyChat["dirty"] := true
    g_StudyChat["started"] := A_TickCount
    g_StudyChat["pending"] := message
    g_StudyChat["lastMessage"] := message
    input.Value := ""
    StudyConsole_Log("CHAT", "message.sent", Map("message", message))
    StudyChat_State("queued", "Message queued — waiting for the current study operation to finish")
    SetTimer(StudyChat_Dispatch, 100)
    return true
}

StudyChat_Dispatch() {
    if !g_StudyChat["busy"] || g_StudyChat["pending"] = "" {
        SetTimer(StudyChat_Dispatch, 0)
        return
    }
    if g_StudyLLM_Busy || g_StudySessBusy || g_StudyToolBusy || g_StudyMacroRunning
        return
    message := g_StudyChat["pending"]
    g_StudyChat["pending"] := ""
    SetTimer(StudyChat_Dispatch, 0)
    StudyChat_Request(message)
}

StudyChat_Request(message) {
    global g_StudyChat
    try {
        StudyChat_State("connecting", "Connecting to DeepSeek — waiting for the first reply token")
        result := StudyLLM_Ask(message, Map("history", g_StudyChat["history"].Clone(), "stream", true,
            "onDelta", StudyChat_Delta, "onProgress", StudyChat_Progress, "maxTokens", 4096, "purpose", "manual chat",
            "system", "You are a helpful conversational assistant. Respond to the user's message and use the previous conversation when relevant."))
        if result["ok"] {
            g_StudyChat["history"].Push(Map("role", "user", "content", message))
            g_StudyChat["history"].Push(Map("role", "assistant", "content", result["answer"]))
            while g_StudyChat["history"].Length > 20
                g_StudyChat["history"].RemoveAt(1, 2)
            StudyConsole_Log("CHAT", "reply.complete", Map("answer", result["answer"], "model", result["model"], "cost_usd", result["costUSD"]))
            Study_SetSetting("chat_history", StudyConsole_Redact(TrackJsonEncode(g_StudyChat["history"])))
            StudyChat_State("complete", "Complete · " . result["model"] . " · " . result["completionTokens"] . " tokens · $" . Round(result["costUSD"], 5))
        } else {
            g_StudyChat["text"] .= "`r`n[" . result["error"] . "]"
            StudyConsole_Log("CHAT", "reply.failed", result["error"], "ERROR")
            StudyChat_State(InStr(result["error"], "Cancelled") ? "cancelled" : "error", result["error"])
            if g_StudyChat["ui"].Has("input") && g_StudyChat["ui"]["input"].Value = ""
                g_StudyChat["ui"]["input"].Value := message
        }
    } catch as err {
        g_StudyChat["text"] .= "`r`n[Chat failed: " . StudyConsole_Redact(err.Message) . "]"
        StudyConsole_Log("CHAT", "reply.failed", err.Message, "ERROR")
        StudyChat_State("error", err.Message)
    } finally {
        g_StudyChat["busy"] := false
        g_StudyChat["dirty"] := true
        StudyChat_Flush()
    }
}

StudyChat_Delta(kind, text) {
    if kind != "answer"
        return
    g_StudyChat["reply"] .= text
    g_StudyChat["text"] .= text
    g_StudyChat["dirty"] := true
    g_StudyChat["state"] := "streaming"
    g_StudyChat["detail"] := "Receiving DeepSeek reply · " . StrLen(g_StudyChat["reply"]) . " characters"
    StudyConsole_Log("CHAT", "reply.delta", Map("text", text))
}

StudyChat_Flush() {
    if !g_StudyChat["dirty"]
        return
    surfaces := [g_StudyChat["ui"], g_StudyConsole["ui"]]
    if IsSet(g_StudyUi)
        surfaces.Push(g_StudyUi)
    for , surface in surfaces {
        if surface.Has("chatoutput") {
            output := surface["chatoutput"]
            output.Value := StudyConsole_Redact(g_StudyChat["text"])
            PostMessage(0x115, 7, 0, output.Hwnd)
        }
        if surface.Has("chatstatus")
            surface["chatstatus"].Value := StudyChat_StatusText()
        for key in ["chatsend", "chatclear"]
            if surface.Has(key)
                surface[key].Enabled := !g_StudyChat["busy"]
        if surface.Has("chatcancel")
            surface["chatcancel"].Enabled := g_StudyChat["busy"]
    }
    g_StudyChat["dirty"] := false
}

StudyChat_State(state, detail) {
    g_StudyChat["state"] := state
    g_StudyChat["detail"] := StudyConsole_Redact(detail)
    g_StudyChat["dirty"] := true
    StudyConsole_Log("CHAT", "state." . state, detail, state = "error" ? "ERROR" : "INFO")
    StudyChat_Flush()
}

StudyChat_Progress(detail) {
    StudyChat_State("connecting", detail)
}

StudyChat_StatusText() {
    seconds := g_StudyChat["busy"] ? " · " . Floor((A_TickCount - g_StudyChat["started"]) / 1000) . "s" : ""
    return StrUpper(g_StudyChat["state"]) . " · " . g_StudyChat["detail"] . seconds
}

StudyChat_Heartbeat() {
    if g_StudyChat["busy"]
        g_StudyChat["dirty"] := true
    StudyChat_Flush()
}

StudyChat_Cancel() {
    if !g_StudyChat["busy"]
        return
    if g_StudyChat["pending"] != "" {
        g_StudyChat["pending"] := ""
        SetTimer(StudyChat_Dispatch, 0)
        g_StudyChat["busy"] := false
        g_StudyChat["text"] .= "`r`n[Cancelled before sending]"
        StudyChat_State("cancelled", "Queued message cancelled. No request was sent.")
    } else {
        StudyLLM_CancelRequest()
        StudyChat_State("cancelling", "Stopping the streamed reply")
    }
}

StudyChat_Open(activate := true) {
    if !IsObject(g_StudyChat["gui"]) {
        g := Gui("+Resize +MinSize720x560", "DeepSeek Chat — Live Portal")
        g.SetFont("s10", "Segoe UI")
        g.OnEvent("Close", (*) => g.Hide())
        g_StudyChat["gui"] := g
        ui := g_StudyChat["ui"]
        ui["heading"] := g.Add("Text", "x14 y12 w860 h30", "DeepSeek Chat")
        ui["heading"].SetFont("s16 bold")
        ui["connection"] := g.Add("Text", "x14 y46 w860 h24", "Model: " . g_StudyLLM_TextModel . " · " . (StudyLLM_HasKey() ? "API key configured" : "API key needed"))
        g.Add("Button", "x14 y78 w115 h28", "Save API Key").OnEvent("Click", (*) => (StudyLive_SaveKey(), StudyChat_RefreshKey()))
        g.Add("Button", "x139 y78 w115 h28", "Test Connection").OnEvent("Click", (*) => StudyChat_Probe())
        g.Add("Button", "x264 y78 w135 h28", "Open local harness").OnEvent("Click", (*) => Run("http://127.0.0.1:3080/"))
        g.Add("Button", "x409 y78 w110 h28", "Activity Console").OnEvent("Click", (*) => StudyConsole_Open())
        ui["chatclear"] := g.Add("Button", "x529 y78 w100 h28", "New chat")
        ui["chatclear"].OnEvent("Click", (*) => StudyChat_Clear())
        ui["chatoutput"] := g.Add("Edit", "x14 y118 w872 h390 ReadOnly Multi", g_StudyChat["text"])
        ui["chatstatus"] := g.Add("Text", "x14 y520 w872 h42", StudyChat_StatusText())
        ui["input"] := g.Add("Edit", "x14 y572 w722 h92 Multi WantReturn", "")
        ui["chatsend"] := g.Add("Button", "x748 y572 w138 h34 Default", "Send message")
        ui["chatsend"].OnEvent("Click", (*) => StudyChat_Send(ui["input"]))
        ui["chatcancel"] := g.Add("Button", "x748 y614 w138 h34", "Stop reply")
        ui["chatcancel"].OnEvent("Click", (*) => StudyChat_Cancel())
        ui["hint"] := g.Add("Text", "x14 y676 w860 h24", "Ctrl+Enter sends · Enter adds a line · Conversation history is kept across restarts")
        g.OnEvent("Size", StudyChat_Resize)
        HotIf((*) => WinActive("ahk_id " . g.Hwnd) && ControlGetFocus(g) = ui["input"].ClassNN)
        Hotkey("^Enter", (*) => StudyChat_Send(ui["input"]))
        HotIf()
        StudyConsole_ShowOnSide(g, "right", 910, 725)
        SetTimer(StudyChat_Heartbeat, 150)
    }
    g := g_StudyChat["gui"]
    g.Show(activate ? "" : "NoActivate")
    if activate {
        WinActivate(g)
        g_StudyChat["ui"]["input"].Focus()
    }
    g_StudyChat["dirty"] := true
    StudyChat_Flush()
}

StudyChat_Resize(g, state, width, height) {
    if state = -1
        return
    ui := g_StudyChat["ui"]
    ui["chatoutput"].Move(14, 118, width-28, height-312)
    ui["chatstatus"].Move(14, height-184, width-28, 42)
    ui["input"].Move(14, height-132, width-180, 92)
    ui["chatsend"].Move(width-152, height-132, 138, 34)
    ui["chatcancel"].Move(width-152, height-90, 138, 34)
    ui["hint"].Move(14, height-30, width-28, 24)
}

StudyChat_RefreshKey() {
    if g_StudyChat["ui"].Has("connection")
        g_StudyChat["ui"]["connection"].Value := "Model: " . g_StudyLLM_TextModel . " · " . (StudyLLM_HasKey() ? "API key configured" : "API key needed")
}

StudyChat_Probe() {
    if g_StudyChat["busy"]
        return
    StudyChat_State("connecting", "Checking API connection")
    result := StudyLLM_Probe()
    StudyChat_State(result["ok"] ? "idle" : "error", result["detail"])
}

StudyChat_Restore() {
    try {
        history := TrackJsonDecode(Study_GetSetting("chat_history", "[]"))
        if !(history is Array)
            return
        g_StudyChat["history"] := []
        g_StudyChat["text"] := ""
        for , message in history {
            if !IsObject(message) || !message.Has("content") || !message.Has("role") || !RegExMatch(message["role"], "^(user|assistant)$")
                continue
            g_StudyChat["history"].Push(message)
            g_StudyChat["text"] .= (g_StudyChat["text"] != "" ? "`r`n`r`n" : "") . (message["role"] = "user" ? "You: " : "DeepSeek: ") . message["content"]
        }
        g_StudyChat["dirty"] := true
    }
}

StudyChat_Clear() {
    if g_StudyChat["busy"]
        return
    g_StudyChat["history"] := []
    g_StudyChat["text"] := ""
    g_StudyChat["dirty"] := true
    Study_SetSetting("chat_history", "[]")
    StudyChat_State("idle", "New conversation — ready for your message")
    StudyConsole_Log("CHAT", "conversation.cleared")
    StudyChat_Flush()
}

StudyConsole_Folder() {
    SplitPath(g_StudyConsole["path"], , &dir)
    if dir != ""
        Run(dir)
}

StudyFeatures_Describe(c, id, url := "") {
    commands := Map("edit", "TYPE", "checkbox", "SET 0/1", "radio", "SET 1", "dropdown", "CHOOSE",
        "button", "CLICK / NAVIGATE when recognized", "link", "NAVIGATE question link", "list", "inspect")
    purpose := Map("edit", "enter a literal answer; replace and verify its value", "checkbox", "select or clear an independent choice",
        "radio", "select one mutually exclusive choice", "dropdown", "choose a named option and verify it", "button", "activate the named page operation",
        "link", "navigate to the named question/page", "list", "inspect the question navigation list")
    feature := Map("id", id, "name", c["name"], "kind", c["kind"], "function", purpose.Get(c["kind"], "review required"),
        "supported", commands.Get(c["kind"], "none"), "description", c["name"] . ": " . purpose.Get(c["kind"], "unknown"),
        "identity", c["kind"] . "|" . c["name"], "source", "Acc accessibility role/name; function inferred from role",
        "value", c["value"], "checked", c["checked"], "bounds", [c["x"], c["y"], c["w"], c["h"]])
    if url != "" {
        saved := Study_GetSetting("feature:" . url . "|" . feature["identity"], "")
        if saved != "" {
            try feature["remembered_description"] := TrackJsonDecode(saved)
        }
    }
    return feature
}

StudyFeatures_Remember(ctx, id, description, model) {
    feature := ctx["features"][id]
    feature["model_description"] := description
    metadata := Map("description", description, "model", model, "time", FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"),
        "status", "model inference; role/name revalidated for every action")
    Study_SetSetting("feature:" . ctx["url"] . "|" . feature["identity"], TrackJsonEncode(metadata))
    StudyConsole_Log("IDENTIFY", "description.saved", Map("url", ctx["url"], "identity", feature["identity"], "metadata", metadata))
}
