; ═══════════════════════════════════════════════════════════════════════════════
; KnowledgeDash.ahk - Live "accumulated knowledge" dashboard + on-screen playback
; ═══════════════════════════════════════════════════════════════════════════════
; One place to watch everything the system has learned, in real time, and to
; "play back" a piece of it by flashing its bounds on screen for validation:
;
;   * window/element discoveries & mapping  (ui_element, discovered_target,
;     appmap_app, window_fact, taskbar_knowledge)
;   * written/versioned tools DAA uses       (app_file *.ahk, revisions)
;   * the DAA planner's chains                (daa_chain, daa_step)
;   * the pre-knowledge / learning layer      (learning_claim/evidence,
;     automation_learning)
;   * usage patterns, study Q&A, media jobs, and env feature maps
;
; Everything is read from the one unified database (TrackDB()); categories that
; do not exist in a given build are skipped. Spatial rows can be flashed on
; screen (playback). Env feature maps produced by EnvIntel.ahk are persisted
; here so they accumulate and are reviewable.
; ═══════════════════════════════════════════════════════════════════════════════

global g_KnowSchemaReady := false

; ─────────────────────────────────────────────────────────────────────────────
; SCHEMA (only the env-map tables are owned here; the rest are read-only)
; ─────────────────────────────────────────────────────────────────────────────
Know_Schema() {
    global g_KnowSchemaReady
    if g_KnowSchemaReady
        return true
    db := TrackDB()
    if !db
        return false
    try {
        db.Exec("CREATE TABLE IF NOT EXISTS env_map ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT, created_ts TEXT, kind TEXT,"
              . "title TEXT, region_count INTEGER DEFAULT 0, control_count INTEGER DEFAULT 0,"
              . "x INTEGER DEFAULT 0, y INTEGER DEFAULT 0, w INTEGER DEFAULT 0, h INTEGER DEFAULT 0)")
        db.Exec("CREATE TABLE IF NOT EXISTS env_region ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT, map_id INTEGER, idx INTEGER,"
              . "role TEXT, text TEXT, x INTEGER, y INTEGER, w INTEGER, h INTEGER)")
        db.Exec("CREATE INDEX IF NOT EXISTS ix_envregion_map ON env_region(map_id)")
        db.Exec("CREATE TABLE IF NOT EXISTS know_validation ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT, kind TEXT,"
              . "total INTEGER, passed INTEGER, score INTEGER)")
    } catch as err {
        TrackLogError("Know_Schema", err)
        return false
    }
    g_KnowSchemaReady := true
    return true
}

; Persist an EnvIntel feature map so it accumulates in the dashboard.
Know_PersistEnvMap(fm) {
    if (!IsObject(fm) || !fm.Has("ok") || !fm["ok"] || !Know_Schema())
        return 0
    db := TrackDB()
    title := fm.Has("kind") ? fm["kind"] : "map"
    if (fm.Has("hwnd") && fm["hwnd"]) {
        try title := WinGetTitle("ahk_id " . fm["hwnd"])
    }
    db.Run("INSERT INTO env_map(created_ts,kind,title,region_count,control_count,x,y,w,h) "
         . "VALUES(?,?,?,?,?,?,?,?,?)"
         , FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"), fm["kind"], SubStr(title, 1, 120)
         , fm["regionCount"], fm["controlCount"]
         , fm.Has("x") ? fm["x"] : 0, fm.Has("y") ? fm["y"] : 0
         , fm.Has("w") ? fm["w"] : 0, fm.Has("h") ? fm["h"] : 0)
    mapId := db.LastInsertId()
    db.Begin()
    try {
        for , r in fm["regions"]
            db.Run("INSERT INTO env_region(map_id,idx,role,text,x,y,w,h) VALUES(?,?,?,?,?,?,?,?)"
                 , mapId, r["id"], r["role"], SubStr(r["text"], 1, 400)
                 , r["x"], r["y"], r["w"], r["h"])
        db.Commit()
    } catch as err {
        db.Rollback()
        TrackLogError("Know_PersistEnvMap", err)
    }
    return mapId
}

