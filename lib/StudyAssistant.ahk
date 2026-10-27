; ═══════════════════════════════════════════════════════════════════════════════
; StudyAssistant.ahk - Layered answer engine, verification, review, exports, UI
; ═══════════════════════════════════════════════════════════════════════════════
; The study half of fan\REALTIME_STUDY_ASSISTANT_SPEC.md, sections 4, 6 and 8:
;
;   * a layered answer engine that prefers local evidence and only falls back to
;     DeepSeek when the material does not cover a question (spec section 4)
;   * a verification / "learn once" workflow with a preserved evidence trail
;     (spec section 6)
;   * exportable study output - study guide, flashcards, missed-question list,
;     concept summary - and a spaced-review queue (spec section 6)
;   * the Study Assistant tab that ties it together (spec section 8)
;
; This module retrieves evidence and proposes answers. StudyLive and the
; guarded StudyComposer controller handle browser perception and answer entry.
; ═══════════════════════════════════════════════════════════════════════════════

global g_StudyCtl := Map()                ; tab control handles
global g_StudyQuestionRows := []          ; rows backing the question ListView
global g_StudySourceRows := []            ; rows backing the source ListView
global g_StudyCurrentQa := 0              ; qa_id currently shown in the engine
global g_StudyReviewGui := ""

; ═══════════════════════════════════════════════════════════════════════════════
; THE LAYERED ANSWER ENGINE (spec section 4)
; ═══════════════════════════════════════════════════════════════════════════════
; Search order, cheapest/most-trusted first:
;   1. a verified exact pair for this question          -> reuse, no API ("learn once")
;   2. a verified near-duplicate question                -> reuse, provisional
;   3. ingested passages + concept relationships         -> local deduction
;   4. DeepSeek fallback (only if allowed and keyed)     -> candidate
;   5. abstain                                           -> explicit review
;
; Returns Map: answer, source, confidence (0..1), evidence, provider, model,
; cost, state, error. Nothing here is auto-promoted to a fact: model and
; deduction results are candidates until the user (or clear source support)
; confirms them.
Study_Answer(qaRow, allowLLM := false) {
    out := Map("answer", "", "source", "none", "confidence", 0.0, "evidence", ""
             , "provider", "", "model", "", "cost", 0.0, "state", "candidate", "error", "")
    if !qaRow.Count {
        out["error"] := "No question"
        return out
    }
    qaId := qaRow["id"]
    question := qaRow["question"]
    StudyConsole_Log("LOOKUP", "answer.start", Map("id", qaId, "question", question, "llm_enabled", allowLLM))
    choices := Qa_Choices(qaRow)

    ; ── 1. verified exact pair (learn once) ─────────────────────────────────
    v := Study_VerifiedAnswer(qaId)
    StudyConsole_Log("LOOKUP", "verified.exact", v.Count ? v : Map("result", "no verified exact answer"))
    if v.Count {
        out["answer"] := v["answer"]
        out["source"] := "verified"
        out["confidence"] := v["confidence"] ? (v["confidence"] + 0.0) : 0.95
        out["evidence"] := "Reused a previously verified answer (no API call)."
        out["state"] := v["state"]
        return out
    }

    ; ── 2. verified near-duplicate question ─────────────────────────────────
    dup := Study_FindVerifiedSimilar(qaId, question, choices, qaRow["kind"])
    StudyConsole_Log("LOOKUP", "verified.similar", dup.Count ? dup : Map("result", "no compatible verified similar answer"))
    if dup.Count {
        out["answer"] := dup["answer"]
        out["source"] := "history"
        ; Materially different wording needs stronger evidence (spec section 6),
        ; so a near-dup match stays a lower-confidence candidate.
        out["confidence"] := 0.6
        out["evidence"] := 'Matches a verified question: "' . TrackEllipsis(dup["question"], 90) . '"'
        out["state"] := "candidate"
        return out
    }

    ; ── 3. local deduction over ingested material ───────────────────────────
    ret := Study_Retrieve(question . " " . Study_ChoiceText(choices))
    evidenceText := Study_EvidenceBlock(ret)
    if (choices.Length >= 2) {
        ded := Study_DeduceChoice(question, choices, ret)
        StudyConsole_Log("LOOKUP", "deduction.choice", ded)
        if (ded["confidence"] >= 0.45) {
            out["answer"] := ded["answer"]
            out["source"] := "deduction"
            out["confidence"] := ded["confidence"]
            out["evidence"] := ded["evidence"] . (evidenceText != "" ? "`n`n" . evidenceText : "")
            ; Strong, well-separated support reads as source-confirmed-able, but
            ; we still leave the final promotion to the user.
            out["state"] := "candidate"
            return out
        }
    } else {
        ded := Study_DeduceOpen(question, ret)
        StudyConsole_Log("LOOKUP", "deduction.open", ded)
        if (ded["confidence"] >= 0.5) {
            out["answer"] := ded["answer"]
            out["source"] := "deduction"
            out["confidence"] := ded["confidence"]
            out["evidence"] := ded["evidence"]
            out["state"] := "candidate"
            return out
        }
    }

    ; ── 4. DeepSeek fallback ────────────────────────────────────────────────
    if allowLLM {
        if !StudyLLM_HasKey() {
            out["error"] := "No local answer and no DeepSeek key configured"
            return out
        }
        prompt := Study_BuildPrompt(question, choices)
        opts := Map("context", evidenceText, "maxTokens", 700)
        ; Use the vision model when the source image matters (uncertain OCR,
        ; diagram/chart/table questions) - spec section 4/5.
        img := Study_QuestionImage(qaRow)
        if (img != "" && Study_QuestionNeedsVision(qaRow)) {
            opts["imagePath"] := img
        }
        res := StudyLLM_Ask(prompt, opts)
        if !res["ok"] {
            out["error"] := res["error"]
            return out
        }
        out["answer"] := res["answer"]
        out["source"] := "deepseek"
        out["provider"] := res["provider"]
        out["model"] := res["model"]
        out["cost"] := res["costUSD"]
        out["confidence"] := 0.5      ; a model answer is provisional by policy
        out["evidence"] := (evidenceText != "" ? "Grounding sent to the model:`n" . evidenceText . "`n`n" : "")
                         . "Model: " . res["model"] . "  (~" . res["promptTokens"] . "+"
                         . res["completionTokens"] . " tokens, est. $" . Round(res["costUSD"], 4) . ")"
        out["state"] := "candidate"
        return out
    }

    ; ── 5. abstain ──────────────────────────────────────────────────────────
    out["error"] := evidenceText != ""
        ? "Weak local support - enable DeepSeek or verify by hand"
        : "No local evidence found - enable DeepSeek or add study material"
    out["evidence"] := evidenceText
    return out
}

