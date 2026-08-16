; ═══════════════════════════════════════════════════════════════════════════════
; TrackingDashboard.ahk - Coordinator + "Tracking" tab UI + detail panels
; ═══════════════════════════════════════════════════════════════════════════════
; One place to start/stop every tracker, see live status, and open the detail
; views (window times, mouse heat/trace, key history, snapshots, research).
;
; Settings persist to the tracking DB's meta table so they survive restarts
; independently of the app's INI files.
; ═══════════════════════════════════════════════════════════════════════════════

; ─── Master state ────────────────────────────────────────────────────────────
global g_TrackMasterOn := false
global g_TrackStatusTimer := false

; Tab control references (set by Track_BuildTab).
global g_TrkStatusDB := ""
global g_TrkStatusWin := ""
global g_TrkStatusMouse := ""
global g_TrkStatusKey := ""
global g_TrkStatusSnap := ""
global g_TrkStatsText := ""
global g_TrkCbWin := ""
global g_TrkCbMouse := ""
global g_TrkCbKey := ""
global g_TrkCbSnap := ""
global g_TrkCbOcr := ""

; ═══════════════════════════════════════════════════════════════════════════════
; INITIALISATION + PERSISTENCE
; ═══════════════════════════════════════════════════════════════════════════════

Track_InitAll() {
    global g_SnapDoOCR

    ok := TrackDB_Init()
    if ok {
        Snap_Init()
        ; Restore persisted preferences.
        g_SnapDoOCR := (TrackDB_MetaGet("opt_snap_ocr", "0") = "1")
        ; The key tracker keeps its never-record list in the same meta table.
        KeyTrack_LoadExclusions()
    }
    return ok
}

Track_SaveOptions() {
    global g_SnapDoOCR
    TrackDB_MetaSet("opt_snap_ocr", g_SnapDoOCR ? "1" : "0")
}

; Named handlers (a fat-arrow cannot declare `global`, so it would shadow the
; global instead of updating it - these must be real functions).
Track_SetSnapOcr(ctrl, *) {
    global g_SnapDoOCR
    g_SnapDoOCR := ctrl.Value
    Track_SaveOptions()
}

; Auto-start whichever trackers were running at last shutdown.
Track_AutoStart() {
    if !TrackDB_Ready()
        return
    if (TrackDB_MetaGet("run_win", "0") = "1")
        WinTrack_Start()
    if (TrackDB_MetaGet("run_mouse", "0") = "1")
        MouseTrack_Start()
    if (TrackDB_MetaGet("run_key", "0") = "1")
        KeyTrack_Start()
    if (TrackDB_MetaGet("run_snap", "0") = "1")
        Snap_Start()
    Track_SyncCheckboxes()
    Track_RefreshStatus()
}

Track_PersistRunState() {
    TrackDB_MetaSet("run_win", WinTrack_IsOn() ? "1" : "0")
    TrackDB_MetaSet("run_mouse", MouseTrack_IsOn() ? "1" : "0")
    TrackDB_MetaSet("run_key", KeyTrack_IsOn() ? "1" : "0")
    TrackDB_MetaSet("run_snap", Snap_IsOn() ? "1" : "0")
}

; ═══════════════════════════════════════════════════════════════════════════════
; MASTER CONTROL
; ═══════════════════════════════════════════════════════════════════════════════

Track_StartAll() {
    if !TrackDB_Ready() {
        if !Track_InitAll() {
            MsgBox("Tracking storage unavailable:`n`n" . g_TrackDBError
                 . "`n`nSee lib\TrackSQLite.ahk for how to supply sqlite3.dll."
                 , "Tracking", "Iconx")
            return false
        }
    }
    WinTrack_Start()
    MouseTrack_Start()
    KeyTrack_Start()
    Snap_Start()
    Track_PersistRunState()
    Track_SyncCheckboxes()
    Track_RefreshStatus()
    ShowStatus("All trackers started", "ok")
    return true
}

Track_StopAll() {
    WinTrack_Stop()
    MouseTrack_Stop()
    KeyTrack_Stop()
    Snap_Stop()
    Track_PersistRunState()
    Track_SyncCheckboxes()
    Track_RefreshStatus()
    ShowStatus("All trackers stopped", "ok")
}

; Called on app exit to flush open buckets/sessions.
Track_ShutdownAll() {
    try WinTrack_Stop()
    try MouseTrack_Stop()
    try KeyTrack_Stop()
    try Snap_Stop()
    try TrackDB_Close()
}

; ═══════════════════════════════════════════════════════════════════════════════
; TAB UI
; ═══════════════════════════════════════════════════════════════════════════════

