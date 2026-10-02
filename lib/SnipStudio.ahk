; ═══════════════════════════════════════════════════════════════════════════════
; SnipStudio.ahk - Repeatable region snips, OCR with a correction memory
; ═══════════════════════════════════════════════════════════════════════════════
; Built for capturing the same rectangle over and over - the question pane of an
; online test, a fixed panel in an app - reading it, and being told when the
; reading was wrong.
;
;   Ctrl+Shift+1   first press sets the region; every press after captures it,
;                  runs OCR and shows the result for a yes/no verdict
;   Ctrl+Shift+2   view the last snip: image plus every representation of it
;   Ctrl+Shift+3   redraw the region
;
; ABOUT "TEACHING" THE OCR ENGINE
; Windows.Media.Ocr is a sealed engine: it cannot be retrained, and no correction
; can be fed back into it. What a correction CAN do is drive a layer in front of
; it, which is what this module builds:
;
;   1. EXACT RECALL      the corrected text is stored against the image's
;                        perceptual signature, so an identical snip returns the
;                        verified text immediately, with no OCR at all
;   2. LEARNED FIXES     each correction is diffed against the raw reading and
;                        the differing tokens are stored as substitutions
;                        ("rn"->"m", "0"->"O"). Repeat offenders are applied
;                        automatically to later readings
;   3. BEST VARIANT      the same crop is read at several scales; whichever
;                        variant has historically matched accepted text wins
;
; The engine never improves, but the answers do - and for a fixed region that is
; the same thing in practice.
;
; Every snip, correction and rule lives in the tracking database plus
; data\snips\, both gitignored.
; ═══════════════════════════════════════════════════════════════════════════════

global g_SnipRegion := ""          ; Map(x,y,w,h) or "" when unset
global g_SnipLast := ""            ; Map of the most recent snip
global g_SnipReviewGui := "", g_SnipViewGui := ""
global g_SnipSchemaReady := false

; ═══════════════════════════════════════════════════════════════════════════════
; STORAGE
; ═══════════════════════════════════════════════════════════════════════════════

Snip_Schema() {
    global g_SnipSchemaReady
    if g_SnipSchemaReady
        return true
    db := TrackDB()
    if !db
        return false
    try {
        db.Exec("CREATE TABLE IF NOT EXISTS snip ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT,"
              . "ts TEXT, x INTEGER, y INTEGER, w INTEGER, h INTEGER,"
              . "image_path TEXT, signature TEXT,"
              . "ocr_raw TEXT,"          ; exactly what the engine returned
              . "ocr_text TEXT,"         ; after learned fixes / after correction
              . "accepted INTEGER DEFAULT 0,"
              . "corrected INTEGER DEFAULT 0,"
              . "variant TEXT, note TEXT)")
        db.Exec("CREATE INDEX IF NOT EXISTS ix_snip_sig ON snip(signature)")
        ; Learned token substitutions, strongest (most hits) applied first.
        db.Exec("CREATE TABLE IF NOT EXISTS ocr_fix ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT,"
              . "wrong TEXT NOT NULL, right TEXT NOT NULL,"
              . "hits INTEGER DEFAULT 1, last_ts TEXT,"
              . "UNIQUE(wrong, right))")
        db.Exec("CREATE TABLE IF NOT EXISTS snip_setting ("
              . "key TEXT PRIMARY KEY, value TEXT)")
    } catch as err {
        TrackLogError("Snip_Schema", err)
        return false
    }
    g_SnipSchemaReady := true
    return true
}

Snip_SetSetting(key, value) {
    if !Snip_Schema()
        return
    TrackDB().Run("INSERT INTO snip_setting(key,value) VALUES(?,?) "
                . "ON CONFLICT(key) DO UPDATE SET value=excluded.value", key, value)
}

Snip_GetSetting(key, default := "") {
    if !Snip_Schema()
        return default
    v := TrackDB().Scalar("SELECT value FROM snip_setting WHERE key=?", key)
    return (v = "" ? default : v)
}

Snip_Dir() {
    global DATA_DIR
    d := DATA_DIR . "\snips"
    if !DirExist(d) {
        try DirCreate(d)
    }
    return d
}

; ═══════════════════════════════════════════════════════════════════════════════
; REGION
; ═══════════════════════════════════════════════════════════════════════════════

