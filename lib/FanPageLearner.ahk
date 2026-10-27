; Native evidence collector for any visible Chrome page. No input actions.
FanPage_Probe(args) {
    hwnd := FanVision_Target(args)
    if StrLower(WinGetProcessName("ahk_id " . hwnd)) != "chrome.exe"
        throw TargetError("Select a Google Chrome window")
    region := FanVision_Region(Map(), hwnd), frame := FanVision_Frame(hwnd, region)
    if !DllCall("IsWindowVisible", "Ptr", hwnd) || DllCall("IsIconic", "Ptr", hwnd)
        return Map("ok", false, "error", "Chrome must be visible and not minimized", "frame", frame)
    catalog := FanVision_Controls(hwnd, region, 1500, true)
    FanVision_Finish(frame)
    if !frame["geometry_stable"]
        return Map("ok", false, "error", "Chrome changed while verifying its page", "frame", frame)
    controls := catalog["controls"], catalog.Delete("controls")
    return Map("ok", true, "url", FanPage_URL(controls), "frame", frame, "controls", controls,
        "accessibility", catalog, "capture_performed", false)
}

FanPage_NormalizeURL(url) {
    if !RegExMatch(url, "i)^[a-z]+://")
        url := "https://" . url
    if !RegExMatch(url, "i)^([a-z]+)://([^/?#]+)([^?#]*)(\?[^#]*)?(#.*)?$", &m)
        return url
    query := ""
    for part in StrSplit(LTrim(m[4], "?"), "&") {
        key := StrLower(StrSplit(part, "=")[1])
        if part = "" || RegExMatch(key, "^(utm_|trk$|trackingid$|ref$|source$)")
            continue
        query .= (query = "" ? "" : "&") . part
    }
    return StrLower(m[1]) . "://" . StrLower(m[2]) . (RTrim(m[3], "/") = "" ? "/" : RTrim(m[3], "/"))
        . (query = "" ? "" : "?" . query) . m[5]
}

FanPage_Learn(args) {
    hwnd := FanVision_Target(args)
    if StrLower(WinGetProcessName("ahk_id " . hwnd)) != "chrome.exe"
        throw TargetError("Select a visible Google Chrome window before learning its page")
    region := FanVision_Region(Map(), hwnd), frame := FanVision_Frame(hwnd, region)
    if !DllCall("IsWindowVisible", "Ptr", hwnd) || DllCall("IsIconic", "Ptr", hwnd)
        return Map("ok", false, "error", "Chrome must be visible and not minimized", "frame", frame)
    ; Capture Chrome's own Direct3D window surface, not desktop pixels that
    ; can contain a notification, VLC or another app covering this window.
    catalog := FanVision_Controls(hwnd, region, FanVision_Int(args, "max_elements", 1000, 1, 1500), true)
    out := Map("ok", true, "frame", frame, "controls", catalog["controls"], "accessibility", catalog,
        "image_path", "", "annotated_image_path", "", "legend", [], "warnings", [])
    out["zones"] := FanVision_Zones(region,catalog["controls"])
    bitmap := FanPage_SurfaceBitmap(hwnd, region)
    try {
        out["image_path"] := FanVision_CaptureRoot() . "\" . frame["frame_id"] . ".png"
        if Gdip_SaveBitmapToFile(bitmap, out["image_path"]) != 0
            throw Error("Chrome window-surface PNG save failed")
        out["ocr"] := FanVision_ReadOCR(region, Map("_zones",out["zones"],"_image_path", out["image_path"], "lang", args.Get("lang", "")))
        if StrLen(Trim(out["ocr"]["text"])) < 3
            throw Error("Chrome surface has no readable text; incomplete/blank capture was not retained")
        out["photo_ref"] := Photo_Store(out["image_path"], "Chrome surface frame " . frame["frame_id"])
        FanVision_Annotate(bitmap, region, out["controls"], out["legend"], true)
        out["annotated_image_path"] := FanVision_CaptureRoot() . "\" . frame["frame_id"] . "_legend.png"
        if Gdip_SaveBitmapToFile(bitmap, out["annotated_image_path"]) != 0
            throw Error("Chrome annotated window-surface PNG save failed")
        out["annotated_photo_ref"] := Photo_Store(out["annotated_image_path"], "Chrome annotated surface frame")
    } finally Gdip_DisposeImage(bitmap)
    frame["capture_source"] := "Windows_Graphics_Capture_Chrome_window_surface"
    frame["image_visibility"] := "Chrome surface captured independently of desktop occlusion; input targets still verify visible ownership"
    FanVision_Finish(frame)
    if !frame["geometry_stable"]
        return Map("ok", false, "error", "Chrome moved during discovery; recapture the page", "frame", frame)
    DeepActivity_Resume()
    DeepActivity_Set(true, "Mapping page elements and screen snips", 120000)
    out["assets"] := FanPage_Assets(out, FanVision_Int(args, "max_patterns", 40, 0, 100))
    ; Keep one control catalog on the wire instead of duplicating it.
    out["accessibility"].Delete("controls")
    out["capture_scope"] := "complete_visible_chrome_window"
    return out
}

