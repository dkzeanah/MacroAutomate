; Click-through feedback for the DeepSeek bridge. Coordinates are physical pixels.
; The main app can supply shared placement without coupling standalone workers
; and their tests to the tracking database or configuration modules.
global g_DeepActivityPlacement := 0
global g_DeepActivity := Map("active", false, "label", "", "dot", 0, "caption", 0,
    "boxes", [], "expires", 0, "hwnd", 0, "rect", Map(), "suspended", false,
    "lease", 0, "studyVisible", false, "allowBackground", false)

DeepActivity_Gui(title, color) {
    window := Gui("+AlwaysOnTop -Caption +ToolWindow +Disabled -DPIScale +E0x08000020", title)
    window.BackColor := color
    ; Keep feedback out of screenshots on supported Windows versions.
    try DllCall("SetWindowDisplayAffinity", "Ptr", window.Hwnd, "UInt", 0x11)
    return window
}

DeepActivity_Set(active, label := "", lease := 5000) {
    g_DeepActivity["active"] := !!active
    g_DeepActivity["label"] := label
    g_DeepActivity["lease"] := A_TickCount + lease
    if !active {
        if IsObject(g_DeepActivity["dot"])
            g_DeepActivity["dot"].Hide()
        if IsObject(g_DeepActivity["caption"])
            g_DeepActivity["caption"].Hide()
    }
    SetTimer(DeepActivity_Tick, 100)
    DeepActivity_Tick()
}

DeepActivity_Position() {
    ; Windows display number 2, falling back to the primary on a one-screen PC.
    monitor := MonitorGetCount() >= 2 ? 2 : MonitorGetPrimary()
    MonitorGet(monitor, &left, &top, &right, &bottom)
    MonitorGetWorkArea(monitor, &wl, &wt, &wr, &wb)
    x := wl + 14, y := wb - 34
    ; Prefer the taskbar band when it is present on this display.
    if bottom - wb >= 24
        y := wb + (bottom-wb-22)//2
    else if wt - top >= 24
        y := top + (wt-top-22)//2
    else if wl - left >= 24
        x := left + (wl-left-22)//2, y := wt+14
    else if right - wr >= 24
        x := wr + (right-wr-22)//2, y := wt+14
    return Map("x", x, "y", y, "labelX", wl+44, "labelY", wb-34,
        "labelW", Max(80, Min(420, wr-wl-60)))
}

DeepActivity_Tick() {
    dpi := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try {
        if g_DeepActivity["expires"] && (A_TickCount >= g_DeepActivity["expires"] || !DeepActivity_FrameCurrent())
            DeepActivity_Clear()
        if g_DeepActivity["active"] && A_TickCount > g_DeepActivity["lease"]
            DeepActivity_Set(false)
        if !g_DeepActivity["active"] && !g_DeepActivity["boxes"].Length
            SetTimer(DeepActivity_Tick, 0)
        if !g_DeepActivity["active"] || g_DeepActivity["suspended"]
            return
        if !IsObject(g_DeepActivity["dot"]) {
            g_DeepActivity["dot"] := DeepActivity_Gui("DeepSeek control indicator", "FF2020")
            g_DeepActivity["caption"] := DeepActivity_Gui("DeepSeek live activity", "202020")
            g_DeepActivity["caption"].SetFont("s9 cFFFFFF", "Segoe UI")
            g_DeepActivity["text"] := g_DeepActivity["caption"].Add("Text", "x7 y4 w406 h22", "")
        }
        p := DeepActivity_Position()
        g_DeepActivity["text"].Value := "DeepSeek · " . g_DeepActivity["label"]
        DeepActivity_Show(g_DeepActivity["caption"],"NA x" . p["labelX"] . " y" . p["labelY"] . " w" . p["labelW"] . " h28")
        if Mod(A_TickCount//450, 2) {
            DeepActivity_Show(g_DeepActivity["dot"],"NA x" . p["x"] . " y" . p["y"] . " w22 h22")
            WinSetRegion("0-0 W22 H22 E", g_DeepActivity["dot"])
        } else
            g_DeepActivity["dot"].Hide()
    } finally {
        if dpi
            DllCall("SetThreadDpiAwarenessContext", "Ptr", dpi, "Ptr")
    }
}

