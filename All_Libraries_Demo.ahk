#Requires AutoHotkey v2.0
#SingleInstance Force

#Include "SQLiteDB.ahk"
#Include "Acc.ahk"
#Include "FindText.ahk"
#Include "AHKv2_Screenshotter.ahk"
;iiii
SetWorkingDir(A_ScriptDir)
CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")

DemoState := {
    Gui: 0,
    Tabs: 0,
    Log: 0,
    AccName: 0,
    AccHook: 0,
    LastAcc: 0,
    FindPattern: 0,
    LastFind: [],
    SQLiteCallbackRows: []
}

if A_Args.Length && (A_Args[1] = "--self-test") {
    RunSelfTest()
    ExitApp()
}
if A_Args.Length && (A_Args[1] = "--sqlite-demo") {
    RunSQLiteDemo()
    ExitApp()
}
if A_Args.Length && (A_Args[1] = "--gui-smoke") {
    BuildDemoGui(false)
    FileAppend("GUI BUILD: passed`n", "*")
    ExitApp()
}

BuildDemoGui()
return

BuildDemoGui(showWindow := true) {
    global DemoState

    demoGui := Gui("+Resize +MinSize850x650", "AutoHotkey Library Collection — Integrated Demo")
    demoGui.SetFont("s10", "Segoe UI")
    demoGui.OnEvent("Close", (*) => ExitApp())
    demoGui.OnEvent("Size", ResizeDemo)

    tabs := demoGui.Add("Tab3", "x15 y15 w940 h480", [
        "Overview", "SQLiteDB", "Acc", "FindText", "Screenshotter", "Vis2 + MCode"
    ])

    tabs.UseTab("Overview")
    demoGui.Add("Text", "x35 y60 w885 h80", "This is an AutoHotkey v2 orchestrator. SQLiteDB, Acc, FindText, and Screenshotter are included directly. Vis2 is launched with AutoHotkey v1, and ahkmcodegen is launched as its own v2 GUI because neither is include-safe in this process.")
    AddDemoButton(demoGui, "Run non-destructive smoke test", 35, 155, 250, RunSelfTestToLog)
    AddDemoButton(demoGui, "Open AccViewer separately", 300, 155, 220, LaunchAccViewer)
    AddDemoButton(demoGui, "Launch original Vis2 demo", 535, 155, 220, LaunchVis2Demo)
    AddDemoButton(demoGui, "Launch ahkmcodegen", 770, 155, 170, LaunchMCodeGen)
    demoGui.Add("Text", "x35 y215 w885 h180", "Suggested tour:`n`n1. Run the SQLite demo; it is entirely in memory.`n2. Inspect the active window or the object under the mouse with Acc.`n3. Open FindText Capture, generate a pattern, paste it into the pattern box, and search.`n4. Exercise each screenshot mode; active-window actions provide a short switch-window countdown.`n5. Launch the v1 Vis2 demo (Win+C OCR, Win+I image labels, Esc exits).`n6. Launch ahkmcodegen and select a C compiler, GNU assembler, and C source file.")

    tabs.UseTab("SQLiteDB")
    demoGui.Add("Text", "x35 y60 w885 h65", "The comprehensive in-memory example exercises SQL execution callbacks, transactions, typed prepared bindings (text, integer, double, BLOB, and NULL), result-table and prepared-row iteration, escaping, counters, REGEXP, and attach/detach.")
    AddDemoButton(demoGui, "Run full in-memory SQLite demo", 35, 140, 280, RunSQLiteDemo)
    AddDemoButton(demoGui, "Load a trusted SQLite extension…", 330, 140, 280, LoadSQLiteExtensionDemo)
    demoGui.Add("Text", "x35 y205 w885 h145", "The optional extension action asks you to choose a native DLL. Only use an extension you trust, and make sure its architecture matches AutoHotkey. The in-memory example creates no database file and closes every prepared statement and callback before closing the connection.")

    tabs.UseTab("Acc")
    demoGui.Add("Text", "x35 y60 w885 h55", "MSAA availability varies by application. Move the mouse over a target before using point inspection. Name search uses the active window's accessibility subtree.")
    AddDemoButton(demoGui, "Inspect active window", 35, 125, 200, InspectActiveAcc)
    AddDemoButton(demoGui, "Inspect under mouse", 250, 125, 200, InspectMouseAcc)
    AddDemoButton(demoGui, "Enumerate first 25 children", 465, 125, 225, EnumerateActiveAcc)
    AddDemoButton(demoGui, "Open AccViewer separately", 705, 125, 225, LaunchAccViewer)
    demoGui.Add("Text", "x35 y190 w120 h25", "Name contains:")
    DemoState.AccName := demoGui.Add("Edit", "x155 y187 w300", "")
    AddDemoButton(demoGui, "Find + highlight", 470, 185, 155, FindAccByName)
    AddDemoButton(demoGui, "Run default action", 640, 185, 160, InvokeLastAcc)
    AddDemoButton(demoGui, "Clear highlights", 815, 185, 125, ClearAccHighlights)
    AddDemoButton(demoGui, "Start foreground event hook", 35, 245, 235, StartAccEvents)
    AddDemoButton(demoGui, "Stop event hook", 285, 245, 165, StopAccEvents)
    demoGui.Add("Text", "x35 y305 w885 h90", "The found element is retained so its path, properties, highlight, and default action can be demonstrated. The action button always asks for confirmation. The event hook is retained in DemoState until stopped; destroying that object unhooks it.")

    tabs.UseTab("FindText")
    demoGui.Add("Text", "x35 y55 w885 h35", "Paste one or more generated FindText patterns below. Use the capture GUI to create patterns from a stable on-screen target.")
    DemoState.FindPattern := demoGui.Add("Edit", "x35 y90 w885 h100 +Multi WantTab", "")
    AddDemoButton(demoGui, "Open Capture GUI", 35, 205, 155, OpenFindTextGui)
    AddDemoButton(demoGui, "Find now", 205, 205, 110, FindTextNow)
    AddDemoButton(demoGui, "Wait 3s: appear", 330, 205, 145, FindTextWaitAppear)
    AddDemoButton(demoGui, "Wait 3s: disappear", 490, 205, 160, FindTextWaitDisappear)
    AddDemoButton(demoGui, "Sort + pattern OCR", 665, 205, 170, SummarizeFindText)
    AddDemoButton(demoGui, "Click first match", 850, 205, 90, ClickFindTextMatch)
    AddDemoButton(demoGui, "Inspect color + hash at mouse", 35, 260, 240, InspectFindTextPixels)
    AddDemoButton(demoGui, "Save 200×200 around mouse", 290, 260, 225, SaveFindTextRegion)
    AddDemoButton(demoGui, "Show 200×200 screenshot", 530, 260, 210, ShowFindTextRegion)
    AddDemoButton(demoGui, "Wait 3s for region change", 755, 260, 185, WaitFindTextChange)
    demoGui.Add("Text", "x35 y325 w885 h85", "FindText's Ocr() combines the IDs/comments of matched patterns; it is not Tesseract OCR. Search output includes top-left x/y, width/height, center mx/my, and the pattern ID. Saved debug images are BMP files under FindTextCaptures.")

    tabs.UseTab("Screenshotter")
    demoGui.Add("Text", "x35 y60 w885 h65", "Each operation saves a timestamped PNG in Screenshots and logs the returned path. For active-window captures the demo hides for three seconds so you can activate a target window.")
    AddDemoButton(demoGui, "Whole screen", 35, 140, 170, CaptureWholeScreenDemo)
    AddDemoButton(demoGui, "Active window", 220, 140, 170, CaptureActiveWindowDemo)
    AddDemoButton(demoGui, "Active client area", 405, 140, 180, CaptureActiveClientDemo)
    AddDemoButton(demoGui, "Rendered window", 600, 140, 170, CaptureRenderedWindowDemo)
    AddDemoButton(demoGui, "Rendered client", 785, 140, 155, CaptureRenderedClientDemo)
    demoGui.Add("Text", "x35 y215 w885 h150", "Rendered capture uses undocumented PrintWindow flags and is deliberately guarded by the warning in AHKv2_Screenshotter. It can be more accurate for some applications but is slower and not guaranteed. The lower-level AHKv2_Screenshot_Tools library also supports regions, cursor capture, bitmaps, and HBITMAP operations.")

    tabs.UseTab("Vis2 + MCode")
    demoGui.Add("Text", "x35 y60 w885 h100", "Vis2 uses AutoHotkey v1 syntax. The launcher locates an installed v1 interpreter and starts demo.ahk, which OCRs test.jpg and then provides Win+C for interactive OCR and Win+I for Google Cloud Vision image labels. ImageIdentify needs network access and a valid Vis2_API.txt key.")
    AddDemoButton(demoGui, "Launch Vis2 v1 demo", 35, 175, 220, LaunchVis2Demo)
    AddDemoButton(demoGui, "Launch ahkmcodegen v2", 270, 175, 230, LaunchMCodeGen)
    demoGui.Add("Text", "x35 y240 w885 h145", "ahkmcodegen is a complete GUI module suite, not an include-only library. Configure a C source, GCC/Clang, and GNU as; choose compile/output options; then compile and copy the generated MCode. It may create intermediate build files beside your C source and can update a configured AHK source file, so test automatic insertion on a backed-up file.")

    tabs.UseTab()
    demoGui.Add("Text", "x15 y505 w80 h25", "Activity log")
    log := demoGui.Add("Edit", "x15 y530 w940 h150 +Multi +ReadOnly -Wrap VScroll", "Ready. See README.md for the full API guide.")

    DemoState.Gui := demoGui
    DemoState.Tabs := tabs
    DemoState.Log := log
    if showWindow
        demoGui.Show("w970 h700")
}

