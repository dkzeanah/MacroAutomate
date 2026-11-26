; ═══════════════════════════════════════════════════════════════════════════════
; AutopilotRecorder.ahk - record once -> SOP, training video, workflow (page 32)
; ═══════════════════════════════════════════════════════════════════════════════
; Ctrl+Alt+F9 (or the Record button) starts and stops a recording. While on, Fan
; captures physical clicks (window screenshot, click point, the visible label
; next to the pointer), window switches, typing bursts and shortcut keys.
; Typing in windows that look like sign-in/password prompts is masked and never
; stored. The Python builder (fan\autopilot\sop.py) turns the recording into an
; SOP (HTML/Markdown/Word), a narrated video and a workflow whose self-heal
; targets are already learned from the recording.
; ═══════════════════════════════════════════════════════════════════════════════

global g_Rec := Map("on", false, "events", [], "dir", "", "ih", 0, "lastHwnd", 0, "typing", "", "typeWin", Map(),
    "typeTick", 0, "masked", false, "down", Map("LButton", false, "RButton", false), "banner", 0, "started", "",
    "shots", 0, "lastSession", "", "lastBuild", 0, "ui", Map(), "pollTick", 0)

; Ctrl+Alt+F9 is registered by Autopilot_Start (the main app only), so headless
; workers that load these modules never claim the hotkey.
Recorder_Toggle(*) {
    global g_Rec
    if g_Rec["on"]
        Recorder_Stop()
    else
        Recorder_Start()
}

Recorder_SelfWindow(hwnd) {
    try return WinGetPID("ahk_id " . hwnd) = DllCall("GetCurrentProcessId", "UInt")
    return true
}

Recorder_Start() {
    global g_Rec, g_WorkflowRunning
    if g_WorkflowRunning
        return MsgBoxTop("Wait for the running workflow to finish before recording.", "Record a procedure", "Iconi")
    dir := Autopilot_DataDir() . "\recordings\" . FormatTime(A_Now, "yyyyMMdd_HHmmss")
    DirCreate(dir)
    g_Rec["dir"] := dir, g_Rec["events"] := [], g_Rec["typing"] := "", g_Rec["shots"] := 0, g_Rec["lastHwnd"] := 0
    g_Rec["started"] := Autopilot_Now(), g_Rec["down"] := Map("LButton", false, "RButton", false)
    ih := InputHook("V I1")
    ih.KeyOpt("{All}", "N")
    ih.OnChar := Recorder_OnChar
    ih.OnKeyDown := Recorder_OnKeyDown
    ih.Start()
    g_Rec["ih"] := ih
    g_Rec["on"] := true
    SetTimer(Recorder_Poll, 30)
    Recorder_Banner()
    Recorder_UiState()
    ; Begin with whatever (non-Fan) window the person is about to use.
    SetTimer(() => Recorder_CheckWindow(), -400)
}

Recorder_Stop() {
    global g_Rec
    if !g_Rec["on"]
        return
    Recorder_FlushTyping()
    g_Rec["on"] := false
    SetTimer(Recorder_Poll, 0)
    try g_Rec["ih"].Stop()
    g_Rec["ih"] := 0
    try g_Rec["banner"].Destroy()
    g_Rec["banner"] := 0
    title := ""
    try title := Trim(g_Rec["ui"]["title"].Value)
    session := Map("title", title != "" ? title : "Recorded procedure", "started", g_Rec["started"], "ended", Autopilot_Now(),
        "user", A_UserName, "events", g_Rec["events"])
    path := g_Rec["dir"] . "\session.json"
    file := FileOpen(path, "w", "UTF-8-RAW")
    file.Write(TrackJsonEncode(session))
    file.Close()
    g_Rec["lastSession"] := path
    Recorder_UiState()
    Recorder_ShowEvents()
    try MainGui.Show()
    FanNav_Open(32)
    Recorder_Status(g_Rec["events"].Length . " steps recorded. Review them, then Build SOP.")
}

