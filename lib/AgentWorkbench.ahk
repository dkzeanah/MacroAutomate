#Include NativeWorkbench.ahk
; Native AHK is the default viewer. The browser view is an optional companion.
AgentWorkbench_Open(view := "canvas",*) {
    global MainGui
    try {
        start := "DeepBridge_Start"
        try %start%()
        owner := IsSet(MainGui) && IsObject(MainGui) ? MainGui.Hwnd : 0
        if hwnd := WinExist("Live Learning Workbench — Native AHK ahk_class AutoHotkeyGUI") {
            PostMessage(0x84F8,view="chains" ? 6 : view="explorer" ? 7 : view="stats" ? 5 : view="discoveries" ? 4 : view="thinking" ? 2 : 1,owner,,hwnd)
            return
        }
        root := FanData_ProjectRoot() . "\fan"
        Run('"' . A_AhkPath . '" /ErrorStdOut=UTF-8 "' . root . '\NativeLearningWorkbench.ahk" ' . owner . ' ' . view,root,"Hide")
    } catch as err
        MsgBox(err.Message,"Native Learning Workbench")
}

AgentWorkbench_OpenWeb(view := "canvas",*) {
    root := FanData_ProjectRoot() . "\fan\DeepSeekBridge", config := Map()
    try {
        start := "DeepBridge_Start"
        try %start%()
        for line in StrSplit(FileRead(root . "\.env","UTF-8"),"`n","`r") {
            split := InStr(line,"=")
            if split>1
                config[Trim(SubStr(line,1,split-1))] := Trim(SubStr(line,split+1))
        }
        token := config.Get("BRIDGE_TOKEN","")
        if !RegExMatch(token,"^[a-zA-Z0-9_-]+$")
            throw Error("Start DeepSeek Bridge services first")
        url := "http://127.0.0.1:" . config.Get("MONITOR_PORT","8766") . "/#access=" . token . "&view=" . view
        SetTimer((*)=>Run(url),-500)
    } catch as err
        MsgBox(err.Message,"Live Learning Workbench")
}

LearningWorkbench_Open(*) => AgentWorkbench_Open("canvas")
