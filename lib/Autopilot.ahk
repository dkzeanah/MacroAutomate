; ═══════════════════════════════════════════════════════════════════════════════
; Autopilot.ahk - routine discovery, plain-English workflows, portals, run ledger
; ═══════════════════════════════════════════════════════════════════════════════
; The analysis lives in the Python package fan\autopilot (standard library only),
; run as a short job: request.json in, result.json out. This module owns the
; schema, the job runner, the run ledger/audit trail used by the workflow engine,
; portal profiles and the discovery notifications. UI: lib\AutopilotUI.ahk.
; ═══════════════════════════════════════════════════════════════════════════════

#Include AutopilotActions.ahk
#Include SelfHeal.ahk
#Include AutopilotUI.ahk

global g_Autopilot := Map("jobs", Map(), "routines", [], "ui", Map(), "compiled", 0, "lastRun", 0,
    "lastReport", "", "toast", 0, "ready", false, "scanBusy", false)
global g_AutopilotRun := 0

; ─── Startup and schema ────────────────────────────────────────────────────────

Autopilot_Start() {
    global g_Autopilot
    if !TrackDB_Ready() && !TrackDB_Init()
        return false
    try {
        Autopilot_ApplySchema()
        g_Autopilot["ready"] := true
    } catch as err {
        LogErrorToFile(err, "caught", "Autopilot schema")
        return false
    }
    try Autopilot_PruneJobs()
    SetTimer(Autopilot_ScanTick, 5 * 60000)
    SetTimer(Autopilot_ScanTick, -90000)  ; first look shortly after startup, never during it
    return true
}

Autopilot_ApplySchema() {
    db := TrackDB()
    db.Run("CREATE TABLE IF NOT EXISTS autopilot_routine (id TEXT PRIMARY KEY, name TEXT, data TEXT, status TEXT DEFAULT 'new', "
        . "first_found TEXT, last_found TEXT, notified INTEGER DEFAULT 0, workflow TEXT DEFAULT '')")
    db.Run("CREATE TABLE IF NOT EXISTS autopilot_portal (name TEXT PRIMARY KEY, url TEXT, title_hint TEXT, username_label TEXT, "
        . "password_label TEXT, submit_label TEXT, notes TEXT, login_workflow TEXT DEFAULT '', created TEXT, updated TEXT)")
    db.Run("CREATE TABLE IF NOT EXISTS autopilot_run (id TEXT PRIMARY KEY, workflow TEXT, portal TEXT, started TEXT, finished TEXT, "
        . "ok INTEGER, aborted INTEGER, failed_step INTEGER, completed INTEGER, heals INTEGER, approvals INTEGER, mode TEXT, error TEXT, dir TEXT)")
    db.Run("CREATE INDEX IF NOT EXISTS ix_autopilot_run_started ON autopilot_run(started DESC)")
    db.Run("CREATE TABLE IF NOT EXISTS autopilot_heal (id INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT, run_id TEXT, workflow TEXT, "
        . "step_index INTEGER, action TEXT, target TEXT, param TEXT, strategy TEXT, confidence REAL, x INTEGER, y INTEGER, window TEXT, "
        . "rel_x REAL, rel_y REAL, label TEXT, detail TEXT, status TEXT DEFAULT 'open', previous TEXT DEFAULT '')")
    db.Run("CREATE TABLE IF NOT EXISTS autopilot_anchor (key TEXT PRIMARY KEY, workflow TEXT, step_index INTEGER, action TEXT, target TEXT, "
        . "exe TEXT, title TEXT, class TEXT, rel_x REAL, rel_y REAL, win_w INTEGER, win_h INTEGER, label TEXT, label_dx INTEGER, "
        . "label_dy INTEGER, sample TEXT, successes INTEGER DEFAULT 0, updated TEXT)")
    db.Run("CREATE INDEX IF NOT EXISTS ix_autopilot_anchor_workflow ON autopilot_anchor(workflow)")
}

Autopilot_DataDir() {
    dir := APP_ROOT . "\data\autopilot"
    if !DirExist(dir)
        DirCreate(dir)
    return dir
}

; ─── Python job runner ─────────────────────────────────────────────────────────

