; ═══════════════════════════════════════════════════════════════════════════════
; SelfHeal.ahk - keep saved workflows working when the screen changes
; ═══════════════════════════════════════════════════════════════════════════════
; LEARN    After a successful click step, remember an *anchor*: the window
;          (exe/class/title), the point relative to that window, the nearest
;          visible label and its offset, and a small pixel fingerprint.
; CHECK    Before a coordinate click with a confirmed anchor, compare the pixels
;          under the target with the fingerprint. If the target moved, re-find
;          it and click the new location instead (a "moved target" heal).
; RECOVER  When a click/find/wait step fails, try in order: wait for the screen,
;          relaxed pattern match, the remembered label, the target's own name as
;          text, the window-relative position, and (opt-in) the vision model.
;          The best candidate must clear a confidence bar (higher when nobody is
;          watching). Irreversible-looking steps are only healed with a person's
;          OK. Every heal is recorded so it can be applied to the workflow.
; ═══════════════════════════════════════════════════════════════════════════════

global g_SelfHealBusy := false
global g_SelfHealSettings := 0

SelfHeal_Settings(refresh := false) {
    global g_SelfHealSettings
    if refresh || !IsObject(g_SelfHealSettings) {
        g_SelfHealSettings := Map(
            "enabled", TrackDB_MetaGet("selfheal_enabled", "1") = "1",
            "learn", TrackDB_MetaGet("selfheal_learn", "1") = "1",
            "vision", TrackDB_MetaGet("selfheal_vision", "0") = "1",
            "minInteractive", 0.6,
            "minUnattended", Number(TrackDB_MetaGet("selfheal_min_unattended", "0.8")))
    }
    return g_SelfHealSettings
}

SelfHeal_SetSetting(key, value) {
    names := Map("enabled", "selfheal_enabled", "learn", "selfheal_learn", "vision", "selfheal_vision", "minUnattended", "selfheal_min_unattended")
    if !names.Has(key)
        return
    TrackDB_MetaSet(names[key], key = "minUnattended" ? String(value) : (value ? "1" : "0"))
    SelfHeal_Settings(true)
}

SelfHeal_ClickActions() => Map("Click", 1, "Double Click", 2, "Triple Click", 3, "Right Click", 1,
    "Find & Click", 1, "Find & DblClick", 2, "Find & TplClick", 3, "Find & RClick", 1, "Click Element", 1, "OCR Click", 1)

SelfHeal_Healable(action) => SelfHeal_ClickActions().Has(action)
    || action = "Hover Mouse" || action = "Hover Element" || action = "Wait for Pattern" || action = "Wait Element"

SelfHeal_Learnable(action) => SelfHeal_ClickActions().Has(action) || action = "Hover Mouse" || action = "Hover Element"

SelfHeal_WorkflowName() {
    global g_SequenceCallStack, g_AutopilotRun
    if IsSet(g_SequenceCallStack) && g_SequenceCallStack.Length
        return g_SequenceCallStack[g_SequenceCallStack.Length]
    if IsSet(g_AutopilotRun) && IsObject(g_AutopilotRun)
        return g_AutopilotRun["workflow"]
    return "(editor workflow)"
}

SelfHeal_Key(workflow, index, step) {
    key := workflow . "|" . index . "|" . step["action"] . "|" . step["target"]
    return step["action"] = "OCR Click" ? key . "|" . step["param"] : key
}

SelfHeal_Anchor(workflow, index, step) {
    if !TrackDB_Ready()
        return Map()
    try return TrackDB().QueryRow("SELECT * FROM autopilot_anchor WHERE key=?", SelfHeal_Key(workflow, index, step))
    return Map()
}

SelfHeal_Describe(step) {
    if step["action"] = "OCR Click"
        return step["param"]
    return step["target"] != "" ? step["target"] : step["action"]
}

; ─── Geometry and pixels ───────────────────────────────────────────────────────

SelfHeal_RootWindowAt(x, y) {
    point := (x & 0xFFFFFFFF) | ((y & 0xFFFFFFFF) << 32)
    hit := DllCall("WindowFromPoint", "Int64", point, "Ptr")
    return hit ? DllCall("GetAncestor", "Ptr", hit, "UInt", 2, "Ptr") : 0
}

SelfHeal_OnScreen(x, y) {
    left := SysGet(76), top := SysGet(77)
    return x >= left && y >= top && x < left + SysGet(78) && y < top + SysGet(79)
}

SelfHeal_SampleHex(x, y) {
    buf := SampleRegionPixels(x - 24, y - 24, 48, 48, 6)
    hex := ""
    loop buf.Size
        hex .= Format("{:02X}", NumGet(buf, A_Index - 1, "UChar"))
    return hex
}

