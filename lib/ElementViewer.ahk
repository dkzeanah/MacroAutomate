; ═══════════════════════════════════════════════════════════════════════════════
; ElementViewer.ahk - Tabbed snapshot viewer + element registry (Feature 4 UI)
; ═══════════════════════════════════════════════════════════════════════════════
; Opens a window that, for a chosen 5-minute cycle, lists every captured window
; and shows each entry's three linked representations in tabs:
;
;   Raw Image     the saved .png (drag on it to mark an element)
;   Base64        the stored text encoding + copy button
;   Binary Image  the FindText image rendered back to a picture, plus ASCII
;   OCR Text      recognised text, when captured
;   Elements      named elements defined on this window
;
; Marking an element: click "Mark Element", drag a rectangle over the raw image,
; give it a name + functional description. It is saved to the `element` table
; with absolute capture coordinates, window-relative coordinates, a cropped
; thumbnail, and a FindText binary pattern of the crop - everything the
; automation engine needs to find and act on it later (see WORKFLOW ACTIONS).
; ═══════════════════════════════════════════════════════════════════════════════

; ─── Viewer state ────────────────────────────────────────────────────────────
global g_VwGui := ""
global g_VwCycleId := 0
global g_VwEntryId := 0
global g_VwEntry := Map()
global g_VwCyclesLV := ""
global g_VwEntriesLV := ""
global g_VwTabs := ""
global g_VwPic := ""
global g_VwB64Edit := ""
global g_VwBinPic := ""
global g_VwBinAscii := ""
global g_VwOcrEdit := ""
global g_VwElemLV := ""
global g_VwInfoText := ""
global g_VwMarkBtn := ""

; Row -> database id maps for the list views (kept in globals rather than as
; ad-hoc control properties, which are not guaranteed across AHK builds).
global g_VwEntryIds := []
global g_VwElemIds := []

; Display mapping for the currently shown raw image.
global g_VwDispScale := 1.0     ; displayed px / capture px
global g_VwPicScreenX := 0      ; screen origin of the displayed image
global g_VwPicScreenY := 0
global g_VwPicDispW := 0
global g_VwPicDispH := 0

; Rubber-band selection state.
global g_VwMarkMode := false
global g_VwSelActive := false
global g_VwSelStartX := 0
global g_VwSelStartY := 0
global g_VwBand := ["", "", "", ""]   ; 4 edge overlays

; Temp render paths (regenerated per entry).
global g_VwTmpBinPng := ""

; ═══════════════════════════════════════════════════════════════════════════════
; ENTRY POINT
; ═══════════════════════════════════════════════════════════════════════════════