; Build the Tracking tab. Call after TabCtrl.UseTab(<index>).
Track_BuildTab(g) {
    global g_TrkStatusDB, g_TrkStatusWin, g_TrkStatusMouse, g_TrkStatusKey, g_TrkStatusSnap
    global g_TrkStatsText, g_TrkCbWin, g_TrkCbMouse, g_TrkCbKey, g_TrkCbSnap, g_TrkCbOcr
    global g_SnapDoOCR, g_KeyMaskDigits

    ; ─── Master controls ─────────────────────────────────────────────────────
    g.Add("GroupBox", "x15 y50 w860 h74", "Behavior Tracking - Master Control")
    g.Add("Button", "x25 y72 w110 h40", "Start All").OnEvent("Click", (*) => Track_StartAll())
    g.Add("Button", "x140 y72 w110 h40", "Stop All").OnEvent("Click", (*) => Track_StopAll())

    g_TrkCbWin := g.Add("CheckBox", "x270 y70 w200", "Window time tracking")
    g_TrkCbWin.OnEvent("Click", Track_ToggleWin)
    g_TrkCbMouse := g.Add("CheckBox", "x270 y90 w200", "Mouse movement tracking")
    g_TrkCbMouse.OnEvent("Click", Track_ToggleMouse)
    g_TrkCbKey := g.Add("CheckBox", "x480 y70 w200", "Keystroke history")
    g_TrkCbKey.OnEvent("Click", Track_ToggleKey)
    g_TrkCbSnap := g.Add("CheckBox", "x480 y90 w220", "5-min window snapshots")
    g_TrkCbSnap.OnEvent("Click", Track_ToggleSnap)

    g_TrkCbOcr := g.Add("CheckBox", "x700 y70 w170" . (g_SnapDoOCR ? " Checked" : ""), "OCR on snapshot")
    g_TrkCbOcr.OnEvent("Click", Track_SetSnapOcr)
    ; Keystroke logging is sensitive - give the never-record list a front door.
    g.Add("Button", "x700 y90 w170 h24", "Key Privacy...").OnEvent("Click", (*) => Track_OpenKeyPrivacy())

    ; ─── Live status ─────────────────────────────────────────────────────────
    g.Add("GroupBox", "x15 y130 w860 h120", "Live Status")
    g_TrkStatusDB := g.Add("Text", "x25 y150 w840 cGray", "Database: ...")
    g_TrkStatusWin := g.Add("Text", "x25 y170 w840", "Window tracking: OFF")
    g_TrkStatusMouse := g.Add("Text", "x25 y190 w840", "Mouse tracking: OFF")
    g_TrkStatusKey := g.Add("Text", "x25 y210 w840", "Key tracking: OFF")
    g_TrkStatusSnap := g.Add("Text", "x25 y230 w840", "Snapshots: OFF")

    ; ─── Detail views ────────────────────────────────────────────────────────
    g.Add("GroupBox", "x15 y256 w860 h90", "Explore Tracked Data")
    g.Add("Button", "x25 y278 w160 h30", "Window Times").OnEvent("Click", (*) => Track_OpenWindowTimes())
    g.Add("Button", "x190 y278 w160 h30", "Mouse Heat / Trace").OnEvent("Click", (*) => Track_OpenMousePanel())
    g.Add("Button", "x355 y278 w160 h30", "Key History").OnEvent("Click", (*) => Track_OpenKeyHistory())
    g.Add("Button", "x520 y278 w160 h30", "Snapshot Viewer").OnEvent("Click", (*) => Snap_OpenViewer())
    g.Add("Button", "x685 y278 w180 h30", "Research Pipeline").OnEvent("Click", (*) => Track_OpenResearch())

    g.Add("Button", "x25 y312 w160 h26", "Snapshot Now").OnEvent("Click", (*) => Track_SnapNow())
    g.Add("Button", "x190 y312 w160 h26", "Elements Registry").OnEvent("Click", (*) => Track_OpenElements())
    g.Add("Button", "x355 y312 w160 h26", "Export All (JSON)").OnEvent("Click", (*) => Track_ExportAll())
    g.Add("Button", "x520 y312 w160 h26", "Prune Old Data").OnEvent("Click", (*) => Track_PrunePrompt())
    g.Add("Button", "x685 y312 w180 h26", "Open Data Folder").OnEvent("Click", (*) => Track_OpenDataFolder())

    ; ─── Stats ───────────────────────────────────────────────────────────────
    g.Add("GroupBox", "x15 y352 w860 h230", "Storage")
    g_TrkStatsText := g.Add("Edit", "x25 y372 w840 h200 ReadOnly -Wrap +VScroll")
    g_TrkStatsText.SetFont("s8", "Consolas")

    Track_SyncCheckboxes()
    Track_StartStatusTimer()
}

Track_StartStatusTimer() {
    global g_TrackStatusTimer
    if g_TrackStatusTimer
        return
    g_TrackStatusTimer := true
    SetTimer(Track_RefreshStatus, 1000)
    Track_RefreshStatus()
}

Track_SyncCheckboxes() {
    global g_TrkCbWin, g_TrkCbMouse, g_TrkCbKey, g_TrkCbSnap
    if IsObject(g_TrkCbWin)
        g_TrkCbWin.Value := WinTrack_IsOn()
    if IsObject(g_TrkCbMouse)
        g_TrkCbMouse.Value := MouseTrack_IsOn()
    if IsObject(g_TrkCbKey)
        g_TrkCbKey.Value := KeyTrack_IsOn()
    if IsObject(g_TrkCbSnap)
        g_TrkCbSnap.Value := Snap_IsOn()
}

Track_RefreshStatus() {
    global g_TrkStatusDB, g_TrkStatusWin, g_TrkStatusMouse, g_TrkStatusKey, g_TrkStatusSnap, g_TrkStatsText

    if !IsObject(g_TrkStatusDB)
        return

    if TrackDB_Ready() {
        db := TrackDB()
        sizeKB := Round(db.FileSize() / 1024, 1)
        g_TrkStatusDB.Value := "Database: " . TrackSQLite.LibInfo() . "  |  "
            . g_TrackDBPath . "  |  " . sizeKB . " KB"
    } else {
        g_TrkStatusDB.Value := "Database: UNAVAILABLE - " . g_TrackDBError
    }

    g_TrkStatusWin.Value := WinTrack_StatusLine() . "   (today: " . TrackFormatMs(WinTrack_TodayMs()) . ")"
    g_TrkStatusMouse.Value := MouseTrack_StatusLine()
    g_TrkStatusKey.Value := KeyTrack_StatusLine()
    g_TrkStatusSnap.Value := Snap_StatusLine()

    ; Stats panel (throttled to ~ every 5s to avoid constant COUNT queries).
    static lastStats := 0
    if (A_TickCount - lastStats > 5000) {
        lastStats := A_TickCount
        Track_UpdateStats()
    }
}