AddDemoButton(guiObj, label, x, y, width, callback) {
    button := guiObj.Add("Button", "x" x " y" y " w" width " h32", label)
    button.OnEvent("Click", callback)
    return button
}

ResizeDemo(guiObj, minMax, width, height) {
    global DemoState
    if (minMax = -1) || !DemoState.Log
        return
    try DemoState.Tabs.Move(, , Max(810, width - 30), Max(430, height - 220))
    try DemoState.Log.Move(15, Max(490, height - 170), Max(810, width - 30), 140)
}

WriteLog(message, clear := false) {
    global DemoState
    timestamp := FormatTime(, "HH:mm:ss")
    line := "[" timestamp "] " message
    if DemoState.Log {
        if clear
            DemoState.Log.Value := line
        else
            DemoState.Log.Value .= "`r`n" line
        SendMessage(0x0115, 7, 0, DemoState.Log.Hwnd) ; WM_VSCROLL / SB_BOTTOM
    } else {
        FileAppend(line "`n", "*")
    }
}

ErrorText(errorObject) {
    return errorObject.Message " (" errorObject.File ":" errorObject.Line ")"
}

CheckDb(ok, db, operation) {
    if !ok
        throw Error(operation " failed: [" db.ErrorCode "] " db.ErrorMsg)
}