; Multiple-choice deduction: score each option by how well the retrieved
; material supports it; pick the best when it is clearly ahead. Handles simple
; negation ("not"/"except") by preferring the LEAST-supported option instead.
Study_DeduceChoice(question, choices, ret) {
    out := Map("answer", "", "confidence", 0.0, "evidence", "")
    ; Evidence units kept separate (one passage / concept each) so a choice is
    ; scored by the SINGLE piece of material that mentions it, not by the whole
    ; blob - otherwise any option named anywhere in the notes looks supported.
    units := []
    for , p in ret["passages"]
        units.Push(p["norm"])
    for , c in ret["concepts"]
        units.Push(Study_Normalize(c["name"] . " " . c["definition"]))
    if !units.Length
        return out

    ; The question's distinctive terms are what disambiguate the options: the
    ; right option is the one whose supporting passage also answers the stem.
    qkw := Study_Keywords(question)
    negated := RegExMatch(question, "i)\b(not|except|least|incorrect|false)\b") ? true : false
    best := 0, bestScore := -1, second := -1
    scores := []
    for i, c in choices {
        ckw := Study_Keywords(c["text"])
        if !ckw.Length
            ckw := [Study_Normalize(c["text"])]
        sc := 0
        for , u in units {
            mentions := false
            for , t in ckw {
                if (t != "" && InStr(u, t, true)) {
                    mentions := true
                    break
                }
            }
            if !mentions
                continue
            ; How well does the material that mentions this option match the
            ; question? Plus a little credit for naming the option strongly.
            s := (qkw.Length ? Study_ScoreText(u, qkw) : 0) + Study_ScoreText(u, ckw) * 0.25
            if (s > sc)
                sc := s
        }
        scores.Push(sc)
        if (sc > bestScore) {
            second := bestScore, bestScore := sc, best := i
        } else if (sc > second) {
            second := sc
        }
    }
    if negated {
        ; pick the lowest-scoring supported option
        lo := 0, loScore := 999999
        for i, sc in scores {
            if (sc < loScore) {
                loScore := sc, lo := i
            }
        }
        best := lo
    }
    if (!best || bestScore <= 0)
        return out
    margin := (bestScore - Max(second, 0))
    ; Confidence from both absolute support and separation from the runner-up.
    conf := Min(0.9, 0.35 + margin * 0.12 + bestScore * 0.03)
    if negated
        conf := Max(0.3, conf - 0.15)       ; negation is error-prone; hedge it
    out["answer"] := choices[best]["tag"] . ") " . choices[best]["text"]
    out["confidence"] := Round(conf, 2)
    out["evidence"] := (negated ? "Negated question - chose the least-supported option. " : "")
                     . "Chosen " . choices[best]["tag"] . " on material support "
                     . Round(bestScore, 1) . " vs next " . Round(Max(second, 0), 1) . "."
    return out
}

; Open/blank deduction: if a retrieved concept's name matches the question,
; offer its definition.
Study_DeduceOpen(question, ret) {
    out := Map("answer", "", "confidence", 0.0, "evidence", "")
    if !ret["concepts"].Length
        return out
    top := ret["concepts"][1]
    if (Trim(top["definition"]) = "")
        return out
    qn := Study_Normalize(question)
    cn := Study_Normalize(top["name"])
    ; Only when the concept name actually appears in the question.
    if (cn != "" && InStr(qn, cn)) {
        out["answer"] := top["definition"]
        out["confidence"] := Min(0.85, 0.5 + top["score"] * 0.05)
        src := Study_SourceTitle(top["source_id"])
        out["evidence"] := 'Definition of "' . top["name"] . '"'
                         . (src != "" ? " from " . src : "")
                         . (top["page"] ? " p." . top["page"] : "")
    }
    return out
}

Study_FindVerifiedSimilar(excludeId, question, choices := [], kind := "") {
    if !Study_Schema()
        return Map()
    kw := Study_Keywords(question, 8)
    if !kw.Length
        return Map()
    db := TrackDB()
    whereParts := [], params := []
    for , t in kw {
        whereParts.Push("question LIKE ?")
        params.Push("%" . t . "%")
    }
    params.Push(excludeId)
    sql := "SELECT id,question,answer,choices,kind FROM qa_item WHERE state IN ('user-confirmed','source-confirmed','portal-confirmed') "
         . "AND answer IS NOT NULL AND answer<>'' AND (" . Study_Join(whereParts, " OR ") . ") "
         . "AND id<>? LIMIT 200"
    best := Map(), bestScore := 0
    cands := []
    try cands := db.Query(sql, params*)
    for , r in cands {
        if (kind != "" && r["kind"] != kind)
            continue
        if (Study_QuestionQualifiers(question) != Study_QuestionQualifiers(r["question"]))
            continue
        if choices.Length {
            mapped := StudyMacro_RemapChoices(Qa_Choices(r), choices, r["answer"], "multi")
            if !mapped["ok"]
                continue
            r["answer"] := mapped["answer"]
        } else if Qa_Choices(r).Length
            continue
        sc := Study_ScoreText(Study_Normalize(r["question"]), kw)
        if (sc > bestScore) {
            bestScore := sc, best := r
        }
    }
    ; Require solid overlap before treating two questions as the same.
    return (bestScore >= kw.Length * 0.8) ? best : Map()
}

