; One collection/review surface for interface maps, visual candidates and usage.
; The existing engines own their schemas, evidence and execution safeguards.
global g_LearnHub := Map("ui", Map(), "controls", [], "windows", [], "rows", [], "allRows", [], "busy", false)

LearningUI_Rect(ctl) {
    rect := Buffer(16), point := Buffer(8)
    DllCall("GetWindowRect","Ptr",ctl.Hwnd,"Ptr",rect)
    NumPut("Int",NumGet(rect,0,"Int"),"Int",NumGet(rect,4,"Int"),point)
    DllCall("MapWindowPoints","Ptr",0,"Ptr",MainGui.Hwnd,"Ptr",point,"UInt",1)
    scale := DllCall("GetDpiForWindow","Ptr",MainGui.Hwnd,"UInt")/96
    return Map("x",NumGet(point,0,"Int")/scale,"y",NumGet(point,4,"Int")/scale,
        "w",(NumGet(rect,8,"Int")-NumGet(rect,0,"Int"))/scale,"h",(NumGet(rect,12,"Int")-NumGet(rect,4,"Int"))/scale)
}

LearningUI_Offset(ctl) {
    ctl.GetPos(&x,&y)
    actual := LearningUI_Rect(ctl)
    return [actual["x"]-x,actual["y"]-y]
}

LearningHub_Add(kind, key, options, text := "") {
    ctl := MainGui.Add(kind, options, text)
    g_LearnHub["ui"][key] := ctl
    g_LearnHub["controls"].Push(ctl)
    return ctl
}

LearningHub_Build() {
    global TabCtrl, g_LearnHub
    TabCtrl.UseTab(14)
    LearningHub_Add("Text", "title", "x16 y58 w850 h26", "Learning — collect, review, reuse").SetFont("s13 bold")
    LearningHub_Add("Text", "guide", "x16 y90 w850 h42", "1 Choose a window.  2 Map its controls or enable the two recorders while doing one task.  3 Stop, select a result below, and review its evidence before reuse. Chrome pages have their own window/profile-aware workspace.")
    LearningHub_Add("Text", "windowLabel", "x16 y142 w58 h18", "Window:")
    LearningHub_Add("DropDownList", "window", "x78 y138 w534", [])
    LearningHub_Add("Button", "options", "x624 y138 w94 h27", "Options").OnEvent("Click",LearningHub_Options)
    LearningHub_Add("Button", "windows", "x730 y138 w138 h27", "Refresh windows").OnEvent("Click", LearningHub_Windows)
    LearningHub_Add("Button", "map", "x16 y176 w145 h28", "Map app controls").OnEvent("Click", LearningHub_Map)
    LearningHub_Add("CheckBox", "visual", "x174 y181 w165 h22", "Watch visual targets").OnEvent("Click", LearningHub_Visual)
    LearningHub_Add("CheckBox", "usage", "x350 y181 w175 h22", "Learn usage sequences").OnEvent("Click", LearningHub_Usage)
    LearningHub_Add("Button", "scan", "x540 y176 w100 h28", "Scan window").OnEvent("Click", LearningHub_Scan)
    LearningHub_Add("Button", "stop", "x650 y176 w100 h28", "Stop both").OnEvent("Click", LearningHub_Stop)
    LearningHub_Add("Button", "refresh", "x760 y176 w108 h28", "Refresh results").OnEvent("Click", LearningHub_Refresh)
    LearningHub_Add("Text", "state", "x16 y214 w850 h34", "")
    LearningHub_Add("Edit", "search", "x16 y252 w450 h25").OnEvent("Change", LearningHub_Filter)
    SendMessage(0x1501, true, StrPtr("Search names, application, evidence or sequence"), g_LearnHub["ui"]["search"])
    LearningHub_Add("DropDownList", "source", "x478 y252 w180 Choose1", ["All sources", "Interface maps", "Visual targets", "Usage candidates", "Repeated sequences"]).OnEvent("Change", LearningHub_Filter)
    LearningHub_Add("Button", "export", "x670 y252 w198 h27", "Export certified patterns").OnEvent("Click", LearningHub_Export)
    LearningHub_Add("ListView", "results", "x16 y288 w852 h180 Grid -Multi", ["Source", "Item", "Evidence / state", "Application", "Recorded"]).OnEvent("ItemSelect", LearningHub_Select)
    LearningHub_Add("Edit", "details", "x16 y480 w852 h220 ReadOnly Multi VScroll")
    actions := [["review", "Review live", LearningHub_Review], ["copy", "Copy reference", LearningHub_Copy],
        ["evidence", "Evidence / lessons", LearningLab_Open], ["script", "App script tools", LearningHub_Script],
        ["chrome", "Chrome learning", (*) => FanNav_Open(25)], ["help", "How to use results", LearningHub_Help]]
    for action in actions
        LearningHub_Add("Button", action[1], "x16 y720 w136 h28", action[2]).OnEvent("Click", action[3])
    LearningHub_Windows()
    LearningHub_Refresh()
}