; The remembered rectangle, restored from the database so it survives a restart.
Snip_Region() {
    global g_SnipRegion
    if IsObject(g_SnipRegion)
        return g_SnipRegion
    saved := Snip_GetSetting("region")
    if (saved != "") {
        p := StrSplit(saved, ",")
        if (p.Length = 4 && Integer(p[3]) > 0 && Integer(p[4]) > 0) {
            g_SnipRegion := Map("x", Integer(p[1]), "y", Integer(p[2])
                              , "w", Integer(p[3]), "h", Integer(p[4]))
            return g_SnipRegion
        }
    }
    return ""
}

; Drag out a new rectangle. Returns true when one was set.
Snip_PickRegion(thenCapture := false) {
    global g_SnipRegion
    sel := ""
    try sel := QuickOCR_SelectRegion()          ; the shared drag-select overlay
    if (!IsObject(sel) || !sel.Count) {
        ShowStatus("Snip region unchanged", "wait")
        return false
    }
    g_SnipRegion := sel
    Snip_SetSetting("region", sel["x"] . "," . sel["y"] . "," . sel["w"] . "," . sel["h"])
    ShowStatus("Snip region set: " . sel["w"] . " x " . sel["h"]
             . " at " . sel["x"] . "," . sel["y"] . "  -  Ctrl+Shift+1 captures it", "ok")
    if thenCapture
        Snip_Capture()
    return true
}

; ═══════════════════════════════════════════════════════════════════════════════
; CAPTURE + READ
; ═══════════════════════════════════════════════════════════════════════════════

; Ctrl+Shift+1. With no region yet, the first press only sets one.
Snip_Hotkey() {
    if (Snip_GetSetting("hotkey", "1") != "1") {
        ShowStatus("Ctrl+Shift+1 is switched off in Snip settings", "wait")
        return
    }
    if !IsObject(Snip_Region()) {
        ShowStatus("No snip region yet - drag one now", "wait")
        Snip_PickRegion(false)
        return
    }
    Snip_Capture()
}

Snip_Capture() {
    global g_SnipLast
    region := Snip_Region()
    if !IsObject(region) {
        Snip_PickRegion(false)
        return
    }
    if !Snip_Schema() {
        ShowStatus("Tracking database unavailable", "fail")
        return
    }

    ; Show what is about to be grabbed, then let the outline clear so it cannot
    ; appear in the capture itself.
    Snip_FlashRegion(region)

    path := Snip_Dir() . "\snip_" . FormatTime(A_Now, "yyyyMMdd_HHmmss") . ".png"
    if !Snip_SaveRegion(region, path) {
        ShowStatus("Could not capture that region", "fail")
        return
    }

    signature := ""
    try signature := Snap_VisualSignature(path)

    ; 1. Exact recall - this very image has been verified before.
    known := Snip_RecallBySignature(signature)
    if (known != "") {
        g_SnipLast := Map("path", path, "region", region, "raw", known, "text", known
                        , "signature", signature, "variant", "recalled", "id", 0)
        g_SnipLast["id"] := Snip_Store(g_SnipLast, 1, 0)
        A_Clipboard := known
        ShowStatus("Recalled verified text for an identical snip (no OCR needed)", "ok")
        Snip_Review(g_SnipLast, true)
        return
    }

    ; 2. Read it, trying a few scales and keeping the most substantial result.
    best := Snip_ReadBest(path)
    raw := best["text"]
    fixed := Snip_ApplyFixes(raw)

    g_SnipLast := Map("path", path, "region", region, "raw", raw, "text", fixed
                    , "signature", signature, "variant", best["variant"], "id", 0)
    g_SnipLast["id"] := Snip_Store(g_SnipLast, 0, 0)
    A_Clipboard := fixed

    ; Smart parsing: one capture of a numbered worksheet is several questions,
    ; each of which wants its own answer.
    if (Snip_GetSetting("parse", "1") = "1") {
        items := SnipParse_Items(fixed)
        if items.Length {
            res := Qa_StoreItems(items, g_SnipLast["id"], path)
            g_SnipLast["parsed"] := items
            ShowStatus("Parsed " . items.Length . " question(s): "
                     . res["added"] . " new, " . res["updated"] . " already known"
                     . (res["improved"] ? ", " . res["improved"] . " filled out further" : "")
                     , "ok")
        }
    }
    Snip_Review(g_SnipLast, false)
}

