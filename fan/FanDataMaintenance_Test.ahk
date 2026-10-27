#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
#Include ..\lib\TrackUtil.ahk
#Include ..\lib\TrackSQLite.ahk
#Include ..\lib\TrackingDB.ahk
#Include ..\lib\FanDataMaintenance.ahk
#Include ..\lib\ElementViewer.ahk
#Include ..\lib\SnapshotEngine.ahk

; Tests only new fixture paths and hidden GUI controls. No real database is
; opened, no maintenance transfer is started, and no user input is generated.
global passed := 0, failures := 0, g_WorkflowRunning := false
global g_StudyMacroRunning := false, g_StudyToolBusy := false, g_DeepBridge := Map("busy", false)
Assert(ok, label) {
    global passed, failures
    if ok
        passed += 1
    else
        failures += 1
    FileAppend((ok ? "PASS " : "FAIL ") . label . "`n", "*")
}
Throws(fn) {
    try fn.Call()
    catch
        return true
    return false
}
WriteFixture(path, value) {
    file := FileOpen(path, "w", "UTF-8-RAW")
    file.Write(value)
    file.Close()
}
FixtureJunction(link, target) {
    global fixtureRoot
    if InStr(link, fixtureRoot . "\") != 1 || InStr(target, fixtureRoot . "\") != 1
        throw Error("Fixture junction must stay within the isolated test directory")
    substitute := "\??\" . target, subBytes := StrLen(substitute)*2, printBytes := StrLen(target)*2
    reparseData := Buffer(16+subBytes+2+printBytes+2, 0)
    NumPut("UInt", 0xA0000003, "UShort", reparseData.Size-8, "UShort", 0,
        "UShort", 0, "UShort", subBytes, "UShort", subBytes+2, "UShort", printBytes, reparseData)
    StrPut(substitute, reparseData.Ptr+16, "UTF-16")
    StrPut(target, reparseData.Ptr+16+subBytes+2, "UTF-16")
    DirCreate(link)
    handle := DllCall("CreateFileW", "Str", link, "UInt", 0x40000000, "UInt", 0, "Ptr", 0,
        "UInt", 3, "UInt", 0x02200000, "Ptr", 0, "Ptr")
    if handle = -1
        throw OSError()
    try {
        if !DllCall("DeviceIoControl", "Ptr", handle, "UInt", 0x900A4, "Ptr", reparseData, "UInt", reparseData.Size,
            "Ptr", 0, "UInt", 0, "UInt*", &returned := 0, "Ptr", 0)
            throw OSError()
    } finally
        DllCall("CloseHandle", "Ptr", handle)
}
global fixtureRoot := A_ScriptDir . "\DeepSeekBridge\.runtime\data-settings-test-" . DllCall("GetCurrentProcessId", "UInt")
DirCreate(fixtureRoot)
global g_FanDataConfigOverride := fixtureRoot . "\設定-café.json"
global fixtureGui := Gui("+ToolWindow", "Isolated maintenance Settings fixture")
global DATA_DIR := fixtureRoot . "\fixture-data"
snapshotAlias := DATA_DIR . "\tracking\snapshots", snapshotTarget := fixtureRoot . "\snapshot-target"
unicodeDestination := fixtureRoot . "\選択-café"
paths := [g_FanDataConfigOverride, g_FanDataConfigOverride . ".tmp", fixtureRoot . "\status.json", fixtureRoot . "\cancel", fixtureRoot . "\画像.png", fixtureRoot . "\tracking.db", fixtureRoot . "\tracking.db-wal", fixtureRoot . "\tracking.db-shm"]
try {
    Assert(FanData_ConfigPath() = g_FanDataConfigOverride, "Configuration override isolates all fixture writes")
    Assert(FanData_Config(true).Count = 0, "Missing fixture config provides an empty/default map")
    FanData_SettingsBuild(fixtureGui)
    Assert(g_FanDataUI["days"].Value = 2 && g_FanDataUI["days"].Text = "Last 30 days", "Settings defaults to bounded30-day analysis")
    Assert(!g_FanDataUI.Has("embed"), "Base64 photo storage is required instead of optional duplication")
    Assert(!g_FanDataUI["cancel"].Enabled, "Cancel is disabled when no job runs")
    buttons := Map()
    for control in fixtureGui
        if control.Type = "Button"
            buttons[control.Text] := true
    Assert(buttons.Has("Consolidate insights") && buttons.Has("Export databases…") && buttons.Has("Offload databases…")
        && buttons.Has("Export snapshots…") && buttons.Has("Import stored photos"), "Actual Settings builder exposes requested analysis and storage controls")
    g_FanDataUI["days"].Value := 1
    Assert(g_FanDataUI["days"].Text = "Last 7 days", "Analysis range supports7-day window")
    g_FanDataUI["days"].Value := 3
    Assert(g_FanDataUI["days"].Text = "Last 90 days", "Analysis range supports90-day window")
    Assert(LearningValidation_SelectMonitor(1, 1, 2) = 0, "No primary-monitor fallback on a single display")
    Assert(LearningValidation_SelectMonitor(3, 1, 3) = 3, "Monitor 3 preference is honored")
    Assert(LearningValidation_SelectMonitor(3, 2, 2) = 3, "Primary monitor and display 1 are both excluded")
    Assert(LearningValidation_SelectMonitor(2, 1, 3) = 2, "Disconnected preferred display falls back to secondary")
    unicodeDatabase := fixtureRoot . "\移動-café\tracking.db"
    config := FanData_Config().Clone()
    config["databases"] := Map("tracking", unicodeDatabase)
    FanData_SaveConfig(config)
    Assert(FanData_DbPath("tracking", "fallback") = unicodeDatabase, "Unicode relocated database path round-trips without loss")
    Assert(Throws(() => FanData_DbAvailable("tracking", unicodeDatabase)) && !FileExist(unicodeDatabase), "Configured missing store refuses creating an empty replacement")
    Assert(FanData_DbPath("appmap", "fixture-fallback") = "fixture-fallback", "Unconfigured roles retain their original fallback path")
    Assert(FanData_DefaultPaths()["tracking"] = unicodeDatabase, "Maintenance database list follows the same live storage route")
    inventory := FanData_DriveInventory(), roots := Map(), structureValid := true
    for , drive in inventory {
        roots[StrUpper(drive["root"])] := drive
        structureValid := structureValid && drive.Has("type") && drive.Has("label") && drive.Has("free_mb")
            && drive.Has("capacity_mb") && drive.Has("ready")
            && IsNumber(drive["free_mb"]) && IsNumber(drive["capacity_mb"])
    }
    Assert(inventory.Length > 0 && structureValid, "Drive picker inventory includes labels, readiness and free/capacity metadata")
    mounted := DriveGetList(), allMountedListed := true, fixedListed := true, removableListed := true
    Loop Parse, mounted {
        driveRoot := StrUpper(A_LoopField . ":\")
        allMountedListed := allMountedListed && roots.Has(driveRoot)
        kind := DriveGetType(driveRoot)
        if kind = "Fixed"
            fixedListed := fixedListed && roots.Has(driveRoot) && roots[driveRoot]["type"] = "Fixed"
        if kind = "Removable"
            removableListed := removableListed && roots.Has(driveRoot) && roots[driveRoot]["type"] = "Removable"
    }
    Assert(allMountedListed, "Every actual mounted drive letter appears without device-type filtering")
    Assert(fixedListed && removableListed, "Mounted Fixed external disks and Removable drives are both supported")
    DirCreate(unicodeDestination)
    validDestination := FanData_ValidateDestination(unicodeDestination, "export", "snapshots")
    Assert(validDestination = unicodeDestination && FanData_FolderIdentity(validDestination) = FanData_FolderIdentity(unicodeDestination),
        "Unicode existing destination resolves to the expected absolute folder")
    quotedDestination := FanData_ValidateDestination(Chr(34) . unicodeDestination . Chr(34), "offload", "snapshots")
    Assert(quotedDestination = unicodeDestination, "Quoted pasted absolute folder works for attached-drive snapshot offload")
    Assert(Throws(() => FanData_ValidateDestination("relative-folder", "export", "snapshots")), "Relative folder path is rejected before transfer")
    Assert(Throws(() => FanData_ValidateDestination(fixtureRoot . "\not-created", "export", "snapshots")) && !DirExist(fixtureRoot . "\not-created"),
        "Missing destination is rejected without creating a directory")
    offlineRoot := ""
    Loop 26 {
        letter := Chr(91-A_Index)
        if !InStr(mounted, letter) {
            offlineRoot := letter . ":\"
            break
        }
    }
    Assert(offlineRoot != "" && Throws(() => FanData_ValidateDestination(offlineRoot, "export", "snapshots")), "Unmounted external-drive letter is rejected without writes")
    Assert(Throws(() => FanData_ValidateDestination("\\fan-unavailable-fixture\share", "offload", "snapshots")), "Unsupported network snapshot offload is rejected")
    Assert(Throws(() => FanData_ValidateDestination(unicodeDestination, "unsupported", "snapshots")), "Unsupported destination operation rejected")
    Assert(Throws(() => FanData_ValidateDestination(unicodeDestination, "export", "unsupported")), "Unsupported destination scope rejected")
    imagePath := fixtureRoot . "\画像.png"
    png := "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/W1sAAAAASUVORK5CYII="
    Assert(TrackBase64DecodeToFile(png, imagePath), "Fixture image is created using real Windows crypto decode")
    g_VwB64Edit := fixtureGui.Add("Edit", "x0 y0 w100 h40")
    g_VwEntry := Map("b64", "", "image_path", imagePath)
    Vw_EnsureB64()
    Assert(g_VwEntry["b64"] = png && g_VwB64Edit.Value = png, "Snapshot viewer lazily regenerates base64 from the image file")
    g_VwEntry := Map("b64", "legacy-stored-base64", "image_path", imagePath)
    Vw_EnsureB64()
    Assert(g_VwEntry["b64"] = "legacy-stored-base64", "Legacy stored base64 remains available without being overwritten")
    g_VwEntry := Map("b64", "", "image_path", fixtureRoot . "\missing.png")
    Vw_EnsureB64()
    Assert(g_VwEntry["b64"] = "", "Missing image is handled without inventing payload data")
    DirCreate(DATA_DIR . "\tracking")
    Assert(TrackDB_Init(fixtureRoot . "\tracking.db"), "Only isolated fixture tracking database is opened")
    photo := Photo_Store(imagePath, "Fixture")
    Assert(RegExMatch(photo, "^photo:\d+$"), "Image stored as database photo reference")
    decoded := Photo_Path(photo)
    Assert(decoded != "" && TrackBase64EncodeFile(decoded) = png, "Database photo renders from identical Base64 bytes")
    Assert(Photo_Path(photo) = decoded, "On-demand photo render is cached")
    DirCreate(snapshotTarget)
    config := FanData_Config().Clone()
    config["snapshots"] := Map("source", snapshotAlias, "target", snapshotTarget)
    FanData_SaveConfig(config)
    Assert(Snap_Init() && !DirExist(snapshotAlias), "Database capture works without a snapshot folder")
    DirCreate(snapshotAlias)
    Assert(Snap_Init(), "Historical snapshot routes do not control database-only captures")
    DirDelete(snapshotAlias)
    FixtureJunction(snapshotAlias, snapshotTarget)
    Assert(FanData_FolderIdentity(snapshotAlias) = FanData_FolderIdentity(snapshotTarget) && Snap_Init(),
        "Real snapshot junction keeps historical paths valid through the same physical directory identity")
    config["snapshots"]["target"] := fixtureRoot . "\disconnected-target"
    FanData_SaveConfig(config)
    Assert(Snap_Init(), "Disconnected legacy image drive does not stop database-only captures")
    DirDelete(snapshotAlias)  ; Removes only this fixture junction, not its target.
    Assert(DirExist(snapshotTarget), "Fixture alias removal leaves its physical target intact")
    g_FanDataJob := fixtureRoot
    g_FanDataPid := 0x7FFFFFFF
    g_FanDataUI["cancel"].Enabled := true
    WriteFixture(fixtureRoot . "\status.json", TrackJsonEncode(Map("phase", "analyzing", "message", "Still working")))
    FanData_PollJob()
    Assert(!g_FanDataPid && !g_FanDataUI["cancel"].Enabled && RegExMatch(g_FanDataUI["status"].Value, "i)stopped.*(completion|unexpectedly)"),
        "A dead worker with readable stale status becomes a visible failure")
    FanData_CancelJob()
    Assert(FileExist(fixtureRoot . "\cancel"), "Cancellation writes a cooperative marker in this job only")
} catch as err {
    Assert(false, "Uncaught " . err.Message . " at line " . err.Line)
} finally {
    TrackDB_Close()
    Photo_ClearCache()
    SetTimer(FanData_PollJob, 0)
    fixtureGui.Destroy()
    for , path in paths
        if InStr(path, fixtureRoot . "\") = 1 && FileExist(path)
            try FileDelete(path)
    try DirDelete(snapshotAlias)
    try DirDelete(snapshotTarget)
    try DirDelete(unicodeDestination)
    try DirDelete(DATA_DIR . "\tracking")
    try DirDelete(DATA_DIR)
    try DirDelete(fixtureRoot)
}
FileAppend("RESULT " . passed . " passed, " . failures . " failed`n", "*")
ExitApp(failures ? 1 : 0)