Track_UpdateStats() {
    global g_TrkStatsText
    if !IsObject(g_TrkStatsText) || !TrackDB_Ready()
        return
    stats := TrackDB_Stats()
    lines := ""
    labels := Map(
        "app", "Applications", "win", "Unique windows", "win_session", "Focus sessions",
        "mouse_snapshot", "Mouse snapshots (1-min)", "mouse_heat", "Heat cells",
        "mouse_feature", "Extracted features", "key_snapshot", "Key snapshots (1-min)",
        "hotkey_stat", "Hotkey combos", "clip_history", "Clipboard captures",
        "snap_cycle", "Snapshot cycles", "snap_entry", "Window snapshots",
        "element", "Named elements", "query", "Research queries",
        "query_link", "Result links", "query_insight", "Insights")
    order := ["app", "win", "win_session", "mouse_snapshot", "mouse_heat", "mouse_feature"
            , "key_snapshot", "hotkey_stat", "clip_history", "snap_cycle", "snap_entry"
            , "element", "query", "query_link", "query_insight"]
    for k in order {
        label := labels.Has(k) ? labels[k] : k
        val := stats.Has(k) ? stats[k] : 0
        lines .= Format("{:-28}", label) . " : " . val . "`n"
    }
    if (g_TrackErrorCount > 0)
        lines .= "`n" . g_TrackErrorCount . " tracker error(s) - see data\tracking_errors.log"
    g_TrkStatsText.Value := lines
}

; ─── Checkbox togglers ───────────────────────────────────────────────────────

Track_ToggleWin(c, *) {
    if c.Value
        WinTrack_Start()
    else
        WinTrack_Stop()
    Track_PersistRunState()
    Track_RefreshStatus()
}

Track_ToggleMouse(c, *) {
    if c.Value
        MouseTrack_Start()
    else
        MouseTrack_Stop()
    Track_PersistRunState()
    Track_RefreshStatus()
}

Track_ToggleKey(c, *) {
    if c.Value {
        if !KeyTrack_Start()
            c.Value := 0
    } else {
        KeyTrack_Stop()
    }
    Track_PersistRunState()
    Track_RefreshStatus()
}

Track_ToggleSnap(c, *) {
    if c.Value
        Snap_Start()
    else
        Snap_Stop()
    Track_PersistRunState()
    Track_RefreshStatus()
}

; ─── Tab buttons ─────────────────────────────────────────────────────────────

; ═══════════════════════════════════════════════════════════════════════════════
; KEY PRIVACY - manage the never-record window list
; ═══════════════════════════════════════════════════════════════════════════════
; Keystrokes are only recorded for windows that pass KeyTrack_IsExcluded(), which
; already blocks credential-looking window names automatically. This panel lets
; the user add their own never-record fragments on top of that.

global g_KpGui := "", g_KpLV := ""

Track_OpenKeyPrivacy() {
    global g_KpGui, g_KpLV

    if !TrackDB_Ready() {
        if !TrackDB_Init() {
            MsgBox("Tracking database unavailable.", "Key Privacy", "Iconx")
            return
        }
    }

    if IsObject(g_KpGui) {
        try {
            g_KpGui.Show()
            Track_KpRefresh()
            return
        }
    }

    g := Gui("+AlwaysOnTop", "Keystroke Privacy")
    g.SetFont("s9", "Segoe UI")
    g.OnEvent("Close", (*) => g.Hide())

    g.Add("Text", "x10 y10 w440 +Wrap"
        , "Keystrokes are NEVER recorded for a window whose name contains any "
        . "fragment below. Credential-style windows (password, sign in, "
        . "1Password, Bitwarden, KeePass, LastPass...) are already blocked "
        . "automatically.")

    g_KpLV := g.Add("ListView", "x10 y70 w440 h200 Grid -Multi", ["Never record windows containing"])
    g_KpLV.ModifyCol(1, 420)

    g.Add("Button", "x10 y280 w140 h28", "Add...").OnEvent("Click", (*) => Track_KpAdd())
    g.Add("Button", "x155 y280 w140 h28", "Remove Selected").OnEvent("Click", (*) => Track_KpRemove())
    g.Add("Button", "x310 y280 w140 h28", "Close").OnEvent("Click", (*) => g.Hide())

    g_KpGui := g
    g.Show("w465 h325")
    Track_KpRefresh()
}

Track_KpRefresh() {
    global g_KpLV
    if !IsObject(g_KpLV)
        return
    g_KpLV.Delete()
    for frag in KeyTrack_Exclusions()
        g_KpLV.Add(, frag)
}

Track_KpAdd() {
    res := InputBox("Never record keystrokes in windows whose name contains:"
                  , "Add Exclusion", "w400 h130")
    if (res.Result != "OK" || Trim(res.Value) = "")
        return
    KeyTrack_ExcludeWindow(Trim(res.Value))
    Track_KpRefresh()
    ShowStatus("Exclusion added", "ok")
}

Track_KpRemove() {
    global g_KpLV
    row := g_KpLV.GetNext()
    if !row {
        ShowStatus("Select an entry first", "fail")
        return
    }
    KeyTrack_UnexcludeWindow(g_KpLV.GetText(row, 1))
    Track_KpRefresh()
    ShowStatus("Exclusion removed", "ok")
}