; Save one screen rectangle as PNG. Returns true on success.
Snip_SaveRegion(region, path) {
    ; Every handle starts assigned: a throw part-way through must still leave
    ; the cleanup below with something valid to look at.
    ok := false, pToken := 0, pBitmap := 0
    try {
        pToken := Gdip_Startup()
        pBitmap := Gdip_BitmapFromScreen(region["x"] . "|" . region["y"]
                                       . "|" . region["w"] . "|" . region["h"])
        if pBitmap {
            ok := (Gdip_SaveBitmapToFile(pBitmap, path) = 0)
            Gdip_DisposeImage(pBitmap)
        }
    } catch as err {
        TrackLogError("Snip_SaveRegion", err)
    }
    if pToken
        try Gdip_Shutdown(pToken)
    return ok && FileExist(path)
}

; Join an OCR result's lines with real newlines, preserving the layout.
Snip_LinesFromResult(res) {
    if !IsObject(res)
        return ""
    out := ""
    try {
        for , line in res.Lines {
            s := Trim(line.Text)
            if (s != "")
                out .= (out = "" ? "" : "`n") . s
        }
    }
    ; Fall back to the flat property if the line list is unavailable.
    if (out = "") {
        try out := res.Text
    }
    return out
}

; Small text reads better enlarged, but over-scaling invents characters, so try
; a few and keep whichever returns the most usable text.
Snip_ReadBest(path) {
    best := Map("text", "", "variant", "none", "score", -1)
    for , v in [Map("n", "scale2", "o", {scale: 2})
              , Map("n", "scale3", "o", {scale: 3})
              , Map("n", "scale2gray", "o", {scale: 2, grayscale: 1})] {
        t := ""
        ; Read line by line rather than taking .Text. The engine's flat Text
        ; property joins the whole page into one run, which destroys exactly the
        ; structure that matters here - a list of terms, one per line, arrives
        ; as an unbroken paragraph and no parser can recover the boundaries.
        try t := Snip_LinesFromResult(OCR.FromFile(path, v["o"]))
        t := Trim(t)
        if (t = "")
            continue
        ; Prefer more recognised words, not merely more characters.
        words := 0
        for , w in StrSplit(RegExReplace(t, "[^A-Za-z0-9]+", " "), " ")
            if (StrLen(w) >= 2)
                words++
        score := words * 10 + StrLen(t)
        if (score > best["score"])
            best := Map("text", t, "variant", v["n"], "score", score)
    }
    return best
}

; ═══════════════════════════════════════════════════════════════════════════════
; THE CORRECTION MEMORY
; ═══════════════════════════════════════════════════════════════════════════════

Snip_Store(snip, accepted, corrected) {
    if !Snip_Schema()
        return 0
    db := TrackDB()
    r := snip["region"]
    db.Run("INSERT INTO snip(ts,x,y,w,h,image_path,signature,ocr_raw,ocr_text,"
         . "accepted,corrected,variant) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)"
         , FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"), r["x"], r["y"], r["w"], r["h"]
         , snip["path"], snip["signature"], snip["raw"], snip["text"]
         , accepted, corrected, snip["variant"])
    return db.LastInsertId()
}

; Verified text for an image that looks like one already confirmed.
Snip_RecallBySignature(signature) {
    if (signature = "" || !Snip_Schema())
        return ""
    db := TrackDB()
    try {
        r := db.QueryRow("SELECT ocr_text FROM snip WHERE signature=? AND accepted=1 "
                       . "AND ocr_text<>'' ORDER BY id DESC LIMIT 1", signature)
        if r.Count
            return r["ocr_text"]
    }
    return ""
}

; Record the verdict. When the reading was wrong, `truth` is what it should have
; said; the difference between the two becomes reusable substitution rules.
Snip_Accept(snipId, raw, truth, wasCorrected) {
    if !Snip_Schema()
        return
    db := TrackDB()
    try db.Run("UPDATE snip SET ocr_text=?, accepted=1, corrected=? WHERE id=?"
             , truth, wasCorrected ? 1 : 0, snipId)
    if wasCorrected
        Snip_LearnFixes(raw, truth)
}

