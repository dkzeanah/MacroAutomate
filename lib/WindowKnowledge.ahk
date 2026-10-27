; Standard native window discovery. Enumerating menus never invokes commands.
#Include WindowExplore.ahk
FanWindow_Probe(args) {
    hwnd := FanVision_Target(args), region := FanVision_Region(args,hwnd), frame := FanVision_Frame(hwnd,region)
    frame["class"] := WinGetClass(hwnd)
    try frame["exe_path"] := WinGetProcessPath(hwnd)
    catalog := FanVision_Controls(hwnd,region,64), tabs := [], menus := FanWindow_Menus(hwnd), menuNames := ""
    for c in catalog["controls"]
        if RegExMatch(c["role"],"i)tab")
            tabs.Push(Map("name",c["name"],"selected",c.Get("selected",false),"focused",c["focused"],"path",c["accessibility_path"],"parent",c["parent_path"]))
    for item in menus
        menuNames .= item["parent"] . ":" . item["label"] . "|"
    url := "", unknownBrowser := false
    if RegExMatch(frame["exe"],"i)^(chrome|msedge|firefox)\.exe$") {
        try url := BrowserUrl_FromWindow(hwnd,frame["exe"])["url"]
        unknownBrowser := url=""
    }
    return Map("ok",true,"probe_only",true,"frame",FanVision_Finish(frame),"controls",catalog["controls"],"tabs",tabs,
        "accessibility",catalog,"menus",menus,"menu_signature",menuNames,"url",url,"browser_context_unknown",unknownBrowser,
        "note","Cheap live identity/schema/tab probe. Coverage is bounded; historical coordinates are not current input targets.")
}

FanWindow_Menus(hwnd) {
    result := []
    if menu := DllCall("GetMenu","Ptr",hwnd,"Ptr")
        FanWindow_MenuWalk(menu,"",result,Map())
    return result
}

FanWindow_MenuWalk(menu,parent,result,seen,depth := 0) {
    if !menu || seen.Has(menu) || depth>12 || result.Length>=500
        return
    seen[menu] := true, count := DllCall("GetMenuItemCount","Ptr",menu,"Int")
    loop Max(0,count) {
        index := A_Index-1, textBuf := Buffer(4096,0)
        DllCall("GetMenuStringW","Ptr",menu,"UInt",index,"Ptr",textBuf,"Int",2048,"UInt",0x400)
        raw := StrGet(textBuf,"UTF-16"), parts := StrSplit(raw,"`t")
        label := StrReplace(StrReplace(StrReplace(parts[1],"&&",Chr(1)),"&",""),Chr(1),"&")
        state := DllCall("GetMenuState","Ptr",menu,"UInt",index,"UInt",0x400,"UInt")
        if label!="" {
            item := Map("label",label,"parent",parent,"shortcut",parts.Length>1 ? parts[2] : "",
                "enabled",!(state & 3),"checked",!!(state & 8),"source_kind","observed_Win32_menu",
                "command_id",DllCall("GetMenuItemID","Ptr",menu,"Int",index,"UInt"))
            if RegExMatch(parts[1],"(?<!&)&([^&])",&mnemonic)
                item["mnemonic"] := mnemonic[1]
            result.Push(item)
        }
        if result.Length>=500
            break
        if child := DllCall("GetSubMenu","Ptr",menu,"Int",index,"Ptr")
            FanWindow_MenuWalk(child,parent="" ? label : parent . " > " . label,result,seen,depth+1)
    }
}

