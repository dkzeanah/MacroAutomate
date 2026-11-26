; ===============================================================================
; Tabs\Tab_21_MediaIntel.ahk
; TAB 21 Media Intelligence: programmatic media processing + environment
; intelligence (OCR feature map). UI + handlers here; logic in lib\MediaLLM.ahk,
; lib\MediaPipeline.ahk, lib\EnvIntel.ahk. Shares the DeepSeek key/cost cap with
; the Study Assistant (Windows Credential Manager / DEEPSEEK_API_KEY).
; ===============================================================================

global g_MediaCtl := Map()
global g_MediaActiveJob := ""
global g_MediaJobRows := []
global g_MediaEnvMap := Map()
global g_MediaTabIndex := 21
global g_MediaWinList := []
global g_MediaMonList := []

Tab_MediaIntel_Build() {
    global g_MediaCtl, g_MediaTabIndex
    g_MediaTabIndex := 21
    TabCtrl.UseTab(g_MediaTabIndex)
    try MediaIntel_BuildTab(MainGui)
    catch as err
        LogErrorToFile(err, "caught", "Media Intelligence tab construction")
}

MediaIntel_BuildTab(g) {
    global g_MediaCtl

    ; ── video / media pipeline ───────────────────────────────────────────────
    g.Add("GroupBox", "x15 y46 w860 h366", "Video analysis — local shots, cuts and motion; optional DeepSeek descriptions")
    g.Add("Text", "x28 y70 w40", "Video:")
    g_MediaCtl["video"] := g.Add("Edit", "x70 y67 w560 h22",Media_GetSetting("last_video",""))
    g_MediaCtl["browse"] := g.Add("Button", "x636 y66 w90 h24", "Browse...")
    g.Add("Text", "x732 y70 w30", "FPS:")
    g_MediaCtl["fps"] := g.Add("Edit", "x762 y67 w40 h22", Media_GetSetting("fps", "1"))
    g_MediaCtl["scene"] := g.Add("CheckBox", "x808 y69 w60", "Scene")

    g.Add("Text", "x28 y98 w60", "AI prompt:")
    g_MediaCtl["question"] := g.Add("Edit", "x90 y95 w540 h22"
        , Media_GetSetting("question","Describe the key actions, UI states and notable events."))
    g.Add("Text", "x636 y98 w70", "Max frames:")
    g_MediaCtl["maxframes"] := g.Add("Edit", "x706 y95 w50 h22", Media_GetSetting("max_frames", "120"))
    g.Add("Text", "x762 y98 w40", "Batch:")
    g_MediaCtl["batch"] := g.Add("Edit", "x802 y95 w36 h22", Media_GetSetting("batch","8"))

    g_MediaCtl["run"] := g.Add("Button", "x28 y124 w186 h26", "Analyze video (local)")
    g_MediaCtl["bridge"] := g.Add("Button", "x218 y124 w196 h26", "Describe content (DeepSeek)")
    g_MediaCtl["analyze"] := g.Add("Button", "x418 y124 w130 h26", "Describe saved job")
    g_MediaCtl["cancel"] := g.Add("Button", "x552 y124 w70 h26", "Cancel")
    g_MediaCtl["status"] := g.Add("Text", "x628 y128 w246 h20 cGray", "")

    g_MediaCtl["jobs"] := g.Add("ListView", "x28 y158 w300 h150 Grid -Multi"
        , ["id", "Title", "Frames", "Status"])
    g_MediaCtl["jobs"].ModifyCol(1, 34)
    g_MediaCtl["jobs"].ModifyCol(2, 150)
    g_MediaCtl["jobs"].ModifyCol(3, 50)
    g_MediaCtl["jobs"].ModifyCol(4, 58)
    g_MediaCtl["timeline"] := g.Add("ListView", "x336 y158 w530 h150 Grid -Multi"
        , ["Time", "Category", "Label", "Description"])
    g_MediaCtl["timeline"].ModifyCol(1, 54)
    g_MediaCtl["timeline"].ModifyCol(2, 80)
    g_MediaCtl["timeline"].ModifyCol(3, 120)
    g_MediaCtl["timeline"].ModifyCol(4, 268)

    g_MediaCtl["expJson"] := g.Add("Button", "x28 y316 w120 h26", "Export JSON")
    g_MediaCtl["expRep"] := g.Add("Button", "x152 y316 w120 h26", "Export report")
    g_MediaCtl["sheet"] := g.Add("Button", "x276 y316 w120 h26", "Contact sheet")
    g_MediaCtl["chapters"] := g.Add("Button", "x400 y316 w110 h26", "Chapters")
    g.Add("Text", "x520 y320 w70", "Clip ms:")
    g_MediaCtl["clipStart"] := g.Add("Edit", "x588 y316 w70 h24", "0")
    g_MediaCtl["clipEnd"] := g.Add("Edit", "x662 y316 w70 h24", "5000")
    g_MediaCtl["clip"] := g.Add("Button", "x736 y316 w130 h26", "Make clip")
    g_MediaCtl["ffline"] := g.Add("Edit", "x28 y348 w838 h52 ReadOnly Multi VScroll", "Choose a video, then Analyze video. Local analysis needs no API key; DeepSeek descriptions are optional.")

    ; ── environment intelligence ─────────────────────────────────────────────
    g.Add("GroupBox", "x15 y418 w860 h300", "Environment intelligence  (OCR feature map -> machine-readable regions)")
    ; Window targeting: pick any open window from a dropdown.
    g.Add("Text", "x28 y445 w48", "Window:")
    g_MediaCtl["winDD"] := g.Add("DropDownList", "x78 y441 w330 h320")
    g_MediaCtl["winRefresh"] := g.Add("Button", "x412 y440 w26 h26", "R")
    g_MediaCtl["mapWin"] := g.Add("Button", "x442 y440 w110 h26", "Map window")
    g_MediaCtl["mapImg"] := g.Add("Button", "x556 y440 w120 h26", "Map image file...")
    ; Region/monitor targeting: pick a monitor, map the whole monitor or drag.
    g.Add("Text", "x28 y473 w50", "Monitor:")
    g_MediaCtl["monDD"] := g.Add("DropDownList", "x80 y469 w130")
    g_MediaCtl["mapMon"] := g.Add("Button", "x214 y468 w104 h26", "Map monitor")
    g_MediaCtl["mapRegion"] := g.Add("Button", "x322 y468 w150 h26", "Map region (drag)")
    g_MediaCtl["envRefine"] := g.Add("CheckBox", "x482 y472 w200", "Refine roles with DeepSeek")

    g_MediaCtl["envExport"] := g.Add("Button", "x28 y498 w160 h26", "Export map JSON")
    g_MediaCtl["envStatus"] := g.Add("Text", "x196 y502 w678 h18 cGray"
        , "Pick a window or monitor -> machine-readable regions (segment -> OCR -> group -> extract).")

    g_MediaCtl["regions"] := g.Add("ListView", "x28 y526 w838 h156 Grid -Multi"
        , ["#", "Role", "Text", "X", "Y", "W", "H"])
    for col, w in [34, 90, 500, 50, 50, 50, 50]
        g_MediaCtl["regions"].ModifyCol(col, w)

    ; ── provider + ffmpeg settings ───────────────────────────────────────────
    g.Add("Text", "x28 y692 w90", "ffmpeg path:")
    g_MediaCtl["ffpath"] := g.Add("Edit", "x118 y689 w520 h22", Media_GetSetting("ffmpeg_path", ""))
    g_MediaCtl["ffsave"] := g.Add("Button", "x644 y688 w90 h24", "Save")
    g_MediaCtl["probe"] := g.Add("Button", "x740 y688 w126 h24", "Test provider")

    ; ── events ───────────────────────────────────────────────────────────────
    g_MediaCtl["browse"].OnEvent("Click", (*) => MediaUI_PickVideo())
    g_MediaCtl["run"].OnEvent("Click", (*) => MediaUI_AnalyzeSelected())
    g_MediaCtl["bridge"].OnEvent("Click", (*) => MediaUI_Run())
    g_MediaCtl["analyze"].OnEvent("Click", (*) => MediaUI_DescribeSelected())
    g_MediaCtl["cancel"].OnEvent("Click", (*) => MediaUI_Cancel())
    g_MediaCtl["jobs"].OnEvent("ItemSelect", (lv, r, sel) => (sel ? MediaUI_JobSelected() : 0))
    g_MediaCtl["expJson"].OnEvent("Click", (*) => MediaUI_Export("json"))
    g_MediaCtl["expRep"].OnEvent("Click", (*) => MediaUI_Export("report"))
    g_MediaCtl["sheet"].OnEvent("Click", (*) => MediaUI_ContactSheet())
    g_MediaCtl["chapters"].OnEvent("Click", (*) => MediaUI_Chapters())
    g_MediaCtl["clip"].OnEvent("Click", (*) => MediaUI_Clip())
    g_MediaCtl["mapWin"].OnEvent("Click", (*) => MediaUI_MapSelectedWindow())
    g_MediaCtl["winRefresh"].OnEvent("Click", (*) => MediaUI_RefreshWindows())
    g_MediaCtl["mapMon"].OnEvent("Click", (*) => MediaUI_MapMonitor())
    g_MediaCtl["mapRegion"].OnEvent("Click", (*) => MediaUI_MapRegion())
    g_MediaCtl["mapImg"].OnEvent("Click", (*) => MediaUI_MapImage())
    ; Selecting a region flashes it on screen - a "playback" to validate the map.
    g_MediaCtl["regions"].OnEvent("ItemSelect", (lv, r, sel) => (sel ? MediaUI_RegionSelected(r) : 0))
    g_MediaCtl["envExport"].OnEvent("Click", (*) => MediaUI_EnvExport())
    g_MediaCtl["ffsave"].OnEvent("Click", (*) => MediaUI_SaveFfmpeg())
    g_MediaCtl["probe"].OnEvent("Click", (*) => MediaUI_Probe())

    MediaUI_RefreshFfLine()
    MediaUI_RefreshJobs()
    MediaUI_RefreshWindows()
    MediaUI_RefreshMonitors()
    MediaUI_Busy(false)
}

