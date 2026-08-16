; ═══════════════════════════════════════════════════════════════════════════════
; TrackingDB.ahk - Schema and data access for the MacroAutomator tracking store
; ═══════════════════════════════════════════════════════════════════════════════
; One SQLite file (data\tracking.db) backs every tracker:
;
;   app / win / win_session   window activation + accumulated focus time
;   mouse_snapshot            1-minute movement traces, per window
;   mouse_heat                aggregated grid heat, per window
;   mouse_feature             extracted interaction hotspots (element candidates)
;   key_snapshot              1-minute keystroke traces, per window
;   hotkey_stat / clip_history
;   snap_cycle / snap_entry   5-minute whole-desktop image captures
;   element                   named, described UI elements for automation
;   query / query_link / query_insight   research pipeline results
;
; Every write goes through a helper here so the trackers stay free of SQL.
; ═══════════════════════════════════════════════════════════════════════════════

global g_TrackDB := ""                     ; TrackSQLite instance (or "" when off)
global g_TrackDBError := ""                ; Last initialisation error
global g_TrackDBPath := ""                 ; Resolved database file path
global g_TrackAppCache := Map()            ; appKey  -> app_id
global g_TrackWinCache := Map()            ; appId|name -> win_id

; Current schema version. Bump when adding tables/columns below.
global TRACK_SCHEMA_VERSION := 3

; ═══════════════════════════════════════════════════════════════════════════════
; LIFECYCLE
; ═══════════════════════════════════════════════════════════════════════════════

; Open (creating if needed) the tracking database and apply the schema.
; Returns true when the store is usable.
TrackDB_Init(dbPath := "") {
    global g_TrackDB, g_TrackDBError, g_TrackDBPath, DATA_DIR

    if IsObject(g_TrackDB) && g_TrackDB.IsOpen()
        return true

    if (dbPath = "")
        dbPath := DATA_DIR . "\tracking.db"
    g_TrackDBPath := dbPath

    if !DirExist(DATA_DIR) {
        try DirCreate(DATA_DIR)
    }

    if !TrackSQLite.Available() {
        g_TrackDBError := TrackSQLite.loadError
        g_TrackDB := ""
        return false
    }

    try {
        g_TrackDB := TrackSQLite(dbPath)
        TrackDB_ApplySchema(g_TrackDB)
        g_TrackDBError := ""
        return true
    } catch as err {
        g_TrackDBError := err.Message
        g_TrackDB := ""
        return false
    }
}

; The live connection, or "" when tracking storage is unavailable.
TrackDB() {
    global g_TrackDB
    return (IsObject(g_TrackDB) && g_TrackDB.IsOpen()) ? g_TrackDB : ""
}

TrackDB_Ready() => TrackDB() != ""

TrackDB_Close() {
    global g_TrackDB, g_TrackAppCache, g_TrackWinCache
    if IsObject(g_TrackDB) {
        try g_TrackDB.Close()
    }
    g_TrackDB := ""
    g_TrackAppCache := Map()
    g_TrackWinCache := Map()
}

; ═══════════════════════════════════════════════════════════════════════════════
; SCHEMA
; ═══════════════════════════════════════════════════════════════════════════════

TrackDB_ApplySchema(db) {
    global TRACK_SCHEMA_VERSION

    ; Statements are applied one at a time so a failure names the exact object.
    ; (Kept as individual strings rather than a continuation section: a line
    ;  beginning with ")" would terminate a continuation section early.)
    for stmt in TrackDB_SchemaStatements()
        db.Exec(stmt)

    ; Forward-compatible column additions for databases created by older builds.
    db.AddColumnIfMissing("mouse_snapshot", "dwell_count", "INTEGER NOT NULL DEFAULT 0")
    db.AddColumnIfMissing("key_snapshot", "wpm", "REAL NOT NULL DEFAULT 0")
    db.AddColumnIfMissing("snap_entry", "ocr_text", "TEXT")
    db.AddColumnIfMissing("element", "role", "TEXT")
    db.AddColumnIfMissing("mouse_feature", "element_id", "INTEGER")

    db.Run("INSERT INTO meta(key,value) VALUES('schema_version',?) "
         . "ON CONFLICT(key) DO UPDATE SET value=excluded.value", TRACK_SCHEMA_VERSION)
}

