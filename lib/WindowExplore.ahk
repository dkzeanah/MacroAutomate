; Active discovery is navigation only. Generic command buttons are never probed.
#Include DaaGraphics.ahk
FanWindow_Focus(hwnd) {
    f := Acc.ElementFromHandle(hwnd).Focus
    loop 16 {
        try next := f.Focus
        catch
            break
        if !IsObject(next) || next.IsEqual(f)
            break
        f := next
    }
    return f
}

FanWindow_InputGuard(hwnd) {
    global g_FanBridgeTask
    if IsSet(g_FanBridgeTask) && g_FanBridgeTask!="" {
        prepare := "FanAPI_PrepareWindow"
        %prepare%(hwnd)
    }
    if !hwnd || WinExist("A")!=hwnd
        throw TargetError("Exact target lost foreground; no exploration input was sent")
}

FanWindow_MenuActive(hwnd) {
    info := Buffer(8+6*A_PtrSize+16,0), NumPut("UInt",info.Size,info)
    thread := DllCall("GetWindowThreadProcessId","Ptr",hwnd,"Ptr",0,"UInt")
    if DllCall("GetGUIThreadInfo","UInt",thread,"Ptr",info) && (NumGet(info,4,"UInt") & 0x1C) && NumGet(info,8+3*A_PtrSize,"Ptr")=hwnd
        return true
    try {
        f := FanWindow_Focus(hwnd)
        loop 8 {
            if RegExMatch(f.RoleText,"i)menu")
                return true
            f := f.Parent
        }
    }
    return false
}

FanWindow_MenuEscape(hwnd,all := false) {
    loop (all ? 6 : 1) {
        FanWindow_InputGuard(hwnd)
        if !FanWindow_MenuActive(hwnd)
            break
        FanVision_Trace("Keyboard","MenuReturn",Map("interaction",true,"hwnd",hwnd,"keys","Escape"))
        Send("{Escape}"), Sleep(100)
    }
    return Map("ok",true,"remaining_menu",FanWindow_MenuActive(hwnd),"note","Escape was sent only while the target exposed menu focus; no leaf command was invoked.")
}

FanWindow_MenuRows(container) {
    rows := []
    for element in container.Children {
        try {
            if !RegExMatch(element.RoleText,"i)menu item")
                continue
            loc := element.Location, state := element.State
            rows.Push(Map("label",element.Name,"order",rows.Length+1,"shortcut",element.KeyboardShortcut,
                "has_submenu",!!(state & 0x40000000),"enabled",!(state & 1),
                "bounds",Map("x",loc.x,"y",loc.y,"w",loc.w,"h",loc.h),"source_kind","observed_menu_accessibility"))
        }
    }
    return rows
}

FanWindow_MenuCatalog(hwnd,close := true) {
    FanWindow_InputGuard(hwnd)
    rows := []
    if menu := DllCall("GetMenu","Ptr",hwnd,"Ptr") {
        all := FanWindow_Menus(hwnd), index := 0
        loop Max(0,DllCall("GetMenuItemCount","Ptr",menu,"Int")) {
            text := Buffer(2048,0), rect := Buffer(16,0), position := A_Index-1
            DllCall("GetMenuStringW","Ptr",menu,"UInt",position,"Ptr",text,"Int",1024,"UInt",0x400)
            raw := StrGet(text,"UTF-16"), label := StrReplace(StrReplace(raw,"&&",Chr(1)),"&","")
            label := StrReplace(label,Chr(1),"&")
            if label=""
                continue
            bounds := Map()
            if DllCall("GetMenuItemRect","Ptr",hwnd,"Ptr",menu,"UInt",position,"Ptr",rect)
                bounds := Map("x",NumGet(rect,0,"Int"),"y",NumGet(rect,4,"Int"),"w",NumGet(rect,8,"Int")-NumGet(rect,0,"Int"),"h",NumGet(rect,12,"Int")-NumGet(rect,4,"Int"))
            state := DllCall("GetMenuState","Ptr",menu,"UInt",position,"UInt",0x400,"UInt")
            row := Map("label",label,"order",position+1,"bounds",bounds,"enabled",!(state & 3),
                "has_submenu",!!DllCall("GetSubMenu","Ptr",menu,"Int",position,"Ptr"),"source_kind","observed_Win32_menu")
            if RegExMatch(raw,"(?<!&)&([^&])",&m)
                row["mnemonic"] := m[1]
            rows.Push(row)
        }
    } else {
        if !FanWindow_MenuActive(hwnd) {
            FanVision_Trace("Keyboard","ExposeMenuBar",Map("interaction",true,"hwnd",hwnd,"keys","Alt"))
            Send("{Alt}"), Sleep(140)
        }
        try {
            focused := FanWindow_Focus(hwnd)
            loop 12 {
                if RegExMatch(focused.RoleText,"i)menu bar") {
                    if focused.Name="System"
                        break ; Window chrome is already recorded; this is not an app menu bar.
                    rows := FanWindow_MenuRows(focused)
                    break
                }
                focused := focused.Parent
            }
        }
    }
    if close
        FanWindow_MenuEscape(hwnd,true)
    return rows
}