FanWindow_Survey(args) {
    hwnd := FanVision_Target(args), probe := FanWindow_Probe(Map("hwnd",hwnd))
    maximize := args.Get("maximize",false), fullscreen := args.Get("fullscreen",false), menu := args.Get("activate_menu",false)
    if (maximize || fullscreen || menu) && WinExist("A")!=hwnd
        throw TargetError("Exploratory layout/menu input requires this exact foreground window. Activate and verify it first.")
    if fullscreen && !(probe["frame"]["exe"]="explorer.exe" && RegExMatch(probe["frame"]["class"],"i)^(CabinetWClass|ExploreWClass)$"))
        throw ValueError("F11 full-screen exploration is supported only for File Explorer; use maximize for other applications.")
    if maximize && fullscreen
        throw ValueError("Choose maximize or fullscreen, not both")
    placement := Buffer(44,0), NumPut("UInt",44,placement), changed := false, toggled := false, menuOpened := false
    if !DllCall("GetWindowPlacement","Ptr",hwnd,"Ptr",placement)
        throw OSError()
    gaps := [], out := 0, menuPerformed := false
    try {
        if maximize && WinGetMinMax(hwnd)!=1
            WinMaximize(hwnd), changed := true
        if fullscreen && (WinGetStyle(hwnd) & 0xC00000)
            Send("{F11}"), toggled := true, changed := true
        if changed
            Sleep(180)
        out := FanVision_Inspect(Map("hwnd",hwnd,"limit",500,"_page",true,"include_image",true,"include_ocr",true,"grid",true))
        out["probe"] := probe, out["menus"] := FanWindow_Menus(hwnd), out["tabs"] := []
        for c in out["controls"]
            if RegExMatch(c["role"],"i)tab")
                out["tabs"].Push(c)
        if menu && WinExist("A")!=hwnd
            gaps.Push("Foreground changed during observation. ALT exploration was skipped; no menu key sent.")
        if menu && WinExist("A")=hwnd {
            FanVision_Trace("Keyboard","SendKeyChord",Map("keys","Alt","purpose","observe menu hints"))
            Send("{Alt}"), menuOpened := true, menuPerformed := true, Sleep(140)
            menus := FanWindow_Menus(hwnd)
            if menus.Length
                out["menus"] := menus
            extra := FanVision_Controls(hwnd,FanVision_Region(Map(),hwnd),500,true), out["menu_controls"] := []
            for c in extra["controls"]
                if RegExMatch(c["role"],"i)menu")
                    out["menu_controls"].Push(c)
        }
        if !out["menus"].Length
            gaps.Push("No Win32 menu exposed. Custom menus/ribbons need app-specific incremental inspection; ALT reveals only currently exposed hints.")
        if out["accessibility"]["truncated"]
            gaps.Push("Accessibility traversal reached a limit. Unseen, offscreen, collapsed and other-tab controls remain incompletely covered.")
        gaps.Push("Graphics without accessible semantics need OCR/FindText or labelled vision interpretation. Geometric zones do not establish meaning.")
        out["coverage"] := Map("gaps",gaps,"control_limit",500,"native_menu_limit",500,"menus_truncated",out["menus"].Length>=500,
            "active_menu_requested",menu,"active_menu_probe",menuPerformed,"maximized_probe",maximize,"fullscreen_probe",fullscreen,"complete_interface",false)
        return out
    } finally {
        if menuOpened && WinExist("A")=hwnd
            Send("{Escape}")
        if toggled && WinExist("A")=hwnd
            Send("{F11}"), Sleep(100)
        else if toggled
            gaps.Push("Foreground changed: F11 restoration was skipped to avoid input in another window. Explorer full-screen state needs manual verification.")
        if changed && WinExist(hwnd)
            DllCall("SetWindowPlacement","Ptr",hwnd,"Ptr",placement)
    }
}

FanWindow_Shortcut(args) {
    hwnd := FanVision_Target(args), before := FanWindow_Probe(Map("hwnd",hwnd)), name := args["shortcut"]
    explorer := before["frame"]["exe"]="explorer.exe" && RegExMatch(before["frame"]["class"],"i)^(CabinetWClass|ExploreWClass)$")
    code := RegExMatch(before["frame"]["exe"],"i)^code(?: - insiders)?\.exe$")
    keys := explorer ? Map("address_bar","!d","address_bar_ctrl","^l","search","^f","next_tab","^{Tab}","previous_tab","^+{Tab}","menu_bar","{Alt}")
        : code ? Map("command_palette","^+p","quick_open","^p","menu_bar","{Alt}") : Map()
    if explorer && RegExMatch(name,"^tab_([1-9])$",&tab)
        keys[name] := "^" . tab[1]
    if !keys.Has(name)
        throw ValueError("No documented navigation binding for this app/context; inspect its exposed shortcut metadata first")
    if WinExist("A")!=hwnd
        throw TargetError("The exact target must be foreground before sending a navigation shortcut")
    DeepActivity_Resume()
    try {
        DeepActivity_Box(before["frame"]["region"]), Sleep(80)
        if WinExist("A")!=hwnd
            throw TargetError("Foreground changed; no shortcut sent")
        FanVision_Trace("Keyboard","SendKeyChord",Map("shortcut",name,"keys",keys[name]))
        Send(keys[name])
    } finally DeepActivity_Suspend()
    Sleep(120), after := FanWindow_Probe(Map("hwnd",hwnd)), verified := false
    if name="address_bar" || name="address_bar_ctrl" {
        for c in after["controls"]
            if c["focused"] && RegExMatch(c["name"],"i)address") && RegExMatch(c["role"],"i)edit|text|combo")
                verified := true
    } else if name="next_tab" || name="previous_tab" || SubStr(name,1,4)="tab_" {
        first := "", second := ""
        for t in before["tabs"]
            if t["selected"]
                first .= t["name"] . "|"
        for t in after["tabs"]
            if t["selected"]
                second .= t["name"] . "|"
        verified := first!="" && second!="" && first!=second
    }
    return Map("ok",true,"action_performed",true,"verified",verified,"shortcut",name,"keys",keys[name],"observation",after,
        "note",verified ? "Live postcondition observed" : "Shortcut sent; semantic effect remains unverified. Do not automatically repeat uncertain input.")
}
