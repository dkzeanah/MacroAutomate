#Requires AutoHotkey v2.0
#SingleInstance Force
#Include SQLiteDB.ahk

; AutoHotkey parses the complete file before executing this parse-only guard.
if (A_Args.Length && A_Args[1] = "validate")
    ExitApp()
global SmokeTestMode := A_Args.Length && A_Args[1] = "smoketest"
if SmokeTestMode
    FileAppend("smoke:auto-execute`n", "*")

; ============================================================================
; Manager v7 - compact Explorer project manager, launcher, Script Hub, and
; console command menu.  AutoHotkey v2.0 only.
;
; Hotkeys
;   Ctrl+Alt+E       Show the manager
;   Ctrl+Win+A       Show the integrated Script Hub view
;   Ctrl+Alt+Space   Show the console command menu
;
; Persistent data is stored in data\Managerv7.sqlite through SQLiteDB.ahk.
; ============================================================================

Persistent()
DetectHiddenWindows(true)
SetTitleMatchMode(2)
SendMode("Input")
SetWorkingDir(A_ScriptDir)

class ManagerStore {
    __New(path) {
        SmokeLog("store:start")
        SplitPath(path, , &folder)
        if !DirExist(folder)
            DirCreate(folder)

        this.Path := path
        this.DB := SQLiteDB()
        if !this.DB.OpenDB(path, "W", true)
            throw Error("Could not open Manager v7 database.`n`n" this.DB.ErrorMsg)
        this.DB.SetTimeout(3000)
        this.CreateSchema()
        SmokeLog("store:ready")
    }

    CreateSchema() {
        sql := "PRAGMA journal_mode=WAL;"
            . "PRAGMA synchronous=NORMAL;"
            . "PRAGMA foreign_keys=ON;"
            . "CREATE TABLE IF NOT EXISTS folder_stats ("
            . " path TEXT PRIMARY KEY COLLATE NOCASE,"
            . " display_name TEXT NOT NULL DEFAULT '',"
            . " visit_count INTEGER NOT NULL DEFAULT 0,"
            . " total_seconds INTEGER NOT NULL DEFAULT 0,"
            . " last_visit TEXT NOT NULL DEFAULT '',"
            . " last_source TEXT NOT NULL DEFAULT '',"
            . " last_folder TEXT NOT NULL DEFAULT '',"
            . " favorite INTEGER NOT NULL DEFAULT 0"
            . ");"
            . "CREATE TABLE IF NOT EXISTS folder_sessions ("
            . " id INTEGER PRIMARY KEY, project_path TEXT NOT NULL,"
            . " folder_path TEXT NOT NULL, started_at TEXT NOT NULL,"
            . " ended_at TEXT NOT NULL, seconds INTEGER NOT NULL DEFAULT 0,"
            . " source TEXT NOT NULL DEFAULT 'Explorer', hwnd INTEGER NOT NULL DEFAULT 0"
            . ");"
            . "CREATE INDEX IF NOT EXISTS idx_folder_sessions_project ON folder_sessions(project_path);"
            . "CREATE TABLE IF NOT EXISTS file_stats ("
            . " path TEXT PRIMARY KEY COLLATE NOCASE, kind TEXT NOT NULL DEFAULT 'file',"
            . " use_count INTEGER NOT NULL DEFAULT 0, first_seen TEXT NOT NULL DEFAULT '',"
            . " last_used TEXT NOT NULL DEFAULT '', favorite INTEGER NOT NULL DEFAULT 0,"
            . " always_start INTEGER NOT NULL DEFAULT 0, tags TEXT NOT NULL DEFAULT '',"
            . " notes TEXT NOT NULL DEFAULT '', removed INTEGER NOT NULL DEFAULT 0"
            . ");"
            . "CREATE TABLE IF NOT EXISTS launch_events ("
            . " id INTEGER PRIMARY KEY, path TEXT NOT NULL, kind TEXT NOT NULL,"
            . " action TEXT NOT NULL, used_at TEXT NOT NULL, pid INTEGER NOT NULL DEFAULT 0"
            . ");"
            . "CREATE INDEX IF NOT EXISTS idx_launch_events_path ON launch_events(path);"
            . "CREATE TABLE IF NOT EXISTS running_snapshot ("
            . " path TEXT PRIMARY KEY COLLATE NOCASE, instance_count INTEGER NOT NULL DEFAULT 1"
            . ");"
            . "CREATE TABLE IF NOT EXISTS custom_commands ("
            . " id INTEGER PRIMARY KEY, label TEXT NOT NULL, command TEXT NOT NULL,"
            . " use_count INTEGER NOT NULL DEFAULT 0, last_used TEXT NOT NULL DEFAULT ''"
            . ");"
            . "CREATE TABLE IF NOT EXISTS command_history ("
            . " command TEXT PRIMARY KEY, use_count INTEGER NOT NULL DEFAULT 0,"
            . " last_used TEXT NOT NULL DEFAULT ''"
            . ");"
            . "CREATE TABLE IF NOT EXISTS app_state ("
            . " key TEXT PRIMARY KEY, value TEXT NOT NULL DEFAULT ''"
            . ");"
        this.Check(this.DB.Exec(sql), "create database schema")
    }

    Execute(sql, params*) {
        sql := this.ExpandSql(sql, params)
        if !this.DB.Exec(sql)
            throw Error("SQLite execute failed:`n" this.DB.ErrorMsg "`n`n" sql)
        return true
    }

    Query(sql, params*) {
        sql := this.ExpandSql(sql, params)
        if !this.DB.GetTable(sql, &table)
            throw Error("SQLite query failed:`n" this.DB.ErrorMsg "`n`n" sql)
        return table.Rows
    }

    Scalar(sql, defaultValue := "", params*) {
        rows := this.Query(sql, params*)
        return rows.Length ? rows[1][1] : defaultValue
    }

    ExpandSql(sql, values) {
        positions := []
        offset := 1
        while (position := InStr(sql, "?", true, offset)) {
            positions.Push(position)
            offset := position + 1
        }
        if (values.Length > positions.Length)
            throw Error("Too many SQLite parameters for query:`n" sql)
        ; Replace right-to-left so question marks inside user values (notes,
        ; commands, and tags) can never be mistaken for later placeholders.
        Loop values.Length {
            index := values.Length - A_Index + 1
            position := positions[index]
            sql := SubStr(sql, 1, position - 1) this.SqlValue(values[index]) SubStr(sql, position + 1)
        }
        return sql
    }

    SqlValue(value) {
        if IsInteger(value) || IsFloat(value)
            return value ""
        return "'" StrReplace(value "", "'", "''") "'"
    }

    Check(result, operation) {
        if !result
            throw Error("Could not " operation ".`n`n" this.DB.ErrorMsg)
        return true
    }

    GetState(key, defaultValue := "") {
        return this.Scalar("SELECT value FROM app_state WHERE key=?", defaultValue, key)
    }

    SetState(key, value) {
        this.Execute(
            "INSERT INTO app_state(key,value) VALUES(?,?) "
            . "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            key, value
        )
    }

    RecordFolderVisit(projectPath, folderPath, source, displayName) {
        now := ManagerV7.NowStamp()
        this.Execute(
            "INSERT INTO folder_stats(path,display_name,visit_count,last_visit,last_source,last_folder) "
            . "VALUES(?,?,1,?,?,?) ON CONFLICT(path) DO UPDATE SET "
            . "display_name=excluded.display_name, visit_count=visit_count+1, "
            . "last_visit=excluded.last_visit, last_source=excluded.last_source, "
            . "last_folder=excluded.last_folder",
            projectPath, displayName, now, source, folderPath
        )
    }

    RecordFolderSegment(projectPath, folderPath, startedAt, seconds, source, hwnd := 0) {
        seconds := Max(0, Round(seconds))
        if (projectPath = "" || seconds < 1)
            return
        now := ManagerV7.NowStamp()
        this.Execute("BEGIN IMMEDIATE")
        try {
            this.Execute(
                "UPDATE folder_stats SET total_seconds=total_seconds+?, last_visit=? WHERE path=?",
                seconds, now, projectPath
            )
            this.Execute(
                "INSERT INTO folder_sessions(project_path,folder_path,started_at,ended_at,seconds,source,hwnd) "
                . "VALUES(?,?,?,?,?,?,?)",
                projectPath, folderPath, startedAt, now, seconds, source, hwnd
            )
            this.Execute("COMMIT")
        } catch as err {
            try this.Execute("ROLLBACK")
            throw err
        }
    }

    RankedFolders(limit := 100) {
        return this.Query(
            "SELECT path,display_name,visit_count,total_seconds,last_visit,favorite,last_folder,"
            . "(visit_count*60+total_seconds) AS score FROM folder_stats "
            . "ORDER BY favorite DESC, score DESC, last_visit DESC LIMIT ?", limit
        )
    }

    ToggleFolderFavorite(path) {
        this.Execute(
            "UPDATE folder_stats SET favorite=CASE favorite WHEN 0 THEN 1 ELSE 0 END WHERE path=?", path
        )
    }

    EnsureFile(path, kind := "file") {
        this.Execute(
            "INSERT INTO file_stats(path,kind,first_seen) VALUES(?,?,?) "
            . "ON CONFLICT(path) DO UPDATE SET kind=excluded.kind, removed=0",
            path, kind, ManagerV7.NowStamp()
        )
    }

    RecordFileUse(path, kind, action, pid := 0) {
        now := ManagerV7.NowStamp()
        this.Execute("BEGIN IMMEDIATE")
        try {
            this.Execute(
                "INSERT INTO file_stats(path,kind,use_count,first_seen,last_used,removed) VALUES(?,?,1,?,?,0) "
                . "ON CONFLICT(path) DO UPDATE SET kind=excluded.kind,use_count=use_count+1,"
                . "last_used=excluded.last_used,removed=0",
                path, kind, now, now
            )
            this.Execute(
                "INSERT INTO launch_events(path,kind,action,used_at,pid) VALUES(?,?,?,?,?)",
                path, kind, action, now, pid
            )
            this.Execute("COMMIT")
        } catch as err {
            try this.Execute("ROLLBACK")
            throw err
        }
    }

    FileStatMap(paths) {
        result := Map()
        for path in paths {
            rows := this.Query(
                "SELECT use_count,last_used,favorite,always_start,tags,notes FROM file_stats WHERE path=?", path
            )
            if rows.Length
                result[StrLower(path)] := rows[1]
        }
        return result
    }

    FrequentFiles(limit := 300) {
        return this.Query(
            "SELECT path,kind,use_count,last_used,favorite,always_start,tags,notes FROM file_stats "
            . "WHERE removed=0 AND use_count>0 ORDER BY favorite DESC,use_count DESC,last_used DESC LIMIT ?", limit
        )
    }

    Scripts(limit := 1000) {
        return this.Query(
            "SELECT path,kind,use_count,last_used,favorite,always_start,tags,notes FROM file_stats "
            . "WHERE removed=0 AND kind='ahk' ORDER BY favorite DESC,use_count DESC,last_used DESC LIMIT ?", limit
        )
    }

    ToggleFileFlag(path, column) {
        if !(column = "favorite" || column = "always_start")
            return
        this.Execute(
            "UPDATE file_stats SET " column "=CASE " column " WHEN 0 THEN 1 ELSE 0 END WHERE path=?", path
        )
    }