; Diff the raw reading against the truth token by token. Tokens that changed
; become substitution candidates; the ones that keep recurring earn their place.
Snip_LearnFixes(raw, truth) {
    a := Snip_Tokens(raw)
    b := Snip_Tokens(truth)
    ; Only align when the token counts match. A different count means words were
    ; merged or split, which token substitution cannot express safely.
    if (a.Length != b.Length || a.Length = 0)
        return 0
    db := TrackDB()
    learned := 0
    now := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    for i, wrong in a {
        right := b[i]
        if (wrong = right || wrong = "" || right = "")
            continue
        ; Wildly different tokens are a misread of a whole word, not a glyph
        ; confusion worth generalising.
        if (Abs(StrLen(wrong) - StrLen(right)) > 3)
            continue
        try {
            db.Run("INSERT INTO ocr_fix(wrong,right,hits,last_ts) VALUES(?,?,1,?) "
                 . "ON CONFLICT(wrong,right) DO UPDATE SET hits=hits+1, last_ts=excluded.last_ts"
                 , wrong, right, now)
            learned++
        } catch as err {
            TrackLogError("Snip_LearnFixes", err)
        }
    }
    return learned
}

Snip_Tokens(s) {
    out := []
    for , t in StrSplit(Trim(RegExReplace(s, "\s+", " ")), " ")
        if (t != "")
            out.Push(t)
    return out
}

; Apply substitutions that have been confirmed more than once, longest first so
; a specific rule wins over a shorter overlapping one.
Snip_ApplyFixes(text) {
    if (text = "" || !Snip_Schema())
        return text
    db := TrackDB()
    rows := []
    try rows := db.Query("SELECT wrong,right FROM ocr_fix WHERE hits>=2 "
                       . "ORDER BY LENGTH(wrong) DESC, hits DESC LIMIT 400")
    for r in rows {
        ; Whole-token replacement only - substring replacement would corrupt
        ; words that merely contain the sequence.
        text := RegExReplace(text, "(?<![\w])" . Snip_Esc(r["wrong"]) . "(?![\w])", r["right"])
    }
    return text
}

Snip_Esc(s) {
    return RegExReplace(s, "([\.\*\?\+\[\]\{\}\(\)\|\^\$])", "\$1")
}

Snip_FixCount() {
    if !Snip_Schema()
        return 0
    v := TrackDB().Scalar("SELECT COUNT(*) FROM ocr_fix WHERE hits>=2")
    return IsInteger(v) ? Integer(v) : 0
}

; ═══════════════════════════════════════════════════════════════════════════════
; REVIEW - was the reading right?
; ═══════════════════════════════════════════════════════════════════════════════

