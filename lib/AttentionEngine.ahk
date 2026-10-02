; ═══════════════════════════════════════════════════════════════════════════════
; AttentionEngine.ahk - What actually held your attention, and for how long
; ═══════════════════════════════════════════════════════════════════════════════
; Opening a thousand pages in a night says almost nothing. Focus time says
; everything: on this machine 50% of all tracked active time lands in about 76
; distinct window titles out of 4,400. This module surfaces that minority.
;
; The window tracker already records one row per focus session in win_session
; (raw_title, start_ts, end_ts, duration_ms). Aggregating those per title gives
; measured signals - nothing inferred:
;
;   total_ms     how long the title held the foreground, summed
;   longest_ms   the deepest single uninterrupted stretch
;   sessions     how many separate times it was returned to
;
; PROMINENCE combines them because each alone misleads: total time favours
; anything left open, longest stretch favours a single idle, and return count
; favours tab-flipping. Something genuinely watched scores on all three.
;
;   prominence = total_minutes
;              * (1 + longest_share)     depth of the deepest stretch
;              * (1 + log2(sessions))    deliberate returns
;              * recency_decay           older days matter less
;
; WATCH TIME: for a media player or a video page the foreground time IS the
; watch time, so no extra instrumentation is needed. Reported as total watched,
; the longest single sitting, and how many sittings.
;
; Everything here reads the tracking database. Nothing is written or deleted.
; ═══════════════════════════════════════════════════════════════════════════════

global g_AttnRows := []
global g_AttnLV := "", g_AttnGui := "", g_AttnPic := "", g_AttnDetail := ""
global g_AttnStatus := "", g_AttnFrom := "", g_AttnTo := "", g_AttnMinSecs := ""
global g_AttnKind := "", g_AttnFilter := ""
global g_AttnSortKey := "score", g_AttnSortDesc := true

; ═══════════════════════════════════════════════════════════════════════════════
; MEASUREMENT
; ═══════════════════════════════════════════════════════════════════════════════

; Aggregate focus sessions per window title.
; opts: from, to (yyyy-MM-dd), minSecs, kind ("all"|"video"|"web"|"nsfw"), limit
Attn_Rank(opts := "") {
    rows := []
    db := TrackDB()
    if !db
        return rows
    if !IsObject(opts)
        opts := Map()
    dFrom := opts.Has("from") ? opts["from"] : FormatTime(DateAdd(A_Now, -7, "Days"), "yyyy-MM-dd")
    dTo := opts.Has("to") ? opts["to"] : FormatTime(A_Now, "yyyy-MM-dd")
    minSecs := opts.Has("minSecs") ? opts["minSecs"] : 60
    kind := opts.Has("kind") ? opts["kind"] : "all"
    limit := opts.Has("limit") ? opts["limit"] : 500

    sql := "SELECT s.raw_title AS title,"
         . " COUNT(*) AS sessions,"
         . " SUM(s.duration_ms) AS total_ms,"
         . " MAX(s.duration_ms) AS longest_ms,"
         . " MIN(s.start_ts) AS first_ts,"
         . " MAX(s.end_ts) AS last_ts,"
         . " (SELECT a.exe FROM app a WHERE a.id = s.app_id) AS exe"
         . " FROM win_session s"
         . " WHERE s.duration_ms > 0 AND s.raw_title IS NOT NULL AND s.raw_title <> ''"
         . "   AND s.day BETWEEN ? AND ?"
         . " GROUP BY s.raw_title"
         . " HAVING SUM(s.duration_ms) >= ?"
         . " ORDER BY total_ms DESC LIMIT ?"
    res := []
    try {
        res := db.Query(sql, dFrom, dTo, minSecs * 1000, limit)
    } catch as err {
        TrackLogError("Attn_Rank", err)
        return rows
    }

    nowStamp := A_Now
    for r in res {
        title := r["title"]
        exe := r["exe"]
        totalMs := Integer(r["total_ms"])
        longestMs := Integer(r["longest_ms"])
        sessions := Integer(r["sessions"])
        rows.Push(Map(
            "title", title,
            "exe", exe,
            "sessions", sessions,
            "total_ms", totalMs,
            "longest_ms", longestMs,
            "first_ts", r["first_ts"],
            "last_ts", r["last_ts"],
            "is_media", Attn_IsMedia(title, exe),
            "url", "",
            "score", Attn_Prominence(totalMs, longestMs, sessions, r["last_ts"], nowStamp)))
    }

    ; One batched lookup for every title's recorded URL, rather than a query per
    ; row. The adult filter consults this: a page whose title gives nothing away
    ; is still identifiable by the address that was captured with it.
    Attn_AttachUrls(rows)

    if (StrLower(kind) != "all") {
        kept := []
        for , r in rows {
            if Attn_KindMatches(kind, r["title"], r["exe"], r["url"])
                kept.Push(r)
        }
        rows := kept
    }
    Attn_SortRows(rows, "score", true)
    return rows
}

