#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
#Include ..\FindText.ahk
#Include ..\OCR.ahk
#Include ..\lib\Acc.ahk
#Include ..\lib\TrackUtil.ahk
#Include ..\lib\TrackSQLite.ahk
#Include ..\lib\TrackingDB.ahk
#Include ..\lib\SnapshotEngine.ahk
#Include ..\lib\SnapshotRecovery.ahk
#Include ..\lib\AppLearner.ahk
#Include Core\_Gdip.ahk
#Include ..\lib\FanBridgeVision.ahk
#Include ..\lib\WindowKnowledge.ahk

; Real library integration on an isolated GUI. No input is sent to other apps.
global g_FanBridgeRoot := A_ScriptDir . "\DeepSeekBridge"
global DATA_DIR := A_Temp . "\FanVisionFixture-" . DllCall("GetCurrentProcessId", "UInt")
DirCreate(DATA_DIR)
global g_FanDataConfigOverride := DATA_DIR . "\storage.json"
if !TrackDB_Init(DATA_DIR . "\tracking.db")
    throw Error(g_TrackDBError)
global g_Patterns := Map(), saves := 0, refreshes := 0, failures := 0, passed := 0, saveAllowed := true
global MainGui := 0, g_StudyPin := Map("hwnd", 0)
SavePatterns() {
    global saves, saveAllowed
    saves += 1
    return saveAllowed
}
RefreshPatternLV() {
    global refreshes
    refreshes += 1
}
Assert(test, label) {
    global failures, passed
    if test
        passed += 1
    else
        failures += 1
    FileAppend((test ? "PASS " : "FAIL ") . label . "`n", "*")
}
Throws(fn) {
    try fn.Call()
    catch
        return true
    return false
}
TrackLogError(where, err) {
    FileAppend("DETAIL " . where . ": " . err.Message . "`n", "*")
}
DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
token := Gdip_Startup()
fixture := Gui("+AlwaysOnTop -DPIScale +ToolWindow", "FanBridgeVision synthetic fixture")
fixture.BackColor := "FFFFFF"
fixture.SetFont("s20 c000000", "Segoe UI")
label := fixture.Add("Text", "x20 y20 w400 h45", "HELLO BRIDGE")
fixture.SetFont("s11", "Segoe UI")
entry := fixture.Add("Edit", "x20 y85 w220 h28", "Observed example")
disabled := fixture.Add("Button", "x260 y85 w140 h28 Disabled", "Disabled action")
protected := fixture.Add("Edit", "x20 y130 w220 h28 Password", "synthetic_password")
button := fixture.Add("Button", "x260 y130 w140 h28", "Continue")
monitor := LearningValidation_Monitor()
if monitor {
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    fixture.Show("NA x" . (left+60) . " y" . (top+60) . " w440 h190")
} else
    fixture.Show("NA x60 y60 w440 h190")