RunSQLiteDemo(*) {
    global DemoState
    db := SQLiteDB(), statement := 0, regexCallback := 0
    report := []
    DemoState.SQLiteCallbackRows := []
    WriteLog("Starting comprehensive in-memory SQLite demo…", true)

    try {
        CheckDb(db.OpenDB(":memory:"), db, "OpenDB")
        CheckDb(db.SetTimeout(1500), db, "SetTimeout")
        report.Push("SQLite " SQLiteDB.Version)

        CheckDb(db.Exec("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT, qty INTEGER, score REAL, payload BLOB, note TEXT)"), db, "create table")
        CheckDb(db.Exec("BEGIN IMMEDIATE"), db, "begin transaction")
        CheckDb(db.Prepare("INSERT INTO items(name, qty, score, payload, note) VALUES (?, ?, ?, ?, ?)" , &statement), db, "prepare insert")

        blob := Buffer(4)
        NumPut("UInt", 0x1234ABCD, blob)
        CheckDb(statement.Bind([
            Map("Text", "Ada"), Map("Int", 3), Map("Double", 98.5), Map("Blob", blob), Map("Null", 0)
        ]), statement, "bind first row")
        if statement.Step() != -1
            throw Error("Prepared INSERT did not reach SQLITE_DONE")

        CheckDb(statement.Reset(), statement, "reset insert")
        CheckDb(statement.Bind([
            Map("Text", "Grace"), Map("Int64", 7), Map("Double", 99.25), Map("Blob", Buffer(0)), Map("Text", "compiler")
        ]), statement, "bind second row")
        if statement.Step() != -1
            throw Error("Second prepared INSERT did not reach SQLITE_DONE")
        CheckDb(statement.Free(), statement, "free insert")
        statement := 0

        escapedName := "O'Reilly"
        CheckDb(db.EscapeStr(&escapedName), db, "EscapeStr")
        CheckDb(db.Exec("INSERT INTO items(name, qty, score, note) VALUES (" escapedName ", 2, 91.0, 'escaped')"), db, "escaped insert")
        CheckDb(db.Exec("COMMIT"), db, "commit transaction")

        CheckDb(db.LastInsertRowID(&lastId), db, "LastInsertRowID")
        CheckDb(db.TotalChanges(&totalChanges), db, "TotalChanges")
        report.Push("last rowid=" lastId ", total changes=" totalChanges ", last Exec changes=" db.Changes)

        CheckDb(db.GetTable("SELECT id, name, qty, score, length(payload), coalesce(note, '<NULL>') FROM items ORDER BY id", &table), db, "GetTable")
        report.Push("GetTable: " table.RowCount " rows / " table.ColumnCount " columns")
        table.Reset()
        while (table.Next(&row) = true)
            report.Push("table row: " JoinValues(row))

        CheckDb(db.Exec("SELECT id, name FROM items ORDER BY id", SQLiteExecCallback), db, "Exec callback")
        report.Push("Exec callback rows: " DemoState.SQLiteCallbackRows.Length)

        CheckDb(db.Prepare("SELECT name, qty, score, payload, note FROM items WHERE qty >= ? ORDER BY qty", &statement), db, "prepare select")
        CheckDb(statement.Bind([Map("Int", 2)]), statement, "bind select")
        report.Push("prepared columns: " JoinValues(statement.ColumnNames))
        Loop {
            status := statement.Next(&row)
            if status = -1
                break
            if !status
                throw Error("prepared select failed: " statement.ErrorMsg)
            report.Push("prepared row: " JoinValues(row))
        }
        CheckDb(statement.Reset(false), statement, "reset select without clearing bindings")
        CheckDb(statement.Free(), statement, "free select")
        statement := 0

        regexCallback := CallbackCreate(SQLiteDB_RegExp, "C", 3)
        CheckDb(db.CreateScalarFunc("REGEXP", 2, regexCallback), db, "CreateScalarFunc")
        CheckDb(db.GetTable("SELECT name FROM items WHERE REGEXP('^G', name)", &regexTable), db, "REGEXP query")
        report.Push("REGEXP ^G: " (regexTable.RowCount ? regexTable.Rows[1][1] : "no match"))

        CheckDb(db.AttachDB(":memory:", "aux"), db, "AttachDB")
        CheckDb(db.Exec("CREATE TABLE aux.audit(message TEXT); INSERT INTO aux.audit VALUES ('attached database works')"), db, "write attached database")
        CheckDb(db.GetTable("SELECT message FROM aux.audit", &auxTable), db, "read attached database")
        report.Push("attached DB: " auxTable.Rows[1][1])
        CheckDb(db.DetachDB("aux"), db, "DetachDB")

        report.Push("extended error code=" db.ExtErrCode())
        WriteLog(JoinValues(report, "`r`n"))
    } catch as err {
        WriteLog("SQLite demo ERROR: " ErrorText(err))
    } finally {
        if statement {
            try statement.Free()
        }
        try db.CloseDB()
        if regexCallback
            CallbackFree(regexCallback)
    }
}

