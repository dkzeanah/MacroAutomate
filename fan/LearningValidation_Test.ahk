#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
#Include ..\lib\TrackUtil.ahk
#Include Core\_Gdip.ahk
CoordMode("Pixel", "Screen")
DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")

global testRoot := A_Temp . "\FanValidationFixture-" . DllCall("GetCurrentProcessId", "UInt")
DirCreate(testRoot)
global g_FanDataConfigOverride := testRoot . "\storage.json"
FanData_SaveConfig(Map("learning_validation", 1, "learning_monitor", 3))
global passed := 0, failures := 0
Assert(ok, label) {
    global passed, failures
    if ok
        passed++
    else
        failures++
    FileAppend((ok ? "PASS " : "FAIL ") . label . "`n", "*")
}
token := Gdip_Startup(), fixture := 0
try {
    monitor := LearningValidation_Monitor()
    Assert(!monitor || (monitor > 1 && monitor != MonitorGetPrimary()), "Feedback never chooses the first or primary display")
    if monitor {
        MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
        fixture := Gui("+ToolWindow -DPIScale", "Synthetic learning target")
        fixture.BackColor := "FFFFFF"
        fixture.Add("Progress", "x20 y40 w180 h70 -Theme cE02030 BackgroundE02030", 100)
        fixture.Show("NA x" . (left+30) . " y" . (top+420) . " w300 h150")
        WinGetClientPos(&x, &y,,, fixture)
        region := Map("x",x+20,"y",y+40,"w",180,"h",70)
        active := WinExist("A")
        Assert(LearningValidation_Show(), "Secondary validation panel opens")
        LearningValidation_Event("Fixture", "verified", "Synthetic red target matches", region, fixture.Hwnd)
        Sleep 200
        Assert(WinExist("A") = active, "Live feedback does not steal focus")
        WinGetPos(&px,&py,&pw,&ph,g_LearnView["gui"])
        Assert(!LearningValidation_PrimaryRegion(px,py,pw,ph), "Entire validation window stays off the primary display")
        Assert(g_LearnView["log"].GetText(1, 3) = "verified", "Evidence status is rendered in the live log")
        g_LearnView["edges"][1].GetPos(&bx,&by,&bw,&bh)
        Assert(bw>2 && bh=2 && bx>=12 && by>=58, "Target box is mapped into the preview")
        WinGetClientPos(&cx,&cy,,,g_LearnView["gui"])
        ; Sample the preview's interior, away from the verification border.
        color := PixelGetColor(cx+bx+10,cy+by+10)
        FileAppend("DETAIL monitor=" . monitor . " area=" . left . "," . top . "," . right . "," . bottom . " window=" . px . "," . py . "," . pw . "," . ph . " sample=" . Format("{:06X}",color) . " border=" . bx . "," . by . "," . bw . "`n", "*")
        bitmap := Gdip_BitmapFromScreen(px . "|" . py . "|" . pw . "|" . ph)
        if bitmap {
            Gdip_SaveBitmapToFile(bitmap, A_ScriptDir . "\tests\runtime\LearningValidation_Test.png")
            Gdip_DisposeImage(bitmap)
        }
        Assert(Abs((color>>16 & 255)-224)<=2 && Abs((color>>8 & 255)-32)<=2 && Abs((color & 255)-48)<=2, "Live preview pixels contain the actual synthetic red target")
        borderColor := PixelGetColor(cx+bx+1,cy+by+1)
        Assert(borderColor = 0x16883E, "Verified target border is visibly green")
        LearningValidation_SetEnabled(false)
        Assert(!(WinGetStyle(g_LearnView["gui"]) & 0x10000000), "Disabling validation hides the window")
    }
} catch as err {
    Assert(false, err.Message . " at line " . err.Line)
} finally {
    SetTimer(LearningValidation_Heartbeat, 0)
    if IsObject(fixture)
        fixture.Destroy()
    if g_LearnView.Has("gui")
        g_LearnView["gui"].Destroy()
    Gdip_Shutdown(token)
    FileDelete(g_FanDataConfigOverride)
    DirDelete(testRoot)
}
FileAppend("RESULT " . passed . " passed, " . failures . " failed`n", "*")
ExitApp(failures ? 1 : 0)
