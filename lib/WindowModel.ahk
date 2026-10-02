; ═══════════════════════════════════════════════════════════════════════════════
; WindowModel.ahk - The semantic layout of a window, not just its elements
; ═══════════════════════════════════════════════════════════════════════════════
; App Learner records what a window contains: thousands of clickable things with
; coordinates. It does not record what the window IS - that a strip down the left
; is a sidebar, that the big area in the middle is where the work happens, that
; the thin band at the bottom is a status bar.
;
; This module derives that structure from the recorded geometry:
;
;   1. SEGMENT   elements are projected onto each axis and split along the wide
;                empty bands between them (the classic XY-cut used in document
;                layout analysis). A real gutter between two panes shows up as a
;                column of screen that no element occupies.
;   2. CLASSIFY  each region is scored against positional, dimensional and
;                textual evidence to give it a role - editor, sidebar, status
;                bar, tab strip, gutter, toolbar.
;   3. STORE     regions are written per app, so automation can later say
;                "the editor" rather than a pixel coordinate.
;
; Everything is normalised 0-1 against the window, so the model survives the
; window being resized or moved to another monitor.
;
; Honest limits: the model can only see what was recorded. For a Win32 app with
; a real accessibility tree the regions are structural. For an Electron app like
; VS Code, most of what was captured is OCR of content, so the regions are
; inferred from where text sits - reliable for the big divisions, weaker for
; nested detail.
; ═══════════════════════════════════════════════════════════════════════════════

global g_WinModelReady := false

WinModel_Schema() {
    global g_WinModelReady
    if g_WinModelReady
        return true
    db := AppMapDB()
    if !db
        return false
    try {
        db.Exec("CREATE TABLE IF NOT EXISTS ui_region ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT,"
              . "app_id INTEGER NOT NULL,"
              . "parent_id INTEGER DEFAULT 0,"
              . "depth INTEGER DEFAULT 0,"
              . "role TEXT, name TEXT,"
              . "rel_x REAL, rel_y REAL, rel_w REAL, rel_h REAL,"
              . "elements INTEGER DEFAULT 0,"
              . "confidence REAL DEFAULT 0,"
              . "evidence TEXT,"
              . "built_ts TEXT)")
        db.Exec("CREATE INDEX IF NOT EXISTS ix_region_app ON ui_region(app_id)")
    } catch as err {
        AppMap_LogError("WinModel_Schema", err)
        return false
    }
    g_WinModelReady := true
    return true
}

; ═══════════════════════════════════════════════════════════════════════════════
; SEGMENTATION
; ═══════════════════════════════════════════════════════════════════════════════

; Build (or rebuild) the layout model for one learned app.
; Returns Map(regions, leaves) or an empty Map on failure.
WinModel_Build(appId) {
    if !WinModel_Schema()
        return Map()
    db := AppMapDB()
    ; Container-sized elements span everything and would hide every gap, so the
    ; segmentation runs on leaf-sized elements only.
    ; Normalised coordinates are computed against the window as it was at
    ; capture time. An element recorded while it sat outside that rectangle -
    ; a popup, or a window that moved mid-scan - lands far outside 0..1 and
    ; would stretch every region it falls into. Keep only plausible geometry.
    els := db.Query("SELECT id,kind,name,role,rel_x,rel_y,rel_w,rel_h FROM ui_element "
                  . "WHERE app_id=? AND rel_w>0 AND rel_h>0 AND (rel_w*rel_h)<=0.5 "
                  . "AND rel_x BETWEEN -0.02 AND 1.02 AND rel_y BETWEEN -0.02 AND 1.02 "
                  . "AND rel_w<=1.02 AND rel_h<=1.02", appId)
    if (els.Length < 6)
        return Map()

    db.Run("DELETE FROM ui_region WHERE app_id=?", appId)
    boxes := []
    for e in els {
        boxes.Push(Map("x", e["rel_x"], "y", e["rel_y"]
                     , "w", e["rel_w"], "h", e["rel_h"]
                     , "name", e["name"], "kind", e["kind"], "role", e["role"]))
    }
    regions := []
    WinModel_Split(boxes, Map("x", 0.0, "y", 0.0, "w", 1.0, "h", 1.0), 0, regions)

    now := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    for , r in regions {
        cls := WinModel_Classify(r)
        db.Run("INSERT INTO ui_region(app_id,parent_id,depth,role,name,"
             . "rel_x,rel_y,rel_w,rel_h,elements,confidence,evidence,built_ts) "
             . "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)"
             , appId, 0, r["depth"], cls["role"], cls["name"]
             , r["bounds"]["x"], r["bounds"]["y"], r["bounds"]["w"], r["bounds"]["h"]
             , r["boxes"].Length, cls["confidence"], cls["evidence"], now)
    }
    return Map("regions", regions.Length, "leaves", els.Length)
}

