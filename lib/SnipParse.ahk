; ═══════════════════════════════════════════════════════════════════════════════
; SnipParse.ahk - Break a captured screenful into individual questions
; ═══════════════════════════════════════════════════════════════════════════════
; One snip of a worksheet is rarely one thing. A single capture of a numbered
; list is three prompts; a multiple-choice block is a stem plus its options.
; This module decides where one item ends and the next begins, works out what
; kind of item it is, and pulls out the parts worth storing separately.
;
;   SnipParse_Items(text) -> array of Map:
;       ordinal    the number or letter the source used ("1", "2", "b")
;       kind       "open" | "mcq" | "blank"
;       label      the bold-style lead-in before a colon, when there is one
;       question   the prompt itself
;       choices    array of Map(tag, text) for multiple choice
;       blanks     how many fill-in gaps were found
;       raw        the exact source lines this item came from
;
; Segmentation rules, in order of confidence:
;   1. a line beginning "1." / "2)" starts a new numbered item
;   2. a line beginning "a)" / "B." directly under a stem is a CHOICE of that
;      stem, not a new item - which is what separates a quiz from a list
;   3. a blank line only splits when nothing else has
;
; OCR never preserves bold, so a lead-in label is recognised by its colon, and
; a run of underscores marks a gap to fill.
; ═══════════════════════════════════════════════════════════════════════════════

; Split OCR text into question items.
;
; A page carries more than questions: a title, a paragraph of instructions, and
; section directives like "Define the following". Those change the meaning of
; everything under them - after "Define the following", a bare line is not prose
; but a TERM AWAITING A DEFINITION. Reading the directive is what turns a list of
; words into a set of answerable items, so it is handled before anything else.
SnipParse_Items(text) {
    items := []
    if (Trim(text) = "")
        return items

    lines := SnipParse_Lines(text)
    if !lines.Length
        return items

    blocks := [], cur := "", section := "", mode := ""
    for , ln in lines {
        t := ln["text"]

        ; ── a section directive: sets the meaning of the lines beneath it ────
        dmode := SnipParse_Directive(t)
        if (dmode != "") {
            if IsObject(cur) {
                blocks.Push(cur)
                cur := ""
            }
            section := RegExReplace(t, "[:\s]+$")
            mode := dmode
            blocks.Push(Map("ordinal", "", "lines", [t], "raw", [t]
                          , "section", section, "force", "context"))
            continue
        }

        ; ── numbered item starts a new block ────────────────────────────────
        if RegExMatch(t, "^\s*(\d{1,2})\s*[.)]\s+(.+)$", &m) {
            if IsObject(cur)
                blocks.Push(cur)
            cur := Map("ordinal", m[1], "lines", [m[2]], "raw", [t], "section", section)
            continue
        }

        ; ── under a "define"-style directive, a short bare line is a term ────
        if (mode = "define" && SnipParse_LooksLikeTerm(t)) {
            if IsObject(cur) {
                blocks.Push(cur)
                cur := ""
            }
            blocks.Push(Map("ordinal", "", "lines", [t], "raw", [t]
                          , "section", section, "force", "define"))
            continue
        }

        if !IsObject(cur)
            cur := Map("ordinal", "", "lines", [], "raw", [], "section", section)
        cur["lines"].Push(t)
        cur["raw"].Push(t)
    }
    if IsObject(cur)
        blocks.Push(cur)

    ; Nothing structured at all: fall back to blank-line grouping.
    if (blocks.Length = 1 && blocks[1]["ordinal"] = "" && !blocks[1].Has("force"))
        blocks := SnipParse_BlankSplit(lines)

    for , b in blocks {
        item := SnipParse_Classify(b)
        if (item.Count && item["question"] != "")
            items.Push(item)
    }
    return items
}