SQLiteExecCallback(databaseObjectPointer, columnCount, valuePointers, namePointers) {
    global DemoState
    row := []
    Loop columnCount {
        offset := (A_Index - 1) * A_PtrSize
        namePtr := NumGet(namePointers + offset, "UPtr")
        valuePtr := NumGet(valuePointers + offset, "UPtr")
        name := namePtr ? StrGet(namePtr, "UTF-8") : "column" A_Index
        value := valuePtr ? StrGet(valuePtr, "UTF-8") : "NULL"
        row.Push(name "=" value)
    }
    DemoState.SQLiteCallbackRows.Push(row)
    return 0
}

LoadSQLiteExtensionDemo(*) {
    selected := FileSelect(1, A_ScriptDir, "Select a trusted SQLite extension", "DLL (*.dll)")
    if !selected
        return
    if MsgBox("Native SQLite extensions execute code inside this process. Load this trusted DLL?`n`n" selected, "Confirm extension", "YesNo Icon!") != "Yes"
        return

    db := SQLiteDB()
    try {
        CheckDb(db.OpenDB(":memory:"), db, "OpenDB")
        CheckDb(db.EnableLoadExtension(true), db, "EnableLoadExtension")
        CheckDb(db.LoadExtension(selected), db, "LoadExtension")
        WriteLog("Loaded SQLite extension: " selected)
    } catch as err {
        WriteLog("SQLite extension ERROR: " ErrorText(err))
    } finally {
        try db.EnableLoadExtension(false)
        try db.CloseDB()
    }
}

JoinValues(values, delimiter := " | ") {
    text := ""
    for index, value in values {
        if index > 1
            text .= delimiter
        if value is Buffer
            text .= "<BLOB " value.Size " bytes>"
        else
            text .= value
    }
    return text
}

InspectActiveAcc(*) {
    global DemoState
    hwnd := AcquireTargetWindow("Activate the window to inspect")
    try {
        element := Acc.ElementFromHandle(hwnd)
        WriteLog("Active accessibility element:`r`n" DescribeAcc(element), true)
    } catch as err {
        WriteLog("Acc active-window ERROR: " ErrorText(err))
    } finally {
        DemoState.Gui.Show()
    }
}