DeepActivity_FrameCurrent() {
    hwnd := g_DeepActivity["hwnd"]
    if !hwnd
        return true
    if !DllCall("IsWindowVisible", "Ptr", hwnd) || DllCall("IsIconic", "Ptr", hwnd)
        || (!g_DeepActivity["allowBackground"] && WinExist("A") != hwnd)
        return false
    r := Buffer(16), old := g_DeepActivity["rect"]
    if !DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", r)
        return false
    return NumGet(r, 0, "Int") = old["x"] && NumGet(r, 4, "Int") = old["y"]
        && NumGet(r, 8, "Int")-old["x"] = old["w"] && NumGet(r, 12, "Int")-old["y"] = old["h"]
}

DeepActivity_Show(gui,options) {
    if IsObject(g_DeepActivityPlacement)
        g_DeepActivityPlacement.Call(gui,options)
    else
        gui.Show(options)
}

DeepActivity_Clear() {
    for window in g_DeepActivity["boxes"]
        try window.Destroy()
    g_DeepActivity["boxes"] := [], g_DeepActivity["expires"] := 0
    g_DeepActivity["hwnd"] := 0
    g_DeepActivity["allowBackground"] := false
}

DeepActivity_Suspend() {
    global g_StudyOverlayGui
    g_DeepActivity["suspended"] := true
    DeepActivity_Clear()
    for name in ["dot", "caption"]
        if IsObject(g_DeepActivity[name])
            g_DeepActivity[name].Hide()
    if IsSet(g_StudyOverlayGui) && IsObject(g_StudyOverlayGui) && DllCall("IsWindowVisible", "Ptr", g_StudyOverlayGui.Hwnd) {
        g_DeepActivity["studyVisible"] := true
        g_StudyOverlayGui.Hide()
    }
    ; Flush hidden windows before visibility sampling and pixel capture.
    try DllCall("dwmapi\DwmFlush")
}

DeepActivity_Resume() {
    global g_StudyOverlayGui
    g_DeepActivity["suspended"] := false
    if g_DeepActivity["studyVisible"] && IsSet(g_StudyOverlayGui) && IsObject(g_StudyOverlayGui)
        try g_StudyOverlayGui.Show("NA")
    g_DeepActivity["studyVisible"] := false
    DeepActivity_Tick()
}

DeepActivity_Box(bounds, color := "FFD400") {
    if !(bounds is Map)
        return
    for key in ["x", "y", "w", "h"]
        if !bounds.Has(key) || !IsNumber(bounds[key])
            return
    x := Round(bounds["x"]), y := Round(bounds["y"]), w := Round(bounds["w"]), h := Round(bounds["h"])
    if w < 1 || h < 1 || w > 16384 || h > 16384
        return
    for strip in [[x,y,w,2], [x,y+h-2,w,2], [x,y,2,h], [x+w-2,y,2,h]] {
        window := DeepActivity_Gui("DeepSeek observed element", color)
        window.Show("NA x" . strip[1] . " y" . strip[2] . " w" . strip[3] . " h" . strip[4])
        g_DeepActivity["boxes"].Push(window)
    }
}

DeepActivity_Target(bounds, label := "Automation target", holdMs := 0) {
    DeepActivity_Clear()
    DeepActivity_Set(true, label, 10000)
    DeepActivity_Box(bounds, "FFD400")
    g_DeepActivity["expires"] := A_TickCount+2200
    try DllCall("dwmapi\DwmFlush")
    if holdMs > 0
        Sleep(Min(1000,holdMs))
}

DeepActivity_Before(name, arg := "") {
    if name = "mouse_click" || name = "mouse_move" {
        if arg = "" {
            MouseGetPos(&px,&py)
            arg := px . "," . py
        }
        xy := StrSplit(arg, ",")
        if xy.Length >= 2 && IsNumber(xy[1]) && IsNumber(xy[2])
            DeepActivity_Target(Map("x",Integer(xy[1])-15,"y",Integer(xy[2])-15,"w",30,"h",30), "About to " . name, 300)
    } else if name = "window_activate" || name = "key_send" || name = "text_type" {
        hwnd := name = "window_activate" ? WinExist(arg) : WinExist("A")
        if !hwnd
            return
        WinGetPos(&x,&y,&w,&h,hwnd)
        if name != "window_activate" {
            try {
                focused := ControlGetFocus(hwnd)
                if focused != "" {
                    control := ControlGetHwnd(focused,hwnd)
                    WinGetPos(&x,&y,&w,&h,control)
                }
            }
        }
        DeepActivity_Target(Map("x",x,"y",y,"w",w,"h",h), "About to " . name, 300)
    }
}

