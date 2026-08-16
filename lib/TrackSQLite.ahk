; ═══════════════════════════════════════════════════════════════════════════════
; TrackSQLite.ahk - Minimal, dependency-free SQLite3 wrapper for AutoHotkey v2
; ═══════════════════════════════════════════════════════════════════════════════
; Used by the MacroAutomator tracking subsystem as the persistent store.
;
; DLL RESOLUTION ORDER (no install required on Windows 10 1607+):
;   1. <script>\lib\sqlite3.dll        (user supplied, newest features)
;   2. <script>\sqlite3.dll
;   3. winsqlite3.dll                  (ships with Windows 10/11 in System32)
;   4. sqlite3.dll on the system PATH
;
; USAGE:
;   db := TrackSQLite("C:\path\tracking.db")
;   db.Exec("CREATE TABLE t(a,b)")
;   db.Run("INSERT INTO t VALUES(?,?)", "x", 1)
;   rows := db.Query("SELECT * FROM t WHERE b > ?", 0)   ; array of Maps
;   n    := db.Scalar("SELECT COUNT(*) FROM t")
;   db.Close()
;
; All strings cross the boundary as UTF-8. Statements are cached per connection
; so hot inserts (mouse/key snapshots) do not re-parse SQL on every call.
; ═══════════════════════════════════════════════════════════════════════════════

class TrackSQLite {
    ; ─── Static library state ────────────────────────────────────────────────
    static hMod := 0            ; HMODULE of the loaded sqlite library
    static pfx := ""            ; DllCall prefix, e.g. "winsqlite3\"
    static libName := ""        ; Human readable name of what got loaded
    static loadError := ""      ; Why loading failed (empty when OK)
    static triedLoad := false

    ; ─── SQLite constants ────────────────────────────────────────────────────
    static OK := 0, ROW := 100, DONE := 101
    static OPEN_READWRITE := 0x02, OPEN_CREATE := 0x04, OPEN_FULLMUTEX := 0x00010000

    ; ─── Instance state ──────────────────────────────────────────────────────
    hDb := 0
    path := ""
    lastError := ""
    stmtCache := Map()
    inTx := 0            ; transaction nesting depth (0 = none)
    _txPrevCrit := 0     ; Critical state to restore when the outermost tx ends

    ; ═══════════════════════════════════════════════════════════════════════
    ; LIBRARY LOADING
    ; ═══════════════════════════════════════════════════════════════════════

