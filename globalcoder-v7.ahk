#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Include SQLiteDB.ahk

; ============================================================================
; GlobalCoder v7
; A portable Windows automation, project, and knowledge manager.
;
; Structure:
;   1. Globals and paths
;   2. All classes
;   3. Startup and migration
;   4. Feature functions, grouped by feature
;   5. Shared helpers
;   6. Context hotkeys
; ============================================================================
;
; REGISTERED HOTKEYS
;
; Global (available from any window):
;   Ctrl + Right Shift  - Open the compact native GlobalCoder menuD
;   Alt  + Right Shift  - Open the compact native GlobalCoder menu
;   Ctrl + Space        - Open Google search and log the query to SQLite
;   Ctrl + Alt + N      - Open the New Project wizard
;   Ctrl + Alt + L      - Open the Learning Center
;   Ctrl + Alt + R      - Rebuild the bounded native menu
;   Ctrl + Alt + M      - Open the navigable GlobalCoder library browser
;   Ctrl + Alt + K      - Search the knowledge web
;   Ctrl + Alt + A      - Open the Windows instruction-language console
;
; GlobalCoder library browser (only while that browser is active):
;   Up / K              - Select the previous item
;   Down / J            - Select the next item
;   Enter / H           - Open or execute the selected item
;   Backspace / F       - Return to the previous folder/menu
;   Escape              - Close the library browser
;
; GUT/shared overlay (only while an overlay is active):
;   Escape              - Close the overlay
;   Ctrl + P            - Pin or unpin the overlay
;   Right-click + drag  - Move the overlay from any point inside it
;
; Itemized GUT overlay (lists such as Recent Projects):
;   Up / Down           - Move the selection
;   Enter               - Open or execute the selected row
;   Ctrl + C            - Copy the overlay's complete content
;
; Input GUT overlay:
;   Ctrl + Enter        - Submit the current input
;
; Tutorial StepCanvas (only while StepCanvas is active):
;   Left / Right        - Show the previous or next tutorial step
;   Ctrl + C            - Copy the current command
;
; REGISTERED HOTSTRINGS (typed triggers, not modifier-key hotkeys):
;   jjj                 - Open the navigable GlobalCoder library browser
;   ggg                 - Open Google search and log the query to SQLite

; --- Portable paths ----------------------------------------------------------
global GC_DATA_DIR := A_ScriptDir "\data"
global GC_PROJECT_DIR := GC_DATA_DIR "\projs"
global GC_DB_PATH := GC_DATA_DIR "\globalcoder-v7.db"
global GC_LIBRARY_DIR := A_ScriptDir "\CustomMenuFiles"
global GC_SQLITE_WRAPPER := A_ScriptDir "\SQLiteDB.ahk"
global GC_SQLITE_DLL := A_ScriptDir "\sqlite3.dll"

; --- Runtime settings --------------------------------------------------------
global GC_OverlayTimeout := 5000
global GC_OverlayOpacity := 235
global GC_OverlayWidth := 600
global GC_OverlayHeight := 400
global GC_VSCodePath := "code"
global GC_SublimePath := "C:\Program Files\Sublime Text\sublime_text.exe"
global GC_GitBashPath := "C:\Program Files\Git\git-bash.exe"

; --- Runtime state -----------------------------------------------------------
global GC_MainMenu := ""
global GC_CustomMenuGui := ""
global GC_MenuList := ""
global GC_MenuVisible := false
global GC_MenuItems := []
global GC_MenuIndex := 1
global GC_MenuStack := []
global GC_CallingWindowHwnd := 0
global GC_ActiveStepCanvas := ""

; ============================================================================
; ALL CLASSES
; ============================================================================

class GlobalCoderDatabase {
    static Connection := ""
    static Ready := false

    static Init(databasePath) {
        if !DirExist(GC_DATA_DIR)
            DirCreate(GC_DATA_DIR)

        this.Connection := SQLiteDB()
        if !this.Connection.OpenDB(databasePath, "W", true)
            throw Error("Could not open GlobalCoder database: " . this.Connection.ErrorMsg)

        this.Connection.SetTimeout(5000)
        this.Exec("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;")
        this.CreateSchema()
        this.Ready := true
        this.SeedDefaults()
    }

    static CreateSchema() {
        schema := "
        (
        CREATE TABLE IF NOT EXISTS settings (
            section TEXT NOT NULL,
            key TEXT NOT NULL,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
            PRIMARY KEY (section, key)
        /*close*/);

        CREATE TABLE IF NOT EXISTS queries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            query TEXT NOT NULL,
            provider TEXT NOT NULL DEFAULT 'google',
            context TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
        /*close*/);

        CREATE TABLE IF NOT EXISTS recent_projects (
            path TEXT PRIMARY KEY,
            name TEXT NOT NULL DEFAULT '',
            project_type TEXT NOT NULL DEFAULT '',
            open_count INTEGER NOT NULL DEFAULT 1,
            last_opened TEXT NOT NULL DEFAULT (datetime('now','localtime'))
        /*close*/);

        CREATE TABLE IF NOT EXISTS actions (
            name TEXT PRIMARY KEY,
            function_name TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
        /*close*/);

        CREATE TABLE IF NOT EXISTS hotstrings (
            trigger TEXT PRIMARY KEY,
            replacement TEXT NOT NULL,
            category TEXT NOT NULL DEFAULT 'Hotstrings',
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
        /*close*/);

        CREATE TABLE IF NOT EXISTS content_items (
            path TEXT PRIMARY KEY,
            title TEXT NOT NULL DEFAULT '',
            content_type TEXT NOT NULL DEFAULT 'text',
            content TEXT NOT NULL DEFAULT '',
            source_mtime TEXT NOT NULL DEFAULT '',
            metadata TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
        /*close*/);

        CREATE TABLE IF NOT EXISTS tutorial_steps (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            language TEXT NOT NULL,
            project_type TEXT NOT NULL,
            step_no INTEGER NOT NULL,
            command TEXT NOT NULL DEFAULT '',
            directions TEXT NOT NULL DEFAULT '',
            input_needed TEXT NOT NULL DEFAULT '',
            explanation TEXT NOT NULL DEFAULT '',
            UNIQUE(language, project_type, step_no)
        /*close*/);

        CREATE TABLE IF NOT EXISTS knowledge_nodes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            node_type TEXT NOT NULL DEFAULT 'fact',
            language TEXT NOT NULL DEFAULT '',
            feature TEXT NOT NULL DEFAULT '',
            content TEXT NOT NULL DEFAULT '',
            confidence REAL NOT NULL DEFAULT 0.5,
            importance REAL NOT NULL DEFAULT 1.0,
            use_count INTEGER NOT NULL DEFAULT 0,
            last_used TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
        /*close*/);

        CREATE TABLE IF NOT EXISTS knowledge_edges (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            from_node_id INTEGER NOT NULL,
            to_node_id INTEGER NOT NULL,
            relation TEXT NOT NULL,
            strength REAL NOT NULL DEFAULT 1.0,
            created_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
            UNIQUE(from_node_id, to_node_id, relation),
            FOREIGN KEY(from_node_id) REFERENCES knowledge_nodes(id) ON DELETE CASCADE,
            FOREIGN KEY(to_node_id) REFERENCES knowledge_nodes(id) ON DELETE CASCADE
        /*close*/);

        CREATE TABLE IF NOT EXISTS knowledge_gaps (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            node_id INTEGER,
            prompt TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'open',
            due_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
            created_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
            resolved_at TEXT,
            FOREIGN KEY(node_id) REFERENCES knowledge_nodes(id) ON DELETE CASCADE
        /*close*/);

        CREATE TABLE IF NOT EXISTS knowledge_reviews (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            node_id INTEGER NOT NULL,
            response TEXT NOT NULL DEFAULT '',
            rating INTEGER NOT NULL DEFAULT 0,
            reviewed_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
            next_review_at TEXT NOT NULL DEFAULT (datetime('now','localtime','+1 day')),
            FOREIGN KEY(node_id) REFERENCES knowledge_nodes(id) ON DELETE CASCADE
        /*close*/);

        CREATE TABLE IF NOT EXISTS activity_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type TEXT NOT NULL,
            detail TEXT NOT NULL DEFAULT '',
            active_window TEXT NOT NULL DEFAULT '',
            idle_ms INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
        /*close*/);

        CREATE TABLE IF NOT EXISTS instruction_commands (
            name TEXT PRIMARY KEY,
            syntax TEXT NOT NULL,
            ahk_mapping TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            example TEXT NOT NULL DEFAULT ''
        /*close*/);

        CREATE TABLE IF NOT EXISTS instruction_programs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            source TEXT NOT NULL,
            run_count INTEGER NOT NULL DEFAULT 0,
            last_run TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
        /*close*/);

        CREATE TABLE IF NOT EXISTS event_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type TEXT NOT NULL,
            detail TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
        /*close*/);

        CREATE TABLE IF NOT EXISTS errors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            message TEXT NOT NULL,
            file TEXT NOT NULL DEFAULT '',
            line INTEGER NOT NULL DEFAULT 0,
            stack TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
        /*close*/);

        CREATE INDEX IF NOT EXISTS idx_queries_created ON queries(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_recent_opened ON recent_projects(last_opened DESC);
        CREATE INDEX IF NOT EXISTS idx_knowledge_lookup ON knowledge_nodes(language, feature, title);
        CREATE INDEX IF NOT EXISTS idx_gaps_due ON knowledge_gaps(status, due_at);
        )"
        this.Exec(schema)
    }

    static SeedDefaults() {
        defaults := [
            ["Overlay", "Timeout", "5000"],
            ["Overlay", "Opacity", "235"],
            ["Overlay", "Width", "600"],
            ["Overlay", "Height", "400"],
            ["Projects", "DefaultRoot", GC_PROJECT_DIR],
            ["Projects", "VSCodePath", "code"],
            ["Projects", "SublimePath", "C:\Program Files\Sublime Text\sublime_text.exe"],
            ["Projects", "GitBashPath", "C:\Program Files\Git\git-bash.exe"],
            ["Knowledge", "PromptOnResume", "1"],
            ["Knowledge", "IdleThresholdMs", "900000"]
        ]
        for row in defaults {
            this.Exec("INSERT OR IGNORE INTO settings(section,key,value) VALUES("
                . this.Q(row[1]) . "," . this.Q(row[2]) . "," . this.Q(row[3]) . ");")
        }

        defaultActions := [
            ["Dump Clipboard", "Action_DumpClipboard", "Store clipboard content in the database for this context"],
            ["New Folder", "Action_NewFolder", "Create a subfolder"],
            ["New File", "Action_NewFile", "Create a physical project or export file and index it"],
            ["Open in Explorer", "Action_OpenFolder", "Open this folder in Explorer"],
            ["Capture Structure", "Action_CaptureStructure", "Display a navigable folder tree"]
        ]
        for row in defaultActions {
            this.Exec("INSERT OR IGNORE INTO actions(name,function_name,description) VALUES("
                . this.Q(row[1]) . "," . this.Q(row[2]) . "," . this.Q(row[3]) . ");")
        }

        commandRows := [
            ["WAIT", "WAIT|milliseconds", "Sleep(milliseconds)", "Pause execution", "WAIT|500"],
            ["RUN", "RUN|target|working-directory", "Run(target, workingDirectory)", "Run a program, document, or URL", "RUN|notepad.exe"],
            ["ACTIVATE", "ACTIVATE|window-title", "WinActivate(title)", "Activate a matching window", "ACTIVATE|Untitled - Notepad"],
            ["WINDOW.WAIT", "WINDOW.WAIT|title|seconds", "WinWait(title,,seconds)", "Wait for a window", "WINDOW.WAIT|Notepad|5"],
            ["WINDOW.CLOSE", "WINDOW.CLOSE|title", "WinClose(title)", "Close a matching window", "WINDOW.CLOSE|Notepad"],
            ["WINDOW.MIN", "WINDOW.MIN|title", "WinMinimize(title)", "Minimize a matching window", "WINDOW.MIN|Notepad"],
            ["WINDOW.MAX", "WINDOW.MAX|title", "WinMaximize(title)", "Maximize a matching window", "WINDOW.MAX|Notepad"],
            ["SEND", "SEND|keys", "Send(keys)", "Send AutoHotkey key syntax", "SEND|^s"],
            ["TEXT", "TEXT|literal text", "SendText(text)", "Type literal text", "TEXT|Hello world"],
            ["CLICK", "CLICK|x|y|button|count", "Click(x,y,button,count)", "Click a screen coordinate", "CLICK|500|300|Left|1"],
            ["MOUSE.MOVE", "MOUSE.MOVE|x|y|speed", "MouseMove(x,y,speed)", "Move the pointer", "MOUSE.MOVE|500|300|10"],
            ["CLIPBOARD", "CLIPBOARD|text", "A_Clipboard := text", "Replace clipboard text", "CLIPBOARD|Reusable text"],
            ["PASTE", "PASTE", "Send('^v')", "Paste the clipboard", "PASTE"],
            ["OPEN", "OPEN|path-or-url", "Run(pathOrUrl)", "Open a path or URL", "OPEN|https://www.autohotkey.com/docs/v2/"],
            ["EXPLORER", "EXPLORER|folder", "Run('explorer.exe folder')", "Open a folder", "EXPLORER|{{projectroot}}"],
            ["OVERLAY", "OVERLAY|title|content", "GUT_Display(title,content)", "Show a GlobalCoder overlay", "OVERLAY|Done|Automation completed"]
        ]
        for row in commandRows {
            this.Exec("INSERT OR IGNORE INTO instruction_commands(name,syntax,ahk_mapping,description,example) VALUES("
                . this.Q(row[1]) . "," . this.Q(row[2]) . "," . this.Q(row[3]) . ","
                . this.Q(row[4]) . "," . this.Q(row[5]) . ");")
        }

        StepRepository.SeedDefaults()
    }

    static Exec(sql) {
        if !this.Connection.Exec(sql)
            throw Error("SQLite error: " . this.Connection.ErrorMsg . "`nSQL: " . SubStr(sql, 1, 600))
        return true
    }

    static Rows(sql, maxRows := 0) {
        if !this.Connection.GetTable(sql, &table, maxRows)
            throw Error("SQLite query error: " . this.Connection.ErrorMsg)
        result := []
        if !IsObject(table) || !table.HasRows
            return result
        for rowData in table.Rows {
            row := Map()
            for index, columnName in table.ColumnNames
                row[columnName] := rowData[index]
            result.Push(row)
        }
        return result
    }

    static Scalar(sql, defaultValue := "") {
        rows := this.Rows(sql, 1)
        if rows.Length = 0
            return defaultValue
        for key, value in rows[1]
            return value
        return defaultValue
    }

    static Q(value) {
        quoted := String(value)
        if !this.Connection.EscapeStr(&quoted, true)
            throw Error("Could not quote SQLite value: " . this.Connection.ErrorMsg)
        return quoted
    }

    static GetSetting(section, key, defaultValue := "") {
        sql := "SELECT value FROM settings WHERE section=" . this.Q(section)
            . " AND key=" . this.Q(key) . " LIMIT 1;"
        return this.Scalar(sql, defaultValue)
    }

    static SetSetting(section, key, value) {
        this.Exec("INSERT INTO settings(section,key,value,updated_at) VALUES("
            . this.Q(section) . "," . this.Q(key) . "," . this.Q(value) . ",datetime('now','localtime')) "
            . "ON CONFLICT(section,key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at;")
    }

    static LogQuery(query, provider := "google", context := "") {
        this.Exec("INSERT INTO queries(query,provider,context) VALUES("
            . this.Q(query) . "," . this.Q(provider) . "," . this.Q(context) . ");")
    }

    static LogEvent(eventType, detail := "") {
        this.Exec("INSERT INTO event_log(event_type,detail) VALUES("
            . this.Q(eventType) . "," . this.Q(detail) . ");")
    }

    static GetContent(path) {
        normalized := NormalizePath(path)
        sourceTime := FileExist(path) ? FileGetTime(path, "M") : ""
        rows := this.Rows("SELECT content,source_mtime FROM content_items WHERE path=" . this.Q(normalized) . " LIMIT 1;")
        if rows.Length > 0 && (sourceTime = "" || rows[1]["source_mtime"] = sourceTime)
            return rows[1]["content"]

        if !FileExist(path)
            return rows.Length > 0 ? rows[1]["content"] : ""

        content := FileRead(path)
        this.UpsertContent(path, content)
        return content
    }

    static UpsertContent(path, content, contentType := "") {
        normalized := NormalizePath(path)
        SplitPath(path, &fileName, , &extension, &nameNoExt)
        if contentType = ""
            contentType := extension = "" ? "text" : StrLower(extension)
        sourceTime := FileExist(path) ? FileGetTime(path, "M") : ""
        this.Exec("INSERT INTO content_items(path,title,content_type,content,source_mtime,updated_at) VALUES("
            . this.Q(normalized) . "," . this.Q(nameNoExt) . "," . this.Q(contentType) . ","
            . this.Q(content) . "," . this.Q(sourceTime) . ",datetime('now','localtime')) "
            . "ON CONFLICT(path) DO UPDATE SET title=excluded.title,content_type=excluded.content_type,"
            . "content=excluded.content,source_mtime=excluded.source_mtime,updated_at=excluded.updated_at;")
    }

    static SaveContent(path, content, mirrorToFile := true) {
        this.UpsertContent(path, content)
        if !mirrorToFile
            return
        SplitPath(path, , &parentDir)
        if parentDir != "" && !DirExist(parentDir)
            DirCreate(parentDir)
        file := FileOpen(path, "w", "UTF-8-RAW")
        if !IsObject(file)
            throw Error("Could not write file: " . path)
        file.Write(content)
        file.Close()
        this.UpsertContent(path, content)
    }

    static RecordError(exception) {
        try {
            stackText := exception.HasProp("Stack") ? exception.Stack : ""
            fileName := exception.HasProp("File") ? exception.File : ""
            lineNo := exception.HasProp("Line") ? exception.Line : 0
            this.Exec("INSERT INTO errors(message,file,line,stack) VALUES("
                . this.Q(exception.Message) . "," . this.Q(fileName) . "," . Integer(lineNo) . ","
                . this.Q(stackText) . ");")
        }
    }
}