; Recognise an instruction that governs the lines beneath it. Returns the mode
; it sets ("define" | "answer" | "choose" | "match"), or "" when it is not one.
SnipParse_Directive(line) {
    s := Trim(line)
    if (StrLen(s) < 8 || StrLen(s) > 160)
        return ""
    ; An imperative aimed at what follows: "Define the following...",
    ; "Answer each of the questions below:".
    if !RegExMatch(s, "i)^(define|describe|explain|identify|list|name|match|answer"
                    . "|choose|select|complete|fill in|compare|contrast|state)\b")
        return ""
    if !RegExMatch(s, "i)\b(following|below|these|each|every|the terms?|them)\b")
        return ""
    if RegExMatch(s, "i)^(define|describe|explain|identify|list|name|state)\b")
        return "define"
    if RegExMatch(s, "i)^(choose|select)\b")
        return "choose"
    if RegExMatch(s, "i)^match\b")
        return "match"
    return "answer"
}

; A bare term to be defined: short, few words, not a sentence or a question.
SnipParse_LooksLikeTerm(line) {
    s := Trim(line)
    if (s = "" || StrLen(s) > 64)
        return false
    if InStr(s, "?")
        return false
    if (SubStr(s, -1) = ".")            ; sentences end in a full stop
        return false
    words := StrSplit(RegExReplace(s, "\s+", " "), " ")
    if (words.Length > 6)
        return false
    ; Needs real letters, not a stray fragment or page furniture.
    if !RegExMatch(s, "[A-Za-z]{3,}")
        return false
    return true
}

; Normalised, non-empty lines with their blank-line gaps recorded.
SnipParse_Lines(text) {
    out := []
    prevBlank := false
    for , raw in StrSplit(text, "`n", "`r") {
        s := Trim(RegExReplace(raw, "\s+", " "))
        if (s = "") {
            prevBlank := true
            continue
        }
        out.Push(Map("text", s, "after_blank", prevBlank))
        prevBlank := false
    }
    return out
}

SnipParse_BlankSplit(lines) {
    blocks := [], cur := ""
    for , ln in lines {
        if (!IsObject(cur) || ln["after_blank"]) {
            if IsObject(cur)
                blocks.Push(cur)
            cur := Map("ordinal", "", "lines", [], "raw", [])
        }
        cur["lines"].Push(ln["text"])
        cur["raw"].Push(ln["text"])
    }
    if IsObject(cur)
        blocks.Push(cur)
    return blocks
}

; ═══════════════════════════════════════════════════════════════════════════════
; CLASSIFICATION
; ═══════════════════════════════════════════════════════════════════════════════

; Decide what one block actually is, and split off its parts.
SnipParse_Classify(block) {
    item := Map("ordinal", block["ordinal"], "kind", "open", "label", ""
              , "question", "", "choices", [], "blanks", 0
              , "section", block.Has("section") ? block["section"] : ""
              , "raw", SnipParse_Join(block["raw"]))

    ; Blocks the segmenter already decided about: a directive line is context,
    ; a term under one is a definition to supply.
    if block.Has("force") {
        item["kind"] := block["force"]
        item["question"] := SnipParse_Join(block["lines"])
        return item
    }

    ; ── separate any choice lines from the stem ──────────────────────────────
    stemLines := [], choices := []
    for , ln in block["lines"] {
        if RegExMatch(ln, "^\s*\(?([A-Ha-h])\)?\s*[.):]\s+(.+)$", &m) && choices.Length < 12 {
            choices.Push(Map("tag", StrUpper(m[1]), "text", Trim(m[2])))
            continue
        }
        ; "The capital is:  a) Berlin  b) Madrid" - stem and options wrapped onto
        ; one OCR line. Whatever precedes the first option is still the stem and
        ; must not be swallowed with the choices.
        if (choices.Length = 0 && SnipParse_InlineChoices(ln, &found, &prefix) && found.Length >= 2) {
            if (Trim(prefix) != "")
                stemLines.Push(Trim(prefix))
            for , c in found
                choices.Push(c)
            continue
        }
        stemLines.Push(ln)
    }

    stem := SnipParse_Join(stemLines)
    stem := Trim(stem)

    ; ── a leading "Label: rest" lead-in ──────────────────────────────────────
    ; Only treat it as a label when it is short - a colon inside a sentence is
    ; not a heading.
    if RegExMatch(stem, "^(.{2,70}?):\s+(.+)$", &lm) {
        head := Trim(lm[1])
        if !InStr(head, "?") && StrLen(head) <= 70 {
            item["label"] := head
            stem := Trim(lm[2])
        }
    }

    item["question"] := stem

    ; ── is this a question at all? ───────────────────────────────────────────
    ; A heading or a paragraph of instructions is worth keeping as context but
    ; must never enter the bank as something to answer.
    if (item["ordinal"] = "" && choices.Length = 0 && SnipParse_CountBlanks(stem) = 0
        && !InStr(stem, "?") && !SnipParse_IsImperative(stem)) {
        item["kind"] := "context"
        return item
    }

    ; ── kind ─────────────────────────────────────────────────────────────────
    if (choices.Length >= 2) {
        item["kind"] := "mcq"
        item["choices"] := choices
    } else {
        gaps := SnipParse_CountBlanks(stem)
        if (gaps > 0) {
            item["kind"] := "blank"
            item["blanks"] := gaps
        }
    }
    return item
}