; ─────────────────────────────────────────────────────────────────────────────
; CATALOG - the knowledge categories, grouped. Rows absent from a build are
; skipped at count time (TableExists guard).
; ─────────────────────────────────────────────────────────────────────────────
Know_Catalog() {
    return [
      Map("key","ui_element",        "label","UI elements mapped",   "table","ui_element",         "group","Window & element discovery", "spatial",true),
      Map("key","discovered_target", "label","Discovered targets",   "table","discovered_target",  "ts","last_ts",   "group","Window & element discovery", "spatial",true),
      Map("key","appmap_app",        "label","Learned apps",         "table","appmap_app",         "ts","learned_ts","group","Window & element discovery", "spatial",true),
      Map("key","window_fact",       "label","Window facts",         "table","window_fact",        "ts","last_at",   "group","Window & element discovery"),
      Map("key","taskbar_knowledge", "label","Taskbar items",        "table","taskbar_knowledge",  "ts","last_ts",   "group","Window & element discovery", "spatial",true),
      Map("key","app_file_ahk",      "label","Written AHK tools",    "table","app_file", "where","path LIKE '%.ahk'", "ts","modified_ts", "group","Written tools"),
      Map("key","revisions",         "label","Tool revisions",       "table","revisions",          "ts","at",        "group","Written tools"),
      Map("key","daa_chain",         "label","DAA chains",           "table","daa_chain",          "ts","created_at","group","DAA planner"),
      Map("key","daa_step",          "label","DAA steps",            "table","daa_step",           "ts","started_at","group","DAA planner"),
      Map("key","learning_claim",    "label","Learning claims",      "table","learning_claim",     "ts","created_ts","group","Pre-knowledge / learning"),
      Map("key","learning_evidence", "label","Learning evidence",    "table","learning_evidence",  "group","Pre-knowledge / learning"),
      Map("key","automation_learning","label","Automation learnings","table","automation_learning","group","Pre-knowledge / learning"),
      Map("key","usage_element",     "label","Usage elements",       "table","usage_element",      "group","Usage patterns"),
      Map("key","usage_transition",  "label","Usage transitions",    "table","usage_transition",   "group","Usage patterns"),
      Map("key","patterns",          "label","Visual patterns",      "table","patterns",           "group","Patterns & media"),
      Map("key","qa_item",           "label","Study Q&A",            "table","qa_item",            "group","Patterns & media"),
      Map("key","media_job",         "label","Media jobs",           "table","media_job",          "group","Patterns & media"),
      Map("key","env_map",           "label","Env feature maps",     "table","env_map", "ts","created_ts", "group","Patterns & media", "spatial",true) ]
}

; Live metrics: [{key,label,group,count,last,spatial}] for existing tables.
Know_Metrics() {
    out := []
    db := TrackDB()
    if !db
        return out
    for , c in Know_Catalog() {
        if !db.TableExists(c["table"])
            continue
        where := c.Has("where") ? (" WHERE " . c["where"]) : ""
        cnt := 0
        try cnt := db.Scalar("SELECT COUNT(*) FROM " . c["table"] . where)
        last := ""
        if c.Has("ts") {
            try last := db.Scalar("SELECT MAX(" . c["ts"] . ") FROM " . c["table"] . where)
        }
        detail := ""
        if (c["key"] = "qa_item") {
            ans := 0
            try ans := db.Scalar("SELECT COUNT(*) FROM qa_item WHERE answer IS NOT NULL AND answer<>''")
            detail := ans . " answered"
        }
        out.Push(Map("key",c["key"], "label",c["label"], "group",c["group"]
                   , "count", IsInteger(cnt) ? cnt : 0, "last", last
                   , "detail", detail, "spatial", c.Has("spatial") && c["spatial"]))
    }
    return out
}

Know_TotalLearned() {
    n := 0
    for , m in Know_Metrics()
        n += m["count"]
    return n
}