Snip_Review(snip, recalled := false) {
    global g_SnipReviewGui
    if IsObject(g_SnipReviewGui) {
        try g_SnipReviewGui.Destroy()
        g_SnipReviewGui := ""
    }
    g := Gui("+AlwaysOnTop +Resize", "Snip - is this reading correct?")
    g.MarginX := 10, g.MarginY := 10

    g.Add("Picture", "x10 y10 w560 h180 Border vSnipPic", snip["path"])
    note := recalled
        ? "Recalled from a previously verified snip - no OCR was run."
        : "Read with " . snip["variant"] . ". "
        . (Snip_FixCount() ? Snip_FixCount() . " learned fix(es) applied. " : "")
        . "Text is on the clipboard."
    g.Add("Text", "x10 y196 w560 cGray vSnipNote", note)

    g.Add("Text", "x10 y218 w560", "Text (edit it here if it is wrong):")
    ed := g.Add("Edit", "x10 y236 w560 h150 Multi VScroll vSnipText", snip["text"])
    ed.SetFont("s10", "Consolas")

    g.Add("Button", "x10 y394 w150 h30 Default vSnipYes", "Yes - correct")
        .OnEvent("Click", (*) => Snip_Verdict(g, snip, true))
    g.Add("Button", "x168 y394 w170 h30 vSnipNo", "No - save my correction")
        .OnEvent("Click", (*) => Snip_Verdict(g, snip, false))
    g.Add("Button", "x346 y394 w110 h30 vSnipRedo", "Re-read")
        .OnEvent("Click", (*) => Snip_Reread(g, snip))
    g.Add("Button", "x462 y394 w108 h30 vSnipForms", "All forms")
        .OnEvent("Click", (*) => Snip_ViewForms(snip))

    g.OnEvent("Close", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.OnEvent("Size", Snip_ReviewResize)
    g_SnipReviewGui := g
    g.Show("w580 h436")
}

Snip_ReviewResize(g, minMax, w, h) {
    if (minMax = -1)
        return
    try {
        g["SnipPic"].Move(10, 10, w - 20, Max(90, Integer(h * 0.42)))
        py := 10 + Max(90, Integer(h * 0.42))
        g["SnipNote"].Move(10, py + 6, w - 20)
        g["SnipText"].Move(10, py + 46, w - 20, Max(60, h - py - 46 - 52))
        by := h - 42
        g["SnipYes"].Move(10, by)
        g["SnipNo"].Move(168, by)
        g["SnipRedo"].Move(346, by)
        g["SnipForms"].Move(462, by)
    }
}

Snip_Verdict(g, snip, correct) {
    final := ""
    try final := g["SnipText"].Value
    final := Trim(final, " `t`r`n")
    if (final = "") {
        ShowStatus("Nothing to save - the text box is empty", "fail")
        return
    }
    wasCorrected := !correct || (final != snip["text"])
    Snip_Accept(snip["id"], snip["raw"], final, wasCorrected)
    A_Clipboard := final
    if wasCorrected {
        learned := Snip_LearnFixes(snip["raw"], final)
        ShowStatus("Correction saved" . (learned ? " - " . learned . " substitution(s) learned" : "")
                 . ". An identical snip will now return this text directly.", "ok")
    } else {
        ShowStatus("Marked correct and remembered for identical snips", "ok")
    }
    g.Destroy()
}

Snip_Reread(g, snip) {
    best := Snip_ReadBest(snip["path"])
    try g["SnipText"].Value := Snip_ApplyFixes(best["text"])
    try g["SnipNote"].Value := "Re-read with " . best["variant"] . "."
    ShowStatus("Re-read using " . best["variant"], "ok")
}

; Ctrl+Shift+2
Snip_ViewLast() {
    global g_SnipLast
    if !IsObject(g_SnipLast) {
        ; Nothing this session - fall back to the newest stored snip.
        if Snip_Schema() {
            r := TrackDB().QueryRow("SELECT * FROM snip ORDER BY id DESC LIMIT 1")
            if r.Count {
                g_SnipLast := Map("path", r["image_path"], "raw", r["ocr_raw"]
                    , "text", r["ocr_text"], "signature", r["signature"]
                    , "variant", r["variant"], "id", r["id"]
                    , "region", Map("x", r["x"], "y", r["y"], "w", r["w"], "h", r["h"]))
            }
        }
    }
    if !IsObject(g_SnipLast) {
        ShowStatus("No snips yet - press Ctrl+Shift+1", "wait")
        return
    }
    Snip_ViewForms(g_SnipLast)
}

; ═══════════════════════════════════════════════════════════════════════════════
; ALL FORMS - the snip expressed every way it can be
; ═══════════════════════════════════════════════════════════════════════════════
; The same content in the representations other parts of this project consume:
; plain text for a person, binary/hex for a diff or a script, a FindText pattern
; for locating it on screen again, and a signature for recognising a repeat.

Snip_ViewForms(snip) {
    global g_SnipViewGui
    if IsObject(g_SnipViewGui) {
        try g_SnipViewGui.Destroy()
        g_SnipViewGui := ""
    }
    g := Gui("+Resize", "Snip - all representations")
    g.MarginX := 10, g.MarginY := 10
    g.Add("Picture", "x10 y10 w520 h150 Border vFormPic", snip["path"])
    tabs := g.Add("Tab3", "x10 y168 w520 h280 vFormTabs"
                , ["Text", "Binary (ASCII)", "Hex", "FindText", "Image base64", "Metadata"])

    txt := snip.Has("text") ? snip["text"] : ""

    tabs.UseTab(1)
    g.Add("Edit", "x20 y196 w500 h240 ReadOnly Multi VScroll vFormText", txt).SetFont("s10", "Consolas")
    tabs.UseTab(2)
    g.Add("Edit", "x20 y196 w500 h240 ReadOnly Multi VScroll vFormBin"
        , Snip_TextToBinary(txt)).SetFont("s8", "Consolas")
    tabs.UseTab(3)
    g.Add("Edit", "x20 y196 w500 h240 ReadOnly Multi VScroll vFormHex"
        , Snip_TextToHex(txt)).SetFont("s8", "Consolas")
    tabs.UseTab(4)
    g.Add("Edit", "x20 y196 w500 h240 ReadOnly Multi VScroll vFormFT"
        , Snip_FindTextPattern(snip["path"])).SetFont("s8", "Consolas")
    tabs.UseTab(5)
    g.Add("Edit", "x20 y196 w500 h240 ReadOnly Multi VScroll vFormB64"
        , Snip_FileBase64(snip["path"])).SetFont("s8", "Consolas")
    tabs.UseTab(6)
    g.Add("Edit", "x20 y196 w500 h240 ReadOnly Multi VScroll vFormMeta"
        , Snip_Metadata(snip)).SetFont("s9", "Consolas")
    tabs.UseTab(0)

    g.Add("Button", "x10 y456 w150 h26 vFormCopy", "Copy current tab")
        .OnEvent("Click", (*) => Snip_CopyCurrentForm(g))
    g.Add("Button", "x168 y456 w130 h26 vFormOpen", "Open image")
        .OnEvent("Click", (*) => Run('"' . snip["path"] . '"'))
    g.Add("Button", "x306 y456 w130 h26 vFormFolder", "Show in folder")
        .OnEvent("Click", (*) => Run('explorer.exe /select,"' . snip["path"] . '"'))
    g.Add("Button", "x444 y456 w86 h26 vFormClose", "Close").OnEvent("Click", (*) => g.Destroy())

    g.OnEvent("Close", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.OnEvent("Size", Snip_FormsResize)
    g_SnipViewGui := g
    g.Show("w540 h496")
}

Snip_FormsResize(g, minMax, w, h) {
    if (minMax = -1)
        return
    try {
        picH := Max(80, Integer(h * 0.28))
        g["FormPic"].Move(10, 10, w - 20, picH)
        g["FormTabs"].Move(10, picH + 18, w - 20, h - picH - 60)
        for , name in ["FormText", "FormBin", "FormHex", "FormFT", "FormB64", "FormMeta"]
            g[name].Move(20, picH + 46, w - 40, h - picH - 100)
        by := h - 36
        g["FormCopy"].Move(10, by)
        g["FormOpen"].Move(168, by)
        g["FormFolder"].Move(306, by)
        g["FormClose"].Move(444, by)
    }
}

Snip_CopyCurrentForm(g) {
    names := ["FormText", "FormBin", "FormHex", "FormFT", "FormB64", "FormMeta"]
    idx := 1
    try idx := g["FormTabs"].Value
    if (idx < 1 || idx > names.Length)
        idx := 1
    try {
        A_Clipboard := g[names[idx]].Value
        ShowStatus("Copied the " . names[idx] . " representation", "ok")
    }
}

; ─── representations ─────────────────────────────────────────────────────────

StrRepeat(s, n) {
    out := ""
    Loop Max(n, 0)
        out .= s
    return out
}

; Each character as 8-bit binary, eight per line with the text alongside.
Snip_TextToBinary(text) {
    if (text = "")
        return "(no text)"
    out := "", row := "", chars := "", n := 0
    for , ch in StrSplit(text) {
        code := Ord(ch)
        bits := ""
        Loop 8
            bits := Mod(code >> (A_Index - 1), 2) . bits
        row .= (row = "" ? "" : " ") . bits
        chars .= (code >= 32 && code < 127) ? ch : "."
        if (++n = 8) {
            out .= row . "  |" . chars . "`r`n"
            row := "", chars := "", n := 0
        }
    }
    if (n > 0)
        out .= row . StrRepeat(" ", (8 - n) * 9) . "  |" . chars . "`r`n"
    return out
}

Snip_TextToHex(text) {
    if (text = "")
        return "(no text)"
    out := "", row := "", chars := "", n := 0, offset := 0
    for , ch in StrSplit(text) {
        code := Ord(ch)
        row .= Format("{:02X} ", code & 0xFF)
        chars .= (code >= 32 && code < 127) ? ch : "."
        if (++n = 16) {
            out .= Format("{:08X}  ", offset) . row . " |" . chars . "|`r`n"
            offset += 16, row := "", chars := "", n := 0
        }
    }
    if (n > 0)
        out .= Format("{:08X}  ", offset) . row . StrRepeat("   ", 16 - n) . " |" . chars . "|`r`n"
    return out
}

; A FindText pattern for the snip, so this exact content can be found on screen
; again by appearance rather than by text.
Snip_FindTextPattern(path) {
    if !FileExist(path)
        return "(image missing)"
    iw := 0, ih := 0
    if !Snip_LoadImageToFindText(path, &iw, &ih)
        return "(could not load the image for fingerprinting)"
    pat := ""
    try pat := FindText().GetTextFromScreen(0, 0, iw - 1, ih - 1, "**50", 0)
    catch as err {
        TrackLogError("Snip_FindTextPattern", err)
        return "(FindText could not fingerprint this image)"
    }
    if (pat = "")
        return "(no usable pattern - the crop may be blank)"
    return pat
}

; FindText samples the screen, so the saved file is briefly drawn at 0,0 behind
; an always-on-top layer and captured from there.
Snip_LoadImageToFindText(path, &iw, &ih) {
    iw := 0, ih := 0
    ok := false
    g := Gui("-Caption +ToolWindow +AlwaysOnTop +E0x08000000")
    try {
        pic := g.Add("Picture", "x0 y0", path)
        pic.GetPos(, , &pw, &ph)
        if (pw >= 1 && ph >= 1) {
            iw := pw, ih := ph
            g.Show("x0 y0 w" . pw . " h" . ph . " NoActivate")
            Sleep(200)
            sx := 0, sy := 0, sw := pw, sh := ph
            FindText().GetBitsFromScreen(&sx, &sy, &sw, &sh, 1)
            ok := true
        }
    } catch as err {
        TrackLogError("Snip_LoadImageToFindText", err)
    }
    try g.Destroy()
    return ok
}

Snip_FileBase64(path) {
    if !FileExist(path)
        return "(image missing)"
    size := FileGetSize(path)
    if (size > 3000000)
        return "(image is " . Round(size / 1048576, 1) . " MB - too large to render as base64)"
    try {
        f := FileOpen(path, "r")
        buf := Buffer(size)
        f.RawRead(buf, size)
        f.Close()
        len := 0
        if !DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", size
                  , "UInt", 0x40000001, "Ptr", 0, "UInt*", &len)
            return "(encoding failed)"
        out := Buffer(len * 2)
        DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", size
              , "UInt", 0x40000001, "Ptr", out, "UInt*", &len)
        return StrGet(out, "UTF-16")
    } catch as err {
        TrackLogError("Snip_FileBase64", err)
        return "(encoding failed)"
    }
}