; Full DDL for the tracking store, in dependency order.
TrackDB_SchemaStatements() {
    return [
    ; ─── Key/value metadata ─────────────────────────────────────────────────
      "CREATE TABLE IF NOT EXISTS meta ("
    . "  key TEXT PRIMARY KEY,"
    . "  value TEXT)"

    ; ─── Application surfaces (exe + window class) ───────────────────────────
    , "CREATE TABLE IF NOT EXISTS app ("
    . "  id          INTEGER PRIMARY KEY AUTOINCREMENT,"
    . "  app_key     TEXT NOT NULL UNIQUE,"
    . "  exe         TEXT,"
    . "  class       TEXT,"
    . "  display     TEXT,"
    . "  first_seen  TEXT,"
    . "  last_seen   TEXT,"
    . "  total_ms    INTEGER NOT NULL DEFAULT 0,"
    . "  activations INTEGER NOT NULL DEFAULT 0)"

    ; ─── Unique window names: the primary time-tracking unit ────────────────
    , "CREATE TABLE IF NOT EXISTS win ("
    . "  id          INTEGER PRIMARY KEY AUTOINCREMENT,"
    . "  app_id      INTEGER NOT NULL REFERENCES app(id),"
    . "  name        TEXT NOT NULL,"
    . "  raw_title   TEXT,"
    . "  first_seen  TEXT,"
    . "  last_seen   TEXT,"
    . "  total_ms    INTEGER NOT NULL DEFAULT 0,"
    . "  activations INTEGER NOT NULL DEFAULT 0,"
    . "  UNIQUE(app_id, name))"
    , "CREATE INDEX IF NOT EXISTS ix_win_app ON win(app_id)"

    ; ─── One row per contiguous focus interval ──────────────────────────────
    , "CREATE TABLE IF NOT EXISTS win_session ("
    . "  id          INTEGER PRIMARY KEY AUTOINCREMENT,"
    . "  win_id      INTEGER NOT NULL REFERENCES win(id),"
    . "  app_id      INTEGER NOT NULL,"
    . "  hwnd        INTEGER,"
    . "  raw_title   TEXT,"
    . "  start_ts    TEXT,"
    . "  end_ts      TEXT,"
    . "  duration_ms INTEGER NOT NULL DEFAULT 0,"
    . "  day         TEXT,"
    . "  hour        INTEGER,"
    . "  x INTEGER, y INTEGER, w INTEGER, h INTEGER)"
    , "CREATE INDEX IF NOT EXISTS ix_sess_win ON win_session(win_id)"
    , "CREATE INDEX IF NOT EXISTS ix_sess_day ON win_session(day)"

    ; ─── Mouse movement, 1-minute snapshots ─────────────────────────────────
    , "CREATE TABLE IF NOT EXISTS mouse_snapshot ("
    . "  id           INTEGER PRIMARY KEY AUTOINCREMENT,"
    . "  win_id       INTEGER NOT NULL REFERENCES win(id),"
    . "  app_id       INTEGER NOT NULL,"
    . "  minute_key   TEXT NOT NULL,"
    . "  start_ts     TEXT,"
    . "  end_ts       TEXT,"
    . "  samples      INTEGER NOT NULL DEFAULT 0,"
    . "  distance     REAL    NOT NULL DEFAULT 0,"
    . "  idle_ms      INTEGER NOT NULL DEFAULT 0,"
    . "  dwell_count  INTEGER NOT NULL DEFAULT 0,"
    . "  click_count  INTEGER NOT NULL DEFAULT 0,"
    . "  win_x INTEGER, win_y INTEGER, win_w INTEGER, win_h INTEGER,"
    . "  path_blob    TEXT,"
    . "  click_blob   TEXT,"
    . "  UNIQUE(win_id, minute_key))"
    , "CREATE INDEX IF NOT EXISTS ix_mouse_min ON mouse_snapshot(minute_key)"
    , "CREATE INDEX IF NOT EXISTS ix_mouse_win ON mouse_snapshot(win_id)"

    ; ─── Aggregated heat grid, window-relative cells ────────────────────────
    , "CREATE TABLE IF NOT EXISTS mouse_heat ("
    . "  win_id   INTEGER NOT NULL REFERENCES win(id),"
    . "  gx       INTEGER NOT NULL,"
    . "  gy       INTEGER NOT NULL,"
    . "  hits     INTEGER NOT NULL DEFAULT 0,"
    . "  clicks   INTEGER NOT NULL DEFAULT 0,"
    . "  dwell_ms INTEGER NOT NULL DEFAULT 0,"
    . "  PRIMARY KEY (win_id, gx, gy))"

    ; ─── Extracted interaction hotspots (element candidates) ────────────────
    , "CREATE TABLE IF NOT EXISTS mouse_feature ("
    . "  id        INTEGER PRIMARY KEY AUTOINCREMENT,"
    . "  win_id    INTEGER NOT NULL REFERENCES win(id),"
    . "  app_id    INTEGER NOT NULL,"
    . "  kind      TEXT,"
    . "  x INTEGER, y INTEGER, w INTEGER, h INTEGER,"
    . "  rel_x REAL, rel_y REAL,"
    . "  weight    REAL    NOT NULL DEFAULT 0,"
    . "  samples   INTEGER NOT NULL DEFAULT 0,"
    . "  clicks    INTEGER NOT NULL DEFAULT 0,"
    . "  dwell_ms  INTEGER NOT NULL DEFAULT 0,"
    . "  first_seen TEXT,"
    . "  last_seen  TEXT,"
    . "  element_id INTEGER)"
    , "CREATE INDEX IF NOT EXISTS ix_feat_win ON mouse_feature(win_id)"

    ; ─── Keystroke history, 1-minute snapshots ──────────────────────────────
    , "CREATE TABLE IF NOT EXISTS key_snapshot ("
    . "  id          INTEGER PRIMARY KEY AUTOINCREMENT,"
    . "  win_id      INTEGER NOT NULL REFERENCES win(id),"
    . "  app_id      INTEGER NOT NULL,"
    . "  minute_key  TEXT NOT NULL,"
    . "  start_ts    TEXT,"
    . "  end_ts      TEXT,"
    . "  keystrokes  INTEGER NOT NULL DEFAULT 0,"
    . "  raw_stream  TEXT,"
    . "  text_typed  TEXT,"
    . "  hotkeys     TEXT,"
    . "  strings     TEXT,"
    . "  sentences   TEXT,"
    . "  code_snips  TEXT,"
    . "  clips       TEXT,"
    . "  wpm         REAL NOT NULL DEFAULT 0,"
    . "  UNIQUE(win_id, minute_key))"
    , "CREATE INDEX IF NOT EXISTS ix_key_min ON key_snapshot(minute_key)"
    , "CREATE INDEX IF NOT EXISTS ix_key_win ON key_snapshot(win_id)"

    , "CREATE TABLE IF NOT EXISTS hotkey_stat ("
    . "  win_id  INTEGER NOT NULL,"
    . "  app_id  INTEGER NOT NULL,"
    . "  combo   TEXT NOT NULL,"
    . "  count   INTEGER NOT NULL DEFAULT 0,"
    . "  last_ts TEXT,"
    . "  PRIMARY KEY (win_id, combo))"

    , "CREATE TABLE IF NOT EXISTS clip_history ("
    . "  id         INTEGER PRIMARY KEY AUTOINCREMENT,"
    . "  win_id     INTEGER,"
    . "  app_id     INTEGER,"
    . "  ts         TEXT,"
    . "  minute_key TEXT,"
    . "  hash       TEXT,"
    . "  length     INTEGER,"
    . "  kind       TEXT,"
    . "  content    TEXT)"
    , "CREATE INDEX IF NOT EXISTS ix_clip_hash ON clip_history(hash)"
    , "CREATE INDEX IF NOT EXISTS ix_clip_ts   ON clip_history(ts)"

    ; ─── 5-minute whole-desktop snapshot cycles ─────────────────────────────
    , "CREATE TABLE IF NOT EXISTS snap_cycle ("
    . "  id           INTEGER PRIMARY KEY AUTOINCREMENT,"
    . "  started_ts   TEXT,"
    . "  finished_ts  TEXT,"
    . "  window_count INTEGER NOT NULL DEFAULT 0,"
    . "  note         TEXT)"

    , "CREATE TABLE IF NOT EXISTS snap_entry ("
    . "  id           INTEGER PRIMARY KEY AUTOINCREMENT,"
    . "  cycle_id     INTEGER NOT NULL REFERENCES snap_cycle(id),"
    . "  win_id       INTEGER,"
    . "  app_id       INTEGER,"
    . "  hwnd         INTEGER,"
    . "  title        TEXT,"
    . "  exe          TEXT,"
    . "  class        TEXT,"
    . "  ts           TEXT,"
    . "  x INTEGER, y INTEGER, w INTEGER, h INTEGER,"
    . "  image_path   TEXT,"
    . "  image_format TEXT,"
    . "  image_bytes  INTEGER,"
    . "  image_hash   TEXT,"
    . "  b64          TEXT,"
    . "  b64_len      INTEGER,"
    . "  bin_text     TEXT,"
    . "  bin_w        INTEGER,"
    . "  bin_h        INTEGER,"
    . "  threshold    TEXT,"
    . "  ocr_text     TEXT)"
    , "CREATE INDEX IF NOT EXISTS ix_snap_cycle ON snap_entry(cycle_id)"
    , "CREATE INDEX IF NOT EXISTS ix_snap_win   ON snap_entry(win_id)"

    ; ─── Named, described elements consumable by the automation engine ──────
    , "CREATE TABLE IF NOT EXISTS element ("
    . "  id            INTEGER PRIMARY KEY AUTOINCREMENT,"
    . "  win_id        INTEGER,"
    . "  app_id        INTEGER,"
    . "  snap_entry_id INTEGER,"
    . "  name          TEXT NOT NULL,"
    . "  description   TEXT,"
    . "  role          TEXT,"
    . "  x INTEGER, y INTEGER, w INTEGER, h INTEGER,"
    . "  rel_x REAL, rel_y REAL, rel_w REAL, rel_h REAL,"
    . "  bin_text      TEXT,"
    . "  ocr_text      TEXT,"
    . "  image_path    TEXT,"
    . "  b64           TEXT,"
    . "  created_ts    TEXT,"
    . "  updated_ts    TEXT,"
    . "  hits          INTEGER NOT NULL DEFAULT 0,"
    . "  last_hit_ts   TEXT,"
    . "  UNIQUE(win_id, name))"
    , "CREATE INDEX IF NOT EXISTS ix_elem_name ON element(name)"

    ; ─── Research pipeline: query -> links -> per-link insight ──────────────
    , "CREATE TABLE IF NOT EXISTS query ("
    . "  id         INTEGER PRIMARY KEY AUTOINCREMENT,"
    . "  text       TEXT NOT NULL,"
    . "  engine     TEXT,"
    . "  created_ts TEXT,"
    . "  status     TEXT,"
    . "  note       TEXT)"

    , "CREATE TABLE IF NOT EXISTS query_link ("
    . "  id         INTEGER PRIMARY KEY AUTOINCREMENT,"
    . "  query_id   INTEGER NOT NULL REFERENCES query(id),"
    . "  rank       INTEGER,"
    . "  url        TEXT,"
    . "  title      TEXT,"
    . "  status     TEXT,"
    . "  visited_ts TEXT,"
    . "  created_ts TEXT)"
    , "CREATE INDEX IF NOT EXISTS ix_link_query ON query_link(query_id)"

    , "CREATE TABLE IF NOT EXISTS query_insight ("
    . "  id         INTEGER PRIMARY KEY AUTOINCREMENT,"
    . "  query_id   INTEGER NOT NULL REFERENCES query(id),"
    . "  link_id    INTEGER,"
    . "  insight    TEXT,"
    . "  source     TEXT,"
    . "  created_ts TEXT)"
    , "CREATE INDEX IF NOT EXISTS ix_insight_query ON query_insight(query_id)"
    ]
}

