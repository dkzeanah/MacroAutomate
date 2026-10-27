FanUnified_Bootstrap() {
    global g_FanSeedPath
    if IsSet(g_FanSeedPath) && g_FanSeedPath != ""
        return
    root := FanData_ProjectRoot(), python := root . "\fan\DeepSeekBridge\.venv\Scripts\python.exe"
    code := RunWait('"' . python . '" -m fan.data_maintenance.unified bootstrap "' . root . '"', root, "Hide")
    if code != 0 {
        MsgBox("Single-database startup failed. Existing archives are unchanged. See fan\unified-startup.log.", "Fan storage")
        ExitApp(1)
    }
    FanData_Config(true)
}

; Used by the schema generator and native regression tests. No GUI, timers,
; providers, old INI imports, or personal database are opened in this mode.
FanUnified_Seed(path) {
    global g_FanSeedPath, DB_FILE, g_DB, g_AppMapDB, g_TrackDBError, g_AppMapDBError
    g_FanSeedPath := path, DB_FILE := path
    if FileExist(path)
        throw Error("Schema seed requires a new file: " . path)
    InitDB()
    if !TrackDB_Init(path)
        throw Error(g_TrackDBError)
    if !AppMapDB()
        throw Error(g_AppMapDBError)
    Snip_Schema()
    Qa_Schema()
    Study_Schema()
    UsagePredictor_ApplySchema()
    VS_ApplySchema(TrackDB())
    TrackDB().Exec("CREATE TABLE IF NOT EXISTS media_image(id INTEGER PRIMARY KEY AUTOINCREMENT,label TEXT,data_url TEXT NOT NULL,created_ts TEXT)")
    AutoDiscovery_Schema()
    LearningLab_Schema()
    FanState_DB()
    g_DB.CloseDB()
    g_AppMapDB.Close()
    TrackDB_Close()
    FanState_Close()
}