; Keyword overlap must never transfer a different quantity or negation.
Study_QuestionQualifiers(question) {
    out := "", pos := 1
    while (pos := RegExMatch(StrLower(question), "\b(?:not|except|least|most|incorrect|false|never|always|only|all|none)\b|[-+]?\d+(?:\.\d+)?", &m, pos)) {
        out .= m[0] . "|"
        pos += StrLen(m[0])
    }
    return out
}

Study_ChoiceText(choices) {
    out := ""
    for , c in choices
        out .= " " . c["text"]
    return out
}

Study_EvidenceCorpus(ret) {
    s := ""
    for , p in ret["passages"]
        s .= " " . p["norm"]
    for , c in ret["concepts"]
        s .= " " . Study_Normalize(c["name"] . " " . c["definition"])
    return Trim(s)
}

; Human-readable grounding block with citations.
Study_EvidenceBlock(ret) {
    lines := []
    for , c in ret["concepts"] {
        if (Trim(c["definition"]) = "")
            continue
        src := Study_SourceTitle(c["source_id"])
        lines.Push("- " . c["name"] . ": " . TrackEllipsis(c["definition"], 160)
                 . (src != "" ? "  [" . src . (c["page"] ? " p." . c["page"] : "") . "]" : ""))
    }
    for , p in ret["passages"] {
        src := Study_SourceTitle(p["source_id"])
        lines.Push("- " . TrackEllipsis(p["text"], 200)
                 . (src != "" ? "  [" . src . (p["page"] ? " p." . p["page"] : "") . "]" : ""))
    }
    out := ""
    for , l in lines
        out .= (out = "" ? "" : "`n") . l
    return out
}

Study_BuildPrompt(question, choices) {
    p := question
    if (choices.Length >= 2) {
        p .= "`n`nOptions:"
        for , c in choices
            p .= "`n" . c["tag"] . ") " . c["text"]
        p .= "`n`nGive the correct option letter(s) and a one-line reason."
    }
    return p
}

Study_BuildPromptRow(row) => Study_BuildPrompt(row["question"], Qa_Choices(row))

; The source snip image for a question, if one is on disk.
Study_QuestionImage(row) {
    p := row.Has("source_image") ? row["source_image"] : ""
    return Photo_Path(p)
}

; Should this question go to the vision model? When it mentions a figure, or its
; OCR text is short/garbled relative to having an image (uncertain OCR).
Study_QuestionNeedsVision(row) {
    q := row["question"]
    if RegExMatch(q, "i)\b(figure|diagram|chart|graph|image|picture|table|shown|above|below|map)\b")
        return true
    ; very short stem but we do have a source image -> OCR probably missed content
    if (StrLen(Trim(q)) < 25)
        return true
    return false
}

; ═══════════════════════════════════════════════════════════════════════════════
; SPACED REVIEW (SM-2 lite)
; ═══════════════════════════════════════════════════════════════════════════════
Study_ReviewEnqueue(qaId) {
    if (!qaId || !Study_Schema())
        return
    now := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    TrackDB().Run("INSERT INTO study_review(qa_id,ease,interval_days,reps,due_ts,last_ts) "
        . "VALUES(?,?,?,?,?,?) ON CONFLICT(qa_id) DO NOTHING"
        , qaId, 2.5, 0, 0, now, now)
}

; Enqueue every answered question that is not already scheduled.
Study_ReviewBuildQueue() {
    if !Study_Schema()
        return 0
    db := TrackDB()
    rows := db.Query("SELECT id FROM qa_item WHERE archived=0 AND answer IS NOT NULL AND answer<>''")
    n := 0
    for , r in rows {
        Study_ReviewEnqueue(r["id"])
        n++
    }
    return n
}

; Grade a review (0..5). SM-2 interval update; a grade < 3 resets the interval.
Study_ReviewGrade(qaId, grade) {
    if (!qaId || !Study_Schema())
        return
    db := TrackDB()
    row := db.QueryRow("SELECT * FROM study_review WHERE qa_id=?", qaId)
    ease := row.Count ? (row["ease"] + 0.0) : 2.5
    interval := row.Count ? Integer(row["interval_days"]) : 0
    reps := row.Count ? Integer(row["reps"]) : 0
    if (grade < 3) {
        reps := 0
        interval := 1
    } else {
        reps++
        interval := (reps = 1) ? 1 : (reps = 2) ? 6 : Round(interval * ease)
        if (interval < 1)
            interval := 1
    }
    ease := ease + (0.1 - (5 - grade) * (0.08 + (5 - grade) * 0.02))
    if (ease < 1.3)
        ease := 1.3
    now := A_Now
    due := DateAdd(now, interval, "Days")
    nowS := FormatTime(now, "yyyy-MM-dd HH:mm:ss")
    dueS := FormatTime(due, "yyyy-MM-dd HH:mm:ss")
    db.Run("INSERT INTO study_review(qa_id,ease,interval_days,reps,due_ts,last_ts,last_grade) "
        . "VALUES(?,?,?,?,?,?,?) ON CONFLICT(qa_id) DO UPDATE SET "
        . "ease=excluded.ease, interval_days=excluded.interval_days, reps=excluded.reps, "
        . "due_ts=excluded.due_ts, last_ts=excluded.last_ts, last_grade=excluded.last_grade"
        , qaId, ease, interval, reps, dueS, nowS, grade)
}

Study_ReviewDueCount() {
    if !Study_Schema()
        return 0
    now := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    v := TrackDB().Scalar("SELECT COUNT(*) FROM study_review WHERE due_ts<=?", now)
    return IsInteger(v) ? Integer(v) : 0
}