Track_SnapNow() {
    id := Snap_RunCycleNow("manual")
    if id
        ShowStatus("Snapshot cycle #" . id . " started", "ok")
    else
        ShowStatus("Snapshot busy or nothing to capture", "fail")
}

Track_OpenElements() {
    Snap_OpenViewer()
    ; The viewer defaults to the Elements tab context per selected window.
}

Track_OpenDataFolder() {
    global DATA_DIR
    dir := DATA_DIR . "\tracking"
    if !DirExist(dir)
        dir := DATA_DIR
    try Run(dir)
}

Track_PrunePrompt() {
    res := InputBox("Delete tracking data older than how many days?", "Prune", "w300 h130", "30")
    if (res.Result != "OK")
        return
    days := IsInteger(res.Value) ? Integer(res.Value) : 30
    if (days < 1)
        days := 1
    out := TrackDB_Prune(days)
    try TrackDB().Vacuum()
    MsgBox("Pruned " . out["rows"] . " rows and " . out["files"] . " image files older than "
         . days . " days.", "Prune complete", "Iconi")
    Track_UpdateStats()
}

Track_ExportAll() {
    global DATA_DIR
    dir := DATA_DIR . "\tracking\export_" . FormatTime(A_Now, "yyyyMMdd_HHmmss")
    try DirCreate(dir)

    ; Window times.
    try WinTrack_ExportCsv(dir . "\window_times.csv", "all")
    ; Elements.
    try Element_ExportJson(dir . "\elements.json", 0)
    ; Per-window mouse features (top 30 windows by time).
    n := 0
    for w in TrackDB_TopWindows("all", 30) {
        try {
            MouseFeatures_Export(w["id"], dir . "\features_win" . w["id"] . ".json", "json")
            n++
        }
    }
    MsgBox("Exported to:`n" . dir, "Export complete", "Iconi")
    try Run(dir)
}

; ═══════════════════════════════════════════════════════════════════════════════
; DETAIL PANEL: WINDOW TIMES
; ═══════════════════════════════════════════════════════════════════════════════

global g_WtGui := "", g_WtLV := "", g_WtScope := "", g_WtWinIds := []

Track_OpenWindowTimes() {
    global g_WtGui, g_WtLV, g_WtScope
    if IsObject(g_WtGui) {
        try {
            g_WtGui.Show()
            Track_WtRefresh()
            return
        }
    }
    g := Gui("+Resize", "Window Time Tracking")
    g.SetFont("s9", "Segoe UI")
    g.OnEvent("Close", (*) => g.Hide())

    g.Add("Text", "x10 y12", "Scope:")
    g_WtScope := g.Add("DropDownList", "x60 y9 w120 Choose1", ["All time", "Today", "This week"])
    g_WtScope.OnEvent("Change", (*) => Track_WtRefresh())
    g.Add("Button", "x190 y8 w110 h24", "Refresh").OnEvent("Click", (*) => Track_WtRefresh())
    g.Add("Button", "x305 y8 w110 h24", "Export CSV").OnEvent("Click", (*) => Track_WtExport())
    g.Add("Button", "x420 y8 w150 h24", "Mouse Heat (sel)").OnEvent("Click", (*) => Track_WtMouse())
    g.Add("Button", "x575 y8 w150 h24", "Key History (sel)").OnEvent("Click", (*) => Track_WtKeys())

    g_WtLV := g.Add("ListView", "x10 y40 w800 h460 Grid", ["Window Name", "Application", "Total Time", "ms", "Activations", "Last Seen"])
    g_WtLV.ModifyCol(1, 300)
    g_WtLV.ModifyCol(2, 130)
    g_WtLV.ModifyCol(3, 90)
    g_WtLV.ModifyCol(4, 0)
    g_WtLV.ModifyCol(5, 75)
    g_WtLV.ModifyCol(6, 120)
    g_WtLV.OnEvent("DoubleClick", (*) => Track_WtMouse())

    g_WtGui := g
    g.Show("w820 h520")
    Track_WtRefresh()
}

Track_WtScopeKey() {
    global g_WtScope
    switch g_WtScope.Value {
        case 2: return "today"
        case 3: return "week"
        default: return "all"
    }
}

Track_WtRefresh() {
    global g_WtLV, g_WtWinIds
    if !IsObject(g_WtLV)
        return
    g_WtLV.Delete()
    g_WtWinIds := []
    for r in TrackDB_TopWindows(Track_WtScopeKey(), 1000) {
        g_WtLV.Add(, r["name"], r["app"], TrackFormatMs(r["total_ms"]), r["total_ms"]
                 , r["activations"], r["last_seen"])
        g_WtWinIds.Push(r["id"])
    }
}

Track_WtSelectedWinId() {
    global g_WtLV, g_WtWinIds
    row := g_WtLV.GetNext()
    if (!row || row > g_WtWinIds.Length)
        return 0
    return g_WtWinIds[row]
}

Track_WtExport() {
    global DATA_DIR
    path := DATA_DIR . "\tracking\window_times_" . Track_WtScopeKey() . ".csv"
    WinTrack_ExportCsv(path, Track_WtScopeKey())
    ShowStatus("Exported to " . path, "ok")
    try Run(path)
}

Track_WtMouse() {
    id := Track_WtSelectedWinId()
    if id
        Track_OpenMousePanel(id)
    else
        ShowStatus("Select a window first", "fail")
}

Track_WtKeys() {
    id := Track_WtSelectedWinId()
    if id
        Track_OpenKeyHistory(id)
    else
        ShowStatus("Select a window first", "fail")
}

