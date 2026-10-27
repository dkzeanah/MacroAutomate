; ═══════════════════════════════════════════════════════════════════════════════
; StudyIngest.ahk - Bring study material into the assistant (study-only build)
; ═══════════════════════════════════════════════════════════════════════════════
; Covers spec section 3: import lesson plans, notes, PDFs, text and markdown;
; OCR image-only PDF pages; derive concise concepts (not verbatim page dumps);
; and - when the user turns it on - read a book/PDF window on a SIDE monitor,
; detecting page changes and storing each new page as a passage with source and
; page metadata.
;
; Everything here is read-only observation of material the user chose. It never
; touches the main-monitor portal, the mouse, or the keyboard.
; ═══════════════════════════════════════════════════════════════════════════════

global g_StudyReadAlongOn := false
global g_StudyReadAlongRegion := ""       ; Map(x,y,w,h) on a side monitor
global g_StudyReadAlongSource := 0        ; source_id for the live session
global g_StudyReadAlongLastSig := ""
global g_StudyReadAlongPage := 0

; ─────────────────────────────────────────────────────────────────────────────
; FILE IMPORT
; ─────────────────────────────────────────────────────────────────────────────
; Import one file. Dispatches on extension. Returns Map(ok, sourceId, passages,
; concepts, detail).
Study_ImportFile(path, course := "", topic := "") {
    out := Map("ok", false, "sourceId", 0, "passages", 0, "concepts", 0, "detail", "")
    if !FileExist(path) {
        out["detail"] := "File not found: " . path
        return out
    }
    SplitPath(path, &fname, , &ext)
    ext := StrLower(ext)
    if !RegExMatch(ext, "i)^(pdf|txt|text|md|markdown)$") {
        out["detail"] := "Supported imports: PDF, text and Markdown. Export this document as PDF or text first."
        return out
    }
    kind := (ext = "pdf") ? "pdf"
          : (ext = "md" || ext = "markdown") ? "markdown"
          : "text"
    bytes := 0
    try bytes := FileGetSize(path)

    if (ext = "pdf")
        return Study_ImportPdf(path, fname, course, topic, bytes)

    ; text / markdown / anything readable as UTF-8 text
    text := ""
    try text := FileRead(path, "UTF-8")
    catch {
        try text := FileRead(path)
    }
    if (Trim(text) = "") {
        out["detail"] := "No readable text in " . fname
        return out
    }
    srcId := Study_AddSource(kind, fname, path, course, topic, bytes, 0)
    res := Study_IngestText(srcId, text, 0)
    out["ok"] := true
    out["sourceId"] := srcId
    out["passages"] := res["passages"]
    out["concepts"] := res["concepts"]
    out["detail"] := fname . ": " . res["passages"] . " passage(s), "
                   . res["concepts"] . " concept(s)"
    return out
}

; Import a PDF page by page. Windows OCR handles image-only pages; text pages
; still come back through the same OCR path, which keeps layout consistent.
Study_ImportPdf(path, fname, course, topic, bytes) {
    out := Map("ok", false, "sourceId", 0, "passages", 0, "concepts", 0, "detail", "")
    pageCount := 0
    try pageCount := OCR.GetPdfPageCount(path)
    catch as err {
        out["detail"] := "Could not open PDF: " . err.Message
        return out
    }
    if (pageCount < 1) {
        out["detail"] := "PDF has no pages"
        return out
    }
    srcId := Study_AddSource("pdf", fname, path, course, topic, bytes, pageCount)
    totalP := 0, totalC := 0
    ; Cap very large PDFs per import so a 900-page book does not freeze the UI;
    ; re-import replaces the passages and reads from page 1 again.
    maxPages := Integer(Study_GetSetting("pdf_max_pages", "60"))
    endPage := Min(pageCount, maxPages)
    Loop endPage {
        pageNo := A_Index
        text := ""
        try {
            res := OCR.FromPDFPage(path, pageNo, {scale: 2})
            text := Study_LinesFromOcr(res)
        } catch as err {
            TrackLogError("Study_ImportPdf page " . pageNo, err)
        }
        if (Trim(text) = "")
            continue
        r := Study_IngestText(srcId, text, pageNo)
        totalP += r["passages"]
        totalC += r["concepts"]
    }
    out["ok"] := true
    out["sourceId"] := srcId
    out["passages"] := totalP
    out["concepts"] := totalC
    out["detail"] := fname . ": read " . endPage . "/" . pageCount . " page(s), "
                   . totalP . " passage(s), " . totalC . " concept(s)"
                   . (pageCount > endPage ? " (limited by pdf_max_pages; re-import restarts at page 1)" : "")
    return out
}