SelfHeal_HexBuffer(hex) {
    size := StrLen(hex) // 2
    buf := Buffer(Max(size, 4), 0)
    loop size
        NumPut("UChar", Integer("0x" . SubStr(hex, A_Index * 2 - 1, 2)), buf, A_Index - 1)
    return buf
}

; Fraction of the fingerprint that changed: 0 = identical, 1 = unrelated.
SelfHeal_SampleDiff(hexA, hexB) {
    if hexA = "" || hexB = "" || StrLen(hexA) != StrLen(hexB)
        return 1.0
    return ComparePixelSamples(SelfHeal_HexBuffer(hexA), SelfHeal_HexBuffer(hexB))
}

; ─── Text matching ─────────────────────────────────────────────────────────────

SelfHeal_Norm(text) => Trim(RegExReplace(StrLower(text), "[^a-z0-9]+", " "))

SelfHeal_Distance(a, b) {
    la := StrLen(a), lb := StrLen(b)
    if !la || !lb
        return Max(la, lb)
    if Abs(la - lb) > 2
        return 3
    prev := []
    loop lb + 1
        prev.Push(A_Index - 1)
    loop la {
        i := A_Index, cur := [i], ca := SubStr(a, i, 1)
        loop lb {
            j := A_Index
            cost := ca = SubStr(b, j, 1) ? 0 : 1
            cur.Push(Min(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost))
        }
        prev := cur
    }
    return prev[lb + 1]
}

; How well an on-screen text matches a wanted label: 0 (no) .. 1 (exact).
SelfHeal_TextScore(screenText, wanted) {
    s := SelfHeal_Norm(screenText), w := SelfHeal_Norm(wanted)
    if s = "" || w = ""
        return 0
    if s = w
        return 1.0
    if StrLen(w) >= 3 && RegExMatch(" " . s . " ", "\Q " . w . " \E")
        return 0.9
    if StrLen(w) >= 4 && InStr(s, w)
        return 0.78
    if StrLen(w) >= 5 && SelfHeal_Distance(s, w) <= 1
        return 0.7
    return 0
}

; "SubmitButton" / "save_btn" / "Email field" -> "Submit" / "save" / "Email"
SelfHeal_NameWords(name) {
    name := RegExReplace(name, "^\[P\] ")
    name := RegExReplace(name, "([a-z])([A-Z])", "$1 $2")
    name := RegExReplace(name, "[_\-.]+", " ")
    name := RegExReplace(name, "i)\b(button|btn|link|field|icon|box|tab|menu|item|spot|pos|position|target|click|area|input)\b", "")
    name := Trim(RegExReplace(name, "\s+", " "))
    return RegExMatch(name, "[A-Za-z]{2,}") ? name : ""
}

; Every OCR word and line inside a region as Map(text, x, y) with screen centers.
SelfHeal_ReadTexts(region) {
    out := []
    if !IsOCRAvailable() || !IsObject(region)
        return out
    result := OCR.FromRect(region["x1"], region["y1"], region["x2"] - region["x1"], region["y2"] - region["y1"], WorkflowOCR_Options())
    for , line in result.Lines {
        center := WorkflowOCR_Center(line)
        out.Push(Map("text", line.Text, "x", center["x"], "y", center["y"], "kind", "line"))
    }
    for , word in result.Words {
        center := WorkflowOCR_Center(word)
        out.Push(Map("text", word.Text, "x", center["x"], "y", center["y"], "kind", "word"))
    }
    return out
}

; ─── Learning ──────────────────────────────────────────────────────────────────

; What is at (x, y): its window, relative position, nearest label and fingerprint.
SelfHeal_Observe(x, y) {
    hwnd := SelfHeal_RootWindowAt(x, y)
    if !hwnd
        return Map()
    try WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . hwnd)
    catch
        return Map()
    if ww <= 0 || wh <= 0
        return Map()
    exe := "", title := "", klass := ""
    try exe := WinGetProcessName("ahk_id " . hwnd)
    try title := WinGetTitle("ahk_id " . hwnd)
    try klass := WinGetClass("ahk_id " . hwnd)
    label := "", dx := 0, dy := 0
    try {
        region := Map("x1", Max(wx, x - 170), "y1", Max(wy, y - 45), "x2", Min(wx + ww, x + 170), "y2", Min(wy + wh, y + 45))
        best := 0, bestDistance := 99999
        for , item in SelfHeal_ReadTexts(region) {
            text := Trim(item["text"])
            if StrLen(text) < 2 || StrLen(text) > 48 || !RegExMatch(text, "[A-Za-z]{2,}")
                continue
            ; Prefer the text under the point, then the closest; lines beat words at equal distance.
            distance := Sqrt((item["x"] - x) ** 2 + (item["y"] - y) ** 2) + (item["kind"] = "word" ? 4 : 0)
            if distance < bestDistance
                best := item, bestDistance := distance
        }
        if IsObject(best) && bestDistance <= 150
            label := best["text"], dx := x - best["x"], dy := y - best["y"]
    }
    return Map("exe", exe, "title", SubStr(title, 1, 200), "class", klass, "hwnd", hwnd,
        "rel_x", (x - wx) / ww, "rel_y", (y - wy) / wh, "win_w", ww, "win_h", wh,
        "label", label, "label_dx", dx, "label_dy", dy, "sample", SelfHeal_SampleHex(x, y))
}

