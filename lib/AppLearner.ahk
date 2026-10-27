; ═══════════════════════════════════════════════════════════════════════════════
; AppLearner.ahk - Learn a program's whole interface into an object model,
;                  then drive it from a plain-text script (or from an LLM).
; ═══════════════════════════════════════════════════════════════════════════════
; WHAT THIS MODULE DOES
;
;   LEARN    Inspect any open window and harvest everything automatable in it:
;              - every control (ClassNN, position, visible text)
;              - the full MSAA/Acc accessibility tree (names, roles, paths,
;                keyboard shortcuts, click locations)
;              - the complete Win32 menu bar, recursed through every submenu
;                (item names, accelerators like "Ctrl+S", access keys for Alt
;                navigation, command ids, position order)
;              - optionally, menus that are NOT Win32 menus, by pressing the
;                menu open and reading the popup with OCR (Alt+OCR scan)
;            All of it is saved to a SQLite database (data\appmap.db) with both
;            absolute and window-relative (0-1) coordinates so it survives the
;            window moving or resizing.
;
;   MODEL    The saved rows ARE the object model: each row is one operable
;            thing (control / acc element / menu item) with every known way to
;            reach it (acc path, ClassNN, menu command id, alt-key sequence,
;            accelerator, coordinates, optional FindText pattern).
;
;   DRIVE    AppExec_Run(appId, script) executes a small automation language
;            (one command per line - see APPDSL_GUIDE below) against the model.
;            Each reference is resolved live in this order:
;              acc path -> ClassNN -> FindText pattern -> relative coordinates
;            Menu items are invoked by command id (WM_COMMAND) when known,
;            else by Alt-key navigation, else by clicking learned coordinates.
;
;   LLM      AppMap_BuildLLMPrompt(appId) emits a complete instruction sheet:
;            the DSL grammar plus the app's full catalog of menus, shortcuts
;            and elements. Give that to any LLM (e.g. a local Ollama model),
;            ask for a goal, and it answers with script lines this module can
;            execute directly. Ollama_GenerateScript() does the round trip
;            against a local Ollama server.
; ═══════════════════════════════════════════════════════════════════════════════

; ─── Module state ────────────────────────────────────────────────────────────
global g_AppMapDB := ""            ; TrackSQLite handle for data\appmap.db
global g_AppMapDBError := ""
global g_AppExecAbort := false     ; set true to stop a running script
global g_AppExecSwitchTo := 0      ; app id a 'use'/'learn' command switches the script to
global g_AppExecVars := Map()      ; $vars produced by ocr/… during a run

; UI control references (set by AppLearner_BuildTab)
global g_ALWinLV := "", g_ALElemLV := "", g_ALAppDD := "", g_ALFilterEdit := ""
global g_ALDemoDD := ""
global g_ALKindDD := "", g_ALScriptEdit := "", g_ALGoalEdit := ""
global g_ALOllamaUrl := "", g_ALOllamaModel := "", g_ALOllamaStatus := ""
global g_ALCbControls := "", g_ALCbAcc := "", g_ALCbMenus := "", g_ALCbAltOcr := ""
global g_ALCbVisuals := "", g_ALCbRandom := "", g_ALCbOcrScan := ""
global g_ALAppIds := []            ; row index in dropdown -> app id
global g_ALWinHwnds := []          ; row index in window LV -> hwnd

; ═══════════════════════════════════════════════════════════════════════════════
; LEARNING CONSOLE (live log window)
; ═══════════════════════════════════════════════════════════════════════════════
; A scrolling always-on-top console that narrates learning in real time: every
; control found, every Acc element, every menu item read by OCR, every FindText
; pattern captured and saved. Shown with NoActivate so it never steals focus
; from the window being learned.

global g_AppLogGui := "", g_AppLogEdit := ""

AppLog_Open() {
    global g_AppLogGui, g_AppLogEdit
    if (IsObject(g_AppLogGui)) {
        try {
            monitor := LearningValidation_Monitor()
            if !monitor
                return g_AppLogGui.Hide()
            MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
            g_AppLogGui.Show("NA x" . (left+12) . " y" . (top+50))
            return
        }
    }
    v := Gui("+Resize +AlwaysOnTop", "App Learner Console")
    ed := v.Add("Edit", "x5 y5 w690 h480 ReadOnly Multi VScroll -Wrap")
    ed.SetFont("s9", "Consolas")
    v.Add("Button", "x5 y492 w80 h24", "Clear").OnEvent("Click", (*) => (g_AppLogEdit.Value := ""))
    v.Add("Button", "x90 y492 w80 h24", "Copy All").OnEvent("Click", (*) => (A_Clipboard := g_AppLogEdit.Value))
    v.Add("Button", "x175 y492 w80 h24", "Hide").OnEvent("Click", (*) => v.Hide())
    v.OnEvent("Close", (*) => v.Hide())
    v.OnEvent("Size", AppLog_Resize)
    g_AppLogGui := v
    g_AppLogEdit := ed
    monitor := LearningValidation_Monitor()
    if monitor {
        MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
        v.Show("NA x" . (left+12) . " y" . (top+50) . " w" . Min(700,right-left-24) . " h" . Min(522,bottom-top-70))
    }
}

AppLog_Resize(g, minMax, w, h) {
    global g_AppLogEdit
    if (minMax = -1)
        return
    try g_AppLogEdit.Move(, , w - 10, h - 42)
}