FanWindow_CurrentMenuRows(hwnd) {
    try {
        f := FanWindow_Focus(hwnd)
        loop 12 {
            if RegExMatch(f.RoleText,"i)popup menu")
                return FanWindow_MenuRows(f)
            f := f.Parent
        }
    }
    ; Native popup menus can be separate owned windows.
    for popup in WinGetList("ahk_class #32768")
        if DllCall("IsWindowVisible","Ptr",popup) && FanVision_OwnedPopup(popup,hwnd)
            try {
                root := Acc.ElementFromHandle(popup), rows := FanWindow_MenuRows(root)
                if rows.Length
                    return rows
                for child in root.Children
                    if RegExMatch(child.RoleText,"i)popup menu")
                        return FanWindow_MenuRows(child)
            }
    return []
}

FanWindow_Menu(args) {
    hwnd := FanVision_Target(args), action := args.Get("action","catalog")
    FanWindow_InputGuard(hwnd)
    if action="return"
        return FanWindow_MenuEscape(hwnd,args.Get("all_menus",false))
    if action="catalog"
        return Map("ok",true,"menus",FanWindow_MenuCatalog(hwnd),"complete_interface",false)
    rows := action="open" ? FanWindow_MenuCatalog(hwnd,false) : FanWindow_CurrentMenuRows(hwnd)
    label := args.Get("label",""), chosen := 0
    for row in rows
        if row["label"]=label {
            chosen := row
            break
        }
    if !IsObject(chosen) || !chosen["enabled"] || !chosen["has_submenu"]
        return Map("ok",false,"error","Exact observed enabled submenu was not found; no command was clicked","menus",rows)
    box := chosen["bounds"]
    if box.Get("w",0)<=0 || box.Get("h",0)<=0
        return Map("ok",false,"error","The observed menu has no current visible bounds")
    x := box["x"]+box["w"]//2, y := box["y"]+box["h"]//2
    FanWindow_InputGuard(hwnd)
    hit := DllCall("WindowFromPoint","Int64",(y<<32)|(x & 0xFFFFFFFF),"Ptr")
    owner := hit ? DllCall("GetAncestor","Ptr",hit,"UInt",2,"Ptr") : 0
    if !owner || owner!=hwnd && !FanVision_OwnedPopup(owner,hwnd)
        throw TargetError("Observed menu is covered by another process; input skipped")
    FanVision_Trace("Mouse","OpenObservedMenu",Map("interaction",true,"hwnd",hwnd,"x",x,"y",y,"label",label,"bounds",box))
    oldCoord := A_CoordModeMouse
    try {
        CoordMode("Mouse","Screen"), Click(x,y), Sleep(180)
        current := FanWindow_CurrentMenuRows(hwnd)
        DeepActivity_Suspend()
        try out := FanVision_Inspect(Map("hwnd",hwnd,"limit",180,"include_image",true,"include_ocr",true,"grid",true))
        finally DeepActivity_Resume()
        out["menu_items"] := current, out["opened_menu"] := label, out["menu_catalog"] := rows
        out["opened_menu_path"] := args.Get("context_path",label)
        out["menu_open_verified"] := FanWindow_MenuActive(hwnd) && current.Length>0
        out["action_performed"] := true
        out["complete_interface"] := false
        return out
    } finally CoordMode("Mouse",oldCoord)
}

