; ═══════════════════════════════════════════════════════════════════════════════
; StudyLive.ahk - the live portal half of the Real-Time Study Assistant
; ═══════════════════════════════════════════════════════════════════════════════
; This is the automation orchestrator that completes the study layer. It:
;
;   * watches the pinned Chrome portal tab (session loop + focus guard)
;   * perceives each new question through Acc/OCR/vision (StudyAutomation.ahk)
;   * stores it in the shared qa_item bank and asks the layered answer engine
;     Study_Answer() for the answer - so memory, local deduction and the
;     DeepSeek fallback (text or vision) are exactly what the study layer
;     implements, never a parallel copy
;   * rechecks the proposed answer against the LIVE controls, then asks
;     StudyMacro_Compose/Run to self-compose and execute a human-paced entry
;     plan made of the existing workflow action vocabulary
;   * observes portal feedback after a submission and records
;     portal-confirmed / disputed through the same versioned trail
;   * owns the "Live Portal" tab, the non-activating status overlay and the
;     hotkeys, and honors the mode ladder observe -> suggest -> fill -> submit
;     (submit additionally requires the auto-submit setting)
;
; Nothing here opens tabs, switches windows, or steals focus: the pinned tab is
; the only input target, re-verified before every action.
; ═══════════════════════════════════════════════════════════════════════════════

global g_StudyLiveLog  := []        ; rolling log lines (tab + overlay)
global g_StudyCurrent  := Map()     ; current question/answer/plan display
global g_StudyTabBuilt := false
global g_StudyUi       := Map()     ; tab control references

; ─────────────────────────────────────────────────────────────────────────────
; LOG + DISPLAY HELPERS
; ─────────────────────────────────────────────────────────────────────────────
StudyLive_Clip(s, n) {
    s := StrReplace(s, "`r", " ")
    s := StrReplace(s, "`n", " ")
    s := RegExReplace(s, "\s+", " ")
    s := Trim(s)
    return StrLen(s) <= n ? s : SubStr(s, 1, n) . "..."
}

; Append a timestamped line everywhere it belongs (log array, tab Edit, status
; bar, overlay). Tolerates being called before the tab exists.
StudyLive_LogSafe(msg) {
    global g_StudyLiveLog, g_StudyUi
    StudyConsole_Log("LIVE", "status", msg)
    line := FormatTime(A_Now, "HH:mm:ss") . "  " . msg
    g_StudyLiveLog.Push(line)
    while (g_StudyLiveLog.Length > 300)
        g_StudyLiveLog.RemoveAt(1)
    try {
        if (IsObject(g_StudyUi) && g_StudyUi.Has("log") && IsObject(g_StudyUi["log"])) {
            g_StudyUi["log"].Value := StudyLive_JoinLog()
            try PostMessage(0x115, 7, 0, g_StudyUi["log"].Hwnd)  ; WM_VSCROLL to bottom
        }
    }
    try ShowStatus(msg, "info")
    try StudyLive_UpdateOverlay()
    return line
}

StudyLive_JoinLog() {
    global g_StudyLiveLog
    out := ""
    start := Max(1, g_StudyLiveLog.Length - 120)
    Loop g_StudyLiveLog.Length - start + 1
        out .= g_StudyLiveLog[start + A_Index - 1] . "`n"
    return out
}

; ─────────────────────────────────────────────────────────────────────────────
; ANSWER BRIDGE - store the live question, reuse the study layer's engine
; ─────────────────────────────────────────────────────────────────────────────
; Persist the perceived question into the shared bank. Returns qaId (0 = fail).
StudyLive_StoreQuestion(q, imagePath) {
    if imagePath != "" && FileExist(imagePath)
        imagePath := Photo_Store(imagePath, "Study question")
    if !Qa_Schema()
        return 0
    kind := "mc"
    switch q["qtype"] {
        case "multi":     kind := "mc-multi"
        case "dropdown":  kind := "dropdown"
        case "fillblank": kind := "blank"
        case "choicefill": kind := "short"
        case "shorttext": kind := "short"
        case "longtext":  kind := "long"
        case "numeric":   kind := "numeric"
        case "image":     kind := "image"
        case "unknown":   kind := "unknown"
        default:          kind := "mc"
    }
    choices := []
    for , c in q["choices"]
        choices.Push(Map("tag", c["tag"], "text", c["text"]))
    item := Map("ordinal", "", "kind", kind, "label", "portal"
              , "question", (q["text"] != "" ? q["text"] : q["raw"])
              , "choices", choices, "blanks", q["blanks"].Length
              , "section", "portal")
    ; Live entry uses exact full stems, never the snip bank's fuzzy 120-char key.
    fingerprint := "portal|" . q["qtype"] . "|" . StrLower(RegExReplace(Trim(item["question"]), "\s+", " "))
    db := TrackDB()
    previous := db.QueryRow("SELECT * FROM qa_item WHERE fingerprint=?", fingerprint)
    choiceText := ""
    for , c in choices
        choiceText .= (choiceText = "" ? "" : "`n") . c["tag"] . "|" . c["text"]
    if previous.Count {
        id := previous["id"]
        if (previous["choices"] != choiceText && previous["answer"] != "") {
            remapped := q["qtype"] = "choicefill"
                ? Map("ok", false, "answer", "", "detail", "Choice/input association changed; re-evaluate the inline answer")
                : StudyMacro_RemapChoices(Qa_Choices(previous), choices, previous["answer"], q["qtype"])
            db.Run("UPDATE qa_item SET choices=?, source_image=? WHERE id=?", choiceText, imagePath, id)
            Study_RecordAnswer(id, remapped["answer"], remapped["ok"] ? previous["state"] : "candidate",
                "choice-remap", remapped["ok"] ? previous["confidence"] : 0, remapped["detail"])
        } else
            db.Run("UPDATE qa_item SET choices=?, source_image=? WHERE id=?", choiceText, imagePath, id)
        return id
    }
    db.Run("INSERT INTO qa_item(created_ts,snip_id,source_image,ordinal,kind,label,question,choices,blanks,section,fingerprint) "
        . "VALUES(?,?,?,?,?,?,?,?,?,?,?)", FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"), 0, imagePath, "", kind,
        "portal", item["question"], choiceText, item["blanks"], "portal", fingerprint)
    return db.Scalar("SELECT id FROM qa_item WHERE fingerprint=?", fingerprint)
}

