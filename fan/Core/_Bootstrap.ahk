; Entry lifecycle: bootstrap. Included by MacroAutomator.ahk.
global APP_ROOT := FileExist(A_ScriptDir . "\..\lib\TrackSQLite.ahk") ? A_ScriptDir . "\.." : A_ScriptDir
; Fail visibly in the logged launcher instead of stranding startup behind an
; unhandled initialization dialog before the normal error handler is installed.
OnError(FanBoot_Error)
FanBoot_Error(err,mode) {
    message := "STARTUP ERROR: " . err.Message . " · " . err.File . ":" . err.Line . "`n"
    try FileAppend(message,"*")
    try FileAppend(message,A_ScriptDir . "\DeepSeekBridge\.runtime\boot-error.log","UTF-8")
    ExitApp(2)
}
global g_FanSeedPath := A_Args.Length >= 2 && A_Args[1] = "--seed-db" ? A_Args[2] : ""
global g_TrackTooltipsDisabled := true
global g_FindTextTooltipHandler := TrackToolTip
OnMessage(0x4E, Track_TooltipNotify)
OnMessage(0x84F7,FanNativeWorkbench_Message)

FanNativeWorkbench_Message(action,identity,*) {
    global MainGui, TabCtrl
    ; Viewer IPC opens native panels only; it cannot execute desktop input.
    if action=1 {
        TabCtrl.Choose(20), MainGui.Show(), DeepBridge_Render()
    } else if action=2
        SetTimer(LearningLab_Open,-1)
    else if action=3 && identity>0
        SetTimer((*)=>LearningLab_Present(Map("claim_id",identity)),-1)
}

SetWorkingDir(APP_ROOT)  ; same working directory the original used
; All capture and monitor geometry uses physical pixels on mixed-DPI displays.
DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
CoordMode("Mouse", "Screen") ; Mouse coordinates relative to screen
CoordMode("Pixel", "Screen") ; Pixel coordinates relative to screen
CoordMode("ToolTip", "Screen") ; Tooltip positioning relative to screen