Snip_Metadata(snip) {
    r := snip.Has("region") ? snip["region"] : Map("x", 0, "y", 0, "w", 0, "h", 0)
    size := FileExist(snip["path"]) ? FileGetSize(snip["path"]) : 0
    out := "image      " . snip["path"] . "`r`n"
    out .= "bytes      " . size . "`r`n"
    out .= "region     " . r["w"] . " x " . r["h"] . " at " . r["x"] . "," . r["y"] . "`r`n"
    out .= "signature  " . (snip.Has("signature") ? snip["signature"] : "") . "`r`n"
    out .= "read with  " . (snip.Has("variant") ? snip["variant"] : "") . "`r`n"
    out .= "snip id    " . (snip.Has("id") ? snip["id"] : 0) . "`r`n`r`n"
    out .= "RAW OCR (before learned fixes)`r`n"
    out .= (snip.Has("raw") ? snip["raw"] : "") . "`r`n`r`n"
    out .= "learned substitutions in force: " . Snip_FixCount() . "`r`n"
    return out
}

; ═══════════════════════════════════════════════════════════════════════════════
; REGION FLASH - show what is about to be captured
; ═══════════════════════════════════════════════════════════════════════════════
; A brief outline around the snip area, drawn as four thin edge windows so the
; middle stays clear and nothing is tinted into the capture. It is torn down
; before the shot is taken.

