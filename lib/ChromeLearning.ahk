; Dedicated native Chrome learning surface. Focus following never activates Fan,
; captures a page, starts a study session or sends input to Chrome.
global g_ChromeLearn := Map("ui", Map(), "controls", [], "windows", [], "contexts", Map(),
    "target", Map(), "captures", [], "capture", Map(), "elements", [], "page", "", "offset", 0, "job", Map(), "pendingPage", Map(), "image", Map(), "foreground", 0)

ChromeLearning_Add(kind, key, options, text := "") {
    ctl := MainGui.Add(kind, options, text)
    g_ChromeLearn["ui"][key] := ctl
    g_ChromeLearn["controls"].Push(ctl)
    return ctl
}

ChromeLearning_Build() {
    TabCtrl.UseTab(25)
    ChromeLearning_Add("Text", "title", "x16 y58 w850 h26", "Chrome learning — window, profile, page evidence").SetFont("s13 bold")
    ChromeLearning_Add("Text", "guide", "x16 y86 w850 h44", "Choose the Chrome window, assign its profile label, then Capture visible page. Review observed controls and text, verify a target, or add useful text to Study. Focus following changes this panel's target without activating Fan or capturing automatically.")
    ChromeLearning_Add("CheckBox", "follow", "x16 y134 w680 h22", "Follow focused Chrome window and select this learning tab (without activating Fan)").OnEvent("Click", ChromeLearning_FollowChanged)
    ChromeLearning_Add("DropDownList", "window", "x16 y164 w700", []).OnEvent("Change", ChromeLearning_WindowChanged)
    ChromeLearning_Add("Button", "windows", "x730 y164 w138 h27", "Refresh Chrome").OnEvent("Click", ChromeLearning_Windows)
    ChromeLearning_Add("Text", "profileLabel", "x16 y204 w50 h18", "Profile:")
    ChromeLearning_Add("Edit", "profile", "x70 y200 w250 h25")
    SendMessage(0x1501, true, StrPtr("Unknown — assign a label for this window"), g_ChromeLearn["ui"]["profile"])
    ChromeLearning_Add("Button", "saveProfile", "x332 y200 w120 h27", "Assign label").OnEvent("Click", ChromeLearning_SaveProfile)
    ChromeLearning_Add("Text", "profileNote", "x468 y203 w400 h30", "User-assigned label; profile identity is not inferred from a title or process ID.")
    ChromeLearning_Add("Text", "context", "x16 y240 w850 h36", "")
    buttons := [["capture", "Capture visible page", ChromeLearning_Capture], ["savedRefresh", "Refresh saved captures", ChromeLearning_LoadCaptures],
        ["library", "Study library", (*) => FanNav_Open(18)], ["portal", "Live Portal", (*) => FanNav_Open(19)],
        ["studyHelp", "How Study works", ChromeLearning_StudyHelp]]
    for item in buttons
        ChromeLearning_Add("Button", item[1], "x16 y284 w160 h28", item[2]).OnEvent("Click", item[3])
    ChromeLearning_Add("DropDownList", "saved", "x16 y322 w610", []).OnEvent("Change", ChromeLearning_OpenSaved)
    ChromeLearning_Add("DropDownList", "scope", "x638 y322 w230 Choose1", ["Current window session", "All saved Chrome sessions"]).OnEvent("Change", ChromeLearning_LoadCaptures)
    ChromeLearning_Add("Edit", "search", "x16 y360 w640 h25")
    SendMessage(0x1501, true, StrPtr("Search this captured page, then press Search"), g_ChromeLearn["ui"]["search"])
    ChromeLearning_Add("Button", "searchButton", "x670 y360 w70 h27", "Search").OnEvent("Click", (*) => ChromeLearning_GetPage(0))
    ChromeLearning_Add("Button", "previous", "x748 y360 w55 h27", "< 100").OnEvent("Click", (*) => ChromeLearning_GetPage(Max(0,g_ChromeLearn["offset"]-100)))
    ChromeLearning_Add("Button", "next", "x811 y360 w57 h27", "100 >").OnEvent("Click", (*) => ChromeLearning_GetPage(g_ChromeLearn["offset"]+100))
    ChromeLearning_Add("ListView", "elements", "x16 y400 w490 h270 Grid -Multi", ["Type", "Observed label / description", "Group"]).OnEvent("ItemSelect", ChromeLearning_ElementSelected)
    ChromeLearning_Add("Picture", "picture", "x520 y400 w348 h145")
    ChromeLearning_Add("Edit", "details", "x520 y556 w348 h138 ReadOnly Multi VScroll")
    for action in [["verify", "Verify live target", ChromeLearning_Verify], ["copy", "Copy observed text", ChromeLearning_Copy],
        ["import", "Add text to Study", ChromeLearning_Import], ["help", "Browser learning guide", ChromeLearning_Help]]
        ChromeLearning_Add("Button", action[1], "x16 y710 w200 h28", action[2]).OnEvent("Click", action[3])
    ChromeLearning_Add("Text", "status", "x16 y748 w850 h20", "Ready. Captures and profile labels stay local; no model call is made by this interface.")
    g_ChromeLearn["ui"]["follow"].Value := FanData_Config().Get("chrome_learning_follow", true)
    ChromeLearning_Schema()
    ChromeLearning_Windows()
    ChromeLearning_Help()
}

