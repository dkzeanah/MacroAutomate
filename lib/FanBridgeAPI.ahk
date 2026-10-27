#Include TaskbarKnowledge.ahk
#Include WindowKnowledge.ahk
#Include ExplorerKnowledge.ahk
; Fan's live internal API. It uses the same stores, action specs and engine as
; the manual composer. No dynamic Eval or arbitrary function name dispatch.
global g_FanBridgeRoot := A_ScriptDir . "\DeepSeekBridge"
global g_FanBridgeBusy := false, g_FanBridgeTask := "", g_FanBridgeRun := "", g_FanBridgeDeadline := 0
global g_FanBridgeError := "", g_FanLibraryIndex := []
global g_FanBridgeTool := ""
global g_FanBridgeChain := ""
global g_FanBridgeTarget := Map()

FanAPI_PrepareWindow(hwnd) {
    global g_FanBridgeTarget
    expected := g_FanBridgeTarget.Get("hwnd",0)=hwnd ? g_FanBridgeTarget : Map()
    target := BoundWindow_Prepare(hwnd,expected,g_FanBridgeTask)
    g_FanBridgeTarget := target
    FanAPI_Observe("Window","ActivateAssignedWindow","end",Map("target_window",target))
    return target
}

FanAPI_Start(root := "") {
    global g_FanBridgeRoot, g_FanVisionObserver
    if root != ""
        g_FanBridgeRoot := root
    SetTimer(FanAPI_Poll, 200)
    g_FanVisionObserver := FanAPI_Observe
    ExplorerKnowledge_Start(g_FanBridgeRoot)
}

FanAPI_Observe(family,method,phase := "start",detail := 0) {
    if !g_FanBridgeBusy
        return
    data := TrackJsonEncode(Map("task_id",g_FanBridgeTask,"tool",g_FanBridgeTool,"chain_step",g_FanBridgeChain,
        "family",family,"method",method,"phase",phase,"detail",IsObject(detail) ? detail : Map()))
    if IsObject(detail) && detail.Get("interaction",false) {
        waited := false, pauseDeadline := g_FanBridgeDeadline ? g_FanBridgeDeadline : A_TickCount+120000
        loop {
            result := FanAPI_HTTP("POST","/observations",data)
            if !TrackJsonDecode(result).Get("paused",false) {
                if waited
                    throw Error("Resumed after perception; inspect the target again before native input")
                return result
            }
            if A_TickCount>pauseDeadline
                throw Error("Automation time budget reached while paused")
            waited := true, Sleep(250)
        }
    }
    try FanAPI_HTTP("POST","/observations",data)
}

FanAPI_HTTP(method, path, body := "", contentType := "application/json; charset=utf-8") {
    config := Map()
    for line in StrSplit(FileRead(g_FanBridgeRoot . "\.env", "UTF-8"), "`n", "`r") {
        at := InStr(line, "=")
        if at > 1
            config[Trim(SubStr(line, 1, at-1))] := Trim(SubStr(line, at+1))
    }
    request := ComObject("WinHttp.WinHttpRequest.5.1")
    request.SetProxy(1)
    request.SetTimeouts(500, 500, 1000, 2000)
    request.Open(method, "http://127.0.0.1:" . config.Get("BRIDGE_PORT", "8765") . path, false)
    request.SetRequestHeader("X-Bridge-Token", config.Get("BRIDGE_TOKEN", ""))
    request.SetRequestHeader("Content-Type", contentType)
    request.Send(body)
    if request.Status < 200 || request.Status >= 300
        throw Error("Fan API HTTP " . request.Status)
    return request.ResponseText
}

FanAPI_Encode(value) {
    bytes := Buffer(StrPut(value, "UTF-8"))
    size := StrPut(value, bytes, "UTF-8")-1, encoded := ""
    loop size {
        n := NumGet(bytes, A_Index-1, "uchar")
        encoded .= (n>=65 && n<=90 || n>=97 && n<=122 || n>=48 && n<=57 || n=45 || n=46 || n=95 || n=126) ? Chr(n) : Format("%{:02X}", n)
    }
    return encoded
}

