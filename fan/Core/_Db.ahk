; ===============================================================================
; Core\_Db.ahk
; Database: SQLite open/migrate, patterns/sequences/spools persistence, SaveAll/LoadAll
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================


; ═══════════════════════════════════════════════════════════════════════════════
; SQLITE PERSISTENCE (patterns, sequences, spools, OCR log)
; ═══════════════════════════════════════════════════════════════════════════════

InitDB() {
    global g_DB, DB_FILE, DATA_DIR

    if !DirExist(DATA_DIR)
        DirCreate(DATA_DIR)

    g_DB := SQLiteDB()
    if !g_DB.OpenDB(DB_FILE) {
        MsgBoxTop("Failed to open database:`n" . g_DB.ErrorMsg . "`n`nData will not be saved this session.", "Database Error")
        return
    }

    if !g_DB.Exec("CREATE TABLE IF NOT EXISTS patterns (name TEXT PRIMARY KEY, text TEXT, desc TEXT, screenshot TEXT, captureX INTEGER, captureY INTEGER, captureWindow TEXT, qualifier TEXT);")
        MsgBoxTop("Failed to create patterns table:`n" . g_DB.ErrorMsg, "Database Error")
    if !g_DB.Exec("CREATE TABLE IF NOT EXISTS sequences (name TEXT PRIMARY KEY, speed REAL);")
        MsgBoxTop("Failed to create sequences table:`n" . g_DB.ErrorMsg, "Database Error")
    if !g_DB.Exec("CREATE TABLE IF NOT EXISTS sequence_steps (seq_name TEXT, step_index INTEGER, action TEXT, target TEXT, param TEXT, enabled INTEGER, failsafe TEXT, PRIMARY KEY (seq_name, step_index));")
        MsgBoxTop("Failed to create sequence_steps table:`n" . g_DB.ErrorMsg, "Database Error")
    if !g_DB.Exec("CREATE TABLE IF NOT EXISTS spools (name TEXT PRIMARY KEY, enabled INTEGER, region TEXT, regionCoords TEXT, detectType TEXT, target TEXT, interval INTEGER, condition TEXT, action TEXT, actionTarget TEXT, extractOCR INTEGER, ocrVar TEXT, autoComplete INTEGER, completion TEXT, completionTarget TEXT, timeout INTEGER, mode TEXT, cooldown INTEGER, notifTime INTEGER);")
        MsgBoxTop("Failed to create spools table:`n" . g_DB.ErrorMsg, "Database Error")
    if !g_DB.Exec("CREATE TABLE IF NOT EXISTS ocr_log (id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT, text TEXT, word_count INTEGER);")
        MsgBoxTop("Failed to create ocr_log table:`n" . g_DB.ErrorMsg, "Database Error")

    ; Migrate older databases without discarding any saved workflows.
    EnsureDBColumn("sequences", "hotkey", "TEXT")
    EnsureDBColumn("sequences", "hotstring", "TEXT")
    EnsureDBColumn("sequence_steps", "qual_pattern", "TEXT")
    EnsureDBColumn("sequence_steps", "qual_window", "TEXT")

    ; One-time import from legacy .ini files if the DB tables are still empty,
    ; so existing pattern/sequence/spool data isn't lost on upgrade.
    ImportLegacyIniIfEmpty()
}

; Escapes a value for safe inline use in a single-quoted SQLite string literal.
SQLQuote2(val) {
    return "'" . StrReplace(String(val), "'", "''") . "'"
}

EnsureDBColumn(tableName, columnName, columnDefinition) {
    global g_DB
    if !IsObject(g_DB)
        return false
    if !g_DB.GetTable("PRAGMA table_info(" . tableName . ");", &tb)
        return false
    row := ""
    Loop tb.RowCount {
        tb.GetRow(A_Index, &row)
        if row[2] = columnName
            return true
    }
    if !g_DB.Exec("ALTER TABLE " . tableName . " ADD COLUMN " . columnName . " " . columnDefinition . ";") {
        MsgBoxTop("Failed to update database column " . tableName . "." . columnName . ":`n" . g_DB.ErrorMsg, "Database Migration Error")
        return false
    }
    return true
}