Sleep 250
files := []
global methodTrace := []
g_FanVisionObserver := (family,method,phase,detail)=>methodTrace.Push(method)
try {
    activeBefore := WinExist("A")
    args := Map("hwnd", fixture.Hwnd, "include_image", true, "include_ocr", true, "grid", true)
    inspect := FanVision_Dispatch("fan_window_inspect", args)
    zoneAt := 0, ocrAt := 0
    for index,method in methodTrace {
        if method="FanVision_Zones" && !zoneAt
            zoneAt := index
        if InStr(method,"OCR.") && !ocrAt
            ocrAt := index
    }
    Assert(zoneAt && ocrAt>zoneAt, "Window zones are established before OCR recognition")
    Assert(inspect["zones"]["zones"].Length=9 && inspect["ocr"]["groups"].Length>0 && inspect["ocr"].Has("raw_text"), "OCR retains raw order and spatially grouped original text")
    testLayout := FanVision_Zones(Map("x",-900,"y",0,"w",900,"h",600))
    crossing := FanVision_ZoneMatch(Map("x",-610,"y",20,"w",40,"h",20),testLayout)
    Assert(crossing["crosses_zone_boundary"], "Text crossing zone boundaries is flagged without cropping or duplication")
    grouped := FanVision_GroupOCR(Map("text","raw","words",[],"lines",[
        Map("text","Right column","bounds",Map("x",-200,"y",20,"w",80,"h",20)),
        Map("text","Left second","bounds",Map("x",-880,"y",60,"w",80,"h",20)),
        Map("text","Left first","bounds",Map("x",-880,"y",20,"w",80,"h",20))]),testLayout)
    Assert(grouped["groups"].Length=2 && grouped["groups"][1]["text"]="Left first`nLeft second" && grouped["groups"][2]["text"]="Right column", "Adjacent columns remain separate and lines are ordered within their originating zone")
    Assert(inspect["ok"], "Inspection returns real MSAA/OCR result")
    if WinExist("A") != activeBefore
        FileAppend("DETAIL foreground changed: before=" . activeBefore . "; after=" . WinExist("A") . "; target=" . fixture.Hwnd . "`n", "*")
    Assert(WinExist("A") = activeBefore, "Inspection never activates target")
    Assert(inspect["frame"]["coordinates"] = "physical_screen_pixels", "Physical screen coordinate metadata")
    Assert(inspect["frame"]["geometry_stable"], "Window identity and geometry remain stable")
    Assert(inspect["controls"].Length >= 4, "Accessible controls discovered")
    Assert(!inspect["accessibility"].Has("controls"), "Control catalog is retained once rather than duplicated in the model payload")
    seenDisabled := false, protectedHidden := false
    for , control in inspect["controls"] {
        if control["name"] = "Disabled action"
            seenDisabled := !control["enabled"]
        if control["protected"]
            protectedHidden := control["value"] = ""
    }
    Assert(seenDisabled, "Disabled controls keep observable geometry and enabled=false")
    Assert(protectedHidden, "Protected edit value is omitted")
    Assert(inspect.Has("ocr") && InStr(StrUpper(inspect["ocr"]["text"]), "HELLO"), "Windows OCR sees fixture label")
    Assert(FileExist(inspect["image_path"]) && FileExist(inspect["annotated_image_path"]), "Raw and grid/numbered PNG saved")
    Assert(inspect["legend"].Length = inspect["controls"].Length, "Image labels have corresponding observed legend")
    assets := FanPage_Assets(inspect, 4)
    Assert(inspect["visual_tiles"].Length = 12, "Page image partition covers all visible regions")
    cropFound := false, protectedOmitted := false, patternFound := false
    for control in inspect["controls"] {
        asset := assets["acc-" . control["id"]]
        if control["protected"]
            protectedOmitted := asset["crop_status"] = "protected" && !asset.Has("photo_ref")
        else if asset.Has("photo_ref")
            cropFound := cropFound || FileExist(Photo_Path(asset["photo_ref"]))
        if asset.Has("pattern_text")
            patternFound := true
    }
    Assert(cropFound, "Page screen snips persist and rehydrate from photo storage")
    Assert(protectedOmitted, "Protected page fields do not create snips or patterns")
    Assert(patternFound && inspect["asset_stats"]["patterns"] <= 4, "FindText candidates derive from retained capture within budget")
    Assert(FanVision_Hash(inspect["frame"]["region"], false) = inspect["frame"]["content_hash"], "Page asset generation preserves native captured pixels")
    originalStability := inspect["frame"]["content_stable"]
    inspect["frame"]["content_stable"] := false
    dynamicAssets := FanPage_Assets(inspect, 1)
    Assert(inspect["asset_stats"]["patterns"] = 1, "Dynamic viewport patterns use the immutable screenshot")
    inspect["frame"]["content_stable"] := originalStability
    Assert(Throws(() => FanPage_Learn(Map("hwnd", fixture.Hwnd))), "Page learner rejects non-Chrome targets")
    cycle := TrackDB_StartCycle("Isolated Base64 capture")
    cacheFiles := 0
    Loop Files, FanVision_CaptureRoot() . "\*", "F"
        cacheFiles++
    Assert(Snap_CaptureWindow(cycle, "", fixture.Hwnd, 1), "Production snapshot capture stores fixture image")
    snapshot := TrackDB().QueryRow("SELECT * FROM snap_entry ORDER BY id DESC LIMIT 1")
    Assert(snapshot.Count && snapshot["image_path"] = "" && snapshot["b64"] != "", "Snapshot is persisted as Base64 without a durable file path")
    remaining := 0
    Loop Files, FanVision_CaptureRoot() . "\*", "F"
        remaining++
    Assert(cacheFiles = remaining, "Snapshot processing scratch image is deleted after database commit")
    Assert(Photo_Path("snapshot:" . snapshot["id"]) != "", "Stored snapshot can be rendered on demand")
    rootElement := Acc.ElementFromHandle(fixture.Hwnd)
    actionElement := rootElement.FindElement({Name: "Continue", RoleText: "push button"})
    path := rootElement.GetPath(actionElement)
    WinGetPos(&wx,&wy,&ww,&wh,fixture)
    context := Map("hwnd",fixture.Hwnd,"exe",WinGetProcessName(fixture),"class",WinGetClass(fixture),"title",fixture.Title,"x",wx,"y",wy,"w",ww,"h",wh)
    AutoDiscovery_SaveAppTarget(context,path,"Continue","push button","",actionElement.Location)
    model := AppMapDB()
    learned := model.QueryRow("SELECT * FROM ui_element WHERE kind='auto-acc' AND name='Continue'")
    app := model.QueryRow("SELECT * FROM app WHERE id=?",learned["app_id"])
    Assert(learned.Count && learned["source_title"] = fixture.Title, "Passive semantic target enters the reusable App Learner model")
    Assert(AppMap_Locate(app,learned).Count, "Automatic target resolves its exact live window and accessibility path")
    button.Text := "Changed action"
    Assert(!AppMap_Locate(app,learned).Count, "Changed automatic target refuses stale-coordinate fallback")
    button.Text := "Continue"
    files.Push(inspect["image_path"]), files.Push(inspect["annotated_image_path"])
    rect := FanVision_WindowRect(label.Hwnd)
    capture := FanVision_Dispatch("fan_pattern_capture", Map("hwnd", fixture.Hwnd, "region", rect,
        "name", "fixture_hello", "threshold", "**50", "description", "Synthetic harmless label"))
    Assert(capture["ok"] && g_Patterns.Has("fixture_hello") && saves = 1 && refreshes = 1,
        "Self-gained pattern enters normal pattern save/refresh flow")
    if capture.Has("image_path")
        files.Push(capture["image_path"])
    found := FanVision_Dispatch("fan_pattern_search", Map("hwnd", fixture.Hwnd, "name", "fixture_hello", "err1", 0, "err0", 0))
    Assert(found["ok"] && found["matches"].Length > 0, "Saved pattern searched using real FindText matcher")
    Assert(found["err1"] = 0 && found["err0"] = 0, "Requested exact tolerance preserved")
    ; The upstream FindText silently retries failed exact searches at 5%.
    ; Mutate one captured pixel to prove the bridge's explicit pattern tolerance
    ; prevents that retry from falsely reporting an exact match.
    info := FanVision_FT().PicInfo(capture["text"]), binary := info[1], pos := InStr(binary, "1")
    mutated := SubStr(binary,1,pos-1) . "0" . SubStr(binary,pos+1)
    wrongText := StrSplit(capture["text"], "$")[1] . "$" . info[2] . "." . FanVision_FT().bit2base64(mutated)
    wrong := FanVision_Dispatch("fan_pattern_search", Map("hwnd", fixture.Hwnd, "text", wrongText, "err1", 0, "err0", 0))
    tolerant := FanVision_Dispatch("fan_pattern_search", Map("hwnd", fixture.Hwnd, "text", wrongText, "err1", .05, "err0", .05))
    Assert(!wrong["matches"].Length && tolerant["matches"].Length > 0, "Exact matching never silently relaxes; explicit tolerance can match")
    if found["matches"].Length {
        box := found["matches"][1]["bounds"], center := found["matches"][1]["center"]
        Assert(FanVision_Contains(inspect["frame"]["region"], box)
            && center["x"] = box["x"]+box["w"]//2, "FindText physical bounds and center returned")
    }
    listing := FanVision_Dispatch("fan_pattern_list", Map("name", "fixture"))
    Assert(listing["patterns"].Length = 1 && listing["patterns"][1]["description"] != "", "Indexed pattern listing retains usage metadata")
    byDescription := FanVision_Dispatch("fan_pattern_list", Map("query", "Synthetic harmless"))
    Assert(byDescription["patterns"].Length = 1 && byDescription["patterns"][1]["name"] = "fixture_hello", "Advertised pattern query searches descriptions")
    Assert(!FanVision_Dispatch("fan_pattern_list", Map("query", "does-not-match"))["patterns"].Length, "Advertised pattern query excludes unrelated patterns")
    Assert(Throws(() => FanVision_Dispatch("fan_pattern_capture", Map("hwnd", fixture.Hwnd, "name", "no_region"))), "Capture requires explicit crop")
    Assert(Throws(() => FanVision_Dispatch("fan_pattern_capture", Map("hwnd", fixture.Hwnd, "region", rect, "name", "fixture_hello"))), "Existing pattern requires explicit overwrite")
    saveAllowed := false, original := g_Patterns["fixture_hello"]["text"]
    Assert(Throws(() => FanVision_Dispatch("fan_pattern_capture", Map("hwnd", fixture.Hwnd, "region", rect, "name", "fixture_hello", "overwrite", true, "threshold", 128)))
        && g_Patterns["fixture_hello"]["text"] = original, "Database save failure restores overwritten pattern")
    saveAllowed := true
    Assert(Throws(() => FanVision_Dispatch("fan_pattern_search", Map("hwnd", fixture.Hwnd, "name", "fixture_hello", "err1", 2))), "Unbounded tolerance rejected")
    Assert(Throws(() => FanVision_Dispatch("fan_ocr", Map("hwnd", fixture.Hwnd, "region", Map("x", -99999, "y", 0, "w", 50, "h", 50)))), "Off-target desktop crop rejected")
    menuCommands := 0
    menuFixture := Menu(), menuFixture.Add("&Open`tCtrl+O",(*)=>menuCommands++)
    menuRoot := MenuBar(), menuRoot.Add("&File",menuFixture), fixture.MenuBar := menuRoot
    tabsFixture := fixture.Add("Tab3","x20 y175 w390 h70",["First knowledge tab","Second knowledge tab"])
    tabsFixture.UseTab(0), fixture.Show("NoActivate w440 h260"), Sleep(100)
    probeFixture := FanWindow_Probe(Map("hwnd",fixture.Hwnd))
    Assert(probeFixture["probe_only"] && probeFixture["frame"]["class"]="AutoHotkeyGUI", "Cheap learning probe records exact native window context")
    menuSeen := false, tabSeen := false
    for item in probeFixture["menus"]
        if item["label"]="Open" && item["parent"]="File" && item["shortcut"]="Ctrl+O"
            menuSeen := true
    for item in probeFixture["tabs"]
        if item["name"]="First knowledge tab" && item["selected"]
            tabSeen := true
    Assert(menuSeen && !menuCommands, "Recursive menu enumeration indexes shortcut relationships without invoking commands")
    Assert(tabSeen, "Live probe identifies the active tab")
    Assert(Throws(()=>FanWindow_Shortcut(Map("hwnd",fixture.Hwnd,"shortcut","address_bar"))), "App shortcut guard rejects unrelated windows before input")
    WinActivate(fixture.Hwnd), WinWaitActive(fixture.Hwnd,,2)
    Run('"' . A_AhkPath . '" /ErrorStdOut=UTF-8 "' . A_ScriptDir . '\tests\WindowMenuFixture.ahk"',A_ScriptDir,"Hide",&menuFixturePID)
    menuHwnd := WinWait("DAA menu regression target ahk_pid " . menuFixturePID,,5)
    WinActivate(menuHwnd), WinWaitActive(menuHwnd,,2)
    menuCatalog := FanWindow_Menu(Map("hwnd",menuHwnd,"action","catalog"))
    Assert(menuCatalog["menus"].Length>0 && menuCatalog["menus"][1]["label"]="File","Active menu explorer reads actual top-level menu order")
    openedMenu := FanWindow_Menu(Map("hwnd",menuHwnd,"action","open","label","File"))
    Assert(openedMenu["ok"] && openedMenu["menu_open_verified"] && openedMenu["menu_items"].Length>0,"Observed menu opens and retains ordered items with zoned OCR/image evidence")
    returnedMenu := FanWindow_Menu(Map("hwnd",menuHwnd,"action","return","all_menus",true))
    Assert(returnedMenu["ok"] && !returnedMenu["remaining_menu"] && ControlGetText("Static1",menuHwnd)="Commands: 0","Menu exploration returns without invoking a leaf command")
    for key in ["image_path","annotated_image_path"]
        if openedMenu.Has(key)
            files.Push(openedMenu[key])
    ProcessClose(menuFixturePID), menuFixturePID := 0
    WinActivate(fixture.Hwnd), WinWaitActive(fixture.Hwnd,,2)
    WinGetPos(&beforeX,&beforeY,&beforeW,&beforeH,fixture.Hwnd)
    surveyFixture := 0
    try surveyFixture := FanWindow_Survey(Map("hwnd",fixture.Hwnd,"maximize",true,"activate_menu",true))
    catch TargetError as focusError
        Assert(InStr(focusError.Message,"foreground"), "Foreground change safely refuses exploration without sending input elsewhere")
    WinGetPos(&afterX,&afterY,&afterW,&afterH,fixture.Hwnd)
    if IsObject(surveyFixture)
        Assert(surveyFixture["ok"] && !surveyFixture["coverage"]["complete_interface"], "Deep survey returns bounded evidence and explicit coverage gaps")
    Assert(beforeX=afterX && beforeY=afterY && beforeW=afterW && beforeH=afterH && WinGetMinMax(fixture.Hwnd)=0, "Exploratory maximize and ALT restore the prior window placement")
    Assert(!menuCommands, "ALT survey observes menus without executing a menu command")
    Assert(Throws(()=>FanWindow_Survey(Map("hwnd",fixture.Hwnd,"fullscreen",true))), "Unknown full-screen binding is refused")
    if IsObject(surveyFixture)
        for key in ["image_path","annotated_image_path"]
            if surveyFixture.Has(key)
                files.Push(surveyFixture[key])
    WinMinimize(fixture)
    minimizedMessage := ""
    try FanVision_Region(Map("hwnd",fixture.Hwnd),fixture.Hwnd)
    catch as err
        minimizedMessage := err.Message
    WinRestore(fixture)
    Assert(InStr(StrLower(minimizedMessage),"minimized") && InStr(StrLower(minimizedMessage),"restore"), "Minimized target returns an actionable restore diagnostic before rectangle capture")
    fixture.Hide()
    hidden := FanVision_Dispatch("fan_ocr", Map("hwnd", fixture.Hwnd))
    Assert(!hidden["ok"] && hidden["frame"]["visibility"]["reason"] = "Window is hidden", "Hidden window OCR fails without focus theft")
} catch as err {
    Assert(false, "Uncaught " . err.Message . " at line " . err.Line)
} finally {
    if IsSet(menuFixturePID) && menuFixturePID && ProcessExist(menuFixturePID)
        ProcessClose(menuFixturePID)
    DeepActivity_Shutdown()
    fixture.Destroy()
    Gdip_Shutdown(token)
    TrackDB_Close()
    if IsObject(g_AppMapDB)
        g_AppMapDB.Close()
    Photo_ClearCache()
    Loop Files, DATA_DIR . "\tracking.db*", "F"
        FileDelete(A_LoopFileFullPath)
    Loop Files, DATA_DIR . "\appmap.db*", "F"
        FileDelete(A_LoopFileFullPath)
    DirDelete(DATA_DIR)
    for , path in files {
        if InStr(path, g_FanBridgeRoot . "\.runtime\captures\") = 1
            try FileDelete(path)
    }
}
FileAppend("RESULT " . passed . " passed, " . failures . " failed`n", "*")
ExitApp(failures ? 1 : 0)