; Recursive XY-cut: split along the widest empty band, vertical or horizontal.
WinModel_Split(boxes, bounds, depth, regions, maxDepth := 4) {
    if (depth >= maxDepth || boxes.Length < 8) {
        regions.Push(Map("bounds", bounds, "boxes", boxes, "depth", depth))
        return
    }
    vGap := WinModel_BestGap(boxes, bounds, true)
    hGap := WinModel_BestGap(boxes, bounds, false)

    use := ""
    if (vGap.Count && hGap.Count)
        use := (vGap["size"] >= hGap["size"]) ? vGap : hGap
    else if vGap.Count
        use := vGap
    else if hGap.Count
        use := hGap

    if !IsObject(use) {
        regions.Push(Map("bounds", bounds, "boxes", boxes, "depth", depth))
        return
    }

    aBoxes := [], bBoxes := []
    cut := use["at"]
    vertical := use["vertical"]
    for , b in boxes {
        mid := vertical ? (b["x"] + b["w"] / 2) : (b["y"] + b["h"] / 2)
        (mid < cut ? aBoxes : bBoxes).Push(b)
    }
    if (!aBoxes.Length || !bBoxes.Length) {
        regions.Push(Map("bounds", bounds, "boxes", boxes, "depth", depth))
        return
    }
    aB := WinModel_Bounds(aBoxes), bB := WinModel_Bounds(bBoxes)
    WinModel_Split(aBoxes, aB, depth + 1, regions, maxDepth)
    WinModel_Split(bBoxes, bB, depth + 1, regions, maxDepth)
}

; The deepest low-density valley across `bounds`.
;
; Requiring a completely empty band only works on tidy Win32 layouts. Most of
; what gets recorded is OCR of content, where a stray word box bridges the
; gutter between two panes and hides it. So this builds a density profile and
; looks for the deepest valley instead - the place where the window is emptiest,
; not necessarily empty. That is what a real pane divider looks like in the
; data.
WinModel_BestGap(boxes, bounds, vertical, minSide := 4) {
    if (boxes.Length < minSide * 2)
        return Map()
    slots := 120
    lo := vertical ? bounds["x"] : bounds["y"]
    span := vertical ? bounds["w"] : bounds["h"]
    if (span <= 0.02)
        return Map()

    dens := []
    Loop slots
        dens.Push(0)
    for , b in boxes {
        s0 := vertical ? b["x"] : b["y"]
        e0 := s0 + (vertical ? b["w"] : b["h"])
        i0 := Max(1, Integer(Floor((s0 - lo) / span * slots)) + 1)
        i1 := Min(slots, Integer(Ceil((e0 - lo) / span * slots)))
        Loop Max(0, i1 - i0 + 1)
            dens[i0 + A_Index - 1] += 1
    }
    ; Smooth so a single-slot hole is not mistaken for a divider.
    sm := []
    Loop slots {
        i := A_Index
        a := (i > 1) ? dens[i - 1] : dens[i]
        c := (i < slots) ? dens[i + 1] : dens[i]
        sm.Push((a + dens[i] + c) / 3)
    }
    total := 0
    for , v in sm
        total += v
    mean := total / slots
    if (mean <= 0)
        return Map()
    threshold := mean * 0.30

    ; Ignore the outer 8% so a page margin is never read as a divider.
    edge := Integer(slots * 0.08)
    best := Map(), run := 0, runSum := 0
    Loop slots + 1 {
        i := A_Index
        low := (i <= slots) && (sm[i] <= threshold) && (i > edge) && (i <= slots - edge)
        if low {
            run++
            runSum += sm[i]
            continue
        }
        if (run >= 2) {
            startSlot := i - run
            at := lo + ((startSlot - 1 + run / 2) / slots * span)
            depth := mean - (runSum / run)
            score := run * depth
            a := 0, b2 := 0
            for , bx in boxes {
                mid := vertical ? (bx["x"] + bx["w"] / 2) : (bx["y"] + bx["h"] / 2)
                (mid < at) ? a++ : b2++
            }
            if (a >= minSide && b2 >= minSide && (!best.Count || score > best["size"]))
                best := Map("at", at, "size", score, "vertical", vertical)
        }
        run := 0, runSum := 0
    }
    return best
}

