; Fan-owned text documents share the unified database. Native files are only
; used for explicit exports, external inputs, and disposable render caches.
global g_FanStateDB := "", g_FanStatePath := ""

FanState_DB() {
    global g_FanStateDB, g_FanStatePath, g_TrackDB, g_TrackDBPath
    path := FanData_Routes().Get("unified_db", "")
    if path = ""
        throw Error("Unified storage is not configured.")
    if IsSet(g_TrackDB) && IsObject(g_TrackDB) && g_TrackDB.IsOpen() && g_TrackDBPath = path {
        FanState_Schema(g_TrackDB)
        return g_TrackDB
    }
    if !IsObject(g_FanStateDB) || !g_FanStateDB.IsOpen() || g_FanStatePath != path {
        if IsObject(g_FanStateDB)
            g_FanStateDB.Close()
        g_FanStateDB := TrackSQLite(path)
        g_FanStatePath := path
        FanState_Schema(g_FanStateDB)
        OnExit(FanState_Close)
    }
    return g_FanStateDB
}

FanState_Schema(db) {
    if !db.TableExists("app_file")
        db.Exec("CREATE TABLE IF NOT EXISTS app_file(path TEXT PRIMARY KEY,content TEXT NOT NULL DEFAULT '',modified_ts TEXT)")
    if !db.TableExists("app_config")
        db.Exec("CREATE TABLE IF NOT EXISTS app_config(key TEXT PRIMARY KEY,value TEXT NOT NULL)")
}

FanState_Close(*) {
    global g_FanStateDB
    if IsObject(g_FanStateDB) {
        try g_FanStateDB.Exec("PRAGMA wal_checkpoint(TRUNCATE)")
        try g_FanStateDB.Close()
    }
    g_FanStateDB := ""
}