; ─────────────────────────────────────────────────────────────────────────────
; HANDLERS
; ─────────────────────────────────────────────────────────────────────────────
MediaUI_Status(msg) {
    global g_MediaCtl
    try g_MediaCtl["status"].Value := TrackEllipsis(msg,42)
    try g_MediaCtl["ffline"].Value := msg
}

MediaUI_RefreshFfLine() {
    global g_MediaCtl
    exe := Media_FfmpegExe()
    ff := exe != "" ? "ffmpeg: " . exe
                    : "ffmpeg NOT found - set its path below."
    try g_MediaCtl["ffline"].Value := ff . "   |   " . MediaBridge_Status()
}

; Analyze the chosen video through the avideditor (Cutline) engine: OpenCV
; shot/cut/motion analysis. Runs off the click thread.
MediaUI_BridgeAnalyze() => MediaUI_AnalyzeSelected()

MediaUI_BridgeWork(path) {
    g_MediaCtl["video"].Value := path
    MediaUI_AnalyzeSelected()
}

MediaUI_PickVideo() {
    global g_MediaCtl
    path := ""
    try path := FileSelect(1, , "Choose a video", "Video (*.mp4; *.mkv; *.mov; *.avi; *.webm; *.wmv)")
    if (path != "") {
        g_MediaCtl["video"].Value := path
        Media_SetSetting("last_video",path)
    }
}

