; Passive collector owned by MacroAutomator's timer/lifecycle. No helper process.
#Include FanBridgeJson.ahk
global g_ExplorerKnowledge := Map("root","","session","","busy",false,"lastError",0)

ExplorerKnowledge_Start(root) {
    if g_ExplorerKnowledge["session"]!=""
        return
    g_ExplorerKnowledge["root"] := root
    g_ExplorerKnowledge["session"] := DllCall("GetCurrentProcessId","UInt") . ":" . A_TickCount
    DirCreate(root . "\.runtime")
    SetTimer(ExplorerKnowledge_Tick,2000)
    OnExit(ExplorerKnowledge_Stop)
}

ExplorerKnowledge_Stop(*) {
    SetTimer(ExplorerKnowledge_Tick,0)
    g_ExplorerKnowledge["session"] := "", g_ExplorerKnowledge["root"] := ""
}

ExplorerKnowledge_Tick(*) {
    s := g_ExplorerKnowledge
    if s["busy"] || s["root"]=""
        return
    ; Do not query Shell while DAA is acting, nor enumerate background folders.
    global g_FanBridgeBusy, g_DeepBridge
    if IsSet(g_FanBridgeBusy) && g_FanBridgeBusy
        return
    if IsSet(g_DeepBridge) && IsObject(g_DeepBridge) && g_DeepBridge.Get("busy",false)
        return
    s["busy"] := true
    try {
        windows := [], foreground := DllCall("GetForegroundWindow","Ptr"), started := A_TickCount
        explorer := foreground && WinGetProcessName(foreground)="explorer.exe"
            && RegExMatch(WinGetClass(foreground),"^(CabinetWClass|ExploreWClass)$")
        if explorer && A_TimeIdlePhysical<60000 {
        shell := ComObject("Shell.Application")
        for item in shell.Windows {
            if A_TickCount-started>150 || windows.Length>=20
                break
            try {
                if item.HWND!=foreground || !RegExMatch(item.FullName,"i)\\explorer\.exe$")
                    continue
                path := item.Document.Folder.Self.Path
                selected := []
                for entry in item.Document.SelectedItems {
                    if selected.Length>=20
                        break
                    selected.Push(entry.Path)
                }
                windows.Push(Map("hwnd",item.HWND,"path",path,"selected",selected,"title",WinGetTitle(item.HWND)))
            }
        }
        }
        data := Map("session",s["session"],"tick",A_TickCount,"idle_ms",A_TimeIdlePhysical,
            "foreground",DllCall("GetForegroundWindow","Ptr"),"windows",windows,"collector_pid",DllCall("GetCurrentProcessId","UInt"),"collector","MacroAutomator timer")
        temp := s["root"] . "\.runtime\explorer-sample.tmp"
        sampleFile := FileOpen(temp,"w","UTF-8")
        sampleFile.Write(FanBridgeJsonEncode(data)), sampleFile.Close()
        FileMove(temp,s["root"] . "\.runtime\explorer-sample.json",true)
    } catch as err {
        ; A failed Shell/locked-file sample is a gap, never guessed attention.
        if !s["lastError"] || A_TickCount-s["lastError"]>60000 {
            s["lastError"] := A_TickCount
            try FileAppend(A_NowUTC . " " . err.Message . "`n",s["root"] . "\.runtime\explorer-observer.log","UTF-8")
        }
    } finally s["busy"] := false
}
