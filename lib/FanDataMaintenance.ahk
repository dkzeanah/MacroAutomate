; Local background jobs; storage cutover runs while Fan is closed by its helper.
global g_FanDataUI := Map(), g_FanDataJob := "", g_FanDataPid := 0

FanData_SettingsBuild(gui) {
    global g_FanDataUI
    gui.Add("GroupBox", "x15 y505 w860 h232", "Learning insights and storage")
    g_FanDataUI["status"] := gui.Add("Text", "x25 y525 w835 h34", "Analyze recent learning or export/offload Fan databases and snapshots to a selected folder.")
    gui.Add("Button", "x25 y565 w155 h28", "Consolidate insights").OnEvent("Click", (*) => FanData_StartJob("analyze"))
    g_FanDataUI["days"] := gui.Add("DropDownList", "x190 y566 w110 Choose2", ["Last 7 days", "Last 30 days", "Last 90 days"])
    gui.Add("Button", "x310 y565 w145 h28", "View insights").OnEvent("Click", (*) => FanData_ViewInsights())
    gui.Add("Button", "x475 y565 w190 h28", "Consolidate old archive...").OnEvent("Click", (*) => FanData_StartJob("consolidate"))
    gui.Add("Button", "x25 y606 w170 h28", "Export databases…").OnEvent("Click", (*) => FanData_StartJob("export", "databases"))
    gui.Add("Button", "x210 y606 w170 h28", "Offload databases…").OnEvent("Click", (*) => FanData_StartJob("offload", "databases"))
    gui.Add("Button", "x395 y606 w170 h28", "Export snapshots…").OnEvent("Click", (*) => FanData_StartJob("export", "snapshots"))
    gui.Add("Button", "x580 y606 w170 h28", "Import stored photos").OnEvent("Click", (*) => FanData_StartJob("images"))
    g_FanDataUI["cancel"] := gui.Add("Button", "x765 y606 w95 h28 Disabled", "Cancel job")
    g_FanDataUI["cancel"].OnEvent("Click", (*) => FanData_CancelJob())
    gui.Add("Text", "x25 y645 w830 h42", "Both database actions archive the data, replace the originals with empty schemas and restart Fan. Export snapshots writes image files from database photos.")
    gui.Add("Button", "x25 y698 w165 h26", "Storage locations").OnEvent("Click", (*) => FanData_ShowLocations())
    gui.Add("Button", "x205 y698 w165 h26", "Open job history").OnEvent("Click", (*) => Run(FanData_ProjectRoot() . "\fan\.maintenance"))
    gui.Add("CheckBox", "x390 y697 w180 vAutoDiscover", "Automatic discovery").Value := FanData_Config().Get("auto_discovery", true)
    gui["AutoDiscover"].OnEvent("Click", FanData_SetLearning)
    gui.Add("CheckBox", "x580 y697 w140 vLearnValidation", "Live validation").Value := FanData_Config().Get("learning_validation", true)
    gui["LearnValidation"].OnEvent("Click", FanData_SetLearning)
    g_FanDataUI["monitor"] := gui.Add("DropDownList", "x725 y696 w135 Choose1", ["Auto secondary", "Monitor 2", "Monitor 3"])
    preference := FanData_Config().Get("learning_monitor", 0)
    g_FanDataUI["monitor"].Choose(preference = 2 ? 2 : preference = 3 ? 3 : 1)
    g_FanDataUI["monitor"].OnEvent("Change", FanData_SetLearning)
    FanData_ResumeArchiveJob()
}

