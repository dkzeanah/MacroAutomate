#Include DeepSeekActivity.ahk
; ═══════════════════════════════════════════════════════════════════════════════
; StudyComposer.ahk - self-composed, human-paced answer entry (spec section 7)
; ═══════════════════════════════════════════════════════════════════════════════
; Turns a structured Question + a proposed answer into a WORKFLOW (steps in the
; same action vocabulary the Macro Automator engine executes: Click / Send Keys /
; Type Text / Paste / Wait) and runs it against the pinned Chrome tab only.
;
; What makes it "human":
;   * bezier-curved, wobbling pointer paths instead of straight-line teleports
;   * randomized hover pauses and micro-jitter before each press
;   * configurable typo-and-correction typing (always verified afterwards)
;   * randomized inter-key timing
;   * long text goes through the clipboard so essays do not take minutes
;
; What makes it safe:
;   * the focus/portal guard runs before EVERY step (StudyAuto_Guard)
;   * every target is re-located fresh in the live accessibility tree
;     immediately before the click - stale coordinates from the
;     capture are never trusted
;   * a page-change signature check between steps aborts the run
;   * each step verifies its outcome (checked state, field value, dropdown
;     value) and any mismatch is a safe stop, never a blind retry
;   * submit is only clicked when the session mode and the auto-submit
;     setting both say so, and only on a control re-found by name
;
; Plans reuse the engine's step Maps and action vocabulary, with a dedicated
; Choose Dropdown action. Live entry uses StudyMacro_Run for input verification.
; ═══════════════════════════════════════════════════════════════════════════════

global g_StudyHuman := Map(
    "typoRate",    0.02,   ; supported settings range 0..0.3 per character
    "hoverMs",     300,    ; hover pause before a click
    "wobble",      1.0,    ; path curvature multiplier
    "longtextPaste", true,
    "wpm", 70, "overshootPx", 6, "overshootRate", 0.25,
    "jitterPx", 2, "pauseRate", 0.04)

global g_StudyMacroRunning := false
global g_StudyMacroCancelled := false
global g_StudyInputTarget := ""
global g_StudyInputGuardAt := 0
global g_StudyMacroTrace := []
global g_StudyInputFailure := ""
global g_StudyMacroLastPlan := []      ; the last composed plan (UI display)
global g_StudyWalkCache := Map("t", 0, "controls", [])  ; fresh Acc walk cache

; ─────────────────────────────────────────────────────────────────────────────
; HUMAN INPUT PRIMITIVES
; ─────────────────────────────────────────────────────────────────────────────
StudyHuman_Rand(min, max) {
    return Random(min + 0.0, max + 0.0)
}

StudyHuman_RandI(min, max) {
    return Round(StudyHuman_Rand(min, max))
}

StudyHuman_Sleep(lowMs, highMs := "") {
    remaining := highMs = "" ? Integer(lowMs) : StudyHuman_RandI(lowMs, highMs)
    while (remaining > 0) {
        if !StudyHuman_Check()
            return false
        slice := Min(20, remaining)
        Sleep(slice)
        remaining -= slice
    }
    return StudyHuman_Check()
}

; Fast checks on every waypoint/key; full tab identity check at least every 300ms.
StudyHuman_Check() {
    global g_StudyMacroCancelled, g_StudyInputGuardAt, g_StudyInputTarget, g_StudyInputFailure
    if (g_StudyMacroCancelled || !g_StudySessOn || !WinActive("ahk_id " . g_StudyPin["hwnd"])) {
        g_StudyInputFailure := g_StudyMacroCancelled ? "ABORT requested" : !g_StudySessOn ? "session stopped" : "pinned Chrome lost foreground focus"
        StudyConsole_Log("ERROR", "input.guard.failed", g_StudyInputFailure, "ERROR")
        return false
    }
    if (IsObject(g_StudyInputTarget) && g_StudyInputTarget.Has("element")) {
        try {
            if !(g_StudyInputTarget["element"].State & 0x4) {
                g_StudyInputFailure := "keyboard focus left the intended control"
                return false
            }
        } catch
            return false
    }
    if (A_TickCount - g_StudyInputGuardAt >= 300) {
        allowed := StudyAuto_Guard()
        if !allowed
            g_StudyInputFailure := StudyAuto_CheckPin()["reason"]
        g_StudyInputGuardAt := A_TickCount
        return allowed
    }
    return true
}

StudyHuman_Load() {
    global g_StudyHuman
    limits := StudyHuman_Limits()
    for key, value in g_StudyHuman {
        saved := Study_GetSetting("human_" . key, String(value))
        if IsNumber(saved) {
            n := Number(saved)
            if !limits.Has(key) || (n >= limits[key][1] && n <= limits[key][2])
                g_StudyHuman[key] := n
        }
    }
}

StudyHuman_Limits() => Map("wpm", [5,250], "typoRate", [0,0.3], "hoverMs", [0,3000], "wobble", [0,3],
    "overshootPx", [0,30], "overshootRate", [0,1], "jitterPx", [0,8], "pauseRate", [0,0.5])

; QWERTY adjacency for plausible typos. Returns "" when unknown.
StudyHuman_Neighbor(ch) {
    static n := Map(
        "a","s","b","v","c","x","d","s","e","w","f","d","g","f","h","g",
        "i","o","j","h","k","j","l","k","m","n","n","b","o","p","p","o",
        "q","w","r","e","s","d","t","r","u","y","v","c","w","q","x","z",
        "y","t","z","x","1","2","2","1","3","2","4","3","5","4","6","5",
        "7","6","8","7","9","8","0","9"," "," ")
    ch := StrLower(ch)
    return n.Has(ch) ? n[ch] : ""
}