    ; Locate and load a sqlite3 implementation. Returns true on success.
    ; Safe to call repeatedly - the result is memoised.
    static EnsureLib() {
        if this.hMod
            return true
        if this.triedLoad && this.loadError != ""
            return false
        this.triedLoad := true

        candidates := [
            A_ScriptDir . "\lib\sqlite3.dll",
            A_ScriptDir . "\sqlite3.dll",
            "winsqlite3.dll",
            "sqlite3.dll"
        ]

        for cand in candidates {
            ; Skip absolute paths that do not exist so LoadLibrary does not
            ; fall back to a PATH lookup of the same bare name.
            if InStr(cand, "\") && !FileExist(cand)
                continue
            h := DllCall("LoadLibrary", "Str", cand, "Ptr")
            if !h
                continue
            ; Derive the module name DllCall uses for symbol lookup.
            SplitPath(cand, , , , &nameNoExt)
            ; Verify the module actually exports the sqlite3 API.
            if !DllCall("GetProcAddress", "Ptr", h, "AStr", "sqlite3_open_v2", "Ptr") {
                DllCall("FreeLibrary", "Ptr", h)
                continue
            }
            this.hMod := h
            this.pfx := nameNoExt . "\"
            this.libName := cand
            this.loadError := ""
            return true
        }

        this.loadError := "No SQLite library found. Expected winsqlite3.dll (Windows 10+) "
                        . "or sqlite3.dll next to the script / in lib\."
        return false
    }

    ; True when a SQLite implementation is available on this machine.
    static Available() => TrackSQLite.EnsureLib()

    ; Description of the loaded library, for status displays.
    static LibInfo() {
        if !TrackSQLite.EnsureLib()
            return "unavailable: " . TrackSQLite.loadError
        ver := ""
        try ver := StrGet(DllCall(TrackSQLite.pfx . "sqlite3_libversion", "Ptr"), "UTF-8")
        return TrackSQLite.libName . (ver != "" ? " (v" . ver . ")" : "")
    }

    ; ═══════════════════════════════════════════════════════════════════════
    ; ENCODING HELPERS
    ; ═══════════════════════════════════════════════════════════════════════

    ; Convert an AHK string into a NUL-terminated UTF-8 Buffer.
    static Utf8(str) {
        buf := Buffer(StrPut(str, "UTF-8"), 0)
        StrPut(str, buf, "UTF-8")
        return buf
    }

    ; Read a UTF-8 C string, tolerating NULL.
    static FromUtf8(ptr) => ptr ? StrGet(ptr, "UTF-8") : ""

    ; ═══════════════════════════════════════════════════════════════════════
    ; CONNECTION LIFECYCLE
    ; ═══════════════════════════════════════════════════════════════════════

    __New(dbPath) {
        if !TrackSQLite.EnsureLib()
            throw Error("SQLite unavailable: " . TrackSQLite.loadError)

        this.path := dbPath
        fnBuf := TrackSQLite.Utf8(dbPath)
        flags := TrackSQLite.OPEN_READWRITE | TrackSQLite.OPEN_CREATE | TrackSQLite.OPEN_FULLMUTEX
        rc := DllCall(TrackSQLite.pfx . "sqlite3_open_v2"
            , "Ptr", fnBuf.Ptr
            , "Ptr*", &hDb := 0
            , "Int", flags
            , "Ptr", 0
            , "Int")
        this.hDb := hDb
        if (rc != TrackSQLite.OK) {
            msg := this.ErrMsg()
            if this.hDb
                DllCall(TrackSQLite.pfx . "sqlite3_close_v2", "Ptr", this.hDb)
            this.hDb := 0
            throw Error("Cannot open database '" . dbPath . "': " . msg)
        }

        ; Wait rather than fail when another handle holds the write lock.
        DllCall(TrackSQLite.pfx . "sqlite3_busy_timeout", "Ptr", this.hDb, "Int", 5000)

        ; WAL keeps the background trackers from blocking the UI thread's reads.
        try this.Exec("PRAGMA journal_mode=WAL")
        try this.Exec("PRAGMA synchronous=NORMAL")
        try this.Exec("PRAGMA foreign_keys=ON")
        try this.Exec("PRAGMA temp_store=MEMORY")
    }

    __Delete() {
        this.Close()
    }

    Close() {
        if !this.hDb
            return
        for sql, st in this.stmtCache
            try DllCall(TrackSQLite.pfx . "sqlite3_finalize", "Ptr", st)
        this.stmtCache := Map()
        DllCall(TrackSQLite.pfx . "sqlite3_close_v2", "Ptr", this.hDb)
        this.hDb := 0
    }

    IsOpen() => this.hDb != 0

    ErrMsg() {
        if !this.hDb
            return "database not open"
        return TrackSQLite.FromUtf8(DllCall(TrackSQLite.pfx . "sqlite3_errmsg", "Ptr", this.hDb, "Ptr"))
    }

    ; ═══════════════════════════════════════════════════════════════════════
    ; STATEMENT HANDLING
    ; ═══════════════════════════════════════════════════════════════════════

    ; Compile a statement, reusing a cached handle when the SQL repeats.
    ; Returns a sqlite3_stmt* reset and ready for binding.
    _Prepare(sql, cache := true) {
        if !this.hDb
            throw Error("Database is not open")

        if cache && this.stmtCache.Has(sql) {
            st := this.stmtCache[sql]
            DllCall(TrackSQLite.pfx . "sqlite3_reset", "Ptr", st)
            DllCall(TrackSQLite.pfx . "sqlite3_clear_bindings", "Ptr", st)
            return st
        }

        sqlBuf := TrackSQLite.Utf8(sql)
        rc := DllCall(TrackSQLite.pfx . "sqlite3_prepare_v2"
            , "Ptr", this.hDb
            , "Ptr", sqlBuf.Ptr
            , "Int", -1
            , "Ptr*", &st := 0
            , "Ptr", 0
            , "Int")
        if (rc != TrackSQLite.OK || !st)
            throw Error("SQL prepare failed: " . this.ErrMsg() . "`n`nSQL: " . SubStr(sql, 1, 400))

        if cache
            this.stmtCache[sql] := st
        return st
    }

    ; Bind a positional parameter. AHK types map onto SQLite storage classes:
    ;   ""            -> NULL      (use TrackSQLite.Null() semantics via unset)
    ;   Integer       -> INTEGER
    ;   Float         -> REAL
    ;   everything else -> TEXT
    _Bind(st, idx, val) {
        if (val == "" && !IsNumber(val)) {
            DllCall(TrackSQLite.pfx . "sqlite3_bind_text", "Ptr", st, "Int", idx
                , "Ptr", 0, "Int", 0, "Ptr", -1)
            return
        }
        if IsInteger(val) {
            DllCall(TrackSQLite.pfx . "sqlite3_bind_int64", "Ptr", st, "Int", idx
                , "Int64", Integer(val))
            return
        }
        if IsFloat(val) {
            DllCall(TrackSQLite.pfx . "sqlite3_bind_double", "Ptr", st, "Int", idx
                , "Double", Float(val))
            return
        }
        buf := TrackSQLite.Utf8(String(val))
        ; SQLITE_TRANSIENT (-1) makes SQLite copy before the buffer dies.
        DllCall(TrackSQLite.pfx . "sqlite3_bind_text", "Ptr", st, "Int", idx
            , "Ptr", buf.Ptr, "Int", -1, "Ptr", -1)
    }

    _BindAll(st, params) {
        for i, v in params
            this._Bind(st, i, v)
    }

    ; Read the current row of a stepped statement into a Map keyed by column name.
    _RowMap(st) {
        row := Map()
        cols := DllCall(TrackSQLite.pfx . "sqlite3_column_count", "Ptr", st, "Int")
        Loop cols {
            i := A_Index - 1
            name := TrackSQLite.FromUtf8(DllCall(TrackSQLite.pfx . "sqlite3_column_name"
                , "Ptr", st, "Int", i, "Ptr"))
            row[name] := this._ColValue(st, i)
        }
        return row
    }

    _ColValue(st, i) {
        type := DllCall(TrackSQLite.pfx . "sqlite3_column_type", "Ptr", st, "Int", i, "Int")
        switch type {
            case 1:  ; SQLITE_INTEGER
                return DllCall(TrackSQLite.pfx . "sqlite3_column_int64", "Ptr", st, "Int", i, "Int64")
            case 2:  ; SQLITE_FLOAT
                return DllCall(TrackSQLite.pfx . "sqlite3_column_double", "Ptr", st, "Int", i, "Double")
            case 5:  ; SQLITE_NULL
                return ""
            default: ; TEXT / BLOB - surfaced as text
                return TrackSQLite.FromUtf8(DllCall(TrackSQLite.pfx . "sqlite3_column_text"
                    , "Ptr", st, "Int", i, "Ptr"))
        }
    }

    ; ═══════════════════════════════════════════════════════════════════════
    ; PUBLIC QUERY API
    ; ═══════════════════════════════════════════════════════════════════════

    ; ─── Reentrancy ─────────────────────────────────────────────────────────
    ; The trackers run on timers (mouse at 20Hz, window poll, key/snapshot
    ; flushes) and all share this one connection. AHK timers can interrupt a
    ; running thread between lines, so without a guard a mouse-flush could
    ; interrupt a window-poll mid-statement and reset a cached statement handle
    ; out from under it. Each statement-executing method runs Critical so it
    ; completes atomically; the previous state is always restored via `finally`.

    ; Execute one or more statements with no parameters and no result rows.
    ; Accepts multi-statement scripts (schema DDL).
    Exec(sql) {
        if !this.hDb
            throw Error("Database is not open")
        prevCrit := A_IsCritical
        Critical("On")
        try {
            sqlBuf := TrackSQLite.Utf8(sql)
            rc := DllCall(TrackSQLite.pfx . "sqlite3_exec"
                , "Ptr", this.hDb
                , "Ptr", sqlBuf.Ptr
                , "Ptr", 0
                , "Ptr", 0
                , "Ptr*", &errPtr := 0
                , "Int")
            if (rc != TrackSQLite.OK) {
                msg := errPtr ? TrackSQLite.FromUtf8(errPtr) : this.ErrMsg()
                if errPtr
                    DllCall(TrackSQLite.pfx . "sqlite3_free", "Ptr", errPtr)
                throw Error("SQL exec failed: " . msg . "`n`nSQL: " . SubStr(sql, 1, 400))
            }
            return true
        } finally {
            Critical(prevCrit)
        }
    }

    ; Execute a parameterised statement that returns no rows.
    ; Returns the number of rows changed.
    Run(sql, params*) {
        prevCrit := A_IsCritical
        Critical("On")
        try {
            st := this._Prepare(sql)
            this._BindAll(st, params)
            rc := DllCall(TrackSQLite.pfx . "sqlite3_step", "Ptr", st, "Int")
            if (rc != TrackSQLite.DONE && rc != TrackSQLite.ROW) {
                msg := this.ErrMsg()
                DllCall(TrackSQLite.pfx . "sqlite3_reset", "Ptr", st)
                throw Error("SQL run failed: " . msg . "`n`nSQL: " . SubStr(sql, 1, 400))
            }
            DllCall(TrackSQLite.pfx . "sqlite3_reset", "Ptr", st)
            return this.Changes()
        } finally {
            Critical(prevCrit)
        }
    }

    ; Execute a query and return every row as an array of Maps.
    Query(sql, params*) {
        prevCrit := A_IsCritical
        Critical("On")
        try {
            st := this._Prepare(sql)
            this._BindAll(st, params)
            rows := []
            loop {
                rc := DllCall(TrackSQLite.pfx . "sqlite3_step", "Ptr", st, "Int")
                if (rc = TrackSQLite.ROW) {
                    rows.Push(this._RowMap(st))
                    continue
                }
                if (rc = TrackSQLite.DONE)
                    break
                msg := this.ErrMsg()
                DllCall(TrackSQLite.pfx . "sqlite3_reset", "Ptr", st)
                throw Error("SQL query failed: " . msg . "`n`nSQL: " . SubStr(sql, 1, 400))
            }
            DllCall(TrackSQLite.pfx . "sqlite3_reset", "Ptr", st)
            return rows
        } finally {
            Critical(prevCrit)
        }
    }

    ; First column of the first row, or "" when there are no rows.
    Scalar(sql, params*) {
        prevCrit := A_IsCritical
        Critical("On")
        try {
            st := this._Prepare(sql)
            this._BindAll(st, params)
            val := ""
            rc := DllCall(TrackSQLite.pfx . "sqlite3_step", "Ptr", st, "Int")
            if (rc = TrackSQLite.ROW)
                val := this._ColValue(st, 0)
            DllCall(TrackSQLite.pfx . "sqlite3_reset", "Ptr", st)
            return val
        } finally {
            Critical(prevCrit)
        }
    }

    ; First row as a Map, or an empty Map when there are no rows.
    QueryRow(sql, params*) {
        rows := this.Query(sql, params*)
        return rows.Length ? rows[1] : Map()
    }

    ; Flat array of the first column across all rows.
    Column(sql, params*) {
        out := []
        for r in this.Query(sql, params*) {
            for k, v in r {
                out.Push(v)
                break
            }
        }
        return out
    }

    LastInsertId() => DllCall(TrackSQLite.pfx . "sqlite3_last_insert_rowid", "Ptr", this.hDb, "Int64")

    Changes() => DllCall(TrackSQLite.pfx . "sqlite3_changes", "Ptr", this.hDb, "Int")

    ; ═══════════════════════════════════════════════════════════════════════
    ; TRANSACTIONS
    ; ═══════════════════════════════════════════════════════════════════════

    ; Transactions hold Critical for their whole span so a timer cannot
    ; interrupt between statements and start a conflicting transaction on this
    ; shared connection. Nested Begin/Commit calls are reference-counted; only
    ; the outermost pair issues real BEGIN/COMMIT and toggles Critical.
    Begin() {
        if this.inTx {
            this.inTx += 1
            return true
        }
        this._txPrevCrit := A_IsCritical
        Critical("On")
        try {
            this.Exec("BEGIN IMMEDIATE")
        } catch {
            Critical(this._txPrevCrit)
            return false
        }
        this.inTx := 1
        return true
    }

    Commit() {
        if (this.inTx > 1) {
            this.inTx -= 1
            return true
        }
        if !this.inTx
            return false
        ok := true
        try this.Exec("COMMIT")
        catch
            ok := false
        this.inTx := 0
        Critical(this._txPrevCrit)   ; release the transaction-wide Critical
        return ok
    }

    Rollback() {
        ; Outside any tracked transaction: best-effort rollback.
        if !this.inTx {
            try this.Exec("ROLLBACK")
            catch
                return false
            return true
        }
        ; Unwind inner scopes to the outermost, which performs the real rollback.
        if (this.inTx > 1) {
            this.inTx -= 1
            return true
        }
        ok := true
        try this.Exec("ROLLBACK")
        catch
            ok := false
        this.inTx := 0
        Critical(this._txPrevCrit)
        return ok
    }

    ; Run `fn` inside a transaction, rolling back if it throws.
    ; fn receives this database instance.
    Transact(fn) {
        this.Begin()
        try {
            result := fn(this)
        } catch as err {
            this.Rollback()
            throw err
        }
        this.Commit()
        return result
    }

    ; ═══════════════════════════════════════════════════════════════════════
    ; UTILITIES
    ; ═══════════════════════════════════════════════════════════════════════

    ; True when a table exists in the main schema.
    TableExists(name) {
        return this.Scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?", name) > 0
    }

    ; True when a column exists on a table (used by the migration helper).
    ColumnExists(table, column) {
        for r in this.Query("PRAGMA table_info(" . table . ")") {
            if (r.Has("name") && r["name"] = column)
                return true
        }
        return false
    }

    ; Add a column only when it is missing - lets the schema evolve without
    ; destroying existing tracking history.
    AddColumnIfMissing(table, column, decl) {
        if this.ColumnExists(table, column)
            return false
        this.Exec("ALTER TABLE " . table . " ADD COLUMN " . column . " " . decl)
        return true
    }

    ; Reclaim space and rebuild indexes.
    Vacuum() {
        try this.Exec("VACUUM")
    }

    ; Bytes on disk for the database file (including WAL sidecar).
    FileSize() {
        total := 0
        for suffix in ["", "-wal", "-shm"] {
            p := this.path . suffix
            if FileExist(p) {
                try total += FileGetSize(p)
            }
        }
        return total
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; SQL LITERAL ESCAPING (for the rare case a value cannot be parameterised,
; e.g. dynamic IN-lists built from validated integers)
; ═══════════════════════════════════════════════════════════════════════════════
SqlQuote(value) {
    return "'" . StrReplace(String(value), "'", "''") . "'"
}

; Join an array of integers into a safe SQL IN-list body ("1,2,3").
; Non-integers are dropped rather than interpolated.
SqlIntList(arr) {
    parts := []
    for v in arr {
        if IsInteger(v)
            parts.Push(Integer(v))
    }
    return parts.Length ? SqlJoin(parts, ",") : "NULL"
}

SqlJoin(arr, sep) {
    out := ""
    for i, v in arr
        out .= (i > 1 ? sep : "") . v
    return out
}
