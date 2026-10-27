; ═══════════════════════════════════════════════════════════════════════════════
; MediaBridge.ahk - Bridge to the avideditor ("Cutline") video engine
; ═══════════════════════════════════════════════════════════════════════════════
; Per the chosen architecture, avideditor's Python sidecar is THE video engine.
; This calls its analysis functions (OpenCV shot/cut/motion analysis, and more)
; through a thin shim (fan\bridge\cutline_bridge.py) run with avideditor's own
; venv python, so OpenCV/numpy/av are available. The /fan ffmpeg path
; (MediaPipeline.ahk) remains a fallback when the bridge is unavailable.
;
; The shim is one-shot: write params to a temp JSON, run the shim, read the
; result JSON. No stdio protocol or background server is needed.
; ═══════════════════════════════════════════════════════════════════════════════

global g_MediaBridgePy := ""

; Resolve the avideditor project root (setting override, then common locations).
MediaBridge_Root() {
    r := Media_GetSetting("avideditor_root", "")
    if (r != "" && DirExist(r))
        return r
    for , c in [A_Desktop . "\avideditor", "C:\Users\Don\Desktop\avideditor"
              , A_MyDocuments . "\avideditor"] {
        if (c != "" && DirExist(c))
            return c
    }
    return ""
}

; avideditor's venv python (has OpenCV). "" when not found.
MediaBridge_Python() {
    global g_MediaBridgePy
    if (g_MediaBridgePy != "" && FileExist(g_MediaBridgePy))
        return g_MediaBridgePy
    root := MediaBridge_Root()
    if (root = "")
        return ""
    for , p in [root . "\.venv\Scripts\python.exe", root . "\.venv\python.exe"] {
        if FileExist(p) {
            g_MediaBridgePy := p
            return p
        }
    }
    return ""
}

; The "python" folder that contains the `sidecar` package.
MediaBridge_PyDir() {
    root := MediaBridge_Root()
    return (root = "") ? "" : root . "\python"
}

; The shim ships inside this project.
MediaBridge_Shim() {
    global APP_ROOT
    return APP_ROOT . "\fan\bridge\cutline_bridge.py"
}

MediaBridge_Available() {
    return MediaBridge_Python() != "" && DirExist(MediaBridge_PyDir()) && FileExist(MediaBridge_Shim())
}

MediaBridge_Status() {
    if MediaBridge_Available()
        return "avideditor engine: " . MediaBridge_Python()
    root := MediaBridge_Root()
    if (root = "")
        return "avideditor engine: not found (set avideditor_root)"
    if (MediaBridge_Python() = "")
        return "avideditor found but no venv python at " . root . "\.venv"
    return "avideditor engine unavailable"
}

; Call one bridge method. params is a Map. Returns Map(ok, result, error).
; result is the decoded dict (Map) on success.
MediaBridge_Call(method, params) {
    out := Map("ok", false, "result", "", "error", "")
    py := MediaBridge_Python()
    pyDir := MediaBridge_PyDir()
    shim := MediaBridge_Shim()
    if (py = "" || pyDir = "" || !FileExist(shim))
        return (out["error"] := "avideditor sidecar not found (set avideditor_root in Media Intel)", out)

    stamp := A_TickCount . "_" . Random(1000, 9999)
    d := Media_TempDir()
    pf := d . "\bridge_in_" . stamp . ".json"
    of := d . "\bridge_out_" . stamp . ".json"
    try FileOpen(pf, "w", "UTF-8").Write(TrackJsonEncode(params))
    catch as err
        return (out["error"] := "could not write bridge params: " . err.Message, out)

    ; Reuse MediaPipeline's robust temp-.cmd runner.
    args := '"' . shim . '" "' . pyDir . '" ' . method . ' "' . pf . '" "' . of . '"'
    r := Media_RunCapture(py, args)

    if FileExist(of) {
        try {
            doc := TrackJsonDecode(FileRead(of, "UTF-8"))
            if (doc is Map) {
                out["ok"] := doc.Has("ok") && doc["ok"]
                out["result"] := doc.Has("result") ? doc["result"] : ""
                out["error"] := doc.Has("error") ? ("" . doc["error"]) : ""
            } else {
                out["error"] := "unexpected bridge output"
            }
        } catch as err {
            out["error"] := "bridge output parse failed: " . err.Message
        }
    } else {
        out["error"] := "bridge produced no output (python exit " . r["code"] . "): "
                      . TrackEllipsis(Trim(r["out"]), 240)
    }
    try FileDelete(pf)
    try FileDelete(of)
    return out
}

; Analyze a video through the avideditor engine. Returns Map(ok, result, error)
; where result = {duration, fps, shots:[{start,end}], cuts:[t], samples:[...], summary}.
MediaBridge_AnalyzeVideo(path) {
    if !FileExist(path)
        return Map("ok", false, "result", "", "error", "video not found: " . path)
    return MediaBridge_Call("analyze", Map("path", path, "use_cache", true))
}

; Store a Cutline analysis result into the media timeline as a job + events
; (one event per detected shot, plus the cut points). Returns the job id.
MediaBridge_StoreAnalysis(sourcePath, result) {
    if (!IsObject(result) || !Media_Schema())
        return 0
    SplitPath(sourcePath, &fname)
    fps := result.Has("fps") ? result["fps"] : 0
    jobId := Media_NewJob("cutline", sourcePath, fname, fps)

    events := []
    shots := result.Has("shots") && result["shots"] is Array ? result["shots"] : []
    n := 0
    for , s in shots {
        if !(s is Map)
            continue
        n++
        startMs := Round((s.Has("start") ? s["start"] : 0) * 1000)
        endMs := Round((s.Has("end") ? s["end"] : 0) * 1000)
        events.Push(Map("ts_ms", startMs, "label", "Shot " . n
                      , "description", "shot " . Format("{:.2f}", (s.Has("start") ? s["start"] : 0))
                      . "s - " . Format("{:.2f}", (s.Has("end") ? s["end"] : 0)) . "s"
                      , "category", "shot", "confidence", 1.0))
    }
    cuts := result.Has("cuts") && result["cuts"] is Array ? result["cuts"] : []
    for , c in cuts {
        events.Push(Map("ts_ms", Round((c + 0.0) * 1000), "label", "Cut"
                      , "description", "scene change at " . Format("{:.2f}", c + 0.0) . "s"
                      , "category", "cut", "confidence", 1.0))
    }
    Media_StoreEvents(jobId, events)

    ; Job summary from the engine's own summary block when present.
    sumParts := []
    sumParts.Push(shots.Length . " shots")
    sumParts.Push(cuts.Length . " cuts")
    if (result.Has("duration"))
        sumParts.Push(Format("{:.1f}", result["duration"] + 0.0) . "s")
    if (result.Has("samples") && result["samples"] is Array)
        sumParts.Push(result["samples"].Length . " samples")
    summary := "Cutline (OpenCV): " . Study_Join(sumParts, ", ")
    TrackDB().Run("UPDATE media_job SET status='analyzed', summary=? WHERE id=?", summary, jobId)
    return jobId
}
