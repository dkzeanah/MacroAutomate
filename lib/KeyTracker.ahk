; ═══════════════════════════════════════════════════════════════════════════════
; KeyTracker.ahk - Feature 3: keystroke history, 1-minute snapshots
; ═══════════════════════════════════════════════════════════════════════════════
; A non-consuming InputHook observes every keystroke system-wide (keys pass
; straight through to the focused app). Each key is attributed to the currently
; tracked window and accumulated into a per-minute bucket, then, on flush,
; distilled into the columns of key_snapshot:
;
;   raw_stream   compact token stream, e.g. "H e l l o {Space} {Enter} ^c"
;   text_typed   the reconstructed printable text
;   hotkeys      chord combos: "^c ^v {F5} !{Tab}"
;   strings      whitespace-delimited words extracted from text_typed
;   sentences    text split on . ! ? and newlines
;   code_snips   lines that look like code (see KeyTrack_LooksLikeCode)
;   clips        clipboard captures that landed in this minute
;   wpm          rough typing rate for the minute
;
; A clipboard watcher (OnClipboardChange) records copies into clip_history and
; folds a short preview into the active bucket's `clips`.
; ═══════════════════════════════════════════════════════════════════════════════

; ─── Configuration ───────────────────────────────────────────────────────────
global g_KeyTrackOn := false
global g_KeyClipMax := 100000         ; Longest clipboard capture kept (chars)
global g_KeyMaskDigits := false       ; Redact digit runs of 4+ (PII-ish)

; ─── Hook + bucket state ─────────────────────────────────────────────────────
global g_KeyHook := ""
global g_KeyBucket := ""
global g_KeyLastCharTick := 0
global g_KeyDownMods := Map()         ; Physical modifier state, refreshed per key

; ═══════════════════════════════════════════════════════════════════════════════
; PUBLIC CONTROL
; ═══════════════════════════════════════════════════════════════════════════════

KeyTrack_Start() {
    global g_KeyTrackOn, g_KeyHook

    if !TrackDB_Ready() {
        if !TrackDB_Init()
            return false
    }
    if g_KeyTrackOn
        return true

    ; ─── Install the observing InputHook ─────────────────────────────────────
    ; V  : keystrokes stay Visible (pass through to the focused app)
    ; L0 : no length cap - the hook runs until we stop it
    ih := InputHook("V L0")
    ih.NotifyNonText := true
    ih.OnChar := KeyTrack_OnChar
    ih.OnKeyDown := KeyTrack_OnKeyDown
    ; Notify for every key, including navigation / editing keys with no char,
    ; and keep them "visible" so none of them terminate the hook.
    ih.KeyOpt("{All}", "NV")
    try {
        ih.Start()
    } catch as err {
        TrackLogError("KeyTrack_Start", err)
        return false
    }
    g_KeyHook := ih

    ; ─── Clipboard watcher ───────────────────────────────────────────────────
    try OnClipboardChange(KeyTrack_OnClipboard, 1)

    g_KeyTrackOn := true
    return true
}

KeyTrack_Stop() {
    global g_KeyTrackOn, g_KeyHook

    if !g_KeyTrackOn
        return
    KeyTrack_FlushBucket()

    if IsObject(g_KeyHook) {
        try g_KeyHook.Stop()
        g_KeyHook := ""
    }
    try OnClipboardChange(KeyTrack_OnClipboard, 0)

    g_KeyTrackOn := false
}

KeyTrack_Toggle() {
    global g_KeyTrackOn
    if g_KeyTrackOn
        KeyTrack_Stop()
    else
        KeyTrack_Start()
    return g_KeyTrackOn
}

KeyTrack_IsOn() {
    global g_KeyTrackOn
    return g_KeyTrackOn
}

; Called by the window tracker when focus moves to a different window.
KeyTrack_OnWindowChange(ctx) {
    global g_KeyTrackOn
    if !g_KeyTrackOn
        return
    KeyTrack_FlushBucket()
}

; ═══════════════════════════════════════════════════════════════════════════════
; BUCKETS
; ═══════════════════════════════════════════════════════════════════════════════

KeyTrack_NewBucket(ctx) {
    return Map(
        "win_id", ctx["win_id"],
        "app_id", ctx["app_id"],
        "win_name", ctx["name"],
        "minute_key", TrackMinuteKey(),
        "start_ts", TrackTS(),
        "keystrokes", 0,
        "raw", "",             ; token stream
        "text", "",            ; reconstructed printable text
        "hotkeys", [],         ; chord tokens
        "clips", [],           ; clipboard previews captured this minute
        "hotkeyCounts", Map()  ; combo -> count, flushed to hotkey_stat
    )
}