DeepActivity_Result(name, result) {
    DeepActivity_Clear()
    if !(result is Map) || !result.Get("ok", false) || !result.Has("frame")
        return
    frame := result["frame"]
    windowSurface := frame.Get("capture_source", "") = "Windows_Graphics_Capture_Chrome_window_surface"
    if (!windowSurface && !frame.Get("visibility", Map()).Get("ok", false)) || !frame.Get("geometry_stable", false)
        return
    g_DeepActivity["allowBackground"] := windowSurface
    g_DeepActivity["hwnd"] := frame["hwnd"], g_DeepActivity["rect"] := frame["window_rect"]
    if !DeepActivity_FrameCurrent()
        return
    if frame.Get("visibility", Map()).Get("ok", false)
        DeepActivity_Box(frame["region"], "FFB000")
    count := 0
    controls := result.Get("matches", result.Get("controls", []))
    if !controls.Length && result.Has("ocr")
        controls := result["ocr"].Get("lines", [])
    for control in controls {
        if control.Get("protected", false) || !control.Get("enabled", true)
            continue
        if control.Has("bounds") {
            if windowSurface && !DeepActivity_TargetVisible(frame["hwnd"], control["bounds"])
                continue
            DeepActivity_Box(control["bounds"])
            if ++count >= 24
                break
        }
    }
    g_DeepActivity["expires"] := A_TickCount + 1200
    SetTimer(DeepActivity_Tick, 100)
}

DeepActivity_TargetVisible(hwnd, bounds) {
    ; Keep the feedback module independent of FanBridgeVision: the standalone
    ; input worker also includes this file. This is only a highlight check.
    if !DllCall("IsWindowVisible", "Ptr", hwnd) || DllCall("IsIconic", "Ptr", hwnd)
        return false
    for point in [[bounds["x"]+bounds["w"]//2,bounds["y"]+bounds["h"]//2],
        [bounds["x"]+1,bounds["y"]+1], [bounds["x"]+bounds["w"]-2,bounds["y"]+bounds["h"]-2]] {
        hit := DllCall("WindowFromPoint", "Int64", (point[2]<<32)|(point[1]&0xFFFFFFFF), "Ptr")
        if DllCall("GetAncestor", "Ptr", hit, "UInt", 2, "Ptr") != hwnd
            return false
    }
    return true
}

DeepActivity_Input(name, arg) {
    DeepActivity_Clear()
    if name = "mouse_click" || name = "mouse_move" {
        xy := StrSplit(arg, ",")
        DeepActivity_Box(Map("x", Integer(xy[1])-12, "y", Integer(xy[2])-12, "w", 24, "h", 24), "FFB000")
    } else if name = "key_send" || name = "text_type" || name = "window_activate" {
        hwnd := WinExist("A")
        if hwnd {
            rect := Buffer(16)
            DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect)
            DeepActivity_Box(Map("x", NumGet(rect,0,"Int"), "y", NumGet(rect,4,"Int"),
                "w", NumGet(rect,8,"Int")-NumGet(rect,0,"Int"), "h", NumGet(rect,12,"Int")-NumGet(rect,4,"Int")), "FFB000")
        }
    }
    g_DeepActivity["expires"] := A_TickCount + 650
    SetTimer(DeepActivity_Tick, 100)
}

DeepActivity_Shutdown(*) {
    SetTimer(DeepActivity_Tick, 0)
    DeepActivity_Clear()
    for name in ["dot", "caption"]
        if IsObject(g_DeepActivity[name])
            try g_DeepActivity[name].Destroy()
    g_DeepActivity["dot"] := 0, g_DeepActivity["caption"] := 0
    g_DeepActivity["active"] := false
}