; Append one timestamped line (EM_REPLACESEL: fast and auto-scrolls).
AppLog(text) {
    global g_AppLogGui, g_AppLogEdit
    if !IsObject(g_AppLogGui)
        AppLog_Open()
    line := FormatTime(A_Now, "HH:mm:ss") . "  " . text . "`r`n"
    try {
        hEd := g_AppLogEdit.Hwnd
        len := DllCall("SendMessageW", "Ptr", hEd, "UInt", 0x000E, "Ptr", 0, "Ptr", 0, "Ptr") ; WM_GETTEXTLENGTH
        DllCall("SendMessageW", "Ptr", hEd, "UInt", 0x00B1, "Ptr", len, "Ptr", len)           ; EM_SETSEL end
        DllCall("SendMessageW", "Ptr", hEd, "UInt", 0x00C2, "Ptr", 0, "WStr", line)           ; EM_REPLACESEL
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; DATABASE
; ═══════════════════════════════════════════════════════════════════════════════

AppMapDB() {
    global g_AppMapDB, g_AppMapDBError, DATA_DIR
    if IsObject(g_AppMapDB) && g_AppMapDB.IsOpen()
        return g_AppMapDB
    if !DirExist(DATA_DIR) {
        try DirCreate(DATA_DIR)
    }
    if !TrackSQLite.Available() {
        g_AppMapDBError := TrackSQLite.loadError
        return ""
    }
    try {
        path := FanData_DbAvailable("appmap", FanData_DbPath("appmap", DATA_DIR . "\appmap.db"))
        g_AppMapDB := TrackSQLite(path)
        AppMap_Schema(g_AppMapDB)
    } catch as err {
        g_AppMapDBError := err.Message
        g_AppMapDB := ""
        return ""
    }
    return g_AppMapDB
}

; NOTE: SQL is built line-by-line (not a continuation section) because AHK v2
; ends a continuation section at any line starting with ")" - which SQL loves.
AppMap_AppTable() => FanData_Routes().Has("unified_db") ? "appmap_app" : "app"

AppMap_Schema(db) {
    ; Text columns are nullable on purpose: the TrackSQLite wrapper binds an
    ; empty AHK string as SQL NULL, and NULL reads back as "" - symmetrical.
    sql := "CREATE TABLE IF NOT EXISTS " . AppMap_AppTable() . " ("
         . "id INTEGER PRIMARY KEY AUTOINCREMENT, "
         . "name TEXT, "
         . "exe TEXT DEFAULT '', "
         . "cls TEXT DEFAULT '', "
         . "title TEXT DEFAULT '', "
         . "win_x INTEGER DEFAULT 0, win_y INTEGER DEFAULT 0, "
         . "win_w INTEGER DEFAULT 0, win_h INTEGER DEFAULT 0, "
         . "learned_ts TEXT DEFAULT '', "
         . "notes TEXT DEFAULT '')"
    db.Exec(sql)

    ; kind: control | acc | menu | menuitem | menuitem-ocr
    ; acc_path: comma path for Acc.ElementFromPath   menu_path: File > Save As
    ; alt_keys: "!f s" Alt navigation   shortcut: accelerator like Ctrl+S
    ; cmd_id: Win32 menu command id (WM_COMMAND)
    sql := "CREATE TABLE IF NOT EXISTS ui_element ("
         . "id INTEGER PRIMARY KEY AUTOINCREMENT, "
         . "app_id INTEGER NOT NULL, "
         . "kind TEXT NOT NULL, "
         . "name TEXT DEFAULT '', "
         . "role TEXT DEFAULT '', "
         . "value TEXT DEFAULT '', "
         . "class_nn TEXT DEFAULT '', "
         . "acc_path TEXT DEFAULT '', "
         . "menu_path TEXT DEFAULT '', "
         . "alt_keys TEXT DEFAULT '', "
         . "shortcut TEXT DEFAULT '', "
         . "cmd_id INTEGER DEFAULT 0, "
         . "pos_order INTEGER DEFAULT 0, "
         . "depth INTEGER DEFAULT 0, "
         . "x INTEGER DEFAULT 0, y INTEGER DEFAULT 0, "
         . "w INTEGER DEFAULT 0, h INTEGER DEFAULT 0, "
         . "rel_x REAL DEFAULT 0, rel_y REAL DEFAULT 0, "
         . "rel_w REAL DEFAULT 0, rel_h REAL DEFAULT 0, "
         . "states TEXT DEFAULT '', "
         . "findtext TEXT DEFAULT '', "
         . "hits INTEGER DEFAULT 0)"
    db.Exec(sql)

    db.Exec("CREATE INDEX IF NOT EXISTS idx_uiel_app ON ui_element(app_id)")
    db.AddColumnIfMissing("ui_element", "source_title", "TEXT DEFAULT ''")
    db.Exec("CREATE INDEX IF NOT EXISTS idx_uiel_name ON ui_element(app_id, name)")
    db.Exec("CREATE TABLE IF NOT EXISTS app_setting ("
          . "key TEXT PRIMARY KEY, value TEXT NOT NULL DEFAULT '')")
}

AppMap_Setting(key, default := "") {
    db := AppMapDB()
    if !db
        return default
    v := db.Scalar("SELECT value FROM app_setting WHERE key=?", key)
    return (v = "" ? default : v)
}

AppMap_SetSetting(key, value) {
    db := AppMapDB()
    if db
        db.Run("INSERT INTO app_setting(key,value) VALUES(?,?) "
             . "ON CONFLICT(key) DO UPDATE SET value=excluded.value", key, value)
}

; ═══════════════════════════════════════════════════════════════════════════════
; LEARNING A WINDOW
; ═══════════════════════════════════════════════════════════════════════════════

; Learn everything about one window. opts is a Map with boolean keys:
;   controls, acc, menus, altocr, visuals
; Returns a Map: id, counts per source, or empty Map on failure.
AppMap_LearnWindow(hwnd, opts) {
    db := AppMapDB()
    if !db {
        ShowStatus("App map DB unavailable: " . g_AppMapDBError, "fail")
        return Map()
    }
    if !WinExist("ahk_id " . hwnd) {
        ShowStatus("Window is gone", "fail")
        return Map()
    }

    ; Bring the window to the front first: coordinates, the Alt menu walk and
    ; the FindText visual capture all need it visible and unobstructed.
    try {
        WinActivate("ahk_id " . hwnd)
        WinWaitActive("ahk_id " . hwnd, , 2)
        Sleep(120)
    }

    title := "", exe := "", cls := ""
    try title := WinGetTitle("ahk_id " . hwnd)
    try exe := WinGetProcessName("ahk_id " . hwnd)
    try cls := WinGetClass("ahk_id " . hwnd)
    wx := 0, wy := 0, ww := 0, wh := 0
    try WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . hwnd)
    if (ww <= 0 || wh <= 0) {
        ShowStatus("Window has no size (minimized?) - restore it first", "fail")
        return Map()
    }

    ; One app row per exe+class pair; relearning replaces its elements.
    appId := db.Scalar("SELECT id FROM " . AppMap_AppTable() . " WHERE exe=? AND cls=?", exe, cls)
    if IsInteger(appId) && Integer(appId) > 0 {
        appId := Integer(appId)
        db.Run("UPDATE " . AppMap_AppTable() . " SET name=?, title=?, win_x=?, win_y=?, win_w=?, win_h=?, learned_ts=? WHERE id=?"
             , title, title, wx, wy, ww, wh, AppMap_TS(), appId)
        db.Run("DELETE FROM ui_element WHERE app_id=?", appId)
    } else {
        db.Run("INSERT INTO " . AppMap_AppTable() . "(name, exe, cls, title, win_x, win_y, win_w, win_h, learned_ts) "
             . "VALUES(?,?,?,?,?,?,?,?,?)", title, exe, cls, title, wx, wy, ww, wh, AppMap_TS())
        appId := Integer(db.Scalar("SELECT last_insert_rowid()"))
    }

    AppLog("══════ Learning '" . TrackEllipsis(title, 50) . "'  (" . exe . " / " . cls . ") ══════")
    counts := Map("id", appId, "controls", 0, "acc", 0, "menus", 0, "altocr", 0
                , "visuals", 0, "ocrtext", 0)
    try db.Exec("BEGIN")
    try {
        if opts.Get("controls", true) {
            ShowStatus("Learning: scanning controls...", "wait")
            counts["controls"] := AppLearn_Controls(appId, hwnd, wx, wy, ww, wh)
            AppLog("controls: " . counts["controls"] . " saved")
        }
        if opts.Get("acc", true) {
            ShowStatus("Learning: walking accessibility tree...", "wait")
            counts["acc"] := AppLearn_AccTree(appId, hwnd, wx, wy, ww, wh)
            AppLog("acc tree: " . counts["acc"] . " elements saved")
        }
        if opts.Get("menus", true) {
            ShowStatus("Learning: reading Win32 menu bar...", "wait")
            counts["menus"] := AppLearn_Menus(appId, hwnd, wx, wy, ww, wh)
            AppLog("win32 menus: " . counts["menus"] . " items saved"
                 . (counts["menus"] = 0 ? " (no Win32 menu bar - Alt+OCR walk will cover it)" : " (with command ids)"))
        }
        if opts.Get("ocrtext", true) {
            ShowStatus("Learning: OCR-reading the window at face value...", "wait")
            counts["ocrtext"] := AppLearn_OcrText(appId, hwnd, wx, wy, ww, wh)
            AppLog("ocr face-value scan: " . counts["ocrtext"] . " text lines saved")
        }
    } catch as err {
        AppMap_LogError("AppMap_LearnWindow", err)
    }
    try db.Exec("COMMIT")

    ; Alt+OCR drives the live window (presses Alt, arrows through the menus),
    ; so it runs outside the transaction. When the Win32 menu walk already got
    ; the real menu (with command ids), the live walk would only duplicate it.
    if opts.Get("altocr", true) {
        if (counts["menus"] > 0) {
            ShowStatus("Skipping Alt+OCR menu walk - Win32 menus already learned with command ids", "info")
            AppLog("alt+ocr walk: skipped (the Win32 menu scan above already covers every menu item)")
        } else {
            ShowStatus("Learning: Alt+OCR menu walk (hands off the mouse/keyboard)...", "wait")
            try counts["altocr"] := AppLearn_MenusAlt(appId, hwnd, wx, wy, ww, wh
                                                   , opts.Get("visuals", true))
            catch as err
                AppMap_LogError("AppLearn_MenusAlt", err)
            AppLog("alt+ocr walk: " . counts["altocr"] . " menu items saved")
        }
    } else {
        AppLog("alt+ocr walk: disabled by checkbox for this run")
    }

    ; FindText visual capture: photograph every learned element's pixels so it
    ; can later be found again purely by its looks.
    if opts.Get("visuals", true) {
        ShowStatus("Learning: capturing FindText visual patterns...", "wait")
        try counts["visuals"] := AppLearn_CaptureVisuals(appId, hwnd)
        catch as err
            AppMap_LogError("AppLearn_CaptureVisuals", err)
        AppLog("findtext visuals: " . counts["visuals"] . " patterns captured and saved")
    }

    total := counts["controls"] + counts["acc"] + counts["menus"] + counts["altocr"] + counts["ocrtext"]
    ShowStatus("Learned '" . TrackEllipsis(title, 35) . "': " . total . " elements ("
             . counts["controls"] . " controls, " . counts["acc"] . " acc, "
             . counts["menus"] . " menu, " . counts["altocr"] . " alt-ocr, "
             . counts["ocrtext"] . " ocr-text) + " . counts["visuals"] . " visual patterns", "ok")
    return counts
}

AppMap_TS() => FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")

AppMap_LogError(where, err) {
    try TrackLogError(where, err)
    catch {
        ; tracking log unavailable - swallow, learning must not die on logging
    }
}

; ─── Source 1: classic controls (ClassNN) ────────────────────────────────────
AppLearn_Controls(appId, hwnd, wx, wy, ww, wh) {
    db := AppMapDB()
    n := 0
    ctrls := []
    try ctrls := WinGetControls("ahk_id " . hwnd)
    for i, nn in ctrls {
        cx := 0, cy := 0, cw := 0, ch := 0, text := ""
        try ControlGetPos(&cx, &cy, &cw, &ch, nn, "ahk_id " . hwnd)
        try text := ControlGetText(nn, "ahk_id " . hwnd)
        text := Trim(StrReplace(StrReplace(text, "`r"), "`n", " "))
        if (StrLen(text) > 80)
            text := SubStr(text, 1, 80)
        ; ControlGetPos is window-relative; store screen-absolute like the rest.
        ax := wx + cx, ay := wy + cy
        name := (text != "" ? text : nn)
        db.Run("INSERT INTO ui_element(app_id, kind, name, role, class_nn, pos_order, "
             . "x, y, w, h, rel_x, rel_y, rel_w, rel_h) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
             , appId, "control", name, "", nn, i
             , ax, ay, cw, ch
             , (ax - wx) / ww, (ay - wy) / wh, cw / ww, ch / wh)
        AppLog("  [control] " . nn . (text != "" ? "  '" . text . "'" : "") . "  @" . ax . "," . ay)
        LearningValidation_Event("App Learner", "observed", "Control: " . name, Map("x",ax,"y",ay,"w",cw,"h",ch),hwnd)
        n++
    }
    return n
}

; ─── Source 2: the MSAA / Acc accessibility tree ─────────────────────────────
AppLearn_AccTree(appId, hwnd, wx, wy, ww, wh) {
    root := ""
    try root := Acc.ElementFromHandle(hwnd)
    if !IsObject(root)
        return 0
    count := 0
    AppLearn_AccWalk(appId, root, "", 0, wx, wy, ww, wh, &count)
    return count
}

AppLearn_AccWalk(appId, el, path, depth, wx, wy, ww, wh, &count, maxDepth := 14, maxCount := 4000) {
    if (depth > maxDepth || count >= maxCount)
        return
    db := AppMapDB()

    name := "", role := "", shortcut := "", states := "", value := ""
    x := 0, y := 0, w := 0, h := 0
    try name := el.Name
    try role := el.RoleText
    try shortcut := el.KeyboardShortcut
    try states := el.StateText
    try value := el.Value
    try {
        loc := el.Location
        x := loc.x, y := loc.y, w := loc.w, h := loc.h
    }
    if !IsInteger(x)
        x := 0, y := 0, w := 0, h := 0

    ; Record anything a script could refer to: it has a name, or it is an
    ; interactive role even without one. Pure anonymous containers are skipped
    ; (but still recursed into).
    interactive := (role ~= "i)button|menu|item|edit|text|check|radio|combo|list|link|tab|slider|spin|tool|cell|outline")
    if (path != "" && (name != "" || interactive) && w > 0 && h > 0) {
        db.Run("INSERT INTO ui_element(app_id, kind, name, role, value, acc_path, shortcut, depth, "
             . "x, y, w, h, rel_x, rel_y, rel_w, rel_h, states) "
             . "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
             , appId, "acc", SubStr(name, 1, 120), role, SubStr(value, 1, 120), path, shortcut, depth
             , x, y, w, h
             , (x - wx) / ww, (y - wy) / wh, w / ww, h / wh
             , SubStr(states, 1, 100))
        AppLog("  [acc] " . role . "  '" . TrackEllipsis(name, 40) . "'"
             . (shortcut != "" ? "  [key: " . shortcut . "]" : "") . "  @" . x . "," . y)
        count++
        LearningValidation_Event("App Learner", "observed", "Accessibility: " . name . " [" . role . "]", Map("x",x,"y",y,"w",w,"h",h))
    }

    children := ""
    try children := el.Children
    if IsObject(children) {
        for i, ch in children {
            AppLearn_AccWalk(appId, ch, (path = "" ? String(i) : path . "," . i)
                           , depth + 1, wx, wy, ww, wh, &count, maxDepth, maxCount)
            if (count >= maxCount)
                break
        }
    }
}

; ─── Source 3: the Win32 menu bar, fully recursed ────────────────────────────
AppLearn_Menus(appId, hwnd, wx, wy, ww, wh) {
    hMenu := DllCall("GetMenu", "Ptr", hwnd, "Ptr")
    if !hMenu
        return 0
    count := 0
    AppLearn_MenuWalk(appId, hwnd, hMenu, "", "", 0, wx, wy, ww, wh, &count)
    return count
}

AppLearn_MenuWalk(appId, hwnd, hMenu, path, altSeq, depth, wx, wy, ww, wh, &count, maxDepth := 6) {
    if (depth > maxDepth)
        return
    db := AppMapDB()
    n := DllCall("GetMenuItemCount", "Ptr", hMenu, "Int")
    if (n <= 0)
        return
    ; pos_order counts only VISIBLE items (separators skipped), because that is
    ; what arrow-key navigation steps through: item with pos_order j is reached
    ; by pressing Down j times from a freshly opened menu.
    visOrder := 0
    Loop n {
        i := A_Index - 1
        buf := Buffer(1024, 0)
        DllCall("GetMenuString", "Ptr", hMenu, "UInt", i, "Ptr", buf, "Int", 500, "UInt", 0x400) ; MF_BYPOSITION
        raw := StrGet(buf, "UTF-16")
        if (raw = "")            ; separator
            continue
        visOrder++

        ; "Save &As...`tCtrl+Shift+S" -> label + accelerator + access key
        accel := "", label := raw
        if (p := InStr(raw, "`t")) {
            accel := SubStr(raw, p + 1)
            label := SubStr(raw, 1, p - 1)
        }
        accessKey := ""
        if RegExMatch(label, "&(\w)", &m)
            accessKey := StrLower(m[1])
        clean := StrReplace(label, "&")

        newPath := (path = "" ? clean : path . " > " . clean)
        if (depth = 0)
            newAlt := (accessKey != "" ? "!" . accessKey : "")
        else
            newAlt := (altSeq != "" && accessKey != "" ? altSeq . " " . accessKey : "")

        hSub := DllCall("GetSubMenu", "Ptr", hMenu, "Int", i, "Ptr")
        cmdId := DllCall("GetMenuItemID", "Ptr", hMenu, "Int", i, "Int")
        if (cmdId = -1 || hSub)
            cmdId := 0

        ; Top-level items have an on-screen rectangle worth keeping.
        mx := 0, my := 0, mw := 0, mh := 0
        if (depth = 0) {
            rect := Buffer(16, 0)
            if DllCall("GetMenuItemRect", "Ptr", hwnd, "Ptr", hMenu, "UInt", i, "Ptr", rect) {
                mx := NumGet(rect, 0, "Int"), my := NumGet(rect, 4, "Int")
                mw := NumGet(rect, 8, "Int") - mx, mh := NumGet(rect, 12, "Int") - my
            }
        }

        db.Run("INSERT INTO ui_element(app_id, kind, name, menu_path, alt_keys, shortcut, cmd_id, "
             . "pos_order, depth, x, y, w, h, rel_x, rel_y, rel_w, rel_h) "
             . "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
             , appId, (hSub ? "menu" : "menuitem"), clean, newPath, newAlt, accel, cmdId
             , visOrder, depth
             , mx, my, mw, mh
             , (mw > 0 ? (mx - wx) / ww : 0), (mh > 0 ? (my - wy) / wh : 0)
             , (mw > 0 ? mw / ww : 0), (mh > 0 ? mh / wh : 0))
        AppLog("  [menu] " . newPath . (accel != "" ? "  [" . accel . "]" : "")
             . (cmdId > 0 ? "  (cmd " . cmdId . ")" : "")
             . (newAlt != "" ? "  (alt: " . newAlt . ")" : ""))
        count++

        if hSub
            AppLearn_MenuWalk(appId, hwnd, hSub, newPath, newAlt, depth + 1
                            , wx, wy, ww, wh, &count, maxDepth)
    }
}

; ─── Source 4: the window read at face value with OCR ────────────────────────
; Exactly what the Live OCR tab does, folded into learning: every line of text
; the window shows on screen is stored as a clickable element (kind "ocr") with
; its coordinates. This catches labels, buttons and values that no API exposes,
; so a script can say  click Total amount  purely from what is visible.
AppLearn_OcrText(appId, hwnd, wx, wy, ww, wh, maxLines := 350) {
    db := AppMapDB()
    res := ""
    try res := OCR.FromWindow("ahk_id " . hwnd)
    if !IsObject(res)
        return 0
    count := 0
    seen := Map()
    for i, line in res.Lines {
        text := Trim(line.Text)
        if (StrLen(text) < 2)
            continue
        if (StrLen(text) > 80)
            text := SubStr(text, 1, 80)
        ; store each distinct text once - the first (topmost) occurrence
        key := StrLower(text)
        if seen.Has(key)
            continue
        seen[key] := true
        lw := line.Words[1]
        lx := lw.x, ly := lw.y, lww := lw.w, lhh := lw.h
        try {
            br := OCR.WordsBoundingRect(line.Words*)
            lx := br.x, ly := br.y, lww := br.w, lhh := br.h
        }
        db.Run("INSERT INTO ui_element(app_id, kind, name, pos_order, "
             . "x, y, w, h, rel_x, rel_y, rel_w, rel_h) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)"
             , appId, "ocr", text, i
             , lx, ly, lww, lhh
             , (lx - wx) / ww, (ly - wy) / wh, lww / ww, lhh / wh)
        AppLog("  [ocr] '" . TrackEllipsis(text, 50) . "'  @" . lx . "," . ly)
        count++
        if (count >= maxLines)
            break
    }
    return count
}

; ─── Source 5: live menus via Alt + arrow keys + OCR / FindText ──────────────
; For apps whose menus are not Win32 menus (custom-drawn, XAML, Qt, Electron):
;   1. OCR the menu-bar strip to find the top items and their positions.
;   2. Press Alt, then {Down} to drop the first menu.
;   3. Read the open dropdown: preferably the real popup window (class #32768),
;      otherwise an OCR diff of the area under the bar against a baseline.
;   4. OCR every item line going down - name, accelerator, position order -
;      and photograph each row with FindText while it is visible.
;   5. {Right} advances to the next top menu with its dropdown open; repeat
;      until every bar item is walked (or the content wraps around).
AppLearn_MenusAlt(appId, hwnd, wx, wy, ww, wh, captureFT := true) {
    db := AppMapDB()
    if !WinExist("ahk_id " . hwnd)
        return 0
    WinActivate("ahk_id " . hwnd)
    if !WinWaitActive("ahk_id " . hwnd, , 2)
        return 0
    Sleep(200)

    ; ── 1. Read the menu-bar strip (below the title bar) ─────────────────────
    ; The strip also catches title-bar text, tab titles and stray document
    ; text, so: keep only clean menu-title-looking words (letters only, short),
    ; cluster them into horizontal rows, and take the row with the most words -
    ; that row IS the menu bar ("File Edit View ...").
    barY := wy + 20, barH := 90
    barWords := []
    try {
        bar := OCR.FromRect(wx, barY, ww, barH)
        cand := []
        for word in bar.Words {
            label := Trim(word.Text)
            ; letters only (any language), 2-14 chars: rejects "3.tx",
            ; "fggf.txt", "v8.ahk -", timestamps and other bar noise
            if (StrLen(label) < 2 || StrLen(label) > 14)
                continue
            if !RegExMatch(label, "^[\p{L}&]+$")
                continue
            cand.Push(Map("text", label, "x", word.x, "y", word.y, "w", word.w, "h", word.h))
        }
        ; cluster by row (same y within 8px), pick the row with the most words;
        ; on a tie prefer the lower row (menus sit under the title bar)
        rows := []
        for c in cand {
            placed := false
            for r in rows {
                if (Abs(r["y"] - c["y"]) <= 8) {
                    r["words"].Push(c)
                    placed := true
                    break
                }
            }
            if !placed
                rows.Push(Map("y", c["y"], "words", [c]))
        }
        best := ""
        for r in rows {
            if (best = "" || r["words"].Length > best["words"].Length
                || (r["words"].Length = best["words"].Length && r["y"] > best["y"]))
                best := r
        }
        if IsObject(best) {
            barWords := best["words"]
            ; left-to-right = menu order
            n := barWords.Length
            Loop n - 1 {
                i := A_Index
                Loop n - i {
                    j := A_Index
                    if (barWords[j]["x"] > barWords[j + 1]["x"]) {
                        tmp := barWords[j], barWords[j] := barWords[j + 1], barWords[j + 1] := tmp
                    }
                }
            }
            while (barWords.Length > 10)
                barWords.Pop()
        }
    }
    maxMenus := barWords.Length ? barWords.Length : 6

    ; Full-area baseline for the OCR-diff fallback (menus are all closed now).
    popX := wx + 2, popY := wy + 55
    popW := Min(ww - 4, 700), popH := Min(wh - 70, 650)
    baseline := ""
    try baseline := OCR.FromRect(popX, popY, popW, popH).Text

    ; ── 2-5. Walk the bar with the keyboard ──────────────────────────────────
    count := 0
    firstMenuSig := ""
    Send("{Alt}")
    Sleep(250)
    Loop maxMenus {
        mi := A_Index
        if (mi = 1)
            Send("{Down}")           ; drop the first menu
        else
            Send("{Right}")          ; next top menu, dropdown stays open
        Sleep(320)

        ; Where is the dropdown? Win32 menu popups are class #32768 windows;
        ; WinUI/XAML apps (new Notepad, Paint...) use Xaml_WindowedPopupClass.
        px := popX, py := popY, pw := popW, ph := popH
        usedPopup := false
        for , popCls in ["#32768", "Xaml_WindowedPopupClass"] {
            popupHwnd := 0
            try popupHwnd := WinExist("ahk_class " . popCls)
            if popupHwnd {
                try {
                    WinGetPos(&tx, &ty, &tw, &th, "ahk_id " . popupHwnd)
                    if (tw > 30 && th > 30) {
                        px := tx, py := ty, pw := tw, ph := th
                        usedPopup := true
                        break
                    }
                }
            }
        }
        ; No popup window found: OCR just the column under this menu's bar
        ; word instead of the whole client area, so document text far from the
        ; dropdown cannot pollute the read.
        if (!usedPopup && barWords.Length >= mi) {
            bw := barWords[mi]
            px := Max(wx, bw["x"] - 50), py := bw["y"] + bw["h"] + 2
            pw := Min(420, wx + ww - px), ph := Min(600, wy + wh - py)
        }

        pop := ""
        try pop := OCR.FromRect(px, py, pw, ph)
        if !IsObject(pop)
            continue

        ; Signature to detect wrap-around (we came back to the first menu).
        sig := SubStr(pop.Text, 1, 160)
        if (mi = 1)
            firstMenuSig := sig
        else if (sig != "" && sig = firstMenuSig)
            break

        rootLabel := (barWords.Length >= mi ? barWords[mi]["text"] : "Menu" . mi)

        ; Store the top item itself (with its bar position when OCR found it).
        if (barWords.Length >= mi) {
            bw := barWords[mi]
            db.Run("INSERT INTO ui_element(app_id, kind, name, menu_path, pos_order, depth, "
                 . "x, y, w, h, rel_x, rel_y, rel_w, rel_h) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
                 , appId, "menu", rootLabel, rootLabel, mi, 0
                 , bw["x"], bw["y"], bw["w"], bw["h"]
                 , (bw["x"] - wx) / ww, (bw["y"] - wy) / wh, bw["w"] / ww, bw["h"] / wh)
        } else {
            db.Run("INSERT INTO ui_element(app_id, kind, name, menu_path, pos_order, depth) "
                 . "VALUES(?,?,?,?,?,?)", appId, "menu", rootLabel, rootLabel, mi, 0)
        }
        count++

        ; ── 4. Every item line going down ────────────────────────────────────
        ; Screenshot the whole open popup ONCE into FindText's buffer; each
        ; item row is then grabbed from those cached bits (ScreenShot=0).
        ; (A ScreenShot=1 grab only blits its own little rect, so grabbing
        ; row-by-row fresh would read black pixels for every row but the first.)
        if captureFT {
            try {
                sx := px, sy := py, sw := pw, sh := ph
                FindText().GetBitsFromScreen(&sx, &sy, &sw, &sh, 1)
            }
        }
        itemOrder := 0
        shot := 0     ; every row grab reuses the popup screenshot above
        for line in pop.Lines {
            itemText := Trim(line.Text)
            if (itemText = "" || StrLen(itemText) < 2)
                continue
            ; In the diff fallback, drop text that was there before the menu
            ; opened. Prefix match (12 chars) because line crops shift between
            ; the two OCR passes.
            if (!usedPopup && baseline != "" && InStr(baseline, SubStr(itemText, 1, 12)))
                continue
            ; Accelerator column often OCRs onto the same line: "Save Ctrl+S"
            accel := ""
            if RegExMatch(itemText, "i)\s((?:Ctrl|Alt|Shift|Win)[\+\w\s]*\+\s*\S+)$", &am) {
                accel := Trim(am[1])
                itemText := Trim(SubStr(itemText, 1, StrLen(itemText) - StrLen(am[0])))
            }
            if (itemText = "" || itemText = rootLabel)
                continue
            itemOrder++
            lw := line.Words[1]
            lx := lw.x, ly := lw.y, lww := lw.w, lhh := lw.h
            try {
                br := OCR.WordsBoundingRect(line.Words*)
                lx := br.x, ly := br.y, lww := br.w, lhh := br.h
            }
            ; Photograph the row while the menu is open - this is the only
            ; moment a dropdown item is on screen.
            ; "**50" = FindText's edge-detect mode: robust across themes and
            ; background colors, and it avoids the library's broken
            ; auto-threshold path (a v1 leftover that indexes an array at 0).
            ftPat := ""
            if (captureFT && lww >= 8 && lhh >= 8 && lww <= 420 && lhh <= 60) {
                try {
                    ftPat := FindText().GetTextFromScreen(lx, ly, lx + lww - 1, ly + lhh - 1, "**50", shot)
                    if (StrLen(ftPat) < 40 || StrLen(ftPat) > 12000)
                        ftPat := ""   ; blank or oversized capture
                }
            }
            db.Run("INSERT INTO ui_element(app_id, kind, name, menu_path, shortcut, pos_order, depth, "
                 . "x, y, w, h, rel_x, rel_y, rel_w, rel_h, findtext) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
                 , appId, "menuitem-ocr", itemText, rootLabel . " > " . itemText, accel, itemOrder, 1
                 , lx, ly, lww, lhh
                 , (lx - wx) / ww, (ly - wy) / wh, lww / ww, lhh / wh, ftPat)
            AppLog("  [alt-ocr] " . rootLabel . " > " . itemText
                 . (accel != "" ? "  [" . accel . "]" : "")
                 . (ftPat != "" ? "  (findtext " . StrLen(ftPat) . " chars)" : ""))
            count++
            if (itemOrder >= 40)
                break
        }
        ShowStatus("Alt+OCR: read menu " . mi . " '" . rootLabel . "' (" . itemOrder . " items)", "wait")
    }

    ; Close whatever is still open.
    Send("{Esc}")
    Sleep(120)
    Send("{Esc}")
    Sleep(120)
    return count
}

; ─── Source 6: FindText visual capture of every learned element ──────────────
; Photographs each element's on-screen pixels into a FindText binary pattern,
; stored under the element's name. AppMap_Locate then finds elements purely by
; their looks - surviving window moves, and working even when Acc/ClassNN fail.
AppLearn_CaptureVisuals(appId, hwnd, maxPatterns := 300) {
    db := AppMapDB()
    if (!db || !WinExist("ahk_id " . hwnd))
        return 0
    WinActivate("ahk_id " . hwnd)
    if !WinWaitActive("ahk_id " . hwnd, , 2)
        return 0
    Sleep(150)

    ; Only elements that are actually on screen right now, at a size FindText
    ; handles well: buttons, inputs, checkboxes, menu-bar items, scrollbar
    ; arrows, small panels. Giant panels make megabyte patterns - skipped, and
    ; so are acc rows recorded as invisible (hidden find bars, collapsed panes:
    ; photographing those would capture whatever background sits there).
    els := db.Query("SELECT id, kind, name, class_nn, x, y, w, h FROM ui_element "
                  . "WHERE app_id=? AND (findtext IS NULL OR findtext='') "
                  . "AND kind IN ('control','acc','menu','ocr') "
                  . "AND (states IS NULL OR states NOT LIKE '%invisible%') "
                  . "AND w BETWEEN 8 AND 360 AND h BETWEEN 8 AND 120 "
                  . "ORDER BY (CASE WHEN name IS NULL OR name='' THEN 1 ELSE 0 END), id "
                  . "LIMIT ?", appId, maxPatterns * 2)

    ; Element rects must sit inside the live window to be photographable.
    wx := 0, wy := 0, ww := 0, wh := 0
    try WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . hwnd)

    ; Screenshot the whole screen ONCE into FindText's buffer, then grab every
    ; element's pattern from those cached bits. (A ScreenShot=1 grab only blits
    ; its own rect, so per-element fresh grabs would read black for all but
    ; the first element.)
    try {
        sx := 0, sy := 0, sw := A_ScreenWidth, sh := A_ScreenHeight
        FindText().GetBitsFromScreen(&sx, &sy, &sw, &sh, 1)
    } catch as err {
        AppMap_LogError("AppLearn_CaptureVisuals(screenshot)", err)
        return 0
    }

    captured := 0
    seenRects := Map()
    shot := 0      ; every grab reuses the full-screen shot above
    for e in els {
        if (captured >= maxPatterns)
            break
        x := e["x"], y := e["y"], w := e["w"], h := e["h"]
        ; on-screen sanity, and inside the live window
        if (x < 0 || y < 0 || x + w > A_ScreenWidth || y + h > A_ScreenHeight)
            continue
        if (ww > 0 && (x < wx || y < wy || x + w > wx + ww || y + h > wy + wh))
            continue
        ; hidden classic controls (collapsed find bars etc.) have coordinates
        ; but no pixels - skip them
        if (e["kind"] = "control" && e["class_nn"] != "") {
            vis := 1
            try vis := ControlGetVisible(e["class_nn"], "ahk_id " . hwnd)
            if !vis
                continue
        }
        ; controls and acc rows for the same widget share a rect - capture once
        rectKey := x . "," . y . "," . w . "," . h
        if seenRects.Has(rectKey)
            continue
        seenRects[rectKey] := true

        ; "**50" edge-detect mode: theme-proof, and dodges the library's broken
        ; auto-threshold path (v1 leftover indexing an array at 0).
        pat := ""
        try pat := FindText().GetTextFromScreen(x, y, x + w - 1, y + h - 1, "**50", shot)
        ; under ~40 chars the pattern is a blank/uniform rectangle - useless
        if (pat = "" || StrLen(pat) < 40 || StrLen(pat) > 12000)
            continue
        db.Run("UPDATE ui_element SET findtext=? WHERE id=?", pat, e["id"])
        AppLog("  [findtext] saved for '" . TrackEllipsis(e["name"], 40) . "' (" . e["kind"]
             . ", " . StrLen(pat) . " chars) @" . x . "," . y)
        captured++
    }
    return captured
}