LearningHub_Layout(width, height) {
    u := g_LearnHub["ui"]
    if !u.Count
        return
    width := Max(860, width), height := Max(760, height)
    offset := LearningUI_Offset(u["title"]), offsetX := offset[1], offsetY := offset[2]
    u["title"].Move(16-offsetX,58-offsetY,width-32,26)
    u["guide"].Move(16-offsetX,90-offsetY,width-32,42)
    u["windowLabel"].Move(16-offsetX,142-offsetY,58,18)
    u["window"].Move(78-offsetX,138-offsetY,width-350)
    u["options"].Move(width-260-offsetX,138-offsetY), u["windows"].Move(width-154-offsetX,138-offsetY)
    u["map"].Move(16-offsetX,176-offsetY), u["visual"].Move(174-offsetX,181-offsetY), u["usage"].Move(350-offsetX,181-offsetY)
    u["state"].Move(16-offsetX,214-offsetY,width-32,34)
    u["scan"].Move(width-324-offsetX,176-offsetY,90,28), u["stop"].Move(width-224-offsetX,176-offsetY,90,28), u["refresh"].Move(width-124-offsetX,176-offsetY,108,28)
    u["search"].Move(16-offsetX,252-offsetY,width-434), u["source"].Move(width-406-offsetX,252-offsetY), u["export"].Move(width-214-offsetX,252-offsetY)
    listHeight := Max(160, Floor((height - 436) * .5))
    u["results"].Move(16-offsetX, 288-offsetY, width - 32, listHeight)
    detailsY := 288 + listHeight + 10
    u["details"].Move(16-offsetX, detailsY-offsetY, width - 32, height - detailsY - 70)
    keys := ["review", "copy", "evidence", "script", "chrome", "help"]
    buttonW := Floor((width - 32 - 5*8)/6)
    for index, key in keys
        u[key].Move(16+(index-1)*(buttonW+8)-offsetX, height-58-offsetY, buttonW, 28)
    for column, fraction in [.13, .25, .25, .22, .15]
        u["results"].ModifyCol(column, Floor((width-52)*fraction))
}

LearningHub_Windows(*) {
    u := g_LearnHub["ui"], prior := LearningHub_Target(), windows := [], names := [], selected := 1
    for hwnd in WinGetList() {
        try {
            title := WinGetTitle(hwnd), exe := WinGetProcessName(hwnd)
            if title = "" || WinGetPID(hwnd) = DllCall("GetCurrentProcessId", "UInt") || WinGetMinMax(hwnd) = -1
                continue
            windows.Push(Map("hwnd", hwnd, "pid", WinGetPID(hwnd), "title", title, "exe", exe))
            names.Push(exe . " | " . TrackEllipsis(title, 90) . " | " . hwnd)
            if prior.Count && hwnd = prior["hwnd"]
                selected := windows.Length
        }
    }
    g_LearnHub["windows"] := windows
    u["window"].Delete(), u["window"].Add(names)
    if names.Length
        u["window"].Choose(selected)
}

