; Selection-only, click-through retained-evidence outlines. Never activates a target.
NativeOverlay_Clear(*) {
    for border in g_NativeWB.Get("overlays",[])
        try border.Destroy()
    g_NativeWB["overlays"] := []
}

NativeOverlay_Input(wParam,lParam,msg,hwnd) {
    u := g_NativeWB["ui"]
    if !u.Has("timeline") || (hwnd!=u["timeline"].Hwnd && hwnd!=u["controls"].Hwnd)
        return
    if msg=0x101 && !InStr("|32|33|34|35|36|37|38|39|40|","|" . wParam . "|")
        return
    ; ItemSelect is also fired by auto-follow. Only a mouse/key selection schedules outlines.
    SetTimer((*)=>NativeOverlay_Selection(hwnd),-20)
}

NativeOverlay_Selection(hwnd) {
    s := g_NativeWB, u := s["ui"]
    try {
        if hwnd=u["timeline"].Hwnd {
            row := u["timeline"].GetNext()
            if row && row<=s["cards"].Length
                NativeOverlay_Show(s["cards"][row])
        } else if s.Has("currentCard")
            NativeOverlay_Show(s["currentCard"],u["controls"].GetNext())
    } catch as err
        u["caption"].Value := "Highlight unavailable · " . err.Message
}

NativeOverlay_Validate(frame) {
    hwnd := frame.Get("hwnd",0), old := frame.Get("window_rect",Map())
    if !hwnd || !frame.Get("pid",0) || !old.Count
        throw Error("This observation has no verified window identity and geometry.")
    if !WinExist("ahk_id " . hwnd) || WinGetPID("ahk_id " . hwnd)!=frame["pid"] || WinGetMinMax("ahk_id " . hwnd)=-1
        throw Error("The retained window is closed, replaced or minimized. Capture it again.")
    WinGetPos(&x,&y,&w,&h,"ahk_id " . hwnd)
    for key,value in Map("x",x,"y",y,"w",w,"h",h)
        if !old.Has(key) || Abs(old[key]-value)>1
            throw Error("Stale coordinates: the window moved or resized. Capture it again.")
    return hwnd
}

NativeOverlay_Boxes(card,row := 0) {
    data := card.Get("data",Map()), kind := card.Get("kind",""), items := [], boxes := []
    if kind="controls" {
        items := data.Get("controls",[])
        if row>0
            items := row<=items.Length ? [items[row]] : []
    } else if kind="ocr"
        items := data.Get("lines",data.Get("groups",data.Get("words",[])))
    else if kind="findtext"
        items := data.Get("matches",[])
    else if kind="zones"
        items := data.Get("zones",[])
    else if kind="image" && data.Has("legend")
        items := data["legend"]
    else if kind="image"
        items := [Map("bounds",card.Get("frame",Map()).Get("region",Map()))]
    if items is Array
        for item in items {
            if boxes.Length>=64
                break
            box := item.Get("bounds",Map())
            if box.Get("w",0)>0 && box.Get("h",0)>0
                boxes.Push(box)
        }
    return boxes
}

NativeOverlay_Show(card,row := 0) {
    NativeOverlay_Clear()
    frame := card.Get("frame",Map()), hwnd := NativeOverlay_Validate(frame), boxes := NativeOverlay_Boxes(card,row)
    shown := 0, region := frame["window_rect"]
    for box in boxes {
        x := Max(region["x"],Round(box["x"])), y := Max(region["y"],Round(box["y"]))
        r := Min(region["x"]+region["w"],Round(box["x"]+box["w"]))
        b := Min(region["y"]+region["h"],Round(box["y"]+box["h"]))
        if r<=x || b<=y
            continue
        hit := DllCall("WindowFromPoint","Int64",((y+(b-y)//2)<<32)|((x+(r-x)//2)&0xFFFFFFFF),"Ptr")
        if !hit || DllCall("GetAncestor","Ptr",hit,"UInt",2,"Ptr")!=hwnd
            continue
        border := NativeOverlay_Border(x,y,r-x,b-y)
        g_NativeWB["overlays"].Push(border)
        shown++
    }
    g_NativeWB["ui"]["caption"].Value := shown ? "Retained candidate bounds · " . shown . " highlighted · current element identity is unverified" : "No visible candidate bounds; target may be covered. Capture it again."
    SetTimer(NativeOverlay_Clear,-1600)
}

NativeOverlay_Border(x,y,w,h) {
    border := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80020 +E0x08000000 -DPIScale")
    border.BackColor := "FF3B30", outer := 0, inner := 0
    try {
        ; One hollow native window per candidate, rather than four border windows.
        outer := DllCall("CreateRectRgn","Int",0,"Int",0,"Int",w,"Int",h,"Ptr")
        if w>4 && h>4 {
            inner := DllCall("CreateRectRgn","Int",2,"Int",2,"Int",w-2,"Int",h-2,"Ptr")
            DllCall("CombineRgn","Ptr",outer,"Ptr",outer,"Ptr",inner,"Int",4)
        }
        if !DllCall("SetWindowRgn","Ptr",border.Hwnd,"Ptr",outer,"Int",true)
            throw Error("Unable to draw candidate outline")
        outer := 0 ; SetWindowRgn owns this region now.
        WinSetTransparent(255,border.Hwnd)
        DllCall("SetWindowDisplayAffinity","Ptr",border.Hwnd,"UInt",0x11)
        border.Show("NoActivate x" . x . " y" . y . " w" . w . " h" . h)
        return border
    } catch {
        border.Destroy()
        throw
    } finally {
        if outer
            DllCall("DeleteObject","Ptr",outer)
        if inner
            DllCall("DeleteObject","Ptr",inner)
    }
}
