; ═══════════════════════════════════════════════════════════════════════════════
; AutoFlow.ahk - Make hand-placed tabs resize without rewriting them
; ═══════════════════════════════════════════════════════════════════════════════
; Every tab in this application was laid out with absolute coordinates. That is
; fine at the size it was designed for and useless at any other: maximise the
; window and the controls stay huddled in the top-left corner.
;
; Rewriting sixteen tabs by hand is not the answer. Instead this records each
; control's original geometry once, infers how it was MEANT to behave from where
; it sits, and re-applies that on every resize:
;
;   a control whose right edge sits near the original right edge was meant to
;   reach the edge - so it either stretches (if it is wide) or is pinned to the
;   right (if it is a button)
;
;   the same reasoning applies vertically for lists and multi-line boxes
;
; It is inference, not magic: a control in the middle of the window has no
; expressed intent and is left where it is. That still leaves every table, edit
; box and edge-anchored button using the full window.
;
; Tabs that lay themselves out properly (Snapshot Recovery) register their
; controls as exempt and are skipped entirely.
; ═══════════════════════════════════════════════════════════════════════════════

global g_FlowItems := []          ; captured geometry, one entry per control
global g_FlowBaseW := 0, g_FlowBaseH := 0
global g_FlowOn := false

; Record the layout as designed. Call once, after every tab is built, with the
; client size the coordinates were authored against.
AutoFlow_Init(gui, baseW := 0, baseH := 0, skip := "") {
    global g_FlowItems, g_FlowBaseW, g_FlowBaseH, g_FlowOn
    g_FlowItems := []

    exempt := Map()
    if IsObject(skip) {
        for , ctl in skip {
            try exempt[ctl.Hwnd] := true
        }
    }

    ; First pass: gather geometry. The design width is measured from the
    ; controls themselves rather than assumed from the window - the tabs were
    ; authored against the tab's inner area, so judging "near the right edge"
    ; against the window width marks everything as fixed and nothing stretches.
    raw := []
    for ctl in gui {
        hwnd := 0
        try hwnd := ctl.Hwnd
        if (!hwnd || exempt.Has(hwnd))
            continue
        type := ""
        try type := ctl.Type
        if (type = "Tab" || type = "Tab2" || type = "Tab3" || type = "StatusBar")
            continue
        x := 0, y := 0, w := 0, h := 0
        try ctl.GetPos(&x, &y, &w, &h)
        if (w <= 0 || h <= 0)
            continue
        raw.Push(Map("ctl", ctl, "type", type, "x", x, "y", y, "w", w, "h", h))
    }
    if !raw.Length {
        g_FlowOn := false
        return 0
    }
    maxRight := 0, maxBottom := 0
    for , r in raw {
        maxRight := Max(maxRight, r["x"] + r["w"])
        maxBottom := Max(maxBottom, r["y"] + r["h"])
    }
    baseW := (baseW > 0) ? Min(baseW, maxRight + 20) : maxRight + 20
    baseH := (baseH > 0) ? Min(baseH, maxBottom + 20) : maxBottom + 20
    g_FlowBaseW := baseW, g_FlowBaseH := baseH

    for , r in raw {
        ctl := r["ctl"], type := r["type"]
        x := r["x"], y := r["y"], w := r["w"], h := r["h"]

        rightGap := baseW - (x + w)
        bottomGap := baseH - (y + h)
        ; "Near the edge" is generous: these layouts were eyeballed, not aligned
        ; to a grid, so a control 40px short of the edge still meant the edge.
        nearRight := (rightGap < 55)
        nearBottom := (bottomGap < 60)
        stretchy := (type = "ListView" || type = "Edit" || type = "GroupBox"
                  || type = "ListBox" || type = "TreeView" || type = "Picture")

        hMode := "fixed"
        if (nearRight && stretchy && w > 160)
            hMode := "stretch"
        else if nearRight
            hMode := "pin"

        vMode := "fixed"
        if (nearBottom && stretchy && h > 90)
            vMode := "stretch"
        else if nearBottom
            vMode := "pin"

        g_FlowItems.Push(Map("ctl", ctl, "x", x, "y", y, "w", w, "h", h
                           , "hMode", hMode, "vMode", vMode))
    }
    g_FlowOn := true
    ; Report how many controls were held back, so an exemption that silently
    ; failed to apply is visible in the log rather than only on screen.
    try LogDiagnostic("AutoFlow exempted " . exempt.Count . " control(s) from reflow"
                    , "AutoFlow", "INFO")
    return g_FlowItems.Length
}

; Re-apply the inferred behaviour for a new client size.
AutoFlow_Resize(w, h) {
    global g_FlowItems, g_FlowBaseW, g_FlowBaseH, g_FlowOn
    static logged := 0
    if (!g_FlowOn || !g_FlowItems.Length || g_FlowBaseW <= 0)
        return
    ; Record the largest size actually seen, once, so a layout that fails to
    ; use the screen can be diagnosed from the log rather than by eye.
    if (w > logged + 200) {
        logged := w
        try LogDiagnostic("AutoFlow resize to " . w . "x" . h
                        . " (base " . g_FlowBaseW . "x" . g_FlowBaseH
                        . ", growth " . (w - g_FlowBaseW) . "px)", "AutoFlow", "INFO")
    }
    dW := w - g_FlowBaseW
    dH := h - g_FlowBaseH
    if (dW = 0 && dH = 0)
        return
    ; Never shrink past the design size - below that the original layout is
    ; already the tightest arrangement that fits.
    if (dW < 0)
        dW := 0
    if (dH < 0)
        dH := 0

    for , it in g_FlowItems {
        nx := it["x"], ny := it["y"], nw := it["w"], nh := it["h"]
        switch it["hMode"] {
            case "stretch": nw := it["w"] + dW
            case "pin":     nx := it["x"] + dW
        }
        switch it["vMode"] {
            case "stretch": nh := it["h"] + dH
            case "pin":     ny := it["y"] + dH
        }
        try it["ctl"].Move(nx, ny, nw, nh)
    }
}

; How many controls were captured, and how they will behave - useful when
; checking that a tab actually gained something.
AutoFlow_Report() {
    global g_FlowItems
    counts := Map("stretch-h", 0, "pin-h", 0, "stretch-v", 0, "pin-v", 0, "fixed", 0)
    for , it in g_FlowItems {
        moved := false
        if (it["hMode"] = "stretch")
            counts["stretch-h"]++, moved := true
        else if (it["hMode"] = "pin")
            counts["pin-h"]++, moved := true
        if (it["vMode"] = "stretch")
            counts["stretch-v"]++, moved := true
        else if (it["vMode"] = "pin")
            counts["pin-v"]++, moved := true
        if !moved
            counts["fixed"]++
    }
    out := ""
    for k, v in counts
        out .= (out = "" ? "" : ", ") . k . "=" . v
    return g_FlowItems.Length . " controls (" . out . ")"
}