    SaveMetadata(path, tags, notes) {
        this.EnsureFile(path, ManagerV7.KindFromPath(path))
        this.Execute("UPDATE file_stats SET tags=?,notes=? WHERE path=?", tags, notes, path)
    }

    RemoveFile(path) {
        this.Execute("UPDATE file_stats SET removed=1 WHERE path=?", path)
    }

    SaveRunningSnapshot(counts) {
        this.Execute("BEGIN IMMEDIATE")
        try {
            this.Execute("DELETE FROM running_snapshot")
            for path, count in counts
                this.Execute("INSERT INTO running_snapshot(path,instance_count) VALUES(?,?)", path, count)
            this.Execute("COMMIT")
        } catch as err {
            try this.Execute("ROLLBACK")
            throw err
        }
    }

    GetRunningSnapshot() {
        return this.Query("SELECT path,instance_count FROM running_snapshot")
    }

    ImportLegacyScriptHub() {
        SmokeLog("legacy-scripts:start")
        legacyState := this.GetState("legacy_script_hub_imported", "0")
        SmokeLog("legacy-scripts:state=" legacyState)
        if (legacyState = "1")
            return
        legacyPath := A_AppData "\AHKScriptHub\scripts.tsv"
        if FileExist(legacyPath) {
            try text := FileRead(legacyPath, "UTF-8")
            catch
                text := ""
            for rawLine in StrSplit(text, "`n", "`r") {
                line := Trim(rawLine, "`r`n")
                if (line = "" || SubStr(line, 1, 1) = "#")
                    continue
                fields := StrSplit(line, "`t")
                if (fields.Length < 8)
                    continue
                path := ManagerV7.NormalizePath(this.LegacyDecode(fields[1]))
                if (path = "")
                    continue
                count := IsNumber(this.LegacyDecode(fields[2])) ? this.LegacyDecode(fields[2]) + 0 : 0
                this.Execute(
                    "INSERT INTO file_stats(path,kind,use_count,first_seen,last_used,favorite,always_start,tags,notes) "
                    . "VALUES(?,'ahk',?,?,?,?,?,?,?) ON CONFLICT(path) DO UPDATE SET "
                    . "use_count=MAX(use_count,excluded.use_count),last_used=MAX(last_used,excluded.last_used),"
                    . "favorite=MAX(favorite,excluded.favorite),always_start=MAX(always_start,excluded.always_start),"
                    . "tags=CASE WHEN tags='' THEN excluded.tags ELSE tags END,"
                    . "notes=CASE WHEN notes='' THEN excluded.notes ELSE notes END",
                    path, count, this.LegacyDecode(fields[3]), this.LegacyDecode(fields[4]),
                    this.SafeFlag(fields[5]), this.SafeFlag(fields[6]),
                    this.LegacyDecode(fields[7]), this.LegacyDecode(fields[8])
                )
            }
        }
        this.SetState("legacy_script_hub_imported", "1")
        SmokeLog("legacy-scripts:done")
    }

    ImportLegacyCommands() {
        SmokeLog("legacy-commands:start")
        commandState := this.GetState("legacy_commands_imported", "0")
        SmokeLog("legacy-commands:state=" commandState)
        if (commandState = "1")
            return
        ini := A_ScriptDir "\GlobalConsoleCommandMenu.ini"
        if FileExist(ini) {
            count := IniRead(ini, "Custom", "Count", 0) + 0
            Loop count {
                label := IniRead(ini, "Custom", "Label" A_Index, "")
                command := IniRead(ini, "Custom", "Command" A_Index, "")
                if (label != "" && command != "")
                    this.Execute("INSERT INTO custom_commands(label,command) VALUES(?,?)", label, command)
            }
        }
        this.SetState("legacy_commands_imported", "1")
        SmokeLog("legacy-commands:done")
    }

    LegacyDecode(value) {
        value := StrReplace(value, "%0A", "`n")
        value := StrReplace(value, "%0D", "`r")
        value := StrReplace(value, "%09", "`t")
        return StrReplace(value, "%25", "%")
    }

    SafeFlag(value) {
        decoded := this.LegacyDecode(value)
        return IsNumber(decoded) && decoded + 0 ? 1 : 0
    }

    __Delete() {
        try this.DB.CloseDB()
    }
}

class ManagerV7 {
    __New() {
        SmokeLog("manager:start")
        this.Title := "Manager v7 - Projects, Files & Scripts"
        this.Store := ManagerStore(A_ScriptDir "\data\Managerv7.sqlite")
        this.Store.ImportLegacyScriptHub()
        this.Store.ImportLegacyCommands()
        SmokeLog("manager:imports-ready")

        this.GuiBuilt := false
        this.ViewMode := "Folder"
        this.CurrentPath := this.Store.GetState("current_path", A_ScriptDir)
        if !DirExist(this.CurrentPath)
            this.CurrentPath := A_ScriptDir
        this.BackHistory := []
        this.ForwardHistory := []
        this.ProjectCache := Map()
        this.RowColors := Map()
        this.Running := Map()
        this.SeenPids := Map()
        this.ActiveExplorerProject := ""
        this.ActiveExplorerFolder := ""
        this.ActiveExplorerHwnd := 0
        this.ActiveSegmentStarted := ""
        this.ActiveSegmentTick := 0
        this.LastRankRefresh := 0
        this.ShellApp := 0
        this.WinEventHooks := []
        this.WinEventCallback := 0
        this.ActionPalette := 0
        this.ResizeCallback := ObjBindMethod(this, "OnGuiSize")
        this.RefreshCallback := ObjBindMethod(this, "DeferredRefresh")
        this.ExplorerPollCallback := ObjBindMethod(this, "PollExplorer")
        this.ScriptPollCallback := ObjBindMethod(this, "ScanRunningScripts")

        this.MigrateLegacyExplorer()
        SmokeLog("manager:legacy-ready")
        this.BuildGui()
        SmokeLog("manager:gui-ready")
        this.RegisterHotkeys()
        this.InitializeExplorerWatcher()
        OnMessage(0x4E, ObjBindMethod(this, "OnNotify"))
        OnExit(ObjBindMethod(this, "Shutdown"))
        SetTimer(this.ExplorerPollCallback, 700)
        SetTimer(this.ScriptPollCallback, 1500)
        SetTimer(ObjBindMethod(this, "RestoreScripts"), -1800)
        this.ScanRunningScripts()
        SmokeLog("manager:ready")
    }

    InitializeExplorerWatcher() {
        this.GetShellApplication()
        try {
            this.WinEventCallback := CallbackCreate(ObjBindMethod(this, "OnExplorerWinEvent"), "", 7)
            for eventId in [0x0003, 0x8005, 0x800C] {
                hook := DllCall(
                    "SetWinEventHook", "UInt", eventId, "UInt", eventId,
                    "Ptr", 0, "Ptr", this.WinEventCallback, "UInt", 0, "UInt", 0,
                    "UInt", 0x0002, "Ptr"
                )
                if hook
                    this.WinEventHooks.Push(hook)
            }
        }
    }

    OnExplorerWinEvent(hook, eventId, hwnd, objectId, childId, eventThread, eventTime) {
        if !hwnd
            return
        try rootHwnd := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
        catch
            rootHwnd := hwnd
        if this.IsExplorerWindow(rootHwnd)
            SetTimer(this.ExplorerPollCallback, -35)
    }

    ShutdownExplorerWatcher() {
        for hook in this.WinEventHooks {
            try DllCall("UnhookWinEvent", "Ptr", hook)
        }
        this.WinEventHooks := []
        if this.WinEventCallback {
            try CallbackFree(this.WinEventCallback)
            this.WinEventCallback := 0
        }
    }

    RegisterHotkeys() {
        Hotkey("^!e", ObjBindMethod(this, "Show"))
        Hotkey("^#a", ObjBindMethod(this, "ShowScripts"))
        HotIfWinActive("ahk_id " this.MainGui.Hwnd)
        Hotkey("!Left", ObjBindMethod(this, "NavigateBack"))
        Hotkey("!Right", ObjBindMethod(this, "NavigateForward"))
        Hotkey("!Up", ObjBindMethod(this, "NavigateUp"))
        Hotkey("^l", ObjBindMethod(this, "FocusAddress"))
        Hotkey("^f", ObjBindMethod(this, "FocusFilter"))
        Hotkey("F5", ObjBindMethod(this, "RefreshView"))
        Hotkey("Backspace", ObjBindMethod(this, "NavigateUp"))
        HotIf()
    }

    MigrateLegacyExplorer() {
        if (this.Store.GetState("legacy_explorer_imported", "0") = "1")
            return
        ini := A_ScriptDir "\ExplorerWorkspaceManager.ini"
        if FileExist(ini) {
            count := IniRead(ini, "History", "Count", 0) + 0
            ; Import oldest to newest so last_visit remains meaningful.
            Loop count {
                index := count - A_Index + 1
                folder := NormalizePath(IniRead(ini, "History", "Path" index, ""))
                if (folder = "" || !DirExist(folder))
                    continue
                project := this.FindProjectRoot(folder)
                this.Store.RecordFolderVisit(project, folder, "Legacy import", this.PathDisplayName(project))
            }
            Loop 10 {
                folder := NormalizePath(IniRead(ini, "Workspace", "Path" A_Index, ""))
                if (folder = "" || !DirExist(folder))
                    continue
                project := this.FindProjectRoot(folder)
                this.Store.RecordFolderVisit(project, folder, "Legacy workspace", this.PathDisplayName(project))
            }
        }
        this.Store.SetState("legacy_explorer_imported", "1")
    }

    PollExplorer(*) {
        hwnd := WinExist("A")
        if !this.IsExplorerWindow(hwnd) {
            this.FlushExplorerSegment(true)
            return
        }

        folder := this.GetExplorerPath(hwnd)
        if (folder = "" || !DirExist(folder)) {
            this.FlushExplorerSegment(true)
            return
        }
        folder := NormalizePath(folder)
        project := this.FindProjectRoot(folder)

        if (
            StrLower(folder) != StrLower(this.ActiveExplorerFolder)
            || hwnd != this.ActiveExplorerHwnd
        ) {
            this.FlushExplorerSegment(true)
            this.ActiveExplorerProject := project
            this.ActiveExplorerFolder := folder
            this.ActiveExplorerHwnd := hwnd
            this.ActiveSegmentStarted := NowStamp()
            this.ActiveSegmentTick := A_TickCount
            this.Store.RecordFolderVisit(project, folder, "Explorer", this.PathDisplayName(project))
            if this.GuiBuilt && this.IsVisible() && (A_TickCount - this.LastRankRefresh > 1000)
                this.RefreshProjects()
            return
        }

        ; Commit long foreground sessions in small durable segments.
        if (A_TickCount - this.ActiveSegmentTick >= 15000)
            this.FlushExplorerSegment(false)
    }

    FlushExplorerSegment(clear := true) {
        if (this.ActiveExplorerProject != "" && this.ActiveSegmentTick) {
            seconds := Floor((A_TickCount - this.ActiveSegmentTick) / 1000)
            if (seconds > 0) {
                try this.Store.RecordFolderSegment(
                    this.ActiveExplorerProject, this.ActiveExplorerFolder,
                    this.ActiveSegmentStarted, seconds, "Explorer", this.ActiveExplorerHwnd
                )
            }
            if !clear {
                this.ActiveSegmentStarted := NowStamp()
                this.ActiveSegmentTick := A_TickCount
            }
        }
        if clear {
            this.ActiveExplorerProject := ""
            this.ActiveExplorerFolder := ""
            this.ActiveExplorerHwnd := 0
            this.ActiveSegmentStarted := ""
            this.ActiveSegmentTick := 0
        }
    }

