; Explicit clipboard-image input. No clipboard image is sent until Send is used.
DeepBridge_HasClipboardImage() => DllCall("IsClipboardFormatAvailable","UInt",2) || DllCall("IsClipboardFormatAvailable","UInt",8) || DllCall("IsClipboardFormatAvailable","UInt",17)

DeepBridge_OnPaste(wParam,lParam,message,hwnd) {
    if g_DeepBridge["ui"].Count && hwnd=g_DeepBridge["ui"]["input"].Hwnd && DeepBridge_HasClipboardImage() {
        SetTimer(DeepBridge_PasteImage,-1)
        return 0
    }
}

DeepBridge_PasteImage(*) {
    if g_DeepBridge["busy"]
        return
    try {
        if g_DeepBridge["images"].Length>=4
            throw Error("Attach up to four images per task")
        if !DeepBridge_HasClipboardImage()
            throw Error("Copy an image with Snipping Tool first")
        token := Gdip_Startup(), bitmap := 0, opened := false
        try {
            if !DllCall("OpenClipboard","Ptr",0)
                throw Error("Clipboard is busy; paste again")
            opened := true
            handle := DllCall("GetClipboardData","UInt",2,"Ptr")
            if !handle || !(bitmap := Gdip_CreateBitmapFromHBITMAP(handle))
                throw Error("Clipboard image could not be decoded")
            folder := g_DeepBridge["root"] . "\.runtime\captures\pasted"
            DirCreate(folder)
            path := folder . "\snip-" . A_TickCount . "-" . Random(1000,9999) . ".png"
            if Gdip_SaveBitmapToFile(bitmap,path)!=0
                throw Error("Clipboard image could not be saved")
        } finally {
            if opened
                DllCall("CloseClipboard")
            if bitmap
                Gdip_DisposeImage(bitmap)
            if token
                Gdip_Shutdown(token)
        }
        g_DeepBridge["images"].Push(Map("path",path,"id","","label","Clipboard snip"))
        DeepBridge_ImageStatus()
    } catch as err
        g_DeepBridge["ui"]["attachment"].Value := err.Message
}

DeepBridge_ImageStatus() {
    count := g_DeepBridge["images"].Length
    g_DeepBridge["ui"]["attachment"].Value := count ? count . " image(s) attached locally · analyzed on Send" : "Paste a snip into the message box · Ctrl+V"
}

DeepBridge_ClearImages(*) {
    if !g_DeepBridge["busy"]
        g_DeepBridge["images"] := [], DeepBridge_ImageStatus()
}

DeepBridge_PreviewImage(*) {
    if !g_DeepBridge["images"].Length
        return
    preview := Gui("+Resize -DPIScale","Attached image — sent for vision analysis with your message")
    preview.Add("Picture","w600 h-1",g_DeepBridge["images"][-1]["path"])
    preview.OnEvent("Close",(*)=>preview.Destroy())
    preview.Show()
}

DeepBridge_PrepareImages() {
    identities := []
    for item in g_DeepBridge["images"] {
        if item["id"]="" {
            if FileGetSize(item["path"])>8388608
                throw Error("Attached image exceeds 8 MiB")
            uploaded := DeepBridge_Request("POST","/images",Map("data_url",Photo_DataUrl(item["path"]),"label",item["label"]))
            item["id"] := uploaded["id"]
        }
        identities.Push(item["id"])
    }
    return identities
}
