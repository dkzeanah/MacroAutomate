; ===============================================================================
; Core\_Notifications.ahk
; Notifications: stackable windows, schedules, action/error reporting
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================



ExecuteShowNotification(params) {
    global g_ExtractedData

    parts := StrSplit(params, ",")
    if parts.Length < 2 {
        ShowStatus("ShowNotification format: Title,Message[,Timeout]", "fail")
        return false
    }

    title := parts[1]

    ; The last value is the timeout when numeric. Everything between the title
    ; and timeout is the message, so OCR text containing commas is not cut off.
    messageEnd := parts.Length
    timeout := 0
    if parts.Length >= 3 && IsNumber(Trim(parts[parts.Length])) {
        timeout := Integer(Trim(parts[parts.Length])) * 1000
        messageEnd--
    }
    message := ""
    Loop messageEnd - 1 {
        if A_Index > 1
            message .= ","
        message .= parts[A_Index + 1]
    }

    ; Substitute variables in message
    for varName, value in g_ExtractedData {
        if InStr(message, varName) {
            message := StrReplace(message, varName, value)
        }
    }

    ShowEnhancedNotification(title, message, timeout)
    return true
}

; ═══════════════════════════════════════════════════════════════════════════════
; SECTION 4: ENHANCED NOTIFICATION SYSTEM
; ═══════════════════════════════════════════════════════════════════════════════
; FEATURES:
;   • Right-click = Snooze (30min, 15min, 10min, 5min sequence)
;   • Double-click = Mark as "Done" and dismiss
;   • Clicks don't bleed through (proper GUI event handling)
;   • Visual feedback for snooze/done actions
; ═══════════════════════════════════════════════════════════════════════════════

ShowEnhancedNotification(title, message, timeout := 0) {
    ; Use the unified notification system
    ShowNotificationBasic(title, message, timeout, "info")
}

; Snooze notification (right-click)
SnoozeNotification(notifID) {
    global g_NotificationData

    if !g_NotificationData.Has(notifID)
        return

    data := g_NotificationData[notifID]

    ; Get next snooze duration
    if data["snoozeIndex"] >= data["snoozeSequence"].Length {
        snoozeMin := 5  ; Default to 5 min after sequence exhausted
    } else {
        snoozeMin := data["snoozeSequence"][data["snoozeIndex"] + 1]
        data["snoozeIndex"]++
    }

    ; Show snooze feedback
    ShowStatus("Notification snoozed for " . snoozeMin . " minutes", "ok")

    ; Hide notification
    try data["gui"].Hide()

    ; Set timer to re-show
    SetTimer(() => ReshowNotification(notifID), -snoozeMin * 60 * 1000)
}

; Re-show snoozed notification
ReshowNotification(notifID) {
    global g_NotificationData

    if !g_NotificationData.Has(notifID)
        return

    data := g_NotificationData[notifID]

    ; Re-show the notification
    try {
        data["gui"].Show("NoActivate")
        ShowStatus("Notification reminder: " . data["title"], "info")
    }
}

; Mark notification as done (double-click)
MarkNotificationDone(notifID) {
    global g_NotificationData, g_SpoolNotifications

    if !g_NotificationData.Has(notifID)
        return

    data := g_NotificationData[notifID]

    ; Visual feedback
    try {
        data["gui"].BackColor := "228B22"  ; Green
        Sleep(200)
    }

    ; Dismiss
    DismissNotification(notifID, data["gui"])

    ShowStatus("Notification marked as done", "ok")
}

; Dismiss notification permanently
DismissNotification(notifID, notifGui) {
    global g_NotificationData, g_SpoolNotifications

    ; Destroy GUI
    try notifGui.Destroy()

    ; Remove from tracking
    g_NotificationData.Delete(notifID)

    ; Remove from active list
    for i, notif in g_SpoolNotifications {
        if notif["id"] = notifID {
            g_SpoolNotifications.RemoveAt(i)
            break
        }
    }

    ; Reposition remaining notifications
    RepositionSpoolNotifications()
}