; "a) red  b) green  c) blue" on a single line. `prefix` receives anything
; before the first option, which belongs to the stem.
SnipParse_InlineChoices(line, &found, &prefix) {
    found := [], prefix := ""
    pos := 1, firstAt := 0
    while (pos := RegExMatch(line, "(?:^|\s)\(?([A-Ha-h])\)\s*([^()]{1,80}?)(?=\s+\(?[A-Ha-h]\)|$)", &m, pos)) {
        if !firstAt
            firstAt := m.Pos(1)
        found.Push(Map("tag", StrUpper(m[1]), "text", Trim(m[2])))
        pos += StrLen(m[0])
        if (found.Length >= 12)
            break
    }
    if (found.Length >= 2 && firstAt > 1)
        prefix := RegExReplace(SubStr(line, 1, firstAt - 1), "[\s:]+$")
    return found.Length >= 2
}

; Runs of underscores, or bracketed gaps, are places an answer belongs.
SnipParse_CountBlanks(s) {
    n := 0, pos := 1
    while (pos := RegExMatch(s, "_{3,}", &m, pos)) {
        n++
        pos += StrLen(m[0])
    }
    return n
}

; Does this read as a task rather than a statement?
SnipParse_IsImperative(s) {
    return RegExMatch(s, "i)^(define|describe|explain|identify|list|name|match|answer"
                       . "|choose|select|complete|fill in|compare|contrast|state|why|how"
                       . "|what|when|where|which|who)\b")
}

SnipParse_Join(arr) {
    out := ""
    for , s in arr
        out .= (out = "" ? "" : " ") . s
    return Trim(RegExReplace(out, "\s{2,}", " "))
}

; A short caption for lists and prompts.
SnipParse_Title(item) {
    if (item["label"] != "")
        return item["label"]
    q := item["question"]
    return StrLen(q) > 60 ? SubStr(q, 1, 57) . "..." : q
}

; ═══════════════════════════════════════════════════════════════════════════════
; THE QUESTION BANK
; ═══════════════════════════════════════════════════════════════════════════════
; Parsed items are stored one row each, with an answer field that starts empty.
; An empty answer is the whole point: it is what the review prompt hunts for.

global g_QaSchemaReady := false

Qa_Schema() {
    global g_QaSchemaReady
    if g_QaSchemaReady
        return true
    db := TrackDB()
    if !db
        return false
    try {
        db.Exec("CREATE TABLE IF NOT EXISTS qa_item ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT,"
              . "created_ts TEXT, snip_id INTEGER, source_image TEXT,"
              . "ordinal TEXT, kind TEXT, label TEXT,"
              . "question TEXT NOT NULL, choices TEXT, blanks INTEGER DEFAULT 0,"
              . "section TEXT DEFAULT '',"
              . "answer TEXT DEFAULT '', answered_ts TEXT,"
              . "correct_tags TEXT DEFAULT '',"      ; which choice letters are right
              . "shown INTEGER DEFAULT 0, last_shown_ts TEXT,"
              . "skipped INTEGER DEFAULT 0, archived INTEGER DEFAULT 0,"
              . "fingerprint TEXT)")
        db.Exec("CREATE INDEX IF NOT EXISTS ix_qa_open ON qa_item(archived, answer)")
        db.Exec("CREATE UNIQUE INDEX IF NOT EXISTS ix_qa_fp ON qa_item(fingerprint)")
    } catch as err {
        TrackLogError("Qa_Schema", err)
        return false
    }
    g_QaSchemaReady := true
    return true
}

