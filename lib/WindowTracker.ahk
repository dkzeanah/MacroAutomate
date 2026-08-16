; ═══════════════════════════════════════════════════════════════════════════════
; WindowTracker.ahk - Feature 1: window activation + focus time tracking
; ═══════════════════════════════════════════════════════════════════════════════
; Polls the foreground window, detects focus changes and accumulates wall-clock
; time against a *unique window name* (see TrackNormalizeWindowName). Time is
; written into win_session rows and rolled up into win.total_ms / app.total_ms.
;
; Design notes:
;   - The open interval is persisted immediately with duration 0 and extended on
;     a heartbeat, so an unexpected exit costs at most one heartbeat of data.
;   - Physical idle time (A_TimeIdlePhysical) is excluded: walking away from the
;     keyboard closes the interval instead of inflating it.
;   - The poll doubles as the shared "tracking context" refresh used by the
;     mouse and key trackers, so all three attribute data to the same win_id.
; ═══════════════════════════════════════════════════════════════════════════════

; ─── State ───────────────────────────────────────────────────────────────────
global g_WinTrackOn := false           ; Tracker enabled
global g_WinTrackPollMs := 500         ; Foreground poll interval
global g_WinTrackHeartbeatMs := 20000  ; How often an open interval is extended
global g_WinTrackIdleMs := 120000      ; Physical idle that closes an interval

global g_WinTrackSessId := 0           ; Open win_session row id
global g_WinTrackWinId := 0
global g_WinTrackAppId := 0
global g_WinTrackHwnd := 0
global g_WinTrackName := ""
global g_WinTrackTitle := ""
global g_WinTrackStartTs := ""
global g_WinTrackLastTick := 0         ; Tick at the last flush
global g_WinTrackLastBeat := 0         ; Tick at the last heartbeat write
global g_WinTrackIdling := false

; ─── Shared context consumed by the other trackers ───────────────────────────
global g_TrackCtx := Map("win_id", 0, "app_id", 0, "name", "", "title", ""
                       , "exe", "", "class", "", "hwnd", 0
                       , "x", 0, "y", 0, "w", 0, "h", 0, "tick", 0)

; ═══════════════════════════════════════════════════════════════════════════════
; PUBLIC CONTROL
; ═══════════════════════════════════════════════════════════════════════════════

WinTrack_Start() {
    global g_WinTrackOn, g_WinTrackPollMs, g_WinTrackLastTick, g_WinTrackLastBeat

    if !TrackDB_Ready() {
        if !TrackDB_Init()
            return false
    }
    if g_WinTrackOn
        return true

    g_WinTrackOn := true
    g_WinTrackLastTick := A_TickCount
    g_WinTrackLastBeat := A_TickCount
    SetTimer(WinTrack_Poll, g_WinTrackPollMs)
    WinTrack_Poll()      ; Attribute the current window right away
    return true
}

WinTrack_Stop() {
    global g_WinTrackOn
    if !g_WinTrackOn
        return
    SetTimer(WinTrack_Poll, 0)
    WinTrack_CloseSession()
    g_WinTrackOn := false
}

WinTrack_Toggle() {
    global g_WinTrackOn
    if g_WinTrackOn
        WinTrack_Stop()
    else
        WinTrack_Start()
    return g_WinTrackOn
}

WinTrack_IsOn() {
    global g_WinTrackOn
    return g_WinTrackOn
}

; ═══════════════════════════════════════════════════════════════════════════════
; SHARED CONTEXT
; ═══════════════════════════════════════════════════════════════════════════════

; Current tracking context. Refreshes on demand when stale (or when the window
; tracker is off), so the mouse/key trackers work standalone too.
TrackCtx_Get(maxAgeMs := 1000) {
    global g_TrackCtx
    if (A_TickCount - g_TrackCtx["tick"] > maxAgeMs)
        TrackCtx_Refresh()
    return g_TrackCtx
}