; Reposition all notifications after one is removed
RepositionSpoolNotifications() {
    global g_SpoolNotifications

    screenW := A_ScreenWidth
    screenH := A_ScreenHeight
    notifW := 400
    notifH := 120

    for i, notif in g_SpoolNotifications {
        stackOffset := (i - 1) * (notifH + 10)
        notifX := screenW - notifW - 20
        notifY := screenH - notifH - 50 - stackOffset

        try notif["gui"].Move(notifX, notifY)
    }
}

; Handle single click (do nothing, just prevent bleed-through)
NotificationSingleClick(notifID, *) {
    ; Just consume the click event to prevent bleed-through
    return
}

; ═══════════════════════════════════════════════════════════════════════════════
; SECTION 5: SMART CLIPBOARD REVOLVER WITH BINS
; ═══════════════════════════════════════════════════════════════════════════════
; FEATURES:
;   • Multiple bins for different formatting rules
;   • OCR-based routing (VSP vs EyeMed, etc.)
;   • Visual bin selection GUI when loading
;   • Format rules per bin (swap names, add date, etc.)
;   • Notification blocks during paste for verification
;   • Top bin processes first
; ═══════════════════════════════════════════════════════════════════════════════

; Initialize bins (call this during startup)

; ═══════════════════════════════════════════════════════════════════════════════

LoadNotificationSchedule() {
    global g_NotificationSchedule, SCHEDULE_FILE

    if !FileExist(SCHEDULE_FILE)
        return

    try {
        content := FileRead(SCHEDULE_FILE, "UTF-8")
        for line in StrSplit(content, "`n", "`r") {
            if line = "" || SubStr(line, 1, 1) = ";"
                continue

            parts := StrSplit(line, "|")
            if parts.Length >= 3 {
                timeSlot := parts[1]
                message := parts[2]
                enabled := (parts[3] = "1")

                g_NotificationSchedule[timeSlot] := Map(
                    "message", message,
                    "enabled", enabled,
                    "lastShown", ""
                )
            }
        }
    }
}

SaveNotificationSchedule() {
    global g_NotificationSchedule, SCHEDULE_FILE

    output := "; Notification Schedule (TimeSlot|Message|Enabled)`n"

    for timeSlot, data in g_NotificationSchedule {
        output .= timeSlot . "|" . data["message"] . "|" . (data["enabled"] ? "1" : "0") . "`n"
    }

    try {
        if FileExist(SCHEDULE_FILE)
            FileDelete(SCHEDULE_FILE)
        FileAppend(output, SCHEDULE_FILE, "UTF-8")
    }
}

CheckScheduledNotifications() {
    global g_NotificationSchedule, g_NotificationSettings

    currentTime := FormatTime(A_Now, "HH:mm")
    startTime := g_NotificationSettings["startTime"]
    endTime := g_NotificationSettings["endTime"]

    ; Convert times to minutes for proper comparison
    currentParts := StrSplit(currentTime, ":")
    currentMinutes := currentParts[1] * 60 + currentParts[2]

    startParts := StrSplit(startTime, ":")
    startMinutes := startParts[1] * 60 + startParts[2]

    endParts := StrSplit(endTime, ":")
    endMinutes := endParts[1] * 60 + endParts[2]

    if currentMinutes < startMinutes || currentMinutes > endMinutes
        return

    blockSize := g_NotificationSettings["blockSize"]
    currentParts := StrSplit(currentTime, ":")
    currentMinutes := currentParts[1] * 60 + currentParts[2]

    roundedMinutes := Floor(currentMinutes / blockSize) * blockSize
    roundedHour := Floor(roundedMinutes / 60)
    roundedMin := Mod(roundedMinutes, 60)
    roundedTime := Format("{:02d}:{:02d}", roundedHour, roundedMin)

    if g_NotificationSchedule.Has(roundedTime) {
        schedule := g_NotificationSchedule[roundedTime]
        if schedule["enabled"] && schedule["lastShown"] != A_YYYY A_MM A_DD {
            ShowScheduledNotification(schedule["message"])
            schedule["lastShown"] := A_YYYY A_MM A_DD
        }
    }
}

ShowScheduledNotification(message) {
    ShowNotificationBasic("Scheduled Reminder", message, 8000)
}