FanPage_SurfaceBitmap(hwnd, region) {
    stream := 0, istream := 0, original := 0, bitmap := 0
    surface := OCR.CreateDirect3DSoftwareBitmapFromWindow(hwnd)
    x := region["x"]-surface.X, y := region["y"]-surface.Y
    if x < 0 || y < 0 || x+region["w"] > surface.W || y+region["h"] > surface.H
        throw Error("Chrome surface geometry differs from its observed DWM bounds")
    try {
        stream := OCR.SoftwareBitmapToRandomAccessStream(surface)
        iid := OCR.CLSIDFromString("{0000000c-0000-0000-C000-000000000046}")
        if DllCall("shcore\CreateStreamOverRandomAccessStream", "Ptr", stream, "Ptr", iid, "Ptr*", &istream, "UInt")
            throw Error("Chrome surface stream bridge failed")
        if DllCall("gdiplus\GdipCreateBitmapFromStream", "Ptr", istream, "Ptr*", &original, "UInt")
            throw Error("Chrome surface PNG decode failed")
        if DllCall("gdiplus\GdipCloneBitmapAreaI", "Int", x, "Int", y, "Int", region["w"], "Int", region["h"],
            "Int", 0x26200A, "Ptr", original, "Ptr*", &bitmap)
            throw Error("Chrome surface region crop failed")
        return bitmap
    } finally {
        if original
            Gdip_DisposeImage(original)
        if istream
            ObjRelease(istream)
        if IsObject(stream)
            try OCR.CloseIClosable(stream)
        try OCR.CloseIClosable(surface)
    }
}

FanPage_Clip(b, r) {
    x := Max(b["x"], r["x"]), y := Max(b["y"], r["y"])
    return Map("x", x, "y", y, "w", Max(0, Min(b["x"]+b["w"], r["x"]+r["w"])-x),
        "h", Max(0, Min(b["y"]+b["h"], r["y"]+r["h"])-y))
}

FanPage_Crop(bitmap, bounds, region, label, force := false) {
    b := FanPage_Clip(bounds, region), crop := 0
    if b["w"] < 1 || b["h"] < 1
        return Map("crop_status", "outside_capture")
    ; Large structural containers are represented by their region in the full
    ; snapshot. fan_page_image can create their crop on demand.
    if !force && b["w"]*b["h"] > 1000000
        return Map("crop_status", "full_snapshot_region", "crop_bounds", b)
    if DllCall("gdiplus\GdipCloneBitmapAreaI", "Int", b["x"]-region["x"], "Int", b["y"]-region["y"],
        "Int", b["w"], "Int", b["h"], "Int", 0x26200A, "Ptr", bitmap, "Ptr*", &crop)
        throw Error("Element screen snip failed")
    path := Photo_TempPath()
    try {
        if Gdip_SaveBitmapToFile(crop, path) != 0
            throw Error("Element PNG save failed")
        return Map("crop_status", "saved", "photo_ref", Photo_Store(path, label), "crop_bounds", b)
    } finally {
        Gdip_DisposeImage(crop)
        if FileExist(path)
            FileDelete(path)
    }
}

