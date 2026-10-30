; ═══════════════════════════════════════════════════════════════════════════════
; MediaPipeline.ahk - Programmatic video/media processing with DeepSeek Flash
; ═══════════════════════════════════════════════════════════════════════════════
; Implements the frame-sampling architecture: decode a video with FFmpeg, sample
; frames (by FPS or scene change), timestamp them, analyze batches with the
; vision model (MediaLLM.ahk), and assemble the observations into a timeline /
; JSON database stored in SQLite. It also *creates* derived media: contact
; sheets, highlight clips, and chapter metadata.
;
; Storage (shared tracking DB, TrackDB()):
;   media_job(id, created_ts, kind, source_path, title, fps, frame_count,
;             status, summary, cost_usd)
;   media_frame(id, job_id, idx, ts_ms, path)
;   media_event(id, job_id, ts_ms, label, description, category, confidence,
;               frame_idx)
;   media_setting(key, value)
;
; FFmpeg/ffprobe are required for extraction and media creation; the analysis,
; timeline, storage and export logic work without them and are unit-tested.
; ═══════════════════════════════════════════════════════════════════════════════

global g_MediaFfmpeg := ""        ; resolved ffmpeg path (memoized)
global g_MediaFfprobe := ""
global g_MediaSchemaReady := false
global g_MediaCancel := false

; ─────────────────────────────────────────────────────────────────────────────
; PATHS + SCHEMA + SETTINGS
; ─────────────────────────────────────────────────────────────────────────────
Media_OutDir() {
    global DATA_DIR
    d := DATA_DIR . "\media"
    if !DirExist(d)
        try DirCreate(d)
    return d
}
Media_TempDir() {
    global DATA_DIR
    d := DATA_DIR . "\media_tmp"
    if !DirExist(d)
        try DirCreate(d)
    return d
}

Media_Schema() {
    global g_MediaSchemaReady
    if g_MediaSchemaReady
        return true
    db := TrackDB()
    if !db
        return false
    try {
        db.Exec("CREATE TABLE IF NOT EXISTS media_setting(key TEXT PRIMARY KEY, value TEXT)")
        db.Exec("CREATE TABLE IF NOT EXISTS media_job ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT, created_ts TEXT, kind TEXT,"
              . "source_path TEXT, title TEXT, fps REAL DEFAULT 1, frame_count INTEGER DEFAULT 0,"
              . "status TEXT DEFAULT 'new', summary TEXT DEFAULT '', cost_usd REAL DEFAULT 0)")
        db.Exec("CREATE TABLE IF NOT EXISTS media_frame ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT, job_id INTEGER, idx INTEGER,"
              . "ts_ms INTEGER, path TEXT)")
        db.Exec("CREATE INDEX IF NOT EXISTS ix_mframe_job ON media_frame(job_id)")
        db.Exec("CREATE TABLE IF NOT EXISTS media_event ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT, job_id INTEGER, ts_ms INTEGER,"
              . "label TEXT, description TEXT, category TEXT DEFAULT '',"
              . "confidence REAL DEFAULT 0, frame_idx INTEGER DEFAULT 0)")
        db.Exec("CREATE INDEX IF NOT EXISTS ix_mevent_job ON media_event(job_id, ts_ms)")
    } catch as err {
        TrackLogError("Media_Schema", err)
        return false
    }
    g_MediaSchemaReady := true
    return true
}

Media_SetSetting(key, value) {
    if Media_Schema()
        TrackDB().Run("INSERT INTO media_setting(key,value) VALUES(?,?) "
                    . "ON CONFLICT(key) DO UPDATE SET value=excluded.value", key, value)
}
Media_GetSetting(key, default := "") {
    if !Media_Schema()
        return default
    v := TrackDB().Scalar("SELECT value FROM media_setting WHERE key=?", key)
    return (v = "" && !IsNumber(v)) ? default : v
}

; ─────────────────────────────────────────────────────────────────────────────
; FFMPEG RESOLUTION + RUN
; ─────────────────────────────────────────────────────────────────────────────
Media_FfmpegExe() {
    global g_MediaFfmpeg
    if (g_MediaFfmpeg != "")
        return g_MediaFfmpeg
    g_MediaFfmpeg := Media_ResolveExe("ffmpeg", "ffmpeg_path")
    return g_MediaFfmpeg
}
Media_FfprobeExe() {
    global g_MediaFfprobe
    if (g_MediaFfprobe != "")
        return g_MediaFfprobe
    g_MediaFfprobe := Media_ResolveExe("ffprobe", "ffprobe_path")
    return g_MediaFfprobe
}