Snip_FlashRegion(region, ms := 220) {
    if (Snip_GetSetting("flash", "1") != "1")
        return
    edges := []
    t := 3                                     ; outline thickness
    x := region["x"], y := region["y"], w := region["w"], h := region["h"]
    for , r in [[x - t, y - t, w + t * 2, t]   ; top
              , [x - t, y + h, w + t * 2, t]   ; bottom
              , [x - t, y - t, t, h + t * 2]   ; left
              , [x + w, y - t, t, h + t * 2]]  ; right
    {
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
        g.BackColor := "FF3B30"
        g.Show("NA x" . r[1] . " y" . r[2] . " w" . r[3] . " h" . r[4])
        try WinSetTransparent(200, g)
        edges.Push(g)
    }
    Sleep(ms)
    for , g in edges {
        try g.Destroy()
    }
    ; Let the desktop repaint before anything is captured.
    Sleep(60)
}

; ═══════════════════════════════════════════════════════════════════════════════
; SETTINGS
; ═══════════════════════════════════════════════════════════════════════════════

Snip_OpenSettings() {
    g := Gui("+AlwaysOnTop", "Snip and question settings")
    g.MarginX := 14, g.MarginY := 12

    g.Add("Text", "x14 y12 w420", "Capture (Ctrl+Shift+1)").SetFont("s10 bold")
    cbHot := g.Add("CheckBox", "x14 y36 w420 vSetHotkey"
        . (Snip_GetSetting("hotkey", "1") = "1" ? " Checked" : "")
        , "Ctrl+Shift+1 captures the region")
    cbFlash := g.Add("CheckBox", "x14 y58 w420 vSetFlash"
        . (Snip_GetSetting("flash", "1") = "1" ? " Checked" : "")
        , "Flash the region outline when capturing")
    cbParse := g.Add("CheckBox", "x14 y80 w420 vSetParse"
        . (Snip_GetSetting("parse", "1") = "1" ? " Checked" : "")
        , "Smart parsing: split a capture into separate questions")

    g.Add("Text", "x14 y112 w420", "Review roulette").SetFont("s10 bold")
    cbRoul := g.Add("CheckBox", "x14 y136 w420 vSetRoulette"
        . (Snip_GetSetting("roulette", "0") = "1" ? " Checked" : "")
        , "Periodically resurface questions that have no answer yet")
    g.Add("Text", "x30 y160 w120", "Every")
    edLo := g.Add("Edit", "x84 y157 w54 Number vSetLo", Snip_GetSetting("roulette_min", "10"))
    g.Add("Text", "x144 y160 w20", "to")
    edHi := g.Add("Edit", "x166 y157 w54 Number vSetHi", Snip_GetSetting("roulette_max", "45"))
    g.Add("Text", "x226 y160 w200", "minutes (picked at random)")

    stat := g.Add("Text", "x14 y190 w420 cGray"
        , Qa_OpenCount() . " unanswered question(s) in the bank.")

    g.Add("Button", "x14 y216 w130 h28 Default", "Save")
        .OnEvent("Click", (*) => Snip_SaveSettings(g))
    g.Add("Button", "x152 y216 w130 h28", "Ask me one now")
        .OnEvent("Click", (*) => Qa_AskNow())
    g.Add("Button", "x290 y216 w144 h28", "Question bank")
        .OnEvent("Click", (*) => Qa_OpenBank())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.Show("w448 h258")
}

Snip_SaveSettings(g) {
    Snip_SetSetting("hotkey", g["SetHotkey"].Value ? "1" : "0")
    Snip_SetSetting("flash", g["SetFlash"].Value ? "1" : "0")
    Snip_SetSetting("parse", g["SetParse"].Value ? "1" : "0")
    lo := Integer(g["SetLo"].Value != "" ? g["SetLo"].Value : 10)
    hi := Integer(g["SetHi"].Value != "" ? g["SetHi"].Value : 45)
    if (lo < 1)
        lo := 1
    if (hi < lo)
        hi := lo
    Snip_SetSetting("roulette_min", lo)
    Snip_SetSetting("roulette_max", hi)
    wantRoulette := g["SetRoulette"].Value ? true : false
    if wantRoulette
        Qa_RouletteStart()
    else
        Qa_RouletteStop()
    ShowStatus("Snip settings saved", "ok")
    g.Destroy()
}

; Restore the roulette on startup if it was left on.
Snip_RestoreState() {
    if (Snip_GetSetting("roulette", "0") = "1")
        Qa_RouletteStart()
}