class SafeMenuBuilder {
    ; Windows native menus have a finite item/handle budget. This builder always
    ; creates a bounded tree (25 entries per Menu), so overflow self-corrects.
    static Build(items, callback, pageSize := 25) {
        return this.BuildLevel(items, callback, pageSize, 1)
    }

    static BuildLevel(items, callback, pageSize, absoluteStart) {
        menuObj := Menu()
        if items.Length <= pageSize {
            for item in items
                menuObj.Add(this.ItemLabel(item), callback.Bind(item))
            return menuObj
        }

        chunkSize := pageSize
        groupCount := Ceil(items.Length / chunkSize)
        if groupCount > pageSize
            chunkSize := Ceil(items.Length / pageSize)

        startIndex := 1
        while startIndex <= items.Length {
            endIndex := Min(items.Length, startIndex + chunkSize - 1)
            chunk := []
            Loop endIndex - startIndex + 1
                chunk.Push(items[startIndex + A_Index - 1])
            child := this.BuildLevel(chunk, callback, pageSize, absoluteStart + startIndex - 1)
            menuObj.Add("Items " . (absoluteStart + startIndex - 1) . "-" . (absoluteStart + endIndex - 1), child)
            startIndex := endIndex + 1
        }
        return menuObj
    }

    static ItemLabel(item) {
        if Type(item) = "Map" {
            if item.Has("label")
                return item["label"]
            if item.Has("text")
                return item["text"]
        }
        return String(item)
    }
}

class OverlayManager {
    static Windows := Map()
    static Initialized := false
    static DragOverlay := ""
    static DragOffsetX := 0
    static DragOffsetY := 0
    static DragTimer := ""

    static Init() {
        if this.Initialized
            return
        OnMessage(0x0204, OverlayRightButtonDown)
        OnMessage(0x0205, OverlayRightButtonUp)
        OnMessage(0x007B, OverlayContextMenu)
        this.DragTimer := OverlayDragTick
        this.Initialized := true
    }

    static Show(title := "Information", content := "", timeout := 0, options := unset) {
        actualOptions := IsSet(options) && Type(options) = "Map" ? options : Map()
        overlay := OverlayWindow(title, content, timeout, actualOptions)
        this.Windows[overlay.GuiObj.Hwnd] := overlay
        overlay.Show()
        return overlay
    }

    static Register(overlay) {
        this.Windows[overlay.GuiObj.Hwnd] := overlay
    }

    static Remove(hwnd) {
        if this.Windows.Has(hwnd)
            this.Windows.Delete(hwnd)
    }

    static Active() {
        hwnd := WinExist("A")
        return this.Windows.Has(hwnd) ? this.Windows[hwnd] : ""
    }

    static UnderMouse() {
        this.GetCursorScreenPosition(&mouseX, &mouseY)
        pointValue := (mouseY << 32) | (mouseX & 0xFFFFFFFF)
        hoveredHwnd := DllCall("User32.dll\WindowFromPoint", "Int64", pointValue, "Ptr")
        if !hoveredHwnd
            return ""
        rootHwnd := DllCall("GetAncestor", "Ptr", hoveredHwnd, "UInt", 2, "Ptr")
        if !rootHwnd
            rootHwnd := hoveredHwnd
        return this.Windows.Has(rootHwnd) ? this.Windows[rootHwnd] : ""
    }

    static HasActiveWindow(*) {
        return IsObject(this.Active())
    }

    static CloseActive(*) {
        overlay := this.Active()
        if IsObject(overlay)
            overlay.Close()
    }

    static SelectActive(*) {
        overlay := this.Active()
        if IsObject(overlay)
            overlay.ActivateSelected()
    }

    static MoveActive(delta, *) {
        overlay := this.Active()
        if IsObject(overlay)
            overlay.MoveSelection(delta)
    }

    static CopyActive(*) {
        overlay := this.Active()
        if IsObject(overlay)
            overlay.Copy()
    }

    static TogglePinActive(*) {
        overlay := this.Active()
        if IsObject(overlay)
            overlay.TogglePin()
    }

    static OnRightButtonDown(wParam, lParam, msg, hwnd) {
        rootHwnd := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
        if !rootHwnd
            rootHwnd := hwnd
        if !this.Windows.Has(rootHwnd)
            return
        overlay := this.Windows[rootHwnd]
        this.GetCursorScreenPosition(&mouseX, &mouseY)
        this.StartDrag(overlay, mouseX, mouseY)
        return 0
    }

    static OnRightButtonUp(wParam, lParam, msg, hwnd) {
        rootHwnd := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
        if !rootHwnd
            rootHwnd := hwnd
        if this.Windows.Has(rootHwnd) {
            this.StopDrag()
            return 0
        }
    }

    static OnContextMenu(wParam, lParam, msg, hwnd) {
        rootHwnd := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
        if !rootHwnd
            rootHwnd := hwnd
        ; Suppress Edit/ListView context menus after a right-drag. Otherwise the
        ; native context menu can appear on release and make the drag seem stuck.
        return this.Windows.Has(rootHwnd) ? 0 : ""
    }

    static StartDrag(overlay, mouseX, mouseY, startTimer := true) {
        if !IsObject(overlay) || overlay.Closed
            return
        this.StopDrag(false)
        WinGetPos(&windowX, &windowY, , , "ahk_id " . overlay.GuiObj.Hwnd)
        this.DragOverlay := overlay
        this.DragOffsetX := mouseX - windowX
        this.DragOffsetY := mouseY - windowY
        try SetTimer(overlay.TimerCallback, 0)
        WinActivate("ahk_id " . overlay.GuiObj.Hwnd)
        if startTimer
            SetTimer(this.DragTimer, 10)
    }

    static DragTick(forceMove := false) {
        if !IsObject(this.DragOverlay) {
            this.StopDrag(false)
            return
        }
        if !forceMove && !GetKeyState("RButton", "P") {
            this.StopDrag()
            return
        }

        overlay := this.DragOverlay
        if overlay.Closed || !WinExist("ahk_id " . overlay.GuiObj.Hwnd) {
            this.StopDrag(false)
            return
        }

        this.GetCursorScreenPosition(&mouseX, &mouseY)
        WinGetPos(, , &windowWidth, &windowHeight, "ahk_id " . overlay.GuiObj.Hwnd)
        virtualLeft := SysGet(76)
        virtualTop := SysGet(77)
        virtualRight := virtualLeft + SysGet(78)
        virtualBottom := virtualTop + SysGet(79)
        newX := Max(virtualLeft, Min(mouseX - this.DragOffsetX, virtualRight - windowWidth))
        newY := Max(virtualTop, Min(mouseY - this.DragOffsetY, virtualBottom - windowHeight))
        WinMove(newX, newY, , , "ahk_id " . overlay.GuiObj.Hwnd)
    }

    static GetCursorScreenPosition(&mouseX, &mouseY) {
        previousMode := A_CoordModeMouse
        CoordMode("Mouse", "Screen")
        try MouseGetPos(&mouseX, &mouseY)
        finally CoordMode("Mouse", previousMode)
    }

    static StopDrag(resetTimeout := true) {
        try SetTimer(this.DragTimer, 0)
        overlay := this.DragOverlay
        this.DragOverlay := ""
        this.DragOffsetX := 0
        this.DragOffsetY := 0
        if resetTimeout && IsObject(overlay) && !overlay.Closed
            overlay.ResetTimeout()
    }
}

class OverlayWindow {
    GuiObj := ""
    Content := ""
    Items := []
    ListControl := ""
    InputControl := ""
    Options := Map()
    Timeout := 0
    Opacity := 235
    Pinned := false
    TimerCallback := ""
    Closed := false

    __New(title, content, timeout, options) {
        global GC_OverlayTimeout, GC_OverlayOpacity, GC_OverlayWidth, GC_OverlayHeight
        this.Options := options
        this.Content := this.ContentToText(content)
        this.Timeout := timeout = 0 ? GC_OverlayTimeout : timeout
        this.Opacity := options.Has("opacity") ? Integer(options["opacity"]) : GC_OverlayOpacity
        width := options.Has("width") ? Integer(options["width"]) : GC_OverlayWidth
        height := options.Has("height") ? Integer(options["height"]) : GC_OverlayHeight
        width := Max(420, width)
        height := Max(260, height)

        this.GuiObj := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "GlobalCoder Overlay - " . title)
        this.GuiObj.BackColor := "1E1E1E"
        this.GuiObj.MarginX := 0
        this.GuiObj.MarginY := 0
        this.GuiObj.OnEvent("Close", (*) => this.Close())
        this.GuiObj.OnEvent("Escape", (*) => this.Close())
        this.GuiObj.overlayWidth := width
        this.GuiObj.overlayHeight := height

        titleBar := this.GuiObj.Add("Text", "x0 y0 w" . width . " h30 +0x200 Background163B65 cFFFFFF", "  " . title . "    [right-drag anywhere to move]")
        titleBar.SetFont("s10 bold", "Segoe UI")

        contentY := 34
        contentHeight := height - 104
        if options.Has("itemized") && options["itemized"] && Type(content) = "Array" {
            this.Items := content
            this.ListControl := this.GuiObj.Add("ListView", "x6 y" . contentY . " w" . (width - 12)
                . " h" . contentHeight . " -Multi -Hdr +Grid Background252526 cE6E6E6", ["Item", "Action"])
            for item in content {
                itemText := Type(item) = "Map" && item.Has("text") ? item["text"] : String(item)
                actionText := Type(item) = "Map" && item.Has("actionText") ? item["actionText"] : ""
                this.ListControl.Add(, itemText, actionText)
            }
            this.ListControl.ModifyCol(1, Max(250, width - 150))
            this.ListControl.ModifyCol(2, 110)
            this.ListControl.OnEvent("DoubleClick", (ctrl, row) => this.ActivateRow(row))
            if this.Items.Length > 0
                this.ListControl.Modify(1, "+Select +Focus")
        } else if options.Has("inputPrompt") {
            prompt := options["inputPrompt"]
            this.GuiObj.Add("Text", "x10 y" . contentY . " w" . (width - 20) . " h45 cE6E6E6", prompt)
            this.InputControl := this.GuiObj.Add("Edit", "x10 y" . (contentY + 52) . " w" . (width - 20)
                . " h" . (contentHeight - 92) . " Background252526 cFFFFFF +Multi +VScroll", this.Content)
            submitButton := this.GuiObj.Add("Button", "x10 y" . (contentY + contentHeight - 32) . " w90 h28 Default", "Submit")
            submitButton.OnEvent("Click", (*) => this.SubmitInput())
        } else {
            editCtrl := this.GuiObj.Add("Edit", "x6 y" . contentY . " w" . (width - 12) . " h" . contentHeight
                . " +ReadOnly -E0x200 Background252526 cE6E6E6 +VScroll", this.Content)
            editCtrl.SetFont("s9", options.Has("font") ? options["font"] : "Consolas")
        }

        legendY := height - 66
        this.GuiObj.Add("Text", "x6 y" . legendY . " w" . (width - 12) . " h20 cA8C7E6 Center",
            "Up/Down Select  |  Enter Open  |  Esc Close  |  Ctrl+C Copy  |  Ctrl+P Pin  |  Right-drag Move")

        toolbarY := height - 42
        this.GuiObj.Add("Text", "x0 y" . (toolbarY - 3) . " w" . width . " h1 Background3F3F46")
        this.GuiObj.Add("Button", "x8 y" . toolbarY . " w62 h30", "Copy").OnEvent("Click", (*) => this.Copy())
        this.GuiObj.Add("Button", "x76 y" . toolbarY . " w55 h30", "Help").OnEvent("Click", (*) => this.ShowHelp())
        this.GuiObj.Add("Button", "x137 y" . toolbarY . " w34 h30", "A-").OnEvent("Click", (*) => this.ChangeOpacity(-15))
        this.GuiObj.Add("Button", "x177 y" . toolbarY . " w34 h30", "A+").OnEvent("Click", (*) => this.ChangeOpacity(15))
        this.GuiObj.Add("Button", "x" . (width - 150) . " y" . toolbarY . " w66 h30 vPinButton", "Pin").OnEvent("Click", (*) => this.TogglePin())
        this.GuiObj.Add("Button", "x" . (width - 78) . " y" . toolbarY . " w70 h30", "Close").OnEvent("Click", (*) => this.Close())

        if options.Has("persistent") && options["persistent"] {
            this.Pinned := true
            this.Timeout := -1
            this.GuiObj["PinButton"].Text := "Unpin"
        }

        this.TimerCallback := (*) => this.Close()
    }

    Show() {
        width := this.GuiObj.overlayWidth
        height := this.GuiObj.overlayHeight
        GetActiveMonitorWorkArea(&left, &top, &right, &bottom)
        width := Min(width, right - left - 20)
        height := Min(height, bottom - top - 20)
        position := this.Options.Has("position") ? this.Options["position"] : "TopRight"
        switch position {
            case "TopLeft":
                x := left + 10, y := top + 10
            case "BottomLeft":
                x := left + 10, y := bottom - height - 10
            case "BottomRight":
                x := right - width - 10, y := bottom - height - 10
            case "Center":
                x := left + ((right - left - width) // 2), y := top + ((bottom - top - height) // 2)
            default:
                x := right - width - 10, y := top + 10
        }
        x := Max(left, Min(x, right - width))
        y := Max(top, Min(y, bottom - height))

        this.GuiObj.Show("x" . x . " y" . y . " w" . width . " h" . height)
        OverlayManager.Register(this)
        WinSetTransparent(this.Opacity, "ahk_id " . this.GuiObj.Hwnd)
        WinActivate("ahk_id " . this.GuiObj.Hwnd)
        if IsObject(this.ListControl)
            this.ListControl.Focus()
        else if IsObject(this.InputControl)
            this.InputControl.Focus()
        this.ResetTimeout()
    }

    ResetTimeout() {
        if this.Closed || this.Pinned || this.Timeout <= 0
            return
        try SetTimer(this.TimerCallback, 0)
        SetTimer(this.TimerCallback, -this.Timeout)
    }

    Close() {
        if this.Closed
            return
        this.Closed := true
        if IsObject(OverlayManager.DragOverlay) && OverlayManager.DragOverlay = this
            OverlayManager.StopDrag(false)
        try SetTimer(this.TimerCallback, 0)
        hwnd := this.GuiObj.Hwnd
        OverlayManager.Remove(hwnd)
        try this.GuiObj.Destroy()
    }

    Copy() {
        A_Clipboard := this.Content
        ShowBriefToolTip("Copied to clipboard")
        this.ResetTimeout()
    }

    TogglePin() {
        this.Pinned := !this.Pinned
        if this.Pinned {
            this.GuiObj.Opt("+AlwaysOnTop")
            this.GuiObj["PinButton"].Text := "Unpin"
            try SetTimer(this.TimerCallback, 0)
        } else {
            this.GuiObj.Opt("-AlwaysOnTop")
            this.GuiObj["PinButton"].Text := "Pin"
            this.ResetTimeout()
        }
    }

    ChangeOpacity(delta) {
        this.Opacity := Max(140, Min(255, this.Opacity + delta))
        WinSetTransparent(this.Opacity, "ahk_id " . this.GuiObj.Hwnd)
        ShowBriefToolTip("Opacity: " . this.Opacity)
        this.ResetTimeout()
    }

    MoveSelection(delta) {
        if !IsObject(this.ListControl) || this.Items.Length = 0
            return
        current := this.ListControl.GetNext(0, "F")
        if current = 0
            current := 1
        nextRow := Max(1, Min(this.Items.Length, current + delta))
        this.ListControl.Modify(0, "-Select -Focus")
        this.ListControl.Modify(nextRow, "+Select +Focus Vis")
        this.ResetTimeout()
    }

    ActivateSelected() {
        if IsObject(this.InputControl) {
            this.SubmitInput()
            return
        }
        if !IsObject(this.ListControl)
            return
        row := this.ListControl.GetNext(0, "F")
        this.ActivateRow(row)
    }

    ActivateRow(row) {
        if row < 1 || row > this.Items.Length
            return
        item := this.Items[row]
        this.ResetTimeout()
        if Type(item) != "Map"
            return
        if item.Has("callback") {
            callback := item["callback"]
            this.Close()
            callback.Call()
        } else if item.Has("copyCommand") {
            A_Clipboard := item["copyCommand"]
            ShowBriefToolTip("Copied: " . item["copyCommand"])
        }
    }

    SubmitInput() {
        if !IsObject(this.InputControl)
            return
        value := this.InputControl.Value
        if this.Options.Has("onSubmit") {
            callback := this.Options["onSubmit"]
            this.Close()
            callback.Call(value)
        } else {
            this.Close()
        }
    }

    ShowHelp() {
        helpText := "Overlay controls`n`n"
            . "Up / Down   Select an item`n"
            . "Enter       Open or submit`n"
            . "Escape      Dismiss`n"
            . "Ctrl+C      Copy all content`n"
            . "Ctrl+P      Pin or unpin`n"
            . "Right-drag  Move from any surface`n"
            . "A- / A+     Adjust transparency"
        ShowBriefToolTip(helpText, 5000)
        this.ResetTimeout()
    }

    ContentToText(content) {
        if Type(content) != "Array"
            return String(content)
        text := ""
        for index, item in content {
            value := Type(item) = "Map" && item.Has("text") ? item["text"] : String(item)
            text .= (index > 1 ? "`n" : "") . value
        }
        return text
    }
}