; ─────────────────────────────────────────────────────────────────────────────
; DRILL-DOWN - recent rows for one category, projected to
; {label, detail, when, bounds([x,y,w,h] or ""), content}
; ─────────────────────────────────────────────────────────────────────────────
Know_CategoryRows(key, limit := 300) {
    db := TrackDB()
    out := []
    if !db
        return out
    q := (sql, params*) => Know_SafeQuery(db, sql, params*)
    switch key {
        case "ui_element":
            for r in q("SELECT id,name,role,kind,source_title,x,y,w,h FROM ui_element "
                     . "ORDER BY id DESC LIMIT " . limit)
                out.Push(Know_Row(Know_Join2(r["name"], r["role"]), Know_Join2(r["kind"], r["source_title"])
                       , "", [r["x"],r["y"],r["w"],r["h"]], ""))
        case "discovered_target":
            for r in q("SELECT title,name,role,x,y,w,h,seen_count,last_ts FROM discovered_target "
                     . "ORDER BY last_ts DESC LIMIT " . limit)
                out.Push(Know_Row(Know_Join2(r["name"], r["title"]), r["role"] . "  seen " . r["seen_count"]
                       , r["last_ts"], [r["x"],r["y"],r["w"],r["h"]], ""))
        case "appmap_app":
            for r in q("SELECT name,exe,win_x,win_y,win_w,win_h,learned_ts FROM appmap_app "
                     . "ORDER BY id DESC LIMIT " . limit)
                out.Push(Know_Row(r["name"], r["exe"], r["learned_ts"]
                       , [r["win_x"],r["win_y"],r["win_w"],r["win_h"]], ""))
        case "taskbar_knowledge":
            for r in q("SELECT label,exe,bounds,seen_count,last_ts FROM taskbar_knowledge "
                     . "ORDER BY last_ts DESC LIMIT " . limit)
                out.Push(Know_Row(r["label"], r["exe"] . "  seen " . r["seen_count"], r["last_ts"]
                       , Know_ParseBounds(r["bounds"]), ""))
        case "window_fact":
            for r in q("SELECT label,kind,zone,observations,last_at FROM window_fact "
                     . "ORDER BY last_at DESC LIMIT " . limit)
                out.Push(Know_Row(r["label"], Know_Join2(r["kind"], r["zone"]) . "  obs " . r["observations"]
                       , r["last_at"], "", ""))
        case "app_file_ahk":
            for r in q("SELECT path,modified_ts,length(content) AS sz,content FROM app_file "
                     . "WHERE path LIKE '%.ahk' ORDER BY modified_ts DESC LIMIT " . limit)
                out.Push(Know_Row(r["path"], r["sz"] . " bytes", r["modified_ts"], "", r["content"]))
        case "revisions":
            for r in q("SELECT name,revision,at,length(content) AS sz,content FROM revisions "
                     . "ORDER BY at DESC LIMIT " . limit)
                out.Push(Know_Row(r["name"] . "  r" . r["revision"], r["sz"] . " bytes", r["at"], "", r["content"]))
        case "daa_chain":
            for r in q("SELECT task_id,created_at,step_count,status FROM daa_chain "
                     . "ORDER BY created_at DESC LIMIT " . limit)
                out.Push(Know_Row(r["task_id"], r["step_count"] . " steps  " . r["status"], r["created_at"], "", ""))
        case "daa_step":
            for r in q("SELECT number,tool,status,arguments,result,started_at FROM daa_step "
                     . "ORDER BY id DESC LIMIT " . limit)
                out.Push(Know_Row("#" . r["number"] . "  " . r["tool"], r["status"], r["started_at"], ""
                       , "ARGS: " . r["arguments"] . "`r`n`r`nRESULT: " . r["result"]))
        case "learning_claim":
            for r in q("SELECT claim,use_text,source,created_ts FROM learning_claim "
                     . "ORDER BY id DESC LIMIT " . limit)
                out.Push(Know_Row(Know_Clip(r["claim"], 90), r["source"], r["created_ts"], "", r["use_text"]))
        case "qa_item":
            for r in q("SELECT question,answer,state,created_ts FROM qa_item "
                     . "ORDER BY id DESC LIMIT " . limit)
                out.Push(Know_Row(Know_Clip(r["question"], 90), r["state"], r["created_ts"], ""
                       , "Q: " . r["question"] . "`r`n`r`nA: " . r["answer"]))
        case "media_job":
            for r in q("SELECT id,title,frame_count,status,summary,created_ts FROM media_job "
                     . "ORDER BY id DESC LIMIT " . limit)
                out.Push(Know_Row(r["title"], r["frame_count"] . " frames  " . r["status"], r["created_ts"], ""
                       , r["summary"]))
        case "env_map":
            for r in q("SELECT id,title,kind,region_count,x,y,w,h,created_ts FROM env_map "
                     . "ORDER BY id DESC LIMIT " . limit)
                out.Push(Know_Row(r["title"], r["kind"] . "  " . r["region_count"] . " regions"
                       , r["created_ts"], [r["x"],r["y"],r["w"],r["h"]], "env_map_id:" . r["id"]))
        default:
            ; generic: show first text-ish columns
            for r in q("SELECT * FROM " . Know_SafeTable(key) . " LIMIT " . Min(limit, 200)) {
                label := "", detail := ""
                for k, v in r {
                    if (label = "")
                        label := k . "=" . Know_Clip("" . v, 60)
                    else if (detail = "") {
                        detail := k . "=" . Know_Clip("" . v, 60)
                        break
                    }
                }
                out.Push(Know_Row(label, detail, "", "", ""))
            }
    }
    return out
}