    IsExplorerWindow(hwnd) {
        if !hwnd
            return false
        try return (
            StrLower(WinGetProcessName("ahk_id " hwnd)) = "explorer.exe"
            && (WinGetClass("ahk_id " hwnd) = "CabinetWClass" || WinGetClass("ahk_id " hwnd) = "ExploreWClass")
        )
        catch
            return false
    }

    GetShellApplication() {
        if this.ShellApp {
            try {
                unused := this.ShellApp.Windows.Count
                return this.ShellApp
            }
        }
        try this.ShellApp := ComObject("Shell.Application")
        catch
            this.ShellApp := 0
        return this.ShellApp
    }

    GetExplorerPath(hwnd) {
        shell := this.GetShellApplication()
        if !shell
            return ""
        candidates := []
        try title := RegExReplace(WinGetTitle("ahk_id " hwnd), "i)\s+-\s+File Explorer$")
        catch
            title := ""
        try {
            for window in shell.Windows {
                try {
                    if ((window.HWND + 0) != hwnd || !InStr(StrLower(window.FullName ""), "explorer.exe"))
                        continue
                    path := NormalizePath(window.Document.Folder.Self.Path "")
                    if (path != "" && DirExist(path))
                        candidates.Push({Path:path, Name:window.LocationName ""})
                }
            }
        }
        for candidate in candidates {
            if (StrLower(candidate.Name) = StrLower(title) || StrLower(this.PathDisplayName(candidate.Path)) = StrLower(title))
                return candidate.Path
        }
        return candidates.Length ? candidates[candidates.Length].Path : ""
    }

    FindProjectRoot(path) {
        path := DirExist(path) ? NormalizePath(path) : this.ParentDirectory(path)
        if (path = "")
            return ""
        key := StrLower(path)
        if this.ProjectCache.Has(key)
            return this.ProjectCache[key]

        original := path
        current := path
        Loop 14 {
            if this.HasProjectMarker(current) {
                this.ProjectCache[key] := current
                return current
            }
            parent := this.ParentDirectory(current)
            if (parent = "" || StrLower(parent) = StrLower(current))
                break
            current := parent
        }
        this.ProjectCache[key] := original
        return original
    }