Study_ReviewNext() {
    if !Study_Schema()
        return Map()
    now := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    return TrackDB().QueryRow("SELECT q.* FROM study_review r JOIN qa_item q ON q.id=r.qa_id "
        . "WHERE r.due_ts<=? AND q.archived=0 ORDER BY r.due_ts ASC LIMIT 1", now)
}

; ═══════════════════════════════════════════════════════════════════════════════
; EXPORTS (spec section 6)
; ═══════════════════════════════════════════════════════════════════════════════
Study_ExportGuide() {
    global DATA_DIR
    if !Study_Schema()
        return ""
    db := TrackDB()
    md := "# Study Guide`r`n`r`nGenerated " . FormatTime(A_Now, "yyyy-MM-dd HH:mm") . "`r`n`r`n"
    md .= "## Key concepts`r`n`r`n"
    for , c in db.Query("SELECT * FROM study_concept ORDER BY importance DESC, seen DESC LIMIT 300") {
        src := Study_SourceTitle(c["source_id"])
        md .= "- **" . c["name"] . "**"
        if (Trim(c["definition"]) != "")
            md .= " - " . c["definition"]
        if (src != "")
            md .= "  _(" . src . (c["page"] ? ", p." . c["page"] : "") . ")_"
        md .= "`r`n"
    }
    md .= "`r`n## Answered questions`r`n`r`n"
    for , q in db.Query("SELECT * FROM qa_item WHERE archived=0 AND answer IS NOT NULL AND answer<>'' ORDER BY id") {
        md .= "**Q:** " . q["question"] . "`r`n`r`n"
        md .= "**A:** " . q["answer"] . "  `r`n"
        md .= "_state: " . Study_StateLabel(q) . "_`r`n`r`n"
    }
    path := DATA_DIR . "\study_guide_" . FormatTime(A_Now, "yyyyMMdd_HHmmss") . ".md"
    Track_WriteFile(path, md)
    return path
}

; Anki-importable flashcards: tab-separated front<TAB>back, one per line.
Study_ExportFlashcards() {
    global DATA_DIR
    if !Study_Schema()
        return ""
    db := TrackDB()
    out := ""
    for , q in db.Query("SELECT * FROM qa_item WHERE archived=0 AND answer IS NOT NULL AND answer<>''") {
        front := Study_CardEscape(q["question"])
        back := Study_CardEscape(q["answer"])
        out .= front . "`t" . back . "`r`n"
    }
    for , c in db.Query("SELECT * FROM study_concept WHERE definition<>'' ORDER BY importance DESC LIMIT 500") {
        out .= Study_CardEscape(c["name"]) . "`t" . Study_CardEscape(c["definition"]) . "`r`n"
    }
    path := DATA_DIR . "\study_flashcards_" . FormatTime(A_Now, "yyyyMMdd_HHmmss") . ".txt"
    Track_WriteFile(path, out)
    return path
}

Study_ExportMissed() {
    global DATA_DIR
    if !Study_Schema()
        return ""
    db := TrackDB()
    md := "# Missed / disputed questions`r`n`r`nGenerated " . FormatTime(A_Now, "yyyy-MM-dd HH:mm") . "`r`n`r`n"
    rows := db.Query("SELECT * FROM qa_item WHERE state IN ('rejected','disputed') ORDER BY id DESC")
    if !rows.Length
        md .= "_Nothing marked wrong yet._`r`n"
    for , q in rows {
        md .= "- **Q:** " . q["question"] . "`r`n"
        md .= "  - recorded answer: " . (q["answer"] != "" ? q["answer"] : "(none)") . "`r`n"
        md .= "  - state: " . Study_StateLabel(q) . "`r`n"
    }
    path := DATA_DIR . "\study_missed_" . FormatTime(A_Now, "yyyyMMdd_HHmmss") . ".md"
    Track_WriteFile(path, md)
    return path
}

Study_ExportConcepts() {
    global DATA_DIR
    if !Study_Schema()
        return ""
    db := TrackDB()
    md := "# Concept summary`r`n`r`n"
    for , c in db.Query("SELECT * FROM study_concept ORDER BY importance DESC, seen DESC LIMIT 500") {
        md .= "## " . c["name"] . "  (seen " . c["seen"] . "x)`r`n"
        if (Trim(c["definition"]) != "")
            md .= c["definition"] . "`r`n"
        rel := Study_RelatedConcepts(c["id"], 6)
        if rel.Length {
            md .= "_related:_ "
            names := []
            for , r in rel
                names.Push(r["name"])
            md .= Study_Join(names, ", ") . "`r`n"
        }
        md .= "`r`n"
    }
    path := DATA_DIR . "\study_concepts_" . FormatTime(A_Now, "yyyyMMdd_HHmmss") . ".md"
    Track_WriteFile(path, md)
    return path
}

Study_CardEscape(s) {
    s := StrReplace(s, "`r`n", " ")
    s := StrReplace(s, "`n", " ")
    s := StrReplace(s, "`t", " ")
    return Trim(s)
}

Study_StateLabel(row) {
    s := row.Has("state") ? row["state"] : ""
    return s != "" ? s : "candidate"
}

; ═══════════════════════════════════════════════════════════════════════════════
; LIFECYCLE
; ═══════════════════════════════════════════════════════════════════════════════
Study_Init() {
    global g_StudyLLM_SpentUSD
    if !Study_Schema()
        return
    try Study_ReadAlong_RestoreState()
    g_StudyLLM_SpentUSD := 0.0      ; reset the per-session cost counter
}