MediaUI_Run() {
    path := Trim(g_MediaCtl["video"].Value, ' "')
    if !FileExist(path) || DirExist(path) {
        MediaUI_Status("Choose an existing video first.")
        return
    }
    MediaUI_StartSemantic(path,0)
}

MediaUI_RunWork(path) => MediaUI_StartSemantic(path,0)

MediaUI_Number(key, fallback, low, high) {
    value := Trim(g_MediaCtl[key].Value)
    return IsNumber(value) ? Max(low,Min(high,value+0)) : fallback
}

MediaUI_StartSemantic(path, jobId) {
    global g_MediaActiveJob, g_StudyLLM_SpentUSD, g_StudyLLM_Endpoint, g_StudyLLM_VisionModel
    if g_MediaActiveJob
        return
    if !StudyLLM_HasKey() {
        MediaUI_Status("DeepSeek descriptions need your saved provider key. Analyze video (local) works without a key.")
        return
    }
    if !Media_FfmpegAvailable() && (!jobId || !Media_Frames(jobId).Length) {
        MediaUI_Status("FFmpeg is required to extract frames. Set its path below; local analysis works through Cutline.")
        return
    }
    args := Map("path",path,"job_id",jobId,"db_path",TrackDB().path,"question",g_MediaCtl["question"].Value,
        "fps",MediaUI_Number("fps",1,.01,10),"batch",Integer(MediaUI_Number("batch",8,1,16)),
        "max_frames",Integer(MediaUI_Number("maxframes",120,1,500)),"scene",g_MediaCtl["scene"].Value,"spent_usd",g_StudyLLM_SpentUSD,"endpoint",g_StudyLLM_Endpoint,"vision_model",g_StudyLLM_VisionModel)
    for key in ["fps","batch","max_frames","question"]
        Media_SetSetting(key,args[key])
    Media_SetSetting("last_video",path)
    try {
        g_MediaActiveJob := WorkspaceJobs_Start("media_semantic",args,MediaUI_SemanticComplete,MediaUI_WorkProgress)
        MediaUI_Busy(true), MediaUI_Status("Starting frame extraction and DeepSeek descriptions…")
    } catch as startError
        MediaUI_Status(startError.Message)
}