; Paste-in / typed notes become a source too.
Study_ImportNotes(title, text, course := "", topic := "") {
    if (Trim(text) = "")
        return Map("ok", false, "detail", "Nothing to import")
    srcId := Study_AddSource("note", title != "" ? title : "Pasted notes", "", course, topic, StrLen(text), 0)
    res := Study_IngestText(srcId, text, 0)
    return Map("ok", true, "sourceId", srcId, "passages", res["passages"]
             , "concepts", res["concepts"]
             , "detail", res["passages"] . " passage(s), " . res["concepts"] . " concept(s)")
}

; ─────────────────────────────────────────────────────────────────────────────
; TEXT -> PASSAGES + CONCEPTS
; ─────────────────────────────────────────────────────────────────────────────
; Split text into passages (paragraph-ish units), store each, then derive
; concepts and link co-occurring ones. Returns Map(passages, concepts).
Study_IngestText(sourceId, text, page := 0) {
    out := Map("passages", 0, "concepts", 0)
    if (!sourceId || Trim(text) = "")
        return out
    passages := Study_SplitPassages(text)
    ord := 0
    conceptIdsAll := []
    for , para in passages {
        ord++
        heading := Study_LooksLikeHeading(para) ? para : ""
        Study_AddPassage(sourceId, para, page, ord, heading)
        out["passages"]++
        ids := Study_ExtractConcepts(para, sourceId, page)
        for , cid in ids
            conceptIdsAll.Push(cid)
        out["concepts"] += ids.Length
    }
    ; Relational layer: concepts that appeared in the same import are related.
    ; Keep it bounded - only link within a modest window so a huge document does
    ; not create a quadratic blow-up of links.
    Study_LinkCooccurring(conceptIdsAll)
    return out
}

; Break text into passages: blank-line separated blocks, with over-long blocks
; split on sentence boundaries so a passage stays retrieval-sized.
Study_SplitPassages(text) {
    text := StrReplace(text, "`r`n", "`n")
    text := StrReplace(text, "`r", "`n")
    blocks := []
    for , blk in StrSplit(RegExReplace(text, "`n[ `t]*`n+", Chr(1)), Chr(1)) {
        blk := Trim(RegExReplace(blk, "[ `t]*`n[ `t]*", " "))
        if (blk = "")
            continue
        if (StrLen(blk) <= 600) {
            blocks.Push(blk)
            continue
        }
        ; Long block: pack sentences into <=600-char passages.
        cur := ""
        for , sent in Study_Sentences(blk) {
            if (StrLen(cur) + StrLen(sent) > 600 && cur != "") {
                blocks.Push(Trim(cur))
                cur := ""
            }
            cur .= (cur = "" ? "" : " ") . sent
        }
        if (Trim(cur) != "")
            blocks.Push(Trim(cur))
    }
    return blocks
}

Study_Sentences(text) {
    out := []
    for , s in StrSplit(RegExReplace(text, "([.!?])\s+", "$1" . Chr(1)), Chr(1))
        if (Trim(s) != "")
            out.Push(Trim(s))
    return out
}

Study_LooksLikeHeading(line) {
    s := Trim(line)
    if (s = "" || StrLen(s) > 80 || InStr(s, "."))
        return false
    ; Markdown heading, or a short title-case/upper line with no sentence marks.
    if RegExMatch(s, "^#{1,6}\s")
        return true
    return !InStr(s, "?") && (StrUpper(s) = s || RegExMatch(s, "^[A-Z][A-Za-z0-9 ,/&-]{2,}$"))
}