InspectMouseAcc(*) {
    global DemoState
    point := AcquireTargetPoint("Move the mouse over an accessible element")
    try {
        element := Acc.ElementFromPoint(point.x, point.y)
        DemoState.LastAcc := element
        element.Highlight(-1800, "Lime", 3)
        WriteLog("Element at " point.x "," point.y ":`r`n" DescribeAcc(element), true)
    } catch as err {
        WriteLog("Acc point ERROR: " ErrorText(err))
    } finally {
        DemoState.Gui.Show()
    }
}

EnumerateActiveAcc(*) {
    global DemoState
    hwnd := AcquireTargetWindow("Activate the window whose children should be enumerated")
    try {
        root := Acc.ElementFromHandle(hwnd)
        lines := ["Active root: " SafeAccProperty(root, "Name")]
        count := 0
        for index, child in root {
            count++
            lines.Push(index ". " SafeAccProperty(child, "RoleText") " — " SafeAccProperty(child, "Name"))
            if count >= 25
                break
        }
        lines.Push("Immediate children reported by Length: " root.Length)
        WriteLog(JoinValues(lines, "`r`n"), true)
    } catch as err {
        WriteLog("Acc enumeration ERROR: " ErrorText(err))
    } finally {
        DemoState.Gui.Show()
    }
}

FindAccByName(*) {
    global DemoState
    needle := Trim(DemoState.AccName.Value)
    if !needle {
        MsgBox("Enter part of an accessible element name first.", "Acc search")
        return
    }
    hwnd := AcquireTargetWindow("Activate the window whose accessibility tree should be searched")
    try {
        root := Acc.ElementFromHandle(hwnd)
        found := root.FindElement({Name: needle, mm: "Substring", cs: false}, "Subtree")
        if !found {
            WriteLog("No accessible element name contained: " needle)
            return
        }
        DemoState.LastAcc := found
        path := root.GetPath(found)
        found.Highlight(-2500, "Lime", 3)
        WriteLog("Acc match; path=" path "`r`n" DescribeAcc(found), true)
    } catch as err {
        WriteLog("Acc search ERROR: " ErrorText(err))
    } finally {
        DemoState.Gui.Show()
    }
}

AcquireTargetWindow(instruction) {
    global DemoState
    DemoState.Gui.Hide()
    ToolTip(instruction " — sampling in 3 seconds…", 20, 20)
    Sleep(3000)
    hwnd := WinExist("A")
    ToolTip()
    return hwnd
}

AcquireTargetPoint(instruction) {
    global DemoState
    DemoState.Gui.Hide()
    ToolTip(instruction " — sampling in 3 seconds…", 20, 20)
    Sleep(3000)
    MouseGetPos(&x, &y)
    ToolTip()
    return {x: x, y: y}
}

InvokeLastAcc(*) {
    global DemoState
    if !DemoState.LastAcc {
        MsgBox("Inspect or find an accessibility element first.", "Acc action")
        return
    }
    description := DescribeAcc(DemoState.LastAcc)
    if MsgBox("Run the element's default action? This may click, open, or change the target application.`n`n" description, "Confirm Acc action", "YesNo Icon!") != "Yes"
        return
    try {
        DemoState.LastAcc.DoDefaultAction()
        WriteLog("Ran Acc.DoDefaultAction on the retained element.")
    } catch as err {
        if MsgBox("Default action failed:`n" err.Message "`n`nTry a coordinate click instead?", "Acc fallback", "YesNo Icon?") = "Yes" {
            try DemoState.LastAcc.Click()
            catch as clickError
                WriteLog("Acc click ERROR: " ErrorText(clickError))
        } else {
            WriteLog("Acc default-action ERROR: " ErrorText(err))
        }
    }
}

ClearAccHighlights(*) {
    Acc.ClearHighlights()
    WriteLog("Cleared all Acc highlights.")
}

StartAccEvents(*) {
    global DemoState
    if DemoState.AccHook {
        WriteLog("The foreground Acc event hook is already active.")
        return
    }
    try {
        DemoState.AccHook := Acc.RegisterWinEvent(AccForegroundEvent, Acc.Event.System_Foreground)
        WriteLog("Started Acc.System_Foreground event hook. Activate another window to test it.")
    } catch as err {
        WriteLog("Acc event-hook ERROR: " ErrorText(err))
    }
}

StopAccEvents(*) {
    global DemoState
    DemoState.AccHook := 0
    WriteLog("Stopped the Acc foreground event hook.")
}

AccForegroundEvent(element, info) {
    eventName := info.Event
    try eventName := Acc.Event[info.Event]
    try WriteLog("Acc event " eventName ": hwnd=" info.WinID ", name=" SafeAccProperty(element, "Name"))
}