FanAPI_Decode(value) {
    bytes := Buffer(StrLen(value)+1), size := 0, at := 1
    while at <= StrLen(value) {
        if SubStr(value, at, 1) = "%" {
            NumPut("uchar", Integer("0x" . SubStr(value, at+1, 2)), bytes, size++)
            at += 3
        } else {
            NumPut("uchar", Ord(SubStr(value, at, 1)), bytes, size++)
            at++
        }
    }
    return StrGet(bytes, size, "UTF-8")
}

FanAPI_Poll() {
    global g_FanBridgeBusy, g_FanBridgeTask, g_FanBridgeRun, g_FanBridgeError, g_FanBridgeTool
    global g_FanBridgeChain
    if g_FanBridgeBusy || !FileExist(g_FanBridgeRoot . "\.env")
        return
    g_FanBridgeBusy := true
    try {
        wire := FanAPI_HTTP("GET", "/fan/next")
        if wire = "NONE"
            return
        lines := StrSplit(StrReplace(wire, "`r", ""), "`n")
        if lines.Length < 3
            throw Error("Malformed Fan request")
        id := lines[1], name := lines[2], args := TrackJsonDecode(FanAPI_Decode(lines[3]))
        FanAPI_Progress(name,"received")
        g_FanBridgeTask := args.Get("_task_id", "")
        g_FanBridgeTool := name
        g_FanBridgeRun := args.Get("_run_id", "")
        g_FanBridgeChain := args.Get("_chain_step", "")
        g_FanBridgeTarget := args.Get("_bound_window",Map())
        result := Map("ok", false)
        DeepActivity_Set(true, "API · " . name, 120000)
        try result := FanAPI_Dispatch(name, args)
        catch as apiError
            result := Map("ok", false, "error", apiError.Message, "tool", name,"location",apiError.File . ":" . apiError.Line,"operation",apiError.What)
        finally
            DeepActivity_Set(true, "API finished · " . name, 1200)
        FanAPI_Progress(name,"dispatch complete")
        body := "id=" . FanAPI_Encode(id) . "&result=" . FanAPI_Encode(StudyConsole_Redact(TrackJsonEncode(result)))
        FanAPI_HTTP("POST", "/fan/result", body, "application/x-www-form-urlencoded")
        FanAPI_Progress(name,"response posted")
        g_FanBridgeError := ""
    } catch as rpcError {
        g_FanBridgeError := rpcError.Message
        FanAPI_Progress("rpc","error: " . rpcError.Message)
    } finally {
        g_FanBridgeTask := "", g_FanBridgeRun := "", g_FanBridgeBusy := false, g_FanBridgeTool := ""
    }
}

FanAPI_Progress(name,phase) {
    try {
        path := g_FanBridgeRoot . "\.runtime\fan-native-status.json"
        file := FileOpen(path,"w","UTF-8")
        file.Write(TrackJsonEncode(Map("tool",name,"phase",SubStr(phase,1,300),"at",A_Now,"pid",DllCall("GetCurrentProcessId","UInt"))))
        file.Close()
    }
}