; ═══════════════════════════════════════════════════════════════════════════════
; META KEY/VALUE
; ═══════════════════════════════════════════════════════════════════════════════

TrackDB_MetaGet(key, default := "") {
    db := TrackDB()
    if !db
        return default
    v := db.Scalar("SELECT value FROM meta WHERE key=?", key)
    return (v = "") ? default : v
}

TrackDB_MetaSet(key, value) {
    db := TrackDB()
    if !db
        return false
    db.Run("INSERT INTO meta(key,value) VALUES(?,?) "
         . "ON CONFLICT(key) DO UPDATE SET value=excluded.value", key, value)
    return true
}

; ═══════════════════════════════════════════════════════════════════════════════
; IDENTITY RESOLUTION
; ═══════════════════════════════════════════════════════════════════════════════

; Resolve (creating on first sight) the app row for an exe/class pair.
TrackDB_AppId(exe, class) {
    global g_TrackAppCache
    db := TrackDB()
    if !db
        return 0

    key := TrackAppKey(exe, class)
    if g_TrackAppCache.Has(key)
        return g_TrackAppCache[key]

    now := TrackTS()
    SplitPath(exe, , , , &display)
    if (display = "")
        display := exe

    db.Run("INSERT INTO app(app_key,exe,class,display,first_seen,last_seen) "
         . "VALUES(?,?,?,?,?,?) ON CONFLICT(app_key) DO UPDATE SET last_seen=excluded.last_seen"
         , key, exe, class, display, now, now)
    id := db.Scalar("SELECT id FROM app WHERE app_key=?", key)
    id := IsInteger(id) ? Integer(id) : 0
    if id
        g_TrackAppCache[key] := id
    return id
}

