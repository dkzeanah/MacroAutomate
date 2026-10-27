; ═══════════════════════════════════════════════════════════════════════════════
; ExplorerAgent.ahk - Safe, OCR-driven, non-destructive window exploration
; ═══════════════════════════════════════════════════════════════════════════════
; WHAT THIS DOES, IN PLAIN ENGLISH
; --------------------------------
; This is the "passive / non-destructive learning" mode from the brief. Point it
; at a window and it will:
;
;   1. LOOK at the window the way a person does - it OCRs the window's rectangle
;      (via the Descolada OCR library already in lib\OCR.ahk) and gets back every
;      recognised word together with that word's position on screen.
;   2. UNDERSTAND each control by running its label through ElementSafety.ahk, so
;      every word is tagged passive / input / volatile / unknown.
;   3. CATALOG all of it - text, screen position, and safety class - and remember
;      it in SQLite so the knowledge of this window accumulates over time.
;
; That is the whole DEFAULT behaviour, and it touches nothing: no clicks, no
; typing. It only reads the screen. It is safe to run on a logged-in Facebook tab
; because it will never press "Post" - it just records that a volatile "Post"
; control exists at some coordinates.
;
; Two capabilities are OPT-IN, because they interact with the UI:
;
;   * HOVER  - move the mouse over cataloged controls (still non-destructive;
;              surfaces tooltips/hover states). Enable with opts["hover"] := true.
;   * PROBE  - actually click a control to deduce what it does, then watch whether
;              the window changed. This is strictly gated: it clicks ONLY controls
;              classified "passive" (reversible), caps how many it will try, and
;              presses Escape afterwards to collapse any menu it opened. Enable
;              with opts["click"] := true. Volatile / input / unknown controls are
;              NEVER clicked, no matter what.
;
; THE LEARNING (the "deduction over time")
; ----------------------------------------
; Every probe is written to an explore_probe table with whether the click changed
; the window. A passive control that reliably changes the UI is "informative" -
; worth clicking to reveal more - while one that changes nothing is a dead end.
; Explore_Informative() reads that accumulated evidence back out: the engine's own
; cheat-sheet of which controls in a window are worth exploring.
; ═══════════════════════════════════════════════════════════════════════════════

; ═══════════════════════════════════════════════════════════════════════════════
; PUBLIC ENTRY POINT
; ═══════════════════════════════════════════════════════════════════════════════

; Explore one window and return a catalog of what was found.
;
;   winTitle : any AHK WinTitle. "A" (default) = the currently active window.
;   opts     : an optional Map of settings (all have safe defaults):
;                "hover"     false - move the mouse over each control (safe)
;                "click"     false - probe PASSIVE controls by clicking them
;                "maxProbes" 12    - most passive controls to click in one run
;                "dwell"     350   - ms to pause after a hover/click
;                "restore"   true  - press Escape after a probing click
;                "highlight" false - briefly box each control, coloured by class
;                "lang"      ""    - OCR language (blank = Windows default)
;                "store"     true  - write the catalog/probes to the tracking DB
;
; Returns an Array of Maps, one per recognised control:
;   Map("text", "line", "class", "reason", "x","y","w","h", "cx","cy",
;       "probed"(bool), "changed"(bool))
; (x,y,w,h and cx,cy are SCREEN coordinates.)
Explore_Window(winTitle := "A", opts := "") {
    if !(opts is Map)
        opts := Map()

    ; ─── Resolve and focus the target window ─────────────────────────────────
    hwnd := WinExist(winTitle)
    if !hwnd {
        ShowStatus("Explore: no window matches '" . winTitle . "'", "fail")
        return []
    }
    ; Bring it to the front so what we OCR is actually what the user sees.
    try {
        WinActivate("ahk_id " . hwnd)
        WinWaitActive("ahk_id " . hwnd, , 1)
    }

    ; ─── Learn its identity + screen rectangle ───────────────────────────────
    title := "", exe := ""
    try title := WinGetTitle("ahk_id " . hwnd)
    try exe   := WinGetProcessName("ahk_id " . hwnd)
    winName := TrackNormalizeWindowName(title, exe)
    try {
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . hwnd)
    } catch as err {
        TrackLogError("Explore_Window(pos)", err)
        return []
    }
    if (ww <= 0 || wh <= 0) {
        ShowStatus("Explore: window has no visible area", "fail")
        return []
    }

    ; ─── LOOK: OCR the whole window rectangle ────────────────────────────────
    ; OCR.FromRect captures from the screen, so the words come back with
    ; SCREEN-relative coordinates - no conversion needed to click them later.
    lang := opts.Has("lang") ? opts["lang"] : ""
    res := Explore_OcrRect(wx, wy, ww, wh, lang)
    if (res = "") {
        ShowStatus("Explore: OCR unavailable or returned nothing", "fail")
        return []
    }

    ; ─── UNDERSTAND + CATALOG every word, with its line as context ───────────
    catalog := []
    for line in res.Lines {
        lineText := line.Text
        for word in line.Words {
            text := Trim(word.Text)
            if (text = "")
                continue
            ; Classify using the word as the name and the whole line as the
            ; description, so a multi-word phrase like "Log out" is still caught.
            verdict := Safety_ClassifyName(text, "", lineText)
            bx := word.x, by := word.y, bw := word.w, bh := word.h
            catalog.Push(Map(
                "text",   text,
                "line",   lineText,
                "class",  verdict["class"],
                "reason", verdict["reason"],
                "x", bx, "y", by, "w", bw, "h", bh,
                "cx", bx + bw // 2, "cy", by + bh // 2,      ; centre, for clicking
                "probed", false, "changed", false))

            ; Optional visual map: box the control in a class colour.
            if (opts.Has("highlight") && opts["highlight"]) {
                try word.Highlight(-1200, Explore_ClassColor(verdict["class"]), 2)
            }
        }
    }

    ShowStatus("Explore: cataloged " . catalog.Length . " controls in '" . winName . "'", "ok")

    ; ─── Optional HOVER (non-destructive) ────────────────────────────────────
    if (opts.Has("hover") && opts["hover"])
        Explore_HoverAll(catalog, opts.Has("dwell") ? opts["dwell"] : 350)

    ; ─── Optional PROBE (passive-only clicking, strictly gated) ──────────────
    if (opts.Has("click") && opts["click"])
        Explore_ProbePassive(catalog, winName, wx, wy, ww, wh, opts)

    ; ─── Remember what we found ──────────────────────────────────────────────
    if (!opts.Has("store") || opts["store"])
        Explore_Store(winName, catalog)

    return catalog
}