ImportLegacyIniIfEmpty() {
    global g_DB, PATTERNS_FILE, SEQUENCES_FILE, SPOOLS_FILE

    if !IsObject(g_DB)
        return

    patternCount := 0
    if g_DB.GetTable("SELECT COUNT(*) FROM patterns;", &tb) && tb.RowCount
        patternCount := Integer(tb.Rows[1][1])
    if patternCount = 0 && FileExist(PATTERNS_FILE) {
        for section in StrSplit(IniRead(PATTERNS_FILE), "`n") {
            if section = ""
                continue
            text := IniRead(PATTERNS_FILE, section, "Text", "")
            if text = ""
                continue
            g_DB.Exec("INSERT OR REPLACE INTO patterns (name, text, desc, screenshot, captureX, captureY, captureWindow, qualifier) VALUES ("
                . SQLQuote(section) . ", " . SQLQuote(text) . ", "
                . SQLQuote(IniRead(PATTERNS_FILE, section, "Desc", "")) . ", "
                . SQLQuote(IniRead(PATTERNS_FILE, section, "Screenshot", "")) . ", "
                . Integer(IniRead(PATTERNS_FILE, section, "CaptureX", 0)) . ", "
                . Integer(IniRead(PATTERNS_FILE, section, "CaptureY", 0)) . ", "
                . SQLQuote(IniRead(PATTERNS_FILE, section, "CaptureWindow", "")) . ", "
                . SQLQuote(IniRead(PATTERNS_FILE, section, "Qualifier", "")) . ");")
        }
    }

    seqCount := 0
    if g_DB.GetTable("SELECT COUNT(*) FROM sequences;", &tb) && tb.RowCount
        seqCount := Integer(tb.Rows[1][1])
    if seqCount = 0 && FileExist(SEQUENCES_FILE) {
        for section in StrSplit(IniRead(SEQUENCES_FILE), "`n") {
            if section = ""
                continue
            count := IniRead(SEQUENCES_FILE, section, "_Count", 0)
            if count = 0
                continue
            speed := IniRead(SEQUENCES_FILE, section, "_Speed", 1.0)
            g_DB.Exec("INSERT OR REPLACE INTO sequences (name, speed) VALUES (" . SQLQuote(section) . ", " . Float(speed) . ");")
            Loop count {
                data := IniRead(SEQUENCES_FILE, section, "Step" . A_Index, "")
                if data = ""
                    continue
                p := StrSplit(data, "|")
                fsData := IniRead(SEQUENCES_FILE, section, "Failsafe" . A_Index, "")
                g_DB.Exec("INSERT OR REPLACE INTO sequence_steps (seq_name, step_index, action, target, param, enabled, failsafe) VALUES ("
                    . SQLQuote(section) . ", " . A_Index . ", "
                    . SQLQuote(p[1]) . ", " . SQLQuote(p.Length >= 2 ? p[2] : "") . ", " . SQLQuote(p.Length >= 3 ? p[3] : "") . ", "
                    . (p.Length >= 4 ? Integer(p[4]) : 1) . ", " . SQLQuote(fsData) . ");")
            }
        }
    }

    spoolCount := 0
    if g_DB.GetTable("SELECT COUNT(*) FROM spools;", &tb) && tb.RowCount
        spoolCount := Integer(tb.Rows[1][1])
    if spoolCount = 0 && FileExist(SPOOLS_FILE) {
        for section in StrSplit(IniRead(SPOOLS_FILE), "`n") {
            if section = ""
                continue
            g_DB.Exec("INSERT OR REPLACE INTO spools (name, enabled, region, regionCoords, detectType, target, interval, condition, action, actionTarget, extractOCR, ocrVar, autoComplete, completion, completionTarget, timeout, mode, cooldown, notifTime) VALUES ("
                . SQLQuote(section) . ", "
                . Integer(IniRead(SPOOLS_FILE, section, "Enabled", 1)) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "Region", "Full Screen")) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "RegionCoords", "")) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "DetectType", "Pattern Match")) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "Target", "")) . ", "
                . Integer(IniRead(SPOOLS_FILE, section, "Interval", 500)) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "Condition", "Found")) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "Action", "Show Notification")) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "ActionTarget", "")) . ", "
                . Integer(IniRead(SPOOLS_FILE, section, "ExtractOCR", 0)) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "OCRVar", "")) . ", "
                . Integer(IniRead(SPOOLS_FILE, section, "AutoComplete", 0)) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "Completion", "Pattern Found")) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "CompletionTarget", "")) . ", "
                . Integer(IniRead(SPOOLS_FILE, section, "Timeout", 0)) . ", "
                . SQLQuote(IniRead(SPOOLS_FILE, section, "Mode", "Continuous")) . ", "
                . Integer(IniRead(SPOOLS_FILE, section, "Cooldown", 5)) . ", "
                . Integer(IniRead(SPOOLS_FILE, section, "NotifTime", 5)) . ");")
        }
    }
}

