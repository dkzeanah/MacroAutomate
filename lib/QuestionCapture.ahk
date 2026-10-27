; ═══════════════════════════════════════════════════════════════════════════════
; QuestionCapture.ahk - Capture real questions from what you TYPE
; ═══════════════════════════════════════════════════════════════════════════════
; The main, clean question-capture mechanism: as you type, a "?" captures the
; sentence immediately before it as a question record. This is deliberately NOT
; OCR of the screen (that is what filled qa_item with jibberish - ChatGPT
; windows, browser pages, video timestamps). Only prose you actually type,
; terminated by "?", becomes a question.
;
; It hooks the existing KeyTracker InputHook (one call from KeyTrack_OnChar), so
; it inherits KeyTracker's window exclusions (password/sensitive windows never
; reach here). Captured questions land in qa_item with kind/label "typed".
; ═══════════════════════════════════════════════════════════════════════════════

global g_QCapBuf := ""            ; rolling buffer of recently typed characters
global g_QCapMax := 600           ; cap the buffer length
global g_QCapOn := true           ; master switch (persisted)
global g_QCapCount := 0           ; questions captured this session

; Called once per typed character from KeyTrack_OnChar (non-excluded windows).
QCap_OnChar(char) {
    global g_QCapBuf, g_QCapMax, g_QCapOn
    if !g_QCapOn
        return
    ; A newline ends the current context (a new line is a new thought).
    if (char = "`r" || char = "`n") {
        g_QCapBuf := ""
        return
    }
    g_QCapBuf .= char
    if (StrLen(g_QCapBuf) > g_QCapMax)
        g_QCapBuf := SubStr(g_QCapBuf, -g_QCapMax)
    if (char = "?")
        QCap_OnQuestionMark()
}

; Extract the sentence ending at the just-typed "?" and store it.
QCap_OnQuestionMark() {
    global g_QCapBuf
    body := SubStr(g_QCapBuf, 1, StrLen(g_QCapBuf) - 1)   ; drop the trailing "?"
    ; The question is whatever follows the previous sentence terminator.
    lastTerm := 0
    for , t in [".", "!", "?", ";"] {
        p := InStr(body, t, false, -1)        ; last occurrence (backward search)
        if (p > lastTerm)
            lastTerm := p
    }
    sentence := Trim(SubStr(body, lastTerm + 1)) . "?"
    QCap_Store(sentence)
    ; Start fresh so the next "?" does not re-capture earlier text.
    g_QCapBuf := ""
}

; Store a typed question if it reads like one and is not a duplicate.
QCap_Store(sentence) {
    global g_QCapCount
    sentence := Trim(RegExReplace(sentence, "\s+", " "))
    if !QCap_LooksLikeQuestion(sentence)
        return false
    if !Qa_Schema()
        return false
    db := TrackDB()
    norm := StrLower(RegExReplace(sentence, "[^a-z0-9 ]", " "))
    norm := Trim(RegExReplace(norm, "\s+", " "))
    fp := "typed|" . SubStr(norm, 1, 150)
    try {
        if db.QueryRow("SELECT id FROM qa_item WHERE fingerprint=?", fp).Count
            return false
    }
    now := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    try {
        db.Run("INSERT INTO qa_item(created_ts,kind,label,question,choices,blanks,section,fingerprint) "
             . "VALUES(?,?,?,?,?,?,?,?)", now, "typed", "typed", sentence, "", 0, "typed", fp)
        g_QCapCount++
        return true
    } catch {
        return false   ; unique-index race or similar; ignore
    }
}

; A real typed question: a few words, actual letters, reasonable length. Rejects
; stray "?" after a word, URLs/paths, and over-long OCR-style dumps.
QCap_LooksLikeQuestion(s) {
    if (StrLen(s) < 10 || StrLen(s) > 280)
        return false
    ; must contain letters, and not look like a path/URL/code fragment
    if !RegExMatch(s, "[A-Za-z]{2,}")
        return false
    if RegExMatch(s, "i)https?://|^[a-z]:\\|[{}<>|]")
        return false
    words := StrSplit(RegExReplace(s, "\s+", " "), " ")
    if (words.Length < 3)
        return false
    ; a minute's worth of pasted text should not count: cap words
    if (words.Length > 45)
        return false
    return true
}

; Persist / restore the master switch and report state.
QCap_SetEnabled(on) {
    global g_QCapOn
    g_QCapOn := on ? true : false
    try Study_SetSetting("typed_question_capture", g_QCapOn ? "1" : "0")
}
QCap_Restore() {
    global g_QCapOn
    try g_QCapOn := (Study_GetSetting("typed_question_capture", "1") = "1")
}
QCap_Count() {
    if !Qa_Schema()
        return 0
    v := TrackDB().Scalar("SELECT COUNT(*) FROM qa_item WHERE kind='typed'")
    return IsInteger(v) ? Integer(v) : 0
}