; Recheck a proposed answer against the LIVE controls (spec section 4): the
; engine works on stored text, the live page is the ground truth for letters
; and values.
StudyLive_Recheck(q, answer) {
    if q["qtype"] = "choicefill" {
        parsed := StudyMacro_ParseAnswer(q, answer)
        return Map("ok", parsed["ok"], "answer", Trim(answer), "note", parsed["note"])
    }
    if (q["qtype"] = "single" || q["qtype"] = "multi" || q["qtype"] = "yesno" || q["qtype"] = "tf") {
        parsed := StudyMacro_ParseAnswer(q, answer)
        for , tag in parsed["letters"]
            if !IsObject(StudyMacro_ChoiceByTag(q, tag))
                return Map("ok", false, "answer", "", "note", "answer tag not in live choices")
        return Map("ok", parsed["ok"], "answer", StudyPercept_JoinTags(parsed["letters"]), "note", parsed["note"])
    }
    out := Map("ok", true, "answer", answer, "note", "")
    switch q["qtype"] {
        case "fillblank":
            out["answer"] := StudyLive_StripQuotes(answer)
        case "numeric":
            if RegExMatch(Trim(answer), "^[+-]?(?:\d+(?:[.,]\d+)?|\.\d+)(?:[eE][+-]?\d+)?(?:\s+[^\r\n]+)?$")
                out["answer"] := Trim(answer)
            else
                out["ok"] := false, out["note"] := "no numeric value in answer"
        default:
            out["answer"] := StudyLive_StripQuotes(answer)
    }
    return out
}

StudyLive_ValidTags(q) {
    v := ""
    for , c in q["choices"]
        v .= StrUpper(c["tag"])
    return v
}

StudyLive_StripQuotes(s) {
    return Trim(RegExReplace(Trim(s), "^[\x22\x27]+|[\x22\x27]+$", ""))
}

; The layered answer for a live question. The reasoning/memory/LLM work is
; Study_Answer() from the study layer; here we only bridge the live controls.
; Returns Map(answer, source, confidence, evidence, provider, model, cost,
; qaId, state, detail).
StudyLive_Answer(q, cap) {
    out := Map("answer", "", "source", "none", "confidence", 0, "evidence", ""
             , "provider", "", "model", "", "cost", 0, "qaId", 0
             , "state", "candidate", "detail", "")
    qaId := StudyLive_StoreQuestion(q, cap["imagePath"])
    out["qaId"] := qaId
    if q.Get("mathExpression", "") != "" {
        localMath := StudyMath_LocalAnswer(q)
        if localMath["ok"] {
            out["answer"] := localMath["answer"]
            out["source"] := "exact-math"
            out["confidence"] := 0.95
            out["evidence"] := localMath["evidence"]
            out["state"] := "candidate"
            out["detail"] := "Exact evaluation of the observed expression"
            if qaId
                Study_RecordAnswer(qaId, out["answer"], "candidate", "exact-math", 0.95, out["evidence"])
            return out
        }
    }
    if q["qtype"] = "choicefill" {
        prompt := q["text"] . "`nChoices:`n"
        for , choice in q["choices"]
            prompt .= choice["tag"] . ". " . choice["text"] . "`n"
        prompt .= "Inline fields:`n"
        for , blank in q["blanks"]
            prompt .= "Option " . blank.Get("choiceTag", "?") . ": " . blank["name"] . "`n"
        options := Map("maxTokens", 500, "purpose", "choice with inline math input",
            "system", "Answer the pictured problem. Return ONLY the selected option and each exact inline value separated by ||, for example A || 10. If the selected option has no input, return just its letter. Use the image for fractions and superscripts; if uncertain return REVIEW REQUIRED.")
        if cap.Get("imagePath", "") != "" && FileExist(cap["imagePath"])
            options["imagePath"] := cap["imagePath"]
        reply := StudyLLM_Ask(prompt, options)
        if reply["ok"] {
            check := StudyLive_Recheck(q, reply["answer"])
            if check["ok"] {
                out["answer"] := check["answer"], out["source"] := "deepseek"
                out["confidence"] := 0.7, out["model"] := reply["model"], out["cost"] := reply["costUSD"]
                out["detail"] := "Combined option/input proposal; review before entry"
            } else
                out["detail"] := check["note"]
        } else
            out["detail"] := reply["error"]
        return out
    }
    if (!qaId) {
        out["detail"] := "question could not be stored"
        return out
    }
    row := TrackDB().QueryRow("SELECT * FROM qa_item WHERE id=?", qaId)
    if (!row.Count) {
        out["detail"] := "stored question unreadable"
        return out
    }
    res := Study_Answer(row, true)      ; memory -> history -> local -> DeepSeek
    if (res["answer"] = "") {
        out["detail"] := res.Has("error") && res["error"] != "" ? res["error"] : "no answer produced"
        out["evidence"] := res.Has("evidence") ? res["evidence"] : ""
        return out
    }
    rc := StudyLive_Recheck(q, res["answer"])
    if (!rc["ok"]) {
        out["source"] := "unverifiable"
        out["detail"] := "model answer failed live recheck: " . rc["note"]
        out["evidence"] := res.Has("evidence") ? res["evidence"] : ""
        return out
    }
    out["answer"] := rc["answer"]
    out["source"] := res["source"]
    out["confidence"] := res["confidence"] + 0.0
    out["evidence"] := res.Has("evidence") ? res["evidence"] : ""
    out["provider"] := res.Has("provider") ? res["provider"] : ""
    out["model"] := res.Has("model") ? res["model"] : ""
    out["cost"] := res.Has("cost") ? res["cost"] + 0.0 : 0
    out["state"] := res["state"]
    out["detail"] := "layered answer via " . res["source"]
    ; Record the proposal in the versioned trail - EXCEPT a reused verified pair,
    ; which must keep its confirmed state untouched (spec section 6).
    if (res["source"] != "verified") {
        Study_RecordAnswer(qaId, out["answer"], out["state"], res["source"]
                         , out["confidence"], out["evidence"], out["provider"]
                         , out["model"], res["source"] = "deepseek" ? "no local evidence" : "", out["cost"])
    }
    return out
}