MediaUI_SemanticComplete(response) {
    global g_MediaActiveJob, g_StudyLLM_SpentUSD
    g_MediaActiveJob := "", MediaUI_Busy(false)
    g_StudyLLM_SpentUSD += response.Get("cost",0)
    MediaUI_RefreshJobs()
    if response.Get("job_id",0)
        MediaUI_SelectJob(response["job_id"]), MediaUI_LoadTimeline(response["job_id"])
    if !response.Get("ok",false)
        MediaUI_Status("DeepSeek analysis: " . response.Get("error","Failed"))
    else
        MediaUI_Status("Completed " . response.Get("events",[]).Length . " descriptions across " . response.Get("batches",0) . " batches; estimated $" . Round(response.Get("cost",0),4) . ". Review the timeline or export a report.")
}

MediaUI_AnalyzeSelected() {
    global g_MediaCtl, g_MediaJobRows, g_MediaActiveJob
    if g_MediaActiveJob {
        MediaUI_Status("Analysis is already running. Cancel it before starting another video.")
        return
    }
    path := Trim(g_MediaCtl["video"].Value, ' "')
    selected := g_MediaCtl["jobs"].GetNext()
    if path = "" && selected && selected <= g_MediaJobRows.Length
        path := g_MediaJobRows[selected]["source_path"]
    if !FileExist(path) || DirExist(path) {
        MediaUI_Status("Choose an existing video with Browse, then Analyze video.")
        return
    }
    Media_SetSetting("last_video",path)
    MediaUI_Status("Starting local Cutline video analysis…")
    try {
        g_MediaActiveJob := WorkspaceJobs_Start("media_local",Map("path",path,"engine_root",MediaBridge_Root()),MediaUI_LocalComplete.Bind(path),MediaUI_WorkProgress)
        MediaUI_Busy(true)
    } catch as startError
        MediaUI_Status(startError.Message)
}

MediaUI_Busy(busy) {
    for key in ["run","bridge","analyze"]
        g_MediaCtl[key].Enabled := !busy
    g_MediaCtl["cancel"].Enabled := busy
}

MediaUI_WorkProgress(update) {
    MediaUI_Status(Round(update.Get("fraction",0)*100) . "% · " . update.Get("message","Working…"))
}

MediaUI_Cancel() {
    global g_MediaActiveJob
    if g_MediaActiveJob
        WorkspaceJobs_Cancel(g_MediaActiveJob)
    Media_CancelAll(), StudyLLM_CancelRequest()
    MediaUI_Status("Cancelling analysis…")
}