; ═══════════════════════════════════════════════════════════════════════════════
; QUERYING THE MODEL
; ═══════════════════════════════════════════════════════════════════════════════

AppMap_Apps() {
    db := AppMapDB()
    if !db
        return []
    return db.Query("SELECT a.*, (SELECT COUNT(*) FROM ui_element e WHERE e.app_id=a.id) AS elements "
                  . "FROM " . AppMap_AppTable() . " a ORDER BY a.learned_ts DESC")
}

AppMap_AppRow(appId) {
    db := AppMapDB()
    if !db
        return Map()
    return db.QueryRow("SELECT * FROM " . AppMap_AppTable() . " WHERE id=?", appId)
}

AppMap_Elements(appId, kind := "", filter := "") {
    db := AppMapDB()
    if !db
        return []
    sql := "SELECT * FROM ui_element WHERE app_id=?"
    params := [appId]
    if (kind != "" && kind != "(all)") {
        sql .= " AND kind=?"
        params.Push(kind)
    }
    if (filter != "") {
        sql .= " AND (name LIKE ? OR menu_path LIKE ? OR class_nn LIKE ? OR shortcut LIKE ?)"
        like := "%" . filter . "%"
        params.Push(like), params.Push(like), params.Push(like), params.Push(like)
    }
    sql .= " ORDER BY kind, menu_path, depth, pos_order, id LIMIT 3000"
    return db.Query(sql, params*)
}

AppMap_DeleteApp(appId) {
    db := AppMapDB()
    if !db
        return
    db.Run("DELETE FROM ui_element WHERE app_id=?", appId)
    db.Run("DELETE FROM " . AppMap_AppTable() . " WHERE id=?", appId)
}

; Find one element for a script reference: "#123" (id) or a name / menu path.
AppMap_Resolve(appId, ref) {
    db := AppMapDB()
    if !db
        return Map()
    ref := Trim(ref)
    if (ref = "")
        return Map()
    if RegExMatch(ref, "^#(\d+)$", &m)
        return db.QueryRow("SELECT * FROM ui_element WHERE id=? AND app_id=?", Integer(m[1]), appId)
    ; exact name, preferring interactive kinds; then exact menu path; then fuzzy
    row := db.QueryRow("SELECT * FROM ui_element WHERE app_id=? AND name=? COLLATE NOCASE "
                     . "ORDER BY CASE kind WHEN 'menuitem' THEN 0 WHEN 'control' THEN 1 "
                     . "WHEN 'acc' THEN 2 ELSE 3 END, id LIMIT 1", appId, ref)
    if row.Count
        return row
    row := db.QueryRow("SELECT * FROM ui_element WHERE app_id=? AND menu_path=? COLLATE NOCASE LIMIT 1"
                     , appId, ref)
    if row.Count
        return row
    return db.QueryRow("SELECT * FROM ui_element WHERE app_id=? AND (name LIKE ? OR menu_path LIKE ?) "
                     . "ORDER BY LENGTH(name), id LIMIT 1", appId, "%" . ref . "%", "%" . ref . "%")
}

