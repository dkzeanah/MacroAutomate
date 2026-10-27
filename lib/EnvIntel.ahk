; ═══════════════════════════════════════════════════════════════════════════════
; EnvIntel.ahk - Environment intelligence: turn a screen/window/image into a
;                machine-readable feature map (the "OCR Feature Map" pipeline)
; ═══════════════════════════════════════════════════════════════════════════════
; Pipeline (mirrors the feature-map reference):
;   1) LAYOUT SEGMENTATION  - group OCR lines into coherent regions/blocks
;   2) TEXT OCR             - Windows OCR over the capture (OCR.ahk)
;   3) SEMANTIC GROUPING    - classify each region's role (title, heading,
;                             button, field/label, list, body, status, path...)
;   4) STRUCTURED EXTRACTION- emit regions as machine-readable JSON with roles,
;                             text and absolute screen bounds
;
; For a live window it also folds in the accessibility tree (Acc.ahk) so named,
; role-typed controls are reconciled with the OCR blocks. An optional refine
; step (off by default, costs a call) asks DeepSeek Flash to label regions.
;
; The capture/OCR/Acc steps touch the live screen; the segmentation and
; classification work on normalized line Maps so they can be unit-tested.
; ═══════════════════════════════════════════════════════════════════════════════

; ─────────────────────────────────────────────────────────────────────────────
; PUBLIC ENTRY POINTS
; ─────────────────────────────────────────────────────────────────────────────
; Map a screen rectangle. region = Map(x,y,w,h). Returns the feature map Map.
Env_MapRegion(region) {
    img := Env_CaptureRegion(region)
    res := ""
    try res := OCR.FromRect(region["x"], region["y"], region["w"], region["h"], {scale: 2})
    lines := Env_LinesFromOcr(res)
    fm := Env_Build(lines, Map("kind", "region", "x", region["x"], "y", region["y"]
                             , "w", region["w"], "h", region["h"], "image", img))
    return fm
}

; Map a window by handle: OCR + accessibility controls fused.
Env_MapWindow(hwnd) {
    if !WinExist("ahk_id " . hwnd)
        return Map("ok", false, "error", "window not found", "regions", [])
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . hwnd)
    region := Map("x", wx, "y", wy, "w", ww, "h", wh)
    img := Env_CaptureRegion(region)
    res := ""
    try res := OCR.FromRect(wx, wy, ww, wh, {scale: 2})
    lines := Env_LinesFromOcr(res)
    controls := Env_AccControls(hwnd)
    fm := Env_Build(lines, Map("kind", "window", "hwnd", hwnd, "x", wx, "y", wy
                             , "w", ww, "h", wh, "image", img, "controls", controls))
    return fm
}

; Map the active window.
Env_MapActive() {
    hwnd := 0
    try hwnd := WinGetID("A")
    if !hwnd
        return Map("ok", false, "error", "no active window", "regions", [])
    return Env_MapWindow(hwnd)
}

; Map an image file (no live screen needed).
Env_MapImage(path) {
    if !FileExist(path)
        return Map("ok", false, "error", "file not found", "regions", [])
    res := ""
    try res := OCR.FromFile(path, {scale: 2})
    lines := Env_LinesFromOcr(res)
    return Env_Build(lines, Map("kind", "image", "image", path))
}

; ─────────────────────────────────────────────────────────────────────────────
; STEP 1+2: OCR -> normalized lines
; ─────────────────────────────────────────────────────────────────────────────
; Normalize an OCR result into an array of Map(text,x,y,w,h). Coordinates are
; whatever the OCR call produced (screen-absolute for FromRect).
Env_LinesFromOcr(res) {
    out := []
    if !IsObject(res)
        return out
    try {
        for , line in res.Lines {
            t := Trim(line.Text)
            if (t = "")
                continue
            ; Line bounds from its words (OCR.Line exposes a BoundingRect too).
            x := 0, y := 0, r := 0, b := 0, have := false
            try {
                for , w in line.Words {
                    wx := w.x, wy := w.y, ww := w.w, wh := w.h
                    if !have {
                        x := wx, y := wy, r := wx + ww, b := wy + wh, have := true
                    } else {
                        x := Min(x, wx), y := Min(y, wy)
                        r := Max(r, wx + ww), b := Max(b, wy + wh)
                    }
                }
            }
            if !have {
                try {
                    br := line.BoundingRect
                    x := br.x, y := br.y, r := br.x + br.w, b := br.y + br.h, have := true
                }
            }
            if have
                out.Push(Map("text", t, "x", x, "y", y, "w", r - x, "h", b - y))
        }
    }
    return out
}