; ─────────────────────────────────────────────────────────────────────────────
; PORTAL FEEDBACK (after a submission)
; ─────────────────────────────────────────────────────────────────────────────
StudyLive_CheckFeedback() {
    global g_StudyPrevQ
    if (!g_StudyPrevQ.Count)
        return
    if (A_TickCount - g_StudyPrevQ["submittedAt"] > 20000) {
        StudyLive_LogSafe("Feedback was not attributable within 20 seconds; review the answer manually")
        g_StudyPrevQ := Map()
        return
    }
    if (g_StudyPin["hwnd"] != g_StudyPrevQ["hwnd"] || g_StudyPin["url"] != g_StudyPrevQ["url"])
        return
    region := g_StudyPrevQ.Has("region") ? g_StudyPrevQ["region"] : StudyAuto_Region()
    ocr := StudyPercept_OCR(region)
    if !ocr["ok"]
        return
    fresh := StudyPercept_BuildQuestion(ocr, StudyPercept_Walk(), region, "")
    if (StudyPercept_QFP(fresh) != g_StudyPrevQ["fp"]) {
        StudyLive_LogSafe("Question changed before feedback could be attributed; review manually")
        g_StudyPrevQ := Map()
        return
    }
    fb := StudyPercept_FeedbackFromOCR(ocr)
    if (fb["text"] = g_StudyPrevQ["baselineFeedback"])
        return
    if (fb["verdict"] = "unknown")
        return     ; keep waiting on later ticks
    qaId := g_StudyPrevQ["qaId"]
    answer := g_StudyPrevQ["answer"]
    if (fb["verdict"] = "correct") {
        Study_RecordAnswer(qaId, answer, "portal-confirmed", "portal-feedback"
                         , 0.95, fb["text"], "", "", "", 0)
        StudyLive_LogSafe("✓ Portal marked the answer CORRECT - pair learned")
    } else {
        Study_RecordAnswer(qaId, answer, "disputed", "portal-feedback"
                         , 0.1, fb["text"], "", "", "", 0)
        StudyLive_LogSafe("✗ Portal marked the answer INCORRECT - flagged for review")
    }
    g_StudyPrevQ := Map()
}

; ─────────────────────────────────────────────────────────────────────────────
; SESSION LOOP
; ─────────────────────────────────────────────────────────────────────────────
StudyLive_Tick() {
    global g_StudySessOn, g_StudySessBusy, g_StudyMode, g_StudyPrevQ
    global g_StudyLastQFP, g_StudyCurrent
    if (!g_StudySessOn || g_StudySessBusy || g_StudyChat["busy"] || g_StudyLLM_Busy || g_StudyToolBusy || g_StudyMacroRunning)
        return
    if !g_StudyPin["hwnd"] {
        StudyLive_TryPinWindow()
        if !g_StudyPin["hwnd"]
            return
    }
    g_StudySessBusy := true
    try {
        if (!StudyAuto_Guard())
            return

        ; feedback from a previous submission, once the page settles
        if (g_StudyPrevQ.Count && g_StudyPrevQ.Has("submittedAt")
         && A_TickCount - g_StudyPrevQ["submittedAt"] > Integer(Study_GetSetting("feedback_wait_ms", g_StudyFeedbackWaitMs)))
            StudyLive_CheckFeedback()

        if (!StudyAuto_RegionChanged())
            return

        capturedUrl := g_StudyPin["url"]
        capturedHwnd := g_StudyPin["hwnd"]
        cap := StudyPercept_Capture()
        if (!cap["ok"]) {
            StudyLive_LogSafe("Perception failed: " . cap["err"])
            return
        }
        q := cap["question"]
        if ((q["text"] = "" || q["raw"] = "") && !q["choices"].Length && !q["hasImage"]) {
            StudyPercept_Dispose(cap["imagePath"])
            return     ; empty / loading frame
        }
        fp := StudyPercept_QFP(q)
        if (fp = "" || fp = g_StudyLastQFP) {
            StudyPercept_Dispose(cap["imagePath"])
            return     ; same question as before
        }
        g_StudyLastQFP := fp

        StudyLive_LogSafe("Q[" . q["qtype"] . "]: " . StudyLive_Clip(q["text"] != "" ? q["text"] : "(image question)", 88))
        if (g_StudyMode = "observe" || q["qtype"] = "unknown" || q["portal"]["view"] = "assignment_overview" || q["portal"]["view"] = "answer_feedback") {
            ans := Map("answer", "", "source", "observation", "confidence", 0, "evidence", "",
                "model", "", "cost", 0, "detail", "Captured without calling the answer engine or API")
            g_StudyCurrent := Map("q", q, "a", ans, "plan", Map(), "at", A_TickCount)
            StudyLive_UpdateCurrentUI()
            StudyLive_LogSafe("Observed " . cap["controls"].Length . " controls; OCR " . (cap["ocr"]["ok"] ? "OK" : "failed"))
            StudyPercept_Dispose(cap["imagePath"])
            return
        }
        ans := StudyLive_Answer(q, cap)
        currentTab := StudyAuto_CheckPin()
        if !currentTab["ok"] || currentTab["url"] != capturedUrl || g_StudyPin["hwnd"] != capturedHwnd {
            StudyPercept_Dispose(cap["imagePath"])
            g_StudyLastQFP := ""
            StudyLive_LogSafe("Tab or focus changed while answering; waiting for the active page")
            return
        }
        if (!g_StudySessOn || g_StudyMacroCancelled) {
            StudyPercept_Dispose(cap["imagePath"])
            return
        }
        g_StudyCurrent := Map("q", q, "a", ans, "plan", Map(), "at", A_TickCount)
        StudyLive_UpdateCurrentUI()

        if (g_StudyMode = "observe") {
            StudyLive_LogSafe("Observed only (mode=observe)")
            StudyPercept_Dispose(cap["imagePath"])
            return
        }
        if (ans["answer"] = "") {
            StudyLive_LogSafe("No answer produced (" . ans["source"] . ": " . ans["detail"] . ")")
            StudyPercept_Dispose(cap["imagePath"])
            return
        }
        if (g_StudyMode = "suggest") {
            StudyLive_LogSafe("SUGGEST " . ans["answer"] . "  [" . ans["source"]
                            . ", " . Round(ans["confidence"] * 100) . "%]")
            StudyPercept_Dispose(cap["imagePath"])
            return
        }

        ; Confidence floor: below it, fill/submit abstains (spec section 4).
        confFloor := Study_GetSetting("confidence_threshold", "0.75") + 0.0
        if (ans["confidence"] < confFloor) {
            StudyLive_LogSafe("Below confidence floor (" . Round(ans["confidence"] * 100)
                            . "% < " . Round(confFloor * 100) . "%) - not entering the answer")
            StudyPercept_Dispose(cap["imagePath"])
            return
        }

        ; fill / submit: compose and run the human-paced entry plan
        plan := StudyMacro_Compose(q, ans["answer"], g_StudyMode)
        g_StudyCurrent["plan"] := plan
        StudyLive_UpdateCurrentUI()
        if (!plan["ok"]) {
            StudyLive_LogSafe("No entry plan: " . plan["detail"])
            StudyPercept_Dispose(cap["imagePath"])
            return
        }
        StudyLive_LogSafe("Plan: " . StrReplace(StudyMacro_Preview(plan["steps"]), "`n", "  |  "))
        res := StudyMacro_Run(q, plan["steps"])
        if (!res["ok"]) {
            StudyLive_LogSafe("⛔ ENTRY STOPPED SAFELY: " . res["detail"])
            ShowTooltipTimed("Live Portal: entry stopped - " . StudyLive_Clip(res["detail"], 60), 3000)
        } else {
            StudyLive_LogSafe("Entered " . res["done"] . " step(s) for " . ans["answer"])
            if (plan.Has("submitted") && plan["submitted"]) {
                g_StudyPrevQ := Map("qaId", ans["qaId"], "answer", ans["answer"]
                                  , "submittedAt", A_TickCount
                                  , "hwnd", g_StudyPin["hwnd"], "url", g_StudyPin["url"], "fp", fp
                                  , "baselineFeedback", StudyPercept_FeedbackFromOCR(cap["ocr"])["text"]
                                  , "region", Map("x", cap["region"]["x"], "y", cap["region"]["y"]
                                                , "w", cap["region"]["w"], "h", cap["region"]["h"]))
                StudyLive_LogSafe("Submitted - watching for portal feedback...")
            }
        }
        StudyPercept_Dispose(cap["imagePath"])
    } catch as err {
        LogErrorToFile(err, "caught", "StudyLive_Tick")
    } finally {
        g_StudySessBusy := false
    }
}