; Resolve (creating on first sight) the win row for a normalised window name.
; Returns a Map: win_id, app_id, name.
TrackDB_ResolveWindow(title, class, exe, aggressive := false) {
    global g_TrackWinCache
    db := TrackDB()
    result := Map("win_id", 0, "app_id", 0, "name", "")
    if !db
        return result

    appId := TrackDB_AppId(exe, class)
    if !appId
        return result

    name := TrackNormalizeWindowName(title, exe, aggressive)
    cacheKey := appId . "|" . name
    result["app_id"] := appId
    result["name"] := name

    if g_TrackWinCache.Has(cacheKey) {
        result["win_id"] := g_TrackWinCache[cacheKey]
        return result
    }

    now := TrackTS()
    db.Run("INSERT INTO win(app_id,name,raw_title,first_seen,last_seen) VALUES(?,?,?,?,?) "
         . "ON CONFLICT(app_id,name) DO UPDATE SET last_seen=excluded.last_seen, raw_title=excluded.raw_title"
         , appId, name, title, now, now)
    id := db.Scalar("SELECT id FROM win WHERE app_id=? AND name=?", appId, name)
    id := IsInteger(id) ? Integer(id) : 0
    if id
        g_TrackWinCache[cacheKey] := id
    result["win_id"] := id
    return result
}

; Look up a window id by name (exact, then LIKE). Used by workflow actions
; that address a window by its tracked name.
TrackDB_FindWinByName(name) {
    db := TrackDB()
    if !db
        return 0
    id := db.Scalar("SELECT id FROM win WHERE name=? ORDER BY total_ms DESC LIMIT 1", name)
    if (id != "")
        return Integer(id)
    id := db.Scalar("SELECT id FROM win WHERE name LIKE ? ORDER BY total_ms DESC LIMIT 1", "%" . name . "%")
    return (id = "") ? 0 : Integer(id)
}

TrackDB_WinRow(winId) {
    db := TrackDB()
    if !db
        return Map()
    return db.QueryRow("SELECT w.*, a.exe AS exe, a.class AS class, a.display AS app_display "
                     . "FROM win w JOIN app a ON a.id=w.app_id WHERE w.id=?", winId)
}

; ═══════════════════════════════════════════════════════════════════════════════
; WINDOW TIME WRITES
; ═══════════════════════════════════════════════════════════════════════════════

; Record a completed focus interval and roll the time up into win + app.
TrackDB_AddSession(winId, appId, hwnd, rawTitle, startTs, endTs, durationMs, rect) {
    db := TrackDB()
    if !db || !winId
        return 0

    day := SubStr(startTs, 1, 10)
    hour := Integer(SubStr(startTs, 12, 2))

    db.Run("INSERT INTO win_session(win_id,app_id,hwnd,raw_title,start_ts,end_ts,duration_ms,day,hour,x,y,w,h) "
         . "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)"
         , winId, appId, hwnd, rawTitle, startTs, endTs, durationMs, day, hour
         , rect.Has("x") ? rect["x"] : 0, rect.Has("y") ? rect["y"] : 0
         , rect.Has("w") ? rect["w"] : 0, rect.Has("h") ? rect["h"] : 0)
    sessId := db.LastInsertId()

    db.Run("UPDATE win SET total_ms = total_ms + ?, activations = activations + 1, "
         . "last_seen = ?, raw_title = ? WHERE id = ?", durationMs, endTs, rawTitle, winId)
    db.Run("UPDATE app SET total_ms = total_ms + ?, activations = activations + 1, "
         . "last_seen = ? WHERE id = ?", durationMs, endTs, appId)

    return sessId
}