; Fill in the most recent recorded URL for every row, in chunked IN() queries.
Attn_AttachUrls(rows) {
    db := TrackDB()
    if (!db || !rows.Length)
        return
    i := 0, total := rows.Length
    urls := Map()
    while (i < total) {
        titles := [], marks := ""
        while (titles.Length < 300 && i < total) {
            i++
            titles.Push(rows[i]["title"])
            marks .= (marks = "" ? "?" : ",?")
        }
        try {
            res := db.Query("SELECT title, url FROM snap_entry"
                          . " WHERE url IS NOT NULL AND url<>'' AND title IN (" . marks . ")"
                          . " GROUP BY title", titles*)
            for r in res
                urls[StrLower(r["title"])] := r["url"]
        } catch as err {
            TrackLogError("Attn_AttachUrls", err)
        }
    }
    for , r in rows {
        k := StrLower(r["title"])
        if urls.Has(k)
            r["url"] := urls[k]
    }
}

; Weighted prominence - see the header for why each term is present.
Attn_Prominence(totalMs, longestMs, sessions, lastTs, nowStamp) {
    minutes := totalMs / 60000.0
    if (minutes <= 0)
        return 0.0
    longestShare := (totalMs > 0) ? (longestMs / totalMs) : 0      ; 0..1 depth
    returnBoost := 1 + (Log(Max(sessions, 1)) / Log(2))            ; log2(sessions)
    ; Recency: full weight today, tapering to about half after two weeks.
    ageDays := 0
    try {
        stamp := RegExReplace(lastTs, "[^0-9]")
        if (StrLen(stamp) >= 14)
            ageDays := Abs(DateDiff(nowStamp, SubStr(stamp, 1, 14), "Days"))
    }
    recency := 1 / (1 + (ageDays / 14.0))
    return Round(minutes * (1 + longestShare) * returnBoost * recency, 2)
}

; Media windows: a video player, or a browser tab showing a video page.
Attn_IsMedia(title, exe) {
    if (exe ~= "i)^(vlc|mpc-hc|mpc-be|mpv|wmplayer|potplayer|smplayer)")
        return true
    if (title ~= "i)\.(mp4|mkv|avi|webm|mov|m4v|wmv|flv|ts|mpg|mpeg)\b")
        return true
    if (title ~= "i)\b(vlc media player|picture-in-picture)\b")
        return true
    return false
}

Attn_KindMatches(kind, title, exe, url := "") {
    switch StrLower(kind) {
        case "video": return Attn_IsMedia(title, exe)
        case "web":   return (exe ~= "i)^(chrome|msedge|firefox|brave|opera|vivaldi)\.exe$")
        ; Title AND recorded address - a bare title like "(1) Facebook" hides
        ; nothing useful, but the URL captured beside it is decisive.
        case "nsfw":  return Nsfw_IsMatch(title, url)
        default:      return true
    }
}

; Watch statistics for one media title.
Attn_WatchTime(title) {
    out := Map("total_ms", 0, "longest_ms", 0, "sittings", 0, "first_ts", "", "last_ts", "")
    db := TrackDB()
    if (!db || title = "")
        return out
    try {
        r := db.QueryRow("SELECT COUNT(*) AS sittings, SUM(duration_ms) AS total_ms,"
                       . " MAX(duration_ms) AS longest_ms, MIN(start_ts) AS first_ts,"
                       . " MAX(end_ts) AS last_ts"
                       . " FROM win_session WHERE raw_title=? AND duration_ms>0", title)
        if r.Count {
            out["total_ms"] := Integer(r["total_ms"] != "" ? r["total_ms"] : 0)
            out["longest_ms"] := Integer(r["longest_ms"] != "" ? r["longest_ms"] : 0)
            out["sittings"] := Integer(r["sittings"] != "" ? r["sittings"] : 0)
            out["first_ts"] := r["first_ts"]
            out["last_ts"] := r["last_ts"]
        }
    } catch as err {
        TrackLogError("Attn_WatchTime", err)
    }
    return out
}

; Snapshots captured while this exact title held focus - the way back to the
; page, with whatever URL was recorded live at capture time.
Attn_SnapshotsFor(title, limit := 25) {
    db := TrackDB()
    if (!db || title = "")
        return []
    try {
        return db.Query("SELECT id, ts, image_path, url, url_source, title, search_query"
                      . " FROM snap_entry WHERE title=? ORDER BY id DESC LIMIT ?", title, limit)
    } catch as err {
        TrackLogError("Attn_SnapshotsFor", err)
        return []
    }
}

; The most recent recorded URL for a title, if any snapshot caught one.
Attn_UrlFor(title) {
    db := TrackDB()
    if (!db || title = "")
        return ""
    try {
        r := db.QueryRow("SELECT url FROM snap_entry WHERE title=? AND url IS NOT NULL"
                       . " AND url<>'' ORDER BY id DESC LIMIT 1", title)
        if r.Count
            return r["url"]
    }
    return ""
}

