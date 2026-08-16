; ═══════════════════════════════════════════════════════════════════════════════
; MouseTracker.ahk - Feature 2: per-window mouse movement capture
; ═══════════════════════════════════════════════════════════════════════════════
; Samples the pointer on a timer, attributes every sample to the currently
; tracked window, and writes one row per (window, minute) into mouse_snapshot.
;
; WHAT COMES OUT OF IT
;   heat map          aggregated grid of hits / clicks / dwell time
;   replay            re-drives the recorded path through MouseMove
;   feature extraction clusters dwell + click density into element candidates
;   export            JSON / CSV / Python / JavaScript / AHK for other tools
;
; ─── PATH BLOB FORMAT (v1) ───────────────────────────────────────────────────
;   "v1;t,x,y;t,x,y;..."
;     t  milliseconds since the start of the snapshot's minute (0-59999)
;     x  pointer X *relative to the window's top-left corner*
;     y  pointer Y relative to the window's top-left corner
;
;   Window-relative coordinates are what make the data portable: a recording
;   replays correctly after the window is moved, and normalising by the window
;   size makes it survive a resize.
;
;   Absolute (rather than delta) samples mean two blobs for the same minute can
;   simply be concatenated - which is exactly what the UPSERT in
;   TrackDB_AddMouseSnapshot does when a window is revisited within a minute.
;
; ─── CLICK BLOB FORMAT (v1) ──────────────────────────────────────────────────
;   "t,x,y,B;..."  with B = L | R | M
; ═══════════════════════════════════════════════════════════════════════════════

; ─── Configuration ───────────────────────────────────────────────────────────
global g_MouseTrackOn := false
global g_MouseSampleMs := 50          ; Sampling period (20 Hz)
global g_MouseMinMove := 2            ; Pixels of travel before a sample is kept
global g_MouseAnchorMs := 500         ; Force a sample at least this often
global g_MouseDwellRadius := 6        ; Pixels that still count as "not moving"
global g_MouseDwellMinMs := 350       ; Dwell shorter than this is not an event
global g_MouseHeatCell := 16          ; Heat grid cell size, in window pixels

; ─── Bucket state (current window + current minute) ──────────────────────────
global g_MouseBucket := ""
global g_MTLastX := -99999   ; window-relative last sample (distinct from v7 Idle Mouse globals)
global g_MTLastY := -99999
global g_MouseLastSampleTick := 0
global g_MouseDwellX := 0
global g_MouseDwellY := 0
global g_MouseDwellStart := 0
global g_MouseBtnDown := Map("L", false, "R", false, "M", false)

; ─── Replay state ────────────────────────────────────────────────────────────
global g_MouseReplayAbort := false
global g_MouseReplayActive := false

; ═══════════════════════════════════════════════════════════════════════════════
; PUBLIC CONTROL
; ═══════════════════════════════════════════════════════════════════════════════

MouseTrack_Start() {
    global g_MouseTrackOn, g_MouseSampleMs, g_MouseLastSampleTick

    if !TrackDB_Ready() {
        if !TrackDB_Init()
            return false
    }
    if g_MouseTrackOn
        return true

    g_MouseTrackOn := true
    g_MouseLastSampleTick := A_TickCount
    MouseTrack_ResetPointerState()
    SetTimer(MouseTrack_Sample, g_MouseSampleMs)
    return true
}

MouseTrack_Stop() {
    global g_MouseTrackOn
    if !g_MouseTrackOn
        return
    SetTimer(MouseTrack_Sample, 0)
    MouseTrack_FlushBucket()
    g_MouseTrackOn := false
}

MouseTrack_Toggle() {
    global g_MouseTrackOn
    if g_MouseTrackOn
        MouseTrack_Stop()
    else
        MouseTrack_Start()
    return g_MouseTrackOn
}

MouseTrack_IsOn() {
    global g_MouseTrackOn
    return g_MouseTrackOn
}

MouseTrack_ResetPointerState() {
    global g_MTLastX, g_MTLastY, g_MouseDwellStart, g_MouseBtnDown
    g_MTLastX := -99999
    g_MTLastY := -99999
    g_MouseDwellStart := 0
    g_MouseBtnDown := Map("L", false, "R", false, "M", false)
}

; Called by the window tracker when focus moves to a different window.
MouseTrack_OnWindowChange(ctx) {
    global g_MouseTrackOn
    if !g_MouseTrackOn
        return
    MouseTrack_FlushBucket()
    MouseTrack_ResetPointerState()
}