class StepRepository {
    static SeedDefaults() {
        steps := [
            ["JavaScript", "Vanilla JS Static Site", 1, "mkdir MySite", "Create the project folder", "Project name", "A dedicated folder keeps the project portable."],
            ["JavaScript", "Vanilla JS Static Site", 2, "cd MySite", "Enter the project folder", "None", "Run later commands from the project root."],
            ["JavaScript", "Vanilla JS Static Site", 3, "code .", "Open the folder in VS Code", "None", "VS Code treats the folder as one workspace."],
            ["JavaScript", "Vanilla JS Static Site", 4, "npx serve .", "Start a local static server", "None", "npx can run serve without a global install."],
            ["JavaScript", "Node + Express API", 1, "npm init -y", "Create package.json", "Project metadata", "The package manifest records scripts and dependencies."],
            ["JavaScript", "Node + Express API", 2, "npm install express", "Install Express", "None", "Express supplies HTTP routing and middleware."],
            ["JavaScript", "Node + Express API", 3, "node index.js", "Start the API", "Port", "Run the entry point with Node."],
            ["Python", "Python venv (Standard)", 1, "python -m venv venv", "Create a virtual environment", "Python version", "A venv isolates project dependencies."],
            ["Python", "Python venv (Standard)", 2, "venv\Scripts\activate", "Activate the environment", "None", "Activation makes this environment's Python and pip current."],
            ["Python", "Python venv (Standard)", 3, "python -m pip install --upgrade pip", "Upgrade pip", "None", "Using python -m pip selects the active interpreter reliably."],
            ["Python", "Python venv (Standard)", 4, "pip freeze > requirements.txt", "Capture dependencies", "None", "requirements.txt makes the environment reproducible."],
            ["C# / .NET", ".NET Console App", 1, "dotnet new console --output .", "Create the console project", "Project name", "--output . prevents an accidental nested project directory."],
            ["C# / .NET", ".NET Console App", 2, "dotnet build", "Compile the project", "None", "Build catches compiler and dependency errors."],
            ["C# / .NET", ".NET Console App", 3, "dotnet run", "Run the project", "None", "dotnet run builds when required, then executes."],
            ["C# / .NET", ".NET Web API", 1, "dotnet new webapi --output .", "Create an ASP.NET Core API", "Project name", "The SDK scaffolds an API in the current folder."],
            ["C# / .NET", ".NET Web API", 2, "dotnet run", "Start the API", "HTTPS trust", "The console prints the actual listening URLs."],
            ["TypeScript", "TypeScript Node Project", 1, "npm init -y", "Create package.json", "None", "Initialize Node package metadata."],
            ["TypeScript", "TypeScript Node Project", 2, "npm install --save-dev typescript", "Install the compiler", "None", "A project-local compiler pins the version."],
            ["TypeScript", "TypeScript Node Project", 3, "npx tsc --init", "Create tsconfig.json", "Target/runtime", "The configuration records compiler behavior."],
            ["TypeScript", "TypeScript Node Project", 4, "npx tsc", "Compile the project", "None", "tsc checks types and emits JavaScript according to tsconfig.json."]
        ]
        for row in steps {
            GlobalCoderDatabase.Exec("INSERT OR IGNORE INTO tutorial_steps(language,project_type,step_no,command,directions,input_needed,explanation) VALUES("
                . GlobalCoderDatabase.Q(row[1]) . "," . GlobalCoderDatabase.Q(row[2]) . "," . row[3] . ","
                . GlobalCoderDatabase.Q(row[4]) . "," . GlobalCoderDatabase.Q(row[5]) . ","
                . GlobalCoderDatabase.Q(row[6]) . "," . GlobalCoderDatabase.Q(row[7]) . ");")
        }
    }

    static Languages() {
        rows := GlobalCoderDatabase.Rows("SELECT DISTINCT language FROM tutorial_steps ORDER BY language;")
        result := []
        for row in rows
            result.Push(row["language"])
        return result
    }

    static ProjectTypes(language) {
        rows := GlobalCoderDatabase.Rows("SELECT DISTINCT project_type FROM tutorial_steps WHERE language="
            . GlobalCoderDatabase.Q(language) . " ORDER BY project_type;")
        result := []
        for row in rows
            result.Push(row["project_type"])
        return result
    }

    static Steps(language, projectType) {
        rows := GlobalCoderDatabase.Rows("SELECT step_no,command,directions,input_needed,explanation FROM tutorial_steps WHERE language="
            . GlobalCoderDatabase.Q(language) . " AND project_type=" . GlobalCoderDatabase.Q(projectType)
            . " ORDER BY step_no;")
        result := []
        for row in rows {
            result.Push(Map(
                "step", row["step_no"],
                "command", row["command"],
                "directions", row["directions"],
                "input", row["input_needed"],
                "explanation", row["explanation"]
            ))
        }
        return result
    }

    static ImportStepsFile(filePath) {
        content := GlobalCoderDatabase.GetContent(filePath)
        currentType := ""
        language := this.LanguageFromPath(filePath)
        count := 0
        for lineText in StrSplit(content, "`n", "`r") {
            lineText := Trim(lineText)
            if lineText = "" || SubStr(lineText, 1, 1) = ";"
                continue
            if SubStr(lineText, 1, 1) = "[" && SubStr(lineText, -1) = "]" {
                currentType := SubStr(lineText, 2, StrLen(lineText) - 2)
                continue
            }
            if currentType = "" || !InStr(lineText, "|")
                continue
            parts := StrSplit(lineText, "|")
            if parts.Length < 5
                continue
            GlobalCoderDatabase.Exec("INSERT INTO tutorial_steps(language,project_type,step_no,command,directions,input_needed,explanation) VALUES("
                . GlobalCoderDatabase.Q(language) . "," . GlobalCoderDatabase.Q(currentType) . "," . Integer(parts[1]) . ","
                . GlobalCoderDatabase.Q(Trim(parts[2])) . "," . GlobalCoderDatabase.Q(Trim(parts[3])) . ","
                . GlobalCoderDatabase.Q(Trim(parts[4])) . "," . GlobalCoderDatabase.Q(Trim(parts[5])) . ") "
                . "ON CONFLICT(language,project_type,step_no) DO UPDATE SET command=excluded.command,directions=excluded.directions,"
                . "input_needed=excluded.input_needed,explanation=excluded.explanation;")
            count++
        }
        return count
    }

    static LanguageFromPath(path) {
        lower := StrLower(path)
        if InStr(lower, "typescript")
            return "TypeScript"
        if InStr(lower, "javascript")
            return "JavaScript"
        if InStr(lower, "python")
            return "Python"
        if InStr(lower, "csharp") || InStr(lower, "dotnet")
            return "C# / .NET"
        return "Imported"
    }
}

class StepFileLoader {
    ; Compatibility facade for v6 callers. Files are imported into SQLite first.
    static LoadFile(filePath) {
        StepRepository.ImportStepsFile(filePath)
        language := StepRepository.LanguageFromPath(filePath)
        result := Map()
        for projectType in StepRepository.ProjectTypes(language)
            result[projectType] := StepRepository.Steps(language, projectType)
        return result
    }

    static GetProjectTypeNames(filePath) {
        this.LoadFile(filePath)
        return StepRepository.ProjectTypes(StepRepository.LanguageFromPath(filePath))
    }

    static GetStepsForType(filePath, typeName) {
        this.LoadFile(filePath)
        return StepRepository.Steps(StepRepository.LanguageFromPath(filePath), typeName)
    }
}

class StepCanvas {
    GuiObj := ""
    Steps := []
    CurrentStep := 1
    ProjectType := ""
    StepLabel := ""
    CodeDisplay := ""
    Directions := ""
    InputNeeded := ""
    Explanation := ""
    Pinned := true

    __New(steps, projectType := "Project Steps") {
        global GC_ActiveStepCanvas
        this.Steps := steps
        this.ProjectType := projectType
        if steps.Length = 0 {
            GUT_Display("No Steps", "No tutorial steps were found.", 3000)
            return
        }

        this.GuiObj := Gui("+AlwaysOnTop +Resize", "GlobalCoder Tutorial - " . projectType)
        this.GuiObj.BackColor := "1E1E1E"
        this.GuiObj.OnEvent("Close", (*) => this.Close())
        this.GuiObj.OnEvent("Escape", (*) => this.Close())
        this.StepLabel := this.GuiObj.Add("Text", "x10 y10 w580 h28 c4FC3F7", "")
        this.StepLabel.SetFont("s12 bold")
        this.GuiObj.Add("Text", "x10 y40 w580 h20 cA8C7E6", "Left/Right: navigate | Ctrl+C: copy command | Esc: close")
        this.GuiObj.Add("Text", "x10 y68 w100 h20 cAAAAAA", "Command")
        this.CodeDisplay := this.GuiObj.Add("Edit", "x10 y90 w580 h75 +ReadOnly Background252526 c7CFF7C -Wrap +HScroll")
        this.CodeDisplay.SetFont("s10", "Consolas")
        this.GuiObj.Add("Button", "x490 y170 w100 h28", "Copy Command").OnEvent("Click", (*) => this.CopyCommand())
        this.GuiObj.Add("Text", "x10 y175 w90 h20 cAAAAAA", "Directions")
        this.Directions := this.GuiObj.Add("Text", "x105 y175 w370 h40 cE6E6E6", "")
        this.GuiObj.Add("Text", "x10 y220 w90 h20 cAAAAAA", "Input")
        this.InputNeeded := this.GuiObj.Add("Text", "x105 y220 w480 h25 cFFCC66", "")
        this.GuiObj.Add("Text", "x10 y252 w100 h20 cAAAAAA", "Explanation")
        this.Explanation := this.GuiObj.Add("Edit", "x10 y275 w580 h100 +ReadOnly Background252526 cE6E6E6 +VScroll")
        this.GuiObj.Add("Button", "x10 y385 w90 h30", "Previous").OnEvent("Click", (*) => this.Previous())
        this.GuiObj.Add("Button", "x110 y385 w90 h30", "Next").OnEvent("Click", (*) => this.Next())
        this.GuiObj.Add("Button", "x430 y385 w75 h30 vPinButton", "Unpin").OnEvent("Click", (*) => this.TogglePin())
        this.GuiObj.Add("Button", "x515 y385 w75 h30", "Close").OnEvent("Click", (*) => this.Close())
        this.Update()
        this.GuiObj.Show("w600 h425")
        GC_ActiveStepCanvas := this
    }

    IsActive() {
        return IsObject(this.GuiObj) && WinActive("ahk_id " . this.GuiObj.Hwnd)
    }

    Previous(*) {
        if this.CurrentStep > 1 {
            this.CurrentStep--
            this.Update()
        }
    }

    Next(*) {
        if this.CurrentStep < this.Steps.Length {
            this.CurrentStep++
            this.Update()
        }
    }

    Update() {
        step := this.Steps[this.CurrentStep]
        this.StepLabel.Text := this.ProjectType . " - Step " . this.CurrentStep . " of " . this.Steps.Length
        this.CodeDisplay.Value := step.Has("command") ? step["command"] : ""
        this.Directions.Text := step.Has("directions") ? step["directions"] : ""
        this.InputNeeded.Text := step.Has("input") ? step["input"] : "None"
        this.Explanation.Value := step.Has("explanation") ? step["explanation"] : ""
    }

    CopyCommand(*) {
        A_Clipboard := this.CodeDisplay.Value
        ShowBriefToolTip("Command copied")
    }

    TogglePin(*) {
        this.Pinned := !this.Pinned
        this.GuiObj.Opt(this.Pinned ? "+AlwaysOnTop" : "-AlwaysOnTop")
        this.GuiObj["PinButton"].Text := this.Pinned ? "Unpin" : "Pin"
    }

    Close(*) {
        global GC_ActiveStepCanvas
        GC_ActiveStepCanvas := ""
        try this.GuiObj.Destroy()
    }
}

class ProjectManager {
    static RecentProjects := []

    static Init() {
        if !DirExist(GC_PROJECT_DIR)
            DirCreate(GC_PROJECT_DIR)
        this.LoadRecentProjects()
    }

    static LoadRecentProjects() {
        this.RecentProjects := []
        rows := GlobalCoderDatabase.Rows("SELECT path,name,project_type,open_count,last_opened FROM recent_projects ORDER BY last_opened DESC LIMIT 50;")
        for row in rows
            this.RecentProjects.Push(row)
    }

    static AddToRecent(projectPath, projectType := "") {
        SplitPath(projectPath, &projectName)
        GlobalCoderDatabase.Exec("INSERT INTO recent_projects(path,name,project_type,open_count,last_opened) VALUES("
            . GlobalCoderDatabase.Q(NormalizePath(projectPath)) . "," . GlobalCoderDatabase.Q(projectName) . ","
            . GlobalCoderDatabase.Q(projectType) . ",1,datetime('now','localtime')) "
            . "ON CONFLICT(path) DO UPDATE SET name=excluded.name,project_type=CASE WHEN excluded.project_type='' "
            . "THEN recent_projects.project_type ELSE excluded.project_type END,open_count=open_count+1,last_opened=excluded.last_opened;")
        this.LoadRecentProjects()
    }

    static ResolveVSCode() {
        global GC_VSCodePath
        if FileExist(GC_VSCodePath)
            return GC_VSCodePath
        candidates := [
            EnvGet("LocalAppData") "\Programs\Microsoft VS Code\Code.exe",
            EnvGet("ProgramFiles") "\Microsoft VS Code\Code.exe"
        ]
        programFilesX86 := EnvGet("ProgramFiles(x86)")
        if programFilesX86 != ""
            candidates.Push(programFilesX86 "\Microsoft VS Code\Code.exe")
        for candidate in candidates {
            if FileExist(candidate)
                return candidate
        }
        return GC_VSCodePath = "" ? "code" : GC_VSCodePath
    }

    static OpenWithVSCode(projectPath, *) {
        this.AddToRecent(projectPath)
        executable := this.ResolveVSCode()
        try Run(QuoteExecutable(executable) . " " . QuoteArgument(projectPath))
        catch as error {
            GUT_Display("VS Code could not open", error.Message . "`n`nSet the VS Code executable in Project Settings.", -1)
        }
    }

    static OpenWithSublime(projectPath, *) {
        global GC_SublimePath
        this.AddToRecent(projectPath)
        if !FileExist(GC_SublimePath) {
            GUT_Display("Sublime Text not found", GC_SublimePath, -1)
            return
        }
        Run(QuoteExecutable(GC_SublimePath) . " " . QuoteArgument(projectPath))
    }

    static OpenInTerminal(projectPath, *) {
        global GC_GitBashPath
        this.AddToRecent(projectPath)
        if FileExist(GC_GitBashPath)
            Run(QuoteExecutable(GC_GitBashPath) . " --cd=" . QuoteArgument(projectPath))
        else
            Run(A_ComSpec . " /K cd /d " . QuoteArgument(projectPath))
    }

    static OpenInExplorer(projectPath, *) {
        this.AddToRecent(projectPath)
        Run("explorer.exe " . QuoteArgument(projectPath))
    }
}

class WindowInstructionLanguage {
    static LastValue := ""

    static Execute(source, programName := "Ad hoc") {
        lineNumber := 0
        executed := 0
        for rawLine in StrSplit(source, "`n", "`r") {
            lineNumber++
            line := Trim(rawLine)
            if line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#"
                continue
            try {
                this.ExecuteLine(line)
                executed++
                GlobalCoderDatabase.LogEvent("instruction", programName . " line " . lineNumber . ": " . line)
            } catch as error {
                GlobalCoderDatabase.LogEvent("instruction_error", programName . " line " . lineNumber . ": " . error.Message)
                throw Error("Instruction line " . lineNumber . " failed:`n" . line . "`n`n" . error.Message)
            }
        }
        return executed
    }

    static ExecuteLine(line) {
        parts := StrSplit(line, "|")
        command := StrUpper(Trim(parts[1]))
        args := []
        if parts.Length > 1 {
            Loop parts.Length - 1
                args.Push(this.Expand(this.Decode(Trim(parts[A_Index + 1]))))
        }

        switch command {
            case "WAIT":
                Sleep(Integer(this.Arg(args, 1, "0")))
            case "RUN":
                target := this.Arg(args, 1)
                workDir := this.Arg(args, 2, "")
                Run(target, workDir)
            case "ACTIVATE":
                title := this.Arg(args, 1)
                if !WinExist(title)
                    throw Error("Window not found: " . title)
                WinActivate(title)
            case "WINDOW.WAIT":
                title := this.Arg(args, 1)
                seconds := Number(this.Arg(args, 2, "10"))
                if !WinWait(title, , seconds)
                    throw Error("Timed out waiting for: " . title)
            case "WINDOW.CLOSE":
                WinClose(this.Arg(args, 1))
            case "WINDOW.MIN":
                WinMinimize(this.Arg(args, 1))
            case "WINDOW.MAX":
                WinMaximize(this.Arg(args, 1))
            case "SEND":
                Send(this.Arg(args, 1))
            case "TEXT":
                SendText(this.Arg(args, 1))
            case "CLICK":
                x := Integer(this.Arg(args, 1)), y := Integer(this.Arg(args, 2))
                button := this.Arg(args, 3, "Left"), count := Integer(this.Arg(args, 4, "1"))
                Click(x, y, button, count)
            case "MOUSE.MOVE":
                MouseMove(Integer(this.Arg(args, 1)), Integer(this.Arg(args, 2)), Integer(this.Arg(args, 3, "2")))
            case "CLIPBOARD":
                A_Clipboard := this.Arg(args, 1)
            case "PASTE":
                Send("^v")
            case "OPEN":
                Run(this.Arg(args, 1))
            case "EXPLORER":
                Run("explorer.exe " . QuoteArgument(this.Arg(args, 1)))
            case "OVERLAY":
                GUT_Display(this.Arg(args, 1, "Automation"), this.Arg(args, 2, ""), 4000)
            default:
                throw Error("Unknown command: " . command)
        }
    }

    static Arg(args, index, defaultValue := unset) {
        if index <= args.Length
            return args[index]
        if IsSet(defaultValue)
            return defaultValue
        throw Error("Missing argument " . index)
    }

    static Decode(value) {
        value := StrReplace(value, "\n", "`n")
        value := StrReplace(value, "\t", "`t")
        value := StrReplace(value, "\p", "|")
        return value
    }

    static Expand(value) {
        value := StrReplace(value, "{{clipboard}}", A_Clipboard)
        value := StrReplace(value, "{{scriptdir}}", A_ScriptDir)
        value := StrReplace(value, "{{projectroot}}", GC_PROJECT_DIR)
        value := StrReplace(value, "{{last}}", this.LastValue)
        return value
    }
}

class KnowledgeBase {
    static Add(title, content, language := "", feature := "", nodeType := "fact") {
        GlobalCoderDatabase.Exec("INSERT INTO knowledge_nodes(title,node_type,language,feature,content) VALUES("
            . GlobalCoderDatabase.Q(title) . "," . GlobalCoderDatabase.Q(nodeType) . ","
            . GlobalCoderDatabase.Q(language) . "," . GlobalCoderDatabase.Q(feature) . ","
            . GlobalCoderDatabase.Q(content) . ");")
        GlobalCoderDatabase.Connection.LastInsertRowID(&nodeId)
        this.PrebuildGaps(nodeId, content)
        return nodeId
    }