    HasProjectMarker(path) {
        static markers := [
            ".git", ".hg", ".svn", ".vscode", "pyproject.toml", "requirements.txt",
            "package.json", "Cargo.toml", "go.mod", "composer.json", "pom.xml",
            "build.gradle", "CMakeLists.txt", "Gemfile"
        ]
        for marker in markers {
            if FileExist(path "\" marker) || DirExist(path "\" marker)
                return true
        }
        try {
            Loop Files path "\*.sln", "F"
                return true
            Loop Files path "\*.code-workspace", "F"
                return true
        }
        return false
    }

    BuildGui() {
        SmokeLog("gui:start")
        this.MainGui := Gui("+Resize +MinSize760x480", this.Title)
        SmokeLog("gui:created")
        this.MainGui.SetFont("s9", "Segoe UI")
        this.MainGui.MarginX := 8
        this.MainGui.MarginY := 8
        this.MainGui.OnEvent("Close", ObjBindMethod(this, "Hide"))
        this.MainGui.OnEvent("Size", this.ResizeCallback)
        this.MainGui.OnEvent("Escape", ObjBindMethod(this, "Hide"))

        ; One compact navigation toolbar replaces the wrapping tab strip.
        this.BackButton := this.MainGui.AddButton("x8 y8 w34 h28", "<")
        this.ForwardButton := this.MainGui.AddButton("x46 y8 w34 h28", ">")
        this.UpButton := this.MainGui.AddButton("x84 y8 w34 h28", "Up")
        this.AddressEdit := this.MainGui.AddEdit("x122 y8 w430 h28 -Wrap", this.CurrentPath)
        this.GoButton := this.MainGui.AddButton("x556 y8 w38 h28 Default", "Go")
        this.RefreshButton := this.MainGui.AddButton("x598 y8 w54 h28", "Refresh")
        this.ExplorerButton := this.MainGui.AddButton("x656 y8 w70 h28", "Explorer")
        this.MoreButton := this.MainGui.AddButton("x730 y8 w52 h28", "More")
        SmokeLog("gui:navigation-controls")

        this.BackButton.OnEvent("Click", ObjBindMethod(this, "NavigateBack"))
        this.ForwardButton.OnEvent("Click", ObjBindMethod(this, "NavigateForward"))
        this.UpButton.OnEvent("Click", ObjBindMethod(this, "NavigateUp"))
        this.AddressEdit.OnEvent("Focus", ObjBindMethod(this, "SelectAddress"))
        this.AddressEdit.OnEvent("LoseFocus", ObjBindMethod(this, "AddressLostFocus"))
        this.GoButton.OnEvent("Click", ObjBindMethod(this, "GoToAddress"))
        this.RefreshButton.OnEvent("Click", ObjBindMethod(this, "RefreshView"))
        this.ExplorerButton.OnEvent("Click", ObjBindMethod(this, "OpenCurrentInExplorer"))
        this.MoreButton.OnEvent("Click", ObjBindMethod(this, "ShowMoreMenu"))

        this.ProjectLabel := this.MainGui.AddText("x8 y46 w210 h22 +0x200", "MOST UTILIZED PROJECTS")
        this.ViewCombo := this.MainGui.AddComboBox("x224 y43 w142 Choose1", ["Folder", "Launcher", "Scripts"])
        this.FilterEdit := this.MainGui.AddEdit("x374 y43 w230 h27 -Wrap")
        this.TypeCombo := this.MainGui.AddComboBox("x610 y43 w120 Choose1", [
            "All types", "Folders", "AutoHotkey", "Python", "Code", "Documents", "Images", "Recent 24h"
        ])
        this.RecursiveCheck := this.MainGui.AddCheckBox("x736 y46 w76 h22", "Recursive")
        this.HiddenCheck := this.MainGui.AddCheckBox("x816 y46 w66 h22", "Hidden")
        this.RegexCheck := this.MainGui.AddCheckBox("x886 y46 w58 h22", "Regex")
        SmokeLog("gui:filter-controls")

        this.ViewCombo.OnEvent("Change", ObjBindMethod(this, "ChangeView"))
        this.FilterEdit.OnEvent("Change", ObjBindMethod(this, "QueueRefresh"))
        this.TypeCombo.OnEvent("Change", ObjBindMethod(this, "QueueRefresh"))
        this.RecursiveCheck.OnEvent("Click", ObjBindMethod(this, "QueueRefresh"))
        this.HiddenCheck.OnEvent("Click", ObjBindMethod(this, "QueueRefresh"))
        this.RegexCheck.OnEvent("Click", ObjBindMethod(this, "QueueRefresh"))

        this.ProjectList := this.MainGui.AddListView("x8 y74 w260 h410 Grid -Multi", [
            "Project", "Visits", "Time", "Last", "Path"
        ])
        this.ProjectList.OnEvent("DoubleClick", ObjBindMethod(this, "OpenProjectRow"))
        this.ProjectList.OnEvent("ContextMenu", ObjBindMethod(this, "ProjectContextMenu"))
        this.ProjectList.OnEvent("Click", ObjBindMethod(this, "UpdateProjectStatus"))
        SmokeLog("gui:project-list")

        this.FileList := this.MainGui.AddListView("x276 y74 w668 h410 Grid AltSubmit Multi", [
            "Name", "Type", "Uses", "State / Size", "Modified / Last used", "Full path"
        ])
        this.FileList.OnEvent("DoubleClick", ObjBindMethod(this, "OpenFileRow"))
        this.FileList.OnEvent("ContextMenu", ObjBindMethod(this, "FileContextMenu"))
        this.FileList.OnEvent("Click", ObjBindMethod(this, "UpdateFileStatus"))
        this.FileList.OnEvent("ItemFocus", ObjBindMethod(this, "UpdateFileStatus"))
        SmokeLog("gui:file-list")

        this.AttachShellImageList(this.ProjectList)
        this.AttachShellImageList(this.FileList)
        SmokeLog("gui:icons")

        ; Compact footer action bar.  Its colors are also the action legend.
        footerY := 492
        this.FooterExplorer := this.AddFooterTile(8, footerY, 112, "Explorer / Folder", "FFF2A8", ObjBindMethod(this, "FooterExplorerAction"))
        SmokeLog("gui:footer-explorer")
        this.FooterEverything := this.AddFooterTile(124, footerY, 108, "Everything", "FFD29A", ObjBindMethod(this, "FooterEverythingAction"))
        SmokeLog("gui:footer-everything")
        this.FooterVSCode := this.AddFooterTile(236, footerY, 100, "VS Code", "BFD8FF", ObjBindMethod(this, "FooterVSCodeAction"))
        SmokeLog("gui:footer-vscode")
        this.FooterRun := this.AddFooterTile(340, footerY, 82, "Run / Open", "D8F5D0", ObjBindMethod(this, "FooterRunAction"))
        SmokeLog("gui:footer-run")
        this.FooterPath := this.MainGui.AddText("x430 y492 w514 h28 +0x200 +0x4000", "Right-click an item for file-type actions")
        SmokeLog("gui:footer")

        this.StatusBar := this.MainGui.AddStatusBar()
        this.StatusBar.SetParts(230, 540)
        this.StatusBar.SetText("Ready", 1)
        this.StatusBar.SetText("Explorer watcher: active", 2)
        this.StatusBar.SetText("Alt+Left/Right  Ctrl+L  Ctrl+F  F5", 3)
        SmokeLog("gui:status")

        this.GuiBuilt := true
        SmokeLog("gui:controls-ready")
        this.RefreshProjects()
        SmokeLog("gui:projects-ready")
        this.RefreshView()
        SmokeLog("gui:view-ready")
        this.OnGuiSize(this.MainGui, 0, 960, 560)
        SmokeLog("gui:layout-ready")
    }

    AddFooterTile(x, y, width, label, color, callback) {
        progress := this.MainGui.AddProgress("x" x " y" y " w" width " h28 c" color " Background" color, 100)
        textCtrl := this.MainGui.AddText(
            "x" (x + 4) " y" (y + 1) " w" (width - 8) " h26 Center +0x200 BackgroundTrans",
            label
        )
        textCtrl.OnEvent("Click", callback)
        return {Background:progress, Text:textCtrl, Width:width}
    }

    OnGuiSize(guiObj, minMax, width, height) {
        if (minMax = -1 || !this.GuiBuilt)
            return
        width := Max(width, 760)
        height := Max(height, 480)
        margin := 8

        ; Navigation row.
        this.BackButton.Move(margin, 8, 34, 28)
        this.ForwardButton.Move(46, 8, 34, 28)
        this.UpButton.Move(84, 8, 34, 28)
        fixedRight := 238
        addressWidth := Max(180, width - 122 - fixedRight)
        this.AddressEdit.Move(122, 8, addressWidth, 28)
        x := 122 + addressWidth + 4
        this.GoButton.Move(x, 8, 38, 28)
        this.RefreshButton.Move(x + 42, 8, 54, 28)
        this.ExplorerButton.Move(x + 100, 8, 70, 28)
        this.MoreButton.Move(x + 174, 8, Max(52, width - margin - (x + 174)), 28)

        ; Filter row.  On narrow screens, keep the essentials visible and hide
        ; the two least-used switches rather than wrapping another toolbar row.
        leftWidth := this.Clamp(Round(width * 0.285), 220, 330)
        this.ProjectLabel.Move(margin, 43, leftWidth - 8, 27)
        rightX := margin + leftWidth + 8
        rightWidth := width - rightX - margin
        viewWidth := this.Clamp(Round(rightWidth * 0.18), 116, 150)
        typeWidth := this.Clamp(Round(rightWidth * 0.16), 104, 130)
        switchWidth := width >= 940 ? 208 : 78
        this.ViewCombo.Move(rightX, 43, viewWidth, 27)
        filterX := rightX + viewWidth + 6
        typeX := rightX + rightWidth - typeWidth - switchWidth - 6
        filterWidth := Max(100, typeX - filterX - 6)
        this.FilterEdit.Move(filterX, 43, filterWidth, 27)
        this.TypeCombo.Move(typeX, 43, typeWidth, 27)
        switchX := typeX + typeWidth + 6
        this.RecursiveCheck.Move(switchX, 46, 76, 22)
        if (width >= 940) {
            this.HiddenCheck.Visible := true
            this.RegexCheck.Visible := true
            this.HiddenCheck.Move(switchX + 78, 46, 66, 22)
            this.RegexCheck.Move(switchX + 146, 46, 58, 22)
        } else {
            this.HiddenCheck.Visible := false
            this.RegexCheck.Visible := false
        }

        footerHeight := 28
        statusHeight := 24
        footerY := height - statusHeight - footerHeight - 8
        contentY := 74
        contentHeight := Max(250, footerY - contentY - 6)
        this.ProjectList.Move(margin, contentY, leftWidth, contentHeight)
        this.FileList.Move(rightX, contentY, rightWidth, contentHeight)

        tileX := margin
        for tile in [this.FooterExplorer, this.FooterEverything, this.FooterVSCode, this.FooterRun] {
            tile.Background.Move(tileX, footerY, tile.Width, footerHeight)
            tile.Text.Move(tileX + 4, footerY + 1, tile.Width - 8, footerHeight - 2)
            tileX += tile.Width + 4
        }
        this.FooterPath.Move(tileX + 4, footerY, Max(120, width - tileX - 12), footerHeight)
        this.StatusBar.SetParts(this.Clamp(leftWidth, 180, 330), this.Clamp(width - 300, 420, 760))
        this.ResizeColumns(leftWidth, rightWidth)
    }

    ResizeColumns(leftWidth, rightWidth) {
        projectUsable := Max(190, leftWidth - 22)
        this.ProjectList.ModifyCol(1, Max(90, projectUsable - 154))
        this.ProjectList.ModifyCol(2, 45)
        this.ProjectList.ModifyCol(3, 55)
        this.ProjectList.ModifyCol(4, 54)
        this.ProjectList.ModifyCol(5, 0)

        usable := Max(430, rightWidth - 24)
        this.FileList.ModifyCol(1, Max(150, Round(usable * 0.34)))
        this.FileList.ModifyCol(2, Max(75, Round(usable * 0.13)))
        this.FileList.ModifyCol(3, 48)
        this.FileList.ModifyCol(4, Max(80, Round(usable * 0.17)))
        this.FileList.ModifyCol(5, Max(120, Round(usable * 0.24)))
        this.FileList.ModifyCol(6, 0)
    }

    Show(*) {
        this.MainGui.Show("w960 h560")
        this.RefreshProjects()
        this.RefreshView()
        try WinActivate("ahk_id " this.MainGui.Hwnd)
    }

    ShowScripts(*) {
        this.ViewCombo.Text := "Scripts"
        this.ViewMode := "Scripts"
        this.Show()
    }

    Hide(*) {
        this.MainGui.Hide()
    }

    IsVisible() {
        try return DllCall("IsWindowVisible", "Ptr", this.MainGui.Hwnd, "Int") != 0
        catch
            return false
    }

    ChangeView(*) {
        this.ViewMode := this.ViewCombo.Text
        this.RefreshView()
    }

    QueueRefresh(*) {
        SetTimer(this.RefreshCallback, 0)
        SetTimer(this.RefreshCallback, -180)
    }

    DeferredRefresh(*) {
        if this.GuiBuilt
            this.RefreshView()
    }

    RefreshView(*) {
        if !this.GuiBuilt
            return
        this.ViewMode := this.ViewCombo.Text
        switch this.ViewMode {
            case "Launcher": this.RefreshLauncher()
            case "Scripts": this.RefreshScripts()
            default: this.RefreshFolder()
        }
        this.UpdateNavigationButtons()
    }

    RefreshProjects(*) {
        if !this.GuiBuilt
            return
        selectedPath := this.GetSelectedProjectPath()
        rows := this.Store.RankedFolders(120)
        colors := Map()
        this.ProjectList.Opt("-Redraw")
        this.ProjectList.Delete()
        for row in rows {
            path := row[1]
            name := row[2] != "" ? row[2] : this.PathDisplayName(path)
            favorite := row[6] + 0
            if favorite
                name := "* " name
            icon := this.GetShellIconIndex(path)
            options := icon >= 0 ? "Icon" (icon + 1) : ""
            listRow := this.ProjectList.Add(
                options, name, row[3], this.FormatDuration(row[4]), this.RelativeTime(row[5]), path
            )
            colors[listRow] := favorite ? this.ColorRef("FFF2A8") : this.ColorRef("F7F9FC")
            if (selectedPath != "" && StrLower(selectedPath) = StrLower(path))
                this.ProjectList.Modify(listRow, "Select Focus")
        }
        this.ProjectList.Opt("+Redraw")
        this.RowColors[this.ProjectList.Hwnd] := colors
        this.LastRankRefresh := A_TickCount
        this.StatusBar.SetText(rows.Length " ranked projects", 1)
    }

    RefreshFolder() {
        root := NormalizePath(this.CurrentPath)
        if !DirExist(root) {
            this.SetStatus("Folder is unavailable: " root)
            return
        }
        this.AddressEdit.Value := root
        entries := []
        paths := []
        recursive := this.RecursiveCheck.Value = 1
        mode := recursive ? "DR" : "D"
        try {
            Loop Files root "\*", mode {
                if entries.Length >= 5000
                    break
                if (!this.HiddenCheck.Value && InStr(A_LoopFileAttrib, "H"))
                    continue
                fullPath := A_LoopFileFullPath
                if !this.MatchesFilters(A_LoopFileName, fullPath, true, A_LoopFileTimeModified)
                    continue
                item := {
                    Path:fullPath, Name:A_LoopFileName, Kind:"folder", IsDir:true,
                    Size:"", Modified:A_LoopFileTimeModified
                }
                entries.Push(item), paths.Push(fullPath)
            }
            mode := recursive ? "FR" : "F"
            Loop Files root "\*", mode {
                if entries.Length >= 5000
                    break
                if (!this.HiddenCheck.Value && InStr(A_LoopFileAttrib, "H"))
                    continue
                fullPath := A_LoopFileFullPath
                kind := KindFromPath(fullPath)
                if !this.MatchesFilters(A_LoopFileName, fullPath, false, A_LoopFileTimeModified)
                    continue
                item := {
                    Path:fullPath, Name:A_LoopFileName, Kind:kind, IsDir:false,
                    Size:A_LoopFileSize, Modified:A_LoopFileTimeModified
                }
                entries.Push(item), paths.Push(fullPath)
            }
        } catch as err {
            this.SetStatus("Could not enumerate folder: " err.Message)
            return
        }
        stats := this.Store.FileStatMap(paths)
        this.FillFileRows(entries, stats, "Folder")
    }

    RefreshLauncher() {
        dbRows := this.Store.FrequentFiles(500)
        entries := []
        stats := Map()
        for row in dbRows {
            path := row[1]
            SplitPath(path, &name)
            if !this.MatchesFilters(name, path, DirExist(path), FileExist(path) ? FileGetTime(path, "M") : "")
                continue
            kind := row[2]
            entries.Push({
                Path:path, Name:name, Kind:kind, IsDir:DirExist(path), Size:"",
                Modified:row[4], Favorite:row[5], Always:row[6], Tags:row[7], Notes:row[8]
            })
            stats[StrLower(path)] := [row[3], row[4], row[5], row[6], row[7], row[8]]
        }
        this.FillFileRows(entries, stats, "Launcher")
    }

    RefreshScripts() {
        this.ScanRunningScripts()
        dbRows := this.Store.Scripts(1000)
        entries := []
        stats := Map()
        for row in dbRows {
            path := row[1]
            SplitPath(path, &name)
            if !this.MatchesFilters(name, path, false, FileExist(path) ? FileGetTime(path, "M") : "")
                continue
            entries.Push({
                Path:path, Name:name, Kind:"ahk", IsDir:false, Size:"", Modified:row[4],
                Favorite:row[5], Always:row[6], Tags:row[7], Notes:row[8]
            })
            stats[StrLower(path)] := [row[3], row[4], row[5], row[6], row[7], row[8]]
        }
        this.FillFileRows(entries, stats, "Scripts")
    }

    FillFileRows(entries, stats, sourceMode) {
        colors := Map()
        selected := this.GetSelectedPaths()
        selectedMap := Map()
        for path in selected
            selectedMap[StrLower(path)] := true
        this.FileList.Opt("-Redraw")
        this.FileList.Delete()
        for item in entries {
            key := StrLower(item.Path)
            stat := stats.Has(key) ? stats[key] : [0, "", 0, 0, "", ""]
            uses := stat[1] + 0
            favorite := stat[3] + 0
            label := favorite ? "* " item.Name : item.Name
            state := ""
            modified := ""
            if (sourceMode = "Scripts") {
                running := this.RunningCount(item.Path)
                state := running ? "Running x" running : (FileExist(item.Path) ? "Stopped" : "Missing")
                if (stat[4] + 0)
                    state .= " | Auto"
                modified := stat[2] != "" ? stat[2] : "Never"
            } else if (sourceMode = "Launcher") {
                state := DirExist(item.Path) ? "Folder" : this.PathDisplayName(this.ParentDirectory(item.Path))
                modified := stat[2] != "" ? stat[2] : "Never"
            } else {
                state := item.IsDir ? "Folder" : this.FormatBytes(item.Size)
                modified := item.Modified != "" ? this.FormatFileTime(item.Modified) : ""
            }
            icon := this.GetShellIconIndex(item.Path)
            options := icon >= 0 ? "Icon" (icon + 1) : ""
            listRow := this.FileList.Add(
                options, label, this.TypeLabel(item.Kind), uses, state, modified, item.Path
            )
            colors[listRow] := this.RowColorForKind(item.Kind)
            if selectedMap.Has(key)
                this.FileList.Modify(listRow, "Select")
        }
        this.FileList.Opt("+Redraw")
        this.RowColors[this.FileList.Hwnd] := colors
        this.StatusBar.SetText(entries.Length " items | " sourceMode, 1)
        this.StatusBar.SetText(sourceMode = "Folder" ? this.CurrentPath : "Sorted by favorites, use count, and recency", 2)
    }

    MatchesFilters(name, path, isDirectory, modified) {
        typeFilter := this.TypeCombo.Text
        kind := isDirectory ? "folder" : KindFromPath(path)
        switch typeFilter {
            case "Folders":
                if !isDirectory
                    return false
            case "AutoHotkey":
                if (kind != "ahk")
                    return false
            case "Python":
                if (kind != "python")
                    return false
            case "Code":
                if !this.IsCodeKind(kind)
                    return false
            case "Documents":
                if (kind != "document")
                    return false
            case "Images":
                if (kind != "image")
                    return false
            case "Recent 24h":
                if (modified = "" || DateDiff(A_Now, modified, "Hours") > 24)
                    return false
        }

        query := Trim(this.FilterEdit.Value)
        if (query = "")
            return true
        if this.RegexCheck.Value {
            try return RegExMatch(name "`n" path, query) != 0
            catch {
                this.SetStatus("Invalid regular expression")
                return false
            }
        }
        for token in StrSplit(query, A_Space) {
            token := Trim(token)
            if (token != "" && !InStr(name " " path, token, false))
                return false
        }
        return true
    }

    NavigateTo(path, addHistory := true, recordVisit := true, *) {
        path := NormalizePath(path)
        if !DirExist(path) {
            MsgBox("The folder is not available:`n`n" path, this.Title, "Icon!")
            return false
        }
        if (addHistory && this.CurrentPath != "" && StrLower(this.CurrentPath) != StrLower(path)) {
            this.BackHistory.Push(this.CurrentPath)
            if (this.BackHistory.Length > 100)
                this.BackHistory.RemoveAt(1)
            this.ForwardHistory := []
        }
        this.CurrentPath := path
        this.Store.SetState("current_path", path)
        this.AddressEdit.Value := path
        this.ViewCombo.Text := "Folder"
        this.ViewMode := "Folder"
        if recordVisit {
            project := this.FindProjectRoot(path)
            this.Store.RecordFolderVisit(project, path, "Manager", this.PathDisplayName(project))
            this.RefreshProjects()
        }
        this.RefreshView()
        return true
    }

    NavigateBack(*) {
        if !this.BackHistory.Length
            return
        path := this.BackHistory.Pop()
        if this.CurrentPath != ""
            this.ForwardHistory.Push(this.CurrentPath)
        this.NavigateTo(path, false, false)
    }

    NavigateForward(*) {
        if !this.ForwardHistory.Length
            return
        path := this.ForwardHistory.Pop()
        if this.CurrentPath != ""
            this.BackHistory.Push(this.CurrentPath)
        this.NavigateTo(path, false, false)
    }

    NavigateUp(*) {
        if (this.ViewMode != "Folder") {
            this.ViewCombo.Text := "Folder"
            this.ViewMode := "Folder"
            this.RefreshView()
            return
        }
        parent := this.ParentDirectory(this.CurrentPath)
        if (parent != "" && StrLower(parent) != StrLower(this.CurrentPath))
            this.NavigateTo(parent)
    }

    GoToAddress(*) {
        raw := Trim(this.AddressEdit.Value, " `t`r`n" Chr(34))
        if (raw = "")
            return
        if DirExist(raw) {
            this.NavigateTo(raw)
            return
        }
        if FileExist(raw) {
            if DirExist(this.ParentDirectory(raw))
                this.NavigateTo(this.ParentDirectory(raw))
            return
        }
        MsgBox("Enter an existing folder path.", this.Title, "Icon!")
        this.AddressEdit.Value := this.CurrentPath
    }

    FocusAddress(*) {
        this.AddressEdit.Focus()
        this.SelectAddress(this.AddressEdit)
    }

    FocusFilter(*) {
        this.FilterEdit.Focus()
        this.FilterEdit.Value := this.FilterEdit.Value
        Send("^a")
    }

    SelectAddress(ctrl, *) {
        try SendMessage(0xB1, 0, -1, ctrl)
    }

    AddressLostFocus(*) {
        if (Trim(this.AddressEdit.Value) = "")
            this.AddressEdit.Value := this.CurrentPath
    }

    UpdateNavigationButtons() {
        this.BackButton.Enabled := this.BackHistory.Length > 0
        this.ForwardButton.Enabled := this.ForwardHistory.Length > 0
        this.UpButton.Enabled := this.ViewMode != "Folder" || this.ParentDirectory(this.CurrentPath) != ""
    }

    OpenProjectRow(ctrl, row, *) {
        if !row
            return
        path := ctrl.GetText(row, 5)
        if DirExist(path)
            this.NavigateTo(path)
    }

    OpenFileRow(ctrl, row, *) {
        if !row
            return
        this.OpenPathDefault(ctrl.GetText(row, 6))
    }

    OpenPathDefault(path, *) {
        if (path = "")
            return
        if DirExist(path) {
            this.NavigateTo(path)
            return
        }
        if !FileExist(path) {
            MsgBox("The item no longer exists:`n`n" path, this.Title, "Icon!")
            return
        }
        kind := KindFromPath(path)
        switch kind {
            case "ahk": this.RunAhk(path)
            case "python": this.RunPython(path)
            default:
                try {
                    Run(Quote(path))
                    this.Store.RecordFileUse(path, kind, "open")
                } catch as err {
                    MsgBox("Could not open:`n" path "`n`n" err.Message, this.Title, "Icon!")
                }
        }
        this.QueueRefresh()
    }

    ProjectContextMenu(ctrl, row, isRightClick, x, y) {
        if !isRightClick || !row
            return
        ctrl.Modify(row, "Select Focus")
        this.ShowActionPalette([ctrl.GetText(row, 5)], "project", x, y)
    }

    FileContextMenu(ctrl, row, isRightClick, x, y) {
        if !isRightClick || !row
            return
        if !ctrl.GetNext()
            ctrl.Modify(row, "Select Focus")
        paths := this.GetSelectedPaths()
        if !paths.Length
            paths.Push(ctrl.GetText(row, 6))
        this.ShowActionPalette(paths, this.ViewMode = "Scripts" ? "script" : "file", x, y)
    }

    ShowActionPalette(paths, context := "file", x := 0, y := 0) {
        if !paths.Length
            return
        try {
            if IsObject(this.ActionPalette)
                this.ActionPalette.Destroy()
        }

        palette := Gui("-Caption +AlwaysOnTop +ToolWindow +Border", "Manager actions")
        palette.SetFont("s9", "Segoe UI")
        palette.BackColor := "F7F7F7"
        width := 326
        rowY := 0
        headerText := paths.Length = 1 ? this.PathDisplayName(paths[1]) : paths.Length " selected items"
        palette.AddText("x10 y4 w306 h28 +0x200 +0x4000", headerText)
        rowY := 32

        first := paths[1]
        kind := DirExist(first) ? "folder" : KindFromPath(first)
        if (kind = "folder") {
            this.AddPaletteRow(palette, &rowY, width, "Open inside Manager", "D8F5D0", ObjBindMethod(this, "NavigateTo", first))
        } else if (kind = "ahk") {
            this.AddPaletteRow(palette, &rowY, width, "Run AutoHotkey script", "D8F5D0", ObjBindMethod(this, "RunPathsAhk", paths))
            if this.AnyRunning(paths)
                this.AddPaletteRow(palette, &rowY, width, "Stop running instance(s)", "FFD0D0", ObjBindMethod(this, "StopPaths", paths))
            this.AddPaletteRow(palette, &rowY, width, "Restart script", "E6F4D7", ObjBindMethod(this, "RestartPaths", paths))
            this.AddPaletteRow(palette, &rowY, width, "Run as administrator", "F4F4F4", ObjBindMethod(this, "RunPathsAhkAdmin", paths))
        } else if (kind = "python") {
            this.AddPaletteRow(palette, &rowY, width, "Run Python file", "D8F5D0", ObjBindMethod(this, "RunPathsPython", paths))
        } else {
            this.AddPaletteRow(palette, &rowY, width, "Open selected", "D8F5D0", ObjBindMethod(this, "OpenPathsDefault", paths))
        }

        ; Consistent category colors requested by the user.
        this.AddPaletteRow(palette, &rowY, width, "Explorer / containing folder", "FFF2A8", ObjBindMethod(this, "OpenPathsInExplorer", paths))
        this.AddPaletteRow(palette, &rowY, width, "Everything / search this path", "FFD29A", ObjBindMethod(this, "OpenPathsInEverything", paths))
        this.AddPaletteRow(palette, &rowY, width, "VS Code / open selected", "BFD8FF", ObjBindMethod(this, "OpenPathsInVSCode", paths))
        this.AddPaletteRow(palette, &rowY, width, "Terminal at project/folder", "E7E7E7", ObjBindMethod(this, "OpenPathsInTerminal", paths))
        this.AddPaletteRow(palette, &rowY, width, "Copy full path(s)", "F4F4F4", ObjBindMethod(this, "CopyPaths", paths))

        if (context = "project") {
            this.AddPaletteRow(palette, &rowY, width, "Toggle favorite project", "FFF6C9", ObjBindMethod(this, "ToggleProjectFavorite", first))
        } else {
            this.AddPaletteRow(palette, &rowY, width, "Toggle favorite launcher item", "FFF6C9", ObjBindMethod(this, "ToggleFileFavorite", paths))
            if (kind = "ahk") {
                this.AddPaletteRow(palette, &rowY, width, "Toggle Always Start", "E8E8FF", ObjBindMethod(this, "ToggleAlwaysStart", paths))
                this.AddPaletteRow(palette, &rowY, width, "Tags / notes", "F2F2F2", ObjBindMethod(this, "EditMetadata", first))
                this.AddPaletteRow(palette, &rowY, width, "Remove from Script Hub", "FFD7D7", ObjBindMethod(this, "RemoveFromHub", paths))
            }
        }

        close := palette.AddText("x0 y" rowY " w" width " h27 Center +0x200", "Close")
        close.OnEvent("Click", (*) => palette.Destroy())
        rowY += 28
        palette.OnEvent("Escape", (*) => palette.Destroy())
        palette.OnEvent("Close", (*) => palette.Destroy())
        this.ActionPalette := palette
        if (!x || !y)
            MouseGetPos(&x, &y)
        palette.Show("x" x " y" y " w" width " h" rowY)
    }

    AddPaletteRow(guiObj, &rowY, width, label, color, callback) {
        guiObj.AddProgress("x0 y" rowY " w" width " h29 c" color " Background" color, 100)
        textCtrl := guiObj.AddText(
            "x12 y" (rowY + 1) " w" (width - 24) " h27 +0x200 BackgroundTrans", label
        )
        textCtrl.OnEvent("Click", (*) => this.InvokePaletteAction(guiObj, callback))
        rowY += 30
    }

    InvokePaletteAction(guiObj, callback, *) {
        try guiObj.Destroy()
        try callback.Call()
        catch as err
            MsgBox("Action failed.`n`n" err.Message, this.Title, "Icon!")
    }

    FooterExplorerAction(*) {
        paths := this.GetSelectedPaths()
        if paths.Length
            this.OpenPathsInExplorer(paths)
        else
            this.OpenCurrentInExplorer()
    }

    FooterEverythingAction(*) {
        paths := this.GetSelectedPaths()
        this.OpenPathsInEverything(paths.Length ? paths : [this.CurrentPath])
    }

    FooterVSCodeAction(*) {
        paths := this.GetSelectedPaths()
        this.OpenPathsInVSCode(paths.Length ? paths : [this.CurrentPath])
    }

    FooterRunAction(*) {
        paths := this.GetSelectedPaths()
        if paths.Length
            this.OpenPathsDefault(paths)
        else
            this.OpenCurrentInExplorer()
    }

    OpenPathsDefault(paths, *) {
        for path in paths
            this.OpenPathDefault(path)
    }

    OpenPathsInExplorer(paths, *) {
        for path in paths {
            try {
                if DirExist(path)
                    Run("explorer.exe " Quote(path))
                else if FileExist(path)
                    Run("explorer.exe /select," Quote(path))
            }
        }
    }

    OpenCurrentInExplorer(*) {
        if DirExist(this.CurrentPath)
            try Run("explorer.exe " Quote(this.CurrentPath))
    }

    OpenPathsInEverything(paths, *) {
        exe := this.FindEverything()
        if (exe = "") {
            MsgBox(
                "Everything was not found. Install Everything 1.5 or place Everything.exe beside this script.",
                this.Title, "Icon!"
            )
            return
        }
        for path in paths {
            folder := DirExist(path) ? path : this.ParentDirectory(path)
            if (folder != "")
                try Run(Quote(exe) " -path " Quote(folder))
        }
    }

    FindEverything() {
        static cached := "__unset__"
        if (cached != "__unset__")
            return cached
        candidates := [
            A_ScriptDir "\Everything.exe",
            A_ScriptDir "\Everything64.exe",
            A_ProgramFiles "\Everything 1.5a\Everything64.exe",
            A_ProgramFiles "\Everything\Everything.exe",
            EnvGet("LOCALAPPDATA") "\Everything\Everything.exe"
        ]
        for candidate in candidates {
            if FileExist(candidate) {
                cached := candidate
                return cached
            }
        }
        try cached := RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Everything.exe")
        catch
            cached := ""
        return FileExist(cached) ? cached : ""
    }

    OpenPathsInVSCode(paths, *) {
        exe := this.FindVSCode()
        for path in paths {
            try {
                if (exe != "")
                    Run(Quote(exe) " --reuse-window " Quote(path))
                else
                    Run("code --reuse-window " Quote(path))
                if FileExist(path) && !DirExist(path)
                    this.Store.RecordFileUse(path, KindFromPath(path), "vscode")
            } catch as err {
                MsgBox("VS Code could not be opened.`n`n" err.Message, this.Title, "Icon!")
                return
            }
        }
        this.QueueRefresh()
    }

    FindVSCode() {
        static cached := "__unset__"
        if (cached != "__unset__")
            return cached
        candidates := [
            EnvGet("LOCALAPPDATA") "\Programs\Microsoft VS Code\Code.exe",
            A_ProgramFiles "\Microsoft VS Code\Code.exe"
        ]
        for candidate in candidates {
            if FileExist(candidate) {
                cached := candidate
                return cached
            }
        }
        try cached := RegRead("HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Code.exe")
        catch
            cached := ""
        return cached
    }

    OpenPathsInTerminal(paths, *) {
        seen := Map()
        for path in paths {
            folder := DirExist(path) ? path : this.ParentDirectory(path)
            if (folder = "" || seen.Has(StrLower(folder)))
                continue
            seen[StrLower(folder)] := true
            try Run("wt.exe -d " Quote(folder))
            catch
                try Run("powershell.exe -NoExit -Command Set-Location -LiteralPath " Quote(folder))
        }
    }

    CopyPaths(paths, *) {
        text := ""
        for path in paths
            text .= (text = "" ? "" : "`r`n") path
        A_Clipboard := text
        this.SetStatus("Copied " paths.Length " path" (paths.Length = 1 ? "" : "s"))
    }

    ToggleProjectFavorite(path, *) {
        this.Store.ToggleFolderFavorite(path)
        this.RefreshProjects()
    }

    ToggleFileFavorite(paths, *) {
        for path in paths {
            this.Store.EnsureFile(path, DirExist(path) ? "folder" : KindFromPath(path))
            this.Store.ToggleFileFlag(path, "favorite")
        }
        this.RefreshView()
    }

    ToggleAlwaysStart(paths, *) {
        for path in paths {
            if (KindFromPath(path) != "ahk")
                continue
            this.Store.EnsureFile(path, "ahk")
            this.Store.ToggleFileFlag(path, "always_start")
        }
        this.RefreshView()
    }

    EditMetadata(path, *) {
        if (path = "")
            return
        rows := this.Store.Query("SELECT tags,notes FROM file_stats WHERE path=?", path)
        tags := rows.Length ? rows[1][1] : ""
        notes := rows.Length ? rows[1][2] : ""
        meta := Gui("+Owner" this.MainGui.Hwnd, "Script tags and notes")
        meta.SetFont("s9", "Segoe UI")
        meta.AddText("xm ym w560", path)
        meta.AddText("xm y+10", "Tags")
        tagsEdit := meta.AddEdit("xm y+4 w560", tags)
        meta.AddText("xm y+10", "Notes")
        notesEdit := meta.AddEdit("xm y+4 w560 r7 VScroll", notes)
        save := meta.AddButton("xm y+10 w90 Default", "Save")
        cancel := meta.AddButton("x+8 w90", "Cancel")
        save.OnEvent("Click", (*) => this.SaveMetadataDialog(meta, path, tagsEdit.Value, notesEdit.Value))
        cancel.OnEvent("Click", (*) => meta.Destroy())
        meta.Show("AutoSize")
    }

    SaveMetadataDialog(guiObj, path, tags, notes, *) {
        this.Store.SaveMetadata(path, tags, notes)
        guiObj.Destroy()
        this.RefreshView()
    }

    RemoveFromHub(paths, *) {
        answer := MsgBox("Remove the selected item(s) from Script Hub history?`n`nFiles are not deleted.", this.Title, "YesNo Icon?")
        if (answer != "Yes")
            return
        for path in paths
            this.Store.RemoveFile(path)
        this.RefreshView()
    }

    RunAhk(path, asAdmin := false, reason := "manager", *) {
        path := NormalizePath(path)
        if !FileExist(path) {
            MsgBox("The script no longer exists:`n`n" path, this.Title, "Icon!")
            return false
        }
        SplitPath(path, , &workingDir)
        command := Quote(A_AhkPath) " " Quote(path)
        if asAdmin
            command := "*RunAs " command
        try Run(command, workingDir, , &pid)
        catch as err {
            MsgBox("Could not run the script.`n`n" err.Message, this.Title, "Icon!")
            return false
        }
        this.Store.RecordFileUse(path, "ahk", reason, pid)
        if pid
            this.SeenPids[pid] := StrLower(path)
        this.SetStatus("Started " this.PathDisplayName(path) (pid ? " | PID " pid : ""))
        SetTimer(this.ScriptPollCallback, -200)
        return true
    }

    RunPython(path, *) {
        path := NormalizePath(path)
        if !FileExist(path)
            return false
        SplitPath(path, , &workingDir)
        try Run("py " Quote(path), workingDir, , &pid)
        catch {
            try Run("python " Quote(path), workingDir, , &pid)
            catch as err {
                MsgBox("Could not run the Python file.`n`n" err.Message, this.Title, "Icon!")
                return false
            }
        }
        this.Store.RecordFileUse(path, "python", "run", pid)
        this.SetStatus("Started " this.PathDisplayName(path))
        return true
    }

    RunPathsAhk(paths, *) {
        for path in paths
            this.RunAhk(path)
        this.QueueRefresh()
    }

    RunPathsAhkAdmin(paths, *) {
        for path in paths
            this.RunAhk(path, true, "run_admin")
        this.QueueRefresh()
    }

    RunPathsPython(paths, *) {
        for path in paths
            this.RunPython(path)
        this.QueueRefresh()
    }

    RestartPaths(paths, *) {
        this.StopPaths(paths, false)
        Sleep(120)
        this.RunPathsAhk(paths)
    }

    StopPaths(paths, refresh := true, *) {
        wanted := Map()
        for path in paths
            wanted[StrLower(NormalizePath(path))] := true
        stopped := 0
        for pid, info in this.CloneMap(this.Running) {
            if !wanted.Has(StrLower(info.Path))
                continue
            closed := false
            try {
                for hwnd in WinGetList("ahk_pid " pid " ahk_class AutoHotkey") {
                    WinClose("ahk_id " hwnd)
                    closed := true
                    break
                }
            }
            if closed {
                try ProcessWaitClose(pid, 0.8)
            }
            if ProcessExist(pid) {
                try ProcessClose(pid)
            }
            stopped += 1
        }
        this.SetStatus("Stopped " stopped " script instance" (stopped = 1 ? "" : "s"))
        this.ScanRunningScripts()
        if refresh
            this.RefreshView()
    }

    AnyRunning(paths) {
        for path in paths {
            if this.RunningCount(path)
                return true
        }
        return false
    }

    RunningCount(path) {
        key := StrLower(NormalizePath(path))
        count := 0
        for pid, info in this.Running {
            if (StrLower(info.Path) = key)
                count += 1
        }
        return count
    }

    ScanRunningScripts(*) {
        current := Map()
        try {
            for hwnd in WinGetList("ahk_class AutoHotkey") {
                try {
                    title := WinGetTitle("ahk_id " hwnd)
                    pid := WinGetPID("ahk_id " hwnd)
                } catch {
                    continue
                }
                path := this.ParseAhkWindowTitle(title)
                if (pid && path != "" && StrLower(path) != StrLower(A_ScriptFullPath))
                    current[pid] := {Path:path, Hwnd:hwnd}
            }
        }

        ; WMI covers scripts that changed or hid their standard main title.
        try {
            wmi := ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
            for proc in wmi.ExecQuery(
                "SELECT ProcessId,Name,ExecutablePath,CommandLine FROM Win32_Process WHERE Name LIKE 'AutoHotkey%.exe'"
            ) {
                pid := proc.ProcessId + 0
                if !pid || current.Has(pid)
                    continue
                path := this.ExtractAhkPath(proc.CommandLine "")
                if (path != "" && StrLower(path) != StrLower(A_ScriptFullPath))
                    current[pid] := {Path:path, Hwnd:0}
            }
        }

        changed := !this.RunningMapsEqual(this.Running, current)
        for pid, info in current {
            if !this.SeenPids.Has(pid) {
                try this.Store.RecordFileUse(info.Path, "ahk", "observed", pid)
                this.SeenPids[pid] := StrLower(info.Path)
            }
        }
        for pid, key in this.CloneMap(this.SeenPids) {
            if !current.Has(pid) && !ProcessExist(pid)
                this.SeenPids.Delete(pid)
        }
        this.Running := current
        if changed && this.GuiBuilt && this.IsVisible() && this.ViewMode = "Scripts"
            this.QueueRefresh()
    }

    ParseAhkWindowTitle(title) {
        if RegExMatch(title, "i)^(.*\.ahk) - AutoHotkey v2(?:\.|$)", &match)
            return NormalizePath(match[1])
        return ""
    }

    ExtractAhkPath(commandLine) {
        if (commandLine = "")
            return ""
        args := this.CommandLineToArray(commandLine)
        for argument in args {
            if (RegExMatch(argument, "i)\.ahk$") && RegExMatch(argument, "i)^[A-Z]:\\|^\\\\"))
                return NormalizePath(argument)
        }
        return ""
    }

    CommandLineToArray(commandLine) {
        args := []
        argc := 0
        ptr := DllCall("Shell32\CommandLineToArgvW", "Str", commandLine, "Int*", &argc, "Ptr")
        if !ptr
            return args
        try {
            Loop argc {
                itemPtr := NumGet(ptr, (A_Index - 1) * A_PtrSize, "Ptr")
                args.Push(StrGet(itemPtr))
            }
        } finally {
            DllCall("LocalFree", "Ptr", ptr, "Ptr")
        }
        return args
    }

    RunningMapsEqual(first, second) {
        if (first.Count != second.Count)
            return false
        for pid, info in second {
            if !first.Has(pid) || StrLower(first[pid].Path) != StrLower(info.Path)
                return false
        }
        return true
    }

    CloneMap(source) {
        clone := Map()
        for key, value in source
            clone[key] := value
        return clone
    }

    RestoreScripts(*) {
        this.ScanRunningScripts()
        wanted := Map()
        for row in this.Store.GetRunningSnapshot()
            wanted[StrLower(row[1])] := {Path:row[1], Count:row[2] + 0}
        for row in this.Store.Query("SELECT path FROM file_stats WHERE kind='ahk' AND always_start=1 AND removed=0") {
            key := StrLower(row[1])
            if !wanted.Has(key)
                wanted[key] := {Path:row[1], Count:1}
        }
        for key, item in wanted {
            if !FileExist(item.Path)
                continue
            needed := Max(0, item.Count - this.RunningCount(item.Path))
            Loop needed {
                this.RunAhk(item.Path, false, "session_restore")
                Sleep(40)
            }
        }
    }

    SaveRunningSnapshot() {
        counts := Map()
        for pid, info in this.Running {
            path := info.Path
            if (StrLower(path) = StrLower(A_ScriptFullPath))
                continue
            if counts.Has(path)
                counts[path] += 1
            else
                counts[path] := 1
        }
        this.Store.SaveRunningSnapshot(counts)
    }

    AddScript(*) {
        path := FileSelect(1, this.CurrentPath, "Add an AutoHotkey v2 script", "AutoHotkey scripts (*.ahk)")
        if (path = "")
            return
        this.Store.EnsureFile(NormalizePath(path), "ahk")
        this.ViewCombo.Text := "Scripts"
        this.ViewMode := "Scripts"
        this.RefreshView()
    }

    ImportScripts(*) {
        folder := DirSelect("*" this.CurrentPath, 3, "Import AutoHotkey scripts")
        if (folder = "")
            return
        count := 0
        Loop Files folder "\*.ahk", "FR" {
            this.Store.EnsureFile(NormalizePath(A_LoopFileFullPath), "ahk")
            count += 1
        }
        this.ViewCombo.Text := "Scripts"
        this.ViewMode := "Scripts"
        this.RefreshView()
        this.SetStatus("Imported " count " AutoHotkey scripts")
    }

    ShowMoreMenu(*) {
        menuObj := Menu()
        menuObj.Add("Show Folder view", (*) => this.SelectView("Folder"))
        menuObj.Add("Show frequency launcher", (*) => this.SelectView("Launcher"))
        menuObj.Add("Show Script Hub", (*) => this.SelectView("Scripts"))
        menuObj.Add()
        menuObj.Add("Add AutoHotkey script...", ObjBindMethod(this, "AddScript"))
        menuObj.Add("Import scripts from folder...", ObjBindMethod(this, "ImportScripts"))
        menuObj.Add("Open Terminal here", (*) => this.OpenPathsInTerminal([this.CurrentPath]))
        menuObj.Add("Open database folder", (*) => Run("explorer.exe /select," Quote(this.Store.Path)))
        menuObj.Add()
        menuObj.Add("Clear filters", ObjBindMethod(this, "ClearFilters"))
        menuObj.Add("Keyboard shortcuts", ObjBindMethod(this, "ShowHelp"))
        menuObj.Add("Exit Manager v7", (*) => ExitApp())
        menuObj.Show()
    }

    SelectView(name, *) {
        this.ViewCombo.Text := name
        this.ViewMode := name
        this.RefreshView()
    }

    ClearFilters(*) {
        this.FilterEdit.Value := ""
        this.TypeCombo.Choose(1)
        this.RecursiveCheck.Value := 0
        this.HiddenCheck.Value := 0
        this.RegexCheck.Value := 0
        this.RefreshView()
    }

    ShowHelp(*) {
        MsgBox(
            "Manager v7 shortcuts`n`n"
            . "Ctrl+Alt+E`tShow manager`n"
            . "Ctrl+Win+A`tOpen Script Hub view`n"
            . "Ctrl+Alt+Space`tConsole command menu`n"
            . "Alt+Left / Right`tBack / Forward`n"
            . "Alt+Up or Backspace`tParent folder`n"
            . "Ctrl+L`tAddress bar`n"
            . "Ctrl+F`tFilter`n"
            . "F5`tRefresh`n`n"
            . "Folder ranks use (visits x 60 seconds) + foreground Explorer time.",
            this.Title, "Iconi"
        )
    }

    GetSelectedPaths() {
        paths := []
        if !this.GuiBuilt
            return paths
        row := 0
        while (row := this.FileList.GetNext(row)) {
            path := this.FileList.GetText(row, 6)
            if (path != "")
                paths.Push(path)
        }
        return paths
    }

    GetSelectedProjectPath() {
        if !this.GuiBuilt
            return ""
        row := this.ProjectList.GetNext()
        return row ? this.ProjectList.GetText(row, 5) : ""
    }

    UpdateProjectStatus(ctrl, row := 0, *) {
        if !row
            row := ctrl.GetNext()
        if !row
            return
        path := ctrl.GetText(row, 5)
        this.FooterPath.Text := path
        this.StatusBar.SetText("Project: " path, 2)
    }

    UpdateFileStatus(ctrl, row := 0, *) {
        if !row
            row := ctrl.GetNext()
        if !row
            return
        path := ctrl.GetText(row, 6)
        this.FooterPath.Text := path
        kind := DirExist(path) ? "Folder" : this.TypeLabel(KindFromPath(path))
        extra := ""
        if (KindFromPath(path) = "ahk")
            extra := " | " (this.RunningCount(path) ? "Running" : "Stopped")
        this.StatusBar.SetText(kind extra " | " path, 2)
    }

    SetStatus(text) {
        if this.GuiBuilt
            this.StatusBar.SetText(text, 1)
    }

    AttachShellImageList(listView) {
        probe := A_WinDir "\System32\shell32.dll"
        info := Buffer(A_PtrSize + 8 + 520 + 160, 0)
        imageList := DllCall(
            "Shell32\SHGetFileInfoW", "Str", probe, "UInt", 0, "Ptr", info.Ptr,
            "UInt", info.Size, "UInt", 0x4000 | 0x1, "Ptr"
        )
        if !imageList
            return false
        DllCall(
            "SendMessageW", "Ptr", listView.Hwnd, "UInt", 0x1003,
            "Ptr", 1, "Ptr", imageList, "Ptr"
        )
        return true
    }

    GetShellIconIndex(path) {
        info := Buffer(A_PtrSize + 8 + 520 + 160, 0)
        attributes := DirExist(path) ? 0x10 : 0x80
        flags := 0x4000 | 0x1
        if !FileExist(path) && !DirExist(path)
            flags |= 0x10
        result := DllCall(
            "Shell32\SHGetFileInfoW", "Str", path, "UInt", attributes, "Ptr", info.Ptr,
            "UInt", info.Size, "UInt", flags, "Ptr"
        )
        return result ? NumGet(info, A_PtrSize, "Int") : -1
    }

    RowColorForKind(kind) {
        switch kind {
            case "folder": return this.ColorRef("FFFBE0")
            case "ahk": return this.ColorRef("E6F5E3")
            case "python": return this.ColorRef("E3EEFF")
            case "code": return this.ColorRef("F0E9FF")
            case "executable": return this.ColorRef("FFE8E8")
            case "image": return this.ColorRef("FBEAFF")
            default: return this.ColorRef("FFFFFF")
        }
    }

    ColorRef(hex) {
        rgb := Integer("0x" hex)
        return ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF)
    }