WinModel_Bounds(boxes) {
    x1 := 1.0, y1 := 1.0, x2 := 0.0, y2 := 0.0
    for , b in boxes {
        x1 := Min(x1, b["x"]), y1 := Min(y1, b["y"])
        x2 := Max(x2, b["x"] + b["w"]), y2 := Max(y2, b["y"] + b["h"])
    }
    return Map("x", x1, "y", y1, "w", Max(x2 - x1, 0.001), "h", Max(y2 - y1, 0.001))
}

; ═══════════════════════════════════════════════════════════════════════════════
; CLASSIFICATION
; ═══════════════════════════════════════════════════════════════════════════════
; Every region is scored against the evidence available. No single signal is
; trusted alone: a narrow left strip could be a sidebar or an editor gutter, and
; only its contents separate the two.

WinModel_Classify(region) {
    b := region["bounds"]
    boxes := region["boxes"]
    x := b["x"], y := b["y"], w := b["w"], h := b["h"]
    n := boxes.Length

    ; ── content evidence ─────────────────────────────────────────────────────
    numeric := 0, named := 0, menuish := 0, words := 0
    keywords := Map()
    for , bx in boxes {
        nm := Trim(bx["name"])
        if (nm != "") {
            named++
            if RegExMatch(nm, "^\d{1,5}$")
                numeric++
            wcount := StrSplit(RegExReplace(nm, "\s+", " "), " ").Length
            words += wcount
        }
        if InStr(bx["kind"], "menu")
            menuish++
        for , k in ["terminal", "output", "problems", "explorer", "search", "console"
                  , "debug", "timeline", "outline", "properties", "toolbox", "playlist"] {
            if InStr(StrLower(nm), k)
                keywords[k] := (keywords.Has(k) ? keywords[k] : 0) + 1
        }
    }
    numericShare := named ? (numeric / named) : 0
    avgWords := named ? (words / named) : 0

    role := "region", conf := 0.35, why := []

    ; ── shape and position evidence ──────────────────────────────────────────
    isTopStrip := (y < 0.10 && h < 0.14)
    isBottomStrip := (y + h > 0.86 && h < 0.12)
    isLeftCol := (x < 0.06 && w < 0.30 && h > 0.35)
    isRightCol := (x + w > 0.94 && w < 0.30 && h > 0.35)
    isThinTall := (w < 0.035 && h > 0.30)
    isBig := (w > 0.35 && h > 0.35)

    if isThinTall {
        role := "scrollbar", conf := 0.55
        why.Push("thin vertical band " . Round(w * 100) . "% wide")
    } else if (numericShare > 0.6 && w < 0.12 && h > 0.3) {
        ; A narrow column of bare integers is a line-number gutter, which also
        ; means the pane beside it holds the document.
        role := "editor gutter", conf := 0.8
        why.Push(Round(numericShare * 100) . "% of its labels are bare numbers")
    } else if isBottomStrip {
        role := "status bar", conf := 0.7
        why.Push("thin band across the bottom")
    } else if (isTopStrip && menuish > n * 0.4) {
        role := "menu bar", conf := 0.75
        why.Push(menuish . " menu items in a strip along the top")
    } else if isTopStrip {
        role := (avgWords <= 4) ? "tab strip" : "title bar"
        conf := 0.55
        why.Push("thin band across the top, labels average "
               . Round(avgWords, 1) . " words")
    } else if (isLeftCol || isRightCol) {
        role := (isLeftCol ? "left sidebar" : "right sidebar")
        conf := 0.65
        why.Push("tall column against the " . (isLeftCol ? "left" : "right") . " edge")
    } else if isBig {
        role := "main work area", conf := 0.6
        why.Push("largest interior area, " . Round(w * 100) . "% x " . Round(h * 100) . "%")
    }

    ; ── a keyword may name the region, but only when it is really a label ────
    ; A word like "output" occurring in OCR'd document text says nothing about
    ; the region's purpose. It only counts when the region is a distinct pane
    ; (not the whole window) and the word is a meaningful share of its labels.
    bestKey := "", bestN := 0
    for k, c in keywords {
        if (c > bestN)
            bestKey := k, bestN := c
    }
    isWholeWindow := (w > 0.9 && h > 0.9)
    keyShare := named ? (bestN / named) : 0
    if (bestKey != "" && bestN >= 3 && keyShare >= 0.12 && !isWholeWindow) {
        role := bestKey . " pane"
        conf := Min(0.9, conf + 0.2)
        why.Push("'" . bestKey . "' appears in " . Round(keyShare * 100)
               . "% of this region's labels")
    }
    if isWholeWindow {
        ; Nothing was divided out, so say so rather than inventing a structure.
        role := "whole window (no divisions found)"
        conf := 0.3
        why.Push("no low-density divider was found; the capture may be mostly "
               . "content text rather than UI structure")
    }

    why.Push(n . " elements")
    ev := ""
    for , s in why
        ev .= (ev = "" ? "" : "; ") . s
    return Map("role", role, "name", WinModel_RegionName(role, b)
             , "confidence", Round(conf, 2), "evidence", ev)
}

