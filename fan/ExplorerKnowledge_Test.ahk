#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
#Include ..\lib\ExplorerKnowledge.ahk
global g_FanBridgeBusy := false, g_DeepBridge := Map("busy",false), failures := 0
Check(ok,label) {
    global failures
    failures += !ok
    FileAppend((ok ? "PASS " : "FAIL ") . label . "`n","*")
}
root := A_Temp . "\fan-explorer-test-" . DllCall("GetCurrentProcessId") . "-" . A_TickCount
try {
    ExplorerKnowledge_Start(root), session := g_ExplorerKnowledge["session"]
    ExplorerKnowledge_Start(root . "\.")
    Check(g_ExplorerKnowledge["session"]=session && g_ExplorerKnowledge["root"]=root,"two startup paths retain one collector session")
    g_FanBridgeBusy := true, ExplorerKnowledge_Tick()
    Check(!FileExist(root . "\.runtime\explorer-sample.json"),"collector yields while the native agent is active")
    g_FanBridgeBusy := false, g_DeepBridge["busy"] := true, ExplorerKnowledge_Tick()
    Check(!FileExist(root . "\.runtime\explorer-sample.json"),"collector yields during a Bridge task")
    g_DeepBridge["busy"] := false, ExplorerKnowledge_Tick()
    sample := FanBridgeJsonDecode(FileRead(root . "\.runtime\explorer-sample.json","UTF-8"))
    Check(sample["collector_pid"]=DllCall("GetCurrentProcessId") && sample["collector"]="MacroAutomator timer","observation is produced in the calling AHK process")
    ExplorerKnowledge_Stop()
    Check(g_ExplorerKnowledge["session"]="" && g_ExplorerKnowledge["root"]="","collector shuts down with its host lifecycle")
} catch as err
    Check(false,err.Message . " · " . err.File . ":" . err.Line)
finally ExplorerKnowledge_Stop()
ExitApp(failures)