; Open a zero-length focus interval. The tracker extends it on a heartbeat so
; that an unexpected exit loses at most one heartbeat of time rather than the
; whole session.
TrackDB_OpenSession(winId, appId, hwnd, rawTitle, startTs, rect) {
    db := TrackDB()
    if !db || !winId
        return 0

    day := SubStr(startTs, 1, 10)
    hour := Integer(SubStr(startTs, 12, 2))

    db.Run("INSERT INTO win_session(win_id,app_id,hwnd,raw_title,start_ts,end_ts,duration_ms,day,hour,x,y,w,h) "
         . "VALUES(?,?,?,?,?,?,0,?,?,?,?,?,?)"
         , winId, appId, hwnd, rawTitle, startTs, startTs, day, hour
         , rect.Has("x") ? rect["x"] : 0, rect.Has("y") ? rect["y"] : 0
         , rect.Has("w") ? rect["w"] : 0, rect.Has("h") ? rect["h"] : 0)
    sessId := db.LastInsertId()

    ; The activation is counted once, when the interval opens.
    db.Run("UPDATE win SET activations = activations + 1, last_seen = ?, raw_title = ? WHERE id = ?"
         , startTs, rawTitle, winId)
    db.Run("UPDATE app SET activations = activations + 1, last_seen = ? WHERE id = ?"
         , startTs, appId)

    return sessId
}

; Add `deltaMs` of elapsed focus time to an open interval and its rollups.
TrackDB_ExtendSession(sessId, winId, appId, deltaMs, endTs) {
    db := TrackDB()
    if !db || !sessId || deltaMs <= 0
        return false

    db.Run("UPDATE win_session SET duration_ms = duration_ms + ?, end_ts = ? WHERE id = ?"
         , deltaMs, endTs, sessId)
    db.Run("UPDATE win SET total_ms = total_ms + ?, last_seen = ? WHERE id = ?"
         , deltaMs, endTs, winId)
    db.Run("UPDATE app SET total_ms = total_ms + ?, last_seen = ? WHERE id = ?"
         , deltaMs, endTs, appId)
    return true
}

; Drop zero-length intervals left behind by transient focus flicker.
TrackDB_PruneEmptySessions(minMs := 250) {
    db := TrackDB()
    if !db
        return 0
    db.Run("DELETE FROM win_session WHERE duration_ms < ?", minMs)
    return db.Changes()
}

; Leaderboard of tracked window names.
; scope: "all" | "today" | "week"
TrackDB_TopWindows(scope := "all", limit := 200) {
    db := TrackDB()
    if !db
        return []

    if (scope = "all") {
        return db.Query("SELECT w.id, w.name, w.total_ms, w.activations, w.last_seen, "
                      . "a.display AS app, a.exe AS exe "
                      . "FROM win w JOIN app a ON a.id = w.app_id "
                      . "WHERE w.total_ms > 0 ORDER BY w.total_ms DESC LIMIT ?", limit)
    }

    since := (scope = "today") ? TrackDayKey() : FormatTime(DateAdd(A_Now, -7, "Days"), "yyyy-MM-dd")
    return db.Query("SELECT w.id, w.name, SUM(s.duration_ms) AS total_ms, COUNT(*) AS activations, "
                  . "MAX(s.end_ts) AS last_seen, a.display AS app, a.exe AS exe "
                  . "FROM win_session s JOIN win w ON w.id = s.win_id JOIN app a ON a.id = w.app_id "
                  . "WHERE s.day >= ? GROUP BY w.id ORDER BY total_ms DESC LIMIT ?", since, limit)
}

; Per-application totals for the same scopes.
TrackDB_TopApps(scope := "all", limit := 100) {
    db := TrackDB()
    if !db
        return []
    if (scope = "all") {
        return db.Query("SELECT id, display AS app, exe, total_ms, activations, last_seen "
                      . "FROM app WHERE total_ms > 0 ORDER BY total_ms DESC LIMIT ?", limit)
    }
    since := (scope = "today") ? TrackDayKey() : FormatTime(DateAdd(A_Now, -7, "Days"), "yyyy-MM-dd")
    return db.Query("SELECT a.id, a.display AS app, a.exe, SUM(s.duration_ms) AS total_ms, "
                  . "COUNT(*) AS activations, MAX(s.end_ts) AS last_seen "
                  . "FROM win_session s JOIN app a ON a.id = s.app_id "
                  . "WHERE s.day >= ? GROUP BY a.id ORDER BY total_ms DESC LIMIT ?", since, limit)
}

; Hour-of-day histogram for one window (or all windows when winId = 0).
TrackDB_HourHistogram(winId := 0) {
    db := TrackDB()
    if !db
        return []
    if winId
        return db.Query("SELECT hour, SUM(duration_ms) AS total_ms FROM win_session "
                      . "WHERE win_id=? GROUP BY hour ORDER BY hour", winId)
    return db.Query("SELECT hour, SUM(duration_ms) AS total_ms FROM win_session "
                  . "GROUP BY hour ORDER BY hour")
}

; ═══════════════════════════════════════════════════════════════════════════════
; MOUSE WRITES
; ═══════════════════════════════════════════════════════════════════════════════

