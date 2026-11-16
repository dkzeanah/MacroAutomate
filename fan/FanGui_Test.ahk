#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
; Build the actual app pages against a fresh store, without starting collectors.
; /background keeps this verification window hidden throughout the test.
if !A_Args.Length || A_Args[1] != "/background" {
    FileAppend("Run FanGui_Test.ahk /background (hidden actual-controls check).`n", "*")
    ExitApp(2)
}
FileAppend("GUI CHECK: bootstrap`n", "*")
#Include Core\_Bootstrap.ahk
global g_FanSeedPath := A_Temp . "\FanGui-" . DllCall("GetCurrentProcessId", "UInt") . ".sqlite"
FileAppend("GUI CHECK: dependencies`n", "*")
#Include Core\_Dependencies.ahk
FileAppend("GUI CHECK: globals`n", "*")
#Include Core\_Globals.ahk
FileAppend("GUI CHECK: modules`n", "*")
#Include Core\_Modules.ahk
FileAppend("GUI CHECK: seed`n", "*")
OnError(GuiTest_Error)
GuiTest_Error(err, *) {
    FileAppend("ERROR " . err.Message . " at " . err.File . ":" . err.Line . "`n", "*")
    ExitApp(2)
}
GuiTest_PageVisible(ctl) {
    ; Tab3 hides the page's parent dialog; a child's own Visible property alone
    ; stays true. Ignore the hidden top-level test window, but honor each parent.
    hwnd := ctl.Hwnd
    while hwnd && hwnd != MainGui.Hwnd {
        if !(DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", -16, "Ptr") & 0x10000000)
            return false
        hwnd := DllCall("GetParent", "Ptr", hwnd, "Ptr")
    }
    return hwnd = MainGui.Hwnd
}
global guiFailures := 0
FanUnified_Seed(g_FanSeedPath)
InitDB()
global g_GdipToken := Gdip_Startup()
OnExit(ShutdownGdip)
#Include Core\_Shell.ahk
g_FanNav["classicTabs"].GetPos(&headerX, &headerY, &headerW, &headerH)
rect := Buffer(16)
SendMessage(0x130A, 0, rect.Ptr, g_FanNav["classicTabs"])
itemW := NumGet(rect, 8, "Int") - NumGet(rect, 0, "Int")
itemH := NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int")
headerOk := itemW > 20 && itemH > 10 && headerH >= itemH
guiFailures += !headerOk
FileAppend((headerOk ? "PASS " : "FAIL ") . "native tab header " . headerW . "x" . headerH . "; item " . itemW . "x" . itemH . "`n", "*")
; The test invokes every original builder above, and checks its real controls.
; Additive navigation controls are excluded from the per-page counts.
excluded := Map()
for ctl in g_FanNav["controls"]
    excluded[ctl.Hwnd] := true
for key in ["OnTop", "Tabs"] {
    try excluded[MainGui[key].Hwnd] := true
}
for page in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23] {
    FanNav_Open(page)
    controls := 0, interactive := 0
    for ctl in MainGui {
        if excluded.Has(ctl.Hwnd) || !GuiTest_PageVisible(ctl)
            continue
        if ctl.Type = "Tab" || ctl.Type = "Tab3" || ctl.Type = "StatusBar"
            continue
        ctl.GetPos(, &y)
        if y < 48
            continue
        controls++
        if ctl.Type = "Button" || ctl.Type = "ListView" || ctl.Type = "Edit" || ctl.Type = "DropDownList"
            interactive++
    }
    ok := controls >= 4 && interactive >= 2
    guiFailures += !ok
    FileAppend((ok ? "PASS " : "FAIL ") . "actual page " . page . " " . FanNav_ClassicPageName(page)
        . ": " . controls . " controls, " . interactive . " interactive`n", "*")
}
; Builders catch their own exceptions, so inspect the isolated error log too.
if FanFileExist(ERROR_LOG_FILE) {
    errors := FanFileRead(ERROR_LOG_FILE)
    if InStr(errors, "tab construction") {
        guiFailures++
        FileAppend("FAIL actual builder logged a construction error`n" . errors . "`n", "*")
    }
}
FileAppend("RESULT GUI failures=" . guiFailures . "`n", "*")
ExitApp(guiFailures ? 1 : 0)