; ═══════════════════════════════════════════════════════════════════════════════
; BUCKETS
; ═══════════════════════════════════════════════════════════════════════════════

; A bucket accumulates one (window, minute) worth of samples in memory.
MouseTrack_NewBucket(ctx) {
    ; Tick that corresponds to :00 of the current minute, so sample timestamps
    ; are comparable across separate visits to the same minute.
    msIntoMinute := (Integer(A_Sec) * 1000) + Integer(A_MSec)

    return Map(
        "win_id", ctx["win_id"],
        "app_id", ctx["app_id"],
        "win_name", ctx["name"],
        "minute_key", TrackMinuteKey(),
        "minute_tick", A_TickCount - msIntoMinute,
        "start_ts", TrackTS(),
        "samples", 0,
        "distance", 0.0,
        "idle_ms", 0,
        "dwell_count", 0,
        "click_count", 0,
        "win_x", ctx["x"], "win_y", ctx["y"],
        "win_w", ctx["w"], "win_h", ctx["h"],
        "path", [],
        "clicks", [],
        "heat", Map()
    )
}

; Ensure a bucket exists that matches the current window and minute.
MouseTrack_EnsureBucket(ctx) {
    global g_MouseBucket

    if !ctx["win_id"]
        return ""

    minuteKey := TrackMinuteKey()
    if IsObject(g_MouseBucket) {
        if (g_MouseBucket["win_id"] = ctx["win_id"] && g_MouseBucket["minute_key"] = minuteKey) {
            ; Track window movement/resize within the minute.
            g_MouseBucket["win_x"] := ctx["x"], g_MouseBucket["win_y"] := ctx["y"]
            g_MouseBucket["win_w"] := ctx["w"], g_MouseBucket["win_h"] := ctx["h"]
            return g_MouseBucket
        }
        MouseTrack_FlushBucket()
    }

    g_MouseBucket := MouseTrack_NewBucket(ctx)
    return g_MouseBucket
}

; Persist the in-memory bucket and clear it.
MouseTrack_FlushBucket() {
    global g_MouseBucket, g_MouseDwellStart

    if !IsObject(g_MouseBucket)
        return false

    b := g_MouseBucket
    g_MouseBucket := ""
    g_MouseDwellStart := 0

    if (b["samples"] = 0 && b["clicks"].Length = 0)
        return false

    try {
        snap := Map(
            "win_id", b["win_id"],
            "app_id", b["app_id"],
            "minute_key", b["minute_key"],
            "start_ts", b["start_ts"],
            "end_ts", TrackTS(),
            "samples", b["samples"],
            "distance", Round(b["distance"], 1),
            "idle_ms", b["idle_ms"],
            "dwell_count", b["dwell_count"],
            "click_count", b["click_count"],
            "win_x", b["win_x"], "win_y", b["win_y"],
            "win_w", b["win_w"], "win_h", b["win_h"],
            "path_blob", "v1;" . TrackArrayJoin(b["path"], ";"),
            "click_blob", TrackArrayJoin(b["clicks"], ";")
        )
        TrackDB_AddMouseSnapshot(snap)
        if b["heat"].Count
            TrackDB_MergeHeat(b["win_id"], b["heat"])
    } catch as err {
        TrackLogError("MouseTrack_FlushBucket", err)
        return false
    }
    return true
}

; ═══════════════════════════════════════════════════════════════════════════════
; SAMPLING
; ═══════════════════════════════════════════════════════════════════════════════

