; ═══════════════════════════════════════════════════════════════════════════════
; ElementAutomation.ahk - Consume tracked data from the automation engine
; ═══════════════════════════════════════════════════════════════════════════════
; This is the bridge between what the trackers learn and what the workflow
; engine can DO. It exposes:
;
;   Element_Locate / Element_ClickByName   find a named element on screen and act
;   Element_ExportJson                     portable element registry
;   MouseFeatures_Export                   extracted hotspots as JSON/CSV/Py/JS/AHK
;
; An element can be located two ways, tried in order:
;   1. VISUAL   its stored FindText binary pattern is searched for on screen
;               (survives the window moving; the strongest signal)
;   2. RELATIVE its window-relative 0-1 coordinates are projected onto the live
;               window of the same tracked name (survives a resize)
; ═══════════════════════════════════════════════════════════════════════════════

; ═══════════════════════════════════════════════════════════════════════════════
; LOCATING ELEMENTS
; ═══════════════════════════════════════════════════════════════════════════════

; Locate an element (a Map row from the `element` table) on the current screen.
; Returns Map(x, y, w, h, cx, cy, method) or an empty Map when not found.
Element_Locate(el, err1 := 0.15, err0 := 0.12) {
    result := Map()
    if !el.Count
        return result

    ; ─── 1. Visual match via the stored FindText pattern ─────────────────────
    if (el.Has("bin_text") && el["bin_text"] != "") {
        try {
            ok := FindText(&fx := 0, &fy := 0, 0, 0, A_ScreenWidth, A_ScreenHeight
                         , err1, err0, el["bin_text"])
            if (IsObject(ok) && ok.Length) {
                m := ok[1]
                return Map("x", m.x, "y", m.y, "w", m.w, "h", m.h
                         , "cx", m.x, "cy", m.y, "method", "visual")
            }
        } catch as err {
            TrackLogError("Element_Locate(visual)", err)
        }
    }

    ; ─── 2. Relative projection onto the live window ─────────────────────────
    if (el.Has("win_id") && el["win_id"]) {
        winRow := TrackDB_WinRow(el["win_id"])
        if winRow.Count {
            hwnd := Element_FindLiveWindow(winRow["name"])
            if hwnd {
                try {
                    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . hwnd)
                    cx := wx + Integer(Round(Float(el["rel_x"]) * ww + Float(el["rel_w"]) * ww / 2))
                    cy := wy + Integer(Round(Float(el["rel_y"]) * wh + Float(el["rel_h"]) * wh / 2))
                    return Map("x", cx - Integer(el["w"]) // 2, "y", cy - Integer(el["h"]) // 2
                             , "w", el["w"], "h", el["h"]
                             , "cx", cx - Integer(el["w"]) // 2, "cy", cy - Integer(el["h"]) // 2
                             , "method", "relative")
                } catch as err {
                    TrackLogError("Element_Locate(relative)", err)
                }
            }
        }
    }

    return result
}