SavePatterns() {
    global g_Patterns, g_DB
    if !IsObject(g_DB)
        return
    g_DB.Exec("DELETE FROM patterns;")
    for name, data in g_Patterns {
        g_DB.Exec("INSERT OR REPLACE INTO patterns (name, text, desc, screenshot, captureX, captureY, captureWindow, qualifier) VALUES ("
            . SQLQuote(name) . ", "
            . SQLQuote(data["text"]) . ", "
            . SQLQuote(data.Has("desc") ? data["desc"] : "") . ", "
            . SQLQuote(data.Has("screenshot") ? data["screenshot"] : "") . ", "
            . Integer(data.Has("captureX") ? data["captureX"] : 0) . ", "
            . Integer(data.Has("captureY") ? data["captureY"] : 0) . ", "
            . SQLQuote(data.Has("captureWindow") ? data["captureWindow"] : "") . ", "
            . SQLQuote(data.Has("qualifier") ? data["qualifier"] : "") . ");")
    }
}

LoadPatterns() {
    global g_Patterns, g_DB
    g_Patterns := Map()
    if !IsObject(g_DB)
        return
    if !g_DB.GetTable("SELECT name, text, desc, screenshot, captureX, captureY, captureWindow, qualifier FROM patterns;", &tb)
        return
    row := ""
    Loop tb.RowCount {
        tb.GetRow(A_Index, &row)
        if row[2] != ""
            g_Patterns[row[1]] := Map(
                "text", row[2],
                "desc", row[3],
                "screenshot", row[4],
                "captureX", Integer(row[5]),
                "captureY", Integer(row[6]),
                "captureWindow", row[7],
                "qualifier", row[8]
            )
    }
}

SaveSequences(showError := false) {
    global g_Sequences, g_DB, g_LastWorkflowSaveError
    g_LastWorkflowSaveError := ""
    if !IsObject(g_DB) {
        g_LastWorkflowSaveError := "The workflow database is not open."
        return false
    }

    try {
        DBExecOrThrow("BEGIN IMMEDIATE;")
        ; Delete children first. The transaction guarantees the old data survives
        ; if any serialization or insert fails.
        DBExecOrThrow("DELETE FROM sequence_steps;")
        DBExecOrThrow("DELETE FROM sequences;")

        for seqName, seqData in g_Sequences {
            speed := seqData.Has("speed") ? seqData["speed"] : 1.0
            hotkey := seqData.Has("hotkey") ? seqData["hotkey"] : ""
            hotstring := seqData.Has("hotstring") ? seqData["hotstring"] : ""
            DBExecOrThrow("INSERT INTO sequences (name, speed, hotkey, hotstring) VALUES ("
                . SQLQuote(seqName) . ", " . Float(speed) . ", " . SQLQuote(hotkey) . ", " . SQLQuote(hotstring) . ");")

            steps := seqData.Has("steps") ? seqData["steps"] : []
            for i, step in steps {
                fs := step.Has("failsafe") ? NormalizeStepFailsafe(step["failsafe"]) : Map()
                fsStr := fs.Count > 0 ? SerializeFailsafe(fs) : ""
                qualPattern := step.Has("qualPattern") ? step["qualPattern"] : ""
                qualWindow := step.Has("qualWindow") ? step["qualWindow"] : ""
                DBExecOrThrow("INSERT INTO sequence_steps (seq_name, step_index, action, target, param, enabled, failsafe, qual_pattern, qual_window) VALUES ("
                    . SQLQuote(seqName) . ", " . i . ", "
                    . SQLQuote(step.Has("action") ? step["action"] : "") . ", "
                    . SQLQuote(step.Has("target") ? step["target"] : "") . ", "
                    . SQLQuote(step.Has("param") ? step["param"] : "") . ", "
                    . (step.Has("enabled") ? Integer(step["enabled"]) : 1) . ", "
                    . SQLQuote(fsStr) . ", " . SQLQuote(qualPattern) . ", " . SQLQuote(qualWindow) . ");")
            }
        }
        DBExecOrThrow("COMMIT;")
        return true
    } catch as err {
        try g_DB.Exec("ROLLBACK;")
        g_LastWorkflowSaveError := err.Message
        if showError
            MsgBoxTop("Workflows could not be saved. Your previous database contents were kept intact.`n`n" . err.Message, "Workflow Save Error")
        return false
    }
}