; ─────────────────────────────────────────────────────────────────────────────
; STEP 3: LAYOUT SEGMENTATION - cluster lines into regions (pure, testable)
; ─────────────────────────────────────────────────────────────────────────────
; Lines are grouped into a block when they are vertically close and horizontally
; overlapping. A large vertical gap, or no horizontal overlap, starts a new block.
Env_Cluster(lines) {
    if (lines.Length = 0)
        return []
    ; sort top-to-bottom, then left-to-right
    sorted := lines.Clone()
    Env_SortLines(sorted)

    ; median line height sets the "close enough" gap threshold
    heights := []
    for , l in sorted
        heights.Push(l["h"])
    medH := Env_Median(heights)
    ; Wrapped lines within a paragraph sit only a fraction of a line-height
    ; apart; a heading/section break is a full line-height or more. Keep the
    ; threshold below one line height so breaks separate but wrapped text groups.
    gapLimit := Max(medH * 0.8, 10)

    blocks := []
    cur := ""
    for , l in sorted {
        if !IsObject(cur) {
            cur := Env_NewBlock(l)
            continue
        }
        vGap := l["y"] - (cur["y"] + cur["h"])
        overlap := Env_HOverlap(cur, l)
        if (vGap <= gapLimit && overlap > 0) {
            Env_GrowBlock(cur, l)
        } else {
            blocks.Push(cur)
            cur := Env_NewBlock(l)
        }
    }
    if IsObject(cur)
        blocks.Push(cur)
    return blocks
}

Env_NewBlock(l) {
    return Map("x", l["x"], "y", l["y"], "w", l["w"], "h", l["h"]
             , "lines", [l["text"]], "text", l["text"])
}

Env_GrowBlock(b, l) {
    r := Max(b["x"] + b["w"], l["x"] + l["w"])
    bot := Max(b["y"] + b["h"], l["y"] + l["h"])
    b["x"] := Min(b["x"], l["x"])
    b["y"] := Min(b["y"], l["y"])
    b["w"] := r - b["x"]
    b["h"] := bot - b["y"]
    b["lines"].Push(l["text"])
    b["text"] .= " " . l["text"]
}

; Horizontal overlap in pixels between a block and a line.
Env_HOverlap(a, b) {
    left := Max(a["x"], b["x"])
    right := Min(a["x"] + a["w"], b["x"] + b["w"])
    return right - left
}

Env_SortLines(arr) {
    ; insertion sort by y then x (stable, small N)
    Loop arr.Length {
        i := A_Index, j := i
        while (j > 1 && Env_LineBefore(arr[j], arr[j - 1])) {
            tmp := arr[j], arr[j] := arr[j - 1], arr[j - 1] := tmp
            j--
        }
    }
}

Env_LineBefore(a, b) {
    ; a before b if clearly higher, or same row and further left
    if (a["y"] + a["h"] <= b["y"] + 2)
        return true
    if (b["y"] + b["h"] <= a["y"] + 2)
        return false
    return a["x"] < b["x"]
}