ChromeLearning_Layout(width, height) {
    u := g_ChromeLearn["ui"]
    if !u.Count
        return
    width := Max(860,width), height := Max(760,height)
    offset := LearningUI_Offset(u["title"]), offsetX := offset[1], offsetY := offset[2]
    u["title"].Move(16-offsetX,58-offsetY,width-32,26)
    u["guide"].Move(16-offsetX,86-offsetY,width-32,44)
    u["follow"].Move(16-offsetX,134-offsetY,width-32,22)
    u["window"].Move(16-offsetX,164-offsetY,width-182), u["windows"].Move(width-154-offsetX,164-offsetY)
    u["profileLabel"].Move(16-offsetX,204-offsetY), u["profile"].Move(70-offsetX,200-offsetY)
    u["saveProfile"].Move(332-offsetX,200-offsetY), u["profileNote"].Move(468-offsetX,203-offsetY,width-484,30)
    u["context"].Move(16-offsetX,240-offsetY,width-32,36)
    u["saved"].Move(16-offsetX,322-offsetY,width-274), u["scope"].Move(width-246-offsetX,322-offsetY)
    for index, key in ["capture", "savedRefresh", "library", "portal", "studyHelp"]
        u[key].Move(16+(index-1)*Floor((width-32)/5)-offsetX, 284-offsetY, Floor((width-32)/5)-8, 28)
    u["search"].Move(16-offsetX,360-offsetY,width-244), u["searchButton"].Move(width-212-offsetX,360-offsetY)
    u["previous"].Move(width-134-offsetX,360-offsetY), u["next"].Move(width-71-offsetX,360-offsetY)
    leftW := Floor((width-48)*.57), rightX := leftW+32, rightW := width-rightX-16
    bodyH := Max(240,height-500), pictureH := Min(175,Floor(bodyH*.48))
    u["elements"].Move(16-offsetX,400-offsetY,leftW,bodyH)
    u["picture"].Move(rightX-offsetX,400-offsetY,rightW,pictureH)
    u["details"].Move(rightX-offsetX,410+pictureH-offsetY,rightW,bodyH-pictureH-10)
    for index, key in ["verify", "copy", "import", "help"]
        u[key].Move(16+(index-1)*Floor((width-32)/4)-offsetX,height-86-offsetY,Floor((width-32)/4)-8,28)
    u["status"].Move(16-offsetX,height-48-offsetY,width-32,20)
    for index, fraction in [.18,.57,.25]
        u["elements"].ModifyCol(index,Floor((leftW-20)*fraction))
    ChromeLearning_DrawImage()
}