; Re-read the foreground window and resolve its database identity.
TrackCtx_Refresh() {
    global g_TrackCtx

    info := TrackGetActiveWindow()
    g_TrackCtx["tick"] := A_TickCount

    if !info["ok"] || !TrackDB_Ready() {
        g_TrackCtx["win_id"] := 0
        g_TrackCtx["app_id"] := 0
        g_TrackCtx["hwnd"] := info["hwnd"]
        g_TrackCtx["title"] := info["title"]
        return g_TrackCtx
    }

    ; Never track our own GUI - it would dominate every statistic.
    if (info["pid"] != 0 && info["pid"] = DllCall("GetCurrentProcessId", "UInt")) {
        g_TrackCtx["win_id"] := 0
        g_TrackCtx["app_id"] := 0
        g_TrackCtx["hwnd"] := info["hwnd"]
        g_TrackCtx["title"] := info["title"]
        g_TrackCtx["exe"] := info["exe"]
        g_TrackCtx["class"] := info["class"]
        g_TrackCtx["name"] := "(macro automator)"
        return g_TrackCtx
    }

    ident := TrackDB_ResolveWindow(info["title"], info["class"], info["exe"])
    g_TrackCtx["win_id"] := ident["win_id"]
    g_TrackCtx["app_id"] := ident["app_id"]
    g_TrackCtx["name"] := ident["name"]
    g_TrackCtx["title"] := info["title"]
    g_TrackCtx["exe"] := info["exe"]
    g_TrackCtx["class"] := info["class"]
    g_TrackCtx["hwnd"] := info["hwnd"]
    g_TrackCtx["x"] := info["x"], g_TrackCtx["y"] := info["y"]
    g_TrackCtx["w"] := info["w"], g_TrackCtx["h"] := info["h"]
    return g_TrackCtx
}

; ═══════════════════════════════════════════════════════════════════════════════
; POLL LOOP
; ═══════════════════════════════════════════════════════════════════════════════