Env_Median(nums) {
    if (nums.Length = 0)
        return 0
    s := nums.Clone()
    Loop s.Length {
        i := A_Index, j := i
        while (j > 1 && s[j] < s[j - 1]) {
            tmp := s[j], s[j] := s[j - 1], s[j - 1] := tmp
            j--
        }
    }
    mid := (s.Length // 2) + 1
    return s[mid]
}

; ─────────────────────────────────────────────────────────────────────────────
; STEP 3b: SEMANTIC GROUPING - classify a region's role (pure, testable)
; ─────────────────────────────────────────────────────────────────────────────
Env_ClassifyRegion(block, meta := "") {
    t := Trim(block["text"])
    lineCount := block.Has("lines") ? block["lines"].Length : 1
    words := StrSplit(RegExReplace(t, "\s+", " "), " ")

    ; a file path or URL
    if RegExMatch(t, "i)^[a-z]:\\|^[a-z][a-z0-9+.-]*://|/[\w.-]+/")
        return "path"
    ; a numeric/metric chip (e.g. "+1,523 -2", counts)
    if RegExMatch(t, "^[+\-]?[\d,]+(\s+[+\-]?[\d,]+)*$")
        return "metric"
    ; short all-caps or title-ish single line -> heading/title
    if (lineCount = 1 && StrLen(t) <= 48 && !InStr(t, ".")) {
        ; == is case-SENSITIVE (= is not): genuinely all-caps -> section heading.
        if (StrUpper(t) == t && RegExMatch(t, "[A-Z]"))
            return "heading"
        ; a short actionable word set -> likely a button/control label
        if (words.Length <= 3 && RegExMatch(t, "i)^(ok|cancel|save|submit|next|back|close|"
            . "open|new|run|edit|delete|add|remove|refresh|send|search|sign in|log in|"
            . "continue|finish|apply|preview|export|import|start|stop)\b"))
            return "button"
        if RegExMatch(t, "i)[:?]$")
            return "label"
        return "heading"
    }
    ; a list: several short lines
    if (lineCount >= 3) {
        shortLines := 0
        for , ln in block["lines"]
            if (StrLen(ln) <= 40)
                shortLines++
        if (shortLines >= lineCount * 0.7)
            return "list"
    }
    ; otherwise prose/body
    return "body"
}

; ─────────────────────────────────────────────────────────────────────────────
; STEP 4: STRUCTURED EXTRACTION - assemble the feature map (pure, testable)
; ─────────────────────────────────────────────────────────────────────────────
Env_Build(lines, meta := "") {
    if !IsObject(meta)
        meta := Map()
    blocks := Env_Cluster(lines)
    regions := []
    id := 0
    for , b in blocks {
        id++
        role := Env_ClassifyRegion(b, meta)
        regions.Push(Map("id", id, "role", role, "text", Trim(b["text"])
                       , "x", b["x"], "y", b["y"], "w", b["w"], "h", b["h"]
                       , "lines", b["lines"].Length))
    }
    ; Fold in accessibility controls when present (window maps).
    controls := (IsObject(meta) && meta.Has("controls")) ? meta["controls"] : []
    out := Map("ok", true, "error", ""
             , "kind", meta.Has("kind") ? meta["kind"] : "region"
             , "stages", ["layout-segmentation", "text-ocr", "semantic-grouping", "structured-extraction"]
             , "regionCount", regions.Length
             , "controlCount", IsObject(controls) ? controls.Length : 0
             , "regions", regions
             , "controls", IsObject(controls) ? controls : [])
    for , k in ["x", "y", "w", "h", "hwnd", "image"]
        if (IsObject(meta) && meta.Has(k))
            out[k] := meta[k]
    return out
}

; ─────────────────────────────────────────────────────────────────────────────
; ACCESSIBILITY CONTROLS (live window)
; ─────────────────────────────────────────────────────────────────────────────
Env_AccControls(hwnd) {
    out := []
    root := ""
    try root := Acc.ElementFromHandle(hwnd)
    if !IsObject(root)
        return out
    els := ""
    try els := root.FindElements({ or: [
        { Role: 43 }, { Role: 44 }, { Role: 45 }    ; pushbutton, checkbox, radio
      , { Role: 42 }, { Role: 46 }, { Role: 47 } ]}) ; text, combobox, list
    if !IsObject(els)
        return out
    for , el in els {
        name := "", roleText := "", val := ""
        try name := el.Name
        try roleText := el.RoleText
        try val := el.Value
        loc := ""
        try loc := el.Location
        if !IsObject(loc)
            continue
        out.Push(Map("name", name != "" ? name : "", "role", roleText
                   , "value", val != "" ? val : ""
                   , "x", loc.x, "y", loc.y, "w", loc.w, "h", loc.h))
        if (out.Length >= 200)
            break
    }
    return out
}

; ─────────────────────────────────────────────────────────────────────────────
; CAPTURE + EXPORT + OPTIONAL VISION REFINE
; ─────────────────────────────────────────────────────────────────────────────
Env_CaptureRegion(region) {
    path := Media_TempDir() . "\env_" . A_TickCount . ".png"
    ok := false, pToken := 0, pBitmap := 0
    try {
        pToken := Gdip_Startup()
        pBitmap := Gdip_BitmapFromScreen(region["x"] . "|" . region["y"]
                                       . "|" . region["w"] . "|" . region["h"])
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

Env_ToJson(fm, indent := 2) {
    ; Emit a clean copy without the local image path blob reference noise.
    ; (param is 'fm', not 'map' - AHK identifiers are case-insensitive, so a
    ; variable named 'map' would shadow the built-in Map class.)
    clean := Map()
    for k, v in fm {
        if (k = "image")
            continue
        clean[k] := v
    }
    return TrackJsonEncode(clean, indent)
}

Env_ExportJson(fm, path := "") {
    if (path = "")
        path := Media_OutDir() . "\envmap_" . FormatTime(A_Now, "yyyyMMdd_HHmmss") . ".json"
    Track_WriteFile(path, Env_ToJson(fm))
    return path
}

; Hotkey (Ctrl+Shift+9): map the active window to a feature-map JSON, copy it to
; the clipboard and save a file. Read-only; no input is driven.
Env_HotMapActive() {
    fm := Env_MapActive()
    if (!fm.Has("ok") || !fm["ok"]) {
        ShowStatus("Env map: " . (fm.Has("error") ? fm["error"] : "failed"), "fail")
        return
    }
    try Know_PersistEnvMap(fm)   ; accumulate in the Knowledge dashboard
    json := Env_ToJson(fm)
    try A_Clipboard := json
    path := Env_ExportJson(fm)
    ShowStatus("Feature map: " . fm["regionCount"] . " region(s), "
             . fm["controlCount"] . " control(s) - JSON copied + saved", "ok")
}

; Optional: ask DeepSeek Flash to describe/label the captured regions. Returns
; the model's JSON (Map/Array) or Map(ok:false,...). Costs one vision call.
Env_RefineWithVision(fm) {
    if (!fm.Has("image") || fm["image"] = "" || !FileExist(fm["image"]))
        return Map("ok", false, "error", "no capture image to refine from")
    instr := "This is a UI screenshot. Return a JSON array of the main regions as "
           . "{role, label, summary}. Roles: title, heading, button, field, label, "
           . "list, body, status, path, metric, media, nav. Be concise."
    return MediaLLM_AnalyzeJson([fm["image"]], instr, Map("maxTokens", 900))
}
