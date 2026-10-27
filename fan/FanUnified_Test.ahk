#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
#Include ..\lib\TrackSQLite.ahk
#Include ..\lib\TrackUtil.ahk
#Include ..\lib\TrackingDB.ahk
#Include ..\lib\AppLearner.ahk

global failures := 0, passed := 0
global DATA_DIR := A_ScriptDir . "\tests\runtime\unified-native-" . DllCall("GetCurrentProcessId", "uint")
global g_FanDataConfigOverride := DATA_DIR . "\routes.json"
DirCreate(DATA_DIR)
dbPath := DATA_DIR . "\fan.sqlite"
FileAppend(TrackJsonEncode(Map("unified_db", dbPath, "unified_initialized", true)), g_FanDataConfigOverride, "UTF-8-RAW")
note := FanData_ProjectRoot() . "\data\notes\unified-test-" . A_TickCount . ".txt"
settings := FanData_ProjectRoot() . "\data\settings.ini"
external := DATA_DIR . "\export.txt"
Assert(ok, label) {
    global failures, passed
    if ok
        passed++
    else
        failures++
    FileAppend((ok ? "PASS " : "FAIL ") . label . "`n", "*")
}
try {
    for role in ["tracking", "macro", "appmap", "bridge", "catalog"]
        Assert(FanData_DbPath(role, "legacy") = dbPath, role . " routes to one file")
    Assert(FanData_DbAvailable("tracking", dbPath) = dbPath, "Missing unified store permits evergreen seeding")
    Assert(!FanFileExist(note), "Fresh store never falls back to loose legacy documents")
    FanFileAppend("First", note, "UTF-8")
    FanFileAppend(" second", note)
    Assert(FanFileRead(note) = "First second" && !FileExist(note), "Notes persist only in SQLite")
    FanFile_Set(note, "")
    Assert(FanFileExist(note) && FanFileRead(note) = "", "Empty documents are valid persisted rows")
    FanIniWrite("hello", settings, "Settings", "Name")
    FanIniWrite(42, settings, "Settings", "Value")
    Assert(FanIniRead(settings, "Settings", "Name") = "hello", "Native INI semantics read database documents")
    Assert(FanIniRead(settings, "Settings", "Value", 0) = 42, "Numeric INI round-trip")
    Assert(FanIniRead(settings, "Settings", "Absent", "fallback") = "fallback", "Missing INI keys retain defaults")
    Assert(InStr(FanIniRead(settings), "Settings"), "Section enumeration is preserved")
    writer := FanFileOpen(note, "w", "UTF-8")
    writer.WriteLine("Header")
    writer.WriteLine("Row")
    writer.Close()
    lines := FanFile_Lines(note)
    Assert(lines.Length = 2 && lines[1] = "Header" && lines[2] = "Row", "CSV line readers work without persistent files")
    Assert(FanFile_ListNotes(FanData_ProjectRoot() . "\data\notes").Length = 1, "Note list queries the database")
    FanFileAppend("Explicit export", external, "UTF-8")
    Assert(FileExist(external) && FileRead(external, "UTF-8") = "Explicit export", "External exports remain real files")
    config := FanData_Config()
    config["learning_monitor"] := 3
    FanData_SaveConfig(config)
    pointer := TrackJsonDecode(FileRead(g_FanDataConfigOverride, "UTF-8"))
    Assert(!pointer.Has("learning_monitor") && FanData_Config(true)["learning_monitor"] = 3, "Preferences live in database, not storage pointer")
    Assert(TrackDB_Init() && AppMapDB(), "Tracking and app learner open the unified database together")
    Assert(AppMap_AppTable() = "appmap_app" && TrackDB().TableExists("app") && TrackDB().TableExists("appmap_app"), "Both distinct app tables coexist")
    id := TrackDB_AppId("test.exe", "test")
    AppMapDB().Run("INSERT INTO appmap_app(name,exe,cls) VALUES(?,?,?)", "Learned", "test.exe", "test")
    Assert(id > 0 && TrackDB().Scalar("SELECT count(*) FROM app") = 1 && AppMapDB().Scalar("SELECT count(*) FROM appmap_app") = 1, "App identities never collide")
    FanFileDelete(note)
    Assert(!FanFileExist(note), "Document delete removes the row")
} catch as testError {
    failures++
    FileAppend("ERROR " . testError.Message . " at " . testError.Line . "`n", "*")
} finally {
    if IsObject(g_AppMapDB)
        g_AppMapDB.Close()
    TrackDB_Close()
    FanState_Close()
}
FileAppend("RESULT " . passed . " passed; " . failures . " failed`n", "*")
ExitApp(failures ? 1 : 0)