FanAPI_Dispatch(name, args) {
    switch name {
        case "fan_window_prepare":
            hwnd := args.Get("hwnd",g_FanBridgeTarget.Get("hwnd",0))
            target := FanAPI_PrepareWindow(hwnd)
            return Map("ok",true,"target_window",target,"frame",target)
        case "fan_window_probe": return FanWindow_Probe(args)
        case "fan_window_survey": return FanWindow_Survey(args)
        case "fan_window_shortcut": return FanWindow_Shortcut(args)
        case "fan_window_menu": return FanWindow_Menu(args)
        case "fan_window_probe_item": return FanWindow_ProbeItem(args)
        case "fan_desktop_preview": return FanWindow_DesktopPreview()
        case "fan_capabilities": return FanAPI_Capabilities()
        case "fan_taskbar_learn": return TaskbarKnowledge_Learn()
        case "fan_taskbar_list": return TaskbarKnowledge_List(args)
        case "fan_taskbar_open": return TaskbarKnowledge_Open(args)
        case "fan_learning_lesson": return LearningLab_Present(args)
        case "fan_learning_compile": return LearningProcedure_Compile(args)
        case "fan_learning_rehearse": return LearningProcedure_Run(args)
        case "fan_code_index": return FanHarness_Present(args)
        case "fan_learning_insights": return FanAPI_LearningInsights(args)
        case "fan_discovered_targets": return FanAPI_DiscoveredTargets(args)
        case "fan_window_inspect", "fan_ocr", "fan_pattern_list", "fan_pattern_search", "fan_pattern_capture", "fan_page_learn", "fan_page_probe", "fan_page_resolve", "fan_page_image": return FanVision_Dispatch(name, args)
        case "fan_workflow_list", "fan_workflow_get", "fan_workflow_save", "fan_workflow_preview", "fan_workflow_run": return FanAPI_Workflow(name, args)
        case "fan_input_settings_get", "fan_input_settings_set": return FanAPI_InputSettings(name, args)
        case "fan_library_search", "fan_library_read": return FanAPI_Library(name, args)
        default: throw Error("Unknown Fan API tool: " . name)
    }
}

FanAPI_LearningInsights(args) {
    path := FanAPI_Repository() . "\data\learning_insights\latest.json"
    if !FanFileExist(path)
        return Map("ok", false, "error", "Run Settings → Consolidate insights to create the first learning report.")
    report := TrackJsonDecode(FanFileRead(path, "UTF-8"))
    query := StrLower(args.Get("query", "")), limit := args.Get("limit", 20), matched := []
    for , finding in report.Get("findings", []) {
        if query = "" || InStr(StrLower(TrackJsonEncode(finding)), query)
            matched.Push(finding)
        if matched.Length >= limit
            break
    }
    report["findings"] := matched
    return Map("ok", true, "report", report, "source", path,
        "usage", "Measurements are observed evidence; recommended changes remain candidates. Recheck dates, scope and live UI before applying them.")
}

FanAPI_DiscoveredTargets(args) {
    db := TrackDB()
    if !db || !db.Scalar("SELECT COUNT(*) FROM sqlite_master WHERE name='discovered_target'")
        return Map("ok", true, "targets", [])
    limit := Max(1, Min(200, Integer(args.Get("limit", 30))))
    query := "%" . args.Get("query", "") . "%"
    rows := db.Query("SELECT * FROM discovered_target WHERE title LIKE ? OR name LIKE ? OR topic LIKE ? ORDER BY last_ts DESC LIMIT ?", query, query, query, limit)
    return Map("ok", true, "targets", rows, "evidence", "Observed accessibility targets; recheck the live window and locator before acting")
}

FanAPI_Repository() {
    SplitPath(A_LineFile,, &libDirectory)
    return RegExReplace(libDirectory, "\\lib$")
}