Recorder_Banner() {
    global g_Rec
    banner := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000020", "Fan recording")
    banner.BackColor := "0xB3261E"
    banner.SetFont("s10 cWhite bold", "Segoe UI")
    g_Rec["bannerText"] := banner.Add("Text", "x12 y6 w300", "● Recording · Ctrl+Alt+F9 to stop · 0 steps")
    banner.Show("NoActivate Hide")
    MonitorGetWorkArea(MonitorGetPrimary(), , , &right, &bottom)
    banner.Show("NoActivate x" . (right - 340) . " y" . (bottom - 46) . " w324 h30")
    WinSetTransparent(220, "ahk_id " . banner.Hwnd)
    g_Rec["banner"] := banner
}

Recorder_UpdateBanner() {
    global g_Rec
    try g_Rec["bannerText"].Value := "● Recording · Ctrl+Alt+F9 to stop · " . g_Rec["events"].Length . " steps"
}

Recorder_Poll() {
    global g_Rec
    if !g_Rec["on"]
        return
    for key, button in Map("LButton", "Left", "RButton", "Right") {
        down := GetKeyState(key, "P")
        if down && !g_Rec["down"][key]
            Recorder_Click(button)
        g_Rec["down"][key] := down
    }
    if A_TickCount - g_Rec["pollTick"] > 200 {
        g_Rec["pollTick"] := A_TickCount
        Recorder_CheckWindow()
        if g_Rec["typing"] != "" && A_TickCount - g_Rec["typeTick"] > 1200
            Recorder_FlushTyping()
    }
}

Recorder_WindowInfo(hwnd) {
    info := Map("hwnd", hwnd, "exe", "", "title", "", "class", "")
    try info["exe"] := WinGetProcessName("ahk_id " . hwnd)
    try info["title"] := SubStr(WinGetTitle("ahk_id " . hwnd), 1, 200)
    try info["class"] := WinGetClass("ahk_id " . hwnd)
    return info
}

Recorder_Sensitive(title) => RegExMatch(title, "i)(password|passcode|passphrase|sign[ -]?in|log ?in|credential|verification|security code|bitwarden|lastpass|keepass|1password)") != 0

Recorder_CheckWindow() {
    global g_Rec
    hwnd := WinExist("A")
    if !hwnd || hwnd = g_Rec["lastHwnd"] || Recorder_SelfWindow(hwnd)
        return
    info := Recorder_WindowInfo(hwnd)
    if info["title"] = "" || info["class"] = "Shell_TrayWnd" || info["exe"] = "ShellExperienceHost.exe"
        return
    Recorder_FlushTyping()
    g_Rec["lastHwnd"] := hwnd
    event := Map("kind", "app", "t", A_TickCount, "exe", info["exe"], "title", info["title"], "class", info["class"])
    shot := Recorder_Shot(hwnd, "", "")
    if shot.Count
        event["shot"] := shot["file"]
    g_Rec["events"].Push(event)
    Recorder_UpdateBanner()
}