StudyLive_SetMode(mode) {
    global g_StudyMode, g_StudyUi
    valid := Map("observe", 1, "suggest", 1, "fill", 1, "submit", 1)
    if !valid.Has(mode)
        return false
    if (mode != g_StudyMode) {
        if g_StudySessOn
            StudyLive_Stop()
        else
            StudyMacro_Abort()
    }
    g_StudyMode := mode
    try g_StudyToolUi["mode"].Choose(mode)
    Study_SetSetting("mode", mode)
    try {
        if (IsObject(g_StudyUi) && g_StudyUi.Has("mode") && IsObject(g_StudyUi["mode"]))
            g_StudyUi["mode"].Choose(mode)
    }
    StudyLive_LogSafe("Mode: " . mode)
    return true
}

StudyLive_Start() {
    global g_StudySessOn, g_StudyPaused, g_StudyPollMs
    global g_StudyLastSig, g_StudyLastQFP, g_StudyPrevQ, g_StudyMacroCancelled
    if g_StudySessOn
        return true
    if (g_StudyMacroRunning || g_StudySessBusy || g_StudyToolBusy || g_StudyLLM_Busy) {
        StudyLive_LogSafe("Wait for the stopped operation to finish before restarting")
        return false
    }
    if !Study_Schema() {
        StudyLive_LogSafe("Study database unavailable - cannot start")
        return false
    }
    if !g_StudyPin["hwnd"]
        StudyLive_TryPinWindow()
    ; Arm the session WITHOUT requiring the pinned window to be foreground right
    ; now: clicking Start in this app necessarily takes focus off the game
    ; window, so a foreground check here always fails. Only reject a pin that is
    ; gone or minimized. The per-tick guard (StudyAuto_Guard) then makes the loop
    ; active whenever the pinned window is focused and pauses it the instant focus
    ; leaves - so "active while the window is focused" is the running behaviour.
    hwnd := g_StudyPin["hwnd"]
    if (hwnd && !WinExist("ahk_id " . hwnd))
        g_StudyPin["hwnd"] := 0, hwnd := 0
    mm := 0
    if hwnd
        try mm := WinGetMinMax("ahk_id " . hwnd)
    g_StudyPollMs := Integer(Study_GetSetting("poll_ms", "1200"))
    g_StudySessOn := true
    g_StudyMacroCancelled := false
    ; Start paused-until-focused. The first tick where the pinned window is the
    ; foreground window flips this to active via StudyAuto_Guard.
    g_StudyPaused := true
    g_StudyLastSig := ""
    g_StudyLastQFP := ""
    g_StudyPrevQ := Map()
    Study_SetSetting("sess_on", "1")
    SetTimer(StudyLive_Tick, g_StudyPollMs)
    StudyAuto_OverlayShow()
    StudyAuto_OverlayPaused(true)
    StudyLive_LogSafe("▶ Session armed (mode " . g_StudyMode . ", poll " . g_StudyPollMs
                    . "ms) - " . (hwnd ? "follows the last activated Chrome tab" : "waiting for Chrome to activate"))
    return true
}

StudyLive_Stop() {
    global g_StudySessOn, g_StudyToolBusy
    g_StudySessOn := false
    StudyMacro_Abort()
    g_StudyToolBusy := false
    SetTimer(StudyLive_Tick, 0)
    Study_SetSetting("sess_on", "0")
    StudyLive_LogSafe("■ Session stopped")
    StudyAuto_OverlayUpdate("Live Portal - stopped")
}

StudyLive_Abort() {
    StudyMacro_Abort()
    StudyLLM_CancelRequest()
    StudyLive_Stop()
    ShowTooltipTimed("Live Portal STOPPED", 1500)
}

StudyLive_ToggleSession() {
    global g_StudySessOn
    g_StudySessOn ? StudyLive_Stop() : StudyLive_Start()
}

StudyLive_HotPin() {
    res := StudyAuto_PinFromActive()
    if (res["ok"]) {
        StudyLive_LogSafe("Pinned: " . res["title"])
        ShowTooltipTimed("Live Portal pinned: " . res["title"], 2000)
    } else {
        ShowTooltipTimed("Pin failed: " . res["detail"], 2500)
    }
    StudyLive_UpdatePinnedUI()
}

; Start the portal and chat console on each launch. Startup uses observe or
; suggest; typing/submission modes are selected explicitly in the running app.
StudyLive_AutoStart() {
    try {
        StudyHuman_Load()
        mode := Study_GetSetting("mode", "suggest")
        if (mode != "observe" && mode != "suggest")
            mode := "suggest"
        StudyLive_SetMode(mode)
        StudyAuto_StartChromeTracking()
        StudyChat_Restore()
        if (Study_GetSetting("overlay_on", "0") = "1")
            StudyAuto_OverlayShow()
        ; Keep the audit stream running without opening a raw console on launch.
        StudyLive_Start()
    } catch as err {
        LogErrorToFile(err, "caught", "StudyLive_AutoStart")
    }
}

StudyLive_TryPinWindow() {
    StudyAuto_TrackChrome()
    return g_StudyPin["hwnd"] != 0
}

