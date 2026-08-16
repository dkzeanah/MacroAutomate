; ═══════════════════════════════════════════════════════════════════════════════
; ResearchPipeline.ahk - Query -> links -> per-link insight workflow
; ═══════════════════════════════════════════════════════════════════════════════
; Implements the databased research loop from the brief:
;
;   "go to chrome, open new tab, search google, take the results page and all
;    entries on it, save those as batch links corresponding to the query, then
;    launch them all, gain one insight from each page, and add it as an entry
;    associated to the original query."
;
; The engine plumbs the data and drives the browser; each step is a workflow
; action so it can be sequenced with everything else the automator does:
;
;   Research_Search           store the query + open Google for it in the browser
;   Research_CaptureLinks*     harvest result URLs (from screen OCR or clipboard)
;   Research_LaunchNext        open the next pending link in the browser
;   Research_AddInsight        attach a takeaway to the current query/link
;   Research_Report            assemble every insight for a query
;
; A small "current context" (query id + link id) lets a multi-step workflow keep
; its place across steps without passing ids around by hand.
; ═══════════════════════════════════════════════════════════════════════════════

global g_ResQueryId := 0        ; Current query in focus
global g_ResLinkId := 0         ; Link currently being read
global g_ResBrowser := "chrome" ; chrome | msedge | firefox | default

; ═══════════════════════════════════════════════════════════════════════════════
; QUERY
; ═══════════════════════════════════════════════════════════════════════════════

; Store a query and open a Google search for it in the browser.
; Returns the query id (0 on failure). Sets it as the current context.
Research_Search(text, engine := "google") {
    global g_ResQueryId, g_ResLinkId

    text := Trim(text)
    if (text = "")
        return 0
    if !TrackDB_Ready() {
        if !TrackDB_Init()
            return 0
    }

    qid := TrackDB_AddQuery(text, engine)
    g_ResQueryId := qid
    g_ResLinkId := 0

    Research_OpenSearchUrl(text, engine)
    ShowStatus("Query #" . qid . " searched: " . TrackEllipsis(text, 40), "ok")
    return qid
}

; Open a search results page for `text` in a new browser tab.
Research_OpenSearchUrl(text, engine := "google") {
    url := Research_SearchUrl(text, engine)
    Research_OpenUrl(url)
}

