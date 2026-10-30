; ═══════════════════════════════════════════════════════════════════════════════
; Scribe.ahk - Visual workflow capture ("playbacks") + DeepSeek reasoning
; ═══════════════════════════════════════════════════════════════════════════════
; Like the Scribe browser extension: while RECORDING, every element interaction
; (a click on a button, menu item, field, ...) is captured as a step - the
; element's accessibility name/role/bounds plus a cropped screenshot "frame"
; around the pointer. An ordered run of steps is an EPISODE (a playback). Episodes
; split on a time gap or a window change; consecutive episodes form cross-window
; CHAINS (whole workflows).
;
; The textual playback (step list) + the frames are what the reasoner feeds to
; DeepSeek: it deduces WHAT was accomplished and WHY, names the workflow, scores
; it, and suggests an optimization - information DeepSeek can certify against the
; captured evidence rather than guessing.
;
; Recording is explicit and off by default (Ctrl+Shift+R, or the Scribe tab), so
; it never captures or slows anything unless you ask it to. It uses pass-through
; (~) mouse hooks, so your clicks are never swallowed, and it ignores clicks on
; this app's own windows.
; ═══════════════════════════════════════════════════════════════════════════════

global g_ScribeOn := false
global g_ScribeEpId := 0
global g_ScribeSeq := 0
global g_ScribeLastTick := 0
global g_ScribeCurWin := ""
global g_ScribeGapMs := 8000       ; idle gap that starts a new episode
global g_ScribeSchemaReady := false

; ─────────────────────────────────────────────────────────────────────────────
; SCHEMA
; ─────────────────────────────────────────────────────────────────────────────
Scribe_Schema() {
    global g_ScribeSchemaReady
    if g_ScribeSchemaReady
        return true
    db := TrackDB()
    if !db
        return false
    try {
        db.Exec("CREATE TABLE IF NOT EXISTS scribe_episode ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT, started_ts TEXT, ended_ts TEXT,"
              . "title TEXT, window_title TEXT, window_app TEXT, step_count INTEGER DEFAULT 0,"
              . "status TEXT DEFAULT 'open', why TEXT DEFAULT '', workflow_name TEXT DEFAULT '',"
              . "score INTEGER DEFAULT 0, chain_id INTEGER DEFAULT 0)")
        db.Exec("CREATE TABLE IF NOT EXISTS scribe_step ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT, episode_id INTEGER, seq INTEGER, ts TEXT,"
              . "window_title TEXT, element_name TEXT, element_role TEXT, action TEXT,"
              . "x INTEGER, y INTEGER, w INTEGER, h INTEGER, frame_path TEXT, detail TEXT DEFAULT '')")
        db.Exec("CREATE INDEX IF NOT EXISTS ix_scribe_step_ep ON scribe_step(episode_id, seq)")
    } catch as err {
        TrackLogError("Scribe_Schema", err)
        return false
    }
    g_ScribeSchemaReady := true
    return true
}

Scribe_Dir(epId) {
    global DATA_DIR
    d := DATA_DIR . "\scribe\ep_" . epId
    if !DirExist(d)
        try DirCreate(d)
    return d
}

; ─────────────────────────────────────────────────────────────────────────────
; RECORDING
; ─────────────────────────────────────────────────────────────────────────────
Scribe_Start() {
    global g_ScribeOn, g_ScribeEpId, g_ScribeLastTick, g_ScribeCurWin
    if g_ScribeOn
        return true
    if !Scribe_Schema() {
        ShowStatus("Scribe: database unavailable", "fail")
        return false
    }
    g_ScribeOn := true
    g_ScribeEpId := 0
    g_ScribeLastTick := 0
    g_ScribeCurWin := ""
    ; Pass-through hooks: the click still happens, we just observe it.
    try Hotkey("~LButton", Scribe_ClickHook, "On")
    try Hotkey("~RButton", Scribe_ClickHook, "On")
    ShowStatus("Scribe RECORDING - interact with elements; Ctrl+Shift+R to stop", "ok")
    return true
}

Scribe_Stop() {
    global g_ScribeOn
    if !g_ScribeOn
        return
    g_ScribeOn := false
    try Hotkey("~LButton", "Off")
    try Hotkey("~RButton", "Off")
    Scribe_CloseEpisode()
    ShowStatus("Scribe stopped", "ok")
}

