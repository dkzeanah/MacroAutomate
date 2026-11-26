; Shared asynchronous Python transport for GUI work. Engines stay in Python.
global g_WorkspaceJobs := Map()

FanPython_Executable() {
    root := FanData_ProjectRoot()
    candidates := [root . "\fan\DeepSeekBridge\.venv\Scripts\python.exe"]
    for hive in ["HKCU", "HKLM"] {
        try {
            Loop Reg, hive . "\Software\Python\PythonCore", "K"
                try candidates.Push(RTrim(RegRead(hive . "\Software\Python\PythonCore\" . A_LoopRegName . "\InstallPath"),"\") . "\python.exe")
        }
    }
    for path in candidates
        if FileExist(path)
            return path
    throw Error("No installed Python found. Run Fan's normal launcher to initialize its Python environment.")
}

WorkspaceJobs_Start(kind, args, completed, progress := 0, timeoutMs := 3600000) {
    static registered := false
    if !registered {
        OnExit(WorkspaceJobs_OnExit)
        registered := true
    }
    id := DllCall("GetCurrentProcessId","UInt") . "-" . A_TickCount . "-" . Random(1000,9999)
    directory := A_Temp . "\FanWorkspaceJobs\" . id
    DirCreate(directory)
    request := Map("kind",kind,"args",args.Clone(),"result",directory . "\result.json",
        "progress",directory . "\progress.json","cancel",directory . "\cancel")
    ; Media previews outlive this job and remain usable by existing exports.
    if kind = "media_local"
        request["args"]["work_dir"] := Media_OutDir() . "\analysis-" . id
    Track_WriteFile(directory . "\request.json",TrackJsonEncode(request))
    if kind = "media_semantic" {
        executable := A_IsCompiled ? A_ProgramFiles . "\AutoHotkey\v2\AutoHotkey64.exe" : A_AhkPath
        worker := FanData_ProjectRoot() . "\fan\MediaAnalysisWorker.ahk"
    } else {
        executable := FanPython_Executable(), worker := FanData_ProjectRoot() . "\fan\bridge\workspace_worker.py"
    }
    Run('"' . executable . '" "' . worker . '" "' . directory . '\request.json"',FanData_ProjectRoot(),"Hide",&pid)
    g_WorkspaceJobs[id] := Map("request",request,"pid",pid,"started",A_TickCount,"timeout",timeoutMs,
        "completed",completed,"progress",progress,"cancelled",false)
    SetTimer(WorkspaceJobs_Poll,250)
    return id
}

WorkspaceJobs_Cancel(id) {
    if !g_WorkspaceJobs.Has(id)
        return
    job := g_WorkspaceJobs[id]
    job["cancelled"] := true
    Track_WriteFile(job["request"]["cancel"],"cancel")
}

WorkspaceJobs_Poll() {
    finished := []
    for id, job in g_WorkspaceJobs {
        request := job["request"]
        if FileExist(request["result"]) {
            try result := TrackJsonDecode(FileRead(request["result"],"UTF-8"))
            catch as parseError
                result := Map("ok",false,"error",parseError.Message)
            if job["cancelled"] {
                result["ok"] := false, result["cancelled"] := true, result["error"] := "Cancelled"
            }
            finished.Push([id,result])
        } else if !ProcessExist(job["pid"]) || A_TickCount-job["started"] > job["timeout"] {
            WorkspaceJobs_Cancel(id)
            finished.Push([id,Map("ok",false,"error","Background worker ended or exceeded its time limit")])
        } else if IsObject(job["progress"]) && FileExist(request["progress"]) {
            try job["progress"].Call(TrackJsonDecode(FileRead(request["progress"],"UTF-8")))
        }
    }
    for item in finished {
        job := g_WorkspaceJobs[item[1]], g_WorkspaceJobs.Delete(item[1])
        try job["completed"].Call(item[2])
        catch as callbackError
            TrackLogError("Workspace job callback",callbackError)
    }
    if !g_WorkspaceJobs.Count
        SetTimer(WorkspaceJobs_Poll,0)
}

WorkspaceJobs_OnExit(*) {
    for id, job in g_WorkspaceJobs
        WorkspaceJobs_Cancel(id)
}