; ─────────────────────────────────────────────────────────────────────────────
; STATUS OVERLAY CONTENT
; ─────────────────────────────────────────────────────────────────────────────
StudyLive_UpdateOverlay() {
    global g_StudyCurrent, g_StudyMode, g_StudyPaused, g_StudySessOn, g_StudyLiveLog
    if (!g_StudySessOn && !g_StudyCurrent.Count)
        return
    txt := "Live Portal · " . g_StudyMode
    if (g_StudyPaused)
        txt .= " · PAUSED (focus/portal)"
    if (g_StudyCurrent.Has("q") && IsObject(g_StudyCurrent["q"])) {
        q := g_StudyCurrent["q"]
        txt .= "`nQ: " . StudyLive_Clip(q["text"] != "" ? q["text"] : "(image)", 64)
    }
    if (g_StudyCurrent.Has("a") && IsObject(g_StudyCurrent["a"])) {
        a := g_StudyCurrent["a"]
        if (a["answer"] != "")
            txt .= "`nA: " . StudyLive_Clip(a["answer"], 40)
                  . " · " . a["source"] . " · " . Round(a["confidence"] * 100) . "%"
        if (a["model"] != "")
            txt .= "`n" . a["model"] . " · $" . Round(a["cost"], 4)
    }
    if (g_StudyLiveLog.Length)
        txt .= "`n" . g_StudyLiveLog[g_StudyLiveLog.Length]
    StudyAuto_OverlayUpdate(txt)
}
; ─────────────────────────────────────────────────────────────────────────────
; ─────────────────────────────────────────────────────────────────────────────
; TAB UI (built into tab 19 by Tabs\Tab_19_PortalAssist.ahk)
; ─────────────────────────────────────────────────────────────────────────────
StudyLive_BuildTab(gui) {
    global g_StudyTabBuilt, g_StudyUi, g_StudyHuman
    if g_StudyTabBuilt
        return
    g_StudyTabBuilt := true

    ; ── Session ───────────────────────────────────────────────────────────
    gui.Add("GroupBox", "x8 y8 w430 h196", "Session & portal (Windows accessibility + OCR + vision only)")
    gui.Add("Button", "x20 y30 w170 h26", "Refresh Chrome Base").OnEvent("Click", (*) => StudyAuto_TrackChrome())
    g_StudyUi["pinned"] := gui.Add("Text", "x20 y62 w404 h56", "No window pinned")
    gui.Add("Text", "x20 y126 w60", "Mode:")
    g_StudyUi["mode"] := gui.Add("DropDownList", "x78 y122 w100", ["observe", "suggest", "fill", "submit"])
    g_StudyUi["mode"].Choose(g_StudyMode)
    g_StudyUi["mode"].OnEvent("Change", (c, *) => StudyLive_SetMode(c.Text))
    gui.Add("Text", "x190 y126 w52", "Poll ms:")
    g_StudyUi["poll"] := gui.Add("Edit", "x244 y122 w48")
    g_StudyUi["poll"].Value := Study_GetSetting("poll_ms", "1200")
    gui.Add("Button", "x20 y154 w84", "Start").OnEvent("Click", (*) => StudyLive_Start())
    gui.Add("Button", "x112 y154 w84", "Stop").OnEvent("Click", (*) => StudyLive_Stop())
    gui.Add("Button", "x204 y154 w104 cRed", "ABORT ALL").OnEvent("Click", (*) => StudyLive_Abort())
    gui.Add("Button", "x20 y186 w84", "Region: Window").OnEvent("Click", (*) => StudyLive_RegionWindow())
    gui.Add("Button", "x112 y186 w84", "Region: Drag").OnEvent("Click", (*) => StudyLive_RegionDrag())
    g_StudyUi["region"] := gui.Add("Text", "x204 y190 w220", StudyLive_RegionText())

    ; ── Answer engine ─────────────────────────────────────────────────────
    gui.Add("GroupBox", "x8 y212 w430 h118", "Answer engine (memory → material → DeepSeek)")
    gui.Add("Text", "x20 y234 w110", "Confidence floor:")
    g_StudyUi["conf"] := gui.Add("Edit", "x128 y230 w44")
    g_StudyUi["conf"].Value := Study_GetSetting("confidence_threshold", "0.75")
    gui.Add("Text", "x190 y234 w58", "Cost cap $:")
    g_StudyUi["cap"] := gui.Add("Edit", "x248 y230 w44")
    g_StudyUi["cap"].Value := Study_GetSetting("cost_cap_usd", "2.00")
    g_StudyUi["spend"] := gui.Add("Text", "x308 y234 w120", "Spent: $" . Round(g_StudyLLM_SpentUSD, 4))
    gui.Add("Button", "x20 y262 w90", "Probe API").OnEvent("Click", (*) => StudyLive_Probe())
    gui.Add("Button", "x118 y262 w90", "Save API Key").OnEvent("Click", (*) => StudyLive_SaveKey())
    gui.Add("Button", "x216 y262 w90", "Apply Engine").OnEvent("Click", (*) => StudyLive_ApplyEngine())
    g_StudyUi["llm"] := gui.Add("Text", "x20 y294 w404 h30", "LLM: " . (StudyLLM_HasKey() ? "key present (" . StudyLLM_KeySource() . ")" : "no API key set"))

    ; ── Human input ───────────────────────────────────────────────────────
    gui.Add("GroupBox", "x8 y338 w430 h118", "Human input simulation")
    gui.Add("Text", "x20 y360 w64", "Typo rate:")
    g_StudyUi["typo"] := gui.Add("Edit", "x86 y356 w44")
    g_StudyUi["typo"].Value := g_StudyHuman["typoRate"]
    gui.Add("Text", "x148 y360 w62", "Hover ms:")
    g_StudyUi["hover"] := gui.Add("Edit", "x210 y356 w44")
    g_StudyUi["hover"].Value := g_StudyHuman["hoverMs"]
    gui.Add("Text", "x272 y360 w50", "Wobble:")
    g_StudyUi["wobble"] := gui.Add("Edit", "x322 y356 w44")
    g_StudyUi["wobble"].Value := g_StudyHuman["wobble"]
    g_StudyUi["lpaste"] := gui.Add("CheckBox", "x20 y388 w150", "Paste long text")
    g_StudyUi["lpaste"].Value := g_StudyHuman["longtextPaste"] ? 1 : 0
    g_StudyUi["autosub"] := gui.Add("CheckBox", "x180 y388 w110", "Auto-submit")
    g_StudyUi["autosub"].Value := Study_GetSetting("auto_submit", "0") = "1" ? 1 : 0
    gui.Add("Text", "x20 y412 w260", "Live Portal starts automatically on launch")
    gui.Add("Button", "x330 y408 w96", "Apply Human").OnEvent("Click", (*) => StudyLive_ApplyHuman())

    ; ── Study bank quick links ────────────────────────────────────────────
    gui.Add("GroupBox", "x8 y464 w430 h118", "Study bank & reading (see Study Assistant tab)")
    g_StudyUi["stats"] := gui.Add("Text", "x20 y486 w404 h48", "")
    gui.Add("Button", "x20 y538 w110", "Refresh Stats").OnEvent("Click", (*) => StudyLive_RefreshStats())
    gui.Add("Button", "x138 y538 w110", "Import Lesson").OnEvent("Click", (*) => StudyLive_ImportClicked())
    gui.Add("Button", "x256 y538 w86", "Open Bank").OnEvent("Click", (*) => Qa_OpenBank())
    gui.Add("Button", "x20 y566 w110", "Read-along: Region").OnEvent("Click", (*) => Study_ReadAlong_PickRegion())
    gui.Add("Button", "x138 y566 w110", "Read-along: On/Off").OnEvent("Click", (*) => Study_ReadAlong_Toggle())
    gui.Add("Button", "x256 y566 w170", "Explain learning").OnEvent("Click",LearningLab_Open)

    ; ── Activity (right column) ───────────────────────────────────────────
    gui.Add("GroupBox", "x446 y8 w434 h170", "Current question / answer")
    g_StudyUi["cur"] := gui.Add("Edit", "x456 y28 w414 h132 ReadOnly Multi", "")
    gui.Add("GroupBox", "x446 y184 w434 h112", "Activity log")
    g_StudyUi["log"] := gui.Add("Edit", "x456 y204 w414 h76 ReadOnly Multi", "")
    gui.Add("GroupBox", "x446 y304 w434 h278", "Chat with DeepSeek")
    g_StudyUi["chatoutput"] := gui.Add("Edit", "x456 y326 w414 h110 ReadOnly Multi", "")
    g_StudyUi["chatstatus"] := gui.Add("Text", "x456 y442 w414 h28", StudyChat_StatusText())
    g_StudyUi["chatinput"] := gui.Add("Edit", "x456 y476 w414 h58 Multi WantReturn", "")
    g_StudyUi["chatsend"] := gui.Add("Button", "x456 y544 w130", "Send to DeepSeek")
    g_StudyUi["chatsend"].OnEvent("Click", (*) => StudyChat_Send(g_StudyUi["chatinput"]))
    gui.Add("Button", "x596 y544 w130", "Full Chat Window").OnEvent("Click", (*) => StudyChat_Open())
    g_StudyUi["chatcancel"] := gui.Add("Button", "x736 y544 w130", "Stop reply")
    g_StudyUi["chatcancel"].OnEvent("Click", (*) => StudyChat_Cancel())

    ; ── Footer row ────────────────────────────────────────────────────────
    g_StudyUi["overlay"] := gui.Add("CheckBox", "x8 y590 w110", "Show overlay")
    g_StudyUi["overlay"].Value := Study_GetSetting("overlay_on", "0") = "1" ? 1 : 0
    g_StudyUi["overlay"].OnEvent("Click", (c, *) => (Study_SetSetting("overlay_on", c.Value ? "1" : "0")
                                                   , c.Value ? StudyAuto_OverlayShow() : StudyAuto_OverlayHide()))
    g_StudyUi["keepframes"] := gui.Add("CheckBox", "x128 y590 w120", "Keep debug frames")
    g_StudyUi["keepframes"].Value := g_StudyKeepFrames ? 1 : 0
    g_StudyUi["keepframes"].OnEvent("Click", StudyLive_ToggleKeepFrames)
    gui.Add("Button", "x446 y586 w110", "Dry-run Fixtures").OnEvent("Click", (*) => StudyLive_SelfTest())
    gui.Add("Button", "x564 y586 w110", "Workflow Lab").OnEvent("Click", (*) => StudyTools_Open())
    gui.Add("Button", "x682 y586 w90", "Input Settings").OnEvent("Click", (*) => StudyHuman_OpenSettings())
    gui.Add("Button", "x780 y586 w90", "Quick Guide").OnEvent("Click", (*) => StudyLive_Guide())
    gui.Add("Text", "x8 y620 w860 h40", "Quick start: Workflow Lab > Practice Page > pin Chrome (Ctrl+Shift+U) > Capture > inspect OCR/controls > Preview > fill > Run. Ctrl+Shift+Esc aborts.")

    if (Study_GetSetting("overlay_on", "0") = "1")
        StudyAuto_OverlayShow()
    StudyLive_RefreshStats()
    StudyLive_UpdateCurrentUI()
    StudyLive_UpdatePinnedUI()
    StudyLive_LogSafe("Live Portal ready — follows the last activated Chrome tab automatically")
}