ChromeLearning_Schema() {
    db := TrackDB()
    db.Exec("CREATE TABLE IF NOT EXISTS chrome_learning_context (context_id TEXT PRIMARY KEY, hwnd INTEGER, pid INTEGER, opened_ts TEXT, last_seen TEXT, title TEXT, profile_label TEXT, profile_source TEXT)")
    db.Exec("CREATE TABLE IF NOT EXISTS chrome_learning_capture (page_id TEXT PRIMARY KEY, context_id TEXT, profile_label TEXT, captured_ts TEXT, title TEXT, url TEXT)")
    db.Exec("CREATE INDEX IF NOT EXISTS ix_chrome_learning_context ON chrome_learning_capture(context_id,captured_ts)")
}

ChromeLearning_Context(hwnd) {
    if !WinExist("ahk_id " . hwnd) || StrLower(WinGetProcessName(hwnd)) != "chrome.exe"
        return Map()
    key := String(hwnd), pid := WinGetPID(hwnd), contexts := g_ChromeLearn["contexts"]
    if !contexts.Has(key) || contexts[key]["pid"] != pid {
        context := Map("context_id", "chrome-" . A_Now . "-" . hwnd . "-" . A_TickCount,
            "hwnd", hwnd, "pid", pid, "title", WinGetTitle(hwnd), "profile_label", "", "profile_source", "unknown", "url", "", "url_title", "")
        contexts[key] := context
        TrackDB().Run("INSERT INTO chrome_learning_context VALUES(?,?,?,?,?,?,?,?)", context["context_id"], hwnd, pid, TrackTS(), TrackTS(), context["title"], "", "unknown")
    }
    context := contexts[key]
    context["title"] := WinGetTitle(hwnd)
    return context
}

ChromeLearning_Windows(*) {
    windows := [], names := [], selected := 0, target := g_ChromeLearn["target"]
    for hwnd in WinGetList("ahk_exe chrome.exe") {
        try {
            if WinGetTitle(hwnd) = "" || WinGetMinMax(hwnd) = -1
                continue
            context := ChromeLearning_Context(hwnd)
            if !context.Count
                continue
            windows.Push(context)
            names.Push(ChromeLearning_Label(context) . " | HWND " . hwnd . " | " . context["title"])
            if target.Count && target["context_id"] = context["context_id"]
                selected := windows.Length
        }
    }
    ; Never carry an old HWND's label into a newly created window.
    expired := []
    for key, context in g_ChromeLearn["contexts"]
        if !WinExist("ahk_id " . context["hwnd"])
            expired.Push(key)
    for key in expired
        g_ChromeLearn["contexts"].Delete(key)
    g_ChromeLearn["windows"] := windows
    u := g_ChromeLearn["ui"]
    u["window"].Delete(), u["window"].Add(names)
    if windows.Length {
        u["window"].Choose(selected ? selected : 1)
        ChromeLearning_WindowChanged()
    } else {
        g_ChromeLearn["target"] := Map()
        u["context"].Value := "No visible Chrome window. Open or restore a window, then Refresh Chrome."
    }
}

ChromeLearning_Label(context) => context.Get("profile_label", "") != "" ? context["profile_label"] . " (assigned)" : "Profile unknown"

ChromeLearning_WindowChanged(*) {
    index := g_ChromeLearn["ui"]["window"].Value
    if index && index <= g_ChromeLearn["windows"].Length {
        g_ChromeLearn["target"] := g_ChromeLearn["windows"][index]
        ChromeLearning_RenderContext()
        ChromeLearning_LoadCaptures()
    }
}

ChromeLearning_SelectWindow(hwnd) {
    if !g_ChromeLearn["ui"].Count
        return
    context := ChromeLearning_Context(hwnd)
    if !context.Count
        return
    g_ChromeLearn["target"] := context
    ChromeLearning_Windows()
}

