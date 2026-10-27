; Standalone progress window for an explicitly selected offload. Fan is closed
; during the transfer, then reopened with its persisted tracker/session state.
#Requires AutoHotkey v2.0
#SingleInstance Off
#Include ..\lib\FanBridgeJson.ahk
if A_Args.Length != 1
    ExitApp(1)
global jobDir := A_Args[1], jobRequest := FanBridgeJsonDecode(FileRead(jobDir . "\request.json", "UTF-8"))
global workerPid := 0, finished := false
global jobGui := Gui("+Resize", "Fan storage transfer")
jobGui.SetFont("s10", "Segoe UI")
jobGui.Add("Text", "x16 y16 w660 h42", jobRequest["mode"] = "images" ? "Importing captured photos into SQLite"
    : jobRequest["mode"] = "consolidate" ? "Consolidating the historical archive: " . jobRequest["destination"]
    : jobRequest["scope"] = "snapshots" ? "Exporting database photos to " . jobRequest["destination"]
    : "Archiving and resetting databases: " . jobRequest["destination"])
global jobStatus := jobGui.Add("Edit", "x16 y70 w660 h190 ReadOnly Multi +VScroll", "Waiting for Fan to close its databases…")
global cancelBtn := jobGui.Add("Button", "x16 y280 w140 h30", "Cancel transfer")
cancelBtn.OnEvent("Click", (*) => CancelTransfer())
global restartBtn := jobGui.Add("Button", "x166 y280 w150 h30 Disabled", "Reopen Fan")
restartBtn.OnEvent("Click", (*) => ReopenFan())
jobGui.OnEvent("Close", (*) => finished ? ExitApp(0) : CancelTransfer())
jobGui.Show("w692 h330")
python := jobRequest["project"] . "\fan\DeepSeekBridge\.venv\Scripts\python.exe"
Run('"' . python . '" -m fan.data_maintenance.cli "' . jobDir . '\request.json"', jobRequest["project"], "Hide", &workerPid)
SetTimer(CheckTransfer, 500)

CancelTransfer() {
    if !finished {
        if !FileExist(jobDir . "\cancel")
            FileAppend("cancel", jobDir . "\cancel", "UTF-8-RAW")
        cancelBtn.Enabled := false
        jobStatus.Value := "Cancellation requested. Waiting for a safe checkpoint…"
    }
}

CheckTransfer() {
    global finished
    state := Map()
    try state := FanBridgeJsonDecode(FileRead(jobDir . "\status.json", "UTF-8"))
    phase := state.Get("phase", "")
    jobStatus.Value := state.Get("message", "Waiting for the transfer worker…")
    if phase = "committing" || phase = "cleanup" || phase = "resetting" || phase = "verify" || phase = "verified"
        cancelBtn.Enabled := false
    if RegExMatch(phase, "^(complete|error|cancelled)$") || (!ProcessExist(workerPid) && !(state.Get("worker_pid", 0) && ProcessExist(state["worker_pid"]))) {
        SetTimer(CheckTransfer, 0)
        finished := true
        cancelBtn.Enabled := false
        restartBtn.Enabled := true
        if !RegExMatch(phase, "^(complete|error|cancelled)$")
            jobStatus.Value := "Worker stopped unexpectedly. Verified copies and the transfer journal are retained. Reopen Fan to inspect job history."
        ; Success or cancellation restores normal operation automatically.
        if RegExMatch(phase, "^(complete|error|cancelled)$")
            SetTimer(ReopenFan, -1500)
    }
}

ReopenFan(*) {
    python := jobRequest["project"] . "\fan\DeepSeekBridge\.venv\Scripts\python.exe"
    code := RunWait('"' . python . '" -m fan.data_maintenance.cli --recover "' . jobDir . '\request.json"', jobRequest["project"], "Hide")
    if code != 0 {
        jobStatus.Value := "Interrupted cutover needs recovery; original data and the journal are retained. Reconnect the destination drive and retry Reopen Fan."
        return
    }
    Run('"' . A_AhkPath . '" /ErrorStdOut=UTF-8 "' . jobRequest["project"] . '\fan\MacroAutomator.ahk" /settings', jobRequest["project"])
    ExitApp(0)
}