DescribeAcc(element) {
    properties := ["Name", "Value", "RoleText", "StateText", "DefaultAction", "KeyboardShortcut", "ChildId", "ControlID", "WinID", "Length", "Exists"]
    lines := []
    for propertyName in properties
        lines.Push(propertyName ": " SafeAccProperty(element, propertyName))
    try {
        location := element.GetLocation("screen")
        lines.Push("Location: x=" location.x ", y=" location.y ", w=" location.w ", h=" location.h)
    }
    return JoinValues(lines, "`r`n")
}

SafeAccProperty(element, propertyName) {
    try return element.%propertyName%
    catch
        return "N/A"
}

LaunchAccViewer(*) {
    try {
        command := QuoteArg(A_AhkPath) " " QuoteArg(A_ScriptDir "\Acc.ahk")
        Run(command, A_ScriptDir)
        WriteLog("Launched AccViewer in a separate process.")
    } catch as err {
        WriteLog("AccViewer launch ERROR: " ErrorText(err))
    }
}

OpenFindTextGui(*) {
    try {
        FindText().Gui("Show")
        WriteLog("Opened the FindText capture GUI.")
    } catch as err {
        WriteLog("FindText GUI ERROR: " ErrorText(err))
    }
}

FindTextNow(*) {
    SearchFindText("")
}

FindTextWaitAppear(*) {
    SearchFindText("wait")
}

FindTextWaitDisappear(*) {
    SearchFindText("wait0")
}

SearchFindText(waitMode) {
    global DemoState
    pattern := Trim(DemoState.FindPattern.Value)
    if !pattern {
        MsgBox("Open the FindText capture GUI, create a pattern, and paste it into the pattern box first.", "FindText")
        return
    }

    DemoState.Gui.Hide()
    ToolTip("Expose the FindText target — search starts in 2 seconds…", 20, 20)
    Sleep(2000)
    ToolTip()
    try {
        if waitMode {
            x := waitMode, y := 3
            result := FindText(&x, &y, 0, 0, 0, 0, 0.10, 0.10, pattern)
            if (waitMode = "wait0") {
                DemoState.LastFind := []
                WriteLog(result ? "FindText target disappeared within 3 seconds." : "FindText disappear wait timed out.")
                return
            }
            matches := result ? result : []
        } else {
            matches := FindText(&x, &y, 0, 0, 0, 0, 0.10, 0.10, pattern)
        }
        DemoState.LastFind := matches
        if !matches.Length {
            WriteLog("FindText returned no matches.")
            return
        }
        first := matches[1]
        FindText().RangeTip(first.x, first.y, first.w, first.h, "Lime", 3)
        SetTimer((*) => FindText().RangeTip(), -2200)
        WriteLog("FindText found " matches.Length " match(es). First: x=" first.x ", y=" first.y ", w=" first.w ", h=" first.h ", center=" first.mx "," first.my ", id=" first.id, true)
    } catch as err {
        WriteLog("FindText search ERROR: " ErrorText(err))
    } finally {
        DemoState.Gui.Show()
    }
}

