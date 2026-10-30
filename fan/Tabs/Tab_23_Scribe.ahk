; ===============================================================================
; Tabs\Tab_23_Scribe.ahk
; TAB 23 Scribe: visual workflow capture. Record element interactions as frame
; "playbacks", review step-by-step, let DeepSeek deduce what/why + score, export
; a guide, and see cross-window chains. UI here; logic in lib\Scribe.ahk.
; Toggle recording with Ctrl+Shift+R.
; ===============================================================================

global g_ScribeCtl := Map()
global g_ScribeEpRows := []
global g_ScribeStepRows := []
global g_ScribeTabIndex := 23

Tab_Scribe_Build() {
    global g_ScribeTabIndex
    g_ScribeTabIndex := 23
    TabCtrl.UseTab(g_ScribeTabIndex)
    try Scribe_BuildTab(MainGui)
    catch as err
        LogErrorToFile(err, "caught", "Scribe tab construction")
}

Scribe_BuildTab(g) {
    global g_ScribeCtl, g_ScribeGapMs
    g.Add("Text", "x15 y50 w200 h22 +0x200", "Workflow Scribe").SetFont("s11 bold")
    g_ScribeCtl["record"] := g.Add("Button", "x220 y48 w150 h26", "● Start recording")
    g.Add("Text", "x380 y52 w80", "Gap (s):")
    g_ScribeCtl["gap"] := g.Add("Edit", "x438 y49 w46 h22", Round(g_ScribeGapMs / 1000))
    g_ScribeCtl["refresh"] := g.Add("Button", "x492 y48 w80 h26", "Refresh")
    g_ScribeCtl["status"] := g.Add("Text", "x580 y52 w295 h20 cGray", "")

    g.Add("Text", "x15 y82 w430", "Captured workflows (episodes)")
    g_ScribeCtl["eps"] := g.Add("ListView", "x15 y102 w430 h250 Grid -Multi"
        , ["id", "Workflow / title", "Window", "Steps", "Score"])
    g_ScribeCtl["eps"].ModifyCol(1, 34)
    g_ScribeCtl["eps"].ModifyCol(2, 150)
    g_ScribeCtl["eps"].ModifyCol(3, 140)
    g_ScribeCtl["eps"].ModifyCol(4, 44)
    g_ScribeCtl["eps"].ModifyCol(5, 44)

    g.Add("Text", "x455 y82 w420", "Steps (select to flash the element + see its frame)")
    g_ScribeCtl["steps"] := g.Add("ListView", "x455 y102 w420 h250 Grid -Multi"
        , ["#", "Interaction", "Role"])
    g_ScribeCtl["steps"].ModifyCol(1, 30)
    g_ScribeCtl["steps"].ModifyCol(2, 270)
    g_ScribeCtl["steps"].ModifyCol(3, 110)

    g_ScribeCtl["explain"] := g.Add("Button", "x15 y360 w170 h26", "Explain with DeepSeek")
    g_ScribeCtl["guide"] := g.Add("Button", "x190 y360 w140 h26", "Export guide")
    g_ScribeCtl["chains"] := g.Add("Button", "x335 y360 w160 h26", "Cross-window chains")
    g_ScribeCtl["frame"] := g.Add("Button", "x500 y360 w120 h26", "Open frame")
    g_ScribeCtl["playstatus"] := g.Add("Text", "x628 y364 w247 h20 cGray", "")

    g_ScribeCtl["viewer"] := g.Add("Edit", "x15 y394 w860 h290 ReadOnly Multi VScroll")
    g_ScribeCtl["viewer"].SetFont("s9", "Consolas")

    g_ScribeCtl["record"].OnEvent("Click", (*) => ScribeUI_Toggle())
    g_ScribeCtl["refresh"].OnEvent("Click", (*) => ScribeUI_RefreshEpisodes())
    g_ScribeCtl["gap"].OnEvent("Change", (*) => ScribeUI_SaveGap())
    g_ScribeCtl["eps"].OnEvent("ItemSelect", (lv, r, sel) => (sel ? ScribeUI_EpSelect() : 0))
    g_ScribeCtl["steps"].OnEvent("ItemSelect", (lv, r, sel) => (sel ? ScribeUI_StepSelect() : 0))
    g_ScribeCtl["explain"].OnEvent("Click", (*) => ScribeUI_Explain())
    g_ScribeCtl["guide"].OnEvent("Click", (*) => ScribeUI_ExportGuide())
    g_ScribeCtl["chains"].OnEvent("Click", (*) => ScribeUI_Chains())
    g_ScribeCtl["frame"].OnEvent("Click", (*) => ScribeUI_OpenFrame())

    ScribeUI_UpdateRecordBtn()
    ScribeUI_RefreshEpisodes()
}

ScribeUI_UpdateRecordBtn() {
    global g_ScribeCtl
    on := Scribe_IsOn()
    try g_ScribeCtl["record"].Text := on ? "■ Stop recording" : "● Start recording"
    try g_ScribeCtl["status"].Value := on
        ? "RECORDING - interact with any app; this window is ignored"
        : "Stopped. Ctrl+Shift+R toggles recording from anywhere."
}

ScribeUI_Toggle() {
    Scribe_Toggle()
    ScribeUI_UpdateRecordBtn()
    if !Scribe_IsOn()
        ScribeUI_RefreshEpisodes()
}

