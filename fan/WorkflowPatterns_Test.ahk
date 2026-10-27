#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
#Include ..\lib\WorkflowPatterns.ahk
global failures := 0, clicks := 0, feedback := 0, matchCount := 1, effect := "", searched := []
global g_Settings := Map("FindTextTolerance",0,"MaxRetries",1,"FailsafeCheckCloseButton",false,"PreActionDelay",0,"PostActionDelay",0)
global g_AbortSequence := false, g_LastClickX := 0, g_LastClickY := 0, g_LastActionError := ""
global g_WorkflowExecutionOptions := Map("interactive",false)
global fixture := Gui("+AlwaysOnTop -DPIScale","Scoped workflow fixture")
global target := fixture.Add("Button","x20 y20 w200 h60","Synthetic calculation")
target.OnEvent("Click",(*) => RecordClick())
RecordClick() {
    global clicks
    clicks++
}
global g_Patterns := Map("test",Map("text","fixture","captureWindow",fixture.Title))
ShowStatus(*) => 0
CheckPatternQualifier(*) => true
IsNearCloseButton(*) => false
FindText(&x,&y,x1:="",y1:="",x2:="",y2:="",*) {
    global searched
    searched := [x1,y1,x2,y2]
    WinGetPos(&px,&py,&pw,&ph,target.Hwnd)
    found := []
    loop matchCount
        found.Push({x:px,y:py,mx:px+pw//2,my:py+ph//2,w:pw,h:ph})
    return found
}
DeepActivity_Target(*) {
    global feedback
    feedback++
    if effect="move" {
        WinGetPos(&x,&y,,,fixture.Hwnd)
        WinMove(x+40,y,,,fixture.Hwnd)
    }
}
Check(ok,label) {
    global failures
    failures += !ok
    FileAppend((ok ? "PASS " : "FAIL ") . label . "`n","*")
}
DllCall("SetThreadDpiAwarenessContext","Ptr",-4,"Ptr")
original := WinExist("A")
fixture.Show("w250 h110")
WinActivate(fixture.Hwnd)
WinWaitActive(fixture.Hwnd,,2)
try {
    matchCount := 2
    Check(!FindAndClickPattern("test") && clicks=0,"ambiguous matches send no input")
    g_Patterns["test"]["captureWindow"] := "Different application"
    matchCount := 1
    Check(!FindAndClickPattern("test") && clicks=0,"wrong captured window sends no input")
    g_Patterns["test"]["captureWindow"] := fixture.Title
    effect := "move"
    Check(!FindAndClickPattern("test") && clicks=0,"window movement during feedback cancels the click")
    effect := ""
    WinGetPos(&x,&y,&w,&h,fixture.Hwnd)
    Check(FindAndClickPattern("test"),"unique current target accepts the native click")
    Sleep(100)
    Check(clicks=1,"only the fixture button received input")
    Check(searched[1]=x && searched[2]=y && searched[3]=x+w-1 && searched[4]=y+h-1,"FindText searches only the active window rectangle")
    Check(feedback=2,"target feedback precedes accepted input and rechecks")
} finally {
    fixture.Destroy()
    if original
        try WinActivate(original)
}
ExitApp(failures)