; Cubic bezier waypoint list from the current pointer position to (x, y).
StudyHuman_Path(sx, sy, ex, ey) {
    global g_StudyHuman
    dist := Sqrt((ex - sx) ** 2 + (ey - sy) ** 2)
    if (dist < 8)
        return [[ex, ey]]
    wob := g_StudyHuman["wobble"]
    rnd := (a, b) => StudyHuman_Rand(a, b)
    ; control points pulled off the straight line by up to 18% of the distance
    c1x := sx + (ex - sx) * 0.3 + rnd(-1.0, 1.0) * dist * 0.18 * wob
    c1y := sy + (ey - sy) * 0.3 + rnd(-1.0, 1.0) * dist * 0.18 * wob
    c2x := sx + (ex - sx) * 0.7 + rnd(-1.0, 1.0) * dist * 0.18 * wob
    c2y := sy + (ey - sy) * 0.7 + rnd(-1.0, 1.0) * dist * 0.18 * wob
    pts := []
    steps := Min(40, Max(8, Round(dist / 24)))
    Loop steps {
        t := A_Index / steps
        u := 1 - t
        px := u ** 3 * sx + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t ** 3 * ex
        py := u ** 3 * sy + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t ** 3 * ey
        pts.Push([Round(px), Round(py)])
    }
    pts.Push([ex, ey])
    return pts
}

; Move the pointer along a curved human path. Never teleports.
StudyHuman_MoveTo(x, y) {
    MouseGetPos(&sx, &sy)
    StudyConsole_Log("INPUT", "pointer.path", Map("from", [sx,sy], "to", [x,y], "wobble", g_StudyHuman["wobble"]))
    for , p in StudyHuman_Path(sx, sy, x, y) {
        if !StudyHuman_Check()
            return false
        MouseMove(p[1], p[2], 0)
        StudyConsole_Log("INPUT", "pointer.waypoint", Map("x", p[1], "y", p[2]))
        if !StudyHuman_Sleep(6, 18)
            return false
    }
    return true
}

; Click like a person: curved approach, hover, micro-jitter, press, settle.
StudyHuman_Click(x, y, button := "Left", count := 1, bounds := "", transition := false) {
    global g_StudyHuman, g_StudyInputFailure
    if (IsObject(bounds) && Random() < g_StudyHuman["overshootRate"]) {
        MouseGetPos(&sx, &sy)
        dist := Max(1, Sqrt((x-sx)**2 + (y-sy)**2))
        amount := g_StudyHuman["overshootPx"]
        ox := Round(x + (x-sx)/dist*amount), oy := Round(y + (y-sy)/dist*amount)
        StudyHuman_ClampPoint(&ox, &oy, bounds)
        StudyConsole_Log("INPUT", "pointer.overshoot", Map("x", ox, "y", oy, "return", [x,y], "maximum_px", amount))
        if !StudyHuman_MoveTo(ox, oy)
            return false
    }
    hover := StudyHuman_RandI(g_StudyHuman["hoverMs"] / 2, g_StudyHuman["hoverMs"])
    StudyConsole_Log("INPUT", "pointer.hover", Map("ms", hover, "target", IsObject(bounds) ? bounds["name"] : ""))
    if !StudyHuman_MoveTo(x, y) || !StudyHuman_Sleep(hover)
        return false
    jitter := Round(g_StudyHuman["jitterPx"])
    cx := x + Random(-jitter, jitter), cy := y + Random(-jitter, jitter)
    if IsObject(bounds)
        StudyHuman_ClampPoint(&cx, &cy, bounds)
    if !StudyHuman_Check()
        return false
    ; Re-read identity and bounds AFTER approach/hover, immediately before press.
    if IsObject(bounds) {
        live := StudyMacro_Relocate(bounds)
        if !IsObject(live) || live["x"] != bounds["x"] || live["y"] != bounds["y"]
         || live["w"] != bounds["w"] || live["h"] != bounds["h"] {
            g_StudyInputFailure := "control moved or disappeared during approach; capture again"
            return false
        }
        if !StudyMacro_HitTarget(live, cx, cy)
            return false
    }
    if !StudyAuto_Guard()
        return false
    if IsObject(bounds)
        DeepActivity_Target(Map("x",bounds["x"],"y",bounds["y"],"w",bounds["w"],"h",bounds["h"]),"Study input target",250)
    else
        DeepActivity_Target(Map("x",cx-15,"y",cy-15,"w",30,"h",30),"Study input target",250)
    if !StudyHuman_Check() || !StudyAuto_Guard()
        return false
    if IsObject(bounds) {
        current := StudyMacro_Relocate(bounds)
        if !IsObject(current) || current["x"] != bounds["x"] || current["y"] != bounds["y"]
         || current["w"] != bounds["w"] || current["h"] != bounds["h"] || !StudyMacro_HitTarget(current,cx,cy) {
            g_StudyInputFailure := "control changed during targeting feedback; capture again"
            return false
        }
    }
    StudyConsole_Log("INPUT", "mouse.press", Map("x", cx, "y", cy, "button", button, "count", count,
        "target", IsObject(bounds) ? bounds["name"] : "", "transition", transition))
    Click(cx, cy, button, count)
    if transition
        return !g_StudyMacroCancelled && g_StudySessOn && WinActive("ahk_id " . g_StudyPin["hwnd"])
    return StudyHuman_Sleep(60, 180)
}