WinModel_RegionName(role, b) {
    return role . " @ " . Round(b["x"] * 100) . "," . Round(b["y"] * 100)
         . " " . Round(b["w"] * 100) . "x" . Round(b["h"] * 100)
}

; ═══════════════════════════════════════════════════════════════════════════════
; READING THE MODEL
; ═══════════════════════════════════════════════════════════════════════════════

WinModel_Regions(appId) {
    if !WinModel_Schema()
        return []
    return AppMapDB().Query("SELECT * FROM ui_region WHERE app_id=? "
                          . "ORDER BY (rel_w*rel_h) DESC", appId)
}

; Elements that fall inside a region, so a region can be operated.
WinModel_ElementsIn(appId, reg, limit := 400) {
    db := AppMapDB()
    if !db
        return []
    x1 := reg["rel_x"], y1 := reg["rel_y"]
    x2 := x1 + reg["rel_w"], y2 := y1 + reg["rel_h"]
    return db.Query("SELECT id,kind,name,role,shortcut,rel_x,rel_y,rel_w,rel_h "
                  . "FROM ui_element WHERE app_id=? AND rel_w>0 "
                  . "AND rel_x>=? AND rel_y>=? AND (rel_x+rel_w)<=? AND (rel_y+rel_h)<=? "
                  . "ORDER BY rel_y, rel_x LIMIT ?"
                  , appId, x1 - 0.005, y1 - 0.005, x2 + 0.005, y2 + 0.005, limit)
}

; The region a live screen point falls in - "where am I working right now".
WinModel_RegionAt(appId, relX, relY) {
    for r in WinModel_Regions(appId) {
        if (relX >= r["rel_x"] && relX <= r["rel_x"] + r["rel_w"]
            && relY >= r["rel_y"] && relY <= r["rel_y"] + r["rel_h"])
            return r
    }
    return Map()
}

; ═══════════════════════════════════════════════════════════════════════════════
; THE WINDOW MAP PANEL
; ═══════════════════════════════════════════════════════════════════════════════
; A scale drawing of the window with each region outlined and named, beside the
; list of regions and the elements inside whichever one is selected.

global g_WMGui := "", g_WMApp := "", g_WMLV := "", g_WMElLV := ""
global g_WMCanvas := "", g_WMInfo := "", g_WMStatus := "", g_WMAppIds := []
global g_WMTiles := []
global g_WMBoxes := []

