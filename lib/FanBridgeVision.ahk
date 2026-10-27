; Native perception tools for the DeepSeek bridge. Loaded by MacroAutomator.ahk.
; Dependencies: the existing FindText, OCR, Acc and fan/Core/_Gdip libraries.
; Optional DeepSeek feedback is hidden for the full perception operation.
; Overlays are drawn only after native geometry and image evidence are complete.
#Include DeepSeekActivity.ahk
#Include FanPageLearner.ahk
#Include BoundWindow.ahk
global g_FanVisionObserver := 0

FanVision_Trace(family,method,detail := 0) {
    global g_FanBridgeTask
    if IsObject(g_FanVisionObserver) {
        if IsObject(detail) && detail.Get("interaction",false)
        {
            if detail.Get("hwnd",0) && IsSet(g_FanBridgeTask) && g_FanBridgeTask!="" {
                prepare := "FanAPI_PrepareWindow"
                %prepare%(detail["hwnd"])
            }
            return g_FanVisionObserver.Call(family,method,"start",detail)
        }
        try g_FanVisionObserver.Call(family,method,"start",IsObject(detail) ? detail : Map())
    }
}

FanVision_Capabilities() {
    return Map("coordinate_system", "physical_screen_pixels", "read_only_focus", true,
        "tools", ["fan_window_inspect", "fan_ocr", "fan_pattern_list", "fan_pattern_search", "fan_pattern_capture", "fan_page_learn", "fan_page_probe", "fan_page_list", "fan_page_get", "fan_page_resolve", "fan_page_image"],
        "description", "Inspect a specific window by HWND (0 uses foreground, or last Chrome base when Fan is foreground). "
            . "Accessible controls have observed geometry, enabled/protected states and numeric IDs. OCR returns observed line/word bounds. "
            . "Images can include numbered control boxes and a coordinate grid baked into the PNG. "
            . "Live screen highlights acknowledge observed results after capture; feedback is hidden during perception. "
            . "Regions are {x,y,w,h} in physical screen pixels, including negative monitor coordinates. "
            . "Capture requires an explicit region and saves a reusable FindText pattern into Fan's normal Patterns database. "
            . "Search requires a saved pattern name or FindText text, supports explicit err1/err0, and returns observed match bounds/centers. "
            . "If image/OCR is unavailable because another window covers the region, explicitly activate the target and recapture. "
            . "Treat frame IDs and coordinates as observations at capture time; recapture after navigation, scrolling or layout changes.")
}

FanVision_Dispatch(name, args) {
    if !(args is Map)
        throw TypeError("Perception arguments must be an object")
    dpi := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    hidden := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    DeepActivity_Suspend()
    try {
        switch name {
            case "fan_window_inspect": result := FanVision_Inspect(args)
            case "fan_ocr": result := FanVision_OCRTool(args)
            case "fan_pattern_list": result := FanVision_PatternList(args)
            case "fan_pattern_search": result := FanVision_PatternSearch(args)
            case "fan_pattern_capture": result := FanVision_PatternCapture(args)
            case "fan_page_learn": result := FanPage_Learn(args)
            case "fan_page_probe": result := FanPage_Probe(args)
            case "fan_page_resolve": result := FanPage_Resolve(args)
            case "fan_page_image": result := FanPage_Image(args)
            default: throw ValueError("Unknown perception tool: " . name)
        }
        try DeepActivity_Result(name, result)
        return result
    } finally {
        DeepActivity_Resume()
        DetectHiddenWindows(hidden)
        if dpi
            DllCall("SetThreadDpiAwarenessContext", "Ptr", dpi, "Ptr")
    }
}

FanVision_Arg(args, name, fallback := "") => args.Has(name) ? args[name] : fallback

FanVision_FT() {
    ; A separate instance of the project's FindText class keeps screenshot
    ; caching and any user-selected BindWindow state out of bridge captures.
    static native := FindTextClass()
    return native
}

FanVision_Int(args, name, fallback, lo, hi) {
    n := FanVision_Arg(args, name, fallback)
    if !IsInteger(n) || n < lo || n > hi
        throw ValueError(name . " must be an integer from " . lo . " to " . hi)
    return Integer(n)
}

FanVision_Target(args) {
    global MainGui, g_StudyPin, g_FanBridgeTask, g_FanBridgeTarget
    hwnd := FanVision_Int(args, "hwnd", 0, 0, 0x7FFFFFFFFFFFFFFF)
    if !hwnd {
        if IsSet(g_FanBridgeTask) && g_FanBridgeTask!="" && IsSet(g_FanBridgeTarget) && g_FanBridgeTarget.Get("hwnd",0)
            hwnd := g_FanBridgeTarget["hwnd"]
    }
    if !hwnd {
        hwnd := WinExist("A")
        own := hwnd && WinGetPID("ahk_id " . hwnd) = DllCall("GetCurrentProcessId", "UInt")
        if IsSet(MainGui) && IsObject(MainGui)
            own := own || hwnd = MainGui.Hwnd
        if own && IsSet(g_StudyPin) && g_StudyPin is Map && g_StudyPin.Has("hwnd")
            && g_StudyPin["hwnd"] && WinExist("ahk_id " . g_StudyPin["hwnd"])
            hwnd := g_StudyPin["hwnd"]
    }
    if !hwnd || !DllCall("IsWindow", "Ptr", hwnd)
        throw TargetError("Target window no longer exists; inspect the window list and select its HWND")
    if IsSet(g_FanBridgeTask) && g_FanBridgeTask!="" {
        prepare := "FanAPI_PrepareWindow"
        %prepare%(hwnd)
    }
    return hwnd
}