SelfHeal_Learn(step, index) {
    global g_SelfHealBusy
    if g_SelfHealBusy || !IsObject(step) || !SelfHeal_Learnable(step["action"]) || !TrackDB_Ready()
        return
    settings := SelfHeal_Settings()
    if !settings["enabled"] || !settings["learn"]
        return
    try {
        workflow := SelfHeal_WorkflowName()
        key := SelfHeal_Key(workflow, index, step)
        db := TrackDB()
        row := db.QueryRow("SELECT successes, updated FROM autopilot_anchor WHERE key=?", key)
        ; Three confirmations, then refresh at most daily: keeps OCR off the hot path.
        if row.Count && Integer(row["successes"]) >= 3 && SubStr(row["updated"], 1, 10) = FormatTime(A_Now, "yyyy-MM-dd") {
            db.Run("UPDATE autopilot_anchor SET successes=successes+1 WHERE key=?", key)
            return
        }
        MouseGetPos(&x, &y)
        SelfHeal_SaveAnchor(key, workflow, index, step, SelfHeal_Observe(x, y))
    } catch as err
        try LogErrorToFile(err, "caught", "SelfHeal_Learn")
}

SelfHeal_SaveAnchor(key, workflow, index, step, anchor) {
    if !anchor.Count
        return
    TrackDB().Run("INSERT INTO autopilot_anchor(key,workflow,step_index,action,target,exe,title,class,rel_x,rel_y,win_w,win_h,label,label_dx,label_dy,sample,successes,updated) "
        . "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,1,?) ON CONFLICT(key) DO UPDATE SET exe=excluded.exe,title=excluded.title,class=excluded.class,"
        . "rel_x=excluded.rel_x,rel_y=excluded.rel_y,win_w=excluded.win_w,win_h=excluded.win_h,"
        . "label=CASE WHEN excluded.label<>'' THEN excluded.label ELSE autopilot_anchor.label END,"
        . "label_dx=CASE WHEN excluded.label<>'' THEN excluded.label_dx ELSE autopilot_anchor.label_dx END,"
        . "label_dy=CASE WHEN excluded.label<>'' THEN excluded.label_dy ELSE autopilot_anchor.label_dy END,"
        . "sample=excluded.sample,successes=autopilot_anchor.successes+1,updated=excluded.updated",
        key, workflow, index, step["action"], step["target"], anchor["exe"], anchor["title"], anchor["class"],
        Float(anchor["rel_x"]), Float(anchor["rel_y"]), anchor["win_w"], anchor["win_h"], anchor["label"],
        anchor["label_dx"], anchor["label_dy"], anchor["sample"], Autopilot_Now())
}

; ─── Locating candidates ───────────────────────────────────────────────────────

; The live window an anchor belongs to: the active one if it matches, else the
; best exe+class match (title words break ties).
SelfHeal_AnchorWindow(anchor) {
    if !anchor.Count || anchor["exe"] = ""
        return 0
    criteria := "ahk_exe " . anchor["exe"] . (anchor["class"] != "" ? " ahk_class " . anchor["class"] : "")
    if hwnd := WinActive(criteria)
        return hwnd
    best := 0, bestScore := -1
    for hwnd in WinGetList(criteria) {
        title := ""
        try title := WinGetTitle("ahk_id " . hwnd)
        if title = ""
            continue
        score := SelfHeal_TextScore(title, anchor["title"])
        if score > bestScore
            best := hwnd, bestScore := score
    }
    return best
}

SelfHeal_WindowRegion(hwnd) {
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " . hwnd)
        if w > 0 && h > 0
            return Map("x1", x, "y1", y, "x2", x + w, "y2", y + h, "w", w, "h", h)
    }
    return 0
}