LearningHub_Target() {
    u := g_LearnHub["ui"]
    index := u.Has("window") ? u["window"].Value : 0
    return index && index <= g_LearnHub["windows"].Length ? g_LearnHub["windows"][index] : Map()
}

LearningHub_Map(*) {
    target := LearningHub_Target()
    if !LearningHub_ValidTarget(target)
        return
    if StrLower(target["exe"]) = "chrome.exe" {
        ChromeLearning_SelectWindow(target["hwnd"])
        FanNav_Open(25)
        g_ChromeLearn["ui"]["status"].Value := "Use Capture visible page here. Browser maps are scoped to this window and its assigned profile label."
        return
    }
    g_LearnHub["busy"] := true
    g_LearnHub["ui"]["state"].Value := "Mapping controls and accessibility. The selected application comes forward for this explicit capture."
    SetTimer(LearningHub_MapWork.Bind(target), -25)
}

LearningHub_MapWork(target) {
    try {
        if !LearningHub_ValidTarget(target)
            return
        MainGui.Hide()
        result := AppMap_LearnWindow(target["hwnd"], Map("controls", true, "acc", true, "menus", true,
            "altocr", false, "visuals", true, "ocrtext", true))
        g_LearnHub["ui"]["details"].Value := "Mapped " . target["title"] . ". Review the retained controls below. Menu opening by simulated keys was not enabled."
    } catch as captureError {
        g_LearnHub["ui"]["details"].Value := captureError.Message
    } finally {
        g_LearnHub["busy"] := false
        MainGui.Show("NA")
        LearningHub_Refresh()
    }
}

LearningHub_ValidTarget(target) {
    valid := target.Count && WinExist("ahk_id " . target.Get("hwnd", 0))
    if valid
        try valid := WinGetPID(target["hwnd"]) = target["pid"]
    if !valid
        g_LearnHub["ui"]["details"].Value := "Choose an available window, then try again. Refresh windows if it was closed or replaced."
    return valid
}

LearningHub_Visual(ctl, *) {
    if ctl.Value
        VS_Start()
    else
        VS_Stop()
    LearningHub_State()
}

LearningHub_Usage(ctl, *) {
    if ctl.Value
        UsagePredictor_Start()
    else
        UsagePredictor_Stop()
    LearningHub_State()
}

LearningHub_Stop(*) {
    VS_Stop(), UsagePredictor_Stop()
    LearningHub_State()
}

LearningHub_Scan(*) {
    target := LearningHub_Target()
    if !LearningHub_ValidTarget(target) || g_LearnHub["busy"]
        return
    if StrLower(target["exe"]) = "chrome.exe" {
        ChromeLearning_SelectWindow(target["hwnd"]), FanNav_Open(25)
        return
    }
    g_LearnHub["busy"] := true
    try {
        MainGui.Hide(), WinActivate(target["hwnd"])
        WinWaitActive(target["hwnd"], , 2)
        VS_ScanScreen("window", false)
    } finally {
        MainGui.Show("NA"), g_LearnHub["busy"] := false
        LearningHub_Refresh()
    }
}

LearningHub_State(*) {
    global g_VSOn, g_UPOn
    u := g_LearnHub["ui"]
    if !u.Count
        return
    u["visual"].Value := g_VSOn, u["usage"].Value := g_UPOn
    u["state"].Value := "Visual recorder: " . (g_VSOn ? "ON" : "off") . " | Usage learner: " . (g_UPOn ? "ON" : "off") . " | Review: " . g_LearnHub["allRows"].Length . " loaded records (Refresh to update)."
        . "`r`nRecorders observe apps as you use them; the selector scopes manual capture. Stop after one task. Frequency is not verification."
}

LearningHub_Row(source, id, label, state, app, stamp, content, extra := 0) {
    row := Map("source", source, "id", id, "label", label, "state", state, "app", app, "stamp", stamp, "content", content)
    if extra is Map
        for key, value in extra
            row[key] := value
    return row
}

