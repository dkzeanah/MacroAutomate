#Requires AutoHotkey v2.0
#SingleInstance Off
#Include ..\lib\DeepSeekActivity.ahk

global failures := 0
Check(value, description) {
    global failures
    if !value
        failures++
    FileAppend((value ? "PASS " : "FAIL ") . description . "`n", "*")
}
DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
original := WinExist("A")
fixture := Gui("+AlwaysOnTop -DPIScale", "DeepSeek feedback test fixture")
fixture.Add("Text", "w300 h60", "Synthetic element discovery target")
try {
    fixture.Show("NA w340 h120")
    foreground := WinExist("A")
    DeepActivity_Set(true, "Test · native discovery")
    Check(WinExist("A") = foreground, "indicator does not activate a window")
    p := DeepActivity_Position()
    monitor := MonitorGetCount() >= 2 ? 2 : MonitorGetPrimary()
    MonitorGet(monitor, &left, &top, &right, &bottom)
    Check(p["x"] >= left && p["x"]+22 <= right && p["y"] >= top && p["y"]+22 <= bottom,
        "indicator uses monitor 2 with primary fallback")
    while !Mod(A_TickCount//450, 2)
        Sleep(20)
    DeepActivity_Tick()
    Check(DllCall("IsWindowVisible", "Ptr", g_DeepActivity["dot"].Hwnd), "blink on phase")
    circle := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
    try {
        DllCall("GetWindowRgn", "Ptr", g_DeepActivity["dot"].Hwnd, "Ptr", circle)
        Check(DllCall("PtInRegion", "Ptr", circle, "Int", 11, "Int", 11)
            && !DllCall("PtInRegion", "Ptr", circle, "Int", 0, "Int", 0), "red dot has a circular region")
    } finally DllCall("DeleteObject", "Ptr", circle)
    style := WinGetExStyle(g_DeepActivity["dot"])
    Check((style & 0x08000020) = 0x08000020, "feedback is no-activate and click-through")
    affinity := 0
    DllCall("GetWindowDisplayAffinity", "Ptr", g_DeepActivity["dot"].Hwnd, "UInt*", &affinity)
    Check(affinity = 0x11, "feedback excluded from screen capture")
    WinActivate(fixture)
    WinWaitActive(fixture,,2)
    rect := Buffer(16)
    DllCall("GetWindowRect", "Ptr", fixture.Hwnd, "Ptr", rect)
    r := Map("x", NumGet(rect,0,"Int"), "y", NumGet(rect,4,"Int"),
        "w", NumGet(rect,8,"Int")-NumGet(rect,0,"Int"), "h", NumGet(rect,12,"Int")-NumGet(rect,4,"Int"))
    frame := Map("hwnd", fixture.Hwnd, "window_rect", r, "region", r,
        "geometry_stable", true, "visibility", Map("ok", true))
    result := Map("ok", true, "frame", frame, "controls", [Map("bounds", r)])
    DeepActivity_Result("fan_window_inspect", result)
    Check(g_DeepActivity["boxes"].Length = 8, "observed region and element highlighted")
    Check(WinExist("A") = fixture.Hwnd, "highlights preserve focus")
    DeepActivity_Suspend()
    DeepActivity_Tick()
    Check(g_DeepActivity["boxes"].Length = 0 && !DllCall("IsWindowVisible", "Ptr", g_DeepActivity["dot"].Hwnd),
        "perception suspension hides all feedback")
    DeepActivity_Resume()
    DeepActivity_Result("fan_window_inspect", result)
    WinMove(r["x"]+15, r["y"],,,fixture)
    DeepActivity_Tick()
    Check(g_DeepActivity["boxes"].Length = 0, "moved window invalidates highlight geometry")
    DeepActivity_Before("mouse_click", "-100,100")
    Check(g_DeepActivity["boxes"].Length = 4, "pre-action target appears before input is dispatched")
    Check(g_DeepActivity["boxes"][1].BackColor = "FFD400", "pre-action highlight is yellow")
    Check(WinExist("A") = fixture.Hwnd, "pre-action feedback preserves foreground focus")
    DeepActivity_Input("mouse_click", "-100,100")
    Check(g_DeepActivity["boxes"].Length = 4, "negative monitor input coordinates supported")
    g_DeepActivity["expires"] := A_TickCount-1
    DeepActivity_Tick()
    Check(g_DeepActivity["boxes"].Length = 0, "expired highlights cleared")
    DeepActivity_Set(true, "Expiring", 1)
    Sleep(10)
    DeepActivity_Tick()
    Check(!g_DeepActivity["active"], "lost heartbeat clears control indicator")
} finally {
    DeepActivity_Shutdown()
    fixture.Destroy()
    if original && DllCall("IsWindow", "Ptr", original)
        try WinActivate("ahk_id " . original)
}
ExitApp(failures ? 1 : 0)