ChromeLearning_RenderContext() {
    context := g_ChromeLearn["target"], u := g_ChromeLearn["ui"]
    if !context.Count
        return
    u["profile"].Value := context["profile_label"]
    url := context["url_title"] = context["title"] && context["url"] != "" ? context["url"] : "not read for this page yet — capture to observe it"
    u["context"].Value := TrackEllipsis(ChromeLearning_Label(context),30) . " | Window " . context["hwnd"] . " | PID " . context["pid"] . " | " . TrackEllipsis(context["title"],55) . "`r`nAddress: " . TrackEllipsis(url,115)
}

ChromeLearning_SaveProfile(*) {
    context := g_ChromeLearn["target"]
    if !context.Count
        return
    context["profile_label"] := SubStr(Trim(g_ChromeLearn["ui"]["profile"].Value),1,120)
    context["profile_source"] := context["profile_label"] != "" ? "user_assigned" : "unknown"
    TrackDB().Run("UPDATE chrome_learning_context SET profile_label=?,profile_source=? WHERE context_id=?", context["profile_label"],context["profile_source"],context["context_id"])
    ChromeLearning_Windows()
    g_ChromeLearn["ui"]["status"].Value := "Label assigned to this live window. Existing captures retain the label recorded when captured. This is not account verification."
}

ChromeLearning_FollowChanged(ctl, *) {
    config := FanData_Config(), config["chrome_learning_follow"] := ctl.Value = 1
    FanData_SaveConfig(config)
}

ChromeLearning_Start() {
    callback := CallbackCreate(ChromeLearning_WindowDestroyed)
    hook := DllCall("SetWinEventHook","UInt",0x8001,"UInt",0x8001,"Ptr",0,"Ptr",callback,"UInt",0,"UInt",0,"UInt",2,"Ptr")
    g_ChromeLearn["destroyCallback"] := callback, g_ChromeLearn["destroyHook"] := hook
    SetTimer(ChromeLearning_Poll, 500)
    OnExit(ChromeLearning_OnExit)
}

ChromeLearning_WindowDestroyed(hook, event, hwnd, objectId, childId, thread, time) {
    if objectId != 0 || childId != 0
        return
    key := String(hwnd)
    if g_ChromeLearn["contexts"].Has(key) {
        g_ChromeLearn["contexts"][key]["closed"] := true
        g_ChromeLearn["contexts"].Delete(key)
    }
}

ChromeLearning_Poll() {
    try {
        hwnd := WinExist("A"), previous := g_ChromeLearn["foreground"]
        g_ChromeLearn["foreground"] := hwnd
        if !hwnd || !g_ChromeLearn["ui"]["follow"].Value || StrLower(WinGetProcessName(hwnd)) != "chrome.exe"
            return
        context := g_ChromeLearn["target"]
        title := WinGetTitle(hwnd)
        if previous != hwnd || !context.Count || context["hwnd"] != hwnd || context["title"] != title {
            g_ChromeLearn["ui"]["scope"].Choose(1)
            ChromeLearning_SelectWindow(hwnd)
            FanNav_Open(25)
        }
    }
}

ChromeLearning_StartJob(tool, args, callback) {
    if g_ChromeLearn["job"].Count {
        g_ChromeLearn["ui"]["status"].Value := "A local page request is still running. Wait for its result."
        return false
    }
    dir := A_Temp . "\FanChromeLearning-" . DllCall("GetCurrentProcessId", "UInt")
    DirCreate(dir)
    request := dir . "\" . A_Now . "-" . A_TickCount . ".json", result := request . ".result"
    Track_WriteFile(request,TrackJsonEncode(Map("tool",tool,"args",args,"result",result)))
    interpreter := A_IsCompiled ? A_ProgramFiles . "\AutoHotkey\v2\AutoHotkey64.exe" : A_AhkPath
    worker := FanData_ProjectRoot() . "\fan\LearningBridgeWorker.ahk"
    try {
        Run('"' . interpreter . '" /ErrorStdOut=UTF-8 "' . worker . '" "' . request . '"',FanData_ProjectRoot(),"Hide",&pid)
        g_ChromeLearn["job"] := Map("pid",pid,"path",result,"callback",callback,"started",A_TickCount)
        SetTimer(ChromeLearning_PollJob,150)
        g_ChromeLearn["ui"]["status"].Value := "Reading local browser evidence… You can continue using the GUI."
        return true
    } catch as workerError {
        g_ChromeLearn["ui"]["status"].Value := workerError.Message
        return false
    }
}

