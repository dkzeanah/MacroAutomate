#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
#Include ..\lib\TrackSQLite.ahk
#Include ..\lib\TrackUtil.ahk
#Include ..\lib\TrackingDB.ahk
#Include Core\_Gdip.ahk
#Include ..\lib\KnowledgeDash.ahk
#Include Core\_Navigation.ahk
#Include Tabs\Tab_22_Knowledge.ahk

global DATA_DIR := A_Temp . "\FanWorkspace-" . DllCall("GetCurrentProcessId", "UInt")
global g_FanDataConfigOverride := DATA_DIR . "\storage.json"
global MainGui := Gui("+Resize", "Fan task workspace - isolated preview")
global failures := 0
DirCreate(DATA_DIR)
OnError(TestError)
TestError(err, *) {
    FileAppend("ERROR " . err.Message . " at " . err.File . ":" . err.Line . "`n", "*")
    ExitApp(2)
}
LogErrorToFile(err, *) => TestError(err)
Check(ok, text) {
    global failures
    failures += !ok
    FileAppend((ok ? "PASS " : "FAIL ") . text . "`n", "*")
}
try {
    TrackDB_Init(DATA_DIR . "\fixture.sqlite")
    LearningLab_Schema()
    id := LearningLab_Record("Fixture", "button", "Open the sample report", "fail", Map("scope", "fixture"), "Button moved", "synthetic test", "Recheck the report button")
    db := TrackDB()
    db.Exec("CREATE TABLE usage_transition(id INTEGER PRIMARY KEY,prefix_text TEXT,next_token TEXT,support INTEGER)")
    db.Exec("INSERT INTO usage_transition VALUES(1,'Report > Open','Export CSV',7)")
    Check(InStr(Know_ReviewSummary(), "1 claims with negative checks"), "negative evidence remains visible in overview")
    records := Know_CategoryRows("learning_claim")
    Check(records.Length = 1 && records[1]["claim_id"] = id, "claims retain stable evidence link IDs")
    records := Know_CategoryRows("learning_evidence")
    Check(records[1]["claim_id"] = id && InStr(records[1]["content"], "Button moved"), "evidence shows outcome, provenance and detail")
    Check(Know_CategoryRows("learning_review").Length = 1, "negative-check review queue contains the contradicted claim")
    records := Know_CategoryRows("usage_transition")
    Check(InStr(records[1]["content"], "Export CSV"), "generic categories expose complete source fields")
    MainGui.SetFont("s9", "Segoe UI")
    names := []
    for page in FanNav_Pages()
        names.Push(page[1])
    global TabCtrl := MainGui.Add("Tab3", "-Wrap +0x500 x5 y28 w890 h730", names)
    SendMessage(0x1329, 0, 0x10001, TabCtrl)
    Loop 23 {
        if A_Index = 22
            Tab_Knowledge_Build()
        else {
            TabCtrl.UseTab(A_Index)
            MainGui.Add("Text", "x20 y70 w800", FanNav_Pages()[A_Index][2])
            if A_Index = 10
                FanNav_SettingsBuild()
        }
    }
    TabCtrl.UseTab(25)
    MainGui.Add("Text", "x20 y70 w800", "Chrome Learning route fixture")
    FanHome_Build(), FanNav_Init()
    Check(g_FanNav["mode"] = "classic" && TabCtrl.Value = 1, "original tabbed interface and Workflow are the default")
    FanNav_Cycle(1)
    Check(TabCtrl.Value = 2, "Tab advances to the next original tab")
    FanNav_Cycle(-1)
    Check(TabCtrl.Value = 1, "Shift+Tab returns to the previous original tab")
    FanNav_Cycle(-1)
    Check(TabCtrl.Value = 23, "Shift+Tab wraps from the first tab to the last")
    FanNav_Cycle(1)
    Check(TabCtrl.Value = 1, "Tab wraps from the last tab to the first")
    Check(g_FanNav["classicTabs"].Visible && !g_FanNav["group"].Visible, "classic mode shows real tabs and hides clean selectors")
    members := Map()
    for group in FanNav_ClassicGroups()
        for page in group[2] {
            Check(!members.Has(page), "original page " . page . " has one classic tab")
            members[page] := true
        }
    Check(members.Count = 22 && FanNav_ClassicGroups().Length = 21, "the merged Learning page and dedicated Chrome page have one route each")
    FanNav_Open(16)
    Check(TabCtrl.Value = 14 && g_FanNav["classicTabs"].Text = "Learning" && !g_FanNav["section"].Visible, "Vision Scout legacy route opens one combined Learning page")
    TabCtrl.Choose(17), FanNav_Sync()
    Check(TabCtrl.Value = 14, "Usage Predictor IPC route resolves to the same combined Learning page")
    FanNav_Open(25)
    Check(g_FanNav["classicTabs"].Text = "Chrome Learning", "Chrome learning has a dedicated visible tab")
    FanNav_Open(19)
    Check(g_FanNav["classicTabs"].Text = "Study" && g_FanNav["section"].Text = "Live Portal", "Live Portal is available inside the combined Study tab")
    FanNav_Open(10), FanNav_SetMode("clean")
    Check(TabCtrl.Value = 10 && g_FanNav["modeSetting"].Value = 2, "switching to clean keeps Settings open")
    Check(FanData_Config(true).Get("interface_mode", "") = "clean", "clean interface preference persists")
    Check(!g_FanNav["classicTabs"].Visible && g_FanNav["group"].Visible, "clean mode hides tabs and shows task navigation")
    FanNav_Open(24), FanNav_Cycle(1)
    Check(TabCtrl.Value = 1, "Tab also advances through the optional clean view")
    FanNav_Cycle(-1)
    Check(TabCtrl.Value = 24, "Shift+Tab returns to the clean overview")
    seen := Map()
    for group in FanNav_Groups()
        for page in group["pages"] {
            Check(!seen.Has(page), "page " . page . " belongs to one task group")
            seen[page] := true
            FanNav_Open(page)
            Check(TabCtrl.Value = page && g_FanNav["page"].Text = FanNav_Pages()[page][1], "navigation and selectors agree for page " . page)
        }
    Check(seen.Count = 23, "all active pages, Chrome and the start page remain reachable")
    TabCtrl.Choose(19), FanNav_Sync()
    Check(g_FanNav["group"].Text = "Study", "direct IPC-style page choice synchronizes navigation")
    FanNav_Open(22)
    g_KnowCurKey := "learning_claim"
    Know_UiSetRows(Know_CategoryRows("learning_claim"))
    g_KnowCtl["search"].Value := "not present", Know_UiFilter()
    Check(g_KnowRows.Length = 0 && !g_KnowCtl["claim"].Enabled, "empty filter clears claim actions")
    g_KnowCtl["search"].Value := "report", Know_UiFilter()
    Check(g_KnowRows.Length = 1 && g_KnowRows[1]["claim_id"] = id, "search preserves the matching claim's identity")
    g_KnowCtl["detail"].Modify(1, "Select"), Know_UiDetailSelect()
    Check(g_KnowCtl["claim"].Enabled && InStr(g_KnowCtl["viewer"].Value, "Recheck the report button"), "selected claim exposes use and evidence action")
    Check(InStr(g_KnowCtl["viewer"].Value, "Contradicted / review"), "selected claim explains the actual evidence state")
    before := g_KnowCtl["viewer"].Value
    Know_UiRefresh(false)
    Check(g_KnowCtl["viewer"].Value = before && g_KnowCtl["detail"].GetNext() = 1, "background inventory refresh preserves the inspected record")
    controlId := g_KnowCtl["viewer"].Hwnd
    FanNav_SetMode("classic")
    Check(TabCtrl.Value = 22 && g_KnowCtl["viewer"].Hwnd = controlId && g_KnowCtl["viewer"].Value = before, "returning to tabs preserves the page and in-progress record review")
    Check(FanData_Config(true).Get("interface_mode", "") = "classic", "original interface preference persists")
    FanNav_SetMode("clean"), FanNav_Open(24), FanNav_SetMode("classic")
    Check(TabCtrl.Value = 1, "leaving clean overview returns to the original Workflow tab")
    g_KnowCtl["search"].Value := "", Know_UiFilter()
    FanNav_Open(10)
    FileAppend("RESULT failures=" . failures . "`n", "*")
    ; Fixture pages intentionally contain placeholders. Never display this
    ; window as an app preview; FanGui_Test builds the actual tool controls.
    ExitApp(failures ? 1 : 0)
} catch as err
    TestError(err)
