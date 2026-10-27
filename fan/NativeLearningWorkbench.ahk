#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, StdOut
#Include Core\_Gdip.ahk
#Include ..\lib\NativeWorkbench.ahk
#Include ..\lib\SecondaryWindows.ahk
; A separate native viewer keeps rendering/network polling out of the automator.
global MainGui := 0
DllCall("SetThreadDpiAwarenessContext","Ptr",-4,"Ptr")
SetWorkingDir(A_ScriptDir . "\..")
g_NativeWB["owner"] := A_Args.Length ? Integer(A_Args[1]) : 0
if !g_NativeWB["owner"] {
    previousHidden := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    owners := WinGetList("Macro Automator v9 - Vision Scout + Usage Predictor ahk_class AutoHotkeyGUI")
    if owners.Length=1
        g_NativeWB["owner"] := owners[1]
    DetectHiddenWindows(previousHidden)
}
if A_Args.Length>=3 && RegExMatch(A_Args[3],"^[a-f0-9]{32}$")
    g_NativeWB["initialTask"] := A_Args[3]
OnMessage(0x84F8,NativeViewer_Message)
SecondaryWindows_Start()
NativeWorkbench_Open(A_Args.Length>=2 ? A_Args[2] : "canvas")
if A_Args.Length>=4 && A_Args[4]="scripts"
    g_NativeWB["ui"]["category"].Choose(2)
if A_Args.Length>=5 && RegExMatch(A_Args[5],"^[a-f0-9]{24}$")
    g_NativeWB["initialWindow"] := A_Args[5]

NativeViewer_Message(view,owner,*) {
    if owner
        g_NativeWB["owner"] := owner
    NativeWorkbench_Open(view=6 ? "chains" : view=7 ? "explorer" : view=5 ? "stats" : view=4 ? "discoveries" : view=2 ? "thinking" : "canvas")
}

FanData_ProjectRoot() => A_ScriptDir . "\.."
LearningValidation_Monitor() {
    primary := MonitorGetPrimary()
    loop MonitorGetCount()
        if A_Index!=primary
            return A_Index
    return 0
}
FanData_Config() {
    file := A_ScriptDir . "\DeepSeekBridge\.runtime\native-window-positions.ini", positions := Map()
    if FileExist(file) {
        for section in StrSplit(IniRead(file),"`n") {
            x := IniRead(file,section,"x",""), y := IniRead(file,section,"y","")
            if IsNumber(x) && IsNumber(y)
                positions[section] := Map("x",Integer(x),"y",Integer(y))
        }
    }
    return Map("secondary_positions",positions)
}
FanData_SaveConfig(config) {
    file := A_ScriptDir . "\DeepSeekBridge\.runtime\native-window-positions.ini"
    for title,position in config.Get("secondary_positions",Map()) {
        IniWrite(position["x"],file,title,"x")
        IniWrite(position["y"],file,title,"y")
    }
}
AgentWorkbench_OpenWeb(view := "canvas") {
    config := NativeWB_Config()
    Run("http://127.0.0.1:" . config.Get("MONITOR_PORT","8766") . "/#access=" . config.Get("BRIDGE_TOKEN","") . "&view=" . view)
}