ScribeUI_SaveGap() {
    global g_ScribeCtl, g_ScribeGapMs
    v := Trim(g_ScribeCtl["gap"].Value)
    if (IsInteger(v) && Integer(v) >= 1)
        g_ScribeGapMs := Integer(v) * 1000
}

ScribeUI_RefreshEpisodes() {
    global g_ScribeCtl, g_ScribeEpRows
    g_ScribeEpRows := Scribe_Episodes()
    lv := g_ScribeCtl["eps"]
    lv.Opt("-Redraw"), lv.Delete()
    for , e in g_ScribeEpRows {
        title := e["workflow_name"] != "" ? e["workflow_name"] : e["title"]
        lv.Add(, e["id"], Scribe_Clip(title, 40), Scribe_Clip(e["window_title"], 34)
             , e["step_count"], e["score"] ? e["score"] : "")
    }
    lv.Opt("+Redraw")
    ScribeUI_UpdateRecordBtn()
}

ScribeUI_SelectedEp() {
    global g_ScribeCtl, g_ScribeEpRows
    r := g_ScribeCtl["eps"].GetNext()
    return (r && r <= g_ScribeEpRows.Length) ? g_ScribeEpRows[r] : Map()
}

ScribeUI_EpSelect() {
    global g_ScribeCtl, g_ScribeStepRows
    ep := ScribeUI_SelectedEp()
    if !ep.Count
        return
    g_ScribeStepRows := Scribe_Steps(ep["id"])
    lv := g_ScribeCtl["steps"]
    lv.Opt("-Redraw"), lv.Delete()
    for , s in g_ScribeStepRows
        lv.Add(, s["seq"], Scribe_StepText(s), s["element_role"])
    lv.Opt("+Redraw")
    t := "PLAYBACK - " . (ep["workflow_name"] != "" ? ep["workflow_name"] : ep["title"]) . "`r`n"
       . "Window: " . ep["window_title"] . "   Steps: " . ep["step_count"] . "`r`n`r`n"
       . Scribe_PlaybackText(ep["id"])
    if (ep["why"] != "")
        t .= "`r`nWHY: " . ep["why"]
    try g_ScribeCtl["viewer"].Value := t
}

ScribeUI_StepSelect() {
    global g_ScribeCtl, g_ScribeStepRows
    r := g_ScribeCtl["steps"].GetNext()
    if (!r || r > g_ScribeStepRows.Length)
        return
    s := g_ScribeStepRows[r]
    if (Integer(s["w"]) > 0 && Integer(s["h"]) > 0)
        try FlashHighlight(Integer(s["x"]), Integer(s["y"]), Integer(s["w"]), Integer(s["h"]), 3, 220, "match")
    hasFrame := (s["frame_path"] != "" && FileExist(s["frame_path"]))
    try g_ScribeCtl["playstatus"].Value := "Step " . s["seq"] . (hasFrame ? " - frame ready (Open frame)" : " - no frame")
}

ScribeUI_OpenFrame() {
    global g_ScribeCtl, g_ScribeStepRows
    r := g_ScribeCtl["steps"].GetNext()
    if (!r || r > g_ScribeStepRows.Length)
        return
    p := g_ScribeStepRows[r]["frame_path"]
    if (p != "" && FileExist(p)) {
        try Run('"' . p . '"')
    } else {
        try g_ScribeCtl["playstatus"].Value := "No frame for this step"
    }
}

ScribeUI_Explain() {
    ep := ScribeUI_SelectedEp()
    if !ep.Count {
        try g_ScribeCtl["playstatus"].Value := "Select a workflow first"
        return
    }
    try g_ScribeCtl["viewer"].Value := "Asking DeepSeek to deduce what/why..."
    epId := ep["id"]
    SetTimer(() => ScribeUI_ExplainWork(epId), -30)
}

ScribeUI_ExplainWork(epId) {
    global g_ScribeCtl
    res := Scribe_Explain(epId)
    if !res["ok"] {
        try g_ScribeCtl["viewer"].Value := "Explain failed: " . res["error"]
        return
    }
    try g_ScribeCtl["viewer"].Value := res["text"]
    ScribeUI_RefreshEpisodes()
}

ScribeUI_ExportGuide() {
    ep := ScribeUI_SelectedEp()
    if !ep.Count {
        try g_ScribeCtl["playstatus"].Value := "Select a workflow first"
        return
    }
    path := Scribe_ExportGuide(ep["id"])
    if (path != "" && FileExist(path)) {
        try g_ScribeCtl["playstatus"].Value := "Guide saved"
        try Run('explorer.exe /select,"' . path . '"')
    }
}

ScribeUI_Chains() {
    global g_ScribeCtl
    chains := Scribe_Chains()
    t := "CROSS-WINDOW CHAINS (workflows spanning windows)`r`n`r`n"
    if !chains.Length
        t .= "(no chains yet - record some workflows)"
    for i, c in chains {
        wins := []
        for w in c["windows"]
            wins.Push(Scribe_Clip(w, 30))
        t .= "Chain " . i . (c["cross"] ? "  [cross-window]" : "") . " - "
           . c["episodes"].Length . " episode(s) across " . c["windows"].Count . " window(s):`r`n"
        for , e in c["episodes"]
            t .= "   - " . (e["workflow_name"] != "" ? e["workflow_name"] : e["title"])
               . "  (" . Scribe_Clip(e["window_title"], 30) . ", " . e["step_count"] . " steps)`r`n"
        t .= "`r`n"
    }
    try g_ScribeCtl["viewer"].Value := t
}