    static PrebuildGaps(nodeId, content) {
        pointCount := 0
        for line in StrSplit(content, "`n", "`r") {
            if Trim(line) != ""
                pointCount++
        }
        if pointCount >= 7
            return
        prompts := [
            "What prerequisites or assumptions are missing?",
            "What is the smallest working example?",
            "What failure modes and exceptions matter?",
            "How should the result be verified?",
            "What related tools, languages, or concepts should this link to?",
            "When should this method not be used?",
            "What reusable standard operating procedure follows from this?"
        ]
        gapsToCreate := Min(prompts.Length, Max(1, 7 - pointCount))
        Loop gapsToCreate {
            GlobalCoderDatabase.Exec("INSERT INTO knowledge_gaps(node_id,prompt) VALUES("
                . Integer(nodeId) . "," . GlobalCoderDatabase.Q(prompts[A_Index]) . ");")
        }
    }

    static Search(searchText, limit := 50) {
        likeValue := "%" . searchText . "%"
        sql := "SELECT id,title,node_type,language,feature,content,confidence,importance,use_count,updated_at "
            . "FROM knowledge_nodes WHERE title LIKE " . GlobalCoderDatabase.Q(likeValue)
            . " OR content LIKE " . GlobalCoderDatabase.Q(likeValue)
            . " OR feature LIKE " . GlobalCoderDatabase.Q(likeValue)
            . " OR language LIKE " . GlobalCoderDatabase.Q(likeValue)
            . " ORDER BY (importance * (use_count + 1)) DESC, updated_at DESC LIMIT " . Integer(limit) . ";"
        return GlobalCoderDatabase.Rows(sql)
    }

    static RecordUse(nodeId) {
        GlobalCoderDatabase.Exec("UPDATE knowledge_nodes SET use_count=use_count+1,last_used=datetime('now','localtime') WHERE id="
            . Integer(nodeId) . ";")
    }

    static Link(fromNodeId, toNodeId, relation, strength := 1.0) {
        GlobalCoderDatabase.Exec("INSERT INTO knowledge_edges(from_node_id,to_node_id,relation,strength) VALUES("
            . Integer(fromNodeId) . "," . Integer(toNodeId) . "," . GlobalCoderDatabase.Q(relation) . ","
            . Number(strength) . ") ON CONFLICT(from_node_id,to_node_id,relation) DO UPDATE SET strength=excluded.strength;")
    }

    static NextGap() {
        rows := GlobalCoderDatabase.Rows("SELECT g.id,g.node_id,g.prompt,n.title,n.content FROM knowledge_gaps g "
            . "LEFT JOIN knowledge_nodes n ON n.id=g.node_id WHERE g.status='open' AND g.due_at<=datetime('now','localtime') "
            . "ORDER BY n.importance DESC,g.created_at LIMIT 1;")
        return rows.Length > 0 ? rows[1] : ""
    }

    static NextReview() {
        rows := GlobalCoderDatabase.Rows("SELECT n.id,n.title,n.language,n.feature,n.content,"
            . "COALESCE(MAX(r.next_review_at),'1970-01-01') AS next_review_at "
            . "FROM knowledge_nodes n LEFT JOIN knowledge_reviews r ON r.node_id=n.id "
            . "GROUP BY n.id ORDER BY (next_review_at<=datetime('now','localtime')) DESC,"
            . "n.importance DESC,n.use_count ASC,RANDOM() LIMIT 1;")
        return rows.Length > 0 ? rows[1] : ""
    }

    static RecordReview(nodeId, response, rating) {
        days := rating >= 3 ? 14 : (rating = 2 ? 7 : (rating = 1 ? 2 : 1))
        GlobalCoderDatabase.Exec("INSERT INTO knowledge_reviews(node_id,response,rating,next_review_at) VALUES("
            . Integer(nodeId) . "," . GlobalCoderDatabase.Q(response) . "," . Integer(rating)
            . ",datetime('now','localtime','+" . days . " days'));")
        if rating >= 2
            this.RecordUse(nodeId)
    }

    static ResolveGap(gapId, nodeId, answer) {
        rows := GlobalCoderDatabase.Rows("SELECT content FROM knowledge_nodes WHERE id=" . Integer(nodeId) . " LIMIT 1;")
        if rows.Length > 0 {
            updated := RTrim(rows[1]["content"]) . "`n`n" . answer
            GlobalCoderDatabase.Exec("UPDATE knowledge_nodes SET content=" . GlobalCoderDatabase.Q(updated)
                . ",updated_at=datetime('now','localtime') WHERE id=" . Integer(nodeId) . ";")
        }
        GlobalCoderDatabase.Exec("UPDATE knowledge_gaps SET status='resolved',resolved_at=datetime('now','localtime') WHERE id="
            . Integer(gapId) . ";")
    }
}

class ActivityMonitor {
    static WasIdle := false
    static LastPromptAt := 0

    static Start() {
        SetTimer((*) => ActivityMonitor.Tick(), 30000)
    }

    static Tick() {
        threshold := Integer(GlobalCoderDatabase.GetSetting("Knowledge", "IdleThresholdMs", "900000"))
        isIdle := A_TimeIdlePhysical >= threshold
        if isIdle != this.WasIdle {
            eventType := isIdle ? "idle_start" : "active_resume"
            title := ""
            try title := WinGetTitle("A")
            GlobalCoderDatabase.Exec("INSERT INTO activity_log(event_type,detail,active_window,idle_ms) VALUES("
                . GlobalCoderDatabase.Q(eventType) . ",'' ," . GlobalCoderDatabase.Q(title) . "," . Integer(A_TimeIdlePhysical) . ");")
            if !isIdle && GlobalCoderDatabase.GetSetting("Knowledge", "PromptOnResume", "1") = "1"
                this.PromptForGap()
            this.WasIdle := isIdle
        }
    }

    static PromptForGap() {
        if A_TickCount - this.LastPromptAt < 600000
            return
        gap := KnowledgeBase.NextGap()
        if !IsObject(gap)
            return
        this.LastPromptAt := A_TickCount
        options := Map(
            "width", 620,
            "height", 360,
            "inputPrompt", gap["title"] . "`n`n" . gap["prompt"],
            "onSubmit", ResolveKnowledgeGapPrompt.Bind(gap["id"], gap["node_id"]),
            "persistent", true
        )
        OverlayManager.Show("Fill a Knowledge Gap", "", -1, options)
    }

    static ResolvePrompt(gapId, nodeId, answer) {
        if Trim(answer) != ""
            KnowledgeBase.ResolveGap(gapId, nodeId, answer)
    }
}

class HotstringManager {
    static Registered := []

    static Init() {
        Hotstring(":*:jjj", ShowCustomMenu)
        Hotstring(":*:ggg", GoogleSearchWithLogging)
        this.ReloadCustom()
    }

    static ReloadCustom() {
        for key in this.Registered {
            try Hotstring(key, "Off")
        }
        this.Registered := []
        rows := GlobalCoderDatabase.Rows("SELECT trigger,replacement FROM hotstrings WHERE enabled=1 ORDER BY trigger;")
        for row in rows {
            key := ":*:" . row["trigger"]
            Hotstring(key, PasteHotstring.Bind(row["replacement"]))
            this.Registered.Push(key)
        }
    }
}

; ============================================================================
; STARTUP AND ONE-TIME MIGRATION
; ============================================================================

InitializeGlobalCoder()
return

InitializeGlobalCoder() {
    global GC_MainMenu
    try {
        EnsurePortableFolders()
        OverlayManager.Init()
        GlobalCoderDatabase.Init(GC_DB_PATH)
        MigrateLegacyStorageOnce()
        LoadRuntimeSettings()
        ProjectManager.Init()
        HotstringManager.Init()
        RegisterGlobalHotkeys()
        GC_MainMenu := PrepareMenu()
        SetupTrayMenu()
        ActivityMonitor.Start()
        OnError(LogGlobalCoderError)
        OnExit(CloseGlobalCoder)
        GlobalCoderDatabase.LogEvent("startup", "GlobalCoder v7 started")
        if IsValidationMode() {
            RunValidationSuite()
            try FileAppend("GlobalCoder v7 validation passed.`n", "*")
            GlobalCoderDatabase.Connection.CloseDB()
            ExitApp(0)
        }
    } catch as error {
        try FileAppend("GlobalCoder v7 startup error: " . error.Message . "`n" . error.Stack . "`n", "*")
        if IsValidationMode()
            ExitApp(1)
        MsgBox("GlobalCoder v7 could not start.`n`n" . error.Message
            . "`n`nRequired files:`n" . GC_SQLITE_WRAPPER . "`n" . GC_SQLITE_DLL,
            "GlobalCoder v7 Startup Error", 16)
        ExitApp()
    }
}

IsValidationMode() {
    return A_Args.Length > 0 && (A_Args[1] = "--validate" || A_Args[1] = "validate")
}

RunValidationSuite() {
    if GlobalCoderDatabase.Scalar("PRAGMA integrity_check;", "failed") != "ok"
        throw Error("SQLite integrity check failed")
    if Integer(GlobalCoderDatabase.Scalar("SELECT COUNT(*) FROM instruction_commands;", "0")) < 10
        throw Error("Instruction language seed data is incomplete")

    menuItems := []
    Loop 90
        menuItems.Push(Map("label", "Validation item " . A_Index, "function", "Action_OpenFolder", "context", A_ScriptDir))
    validationMenu := SafeMenuBuilder.Build(menuItems, ExecuteActionItem)
    if !IsObject(validationMenu)
        throw Error("Safe menu pagination failed")

    overlayItems := [Map("text", "Validation row", "actionText", "OK")]
    overlay := OverlayManager.Show("Validation", overlayItems, -1,
        Map("itemized", true, "width", 480, "height", 300, "position", "Center"))
    overlay.MoveSelection(1)
    WinGetPos(&startX, &startY, , , "ahk_id " . overlay.GuiObj.Hwnd)
    OverlayManager.GetCursorScreenPosition(&savedMouseX, &savedMouseY)
    previousMouseMode := A_CoordModeMouse
    CoordMode("Mouse", "Screen")
    try {
        ; Exercise the same StartDrag/DragTick path used by the overlay-scoped
        ; RButton hotkey. Synthetic input on the non-interactive validation
        ; desktop cannot trigger an AHK physical hotkey reliably.
        DllCall("User32.dll\SetCursorPos", "Int", startX + 100, "Int", startY + 100, "Int")
        OverlayManager.GetCursorScreenPosition(&dragStartX, &dragStartY)
        OverlayManager.StartDrag(overlay, dragStartX, dragStartY, false)
        DllCall("User32.dll\SetCursorPos", "Int", startX + 124, "Int", startY + 116, "Int")
        OverlayManager.DragTick(true)
    } finally {
        OverlayManager.StopDrag(false)
        CoordMode("Mouse", previousMouseMode)
    }
    WinGetPos(&movedX, &movedY, , , "ahk_id " . overlay.GuiObj.Hwnd)
    OverlayManager.StopDrag(false)
    DllCall("User32.dll\SetCursorPos", "Int", savedMouseX, "Int", savedMouseY, "Int")
    if movedX = startX && movedY = startY
        throw Error("Overlay right-drag movement failed")
    overlay.Close()

    steps := [Map("command", "WAIT|1", "directions", "Validate", "input", "None", "explanation", "Runtime validation")]
    canvas := StepCanvas(steps, "Validation")
    if IsObject(canvas.GuiObj)
        canvas.Close()
}

EnsurePortableFolders() {
    required := [GC_DATA_DIR, GC_PROJECT_DIR, GC_LIBRARY_DIR]
    for folder in required {
        if !DirExist(folder)
            DirCreate(folder)
    }
}

LoadRuntimeSettings() {
    global GC_OverlayTimeout, GC_OverlayOpacity, GC_OverlayWidth, GC_OverlayHeight
    global GC_VSCodePath, GC_SublimePath, GC_GitBashPath
    GC_OverlayTimeout := ToInteger(GlobalCoderDatabase.GetSetting("Overlay", "Timeout", "5000"), 5000)
    GC_OverlayOpacity := Max(140, Min(255, ToInteger(GlobalCoderDatabase.GetSetting("Overlay", "Opacity", "235"), 235)))
    GC_OverlayWidth := Max(420, ToInteger(GlobalCoderDatabase.GetSetting("Overlay", "Width", "600"), 600))
    GC_OverlayHeight := Max(260, ToInteger(GlobalCoderDatabase.GetSetting("Overlay", "Height", "400"), 400))
    GC_VSCodePath := GlobalCoderDatabase.GetSetting("Projects", "VSCodePath", "code")
    GC_SublimePath := GlobalCoderDatabase.GetSetting("Projects", "SublimePath", "C:\Program Files\Sublime Text\sublime_text.exe")
    GC_GitBashPath := GlobalCoderDatabase.GetSetting("Projects", "GitBashPath", "C:\Program Files\Git\git-bash.exe")
}

MigrateLegacyStorageOnce() {
    if GlobalCoderDatabase.GetSetting("Migration", "LegacyV6Imported", "0") = "1"
        return

    queryLog := GC_LIBRARY_DIR "\query_log.txt"
    if FileExist(queryLog) {
        for line in StrSplit(FileRead(queryLog), "`n", "`r") {
            line := Trim(line)
            if line = ""
                continue
            separator := InStr(line, " | ")
            query := separator ? SubStr(line, separator + 3) : line
            if Trim(query) != ""
                GlobalCoderDatabase.LogQuery(query, "legacy", "Imported from query_log.txt")
        }
    }

    hotstringsFile := GC_LIBRARY_DIR "\hotstrings.ini"
    if FileExist(hotstringsFile)
        ImportLegacyHotstrings(hotstringsFile)

    actionsFile := GC_LIBRARY_DIR "\actions.ini"
    if FileExist(actionsFile)
        ImportLegacyActions(actionsFile)

    projectsIni := GC_LIBRARY_DIR "\1_projects\projects.ini"
    if FileExist(projectsIni) {
        recent := IniRead(projectsIni, "RecentProjects", "List", "")
        for projectPath in StrSplit(recent, "|") {
            if Trim(projectPath) != ""
                ProjectManager.AddToRecent(projectPath)
        }
    }

    GlobalCoderDatabase.SetSetting("Migration", "LegacyV6Imported", "1")
    GlobalCoderDatabase.LogEvent("migration", "Legacy file-backed state imported into SQLite")
}

ImportLegacyHotstrings(filePath) {
    currentSection := ""
    for line in StrSplit(FileRead(filePath), "`n", "`r") {
        line := Trim(line)
        if line = "" || SubStr(line, 1, 1) = ";"
            continue
        if SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]" {
            currentSection := SubStr(line, 2, StrLen(line) - 2)
            continue
        }
        if !InStr(line, "=")
            continue
        parts := StrSplit(line, "=", , 2)
        trigger := Trim(parts[1])
        replacement := StrReplace(StrReplace(Trim(parts[2]), "``n", "`n"), "``t", "`t")
        if trigger != "" {
            GlobalCoderDatabase.Exec("INSERT OR IGNORE INTO hotstrings(trigger,replacement,category) VALUES("
                . GlobalCoderDatabase.Q(trigger) . "," . GlobalCoderDatabase.Q(replacement) . ","
                . GlobalCoderDatabase.Q(currentSection) . ");")
        }
    }
}

ImportLegacyActions(filePath) {
    inActions := false
    for line in StrSplit(FileRead(filePath), "`n", "`r") {
        line := Trim(line)
        if line = "" || SubStr(line, 1, 1) = ";"
            continue
        if SubStr(line, 1, 1) = "[" {
            inActions := line = "[Actions]"
            continue
        }
        if inActions && InStr(line, "=") {
            parts := StrSplit(line, "=", , 2)
            GlobalCoderDatabase.Exec("INSERT OR IGNORE INTO actions(name,function_name) VALUES("
                . GlobalCoderDatabase.Q(Trim(parts[1])) . "," . GlobalCoderDatabase.Q(Trim(parts[2])) . ");")
        }
    }
}

CloseGlobalCoder(exitReason, exitCode) {
    try GlobalCoderDatabase.LogEvent("shutdown", exitReason . " (" . exitCode . ")")
    try GlobalCoderDatabase.Connection.CloseDB()
}

; ============================================================================
; TRAY AND SAFE NATIVE MENU
; ============================================================================

SetupTrayMenu() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Open GlobalCoder", (*) => ShowMainFeaturesGUI())
    A_TrayMenu.Add("Browse Library", (*) => ShowCustomMenu())
    A_TrayMenu.Add()

    projectMenu := Menu()
    projectMenu.Add("Create New Project", (*) => ShowNewProjectWizard())
    projectMenu.Add("Recent Projects", (*) => ShowRecentProjects())
    projectMenu.Add("Learning Center", (*) => ShowLearningCenter())
    projectMenu.Add("Project Settings", (*) => ShowProjectSettings())
    A_TrayMenu.Add("Projects", projectMenu)

    knowledgeMenu := Menu()
    knowledgeMenu.Add("Add Knowledge", (*) => ShowAddKnowledgeGUI())
    knowledgeMenu.Add("Search Knowledge", (*) => ShowKnowledgeSearch())
    knowledgeMenu.Add("Review a Gap", (*) => ActivityMonitor.PromptForGap())
    knowledgeMenu.Add("Knowledge Test", (*) => ShowKnowledgeTest())
    A_TrayMenu.Add("Knowledge Web", knowledgeMenu)

    automationMenu := Menu()
    automationMenu.Add("Instruction Language", (*) => ShowInstructionLanguageConsole())
    automationMenu.Add("Command Reference", (*) => ShowInstructionReference())
    automationMenu.Add("Find in Knowledge and Files", (*) => FindInFiles())
    A_TrayMenu.Add("Automation", automationMenu)

    A_TrayMenu.Add()
    A_TrayMenu.Add("Settings", (*) => ShowSettingsGUI())
    A_TrayMenu.Add("Hotstrings", (*) => ShowHotstringsGUI())
    A_TrayMenu.Add("Query History", (*) => ShowQueryLog())
    A_TrayMenu.Add("Open Script Folder", (*) => Run("explorer.exe " . QuoteArgument(A_ScriptDir)))
    A_TrayMenu.Add()
    A_TrayMenu.Add("Reload", (*) => Reload())
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.Default := "Open GlobalCoder"

    ; AutoHotkey v2 equivalent of: Menu, Tray, Icon, Shell32.dll, 14, 1
    ; The final true freezes the loaded globe icon so later tray updates keep it.
    try TraySetIcon(A_WinDir "\System32\Shell32.dll", 14, true)
    A_IconTip := "GlobalCoder v7 - portable project and knowledge manager"
    OnMessage(0x0404, TrayIconCallback)
}