    OnNotify(wParam, lParam, msg, hwnd) {
        ; NM_CUSTOMDRAW supplies subtle per-file-type row backgrounds while
        ; preserving normal selection/focus drawing.
        try sourceHwnd := NumGet(lParam, 0, "Ptr")
        catch
            return
        if !this.RowColors.Has(sourceHwnd)
            return
        code := NumGet(lParam, A_PtrSize * 2, "Int")
        if (code != -12)
            return
        headerSize := A_PtrSize = 8 ? 24 : 12
        stage := NumGet(lParam, headerSize, "UInt")
        if (stage = 1)
            return 0x20
        if (stage = 0x10001)
            return 0x20
        if (stage = 0x30001) {
            itemOffset := A_PtrSize = 8 ? 56 : 36
            colorOffset := A_PtrSize = 8 ? 84 : 52
            rowIndex := NumGet(lParam, itemOffset, "UPtr") + 1
            colors := this.RowColors[sourceHwnd]
            if colors.Has(rowIndex)
                NumPut("UInt", colors[rowIndex], lParam + colorOffset)
            return 0
        }
    }

    FormatDuration(totalSeconds) {
        totalSeconds := Max(0, totalSeconds + 0)
        if (totalSeconds < 60)
            return totalSeconds "s"
        if (totalSeconds < 3600)
            return Floor(totalSeconds / 60) "m"
        hours := Floor(totalSeconds / 3600)
        minutes := Floor(Mod(totalSeconds, 3600) / 60)
        return hours "h" (minutes ? " " minutes "m" : "")
    }