; ═══════════════════════════════════════════════════════════════════════════════
; DETAIL PANEL: MOUSE HEAT / TRACE / FEATURES
; ═══════════════════════════════════════════════════════════════════════════════

global g_MpGui := "", g_MpWinDD := "", g_MpPic := "", g_MpSnapLV := ""
global g_MpMetric := "", g_MpInfo := "", g_MpWinIds := [], g_MpFmtDD := ""
global g_MpTmpImg := "", g_MpSnapIds := []

Track_OpenMousePanel(winId := 0) {
    global g_MpGui, g_MpWinDD, g_MpPic, g_MpSnapLV, g_MpMetric, g_MpInfo, g_MpWinIds
    global g_MpFmtDD, g_MpTmpImg, DATA_DIR

    g_MpTmpImg := DATA_DIR . "\tracking\_mouse_panel.png"

    if IsObject(g_MpGui) {
        try {
            g_MpGui.Show()
            Track_MpLoadWindows(winId)
            return
        }
    }

    g := Gui("+Resize", "Mouse Tracking - Heat / Trace / Features")
    g.SetFont("s9", "Segoe UI")
    g.OnEvent("Close", (*) => g.Hide())

    g.Add("Text", "x10 y12", "Window:")
    g_MpWinDD := g.Add("DropDownList", "x65 y9 w360", [])
    g_MpWinDD.OnEvent("Change", (*) => Track_MpOnWindow())

    g.Add("Text", "x435 y12", "View:")
    g_MpMetric := g.Add("DropDownList", "x475 y9 w150 Choose1"
                      , ["Heat: hover", "Heat: clicks", "Heat: dwell", "Features"])
    g_MpMetric.OnEvent("Change", (*) => Track_MpRender())
    g.Add("Button", "x635 y8 w150 h24", "Extract Features").OnEvent("Click", (*) => Track_MpExtract())

    g_MpInfo := g.Add("Text", "x10 y38 w780 cGray", "")

    ; Left: rendered image. Right: snapshot list for trace/replay.
    g_MpPic := g.Add("Picture", "x10 y58 w560 h440 Border")

    g.Add("Text", "x580 y58", "1-minute snapshots:")
    g_MpSnapLV := g.Add("ListView", "x580 y78 w290 h300 Grid", ["Minute", "Pts", "Clicks"])
    g_MpSnapLV.ModifyCol(1, 130)
    g_MpSnapLV.ModifyCol(2, 60)
    g_MpSnapLV.ModifyCol(3, 60)
    g_MpSnapLV.OnEvent("DoubleClick", (*) => Track_MpTrace())

    g.Add("Button", "x580 y384 w140 h26", "Show Trace").OnEvent("Click", (*) => Track_MpTrace())
    g.Add("Button", "x725 y384 w145 h26", "Replay Movement").OnEvent("Click", (*) => Track_MpReplay())

    g.Add("Text", "x580 y418", "Export features as:")
    g_MpFmtDD := g.Add("DropDownList", "x580 y438 w150 Choose1"
                     , ["json", "csv", "python", "javascript", "ahk"])
    g.Add("Button", "x735 y437 w135 h24", "Export").OnEvent("Click", (*) => Track_MpExport())

    g_MpGui := g
    g.Show("w880 h520")
    Track_MpLoadWindows(winId)
}

Track_MpLoadWindows(winId := 0) {
    global g_MpWinDD, g_MpWinIds
    items := []
    g_MpWinIds := []
    sel := 1
    for w in TrackDB_TopWindows("all", 500) {
        items.Push(TrackEllipsis(w["name"], 55) . "  [" . w["app"] . "]")
        g_MpWinIds.Push(w["id"])
        if (w["id"] = winId)
            sel := g_MpWinIds.Length
    }
    g_MpWinDD.Delete()
    if items.Length {
        g_MpWinDD.Add(items)
        g_MpWinDD.Choose(sel)
    }
    Track_MpOnWindow()
}

Track_MpSelectedWinId() {
    global g_MpWinDD, g_MpWinIds
    idx := g_MpWinDD.Value
    if (idx < 1 || idx > g_MpWinIds.Length)
        return 0
    return g_MpWinIds[idx]
}

Track_MpOnWindow() {
    global g_MpSnapLV, g_MpSnapIds
    winId := Track_MpSelectedWinId()
    ; Snapshot list
    g_MpSnapLV.Delete()
    g_MpSnapIds := []
    if winId {
        for s in MouseTrack_Snapshots(winId, 500) {
            mk := s["minute_key"]
            pretty := SubStr(mk, 1, 4) . "-" . SubStr(mk, 5, 2) . "-" . SubStr(mk, 7, 2)
                    . " " . SubStr(mk, 9, 2) . ":" . SubStr(mk, 11, 2)
            g_MpSnapLV.Add(, pretty, s["samples"], s["click_count"])
            g_MpSnapIds.Push(s["id"])
        }
    }
    Track_MpRender()
}