FanAPI_Capabilities() {
    actions := []
    for , name in GetWorkflowActionNames() {
        spec := GetWorkflowActionSpec(name)
        if name = "OCR Region" || name = "OCR Click" || name = "OCR Wait" {
            spec["targetHint"] := "x1,y1,x2,y2 (physical screen rectangle corners)"
            spec["help"] := "Raw rectangles use opposite corners, not width/height. " . spec["help"]
        }
        actions.Push(Map("name", name, "spec", spec))
    }
    return Map("ok", true, "api_version", "2", "app", "Fan Macro Automator", "tools", FanVision_Capabilities(),
        "workflow_actions", actions, "step_schema", Map("action", "exact workflow action name", "target", "string from action spec", "param", "string from action spec", "enabled", "boolean", "failsafe", "map", "qualWindow", "string", "qualPattern", "saved pattern name"),
        "script_sdk", FanAPI_Repository() . "\lib\FanBridgeClient.ahk",
        "taskbar_api", "fan_taskbar_learn() passively stores named taskbar icons, screenshots and binary FindText patterns; fan_taskbar_list(query=...) reads them; fan_taskbar_open(name=...) re-resolves the live icon before clicking and verifies the foreground executable",
        "learning_insights_api", "fan_learning_insights(query=..., limit=20); Settings → Consolidate insights builds the current evidence report",
        "discovery_api", "fan_discovered_targets(query=..., limit=30) reads passively captured semantic targets and Claude/ChatGPT/development topics",
        "page_learner_api", "fan_page_learn(hwnd=0) captures any visible Chrome viewport; fan_page_get searches its saved groups/elements; fan_page_resolve verifies fresh targets; fan_page_image renders stored crops",
        "script_example", "#Requires AutoHotkey v2.0`n#Include " . FanAPI_Repository() . "\lib\FanBridgeClient.ahk`ninfo := FanBridge.Inspect(0, false)`nFileAppend(FanBridgeJsonEncode(info), " . Chr(34) . "*" . Chr(34) . ")",
        "coordinate_system", "physical screen pixels; negative multi-monitor coordinates allowed; OCR/Acc boxes already absolute",
        "usage", "Use library search/read for real callable library signatures. Include FanBridgeClient.ahk in saved scripts to call the running app. Do not include the full MacroAutomator entry point.",
        "settings", FanAPI_InputSettings("fan_input_settings_get", Map()), "tooltips_disabled", true)
}

FanAPI_Workflow(name, args) {
    global g_Sequences, g_LastWorkflowSaveError
    if name = "fan_workflow_list" {
        items := [], query := StrLower(args.Get("query", ""))
        for savedName, item in g_Sequences
            if query = "" || InStr(StrLower(savedName), query)
                items.Push(Map("name", savedName, "step_count", item["steps"].Length, "speed", item.Get("speed", 1.0)))
        return Map("ok", true, "workflows", items)
    }
    savedName := Trim(args.Get("name", ""))
    if savedName = "" || StrLen(savedName)>120
        throw Error("A workflow name of 1..120 characters is required")
    if name = "fan_workflow_save" {
        if g_Sequences.Has(savedName) && !args.Get("overwrite", false)
            throw Error("Workflow already exists; read it and use overwrite=true to edit")
        steps := args.Get("steps", 0)
        if !(steps is Array) || !steps.Length || steps.Length > 300
            throw Error("Workflow requires 1..300 structured steps")
        accepted := [], depth := 0, allowed := Map()
        for , action in GetWorkflowActionNames()
            allowed[action] := true
        for index, step in steps {
            if !(step is Map) || !allowed.Has(step.Get("action", ""))
                throw Error("Unknown workflow action at step " . index)
            action := step["action"], spec := GetWorkflowActionSpec(action)
            target := String(step.Get("target", "")), param := String(step.Get("param", ""))
            if spec["targetRequired"] && Trim(target) = "" || spec["paramRequired"] && Trim(param) = ""
                throw Error("Missing required target/param at step " . index . "; inspect the action spec")
            if action = "Loop Start"
                depth++
            if action = "Loop End" && --depth < 0
                throw Error("Loop End without Loop Start at step " . index)
            accepted.Push(Map("action", action, "target", target, "param", param,
                "enabled", step.Get("enabled", true), "failsafe", NormalizeStepFailsafe(step.Get("failsafe", Map())),
                "qualPattern", String(step.Get("qualPattern", "")), "qualWindow", String(step.Get("qualWindow", "")), "notificationMuted", true))
        }
        if depth != 0
            throw Error("Workflow contains unclosed loops")
        existed := g_Sequences.Has(savedName), prior := existed ? g_Sequences[savedName] : 0
        g_Sequences[savedName] := Map("steps", accepted, "speed", existed ? prior.Get("speed", 1.0) : 1.0,
            "hotkey", existed ? prior.Get("hotkey", "") : "", "hotstring", existed ? prior.Get("hotstring", "") : "")
        if !SaveSequences() {
            if existed
                g_Sequences[savedName] := prior
            else
                g_Sequences.Delete(savedName)
            throw Error("Workflow persistence failed: " . g_LastWorkflowSaveError)
        }
        try RefreshSeqLV()
        return Map("ok", true, "name", savedName, "steps", accepted, "description", args.Get("description", ""),
            "usage", "fan_workflow_run(name=" . savedName . ") executes the same engine as the manual composer")
    }
    if !g_Sequences.Has(savedName)
        throw Error("Workflow not found: " . savedName)
    workflow := g_Sequences[savedName]
    if name = "fan_workflow_get" || name = "fan_workflow_preview"
        return Map("ok", true, "name", savedName, "workflow", workflow, "preview", FanAPI_Preview(workflow["steps"]))
    return FanAPI_RunWorkflow(savedName, workflow, args.Get("timeout_seconds", 120))
}