FanWindow_ProbeItem(args) {
    hwnd := FanVision_Target(args)
    FanWindow_InputGuard(hwnd)
    root := Acc.ElementFromHandle(hwnd), el := Acc.ElementFromPath(args["path"],root)
    if el.Name!=args["label"]
        throw TargetError("Navigation label/path changed; no input was issued")
    role := el.RoleText, state := el.State, back := 0
    if (state & 1) || (state & 0x20000000)
        throw TargetError("Unavailable/protected navigation element")
    if RegExMatch(role,"i)^page tab$") {
        for sibling in el.Parent.Children
            if sibling.State & 2 && sibling.Name!=el.Name {
                back := Map("path",root.GetPath(sibling),"label",sibling.Name)
                break
            }
        if !IsObject(back)
            throw TargetError("No observed selected sibling tab for a reversible probe")
    } else if RegExMatch(role,"i)outline item|tree.*item") && (state & 0x600) {
        back := Map("path",args["path"],"label",args["label"])
    } else
        throw ValueError("Probe accepts navigation tabs or expandable tree branches, not generic command buttons or leaf items")
    FanWindow_InputGuard(hwnd)
    FanVision_Trace("Accessibility","ProbeNavigation",Map("interaction",true,"hwnd",hwnd,"role",role,"label",el.Name,"path",args["path"]))
    if RegExMatch(role,"i)^page tab$")
        el.Select(2) ; TAKESELECTION; no generic button invocation.
    else
        el.DoDefaultAction() ; Only an observed expanded/collapsed tree branch.
    Sleep(160)
    DeepActivity_Suspend()
    try out := FanVision_Inspect(Map("hwnd",hwnd,"include_image",true,"include_ocr",true,"grid",true,"limit",180))
    finally DeepActivity_Resume()
    out["return_target"] := back, out["probed_label"] := args["label"]
    return out
}

FanWindow_DesktopPreview() {
    x := SysGet(76), y := SysGet(77), w := SysGet(78), h := SysGet(79)
    if w<1 || h<1 || w*h>40000000
        throw ValueError("Desktop preview is unavailable or exceeds the bounded capture budget")
    token := Gdip_Startup(), bitmap := 0, scaled := 0, graphics := 0
    try {
        bitmap := Gdip_BitmapFromScreen(x . "|" . y . "|" . w . "|" . h)
        scale := Min(720/w,320/h), sw := Max(1,Round(w*scale)), sh := Max(1,Round(h*scale))
        scaled := DaaGdip_CreateBitmap(sw,sh), graphics := DaaGdip_GraphicsFromImage(scaled)
        DaaGdip_DrawImage(graphics,bitmap,0,0,sw,sh,0,0,w,h)
        path := g_FanBridgeRoot . "\.runtime\captures\desktop-mini-" . A_NowUTC . "-" . A_TickCount . ".png"
        SplitPath(path,,&folder), DirCreate(folder)
        Gdip_SaveBitmapToFile(scaled,path)
        return Map("ok",true,"image_path",path,"desktop",Map("x",x,"y",y,"w",w,"h",h),
            "preview",Map("w",sw,"h",sh),"captured_at_utc",A_NowUTC,"local_only",true)
    } finally {
        if graphics
            DaaGdip_DeleteGraphics(graphics)
        if scaled
            Gdip_DisposeImage(scaled)
        if bitmap
            Gdip_DisposeImage(bitmap)
        Gdip_Shutdown(token)
    }
}