; ═══════════════════════════════════════════════════════════════════════════════
; LIVE RESOLUTION (model row -> screen location, right now)
; ═══════════════════════════════════════════════════════════════════════════════

; Live top-level window of a learned app.
AppMap_LiveHwnd(app) {
    if (!app.Count || app["exe"] = "")
        return 0
    hwnd := 0
    try hwnd := WinExist("ahk_exe " . app["exe"] . " ahk_class " . app["cls"])
    if !hwnd
        try hwnd := WinExist("ahk_exe " . app["exe"])
    return hwnd
}

; Locate an element on the current screen. Resolution order:
;   1. live Acc path lookup   2. live ClassNN lookup
;   3. FindText pattern       4. stored relative coords projected on the window
; Returns Map(x,y,w,h,cx,cy,method) or empty Map.
AppMap_Locate(app, el) {
    result := Map()
    if !el.Count
        return result
    hwnd := AppMap_LiveHwnd(app)
    if el["kind"] = "auto-acc" {
        hwnd := 0
        for candidate in WinGetList("ahk_exe " . app["exe"] . " ahk_class " . app["cls"])
            if WinGetTitle("ahk_id " . candidate) = el.Get("source_title", "") {
                hwnd := candidate
                break
            }
        if !hwnd
            return Map()
    }

    ; 1. Acc path (strongest: tracks the real element wherever it is now)
    if (hwnd && el["acc_path"] != "") {
        try {
            live := Acc.ElementFromPath(el["acc_path"], hwnd)
            loc := live.Location
            if el["kind"] = "auto-acc" && (SubStr(live.Name,1,120) != el["name"] || live.RoleText != el["role"])
                return Map()
            if (loc.w > 0 && loc.h > 0)
                return Map("x", loc.x, "y", loc.y, "w", loc.w, "h", loc.h
                         , "cx", loc.x + loc.w // 2, "cy", loc.y + loc.h // 2, "method", "acc")
        }
    }

    if el["kind"] = "auto-acc"
        return Map()

    ; 2. ClassNN
    if (hwnd && el["class_nn"] != "") {
        try {
            ControlGetPos(&cx, &cy, &cw, &ch, el["class_nn"], "ahk_id " . hwnd)
            WinGetPos(&wx, &wy, , , "ahk_id " . hwnd)
            if (cw > 0 && ch > 0)
                return Map("x", wx + cx, "y", wy + cy, "w", cw, "h", ch
                         , "cx", wx + cx + cw // 2, "cy", wy + cy + ch // 2, "method", "classnn")
        }
    }

    ; 3. FindText visual pattern
    if (el["findtext"] != "") {
        try {
            ok := FindText(&fx := 0, &fy := 0, 0, 0, A_ScreenWidth, A_ScreenHeight
                         , 0.15, 0.12, el["findtext"])
            if (IsObject(ok) && ok.Length) {
                mres := ok[1]
                return Map("x", mres.x, "y", mres.y, "w", mres.w, "h", mres.h
                         , "cx", mres.x + mres.w // 2, "cy", mres.y + mres.h // 2, "method", "findtext")
            }
        }
    }

    ; 4. Relative coordinates projected onto the live window
    if (hwnd && el["rel_w"] > 0) {
        try {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . hwnd)
            ex := wx + Integer(Round(Float(el["rel_x"]) * ww))
            ey := wy + Integer(Round(Float(el["rel_y"]) * wh))
            ew := Integer(Round(Float(el["rel_w"]) * ww))
            eh := Integer(Round(Float(el["rel_h"]) * wh))
            return Map("x", ex, "y", ey, "w", ew, "h", eh
                     , "cx", ex + ew // 2, "cy", ey + eh // 2, "method", "relative")
        }
    }

    ; Last resort: the absolute coordinates from learn time.
    if (el["w"] > 0)
        return Map("x", el["x"], "y", el["y"], "w", el["w"], "h", el["h"]
                 , "cx", el["x"] + el["w"] // 2, "cy", el["y"] + el["h"] // 2, "method", "absolute")
    return result
}

; ═══════════════════════════════════════════════════════════════════════════════
; ACTING ON THE MODEL
; ═══════════════════════════════════════════════════════════════════════════════

; All learned coordinates are SCREEN coordinates. Click through this helper so
; the pathway works regardless of the ambient CoordMode (the main app sets
; Screen globally, but the library must not depend on that).
AppAct_ClickScreen(x, y, button := "Left", clicks := 1) {
    CoordMode("Mouse", "Screen")
    Click(x, y, button, clicks)
}

AppAct_MoveScreen(x, y) {
    CoordMode("Mouse", "Screen")
    MouseMove(x, y, 2)
}

AppAct_Focus(app) {
    hwnd := AppMap_LiveHwnd(app)
    if !hwnd {
        ShowStatus("App window not found: " . app["exe"], "fail")
        return false
    }
    WinActivate("ahk_id " . hwnd)
    return WinWaitActive("ahk_id " . hwnd, , 3) != 0
}

AppAct_Click(app, el, button := "Left", clicks := 1) {
    loc := AppMap_Locate(app, el)
    if !loc.Count {
        ShowStatus("Cannot locate '" . el["name"] . "' on screen", "fail")
        return false
    }
    try HighlightRegion(loc["x"], loc["y"], loc["w"], loc["h"], 350, "highlight", el["name"])
    AppAct_ClickScreen(loc["cx"], loc["cy"], button, clicks)
    AppMapDB().Run("UPDATE ui_element SET hits=hits+1 WHERE id=?", el["id"])
    return true
}

; ─── Menu invocation: four interchangeable pathways ──────────────────────────
; The same menu item can be reached several ways, and each is implemented as
; its own method so scripts can force one, and so "randomize pathways" can vary
; how the program is driven from run to run:
;
;   cmd        post WM_COMMAND with the learned command id (instant, invisible)
;   altletter  Alt, then the access letter (Alt+F for File), then the item's
;              access letters when known, else Down x N + Enter
;   keys       pure arrow navigation: Alt, Right x(menu-1), Down opens,
;              Down x(item-1), Enter - driven entirely by learned positions
;   mouse      click the top menu open, then click the item (located by its
;              stored coords / FindText pattern, or OCR of the open dropdown)

; Which pathways can reach this element right now?
AppAct_MenuMethods(app, el) {
    m := []
    hasPath := (el["menu_path"] != "" && InStr(el["menu_path"], " > "))
    if (el["cmd_id"] > 0)
        m.Push("cmd")
    if (el["alt_keys"] != "" || (hasPath && el["pos_order"] > 0 && el["depth"] = 1))
        m.Push("altletter")
    if (hasPath && el["pos_order"] > 0 && el["depth"] = 1
        && AppAct_TopMenuOrder(app, el) > 0)
        m.Push("keys")
    if hasPath
        m.Push("mouse")
    return m
}

; Visible position of the element's top-level menu in the bar (0 if unknown).
AppAct_TopMenuOrder(app, el) {
    if (el["menu_path"] = "" || !InStr(el["menu_path"], " > "))
        return 0
    top := Trim(StrSplit(el["menu_path"], " > ")[1])
    db := AppMapDB()
    mi := db.Scalar("SELECT pos_order FROM ui_element WHERE app_id=? AND kind='menu' "
                  . "AND depth=0 AND name=? COLLATE NOCASE LIMIT 1", app["id"], top)
    return (IsInteger(mi) && Integer(mi) > 0) ? Integer(mi) : 0
}

; Invoke a menu item. method: "" = automatic, or one of
; cmd | altletter | keys | mouse | random.
; Automatic order is most-reliable-first; with the app's "randomize pathways"
; setting on (or method "random"), the visible pathways are tried in a random
; order instead, so the program is driven a different way each time.
AppAct_Menu(app, el, method := "") {
    hwnd := AppMap_LiveHwnd(app)
    if !hwnd {
        ShowStatus("App window not found: " . app["exe"], "fail")
        return false
    }

    avail := AppAct_MenuMethods(app, el)
    if !avail.Length {
        ShowStatus("No way to invoke menu item '" . el["name"] . "'", "fail")
        return false
    }

    randomize := (method = "random")
             || (method = "" && AppMap_Setting("randomize_menus", "0") = "1")
    if (method != "" && method != "random") {
        order := [method]
    } else if randomize {
        ; random order over the VISIBLE pathways; the invisible cmd post stays
        ; as a silent last resort
        pool := [], last := []
        for , mm in avail
            (mm = "cmd" ? last : pool).Push(mm)
        order := []
        while pool.Length {
            pick := Random(1, pool.Length)
            order.Push(pool[pick])
            pool.RemoveAt(pick)
        }
        for , mm in last
            order.Push(mm)
    } else {
        order := avail    ; already reliability-ordered: cmd, altletter, keys, mouse
    }

    for , mm in order {
        ok := false
        switch mm {
            case "cmd":       ok := AppAct_MenuByCmd(app, el, hwnd)
            case "altletter": ok := AppAct_MenuByAltLetter(app, el, hwnd)
            case "keys":      ok := AppAct_MenuByKeys(app, el, hwnd)
            case "mouse":     ok := AppAct_MenuByMouse(app, el, hwnd)
        }
        if ok {
            ShowStatus("Menu '" . el["name"] . "' via " . mm, "ok")
            try AppMapDB().Run("UPDATE ui_element SET hits=hits+1 WHERE id=?", el["id"])
            return true
        }
        Send("{Esc}")     ; close any half-open menu before the next attempt
        Sleep(150)
    }
    ShowStatus("All pathways failed for menu item '" . el["name"] . "'", "fail")
    return false
}

; Pathway 1: WM_COMMAND with the learned command id - instant and layout-proof.
AppAct_MenuByCmd(app, el, hwnd) {
    if (el["cmd_id"] <= 0)
        return false
    WinActivate("ahk_id " . hwnd)
    PostMessage(0x111, el["cmd_id"], 0, , "ahk_id " . hwnd)  ; WM_COMMAND
    return true
}

; Pathway 2: Alt then access letters - Alt+F for File, then the item's own
; access letter when learned ("!f s"), else Down x position + Enter.
AppAct_MenuByAltLetter(app, el, hwnd) {
    WinActivate("ahk_id " . hwnd)
    if !WinWaitActive("ahk_id " . hwnd, , 2)
        return false
    if (el["alt_keys"] != "") {
        for , tok in StrSplit(el["alt_keys"], " ") {
            Send(tok)
            Sleep(200)
        }
        return true
    }
    ; No learned access letters (OCR-learned menus): open the top menu with
    ; Alt + its first letter, then walk down to the item's position.
    if (el["pos_order"] <= 0 || !InStr(el["menu_path"], " > "))
        return false
    top := Trim(StrSplit(el["menu_path"], " > ")[1])
    if (top = "")
        return false
    Send("!" . StrLower(SubStr(top, 1, 1)))
    Sleep(300)
    ; Alt+letter opens the dropdown with nothing selected, so the item's
    ; visible position equals its Down count.
    Send("{Down " . Integer(el["pos_order"]) . "}")
    Sleep(200)
    Send("{Enter}")
    return true
}

; Pathway 3: pure arrow-key navigation from learned positions -
; Alt, Right x(menu-1), Down opens with item 1 selected, Down x(item-1), Enter.
AppAct_MenuByKeys(app, el, hwnd) {
    mi := AppAct_TopMenuOrder(app, el)
    j := Integer(el["pos_order"])
    if (mi <= 0 || j <= 0)
        return false
    WinActivate("ahk_id " . hwnd)
    if !WinWaitActive("ahk_id " . hwnd, , 2)
        return false
    Send("{Alt}")
    Sleep(250)
    if (mi > 1) {
        Send("{Right " . (mi - 1) . "}")
        Sleep(200)
    }
    Send("{Down}")          ; open the dropdown; first item becomes selected
    Sleep(280)
    if (j > 1) {
        Send("{Down " . (j - 1) . "}")
        Sleep(200)
    }
    Send("{Enter}")
    return true
}

; Pathway 4: mouse - click the top menu open, then click the item inside the
; dropdown, finding it by stored coords / FindText pattern, or by OCR of the
; open popup as a last resort.
AppAct_MenuByMouse(app, el, hwnd) {
    if (el["menu_path"] = "" || !InStr(el["menu_path"], " > "))
        return false
    top := Trim(StrSplit(el["menu_path"], " > ")[1])
    topEl := AppMap_Resolve(app["id"], top)
    WinActivate("ahk_id " . hwnd)
    if !WinWaitActive("ahk_id " . hwnd, , 2)
        return false
    if !topEl.Count
        return false
    tl := AppMap_Locate(app, topEl)
    if !tl.Count
        return false
    AppAct_ClickScreen(tl["cx"], tl["cy"])
    Sleep(350)

    ; With the dropdown open, the item's FindText pattern / stored coords work.
    loc := AppMap_Locate(app, el)
    if loc.Count {
        AppAct_ClickScreen(loc["cx"], loc["cy"])
        return true
    }

    ; Still nothing: read the open popup with OCR and click the matching line.
    px := 0, py := 0, pw := 0, ph := 0
    for , popCls in ["#32768", "Xaml_WindowedPopupClass"] {
        popupHwnd := 0
        try popupHwnd := WinExist("ahk_class " . popCls)
        if popupHwnd {
            try WinGetPos(&px, &py, &pw, &ph, "ahk_id " . popupHwnd)
            if (pw > 30 && ph > 30)
                break
            pw := 0
        }
    }
    if (pw > 30 && ph > 30) {
        pop := ""
        try pop := OCR.FromRect(px, py, pw, ph)
        if IsObject(pop) {
            for line in pop.Lines {
                if InStr(line.Text, el["name"]) {
                    lw := line.Words[1]
                    AppAct_ClickScreen(lw.x + lw.w // 2, lw.y + lw.h // 2)
                    return true
                }
            }
        }
    }
    Send("{Esc}")
    return false
}

; ═══════════════════════════════════════════════════════════════════════════════
; THE AUTOMATION LANGUAGE (AppDSL)
; ═══════════════════════════════════════════════════════════════════════════════

global APPDSL_GUIDE := "
(
AppDSL - one command per line. Lines starting with ; or # are comments.
Prefix any line with 'try ' to keep going even if that line fails.
Prefix 'retry ' (optional timeout ms: retry 15000 <cmd>) to repeat the command
every 0.8s until it succeeds - for steps that must wait on a window, list or
menu that is still appearing. Prefixes combine: try retry 5000 menupick Open with

TARGET refs: an element name (e.g. Save), a menu path (File > Save As),
or #id from the element list (e.g. #142).

  focus                       activate the app's window (do this first)
  use msinfo32                switch targeting to another LEARNED app (exe or name)
  learn                       inspect the ACTIVE window into the database and target it
  menu File > Save As         invoke a learned menu item; picks a pathway
                              automatically (or randomly when randomizing).
                              Append @cmd @altletter @keys @mouse or @random
                              to force one:  menu File > Save @keys
  alt f s                     raw Alt-key menu navigation (Alt+F then S)
  click TARGET                left-click an element
  dblclick TARGET             double-click an element
  rightclick TARGET           right-click an element
  hover TARGET                move the mouse onto an element
  clickat X Y [win]           click raw coordinates (screen, or window-relative with 'win')
  type Some text here         type literal text into the focused control
  ctrltext ClassNN|text       set a control's text directly (fast, no typing)
  keys ^s                     send keystrokes in AHK syntax (^=Ctrl !=Alt +=Shift, {Enter}, {F2}...)
  wait 500                    pause N milliseconds
  waitwin Title text [5000]   wait for a window whose title contains the text
  focuswin Title text [8000]  wait for that window AND activate it (focus) -
                              required before keys/type aimed at a new window
  ocr [X Y W H]               OCR the active/app window (or a region); saves text as $ocr
  ocrclick Some text          find text with OCR (active window first) and click it
  ocrrightclick Some text     same but right-click - opens a context menu on it
                              add ' @scroll' to either: scrolls the view top-to-
                              bottom page by page until the text comes into view
  waitocr Some text [8000]    wait until the active window visibly shows the text
  menupick Menu item text     read the OPEN menu / context menu live with OCR
                              and click the item showing that text
  run notepad.exe             launch a program or file (%ENVVARS% expand)
  setclip Some text\nline2    put text on the clipboard (\n and \t become newline/tab)
  say A message               show a status message
)"

; Worked examples of the kind of scripts an LLM copilot generates. All four
; are non-destructive multi-window automations with built-in certification
; gates (waitocr) that stop the script if a step did not really happen.
AppLearner_DemoScript(n := 1) {
    switch n {
        case 2: return AppLearner_Demo2()
        case 3: return AppLearner_Demo3()
        case 4: return AppLearner_Demo4()
    }
    return AppLearner_Demo1()
}

; Demo 2: every menu pathway certified on a freshly learned app, then a
; cross-program clipboard hand-off - proves cmd/altletter/keys/mouse/random
; all reach the same menu item, and that the object model can be grown
; mid-script with 'learn'.
AppLearner_Demo2() {
    return "
(
; ═══ DEMO 2: certify all four menu pathways on a learned app ═══
say Demo 2: menu pathway certification (msinfo32) - nothing gets modified
run msinfo32.exe
focuswin System Information 25000
wait 1500
; add/refresh this window in the object-model database and target it
learn
; the same harmless menu item, reached five different ways:
say Pathway 1/5: WM_COMMAND id (invisible, instant)
menu Edit > Select All @cmd
wait 800
say Pathway 2/5: Alt+letter access keys
menu Edit > Select All @altletter
wait 800
say Pathway 3/5: pure arrow-key counting
menu Edit > Select All @keys
wait 800
say Pathway 4/5: mouse clicks + live OCR of the dropdown
menu Edit > Select All @mouse
wait 800
say Pathway 5/5: random pick between the visible pathways
menu Edit > Select All @random
wait 800
; carry the selected system summary into a second program
menu Edit > Copy @cmd
wait 600
run notepad.exe
focuswin Notepad 10000
keys ^n
wait 600
keys ^v
; CERTIFY: the OS summary really crossed programs (stops here if not)
waitocr OS Name 8000
say CERTIFIED: 5 pathway invocations + clipboard hand-off into Notepad
; tidy up - discard the scratch tab, close msinfo32 via its learned menu
keys ^w
wait 700
try ocrclick Don't save
wait 500
focuswin System Information 5000
menu File > Exit @cmd
say Demo 2 complete - zero changes to disk or settings
)"
}

; Demo 3: Explorer driven at face value - scroll-find a file, map the
; right-click context menu in real time, and round-trip its path into Notepad.
; Uses only read-only menu items (Copy as path). Needs appdsl_demo.py on the
; Desktop (Demo 1 creates it) - or edit the filename below to any file you see.
AppLearner_Demo3() {
    return "
(
; ═══ DEMO 3: Explorer context menu mapped live, path round-trip ═══
say Demo 3: find file visually -> live context menu -> path into Notepad
run explorer.exe %USERPROFILE%\Desktop
focuswin Desktop 15000
; find the file BY LOOKING AT the window, scrolling if it is below the fold
retry 20000 ocrrightclick appdsl_demo @scroll
; the context menu is read live with OCR; 'Copy as path' writes nothing
try retry 6000 menupick Copy as path
; older/classic menu layout fallback
try retry 4000 menupick Show more options
try retry 4000 menupick Copy as path
wait 600
run notepad.exe
focuswin Notepad 10000
keys ^n
wait 600
keys ^v
; CERTIFY: the real full path arrived from Explorer's menu
waitocr appdsl_demo.py 8000
say CERTIFIED: visual find + live menu map + cross-program paste all worked
keys ^w
wait 700
try ocrclick Don't save
say Demo 3 complete - zero writes to disk
)"
}

; Demo 4: three programs chained - Calculator driven by reading its buttons at
; face value, the result carried into Notepad, then Explorer's read-only
; Properties dialog opened through the live context menu.
AppLearner_Demo4() {
    return "
(
; ═══ DEMO 4: Calculator + Notepad + Explorer, chained ═══
say Demo 4: three-program chain - calculator read at face value
run calc.exe
focuswin Calculator 20000
wait 1200
; press buttons by SEEING them (OCR), mixed with keystrokes - 7 + 8 =
ocrclick 7
wait 400
keys {+}
wait 400
ocrclick 8
wait 400
keys {Enter}
wait 600
; CERTIFY: the display really shows the sum
waitocr 15 6000
say CERTIFIED: OCR button clicks computed 7 + 8 = 15
keys ^c
wait 500
run notepad.exe
focuswin Notepad 10000
keys ^n
wait 600
type The calculator said 7 + 8 =
keys ^v
; CERTIFY: the result crossed into Notepad
waitocr calculator said 6000
say CERTIFIED: result carried across programs
; third program: Explorer, read-only Properties via the live context menu
run explorer.exe %USERPROFILE%\Desktop
focuswin Desktop 15000
retry 15000 ocrrightclick appdsl_demo @scroll
try retry 6000 menupick Properties
try retry 4000 menupick Show more options
try retry 4000 menupick Properties
; CERTIFY: the Properties dialog opened (fully read-only)
waitocr Type of file 8000
say CERTIFIED: live context menu -> Properties dialog
keys {Esc}
wait 500
; tidy everything without saving or changing a thing
focuswin Notepad 5000
keys ^w
wait 700
try ocrclick Don't save
wait 400
focuswin Calculator 5000
keys !{F4}
say Demo 4 complete - three programs orchestrated, nothing modified
)"
}

; Demo 1: the original end-to-end - python code through Notepad's GUI to the
; Desktop, found in Explorer, opened in VS Code via the context menu, and run.
AppLearner_Demo1() {
    return "
(
; ═══ Example of the kind of script an LLM copilot generates ═══
; Goal: save Python code to the Desktop through Notepad's own GUI, find the
; file in Explorer, open it in VS Code via the right-click menu, and run it.
say Demo: python code -> Notepad -> save to Desktop -> Explorer -> VS Code
setclip print("hello from AppDSL")\nfor i in range(3):\n    print("loop", i)
run notepad.exe
focuswin Notepad 10000
wait 700
keys ^n
wait 500
keys ^v
wait 500
; Save As dialog
keys ^+s
focuswin Save 8000
wait 900
; the File name box is Alt+N in every Windows save dialog; typing a full path
; names the file AND navigates the dialog to the Desktop in one step
keys !n
wait 400
type %USERPROFILE%\Desktop\appdsl_demo.py
wait 300
; ensure the file type cannot mangle the .py extension: Save as type -> All files
keys !t
wait 300
keys a
wait 300
; the Save button (Alt+S presses it whatever has focus)
keys !s
wait 1000
; confirm the overwrite prompt if one appeared; otherwise this line just skips
try ocrclick Yes
wait 800
; ═══ Explorer: open the Desktop folder and find the file at face value ═══
run explorer.exe %USERPROFILE%\Desktop
focuswin Desktop 15000
; wait until Explorer has actually RENDERED the file list, then find the file
; visually - retry keeps re-reading while the window is still loading, and
; @scroll pages through the view if the file sits below the fold
retry 20000 ocrrightclick appdsl_demo @scroll
; the context menu is mapped IN REAL TIME with OCR - no pre-learning needed;
; retry waits for the menu to finish appearing before each read
try retry 6000 menupick Open with Code
wait 700
try retry 4000 menupick Open with
wait 700
try retry 4000 menupick Code
; ═══ VS Code: run the file in a terminal ═══
focuswin Visual Studio Code 30000
; wait until the editor has visibly loaded the file before touching it
waitocr appdsl_demo 20000
wait 800
keys ^+p
wait 800
type Terminal: Create New Terminal
wait 400
keys {Enter}
wait 1500
type python `"%USERPROFILE%\Desktop\appdsl_demo.py`"
wait 300
keys {Enter}
say Demo complete - check the VS Code terminal for the output
)"
}

; Execute an AppDSL script against a learned app. Returns lines-run count.
AppExec_Run(appId, script) {
    global g_AppExecAbort, g_AppExecVars, g_AppExecSwitchTo
    g_AppExecSwitchTo := 0
    app := AppMap_AppRow(appId)
    if !app.Count {
        ; No learned app: window-agnostic commands (run, keys, type, setclip,
        ; waitwin, ocrclick, menupick...) still work against the active window.
        app := Map("id", 0, "name", "(no app)", "exe", "", "cls", "")
    }
    g_AppExecAbort := false
    g_AppExecVars := Map()
    ran := 0
    for lineNo, rawLine in StrSplit(script, "`n", "`r") {
        if g_AppExecAbort {
            ShowStatus("Script aborted at line " . lineNo, "wait")
            break
        }
        line := Trim(rawLine)
        if (line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#")
            continue
        tolerant := false
        if (StrLower(SubStr(line, 1, 4)) = "try ") {
            tolerant := true
            line := Trim(SubStr(line, 5))
        }
        ; 'retry [ms] <command>' repeats the command every 0.8s until it
        ; succeeds or the timeout (default 10s) runs out - the way to wait for
        ; a window/list/menu that has not finished appearing yet.
        retryMs := 0
        if RegExMatch(line, "i)^retry(?:\s+(\d+))?\s+(.+)$", &rm) {
            retryMs := (rm[1] != "" ? Integer(rm[1]) : 10000)
            line := Trim(rm[2])
        }
        ok := false
        deadline := A_TickCount + retryMs
        loop {
            try ok := AppExec_Line(app, line)
            catch as err {
                AppMap_LogError("AppExec line " . lineNo, err)
                ok := false
            }
            if (ok || retryMs = 0 || A_TickCount >= deadline || g_AppExecAbort)
                break
            ShowStatus("Retrying (line " . lineNo . "): " . TrackEllipsis(line, 45), "wait")
            Sleep(800)
        }
        ; a 'use' or 'learn' line retargets the rest of the script
        if g_AppExecSwitchTo {
            newApp := AppMap_AppRow(g_AppExecSwitchTo)
            if newApp.Count {
                app := newApp
                ShowStatus("Script now targets '" . TrackEllipsis(app["name"], 35) . "' (" . app["exe"] . ")", "info")
            }
            g_AppExecSwitchTo := 0
        }
        ran++
        if (!ok && !tolerant) {
            ShowStatus("Script stopped: line " . lineNo . " failed → " . TrackEllipsis(line, 50), "fail")
            return ran
        }
    }
    ShowStatus("Script finished: " . ran . " commands", "ok")
    return ran
}

AppExec_Stop() {
    global g_AppExecAbort
    g_AppExecAbort := true
}

; One command. Returns true on success.
AppExec_Line(app, line) {
    global g_AppExecVars, g_AppExecAbort, g_AppExecSwitchTo
    if !RegExMatch(line, "^(\S+)\s*(.*)$", &m)
        return false
    verb := StrLower(m[1])
    arg := Trim(m[2])
    ; strip optional surrounding quotes on the argument
    if (StrLen(arg) >= 2 && SubStr(arg, 1, 1) = '"' && SubStr(arg, -1) = '"')
        arg := SubStr(arg, 2, StrLen(arg) - 2)

    switch verb {
        case "focus":
            return AppAct_Focus(app)

        case "use":
            ; switch targeting to an already-learned app, by exe or name
            if (arg = "")
                return false
            db := AppMapDB()
            if !db
                return false
            id := db.Scalar("SELECT id FROM " . AppMap_AppTable() . " WHERE exe LIKE ? OR name LIKE ? "
                          . "ORDER BY learned_ts DESC LIMIT 1", "%" . arg . "%", "%" . arg . "%")
            if (!IsInteger(id) || Integer(id) <= 0) {
                ShowStatus("No learned app matches: " . arg, "fail")
                return false
            }
            g_AppExecSwitchTo := Integer(id)
            return true

        case "learn":
            ; inspect the ACTIVE window into the database, then target it
            hwnd := WinExist("A")
            if !hwnd
                return false
            counts := AppMap_LearnWindow(hwnd, Map("controls", true, "acc", true
                , "menus", true, "ocrtext", true, "altocr", false, "visuals", true))
            if !counts.Count
                return false
            g_AppExecSwitchTo := counts["id"]
            return true

        case "menu":
            ; optional pathway suffix:  menu File > Save @mouse
            method := ""
            if RegExMatch(arg, "i)^(.*?)\s*@(cmd|altletter|keys|mouse|random)$", &pm) {
                arg := Trim(pm[1])
                method := StrLower(pm[2])
            }
            el := AppMap_Resolve(app["id"], arg)
            if !el.Count {
                ShowStatus("Menu item not learned: " . arg, "fail")
                return false
            }
            return AppAct_Menu(app, el, method)

        case "alt":
            hwnd := AppMap_LiveHwnd(app)
            if !hwnd
                return false
            WinActivate("ahk_id " . hwnd)
            if !WinWaitActive("ahk_id " . hwnd, , 2)
                return false
            for i, tok in StrSplit(arg, " ") {
                if (tok = "")
                    continue
                Send(i = 1 ? "!" . tok : tok)
                Sleep(180)
            }
            return true

        case "click", "dblclick", "rightclick", "hover":
            el := AppMap_Resolve(app["id"], arg)
            if !el.Count {
                ShowStatus("Element not learned: " . arg, "fail")
                return false
            }
            if (verb = "hover") {
                loc := AppMap_Locate(app, el)
                if !loc.Count
                    return false
                AppAct_MoveScreen(loc["cx"], loc["cy"])
                return true
            }
            btn := (verb = "rightclick" ? "Right" : "Left")
            cnt := (verb = "dblclick" ? 2 : 1)
            return AppAct_Click(app, el, btn, cnt)

        case "clickat":
            parts := StrSplit(RegExReplace(arg, "\s+", " "), " ")
            if (parts.Length < 2)
                return false
            x := Integer(parts[1]), y := Integer(parts[2])
            if (parts.Length >= 3 && StrLower(parts[3]) = "win") {
                hwnd := AppMap_LiveHwnd(app)
                if !hwnd
                    return false
                WinGetPos(&wx, &wy, , , "ahk_id " . hwnd)
                x += wx, y += wy
            }
            AppAct_ClickScreen(x, y)
            return true

        case "type":
            if (arg = "")
                return false
            SendText(AppExec_Expand(arg))
            return true

        case "run":
            if (arg = "")
                return false
            try Run(AppExec_Expand(arg))
            catch as err {
                ShowStatus("run failed: " . TrackEllipsis(err.Message, 60), "fail")
                return false
            }
            return true

        case "setclip":
            txt := AppExec_Expand(arg)
            txt := StrReplace(txt, "\n", "`n")
            txt := StrReplace(txt, "\t", "`t")
            A_Clipboard := txt
            Sleep(150)
            return true

        case "menupick":
            if (arg = "")
                return false
            return AppExec_MenuPick(arg)

        case "ctrltext":
            p := InStr(arg, "|")
            if !p
                return false
            nn := Trim(SubStr(arg, 1, p - 1)), txt := SubStr(arg, p + 1)
            hwnd := AppMap_LiveHwnd(app)
            if !hwnd
                return false
            try {
                ControlSetText(txt, nn, "ahk_id " . hwnd)
                return true
            } catch {
                return false
            }

        case "keys":
            if (arg = "")
                return false
            Send(arg)
            return true

        case "wait":
            ms := IsInteger(arg) ? Integer(arg) : 500
            Sleep(Min(ms, 60000))
            return true

        case "waitwin":
            timeout := 5000
            title := arg
            if RegExMatch(arg, "^(.*?)\s+(\d+)$", &wm) {
                title := Trim(wm[1]), timeout := Integer(wm[2])
            }
            return WinWait(title, , timeout / 1000.0) != 0

        case "ocr":
            text := ""
            if (arg != "") {
                parts := StrSplit(RegExReplace(arg, "\s+", " "), " ")
                if (parts.Length >= 4)
                    try text := OCR.FromRect(Integer(parts[1]), Integer(parts[2])
                                           , Integer(parts[3]), Integer(parts[4])).Text
            } else {
                hwnd := AppMap_LiveHwnd(app)
                if hwnd {
                    try text := OCR.FromWindow("ahk_id " . hwnd).Text
                } else {
                    try text := OCR.FromWindow("A").Text
                }
            }
            g_AppExecVars["ocr"] := text
            ShowStatus("OCR captured " . StrLen(text) . " chars", text != "" ? "ok" : "fail")
            return text != ""

        case "ocrclick", "ocrrightclick":
            if (arg = "")
                return false
            btn := (verb = "ocrrightclick" ? "Right" : "Left")
            ; '@scroll' suffix: if the text is not in view, scroll the active
            ; window page by page (top first) re-reading with OCR each step -
            ; for files below the fold in an Explorer view, long lists, etc.
            if RegExMatch(arg, "i)^(.*?)\s*@scroll$", &sm)
                return AppExec_OcrClickScroll(app, Trim(sm[1]), btn)
            return AppExec_OcrClick(app, arg, btn)

        case "focuswin":
            ; wait for a window whose title contains the text, then ACTIVATE it
            ; and confirm it has focus - use at every hand-off between windows
            ; (waitwin only proves existence; keystrokes go to the ACTIVE window)
            timeout := 8000
            title := arg
            if RegExMatch(arg, "^(.*?)\s+(\d+)$", &fw) {
                title := Trim(fw[1])
                timeout := Integer(fw[2])
            }
            if (title = "")
                return false
            if !WinWait(title, , timeout / 1000.0)
                return false
            WinActivate(title)
            return WinWaitActive(title, , 3) != 0

        case "waitocr":
            timeout := 8000
            txt := arg
            if RegExMatch(arg, "^(.*?)\s+(\d+)$", &wo) {
                txt := Trim(wo[1])
                timeout := Integer(wo[2])
            }
            if (txt = "")
                return false
            deadline := A_TickCount + timeout
            loop {
                t := ""
                try t := OCR.FromWindow("A").Text
                if InStr(t, txt)
                    return true
                if (A_TickCount >= deadline || g_AppExecAbort)
                    return false
                Sleep(500)
            }

        case "say":
            ShowStatus(arg, "info")
            return true
    }
    ShowStatus("Unknown command: " . verb, "fail")
    return false
}

; ─── DSL helpers ─────────────────────────────────────────────────────────────

; Expand %ENVVAR% references, e.g. %USERPROFILE%\Desktop.
AppExec_Expand(s) {
    while RegExMatch(s, "%(\w+)%", &m) {
        v := ""
        try v := EnvGet(m[1])
        s := StrReplace(s, m[0], v)
    }
    return s
}

; Find text on screen with OCR and click it. Reads the ACTIVE window first
; (dialogs, Explorer, whatever has focus), then the learned app's window, then
; the whole desktop. button: "Left" | "Right". quiet suppresses the fail status
; (used by the scroll/retry loops that expect misses).
AppExec_OcrClick(app, text, button := "Left", quiet := false) {
    sources := ["A"]
    hwnd := AppMap_LiveHwnd(app)
    if hwnd
        sources.Push("ahk_id " . hwnd)
    for , srcWin in sources {
        res := ""
        try res := OCR.FromWindow(srcWin)
        if IsObject(res) {
            loc := AppExec_FindInOcr(res, text)
            if loc.Count {
                AppAct_ClickScreen(loc["x"], loc["y"], button)
                return true
            }
        }
    }
    res := ""
    try res := OCR.FromDesktop()
    if IsObject(res) {
        loc := AppExec_FindInOcr(res, text)
        if loc.Count {
            AppAct_ClickScreen(loc["x"], loc["y"], button)
            return true
        }
    }
    if !quiet
        ShowStatus("OCR could not find: " . text, "fail")
    return false
}

; Scroll-search: look for the text in the current view; if absent, hover the
; active window, wheel back to the top, then step down one page at a time,
; re-reading with OCR after each step, until found or the bottom-most page.
AppExec_OcrClickScroll(app, text, button := "Left", maxPages := 12) {
    global g_AppExecAbort
    if AppExec_OcrClick(app, text, button, true)
        return true

    ; hover the centre of the active window so the wheel scrolls ITS content
    wx := 0, wy := 0, ww := 0, wh := 0
    try WinGetPos(&wx, &wy, &ww, &wh, "A")
    if (ww > 0)
        AppAct_MoveScreen(wx + ww // 2, wy + wh // 2)

    Send("{WheelUp 40}")     ; back to the top of the view
    Sleep(500)
    Loop maxPages {
        if g_AppExecAbort
            return false
        if AppExec_OcrClick(app, text, button, true)
            return true
        Send("{WheelDown 8}")
        Sleep(650)
    }
    ; one last loud attempt so the miss is reported
    return AppExec_OcrClick(app, text, button)
}

; Centre of the first OCR word (then line) containing `text`; empty Map if none.
AppExec_FindInOcr(res, text) {
    for word in res.Words {
        if InStr(word.Text, text)
            return Map("x", word.x + word.w // 2, "y", word.y + word.h // 2)
    }
    for line in res.Lines {
        if InStr(line.Text, text) {
            lw := line.Words[1]
            return Map("x", lw.x + lw.w // 2, "y", lw.y + lw.h // 2)
        }
    }
    return Map()
}

; Real-time menu mapping: read whatever menu / context menu is OPEN right now
; with OCR and click the item whose text matches. Works on Win32 menus,
; WinUI/XAML flyouts and Explorer's Windows 11 context menu; falls back to a
; whole-screen OCR and clicks the match nearest the mouse (menus open at the
; cursor), refusing anything suspiciously far away.
AppExec_MenuPick(text) {
    ; 1. A recognizable popup window class
    for , popCls in ["#32768", "Xaml_WindowedPopupClass", "Microsoft.UI.Content.PopupWindowSiteBridge"] {
        popupHwnd := 0
        try popupHwnd := WinExist("ahk_class " . popCls)
        if !popupHwnd
            continue
        px := 0, py := 0, pw := 0, ph := 0
        try WinGetPos(&px, &py, &pw, &ph, "ahk_id " . popupHwnd)
        if (pw < 20 || ph < 20)
            continue
        pop := ""
        try pop := OCR.FromRect(px, py, pw, ph)
        if IsObject(pop) {
            loc := AppExec_FindInOcr(pop, text)
            if loc.Count {
                AppAct_ClickScreen(loc["x"], loc["y"])
                ShowStatus("Menu item '" . text . "' picked (live OCR)", "ok")
                return true
            }
        }
    }

    ; 2. Fallback: whole-screen OCR, nearest match to the cursor
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    res := ""
    try res := OCR.FromDesktop()
    if !IsObject(res)
        return false
    bestX := 0, bestY := 0, bestD := -1
    for line in res.Lines {
        if !InStr(line.Text, text)
            continue
        lw := line.Words[1]
        cx := lw.x + lw.w // 2, cy := lw.y + lw.h // 2
        d := Abs(cx - mx) + Abs(cy - my)
        if (bestD < 0 || d < bestD)
            bestX := cx, bestY := cy, bestD := d
    }
    ; menus open at the cursor - a distant match is NOT the open menu
    if (bestD >= 0 && bestD <= 700) {
        AppAct_ClickScreen(bestX, bestY)
        ShowStatus("Menu item '" . text . "' picked (screen OCR)", "ok")
        return true
    }
    ShowStatus("No open menu shows: " . text, "fail")
    return false
}

; ═══════════════════════════════════════════════════════════════════════════════
; LLM INSTRUCTION SHEET + CATALOG
; ═══════════════════════════════════════════════════════════════════════════════

; Human/LLM-readable catalog of everything learned for an app.
AppMap_Catalog(appId, maxElements := 400) {
    app := AppMap_AppRow(appId)
    if !app.Count
        return ""
    out := "APPLICATION: " . app["name"] . "  (exe: " . app["exe"] . ", class: " . app["cls"] . ")`n"
    out .= "Learned: " . app["learned_ts"] . "`n`n"

    menus := AppMap_Elements(appId, "menuitem")
    for e in AppMap_Elements(appId, "menuitem-ocr")
        menus.Push(e)
    if menus.Length {
        out .= "MENU ITEMS (invoke with:  menu <path>):`n"
        for e in menus {
            out .= "  " . e["menu_path"]
            if (e["shortcut"] != "")
                out .= "   [shortcut: " . e["shortcut"] . "]"
            if (e["alt_keys"] != "")
                out .= "   [alt: " . StrReplace(e["alt_keys"], "!", "Alt+") . "]"
            out .= "`n"
        }
        out .= "`n"
    }

    ctrls := AppMap_Elements(appId, "control")
    if ctrls.Length {
        out .= "CONTROLS (click <name>, or ctrltext <ClassNN>|<text>):`n"
        for e in ctrls {
            out .= "  #" . e["id"] . "  " . e["class_nn"]
            if (e["name"] != e["class_nn"])
                out .= '  "' . TrackEllipsis(e["name"], 40) . '"'
            out .= "`n"
        }
        out .= "`n"
    }

    ocrs := AppMap_Elements(appId, "ocr")
    if ocrs.Length {
        out .= "VISIBLE TEXT read from the window with OCR (click <text> works at face value):`n"
        shownO := 0
        for e in ocrs {
            out .= "  " . TrackEllipsis(e["name"], 60) . "`n"
            shownO++
            if (shownO >= 120) {
                out .= "  ... (" . (ocrs.Length - shownO) . " more)`n"
                break
            }
        }
        out .= "`n"
    }

    accs := AppMap_Elements(appId, "acc")
    if accs.Length {
        out .= "UI ELEMENTS from the accessibility tree (click <name> or click #id):`n"
        shown := 0
        for e in accs {
            if (e["name"] = "")
                continue
            out .= "  #" . e["id"] . "  [" . e["role"] . "]  " . TrackEllipsis(e["name"], 50)
            if (e["shortcut"] != "")
                out .= "   [key: " . e["shortcut"] . "]"
            out .= "`n"
            shown++
            if (shown >= maxElements) {
                out .= "  ... (" . (accs.Length - shown) . " more)`n"
                break
            }
        }
    }
    return out
}

; The complete instruction sheet an LLM needs to drive this app.
AppMap_BuildLLMPrompt(appId, goal := "") {
    global APPDSL_GUIDE
    out := "You control a Windows program through an automation engine. "
    out .= "You can ONLY act by emitting AppDSL commands, one per line.`n`n"
    out .= "=== APPDSL LANGUAGE ===`n" . APPDSL_GUIDE . "`n"
    out .= "=== THE PROGRAM YOU CONTROL ===`n" . AppMap_Catalog(appId) . "`n"
    out .= "=== RULES ===`n"
    out .= "1. Output ONLY AppDSL command lines, nothing else. No prose, no markdown fences.`n"
    out .= "2. Start with 'focus'.`n"
    out .= "3. Prefer 'menu <path>' and 'keys <shortcut>' over clicking coordinates.`n"
    out .= "4. Use 'wait 500' after actions that open dialogs; use 'waitwin'/'waitocr' for new windows or content, and the 'retry' prefix on any step that depends on something still loading.`n"
    out .= "5. Only reference menu paths and elements listed above.`n"
    out .= "6. Pathway suffixes on menu lines (@cmd @altletter @keys @mouse @random) are optional; omit them unless the task asks for a specific input style.`n"
    if (goal != "")
        out .= "`n=== TASK ===`n" . goal . "`n"
    return out
}

; ═══════════════════════════════════════════════════════════════════════════════
; OLLAMA BRIDGE
; ═══════════════════════════════════════════════════════════════════════════════

; POST /api/generate on a local Ollama server. Returns the response text ("" on
; failure; sets errOut). Blocking call - Ollama generation can take a while.
Ollama_Generate(prompt, model, url := "http://localhost:11434", &errOut := "") {
    errOut := ""
    ; Built by hand: Ollama's Go server needs a true JSON boolean for "stream",
    ; which a generic AHK encoder would emit as 0.
    body := '{"model":' . Ollama_JsonStr(model) . ',"prompt":' . Ollama_JsonStr(prompt) . ',"stream":false}'
    whr := ""
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("POST", RTrim(url, "/") . "/api/generate", false)
        whr.SetRequestHeader("Content-Type", "application/json")
        whr.SetTimeouts(5000, 5000, 10000, 600000)
        whr.Send(body)
    } catch as err {
        errOut := "Cannot reach Ollama at " . url . " (" . err.Message . ")"
        return ""
    }
    if (whr.Status != 200) {
        errOut := "Ollama HTTP " . whr.Status . ": " . TrackEllipsis(whr.ResponseText, 200)
        return ""
    }
    resp := Ollama_ExtractJsonString(whr.ResponseText, "response")
    if (resp = "")
        errOut := "Empty response from model " . model
    return resp
}

; Is the server up? Returns version string or "".
Ollama_Ping(url := "http://localhost:11434") {
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("GET", RTrim(url, "/") . "/api/version", false)
        whr.SetTimeouts(3000, 3000, 3000, 5000)
        whr.Send()
        if (whr.Status = 200)
            return Ollama_ExtractJsonString(whr.ResponseText, "version")
    }
    return ""
}

; Encode a string as a JSON string literal.
Ollama_JsonStr(s) {
    s := StrReplace(String(s), "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    out := ""
    for , c in StrSplit(s) {
        out .= (Ord(c) < 0x20) ? Format("\u{:04X}", Ord(c)) : c
    }
    return '"' . out . '"'
}

; Pull one string field out of a flat JSON object and unescape it.
Ollama_ExtractJsonString(json, key) {
    if !RegExMatch(json, '"' . key . '"\s*:\s*"((?:[^"\\]|\\.)*)"', &m)
        return ""
    s := m[1]
    s := StrReplace(s, "\n", "`n")
    s := StrReplace(s, "\r", "`r")
    s := StrReplace(s, "\t", "`t")
    s := StrReplace(s, '\"', '"')
    while RegExMatch(s, "\\u([0-9A-Fa-f]{4})", &u)
        s := StrReplace(s, u[0], Chr(Integer("0x" . u[1])))
    s := StrReplace(s, "\\", "\")
    return s
}

; Full round trip: build the instruction sheet, ask the model, clean the reply
; down to valid AppDSL lines. Returns the script text ("" on failure).
Ollama_GenerateScript(appId, goal, model, url, &errOut := "") {
    prompt := AppMap_BuildLLMPrompt(appId, goal)
    raw := Ollama_Generate(prompt, model, url, &errOut)
    if (raw = "")
        return ""
    return AppLLM_CleanScript(raw)
}

; Keep only lines that look like AppDSL (models love adding prose and fences).
AppLLM_CleanScript(text) {
    verbs := "i)^(try\s+)?(retry(\s+\d+)?\s+)?(focus|focuswin|use|learn|menu|alt|click|dblclick|rightclick|hover|clickat|type|ctrltext|keys|wait|waitwin|waitocr|ocr|ocrclick|ocrrightclick|menupick|run|setclip|say)\b"
    out := ""
    for , line in StrSplit(text, "`n", "`r") {
        t := Trim(line)
        t := RegExReplace(t, "^\x60{3,}\s*\w*\s*$")   ; markdown code fences
        if (t = "")
            continue
        if (SubStr(t, 1, 1) = ";" || SubStr(t, 1, 1) = "#" || t ~= verbs)
            out .= t . "`n"
    }
    return RTrim(out, "`n")
}

; ═══════════════════════════════════════════════════════════════════════════════
; EXPORT
; ═══════════════════════════════════════════════════════════════════════════════

; Portable JSON export of one app's whole object model.
AppMap_ExportJson(appId, path) {
    app := AppMap_AppRow(appId)
    if !app.Count
        return 0
    els := AppMap_Elements(appId)
    arr := []
    for e in els {
        arr.Push(Map("id", e["id"], "kind", e["kind"], "name", e["name"], "role", e["role"]
                   , "class_nn", e["class_nn"], "acc_path", e["acc_path"]
                   , "menu_path", e["menu_path"], "alt_keys", e["alt_keys"]
                   , "shortcut", e["shortcut"], "cmd_id", e["cmd_id"]
                   , "order", e["pos_order"], "depth", e["depth"]
                   , "abs", Map("x", e["x"], "y", e["y"], "w", e["w"], "h", e["h"])
                   , "rel", Map("x", e["rel_x"], "y", e["rel_y"], "w", e["rel_w"], "h", e["rel_h"])))
    }
    doc := Map("kind", "macroautomate.appmap", "version", 1
             , "app", Map("name", app["name"], "exe", app["exe"], "class", app["cls"])
             , "exported", AppMap_TS(), "count", arr.Length, "elements", arr)
    Track_WriteFile(path, TrackJsonEncode(doc, 2))
    return arr.Length
}

; ═══════════════════════════════════════════════════════════════════════════════
; APP LEARNER TAB (UI)
; ═══════════════════════════════════════════════════════════════════════════════

AppLearner_BuildTab(g) {
    global g_ALWinLV, g_ALElemLV, g_ALAppDD, g_ALFilterEdit, g_ALKindDD
    global g_ALScriptEdit, g_ALGoalEdit, g_ALOllamaUrl, g_ALOllamaModel, g_ALOllamaStatus, g_ALDemoDD
    global g_ALCbControls, g_ALCbAcc, g_ALCbMenus, g_ALCbAltOcr, g_ALCbVisuals, g_ALCbRandom, g_ALCbOcrScan

    ; ─── 1. Pick a window and learn it ───────────────────────────────────────
    g.Add("GroupBox", "x15 y50 w860 h160", "1. Learn a Window (inspects it and saves every control, menu and shortcut)")
    g_ALWinLV := g.Add("ListView", "x25 y70 w545 h130 Grid NoSortHdr", ["Title", "Exe", "Class"])
    g_ALWinLV.ModifyCol(1, 290)
    g_ALWinLV.ModifyCol(2, 120)
    g_ALWinLV.ModifyCol(3, 125)
    g.Add("Button", "x580 y70 w130 h24", "🔄 Refresh List").OnEvent("Click", (*) => AppLearner_RefreshWindows())
    g_ALCbControls := g.Add("CheckBox", "x580 y97 w130 Checked", "Controls")
    g_ALCbAcc := g.Add("CheckBox", "x580 y115 w130 Checked", "Acc tree")
    g_ALCbMenus := g.Add("CheckBox", "x580 y133 w130 Checked", "Menus (Win32)")
    g_ALCbAltOcr := g.Add("CheckBox", "x580 y151 w135 Checked", "Alt+OCR menus")
    g_ALCbAltOcr.ToolTip := "Presses Alt and arrows through every menu, reading items with OCR. Runs when the app has no Win32 menu bar. Hands off while it works!"
    g_ALCbVisuals := g.Add("CheckBox", "x580 y169 w135 Checked", "FindText visuals")
    g_ALCbVisuals.ToolTip := "Photographs every learned element's pixels into a FindText pattern so it can be found again purely by its looks."
    g_ALCbOcrScan := g.Add("CheckBox", "x580 y187 w135 Checked", "OCR text scan")
    g_ALCbOcrScan.ToolTip := "Reads the whole window with OCR (like the Live OCR tab) and stores every visible line of text as a clickable element."
    g.Add("Button", "x720 y70 w145 h52 cGreen", "🎓 Learn Selected").OnEvent("Click", (*) => AppLearner_LearnSelected())
    g.Add("Button", "x720 y130 w145 h26", "Learn ALL Windows").OnEvent("Click", (*) => AppLearner_LearnAll())
    g.Add("Button", "x720 y162 w70 h26", "DB Folder").OnEvent("Click", (*) => Run("explore " . DATA_DIR))
    g.Add("Button", "x795 y162 w70 h26", "📜 Console").OnEvent("Click", (*) => AppLog_Open())

    ; ─── 2. The learned object model ─────────────────────────────────────────
    g.Add("GroupBox", "x15 y215 w860 h245", "2. Learned Apps and Their Object Model")
    g.Add("Text", "x25 y240", "App:")
    g_ALAppDD := g.Add("DropDownList", "x55 y236 w250")
    g_ALAppDD.OnEvent("Change", (*) => AppLearner_RefreshElements())
    g.Add("Button", "x310 y235 w55 h24", "Delete").OnEvent("Click", (*) => AppLearner_DeleteApp())
    g.Add("Text", "x380 y240", "Filter:")
    g_ALFilterEdit := g.Add("Edit", "x420 y236 w150")
    g_ALFilterEdit.OnEvent("Change", (*) => AppLearner_RefreshElements())
    g.Add("Text", "x580 y240", "Kind:")
    g_ALKindDD := g.Add("DropDownList", "x615 y236 w120 Choose1"
        , ["(all)", "menuitem", "menuitem-ocr", "menu", "control", "acc", "ocr"])
    g_ALKindDD.OnEvent("Change", (*) => AppLearner_RefreshElements())
    g_ALCbRandom := g.Add("CheckBox", "x743 y239 w125"
        . (AppMap_Setting("randomize_menus", "0") = "1" ? " Checked" : ""), "🎲 Randomize")
    g_ALCbRandom.ToolTip := "Vary how menu items are invoked: each call randomly picks Alt+letter, arrow keys, or mouse clicks instead of always using the same pathway."
    g_ALCbRandom.OnEvent("Click", (*) => AppMap_SetSetting("randomize_menus", g_ALCbRandom.Value ? "1" : "0"))

    g_ALElemLV := g.Add("ListView", "x25 y266 w690 h185 Grid", ["ID", "Kind", "Name", "Menu Path / ClassNN", "Shortcut", "Alt", "X", "Y"])
    g_ALElemLV.ModifyCol(1, 45)
    g_ALElemLV.ModifyCol(2, 75)
    g_ALElemLV.ModifyCol(3, 170)
    g_ALElemLV.ModifyCol(4, 200)
    g_ALElemLV.ModifyCol(5, 75)
    g_ALElemLV.ModifyCol(6, 45)
    g_ALElemLV.ModifyCol(7, 40)
    g_ALElemLV.ModifyCol(8, 40)
    g_ALElemLV.OnEvent("DoubleClick", (lv, row) => AppLearner_HighlightRow(row))

    g.Add("Button", "x725 y266 w140 h24", "💡 Highlight").OnEvent("Click", (*) => AppLearner_HighlightRow(0))
    g.Add("Button", "x725 y294 w140 h24", "🖱 Test Click").OnEvent("Click", (*) => AppLearner_TestClick())
    g.Add("Button", "x725 y322 w140 h24", "Copy Ref").OnEvent("Click", (*) => AppLearner_CopyRef())
    g.Add("Button", "x725 y350 w140 h24", "Export JSON").OnEvent("Click", (*) => AppLearner_ExportJson())
    g.Add("Button", "x725 y378 w140 h24 cBlue", "📋 LLM Instructions").OnEvent("Click", (*) => AppLearner_ShowPrompt())
    g.Add("Button", "x725 y406 w140 h24", "View Catalog").OnEvent("Click", (*) => AppLearner_ShowCatalog())

    ; ─── 3. AppDSL script runner ─────────────────────────────────────────────
    g.Add("GroupBox", "x15 y465 w425 h288", "3. Automation Script (AppDSL)")
    g_ALScriptEdit := g.Add("Edit", "x25 y485 w405 h196 Multi WantTab VScroll")
    g_ALScriptEdit.SetFont("s9", "Consolas")
    g_ALScriptEdit.Value := "; Example - select an app above, then:`nfocus`nsay Hello from AppDSL"
    g.Add("Text", "x25 y689 w40", "Demo:")
    g_ALDemoDD := g.Add("DropDownList", "x66 y685 w244 Choose1", [
        "1: Notepad → save .py → VS Code",
        "2: Certify all 4 menu pathways",
        "3: Explorer live context menu",
        "4: Calc + Notepad + Explorer chain"])
    g.Add("Button", "x315 y684 w115 h24", "🧪 Load Demo").OnEvent("Click", (*) => AppLearner_LoadDemo())
    g.Add("Button", "x25 y713 w110 h28 cGreen", "▶ Run Script").OnEvent("Click", (*) => AppLearner_RunScript())
    g.Add("Button", "x140 y713 w60 h28", "■ Stop").OnEvent("Click", (*) => AppExec_Stop())
    g.Add("Button", "x205 y713 w95 h28", "DSL Guide").OnEvent("Click", (*) => AppLearner_ShowGuide())
    g.Add("Button", "x305 y713 w125 h28", "Copy as Prompt").OnEvent("Click", (*) => AppLearner_CopyPrompt())

    ; ─── 4. Ollama copilot ───────────────────────────────────────────────────
    g.Add("GroupBox", "x450 y465 w425 h288", "4. Ollama Copilot (LLM drives the app)")
    g.Add("Text", "x460 y489", "Server:")
    g_ALOllamaUrl := g.Add("Edit", "x505 y485 w205", AppMap_Setting("ollama_url", "http://localhost:11434"))
    g.Add("Button", "x715 y484 w70 h24", "Test").OnEvent("Click", (*) => AppLearner_TestOllama())
    g.Add("Text", "x460 y517", "Model:")
    g_ALOllamaModel := g.Add("Edit", "x505 y513 w205", AppMap_Setting("ollama_model", "llama3.2"))
    g.Add("Text", "x460 y543", "Goal (what should the LLM make the program do?):")
    g_ALGoalEdit := g.Add("Edit", "x460 y560 w405 h110 Multi VScroll")
    g.Add("Button", "x460 y678 w150 h28 cBlue", "🤖 Generate Script").OnEvent("Click", (*) => AppLearner_AskOllama(false))
    g.Add("Button", "x615 y678 w150 h28", "Generate + Run").OnEvent("Click", (*) => AppLearner_AskOllama(true))
    g_ALOllamaStatus := g.Add("Text", "x460 y712 w405 h30 cGray", "The generated AppDSL lands in box 3 for review before running.")

    AppLearner_RefreshWindows()
    AppLearner_RefreshApps()
}

; ─── window list ─────────────────────────────────────────────────────────────
AppLearner_RefreshWindows() {
    global g_ALWinLV, g_ALWinHwnds
    g_ALWinLV.Delete()
    g_ALWinHwnds := []
    for hwnd in WinGetList() {
        title := "", exe := "", cls := ""
        try title := WinGetTitle("ahk_id " . hwnd)
        if (title = "")
            continue
        try exe := WinGetProcessName("ahk_id " . hwnd)
        try cls := WinGetClass("ahk_id " . hwnd)
        ; skip our own GUI and shell chrome
        if (exe = "AutoHotkey64.exe" && InStr(title, "Macro"))
            continue
        if (cls = "Progman" || cls = "Shell_TrayWnd" || cls = "Windows.UI.Core.CoreWindow")
            continue
        g_ALWinLV.Add(, TrackEllipsis(title, 45), exe, cls)
        g_ALWinHwnds.Push(hwnd)
    }
}

AppLearner_LearnOpts() {
    global g_ALCbControls, g_ALCbAcc, g_ALCbMenus, g_ALCbAltOcr, g_ALCbVisuals, g_ALCbOcrScan
    return Map("controls", g_ALCbControls.Value = 1, "acc", g_ALCbAcc.Value = 1
             , "menus", g_ALCbMenus.Value = 1, "altocr", g_ALCbAltOcr.Value = 1
             , "visuals", g_ALCbVisuals.Value = 1, "ocrtext", g_ALCbOcrScan.Value = 1)
}

AppLearner_LearnSelected() {
    global g_ALWinLV, g_ALWinHwnds
    row := g_ALWinLV.GetNext()
    if (!row || row > g_ALWinHwnds.Length) {
        MsgBoxTop("Select a window in the list first.", "App Learner")
        return
    }
    AppLog_Open()      ; live console narrates every element as it is learned
    ShowStatus("Learning window... (watch the App Learner Console)", "wait")
    AppMap_LearnWindow(g_ALWinHwnds[row], AppLearner_LearnOpts())
    AppLearner_RefreshApps()
}

AppLearner_LearnAll() {
    global g_ALWinHwnds
    opts := AppLearner_LearnOpts()
    ; The Alt+OCR walk drives each window live (activates it, opens its menus
    ; with the keyboard). In bulk that means every window in turn - confirm.
    if opts["altocr"] {
        r := MsgBoxTop("Alt+OCR menu walk is ON. Bulk learning will activate EVERY window "
            . "in turn and open its menus with the keyboard to read them - hands off the "
            . "mouse and keyboard until it finishes.`n`nYes = walk menus in every window"
            . "`nNo = bulk learn without the live menu walk (Win32 menus still read)"
            . "`nCancel = abort", "Learn ALL Windows", "YesNoCancel Icon?")
        if (r = "Cancel")
            return
        if (r = "No")
            opts["altocr"] := false
    }
    AppLog_Open()
    AppLearner_RefreshWindows()
    AppLog("════════ BULK LEARN: " . g_ALWinHwnds.Length . " windows ════════"
         . (opts["altocr"] ? "  (with live Alt+OCR menu walking)" : "  (Alt+OCR menu walk off)"))
    total := 0
    for i, hwnd in g_ALWinHwnds {
        if !WinExist("ahk_id " . hwnd) {
            AppLog("── window " . i . "/" . g_ALWinHwnds.Length . ": gone, skipped")
            continue
        }
        AppLog("── window " . i . "/" . g_ALWinHwnds.Length . " ──")
        c := AppMap_LearnWindow(hwnd, opts)
        if c.Count
            total++
    }
    AppLog("════════ BULK LEARN DONE: " . total . " windows saved to appmap.db ════════")
    ShowStatus("Bulk learn complete: " . total . " windows saved to appmap.db", "ok")
    AppLearner_RefreshApps()
}

; ─── learned apps + elements ─────────────────────────────────────────────────
AppLearner_RefreshApps() {
    global g_ALAppDD, g_ALAppIds
    apps := AppMap_Apps()
    names := []
    g_ALAppIds := []
    for a in apps {
        names.Push(TrackEllipsis(a["name"], 30) . "  [" . a["exe"] . ", " . a["elements"] . " el]")
        g_ALAppIds.Push(a["id"])
    }
    g_ALAppDD.Delete()
    if names.Length {
        g_ALAppDD.Add(names)
        g_ALAppDD.Choose(1)
    }
    AppLearner_RefreshElements()
}

AppLearner_CurrentAppId() {
    global g_ALAppDD, g_ALAppIds
    idx := g_ALAppDD.Value
    return (idx >= 1 && idx <= g_ALAppIds.Length) ? g_ALAppIds[idx] : 0
}

AppLearner_RefreshElements() {
    global g_ALElemLV, g_ALFilterEdit, g_ALKindDD
    g_ALElemLV.Delete()
    appId := AppLearner_CurrentAppId()
    if !appId
        return
    kind := g_ALKindDD.Text
    els := AppMap_Elements(appId, kind, Trim(g_ALFilterEdit.Value))
    for e in els {
        pathCol := (e["menu_path"] != "" ? e["menu_path"] : e["class_nn"])
        g_ALElemLV.Add(, e["id"], e["kind"], TrackEllipsis(e["name"], 40)
                     , TrackEllipsis(pathCol, 48), e["shortcut"], e["alt_keys"], e["x"], e["y"])
    }
}

AppLearner_SelectedElement() {
    global g_ALElemLV
    row := g_ALElemLV.GetNext()
    if !row
        return Map()
    id := g_ALElemLV.GetText(row, 1)
    if !IsInteger(id)
        return Map()
    db := AppMapDB()
    return db ? db.QueryRow("SELECT * FROM ui_element WHERE id=?", Integer(id)) : Map()
}

AppLearner_HighlightRow(row) {
    el := AppLearner_SelectedElement()
    if !el.Count {
        ShowStatus("Select an element row first", "wait")
        return
    }
    app := AppMap_AppRow(el["app_id"])
    loc := AppMap_Locate(app, el)
    if !loc.Count {
        ShowStatus("Cannot locate '" . el["name"] . "' right now", "fail")
        return
    }
    HighlightRegion(loc["x"], loc["y"], loc["w"], loc["h"], 2000, "highlight"
                  , el["name"] . " (" . loc["method"] . ")")
}

AppLearner_TestClick() {
    el := AppLearner_SelectedElement()
    if !el.Count {
        ShowStatus("Select an element row first", "wait")
        return
    }
    app := AppMap_AppRow(el["app_id"])
    if (el["kind"] = "menuitem" || el["kind"] = "menuitem-ocr")
        AppAct_Menu(app, el)
    else {
        AppAct_Focus(app)
        AppAct_Click(app, el)
    }
}

AppLearner_CopyRef() {
    global g_ALScriptEdit
    el := AppLearner_SelectedElement()
    if !el.Count
        return
    if (el["menu_path"] != "" && el["kind"] != "menu")
        ref := "menu " . el["menu_path"]
    else
        ref := "click #" . el["id"]
    A_Clipboard := ref
    ShowStatus("Copied:  " . ref, "ok")
}

AppLearner_DeleteApp() {
    appId := AppLearner_CurrentAppId()
    if !appId
        return
    app := AppMap_AppRow(appId)
    result := MsgBoxTop("Delete learned app '" . app["name"] . "' and all its elements?"
                      , "App Learner", "YesNo Icon?")
    if (result = "Yes") {
        AppMap_DeleteApp(appId)
        AppLearner_RefreshApps()
    }
}

AppLearner_ExportJson() {
    global DATA_DIR
    appId := AppLearner_CurrentAppId()
    if !appId
        return
    app := AppMap_AppRow(appId)
    safe := RegExReplace(app["exe"], "\W", "_")
    path := DATA_DIR . "\appmap_" . safe . ".json"
    n := AppMap_ExportJson(appId, path)
    ShowStatus("Exported " . n . " elements → " . path, "ok")
    try Run("explore /select,`"" . path . "`"")
}

AppLearner_ShowPrompt() {
    appId := AppLearner_CurrentAppId()
    if !appId
        return
    text := AppMap_BuildLLMPrompt(appId)
    A_Clipboard := text
    AppLearner_TextViewer("LLM Instruction Sheet (copied to clipboard)", text)
}

AppLearner_ShowCatalog() {
    appId := AppLearner_CurrentAppId()
    if !appId
        return
    AppLearner_TextViewer("Learned Catalog", AppMap_Catalog(appId))
}

AppLearner_ShowGuide() {
    global APPDSL_GUIDE
    AppLearner_TextViewer("AppDSL Guide", APPDSL_GUIDE)
}

AppLearner_CopyPrompt() {
    appId := AppLearner_CurrentAppId()
    if !appId {
        ShowStatus("Select a learned app first", "wait")
        return
    }
    A_Clipboard := AppMap_BuildLLMPrompt(appId)
    ShowStatus("Full LLM instruction sheet copied - paste it into any chat model", "ok")
}

AppLearner_TextViewer(title, text) {
    v := Gui("+Resize", title)
    ed := v.Add("Edit", "x5 y5 w780 h560 ReadOnly Multi VScroll -Wrap")
    ed.SetFont("s9", "Consolas")
    ed.Value := text
    v.Add("Button", "x5 y572 w110 h26", "Copy All").OnEvent("Click", (*) => (A_Clipboard := text, ShowStatus("Copied", "ok")))
    v.OnEvent("Escape", (*) => v.Destroy())
    v.Show("w790 h605")
}

; ─── script + ollama handlers ────────────────────────────────────────────────
AppLearner_RunScript() {
    global g_ALScriptEdit
    ; No learned app selected is fine: window-agnostic commands (run, keys,
    ; type, ocrclick, menupick...) drive the active window; only app-scoped
    ; refs (focus / click <name> / menu <path>) need a selection.
    appId := AppLearner_CurrentAppId()
    script := g_ALScriptEdit.Value
    if (Trim(script) = "")
        return
    SetTimer(() => AppExec_Run(appId, script), -50)   ; keep the GUI responsive
}

AppLearner_LoadDemo() {
    global g_ALScriptEdit, g_ALDemoDD
    n := g_ALDemoDD.Value
    g_ALScriptEdit.Value := AppLearner_DemoScript(n)
    ShowStatus("Demo " . n . " loaded - review it, then press ▶ Run Script (hands off while it runs)", "ok")
}

AppLearner_TestOllama() {
    global g_ALOllamaUrl, g_ALOllamaStatus
    url := Trim(g_ALOllamaUrl.Value)
    AppMap_SetSetting("ollama_url", url)
    ver := Ollama_Ping(url)
    if (ver != "") {
        g_ALOllamaStatus.Value := "✓ Ollama " . ver . " is running at " . url
        ShowStatus("Ollama " . ver . " reachable", "ok")
    } else {
        g_ALOllamaStatus.Value := "✗ No Ollama server at " . url . " - is 'ollama serve' running?"
        ShowStatus("Ollama not reachable", "fail")
    }
}

AppLearner_AskOllama(autoRun := false) {
    global g_ALGoalEdit, g_ALOllamaUrl, g_ALOllamaModel, g_ALOllamaStatus, g_ALScriptEdit
    appId := AppLearner_CurrentAppId()
    if !appId {
        MsgBoxTop("Select a learned app first (box 2).", "App Learner")
        return
    }
    goal := Trim(g_ALGoalEdit.Value)
    if (goal = "") {
        MsgBoxTop("Describe the goal first.", "App Learner")
        return
    }
    url := Trim(g_ALOllamaUrl.Value)
    model := Trim(g_ALOllamaModel.Value)
    AppMap_SetSetting("ollama_url", url)
    AppMap_SetSetting("ollama_model", model)

    g_ALOllamaStatus.Value := "⏳ Asking " . model . "... (generation can take a minute)"
    ShowStatus("Waiting for Ollama (" . model . ")...", "wait")
    ; WinHttp blocks; run in a timer thread so the click handler returns first.
    SetTimer(() => AppLearner_AskOllamaWork(appId, goal, model, url, autoRun), -50)
}

AppLearner_AskOllamaWork(appId, goal, model, url, autoRun) {
    global g_ALOllamaStatus, g_ALScriptEdit
    err := ""
    script := Ollama_GenerateScript(appId, goal, model, url, &err)
    if (script = "") {
        g_ALOllamaStatus.Value := "✗ " . (err != "" ? err : "Model returned no usable AppDSL lines")
        ShowStatus("Ollama generation failed", "fail")
        return
    }
    g_ALScriptEdit.Value := script
    lines := StrSplit(script, "`n").Length
    g_ALOllamaStatus.Value := "✓ " . lines . " command(s) generated - review in box 3" . (autoRun ? ", running now" : "")
    ShowStatus("Ollama generated " . lines . " AppDSL lines", "ok")
    if autoRun
        AppExec_Run(appId, script)
}