DBExecOrThrow(sql) {
    global g_DB
    if !g_DB.Exec(sql)
        throw Error(g_DB.ErrorMsg != "" ? g_DB.ErrorMsg : "SQLite operation failed.")
}

; Serialize failsafe map to string
SerializeFailsafe(fs) {
    parts := []
    for key, val in fs {
        if val != "" && val != 0
            parts.Push(key . "=" . String(val))
    }
    return StrJoin(parts, ";")
}

; Deserialize failsafe string to map
DeserializeFailsafe(str) {
    fs := Map()
    if str = ""
        return fs
    for part in StrSplit(str, ";") {
        eq := InStr(part, "=")
        if eq > 0 {
            key := SubStr(part, 1, eq - 1)
            val := SubStr(part, eq + 1)
            ; Try to convert to number
            if IsNumber(val)
                fs[key] := Number(val)
            else
                fs[key] := val
        }
    }
    return fs
}

NormalizeStepFailsafe(value) {
    if value is Map
        return value
    if Type(value) = "String" {
        if value = "close_button"
            return Map("checkCloseBtn", 1)
        return DeserializeFailsafe(value)
    }
    return Map()
}

LoadSequences() {
    global g_Sequences, g_DB
    g_Sequences := Map()
    if !IsObject(g_DB)
        return
    if !g_DB.GetTable("SELECT name, speed, hotkey, hotstring FROM sequences ORDER BY name;", &tbSeq)
        return
    row := ""
    Loop tbSeq.RowCount {
        tbSeq.GetRow(A_Index, &row)
        seqName := row[1]
        speed := row[2]
        steps := []
        if g_DB.GetTable("SELECT action, target, param, enabled, failsafe, qual_pattern, qual_window FROM sequence_steps WHERE seq_name = " . SQLQuote(seqName) . " ORDER BY step_index;", &tbSteps) {
            stepRow := ""
            Loop tbSteps.RowCount {
                tbSteps.GetRow(A_Index, &stepRow)
                step := Map("action", stepRow[1], "target", stepRow[2], "param", stepRow[3], "enabled", Integer(stepRow[4]))
                if stepRow[5] != ""
                    step["failsafe"] := DeserializeFailsafe(stepRow[5])
                if stepRow[6] != ""
                    step["qualPattern"] := stepRow[6]
                if stepRow[7] != ""
                    step["qualWindow"] := stepRow[7]
                steps.Push(step)
            }
        }
        seqData := Map("steps", steps, "speed", Float(speed))
        if row[3] != ""
            seqData["hotkey"] := row[3]
        if row[4] != ""
            seqData["hotstring"] := row[4]
        g_Sequences[seqName] := seqData
    }
}


; ═══════════════════════════════════════════════════════════════════════════════
; SPOOL SYSTEM - EVENT-DRIVEN AUTOMATION
; ═══════════════════════════════════════════════════════════════════════════════
; SPOOL SYSTEM - Event-Driven Automation

; ═══════════════════════════════════════════════════════════════════════════════
; SPOOLS CONTINUOUSLY MONITOR SCREEN REGIONS AND TRIGGER WORKFLOWS/ACTIONS
; ═══════════════════════════════════════════════════════════════════════════════
; Spools continuously monitor screen regions and trigger workflows/actions
; when specific conditions are detected (patterns, OCR text, pixel changes)

