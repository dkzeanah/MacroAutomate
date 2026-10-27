#Requires AutoHotkey v2.0
#SingleInstance Off
#Include Core\_Gdip.ahk
#Include ..\lib\DeepSeekImages.ahk
DeepBridge_Request(*) => 0
Photo_DataUrl(*) => ""
failures := 0
Check(ok,label) {
    global failures
    failures += !ok
    FileAppend((ok ? "PASS " : "FAIL ") . label . "`n","*")
}
fixture := Gui("-DPIScale","Clipboard input test fixture")
status := fixture.Add("Text","w420")
global g_DeepBridge := Map("busy",false,"images",[],"root",A_ScriptDir . "\DeepSeekBridge","ui",Map("attachment",status))
saved := ClipboardAll(), bitmap := 0, path := ""
try {
    pixels := Buffer(16*16*4,0)
    loop 16*16
        NumPut("UInt",0xFFFF0000,pixels,(A_Index-1)*4)
    bitmap := DllCall("CreateBitmap","Int",16,"Int",16,"UInt",1,"UInt",32,"Ptr",pixels,"Ptr")
    if !bitmap || !DllCall("OpenClipboard","Ptr",fixture.Hwnd)
        throw Error("Could not initialize clipboard fixture")
    try {
        DllCall("EmptyClipboard")
        if !DllCall("SetClipboardData","UInt",2,"Ptr",bitmap,"Ptr")
            throw Error("Could not set clipboard fixture")
        bitmap := 0
    } finally DllCall("CloseClipboard")
    Check(DeepBridge_HasClipboardImage(),"Windows bitmap is recognized as image input")
    DeepBridge_PasteImage()
    Check(g_DeepBridge["images"].Length=1,"production paste captures a local image attachment")
    if g_DeepBridge["images"].Length {
        item := g_DeepBridge["images"][1], path := item["path"]
        Check(FileExist(path) && FileGetSize(path)>33,"clipboard bitmap is saved as a real PNG")
        data := FileRead(path,"RAW")
        Check(NumGet(data,0,"UInt")=0x474E5089,"saved attachment has PNG signature")
        Check(item["id"]="","paste does not upload or invoke vision before Send")
        Check(InStr(status.Value,"1 image(s)"),"native composer displays attached-image count")
    }
    g_DeepBridge["busy"] := true
    DeepBridge_PasteImage()
    Check(g_DeepBridge["images"].Length=1,"active task cannot mutate its submitted image list")
    g_DeepBridge["busy"] := false
    DeepBridge_ClearImages()
    Check(g_DeepBridge["images"].Length=0,"Remove clears pending attachments")
} catch as err {
    Check(false,err.Message . " " . status.Value)
} finally {
    A_Clipboard := saved
    if bitmap
        DllCall("DeleteObject","Ptr",bitmap)
    if path && FileExist(path)
        FileDelete(path)
    fixture.Destroy()
}
ExitApp(failures ? 1 : 0)