FanPage_Assets(out, maxPatterns := 40) {
    assets := Map(), bitmap := 0, region := out["frame"]["region"], patterns := 0, started := A_TickCount
    if DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", out["image_path"], "Ptr*", &bitmap)
        throw Error("Full page snapshot could not be reopened")
    try {
        ; Load the immutable PNG into a separate FindText cache. Dynamic pages
        ; can change while OCR runs; their patterns must still describe THIS PNG.
        patternFT := FindTextClass()
        patternFT.bits.Scan0 := 0
        patternFT.ShowPic(out["image_path"], 0, &imageX, &imageY, &imageW, &imageH)
        if imageW != region["w"] || imageH != region["h"]
            throw Error("FindText snapshot dimensions differ from the captured page")
        document := Map(), area := 0, primary := [], secondary := []
        for c in out["controls"]
            if RegExMatch(c["role"], "i)document") && c["bounds"]["w"]*c["bounds"]["h"] > area
                document := c, area := c["bounds"]["w"]*c["bounds"]["h"]
        for c in out["controls"] {
            if document.Count && SubStr(c["accessibility_path"], 1, StrLen(document["accessibility_path"])+1) = document["accessibility_path"] . "."
                primary.Push(c)
            else
                secondary.Push(c)
        }
        for c in secondary
            primary.Push(c)
        ; Spend the pattern budget on page controls before browser toolbar icons.
        for control in primary {
            id := "acc-" . control["id"], b := FanPage_Clip(control["bounds"], region)
            if control.Get("protected", false) {
                assets[id] := Map("crop_status", "protected", "pattern_status", "protected")
                continue
            }
            asset := FanPage_Crop(bitmap, b, region, "Page element " . id . " · " . SubStr(control["name"], 1, 100))
            asset["pattern_status"] := "not_eligible"
            ; Read patterns from the immutable snapshot, never a later screen.
            if patterns < maxPatterns
                && b["w"] >= 3 && b["h"] >= 3 && b["w"] <= 256 && b["h"] <= 96
                && control.Get("enabled", true) && RegExMatch(control["role"], "i)link|button|check|radio|graphic|image|tab") {
                px := imageX+b["x"]-region["x"], py := imageY+b["y"]-region["y"]
                text := patternFT.GetTextFromScreen(px, py, px+b["w"]-1, py+b["h"]-1, "**50", 0)
                if text != "" && IsObject(info := patternFT.PicInfo(text)) && info[4] && info[5] {
                    asset["pattern_text"] := StrReplace(text, "|<>", "|<" . id . ">")
                    asset["pattern_status"] := "observed_candidate"
                    patterns++
                }
            }
            assets[id] := asset
        }
        for index, line in out.Get("ocr", Map()).Get("lines", [])
            assets["ocr-" . index] := FanPage_Crop(bitmap, line["bounds"], region, "Page OCR line " . index)
        ; A regular image partition preserves evidence for visual areas that
        ; have no accessibility name or OCR text (icons, pictures, charts).
        tiles := [], tileId := 0
        Loop 3 {
            row := A_Index-1
            Loop 4 {
                col := A_Index-1
                x := region["x"]+Floor(region["w"]*col/4), y := region["y"]+Floor(region["h"]*row/3)
                b := Map("x", x, "y", y, "w", region["x"]+Floor(region["w"]*(col+1)/4)-x,
                    "h", region["y"]+Floor(region["h"]*(row+1)/3)-y)
                id := "tile-" . ++tileId
                tiles.Push(Map("id", id, "bounds", b))
                assets[id] := FanPage_Crop(bitmap, b, region, "Page visual region " . tileId)
            }
        }
        out["visual_tiles"] := tiles
        out["asset_stats"] := Map("count", assets.Count, "patterns", patterns, "pattern_limit", maxPatterns,
            "elapsed_ms", A_TickCount-started, "pattern_source", "immutable_saved_snapshot")
    } finally Gdip_DisposeImage(bitmap)
    return assets
}

FanPage_URL(controls) {
    fallback := ""
    for c in controls {
        value := c.Get("value", ""), role := c.Get("role", "")
        if RegExMatch(role, "i)document") && RegExMatch(value, "i)^(https?://|file://)")
            return value
        if fallback = "" && RegExMatch(c.Get("name", ""), "i)address.*(search|bar)") && value != ""
            fallback := value
    }
    return fallback
}

