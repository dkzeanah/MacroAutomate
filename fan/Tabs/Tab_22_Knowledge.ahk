; ===============================================================================
; Tabs\Tab_22_Knowledge.ahk
; TAB 22 Knowledge: live "accumulated knowledge" dashboard with on-screen
; playback. UI + handlers here; data/logic in lib\KnowledgeDash.ahk. Reads the
; one unified database: window/element discoveries, written/versioned AHK tools,
; DAA planner chains, the pre-knowledge/learning layer, usage patterns, study
; Q&A, media jobs and env feature maps.
; ===============================================================================

global g_KnowCtl := Map()
global g_KnowRows := []
global g_KnowCurKey := ""
global g_KnowLiveOn := false
global g_KnowTabIndex := 22

Tab_Knowledge_Build() {
    global g_KnowTabIndex
    g_KnowTabIndex := 22
    TabCtrl.UseTab(g_KnowTabIndex)
    try Know_BuildTab(MainGui)
    catch as err
        LogErrorToFile(err, "caught", "Knowledge tab construction")
}

Know_BuildTab(g) {
    global g_KnowCtl
    g.Add("Text", "x15 y50 w260 h22 +0x200", "Accumulated Knowledge  (live)").SetFont("s11 bold")
    g_KnowCtl["live"] := g.Add("CheckBox", "x290 y52 w120", "Auto-refresh")
    g_KnowCtl["refresh"] := g.Add("Button", "x414 y48 w90 h24", "Refresh")
    g_KnowCtl["export"] := g.Add("Button", "x508 y48 w150 h24", "Export snapshot")
    g_KnowCtl["total"] := g.Add("Text", "x664 y52 w210 h20 cGray", "")

    g.Add("Text", "x15 y80 w420", "Knowledge categories (select to drill in)")
    g_KnowCtl["score"] := g.Add("ListView", "x15 y100 w420 h280 Grid -Multi"
        , ["Group", "Category", "Count", "Last"])
    g_KnowCtl["score"].ModifyCol(1, 150)
    g_KnowCtl["score"].ModifyCol(2, 130)
    g_KnowCtl["score"].ModifyCol(3, 55)
    g_KnowCtl["score"].ModifyCol(4, 120)

    g.Add("Text", "x445 y80 w430", "Items (select to view / flash on screen)")
    g_KnowCtl["detail"] := g.Add("ListView", "x445 y100 w430 h280 Grid -Multi"
        , ["Item", "Detail", "When"])
    g_KnowCtl["detail"].ModifyCol(1, 200)
    g_KnowCtl["detail"].ModifyCol(2, 150)
    g_KnowCtl["detail"].ModifyCol(3, 110)

    g_KnowCtl["flash"] := g.Add("Button", "x445 y384 w160 h26", "Flash on screen (playback)")
    g_KnowCtl["playstatus"] := g.Add("Text", "x612 y388 w263 h20 cGray", "")

    ; "Big picture" utility actions - not counts: see real records, validate
    ; live, and get DeepSeek to turn the knowledge into next actions.
    g_KnowCtl["sample"] := g.Add("Button", "x15 y414 w140 h26", "Sample records")
    g_KnowCtl["validate"] := g.Add("Button", "x160 y414 w150 h26", "Bulk live-validate")
    g_KnowCtl["insights"] := g.Add("Button", "x315 y414 w160 h26", "DeepSeek insights")
    g_KnowCtl["bigstatus"] := g.Add("Text", "x485 y418 w390 h20 cGray", "")

    g_KnowCtl["viewer"] := g.Add("Edit", "x15 y446 w860 h238 ReadOnly Multi VScroll")
    g_KnowCtl["viewer"].SetFont("s9", "Consolas")

    g_KnowCtl["refresh"].OnEvent("Click", (*) => Know_UiRefresh())
    g_KnowCtl["export"].OnEvent("Click", (*) => Know_UiExport())
    g_KnowCtl["live"].OnEvent("Click", (c, *) => Know_UiToggleLive(c.Value))
    g_KnowCtl["score"].OnEvent("ItemSelect", (lv, r, sel) => (sel ? Know_UiScoreSelect() : 0))
    g_KnowCtl["detail"].OnEvent("ItemSelect", (lv, r, sel) => (sel ? Know_UiDetailSelect() : 0))
    g_KnowCtl["flash"].OnEvent("Click", (*) => Know_UiFlash())
    g_KnowCtl["sample"].OnEvent("Click", (*) => Know_UiSample())
    g_KnowCtl["validate"].OnEvent("Click", (*) => Know_UiValidate())
    g_KnowCtl["insights"].OnEvent("Click", (*) => Know_UiInsights())

    Know_UiRefresh()
}

; Show a randomized sample of real records (not counts) in the detail list.
Know_UiSample() {
    global g_KnowCtl, g_KnowRows, g_KnowCurKey
    g_KnowCurKey := "sample"
    g_KnowRows := Know_SampleRecords(40)
    lv := g_KnowCtl["detail"]
    lv.Opt("-Redraw"), lv.Delete()
    for , r in g_KnowRows
        lv.Add(, r["label"], r["detail"], SubStr(r["when"], 1, 16))
    lv.Opt("+Redraw")
    try g_KnowCtl["bigstatus"].Value := "Random sample of " . g_KnowRows.Length
        . " real records - select one to view / flash"
    try g_KnowCtl["viewer"].Value := "A randomized cross-section of what the system has actually captured.`r`n"
        . "Spatial items flash on screen when selected."
}