; Best text match in a window for `wanted`, near the expected point when known.
SelfHeal_FindText(hwnd, wanted, expectX := "", expectY := "") {
    region := SelfHeal_WindowRegion(hwnd)
    if !region || SelfHeal_Norm(wanted) = ""
        return Map()
    matches := []
    for , item in SelfHeal_ReadTexts(region) {
        score := SelfHeal_TextScore(item["text"], wanted)
        if score > 0
            matches.Push(Map("x", item["x"], "y", item["y"], "score", score, "text", item["text"]))
    }
    if !matches.Length
        return Map()
    best := 0, second := 0
    for , m in matches {
        m["rank"] := m["score"] - (expectX != "" ? Min(0.25, Sqrt((m["x"] - expectX) ** 2 + (m["y"] - expectY) ** 2) / 2000) : 0)
        if !IsObject(best) || m["rank"] > best["rank"]
            second := best, best := m
        else if !IsObject(second) || m["rank"] > second["rank"]
            second := m
    }
    ; Several equally good, far-apart matches are ambiguous.
    if IsObject(second) && best["rank"] - second["rank"] < 0.05 && Abs(best["x"] - second["x"]) + Abs(best["y"] - second["y"]) > 30
        best["score"] -= 0.2
    best["count"] := matches.Length
    return best
}

SelfHeal_Candidates(step, anchor) {
    global g_Settings
    action := step["action"], target := step["target"], out := []
    hwnd := SelfHeal_AnchorWindow(anchor)
    if !hwnd
        hwnd := WinExist("A")
    region := hwnd ? SelfHeal_WindowRegion(hwnd) : 0
    expectX := "", expectY := ""
    if anchor.Count && region
        expectX := region["x1"] + Round(Float(anchor["rel_x"]) * region["w"]), expectY := region["y1"] + Round(Float(anchor["rel_y"]) * region["h"])

    ; 1. A saved pattern with a relaxed tolerance (anti-aliasing, theme or DPI drift).
    if InStr(action, "Find & ") = 1 || action = "Wait for Pattern" {
        name := StrReplace(target, "[P] ", "")
        tolerance := Min(0.35, Max(0.2, Float(g_Settings["FindTextTolerance"]) * 2))
        found := FindPatternOnScreen(name, tolerance, hwnd)
        if found["found"] && found["match_count"] = 1
            out.Push(Map("strategy", "relaxed pattern match", "confidence", 0.8, "x", found["mx"], "y", found["my"], "label", name))
    }
    ; 2. The label remembered next to the target on earlier successful runs.
    if hwnd && anchor.Count && anchor["label"] != "" {
        m := SelfHeal_FindText(hwnd, anchor["label"], expectX, expectY)
        if m.Count {
            confidence := 0.62 + (m["score"] - 0.7) * 0.9
            out.Push(Map("strategy", "remembered label", "confidence", Min(0.92, confidence), "label", m["text"],
                "x", m["x"] + Integer(anchor["label_dx"]), "y", m["y"] + Integer(anchor["label_dy"])))
        }
    }
    ; 3. The step's own name or text (OCR Click text, "SubmitButton" -> "Submit").
    wanted := action = "OCR Click" ? step["param"] : SelfHeal_NameWords(target)
    if hwnd && wanted != "" && (!anchor.Count || SelfHeal_Norm(wanted) != SelfHeal_Norm(anchor["label"])) {
        m := SelfHeal_FindText(hwnd, wanted, expectX, expectY)
        if m.Count
            out.Push(Map("strategy", "visible text", "confidence", Min(0.85, 0.5 + (m["score"] - 0.7) * 0.9 - (m["count"] > 2 ? 0.1 : 0)),
                "label", m["text"], "x", m["x"], "y", m["y"]))
    }
    ; 4. Same spot relative to the (moved or resized) window, if it still looks the same.
    if anchor.Count && region && expectX != "" {
        diff := SelfHeal_SampleDiff(anchor["sample"], SelfHeal_SampleHex(expectX, expectY))
        if diff <= 0.4
            out.Push(Map("strategy", "window-relative position", "confidence", diff <= 0.2 ? 0.82 : 0.66,
                "label", anchor["label"], "x", expectX, "y", expectY, "detail", Round((1 - diff) * 100) . "% pixel match"))
    }
    ; Agreement between independent strategies raises confidence.
    for , a in out {
        for , b in out
            if a != b && Abs(a["x"] - b["x"]) <= 12 && Abs(a["y"] - b["y"]) <= 12
                a["confidence"] := Min(0.97, a["confidence"] + 0.06)
        if anchor.Count && anchor["sample"] != "" && a["strategy"] != "window-relative position" {
            diff := SelfHeal_SampleDiff(anchor["sample"], SelfHeal_SampleHex(a["x"], a["y"]))
            a["confidence"] += diff <= 0.3 ? 0.05 : diff > 0.65 ? -0.12 : 0
        }
    }
    return out
}