LearningHub_Collect(db) {
    rows := []
    if !db
        return rows
    if db.TableExists("ui_element") && db.TableExists(AppMap_AppTable()) {
        for r in db.Query("SELECT e.*,a.title AS app_title,a.exe AS app_exe,a.learned_ts FROM ui_element e JOIN " . AppMap_AppTable() . " a ON a.id=e.app_id ORDER BY a.learned_ts DESC,e.id DESC LIMIT 120") {
            ref := r["menu_path"] != "" && r["kind"] != "menu" ? "menu " . r["menu_path"] : "click #" . r["id"]
            legacyChrome := StrLower(r["app_exe"]) = "chrome.exe"
            rows.Push(LearningHub_Row("Interface", r["id"], r["name"] != "" ? r["name"] : r["kind"] . " #" . r["id"],
                legacyChrome ? "Legacy Chrome; profile unknown" : "Observed " . r["kind"], r["app_title"], r["learned_ts"],
                "Named control from an app map. Check its current app and meaning before use.`r`nAppDSL reference: " . ref
                . "`r`nShortcut: " . r["shortcut"] . "`r`nPath: " . r["acc_path"] . "`r`nMenu: " . r["menu_path"]
                . "`r`nUse: Copy reference, open App script tools for this app, review your script, then run deliberately.",
                Map("app_id", r["app_id"], "ref", ref, "legacy_chrome",legacyChrome,"bounds", [r["x"],r["y"],r["w"],r["h"]])))
        }
    }
    if db.TableExists("vs_element") {
        for r in db.Query("SELECT v.*,w.name AS window_name FROM vs_element v LEFT JOIN win w ON w.id=v.win_id ORDER BY v.last_seen DESC LIMIT 100")
            rows.Push(LearningHub_Row("Visual", r["id"], "Target #" . r["id"] . " " . r["ocr_text"], r["review_state"], r["window_name"], r["last_seen"],
                "Visual candidate; " . r["clicks"] . " clicks and " . r["accesses"] . " accesses describe frequency.`r`nReview state: " . r["review_state"]
                . "`r`nReview note: " . r["review_note"] . "`r`nUse: Review live, test the target, certify only a correct match, then Export certified patterns for use in Workflow.",
                Map("bounds", [r["x"],r["y"],r["w"],r["h"]], "ref", r["bin_text"])))
    }
    if db.TableExists("usage_element") {
        for r in db.Query("SELECT e.*,a.exe FROM usage_element e LEFT JOIN app a ON a.id=e.app_id ORDER BY e.last_ts DESC LIMIT 100")
            rows.Push(LearningHub_Row("Usage", r["id"], r["name"] != "" ? r["name"] : "Candidate #" . r["id"],
                r["promoted"] ? "Promoted by usage" : "Observed candidate", r["exe"], r["last_ts"],
                "Usage candidate: seen " . r["seen_count"] . ", clicked " . r["click_count"] . ". Promotion measures use, not semantic correctness.`r`nUse: inspect this region and pattern, then review a named target before building a workflow.",
                Map("bounds", [r["x"],r["y"],r["w"],r["h"]], "ref", r["pattern"])))
    }
    if db.TableExists("usage_transition") {
        for r in db.Query("SELECT * FROM usage_transition ORDER BY support DESC,last_ts DESC LIMIT 80")
            rows.Push(LearningHub_Row("Sequence", r["id"], r["prefix_text"] . " > " . r["next_token"], "Observed " . r["support"] . " times", "Recorded sequence", r["last_ts"],
                "Repeated sequence:`r`n" . r["prefix_text"] . "`r`nNext: " . r["next_token"] . "`r`nSupport: " . r["support"]
                . "`r`nUse: Evidence / lessons shows the recorded checks and possible rehearsal. Inspect every step and current application state; a repeated sequence is not automatically a successful procedure.", Map("ref", r["prefix_text"] . " > " . r["next_token"])))
    }
    if db.TableExists("vs_sequence") {
        for r in db.Query("SELECT * FROM vs_sequence ORDER BY count DESC,last_seen DESC LIMIT 60")
            rows.Push(LearningHub_Row("Sequence", "visual-" . r["id"], "Visual sequence #" . r["id"], "Observed " . r["count"] . " times", "Visual recorder", r["last_seen"],
                "Vision Scout sequence retained from physical interactions.`r`n" . r["steps"]
                . "`r`nUse: inspect the recorded order and original application context in Evidence / lessons. Repetition does not verify that a task succeeded.", Map("ref", r["steps"])))
    }
    return rows
}

