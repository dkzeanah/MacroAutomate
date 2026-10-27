#Include %A_LineFile%\..\SecondaryWindows.ahk
#Include %A_LineFile%\..\LearningWorkbench.ahk
; Live evidence is rendered on a secondary display, without activating it.
global g_LearnView := Map(), g_LearnLastEvent := 0, g_LearnPreviewTick := 0
global g_LearnSourceTicks := Map()
global g_DiscoveryLastHwnd := 0, g_DiscoverySeen := Map(), g_DiscoveryBusy := false

LearningValidation_Monitor() {
    preferred := FanData_Config().Get("learning_monitor", 2)
    primary := MonitorGetPrimary(), count := MonitorGetCount()
    return LearningValidation_SelectMonitor(count, primary, preferred)
}

LearningValidation_SelectMonitor(count, primary, preferred := 2) {
    if IsNumber(preferred) && preferred > 1 && preferred <= count && preferred != primary
        return Integer(preferred)
    Loop count
        if A_Index > 1 && A_Index != primary
            return A_Index
    return 0
}

LearningValidation_PrimaryRegion(x, y, w, h) {
    for index in [1, MonitorGetPrimary()] {
        MonitorGet(index, &left, &top, &right, &bottom)
        if x < right && x+w > left && y < bottom && y+h > top
            return true
    }
    return false
}

LearningValidation_Show(*) {
    previousDpi := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try return LearningValidation_ShowPhysical()
    finally DllCall("SetThreadDpiAwarenessContext", "Ptr", previousDpi, "Ptr")
}

LearningValidation_ShowPhysical() {
    global g_LearnView
    monitor := LearningValidation_Monitor()
    if !monitor || !FanData_Config().Get("learning_validation", true) {
        if g_LearnView.Has("gui")
            g_LearnView["gui"].Hide()
        return false
    }
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    width := Min(700, right-left-24), height := Min(630, bottom-top-40)
    if width < 320 || height < 300
        return false
    if !g_LearnView.Has("gui") {
        view := Gui("+AlwaysOnTop +ToolWindow -DPIScale", "Learning validation")
        view.SetFont("s9", "Segoe UI")
        g_LearnView["gui"] := view
        g_LearnView["status"] := view.Add("Text", "x12 y10 w650 h38", "Waiting for learning evidence")
        g_LearnView["pic"] := view.Add("Picture", "x12 y58 w650 h300 Border")
        g_LearnView["edges"] := []
        Loop 4
            g_LearnView["edges"].Push(view.Add("Text", "x12 y58 w2 h2 Background22AA55"))
        g_LearnView["log"] := view.Add("ListView", "x12 y374 w650 h200", ["Time", "Learner", "Evidence", "Result"])
        g_LearnView["log"].ModifyCol(1, 70), g_LearnView["log"].ModifyCol(2, 115)
        g_LearnView["log"].ModifyCol(3, 90), g_LearnView["log"].ModifyCol(4, 360)
        g_LearnView["clock"] := view.Add("Text", "x12 y588 w490 h22")
        g_LearnView["workbench"] := view.Add("Button", "x510 y584 w150 h26", "Explain learning")
        g_LearnView["workbench"].OnEvent("Click", LearningLab_Open)
        view.OnEvent("Close", (*) => LearningValidation_SetEnabled(false))
        SetTimer(LearningValidation_Heartbeat, 1000)
    }
    picH := Max(100, height-310), logY := 70+picH, logH := Max(80, height-logY-42)
    g_LearnView["status"].Move(12, 10, width-24, 38)
    g_LearnView["pic"].Move(12, 58, width-24, picH)
    g_LearnView["log"].Move(12, logY, width-24, logH)
    g_LearnView["clock"].Move(12, height-28, width-190, 22)
    g_LearnView["workbench"].Move(width-170, height-32, 158, 26)
    g_LearnView["pw"] := width-24, g_LearnView["ph"] := picH
    g_LearnView["monitor"] := monitor
    if !g_LearnView.Get("placed",false) {
        SecondaryWindows_Place(g_LearnView["gui"], "NA x" . (right-width-12) . " y" . (top+12) . " w" . width . " h" . height)
        g_LearnView["placed"] := true
    } else
        g_LearnView["gui"].Show("NA")
    return true
}