    RelativeTime(stamp) {
        if (stamp = "")
            return "Never"
        try {
            normalized := RegExReplace(stamp, "[-: ]")
            seconds := DateDiff(A_Now, normalized, "Seconds")
            if (seconds < 60)
                return "now"
            if (seconds < 3600)
                return Floor(seconds / 60) "m"
            if (seconds < 86400)
                return Floor(seconds / 3600) "h"
            return Floor(seconds / 86400) "d"
        }
        return stamp
    }

    FormatBytes(bytes) {
        bytes += 0
        if (bytes < 1024)
            return bytes " B"
        if (bytes < 1048576)
            return Round(bytes / 1024, 1) " KB"
        if (bytes < 1073741824)
            return Round(bytes / 1048576, 1) " MB"
        return Round(bytes / 1073741824, 1) " GB"
    }

    FormatFileTime(stamp) {
        if (stamp = "")
            return ""
        try return FormatTime(stamp, "yyyy-MM-dd HH:mm")
        catch
            return stamp
    }

    TypeLabel(kind) {
        switch kind {
            case "folder": return "Folder"
            case "ahk": return "AutoHotkey"
            case "python": return "Python"
            case "code": return "Code"
            case "document": return "Document"
            case "image": return "Image"
            case "video": return "Video"
            case "audio": return "Audio"
            case "archive": return "Archive"
            case "executable": return "Executable"
            default: return "File"
        }
    }

