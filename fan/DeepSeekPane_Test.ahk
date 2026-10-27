#Requires AutoHotkey v2.0
#SingleInstance Off
#Include ..\lib\DeepSeekPane.ahk
StudyConsole_Redact(value) => value
failures := 0
Check(ok,label) {
    global failures
    failures += !ok
    FileAppend((ok ? "PASS " : "FAIL ") . label . "`n","*")
}
g := Gui("-DPIScale","Stream scrolling regression fixture")
pane := g.Add("Edit","w350 h100 ReadOnly Multi +VScroll")
original := WinExist("A")
g.Show("NA")
text := ""
loop 150
    text .= "Thinking entry " . A_Index . " â€” Î± ðŸ˜€`r`n"
DeepBridge_Pane(pane,text)
start := Buffer(4), finish := Buffer(4)
SendMessage(0x00B0,start.Ptr,finish.Ptr,pane)
length := SendMessage(0x000E,0,0,pane)
Check(NumGet(finish,0,"UInt")=length,"caret reaches actual UTF-16 end of stream")
first := SendMessage(0x00CE,0,0,pane)
Check(first>100,"thinking pane follows bottom entries")
DeepBridge_Pane(pane,text . "Newest visible entry`r`n")
Check(SendMessage(0x00CE,0,0,pane)>=first,"appending keeps the viewport at the bottom")
Check(InStr(pane.Value,"Newest visible entry"),"stream content is preserved")
Check(WinExist("A")=original,"following stream does not steal foreground focus")
g.Destroy()
ExitApp(failures)