Autopilot_SearchPath(exe) {
    buf := Buffer(1040, 0)
    if DllCall("SearchPathW", "Ptr", 0, "Str", exe, "Ptr", 0, "UInt", 520, "Ptr", buf, "Ptr", 0, "UInt")
        return StrGet(buf, "UTF-16")
    return ""
}

; The bridge virtual environment, else any real Python 3 (the helper needs only the
; standard library). The Microsoft Store "python.exe" stub is skipped.
Autopilot_Python() {
    venv := APP_ROOT . "\fan\DeepSeekBridge\.venv\Scripts\python.exe"
    if FileExist(venv)
        return '"' . venv . '"'
    if (launcher := Autopilot_SearchPath("py.exe")) != ""
        return '"' . launcher . '" -3'
    path := Autopilot_SearchPath("python.exe")
    if path != "" && !InStr(path, "\WindowsApps\")
        return '"' . path . '"'
    return ""
}

Autopilot_Job(mode, request, callback, timeoutMs := 120000) {
    global g_Autopilot
    jobs := g_Autopilot["jobs"]
    if jobs.Has(mode) && ProcessExist(jobs[mode]["pid"]) {
        callback.Call(Map("ok", false, "error", "A " . mode . " job is already running"))
        return false
    }
    python := Autopilot_Python()
    if python = "" {
        callback.Call(Map("ok", false, "error", "Python 3 was not found. Install the DeepSeek Bridge (Settings) or Python 3.10+."))
        return false
    }
    id := FormatTime(A_Now, "yyyyMMdd_HHmmss") . "_" . mode . "_" . Mod(A_TickCount, 1000000)
    dir := Autopilot_DataDir() . "\jobs\" . id
    DirCreate(dir)
    request["mode"] := mode
    file := FileOpen(dir . "\request.json", "w", "UTF-8-RAW")
    file.Write(TrackJsonEncode(request))
    file.Close()
    try Run(python . ' -m fan.autopilot.cli "' . dir . '\request.json"', APP_ROOT, "Hide", &pid)
    catch as err {
        callback.Call(Map("ok", false, "error", "Could not start the Autopilot helper: " . err.Message))
        return false
    }
    jobs[mode] := Map("pid", pid, "dir", dir, "callback", callback, "deadline", A_TickCount + timeoutMs, "exitedAt", 0)
    SetTimer(Autopilot_PollJobs, 300)
    return true
}

Autopilot_PollJobs() {
    global g_Autopilot
    jobs := g_Autopilot["jobs"], finished := []
    for mode, job in jobs {
        result := 0, path := job["dir"] . "\result.json"
        running := ProcessExist(job["pid"])
        if !running && FileExist(path) {
            try result := TrackJsonDecode(FileRead(path, "UTF-8"))
            catch as err
                result := Map("ok", false, "error", "Unreadable Autopilot result: " . err.Message)
        } else if !running {
            ; Allow a moment for the final rename before declaring a crash.
            if !job["exitedAt"]
                job["exitedAt"] := A_TickCount
            else if A_TickCount - job["exitedAt"] > 1500
                result := Map("ok", false, "error", "The Autopilot helper stopped without a result (see " . job["dir"] . ")")
        } else if A_TickCount > job["deadline"] {
            try ProcessClose(job["pid"])
            result := Map("ok", false, "error", "The Autopilot " . mode . " job took too long and was stopped")
        }
        if IsObject(result)
            finished.Push([mode, job, result])
    }
    for , item in finished {
        jobs.Delete(item[1])
        try item[2]["callback"].Call(item[3])
        catch as err
            LogErrorToFile(err, "caught", "Autopilot " . item[1] . " result")
    }
    if !jobs.Count
        SetTimer(Autopilot_PollJobs, 0)
}

Autopilot_PruneJobs(keep := 40) {
    dirs := []
    loop files Autopilot_DataDir() . "\jobs\*", "D"
        dirs.Push(A_LoopFileFullPath)
    if dirs.Length <= keep
        return
    ; Names start with a sortable timestamp; enumeration order is not guaranteed.
    sorted := StrSplit(Sort(StrJoin(dirs, "`n")), "`n")
    loop sorted.Length - keep
        try DirDelete(sorted[A_Index], true)
}

; ─── What the app knows (for validation and the compiler) ──────────────────────

Autopilot_Catalog() {
    actions := []
    for , name in GetWorkflowActionNames()
        if name != "Learned Rehearsal Step"
            actions.Push(Map("name", name, "spec", GetWorkflowActionSpec(name)))
    return actions
}

Autopilot_Context(includeTitles := false) {
    global g_Coordinates, g_Patterns, g_Sequences
    context := Map("coordinates", [], "patterns", [], "workflows", [], "credentials", [], "portals", [], "windows", [])
    for name in g_Coordinates
        context["coordinates"].Push(name)
    for name in g_Patterns
        context["patterns"].Push(name)
    for name in g_Sequences
        context["workflows"].Push(name)
    if TrackDB_Ready() {
        try {
            elements := []
            for , row in TrackDB().Query("SELECT name FROM element WHERE name<>'' GROUP BY name ORDER BY MAX(hits) DESC LIMIT 200")
                elements.Push(row["name"])
            context["elements"] := elements
        }
    }
    for name, portal in Autopilot_Portals() {
        context["portals"].Push(Map("name", name, "url", portal["url"]))
        if AutopilotCred_Exists(name)
            context["credentials"].Push(name)
    }
    seen := Map(), self := DllCall("GetCurrentProcessId", "UInt")
    for hwnd in WinGetList() {
        try {
            if WinGetPID("ahk_id " . hwnd) = self || !(WinGetStyle("ahk_id " . hwnd) & 0x10000000)
                continue
            title := WinGetTitle("ahk_id " . hwnd), exe := WinGetProcessName("ahk_id " . hwnd)
            if title = "" || exe = ""
                continue
            ; Process names by default; window titles (which can name documents or people) only on request.
            entry := includeTitles ? SubStr(title, 1, 80) : "ahk_exe " . exe
            if !seen.Has(entry) {
                seen[entry] := true
                context["windows"].Push(entry)
            }
        }
        if context["windows"].Length >= 30
            break
    }
    return context
}

; ─── Run ledger and audit trail (called by the workflow engine) ────────────────

Autopilot_WorkflowNameFor(steps) {
    global g_Sequences, g_CurrentSequenceSteps
    for name, seq in g_Sequences
        if seq["steps"] = steps
            return name
    if IsSet(g_CurrentSequenceSteps) && g_CurrentSequenceSteps = steps
        return "(editor workflow)"
    return "(unsaved workflow)"
}

Autopilot_RunBegin(steps, opts) {
    global g_AutopilotRun
    static sequence := 0
    g_AutopilotRun := 0
    try {
        name := opts is Map ? opts.Get("sequenceName", "") : ""
        if name = ""
            name := Autopilot_WorkflowNameFor(steps)
        interactive := !(opts is Map) || opts.Get("interactive", true)
        ; Timestamp + tick + per-process counter: runs started in the same tick stay distinct.
        runId := FormatTime(A_Now, "yyyyMMdd_HHmmss") . "_" . Format("{:06}", Mod(A_TickCount, 1000000)) . "_" . Format("{:03}", Mod(++sequence, 1000))
        g_AutopilotRun := Map("run_id", runId,
            "workflow", name, "portal", opts is Map ? opts.Get("portal", "") : "", "started", Autopilot_Now(),
            "user", A_UserName, "mode", interactive ? "interactive" : "unattended",
            "evidenceMode", opts is Map ? opts.Get("evidence", "") : "", "steps", [], "evidence", [],
            "dir", "", "heals", 0, "approvals", 0, "stepStart", A_TickCount, "pending", Map())
    } catch as err
        try LogErrorToFile(err, "caught", "Autopilot_RunBegin")
}

Autopilot_StepBegin(index, step) {
    global g_AutopilotRun
    if IsObject(g_AutopilotRun)
        g_AutopilotRun["stepStart"] := A_TickCount, g_AutopilotRun["pending"] := Map()
}

Autopilot_RunNote(kind, data) {
    global g_AutopilotRun
    if !IsObject(g_AutopilotRun)
        return
    g_AutopilotRun["pending"][kind] := data
    if kind = "approval"
        g_AutopilotRun["approvals"] += 1
}

Autopilot_StepEnd(index, step, status, errorText := "", heal := 0) {
    global g_AutopilotRun
    run := g_AutopilotRun
    if !IsObject(run) || !IsObject(step)
        return
    try {
        record := Map("index", index, "action", step["action"], "target", step.Get("target", ""), "param", step.Get("param", ""),
            "status", status, "ms", A_TickCount - run["stepStart"], "at", Autopilot_Now())
        if errorText != ""
            record["error"] := StudyConsole_Redact(errorText)
        if heal is Map {
            record["heal"] := heal
            run["heals"] += 1
            if status = "completed"
                record["status"] := "healed"
        }
        pending := run["pending"]
        if pending.Has("approval") {
            record["approval"] := pending["approval"]
            record["status"] := pending["approval"]["decision"]
        }
        if pending.Has("human")
            record["human"] := pending["human"], record["status"] := status = "completed" ? "human" : status
        quiet := Map("Wait", 1, "Loop Start", 1, "Loop End", 1, "Loop Break", 1, "Set Variable", 1, "If Contains", 1,
            "If Variable", 1, "Grab Clipboard", 1, "Show Notification", 1, "Capture Evidence", 1, "Ask Input", 1)
        if status = "failed" || run["evidenceMode"] = "steps" && !quiet.Has(step["action"]) {
            file := Autopilot_EvidenceCapture("window:A", "Step " . index . " · " . step["action"], false, index)
            if file != ""
                record["evidence"] := file
        }
        if run["steps"].Length < 2000
            run["steps"].Push(record)
    } catch as err
        try LogErrorToFile(err, "caught", "Autopilot_StepEnd")
}

Autopilot_RunEnd(out) {
    global g_AutopilotRun, g_Autopilot
    run := g_AutopilotRun
    g_AutopilotRun := 0
    if !IsObject(run) || !IsObject(out)
        return
    try {
        run["finished"] := Autopilot_Now()
        run["ok"] := out["ok"] ? 1 : 0, run["aborted"] := out["aborted"] ? 1 : 0
        run["completed"] := out["completed"], run["failed_step"] := out["failed_step"]
        run["error"] := StudyConsole_Redact(out["error"])
        keep := run["dir"] != "" || run["heals"] || run["approvals"] || run["evidenceMode"] != "" || run["portal"] != ""
        if keep {
            if run["dir"] = ""
                run["dir"] := Autopilot_DataDir() . "\runs\" . run["run_id"]
            DirCreate(run["dir"])
            record := Map()
            for key in ["run_id", "workflow", "portal", "started", "finished", "user", "mode", "ok", "aborted", "completed",
                "failed_step", "error", "heals", "approvals", "steps", "evidence"]
                record[key] := run[key]
            file := FileOpen(run["dir"] . "\run.json", "w", "UTF-8-RAW")
            file.Write(TrackJsonEncode(record))
            file.Close()
        }
        if TrackDB_Ready() {
            db := TrackDB()
            db.Run("INSERT OR REPLACE INTO autopilot_run(id,workflow,portal,started,finished,ok,aborted,failed_step,completed,heals,approvals,mode,error,dir) "
                . "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)", run["run_id"], run["workflow"], run["portal"], run["started"], run["finished"],
                run["ok"], run["aborted"], run["failed_step"], run["completed"], run["heals"], run["approvals"], run["mode"],
                SubStr(run["error"], 1, 500), keep ? run["dir"] : "")
            if Mod(A_TickCount, 20) = 0
                db.Run("DELETE FROM autopilot_run WHERE id NOT IN (SELECT id FROM autopilot_run ORDER BY started DESC LIMIT 5000)")
        }
        g_Autopilot["lastRun"] := run
        if keep && (run["evidenceMode"] != "" || run["portal"] != "")
            Autopilot_BuildReport(run["dir"], run.Get("openReport", true))
    } catch as err
        try LogErrorToFile(err, "caught", "Autopilot_RunEnd")
}

; Screenshot into the current run's folder (or a dated folder outside a run). Returns the file name.
Autopilot_EvidenceCapture(area, label, gallery := true, stepIndex := 0) {
    global g_AutopilotRun
    region := ParseRegionCoords(area)
    if !region
        return ""
    run := g_AutopilotRun
    if IsObject(run) {
        if run["dir"] = ""
            run["dir"] := Autopilot_DataDir() . "\runs\" . run["run_id"]
        dir := run["dir"]
    } else
        dir := Autopilot_DataDir() . "\evidence\" . FormatTime(A_Now, "yyyy-MM-dd")
    if !DirExist(dir)
        DirCreate(dir)
    count := 0
    loop files dir . "\*.png"
        count++
    file := Format("{:03}", count + 1) . "_" . Trim(RegExReplace(SubStr(label, 1, 40), "[^A-Za-z0-9]+", "_"), "_") . ".png"
    if !Autopilot_CaptureRegion(region, dir . "\" . file)
        return ""
    if IsObject(run) && gallery
        run["evidence"].Push(Map("label", label, "file", file, "at", Autopilot_Now(), "step", stepIndex))
    return file
}

Autopilot_BuildReport(dir, openWhenDone := false) {
    global g_Autopilot
    Autopilot_Job("portal_report", Map("run_dir", dir), Autopilot_ReportDone.Bind(openWhenDone), 60000)
}

Autopilot_ReportDone(openWhenDone, result) {
    global g_Autopilot
    if !result.Get("ok", false) {
        Autopilot_Status("portals", "Audit report failed: " . result.Get("error", "unknown error"))
        return
    }
    g_Autopilot["lastReport"] := result["report"]
    Autopilot_Status("portals", "Audit report ready: " . result["steps"] . " steps, " . result["evidence"] . " screenshots, "
        . result["heals"] . " self-heals, " . result["approvals"] . " approvals.")
    try AutopilotUI_RefreshRuns()
    if openWhenDone
        try Run('"' . result["report"] . '"')
}

; ─── Portals ───────────────────────────────────────────────────────────────────

Autopilot_Portals() {
    out := Map()
    if !TrackDB_Ready()
        return out
    try {
        for , row in TrackDB().Query("SELECT * FROM autopilot_portal ORDER BY name")
            out[row["name"]] := row
    }
    return out
}

Autopilot_PortalHint(name) {
    if !TrackDB_Ready()
        return ""
    try return TrackDB().Scalar("SELECT title_hint FROM autopilot_portal WHERE name=?", name)
    return ""
}

Autopilot_ValidatePortal(profile) {
    name := Trim(profile.Get("name", "")), url := Trim(profile.Get("url", ""))
    if !AutopilotCred_ValidName(name)
        return "Portal name must be 1..60 letters, numbers, spaces, _ . -"
    if !RegExMatch(url, "i)^https://[^\s`"'<>]+$") {
        if !RegExMatch(url, "i)^http://(localhost|127\.0\.0\.1|[^/\s]+\.(localhost|test))([:/][^\s]*)?$")
            return "Use the portal's https:// address (passwords are never typed into plain http pages)"
    }
    for key in ["title_hint", "username_label", "password_label", "submit_label"]
        if StrLen(profile.Get(key, "")) > 60
            return key . " is too long (60 characters)"
    return ""
}

Autopilot_PortalSave(profile, previousName := "") {
    problem := Autopilot_ValidatePortal(profile)
    if problem != ""
        throw ValueError(problem)
    name := Trim(profile["name"])
    hint := Trim(profile.Get("title_hint", ""))
    if hint = ""
        hint := Autopilot_HostHint(profile["url"])
    now := Autopilot_Now(), db := TrackDB()
    if previousName != "" && previousName != name {
        if db.Scalar("SELECT COUNT(*) FROM autopilot_portal WHERE name=?", name)
            throw ValueError("A portal named '" . name . "' already exists")
        db.Run("DELETE FROM autopilot_portal WHERE name=?", previousName)
    }
    db.Run("INSERT INTO autopilot_portal(name,url,title_hint,username_label,password_label,submit_label,notes,created,updated) "
        . "VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(name) DO UPDATE SET url=excluded.url,title_hint=excluded.title_hint,"
        . "username_label=excluded.username_label,password_label=excluded.password_label,submit_label=excluded.submit_label,"
        . "notes=excluded.notes,updated=excluded.updated", name, Trim(profile["url"]), hint,
        Trim(profile.Get("username_label", "")), Trim(profile.Get("password_label", "")), Trim(profile.Get("submit_label", "")),
        Trim(profile.Get("notes", "")), now, now)
    return name
}

Autopilot_PortalDelete(name) {
    if TrackDB_Ready()
        TrackDB().Run("DELETE FROM autopilot_portal WHERE name=?", name)
    AutopilotCred_Delete(name)
}

; ─── Saving generated workflows (same rules as the agent API) ──────────────────

Autopilot_SaveWorkflow(name, steps, overwrite := false) {
    global g_Sequences, g_LastWorkflowSaveError
    name := Trim(RegExReplace(name, "[\r\n\t]+", " "))
    if name = "" || StrLen(name) > 120
        throw ValueError("A workflow name of 1..120 characters is required")
    if g_Sequences.Has(name) && !overwrite
        throw ValueError("A workflow named '" . name . "' already exists")
    if !(steps is Array) || !steps.Length || steps.Length > 300
        throw ValueError("A workflow needs 1..300 steps")
    allowed := Map()
    for , action in GetWorkflowActionNames()
        allowed[action] := true
    accepted := [], depth := 0
    for index, step in steps {
        action := step.Get("action", "")
        if !allowed.Has(action)
            throw ValueError("Step " . index . " uses an unknown action: " . action)
        spec := GetWorkflowActionSpec(action)
        target := String(step.Get("target", "")), param := String(step.Get("param", ""))
        if spec["targetRequired"] && Trim(target) = "" || spec["paramRequired"] && Trim(param) = ""
            throw ValueError("Step " . index . " (" . action . ") is missing its " . (Trim(target) = "" && spec["targetRequired"] ? spec["targetLabel"] : spec["paramLabel"]))
        if action = "Loop Start"
            depth++
        else if action = "Loop End" && --depth < 0
            throw ValueError("Step " . index . ": Loop End without Loop Start")
        failsafe := step.Get("failsafe", Map())
        accepted.Push(Map("action", action, "target", target, "param", param, "enabled", step.Get("enabled", true) ? 1 : 0,
            "failsafe", NormalizeStepFailsafe(failsafe is Map ? failsafe : Map())))
    }
    if depth != 0
        throw ValueError("The workflow has a Loop Start without a Loop End")
    existed := g_Sequences.Has(name), prior := existed ? g_Sequences[name] : 0
    g_Sequences[name] := Map("steps", accepted, "speed", existed ? prior.Get("speed", 1.0) : 1.0,
        "hotkey", existed ? prior.Get("hotkey", "") : "", "hotstring", existed ? prior.Get("hotstring", "") : "")
    if !SaveSequences() {
        if existed
            g_Sequences[name] := prior
        else
            g_Sequences.Delete(name)
        throw Error("Workflow could not be saved: " . g_LastWorkflowSaveError)
    }
    try RefreshSeqLV()
    return name
}

Autopilot_RunWorkflow(name, opts := 0) {
    global g_Sequences, g_WorkflowRunning, g_AbortSequence, g_IsPaused
    if !g_Sequences.Has(name)
        throw ValueError("Workflow '" . name . "' is not saved")
    if g_WorkflowRunning
        throw Error("Another workflow is running; wait for it to finish")
    options := Map("sequenceName", name)
    if opts is Map
        for key, value in opts
            options[key] := value
    g_AbortSequence := false, g_IsPaused := false
    seq := g_Sequences[name]
    return ExecuteSequenceVerified(seq["steps"], seq.Get("speed", 1.0), options)
}

; ─── Routine discovery and notifications ───────────────────────────────────────

Autopilot_ScanTick() {
    global g_Autopilot, g_WorkflowRunning
    if !g_Autopilot["ready"] || g_Autopilot["scanBusy"] || g_WorkflowRunning
        return
    if TrackDB_MetaGet("autopilot_scan_enabled", "1") != "1"
        return
    last := TrackDB_MetaGet("autopilot_last_scan", "")
    if last != "" && DateDiff(A_Now, last, "Minutes") < 30
        return
    if A_TimeIdlePhysical < 20000  ; wait for a pause in the person's work
        return
    Autopilot_ScanRoutines(false)
}

Autopilot_ScanRoutines(manual := true) {
    global g_Autopilot, g_TrackDBPath
    if !TrackDB_Ready() {
        Autopilot_Status("routines", "The tracking database is not open, so there is no usage history to analyze.")
        return false
    }
    excluded := []
    for , row in TrackDB().Query("SELECT id FROM autopilot_routine WHERE status IN ('dismissed','automated')")
        excluded.Push(row["id"])
    g_Autopilot["scanBusy"] := true
    Autopilot_Status("routines", "Looking through the last 30 days of local activity...")
    return Autopilot_Job("routines", Map("db", g_TrackDBPath, "lookback_days", 30, "excluded", excluded,
        "min_occurrences", 3, "limit", 25), Autopilot_RoutinesDone.Bind(manual), 180000)
}

Autopilot_RoutinesDone(manual, result) {
    global g_Autopilot
    g_Autopilot["scanBusy"] := false
    TrackDB_MetaSet("autopilot_last_scan", A_Now)
    if !result.Get("ok", false) {
        Autopilot_Status("routines", "Routine search failed: " . result.Get("error", "unknown error"))
        return
    }
    db := TrackDB(), now := Autopilot_Now()
    for , routine in result["routines"]
        db.Run("INSERT INTO autopilot_routine(id,name,data,status,first_found,last_found) VALUES(?,?,?,'new',?,?) "
            . "ON CONFLICT(id) DO UPDATE SET name=excluded.name,data=excluded.data,last_found=excluded.last_found",
            routine["id"], routine["name"], TrackJsonEncode(routine), now, now)
    count := result["routines"].Length
    Autopilot_Status("routines", (count ? "Found " . count . " repeated routine" . (count = 1 ? "" : "s") : "No repeated routines yet")
        . " in " . result["events_analyzed"] . " recorded actions over " . Round(result["observed_days"], 1) . " days."
        . (result["events_analyzed"] < 200 ? " Keep Usage Predictor learning on so Fan can see your routines." : ""))
    try AutopilotUI_RefreshRoutines()
    if !manual
        Autopilot_MaybeNotify()
}

Autopilot_Routines(includeDismissed := false) {
    out := []
    if !TrackDB_Ready()
        return out
    for , row in TrackDB().Query("SELECT * FROM autopilot_routine " . (includeDismissed ? "" : "WHERE status<>'dismissed' ")
        . "ORDER BY CASE status WHEN 'new' THEN 0 WHEN 'snoozed' THEN 1 WHEN 'automated' THEN 2 ELSE 3 END, last_found DESC LIMIT 100") {
        try {
            data := TrackJsonDecode(row["data"])
            data["status"] := row["status"], data["workflow"] := row["workflow"], data["notified"] := row["notified"]
            out.Push(data)
        }
    }
    return out
}

Autopilot_SetRoutineStatus(id, status, workflow := "") {
    if TrackDB_Ready()
        TrackDB().Run("UPDATE autopilot_routine SET status=?, workflow=CASE WHEN ?<>'' THEN ? ELSE workflow END WHERE id=?",
            status, workflow, workflow, id)
}

Autopilot_MaybeNotify() {
    if TrackDB_MetaGet("autopilot_toasts", "1") != "1"
        return
    today := FormatTime(A_Now, "yyyyMMdd")
    sent := TrackDB_MetaGet("autopilot_toasts_" . today, "0")
    if Integer(sent) >= 2
        return
    best := 0
    for , routine in Autopilot_Routines() {
        if routine["status"] != "new" || routine["notified"] || routine["occurrences"] < 4 || routine["minutes_observed"] < 1
            continue
        if !IsObject(best) || routine["minutes_observed"] > best["minutes_observed"]
            best := routine
    }
    if !IsObject(best)
        return
    TrackDB().Run("UPDATE autopilot_routine SET notified=1 WHERE id=?", best["id"])
    TrackDB_MetaSet("autopilot_toasts_" . today, String(Integer(sent) + 1))
    week := best["occurrences_last_7_days"]
    times := week >= 3 ? week . " times this week" : best["occurrences"] . " times recently"
    minutes := week >= 3 ? best["minutes_last_7_days"] : best["minutes_observed"]
    Autopilot_Toast("Fan spotted a routine",
        "You've done “" . best["name"] . "” " . times . " (about " . Autopilot_Minutes(minutes) . "). Want Fan to do it for you?",
        [["Show me", Autopilot_OpenRoutine.Bind(best["id"])], ["Not now", (*) => 0],
         ["Don't suggest", (*) => (Autopilot_SetRoutineStatus(best["id"], "dismissed"), AutopilotUI_RefreshRoutines())]])
}

Autopilot_Minutes(minutes) {
    if minutes < 1
        return Round(minutes * 60) . " seconds"
    return Round(minutes) = 1 ? "1 minute" : Round(minutes) . " minutes"
}

Autopilot_OpenRoutine(id, *) {
    global MainGui, g_Autopilot
    g_Autopilot["selectRoutine"] := id
    try MainGui.Show()
    FanNav_Open(26)
}

; Bottom-right notification with action buttons; it never steals focus.
Autopilot_Toast(title, body, buttons, seconds := 25) {
    global g_Autopilot
    try g_Autopilot["toast"].Destroy()
    toast := Gui("+AlwaysOnTop -Caption +ToolWindow +Border +E0x08000000", "Fan")
    toast.BackColor := "0x1F2430"
    toast.MarginX := 16, toast.MarginY := 12
    toast.SetFont("s11 cWhite bold", "Segoe UI")
    toast.Add("Text", "w360", title)
    toast.SetFont("s10 cD8DEE9 norm", "Segoe UI")
    toast.Add("Text", "w360 y+6", body)
    toast.SetFont("s9", "Segoe UI")
    first := true
    for , spec in buttons {
        button := toast.Add("Button", (first ? "xm y+12" : "x+8 yp") . " h26 w" . Max(80, StrLen(spec[1]) * 8 + 24), spec[1])
        button.OnEvent("Click", Autopilot_ToastClick.Bind(toast, spec[2]))
        first := false
    }
    toast.Show("NoActivate Hide")
    toast.GetPos(, , &w, &h)
    MonitorGetWorkArea(MonitorGetPrimary(), , , &right, &bottom)
    toast.Show("NoActivate x" . (right - w - 18) . " y" . (bottom - h - 18))
    g_Autopilot["toast"] := toast
    SetTimer(() => (IsObject(g_Autopilot["toast"]) && g_Autopilot["toast"] = toast ? (toast.Destroy(), g_Autopilot["toast"] := 0) : 0), -seconds * 1000)
}

Autopilot_ToastClick(toast, callback, *) {
    global g_Autopilot
    try toast.Destroy()
    g_Autopilot["toast"] := 0
    try callback.Call()
}

; ─── Plain-English compile ─────────────────────────────────────────────────────

Autopilot_Compile(description, offlineOnly, includeTitles, callback) {
    global g_StudyLLM_Endpoint, g_StudyLLM_TextModel, g_StudyLLM_Price, g_StudyLLM_SpentUSD
    budget := 0
    try budget := Study_GetSetting("cost_cap_usd", "2.00") + 0.0
    remaining := budget > 0 ? Max(0, budget - g_StudyLLM_SpentUSD) : 50
    request := Map("description", description, "catalog", Autopilot_Catalog(), "context", Autopilot_Context(includeTitles),
        "compile_mode", offlineOnly ? "offline" : "auto", "endpoint", g_StudyLLM_Endpoint, "model", g_StudyLLM_TextModel,
        "budget_usd", remaining, "prices", g_StudyLLM_Price)
    return Autopilot_Job("compile", request, Autopilot_CompileDone.Bind(callback), 240000)
}

Autopilot_CompileDone(callback, result) {
    global g_StudyLLM_SpentUSD
    usage := result.Get("usage", 0)
    if usage is Map && IsNumber(usage.Get("cost_usd", ""))
        g_StudyLLM_SpentUSD += usage["cost_usd"]  ; shares the Study Assistant session cost cap
    callback.Call(result)
}

Autopilot_Status(section, text) {
    global g_Autopilot
    ui := g_Autopilot["ui"]
    if ui.Has(section . "Status")
        try ui[section . "Status"].Value := text
}