FanFile_Key(path) {
    if !FanData_Routes().Has("unified_db") || Type(path) != "String"
        return ""
    full := FanFile_Absolute(path), root := StrLower(FanFile_Absolute(FanData_ProjectRoot())) . "\"
    if SubStr(full, 1, StrLen(root)) != root
        return ""
    relative := StrReplace(SubStr(full, StrLen(root)+1), "\", "/")
    if RegExMatch(relative, "^(data|fan/data)/(coordinates\.csv|sequences\.ini|hotkeys\.ini|settings\.ini|extraction_rules\.csv|patterns\.ini|spools\.ini|ocr_log\.txt|ocr_words\.ini|analytics\.ini|recording\.csv|hotstrings\.txt|notification_schedule\.txt|templates\.json|notification_triggers\.json|revolver_bins\.ini|taskbar\.ini|appointments\.ini|patients\.ini|trigger_log\.txt|tracking_errors\.log)$")
        return relative
    if RegExMatch(relative, "^(data/(notes|logs|learning_insights)/|fan/logs/study/).+\.(txt|log|json|jsonl|md|csv)$")
        return relative
    return ""
}

FanFile_Absolute(path) {
    length := DllCall("GetFullPathNameW", "str", path, "uint", 0, "ptr", 0, "ptr", 0, "uint")
    resolved := Buffer(length*2)
    if !length || !DllCall("GetFullPathNameW", "str", path, "uint", length, "ptr", resolved, "ptr", 0, "uint")
        throw Error("Cannot resolve document path: " . path)
    return StrLower(StrGet(resolved))
}

FanFileRead(path, options := "") {
    key := FanFile_Key(path)
    if key = ""
        return FileRead(path, options)
    rows := FanState_DB().Query("SELECT content FROM app_file WHERE path=?", key)
    if !rows.Length
        throw Error("Document not found: " . path)
    return rows[1]["content"]
}

FanFileExist(path) {
    key := FanFile_Key(path)
    return key = "" ? FileExist(path) : (FanState_DB().Scalar("SELECT COUNT(*) FROM app_file WHERE path=?", key) ? "A" : "")
}

FanFileDelete(path) {
    key := FanFile_Key(path)
    if key = ""
        return FileDelete(path)
    FanState_DB().Run("DELETE FROM app_file WHERE path=?", key)
}

FanFileAppend(text, path := "*", encoding := "") {
    key := FanFile_Key(path)
    if key = ""
        return FileAppend(text, path, encoding)
    FanState_DB().Run("INSERT INTO app_file(path,content,modified_ts) VALUES(?,COALESCE(?,''),?) "
        . "ON CONFLICT(path) DO UPDATE SET content=app_file.content||excluded.content,modified_ts=excluded.modified_ts", key, text, TrackTS())
}

FanFile_Set(path, text) {
    key := FanFile_Key(path)
    if key = ""
        throw Error("Not a managed Fan document: " . path)
    FanState_DB().Run("INSERT INTO app_file(path,content,modified_ts) VALUES(?,COALESCE(?,''),?) "
        . "ON CONFLICT(path) DO UPDATE SET content=excluded.content,modified_ts=excluded.modified_ts", key, text, TrackTS())
}

FanFileOpen(path, flags, encoding := "") {
    if FanFile_Key(path) = ""
        return FileOpen(path, flags, encoding)
    if flags != "w"
        throw Error("Unsupported document open mode: " . flags)
    return FanDocumentWriter(path)
}

class FanDocumentWriter {
    __New(path) {
        this.path := path, this.text := "", this.closed := false
    }
    Write(text) {
        this.text .= text
        return StrLen(text)
    }
    WriteLine(text := "") => this.Write(text . "`r`n")
    Close() {
        if !this.closed {
            FanFile_Set(this.path, this.text)
            this.closed := true
        }
    }
    __Delete() {
        if !this.closed
            this.Close()
    }
}

; The Windows INI implementation parses a temporary copy; its committed text
; lives in SQLite, preserving existing INI semantics without a custom parser.
FanIniRead(path, section?, key?, fallback?) {
    if FanFile_Key(path) = ""
        return IniRead(path, section?, key?, fallback?)
    temp := FanFile_IniScratch(path)
    try return IniRead(temp, section?, key?, fallback?)
    finally {
        if FileExist(temp)
            FileDelete(temp)
    }
}

FanIniWrite(value, path, section, key?) {
    if FanFile_Key(path) = ""
        return IniWrite(value, path, section, key?)
    temp := FanFile_IniScratch(path)
    try {
        IniWrite(value, temp, section, key?)
        FanFile_Set(path, FileRead(temp, "UTF-16"))
    } finally {
        if FileExist(temp)
            FileDelete(temp)
    }
}

FanFile_IniScratch(path) {
    temp := Photo_TempPath("ini")
    FileAppend(FanFileExist(path) ? FanFileRead(path) : "", temp, "UTF-16")
    return temp
}

FanFile_Lines(path) => StrSplit(RTrim(FanFileRead(path), "`r`n"), "`n", "`r")

FanFile_ListNotes(folder) {
    result := []
    if FanData_Routes().Has("unified_db") {
        for row in FanState_DB().Query("SELECT path,modified_ts,length(content) AS size FROM app_file WHERE path LIKE 'data/notes/%.txt' ORDER BY path") {
            SplitPath(StrReplace(row["path"], "/", "\"), &name)
            result.Push(Map("name", name, "modified", row["modified_ts"], "size", row["size"]))
        }
    } else {
        Loop Files, folder . "\*.txt", "F"
            result.Push(Map("name", A_LoopFileName, "modified", FormatTime(A_LoopFileTimeModified, "yyyy-MM-dd HH:mm:ss"), "size", A_LoopFileSize))
    }
    return result
}

FanFile_View(path) {
    if FanFile_Key(path) = ""
        return Run(path)
    temp := Photo_TempPath("txt")
    FileAppend(FanFileRead(path), temp, "UTF-8")
    return Run(temp)
}