Track_MpRender() {
    global g_MpPic, g_MpMetric, g_MpInfo, g_MpTmpImg
    winId := Track_MpSelectedWinId()
    if !winId {
        g_MpPic.Value := ""
        g_MpInfo.Value := "No window selected."
        return
    }

    path := ""
    switch g_MpMetric.Value {
        case 1: path := MouseTrack_RenderHeatmap(winId, g_MpTmpImg, "hits", 550)
        case 2: path := MouseTrack_RenderHeatmap(winId, g_MpTmpImg, "clicks", 550)
        case 3: path := MouseTrack_RenderHeatmap(winId, g_MpTmpImg, "dwell_ms", 550)
        case 4: path := MouseTrack_RenderFeatures(winId, g_MpTmpImg, 550)
    }

    if (path != "" && FileExist(path))
        g_MpPic.Value := "*w550 *h430 " . path
    else
        g_MpPic.Value := ""

    size := MouseTrack_WindowSize(winId)
    feats := MouseTrack_Features(winId)
    g_MpInfo.Value := "Window size ~" . size["w"] . "x" . size["h"]
        . "  |  " . feats.Length . " extracted features"
        . (path = "" ? "   (no data yet - move the mouse over this window while tracking)" : "")
}

Track_MpExtract() {
    winId := Track_MpSelectedWinId()
    if !winId {
        ShowStatus("Select a window first", "fail")
        return
    }
    feats := MouseTrack_ExtractFeatures(winId)
    ShowStatus("Extracted " . feats.Length . " features", "ok")
    global g_MpMetric
    g_MpMetric.Choose(4)
    Track_MpRender()
}

Track_MpSelectedSnapId() {
    global g_MpSnapLV, g_MpSnapIds
    row := g_MpSnapLV.GetNext()
    if (!row || row > g_MpSnapIds.Length)
        return 0
    return g_MpSnapIds[row]
}

Track_MpTrace() {
    global g_MpPic, g_MpTmpImg
    snapId := Track_MpSelectedSnapId()
    if !snapId {
        ShowStatus("Select a snapshot first", "fail")
        return
    }
    path := MouseTrack_RenderTrace(snapId, g_MpTmpImg, 550)
    if (path != "" && FileExist(path))
        g_MpPic.Value := "*w550 *h430 " . path
    else
        ShowStatus("No path in that snapshot", "fail")
}

Track_MpReplay() {
    snapId := Track_MpSelectedSnapId()
    if !snapId {
        ShowStatus("Select a snapshot first", "fail")
        return
    }
    res := MsgBox("Replay the recorded mouse movement now?`n`n"
        . "The pointer will move on screen. Press ESC to abort.`n`n"
        . "Include recorded clicks?", "Replay Movement", "YesNoCancel Icon?")
    if (res = "Cancel")
        return
    doClicks := (res = "Yes")
    ShowStatus("Replaying in 2s - switch to the target window...", "wait")
    Sleep(2000)
    n := MouseTrack_Replay(snapId, 1.0, 0, doClicks)
    ShowStatus("Replayed " . n . " points", "ok")
}

Track_MpExport() {
    global g_MpFmtDD, DATA_DIR
    winId := Track_MpSelectedWinId()
    if !winId {
        ShowStatus("Select a window first", "fail")
        return
    }
    fmt := g_MpFmtDD.Text
    ext := (fmt = "python") ? "py" : (fmt = "javascript") ? "js" : (fmt = "ahk") ? "ahk" : fmt
    path := DATA_DIR . "\tracking\features_win" . winId . "." . ext
    n := MouseFeatures_Export(winId, path, fmt)
    ShowStatus("Exported " . n . " features to " . path, "ok")
    try Run(path)
}

; ═══════════════════════════════════════════════════════════════════════════════
; DETAIL PANEL: KEY HISTORY
; ═══════════════════════════════════════════════════════════════════════════════

global g_KhGui := "", g_KhWinDD := "", g_KhLV := "", g_KhTabs := ""
global g_KhWinIds := [], g_KhEdits := Map(), g_KhSnapIds := []

Track_OpenKeyHistory(winId := 0) {
    global g_KhGui, g_KhWinDD, g_KhLV, g_KhTabs, g_KhWinIds, g_KhEdits

    if IsObject(g_KhGui) {
        try {
            g_KhGui.Show()
            Track_KhLoadWindows(winId)
            return
        }
    }

    g := Gui("+Resize", "Keystroke History")
    g.SetFont("s9", "Segoe UI")
    g.OnEvent("Close", (*) => g.Hide())

    g.Add("Text", "x10 y12", "Window:")
    g_KhWinDD := g.Add("DropDownList", "x65 y9 w360", [])
    g_KhWinDD.OnEvent("Change", (*) => Track_KhOnWindow())
    g.Add("Button", "x435 y8 w120 h24", "Top Hotkeys").OnEvent("Click", (*) => Track_KhHotkeys())
    g.Add("Button", "x560 y8 w120 h24", "Clipboard Log").OnEvent("Click", (*) => Track_KhClips())

    g_KhLV := g.Add("ListView", "x10 y40 w300 h500 Grid", ["Minute", "Keys", "WPM"])
    g_KhLV.ModifyCol(1, 150)
    g_KhLV.ModifyCol(2, 70)
    g_KhLV.ModifyCol(3, 60)
    g_KhLV.OnEvent("ItemSelect", Track_KhOnSnap)

    g_KhTabs := g.Add("Tab3", "x320 y40 w560 h500"
                    , ["Text Typed", "Hotkeys", "Strings", "Sentences", "Code", "Clipboard", "Raw"])
    keys := ["text", "hotkeys", "strings", "sentences", "code", "clips", "raw"]
    idx := 1
    for k in keys {
        g_KhTabs.UseTab(idx)
        ed := g.Add("Edit", "x330 y70 w540 h460 ReadOnly +Wrap VScroll")
        if (k = "raw" || k = "code")
            ed.SetFont("s8", "Consolas")
        g_KhEdits[k] := ed
        idx++
    }
    g_KhTabs.UseTab()

    g_KhGui := g
    g.Show("w890 h560")
    Track_KhLoadWindows(winId)
}