; ─────────────────────────────────────────────────────────────────────────────
; CONCEPT EXTRACTION (local heuristics; no LLM, no cost)
; ─────────────────────────────────────────────────────────────────────────────
; Derive concepts from a passage:
;   "Term: definition"                         -> definition concept
;   "X is/are/refers to/means/is defined as Y" -> definition concept
;   a markdown/colon heading                   -> topic concept (low importance)
; Importance is seeded from the pattern strength; re-seeing a concept raises it.
; Returns the concept ids touched.
Study_ExtractConcepts(passage, sourceId, page) {
    ids := []
    ; 1. "Term: definition" (short lead-in before the colon)
    if RegExMatch(passage, "^\s*([A-Z][A-Za-z0-9 /&-]{1,48}?)\s*[:\x{2013}\x{2014}-]\s+(\S.{8,})$", &m) {
        cid := Study_AddConcept(Trim(m[1]), Trim(m[2]), "definition", sourceId, page, 3)
        if cid
            ids.Push(cid)
    }
    ; 2. "X is/are/means/refers to/is defined as Y"
    pos := 1
    while (pos := RegExMatch(passage
        , "([A-Z][A-Za-z0-9 /&-]{2,48}?)\s+(?:is|are|refers to|means|is defined as|is called)\s+([a-z].{10,160}?)(?:[.;]|$)"
        , &m2, pos)) {
        term := Trim(m2[1])
        ; Skip sentence-start pronouns / filler that slipped into the capture.
        if !RegExMatch(term, "i)^(it|this|that|these|those|there|they|he|she|we|you|here)\b") {
            cid := Study_AddConcept(term, Trim(m2[2]), "definition", sourceId, page, 2)
            if cid
                ids.Push(cid)
        }
        pos += StrLen(m2[0])
        if (ids.Length >= 12)
            break
    }
    ; 3. a heading becomes a low-importance topic concept
    if (ids.Length = 0 && Study_LooksLikeHeading(passage)) {
        name := Trim(RegExReplace(passage, "^#{1,6}\s*", ""))
        if (StrLen(name) >= 3 && StrLen(name) <= 64) {
            cid := Study_AddConcept(name, "", "topic", sourceId, page, 1)
            if cid
                ids.Push(cid)
        }
    }
    return ids
}

Study_LinkCooccurring(conceptIds) {
    n := conceptIds.Length
    if (n < 2)
        return
    ; Link each concept to the next few that followed it, not all pairs.
    Loop n {
        i := A_Index
        j := i + 1
        linked := 0
        while (j <= n && linked < 4) {
            if (conceptIds[i] != conceptIds[j])
                Study_LinkConcepts(conceptIds[i], conceptIds[j], "related", 1)
            j++
            linked++
        }
    }
}

Study_LinesFromOcr(res) {
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
    if (out = "") {
        try out := res.Text
    }
    return out
}

; ─────────────────────────────────────────────────────────────────────────────
; READ-ALONG (side-monitor page watcher)
; ─────────────────────────────────────────────────────────────────────────────
; Watch a user-chosen region on a side monitor. On each tick, capture it, and
; when the visual signature has changed enough to be a new page, OCR it and
; store it as a passage under the live read-along source. Read-only.
Study_ReadAlong_PickRegion() {
    global g_StudyReadAlongRegion
    sel := ""
    try sel := QuickOCR_SelectRegion()
    if (!IsObject(sel) || !sel.Count) {
        ShowStatus("Read-along region unchanged", "wait")
        return false
    }
    g_StudyReadAlongRegion := sel
    Study_SetSetting("readalong_region", sel["x"] . "," . sel["y"] . "," . sel["w"] . "," . sel["h"])
    ShowStatus("Read-along region set: " . sel["w"] . "x" . sel["h"]
             . " at " . sel["x"] . "," . sel["y"], "ok")
    return true
}