Scribe_Toggle() {
    global g_ScribeOn
    g_ScribeOn ? Scribe_Stop() : Scribe_Start()
}

Scribe_IsOn() {
    global g_ScribeOn
    return g_ScribeOn
}

; The click handler: grab position immediately, do the heavy capture off-thread
; so the click is never delayed.
Scribe_ClickHook(*) {
    global g_ScribeOn
    if !g_ScribeOn
        return
    MouseGetPos(&mx, &my, &hwnd)
    btn := InStr(A_ThisHotkey, "R") ? "right" : "left"
    SetTimer(Scribe_CaptureBound(mx, my, hwnd, btn), -1)
}

Scribe_CaptureBound(mx, my, hwnd, btn) {
    return () => Scribe_Capture(mx, my, hwnd, btn)
}

Scribe_Capture(mx, my, hwnd, btn) {
    global g_ScribeOn, g_ScribeEpId, g_ScribeSeq, g_ScribeLastTick, g_ScribeCurWin, g_ScribeGapMs
    if !g_ScribeOn
        return
    ; Ignore clicks on our own windows (the Scribe tab, dialogs, etc.).
    pid := 0
    try pid := WinGetPID("ahk_id " . hwnd)
    if (pid = DllCall("GetCurrentProcessId", "UInt"))
        return
    now := A_TickCount
    wtitle := "", wapp := ""
    try wtitle := WinGetTitle("ahk_id " . hwnd)
    try wapp := WinGetProcessName("ahk_id " . hwnd)

    ; Episode boundary: first step, a long idle gap, or a different window.
    if (g_ScribeEpId = 0
        || (g_ScribeLastTick && (now - g_ScribeLastTick) > g_ScribeGapMs)
        || (g_ScribeCurWin != "" && g_ScribeCurWin != wtitle)) {
        Scribe_CloseEpisode()
        Scribe_OpenEpisode(wtitle, wapp)
    }
    g_ScribeLastTick := now

    ; Identify the element under the pointer (accessibility).
    ename := "", erole := "", ex := mx, ey := my, ew := 0, eh := 0
    try {
        el := Acc.ElementFromPoint(mx, my)
        if IsObject(el) {
            try ename := el.Name
            try erole := el.RoleText
            try {
                loc := el.Location
                if IsObject(loc)
                    ex := loc.x, ey := loc.y, ew := loc.w, eh := loc.h
            }
        }
    }

    g_ScribeSeq++
    frame := Scribe_Frame(mx, my)
    db := TrackDB()
    now2 := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    try {
        db.Run("INSERT INTO scribe_step(episode_id,seq,ts,window_title,element_name,element_role,"
             . "action,x,y,w,h,frame_path,detail) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)"
             , g_ScribeEpId, g_ScribeSeq, now2, wtitle, "" . ename, "" . erole
             , btn . "-click", ex, ey, ew, eh, frame, "")
        db.Run("UPDATE scribe_episode SET ended_ts=?, step_count=? WHERE id=?"
             , now2, g_ScribeSeq, g_ScribeEpId)
    } catch as err {
        TrackLogError("Scribe_Capture", err)
    }
}

Scribe_OpenEpisode(wtitle, wapp) {
    global g_ScribeEpId, g_ScribeSeq, g_ScribeCurWin
    db := TrackDB()
    now := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    title := wtitle != "" ? wtitle : (wapp != "" ? wapp : "Workflow")
    db.Run("INSERT INTO scribe_episode(started_ts,ended_ts,title,window_title,window_app,status) "
         . "VALUES(?,?,?,?,?, 'open')", now, now, SubStr(title, 1, 120), wtitle, wapp)
    g_ScribeEpId := db.LastInsertId()
    g_ScribeSeq := 0
    g_ScribeCurWin := wtitle
}

Scribe_CloseEpisode() {
    global g_ScribeEpId, g_ScribeSeq
    if !g_ScribeEpId
        return
    db := TrackDB()
    ; Drop empty episodes rather than leave noise.
    if (g_ScribeSeq = 0) {
        try db.Run("DELETE FROM scribe_episode WHERE id=?", g_ScribeEpId)
    } else {
        try db.Run("UPDATE scribe_episode SET status='done' WHERE id=?", g_ScribeEpId)
    }
    g_ScribeEpId := 0
}