; Bulk live validation with a score.
Know_UiValidate() {
    global g_KnowCtl, g_KnowRows, g_KnowCurKey
    try g_KnowCtl["bigstatus"].Value := "Validating remembered targets against live windows..."
    res := Know_BulkValidate(40)
    g_KnowCurKey := "validate"
    g_KnowRows := res["rows"]
    lv := g_KnowCtl["detail"]
    lv.Opt("-Redraw"), lv.Delete()
    for , r in g_KnowRows
        lv.Add(, r["label"], r["detail"], "")
    lv.Opt("+Redraw")
    try g_KnowCtl["bigstatus"].Value := "Validation score " . res["score"] . "%  ("
        . res["passed"] . "/" . res["total"] . " still valid) - logged for ranking"
    try g_KnowCtl["viewer"].Value := "Bulk live-validation: sampled " . res["total"]
        . " remembered spatial targets and checked each against live windows + screen bounds.`r`n"
        . "Passed: " . res["passed"] . "   Score: " . res["score"] . "%`r`n`r`n"
        . "Select a row to flash where that target was remembered."
}

; DeepSeek insights over the accumulated knowledge (off the click thread).
Know_UiInsights() {
    global g_KnowCtl
    try g_KnowCtl["bigstatus"].Value := "Asking DeepSeek for insights over your knowledge..."
    try g_KnowCtl["viewer"].Value := "Contacting DeepSeek..."
    SetTimer(() => Know_UiInsightsWork(), -30)
}

Know_UiInsightsWork() {
    global g_KnowCtl
    res := Know_InsightsDeepSeek()
    if !res["ok"] {
        try g_KnowCtl["bigstatus"].Value := "Insights: " . res["error"]
        try g_KnowCtl["viewer"].Value := res["error"]
        return
    }
    try g_KnowCtl["bigstatus"].Value := "DeepSeek insights ready (est $" . Round(res["cost"], 4) . ")"
    try g_KnowCtl["viewer"].Value := res["text"]
}

; ─────────────────────────────────────────────────────────────────────────────
Know_UiRefresh() {
    global g_KnowCtl
    if !Know_Schema()
        return
    metrics := Know_Metrics()
    lv := g_KnowCtl["score"]
    sel := lv.GetNext()
    lv.Opt("-Redraw"), lv.Delete()
    total := 0
    for , m in metrics {
        lv.Add(, m["group"], m["label"], m["count"] . (m["detail"] != "" ? " (" . m["detail"] . ")" : "")
             , m["last"] != "" ? SubStr(m["last"], 1, 16) : "")
        total += m["count"]
    }
    lv.Opt("+Redraw")
    if (sel && sel <= metrics.Length)
        try lv.Modify(sel, "Select")
    try g_KnowCtl["total"].Value := "Total learned items: " . total
}

Know_UiScoreSelect() {
    global g_KnowCtl, g_KnowRows, g_KnowCurKey
    row := g_KnowCtl["score"].GetNext()
    if !row
        return
    metrics := Know_Metrics()
    if (row > metrics.Length)
        return
    g_KnowCurKey := metrics[row]["key"]
    g_KnowRows := Know_CategoryRows(g_KnowCurKey)
    lv := g_KnowCtl["detail"]
    lv.Opt("-Redraw"), lv.Delete()
    for , r in g_KnowRows
        lv.Add(, r["label"], r["detail"], SubStr(r["when"], 1, 16))
    lv.Opt("+Redraw")
    try g_KnowCtl["playstatus"].Value := g_KnowRows.Length . " item(s) in " . metrics[row]["label"]
    try g_KnowCtl["viewer"].Value := ""
}

Know_UiDetailSelect() {
    global g_KnowCtl, g_KnowRows
    row := g_KnowCtl["detail"].GetNext()
    if (!row || row > g_KnowRows.Length)
        return
    r := g_KnowRows[row]
    ; content -> viewer
    v := r["content"]
    if (v = "")
        v := r["label"] . "`r`n" . r["detail"] . (r["when"] != "" ? "`r`n" . r["when"] : "")
    try g_KnowCtl["viewer"].Value := v
    ; spatial -> flash (playback)
    if (IsObject(r["bounds"]) && r["bounds"].Length >= 4) {
        if Know_Flash(r["bounds"])
            try g_KnowCtl["playstatus"].Value := "Playback: flashed " . r["bounds"][3] . "x" . r["bounds"][4]
                . " at " . r["bounds"][1] . "," . r["bounds"][2] . " (retained bounds)"
    }
}

Know_UiFlash() {
    global g_KnowCtl, g_KnowRows
    row := g_KnowCtl["detail"].GetNext()
    if (!row || row > g_KnowRows.Length) {
        try g_KnowCtl["playstatus"].Value := "Select an item first"
        return
    }
    r := g_KnowRows[row]
    if !Know_Flash(r["bounds"])
        try g_KnowCtl["playstatus"].Value := "This item has no remembered screen bounds"
}

Know_UiToggleLive(on) {
    global g_KnowLiveOn
    g_KnowLiveOn := on ? true : false
    SetTimer(Know_UiTick, g_KnowLiveOn ? 4000 : 0)
}

Know_UiTick() {
    global g_KnowLiveOn
    if !g_KnowLiveOn
        return
    Know_UiRefresh()
}

Know_UiExport() {
    global g_KnowCtl
    path := Know_ExportSnapshot()
    if (path != "" && FileExist(path)) {
        try g_KnowCtl["total"].Value := "Snapshot saved"
        try Run('explorer.exe /select,"' . path . '"')
    }
}