FanVision_WindowRect(hwnd) {
    rect := Buffer(16, 0)
    if !DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect)
        throw OSError()
    x := NumGet(rect, 0, "Int"), y := NumGet(rect, 4, "Int")
    return Map("x", x, "y", y, "w", NumGet(rect, 8, "Int")-x, "h", NumGet(rect, 12, "Int")-y)
}

FanVision_Contains(outer, inner) => inner["w"] > 0 && inner["h"] > 0
    && inner["x"] >= outer["x"] && inner["y"] >= outer["y"]
    && inner["x"]+inner["w"] <= outer["x"]+outer["w"]
    && inner["y"]+inner["h"] <= outer["y"]+outer["h"]

FanVision_Intersects(a, b) => a["x"] < b["x"]+b["w"] && a["x"]+a["w"] > b["x"]
    && a["y"] < b["y"]+b["h"] && a["y"]+a["h"] > b["y"]

FanVision_Region(args, hwnd, explicit := false) {
    if DllCall("IsIconic","Ptr",hwnd)
        throw TargetError("Target window is minimized. Activate/restore this exact HWND before inspecting it; repeating the same probe cannot fix its geometry.")
    win := FanVision_WindowRect(hwnd)
    if explicit && !args.Has("region")
        throw ValueError("Supply an explicit region {x,y,w,h}; pattern capture never captures the whole desktop implicitly")
    ; Maximized Chrome has invisible resize borders outside the desktop. Capture
    ; its complete visible rectangle rather than rejecting those off-screen pixels.
    if args.Has("region")
        region := args["region"]
    else {
        visible := win, dwm := Buffer(16)
        if !DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", dwm, "UInt", 16)
            visible := Map("x", NumGet(dwm,0,"Int"), "y", NumGet(dwm,4,"Int"),
                "w", NumGet(dwm,8,"Int")-NumGet(dwm,0,"Int"), "h", NumGet(dwm,12,"Int")-NumGet(dwm,4,"Int"))
        x := Max(visible["x"], SysGet(76)), y := Max(visible["y"], SysGet(77))
        region := Map("x", x, "y", y, "w", Max(0, Min(visible["x"]+visible["w"], SysGet(76)+SysGet(78))-x),
            "h", Max(0, Min(visible["y"]+visible["h"], SysGet(77)+SysGet(79))-y))
    }
    if !(region is Map)
        throw TypeError("region must be an object with x, y, w, h")
    if !args.Has("region") && (region["w"]<=0 || region["h"]<=0)
        throw TargetError("Target has no visible rectangle on the current desktop. Select and restore an on-screen window before retrying.")
    out := Map("x", FanVision_Int(region, "x", 0, -100000, 100000),
        "y", FanVision_Int(region, "y", 0, -100000, 100000),
        "w", FanVision_Int(region, "w", 0, 1, 8192),
        "h", FanVision_Int(region, "h", 0, 1, 8192))
    if out["w"]*out["h"] > 12000000
        throw ValueError("Region is too large; use a crop smaller than 12 million pixels")
    if !FanVision_Contains(win, out)
        throw ValueError("Region must lie inside the selected window's physical screen rectangle")
    return out
}

FanVision_OwnedPopup(popup,hwnd) {
    owner := popup
    loop 8 {
        owner := DllCall("GetWindow","Ptr",owner,"UInt",4,"Ptr")
        if owner=hwnd
            return true
        if !owner
            break
    }
    try {
        if WinGetClass(popup)="#32768" && WinGetPID(popup)=WinGetPID(hwnd) {
            info := Buffer(8+6*A_PtrSize+16,0), NumPut("UInt",info.Size,info)
            thread := DllCall("GetWindowThreadProcessId","Ptr",hwnd,"Ptr",0,"UInt")
            if DllCall("GetGUIThreadInfo","UInt",thread,"Ptr",info)
                return NumGet(info,8+3*A_PtrSize,"Ptr")=hwnd
        }
    }
    return false
}

