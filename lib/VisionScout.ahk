; ═══════════════════════════════════════════════════════════════════════════════
; VisionScout.ahk - MacroAutomator v9 self-learning subsystem (deepseek build)
; ═══════════════════════════════════════════════════════════════════════════════
; Four coupled capabilities, layered on top of the existing tracking store:
;
;   1. VISUAL SCRAPING  Segment the screen into "interesting" regions (edges /
;                       text / buttons / icons) and capture a FindText pattern
;                       for each one, so every visible item becomes a named,
;                       re-findable element.
;
;   2. USAGE STREAM     A passive, ordered log of what the user actually does:
;                       clicks (with element attribution), typed runs, hotkeys,
;                       navigation keys and window switches. Synthetic input
;                       this script itself produces is excluded.
;
;   3. PROMOTION        Elements that are clicked / dwelled on repeatedly gain
;                       score and a tier (cold -> seen -> frequent -> hot).
;                       Promoted elements re-capture a high-fidelity pattern and
;                       can be exported into the Patterns tab as first-class
;                       FindText patterns.
;
;   4. SEQUENCE LEARN   Compress the usage stream into steps, mine frequent
;                       sub-sequences, and when the user begins to repeat a known
;                       sequence manually, offer to auto-complete it: a tooltip
;                       appears and pressing Win+CapsLock runs the remaining
;                       steps.
;
; All data lives in the shared tracking DB (data\tracking.db) under its own
; vs_element / vs_action / vs_sequence tables, so nothing here touches the app's
; workflow SQLite or its INI files.
; ═══════════════════════════════════════════════════════════════════════════════

; ═══════════════════════════════════════════════════════════════════════════════
; CONFIGURATION
; ═══════════════════════════════════════════════════════════════════════════════
global g_VSOn := false                 ; Master switch for the whole subsystem
global g_VSMousePollMs := 50           ; Click / dwell edge poll period
global g_VSWinPollMs := 500            ; Foreground-window change poll period
global g_VSPauseMs := 1200             ; Gap that ends a typing run
global g_VSScanStep := 6               ; Segmentation grid step, in pixels
global g_VSContrastThresh := 26        ; Luminance neighbour diff that marks an edge
global g_VSMinAreaCells := 8           ; Ignore blobs smaller than this many cells
global g_VSMaxAreaFrac := 0.42         ; Ignore blobs wider/taller than this fraction
global g_VSMergeDist := 16             ; Pixels: merge nearby bounding boxes
global g_VSMaxScanElements := 90       ; Hard cap on elements captured per scan
global g_VSDwellRadius := 6            ; Pixels that still count as "not moving"
global g_VSDwellMinMs := 1200          ; Dwell shorter than this is not an access
global g_VSAutoScanMin := 3            ; Background window scan interval (minutes, 0=off)
global g_VSMinSupport := 3             ; A sequence must repeat this many times to learn
global g_VSMinPrefix := 2              ; Recent steps that must match to offer help
global g_VSMaxSeqLen := 6              ; Longest sequence length to mine
global g_VSOfferCooldownMs := 8000     ; Do not re-offer the same sequence this fast
global g_VSMaxSteps := 600             ; In-memory compressed-step ring size
global g_VSMaxRecent := 300            ; In-memory raw-event ring size
global g_VSFlushMs := 5000             ; Persist buffered events this often
global g_VSMineMs := 20000             ; Re-mine sequences this often
global g_VSAutoScanMs := 180000        ; Background scan period (recomputed from minutes)

; ═══════════════════════════════════════════════════════════════════════════════
; STATE
; ═══════════════════════════════════════════════════════════════════════════════
global g_VSMouseBtnDown := Map("L", false, "R", false, "M", false)
global g_VSHook := ""                  ; InputHook instance
global g_VSTextRun := []               ; Pending typed characters
global g_VSLastCharTick := 0
global g_VSDwellX := 0, g_VSDwellY := 0, g_VSDwellStart := 0, g_VSDwellCounted := false
global g_VSLastWinId := 0
global g_VSLastActiveTick := 0
global g_VSSteps := []                 ; Compressed step tokens (ring)
global g_VSRecent := []                ; Raw recent events (ring)
global g_VSSequences := []             ; Learned sequence rows (Map cache)
global g_VSElements := []              ; Element rows (Map cache)
global g_VSFlushQueue := []            ; Events awaiting persistence
global g_VSPending := Map()            ; Pending prediction offer
global g_VSOfferArmed := false         ; Win+CapsLock hotkey is registered
global g_VSLastOfferTick := 0
global g_VSLastOfferSig := ""
global g_VSReplaying := false          ; True while this script runs a learned sequence
global g_VSScanBusy := false
global g_VSLastScanIds := []           ; Every candidate touched by the most recent scan

; Interactive review layer.  Scan results are deliberately kept separate from
; the normal (click-through) Macro Automator overlays: these windows must accept
; clicks so a candidate can be selected and dragged into the correct position.
global g_VSReviewOverlays := Map()     ; element id -> {gui, label, drawW, drawH}
global g_VSOverlayHandleMap := Map()   ; GUI/control HWND -> element id
global g_VSReviewSelectedId := 0
global g_VSReviewPalette := ""
global g_VSReviewInfo := ""
global g_VSOverlayMessagesReady := false
global g_VSRestoreMainGui := false

; ─── UI control references (set by VisionScout_BuildTab) ──────────────────────
global g_VSStatusText := ""
global g_VSElemLV := ""
global g_VSSeqLV := ""
global g_VSCbOn := ""

; ═══════════════════════════════════════════════════════════════════════════════
; SCHEMA
; ═══════════════════════════════════════════════════════════════════════════════

; Create the three tables this subsystem owns. Called after TrackDB is open.
VS_ApplySchema(db) {
    db.Exec("CREATE TABLE IF NOT EXISTS vs_element ("
          . "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
          . "  win_id INTEGER NOT NULL DEFAULT 0,"
          . "  app_id INTEGER NOT NULL DEFAULT 0,"
          . "  x INTEGER, y INTEGER, w INTEGER, h INTEGER,"
          . "  rel_x REAL, rel_y REAL, rel_w REAL, rel_h REAL,"
          . "  bin_text TEXT,"
          . "  ocr_text TEXT,"
          . "  score REAL NOT NULL DEFAULT 0,"
          . "  clicks INTEGER NOT NULL DEFAULT 0,"
          . "  accesses INTEGER NOT NULL DEFAULT 0,"
          . "  tier INTEGER NOT NULL DEFAULT 0,"
          . "  promoted INTEGER NOT NULL DEFAULT 0,"
          . "  first_seen TEXT, last_seen TEXT,"
          . "  UNIQUE(win_id, x, y, w, h))")
    db.Exec("CREATE INDEX IF NOT EXISTS ix_vs_elem_win ON vs_element(win_id)")
    db.Exec("CREATE INDEX IF NOT EXISTS ix_vs_elem_tier ON vs_element(tier)")

    ; v9.1 review metadata.  Existing tracking databases are migrated in place.
    ; "promoted" remains the frequency/automation flag; review_state records a
    ; human decision, so frequently-used noise cannot silently become a Pattern.
    db.AddColumnIfMissing("vs_element", "review_state", "TEXT NOT NULL DEFAULT 'unreviewed'")
    db.AddColumnIfMissing("vs_element", "review_note", "TEXT NOT NULL DEFAULT ''")
    db.AddColumnIfMissing("vs_element", "reviewed_at", "TEXT NOT NULL DEFAULT ''")

    db.Exec("CREATE TABLE IF NOT EXISTS vs_action ("
          . "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
          . "  ts TEXT, tick INTEGER,"
          . "  kind TEXT,"
          . "  win_id INTEGER NOT NULL DEFAULT 0,"
          . "  app_id INTEGER NOT NULL DEFAULT 0,"
          . "  element_id INTEGER NOT NULL DEFAULT 0,"
          . "  x INTEGER, y INTEGER,"
          . "  label TEXT, detail TEXT)")
    db.Exec("CREATE INDEX IF NOT EXISTS ix_vs_action_ts ON vs_action(ts)")

    db.Exec("CREATE TABLE IF NOT EXISTS vs_sequence ("
          . "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
          . "  sig TEXT NOT NULL UNIQUE,"
          . "  steps TEXT,"
          . "  count INTEGER NOT NULL DEFAULT 0,"
          . "  length INTEGER NOT NULL DEFAULT 0,"
          . "  first_seen TEXT, last_seen TEXT)")
}

; ═══════════════════════════════════════════════════════════════════════════════
; LIFECYCLE
; ═══════════════════════════════════════════════════════════════════════════════

; Open the tracking DB (if needed), apply our schema and load the caches.
VisionScout_Init() {
    if !TrackDB_Ready() {
        if !TrackDB_Init()
            return false
    }
    db := TrackDB()
    if !db
        return false
    VS_ApplySchema(db)
    VS_LoadElements()
    VS_LoadSequences()
    return true
}

VS_Start() {
    global g_VSOn, g_VSLastWinId, g_VSDwellStart, g_VSDwellCounted, g_VSHook, g_VSAutoScanMs, g_VSAutoScanMin
    if g_VSOn
        return true
    if !VisionScout_Init() {
        ShowStatus("Vision Scout: tracking DB unavailable", "fail")
        return false
    }
    g_VSOn := true
    g_VSDwellStart := 0
    g_VSDwellCounted := false
    g_VSLastWinId := 0
    VS_StartInputHook()
    SetTimer(VS_PollMouse, g_VSMousePollMs)
    SetTimer(VS_PollWindow, g_VSWinPollMs)
    SetTimer(VS_FlushQueue, g_VSFlushMs)
    SetTimer(VS_MineSequencesTimer, g_VSMineMs)
    if g_VSAutoScanMin > 0 {
        g_VSAutoScanMs := g_VSAutoScanMin * 60000
        SetTimer(VS_AutoScanTimer, g_VSAutoScanMs)
    }
    VS_PersistRunState()
    VS_Refresh()
    ShowStatus("Vision Scout: learning ON (scanning + usage capture)", "ok")
    return true
}