; Persist one 1-minute mouse snapshot. Re-running the same minute merges by
; appending to the stored path rather than duplicating the row.
TrackDB_AddMouseSnapshot(snap) {
    db := TrackDB()
    if !db || !snap.Has("win_id") || !snap["win_id"]
        return 0

    db.Run("INSERT INTO mouse_snapshot"
         . "(win_id,app_id,minute_key,start_ts,end_ts,samples,distance,idle_ms,dwell_count,click_count,"
         . " win_x,win_y,win_w,win_h,path_blob,click_blob) "
         . "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) "
         . "ON CONFLICT(win_id,minute_key) DO UPDATE SET "
         . "  end_ts=excluded.end_ts,"
         . "  samples=mouse_snapshot.samples+excluded.samples,"
         . "  distance=mouse_snapshot.distance+excluded.distance,"
         . "  idle_ms=mouse_snapshot.idle_ms+excluded.idle_ms,"
         . "  dwell_count=mouse_snapshot.dwell_count+excluded.dwell_count,"
         . "  click_count=mouse_snapshot.click_count+excluded.click_count,"
         . "  path_blob=mouse_snapshot.path_blob||';'||excluded.path_blob,"
         . "  click_blob=CASE WHEN excluded.click_blob='' THEN mouse_snapshot.click_blob "
         . "                  WHEN mouse_snapshot.click_blob='' THEN excluded.click_blob "
         . "                  ELSE mouse_snapshot.click_blob||';'||excluded.click_blob END"
         , snap["win_id"], snap["app_id"], snap["minute_key"], snap["start_ts"], snap["end_ts"]
         , snap["samples"], snap["distance"], snap["idle_ms"], snap["dwell_count"], snap["click_count"]
         , snap["win_x"], snap["win_y"], snap["win_w"], snap["win_h"]
         , snap["path_blob"], snap["click_blob"])
    return db.LastInsertId()
}

; Merge a batch of grid-cell hits into the aggregated heat table.
; cells: Map of "gx,gy" -> Map("hits", n, "clicks", n, "dwell_ms", n)
TrackDB_MergeHeat(winId, cells) {
    db := TrackDB()
    if !db || !winId || !cells.Count
        return 0

    db.Begin()
    try {
        for key, c in cells {
            parts := StrSplit(key, ",")
            if (parts.Length < 2)
                continue
            db.Run("INSERT INTO mouse_heat(win_id,gx,gy,hits,clicks,dwell_ms) VALUES(?,?,?,?,?,?) "
                 . "ON CONFLICT(win_id,gx,gy) DO UPDATE SET "
                 . "hits=mouse_heat.hits+excluded.hits, "
                 . "clicks=mouse_heat.clicks+excluded.clicks, "
                 . "dwell_ms=mouse_heat.dwell_ms+excluded.dwell_ms"
                 , winId, Integer(parts[1]), Integer(parts[2])
                 , c["hits"], c["clicks"], c["dwell_ms"])
        }
    } catch as err {
        db.Rollback()
        throw err
    }
    db.Commit()
    return cells.Count
}

; ═══════════════════════════════════════════════════════════════════════════════
; KEY WRITES
; ═══════════════════════════════════════════════════════════════════════════════

TrackDB_AddKeySnapshot(snap) {
    db := TrackDB()
    if !db || !snap.Has("win_id") || !snap["win_id"]
        return 0

    db.Run("INSERT INTO key_snapshot"
         . "(win_id,app_id,minute_key,start_ts,end_ts,keystrokes,raw_stream,text_typed,"
         . " hotkeys,strings,sentences,code_snips,clips,wpm) "
         . "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?) "
         . "ON CONFLICT(win_id,minute_key) DO UPDATE SET "
         . "  end_ts=excluded.end_ts,"
         . "  keystrokes=key_snapshot.keystrokes+excluded.keystrokes,"
         . "  raw_stream=key_snapshot.raw_stream||excluded.raw_stream,"
         . "  text_typed=key_snapshot.text_typed||excluded.text_typed,"
         . "  hotkeys=CASE WHEN excluded.hotkeys='' THEN key_snapshot.hotkeys "
         . "               WHEN key_snapshot.hotkeys='' THEN excluded.hotkeys "
         . "               ELSE key_snapshot.hotkeys||' '||excluded.hotkeys END,"
         . "  strings=CASE WHEN excluded.strings='' THEN key_snapshot.strings "
         . "               ELSE key_snapshot.strings||char(10)||excluded.strings END,"
         . "  sentences=CASE WHEN excluded.sentences='' THEN key_snapshot.sentences "
         . "                 ELSE key_snapshot.sentences||char(10)||excluded.sentences END,"
         . "  code_snips=CASE WHEN excluded.code_snips='' THEN key_snapshot.code_snips "
         . "                  ELSE key_snapshot.code_snips||char(10)||excluded.code_snips END,"
         . "  clips=CASE WHEN excluded.clips='' THEN key_snapshot.clips "
         . "             ELSE key_snapshot.clips||char(10)||excluded.clips END,"
         . "  wpm=excluded.wpm"
         , snap["win_id"], snap["app_id"], snap["minute_key"], snap["start_ts"], snap["end_ts"]
         , snap["keystrokes"], snap["raw_stream"], snap["text_typed"], snap["hotkeys"]
         , snap["strings"], snap["sentences"], snap["code_snips"], snap["clips"], snap["wpm"])
    return db.LastInsertId()
}

TrackDB_BumpHotkey(winId, appId, combo, count := 1) {
    db := TrackDB()
    if !db || !winId || combo = ""
        return false
    db.Run("INSERT INTO hotkey_stat(win_id,app_id,combo,count,last_ts) VALUES(?,?,?,?,?) "
         . "ON CONFLICT(win_id,combo) DO UPDATE SET count=hotkey_stat.count+excluded.count, "
         . "last_ts=excluded.last_ts", winId, appId, combo, count, TrackTS())
    return true
}