LearningValidation_SetEnabled(enabled) {
    config := FanData_Config().Clone()
    config["learning_validation"] := !!enabled
    FanData_SaveConfig(config)
    LearningValidation_Show()
}

LearningValidation_Match(x, y, label := "Live pattern match") {
    LearningValidation_Event("Patterns", "verified", label, Map("x",x-10,"y",y-10,"w",20,"h",20))
}

LearningValidation_Event(source, evidence, message, region := "", hwnd := 0) {
    global g_LearnView, g_LearnLastEvent, g_LearnPreviewTick, g_LearnSourceTicks
    try {
        if source = "App Learner" || source = "Discovery" {
            context := LearningLab_Context(hwnd)
            LearningLab_Record(source, context.Get("exe", "unknown") . "|" . message, message, "observed", context,
                "A control was observed or stored; invocation and meaning have not been verified.", "LearningValidation event", "Review the saved locator in App Learner, then validate it in the intended application state.")
        }
        if evidence != "error" && g_LearnSourceTicks.Has(source) && A_TickCount-g_LearnSourceTicks[source] < 200
            return
        g_LearnSourceTicks[source] := A_TickCount
        if !LearningValidation_Show()
            return
        g_LearnLastEvent := A_TickCount
        color := evidence = "verified" ? "16883E" : evidence = "error" ? "CC3333" : "2679B8"
        g_LearnView["status"].Opt("c" . color)
        g_LearnView["status"].Value := source . " | " . evidence . "`n" . SubStr(message, 1, 160)
        lv := g_LearnView["log"]
        lv.Insert(1, , FormatTime(, "HH:mm:ss"), source, evidence, SubStr(message, 1, 240))
        if lv.GetCount() > 100
            lv.Delete(101)
        if region is Map && region.Count && A_TickCount-g_LearnPreviewTick >= 700 {
            g_LearnPreviewTick := A_TickCount
            LearningValidation_Preview(region, hwnd, color)
        }
    } catch as validationError {
        try TrackLogError("Learning validation", validationError)
    }
}

LearningValidation_Preview(region, hwnd, color) {
    previousDpi := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try LearningValidation_PreviewPhysical(region, hwnd, color)
    finally DllCall("SetThreadDpiAwarenessContext", "Ptr", previousDpi, "Ptr")
}

LearningValidation_PreviewPhysical(region, hwnd, color) {
    global g_LearnView
    x := region["x"], y := region["y"], w := region["w"], h := region["h"]
    if hwnd && WinExist("ahk_id " . hwnd)
        WinGetPos(&x, &y, &w, &h, "ahk_id " . hwnd)
    vx := SysGet(76), vy := SysGet(77), vr := vx+SysGet(78), vb := vy+SysGet(79)
    r := Min(vr, x+w), b := Min(vb, y+h), x := Max(vx, x), y := Max(vy, y)
    w := r-x, h := b-y
    if w <= 0 || h <= 0
        return
    scale := Min(g_LearnView["pw"]/w, g_LearnView["ph"]/h)
    dw := Max(1, Round(w*scale)), dh := Max(1, Round(h*scale))
    bitmap := Gdip_BitmapFromScreen(x . "|" . y . "|" . w . "|" . h)
    if !bitmap
        return
    try {
        DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", bitmap, "Ptr*", &hbm := 0, "UInt", 0xFFFFFFFF)
        if !hbm
            return
        try g_LearnView["pic"].Value := "*w" . dw . " *h" . dh . " HBITMAP:*" . hbm
        finally DllCall("DeleteObject", "Ptr", hbm)
    } finally Gdip_DisposeImage(bitmap)
    bx := 12+Max(0, Round((region["x"]-x)*scale)), by := 58+Max(0, Round((region["y"]-y)*scale))
    bw := Max(2, Min(dw-(bx-12), Round(region["w"]*scale)))
    bh := Max(2, Min(dh-(by-58), Round(region["h"]*scale)))
    edges := g_LearnView["edges"]
    for edge in edges
        edge.Opt("c" . color . " Background" . color)
    edges[1].Move(bx, by, bw, 2), edges[2].Move(bx, by+bh-2, bw, 2)
    edges[3].Move(bx, by, 2, bh), edges[4].Move(bx+bw-2, by, 2, bh)
}