StudyLive_PinClicked() {
    windows := WinGetList("ahk_exe chrome.exe"), titles := []
    if !windows.Length {
        StudyLive_LogSafe("Open Chrome first, then pin the selected portal window")
        return
    }
    for , hwnd in windows
        titles.Push(WinGetTitle(hwnd))
    picker := Gui(, "Select Chrome Portal Window")
    picker.Add("Text", "w560", "Select the Chrome window showing the portal tab you want to capture and automate.")
    choices := picker.Add("DropDownList", "w560", titles)
    choices.Choose(1)
    picker.Add("Button", "w120 Default", "Pin Selected").OnEvent("Click", (*) => StudyLive_PinSelected(picker, windows, choices.Value))
    picker.Show()
}

StudyLive_PinSelected(picker, windows, index) {
    result := StudyAuto_Pin(windows[index])
    picker.Destroy()
    StudyLive_LogSafe(result["detail"])
    StudyLive_UpdatePinnedUI()
}

StudyLive_RegionWindow() {
    global g_StudyPin
    reg := StudyAuto_RegionFromWindow(g_StudyPin["hwnd"])
    if !IsObject(reg) {
        StudyLive_LogSafe("Cannot read the pinned window's client area")
        return
    }
    StudyAuto_RegionSet(reg, "window")
    StudyLive_LogSafe("Capture region = pinned window client area")
    StudyLive_UpdateRegionUI()
}

StudyLive_RegionDrag() {
    sel := ""
    try sel := QuickOCR_SelectRegion()
    if (!IsObject(sel) || !sel.Count) {
        ShowStatus("Region unchanged", "wait")
        return
    }
    if !StudyAuto_RegionSet(sel, "manual") {
        StudyLive_LogSafe("Drag a region entirely inside the pinned Chrome window")
        return
    }
    StudyLive_LogSafe("Capture region = dragged rectangle " . sel["w"] . "x" . sel["h"])
    StudyLive_UpdateRegionUI()
}

