; ═══════════════════════════════════════════════════════════════════════════════
; SnapshotRecovery.ahk - Get back to what you were looking at, from a snapshot
; ═══════════════════════════════════════════════════════════════════════════════
; The snapshot engine already stores an image plus the window title for every
; capture. A title alone is a poor way back to a page: it is underscored on disk,
; truncated to fit a filename, and it is NOT the text that was typed into a
; search box. This module closes that gap from three directions:
;
;   1. RECORD THE URL AT CAPTURE TIME (the reliable one)
;      BrowserUrl_FromWindow() reads the live address bar out of the browser's
;      accessibility tree, so every new snapshot stores the exact page URL
;      alongside the image. Nothing has to be reconstructed later.
;
;   2. RECOVER CLUES FROM OLD SNAPSHOTS (the retroactive one)
;      SnapClue_FromFilename() turns
;        02_Hot_Korean_oils_..._-_SpankBang_-_Google_Ch.png
;      into a searchable phrase ("Hot Korean oils ..."), the site it came from
;      ("SpankBang") and the viewer app - dropping the underscores and the
;      "- Google Chrome" tail that make a filename useless as a search query.
;
;   3. CROSS-REFERENCE CHROME'S OWN HISTORY (the corroborating one)
;      ChromeHist_* reads Chrome's History database (a copy of it - the live
;      file is locked) including keyword_search_terms, which holds the actual
;      search terms typed. Matching a snapshot's title/time against history
;      usually recovers the exact URL even for captures taken before URL
;      recording existed.
;
; The Snapshot Recovery tab ties these together over an Everything 1.5 query, so
; the same search syntax used in Everything works here, with the snapshot index,
; the recorded URL, history matches and the image preview all in one place.
;
; Nothing here renames, moves, uploads or opens a recovered URL by itself.
; ═══════════════════════════════════════════════════════════════════════════════

global g_SnapRecEverything := ""     ; Everything3SDK instance (lazy)
global g_SnapRecRows := []           ; rows backing the results ListView
global g_SnapRecLV := "", g_SnapRecQuery := "", g_SnapRecPic := ""
global g_SnapRecEvidence := "", g_SnapRecStatus := "", g_SnapRecHistLV := ""
global g_SnapRecHistSearch := "", g_SnapRecPreset := "", g_SnapRecUrlOnly := false
global g_SnapRecCtl := Map()
global g_ChromeHistCache := ""       ; path of the last History copy
global g_ChromeHistCacheTs := 0
global g_ChromeHistGui := "", g_ChromeHistLV := "", g_ChromeHistSearch := ""
global g_ChromeHistStatus := "", g_ChromeHistRefreshBusy := false
global g_SnapSigWork := Map()
global g_SnapSigBtn := ""
global g_SnapExclusionGui := "", g_SnapExclusionLV := ""

; ═══════════════════════════════════════════════════════════════════════════════
; 1. LIVE BROWSER URL (accessibility tree)
; ═══════════════════════════════════════════════════════════════════════════════

; Read the address bar of a browser window. Returns Map(url, source) - source is
; "acc" when the URL came from the accessibility tree, "" when nothing was found.
; Chromium exposes the omnibox as an editable-text element whose Name is
; "Address and search bar"; Firefox names it differently, so the role is matched
; first and the name only used to rank candidates.
BrowserUrl_FromWindow(hwnd, exe := "") {
    out := Map("url", "", "source", "")
    if !hwnd
        return out
    if (exe = "") {
        try exe := WinGetProcessName("ahk_id " . hwnd)
    }
    if !BrowserUrl_IsBrowser(exe)
        return out

    root := ""
    try root := Acc.ElementFromHandle(hwnd)     ; also activates Chromium a11y
    if !IsObject(root)
        return out

    ; ROLE_SYSTEM_TEXT (42) is the omnibox in Chromium and Firefox. The address
    ; bar lives in the browser chrome, near the top of the tree, so stopping at
    ; the first shallow match is 10-18x faster than enumerating every text
    ; element - the alternative walks the entire rendered page (measured at
    ; ~2s per window, which a whole-desktop snapshot cycle cannot afford).
    best := ""
    try {
        el := root.FindElement({Role: 42}, 4, 1, 0, 12)
        if IsObject(el)
            try best := Trim(el.Value)
    }
    if !BrowserUrl_LooksLikeUrl(best) {
        ; Fallback for layouts where the first text element is not the address
        ; bar: score every candidate on name and value shape.
        best := ""
        bestScore := -1
        cands := []
        try cands := root.FindElements({Role: 42})
        if IsObject(cands) {
            for , el2 in cands {
                name := "", val := ""
                try name := el2.Name
                try val := el2.Value
                val := Trim(val)
                if (val = "")
                    continue
                score := 0
                if (name ~= "i)address|search bar|location|enter address")
                    score += 10
                if BrowserUrl_LooksLikeUrl(val)
                    score += 5
                if (score > bestScore) {
                    bestScore := score
                    best := val
                }
            }
        }
        if (bestScore < 5)
            best := ""
    }

    if (best != "") {
        ; Chromium hides the scheme in the omnibox; put it back so the stored
        ; value is a usable link.
        if !(best ~= "i)^[a-z][a-z0-9+.-]*://")
            best := "https://" . best
        out["url"] := best
        out["source"] := "acc"
    }
    return out
}

; Does this address-bar value actually look like a location? Guards against
; picking up a page search box or a half-typed query.
BrowserUrl_LooksLikeUrl(v) {
    if (v = "" || InStr(v, " "))
        return false
    if (v ~= "i)^[a-z][a-z0-9+.-]*://\S+")
        return true
    ; scheme-less forms Chromium shows in the omnibox
    if (v ~= "i)^[\w.-]+\.[a-z]{2,}([/:?#]|$)")      ; host.tld[/path]
        return true
    if (v ~= "i)^localhost([/:?#]|$)")               ; localhost[:port]
        return true
    if (v ~= "^\d{1,3}(\.\d{1,3}){3}([:/?#]|$)")     ; 127.0.0.1:3080
        return true
    if (v ~= "i)^[\w-]+:\d{2,5}([/?#]|$)")           ; host:port
        return true
    return false
}

BrowserUrl_IsBrowser(exe) {
    return exe ~= "i)^(chrome|msedge|firefox|brave|opera|vivaldi|chromium|arc)\.exe$"
}

; ═══════════════════════════════════════════════════════════════════════════════
; 2. FILENAME / TITLE CLUES
; ═══════════════════════════════════════════════════════════════════════════════

; Turn a snapshot path (or a raw window title) into search clues.
; Returns Map(query, site, app, index, raw).
;   query - the human phrase, underscores gone and the app/site tail stripped
;   site  - the site the page belonged to, when the title advertises one
;   app   - the viewer the capture came from (Google Chrome, VLC media player...)
SnapClue_FromFilename(path) {
    SplitPath(path, , , , &nameNoExt)
    raw := (nameNoExt != "" ? nameNoExt : path)
    return SnapClue_FromTitle(raw)
}

SnapClue_FromTitle(raw) {
    out := Map("query", "", "site", "", "app", "", "index", "", "raw", raw)
    s := raw

    ; Leading capture index the snapshot engine adds: "02_..."
    if RegExMatch(s, "^(\d{1,3})[_ ]+(.*)$", &m) {
        out["index"] := m[1]
        s := m[2]
    }

    ; Underscores are a filename artifact, not part of the phrase. This is the
    ; single change that makes these titles searchable again.
    s := StrReplace(s, "_", " ")
    s := RegExReplace(s, "\s{2,}", " ")
    s := Trim(s)

    ; Split on the " - " chain the window title uses: "<page> - <site> - <app>"
    parts := []
    for , p in StrSplit(s, " - ")
        if (Trim(p) != "")
            parts.Push(Trim(p))

    ; Strip the trailing viewer application. The snapshot filename is cut to a
    ; fixed length, so this tail is routinely truncated mid-word - real examples
    ; end in "Google Ch" and even "Goo" - which is why a plain name comparison
    ; misses it and the app ends up glued to the search phrase.
    while (parts.Length > 1 && SnapClue_IsAppTail(parts[parts.Length])) {
        out["app"] := parts[parts.Length]
        parts.Pop()
    }

    ; What is left ends with the site when there is more than one segment.
    if (parts.Length > 1) {
        out["site"] := parts[parts.Length]
        core := ""
        Loop parts.Length - 1
            core .= (core = "" ? "" : " - ") . parts[A_Index]
        out["query"] := core
    } else if parts.Length {
        out["query"] := parts[1]
    }

    ; Media containers leak into video-player titles: "SpankBang.mp4"
    mediaPat := "i)\.(mp4|mkv|avi|webm|mov|m4v|wmv|flv|ts|mpg|mpeg)\b"
    out["query"] := SnapClue_Tidy(RegExReplace(out["query"], mediaPat, ""))
    out["site"] := SnapClue_Tidy(RegExReplace(out["site"], mediaPat, ""))
    return out
}

; Collapse whitespace and shave the dangling separators a truncated filename
; leaves behind ("SpankBang -", "- Some title").
SnapClue_Tidy(s) {
    s := RegExReplace(s, "\s{2,}", " ")
    s := RegExReplace(s, "^[\s\-|:]+", "")
    s := RegExReplace(s, "[\s\-|:]+$", "")
    return Trim(s)
}

; Is this trailing title segment the application name rather than content?
; Accepts truncations, because the filename length cap chops them: a segment
; that is a PREFIX of a known application name ("Goo" of "Google Chrome") counts,
; as does one that starts with a known name ("VLC media player 3.0").
SnapClue_IsAppTail(seg) {
    static apps := ["google chrome", "mozilla firefox", "microsoft edge", "vlc media player"
                  , "windows photo viewer", "internet explorer", "chromium", "vivaldi"
                  , "firefox", "chrome", "opera", "brave", "edge", "photos", "vlc"]
    s := StrLower(Trim(RegExReplace(seg, "\s{2,}", " ")))
    if (StrLen(s) < 3)
        return false
    for , a in apps {
        if (SubStr(a, 1, StrLen(s)) = s)      ; segment is a truncated app name
            return true
        if (SubStr(s, 1, StrLen(a)) = a)      ; segment starts with an app name
            return true
    }
    return false
}