WinModel_OpenPanel() {
    global g_WMGui, g_WMApp, g_WMLV, g_WMElLV, g_WMCanvas, g_WMInfo, g_WMStatus
    if IsObject(g_WMGui) {
        try {
            g_WMGui.Show()
            return
        }
    }
    g := Gui("+Resize", "Window structure - what each part of a program is for")
    g.MarginX := 10, g.MarginY := 10

    g.Add("Text", "x12 y14 w32", "App:")
    g_WMApp := g.Add("DropDownList", "x46 y11 w290 vWMApp")
    g_WMApp.OnEvent("Change", (*) => WinModel_PanelLoad())
    g.Add("Button", "x342 y10 w120 h24", "Rebuild model").OnEvent("Click", (*) => WinModel_PanelRebuild())
    g.Add("Button", "x468 y10 w130 h24", "Rebuild all apps").OnEvent("Click", (*) => WinModel_RebuildAll())
    g.Add("Button", "x604 y10 w110 h24", "Export map").OnEvent("Click", (*) => WinModel_Export())

    ; The drawing surface: a picture control we paint region boxes onto.
    g.Add("Text", "x12 y42 w400 cGray", "Scale drawing of the window - click a region in the list to highlight it")
    g_WMCanvas := g.Add("Picture", "x12 y60 w560 h330 Border vWMCanvas")

    g.Add("Text", "x12 y398 w560", "Regions found (largest first)")
    g_WMLV := g.Add("ListView", "x12 y416 w560 h150 Grid vWMLV"
        , ["Role", "Position", "Size", "Elements", "Confidence", "#"])
    g_WMLV.ModifyCol(1, 150)
    g_WMLV.ModifyCol(2, 90)
    g_WMLV.ModifyCol(3, 90)
    g_WMLV.ModifyCol(4, 70)
    g_WMLV.ModifyCol(5, 80)
    g_WMLV.ModifyCol(6, 0)
    g_WMLV.OnEvent("ItemSelect", (lv, r, sel) => (sel ? WinModel_PanelSelect() : 0))

    g_WMInfo := g.Add("Edit", "x584 y60 w390 h180 ReadOnly Multi VScroll vWMInfo")
    g_WMInfo.SetFont("s9", "Consolas")
    g.Add("Text", "x584 y246 w390", "Elements inside the selected region")
    g_WMElLV := g.Add("ListView", "x584 y264 w390 h302 Grid vWMElLV"
        , ["Kind", "Name", "Shortcut"])
    g_WMElLV.ModifyCol(1, 80)
    g_WMElLV.ModifyCol(2, 220)
    g_WMElLV.ModifyCol(3, 80)

    g_WMStatus := g.Add("Text", "x12 y574 w962 vWMStatus", "Select an application.")
    g.OnEvent("Size", WinModel_PanelResize)
    g.OnEvent("Close", (*) => g.Hide())
    g.OnEvent("Escape", (*) => g.Hide())
    g_WMGui := g
    g.Show("w986 h602")
    WinModel_PanelApps()
}

WinModel_PanelResize(g, minMax, w, h) {
    if (minMax = -1)
        return
    try {
        rightW := 390
        leftW := Max(300, w - rightW - 34)
        canH := Max(140, Integer((h - 130) * 0.55))
        g["WMCanvas"].Move(12, 60, leftW, canH)
        g["WMLV"].Move(12, 60 + canH + 34, leftW, h - (60 + canH + 34) - 36)
        rx := 24 + leftW
        g["WMInfo"].Move(rx, 60, rightW, 180)
        g["WMElLV"].Move(rx, 264, rightW, h - 264 - 36)
        g["WMStatus"].Move(12, h - 26, w - 24)
    }
}