Know_Row(label, detail, when, bounds, content) {
    return Map("label", "" . label, "detail", "" . detail, "when", "" . when
             , "bounds", bounds, "content", "" . content)
}

Know_SafeQuery(db, sql, params*) {
    try return db.Query(sql, params*)
    catch as err {
        TrackLogError("Know_SafeQuery", err)
        return []
    }
}

; Only allow a catalog table name through the generic path (no injection).
Know_SafeTable(key) {
    for , c in Know_Catalog()
        if (c["key"] = key)
            return c["table"]
    return "sqlite_master"
}

Know_ParseBounds(s) {
    ; accept "x,y,w,h", "x y w h", or JSON-ish with 4 ints
    nums := []
    pos := 1
    while (pos := RegExMatch(s, "-?\d+", &m, pos)) {
        nums.Push(Integer(m[0]))
        pos += StrLen(m[0])
        if (nums.Length >= 4)
            break
    }
    return nums.Length >= 4 ? [nums[1], nums[2], nums[3], nums[4]] : ""
}

Know_Join2(a, b) {
    a := Trim("" . a), b := Trim("" . b)
    if (a = "")
        return b
    if (b = "")
        return a
    return a . "  -  " . b
}

Know_Clip(s, n) {
    s := StrReplace(StrReplace("" . s, "`r", " "), "`n", " ")
    return StrLen(s) > n ? SubStr(s, 1, n - 1) . "..." : s
}

; ─────────────────────────────────────────────────────────────────────────────
; PLAYBACK - flash a remembered rectangle on screen (retained candidate).
; ─────────────────────────────────────────────────────────────────────────────
Know_Flash(bounds) {
    if (!IsObject(bounds) || bounds.Length < 4)
        return false
    x := Integer(bounds[1]), y := Integer(bounds[2])
    w := Integer(bounds[3]), h := Integer(bounds[4])
    if (w <= 0 || h <= 0)
        return false
    try FlashHighlight(x, y, w, h, 3, 220, "match")
    return true
}

; ─────────────────────────────────────────────────────────────────────────────
; EXPORT - a "big picture" snapshot for certification / sharing.
; ─────────────────────────────────────────────────────────────────────────────
Know_ExportSnapshot(path := "") {
    global DATA_DIR
    metrics := Know_Metrics()
    doc := Map("captured_ts", FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
             , "total_items", Know_TotalLearned(), "categories", [])
    for , m in metrics
        doc["categories"].Push(Map("group", m["group"], "label", m["label"]
                              , "count", m["count"], "last", m["last"]))
    if (path = "")
        path := DATA_DIR . "\knowledge_snapshot_" . FormatTime(A_Now, "yyyyMMdd_HHmmss") . ".json"
    Track_WriteFile(path, TrackJsonEncode(doc, 2))
    return path
}

; ─────────────────────────────────────────────────────────────────────────────
; "BIG PICTURE" UTILITY (not counts): random samples, live validation, insights
; ─────────────────────────────────────────────────────────────────────────────