TrayIconCallback(wParam, lParam, msg, hwnd) {
    if lParam = 0x0203 {
        ShowMainFeaturesGUI()
        return 0
    }
}

PrepareMenu(*) {
    ; Intentionally static and small. Directory content belongs in the ListView
    ; browser, where Windows' native Menu item/handle limit does not apply.
    menuObj := Menu()
    menuObj.Add("GlobalCoder Dashboard", (*) => ShowMainFeaturesGUI())
    menuObj.Add("Browse Library", (*) => ShowCustomMenu())
    menuObj.Add()
    menuObj.Add("New Project", (*) => ShowNewProjectWizard())
    menuObj.Add("Recent Projects", (*) => ShowRecentProjects())
    menuObj.Add("Learning Center", (*) => ShowLearningCenter())
    menuObj.Add()
    menuObj.Add("Knowledge Search", (*) => ShowKnowledgeSearch())
    menuObj.Add("Instruction Language", (*) => ShowInstructionLanguageConsole())
    menuObj.Add("Google Search", (*) => GoogleSearchWithLogging())
    menuObj.Add()
    menuObj.Add("Settings", (*) => ShowSettingsGUI())
    menuObj.Add("Exit", (*) => ExitApp())
    return menuObj
}

ShowMainMenu(*) {
    global GC_MainMenu, GC_CallingWindowHwnd
    GC_CallingWindowHwnd := WinExist("A")
    if !IsObject(GC_MainMenu)
        GC_MainMenu := PrepareMenu()
    GC_MainMenu.Show()
}

RebuildMenu(*) {
    global GC_MainMenu
    GC_MainMenu := PrepareMenu()
    GUT_Display("Menu Ready", "The bounded native menu and library browser were refreshed.", 2500)
}

; ============================================================================
; CUSTOM LIBRARY MENU
; ============================================================================

ShowCustomMenu(*) {
    global GC_MenuVisible, GC_MenuStack, GC_MenuItems, GC_MenuIndex, GC_CallingWindowHwnd
    if GC_MenuVisible {
        CloseCustomMenu()
        return
    }
    GC_CallingWindowHwnd := WinExist("A")
    GC_MenuStack := []
    GC_MenuItems := BuildMenuItems(GC_LIBRARY_DIR)
    GC_MenuIndex := FirstSelectableIndex(GC_MenuItems)
    CreateCustomMenuGui("GlobalCoder Library")
}

BuildMenuItems(path, isSubmenu := false) {
    result := []
    if isSubmenu
        result.Push(Map("name", "< Back", "path", "", "type", "back"))
    else {
        result.Push(Map("name", "Knowledge: Add", "path", "action:AddKnowledge", "type", "action"))
        result.Push(Map("name", "Knowledge: Search", "path", "action:SearchKnowledge", "type", "action"))
        result.Push(Map("name", "Knowledge: Test Recall", "path", "action:TestKnowledge", "type", "action"))
        result.Push(Map("name", "Automation Instruction Language", "path", "action:InstructionLanguage", "type", "action"))
        result.Push(Map("name", "Projects: New", "path", "action:NewProject", "type", "action"))
        result.Push(Map("name", "Projects: Recent", "path", "action:RecentProjects", "type", "action"))
        result.Push(Map("name", "--- Library ---", "path", "", "type", "separator"))
    }

    if !DirExist(path)
        return result
    try {
        Loop Files, path "\*", "D"
            result.Push(Map("name", "[Folder] " . A_LoopFileName, "path", A_LoopFilePath, "type", "folder"))
        Loop Files, path "\*", "F"
            result.Push(Map("name", A_LoopFileName, "path", A_LoopFilePath, "type", "file"))
    }
    return result
}