MouseTrack_Sample() {
    global g_MouseTrackOn, g_MouseBucket, g_MTLastX, g_MTLastY
    global g_MouseLastSampleTick, g_MouseMinMove, g_MouseAnchorMs
    global g_MouseDwellX, g_MouseDwellY, g_MouseDwellStart
    global g_MouseDwellRadius, g_MouseDwellMinMs, g_MouseHeatCell
    global g_MouseReplayActive

    if !g_MouseTrackOn
        return
    ; Do not record our own synthetic replay as if it were the user.
    if g_MouseReplayActive
        return

    ctx := TrackCtx_Get(750)
    if !ctx["win_id"] {
        if IsObject(g_MouseBucket)
            MouseTrack_FlushBucket()
        return
    }

    b := MouseTrack_EnsureBucket(ctx)
    if !IsObject(b)
        return

    MouseGetPos(&sx, &sy)
    rx := sx - b["win_x"]
    ry := sy - b["win_y"]

    now := A_TickCount
    elapsed := now - g_MouseLastSampleTick
    g_MouseLastSampleTick := now

    ; ─── Distance / idle accounting ──────────────────────────────────────────
    moved := 0
    if (g_MTLastX > -99999) {
        dx := rx - g_MTLastX
        dy := ry - g_MTLastY
        moved := Sqrt(dx * dx + dy * dy)
        b["distance"] := b["distance"] + moved
        if (moved < 1)
            b["idle_ms"] := b["idle_ms"] + elapsed
    }

    ; ─── Dwell detection ─────────────────────────────────────────────────────
    if (g_MouseDwellStart = 0) {
        g_MouseDwellStart := now
        g_MouseDwellX := rx
        g_MouseDwellY := ry
    } else {
        ddx := rx - g_MouseDwellX
        ddy := ry - g_MouseDwellY
        if (Sqrt(ddx * ddx + ddy * ddy) > g_MouseDwellRadius) {
            dwellMs := now - g_MouseDwellStart
            if (dwellMs >= g_MouseDwellMinMs) {
                b["dwell_count"] := b["dwell_count"] + 1
                MouseTrack_AddHeat(b, g_MouseDwellX, g_MouseDwellY, 0, 0, dwellMs)
            }
            g_MouseDwellStart := now
            g_MouseDwellX := rx
            g_MouseDwellY := ry
        }
    }

    ; ─── Click edges (polled, so no hotkey is stolen from the user) ──────────
    MouseTrack_PollButtons(b, rx, ry)

    ; ─── Keep the sample? ────────────────────────────────────────────────────
    keep := false
    if (g_MTLastX <= -99999)
        keep := true
    else if (moved >= g_MouseMinMove)
        keep := true
    else if (b["path"].Length && (now - b["minute_tick"]) - MouseTrack_LastSampleT(b) >= g_MouseAnchorMs)
        keep := true

    if keep {
        t := TrackClamp(now - b["minute_tick"], 0, 59999)
        b["path"].Push(t . "," . Round(rx) . "," . Round(ry))
        b["samples"] := b["samples"] + 1
        MouseTrack_AddHeat(b, rx, ry, 1, 0, 0)
    }

    g_MTLastX := rx
    g_MTLastY := ry

    ; ─── Minute rollover ─────────────────────────────────────────────────────
    if (b["minute_key"] != TrackMinuteKey())
        MouseTrack_FlushBucket()
}

; Timestamp of the last stored sample, in the bucket's minute-relative clock.
MouseTrack_LastSampleT(b) {
    if !b["path"].Length
        return 0
    last := b["path"][b["path"].Length]
    parts := StrSplit(last, ",")
    return parts.Length ? Integer(parts[1]) : 0
}

; Detect button press edges and record them as clicks.
MouseTrack_PollButtons(b, rx, ry) {
    global g_MouseBtnDown

    for code, btn in Map("L", "LButton", "R", "RButton", "M", "MButton") {
        down := GetKeyState(btn, "P")
        if (down && !g_MouseBtnDown[code]) {
            t := TrackClamp(A_TickCount - b["minute_tick"], 0, 59999)
            b["clicks"].Push(t . "," . Round(rx) . "," . Round(ry) . "," . code)
            b["click_count"] := b["click_count"] + 1
            MouseTrack_AddHeat(b, rx, ry, 0, 1, 0)
        }
        g_MouseBtnDown[code] := down
    }
}

; Accumulate into the bucket's heat grid. Points outside the window are ignored
; so the grid stays meaningful when normalised by window size.
MouseTrack_AddHeat(b, rx, ry, hits, clicks, dwellMs) {
    global g_MouseHeatCell

    if (rx < 0 || ry < 0)
        return
    if (b["win_w"] > 0 && rx >= b["win_w"])
        return
    if (b["win_h"] > 0 && ry >= b["win_h"])
        return

    gx := Integer(Floor(rx / g_MouseHeatCell))
    gy := Integer(Floor(ry / g_MouseHeatCell))
    key := gx . "," . gy

    if !b["heat"].Has(key)
        b["heat"][key] := Map("hits", 0, "clicks", 0, "dwell_ms", 0)
    cell := b["heat"][key]
    cell["hits"] := cell["hits"] + hits
    cell["clicks"] := cell["clicks"] + clicks
    cell["dwell_ms"] := cell["dwell_ms"] + dwellMs
}