SelfHeal_Best(candidates, minimum, anchor := 0) {
    best := Map()
    for , c in candidates {
        if c["confidence"] < minimum || !SelfHeal_OnScreen(c["x"], c["y"]) || IsNearCloseButton(c["x"], c["y"])
            continue
        if IsObject(anchor) && anchor.Count && anchor["exe"] != "" {
            hit := SelfHeal_RootWindowAt(c["x"], c["y"]), exe := ""
            try exe := WinGetProcessName("ahk_id " . hit)
            if exe != anchor["exe"]
                continue  ; never land in a different application
        }
        if !best.Count || c["confidence"] > best["confidence"]
            best := c
    }
    return best
}

; Last resort, opt-in: ask the vision model where the control is.
SelfHeal_Vision(step, anchor) {
    if !SelfHeal_Settings()["vision"] || !StudyLLM_HasKey()
        return Map()
    hwnd := SelfHeal_AnchorWindow(anchor)
    if !hwnd
        hwnd := WinExist("A")
    region := hwnd ? SelfHeal_WindowRegion(hwnd) : 0
    if !region
        return Map()
    path := A_Temp . "\fan-selfheal-" . A_TickCount . ".png"
    if !Autopilot_CaptureRegion(region, path)
        return Map()
    try {
        wanted := step["action"] . " target '" . SelfHeal_Describe(step) . "'"
            . (anchor.Count && anchor["label"] != "" ? " (it had the visible label '" . anchor["label"] . "')" : "")
        reply := StudyLLM_Ask("This screenshot is a " . region["w"] . "x" . region["h"] . " pixel Windows application window. "
            . "Find the control for this workflow step: " . wanted . ". Answer with one JSON object only: "
            . '{"found": true or false, "x": center x in screenshot pixels, "y": center y, "confidence": 0 to 1, "label": "visible text of the control"}',
            Map("imagePath", path, "maxTokens", 200, "system", "You locate user-interface controls in screenshots. Reply with one JSON object and nothing else."))
        if !reply.Get("ok", false) || !RegExMatch(reply["answer"], "s)\{.*\}", &m)
            return Map()
        data := TrackJsonDecode(m[0])
        if !data.Get("found", false) || !IsNumber(data.Get("x", "")) || !IsNumber(data.Get("y", ""))
            return Map()
        x := Integer(data["x"]), y := Integer(data["y"])
        if x < 0 || y < 0 || x >= region["w"] || y >= region["h"]
            return Map()
        confidence := Min(0.75, IsNumber(data.Get("confidence", "")) ? Float(data["confidence"]) : 0.5)
        return Map("strategy", "vision model", "confidence", confidence, "x", region["x1"] + x, "y", region["y1"] + y,
            "label", String(data.Get("label", "")), "detail", "estimated cost $" . Round(reply.Get("costUSD", 0), 4))
    } catch as err {
        try LogErrorToFile(err, "caught", "SelfHeal_Vision")
        return Map()
    } finally {
        try FileDelete(path)
    }
}

SelfHeal_Risky(step, candidate) {
    text := step["target"] . " " . step["param"] . " " . candidate.Get("label", "")
    return RegExMatch(text, "i)\b(submit|send|pay|payment|transfer|wire|delete|remove|purchase|buy|checkout|place order|confirm|approve|e-?sign|publish|refund|void|file return|finali[sz]e)\b") != 0
}

; Perform the step's own action at a re-found point.
SelfHeal_Perform(step, candidate) {
    action := step["action"], x := candidate["x"], y := candidate["y"]
    clicks := SelfHeal_ClickActions()
    if action = "Hover Mouse" || action = "Hover Element" {
        MouseMove(x, y, 5)
        return true
    }
    if action = "Wait for Pattern" || action = "Wait Element"
        return true
    if !clicks.Has(action)
        return false
    button := action = "Right Click" || action = "Find & RClick" ? "Right" : "Left", count := clicks[action]
    if action = "Click" && IsNumber(step["param"])
        count := Max(1, Min(3, Integer(step["param"])))
    if action = "Click Element" && step["param"] != "" {
        parts := StrSplit(step["param"], ",")
        button := RegExMatch(Trim(parts[1]), "i)^(Left|Right|Middle)$") ? Trim(parts[1]) : "Left"
        count := parts.Length > 1 && IsNumber(Trim(parts[2])) ? Integer(Trim(parts[2])) : 1
    }
    FlashClickPosition(x, y)
    return ClickVerified(x, y, button, count)
}

; ─── Engine hooks ──────────────────────────────────────────────────────────────