Study_OnExit(*) {
    try {
        if g_StudyReadAlongOn
            Study_SetSetting("readalong_on", "1")
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; TAB UI
; ═══════════════════════════════════════════════════════════════════════════════
Study_BuildTab(guiObj) {
    global g_StudyCtl
    g_StudyCtl := Map()

    ; ── provider row ────────────────────────────────────────────────────────
    guiObj.Add("GroupBox", "x15 y46 w860 h70", "DeepSeek provider  (key lives in Windows Credential Manager, never in a file)")
    g_StudyCtl["probe"]  := guiObj.Add("Button", "x28 y68 w100 h24", "Test / probe")
    g_StudyCtl["savekey"]:= guiObj.Add("Button", "x134 y68 w120 h24", "Save API key...")
    g_StudyCtl["forget"] := guiObj.Add("Button", "x260 y68 w100 h24", "Forget key")
    guiObj.Add("Text", "x372 y72 w70", "Cost cap $:")
    g_StudyCtl["costcap"]:= guiObj.Add("Edit", "x442 y68 w60 h24", Study_GetSetting("cost_cap_usd", "2.00"))
    g_StudyCtl["savecap"]:= guiObj.Add("Button", "x506 y68 w60 h24", "Set")
    g_StudyCtl["provstat"]:= guiObj.Add("Text", "x576 y72 w290 h20 cGray", "")

    ; ── material ──────────────────────────────────────────────────────────
    guiObj.Add("GroupBox", "x15 y122 w860 h250", "Study material")
    g_StudyCtl["sources"] := guiObj.Add("ListView", "x28 y144 w600 h200 Grid -Multi"
        , ["Title", "Kind", "Course/Topic", "Passages", "Pages", "Excl"])
    for col, w in [220, 70, 150, 70, 50, 40]
        g_StudyCtl["sources"].ModifyCol(col, w)
    g_StudyCtl["impFile"] := guiObj.Add("Button", "x636 y144 w230 h26", "Import file (txt / md)...")
    g_StudyCtl["impPdf"]  := guiObj.Add("Button", "x636 y174 w230 h26", "Import PDF (OCR)...")
    g_StudyCtl["impNote"] := guiObj.Add("Button", "x636 y204 w230 h26", "Paste notes...")
    g_StudyCtl["srcExcl"] := guiObj.Add("Button", "x636 y240 w112 h26", "Exclude / include")
    g_StudyCtl["srcDel"]  := guiObj.Add("Button", "x754 y240 w112 h26", "Delete source")
    g_StudyCtl["raPick"]  := guiObj.Add("Button", "x636 y284 w112 h26", "Read-along region")
    g_StudyCtl["raToggle"]:= guiObj.Add("Button", "x754 y284 w112 h26", "Start read-along")
    g_StudyCtl["matStat"] := guiObj.Add("Text", "x636 y316 w230 h50 cGray", "")

    ; ── answer engine ───────────────────────────────────────────────────────
    guiObj.Add("GroupBox", "x15 y378 w860 h316", "Answer engine  (produces study answers for you to verify - nothing is entered anywhere)")
    g_StudyCtl["questions"] := guiObj.Add("ListView", "x28 y400 w430 h210 Grid -Multi"
        , ["Kind", "Question", "State", "id"])
    g_StudyCtl["questions"].ModifyCol(1, 46)
    g_StudyCtl["questions"].ModifyCol(2, 260)
    g_StudyCtl["questions"].ModifyCol(3, 92)
    g_StudyCtl["questions"].ModifyCol(4, 0)
    g_StudyCtl["qFilter"] := guiObj.Add("DropDownList", "x28 y616 w140 Choose1"
        , ["Unanswered", "All open", "Answered", "Disputed/rejected"])
    g_StudyCtl["qRefresh"] := guiObj.Add("Button", "x174 y614 w90 h24", "Refresh")
    g_StudyCtl["review"]  := guiObj.Add("Button", "x270 y614 w90 h24", "Review due")
    g_StudyCtl["buildQ"]  := guiObj.Add("Button", "x366 y614 w92 h24", "Queue all")

    g_StudyCtl["answerLocal"] := guiObj.Add("Button", "x466 y400 w200 h26", "Answer (local evidence only)")
    g_StudyCtl["answerLLM"]   := guiObj.Add("Button", "x672 y400 w194 h26", "Answer (allow DeepSeek)")
    g_StudyCtl["cancel"]      := guiObj.Add("Button", "x672 y430 w194 h22", "Cancel request")
    g_StudyCtl["conf"] := guiObj.Add("Text", "x466 y432 w200 h20 cGray", "")
    g_StudyCtl["evidence"] := guiObj.Add("Edit", "x466 y456 w400 h150 ReadOnly Multi VScroll")
    g_StudyCtl["evidence"].SetFont("s9", "Consolas")
    g_StudyCtl["confirm"] := guiObj.Add("Button", "x466 y614 w96 h26", "Confirm")
    g_StudyCtl["dispute"] := guiObj.Add("Button", "x566 y614 w96 h26", "Dispute")
    g_StudyCtl["reject"]  := guiObj.Add("Button", "x666 y614 w96 h26", "Mark wrong")
    g_StudyCtl["editAns"] := guiObj.Add("Button", "x766 y614 w100 h26", "Edit answer")

    ; ── exports ───────────────────────────────────────────────────────────
    g_StudyCtl["expGuide"] := guiObj.Add("Button", "x28 y652 w160 h28", "Export study guide")
    g_StudyCtl["expCards"] := guiObj.Add("Button", "x194 y652 w160 h28", "Export flashcards")
    g_StudyCtl["expMissed"]:= guiObj.Add("Button", "x360 y652 w160 h28", "Export missed list")
    g_StudyCtl["expConc"]  := guiObj.Add("Button", "x526 y652 w160 h28", "Export concepts")

    ; ── wire events ───────────────────────────────────────────────────────
    g_StudyCtl["probe"].OnEvent("Click", (*) => Study_UiProbe())
    g_StudyCtl["savekey"].OnEvent("Click", (*) => Study_UiSaveKey())
    g_StudyCtl["forget"].OnEvent("Click", (*) => Study_UiForgetKey())
    g_StudyCtl["savecap"].OnEvent("Click", (*) => Study_UiSaveCostCap())
    g_StudyCtl["impFile"].OnEvent("Click", (*) => Study_UiImportFile(false))
    g_StudyCtl["impPdf"].OnEvent("Click", (*) => Study_UiImportFile(true))
    g_StudyCtl["impNote"].OnEvent("Click", (*) => Study_UiPasteNotes())
    g_StudyCtl["srcExcl"].OnEvent("Click", (*) => Study_UiToggleExclude())
    g_StudyCtl["srcDel"].OnEvent("Click", (*) => Study_UiDeleteSource())
    g_StudyCtl["raPick"].OnEvent("Click", (*) => (Study_ReadAlong_PickRegion(), Study_UiRefreshMat()))
    g_StudyCtl["raToggle"].OnEvent("Click", (*) => Study_UiToggleReadAlong())
    g_StudyCtl["qRefresh"].OnEvent("Click", (*) => Study_UiRefreshQuestions())
    g_StudyCtl["qFilter"].OnEvent("Change", (*) => Study_UiRefreshQuestions())
    g_StudyCtl["answerLocal"].OnEvent("Click", (*) => Study_UiAnswer(false))
    g_StudyCtl["answerLLM"].OnEvent("Click", (*) => Study_UiAnswer(true))
    g_StudyCtl["cancel"].OnEvent("Click", (*) => StudyLLM_CancelRequest())
    g_StudyCtl["confirm"].OnEvent("Click", (*) => Study_UiSetState("user-confirmed"))
    g_StudyCtl["dispute"].OnEvent("Click", (*) => Study_UiSetState("disputed"))
    g_StudyCtl["reject"].OnEvent("Click", (*) => Study_UiSetState("rejected"))
    g_StudyCtl["editAns"].OnEvent("Click", (*) => Study_UiEditAnswer())
    g_StudyCtl["review"].OnEvent("Click", (*) => Study_UiReviewNow())
    g_StudyCtl["buildQ"].OnEvent("Click", (*) => Study_UiBuildQueue())
    g_StudyCtl["expGuide"].OnEvent("Click", (*) => Study_UiExport(Study_ExportGuide()))
    g_StudyCtl["expCards"].OnEvent("Click", (*) => Study_UiExport(Study_ExportFlashcards()))
    g_StudyCtl["expMissed"].OnEvent("Click", (*) => Study_UiExport(Study_ExportMissed()))
    g_StudyCtl["expConc"].OnEvent("Click", (*) => Study_UiExport(Study_ExportConcepts()))
    g_StudyCtl["questions"].OnEvent("ItemSelect", (lv, r, sel) => (sel ? Study_UiQuestionSelected() : 0))

    Study_UiRefreshProvider()
    Study_UiRefreshMat()
    Study_UiRefreshQuestions()
}

; ─────────────────────────────────────────────────────────────────────────────
; UI HANDLERS
; ─────────────────────────────────────────────────────────────────────────────
Study_UiRefreshProvider() {
    global g_StudyCtl
    src := StudyLLM_KeySource()
    txt := (src != "") ? "Key: " . src : "No key set (text/local still works)"
    try g_StudyCtl["provstat"].Value := txt
}

Study_UiProbe() {
    global g_StudyCtl
    g_StudyCtl["provstat"].Value := "Probing..."
    res := StudyLLM_Probe()
    models := ""
    if res["models"].Length
        models := "  [" . Study_Join(res["models"], ", ") . "]"
    g_StudyCtl["provstat"].Value := (res["ok"] ? "OK - " : "X - ") . res["detail"]
    ShowStatus("DeepSeek: " . res["detail"] . models, res["ok"] ? "ok" : "fail")
}

Study_UiSaveKey() {
    ib := InputBox("Paste your DeepSeek API key.`n`nIt is stored in Windows Credential Manager (per-user, DPAPI-protected), never written to this project. Rotate any key that has been shared in chat."
                 , "DeepSeek API key", "Password w420")
    if (ib.Result != "OK" || Trim(ib.Value) = "")
        return
    if StudyLLM_SaveKey(Trim(ib.Value)) {
        ShowStatus("Key saved to Windows Credential Manager", "ok")
    } else {
        ShowStatus("Could not save the key (CredWrite failed)", "fail")
    }
    ib := ""               ; drop the cleartext value promptly
    Study_UiRefreshProvider()
}

Study_UiForgetKey() {
    if StudyLLM_DeleteKey()
        ShowStatus("Stored key removed from Credential Manager", "ok")
    else
        ShowStatus("No stored key to remove (or removal failed)", "wait")
    Study_UiRefreshProvider()
}

Study_UiSaveCostCap() {
    global g_StudyCtl
    v := Trim(g_StudyCtl["costcap"].Value)
    if !IsNumber(v) {
        ShowStatus("Cost cap must be a number", "fail")
        return
    }
    Study_SetSetting("cost_cap_usd", v)
    ShowStatus("Session cost cap set to $" . v, "ok")
}

Study_UiImportFile(pdf) {
    global g_StudyCtl
    filter := pdf ? "PDF (*.pdf)" : "Documents (*.txt; *.md; *.markdown; *.text)"
    path := ""
    try path := FileSelect(1, , pdf ? "Choose a PDF to ingest" : "Choose a document to ingest", filter)
    if (path = "")
        return
    ShowStatus("Ingesting " . path . " ...", "wait")
    res := Study_ImportFile(path)
    ShowStatus(res["detail"], res["ok"] ? "ok" : "fail")
    g_StudyCtl["matStat"].Value := res["detail"]
    Study_UiRefreshMat()
}

Study_UiPasteNotes() {
    global g_StudyCtl
    g := Gui("+AlwaysOnTop +Resize", "Paste study notes")
    g.MarginX := 10, g.MarginY := 10
    g.Add("Text", "x12 y10 w120", "Title:")
    titleE := g.Add("Edit", "x12 y30 w460 h24", "Pasted notes " . FormatTime(A_Now, "yyyy-MM-dd HH:mm"))
    g.Add("Text", "x12 y60 w200", "Notes (plain text or markdown):")
    bodyE := g.Add("Edit", "x12 y82 w460 h300 Multi VScroll WantReturn")
    g.Add("Button", "x12 y392 w120 h30 Default", "Import").OnEvent("Click", (*) => (
        Study_UiPasteNotesSave(titleE.Value, bodyE.Value), g.Destroy()))
    g.Add("Button", "x140 y392 w100 h30", "Cancel").OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.Show("w484 h436")
}

Study_UiPasteNotesSave(title, body) {
    global g_StudyCtl
    res := Study_ImportNotes(title, body)
    ShowStatus(res["detail"], res["ok"] ? "ok" : "fail")
    if res.Has("detail")
        g_StudyCtl["matStat"].Value := res["detail"]
    Study_UiRefreshMat()
}

Study_UiToggleExclude() {
    r := Study_SelectedSource()
    if !r.Count
        return
    Study_SourceExclude(r["id"], r["excluded"] ? 0 : 1)
    Study_UiRefreshMat()
}

Study_UiDeleteSource() {
    r := Study_SelectedSource()
    if !r.Count
        return
    if (MsgBox("Delete source '" . r["title"] . "' and its passages? Concepts and answers are kept.", "Confirm", "YesNo Icon!") != "Yes")
        return
    Study_SourceDelete(r["id"])
    Study_UiRefreshMat()
    ShowStatus("Source deleted", "ok")
}

Study_SelectedSource() {
    global g_StudyCtl, g_StudySourceRows
    lv := g_StudyCtl["sources"]
    row := lv.GetNext()
    if (!row || row > g_StudySourceRows.Length)
        return Map()
    return g_StudySourceRows[row]
}

Study_UiRefreshMat() {
    global g_StudyCtl, g_StudySourceRows, g_StudyReadAlongOn
    g_StudySourceRows := Study_Sources()
    lv := g_StudyCtl["sources"]
    lv.Opt("-Redraw")
    lv.Delete()
    for , s in g_StudySourceRows {
        ct := Trim(s["course"] . (s["topic"] != "" ? " / " . s["topic"] : ""))
        lv.Add(, s["title"], s["kind"], ct, s["passage_count"], s["pages"], s["excluded"] ? "yes" : "")
    }
    lv.Opt("+Redraw")
    g_StudyCtl["raToggle"].Text := g_StudyReadAlongOn ? "Stop read-along" : "Start read-along"
    cc := Study_ConceptCount()
    g_StudyCtl["matStat"].Value := g_StudySourceRows.Length . " source(s), "
        . cc . " concept(s)" . (g_StudyReadAlongOn ? "  -  reading along" : "")
}

Study_UiToggleReadAlong() {
    Study_ReadAlong_Toggle()
    Study_UiRefreshMat()
}

Study_UiRefreshQuestions() {
    global g_StudyCtl, g_StudyQuestionRows
    if !Study_Schema()
        return
    mode := g_StudyCtl["qFilter"].Text
    where := "archived=0 AND (answer IS NULL OR answer='')"
    if (mode = "All open")
        where := "archived=0"
    else if (mode = "Answered")
        where := "archived=0 AND answer IS NOT NULL AND answer<>''"
    else if (mode = "Disputed/rejected")
        where := "state IN ('disputed','rejected')"
    g_StudyQuestionRows := TrackDB().Query("SELECT * FROM qa_item WHERE " . where . " ORDER BY id DESC LIMIT 1000")
    lv := g_StudyCtl["questions"]
    lv.Opt("-Redraw")
    lv.Delete()
    for i, q in g_StudyQuestionRows {
        title := (q["label"] != "" ? q["label"] . " - " : "") . q["question"]
        lv.Add(, q["kind"], SubStr(title, 1, 90), Study_StateLabel(q), i)
    }
    lv.Opt("+Redraw")
}

Study_UiQuestionSelected() {
    global g_StudyCtl, g_StudyQuestionRows, g_StudyCurrentQa
    lv := g_StudyCtl["questions"]
    row := lv.GetNext()
    if (!row || row > g_StudyQuestionRows.Length)
        return
    idx := Integer(lv.GetText(row, 4))
    if (idx < 1 || idx > g_StudyQuestionRows.Length)
        return
    q := g_StudyQuestionRows[idx]
    g_StudyCurrentQa := q["id"]
    t := q["question"] . "`r`n"
    for , c in Qa_Choices(q)
        t .= "  (" . c["tag"] . ") " . c["text"] . "`r`n"
    if (q["answer"] != "")
        t .= "`r`nCURRENT ANSWER (" . Study_StateLabel(q) . "):`r`n" . q["answer"] . "`r`n"
    if (q.Has("evidence") && q["evidence"] != "")
        t .= "`r`nEVIDENCE:`r`n" . q["evidence"]
    g_StudyCtl["evidence"].Value := t
    g_StudyCtl["conf"].Value := q.Has("confidence") && q["confidence"]
        ? "confidence " . Round(q["confidence"] * 100) . "%" : ""
}

Study_CurrentRow() {
    global g_StudyCurrentQa
    if (!g_StudyCurrentQa || !Study_Schema())
        return Map()
    return TrackDB().QueryRow("SELECT * FROM qa_item WHERE id=?", g_StudyCurrentQa)
}

Study_UiAnswer(allowLLM) {
    global g_StudyCtl
    row := Study_CurrentRow()
    if !row.Count {
        ShowStatus("Select a question first", "wait")
        return
    }
    if allowLLM {
        g_StudyCtl["conf"].Value := "asking DeepSeek..."
        g_StudyCtl["evidence"].Value := "Contacting DeepSeek (Cancel to abort)..."
    }
    ; Run off the click handler so the UI stays responsive during a network call.
    SetTimer(() => Study_UiAnswerWork(row, allowLLM), -30)
}

Study_UiAnswerWork(row, allowLLM) {
    global g_StudyCtl
    res := Study_Answer(row, allowLLM)
    if (res["answer"] = "") {
        g_StudyCtl["conf"].Value := ""
        g_StudyCtl["evidence"].Value := "No answer produced." . (res["error"] != "" ? "`r`n`r`n" . res["error"] : "")
        ShowStatus(res["error"] != "" ? res["error"] : "No answer", "wait")
        return
    }
    ; Record the proposal in the trail + qa_item snapshot (stays a candidate).
    Study_RecordAnswer(row["id"], res["answer"], res["state"], res["source"]
                     , res["confidence"], res["evidence"], res["provider"], res["model"]
                     , res["source"] = "deepseek" ? "no local evidence" : "", res["cost"])
    body := "PROPOSED ANSWER  (source: " . res["source"] . ", state: " . res["state"] . ")`r`n`r`n"
          . res["answer"] . "`r`n`r`n--- EVIDENCE ---`r`n" . res["evidence"]
    g_StudyCtl["evidence"].Value := body
    g_StudyCtl["conf"].Value := "confidence " . Round(res["confidence"] * 100) . "%"
        . (res["cost"] ? "   est $" . Round(res["cost"], 4) : "")
    ShowStatus("Proposed (" . res["source"] . ") - verify before trusting", res["confidence"] >= 0.6 ? "ok" : "wait")
    Study_UiRefreshQuestions()
}

Study_UiSetState(state) {
    row := Study_CurrentRow()
    if !row.Count {
        ShowStatus("Select a question first", "wait")
        return
    }
    if ((state = "user-confirmed") && Trim(row["answer"]) = "") {
        ShowStatus("Nothing to confirm - answer it first", "wait")
        return
    }
    Study_SetState(row["id"], state)
    ; A confirmed answer becomes eligible for spaced review.
    if (state = "user-confirmed")
        Study_ReviewEnqueue(row["id"])
    ShowStatus("Marked " . state, "ok")
    Study_UiRefreshQuestions()
    Study_UiQuestionSelected()
}

Study_UiEditAnswer() {
    row := Study_CurrentRow()
    if !row.Count {
        ShowStatus("Select a question first", "wait")
        return
    }
    ib := InputBox("Correct or write the answer. Saving records it as user-confirmed and keeps the earlier attempt in the history."
                 , "Edit answer", "w480 h180", row["answer"])
    if (ib.Result != "OK")
        return
    Study_RecordAnswer(row["id"], Trim(ib.Value), "user-confirmed", "user", 1.0
                     , "Entered by hand", "", "", "", 0)
    Study_ReviewEnqueue(row["id"])
    ShowStatus("Answer saved and confirmed", "ok")
    Study_UiRefreshQuestions()
    Study_UiQuestionSelected()
}

Study_UiBuildQueue() {
    n := Study_ReviewBuildQueue()
    ShowStatus("Spaced-review queue: " . n . " question(s), " . Study_ReviewDueCount() . " due now", "ok")
}

Study_UiReviewNow() {
    row := Study_ReviewNext()
    if !row.Count {
        ShowStatus("Nothing due for review", "ok")
        return
    }
    Study_ReviewShow(row)
}

; A small self-test-style review card. Shows the question, reveals the stored
; answer on request, and grades it. No input is sent anywhere.
Study_ReviewShow(row) {
    global g_StudyReviewGui
    if IsObject(g_StudyReviewGui) {
        try g_StudyReviewGui.Destroy()
    }
    g := Gui("+AlwaysOnTop", "Spaced review  -  " . Study_ReviewDueCount() . " due")
    g.MarginX := 12, g.MarginY := 12
    g.Add("Edit", "x12 y10 w520 h90 ReadOnly Multi VScroll", row["question"]).SetFont("s10")
    ansBox := g.Add("Edit", "x12 y108 w520 h110 ReadOnly Multi VScroll")
    ansBox.SetFont("s10")
    ansBox.Value := "(click Show answer)"
    shown := {v: false}
    g.Add("Button", "x12 y226 w120 h28", "Show answer").OnEvent("Click", (*) => (
        ansBox.Value := row["answer"], shown.v := true))
    g.Add("Text", "x12 y262 w520 h18 cGray", "Grade your recall:")
    g.Add("Button", "x12 y284 w120 h30", "Again (0)").OnEvent("Click", (*) => Study_ReviewAnswer(g, row, 0))
    g.Add("Button", "x138 y284 w120 h30", "Hard (3)").OnEvent("Click", (*) => Study_ReviewAnswer(g, row, 3))
    g.Add("Button", "x264 y284 w120 h30", "Good (4)").OnEvent("Click", (*) => Study_ReviewAnswer(g, row, 4))
    g.Add("Button", "x390 y284 w142 h30", "Easy (5)").OnEvent("Click", (*) => Study_ReviewAnswer(g, row, 5))
    g.OnEvent("Close", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g_StudyReviewGui := g
    g.Show("w556 h330")
}

Study_ReviewAnswer(g, row, grade) {
    Study_ReviewGrade(row["id"], grade)
    g.Destroy()
    nxt := Study_ReviewNext()
    if nxt.Count
        Study_ReviewShow(nxt)
    else
        ShowStatus("Review complete - nothing else due", "ok")
}

Study_UiExport(path) {
    if (path = "" || !FileExist(path)) {
        ShowStatus("Nothing to export yet", "wait")
        return
    }
    ShowStatus("Exported: " . path, "ok")
    try Run('explorer.exe /select,"' . path . '"')
}