; Ensure a bucket that matches the current tracked window + minute. Returns ""
; when there is no trackable window (keystrokes into our own GUI are ignored).
KeyTrack_EnsureBucket() {
    global g_KeyBucket

    ctx := TrackCtx_Get(750)
    if !ctx["win_id"]
        return ""

    minuteKey := TrackMinuteKey()
    if IsObject(g_KeyBucket) {
        if (g_KeyBucket["win_id"] = ctx["win_id"] && g_KeyBucket["minute_key"] = minuteKey)
            return g_KeyBucket
        KeyTrack_FlushBucket()
    }

    g_KeyBucket := KeyTrack_NewBucket(ctx)
    return g_KeyBucket
}

KeyTrack_FlushBucket() {
    global g_KeyBucket

    if !IsObject(g_KeyBucket)
        return false

    b := g_KeyBucket
    g_KeyBucket := ""

    if (b["keystrokes"] = 0 && b["clips"].Length = 0)
        return false

    try {
        text := b["text"]
        cats := KeyTrack_Categorize(text)

        ; Rough WPM: 5 chars per "word" over 60s.
        wpm := Round((StrLen(RegExReplace(text, "[\r\n\t]", " ")) / 5), 1)

        snap := Map(
            "win_id", b["win_id"],
            "app_id", b["app_id"],
            "minute_key", b["minute_key"],
            "start_ts", b["start_ts"],
            "end_ts", TrackTS(),
            "keystrokes", b["keystrokes"],
            "raw_stream", b["raw"],
            "text_typed", text,
            "hotkeys", TrackArrayJoin(b["hotkeys"], " "),
            "strings", cats["strings"],
            "sentences", cats["sentences"],
            "code_snips", cats["code"],
            "clips", TrackArrayJoin(b["clips"], "`n"),
            "wpm", wpm
        )
        TrackDB_AddKeySnapshot(snap)

        for combo, n in b["hotkeyCounts"]
            TrackDB_BumpHotkey(b["win_id"], b["app_id"], combo, n)
    } catch as err {
        TrackLogError("KeyTrack_FlushBucket", err)
        return false
    }
    return true
}

; ═══════════════════════════════════════════════════════════════════════════════
; HOOK CALLBACKS
; ═══════════════════════════════════════════════════════════════════════════════