VS_Stop() {
    global g_VSOn, g_VSHook
    if !g_VSOn
        return
    g_VSOn := false
    VS_StopInputHook()
    SetTimer(VS_PollMouse, 0)
    SetTimer(VS_PollWindow, 0)
    SetTimer(VS_FlushQueue, 0)
    SetTimer(VS_MineSequencesTimer, 0)
    SetTimer(VS_AutoScanTimer, 0)
    VS_CloseRun()
    VS_FlushQueue()
    VS_DisarmOffer()
    VS_PersistRunState()
    VS_Refresh()
    ShowStatus("Vision Scout: learning OFF", "info")
}

VS_Toggle(ctrl := "") {
    global g_VSOn, g_VSCbOn
    if g_VSOn
        VS_Stop()
    else
        VS_Start()
    if IsObject(g_VSCbOn)
        g_VSCbOn.Value := g_VSOn
}

VS_IsOn() {
    global g_VSOn
    return g_VSOn
}

VS_PersistRunState() {
    global g_VSOn
    TrackDB_MetaSet("run_vs", g_VSOn ? "1" : "0")
}

; Resume the learner at startup if it was running at last shutdown.
VisionScout_AutoStart() {
    if (TrackDB_MetaGet("run_vs", "0") = "1")
        VS_Start()
}

; Flush open state and stop timers on app exit.
VisionScout_Shutdown() {
    try VS_Stop()
}

; ═══════════════════════════════════════════════════════════════════════════════
; SCREEN CAPTURE + SEGMENTATION (visual scraper)
; ═══════════════════════════════════════════════════════════════════════════════

; Capture a screen rectangle into a 32bpp DIB and return its pixel buffer.
; Result Map: buf (Buffer), w, h, bits (address). Caller deletes the bitmap via
; VS_ReleaseCapture when done (or lets the buffer die and deletes immediately).
VS_CaptureRegion(x, y, w, h) {
    if (w < 8 || h < 8)
        return Map()
    hdc := GetDC()
    if !hdc
        return Map()
    chdc := CreateCompatibleDC()
    hbm := CreateDIBSection(w, h, chdc, 32, &bits)
    if !hbm {
        DeleteDC(chdc)
        ReleaseDC(hdc)
        return Map()
    }
    old := SelectObject(chdc, hbm)
    BitBlt(chdc, 0, 0, w, h, hdc, x, y)
    SelectObject(chdc, old)
    DeleteDC(chdc)
    ReleaseDC(hdc)
    return Map("hbm", hbm, "bits", bits, "w", w, "h", h)
}

; Delete the bitmap created by VS_CaptureRegion.
VS_ReleaseCapture(cap) {
    if cap.Has("hbm") && cap["hbm"]
        DeleteObject(cap["hbm"])
}