LearningHub_Refresh(*) {
    try {
        g_LearnHub["allRows"] := LearningHub_Collect(TrackDB())
        LearningHub_Filter()
        LearningHub_State()
    } catch as refreshError
        g_LearnHub["ui"]["details"].Value := "Could not read all learning results: " . refreshError.Message
}

LearningHub_Filter(*) {
    u := g_LearnHub["ui"], query := Trim(u["search"].Value), source := u["source"].Value
    sources := ["", "Interface", "Visual", "Usage", "Sequence"]
    g_LearnHub["rows"] := [], u["results"].Delete()
    for row in g_LearnHub["allRows"] {
        if source > 1 && row["source"] != sources[source]
            continue
        if query != "" && !InStr(row["label"] . " " . row["state"] . " " . row["app"] . " " . row["content"], query, false)
            continue
        g_LearnHub["rows"].Push(row)
        u["results"].Add(, row["source"], TrackEllipsis(row["label"], 110), row["state"], row["app"], row["stamp"])
    }
    u["details"].Value := g_LearnHub["rows"].Length . " results in this bounded review (recent maps/candidates and highest-support sequences).`r`n"
        . "Select any result to see its source, uncertainty and next action. Interface, visual and usage records appear together; use Search or the source filter to narrow them."
}

LearningHub_Selected() {
    index := g_LearnHub["ui"]["results"].GetNext()
    return index && index <= g_LearnHub["rows"].Length ? g_LearnHub["rows"][index] : Map()
}

LearningHub_Select(lv, index, selected) {
    if !selected
        return
    row := LearningHub_Selected()
    if row.Count
        g_LearnHub["ui"]["details"].Value := row["source"] . " | " . row["label"] . "`r`nApplication: " . row["app"]
            . "`r`nRecorded: " . row["stamp"] . "`r`nState: " . row["state"] . "`r`n`r`n" . row["content"]
}

LearningHub_Review(*) {
    global g_VSReviewSelectedId
    row := LearningHub_Selected()
    if !row.Count
        return
    if row["source"] = "Visual" {
        VS_LoadElements()
        g_VSReviewSelectedId := row["id"]
        VS_OpenReview([row["id"]])
    } else if row.Has("bounds") {
        Know_Flash(row["bounds"])
        g_LearnHub["ui"]["details"].Value .= "`r`n`r`nShowing retained coordinates only. This does not verify the target's identity or execute an action."
    } else
        LearningLab_Open()
}

LearningHub_Copy(*) {
    row := LearningHub_Selected()
    if row.Get("legacy_chrome",false) {
        g_LearnHub["ui"]["details"].Value := "This old generic Chrome map has no reliable window/profile scope. Capture the intended window in Chrome Learning before reuse."
        return
    }
    if row.Count && row.Get("ref", "") != "" {
        A_Clipboard := row["ref"]
        g_LearnHub["ui"]["details"].Value .= "`r`n`r`nCopied the retained reference. Recheck the live target before using it."
    }
}

LearningHub_Export(*) {
    VS_LoadElements()
    VS_ExportPromoted()
    LearningHub_Refresh()
}