; Pull http(s) URLs out of arbitrary text (OCR output, page text, titles).
SnapClue_UrlsFromText(text) {
    urls := [], seen := Map()
    pos := 1
    while (pos := RegExMatch(text, "i)\bhttps?://[^\s`"'<>()\[\]]{4,}", &m, pos)) {
        u := RegExReplace(m[0], "[.,;:!?]+$")
        pos += StrLen(m[0])
        if !seen.Has(u) {
            seen[u] := true
            urls.Push(u)
        }
    }
    ; Bare domains with a path, as an address bar renders them.
    pos := 1
    while (pos := RegExMatch(text, "i)\b(?:www\.)?[a-z0-9-]{3,}\.(?:com|net|org|tv|cc|xxx|io|co)\b(?:/\S*)?", &m2, pos)) {
        u := RegExReplace(m2[0], "[.,;:!?]+$")
        pos += StrLen(m2[0])
        if (StrLen(u) < 8)
            continue
        full := "https://" . RegExReplace(u, "i)^https?://")
        if !seen.Has(full) {
            seen[full] := true
            urls.Push(full)
        }
    }
    return urls
}

; ═══════════════════════════════════════════════════════════════════════════════
; 3. CHROME HISTORY
; ═══════════════════════════════════════════════════════════════════════════════
; Chrome keeps its History in SQLite but holds an exclusive lock while running,
; so every read works on a fresh copy. Timestamps are microseconds since
; 1601-01-01 UTC (the WebKit epoch), converted here to normal local timestamps.

ChromeHist_ProfileDirs() {
    dirs := []
    base := EnvGet("LOCALAPPDATA") . "\Google\Chrome\User Data"
    if !DirExist(base)
        return dirs
    for , sub in ["Default"] {
        if FileExist(base . "\" . sub . "\History")
            dirs.Push(base . "\" . sub)
    }
    Loop Files, base . "\Profile *", "D" {
        if FileExist(A_LoopFileFullPath . "\History")
            dirs.Push(A_LoopFileFullPath)
    }
    return dirs
}

; Copy one locked Chrome profile database to our data directory. WAL side-files
; travel with it so visits made moments ago are visible in the copy.
ChromeHist_CopyProfile(profileDir) {
    global DATA_DIR
    SplitPath(profileDir, &profile)
    safe := RegExReplace(profile, "[^A-Za-z0-9_.-]", "_")
    dest := DATA_DIR . "\chrome_history_" . safe . ".db"
    ; Chrome may run History in WAL or rollback-journal mode. Copying whichever
    ; side-file exists means a copy taken mid-commit is rolled back to a
    ; consistent state when opened, instead of reading half a transaction.
    for , ext in ["", "-wal", "-shm", "-journal"] {
        src := profileDir . "\History" . ext
        if FileExist(src) {
            try FileCopy(src, dest . ext, true)
        } else if FileExist(dest . ext) {
            try FileDelete(dest . ext)
        }
    }
    return FileExist(dest) ? dest : ""
}

; Compatibility helper for callers that only need the first profile copy.
ChromeHist_Snapshot(force := false) {
    global g_ChromeHistCache, g_ChromeHistCacheTs
    if (!force && g_ChromeHistCache != "" && FileExist(g_ChromeHistCache)
        && (A_TickCount - g_ChromeHistCacheTs) < 60000)
        return g_ChromeHistCache
    dirs := ChromeHist_ProfileDirs()
    if !dirs.Length
        return ""
    g_ChromeHistCache := ChromeHist_CopyProfile(dirs[1])
    g_ChromeHistCacheTs := A_TickCount
    return g_ChromeHistCache
}

; WebKit microseconds -> "yyyy-MM-dd HH:mm:ss" local time ("" when zero).
ChromeHist_Time(webkitUs) {
    if (!IsNumber(webkitUs) || webkitUs <= 0)
        return ""
    unix := (Integer(webkitUs) // 1000000) - 11644473600
    if (unix <= 0)
        return ""
    ; 1970-01-01 as an AHK timestamp, advanced by the unix seconds.
    t := "19700101000000"
    t := DateAdd(t, unix, "Seconds")
    ; Stored UTC; shift to local so it lines up with snapshot timestamps.
    bias := DateDiff(A_Now, A_NowUTC, "Seconds")
    t := DateAdd(t, bias, "Seconds")
    return FormatTime(t, "yyyy-MM-dd HH:mm:ss")
}

; Pull unseen visits from every Chrome profile into tracking.db. Refreshing is
; append-only: history remains searchable here even if Chrome later prunes it.
; forceFull re-reads the source databases but the UNIQUE key prevents copies.
ChromeHist_RefreshArchive(forceFull := false) {
    db := TrackDB()
    if !db
        return Map("profiles", 0, "read", 0, "added", 0)
    dirs := ChromeHist_ProfileDirs()
    stats := Map("profiles", 0, "read", 0, "added", 0)

    for profileDir in dirs {
        SplitPath(profileDir, &profile)
        copyPath := ChromeHist_CopyProfile(profileDir)
        if copyPath = ""
            continue
        source := ""
        try source := TrackSQLite(copyPath)
        catch as err {
            TrackLogError("ChromeHist_RefreshArchive(open " . profile . ")", err)
            continue
        }

        since := forceFull ? 0 : db.Scalar(
            "SELECT COALESCE(MAX(visit_time),0) FROM chrome_history_archive WHERE profile=?"
            , profile)
        imported := []
        try imported := source.Query(
              "SELECT v.id AS visit_id,v.visit_time AS vt,u.url AS url,u.title AS title,"
            . "u.visit_count AS visits,"
            . "(SELECT group_concat(k.term,' | ') FROM keyword_search_terms k "
            . " WHERE k.url_id=u.id) AS term "
            . "FROM visits v JOIN urls u ON u.id=v.url "
            . "WHERE v.visit_time>? ORDER BY v.visit_time ASC LIMIT 200000", since)
        catch as err
            TrackLogError("ChromeHist_RefreshArchive(query " . profile . ")", err)
        try source.Close()
        stats["profiles"]++
        stats["read"] += imported.Length
        if !imported.Length
            continue

        before := db.Scalar("SELECT COUNT(*) FROM chrome_history_archive")
        now := TrackTS()
        db.Begin()
        try {
            for r in imported {
                db.Run("INSERT INTO chrome_history_archive"
                     . "(profile,source_visit_id,visit_time,visited_ts,url,title,search_term,"
                     . " visit_count,first_import_ts,last_import_ts) "
                     . "VALUES(?,?,?,?,?,?,?,?,?,?) "
                     . "ON CONFLICT(profile,visit_time,url) DO UPDATE SET "
                     . "title=excluded.title,search_term=excluded.search_term,"
                     . "visit_count=excluded.visit_count,last_import_ts=excluded.last_import_ts"
                     , profile, r["visit_id"], r["vt"], ChromeHist_Time(r["vt"])
                     , r["url"], r["title"], r["term"], r["visits"], now, now)
            }
            db.Commit()
        } catch as err {
            db.Rollback()
            TrackLogError("ChromeHist_RefreshArchive(write " . profile . ")", err)
            continue
        }
        after := db.Scalar("SELECT COUNT(*) FROM chrome_history_archive")
        stats["added"] += Max(0, Integer(after) - Integer(before))
    }
    return stats
}

; ─── automatic sync ──────────────────────────────────────────────────────────
; The archive used to refresh only when empty, so after the first import it
; silently froze - matching a snapshot then searched history that stopped days
; earlier. Chrome's own file is current to within seconds and copies in a
; fraction of a second, and the import is incremental (only visits newer than
; the archive's newest), so keeping it current costs almost nothing:
;
;   - before every history match or search, if the last sync is over a minute old
;   - every five minutes in the background while the app runs
;   - once shortly after startup, to catch up on anything missed while closed

global g_ChromeHistLastSync := 0

; Sync unless one ran within maxAgeMs. Returns true when a sync actually ran.
ChromeHist_SyncIfStale(maxAgeMs := 60000) {
    global g_ChromeHistRefreshBusy, g_ChromeHistLastSync
    if g_ChromeHistRefreshBusy
        return false
    if (g_ChromeHistLastSync && (A_TickCount - g_ChromeHistLastSync) < maxAgeMs)
        return false
    g_ChromeHistRefreshBusy := true
    stats := Map("profiles", 0, "read", 0, "added", 0)
    try stats := ChromeHist_RefreshArchive()
    catch as err
        TrackLogError("ChromeHist_SyncIfStale", err)
    g_ChromeHistRefreshBusy := false
    g_ChromeHistLastSync := A_TickCount
    ChromeHist_ShowSyncState(stats)
    return true
}

; Put the sync time and the newest archived visit in the history header, so it
; is always visible how current the data being matched against is.
ChromeHist_ShowSyncState(stats := "") {
    global g_SnapRecCtl
    newest := ""
    try newest := TrackDB().Scalar("SELECT MAX(visited_ts) FROM chrome_history_archive")
    added := (IsObject(stats) && stats.Has("added")) ? stats["added"] : 0
    txt := "Chrome history  -  synced " . FormatTime(A_Now, "HH:mm:ss")
         . (newest != "" ? ", newest visit " . newest : "")
         . (added ? "  (+" . added . " new)" : "")
         . "  -  auto-syncs every 5 min and before each match"
    try g_SnapRecCtl["histHdr"].Value := txt
}

ChromeHist_AutoSyncTick() {
    ChromeHist_SyncIfStale(240000)
}

; The button: sync right now, without replacing whatever match is on screen.
ChromeHist_SyncNowUI() {
    ShowStatus("Syncing Chrome history...", "wait")
    ChromeHist_SyncIfStale(0)
    ShowStatus("Chrome history synced", "ok")
}

ChromeHist_EnsureArchive() {
    db := TrackDB()
    if !db
        return false
    count := db.Scalar("SELECT COUNT(*) FROM chrome_history_archive")
    if !count
        ChromeHist_RefreshArchive()
    return true
}

; Search the durable archive across title, URL, typed search term and profile.
; An empty search returns the most recent visits.
ChromeHist_Search(text := "", limit := 1000) {
    rows := []
    if !ChromeHist_EnsureArchive()
        return rows
    db := TrackDB()
    text := Trim(text)
    if text = "" {
        res := db.Query("SELECT * FROM chrome_history_archive "
                      . "ORDER BY visit_time DESC LIMIT ?", limit)
    } else {
        like := "%" . text . "%"
        res := db.Query("SELECT * FROM chrome_history_archive WHERE "
                      . "title LIKE ? OR url LIKE ? OR search_term LIKE ? OR profile LIKE ? "
                      . "ORDER BY visit_time DESC LIMIT ?", like, like, like, like, limit)
    }
    for r in res {
        rows.Push(Map("url", r["url"], "title", r["title"], "visits", r["visit_count"]
                    , "last_ts", r["visited_ts"], "delta", "", "terms", r["search_term"]
                    , "profile", r["profile"]))
    }
    return rows
}

; "47m before" / "3m after" - how far a visit sits from the snapshot.
ChromeHist_Delta(visitUs, centerUs) {
    diff := Integer(visitUs) - Integer(centerUs)
    secs := Abs(diff) // 1000000
    word := (diff < 0 ? "before" : "after")
    if (secs < 90)
        return secs . "s " . word
    if (secs < 5400)
        return Round(secs / 60) . "m " . word
    return Round(secs / 3600, 1) . "h " . word
}

; The visits NEAREST a snapshot's timestamp, closest first, each carrying how
; far off it was ("47m before").
;
; Ranking beats a hard time window here: a page is visited once and then the tab
; sits open, so the snapshot that captures it is routinely tens of minutes after
; the visit. A +/-45min cutoff returned nothing for a Facebook capture whose real
; visit was 47 minutes earlier - the answer was there, just outside the fence.
; windowMin now only bounds how far out to look before giving up.
ChromeHist_Around(tsText, windowMin := 360, limit := 40) {
    rows := []
    if (tsText = "")
        return rows
    if !ChromeHist_EnsureArchive()
        return rows
    ; snapshot ts "yyyy-MM-dd HH:mm:ss" -> WebKit microseconds (UTC based)
    stamp := RegExReplace(tsText, "[^0-9]")      ; yyyyMMddHHmmss
    if (StrLen(stamp) < 14)
        return rows
    stamp := SubStr(stamp, 1, 14)
    bias := DateDiff(A_Now, A_NowUTC, "Seconds")
    utc := DateAdd(stamp, -bias, "Seconds")
    unix := DateDiff(utc, "19700101000000", "Seconds")
    center := (unix + 11644473600) * 1000000
    span := windowMin * 60 * 1000000

    db := TrackDB()
    try {
        res := db.Query("SELECT url,title,visit_time AS vt,search_term AS term,profile "
                      . "FROM chrome_history_archive WHERE visit_time BETWEEN ? AND ? "
                      . "ORDER BY ABS(visit_time - ?) LIMIT ?"
                      , center - span, center + span, center, limit)
        for r in res {
            rows.Push(Map("url", r["url"], "title", r["title"], "visits", ""
                        , "last_ts", ChromeHist_Time(r["vt"])
                        , "delta", ChromeHist_Delta(r["vt"], center), "terms", r["term"]
                        , "profile", r["profile"]))
        }
    } catch as err {
        TrackLogError("ChromeHist_Around(query)", err)
    }
    return rows
}

; ═══════════════════════════════════════════════════════════════════════════════
; 4. SNAPSHOT INDEX LOOKUP
; ═══════════════════════════════════════════════════════════════════════════════

; Is the tracking database (the snapshot index) actually available?
SnapRec_IndexReady() => TrackDB() != ""

; Look up many images at once, keyed by lowercased path.
; One query per 400 paths instead of one query per result: a thousand-result
; search was otherwise a thousand separate lookups, which is what made the
; window sit there unresponsive after a broad search.
SnapRec_EntriesForPaths(paths) {
    out := Map()
    db := TrackDB()
    if (!db || !paths.Length)
        return out
    i := 0
    total := paths.Length
    while (i < total) {
        chunk := [], marks := ""
        while (chunk.Length < 400 && i < total) {
            i++
            chunk.Push(paths[i])
            marks .= (marks = "" ? "?" : ",?")
        }
        try {
            rows := db.Query("SELECT * FROM snap_entry WHERE image_path IN (" . marks . ")", chunk*)
            for r in rows
                out[StrLower(r["image_path"])] := r
        } catch as err {
            AppMap_LogError("SnapRec_EntriesForPaths", err)
        }
    }
    return out
}

; The snap_entry row for an image on disk, matched on the stored path.
SnapRec_EntryForPath(path) {
    db := TrackDB()
    if !db
        return Map()
    row := db.QueryRow("SELECT * FROM snap_entry WHERE image_path=? LIMIT 1", path)
    if row.Count
        return row
    SplitPath(path, &fileName)
    return db.QueryRow("SELECT * FROM snap_entry WHERE image_path LIKE ? ORDER BY id DESC LIMIT 1"
                     , "%" . fileName)
}

; Fill search_query for rows captured before clue extraction existed, so the
; whole back catalogue becomes searchable from the database rather than only
; through filenames. Read-modify of one column; images are never touched.
;
; Done in timed chunks rather than one loop: measured on this database a single
; pass is ~18,400 rows at roughly 2 ms each even inside a transaction (nearly
; 9 ms each without one), which blocks the GUI for minutes and looks exactly
; like the button doing nothing. Each chunk commits and yields, so the window
; stays responsive and the status line reports progress.

global g_SnapBackfillQueue := []
global g_SnapBackfillPos := 0
global g_SnapBackfillDone := 0

SnapRec_BackfillStart() {
    global g_SnapBackfillQueue, g_SnapBackfillPos, g_SnapBackfillDone, g_SnapRecStatus
    db := TrackDB()
    if !db {
        ShowStatus("Tracking database is not open", "fail")
        return false
    }
    if g_SnapBackfillQueue.Length {
        ShowStatus("Backfill already running", "wait")
        return false
    }
    rows := db.Query("SELECT id, title FROM snap_entry "
                   . "WHERE (search_query IS NULL OR search_query='') AND title IS NOT NULL AND title<>''")
    if !rows.Length {
        try g_SnapRecStatus.Value := "Nothing to backfill - every snapshot already has a search phrase."
        ShowStatus("Nothing to backfill", "ok")
        return false
    }
    g_SnapBackfillQueue := rows
    g_SnapBackfillPos := 0
    g_SnapBackfillDone := 0
    try g_SnapRecStatus.Value := "Backfilling 0 / " . rows.Length . " ..."
    SetTimer(SnapRec_BackfillTick, -30)
    return true
}

SnapRec_BackfillTick() {
    global g_SnapBackfillQueue, g_SnapBackfillPos, g_SnapBackfillDone, g_SnapRecStatus
    static chunk := 400

    db := TrackDB()
    if (!db || !g_SnapBackfillQueue.Length) {
        g_SnapBackfillQueue := []
        return
    }
    total := g_SnapBackfillQueue.Length
    stop := Min(g_SnapBackfillPos + chunk, total)

    try db.Exec("BEGIN")
    try {
        while (g_SnapBackfillPos < stop) {
            g_SnapBackfillPos++
            r := g_SnapBackfillQueue[g_SnapBackfillPos]
            clue := SnapClue_FromTitle(r["title"])
            if (clue["query"] = "")
                continue
            db.Run("UPDATE snap_entry SET search_query=? WHERE id=?", clue["query"], r["id"])
            g_SnapBackfillDone++
        }
    } catch as err {
        AppMap_LogError("SnapRec_BackfillTick", err)
    }
    try db.Exec("COMMIT")

    if (g_SnapBackfillPos < total) {
        try g_SnapRecStatus.Value := "Backfilling " . g_SnapBackfillPos . " / " . total
            . "  (" . g_SnapBackfillDone . " phrases written) - the window stays usable."
        SetTimer(SnapRec_BackfillTick, -30)     ; yield, then continue
        return
    }

    done := g_SnapBackfillDone
    g_SnapBackfillQueue := []
    try g_SnapRecStatus.Value := "Backfill complete: " . done
        . " snapshot rows now carry a clean search phrase."
    ShowStatus("Backfill complete: " . done . " rows", "ok")
}

; ═══════════════════════════════════════════════════════════════════════════════
; 5. EVERYTHING SEARCH
; ═══════════════════════════════════════════════════════════════════════════════

SnapRec_Everything() {
    global g_SnapRecEverything
    if IsObject(g_SnapRecEverything)
        return g_SnapRecEverything
    ; Resolution order: <script>\lib, <script>, then the shared project root
    ; when the multi-file build defines APP_ROOT. The fan\ build lives one level
    ; below the root, so the last candidates let it load the same DLL the
    ; single-file original loads - no DLL copy needed inside fan\.
    dll := ""
    cands := [A_ScriptDir . "\lib\Everything3.dll", A_ScriptDir . "\Everything3.dll"]
    if IsSet(APP_ROOT) {
        cands.Push(APP_ROOT . "\lib\Everything3.dll")
        cands.Push(APP_ROOT . "\Everything3.dll")
    }
    for , c in cands {
        if FileExist(c) {
            dll := c
            break
        }
    }
    try g_SnapRecEverything := Everything3SDK(dll)
    catch as err {
        TrackLogError("SnapRec_Everything", err)
        return ""
    }
    return g_SnapRecEverything
}

; Everything's search syntax does not understand "." / ".." segments, so a
; query typed with parent-directory notation matches nothing. Flatten such
; paths to absolute form before the search runs:
;   "C:\a\..\b"      -> resolved from the drive root
;   "..\data\x"  and "\..\data\x"  -> resolved relative to DATA_DIR (the
;      snapshot archive's parent relationships are what users usually mean)
; Paths without ".." are returned unchanged.
SnapRec_ResolveQueryPath(p) {
    p := Trim(p)
    if (p = "" || !InStr(p, ".."))
        return p
    trail := (SubStr(p, -1) = "\" || SubStr(p, -1) = "/") ? "\" : ""
    r := RegExReplace(p, "[\\/]+$", "")
    rooted := RegExMatch(r, "^[A-Za-z]:", &dm) ? true : false
    if rooted {
        segs := StrSplit(SubStr(r, 3), "\", "/")
        out := [SubStr(r, 1, 2)]
    } else {
        segs := StrSplit(RegExReplace(r, "^[\\/]+", ""), "\", "/")
        out := []
        for , s in StrSplit(DATA_DIR, "\", "/")
            if (s != "")
                out.Push(s)
    }
    for , s in segs {
        if (s = "" || s = ".")
            continue
        if (s = "..") {
            if (out.Length > (rooted ? 1 : 0))
                out.Pop()
            continue
        }
        out.Push(s)
    }
    if (!rooted && !out.Length)
        return DATA_DIR . trail
    joined := ""
    for , s in out
        joined .= (joined = "" ? "" : "\") . s
    return joined . trail
}

; Rewrite every ancestor:/path:/parent:/folder: value in a query that contains
; ".." segments. Reports whether anything changed so the caller can tell the
; user the query was rewritten.
SnapRec_NormalizeQuery(query, &changed) {
    changed := false
    pos := 1
    while pos := RegExMatch(query, "i)\b(ancestor|path|parent|folder):(\x22[^\x22]*\x22|[^\s\x22]+)", &m, pos) {
        kw := m[1]
        val := m[2]
        inner := (SubStr(val, 1, 1) = '"') ? SubStr(val, 2, StrLen(val) - 2) : val
        res := SnapRec_ResolveQueryPath(inner)
        if (res != inner) {
            repl := kw . ':"' . res . '"'
            query := SubStr(query, 1, m.Pos - 1) . repl . SubStr(query, m.Pos + m.Len)
            pos := m.Pos + StrLen(repl)
            changed := true
        } else {
            pos := m.Pos + m.Len
        }
    }
    return query
}

; The preset list. Every entry is scoped to the snapshot archive, so none of
; them can trigger a machine-wide scan.
SnapRec_PresetNames() {
    return ["Today", "Yesterday", "Last 3 days", "Last 7 days", "This month"
          , "Everything ever captured"
          , "Browser captures only (Chrome / Edge / Firefox)"
          , "Video player captures (VLC)"
          , "Captures with a recorded URL"
          , "Largest / full-screen captures"
          , "Search by word - type it after the preset loads"]
}

SnapRec_PresetQuery(idx) {
    global DATA_DIR
    base := 'file: ancestor:"' . DATA_DIR . '\tracking\snapshots\" '
    d := (n) => FormatTime(DateAdd(A_Now, n, "Days"), "yyyy-MM-dd")
    switch idx {
        case 1: return base . "dc:" . d(0)
        case 2: return base . "dc:" . d(-1)
        case 3: return base . "dc:" . d(-2) . ".." . d(0)
        case 4: return base . "dc:" . d(-6) . ".." . d(0)
        case 5: return base . "dc:" . FormatTime(A_Now, "yyyy-MM") . "-01.." . d(0)
        case 6: return base
        case 7: return base . "Chrome|Edge|Firefox"
        case 8: return base . "VLC"
        case 9: return base . "dc:" . d(-6) . ".." . d(0)     ; refined below
        case 10: return base . "size:>800kb"
        case 11: return base
    }
    return base
}

; Apply the chosen preset. Some presets are a filter on the snapshot index
; rather than on filenames, and say so.
SnapRec_ApplyPreset(runIt := false) {
    global g_SnapRecPreset, g_SnapRecQuery, g_SnapRecStatus, g_SnapRecUrlOnly
    idx := g_SnapRecPreset.Value
    if (idx < 1)
        return
    g_SnapRecQuery.Value := SnapRec_PresetQuery(idx)
    g_SnapRecUrlOnly := (idx = 9)
    note := ""
    if (idx = 9)
        note := "  -  results are then filtered to those with a URL recorded at capture time."
    else if (idx = 11)
        note := "  -  add your word(s) at the end of the query, then press Search."
    g_SnapRecStatus.Value := "Preset loaded: " . g_SnapRecPreset.Text . note
    if (runIt || idx <= 10)
        SnapRec_Search()
}

; NOTE the "dc:" prefix on the date range. Without it Everything treats
; "2026-09-03..2026-09-05" as literal filename text and returns nothing at all -
; which is exactly how this tab came up empty before.
SnapRec_DefaultQuery() {
    global DATA_DIR
    return 'file: ancestor:"' . DATA_DIR . '\tracking\snapshots\" dc:'
         . FormatTime(DateAdd(A_Now, -2, "Days"), "yyyy-MM-dd") . ".."
         . FormatTime(A_Now, "yyyy-MM-dd")
}

; ═══════════════════════════════════════════════════════════════════════════════
; 6. THE SNAPSHOT RECOVERY TAB
; ═══════════════════════════════════════════════════════════════════════════════

SnapRec_BuildTab(g) {
    global g_SnapRecLV, g_SnapRecQuery, g_SnapRecPic, g_SnapRecEvidence
    global g_SnapRecStatus, g_SnapRecHistLV, g_SnapRecHistSearch
    global g_SnapRecPreset, g_SnapSigBtn, g_SnapRecCtl

    ; Every control is registered in g_SnapRecCtl so SnapRec_Layout can reflow
    ; the tab from one place. The positions below are only a first guess - the
    ; layout pass runs immediately and again on every resize, which is what
    ; stops controls from overlapping at any window size.
    g_SnapRecCtl := Map()

    ; ── row 1: the query ─────────────────────────────────────────────────────
    g_SnapRecCtl["qLabel"] := g.Add("Text", "x15 y54 w42", "Query:")
    ; -Multi -VScroll -WantReturn plus an explicit height: a query is one line,
    ; and without pinning the height something further down the resize chain can
    ; leave it two rows tall, overlapping the preset row beneath.
    g_SnapRecQuery := g.Add("Edit", "x60 y51 w520 h22 -Multi -VScroll -WantReturn"
                          , SnapRec_DefaultQuery())
    g_SnapRecQuery.SetFont("s9", "Consolas")
    g_SnapRecCtl["query"] := g_SnapRecQuery
    g_SnapRecCtl["search"] := g.Add("Button", "x585 y50 w90 h24 Default cGreen", "🔍 Search")
    g_SnapRecCtl["search"].OnEvent("Click", (*) => SnapRec_Search())
    g_SnapRecCtl["reset"] := g.Add("Button", "x680 y50 w90 h24", "Reset Query")
    g_SnapRecCtl["reset"].OnEvent("Click", (*) => (g_SnapRecQuery.Value := SnapRec_DefaultQuery()))

    ; ── row 2: presets and backfill ──────────────────────────────────────────
    g_SnapRecCtl["pLabel"] := g.Add("Text", "x15 y82 w42", "Preset:")
    g_SnapRecPreset := g.Add("DropDownList", "x60 y79 w300", SnapRec_PresetNames())
    g_SnapRecPreset.OnEvent("Change", (*) => SnapRec_ApplyPreset())
    g_SnapRecCtl["preset"] := g_SnapRecPreset
    g_SnapRecCtl["usePreset"] := g.Add("Button", "x366 y78 w86 h22", "Use preset")
    g_SnapRecCtl["usePreset"].OnEvent("Click", (*) => SnapRec_ApplyPreset(true))
    g_SnapRecCtl["backfill"] := g.Add("Button", "x458 y78 w217 h22", "Backfill phrases for old snapshots")
    g_SnapRecCtl["backfill"].OnEvent("Click", (*) => SnapRec_BackfillUI())

    ; ── left column: preview, evidence, actions ──────────────────────────────
    g_SnapRecCtl["previewHdr"] := g.Add("Text", "x15 y112 w300", "Snapshot preview")
    g_SnapRecPic := g.Add("Picture", "x15 y130 w400 h240 Border")
    g_SnapRecCtl["pic"] := g_SnapRecPic
    g_SnapRecCtl["evidenceHdr"] := g.Add("Text", "x15 y378 w300", "Evidence and recovery")
    g_SnapRecEvidence := g.Add("Edit", "x15 y396 w400 h150 ReadOnly Multi VScroll -Wrap")
    g_SnapRecEvidence.SetFont("s8", "Consolas")
    g_SnapRecCtl["evidence"] := g_SnapRecEvidence

    Btn(key, opts, label, cb) {
        global g_SnapRecCtl
        b := g_SnapRecCtl["__gui"].Add("Button", opts, label)
        b.OnEvent("Click", cb)
        g_SnapRecCtl[key] := b
        return b
    }
    g_SnapRecCtl["__gui"] := g
    Btn("bOpen", "x15 y556 w97 h24", "Open Image", (*) => SnapRec_OpenImage())
    Btn("bFolder", "x116 y556 w97 h24", "Show in Folder", (*) => SnapRec_ShowInFolder())
    Btn("bPhrase", "x217 y556 w97 h24", "Copy Phrase", (*) => SnapRec_CopyPhrase())
    Btn("bPath", "x318 y556 w97 h24", "Copy Path", (*) => SnapRec_CopyPath())
    Btn("bGoogle", "x15 y584 w97 h24 cBlue", "Google Phrase", (*) => SnapRec_GooglePhrase())
    Btn("bUrl", "x116 y584 w97 h24 cBlue", "Open URL / file", (*) => SnapRec_OpenUrl())
    Btn("bOcr", "x217 y584 w198 h24", "OCR This Image", (*) => SnapRec_OcrSelected())
    g_SnapSigBtn := Btn("bSig", "x15 y612 w130 h24", "Signature: Exclude Same"
                      , (*) => SnapRec_ExcludeSignature())
    g_SnapSigBtn.ToolTip := "Hide every snapshot that looks like the selected one. "
                          . "While a scan runs this button stops it."
    Btn("bExWin", "x149 y612 w130 h24", "Exclude This Window", (*) => SnapRec_ExcludeWindow())
    Btn("bManage", "x283 y612 w132 h24", "Manage Exclusions", (*) => SnapRec_ShowExclusions())
    Btn("bHistTitle", "x15 y640 w198 h24", "Match Chrome History (title)"
      , (*) => SnapRec_HistoryMatch(false))
    Btn("bHistTime", "x217 y640 w198 h24", "Chrome History Around This Time"
      , (*) => SnapRec_HistoryMatch(true))

    ; ── right column: the results, given the width they need ─────────────────
    g_SnapRecCtl["resultsHdr"] := g.Add("Text", "x430 y112 w440"
        , "Results  -  click a heading to sort; hover any cell for its full text")
    g_SnapRecLV := g.Add("ListView", "x430 y130 w440 h300 Grid"
        , ["Time", "Search phrase (underscores removed)", "Site", "Recorded URL", "App", "File"])
    g_SnapRecLV.OnEvent("ItemSelect", (lv, row, sel) => (sel ? SnapRec_OnSelect(row) : 0))
    g_SnapRecLV.OnEvent("DoubleClick", (lv, row) => SnapRec_OpenImage())
    ; LVS_EX_LABELTIP: Windows itself shows the full text of any cell too narrow
    ; to display it, so columns can be squeezed without losing readability.
    g_SnapRecLV.Opt("+LV0x4000")
    g_SnapRecCtl["lv"] := g_SnapRecLV

    g_SnapRecStatus := g.Add("Text", "x430 y436 w440 cGray"
        , "Choose a preset or enter a query, then press Search.")
    g_SnapRecCtl["status"] := g_SnapRecStatus

    g_SnapRecCtl["histHdr"] := g.Add("Text", "x430 y458 w440"
        , "Chrome history  -  double-click a row to open the page")
    g_SnapRecCtl["histLabel"] := g.Add("Text", "x430 y480 w44", "Search:")
    g_SnapRecHistSearch := g.Add("Edit", "x478 y477 w200")
    g_SnapRecCtl["histSearch"] := g_SnapRecHistSearch
    Btn("histGo", "x684 y476 w80 h24", "Search", (*) => ChromeHist_ExplorerSearch())
    Btn("histRefresh", "x768 y476 w102 h24", "Sync now", (*) => ChromeHist_SyncNowUI())
    Btn("histOpenAll", "x874 y476 w132 h24", "Open all in Chrome"
      , (*) => SnapRec_OpenAllHistory())
    g_SnapRecCtl["histOpenAll"].ToolTip := "Open every listed history row in Chrome, "
        . "one tab each. Duplicate addresses are opened only once."
    g_SnapRecHistLV := g.Add("ListView", "x430 y506 w440 h158 Grid"
        , ["Visited", "vs snapshot", "Title", "Search term typed", "URL"])
    g_SnapRecHistLV.OnEvent("DoubleClick", (lv, row) => SnapRec_OpenHistoryRow(row))
    g_SnapRecHistLV.Opt("+LV0x4000")
    g_SnapRecCtl["histLV"] := g_SnapRecHistLV

    SnapRec_Layout(880, 720)

    ; Keep the history archive current without anyone having to remember to.
    SetTimer(ChromeHist_AutoSyncTick, 300000)
    SetTimer(() => ChromeHist_SyncIfStale(0), -8000)     ; startup catch-up
}

; Reflow the whole tab. Called once at build time and again from the window's
; resize handler, so the tab always fills whatever space it is given and no two
; controls can land on top of each other.
SnapRec_Layout(w, h) {
    global g_SnapRecCtl
    if (!IsObject(g_SnapRecCtl) || !g_SnapRecCtl.Count)
        return
    w := Max(w, 780), h := Max(h, 560)
    pad := 15, top := 50

    ; The results table takes the larger share; the left column needs only
    ; enough room for a preview and the action buttons.
    leftW := Min(430, Max(330, Integer(w * 0.36)))
    rightX := pad + leftW + 14
    rightW := Max(320, w - rightX - pad)

    ; Control.Move takes OPTIONAL width/height. Passing an empty string for one
    ; is not the same as omitting it - it throws, and a try around the call then
    ; swallows the failure so the control silently stays where it was built.
    ; That is what left the status line and history header sitting on top of the
    ; results list. Each arity is therefore called explicitly.
    Mv(key, x, y, cw := "", chh := "") {
        global g_SnapRecCtl
        if !g_SnapRecCtl.Has(key)
            return
        c := g_SnapRecCtl[key]
        try {
            if (cw = "")
                c.Move(x, y)
            else if (chh = "")
                c.Move(x, y, cw)
            else
                c.Move(x, y, cw, chh)
        }
    }

    ; row 1 - the query stretches, its two buttons stay pinned to its right.
    ; The height is restated every pass so the field can never grow a second row.
    qW := Max(200, leftW + 14 + rightW - 45 - 196)
    Mv("qLabel", pad, top + 5, 42, 16)
    Mv("query", pad + 45, top + 1, qW, 22)
    Mv("search", pad + 45 + qW + 8, top, 90, 24)
    Mv("reset", pad + 45 + qW + 103, top, 90, 24)

    ; row 2 - presets, a clear 12px below the query row rather than 6
    row2 := top + 36
    presetW := Min(340, Max(180, Integer(qW * 0.55)))
    Mv("pLabel", pad, row2 + 4, 42, 16)
    Mv("preset", pad + 45, row2, presetW, 21)
    Mv("usePreset", pad + 51 + presetW, row2 - 1, 86, 23)
    Mv("backfill", pad + 145 + presetW, row2 - 1, 217, 23)

    ; ── left column ──────────────────────────────────────────────────────────
    y := top + 70
    Mv("previewHdr", pad, y, leftW)
    picH := Max(150, Integer((h - 300) * 0.46))
    Mv("pic", pad, y + 18, leftW, picH)
    ey := y + 18 + picH + 10
    Mv("evidenceHdr", pad, ey, leftW)
    btnBlock := 112
    evH := Max(70, h - ey - 18 - btnBlock - 12)
    Mv("evidence", pad, ey + 18, leftW, evH)

    by := ey + 18 + evH + 10
    q4 := Integer((leftW - 15) / 4)
    Mv("bOpen", pad, by, q4, 24)
    Mv("bFolder", pad + q4 + 5, by, q4, 24)
    Mv("bPhrase", pad + (q4 + 5) * 2, by, q4, 24)
    Mv("bPath", pad + (q4 + 5) * 3, by, q4, 24)
    Mv("bGoogle", pad, by + 28, q4, 24)
    Mv("bUrl", pad + q4 + 5, by + 28, q4, 24)
    Mv("bOcr", pad + (q4 + 5) * 2, by + 28, q4 * 2 + 5, 24)
    t3 := Integer((leftW - 10) / 3)
    Mv("bSig", pad, by + 56, t3, 24)
    Mv("bExWin", pad + t3 + 5, by + 56, t3, 24)
    Mv("bManage", pad + (t3 + 5) * 2, by + 56, t3, 24)
    half := Integer((leftW - 6) / 2)
    Mv("bHistTitle", pad, by + 84, half, 24)
    Mv("bHistTime", pad + half + 6, by + 84, half, 24)

    ; ── right column ─────────────────────────────────────────────────────────
    ry := top + 70
    Mv("resultsHdr", rightX, ry, rightW)
    lvH := Max(160, Integer((h - ry - 160) * 0.62))
    Mv("lv", rightX, ry + 18, rightW, lvH)
    sy := ry + 18 + lvH + 6
    Mv("status", rightX, sy, rightW)
    hy := sy + 22
    Mv("histHdr", rightX, hy, rightW)
    Mv("histLabel", rightX, hy + 25, 44)
    searchW := Max(120, rightW - 390)
    Mv("histSearch", rightX + 48, hy + 22, searchW)
    Mv("histGo", rightX + 52 + searchW, hy + 21, 80, 24)
    Mv("histRefresh", rightX + 136 + searchW, hy + 21, 116, 24)
    Mv("histOpenAll", rightX + 256 + searchW, hy + 21, Max(120, rightW - searchW - 260), 24)
    histH := Max(90, h - (hy + 52) - 4)
    Mv("histLV", rightX, hy + 52, rightW, histH)

    SnapRec_FitColumns(rightW)
}

; Share the available width between columns rather than using fixed pixel
; widths that either clip or waste space. Anything still too narrow shows in
; full on hover, via the label-tip style set when the lists were created.
SnapRec_FitColumns(totalW) {
    global g_SnapRecLV, g_SnapRecHistLV
    w := Max(300, totalW - 26)
    try {
        g_SnapRecLV.ModifyCol(1, 118)
        g_SnapRecLV.ModifyCol(2, Max(150, Integer(w * 0.33)))
        g_SnapRecLV.ModifyCol(3, Max(60, Integer(w * 0.09)))
        g_SnapRecLV.ModifyCol(4, Max(90, Integer(w * 0.25)))
        g_SnapRecLV.ModifyCol(5, Max(70, Integer(w * 0.11)))
        g_SnapRecLV.ModifyCol(6, 0)
    }
    try {
        g_SnapRecHistLV.ModifyCol(1, 116)
        g_SnapRecHistLV.ModifyCol(2, 78)
        g_SnapRecHistLV.ModifyCol(3, Max(110, Integer(w * 0.28)))
        g_SnapRecHistLV.ModifyCol(4, Max(90, Integer(w * 0.18)))
        g_SnapRecHistLV.ModifyCol(5, Max(120, Integer(w * 0.25)))
    }
}

SnapRec_Search() {
    global g_SnapRecQuery, g_SnapRecLV, g_SnapRecRows, g_SnapRecStatus, g_SnapRecUrlOnly

    query := Trim(g_SnapRecQuery.Value)
    if (query = "")
        return

    ; Expand any ".." path segments typed into the query (Everything's search
    ; syntax cannot resolve them itself, so such queries return nothing).
    normChanged := false
    query := SnapRec_NormalizeQuery(query, &normChanged)
    if normChanged {
        g_SnapRecQuery.Value := query
        ShowStatus("Query path expanded to an absolute folder", "wait")
    }

    ; A query with no folder constraint asks Everything about the entire
    ; machine. "dc:2026-09-03" alone matches every file created that day, and
    ; the search call blocks the GUI while it builds that result set - which is
    ; what makes the window stop responding. Scope it to the snapshot archive.
    if !RegExMatch(query, "i)\b(ancestor|path|parent|folder):") {
        query := 'file: ancestor:"' . DATA_DIR . '\tracking\snapshots\" ' . query
        g_SnapRecQuery.Value := query
        ShowStatus("Query had no folder limit - scoped it to the snapshot archive", "wait")
    }

    ev := SnapRec_Everything()
    if !IsObject(ev) {
        g_SnapRecStatus.Value := "Everything3.dll could not be loaded (expected in lib\)."
        return
    }
    g_SnapRecStatus.Value := "Searching..."
    res := ev.Search(query, 1000)
    if !res.Ok {
        g_SnapRecStatus.Value := "Everything search failed: " . res.Error
              . "   (is Everything 1.5 running?)"
        return
    }

    ; Collect the image paths first, then resolve every snapshot row in a
    ; handful of batched queries rather than one lookup per result.
    imagePaths := []
    for , r in res.Results {
        if (!r.IsDirectory && (r.Path ~= "i)\.(png|jpg|jpeg|bmp|gif|webp)$"))
            imagePaths.Push(r.Path)
    }
    entries := SnapRec_EntriesForPaths(imagePaths)

    g_SnapRecLV.Opt("-Redraw")
    g_SnapRecLV.Delete()
    g_SnapRecRows := []
    images := 0
    for , path in imagePaths {
        ; "Captures with a recorded URL" filters on the index, not the filename,
        ; because a filename never carries the address.
        if g_SnapRecUrlOnly {
            e0 := entries.Has(StrLower(path)) ? entries[StrLower(path)] : Map()
            if (!e0.Count || !e0.Has("url") || e0["url"] = "")
                continue
        }
        images++
        clue := SnapClue_FromFilename(path)
        entry := entries.Has(StrLower(path)) ? entries[StrLower(path)] : Map()
        if (entry.Count && entry.Has("is_excluded") && entry["is_excluded"])
            continue
        url := entry.Count && entry.Has("url") ? entry["url"] : ""
        ts := entry.Count ? entry["ts"] : ""
        if (ts = "") {
            try ts := FormatTime(FileGetTime(path, "C"), "yyyy-MM-dd HH:mm:ss")
        }
        SplitPath(path, &fileName)
        ; The stored window title is the untruncated original; the filename on
        ; disk is cut to fit, so prefer a phrase derived from the title.
        if entry.Count {
            stored := entry.Has("search_query") ? entry["search_query"] : ""
            if (stored != "")
                clue["query"] := stored
            else if (entry["title"] != "") {
                fromTitle := SnapClue_FromTitle(entry["title"])
                if (StrLen(fromTitle["query"]) > StrLen(clue["query"])) {
                    clue["query"] := fromTitle["query"]
                    if (clue["site"] = "")
                        clue["site"] := fromTitle["site"]
                }
            }
        }
        row := Map("path", path, "file", fileName, "ts", ts, "clue", clue
                 , "url", url, "entry", entry)
        g_SnapRecRows.Push(row)
        g_SnapRecLV.Add(, ts, clue["query"], clue["site"]
                      , url != "" ? url : "(none recorded)", clue["app"], g_SnapRecRows.Length)
    }
    g_SnapRecLV.Opt("+Redraw")
    ; Without the tracking database every row loses its recorded URL and stored
    ; title, so say that plainly instead of showing a page full of "(none)".
    indexNote := SnapRec_IndexReady() ? ""
        : "  ⚠ tracking.db is not open - recorded URLs and titles are unavailable."
    g_SnapRecStatus.Value := "Everything returned " . res.Results.Length . " results; "
        . images . " snapshot images listed. Select one to see its evidence." . indexNote
}

SnapRec_Selected() {
    global g_SnapRecLV, g_SnapRecRows
    row := g_SnapRecLV.GetNext()
    if (!row)
        return Map()
    idx := Integer(g_SnapRecLV.GetText(row, 6))
    return (idx >= 1 && idx <= g_SnapRecRows.Length) ? g_SnapRecRows[idx] : Map()
}

SnapRec_OnSelect(lvRow) {
    global g_SnapRecPic, g_SnapRecEvidence
    rec := SnapRec_Selected()
    if !rec.Count
        return
    try g_SnapRecPic.Value := rec["path"]

    clue := rec["clue"]
    entry := rec["entry"]
    txt := "SEARCH PHRASE (underscores removed - paste this into Google)`r`n  "
         . clue["query"] . "`r`n`r`n"
    if (clue["site"] != "")
        txt .= "SITE      " . clue["site"] . "`r`n"
    if (clue["app"] != "")
        txt .= "APP       " . clue["app"] . "`r`n"
    txt .= "CAPTURED  " . (rec["ts"] != "" ? rec["ts"] : "(unknown)") . "`r`n"
    ; Browser captures have an address; a capture of VLC, Everything or any
    ; other file-backed window has a path instead. Resolve whichever applies so
    ; the row always points at something openable.
    if (rec["url"] != "")
        txt .= "URL       " . rec["url"] . "`r`n"
    else {
        srcTitle := entry.Count && entry["title"] != "" ? entry["title"] : rec["clue"]["raw"]
        filePath := ""
        try filePath := Media_PathFromTitle(srcTitle, entry.Count ? entry["exe"] : "")
        if (filePath != "")
            txt .= "FILE      " . filePath . "`r`n"
        else
            txt .= "URL       (not recorded - captured before URL logging, use history match)`r`n"
    }
    if entry.Count {
        txt .= "`r`nSNAPSHOT INDEX`r`n"
        txt .= "  entry #" . entry["id"] . "  exe=" . entry["exe"]
             . "  " . entry["w"] . "x" . entry["h"] . "`r`n"
        txt .= "  title: " . entry["title"] . "`r`n"
        if (entry.Has("visual_signature") && entry["visual_signature"] != "")
            txt .= "  signature: " . entry["visual_signature"] . "`r`n"
        ocr := entry.Has("ocr_text") ? entry["ocr_text"] : ""
        if (Trim(ocr) != "") {
            urls := SnapClue_UrlsFromText(ocr)
            if urls.Length {
                txt .= "`r`nURLs SEEN IN THE IMAGE (OCR)`r`n"
                for , u in urls
                    txt .= "  " . u . "`r`n"
            }
            txt .= "`r`nOCR TEXT`r`n  " . TrackEllipsis(StrReplace(ocr, "`n", " "), 600) . "`r`n"
        }
    } else {
        txt .= "`r`n(no snap_entry row for this file - it is on disk but not in the index)`r`n"
    }
    txt .= "`r`nFILE`r`n  " . rec["path"]
    g_SnapRecEvidence.Value := txt
}

SnapRec_OpenImage() {
    rec := SnapRec_Selected()
    if rec.Count
        try Run('"' . rec["path"] . '"')
}

SnapRec_ShowInFolder() {
    rec := SnapRec_Selected()
    if rec.Count
        try Run('explorer.exe /select,"' . rec["path"] . '"')
}

SnapRec_CopyPhrase() {
    rec := SnapRec_Selected()
    if !rec.Count
        return
    A_Clipboard := rec["clue"]["query"]
    ShowStatus("Copied search phrase: " . TrackEllipsis(rec["clue"]["query"], 50), "ok")
}

; Full path of the selected image (or of every selected row with Shift held),
; which is what a file manager, a script or another tool actually needs.
SnapRec_CopyPath() {
    global g_SnapRecLV, g_SnapRecRows
    paths := []
    if GetKeyState("Shift", "P") {
        row := 0
        while (row := g_SnapRecLV.GetNext(row)) {
            idx := Integer(g_SnapRecLV.GetText(row, 6))
            if (idx >= 1 && idx <= g_SnapRecRows.Length)
                paths.Push(g_SnapRecRows[idx]["path"])
        }
    } else {
        rec := SnapRec_Selected()
        if rec.Count
            paths.Push(rec["path"])
    }
    if !paths.Length {
        ShowStatus("Select a snapshot row first", "wait")
        return
    }
    out := ""
    for , p in paths
        out .= (out = "" ? "" : "`r`n") . p
    A_Clipboard := out
    ShowStatus(paths.Length = 1
        ? "Copied path: " . TrackEllipsis(paths[1], 60)
        : "Copied " . paths.Length . " full paths", "ok")
}

SnapRec_GooglePhrase() {
    rec := SnapRec_Selected()
    if !rec.Count
        return
    q := rec["clue"]["query"]
    if (q = "")
        return
    Research_OpenUrl("https://www.google.com/search?q=" . Research_UrlEncode(q))
}

SnapRec_OpenUrl() {
    rec := SnapRec_Selected()
    if !rec.Count
        return
    if (rec["url"] != "") {
        Research_OpenUrl(rec["url"])
        return
    }
    ; No address: this may be a capture of a local file (VLC, Everything...).
    entry := rec["entry"]
    srcTitle := entry.Count && entry["title"] != "" ? entry["title"] : rec["clue"]["raw"]
    filePath := ""
    try filePath := Media_PathFromTitle(srcTitle, entry.Count ? entry["exe"] : "")
    if (filePath != "") {
        try Run('explorer.exe /select,"' . filePath . '"')
        ShowStatus("Revealed the played file: " . TrackEllipsis(filePath, 60), "ok")
        return
    }
    ShowStatus("No URL or file resolved for this snapshot - try the history match buttons", "fail")
}

; OCR the snapshot image and store the text back on its snap_entry row, so the
; evidence panel can mine it for URLs.
SnapRec_OcrSelected() {
    rec := SnapRec_Selected()
    if !rec.Count
        return
    ShowStatus("Running OCR on the snapshot...", "wait")
    text := ""
    try text := OCR.FromFile(rec["path"], {scale: 2}).Text
    catch as err
        TrackLogError("SnapRec_OcrSelected", err)
    if (Trim(text) = "") {
        ShowStatus("OCR found no text in that image", "fail")
        return
    }
    entry := rec["entry"]
    if entry.Count {
        db := TrackDB()
        if db
            db.Run("UPDATE snap_entry SET ocr_text=? WHERE id=?", text, entry["id"])
        entry["ocr_text"] := text
    }
    ; Segment the raw text into meaning before it reaches the user: interface
    ; furniture is stripped, addresses and media timecodes are pulled out, and a
    ; headline is chosen. The clipboard then carries the useful part first
    ; instead of a wall of characters.
    hint := entry.Count ? entry["title"] : rec["clue"]["query"]
    seg := OcrSeg_Analyse(text, hint)
    A_Clipboard := seg["clipboard"]
    urls := seg["urls"]
    ShowStatus("OCR copied to clipboard - " . seg["context"], "ok")
    SnapRec_OnSelect(0)
}

; Create a perceptual signature rule, then walk the complete indexed archive in
; small timed batches. This keeps the GUI responsive even with many thousands
; of snapshots. Historical matches are hidden, not deleted.
SnapRec_ExcludeSignature() {
    global g_SnapSigWork, g_SnapRecStatus, g_SnapSigBtn
    ; A scan in progress turns this button into its own stop control - there was
    ; previously no way to interrupt a walk of the whole archive.
    if (g_SnapSigWork.Count && g_SnapSigWork.Has("running") && g_SnapSigWork["running"]) {
        SnapRec_StopSignatureScan("stopped by you")
        return
    }
    rec := SnapRec_Selected()
    if !rec.Count {
        ShowStatus("Select a snapshot first", "wait")
        return
    }
    if !FileExist(rec["path"]) {
        ShowStatus("The selected image is no longer on disk", "fail")
        return
    }
    ; Scanning the archive means opening and fingerprinting every snapshot that
    ; does not yet have one - on this database that is tens of thousands of
    ; images and takes minutes. It is worth offering, but never worth doing
    ; silently just because a rule was created.
    db0 := TrackDB()
    pending := 0
    if db0 {
        try pending := Integer(db0.Scalar("SELECT COUNT(*) FROM snap_entry "
            . "WHERE image_path<>'' AND COALESCE(is_excluded,0)=0 "
            . "AND (visual_signature IS NULL OR visual_signature='')"))
    }
    answer := MsgBox("Create a visual signature from this image and hide snapshots that match it?"
                   . "`n`nYES  - also scan the whole archive now."
                   . (pending > 0
                        ? "`n         " . pending . " snapshot(s) still need a fingerprint, so this"
                        . "`n         first pass takes a while. Fingerprints are saved, so"
                        . "`n         later scans are quick. The button becomes Stop."
                        : "`n         Every snapshot is already fingerprinted, so this is quick.")
                   . "`n`nNO   - just save the rule. It hides matches in the current results"
                   . "`n         and any future snapshot, with no archive scan."
                   . "`n`nFiles always stay on disk and can be restored from Manage Exclusions."
                   , "Exclude matching pictures", "YesNoCancel Icon!")
    if (answer = "Cancel")
        return
    scanArchive := (answer = "Yes")

    signature := Snap_VisualSignature(rec["path"])
    if signature = "" {
        ShowStatus("Could not calculate a visual signature", "fail")
        return
    }
    db := TrackDB()
    if !db {
        ShowStatus("Tracking database is not open", "fail")
        return
    }
    ruleId := TrackDB_AddSignatureExclusion(signature, 5, "Selected: " . rec["path"])
    if !ruleId {
        ShowStatus("Could not save the exclusion rule", "fail")
        return
    }
    if rec["entry"].Count
        db.Run("UPDATE snap_entry SET visual_signature=? WHERE id=?"
             , signature, rec["entry"]["id"])

    if !scanArchive {
        ; Rule only: hide what already carries a matching fingerprint, which is
        ; instant, and leave the rest to be caught as snapshots are captured.
        quick := 0
        try {
            rows := db.Query("SELECT id,visual_signature FROM snap_entry "
                           . "WHERE visual_signature IS NOT NULL AND visual_signature<>'' "
                           . "AND COALESCE(is_excluded,0)=0")
            db.Begin()
            for r in rows {
                if (Snap_SignatureDistance(signature, r["visual_signature"]) <= 5) {
                    db.Run("UPDATE snap_entry SET is_excluded=1,exclusion_reason=? WHERE id=?"
                         , "rule:" . ruleId, r["id"])
                    quick++
                }
            }
            db.Commit()
        } catch as err {
            try db.Rollback()
            TrackLogError("SnapRec_ExcludeSignature(quick)", err)
        }
        try TrackDB_BumpSnapshotExclusion(ruleId, quick)
        SnapRec_Search()
        g_SnapRecStatus.Value := "Rule saved. " . quick . " already-fingerprinted snapshot(s) hidden; "
            . "no archive scan run. Future captures are checked automatically."
        ShowStatus("Signature rule saved (no archive scan)", "ok")
        return
    }

    queue := db.Query("SELECT id,image_path,visual_signature FROM snap_entry "
                    . "WHERE image_path<>'' AND COALESCE(is_excluded,0)=0 ORDER BY id")
    g_SnapSigWork := Map("running", true, "signature", signature, "rule_id", ruleId
                       , "queue", queue, "pos", 0, "matched", 0, "hashed", 0
                       , "missing", 0)
    if IsObject(g_SnapSigBtn)
        try g_SnapSigBtn.Text := "STOP Signature Scan"
    g_SnapRecStatus.Value := "Signature " . signature . ": scanning 0 / " . queue.Length . " ..."
    ShowStatus("Scanning the archive - press the same button again to stop", "wait")
    SetTimer(SnapRec_SignatureTick, -25)
}

; Halt a running archive scan. Fingerprints already computed are kept - they are
; written as they go - so stopping wastes nothing and a later scan resumes from
; the work already done.
SnapRec_StopSignatureScan(why := "stopped") {
    global g_SnapSigWork, g_SnapRecStatus
    if (!g_SnapSigWork.Count || !g_SnapSigWork.Has("running"))
        return
    work := g_SnapSigWork
    done := work.Has("pos") ? work["pos"] : 0
    total := work.Has("queue") ? work["queue"].Length : 0
    matched := work.Has("matched") ? work["matched"] : 0
    hashed := work.Has("hashed") ? work["hashed"] : 0
    ruleId := work.Has("rule_id") ? work["rule_id"] : 0
    g_SnapSigWork := Map()
    SetTimer(SnapRec_SignatureTick, 0)
    if ruleId
        try TrackDB_BumpSnapshotExclusion(ruleId, matched)
    SnapRec_ResetSignatureButton()
    try g_SnapRecStatus.Value := "Signature scan " . why . " at " . done . " / " . total
        . " - " . matched . " hidden, " . hashed . " fingerprints kept. "
        . "The rule stays active for new snapshots."
    ShowStatus("Signature scan " . why, "ok")
}

SnapRec_ResetSignatureButton() {
    global g_SnapSigBtn
    if IsObject(g_SnapSigBtn)
        try g_SnapSigBtn.Text := "Signature: Exclude Same"
}

SnapRec_SignatureTick() {
    global g_SnapSigWork, g_SnapRecStatus
    if (!g_SnapSigWork.Count || !g_SnapSigWork["running"])
        return
    db := TrackDB()
    if !db {
        g_SnapSigWork := Map()
        SnapRec_ResetSignatureButton()
        ShowStatus("Signature scan stopped: database unavailable", "fail")
        return
    }
    work := g_SnapSigWork
    queue := work["queue"]
    stop := Min(queue.Length, work["pos"] + 30)
    try db.Begin()
    try {
        while (work["pos"] < stop) {
            work["pos"]++
            r := queue[work["pos"]]
            sig := r["visual_signature"]
            if (sig = "" && FileExist(r["image_path"])) {
                sig := Snap_VisualSignature(r["image_path"])
                if sig != "" {
                    db.Run("UPDATE snap_entry SET visual_signature=? WHERE id=?", sig, r["id"])
                    work["hashed"]++
                }
            } else if sig = "" {
                work["missing"]++
            }
            if (sig != "" && Snap_SignatureDistance(work["signature"], sig) <= 5) {
                db.Run("UPDATE snap_entry SET is_excluded=1,exclusion_reason=? WHERE id=?"
                     , "rule:" . work["rule_id"], r["id"])
                work["matched"]++
            }
        }
        db.Commit()
    } catch as err {
        try db.Rollback()
        TrackLogError("SnapRec_SignatureTick", err)
        g_SnapSigWork := Map()
        SnapRec_ResetSignatureButton()
        ShowStatus("Signature scan stopped: " . err.Message, "fail")
        return
    }

    g_SnapRecStatus.Value := "Signature scan " . work["pos"] . " / " . queue.Length
        . " — " . work["matched"] . " match(es), " . work["hashed"] . " new fingerprints."
    if (work["pos"] < queue.Length) {
        SetTimer(SnapRec_SignatureTick, -25)
        return
    }

    matched := work["matched"], ruleId := work["rule_id"]
    try TrackDB_BumpSnapshotExclusion(ruleId, matched)
    g_SnapSigWork := Map()
    SnapRec_ResetSignatureButton()
    SnapRec_Search()
    g_SnapRecStatus.Value := "Signature scan complete: " . matched
        . " matching snapshot(s) hidden; originals remain on disk."
    ShowStatus("Signature exclusion complete: " . matched . " hidden", "ok")
    if IsObject(g_SnapExclusionGui)
        try SnapRec_LoadExclusions()
}

; Add a persistent rule for the selected window identity and immediately hide
; matching historical snapshots. Exact exe/class + title substring avoids
; suppressing unrelated windows from the same program.
SnapRec_ExcludeWindow() {
    rec := SnapRec_Selected()
    if !rec.Count {
        ShowStatus("Select a snapshot first", "wait")
        return
    }
    entry := rec["entry"]
    if !entry.Count {
        ShowStatus("This file has no snapshot-index row, so its window identity is unknown", "fail")
        return
    }
    title := Trim(entry["title"]), exe := entry["exe"], class := entry["class"]
    answer := MsgBox("Exclude future captures of this window and hide its indexed history?"
                   . "`n`nTitle contains: " . (title != "" ? title : "(any title)")
                   . "`nExecutable: " . exe . "`nClass: " . class
                   . "`n`nHistorical image files remain on disk."
                   , "Exclude this window", "YesNo Icon!")
    if answer != "Yes"
        return
    db := TrackDB()
    ruleId := TrackDB_AddWindowExclusion(title, exe, class, "Selected from " . rec["path"])
    if !ruleId {
        ShowStatus("Could not save the window exclusion", "fail")
        return
    }
    like := "%" . title . "%"
    db.Run("UPDATE snap_entry SET is_excluded=1,exclusion_reason=? "
         . "WHERE COALESCE(is_excluded,0)=0 AND (?='' OR title LIKE ?) "
         . "AND (?='' OR lower(exe)=lower(?)) AND (?='' OR lower(class)=lower(?))"
         , "rule:" . ruleId, title, like, exe, exe, class, class)
    matched := db.Changes()
    if matched
        TrackDB_BumpSnapshotExclusion(ruleId, matched)
    SnapRec_Search()
    ShowStatus("Window exclusion saved; " . matched . " historical snapshot(s) hidden", "ok")
    if IsObject(g_SnapExclusionGui)
        try SnapRec_LoadExclusions()
}

SnapRec_ShowExclusions(*) {
    global g_SnapExclusionGui, g_SnapExclusionLV
    if IsObject(g_SnapExclusionGui) {
        try g_SnapExclusionGui.Destroy()
    }
    g_SnapExclusionGui := Gui("+Resize +MinSize720x360", "Snapshot Exclusions")
    g_SnapExclusionGui.SetFont("s9", "Segoe UI")
    g_SnapExclusionGui.Add("Text", "x10 y10 w690"
        , "Disabled rules restore hidden index rows. Historical image files are never deleted.")
    g_SnapExclusionLV := g_SnapExclusionGui.Add("ListView", "x10 y35 w880 h330 Grid"
        , ["ID", "Type", "Match", "Created", "Hits", "Last match"])
    g_SnapExclusionLV.ModifyCol(1, 55)
    g_SnapExclusionLV.ModifyCol(2, 80)
    g_SnapExclusionLV.ModifyCol(3, 390)
    g_SnapExclusionLV.ModifyCol(4, 145)
    g_SnapExclusionLV.ModifyCol(5, 65)
    g_SnapExclusionLV.ModifyCol(6, 145)
    g_SnapExclusionGui.Add("Button", "x10 y375 w150 h27", "Disable Selected Rule")
        .OnEvent("Click", (*) => SnapRec_DisableExclusion())
    g_SnapExclusionGui.Add("Button", "x166 y375 w90 h27", "Refresh")
        .OnEvent("Click", (*) => SnapRec_LoadExclusions())
    g_SnapExclusionGui.OnEvent("Size", SnapRec_ExclusionsResize)
    g_SnapExclusionGui.OnEvent("Close", (*) => (g_SnapExclusionGui := ""))
    SnapRec_LoadExclusions()
    g_SnapExclusionGui.Show("w900 h420")
}

SnapRec_ExclusionsResize(guiObj, minMax, width, height) {
    global g_SnapExclusionLV
    if minMax = -1
        return
    try g_SnapExclusionLV.Move(, , Max(500, width - 20), Max(220, height - 90))
}

SnapRec_LoadExclusions() {
    global g_SnapExclusionLV
    if !IsObject(g_SnapExclusionLV)
        return
    db := TrackDB()
    if !db
        return
    rows := db.Query("SELECT * FROM snap_exclusion WHERE active=1 ORDER BY id DESC")
    g_SnapExclusionLV.Opt("-Redraw")
    g_SnapExclusionLV.Delete()
    for r in rows {
        if r["kind"] = "signature"
            match := "image dHash " . r["signature"] . " (distance <= " . r["tolerance"] . ")"
        else
            match := 'title contains "' . r["title_pattern"] . '"  exe=' . r["exe"]
                   . "  class=" . r["class"]
        g_SnapExclusionLV.Add(, r["id"], r["kind"], match, r["created_ts"]
                            , r["match_count"], r["last_match_ts"])
    }
    g_SnapExclusionLV.Opt("+Redraw")
}

SnapRec_DisableExclusion() {
    global g_SnapExclusionLV
    row := g_SnapExclusionLV.GetNext()
    if !row {
        ShowStatus("Select an exclusion rule first", "wait")
        return
    }
    ruleId := Integer(g_SnapExclusionLV.GetText(row, 1))
    if MsgBox("Disable rule #" . ruleId . " and restore its hidden historical rows?"
            , "Disable snapshot exclusion", "YesNo Icon?") != "Yes"
        return
    TrackDB_DisableSnapshotExclusion(ruleId)
    SnapRec_LoadExclusions()
    SnapRec_Search()
    ShowStatus("Snapshot exclusion #" . ruleId . " disabled", "ok")
}

; Fill the history list either from the snapshot's phrase or from its clock.
SnapRec_HistoryMatch(byTime) {
    global g_SnapRecHistSearch
    rec := SnapRec_Selected()
    if !rec.Count {
        ShowStatus("Select a snapshot row first", "wait")
        return
    }
    ShowStatus("Reading Chrome history...", "wait")
    ; Match against history as it is now, not as of the last manual refresh.
    ChromeHist_SyncIfStale(60000)
    if byTime {
        ; A tab can sit open long after it was visited, so a tight window
        ; finds nothing for exactly the pages most worth recovering.
        rows := ChromeHist_Around(rec["ts"])
        label := "nearest visits to " . rec["ts"] . " (closest first)"
    } else {
        ; The first few words of the phrase are the most reliable needle; the
        ; tail of a title is what gets truncated on disk.
        phrase := rec["clue"]["query"]
        words := StrSplit(phrase, " ")
        needle := ""
        Loop Min(5, words.Length)
            needle .= (needle = "" ? "" : " ") . words[A_Index]
        rows := ChromeHist_Search(needle)
        label := 'title/url containing "' . needle . '"'
        try g_SnapRecHistSearch.Value := needle
    }
    SnapRec_FillHistory(rows, label)
}

SnapRec_FillHistory(rows, label := "") {
    global g_SnapRecHistLV, g_SnapRecStatus
    g_SnapRecHistLV.Opt("-Redraw")
    g_SnapRecHistLV.Delete()
    for , r in rows
        g_SnapRecHistLV.Add(, r["last_ts"], r.Has("delta") ? r["delta"] : ""
                          , r["title"], r["terms"], r["url"])
    g_SnapRecHistLV.Opt("+Redraw")
    g_SnapRecStatus.Value := "Chrome history: " . rows.Length . " row(s)"
        . (label != "" ? " - " . label : "")
    ShowStatus("Chrome history: " . rows.Length . " row(s)", rows.Length ? "ok" : "fail")
}

SnapRec_HistorySearchUI() {
    global g_SnapRecHistSearch
    query := Trim(g_SnapRecHistSearch.Value)
    ShowStatus("Searching the archived Chrome history...", "wait")
    ChromeHist_SyncIfStale(60000)
    rows := ChromeHist_Search(query, 1000)
    SnapRec_FillHistory(rows, query != "" ? 'title/url/search term containing "' . query . '"'
                                        : "latest visits")
}

; Manual full refresh (the Chrome History Explorer uses this). Routine
; freshness is handled automatically by ChromeHist_SyncIfStale.
ChromeHist_RefreshUI(*) {
    global g_ChromeHistRefreshBusy, g_SnapRecStatus, g_ChromeHistStatus
    if g_ChromeHistRefreshBusy {
        ShowStatus("Chrome history refresh is already running", "wait")
        return
    }
    g_ChromeHistRefreshBusy := true
    try g_SnapRecStatus.Value := "Refreshing every Chrome profile and appending new visits..."
    try g_ChromeHistStatus.Value := "Refreshing every Chrome profile and appending new visits..."
    ShowStatus("Refreshing Chrome history...", "wait")
    SetTimer(ChromeHist_RefreshTick, -30)
}

ChromeHist_RefreshTick() {
    global g_ChromeHistRefreshBusy, g_SnapRecStatus, g_ChromeHistStatus, g_ChromeHistLastSync
    try {
        stats := ChromeHist_RefreshArchive()
        g_ChromeHistLastSync := A_TickCount
        ChromeHist_ShowSyncState(stats)
        msg := "Chrome history refreshed: " . stats["profiles"] . " profile(s), "
             . stats["read"] . " source visit(s) read, " . stats["added"] . " new visit(s) appended."
        try g_SnapRecStatus.Value := msg
        try g_ChromeHistStatus.Value := msg
        try SnapRec_HistorySearchUI()
        if IsObject(g_ChromeHistGui)
            try ChromeHist_ExplorerSearch()
        ShowStatus(msg, "ok")
    } catch as err {
        TrackLogError("ChromeHist_RefreshTick", err)
        try g_SnapRecStatus.Value := "Chrome history refresh failed: " . err.Message
        try g_ChromeHistStatus.Value := "Refresh failed: " . err.Message
        ShowStatus("Chrome history refresh failed", "fail")
    }
    g_ChromeHistRefreshBusy := false
}

; A dedicated, resizable history window avoids forcing the Snapshot Recovery
; preview into a tiny table. Header clicks use the native ListView sorter.
ChromeHist_ShowExplorer(*) {
    global g_ChromeHistGui, g_ChromeHistLV, g_ChromeHistSearch, g_ChromeHistStatus
    if IsObject(g_ChromeHistGui) {
        try {
            g_ChromeHistGui.Show()
            g_ChromeHistSearch.Focus()
            return
        }
    }
    g_ChromeHistGui := Gui("+Resize +MinSize900x500", "Chrome History Explorer")
    g_ChromeHistGui.SetFont("s9", "Segoe UI")
    g_ChromeHistGui.Add("Text", "x10 y13", "Search:")
    g_ChromeHistSearch := g_ChromeHistGui.Add("Edit", "x65 y9 w500 h25")
    g_ChromeHistGui.Add("Button", "x573 y8 w90 h27 Default", "Search")
        .OnEvent("Click", (*) => ChromeHist_ExplorerSearch())
    g_ChromeHistGui.Add("Button", "x671 y8 w155 h27", "Refresh + Append New")
        .OnEvent("Click", (*) => ChromeHist_RefreshUI())
    g_ChromeHistGui.Add("Button", "x834 y8 w135 h27", "Show Latest 5,000")
        .OnEvent("Click", (*) => (g_ChromeHistSearch.Value := "", ChromeHist_ExplorerSearch()))
    g_ChromeHistLV := g_ChromeHistGui.Add("ListView", "x10 y44 w1160 h605 Grid"
        , ["Visited", "Profile", "Visits", "Title", "Search term typed", "URL"])
    g_ChromeHistLV.ModifyCol(1, 145)
    g_ChromeHistLV.ModifyCol(2, 90)
    g_ChromeHistLV.ModifyCol(3, "Integer 65")
    g_ChromeHistLV.ModifyCol(4, 315)
    g_ChromeHistLV.ModifyCol(5, 220)
    g_ChromeHistLV.ModifyCol(6, 520)
    g_ChromeHistLV.OnEvent("DoubleClick", (lv, row) => ChromeHist_ExplorerOpen(row))
    g_ChromeHistStatus := g_ChromeHistGui.Add("Text", "x10 y657 w1160 cGray", "Loading...")
    g_ChromeHistGui.OnEvent("Size", ChromeHist_ExplorerResize)
    g_ChromeHistGui.OnEvent("Close", (*) => (g_ChromeHistGui := ""))
    g_ChromeHistGui.Show("w1180 h690")
    SetTimer(ChromeHist_ExplorerSearch, -30)
}

ChromeHist_ExplorerResize(guiObj, minMax, width, height) {
    global g_ChromeHistLV, g_ChromeHistStatus
    if minMax = -1
        return
    try g_ChromeHistLV.Move(, , Max(700, width - 20), Max(360, height - 85))
    try g_ChromeHistStatus.Move(10, Max(455, height - 28), Max(700, width - 20))
}

ChromeHist_ExplorerSearch(*) {
    global g_ChromeHistLV, g_ChromeHistSearch, g_ChromeHistStatus
    if !IsObject(g_ChromeHistLV)
        return
    query := Trim(g_ChromeHistSearch.Value)
    g_ChromeHistStatus.Value := "Searching..."
    rows := ChromeHist_Search(query, 5000)
    g_ChromeHistLV.Opt("-Redraw")
    g_ChromeHistLV.Delete()
    for r in rows
        g_ChromeHistLV.Add(, r["last_ts"], r["profile"], r["visits"]
                         , r["title"], r["terms"], r["url"])
    g_ChromeHistLV.Opt("+Redraw")
    g_ChromeHistStatus.Value := rows.Length . " row(s). Click any column heading to sort; double-click to open."
}

ChromeHist_ExplorerOpen(row) {
    global g_ChromeHistLV
    if row {
        url := g_ChromeHistLV.GetText(row, 6)
        if url != ""
            Research_OpenUrl(url)
    }
}

SnapRec_BackfillUI() {
    ShowStatus("Backfilling search phrases from stored titles...", "wait")
    SnapRec_BackfillStart()
}

; ═══════════════════════════════════════════════════════════════════════════════
; OPENING HISTORY ROWS - preview, group, then launch
; ═══════════════════════════════════════════════════════════════════════════════

; The snapshot that shows what a history entry actually looked like.
;
; Two routes, strongest first. An exact match on the URL recorded at capture
; time is certain. Failing that, the window title is compared - a browser
; window is titled after its page, so "<page> - Google Chrome" and the history
; title agree on their leading text. Measured on this machine, the two together
; find a picture for roughly half of the rows in a typical result set.
SnapRec_SnapshotForHistory(url, title) {
    db := TrackDB()
    if !db
        return Map()
    if (url != "") {
        row := db.QueryRow("SELECT id,ts,title,image_path FROM snap_entry "
                         . "WHERE url=? AND image_path<>'' ORDER BY id DESC LIMIT 1", url)
        if row.Count {
            row["how"] := "recorded URL"
            return row
        }
    }
    key := SnapRec_TitleKey(title)
    if (StrLen(key) < 8)
        return Map()
    ; Compare on a normalised prefix so the "- Google Chrome" tail and any
    ; punctuation differences do not prevent a match.
    row := db.QueryRow("SELECT id,ts,title,image_path FROM snap_entry "
                     . "WHERE image_path<>'' AND title LIKE ? ORDER BY id DESC LIMIT 1"
                     , SubStr(title, 1, 30) . "%")
    if row.Count {
        row["how"] := "window title"
        return row
    }
    return Map()
}

SnapRec_TitleKey(s) {
    return StrLower(RegExReplace(s, "[^A-Za-z0-9]", ""))
}

; The site a URL belongs to - used to group rows before opening them.
SnapRec_HostOf(url) {
    if RegExMatch(url, "i)^https?://([^/:]+)", &m)
        return RegExReplace(m[1], "i)^www\.")
    return "other"
}

global g_OpenAllRows := [], g_OpenAllGui := "", g_OpenAllLV := ""
global g_OpenAllPic := "", g_OpenAllInfo := "", g_OpenAllStatus := ""

; Collect the listed history rows, collapse duplicate addresses, attach a
; snapshot to each, and show them for review before anything is launched.
SnapRec_OpenAllHistory() {
    global g_SnapRecHistLV, g_OpenAllRows
    rows := g_SnapRecHistLV.GetCount()
    if !rows {
        ShowStatus("No history rows listed - run a history match first", "wait")
        return
    }
    ShowStatus("Matching " . rows . " history row(s) to snapshots...", "wait")

    g_OpenAllRows := []
    seen := Map()
    Loop rows {
        i := A_Index
        u := Trim(g_SnapRecHistLV.GetText(i, 5))
        if (u = "" || !(u ~= "i)^https?://"))
            continue
        key := StrLower(u)
        if seen.Has(key)
            continue
        seen[key] := true
        title := g_SnapRecHistLV.GetText(i, 3)
        snap := SnapRec_SnapshotForHistory(u, title)
        g_OpenAllRows.Push(Map(
            "url", u,
            "title", title,
            "visited", g_SnapRecHistLV.GetText(i, 1),
            "host", SnapRec_HostOf(u),
            "shot", snap.Count && FileExist(snap["image_path"]) ? snap["image_path"] : "",
            "how", snap.Count ? snap["how"] : "",
            "pick", true))
    }
    if !g_OpenAllRows.Length {
        ShowStatus("No openable addresses in those rows", "fail")
        return
    }
    SnapRec_OpenAllPreview(rows)
}

SnapRec_OpenAllPreview(sourceRows) {
    global g_OpenAllGui, g_OpenAllLV, g_OpenAllPic, g_OpenAllInfo, g_OpenAllStatus, g_OpenAllRows
    if IsObject(g_OpenAllGui) {
        try g_OpenAllGui.Destroy()
        g_OpenAllGui := ""
    }
    g := Gui("+Resize", "Open history in Chrome - review first")
    g.SetFont("s9", "Segoe UI")
    g.MarginX := 10, g.MarginY := 10

    g.Add("Text", "x12 y12 w700 vOAHdr", "")
    g_OpenAllLV := g.Add("ListView", "x12 y34 w700 h420 Grid Checked vOALV"
        , ["Site", "Title", "Preview", "Visited", "URL"])
    g_OpenAllLV.ModifyCol(1, 130)
    g_OpenAllLV.ModifyCol(2, 240)
    g_OpenAllLV.ModifyCol(3, 90)
    g_OpenAllLV.ModifyCol(4, 120)
    g_OpenAllLV.ModifyCol(5, 300)
    g_OpenAllLV.Opt("+LV0x4000")
    g_OpenAllLV.OnEvent("ItemSelect", (lv, r, sel) => (sel ? SnapRec_OpenAllShow(r) : 0))

    g_OpenAllPic := g.Add("Picture", "x724 y34 w330 h230 Border vOAPic")
    g_OpenAllInfo := g.Add("Edit", "x724 y272 w330 h182 ReadOnly Multi VScroll vOAInfo")
    g_OpenAllInfo.SetFont("s8", "Consolas")

    g.Add("Button", "x12 y464 w90 h26 vOAAll", "Select all")
        .OnEvent("Click", (*) => SnapRec_OpenAllCheck(true))
    g.Add("Button", "x108 y464 w90 h26 vOANone", "Select none")
        .OnEvent("Click", (*) => SnapRec_OpenAllCheck(false))
    g.Add("Button", "x204 y464 w150 h26 vOAWithShot", "Only ones with a preview")
        .OnEvent("Click", (*) => SnapRec_OpenAllCheckShots())
    g.Add("Button", "x600 y464 w220 h26 Default vOAOpen", "Open ticked in ONE new window")
        .OnEvent("Click", (*) => SnapRec_OpenAllLaunch(false))
    g.Add("Button", "x826 y464 w228 h26 vOAGroup", "Open each site in its own window")
        .OnEvent("Click", (*) => SnapRec_OpenAllLaunch(true))

    g_OpenAllStatus := g.Add("Text", "x12 y498 w1042 cGray vOAStatus", "")
    g.OnEvent("Size", SnapRec_OpenAllResize)
    g.OnEvent("Close", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g_OpenAllGui := g
    SnapRec_OpenAllFill(sourceRows)
    g.Show("w1066 h526")
}

SnapRec_OpenAllResize(g, minMax, w, h) {
    if (minMax = -1)
        return
    try {
        rightW := 330
        lvW := Max(300, w - rightW - 34)
        lvH := Max(150, h - 106)
        g["OAHdr"].Move(12, 12, w - 24)
        g["OALV"].Move(12, 34, lvW, lvH)
        rx := 24 + lvW
        picH := Max(120, Integer(lvH * 0.55))
        g["OAPic"].Move(rx, 34, rightW, picH)
        g["OAInfo"].Move(rx, 42 + picH, rightW, lvH - picH - 8)
        by := 40 + lvH
        g["OAAll"].Move(12, by, 90, 26)
        g["OANone"].Move(108, by, 90, 26)
        g["OAWithShot"].Move(204, by, 150, 26)
        g["OAOpen"].Move(w - 462, by, 220, 26)
        g["OAGroup"].Move(w - 236, by, 228, 26)
        g["OAStatus"].Move(12, by + 34, w - 24)
    }
}

SnapRec_OpenAllFill(sourceRows) {
    global g_OpenAllRows, g_OpenAllLV, g_OpenAllGui, g_OpenAllStatus
    ; Group by site so related pages sit together and can be opened as a set.
    SnapRec_SortRowsByHost(g_OpenAllRows)
    g_OpenAllLV.Opt("-Redraw")
    g_OpenAllLV.Delete()
    withShot := 0
    hosts := Map()
    for i, r in g_OpenAllRows {
        g_OpenAllLV.Add("Check", r["host"], r["title"]
                      , (r["shot"] != "" ? "yes (" . r["how"] . ")" : "-")
                      , r["visited"], r["url"])
        if (r["shot"] != "")
            withShot++
        hosts[r["host"]] := true
    }
    g_OpenAllLV.Opt("+Redraw")
    dupes := sourceRows - g_OpenAllRows.Length
    try g_OpenAllGui["OAHdr"].Value := g_OpenAllRows.Length . " unique page(s) from "
        . sourceRows . " history row(s)"
        . (dupes > 0 ? "  -  " . dupes . " duplicate address(es) collapsed" : "")
        . "  -  " . hosts.Count . " site(s)  -  " . withShot . " with a snapshot preview"
    try g_OpenAllStatus.Value := "Untick anything you do not want. Nothing opens until "
        . "you press one of the Open buttons."
    if g_OpenAllRows.Length
        g_OpenAllLV.Modify(1, "Select Focus")
}

; Group rows by host, keeping the biggest groups first.
SnapRec_SortRowsByHost(rows) {
    counts := Map()
    for , r in rows
        counts[r["host"]] := (counts.Has(r["host"]) ? counts[r["host"]] : 0) + 1
    n := rows.Length
    i := 2
    while (i <= n) {
        cur := rows[i]
        j := i - 1
        while (j >= 1) {
            a := rows[j], b := cur
            ca := counts[a["host"]], cb := counts[b["host"]]
            swap := (ca < cb) || (ca = cb && StrCompare(a["host"], b["host"]) > 0)
            if !swap
                break
            rows[j + 1] := rows[j]
            j--
        }
        rows[j + 1] := cur
        i++
    }
}

SnapRec_OpenAllShow(row) {
    global g_OpenAllRows, g_OpenAllPic, g_OpenAllInfo
    if (row < 1 || row > g_OpenAllRows.Length)
        return
    r := g_OpenAllRows[row]
    try g_OpenAllPic.Value := (r["shot"] != "" ? r["shot"] : "")
    t := r["title"] . "`r`n`r`n"
    t .= "site     " . r["host"] . "`r`n"
    t .= "visited  " . r["visited"] . "`r`n"
    t .= "url      " . r["url"] . "`r`n`r`n"
    t .= (r["shot"] != ""
        ? "PREVIEW matched by " . r["how"] . "`r`n" . r["shot"]
        : "No snapshot found for this page. It was either never captured, or "
        . "captured before URL recording existed and its title does not match.")
    g_OpenAllInfo.Value := t
}

SnapRec_OpenAllCheck(state) {
    global g_OpenAllLV
    Loop g_OpenAllLV.GetCount()
        g_OpenAllLV.Modify(A_Index, state ? "Check" : "-Check")
}

SnapRec_OpenAllCheckShots() {
    global g_OpenAllLV, g_OpenAllRows
    Loop g_OpenAllLV.GetCount() {
        i := A_Index
        g_OpenAllLV.Modify(i, (g_OpenAllRows[i]["shot"] != "") ? "Check" : "-Check")
    }
}

; Launch the ticked rows.
;
; The first page of a window is opened with --new-window and the rest with
; --new-tab, so everything lands in ONE fresh window rather than being scattered
; through whatever browsing is already open. With byGroup set, each site gets
; its own window, which is as close to a tab group as the command line allows -
; Chrome exposes no way to create a named tab group externally.
SnapRec_OpenAllLaunch(byGroup) {
    global g_OpenAllLV, g_OpenAllRows, g_OpenAllStatus, g_OpenAllGui
    picked := []
    Loop g_OpenAllLV.GetCount() {
        i := A_Index
        if g_OpenAllLV.GetNext(i - 1, "Checked") = i
            picked.Push(g_OpenAllRows[i])
    }
    if !picked.Length {
        try g_OpenAllStatus.Value := "Nothing ticked."
        return
    }
    if (picked.Length > 60) {
        picked.Length := 60
        try g_OpenAllStatus.Value := "Limited to the first 60."
    }

    windows := 0, opened := 0
    if byGroup {
        seenHost := Map()
        for , r in picked {
            fresh := !seenHost.Has(r["host"])
            seenHost[r["host"]] := true
            if SnapRec_LaunchOne(r["url"], fresh)
                opened++
            if fresh
                windows++
            Sleep(fresh ? 500 : 130)      ; a new window needs longer to settle
        }
    } else {
        first := true
        for , r in picked {
            if SnapRec_LaunchOne(r["url"], first)
                opened++
            if first
                windows++, first := false
            Sleep(first ? 500 : 130)
        }
    }

    msg := "Opened " . opened . " page(s) in " . windows . " new window(s)"
        . (byGroup ? ", one per site." : ".")
    try g_OpenAllStatus.Value := msg
    ShowStatus(msg, "ok")
    if IsObject(g_OpenAllGui)
        try g_OpenAllGui.Destroy()
}

SnapRec_LaunchOne(url, newWindow) {
    try {
        Run('chrome.exe ' . (newWindow ? '--new-window' : '--new-tab') . ' "' . url . '"')
        return true
    } catch {
        try {
            Run(url)          ; fall back to whatever handles http
            return true
        }
    }
    return false
}

SnapRec_OpenHistoryRow(row) {
    global g_SnapRecHistLV
    if !row
        return
    url := g_SnapRecHistLV.GetText(row, 5)
    if (url != "")
        Research_OpenUrl(url)
}