FanAPI_Preview(steps) {
    text := ""
    for index, step in steps
        text .= index . ". " . step["action"] . " | " . step.Get("target", "") . " | " . step.Get("param", "") . (step.Get("enabled", true) ? "" : " [disabled]") . "`n"
    return Trim(text, "`n")
}

FanAPI_RunWorkflow(name, workflow, timeoutSeconds) {
    global g_AbortSequence, g_FanBridgeDeadline, g_DebugMode, g_StepThroughMode, g_IsPaused
    if g_StudyMacroRunning || g_StudyToolBusy || g_WorkflowRunning
        throw Error("Another native input workflow is running; retry when it finishes")
    if timeoutSeconds < 1 || timeoutSeconds > 300
        throw Error("Workflow timeout must be 1..300 seconds")
    oldDebug := g_DebugMode, oldStep := g_StepThroughMode, oldPause := g_IsPaused
    g_DebugMode := false, g_StepThroughMode := false, g_IsPaused := false
    g_FanBridgeDeadline := A_TickCount + timeoutSeconds*1000
    SetTimer(FanAPI_CheckRun, 250)
    try {
        result := ExecuteSequenceVerified(workflow["steps"], workflow.Get("speed", 1.0), Map("interactive", false))
        result["name"] := name
        return result
    } finally {
        SetTimer(FanAPI_CheckRun, 0)
        g_FanBridgeDeadline := 0
        g_DebugMode := oldDebug, g_StepThroughMode := oldStep, g_IsPaused := oldPause
    }
}

FanAPI_CheckRun() {
    global g_AbortSequence, g_StudyMacroCancelled
    stop := g_FanBridgeDeadline && A_TickCount > g_FanBridgeDeadline
    if !stop && g_FanBridgeTask != "" {
        try stop := TrackJsonDecode(FanAPI_HTTP("GET", "/tasks/" . g_FanBridgeTask))["status"] = "cancelled"
        catch
            stop := true
    }
    if !stop && g_FanBridgeRun != "" {
        try stop := TrackJsonDecode(FanAPI_HTTP("POST", "/tools/ahk_script_status", TrackJsonEncode(Map("run_id", g_FanBridgeRun))))["status"] != "running"
        catch
            stop := true
    }
    if stop
        g_AbortSequence := true, g_StudyMacroCancelled := true
}

