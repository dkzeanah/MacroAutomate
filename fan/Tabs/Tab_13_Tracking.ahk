; ===============================================================================
; Tabs\Tab_13_Tracking.ahk
; TAB 13 Tracking: tracker glue + element actions (UI from lib\TrackingDashboard.ahk)
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================


TrackingOnExit(ExitReason, ExitCode) {
    try VisionScout_Shutdown()
    ; Both learners share tracking.db, so flush them before the tracking layer
    ; closes its connection.
    try UsagePredictor_Stop()
    try Track_ShutdownAll()
    return 0
}

Tab_Tracking_Build() {
    TabCtrl.UseTab(13)
    ; Open the tracking database and restore saved options before building controls.
    try Track_InitAll()
    catch as err
        LogErrorToFile(err, "caught", "Tracking subsystem initialization")
    try Track_BuildTab(MainGui)
    catch as err
        LogErrorToFile(err, "caught", "Tracking tab construction")

}


; SHOW NOTIFICATION - Display notification (dismissable, snoozeable)
; Format: "ShowNotification,Title,Message[,Timeout]"
; ═══════════════════════════════════════════════════════════════════════════════
; TRACKING WORKFLOW ACTIONS
; ═══════════════════════════════════════════════════════════════════════════════
; Bridge the workflow engine to the tracking subsystem. Element targets are
; addressed by the name given in the Snapshot Viewer (Tracking tab); research
; actions operate on the current query context (see lib\ResearchPipeline.ahk).
; =============================================================================

; Click Element - TARGET: element name | PARAM: Left/Right/Middle[,count]
ExecuteClickElement(target, param) {
    hasTarget := (target != "" && target != "(none)")
    name := hasTarget ? target : param
    if (name = "") {
        ShowStatus("Click Element: no element name", "fail")
        return false
    }
    button := "Left", count := 1
    ; When the name came from TARGET, PARAM may hold "Right" or "Right,2".
    spec := hasTarget ? param : ""
    if (spec != "") {
        parts := StrSplit(spec, ",")
        b := Trim(parts[1])
        if (b != "")
            button := b
        if (parts.Length >= 2 && IsInteger(Trim(parts[2])))
            count := Integer(Trim(parts[2]))
    }
    return Element_ClickByName(name, button, count)
}

; Wait Element - TARGET: element name | PARAM: timeout ms (default 5000)
ExecuteWaitElement(target, param) {
    name := (target != "" && target != "(none)") ? target : param
    if (name = "")
        return false
    timeout := (Trim(param) != "" && IsInteger(Trim(param))) ? Integer(Trim(param)) : 5000
    loc := Element_WaitByName(name, timeout)
    if (loc = "" || !loc.Count) {
        ShowStatus("Wait Element: '" . name . "' did not appear", "fail")
        return false
    }
    ShowStatus("Element appeared: " . name, "ok")
    return true
}

; Replay Window Mouse - TARGET: tracked window name | PARAM: [speed][,clicks]
; Replays that window's most recent recorded mouse snapshot.
ExecuteReplayWindowMouse(target, param) {
    if (target = "" || target = "(none)") {
        ShowStatus("Replay Window Mouse: no window name", "fail")
        return false
    }
    winId := TrackDB_FindWinByName(target)
    if !winId {
        ShowStatus("No tracked window named '" . target . "'", "fail")
        return false
    }
    snaps := MouseTrack_Snapshots(winId, 1)
    if !snaps.Length {
        ShowStatus("No mouse snapshots for '" . target . "'", "fail")
        return false
    }
    speed := 1.0, doClicks := false
    if (param != "") {
        parts := StrSplit(param, ",")
        if (Trim(parts[1]) != "" && IsNumber(Trim(parts[1])))
            speed := Float(Trim(parts[1]))
        if (parts.Length >= 2 && (Trim(parts[2]) = "1" || StrLower(Trim(parts[2])) = "clicks"))
            doClicks := true
    }
    hwnd := Element_FindLiveWindow(target)
    ; manageEsc:=false - the running sequence already owns the Escape hotkey.
    n := MouseTrack_Replay(snaps[1]["id"], speed, hwnd, doClicks, false)
    ShowStatus("Replayed " . n . " mouse points for '" . target . "'", "ok")
    return n > 0
}

; Research Capture Links - PARAM: "screen" (OCR the page) or "clip" (clipboard)
ExecuteResearchCaptureLinks(param) {
    global g_ResQueryId
    if !g_ResQueryId {
        ShowStatus("Research: no active query (use Research Search first)", "fail")
        return false
    }
    mode := StrLower(Trim(param))
    n := (mode = "clip" || mode = "clipboard")
        ? Research_CaptureLinksFromClipboard(g_ResQueryId)
        : Research_CaptureLinksFromScreen(g_ResQueryId)
    ShowStatus("Research: captured " . n . " links", "ok")
    return true
}

; Names of every registered element, for the workflow action dropdowns.
GetTrackedElementNames() {
    names := []
    if !TrackDB_Ready()
        return ["(define elements in the Snapshot Viewer first)"]
    for el in TrackDB_Elements(0)
        names.Push(el["name"])
    if !names.Length
        names.Push("(define elements in the Snapshot Viewer first)")
    return names
}

; Refresh the cached element-name list (called by the viewer after an edit).
UpdateElementActionChoices() {
    global g_ElementNames
    g_ElementNames := []
    if !TrackDB_Ready()
        return
    for el in TrackDB_Elements(0)
        g_ElementNames.Push(el["name"])
}

; Toggle every tracker together from a hotkey, mirroring the master button.
Track_ToggleAllHotkey() {
    if (WinTrack_IsOn() || MouseTrack_IsOn() || KeyTrack_IsOn() || Snap_IsOn())
        Track_StopAll()
    else
        Track_StartAll()
}


AutoFlow_FirstPass() {
    try {
        MainGui.GetClientPos(, , &cw, &ch)
        if (cw > 0 && ch > 0)
            GuiResize(MainGui, 0, cw, ch)
    }
}