Track_KhLoadWindows(winId := 0) {
    global g_KhWinDD, g_KhWinIds
    items := ["(all windows)"]
    g_KhWinIds := [0]
    sel := 1
    for w in TrackDB_TopWindows("all", 500) {
        items.Push(TrackEllipsis(w["name"], 55) . "  [" . w["app"] . "]")
        g_KhWinIds.Push(w["id"])
        if (w["id"] = winId)
            sel := g_KhWinIds.Length
    }
    g_KhWinDD.Delete()
    g_KhWinDD.Add(items)
    g_KhWinDD.Choose(sel)
    Track_KhOnWindow()
}

Track_KhSelectedWinId() {
    global g_KhWinDD, g_KhWinIds
    idx := g_KhWinDD.Value
    if (idx < 1 || idx > g_KhWinIds.Length)
        return 0
    return g_KhWinIds[idx]
}

Track_KhOnWindow() {
    global g_KhLV, g_KhSnapIds
    winId := Track_KhSelectedWinId()
    g_KhLV.Delete()
    g_KhSnapIds := []
    for s in KeyTrack_Snapshots(winId, 1000) {
        mk := s["minute_key"]
        pretty := SubStr(mk, 5, 2) . "-" . SubStr(mk, 7, 2) . " " . SubStr(mk, 9, 2) . ":" . SubStr(mk, 11, 2)
        g_KhLV.Add(, pretty, s["keystrokes"], Round(s["wpm"], 0))
        g_KhSnapIds.Push(s["id"])
    }
    Track_KhClearEdits()
}

Track_KhClearEdits() {
    global g_KhEdits
    for k, ed in g_KhEdits
        ed.Value := ""
}

Track_KhOnSnap(lv, item, selected) {
    global g_KhEdits, g_KhSnapIds
    if !selected
        return
    if (item < 1 || item > g_KhSnapIds.Length)
        return
    snapId := g_KhSnapIds[item]
    db := TrackDB()
    s := db.QueryRow("SELECT * FROM key_snapshot WHERE id=?", snapId)
    if !s.Count
        return
    g_KhEdits["text"].Value := s["text_typed"]
    g_KhEdits["hotkeys"].Value := s["hotkeys"]
    g_KhEdits["strings"].Value := s["strings"]
    g_KhEdits["sentences"].Value := s["sentences"]
    g_KhEdits["code"].Value := s["code_snips"]
    g_KhEdits["clips"].Value := s["clips"]
    g_KhEdits["raw"].Value := s["raw_stream"]
}

Track_KhHotkeys() {
    winId := Track_KhSelectedWinId()
    rows := KeyTrack_TopHotkeys(winId, 200)
    out := "Combo`tCount`tLast`n"
    for r in rows
        out .= r["combo"] . "`t" . r["count"] . "`t" . r["last_ts"] . "`n"
    Track_ShowTextPopup("Top Hotkeys", out)
}

Track_KhClips() {
    winId := Track_KhSelectedWinId()
    rows := KeyTrack_RecentClips(300, winId)
    out := ""
    for r in rows
        out .= "[" . r["ts"] . "] (" . r["kind"] . ", " . r["length"] . ") "
             . TrackEllipsis(r["content"], 120) . "`n"
    Track_ShowTextPopup("Clipboard History", out)
}

; ═══════════════════════════════════════════════════════════════════════════════
; DETAIL PANEL: RESEARCH PIPELINE
; ═══════════════════════════════════════════════════════════════════════════════

global g_RpGui := "", g_RpLV := "", g_RpLinkLV := "", g_RpInsEdit := "", g_RpQueryIds := [], g_RpLinkIds := []

Track_OpenResearch() {
    global g_RpGui, g_RpLV, g_RpLinkLV, g_RpInsEdit

    if IsObject(g_RpGui) {
        try {
            g_RpGui.Show()
            Track_RpRefresh()
            return
        }
    }

    g := Gui("+Resize", "Research Pipeline - Query / Links / Insights")
    g.SetFont("s9", "Segoe UI")
    g.OnEvent("Close", (*) => g.Hide())

    g.Add("Button", "x10 y8 w110 h26", "New Query").OnEvent("Click", (*) => Track_RpNewQuery())
    g.Add("Button", "x125 y8 w130 h26", "Capture Links (OCR)").OnEvent("Click", (*) => Track_RpCaptureScreen())
    g.Add("Button", "x260 y8 w130 h26", "Capture Links (Clip)").OnEvent("Click", (*) => Track_RpCaptureClip())
    g.Add("Button", "x395 y8 w110 h26", "Launch Next").OnEvent("Click", (*) => Track_RpLaunchNext())
    g.Add("Button", "x510 y8 w110 h26", "Add Insight").OnEvent("Click", (*) => Track_RpAddInsight())
    g.Add("Button", "x625 y8 w90 h26", "Report").OnEvent("Click", (*) => Track_RpReport())
    g.Add("Button", "x720 y8 w90 h26", "Refresh").OnEvent("Click", (*) => Track_RpRefresh())

    g.Add("Text", "x10 y42", "Queries:")
    g_RpLV := g.Add("ListView", "x10 y60 w350 h250 Grid", ["#", "Query", "Links", "Insights", "Status"])
    g_RpLV.ModifyCol(1, 30)
    g_RpLV.ModifyCol(2, 175)
    g_RpLV.ModifyCol(3, 40)
    g_RpLV.ModifyCol(4, 50)
    g_RpLV.ModifyCol(5, 55)
    g_RpLV.OnEvent("ItemSelect", Track_RpOnQuery)

    g.Add("Text", "x370 y42", "Result links:")
    g_RpLinkLV := g.Add("ListView", "x370 y60 w450 h250 Grid", ["#", "URL", "Status"])
    g_RpLinkLV.ModifyCol(1, 30)
    g_RpLinkLV.ModifyCol(2, 350)
    g_RpLinkLV.ModifyCol(3, 60)
    g_RpLinkLV.OnEvent("DoubleClick", (*) => Track_RpOpenLink())

    g.Add("Text", "x10 y318", "Insights (key takeaways) for the selected query:")
    g_RpInsEdit := g.Add("Edit", "x10 y338 w810 h200 ReadOnly +Wrap VScroll")

    g_RpGui := g
    g.Show("w835 h560")
    Track_RpRefresh()
}