    IsCodeKind(kind) {
        return kind = "ahk" || kind = "python" || kind = "code"
    }

    PathDisplayName(path) {
        path := RTrim(path, "\")
        SplitPath(path, &name)
        return name != "" ? name : path
    }

    ParentDirectory(path) {
        path := NormalizePath(path)
        if (path = "")
            return ""
        SplitPath(path, , &parent)
        return parent
    }

    Clamp(value, minimum, maximum) {
        return Min(maximum, Max(minimum, value))
    }

    Shutdown(exitReason := "", exitCode := 0, *) {
        try SetTimer(this.ExplorerPollCallback, 0)
        try SetTimer(this.ScriptPollCallback, 0)
        try this.FlushExplorerSegment(true)
        try this.ShutdownExplorerWatcher()
        try this.SaveRunningSnapshot()
        try this.Store.SetState("current_path", this.CurrentPath)
    }

    static NormalizePath(path) {
        path := Trim(path "", " `t`r`n" Chr(34))
        if (path = "")
            return ""
        path := StrReplace(path, "/", "\")
        bufferObj := Buffer(32768 * 2, 0)
        length := DllCall(
            "GetFullPathNameW", "Str", path, "UInt", 32768,
            "Ptr", bufferObj.Ptr, "Ptr", 0, "UInt"
        )
        if (length > 0 && length < 32768)
            path := StrGet(bufferObj.Ptr)
        if (StrLen(path) > 3)
            path := RTrim(path, "\")
        return path
    }

    static KindFromPath(path) {
        if DirExist(path)
            return "folder"
        SplitPath(path, , , &extension)
        extension := StrLower(extension)
        if (extension = "ahk")
            return "ahk"
        if (extension = "py" || extension = "pyw")
            return "python"
        if InStr(",js,jsx,ts,tsx,css,scss,html,htm,json,jsonc,xml,yaml,yml,toml,ini,md,sql,cs,cpp,c,h,hpp,java,go,rs,php,rb,ps1,bat,cmd,sh,lua,vbs,", "," extension ",")
            return "code"
        if InStr(",txt,rtf,pdf,doc,docx,xls,xlsx,ppt,pptx,csv,odt,ods,", "," extension ",")
            return "document"
        if InStr(",png,jpg,jpeg,gif,bmp,webp,svg,ico,tif,tiff,", "," extension ",")
            return "image"
        if InStr(",mp4,mkv,avi,mov,wmv,webm,m4v,", "," extension ",")
            return "video"
        if InStr(",mp3,wav,flac,aac,m4a,ogg,opus,wma,", "," extension ",")
            return "audio"
        if InStr(",zip,7z,rar,tar,gz,bz2,xz,", "," extension ",")
            return "archive"
        if InStr(",exe,msi,com,scr,", "," extension ",")
            return "executable"
        return "file"
    }

    static NowStamp() {
        return FormatTime(, "yyyy-MM-dd HH:mm:ss")
    }
}

; Short global helpers keep expression-heavy GUI code readable.
NormalizePath(path) => ManagerV7.NormalizePath(path)
KindFromPath(path) => ManagerV7.KindFromPath(path)
NowStamp() => ManagerV7.NowStamp()
Quote(value) => Chr(34) value Chr(34)
SmokeLog(text) {
    global SmokeTestMode
    if SmokeTestMode
        FileAppend(text "`n", "*")
}

class CompactCommandMenu {
    __New(store, manager) {
        this.Store := store
        this.Manager := manager
        this.Mode := this.Store.GetState("command_mode", "Run")
        this.InvocationHwnd := 0
        this.ConsoleProcesses := Map(
            "windowsterminal.exe", 1, "powershell.exe", 1, "pwsh.exe", 1,
            "cmd.exe", 1, "conemu.exe", 1, "conemu64.exe", 1,
            "mintty.exe", 1, "wezterm-gui.exe", 1, "alacritty.exe", 1
        )
        Hotkey("^!Space", ObjBindMethod(this, "Show"))
        Hotkey("^!+Space", ObjBindMethod(this, "Show", "Copy"))
        Hotkey("^!r", ObjBindMethod(this, "SendClipboard", true))
        Hotkey("^!v", ObjBindMethod(this, "SendClipboard", false))
    }

    Show(modeOverride := "", *) {
        this.InvocationHwnd := WinExist("A")
        oldMode := this.Mode
        if (modeOverride != "")
            this.Mode := modeOverride
        menuObj := Menu()
        menuObj.Add("Open Manager v7", ObjBindMethod(this.Manager, "Show"))
        menuObj.Add("Open Script Hub", ObjBindMethod(this.Manager, "ShowScripts"))
        menuObj.Add("Send mode: " this.Mode, this.BuildModeMenu())
        menuObj.Add()

        custom := this.Store.Query(
            "SELECT id,label,command,use_count FROM custom_commands ORDER BY use_count DESC,label COLLATE NOCASE"
        )
        if custom.Length {
            customMenu := Menu()
            for row in custom
                customMenu.Add(this.MenuSafe(row[2]), ObjBindMethod(this, "ExecuteCustom", row[1], row[3]))
            menuObj.Add("Custom commands", customMenu)
        }

        history := this.Store.Query(
            "SELECT command,use_count FROM command_history ORDER BY last_used DESC LIMIT 20"
        )
        if history.Length {
            historyMenu := Menu()
            for row in history
                historyMenu.Add(this.MenuSafe(this.Truncate(row[1], 90)), ObjBindMethod(this, "Execute", row[1]))
            menuObj.Add("Recent commands", historyMenu)
        }

        common := Menu()
        for item in [
            ["git status", "git status"], ["git log --oneline -20", "git log --oneline -20"],
            ["Python version", "python --version"], ["List Python environments", "py -0p"],
            ["npm run dev", "npm run dev"], ["npm test", "npm test"],
            ["Current directory", "cd"], ["Directory listing", "dir"]
        ]
            common.Add(item[1], ObjBindMethod(this, "Execute", item[2]))
        menuObj.Add("Common commands", common)
        menuObj.Add()
        menuObj.Add("Add custom command...", ObjBindMethod(this, "AddCustom"))
        menuObj.Add("Open a new terminal", (*) => this.OpenTerminal())
        menuObj.Add("Exit Manager v7", (*) => ExitApp())
        menuObj.Show()
        this.Mode := oldMode
    }

    BuildModeMenu() {
        result := Menu()
        result.Add("Paste + Enter", ObjBindMethod(this, "SetMode", "Run"))
        result.Add("Paste only", ObjBindMethod(this, "SetMode", "Paste"))
        result.Add("Copy only", ObjBindMethod(this, "SetMode", "Copy"))
        switch this.Mode {
            case "Run": result.Check("Paste + Enter")
            case "Paste": result.Check("Paste only")
            case "Copy": result.Check("Copy only")
        }
        return result
    }

    SetMode(mode, *) {
        this.Mode := mode
        this.Store.SetState("command_mode", mode)
        TrayTip("Command mode", mode, 1)
    }

    ExecuteCustom(id, command, *) {
        this.Store.Execute(
            "UPDATE custom_commands SET use_count=use_count+1,last_used=? WHERE id=?", NowStamp(), id
        )
        this.Execute(command)
    }

    Execute(command, *) {
        command := Trim(command)
        if (command = "")
            return
        now := NowStamp()
        this.Store.Execute(
            "INSERT INTO command_history(command,use_count,last_used) VALUES(?,1,?) "
            . "ON CONFLICT(command) DO UPDATE SET use_count=use_count+1,last_used=excluded.last_used",
            command, now
        )
        A_Clipboard := command
        if (this.Mode = "Copy") {
            TrayTip("Command copied", this.Truncate(command, 100), 1)
            return
        }
        target := this.InvocationHwnd
        if !this.IsConsole(target)
            target := this.OpenTerminal()
        if !target
            return
        try {
            WinActivate("ahk_id " target)
            WinWaitActive("ahk_id " target, , 2)
            Send("^v")
            if (this.Mode = "Run")
                Send("{Enter}")
        }
    }

    SendClipboard(pressEnter := false, *) {
        hwnd := WinExist("A")
        if !this.IsConsole(hwnd)
            hwnd := this.OpenTerminal()
        if !hwnd
            return
        try {
            WinActivate("ahk_id " hwnd)
            Send("^v")
            if pressEnter
                Send("{Enter}")
        }
    }

    IsConsole(hwnd) {
        if !hwnd
            return false
        try process := StrLower(WinGetProcessName("ahk_id " hwnd))
        catch
            return false
        return this.ConsoleProcesses.Has(process)
    }

    OpenTerminal(*) {
        before := WinGetList("ahk_exe WindowsTerminal.exe")
        try Run("wt.exe -d " Quote(this.Manager.CurrentPath))
        catch {
            try Run("powershell.exe -NoExit", this.Manager.CurrentPath, , &pid)
            catch
                return 0
            try {
                WinWait("ahk_pid " pid, , 3)
                return WinExist("ahk_pid " pid)
            }
            return 0
        }
        Loop 30 {
            Sleep(50)
            try {
                for hwnd in WinGetList("ahk_exe WindowsTerminal.exe") {
                    found := false
                    for oldHwnd in before {
                        if (oldHwnd = hwnd) {
                            found := true
                            break
                        }
                    }
                    if !found
                        return hwnd
                }
                active := WinExist("A")
                if this.IsConsole(active)
                    return active
            }
        }
        try return WinExist("ahk_exe WindowsTerminal.exe")
        catch
            return 0
    }

    AddCustom(*) {
        labelResult := InputBox("Menu label:", "Add custom command", "w480 h130")
        if (labelResult.Result != "OK" || Trim(labelResult.Value) = "")
            return
        commandResult := InputBox("Command:", "Add custom command", "w600 h150")
        if (commandResult.Result != "OK" || Trim(commandResult.Value) = "")
            return
        this.Store.Execute(
            "INSERT INTO custom_commands(label,command) VALUES(?,?)",
            Trim(labelResult.Value), Trim(commandResult.Value)
        )
    }

    MenuSafe(text) {
        return StrReplace(text, "&", "&&")
    }

    Truncate(text, maximum) {
        return StrLen(text) > maximum ? SubStr(text, 1, maximum - 1) "..." : text
    }
}

try {
    SmokeLog("startup:begin")
    global ManagerApp := ManagerV7()
    SmokeLog("startup:manager")
    global CommandMenuApp := CompactCommandMenu(ManagerApp.Store, ManagerApp)
    SmokeLog("startup:commands")
    if SmokeTestMode {
        smokeKey := "__smoke?key"
        smokeValue := "SQLite handles ? and ' safely"
        ManagerApp.Store.SetState(smokeKey, smokeValue)
        if (ManagerApp.Store.GetState(smokeKey) != smokeValue)
            throw Error("SQLite parameter round-trip failed")
        ManagerApp.Store.Execute("DELETE FROM app_state WHERE key=?", smokeKey)
        ManagerApp.Shutdown()
        ExitApp()
    }
    ManagerApp.Show()
} catch as StartupError {
    if SmokeTestMode
        throw StartupError
    MsgBox(
        "Manager v7 could not start.`n`n" StartupError.Message "`n`nLine: " StartupError.Line,
        "Manager v7", "Iconx"
    )
    ExitApp()
}