; ═══════════════════════════════════════════════════════════════════════════════
; FORMATTING / SORTING
; ═══════════════════════════════════════════════════════════════════════════════

Attn_Dur(ms) {
    secs := Round(ms / 1000)
    if (secs < 60)
        return secs . "s"
    if (secs < 3600)
        return Format("{:d}m {:02d}s", secs // 60, Mod(secs, 60))
    return Format("{:d}h {:02d}m", secs // 3600, Mod(secs // 60, 60))
}

; Insertion sort: the list is capped at a few hundred rows, and this keeps
; equal-key rows in their existing order.
Attn_SortRows(rows, key, desc := true) {
    n := rows.Length
    if (n < 2)
        return
    i := 2
    while (i <= n) {
        cur := rows[i]
        j := i - 1
        while (j >= 1 && Attn_Cmp(rows[j], cur, key, desc) > 0) {
            rows[j + 1] := rows[j]
            j--
        }
        rows[j + 1] := cur
        i++
    }
}

Attn_Cmp(a, b, key, desc) {
    va := a.Has(key) ? a[key] : ""
    vb := b.Has(key) ? b[key] : ""
    if (IsNumber(va) && IsNumber(vb))
        r := (va < vb) ? -1 : (va > vb) ? 1 : 0
    else {
        sa := StrLower(String(va)), sb := StrLower(String(vb))
        r := (sa < sb) ? -1 : (sa > sb) ? 1 : 0
    }
    return desc ? -r : r
}

; ═══════════════════════════════════════════════════════════════════════════════
; NSFW VOCABULARY (learned, never committed)
; ═══════════════════════════════════════════════════════════════════════════════
; The vocabulary is derived from this machine's own browsing history and kept in
; data\nsfw_vocab.ini. That path is gitignored, so no explicit term, domain or
; phrase ever reaches the repository - this source file deliberately contains
; none of them. If the file is missing every item is simply treated as ordinary.

global g_NsfwDomains := "", g_NsfwTerms := "", g_NsfwBases := ""

Nsfw_Load(force := false) {
    global g_NsfwDomains, g_NsfwTerms, g_NsfwBases, DATA_DIR
    if (!force && IsObject(g_NsfwDomains))
        return
    g_NsfwDomains := Map(), g_NsfwTerms := Map(), g_NsfwBases := Map()
    path := DATA_DIR . "\nsfw_vocab.ini"
    if !FileExist(path)
        return
    section := ""
    try content := FileRead(path, "UTF-8")
    catch
        return
    for , line in StrSplit(content, "`n", "`r") {
        s := Trim(line)
        if (s = "" || SubStr(s, 1, 1) = ";")
            continue
        if (SubStr(s, 1, 1) = "[") {
            section := StrLower(Trim(s, "[]"))
            continue
        }
        s := StrLower(s)
        if (section = "domains") {
            g_NsfwDomains[s] := true
            ; The bare host label also appears inside window titles ("... - Site").
            base := StrSplit(s, ".")[1]
            if (StrLen(base) >= 4)
                g_NsfwBases[base] := true
        } else if (section = "terms") {
            g_NsfwTerms[s] := true
        }
    }
}

; Does this text (a window title, filename phrase or URL) look adult?
; A host match is decisive on its own; otherwise two learned terms are required,
; because a single common word matches innocent titles by accident.
Nsfw_IsMatch(text, url := "") {
    global g_NsfwDomains, g_NsfwTerms, g_NsfwBases
    Nsfw_Load()
    if !IsObject(g_NsfwTerms)
        return false
    h := StrLower(text)
    u := StrLower(url)
    if (u != "") {
        for d in g_NsfwDomains {
            if InStr(u, d)
                return true
        }
    }
    for b in g_NsfwBases {
        if InStr(h, b)
            return true
    }
    hits := 0
    for , w in StrSplit(RegExReplace(h, "[^a-z]+", " "), " ") {
        if (StrLen(w) >= 3 && g_NsfwTerms.Has(w)) {
            hits++
            if (hits >= 2)
                return true
        }
    }
    return false
}

Nsfw_Ready() {
    global g_NsfwTerms
    Nsfw_Load()
    return IsObject(g_NsfwTerms) && g_NsfwTerms.Count > 0
}

; ═══════════════════════════════════════════════════════════════════════════════
; THE ATTENTION PANEL
; ═══════════════════════════════════════════════════════════════════════════════
; Resizable, column-sortable, viewer on the right. Opened from a hotkey or a
; button; it is its own window so it works from any build without touching the
; main tab layout.

Attn_OpenPanel() {
    global g_AttnGui, g_AttnLV, g_AttnPic, g_AttnDetail, g_AttnStatus
    global g_AttnFrom, g_AttnTo, g_AttnMinSecs, g_AttnKind, g_AttnFilter

    if IsObject(g_AttnGui) {
        try {
            g_AttnGui.Show()
            return
        }
    }
    g := Gui("+Resize", "Attention - what actually held your focus")
    g.MarginX := 10, g.MarginY := 10

    g.Add("Text", "x12 y14 w34", "From:")
    g_AttnFrom := g.Add("Edit", "x48 y11 w86 vAttnFrom"
        , FormatTime(DateAdd(A_Now, -7, "Days"), "yyyy-MM-dd"))
    g.Add("Text", "x142 y14 w20", "To:")
    g_AttnTo := g.Add("Edit", "x164 y11 w86 vAttnTo", FormatTime(A_Now, "yyyy-MM-dd"))
    g.Add("Text", "x260 y14 w56", "Min secs:")
    g_AttnMinSecs := g.Add("Edit", "x318 y11 w52 Number vAttnMin", "60")
    g.Add("Text", "x380 y14 w30", "Show:")
    g_AttnKind := g.Add("DropDownList", "x414 y11 w110 Choose1 vAttnKind"
        , ["Everything", "Video only", "Web only", "Adult only"])
    g.Add("Text", "x534 y14 w34", "Find:")
    g_AttnFilter := g.Add("Edit", "x570 y11 w180 vAttnFilter")
    g_AttnFilter.OnEvent("Change", (*) => Attn_Populate())
    g.Add("Button", "x758 y10 w86 h24 Default", "Refresh").OnEvent("Click", (*) => Attn_Refresh())
    g.Add("Button", "x850 y10 w96 h24", "Export CSV").OnEvent("Click", (*) => Attn_ExportCsv())

    ; Left: the ranked list. Click any header to sort by that column.
    g_AttnLV := g.Add("ListView", "x12 y44 w660 h520 Grid vAttnLV"
        , ["Prominence", "Watched / active", "Longest run", "Returns", "App", "Last in focus", "Title", "#"])
    g_AttnLV.ModifyCol(1, 80)
    g_AttnLV.ModifyCol(2, 105)
    g_AttnLV.ModifyCol(3, 90)
    g_AttnLV.ModifyCol(4, 60)
    g_AttnLV.ModifyCol(5, 90)
    g_AttnLV.ModifyCol(6, 125)
    g_AttnLV.ModifyCol(7, 400)
    g_AttnLV.ModifyCol(8, 0)      ; hidden: index back into g_AttnRows
    g_AttnLV.OnEvent("ColClick", Attn_OnColClick)
    g_AttnLV.OnEvent("ItemSelect", (lv, row, sel) => (sel ? Attn_ShowDetail(row) : 0))
    g_AttnLV.OnEvent("DoubleClick", (*) => Attn_OpenSnapshot())

    ; Right: viewer.
    g_AttnPic := g.Add("Picture", "x680 y44 w300 h210 Border vAttnPic")
    g_AttnDetail := g.Add("Edit", "x680 y260 w300 h240 ReadOnly Multi VScroll vAttnDetail")
    g_AttnDetail.SetFont("s8", "Consolas")
    g.Add("Button", "x680 y506 w96 h26 vAttnB1", "Open snapshot").OnEvent("Click", (*) => Attn_OpenSnapshot())
    g.Add("Button", "x782 y506 w96 h26 vAttnB2", "Open URL / file").OnEvent("Click", (*) => Attn_OpenUrl())
    g.Add("Button", "x884 y506 w96 h26 vAttnB3", "Copy title").OnEvent("Click", (*) => Attn_CopyTitle())
    g.Add("Button", "x680 y536 w146 h26 vAttnB5", "Copy URL / path").OnEvent("Click", (*) => Attn_CopyLocation())
    g.Add("Button", "x832 y536 w148 h26 vAttnB4", "Find in Snapshot Recovery").OnEvent("Click", (*) => Attn_SendToSnapRec())

    g_AttnStatus := g.Add("Text", "x12 y572 w968 vAttnStatus", "Choose a range and press Refresh.")

    g.OnEvent("Size", Attn_OnResize)
    g.OnEvent("Close", (*) => g.Hide())
    g.OnEvent("Escape", (*) => g.Hide())
    g_AttnGui := g
    g.Show("w992 h600")
    Attn_Refresh()
}

; Keep the list stretching with the window and the viewer pinned right.
Attn_OnResize(g, minMax, w, h) {
    if (minMax = -1)
        return
    try {
        pad := 12
        rightW := 300
        listW := Max(260, w - rightW - pad * 3)
        listH := Max(150, h - 44 - 36)
        g["AttnLV"].Move(pad, 44, listW, listH)
        rx := pad * 2 + listW
        picH := Max(120, Integer(listH * 0.38))
        g["AttnPic"].Move(rx, 44, rightW, picH)
        detH := Max(80, listH - picH - 76)
        g["AttnDetail"].Move(rx, 44 + picH + 8, rightW, detH)
        by := 44 + picH + 8 + detH + 8
        g["AttnB1"].Move(rx, by, 96, 26)
        g["AttnB2"].Move(rx + 102, by, 96, 26)
        g["AttnB3"].Move(rx + 204, by, 96, 26)
        g["AttnB5"].Move(rx, by + 30, Integer(rightW * 0.48), 26)
        g["AttnB4"].Move(rx + Integer(rightW * 0.5), by + 30, Integer(rightW * 0.5), 26)
        g["AttnStatus"].Move(pad, h - 26, w - pad * 2)
    }
}

; ─── data flow ───────────────────────────────────────────────────────────────

Attn_Refresh() {
    global g_AttnRows, g_AttnFrom, g_AttnTo, g_AttnMinSecs, g_AttnKind, g_AttnStatus
    kindMap := Map(1, "all", 2, "video", 3, "web", 4, "nsfw")
    kind := kindMap.Has(g_AttnKind.Value) ? kindMap[g_AttnKind.Value] : "all"
    if (kind = "nsfw" && !Nsfw_Ready()) {
        g_AttnStatus.Value := "No learned vocabulary found (data\nsfw_vocab.ini) - showing everything instead."
        kind := "all"
    }
    g_AttnStatus.Value := "Measuring focus time..."
    g_AttnRows := Attn_Rank(Map(
        "from", Trim(g_AttnFrom.Value),
        "to", Trim(g_AttnTo.Value),
        "minSecs", Integer(g_AttnMinSecs.Value != "" ? g_AttnMinSecs.Value : 60),
        "kind", kind))
    Attn_Populate()
}

Attn_Populate() {
    global g_AttnRows, g_AttnLV, g_AttnFilter, g_AttnStatus
    needle := StrLower(Trim(g_AttnFilter.Value))
    g_AttnLV.Opt("-Redraw")
    g_AttnLV.Delete()
    shown := 0, totalMs := 0
    for i, r in g_AttnRows {
        if (needle != "" && !InStr(StrLower(r["title"] . " " . r["exe"]), needle))
            continue
        shown++
        totalMs += r["total_ms"]
        g_AttnLV.Add(, Format("{:.1f}", r["score"])
                    , Attn_Dur(r["total_ms"])
                    , Attn_Dur(r["longest_ms"])
                    , r["sessions"]
                    , r["exe"]
                    , r["last_ts"]
                    , r["title"])
        ; Column 8 is hidden bookkeeping: which row of g_AttnRows this is.
        g_AttnLV.Modify(shown, "Col8", i)
    }
    g_AttnLV.Opt("+Redraw")
    g_AttnStatus.Value := shown . " item(s) shown of " . g_AttnRows.Length
        . " measured  |  combined focus time " . Attn_Dur(totalMs)
        . "  |  click a column header to sort, drag edges to resize"
    if shown
        g_AttnLV.Modify(1, "Select Focus")
}

; Header click sorts by that column, toggling direction.
Attn_OnColClick(lv, col) {
    global g_AttnRows, g_AttnSortKey, g_AttnSortDesc
    keys := Map(1, "score", 2, "total_ms", 3, "longest_ms", 4, "sessions"
              , 5, "exe", 6, "last_ts", 7, "title")
    if !keys.Has(col)
        return
    key := keys[col]
    if (key = g_AttnSortKey)
        g_AttnSortDesc := !g_AttnSortDesc
    else {
        g_AttnSortKey := key
        ; Numbers read best largest-first, text A-Z.
        g_AttnSortDesc := (key = "score" || key = "total_ms" || key = "longest_ms"
                        || key = "sessions" || key = "last_ts")
    }
    Attn_SortRows(g_AttnRows, g_AttnSortKey, g_AttnSortDesc)
    Attn_Populate()
}

Attn_SelectedRow() {
    global g_AttnLV, g_AttnRows
    row := g_AttnLV.GetNext()
    if !row
        return Map()
    idx := Integer(g_AttnLV.GetText(row, 8))
    return (idx >= 1 && idx <= g_AttnRows.Length) ? g_AttnRows[idx] : Map()
}

; ─── viewer ──────────────────────────────────────────────────────────────────

Attn_ShowDetail(lvRow) {
    global g_AttnPic, g_AttnDetail
    rec := Attn_SelectedRow()
    if !rec.Count
        return
    shots := Attn_SnapshotsFor(rec["title"], 12)
    shotPath := ""
    for s in shots {
        if FileExist(s["image_path"]) {
            shotPath := s["image_path"]
            break
        }
    }
    try g_AttnPic.Value := (shotPath != "" ? shotPath : "")

    t := ""
    t .= rec["title"] . "`r`n`r`n"
    if rec["is_media"] {
        w := Attn_WatchTime(rec["title"])
        t .= "WATCH TIME (foreground time on this media)`r`n"
        t .= "  watched total : " . Attn_Dur(w["total_ms"]) . "`r`n"
        t .= "  longest sitting: " . Attn_Dur(w["longest_ms"]) . "`r`n"
        t .= "  sittings      : " . w["sittings"] . "`r`n"
        t .= "  first / last  : " . w["first_ts"] . "  ..  " . w["last_ts"] . "`r`n`r`n"
    } else {
        t .= "FOCUS TIME`r`n"
        t .= "  active total  : " . Attn_Dur(rec["total_ms"]) . "`r`n"
        t .= "  longest run   : " . Attn_Dur(rec["longest_ms"]) . "`r`n"
        t .= "  returned to   : " . rec["sessions"] . " time(s)`r`n"
        t .= "  first / last  : " . rec["first_ts"] . "  ..  " . rec["last_ts"] . "`r`n`r`n"
    }
    share := (rec["total_ms"] > 0) ? Round(100.0 * rec["longest_ms"] / rec["total_ms"]) : 0
    t .= "PROMINENCE " . Format("{:.1f}", rec["score"]) . "`r`n"
    t .= "  = minutes x depth x returns x recency`r`n"
    t .= "  deepest run is " . share . "% of its total time`r`n`r`n"
    t .= "APP  " . rec["exe"] . "`r`n"
    ; A page has an address; a local file has a path. Show whichever applies.
    loc := Attn_LocationFor(rec)
    if (loc["kind"] = "url")
        t .= "URL  " . loc["value"] . "`r`n`r`n"
    else if (loc["kind"] = "file")
        t .= "FILE " . loc["value"] . "`r`n`r`n"
    else {
        named := Media_NameFromTitle(rec["title"], rec["exe"])
        t .= "URL  " . (named != ""
            ? "(no address; '" . named . "' not found by Everything)"
            : "(none recorded - captured before URL logging)") . "`r`n`r`n"
    }
    t .= "SNAPSHOTS  " . shots.Length . " on file`r`n"
    for i, s in shots {
        t .= "  " . s["ts"] . "`r`n"
        if (i >= 6)
            break
    }
    g_AttnDetail.Value := t
}

Attn_OpenSnapshot() {
    rec := Attn_SelectedRow()
    if !rec.Count
        return
    for s in Attn_SnapshotsFor(rec["title"], 12) {
        if FileExist(s["image_path"]) {
            try Run('"' . s["image_path"] . '"')
            return
        }
    }
    ShowStatus("No snapshot image on disk for that title", "fail")
}

; Opens the page for a browser row, or reveals the file for a local-media row.
Attn_OpenUrl() {
    rec := Attn_SelectedRow()
    if !rec.Count
        return
    loc := Attn_LocationFor(rec)
    if (loc["kind"] = "url") {
        try Research_OpenUrl(loc["value"])
        return
    }
    if (loc["kind"] = "file") {
        try Run('explorer.exe /select,"' . loc["value"] . '"')
        ShowStatus("Revealed " . loc["value"], "ok")
        return
    }
    ShowStatus("No address or file could be resolved for that title", "fail")
}

; Whichever location applies, on the clipboard.
Attn_CopyLocation() {
    rec := Attn_SelectedRow()
    if !rec.Count
        return
    loc := Attn_LocationFor(rec)
    if (loc["value"] = "") {
        ShowStatus("Nothing to copy - no address or file for that title", "fail")
        return
    }
    A_Clipboard := loc["value"]
    ShowStatus("Copied " . loc["kind"] . ": " . TrackEllipsis(loc["value"], 60), "ok")
}

Attn_CopyTitle() {
    rec := Attn_SelectedRow()
    if !rec.Count
        return
    clue := SnapClue_FromTitle(rec["title"])
    A_Clipboard := (clue["query"] != "" ? clue["query"] : rec["title"])
    ShowStatus("Copied: " . TrackEllipsis(A_Clipboard, 50), "ok")
}

; Hand the title to the Snapshot Recovery tab as an Everything query.
Attn_SendToSnapRec() {
    global g_SnapRecQuery, DATA_DIR
    rec := Attn_SelectedRow()
    if !rec.Count
        return
    clue := SnapClue_FromTitle(rec["title"])
    words := StrSplit(clue["query"], " ")
    needle := ""
    Loop Min(4, words.Length)
        needle .= (needle = "" ? "" : " ") . words[A_Index]
    q := 'file: ancestor:"' . DATA_DIR . '\tracking\snapshots\" ' . needle
    if IsObject(g_SnapRecQuery) {
        try {
            g_SnapRecQuery.Value := q
            SnapRec_Search()
            ShowStatus("Snapshot Recovery searched for: " . needle, "ok")
            return
        }
    }
    A_Clipboard := q
    ShowStatus("Snapshot Recovery not open - query copied to clipboard", "wait")
}

Attn_ExportCsv() {
    global g_AttnRows, DATA_DIR
    if !g_AttnRows.Length {
        ShowStatus("Nothing to export", "wait")
        return
    }
    path := DATA_DIR . "\attention_" . FormatTime(A_Now, "yyyyMMdd_HHmmss") . ".csv"
    out := "prominence,total_seconds,longest_seconds,sessions,exe,first_ts,last_ts,title`r`n"
    for r in g_AttnRows {
        out .= Format("{:.2f}", r["score"]) . ","
             . Round(r["total_ms"] / 1000) . ","
             . Round(r["longest_ms"] / 1000) . ","
             . r["sessions"] . ","
             . TrackCsvRow([r["exe"], r["first_ts"], r["last_ts"], r["title"]]) . "`r`n"
    }
    Track_WriteFile(path, out)
    ShowStatus("Exported " . g_AttnRows.Length . " rows -> " . path, "ok")
    try Run('explorer.exe /select,"' . path . '"')
}

; ═══════════════════════════════════════════════════════════════════════════════
; OCR SEGMENTATION - turning a screenful of noise into usable context
; ═══════════════════════════════════════════════════════════════════════════════
; Raw OCR of a full-screen capture is mostly furniture: tab strips, sidebars,
; menus, clocks, notification counts. Dumping all of it on the clipboard buries
; the two or three lines that actually identify what was on screen.
;
; OcrSeg_Analyse sorts the text into labelled buckets and produces a short
; "context" summary - the headline, any address, any media timecode - so the
; clipboard carries meaning rather than a wall of characters.
;
; Returns Map:
;   urls        addresses recognised anywhere in the text
;   timecodes   media positions/durations (0:12:34, 12:34)
;   headline    the most title-like line
;   lines       cleaned content lines, furniture removed
;   noise       the discarded lines (kept for inspection)
;   context     a compact human summary
;   clipboard   the text to place on the clipboard

OcrSeg_Analyse(text, hintTitle := "") {
    out := Map("urls", [], "timecodes", [], "headline", "", "lines", []
             , "noise", [], "context", "", "clipboard", "")
    if (Trim(text) = "")
        return out

    seen := Map()
    for , raw in StrSplit(text, "`n", "`r") {
        line := Trim(raw)
        if (line = "")
            continue
        ; collapse OCR's doubled spaces
        line := RegExReplace(line, "\s{2,}", " ")
        if OcrSeg_IsFurniture(line) {
            out["noise"].Push(line)
            continue
        }
        key := StrLower(line)
        if seen.Has(key)
            continue
        seen[key] := true
        out["lines"].Push(line)
    }

    ; Addresses: reuse the recovery module's extractor when present.
    try out["urls"] := SnapClue_UrlsFromText(text)
    catch
        out["urls"] := []

    ; Media positions like 1:23:45 or 12:34 - the strongest hint that a video
    ; was on screen, and roughly where it was.
    pos := 1
    while (pos := RegExMatch(text, "\b\d{1,2}:\d{2}(?::\d{2})?\b", &m, pos)) {
        pos += StrLen(m[0])
        if (out["timecodes"].Length < 12)
            out["timecodes"].Push(m[0])
    }

    out["headline"] := OcrSeg_Headline(out["lines"], hintTitle)
    out["context"] := OcrSeg_Context(out, hintTitle)
    out["clipboard"] := OcrSeg_Clipboard(out, hintTitle)
    return out
}

; Interface furniture rather than content.
OcrSeg_IsFurniture(line) {
    if (StrLen(line) < 3)
        return true
    ; Mostly punctuation or box-drawing left over from thresholding.
    letters := StrLen(RegExReplace(line, "[^A-Za-z]"))
    if (letters * 2 < StrLen(line))
        return true
    ; Clocks, dates, battery, common chrome labels.
    if (line ~= "i)^(\d{1,2}:\d{2}(\s?[ap]m)?|\d{1,3}%)$")
        return true
    if (line ~= "i)^(file|edit|view|help|tools|window|bookmarks|history|settings"
              . "|home|back|forward|reload|search|menu|more|share|save|sign in"
              . "|subscribe|log in|download|next|previous|play|pause|mute)$")
        return true
    return false
}

; The most title-like remaining line: long enough to be a phrase, not a URL,
; and preferring one that overlaps the window title we already know.
OcrSeg_Headline(lines, hintTitle) {
    best := "", bestScore := -1
    hintWords := Map()
    for , w in StrSplit(StrLower(RegExReplace(hintTitle, "[^A-Za-z ]", " ")), " ")
        if (StrLen(w) >= 4)
            hintWords[w] := true
    for , line in lines {
        if (line ~= "i)^https?://" || StrLen(line) < 12 || StrLen(line) > 140)
            continue
        score := Min(StrLen(line), 90) / 10.0
        words := 0
        for , w in StrSplit(StrLower(RegExReplace(line, "[^A-Za-z ]", " ")), " ")
            if (StrLen(w) >= 4 && hintWords.Has(w))
                words++
        score += words * 6
        if (score > bestScore) {
            bestScore := score
            best := line
        }
    }
    return best
}

OcrSeg_Context(seg, hintTitle) {
    bits := []
    if (seg["headline"] != "")
        bits.Push("on screen: " . TrackEllipsis(seg["headline"], 70))
    if seg["urls"].Length
        bits.Push("address: " . seg["urls"][1])
    if seg["timecodes"].Length {
        tc := ""
        for i, t in seg["timecodes"] {
            tc .= (tc = "" ? "" : " ") . t
            if (i >= 3)
                break
        }
        bits.Push("timecodes: " . tc)
    }
    bits.Push(seg["lines"].Length . " content lines, " . seg["noise"].Length . " discarded")
    out := ""
    for , b in bits
        out .= (out = "" ? "" : "  |  ") . b
    return out
}

; What lands on the clipboard: the meaningful part first, full text after.
OcrSeg_Clipboard(seg, hintTitle) {
    s := ""
    if (hintTitle != "")
        s .= "WINDOW: " . hintTitle . "`r`n"
    if (seg["headline"] != "")
        s .= "HEADLINE: " . seg["headline"] . "`r`n"
    if seg["urls"].Length {
        s .= "URLS:`r`n"
        for , u in seg["urls"]
            s .= "  " . u . "`r`n"
    }
    if seg["timecodes"].Length {
        tc := ""
        for , t in seg["timecodes"]
            tc .= (tc = "" ? "" : ", ") . t
        s .= "TIMECODES: " . tc . "`r`n"
    }
    s .= "`r`nTEXT:`r`n"
    for , line in seg["lines"]
        s .= line . "`r`n"
    return s
}

; ═══════════════════════════════════════════════════════════════════════════════
; LOCAL FILES - the "URL" of anything played from disk
; ═══════════════════════════════════════════════════════════════════════════════
; A browser snapshot has an address; a VLC snapshot has a file. The window title
; names it ("clip.mp4 - VLC media player") but not where it lives, so the path is
; resolved on demand through Everything - the same index the Snapshot Recovery
; search already uses. Resolving lazily (rather than storing at capture time)
; also means it still works for the whole existing archive, and keeps up when a
; file is later moved.

global g_MediaPathCache := Map()

; Extract the filename a window title is showing, or "" when it names no file.
Media_NameFromTitle(title, exe := "") {
    t := Trim(title)
    if (t = "")
        return ""
    ; Everything and some players put the full path straight in the title.
    if RegExMatch(t, "i)([A-Za-z]:\[^\r\n]*?\.[A-Za-z0-9]{2,5})(?=\s+-\s|\s*$)", &m)
        return Trim(m[1])
    ; Otherwise take the first path-less filename with a real extension.
    if RegExMatch(t, "i)([^\/:*?<>|\r\n]+?\.(mp4|mkv|avi|webm|mov|m4v|wmv|flv|ts|mpg|mpeg"
                   . "|mp3|flac|wav|m4a|opus|pdf|txt|ahk|py|md|docx|xlsx|zip))\b", &m2)
        return Trim(m2[1])
    return ""
}

; Full path for a title that names a file. Returns "" when it cannot be found.
Media_PathFromTitle(title, exe := "") {
    global g_MediaPathCache
    name := Media_NameFromTitle(title, exe)
    if (name = "")
        return ""
    ; Already absolute - trust it when the file is really there.
    if (name ~= "i)^[A-Za-z]:\\")
        return FileExist(name) ? name : ""
    key := StrLower(name)
    if g_MediaPathCache.Has(key)
        return g_MediaPathCache[key]

    path := ""
    ev := ""
    try ev := SnapRec_Everything()
    if IsObject(ev) {
        try {
            ; Quote the name so spaces stay one term; ask for exact filename.
            res := ev.Search('file: "' . name . '"', 25)
            if (res.Ok && res.Results.Length) {
                SplitPath(name, , , &wantExt)
                wantExt := StrLower(wantExt)
                best := "", fallback := ""
                for , r in res.Results {
                    if r.IsDirectory
                        continue
                    ; Our own captures are named after the window they show, so
                    ; a snapshot of Everything listing "clip.mp4" matches the
                    ; search for "clip.mp4" and would otherwise win.
                    if InStr(r.Path, "\tracking\snapshots\")
                        continue
                    SplitPath(r.Path, &fn, , &gotExt)
                    if (StrLower(fn) = key) {
                        best := r.Path
                        break
                    }
                    ; Anything else must at least be the same kind of file.
                    if (fallback = "" && wantExt != "" && StrLower(gotExt) = wantExt)
                        fallback := r.Path
                }
                path := (best != "" ? best : fallback)
            }
        } catch as err {
            TrackLogError("Media_PathFromTitle", err)
        }
    }
    g_MediaPathCache[key] := path
    return path
}

; The best "where was this" for a row: a recorded URL, else a resolved file path.
Attn_LocationFor(rec) {
    if (rec.Has("url") && rec["url"] != "")
        return Map("kind", "url", "value", rec["url"])
    p := Media_PathFromTitle(rec["title"], rec.Has("exe") ? rec["exe"] : "")
    if (p != "")
        return Map("kind", "file", "value", p)
    return Map("kind", "", "value", "")
}