; ═══════════════════════════════════════════════════════════════════════════════
; BLOB DECODING
; ═══════════════════════════════════════════════════════════════════════════════

; Decode a path blob into an array of Maps: t, x, y.
MouseTrack_DecodePath(blob) {
    out := []
    if (blob = "")
        return out
    for token in StrSplit(blob, ";") {
        token := Trim(token)
        if (token = "" || SubStr(token, 1, 1) = "v")
            continue
        p := StrSplit(token, ",")
        if (p.Length < 3)
            continue
        if !IsNumber(p[1]) || !IsNumber(p[2]) || !IsNumber(p[3])
            continue
        out.Push(Map("t", Integer(p[1]), "x", Integer(p[2]), "y", Integer(p[3])))
    }
    ; Concatenated blobs can interleave visits; sort so replay runs in order.
    MouseTrack_SortByT(out)
    return out
}

; Decode a click blob into an array of Maps: t, x, y, btn.
MouseTrack_DecodeClicks(blob) {
    out := []
    if (blob = "")
        return out
    for token in StrSplit(blob, ";") {
        token := Trim(token)
        if (token = "")
            continue
        p := StrSplit(token, ",")
        if (p.Length < 4)
            continue
        if !IsNumber(p[1]) || !IsNumber(p[2]) || !IsNumber(p[3])
            continue
        out.Push(Map("t", Integer(p[1]), "x", Integer(p[2]), "y", Integer(p[3]), "btn", p[4]))
    }
    MouseTrack_SortByT(out)
    return out
}

; Insertion sort on the "t" key - paths are near-sorted already.
MouseTrack_SortByT(arr) {
    i := 2
    while (i <= arr.Length) {
        item := arr[i]
        j := i - 1
        while (j >= 1 && arr[j]["t"] > item["t"]) {
            arr[j + 1] := arr[j]
            j--
        }
        arr[j + 1] := item
        i++
    }
    return arr
}

; ═══════════════════════════════════════════════════════════════════════════════
; QUERIES
; ═══════════════════════════════════════════════════════════════════════════════

MouseTrack_Snapshots(winId, limit := 200) {
    db := TrackDB()
    if !db
        return []
    if winId {
        return db.Query("SELECT * FROM mouse_snapshot WHERE win_id=? "
                      . "ORDER BY minute_key DESC LIMIT ?", winId, limit)
    }
    return db.Query("SELECT m.*, w.name AS win_name FROM mouse_snapshot m "
                  . "JOIN win w ON w.id=m.win_id ORDER BY m.minute_key DESC LIMIT ?", limit)
}

MouseTrack_Snapshot(snapId) {
    db := TrackDB()
    if !db
        return Map()
    return db.QueryRow("SELECT m.*, w.name AS win_name FROM mouse_snapshot m "
                     . "JOIN win w ON w.id=m.win_id WHERE m.id=?", snapId)
}

MouseTrack_HeatCells(winId) {
    db := TrackDB()
    if !db
        return []
    return db.Query("SELECT gx,gy,hits,clicks,dwell_ms FROM mouse_heat WHERE win_id=?", winId)
}

; Representative window size for a tracked window (the most recent non-zero).
MouseTrack_WindowSize(winId) {
    db := TrackDB()
    size := Map("w", 0, "h", 0)
    if !db
        return size
    row := db.QueryRow("SELECT win_w, win_h FROM mouse_snapshot "
                     . "WHERE win_id=? AND win_w>0 AND win_h>0 ORDER BY id DESC LIMIT 1", winId)
    if row.Count {
        size["w"] := Integer(row["win_w"])
        size["h"] := Integer(row["win_h"])
        return size
    }
    row := db.QueryRow("SELECT w, h FROM win_session WHERE win_id=? AND w>0 AND h>0 "
                     . "ORDER BY id DESC LIMIT 1", winId)
    if row.Count {
        size["w"] := Integer(row["w"])
        size["h"] := Integer(row["h"])
    }
    return size
}

; ═══════════════════════════════════════════════════════════════════════════════
; HEAT MAP RENDERING
; ═══════════════════════════════════════════════════════════════════════════════