; Convenience: catalog only, guaranteed to touch nothing (hover/click forced off).
Explore_Catalog(winTitle := "A") {
    return Explore_Window(winTitle, Map("hover", false, "click", false))
}

; ═══════════════════════════════════════════════════════════════════════════════
; HOVER - move the mouse over each cataloged control (safe for every class)
; ═══════════════════════════════════════════════════════════════════════════════
; Hovering cannot fire a button, so it is safe to do over anything. It is useful
; because many UIs only reveal tooltips/affordances on hover.
Explore_HoverAll(catalog, dwell := 350) {
    for item in catalog {
        try {
            MouseMove(item["cx"], item["cy"], 2)
            Sleep(dwell)
        } catch as err {
            TrackLogError("Explore_HoverAll", err)
        }
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; PROBE - click PASSIVE controls only, and measure whether the window changed
; ═══════════════════════════════════════════════════════════════════════════════
; This is the one place the explorer clicks. The gate is absolute: a control is
; clicked only if its safety class is exactly "passive". Volatile (Post/Send/...),
; input fields, and anything unclassified are skipped. maxProbes bounds how many
; clicks happen; restore presses Escape afterwards to undo transient menus.
Explore_ProbePassive(catalog, winName, wx, wy, ww, wh, opts) {
    maxProbes := opts.Has("maxProbes") ? opts["maxProbes"] : 12
    dwell     := opts.Has("dwell")     ? opts["dwell"]     : 350
    restore   := !opts.Has("restore") || opts["restore"]
    done      := 0

    for item in catalog {
        if (done >= maxProbes)
            break
        if (item["class"] != "passive")       ; the hard safety gate
            continue

        ; Snapshot the window's text BEFORE the click.
        before := Explore_WindowText(wx, wy, ww, wh, opts.Has("lang") ? opts["lang"] : "")

        ; The one click. It is a reversible/passive control by classification.
        try {
            Click(item["cx"], item["cy"], "Left", 1)
            Sleep(dwell)
        } catch as err {
            TrackLogError("Explore_ProbePassive(click)", err)
            continue
        }

        ; Snapshot AFTER, and deduce whether anything changed.
        after := Explore_WindowText(wx, wy, ww, wh, opts.Has("lang") ? opts["lang"] : "")
        item["probed"]  := true
        item["changed"] := (after != before)

        ShowStatus("Probed passive '" . item["text"] . "' -> "
                 . (item["changed"] ? "UI changed" : "no change"), "info")

        ; Best-effort restore: collapse any menu/popup the click opened so we
        ; leave the window as we found it. (Not guaranteed for every app.)
        if (restore) {
            try Send("{Escape}")
            Sleep(120)
        }

        done++
    }
    if (done)
        ShowStatus("Explore: probed " . done . " passive control(s)", "ok")
}

; ═══════════════════════════════════════════════════════════════════════════════
; OCR HELPERS
; ═══════════════════════════════════════════════════════════════════════════════

; OCR a screen rectangle and return the Result object (or "" on failure).
Explore_OcrRect(x, y, w, h, lang := "") {
    try {
        ; The OCR library's 5th argument is an Options object; it reads a
        ; "lang"/"language" key from it. Pass one only when a language was given.
        if (lang != "")
            return OCR.FromRect(x, y, w, h, {lang: lang})
        return OCR.FromRect(x, y, w, h)
    } catch as err {
        TrackLogError("Explore_OcrRect", err)
        return ""
    }
}

; OCR a rectangle and return just its concatenated text (for change detection).
Explore_WindowText(x, y, w, h, lang := "") {
    res := Explore_OcrRect(x, y, w, h, lang)
    if (res = "")
        return ""
    txt := ""
    try txt := res.Text
    return txt
}

; A highlight colour per safety class, for the optional visual map.
Explore_ClassColor(cls) {
    switch cls {
        case "passive":  return "Lime"
        case "input":    return "Aqua"
        case "volatile": return "Red"
        default:         return "Gray"       ; unknown
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; PERSISTENCE + ACCUMULATED KNOWLEDGE
; ═══════════════════════════════════════════════════════════════════════════════

; Lazily create the explore_probe table (self-contained, like TieredAutomation's).
Explore_EnsureTable() {
    static made := false
    if made
        return true
    db := TrackDB()
    if !db
        return false
    try {
        db.Exec(
            "CREATE TABLE IF NOT EXISTS explore_probe ("
          . "  id      INTEGER PRIMARY KEY AUTOINCREMENT,"
          . "  win     TEXT NOT NULL,"
          . "  text    TEXT NOT NULL,"
          . "  class   TEXT NOT NULL,"
          . "  line    TEXT,"
          . "  x INTEGER, y INTEGER, w INTEGER, h INTEGER,"
          . "  probed  INTEGER NOT NULL DEFAULT 0,"
          . "  changed INTEGER NOT NULL DEFAULT 0,"
          . "  ts      TEXT)")
        made := true
    } catch as err {
        TrackLogError("Explore_EnsureTable", err)
        return false
    }
    return true
}

; Write a catalog to the tracking DB. Each row records what was seen and - if it
; was probed - whether clicking it changed the window.
Explore_Store(winName, catalog) {
    db := TrackDB()
    if (!db || !Explore_EnsureTable())
        return 0
    ts := TrackTS()
    n := 0
    for item in catalog {
        try {
            db.Run(
                "INSERT INTO explore_probe(win,text,class,line,x,y,w,h,probed,changed,ts) "
              . "VALUES(?,?,?,?,?,?,?,?,?,?,?)"
              , winName, item["text"], item["class"], item["line"]
              , item["x"], item["y"], item["w"], item["h"]
              , item["probed"] ? 1 : 0, item["changed"] ? 1 : 0, ts)
            n++
        } catch as err {
            TrackLogError("Explore_Store", err)
        }
    }
    return n
}

; The engine's learned cheat-sheet for a window: passive controls that, when
; clicked, have actually changed the UI before (i.e. worth exploring). Ordered by
; how often they proved informative.
Explore_Informative(winName, limit := 50) {
    db := TrackDB()
    if (!db || !Explore_EnsureTable())
        return []
    try {
        return db.Query(
            "SELECT text, line, COUNT(*) AS seen, "
          . "       SUM(changed) AS informative, MAX(ts) AS last_ts "
          . "FROM explore_probe "
          . "WHERE win=? AND class='passive' AND probed=1 "
          . "GROUP BY text "
          . "HAVING informative > 0 "
          . "ORDER BY informative DESC, seen DESC LIMIT ?"
          , winName, limit)
    } catch as err {
        TrackLogError("Explore_Informative", err)
        return []
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; REPORTING
; ═══════════════════════════════════════════════════════════════════════════════

; A readable summary of a catalog, grouped by safety class. Good for a tooltip,
; the dashboard, or a quick "what did it find" log.
Explore_Report(catalog) {
    buckets := Map("passive", [], "input", [], "volatile", [], "unknown", [])
    for item in catalog {
        cls := item["class"]
        if !buckets.Has(cls)
            buckets[cls] := []
        buckets[cls].Push(item["text"])
    }
    out := "Explored " . catalog.Length . " control(s):`n"
    for cls in ["passive", "input", "volatile", "unknown"] {
        names := buckets.Has(cls) ? buckets[cls] : []
        out .= Format("  {:-9} {:3}  ", cls, names.Length)
        out .= Explore_JoinUnique(names, ", ", 12) . "`n"
    }
    out .= "`n(passive = safe to explore; volatile/input/unknown are never auto-clicked)"
    return out
}

; Join up to `maxItems` unique strings with a separator, appending "..." if there
; were more. Keeps the report compact for toolbars with many repeated labels.
Explore_JoinUnique(arr, sep := ", ", maxItems := 12) {
    seen := Map(), picked := []
    for s in arr {
        if (s = "" || seen.Has(s))
            continue
        seen[s] := true
        picked.Push(s)
        if (picked.Length >= maxItems)
            break
    }
    out := ""
    for i, s in picked
        out .= (i > 1 ? sep : "") . s
    if (seen.Count > picked.Length)
        out .= sep . "..."
    return out
}