; Build a per-cell "interesting" mask. A cell is interesting when its luminance
; differs sharply from a neighbour (an edge / glyph / border), i.e. it is part of
; an item rather than empty background. Returns Map(mask:Buffer, gw, gh).
VS_Segment(cap, step, thresh) {
    w := cap["w"], h := cap["h"], bits := cap["bits"]
    gw := Max(1, (w + step - 1) // step)
    gh := Max(1, (h + step - 1) // step)
    stride := w * 4
    lum := Buffer(gw * gh, 0)

    ; Sample one pixel per cell. The DIB is bottom-up: memory row 0 = screen
    ; bottom, so translate screen y to the memory row.
    Loop gh {
        gy := A_Index - 1
        py := Min(h - 1, gy * step + step // 2)
        memRow := h - 1 - py
        Loop gw {
            gx := A_Index - 1
            px := Min(w - 1, gx * step + step // 2)
            off := memRow * stride + px * 4
            b := NumGet(bits, off, "UChar")
            g := NumGet(bits, off + 1, "UChar")
            r := NumGet(bits, off + 2, "UChar")
            NumPut("UChar", (r + g + b) // 3, lum, gy * gw + gx)
        }
    }

    mask := Buffer(gw * gh, 0)
    Loop gh {
        gy := A_Index - 1
        Loop gw {
            gx := A_Index - 1
            idx := gy * gw + gx
            v := NumGet(lum, idx, "UChar")
            maxd := 0
            if gx > 0 {
                d := Abs(v - NumGet(lum, idx - 1, "UChar"))
                if d > maxd
                    maxd := d
            }
            if gx < gw - 1 {
                d := Abs(v - NumGet(lum, idx + 1, "UChar"))
                if d > maxd
                    maxd := d
            }
            if gy > 0 {
                d := Abs(v - NumGet(lum, idx - gw, "UChar"))
                if d > maxd
                    maxd := d
            }
            if gy < gh - 1 {
                d := Abs(v - NumGet(lum, idx + gw, "UChar"))
                if d > maxd
                    maxd := d
            }
            NumPut("UChar", maxd > thresh ? 1 : 0, mask, idx)
        }
    }
    return Map("mask", mask, "gw", gw, "gh", gh)
}

; Group interesting cells into connected blobs (8-connectivity).
VS_ConnectedComponents(mask, gw, gh) {
    seen := Buffer(gw * gh, 0)
    blobs := []
    stack := []
    Loop gw * gh {
        start := A_Index - 1
        if NumGet(mask, start, "UChar") = 0 || NumGet(seen, start, "UChar") = 1
            continue
        minGx := gw, maxGx := -1, minGy := gh, maxGy := -1, cells := 0
        stack.Length := 0
        stack.Push(start)
        NumPut("UChar", 1, seen, start)
        while stack.Length {
            cur := stack.Pop()
            cells++
            gx := Mod(cur, gw)
            gy := cur // gw
            if gx < minGx
                minGx := gx
            if gx > maxGx
                maxGx := gx
            if gy < minGy
                minGy := gy
            if gy > maxGy
                maxGy := gy
            Loop 3 {
                dy := A_Index - 2
                Loop 3 {
                    dx := A_Index - 2
                    if dx = 0 && dy = 0
                        continue
                    nx := gx + dx, ny := gy + dy
                    if nx < 0 || ny < 0 || nx >= gw || ny >= gh
                        continue
                    ni := ny * gw + nx
                    if NumGet(mask, ni, "UChar") = 0 || NumGet(seen, ni, "UChar") = 1
                        continue
                    NumPut("UChar", 1, seen, ni)
                    stack.Push(ni)
                }
            }
        }
        blobs.Push(Map("minGx", minGx, "maxGx", maxGx, "minGy", minGy, "maxGy", maxGy, "cells", cells))
    }
    return blobs
}

; Convert blobs to screen-space bounding boxes, filtering by size.
VS_BlobsToBoxes(blobs, step, offX, offY, w, h, minCells, maxFrac) {
    boxes := []
    for b in blobs {
        if b["cells"] < minCells
            continue
        x1 := offX + b["minGx"] * step
        y1 := offY + b["minGy"] * step
        x2 := Min(offX + w - 1, offX + (b["maxGx"] + 1) * step)
        y2 := Min(offY + h - 1, offY + (b["maxGy"] + 1) * step)
        bw := x2 - x1
        bh := y2 - y1
        if bw < 8 || bh < 8
            continue
        if bw > w * maxFrac || bh > h * maxFrac
            continue
        boxes.Push(Map("x1", x1, "y1", y1, "x2", x2, "y2", y2, "w", bw, "h", bh))
    }
    return boxes
}

; Merge boxes whose expanded rectangles intersect.
VS_MergeBoxes(boxes, dist) {
    if !boxes.Length
        return boxes
    merged := []
    for b in boxes {
        placed := false
        for i, m in merged {
            ex1 := b["x1"] - dist, ey1 := b["y1"] - dist
            ex2 := b["x2"] + dist, ey2 := b["y2"] + dist
            if ex1 < m["x2"] && ex2 > m["x1"] && ey1 < m["y2"] && ey2 > m["y1"] {
                m["x1"] := Min(m["x1"], b["x1"])
                m["y1"] := Min(m["y1"], b["y1"])
                m["x2"] := Max(m["x2"], b["x2"])
                m["y2"] := Max(m["y2"], b["y2"])
                m["w"] := m["x2"] - m["x1"]
                m["h"] := m["y2"] - m["y1"]
                placed := true
                break
            }
        }
        if !placed
            merged.Push(Map("x1", b["x1"], "y1", b["y1"], "x2", b["x2"], "y2", b["y2"], "w", b["w"], "h", b["h"]))
    }
    ; Repeat once more to collapse chains created by the first pass.
    if merged.Length < boxes.Length
        return VS_MergeBoxes(merged, dist)
    return merged
}

; Capture a FindText pattern for a screen rectangle. Returns the raw encoded
; pattern text ("" when the region has no usable pixels).
VS_CapturePattern(x1, y1, x2, y2) {
    if (x2 - x1) < 4 || (y2 - y1) < 4
        return ""
    try {
        text := FindText().GetTextFromScreen(x1, y1, x2, y2, "**50")
        if (text != "" && StrLen(text) >= 8)
            return text
    } catch as err {
        TrackLogError("VS_CapturePattern", err)
    }
    return ""
}

; Register a set of merged boxes as elements (dedupe + FindText capture).
VS_RegisterElements(merged, winId, appId, regionX, regionY, regionW, regionH) {
    global g_VSElements, g_VSMaxScanElements, g_VSLastScanIds
    added := 0
    g_VSLastScanIds := []
    now := TrackTS()
    for box in merged {
        if g_VSLastScanIds.Length >= g_VSMaxScanElements
            break
        w := box["w"], h := box["h"]
        if w < 8 || h < 8
            continue
        cx := box["x1"], cy := box["y1"]
        relX := regionW > 0 ? Round((cx - regionX) / regionW, 5) : 0.0
        relY := regionH > 0 ? Round((cy - regionY) / regionH, 5) : 0.0
        relW := regionW > 0 ? Round(w / regionW, 5) : 0.0
        relH := regionH > 0 ? Round(h / regionH, 5) : 0.0

        ; Dedupe against an existing element in the same window by overlap.
        existing := VS_FindOverlapping(winId, cx, cy, w, h)
        if existing.Count {
            VS_UpdateElementRect(existing, cx, cy, w, h, relX, relY, relW, relH, now)
            g_VSLastScanIds.Push(Integer(existing["id"]))
            continue
        }

        pattern := VS_CapturePattern(cx, cy, cx + w, cy + h)
        if pattern = ""
            continue

        db := TrackDB()
        if !db
            continue
        db.Run("INSERT INTO vs_element(win_id,app_id,x,y,w,h,rel_x,rel_y,rel_w,rel_h,bin_text,first_seen,last_seen) "
             . "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)"
             , winId, appId, cx, cy, w, h, relX, relY, relW, relH, pattern, now, now)
        id := db.LastInsertId()
        g_VSElements.Push(Map(
            "id", Integer(id), "win_id", winId, "app_id", appId,
            "x", cx, "y", cy, "w", w, "h", h,
            "rel_x", relX, "rel_y", relY, "rel_w", relW, "rel_h", relH,
            "bin_text", pattern, "ocr_text", "",
            "score", 0.0, "clicks", 0, "accesses", 0, "tier", 0, "promoted", 0,
            "review_state", "unreviewed", "review_note", "", "reviewed_at", "",
            "first_seen", now, "last_seen", now))
        g_VSLastScanIds.Push(Integer(id))
        added++
        LearningLab_Record("Vision Scout", id, "Visual candidate #" . id . " can be recognized", "observed", LearningLab_Context(),
            "FindText candidate captured, awaiting testing.", "vs_element:" . id, "Test and certify this candidate in Vision Scout before exporting it to Patterns. Recheck after changing application state.")
        LearningValidation_Event("Vision Scout", "stored", "Visual candidate #" . id . " captured", Map("x",cx,"y",cy,"w",w,"h",h))
    }
    if added
        VS_SortElements()
    return added
}

VS_FindOverlapping(winId, x, y, w, h) {
    global g_VSElements
    area := w * h
    if area <= 0
        return Map()
    best := Map()
    bestIoU := 0.5
    for el in g_VSElements {
        if winId != 0 && Integer(el["win_id"]) != 0 && Integer(el["win_id"]) != winId
            continue
        ix1 := Max(x, Integer(el["x"]))
        iy1 := Max(y, Integer(el["y"]))
        ix2 := Min(x + w, Integer(el["x"]) + Integer(el["w"]))
        iy2 := Min(y + h, Integer(el["y"]) + Integer(el["h"]))
        if ix2 <= ix1 || iy2 <= iy1
            continue
        inter := (ix2 - ix1) * (iy2 - iy1)
        union := area + Integer(el["w"]) * Integer(el["h"]) - inter
        iou := inter / Max(union, 1)
        if iou > bestIoU {
            bestIoU := iou
            best := el
        }
    }
    return best
}

VS_UpdateElementRect(el, x, y, w, h, relX, relY, relW, relH, now) {
    ; A human-adjusted certified box outranks the coarse edge-segmentation box.
    ; Re-scans may confirm that it is present, but must not undo the vetted
    ; position that its saved FindText pattern and export are based on.
    if VS_ElementReviewState(el) = "certified" {
        el["last_seen"] := now
        db := TrackDB()
        if db
            db.Run("UPDATE vs_element SET last_seen=? WHERE id=?", now, el["id"])
        return
    }
    el["x"] := x, el["y"] := y, el["w"] := w, el["h"] := h
    el["rel_x"] := relX, el["rel_y"] := relY, el["rel_w"] := relW, el["rel_h"] := relH
    el["last_seen"] := now
    db := TrackDB()
    if db {
        db.Run("UPDATE vs_element SET x=?,y=?,w=?,h=?,rel_x=?,rel_y=?,rel_w=?,rel_h=?,last_seen=? WHERE id=?"
             , x, y, w, h, relX, relY, relW, relH, now, el["id"])
    }
}

VS_SortElements() {
    global g_VSElements
    VS_SortRowsBy(g_VSElements, "score", true)
}

; Generic descending sort on a numeric key (insertion sort; lists are short).
VS_SortRowsBy(arr, key, desc) {
    i := 2
    while i <= arr.Length {
        item := arr[i]
        j := i - 1
        while j >= 1 {
            a := Float(arr[j][key])
            b := Float(item[key])
            if (desc ? (a >= b) : (a <= b))
                break
            arr[j + 1] := arr[j]
            j--
        }
        arr[j + 1] := item
        i++
    }
    return arr
}

; ═══════════════════════════════════════════════════════════════════════════════
; ELEMENT MATCHING + PROMOTION
; ═══════════════════════════════════════════════════════════════════════════════

VS_LoadElements() {
    global g_VSElements
    db := TrackDB()
    g_VSElements := []
    if db
        g_VSElements := db.Query("SELECT * FROM vs_element ORDER BY tier DESC, score DESC")
}

; Find the element whose box contains a screen point (smallest area wins).
VS_MatchElement(sx, sy) {
    global g_VSElements
    best := Map()
    bestArea := 0x7FFFFFFF
    for el in g_VSElements {
        x := Integer(el["x"]) - 6, y := Integer(el["y"]) - 6
        x2 := x + Integer(el["w"]) + 12, y2 := y + Integer(el["h"]) + 12
        if sx >= x && sx <= x2 && sy >= y && sy <= y2 {
            area := Integer(el["w"]) * Integer(el["h"])
            if area < bestArea {
                bestArea := area
                best := el
            }
        }
    }
    return best
}

; Record an access to an element and promote it when its score crosses a tier.
VS_BumpElement(el, clickBool) {
    inc := clickBool ? 10.0 : 2.0
    el["score"] := Float(el["score"]) + inc
    el["accesses"] := Integer(el["accesses"]) + 1
    if clickBool
        el["clicks"] := Integer(el["clicks"]) + 1
    el["last_seen"] := TrackTS()
    newTier := Float(el["score"]) >= 30 ? 3 : Float(el["score"]) >= 10 ? 2 : Float(el["score"]) >= 1 ? 1 : 0
    if newTier > Integer(el["tier"]) {
        el["tier"] := newTier
    }
    if newTier >= 2 && Integer(el["promoted"]) = 0 {
        el["promoted"] := 1
        VS_RecapturePattern(el)
    }
    db := TrackDB()
    if db {
        db.Run("UPDATE vs_element SET score=?,clicks=?,accesses=?,tier=?,promoted=?,last_seen=? WHERE id=?"
             , el["score"], el["clicks"], el["accesses"], el["tier"], el["promoted"], el["last_seen"], el["id"])
    }
    return newTier
}

; Refresh a promoted element's pattern at its current on-screen location.
VS_RecapturePattern(el) {
    ; Prefer the current live location (via the old pattern), else stored coords.
    x1 := Integer(el["x"]), y1 := Integer(el["y"])
    w := Integer(el["w"]), h := Integer(el["h"])
    if el["bin_text"] != "" {
        try {
            ok := FindText(&fx, &fy, 0, 0, A_ScreenWidth, A_ScreenHeight, 0.2, 0.15, "|<vs>" . el["bin_text"])
            if ok && ok.Length {
                x1 := ok[1].x, y1 := ok[1].y
                w := Max(8, ok[1].w), h := Max(8, ok[1].h)
            }
        }
    }
    p := VS_CapturePattern(x1, y1, x1 + w, y1 + h)
    if p != "" {
        el["bin_text"] := p
        db := TrackDB()
        if db
            db.Run("UPDATE vs_element SET bin_text=? WHERE id=?", p, el["id"])
    }
}

; Promote everything that already crossed a tier threshold (recompute + recapture).
VS_ApplyPromotion() {
    global g_VSElements
    VS_LoadElements()
    count := 0
    for el in g_VSElements {
        tier := Float(el["score"]) >= 30 ? 3 : Float(el["score"]) >= 10 ? 2 : Float(el["score"]) >= 1 ? 1 : 0
        if tier != Integer(el["tier"]) || (tier >= 2 && Integer(el["promoted"]) = 0) {
            el["tier"] := tier
            if tier >= 2 {
                el["promoted"] := 1
                VS_RecapturePattern(el)
            }
            db := TrackDB()
            if db
                db.Run("UPDATE vs_element SET tier=?,promoted=? WHERE id=?", tier, el["promoted"], el["id"])
            count++
        }
    }
    VS_SortElements()
    VS_Refresh()
    return count
}

; Export human-certified elements into the Patterns tab as first-class FindText
; patterns.  Frequency promotion alone is intentionally not enough: the review
; gate prevents incidental edges/background noise from entering workflows.
VS_ExportPromoted() {
    global g_Patterns
    VS_LoadElements()
    exported := 0
    eligible := 0
    for el in g_VSElements {
        state := el.Has("review_state") ? el["review_state"] : "unreviewed"
        if state != "certified" || el["bin_text"] = ""
            continue
        eligible++
        name := "VS_" . TrackSafeName("el" . el["id"])
        patternText := "|<" . name . ">" . el["bin_text"]
        try {
            if !IsObject(g_Patterns)
                continue
            ; Re-export updates the reserved VS_el<ID> entry after a candidate
            ; has been repositioned/re-certified instead of leaving stale code.
            g_Patterns[name] := Map("text", patternText, "desc", "Certified by Vision Scout (id " . el["id"] . ")", "screenshot", "")
            exported++
        } catch as err {
            TrackLogError("VS_ExportPromoted", err)
        }
    }
    if exported {
        try SavePatterns()
        try RefreshPatternLV()
        try UpdateTargetDD()
        try UpdateQualPatternDD()
        ShowStatus("Exported " . exported . " certified element(s) to Patterns", "ok")
    } else {
        ShowStatus(eligible ? "Certified elements could not be exported" : "No certified elements yet — review and certify a candidate first", "info")
    }
    return exported
}

; ═══════════════════════════════════════════════════════════════════════════════
; USAGE CAPTURE (mouse / keys / window)
; ═══════════════════════════════════════════════════════════════════════════════

VS_StartInputHook() {
    global g_VSHook
    if IsObject(g_VSHook)
        return
    try {
        ih := InputHook("I1 V")
        ih.VisibleText := true
        ih.VisibleNonText := true
        ih.NotifyNonText := true
        ih.KeyOpt("{All}", "N")
        ih.OnChar := VS_OnChar
        ih.OnKeyDown := VS_OnKeyDown
        ih.Start()
        g_VSHook := ih
    } catch as err {
        TrackLogError("VS_StartInputHook", err)
    }
}

VS_StopInputHook() {
    global g_VSHook
    if IsObject(g_VSHook) {
        try g_VSHook.Stop()
    }
    g_VSHook := ""
}

; Printable characters (no modifier): accumulate into the current typing run.
VS_OnChar(ih, char) {
    global g_VSTextRun, g_VSLastCharTick, g_VSPauseMs
    if GetKeyState("Control", "P") || GetKeyState("Alt", "P")
        || GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
        return
    now := A_TickCount
    if g_VSLastCharTick && (now - g_VSLastCharTick) > g_VSPauseMs
        VS_CloseRun()
    g_VSLastCharTick := now
    g_VSTextRun.Push(char)
}

; Non-text keys: close any typing run, then record a step for meaningful keys.
VS_OnKeyDown(ih, vk, sc) {
    keyName := ""
    try keyName := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
    if keyName = ""
        return
    if TrackArrayHas(["LControl", "RControl", "LShift", "RShift", "LAlt", "RAlt"
                    , "LWin", "RWin", "Control", "Shift", "Alt"], keyName)
        return

    ctrl := GetKeyState("Control", "P")
    alt := GetKeyState("Alt", "P")
    win := GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
    shift := GetKeyState("Shift", "P")

    if ctrl || alt || win {
        VS_CloseRun()
        combo := (ctrl ? "^" : "") . (alt ? "!" : "") . (shift ? "+" : "") . (win ? "#" : "")
        combo .= (StrLen(keyName) = 1) ? StrLower(keyName) : "{" . keyName . "}"
        VS_RecordEvent("hotkey", 0, 0, combo)
        return
    }

    switch keyName {
        case "Backspace":
            return  ; correcting within a run: do not split or emit
        case "Enter", "NumpadEnter":
            VS_CloseRun()
            VS_RecordEvent("key", 0, 0, "{Enter}")
            return
        case "Tab":
            VS_CloseRun()
            VS_RecordEvent("key", 0, 0, "{Tab}")
            return
        case "Escape":
            VS_CloseRun()
            VS_RecordEvent("key", 0, 0, "{Esc}")
            return
        case "Space":
            return  ; already captured by OnChar as " "
    }
    ; Other non-text keys (arrows, function keys, Home/End, Delete...) break the
    ; run and emit a step. Single-character names are text keys owned by OnChar,
    ; so they are deliberately ignored here to avoid fragmenting typing runs.
    if StrLen(keyName) > 1 {
        VS_CloseRun()
        VS_RecordEvent("key", 0, 0, "{" . keyName . "}")
    }
}

VS_CloseRun() {
    global g_VSTextRun
    if g_VSTextRun.Length {
        text := TrackArrayJoin(g_VSTextRun, "")
        g_VSTextRun := []
        VS_RecordEvent("type", 0, 0, TrackEllipsis(text, 120))
    }
}

; Poll mouse buttons for edges (passive: never steals the input).
VS_PollMouse() {
    global g_VSOn, g_VSMouseBtnDown, g_VSReplaying, g_VSDwellX, g_VSDwellY, g_VSDwellStart, g_VSDwellCounted
    global g_VSDwellRadius, g_VSDwellMinMs
    if !g_VSOn || g_VSReplaying
        return

    MouseGetPos(&sx, &sy)
    now := A_TickCount

    ; ─── Dwell access: the pointer resting over an element ───────────────────
    if g_VSDwellStart = 0 {
        g_VSDwellStart := now, g_VSDwellX := sx, g_VSDwellY := sy, g_VSDwellCounted := false
    } else {
        dx := sx - g_VSDwellX, dy := sy - g_VSDwellY
        if Sqrt(dx * dx + dy * dy) > g_VSDwellRadius {
            g_VSDwellStart := now, g_VSDwellX := sx, g_VSDwellY := sy, g_VSDwellCounted := false
        } else if !g_VSDwellCounted && (now - g_VSDwellStart) >= g_VSDwellMinMs {
            g_VSDwellCounted := true
            el := VS_MatchElement(sx, sy)
            if el.Count
                VS_BumpElement(el, false)
        }
    }

    ; ─── Click edges ──────────────────────────────────────────────────────────
    for code, btn in Map("L", "LButton", "R", "RButton", "M", "MButton") {
        down := GetKeyState(btn, "P")
        if down && !g_VSMouseBtnDown[code] {
            VS_RecordClick(sx, sy, code)
        }
        g_VSMouseBtnDown[code] := down
    }
}

VS_RecordClick(sx, sy, code) {
    el := VS_MatchElement(sx, sy)
    elementId := 0
    if el.Count {
        elementId := Integer(el["id"])
        VS_BumpElement(el, true)
    }
    VS_RecordEvent("click", sx, sy, code, elementId)
}

; Watch the foreground window and emit an "activate" step when it changes.
VS_PollWindow() {
    global g_VSOn, g_VSLastWinId, g_VSReplaying
    if !g_VSOn || g_VSReplaying
        return
    ctx := TrackCtx_Get(500)
    if ctx["win_id"] && ctx["win_id"] != g_VSLastWinId {
        g_VSLastWinId := ctx["win_id"]
        VS_RecordEvent("activate", 0, 0, ctx["name"])
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; EVENT RECORDING + STEP COMPRESSION
; ═══════════════════════════════════════════════════════════════════════════════

; Record one usage event: append to the in-memory rings, compress to a step,
; queue for persistence, and run prediction. `elementId` is set by callers that
; already resolved the click target.
VS_RecordEvent(kind, x, y, label, elementId := 0) {
    global g_VSOn, g_VSRecent, g_VSSteps, g_VSFlushQueue, g_VSMaxSteps, g_VSMaxRecent
    if !g_VSOn
        return

    ctx := TrackCtx_Get(500)
    ev := Map("ts", TrackTS(), "tick", A_TickCount, "kind", kind
            , "win_id", ctx["win_id"], "app_id", ctx["app_id"]
            , "element_id", elementId, "x", x, "y", y, "label", label)

    g_VSRecent.Push(ev)
    if g_VSRecent.Length > g_VSMaxRecent
        g_VSRecent.RemoveAt(1)

    token := VS_ToStepToken(ev)
    if token != "" {
        g_VSSteps.Push(token)
        if g_VSSteps.Length > g_VSMaxSteps
            g_VSSteps.RemoveAt(1)
        VS_AfterStep(token)
    }

    g_VSFlushQueue.Push(ev)
}

VS_ToStepToken(ev) {
    switch ev["kind"] {
        case "click":
            if Integer(ev["element_id"]) > 0
                return "click@" . Integer(ev["element_id"])
            return "click@" . Integer(ev["x"]) . "," . Integer(ev["y"])
        case "type":
            return "type"
        case "hotkey":
            return "hk:" . ev["label"]
        case "key":
            return "key:" . ev["label"]
        case "activate":
            return "win:" . ev["label"]
    }
    return ""
}

; Persist queued events in one transaction.
VS_FlushQueue() {
    global g_VSFlushQueue
    if !g_VSFlushQueue.Length
        return
    db := TrackDB()
    if !db {
        g_VSFlushQueue := []
        return
    }
    q := g_VSFlushQueue
    g_VSFlushQueue := []
    db.Begin()
    try {
        for ev in q {
            db.Run("INSERT INTO vs_action(ts,tick,kind,win_id,app_id,element_id,x,y,label,detail) "
                 . "VALUES(?,?,?,?,?,?,?,?,?,?)"
                 , ev["ts"], ev["tick"], ev["kind"], ev["win_id"], ev["app_id"]
                 , ev["element_id"], ev["x"], ev["y"], ev["label"], ev["kind"])
        }
    } catch as err {
        db.Rollback()
        TrackLogError("VS_FlushQueue", err)
        return
    }
    db.Commit()
}

; ═══════════════════════════════════════════════════════════════════════════════
; SEQUENCE MINING + PREDICTION
; ═══════════════════════════════════════════════════════════════════════════════

VS_LoadSequences() {
    global g_VSSequences
    db := TrackDB()
    g_VSSequences := []
    if !db
        return
    for row in db.Query("SELECT * FROM vs_sequence ORDER BY length DESC, count DESC") {
        row["stepsArr"] := VS_DecodeSteps(row["steps"])
        g_VSSequences.Push(row)
    }
}

VS_EncodeSteps(arr) {
    return TrackJsonEncode(arr)
}

VS_DecodeSteps(text) {
    if text = "" || text = "[]"
        return []
    try {
        v := TrackJsonDecode(text)
        return IsObject(v) ? v : []
    } catch {
        return []
    }
}

VS_MineSequencesTimer() {
    global g_VSOn
    if g_VSOn
        VS_MineSequences()
}

; Mine frequent sub-sequences from the in-memory compressed step ring.
VS_MineSequences() {
    global g_VSSteps, g_VSSequences, g_VSMinSupport, g_VSMaxSeqLen
    if g_VSSteps.Length < g_VSMinSupport + 1
        return 0

    ; Count n-grams and tally the token that follows each.
    counts := Map()   ; key -> Map("count", n, "next", Map(token -> n), "last", tick)
    Loop g_VSSteps.Length {
        i := A_Index
        maxLen := Min(g_VSMaxSeqLen, g_VSSteps.Length - i + 1)
        if maxLen < 3
            continue
        n := 3
        while n <= maxLen {
            key := ""
            Loop n {
                if A_Index > 1
                    key .= Chr(31)
                key .= g_VSSteps[i + A_Index - 1]
            }
            entry := counts.Has(key) ? counts[key] : Map("count", 0, "next", Map())
            entry["count"] := entry["count"] + 1
            ; The following step (continuation) is tallied.
            if i + n <= g_VSSteps.Length {
                nxt := g_VSSteps[i + n]
                entry["next"][nxt] := entry["next"].Has(nxt) ? entry["next"][nxt] + 1 : 1
            }
            counts[key] := entry
            n++
        }
    }

    ; Keep frequent ones and persist.
    db := TrackDB()
    if !db
        return 0
    learned := 0
    now := TrackTS()
    db.Begin()
    try {
        for key, entry in counts {
            if entry["count"] < g_VSMinSupport
                continue
            steps := StrSplit(key, Chr(31))
            if steps.Length < 3
                continue
            sig := TrackHash(key)
            db.Run("INSERT INTO vs_sequence(sig,steps,count,length,first_seen,last_seen) "
                 . "VALUES(?,?,?,?,?,?) ON CONFLICT(sig) DO UPDATE SET "
                 . "steps=excluded.steps, count=excluded.count, length=excluded.length, last_seen=excluded.last_seen"
                 , sig, VS_EncodeSteps(steps), entry["count"], steps.Length, now, now)
            learned++
        }
    } catch as err {
        db.Rollback()
        TrackLogError("VS_MineSequences", err)
        return 0
    }
    db.Commit()
    VS_LoadSequences()
    return learned
}

; Called after every new compressed step: try to match a learned sequence prefix.
VS_AfterStep(token) {
    global g_VSSteps, g_VSOfferCooldownMs, g_VSLastOfferTick, g_VSLastOfferSig
    if g_VSSteps.Length < g_VSMinPrefix
        return
    cand := VS_FindContinuation()
    if !cand.Count
        return
    if cand["sig"] = g_VSLastOfferSig && (A_TickCount - g_VSLastOfferTick) < g_VSOfferCooldownMs
        return
    VS_ArmOffer(cand)
}

VS_FindContinuation() {
    global g_VSSteps, g_VSSequences, g_VSMinPrefix
    best := Map()
    bestScore := 0
    ; Try progressively longer recent tails (longest match wins).
    k := Min(4, g_VSSteps.Length)
    while k >= g_VSMinPrefix {
        tail := []
        Loop k
            tail.Push(g_VSSteps[g_VSSteps.Length - k + A_Index])
        for seq in g_VSSequences {
            steps := seq["stepsArr"]
            if steps.Length <= k
                continue
            match := true
            Loop k {
                if steps[A_Index] != tail[A_Index] {
                    match := false
                    break
                }
            }
            if !match
                continue
            cont := []
            i := k + 1
            while i <= steps.Length {
                cont.Push(steps[i])
                i++
            }
            if !cont.Length
                continue
            score := Integer(seq["count"]) * (steps.Length - k)
            if score > bestScore {
                bestScore := score
                best := Map("sig", seq["sig"], "name", VS_SeqName(steps), "continuation", cont, "count", Integer(seq["count"]))
            }
        }
        if best.Count
            break
        k--
    }
    return best
}

; A short human-readable label for a learned sequence.
VS_SeqName(steps) {
    parts := []
    i := 1
    while i <= Min(steps.Length, 4) {
        t := steps[i]
        if InStr(t, "click@") = 1
            parts.Push("Click")
        else if t = "type"
            parts.Push("Type")
        else if InStr(t, "hk:") = 1
            parts.Push("Hotkey " . SubStr(t, 4))
        else if InStr(t, "key:") = 1
            parts.Push(SubStr(t, 5))
        else if InStr(t, "win:") = 1
            parts.Push("Go " . TrackEllipsis(SubStr(t, 5), 14))
        else
            parts.Push(t)
        i++
    }
    return TrackArrayJoin(parts, " → ")
}

; ═══════════════════════════════════════════════════════════════════════════════
; OFFER + AUTO-RUN
; ═══════════════════════════════════════════════════════════════════════════════

VS_ArmOffer(cand) {
    global g_VSPending, g_VSOfferArmed, g_VSLastOfferTick, g_VSLastOfferSig
    g_VSPending := cand
    g_VSLastOfferTick := A_TickCount
    g_VSLastOfferSig := cand["sig"]
    try Hotkey("#CapsLock", VS_ContinueHandler, "On")
    g_VSOfferArmed := true
    TrackToolTip("⚡ Sequence '" . cand["name"] . "' — press Win+CapsLock to continue and automate " . cand["continuation"].Length . " step(s)")
    SetTimer(VS_ClearOfferTip, -6000)
}

VS_ClearOfferTip(*) {
    TrackToolTip()
}

VS_DisarmOffer() {
    global g_VSPending, g_VSOfferArmed
    if g_VSOfferArmed {
        try Hotkey("#CapsLock", "Off")
        g_VSOfferArmed := false
    }
    g_VSPending := Map()
    TrackToolTip()
}

VS_ContinueHandler(*) {
    global g_VSPending
    if !g_VSPending.Count
        return
    cand := g_VSPending
    VS_DisarmOffer()
    VS_ExecuteContinuation(cand["continuation"])
}

; Execute the learned continuation steps.
VS_ExecuteContinuation(steps) {
    global g_VSReplaying
    if !steps.Length
        return
    g_VSReplaying := true
    done := 0
    try {
        ShowStatus("Vision Scout: running learned sequence (" . steps.Length . " steps)", "wait")
        for t in steps {
            if VS_ExecuteStepToken(t)
                done++
            Sleep(220)
        }
    } finally {
        g_VSReplaying := false
    }
    ShowStatus("Vision Scout: sequence complete (" . done . "/" . steps.Length . " steps)", done = steps.Length ? "ok" : "info")
    ShowNotificationBasic("Vision Scout", "Automated " . done . " learned step(s)", 3000, "success")
}

VS_ExecuteStepToken(t) {
    if InStr(t, "click@") = 1 {
        rest := SubStr(t, 7)
        if RegExMatch(rest, "^\d+$") {
            return VS_ClickElementById(Integer(rest))
        }
        if InStr(rest, ",") {
            p := StrSplit(rest, ",")
            if p.Length >= 2 && IsNumber(Trim(p[1])) && IsNumber(Trim(p[2])) {
                Click(Integer(Trim(p[1])), Integer(Trim(p[2])))
                return true
            }
        }
        return false
    }
    if InStr(t, "hk:") = 1 {
        Send(SubStr(t, 4))
        return true
    }
    if InStr(t, "key:") = 1 {
        Send(SubStr(t, 5))
        return true
    }
    if InStr(t, "win:") = 1 {
        name := SubStr(t, 5)
        return VS_ActivateWindow(name)
    }
    if t = "type" {
        ; Freeform text cannot be predicted/replayed; leave focus for the user.
        ShowStatus("Vision Scout: type here (text not auto-filled)", "info")
        return false
    }
    return false
}

VS_ClickElementById(id) {
    global g_VSElements
    el := Map()
    for e in g_VSElements {
        if Integer(e["id"]) = id {
            el := e
            break
        }
    }
    if !el.Count {
        db := TrackDB()
        if db
            el := db.QueryRow("SELECT * FROM vs_element WHERE id=?", id)
    }
    if !el.Count
        return false
    return VS_ClickElement(el)
}

VS_ClickElement(el) {
    ; 1. Visual: re-find the stored FindText pattern anywhere on screen.
    if el["bin_text"] != "" {
        try {
            ok := FindText(&fx, &fy, 0, 0, A_ScreenWidth, A_ScreenHeight, 0.2, 0.15, "|<vs>" . el["bin_text"])
            if ok && ok.Length {
                Click(ok[1].mx, ok[1].my)
                return true
            }
        }
    }
    ; 2. Relative projection onto the live window.
    winId := Integer(el["win_id"])
    if winId {
        winRow := TrackDB_WinRow(winId)
        if winRow.Count {
            hwnd := Element_FindLiveWindow(winRow["name"])
            if hwnd {
                try {
                    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . hwnd)
                    cx := wx + Integer(Round(Float(el["rel_x"]) * ww + Float(el["rel_w"]) * ww / 2))
                    cy := wy + Integer(Round(Float(el["rel_y"]) * wh + Float(el["rel_h"]) * wh / 2))
                    Click(cx, cy)
                    return true
                }
            }
        }
    }
    ; 3. Last resort: stored absolute coordinates.
    Click(Integer(el["x"]) + Integer(el["w"]) // 2, Integer(el["y"]) + Integer(el["h"]) // 2)
    return true
}

VS_ActivateWindow(name) {
    if name = "" || name = "(untitled)"
        return false
    try {
        if WinExist(name) {
            WinActivate(name)
            return true
        }
    }
    return false
}

; ═══════════════════════════════════════════════════════════════════════════════
; SCAN ENTRY POINTS
; ═══════════════════════════════════════════════════════════════════════════════

; Scan the active window (default) or the whole screen, capturing FindText
; patterns for every visually distinct region. Returns the number of elements
; added.
VS_ScanScreen(scope := "window", showReview := false) {
    global g_VSScanBusy, g_VSScanStep, g_VSContrastThresh, g_VSMinAreaCells, g_VSMaxAreaFrac, g_VSMergeDist, g_VSLastScanIds
    if g_VSScanBusy
        return 0
    if !VisionScout_Init() {
        if showReview
            VS_EndReview(true)
        return 0
    }
    g_VSScanBusy := true
    g_VSLastScanIds := []
    added := 0
    try {
        winId := 0, appId := 0, x := 0, y := 0, w := A_ScreenWidth, h := A_ScreenHeight
        if scope = "window" {
            ctx := TrackCtx_Get(300)
            if ctx["win_id"] && ctx["w"] > 0 && ctx["h"] > 0 {
                x := ctx["x"], y := ctx["y"], w := ctx["w"], h := ctx["h"]
                winId := ctx["win_id"], appId := ctx["app_id"]
            }
        }
        ShowStatus("Vision Scout: scanning " . (scope = "window" ? "active window" : "full screen") . "...", "wait")
        cap := VS_CaptureRegion(x, y, w, h)
        if !cap.Count {
            ShowStatus("Vision Scout: capture failed", "fail")
            if showReview
                VS_EndReview(true)
            return 0
        }
        seg := VS_Segment(cap, g_VSScanStep, g_VSContrastThresh)
        blobs := VS_ConnectedComponents(seg["mask"], seg["gw"], seg["gh"])
        boxes := VS_BlobsToBoxes(blobs, g_VSScanStep, x, y, w, h, g_VSMinAreaCells, g_VSMaxAreaFrac)
        merged := VS_MergeBoxes(boxes, g_VSMergeDist)
        added := VS_RegisterElements(merged, winId, appId, x, y, w, h)
        VS_ReleaseCapture(cap)
    } catch as err {
        TrackLogError("VS_ScanScreen", err)
    } finally {
        g_VSScanBusy := false
    }
    VS_Refresh()
    total := g_VSLastScanIds.Length
    ShowStatus("Vision Scout: " . total . " candidate(s), " . added . " new, in " . (scope = "window" ? "active window" : "full screen"), total ? "ok" : "info")
    if showReview {
        if total
            VS_ShowReviewOverlays(g_VSLastScanIds)
        else
            VS_EndReview(true)
    }
    return added
}

VS_AutoScanTimer() {
    global g_VSOn
    if g_VSOn
        VS_ScanScreen("window")
}

; ═══════════════════════════════════════════════════════════════════════════════
; INTERACTIVE SCAN REVIEW
; ═══════════════════════════════════════════════════════════════════════════════

; A GUI button makes Macro Automator the active window.  Hide it and give the
; user a short targeting countdown before asking the scanner for "active window".
VS_BeginReviewScan(scope, *) {
    global MainGui, g_GuiVisible, g_VSRestoreMainGui, g_VSScanBusy
    if g_VSScanBusy {
        ShowStatus("Vision Scout: a scan is already running", "info")
        return
    }
    VS_DestroyReviewOverlays()
    g_VSRestoreMainGui := g_GuiVisible
    try MainGui.Hide()
    g_GuiVisible := false

    if scope = "window" {
        Loop 3 {
            left := 4 - A_Index
            TrackToolTip("Vision Scout: focus the window to scan — " . left, 24, 24, 18)
            Sleep(1000)
        }
    } else {
        TrackToolTip("Vision Scout: scanning the visible desktop...", 24, 24, 18)
        Sleep(350)
    }
    TrackToolTip("", , , 18)
    VS_ScanScreen(scope, true)
}

; Open review mode for the most recent scan without scanning again.
VS_ShowLastScan(*) {
    global g_VSLastScanIds
    if !g_VSLastScanIds.Length {
        ShowStatus("Vision Scout: no scan results to review yet", "info")
        return
    }
    VS_OpenReview(g_VSLastScanIds)
}

; Open review mode for the row selected in Discovered Elements.
VS_ReviewSelected(*) {
    global g_VSElemLV
    if !IsObject(g_VSElemLV)
        return
    row := g_VSElemLV.GetNext()
    if !row {
        ShowStatus("Vision Scout: select an element row first", "info")
        return
    }
    VS_OpenReview([Integer(g_VSElemLV.GetText(row, 1))])
}

VS_OpenReview(ids) {
    global MainGui, g_GuiVisible, g_VSRestoreMainGui
    g_VSRestoreMainGui := g_GuiVisible
    try MainGui.Hide()
    g_GuiVisible := false
    if !VS_ShowReviewOverlays(ids)
        VS_EndReview(true)
}

VS_ElementById(id) {
    global g_VSElements
    for el in g_VSElements {
        if Integer(el["id"]) = Integer(id)
            return el
    }
    return Map()
}

VS_ElementReviewState(el) {
    if !el.Count || !el.Has("review_state") || el["review_state"] = ""
        return "unreviewed"
    return el["review_state"]
}

VS_ReviewColor(el, selected := false) {
    if selected
        return "039BE5"                    ; blue = selected
    switch VS_ElementReviewState(el) {
        case "certified": return "43A047" ; green = approved
        case "rejected":  return "E53935" ; red = rejected/noise
        default:          return "FBC02D" ; amber = needs review
    }
}

VS_EnsureOverlayMessages() {
    global g_VSOverlayMessagesReady
    if g_VSOverlayMessagesReady
        return
    OnMessage(0x0201, VS_OverlayMouseDown)  ; WM_LBUTTONDOWN
    OnMessage(0x0232, VS_OverlayMoveDone)  ; WM_EXITSIZEMOVE
    g_VSOverlayMessagesReady := true
}

; Draw a translucent, clickable box for every candidate.  The minimum display
; size keeps tiny icon/text regions selectable; the stored recognition bounds
; remain unchanged unless Test/Certify obtains a new FindText match.
VS_ShowReviewOverlays(ids := "") {
    global g_VSLastScanIds, g_VSReviewOverlays, g_VSOverlayHandleMap
    global g_VSReviewSelectedId
    if !IsObject(ids)
        ids := g_VSLastScanIds
    VS_DestroyReviewOverlays()
    VS_EnsureOverlayMessages()

    shown := 0
    firstId := 0
    for id in ids {
        el := VS_ElementById(id)
        if !el.Count
            continue
        x := Integer(el["x"]), y := Integer(el["y"])
        drawW := Max(26, Integer(el["w"])), drawH := Max(18, Integer(el["h"]))
        if LearningValidation_PrimaryRegion(x, y, drawW, drawH) {
            LearningValidation_Event("Vision review", "observed", "Candidate #" . id, Map("x",x,"y",y,"w",drawW,"h",drawH))
            if !firstId
                firstId := Integer(id)
            shown++
            continue
        }
        overlayGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "VS candidate " . id)
        overlayGui.MarginX := 0
        overlayGui.MarginY := 0
        overlayGui.BackColor := VS_ReviewColor(el)
        overlayGui.SetFont("s8 Bold c202020", "Segoe UI")
        label := overlayGui.Add("Text", "x0 y0 w" . drawW . " h" . drawH . " Center +0x200 BackgroundTrans", "#" . id)
        g_VSReviewOverlays[Integer(id)] := Map("gui", overlayGui, "label", label, "draw_w", drawW, "draw_h", drawH)
        g_VSOverlayHandleMap[overlayGui.Hwnd] := Integer(id)
        g_VSOverlayHandleMap[label.Hwnd] := Integer(id)
        overlayGui.Show("NA x" . x . " y" . y . " w" . drawW . " h" . drawH)
        WinSetTransparent(82, overlayGui)
        if !firstId
            firstId := Integer(id)
        shown++
    }

    if !shown {
        ShowStatus("Vision Scout: this scan produced no reviewable regions", "info")
        return false
    }
    VS_ShowReviewPalette(shown)
    VS_SelectOverlay(firstId)
    ShowStatus("Vision Scout: review mode — " . shown . " selectable candidate(s)", "ok")
    return true
}

VS_DestroyReviewOverlays() {
    global g_VSReviewOverlays, g_VSOverlayHandleMap, g_VSReviewSelectedId
    for _, ov in g_VSReviewOverlays
        try ov["gui"].Destroy()
    g_VSReviewOverlays := Map()
    g_VSOverlayHandleMap := Map()
    g_VSReviewSelectedId := 0
}

VS_ShowReviewPalette(count) {
    global g_VSReviewPalette, g_VSReviewInfo
    if !IsObject(g_VSReviewPalette) {
        p := Gui("+AlwaysOnTop +ToolWindow", "Vision Scout Review")
        p.SetFont("s9", "Segoe UI")
        g_VSReviewInfo := p.Add("Text", "x12 y10 w416 h58", "Select a candidate...")
        p.Add("Button", "x12 y76 w76 h27", "Test Find").OnEvent("Click", VS_TestSelected)
        p.Add("Button", "x94 y76 w76 h27", "Certify").OnEvent("Click", VS_CertifySelected)
        p.Add("Button", "x176 y76 w76 h27", "Reject").OnEvent("Click", VS_RejectSelected)
        p.Add("Button", "x258 y76 w76 h27", "Reset").OnEvent("Click", VS_ResetSelected)
        p.Add("Button", "x340 y76 w88 h27", "Export").OnEvent("Click", (*) => VS_ExportPromoted())
        p.Add("Button", "x12 y109 w120 h25", "How to use this").OnEvent("Click", VS_ShowGuide)
        p.Add("Button", "x308 y109 w120 h25", "Done / Return").OnEvent("Click", (*) => VS_EndReview(true))
        p.OnEvent("Close", (*) => VS_EndReview(true))
        g_VSReviewPalette := p
    }
    g_VSReviewPalette.Title := "Vision Scout Review — " . count . " candidates"
    monitor := LearningValidation_Monitor()
    if !monitor
        return g_VSReviewPalette.Hide()
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    g_VSReviewPalette.Show("NA x" . (left+20) . " y" . (top+20) . " w440 h146")
}

VS_SelectOverlay(id, updateList := true) {
    global g_VSReviewSelectedId, g_VSReviewOverlays, g_VSElemLV
    oldId := g_VSReviewSelectedId
    g_VSReviewSelectedId := Integer(id)
    if oldId && g_VSReviewOverlays.Has(oldId)
        VS_StyleReviewOverlay(oldId, false)
    if g_VSReviewOverlays.Has(g_VSReviewSelectedId)
        VS_StyleReviewOverlay(g_VSReviewSelectedId, true)
    VS_UpdateReviewInfo()

    if updateList && IsObject(g_VSElemLV) {
        row := 0
        while row := g_VSElemLV.GetNext(row, "F") {
            if Integer(g_VSElemLV.GetText(row, 1)) = g_VSReviewSelectedId {
                g_VSElemLV.Modify(row, "Select Focus Vis")
                break
            }
        }
        ; GetNext(..., "F") only returns focused rows; fall back to a small
        ; linear search when focus has not yet been assigned.
        if !row {
            Loop g_VSElemLV.GetCount() {
                if Integer(g_VSElemLV.GetText(A_Index, 1)) = g_VSReviewSelectedId {
                    g_VSElemLV.Modify(A_Index, "Select Focus Vis")
                    break
                }
            }
        }
    }
}

VS_StyleReviewOverlay(id, selected := false) {
    global g_VSReviewOverlays
    if !g_VSReviewOverlays.Has(Integer(id))
        return
    el := VS_ElementById(id)
    if !el.Count
        return
    ov := g_VSReviewOverlays[Integer(id)]
    ov["gui"].BackColor := VS_ReviewColor(el, selected)
    try WinSetTransparent(selected ? 132 : 82, ov["gui"])
}

VS_UpdateReviewInfo(extra := "") {
    global g_VSReviewSelectedId, g_VSReviewInfo
    if !IsObject(g_VSReviewInfo)
        return
    el := VS_ElementById(g_VSReviewSelectedId)
    if !el.Count {
        g_VSReviewInfo.Value := "Click a colored candidate box to select it."
        return
    }
    state := StrUpper(VS_ElementReviewState(el))
    line := "Selected #" . el["id"] . "  |  " . state . "  |  box " . el["x"] . "," . el["y"] . "  " . el["w"] . "x" . el["h"]
    line .= "`nDrag the blue box to correct its position; Test Find checks whether its saved pattern can be found."
    if extra != ""
        line .= "`n" . extra
    g_VSReviewInfo.Value := line
}

VS_OverlayMouseDown(wParam, lParam, msg, hwnd) {
    global g_VSOverlayHandleMap, g_VSReviewOverlays
    if !g_VSOverlayHandleMap.Has(hwnd)
        return
    id := g_VSOverlayHandleMap[hwnd]
    if !g_VSReviewOverlays.Has(id)
        return
    VS_SelectOverlay(id)
    try DllCall("ReleaseCapture")
    try PostMessage(0x00A1, 2, 0, , "ahk_id " . g_VSReviewOverlays[id]["gui"].Hwnd) ; WM_NCLBUTTONDOWN/HTCAPTION
    return 0
}

VS_OverlayMoveDone(wParam, lParam, msg, hwnd) {
    global g_VSOverlayHandleMap
    if g_VSOverlayHandleMap.Has(hwnd)
        VS_SaveOverlayPosition(g_VSOverlayHandleMap[hwnd])
}

VS_SaveOverlayPosition(id) {
    global g_VSReviewOverlays
    if !g_VSReviewOverlays.Has(Integer(id))
        return
    ov := g_VSReviewOverlays[Integer(id)]
    try WinGetPos(&x, &y, , , "ahk_id " . ov["gui"].Hwnd)
    catch
        return
    el := VS_ElementById(id)
    if !el.Count
        return
    el["x"] := x, el["y"] := y
    el["last_seen"] := TrackTS()
    db := TrackDB()
    if db
        db.Run("UPDATE vs_element SET x=?,y=?,last_seen=? WHERE id=?", x, y, el["last_seen"], el["id"])
    VS_UpdateReviewInfo("Position saved.")
}

VS_SetReviewVisualsVisible(visible) {
    global g_VSReviewOverlays, g_VSReviewPalette
    for _, ov in g_VSReviewOverlays {
        if visible {
            try ov["gui"].Show("NA")
        } else {
            try ov["gui"].Hide()
        }
    }
    if IsObject(g_VSReviewPalette) {
        if visible {
            try g_VSReviewPalette.Show("NA")
        } else {
            try g_VSReviewPalette.Hide()
        }
    }
}

VS_UpdateElementMatch(el, match) {
    el["x"] := Integer(match.x), el["y"] := Integer(match.y)
    el["w"] := Max(8, Integer(match.w)), el["h"] := Max(8, Integer(match.h))
    el["last_seen"] := TrackTS()
    db := TrackDB()
    if db
        db.Run("UPDATE vs_element SET x=?,y=?,w=?,h=?,last_seen=? WHERE id=?"
             , el["x"], el["y"], el["w"], el["h"], el["last_seen"], el["id"])
}

VS_MoveReviewOverlayToElement(el) {
    global g_VSReviewOverlays
    id := Integer(el["id"])
    if !g_VSReviewOverlays.Has(id)
        return
    ov := g_VSReviewOverlays[id]
    try WinMove(Integer(el["x"]), Integer(el["y"]), ov["draw_w"], ov["draw_h"], "ahk_id " . ov["gui"].Hwnd)
}

VS_TestSelected(*) {
    global g_VSReviewSelectedId
    el := VS_ElementById(g_VSReviewSelectedId)
    if !el.Count {
        ShowStatus("Vision Scout: select a candidate first", "info")
        return false
    }
    if el["bin_text"] = "" {
        ShowStatus("Vision Scout: candidate has no FindText pattern", "fail")
        return false
    }

    VS_SaveOverlayPosition(el["id"])
    VS_SetReviewVisualsVisible(false)
    Sleep(100)
    ok := false
    try ok := FindText(&fx, &fy, 0, 0, 0, 0, 0.20, 0.15, "|<VS_Test_" . el["id"] . ">" . el["bin_text"])
    catch as err
        TrackLogError("VS_TestSelected", err)
    VS_SetReviewVisualsVisible(true)

    LearningLab_Record("Vision Scout", el["id"], "Visual candidate #" . el["id"] . " can be recognized", ok && ok.Length ? "pass" : "fail", LearningLab_Context(),
        "Explicit current-screen FindText test. Absence may mean a changed or hidden application state, not a defective pattern.", "vs_element:" . el["id"], "Inspect the candidate in Vision Scout; test in the intended visible state before using its locator.")
    if ok && ok.Length {
        VS_UpdateElementMatch(el, ok[1])
        VS_MoveReviewOverlayToElement(el)
        VS_SelectOverlay(el["id"])
        try CreateOverlay(ok[1].x, ok[1].y, ok[1].w, ok[1].h, "match", 1800, "FOUND #" . el["id"])
        VS_UpdateReviewInfo("PASS: FindText located this candidate on the current screen.")
        ShowStatus("Vision Scout: PASS — found candidate #" . el["id"], "ok")
        return true
    }
    VS_UpdateReviewInfo("FAIL: the saved pattern was not found. Re-open the target state, reposition if needed, then Certify to recapture it.")
    ShowStatus("Vision Scout: FAIL — candidate #" . el["id"] . " was not found", "fail")
    return false
}

VS_CertifySelected(*) {
    global g_VSReviewSelectedId
    el := VS_ElementById(g_VSReviewSelectedId)
    if !el.Count {
        ShowStatus("Vision Scout: select a candidate first", "info")
        return false
    }
    VS_SaveOverlayPosition(el["id"])
    VS_SetReviewVisualsVisible(false)
    Sleep(100)
    pattern := VS_CapturePattern(Integer(el["x"]), Integer(el["y"]), Integer(el["x"]) + Integer(el["w"]), Integer(el["y"]) + Integer(el["h"]))
    ok := false
    if pattern != "" {
        try ok := FindText(&fx, &fy, 0, 0, 0, 0, 0.18, 0.12, "|<VS_Cert_" . el["id"] . ">" . pattern)
        catch as err
            TrackLogError("VS_CertifySelected", err)
    }
    VS_SetReviewVisualsVisible(true)

    if pattern = "" || !ok || !ok.Length {
        VS_UpdateReviewInfo("NOT CERTIFIED: the adjusted region did not produce a pattern FindText could immediately verify.")
        ShowStatus("Vision Scout: could not certify candidate #" . el["id"], "fail")
        return false
    }

    el["bin_text"] := pattern
    el["review_state"] := "certified"
    el["review_note"] := "FindText verified on current screen"
    LearningLab_Record("Vision Scout", el["id"], "Visual candidate #" . el["id"] . " can be recognized", "pass", LearningLab_Context(),
        "User certification plus immediate FindText recognition. Control purpose and action success are separate questions.", "vs_element:" . el["id"], "Certified locator can be exported to Patterns. Recheck in a new state before running an action.")
    el["reviewed_at"] := TrackTS()
    el["promoted"] := 1
    VS_UpdateElementMatch(el, ok[1])
    db := TrackDB()
    if db
        db.Run("UPDATE vs_element SET bin_text=?,review_state=?,review_note=?,reviewed_at=?,promoted=? WHERE id=?"
             , el["bin_text"], el["review_state"], el["review_note"], el["reviewed_at"], el["promoted"], el["id"])
    VS_MoveReviewOverlayToElement(el)
    VS_StyleReviewOverlay(el["id"], true)
    VS_Refresh()
    VS_UpdateReviewInfo("CERTIFIED: current-screen recognition passed. Test again after changing UI state to check robustness.")
    ShowStatus("Vision Scout: certified candidate #" . el["id"], "ok")
    return true
}

VS_SetSelectedReviewState(state, note) {
    global g_VSReviewSelectedId
    el := VS_ElementById(g_VSReviewSelectedId)
    if !el.Count {
        ShowStatus("Vision Scout: select a candidate first", "info")
        return false
    }
    el["review_state"] := state
    el["review_note"] := note
    el["reviewed_at"] := state = "unreviewed" ? "" : TrackTS()
    if state != "certified"
        el["promoted"] := 0
    db := TrackDB()
    if db
        db.Run("UPDATE vs_element SET review_state=?,review_note=?,reviewed_at=?,promoted=? WHERE id=?"
             , el["review_state"], el["review_note"], el["reviewed_at"], el["promoted"], el["id"])
    VS_StyleReviewOverlay(el["id"], true)
    VS_Refresh()
    VS_UpdateReviewInfo(state = "rejected" ? "REJECTED: this candidate will not be exported." : "Reset to UNREVIEWED.")
    return true
}

VS_RejectSelected(*) {
    if VS_SetSelectedReviewState("rejected", "Rejected during visual review")
        ShowStatus("Vision Scout: candidate rejected", "info")
}

VS_ResetSelected(*) {
    if VS_SetSelectedReviewState("unreviewed", "")
        ShowStatus("Vision Scout: candidate reset to unreviewed", "info")
}

VS_EndReview(restoreMain := true) {
    global g_VSReviewPalette, g_VSRestoreMainGui, MainGui, g_GuiVisible
    VS_DestroyReviewOverlays()
    if IsObject(g_VSReviewPalette)
        try g_VSReviewPalette.Hide()
    if restoreMain && g_VSRestoreMainGui {
        try MainGui.Show()
        g_GuiVisible := true
    }
    g_VSRestoreMainGui := false
}

VS_ShowGuide(*) {
    text := "WHAT THE SCAN DOES`n"
    text .= "It samples screen contrast, joins neighboring edge cells into boxes, and saves each box as a FindText pattern. It does not know what a box means until you vet it.`n`n"
    text .= "REVIEW COLORS`nAmber = unreviewed   Blue = selected   Green = certified   Red = rejected`n`n"
    text .= "VETTING WORKFLOW`n1. Scan Window; during the 3-second countdown focus the target app.`n"
    text .= "2. Click a numbered box. Drag it if its position is wrong.`n"
    text .= "3. Test Find. A PASS means the saved pattern can be located now.`n"
    text .= "4. Certify recaptures the adjusted box and requires an immediate FindText match.`n"
    text .= "5. Change the target (hover, scroll, reopen it) and Test again. Repeated passes are the practical stability check.`n"
    text .= "6. Export sends certified items to the Patterns tab as VS_el<ID>.`n`n"
    text .= "USAGE EXAMPLES`nIn Workflow choose Find & Click and select VS_el<ID> as the target. Or use Wait for Pattern / Wait Until Gone. In Spools, choose Pattern Match to trigger an action when it appears.`n`n"
    text .= "Certification proves current-screen recognition; it cannot guarantee a future app theme, zoom, DPI, or layout will be identical."
    MsgBoxTop(text, "Vision Scout — scan, vet, use")
}

; ═══════════════════════════════════════════════════════════════════════════════
; UI TAB
; ═══════════════════════════════════════════════════════════════════════════════

VisionScout_BuildTab(g) {
    global g_VSStatusText, g_VSElemLV, g_VSSeqLV, g_VSCbOn, g_VSOn

    g.Add("GroupBox", "x15 y50 w860 h110", "Vision Scout — scan → visually review → certify → export")
    g.Add("Button", "x25 y72 w100 h34", g_VSOn ? "Stop Scout" : "Start Scout").OnEvent("Click", VS_OnStartBtn)
    g_VSCbOn := g.Add("CheckBox", "x135 y79 w165", "Scout + Learn ON")
    g_VSCbOn.OnEvent("Click", VS_OnToggle)
    g.Add("Button", "x310 y70 w130 h28 cBlue", "🔎 Scan Window").OnEvent("Click", VS_BeginReviewScan.Bind("window"))
    g.Add("Button", "x445 y70 w130 h28", "▣ Scan Full Screen").OnEvent("Click", VS_BeginReviewScan.Bind("screen"))
    g.Add("Button", "x580 y70 w95 h28", "? Guide").OnEvent("Click", VS_ShowGuide)
    g.Add("Button", "x780 y70 w85 h28 cRed", "Clear Data").OnEvent("Click", VS_OnClear)
    g.Add("Button", "x310 y110 w130 h26 cBlue", "Review Selected").OnEvent("Click", VS_ReviewSelected)
    g.Add("Button", "x445 y110 w130 h26", "Show Last Scan").OnEvent("Click", VS_ShowLastScan)
    g.Add("Button", "x580 y110 w95 h26", "Mine Seqs").OnEvent("Click", VS_OnMine)
    g.Add("Button", "x680 y110 w95 h26", "Promote Use").OnEvent("Click", VS_OnPromote)
    g.Add("Button", "x780 y110 w85 h26 cGreen", "Export ✓").OnEvent("Click", (*) => VS_ExportPromoted())

    g.Add("Text", "x25 y166 w840 cGray", "Scanning finds visual candidates; only GREEN certified candidates can be exported. Double-click a row to review one. Win+CapsLock accepts a learned sequence offer.")

    g.Add("GroupBox", "x15 y184 w860 h280", "Discovered Elements — review status is separate from usage frequency")
    g_VSElemLV := g.Add("ListView", "x25 y206 w840 h220 Grid -Multi", ["#", "Review", "Tier", "Score", "Access", "Clicks", "W", "H", "Window"])
    g_VSElemLV.OnEvent("ItemSelect", VS_OnElementSelect)
    g_VSElemLV.OnEvent("DoubleClick", VS_ReviewSelected)
    g.Add("Text", "x25 y436 w180 cC08A00", "AMBER  unreviewed")
    g.Add("Text", "x210 y436 w150 c039BE5", "BLUE  selected")
    g.Add("Text", "x365 y436 w160 c2E8B3C", "GREEN  certified")
    g.Add("Text", "x530 y436 w150 cD32F2F", "RED  rejected")

    g.Add("GroupBox", "x15 y474 w860 h180", "Learned Sequences (repeat these 3+ times to learn)")
    g_VSSeqLV := g.Add("ListView", "x25 y494 w840 h150 Grid -Multi", ["Count", "Len", "Sequence", "Window"])

    g_VSStatusText := g.Add("Edit", "x15 y660 w860 h60 ReadOnly -Wrap +VScroll")
    g_VSStatusText.SetFont("s8", "Consolas")

    g_VSCbOn.Value := g_VSOn
    VS_Refresh()
    SetTimer(VS_RefreshStatusTimer, 1000)
}

VS_OnElementSelect(lv, row, selected) {
    global g_VSReviewSelectedId, g_VSReviewOverlays
    if !selected || !row
        return
    id := Integer(lv.GetText(row, 1))
    g_VSReviewSelectedId := id
    if g_VSReviewOverlays.Has(id)
        VS_SelectOverlay(id, false)
}

VS_OnStartBtn(*) {
    global g_VSOn
    if g_VSOn
        VS_Stop()
    else
        VS_Start()
}

VS_OnToggle(ctrl, *) {
    if ctrl.Value
        VS_Start()
    else
        VS_Stop()
}

VS_OnMine(*) {
    n := VS_MineSequences()
    ShowStatus("Vision Scout: mined " . n . " sequence(s)", "ok")
    VS_Refresh()
}

VS_OnPromote(*) {
    n := VS_ApplyPromotion()
    ShowStatus("Vision Scout: promoted " . n . " element(s)", "ok")
}

VS_OnClear(*) {
    global g_VSElements, g_VSSequences, g_VSSteps, g_VSRecent
    result := MsgBoxTop("Clear Vision Scout data?`n`nThis removes discovered elements and the learned usage history, but keeps your normal workflows.", "Vision Scout", "YesNo")
    if result != "Yes"
        return
    VS_EndReview(false)
    db := TrackDB()
    if db {
        db.Begin()
        try {
            db.Run("DELETE FROM vs_action")
            db.Run("DELETE FROM vs_element")
            db.Run("DELETE FROM vs_sequence")
        } catch as err {
            db.Rollback()
            TrackLogError("VS_OnClear", err)
            return
        }
        db.Commit()
    }
    g_VSElements := []
    g_VSSequences := []
    g_VSSteps := []
    g_VSRecent := []
    VS_DisarmOffer()
    VS_Refresh()
    ShowStatus("Vision Scout: data cleared", "ok")
}

VS_Refresh() {
    global g_VSElemLV, g_VSSeqLV, g_VSElements, g_VSSequences, g_VSReviewSelectedId
    if IsObject(g_VSElemLV) {
        g_VSElemLV.Delete()
        selectedRow := 0
        for el in g_VSElements {
            winName := ""
            if Integer(el["win_id"]) {
                wr := TrackDB_WinRow(Integer(el["win_id"]))
                if wr.Count
                    winName := wr["name"]
            }
            tierName := ["cold", "seen", "freq", "HOT"][Integer(el["tier"]) + 1]
            reviewState := VS_ElementReviewState(el)
            reviewName := reviewState = "certified" ? "CERTIFIED" : reviewState = "rejected" ? "rejected" : "unreviewed"
            row := g_VSElemLV.Add(, el["id"], reviewName, tierName, Round(Float(el["score"]), 1), el["accesses"], el["clicks"], el["w"], el["h"], TrackEllipsis(winName, 24))
            if Integer(el["id"]) = g_VSReviewSelectedId
                selectedRow := row
        }
        if selectedRow
            g_VSElemLV.Modify(selectedRow, "Select Focus Vis")
    }
    if IsObject(g_VSSeqLV) {
        g_VSSeqLV.Delete()
        for seq in g_VSSequences {
            g_VSSeqLV.Add(, seq["count"], seq["length"], VS_SeqName(seq["stepsArr"]), TrackEllipsis(VS_SeqWindow(seq["stepsArr"]), 30))
        }
    }
}

; Best-effort window label for a sequence: the "win:" step if one is present.
VS_SeqWindow(steps) {
    for t in steps {
        if InStr(t, "win:") = 1
            return SubStr(t, 5)
    }
    return ""
}

VS_RefreshStatusTimer() {
    global g_VSStatusText, g_VSOn, g_VSElements, g_VSSequences, g_VSSteps, g_VSRecent, g_VSPending
    if !IsObject(g_VSStatusText)
        return
    line1 := "Scout+Learn: " . (g_VSOn ? "ON" : "OFF")
    certified := 0, rejected := 0
    for el in g_VSElements {
        state := VS_ElementReviewState(el)
        certified += state = "certified" ? 1 : 0
        rejected += state = "rejected" ? 1 : 0
    }
    line2 := "Elements: " . g_VSElements.Length . " (" . certified . " certified, " . rejected . " rejected)   |   Learned sequences: " . g_VSSequences.Length
    line3 := "Recent steps: " . g_VSSteps.Length . "   |   Recent events: " . g_VSRecent.Length
    line4 := ""
    if g_VSPending.Count
        line4 := "OFFER READY: press Win+CapsLock to run '" . g_VSPending["name"] . "'"
    g_VSStatusText.Value := line1 . "`r`n" . line2 . "`r`n" . line3 . (line4 != "" ? "`r`n" . line4 : "")
}
