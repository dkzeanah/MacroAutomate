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
;   Ctrl + Right Shift  - Open the bounded native GlobalCoder menu, including Snips
;   Alt  + Right Shift  - Open the bounded native GlobalCoder menu, including Snips
;   Ctrl + M            - Resume the last Snips language/feature section (or open root)
;   Ctrl + Space        - Open Google search and log the query to SQLite
;   Ctrl + Alt + N      - Open the New Project wizard
;   Ctrl + Alt + L      - Open the Learning Center
;   Ctrl + Alt + R      - Rebuild the bounded native menu
;   Ctrl + Alt + M      - Resume the last Snips language/feature section (alias)
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
; Snips suggestion overlay (only in enabled IDE/editor applications):
;   Tab                 - Insert the selected snippet and place {{cursor}}
;   Up / Down           - Select a different likely snippet
;   Escape              - Dismiss suggestions and clear the typed prefix
;
; Native project-tree menu item actions (while a file/folder is highlighted):
;   V                   - Open the highlighted path in VS Code
;   N                   - Create a new file in the corresponding folder
;   O                   - Open Windows Terminal/cmd in that folder
;   E                   - Open or select the path in Explorer
;   C                   - Copy the highlighted path
;
; Tutorial StepCanvas (only while StepCanvas is active):
;   Left / Right        - Show the previous or next tutorial step
;   Ctrl + C            - Copy the current command
;
; REGISTERED HOTSTRINGS (typed triggers, not modifier-key hotkeys):
;   jjj                 - Open the arrow-navigable native GlobalCoder menu
;   ggg                 - Open Google search and log the query to SQLite
;   gcd                 - Open A_ScriptDir in the active/new Explorer window
;
; SQLite contextual bindings:
;   User-defined hotkeys and hotstrings can be limited by active executable,
;   excluded executable, window-title text, window class, or any window.