ChromeLearning_PollJob() {
    job := g_ChromeLearn["job"]
    if !job.Count
        return
    if FileExist(job["path"]) {
        SetTimer(ChromeLearning_PollJob,0), g_ChromeLearn["job"] := Map()
        try {
            result := TrackJsonDecode(FileRead(job["path"],"UTF-8"))
            if !result.Get("ok",false)
                throw Error(result.Get("error","Page request failed"))
            job["callback"].Call(result)
        } catch as requestError
            g_ChromeLearn["ui"]["details"].Value := g_ChromeLearn["ui"]["status"].Value := "Page request: " . requestError.Message
        ChromeLearning_NextPageJob()
    } else if A_TickCount-job["started"] > 190000 || !ProcessExist(job["pid"]) {
        SetTimer(ChromeLearning_PollJob,0), g_ChromeLearn["job"] := Map()
        g_ChromeLearn["ui"]["status"].Value := "Page request ended without a result. Check that the local bridge is running, then try again."
        ChromeLearning_NextPageJob()
    }
}

ChromeLearning_NextPageJob() {
    pending := g_ChromeLearn["pendingPage"]
    if !pending.Count || g_ChromeLearn["job"].Count
        return
    g_ChromeLearn["pendingPage"] := Map()
    if pending["page"] = g_ChromeLearn["page"]
        ChromeLearning_StartJob("fan_page_get",Map("page_id",pending["page"],"offset",pending["offset"],"query",pending["query"],"limit",100),ChromeLearning_ShowPage.Bind(pending["page"],pending["offset"]))
}

ChromeLearning_Capture(*) {
    context := g_ChromeLearn["target"]
    if !context.Count || context.Get("closed",false) || !WinExist("ahk_id " . context["hwnd"]) || WinGetPID(context["hwnd"]) != context["pid"] {
        g_ChromeLearn["ui"]["status"].Value := "Select an available Chrome window first."
        return
    }
    ; Always take a fresh observation here. The legacy URL/schema cache is not
    ; scoped by Chrome profile and must not reuse another window's observation.
    ChromeLearning_StartJob("fan_page_learn",Map("hwnd",context["hwnd"],"refresh",true),ChromeLearning_Captured.Bind(context.Clone()))
}

ChromeLearning_Captured(context, page) {
    if !page.Get("page_id","")
        throw Error("Capture returned no page identity")
    TrackDB().Run("INSERT OR REPLACE INTO chrome_learning_capture VALUES(?,?,?,?,?,?)",page["page_id"],context["context_id"],context["profile_label"],TrackTS(),page.Get("title",context["title"]),page.Get("url",""))
    live := g_ChromeLearn["target"]
    if !live.Count || live["context_id"] != context["context_id"] {
        g_ChromeLearn["ui"]["status"].Value := "Capture saved for its original window. The selected window changed; its results were not mixed into this panel."
        return
    }
    live["url"] := page.Get("url",""), live["url_title"] := context["title"]
    ChromeLearning_RenderContext()
    g_ChromeLearn["page"] := page["page_id"]
    ChromeLearning_LoadCaptures()
    ChromeLearning_GetPage(0)
}

