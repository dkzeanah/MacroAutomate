; Shared physical-pixel movement for this process, including click-through HUDs.
global g_SecondaryDrag := Map(), g_SecondaryPins := Map()

SecondaryWindows_Start() {
    HotIf((*) => SecondaryWindows_Target() != 0)
    Hotkey("^RButton", SecondaryWindows_Begin)
    HotIf()
}

SecondaryWindows_Target() {
    global MainGui
    old := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try {
        MouseGetPos(&mx, &my)
        for hwnd in WinGetList() {
            if WinGetMinMax(hwnd) = -1
                continue
            WinGetPos(&x, &y, &w, &h, hwnd)
            if mx >= x && mx < x+w && my >= y && my < y+h {
                if WinGetPID(hwnd) != DllCall("GetCurrentProcessId", "UInt")
                    return 0
                if IsSet(MainGui) && IsObject(MainGui) && hwnd = MainGui.Hwnd
                    return 0
                return hwnd
            }
        }
        return 0
    } finally DllCall("SetThreadDpiAwarenessContext", "Ptr", old, "Ptr")
}

SecondaryWindows_Begin(*) {
    global g_SecondaryDrag, g_SecondaryPins
    hwnd := SecondaryWindows_Target()
    if !hwnd
        return
    old := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try {
        MouseGetPos(&mx, &my)
        WinGetPos(&x, &y,,, hwnd)
        g_SecondaryDrag := Map("hwnd", hwnd, "dx", mx-x, "dy", my-y)
        g_SecondaryPins[hwnd] := WinGetTitle(hwnd)
        SetTimer(SecondaryWindows_Tick, 16)
    } finally DllCall("SetThreadDpiAwarenessContext", "Ptr", old, "Ptr")
}

SecondaryWindows_Tick() {
    global g_SecondaryDrag
    old := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try {
        hwnd := g_SecondaryDrag.Get("hwnd", 0)
        if !hwnd || !WinExist(hwnd) {
            SetTimer(SecondaryWindows_Tick, 0)
            return
        }
        if !GetKeyState("RButton", "P") || !GetKeyState("Ctrl", "P") {
            SetTimer(SecondaryWindows_Tick, 0)
            SecondaryWindows_Clamp(hwnd)
            SecondaryWindows_Save(hwnd)
            g_SecondaryDrag := Map()
            return
        }
        MouseGetPos(&mx, &my)
        WinMove(mx-g_SecondaryDrag["dx"], my-g_SecondaryDrag["dy"],,, hwnd)
    } finally DllCall("SetThreadDpiAwarenessContext", "Ptr", old, "Ptr")
}

SecondaryWindows_Clamp(hwnd) {
    WinGetPos(&x, &y, &w, &h, hwnd)
    cx := x+w/2, cy := y+h/2, best := 0, distance := 1.0e30
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        d := (cx-Max(l,Min(r,cx)))**2 + (cy-Max(t,Min(b,cy)))**2
        if d < distance
            best := A_Index, distance := d
    }
    MonitorGetWorkArea(best, &l, &t, &r, &b)
    ; Size as well as position must fit: a HUD must never straddle a seam.
    w := Min(w,r-l), h := Min(h,b-t)
    WinMove(Max(l,Min(r-w,x)), Max(t,Min(b-h,y)), w, h, hwnd)
}

SecondaryWindows_Save(hwnd) {
    config := FanData_Config().Clone()
    positions := config.Get("secondary_positions", Map())
    WinGetPos(&x, &y,,, hwnd)
    positions[WinGetTitle(hwnd)] := Map("x",x,"y",y)
    config["secondary_positions"] := positions
    FanData_SaveConfig(config)
}

SecondaryWindows_Place(gui, options := "NoActivate") {
    global g_SecondaryPins
    old := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try {
        saved := FanData_Config().Get("secondary_positions", Map()).Get(gui.Title, Map())
        if saved.Count {
            gui.Show(options . " x" . saved["x"] . " y" . saved["y"])
            g_SecondaryPins[gui.Hwnd] := gui.Title
        } else
            gui.Show(options)
        SecondaryWindows_Clamp(gui.Hwnd)
    } finally DllCall("SetThreadDpiAwarenessContext", "Ptr", old, "Ptr")
}

SecondaryWindows_IsPinned(hwnd) {
    return g_SecondaryPins.Has(hwnd) && g_SecondaryPins[hwnd] = WinGetTitle(hwnd)
}

SecondaryWindows_ShowAt(gui, options) {
    if SecondaryWindows_IsPinned(gui.Hwnd)
        gui.Show("NA")
    else
        SecondaryWindows_Place(gui, options)
}
