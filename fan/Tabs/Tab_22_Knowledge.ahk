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
global g_KnowAllRows := [], g_KnowMetrics := []
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
    g.Add("Text", "x15 y50 w260 h22 +0x200", "Evidence & knowledge").SetFont("s11 bold")
    g_KnowCtl["live"] := g.Add("CheckBox", "x290 y52 w120", "Auto-refresh")
    g_KnowCtl["refresh"] := g.Add("Button", "x414 y48 w90 h24", "Refresh")
    g_KnowCtl["export"] := g.Add("Button", "x508 y48 w150 h24", "Export inventory")
    g_KnowCtl["total"] := g.Add("Text", "x664 y52 w210 h20 cGray", "")

    g_KnowCtl["summary"] := g.Add("Text", "x15 y80 w860 h46", "")
    g.Add("Text", "x15 y132 w420", "Categories: choose what to review")
    g_KnowCtl["score"] := g.Add("ListView", "x15 y156 w420 h218 Grid -Multi"
        , ["Group", "Category", "Count", "Last"])
    g_KnowCtl["score"].ModifyCol(1, 150)
    g_KnowCtl["score"].ModifyCol(2, 130)
    g_KnowCtl["score"].ModifyCol(3, 55)
    g_KnowCtl["score"].ModifyCol(4, 120)

    g_KnowCtl["search"] := g.Add("Edit", "x445 y128 w330 h23")
    SendMessage(0x1501, true, StrPtr("Search this category's latest 300 records"), g_KnowCtl["search"])
    g_KnowCtl["clear"] := g.Add("Button", "x780 y128 w95 h23", "Clear search")
    g_KnowCtl["search"].OnEvent("Change", Know_UiFilter)
    g_KnowCtl["clear"].OnEvent("Click", (*) => (g_KnowCtl["search"].Value := "", Know_UiFilter()))
    g_KnowCtl["detail"] := g.Add("ListView", "x445 y156 w430 h218 Grid -Multi"
        , ["Item", "Detail", "When"])
    g_KnowCtl["detail"].ModifyCol(1, 200)
    g_KnowCtl["detail"].ModifyCol(2, 150)
    g_KnowCtl["detail"].ModifyCol(3, 110)

    g_KnowCtl["flash"] := g.Add("Button", "x445 y380 w185 h26", "Show remembered bounds")
    g_KnowCtl["playstatus"] := g.Add("Text", "x15 y382 w420 h24 cGray", "")

    g_KnowCtl["claim"] := g.Add("Button", "x635 y380 w120 h26", "Review claim")
    g_KnowCtl["claim"].Enabled := false
    g_KnowCtl["claim"].OnEvent("Click", Know_UiReviewClaim)
    g_KnowCtl["lessons"] := g.Add("Button", "x760 y380 w115 h26", "Evidence / lessons")
    g_KnowCtl["lessons"].OnEvent("Click", LearningLab_Open)

    ; "Big picture" utility actions - not counts: see real records, validate
    ; live, and get DeepSeek to turn the knowledge into next actions.
    g_KnowCtl["sample"] := g.Add("Button", "x15 y414 w140 h26", "Sample records")
    g_KnowCtl["validate"] := g.Add("Button", "x160 y414 w150 h26", "Check window / bounds")
    g_KnowCtl["insights"] := g.Add("Button", "x315 y414 w170 h26", "DeepSeek insights (API)")
    g_KnowCtl["bigstatus"] := g.Add("Text", "x490 y418 w385 h20 cGray", "")

    g_KnowCtl["viewer"] := g.Add("Edit", "x15 y446 w860 h238 ReadOnly Multi VScroll")
    g_KnowCtl["viewer"].SetFont("s9", "Consolas")

    g_KnowCtl["refresh"].OnEvent("Click", (*) => Know_UiRefresh())
    g_KnowCtl["export"].OnEvent("Click", (*) => Know_UiExport())
    g_KnowCtl["live"].OnEvent("Click", (c, *) => Know_UiToggleLive(c.Value))
    g_KnowCtl["score"].OnEvent("ItemSelect", Know_UiCategorySelected)
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
    Know_UiSetRows(g_KnowRows)
    try g_KnowCtl["bigstatus"].Value := "Random sample of " . g_KnowRows.Length
        . " real records - select one to view / flash"
    try g_KnowCtl["viewer"].Value := "A randomized cross-section of what the system has actually captured.`r`n"
        . "Select an item to inspect it. Use Show remembered bounds for a location preview."
}

; Bulk live validation with a score.
Know_UiValidate() {
    global g_KnowCtl, g_KnowRows, g_KnowCurKey
    try g_KnowCtl["bigstatus"].Value := "Validating remembered targets against live windows..."
    res := Know_BulkValidate(40)
    g_KnowCurKey := "validate"
    g_KnowRows := res["rows"]
    Know_UiSetRows(g_KnowRows)
    try g_KnowCtl["bigstatus"].Value := "Window / bounds availability " . res["score"] . "%  ("
        . res["passed"] . "/" . res["total"] . " available) - not a target identity check"
    try g_KnowCtl["viewer"].Value := "Window / bounds availability: sampled " . res["total"]
        . " remembered spatial targets and checked each against live windows + screen bounds.`r`n"
        . "Passed: " . res["passed"] . "   Score: " . res["score"] . "%`r`n`r`n"
        . "Select a row and use Show remembered bounds for a location preview. This check does not verify target identity or action success."
}