ShowActionNotification(actionType, status, details := "", errorInfo := "") {
    global g_NotificationSettings, g_ActionErrors, g_NotificationHistory, g_DebugMode

    ; In debug mode, show all notifications; otherwise respect settings
    if !g_DebugMode && !g_NotificationSettings["showErrors"] && status = "error"
        return

    title := "Step: " . actionType

    message := ""
    if status = "error" {
        message .= details
        if errorInfo != ""
            message .= "`n`nError: " . errorInfo

        if !g_ActionErrors.Has(actionType)
            g_ActionErrors[actionType] := []
        g_ActionErrors[actionType].Push(Map(
            "time", A_Now,
            "details", details,
            "error", errorInfo
        ))
    }
    else if status = "success" {
        message .= details
    }
    else if status = "warning" {
        message .= details
    }

    g_NotificationHistory.Push(Map(
        "time", A_Now,
        "action", actionType,
        "status", status,
        "message", message
    ))

    ; All notifications dismissible by default, success can auto-dismiss in 3 seconds if not in debug mode
    timeout := (status = "success" && !g_DebugMode) ? 3000 : 0
    ShowNotificationBasic(title, message, timeout, status)
}


ShowNotificationBasic(title, message, timeout := 0, status := "info", copyData := "", stepIndex := 0) {
    global g_NotificationStack, g_NotificationDismissible, g_NotificationTimeout, g_CurrentSequenceSteps

    ; Use global settings if timeout not specified
    if timeout = 0 && !g_NotificationDismissible
        timeout := g_NotificationTimeout

    ; Create notification GUI with proper drag capability
    notifGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "Notification")

    ; Color based on status
    bgColor := "0x1a1a1a"
    topBarColor := "0x2a2a2a"  ; Lighter for top bar
    if status = "success" {
        bgColor := "0x0d3d0d"  ; Dark green
        topBarColor := "0x1d5d1d"  ; Lighter green for top bar
    } else if status = "error" {
        bgColor := "0x3d0d0d"  ; Dark red
        topBarColor := "0x5d1d1d"  ; Lighter red for top bar
    } else if status = "warning" {
        bgColor := "0x3d3d0d"  ; Dark yellow
        topBarColor := "0x5d5d1d"  ; Lighter yellow for top bar
    }

    notifGui.BackColor := bgColor

    ; Status icon
    statusIcon := "⬤"
    if status = "success"
        statusIcon := "✓"
    else if status = "error"
        statusIcon := "✗"
    else if status = "warning"
        statusIcon := "⚠"

    ; Top bar with lighter background (draggable area)
    notifGui.SetFont("s10 cWhite Bold", "Segoe UI")
    topBar := notifGui.Add("Text", "x0 y0 w320 h30 Background" . topBarColor . " Center", "")

    ; Title on top bar
    titleCtrl := notifGui.Add("Text", "x10 y7 w250 cWhite Background" . topBarColor, statusIcon . " " . title)

    ; Add mute/unmute toggle button if this is a step notification
    if stepIndex > 0 {
        notifGui.SetFont("s9 Bold", "Segoe UI")
        muteBtn := notifGui.Add("Text", "x270 y5 w40 h20 cWhite Background" . topBarColor . " Center Border", "🔔")
        muteBtn.stepIndex := stepIndex
        muteBtn.notifGui := notifGui

        ; Check if this step is muted
        if stepIndex <= g_CurrentSequenceSteps.Length {
            step := g_CurrentSequenceSteps[stepIndex]
            if step.Has("notificationMuted") && step["notificationMuted"] {
                muteBtn.Text := "🔕"
            }
        }

        muteBtn.OnEvent("Click", ToggleStepNotification)
    }

    ; Add scrollable message (use Edit for scrolling)
    notifGui.SetFont("s9 cWhite Norm", "Segoe UI")
    messageLines := StrSplit(message, "`n")
    messageHeight := Min(messageLines.Length * 18, 200)  ; Max 200px height
    msgCtrl := notifGui.Add("Edit", "x10 y35 w300 h" . messageHeight . " cWhite Background" . bgColor . " ReadOnly -E0x200 Multi", message)

    yPos := 35 + messageHeight + 5

    ; Add copy button if copyData is provided
    if copyData != "" {
        notifGui.SetFont("s8", "Segoe UI")
        copyBtn := notifGui.Add("Button", "x10 y" . yPos . " w80 h22", "📋 Copy")
        copyBtn.OnEvent("Click", (*) => CopyNotificationData(copyData))
        yPos += 27
    }

    ; Add dismiss instruction
    notifGui.SetFont("s8 c808080", "Segoe UI")
    dismissCtrl := notifGui.Add("Text", "x10 y" . yPos . " w300 Background" . bgColor, "Drag top bar to move | Right-click to dismiss")

    ; Enable dragging on top bar
    topBar.OnEvent("Click", (*) => PostMessage(0xA1, 2, 0, , notifGui.Hwnd))
    titleCtrl.OnEvent("Click", (*) => PostMessage(0xA1, 2, 0, , notifGui.Hwnd))

    ; Right-click or double-click to dismiss
    for ctrl in notifGui {
        try ctrl.OnEvent("DoubleClick", (*) => RemoveNotification(notifGui))
        try ctrl.OnEvent("ContextMenu", (*) => RemoveNotification(notifGui))
    }

    notifGui.OnEvent("Close", (*) => RemoveNotification(notifGui))

    ; Add to stack
    g_NotificationStack.Push(notifGui)
    RepositionNotifications()

    ; Auto-dismiss timer
    if timeout > 0
        SetTimer(() => RemoveNotification(notifGui), -timeout)

    return notifGui
}