; Before a coordinate click: if the pixels under the target no longer match the
; learned fingerprint, return a re-found "x,y" for the engine to click instead.
SelfHeal_Before(step, index, &heal) {
    global g_SelfHealBusy, g_AbortSequence
    heal := 0
    action := step["action"]
    if g_SelfHealBusy || g_AbortSequence || !(action = "Click" || action = "Double Click" || action = "Triple Click" || action = "Right Click")
        return ""
    if !SelfHeal_Settings()["enabled"] || step["target"] = "" || step["target"] = "(none)"
        return ""
    try {
        workflow := SelfHeal_WorkflowName()
        anchor := SelfHeal_Anchor(workflow, index, step)
        if !anchor.Count || Integer(anchor["successes"]) < 2 || anchor["sample"] = ""
            return ""
        target := SubstituteWorkflowVariables(step["target"])
        if !ResolveWorkflowPoint(target, &x, &y)
            return ""
        if SelfHeal_SampleDiff(anchor["sample"], SelfHeal_SampleHex(x, y)) <= 0.35
            return ""
        Sleep(600)  ; maybe still drawing
        if SelfHeal_SampleDiff(anchor["sample"], SelfHeal_SampleHex(x, y)) <= 0.35
            return ""
        g_SelfHealBusy := true
        settings := SelfHeal_Settings()
        minimum := Autopilot_Interactive() ? Max(0.7, settings["minInteractive"]) : settings["minUnattended"]
        candidate := SelfHeal_Best(SelfHeal_Candidates(step, anchor), minimum, anchor)
        if !candidate.Count || Abs(candidate["x"] - x) + Abs(candidate["y"] - y) < 6
            return ""  ; nothing better: keep the saved behavior
        if SelfHeal_Risky(step, candidate) && !SelfHeal_Confirm(step, index, candidate)
            return ""
        heal := Map("strategy", "moved target · " . candidate["strategy"], "confidence", Round(candidate["confidence"], 2),
            "x", candidate["x"], "y", candidate["y"], "detail", "the original spot no longer looked the same")
        SelfHeal_Record(workflow, index, step, heal, anchor)
        return candidate["x"] . "," . candidate["y"]
    } catch as err {
        try LogErrorToFile(err, "caught", "SelfHeal_Before")
        return ""
    } finally g_SelfHealBusy := false
}

; After a failed step: try to complete it at a re-found target. True when healed.
SelfHeal_Recover(step, index, speed, &heal) {
    global g_SelfHealBusy, g_AbortSequence, g_LastActionError
    heal := 0
    if g_SelfHealBusy || g_AbortSequence || !IsObject(step) || !SelfHeal_Healable(step["action"]) || !SelfHeal_Settings()["enabled"]
        return false
    originalError := g_LastActionError
    g_SelfHealBusy := true
    try {
        settings := SelfHeal_Settings()
        interactive := Autopilot_Interactive()
        minimum := interactive ? settings["minInteractive"] : settings["minUnattended"]
        workflow := SelfHeal_WorkflowName()
        anchor := SelfHeal_Anchor(workflow, index, step)
        ShowStatus("Self-heal: looking for '" . SelfHeal_Describe(step) . "' again...", "retry")
        ; 1. Often the screen simply had not finished loading.
        if !WorkflowExecution_Wait(Round(900 / Max(Float(speed), 0.25)))
            return false
        g_LastActionError := ""
        if ExecuteActionVerified(step["action"], step["target"], step["param"], step, speed) {
            heal := Map("strategy", "waited for the screen", "confidence", 0.95, "detail", "worked after a short wait; consider adding a Wait step")
            return SelfHeal_Record(workflow, index, step, heal, anchor)
        }
        if g_AbortSequence
            return false
        candidate := SelfHeal_Best(SelfHeal_Candidates(step, anchor), minimum, anchor)
        if !candidate.Count {
            vision := SelfHeal_Vision(step, anchor)
            if vision.Count
                candidate := SelfHeal_Best([vision], minimum, anchor)
        }
        if !candidate.Count {
            g_LastActionError := (originalError != "" ? originalError : step["action"] . " failed") . " · self-heal found no confident match"
            return false
        }
        ; A person confirms irreversible-looking steps and any heal below 80% confidence.
        if (SelfHeal_Risky(step, candidate) || candidate["confidence"] < 0.8) && !SelfHeal_Confirm(step, index, candidate) {
            g_LastActionError := (originalError != "" ? originalError : step["action"] . " failed")
                . " · self-heal needs a person to confirm '" . candidate.Get("label", "") . "'"
            return false
        }
        if !SelfHeal_Perform(step, candidate) {
            g_LastActionError := "Self-heal found the target but could not act on it"
            return false
        }
        heal := Map("strategy", candidate["strategy"], "confidence", Round(candidate["confidence"], 2),
            "x", candidate["x"], "y", candidate["y"], "detail", candidate.Get("detail", candidate.Get("label", "")))
        SelfHeal_Record(workflow, index, step, heal, anchor)
        ShowStatus("Self-healed step " . index . " (" . candidate["strategy"] . ", " . Round(candidate["confidence"] * 100) . "%)", "ok")
        return true
    } catch as err {
        try LogErrorToFile(err, "caught", "SelfHeal_Recover")
        if g_LastActionError = ""
            g_LastActionError := originalError
        return false
    } finally g_SelfHealBusy := false
}