TrackDB_AddClip(winId, appId, content, kind := "text") {
    db := TrackDB()
    if !db || content = ""
        return 0
    hash := TrackHash(content)
    ; Skip an identical clip captured within the last 5 minutes.
    dup := db.Scalar("SELECT COUNT(*) FROM clip_history WHERE hash=? "
                   . "AND ts > datetime('now','localtime','-5 minutes')", hash)
    if (dup > 0)
        return 0
    db.Run("INSERT INTO clip_history(win_id,app_id,ts,minute_key,hash,length,kind,content) "
         . "VALUES(?,?,?,?,?,?,?,?)"
         , winId, appId, TrackTS(), TrackMinuteKey(), hash, StrLen(content), kind, content)
    return db.LastInsertId()
}

; ═══════════════════════════════════════════════════════════════════════════════
; SNAPSHOT WRITES
; ═══════════════════════════════════════════════════════════════════════════════

TrackDB_StartCycle(note := "") {
    db := TrackDB()
    if !db
        return 0
    db.Run("INSERT INTO snap_cycle(started_ts,note) VALUES(?,?)", TrackTS(), note)
    return db.LastInsertId()
}

TrackDB_FinishCycle(cycleId, windowCount) {
    db := TrackDB()
    if !db || !cycleId
        return false
    db.Run("UPDATE snap_cycle SET finished_ts=?, window_count=? WHERE id=?"
         , TrackTS(), windowCount, cycleId)
    return true
}

TrackDB_AddSnapEntry(e) {
    db := TrackDB()
    if !db || !e.Has("cycle_id")
        return 0
    db.Run("INSERT INTO snap_entry"
         . "(cycle_id,win_id,app_id,hwnd,title,exe,class,ts,x,y,w,h,"
         . " image_path,image_format,image_bytes,image_hash,b64,b64_len,"
         . " bin_text,bin_w,bin_h,threshold,ocr_text) "
         . "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
         , e["cycle_id"], e["win_id"], e["app_id"], e["hwnd"], e["title"], e["exe"], e["class"]
         , e["ts"], e["x"], e["y"], e["w"], e["h"]
         , e["image_path"], e["image_format"], e["image_bytes"], e["image_hash"]
         , e["b64"], e["b64_len"], e["bin_text"], e["bin_w"], e["bin_h"], e["threshold"]
         , e.Has("ocr_text") ? e["ocr_text"] : "")
    return db.LastInsertId()
}

TrackDB_CycleEntries(cycleId) {
    db := TrackDB()
    if !db
        return []
    return db.Query("SELECT * FROM snap_entry WHERE cycle_id=? ORDER BY id", cycleId)
}

TrackDB_RecentCycles(limit := 50) {
    db := TrackDB()
    if !db
        return []
    return db.Query("SELECT c.*, (SELECT COUNT(*) FROM snap_entry e WHERE e.cycle_id=c.id) AS entries "
                  . "FROM snap_cycle c ORDER BY c.id DESC LIMIT ?", limit)
}

; ═══════════════════════════════════════════════════════════════════════════════
; ELEMENT REGISTRY WRITES
; ═══════════════════════════════════════════════════════════════════════════════

; Insert or update a named element. Returns the element id.
TrackDB_SaveElement(el) {
    db := TrackDB()
    if !db || !el.Has("name") || el["name"] = ""
        return 0

    now := TrackTS()
    db.Run("INSERT INTO element"
         . "(win_id,app_id,snap_entry_id,name,description,role,x,y,w,h,rel_x,rel_y,rel_w,rel_h,"
         . " bin_text,ocr_text,image_path,b64,created_ts,updated_ts) "
         . "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) "
         . "ON CONFLICT(win_id,name) DO UPDATE SET "
         . "  description=excluded.description, role=excluded.role,"
         . "  snap_entry_id=excluded.snap_entry_id,"
         . "  x=excluded.x, y=excluded.y, w=excluded.w, h=excluded.h,"
         . "  rel_x=excluded.rel_x, rel_y=excluded.rel_y, rel_w=excluded.rel_w, rel_h=excluded.rel_h,"
         . "  bin_text=excluded.bin_text, ocr_text=excluded.ocr_text,"
         . "  image_path=excluded.image_path, b64=excluded.b64,"
         . "  updated_ts=excluded.updated_ts"
         , el["win_id"], el["app_id"], el.Has("snap_entry_id") ? el["snap_entry_id"] : 0
         , el["name"], el.Has("description") ? el["description"] : ""
         , el.Has("role") ? el["role"] : ""
         , el["x"], el["y"], el["w"], el["h"]
         , el["rel_x"], el["rel_y"], el["rel_w"], el["rel_h"]
         , el.Has("bin_text") ? el["bin_text"] : ""
         , el.Has("ocr_text") ? el["ocr_text"] : ""
         , el.Has("image_path") ? el["image_path"] : ""
         , el.Has("b64") ? el["b64"] : ""
         , now, now)

    id := db.Scalar("SELECT id FROM element WHERE win_id=? AND name=?", el["win_id"], el["name"])
    return (id = "") ? 0 : Integer(id)
}

; Find an element by name - exact first, then case-insensitive partial.
TrackDB_FindElement(name, winId := 0) {
    db := TrackDB()
    if !db
        return Map()
    if winId {
        row := db.QueryRow("SELECT * FROM element WHERE win_id=? AND name=?", winId, name)
        if row.Count
            return row
    }
    row := db.QueryRow("SELECT * FROM element WHERE name=? ORDER BY hits DESC LIMIT 1", name)
    if row.Count
        return row
    return db.QueryRow("SELECT * FROM element WHERE name LIKE ? ORDER BY hits DESC LIMIT 1"
                     , "%" . name . "%")
}