MediaUI_LocalComplete(path, response) {
    global g_MediaActiveJob
    g_MediaActiveJob := "", MediaUI_Busy(false)
    if !response.Get("ok",false) {
        MediaUI_Status(response.Get("error","Video analysis failed"))
        return
    }
    jobId := MediaBridge_StoreAnalysis(path,response["result"])
    Media_StoreFrames(jobId,response.Get("frames",[]))
    TrackDB().Run("UPDATE media_job SET status='analyzed' WHERE id=?",jobId)
    MediaUI_RefreshJobs(), MediaUI_SelectJob(jobId), MediaUI_LoadTimeline(jobId)
    result := response["result"]
    MediaUI_Status("Completed local analysis: " . result.Get("shots",[]).Length . " shots, " . result.Get("cuts",[]).Length
        . " cuts, " . result.Get("samples",[]).Length . " visual samples; " . response.Get("frames",[]).Length
        . " preview frames. Review the timeline, export a report or make a contact sheet. Use DeepSeek for semantic descriptions.")
}

MediaUI_DescribeSelected() {
    jobId := MediaUI_SelectedJobId()
    if !jobId {
        MediaUI_Status("Choose a saved job, or use Describe content for the video above.")
        return
    }
    for job in g_MediaJobRows
        if job["id"] = jobId {
            MediaUI_StartSemantic(job["source_path"],jobId)
            return
        }
}

MediaUI_AnalyzeJob(jobId) {
    for job in g_MediaJobRows
        if job["id"] = jobId {
            MediaUI_StartSemantic(job["source_path"],jobId)
            return
        }
}

MediaUI_RefreshJobs() {
    global g_MediaCtl, g_MediaJobRows
    g_MediaJobRows := Media_Jobs()
    lv := g_MediaCtl["jobs"]
    lv.Opt("-Redraw"), lv.Delete()
    for , j in g_MediaJobRows
        lv.Add(, j["id"], j["title"], j["frame_count"], j["status"])
    lv.Opt("+Redraw")
}

MediaUI_SelectedJobId() {
    global g_MediaCtl, g_MediaJobRows
    r := g_MediaCtl["jobs"].GetNext()
    if (!r || r > g_MediaJobRows.Length)
        return 0
    return g_MediaJobRows[r]["id"]
}

MediaUI_SelectJob(jobId) {
    global g_MediaCtl, g_MediaJobRows
    for i, j in g_MediaJobRows {
        if (j["id"] = jobId) {
            try g_MediaCtl["jobs"].Modify(i, "Select Focus")
            return
        }
    }
}

MediaUI_JobSelected() {
    jobId := MediaUI_SelectedJobId()
    if jobId {
        for job in g_MediaJobRows
            if job["id"] = jobId {
                g_MediaCtl["video"].Value := job["source_path"]
                MediaUI_Status(job["status"] . " · " . job["summary"])
                break
            }
        MediaUI_LoadTimeline(jobId)
    }
}

MediaUI_LoadTimeline(jobId) {
    global g_MediaCtl
    lv := g_MediaCtl["timeline"]
    lv.Opt("-Redraw"), lv.Delete()
    for , e in Media_Timeline(jobId)
        lv.Add(, Media_FmtMs(e["ts_ms"]), e["category"], e["label"], e["description"])
    lv.Opt("+Redraw")
}

MediaUI_Export(kind) {
    jobId := MediaUI_SelectedJobId()
    if !jobId {
        MediaUI_Status("Select a job first")
        return
    }
    path := (kind = "report") ? Media_ExportReport(jobId) : Media_ExportTimelineJson(jobId)
    MediaUI_OpenResult(path)
}

MediaUI_ContactSheet() {
    jobId := MediaUI_SelectedJobId()
    if !jobId {
        MediaUI_Status("Select a job first")
        return
    }
    MediaUI_Status("Building contact sheet...")
    res := Media_ContactSheet(jobId, 5)
    if res["ok"]
        MediaUI_OpenResult(res["path"])
    else
        MediaUI_Status("Contact sheet: " . res["error"])
}

MediaUI_Chapters() {
    jobId := MediaUI_SelectedJobId()
    if !jobId {
        MediaUI_Status("Select a job first")
        return
    }
    path := Media_ChaptersFile(jobId)
    if (path = "")
        MediaUI_Status("No events to build chapters from")
    else
        MediaUI_OpenResult(path)
}