Media_ResolveExe(name, settingKey) {
    ; 1. explicit setting
    p := Media_GetSetting(settingKey, "")
    if (p != "" && FileExist(p))
        return p
    ; 2. common install locations, modern builds FIRST. The ffmpeg in
    ; %LOCALAPPDATA%\Python\bin on this machine is an ancient 2013 build that
    ; rejects modern codecs/options, so Chocolatey's current build is preferred.
    cands := [
        "C:\ProgramData\chocolatey\lib\ffmpeg\tools\ffmpeg\bin\" . name . ".exe",
        "C:\ProgramData\chocolatey\bin\" . name . ".exe",
        "C:\ffmpeg\bin\" . name . ".exe",
        A_ProgramFiles . "\ffmpeg\bin\" . name . ".exe",
        EnvGet("LOCALAPPDATA") . "\Python\bin\" . name . ".exe" ]
    for , c in cands
        if (c != "" && FileExist(c))
            return c
    ; 3. PATH lookup via 'where'
    try {
        tmp := Media_TempDir() . "\which_" . name . ".txt"
        RunWait(A_ComSpec . ' /c where ' . name . ' > "' . tmp . '" 2>nul', , "Hide")
        if FileExist(tmp) {
            txt := FileRead(tmp)
            try FileDelete(tmp)
            for , ln in StrSplit(txt, "`n", "`r") {
                ln := Trim(ln)
                if (ln != "" && FileExist(ln))
                    return ln
            }
        }
    }
    return ""   ; not found
}

Media_FfmpegAvailable() => Media_FfmpegExe() != ""

; Run an exe with an argument line, capturing combined stdout+stderr.
; Returns Map(code, out). The command is written to a temporary .cmd file and
; run from there, which avoids the nested-quote breakage of `cmd /c "" ... ""`
; when the arguments themselves contain quoted paths and filter expressions.
Media_RunCapture(exe, argsLine) {
    out := Map("code", -1, "out", "")
    if (exe = "" || !FileExist(exe))
        return out
    stamp := A_TickCount . "_" . Random(1000, 9999)
    d := Media_TempDir()
    outFile := d . "\run_" . stamp . ".txt"
    batFile := d . "\run_" . stamp . ".cmd"
    try {
        f := FileOpen(batFile, "w")
        f.Write("@echo off`r`n")
        f.Write('"' . exe . '" ' . argsLine . ' > "' . outFile . '" 2>&1`r`n')
        f.Close()
    } catch {
        return out
    }
    code := -1
    try code := RunWait(A_ComSpec . ' /c "' . batFile . '"', , "Hide")
    out["code"] := code
    if FileExist(outFile) {
        try out["out"] := FileRead(outFile)
    }
    try FileDelete(outFile)
    try FileDelete(batFile)
    return out
}

Media_CancelAll() {
    global g_MediaCancel
    g_MediaCancel := true
}

; ─────────────────────────────────────────────────────────────────────────────
; PROBE + SAMPLING PLAN
; ─────────────────────────────────────────────────────────────────────────────
; Duration in seconds (0 on failure).
Media_ProbeDuration(path) {
    exe := Media_FfprobeExe()
    if (exe = "" || !FileExist(path))
        return 0
    r := Media_RunCapture(exe, '-v error -show_entries format=duration '
        . '-of default=nk=1:nw=1 "' . path . '"')
    val := Trim(r["out"])
    return IsNumber(val) ? (val + 0.0) : 0
}

; How many frames a plan produces (pure - used for a pre-extract estimate).
Media_SamplingPlan(durationSec, fps) {
    if (durationSec <= 0 || fps <= 0)
        return Map("frames", 0, "fps", fps, "duration", durationSec)
    n := Floor(durationSec * fps) + 1
    return Map("frames", n, "fps", fps, "duration", durationSec)
}

Media_FrameLabel(idx, tsMs) {
    secs := tsMs / 1000.0
    return "frame " . idx . "  t=" . Format("{:.2f}", secs) . "s (" . tsMs . "ms)"
}

; ─────────────────────────────────────────────────────────────────────────────
; FRAME EXTRACTION
; ─────────────────────────────────────────────────────────────────────────────
; Sample at a fixed FPS. Returns Map(ok, frames, error). frames = array of
; Map(idx, ts_ms, path).
Media_ExtractFrames(path, fps := 1, maxFrames := 240) {
    out := Map("ok", false, "frames", [], "error", "")
    exe := Media_FfmpegExe()
    if (exe = "")
        return (out["error"] := "ffmpeg not found - set its path in the tab", out)
    if !FileExist(path)
        return (out["error"] := "source not found: " . path, out)
    dir := Media_TempDir() . "\frames_" . A_TickCount
    try DirCreate(dir)
    args := '-y -i "' . path . '" -vf fps=' . fps
          . ' -frames:v ' . maxFrames . ' -q:v 3 "' . dir . '\frame_%06d.jpg"'
    r := Media_RunCapture(exe, args)
    frames := Media_CollectFrames(dir, "frame_", fps)
    if !frames.Length
        return (out["error"] := "no frames extracted (ffmpeg code " . r["code"] . ")", out)
    out["ok"] := true
    out["frames"] := frames
    return out
}

; Sample on scene change. Returns the same shape; timestamps come from ffmpeg's
; showinfo pts_time so they are real positions, not a fixed cadence.
Media_ExtractSceneFrames(path, threshold := 0.3, maxFrames := 120) {
    out := Map("ok", false, "frames", [], "error", "")
    exe := Media_FfmpegExe()
    if (exe = "")
        return (out["error"] := "ffmpeg not found", out)
    if !FileExist(path)
        return (out["error"] := "source not found", out)
    dir := Media_TempDir() . "\scenes_" . A_TickCount
    try DirCreate(dir)
    ; Escape the comma inside gt(scene,THRESH) so ffmpeg does not read it as a
    ; filter separator. No single quotes (they do not survive the Windows shell).
    args := '-y -i "' . path . '" '
          . '-vf "select=gt(scene\,' . threshold . '),showinfo" '
          . '-vsync vfr -frames:v ' . maxFrames . ' "' . dir . '\scene_%06d.jpg"'
    r := Media_RunCapture(exe, args)
    ; pts_time values appear in showinfo stderr, one per emitted frame, in order.
    times := []
    pos := 1
    while (pos := RegExMatch(r["out"], "pts_time:([\d.]+)", &m, pos)) {
        times.Push(Round((m[1] + 0.0) * 1000))
        pos += StrLen(m[0])
    }
    files := Media_ListSorted(dir, "scene_")
    ; A video with no hard cuts yields no scene frames - fall back to 1 FPS
    ; sampling so the analysis still runs instead of failing.
    if !files.Length
        return Media_ExtractFrames(path, 1, maxFrames)
    frames := []
    for i, f in files {
        frames.Push(Map("idx", i, "ts_ms", (i <= times.Length ? times[i] : 0), "path", f))
    }
    out["ok"] := true
    out["frames"] := frames
    return out
}

Media_CollectFrames(dir, prefix, fps) {
    files := Media_ListSorted(dir, prefix)
    frames := []
    for i, f in files
        frames.Push(Map("idx", i, "ts_ms", Round((i - 1) * 1000 / fps), "path", f))
    return frames
}

Media_ListSorted(dir, prefix) {
    files := []
    try {
        Loop Files, dir . "\" . prefix . "*.jpg"
            files.Push(A_LoopFilePath)
    }
    ; filenames are zero-padded, so a plain string sort is chronological
    Loop files.Length {
        i := A_Index, j := i
        while (j > 1 && StrCompare(files[j], files[j - 1]) < 0) {
            tmp := files[j], files[j] := files[j - 1], files[j - 1] := tmp
            j--
        }
    }
    return files
}

; ─────────────────────────────────────────────────────────────────────────────
; JOB LIFECYCLE
; ─────────────────────────────────────────────────────────────────────────────
Media_NewJob(kind, sourcePath, title, fps) {
    if !Media_Schema()
        return 0
    db := TrackDB()
    db.Run("INSERT INTO media_job(created_ts,kind,source_path,title,fps,status) "
         . "VALUES(?,?,?,?,?, 'new')"
         , FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"), kind, sourcePath, title, fps)
    return db.LastInsertId()
}

Media_StoreFrames(jobId, frames) {
    if (!jobId || !Media_Schema())
        return
    db := TrackDB()
    db.Begin()
    try {
        for , f in frames
            db.Run("INSERT INTO media_frame(job_id,idx,ts_ms,path) VALUES(?,?,?,?)"
                 , jobId, f["idx"], f["ts_ms"], f["path"])
        db.Run("UPDATE media_job SET frame_count=?, status='frames' WHERE id=?"
             , frames.Length, jobId)
        db.Commit()
    } catch as err {
        db.Rollback()
        TrackLogError("Media_StoreFrames", err)
    }
}

Media_Frames(jobId) {
    if !Media_Schema()
        return []
    return TrackDB().Query("SELECT * FROM media_frame WHERE job_id=? ORDER BY idx", jobId)
}

; ─────────────────────────────────────────────────────────────────────────────
; ANALYSIS - batch frames to the vision model, assemble a timeline
; ─────────────────────────────────────────────────────────────────────────────
; question: what to look for (e.g. "describe the key actions and UI states").
; Returns Map(ok, events, cost, batches, error).
Media_AnalyzeJob(jobId, question := "", batchSize := 8) {
    global g_MediaCancel
    g_MediaCancel := false
    out := Map("ok", false, "events", [], "cost", 0.0, "batches", 0, "error", "")
    if !Media_Schema()
        return (out["error"] := "media DB unavailable", out)
    frames := Media_Frames(jobId)
    if !frames.Length
        return (out["error"] := "no frames stored for this job", out)
    if (batchSize < 1)
        batchSize := 8
    if (batchSize > 16)
        batchSize := 16

    allEvents := [], totalCost := 0.0, batches := 0
    i := 1
    while (i <= frames.Length) {
        if g_MediaCancel {
            out["error"] := "cancelled"
            break
        }
        batch := [], labels := ""
        j := i
        while (j <= frames.Length && (j - i) < batchSize) {
            f := frames[j]
            batch.Push(Map("path", f["path"], "label", Media_FrameLabel(f["idx"], f["ts_ms"])))
            labels .= (labels = "" ? "" : ", ") . f["ts_ms"]
            j++
        }
        instr := (question != "" ? question . "`n`n" : "")
               . "These are timestamped frames sampled from one video. Identify the "
               . "distinct events/actions/states visible across them. Return a JSON array; "
               . 'each element: {"ts_ms": <int ms from the labels>, "label": <short>, '
               . '"description": <one sentence>, "category": <word>, '
               . '"confidence": <0..1>}. Only real, visible events.'
        res := MediaLLM_AnalyzeJson(batch, instr, Map("maxTokens", 1100))
        batches++
        if !res["ok"] {
            out["error"] := res["error"]
            break
        }
        totalCost += res["costUSD"]
        for , ev in Media_EventsFromValue(res["value"])
            allEvents.Push(ev)
        i := j
    }

    ; persist events + job summary
    Media_StoreEvents(jobId, allEvents)
    db := TrackDB()
    summary := allEvents.Length . " event(s) across " . batches . " batch(es)"
    db.Run("UPDATE media_job SET status=?, summary=?, cost_usd=cost_usd+? WHERE id=?"
         , (out["error"] = "" ? "analyzed" : "partial"), summary, totalCost, jobId)

    out["ok"] := (out["error"] = "")
    out["events"] := allEvents
    out["cost"] := totalCost
    out["batches"] := batches
    return out
}

; Normalize the model's decoded JSON into event Maps. Accepts an array, or an
; object with an "events"/"timeline" array.
Media_EventsFromValue(value) {
    arr := []
    if (value is Array)
        arr := value
    else if (value is Map) {
        for , k in ["events", "timeline", "items", "results"] {
            if (value.Has(k) && value[k] is Array) {
                arr := value[k]
                break
            }
        }
    }
    out := []
    for , e in arr {
        if !(e is Map)
            continue
        out.Push(Map(
            "ts_ms", Media_AsMs(Media_Field(e, ["ts_ms", "ts", "time", "timestamp"], 0)),
            "label", "" . Media_Field(e, ["label", "title", "name"], ""),
            "description", "" . Media_Field(e, ["description", "desc", "summary", "detail"], ""),
            "category", "" . Media_Field(e, ["category", "type", "kind"], ""),
            "confidence", Media_AsNum(Media_Field(e, ["confidence", "conf", "score"], 0))))
    }
    return out
}

Media_Field(m, keys, default) {
    for , k in keys
        if (m.Has(k))
            return m[k]
    return default
}

; Accept ms ints, seconds floats, or "mm:ss"/"hh:mm:ss" strings -> ms.
Media_AsMs(v) {
    if (v is Integer)
        return v
    if (v is Float)
        return Round(v * (v < 1000 ? 1000 : 1))   ; small float = seconds
    s := Trim("" . v)
    if (s = "")
        return 0
    if RegExMatch(s, "^(\d+):(\d{1,2})(?::(\d{1,2}))?") {
        parts := StrSplit(s, ":")
        if (parts.Length = 2)
            return (Integer(parts[1]) * 60 + Integer(parts[2])) * 1000
        if (parts.Length = 3)
            return (Integer(parts[1]) * 3600 + Integer(parts[2]) * 60 + Integer(parts[3])) * 1000
    }
    if IsNumber(s)
        return (s + 0.0) < 1000 ? Round((s + 0.0) * 1000) : Round(s + 0.0)
    return 0
}
Media_AsNum(v) => IsNumber(v) ? (v + 0.0) : 0

Media_StoreEvents(jobId, events) {
    if (!jobId || !events.Length || !Media_Schema())
        return
    db := TrackDB()
    db.Begin()
    try {
        for , e in events
            db.Run("INSERT INTO media_event(job_id,ts_ms,label,description,category,confidence) "
                 . "VALUES(?,?,?,?,?,?)"
                 , jobId, e["ts_ms"], e["label"], e["description"], e["category"], e["confidence"])
        db.Commit()
    } catch as err {
        db.Rollback()
        TrackLogError("Media_StoreEvents", err)
    }
}

Media_Timeline(jobId) {
    if !Media_Schema()
        return []
    return TrackDB().Query("SELECT * FROM media_event WHERE job_id=? ORDER BY ts_ms, id", jobId)
}

Media_Jobs() {
    if !Media_Schema()
        return []
    return TrackDB().Query("SELECT * FROM media_job ORDER BY id DESC LIMIT 500")
}

; ─────────────────────────────────────────────────────────────────────────────
; EXPORTS
; ─────────────────────────────────────────────────────────────────────────────
Media_ExportTimelineJson(jobId, path := "") {
    if !Media_Schema()
        return ""
    job := TrackDB().QueryRow("SELECT * FROM media_job WHERE id=?", jobId)
    if !job.Count
        return ""
    events := []
    for , e in Media_Timeline(jobId)
        events.Push(Map("ts_ms", e["ts_ms"], "time", Media_FmtMs(e["ts_ms"])
                      , "label", e["label"], "description", e["description"]
                      , "category", e["category"], "confidence", e["confidence"]))
    doc := Map("job", job["id"], "title", job["title"], "source", job["source_path"]
             , "fps", job["fps"], "frames", job["frame_count"], "events", events)
    if (path = "")
        path := Media_OutDir() . "\timeline_" . jobId . "_" . FormatTime(A_Now, "yyyyMMdd_HHmmss") . ".json"
    Track_WriteFile(path, TrackJsonEncode(doc, 2))
    return path
}

Media_ExportReport(jobId, path := "") {
    if !Media_Schema()
        return ""
    job := TrackDB().QueryRow("SELECT * FROM media_job WHERE id=?", jobId)
    if !job.Count
        return ""
    md := "# Media timeline - " . (job["title"] != "" ? job["title"] : ("job " . jobId)) . "`r`n`r`n"
    md .= "Source: " . job["source_path"] . "  |  frames: " . job["frame_count"]
        . "  |  " . job["summary"] . "`r`n`r`n"
    for , e in Media_Timeline(jobId) {
        md .= "- **" . Media_FmtMs(e["ts_ms"]) . "** "
            . (e["category"] != "" ? "[" . e["category"] . "] " : "")
            . (e["label"] != "" ? e["label"] . " - " : "") . e["description"]
            . (e["confidence"] ? "  _(" . Round(e["confidence"] * 100) . "%)_" : "") . "`r`n"
    }
    if (path = "")
        path := Media_OutDir() . "\timeline_" . jobId . "_" . FormatTime(A_Now, "yyyyMMdd_HHmmss") . ".md"
    Track_WriteFile(path, md)
    return path
}

Media_FmtMs(ms) {
    ms := Integer(ms)
    s := ms // 1000
    return Format("{:02}:{:02}", s // 60, Mod(s, 60))
}

; ─────────────────────────────────────────────────────────────────────────────
; MEDIA CREATION (derived artifacts via ffmpeg)
; ─────────────────────────────────────────────────────────────────────────────
; A tiled contact sheet of a job's frames. cols/rows bound the tile grid.
Media_ContactSheet(jobId, cols := 5, outPath := "") {
    exe := Media_FfmpegExe()
    if (exe = "")
        return Map("ok", false, "error", "ffmpeg not found")
    frames := Media_Frames(jobId)
    if !frames.Length
        return Map("ok", false, "error", "no frames")
    ; Build a frame list file so ffmpeg tiles exactly the stored frames.
    listDir := frames[1]["path"]
    SplitPath(listDir, , &srcDir)
    rows := Ceil(frames.Length / cols)
    if (outPath = "")
        outPath := Media_OutDir() . "\contactsheet_" . jobId . ".jpg"
    ; Use the glob of the source dir (frames share one dir per extraction run).
    args := '-y -pattern_type sequence -i "' . srcDir . '\frame_%06d.jpg" '
          . '-vf "scale=320:-1,tile=' . cols . 'x' . rows . '" -frames:v 1 -q:v 3 "' . outPath . '"'
    r := Media_RunCapture(exe, args)
    return FileExist(outPath)
        ? Map("ok", true, "path", outPath)
        : Map("ok", false, "error", "ffmpeg code " . r["code"])
}

; Cut a clip [startMs, endMs] from a source video (stream copy where possible).
Media_HighlightClip(srcPath, startMs, endMs, outPath := "") {
    exe := Media_FfmpegExe()
    if (exe = "")
        return Map("ok", false, "error", "ffmpeg not found")
    if !FileExist(srcPath)
        return Map("ok", false, "error", "source not found")
    dur := (endMs - startMs) / 1000.0
    if (dur <= 0)
        return Map("ok", false, "error", "end must be after start")
    if (outPath = "")
        outPath := Media_OutDir() . "\clip_" . startMs . "_" . endMs . ".mp4"
    ss := Format("{:.3f}", startMs / 1000.0)
    args := '-y -ss ' . ss . ' -i "' . srcPath . '" -t '
          . Format("{:.3f}", dur) . ' -c copy "' . outPath . '"'
    r := Media_RunCapture(exe, args)
    if !FileExist(outPath) {
        ; stream-copy can fail on non-keyframe cuts; re-encode as a fallback
        args := '-y -ss ' . ss . ' -i "' . srcPath . '" -t '
              . Format("{:.3f}", dur) . ' -c:v libx264 -c:a aac "' . outPath . '"'
        r := Media_RunCapture(exe, args)
    }
    return FileExist(outPath)
        ? Map("ok", true, "path", outPath)
        : Map("ok", false, "error", "ffmpeg code " . r["code"])
}

; FFMETADATA chapters file from a job's events (import with ffmpeg -i in, -i meta).
Media_ChaptersFile(jobId, path := "") {
    events := Media_Timeline(jobId)
    if !events.Length
        return ""
    meta := ";FFMETADATA1`n"
    n := events.Length
    for i, e in events {
        startMs := Integer(e["ts_ms"])
        endMs := (i < n) ? Integer(events[i + 1]["ts_ms"]) : startMs + 2000
        if (endMs <= startMs)
            endMs := startMs + 1000
        title := e["label"] != "" ? e["label"] : e["description"]
        title := StrReplace(StrReplace(title, "=", " "), "`n", " ")
        meta .= "[CHAPTER]`nTIMEBASE=1/1000`nSTART=" . startMs . "`nEND=" . endMs
              . "`ntitle=" . SubStr(title, 1, 80) . "`n"
    }
    if (path = "")
        path := Media_OutDir() . "\chapters_" . jobId . ".txt"
    Track_WriteFile(path, meta)
    return path
}