FanAPI_InputSettings(name, args) {
    global g_StudyHuman, g_Settings
    limits := StudyHuman_Limits()
    if name = "fan_input_settings_set" {
        settings := args.Get("settings", Map()), changes := Map(), workflowChanges := Map()
        for key, value in settings {
            if SubStr(key, 1, 9) = "workflow." {
                settingName := SubStr(key, 10)
                if !g_Settings.Has(settingName)
                    throw Error("Unknown workflow setting: " . settingName)
                if settingName = "DateFormat" {
                    if Type(value) != "String" || StrLen(value)>100 || value=""
                        throw Error("DateFormat must be a nonempty format string up to 100 characters")
                } else {
                    if !IsNumber(value) || value < (InStr(settingName,"Offset") ? -10000 : 0) || value > 60000
                        throw Error("Invalid numeric workflow setting: " . settingName)
                    if settingName = "FindTextTolerance" && value>1
                        throw Error("FindTextTolerance must be 0..1")
                    if RegExMatch(settingName,"^(ShowActionTooltips|AutoCapturePattern|FailsafeCheckCloseButton|DefinitionModeAutoPattern|SpoolMasterEnabled)$") && value != 0 && value != 1
                        throw Error("Boolean workflow setting must be 0/1: " . settingName)
                }
                workflowChanges[settingName] := value
                continue
            }
            if !g_StudyHuman.Has(key) || !limits.Has(key) || !IsNumber(value) || value < limits[key][1] || value > limits[key][2]
                throw Error("Invalid input setting " . key . "; use the returned limits")
            changes[key] := Number(value)
        }
        for key, value in changes {
            Study_SetSetting("human_" . key, String(value))
            g_StudyHuman[key] := value
        }
        prior := g_Settings.Clone()
        try {
            for key, value in workflowChanges
                g_Settings[key] := value
            if workflowChanges.Count
                SaveSettings()
        } catch {
            g_Settings := prior
            throw Error("Workflow settings could not be saved; prior in-memory settings were restored")
        }
    }
    return Map("ok", true, "human_input", g_StudyHuman.Clone(), "limits", limits, "workflow_settings", g_Settings.Clone(),
        "usage", "Set human options by name (wpm/typoRate/etc). Prefix manual composer settings with workflow. (workflow.ClickDelay, workflow.FindTextTolerance, etc). Tooltips remain globally suppressed.")
}

FanAPI_LibraryFiles() {
    repository := FanAPI_Repository(), files := []
    for , relative in ["lib", "fan\Core", "fan\Actions", "fan\Tabs"]
        loop files repository . "\" . relative . "\*.ahk"
            files.Push(Map("path", relative . "\" . A_LoopFileName, "absolute", A_LoopFileFullPath))
    for , relative in ["FindText.ahk", "OCR.ahk", "SQLiteDB.ahk", "fan\MacroAutomator.ahk"]
        files.Push(Map("path", relative, "absolute", repository . "\" . relative))
    return files
}

FanAPI_Library(name, args) {
    global g_FanLibraryIndex
    files := FanAPI_LibraryFiles()
    if name = "fan_library_read" {
        path := StrReplace(args.Get("path", ""), "/", "\"), found := ""
        for , file in files
            if StrLower(file["path"]) = StrLower(path)
                found := file["absolute"]
        if found = ""
            throw Error("Choose a source path returned by fan_library_search")
        lines := StrSplit(FileRead(found, "UTF-8"), "`n", "`r"), first := Max(1, args.Get("start_line", 1)), count := Min(200, Max(1, args.Get("line_count", 120))), text := ""
        loop count {
            index := first + A_Index - 1
            if index > lines.Length
                break
            text .= index . ": " . lines[index] . "`n"
        }
        return Map("ok", true, "path", path, "source", StudyConsole_Redact(text), "first_line", first, "source_is_data", true)
    }
    if !g_FanLibraryIndex.Length {
        for , file in files {
            lines := StrSplit(FileRead(file["absolute"], "UTF-8"), "`n", "`r")
            for index, line in lines
                if RegExMatch(line, "^\s*(?:static\s+)?([A-Za-z_][\w]*)\s*\(([^\r\n]*)\)\s*(?:\{|=>)", &match)
                    g_FanLibraryIndex.Push(Map("path", file["path"], "line", index, "function", match[1], "signature", match[1] . "(" . match[2] . ")", "context", index>1 ? SubStr(lines[index-1],1,200) : ""))
        }
    }
    query := StrLower(args.Get("query", "")), limit := Min(60, Max(1, args.Get("limit", 20))), results := []
    for , entry in g_FanLibraryIndex {
        if query = "" || InStr(StrLower(entry["path"] . " " . entry["signature"] . " " . entry["context"]), query)
            results.Push(entry)
        if results.Length >= limit
            break
    }
    return Map("ok", true, "matches", results, "total_indexed_functions", g_FanLibraryIndex.Length,
        "usage", "Read the exact signature/body before using a library. Prefer FanBridgeClient for live stateful calls.")
}