; A printable character was produced. `char` is the resolved glyph.
KeyTrack_OnChar(ih, char) {
    global g_KeyMaskDigits, g_KeyLastCharTick

    b := KeyTrack_EnsureBucket()
    if !IsObject(b)
        return

    ; Skip characters emitted while Ctrl/Alt/Win is held - those are chords,
    ; handled (and counted) in OnKeyDown, and would otherwise pollute the text.
    if (GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P") || GetKeyState("LWin", "P")
        || GetKeyState("RWin", "P"))
        return

    ; Control characters (Enter -> `r, Tab, Backspace ...) are recorded by
    ; OnKeyDown with proper tokens; skip them here to avoid double-counting.
    if (Ord(char) < 32)
        return

    if (g_KeyMaskDigits && char ~= "\d")
        char := "#"

    b["text"] := b["text"] . char
    b["raw"] := b["raw"] . char
    b["keystrokes"] := b["keystrokes"] + 1
    g_KeyLastCharTick := A_TickCount

    if (b["minute_key"] != TrackMinuteKey())
        KeyTrack_FlushBucket()
}

; Any key went down. Used for non-printing keys and to detect chords.
KeyTrack_OnKeyDown(ih, vk, sc) {
    b := KeyTrack_EnsureBucket()
    if !IsObject(b)
        return

    name := ""
    try name := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if (name = "")
        try name := GetKeyName("vk" . Format("{:x}", vk))
    if (name = "")
        return

    lname := StrLower(name)

    ; Modifiers by themselves are not events; they qualify the next key.
    if (lname ~= "^(l|r)?(control|ctrl|alt|shift|win)$")
        return

    ctrl := GetKeyState("Ctrl", "P")
    alt := GetKeyState("Alt", "P")
    win := GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
    shift := GetKeyState("Shift", "P")

    isChord := ctrl || alt || win

    ; ─── Chord (hotkey) ──────────────────────────────────────────────────────
    if isChord {
        combo := (ctrl ? "^" : "") . (alt ? "!" : "") . (win ? "#" : "")
               . (shift ? "+" : "") . KeyTrack_KeyToken(name)
        b["hotkeys"].Push(combo)
        b["raw"] := b["raw"] . " " . combo . " "
        b["keystrokes"] := b["keystrokes"] + 1
        if !b["hotkeyCounts"].Has(combo)
            b["hotkeyCounts"][combo] := 0
        b["hotkeyCounts"][combo] := b["hotkeyCounts"][combo] + 1
        return
    }

    ; ─── Non-printing navigation / editing keys ─────────────────────────────
    ; Printable keys are handled by OnChar; only record the ones OnChar misses.
    if KeyTrack_IsPrintable(vk, name)
        return

    token := "{" . name . "}"
    b["raw"] := b["raw"] . token
    b["keystrokes"] := b["keystrokes"] + 1

    ; Newlines belong in the reconstructed text so sentence splitting works.
    if (lname = "enter" || lname = "return" || lname = "numpadenter")
        b["text"] := b["text"] . "`n"
    else if (lname = "tab")
        b["text"] := b["text"] . "`t"
    ; Backspace trims the reconstructed text so it mirrors what was actually left.
    else if (lname = "backspace" && StrLen(b["text"]))
        b["text"] := SubStr(b["text"], 1, StrLen(b["text"]) - 1)

    if (b["minute_key"] != TrackMinuteKey())
        KeyTrack_FlushBucket()
}

; True when the key normally yields a character (so OnChar will handle it).
KeyTrack_IsPrintable(vk, name) {
    ; Letters / digits / oem punctuation - single character names.
    if (StrLen(name) = 1)
        return true
    if (name ~= "i)^Numpad\d$")
        return true
    if (name ~= "i)^(Space)$")
        return true
    return false
}

; Normalise a key name into a Send-style token for the raw stream.
KeyTrack_KeyToken(name) {
    if (StrLen(name) = 1)
        return StrLower(name)
    return "{" . name . "}"
}

; ═══════════════════════════════════════════════════════════════════════════════
; CLIPBOARD
; ═══════════════════════════════════════════════════════════════════════════════

KeyTrack_OnClipboard(dataType) {
    global g_KeyClipMax, g_KeyBucket

    ; 1 = plain text. Other types (files/images) are noted but not stored raw.
    if (dataType != 1)
        return

    content := ""
    try content := A_Clipboard
    if (content = "" || StrLen(content) < 1)
        return
    if (StrLen(content) > g_KeyClipMax)
        content := SubStr(content, 1, g_KeyClipMax)

    ctx := TrackCtx_Get(1500)
    kind := KeyTrack_ClipKind(content)

    try TrackDB_AddClip(ctx["win_id"], ctx["app_id"], content, kind)
    catch as err
        TrackLogError("KeyTrack_OnClipboard", err)

    ; Fold a short preview into the active key bucket.
    if IsObject(g_KeyBucket)
        g_KeyBucket["clips"].Push("[" . kind . "] " . TrackEllipsis(content, 160))
}

; Heuristic classification of clipboard text.
KeyTrack_ClipKind(text) {
    t := Trim(text)
    if (t ~= "i)^https?://")
        return "url"
    if (t ~= "i)^[\w.+-]+@[\w-]+\.\w+$")
        return "email"
    if (t ~= "^[\d\s().+-]{7,}$" && (StrLen(RegExReplace(t, "\D")) >= 7))
        return "phone"
    if KeyTrack_LooksLikeCode(text)
        return "code"
    if (InStr(text, "`n"))
        return "multiline"
    return "text"
}

; ═══════════════════════════════════════════════════════════════════════════════
; CATEGORISATION (on flush)
; ═══════════════════════════════════════════════════════════════════════════════

; Split a minute's reconstructed text into strings / sentences / code lines.
KeyTrack_Categorize(text) {
    result := Map("strings", "", "sentences", "", "code", "")
    if (text = "")
        return result

    ; ─── Strings: distinct whitespace-delimited words, in order ─────────────
    words := []
    seen := Map()
    for w in StrSplit(RegExReplace(text, "[\r\n\t]", " "), " ") {
        w := Trim(w)
        if (w = "")
            continue
        if !seen.Has(w) {
            seen[w] := true
            words.Push(w)
        }
    }
    result["strings"] := TrackArrayJoin(words, " ")

    ; ─── Sentences: split on terminators and newlines, keep substantial ones ─
    sentences := []
    for chunk in StrSplit(text, "`n") {
        for s in KeyTrack_SplitSentences(chunk) {
            s := Trim(s)
            if (StrLen(s) >= 12 && InStr(s, " "))
                sentences.Push(s)
        }
    }
    result["sentences"] := TrackArrayJoin(sentences, "`n")

    ; ─── Code: lines that trip the code heuristic ───────────────────────────
    codeLines := []
    for line in StrSplit(text, "`n") {
        line := RegExReplace(line, "\s+$")
        if (Trim(line) != "" && KeyTrack_LooksLikeCode(line))
            codeLines.Push(line)
    }
    result["code"] := TrackArrayJoin(codeLines, "`n")

    return result
}

KeyTrack_SplitSentences(text) {
    out := []
    cur := ""
    Loop Parse, text {
        cur .= A_LoopField
        if (A_LoopField = "." || A_LoopField = "!" || A_LoopField = "?") {
            out.Push(cur)
            cur := ""
        }
    }
    if (Trim(cur) != "")
        out.Push(cur)
    return out
}

; Heuristic: does a line read as source code rather than prose?
KeyTrack_LooksLikeCode(line) {
    t := Trim(line)
    if (t = "")
        return false

    ; Strong structural signals.
    if (t ~= "[;{}]\s*$")                                   ; ends in ; { }
        return true
    if (t ~= "i)^\s*(function|def|class|import|export|const|let|var|public|private|return|if|for|while|foreach|elseif|else|switch|case|include|require|package|namespace|struct|enum|interface|async|await|use|from|module)\b")
        return true
    if (t ~= "[\w\])]\s*(==|!=|===|=>|->|:=|\+=|-=|\|\||&&|::)\s*")   ; operators
        return true
    if (t ~= "^\s*[\w$.]+\s*\(.*\)\s*[;{]?\s*$")            ; a call / signature
        return true
    if (t ~= "^\s*(#|//|/\*|--)\s")                          ; a code comment
        return true
    if (t ~= "^\s*[<]/?[a-zA-Z][\w-]*")                     ; a markup tag
        return true

    ; Symbol density: prose rarely exceeds ~25% punctuation.
    total := StrLen(t)
    if (total >= 6) {
        symbols := StrLen(RegExReplace(t, "[\w\s]"))
        if (symbols / total > 0.25 && (InStr(t, "(") || InStr(t, "{") || InStr(t, "[")
            || InStr(t, "=") || InStr(t, ";")))
            return true
    }
    return false
}

; ═══════════════════════════════════════════════════════════════════════════════
; QUERIES
; ═══════════════════════════════════════════════════════════════════════════════

KeyTrack_Snapshots(winId, limit := 200) {
    db := TrackDB()
    if !db
        return []
    if winId {
        return db.Query("SELECT * FROM key_snapshot WHERE win_id=? "
                      . "ORDER BY minute_key DESC LIMIT ?", winId, limit)
    }
    return db.Query("SELECT k.*, w.name AS win_name FROM key_snapshot k "
                  . "JOIN win w ON w.id=k.win_id ORDER BY k.minute_key DESC LIMIT ?", limit)
}

KeyTrack_TopHotkeys(winId := 0, limit := 100) {
    db := TrackDB()
    if !db
        return []
    if winId {
        return db.Query("SELECT combo, count, last_ts FROM hotkey_stat WHERE win_id=? "
                      . "ORDER BY count DESC LIMIT ?", winId, limit)
    }
    return db.Query("SELECT combo, SUM(count) AS count, MAX(last_ts) AS last_ts "
                  . "FROM hotkey_stat GROUP BY combo ORDER BY count DESC LIMIT ?", limit)
}

KeyTrack_RecentClips(limit := 200, winId := 0) {
    db := TrackDB()
    if !db
        return []
    if winId {
        return db.Query("SELECT c.*, w.name AS win_name FROM clip_history c "
                      . "LEFT JOIN win w ON w.id=c.win_id WHERE c.win_id=? "
                      . "ORDER BY c.id DESC LIMIT ?", winId, limit)
    }
    return db.Query("SELECT c.*, w.name AS win_name FROM clip_history c "
                  . "LEFT JOIN win w ON w.id=c.win_id ORDER BY c.id DESC LIMIT ?", limit)
}

; ═══════════════════════════════════════════════════════════════════════════════
; STATUS
; ═══════════════════════════════════════════════════════════════════════════════

KeyTrack_StatusLine() {
    global g_KeyTrackOn, g_KeyBucket
    if !g_KeyTrackOn
        return "Key tracking: OFF"
    if !IsObject(g_KeyBucket)
        return "Key tracking: ON (waiting for keystrokes)"
    return "Key tracking: " . g_KeyBucket["keystrokes"] . " keys, "
         . g_KeyBucket["hotkeys"].Length . " hotkeys this minute"
}