FanVision_Visibility(hwnd, region) {
    if !DllCall("IsWindowVisible", "Ptr", hwnd)
        return Map("ok", false, "reason", "Window is hidden")
    if DllCall("IsIconic", "Ptr", hwnd)
        return Map("ok", false, "reason", "Window is minimized")
    desktop := Map("x", SysGet(76), "y", SysGet(77), "w", SysGet(78), "h", SysGet(79))
    if !FanVision_Contains(desktop, region)
        return Map("ok", false, "reason", "Region extends outside the visible monitor desktop")
    ; Check windows above the target as well as sample points. Snipping Tool's
    ; translucent selection surface can be missed by WindowFromPoint sampling.
    targetPID := WinGetPID("ahk_id " . hwnd)
    for other in WinGetList() {
        if other = hwnd
            break
        if !DllCall("IsWindowVisible", "Ptr", other) || DllCall("IsIconic", "Ptr", other)
            continue
        cloaked := 0, affinity := 0
        DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", other, "UInt", 14, "UInt*", &cloaked, "UInt", 4)
        if cloaked
            continue
        DllCall("GetWindowDisplayAffinity", "Ptr", other, "UInt*", &affinity)
        if affinity = 0x11
            continue
        try {
            if WinGetPID("ahk_id " . other) = targetPID
                continue
            box := FanVision_WindowRect(other)
            if FanVision_Intersects(box, region)
                return Map("ok", false, "reason", "An overlapping window or screen-snipping surface covers the capture; uncover Chrome and recapture",
                    "occluding_window", other, "occluding_title", WinGetTitle("ahk_id " . other))
        }
    }
    ; Sampling detects obvious occlusion without activating the target. This is
    ; evidence about the sampled points, not a guarantee of every pixel's owner.
    points := []
    Loop 3 {
        iy := A_Index-1
        Loop 3 {
            ix := A_Index-1
            x := region["x"]+Min(8, region["w"]//2)+Round(ix*Max(0,region["w"]-17)/2)
            y := region["y"]+Min(8, region["h"]//2)+Round(iy*Max(0,region["h"]-17)/2)
            hit := DllCall("WindowFromPoint", "Int64", (y << 32) | (x & 0xFFFFFFFF), "Ptr")
            root := DllCall("GetAncestor", "Ptr", hit, "UInt", 2, "Ptr")
            points.Push(Map("x", x, "y", y, "window", root))
            if root != hwnd && !FanVision_OwnedPopup(root,hwnd) {
                cloaked := 0, affinity := 0
                DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", root, "UInt", 14, "UInt*", &cloaked, "UInt", 4)
                DllCall("GetWindowDisplayAffinity", "Ptr", root, "UInt*", &affinity)
                return Map("ok", false, "reason", "Another window covers a sampled point; activate the target explicitly, then recapture", "points", points,
                    "occluding_window", root, "occluding_title", WinGetTitle("ahk_id " . root),
                    "occluding_class", WinGetClass("ahk_id " . root), "occluding_visible", !!DllCall("IsWindowVisible", "Ptr", root),
                    "occluding_cloaked", cloaked, "occluding_affinity", affinity)
            }
        }
    }
    return Map("ok", true, "method", "nine_point_window_ownership_sample", "points", points)
}

FanVision_Frame(hwnd, region) {
    static seq := 0
    seq += 1
    return Map("frame_id", "fan_" . A_NowUTC . "_" . A_TickCount . "_" . seq,
        "hwnd", hwnd, "title", WinGetTitle("ahk_id " . hwnd),
        "pid", WinGetPID("ahk_id " . hwnd), "exe", WinGetProcessName("ahk_id " . hwnd),
        "window_rect", FanVision_WindowRect(hwnd), "region", region,
        "captured_at_utc", FormatTime(A_NowUTC, "yyyy-MM-dd'T'HH:mm:ss'Z'"),
        "captured_tick", A_TickCount, "coordinates", "physical_screen_pixels",
        "foreground", WinExist("A") = hwnd, "visibility", FanVision_Visibility(hwnd, region),
        "geometry_stable", false, "content_stable", false,
        "note", "Accessible and OCR geometry is observed. Semantic interpretations are inferred. Recapture before acting if the window or content changes.")
}

FanVision_Hash(region, capture := true) {
    ; The bundled GetPicHash spells rtlComputeCrc32 with a lower-case r, which
    ; fails on Windows' case-sensitive DLL exports. Reuse its captured bitmap
    ; and the correctly named Windows CRC function for a bounded fingerprint.
    x := region["x"], y := region["y"], w := region["w"], h := region["h"]
    bits := FanVision_FT().GetBitsFromScreen(&x, &y, &w, &h, capture, &zx, &zy)
    if w < 1 || h < 1 || !bits.Scan0
        throw Error("Frame pixels unavailable")
    scan := bits.Scan0+(y-zy)*bits.Stride+(x-zx)*4, hash := 0
    Loop h {
        hash := (hash*31+DllCall("ntdll\RtlComputeCrc32", "UInt", 0, "Ptr", scan,
            "UInt", w*4, "UInt")) & 0xFFFFFFFF
        scan += bits.Stride
    }
    return hash
}

FanVision_Finish(frame, initialHash := "") {
    hwnd := frame["hwnd"]
    if !DllCall("IsWindow", "Ptr", hwnd)
        return frame
    r := FanVision_WindowRect(hwnd), old := frame["window_rect"]
    frame["geometry_stable"] := frame["title"] = WinGetTitle("ahk_id " . hwnd)
        && r["x"] = old["x"] && r["y"] = old["y"] && r["w"] = old["w"] && r["h"] = old["h"]
    if initialHash != "" && frame["visibility"]["ok"] {
        frame["content_hash"] := initialHash
        frame["content_stable"] := initialHash = FanVision_Hash(frame["region"])
    }
    frame["finished_tick"] := A_TickCount
    frame["visibility_after"] := FanVision_Visibility(hwnd, frame["region"])
    return frame
}

FanVision_Controls(hwnd, region, limit := 200, thorough := false) {
    FanVision_Trace("Accessibility","Acc.ElementFromHandle",Map("hwnd",hwnd,"region",region,"limit",limit))
    out := [], queue := [], visited := 0, cursor := 1, started := A_TickCount, treeLimited := false
    try queue.Push(Map("el", Acc.ElementFromHandle(hwnd), "path", "", "depth", 0))
    catch as err
        return Map("controls", out, "truncated", false, "error", err.Message, "method", "MSAA")
    maxNodes := thorough ? 15000 : 4000, budget := thorough ? 15000 : 6000
    while cursor <= queue.Length && visited < maxNodes && A_TickCount-started < budget {
        item := queue[cursor++], el := item["el"], visited += 1
        try {
            loc := el.Location, state := el.State, role := el.RoleText
            bounds := Map("x", Round(loc.x), "y", Round(loc.y), "w", Round(loc.w), "h", Round(loc.h))
            if loc.w > 0 && loc.h > 0 && !(state & (0x8000|0x10000)) && FanVision_Intersects(bounds, region) {
                name := "", value := "", stateText := "", action := "", description := "", shortcut := ""
                try name := SubStr(el.Name, 1, 2000)
                try stateText := el.StateText
                protected := !!(state & 0x20000000) || InStr(StrLower(stateText), "protected") != 0
                if !protected
                    try value := SubStr(el.Value, 1, 4000)
                try action := SubStr(el.DefaultAction, 1, 200)
                try description := SubStr(el.Description, 1, 1000)
                try shortcut := SubStr(el.KeyboardShortcut, 1, 100)
                ; Keep actionable controls and descriptive text, not every empty container.
                if name != "" || value != "" || RegExMatch(role, "i)button|check|radio|edit|link|combo|list|tab|menu|slider|separator")
                    || (thorough && RegExMatch(role, "i)graphic|image|document|group|pane|toolbar|table|section")) {
                    out.Push(Map("id", out.Length+1, "role", role, "name", name, "value", value,
                        "bounds", bounds, "center", Map("x", bounds["x"]+bounds["w"]//2, "y", bounds["y"]+bounds["h"]//2),
                        "enabled", !(state & 1), "protected", protected, "checked", !!(state & 0x10), "selected", !!(state & 2),
                        "focused", !!(state & 4), "state", state, "state_text", stateText,
                        "default_action", action, "description", description, "shortcut", shortcut,
                        "parent_path", RegExReplace(item["path"], "(^|\.)[^.]+$"),
                        "href", RegExMatch(role, "i)link") && RegExMatch(value, "i)^(https?://|mailto:|tel:)") ? value : "",
                        "accessibility_path", item["path"], "source", "observed_MSAA_geometry"))
                    ; Acknowledge elements as they are enumerated, then hide all
                    ; feedback before any OCR, hashes or screen images are read.
                    if !g_DeepActivity["suspended"] && out.Length <= 24 && !protected && !(state & 1)
                        try DeepActivity_Box(bounds)
                    if out.Length >= limit
                        break
                }
            }
            if item["depth"] < (thorough ? 64 : 32) {
                children := el.Children
                for index, child in children {
                    if queue.Length >= maxNodes {
                        treeLimited := true
                        break
                    }
                    queue.Push(Map("el", child, "path", item["path"] . (item["path"] = "" ? "" : ".") . index, "depth", item["depth"]+1))
                }
            }
        }
    }
    return Map("controls", out, "truncated", treeLimited || cursor <= queue.Length || out.Length >= limit,
        "visited", visited, "elapsed_ms", A_TickCount-started, "method", "MSAA", "error", "",
        "node_limit", maxNodes, "time_budget_ms", budget)
}

FanVision_Zones(region, controls := unset) {
    FanVision_Trace("Layout","FanVision_Zones",Map("phase","before_text_recognition","region",region))
    zones := [], sections := []
    loop 3 {
        row := A_Index-1
        loop 3 {
            col := A_Index-1, x := region["x"]+Floor(region["w"]*col/3), y := region["y"]+Floor(region["h"]*row/3)
            zones.Push(Map("id",["top","middle","bottom"][row+1] . "-" . ["left","center","right"][col+1],
                "bounds",Map("x",x,"y",y,"w",region["x"]+Floor(region["w"]*(col+1)/3)-x,"h",region["y"]+Floor(region["h"]*(row+1)/3)-y),
                "source_kind","geometric_partition","reading_order",row*3+col+1))
        }
    }
    if IsSet(controls)
        for c in controls {
            if sections.Length>=60
                break
            if c.Get("name","")!="" && RegExMatch(c.Get("role",""),"i)pane|group|toolbar|document") && c.Has("bounds")
                sections.Push(Map("id","section:" . c.Get("accessibility_path",c.Get("id","")),"label",c["name"],"parent",c.Get("parent_path",""),
                    "bounds",c["bounds"],"source_kind","observed_accessibility"))
        }
    return Map("zones",zones,"sections",sections,"created_before_ocr",true,"coordinates","physical_screen_pixels",
        "reading_order","Grid metadata is row-major. Text groups use their top-left bounds, then lines top-to-bottom/left-to-right. This is a spatial convention, not inferred document semantics.")
}

FanVision_ZoneMatch(bounds, layout) {
    cx := bounds["x"]+bounds["w"]/2, cy := bounds["y"]+bounds["h"]/2, zoneId := "unassigned", sectionId := "", area := 1.0e30, crossing := false
    for z in layout["zones"] {
        b := z["bounds"]
        if cx>=b["x"] && cx<b["x"]+b["w"] && cy>=b["y"] && cy<b["y"]+b["h"] {
            zoneId := z["id"], crossing := !FanVision_Contains(b,bounds)
            break
        }
    }
    for section in layout["sections"] {
        b := section["bounds"], size := b["w"]*b["h"]
        if size>0 && size<area && cx>=b["x"] && cx<b["x"]+b["w"] && cy>=b["y"] && cy<b["y"]+b["h"]
            sectionId := section["id"], area := size
    }
    return Map("zone_id",zoneId,"section_id",sectionId,"crosses_zone_boundary",crossing)
}

FanVision_GroupOCR(out,layout) {
    groups := Map(), ordered := [], combined := ""
    for line in out["lines"] {
        mapping := FanVision_ZoneMatch(line["bounds"],layout)
        for k,v in mapping
            line[k] := v
        key := mapping["section_id"]!="" ? mapping["section_id"] : mapping["zone_id"]
        if !groups.Has(key) {
            groups[key] := Map("id",key,"zone_id",mapping["zone_id"],"section_id",mapping["section_id"],"lines",[],"text","","bounds",line["bounds"])
            ordered.Push(groups[key])
        }
        old := groups[key]["bounds"], b := line["bounds"]
        groups[key]["bounds"] := Map("x",Min(old["x"],b["x"]),"y",Min(old["y"],b["y"]),
            "w",Max(old["x"]+old["w"],b["x"]+b["w"])-Min(old["x"],b["x"]),"h",Max(old["y"]+old["h"],b["y"]+b["h"])-Min(old["y"],b["y"]))
        groups[key]["lines"].Push(line)
    }
    FanVision_SpatialOrder(ordered)
    for group in ordered {
        FanVision_SpatialOrder(group["lines"])
        for line in group["lines"]
            group["text"] .= (group["text"]="" ? "" : "`n") . line["text"]
        combined .= (combined="" ? "" : "`n`n") . group["text"]
    }
    for word in out["words"]
        for k,v in FanVision_ZoneMatch(word["bounds"],layout)
            word[k] := v
    out["raw_text"] := out["text"], out["text"] := combined, out["groups"] := ordered, out["layout"] := layout
    out["grouping_note"] := "Zones/accessible sections established before recognition. Each intact OCR line belongs to its smallest named section or center zone; boundary-crossing lines are flagged, never cropped or duplicated. Raw recognizer order retained separately. Spatial order is not semantic proof."
    return out
}

FanVision_SpatialOrder(items) {
    ; Stable insertion sort with binary position search; bounded OCR output.
    loop Max(0,items.Length-1) {
        index := A_Index+1, item := items[index], lo := 1, hi := index
        while lo<hi {
            mid := (lo+hi)//2, a := items[mid]["bounds"], b := item["bounds"]
            if a["y"]<b["y"] || (a["y"]=b["y"] && a["x"]<=b["x"])
                lo := mid+1
            else
                hi := mid
        }
        if lo<index
            items.RemoveAt(index), items.InsertAt(lo,item)
    }
}

FanVision_ReadOCR(region, args) {
    layout := args.Get("_zones",0)
    if !IsObject(layout)
        layout := FanVision_Zones(region)
    FanVision_Trace("OCR",args.Get("_image_path","")!="" ? "OCR.FromFile" : "OCR.FromRect",Map("region",region))
    options := {scale: Min(1.5, OCR.MaxImageDimension/Max(region["w"], region["h"]))}
    lang := FanVision_Arg(args, "lang", "")
    if lang != ""
        options.lang := lang
    fromImage := args.Get("_image_path", "") != ""
    result := fromImage ? OCR.FromFile(args["_image_path"], options) : OCR.FromRect(region["x"], region["y"], region["w"], region["h"], options)
    out := Map("text", SubStr(result.Text, 1, 50000), "lines", [], "words", [], "source", "observed_Windows_OCR",
        "coordinates", "physical_screen_pixels", "truncated", false)
    for , line in result.Lines {
        box := line.BoundingRect
        out["lines"].Push(Map("text", line.Text, "bounds", Map("x", box.x+(fromImage ? region["x"] : 0), "y", box.y+(fromImage ? region["y"] : 0), "w", box.w, "h", box.h)))
        for , word in line.Words {
            box := word.BoundingRect
            bx := box.x+(fromImage ? region["x"] : 0), by := box.y+(fromImage ? region["y"] : 0)
            out["words"].Push(Map("text", word.Text, "bounds", Map("x", bx, "y", by, "w", box.w, "h", box.h),
                "center", Map("x", bx+box.w//2, "y", by+box.h//2)))
            if out["words"].Length >= 2000 {
                out["truncated"] := true
                return FanVision_GroupOCR(out,layout)
            }
        }
    }
    return FanVision_GroupOCR(out,layout)
}

FanVision_Inspect(args) {
    hwnd := FanVision_Target(args), region := FanVision_Region(args, hwnd), frame := FanVision_Frame(hwnd, region)
    thorough := args.Get("_page", false)
    limit := FanVision_Int(args, "limit", 200, 1, thorough ? 1500 : 500)
    if frame["visibility"]["ok"] {
        DeepActivity_Resume()
        DeepActivity_Set(true, "Discovering elements · MSAA", 30000)
        DeepActivity_Box(region, "FFB000")
    }
    try catalog := FanVision_Controls(hwnd, region, limit, thorough)
    finally DeepActivity_Suspend()
    out := Map("ok", true, "frame", frame, "controls", catalog["controls"], "accessibility", catalog,
        "image_path", "", "annotated_image_path", "", "legend", [], "warnings", [])
    out["zones"] := FanVision_Zones(FanVision_Region(Map(),hwnd),catalog["controls"]), args := args.Clone(), args["_zones"] := out["zones"]
    initial := ""
    if frame["visibility"]["ok"] {
        initial := FanVision_Hash(region)
        if FanVision_Arg(args, "include_ocr", true) {
            try out["ocr"] := FanVision_ReadOCR(region, args)
            catch as err
                out["warnings"].Push("OCR unavailable: " . err.Message)
        }
        if FanVision_Arg(args, "include_image", true) {
            try FanVision_SaveImage(out, FanVision_Arg(args, "grid", true))
            catch as err
                out["warnings"].Push("Image unavailable: " . err.Message)
        }
    } else
        out["warnings"].Push(frame["visibility"]["reason"])
    FanVision_Finish(frame, initial)
    ; The top-level controls array is the catalog; do not serialize it twice.
    out["accessibility"].Delete("controls")
    return out
}

FanVision_OCRTool(args) {
    hwnd := FanVision_Target(args), region := FanVision_Region(args, hwnd), frame := FanVision_Frame(hwnd, region)
    if !frame["visibility"]["ok"]
        return Map("ok", false, "error", frame["visibility"]["reason"], "frame", FanVision_Finish(frame))
    layout := FanVision_Zones(FanVision_Region(Map(),hwnd)), args := args.Clone(), args["_zones"] := layout
    initial := FanVision_Hash(region)
    out := Map("ok", true, "frame", frame, "zones",layout,"ocr", FanVision_ReadOCR(region, args), "controls", [],
        "image_path", "", "annotated_image_path", "", "legend", [])
    if FanVision_Arg(args, "include_image", false)
        FanVision_SaveImage(out, FanVision_Arg(args, "grid", true))
    FanVision_Finish(frame, initial)
    return out
}

FanVision_CaptureRoot() {
    SplitPath(Photo_TempPath(),, &path)
    return path
}

FanVision_SaveImage(out, grid := true) {
    FanVision_Trace("Images","Gdip_BitmapFromScreen",Map("frame_id",out["frame"]["frame_id"],"region",out["frame"]["region"]))
    region := out["frame"]["region"], dir := FanVision_CaptureRoot()
    bitmap := Gdip_BitmapFromScreen(region["x"] . "|" . region["y"] . "|" . region["w"] . "|" . region["h"])
    if !bitmap
        throw Error("Screen capture failed")
    try {
        raw := dir . "\" . out["frame"]["frame_id"] . ".png"
        if Gdip_SaveBitmapToFile(bitmap, raw) != 0
            throw Error("PNG save failed")
        out["image_path"] := raw
        out["photo_ref"] := Photo_Store(raw, "Bridge frame " . out["frame"]["frame_id"])
        if grid || out["controls"].Length {
            FanVision_Annotate(bitmap, region, out["controls"], out["legend"], grid)
            annotated := dir . "\" . out["frame"]["frame_id"] . "_legend.png"
            if Gdip_SaveBitmapToFile(bitmap, annotated) != 0
                throw Error("Annotated PNG save failed")
            out["annotated_image_path"] := annotated
            out["annotated_photo_ref"] := Photo_Store(annotated, "Bridge annotated frame")
        }
    } finally
        Gdip_DisposeImage(bitmap)
}

FanVision_RemoveCapture(out) {
    ; Only remove filenames this invocation constructed, never a caller path.
    for , suffix in [".png", "_legend.png"] {
        path := FanVision_CaptureRoot() . "\" . out["frame"]["frame_id"] . suffix
        if FileExist(path)
            try FileDelete(path)
    }
}

; Annotation is drawn into an image using the existing GDI+ runtime. These
; uniquely named helpers avoid adding another competing Gdip library to Fan.
FanVision_Annotate(bitmap, region, controls, legend, grid) {
    graphics := pen := brush := font := family := format := 0
    try {
        if DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bitmap, "Ptr*", &graphics)
            throw Error("GDI+ graphics unavailable")
        DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", graphics, "Int", 4)
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0xB02090F0, "Float", 1.0, "Int", 2, "Ptr*", &pen)
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFFF02040, "Ptr*", &brush)
        DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Segoe UI", "Ptr", 0, "Ptr*", &family)
        DllCall("gdiplus\GdipCreateFont", "Ptr", family, "Float", 15, "Int", 1, "Int", 2, "Ptr*", &font)
        DllCall("gdiplus\GdipStringFormatGetGenericTypographic", "Ptr*", &format)
        if grid {
            step := Max(100, Ceil(Max(region["w"], region["h"])/12/50)*50)
            x := 0
            while x < region["w"] {
                DllCall("gdiplus\GdipDrawLine", "Ptr", graphics, "Ptr", pen, "Float", x, "Float", 0, "Float", x, "Float", region["h"])
                FanVision_DrawLabel(graphics, font, format, brush, "x=" . (region["x"]+x), x+3, 3, 100, 22)
                x += step
            }
            y := 0
            while y < region["h"] {
                DllCall("gdiplus\GdipDrawLine", "Ptr", graphics, "Ptr", pen, "Float", 0, "Float", y, "Float", region["w"], "Float", y)
                FanVision_DrawLabel(graphics, font, format, brush, "y=" . (region["y"]+y), 3, y+22, 100, 22)
                y += step
            }
        }
        DllCall("gdiplus\GdipSetPenColor", "Ptr", pen, "UInt", 0xE0EF2040)
        for , control in controls {
            b := control["bounds"], x := Max(0, b["x"]-region["x"]), y := Max(0, b["y"]-region["y"])
            w := Min(b["x"]+b["w"]-region["x"], region["w"])-x
            h := Min(b["y"]+b["h"]-region["y"], region["h"])-y
            DllCall("gdiplus\GdipDrawRectangle", "Ptr", graphics, "Ptr", pen, "Float", x, "Float", y, "Float", w, "Float", h)
            FanVision_DrawLabel(graphics, font, format, brush, "#" . control["id"], x+2, y+2, 55, 24)
            legend.Push(Map("id", control["id"], "label", "#" . control["id"], "role", control["role"],
                "name", control["name"], "bounds", b, "center", control["center"], "source", control["source"]))
        }
    } finally {
        if format
            DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", format)
        if font
            DllCall("gdiplus\GdipDeleteFont", "Ptr", font)
        if family
            DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", family)
        if brush
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
        if pen
            DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
        if graphics
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
    }
}

FanVision_DrawLabel(graphics, font, format, brush, text, x, y, w, h) {
    rect := Buffer(16, 0)
    NumPut("Float", x, "Float", y, "Float", w, "Float", h, rect)
    DllCall("gdiplus\GdipDrawString", "Ptr", graphics, "WStr", text, "Int", -1,
        "Ptr", font, "Ptr", rect, "Ptr", format, "Ptr", brush)
}

FanVision_PatternList(args) {
    global g_Patterns
    limit := FanVision_Int(args, "limit", 100, 1, 500), out := []
    query := StrLower(FanVision_Arg(args, "query", FanVision_Arg(args, "name", "")))
    for name, pattern in g_Patterns {
        if query != "" && !InStr(StrLower(name . " " . FanVision_Arg(pattern, "desc", "")), query)
            continue
        out.Push(Map("name", name, "text", pattern["text"], "description", FanVision_Arg(pattern, "desc", ""),
            "screenshot", FanVision_Arg(pattern, "screenshot", ""),
            "capture_window", FanVision_Arg(pattern, "captureWindow", ""),
            "qualifier", FanVision_Arg(pattern, "qualifier", "")))
        if out.Length >= limit
            break
    }
    return Map("ok", true, "patterns", out, "total", g_Patterns.Count, "limit", limit,
        "library", "Fan Patterns / FindText", "coordinates", "physical_screen_pixels")
}

FanVision_Tolerance(args, name) {
    value := FanVision_Arg(args, name, 0)
    if !IsNumber(value) || value < 0 || value > 0.5
        throw ValueError(name . " must be a number from 0 to 0.5")
    return value+0
}

FanVision_PatternSearch(args) {
    global g_Patterns
    name := FanVision_Arg(args, "name", ""), text := FanVision_Arg(args, "text", "")
    if name != "" {
        if !g_Patterns.Has(name)
            throw ValueError("Saved pattern not found: " . name)
        text := g_Patterns[name]["text"]
    }
    if StrLen(text) > 300000 || !InStr(text, "$")
        throw ValueError("Supply a valid saved pattern name or FindText text")
    err1 := FanVision_Tolerance(args, "err1"), err0 := FanVision_Tolerance(args, "err0")
    ; Explicit pattern overrides prevent FindText's built-in second pass from
    ; silently relaxing a requested zero tolerance to five percent.
    fixed := "", count := 0
    for , part in StrSplit(text, "|") {
        if part = ""
            continue
        part := RegExReplace(part, "\[[^\]\r\n]*\]", "")
        if !IsObject(FanVision_FT().PicInfo(part))
            throw ValueError("Invalid FindText pattern")
        if ++count > 50
            throw ValueError("Search at most 50 patterns in one call")
        fixed .= "|[" . err1 . "," . err0 . "]" . part
    }
    hwnd := FanVision_Target(args), region := FanVision_Region(args, hwnd), frame := FanVision_Frame(hwnd, region)
    if !frame["visibility"]["ok"]
        return Map("ok", false, "frame", FanVision_Finish(frame), "error", frame["visibility"]["reason"], "matches", [])
    layout := FanVision_Zones(FanVision_Region(Map(),hwnd))
    initial := FanVision_Hash(region), limit := FanVision_Int(args, "limit", 50, 1, 500), out := []
    FanVision_Trace("FindText","FindTextClass.FindText",Map("hwnd",hwnd,"region",region,"name",name))
    found := FanVision_FT().FindText(&x, &y, region["x"], region["y"], region["x"]+region["w"]-1,
        region["y"]+region["h"]-1, err1, err0, fixed, 0, 1)
    for , match in found {
        grouping := FanVision_ZoneMatch(Map("x",match.x,"y",match.y,"w",match.w,"h",match.h),layout)
        out.Push(Map("pattern", name, "id", match.id,
            "zone_id",grouping["zone_id"],"crosses_zone_boundary",grouping["crosses_zone_boundary"],
            "bounds", Map("x", match.x, "y", match.y, "w", match.w, "h", match.h),
            "center", Map("x", match.mx, "y", match.my), "source", "observed_FindText_match"))
        if out.Length >= limit
            break
    }
    FanVision_Finish(frame, initial)
    return Map("ok", true, "frame", frame, "zones",layout,"matches", out, "total_matches", found.Length,
        "truncated", found.Length > out.Length, "err1", err1, "err0", err0, "library", "FindText",
        "name", name, "text", text)
}

FanVision_PatternCapture(args) {
    global g_Patterns
    name := Trim(FanVision_Arg(args, "name", ""))
    if name = "" || StrLen(name) > 120 || RegExMatch(name, "[<>|\r\n\x00-\x1F]")
        throw ValueError("Pattern name must be 1–120 characters without control characters or < > |")
    if g_Patterns.Has(name) && !FanVision_Arg(args, "overwrite", false)
        throw ValueError("Pattern exists; choose another name or set overwrite=true")
    threshold := FanVision_Arg(args, "threshold", "**50")
    if IsNumber(threshold)
        threshold := "*" . Round(threshold)
    if !RegExMatch(threshold, "^\*{1,2}(\d{1,3})$", &m) || Integer(m[1]) > 255
        throw ValueError("threshold must be 0–255, '*128' (gray) or '**50' (gray difference)")
    hwnd := FanVision_Target(args), region := FanVision_Region(args, hwnd, true), frame := FanVision_Frame(hwnd, region)
    if region["w"] > 1024 || region["h"] > 1024 || region["w"] < 3 || region["h"] < 3
        throw ValueError("Pattern capture width/height must be 3–1024 pixels; crop the target element")
    if !frame["visibility"]["ok"]
        return Map("ok", false, "frame", FanVision_Finish(frame), "error", frame["visibility"]["reason"])
    layout := FanVision_Zones(FanVision_Region(Map(),hwnd))
    initial := FanVision_Hash(region)
    FanVision_Trace("FindText","FindTextClass.GetTextFromScreen",Map("hwnd",hwnd,"region",region,"name",name))
    text := FanVision_FT().GetTextFromScreen(region["x"], region["y"], region["x"]+region["w"]-1,
        region["y"]+region["h"]-1, threshold, 0, &rx, &ry)
    if text = "" || !IsObject(info := FanVision_FT().PicInfo(text)) || info[4] = 0 || info[5] = 0
        throw ValueError("Crop does not contain a usable foreground/background pattern; adjust the region or threshold")
    text := StrReplace(text, "|<>", "|<" . name . ">")
    out := Map("ok", true, "frame", frame, "zones",layout,"controls", [], "image_path", "", "annotated_image_path", "", "legend", [])
    FanVision_SaveImage(out, false)
    FanVision_Finish(frame, initial)
    if !frame["geometry_stable"] || !frame["content_stable"] {
        FanVision_RemoveCapture(out)
        return Map("ok", false, "error", "Window content changed during capture; recapture before saving", "frame", frame)
    }
    description := SubStr(FanVision_Arg(args, "description", "Reusable element learned by DeepSeek"), 1, 2000)
        . " [FanVision " . frame["frame_id"] . "; threshold=" . threshold . "; region="
        . region["x"] . "," . region["y"] . "," . region["w"] . "," . region["h"] . "; observed]"
    data := Map("text", text, "desc", description, "screenshot", Photo_DataUrl(out["image_path"]),
        "captureX", rx, "captureY", ry, "captureWindow", frame["title"],
        "qualifier", SubStr(FanVision_Arg(args, "qualifier", ""), 1, 2000))
    previous := g_Patterns.Has(name) ? g_Patterns[name] : ""
    g_Patterns[name] := data
    try {
        if !SavePatterns()
            throw Error("Pattern database did not save; the in-memory change was rolled back")
    }
    catch as err {
        if IsObject(previous)
            g_Patterns[name] := previous
        else
            g_Patterns.Delete(name)
        FanVision_RemoveCapture(out)
        throw err
    }
    try RefreshPatternLV()
    out["name"] := name, out["text"] := text, out["description"] := description
    out["pattern_dimensions"] := Map("w", info[2], "h", info[3])
    out["capture_center"] := Map("x", rx, "y", ry)
    out["threshold"] := threshold, out["saved_to"] := "Fan Patterns database"
    return out
}