; --- Portable paths ----------------------------------------------------------
global GC_DATA_DIR := A_ScriptDir "\data"
global GC_PROJECT_DIR := GC_DATA_DIR "\projs"
global GC_SNIP_IMPORT_DIR := GC_DATA_DIR "\snips-import"
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
global GC_CallingControl := ""
global GC_ActiveStepCanvas := ""
global GC_NativeMenuActive := false
global GC_HighlightedMenuContext := ""
global GC_LastHighlightedSnippetContext := ""
global GC_MenuCommandContexts := Map()
global GC_MenuPositionContexts := Map()

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

        CREATE TABLE IF NOT EXISTS context_bindings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            binding_type TEXT NOT NULL DEFAULT 'hotstring',
            trigger TEXT NOT NULL,
            context_type TEXT NOT NULL DEFAULT 'any',
            context_value TEXT NOT NULL DEFAULT '',
            action_type TEXT NOT NULL DEFAULT 'send_text',
            action_value TEXT NOT NULL DEFAULT '',
            description TEXT NOT NULL DEFAULT '',
            enabled INTEGER NOT NULL DEFAULT 1,
            priority INTEGER NOT NULL DEFAULT 100,
            created_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
            UNIQUE(binding_type, trigger, context_type, context_value)
        /*close*/);

        CREATE TABLE IF NOT EXISTS snippet_languages (
            code TEXT PRIMARY KEY,
            label TEXT NOT NULL,
            aliases TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 100,
            enabled INTEGER NOT NULL DEFAULT 1
        /*close*/);

        CREATE TABLE IF NOT EXISTS snippet_feature_groups (
            code TEXT PRIMARY KEY,
            label TEXT NOT NULL,
            domain TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 100,
            enabled INTEGER NOT NULL DEFAULT 1
        /*close*/);

        CREATE TABLE IF NOT EXISTS snippets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            language_code TEXT NOT NULL,
            feature_code TEXT NOT NULL,
            name TEXT NOT NULL,
            trigger TEXT NOT NULL,
            body TEXT NOT NULL DEFAULT '',
            description TEXT NOT NULL DEFAULT '',
            enabled INTEGER NOT NULL DEFAULT 1,
            usage_count INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
            UNIQUE(language_code, feature_code, name),
            FOREIGN KEY(language_code) REFERENCES snippet_languages(code),
            FOREIGN KEY(feature_code) REFERENCES snippet_feature_groups(code)
        /*close*/);

        CREATE TABLE IF NOT EXISTS snippet_editor_contexts (
            executable TEXT PRIMARY KEY,
            label TEXT NOT NULL DEFAULT '',
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
        CREATE INDEX IF NOT EXISTS idx_context_bindings_lookup ON context_bindings(binding_type, trigger, enabled, priority);
        CREATE INDEX IF NOT EXISTS idx_snippets_lookup ON snippets(language_code, feature_code, enabled, usage_count DESC);
        CREATE INDEX IF NOT EXISTS idx_snippets_trigger ON snippets(trigger, enabled, usage_count DESC);
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
            ["Knowledge", "IdleThresholdMs", "900000"],
            ["Snippets", "SuggestionsEnabled", "1"],
            ["Snippets", "MinimumPrefixLength", "4"]
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

class NativeMenuLegendWindow {
    static GuiObj := ""
    static LegendText := ""

    static Init() {
        if IsObject(this.GuiObj)
            return
        this.GuiObj := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000020", "GlobalCoder Menu Keys")
        this.GuiObj.BackColor := "101010"
        this.GuiObj.MarginX := 0
        this.GuiObj.MarginY := 0
        this.LegendText := this.GuiObj.Add("Text", "x12 y9 w548 h70 Background101010 cFFFFFF")
        this.LegendText.SetFont("s9", "Segoe UI")
    }

    static Show(context := "") {
        this.Init()
        this.Update(context)
        GetActiveMonitorWorkArea(&left, &top, &right, &bottom)
        width := 572, height := 88
        x := right - width - 10
        y := bottom - height - 10
        this.GuiObj.Show("NA x" . x . " y" . y . " w" . width . " h" . height)
        try WinSetTransparent(238, "ahk_id " . this.GuiObj.Hwnd)
    }

    static Update(context := "") {
        if !IsObject(this.LegendText)
            return
        line1 := "↑↓ select   → submenu   ← back   Enter open/insert   Esc close"
        if IsObject(context) && context.Has("path") {
            line2 := "V VS Code   N new file   O terminal here   E Explorer   C copy path"
            line3 := DatabaseBrowser.Compact(context["path"], 88)
        } else if IsObject(context) && context.Has("kind") && context["kind"] = "snippet_feature" {
            languageLabel := GlobalCoderDatabase.Scalar("SELECT label FROM snippet_languages WHERE code="
                . GlobalCoderDatabase.Q(context["language_code"]) . " LIMIT 1;", context["language_code"])
            section := SnippetMenuSectionByCode(context["section_code"])
            sectionLabel := IsObject(section) ? section["label"] : context["section_code"]
            line2 := "Resume target: Snips > " . languageLabel . " > " . sectionLabel
            line3 := context["label"] . " | Enter opens this feature; syntax leaves insert at the calling cursor."
        } else {
            line2 := "File/folder actions appear when a project-tree item is highlighted."
            line3 := "Snips: Enter on a syntax leaf inserts at the calling editor cursor."
        }
        this.LegendText.Text := line1 . "`r`n" . line2 . "`r`n" . line3
    }

    static Hide() {
        if IsObject(this.GuiObj)
            try this.GuiObj.Hide()
    }

    static Close() {
        if IsObject(this.GuiObj)
            try this.GuiObj.Destroy()
        this.GuiObj := ""
        this.LegendText := ""
    }
}

class NativeMenuMonitor {
    static Initialized := false

    static Init() {
        if this.Initialized
            return
        OnMessage(0x0211, NativeMenuEnterLoop)
        OnMessage(0x0212, NativeMenuExitLoop)
        OnMessage(0x011F, NativeMenuSelect)
        NativeMenuLegendWindow.Init()
        this.Initialized := true
    }

    static ResetMappings() {
        global GC_MenuCommandContexts, GC_MenuPositionContexts
        GC_MenuCommandContexts := Map()
        GC_MenuPositionContexts := Map()
    }

    static RegisterLastItem(menuObj, context) {
        global GC_MenuCommandContexts, GC_MenuPositionContexts
        if !IsObject(menuObj) || !IsObject(context)
            return
        try menuHandle := menuObj.Handle
        catch
            return
        position := DllCall("User32.dll\GetMenuItemCount", "Ptr", menuHandle, "Int") - 1
        if position < 0
            return
        GC_MenuPositionContexts[menuHandle . ":" . position] := context
        commandId := DllCall("User32.dll\GetMenuItemID", "Ptr", menuHandle, "Int", position, "UInt")
        if commandId != 0xFFFFFFFF
            GC_MenuCommandContexts[commandId] := context
    }

    static Enter(*) {
        global GC_NativeMenuActive, GC_HighlightedMenuContext, GC_LastHighlightedSnippetContext
        GC_NativeMenuActive := true
        GC_HighlightedMenuContext := ""
        GC_LastHighlightedSnippetContext := ""
        NativeMenuLegendWindow.Show()
    }

    static Exit(*) {
        global GC_NativeMenuActive, GC_HighlightedMenuContext, GC_LastHighlightedSnippetContext
        if IsObject(GC_LastHighlightedSnippetContext) {
            try RememberSnippetMenuContext(GC_LastHighlightedSnippetContext["language_code"],
                GC_LastHighlightedSnippetContext["feature_code"])
        }
        GC_NativeMenuActive := false
        GC_HighlightedMenuContext := ""
        GC_LastHighlightedSnippetContext := ""
        NativeMenuLegendWindow.Hide()
    }

    static Select(wParam, lParam) {
        global GC_HighlightedMenuContext, GC_LastHighlightedSnippetContext, GC_MenuCommandContexts, GC_MenuPositionContexts
        itemValue := wParam & 0xFFFF
        flags := (wParam >> 16) & 0xFFFF
        context := ""
        if lParam && (flags & 0x0010) {
            positionKey := lParam . ":" . itemValue
            if GC_MenuPositionContexts.Has(positionKey)
                context := GC_MenuPositionContexts[positionKey]
        } else if GC_MenuCommandContexts.Has(itemValue) {
            context := GC_MenuCommandContexts[itemValue]
        }
        GC_HighlightedMenuContext := context
        if IsObject(context) && context.Has("kind") && context["kind"] = "snippet_feature"
            GC_LastHighlightedSnippetContext := context
        NativeMenuLegendWindow.Update(context)
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
        Hotstring(":*:jjj", ShowMainMenu)
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

class SyntaxGuideRepository {
    static Seed() {
        pythonGuide := "
        (
PYTHON, PIP, AND VIRTUAL ENVIRONMENTS

1. Verify the Windows Python launcher
   py --version
   py -0p                         List installed Python versions and paths
   py -3.12 --version             Select a particular installed version

2. Create and activate a project environment
   mkdir my-project
   cd my-project
   py -m venv .venv
   .\.venv\Scripts\Activate.ps1  PowerShell
   .venv\Scripts\activate.bat    Command Prompt
   deactivate                     Leave the environment

   If PowerShell blocks activation for the current process:
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

3. Always invoke pip through the selected interpreter
   py -m pip install --upgrade pip setuptools wheel
   python -m pip install package-name
   python -m pip list
   python -m pip show package-name
   python -m pip uninstall package-name
   python -m pip check
   python -m pip cache purge

4. Reproducible dependencies
   python -m pip freeze > requirements.txt
   python -m pip install -r requirements.txt
   python -m pip install --upgrade -r requirements.txt
   python -m pip install -e .     Editable install for the current package

5. Popular library groups
   HTTP and APIs:       python -m pip install requests httpx aiohttp
   Data:                python -m pip install numpy pandas polars scipy
   Charts:              python -m pip install matplotlib seaborn plotly
   Web APIs:            python -m pip install fastapi uvicorn flask django
   Database:            python -m pip install sqlalchemy alembic psycopg[binary] pymysql
   Files and formats:   python -m pip install openpyxl pillow pypdf python-docx
   Scraping:            python -m pip install beautifulsoup4 lxml playwright
   CLI and config:      python -m pip install typer rich python-dotenv pydantic
   Testing and quality: python -m pip install pytest pytest-cov ruff mypy black
   Notebooks:           python -m pip install jupyterlab ipykernel

6. Typical project checks
   python -m pytest -q
   python -m pytest --cov=src
   python -m ruff check .
   python -m ruff format .
   python -m mypy src

7. Troubleshooting
   where.exe python
   where.exe pip
   python -c 'import sys; print(sys.executable)'
   python -c 'import site; print(site.getsitepackages())'
   python -m pip debug --verbose

Rules of thumb: create one .venv per project; do not commit .venv; commit requirements.txt or a lock file; prefer python -m pip so installs go to the interpreter you intended.
        )"

        gitGuide := "
        (
GIT COMMANDS AND WORKFLOW

Identity and defaults
   git --version
   git config --global user.name 'Your Name'
   git config --global user.email 'you@example.com'
   git config --global init.defaultBranch main
   git config --list --show-origin

Start or obtain a repository
   git init
   git clone URL
   git clone URL folder-name

Daily loop
   git status --short --branch
   git diff                         Unstaged changes
   git diff --staged                Staged changes
   git add file
   git add -p                       Stage selected hunks
   git commit -m 'Clear message'
   git log --oneline --graph --decorate --all

Branches
   git branch
   git switch -c feature/name
   git switch main
   git merge feature/name
   git branch -d feature/name
   git rebase main                  Replay current branch on main
   git rebase --continue
   git rebase --abort

Remotes and collaboration
   git remote -v
   git remote add origin URL
   git fetch --all --prune
   git pull --rebase
   git push -u origin branch-name
   git push

Safe correction and recovery
   git restore file                 Discard unstaged file changes
   git restore --staged file        Unstage without losing work
   git commit --amend               Repair the newest local commit
   git revert COMMIT                Make a new commit that reverses one
   git reflog                       Find recently moved branch pointers

Temporary work
   git stash push -u -m 'description'
   git stash list
   git stash pop
   git stash apply stash@{0}

Tags and inspection
   git tag -a v1.0.0 -m 'Release 1.0.0'
   git push origin v1.0.0
   git show COMMIT
   git blame file
   git log -- path/to/file

Recommended feature workflow: update main; create a feature branch; make focused commits; fetch and rebase; run tests; push; review; merge. Avoid reset --hard and force-push unless you have resolved the exact target and understand who else shares the history.
        )"

        npmGuide := "
        (
NPM, TYPESCRIPT, AND REACT APPLICATION SETUP

Verify tools
   node --version
   npm --version
   npm config get prefix

Create a modern React plus TypeScript app with Vite
   npm create vite@latest my-app -- --template react-ts
   cd my-app
   npm install
   npm run dev
   npm run build
   npm run preview

Create a plain TypeScript project
   mkdir my-ts-app
   cd my-ts-app
   npm init -y
   npm install --save-dev typescript tsx @types/node
   npx tsc --init
   npx tsc --noEmit
   npx tsx src/index.ts

Package operations
   npm install package-name
   npm install --save-dev package-name
   npm uninstall package-name
   npm update
   npm outdated
   npm audit
   npm audit fix
   npm ls --depth=0
   npm explain package-name

Common React packages
   Routing:       npm install react-router-dom
   Server state:  npm install @tanstack/react-query
   Forms:         npm install react-hook-form zod @hookform/resolvers
   State:         npm install zustand
   HTTP:          npm install axios
   Dates:         npm install date-fns
   UI utilities:  npm install clsx tailwind-merge
   Testing:       npm install -D vitest @testing-library/react @testing-library/jest-dom jsdom
   Quality:       npm install -D eslint prettier typescript-eslint

Useful package.json scripts
   dev     starts the local development server
   build   runs tsc and creates the production bundle
   test    runs Vitest
   lint    runs ESLint
   typecheck runs tsc --noEmit

Locking and clean installs
   npm install                       Updates package-lock.json as needed
   npm ci                            Exact clean install from package-lock.json
   npx package-command               Run a local package executable

Troubleshooting
   npm cache verify
   npm doctor
   npm config list
   Remove node_modules and run npm ci only after confirming the project lock file is correct.

Commit package.json and package-lock.json. Do not commit node_modules, dist, local environment secrets, or generated coverage output.
        )"

        dotnetGuide := "
        (
.NET CLI COMMAND GUIDE

Inspect SDKs and templates
   dotnet --info
   dotnet --list-sdks
   dotnet new list

Create projects and a solution
   dotnet new sln -n MySolution
   dotnet new console -n MyApp
   dotnet new classlib -n MyLibrary
   dotnet new webapi -n MyApi
   dotnet new xunit -n MyApp.Tests
   dotnet sln MySolution.sln add MyApp/MyApp.csproj
   dotnet sln MySolution.sln add MyLibrary/MyLibrary.csproj
   dotnet add MyApp/MyApp.csproj reference MyLibrary/MyLibrary.csproj

Packages
   dotnet add PROJECT package PACKAGE
   dotnet add PROJECT package PACKAGE --version VERSION
   dotnet list PROJECT package
   dotnet list PROJECT package --outdated
   dotnet remove PROJECT package PACKAGE
   dotnet restore

Build, run, and test
   dotnet clean
   dotnet build
   dotnet build --configuration Release
   dotnet run --project MyApp
   dotnet watch --project MyApi
   dotnet test
   dotnet test --collect:'XPlat Code Coverage'
   dotnet format

Publish
   dotnet publish MyApp -c Release -o publish
   dotnet publish MyApp -c Release -r win-x64 --self-contained true

Entity Framework Core
   dotnet tool install --global dotnet-ef
   dotnet add PROJECT package Microsoft.EntityFrameworkCore.Design
   dotnet ef migrations add InitialCreate --project PROJECT
   dotnet ef database update --project PROJECT
   dotnet ef migrations list --project PROJECT
   dotnet ef migrations remove --project PROJECT

Useful templates: console, classlib, webapi, webapp, mvc, worker, xunit, nunit, mstest, gitignore, editorconfig. Keep SDK selection repeatable with global.json when a team or build server must use a specific SDK feature band.
        )"

        sqliteGuide := "
        (
SQLITE SYNTAX AND OPERATIONS

CLI basics
   sqlite3 app.db
   .databases
   .tables
   .schema table_name
   .headers on
   .mode column
   .mode csv
   .import file.csv table_name
   .output backup.sql
   .dump
   .quit

Schema
   CREATE TABLE users (
       id INTEGER PRIMARY KEY,
       email TEXT NOT NULL UNIQUE,
       display_name TEXT NOT NULL DEFAULT '',
       created_at TEXT NOT NULL DEFAULT (datetime('now'))
   /* end columns */ );
   ALTER TABLE users ADD COLUMN enabled INTEGER NOT NULL DEFAULT 1;
   CREATE INDEX idx_users_email ON users(email);
   DROP INDEX IF EXISTS idx_users_email;

Data changes
   INSERT INTO users(email, display_name) VALUES('a@example.com', 'Ada');
   UPDATE users SET display_name='Ada L.' WHERE id=1;
   DELETE FROM users WHERE id=1;
   INSERT INTO settings(key,value) VALUES('theme','dark')
     ON CONFLICT(key) DO UPDATE SET value=excluded.value;

Queries
   SELECT id,email FROM users WHERE enabled=1 ORDER BY created_at DESC LIMIT 50;
   SELECT project_id, COUNT(*) AS total FROM tasks GROUP BY project_id HAVING COUNT(*) > 2;
   SELECT u.email, p.name FROM users u LEFT JOIN projects p ON p.owner_id=u.id;
   WITH recent AS (SELECT * FROM events ORDER BY id DESC LIMIT 100)
   SELECT event_type, COUNT(*) FROM recent GROUP BY event_type;

Transactions
   BEGIN IMMEDIATE;
   INSERT INTO ...;
   UPDATE ...;
   COMMIT;
   ROLLBACK;

Parameters should be bound by the application instead of concatenating user input. Use foreign keys explicitly with PRAGMA foreign_keys=ON. For desktop applications, WAL mode often improves read/write concurrency:
   PRAGMA journal_mode=WAL;
   PRAGMA foreign_keys=ON;
   PRAGMA integrity_check;
   PRAGMA table_info(table_name);

Backup and maintenance
   VACUUM;
   ANALYZE;
   .backup backup.db
   .restore backup.db
        )"

        tsqlGuide := "
        (
T-SQL / SQL SERVER SYNTAX GUIDE

sqlcmd connection examples
   sqlcmd -S localhost -E
   sqlcmd -S SERVER -d DATABASE -U USER -P PASSWORD
   sqlcmd -S SERVER -d DATABASE -E -i script.sql -o result.txt

GO is a client batch separator, not a T-SQL statement.

Schema and data
   CREATE TABLE dbo.Users (
       UserId int IDENTITY(1,1) PRIMARY KEY,
       Email nvarchar(320) NOT NULL UNIQUE,
       CreatedAt datetime2 NOT NULL DEFAULT sysdatetime()
   /* end columns */ );
   ALTER TABLE dbo.Users ADD Enabled bit NOT NULL CONSTRAINT DF_Users_Enabled DEFAULT 1;
   CREATE INDEX IX_Users_Email ON dbo.Users(Email) INCLUDE(CreatedAt);
   INSERT dbo.Users(Email) OUTPUT inserted.UserId VALUES('a@example.com');
   UPDATE dbo.Users SET Enabled=0 WHERE UserId=@UserId;

Queries
   SELECT TOP (50) UserId,Email FROM dbo.Users WHERE Enabled=1 ORDER BY CreatedAt DESC;
   SELECT p.ProjectId, COUNT_BIG(*) AS TaskCount
   FROM dbo.Projects p
   JOIN dbo.Tasks t ON t.ProjectId=p.ProjectId
   GROUP BY p.ProjectId;

Variables, CTEs, and windows
   DECLARE @Since datetime2 = dateadd(day,-30,sysdatetime());
   WITH Ranked AS (
       SELECT *, row_number() OVER(PARTITION BY ProjectId ORDER BY CreatedAt DESC) AS rn
       FROM dbo.Tasks WHERE CreatedAt >= @Since
   /* end CTE */ )
   SELECT * FROM Ranked WHERE rn=1;

Transactions and error handling
   SET XACT_ABORT ON;
   BEGIN TRY
       BEGIN TRANSACTION;
       -- statements
       COMMIT TRANSACTION;
   END TRY
   BEGIN CATCH
       IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
       THROW;
   END CATCH;

Stored procedure
   CREATE OR ALTER PROCEDURE dbo.GetUser @UserId int AS
   BEGIN
       SET NOCOUNT ON;
       SELECT UserId,Email FROM dbo.Users WHERE UserId=@UserId;
   END;

Temporary data
   CREATE TABLE #Work(Id int PRIMARY KEY, Value nvarchar(100));
   DECLARE @Ids TABLE(Id int PRIMARY KEY);

Use sp_executesql with parameters for dynamic SQL. Prefer datetime2 over datetime, nvarchar for Unicode, explicit column lists, schema-qualified object names, TRY/CATCH around multi-statement writes, and least-privilege database accounts.
        )"

        this.SeedGuide("python-pip-venv", "Python, pip, venv, and Popular Libraries", "Python", pythonGuide)
        this.SeedGuide("git-command-guide", "Git Commands and Workflow", "Git", gitGuide)
        this.SeedGuide("npm-typescript-react", "npm, TypeScript, and React Setup", "JavaScript / TypeScript", npmGuide)
        this.SeedGuide("dotnet-cli", ".NET CLI Commands", ".NET", dotnetGuide)
        this.SeedGuide("sqlite-syntax", "SQLite Syntax", "SQL", sqliteGuide)
        this.SeedGuide("tsql-syntax", "T-SQL / SQL Server Syntax", "SQL", tsqlGuide)
    }

    static SeedGuide(slug, title, category, content) {
        virtualPath := "guide://" . slug
        GlobalCoderDatabase.Exec("INSERT OR IGNORE INTO content_items(path,title,content_type,content,source_mtime,metadata) VALUES("
            . GlobalCoderDatabase.Q(virtualPath) . "," . GlobalCoderDatabase.Q(title) . ",'guide',"
            . GlobalCoderDatabase.Q(Trim(content, "`r`n ")) . ",''," . GlobalCoderDatabase.Q("builtin:v1|" . category) . ");")
        GlobalCoderDatabase.Exec("INSERT INTO knowledge_nodes(title,node_type,language,feature,content,confidence,importance) "
            . "SELECT " . GlobalCoderDatabase.Q(title) . ",'guide'," . GlobalCoderDatabase.Q(category)
            . ",'syntax-guide'," . GlobalCoderDatabase.Q("Reusable command and syntax reference. Open Automation > Syntax Guides to browse it.")
            . ",1.0,1.25 WHERE NOT EXISTS(SELECT 1 FROM knowledge_nodes WHERE title=" . GlobalCoderDatabase.Q(title)
            . " AND node_type='guide');")
    }
}

class SyntaxGuideBrowser {
    GuiObj := ""
    SearchEdit := ""
    List := ""
    ContentEdit := ""
    StatusText := ""
    Rows := []
    SelectedRow := 0

    __New() {
        this.GuiObj := Gui("+AlwaysOnTop", "GlobalCoder Syntax Guides")
        this.GuiObj.BackColor := "1E1E1E"
        this.GuiObj.SetFont("s9", "Segoe UI")
        this.GuiObj.OnEvent("Close", (*) => this.Close())
        this.GuiObj.OnEvent("Escape", (*) => this.Close())
        heading := this.GuiObj.Add("Text", "x12 y12 w1076 h32 c4FC3F7 Center", "Portable Syntax and Setup Guides")
        heading.SetFont("s14 bold")
        this.SearchEdit := this.GuiObj.Add("Edit", "x12 y54 w470 Background252526 cFFFFFF")
        this.GuiObj.Add("Button", "x490 y53 w78 h28 Default", "Search").OnEvent("Click", (*) => this.Load())
        this.GuiObj.Add("Button", "x576 y53 w78 h28", "Clear").OnEvent("Click", (*) => this.ClearSearch())
        this.GuiObj.Add("Button", "x850 y53 w112 h28", "Copy Guide").OnEvent("Click", (*) => this.CopyGuide())
        this.GuiObj.Add("Button", "x970 y53 w118 h28", "All DB Records").OnEvent("Click", (*) => ShowDatabaseBrowser("content_items"))
        this.List := this.GuiObj.Add("ListView", "x12 y92 w330 h548 -Multi +Grid Background252526 cE6E6E6", ["Category", "Guide"])
        this.List.ModifyCol(1, 105), this.List.ModifyCol(2, 205)
        this.List.OnEvent("ItemFocus", (ctrl, row) => this.ShowRow(row))
        this.List.OnEvent("DoubleClick", (ctrl, row) => this.ShowRow(row))
        this.ContentEdit := this.GuiObj.Add("Edit", "x352 y92 w736 h548 ReadOnly +Multi +VScroll +HScroll Background181818 cF0F0F0")
        this.ContentEdit.SetFont("s10", "Consolas")
        this.StatusText := this.GuiObj.Add("Text", "x12 y650 w950 h30 cA8C7E6", "")
        this.GuiObj.Add("Button", "x998 y646 w90 h30", "Close").OnEvent("Click", (*) => this.Close())
        this.GuiObj.Show("w1100 h690")
        WinActivate("ahk_id " . this.GuiObj.Hwnd)
        this.Load()
    }

    Load() {
        term := Trim(this.SearchEdit.Value)
        whereSql := " WHERE content_type='guide'"
        if term != "" {
            likeValue := GlobalCoderDatabase.Q("%" . term . "%")
            whereSql .= " AND (title LIKE " . likeValue . " OR content LIKE " . likeValue . " OR metadata LIKE " . likeValue . ")"
        }
        this.Rows := GlobalCoderDatabase.Rows("SELECT path,title,metadata,content FROM content_items" . whereSql . " ORDER BY title;")
        this.List.Delete()
        for row in this.Rows
            this.List.Add(, this.Category(row["metadata"]), row["title"])
        this.StatusText.Text := this.Rows.Length . " guide(s) | Search checks titles, categories, commands, and guide text."
        this.SelectedRow := 0
        this.ContentEdit.Value := this.Rows.Length > 0 ? "Select a guide on the left." : "No guides match this search."
        if this.Rows.Length > 0 {
            this.List.Modify(1, "+Select +Focus Vis")
            this.ShowRow(1)
        }
    }

    ClearSearch() {
        this.SearchEdit.Value := ""
        this.Load()
        this.SearchEdit.Focus()
    }

    ShowRow(rowIndex) {
        if rowIndex < 1 || rowIndex > this.Rows.Length
            return
        this.SelectedRow := rowIndex
        row := this.Rows[rowIndex]
        this.ContentEdit.Value := row["title"] . "`r`n========================================`r`n`r`n" . row["content"]
    }

    CopyGuide() {
        if this.SelectedRow < 1 || this.SelectedRow > this.Rows.Length {
            GUT_Display("Syntax Guides", "Select a guide first.", 1800)
            return
        }
        row := this.Rows[this.SelectedRow]
        A_Clipboard := row["title"] . "`r`n`r`n" . row["content"]
        GUT_Display("Guide Copied", row["title"], 1800)
    }

    Category(metadata) {
        separatorAt := InStr(metadata, "|")
        return separatorAt > 0 ? SubStr(metadata, separatorAt + 1) : metadata
    }

    Close() {
        if IsObject(this.GuiObj)
            try this.GuiObj.Destroy()
        this.GuiObj := ""
    }
}

class ContextBindingManager {
    static Registered := []

    static Init() {
        this.SeedDefaults()
        return this.Reload()
    }

    static SeedDefaults() {
        rows := [
            ["hotstring", "gcd", "exe", "explorer.exe", "function", "OpenScriptDirectoryCurrentExplorer",
                "In Explorer: target the address bar and navigate to A_ScriptDir", 10],
            ["hotstring", "gcd", "not_exe", "explorer.exe", "function", "OpenScriptDirectoryNewExplorer",
                "Outside Explorer: launch Explorer, target its address bar, and navigate to A_ScriptDir", 20]
        ]
        for row in rows {
            GlobalCoderDatabase.Exec("INSERT OR IGNORE INTO context_bindings(binding_type,trigger,context_type,context_value,action_type,action_value,description,priority) VALUES("
                . GlobalCoderDatabase.Q(row[1]) . "," . GlobalCoderDatabase.Q(row[2]) . ","
                . GlobalCoderDatabase.Q(row[3]) . "," . GlobalCoderDatabase.Q(row[4]) . ","
                . GlobalCoderDatabase.Q(row[5]) . "," . GlobalCoderDatabase.Q(row[6]) . ","
                . GlobalCoderDatabase.Q(row[7]) . "," . Integer(row[8]) . ");")
        }
    }

    static Reload() {
        for registration in this.Registered {
            try {
                if IsObject(registration["predicate"])
                    HotIf(registration["predicate"])
                else
                    HotIf()
                if registration["binding_type"] = "hotstring"
                    Hotstring(registration["registered_trigger"], "Off")
                else
                    Hotkey(registration["registered_trigger"], "Off")
            }
        }
        HotIf()
        this.Registered := []

        rows := GlobalCoderDatabase.Rows("SELECT id,binding_type,trigger,context_type,context_value,action_type,action_value,description "
            . "FROM context_bindings WHERE enabled=1 ORDER BY priority,id;")
        errorCount := 0
        for row in rows {
            predicate := row["context_type"] = "any" ? "" : ContextBindingMatches.Bind(row["context_type"], row["context_value"])
            try {
                if IsObject(predicate)
                    HotIf(predicate)
                else
                    HotIf()
                callback := ExecuteContextBinding.Bind(row)
                registeredTrigger := row["binding_type"] = "hotstring" ? ":*:" . row["trigger"] : row["trigger"]
                if row["binding_type"] = "hotstring"
                    Hotstring(registeredTrigger, callback)
                else
                    Hotkey(registeredTrigger, callback)
                this.Registered.Push(Map(
                    "binding_type", row["binding_type"],
                    "registered_trigger", registeredTrigger,
                    "predicate", predicate
                ))
            } catch as error {
                errorCount += 1
                GlobalCoderDatabase.LogEvent("context_binding_error", "Binding " . row["id"] . ": " . error.Message)
            }
        }
        HotIf()
        return errorCount
    }

    static ExpandTokens(value) {
        value := StrReplace(value, "{{scriptdir}}", A_ScriptDir)
        value := StrReplace(value, "{{datadir}}", GC_DATA_DIR)
        value := StrReplace(value, "{{projectdir}}", GC_PROJECT_DIR)
        value := StrReplace(value, "{{database}}", GC_DB_PATH)
        return value
    }

    static IsKnownBuiltIn(actionName) {
        known := Map(
            "OpenScriptDirectoryCurrentExplorer", true,
            "OpenScriptDirectoryNewExplorer", true,
            "GoogleSearch", true,
            "ShowMainMenu", true,
            "ShowCustomMenu", true,
            "ShowSyntaxGuides", true,
            "ShowSnippets", true,
            "ShowContextBindings", true
        )
        return known.Has(actionName)
    }
}

class ContextBindingEditor {
    GuiObj := ""
    List := ""
    TypeDrop := ""
    TriggerEdit := ""
    ContextDrop := ""
    ContextValueEdit := ""
    ActionDrop := ""
    ActionValueEdit := ""
    DescriptionEdit := ""
    EnabledCheck := ""
    StatusText := ""
    Rows := []
    SelectedId := 0
    SourceHwnd := 0

    __New() {
        global GC_CallingWindowHwnd
        this.SourceHwnd := GC_CallingWindowHwnd && WinExist("ahk_id " . GC_CallingWindowHwnd)
            ? GC_CallingWindowHwnd : WinExist("A")
        this.GuiObj := Gui("+AlwaysOnTop", "GlobalCoder Context Hotkeys and Hotstrings")
        this.GuiObj.BackColor := "1E1E1E"
        this.GuiObj.SetFont("s9", "Segoe UI")
        this.GuiObj.OnEvent("Close", (*) => this.Close())
        this.GuiObj.OnEvent("Escape", (*) => this.Close())
        heading := this.GuiObj.Add("Text", "x12 y10 w876 h30 c4FC3F7 Center", "Window-Context Hotkeys and Hotstrings")
        heading.SetFont("s14 bold")
        this.List := this.GuiObj.Add("ListView", "x12 y48 w876 h238 -Multi +Grid Background252526 cE6E6E6",
            ["ID", "Type", "Trigger", "Window context", "Action", "On", "Description"])
        this.List.ModifyCol(1, 42), this.List.ModifyCol(2, 74), this.List.ModifyCol(3, 82)
        this.List.ModifyCol(4, 185), this.List.ModifyCol(5, 170), this.List.ModifyCol(6, 42), this.List.ModifyCol(7, 255)
        this.List.OnEvent("ItemFocus", (ctrl, row) => this.LoadSelected(row))
        this.List.OnEvent("DoubleClick", (ctrl, row) => this.LoadSelected(row))

        this.GuiObj.Add("Text", "x12 y304 w100 cE6E6E6", "Binding type")
        this.TypeDrop := this.GuiObj.Add("DropDownList", "x12 y326 w160 Choose1", ["Hotstring", "Hotkey"])
        this.GuiObj.Add("Text", "x188 y304 w210 cE6E6E6", "Trigger (gcd, ^!g, #n, etc.)")
        this.TriggerEdit := this.GuiObj.Add("Edit", "x188 y326 w220 Background252526 cFFFFFF")
        this.EnabledCheck := this.GuiObj.Add("Checkbox", "x430 y330 w130 Checked cE6E6E6", "Enabled")

        this.GuiObj.Add("Text", "x12 y370 w180 cE6E6E6", "Window context")
        this.ContextDrop := this.GuiObj.Add("DropDownList", "x12 y392 w210 Choose1",
            ["Any window", "Active executable", "Not executable", "Title contains", "Window class"])
        this.GuiObj.Add("Text", "x238 y370 w330 cE6E6E6", "Context value (example: explorer.exe)")
        this.ContextValueEdit := this.GuiObj.Add("Edit", "x238 y392 w390 Background252526 cFFFFFF")
        this.GuiObj.Add("Button", "x644 y390 w160 h28", "Use Calling Window").OnEvent("Click", (*) => this.CaptureContext())

        this.GuiObj.Add("Text", "x12 y438 w160 cE6E6E6", "Action")
        this.ActionDrop := this.GuiObj.Add("DropDownList", "x12 y460 w210 Choose1",
            ["Send text", "Send keys", "Run / open", "Built-in function"])
        this.GuiObj.Add("Text", "x238 y438 w650 cE6E6E6", "Action value")
        this.ActionValueEdit := this.GuiObj.Add("Edit", "x238 y460 w650 Background252526 cFFFFFF")

        this.GuiObj.Add("Text", "x12 y502 w876 cA8C7E6", "Tokens: {{scriptdir}}, {{datadir}}, {{projectdir}}, {{database}}. Built-ins: OpenScriptDirectoryCurrentExplorer, OpenScriptDirectoryNewExplorer, GoogleSearch, ShowMainMenu, ShowCustomMenu, ShowSyntaxGuides, ShowSnippets, ShowContextBindings")
        this.GuiObj.Add("Text", "x12 y536 w120 cE6E6E6", "Description")
        this.DescriptionEdit := this.GuiObj.Add("Edit", "x12 y558 w876 h60 +Multi Background252526 cFFFFFF")

        this.GuiObj.Add("Button", "x12 y634 w90 h32 Default", "Save").OnEvent("Click", (*) => this.Save())
        this.GuiObj.Add("Button", "x110 y634 w90 h32", "New").OnEvent("Click", (*) => this.NewBinding())
        this.GuiObj.Add("Button", "x208 y634 w110 h32", "Enable/Disable").OnEvent("Click", (*) => this.ToggleSelected())
        this.GuiObj.Add("Button", "x326 y634 w90 h32", "Delete").OnEvent("Click", (*) => this.DeleteSelected())
        this.GuiObj.Add("Button", "x424 y634 w110 h32", "Reload Rules").OnEvent("Click", (*) => this.ReloadRules())
        this.StatusText := this.GuiObj.Add("Text", "x12 y678 w760 h28 cA8C7E6", "")
        this.GuiObj.Add("Button", "x798 y674 w90 h32", "Close").OnEvent("Click", (*) => this.Close())
        this.GuiObj.Show("w900 h720")
        WinActivate("ahk_id " . this.GuiObj.Hwnd)
        this.ReloadRows()
    }

    ReloadRows() {
        this.Rows := GlobalCoderDatabase.Rows("SELECT id,binding_type,trigger,context_type,context_value,action_type,action_value,description,enabled "
            . "FROM context_bindings ORDER BY binding_type,trigger,priority,id;")
        this.List.Delete()
        for row in this.Rows {
            contextLabel := this.ContextLabel(row["context_type"]) . (row["context_value"] != "" ? ": " . row["context_value"] : "")
            actionLabel := this.ActionLabel(row["action_type"]) . ": " . DatabaseBrowser.Compact(row["action_value"], 55)
            this.List.Add(, row["id"], this.TypeLabel(row["binding_type"]), row["trigger"], contextLabel,
                actionLabel, Integer(row["enabled"]) ? "Yes" : "No", row["description"])
        }
        this.StatusText.Text := this.Rows.Length . " SQLite binding(s). Changes are registered immediately when saved."
    }

    LoadSelected(rowIndex) {
        if rowIndex < 1 || rowIndex > this.Rows.Length
            return
        row := this.Rows[rowIndex]
        this.SelectedId := Integer(row["id"])
        this.TypeDrop.Text := this.TypeLabel(row["binding_type"])
        this.TriggerEdit.Value := row["trigger"]
        this.ContextDrop.Text := this.ContextLabel(row["context_type"])
        this.ContextValueEdit.Value := row["context_value"]
        this.ActionDrop.Text := this.ActionLabel(row["action_type"])
        this.ActionValueEdit.Value := row["action_value"]
        this.DescriptionEdit.Value := row["description"]
        this.EnabledCheck.Value := Integer(row["enabled"])
    }

    NewBinding() {
        this.SelectedId := 0
        this.TypeDrop.Choose(1)
        this.TriggerEdit.Value := ""
        this.ContextDrop.Choose(1)
        this.ContextValueEdit.Value := ""
        this.ActionDrop.Choose(1)
        this.ActionValueEdit.Value := ""
        this.DescriptionEdit.Value := ""
        this.EnabledCheck.Value := 1
        this.TriggerEdit.Focus()
        this.StatusText.Text := "Creating a new contextual binding."
    }

    Save() {
        bindingType := this.TypeCode(this.TypeDrop.Text)
        trigger := Trim(this.TriggerEdit.Value)
        contextType := this.ContextCode(this.ContextDrop.Text)
        contextValue := Trim(this.ContextValueEdit.Value)
        actionType := this.ActionCode(this.ActionDrop.Text)
        actionValue := this.ActionValueEdit.Value
        description := Trim(this.DescriptionEdit.Value)
        enabled := this.EnabledCheck.Value ? 1 : 0

        if trigger = "" {
            MsgBox("Enter a hotstring or hotkey trigger.", "Context Binding", 48)
            return
        }
        if bindingType = "hotstring" && RegExMatch(trigger, "\s") {
            MsgBox("A hotstring trigger cannot contain whitespace.", "Context Binding", 48)
            return
        }
        if contextType != "any" && contextValue = "" {
            MsgBox("This context type needs an executable, title fragment, or window class.", "Context Binding", 48)
            return
        }
        if actionValue = "" {
            MsgBox("Enter an action value.", "Context Binding", 48)
            return
        }
        if actionType = "function" && !ContextBindingManager.IsKnownBuiltIn(actionValue) {
            MsgBox("That built-in function is not on the allowed list shown above the Description field.", "Context Binding", 48)
            return
        }

        try {
            if this.SelectedId > 0 {
                GlobalCoderDatabase.Exec("UPDATE context_bindings SET binding_type=" . GlobalCoderDatabase.Q(bindingType)
                    . ",trigger=" . GlobalCoderDatabase.Q(trigger) . ",context_type=" . GlobalCoderDatabase.Q(contextType)
                    . ",context_value=" . GlobalCoderDatabase.Q(contextValue) . ",action_type=" . GlobalCoderDatabase.Q(actionType)
                    . ",action_value=" . GlobalCoderDatabase.Q(actionValue) . ",description=" . GlobalCoderDatabase.Q(description)
                    . ",enabled=" . enabled . ",updated_at=datetime('now','localtime') WHERE id=" . this.SelectedId . ";")
            } else {
                GlobalCoderDatabase.Exec("INSERT INTO context_bindings(binding_type,trigger,context_type,context_value,action_type,action_value,description,enabled) VALUES("
                    . GlobalCoderDatabase.Q(bindingType) . "," . GlobalCoderDatabase.Q(trigger) . ","
                    . GlobalCoderDatabase.Q(contextType) . "," . GlobalCoderDatabase.Q(contextValue) . ","
                    . GlobalCoderDatabase.Q(actionType) . "," . GlobalCoderDatabase.Q(actionValue) . ","
                    . GlobalCoderDatabase.Q(description) . "," . enabled . ");")
                this.SelectedId := Integer(GlobalCoderDatabase.Scalar("SELECT last_insert_rowid();", "0"))
            }
            errorCount := ContextBindingManager.Reload()
            this.ReloadRows()
            this.StatusText.Text := errorCount = 0 ? "Saved and activated." : "Saved; " . errorCount . " invalid binding(s) were skipped and logged."
        } catch as error {
            MsgBox(error.Message, "Could Not Save Context Binding", 16)
        }
    }

    ToggleSelected() {
        id := this.SelectedRecordId()
        if id < 1
            return
        GlobalCoderDatabase.Exec("UPDATE context_bindings SET enabled=CASE enabled WHEN 1 THEN 0 ELSE 1 END,updated_at=datetime('now','localtime') WHERE id=" . id . ";")
        ContextBindingManager.Reload()
        this.ReloadRows()
    }

    DeleteSelected() {
        id := this.SelectedRecordId()
        if id < 1
            return
        if MsgBox("Delete contextual binding " . id . "?", "Delete Context Binding", 0x24) != "Yes"
            return
        GlobalCoderDatabase.Exec("DELETE FROM context_bindings WHERE id=" . id . ";")
        this.SelectedId := 0
        ContextBindingManager.Reload()
        this.ReloadRows()
        this.NewBinding()
    }

    ReloadRules() {
        errorCount := ContextBindingManager.Reload()
        this.ReloadRows()
        this.StatusText.Text := errorCount = 0 ? "All enabled rules reloaded." : errorCount . " invalid binding(s) were skipped and logged."
    }

    SelectedRecordId() {
        rowIndex := this.List.GetNext(0, "F")
        if rowIndex < 1
            rowIndex := this.List.GetNext()
        if rowIndex < 1 || rowIndex > this.Rows.Length {
            MsgBox("Select a binding first.", "Context Binding", 48)
            return 0
        }
        return Integer(this.Rows[rowIndex]["id"])
    }

    CaptureContext() {
        contextType := this.ContextCode(this.ContextDrop.Text)
        target := this.SourceHwnd && WinExist("ahk_id " . this.SourceHwnd) ? "ahk_id " . this.SourceHwnd : "A"
        try {
            switch contextType {
                case "exe", "not_exe":
                    this.ContextValueEdit.Value := WinGetProcessName(target)
                case "title":
                    this.ContextValueEdit.Value := WinGetTitle(target)
                case "class":
                    this.ContextValueEdit.Value := WinGetClass(target)
                default:
                    this.ContextValueEdit.Value := ""
            }
        }
    }

    TypeCode(label) {
        return label = "Hotkey" ? "hotkey" : "hotstring"
    }

    TypeLabel(code) {
        return code = "hotkey" ? "Hotkey" : "Hotstring"
    }

    ContextCode(label) {
        codes := Map("Any window", "any", "Active executable", "exe", "Not executable", "not_exe", "Title contains", "title", "Window class", "class")
        return codes.Has(label) ? codes[label] : "any"
    }

    ContextLabel(code) {
        labels := Map("any", "Any window", "exe", "Active executable", "not_exe", "Not executable", "title", "Title contains", "class", "Window class")
        return labels.Has(code) ? labels[code] : code
    }

    ActionCode(label) {
        codes := Map("Send text", "send_text", "Send keys", "send_keys", "Run / open", "run", "Built-in function", "function")
        return codes.Has(label) ? codes[label] : "send_text"
    }

    ActionLabel(code) {
        labels := Map("send_text", "Send text", "send_keys", "Send keys", "run", "Run / open", "function", "Built-in function")
        return labels.Has(code) ? labels[code] : code
    }

    Close() {
        if IsObject(this.GuiObj)
            try this.GuiObj.Destroy()
        this.GuiObj := ""
    }
}

class SnippetRepository {
    static Init() {
        this.SeedLanguages()
        this.SeedFeatureGroups()
        this.SeedEditorContexts()
        this.SeedStarterSnippets()
    }

    static SeedLanguages() {
        rows := [
            ["c", "C", "c,h", 10],
            ["cpp", "C++", "cpp,cxx,cc,hpp,hxx", 20],
            ["python", "Python", "py,pyw", 30],
            ["javascript", "JavaScript", "js,jsx,mjs,cjs", 40],
            ["typescript", "TypeScript", "ts,tsx,mts,cts", 50],
            ["csharp", "C#", "cs", 60],
            ["ahk2", "AutoHotkey v2", "ahk", 70]
        ]
        for row in rows {
            GlobalCoderDatabase.Exec("INSERT OR IGNORE INTO snippet_languages(code,label,aliases,sort_order) VALUES("
                . GlobalCoderDatabase.Q(row[1]) . "," . GlobalCoderDatabase.Q(row[2]) . ","
                . GlobalCoderDatabase.Q(row[3]) . "," . row[4] . ");")
        }
    }

    static SeedFeatureGroups() {
        rows := [
            ["program-structure", "Program Structure", "Core Syntax", "Entry points, source layout, declarations, and basic statements"],
            ["variables-constants", "Variables and Constants", "Core Syntax", "Declarations, assignment, scope, mutability, and constants"],
            ["types-casting", "Data Types and Casting", "Core Syntax", "Primitive types, inference, conversion, parsing, and type checks"],
            ["operators-expressions", "Operators and Expressions", "Core Syntax", "Arithmetic, comparison, Boolean, bitwise, null, and expression syntax"],
            ["strings-text", "Strings and Text", "Core Syntax", "Literals, interpolation, formatting, encoding, and text operations"],
            ["arrays-collections", "Arrays, Lists, and Collections", "Core Syntax", "Creation, indexing, slicing, mutation, and traversal"],
            ["maps-sets", "Maps, Dictionaries, and Sets", "Core Syntax", "Key/value and unique-value collections"],
            ["conditionals-patterns", "Conditionals and Pattern Matching", "Control and Abstraction", "If, else, switch, match, guards, and conditional expressions"],
            ["loops-iteration", "Loops and Iteration", "Control and Abstraction", "For, while, enumeration, ranges, break, and continue"],
            ["functions-parameters", "Functions and Parameters", "Control and Abstraction", "Definitions, returns, defaults, variadics, closures, and lambdas"],
            ["classes-objects", "Classes and Objects", "Control and Abstraction", "Construction, members, inheritance, encapsulation, and object syntax"],
            ["interfaces-protocols", "Interfaces, Traits, and Protocols", "Control and Abstraction", "Contracts, abstract behavior, mixins, and structural typing"],
            ["generics-templates", "Generics and Templates", "Control and Abstraction", "Reusable type-parameterized functions and types"],
            ["modules-imports", "Modules, Packages, and Imports", "Control and Abstraction", "Namespaces, imports, exports, includes, and package boundaries"],
            ["errors-exceptions", "Errors and Exceptions", "Reliability and Data", "Error values, throwing, catching, cleanup, and recovery"],
            ["files-streams", "Files, Paths, and Streams", "Reliability and Data", "Reading, writing, paths, buffering, and resource cleanup"],
            ["dates-time", "Dates, Time, and Timers", "Reliability and Data", "Timestamps, duration, formatting, scheduling, and timers"],
            ["regex-parsing", "Regular Expressions and Parsing", "Reliability and Data", "Pattern matching, tokenization, validation, and parsing"],
            ["serialization-formats", "Serialization and Data Formats", "Reliability and Data", "JSON, XML, CSV, binary formats, and object mapping"],
            ["memory-resources", "Memory and Resources", "Reliability and Data", "Allocation, ownership, disposal, pointers, handles, and lifetimes"],
            ["data-structures-algorithms", "Algorithms and Data Structures", "Reliability and Data", "Stacks, queues, trees, graphs, searching, sorting, and complexity"],
            ["async-concurrency", "Concurrency and Async", "Integration and Engineering", "Threads, tasks, promises, async/await, locks, and coordination"],
            ["networking-http", "Networking and HTTP", "Integration and Engineering", "Clients, servers, sockets, requests, responses, and APIs"],
            ["databases-sql", "Databases and SQL", "Integration and Engineering", "Connections, commands, transactions, queries, and mapping"],
            ["processes-cli", "Processes and Command Line", "Integration and Engineering", "Arguments, environment, subprocesses, shells, and exit codes"],
            ["ui-events", "UI, Events, and Callbacks", "Integration and Engineering", "Windows, controls, event handlers, messages, and interaction"],
            ["testing-assertions", "Testing and Assertions", "Integration and Engineering", "Unit, integration, fixtures, mocks, assertions, and coverage"],
            ["debugging-logging", "Debugging and Logging", "Integration and Engineering", "Breakpoints, diagnostics, structured logs, traces, and profiling"],
            ["build-dependencies", "Build, Dependencies, and Tooling", "Integration and Engineering", "Compilers, package managers, builds, linting, and formatting"],
            ["interop-native", "Interop and Native APIs", "Integration and Engineering", "FFI, COM, DLLs, platform APIs, and cross-language calls"],
            ["security-crypto", "Security and Cryptography", "Integration and Engineering", "Secrets, hashing, encryption, validation, and safe boundaries"],
            ["language-specific", "Language-Specific Features", "Integration and Engineering", "Idioms and capabilities unique to a language or runtime"]
        ]
        for index, row in rows {
            GlobalCoderDatabase.Exec("INSERT OR IGNORE INTO snippet_feature_groups(code,label,domain,description,sort_order) VALUES("
                . GlobalCoderDatabase.Q(row[1]) . "," . GlobalCoderDatabase.Q(row[2]) . ","
                . GlobalCoderDatabase.Q(row[3]) . "," . GlobalCoderDatabase.Q(row[4]) . "," . index * 10 . ");")
        }
    }

    static SeedEditorContexts() {
        rows := [
            ["Code.exe", "Visual Studio Code"],
            ["Cursor.exe", "Cursor"],
            ["Windsurf.exe", "Windsurf"],
            ["SciTE4AutoHotkey.exe", "SciTE4AutoHotkey"],
            ["SciTE.exe", "SciTE"],
            ["notepad.exe", "Windows Notepad"],
            ["notepad++.exe", "Notepad++"],
            ["sublime_text.exe", "Sublime Text"],
            ["devenv.exe", "Visual Studio"],
            ["rider64.exe", "JetBrains Rider"],
            ["pycharm64.exe", "PyCharm"],
            ["webstorm64.exe", "WebStorm"],
            ["idea64.exe", "IntelliJ IDEA"],
            ["eclipse.exe", "Eclipse"]
        ]
        for row in rows {
            GlobalCoderDatabase.Exec("INSERT OR IGNORE INTO snippet_editor_contexts(executable,label) VALUES("
                . GlobalCoderDatabase.Q(row[1]) . "," . GlobalCoderDatabase.Q(row[2]) . ");")
        }
    }

    static SeedStarterSnippets() {
        rows := [
            ["c", "modules-imports", "Include standard header", "cinc", "#include <header.h>`n{{cursor}}", "C preprocessor include"],
            ["c", "conditionals-patterns", "if / else", "cifx", "if (condition) {`n    {{cursor}}`n} else {`n`n}", "C conditional block"],
            ["c", "loops-iteration", "indexed for loop", "cfor", "for (size_t i = 0; i < count; ++i) {`n    {{cursor}}`n}", "C indexed loop"],
            ["c", "loops-iteration", "while loop", "cwhi", "while (condition) {`n    {{cursor}}`n}", "C while loop"],
            ["c", "functions-parameters", "function definition", "cfun", "return_type function_name(parameters) {`n    {{cursor}}`n}", "C function skeleton"],
            ["c", "types-casting", "struct declaration", "cstruct", "typedef struct Name {`n    {{cursor}}`n} Name;", "C typedef struct"],
            ["c", "memory-resources", "allocate and validate", "calloc", "Type *items = calloc(count, sizeof(*items));`nif (items == NULL) {`n    {{cursor}}`n}", "C allocation check"],

            ["cpp", "modules-imports", "include header", "cppinc", "#include <header>`n{{cursor}}", "C++ include"],
            ["cpp", "conditionals-patterns", "if / else", "cppif", "if (condition) {`n    {{cursor}}`n} else {`n`n}", "C++ conditional"],
            ["cpp", "loops-iteration", "range for loop", "cppfor", "for (const auto& item : items) {`n    {{cursor}}`n}", "C++ range loop"],
            ["cpp", "functions-parameters", "function definition", "cppfun", "ReturnType functionName(Parameters) {`n    {{cursor}}`n}", "C++ function skeleton"],
            ["cpp", "classes-objects", "class declaration", "cppclass", "class Name {`npublic:`n    Name() = default;`n`nprivate:`n    {{cursor}}`n};", "C++ class skeleton"],
            ["cpp", "functions-parameters", "lambda expression", "cpplambda", "[&](auto value) {`n    {{cursor}}`n}", "C++ lambda"],
            ["cpp", "errors-exceptions", "try / catch", "cpptry", "try {`n    {{cursor}}`n} catch (const std::exception& error) {`n`n}", "C++ exception block"],

            ["python", "conditionals-patterns", "if / elif / else", "pyif", "if condition:`n    {{cursor}}`nelif other_condition:`n    pass`nelse:`n    pass", "Python conditional"],
            ["python", "loops-iteration", "for loop", "pyfor", "for item in items:`n    {{cursor}}", "Python for loop"],
            ["python", "loops-iteration", "enumerated loop", "pyenum", "for index, item in enumerate(items):`n    {{cursor}}", "Python enumerate loop"],
            ["python", "functions-parameters", "function definition", "pydef", "def function_name(parameters):`n    {{cursor}}", "Python function"],
            ["python", "classes-objects", "class definition", "pyclass", "class Name:`n    def __init__(self):`n        {{cursor}}", "Python class"],
            ["python", "errors-exceptions", "try / except", "pytry", "try:`n    {{cursor}}`nexcept Exception as error:`n    raise", "Python exception handling"],
            ["python", "files-streams", "with open", "pywith", "with open(path, 'r', encoding='utf-8') as file:`n    {{cursor}}", "Python managed file open"],
            ["python", "async-concurrency", "async function", "pyasync", "async def function_name(parameters):`n    {{cursor}}", "Python async function"],

            ["javascript", "conditionals-patterns", "if / else", "jsif", "if (condition) {`n  {{cursor}}`n} else {`n`n}", "JavaScript conditional"],
            ["javascript", "loops-iteration", "for of loop", "jsfor", "for (const item of items) {`n  {{cursor}}`n}", "JavaScript for-of loop"],
            ["javascript", "functions-parameters", "function declaration", "jsfun", "function functionName(parameters) {`n  {{cursor}}`n}", "JavaScript function"],
            ["javascript", "functions-parameters", "arrow function", "jsarrow", "const functionName = (parameters) => {`n  {{cursor}}`n};", "JavaScript arrow function"],
            ["javascript", "classes-objects", "class definition", "jsclass", "class Name {`n  constructor() {`n    {{cursor}}`n  }`n}", "JavaScript class"],
            ["javascript", "errors-exceptions", "try / catch", "jstry", "try {`n  {{cursor}}`n} catch (error) {`n`n}", "JavaScript error handling"],
            ["javascript", "async-concurrency", "async function", "jsasync", "async function functionName(parameters) {`n  {{cursor}}`n}", "JavaScript async function"],
            ["javascript", "modules-imports", "ES module import", "jsimport", "import { name } from 'module';`n{{cursor}}", "JavaScript named import"],

            ["typescript", "conditionals-patterns", "if / else", "tsif", "if (condition) {`n  {{cursor}}`n} else {`n`n}", "TypeScript conditional"],
            ["typescript", "loops-iteration", "typed for of", "tsfor", "for (const item of items) {`n  {{cursor}}`n}", "TypeScript for-of loop"],
            ["typescript", "functions-parameters", "typed function", "tsfun", "function functionName(parameters: Type): ReturnType {`n  {{cursor}}`n}", "TypeScript function"],
            ["typescript", "interfaces-protocols", "interface", "tsinterface", "interface Name {`n  {{cursor}}`n}", "TypeScript interface"],
            ["typescript", "types-casting", "type alias", "tstype", "type Name = {`n  {{cursor}}`n};", "TypeScript type alias"],
            ["typescript", "classes-objects", "class", "tsclass", "class Name {`n  constructor() {`n    {{cursor}}`n  }`n}", "TypeScript class"],
            ["typescript", "generics-templates", "generic function", "tsgeneric", "function functionName<T>(value: T): T {`n  {{cursor}}`n}", "TypeScript generic function"],
            ["typescript", "async-concurrency", "async function", "tsasync", "async function functionName(): Promise<Result> {`n  {{cursor}}`n}", "TypeScript async function"],

            ["csharp", "conditionals-patterns", "if / else", "csif", "if (condition)`n{`n    {{cursor}}`n}`nelse`n{`n`n}", "C# conditional"],
            ["csharp", "loops-iteration", "foreach loop", "csfor", "foreach (var item in items)`n{`n    {{cursor}}`n}", "C# foreach loop"],
            ["csharp", "functions-parameters", "method", "csmethod", "ReturnType MethodName(Parameters)`n{`n    {{cursor}}`n}", "C# method"],
            ["csharp", "classes-objects", "class", "csclass", "public class Name`n{`n    public Name()`n    {`n        {{cursor}}`n    }`n}", "C# class"],
            ["csharp", "classes-objects", "record", "csrecord", "public sealed record Name(Type Value);`n{{cursor}}", "C# record"],
            ["csharp", "errors-exceptions", "try / catch", "cstry", "try`n{`n    {{cursor}}`n}`ncatch (Exception error)`n{`n`n}", "C# exception block"],
            ["csharp", "async-concurrency", "async method", "csasync", "public async Task<Result> MethodNameAsync()`n{`n    {{cursor}}`n}", "C# async method"],
            ["csharp", "arrays-collections", "LINQ pipeline", "cslinq", "var result = items`n    .Where(item => condition)`n    .Select(item => item)`n    .ToList();`n{{cursor}}", "C# LINQ pipeline"],

            ["ahk2", "conditionals-patterns", "if / else", "ahkif", "if condition {`n    {{cursor}}`n} else {`n`n}", "AutoHotkey v2 conditional"],
            ["ahk2", "loops-iteration", "for key and value", "ahkfor", "for key, value in collection {`n    {{cursor}}`n}", "AutoHotkey v2 for loop"],
            ["ahk2", "loops-iteration", "Loop", "ahkloop", "Loop count {`n    {{cursor}}`n}", "AutoHotkey v2 Loop"],
            ["ahk2", "functions-parameters", "function", "ahkfunc", "FunctionName(parameter := defaultValue) {`n    {{cursor}}`n}", "AutoHotkey v2 function"],
            ["ahk2", "classes-objects", "class", "ahkclass", "class Name {`n    __New() {`n        {{cursor}}`n    }`n}", "AutoHotkey v2 class"],
            ["ahk2", "errors-exceptions", "try / catch", "ahktry", "try {`n    {{cursor}}`n} catch as error {`n`n}", "AutoHotkey v2 exception block"],
            ["ahk2", "ui-events", "GUI", "ahkgui", "guiObj := Gui()`nguiObj.Add(`"Text`", , `"Hello`")`nguiObj.Show()`n{{cursor}}", "AutoHotkey v2 GUI"],
            ["ahk2", "ui-events", "dynamic hotkey", "ahkhotkey", "Hotkey(`"^!k`", (*) => {{cursor}})", "AutoHotkey v2 dynamic hotkey"]
        ]
        for row in rows {
            GlobalCoderDatabase.Exec("INSERT OR IGNORE INTO snippets(language_code,feature_code,name,trigger,body,description) VALUES("
                . GlobalCoderDatabase.Q(row[1]) . "," . GlobalCoderDatabase.Q(row[2]) . ","
                . GlobalCoderDatabase.Q(row[3]) . "," . GlobalCoderDatabase.Q(row[4]) . ","
                . GlobalCoderDatabase.Q(row[5]) . "," . GlobalCoderDatabase.Q(row[6]) . ");")
        }
    }

    static Languages() {
        return GlobalCoderDatabase.Rows("SELECT code,label,aliases FROM snippet_languages WHERE enabled=1 ORDER BY sort_order,label;")
    }

    static Features(domain := "") {
        whereSql := domain = "" ? "" : " AND domain=" . GlobalCoderDatabase.Q(domain)
        return GlobalCoderDatabase.Rows("SELECT code,label,domain,description FROM snippet_feature_groups WHERE enabled=1"
            . whereSql . " ORDER BY sort_order,label;")
    }

    static Search(languageCode := "", featureCode := "", searchText := "", limit := 500) {
        clauses := ["s.enabled=1"]
        if languageCode != ""
            clauses.Push("s.language_code=" . GlobalCoderDatabase.Q(languageCode))
        if featureCode != ""
            clauses.Push("s.feature_code=" . GlobalCoderDatabase.Q(featureCode))
        if Trim(searchText) != "" {
            likeValue := GlobalCoderDatabase.Q("%" . Trim(searchText) . "%")
            clauses.Push("(s.name LIKE " . likeValue . " OR s.trigger LIKE " . likeValue
                . " OR s.body LIKE " . likeValue . " OR s.description LIKE " . likeValue . ")")
        }
        return GlobalCoderDatabase.Rows("SELECT s.id,s.language_code,l.label AS language_label,s.feature_code,f.label AS feature_label,"
            . "s.name,s.trigger,s.body,s.description,s.enabled,s.usage_count FROM snippets s "
            . "JOIN snippet_languages l ON l.code=s.language_code JOIN snippet_feature_groups f ON f.code=s.feature_code "
            . "WHERE " . DatabaseBrowser.Join(clauses, " AND ") . " ORDER BY s.usage_count DESC,l.sort_order,f.sort_order,s.name LIMIT " . Integer(limit) . ";")
    }

    static ById(id) {
        rows := GlobalCoderDatabase.Rows("SELECT s.id,s.language_code,l.label AS language_label,s.feature_code,f.label AS feature_label,"
            . "s.name,s.trigger,s.body,s.description,s.enabled,s.usage_count FROM snippets s "
            . "JOIN snippet_languages l ON l.code=s.language_code JOIN snippet_feature_groups f ON f.code=s.feature_code "
            . "WHERE s.id=" . Integer(id) . " LIMIT 1;")
        return rows.Length > 0 ? rows[1] : ""
    }

    static RecordUse(id) {
        GlobalCoderDatabase.Exec("UPDATE snippets SET usage_count=usage_count+1,updated_at=datetime('now','localtime') WHERE id=" . Integer(id) . ";")
    }

    static ExpandBody(body) {
        expanded := StrReplace(body, "{{scriptdir}}", A_ScriptDir)
        expanded := StrReplace(expanded, "{{datadir}}", GC_DATA_DIR)
        expanded := StrReplace(expanded, "{{projectdir}}", GC_PROJECT_DIR)
        expanded := StrReplace(expanded, "{{database}}", GC_DB_PATH)
        expanded := StrReplace(expanded, "{{clipboard}}", A_Clipboard)
        expanded := StrReplace(expanded, "{{date}}", FormatTime(, "yyyy-MM-dd"))
        expanded := StrReplace(expanded, "{{time}}", FormatTime(, "HH:mm:ss"))
        return expanded
    }

    static Insert(row, erasePrefixLength := 0, targetHwnd := 0, targetControl := "") {
        if !IsObject(row)
            return false
        PassivePreviewWindow.CloseCurrent()
        if targetHwnd && WinExist("ahk_id " . targetHwnd) {
            WinActivate("ahk_id " . targetHwnd)
            try WinWaitActive("ahk_id " . targetHwnd, , 1)
            if targetControl != ""
                try ControlFocus(targetControl, "ahk_id " . targetHwnd)
            Sleep(30)
        }
        controlClass := ""
        if targetControl != "" {
            try controlClass := WinGetClass("ahk_id " . targetControl)
        }
        controlInsertion := targetHwnd && targetControl != ""
            && RegExMatch(controlClass != "" ? controlClass : String(targetControl), "i)^(Edit|RichEdit|Scintilla)")
        if erasePrefixLength > 0 {
            if controlInsertion
                ControlSend("{Backspace " . erasePrefixLength . "}", targetControl, "ahk_id " . targetHwnd)
            else
                Send("{Backspace " . erasePrefixLength . "}")
        }
        body := this.ExpandBody(row["body"])
        marker := "{{cursor}}"
        markerAt := InStr(body, marker)
        body := StrReplace(body, marker, "")
        if controlInsertion
            ControlSendText(body, targetControl, "ahk_id " . targetHwnd)
        else
            SendText(body)
        if markerAt > 0 {
            trailingCount := StrLen(body) - (markerAt - 1)
            if trailingCount > 0 {
                if controlInsertion
                    ControlSend("{Left " . trailingCount . "}", targetControl, "ahk_id " . targetHwnd)
                else
                    Send("{Left " . trailingCount . "}")
            }
        }
        this.RecordUse(row["id"])
        return true
    }

    static SaveGhost(languageCode, featureCode, body) {
        body := Trim(body, "`r`n")
        if body = ""
            return 0
        firstLine := Trim(StrSplit(StrReplace(body, "`r", ""), "`n")[1])
        baseName := firstLine != "" ? DatabaseBrowser.Compact(firstLine, 72) : "Captured syntax"
        name := baseName
        suffix := 2
        while Integer(GlobalCoderDatabase.Scalar("SELECT COUNT(*) FROM snippets WHERE language_code="
            . GlobalCoderDatabase.Q(languageCode) . " AND feature_code=" . GlobalCoderDatabase.Q(featureCode)
            . " AND name=" . GlobalCoderDatabase.Q(name) . ";", "0")) > 0 {
            name := baseName . " (" . suffix . ")"
            suffix += 1
        }
        prefixes := Map("c", "c", "cpp", "cpp", "python", "py", "javascript", "js",
            "typescript", "ts", "csharp", "cs", "ahk2", "ahk")
        languagePrefix := prefixes.Has(languageCode) ? prefixes[languageCode] : SubStr(languageCode, 1, 3)
        featureStem := RegExReplace(featureCode, "[^A-Za-z0-9]", "")
        baseTrigger := languagePrefix . SubStr(featureStem, 1, 4)
        existingCount := Integer(GlobalCoderDatabase.Scalar("SELECT COUNT(*) FROM snippets WHERE language_code="
            . GlobalCoderDatabase.Q(languageCode) . " AND feature_code=" . GlobalCoderDatabase.Q(featureCode) . ";", "0"))
        trigger := baseTrigger . (existingCount + 1)
        GlobalCoderDatabase.Exec("INSERT INTO snippets(language_code,feature_code,name,trigger,body,description) VALUES("
            . GlobalCoderDatabase.Q(languageCode) . "," . GlobalCoderDatabase.Q(featureCode) . ","
            . GlobalCoderDatabase.Q(name) . "," . GlobalCoderDatabase.Q(trigger) . ","
            . GlobalCoderDatabase.Q(body) . "," . GlobalCoderDatabase.Q("Captured from the native placeholder menu") . ");")
        return Integer(GlobalCoderDatabase.Scalar("SELECT last_insert_rowid();", "0"))
    }
}

class SnippetBatchImporter {
    static FormatHeader := "GLOBALCODER_SNIPS_V1"

    static Parse(sourceText) {
        entries := []
        errors := []
        normalized := StrReplace(String(sourceText), "`r`n", "`n")
        normalized := StrReplace(normalized, "`r", "`n")
        lines := StrSplit(normalized, "`n")
        headerFound := false
        inBlock := false
        inBody := false
        current := ""
        bodyLines := []

        for lineNumber, rawLine in lines {
            line := RTrim(rawLine, "`r")
            if lineNumber = 1
                line := LTrim(line, Chr(0xFEFF))
            trimmed := Trim(line)

            if !headerFound {
                if trimmed = "" || SubStr(trimmed, 1, 1) = "#"
                    continue
                if trimmed = this.FormatHeader {
                    headerFound := true
                    continue
                }
                errors.Push("Line " . lineNumber . ": expected " . this.FormatHeader . ".")
                break
            }

            if !inBlock {
                if trimmed = "" || SubStr(trimmed, 1, 1) = "#"
                    continue
                if trimmed = "@@SNIP" {
                    current := Map("source_line", lineNumber)
                    bodyLines := []
                    inBlock := true
                    inBody := false
                    continue
                }
                errors.Push("Line " . lineNumber . ": expected @@SNIP or a comment.")
                continue
            }

            if !inBody {
                if trimmed = "@@BODY" {
                    inBody := true
                    continue
                }
                if trimmed = "@@END" {
                    errors.Push("Line " . lineNumber . ": @@BODY is missing before @@END.")
                    inBlock := false
                    current := ""
                    continue
                }
                if trimmed = "" || SubStr(trimmed, 1, 1) = "#"
                    continue
                separatorAt := InStr(line, ":")
                if separatorAt < 2 {
                    errors.Push("Line " . lineNumber . ": metadata must use key: value syntax.")
                    continue
                }
                key := StrLower(Trim(SubStr(line, 1, separatorAt - 1)))
                value := Trim(SubStr(line, separatorAt + 1))
                if !this.MetadataKeys().Has(key) {
                    errors.Push("Line " . lineNumber . ": unknown metadata key '" . key . "'.")
                    continue
                }
                if current.Has(key)
                    errors.Push("Line " . lineNumber . ": duplicate metadata key '" . key . "'.")
                else
                    current[key] := value
                continue
            }

            if trimmed = "@@END" {
                current["body"] := this.Join(bodyLines, "`n")
                entries.Push(current)
                current := ""
                bodyLines := []
                inBlock := false
                inBody := false
            } else {
                bodyLines.Push(line)
            }
        }

        if !headerFound && errors.Length = 0
            errors.Push("The batch is empty or is missing " . this.FormatHeader . ".")
        if inBlock
            errors.Push("Block starting on line " . current["source_line"] . " is missing @@END.")
        this.Validate(entries, errors)
        return Map("ok", errors.Length = 0, "entries", entries, "errors", errors)
    }

    static Validate(entries, errors) {
        languageCodes := Map()
        for row in SnippetRepository.Languages()
            languageCodes[row["code"]] := true
        featureCodes := Map()
        for row in SnippetRepository.Features()
            featureCodes[row["code"]] := true
        identities := Map()
        triggers := Map()

        for index, entry in entries {
            lineNumber := entry.Has("source_line") ? entry["source_line"] : "?"
            prefix := "Block " . index . " (line " . lineNumber . ")"
            for requiredKey in ["language", "feature", "name", "trigger", "body"] {
                if !entry.Has(requiredKey) || Trim(entry[requiredKey]) = ""
                    errors.Push(prefix . ": required field '" . requiredKey . "' is empty.")
            }
            if !entry.Has("language") || !entry.Has("feature") || !entry.Has("name") || !entry.Has("trigger")
                continue

            languageCode := StrLower(Trim(entry["language"]))
            featureCode := StrLower(Trim(entry["feature"]))
            name := Trim(entry["name"])
            trigger := Trim(entry["trigger"])
            entry["language"] := languageCode
            entry["feature"] := featureCode
            entry["name"] := name
            entry["trigger"] := trigger
            entry["description"] := entry.Has("description") ? Trim(entry["description"]) : ""
            entry["enabled"] := entry.Has("enabled") ? Trim(entry["enabled"]) : "1"

            if !languageCodes.Has(languageCode)
                errors.Push(prefix . ": unknown language code '" . languageCode . "'.")
            if !featureCodes.Has(featureCode)
                errors.Push(prefix . ": unknown feature code '" . featureCode . "'.")
            if StrLen(trigger) < 4
                errors.Push(prefix . ": trigger must contain at least four characters.")
            if RegExMatch(trigger, "\s")
                errors.Push(prefix . ": trigger cannot contain whitespace.")
            if entry["enabled"] != "0" && entry["enabled"] != "1"
                errors.Push(prefix . ": enabled must be 0 or 1.")

            identity := languageCode . Chr(31) . featureCode . Chr(31) . StrLower(name)
            if identities.Has(identity)
                errors.Push(prefix . ": duplicate language/feature/name also appears in block " . identities[identity] . ".")
            else
                identities[identity] := index

            triggerIdentity := languageCode . Chr(31) . StrLower(trigger)
            if triggers.Has(triggerIdentity) && triggers[triggerIdentity] != identity
                errors.Push(prefix . ": trigger '" . trigger . "' is reused by another entry in this batch.")
            else
                triggers[triggerIdentity] := identity
        }
        if entries.Length = 0 && errors.Length = 0
            errors.Push("The batch contains no @@SNIP blocks.")
    }

    static Import(sourceText, refreshRuntime := true) {
        parsed := this.Parse(sourceText)
        if !parsed["ok"]
            return Map("ok", false, "inserted", 0, "updated", 0, "errors", parsed["errors"])

        inserted := 0
        updated := 0
        transactionOpen := false
        try {
            GlobalCoderDatabase.Exec("BEGIN IMMEDIATE;")
            transactionOpen := true
            for entry in parsed["entries"] {
                identityWhere := "language_code=" . GlobalCoderDatabase.Q(entry["language"])
                    . " AND feature_code=" . GlobalCoderDatabase.Q(entry["feature"])
                    . " AND name=" . GlobalCoderDatabase.Q(entry["name"])
                existed := Integer(GlobalCoderDatabase.Scalar("SELECT COUNT(*) FROM snippets WHERE " . identityWhere . ";", "0")) > 0
                GlobalCoderDatabase.Exec("INSERT INTO snippets(language_code,feature_code,name,trigger,body,description,enabled,updated_at) VALUES("
                    . GlobalCoderDatabase.Q(entry["language"]) . "," . GlobalCoderDatabase.Q(entry["feature"]) . ","
                    . GlobalCoderDatabase.Q(entry["name"]) . "," . GlobalCoderDatabase.Q(entry["trigger"]) . ","
                    . GlobalCoderDatabase.Q(entry["body"]) . "," . GlobalCoderDatabase.Q(entry["description"]) . ","
                    . Integer(entry["enabled"]) . ",datetime('now','localtime')) "
                    . "ON CONFLICT(language_code,feature_code,name) DO UPDATE SET "
                    . "trigger=excluded.trigger,body=excluded.body,description=excluded.description,enabled=excluded.enabled,updated_at=excluded.updated_at;")
                if existed
                    updated += 1
                else
                    inserted += 1
            }
            GlobalCoderDatabase.Exec("COMMIT;")
            transactionOpen := false
        } catch as error {
            if transactionOpen
                try GlobalCoderDatabase.Exec("ROLLBACK;")
            return Map("ok", false, "inserted", 0, "updated", 0,
                "errors", ["SQLite import failed; no snippets were changed. " . error.Message])
        }

        GlobalCoderDatabase.LogEvent("snippet_batch_import", "Inserted " . inserted . ", updated " . updated . ", total " . parsed["entries"].Length)
        if refreshRuntime {
            try SnippetSuggestionManager.RefreshSnippets()
            try RebuildMenu(true)
        }
        return Map("ok", true, "inserted", inserted, "updated", updated, "errors", [])
    }

    static MetadataKeys() {
        return Map("language", true, "feature", true, "name", true, "trigger", true,
            "description", true, "enabled", true)
    }

    static Join(values, separator := "`n") {
        result := ""
        for index, value in values
            result .= (index > 1 ? separator : "") . value
        return result
    }
}

class SnippetBatchImportWindow {
    GuiObj := ""
    BatchEdit := ""
    StatusText := ""
    BuiltInLanguage := ""

    __New(initialFile := "") {
        this.GuiObj := Gui(, "GlobalCoder - Batch Import Snips")
        this.GuiObj.BackColor := "1E1E1E"
        this.GuiObj.SetFont("s10", "Segoe UI")
        this.GuiObj.OnEvent("Close", (*) => this.Close())
        this.GuiObj.OnEvent("Escape", (*) => this.Close())
        this.GuiObj.OnEvent("DropFiles", (guiObj, ctrl, files, x, y) => this.LoadDroppedFiles(files))

        title := this.GuiObj.Add("Text", "x16 y14 w850 h28 cFFFFFF", "SQLite Snip Batch Import")
        title.SetFont("s14 bold")
        this.GuiObj.Add("Text", "x16 y45 w850 h42 cB9C7DB",
            "Paste an AI-generated GLOBALCODER_SNIPS_V1 batch or load a .snips file. The complete batch is validated before one atomic SQLite upsert.")
        this.BatchEdit := this.GuiObj.Add("Edit", "x16 y92 w868 h480 +Multi +WantTab +HScroll -Wrap Background101010 cF0F0F0")
        this.BatchEdit.SetFont("s10", "Consolas")
        this.GuiObj.Add("Button", "x16 y586 w120 h30", "Paste Clipboard").OnEvent("Click", (*) => this.PasteClipboard())
        this.GuiObj.Add("Button", "x146 y586 w105 h30", "Load File...").OnEvent("Click", (*) => this.SelectFile())
        this.GuiObj.Add("Button", "x261 y586 w136 h30", "Open Import Folder").OnEvent("Click", (*) => this.OpenImportFolder())
        this.BuiltInLanguage := this.GuiObj.Add("DropDownList", "x407 y588 w112 Choose1", ["All languages", "AutoHotkey v2", "C", "C++", "Python", "JavaScript", "TypeScript", "C#"])
        this.GuiObj.Add("Button", "x527 y586 w90 h30", "Load Built-in").OnEvent("Click", (*) => this.LoadBuiltInBatch())
        importButton := this.GuiObj.Add("Button", "x617 y586 w130 h30 Default", "Validate + Import")
        importButton.OnEvent("Click", (*) => this.Import())
        this.GuiObj.Add("Button", "x757 y586 w127 h30", "Close").OnEvent("Click", (*) => this.Close())
        this.StatusText := this.GuiObj.Add("Text", "x16 y627 w868 h46 c9CDCFE",
            "Format: @@SNIP metadata, @@BODY multiline code, @@END. Existing language + feature + name records are updated; new records are inserted.")

        if initialFile != "" && FileExist(initialFile)
            this.LoadFile(initialFile)
        this.GuiObj.Show("w900 h690")
        this.BatchEdit.Focus()
    }

    PasteClipboard() {
        this.BatchEdit.Value := A_Clipboard
        this.StatusText.Text := "Clipboard pasted. Choose Validate + Import when ready."
        this.BatchEdit.Focus()
    }

    SelectFile() {
        selected := FileSelect(1, GC_SNIP_IMPORT_DIR, "Load a GlobalCoder Snip batch", "Snip batches (*.snips; *.txt)")
        if selected != ""
            this.LoadFile(selected)
    }

    LoadDroppedFiles(files) {
        if files.Length > 0
            this.LoadFile(files[1])
    }

    LoadFile(filePath) {
        try {
            this.BatchEdit.Value := FileRead(filePath, "UTF-8")
            this.StatusText.Text := "Loaded: " . filePath
            this.BatchEdit.Focus()
        } catch as error {
            this.StatusText.Text := "Could not load file: " . error.Message
        }
    }

    LoadBuiltInBatch() {
        fileNames := Map(
            "AutoHotkey v2", "autohotkey-v2-batch.snips",
            "C", "c-batch.snips",
            "C++", "cpp-batch.snips",
            "Python", "python-batch.snips",
            "JavaScript", "javascript-batch.snips",
            "TypeScript", "typescript-batch.snips",
            "C#", "csharp-batch.snips")
        selectedLanguage := this.BuiltInLanguage.Text
        if selectedLanguage = "All languages" {
            combined := SnippetBatchImporter.FormatHeader
            for languageLabel, fileName in fileNames {
                filePath := GC_SNIP_IMPORT_DIR . "\" . fileName
                if !FileExist(filePath) {
                    this.StatusText.Text := "Missing built-in batch: " . filePath
                    return
                }
                batchText := FileRead(filePath, "UTF-8")
                batchText := RegExReplace(batchText, "^\x{FEFF}?GLOBALCODER_SNIPS_V1\R?", "")
                combined .= "`r`n`r`n" . LTrim(batchText, "`r`n")
            }
            this.BatchEdit.Value := combined
            this.StatusText.Text := "Loaded all seven built-in language batches into one atomic import."
            this.BatchEdit.Focus()
            return
        }
        if !fileNames.Has(selectedLanguage) {
            this.StatusText.Text := "Choose a built-in language batch first."
            return
        }
        this.LoadFile(GC_SNIP_IMPORT_DIR . "\" . fileNames[selectedLanguage])
    }

    OpenImportFolder() {
        if !DirExist(GC_SNIP_IMPORT_DIR)
            DirCreate(GC_SNIP_IMPORT_DIR)
        Run("explorer.exe " . QuoteArgument(GC_SNIP_IMPORT_DIR))
    }

    Import() {
        result := SnippetBatchImporter.Import(this.BatchEdit.Value)
        if !result["ok"] {
            message := "Import cancelled; SQLite was not changed.`r`n`r`n" . SnippetBatchImporter.Join(result["errors"], "`r`n")
            this.StatusText.Text := "Validation failed: " . result["errors"].Length . " issue(s). No database changes."
            MsgBox(message, "Snip Batch Validation", 48)
            return
        }
        message := "Batch import complete.`r`n`r`nInserted: " . result["inserted"] . "`r`nUpdated: " . result["updated"]
            . "`r`n`r`nThe Snips menus and four-character suggestions are refreshed."
        this.StatusText.Text := "Imported: " . result["inserted"] . " inserted, " . result["updated"] . " updated."
        MsgBox(message, "GlobalCoder Snips", 64)
    }

    Close() {
        if IsObject(this.GuiObj)
            try this.GuiObj.Destroy()
        this.GuiObj := ""
    }
}

class SnippetBrowser {
    GuiObj := ""
    FilterLanguage := ""
    FilterFeature := ""
    SearchEdit := ""
    List := ""
    NameEdit := ""
    TriggerEdit := ""
    EditLanguage := ""
    EditFeature := ""
    BodyEdit := ""
    DescriptionEdit := ""
    EnabledCheck := ""
    StatusText := ""
    LanguageRows := []
    FeatureRows := []
    Rows := []
    SelectedId := 0
    TargetHwnd := 0
    TargetControl := ""

    __New(initialLanguage := "", initialFeature := "") {
        global GC_CallingWindowHwnd, GC_CallingControl
        this.TargetHwnd := GC_CallingWindowHwnd && WinExist("ahk_id " . GC_CallingWindowHwnd)
            ? GC_CallingWindowHwnd : WinExist("A")
        this.TargetControl := GC_CallingControl
        this.LanguageRows := SnippetRepository.Languages()
        this.FeatureRows := SnippetRepository.Features()

        this.GuiObj := Gui("+AlwaysOnTop", "GlobalCoder Snips - IDE-Agnostic Code Helper")
        this.GuiObj.BackColor := "1E1E1E"
        this.GuiObj.SetFont("s9", "Segoe UI")
        this.GuiObj.OnEvent("Close", (*) => this.Close())
        this.GuiObj.OnEvent("Escape", (*) => this.Close())
        heading := this.GuiObj.Add("Text", "x12 y10 w1176 h30 c4FC3F7 Center", "Snips: Learn, Add, Find, and Insert")
        heading.SetFont("s14 bold")

        languageLabels := ["All languages"]
        selectedLanguageIndex := 1
        for row in this.LanguageRows {
            languageLabels.Push(row["label"])
            if row["code"] = initialLanguage
                selectedLanguageIndex := languageLabels.Length
        }
        featureLabels := ["All feature groups"]
        selectedFeatureIndex := 1
        for row in this.FeatureRows {
            featureLabels.Push(row["domain"] . " > " . row["label"])
            if row["code"] = initialFeature
                selectedFeatureIndex := featureLabels.Length
        }
        this.FilterLanguage := this.GuiObj.Add("DropDownList", "x12 y50 w180 Choose" . selectedLanguageIndex, languageLabels)
        this.FilterFeature := this.GuiObj.Add("DropDownList", "x202 y50 w300 Choose" . selectedFeatureIndex, featureLabels)
        this.SearchEdit := this.GuiObj.Add("Edit", "x512 y50 w310 Background252526 cFFFFFF")
        this.GuiObj.Add("Button", "x832 y49 w72 h28 Default", "Search").OnEvent("Click", (*) => this.LoadRows())
        this.GuiObj.Add("Button", "x912 y49 w66 h28", "Clear").OnEvent("Click", (*) => this.ClearFilters())
        this.GuiObj.Add("Button", "x986 y49 w96 h28", "Structure").OnEvent("Click", (*) => ShowSnippetStructure())
        this.GuiObj.Add("Button", "x1090 y49 w98 h28", "IDE Apps").OnEvent("Click", (*) => ShowSnippetEditorContexts())
        this.FilterLanguage.OnEvent("Change", (*) => this.LoadRows())
        this.FilterFeature.OnEvent("Change", (*) => this.LoadRows())

        this.List := this.GuiObj.Add("ListView", "x12 y88 w460 h538 -Multi +Grid Background252526 cE6E6E6",
            ["Language", "Feature", "Trigger", "Snippet", "Uses"])
        this.List.ModifyCol(1, 92), this.List.ModifyCol(2, 122), this.List.ModifyCol(3, 76)
        this.List.ModifyCol(4, 130), this.List.ModifyCol(5, 40)
        this.List.OnEvent("ItemFocus", (ctrl, row) => this.LoadSelected(row))
        this.List.OnEvent("DoubleClick", (ctrl, row) => this.InsertSelected(row))

        this.GuiObj.Add("Text", "x486 y90 w315 cE6E6E6", "Snippet name")
        this.GuiObj.Add("Text", "x808 y90 w180 cE6E6E6", "Suggestion trigger (4+ characters)")
        this.NameEdit := this.GuiObj.Add("Edit", "x486 y112 w310 Background252526 cFFFFFF")
        this.TriggerEdit := this.GuiObj.Add("Edit", "x808 y112 w180 Background252526 cFFFFFF")
        this.EnabledCheck := this.GuiObj.Add("Checkbox", "x1004 y116 w100 Checked cE6E6E6", "Enabled")

        editLanguageLabels := []
        for row in this.LanguageRows
            editLanguageLabels.Push(row["label"])
        editFeatureLabels := []
        for row in this.FeatureRows
            editFeatureLabels.Push(row["domain"] . " > " . row["label"])
        this.GuiObj.Add("Text", "x486 y154 w180 cE6E6E6", "Language")
        this.GuiObj.Add("Text", "x728 y154 w360 cE6E6E6", "Uniform feature group")
        this.EditLanguage := this.GuiObj.Add("DropDownList", "x486 y176 w230 Choose1", editLanguageLabels)
        this.EditFeature := this.GuiObj.Add("DropDownList", "x728 y176 w460 Choose1", editFeatureLabels)

        this.GuiObj.Add("Text", "x486 y218 w500 cE6E6E6", "Insertable body")
        this.BodyEdit := this.GuiObj.Add("Edit", "x486 y240 w702 h254 +Multi +VScroll +HScroll Background181818 cF0F0F0")
        this.BodyEdit.SetFont("s10", "Consolas")
        this.GuiObj.Add("Text", "x486 y502 w702 cA8C7E6",
            "Tokens: {{cursor}}, {{clipboard}}, {{date}}, {{time}}, {{scriptdir}}, {{datadir}}, {{projectdir}}, {{database}}")
        this.GuiObj.Add("Text", "x486 y530 w180 cE6E6E6", "Description / learning note")
        this.DescriptionEdit := this.GuiObj.Add("Edit", "x486 y552 w702 h74 +Multi Background252526 cFFFFFF")

        this.GuiObj.Add("Button", "x12 y640 w90 h32", "New").OnEvent("Click", (*) => this.NewSnippet())
        this.GuiObj.Add("Button", "x110 y640 w90 h32", "Save").OnEvent("Click", (*) => this.Save())
        this.GuiObj.Add("Button", "x208 y640 w90 h32", "Delete").OnEvent("Click", (*) => this.DeleteSelected())
        this.GuiObj.Add("Button", "x306 y640 w90 h32", "Copy").OnEvent("Click", (*) => this.CopySelected())
        this.GuiObj.Add("Button", "x486 y640 w170 h34", "Insert into Calling Editor").OnEvent("Click", (*) => this.InsertSelected())
        this.GuiObj.Add("Button", "x666 y640 w110 h34", "Reload Snips").OnEvent("Click", (*) => this.ReloadSnips())
        this.StatusText := this.GuiObj.Add("Text", "x12 y686 w1050 h34 cA8C7E6", "")
        this.GuiObj.Add("Button", "x1098 y682 w90 h32", "Close").OnEvent("Click", (*) => this.Close())
        this.GuiObj.Show("w1200 h732")
        WinActivate("ahk_id " . this.GuiObj.Hwnd)
        this.LoadRows()
        if initialLanguage != "" || initialFeature != ""
            this.NewSnippet(false)
    }

    LoadRows() {
        languageCode := this.FilterLanguage.Value > 1 ? this.LanguageRows[this.FilterLanguage.Value - 1]["code"] : ""
        featureCode := this.FilterFeature.Value > 1 ? this.FeatureRows[this.FilterFeature.Value - 1]["code"] : ""
        this.Rows := SnippetRepository.Search(languageCode, featureCode, this.SearchEdit.Value)
        this.List.Delete()
        for row in this.Rows
            this.List.Add(, row["language_label"], row["feature_label"], row["trigger"], row["name"], row["usage_count"])
        this.StatusText.Text := this.Rows.Length . " snippet(s). Double-click inserts into the calling editor; Save changes SQLite immediately."
        if this.Rows.Length > 0 {
            this.List.Modify(1, "+Select +Focus Vis")
            this.LoadSelected(1)
        }
    }

    LoadSelected(rowIndex) {
        if rowIndex < 1 || rowIndex > this.Rows.Length
            return
        row := this.Rows[rowIndex]
        this.SelectedId := Integer(row["id"])
        this.NameEdit.Value := row["name"]
        this.TriggerEdit.Value := row["trigger"]
        this.EditLanguage.Text := row["language_label"]
        this.EditFeature.Text := row["feature_label"] = "" ? this.EditFeature.Text : this.FeatureDisplay(row["feature_code"])
        this.BodyEdit.Value := row["body"]
        this.DescriptionEdit.Value := row["description"]
        this.EnabledCheck.Value := Integer(row["enabled"])
    }

    NewSnippet(focusName := true) {
        this.SelectedId := 0
        this.NameEdit.Value := ""
        this.TriggerEdit.Value := ""
        this.BodyEdit.Value := "{{cursor}}"
        this.DescriptionEdit.Value := ""
        this.EnabledCheck.Value := 1
        if this.FilterLanguage.Value > 1
            this.EditLanguage.Text := this.LanguageRows[this.FilterLanguage.Value - 1]["label"]
        else
            this.EditLanguage.Choose(1)
        if this.FilterFeature.Value > 1
            this.EditFeature.Text := this.FeatureDisplay(this.FeatureRows[this.FilterFeature.Value - 1]["code"])
        else
            this.EditFeature.Choose(1)
        if focusName
            this.NameEdit.Focus()
        this.StatusText.Text := "New placeholder ready. Choose the same feature group in any language for a uniform reference structure."
    }

    Save() {
        name := Trim(this.NameEdit.Value)
        trigger := Trim(this.TriggerEdit.Value)
        languageCode := this.LanguageCodeFromLabel(this.EditLanguage.Text)
        featureCode := this.FeatureCodeFromDisplay(this.EditFeature.Text)
        if name = "" || trigger = "" || Trim(this.BodyEdit.Value) = "" {
            MsgBox("Name, trigger, and body are required.", "Snips", 48)
            return
        }
        if StrLen(trigger) < 4 || RegExMatch(trigger, "\s") {
            MsgBox("Use a trigger of at least four non-whitespace characters so suggestions are intentional.", "Snips", 48)
            return
        }
        try {
            if this.SelectedId > 0 {
                GlobalCoderDatabase.Exec("UPDATE snippets SET language_code=" . GlobalCoderDatabase.Q(languageCode)
                    . ",feature_code=" . GlobalCoderDatabase.Q(featureCode) . ",name=" . GlobalCoderDatabase.Q(name)
                    . ",trigger=" . GlobalCoderDatabase.Q(trigger) . ",body=" . GlobalCoderDatabase.Q(this.BodyEdit.Value)
                    . ",description=" . GlobalCoderDatabase.Q(this.DescriptionEdit.Value) . ",enabled=" . (this.EnabledCheck.Value ? 1 : 0)
                    . ",updated_at=datetime('now','localtime') WHERE id=" . this.SelectedId . ";")
            } else {
                GlobalCoderDatabase.Exec("INSERT INTO snippets(language_code,feature_code,name,trigger,body,description,enabled) VALUES("
                    . GlobalCoderDatabase.Q(languageCode) . "," . GlobalCoderDatabase.Q(featureCode) . ","
                    . GlobalCoderDatabase.Q(name) . "," . GlobalCoderDatabase.Q(trigger) . ","
                    . GlobalCoderDatabase.Q(this.BodyEdit.Value) . "," . GlobalCoderDatabase.Q(this.DescriptionEdit.Value)
                    . "," . (this.EnabledCheck.Value ? 1 : 0) . ");")
                this.SelectedId := Integer(GlobalCoderDatabase.Scalar("SELECT last_insert_rowid();", "0"))
            }
            SnippetSuggestionManager.RefreshSnippets()
            RebuildMenu(true)
            this.LoadRows()
            this.StatusText.Text := "Snippet saved to SQLite and menus/suggestions refreshed."
        } catch as error {
            MsgBox(error.Message, "Could Not Save Snippet", 16)
        }
    }

    DeleteSelected() {
        if this.SelectedId < 1 {
            MsgBox("Select a saved snippet first.", "Snips", 48)
            return
        }
        if MsgBox("Delete this snippet from SQLite?", "Delete Snippet", 0x24) != "Yes"
            return
        GlobalCoderDatabase.Exec("DELETE FROM snippets WHERE id=" . this.SelectedId . ";")
        this.SelectedId := 0
        SnippetSuggestionManager.RefreshSnippets()
        RebuildMenu(true)
        this.LoadRows()
        this.NewSnippet(false)
    }

    InsertSelected(rowIndex := 0) {
        if rowIndex > 0 && rowIndex <= this.Rows.Length
            row := this.Rows[rowIndex]
        else
            row := SnippetRepository.ById(this.SelectedId)
        if !IsObject(row) {
            MsgBox("Select a saved snippet first.", "Snips", 48)
            return
        }
        this.Close()
        Sleep(80)
        SnippetRepository.Insert(row, 0, this.TargetHwnd, this.TargetControl)
    }

    CopySelected() {
        row := SnippetRepository.ById(this.SelectedId)
        if !IsObject(row) {
            MsgBox("Select a saved snippet first.", "Snips", 48)
            return
        }
        A_Clipboard := SnippetRepository.ExpandBody(StrReplace(row["body"], "{{cursor}}", ""))
        this.StatusText.Text := "Snippet copied."
    }

    ReloadSnips() {
        SnippetSuggestionManager.RefreshSnippets()
        RebuildMenu(true)
        this.LoadRows()
        this.StatusText.Text := "Snips, suggestions, and the native menu were rebuilt."
    }

    ClearFilters() {
        this.FilterLanguage.Choose(1)
        this.FilterFeature.Choose(1)
        this.SearchEdit.Value := ""
        this.LoadRows()
    }

    LanguageCodeFromLabel(label) {
        for row in this.LanguageRows {
            if row["label"] = label
                return row["code"]
        }
        return this.LanguageRows[1]["code"]
    }

    FeatureCodeFromDisplay(display) {
        for row in this.FeatureRows {
            if this.FeatureDisplay(row["code"]) = display
                return row["code"]
        }
        return this.FeatureRows[1]["code"]
    }

    FeatureDisplay(code) {
        for row in this.FeatureRows {
            if row["code"] = code
                return row["domain"] . " > " . row["label"]
        }
        return ""
    }

    Close() {
        if IsObject(this.GuiObj)
            try this.GuiObj.Destroy()
        this.GuiObj := ""
    }
}

class SnippetStructureBrowser {
    GuiObj := ""
    List := ""
    Rows := []

    __New() {
        this.GuiObj := Gui("+AlwaysOnTop", "GlobalCoder Snip Feature Structure")
        this.GuiObj.BackColor := "1E1E1E"
        this.GuiObj.SetFont("s9", "Segoe UI")
        this.GuiObj.OnEvent("Close", (*) => this.Close())
        this.GuiObj.OnEvent("Escape", (*) => this.Close())
        this.GuiObj.Add("Text", "x12 y12 w876 h44 cA8C7E6",
            "Every language receives the same feature structure. Zero-count rows are intentional placeholders—double-click one to add its first syntax snippet.")
        this.List := this.GuiObj.Add("ListView", "x12 y62 w876 h570 -Multi +Grid Background252526 cE6E6E6",
            ["Language", "Domain", "Feature group", "Snips", "Purpose"])
        this.List.ModifyCol(1, 110), this.List.ModifyCol(2, 155), this.List.ModifyCol(3, 205), this.List.ModifyCol(4, 48), this.List.ModifyCol(5, 335)
        this.Rows := GlobalCoderDatabase.Rows("SELECT l.code AS language_code,l.label AS language_label,f.code AS feature_code,f.domain,f.label AS feature_label,f.description,COUNT(s.id) AS snippet_count "
            . "FROM snippet_languages l CROSS JOIN snippet_feature_groups f LEFT JOIN snippets s ON s.language_code=l.code AND s.feature_code=f.code "
            . "WHERE l.enabled=1 AND f.enabled=1 GROUP BY l.code,f.code ORDER BY l.sort_order,f.sort_order;")
        for row in this.Rows
            this.List.Add(, row["language_label"], row["domain"], row["feature_label"], row["snippet_count"], row["description"])
        this.List.OnEvent("DoubleClick", (ctrl, row) => this.OpenGroup(row))
        this.GuiObj.Add("Text", "x12 y642 w730 h26 c777777", "Double-click: browse/add that language and feature group | Esc: close")
        this.GuiObj.Add("Button", "x798 y638 w90 h30", "Close").OnEvent("Click", (*) => this.Close())
        this.GuiObj.Show("w900 h682")
        WinActivate("ahk_id " . this.GuiObj.Hwnd)
    }

    OpenGroup(rowIndex) {
        if rowIndex < 1 || rowIndex > this.Rows.Length
            return
        row := this.Rows[rowIndex]
        this.Close()
        ShowSnippets(row["language_code"], row["feature_code"])
    }

    Close() {
        if IsObject(this.GuiObj)
            try this.GuiObj.Destroy()
        this.GuiObj := ""
    }
}

class SnippetEditorContextEditor {
    GuiObj := ""
    List := ""
    ExecutableEdit := ""
    LabelEdit := ""
    EnabledCheck := ""
    Rows := []
    CallingHwnd := 0

    __New() {
        global GC_CallingWindowHwnd
        this.CallingHwnd := GC_CallingWindowHwnd && WinExist("ahk_id " . GC_CallingWindowHwnd)
            ? GC_CallingWindowHwnd : WinExist("A")
        this.GuiObj := Gui("+AlwaysOnTop", "Snip Suggestion IDE Applications")
        this.GuiObj.BackColor := "1E1E1E"
        this.GuiObj.OnEvent("Close", (*) => this.Close())
        this.GuiObj.OnEvent("Escape", (*) => this.Close())
        this.GuiObj.Add("Text", "x12 y12 w616 h42 cA8C7E6",
            "Transparent four-character suggestions run only while an enabled executable below is active.")
        this.List := this.GuiObj.Add("ListView", "x12 y62 w616 h310 -Multi +Grid Background252526 cE6E6E6", ["Executable", "Editor / IDE", "Enabled"])
        this.List.ModifyCol(1, 190), this.List.ModifyCol(2, 330), this.List.ModifyCol(3, 78)
        this.List.OnEvent("ItemFocus", (ctrl, row) => this.LoadSelected(row))
        this.GuiObj.Add("Text", "x12 y390 w210 cE6E6E6", "Executable (example: Code.exe)")
        this.GuiObj.Add("Text", "x254 y390 w250 cE6E6E6", "Display label")
        this.ExecutableEdit := this.GuiObj.Add("Edit", "x12 y412 w230 Background252526 cFFFFFF")
        this.LabelEdit := this.GuiObj.Add("Edit", "x254 y412 w260 Background252526 cFFFFFF")
        this.EnabledCheck := this.GuiObj.Add("Checkbox", "x526 y416 w100 Checked cE6E6E6", "Enabled")
        this.GuiObj.Add("Button", "x12 y458 w90 h30 Default", "Save").OnEvent("Click", (*) => this.Save())
        this.GuiObj.Add("Button", "x110 y458 w118 h30", "Capture Caller").OnEvent("Click", (*) => this.CaptureCaller())
        this.GuiObj.Add("Button", "x236 y458 w90 h30", "Delete").OnEvent("Click", (*) => this.DeleteSelected())
        this.GuiObj.Add("Button", "x538 y458 w90 h30", "Close").OnEvent("Click", (*) => this.Close())
        this.GuiObj.Show("w640 h506")
        WinActivate("ahk_id " . this.GuiObj.Hwnd)
        this.ReloadRows()
    }

    ReloadRows() {
        this.Rows := GlobalCoderDatabase.Rows("SELECT executable,label,enabled FROM snippet_editor_contexts ORDER BY label,executable;")
        this.List.Delete()
        for row in this.Rows
            this.List.Add(, row["executable"], row["label"], Integer(row["enabled"]) ? "Yes" : "No")
    }

    LoadSelected(rowIndex) {
        if rowIndex < 1 || rowIndex > this.Rows.Length
            return
        row := this.Rows[rowIndex]
        this.ExecutableEdit.Value := row["executable"]
        this.LabelEdit.Value := row["label"]
        this.EnabledCheck.Value := Integer(row["enabled"])
    }

    CaptureCaller() {
        target := this.CallingHwnd && WinExist("ahk_id " . this.CallingHwnd) ? "ahk_id " . this.CallingHwnd : "A"
        try {
            this.ExecutableEdit.Value := WinGetProcessName(target)
            this.LabelEdit.Value := WinGetTitle(target)
        }
    }

    Save() {
        executable := Trim(this.ExecutableEdit.Value)
        if executable = "" {
            MsgBox("Enter an executable name.", "Snip IDE Context", 48)
            return
        }
        GlobalCoderDatabase.Exec("INSERT INTO snippet_editor_contexts(executable,label,enabled) VALUES("
            . GlobalCoderDatabase.Q(executable) . "," . GlobalCoderDatabase.Q(Trim(this.LabelEdit.Value)) . ","
            . (this.EnabledCheck.Value ? 1 : 0) . ") ON CONFLICT(executable) DO UPDATE SET label=excluded.label,enabled=excluded.enabled;")
        SnippetSuggestionManager.ReloadEditorContexts()
        this.ReloadRows()
    }

    DeleteSelected() {
        executable := Trim(this.ExecutableEdit.Value)
        if executable = ""
            return
        if MsgBox("Remove " . executable . " from suggestion-enabled applications?", "Snip IDE Context", 0x24) != "Yes"
            return
        GlobalCoderDatabase.Exec("DELETE FROM snippet_editor_contexts WHERE executable=" . GlobalCoderDatabase.Q(executable) . ";")
        this.ExecutableEdit.Value := "", this.LabelEdit.Value := ""
        SnippetSuggestionManager.ReloadEditorContexts()
        this.ReloadRows()
    }

    Close() {
        if IsObject(this.GuiObj)
            try this.GuiObj.Destroy()
        this.GuiObj := ""
    }
}

class GhostSnippetCaptureWindow {
    static Current := ""
    GuiObj := ""
    BodyEdit := ""
    StatusText := ""
    LanguageCode := ""
    FeatureCode := ""
    TargetHwnd := 0
    LastChangeTick := 0
    Changed := false
    Finished := false
    TickTimer := ""

    static Show(languageCode, featureCode) {
        if IsObject(this.Current)
            this.Current.Finish(false)
        this.Current := GhostSnippetCaptureWindow(languageCode, featureCode)
        return this.Current
    }

    __New(languageCode, featureCode) {
        global GC_CallingWindowHwnd
        this.LanguageCode := languageCode
        this.FeatureCode := featureCode
        this.TargetHwnd := GC_CallingWindowHwnd
        languageLabel := GlobalCoderDatabase.Scalar("SELECT label FROM snippet_languages WHERE code="
            . GlobalCoderDatabase.Q(languageCode) . " LIMIT 1;", languageCode)
        featureLabel := GlobalCoderDatabase.Scalar("SELECT label FROM snippet_feature_groups WHERE code="
            . GlobalCoderDatabase.Q(featureCode) . " LIMIT 1;", featureCode)

        this.GuiObj := Gui("+AlwaysOnTop +ToolWindow -MaximizeBox -MinimizeBox", "Ghost Snip Capture")
        this.GuiObj.BackColor := "10243A"
        this.GuiObj.SetFont("s9", "Segoe UI")
        this.GuiObj.OnEvent("Close", (*) => this.Finish(true))
        this.GuiObj.OnEvent("Escape", (*) => this.Finish(false))
        this.GuiObj.Add("Text", "x12 y10 w616 h38 cFFFFFF",
            languageLabel . " > " . SnippetFeatureMenuLabel(featureCode, featureLabel)
            . "`nType the syntax body below. It becomes this placeholder's first Snip.")
        this.BodyEdit := this.GuiObj.Add("Edit", "x12 y56 w616 h150 +Multi +VScroll Background081726 cFFFFFF")
        this.BodyEdit.SetFont("s10", "Consolas")
        this.BodyEdit.OnEvent("Change", (*) => this.OnChange())
        this.StatusText := this.GuiObj.Add("Text", "x12 y216 w616 h36 cA8C7E6",
            "Auto-save in 5.0 seconds after the last character | Esc cancels")
        this.GuiObj.Show("w640 h264")
        try WinSetTransparent(245, "ahk_id " . this.GuiObj.Hwnd)
        WinActivate("ahk_id " . this.GuiObj.Hwnd)
        this.BodyEdit.Focus()
        this.LastChangeTick := A_TickCount
        this.TickTimer := ObjBindMethod(this, "Tick")
        SetTimer(this.TickTimer, 100)
    }

    OnChange() {
        this.Changed := true
        this.LastChangeTick := A_TickCount
    }

    Tick(*) {
        if this.Finished
            return
        remaining := Max(0, 5000 - (A_TickCount - this.LastChangeTick))
        this.StatusText.Text := "Auto-save in " . Format("{:.1f}", remaining / 1000)
            . " seconds after the last character | Esc cancels"
        if remaining <= 0
            this.Finish(true)
    }

    Finish(saveText := true, *) {
        if this.Finished
            return
        this.Finished := true
        if IsObject(this.TickTimer)
            SetTimer(this.TickTimer, 0)
        body := IsObject(this.BodyEdit) ? this.BodyEdit.Value : ""
        if IsObject(this.GuiObj)
            try this.GuiObj.Destroy()
        this.GuiObj := ""

        savedId := 0
        if saveText && this.Changed && Trim(body) != "" {
            savedId := SnippetRepository.SaveGhost(this.LanguageCode, this.FeatureCode, body)
            SnippetSuggestionManager.RefreshSnippets()
            RebuildMenu(true)
        }
        if this.TargetHwnd && WinExist("ahk_id " . this.TargetHwnd)
            WinActivate("ahk_id " . this.TargetHwnd)
        if savedId > 0 {
            row := SnippetRepository.ById(savedId)
            PassivePreviewWindow.Show("Ghost Snip Saved",
                row["name"] . "  [" . row["trigger"] . "]`r`n`r`nSaved into the selected SQLite placeholder.", 2600)
        }
        if GhostSnippetCaptureWindow.Current = this
            GhostSnippetCaptureWindow.Current := ""
    }
}

class PassivePreviewWindow {
    static Current := ""
    GuiObj := ""
    ContentText := ""
    CloseTimer := ""

    static Show(title, content, timeout := 9000) {
        this.CloseCurrent()
        this.Current := PassivePreviewWindow(title, content, timeout)
        return this.Current
    }

    static CloseCurrent(*) {
        if IsObject(this.Current)
            this.Current.Close()
        this.Current := ""
    }

    __New(title, content, timeout) {
        this.GuiObj := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000020", title)
        this.GuiObj.BackColor := "10243A"
        this.GuiObj.MarginX := 0
        this.GuiObj.MarginY := 0
        displayText := title . "`r`n" . "========================================" . "`r`n`r`n" . content
        this.ContentText := this.GuiObj.Add("Text", "x14 y12 w872 h536 Background10243A cEAF5FF", displayText)
        this.ContentText.SetFont("s9", "Consolas")
        GetActiveMonitorWorkArea(&left, &top, &right, &bottom)
        width := Min(900, right - left - 24)
        height := Min(560, bottom - top - 24)
        x := left + ((right - left - width) // 2)
        y := top + ((bottom - top - height) // 2)
        this.ContentText.Move(, , width - 28, height - 24)
        this.GuiObj.Show("NA x" . x . " y" . y . " w" . width . " h" . height)
        try WinSetTransparent(230, "ahk_id " . this.GuiObj.Hwnd)
        this.CloseTimer := ObjBindMethod(this, "Close")
        SetTimer(this.CloseTimer, -Max(1500, Integer(timeout)))
    }

    Close(*) {
        if IsObject(this.CloseTimer)
            SetTimer(this.CloseTimer, 0)
        if IsObject(this.GuiObj)
            try this.GuiObj.Destroy()
        this.GuiObj := ""
        if PassivePreviewWindow.Current = this
            PassivePreviewWindow.Current := ""
    }
}

class SnippetSuggestionWindow {
    GuiObj := ""
    ContentText := ""

    __New() {
        this.GuiObj := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000020", "GlobalCoder Snip Suggestions")
        this.GuiObj.BackColor := "10243A"
        this.GuiObj.MarginX := 0
        this.GuiObj.MarginY := 0
        this.ContentText := this.GuiObj.Add("Text", "x0 y0 w620 h180 +0x200 Background10243A cEAF5FF")
        this.ContentText.SetFont("s9", "Consolas")
    }

    Show(items, selectedIndex, typedPrefix) {
        lines := "  Snips: '" . typedPrefix . "'    Tab insert | Up/Down select | Esc dismiss`n"
        for index, row in items {
            marker := index = selectedIndex ? "> " : "  "
            lines .= marker . row["trigger"] . "  -  " . row["name"] . "  [" . row["language_label"] . " / " . row["feature_label"] . "]`n"
        }
        this.ContentText.Text := RTrim(lines, "`r`n")
        height := 32 + items.Length * 22
        this.ContentText.Move(, , 620, height)
        this.GetSuggestionPosition(620, height, &x, &y)
        this.GuiObj.Show("NA x" . x . " y" . y . " w620 h" . height)
        try WinSetTransparent(228, "ahk_id " . this.GuiObj.Hwnd)
    }

    GetSuggestionPosition(width, height, &x, &y) {
        caretX := 0, caretY := 0
        try CaretGetPos(&caretX, &caretY)
        GetActiveMonitorWorkArea(&left, &top, &right, &bottom)
        if !IsNumber(caretX) || !IsNumber(caretY) || (caretX = 0 && caretY = 0) {
            try MouseGetPos(&caretX, &caretY)
        }
        if !IsNumber(caretX) || !IsNumber(caretY)
            caretX := left + 40, caretY := top + 80
        x := Max(left + 8, Min(caretX, right - width - 8))
        y := caretY + 28
        if y + height > bottom - 8
            y := Max(top + 8, caretY - height - 12)
    }

    Hide() {
        if IsObject(this.GuiObj)
            try this.GuiObj.Hide()
    }

    Close() {
        if IsObject(this.GuiObj)
            try this.GuiObj.Destroy()
        this.GuiObj := ""
    }
}

class SnippetSuggestionManager {
    static Hook := ""
    static Window := ""
    static Running := false
    static Visible := false
    static Buffer := ""
    static Suggestions := []
    static SelectedIndex := 1
    static EditorExecutables := Map()
    static ExtensionLanguages := Map()
    static MinimumPrefixLength := 4
    static LastEditorHwnd := 0

    static Init() {
        this.MinimumPrefixLength := Max(4, ToInteger(GlobalCoderDatabase.GetSetting("Snippets", "MinimumPrefixLength", "4"), 4))
        this.ReloadEditorContexts()
        this.RefreshSnippets()
        if GlobalCoderDatabase.GetSetting("Snippets", "SuggestionsEnabled", "1") = "1"
            this.Start()
    }

    static ReloadEditorContexts() {
        this.EditorExecutables := Map()
        rows := GlobalCoderDatabase.Rows("SELECT executable FROM snippet_editor_contexts WHERE enabled=1;")
        for row in rows
            this.EditorExecutables[StrLower(row["executable"])] := true

        this.ExtensionLanguages := Map()
        languageRows := GlobalCoderDatabase.Rows("SELECT code,aliases FROM snippet_languages WHERE enabled=1;")
        for row in languageRows {
            for extension in StrSplit(row["aliases"], ",")
                this.ExtensionLanguages[StrLower(Trim(extension))] := row["code"]
        }
    }

    static RefreshSnippets() {
        ; Suggestions query SQLite on demand so newly saved records and usage
        ; ranking are immediately visible without maintaining a second datastore.
        if this.Visible
            this.UpdateSuggestions()
    }

    static Start() {
        if this.Running
            return
        try {
            this.Hook := InputHook("V I1")
            this.Hook.OnChar := SnippetInputChar
            this.Hook.OnKeyDown := SnippetInputKeyDown
            this.Hook.KeyOpt("{Backspace}{Tab}{Enter}{Space}{Left}{Right}{Up}{Down}{Home}{End}{Delete}{PgUp}{PgDn}", "N")
            this.Hook.Start()
            SetTimer(SnippetSuggestionContextTick, 250)
            this.Running := true
        } catch as error {
            this.Running := false
            GlobalCoderDatabase.LogEvent("snippet_input_hook_error", error.Message)
        }
    }

    static Stop() {
        if IsObject(this.Hook)
            try this.Hook.Stop()
        SetTimer(SnippetSuggestionContextTick, 0)
        this.Hook := ""
        this.Running := false
        this.Reset()
        if IsObject(this.Window)
            this.Window.Close()
        this.Window := ""
    }

    static Toggle(*) {
        enabled := GlobalCoderDatabase.GetSetting("Snippets", "SuggestionsEnabled", "1") = "1"
        GlobalCoderDatabase.SetSetting("Snippets", "SuggestionsEnabled", enabled ? "0" : "1")
        if enabled
            this.Stop()
        else
            this.Start()
        RebuildMenu(true)
        PassivePreviewWindow.Show("Snip Suggestions",
            enabled ? "Four-character suggestions disabled." : "Four-character suggestions enabled.", 2200)
    }

    static OnChar(characters) {
        if !this.IsEditorActive() {
            this.Reset()
            return
        }
        activeHwnd := WinExist("A")
        if this.LastEditorHwnd != activeHwnd
            this.Buffer := ""
        this.LastEditorHwnd := activeHwnd
        for character in StrSplit(characters) {
            if RegExMatch(character, "^[A-Za-z0-9_+#]$")
                this.Buffer .= StrLower(character)
            else {
                this.Reset()
                return
            }
        }
        if StrLen(this.Buffer) > 64
            this.Buffer := SubStr(this.Buffer, -63)
        if StrLen(this.Buffer) >= this.MinimumPrefixLength
            this.UpdateSuggestions()
        else
            this.Hide()
    }

    static OnKeyDown(vk, sc) {
        if vk = 0x08 {
            if StrLen(this.Buffer) > 0
                this.Buffer := SubStr(this.Buffer, 1, -1)
            if StrLen(this.Buffer) >= this.MinimumPrefixLength
                this.UpdateSuggestions()
            else
                this.Hide()
            return
        }
        if this.Visible && (vk = 0x09 || vk = 0x26 || vk = 0x28)
            return
        if vk = 0x0D || vk = 0x09 || vk = 0x20 || vk = 0x25 || vk = 0x27
            || vk = 0x24 || vk = 0x23 || vk = 0x2E || vk = 0x21 || vk = 0x22
            this.Reset()
    }

    static UpdateSuggestions() {
        if !this.IsEditorActive() || StrLen(this.Buffer) < this.MinimumPrefixLength {
            this.Hide()
            return
        }
        prefixLike := GlobalCoderDatabase.Q(this.Buffer . "%")
        detectedLanguage := this.DetectActiveLanguage()
        languageOrder := detectedLanguage = "" ? "1" : "CASE WHEN s.language_code="
            . GlobalCoderDatabase.Q(detectedLanguage) . " THEN 0 ELSE 1 END"
        this.Suggestions := GlobalCoderDatabase.Rows("SELECT s.id,s.language_code,l.label AS language_label,s.feature_code,"
            . "f.label AS feature_label,s.name,s.trigger,s.body,s.description,s.enabled,s.usage_count FROM snippets s "
            . "JOIN snippet_languages l ON l.code=s.language_code JOIN snippet_feature_groups f ON f.code=s.feature_code "
            . "WHERE s.enabled=1 AND (lower(s.trigger) LIKE " . prefixLike . " OR lower(s.name) LIKE " . prefixLike . ") "
            . "ORDER BY " . languageOrder . ",CASE WHEN lower(s.trigger)=" . GlobalCoderDatabase.Q(this.Buffer)
            . " THEN 0 ELSE 1 END,s.usage_count DESC,s.name LIMIT 8;")
        if this.Suggestions.Length = 0 {
            this.Hide()
            return
        }
        this.SelectedIndex := Min(Max(1, this.SelectedIndex), this.Suggestions.Length)
        if !IsObject(this.Window)
            this.Window := SnippetSuggestionWindow()
        this.Window.Show(this.Suggestions, this.SelectedIndex, this.Buffer)
        this.Visible := true
    }

    static Move(delta) {
        if !this.Visible || this.Suggestions.Length = 0
            return
        this.SelectedIndex += delta
        if this.SelectedIndex < 1
            this.SelectedIndex := this.Suggestions.Length
        else if this.SelectedIndex > this.Suggestions.Length
            this.SelectedIndex := 1
        this.Window.Show(this.Suggestions, this.SelectedIndex, this.Buffer)
    }

    static Accept() {
        if !this.Visible || this.SelectedIndex < 1 || this.SelectedIndex > this.Suggestions.Length
            return
        row := this.Suggestions[this.SelectedIndex]
        prefixLength := StrLen(this.Buffer)
        this.Buffer := ""
        this.Hide()
        KeyWait("Tab")
        SnippetRepository.Insert(row, prefixLength)
    }

    static Dismiss() {
        this.Reset()
    }

    static Hide() {
        if IsObject(this.Window)
            this.Window.Hide()
        this.Visible := false
        this.Suggestions := []
        this.SelectedIndex := 1
    }

    static Reset() {
        this.Buffer := ""
        this.Hide()
    }

    static ContextTick() {
        if this.Visible && (!this.IsEditorActive() || WinExist("A") != this.LastEditorHwnd)
            this.Reset()
    }

    static IsEditorActive() {
        try return this.EditorExecutables.Has(StrLower(WinGetProcessName("A")))
        catch
            return false
    }

    static DetectActiveLanguage() {
        try title := WinGetTitle("A")
        catch
            return ""
        bestExtension := ""
        for extension, languageCode in this.ExtensionLanguages {
            if RegExMatch(title, "i)\." . RegExReplace(extension, "([\\.\+\*\?\[\]\(\)\{\}\^\$\|])", "\\$1") . "(?:\s|[-|]|—|$)") {
                if StrLen(extension) > StrLen(bestExtension)
                    bestExtension := extension
            }
        }
        return bestExtension != "" ? this.ExtensionLanguages[bestExtension] : ""
    }
}

class DatabaseBrowser {
    GuiObj := ""
    SourceDrop := ""
    SearchEdit := ""
    List := ""
    StatusText := ""
    Page := 1
    PageSize := 100
    CurrentKey := "queries"
    CurrentRows := []
    CurrentColumns := []
    TotalRows := 0

    static Sources() {
        ; Table names, column names, sort expressions, and searchable columns are
        ; deliberately whitelisted here. User text is only ever used as a quoted value.
        return Map(
            "queries", Map("label", "Google / Query History", "table", "queries",
                "columns", ["id", "created_at", "query", "provider", "context"],
                "search", ["query", "provider", "context", "created_at"], "order", "id DESC"),
            "recent_projects", Map("label", "Recent Projects", "table", "recent_projects",
                "columns", ["name", "path", "project_type", "open_count", "last_opened"],
                "search", ["name", "path", "project_type"], "order", "last_opened DESC"),
            "settings", Map("label", "Settings", "table", "settings",
                "columns", ["section", "key", "value", "updated_at"],
                "search", ["section", "key", "value"], "order", "section, key"),
            "event_log", Map("label", "Event Log", "table", "event_log",
                "columns", ["id", "created_at", "event_type", "detail"],
                "search", ["event_type", "detail", "created_at"], "order", "id DESC"),
            "errors", Map("label", "Error Log", "table", "errors",
                "columns", ["id", "created_at", "message", "file", "line", "stack"],
                "search", ["message", "file", "stack", "created_at"], "order", "id DESC"),
            "activity_log", Map("label", "Activity / Idle Log", "table", "activity_log",
                "columns", ["id", "created_at", "event_type", "active_window", "idle_ms", "detail"],
                "search", ["event_type", "active_window", "detail", "created_at"], "order", "id DESC"),
            "knowledge_nodes", Map("label", "Knowledge Nodes", "table", "knowledge_nodes",
                "columns", ["id", "title", "node_type", "language", "feature", "confidence", "importance", "use_count", "updated_at", "content"],
                "search", ["title", "node_type", "language", "feature", "content"], "order", "importance DESC, use_count DESC, updated_at DESC"),
            "knowledge_edges", Map("label", "Knowledge Relationships", "table", "knowledge_edges",
                "columns", ["id", "from_node_id", "to_node_id", "relation", "strength", "created_at"],
                "search", ["relation", "created_at"], "order", "id DESC"),
            "knowledge_gaps", Map("label", "Knowledge Gaps", "table", "knowledge_gaps",
                "columns", ["id", "node_id", "status", "due_at", "created_at", "resolved_at", "prompt"],
                "search", ["status", "prompt", "due_at", "created_at"], "order", "status, due_at DESC"),
            "knowledge_reviews", Map("label", "Knowledge Reviews", "table", "knowledge_reviews",
                "columns", ["id", "node_id", "rating", "reviewed_at", "next_review_at", "response"],
                "search", ["response", "reviewed_at", "next_review_at"], "order", "id DESC"),
            "actions", Map("label", "Action Definitions", "table", "actions",
                "columns", ["name", "function_name", "enabled", "description", "created_at"],
                "search", ["name", "function_name", "description"], "order", "name"),
            "hotstrings", Map("label", "Hotstrings", "table", "hotstrings",
                "columns", ["trigger", "category", "enabled", "replacement", "created_at"],
                "search", ["trigger", "category", "replacement"], "order", "trigger"),
            "context_bindings", Map("label", "Context Hotkeys / Hotstrings", "table", "context_bindings",
                "columns", ["id", "binding_type", "trigger", "context_type", "context_value", "action_type", "action_value", "enabled", "priority", "updated_at", "description"],
                "search", ["binding_type", "trigger", "context_type", "context_value", "action_type", "action_value", "description"], "order", "binding_type, trigger, priority, id"),
            "snippet_languages", Map("label", "Snippet Languages", "table", "snippet_languages",
                "columns", ["code", "label", "aliases", "sort_order", "enabled"],
                "search", ["code", "label", "aliases"], "order", "sort_order, label"),
            "snippet_feature_groups", Map("label", "Snippet Feature Groups", "table", "snippet_feature_groups",
                "columns", ["code", "label", "domain", "sort_order", "enabled", "description"],
                "search", ["code", "label", "domain", "description"], "order", "sort_order, label"),
            "snippets", Map("label", "Code Snippets", "table", "snippets",
                "columns", ["id", "language_code", "feature_code", "name", "trigger", "enabled", "usage_count", "updated_at", "description", "body"],
                "search", ["language_code", "feature_code", "name", "trigger", "description", "body"], "order", "usage_count DESC, language_code, feature_code, name"),
            "snippet_editor_contexts", Map("label", "Snippet IDE Applications", "table", "snippet_editor_contexts",
                "columns", ["executable", "label", "enabled", "created_at"],
                "search", ["executable", "label"], "order", "label, executable"),
            "content_items", Map("label", "Indexed Content", "table", "content_items",
                "columns", ["title", "path", "content_type", "source_mtime", "updated_at", "content"],
                "search", ["title", "path", "content_type", "content"], "order", "updated_at DESC"),
            "tutorial_steps", Map("label", "Tutorial Steps", "table", "tutorial_steps",
                "columns", ["id", "language", "project_type", "step_no", "command", "directions", "input_needed", "explanation"],
                "search", ["language", "project_type", "command", "directions", "explanation"], "order", "language, project_type, step_no"),
            "instruction_commands", Map("label", "Instruction Commands", "table", "instruction_commands",
                "columns", ["name", "syntax", "ahk_mapping", "description", "example"],
                "search", ["name", "syntax", "ahk_mapping", "description", "example"], "order", "name"),
            "instruction_programs", Map("label", "Instruction Programs", "table", "instruction_programs",
                "columns", ["id", "name", "run_count", "last_run", "updated_at", "source"],
                "search", ["name", "source"], "order", "updated_at DESC")
        )
    }

    __New(initialKey := "queries") {
        sources := DatabaseBrowser.Sources()
        if !sources.Has(initialKey)
            initialKey := "queries"
        this.CurrentKey := initialKey

        this.GuiObj := Gui("+AlwaysOnTop", "GlobalCoder Admin - SQLite Records")
        this.GuiObj.BackColor := "1E1E1E"
        this.GuiObj.SetFont("s9", "Segoe UI")
        this.GuiObj.OnEvent("Close", (*) => this.Close())
        this.GuiObj.OnEvent("Escape", (*) => this.Close())

        this.GuiObj.Add("Text", "x12 y15 w54 cE6E6E6", "Records")
        labels := []
        selectedIndex := 1
        for key, config in sources {
            labels.Push(config["label"])
            if key = initialKey
                selectedIndex := labels.Length
        }
        this.SourceDrop := this.GuiObj.Add("DropDownList", "x70 y11 w260 Choose" . selectedIndex, labels)
        this.SourceDrop.OnEvent("Change", (*) => this.ChangeSource())

        this.SearchEdit := this.GuiObj.Add("Edit", "x342 y11 w430 Background252526 cFFFFFF")
        this.GuiObj.Add("Button", "x782 y10 w80 h28 Default", "Search").OnEvent("Click", (*) => this.Search())
        this.GuiObj.Add("Button", "x870 y10 w70 h28", "Clear").OnEvent("Click", (*) => this.ClearSearch())
        this.GuiObj.Add("Button", "x948 y10 w140 h28", "Open DB Folder").OnEvent("Click", (*) => this.OpenDatabaseFolder())

        this.GuiObj.Add("Button", "x12 y48 w74 h28", "< Previous").OnEvent("Click", (*) => this.PreviousPage())
        this.GuiObj.Add("Button", "x94 y48 w74 h28", "Next >").OnEvent("Click", (*) => this.NextPage())
        this.GuiObj.Add("Button", "x176 y48 w74 h28", "Refresh").OnEvent("Click", (*) => this.Load())
        this.GuiObj.Add("Button", "x834 y48 w122 h28", "Record Details").OnEvent("Click", (*) => this.ShowSelectedDetails())
        this.GuiObj.Add("Button", "x964 y48 w124 h28", "Copy Record").OnEvent("Click", (*) => this.CopySelectedRecord())

        this.List := this.GuiObj.Add("ListView", "x12 y86 w1076 h520 -Multi +Grid Background252526 cE6E6E6", ["Loading"])
        this.List.OnEvent("DoubleClick", (ctrl, row) => this.ShowSelectedDetails(row))
        this.StatusText := this.GuiObj.Add("Text", "x12 y618 w1076 h42 cA8C7E6", "Loading SQLite records...")
        this.GuiObj.Add("Text", "x12 y666 w850 h22 c777777", "Enter: search | Double-click: full record | Esc: close | Up/Down: select")
        this.GuiObj.Add("Button", "x998 y660 w90 h30", "Close").OnEvent("Click", (*) => this.Close())

        this.GuiObj.Show("w1100 h704")
        WinActivate("ahk_id " . this.GuiObj.Hwnd)
        this.Load()
    }

    ChangeSource() {
        selectedLabel := this.SourceDrop.Text
        for key, config in DatabaseBrowser.Sources() {
            if config["label"] = selectedLabel {
                this.CurrentKey := key
                break
            }
        }
        this.Page := 1
        this.Load()
    }

    Search() {
        this.Page := 1
        this.Load()
    }

    ClearSearch() {
        this.SearchEdit.Value := ""
        this.Page := 1
        this.Load()
        this.SearchEdit.Focus()
    }

    PreviousPage() {
        if this.Page > 1 {
            this.Page -= 1
            this.Load()
        }
    }

    NextPage() {
        if this.Page * this.PageSize < this.TotalRows {
            this.Page += 1
            this.Load()
        }
    }

    Load() {
        config := DatabaseBrowser.Sources()[this.CurrentKey]
        whereSql := this.BuildWhere(config)
        this.TotalRows := Integer(GlobalCoderDatabase.Scalar("SELECT COUNT(*) FROM " . config["table"] . whereSql . ";", "0"))
        maxPage := Max(1, Ceil(this.TotalRows / this.PageSize))
        this.Page := Min(this.Page, maxPage)
        offset := (this.Page - 1) * this.PageSize
        columnsSql := DatabaseBrowser.Join(config["columns"], ",")
        sql := "SELECT " . columnsSql . " FROM " . config["table"] . whereSql
            . " ORDER BY " . config["order"] . " LIMIT " . this.PageSize . " OFFSET " . offset . ";"
        this.CurrentRows := GlobalCoderDatabase.Rows(sql)
        this.CurrentColumns := config["columns"]
        this.RebuildList()

        firstRow := this.TotalRows = 0 ? 0 : offset + 1
        lastRow := Min(this.TotalRows, offset + this.CurrentRows.Length)
        this.StatusText.Text := config["label"] . ": records " . firstRow . "-" . lastRow . " of " . this.TotalRows
            . " | page " . this.Page . " of " . maxPage . " | table: " . config["table"]
    }

    BuildWhere(config) {
        term := Trim(this.SearchEdit.Value)
        if term = ""
            return ""
        likeValue := GlobalCoderDatabase.Q("%" . term . "%")
        clauses := []
        for columnName in config["search"]
            clauses.Push("CAST(" . columnName . " AS TEXT) LIKE " . likeValue)
        return " WHERE " . DatabaseBrowser.Join(clauses, " OR ")
    }

    RebuildList() {
        this.List.Delete()
        while this.List.GetCount("Column") > 0
            this.List.DeleteCol(1)
        for index, columnName in this.CurrentColumns
            this.List.InsertCol(index, , columnName)
        for row in this.CurrentRows {
            values := []
            for columnName in this.CurrentColumns
                values.Push(DatabaseBrowser.Compact(row[columnName]))
            this.List.Add(, values*)
        }
        for index, columnName in this.CurrentColumns {
            width := (columnName = "query" || columnName = "message" || columnName = "detail"
                || columnName = "content" || columnName = "stack" || columnName = "path") ? 280 : 135
            if columnName = "id" || columnName = "line" || columnName = "rating" || columnName = "enabled"
                width := 65
            this.List.ModifyCol(index, width)
        }
        if this.CurrentRows.Length > 0
            this.List.Modify(1, "+Select +Focus Vis")
    }

    SelectedRow(rowIndex := 0) {
        if rowIndex < 1
            rowIndex := this.List.GetNext(0, "F")
        if rowIndex < 1
            rowIndex := this.List.GetNext()
        if rowIndex < 1 || rowIndex > this.CurrentRows.Length
            return ""
        return this.CurrentRows[rowIndex]
    }

    ShowSelectedDetails(rowIndex := 0) {
        row := this.SelectedRow(rowIndex)
        if !IsObject(row) {
            GUT_Display("Database Records", "Select a record first.", 2200)
            return
        }
        config := DatabaseBrowser.Sources()[this.CurrentKey]
        GUT_Display(config["label"] . " - Record Details", this.RowText(row), -1,
            Map("width", 900, "height", 620, "persistent", true, "position", "Center"))
    }

    CopySelectedRecord() {
        row := this.SelectedRow()
        if !IsObject(row) {
            GUT_Display("Database Records", "Select a record first.", 2200)
            return
        }
        A_Clipboard := this.RowText(row)
        GUT_Display("Record Copied", "The complete SQLite record is on the clipboard.", 1800)
    }

    RowText(row) {
        textValue := ""
        for columnName in this.CurrentColumns
            textValue .= columnName . ":`n" . row[columnName] . "`n`n"
        return RTrim(textValue, "`r`n")
    }

    OpenDatabaseFolder() {
        SplitPath(GC_DB_PATH, , &databaseFolder)
        Run("explorer.exe " . QuoteArgument(databaseFolder))
    }

    Close() {
        if IsObject(this.GuiObj)
            try this.GuiObj.Destroy()
        this.GuiObj := ""
    }

    static Compact(value, maxLength := 180) {
        compactValue := StrReplace(StrReplace(String(value), "`r", " "), "`n", " ")
        return StrLen(compactValue) > maxLength ? SubStr(compactValue, 1, maxLength - 3) . "..." : compactValue
    }

    static Join(values, separator := ", ") {
        result := ""
        for index, value in values
            result .= (index > 1 ? separator : "") . value
        return result
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
        NativeMenuMonitor.Init()
        GlobalCoderDatabase.Init(GC_DB_PATH)
        MigrateLegacyStorageOnce()
        LoadRuntimeSettings()
        ProjectManager.Init()
        SyntaxGuideRepository.Seed()
        SnippetRepository.Init()
        HotstringManager.Init()
        RegisterGlobalHotkeys()
        ContextBindingManager.Init()
        SnippetSuggestionManager.Init()
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
    global GC_CallingWindowHwnd, GC_CallingControl, GC_MenuCommandContexts
    if GlobalCoderDatabase.Scalar("PRAGMA integrity_check;", "failed") != "ok"
        throw Error("SQLite integrity check failed")
    if Integer(GlobalCoderDatabase.Scalar("SELECT COUNT(*) FROM instruction_commands;", "0")) < 10
        throw Error("Instruction language seed data is incomplete")
    if UrlEncode("a b+é") != "a+b%2B%C3%A9"
        throw Error("UTF-8 URL encoding validation failed")

    menuItems := []
    Loop 90
        menuItems.Push(Map("label", "Validation item " . A_Index, "function", "Action_OpenFolder", "context", A_ScriptDir))
    validationMenu := SafeMenuBuilder.Build(menuItems, ExecuteActionItem)
    if !IsObject(validationMenu)
        throw Error("Safe menu pagination failed")

    adminItems := BuildSpecialSubmenu("Admin")
    if adminItems.Length < 10
        throw Error("Custom Admin submenu validation failed")
    adminMenu := BuildAdminNativeMenu()
    if !IsObject(adminMenu)
        throw Error("Native Admin submenu validation failed")

    recordBrowser := DatabaseBrowser("queries")
    if !IsObject(recordBrowser.GuiObj) || recordBrowser.CurrentKey != "queries"
        throw Error("SQLite record browser validation failed")
    recordBrowser.Close()

    if Integer(GlobalCoderDatabase.Scalar("SELECT COUNT(*) FROM content_items WHERE content_type='guide';", "0")) < 6
        throw Error("Built-in syntax guide seed validation failed")
    guideBrowser := SyntaxGuideBrowser()
    if !IsObject(guideBrowser.GuiObj) || guideBrowser.Rows.Length < 6
        throw Error("Syntax guide browser validation failed")
    guideBrowser.Close()

    if Integer(GlobalCoderDatabase.Scalar("SELECT COUNT(*) FROM context_bindings WHERE trigger='gcd';", "0")) != 2
        throw Error("Contextual gcd hotstring seed validation failed")
    if ContextBindingManager.Registered.Length < 2
        throw Error("Context binding runtime registration failed")
    bindingEditor := ContextBindingEditor()
    if !IsObject(bindingEditor.GuiObj) || bindingEditor.Rows.Length < 2
        throw Error("Context binding editor validation failed")
    bindingEditor.LoadSelected(1)
    if Trim(bindingEditor.TriggerEdit.Value) = ""
        throw Error("Context binding form population failed")
    bindingEditor.Close()

    contextRecordBrowser := DatabaseBrowser("context_bindings")
    if contextRecordBrowser.CurrentRows.Length < 2
        throw Error("Context binding record browser validation failed")
    contextRecordBrowser.Close()

    if ContextBindingManager.ExpandTokens("{{scriptdir}}") != A_ScriptDir
        throw Error("Context binding token expansion failed")

    if Integer(GlobalCoderDatabase.Scalar("SELECT COUNT(*) FROM snippet_languages WHERE enabled=1;", "0")) != 7
        throw Error("Snippet language taxonomy validation failed")
    if Integer(GlobalCoderDatabase.Scalar("SELECT COUNT(*) FROM snippet_feature_groups WHERE enabled=1;", "0")) < 32
        throw Error("Snippet feature taxonomy validation failed")
    if Integer(GlobalCoderDatabase.Scalar("SELECT COUNT(*) FROM snippets WHERE enabled=1;", "0")) < 50
        throw Error("Starter snippet validation failed")
    if Integer(GlobalCoderDatabase.Scalar("SELECT COUNT(*) FROM snippets WHERE length(trigger)<4;", "0")) != 0
        throw Error("Snippet suggestion trigger-length validation failed")
    if Integer(GlobalCoderDatabase.Scalar("SELECT COUNT(*) FROM snippet_editor_contexts WHERE enabled=1;", "0")) < 10
        throw Error("Snippet editor-context validation failed")

    builtInBatches := Map(
        "c", "c-batch.snips",
        "cpp", "cpp-batch.snips",
        "python", "python-batch.snips",
        "javascript", "javascript-batch.snips",
        "typescript", "typescript-batch.snips",
        "csharp", "csharp-batch.snips",
        "ahk2", "autohotkey-v2-batch.snips")
    for languageCode, batchFileName in builtInBatches {
        batchPath := GC_SNIP_IMPORT_DIR . "\" . batchFileName
        if !FileExist(batchPath)
            throw Error("Built-in Snip batch is missing: " . batchPath)
        batchValidation := SnippetBatchImporter.Parse(FileRead(batchPath, "UTF-8"))
        if !batchValidation["ok"]
            throw Error(batchFileName . " validation failed: " . SnippetBatchImporter.Join(batchValidation["errors"], " | "))
        featureCoverage := Map()
        for entry in batchValidation["entries"] {
            if entry["language"] != languageCode
                throw Error(batchFileName . " contains the wrong language code: " . entry["language"])
            featureCoverage[entry["feature"]] := true
        }
        if featureCoverage.Count != 32
            throw Error(batchFileName . " does not cover all 32 Snip feature groups")
    }

    validBatch := "
    (
    GLOBALCODER_SNIPS_V1

    @@SNIP
    language: ahk2
    feature: program-structure
    name: __GlobalCoder batch validation__
    trigger: ahkbatchvalidation
    description: Temporary validation row
    @@BODY
    #Requires AutoHotkey v2.0
    {{cursor}}
    @@END
    )"
    invalidBatch := validBatch . "`n`n@@SNIP`nlanguage: ahk2`nfeature: not-a-real-feature`nname: Must not import`ntrigger: ahkinvalid`n@@BODY`nno_op()`n@@END"
    GlobalCoderDatabase.Exec("DELETE FROM snippets WHERE name='__GlobalCoder batch validation__';")
    invalidResult := SnippetBatchImporter.Import(invalidBatch, false)
    if invalidResult["ok"]
        throw Error("Invalid Snip batch was not rejected atomically")
    if Integer(GlobalCoderDatabase.Scalar("SELECT COUNT(*) FROM snippets WHERE name='__GlobalCoder batch validation__';", "0")) != 0
        throw Error("Invalid Snip batch changed SQLite before validation completed")
    try {
        firstImport := SnippetBatchImporter.Import(validBatch, false)
        if !firstImport["ok"] || firstImport["inserted"] != 1
            throw Error("Valid Snip batch insert validation failed")
        updatedBatch := StrReplace(validBatch, "{{cursor}}", "MsgBox(`"updated`")`n{{cursor}}")
        secondImport := SnippetBatchImporter.Import(updatedBatch, false)
        if !secondImport["ok"] || secondImport["updated"] != 1
            throw Error("Snip batch upsert validation failed")
        if !InStr(GlobalCoderDatabase.Scalar("SELECT body FROM snippets WHERE name='__GlobalCoder batch validation__' LIMIT 1;"), "updated")
            throw Error("Snip batch upsert did not replace the body")
    } finally {
        GlobalCoderDatabase.Exec("DELETE FROM snippets WHERE name='__GlobalCoder batch validation__';")
    }
    batchWindow := SnippetBatchImportWindow()
    if !IsObject(batchWindow.GuiObj)
        throw Error("Snip batch import window validation failed")
    batchWindow.BuiltInLanguage.Choose(1)
    batchWindow.LoadBuiltInBatch()
    combinedBatchValidation := SnippetBatchImporter.Parse(batchWindow.BatchEdit.Value)
    if !combinedBatchValidation["ok"] || combinedBatchValidation["entries"].Length < 224
        throw Error("Combined all-language Snip batch validation failed")
    batchWindow.Close()

    snipsMenu := BuildSnipsNativeMenu()
    if !IsObject(snipsMenu)
        throw Error("Bounded native Snips hierarchy validation failed")
    snipGui := SnippetBrowser("python", "loops-iteration")
    if !IsObject(snipGui.GuiObj) || snipGui.Rows.Length < 2
        throw Error("Snippet browser/editor validation failed")
    snipGui.Close()
    structureBrowser := SnippetStructureBrowser()
    if structureBrowser.Rows.Length < 224
        throw Error("Uniform language/feature placeholder structure validation failed")
    structureBrowser.Close()
    editorContextBrowser := SnippetEditorContextEditor()
    if editorContextBrowser.Rows.Length < 10
        throw Error("Snippet IDE context editor validation failed")
    editorContextBrowser.Close()

    suggestionRows := SnippetRepository.Search("python", "loops-iteration", "", 1)
    suggestionWindow := SnippetSuggestionWindow()
    suggestionWindow.Show([suggestionRows[1]], 1, "pyfo")
    suggestionWindow.Hide()
    suggestionWindow.Close()
    if !SnippetSuggestionManager.Running
        throw Error("Snippet input monitor validation failed")

    if SnippetMenuSections().Length < 10
        throw Error("Arrow-navigable Snips category tree validation failed")
    insertionRows := SnippetRepository.Search("python", "conditionals-patterns", "pyif", 1)
    insertionGui := Gui("+AlwaysOnTop", "Snips Cursor Target Validation")
    insertionEdit := insertionGui.Add("Edit", "w500 h260 +Multi")
    insertionGui.Show("w520 h290")
    WinActivate("ahk_id " . insertionGui.Hwnd)
    insertionEdit.Focus()
    savedCallingHwnd := GC_CallingWindowHwnd
    savedCallingControl := GC_CallingControl
    GC_CallingWindowHwnd := insertionGui.Hwnd
    GC_CallingControl := ControlGetFocus("ahk_id " . insertionGui.Hwnd)
    previewActiveHwnd := WinExist("A")
    PreviewSnippetFeature("python", "conditionals-patterns")
    Sleep(50)
    if WinExist("A") != previewActiveHwnd
        throw Error("Passive snippet preview stole editor focus")
    PassivePreviewWindow.CloseCurrent()
    insertionEdit.Focus()
    InsertSnippetById(insertionRows[1]["id"])
    Sleep(80)
    if !InStr(insertionEdit.Value, "if condition:")
        throw Error("Native menu snippet did not insert at the calling editor cursor. Control: " . GC_CallingControl . " Captured: " . insertionEdit.Value)
    GlobalCoderDatabase.Exec("UPDATE snippets SET usage_count=MAX(0,usage_count-1) WHERE id=" . Integer(insertionRows[1]["id"]) . ";")

    GlobalCoderDatabase.Exec("SAVEPOINT validation_snip_context;")
    GlobalCoderDatabase.SetSetting("Menu", "LastSnippetLanguage", "")
    GlobalCoderDatabase.SetSetting("Menu", "LastSnippetSection", "")
    NativeMenuMonitor.ResetMappings()
    hoverSectionMenu := BuildSnippetSectionNativeMenu("python", "control-flow", false)
    NativeMenuMonitor.Enter()
    NativeMenuMonitor.Select((0x0010 << 16) | 0, hoverSectionMenu.Handle)
    NativeMenuMonitor.Exit()
    if GlobalCoderDatabase.GetSetting("Menu", "LastSnippetLanguage", "") != "python"
        || GlobalCoderDatabase.GetSetting("Menu", "LastSnippetSection", "") != "control-flow"
        throw Error("Highlighted Snips section persistence validation failed")
    resumeMenu := BuildSnippetSectionNativeMenu("python", "control-flow", true)
    if !IsObject(resumeMenu)
        throw Error("Ctrl+M Snips resume menu validation failed")

    ghostWindow := GhostSnippetCaptureWindow.Show("c", "security-crypto")
    priorGhostTick := ghostWindow.LastChangeTick
    ghostWindow.BodyEdit.Value := "validation_security_call();"
    ghostWindow.OnChange()
    if ghostWindow.LastChangeTick < priorGhostTick
        throw Error("Ghost Snip debounce refresh validation failed")
    ghostWindow.LastChangeTick := A_TickCount - 5100
    ghostWindow.Tick()
    if Integer(GlobalCoderDatabase.Scalar("SELECT COUNT(*) FROM snippets WHERE language_code='c' AND feature_code='security-crypto' "
        . "AND body='validation_security_call();';", "0")) < 1
        throw Error("Ghost Snip contextual auto-save validation failed")
    PassivePreviewWindow.CloseCurrent()
    GlobalCoderDatabase.Exec("ROLLBACK TO validation_snip_context;")
    GlobalCoderDatabase.Exec("RELEASE validation_snip_context;")
    RebuildMenu(true)

    pathContextMenu := Menu()
    pathContextMenu.Add("Validation project file", (*) => 0)
    NativeMenuMonitor.RegisterLastItem(pathContextMenu, Map("kind", "file", "path", A_ScriptFullPath))
    pathCommandId := DllCall("User32.dll\GetMenuItemID", "Ptr", pathContextMenu.Handle, "Int", 0, "UInt")
    legendActiveHwnd := WinExist("A")
    NativeMenuMonitor.Enter()
    NativeMenuMonitor.Select(pathCommandId, pathContextMenu.Handle)
    if !NativeMenuPathActionIsActive()
        throw Error("Highlighted native menu path-action context validation failed")
    if WinExist("A") != legendActiveHwnd
        throw Error("Native menu key legend stole editor focus")
    NativeMenuMonitor.Exit()
    projectTreeMenu := BuildProjectTreesNativeMenu()
    if !IsObject(projectTreeMenu) || GC_MenuCommandContexts.Count = 0
        throw Error("Bounded project file-tree menu context validation failed")

    GC_CallingWindowHwnd := savedCallingHwnd
    GC_CallingControl := savedCallingControl
    insertionGui.Destroy()

    snippetRecordBrowser := DatabaseBrowser("snippets")
    if snippetRecordBrowser.CurrentRows.Length < 50
        throw Error("Snippet SQLite record browser validation failed")
    snippetRecordBrowser.Close()

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
    required := [GC_DATA_DIR, GC_PROJECT_DIR, GC_LIBRARY_DIR, GC_SNIP_IMPORT_DIR]
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
    try SnippetSuggestionManager.Stop()
    try {
        if IsObject(GhostSnippetCaptureWindow.Current)
            GhostSnippetCaptureWindow.Current.Finish(false)
    }
    try PassivePreviewWindow.CloseCurrent()
    try NativeMenuLegendWindow.Close()
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

    A_TrayMenu.Add("Projects", BuildProjectsNativeMenu())
    A_TrayMenu.Add("Knowledge Web", BuildKnowledgeNativeMenu())
    A_TrayMenu.Add("Automation", BuildAutomationNativeMenu())
    A_TrayMenu.Add("Snips Admin", BuildSnipsQuickMenu())
    A_TrayMenu.Add("Admin", BuildAdminNativeMenu())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Reload", (*) => Reload())
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.Default := "Open GlobalCoder"

    ; AutoHotkey v2 equivalent of: Menu, Tray, Icon, Shell32.dll, 14, 1
    ; The final true freezes the loaded globe icon so later tray updates keep it.
    try TraySetIcon(A_WinDir "\System32\Shell32.dll", 14, true)
    A_IconTip := "GlobalCoder v7 - portable project and knowledge manager"
    try OnMessage(0x0404, TrayIconCallback, 0)
    OnMessage(0x0404, TrayIconCallback)
}

TrayIconCallback(wParam, lParam, msg, hwnd) {
    if lParam = 0x0203 {
        ShowMainFeaturesGUI()
        return 0
    }
}

PrepareMenu(*) {
    ; Every native branch is bounded. Snips caps languages, domains, features,
    ; and direct insert choices; full database content belongs in ListViews.
    NativeMenuMonitor.ResetMappings()
    menuObj := Menu()
    menuObj.Add("GlobalCoder Dashboard", (*) => ShowMainFeaturesGUI())
    menuObj.Add("Browse Library", (*) => ShowCustomMenu())
    menuObj.Add()
    menuObj.Add("Projects", BuildProjectsNativeMenu())
    menuObj.Add("Knowledge Web", BuildKnowledgeNativeMenu())
    menuObj.Add("Automation", BuildAutomationNativeMenu())
    menuObj.Add("Snips", BuildSnipsNativeMenu())
    menuObj.Add("Admin", BuildAdminNativeMenu())
    menuObj.Add()
    menuObj.Add("Exit", (*) => ExitApp())
    return menuObj
}

BuildProjectsNativeMenu() {
    menuObj := Menu()
    menuObj.Add("Create New Project", (*) => ShowNewProjectWizard())
    menuObj.Add("Recent Projects", (*) => ShowRecentProjects())
    menuObj.Add("Learning Center", (*) => ShowLearningCenter())
    menuObj.Add("Project Settings", (*) => ShowProjectSettings())
    menuObj.Add()
    menuObj.Add("Project File Trees", BuildProjectTreesNativeMenu())
    return menuObj
}

BuildProjectTreesNativeMenu() {
    treeMenu := Menu()
    state := Map("remaining", 420)
    seen := Map()
    addedCount := 0
    rootPath := GlobalCoderDatabase.GetSetting("Projects", "DefaultRoot", GC_PROJECT_DIR)
    if DirExist(rootPath) {
        treeMenu.Add("Default Projects Root", BuildProjectPathNativeMenu(rootPath, 0, state))
        NativeMenuMonitor.RegisterLastItem(treeMenu, Map("kind", "folder", "path", rootPath))
        seen[StrLower(NormalizePath(rootPath))] := true
        addedCount += 1
    }
    rows := GlobalCoderDatabase.Rows("SELECT name,path FROM recent_projects ORDER BY last_opened DESC LIMIT 15;")
    for row in rows {
        path := row["path"]
        normalized := StrLower(NormalizePath(path))
        if !DirExist(path) || seen.Has(normalized)
            continue
        label := row["name"] != "" ? row["name"] : path
        treeMenu.Add(label, BuildProjectPathNativeMenu(path, 0, state))
        NativeMenuMonitor.RegisterLastItem(treeMenu, Map("kind", "folder", "path", path))
        seen[normalized] := true
        addedCount += 1
        if state["remaining"] <= 0
            break
    }
    if addedCount = 0
        treeMenu.Add("No project folders recorded", (*) => PassivePreviewWindow.Show("Project Trees", "Create or open a project first.", 2600))
    return treeMenu
}

BuildProjectPathNativeMenu(folderPath, depth, state) {
    menuObj := Menu()
    menuObj.Add("Open This Folder", (*) => Run("explorer.exe " . QuoteArgument(folderPath)))
    NativeMenuMonitor.RegisterLastItem(menuObj, Map("kind", "folder", "path", folderPath))
    state["remaining"] -= 1
    if depth >= 6 || state["remaining"] <= 0 {
        menuObj.Add("More Items in Explorer...", (*) => Run("explorer.exe " . QuoteArgument(folderPath)))
        NativeMenuMonitor.RegisterLastItem(menuObj, Map("kind", "folder", "path", folderPath))
        return menuObj
    }

    menuObj.Add()
    itemCount := 0
    truncated := false
    try {
        Loop Files, folderPath . "\*", "D" {
            if A_LoopFileName = ".git" || A_LoopFileName = "node_modules" || A_LoopFileName = ".venv"
                continue
            if itemCount >= 20 || state["remaining"] <= 0 {
                truncated := true
                break
            }
            childPath := A_LoopFilePath
            menuObj.Add("[+] " . A_LoopFileName, BuildProjectPathNativeMenu(childPath, depth + 1, state))
            NativeMenuMonitor.RegisterLastItem(menuObj, Map("kind", "folder", "path", childPath))
            itemCount += 1
            state["remaining"] -= 1
        }
        if itemCount < 20 && state["remaining"] > 0 {
            Loop Files, folderPath . "\*", "F" {
                if itemCount >= 20 || state["remaining"] <= 0 {
                    truncated := true
                    break
                }
                filePath := A_LoopFilePath
                menuObj.Add(A_LoopFileName, OpenProjectTreeFile.Bind(filePath))
                NativeMenuMonitor.RegisterLastItem(menuObj, Map("kind", "file", "path", filePath))
                itemCount += 1
                state["remaining"] -= 1
            }
        }
    }
    if truncated || state["remaining"] <= 0 {
        menuObj.Add("More Items in Explorer...", (*) => Run("explorer.exe " . QuoteArgument(folderPath)))
        NativeMenuMonitor.RegisterLastItem(menuObj, Map("kind", "folder", "path", folderPath))
    }
    return menuObj
}

OpenProjectTreeFile(filePath, *) {
    Run(filePath)
}

BuildKnowledgeNativeMenu() {
    menuObj := Menu()
    menuObj.Add("Add Knowledge", (*) => ShowAddKnowledgeGUI())
    menuObj.Add("Search Knowledge", (*) => ShowKnowledgeSearch())
    menuObj.Add("Knowledge Test", (*) => ShowKnowledgeTest())
    menuObj.Add("Review a Knowledge Gap", (*) => ActivityMonitor.PromptForGap())
    return menuObj
}

BuildAutomationNativeMenu() {
    menuObj := Menu()
    menuObj.Add("Syntax and Setup Guides", (*) => ShowSyntaxGuides())
    menuObj.Add("Instruction Language", (*) => ShowInstructionLanguageConsole())
    menuObj.Add("Command Reference", (*) => ShowInstructionReference())
    menuObj.Add("Find in Knowledge and Files", (*) => FindInFiles())
    menuObj.Add("Google Search", (*) => GoogleSearchWithLogging())
    menuObj.Add("Context Hotkeys / Hotstrings", (*) => ShowContextBindings())
    return menuObj
}

BuildSnipsQuickMenu() {
    menuObj := Menu()
    menuObj.Add("Browse / Add Snips", (*) => ShowSnippets())
    menuObj.Add("Batch Import Snips...", (*) => ShowSnippetBatchImporter())
    menuObj.Add("Uniform Feature Structure", (*) => ShowSnippetStructure())
    menuObj.Add("Suggestion IDE Applications", (*) => ShowSnippetEditorContexts())
    menuObj.Add("Toggle Four-Character Suggestions", (*) => SnippetSuggestionManager.Toggle())
    if GlobalCoderDatabase.GetSetting("Snippets", "SuggestionsEnabled", "1") = "1"
        menuObj.Check("Toggle Four-Character Suggestions")
    return menuObj
}

BuildSnipsNativeMenu() {
    ; Normal Snips navigation is entirely native: no ListView or management GUI.
    menuObj := Menu()
    languageRows := SnippetRepository.Languages()
    for index, languageRow in languageRows {
        if index > 20
            break
        menuObj.Add(languageRow["label"], BuildSnippetLanguageNativeMenu(languageRow["code"]))
    }
    if languageRows.Length > 20
        menuObj.Add("Additional languages are available in Admin", (*) => ShowSnippetMenuHelp())
    menuObj.Add()
    menuObj.Add("Snips Keyboard Help (passive)", (*) => ShowSnippetMenuHelp())
    menuObj.Add("Four-Character Suggestions", (*) => SnippetSuggestionManager.Toggle())
    if GlobalCoderDatabase.GetSetting("Snippets", "SuggestionsEnabled", "1") = "1"
        menuObj.Check("Four-Character Suggestions")
    return menuObj
}

BuildSnippetLanguageNativeMenu(languageCode) {
    languageMenu := Menu()
    for section in SnippetMenuSections() {
        sectionMenu := BuildSnippetSectionNativeMenu(languageCode, section["code"], false)
        languageMenu.Add(section["label"], sectionMenu)
    }
    return languageMenu
}

BuildSnippetSectionNativeMenu(languageCode, sectionCode, includeResumeHeader := false) {
    sectionMenu := Menu()
    section := SnippetMenuSectionByCode(sectionCode)
    if !IsObject(section)
        return sectionMenu
    if includeResumeHeader {
        languageLabel := GlobalCoderDatabase.Scalar("SELECT label FROM snippet_languages WHERE code="
            . GlobalCoderDatabase.Q(languageCode) . " LIMIT 1;", languageCode)
        headerLabel := "[Snips > " . languageLabel . " > " . section["label"] . "]"
        sectionMenu.Add(headerLabel, (*) => 0)
        sectionMenu.Disable(headerLabel)
        sectionMenu.Add()
    }
    featureRows := SnippetRepository.Features()
    featureLookup := Map()
    for row in featureRows
        featureLookup[row["code"]] := row
    for featureCode in section["features"] {
        if !featureLookup.Has(featureCode)
            continue
        featureRow := featureLookup[featureCode]
        menuLabel := SnippetFeatureMenuLabel(featureCode, featureRow["label"])
        sectionMenu.Add(menuLabel, BuildSnippetFeatureNativeMenu(languageCode, featureCode))
        NativeMenuMonitor.RegisterLastItem(sectionMenu, Map("kind", "snippet_feature",
            "language_code", languageCode, "feature_code", featureCode,
            "section_code", sectionCode, "label", menuLabel))
    }
    if includeResumeHeader {
        sectionMenu.Add()
        sectionMenu.Add("Full GlobalCoder Menu", (*) => ShowMainMenu())
    }
    return sectionMenu
}

BuildSnippetFeatureNativeMenu(languageCode, featureCode) {
    rows := SnippetRepository.Search(languageCode, featureCode, "", 500)
    if rows.Length > 0 {
        items := []
        for row in rows
            items.Push(Map("label", row["name"] . "  [" . row["trigger"] . "]", "id", row["id"],
                "language_code", languageCode, "feature_code", featureCode))
        featureMenu := SafeMenuBuilder.Build(items, InsertSnippetMenuItem, 20)
        featureMenu.Add()
        featureMenu.Add("Preview Feature Reference (passive)", (*) => PreviewSnippetFeature(languageCode, featureCode))
    } else {
        featureMenu := Menu()
        featureMenu.Add("No syntax saved yet - type one now...", (*) => CaptureSnippetPlaceholder(languageCode, featureCode))
    }
    return featureMenu
}

SnippetMenuSections() {
    return [
        Map("code", "basics-types", "label", "Basics and Types", "features", ["program-structure", "variables-constants", "types-casting", "operators-expressions", "strings-text"]),
        Map("code", "collections-data", "label", "Collections and Data", "features", ["arrays-collections", "maps-sets", "data-structures-algorithms"]),
        Map("code", "control-flow", "label", "Control Flow", "features", ["conditionals-patterns", "loops-iteration"]),
        Map("code", "functions-modules", "label", "Functions and Modules", "features", ["functions-parameters", "generics-templates", "modules-imports"]),
        Map("code", "objects-contracts", "label", "Objects and Contracts", "features", ["classes-objects", "interfaces-protocols"]),
        Map("code", "errors-resources", "label", "Errors and Resources", "features", ["errors-exceptions", "memory-resources"]),
        Map("code", "files-formats-time", "label", "Files, Formats, and Time", "features", ["files-streams", "dates-time", "regex-parsing", "serialization-formats"]),
        Map("code", "async-events", "label", "Async and Events", "features", ["async-concurrency", "ui-events"]),
        Map("code", "integration-system", "label", "Integration and System", "features", ["networking-http", "databases-sql", "processes-cli", "interop-native"]),
        Map("code", "testing-tooling", "label", "Testing and Tooling", "features", ["testing-assertions", "debugging-logging", "build-dependencies"]),
        Map("code", "security-language", "label", "Security and Language Features", "features", ["security-crypto", "language-specific"])
    ]
}

SnippetMenuSectionByCode(sectionCode) {
    for section in SnippetMenuSections() {
        if section["code"] = sectionCode
            return section
    }
    return ""
}

SnippetMenuSectionForFeature(featureCode) {
    for section in SnippetMenuSections() {
        for candidate in section["features"] {
            if candidate = featureCode
                return section
        }
    }
    return ""
}

SnippetFeatureMenuLabel(featureCode, fallbackLabel) {
    labels := Map(
        "program-structure", "Program / File Structure",
        "variables-constants", "Variables / Constants / Scope",
        "types-casting", "Types / Casting / Type Checks",
        "operators-expressions", "Operators / Expressions",
        "strings-text", "Strings / Formatting / Encoding",
        "arrays-collections", "Arrays / Lists / Collections",
        "maps-sets", "Maps / Dictionaries / Sets",
        "conditionals-patterns", "If / Else / Switch / Match",
        "loops-iteration", "For / While / Loop / Iteration",
        "functions-parameters", "Functions / Parameters / Lambdas",
        "classes-objects", "Classes / Objects / Construction",
        "interfaces-protocols", "Interfaces / Traits / Protocols",
        "generics-templates", "Generics / Templates",
        "modules-imports", "Modules / Packages / Imports",
        "errors-exceptions", "Errors / Exceptions / Cleanup",
        "files-streams", "Files / Paths / Streams",
        "dates-time", "Dates / Time / Timers",
        "regex-parsing", "Regex / Parsing / Validation",
        "serialization-formats", "JSON / XML / CSV / Serialization",
        "memory-resources", "Memory / Pointers / Resources",
        "data-structures-algorithms", "Algorithms / Data Structures",
        "async-concurrency", "Async / Threads / Concurrency",
        "networking-http", "Networking / HTTP / APIs",
        "databases-sql", "Databases / SQL / Transactions",
        "processes-cli", "Processes / CLI / Environment",
        "ui-events", "UI / Events / Callbacks",
        "testing-assertions", "Tests / Assertions / Mocks",
        "debugging-logging", "Debugging / Logging / Profiling",
        "build-dependencies", "Build / Dependencies / Tooling",
        "interop-native", "Interop / COM / DLL / Native APIs",
        "security-crypto", "Security / Hashing / Cryptography",
        "language-specific", "Language-Specific Features"
    )
    return labels.Has(featureCode) ? labels[featureCode] : fallbackLabel
}

InsertSnippetMenuItem(item, *) {
    RememberSnippetMenuContext(item["language_code"], item["feature_code"])
    InsertSnippetById(item["id"])
}

BuildRecordViewsNativeMenu() {
    menuObj := Menu()
    menuObj.Add("Google / Query History", (*) => ShowDatabaseBrowser("queries"))
    menuObj.Add("Recent Projects", (*) => ShowDatabaseBrowser("recent_projects"))
    menuObj.Add("Knowledge Nodes", (*) => ShowDatabaseBrowser("knowledge_nodes"))
    menuObj.Add("Knowledge Relationships", (*) => ShowDatabaseBrowser("knowledge_edges"))
    menuObj.Add("Knowledge Gaps", (*) => ShowDatabaseBrowser("knowledge_gaps"))
    menuObj.Add("Knowledge Reviews", (*) => ShowDatabaseBrowser("knowledge_reviews"))
    menuObj.Add("Indexed Content", (*) => ShowDatabaseBrowser("content_items"))
    menuObj.Add("Tutorial Steps", (*) => ShowDatabaseBrowser("tutorial_steps"))
    menuObj.Add("Instruction Commands", (*) => ShowDatabaseBrowser("instruction_commands"))
    menuObj.Add("Instruction Programs", (*) => ShowDatabaseBrowser("instruction_programs"))
    menuObj.Add("Action Definitions", (*) => ShowDatabaseBrowser("actions"))
    menuObj.Add("Hotstrings", (*) => ShowDatabaseBrowser("hotstrings"))
    menuObj.Add("Context Hotkeys / Hotstrings", (*) => ShowDatabaseBrowser("context_bindings"))
    menuObj.Add("Code Snippets", (*) => ShowDatabaseBrowser("snippets"))
    menuObj.Add("Snippet Languages", (*) => ShowDatabaseBrowser("snippet_languages"))
    menuObj.Add("Snippet Feature Groups", (*) => ShowDatabaseBrowser("snippet_feature_groups"))
    menuObj.Add("Snippet IDE Applications", (*) => ShowDatabaseBrowser("snippet_editor_contexts"))
    menuObj.Add("Settings", (*) => ShowDatabaseBrowser("settings"))
    menuObj.Add("Activity / Idle Log", (*) => ShowDatabaseBrowser("activity_log"))
    menuObj.Add("Event Log", (*) => ShowDatabaseBrowser("event_log"))
    menuObj.Add("Error Log", (*) => ShowDatabaseBrowser("errors"))
    return menuObj
}

BuildAdminNativeMenu() {
    menuObj := Menu()
    menuObj.Add("Browse SQLite Records", BuildRecordViewsNativeMenu())
    menuObj.Add("Query History", (*) => ShowDatabaseBrowser("queries"))
    menuObj.Add("Error Log", (*) => ShowDatabaseBrowser("errors"))
    menuObj.Add("Event Log", (*) => ShowDatabaseBrowser("event_log"))
    menuObj.Add()
    menuObj.Add("Settings", (*) => ShowSettingsGUI())
    menuObj.Add("Project Settings", (*) => ShowProjectSettings())
    menuObj.Add("Hotstrings", (*) => ShowHotstringsGUI())
    menuObj.Add("Context Hotkeys / Hotstrings", (*) => ShowContextBindings())
    menuObj.Add("Snip Database Editor", (*) => ShowSnippets())
    menuObj.Add("Batch Import Snips...", (*) => ShowSnippetBatchImporter())
    menuObj.Add("Snip Feature Coverage", (*) => ShowSnippetStructure())
    menuObj.Add("Snip Suggestion IDE Apps", (*) => ShowSnippetEditorContexts())
    menuObj.Add("Add Action Definition", (*) => ShowAddActionGUI())
    menuObj.Add()
    menuObj.Add("Rebuild Menus", (*) => RebuildMenu())
    menuObj.Add("Open Script Folder", (*) => Run("explorer.exe " . QuoteArgument(A_ScriptDir)))
    menuObj.Add("Open Database Folder", (*) => OpenDatabaseFolder())
    menuObj.Add("Reload GlobalCoder", (*) => Reload())
    return menuObj
}

ShowMainMenu(*) {
    global GC_MainMenu
    CaptureNativeMenuCallingContext()
    if !IsObject(GC_MainMenu)
        GC_MainMenu := PrepareMenu()
    GC_MainMenu.Show()
}

ShowLastSnippetSectionMenu(*) {
    CaptureNativeMenuCallingContext()
    languageCode := GlobalCoderDatabase.GetSetting("Menu", "LastSnippetLanguage", "")
    sectionCode := GlobalCoderDatabase.GetSetting("Menu", "LastSnippetSection", "")
    if languageCode = "" || !IsObject(SnippetMenuSectionByCode(sectionCode)) {
        ShowMainMenu()
        return
    }
    resumeMenu := BuildSnippetSectionNativeMenu(languageCode, sectionCode, true)
    resumeMenu.Show()
}

CaptureNativeMenuCallingContext() {
    global GC_CallingWindowHwnd, GC_CallingControl
    GC_CallingWindowHwnd := WinExist("A")
    try GC_CallingControl := ControlGetFocus("ahk_id " . GC_CallingWindowHwnd)
    catch
        GC_CallingControl := ""
}

RememberSnippetMenuContext(languageCode, featureCode) {
    section := SnippetMenuSectionForFeature(featureCode)
    if !IsObject(section)
        return
    GlobalCoderDatabase.SetSetting("Menu", "LastSnippetLanguage", languageCode)
    GlobalCoderDatabase.SetSetting("Menu", "LastSnippetSection", section["code"])
    GlobalCoderDatabase.SetSetting("Menu", "LastSnippetFeature", featureCode)
}

RebuildMenu(silent := false, *) {
    global GC_MainMenu
    GC_MainMenu := PrepareMenu()
    SetupTrayMenu()
    if Type(silent) != "Integer"
        silent := false
    if !silent
        GUT_Display("Menu Ready", "The bounded native menu, Snips hierarchy, and library browser were refreshed.", 2500)
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
    CreateCustomMenuGui("GlobalCoder v7")
}

BuildMenuItems(path, isSubmenu := false) {
    result := []
    if isSubmenu
        result.Push(Map("name", "< Back", "path", "", "type", "back"))
    else {
        result.Push(Map("name", "Projects >", "path", "submenu:Projects", "type", "submenu"))
        result.Push(Map("name", "Knowledge Web >", "path", "submenu:Knowledge", "type", "submenu"))
        result.Push(Map("name", "Automation >", "path", "submenu:Automation", "type", "submenu"))
        result.Push(Map("name", "Snips >", "path", "submenu:Snips", "type", "submenu"))
        result.Push(Map("name", "Admin >", "path", "submenu:Admin", "type", "submenu"))
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

BuildSpecialSubmenu(submenuName) {
    result := [Map("name", "< Back", "path", "", "type", "back")]
    switch submenuName {
        case "Projects":
            result.Push(Map("name", "Create New Project", "path", "action:NewProject", "type", "action"))
            result.Push(Map("name", "Recent Projects", "path", "action:RecentProjects", "type", "action"))
            result.Push(Map("name", "Learning Center", "path", "action:LearningCenter", "type", "action"))
            result.Push(Map("name", "Project Settings", "path", "action:ProjectSettings", "type", "action"))
        case "Knowledge":
            result.Push(Map("name", "Add Knowledge", "path", "action:AddKnowledge", "type", "action"))
            result.Push(Map("name", "Search Knowledge", "path", "action:SearchKnowledge", "type", "action"))
            result.Push(Map("name", "Knowledge Test", "path", "action:TestKnowledge", "type", "action"))
            result.Push(Map("name", "Review a Knowledge Gap", "path", "action:ReviewGap", "type", "action"))
        case "Automation":
            result.Push(Map("name", "Syntax and Setup Guides", "path", "action:SyntaxGuides", "type", "action"))
            result.Push(Map("name", "Instruction Language", "path", "action:InstructionLanguage", "type", "action"))
            result.Push(Map("name", "Command Reference", "path", "action:InstructionReference", "type", "action"))
            result.Push(Map("name", "Find in Knowledge and Files", "path", "action:GlobalSearch", "type", "action"))
            result.Push(Map("name", "Google Search", "path", "action:GoogleSearch", "type", "action"))
            result.Push(Map("name", "Context Hotkeys / Hotstrings", "path", "action:ContextBindings", "type", "action"))
        case "Snips":
            result.Push(Map("name", "Browse / Add All Snips", "path", "action:Snips", "type", "action"))
            result.Push(Map("name", "Uniform Feature Structure", "path", "action:SnippetStructure", "type", "action"))
            result.Push(Map("name", "Suggestion IDE Applications", "path", "action:SnippetEditors", "type", "action"))
            result.Push(Map("name", "Toggle Four-Character Suggestions", "path", "action:ToggleSnippetSuggestions", "type", "action"))
            result.Push(Map("name", "--- Languages ---", "path", "", "type", "separator"))
            result.Push(Map("name", "C", "path", "action:SnipsC", "type", "action"))
            result.Push(Map("name", "C++", "path", "action:SnipsCpp", "type", "action"))
            result.Push(Map("name", "Python", "path", "action:SnipsPython", "type", "action"))
            result.Push(Map("name", "JavaScript", "path", "action:SnipsJavaScript", "type", "action"))
            result.Push(Map("name", "TypeScript", "path", "action:SnipsTypeScript", "type", "action"))
            result.Push(Map("name", "C#", "path", "action:SnipsCSharp", "type", "action"))
            result.Push(Map("name", "AutoHotkey v2", "path", "action:SnipsAhk2", "type", "action"))
        case "Admin":
            result.Push(Map("name", "Browse All SQLite Records", "path", "action:DatabaseBrowser", "type", "action"))
            result.Push(Map("name", "Google / Query History", "path", "action:QueryHistory", "type", "action"))
            result.Push(Map("name", "Error Log", "path", "action:ErrorRecords", "type", "action"))
            result.Push(Map("name", "Event Log", "path", "action:EventRecords", "type", "action"))
            result.Push(Map("name", "Activity / Idle Log", "path", "action:ActivityRecords", "type", "action"))
            result.Push(Map("name", "--- Configuration ---", "path", "", "type", "separator"))
            result.Push(Map("name", "Settings", "path", "action:Settings", "type", "action"))
            result.Push(Map("name", "Project Settings", "path", "action:ProjectSettings", "type", "action"))
            result.Push(Map("name", "Hotstrings", "path", "action:Hotstrings", "type", "action"))
            result.Push(Map("name", "Context Hotkeys / Hotstrings", "path", "action:ContextBindings", "type", "action"))
            result.Push(Map("name", "Snips Database / Editor", "path", "action:Snips", "type", "action"))
            result.Push(Map("name", "Batch Import Snips", "path", "action:SnippetBatchImport", "type", "action"))
            result.Push(Map("name", "Add Action Definition", "path", "action:AddAction", "type", "action"))
            result.Push(Map("name", "--- Maintenance ---", "path", "", "type", "separator"))
            result.Push(Map("name", "Rebuild Menus", "path", "action:RebuildMenu", "type", "action"))
            result.Push(Map("name", "Open Script Folder", "path", "action:OpenScriptFolder", "type", "action"))
            result.Push(Map("name", "Open Database Folder", "path", "action:OpenDatabaseFolder", "type", "action"))
            result.Push(Map("name", "Reload GlobalCoder", "path", "action:Reload", "type", "action"))
            result.Push(Map("name", "Exit GlobalCoder", "path", "action:Exit", "type", "action"))
        default:
            result.Push(Map("name", "Unknown menu: " . submenuName, "path", "", "type", "separator"))
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
        case "submenu":
            GC_MenuStack.Push(Map("items", GC_MenuItems, "index", GC_MenuIndex))
            GC_MenuItems := BuildSpecialSubmenu(StrReplace(item["path"], "submenu:", ""))
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
        case "SyntaxGuides":
            ShowSyntaxGuides()
        case "ContextBindings":
            ShowContextBindings()
        case "Snips":
            ShowSnippets()
        case "SnippetBatchImport":
            ShowSnippetBatchImporter()
        case "SnippetStructure":
            ShowSnippetStructure()
        case "SnippetEditors":
            ShowSnippetEditorContexts()
        case "ToggleSnippetSuggestions":
            SnippetSuggestionManager.Toggle()
        case "SnipsC":
            ShowSnippets("c")
        case "SnipsCpp":
            ShowSnippets("cpp")
        case "SnipsPython":
            ShowSnippets("python")
        case "SnipsJavaScript":
            ShowSnippets("javascript")
        case "SnipsTypeScript":
            ShowSnippets("typescript")
        case "SnipsCSharp":
            ShowSnippets("csharp")
        case "SnipsAhk2":
            ShowSnippets("ahk2")
        case "InstructionReference":
            ShowInstructionReference()
        case "NewProject":
            ShowNewProjectWizard()
        case "RecentProjects":
            ShowRecentProjects()
        case "LearningCenter":
            ShowLearningCenter()
        case "ProjectSettings":
            ShowProjectSettings()
        case "ReviewGap":
            ActivityMonitor.PromptForGap()
        case "GlobalSearch":
            FindInFiles()
        case "GoogleSearch":
            GoogleSearchWithLogging()
        case "DatabaseBrowser", "QueryHistory":
            ShowDatabaseBrowser("queries")
        case "ErrorRecords":
            ShowDatabaseBrowser("errors")
        case "EventRecords":
            ShowDatabaseBrowser("event_log")
        case "ActivityRecords":
            ShowDatabaseBrowser("activity_log")
        case "Settings":
            ShowSettingsGUI()
        case "Hotstrings":
            ShowHotstringsGUI()
        case "AddAction":
            ShowAddActionGUI()
        case "RebuildMenu":
            RebuildMenu()
        case "OpenScriptFolder":
            Run("explorer.exe " . QuoteArgument(A_ScriptDir))
        case "OpenDatabaseFolder":
            OpenDatabaseFolder()
        case "Reload":
            Reload()
        case "Exit":
            ExitApp()
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
    global GC_DB_PATH
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
    ShowDatabaseBrowser("queries")
}

ShowDatabaseBrowser(initialKey := "queries", *) {
    DatabaseBrowser(initialKey)
}

ShowSyntaxGuides(*) {
    SyntaxGuideBrowser()
}

ShowSnippets(initialLanguage := "", initialFeature := "", *) {
    SnippetBrowser(initialLanguage, initialFeature)
}

ShowSnippetBatchImporter(initialFile := "", *) {
    SnippetBatchImportWindow(initialFile)
}

ShowSnippetStructure(*) {
    SnippetStructureBrowser()
}

ShowSnippetEditorContexts(*) {
    SnippetEditorContextEditor()
}

ShowSnippetMenuHelp(*) {
    content := "Ctrl+Right Shift or Ctrl+M opens the native menu.`r`n`r`n"
        . "Use arrows to move through Snips > Language > Category > Feature.`r`n"
        . "Press Right to enter a submenu, Left to go back, and Enter on a snippet to insert it.`r`n"
        . "The insertion target is the editor window from which the menu was called.`r`n`r`n"
        . "Snippet management remains under Admin; it is never part of normal Snips navigation.`r`n"
        . "This preview is click-through, non-activating, and dismisses automatically."
    PassivePreviewWindow.Show("Snips Keyboard Navigation", content, 9000)
}

CaptureSnippetPlaceholder(languageCode, featureCode, *) {
    RememberSnippetMenuContext(languageCode, featureCode)
    GhostSnippetCaptureWindow.Show(languageCode, featureCode)
}

PreviewSnippetFeature(languageCode, featureCode, *) {
    RememberSnippetMenuContext(languageCode, featureCode)
    languageLabel := GlobalCoderDatabase.Scalar("SELECT label FROM snippet_languages WHERE code="
        . GlobalCoderDatabase.Q(languageCode) . " LIMIT 1;", languageCode)
    featureLabel := GlobalCoderDatabase.Scalar("SELECT label FROM snippet_feature_groups WHERE code="
        . GlobalCoderDatabase.Q(featureCode) . " LIMIT 1;", featureCode)
    rows := SnippetRepository.Search(languageCode, featureCode, "", 30)
    if rows.Length = 0 {
        content := "This language/feature slot exists in the uniform Snips tree, but no syntax has been recorded yet.`r`n`r`n"
            . "Add its first syntax later through Admin > Snip Database Editor."
    } else {
        content := ""
        for row in rows {
            content .= row["name"] . "  [" . row["trigger"] . "]`r`n"
            if row["description"] != ""
                content .= row["description"] . "`r`n"
            content .= row["body"] . "`r`n`r`n----------------------------------------`r`n`r`n"
        }
        content := RTrim(content, "`r`n- ")
    }
    PassivePreviewWindow.Show(languageLabel . " - " . featureLabel, content, 12000)
}

InsertSnippetById(id, *) {
    global GC_CallingWindowHwnd, GC_CallingControl
    row := SnippetRepository.ById(id)
    if !IsObject(row) {
        GUT_Display("Snips", "That snippet record no longer exists.", 2200)
        return
    }
    targetHwnd := GC_CallingWindowHwnd && WinExist("ahk_id " . GC_CallingWindowHwnd) ? GC_CallingWindowHwnd : WinExist("A")
    SnippetRepository.Insert(row, 0, targetHwnd, GC_CallingControl)
}

SnippetInputChar(inputHook, characters) {
    SnippetSuggestionManager.OnChar(characters)
}

SnippetInputKeyDown(inputHook, vk, sc) {
    SnippetSuggestionManager.OnKeyDown(vk, sc)
}

SnippetSuggestionContextTick(*) {
    SnippetSuggestionManager.ContextTick()
}

SnippetSuggestionIsActive(*) {
    return SnippetSuggestionManager.Visible && SnippetSuggestionManager.IsEditorActive()
}

SnippetAcceptSuggestion(*) {
    SnippetSuggestionManager.Accept()
}

SnippetMoveSuggestion(delta, *) {
    SnippetSuggestionManager.Move(delta)
}

SnippetDismissSuggestion(*) {
    SnippetSuggestionManager.Dismiss()
}

NativeMenuEnterLoop(wParam, lParam, msg, hwnd) {
    NativeMenuMonitor.Enter()
}

NativeMenuExitLoop(wParam, lParam, msg, hwnd) {
    NativeMenuMonitor.Exit()
}

NativeMenuSelect(wParam, lParam, msg, hwnd) {
    NativeMenuMonitor.Select(wParam, lParam)
}

NativeMenuPathActionIsActive(*) {
    global GC_NativeMenuActive, GC_HighlightedMenuContext
    return GC_NativeMenuActive && IsObject(GC_HighlightedMenuContext)
        && GC_HighlightedMenuContext.Has("path")
}

QueueNativeMenuPathAction(actionName, *) {
    global GC_HighlightedMenuContext
    if !IsObject(GC_HighlightedMenuContext) || !GC_HighlightedMenuContext.Has("path")
        return
    context := GC_HighlightedMenuContext.Clone()
    Send("{Esc}")
    SetTimer(PerformNativeMenuPathAction.Bind(actionName, context), -60)
}

PerformNativeMenuPathAction(actionName, context, *) {
    global GC_VSCodePath
    path := context["path"]
    directory := MenuContextDirectory(context)
    switch actionName {
        case "vscode":
            try Run(QuoteArgument(GC_VSCodePath) . " " . QuoteArgument(path), directory)
            catch as error
                PassivePreviewWindow.Show("VS Code", "Could not open VS Code:`r`n" . error.Message, 3500)
        case "new_file":
            CreateFileFromMenuContext(context)
        case "terminal":
            try Run("wt.exe -d " . QuoteArgument(directory), directory)
            catch
                Run(QuoteArgument(A_ComSpec), directory)
        case "explorer":
            if context["kind"] = "file"
                Run("explorer.exe /select," . QuoteArgument(path))
            else
                Run("explorer.exe " . QuoteArgument(path))
        case "copy_path":
            A_Clipboard := path
            PassivePreviewWindow.Show("Path Copied", path, 2200)
    }
}

MenuContextDirectory(context) {
    path := context["path"]
    if context["kind"] = "folder"
        return path
    SplitPath(path, , &directory)
    return directory
}

CreateFileFromMenuContext(context) {
    directory := MenuContextDirectory(context)
    if !DirExist(directory) {
        PassivePreviewWindow.Show("New File", "The target folder no longer exists:`r`n" . directory, 3200)
        return
    }
    result := InputBox("New file name in:`n" . directory, "New Project File", "w520 h150")
    if result.Result = "Cancel"
        return
    fileName := Trim(result.Value)
    if !IsSafeFileName(fileName) {
        MsgBox("Enter a valid file name without path separators.", "New Project File", 48)
        return
    }
    filePath := directory . "\" . fileName
    if FileExist(filePath) {
        MsgBox("That file already exists.", "New Project File", 48)
        return
    }
    file := FileOpen(filePath, "w", "UTF-8-RAW")
    if !IsObject(file) {
        MsgBox("Could not create the file.", "New Project File", 16)
        return
    }
    file.Close()
    GlobalCoderDatabase.UpsertContent(filePath, "")
    RebuildMenu(true)
    PassivePreviewWindow.Show("Project File Created", filePath, 2600)
}

ShowContextBindings(*) {
    ContextBindingEditor()
}

OpenDatabaseFolder(*) {
    SplitPath(GC_DB_PATH, , &databaseFolder)
    Run("explorer.exe " . QuoteArgument(databaseFolder))
}

ContextBindingMatches(contextType, contextValue, *) {
    try {
        switch contextType {
            case "exe":
                return StrLower(WinGetProcessName("A")) = StrLower(contextValue)
            case "not_exe":
                return StrLower(WinGetProcessName("A")) != StrLower(contextValue)
            case "title":
                return InStr(WinGetTitle("A"), contextValue, false) > 0
            case "class":
                return StrLower(WinGetClass("A")) = StrLower(contextValue)
            default:
                return true
        }
    } catch {
        return contextType = "not_exe" || contextType = "any"
    }
}

ExecuteContextBinding(binding, *) {
    actionType := binding["action_type"]
    actionValue := ContextBindingManager.ExpandTokens(binding["action_value"])
    switch actionType {
        case "send_text":
            SendText(actionValue)
        case "send_keys":
            Send(actionValue)
        case "run":
            Run(actionValue)
        case "function":
            switch actionValue {
                case "OpenScriptDirectoryCurrentExplorer":
                    OpenScriptDirectoryCurrentExplorer()
                case "OpenScriptDirectoryNewExplorer":
                    OpenScriptDirectoryNewExplorer()
                case "GoogleSearch":
                    GoogleSearchWithLogging()
                case "ShowMainMenu":
                    ShowMainMenu()
                case "ShowCustomMenu":
                    ShowCustomMenu()
                case "ShowSyntaxGuides":
                    ShowSyntaxGuides()
                case "ShowSnippets":
                    ShowSnippets()
                case "ShowContextBindings":
                    ShowContextBindings()
                default:
                    GUT_Display("Context Binding", "Unknown built-in action: " . actionValue, 3000)
            }
    }
}

OpenScriptDirectoryCurrentExplorer(*) {
    if !WinActive("ahk_exe explorer.exe") {
        OpenScriptDirectoryNewExplorer()
        return
    }
    Send("!d")
    Sleep(100)
    Send("^a")
    Sleep(60)
    SendText(A_ScriptDir)
    Sleep(60)
    Send("{Enter}")
}

OpenScriptDirectoryNewExplorer(*) {
    try Run("explorer.exe")
    if !WinWaitActive("ahk_exe explorer.exe", , 5) {
        Run("explorer.exe " . QuoteArgument(A_ScriptDir))
        return
    }
    OpenScriptDirectoryCurrentExplorer()
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
        ["Syntax and Setup Guides", ShowSyntaxGuides],
        ["Snips: Browse, Add, and Insert", ShowSnippets],
        ["Windows Instruction Language", ShowInstructionLanguageConsole],
        ["Global Search", FindInFiles],
        ["Context Hotkeys / Hotstrings", ShowContextBindings],
        ["Admin: Browse SQLite Records", ShowDatabaseBrowser],
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
    utf8Bytes := Buffer(byteCount, 0)
    StrPut(text, utf8Bytes, "UTF-8")
    encoded := ""
    Loop byteCount - 1 {
        byte := NumGet(utf8Bytes, A_Index - 1, "UChar")
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
    ; Highlight-sensitive actions inside the native project file tree.
    HotIf(NativeMenuPathActionIsActive)
    Hotkey("v", QueueNativeMenuPathAction.Bind("vscode"))
    Hotkey("n", QueueNativeMenuPathAction.Bind("new_file"))
    Hotkey("o", QueueNativeMenuPathAction.Bind("terminal"))
    Hotkey("e", QueueNativeMenuPathAction.Bind("explorer"))
    Hotkey("c", QueueNativeMenuPathAction.Bind("copy_path"))

    ; Non-focus-stealing Snips suggestions inside configured IDE/editor apps.
    HotIf(SnippetSuggestionIsActive)
    Hotkey("Tab", SnippetAcceptSuggestion)
    Hotkey("Up", SnippetMoveSuggestion.Bind(-1))
    Hotkey("Down", SnippetMoveSuggestion.Bind(1))
    Hotkey("Escape", SnippetDismissSuggestion)

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
    Hotkey("^m", ShowLastSnippetSectionMenu)
    Hotkey("^Space", GoogleSearchWithLogging)
    Hotkey("^!n", ShowNewProjectWizard)
    Hotkey("^!l", ShowLearningCenter)
    Hotkey("^!r", RebuildMenu)
    Hotkey("^!m", ShowLastSnippetSectionMenu)
    Hotkey("^!k", ShowKnowledgeSearch)
    Hotkey("^!a", ShowInstructionLanguageConsole)
}

; ============================================================================
; CONTEXT HOTKEYS
; ============================================================================

; Hotkeys are registered during initialization by RegisterGlobalHotkeys().
