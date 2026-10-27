#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\lib\FanBridgeClient.ahk
DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")

global atlas := Map("page", "", "windows", [], "pages", [], "elements", [], "groups", [], "offset", 0)
global viewer := Gui("+Resize +MinSize1100x720 -DPIScale", "Chrome Page Learner — Local Atlas")
viewer.SetFont("s9", "Segoe UI")
viewer.Add("Text", "x12 y10 w1060 h24", "Capture a visible Chrome page, inspect its visual elements, and verify targets for automation. Page data stays on this computer.")
atlas["windowsControl"] := viewer.Add("DropDownList", "x12 y40 w500")
viewer.Add("Button", "x524 y38 w95 h27", "Refresh Chrome").OnEvent("Click", (*) => Atlas_Windows())
viewer.Add("Button", "x631 y38 w135 h27", "Learn / reuse page").OnEvent("Click", (*) => Atlas_Capture())
viewer.Add("Button", "x778 y38 w145 h27", "Whole screenshot").OnEvent("Click", (*) => Atlas_Image())
viewer.Add("Button", "x935 y38 w150 h27", "Verify live target").OnEvent("Click", (*) => Atlas_Resolve())
atlas["saved"] := viewer.Add("DropDownList", "x12 y78 w870")
atlas["saved"].OnEvent("Change", (*) => Atlas_Load())
viewer.Add("Button", "x894 y76 w191 h27", "Refresh saved pages").OnEvent("Click", (*) => Atlas_Pages())
atlas["query"] := viewer.Add("Edit", "x12 y115 w330 h26")
atlas["query"].OnEvent("Change", (*) => Atlas_Search())
atlas["group"] := viewer.Add("DropDownList", "x354 y115 w300")
atlas["group"].OnEvent("Change", (*) => Atlas_Search())
viewer.Add("Button", "x666 y113 w95 h28", "Previous 100").OnEvent("Click", (*) => Atlas_Page(-100))
viewer.Add("Button", "x773 y113 w95 h28", "Next 100").OnEvent("Click", (*) => Atlas_Page(100))
viewer.Add("Button", "x935 y113 w150 h28", "Refresh page map").OnEvent("Click", (*) => Atlas_Capture(true))
atlas["list"] := viewer.Add("ListView", "x12 y155 w650 h505", ["ID", "Type", "Description", "Group"])
atlas["list"].ModifyCol(1, 75), atlas["list"].ModifyCol(2, 100), atlas["list"].ModifyCol(3, 280), atlas["list"].ModifyCol(4, 180)
atlas["list"].OnEvent("ItemSelect", (control, row, selected) => selected ? Atlas_Select(row) : 0)
atlas["picture"] := viewer.Add("Picture", "x678 y155 w407 h290")
atlas["details"] := viewer.Add("Edit", "x678 y460 w407 h200 ReadOnly Multi +Wrap +VScroll")
atlas["status"] := viewer.Add("Text", "x12 y679 w1070 h28", "Ready · local capture only · no page content sent to a model")
viewer.OnEvent("Close", (*) => ExitApp())
viewer.OnEvent("Size", Atlas_Size)
Atlas_Windows()
Atlas_Pages()
if A_Args.Length {
    atlas["page"] := A_Args[1]
    try Atlas_ShowPage(FanBridge.PageElements(atlas["page"]))
    catch as err
        atlas["status"].Value := err.Message
}
viewer.Show("w1100 h720")

Atlas_Size(gui, state, width, height) {
    if state = -1
        return
    right := Max(680, width-422), wide := right-28
    atlas["list"].Move(12,155,wide,height-215)
    atlas["picture"].Move(right,155,407,290)
    atlas["details"].Move(right,460,407,Max(140,height-520))
    atlas["status"].Move(12,height-41,width-24)
}

Atlas_Windows() {
    atlas["windows"] := [], labels := []
    for hwnd in WinGetList("ahk_exe chrome.exe") {
        if WinGetTitle("ahk_id " . hwnd) != "" {
            atlas["windows"].Push(hwnd)
            labels.Push(WinGetTitle("ahk_id " . hwnd))
        }
    }
    atlas["windowsControl"].Delete(), atlas["windowsControl"].Add(labels)
    if labels.Length
        atlas["windowsControl"].Choose(1)
}

Atlas_Pages() {
    try {
        atlas["pages"] := FanBridge.Call("fan_page_list", Map("limit", 50))["pages"]
        labels := []
        for page in atlas["pages"]
            labels.Push(page["title"] . " · " . page["element_count"] . " elements · " . page["page_id"])
        atlas["saved"].Delete(), atlas["saved"].Add(labels)
    } catch as err
        atlas["status"].Value := err.Message
}