SelfHeal_Confirm(step, index, candidate) {
    if !Autopilot_Interactive()
        return false
    reason := SelfHeal_Risky(step, candidate) ? "This step looks irreversible." : "Fan is not fully sure this is the same control."
    HighlightRegion(candidate["x"] - 20, candidate["y"] - 12, 40, 24, 4000, "match", candidate.Get("label", ""))
    return MsgBoxTop("Step " . index . " (" . step["action"] . " '" . SelfHeal_Describe(step) . "') could not use its saved target.`n`n"
        . "Fan found '" . candidate.Get("label", "?") . "' by " . candidate["strategy"] . " ("
        . Round(candidate["confidence"] * 100) . "% confident), highlighted on screen.`n`n" . reason . " Use the re-found target?",
        "Fan · confirm self-heal", "YesNo Icon? Default2") = "Yes"
}

; Ledger row + refreshed anchor at the healed location. Returns true.
SelfHeal_Record(workflow, index, step, heal, anchor) {
    global g_AutopilotRun
    if !TrackDB_Ready()
        return true
    try {
        window := "", relX := "", relY := "", label := heal.Get("detail", "")
        if heal.Has("x") {
            observed := SelfHeal_Observe(heal["x"], heal["y"])
            if observed.Count {
                window := "ahk_exe " . observed["exe"] . (observed["class"] != "" ? " ahk_class " . observed["class"] : "")
                relX := Round(observed["rel_x"], 4), relY := Round(observed["rel_y"], 4)
                if observed["label"] != ""
                    label := observed["label"]
                SelfHeal_SaveAnchor(SelfHeal_Key(workflow, index, step), workflow, index, step, observed)
            }
        }
        TrackDB().Run("INSERT INTO autopilot_heal(at,run_id,workflow,step_index,action,target,param,strategy,confidence,x,y,window,rel_x,rel_y,label,detail,status) "
            . "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", Autopilot_Now(), IsObject(g_AutopilotRun) ? g_AutopilotRun["run_id"] : "",
            workflow, index, step["action"], step["target"], step["param"], heal["strategy"], Float(heal["confidence"]),
            heal.Get("x", ""), heal.Get("y", ""), window, relX, relY, label, heal.Get("detail", ""),
            heal["strategy"] = "waited for the screen" ? "info" : "open")
        db := TrackDB()
        db.Run("DELETE FROM autopilot_heal WHERE id NOT IN (SELECT id FROM autopilot_heal ORDER BY id DESC LIMIT 2000)")
    } catch as err
        try LogErrorToFile(err, "caught", "SelfHeal_Record")
    return true
}

; ─── Reliability ───────────────────────────────────────────────────────────────

; Map(workflow -> Map(runs, ok, rate, heals, recentHeals, last, lastError, badge)) from the last 20 runs each.
SelfHeal_Health() {
    out := Map()
    if !TrackDB_Ready()
        return out
    rows := TrackDB().Query("SELECT workflow, ok, aborted, heals, started, error FROM autopilot_run ORDER BY started DESC LIMIT 4000")
    for , row in rows {
        name := row["workflow"]
        if !out.Has(name)
            out[name] := Map("runs", 0, "ok", 0, "heals", 0, "recentHeals", 0, "last", row["started"], "lastError", "")
        h := out[name]
        if h["runs"] >= 20
            continue
        h["runs"]++
        h["ok"] += Integer(row["ok"]) ? 1 : 0
        h["heals"] += Integer(row["heals"] = "" ? 0 : row["heals"])
        if h["runs"] <= 5
            h["recentHeals"] += Integer(row["heals"] = "" ? 0 : row["heals"])
        if h["lastError"] = "" && !Integer(row["ok"]) && row["error"] != ""
            h["lastError"] := row["error"]
    }
    for name, h in out {
        h["rate"] := h["runs"] ? h["ok"] / h["runs"] : 0
        h["badge"] := h["runs"] < 3 ? "New"
            : h["rate"] < 0.8 ? "Needs attention"
            : h["recentHeals"] > 0 ? "Self-healing"
            : h["rate"] >= 0.95 ? "Reliable" : "Mostly reliable"
    }
    return out
}