FanPage_Resolve(args) {
    saved := args.Get("_element", Map()), page := args.Get("_page", Map())
    if !saved.Count || !page.Count
        throw ValueError("Page element must be loaded by the authenticated gateway")
    hwnd := args.Get("hwnd", 0)
    if !hwnd {
        try hwnd := FanVision_Target(Map())
        if !hwnd || StrLower(WinGetProcessName("ahk_id " . hwnd)) != "chrome.exe"
            hwnd := page["frame"]["hwnd"]
    }
    hwnd := FanVision_Target(Map("hwnd", hwnd))
    if StrLower(WinGetProcessName("ahk_id " . hwnd)) != "chrome.exe"
        return Map("ok", false, "error", "Select the Chrome window containing this saved page")
    if page.Get("url", "") = "" && WinGetTitle("ahk_id " . hwnd) != page["frame"]["title"]
        return Map("ok", false, "error", "Chrome page identity cannot be verified")
    if saved.Get("protected", false) || !saved.Get("enabled", true) || saved.Get("kind", "") = "visual_region"
        return Map("ok", false, "error", "Element is protected, disabled, or is an uninterpreted image region")
    region := FanVision_Region(Map(), hwnd), frame := FanVision_Frame(hwnd, region)
    if !DllCall("IsWindowVisible", "Ptr", hwnd) || DllCall("IsIconic", "Ptr", hwnd)
        return Map("ok", false, "error", "Chrome must be visible and not minimized")
    ; Verify uniqueness in the current tree. A once-unique saved path can now
    ; point at the first of two identical controls; memory alone cannot prove it.
    ; This lightweight accessibility check does not repeat OCR/snips/learning.
    current := FanVision_Controls(hwnd, region, 1500, true)
    if current.Get("truncated", false) || current.Get("error", "") != ""
        return Map("ok", false, "error", "Current accessibility tree is incomplete; target uniqueness cannot be verified")
    liveURL := FanPage_URL(current["controls"])
    if page.Get("url", "") != "" && FanPage_NormalizeURL(liveURL) != FanPage_NormalizeURL(page["url"])
        return Map("ok", false, "error", "This is a different page; select its retained map or learn it once")
    matches := []
    for c in current["controls"]
        if c["name"] = saved.Get("name", "") && c["role"] = saved.Get("role", "")
            && (saved.Get("href", "") = "" || c["href"] = saved["href"]) {
            if !c["enabled"] || c["protected"]
                return Map("ok", false, "error", "Live target is disabled or protected")
            matches.Push(c)
        }
    ; A unique live identity may move within the tree; duplicates are refused.
    if matches.Length = 1 && saved.Get("name", "") != "" {
        target := matches[1]
        try {
            live := Acc.ElementFromPath(target["accessibility_path"], hwnd), loc := live.Location
            if live.Name != saved["name"] || live.RoleText != saved["role"] || (live.State & (1|0x8000|0x10000|0x20000000))
                return Map("ok", false, "error", "Target changed while resolving; recapture")
            if saved.Get("href", "") != "" && live.Value != saved["href"]
                return Map("ok", false, "error", "Link target changed while resolving; recapture")
            b := FanPage_Clip(Map("x", Round(loc.x), "y", Round(loc.y), "w", Round(loc.w), "h", Round(loc.h)), region)
        } catch
            return Map("ok", false, "error", "Target disappeared while resolving; recapture")
        if b["w"] < 1 || b["h"] < 1
            return Map("ok", false, "error", "Target is outside the current viewport")
        FanVision_Finish(frame)
        if !frame["geometry_stable"]
            return Map("ok", false, "error", "Chrome moved while resolving")
        targetVisibility := FanVision_Visibility(hwnd, b)
        if !targetVisibility["ok"]
            return Map("ok", false, "error", targetVisibility["reason"])
        frame["window_visibility"] := frame["visibility"], frame["visibility"] := targetVisibility
        frame["visibility_scope"] := "resolved_target_bounds"
        return Map("ok", true, "method", "unique_live_accessibility_identity", "frame", frame,
            "bounds", b, "center", Map("x", b["x"]+b["w"]//2, "y", b["y"]+b["h"]//2), "controls", [target])
    }
    if matches.Length > 1 && saved.Get("name", "") != ""
        return Map("ok", false, "error", "More than one live control has this identity; relearn and disambiguate", "matches", matches)
    if saved.Get("kind", "") = "ocr_text" {
        observed := FanVision_OCRTool(Map("hwnd", hwnd)), lines := []
        for line in observed.Get("ocr", Map()).Get("lines", [])
            if line["text"] = saved["name"]
                lines.Push(line)
        if lines.Length = 1 && observed["frame"].Get("geometry_stable", false) && observed["frame"].Get("content_stable", false) {
            b := lines[1]["bounds"]
            return Map("ok", true, "method", "unique_live_ocr_text", "action_verified", false,
                "frame", observed["frame"], "bounds", b, "center", Map("x", b["x"]+b["w"]//2, "y", b["y"]+b["h"]//2))
        }
    }
    if saved.Get("pattern_text", "") != "" {
        found := FanVision_PatternSearch(Map("hwnd", hwnd, "text", saved["pattern_text"], "limit", 2))
        if found.Get("ok", false) && found["matches"].Length = 1 && found["frame"].Get("geometry_stable", false) && found["frame"].Get("content_stable", false)
            return Map("ok", true, "method", "unique_live_findtext_match", "frame", found["frame"],
                "bounds", found["matches"][1]["bounds"], "center", found["matches"][1]["center"], "matches", found["matches"])
    }
    return Map("ok", false, "error", "Saved target has no unique live match; no old coordinates were used")
}

FanPage_Image(args) {
    photo := args.Get("_photo_ref", ""), path := Photo_Path(photo)
    if path = ""
        return Map("ok", false, "error", "Stored page image is unavailable")
    if args.Get("_crop", false) {
        bitmap := 0
        if DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", path, "Ptr*", &bitmap)
            throw Error("Stored snapshot could not be reopened")
        try {
            crop := FanPage_Crop(bitmap, args["_bounds"], args["_capture_region"], "Stored page region", true)
            photo := crop.Get("photo_ref", ""), path := Photo_Path(photo)
        } finally Gdip_DisposeImage(bitmap)
    }
    if path = ""
        return Map("ok", false, "error", "This element has no pixels inside the stored viewport")
    return Map("ok", true, "image_path", path, "photo_ref", photo, "source_kind", "historical_observed_image",
        "geometry", args.Get("_bounds", Map()), "note", "Stored screenshot geometry is historical; resolve against the live page before acting")
}