Snap_OpenViewer(cycleId := 0) {
    global g_VwGui

    if !TrackDB_Ready() {
        if !TrackDB_Init() {
            MsgBox("Tracking database is unavailable:`n" . g_TrackDBError, "Snapshot Viewer", "Iconx")
            return
        }
    }

    if IsObject(g_VwGui) {
        try {
            g_VwGui.Show()
            Vw_LoadCycles()
            if cycleId
                Vw_SelectCycle(cycleId)
            return
        }
    }

    Vw_BuildGui()
    Vw_LoadCycles()
    if cycleId
        Vw_SelectCycle(cycleId)
    else {
        cycles := TrackDB_RecentCycles(1)
        if cycles.Length
            Vw_SelectCycle(cycles[1]["id"])
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; GUI CONSTRUCTION
; ═══════════════════════════════════════════════════════════════════════════════

Vw_BuildGui() {
    global g_VwGui, g_VwCyclesLV, g_VwEntriesLV, g_VwTabs, g_VwPic
    global g_VwB64Edit, g_VwBinPic, g_VwBinAscii, g_VwOcrEdit, g_VwElemLV
    global g_VwInfoText, g_VwMarkBtn, g_VwTmpBinPng, DATA_DIR

    g_VwTmpBinPng := DATA_DIR . "\tracking\_viewer_bin.png"

    g := Gui("+Resize +MinSize900x600", "Snapshot Viewer & Element Registry")
    g.SetFont("s9", "Segoe UI")
    g.OnEvent("Close", (*) => g.Hide())
    g.OnEvent("Size", Vw_OnResize)

    ; ─── Left column: cycles + entries ───────────────────────────────────────
    g.Add("Text", "x10 y10 w200", "Snapshot Cycles").SetFont("s9 Bold")
    g_VwCyclesLV := g.Add("ListView", "x10 y30 w270 h180 Grid -Multi", ["Cycle", "Time", "Win"])
    g_VwCyclesLV.ModifyCol(1, 45)
    g_VwCyclesLV.ModifyCol(2, 160)
    g_VwCyclesLV.ModifyCol(3, 45)
    g_VwCyclesLV.OnEvent("ItemSelect", Vw_OnCycleSelect)

    g.Add("Text", "x10 y216 w200", "Captured Windows").SetFont("s9 Bold")
    g_VwEntriesLV := g.Add("ListView", "x10 y236 w270 h300 Grid -Multi", ["#", "Window", "Size"])
    g_VwEntriesLV.ModifyCol(1, 30)
    g_VwEntriesLV.ModifyCol(2, 170)
    g_VwEntriesLV.ModifyCol(3, 60)
    g_VwEntriesLV.OnEvent("ItemSelect", Vw_OnEntrySelect)

    g.Add("Button", "x10 y540 w130 h26", "Snapshot Now").OnEvent("Click", Vw_SnapshotNow)
    g.Add("Button", "x145 y540 w135 h26", "Refresh").OnEvent("Click", (*) => Vw_LoadCycles())

    ; ─── Right column: info + tabs ───────────────────────────────────────────
    g_VwInfoText := g.Add("Text", "x290 y10 w690 h32 +Wrap", "Select a cycle and a window.")
    g_VwInfoText.SetFont("s9")

    g_VwTabs := g.Add("Tab3", "x290 y46 w690 h490 vVwTab"
                    , ["Raw Image", "Base64", "Binary Image", "OCR Text", "Elements"])

    ; Tab 1: Raw image
    g_VwTabs.UseTab(1)
    g_VwMarkBtn := g.Add("Button", "x300 y76 w120 h24", "Mark Element")
    g_VwMarkBtn.OnEvent("Click", Vw_ToggleMarkMode)
    g.Add("Button", "x425 y76 w110 h24", "Open File").OnEvent("Click", Vw_OpenRawFile)
    g.Add("Button", "x540 y76 w150 h24", "Re-extract Features").OnEvent("Click", Vw_ReExtract)
    g.Add("Text", "x700 y80 w270 cGray", "Drag on the image to mark an element region")
    g_VwPic := g.Add("Picture", "x300 y106 w670 h420 Border")

    ; Tab 2: Base64
    g_VwTabs.UseTab(2)
    g.Add("Text", "x300 y76 w400", "Base64 encoding of the raw image bytes:")
    g.Add("Button", "x700 y74 w130 h22", "Copy Base64").OnEvent("Click", Vw_CopyB64)
    g.Add("Button", "x835 y74 w130 h22", "Save as .txt").OnEvent("Click", Vw_SaveB64)
    g_VwB64Edit := g.Add("Edit", "x300 y100 w670 h420 ReadOnly -Wrap +HScroll VScroll")

    ; Tab 3: Binary image
    g_VwTabs.UseTab(3)
    g.Add("Text", "x300 y76 w400", "FindText binary image (thresholded 1-bit form):")
    g.Add("Button", "x700 y74 w130 h22", "Copy FindText").OnEvent("Click", Vw_CopyBinary)
    g.Add("Button", "x835 y74 w130 h22", "Copy ASCII").OnEvent("Click", Vw_CopyAscii)
    g_VwBinPic := g.Add("Picture", "x300 y100 w400 h300 Border")
    g_VwBinAscii := g.Add("Edit", "x705 y100 w265 h420 ReadOnly -Wrap +HScroll VScroll")
    g_VwBinAscii.SetFont("s6", "Consolas")

    ; Tab 4: OCR
    g_VwTabs.UseTab(4)
    g.Add("Text", "x300 y76 w400", "OCR text recognised from the capture:")
    g.Add("Button", "x835 y74 w130 h22", "Copy Text").OnEvent("Click", Vw_CopyOcr)
    g_VwOcrEdit := g.Add("Edit", "x300 y100 w670 h420 ReadOnly +Wrap VScroll")

    ; Tab 5: Elements
    g_VwTabs.UseTab(5)
    g.Add("Text", "x300 y76 w400", "Named elements on this window:")
    g_VwElemLV := g.Add("ListView", "x300 y100 w670 h360 Grid"
                      , ["Name", "Role", "Description", "X", "Y", "W", "H", "Hits"])
    g_VwElemLV.ModifyCol(1, 130)
    g_VwElemLV.ModifyCol(2, 80)
    g_VwElemLV.ModifyCol(3, 200)
    g_VwElemLV.ModifyCol(4, 45)
    g_VwElemLV.ModifyCol(5, 45)
    g_VwElemLV.ModifyCol(6, 45)
    g_VwElemLV.ModifyCol(7, 45)
    g_VwElemLV.ModifyCol(8, 40)
    g_VwElemLV.OnEvent("DoubleClick", Vw_EditElement)
    g.Add("Button", "x300 y466 w130 h26", "Edit").OnEvent("Click", Vw_EditElement)
    g.Add("Button", "x435 y466 w130 h26", "Delete").OnEvent("Click", Vw_DeleteElement)
    g.Add("Button", "x570 y466 w150 h26", "Test on Screen").OnEvent("Click", Vw_TestElement)
    g.Add("Button", "x725 y466 w150 h26", "Export Elements JSON").OnEvent("Click", Vw_ExportElements)

    g_VwTabs.UseTab()

    g_VwGui := g
    g.Show("w990 h580")
}

; ═══════════════════════════════════════════════════════════════════════════════
; DATA LOADING
; ═══════════════════════════════════════════════════════════════════════════════

Vw_LoadCycles() {
    global g_VwCyclesLV
    if !IsObject(g_VwCyclesLV)
        return
    g_VwCyclesLV.Delete()
    for c in TrackDB_RecentCycles(100) {
        when := c["started_ts"] != "" ? SubStr(c["started_ts"], 6) : ""
        g_VwCyclesLV.Add(, c["id"], when, c["entries"])
    }
}

Vw_SelectCycle(cycleId) {
    global g_VwCyclesLV
    ; Find the row with this cycle id and select it.
    Loop g_VwCyclesLV.GetCount() {
        if (g_VwCyclesLV.GetText(A_Index, 1) = String(cycleId)) {
            g_VwCyclesLV.Modify(A_Index, "Select Focus Vis")
            Vw_ShowCycle(cycleId)
            return
        }
    }
}

Vw_OnCycleSelect(lv, item, selected) {
    if !selected
        return
    cid := lv.GetText(item, 1)
    if (cid != "")
        Vw_ShowCycle(Integer(cid))
}

Vw_ShowCycle(cycleId) {
    global g_VwCycleId, g_VwEntriesLV, g_VwEntryIds
    g_VwCycleId := cycleId
    g_VwEntriesLV.Delete()
    entries := TrackDB_CycleEntries(cycleId)
    g_VwEntryIds := []
    for e in entries {
        name := e["title"] != "" ? e["title"] : e["exe"]
        g_VwEntriesLV.Add(, A_Index, TrackEllipsis(name, 40), e["w"] . "x" . e["h"])
        g_VwEntryIds.Push(e["id"])
    }

    if entries.Length {
        g_VwEntriesLV.Modify(1, "Select Focus Vis")
        Vw_ShowEntry(entries[1]["id"])
    } else {
        Vw_ClearEntry()
    }
}

Vw_OnEntrySelect(lv, item, selected) {
    global g_VwEntryIds
    if !selected
        return
    if (item < 1 || item > g_VwEntryIds.Length)
        return
    Vw_ShowEntry(g_VwEntryIds[item])
}

; ═══════════════════════════════════════════════════════════════════════════════
; ENTRY DISPLAY
; ═══════════════════════════════════════════════════════════════════════════════

Vw_ShowEntry(entryId) {
    global g_VwEntryId, g_VwEntry, g_VwInfoText, g_VwPic, g_VwB64Edit
    global g_VwBinPic, g_VwBinAscii, g_VwOcrEdit, g_VwTmpBinPng
    global g_VwDispScale, g_VwPicDispW, g_VwPicDispH

    db := TrackDB()
    if !db
        return
    e := db.QueryRow("SELECT * FROM snap_entry WHERE id=?", entryId)
    if !e.Count
        return

    g_VwEntryId := entryId
    g_VwEntry := e

    ; ─── Header ──────────────────────────────────────────────────────────────
    g_VwInfoText.Value := "Window: " . e["title"] . "`n"
        . "App: " . e["exe"] . "  |  Class: " . e["class"]
        . "  |  Region: " . e["x"] . "," . e["y"] . "  " . e["w"] . "x" . e["h"]
        . "  |  Captured: " . e["ts"]
        . "  |  Image: " . Round(e["image_bytes"] / 1024, 1) . " KB "
        . "  |  Base64: " . e["b64_len"] . " chars"
        . "  |  Binary: " . e["bin_w"] . "x" . e["bin_h"] . " " . e["threshold"]

    ; ─── Raw image ───────────────────────────────────────────────────────────
    Vw_ResetMarkMode()
    if (e["image_path"] != "" && FileExist(e["image_path"])) {
        ; Fit within the picture control, remembering the scale for coord mapping.
        boxW := 670, boxH := 420
        capW := Max(1, Integer(e["w"])), capH := Max(1, Integer(e["h"]))
        scale := Min(boxW / capW, boxH / capH, 1.0)
        g_VwDispScale := scale
        g_VwPicDispW := Integer(Round(capW * scale))
        g_VwPicDispH := Integer(Round(capH * scale))
        g_VwPic.Value := "*w" . g_VwPicDispW . " *h" . g_VwPicDispH . " " . e["image_path"]
    } else {
        g_VwPic.Value := ""
        g_VwDispScale := 1.0
    }

    ; ─── Base64 ──────────────────────────────────────────────────────────────
    g_VwB64Edit.Value := e["b64"]

    ; ─── Binary image ────────────────────────────────────────────────────────
    if (e["bin_text"] != "") {
        rendered := ""
        try rendered := Snap_RenderBinary(e["bin_text"], g_VwTmpBinPng, 2)
        if (rendered != "" && FileExist(rendered))
            g_VwBinPic.Value := "*w390 *h290 " . rendered
        else
            g_VwBinPic.Value := ""
        g_VwBinAscii.Value := Snap_BinaryToAscii(e["bin_text"], 120)
    } else {
        g_VwBinPic.Value := ""
        g_VwBinAscii.Value := "(no binary form stored)"
    }

    ; ─── OCR ─────────────────────────────────────────────────────────────────
    g_VwOcrEdit.Value := (e["ocr_text"] != "") ? e["ocr_text"] : "(OCR not captured - enable 'OCR on snapshot' in the Tracking tab)"

    ; ─── Elements ────────────────────────────────────────────────────────────
    Vw_LoadElements()
}

Vw_ClearEntry() {
    global g_VwEntryId, g_VwEntry, g_VwPic, g_VwB64Edit, g_VwBinPic, g_VwBinAscii, g_VwOcrEdit, g_VwInfoText
    g_VwEntryId := 0
    g_VwEntry := Map()
    g_VwInfoText.Value := "This cycle has no captured windows."
    g_VwPic.Value := ""
    g_VwB64Edit.Value := ""
    g_VwBinPic.Value := ""
    g_VwBinAscii.Value := ""
    g_VwOcrEdit.Value := ""
    Vw_LoadElements()
}

Vw_LoadElements() {
    global g_VwElemLV, g_VwEntry, g_VwElemIds
    if !IsObject(g_VwElemLV)
        return
    g_VwElemLV.Delete()
    g_VwElemIds := []
    if !g_VwEntry.Count || !g_VwEntry.Has("win_id")
        return
    els := TrackDB_Elements(g_VwEntry["win_id"])
    for el in els {
        g_VwElemLV.Add(, el["name"], el["role"], TrackEllipsis(el["description"], 40)
                     , el["x"], el["y"], el["w"], el["h"], el["hits"])
        g_VwElemIds.Push(el["id"])
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; MARK MODE (rubber-band selection over the raw image)
; ═══════════════════════════════════════════════════════════════════════════════

Vw_ToggleMarkMode(*) {
    global g_VwMarkMode
    if g_VwMarkMode
        Vw_ResetMarkMode()
    else
        Vw_EnterMarkMode()
}

Vw_EnterMarkMode() {
    global g_VwMarkMode, g_VwMarkBtn, g_VwEntry, g_VwPicScreenX, g_VwPicScreenY, g_VwPic

    if !g_VwEntry.Count || g_VwEntry["image_path"] = "" {
        ShowStatus("No image to mark", "fail")
        return
    }

    ; Record the displayed image's screen origin so drags can be mapped back.
    try {
        g_VwPic.GetPos(&cx, &cy, &cw, &ch)
        pt := Buffer(8, 0)
        NumPut("Int", cx, "Int", cy, pt)
        DllCall("ClientToScreen", "Ptr", g_VwGui.Hwnd, "Ptr", pt)
        g_VwPicScreenX := NumGet(pt, 0, "Int")
        g_VwPicScreenY := NumGet(pt, 4, "Int")
    }

    g_VwMarkMode := true
    g_VwMarkBtn.Text := "Cancel Mark"
    OnMessage(0x201, Vw_OnLButtonDown)   ; WM_LBUTTONDOWN
    OnMessage(0x200, Vw_OnMouseMove)     ; WM_MOUSEMOVE
    OnMessage(0x202, Vw_OnLButtonUp)     ; WM_LBUTTONUP
    ShowStatus("Mark mode: drag a rectangle over the image", "wait")
}

Vw_ResetMarkMode() {
    global g_VwMarkMode, g_VwMarkBtn, g_VwSelActive
    if g_VwMarkMode {
        OnMessage(0x201, Vw_OnLButtonDown, 0)
        OnMessage(0x200, Vw_OnMouseMove, 0)
        OnMessage(0x202, Vw_OnLButtonUp, 0)
    }
    g_VwMarkMode := false
    g_VwSelActive := false
    if IsObject(g_VwMarkBtn)
        g_VwMarkBtn.Text := "Mark Element"
    Vw_DestroyBand()
}

Vw_OnLButtonDown(wParam, lParam, msg, hwnd) {
    global g_VwMarkMode, g_VwSelActive, g_VwSelStartX, g_VwSelStartY
    global g_VwPicScreenX, g_VwPicScreenY, g_VwPicDispW, g_VwPicDispH

    if !g_VwMarkMode
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    ; Only start when the press lands inside the displayed image.
    if (mx < g_VwPicScreenX || my < g_VwPicScreenY
        || mx > g_VwPicScreenX + g_VwPicDispW || my > g_VwPicScreenY + g_VwPicDispH)
        return
    g_VwSelActive := true
    g_VwSelStartX := mx
    g_VwSelStartY := my
    Vw_UpdateBand(mx, my, mx, my)
    return 0
}

Vw_OnMouseMove(wParam, lParam, msg, hwnd) {
    global g_VwSelActive, g_VwSelStartX, g_VwSelStartY
    if !g_VwSelActive
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    Vw_UpdateBand(g_VwSelStartX, g_VwSelStartY, mx, my)
}

Vw_OnLButtonUp(wParam, lParam, msg, hwnd) {
    global g_VwSelActive, g_VwSelStartX, g_VwSelStartY
    global g_VwPicScreenX, g_VwPicScreenY, g_VwDispScale, g_VwEntry
    global g_VwPicDispW, g_VwPicDispH

    if !g_VwSelActive
        return
    g_VwSelActive := false
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    Vw_DestroyBand()

    ; Clamp both corners to the displayed image bounds.
    x1 := TrackClamp(Min(g_VwSelStartX, mx), g_VwPicScreenX, g_VwPicScreenX + g_VwPicDispW)
    y1 := TrackClamp(Min(g_VwSelStartY, my), g_VwPicScreenY, g_VwPicScreenY + g_VwPicDispH)
    x2 := TrackClamp(Max(g_VwSelStartX, mx), g_VwPicScreenX, g_VwPicScreenX + g_VwPicDispW)
    y2 := TrackClamp(Max(g_VwSelStartY, my), g_VwPicScreenY, g_VwPicScreenY + g_VwPicDispH)

    ; Map displayed pixels -> capture-image pixels.
    scale := (g_VwDispScale > 0) ? g_VwDispScale : 1.0
    imgX := Integer(Round((x1 - g_VwPicScreenX) / scale))
    imgY := Integer(Round((y1 - g_VwPicScreenY) / scale))
    imgW := Integer(Round((x2 - x1) / scale))
    imgH := Integer(Round((y2 - y1) / scale))

    if (imgW < 4 || imgH < 4) {
        ShowStatus("Selection too small - drag a larger box", "fail")
        return
    }

    Vw_ResetMarkMode()
    ; Defer the naming dialog out of this WM_LBUTTONUP handler so the modal wait
    ; does not block message processing inside the hook callback.
    SetTimer(() => Vw_DefineElement(imgX, imgY, imgW, imgH), -1)
}

; ─── Rubber-band overlay (4 thin always-on-top strips) ───────────────────────

Vw_UpdateBand(x1, y1, x2, y2) {
    global g_VwBand
    left := Min(x1, x2), top := Min(y1, y2)
    w := Abs(x2 - x1), h := Abs(y2 - y1)
    color := "Red"
    edges := [[left, top, w, 2], [left, top + h - 2, w, 2]
            , [left, top, 2, h], [left + w - 2, top, 2, h]]
    Loop 4 {
        e := edges[A_Index]
        if !IsObject(g_VwBand[A_Index]) {
            bg := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
            bg.BackColor := color
            g_VwBand[A_Index] := bg
        }
        try g_VwBand[A_Index].Show("NA x" . e[1] . " y" . e[2] . " w" . Max(1, e[3]) . " h" . Max(1, e[4]))
    }
}

Vw_DestroyBand() {
    global g_VwBand
    Loop 4 {
        if IsObject(g_VwBand[A_Index]) {
            try g_VwBand[A_Index].Destroy()
            g_VwBand[A_Index] := ""
        }
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; ELEMENT DEFINITION
; ═══════════════════════════════════════════════════════════════════════════════

; imgX/Y/W/H are in capture-image pixels (relative to the snapshot png).
Vw_DefineElement(imgX, imgY, imgW, imgH) {
    global g_VwEntry, DATA_DIR

    if !g_VwEntry.Count
        return

    ; ─── Collect a name + functional description ─────────────────────────────
    dlg := Gui("+Owner" . g_VwGui.Hwnd . " +AlwaysOnTop", "Name this element")
    dlg.SetFont("s9", "Segoe UI")
    dlg.Add("Text", "x10 y10 w360"
          , "Region " . imgW . "x" . imgH . " at " . imgX . "," . imgY
          . " (window '" . TrackEllipsis(g_VwEntry["title"], 40) . "')")
    dlg.Add("Text", "x10 y40", "Name:")
    nameEdit := dlg.Add("Edit", "x100 y37 w270", "")
    dlg.Add("Text", "x10 y70", "Role:")
    roleDD := dlg.Add("ComboBox", "x100 y67 w270"
                    , ["button", "textbox", "link", "icon", "menu", "tab", "checkbox", "label", "region", "result", "field"])
    dlg.Add("Text", "x10 y100", "Description:")
    descEdit := dlg.Add("Edit", "x100 y97 w270 h80 Multi", "")
    dlg.Add("Text", "x10 y185 w360 cGray"
          , "Functional description - what the automation engine does with it,`ne.g. 'Search box - type the query and press Enter'.")

    result := Map("ok", false)
    dlg.Add("Button", "x100 y225 w120 h28 Default", "Save Element").OnEvent("Click", (*) => (
        result["ok"] := true,
        result["name"] := Trim(nameEdit.Value),
        result["role"] := Trim(roleDD.Text),
        result["desc"] := descEdit.Value,
        dlg.Destroy()
    ))
    dlg.Add("Button", "x225 y225 w120 h28", "Cancel").OnEvent("Click", (*) => dlg.Destroy())
    dlg.OnEvent("Close", (*) => dlg.Destroy())
    dlg.Show("w385 h270")

    ; Modal wait
    WinWaitClose("ahk_id " . dlg.Hwnd)

    if !result["ok"] || result["name"] = "" {
        ShowStatus("Element not saved", "fail")
        return
    }

    Vw_SaveElementRegion(result["name"], result["role"], result["desc"], imgX, imgY, imgW, imgH)
}

Vw_SaveElementRegion(name, role, desc, imgX, imgY, imgW, imgH) {
    global g_VwEntry, DATA_DIR

    e := g_VwEntry
    capW := Max(1, Integer(e["w"])), capH := Max(1, Integer(e["h"]))

    ; Absolute screen coords at capture time (for direct clicking/reference).
    absX := Integer(e["x"]) + imgX
    absY := Integer(e["y"]) + imgY

    ; Window-relative 0-1 coordinates (portable across moves and resizes).
    relX := Round(imgX / capW, 5)
    relY := Round(imgY / capH, 5)
    relW := Round(imgW / capW, 5)
    relH := Round(imgH / capH, 5)

    ; Crop a thumbnail + build a FindText pattern of just this element.
    elemsDir := DATA_DIR . "\tracking\elements"
    if !DirExist(elemsDir) {
        try DirCreate(elemsDir)
    }
    cropName := TrackSafeName(e["win_id"] . "_" . name) . "_" . A_TickCount . ".png"
    cropPath := elemsDir . "\" . cropName

    b64 := ""
    binText := ""
    if (e["image_path"] != "" && FileExist(e["image_path"])) {
        saved := ""
        try saved := Snap_CropToFile(e["image_path"], imgX, imgY, imgW, imgH, cropPath)
        if (saved != "") {
            try b64 := TrackBase64EncodeFile(saved)
            try {
                bin := Snap_FileToBinary(saved, 0, 0, 0, 0)
                binText := bin["text"]
            }
        }
    }

    el := Map(
        "win_id", e["win_id"],
        "app_id", e["app_id"],
        "snap_entry_id", g_VwEntryId,
        "name", name,
        "description", desc,
        "role", role,
        "x", absX, "y", absY, "w", imgW, "h", imgH,
        "rel_x", relX, "rel_y", relY, "rel_w", relW, "rel_h", relH,
        "bin_text", binText,
        "ocr_text", "",
        "image_path", cropPath,
        "b64", b64
    )

    id := 0
    try id := TrackDB_SaveElement(el)
    if id {
        ShowStatus("Element saved: " . name, "ok")
        Vw_LoadElements()
        Vw_RefreshEngineElements()
    } else {
        ShowStatus("Failed to save element", "fail")
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; ELEMENT ACTIONS
; ═══════════════════════════════════════════════════════════════════════════════

Vw_SelectedElementId() {
    global g_VwElemLV, g_VwElemIds
    row := g_VwElemLV.GetNext()
    if (!row || row > g_VwElemIds.Length)
        return 0
    return g_VwElemIds[row]
}

Vw_EditElement(*) {
    id := Vw_SelectedElementId()
    if !id {
        ShowStatus("Select an element first", "fail")
        return
    }
    db := TrackDB()
    el := db.QueryRow("SELECT * FROM element WHERE id=?", id)
    if !el.Count
        return

    dlg := Gui("+Owner" . g_VwGui.Hwnd . " +AlwaysOnTop", "Edit element")
    dlg.SetFont("s9", "Segoe UI")
    dlg.Add("Text", "x10 y12", "Name:")
    nameEdit := dlg.Add("Edit", "x100 y9 w270", el["name"])
    dlg.Add("Text", "x10 y42", "Role:")
    roleEdit := dlg.Add("Edit", "x100 y39 w270", el["role"])
    dlg.Add("Text", "x10 y72", "Description:")
    descEdit := dlg.Add("Edit", "x100 y69 w270 h90 Multi", el["description"])

    dlg.Add("Button", "x100 y175 w120 h28 Default", "Save").OnEvent("Click", (*) => (
        db.Run("UPDATE element SET name=?, role=?, description=?, updated_ts=? WHERE id=?"
             , Trim(nameEdit.Value), Trim(roleEdit.Value), descEdit.Value, TrackTS(), id),
        dlg.Destroy(),
        Vw_LoadElements(),
        Vw_RefreshEngineElements(),
        ShowStatus("Element updated", "ok")
    ))
    dlg.Add("Button", "x225 y175 w120 h28", "Cancel").OnEvent("Click", (*) => dlg.Destroy())
    dlg.OnEvent("Close", (*) => dlg.Destroy())
    dlg.Show("w385 h220")
}

Vw_DeleteElement(*) {
    id := Vw_SelectedElementId()
    if !id {
        ShowStatus("Select an element first", "fail")
        return
    }
    if (MsgBox("Delete this element?", "Confirm", "YesNo Iconx") = "No")
        return
    TrackDB_DeleteElement(id)
    Vw_LoadElements()
    Vw_RefreshEngineElements()
    ShowStatus("Element deleted", "ok")
}

; Locate the element's stored FindText pattern on the current screen and flash it.
Vw_TestElement(*) {
    id := Vw_SelectedElementId()
    if !id {
        ShowStatus("Select an element first", "fail")
        return
    }
    db := TrackDB()
    el := db.QueryRow("SELECT * FROM element WHERE id=?", id)
    if !el.Count
        return
    res := Element_Locate(el)
    if res.Count {
        ShowStatus("Found '" . el["name"] . "' at " . res["x"] . "," . res["y"], "ok")
        try {
            ToolTip("Found: " . el["name"], res["x"] + 15, res["y"])
            SetTimer(() => ToolTip(), -1500)
        }
    } else {
        ShowStatus("Element not found on screen right now", "fail")
    }
}

Vw_ExportElements(*) {
    global g_VwEntry
    winId := g_VwEntry.Count ? g_VwEntry["win_id"] : 0
    path := DATA_DIR . "\tracking\elements_export.json"
    n := Element_ExportJson(path, winId)
    ShowStatus("Exported " . n . " elements to " . path, "ok")
    try Run(path)
}

Vw_RefreshEngineElements() {
    ; Hook for the main GUI to refresh its element dropdown, if present.
    try UpdateElementActionChoices()
}

; ═══════════════════════════════════════════════════════════════════════════════
; MISC BUTTONS
; ═══════════════════════════════════════════════════════════════════════════════

Vw_SnapshotNow(*) {
    id := Snap_RunCycleNow("manual from viewer")
    if id {
        ShowStatus("Snapshot cycle started (#" . id . ")", "ok")
        ; Refresh once the cycle drains.
        SetTimer(Vw_PostSnapshotRefresh, -1500)
    } else {
        ShowStatus("Snapshot busy or no windows to capture", "fail")
    }
}

Vw_PostSnapshotRefresh() {
    global g_SnapBusy, g_VwCycleId
    if g_SnapBusy {
        SetTimer(Vw_PostSnapshotRefresh, -1000)
        return
    }
    Vw_LoadCycles()
    cycles := TrackDB_RecentCycles(1)
    if cycles.Length
        Vw_SelectCycle(cycles[1]["id"])
}

Vw_OpenRawFile(*) {
    global g_VwEntry
    if (g_VwEntry.Count && g_VwEntry["image_path"] != "" && FileExist(g_VwEntry["image_path"]))
        try Run(g_VwEntry["image_path"])
    else
        ShowStatus("No image file", "fail")
}

Vw_ReExtract(*) {
    global g_VwEntry
    if !g_VwEntry.Count || !g_VwEntry["win_id"] {
        ShowStatus("No window selected", "fail")
        return
    }
    feats := MouseTrack_ExtractFeatures(g_VwEntry["win_id"])
    ShowStatus("Extracted " . feats.Length . " interaction features for this window", "ok")
}

Vw_CopyB64(*) {
    global g_VwEntry
    if (g_VwEntry.Count && g_VwEntry["b64"] != "") {
        A_Clipboard := g_VwEntry["b64"]
        ShowStatus("Base64 copied (" . StrLen(g_VwEntry["b64"]) . " chars)", "ok")
    }
}

Vw_SaveB64(*) {
    global g_VwEntry, DATA_DIR
    if (!g_VwEntry.Count || g_VwEntry["b64"] = "")
        return
    path := DATA_DIR . "\tracking\snap_" . g_VwEntryId . "_base64.txt"
    if FileExist(path)
        FileDelete(path)
    FileAppend(g_VwEntry["b64"], path, "UTF-8")
    ShowStatus("Saved base64 to " . path, "ok")
}

Vw_CopyBinary(*) {
    global g_VwEntry
    if (g_VwEntry.Count && g_VwEntry["bin_text"] != "") {
        A_Clipboard := g_VwEntry["bin_text"]
        ShowStatus("FindText binary copied", "ok")
    }
}

Vw_CopyAscii(*) {
    global g_VwEntry
    if (g_VwEntry.Count && g_VwEntry["bin_text"] != "") {
        A_Clipboard := Snap_BinaryToAscii(g_VwEntry["bin_text"], 160)
        ShowStatus("ASCII art copied", "ok")
    }
}

Vw_CopyOcr(*) {
    global g_VwEntry
    if (g_VwEntry.Count && g_VwEntry["ocr_text"] != "") {
        A_Clipboard := g_VwEntry["ocr_text"]
        ShowStatus("OCR text copied", "ok")
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; RESIZE
; ═══════════════════════════════════════════════════════════════════════════════

Vw_OnResize(thisGui, minMax, w, h) {
    if (minMax = -1)
        return
    ; The layout is fixed-position; keep it simple and let the tab area sit as
    ; laid out. A full fluid relayout is unnecessary for this utility window.
}