FanData_ResumeArchiveJob() {
    global g_FanDataJob, g_FanDataPid
    job := FanData_Config().Get("archive_job", "")
    root := RTrim(FanFile_Absolute(FanData_ProjectRoot() . "\fan\.maintenance"), "\") . "\"
    if job = "" || SubStr(FanFile_Absolute(job), 1, StrLen(root)) != root
        return
    if !FileExist(job . "\status.json")
        return
    state := TrackJsonDecode(FileRead(job . "\status.json", "UTF-8"))
    FanData_SetStatus(state.Get("message", "Archive consolidation"))
    if state.Get("worker_pid", 0) && ProcessExist(state["worker_pid"]) {
        g_FanDataJob := job
        g_FanDataPid := state["worker_pid"]
        g_FanDataUI["cancel"].Enabled := true
        SetTimer(FanData_PollJob, 500)
    }
}

FanData_DefaultPaths() {
    root := FanData_ProjectRoot(), data := root . "\data", bridge := root . "\fan\DeepSeekBridge"
    return Map("tracking", FanData_DbPath("tracking", data . "\tracking.db"),
        "macro", FanData_DbPath("macro", data . "\macroauto.sqlite"), "appmap", FanData_DbPath("appmap", data . "\appmap.db"),
        "bridge", FanData_DbPath("bridge", bridge . "\bridge.sqlite3"),
        "catalog", FanData_DbPath("catalog", bridge . "\.runtime\tool_catalog.sqlite3"))
}

FanData_StartJob(mode, scope := "") {
    global g_FanDataJob, g_FanDataPid
    reset := scope = "databases" && (mode = "export" || mode = "offload")
    closedJob := mode = "offload" || reset || mode = "images" || mode = "consolidate" || (mode = "export" && scope = "snapshots")
    if g_FanDataPid && ProcessExist(g_FanDataPid) {
        FanData_SetStatus("A maintenance job is already running.")
        return false
    }
    if closedJob && (g_WorkflowRunning || g_StudyMacroRunning || g_StudyToolBusy || g_DeepBridge["busy"]
        || g_DeepBridge.Get("scripts", []).Length || (IsSet(g_StudyChat) && g_StudyChat is Map && g_StudyChat.Get("busy", false))
        || (IsSet(g_StudySessBusy) && g_StudySessBusy)) {
        FanData_SetStatus("Finish or stop the active automation/request before offloading.")
        return false
    }
    root := FanData_ProjectRoot(), python := root . "\fan\DeepSeekBridge\.venv\Scripts\python.exe"
    if !FileExist(python) {
        FanData_SetStatus("Install the Fan DeepSeek Bridge dependencies before running maintenance.")
        return false
    }
    destination := ""
    relocatedSnapshots := ""
    if mode = "consolidate" {
        destination := FileSelect(1, "K:\tracking.db", "Select the moved tracking archive after Explorer finishes", "SQLite (*.db; *.sqlite)")
        if destination = ""
            return false
        relocatedSnapshots := DirSelect("*K:\snapshots", 0, "Select the moved snapshots folder")
        if relocatedSnapshots = ""
            return false
    } else if mode != "analyze" && mode != "images" {
        destination := FanData_SelectDestination(mode, scope)
        if destination = ""
            return false
    }
    id := FormatTime(A_Now, "yyyyMMdd_HHmmss") . "_" . A_TickCount
    dir := root . "\fan\.maintenance\" . id
    DirCreate(dir)
    days := [7, 30, 90][g_FanDataUI["days"].Value]
    request := Map("id", id, "project", root, "mode", mode, "scope", scope, "destination", destination,
        "databases", FanData_DefaultPaths(), "snapshot_root", root . "\data\tracking\snapshots",
        "days", days, "row_limit", 5000, "max_seconds", mode = "analyze" ? 30 : 14400,
        "relocated_snapshots", relocatedSnapshots,
        "bridge_parent", closedJob ? g_DeepBridge["pid"] : 0,
        "parent", closedJob ? DllCall("GetCurrentProcessId", "uint") : 0)
    g_FanDataJob := dir
    FileAppend(TrackJsonEncode(request), dir . "\request.json", "UTF-8-RAW")
    if closedJob {
        summary := reset ? "Archive databases to:`n" . destination . "`nThen replace the originals with empty schemas."
            : mode = "consolidate" ? "Merge the legacy Fan stores and documents into:`n" . destination . "`nEmbed remaining relocated photos; keep source files for verification."
            : mode = "images" ? "Import existing captured photos into SQLite and reclaim verified app-owned file copies."
            : "Export database photos as image files to:`n" . destination
        summary .= "`n`nFan will save, close during the job and restart afterwards so all image references refresh."
            . "`nOther processes using these stores must be closed."
            . "`n`n" . (reset ? "Archive and start fresh?" : "Start this photo job?")
        if MsgBox(summary, reset ? "Archive and reset" : "Database photos", "YesNo Icon?") != "Yes"
            return false
        pending := root . "\fan\.maintenance\pending.json"
        if FileExist(pending) {
            FanData_SetStatus("An interrupted offload needs recovery. Restart Fan to recover it before starting another.")
            return false
        }
        FileAppend(TrackJsonEncode(Map("request", dir . "\request.json")), pending, "UTF-8-RAW")
        ; A separate visible progress window survives the controlled Fan exit.
        Run('"' . A_AhkPath . '" /ErrorStdOut=UTF-8 "' . root . '\fan\StorageMaintenance.ahk" "' . dir . '"', root)
        ExitApp(0)
    }
    command := '"' . python . '" -m fan.data_maintenance.cli "' . dir . '\request.json"'
    Run(command, root, "Hide", &pid)
    g_FanDataPid := pid
    g_FanDataUI["cancel"].Enabled := true
    FanData_SetStatus(mode = "analyze" ? "Consolidating bounded, recent evidence locally…" : "Building and verifying an export…")
    SetTimer(FanData_PollJob, 500)
    return true
}

FanData_DriveInventory() {
    drives := []
    ; USB disks often report FIXED. List every mounted letter without filtering
    ; by device type; unavailable media remain visible with a clear status.
    Loop Parse, DriveGetList() {
        root := A_LoopField . ":\", kind := "Unknown", label := "", free := 0, capacity := 0
        try kind := DriveGetType(root)
        ready := DirExist(root) != "" && kind != "CDROM"
        if ready {
            try label := DriveGetLabel(root)
            try free := DriveGetSpaceFree(root)
            catch
                ready := false
            try capacity := DriveGetCapacity(root)
        }
        drives.Push(Map("root", root, "type", kind, "label", label, "ready", ready,
            "free_mb", free, "capacity_mb", capacity))
    }
    return drives
}

FanData_ValidateDestination(path, mode, scope) {
    if !(mode = "export" || mode = "offload") || !(scope = "databases" || scope = "snapshots")
        throw Error("Choose an export/offload operation for databases or snapshots.")
    path := Trim(path, " `t`r`n" . Chr(34))
    if !RegExMatch(path, "i)^(?:[a-z]:\\|\\\\[^\\]+\\[^\\]+)")
        throw Error("Choose a drive or enter an absolute folder path, such as J:\\FanStorage.")
    if mode = "offload" && scope = "snapshots" && (SubStr(path, 1, 2) = "\\" || DriveGetType(SubStr(path, 1, 3)) = "Network")
        throw Error("Snapshot offload needs a local attached drive for its historical-path junction. Network folders can be used for export.")
    if !DirExist(path)
        throw Error("This folder/drive is unavailable. Reconnect it or choose an existing folder.")
    if scope = "databases" {
        required := 0
        seen := Map()
        for , source in FanData_DefaultPaths() {
            if seen.Has(source)
                continue
            seen[source] := true
            if FileExist(source)
                required += FileGetSize(source)
            if FileExist(source . "-wal")
                required += FileGetSize(source . "-wal")
        }
        margin := Max(67108864, Min(required//20, 2147483648))
        free := DriveGetSpaceFree(path)*1048576
        if free < required+margin
            throw Error("This location has " . Round(free/1073741824, 1) . " GiB free; the databases need approximately "
                . Round((required+margin)/1073741824, 1) . " GiB including transfer headroom. Choose a drive with more free space.")
    }
    length := DllCall("GetFullPathNameW", "str", path, "uint", 0, "ptr", 0, "ptr", 0, "uint")
    resolved := Buffer(length*2)
    if !length || !DllCall("GetFullPathNameW", "str", path, "uint", length, "ptr", resolved, "ptr", 0, "uint")
        throw Error("The folder path could not be resolved.")
    return StrGet(resolved)
}

FanData_SelectDestination(mode, scope) {
    state := Map()
    owner := IsSet(MainGui) && IsObject(MainGui) ? MainGui : 0
    picker := Gui(owner ? "+Owner" . owner.Hwnd : "", "Choose " . mode . " destination")
    picker.SetFont("s10", "Segoe UI")
    picker.Add("Text", "x16 y16 w730 h35", "Select any mounted drive, including external USB disks, then choose its root or a folder.")
    picker.Add("Text", "x16 y57 w100", "Mounted drives")
    driveControl := picker.Add("DropDownList", "x16 y82 w620")
    picker.Add("Button", "x650 y81 w100 h28", "Refresh").OnEvent("Click", (*) => FanData_DestinationRefresh(state))
    picker.Add("Text", "x16 y123 w730", "Destination folder (you can also paste an existing path or mounted-volume folder)")
    pathControl := picker.Add("Edit", "x16 y148 w620 h28")
    picker.Add("Button", "x650 y148 w100 h28", "Browse…").OnEvent("Click", (*) => FanData_DestinationBrowse(state))
    picker.Add("Button", "x16 y187 w135 h28", "Use drive root").OnEvent("Click", (*) => FanData_DestinationDrive(state))
    picker.Add("Button", "x166 y187 w155 h28", "Open in Explorer").OnEvent("Click", (*) => DirExist(pathControl.Value) ? Run(pathControl.Value) : 0)
    message := picker.Add("Text", "x16 y231 w730 h70", "Drive labels and free space are shown above. Refresh after connecting another drive.")
    picker.Add("Button", "x480 y317 w130 h32 Default", "Use this folder").OnEvent("Click", (*) => FanData_DestinationAccept(state))
    picker.Add("Button", "x620 y317 w130 h32", "Cancel").OnEvent("Click", (*) => picker.Destroy())
    state := Map("gui", picker, "drive", driveControl, "path", pathControl, "message", message,
        "mode", mode, "scope", scope, "result", "", "drives", [])
    driveControl.OnEvent("Change", (*) => FanData_DestinationDrive(state))
    picker.OnEvent("Close", (*) => picker.Destroy())
    picker.OnEvent("Escape", (*) => picker.Destroy())
    FanData_DestinationRefresh(state)
    if owner
        owner.Opt("+Disabled")
    try {
        hwnd := picker.Hwnd
        picker.Show("w768 h368")
        WinWaitClose("ahk_id " . hwnd)
    } finally {
        if owner {
            owner.Opt("-Disabled")
            owner.Show()
        }
    }
    return state["result"]
}

FanData_DestinationRefresh(state) {
    previous := state["path"].Value, labels := []
    state["drives"] := FanData_DriveInventory()
    for , drive in state["drives"]
        labels.Push(drive["root"] . "  " . (drive["label"] != "" ? drive["label"] : "(no label)") . "  [" . drive["type"] . "]  "
            . (drive["ready"] ? Round(drive["free_mb"]/1024, 1) . " GiB free of " . Round(drive["capacity_mb"]/1024, 1) . " GiB" : "Unavailable / no writable media"))
    state["drive"].Delete()
    state["drive"].Add(labels)
    if labels.Length {
        index := 1
        for i, drive in state["drives"]
            if SubStr(previous, 1, 3) = drive["root"]
                index := i
        state["drive"].Choose(index)
        if previous = ""
            FanData_DestinationDrive(state)
    }
}

FanData_DestinationDrive(state) {
    index := state["drive"].Value
    if index && index <= state["drives"].Length {
        drive := state["drives"][index]
        state["path"].Value := drive["root"]
        state["message"].Value := drive["ready"] ? "Choose the drive root directly or Browse to a folder on it." : "This drive is listed but unavailable. Reconnect/unlock it, then Refresh."
    }
}

FanData_DestinationBrowse(state) {
    initial := state["path"].Value
    if !DirExist(initial) {
        state["message"].Value := "Choose a connected drive before browsing its folders."
        return
    }
    selected := DirSelect("*" . initial, 3, "Choose a folder on the selected drive")
    if selected != ""
        state["path"].Value := selected
}

FanData_DestinationAccept(state) {
    try {
        state["result"] := FanData_ValidateDestination(state["path"].Value, state["mode"], state["scope"])
        state["gui"].Destroy()
    } catch as err {
        state["message"].Value := err.Message
    }
}

FanData_RecoveryBootstrap() {
    root := FanData_ProjectRoot(), pending := root . "\fan\.maintenance\pending.json"
    if !FileExist(pending)
        return
    record := TrackJsonDecode(FileRead(pending, "UTF-8")), request := record["request"]
    SplitPath(request,, &jobDir)
    try {
        state := TrackJsonDecode(FileRead(jobDir . "\status.json", "UTF-8"))
        if state.Get("worker_pid", 0) && ProcessExist(state["worker_pid"]) {
            MsgBox("A controlled storage transfer is still running. Wait for its progress window to finish before reopening Fan.", "Storage transfer active")
            ExitApp(0)
        }
    }
    python := root . "\fan\DeepSeekBridge\.venv\Scripts\python.exe"
    code := RunWait('"' . python . '" -m fan.data_maintenance.cli --recover "' . request . '"', root, "Hide")
    if code != 0 {
        MsgBox("Interrupted snapshot/storage cutover could not be recovered. Original data and its job journal are retained. Reconnect the selected drive and reopen Fan.", "Storage recovery required")
        ExitApp(1)
    }
}

FanData_SetStatus(value) {
    if g_FanDataUI.Has("status")
        g_FanDataUI["status"].Value := value
}

FanData_PollJob() {
    global g_FanDataPid
    try {
        state := TrackJsonDecode(FileRead(g_FanDataJob . "\status.json", "UTF-8"))
        FanData_SetStatus(state.Get("message", state.Get("phase", "Working…")))
        if RegExMatch(state.Get("phase", ""), "^(complete|error|cancelled|deferred)$") {
            SetTimer(FanData_PollJob, 0)
            g_FanDataUI["cancel"].Enabled := false
            g_FanDataPid := 0
            if state["phase"] = "complete" && state.Has("report")
                FanData_ViewInsights()
        } else if g_FanDataPid && !ProcessExist(g_FanDataPid) && !(state.Get("worker_pid", 0) && ProcessExist(state["worker_pid"])) {
            SetTimer(FanData_PollJob, 0)
            g_FanDataUI["cancel"].Enabled := false
            g_FanDataPid := 0
            FanData_SetStatus("Worker stopped unexpectedly before completion. Open job history; original storage is retained.")
        }
    } catch {
        if g_FanDataPid && !ProcessExist(g_FanDataPid) {
            SetTimer(FanData_PollJob, 0)
            g_FanDataUI["cancel"].Enabled := false
            g_FanDataPid := 0
            FanData_SetStatus("Job stopped unexpectedly. Open job history for its log; original storage is retained.")
        }
    }
}

FanData_CancelJob() {
    if g_FanDataJob != ""
        try FileAppend("cancel", g_FanDataJob . "\cancel", "UTF-8-RAW")
}

FanData_ViewInsights() {
    path := FanData_ProjectRoot() . "\data\learning_insights\latest.md"
    if !FanFileExist(path) {
        FanData_SetStatus("Run Consolidate insights to build the first report.")
        return
    }
    monitor := LearningValidation_Monitor()
    if !monitor {
        FanData_SetStatus("A secondary display is required for the learning report window.")
        return
    }
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    width := Min(960, right-left-48), height := Min(680, bottom-top-64)
    view := Gui("+Resize -DPIScale", "Consolidated learning insights")
    view.SetFont("s10", "Segoe UI")
    text := view.Add("Edit", "x12 y12 w936 h656 ReadOnly Multi +VScroll", FanFileRead(path, "UTF-8"))
    view.OnEvent("Size", (g, state, w, h) => state != -1 ? text.Move(12, 12, Max(300, w-24), Max(200, h-24)) : 0)
    view.Show("NA x" . (left+12) . " y" . (top+12) . " w" . width . " h" . height)
}

FanData_ShowLocations() {
    if FanData_Routes().Has("unified_db") {
        path := FanData_Routes()["unified_db"]
        MsgBox("Active database:`n" . path . "`n`nPhotos, workflows, learning, notes and settings share this file."
            . "`nClose Fan before manually moving it. The next launch seeds an empty database at this path.", "Fan storage")
        return
    }
    value := "Managed Fan databases:`n"
    for role, path in FanData_DefaultPaths() {
        bytes := FileExist(path) ? FileGetSize(path) : 0
        value .= "`n" . role . ": " . path . " (" . Round(bytes/1073741824, 3) . " GB)"
    }
    value .= "`n`nSnapshots: " . FanData_ProjectRoot() . "\data\tracking\snapshots"
    config := FanData_Config()
    if config.Has("snapshots")
        value .= "`nPhysical target: " . config["snapshots"].Get("target", "")
    MsgBox(value, "Current storage locations")
}

FanData_SetLearning(*) {
    config := FanData_Config().Clone()
    config["auto_discovery"] := !!MainGui["AutoDiscover"].Value
    config["learning_validation"] := !!MainGui["LearnValidation"].Value
    config["learning_monitor"] := [0, 2, 3][g_FanDataUI["monitor"].Value]
    FanData_SaveConfig(config)
    AutoDiscovery_Start()
    LearningValidation_Show()
    FanData_SetStatus(LearningValidation_Monitor() ? "Learning feedback is on the selected secondary display." : "No secondary display is available; background feedback stays hidden.")
}