ChromeLearning_LoadCaptures(*) {
    context := g_ChromeLearn["target"], u := g_ChromeLearn["ui"]
    g_ChromeLearn["captures"] := [], names := []
    if context.Count || u["scope"].Value = 2 {
        g_ChromeLearn["captures"] := u["scope"].Value = 2
            ? TrackDB().Query("SELECT * FROM chrome_learning_capture ORDER BY captured_ts DESC,rowid DESC LIMIT 100")
            : TrackDB().Query("SELECT * FROM chrome_learning_capture WHERE context_id=? ORDER BY captured_ts DESC,rowid DESC LIMIT 100",context["context_id"])
        for capture in g_ChromeLearn["captures"]
            names.Push(capture["captured_ts"] . " | " . (capture["profile_label"] != "" ? capture["profile_label"] : "Profile unknown") . " | " . capture["title"] . " | " . capture["url"])
    }
    u["saved"].Delete(), u["saved"].Add(names)
    u["elements"].Delete(), g_ChromeLearn["elements"] := [], u["picture"].Value := "", g_ChromeLearn["image"] := Map(), g_ChromeLearn["pendingPage"] := Map()
    if names.Length {
        selected := 1
        for index, capture in g_ChromeLearn["captures"]
            if capture["page_id"] = g_ChromeLearn["page"]
                selected := index
        u["saved"].Choose(selected), g_ChromeLearn["page"] := g_ChromeLearn["captures"][selected]["page_id"]
        g_ChromeLearn["capture"] := g_ChromeLearn["captures"][selected]
        u["details"].Value := "Choose a saved capture to load its elements. Captures shown here belong to this window session only."
    } else {
        g_ChromeLearn["page"] := ""
        g_ChromeLearn["capture"] := Map()
        u["details"].Value := "No captures for this window session yet. Capture visible page to collect controls and text. Historical captures from other sessions are available in the existing standalone Chrome Page Learner."
    }
}

ChromeLearning_OpenSaved(*) {
    index := g_ChromeLearn["ui"]["saved"].Value
    if index && index <= g_ChromeLearn["captures"].Length {
        g_ChromeLearn["ui"]["elements"].Delete(), g_ChromeLearn["elements"] := []
        g_ChromeLearn["ui"]["picture"].Value := "", g_ChromeLearn["image"] := Map()
        g_ChromeLearn["ui"]["details"].Value := "Loading the selected capture's evidence…"
        g_ChromeLearn["page"] := g_ChromeLearn["captures"][index]["page_id"]
        g_ChromeLearn["capture"] := g_ChromeLearn["captures"][index]
        ChromeLearning_GetPage(0)
    }
}

ChromeLearning_GetPage(offset) {
    page := g_ChromeLearn["page"]
    if page = ""
        return
    if g_ChromeLearn["job"].Count {
        g_ChromeLearn["pendingPage"] := Map("page",page,"offset",offset,"query",Trim(g_ChromeLearn["ui"]["search"].Value))
        g_ChromeLearn["ui"]["status"].Value := "Selected page read queued after the current local request."
        return
    }
    args := Map("page_id",page,"query",Trim(g_ChromeLearn["ui"]["search"].Value),"offset",offset,"limit",100)
    ChromeLearning_StartJob("fan_page_get",args,ChromeLearning_ShowPage.Bind(page,offset))
}

ChromeLearning_ShowPage(pageId, offset, result) {
    if pageId != g_ChromeLearn["page"]
        return
    u := g_ChromeLearn["ui"]
    g_ChromeLearn["offset"] := offset, g_ChromeLearn["elements"] := result.Get("elements",[])
    g_ChromeLearn["matches"] := result.Get("matches",result.Get("element_count",0))
    u["elements"].Delete()
    for element in g_ChromeLearn["elements"]
        u["elements"].Add(,element.Get("kind",""),element.Get("description",element.Get("name","")),element.Get("group",""))
    u["status"].Value := g_ChromeLearn["elements"].Length . " shown, starting at " . offset . " / " . result.Get("matches",result.Get("element_count",0)) . " matches. Historical viewport; verify before reuse."
    u["details"].Value := "Select an observed element. Verify live target checks current identity and geometry without clicking. Add text to Study is deliberate; browser capture does not automatically become a verified answer."
    ChromeLearning_StartJob("fan_page_image",Map("page_id",pageId),ChromeLearning_ImageReady.Bind(pageId,""))
}

ChromeLearning_Selected() {
    index := g_ChromeLearn["ui"]["elements"].GetNext()
    return index && index <= g_ChromeLearn["elements"].Length ? g_ChromeLearn["elements"][index] : Map()
}