; DeepSeek insights (API) over the accumulated knowledge (off the click thread).
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
    try g_KnowCtl["bigstatus"].Value := "DeepSeek insights (API) ready (est $" . Round(res["cost"], 4) . ")"
    try g_KnowCtl["viewer"].Value := res["text"]
}

; ─────────────────────────────────────────────────────────────────────────────
Know_UiRefresh(refreshRows := true) {
    global g_KnowCtl, g_KnowMetrics, g_KnowCurKey
    if !Know_Schema()
        return
    metrics := Know_Metrics()
    g_KnowMetrics := metrics
    lv := g_KnowCtl["score"]
    sel := lv.GetNext()
    ; Restore by category key: new tables can appear after a learner starts.
    for index, metric in metrics
        if metric["key"] = g_KnowCurKey
            sel := index
    g_KnowCtl["score"].OnEvent("ItemSelect", Know_UiCategorySelected, 0)
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
    try g_KnowCtl["total"].Value := "Inventory records: " . total
    try g_KnowCtl["summary"].Value := Know_ReviewSummary()
    if !sel && metrics.Length
        lv.Modify(1, "Select")
    g_KnowCtl["score"].OnEvent("ItemSelect", Know_UiCategorySelected)
    if refreshRows
        Know_UiScoreSelect()
}

Know_UiCategorySelected(lv, row, selected) {
    if selected
        Know_UiScoreSelect()
}

Know_UiScoreSelect() {
    global g_KnowCtl, g_KnowCurKey, g_KnowMetrics
    row := g_KnowCtl["score"].GetNext()
    if !row || row > g_KnowMetrics.Length
        return
    g_KnowCurKey := g_KnowMetrics[row]["key"]
    Know_UiSetRows(Know_CategoryRows(g_KnowCurKey))
}

; Keep the displayed row IDs bound to their source even when filtering.
Know_UiSetRows(rows) {
    global g_KnowAllRows
    g_KnowAllRows := rows
    Know_UiFilter()
}

Know_UiFilter(*) {
    global g_KnowCtl, g_KnowRows, g_KnowAllRows, g_KnowCurKey
    query := Trim(g_KnowCtl["search"].Value)
    g_KnowRows := []
    lv := g_KnowCtl["detail"]
    lv.Opt("-Redraw"), lv.Delete()
    for r in g_KnowAllRows {
        haystack := r["label"] . " " . r["detail"] . " " . r["when"] . " " . r["content"]
        if query != "" && !InStr(haystack, query, false)
            continue
        g_KnowRows.Push(r)
        lv.Add(, r["label"], r["detail"], SubStr(r["when"], 1, 16))
    }
    lv.Opt("+Redraw")
    g_KnowCtl["claim"].Enabled := false
    g_KnowCtl["playstatus"].Value := g_KnowRows.Length . " shown / " . g_KnowAllRows.Length . " loaded (recent records)"
    g_KnowCtl["viewer"].Value := Know_CategoryGuide(g_KnowCurKey)
        . (g_KnowRows.Length ? "`r`n`r`nSelect a record to inspect its source and content." : "`r`n`r`nNo matching records. Clear the search, choose another category, or collect a small example using Capture & learn.")
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
    if r.Get("claim_id", 0) {
        evidence := LearningLab_Summary(r["claim_id"])
        if evidence.Count
            v := "Evidence state: " . evidence["state"] . "`r`n"
                . evidence["passes"] . " spaced positive checks; " . evidence["failures"] . " negative checks; "
                . evidence["contexts"] . " positive contexts across " . evidence["sessions"] . " sessions.`r`n"
                . "Use Review claim for the source ledger, limitations and rehearsal.`r`n`r`n" . v
    }
    g_KnowCtl["viewer"].Value := Know_CategoryGuide(g_KnowCurKey)
        . "`r`n`r`nRecord: " . r["label"] . "`r`nSource/detail: " . r["detail"]
        . "`r`nRecorded: " . (r["when"] != "" ? r["when"] : "timestamp unavailable") . "`r`n`r`n" . v
    g_KnowCtl["claim"].Enabled := r.Get("claim_id", 0) > 0

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
    ; Update inventory counts while the operator reads a selected record.
    Know_UiRefresh(false)
}

Know_UiExport() {
    global g_KnowCtl
    path := Know_ExportSnapshot()
    if (path != "" && FileExist(path)) {
        try g_KnowCtl["total"].Value := "Snapshot saved"
        try Run('explorer.exe /select,"' . path . '"')
    }
}

Know_UiReviewClaim(*) {
    global g_KnowCtl, g_KnowRows
    row := g_KnowCtl["detail"].GetNext()
    if row && row <= g_KnowRows.Length && g_KnowRows[row].Get("claim_id", 0)
        LearningLab_Present(Map("claim_id", g_KnowRows[row]["claim_id"]))
}