; A randomized, interleaved sample of ACTUAL records across the useful
; categories, so you can see what is captured and judge its quality - not counts.
Know_SampleRecords(n := 36) {
    cats := ["qa_item", "discovered_target", "ui_element", "app_file_ahk"
           , "learning_claim", "usage_transition", "daa_step", "env_map"]
    pool := []
    per := Max(4, (n // cats.Length) + 3)
    for , k in cats {
        for , r in Know_CategoryRows(k, per) {
            r["label"] := "[" . k . "] " . r["label"]
            pool.Push(r)
        }
    }
    Know_Shuffle(pool)
    out := []
    Loop Min(n, pool.Length)
        out.Push(pool[A_Index])
    return out
}

Know_Shuffle(arr) {
    i := arr.Length
    while (i > 1) {
        j := Random(1, i)
        tmp := arr[i], arr[i] := arr[j], arr[j] := tmp
        i--
    }
}

; Bulk live validation: sample remembered spatial items and check whether their
; source window still exists and their bounds are on a real screen. Produces a
; pass/fail per item and an overall score (how much mapped knowledge is still
; valid), logged to know_validation for ranking over time.
Know_BulkValidate(n := 40) {
    out := Map("total", 0, "passed", 0, "score", 0, "rows", [])
    db := TrackDB()
    if !db
        return out
    rows := []
    try rows := db.Query("SELECT title AS wtitle, name, x, y, w, h FROM discovered_target "
                       . "WHERE title IS NOT NULL AND title<>'' ORDER BY RANDOM() LIMIT ?", n)
    if db.TableExists("ui_element") {
        uir := []
        try uir := db.Query("SELECT source_title AS wtitle, name, x, y, w, h FROM ui_element "
                          . "WHERE source_title IS NOT NULL AND source_title<>'' ORDER BY RANDOM() LIMIT ?", n)
        for , r in uir
            rows.Push(r)
    }
    ; virtual-desktop bounds
    vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
    total := 0, passed := 0, results := []
    for , r in rows {
        total++
        winOk := false
        try winOk := WinExist(r["wtitle"]) ? true : false
        x := Integer(r["x"]), y := Integer(r["y"]), w := Integer(r["w"]), h := Integer(r["h"])
        boundsOk := (w > 0 && h > 0 && x >= vx - 50 && y >= vy - 50 && x < vx + vw + 50 && y < vy + vh + 50)
        ok := winOk && boundsOk
        if ok
            passed++
        results.Push(Map("label", Know_Clip(r["name"] . " @ " . r["wtitle"], 72)
                       , "detail", (winOk ? "win OK" : "win gone") . "  "
                               . (boundsOk ? "bounds OK" : "bounds off")
                       , "when", "", "bounds", [x, y, w, h], "content", ""))
    }
    score := total ? Round(passed * 100 / total) : 0
    if Know_Schema()
        try db.Run("INSERT INTO know_validation(ts,kind,total,passed,score) VALUES(?,?,?,?,?)"
                 , FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"), "spatial", total, passed, score)
    out["total"] := total, out["passed"] := passed, out["score"] := score, out["rows"] := results
    return out
}

; A compact digest of sampled knowledge, for a DeepSeek insight request.
Know_Digest() {
    db := TrackDB()
    if !db
        return ""
    parts := []
    Know_DigestBlock(db, parts, "Recent typed questions"
        , "SELECT question AS v FROM qa_item WHERE kind='typed' ORDER BY id DESC LIMIT 15", 110)
    Know_DigestBlock(db, parts, "Most-seen discovered UI targets"
        , "SELECT (name || ' @ ' || substr(title,1,40) || '  x' || seen_count) AS v FROM discovered_target "
        . "WHERE title<>'' ORDER BY seen_count DESC LIMIT 15", 90)
    Know_DigestBlock(db, parts, "Written automation tools (.ahk)"
        , "SELECT path AS v FROM app_file WHERE path LIKE '%.ahk' ORDER BY modified_ts DESC LIMIT 15", 90)
    Know_DigestBlock(db, parts, "Recent learning claims"
        , "SELECT claim AS v FROM learning_claim ORDER BY id DESC LIMIT 12", 110)
    Know_DigestBlock(db, parts, "Recent DAA tool steps"
        , "SELECT (tool || ' -> ' || status) AS v FROM daa_step ORDER BY id DESC LIMIT 12", 80)
    out := ""
    for , p in parts
        out .= p . "`n"
    return out
}

Know_DigestBlock(db, parts, title, sql, clip) {
    rows := []
    try rows := db.Query(sql)
    if !rows.Length
        return
    s := title . ":`n"
    for , r in rows
        s .= "- " . Know_Clip("" . r["v"], clip) . "`n"
    parts.Push(s)
}

; Ask DeepSeek for actionable insights over the accumulated knowledge.
; Returns Map(ok, text, cost, error).
Know_InsightsDeepSeek() {
    if !StudyLLM_HasKey()
        return Map("ok", false, "text", "", "cost", 0, "error", "No DeepSeek key (set one in Study Assistant)")
    digest := Know_Digest()
    if (Trim(digest) = "")
        return Map("ok", false, "text", "", "cost", 0, "error", "No knowledge captured yet to analyze")
    prompt := "You optimize a Windows desktop-automation agent's accumulated knowledge. "
            . "From this sample of what it has learned, give concrete, actionable output:`n"
            . "1) patterns/themes in what the user actually does;`n"
            . "2) 2-4 specific automations or reusable tools worth building next;`n"
            . "3) which captured knowledge looks stale/low-value and should be pruned;`n"
            . "4) how to reinforce and rank the most useful items.`n"
            . "Be specific and brief; reference the real items.`n`n"
            . "KNOWLEDGE SAMPLE:`n" . digest
    res := StudyLLM_Ask(prompt, Map("maxTokens", 1000))
    if !res["ok"]
        return Map("ok", false, "text", "", "cost", 0, "error", res["error"])
    return Map("ok", true, "text", res["answer"], "cost", res["costUSD"], "error", "")
}