ChromeLearning_ElementSelected(lv, row, selected) {
    if !selected
        return
    element := ChromeLearning_Selected()
    if !element.Count
        return
    g_ChromeLearn["ui"]["details"].Value := "OBSERVED: " . element.Get("description","") . "`r`nRole: " . element.Get("role","")
        . "`r`nOCR: " . element.Get("ocr_text","") . "`r`nLink: " . element.Get("href","")
        . "`r`nLink evidence: " . element.Get("link_status","") . "`r`nPattern: " . element.Get("pattern_status","")
        . "`r`nUse: verify the live target, then use its observed label/reference in a reviewed workflow. Retained coordinates alone are not a locator."
    if !g_ChromeLearn["job"].Count
        ChromeLearning_StartJob("fan_page_image",Map("page_id",g_ChromeLearn["page"],"element_id",element["element_id"]),ChromeLearning_ImageReady.Bind(g_ChromeLearn["page"],element["element_id"]))
}

ChromeLearning_ImageReady(pageId, elementId, result) {
    if pageId != g_ChromeLearn["page"] || !result.Get("image_path","") || !FileExist(result["image_path"])
        return
    selected := ChromeLearning_Selected(), selectedId := selected.Get("element_id","")
    if selectedId != elementId && selectedId != "" {
        ChromeLearning_StartJob("fan_page_image",Map("page_id",pageId,"element_id",selectedId),ChromeLearning_ImageReady.Bind(pageId,selectedId))
        return
    }
    g_ChromeLearn["image"] := result
    ChromeLearning_DrawImage()
    g_ChromeLearn["ui"]["status"].Value := g_ChromeLearn["elements"].Length . " elements shown / " . g_ChromeLearn.Get("matches",0) . " matches. Retained image ready; verify live before reuse."
}

ChromeLearning_DrawImage() {
    result := g_ChromeLearn["image"]
    if !result.Count || !result.Get("image_path","") || !FileExist(result["image_path"])
        return
    u := g_ChromeLearn["ui"]
    u["picture"].GetPos(, , &width, &height)
    geometry := result.Get("geometry",Map("w",width,"h",height))
    scale := Min(width/Max(1,geometry["w"]),height/Max(1,geometry["h"]))
    u["picture"].Value := "*w" . Max(1,Floor(geometry["w"]*scale)) . " *h" . Max(1,Floor(geometry["h"]*scale)) . " " . result["image_path"]
}

ChromeLearning_Verify(*) {
    element := ChromeLearning_Selected(), context := g_ChromeLearn["target"], page := g_ChromeLearn["page"]
    if !element.Count || !context.Count || page = ""
        return
    if context["context_id"] != g_ChromeLearn["capture"].Get("context_id", "") {
        g_ChromeLearn["ui"]["status"].Value := "This capture belongs to another window session. Capture the selected live window before verification."
        return
    }
    ChromeLearning_StartJob("fan_page_resolve",Map("page_id",page,"element_id",element["element_id"],"hwnd",context["hwnd"]),ChromeLearning_Verified.Bind(page))
}

ChromeLearning_Verified(page, result) {
    if page = g_ChromeLearn["page"] {
        g_ChromeLearn["ui"]["details"].Value .= "`r`n`r`nLIVE CHECK (no click):`r`n" . TrackJsonEncode(result,2)
        g_ChromeLearn["ui"]["status"].Value := "Live target check completed. No click or keystroke was sent."
    }
}

ChromeLearning_Copy(*) {
    element := ChromeLearning_Selected()
    if element.Count
        A_Clipboard := element.Get("ocr_text","") . "`r`n" . element.Get("description","") . "`r`n" . element.Get("href","")
}