ToggleStepNotification(ctrl, *) {
    global g_CurrentSequenceSteps

    stepIndex := ctrl.stepIndex
    if stepIndex <= 0 || stepIndex > g_CurrentSequenceSteps.Length
        return

    step := g_CurrentSequenceSteps[stepIndex]

    ; Toggle muted state
    if step.Has("notificationMuted") && step["notificationMuted"] {
        step["notificationMuted"] := false
        ctrl.Text := "🔔"
        ShowStatus("Step " . stepIndex . " notifications enabled", "ok")
    } else {
        step["notificationMuted"] := true
        ctrl.Text := "🔕"
        ShowStatus("Step " . stepIndex . " notifications muted", "ok")
    }

    ; Close this notification
    try ctrl.notifGui.Destroy()
}

CopyNotificationData(data) {
    A_Clipboard := data
    ShowStatus("Copied to clipboard: " . SubStr(data, 1, 50) . (StrLen(data) > 50 ? "..." : ""), "ok")
}

; Drag notification is no longer needed - handled by title click

RemoveNotification(notifGui) {
    global g_NotificationStack

    try {
        if !notifGui
            return

        ; Remove from stack
        for i, gui in g_NotificationStack {
            if gui = notifGui {
                g_NotificationStack.RemoveAt(i)
                break
            }
        }

        notifGui.Destroy()
        RepositionNotifications()
    }
}

RepositionNotifications() {
    global g_NotificationStack

    if g_NotificationStack.Length = 0
        return

    screenW := A_ScreenWidth
    screenH := A_ScreenHeight
    guiW := 320
    spacing := 10
    bottomMargin := 60

    currentY := screenH - bottomMargin

    ; Stack from bottom up (newest at bottom)
    i := g_NotificationStack.Length
    while i >= 1 {
        try {
            notifGui := g_NotificationStack[i]

            ; Get actual GUI height
            notifGui.GetPos(,, &actualW, &actualH)
            guiH := actualH > 0 ? actualH : 180

            xPos := screenW - guiW - 20
            currentY -= guiH

            ; Ensure notification stays on screen
            if currentY < 10 {
                ; If we run out of vertical space, start a new column to the left
                xPos -= (guiW + spacing)
                currentY := screenH - bottomMargin - guiH
            }

            notifGui.Show("x" . xPos . " y" . currentY . " w" . guiW . " NoActivate")
            currentY -= spacing
        }
        i--
    }
}

ClearAllNotifications(*) {
    global g_NotificationStack

    for notifGui in g_NotificationStack {
        try notifGui.Destroy()
    }

    g_NotificationStack := []
}

; Global variable for notification GUI
global g_NotificationGui := ""

StartNotificationTimer() {
    LoadNotificationSchedule()
    SetTimer(CheckScheduledNotifications, 60000)
}