SummarizeFindText(*) {
    global DemoState
    if !DemoState.LastFind.Length {
        MsgBox("Run a successful FindText search first.", "FindText")
        return
    }
    try {
        sorted := FindText().Sort(DemoState.LastFind)
        nearest := FindText().Sort2(DemoState.LastFind, A_ScreenWidth // 2, A_ScreenHeight // 2)
        directional := FindText().Sort3(DemoState.LastFind, 1)
        ocr := FindText().Ocr(sorted)
        WriteLog("FindText result processing:`r`nreading-order count=" sorted.Length "`r`nnearest-to-primary-center id=" nearest[1].id "`r`ndirectional first id=" directional[1].id "`r`npattern OCR text=" ocr.text, true)
    } catch as err {
        WriteLog("FindText result-processing ERROR: " ErrorText(err))
    }
}

ClickFindTextMatch(*) {
    global DemoState
    if !DemoState.LastFind.Length {
        MsgBox("Run a successful FindText search first.", "FindText")
        return
    }
    match := DemoState.LastFind[1]
    if MsgBox("Click the center of the first FindText match at " match.mx "," match.my "?", "Confirm click", "YesNo Icon!") != "Yes"
        return
    FindText().Click(match.mx, match.my)
    WriteLog("Clicked the first FindText match.")
}

InspectFindTextPixels(*) {
    global DemoState
    point := AcquireTargetPoint("Move the mouse to the pixel/region to inspect")
    try {
        ft := FindText()
        ft.ScreenShot(point.x - 50, point.y - 50, point.x + 50, point.y + 50)
        color := ft.GetColor(point.x, point.y)
        hash := ft.GetPicHash(point.x - 50, point.y - 50, point.x + 50, point.y + 50, 0)
        ft.MouseTip(point.x, point.y, 8, 8, 3)
        WriteLog("FindText pixel at " point.x "," point.y ": color=" color ", 101×101 retained-screen hash=" hash)
    } catch as err {
        WriteLog("FindText pixel/hash ERROR: " ErrorText(err))
    } finally {
        DemoState.Gui.Show()
    }
}

SaveFindTextRegion(*) {
    global DemoState
    point := AcquireTargetPoint("Move the mouse to the center of the region to save")
    try {
        directory := A_ScriptDir "\FindTextCaptures"
        if !DirExist(directory)
            DirCreate(directory)
        file := directory "\FindText-" FormatTime(, "yyyyMMdd-HHmmss") "-" A_MSec ".bmp"
        FindText().SavePic(file, point.x - 100, point.y - 100, point.x + 99, point.y + 99)
        WriteLog("Saved FindText BMP: " file)
    } catch as err {
        WriteLog("FindText SavePic ERROR: " ErrorText(err))
    } finally {
        DemoState.Gui.Show()
    }
}

ShowFindTextRegion(*) {
    global DemoState
    point := AcquireTargetPoint("Move the mouse to the center of the region to preview")
    try {
        FindText().ShowScreenShot(point.x - 100, point.y - 100, point.x + 99, point.y + 99)
        SetTimer((*) => FindText().ShowScreenShot(), -3000)
        WriteLog("Showing a FindText 200×200 screen capture for three seconds.")
    } catch as err {
        WriteLog("FindText ShowScreenShot ERROR: " ErrorText(err))
    } finally {
        DemoState.Gui.Show()
    }
}

WaitFindTextChange(*) {
    global DemoState
    point := AcquireTargetPoint("Move the mouse to the center of the region to monitor")
    try {
        ft := FindText()
        ft.ScreenShot(point.x - 50, point.y - 50, point.x + 50, point.y + 50)
        WriteLog("Waiting up to three seconds for the 101×101 region around the prior mouse position to change…")
        changed := ft.WaitChange(3, point.x - 50, point.y - 50, point.x + 50, point.y + 50)
        WriteLog(changed ? "FindText detected a region change." : "FindText region-change wait timed out.")
    } catch as err {
        WriteLog("FindText WaitChange ERROR: " ErrorText(err))
    } finally {
        DemoState.Gui.Show()
    }
}

CaptureWholeScreenDemo(*) {
    try WriteLog("Saved whole-screen capture: " CaptureWholeScreen())
    catch as err
        WriteLog("Whole-screen capture ERROR: " ErrorText(err))
}

CaptureActiveWindowDemo(*) {
    CaptureAfterCountdown(false, false)
}

CaptureActiveClientDemo(*) {
    CaptureAfterCountdown(true, false)
}

CaptureRenderedWindowDemo(*) {
    CaptureAfterCountdown(false, true)
}

CaptureRenderedClientDemo(*) {
    CaptureAfterCountdown(true, true)
}

CaptureAfterCountdown(clientOnly, rendered) {
    global DemoState
    DemoState.Gui.Hide()
    ToolTip("Activate the target window — capture in 3 seconds…", 20, 20)
    Sleep(3000)
    ToolTip()
    try {
        path := rendered ? CaptureRenderedActiveWindow(clientOnly) : CaptureActiveWindow(clientOnly)
        WriteLog(path ? "Saved " (rendered ? "rendered " : "") (clientOnly ? "client " : "window ") "capture: " path : "Capture canceled.")
    } catch as err {
        WriteLog("Window capture ERROR: " ErrorText(err))
    } finally {
        DemoState.Gui.Show()
    }
}

LaunchVis2Demo(*) {
    executable := FindAhkV1()
    if !executable {
        MsgBox("AutoHotkey v1.1 was not found in the standard install locations. Install v1.1 or edit FindAhkV1() in this demo.", "Vis2 requires AutoHotkey v1")
        return
    }
    try {
        Run(QuoteArg(executable) " " QuoteArg(A_ScriptDir "\demo.ahk"), A_ScriptDir)
        WriteLog("Launched Vis2 demo with: " executable)
    } catch as err {
        WriteLog("Vis2 launch ERROR: " ErrorText(err))
    }
}

FindAhkV1() {
    candidates := [
        "C:\Program Files\AutoHotkey\v1.1.37.02\AutoHotkeyU64.exe",
        "C:\Program Files\AutoHotkey\v1.1.37.02\AutoHotkeyU32.exe",
        A_ProgramFiles "\AutoHotkey\AutoHotkeyU64.exe",
        A_ProgramFiles "\AutoHotkey\AutoHotkey.exe"
    ]
    for candidate in candidates {
        if FileExist(candidate)
            return candidate
    }
    return ""
}

LaunchMCodeGen(*) {
    try {
        Run(QuoteArg(A_AhkPath) " " QuoteArg(A_ScriptDir "\ahkmcodegen.ahk"), A_ScriptDir)
        WriteLog("Launched ahkmcodegen as a separate AutoHotkey v2 process.")
    } catch as err {
        WriteLog("ahkmcodegen launch ERROR: " ErrorText(err))
    }
}

QuoteArg(value) {
    return '"' value '"'
}

RunSelfTestToLog(*) {
    result := RunSelfTest(false)
    WriteLog(result, true)
}

RunSelfTest(writeStdout := true) {
    global pToken
    passes := [], failures := []
    requiredFiles := [
        "SQLiteDB.ahk", "sqlite3.dll", "Acc.ahk", "FindText.ahk",
        "AHKv2_Screenshotter.ahk", "lib\AHKv2_Screenshot_Tools.ahk",
        "Vis2.ahk", "Gdip_All.ahk", "ImagePut.ahk", "JSON.ahk",
        "bin\tesseract\tesseract.exe", "bin\tesseract\tessdata_best\eng.traineddata",
        "bin\tesseract\tessdata_fast\eng.traineddata", "demo.ahk",
        "ahkmcodegen.ahk", "_cfg.ahk", "_guibase.ahk", "_tab_main.ahk",
        "_tab_opts.ahk", "_tab_out.ahk", "_get_c_function_header.ahk",
        "lib\ahk\CreateImageButton.ahk", "sample.ahk", "README.md",
        "Vis2_README.md", "AHKv2_Screenshot_Tools_README.md", "ahkmcodegen_README.md",
        "Ollama_Job_Automation_Studio_v1.2\Ollama_Job_Automation_Studio_README.md"
    ]

    for relativePath in requiredFiles {
        if FileExist(A_ScriptDir "\" relativePath)
            passes.Push("file: " relativePath)
        else
            failures.Push("missing file: " relativePath)
    }

    try {
        db := SQLiteDB()
        CheckDb(db.OpenDB(":memory:"), db, "self-test OpenDB")
        CheckDb(db.Exec("CREATE TABLE smoke (value TEXT); INSERT INTO smoke VALUES ('ok')"), db, "self-test Exec")
        CheckDb(db.GetTable("SELECT value FROM smoke", &table), db, "self-test GetTable")
        if (table.RowCount != 1) || (table.Rows[1][1] != "ok")
            throw Error("unexpected SQLite smoke-test result")
        db.CloseDB()
        passes.Push("SQLite memory database")
    } catch as err {
        failures.Push("SQLite: " ErrorText(err))
        try db.CloseDB()
    }

    accTestGui := 0
    try {
        accTestGui := Gui(, "Acc smoke-test window")
        accTestGui.Add("Text", , "Accessible text")
        accTestGui.Show("Hide")
        root := Acc.ElementFromHandle(accTestGui.Hwnd)
        if !root
            throw Error("no element returned for a known GUI hwnd")
        passes.Push("Acc known-window element (role=" SafeAccProperty(root, "RoleText") ")")
    } catch as err {
        failures.Push("Acc: " ErrorText(err))
    } finally {
        if accTestGui
            accTestGui.Destroy()
    }

    try {
        ft := FindText()
        if Type(ft) != "FindTextClass"
            throw Error("unexpected FindText object type: " Type(ft))
        passes.Push("FindText singleton")
    } catch as err {
        failures.Push("FindText: " ErrorText(err))
    }

    if pToken
        passes.Push("Screenshotter GDI+ token")
    else
        failures.Push("Screenshotter: GDI+ did not start")

    v1 := FindAhkV1()
    if v1
        passes.Push("AutoHotkey v1: " v1)
    else
        failures.Push("AutoHotkey v1 not found (required for Vis2)")

    summary := "SELF-TEST: " passes.Length " passed, " failures.Length " failed`r`n"
    if failures.Length
        summary .= "`r`nFAILURES`r`n- " JoinValues(failures, "`r`n- ") "`r`n"
    summary .= "`r`nPASSES`r`n- " JoinValues(passes, "`r`n- ")

    if writeStdout
        FileAppend(summary "`n", "*")
    return summary
}