; A stable identity for a question so re-capturing the same worksheet updates
; rather than duplicating - screens get snipped more than once.
Qa_Fingerprint(item) {
    s := StrLower(RegExReplace(item["label"] . " " . item["question"], "[^A-Za-z0-9]+", ""))
    return SubStr(s, 1, 120)
}

; Find an item already in the bank that is really the same question.
;
; An exact fingerprint match only catches a clean re-capture. Overlapping snips
; produce two other kinds of near-duplicate that matter just as much:
;
;   TRUNCATION  the region clipped a question mid-sentence, so one copy is a
;               prefix of the other ("...primary sympt" vs "...primary symptoms
;               and behavioral changes")
;   MISREAD     OCR turned one character into another ("Agonlst" / "Agonist")
;
; Both are resolved here. Candidates are prefiltered in SQL on a shared opening
; so this stays cheap as the bank grows.
Qa_FindSimilar(fp) {
    db := TrackDB()
    if (!db || fp = "")
        return 0
    row := db.QueryRow("SELECT id FROM qa_item WHERE fingerprint=?", fp)
    if row.Count
        return row["id"]

    head := SubStr(fp, 1, 3)
    if (StrLen(head) < 3)
        return 0
    cands := []
    try cands := db.Query("SELECT id,fingerprint FROM qa_item "
                        . "WHERE substr(fingerprint,1,3)=? LIMIT 400", head)
    for c in cands {
        other := c["fingerprint"]
        if (other = "")
            continue
        ; one is a prefix of the other - the same question, differently clipped
        shorter := StrLen(fp) <= StrLen(other) ? fp : other
        longer := StrLen(fp) <= StrLen(other) ? other : fp
        if (StrLen(shorter) >= 12 && SubStr(longer, 1, StrLen(shorter)) = shorter)
            return c["id"]
        ; a character or two apart - almost certainly one misread glyph
        if (Abs(StrLen(fp) - StrLen(other)) <= 2) {
            budget := Max(1, Min(2, StrLen(fp) // 8))
            if (Qa_EditDistance(fp, other, budget) <= budget)
                return c["id"]
        }
    }
    return 0
}

; Levenshtein distance, abandoned as soon as it exceeds `budget` so a long
; comparison costs nothing once it is clearly not a match.
Qa_EditDistance(a, b, budget := 2) {
    la := StrLen(a), lb := StrLen(b)
    if (Abs(la - lb) > budget)
        return budget + 1
    if (a = b)
        return 0
    prev := [], cur := []
    Loop lb + 1
        prev.Push(A_Index - 1)
    Loop la {
        i := A_Index
        cur := [i]
        best := i
        Loop lb {
            j := A_Index
            cost := (SubStr(a, i, 1) = SubStr(b, j, 1)) ? 0 : 1
            v := Min(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost)
            cur.Push(v)
            if (v < best)
                best := v
        }
        if (best > budget)
            return budget + 1
        prev := cur
    }
    return prev[lb + 1]
}

; Store parsed items. Returns Map(added, updated, skipped).
Qa_StoreItems(items, snipId := 0, sourceImage := "") {
    out := Map("added", 0, "updated", 0, "skipped", 0, "improved", 0)
    if (!items.Length || !Qa_Schema())
        return out
    db := TrackDB()
    now := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    for , it in items {
        if (it["kind"] = "context") {      ; titles and instructions, not tasks
            out["skipped"]++
            continue
        }
        fp := Qa_Fingerprint(it)
        if (fp = "") {
            out["skipped"]++
            continue
        }
        choicesText := ""
        for , c in it["choices"]
            choicesText .= (choicesText = "" ? "" : "`n") . c["tag"] . "|" . c["text"]
        existingId := Qa_FindSimilar(fp)
        if existingId {
            ; Keep whichever copy of the text is more complete. A later capture
            ; that caught the whole question should replace an earlier one that
            ; was clipped, without losing an answer already given.
            prev := db.QueryRow("SELECT question,label,answer,fingerprint FROM qa_item WHERE id=?"
                              , existingId)
            if (prev.Count && StrLen(it["question"]) > StrLen(prev["question"])) {
                db.Run("UPDATE qa_item SET question=?, label=?, fingerprint=? WHERE id=?"
                     , it["question"]
                     , (it["label"] != "" ? it["label"] : prev["label"])
                     , fp, existingId)
                out["improved"]++
            }
            db.Run("UPDATE qa_item SET source_image=?, choices=?, kind=?, blanks=? WHERE id=?"
                 , sourceImage, choicesText, it["kind"], it["blanks"], existingId)
            out["updated"]++
            continue
        }
        try {
            db.Run("INSERT INTO qa_item(created_ts,snip_id,source_image,ordinal,kind,label,"
                 . "question,choices,blanks,section,fingerprint) VALUES(?,?,?,?,?,?,?,?,?,?,?)"
                 , now, snipId, sourceImage, it["ordinal"], it["kind"], it["label"]
                 , it["question"], choicesText, it["blanks"]
                 , it.Has("section") ? it["section"] : "", fp)
            out["added"]++
        } catch as err {
            TrackLogError("Qa_StoreItems", err)
            out["skipped"]++
        }
    }
    return out
}

Qa_Choices(row) {
    out := []
    txt := row.Has("choices") ? row["choices"] : ""
    for , line in StrSplit(txt, "`n", "`r") {
        if (Trim(line) = "")
            continue
        p := StrSplit(line, "|", , 2)
        out.Push(Map("tag", p[1], "text", p.Length > 1 ? p[2] : ""))
    }
    return out
}

Qa_OpenCount() {
    if !Qa_Schema()
        return 0
    v := TrackDB().Scalar("SELECT COUNT(*) FROM qa_item WHERE archived=0 AND (answer IS NULL OR answer='')")
    return IsInteger(v) ? Integer(v) : 0
}

; Pick one unanswered question. Least-shown first so the whole set gets covered,
; with a random tiebreak so the order is not identical every session.
Qa_PickUnanswered() {
    if !Qa_Schema()
        return Map()
    return TrackDB().QueryRow("SELECT * FROM qa_item WHERE archived=0 "
        . "AND (answer IS NULL OR answer='') ORDER BY shown ASC, RANDOM() LIMIT 1")
}

Qa_SaveAnswer(id, answer, correctTags := "") {
    if !Qa_Schema()
        return
    TrackDB().Run("UPDATE qa_item SET answer=?, correct_tags=?, answered_ts=? WHERE id=?"
        , answer, correctTags, FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"), id)
}

Qa_MarkShown(id) {
    if !Qa_Schema()
        return
    TrackDB().Run("UPDATE qa_item SET shown=shown+1, last_shown_ts=? WHERE id=?"
        , FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"), id)
}

Qa_Archive(id) {
    if !Qa_Schema()
        return
    TrackDB().Run("UPDATE qa_item SET archived=1 WHERE id=?", id)
}

; ═══════════════════════════════════════════════════════════════════════════════
; THE ROULETTE - unanswered questions come back on their own
; ═══════════════════════════════════════════════════════════════════════════════
; A question with no answer is worth nothing until it is answered, so the bank
; nags. The interval is randomised between two bounds rather than fixed: a
; predictable prompt gets dismissed reflexively.

global g_QaRouletteOn := false
global g_QaPromptGui := ""

Qa_RouletteStart() {
    global g_QaRouletteOn
    g_QaRouletteOn := true
    Snip_SetSetting("roulette", "1")
    Qa_RouletteArm()
    ShowStatus("Question roulette on - unanswered questions will surface periodically", "ok")
}

Qa_RouletteStop() {
    global g_QaRouletteOn
    g_QaRouletteOn := false
    Snip_SetSetting("roulette", "0")
    SetTimer(Qa_RouletteFire, 0)
    ShowStatus("Question roulette off", "ok")
}

Qa_RouletteToggle() {
    global g_QaRouletteOn
    g_QaRouletteOn ? Qa_RouletteStop() : Qa_RouletteStart()
}

; Schedule the next appearance somewhere inside the configured window.
Qa_RouletteArm() {
    global g_QaRouletteOn
    if !g_QaRouletteOn
        return
    lo := Integer(Snip_GetSetting("roulette_min", "10"))     ; minutes
    hi := Integer(Snip_GetSetting("roulette_max", "45"))
    if (lo < 1)
        lo := 1
    if (hi < lo)
        hi := lo
    mins := Random(lo, hi)
    SetTimer(Qa_RouletteFire, -(mins * 60000))
}

Qa_RouletteFire() {
    global g_QaRouletteOn, g_QaPromptGui
    if !g_QaRouletteOn
        return
    ; Never interrupt a prompt that is already waiting for an answer.
    if IsObject(g_QaPromptGui) {
        Qa_RouletteArm()
        return
    }
    row := Qa_PickUnanswered()
    if !row.Count {
        Qa_RouletteArm()
        return
    }
    Qa_Prompt(row)
    Qa_RouletteArm()
}

; Ask one question. Answering stores it; Skip puts it back in the pool.
Qa_Prompt(row) {
    global g_QaPromptGui
    if IsObject(g_QaPromptGui) {
        try g_QaPromptGui.Destroy()
        g_QaPromptGui := ""
    }
    Qa_MarkShown(row["id"])
    choices := Qa_Choices(row)

    g := Gui("+AlwaysOnTop +Resize", "Question - " . Qa_OpenCount() . " still unanswered")
    g.MarginX := 12, g.MarginY := 12
    if (row["label"] != "") {
        lbl := g.Add("Text", "x12 y10 w576 vQaLabel", row["label"])
        lbl.SetFont("s11 bold")
    }
    g.Add("Edit", "x12 y36 w576 h96 ReadOnly Multi VScroll vQaQuestion", row["question"])
        .SetFont("s10")

    y := 140
    if choices.Length {
        g.Add("Text", "x12 y" . y . " w576 vQaChoiceHdr"
            , "Choices - tick every correct one:")
        y += 20
        for i, c in choices {
            g.Add("CheckBox", "x18 y" . y . " w570 vQaC" . i, c["tag"] . ")  " . c["text"])
            y += 22
        }
        y += 4
    }
    g.Add("Text", "x12 y" . y . " w576 vQaAnsHdr", choices.Length
        ? "Notes (optional):" : "Your answer:")
    y += 18
    g.Add("Edit", "x12 y" . y . " w576 h110 Multi VScroll vQaAnswer").SetFont("s10")
    y += 120

    g.Add("Button", "x12 y" . y . " w150 h30 Default vQaSave", "Save answer")
        .OnEvent("Click", (*) => Qa_PromptSave(g, row, choices))
    g.Add("Button", "x170 y" . y . " w110 h30 vQaSkip", "Skip for now")
        .OnEvent("Click", (*) => (g.Destroy(), ShowStatus("Skipped - it stays in the pool", "wait")))
    g.Add("Button", "x288 y" . y . " w120 h30 vQaSource", "Show source")
        .OnEvent("Click", (*) => Qa_ShowSource(row))
    g.Add("Button", "x416 y" . y . " w172 h30 vQaRetire", "Retire this question")
        .OnEvent("Click", (*) => (Qa_Archive(row["id"]), g.Destroy()
            , ShowStatus("Question retired", "ok")))

    g.OnEvent("Close", (*) => (g.Destroy(), Qa_ForgetPrompt()))
    g.OnEvent("Escape", (*) => (g.Destroy(), Qa_ForgetPrompt()))
    g_QaPromptGui := g
    g.Show("w600 h" . (y + 48))
}

Qa_ForgetPrompt() {
    global g_QaPromptGui
    g_QaPromptGui := ""
}

Qa_PromptSave(g, row, choices) {
    ans := ""
    try ans := Trim(g["QaAnswer"].Value, " `t`r`n")
    tags := ""
    for i, c in choices {
        try {
            if g["QaC" . i].Value
                tags .= (tags = "" ? "" : ",") . c["tag"]
        }
    }
    if (ans = "" && tags = "") {
        ShowStatus("Type an answer or tick a choice first", "wait")
        return
    }
    ; A ticked choice is itself an answer even with no notes.
    if (ans = "")
        ans := "Selected: " . tags
    Qa_SaveAnswer(row["id"], ans, tags)
    g.Destroy()
    Qa_ForgetPrompt()
    ShowStatus("Answer saved - " . Qa_OpenCount() . " question(s) still unanswered", "ok")
}

Qa_ShowSource(row) {
    p := row.Has("source_image") ? row["source_image"] : ""
    ; Braces are required: in v2 a braceless `try` claims the `else`.
    if (p != "" && FileExist(p)) {
        try Run('"' . p . '"')
    } else {
        ShowStatus("The source image for that question is not on disk", "fail")
    }
}

; Ask one now, rather than waiting for the timer.
Qa_AskNow() {
    row := Qa_PickUnanswered()
    if !row.Count {
        ShowStatus("No unanswered questions in the bank", "ok")
        return
    }
    Qa_Prompt(row)
}

; ═══════════════════════════════════════════════════════════════════════════════
; QUESTION BANK VIEWER
; ═══════════════════════════════════════════════════════════════════════════════

global g_QaBankGui := "", g_QaBankLV := "", g_QaBankRows := []
global g_QaBankFilter := "", g_QaBankDetail := ""

Qa_OpenBank() {
    global g_QaBankGui, g_QaBankLV, g_QaBankFilter, g_QaBankDetail
    if IsObject(g_QaBankGui) {
        try {
            g_QaBankGui.Show()
            Qa_BankLoad()
            return
        }
    }
    g := Gui("+Resize", "Question bank")
    g.MarginX := 10, g.MarginY := 10
    g.Add("Text", "x12 y14 w40", "Show:")
    g_QaBankFilter := g.Add("DropDownList", "x54 y11 w150 Choose1 vQaShow"
        , ["Unanswered", "Answered", "All", "Retired"])
    g_QaBankFilter.OnEvent("Change", (*) => Qa_BankLoad())
    g.Add("Button", "x212 y10 w96 h24", "Refresh").OnEvent("Click", (*) => Qa_BankLoad())
    g.Add("Button", "x314 y10 w110 h24", "Ask me one").OnEvent("Click", (*) => Qa_AskNow())
    g.Add("Button", "x430 y10 w110 h24", "Export CSV").OnEvent("Click", (*) => Qa_ExportCsv())

    g_QaBankLV := g.Add("ListView", "x12 y44 w620 h420 Grid vQaLV"
        , ["#", "Kind", "Label / question", "Answer", "Shown", "id"])
    g_QaBankLV.ModifyCol(1, 34)
    g_QaBankLV.ModifyCol(2, 54)
    g_QaBankLV.ModifyCol(3, 300)
    g_QaBankLV.ModifyCol(4, 160)
    g_QaBankLV.ModifyCol(5, 46)
    g_QaBankLV.ModifyCol(6, 0)
    g_QaBankLV.OnEvent("ItemSelect", (lv, r, sel) => (sel ? Qa_BankDetail() : 0))
    g_QaBankLV.OnEvent("DoubleClick", (*) => Qa_BankAnswer())

    g_QaBankDetail := g.Add("Edit", "x640 y44 w330 h380 ReadOnly Multi VScroll vQaDetail")
    g_QaBankDetail.SetFont("s9", "Consolas")
    g.Add("Button", "x640 y430 w160 h30 vQaBankAns", "Answer this")
        .OnEvent("Click", (*) => Qa_BankAnswer())
    g.Add("Button", "x808 y430 w162 h30 vQaBankRetire", "Retire")
        .OnEvent("Click", (*) => Qa_BankRetire())
    g.OnEvent("Size", Qa_BankResize)
    g.OnEvent("Close", (*) => g.Hide())
    g.OnEvent("Escape", (*) => g.Hide())
    g_QaBankGui := g
    g.Show("w982 h476")
    Qa_BankLoad()
}

Qa_BankResize(g, minMax, w, h) {
    if (minMax = -1)
        return
    try {
        rightW := 330
        lvW := Max(240, w - rightW - 34)
        g["QaLV"].Move(12, 44, lvW, h - 60)
        rx := 24 + lvW
        g["QaDetail"].Move(rx, 44, rightW, h - 100)
        g["QaBankAns"].Move(rx, h - 46, 160, 30)
        g["QaBankRetire"].Move(rx + 168, h - 46, 162, 30)
    }
}

Qa_BankLoad() {
    global g_QaBankLV, g_QaBankRows, g_QaBankFilter
    if !Qa_Schema()
        return
    mode := g_QaBankFilter.Text
    where := "archived=0 AND (answer IS NULL OR answer='')"
    if (mode = "Answered")
        where := "archived=0 AND answer IS NOT NULL AND answer<>''"
    else if (mode = "All")
        where := "archived=0"
    else if (mode = "Retired")
        where := "archived=1"
    g_QaBankRows := TrackDB().Query("SELECT * FROM qa_item WHERE " . where
                                  . " ORDER BY id DESC LIMIT 2000")
    g_QaBankLV.Opt("-Redraw")
    g_QaBankLV.Delete()
    for i, r in g_QaBankRows {
        title := (r["label"] != "" ? r["label"] . " - " : "") . r["question"]
        g_QaBankLV.Add(, r["ordinal"], r["kind"], SubStr(title, 1, 110)
                     , SubStr(r["answer"], 1, 90), r["shown"], i)
    }
    g_QaBankLV.Opt("+Redraw")
    if g_QaBankRows.Length
        g_QaBankLV.Modify(1, "Select Focus")
}

Qa_BankSelected() {
    global g_QaBankLV, g_QaBankRows
    row := g_QaBankLV.GetNext()
    if !row
        return Map()
    idx := Integer(g_QaBankLV.GetText(row, 6))
    return (idx >= 1 && idx <= g_QaBankRows.Length) ? g_QaBankRows[idx] : Map()
}

Qa_BankDetail() {
    global g_QaBankDetail
    r := Qa_BankSelected()
    if !r.Count
        return
    t := ""
    if (r["label"] != "")
        t .= r["label"] . "`r`n`r`n"
    t .= r["question"] . "`r`n`r`n"
    for , c in Qa_Choices(r)
        t .= "  (" . c["tag"] . ") " . c["text"] . "`r`n"
    if (r["correct_tags"] != "")
        t .= "`r`nmarked correct: " . r["correct_tags"] . "`r`n"
    t .= "`r`nANSWER`r`n" . (r["answer"] != "" ? r["answer"] : "(not answered yet)") . "`r`n"
    t .= "`r`nkind " . r["kind"] . "   shown " . r["shown"] . " time(s)"
    t .= "`r`ncaptured " . r["created_ts"] . "`r`n" . r["source_image"]
    g_QaBankDetail.Value := t
}

Qa_BankAnswer() {
    r := Qa_BankSelected()
    if r.Count
        Qa_Prompt(r)
}

Qa_BankRetire() {
    r := Qa_BankSelected()
    if !r.Count
        return
    Qa_Archive(r["id"])
    Qa_BankLoad()
    ShowStatus("Question retired", "ok")
}

Qa_ExportCsv() {
    global g_QaBankRows, DATA_DIR
    if !g_QaBankRows.Length {
        ShowStatus("Nothing to export", "wait")
        return
    }
    path := DATA_DIR . "\questions_" . FormatTime(A_Now, "yyyyMMdd_HHmmss") . ".csv"
    out := "ordinal,kind,label,question,choices,answer,correct_tags,created_ts`r`n"
    for r in g_QaBankRows {
        out .= TrackCsvRow([r["ordinal"], r["kind"], r["label"], r["question"]
                          , StrReplace(r["choices"], "`n", " / "), r["answer"]
                          , r["correct_tags"], r["created_ts"]]) . "`r`n"
    }
    Track_WriteFile(path, out)
    ShowStatus("Exported " . g_QaBankRows.Length . " question(s)", "ok")
    try Run('explorer.exe /select,"' . path . '"')
}