StudyHuman_ClampPoint(&x, &y, bounds) {
    pad := Min(3, Max(0, (Min(bounds["w"], bounds["h"]) - 1) // 2))
    x := Max(bounds["x"] + pad, Min(bounds["x"] + bounds["w"] - 1 - pad, x))
    y := Max(bounds["y"] + pad, Min(bounds["y"] + bounds["h"] - 1 - pad, y))
}

StudyMacro_HitTarget(ctl, x, y) {
    global g_StudyInputFailure
    root := DllCall("GetAncestor", "Ptr", DllCall("WindowFromPoint", "Int64", (y << 32) | (x & 0xFFFFFFFF), "Ptr"), "UInt", 2, "Ptr")
    StudyAuto_Debug("Hit test " . ctl["name"] . " at " . x . "," . y . " root " . root . " expected " . g_StudyPin["hwnd"])
    if (root != g_StudyPin["hwnd"]) {
        g_StudyInputFailure := "another window covers the target"
        return false
    }
    try {
        hit := Acc.ElementFromPoint(x, y, false)
        ; Chromium may return the button's text child at its center. Resolve
        ; that child's actual control ancestor and require the same bounds.
        Loop 8 {
            StudyAuto_Debug("Hit accessible " . hit.Name . " role " . hit.RoleText)
            if (Trim(hit.Name) = Trim(ctl["name"]) && StudyPercept_Kind(hit.RoleText) = ctl["kind"]) {
                loc := hit.Location
                if (loc.x = ctl["x"] && loc.y = ctl["y"] && loc.w = ctl["w"] && loc.h = ctl["h"])
                    return true
            }
            hit := hit.Parent
        }
        g_StudyInputFailure := "hit-test identity differs from " . ctl["name"]
        return false
    } catch as err {
        g_StudyInputFailure := "target hit-test unavailable: " . err.Message
        return false
    }
}

; Type text character by character, occasionally fumbling a key and fixing it.
; Raw text via SendText so no character is ever interpreted as a hotkey.
StudyHuman_TypeText(text) {
    global g_StudyHuman
    if (text = "")
        return true
    DeepActivity_Before("text_type")
    for , ch in StrSplit(text) {
        if !StudyHuman_Check()
            return false
        if (Random(1, 10000) <= Integer(g_StudyHuman["typoRate"] * 10000)) {
            wrong := StudyHuman_Neighbor(ch)
            if (wrong != "") {
                SendText(wrong)
                StudyConsole_Log("INPUT", "key.typo", Map("literal", wrong, "intended", ch))
                if !StudyHuman_Sleep(40, 110)
                    return false
                Send("{Backspace}")
                StudyConsole_Log("INPUT", "key.correction", "Backspace")
                if !StudyHuman_Sleep(50, 130)
                    return false
            }
        }
        SendText(ch)
        delay := 60000 / (Max(5, g_StudyHuman["wpm"]) * 5)
        actualDelay := StudyHuman_RandI(delay * 0.55, delay * 1.45)
        StudyConsole_Log("INPUT", "key.literal", Map("text", ch, "wpm", g_StudyHuman["wpm"], "delay_ms", actualDelay))
        if !StudyHuman_Sleep(actualDelay)
            return false
        if (Random() < g_StudyHuman["pauseRate"] || ch ~= "[.!?,;:]")
            if !StudyHuman_Sleep(100, 350)
                return false
    }
    return true
}

; Clear whatever is already in a focused text field.
StudyHuman_ClearField() {
    DeepActivity_Before("key_send")
    if !StudyHuman_Check()
        return false
    Send("^a")
    StudyConsole_Log("INPUT", "key.command", "Ctrl+A")
    if !StudyHuman_Sleep(30, 70)
        return false
    Send("{Delete}")
    StudyConsole_Log("INPUT", "key.command", "Delete")
    return StudyHuman_Sleep(40, 90)
}

; Paste text via the clipboard (long answers), then give the app a beat.
StudyHuman_Paste(text) {
    saved := ClipboardAll()
    try {
        if !StudyHuman_Check()
            return false
        A_Clipboard := text
        if !ClipWait(1) || !StudyHuman_Sleep(50, 120)
            return false
        DeepActivity_Before("key_send")
        if !StudyHuman_Check()
            return false
        Send("^v")
        StudyConsole_Log("INPUT", "clipboard.paste", Map("text", text, "characters", StrLen(text)))
        return StudyHuman_Sleep(200, 300)
    } finally {
        ; Preserve a clipboard change the user made during entry.
        if (A_Clipboard = text)
            A_Clipboard := saved
    }
}

; ─────────────────────────────────────────────────────────────────────────────
; ANSWER PARSING
; ─────────────────────────────────────────────────────────────────────────────
; Normalize the proposed answer into per-target values.
; Returns Map(ok, note, letters[], values[]).
StudyMacro_ParseAnswer(q, answer) {
    out := Map("ok", true, "note", "", "letters", [], "values", [])
    answer := Trim(answer)
    ; strip a leading "ANSWER:" / "answer =" the LLM may have left in
    answer := RegExReplace(answer, "i)^\s*answer\s*[:=]\s*", "")
    answer := Trim(RegExReplace(answer, "[\r\n]+", " "))

    switch q["qtype"] {
        case "choicefill":
            chunks := StrSplit(answer, "||")
            choiceQ := q.Clone()
            choiceQ["qtype"] := "single"
            selected := StudyMacro_ParseAnswer(choiceQ, chunks[1])
            if !selected["ok"] || selected["letters"].Length != 1 {
                out["ok"] := false, out["note"] := "Use option || value, for example A || 10"
                return out
            }
            out["letters"] := selected["letters"]
            tag := selected["letters"][1], fields := []
            for , blank in q["blanks"] {
                if blank.Get("choiceTag", "") = "" {
                    out["ok"] := false, out["note"] := "An inline input has no unambiguous answer-choice association"
                    return out
                }
                if blank["choiceTag"] = tag
                    fields.Push(blank)
            }
            if chunks.Length - 1 != fields.Length {
                out["ok"] := false, out["note"] := "Provide exactly one || value for each input belonging to option " . tag
                return out
            }
            Loop fields.Length {
                value := StudyMacro_CleanValue(chunks[A_Index + 1])
                if value = "" {
                    out["ok"] := false, out["note"] := "Inline answer is empty"
                    return out
                }
                out["values"].Push(value)
            }
            out["fields"] := fields
        case "single", "yesno", "tf", "multi", "image":
            letters := []
            ; Read explicit answer tags at the start, never an article 'a' in prose.
            if RegExMatch(answer, "i)^(?:options?\s+|choices?\s+)?([A-P](?:\s*(?:[,/;+&]|and)\s*[A-P])*)(?:\s*[-:.)]\s*.*|\s*$)", &m) {
                pos := 1
                while (pos := RegExMatch(m[1], "i)[A-P]", &tagMatch, pos)) {
                    tag := StrUpper(tagMatch[0])
                    if !StudyMacro_Has(letters, tag)
                        letters.Push(tag)
                    pos++
                }
            } else if (q["qtype"] = "multi" && RegExMatch(answer, "i)^[A-P]{2,16}$")) {
                for , tag in StrSplit(StrUpper(answer))
                    if !StudyMacro_Has(letters, tag)
                        letters.Push(tag)
            }
            if (letters.Length = 0) {
                ; no letters - try matching the answer against the choice text
                ansNorm := Study_Normalize(answer)
                for i, c in q["choices"] {
                    cn := Study_Normalize(c["text"])
                    if (cn != "" && ansNorm != ""
                     && (ansNorm = cn || InStr(" " . ansNorm . " ", " " . cn . " "))) {
                        letters.Push(c["tag"])
                    }
                }
            }
            if (letters.Length = 0) {
                out["ok"] := false
                out["note"] := "No matching option in: " . StudyMacro_Clip(answer, 90)
                return out
            }
            out["letters"] := letters
            if (q["qtype"] != "multi" && letters.Length != 1) {
                out["ok"] := false
                out["note"] := "Single-select answer contains multiple options"
            }
            if (q["qtype"] = "multi" && letters.Length = 1
             && RegExMatch(q["raw"], "i)select all|all that apply|more than one"))
                out["note"] := "multi-select: only one option chosen"
        case "dropdown":
            ; a letter maps to that choice's text, otherwise use the answer text
            if RegExMatch(answer, "i)^\s*([A-P])\s*$", &m) && q["choices"].Length {
                c := StudyMacro_ChoiceByTag(q, m[1])
                if IsObject(c)
                    out["values"].Push(c["text"])
            }
            if (out["values"].Length = 0)
                out["values"].Push(StudyMacro_CleanValue(answer))
        case "fillblank":
            ; "value1 || value2 || ..." for multiple blanks
            parts := []
            for , p in StrSplit(answer, "||")
                parts.Push(StudyMacro_CleanValue(p))
            while (parts.Length && parts[parts.Length] = "")
                parts.Pop()
            if (parts.Length = 0)
                parts.Push(StudyMacro_CleanValue(answer))
            out["values"] := parts
        default:  ; shorttext / longtext / numeric / unknown
            out["values"].Push(answer)
    }
    if (out["values"].Length = 0 && out["letters"].Length = 0) {
        out["ok"] := false
        out["note"] := "Answer is empty"
    }
    return out
}

StudyMacro_CleanValue(v) {
    v := Trim(v)
    v := RegExReplace(v, "^[\x22\x27]+|[\x22\x27]+$", "")   ; strip quotes
    return v
}

StudyMacro_Has(arr, v) {
    for , x in arr
        if (x = v)
            return true
    return false
}

StudyMacro_Clip(s, n) {
    return StrLen(s) <= n ? s : SubStr(s, 1, n) . "..."
}

StudyMacro_ChoiceByTag(q, tag) {
    for , c in q["choices"]
        if (StrUpper(c["tag"]) = StrUpper(tag))
            return c
    return ""
}

; Transfer answer meaning only when the complete choice set is unchanged.
StudyMacro_RemapChoices(oldChoices, newChoices, answer, qtype) {
    out := Map("ok", false, "answer", "", "detail", "Choice set changed; verified answer requires review")
    if (oldChoices.Length != newChoices.Length || oldChoices.Length = 0)
        return out
    mapping := Map(), used := Map()
    for , old in oldChoices {
        matches := 0, mappedTag := ""
        key := StrLower(RegExReplace(Trim(old["text"]), "\s+", " "))
        for , current in newChoices
            if (key = StrLower(RegExReplace(Trim(current["text"]), "\s+", " ")))
                matches++, mappedTag := current["tag"]
        if (matches != 1 || key = "" || used.Has(mappedTag))
            return out
        mapping[old["tag"]] := mappedTag
        used[mappedTag] := true
    }
    oldQ := Map("qtype", qtype, "raw", "", "choices", oldChoices)
    parsed := StudyMacro_ParseAnswer(oldQ, answer)
    if !parsed["ok"] || !parsed["letters"].Length
        return out
    tags := []
    for , tag in parsed["letters"] {
        if !mapping.Has(tag)
            return out
        tags.Push(mapping[tag])
    }
    out["ok"] := true
    out["answer"] := StudyPercept_JoinTags(tags)
    out["detail"] := "Answer remapped by exact choice text after option order changed"
    return out
}

; ─────────────────────────────────────────────────────────────────────────────
; PLAN COMPOSITION  (self-composed workflow in engine vocabulary)
; ─────────────────────────────────────────────────────────────────────────────
; Compose the entry plan for one question. Returns
; Map(ok, steps, detail, parts). Steps are Maps(action, target, param, acc,
; verify, note) - engine-compatible action names.
StudyMacro_Compose(q, answer, mode) {
    global g_StudyMacroLastPlan
    out := Map("ok", false, "steps", [], "detail", "", "parts", Map())
    if (mode != "fill" && mode != "submit") {
        out["detail"] := "Observe/suggest mode does not create input plans"
        return out
    }
    if (Trim(answer) = "") {
        out["detail"] := "Answer is empty"
        return out
    }
    parts := StudyMacro_ParseAnswer(q, answer)
    out["parts"] := parts
    if !parts["ok"] {
        out["detail"] := parts["note"]
        return out
    }
    steps := []

    switch q["qtype"] {
        case "choicefill":
            choiceQ := q.Clone()
            choiceQ["qtype"] := "single"
            choicePlan := StudyMacro_Compose(choiceQ, parts["letters"][1], "fill")
            if !choicePlan["ok"] {
                out["detail"] := choicePlan["detail"]
                return out
            }
            for , step in choicePlan["steps"]
                steps.Push(step)
            if parts["fields"].Length {
                fieldQ := q.Clone()
                fieldQ["qtype"] := "fillblank"
                fieldQ["blanks"] := parts["fields"]
                fieldPlan := StudyMacro_Compose(fieldQ, StrReplace(StudyPercept_Join(parts["values"]), "`n", " || "), "fill")
                if !fieldPlan["ok"] {
                    out["detail"] := fieldPlan["detail"]
                    return out
                }
                for , step in fieldPlan["steps"]
                    steps.Push(step)
            }
        case "single", "yesno", "tf", "multi":
            for , tag in parts["letters"]
                if !IsObject(StudyMacro_ChoiceByTag(q, tag)) {
                    out["detail"] := "Option " . tag . " not present in the current question"
                    return out
                }
            ; Set the entire checkbox group, including removing old selections.
            for , c in q["choices"] {
                tag := c["tag"]
                wanted := StudyMacro_Has(parts["letters"], tag)
                if (q["qtype"] != "multi" && !wanted)
                    continue
                if (c.Has("fromOcr") && c["fromOcr"]) {
                    out["detail"] := "OCR-only option has no readable selected state; review required"
                    return out
                }
                if !IsObject(c) {
                    out["detail"] := "Option " . tag . " not present in the current question"
                    return out
                }
                step := StudyMacro_StepClick(q, c, tag)
                step["verify"] := Map("kind", "checked", "expect", wanted ? 1 : 0)
                step["ensureState"] := true
                steps.Push(step)
                if (q["qtype"] = "multi")
                    steps.Push(Map("action", "Wait", "target", "", "param", "140", "acc", "", "verify", "", "note", "pause between selections"))
            }
        case "dropdown":
            if (!IsObject(q["dropdown"]) || !parts["values"].Length) {
                out["detail"] := "Dropdown control not located - abstaining"
                return out
            }
            d := q["dropdown"]
            clickStep := StudyMacro_StepClick(q, Map("kind", "dropdown", "name", d["name"], "x", d["x"], "y", d["y"], "w", d["w"], "h", d["h"]), "")
            steps.Push(Map("action", "Choose Dropdown", "target", "", "param", parts["values"][1], "acc", clickStep["acc"],
                "verify", Map("kind", "dropdown-value", "expect", parts["values"][1]), "note", "select and verify dropdown " . d["name"]))
        case "fillblank", "shorttext", "longtext", "numeric":
            if (!q["blanks"].Length) {
                out["detail"] := "No text field located - abstaining (review)"
                return out
            }
            nBlanks := q["blanks"].Length
            values := parts["values"]
            if (values.Length != nBlanks) {
                out["detail"] := "Answer count must equal field count (use || between blanks)"
                return out
            }
            if (q["qtype"] = "fillblank" && values.Length < nBlanks) {
                ; pad missing values - a single value fills the first blank
                while (values.Length < nBlanks)
                    values.Push("")
            }
            longText := (q["qtype"] = "longtext") && g_StudyHuman["longtextPaste"]
            for i, b in q["blanks"] {
                if (b["protected"]) {
                    out["detail"] := "Field '" . b["name"] . "' looks like a password - refused"
                    return out
                }
                val := (i <= values.Length) ? values[i] : ""
                if (val = "" && q["qtype"] = "fillblank") {
                    out["detail"] := "No value for blank " . i . " - abstaining"
                    return out
                }
                steps.Push(StudyMacro_StepClick(q, Map("kind", "edit", "name", b["name"], "x", b["x"], "y", b["y"], "w", b["w"], "h", b["h"]), ""))
                acc := steps[steps.Length]["acc"]
                steps.Push(Map("action", "Send Keys", "target", "", "param", "^a", "acc", acc, "verify", "", "note", "select existing field text"))
                steps.Push(Map("action", "Wait", "target", "", "param", "90", "acc", "", "verify", "", "note", ""))
                if (longText)
                    steps.Push(Map("action", "Paste", "target", "", "param", val, "acc", acc, "verify", Map("kind", "field-value", "expect", val), "note", "paste the answer"))
                else
                    steps.Push(Map("action", "Type Text", "target", "", "param", val, "acc", acc, "verify", Map("kind", "field-value", "expect", val), "note", "type the answer"))
            }
        default:
            out["detail"] := "Question type '" . q["qtype"] . "' has no input plan (review)"
            return out
    }

    ; Submit step: mode must be submit AND the auto-submit setting must be on.
    if (mode = "submit" && Study_GetSetting("auto_submit", "0") = "1") {
        sub := StudyMacro_FindSubmit(q)
        if IsObject(sub) {
            steps.Push(Map("action", "Wait", "target", "", "param", "220", "acc", "", "verify", "", "note", "settle before submitting"))
            steps.Push(StudyMacro_StepClick(q, Map("kind", "button", "name", sub["name"], "x", sub["x"], "y", sub["y"], "w", sub["w"], "h", sub["h"]), ""))
            steps[steps.Length]["submit"] := true
            out["submitted"] := true
        } else {
            out["detail"] := "No Submit/Next control located - answer entered but not submitted"
        }
    }

    out["steps"] := steps
    out["ok"] := steps.Length > 0
    if (!out["ok"] && out["detail"] = "")
        out["detail"] := "Plan is empty"
    g_StudyMacroLastPlan := steps
    return out
}

; One click step carrying everything the executor needs for relocation + verify.
StudyMacro_StepClick(q, ctl, tag := "") {
    fromOcr := ctl.Has("fromOcr") && ctl["fromOcr"]
    ctlName := ctl.Has("name") ? ctl["name"]
             : ctl.Has("accName") ? ctl["accName"]
             : ctl.Has("text") ? ctl["text"] : ""
    step := Map("action", "Click", "target", ctl["x"] + ctl["w"] // 2 . "," . ctl["y"] + ctl["h"] // 2
              , "param", "", "acc", Map("kind", ctl.Has("kind") ? ctl["kind"] : "radio"
              , "name", ctlName, "fromOcr", fromOcr
              , "x", ctl["x"], "y", ctl["y"], "w", ctl["w"], "h", ctl["h"])
              , "verify", "", "note", "")
    if (ctl["kind"] = "radio" || ctl["kind"] = "checkbox") {
        ; OCR-only targets have no readable checked state - the click cannot be
        ; verified, so verification is skipped (and the click itself is guarded
        ; by relocation on a fresh OCR pass). Acc targets always verify.
        if (!fromOcr)
            step["verify"] := Map("kind", "checked", "expect", 1)
        step["note"] := (fromOcr ? "select (OCR target) " : "select option ") . tag
    } else if (ctl["kind"] = "button") {
        step["verify"] := ""
        step["note"] := "press " . ctl["name"]
    } else if (ctl["kind"] = "dropdown") {
        step["verify"] := ""
        step["note"] := "open dropdown " . ctl["name"]
    } else {
        step["note"] := "focus field " . ctl["name"]
    }
    return step
}

; Locate the submit/next control by name pattern.
StudyMacro_FindSubmit(q) {
    pat := "i)^(submit|submit answer|check answer|grade|turn in)$"
    for , b in q["buttons"] {
        if RegExMatch(Trim(b["name"]), pat)
            return b
    }
    return ""
}

; Human-readable preview of a composed plan.
StudyMacro_Preview(steps) {
    if (!steps.Length)
        return "(empty plan)"
    out := ""
    for i, s in steps {
        what := s["action"] . (s["note"] != "" ? "  -  " . s["note"] : "")
        if (s["param"] != "" && s["action"] != "Click")
            what .= "  [" . StudyMacro_Clip(s["param"], 40) . "]"
        out .= i . ". " . what . "`n"
    }
    return Trim(out, "`n")
}

; ─────────────────────────────────────────────────────────────────────────────
; EXECUTION (guard + relocate + human input + verify, every step)
; ─────────────────────────────────────────────────────────────────────────────
; Cached observation for monitors/tests. Relocation explicitly invalidates this
; cache before it reads bounds or values used for any input action.
StudyMacro_FreshControls() {
    global g_StudyWalkCache
    if (A_TickCount - g_StudyWalkCache["t"] < 450)
        return g_StudyWalkCache["controls"]
    g_StudyWalkCache := Map("t", A_TickCount, "controls", StudyPercept_Walk())
    return g_StudyWalkCache["controls"]
}

StudyMacro_InvalidateWalk() {
    global g_StudyWalkCache
    g_StudyWalkCache := Map("t", 0, "controls", [])
}

; Re-locate a control from the plan in the live accessibility tree.
; Returns a control Map with fresh bounds, or "".
StudyMacro_Relocate(acc) {
    StudyMacro_InvalidateWalk()
    ctrls := StudyMacro_FreshControls()
    best := "", matches := 0
    region := StudyAuto_Region()
    for , c in ctrls {
        if (c["kind"] != acc["kind"])
            continue
        if (StrLower(Trim(acc["name"])) != StrLower(Trim(c["name"])))
            continue
        if (c["w"] <= 0 || c["h"] <= 0 || (c.Has("protected") && c["protected"]))
            continue
        if c.Has("state") && (c["state"] & (0x1 | 0x8000 | 0x10000))
            continue
        if !StudyMacro_InRegion(c, region)
            continue
        matches++
        best := c
    }
    if (matches = 1) {
        StudyConsole_Log("IDENTIFY", "target.relocated", Map("name", best["name"], "kind", best["kind"],
            "bounds", [best["x"],best["y"],best["w"],best["h"]], "matches", matches))
        return best
    }
    StudyConsole_Log("IDENTIFY", "target.unresolved", Map("name", acc["name"], "kind", acc["kind"], "matches", matches), "WARN")
    return ""
}

StudyMacro_InRegion(c, r) {
    return c["x"] >= r["x"] && c["y"] >= r["y"]
        && c["x"] + c["w"] <= r["x"] + r["w"]
        && c["y"] + c["h"] <= r["y"] + r["h"]
}

; Read back a control's live state for step verification.
StudyMacro_Readback(acc, kind) {
    c := StudyMacro_Relocate(acc)
    if !IsObject(c) {
        StudyConsole_Log("VERIFY", "readback.missing", Map("name", acc["name"], "kind", kind), "WARN")
        return Map("ok", false, "detail", "control gone")
    }
    StudyConsole_Log("VERIFY", "readback", Map("name", c["name"], "kind", kind,
        "value", kind = "checked" ? c["checked"] : c["value"]))
    if (kind = "checked")
        return Map("ok", true, "value", c["checked"], "detail", "")
    if (kind = "field-value" || kind = "dropdown-value") {
        return Map("ok", true, "value", c["value"], "detail", "")
    }
    return Map("ok", true, "value", "", "detail", "")
}

StudyMacro_VerifyStep(s, q) {
    v := s["verify"]
    if (!IsObject(v) || !v.Has("kind"))
        return Map("ok", true, "detail", "no verification defined")
    if (s["acc"] = "")
        return Map("ok", false, "detail", "step has no control to verify")
    kind := v["kind"]
    if (kind = "field-value" || kind = "dropdown-value") {
        ; The cached walk predates our keystrokes - force a fresh read so the
        ; comparison sees the value the browser shows now.
        StudyMacro_InvalidateWalk()
    }
    ; give the browser a beat to update its accessibility state
    if (kind = "checked") {
        Loop 3 {
            rb := StudyMacro_Readback(s["acc"], "checked")
            if (rb["ok"] && rb["value"] = v["expect"])
                return Map("ok", true, "detail", "selected state verified = " . v["expect"])
            if !StudyHuman_Sleep(120, 220)
                return Map("ok", false, "detail", "cancelled during verification")
        }
        return Map("ok", false, "detail", "option did not end up selected")
    }
    expect := v["expect"]
    Loop 3 {
        rb := StudyMacro_Readback(s["acc"], "field-value")
        if !rb["ok"]
            return Map("ok", false, "detail", "field disappeared")
        got := rb["value"]
        if StudyMacro_ValueEqual(got, expect)
            return Map("ok", true, "detail", "exact value verified: " . StudyMacro_Clip(got, 80))
        if !StudyHuman_Sleep(140, 260)
            return Map("ok", false, "detail", "cancelled during verification")
    }
    return Map("ok", false, "detail", "field value mismatch (expected '" . StudyMacro_Clip(expect, 40) . "')")
}

StudyMacro_ValueEqual(got, expect) {
    return StrCompare(StrReplace(got, "`r`n", "`n"), StrReplace(expect, "`r`n", "`n"), true) = 0
}

; Execute one composed step.
StudyMacro_ExecStep(q, s, region) {
    global g_StudyHuman, g_StudyInputTarget, g_StudyInputFailure
    g_StudyInputTarget := ""
    g_StudyInputFailure := ""
    StudyConsole_Log("ACTION", "attempt", Map("action", s["action"], "target", IsObject(s["acc"]) ? s["acc"]["name"] : "",
        "param", s["param"], "note", s["note"]))
    switch s["action"] {
        case "Choose Dropdown":
            return StudyHuman_ChooseDropdown(q, s, region)
        case "Hover":
            target := StudyMacro_Relocate(s["acc"])
            if !IsObject(target)
                return false
            return StudyHuman_MoveTo(target["x"] + target["w"] // 2, target["y"] + target["h"] // 2)
                && StudyHuman_Sleep(Integer(s["param"]))
        case "Wait":
            return StudyHuman_Sleep(Integer(s["param"]))
        case "Click":
            target := ""
            if (s["acc"] != "" && IsObject(s["acc"])) {
                target := StudyMacro_Relocate(s["acc"])
                if (!IsObject(target))
                    return false
            } else
                return false
            if s.Has("submit") && s["submit"] {
                if (g_StudyMode != "submit" || Study_GetSetting("auto_submit", "0") != "1")
                    return false
            }
            if s.Has("ensureState") && s["ensureState"]
                if (target["checked"] = s["verify"]["expect"])
                    return true
            StudyMacro_InvalidateWalk()
            if !StudyHuman_Click(target["x"] + target["w"] // 2, target["y"] + target["h"] // 2, "Left", 1, target, s.Get("transition", false))
                return false
            vres := StudyMacro_VerifyStep(s, q)
            if (!vres["ok"] && vres["detail"] = "no verification defined")
                return true
            return vres["ok"]
        case "Send Keys":
            if (!s["param"] || s["param"] = "")
                return true
            if !StudyMacro_FocusTarget(s["acc"])
                return false
            if (s["param"] != "^a" && s["param"] != "{Enter}")
                return false
            if !StudyHuman_Check()
                return false
            Send(s["param"])
            StudyConsole_Log("INPUT", "key.command", s["param"])
            if !StudyHuman_Sleep(60, 100)
                return false
            return StudyMacro_VerifyStep(s, q)["ok"]
        case "Type Text":
            if !StudyMacro_FocusTarget(s["acc"]) || !StudyHuman_TypeText(s["param"])
                return false
            vres := StudyMacro_VerifyStep(s, q)
            return vres["ok"]
        case "Paste":
            if !StudyMacro_FocusTarget(s["acc"]) || !StudyHuman_Paste(s["param"])
                return false
            vres := StudyMacro_VerifyStep(s, q)
            return vres["ok"]
    }
    return false
}

StudyMacro_FocusTarget(acc) {
    global g_StudyInputTarget, g_StudyInputFailure
    if !IsObject(acc)
        return false
    c := StudyMacro_Relocate(acc)
    if !IsObject(c) {
        g_StudyInputFailure := "focused target is no longer discoverable"
        return false
    }
    StudyAuto_Debug("Focus target " . c["name"] . " state " . c["state"] . " focused " . c["focused"])
    if !c.Has("focused") || !c["focused"] {
        if (c["kind"] = "dropdown") {
            try {
                focusChild := c["element"].Focus
                if (focusChild.State & 0x4) {
                    c["element"] := focusChild
                    c["focusValue"] := focusChild.Name
                    g_StudyInputTarget := c
                    return StudyHuman_Check()
                }
            }
        }
        g_StudyInputFailure := "target did not retain keyboard focus"
        return false
    }
    g_StudyInputTarget := c
    if (c["kind"] = "dropdown")
        g_StudyInputTarget["focusValue"] := c["value"]
    return StudyHuman_Check()
}

; Native combo lists report focus on their selected item. Navigate that item
; with real keyboard keys, then commit and read back the combo's exact value.
; Typo correction is appropriate for edit fields, not option-selection keys.
StudyHuman_ChooseDropdown(q, s, region) {
    global g_StudyInputTarget, g_StudyInputFailure
    clickStep := s.Clone()
    clickStep["action"] := "Click"
    clickStep["verify"] := ""
    if !StudyMacro_ExecStep(q, clickStep, region) || !StudyMacro_FocusTarget(s["acc"])
        return false
    Send("{Home}")
    StudyConsole_Log("INPUT", "key.command", "Home (dropdown)")
    g_StudyInputTarget := ""
    if !StudyHuman_Sleep(50, 100)
        return false
    Loop 64 {
        if !StudyMacro_FocusTarget(s["acc"])
            return false
        current := g_StudyInputTarget["focusValue"]
        if StudyMacro_ValueEqual(current, s["param"]) {
            Send("{Enter}")
            StudyConsole_Log("INPUT", "key.command", "Enter (dropdown commit)")
            g_StudyInputTarget := ""
            if !StudyHuman_Sleep(80, 140)
                return false
            return StudyMacro_VerifyStep(s, q)["ok"]
        }
        if !StudyHuman_Check()
            return false
        Send("{Down}")
        StudyConsole_Log("INPUT", "key.command", "Down (dropdown)")
        g_StudyInputTarget := ""
        if !StudyHuman_Sleep(50, 100)
            return false
        if !StudyMacro_FocusTarget(s["acc"])
            return false
        if StudyMacro_ValueEqual(g_StudyInputTarget["focusValue"], current) {
            g_StudyInputFailure := "dropdown option not found: " . s["param"]
            return false
        }
    }
    g_StudyInputFailure := "dropdown exceeds 64 accessible options; review required"
    return false
}

; Run a composed plan against the pinned tab. Returns Map(ok, detail, done).
StudyMacro_Run(q, steps) {
    global g_StudyMacroRunning, g_StudyMacroCancelled, g_StudyInputTarget, g_StudyMacroTrace, g_StudyInputGuardAt
    if (g_StudyMacroRunning)
        return Map("ok", false, "detail", "another entry run is in progress", "done", 0)
    g_StudyMacroRunning := true
    g_StudyMacroCancelled := false
    g_StudyInputGuardAt := 0
    g_StudyMacroTrace := []
    StudyConsole_Log("ACTION", "workflow.start", Map("steps", steps.Length, "question", q["text"], "profile", g_StudyHuman))
    out := Map("ok", true, "detail", "", "done", 0)
    dpiContext := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try {
        if !StudyAuto_Guard() || !StudyMacro_QuestionCurrent(q)
            return Map("ok", false, "detail", "question changed or portal unavailable; capture again", "done", 0)
        region := StudyAuto_Region()
        baseSig := StudyAuto_FrameSig(region)
        finalChecks := Map()
        for , s in steps {
            if (g_StudyMacroCancelled || !StudyAuto_Guard()) {
                out["ok"] := false
                out["detail"] := "stopped: portal guard failed"
                break
            }
            ; The page visibly changed under us - stop before touching anything.
            if (ComparePixelSamples(baseSig, StudyAuto_FrameSig(region)) > 0.45) {
                out["ok"] := false
                out["detail"] := "stopped: page changed during entry"
                break
            }
            if s.Has("submit") && s["submit"] {
                if !StudyMacro_QuestionCurrent(q) {
                    out["ok"] := false, out["detail"] := "question changed before submission"
                    break
                }
                for , previous in finalChecks {
                    if !StudyMacro_VerifyStep(previous, q)["ok"] {
                        out["ok"] := false, out["detail"] := "answer changed before submission"
                        break
                    }
                }
                if !out["ok"]
                    break
            }
            ok := StudyMacro_ExecStep(q, s, region)
            trace := (ok ? "PASS " : "FAIL ") . s["action"] . " - " . s["note"]
            if IsObject(s["verify"]) && s["verify"].Has("kind")
                trace .= " (read-back " . s["verify"]["kind"] . " = " . StudyMacro_Clip(String(s["verify"]["expect"]), 80) . ")"
            g_StudyMacroTrace.Push(trace)
            StudyConsole_Log("ACTION", "result", Map("ok", ok, "trace", trace, "failure", g_StudyInputFailure))
            StudyLive_LogSafe(trace)
            if (!ok) {
                out["ok"] := false
                out["detail"] := "step failed: " . (s["note"] != "" ? s["note"] : s["action"])
                    . (g_StudyInputFailure != "" ? " - " . g_StudyInputFailure : " (focus, cancellation or read-back check)")
                break
            }
            if IsObject(s["verify"]) && IsObject(s["acc"])
                finalChecks[s["acc"]["kind"] . "|" . s["acc"]["name"]] := s
            out["done"]++
        }
    } catch as err {
        out["ok"] := false
        out["detail"] := "error: " . err.Message
        StudyConsole_Log("ERROR", "workflow.exception", Map("message", err.Message, "extra", err.Extra,
            "file", err.File, "line", err.Line, "stack", err.Stack), "ERROR")
        LogErrorToFile(err, "caught", "StudyMacro_Run")
    } finally {
        StudyConsole_Log("ACTION", "workflow.end", out)
        g_StudyMacroRunning := false
        g_StudyInputTarget := ""
        DllCall("SetThreadDpiAwarenessContext", "Ptr", dpiContext, "Ptr")
    }
    return out
}

StudyMacro_QuestionCurrent(q) {
    region := StudyAuto_Region()
    ocr := StudyPercept_OCR(region)
    if !ocr["ok"]
        return false
    fresh := StudyPercept_BuildQuestion(ocr, StudyPercept_Walk(), region, "")
    return StudyPercept_QFP(fresh) = StudyPercept_QFP(q)
}

; Abort any in-flight entry (checked during movement, typing and sliced waits).
StudyMacro_Abort() {
    global g_StudyMacroCancelled
    g_StudyMacroCancelled := true
    StudyLLM_CancelRequest()
}