WinTrack_Poll() {
    global g_WinTrackOn, g_WinTrackIdleMs, g_WinTrackIdling
    global g_WinTrackWinId, g_WinTrackHwnd, g_WinTrackLastBeat, g_WinTrackHeartbeatMs

    if !g_WinTrackOn
        return

    ; ─── Idle gate ───────────────────────────────────────────────────────────
    ; A_TimeIdlePhysical ignores synthetic input, so a running macro does not
    ; count as the user being present.
    idle := A_TimeIdlePhysical
    if (idle >= g_WinTrackIdleMs) {
        if !g_WinTrackIdling {
            ; Bank the time up to when input actually stopped, then close.
            WinTrack_Flush(idle)
            WinTrack_CloseSession()
            g_WinTrackIdling := true
        }
        return
    }
    if g_WinTrackIdling {
        g_WinTrackIdling := false
        WinTrack_ResetClock()
    }

    ctx := TrackCtx_Refresh()

    ; Untrackable foreground (our own GUI, desktop, or DB down): bank and idle.
    if !ctx["win_id"] {
        if g_WinTrackWinId {
            WinTrack_Flush(0)
            WinTrack_CloseSession()
        }
        return
    }

    ; ─── Focus change? ───────────────────────────────────────────────────────
    if (ctx["win_id"] != g_WinTrackWinId || ctx["hwnd"] != g_WinTrackHwnd) {
        WinTrack_Flush(0)
        WinTrack_CloseSession()
        WinTrack_OpenSession(ctx)
        return
    }

    ; ─── Same window: heartbeat the open interval ────────────────────────────
    if (A_TickCount - g_WinTrackLastBeat >= g_WinTrackHeartbeatMs) {
        WinTrack_Flush(0)
        g_WinTrackLastBeat := A_TickCount
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; SESSION LIFECYCLE
; ═══════════════════════════════════════════════════════════════════════════════

WinTrack_OpenSession(ctx) {
    global g_WinTrackSessId, g_WinTrackWinId, g_WinTrackAppId, g_WinTrackHwnd
    global g_WinTrackName, g_WinTrackTitle, g_WinTrackStartTs
    global g_WinTrackLastTick, g_WinTrackLastBeat

    if !ctx["win_id"]
        return

    g_WinTrackWinId := ctx["win_id"]
    g_WinTrackAppId := ctx["app_id"]
    g_WinTrackHwnd := ctx["hwnd"]
    g_WinTrackName := ctx["name"]
    g_WinTrackTitle := ctx["title"]
    g_WinTrackStartTs := TrackTS()
    g_WinTrackLastTick := A_TickCount
    g_WinTrackLastBeat := A_TickCount

    rect := Map("x", ctx["x"], "y", ctx["y"], "w", ctx["w"], "h", ctx["h"])
    try {
        g_WinTrackSessId := TrackDB_OpenSession(g_WinTrackWinId, g_WinTrackAppId
            , g_WinTrackHwnd, g_WinTrackTitle, g_WinTrackStartTs, rect)
    } catch as err {
        g_WinTrackSessId := 0
        TrackLogError("WinTrack_OpenSession", err)
    }

    ; Hand the new window to the per-window trackers.
    MouseTrack_OnWindowChange(ctx)
    KeyTrack_OnWindowChange(ctx)
}

; Write elapsed time since the last flush into the open interval.
; `excludeMs` trims trailing idle time that should not be credited.
WinTrack_Flush(excludeMs := 0) {
    global g_WinTrackSessId, g_WinTrackWinId, g_WinTrackAppId, g_WinTrackLastTick

    if !g_WinTrackSessId || !g_WinTrackWinId
        return 0

    now := A_TickCount
    delta := now - g_WinTrackLastTick
    if (excludeMs > 0)
        delta -= excludeMs
    if (delta <= 0) {
        g_WinTrackLastTick := now
        return 0
    }

    try {
        TrackDB_ExtendSession(g_WinTrackSessId, g_WinTrackWinId, g_WinTrackAppId
            , delta, TrackTS())
    } catch as err {
        TrackLogError("WinTrack_Flush", err)
    }
    g_WinTrackLastTick := now
    return delta
}

WinTrack_CloseSession() {
    global g_WinTrackSessId, g_WinTrackWinId, g_WinTrackAppId, g_WinTrackHwnd
    global g_WinTrackName, g_WinTrackTitle

    if !g_WinTrackSessId {
        g_WinTrackWinId := 0
        g_WinTrackHwnd := 0
        return
    }

    WinTrack_Flush(0)

    ; The per-window trackers must finalise their buckets before the window
    ; attribution changes.
    MouseTrack_FlushBucket()
    KeyTrack_FlushBucket()

    g_WinTrackSessId := 0
    g_WinTrackWinId := 0
    g_WinTrackAppId := 0
    g_WinTrackHwnd := 0
    g_WinTrackName := ""
    g_WinTrackTitle := ""
}

WinTrack_ResetClock() {
    global g_WinTrackLastTick, g_WinTrackLastBeat
    g_WinTrackLastTick := A_TickCount
    g_WinTrackLastBeat := A_TickCount
}

; ═══════════════════════════════════════════════════════════════════════════════
; STATUS / REPORTING
; ═══════════════════════════════════════════════════════════════════════════════

; One-line description of what the tracker is doing right now.
WinTrack_StatusLine() {
    global g_WinTrackOn, g_WinTrackName, g_WinTrackIdling, g_WinTrackStartTs, g_WinTrackLastTick

    if !g_WinTrackOn
        return "Window tracking: OFF"
    if g_WinTrackIdling
        return "Window tracking: idle (no physical input)"
    if (g_WinTrackName = "")
        return "Window tracking: ON (no trackable window)"
    return "Window tracking: " . TrackEllipsis(g_WinTrackName, 48)
}

; Total tracked time today, in milliseconds.
WinTrack_TodayMs() {
    db := TrackDB()
    if !db
        return 0
    v := db.Scalar("SELECT COALESCE(SUM(duration_ms),0) FROM win_session WHERE day = ?", TrackDayKey())
    return IsNumber(v) ? Integer(v) : 0
}

; Export the window-time leaderboard as CSV. Returns the path written.
WinTrack_ExportCsv(path, scope := "all") {
    rows := TrackDB_TopWindows(scope, 5000)
    out := "Window Name,Application,Executable,Total ms,Total,Activations,Last Seen`n"
    for r in rows {
        out .= TrackCsvRow([r["name"], r["app"], r["exe"], r["total_ms"]
                          , TrackFormatMs(r["total_ms"]), r["activations"], r["last_seen"]]) . "`n"
    }
    if FileExist(path)
        FileDelete(path)
    FileAppend(out, path, "UTF-8")
    return path
}

; ═══════════════════════════════════════════════════════════════════════════════
; ERROR SINK
; ═══════════════════════════════════════════════════════════════════════════════
; Trackers run on timers - an uncaught throw would silently kill the timer, so
; failures are funnelled here instead.

global g_TrackErrorLog := []
global g_TrackErrorCount := 0

TrackLogError(where, err) {
    global g_TrackErrorLog, g_TrackErrorCount, DATA_DIR
    g_TrackErrorCount++
    msg := TrackTS() . " [" . where . "] " . (IsObject(err) ? err.Message : String(err))
    g_TrackErrorLog.Push(msg)
    if (g_TrackErrorLog.Length > 200)
        g_TrackErrorLog.RemoveAt(1)
    try FileAppend(msg . "`n", DATA_DIR . "\tracking_errors.log", "UTF-8")
}