; Centre point of a located element.
Element_Center(loc) {
    if !loc.Count
        return Map()
    return Map("x", loc["x"] + Integer(loc["w"]) // 2, "y", loc["y"] + Integer(loc["h"]) // 2)
}

; Find a live top-level window whose tracked (normalised) name matches `name`.
Element_FindLiveWindow(name) {
    best := 0
    for hwnd in WinGetList() {
        title := "", exe := "", class := ""
        try title := WinGetTitle("ahk_id " . hwnd)
        if (title = "")
            continue
        try exe := WinGetProcessName("ahk_id " . hwnd)
        try class := WinGetClass("ahk_id " . hwnd)
        norm := TrackNormalizeWindowName(title, exe)
        if (norm = name)
            return hwnd
        if (best = 0 && InStr(norm, name))
            best := hwnd
    }
    return best
}

; ═══════════════════════════════════════════════════════════════════════════════
; ACTING ON ELEMENTS (used by workflow actions)
; ═══════════════════════════════════════════════════════════════════════════════

; Resolve an element by name, locate it, and click it.
; button: "Left" | "Right" | "Middle", count: click count.
; Returns true on success.
Element_ClickByName(name, button := "Left", count := 1) {
    el := TrackDB_FindElement(name)
    if !el.Count {
        ShowStatus("Element not found in registry: " . name, "fail")
        return false
    }
    loc := Element_Locate(el)
    if !loc.Count {
        ShowStatus("Element '" . name . "' not on screen", "fail")
        return false
    }
    c := Element_Center(loc)
    try {
        Click(c["x"], c["y"], button, count)
    } catch as err {
        TrackLogError("Element_ClickByName", err)
        return false
    }
    TrackDB_BumpElementHit(el["id"])
    ShowStatus("Clicked element '" . name . "' (" . loc["method"] . ")", "ok")
    return true
}

; Move the mouse to an element without clicking.
Element_HoverByName(name) {
    el := TrackDB_FindElement(name)
    if !el.Count
        return false
    loc := Element_Locate(el)
    if !loc.Count
        return false
    c := Element_Center(loc)
    try MouseMove(c["x"], c["y"], 2)
    TrackDB_BumpElementHit(el["id"])
    return true
}

; Wait up to `timeoutMs` for an element to appear. Returns the location Map or "".
Element_WaitByName(name, timeoutMs := 5000) {
    el := TrackDB_FindElement(name)
    if !el.Count
        return ""
    deadline := A_TickCount + timeoutMs
    loop {
        loc := Element_Locate(el)
        if loc.Count
            return loc
        if (A_TickCount >= deadline)
            return ""
        Sleep(150)
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; PORTABLE ELEMENT EXPORT
; ═══════════════════════════════════════════════════════════════════════════════

; Export the element registry (optionally filtered to one window) as JSON.
; Returns the number of elements written.
Element_ExportJson(path, winId := 0) {
    els := TrackDB_Elements(winId)
    arr := []
    for el in els {
        winName := el.Has("win_name") ? el["win_name"] : ""
        arr.Push(Map(
            "name", el["name"],
            "role", el["role"],
            "description", el["description"],
            "window", winName,
            "abs", Map("x", el["x"], "y", el["y"], "w", el["w"], "h", el["h"]),
            "relative", Map("x", el["rel_x"], "y", el["rel_y"], "w", el["rel_w"], "h", el["rel_h"]),
            "findtext", el["bin_text"],
            "hits", el["hits"]
        ))
    }
    doc := Map("kind", "macroautomate.elements", "version", 1
             , "exported", TrackTS(), "count", arr.Length, "elements", arr)
    Track_WriteFile(path, TrackJsonEncode(doc, 2))
    return arr.Length
}

; ═══════════════════════════════════════════════════════════════════════════════
; PORTABLE MOUSE-FEATURE EXPORT
; ═══════════════════════════════════════════════════════════════════════════════
; The extracted interaction hotspots are the reusable, tool-agnostic product of
; the mouse tracker. They are exported in whichever paradigm the target tool
; speaks, always with BOTH absolute window-pixel and normalised 0-1 coordinates.

; format: "json" | "csv" | "python" | "javascript" | "ahk"
MouseFeatures_Export(winId, path, format := "json") {
    feats := MouseTrack_Features(winId)
    winRow := TrackDB_WinRow(winId)
    winName := winRow.Count ? winRow["name"] : ("win" . winId)
    size := MouseTrack_WindowSize(winId)

    switch StrLower(format) {
        case "csv":        content := MouseFeatures_Csv(feats)
        case "python":     content := MouseFeatures_Python(feats, winName, size)
        case "javascript": content := MouseFeatures_JavaScript(feats, winName, size)
        case "ahk":        content := MouseFeatures_Ahk(feats, winName)
        default:           content := MouseFeatures_Json(feats, winName, size)
    }

    Track_WriteFile(path, content)
    return feats.Length
}

MouseFeatures_Json(feats, winName, size) {
    arr := []
    for f in feats {
        arr.Push(Map(
            "kind", f["kind"],
            "x", f["x"], "y", f["y"], "w", f["w"], "h", f["h"],
            "rel_x", f["rel_x"], "rel_y", f["rel_y"],
            "weight", f["weight"], "clicks", f["clicks"],
            "dwell_ms", f["dwell_ms"], "samples", f["samples"]
        ))
    }
    doc := Map("kind", "macroautomate.mouse_features", "version", 1
             , "window", winName
             , "window_size", Map("w", size["w"], "h", size["h"])
             , "count", arr.Length, "features", arr)
    return TrackJsonEncode(doc, 2)
}

MouseFeatures_Csv(feats) {
    out := "kind,x,y,w,h,rel_x,rel_y,weight,clicks,dwell_ms,samples`n"
    for f in feats {
        out .= TrackCsvRow([f["kind"], f["x"], f["y"], f["w"], f["h"]
                          , f["rel_x"], f["rel_y"], f["weight"], f["clicks"]
                          , f["dwell_ms"], f["samples"]]) . "`n"
    }
    return out
}

; A ready-to-run pyautogui snippet: relative coords projected onto the window,
; so it works after the window is resized on another machine.
MouseFeatures_Python(feats, winName, size) {
    out := "# Interaction hotspots extracted by MacroAutomate`n"
    out .= "# Window: " . winName . "  (captured at " . size["w"] . "x" . size["h"] . ")`n"
    out .= "# Coordinates are normalised 0-1; multiply by the live window size.`n`n"
    out .= "FEATURES = [`n"
    for f in feats {
        out .= "    {"
             . "'kind': '" . f["kind"] . "', "
             . "'rel_x': " . f["rel_x"] . ", 'rel_y': " . f["rel_y"] . ", "
             . "'weight': " . f["weight"] . ", 'clicks': " . f["clicks"]
             . "},`n"
    }
    out .= "]`n`n"
    out .= "def click_feature(win_x, win_y, win_w, win_h, feature):`n"
    out .= "    import pyautogui`n"
    out .= "    pyautogui.click(win_x + feature['rel_x'] * win_w,`n"
    out .= "                    win_y + feature['rel_y'] * win_h)`n"
    return out
}

MouseFeatures_JavaScript(feats, winName, size) {
    out := "// Interaction hotspots extracted by MacroAutomate`n"
    out .= "// Window: " . winName . "  (captured at " . size["w"] . "x" . size["h"] . ")`n"
    out .= "export const features = [`n"
    for f in feats {
        out .= "  { kind: '" . f["kind"] . "', "
             . "relX: " . f["rel_x"] . ", relY: " . f["rel_y"] . ", "
             . "weight: " . f["weight"] . ", clicks: " . f["clicks"] . " },`n"
    }
    out .= "];`n`n"
    out .= "// project onto a live window rect: {x,y,width,height}`n"
    out .= "export const point = (rect, f) => ({`n"
    out .= "  x: rect.x + f.relX * rect.width,`n"
    out .= "  y: rect.y + f.relY * rect.height,`n"
    out .= "});`n"
    return out
}

; An AutoHotkey v2 array literal that drops straight into another script.
MouseFeatures_Ahk(feats, winName) {
    out := "; Interaction hotspots extracted by MacroAutomate - window: " . winName . "`n"
    out .= "features := [`n"
    for f in feats {
        out .= "    Map(""kind"", """ . f["kind"] . """, "
             . """relX"", " . f["rel_x"] . ", ""relY"", " . f["rel_y"] . ", "
             . """weight"", " . f["weight"] . ", ""clicks"", " . f["clicks"] . "),`n"
    }
    out .= "]`n"
    return out
}

; ═══════════════════════════════════════════════════════════════════════════════
; FILE WRITER
; ═══════════════════════════════════════════════════════════════════════════════

Track_WriteFile(path, content) {
    dir := ""
    SplitPath(path, , &dir)
    if (dir != "" && !DirExist(dir)) {
        try DirCreate(dir)
    }
    if FileExist(path) {
        try FileDelete(path)
    }
    FileAppend(content, path, "UTF-8")
    return path
}