Atlas_Capture(refresh := false) {
    index := atlas["windowsControl"].Value
    if index < 1
        return
    hwnd := atlas["windows"][index]
    atlas["status"].Value := "Learning screenshot, accessibility, OCR, screen snips and visual patterns…"
    viewer.Hide()
    try {
        Sleep(200)
        page := FanBridge.Call("fan_page_learn", Map("hwnd", hwnd, "refresh", refresh), 155000)
        if !page.Get("ok", false)
            throw Error(page.Get("error", "Page capture failed"))
        atlas["page"] := page["page_id"]
        Atlas_Pages()
        Atlas_ShowPage(page)
    } catch as err
        atlas["status"].Value := err.Message
    finally viewer.Show("NA")
}

Atlas_Load() {
    index := atlas["saved"].Value
    if index < 1
        return
    atlas["page"] := atlas["pages"][index]["page_id"]
    try Atlas_ShowPage(FanBridge.PageElements(atlas["page"]))
    catch as err
        atlas["status"].Value := err.Message
}

Atlas_ShowPage(page) {
    labels := ["All groups"], atlas["groups"] := [""]
    for group in page["groups"] {
        atlas["groups"].Push(group["group_id"])
        labels.Push(group["label"] . " (" . group["count"] . ")")
    }
    for group in page.Get("semantic_groups", []) {
        if !group.Has("group_id") || !group.Has("label")
            continue
        atlas["groups"].Push(group["group_id"])
        labels.Push(group["label"] . " (model inference)")
    }
    atlas["group"].Delete(), atlas["group"].Add(labels), atlas["group"].Choose(1)
    atlas["query"].Value := ""
    Atlas_Search()
    coverage := page["coverage"]
    atlas["status"].Value := page["element_count"] . " mapped elements · " . coverage["saved_crops"]
        . " screen snips · " . coverage["findtext_candidates"] . " patterns · "
        . (coverage["accessibility_truncated"] ? "Accessibility scan reached its limit" : "Accessibility scan complete") . " · visible viewport only"
    if page.Get("reused", false)
        atlas["status"].Value := "Saved map reused · " . page["element_count"] . " retained elements · current page checked · screenshot is historical"
    Atlas_Image()
}

Atlas_Page(delta) {
    atlas["offset"] := Max(0, atlas["offset"]+delta)
    Atlas_Search(false)
}

Atlas_Search(reset := true) {
    if atlas["page"] = ""
        return
    if reset
        atlas["offset"] := 0
    groupIndex := atlas["group"].Value, group := groupIndex > 0 ? atlas["groups"][groupIndex] : ""
    try {
        args := Map("page_id", atlas["page"], "query", atlas["query"].Value, "group", group, "limit", 100, "offset", atlas["offset"])
        page := FanBridge.Call("fan_page_get", args)
        atlas["elements"] := page["elements"], atlas["list"].Delete()
        for e in atlas["elements"]
            atlas["list"].Add(, e["element_id"], e["kind"], e.Get("semantic_description", e["description"]), e.Get("semantic_group", e["group"]))
        atlas["status"].Value := "Showing " . (atlas["offset"]+1) . "–" . (atlas["offset"]+atlas["elements"].Length)
            . " of " . page["matches"] . " matching elements."
    } catch as err
        atlas["status"].Value := err.Message
}

Atlas_Select(row) {
    if row < 1 || row > atlas["elements"].Length
        return
    e := atlas["elements"][row]
    atlas["selected"] := e["element_id"]
    atlas["details"].Value := e["description"] . "`r`nRole: " . e.Get("role", "image region")
        . "`r`nGroup: " . e["group"] . "`r`nAction hint: " . e.Get("action_hint", "")
        . "`r`nLink: " . e.Get("href", "") . "`r`nLink evidence: " . e.Get("link_status", "")
        . "`r`nOCR: " . e.Get("ocr_text", "") . "`r`nDescription source: " . e["description_source"]
        . "`r`nPattern: " . e.Get("pattern_status", "not available")
        . "`r`nModel description: " . e.Get("semantic_description", "")
        . "`r`nModel purpose: " . e.Get("semantic_purpose", "")
    Atlas_Image(e["element_id"])
}

Atlas_Image(elementId := "") {
    if atlas["page"] = ""
        return
    try {
        image := FanBridge.PageImage(atlas["page"], elementId)
        if image.Get("ok", false) {
            b := image["geometry"], drawW := Max(1, Min(400, Floor(285*b["w"]/Max(1,b["h"]))))
            atlas["picture"].Value := "*w" . drawW . " *h-1 " . image["image_path"]
        }
    } catch as err
        atlas["status"].Value := err.Message
}

Atlas_Resolve() {
    if !atlas.Has("selected") || atlas["page"] = ""
        return
    viewer.Hide()
    try {
        Sleep(200)
        index := atlas["windowsControl"].Value, hwnd := index > 0 ? atlas["windows"][index] : 0
        result := FanBridge.ResolvePageElement(atlas["page"], atlas["selected"], hwnd)
        atlas["status"].Value := result.Get("ok", false) ? "Verified live target · " . result["method"] . " · "
            . result["center"]["x"] . ", " . result["center"]["y"] : result.Get("error", "Target did not resolve")
    } catch as err
        atlas["status"].Value := err.Message
    finally viewer.Show("NA")
}