; Capture a cropped frame centered on the pointer (clamped to the virtual screen).
Scribe_Frame(mx, my) {
    global g_ScribeEpId, g_ScribeSeq
    w := 460, h := 320
    vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
    x := Max(vx, Min(mx - w // 2, vx + vw - w))
    y := Max(vy, Min(my - h // 2, vy + vh - h))
    path := Scribe_Dir(g_ScribeEpId) . "\step_" . Format("{:03}", g_ScribeSeq) . ".png"
    ok := false, pToken := 0, pBitmap := 0
    try {
        pToken := Gdip_Startup()
        pBitmap := Gdip_BitmapFromScreen(x . "|" . y . "|" . w . "|" . h)
        if pBitmap {
            ok := (Gdip_SaveBitmapToFile(pBitmap, path) = 0)
            Gdip_DisposeImage(pBitmap)
        }
    } catch {
    }
    if pToken
        try Gdip_Shutdown(pToken)
    return (ok && FileExist(path)) ? path : ""
}

; ─────────────────────────────────────────────────────────────────────────────
; PLAYBACK (textual representation of a frame sequence)
; ─────────────────────────────────────────────────────────────────────────────
Scribe_Episodes(limit := 500) {
    if !Scribe_Schema()
        return []
    return TrackDB().Query("SELECT * FROM scribe_episode WHERE step_count>0 "
        . "ORDER BY id DESC LIMIT " . limit)
}

Scribe_Steps(epId) {
    if !Scribe_Schema()
        return []
    return TrackDB().Query("SELECT * FROM scribe_step WHERE episode_id=? ORDER BY seq", epId)
}

Scribe_StepText(s) {
    el := (s["element_name"] != "") ? ("'" . s["element_name"] . "'") : "an element"
    role := (s["element_role"] != "") ? (" [" . s["element_role"] . "]") : ""
    return s["action"] . " " . el . role
}

Scribe_PlaybackText(epId) {
    steps := Scribe_Steps(epId)
    out := ""
    for i, s in steps
        out .= i . ". " . Scribe_StepText(s) . "`r`n"
    return out
}

; ─────────────────────────────────────────────────────────────────────────────
; CROSS-WINDOW CHAINS
; ─────────────────────────────────────────────────────────────────────────────
; Group consecutive episodes whose gaps are small into one chain (a whole
; workflow that may span several windows). Returns an array of chains, each a
; Map(episodes:[rows], windows:[...], cross: bool).
Scribe_Chains(maxGapSec := 90, limit := 200) {
    eps := []
    if Scribe_Schema()
        eps := TrackDB().Query("SELECT * FROM scribe_episode WHERE step_count>0 ORDER BY id ASC LIMIT " . limit)
    chains := [], cur := ""
    for , e in eps {
        if !IsObject(cur) {
            cur := Map("episodes", [e], "windows", Map(e["window_title"], 1))
            continue
        }
        gap := Scribe_GapSec(cur["episodes"][cur["episodes"].Length]["ended_ts"], e["started_ts"])
        if (gap >= 0 && gap <= maxGapSec) {
            cur["episodes"].Push(e)
            cur["windows"][e["window_title"]] := 1
        } else {
            chains.Push(cur)
            cur := Map("episodes", [e], "windows", Map(e["window_title"], 1))
        }
    }
    if IsObject(cur)
        chains.Push(cur)
    ; newest first; mark cross-window
    out := []
    i := chains.Length
    while (i >= 1) {
        c := chains[i]
        c["cross"] := c["windows"].Count > 1
        out.Push(c)
        i--
    }
    return out
}

Scribe_GapSec(endTs, startTs) {
    if (endTs = "" || startTs = "")
        return -1
    try {
        a := Scribe_ToStamp(endTs), b := Scribe_ToStamp(startTs)
        return DateDiff(b, a, "Seconds")
    }
    return -1
}
Scribe_ToStamp(ts) {
    ; "yyyy-MM-dd HH:mm:ss" -> yyyyMMddHHmmss
    return RegExReplace(ts, "[^0-9]", "")
}

; ─────────────────────────────────────────────────────────────────────────────
; DEEPSEEK REASONER
; ─────────────────────────────────────────────────────────────────────────────
; Deduce WHAT/WHY, name the workflow, score it, suggest an optimization, from the
; textual playback. (Text-only V1; frames are available for a future vision pass.)
Scribe_Explain(epId) {
    out := Map("ok", false, "text", "", "error", "")
    if !Scribe_Schema()
        return (out["error"] := "Scribe DB unavailable", out)
    ep := TrackDB().QueryRow("SELECT * FROM scribe_episode WHERE id=?", epId)
    if !ep.Count
        return (out["error"] := "episode not found", out)
    if !StudyLLM_HasKey()
        return (out["error"] := "No DeepSeek key (set one in Study Assistant)", out)
    pb := Scribe_PlaybackText(epId)
    if (Trim(pb) = "")
        return (out["error"] := "no steps to explain", out)
    prompt := "A captured sequence of Windows UI interactions (a workflow playback). "
            . "Window: " . ep["window_title"] . " (" . ep["window_app"] . ")`n`n"
            . "STEPS:`n" . pb . "`n"
            . "Deduce, grounded ONLY in these steps:`n"
            . "WHAT: one line - what was accomplished.`n"
            . "WHY: one line - the likely intent, relating later steps to earlier ones.`n"
            . "NAME: a short workflow name (<=6 words).`n"
            . "SCORE: a 1-5 reusability score.`n"
            . "OPTIMIZE: one faster path / hotkey / tool to do this."
    res := StudyLLM_Ask(prompt, Map("maxTokens", 700))
    if !res["ok"]
        return (out["error"] := res["error"], out)
    text := res["answer"]
    ; Pull the structured fields back out (best-effort).
    name := Scribe_Field(text, "NAME")
    why := Scribe_Field(text, "WHY")
    score := 0
    if RegExMatch(Scribe_Field(text, "SCORE"), "([1-5])", &m)
        score := Integer(m[1])
    try TrackDB().Run("UPDATE scribe_episode SET why=?, workflow_name=?, score=? WHERE id=?"
                    , why, name, score, epId)
    out["ok"] := true
    out["text"] := text
    out["cost"] := res["costUSD"]
    return out
}

Scribe_Field(text, label) {
    if RegExMatch(text, "im)^\s*" . label . "\s*[:\-]\s*(.+)$", &m)
        return Trim(m[1])
    return ""
}

; ─────────────────────────────────────────────────────────────────────────────
; EXPORT - a Scribe-style step-by-step guide (markdown with frame images)
; ─────────────────────────────────────────────────────────────────────────────
Scribe_ExportGuide(epId) {
    global DATA_DIR
    if !Scribe_Schema()
        return ""
    ep := TrackDB().QueryRow("SELECT * FROM scribe_episode WHERE id=?", epId)
    if !ep.Count
        return ""
    title := ep["workflow_name"] != "" ? ep["workflow_name"] : ep["title"]
    md := "# " . title . "`r`n`r`n"
    md .= "_Window: " . ep["window_title"] . "  |  captured " . ep["started_ts"] . "_`r`n`r`n"
    if (ep["why"] != "")
        md .= "**Purpose:** " . ep["why"] . "`r`n`r`n"
    for i, s in Scribe_Steps(epId) {
        md .= "## Step " . i . " - " . Scribe_StepText(s) . "`r`n`r`n"
        if (s["frame_path"] != "" && FileExist(s["frame_path"]))
            md .= "![step " . i . "](" . s["frame_path"] . ")`r`n`r`n"
    }
    base := DATA_DIR . "\scribe"
    if !DirExist(base)
        try DirCreate(base)
    path := base . "\guide_ep" . epId . "_" . FormatTime(A_Now, "yyyyMMdd_HHmmss") . ".md"
    Track_WriteFile(path, md)
    return path
}

Scribe_Clip(s, n) {
    s := StrReplace(StrReplace("" . s, "`r", " "), "`n", " ")
    return StrLen(s) > n ? SubStr(s, 1, n - 1) . "..." : s
}