Research_SearchUrl(text, engine := "google") {
    q := Research_UrlEncode(text)
    switch StrLower(engine) {
        case "bing":       return "https://www.bing.com/search?q=" . q
        case "duckduckgo": return "https://duckduckgo.com/?q=" . q
        default:           return "https://www.google.com/search?q=" . q
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; LINK HARVESTING
; ═══════════════════════════════════════════════════════════════════════════════

; Extract URLs from an arbitrary block of text and store them against a query.
; Returns the number of new links added.
Research_AddLinksFromText(queryId, text) {
    if !queryId || text = ""
        return 0
    urls := Research_ExtractUrls(text)
    added := 0
    rank := Research_LinkCount(queryId)
    for u in urls {
        rank++
        if TrackDB_AddQueryLink(queryId, rank, u, "")
            added++
    }
    return added
}

; OCR the active window (a results page) and harvest any URLs it shows.
; Falls back gracefully when OCR is unavailable.
Research_CaptureLinksFromScreen(queryId) {
    if !queryId
        return 0
    text := ""
    try {
        res := OCR.FromWindow("A")
        text := res.Text
    } catch as err {
        try {
            res := OCR.FromDesktop()
            text := res.Text
        } catch as err2 {
            TrackLogError("Research_CaptureLinksFromScreen", err2)
            return 0
        }
    }
    return Research_AddLinksFromText(queryId, text)
}

; Harvest URLs sitting on the clipboard (e.g. after Ctrl+A, Ctrl+C on results).
Research_CaptureLinksFromClipboard(queryId) {
    if !queryId
        return 0
    content := ""
    try content := A_Clipboard
    return Research_AddLinksFromText(queryId, content)
}

; ═══════════════════════════════════════════════════════════════════════════════
; LINK NAVIGATION
; ═══════════════════════════════════════════════════════════════════════════════

; Open the next pending link for a query in the browser and mark it visiting.
; Returns the link id, or 0 when none remain. Sets it as the current link.
Research_LaunchNext(queryId := 0) {
    global g_ResQueryId, g_ResLinkId
    if !queryId
        queryId := g_ResQueryId
    if !queryId
        return 0

    link := TrackDB_NextPendingLink(queryId)
    if !link.Count {
        ShowStatus("No pending links for query #" . queryId, "wait")
        return 0
    }

    db := TrackDB()
    db.Run("UPDATE query_link SET status='visiting', visited_ts=? WHERE id=?"
         , TrackTS(), link["id"])
    g_ResLinkId := link["id"]

    Research_OpenUrl(link["url"])
    ShowStatus("Opened link #" . link["rank"] . ": " . TrackEllipsis(link["url"], 50), "ok")
    return link["id"]
}

; ═══════════════════════════════════════════════════════════════════════════════
; INSIGHTS
; ═══════════════════════════════════════════════════════════════════════════════

; Attach an insight (key takeaway) to a query/link. Uses the current context
; when ids are not supplied. Returns the insight id.
Research_AddInsight(insight, queryId := 0, linkId := 0, source := "") {
    global g_ResQueryId, g_ResLinkId
    if !queryId
        queryId := g_ResQueryId
    if !linkId
        linkId := g_ResLinkId
    if !queryId || insight = ""
        return 0

    id := TrackDB_AddInsight(queryId, linkId, insight, source)
    ShowStatus("Insight added to query #" . queryId, "ok")
    return id
}

; Mark a query complete.
Research_CloseQuery(queryId := 0) {
    global g_ResQueryId
    if !queryId
        queryId := g_ResQueryId
    if !queryId
        return false
    db := TrackDB()
    db.Run("UPDATE query SET status='done' WHERE id=?", queryId)
    return true
}

; ═══════════════════════════════════════════════════════════════════════════════
; REPORTING
; ═══════════════════════════════════════════════════════════════════════════════

; Every insight gathered for a query, as a readable report string.
Research_Report(queryId) {
    db := TrackDB()
    if !db || !queryId
        return ""
    q := db.QueryRow("SELECT * FROM query WHERE id=?", queryId)
    if !q.Count
        return ""

    out := "QUERY #" . queryId . ": " . q["text"] . "`n"
    out .= "Created: " . q["created_ts"] . "  |  Status: " . q["status"] . "`n"
    out .= "═══════════════════════════════════════════════════════════════`n`n"

    insights := db.Query("SELECT i.*, l.url AS url, l.title AS link_title "
                       . "FROM query_insight i LEFT JOIN query_link l ON l.id=i.link_id "
                       . "WHERE i.query_id=? ORDER BY i.id", queryId)
    if !insights.Length {
        out .= "(no insights yet)`n"
        return out
    }
    for i, ins in insights {
        out .= i . ". " . ins["insight"] . "`n"
        if (ins["url"] != "")
            out .= "   source: " . ins["url"] . "`n"
        out .= "`n"
    }
    return out
}

Research_ExportReport(queryId, path) {
    Track_WriteFile(path, Research_Report(queryId))
    return path
}

; Full pipeline export (query + links + insights) as JSON.
Research_ExportJson(queryId, path) {
    db := TrackDB()
    if !db || !queryId
        return ""
    q := db.QueryRow("SELECT * FROM query WHERE id=?", queryId)
    if !q.Count
        return ""

    links := db.Query("SELECT * FROM query_link WHERE query_id=? ORDER BY rank", queryId)
    insights := db.Query("SELECT * FROM query_insight WHERE query_id=? ORDER BY id", queryId)

    linkArr := []
    for l in links
        linkArr.Push(Map("rank", l["rank"], "url", l["url"], "title", l["title"], "status", l["status"]))
    insArr := []
    for ins in insights
        insArr.Push(Map("link_id", ins["link_id"], "insight", ins["insight"], "source", ins["source"]))

    doc := Map("kind", "macroautomate.research", "version", 1
             , "query", q["text"], "created", q["created_ts"]
             , "links", linkArr, "insights", insArr)
    Track_WriteFile(path, TrackJsonEncode(doc, 2))
    return path
}

; ═══════════════════════════════════════════════════════════════════════════════
; QUERIES (list helpers for the UI)
; ═══════════════════════════════════════════════════════════════════════════════

Research_RecentQueries(limit := 100) {
    db := TrackDB()
    if !db
        return []
    return db.Query("SELECT q.*, "
                  . "(SELECT COUNT(*) FROM query_link l WHERE l.query_id=q.id) AS links, "
                  . "(SELECT COUNT(*) FROM query_insight i WHERE i.query_id=q.id) AS insights "
                  . "FROM query q ORDER BY q.id DESC LIMIT ?", limit)
}

Research_LinkCount(queryId) {
    db := TrackDB()
    if !db
        return 0
    v := db.Scalar("SELECT COUNT(*) FROM query_link WHERE query_id=?", queryId)
    return IsInteger(v) ? Integer(v) : 0
}

Research_Links(queryId) {
    db := TrackDB()
    if !db
        return []
    return db.Query("SELECT * FROM query_link WHERE query_id=? ORDER BY rank", queryId)
}

Research_Insights(queryId) {
    db := TrackDB()
    if !db
        return []
    return db.Query("SELECT i.*, l.url AS url FROM query_insight i "
                  . "LEFT JOIN query_link l ON l.id=i.link_id WHERE i.query_id=? ORDER BY i.id", queryId)
}

; ═══════════════════════════════════════════════════════════════════════════════
; BROWSER + URL HELPERS
; ═══════════════════════════════════════════════════════════════════════════════

; Open a URL. Prefers the configured browser; falls back to the shell default.
Research_OpenUrl(url) {
    global g_ResBrowser
    if (url = "")
        return false
    exe := ""
    switch StrLower(g_ResBrowser) {
        case "chrome":  exe := "chrome.exe"
        case "msedge", "edge": exe := "msedge.exe"
        case "firefox": exe := "firefox.exe"
    }
    if (exe != "") {
        try {
            Run(exe . " --new-tab " . '"' . url . '"')
            return true
        } catch {
            ; fall through to default handler
        }
    }
    try Run(url)
    catch as err {
        TrackLogError("Research_OpenUrl", err)
        return false
    }
    return true
}

; RFC-3986-ish query encoding for search strings.
Research_UrlEncode(text) {
    out := ""
    for c in StrSplit(text) {
        if (c ~= "[A-Za-z0-9\-_.~]")
            out .= c
        else if (c = " ")
            out .= "+"
        else {
            ; Encode each UTF-8 byte of the character.
            buf := Buffer(StrPut(c, "UTF-8"))
            n := StrPut(c, buf, "UTF-8") - 1
            Loop n
                out .= Format("%{:02X}", NumGet(buf, A_Index - 1, "UChar"))
        }
    }
    return out
}

; Pull http(s) URLs out of free text.
Research_ExtractUrls(text) {
    urls := []
    seen := Map()
    pos := 1
    while (pos := RegExMatch(text, "https?://[^\s""'<>()\]}]+", &m, pos)) {
        u := m[0]
        ; Trim trailing punctuation that commonly clings to URLs in prose.
        u := RegExReplace(u, "[.,;:!?]+$")
        pos += StrLen(m[0])
        if (StrLen(u) < 12)
            continue
        ; Skip Google's own chrome (result pages link back to google infra).
        if (u ~= "i)google\.com/(search|imgres|url\?)")
            continue
        if !seen.Has(u) {
            seen[u] := true
            urls.Push(u)
        }
    }
    return urls
}