Study_ReadAlong_Region() {
    global g_StudyReadAlongRegion
    if IsObject(g_StudyReadAlongRegion)
        return g_StudyReadAlongRegion
    saved := Study_GetSetting("readalong_region")
    if (saved != "") {
        p := StrSplit(saved, ",")
        if (p.Length = 4 && Integer(p[3]) > 0 && Integer(p[4]) > 0) {
            g_StudyReadAlongRegion := Map("x", Integer(p[1]), "y", Integer(p[2])
                                        , "w", Integer(p[3]), "h", Integer(p[4]))
            return g_StudyReadAlongRegion
        }
    }
    return ""
}

Study_ReadAlong_Start(title := "") {
    global g_StudyReadAlongOn, g_StudyReadAlongSource, g_StudyReadAlongLastSig, g_StudyReadAlongPage
    if g_StudyReadAlongOn
        return true
    region := Study_ReadAlong_Region()
    if !IsObject(region) {
        ShowStatus("Pick a read-along region first", "wait")
        return false
    }
    if !Study_Schema() {
        ShowStatus("Study database unavailable", "fail")
        return false
    }
    ; Each read-along session is its own source so pages group together.
    g_StudyReadAlongSource := Study_AddSource("readalong"
        , title != "" ? title : "Read-along " . FormatTime(A_Now, "yyyy-MM-dd HH:mm"))
    g_StudyReadAlongLastSig := ""
    g_StudyReadAlongPage := 0
    g_StudyReadAlongOn := true
    Study_SetSetting("readalong_on", "1")
    secs := Integer(Study_GetSetting("readalong_secs", "4"))
    SetTimer(Study_ReadAlong_Tick, secs * 1000)
    ShowStatus("Reading along - new pages on the side monitor will be ingested", "ok")
    return true
}

Study_ReadAlong_Stop() {
    global g_StudyReadAlongOn
    g_StudyReadAlongOn := false
    Study_SetSetting("readalong_on", "0")
    SetTimer(Study_ReadAlong_Tick, 0)
    ShowStatus("Read-along stopped", "ok")
}

Study_ReadAlong_Toggle(title := "") {
    global g_StudyReadAlongOn
    g_StudyReadAlongOn ? Study_ReadAlong_Stop() : Study_ReadAlong_Start(title)
}

Study_ReadAlong_Tick() {
    global g_StudyReadAlongOn, g_StudyReadAlongRegion, g_StudyReadAlongSource
    global g_StudyReadAlongLastSig, g_StudyReadAlongPage
    if !g_StudyReadAlongOn
        return
    region := g_StudyReadAlongRegion
    if !IsObject(region)
        return
    tmp := Study_TempDir() . "\readalong_" . A_TickCount . ".png"
    if !Snip_SaveRegion(region, tmp)      ; reuse SnipStudio's GDI+ region capture
        return
    sig := ""
    try sig := Snap_VisualSignature(tmp)
    ; New page only when the picture changed meaningfully. A small signature
    ; distance is scrolling jitter / cursor movement, not a page turn.
    isNew := (g_StudyReadAlongLastSig = "")
          || (Snap_SignatureDistance(sig, g_StudyReadAlongLastSig) >= 12)
    if !isNew {
        try FileDelete(tmp)
        return
    }
    text := ""
    try text := Study_LinesFromOcr(OCR.FromFile(tmp, {scale: 2}))
    text := Trim(Snip_ApplyFixes(text))    ; reuse the OCR correction memory
    try FileDelete(tmp)
    if (StrLen(text) < 20)                 ; too little text to be a real page
        return
    g_StudyReadAlongLastSig := sig
    g_StudyReadAlongPage++
    Study_IngestText(g_StudyReadAlongSource, text, g_StudyReadAlongPage)
    ShowStatus("Read-along: captured page " . g_StudyReadAlongPage, "ok")
}

Study_TempDir() {
    SplitPath(Photo_TempPath("tmp"),, &directory)
    return directory
}

Study_ReadAlong_RestoreState() {
    ; Resume if it was running at last shutdown and a region is remembered.
    if (Study_GetSetting("readalong_on", "0") = "1" && IsObject(Study_ReadAlong_Region()))
        Study_ReadAlong_Start()
}