Track_RpRefresh() {
    global g_RpLV, g_RpQueryIds
    if !IsObject(g_RpLV)
        return
    g_RpLV.Delete()
    g_RpQueryIds := []
    for q in Research_RecentQueries(300) {
        g_RpLV.Add(, q["id"], TrackEllipsis(q["text"], 40), q["links"], q["insights"], q["status"])
        g_RpQueryIds.Push(q["id"])
    }
}

Track_RpSelectedQueryId() {
    global g_RpLV, g_RpQueryIds
    row := g_RpLV.GetNext()
    if (!row || row > g_RpQueryIds.Length)
        return 0
    return g_RpQueryIds[row]
}

Track_RpOnQuery(lv, item, selected) {
    global g_RpLinkLV, g_RpInsEdit, g_ResQueryId, g_RpQueryIds, g_RpLinkIds
    if !selected
        return
    if (item < 1 || item > g_RpQueryIds.Length)
        return
    qid := g_RpQueryIds[item]
    g_ResQueryId := qid   ; make it the current context

    ; Links
    g_RpLinkLV.Delete()
    g_RpLinkIds := []
    for l in Research_Links(qid) {
        g_RpLinkLV.Add(, l["rank"], TrackEllipsis(l["url"], 70), l["status"])
        g_RpLinkIds.Push(l["id"])
    }

    ; Insights
    g_RpInsEdit.Value := Research_Report(qid)
}

Track_RpNewQuery() {
    res := InputBox("Enter a search query. It will be stored and opened in the browser.", "New Query", "w420 h130")
    if (res.Result != "OK" || Trim(res.Value) = "")
        return
    Research_Search(res.Value)
    Track_RpRefresh()
}

Track_RpCaptureScreen() {
    qid := Track_RpSelectedQueryId()
    if !qid {
        ShowStatus("Select a query first", "fail")
        return
    }
    n := Research_CaptureLinksFromScreen(qid)
    ShowStatus("Captured " . n . " links from screen", "ok")
    Track_RpRefresh()
    Track_RpReselect(qid)
}

Track_RpCaptureClip() {
    qid := Track_RpSelectedQueryId()
    if !qid {
        ShowStatus("Select a query first", "fail")
        return
    }
    n := Research_CaptureLinksFromClipboard(qid)
    ShowStatus("Captured " . n . " links from clipboard", "ok")
    Track_RpRefresh()
    Track_RpReselect(qid)
}

Track_RpLaunchNext() {
    qid := Track_RpSelectedQueryId()
    if !qid {
        ShowStatus("Select a query first", "fail")
        return
    }
    id := Research_LaunchNext(qid)
    if !id
        ShowStatus("No pending links", "wait")
    Track_RpReselect(qid)
}

Track_RpAddInsight() {
    qid := Track_RpSelectedQueryId()
    if !qid {
        ShowStatus("Select a query first", "fail")
        return
    }
    res := InputBox("Enter the key takeaway / insight from the current page:", "Add Insight", "w440 h150")
    if (res.Result != "OK" || Trim(res.Value) = "")
        return
    Research_AddInsight(res.Value, qid)
    Track_RpRefresh()
    Track_RpReselect(qid)
}

Track_RpReport() {
    qid := Track_RpSelectedQueryId()
    if !qid {
        ShowStatus("Select a query first", "fail")
        return
    }
    Track_ShowTextPopup("Research Report - Query #" . qid, Research_Report(qid))
}

Track_RpOpenLink() {
    global g_RpLinkLV, g_RpLinkIds
    row := g_RpLinkLV.GetNext()
    if (!row || row > g_RpLinkIds.Length)
        return
    db := TrackDB()
    l := db.QueryRow("SELECT * FROM query_link WHERE id=?", g_RpLinkIds[row])
    if l.Count
        Research_OpenUrl(l["url"])
}

Track_RpReselect(qid) {
    global g_RpLV, g_RpQueryIds
    Loop g_RpQueryIds.Length {
        if (g_RpQueryIds[A_Index] = qid) {
            g_RpLV.Modify(A_Index, "Select Focus")
            Track_RpOnQuery(g_RpLV, A_Index, true)
            return
        }
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; SHARED: SIMPLE TEXT POPUP
; ═══════════════════════════════════════════════════════════════════════════════

Track_ShowTextPopup(title, text) {
    g := Gui("+Resize +AlwaysOnTop", title)
    g.SetFont("s9", "Consolas")
    ed := g.Add("Edit", "x10 y10 w600 h400 ReadOnly +Wrap VScroll", text)
    g.Add("Button", "x10 y418 w100 h26", "Copy").OnEvent("Click", (*) => (A_Clipboard := text, ShowStatus("Copied", "ok")))
    g.Add("Button", "x115 y418 w100 h26", "Close").OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    g.Show("w620 h455")
}