WinModel_PanelApps() {
    global g_WMApp, g_WMAppIds
    g_WMAppIds := []
    names := []
    for a in AppMap_Apps() {
        cnt := 0
        try cnt := AppMapDB().Scalar("SELECT COUNT(*) FROM ui_region WHERE app_id=?", a["id"])
        names.Push(a["exe"] . "  (" . a["elements"] . " elements"
                 . (cnt ? ", " . cnt . " regions" : ", not modelled yet") . ")")
        g_WMAppIds.Push(a["id"])
    }
    g_WMApp.Delete()
    if names.Length {
        g_WMApp.Add(names)
        g_WMApp.Choose(1)
        WinModel_PanelLoad()
    }
}

WinModel_PanelAppId() {
    global g_WMApp, g_WMAppIds
    i := g_WMApp.Value
    return (i >= 1 && i <= g_WMAppIds.Length) ? g_WMAppIds[i] : 0
}

WinModel_PanelLoad() {
    global g_WMLV, g_WMStatus, g_WMBoxes
    appId := WinModel_PanelAppId()
    g_WMLV.Delete()
    g_WMBoxes := []
    if !appId
        return
    regs := WinModel_Regions(appId)
    if !regs.Length {
        g_WMStatus.Value := "No layout model for this app yet - press Rebuild model."
        WinModel_Draw([])
        return
    }
    for i, r in regs {
        g_WMLV.Add(, r["role"]
                 , Round(r["rel_x"] * 100) . "%, " . Round(r["rel_y"] * 100) . "%"
                 , Round(r["rel_w"] * 100) . "% x " . Round(r["rel_h"] * 100) . "%"
                 , r["elements"], Format("{:.2f}", r["confidence"]), i)
        g_WMBoxes.Push(r)
    }
    WinModel_Draw(regs)
    g_WMStatus.Value := regs.Length . " region(s) derived from the recorded geometry. "
        . "Select one to see what lives inside it."
    g_WMLV.Modify(1, "Select Focus")
}

WinModel_PanelSelect() {
    global g_WMLV, g_WMBoxes, g_WMInfo, g_WMElLV
    row := g_WMLV.GetNext()
    if !row
        return
    idx := Integer(g_WMLV.GetText(row, 6))
    if (idx < 1 || idx > g_WMBoxes.Length)
        return
    r := g_WMBoxes[idx]
    appId := WinModel_PanelAppId()

    t := r["role"] . "`r`n`r`n"
    t .= "position  " . Round(r["rel_x"] * 100) . "% from the left, "
       . Round(r["rel_y"] * 100) . "% from the top`r`n"
    t .= "size      " . Round(r["rel_w"] * 100) . "% wide x "
       . Round(r["rel_h"] * 100) . "% tall`r`n"
    t .= "elements  " . r["elements"] . "`r`n"
    t .= "certainty " . Format("{:.0f}", r["confidence"] * 100) . "%`r`n`r`n"
    t .= "WHY IT WAS CALLED THIS`r`n  " . StrReplace(r["evidence"], "; ", "`r`n  ") . "`r`n`r`n"
    t .= "All coordinates are relative to the window, so they still hold after "
       . "it is moved or resized."
    g_WMInfo.Value := t

    g_WMElLV.Opt("-Redraw")
    g_WMElLV.Delete()
    for e in WinModel_ElementsIn(appId, r, 300)
        g_WMElLV.Add(, e["kind"], e["name"], e["shortcut"])
    g_WMElLV.Opt("+Redraw")
    WinModel_Draw(g_WMBoxes, idx)
}