MediaUI_Clip() {
    global g_MediaCtl, g_MediaJobRows
    r := g_MediaCtl["jobs"].GetNext()
    if (!r || r > g_MediaJobRows.Length) {
        MediaUI_Status("Select a job first")
        return
    }
    src := g_MediaJobRows[r]["source_path"]
    s := Integer(Trim(g_MediaCtl["clipStart"].Value))
    e := Integer(Trim(g_MediaCtl["clipEnd"].Value))
    MediaUI_Status("Cutting clip...")
    res := Media_HighlightClip(src, s, e)
    if res["ok"]
        MediaUI_OpenResult(res["path"])
    else
        MediaUI_Status("Clip: " . res["error"])
}

MediaUI_OpenResult(path) {
    if (path = "" || !FileExist(path)) {
        MediaUI_Status("Nothing produced")
        return
    }
    MediaUI_Status("Saved: " . path)
    try Run('explorer.exe /select,"' . path . '"')
}

; ── environment intelligence handlers ────────────────────────────────────────
; Enumerate all open top-level windows (excluding this app) into the dropdown.
MediaUI_RefreshWindows() {
    global g_MediaCtl, g_MediaWinList
    g_MediaWinList := []
    items := []
    myPid := DllCall("GetCurrentProcessId", "UInt")
    for hwnd in WinGetList() {
        t := ""
        try t := WinGetTitle("ahk_id " . hwnd)
        if (t = "")
            continue
        if !DllCall("IsWindowVisible", "Ptr", hwnd)
            continue
        pid := 0
        try pid := WinGetPID("ahk_id " . hwnd)
        if (pid = myPid)
            continue
        exe := ""
        try exe := WinGetProcessName("ahk_id " . hwnd)
        g_MediaWinList.Push(Map("hwnd", hwnd, "title", t, "exe", exe))
        items.Push(SubStr(t, 1, 64) . (exe != "" ? "  [" . exe . "]" : ""))
    }
    dd := g_MediaCtl["winDD"]
    dd.Delete()
    if items.Length {
        dd.Add(items)
        dd.Choose(1)
    }
    MediaUI_EnvStatus(g_MediaWinList.Length . " open window(s) - pick one and Map window")
}

MediaUI_MapSelectedWindow() {
    global g_MediaCtl, g_MediaWinList
    idx := g_MediaCtl["winDD"].Value
    if (!idx || idx > g_MediaWinList.Length) {
        MediaUI_EnvStatus("Pick a window from the dropdown (R refreshes the list)")
        return
    }
    w := g_MediaWinList[idx]
    if !WinExist("ahk_id " . w["hwnd"]) {
        MediaUI_EnvStatus("That window has closed - press R to refresh")
        return
    }
    MediaUI_EnvStatus("Mapping window: " . SubStr(w["title"], 1, 60))
    MediaUI_ShowMap(Env_MapWindow(w["hwnd"]))
}

; List monitors (with size/primary) into the dropdown.
MediaUI_RefreshMonitors() {
    global g_MediaCtl, g_MediaMonList
    g_MediaMonList := []
    items := []
    cnt := MonitorGetCount()
    primary := MonitorGetPrimary()
    Loop cnt {
        n := A_Index
        MonitorGet(n, &l, &t, &r, &b)
        g_MediaMonList.Push(Map("x", l, "y", t, "w", r - l, "h", b - t))
        items.Push("Monitor " . n . (n = primary ? " (primary)" : "") . "  " . (r - l) . "x" . (b - t))
    }
    dd := g_MediaCtl["monDD"]
    dd.Delete()
    if items.Length {
        dd.Add(items)
        dd.Choose(primary >= 1 ? primary : 1)
    }
}

MediaUI_MapMonitor() {
    global g_MediaCtl, g_MediaMonList
    idx := g_MediaCtl["monDD"].Value
    if (!idx || idx > g_MediaMonList.Length) {
        MediaUI_EnvStatus("Pick a monitor")
        return
    }
    m := g_MediaMonList[idx]
    MediaUI_EnvStatus("Mapping monitor " . idx . " (" . m["w"] . "x" . m["h"] . ")...")
    MediaUI_ShowMap(Env_MapRegion(Map("x", m["x"], "y", m["y"], "w", m["w"], "h", m["h"])))
}