; Render the aggregated heat grid for a window into a PNG.
; metric: "hits" | "clicks" | "dwell_ms"
; Returns the file path, or "" when there is nothing to draw.
MouseTrack_RenderHeatmap(winId, outPath := "", metric := "hits", maxWidth := 1100) {
    global g_MouseHeatCell, DATA_DIR

    cells := MouseTrack_HeatCells(winId)
    if !cells.Length
        return ""

    size := MouseTrack_WindowSize(winId)
    winW := size["w"], winH := size["h"]

    ; Fall back to the grid extents when no window size was ever recorded.
    if (winW <= 0 || winH <= 0) {
        maxGx := 0, maxGy := 0
        for c in cells {
            maxGx := Max(maxGx, Integer(c["gx"]))
            maxGy := Max(maxGy, Integer(c["gy"]))
        }
        winW := (maxGx + 1) * g_MouseHeatCell
        winH := (maxGy + 1) * g_MouseHeatCell
    }
    if (winW <= 0 || winH <= 0)
        return ""

    scale := (winW > maxWidth) ? (maxWidth / winW) : 1.0
    imgW := Max(1, Integer(Round(winW * scale)))
    imgH := Max(1, Integer(Round(winH * scale)))

    canvas := PixelCanvas(imgW, imgH, 0xFF14161A)

    ; Peak value drives the colour ramp normalisation.
    peak := 0
    for c in cells
        peak := Max(peak, Integer(c[metric]))
    if (peak <= 0)
        return ""

    cellPx := Max(1, Integer(Round(g_MouseHeatCell * scale)))
    radius := Max(2, Integer(Round(cellPx * 1.6)))

    for c in cells {
        v := Integer(c[metric])
        if (v <= 0)
            continue
        ; Log scaling keeps a single hot cell from flattening everything else.
        t := Ln(1 + v) / Ln(1 + peak)
        px := (Integer(c["gx"]) * g_MouseHeatCell + g_MouseHeatCell / 2) * scale
        py := (Integer(c["gy"]) * g_MouseHeatCell + g_MouseHeatCell / 2) * scale
        rgb := HeatRampRGB(t)
        canvas.Blob(px, py, radius, rgb["r"], rgb["g"], rgb["b"], TrackClamp(0.25 + t * 0.75, 0, 1))
    }

    ; Click markers sit on top so they read as discrete events.
    if (metric != "clicks") {
        for c in cells {
            if (Integer(c["clicks"]) <= 0)
                continue
            px := (Integer(c["gx"]) * g_MouseHeatCell + g_MouseHeatCell / 2) * scale
            py := (Integer(c["gy"]) * g_MouseHeatCell + g_MouseHeatCell / 2) * scale
            canvas.Circle(px, py, Max(2, cellPx // 3), 0xC0FFFFFF)
        }
    }

    canvas.DrawRect(0, 0, imgW, imgH, 0xFF3A3F47, 1)

    if (outPath = "")
        outPath := DATA_DIR . "\tracking\heatmap_win" . winId . "_" . metric . ".png"
    return canvas.Save(outPath) ? outPath : ""
}

; Render one snapshot's movement trace: poly-line, start/end markers, clicks.
MouseTrack_RenderTrace(snapId, outPath := "", maxWidth := 1100) {
    global DATA_DIR

    snap := MouseTrack_Snapshot(snapId)
    if !snap.Count
        return ""

    path := MouseTrack_DecodePath(snap["path_blob"])
    clicks := MouseTrack_DecodeClicks(snap["click_blob"])
    if (!path.Length && !clicks.Length)
        return ""

    winW := Integer(snap["win_w"]), winH := Integer(snap["win_h"])
    if (winW <= 0 || winH <= 0) {
        maxX := 100, maxY := 100
        for p in path {
            maxX := Max(maxX, p["x"])
            maxY := Max(maxY, p["y"])
        }
        winW := maxX + 20, winH := maxY + 20
    }

    scale := (winW > maxWidth) ? (maxWidth / winW) : 1.0
    imgW := Max(1, Integer(Round(winW * scale)))
    imgH := Max(1, Integer(Round(winH * scale)))
    canvas := PixelCanvas(imgW, imgH, 0xFF14161A)

    ; Grid every 100 window pixels for a sense of scale.
    gridStep := Max(10, Integer(Round(100 * scale)))
    x := gridStep
    while (x < imgW) {
        canvas.FillRect(x, 0, 1, imgH, 0xFF20242B)
        x += gridStep
    }
    y := gridStep
    while (y < imgH) {
        canvas.FillRect(0, y, imgW, 1, 0xFF20242B)
        y += gridStep
    }

    ; The trace fades from cool (early) to warm (late) so direction is readable.
    n := path.Length
    Loop Max(0, n - 1) {
        a := path[A_Index]
        b := path[A_Index + 1]
        t := (n > 1) ? ((A_Index - 1) / (n - 1)) : 0
        color := HeatRampColor(t, 0xE0)
        canvas.Line(a["x"] * scale, a["y"] * scale, b["x"] * scale, b["y"] * scale, color, 2)
    }

    if n {
        first := path[1]
        last := path[n]
        canvas.Circle(first["x"] * scale, first["y"] * scale, 5, 0xFF3BD16F)   ; start: green
        canvas.Circle(last["x"] * scale, last["y"] * scale, 5, 0xFFE84A3F)     ; end: red
    }

    for c in clicks {
        cx := c["x"] * scale, cy := c["y"] * scale
        col := (c["btn"] = "R") ? 0xFFFFD24A : (c["btn"] = "M") ? 0xFF9A7BFF : 0xFFFFFFFF
        canvas.Circle(cx, cy, 6, 0x60000000)
        canvas.DrawRect(cx - 6, cy - 6, 13, 13, col, 2)
    }

    canvas.DrawRect(0, 0, imgW, imgH, 0xFF3A3F47, 1)

    if (outPath = "")
        outPath := DATA_DIR . "\tracking\trace_" . snapId . ".png"
    return canvas.Save(outPath) ? outPath : ""
}

; ═══════════════════════════════════════════════════════════════════════════════
; REPLAY / SIMULATION
; ═══════════════════════════════════════════════════════════════════════════════

; Re-drive a recorded path with MouseMove.
;   speed       1.0 = original timing, 2.0 = twice as fast
;   targetHwnd  0 = replay against the window rect stored with the snapshot;
;               otherwise translate onto that window's current position
;   doClicks    replay the recorded button presses too
;
; ESC aborts. Returns the number of points replayed.
;   manageEsc:  bind/unbind the Escape abort hotkey. Pass false when a workflow
;               step calls this - the running sequence already owns Escape, and
;               grabbing/releasing it here would disable the sequence's abort.
;               In that case replay stops on the shared g_AbortSequence flag.
MouseTrack_Replay(snapId, speed := 1.0, targetHwnd := 0, doClicks := false, manageEsc := true) {
    global g_MouseReplayAbort, g_MouseReplayActive, g_AbortSequence

    snap := MouseTrack_Snapshot(snapId)
    if !snap.Count
        return 0

    path := MouseTrack_DecodePath(snap["path_blob"])
    if !path.Length
        return 0

    clicks := doClicks ? MouseTrack_DecodeClicks(snap["click_blob"]) : []

    ; ─── Work out where window-relative coordinates land right now ───────────
    originX := Integer(snap["win_x"])
    originY := Integer(snap["win_y"])
    scaleX := 1.0, scaleY := 1.0
    recW := Integer(snap["win_w"]), recH := Integer(snap["win_h"])

    if targetHwnd {
        try {
            WinGetPos(&tx, &ty, &tw, &th, "ahk_id " . targetHwnd)
            originX := tx, originY := ty
            ; Scale so the path still lands on the same relative features after
            ; a resize.
            if (recW > 0 && tw > 0)
                scaleX := tw / recW
            if (recH > 0 && th > 0)
                scaleY := th / recH
        } catch as err {
            TrackLogError("MouseTrack_Replay(target)", err)
        }
    }

    if (speed <= 0)
        speed := 1.0

    g_MouseReplayAbort := false
    g_MouseReplayActive := true
    if manageEsc
        try Hotkey("Escape", MouseTrack_AbortReplay, "On")

    ; The script runs screen-relative everywhere; make that explicit for the
    ; replay thread since stored coordinates are screen-space once translated.
    CoordMode("Mouse", "Screen")

    done := 0
    startTick := A_TickCount
    baseT := path[1]["t"]
    clickIdx := 1

    try {
        for i, p in path {
            ; Stop on our own abort or on the sequence-wide abort (ESC during a
            ; workflow sets g_AbortSequence, which we must respect too).
            if (g_MouseReplayAbort || g_AbortSequence)
                break

            targetX := Integer(Round(originX + p["x"] * scaleX))
            targetY := Integer(Round(originY + p["y"] * scaleY))
            MouseMove(targetX, targetY, 0)
            done++

            ; Fire any clicks scheduled at or before this point.
            while (doClicks && clickIdx <= clicks.Length && clicks[clickIdx]["t"] <= p["t"]) {
                c := clicks[clickIdx]
                cx := Integer(Round(originX + c["x"] * scaleX))
                cy := Integer(Round(originY + c["y"] * scaleY))
                btn := (c["btn"] = "R") ? "Right" : (c["btn"] = "M") ? "Middle" : "Left"
                Click(cx, cy, btn)
                clickIdx++
            }

            ; Pace against the recorded timeline rather than sleeping a constant.
            if (i < path.Length) {
                wantElapsed := (path[i + 1]["t"] - baseT) / speed
                actual := A_TickCount - startTick
                wait := Integer(Round(wantElapsed - actual))
                if (wait > 0)
                    Sleep(Min(wait, 2000))
            }
        }
    } catch as err {
        TrackLogError("MouseTrack_Replay", err)
    }

    if manageEsc
        try Hotkey("Escape", "Off")
    g_MouseReplayActive := false
    return done
}

MouseTrack_AbortReplay(*) {
    global g_MouseReplayAbort
    g_MouseReplayAbort := true
}

; ═══════════════════════════════════════════════════════════════════════════════
; FEATURE EXTRACTION
; ═══════════════════════════════════════════════════════════════════════════════
; Turns raw heat into a ranked list of *element candidates*: places the user
; repeatedly hovers over or clicks. Each candidate carries both absolute
; window-relative pixels and normalised 0-1 coordinates, so it can be handed to
; any automation tool - including ones that know nothing about this script.

; Extract and persist features for one window. Returns the array of features.
MouseTrack_ExtractFeatures(winId, minWeight := 3.0, clusterRadius := 3) {
    db := TrackDB()
    if !db || !winId
        return []

    cells := MouseTrack_HeatCells(winId)
    if !cells.Length
        return []

    global g_MouseHeatCell
    size := MouseTrack_WindowSize(winId)

    ; Index cells and score them. Clicks dominate, dwell matters, raw movement
    ; is only a tiebreaker - passing through a spot is not interest in it.
    index := Map()
    scored := []
    for c in cells {
        gx := Integer(c["gx"]), gy := Integer(c["gy"])
        weight := Integer(c["clicks"]) * 10.0
                + (Integer(c["dwell_ms"]) / 250.0)
                + (Integer(c["hits"]) * 0.15)
        entry := Map("gx", gx, "gy", gy, "hits", Integer(c["hits"])
                   , "clicks", Integer(c["clicks"]), "dwell_ms", Integer(c["dwell_ms"])
                   , "weight", weight, "used", false)
        index[gx . "," . gy] := entry
        scored.Push(entry)
    }

    ; Descending weight, so the strongest cell seeds each cluster.
    MouseTrack_SortByWeightDesc(scored)

    features := []
    for seed in scored {
        if seed["used"]
            continue
        if (seed["weight"] < minWeight)
            break

        ; Absorb neighbours within clusterRadius cells.
        members := []
        dy := -clusterRadius
        while (dy <= clusterRadius) {
            dx := -clusterRadius
            while (dx <= clusterRadius) {
                key := (seed["gx"] + dx) . "," . (seed["gy"] + dy)
                if index.Has(key) {
                    m := index[key]
                    if !m["used"] {
                        m["used"] := true
                        members.Push(m)
                    }
                }
                dx++
            }
            dy++
        }
        if !members.Length
            continue

        ; Weighted centroid + bounding box in window pixels.
        totW := 0.0, sumX := 0.0, sumY := 0.0
        minGx := 99999, maxGx := -99999, minGy := 99999, maxGy := -99999
        hits := 0, clicks := 0, dwell := 0
        for m in members {
            w := Max(m["weight"], 0.001)
            totW += w
            sumX += (m["gx"] + 0.5) * g_MouseHeatCell * w
            sumY += (m["gy"] + 0.5) * g_MouseHeatCell * w
            minGx := Min(minGx, m["gx"]), maxGx := Max(maxGx, m["gx"])
            minGy := Min(minGy, m["gy"]), maxGy := Max(maxGy, m["gy"])
            hits += m["hits"], clicks += m["clicks"], dwell += m["dwell_ms"]
        }
        cx := Integer(Round(sumX / totW))
        cy := Integer(Round(sumY / totW))
        bx := minGx * g_MouseHeatCell
        by := minGy * g_MouseHeatCell
        bw := (maxGx - minGx + 1) * g_MouseHeatCell
        bh := (maxGy - minGy + 1) * g_MouseHeatCell

        kind := (clicks > 0) ? "click-target" : (dwell >= 2000) ? "dwell-target" : "transit"

        features.Push(Map(
            "kind", kind,
            "x", cx, "y", cy,
            "bx", bx, "by", by, "w", bw, "h", bh,
            "rel_x", (size["w"] > 0) ? Round(cx / size["w"], 5) : 0,
            "rel_y", (size["h"] > 0) ? Round(cy / size["h"], 5) : 0,
            "weight", Round(totW, 2),
            "hits", hits, "clicks", clicks, "dwell_ms", dwell
        ))
    }

    ; Replace the previous extraction for this window.
    now := TrackTS()
    db.Begin()
    try {
        db.Run("DELETE FROM mouse_feature WHERE win_id=?", winId)
        appId := db.Scalar("SELECT app_id FROM win WHERE id=?", winId)
        for f in features {
            db.Run("INSERT INTO mouse_feature"
                 . "(win_id,app_id,kind,x,y,w,h,rel_x,rel_y,weight,samples,clicks,dwell_ms,first_seen,last_seen) "
                 . "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
                 , winId, appId, f["kind"], f["x"], f["y"], f["w"], f["h"]
                 , f["rel_x"], f["rel_y"], f["weight"], f["hits"], f["clicks"], f["dwell_ms"]
                 , now, now)
        }
    } catch as err {
        db.Rollback()
        TrackLogError("MouseTrack_ExtractFeatures", err)
        return features
    }
    db.Commit()

    return features
}

MouseTrack_SortByWeightDesc(arr) {
    i := 2
    while (i <= arr.Length) {
        item := arr[i]
        j := i - 1
        while (j >= 1 && arr[j]["weight"] < item["weight"]) {
            arr[j + 1] := arr[j]
            j--
        }
        arr[j + 1] := item
        i++
    }
    return arr
}

MouseTrack_Features(winId) {
    db := TrackDB()
    if !db
        return []
    return db.Query("SELECT * FROM mouse_feature WHERE win_id=? ORDER BY weight DESC", winId)
}

; Render extracted features over the heat map so they can be eyeballed.
MouseTrack_RenderFeatures(winId, outPath := "", maxWidth := 1100) {
    global DATA_DIR

    feats := MouseTrack_Features(winId)
    if !feats.Length
        return ""

    size := MouseTrack_WindowSize(winId)
    winW := size["w"], winH := size["h"]
    if (winW <= 0 || winH <= 0) {
        winW := 1280, winH := 800
    }

    scale := (winW > maxWidth) ? (maxWidth / winW) : 1.0
    imgW := Max(1, Integer(Round(winW * scale)))
    imgH := Max(1, Integer(Round(winH * scale)))
    canvas := PixelCanvas(imgW, imgH, 0xFF14161A)

    peak := 0.0
    for f in feats
        peak := Max(peak, Float(f["weight"]))
    if (peak <= 0)
        peak := 1

    for f in feats {
        t := Float(f["weight"]) / peak
        color := HeatRampColor(t, 0xFF)
        bx := (Integer(f["x"]) - Integer(f["w"]) / 2) * scale
        by := (Integer(f["y"]) - Integer(f["h"]) / 2) * scale
        canvas.FillRect(bx, by, Integer(f["w"]) * scale, Integer(f["h"]) * scale
                      , HeatRampColor(t, 0x40))
        canvas.DrawRect(bx, by, Integer(f["w"]) * scale, Integer(f["h"]) * scale, color, 2)
        canvas.Circle(Integer(f["x"]) * scale, Integer(f["y"]) * scale, 3, 0xFFFFFFFF)
    }

    canvas.DrawRect(0, 0, imgW, imgH, 0xFF3A3F47, 1)

    if (outPath = "")
        outPath := DATA_DIR . "\tracking\features_win" . winId . ".png"
    return canvas.Save(outPath) ? outPath : ""
}

; ═══════════════════════════════════════════════════════════════════════════════
; STATUS
; ═══════════════════════════════════════════════════════════════════════════════

MouseTrack_StatusLine() {
    global g_MouseTrackOn, g_MouseBucket
    if !g_MouseTrackOn
        return "Mouse tracking: OFF"
    if !IsObject(g_MouseBucket)
        return "Mouse tracking: ON (waiting for a window)"
    return "Mouse tracking: " . g_MouseBucket["samples"] . " pts, "
         . g_MouseBucket["click_count"] . " clicks this minute"
}