; Paint the regions as a scale drawing.
;
; Drawn with plain GUI controls rather than GDI+: the main scripts already
; define their own small set of Gdip_* helpers, so including the full library
; here would collide with them. A pool of coloured labels is enough for a
; rectangle map and costs nothing to keep in sync.
WinModel_Draw(regs, highlight := 0) {
    global g_WMGui, g_WMCanvas, g_WMTiles
    if (!IsObject(g_WMGui) || !IsObject(g_WMCanvas))
        return
    if !IsObject(g_WMTiles)
        g_WMTiles := []

    g_WMCanvas.GetPos(&cx, &cy, &cw, &ch)
    if (cw < 40 || ch < 40)
        return
    pad := 6
    w := cw - pad * 2, h := ch - pad * 2

    ; Grow the pool on demand; controls cannot be destroyed individually in v2,
    ; so unused ones are simply hidden.
    while (g_WMTiles.Length < regs.Length) {
        t := g_WMGui.Add("Text", "x0 y0 w10 h10 Center 0x200")
        t.Visible := false
        g_WMTiles.Push(t)
    }

    for i, r in regs {
        tile := g_WMTiles[i]
        x := cx + pad + Round(r["rel_x"] * w)
        y := cy + pad + Round(r["rel_y"] * h)
        rw := Max(6, Round(r["rel_w"] * w))
        rh := Max(6, Round(r["rel_h"] * h))
        tile.Move(x, y, rw, rh)
        tile.Opt("Background" . WinModel_RoleColour(r["role"], i = highlight))
        tile.SetFont((i = highlight) ? "s8 bold cFFFFFF" : "s8 cE8E8E8", "Segoe UI")
        tile.Text := (rw > 54 && rh > 16) ? r["role"] : ""
        tile.Visible := true
        tile.Redraw()
    }
    i := regs.Length + 1
    while (i <= g_WMTiles.Length) {
        g_WMTiles[i].Visible := false
        i++
    }
}

; A colour per role, brightened when the region is selected, so the shape of
; the program is readable at a glance.
WinModel_RoleColour(role, hot := false) {
    c := "4A5568"
    if InStr(role, "main work")
        c := hot ? "3182CE" : "2B6CB0"
    else if InStr(role, "sidebar")
        c := hot ? "38A169" : "2F855A"
    else if InStr(role, "status")
        c := hot ? "9F7AEA" : "805AD5"
    else if InStr(role, "tab strip")
        c := hot ? "D69E2E" : "B7791F"
    else if InStr(role, "menu bar")
        c := hot ? "DD6B20" : "C05621"
    else if InStr(role, "gutter")
        c := hot ? "A0AEC0" : "718096"
    else if InStr(role, "scrollbar")
        c := hot ? "718096" : "4A5568"
    else if InStr(role, "pane")
        c := hot ? "319795" : "2C7A7B"
    else if hot
        c := "718096"
    return c
}

WinModel_PanelRebuild() {
    global g_WMStatus
    appId := WinModel_PanelAppId()
    if !appId
        return
    g_WMStatus.Value := "Deriving layout..."
    r := WinModel_Build(appId)
    if !r.Count {
        g_WMStatus.Value := "Not enough recorded geometry for this app - learn it again "
            . "with the Acc tree and OCR options enabled."
        return
    }
    WinModel_PanelApps()
    g_WMStatus.Value := "Derived " . r["regions"] . " region(s) from " . r["leaves"] . " elements."
}

WinModel_RebuildAll() {
    global g_WMStatus
    n := 0, total := 0
    for a in AppMap_Apps() {
        r := WinModel_Build(a["id"])
        if r.Count {
            n++
            total += r["regions"]
        }
    }
    WinModel_PanelApps()
    g_WMStatus.Value := "Modelled " . n . " app(s), " . total . " region(s) in total."
}

WinModel_Export() {
    global DATA_DIR, g_WMStatus
    appId := WinModel_PanelAppId()
    if !appId
        return
    app := AppMap_AppRow(appId)
    path := DATA_DIR . "\windowmap_" . RegExReplace(app["exe"], "\W", "_") . ".txt"
    out := "WINDOW STRUCTURE - " . app["name"] . "  (" . app["exe"] . ")`r`n"
    out .= "captured at " . app["win_w"] . "x" . app["win_h"] . "`r`n"
    out .= "all coordinates are percentages of the window`r`n`r`n"
    for r in WinModel_Regions(appId) {
        out .= Format("{:-28s} at {:3d}%,{:3d}%  size {:3d}%x{:3d}%  {:4d} elements  ({:.0f}% certain)`r`n"
            , r["role"], Round(r["rel_x"]*100), Round(r["rel_y"]*100)
            , Round(r["rel_w"]*100), Round(r["rel_h"]*100), r["elements"], r["confidence"]*100)
        out .= "    why: " . r["evidence"] . "`r`n"
    }
    Track_WriteFile(path, out)
    g_WMStatus.Value := "Exported to " . path
    try Run('explorer.exe /select,"' . path . '"')
}