MediaUI_MapRegion() {
    sel := ""
    try sel := QuickOCR_SelectRegion()
    if (!IsObject(sel) || !sel.Count) {
        MediaUI_EnvStatus("Region unchanged")
        return
    }
    MediaUI_ShowMap(Env_MapRegion(sel))
}

MediaUI_MapImage() {
    path := ""
    try path := FileSelect(1, , "Choose an image", "Images (*.png; *.jpg; *.jpeg; *.bmp; *.webp)")
    if (path != "")
        MediaUI_ShowMap(Env_MapImage(path))
}

MediaUI_ShowMap(fm) {
    global g_MediaCtl, g_MediaEnvMap
    if (!fm.Has("ok") || !fm["ok"]) {
        MediaUI_EnvStatus("Map failed: " . (fm.Has("error") ? fm["error"] : "unknown"))
        return
    }
    g_MediaEnvMap := fm
    try Know_PersistEnvMap(fm)   ; accumulate in the Knowledge dashboard
    ; optional DeepSeek refine
    extra := ""
    if (g_MediaCtl["envRefine"].Value && StudyLLM_HasKey() && fm.Has("image") && fm["image"] != "") {
        MediaUI_EnvStatus("Refining roles with DeepSeek...")
        ref := Env_RefineWithVision(fm)
        if ref["ok"]
            fm["vision"] := ref["value"], extra := ", vision-refined"
    }
    lv := g_MediaCtl["regions"]
    lv.Opt("-Redraw"), lv.Delete()
    for , r in fm["regions"]
        lv.Add(, r["id"], r["role"], SubStr(r["text"], 1, 160), r["x"], r["y"], r["w"], r["h"])
    lv.Opt("+Redraw")
    MediaUI_EnvStatus(fm["regionCount"] . " region(s), " . fm["controlCount"]
        . " control(s)" . extra . "  [" . fm["kind"] . "]")
}

MediaUI_EnvExport() {
    global g_MediaEnvMap
    if (!IsObject(g_MediaEnvMap) || !g_MediaEnvMap.Has("ok")) {
        MediaUI_EnvStatus("Map something first")
        return
    }
    path := Env_ExportJson(g_MediaEnvMap)
    MediaUI_EnvStatus("Saved: " . path)
    try Run('explorer.exe /select,"' . path . '"')
}

MediaUI_EnvStatus(msg) {
    global g_MediaCtl
    try g_MediaCtl["envStatus"].Value := msg
}

; Playback: flash the selected region's bounds on screen so you can confirm the
; map lines up with the real element. Screen-anchored maps (window/region) only.
MediaUI_RegionSelected(row) {
    global g_MediaEnvMap
    if (!IsObject(g_MediaEnvMap) || !g_MediaEnvMap.Has("regions"))
        return
    regs := g_MediaEnvMap["regions"]
    if (row < 1 || row > regs.Length)
        return
    rg := regs[row]
    if (g_MediaEnvMap.Has("kind") && g_MediaEnvMap["kind"] = "image") {
        MediaUI_EnvStatus("Region " . rg["id"] . " [" . rg["role"]
            . "] - image map has no screen position to flash")
        return
    }
    try FlashHighlight(rg["x"], rg["y"], rg["w"], rg["h"], 3, 220, "match")
    MediaUI_EnvStatus("Playback: region " . rg["id"] . " [" . rg["role"] . "]  "
        . rg["x"] . "," . rg["y"] . " " . rg["w"] . "x" . rg["h"])
}

; ── settings ──────────────────────────────────────────────────────────────
MediaUI_SaveFfmpeg() {
    global g_MediaFfmpeg, g_MediaFfprobe, g_MediaCtl
    p := Trim(g_MediaCtl["ffpath"].Value)
    Media_SetSetting("ffmpeg_path", p)
    ; also point ffprobe next to it if present
    if (p != "") {
        SplitPath(p, , &dir)
        probe := dir . "\ffprobe.exe"
        if FileExist(probe)
            Media_SetSetting("ffprobe_path", probe)
    }
    g_MediaFfmpeg := "", g_MediaFfprobe := ""   ; force re-resolve
    MediaUI_RefreshFfLine()
    MediaUI_Status("ffmpeg path saved")
}

MediaUI_Probe() {
    res := StudyLLM_Probe()
    MediaUI_Status("Provider: " . res["detail"])
}