LearningValidation_Heartbeat() {
    global g_LearnView, g_LearnLastEvent
    if !LearningValidation_Monitor() || !FanData_Config().Get("learning_validation", true) {
        if g_LearnView.Has("gui")
            g_LearnView["gui"].Hide()
        return
    }
    if g_LearnView.Has("gui") {
        WinGetPos(&x, &y, &w, &h, g_LearnView["gui"])
        ; Respect user placement. Only clamp when monitor topology changes.
        SecondaryWindows_Clamp(g_LearnView["gui"].Hwnd)
    }
    if g_LearnView.Has("clock")
        g_LearnView["clock"].Value := FormatTime(, "HH:mm:ss") . " | Last evidence "
            . (g_LearnLastEvent ? Round((A_TickCount-g_LearnLastEvent)/1000) . "s ago" : "pending")
}

AutoDiscovery_Start() {
    SetTimer(AutoDiscovery_Tick, FanData_Config().Get("auto_discovery", true) ? 4000 : 0)
}

AutoDiscovery_Schema() {
    TrackDB().Exec("CREATE TABLE IF NOT EXISTS discovered_target(id INTEGER PRIMARY KEY AUTOINCREMENT, app_key TEXT, title TEXT, topic TEXT, name TEXT, role TEXT, acc_path TEXT, x INTEGER,y INTEGER,w INTEGER,h INTEGER, rel_x REAL,rel_y REAL,rel_w REAL,rel_h REAL, shortcut TEXT, seen_count INTEGER DEFAULT 1, last_ts TEXT, UNIQUE(app_key,title,acc_path))")
}