ChromeLearning_Import(*) {
    element := ChromeLearning_Selected(), capture := g_ChromeLearn["capture"]
    if !element.Count || !capture.Count
        return
    text := Trim(element.Get("ocr_text","") . "`r`n" . element.Get("description",""))
    if text = ""
        return
    text := "Browser observation (not a verified answer).`r`nPage ID: " . capture["page_id"] . "`r`nWindow session: " . capture["context_id"]
        . "`r`nAssigned profile: " . capture["profile_label"] . "`r`nURL: " . capture["url"] . "`r`n`r`n" . text
    result := Study_ImportNotes("Chrome [" . capture["profile_label"] . "]: " . capture["title"] . " | " . capture["url"],text,"Browser learning",capture["profile_label"])
    g_ChromeLearn["ui"]["status"].Value := result["ok"] ? "Selected observed text added as a Study source. Review it in Study library; no answer was verified automatically." : result["detail"]
}

ChromeLearning_Help(*) {
    g_ChromeLearn["ui"]["details"].Value := "WINDOWS / PROFILES: HWND + process + a fresh window-session identity separate captures. Assign a descriptive profile label; titles and shared Chrome processes do not prove profile identity.`r`n`r`nCAPTURE: takes a fresh, visible viewport through the existing local Chrome Page Learner. Hidden menus and scrolled-away content require another capture. This interface makes no model call.`r`n`r`nREVIEW: choose a capture, search its observed controls and OCR, inspect the screenshot, then Verify live target. Verification does not click or prove an answer is correct.`r`n`r`nUSE: copy the observed text/reference, or deliberately Add text to Study. Study library reviews sources and answers. Live Portal is for a separately pinned study session; focus following does not start it."
}

ChromeLearning_StudyHelp(*) {
    window := Gui("+Resize +MinSize600x380 +Owner" . MainGui.Hwnd,"How Study and Chrome learning connect")
    window.SetFont("s10","Segoe UI")
    helpText := window.Add("Edit","x16 y16 w720 h390 ReadOnly Multi VScroll", "STUDY LIBRARY`r`nImport PDFs, notes or selected browser evidence. Questions and versioned answers live in the shared memory. The answer engine first reuses an exact verified answer, then checks similar answers and local source passages. DeepSeek is an optional fallback, and generated answers remain candidates.`r`n`r`nLIVE PORTAL (the browser workflow)`r`nPin the specific Chrome window using the Live Portal picker or Ctrl+Shift+U. Start in observe/suggest mode. Focus and target checks guard the pinned window. Fill mode enters answers; submit mode additionally needs the explicit auto-submit setting. Chrome focus alone does not change these modes or start a session.`r`n`r`nCHROME LEARNING`r`nThis is the browser evidence workspace: distinguish windows, label profiles, capture visible pages and inspect their controls/text. It follows focus without activating Fan or capturing every page. Add only relevant observed text to Study; web browsing and searches are not automatically trusted knowledge.`r`n`r`nREVIEW / REUSE`r`nCheck cited source material, correct answers, verify them deliberately, then use spaced review or export. A screenshot, a repeated action and a model suggestion establish different things. Ctrl+Shift+Esc aborts live automation.")
    libraryButton := window.Add("Button","x16 y420 w150 h30","Study library")
    libraryButton.OnEvent("Click",(*)=>(window.Hide(),FanNav_Open(18)))
    portalButton := window.Add("Button","x180 y420 w150 h30","Live Portal")
    portalButton.OnEvent("Click",(*)=>(window.Hide(),FanNav_Open(19)))
    window.OnEvent("Size",(g,state,w,h)=>ChromeLearning_HelpLayout(helpText,[libraryButton,portalButton],w,h))
    window.Show("w752 h470")
}

ChromeLearning_HelpLayout(text, buttons, width, height) {
    text.Move(,,Max(500,width-32),Max(240,height-90))
    for button in buttons
        button.Move(,height-48)
}

ChromeLearning_OnExit(*) {
    SetTimer(ChromeLearning_Poll,0), SetTimer(ChromeLearning_PollJob,0)
    if g_ChromeLearn.Get("destroyHook",0)
        DllCall("UnhookWinEvent","Ptr",g_ChromeLearn["destroyHook"])
    if g_ChromeLearn.Get("destroyCallback",0)
        CallbackFree(g_ChromeLearn["destroyCallback"])
}