StudyLive_ApplyEngine() {
    global g_StudyUi, g_StudyPollMs, g_StudySessOn
    conf := g_StudyUi["conf"].Value
    if (!IsNumber(conf) || Number(conf) < 0 || Number(conf) > 1) {
        StudyLive_LogSafe("Confidence floor must be 0-1")
        return
    }
    Study_SetSetting("confidence_threshold", conf)
    cap := g_StudyUi["cap"].Value
    if (IsNumber(cap))
        Study_SetSetting("cost_cap_usd", cap)
    poll := Integer(g_StudyUi["poll"].Value)
    if (poll < 400)
        poll := 400
    Study_SetSetting("poll_ms", String(poll))
    g_StudyPollMs := poll
    if (g_StudySessOn)
        SetTimer(StudyLive_Tick, g_StudyPollMs)
    StudyLive_LogSafe("Engine settings applied (floor " . conf . ", cap $" . cap . ", poll " . poll . "ms)")
}

StudyLive_ApplyHuman() {
    global g_StudyUi, g_StudyHuman
    t := g_StudyUi["typo"].Value
    if (IsNumber(t) && Number(t) >= 0 && Number(t) <= 0.3)
        g_StudyHuman["typoRate"] := Number(t)
    h := g_StudyUi["hover"].Value
    if (IsInteger(h) && Integer(h) >= 0 && Integer(h) <= 3000)
        g_StudyHuman["hoverMs"] := Integer(h)
    w := g_StudyUi["wobble"].Value
    if (IsNumber(w) && Number(w) >= 0 && Number(w) <= 3)
        g_StudyHuman["wobble"] := Number(w)
    g_StudyHuman["longtextPaste"] := g_StudyUi["lpaste"].Value ? true : false
    for key, value in g_StudyHuman
        Study_SetSetting("human_" . key, String(value))
    Study_SetSetting("auto_submit", g_StudyUi["autosub"].Value ? "1" : "0")
    StudyLive_LogSafe("Human-input settings applied")
}

StudyLive_ToggleKeepFrames(c, *) {
    global g_StudyKeepFrames
    g_StudyKeepFrames := c.Value ? true : false
    StudyLive_LogSafe(g_StudyKeepFrames ? "Debug frames kept (temp folder)" : "Debug frames auto-deleted")
}

StudyLive_Probe() {
    global g_StudyUi
    res := StudyLLM_Probe()
    txt := res["ok"] ? "API reachable: " . res["detail"] : "API check failed: " . res["detail"]
    g_StudyUi["llm"].Value := "LLM: " . txt
    StudyLive_LogSafe(txt)
}

StudyLive_SaveKey() {
    global g_StudyUi
    ib := InputBox("Paste the DeepSeek API key. Stored in Windows Credential Manager (per-user, DPAPI-protected), never on disk.", "DeepSeek API key", "Password w420")
    if (ib.Result != "OK" || Trim(ib.Value) = "")
        return
    key := Trim(ib.Value)
    ib := ""
    if StudyLLM_SaveKey(key)
        g_StudyUi["llm"].Value := "LLM: key saved in Windows Credential Manager"
    else
        g_StudyUi["llm"].Value := "LLM: failed to save the key"
}

StudyLive_ImportClicked() {
    path := ""
    try path := FileSelect(1, , "Import lesson plan / notes", "Documents (*.pdf; *.md; *.txt; *.markdown)")
    if (path = "")
        return
    StudyLive_LogSafe("Importing " . path . " ... (OCR pages can take a while)")
    res := Study_ImportFile(path)
    StudyLive_LogSafe(res["ok"] ? "Imported: " . res["detail"] : "Import failed: " . res["detail"])
    StudyLive_RefreshStats()
}

StudyLive_RefreshStats() {
    global g_StudyUi, g_StudyReadAlongOn, g_StudyReadAlongPage
    if (!IsObject(g_StudyUi) || !g_StudyUi.Has("stats"))
        return
    srcs := 0
    try srcs := Study_Sources().Length
    g_StudyUi["stats"].Value := "Sources: " . srcs
        . " · Concepts: " . Study_ConceptCount()
        . " · Open questions: " . Qa_OpenCount()
        . "`nRead-along: " . (g_StudyReadAlongOn ? "ON (page " . g_StudyReadAlongPage . ")" : "off")
}

StudyLive_UpdatePinnedUI() {
    global g_StudyUi, g_StudyPin
    if (!IsObject(g_StudyUi) || !g_StudyUi.Has("pinned"))
        return
    if (g_StudyPin["hwnd"]) {
        g_StudyUi["pinned"].Value := "Chrome base: " . g_StudyPin["title"]
            . (g_StudyPin["origin"] != "" ? "`n" . g_StudyPin["origin"] : "`n(URL pending)")
    } else {
        g_StudyUi["pinned"].Value := "Activate a Chrome tab once — it becomes the learning base automatically"
    }
}

StudyLive_RegionText() {
    reg := StudyAuto_Region()
    return "Region: " . reg["x"] . "," . reg["y"] . " " . reg["w"] . "x" . reg["h"]
}

StudyLive_UpdateRegionUI() {
    global g_StudyUi
    if (IsObject(g_StudyUi) && g_StudyUi.Has("region"))
        g_StudyUi["region"].Value := StudyLive_RegionText()
}

StudyLive_UpdateCurrentUI() {
    global g_StudyUi, g_StudyCurrent
    if (!IsObject(g_StudyUi) || !g_StudyUi.Has("cur"))
        return
    if (!g_StudyCurrent.Has("q"))
        return
    q := g_StudyCurrent["q"], a := g_StudyCurrent["a"]
    txt := "TYPE: " . q["qtype"] . "   (source " . q["source"] . ", perception conf " . Round(q["conf"] * 100) . "%)`n"
    if q.Has("profile") {
        txt := "PAGE: " . q["profile"]["view"] . "`n" . txt
        for , area in q["profile"]["areas"]
            txt .= "  area: " . area . "`n"
    }
    txt .= "Q: " . StudyLive_Clip(q["text"] != "" ? q["text"] : "(image-based question)", 300) . "`n"
    for , c in q["choices"]
        txt .= "  " . c["tag"] . ". " . StudyLive_Clip(c["text"], 70) . "`n"
    if (q["blanks"].Length)
        txt .= "  fields: " . q["blanks"].Length . "`n"
    txt .= "A: " . (a["answer"] != "" ? a["answer"] : "(none)")
        . "   [" . a["source"] . " " . Round(a["confidence"] * 100) . "%]`n"
    if (a["evidence"] != "")
        txt .= "why: " . StudyLive_Clip(a["evidence"], 140) . "`n"
    if (a["model"] != "")
        txt .= "model: " . a["model"] . " $" . Round(a["cost"], 4) . "`n"
    if (a["detail"] != "")
        txt .= "note: " . a["detail"] . "`n"
    plan := g_StudyCurrent["plan"]
    if (IsObject(plan) && plan.Has("steps") && plan["steps"].Length)
        txt .= "plan: " . StrReplace(StudyMacro_Preview(plan["steps"]), "`n", " | ")
    if q.Has("controls") {
        txt .= "`nGathered " . q["controls"].Length . " accessible controls:`n"
        for , c in q["controls"]
            if !c["protected"]
                txt .= "  " . c["kind"] . " " . StudyLive_Clip(c["name"], 40) . " @ " . c["x"] . "," . c["y"] . "`n"
    }
    g_StudyUi["cur"].Value := txt
    StudyLive_UpdateOverlay()
}

