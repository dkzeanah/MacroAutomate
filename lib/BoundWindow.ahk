; Explicit, process-pinned window routing shared by the app, worker and SDK.
global g_BoundWindows := Map(), g_BoundTaskWindows := Map()
BoundWindow_Prepare(hwnd, expected := 0, task := "") {
    if !hwnd || !DllCall("IsWindow","Ptr",hwnd)
        throw TargetError("Assigned window closed. Select a new target; no foreground fallback was used.")
    pid := WinGetPID(hwnd), exe := WinGetProcessName(hwnd), cls := WinGetClass(hwnd)
    key := task . ":" . hwnd
    pin := IsObject(expected) && expected.Get("pid",0) ? expected : g_BoundWindows.Get(key,Map())
    if pin.Count && (pin.Get("pid",0)!=pid || StrLower(pin.Get("exe",""))!=StrLower(exe) || pin.Get("class",cls)!=cls)
        throw TargetError("Assigned window identity changed. Rebind before continuing.")
    if WinGetMinMax(hwnd)=-1
        WinRestore(hwnd)
    WinActivate(hwnd)
    if !WinWaitActive(hwnd,,3)
        throw TargetError("Assigned window could not be activated. No input issued.")
    rect := Buffer(16)
    DllCall("GetWindowRect","Ptr",hwnd,"Ptr",rect)
    target := Map("hwnd",hwnd,"pid",pid,"exe",exe,"class",cls,"title",WinGetTitle(hwnd),
        "window_rect",Map("x",NumGet(rect,0,"Int"),"y",NumGet(rect,4,"Int"),"w",NumGet(rect,8,"Int")-NumGet(rect,0,"Int"),"h",NumGet(rect,12,"Int")-NumGet(rect,4,"Int")))
    g_BoundWindows[key] := target
    if task!=""
        g_BoundTaskWindows[task] := target
    return target
}