LearningHub_Options(*) {
    global g_UPCaptureText, g_UPScanIntervalMs
    window := Gui("+Owner" . MainGui.Hwnd,"Learning collection options")
    window.SetFont("s9","Segoe UI")
    window.Add("Text","w560 h44","The usage learner records physical interactions across applications. These controls use its existing settings; the main window selector scopes only explicit captures.")
    literal := window.Add("CheckBox","y+12 w560 h24","Store literal typed text (optional; sensitive-window exclusions still apply)")
    literal.Value := g_UPCaptureText
    literal.OnEvent("Click",UsagePredictor_SetTextCapture)
    window.Add("Text","y+16 w560 h20","Usage visual scan interval:")
    interval := window.Add("DropDownList","y+4 w140",["3 sec","6 sec","10 sec","20 sec","30 sec"])
    chosen := 2
    for index, seconds in [3,6,10,20,30]
        if seconds*1000 = g_UPScanIntervalMs
            chosen := index
    interval.Choose(chosen), interval.OnEvent("Change",UsagePredictor_SetScanInterval)
    window.Add("Text","y+16 w560 h42","With literal text off, typing structure is still observed. Stop both ends the two learning recorders; it does not stop the separate Tracking or Live Portal features.")
    window.Show()
}

LearningHub_Help(*) {
    g_LearnHub["ui"]["details"].Value := "MAP APP CONTROLS: one explicit scan of the selected app's controls, accessibility and menus. For Chrome, use Chrome learning instead so different windows and assigned profiles stay separate.`r`n`r`n"
        . "WATCH VISUAL TARGETS: Vision Scout records visual candidates and physical interaction. Review live opens its existing test/certify workflow. Only certified targets export to Patterns.`r`n`r`n"
        . "LEARN USAGE SEQUENCES: records physical interaction and repeated continuations. Literal typed text retains its existing opt-in setting. Stop both recorders after a representative task, then Refresh results.`r`n`r`n"
        . "REVIEW AND USE: select a result; read source, state and limits; inspect its live location; inspect Evidence / lessons; copy a reference or export a certified pattern; build and simulate a Workflow before running it. Frequency and replay are not proof of correctness."
}

LearningHub_Script(*) {
    row := LearningHub_Selected()
    if !row.Get("app_id", 0) || row.Get("legacy_chrome",false) {
        g_LearnHub["ui"]["details"].Value := "Select an Interface result first. Script references are scoped to that learned application."
        return
    }
    appId := row["app_id"], window := Gui("+Resize +MinSize720x440 +Owner" . MainGui.Hwnd, "App script tools — " . row["app"])
    window.SetFont("s9", "Segoe UI")
    window.Add("Text", "x16 y16 w680 h42", "Review a script for this learned app. References come from the combined Learning results. Running sends input to the application; it is an explicit action.")
    editor := window.Add("Edit", "x16 y66 w680 h300 Multi WantTab VScroll", "focus`r`n; Paste reviewed references here")
    runButton := window.Add("Button", "x16 y380 w130 h28", "Run reviewed script")
    runButton.OnEvent("Click", (*) => AppExec_Run(appId, editor.Value))
    stopButton := window.Add("Button", "x154 y380 w90 h28", "Stop")
    stopButton.OnEvent("Click", (*) => AppExec_Stop())
    guideButton := window.Add("Button", "x252 y380 w130 h28", "DSL guide")
    guideButton.OnEvent("Click", (*) => AppLearner_ShowGuide())
    promptButton := window.Add("Button", "x390 y380 w180 h28", "Copy app instructions")
    promptButton.OnEvent("Click", (*) => (A_Clipboard := AppMap_BuildLLMPrompt(appId)))
    window.OnEvent("Size", (g, state, w, h) => LearningHub_ScriptLayout(editor,[runButton,stopButton,guideButton,promptButton],w,h))
    window.Show("w720 h440")
}

LearningHub_ScriptLayout(editor, buttons, width, height) {
    editor.Move(, , Max(500,width-32),Max(200,height-136))
    for button in buttons
        button.Move(,height-48)
}