; Window screenshot; with a click point, also a crop around it for label OCR.
Recorder_Shot(hwnd, x, y) {
    global g_Rec
    region := SelfHeal_WindowRegion(hwnd)
    if !region
        return Map()
    g_Rec["shots"] += 1
    file := Format("{:03}.png", g_Rec["shots"])
    if !Autopilot_CaptureRegion(region, g_Rec["dir"] . "\" . file)
        return Map()
    out := Map("file", file, "region", region)
    if x != "" {
        crop := Map("x1", Max(region["x1"], x - 170), "y1", Max(region["y1"], y - 45), "x2", Min(region["x2"], x + 170), "y2", Min(region["y2"], y + 45))
        cropFile := A_Temp . "\fan-rec-" . A_TickCount . ".png"
        if Autopilot_CaptureRegion(crop, cropFile)
            out["crop"] := Map("file", cropFile, "x1", crop["x1"], "y1", crop["y1"])
    }
    return out
}

; The text nearest the click, read from the crop saved at click time.
Recorder_Label(crop, x, y) {
    result := Map("label", "", "dx", 0, "dy", 0)
    if !IsObject(crop) || !IsOCRAvailable()
        return result
    try {
        ocr := OCR.FromFile(crop["file"], WorkflowOCR_Options())
        best := 0, bestDistance := 99999
        for , group in [ocr.Lines, ocr.Words] {
            for , item in group {
                text := Trim(item.Text)
                if StrLen(text) < 2 || StrLen(text) > 48 || !RegExMatch(text, "[A-Za-z]{2,}")
                    continue
                center := WorkflowOCR_Center(item)
                cx := crop["x1"] + center["x"], cy := crop["y1"] + center["y"]
                distance := Sqrt((cx - x) ** 2 + (cy - y) ** 2) + (group = ocr.Words ? 4 : 0)
                if distance < bestDistance
                    best := Map("text", text, "x", cx, "y", cy), bestDistance := distance
            }
        }
        if IsObject(best) && bestDistance <= 150
            result := Map("label", best["text"], "dx", x - best["x"], "dy", y - best["y"])
    }
    try FileDelete(crop["file"])
    return result
}

Recorder_Click(button) {
    global g_Rec
    MouseGetPos(&x, &y)
    hwnd := SelfHeal_RootWindowAt(x, y)
    if !hwnd || Recorder_SelfWindow(hwnd)
        return
    Recorder_FlushTyping()
    events := g_Rec["events"]
    if events.Length {
        last := events[events.Length]
        if last["kind"] = "click" && last["button"] = button && A_TickCount - last["t"] <= DllCall("GetDoubleClickTime")
            && Abs(last["x"] - x) <= 6 && Abs(last["y"] - y) <= 6 {
            last["double"] := 1
            return
        }
    }
    info := Recorder_WindowInfo(hwnd)
    if hwnd != g_Rec["lastHwnd"] {
        g_Rec["lastHwnd"] := hwnd
        events.Push(Map("kind", "app", "t", A_TickCount, "exe", info["exe"], "title", info["title"], "class", info["class"]))
    }
    sample := SelfHeal_SampleHex(x, y)
    shot := Recorder_Shot(hwnd, x, y)
    region := shot.Count ? shot["region"] : SelfHeal_WindowRegion(hwnd)
    if !region
        return
    label := Recorder_Label(shot.Get("crop", 0), x, y)
    event := Map("kind", "click", "t", A_TickCount, "button", button, "x", x, "y", y, "exe", info["exe"], "title", info["title"],
        "class", info["class"], "rel_x", Round((x - region["x1"]) / region["w"], 4), "rel_y", Round((y - region["y1"]) / region["h"], 4),
        "win_w", region["w"], "win_h", region["h"], "label", label["label"], "label_dx", label["dx"], "label_dy", label["dy"],
        "sample", sample, "double", 0)
    if shot.Count
        event["shot"] := shot["file"], event["shot_x"] := x - region["x1"], event["shot_y"] := y - region["y1"]
    events.Push(event)
    Recorder_UpdateBanner()
}

Recorder_OnChar(ih, char) {
    global g_Rec
    if !g_Rec["on"] || GetKeyState("Control", "P") || GetKeyState("Alt", "P") || GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
        return
    hwnd := WinExist("A")
    if !hwnd || Recorder_SelfWindow(hwnd)
        return
    if g_Rec["typing"] = "" {
        g_Rec["typeWin"] := Recorder_WindowInfo(hwnd)
        g_Rec["masked"] := Recorder_Sensitive(g_Rec["typeWin"]["title"])
    }
    g_Rec["typing"] .= char
    g_Rec["typeTick"] := A_TickCount
}

Recorder_OnKeyDown(ih, vk, sc) {
    global g_Rec
    if !g_Rec["on"]
        return
    key := ""
    try key := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
    if key = "" || RegExMatch(key, "i)^(L|R)?(Control|Shift|Alt|Win)$") || key = "F9" && GetKeyState("Control", "P") && GetKeyState("Alt", "P")
        return
    hwnd := WinExist("A")
    if !hwnd || Recorder_SelfWindow(hwnd)
        return
    ctrl := GetKeyState("Control", "P"), alt := GetKeyState("Alt", "P"), shift := GetKeyState("Shift", "P")
    win := GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
    if !(ctrl || alt || win) {
        if key = "Backspace" {
            if g_Rec["typing"] != ""
                g_Rec["typing"] := SubStr(g_Rec["typing"], 1, -1)
            return
        }
        if StrLen(key) = 1 || key = "Space"
            return  ; part of typing (OnChar)
    }
    Recorder_FlushTyping()
    send := (ctrl ? "^" : "") . (alt ? "!" : "") . (shift && (ctrl || alt || win) ? "+" : "") . (win ? "#" : "")
    send .= StrLen(key) = 1 ? StrLower(key) : "{" . key . "}"
    info := Recorder_WindowInfo(hwnd)
    g_Rec["events"].Push(Map("kind", "key", "t", A_TickCount, "send", send, "exe", info["exe"], "title", info["title"]))
    Recorder_UpdateBanner()
}

Recorder_FlushTyping() {
    global g_Rec
    text := g_Rec["typing"]
    g_Rec["typing"] := ""
    if text = ""
        return
    win := g_Rec["typeWin"]
    event := Map("kind", "type", "t", g_Rec["typeTick"], "exe", win.Get("exe", ""), "title", win.Get("title", ""),
        "masked", g_Rec["masked"] ? 1 : 0, "length", StrLen(text))
    if !g_Rec["masked"]
        event["text"] := text
    else
        StudyConsole_Secret(text)
    text := ""
    g_Rec["events"].Push(event)
    Recorder_UpdateBanner()
}

; ─── page 32 · Record & SOP ───────────────────────────────────────────────────

Recorder_BuildPage() {
    global MainGui, TabCtrl, g_Rec
    ui := g_Rec["ui"]
    AutopilotUI_Title(32, "Record once — get an SOP, a training video and a workflow",
        "Press Record (or Ctrl+Alt+F9), do the task once the normal way, then stop. Fan writes the step-by-step procedure with screenshots, "
        . "a narrated training video, and a workflow that can repeat it. Typing in sign-in windows is masked and never saved.")
    MainGui.Add("Text", "x16 y130 w40", "Title:")
    ui["title"] := MainGui.Add("Edit", "x58 y126 w340 h24", "")
    SendMessage(0x1501, 1, StrPtr("e.g. Enter a new patient in the scheduler"), ui["title"])
    ui["record"] := MainGui.Add("Button", "x408 y124 w150 h28", "● Start recording")
    ui["narrate"] := MainGui.Add("CheckBox", "x572 y124 w150 Checked", "Narrate (Windows voice)")
    ui["video"] := MainGui.Add("CheckBox", "x728 y124 w148 Checked", "Make a video")
    ui["polish"] := MainGui.Add("CheckBox", "x572 y146 w304", "Polish wording with AI (sends step text only)")
    ui["saveWorkflow"] := MainGui.Add("CheckBox", "x408 y158 w160 Checked", "Save as a workflow")
    ui["events"] := MainGui.Add("ListView", "x16 y184 w860 h244 Grid -Multi", ["#", "What happened", "Window", "Screenshot"])
    for col, width in [36, 470, 260, 80]
        ui["events"].ModifyCol(col, width)
    ui["build"] := MainGui.Add("Button", "x16 y434 w130 h28", "Build SOP")
    ui["fromRun"] := MainGui.Add("Button", "x152 y434 w190 h28", "SOP from last audited run")
    ui["removeEvent"] := MainGui.Add("Button", "x348 y434 w110 h28", "Remove step")
    ui["openSop"] := MainGui.Add("Button", "x464 y434 w100 h28", "Open SOP")
    ui["openDocx"] := MainGui.Add("Button", "x570 y434 w100 h28", "Open Word")
    ui["openVideo"] := MainGui.Add("Button", "x676 y434 w100 h28", "Play video")
    ui["openFolder"] := MainGui.Add("Button", "x782 y434 w94 h28", "Folder")
    ui["status"] := MainGui.Add("Text", "x16 y468 w860 h34 cGray", "Nothing recorded yet.")
    MainGui.Add("Text", "x16 y506 w300", "Procedures built so far (double-click to open)")
    ui["built"] := MainGui.Add("ListView", "x16 y526 w860 h166 Grid -Multi", ["Recorded", "Title", "Steps", "Video", "Workflow"])
    for col, width in [130, 360, 50, 80, 230]
        ui["built"].ModifyCol(col, width)
    MainGui.Add("Text", "x16 y698 w860 h28 cGray",
        "The workflow clicks window-relative positions and already knows each button's label, so self-heal can re-find a button that moved. Simulate it before running.")
    ui["record"].OnEvent("Click", Recorder_Toggle)
    ui["build"].OnEvent("Click", (*) => Recorder_Build("session"))
    ui["fromRun"].OnEvent("Click", (*) => Recorder_Build("run"))
    ui["removeEvent"].OnEvent("Click", Recorder_RemoveEvent)
    ui["openSop"].OnEvent("Click", (*) => Recorder_OpenOutput("html"))
    ui["openDocx"].OnEvent("Click", (*) => Recorder_OpenOutput("docx"))
    ui["openVideo"].OnEvent("Click", (*) => Recorder_OpenOutput("video"))
    ui["openFolder"].OnEvent("Click", (*) => Recorder_OpenOutput("folder"))
    ui["built"].OnEvent("DoubleClick", Recorder_OpenBuilt)
    TabCtrl.UseTab(0)
}

Recorder_Status(text) {
    global g_Rec
    if g_Rec["ui"].Has("status")
        try g_Rec["ui"]["status"].Value := text
}

Recorder_UiState() {
    global g_Rec
    if g_Rec["ui"].Has("record")
        g_Rec["ui"]["record"].Text := g_Rec["on"] ? "■ Stop recording" : "● Start recording"
}

Recorder_EventText(event) {
    switch event["kind"] {
        case "app": return "Switched to " . event["exe"]
        case "click": return (event.Get("double", 0) ? "Double-click" : event["button"] = "Right" ? "Right-click" : "Click")
            . (event["label"] != "" ? " “" . event["label"] . "”" : " at " . Round(event["rel_x"] * 100) . "%, " . Round(event["rel_y"] * 100) . "% of the window")
        case "type": return event.Get("masked", 0) ? "Typed " . event["length"] . " characters (masked)" : "Typed “" . SubStr(event.Get("text", ""), 1, 60) . "”"
        case "key": return "Pressed " . event["send"]
    }
    return event["kind"]
}

Recorder_ShowEvents() {
    global g_Rec
    lv := g_Rec["ui"]["events"]
    lv.Opt("-Redraw"), lv.Delete()
    for index, event in g_Rec["events"]
        lv.Add("", index, Recorder_EventText(event), SubStr(event.Get("title", ""), 1, 60), event.Get("shot", ""))
    lv.Opt("+Redraw")
}

Recorder_RemoveEvent(*) {
    global g_Rec
    row := g_Rec["ui"]["events"].GetNext()
    if !row || g_Rec["on"] || g_Rec["lastSession"] = ""
        return
    g_Rec["events"].RemoveAt(row)
    session := TrackJsonDecode(FileRead(g_Rec["lastSession"], "UTF-8"))
    session["events"] := g_Rec["events"]
    file := FileOpen(g_Rec["lastSession"], "w", "UTF-8-RAW")
    file.Write(TrackJsonEncode(session))
    file.Close()
    Recorder_ShowEvents()
}

Recorder_Build(kind) {
    global g_Rec, g_Autopilot, g_StudyLLM_Endpoint, g_StudyLLM_TextModel
    ui := g_Rec["ui"]
    request := Map("narrate", ui["narrate"].Value, "video", ui["video"].Value, "polish", ui["polish"].Value,
        "endpoint", g_StudyLLM_Endpoint, "model", g_StudyLLM_TextModel, "budget_usd", 1)
    if Trim(ui["title"].Value) != ""
        request["title"] := Trim(ui["title"].Value)
    if kind = "session" {
        if g_Rec["on"]
            Recorder_Stop()
        if g_Rec["lastSession"] = "" || !FileExist(g_Rec["lastSession"])
            return MsgBoxTop("Record a procedure first (Start recording, do the task, Stop).", "Record a procedure", "Iconi")
        request["session"] := g_Rec["lastSession"]
    } else {
        run := g_Autopilot["lastRun"]
        dir := IsObject(run) ? run["dir"] : ""
        if dir = "" && TrackDB_Ready()
            dir := TrackDB().Scalar("SELECT dir FROM autopilot_run WHERE dir<>'' ORDER BY started DESC LIMIT 1")
        if dir = "" || !FileExist(dir . "\run.json")
            return MsgBoxTop("No audited run yet. Use Portals > Run && record first.", "Record a procedure", "Iconi")
        request["run"] := dir . "\run.json"
        request["out_dir"] := dir . "\sop"
    }
    Recorder_Status(request.Get("video", 0) ? "Writing the SOP and rendering the video (about a second per step)..." : "Writing the SOP...")
    ui["build"].Enabled := false
    Autopilot_Job("sop_build", request, Recorder_BuildDone.Bind(kind), 1200000)
}

Recorder_BuildDone(kind, result) {
    global g_Rec, g_Sequences
    ui := g_Rec["ui"]
    ui["build"].Enabled := true
    if !result.Get("ok", false)
        return Recorder_Status("Could not build the SOP: " . result.Get("error", "unknown error"))
    g_Rec["lastBuild"] := result
    saved := ""
    if kind = "session" && ui["saveWorkflow"].Value && result["workflow"].Length {
        try {
            name := Autopilot_SaveWorkflow(AutopilotUI_UniqueName(result["title"]), AutopilotUI_EngineSteps(result["workflow"]))
            Recorder_SeedAnchors(name, result["anchors"])
            saved := name
        } catch as err
            Recorder_Status("SOP written, but the workflow could not be saved: " . err.Message)
    }
    notes := result.Get("notes", [])
    Recorder_Status("SOP ready: " . result["steps"].Length . " steps" . (result["video"] != "" ? " · video made" : "") . (saved != "" ? " · workflow '" . saved . "' saved" : "")
        . (notes.Length ? " · " . StrJoin(notes, " ") : ""))
    Recorder_RememberBuild(result, saved)
    Recorder_RefreshBuilt()
    try Run('"' . result["html"] . '"')
}

; The recording already observed each click's window, position, label and pixels:
; store them as self-heal anchors so the first run can already re-find moved buttons.
Recorder_SeedAnchors(workflow, anchors) {
    if !TrackDB_Ready()
        return
    for , a in anchors {
        step := Map("action", a["action"], "target", a["target"], "param", "")
        anchor := Map("exe", a["exe"], "title", SubStr(a["title"], 1, 200), "class", a["class"], "rel_x", a["rel_x"], "rel_y", a["rel_y"],
            "win_w", a["win_w"], "win_h", a["win_h"], "label", a["label"], "label_dx", a["label_dx"], "label_dy", a["label_dy"], "sample", a["sample"])
        try SelfHeal_SaveAnchor(SelfHeal_Key(workflow, a["step_index"], step), workflow, a["step_index"], step, anchor)
    }
}

Recorder_RememberBuild(result, workflow) {
    if !TrackDB_Ready()
        return
    builds := []
    try builds := TrackJsonDecode(TrackDB_MetaGet("sop_builds", "[]"))
    if !(builds is Array)
        builds := []
    builds.InsertAt(1, Map("at", Autopilot_Now(), "title", result["title"], "steps", result["steps"].Length, "video", result["video"],
        "html", result["html"], "docx", result["docx"], "folder", result["folder"], "workflow", workflow))
    while builds.Length > 50
        builds.Pop()
    TrackDB_MetaSet("sop_builds", TrackJsonEncode(builds))
}

Recorder_Builds() {
    builds := []
    try builds := TrackJsonDecode(TrackDB_MetaGet("sop_builds", "[]"))
    return builds is Array ? builds : []
}

Recorder_RefreshBuilt() {
    global g_Rec
    if !g_Rec["ui"].Has("built")
        return
    lv := g_Rec["ui"]["built"]
    lv.Opt("-Redraw"), lv.Delete()
    for , b in Recorder_Builds()
        lv.Add("", b["at"], b["title"], b["steps"], b["video"] != "" ? "yes" : "no", b["workflow"])
    lv.Opt("+Redraw")
}

Recorder_OpenBuilt(lv, row) {
    builds := Recorder_Builds()
    if row && row <= builds.Length && FileExist(builds[row]["html"])
        Run('"' . builds[row]["html"] . '"')
}

Recorder_OpenOutput(kind) {
    global g_Rec
    build := g_Rec["lastBuild"]
    if !IsObject(build) {
        builds := Recorder_Builds()
        if !builds.Length
            return MsgBoxTop("Build an SOP first.", "Record a procedure", "Iconi")
        build := builds[1]
    }
    path := kind = "folder" ? build["folder"] : build[kind]
    if path = "" || !FileExist(path)
        return MsgBoxTop(kind = "video" ? "No video was made (see the status line)." : "That file is missing.", "Record a procedure", "Iconi")
    Run('"' . path . '"')
}