; ─────────────────────────────────────────────────────────────────────────────
StudyLive_Guide() {
    MsgBox("1. Activate a Chrome practice page. The last activated tab becomes the learning base automatically.`n"
        . "2. Observe gathers only; suggest asks memory/material/DeepSeek without typing.`n"
        . "3. Workflow Lab: Capture in 3 sec, focus Chrome, inspect OCR + named controls.`n"
        . "4. Preview a manual tool, or enter a goal and Generate with DeepSeek. Review its commands.`n"
        . "5. Choose fill, Run in 3 sec, focus Chrome. Inspect PASS/FAIL exact read-back.`n"
        . "6. Input Settings controls WPM, typos, hover, curve, overshoot and click variation.`n"
        . "7. Submit needs submit mode + Auto-submit. Restart returns submit to suggest.`n"
        . "Ctrl+Shift+Y toggles the session; Ctrl+Shift+Esc aborts input and API receive.`n"
        . "Tab and window changes are followed automatically. Full Chat Window opens the conversation, progress and composer. OCR-only clicks require review.", "Live Portal Quick Guide")
}

; DRY-RUN FIXTURES (no mouse, no keys - classifier + planner only)
; ─────────────────────────────────────────────────────────────────────────────
; Local replay fixtures covering the question types in spec section 2. Each
; exercises the same classifier/composer code a live capture would, with
; synthetic OCR/controls, so the acceptance path can be checked without a
; live portal.
StudyLive_SelfTest() {
    fixtures := [
        Map("name", "single choice (Acc radios)",
            "lines", ["Question 1", "Which gas do plants absorb for photosynthesis?", "A. Oxygen", "B. Carbon dioxide", "C. Nitrogen", "D. Hydrogen"],
            "controls", [StudyLive_FixCtl("radio", "Oxygen", 100, 120), StudyLive_FixCtl("radio", "Carbon dioxide", 100, 150)
                        , StudyLive_FixCtl("radio", "Nitrogen", 100, 180), StudyLive_FixCtl("radio", "Hydrogen", 100, 210)],
            "answer", "B", "expect", "single"),
        Map("name", "true/false (Acc radios)",
            "lines", ["Question 2", "Water boils at 100°C at sea level.", "A. True", "B. False"],
            "controls", [StudyLive_FixCtl("radio", "True", 100, 120), StudyLive_FixCtl("radio", "False", 100, 150)],
            "answer", "A", "expect", "tf"),
        Map("name", "multi-select (Acc checkboxes)",
            "lines", ["Question 3", "Select all that apply:", "A. Apple", "B. Banana", "C. Carrot", "D. Date"],
            "controls", [StudyLive_FixCtl("checkbox", "Apple", 100, 120), StudyLive_FixCtl("checkbox", "Banana", 100, 150)
                        , StudyLive_FixCtl("checkbox", "Carrot", 100, 180), StudyLive_FixCtl("checkbox", "Date", 100, 210)],
            "answer", "A, C", "expect", "multi"),
        Map("name", "dropdown",
            "lines", ["Question 4", "Choose the capital of France:", "Paris"],
            "controls", [StudyLive_FixCtl("dropdown", "Capital", 100, 120)],
            "answer", "Paris", "expect", "dropdown"),
        Map("name", "fill in the blank (one edit)",
            "lines", ["Question 5", "The powerhouse of the cell is the _______.", "mitochondria"],
            "controls", [StudyLive_FixCtl("edit", "answer", 100, 120)],
            "answer", "mitochondria", "expect", "fillblank"),
        Map("name", "short text (one edit)",
            "lines", ["Question 6", "In one sentence, define osmosis."],
            "controls", [StudyLive_FixCtl("edit", "answer", 100, 120)],
            "answer", "Diffusion of water across a membrane", "expect", "shorttext"),
        Map("name", "numeric with units (one edit)",
            "lines", ["Question 7", "Convert 1.5 km to meters."],
            "controls", [StudyLive_FixCtl("edit", "answer", 100, 120)],
            "answer", "1500", "expect", "numeric"),
        Map("name", "OCR-only single choice (no a11y)",
            "lines", ["Question 8", "Which is the largest planet?", "A. Earth", "B. Jupiter", "C. Mars", "D. Venus"],
            "controls", [],
            "answer", "B", "expect", "single"),
        Map("name", "image-based (no readable text)",
            "lines", [],
            "controls", [],
            "answer", "", "expect", "image")
    ]
    StudyLive_LogSafe("── Dry-run fixtures ──")
    pass := 0, fail := 0
    for , fx in fixtures {
        ocr := Map("ok", true, "text", "", "lines", [], "words", [])
        for , t in fx["lines"] {
            ocr["lines"].Push(Map("text", t, "y", 60 + A_Index * 28, "x", 80, "w", 400, "h", 22))
            ocr["text"] .= (ocr["text"] = "" ? "" : "`n") . t
            for , wd in StrSplit(t, " ")
                ocr["words"].Push(Map("text", wd, "x", 80, "y", 60 + A_Index * 28, "w", 40, "h", 22))
        }
        q := StudyPercept_BuildQuestion(ocr, fx["controls"], Map("x", 0, "y", 0, "w", 800, "h", 600), "")
        gotType := q["qtype"]
        okType := (gotType = fx["expect"])
        plan := StudyMacro_Compose(q, fx["answer"], "fill")
        mustAbstain := fx["answer"] = "" || InStr(fx["name"], "OCR-only")
        okPlan := mustAbstain ? !plan["ok"] : plan["ok"]
        ok := okType && okPlan
        ok ? pass++ : fail++
        StudyLive_LogSafe((ok ? "PASS " : "FAIL ") . fx["name"]
            . "  → " . gotType . "  plan:" . (plan["ok"] ? StudyLive_Clip(StudyMacro_Preview(plan["steps"]), 70) : plan["detail"]))
    }
    StudyLive_LogSafe("── Fixtures: " . pass . " passed, " . fail . " failed ──")
}

StudyLive_FixCtl(kind, name, x, y) {
    return Map("kind", kind, "role", kind, "name", name, "value", "", "x", x, "y", y
             , "w", 16, "h", 16, "checked", false, "protected", false, "stText", "")
}