SaveSpools() {
    global g_Spools, g_DB
    if !IsObject(g_DB)
        return
    g_DB.Exec("DELETE FROM spools;")
    for name, spool in g_Spools {
        g_DB.Exec("INSERT OR REPLACE INTO spools (name, enabled, region, regionCoords, detectType, target, interval, condition, action, actionTarget, extractOCR, ocrVar, autoComplete, completion, completionTarget, timeout, mode, cooldown, notifTime) VALUES ("
            . SQLQuote(name) . ", "
            . Integer(spool["enabled"]) . ", "
            . SQLQuote(spool["region"]) . ", "
            . SQLQuote(spool["regionCoords"]) . ", "
            . SQLQuote(spool["detectType"]) . ", "
            . SQLQuote(spool["target"]) . ", "
            . Integer(spool["interval"]) . ", "
            . SQLQuote(spool["condition"]) . ", "
            . SQLQuote(spool["action"]) . ", "
            . SQLQuote(spool["actionTarget"]) . ", "
            . Integer(spool["extractOCR"]) . ", "
            . SQLQuote(spool["ocrVar"]) . ", "
            . Integer(spool["autoComplete"]) . ", "
            . SQLQuote(spool["completion"]) . ", "
            . SQLQuote(spool["completionTarget"]) . ", "
            . Integer(spool["timeout"]) . ", "
            . SQLQuote(spool.Has("mode") ? spool["mode"] : "Continuous") . ", "
            . Integer(spool.Has("cooldown") ? spool["cooldown"] : 5) . ", "
            . Integer(spool.Has("notifTime") ? spool["notifTime"] : 5) . ");")
    }
}

LoadSpools() {
    global g_Spools, g_DB
    g_Spools := Map()
    if !IsObject(g_DB)
        return
    if !g_DB.GetTable("SELECT name, enabled, region, regionCoords, detectType, target, interval, condition, action, actionTarget, extractOCR, ocrVar, autoComplete, completion, completionTarget, timeout, mode, cooldown, notifTime FROM spools;", &tb)
        return
    row := ""
    Loop tb.RowCount {
        tb.GetRow(A_Index, &row)
        g_Spools[row[1]] := Map(
            "enabled", Integer(row[2]),
            "region", row[3],
            "regionCoords", row[4],
            "detectType", row[5],
            "target", row[6],
            "interval", Integer(row[7]),
            "condition", row[8],
            "action", row[9],
            "actionTarget", row[10],
            "extractOCR", Integer(row[11]),
            "ocrVar", row[12],
            "autoComplete", Integer(row[13]),
            "completion", row[14],
            "completionTarget", row[15],
            "timeout", Integer(row[16]),
            "mode", row[17],
            "cooldown", Integer(row[18]),
            "notifTime", Integer(row[19])
        )
    }
}


SaveAll() {
    SaveCoordinates()
    SavePatterns()
    SaveSequences()
    SaveSpools()
    SaveHotkeys()
    SaveSettings()
    SaveExtractionRules()
}

; Registered via OnExit so in-progress edits are never lost just by closing the window.
SaveAllOnExit(ExitReason, ExitCode) {
    global g_DB
    try AutoSaveCurrentWorkflow()
    try SaveAll()
    if IsObject(g_DB)
        g_DB.CloseDB()
    return 0
}


LoadAll() {
    LoadCoordinates()
    LoadPatterns()
    LoadSequences()
    LoadHotkeys()
    LoadSettings()
    LoadExtractionRules()
    LoadHotstrings()
    LoadNotificationTriggers()
    StartNotificationTimer()
    InitializeParameterValidators()
    InitializeActionTemplates()

    ; Apply notification settings from saved settings
    global g_DebugMode, g_NotificationDismissible, g_NotificationTimeout
    if g_Settings.Has("DebugMode")
        g_DebugMode := g_Settings["DebugMode"]
    if g_Settings.Has("NotificationDismissible")
        g_NotificationDismissible := g_Settings["NotificationDismissible"]
    if g_Settings.Has("NotificationTimeout")
        g_NotificationTimeout := Integer(g_Settings["NotificationTimeout"]) * 1000

    ; Register all sequence hotkeys/hotstrings
    RegisterAllSequenceTriggers()
}