TrackDB_BumpElementHit(elementId) {
    db := TrackDB()
    if !db || !elementId
        return false
    db.Run("UPDATE element SET hits=hits+1, last_hit_ts=? WHERE id=?", TrackTS(), elementId)
    return true
}

TrackDB_Elements(winId := 0) {
    db := TrackDB()
    if !db
        return []
    if winId
        return db.Query("SELECT * FROM element WHERE win_id=? ORDER BY name", winId)
    return db.Query("SELECT e.*, w.name AS win_name FROM element e "
                  . "LEFT JOIN win w ON w.id=e.win_id ORDER BY w.name, e.name")
}

TrackDB_DeleteElement(elementId) {
    db := TrackDB()
    if !db
        return false
    db.Run("DELETE FROM element WHERE id=?", elementId)
    return true
}

; ═══════════════════════════════════════════════════════════════════════════════
; RESEARCH PIPELINE WRITES
; ═══════════════════════════════════════════════════════════════════════════════

TrackDB_AddQuery(text, engine := "google") {
    db := TrackDB()
    if !db || text = ""
        return 0
    db.Run("INSERT INTO query(text,engine,created_ts,status) VALUES(?,?,?,'open')"
         , text, engine, TrackTS())
    return db.LastInsertId()
}

TrackDB_AddQueryLink(queryId, rank, url, title := "") {
    db := TrackDB()
    if !db || !queryId || url = ""
        return 0
    ; Skip URLs already captured for this query.
    dup := db.Scalar("SELECT COUNT(*) FROM query_link WHERE query_id=? AND url=?", queryId, url)
    if (dup > 0)
        return 0
    db.Run("INSERT INTO query_link(query_id,rank,url,title,status,created_ts) "
         . "VALUES(?,?,?,?,'pending',?)", queryId, rank, url, title, TrackTS())
    return db.LastInsertId()
}

TrackDB_AddInsight(queryId, linkId, insight, source := "") {
    db := TrackDB()
    if !db || !queryId || insight = ""
        return 0
    db.Run("INSERT INTO query_insight(query_id,link_id,insight,source,created_ts) "
         . "VALUES(?,?,?,?,?)", queryId, linkId, insight, source, TrackTS())
    if linkId
        db.Run("UPDATE query_link SET status='done', visited_ts=? WHERE id=?", TrackTS(), linkId)
    return db.LastInsertId()
}

TrackDB_NextPendingLink(queryId) {
    db := TrackDB()
    if !db
        return Map()
    return db.QueryRow("SELECT * FROM query_link WHERE query_id=? AND status='pending' "
                     . "ORDER BY rank, id LIMIT 1", queryId)
}

TrackDB_QueryByText(text) {
    db := TrackDB()
    if !db
        return Map()
    return db.QueryRow("SELECT * FROM query WHERE text=? ORDER BY id DESC LIMIT 1", text)
}

; ═══════════════════════════════════════════════════════════════════════════════
; MAINTENANCE
; ═══════════════════════════════════════════════════════════════════════════════

; Delete tracking rows older than `days`. Snapshot image files on disk that no
; longer have a database row are removed too.
TrackDB_Prune(days := 30) {
    db := TrackDB()
    if !db
        return Map("rows", 0, "files", 0)

    cutoff := FormatTime(DateAdd(A_Now, -days, "Days"), "yyyy-MM-dd HH:mm:ss")
    removedFiles := 0

    ; Collect image paths that are about to lose their row.
    doomed := db.Column("SELECT image_path FROM snap_entry WHERE ts < ? AND image_path <> ''", cutoff)

    rows := 0
    db.Begin()
    try {
        db.Run("DELETE FROM win_session WHERE start_ts < ?", cutoff)
        rows += db.Changes()
        db.Run("DELETE FROM mouse_snapshot WHERE start_ts < ?", cutoff)
        rows += db.Changes()
        db.Run("DELETE FROM key_snapshot WHERE start_ts < ?", cutoff)
        rows += db.Changes()
        db.Run("DELETE FROM clip_history WHERE ts < ?", cutoff)
        rows += db.Changes()
        db.Run("DELETE FROM snap_entry WHERE ts < ?", cutoff)
        rows += db.Changes()
        db.Run("DELETE FROM snap_cycle WHERE started_ts < ? "
             . "AND id NOT IN (SELECT DISTINCT cycle_id FROM snap_entry)", cutoff)
        rows += db.Changes()
    } catch as err {
        db.Rollback()
        throw err
    }
    db.Commit()

    for p in doomed {
        if (p != "" && FileExist(p)) {
            try {
                FileDelete(p)
                removedFiles++
            }
        }
    }

    return Map("rows", rows, "files", removedFiles)
}

; Row counts per table, for the status display.
TrackDB_Stats() {
    db := TrackDB()
    stats := Map()
    if !db
        return stats
    tables := ["app", "win", "win_session", "mouse_snapshot", "mouse_heat", "mouse_feature"
             , "key_snapshot", "hotkey_stat", "clip_history", "snap_cycle", "snap_entry"
             , "element", "query", "query_link", "query_insight"]
    for t in tables {
        try stats[t] := db.Scalar("SELECT COUNT(*) FROM " . t)
        catch
            stats[t] := 0
    }
    return stats
}