; Enabled-step index (what the engine reports) -> position in the saved steps array.
SelfHeal_StepPosition(steps, enabledIndex) {
    count := 0
    for position, step in steps {
        if step.Has("enabled") && step["enabled"] {
            count++
            if count = enabledIndex
                return position
        }
    }
    return 0
}

; The permanent change a heal suggests, or "" when it has none.
SelfHeal_FixFor(heal) {
    action := heal["action"]
    if heal["window"] != "" && heal["rel_x"] != "" && (action = "Click" || action = "Double Click" || action = "Triple Click"
        || action = "Right Click" || action = "Hover Mouse")
        return Map("action", action, "target", "winrel:" . heal["window"] . "|" . Format("{:.4f}", heal["rel_x"]) . "," . Format("{:.4f}", heal["rel_y"]),
            "describe", "click at the re-found spot inside the window (follows the window when it moves)")
    if action = "Find & Click" && heal["label"] != ""
        return Map("action", "OCR Click", "target", "window:A", "param", heal["label"],
            "describe", "click the visible text '" . heal["label"] . "' instead of the image pattern")
    return ""
}

SelfHeal_ApplyFix(healId) {
    global g_Sequences
    db := TrackDB()
    heal := db.QueryRow("SELECT * FROM autopilot_heal WHERE id=?", healId)
    if !heal.Count
        throw Error("That heal record no longer exists")
    fix := SelfHeal_FixFor(heal)
    if !IsObject(fix)
        throw Error("This heal has no automatic fix. Re-capture the target in the Workflow editor.")
    if !g_Sequences.Has(heal["workflow"])
        throw Error("Workflow '" . heal["workflow"] . "' is not saved (or was renamed)")
    steps := g_Sequences[heal["workflow"]]["steps"]
    position := SelfHeal_StepPosition(steps, Integer(heal["step_index"]))
    if !position || steps[position]["action"] != heal["action"] || steps[position]["target"] != heal["target"]
        throw Error("The workflow changed since this heal; open it in the Workflow editor instead")
    old := steps[position]
    if MsgBoxTop("Update step " . position . " of '" . heal["workflow"] . "'?`n`nNow: " . old["action"] . " | " . old["target"] . " | " . old["param"]
        . "`nNew: " . fix["action"] . " | " . fix["target"] . " | " . fix.Get("param", old["param"]) . "`n`nThe step will " . fix["describe"] . ".",
        "Fan · apply self-heal fix", "YesNo Icon?") != "Yes"
        return false
    updated := old.Clone()
    updated["action"] := fix["action"], updated["target"] := fix["target"]
    if fix.Has("param")
        updated["param"] := fix["param"]
    steps[position] := updated
    if !SaveSequences(true) {
        steps[position] := old
        throw Error("The workflow could not be saved; it was left unchanged")
    }
    db.Run("UPDATE autopilot_heal SET status='applied', previous=? WHERE id=?", TrackJsonEncode(old), healId)
    try RefreshSeqLV()
    return true
}

SelfHeal_UndoFix(healId) {
    global g_Sequences
    db := TrackDB()
    heal := db.QueryRow("SELECT * FROM autopilot_heal WHERE id=?", healId)
    if !heal.Count || heal["status"] != "applied" || heal["previous"] = ""
        throw Error("Only an applied fix can be undone")
    if !g_Sequences.Has(heal["workflow"])
        throw Error("Workflow '" . heal["workflow"] . "' is not saved")
    previous := TrackJsonDecode(heal["previous"])
    fix := SelfHeal_FixFor(heal)
    steps := g_Sequences[heal["workflow"]]["steps"]
    position := SelfHeal_StepPosition(steps, Integer(heal["step_index"]))
    if !position || !IsObject(fix) || steps[position]["target"] != fix["target"]
        throw Error("That step was edited after the fix; change it in the Workflow editor")
    current := steps[position]
    restored := current.Clone()
    for key in ["action", "target", "param"]
        restored[key] := previous.Get(key, current[key])
    steps[position] := restored
    if !SaveSequences(true) {
        steps[position] := current
        throw Error("The workflow could not be saved")
    }
    db.Run("UPDATE autopilot_heal SET status='open' WHERE id=?", healId)
    try RefreshSeqLV()
    return true
}

SelfHeal_Forget(workflow) {
    if TrackDB_Ready()
        TrackDB().Run("DELETE FROM autopilot_anchor WHERE workflow=?", workflow)
}