CreateCustomMenuGui(title) {
    global GC_CustomMenuGui, GC_MenuList, GC_MenuVisible, GC_MenuItems, GC_MenuIndex
    GC_CustomMenuGui := Gui("+AlwaysOnTop +ToolWindow", title)
    GC_CustomMenuGui.BackColor := "1E1E1E"
    GC_CustomMenuGui.OnEvent("Close", (*) => CloseCustomMenu())
    GC_CustomMenuGui.OnEvent("Escape", (*) => CloseCustomMenu())
    header := GC_CustomMenuGui.Add("Text", "x0 y0 w560 h34 +0x200 Background163B65 cFFFFFF Center", title)
    header.SetFont("s11 bold")
    GC_CustomMenuGui.Add("Text", "x5 y38 w550 h22 cA8C7E6 Center",
        "Up/Down or J/K | Enter or H: select | Backspace or F: back | Esc: close")
    GC_MenuList := GC_CustomMenuGui.Add("ListView", "x5 y65 w550 h410 -Hdr -Multi +Grid Background252526 cE6E6E6", ["Item"])
    PopulateCustomMenu()
    GC_MenuList.OnEvent("DoubleClick", (ctrl, row) => SelectMenuItem(row))
    GC_CustomMenuGui.Add("Text", "x5 y480 w550 h22 c888888 Center", "Database: " . GC_DB_PATH)

    GetActiveMonitorWorkArea(&left, &top, &right, &bottom)
    width := Min(560, right - left - 20)
    height := Min(510, bottom - top - 20)
    x := left + ((right - left - width) // 2)
    y := top + ((bottom - top - height) // 2)
    GC_CustomMenuGui.Show("x" . x . " y" . y . " w" . width . " h" . height)
    GC_MenuVisible := true
    WinActivate("ahk_id " . GC_CustomMenuGui.Hwnd)
    GC_MenuList.Focus()
    if GC_MenuItems.Length > 0
        GC_MenuList.Modify(GC_MenuIndex, "+Select +Focus Vis")
}

PopulateCustomMenu() {
    global GC_MenuList, GC_MenuItems
    GC_MenuList.Delete()
    for item in GC_MenuItems
        GC_MenuList.Add(, item["name"])
    GC_MenuList.ModifyCol(1, 530)
}

CustomMenuIsActive(*) {
    global GC_MenuVisible, GC_CustomMenuGui
    return GC_MenuVisible && IsObject(GC_CustomMenuGui) && WinActive("ahk_id " . GC_CustomMenuGui.Hwnd)
}

MenuMove(delta, *) {
    global GC_MenuItems, GC_MenuIndex, GC_MenuList
    if GC_MenuItems.Length = 0
        return
    candidate := GC_MenuIndex
    Loop GC_MenuItems.Length {
        candidate += delta
        if candidate < 1
            candidate := GC_MenuItems.Length
        else if candidate > GC_MenuItems.Length
            candidate := 1
        if GC_MenuItems[candidate]["type"] != "separator"
            break
    }
    GC_MenuIndex := candidate
    GC_MenuList.Modify(0, "-Select -Focus")
    GC_MenuList.Modify(candidate, "+Select +Focus Vis")
}

MenuSelect(*) {
    global GC_MenuIndex
    SelectMenuItem(GC_MenuIndex)
}

SelectMenuItem(rowIndex) {
    global GC_MenuItems, GC_MenuStack, GC_MenuIndex
    if rowIndex < 1 || rowIndex > GC_MenuItems.Length
        return
    item := GC_MenuItems[rowIndex]
    switch item["type"] {
        case "separator":
            return
        case "back":
            MenuGoBack()
        case "folder":
            GC_MenuStack.Push(Map("items", GC_MenuItems, "index", GC_MenuIndex))
            GC_MenuItems := BuildMenuItems(item["path"], true)
            GC_MenuIndex := FirstSelectableIndex(GC_MenuItems)
            RefreshCustomMenu()
        case "file":
            CloseCustomMenu()
            MenuEventHandler(item["path"])
        case "action":
            CloseCustomMenu()
            ExecuteMenuAction(StrReplace(item["path"], "action:", ""))
    }
}

MenuGoBack(*) {
    global GC_MenuStack, GC_MenuItems, GC_MenuIndex
    if GC_MenuStack.Length = 0 {
        CloseCustomMenu()
        return
    }
    previous := GC_MenuStack.Pop()
    GC_MenuItems := previous["items"]
    GC_MenuIndex := previous["index"]
    RefreshCustomMenu()
}

RefreshCustomMenu() {
    global GC_MenuList, GC_MenuIndex
    PopulateCustomMenu()
    GC_MenuList.Modify(GC_MenuIndex, "+Select +Focus Vis")
    GC_MenuList.Focus()
}

CloseCustomMenu(*) {
    global GC_CustomMenuGui, GC_MenuVisible
    if IsObject(GC_CustomMenuGui)
        try GC_CustomMenuGui.Destroy()
    GC_CustomMenuGui := ""
    GC_MenuVisible := false
}

ExecuteMenuAction(actionName) {
    switch actionName {
        case "AddKnowledge":
            ShowAddKnowledgeGUI()
        case "SearchKnowledge":
            ShowKnowledgeSearch()
        case "TestKnowledge":
            ShowKnowledgeTest()
        case "InstructionLanguage":
            ShowInstructionLanguageConsole()
        case "NewProject":
            ShowNewProjectWizard()
        case "RecentProjects":
            ShowRecentProjects()
        default:
            GUT_Display("Unknown Action", actionName, 3000)
    }
}

FirstSelectableIndex(items) {
    for index, item in items {
        if item["type"] != "separator"
            return index
    }
    return 1
}

; ============================================================================
; SHARED OVERLAY COMPATIBILITY API
; ============================================================================

GUT_Display(title := "Information", content := "", timeout := 0, options := unset) {
    return IsSet(options)
        ? OverlayManager.Show(title, content, timeout, options)
        : OverlayManager.Show(title, content, timeout, Map())
}

; ============================================================================
; PROJECT CREATOR AND RECENT PROJECTS
; ============================================================================

ShowNewProjectWizard(*) {
    defaultRoot := GlobalCoderDatabase.GetSetting("Projects", "DefaultRoot", GC_PROJECT_DIR)
    if !DirExist(defaultRoot)
        DirCreate(defaultRoot)

    wizard := Gui("+AlwaysOnTop", "Create New Project")
    wizard.BackColor := "1E1E1E"
    wizard.OnEvent("Escape", (*) => wizard.Destroy())
    wizard.Add("Text", "x12 y12 w380 cE6E6E6", "Project name")
    nameEdit := wizard.Add("Edit", "x12 y34 w416 h27 vProjectName Background252526 cFFFFFF", "MyProject")
    nameEdit.Focus()
    wizard.Add("Text", "x12 y70 w380 cE6E6E6", "Parent folder (portable default: script\data\projs)")
    wizard.Add("Edit", "x12 y92 w330 h27 vProjectPath Background252526 cFFFFFF", defaultRoot)
    wizard.Add("Button", "x350 y92 w78 h27", "Browse").OnEvent("Click", (*) => BrowseProjectPath(wizard))
    wizard.Add("Text", "x12 y130 w380 cE6E6E6", "Project type")
    wizard.Add("DropDownList", "x12 y152 w260 vProjectType Choose1", [
        ".NET Console App",
        ".NET Solution + Console + Library",
        ".NET Web API",
        "Node.js Express",
        "Python Virtual Env",
        "Empty Folder"
    ])
    wizard.Add("GroupBox", "x12 y192 w416 h104 cE6E6E6", "After creation")
    wizard.Add("Checkbox", "x24 y216 vOpenVSCode Checked cE6E6E6", "Open in VS Code")
    wizard.Add("Checkbox", "x24 y242 vCreateVSCodeConfig Checked cE6E6E6", "Create portable .vscode settings")
    wizard.Add("Checkbox", "x24 y268 vInitGit cE6E6E6", "Initialize a Git repository")
    wizard.Add("Text", "x8 y308 w424 h1 Background444444")
    wizard.Add("Button", "x12 y320 w110 h34 Default", "Create").OnEvent("Click", (*) => CreateProject(wizard))
    wizard.Add("Button", "x132 y320 w110 h34", "Tutorial").OnEvent("Click", (*) => (wizard.Destroy(), ShowLearningCenter()))
    wizard.Add("Button", "x318 y320 w110 h34", "Cancel").OnEvent("Click", (*) => wizard.Destroy())
    wizard.Show("w440 h366")
    WinActivate("ahk_id " . wizard.Hwnd)
}

BrowseProjectPath(guiObj) {
    selected := FileSelect("D", guiObj["ProjectPath"].Value, "Select the project parent folder")
    if selected != ""
        guiObj["ProjectPath"].Value := selected
}

CreateProject(guiObj) {
    values := guiObj.Submit(false)
    projectName := Trim(values.ProjectName)
    parentPath := Trim(values.ProjectPath)
    projectType := values.ProjectType

    if !IsSafeFileName(projectName) {
        MsgBox("Enter a non-empty project name without these characters:`n\ / : * ? " . Chr(34) . " < > |", "Invalid Project Name", 48)
        return
    }
    if parentPath = "" {
        MsgBox("Select a parent folder.", "Invalid Project Path", 48)
        return
    }

    fullPath := RTrim(parentPath, "\/") . "\" . projectName
    if DirExist(fullPath) {
        if MsgBox("This folder already exists:`n" . fullPath . "`n`nContinue and add the selected setup?",
            "Existing Project", 52) != "Yes"
            return
    } else {
        DirCreate(fullPath)
    }

    ; The Create button always destroys the wizard before setup begins. This
    ; prevents a dead/stale creator window while dotnet, npm, Python, or Git run.
    guiObj.Destroy()
    progress := GUT_Display("Creating Project", projectName . "`n" . projectType . "`n`nPlease wait...", -1,
        Map("persistent", true, "width", 500, "height", 280, "position", "Center"))

    try {
        switch projectType {
            case ".NET Console App":
                SetupDotNetConsole(fullPath, projectName)
            case ".NET Solution + Console + Library":
                SetupDotNetFullSolution(fullPath, projectName)
            case ".NET Web API":
                SetupDotNetWebAPI(fullPath, projectName)
            case "Node.js Express":
                SetupNodeExpress(fullPath, projectName)
            case "Python Virtual Env":
                SetupPythonVenv(fullPath, projectName)
        }

        if values.CreateVSCodeConfig
            CreateProjectVSCodeConfig(fullPath)
        if values.InitGit
            RunProjectCommand("git init", fullPath, "Git initialization")

        ProjectManager.AddToRecent(fullPath, projectType)
        GlobalCoderDatabase.LogEvent("project_created", projectType . " | " . fullPath)
        progress.Close()

        if values.OpenVSCode
            ProjectManager.OpenWithVSCode(fullPath)

        GUT_Display("Project Created", projectName . "`n" . fullPath . "`n`n" . projectType, 5000,
            Map("width", 560, "height", 300))
        RebuildMenu()
    } catch as error {
        progress.Close()
        GUT_Display("Project Setup Failed", fullPath . "`n`n" . error.Message, -1,
            Map("width", 650, "height", 420, "persistent", true))
    }
}

SetupDotNetConsole(path, name) {
    RunProjectCommand("dotnet new console --output . --name " . QuoteArgument(name), path, ".NET console setup")
}

SetupDotNetWebAPI(path, name) {
    RunProjectCommand("dotnet new webapi --output . --name " . QuoteArgument(name), path, ".NET Web API setup")
}

SetupDotNetFullSolution(path, name) {
    consoleName := name . ".Console"
    libraryName := name . ".Library"
    RunProjectCommand("dotnet new sln --name " . QuoteArgument(name), path, "solution setup")
    RunProjectCommand("dotnet new console --output " . QuoteArgument(consoleName), path, "console project setup")
    RunProjectCommand("dotnet new classlib --output " . QuoteArgument(libraryName), path, "library project setup")
    consoleProject := consoleName . "\" . consoleName . ".csproj"
    libraryProject := libraryName . "\" . libraryName . ".csproj"
    RunProjectCommand("dotnet sln " . QuoteArgument(name . ".sln") . " add "
        . QuoteArgument(consoleProject) . " " . QuoteArgument(libraryProject), path, "solution membership")
    RunProjectCommand("dotnet add " . QuoteArgument(consoleProject) . " reference " . QuoteArgument(libraryProject),
        path, "project reference")
}

SetupNodeExpress(path, name) {
    RunProjectCommand("npm init -y", path, "npm initialization")
    RunProjectCommand("npm install express", path, "Express installation")
    indexContent := "const express = require('express');`n"
        . "const path = require('path');`n"
        . "const app = express();`n"
        . "const PORT = process.env.PORT || 3000;`n`n"
        . "app.use(express.static(path.join(__dirname, 'public')));`n"
        . "app.use(express.json());`n`n"
        . "app.get('/api/hello', (req, res) => {`n"
        . "    res.json({ message: 'Hello from " . name . "!' });`n"
        . "});`n`n"
        . "app.listen(PORT, () => console.log(``Server: http://localhost:${PORT}``));`n"
    WriteProjectFile(path "\index.js", indexContent)
    if !DirExist(path "\public")
        DirCreate(path "\public")
    html := "<!doctype html>`n<html lang=" . Chr(34) . "en" . Chr(34) . ">`n<head>`n"
        . "  <meta charset=" . Chr(34) . "utf-8" . Chr(34) . ">`n"
        . "  <meta name=" . Chr(34) . "viewport" . Chr(34) . " content=" . Chr(34) . "width=device-width,initial-scale=1" . Chr(34) . ">`n"
        . "  <title>" . name . "</title>`n</head>`n<body>`n"
        . "  <h1>" . name . "</h1>`n  <script src=" . Chr(34) . "main.js" . Chr(34) . "></script>`n"
        . "</body>`n</html>`n"
    WriteProjectFile(path "\public\index.html", html)
    WriteProjectFile(path "\public\main.js", "fetch('/api/hello').then(r => r.json()).then(console.log).catch(console.error);`n")
}

SetupPythonVenv(path, name) {
    RunProjectCommand("python -m venv venv", path, "Python virtual environment")
    pythonContent := Chr(34) . Chr(34) . Chr(34) . name . " entry point." . Chr(34) . Chr(34) . Chr(34) . "`n`n"
        . "def main():`n    print('Hello from " . name . "!')`n`n"
        . "if __name__ == '__main__':`n    main()`n"
    WriteProjectFile(path "\main.py", pythonContent)
    WriteProjectFile(path "\requirements.txt", "# Add project dependencies here.`n")
    WriteProjectFile(path "\.gitignore", "venv/`n__pycache__/`n*.pyc`n")
}

CreateProjectVSCodeConfig(path) {
    vscodeDir := path "\.vscode"
    if !DirExist(vscodeDir)
        DirCreate(vscodeDir)
    settings := "{`n  " . Chr(34) . "files.exclude" . Chr(34) . ": {`n"
        . "    " . Chr(34) . "**/.git" . Chr(34) . ": true,`n"
        . "    " . Chr(34) . "**/__pycache__" . Chr(34) . ": true`n  }`n}`n"
    WriteProjectFile(vscodeDir "\settings.json", settings)
}

RunProjectCommand(command, workingDirectory, label) {
    commandLine := A_ComSpec . " /D /S /C " . Chr(34) . command . Chr(34)
    exitCode := RunWait(commandLine, workingDirectory, "Hide")
    if exitCode != 0
        throw Error(label . " failed with exit code " . exitCode . ".`nCommand: " . command)
}

WriteProjectFile(path, content) {
    GlobalCoderDatabase.SaveContent(path, content, true)
}

ShowRecentProjects(*) {
    ProjectManager.LoadRecentProjects()
    if ProjectManager.RecentProjects.Length = 0 {
        GUT_Display("Recent Projects", "No projects have been recorded yet.`n`nDefault root:`n" . GC_PROJECT_DIR, 4000)
        return
    }
    items := []
    for project in ProjectManager.RecentProjects {
        path := project["path"]
        existsLabel := DirExist(path) ? "" : " [missing]"
        items.Push(Map(
            "text", project["name"] . existsLabel . " - " . path,
            "actionText", "Open VS Code",
            "callback", OpenRecentProject.Bind(path)
        ))
    }
    GUT_Display("Recent Projects", items, -1, Map(
        "itemized", true,
        "width", 780,
        "height", 500,
        "persistent", true,
        "position", "Center"
    ))
}

OpenRecentProject(path) {
    if !DirExist(path) {
        GUT_Display("Project Missing", path . "`n`nThe record remains in SQLite so it can be repaired or relocated.", -1)
        return
    }
    ProjectManager.OpenWithVSCode(path)
}

ShowProjectSettings(*) {
    global GC_VSCodePath, GC_SublimePath, GC_GitBashPath
    guiObj := Gui("+AlwaysOnTop", "Project Settings")
    guiObj.BackColor := "1E1E1E"
    guiObj.OnEvent("Escape", (*) => guiObj.Destroy())
    guiObj.Add("Text", "x12 y12 w420 cE6E6E6", "Default project root")
    guiObj.Add("Edit", "x12 y34 w330 vDefaultRoot Background252526 cFFFFFF",
        GlobalCoderDatabase.GetSetting("Projects", "DefaultRoot", GC_PROJECT_DIR))
    guiObj.Add("Button", "x350 y34 w78", "Browse").OnEvent("Click", (*) => BrowseAndSet(guiObj, "DefaultRoot"))
    guiObj.Add("Text", "x12 y72 w420 cE6E6E6", "VS Code command or Code.exe path")
    guiObj.Add("Edit", "x12 y94 w416 vVSCodePath Background252526 cFFFFFF", GC_VSCodePath)
    guiObj.Add("Text", "x12 y132 w420 cE6E6E6", "Sublime Text executable")
    guiObj.Add("Edit", "x12 y154 w330 vSublimePath Background252526 cFFFFFF", GC_SublimePath)
    guiObj.Add("Button", "x350 y154 w78", "Browse").OnEvent("Click", (*) => BrowseFileAndSet(guiObj, "SublimePath"))
    guiObj.Add("Text", "x12 y192 w420 cE6E6E6", "Git Bash executable")
    guiObj.Add("Edit", "x12 y214 w330 vGitBashPath Background252526 cFFFFFF", GC_GitBashPath)
    guiObj.Add("Button", "x350 y214 w78", "Browse").OnEvent("Click", (*) => BrowseFileAndSet(guiObj, "GitBashPath"))
    guiObj.Add("Button", "x12 y258 w90 h32 Default", "Save").OnEvent("Click", (*) => SaveProjectSettings(guiObj))
    guiObj.Add("Button", "x338 y258 w90 h32", "Cancel").OnEvent("Click", (*) => guiObj.Destroy())
    guiObj.Show("w440 h304")
}

BrowseAndSet(guiObj, controlName) {
    selected := FileSelect("D", guiObj[controlName].Value, "Select folder")
    if selected != ""
        guiObj[controlName].Value := selected
}

BrowseFileAndSet(guiObj, controlName) {
    selected := FileSelect(3, guiObj[controlName].Value, "Select executable", "Executables (*.exe)")
    if selected != ""
        guiObj[controlName].Value := selected
}

SaveProjectSettings(guiObj) {
    values := guiObj.Submit(false)
    GlobalCoderDatabase.SetSetting("Projects", "DefaultRoot", values.DefaultRoot)
    GlobalCoderDatabase.SetSetting("Projects", "VSCodePath", values.VSCodePath)
    GlobalCoderDatabase.SetSetting("Projects", "SublimePath", values.SublimePath)
    GlobalCoderDatabase.SetSetting("Projects", "GitBashPath", values.GitBashPath)
    LoadRuntimeSettings()
    guiObj.Destroy()
    GUT_Display("Settings Saved", "Project settings are now stored in:`n" . GC_DB_PATH, 3000)
}

; ============================================================================
; LEARNING CENTER
; ============================================================================

ShowLearningCenter(*) {
    languages := StepRepository.Languages()
    if languages.Length = 0 {
        GUT_Display("Learning Center", "No tutorial steps exist in the database.", -1)
        return
    }
    guiObj := Gui("+AlwaysOnTop", "GlobalCoder Learning Center")
    guiObj.BackColor := "1E1E1E"
    guiObj.OnEvent("Escape", (*) => guiObj.Destroy())
    heading := guiObj.Add("Text", "x10 y10 w580 h32 c4FC3F7 Center", "Project Setup Learning Center")
    heading.SetFont("s14 bold")
    guiObj.Add("Text", "x12 y54 w150 cE6E6E6", "Language")
    langDrop := guiObj.Add("DropDownList", "x12 y76 w220 vLanguage Choose1", languages)
    guiObj.Add("Text", "x250 y54 w320 cE6E6E6", "Project type")
    projectDrop := guiObj.Add("DropDownList", "x250 y76 w338 vProjectType", [])
    guiObj.Add("Edit", "x12 y118 w576 h210 +ReadOnly Background252526 cE6E6E6 +VScroll vDescription")
    guiObj.Add("Button", "x12 y342 w130 h34 Default", "Launch Tutorial").OnEvent("Click", (*) => LaunchTutorial(guiObj))
    guiObj.Add("Button", "x152 y342 w150 h34", "Instruction Language").OnEvent("Click", (*) => ShowInstructionLanguageConsole())
    guiObj.Add("Button", "x498 y342 w90 h34", "Close").OnEvent("Click", (*) => guiObj.Destroy())
    langDrop.OnEvent("Change", (ctrl, *) => UpdateProjectTypes(guiObj, ctrl.Text))
    projectDrop.OnEvent("Change", (ctrl, *) => UpdateProjectDescription(guiObj, guiObj["Language"].Text, ctrl.Text))
    UpdateProjectTypes(guiObj, languages[1])
    guiObj.Show("w600 h390")
}

UpdateProjectTypes(guiObj, language) {
    types := StepRepository.ProjectTypes(language)
    control := guiObj["ProjectType"]
    control.Delete()
    if types.Length = 0 {
        control.Add(["No project types found"])
        control.Value := 1
        guiObj["Description"].Value := "No tutorials found for " . language
        return
    }
    control.Add(types)
    control.Value := 1
    UpdateProjectDescription(guiObj, language, types[1])
}

UpdateProjectDescription(guiObj, language, projectType) {
    steps := StepRepository.Steps(language, projectType)
    text := projectType . "`n" . RepeatText("-", 72) . "`n"
        . steps.Length . " steps stored in SQLite`n`n"
    for index, step in steps
        text .= index . ". " . step["directions"] . "`n   " . step["command"] . "`n`n"
    guiObj["Description"].Value := text
}

LaunchTutorial(guiObj) {
    language := guiObj["Language"].Text
    projectType := guiObj["ProjectType"].Text
    steps := StepRepository.Steps(language, projectType)
    if steps.Length = 0 {
        MsgBox("Select a valid project type.", "Learning Center", 48)
        return
    }
    guiObj.Destroy()
    StepCanvas(steps, projectType)
}

ShowProjectStepsBrowser(*) {
    ShowLearningCenter()
}

ViewProjectSteps(folderPath, *) {
    stepsPath := folderPath "\steps.txt"
    if !FileExist(stepsPath) {
        GUT_Display("Steps Not Found", stepsPath, 4000)
        return
    }
    projects := StepFileLoader.LoadFile(stepsPath)
    for typeName, steps in projects {
        StepCanvas(steps, typeName)
        return
    }
}

; ============================================================================
; KNOWLEDGE WEB
; ============================================================================

ShowAddKnowledgeGUI(*) {
    guiObj := Gui("+AlwaysOnTop +Resize", "Add Knowledge")
    guiObj.BackColor := "1E1E1E"
    guiObj.OnEvent("Escape", (*) => guiObj.Destroy())
    guiObj.Add("Text", "x12 y12 w520 cE6E6E6", "Title")
    titleEdit := guiObj.Add("Edit", "x12 y34 w556 vTitle Background252526 cFFFFFF")
    titleEdit.Focus()
    guiObj.Add("Text", "x12 y72 w250 cE6E6E6", "Language / platform")
    guiObj.Add("Edit", "x12 y94 w260 vLanguage Background252526 cFFFFFF")
    guiObj.Add("Text", "x308 y72 w260 cE6E6E6", "Shared feature or concept")
    guiObj.Add("Edit", "x308 y94 w260 vFeature Background252526 cFFFFFF")
    guiObj.Add("Text", "x12 y132 w556 cE6E6E6", "Points of truth, procedure, example, and verification")
    guiObj.Add("Edit", "x12 y154 w556 h250 vContent Background252526 cFFFFFF +Multi +VScroll")
    guiObj.Add("Button", "x12 y418 w100 h34 Default", "Save").OnEvent("Click", (*) => SaveKnowledge(guiObj))
    guiObj.Add("Button", "x468 y418 w100 h34", "Cancel").OnEvent("Click", (*) => guiObj.Destroy())
    guiObj.Show("w580 h466")
}

SaveKnowledge(guiObj) {
    values := guiObj.Submit(false)
    if Trim(values.Title) = "" || Trim(values.Content) = "" {
        MsgBox("Title and content are required.", "Add Knowledge", 48)
        return
    }
    nodeId := KnowledgeBase.Add(Trim(values.Title), values.Content, Trim(values.Language), Trim(values.Feature))
    guiObj.Destroy()
    GUT_Display("Knowledge Saved", "Node " . nodeId . " was saved.`n`n"
        . "Sparse notes automatically receive gap prompts for prerequisites, examples, failures, verification, and links.", 5000,
        Map("width", 620, "height", 330))
}

ShowKnowledgeSearch(*) {
    result := InputBox("Search titles, content, languages, and shared features:", "Knowledge Search", "w420 h130")
    if result.Result = "Cancel"
        return
    rows := KnowledgeBase.Search(Trim(result.Value))
    if rows.Length = 0 {
        GUT_Display("Knowledge Search", "No matching knowledge nodes.", 3000)
        return
    }
    items := []
    for row in rows {
        summary := row["title"]
        if row["language"] != ""
            summary .= " [" . row["language"] . "]"
        if row["feature"] != ""
            summary .= " / " . row["feature"]
        items.Push(Map(
            "text", summary,
            "actionText", "View",
            "callback", ShowKnowledgeNode.Bind(row["id"])
        ))
    }
    GUT_Display("Knowledge Results (" . rows.Length . ")", items, -1,
        Map("itemized", true, "width", 760, "height", 500, "persistent", true, "position", "Center"))
}

ShowKnowledgeNode(nodeId, *) {
    rows := GlobalCoderDatabase.Rows("SELECT id,title,node_type,language,feature,content,confidence,importance,use_count,updated_at "
        . "FROM knowledge_nodes WHERE id=" . Integer(nodeId) . " LIMIT 1;")
    if rows.Length = 0
        return
    row := rows[1]
    KnowledgeBase.RecordUse(nodeId)
    edges := GlobalCoderDatabase.Rows("SELECT e.relation,n.title FROM knowledge_edges e JOIN knowledge_nodes n ON n.id=e.to_node_id "
        . "WHERE e.from_node_id=" . Integer(nodeId) . " ORDER BY e.strength DESC;")
    text := row["content"] . "`n`n" . RepeatText("-", 70) . "`n"
        . "Language: " . row["language"] . "`nFeature: " . row["feature"]
        . "`nUses: " . row["use_count"] . "`nUpdated: " . row["updated_at"]
    if edges.Length > 0 {
        text .= "`n`nLinks:`n"
        for edge in edges
            text .= "- " . edge["relation"] . " -> " . edge["title"] . "`n"
    }
    GUT_Display(row["title"], text, -1, Map("width", 760, "height", 560, "persistent", true, "position", "Center"))
}

ShowKnowledgeTest(*) {
    node := KnowledgeBase.NextReview()
    if !IsObject(node) {
        GUT_Display("Knowledge Test", "Add at least one knowledge node before starting a recall test.", 3500)
        return
    }
    context := node["title"]
    if node["language"] != ""
        context .= " [" . node["language"] . "]"
    if node["feature"] != ""
        context .= " / " . node["feature"]
    prompt := "Without looking at the saved note, write the key facts, procedure, example, and verification for:`n`n" . context
    options := Map(
        "width", 700,
        "height", 500,
        "inputPrompt", prompt,
        "onSubmit", GradeKnowledgeRecall.Bind(node["id"], node["title"], node["content"]),
        "persistent", true,
        "position", "Center"
    )
    GUT_Display("Knowledge Recall Test", "", -1, options)
}

GradeKnowledgeRecall(nodeId, title, truth, response) {
    items := [
        Map("text", "I missed most of it", "actionText", "Review tomorrow", "callback", SaveKnowledgeReview.Bind(nodeId, response, 0)),
        Map("text", "I remembered some", "actionText", "Review in 2 days", "callback", SaveKnowledgeReview.Bind(nodeId, response, 1)),
        Map("text", "I remembered the core", "actionText", "Review in 7 days", "callback", SaveKnowledgeReview.Bind(nodeId, response, 2)),
        Map("text", "I knew it well", "actionText", "Review in 14 days", "callback", SaveKnowledgeReview.Bind(nodeId, response, 3))
    ]
    comparison := "YOUR RECALL`n" . RepeatText("-", 70) . "`n" . response
        . "`n`nSAVED POINTS OF TRUTH`n" . RepeatText("-", 70) . "`n" . truth
    GUT_Display("Self-grade: " . title, comparison . "`n`nSelect a rating below.", -1,
        Map("width", 820, "height", 620, "persistent", true, "position", "Center"))
    GUT_Display("Choose Recall Rating", items, -1,
        Map("itemized", true, "width", 650, "height", 420, "persistent", true, "position", "BottomRight"))
}

SaveKnowledgeReview(nodeId, response, rating, *) {
    KnowledgeBase.RecordReview(nodeId, response, rating)
    GUT_Display("Review Scheduled", "Your recall was recorded in SQLite and the next review interval was scheduled.", 3500)
}

; ============================================================================
; AUTOHOTKEY-BACKED WINDOWS INSTRUCTION LANGUAGE
; ============================================================================

ShowInstructionLanguageConsole(*) {
    guiObj := Gui("+AlwaysOnTop +Resize", "GlobalCoder Windows Instruction Language")
    guiObj.BackColor := "1E1E1E"
    guiObj.OnEvent("Escape", (*) => guiObj.Destroy())
    heading := guiObj.Add("Text", "x12 y10 w696 h28 c4FC3F7", "Readable instructions mapped to AutoHotkey v2")
    heading.SetFont("s12 bold")
    guiObj.Add("Text", "x12 y43 w90 cE6E6E6", "Program name")
    guiObj.Add("Edit", "x108 y40 w300 vProgramName Background252526 cFFFFFF", "My Windows Automation")
    guiObj.Add("Text", "x12 y75 w696 cA8C7E6", "One command per line. Fields use |. Escape a literal pipe as \p and a newline as \n.")
    sample := "; GlobalCoder instruction program`n"
        . "RUN|notepad.exe`n"
        . "WINDOW.WAIT|Untitled - Notepad|5`n"
        . "ACTIVATE|Untitled - Notepad`n"
        . "TEXT|Hello from GlobalCoder v7!`n"
        . "SEND|^s`n"
        . "OVERLAY|Done|The instruction program completed."
    programEdit := guiObj.Add("Edit", "x12 y100 w696 h360 vProgramSource Background252526 cFFFFFF +Multi +VScroll +HScroll", sample)
    programEdit.SetFont("s10", "Consolas")
    guiObj.Add("Button", "x12 y474 w100 h34 Default", "Run").OnEvent("Click", (*) => RunInstructionProgram(guiObj))
    guiObj.Add("Button", "x122 y474 w100 h34", "Save").OnEvent("Click", (*) => SaveInstructionProgram(guiObj))
    guiObj.Add("Button", "x232 y474 w130 h34", "Command Reference").OnEvent("Click", (*) => ShowInstructionReference())
    guiObj.Add("Button", "x618 y474 w90 h34", "Close").OnEvent("Click", (*) => guiObj.Destroy())
    guiObj.Show("w720 h522")
}

RunInstructionProgram(guiObj) {
    values := guiObj.Submit(false)
    name := Trim(values.ProgramName) = "" ? "Ad hoc" : Trim(values.ProgramName)
    try {
        count := WindowInstructionLanguage.Execute(values.ProgramSource, name)
        GlobalCoderDatabase.Exec("INSERT INTO instruction_programs(name,source,run_count,last_run) VALUES("
            . GlobalCoderDatabase.Q(name) . "," . GlobalCoderDatabase.Q(values.ProgramSource)
            . ",1,datetime('now','localtime'));")
        GUT_Display("Instruction Program Complete", count . " commands executed.`n" . name, 3500)
    } catch as error {
        GUT_Display("Instruction Program Stopped", error.Message, -1,
            Map("width", 680, "height", 440, "persistent", true))
    }
}

SaveInstructionProgram(guiObj) {
    values := guiObj.Submit(false)
    name := Trim(values.ProgramName)
    if name = "" {
        MsgBox("Enter a program name.", "Instruction Language", 48)
        return
    }
    GlobalCoderDatabase.Exec("INSERT INTO instruction_programs(name,source) VALUES("
        . GlobalCoderDatabase.Q(name) . "," . GlobalCoderDatabase.Q(values.ProgramSource) . ");")
    GUT_Display("Program Saved", name . "`nStored in the GlobalCoder SQLite database.", 3000)
}

ShowInstructionReference(*) {
    rows := GlobalCoderDatabase.Rows("SELECT name,syntax,ahk_mapping,description,example FROM instruction_commands ORDER BY name;")
    items := []
    for row in rows {
        items.Push(Map(
            "text", row["syntax"] . "  ->  " . row["ahk_mapping"],
            "actionText", "Copy example",
            "copyCommand", row["example"]
        ))
    }
    GUT_Display("Windows Instruction Language Reference", items, -1,
        Map("itemized", true, "width", 920, "height", 600, "persistent", true, "position", "Center"))
}

; ============================================================================
; SEARCH, QUERY HISTORY, HOTSTRINGS, AND ACTION DEFINITIONS
; ============================================================================

GoogleSearchWithLogging(*) {
    result := InputBox("Enter a search query. It will be stored in SQLite:", "Google Search", "w420 h130")
    if result.Result = "Cancel" || Trim(result.Value) = ""
        return
    query := Trim(result.Value)
    context := ""
    try context := WinGetTitle("A")
    GlobalCoderDatabase.LogQuery(query, "google", context)
    Run("https://www.google.com/search?q=" . UrlEncode(query) . "&as_qdr=y1")
    GUT_Display("Search Logged", query . "`n`nDatabase: " . GC_DB_PATH, 2500)
}

GoogleSearch(*) {
    GoogleSearchWithLogging()
}

ShowQueryLog(*) {
    rows := GlobalCoderDatabase.Rows("SELECT query,provider,context,created_at FROM queries ORDER BY id DESC LIMIT 500;")
    if rows.Length = 0 {
        GUT_Display("Query History", "No searches have been logged.", 3000)
        return
    }
    items := []
    for row in rows {
        items.Push(Map(
            "text", row["created_at"] . " | " . row["query"],
            "actionText", row["provider"],
            "copyCommand", row["query"]
        ))
    }
    GUT_Display("Query History (SQLite)", items, -1,
        Map("itemized", true, "width", 860, "height", 560, "persistent", true, "position", "Center"))
}

PasteHotstring(replacement, *) {
    SendText(replacement)
}

ShowHotstringsGUI(*) {
    guiObj := Gui("+AlwaysOnTop", "SQLite Hotstrings")
    guiObj.BackColor := "1E1E1E"
    guiObj.OnEvent("Escape", (*) => guiObj.Destroy())
    guiObj.Add("Text", "x12 y12 w160 cE6E6E6", "Trigger")
    guiObj.Add("Edit", "x12 y34 w180 vTrigger Background252526 cFFFFFF")
    guiObj.Add("Text", "x210 y12 w350 cE6E6E6", "Replacement")
    guiObj.Add("Edit", "x210 y34 w358 h150 vReplacement Background252526 cFFFFFF +Multi +VScroll")
    rows := GlobalCoderDatabase.Rows("SELECT trigger,replacement,category FROM hotstrings ORDER BY trigger;")
    list := guiObj.Add("ListView", "x12 y196 w556 h210 -Multi +Grid Background252526 cE6E6E6", ["Trigger", "Replacement"])
    for row in rows
        list.Add(, row["trigger"], SubStr(StrReplace(row["replacement"], "`n", " "), 1, 90))
    list.ModifyCol(1, 140), list.ModifyCol(2, 390)
    guiObj.Add("Button", "x12 y420 w90 h32 Default", "Save").OnEvent("Click", (*) => SaveHotstring(guiObj))
    guiObj.Add("Button", "x478 y420 w90 h32", "Close").OnEvent("Click", (*) => guiObj.Destroy())
    guiObj.Show("w580 h466")
}

SaveHotstring(guiObj) {
    values := guiObj.Submit(false)
    trigger := Trim(values.Trigger)
    if trigger = "" || values.Replacement = "" {
        MsgBox("Enter a trigger and replacement.", "Hotstrings", 48)
        return
    }
    if RegExMatch(trigger, "\s") {
        MsgBox("A hotstring trigger cannot contain whitespace.", "Hotstrings", 48)
        return
    }
    GlobalCoderDatabase.Exec("INSERT INTO hotstrings(trigger,replacement) VALUES("
        . GlobalCoderDatabase.Q(trigger) . "," . GlobalCoderDatabase.Q(values.Replacement) . ") "
        . "ON CONFLICT(trigger) DO UPDATE SET replacement=excluded.replacement,enabled=1;")
    HotstringManager.ReloadCustom()
    guiObj.Destroy()
    GUT_Display("Hotstring Saved", trigger . " is active.", 2500)
}

ShowAddActionGUI(*) {
    guiObj := Gui("+AlwaysOnTop", "Add Action Definition")
    guiObj.BackColor := "1E1E1E"
    guiObj.OnEvent("Escape", (*) => guiObj.Destroy())
    guiObj.Add("Text", "x12 y12 w360 cE6E6E6", "Display name")
    guiObj.Add("Edit", "x12 y34 w376 vActionName Background252526 cFFFFFF")
    guiObj.Add("Text", "x12 y72 w360 cE6E6E6", "Function name")
    guiObj.Add("Edit", "x12 y94 w376 vFunctionName Background252526 cFFFFFF", "Action_")
    guiObj.Add("Text", "x12 y132 w360 cE6E6E6", "Description")
    guiObj.Add("Edit", "x12 y154 w376 h70 vDescription Background252526 cFFFFFF +Multi")
    guiObj.Add("Button", "x12 y238 w90 h32 Default", "Save").OnEvent("Click", (*) => AddActionItem(guiObj))
    guiObj.Add("Button", "x298 y238 w90 h32", "Cancel").OnEvent("Click", (*) => guiObj.Destroy())
    guiObj.Show("w400 h284")
}

AddActionItem(guiObj) {
    values := guiObj.Submit(false)
    if Trim(values.ActionName) = "" || Trim(values.FunctionName) = "" {
        MsgBox("Name and function are required.", "Action Definition", 48)
        return
    }
    GlobalCoderDatabase.Exec("INSERT INTO actions(name,function_name,description) VALUES("
        . GlobalCoderDatabase.Q(Trim(values.ActionName)) . "," . GlobalCoderDatabase.Q(Trim(values.FunctionName)) . ","
        . GlobalCoderDatabase.Q(values.Description) . ") ON CONFLICT(name) DO UPDATE SET "
        . "function_name=excluded.function_name,description=excluded.description,enabled=1;")
    guiObj.Destroy()
    GUT_Display("Action Saved", values.ActionName . " is stored in SQLite.", 2500)
}

BuildActionsMenu(contextPath) {
    rows := GlobalCoderDatabase.Rows("SELECT name,function_name,description FROM actions WHERE enabled=1 ORDER BY name;")
    items := []
    for row in rows
        items.Push(Map("label", row["name"], "function", row["function_name"], "context", contextPath))
    return items.Length > 0 ? SafeMenuBuilder.Build(items, ExecuteActionItem) : ""
}

ExecuteActionItem(item, *) {
    ExecuteAction(item["function"], item["context"])
}

ExecuteAction(functionName, contextPath) {
    switch functionName {
        case "Action_DumpClipboard":
            Action_DumpClipboard(contextPath)
        case "Action_NewFolder":
            Action_NewFolder(contextPath)
        case "Action_NewFile":
            Action_NewFile(contextPath)
        case "Action_OpenFolder":
            Action_OpenFolder(contextPath)
        case "Action_CaptureStructure":
            Action_CaptureStructure(contextPath)
        default:
            GUT_Display("Unknown Action", functionName . "`n`nThe definition remains in SQLite for repair.", -1)
    }
}

FindInFiles(*) {
    result := InputBox("Search indexed content and knowledge:", "Global Search", "w420 h130")
    if result.Result = "Cancel" || Trim(result.Value) = ""
        return
    searchText := Trim(result.Value)
    IndexLibraryTextFiles()
    likeValue := "%" . searchText . "%"
    contentRows := GlobalCoderDatabase.Rows("SELECT path,title,content_type,updated_at FROM content_items WHERE title LIKE "
        . GlobalCoderDatabase.Q(likeValue) . " OR content LIKE " . GlobalCoderDatabase.Q(likeValue)
        . " ORDER BY updated_at DESC LIMIT 100;")
    knowledgeRows := KnowledgeBase.Search(searchText, 100)
    items := []
    for row in knowledgeRows
        items.Push(Map("text", "[Knowledge] " . row["title"], "actionText", "View", "callback", ShowKnowledgeNode.Bind(row["id"])))
    for row in contentRows
        items.Push(Map("text", "[Content] " . row["path"], "actionText", "Open", "callback", MenuEventHandler.Bind(row["path"])))
    if items.Length = 0 {
        GUT_Display("Global Search", "No matches for: " . searchText, 3000)
        return
    }
    GUT_Display("Global Search: " . searchText, items, -1,
        Map("itemized", true, "width", 900, "height", 600, "persistent", true, "position", "Center"))
}

IndexLibraryTextFiles() {
    allowed := Map("txt", true, "md", true, "ahk", true, "json", true, "html", true, "htm", true,
        "css", true, "js", true, "ts", true, "py", true, "cs", true, "ini", true, "steps", true,
        "note", true, "dump", true, "action", true, "sql", true, "ps1", true, "cmd", true, "bat", true)
    try {
        Loop Files, GC_LIBRARY_DIR "\*", "RF" {
            extension := StrLower(A_LoopFileExt)
            if allowed.Has(extension) && A_LoopFileSize < 5000000
                GlobalCoderDatabase.GetContent(A_LoopFilePath)
        }
    }
}

; ============================================================================
; CONTEXT ACTIONS
; ============================================================================

Action_DumpClipboard(folderPath) {
    content := A_Clipboard
    if content = "" {
        GUT_Display("Dump Clipboard", "The clipboard is empty.", 2500)
        return
    }
    contextKey := NormalizePath(folderPath)
    virtualPath := "db://clipboard-dumps/" . Format("{:08X}", HashText(contextKey))
    existing := GlobalCoderDatabase.GetContent(virtualPath)
    title := ""
    try title := WinGetTitle("A")
    entry := (existing != "" ? existing . "`n`n" : "")
        . RepeatText("=", 72) . "`n"
        . FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") . " | " . title . "`n"
        . RepeatText("=", 72) . "`n" . content
    GlobalCoderDatabase.SaveContent(virtualPath, entry, false)
    GUT_Display("Clipboard Stored", "SQLite dump context:`n" . contextKey . "`n`nCharacters: " . StrLen(content), 3500)
}

Action_NewFolder(folderPath) {
    result := InputBox("New folder name:", "Create Folder", "w340 h125")
    if result.Result = "Cancel" || !IsSafeFileName(Trim(result.Value))
        return
    newPath := RTrim(folderPath, "\/") . "\" . Trim(result.Value)
    if DirExist(newPath) {
        GUT_Display("Folder Exists", newPath, 3000)
        return
    }
    DirCreate(newPath)
    GlobalCoderDatabase.LogEvent("folder_created", newPath)
    RebuildMenu()
}

Action_NewFile(folderPath) {
    guiObj := Gui("+AlwaysOnTop", "Create and Index File")
    guiObj.BackColor := "1E1E1E"
    guiObj.targetFolder := folderPath
    guiObj.OnEvent("Escape", (*) => guiObj.Destroy())
    guiObj.Add("Text", "x12 y12 w376 cE6E6E6", "Filename with extension")
    nameEdit := guiObj.Add("Edit", "x12 y34 w376 vFileName Background252526 cFFFFFF")
    nameEdit.Focus()
    guiObj.Add("Checkbox", "x12 y72 vUseClipboard cE6E6E6", "Use clipboard as initial content")
    guiObj.Add("Button", "x12 y108 w90 h32 Default", "Create").OnEvent("Click", (*) => CreateFileFromGUI(guiObj))
    guiObj.Add("Button", "x298 y108 w90 h32", "Cancel").OnEvent("Click", (*) => guiObj.Destroy())
    guiObj.Show("w400 h154")
}

CreateFileFromGUI(guiObj) {
    values := guiObj.Submit(false)
    fileName := Trim(values.FileName)
    if !IsSafeFileName(fileName) {
        MsgBox("Enter a safe filename.", "Create File", 48)
        return
    }
    path := RTrim(guiObj.targetFolder, "\/") . "\" . fileName
    if FileExist(path) {
        MsgBox("The file already exists:`n" . path, "Create File", 48)
        return
    }
    content := values.UseClipboard ? A_Clipboard : ""
    GlobalCoderDatabase.SaveContent(path, content, true)
    guiObj.Destroy()
    RebuildMenu()
    GUT_Display("File Created and Indexed", path, 3000)
}

Action_OpenFolder(folderPath) {
    Run("explorer.exe " . QuoteArgument(folderPath))
}

Action_CaptureStructure(folderPath) {
    tree := GenerateFolderTree(folderPath)
    GlobalCoderDatabase.UpsertContent("db://folder-trees/" . Format("{:08X}", HashText(folderPath)), tree, "tree")
    GUT_Display("Folder Structure", tree, -1,
        Map("width", 760, "height", 600, "persistent", true, "position", "Center"))
}

GenerateFolderTree(path, indent := "", isLast := true) {
    SplitPath(path, &name)
    if name = ""
        name := path
    text := indent . (isLast ? "\-- " : "+-- ") . name . "`n"
    childIndent := indent . (isLast ? "    " : "|   ")
    children := []
    try {
        Loop Files, path "\*", "DF"
            children.Push(Map("path", A_LoopFilePath, "name", A_LoopFileName, "directory", InStr(A_LoopFileAttrib, "D") > 0))
    }
    for index, child in children {
        lastChild := index = children.Length
        if child["directory"]
            text .= GenerateFolderTree(child["path"], childIndent, lastChild)
        else
            text .= childIndent . (lastChild ? "\-- " : "+-- ") . child["name"] . "`n"
    }
    return text
}

; ============================================================================
; FILE HANDLERS AND DATABASE-BACKED EDITING
; ============================================================================

MenuEventHandler(filePath, *) {
    if filePath = ""
        return
    if SubStr(filePath, 1, 5) = "db://" {
        content := GlobalCoderDatabase.GetContent(filePath)
        GUT_Display(filePath, content, -1, Map("width", 760, "height", 560, "persistent", true))
        return
    }
    SplitPath(filePath, , , &extension)
    switch StrLower(extension) {
        case "txt":
            Handler_txt(filePath)
        case "rtf":
            Handler_RTF(filePath)
        case "dump":
            Handler_dump(filePath)
        case "action":
            Handler_Action(filePath)
        case "note":
            Handler_note(filePath)
        case "ahk":
            Handler_Ahk(filePath)
        case "json", "md", "css", "js", "ts", "py", "cs", "ini", "sql", "ps1":
            Handler_default(filePath)
        case "html", "htm":
            Handler_html(filePath)
        case "exe", "bat", "cmd":
            Handler_LaunchProgram(filePath)
        case "steps":
            Handler_steps(filePath)
        default:
            if FileExist(filePath)
                Run(filePath)
    }
}

Handler_txt(path) {
    content := GlobalCoderDatabase.GetContent(path)
    A_Clipboard := content
    Send("^v")
}

Handler_steps(filePath) {
    projects := StepFileLoader.LoadFile(filePath)
    if projects.Count = 0 {
        GUT_Display("No Steps", "No valid tutorial steps were found.", 3000)
        return
    }
    items := []
    for projectType, steps in projects
        items.Push(Map("text", projectType . " (" . steps.Length . " steps)", "actionText", "Open", "callback", LaunchStepCanvas.Bind(steps, projectType)))
    GUT_Display("Select Tutorial", items, -1,
        Map("itemized", true, "width", 620, "height", 450, "persistent", true, "position", "Center"))
}

Handler_default(path) {
    if !FileExist(path) {
        GUT_Display("File Not Found", path, 3500)
        return
    }
    content := GlobalCoderDatabase.GetContent(path)
    SplitPath(path, &fileName)
    options := Map(
        "width", 820,
        "height", 620,
        "inputPrompt", "Edit " . fileName . "`nChanges are committed to SQLite and mirrored to the physical file.",
        "onSubmit", SaveEditedContent.Bind(path),
        "persistent", true,
        "position", "Center"
    )
    GUT_Display("Database-backed Editor", content, -1, options)
}

SaveEditedContent(path, content) {
    try {
        GlobalCoderDatabase.SaveContent(path, content, true)
        GUT_Display("Saved", path . "`n`nSQLite and the editor-facing file now match.", 3000)
    } catch as error {
        GUT_Display("Save Failed", error.Message, -1)
    }
}

Handler_RTF(filePath) {
    try {
        word := ComObject("Word.Application")
        document := word.Documents.Open(filePath)
        document.Range.FormattedText.Copy()
        document.Close(0)
        word.Quit()
        if ClipWait(2)
            Send("^v")
    } catch as error {
        GUT_Display("RTF Error", error.Message, -1)
    }
}

Handler_dump(path) {
    clipboardText := A_Clipboard
    if clipboardText = ""
        return
    existing := GlobalCoderDatabase.GetContent(path)
    updated := existing . "`n`n" . RepeatText("=", 64) . "`n"
        . FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") . "`n" . RepeatText("=", 64) . "`n" . clipboardText
    GlobalCoderDatabase.SaveContent(path, updated, true)
    GUT_Display("Dump Updated", path, 2500)
}

Handler_Action(filePath) {
    SplitPath(filePath, , &parent, , &nameNoExt)
    switch StrLower(nameNoExt) {
        case "dump":
            Action_DumpClipboard(parent)
        case "newfolder":
            Action_NewFolder(parent)
        case "newfile":
            Action_NewFile(parent)
        case "openfolder":
            Action_OpenFolder(parent)
        case "capturestructure":
            Action_CaptureStructure(parent)
        default:
            GUT_Display("Unknown Action File", nameNoExt, -1)
    }
}

Handler_note(path) {
    content := GlobalCoderDatabase.GetContent(path)
    lines := StrSplit(content, "`n", "`r")
    if lines.Length > 1 {
        body := ""
        Loop lines.Length - 1
            body .= (A_Index > 1 ? "`n" : "") . lines[A_Index + 1]
        A_Clipboard := body
        Send("^v")
    }
}

Handler_Ahk(filePath) {
    items := [
        Map("label", "View / Edit (database-backed)", "callback", (*) => Handler_default(filePath)),
        Map("label", "Open in VS Code", "callback", (*) => ProjectManager.OpenWithVSCode(filePath)),
        Map("label", "Run Script", "callback", (*) => Run(filePath)),
        Map("label", "Open Containing Folder", "callback", (*) => Run("explorer.exe /select," . QuoteArgument(filePath)))
    ]
    SafeMenuBuilder.Build(items, RunMenuCallback).Show()
}

RunMenuCallback(item, *) {
    item["callback"].Call()
}

ViewAhkInGUT(filePath) {
    Handler_default(filePath)
}

Handler_json(filePath) {
    Handler_default(filePath)
}

Handler_html(filePath) {
    menuItems := [
        Map("label", "Open in Browser", "callback", (*) => Run(filePath)),
        Map("label", "View / Edit Source", "callback", (*) => Handler_default(filePath))
    ]
    SafeMenuBuilder.Build(menuItems, RunMenuCallback).Show()
}

Handler_LaunchProgram(filePath) {
    Run(filePath)
}

; ============================================================================
; SETTINGS AND DASHBOARD
; ============================================================================

ShowSettingsGUI(*) {
    global GC_OverlayTimeout, GC_OverlayOpacity, GC_OverlayWidth, GC_OverlayHeight
    guiObj := Gui("+AlwaysOnTop", "GlobalCoder v7 Settings")
    guiObj.BackColor := "1E1E1E"
    guiObj.OnEvent("Escape", (*) => guiObj.Destroy())
    guiObj.Add("GroupBox", "x12 y10 w416 h180 cE6E6E6", "Shared Overlay Settings")
    guiObj.Add("Text", "x24 y38 w180 cE6E6E6", "Auto-dismiss timeout (ms)")
    guiObj.Add("Edit", "x220 y35 w110 vTimeout Background252526 cFFFFFF", GC_OverlayTimeout)
    guiObj.Add("Text", "x24 y75 w180 cE6E6E6", "Opacity (140-255)")
    guiObj.Add("Edit", "x220 y72 w110 vOpacity Background252526 cFFFFFF", GC_OverlayOpacity)
    guiObj.Add("Text", "x24 y112 w180 cE6E6E6", "Default width")
    guiObj.Add("Edit", "x220 y109 w110 vWidth Background252526 cFFFFFF", GC_OverlayWidth)
    guiObj.Add("Text", "x24 y149 w180 cE6E6E6", "Default height")
    guiObj.Add("Edit", "x220 y146 w110 vHeight Background252526 cFFFFFF", GC_OverlayHeight)
    guiObj.Add("Checkbox", "x16 y206 vPromptOnResume cE6E6E6 "
        . (GlobalCoderDatabase.GetSetting("Knowledge", "PromptOnResume", "1") = "1" ? "Checked" : ""),
        "Prompt for a due knowledge gap after a long idle period")
    guiObj.Add("Text", "x12 y244 w416 h45 cA8C7E6", "All application state: " . GC_DB_PATH)
    guiObj.Add("Button", "x12 y296 w90 h32 Default", "Save").OnEvent("Click", (*) => SaveSettings(guiObj))
    guiObj.Add("Button", "x112 y296 w120 h32", "Project Paths").OnEvent("Click", (*) => ShowProjectSettings())
    guiObj.Add("Button", "x338 y296 w90 h32", "Cancel").OnEvent("Click", (*) => guiObj.Destroy())
    guiObj.Show("w440 h342")
}

SaveSettings(guiObj) {
    values := guiObj.Submit(false)
    timeout := Max(-1, ToInteger(values.Timeout, 5000))
    opacity := Max(140, Min(255, ToInteger(values.Opacity, 235)))
    width := Max(420, ToInteger(values.Width, 600))
    height := Max(260, ToInteger(values.Height, 400))
    GlobalCoderDatabase.SetSetting("Overlay", "Timeout", timeout)
    GlobalCoderDatabase.SetSetting("Overlay", "Opacity", opacity)
    GlobalCoderDatabase.SetSetting("Overlay", "Width", width)
    GlobalCoderDatabase.SetSetting("Overlay", "Height", height)
    GlobalCoderDatabase.SetSetting("Knowledge", "PromptOnResume", values.PromptOnResume ? "1" : "0")
    LoadRuntimeSettings()
    guiObj.Destroy()
    GUT_Display("Settings Saved", "All transparent boxes now use the updated shared controls.", 3000)
}

ShowMainFeaturesGUI(*) {
    guiObj := Gui("+AlwaysOnTop", "GlobalCoder v7")
    guiObj.BackColor := "1E1E1E"
    guiObj.OnEvent("Escape", (*) => guiObj.Destroy())
    heading := guiObj.Add("Text", "x12 y12 w376 h34 c4FC3F7 Center", "GlobalCoder v7")
    heading.SetFont("s15 bold")
    buttons := [
        ["Browse Global Library", ShowCustomMenu],
        ["Create New Project", ShowNewProjectWizard],
        ["Recent Projects", ShowRecentProjects],
        ["Learning Center", ShowLearningCenter],
        ["Knowledge Web", ShowKnowledgeSearch],
        ["Add Knowledge", ShowAddKnowledgeGUI],
        ["Knowledge Recall Test", ShowKnowledgeTest],
        ["Windows Instruction Language", ShowInstructionLanguageConsole],
        ["Global Search", FindInFiles],
        ["Settings", ShowSettingsGUI]
    ]
    y := 56
    for item in buttons {
        guiObj.Add("Button", "x12 y" . y . " w376 h34", item[1]).OnEvent("Click", DashboardButtonClicked.Bind(guiObj, item[2]))
        y += 42
    }
    guiObj.Add("Button", "x12 y" . (y + 4) . " w376 h32", "Close").OnEvent("Click", (*) => guiObj.Destroy())
    guiObj.Show("w400 h" . (y + 50))
}

; ============================================================================
; SMALL FEATURES AND DEMOS
; ============================================================================

AddClassNote(*) {
    result := InputBox("Class name:", "Add C# Class Knowledge", "w340 h125")
    if result.Result = "Cancel" || !IsSafeFileName(Trim(result.Value))
        return
    className := Trim(result.Value)
    template := "public class " . className . "`n{`n    public " . className . "()`n    {`n    }`n}`n"
    nodeId := KnowledgeBase.Add(className, template, "C#", "class", "code")
    A_Clipboard := template
    GUT_Display("Class Knowledge Added", className . " is knowledge node " . nodeId . ".`nThe template is on the clipboard.", 3500)
}

ShowClasses(*) {
    rows := GlobalCoderDatabase.Rows("SELECT id,title,content FROM knowledge_nodes WHERE language='C#' AND feature='class' ORDER BY use_count DESC,title;")
    items := []
    for row in rows
        items.Push(Map("text", row["title"], "actionText", "View", "callback", ShowKnowledgeNode.Bind(row["id"])))
    if items.Length = 0
        GUT_Display("C# Classes", "No class knowledge has been captured.", 3000)
    else
        GUT_Display("C# Classes", items, -1, Map("itemized", true, "width", 560, "height", 440, "persistent", true))
}

DemoGUTDisplay(*) {
    items := [
        Map("text", "Arrow-key selection", "actionText", "Built in"),
        Map("text", "Escape dismissal", "actionText", "Built in"),
        Map("text", "Right-drag from any surface", "actionText", "Built in"),
        Map("text", "Screen-clamped focused display", "actionText", "Built in"),
        Map("text", "Input, timeout, opacity, copy, and pin controls", "actionText", "Built in")
    ]
    GUT_Display("Shared Overlay Demo", items, -1,
        Map("itemized", true, "width", 680, "height", 440, "persistent", true, "position", "Center"))
}

DemoStepCanvas(*) {
    types := StepRepository.ProjectTypes("JavaScript")
    if types.Length > 0
        StepCanvas(StepRepository.Steps("JavaScript", types[1]), types[1])
}

; ============================================================================
; SHARED HELPERS
; ============================================================================

UrlEncode(text) {
    byteCount := StrPut(text, "UTF-8")
    buffer := Buffer(byteCount, 0)
    StrPut(text, buffer, "UTF-8")
    encoded := ""
    Loop byteCount - 1 {
        byte := NumGet(buffer, A_Index - 1, "UChar")
        if (byte >= 0x30 && byte <= 0x39)
            || (byte >= 0x41 && byte <= 0x5A)
            || (byte >= 0x61 && byte <= 0x7A)
            || byte = 0x2D || byte = 0x2E || byte = 0x5F || byte = 0x7E
            encoded .= Chr(byte)
        else if byte = 0x20
            encoded .= "+"
        else
            encoded .= "%" . Format("{:02X}", byte)
    }
    return encoded
}

GetActiveMonitorWorkArea(&left, &top, &right, &bottom) {
    monitorIndex := MonitorGetPrimary()
    try {
        hwnd := WinExist("A")
        WinGetPos(&windowX, &windowY, &windowWidth, &windowHeight, "ahk_id " . hwnd)
        centerX := windowX + (windowWidth // 2)
        centerY := windowY + (windowHeight // 2)
        Loop MonitorGetCount() {
            MonitorGet(A_Index, &monitorLeft, &monitorTop, &monitorRight, &monitorBottom)
            if centerX >= monitorLeft && centerX < monitorRight && centerY >= monitorTop && centerY < monitorBottom {
                monitorIndex := A_Index
                break
            }
        }
    }
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)
}

NormalizePath(path) {
    if SubStr(path, 1, 5) = "db://"
        return path
    return StrReplace(path, "/", "\")
}

QuoteArgument(value) {
    return Chr(34) . StrReplace(String(value), Chr(34), "\" . Chr(34)) . Chr(34)
}

QuoteExecutable(value) {
    value := String(value)
    if SubStr(value, 1, 1) = Chr(34)
        return value
    return InStr(value, " ") ? QuoteArgument(value) : value
}

ToInteger(value, defaultValue := 0) {
    return IsInteger(value) ? Integer(value) : defaultValue
}

IsSafeFileName(name) {
    return Trim(name) != "" && !RegExMatch(name, "[\\/:*?" . Chr(34) . "<>|]")
        && name != "." && name != ".."
}

RepeatText(text, count) {
    result := ""
    Loop count
        result .= text
    return result
}

CountWords(text) {
    count := 0
    Loop Parse, text, " `t`n`r" {
        if A_LoopField != ""
            count++
    }
    return count
}

HashText(text) {
    hash := 2166136261
    Loop Parse, text {
        hash := (hash ^ Ord(A_LoopField)) * 16777619
        hash := hash & 0xFFFFFFFF
    }
    return hash
}

ShowBriefToolTip(text, duration := 1800) {
    ToolTip(text)
    SetTimer((*) => ToolTip(), -duration)
}

FocusCallingWindow(*) {
    global GC_CallingWindowHwnd
    if GC_CallingWindowHwnd && WinExist("ahk_id " . GC_CallingWindowHwnd)
        WinActivate("ahk_id " . GC_CallingWindowHwnd)
}

LogGlobalCoderError(exception, mode) {
    try GlobalCoderDatabase.RecordError(exception)
    OutputDebug("GlobalCoder v7 error: " . exception.Message)
    ShowBriefToolTip("GlobalCoder recovered from an error: " . exception.Message, 5000)
    return true
}

StepCanvasIsActive(*) {
    global GC_ActiveStepCanvas
    return IsObject(GC_ActiveStepCanvas) && GC_ActiveStepCanvas.IsActive()
}

StepCanvasPrevious(*) {
    global GC_ActiveStepCanvas
    if IsObject(GC_ActiveStepCanvas)
        GC_ActiveStepCanvas.Previous()
}

StepCanvasNext(*) {
    global GC_ActiveStepCanvas
    if IsObject(GC_ActiveStepCanvas)
        GC_ActiveStepCanvas.Next()
}

StepCanvasCopy(*) {
    global GC_ActiveStepCanvas
    if IsObject(GC_ActiveStepCanvas)
        GC_ActiveStepCanvas.CopyCommand()
}

LaunchStepCanvas(steps, projectType, *) {
    StepCanvas(steps, projectType)
}

DashboardButtonClicked(guiObj, callback, *) {
    guiObj.Destroy()
    callback.Call()
}

OverlayActiveHasItems(*) {
    overlay := OverlayManager.Active()
    return IsObject(overlay) && overlay.Items.Length > 0
}

OverlayActiveHasInput(*) {
    overlay := OverlayManager.Active()
    return IsObject(overlay) && IsObject(overlay.InputControl)
}

OverlaySubmitActive(*) {
    overlay := OverlayManager.Active()
    if IsObject(overlay)
        overlay.SubmitInput()
}

OverlayRightButtonDown(wParam, lParam, msg, hwnd) {
    return OverlayManager.OnRightButtonDown(wParam, lParam, msg, hwnd)
}

OverlayRightButtonUp(wParam, lParam, msg, hwnd) {
    return OverlayManager.OnRightButtonUp(wParam, lParam, msg, hwnd)
}

OverlayContextMenu(wParam, lParam, msg, hwnd) {
    return OverlayManager.OnContextMenu(wParam, lParam, msg, hwnd)
}

OverlayDragTick(*) {
    OverlayManager.DragTick()
}

OverlayManagerHasActiveWindow(*) {
    return OverlayManager.HasActiveWindow()
}

OverlayMouseIsOver(*) {
    overlay := OverlayManager.Active()
    if !IsObject(overlay) || overlay.Closed
        return false
    OverlayManager.GetCursorScreenPosition(&mouseX, &mouseY)
    WinGetPos(&windowX, &windowY, &windowWidth, &windowHeight, "ahk_id " . overlay.GuiObj.Hwnd)
    return mouseX >= windowX && mouseX < windowX + windowWidth
        && mouseY >= windowY && mouseY < windowY + windowHeight
}

OverlayCloseActive(*) {
    OverlayManager.CloseActive()
}

OverlayTogglePinActive(*) {
    OverlayManager.TogglePinActive()
}

OverlayBeginRightDrag(*) {
    overlay := OverlayManager.Active()
    if !IsObject(overlay)
        return
    OverlayManager.GetCursorScreenPosition(&mouseX, &mouseY)
    OverlayManager.StartDrag(overlay, mouseX, mouseY)
}

OverlayMoveActive(delta, *) {
    OverlayManager.MoveActive(delta)
}

OverlaySelectActive(*) {
    OverlayManager.SelectActive()
}

OverlayCopyActive(*) {
    OverlayManager.CopyActive()
}

ResolveKnowledgeGapPrompt(gapId, nodeId, answer) {
    ActivityMonitor.ResolvePrompt(gapId, nodeId, answer)
}

RegisterGlobalHotkeys() {
    ; Custom library browser.
    HotIf(CustomMenuIsActive)
    Hotkey("Up", MenuMove.Bind(-1))
    Hotkey("Down", MenuMove.Bind(1))
    Hotkey("j", MenuMove.Bind(1))
    Hotkey("k", MenuMove.Bind(-1))
    Hotkey("Enter", MenuSelect)
    Hotkey("h", MenuSelect)
    Hotkey("Backspace", MenuGoBack)
    Hotkey("f", MenuGoBack)
    Hotkey("Escape", CloseCustomMenu)

    ; All shared overlays.
    HotIf(OverlayManagerHasActiveWindow)
    Hotkey("Escape", OverlayCloseActive)
    Hotkey("^p", OverlayTogglePinActive)

    HotIf(OverlayMouseIsOver)
    ; A scoped physical hotkey works over native Edit/ListView child controls,
    ; whose window procedures otherwise consume WM_RBUTTONDOWN.
    Hotkey("RButton", OverlayBeginRightDrag)

    ; Itemized overlays only. Input overlays retain normal editing keys.
    HotIf(OverlayActiveHasItems)
    Hotkey("Up", OverlayMoveActive.Bind(-1))
    Hotkey("Down", OverlayMoveActive.Bind(1))
    Hotkey("Enter", OverlaySelectActive)
    Hotkey("^c", OverlayCopyActive)

    HotIf(OverlayActiveHasInput)
    Hotkey("^Enter", OverlaySubmitActive)

    ; Step canvas.
    HotIf(StepCanvasIsActive)
    Hotkey("Left", StepCanvasPrevious)
    Hotkey("Right", StepCanvasNext)
    Hotkey("^c", StepCanvasCopy)

    ; Global shortcuts.
    HotIf()
    Hotkey("^RShift", ShowMainMenu)
    Hotkey("!RShift", ShowMainMenu)
    Hotkey("^Space", GoogleSearchWithLogging)
    Hotkey("^!n", ShowNewProjectWizard)
    Hotkey("^!l", ShowLearningCenter)
    Hotkey("^!r", RebuildMenu)
    Hotkey("^!m", ShowCustomMenu)
    Hotkey("^!k", ShowKnowledgeSearch)
    Hotkey("^!a", ShowInstructionLanguageConsole)
}

; ============================================================================
; CONTEXT HOTKEYS
; ============================================================================

; Hotkeys are registered during initialization by RegisterGlobalHotkeys().