AutoDiscovery_Tick() {
    global g_DiscoveryLastHwnd, g_DiscoverySeen, g_DiscoveryBusy
    if g_DiscoveryBusy || !FanData_Config().Get("auto_discovery", true) || A_TimeIdlePhysical < 800
        return
    if !TrackDB_Ready()
        return
    ctx := TrackGetActiveWindow()
    if !ctx["ok"] || ctx["pid"] = DllCall("GetCurrentProcessId", "UInt") || ctx["w"] <= 0 || ctx["h"] <= 0
        return
    if RegExMatch(ctx["title"], "i)password|sign.?in|log.?in|credential|private|incognito")
        return
    key := ctx["hwnd"] . "|" . ctx["title"]
    if g_DiscoverySeen.Has(key) && A_TickCount-g_DiscoverySeen[key] < 120000
        return
    g_DiscoveryBusy := true
    try {
        g_DiscoveryLastHwnd := ctx["hwnd"]
        db := TrackDB()
        AutoDiscovery_Schema()
        queue := [Map("el", Acc.ElementFromHandle(ctx["hwnd"]), "path", "", "depth", 0)]
        started := A_TickCount, scanned := 0, saved := 0
        url := ""
        try url := BrowserUrl_FromWindow(ctx["hwnd"], ctx["exe"])["url"]
        contextName := ctx["title"] . " " . ctx["exe"] . " " . url
        topic := RegExMatch(contextName, "i)claude") ? "Claude"
            : RegExMatch(contextName, "i)chatgpt|openai") ? "ChatGPT"
            : RegExMatch(ctx["title"] . " " . ctx["exe"], "i)code|studio|\.ahk|\.py|github|terminal|powershell") ? "Development" : "Workflow"
        while queue.Length && scanned < 180 && A_TickCount-started < 450 {
            item := queue.RemoveAt(1), el := item["el"], scanned++
            name := "", role := "", shortcut := ""
            try name := el.Name
            try role := el.RoleText
            try shortcut := el.KeyboardShortcut
            if item["path"] != "" && RegExMatch(role, "i)button|menu|edit|check|radio|combo|link|tab|cell|item") {
                try {
                    loc := el.Location
                    if loc.w > 0 && loc.h > 0 {
                        db.Run("INSERT INTO discovered_target(app_key,title,topic,name,role,acc_path,x,y,w,h,rel_x,rel_y,rel_w,rel_h,shortcut,last_ts) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(app_key,title,acc_path) DO UPDATE SET name=excluded.name,role=excluded.role,x=excluded.x,y=excluded.y,w=excluded.w,h=excluded.h,rel_x=excluded.rel_x,rel_y=excluded.rel_y,rel_w=excluded.rel_w,rel_h=excluded.rel_h,shortcut=excluded.shortcut,seen_count=seen_count+1,last_ts=excluded.last_ts",
                            TrackAppKey(ctx["exe"],ctx["class"]), ctx["title"],topic,SubStr(name,1,120),role,item["path"],loc.x,loc.y,loc.w,loc.h,
                            (loc.x-ctx["x"])/ctx["w"],(loc.y-ctx["y"])/ctx["h"],loc.w/ctx["w"],loc.h/ctx["h"],shortcut,TrackTS())
                        saved++
                        AutoDiscovery_SaveAppTarget(ctx, item["path"], name, role, shortcut, loc)
                        if saved = 1
                            LearningValidation_Event("Discovery", "observed", topic . ": " . name . " [" . role . "]", Map("x",loc.x,"y",loc.y,"w",loc.w,"h",loc.h),ctx["hwnd"])
                    }
                }
            }
            if item["depth"] < 8 {
                try {
                    for i, child in el.Children {
                        if queue.Length >= 180
                            break
                        queue.Push(Map("el",child,"path",item["path"] . (item["path"] = "" ? "" : ",") . i,"depth",item["depth"]+1))
                    }
                }
            }
        }
        g_DiscoverySeen[key] := A_TickCount
        if g_DiscoverySeen.Count > 300
            g_DiscoverySeen := Map(key, A_TickCount)
        LearningValidation_Event("Discovery", saved ? "stored" : "observed", topic . ": " . saved . " reusable controls saved; " . scanned . " nodes inspected")
    } catch as discoveryError {
        LearningValidation_Event("Discovery", "error", discoveryError.Message)
    } finally g_DiscoveryBusy := false
}

AutoDiscovery_SaveAppTarget(ctx, path, name, role, shortcut, loc) {
    db := AppMapDB()
    if !db
        return
    appId := db.Scalar("SELECT id FROM " . AppMap_AppTable() . " WHERE exe=? AND cls=? LIMIT 1", ctx["exe"], ctx["class"])
    if !appId {
        db.Run("INSERT INTO " . AppMap_AppTable() . "(name,exe,cls,title,win_x,win_y,win_w,win_h,learned_ts,notes) VALUES(?,?,?,?,?,?,?,?,?,?)",
            ctx["title"],ctx["exe"],ctx["class"],ctx["title"],ctx["x"],ctx["y"],ctx["w"],ctx["h"],TrackTS(),"Automatic passive discovery")
        appId := db.LastInsertId()
    }
    id := db.Scalar("SELECT id FROM ui_element WHERE app_id=? AND kind='auto-acc' AND acc_path=? AND source_title=? LIMIT 1", appId, path, ctx["title"])
    values := [SubStr(name,1,120),role,shortcut,loc.x,loc.y,loc.w,loc.h,
        (loc.x-ctx["x"])/ctx["w"],(loc.y-ctx["y"])/ctx["h"],loc.w/ctx["w"],loc.h/ctx["h"],ctx["title"]]
    if id {
        values.Push(id)
        db.Run("UPDATE ui_element SET name=?,role=?,shortcut=?,x=?,y=?,w=?,h=?,rel_x=?,rel_y=?,rel_w=?,rel_h=?,source_title=? WHERE id=?", values*)
    } else {
        values.Push(appId), values.Push(path)
        db.Run("INSERT INTO ui_element(name,role,shortcut,x,y,w,h,rel_x,rel_y,rel_w,rel_h,source_title,app_id,acc_path,kind) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,'auto-acc')", values*)
    }
}
