; ===============================================================================
; Tabs\Tab_10_Settings.ahk
; TAB 10 Settings: timing, verification, notification settings
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================


SaveSettings() {
    global g_Settings, SETTINGS_FILE
    for k, v in g_Settings
        IniWrite(v, SETTINGS_FILE, "Settings", k)
}

LoadSettings() {
    global g_Settings, SETTINGS_FILE
    if !FileExist(SETTINGS_FILE)
        return
    for k, def in g_Settings.Clone()
        g_Settings[k] := IsNumber(def) ? Number(IniRead(SETTINGS_FILE, "Settings", k, def)) : IniRead(SETTINGS_FILE, "Settings", k, def)
}

Tab_Settings_Build() {
    TabCtrl.UseTab(10)

    MainGui.Add("GroupBox", "x15 y50 w350 h100", "Timing (ms)")
    MainGui.Add("Text", "x25 y70", "Click:")
    MainGui.Add("Edit", "x65 yp-3 w45 vClickDelay Number", g_Settings["ClickDelay"])
    MainGui.Add("Text", "x115 yp+3", "Type:")
    MainGui.Add("Edit", "x150 yp-3 w45 vTypeDelay Number", g_Settings["TypeDelay"])
    MainGui.Add("Text", "x200 yp+3", "Action:")
    MainGui.Add("Edit", "x245 yp-3 w45 vActionDelay Number", g_Settings["ActionDelay"])
    MainGui.Add("Text", "x25 y100", "Pre:")
    MainGui.Add("Edit", "x55 yp-3 w45 vPreActionDelay Number", g_Settings["PreActionDelay"])
    MainGui.Add("Text", "x105 yp+3", "Post:")
    MainGui.Add("Edit", "x140 yp-3 w45 vPostActionDelay Number", g_Settings["PostActionDelay"])
    MainGui.Add("Text", "x190 yp+3", "Drag:")
    MainGui.Add("Edit", "x225 yp-3 w45 vDragTime Number", g_Settings["DefaultDragTime"])

    MainGui.Add("GroupBox", "x15 y155 w350 h70", "Tooltips")
    MainGui.Add("Text", "x25 y175", "Status Duration:")
    MainGui.Add("Edit", "x115 yp-3 w50 vTooltipDuration Number", g_Settings["TooltipDuration"])
    MainGui.Add("Text", "x170 yp+3", "ms")
    MainGui.Add("Text", "x25 y200", "Preview Duration:")
    MainGui.Add("Edit", "x115 yp-3 w50 vPreviewTooltipDuration Number", g_Settings["PreviewTooltipDuration"])
    MainGui.Add("Text", "x170 yp+3", "ms")

    MainGui.Add("GroupBox", "x15 y230 w350 h70", "Verification")
    MainGui.Add("Text", "x25 y250", "Max Retries:")
    MainGui.Add("Edit", "x95 yp-3 w40 vMaxRetries Number", g_Settings["MaxRetries"])
    MainGui.Add("Text", "x145 yp+3", "Win Timeout:")
    MainGui.Add("Edit", "x220 yp-3 w50 vWindowActivateTimeout Number", g_Settings["WindowActivateTimeout"])

    MainGui.Add("GroupBox", "x15 y305 w350 h70", "FindText")
    MainGui.Add("Text", "x25 y325", "Tolerance:")
    MainGui.Add("Edit", "x80 yp-3 w50 vFindTextTolerance", g_Settings["FindTextTolerance"])
    MainGui.Add("Text", "x135 yp+3", "(0-1)")
    MainGui.Add("Text", "x180 yp", "Timeout:")
    MainGui.Add("Edit", "x230 yp-3 w50 vFindTextTimeout Number", g_Settings["FindTextTimeout"])

    MainGui.Add("GroupBox", "x15 y380 w350 h75", "Failsafes")
    MainGui.Add("CheckBox", "x25 y398 vFailsafeCheckCloseButton Checked", "Block clicks near window close buttons")
    MainGui.Add("CheckBox", "x25 y418 vAutoCapPattern Checked", "Auto-capture patterns on recording")
    MainGui.Add("CheckBox", "x25 y438 vDefModeAutoPattern Checked", "Definition Mode auto-pattern capture")

    ; Notification Settings
    MainGui.Add("GroupBox", "x380 y380 w200 h95", "Notifications")
    MainGui.Add("CheckBox", "x390 y400 vDebugMode Checked", "Debug Mode (show all steps)")
    MainGui.Add("CheckBox", "x390 y420 vNotifDismissible Checked", "Dismissible (stay until clicked)")
    MainGui.Add("Text", "x390 y440", "Auto-dismiss:")
    MainGui.Add("Edit", "x465 y437 w40 vNotifTimeout Number", "5")
    MainGui.Add("Text", "x510 y440", "sec")

    MainGui.Add("Button", "x15 y465 w80 h24", "Save").OnEvent("Click", SaveSettingsGUI)
    MainGui.Add("Button", "x100 yp w80 h24", "Reset").OnEvent("Click", ResetSettingsGUI)
    MainGui.Add("Button", "x185 yp w100 h24", "Open Folder").OnEvent("Click", (*) => Run(DATA_DIR))

    ; Reference
    MainGui.Add("GroupBox", "x380 y50 w490 h405", "Reference")
    MainGui.Add("Text", "x390 y70", "DEFINITION MODE (CAPSLOCK ON):")
    MainGui.Add("Text", "x390 y85 cBlue", "  C=Click  D=Drag(2x)  R=RightClick  T=Triple")
    MainGui.Add("Text", "x390 y100 cBlue", "  P=Pattern  W=Wait  K=SendKeys  M=MenuSelect")
    MainGui.Add("Text", "x390 y115 cBlue", "  ESC=Cancel/Hide tooltip")
    MainGui.Add("Text", "x390 y140", "SEND KEYS: ^=Ctrl +=Shift !=Alt #=Win")
    MainGui.Add("Text", "x390 y155", "  ^c=Ctrl+C  ^v=Ctrl+V  !d=Alt+D  #1=Win+1")
    MainGui.Add("Text", "x390 y180", "FIND ACTIONS:")
    MainGui.Add("Text", "x390 y195", "  Find & Click/DblClick/TplClick/RClick/Drag")
    MainGui.Add("Text", "x390 y210", "  Wait for Pattern / Wait Until Gone")
    MainGui.Add("Text", "x390 y235", "GLOBAL HOTKEYS:")
    MainGui.Add("Text", "x390 y250", "  Ctrl+Shift+G - Toggle window")
    MainGui.Add("Text", "x390 y265", "  Ctrl+Shift+P - Pause/Resume")
    MainGui.Add("Text", "x390 y280", "  Ctrl+Shift+X - Abort sequence")
    MainGui.Add("Text", "x390 y295", "  Ctrl+Shift+C - Clear notifications")
    MainGui.Add("Text", "x390 y310", "  Ctrl+Shift+F - FindText GUI")
    MainGui.Add("Text", "x390 y325", "  Ctrl+B - Load revolver (copy+parse)")
    MainGui.Add("Text", "x390 y340", "  Ctrl+Shift+B - Fire all shots")
    MainGui.Add("Text", "x390 y360", "TASKBAR:")
    MainGui.Add("Text", "x390 y375", "  Analytics tab -> Index Taskbar button")
    MainGui.Add("Text", "x390 y390", "  Saved to data/taskbar.ini")
    MainGui.Add("Text", "x390 y410", "REVOLVER (Clipboard tab):")
    MainGui.Add("Text", "x390 y425", "  Configure field order with ▲▼ buttons")
    MainGui.Add("Text", "x390 y445", "VISUAL: Green=OK, Blue=Progress, Red=Fail")


}





; ═══════════════════════════════════════════════════════════════════════════════
; SETTINGS
; ═══════════════════════════════════════════════════════════════════════════════
; SETTINGS
; =============================================================================

SaveSettingsGUI(*) {
    global g_Settings, g_NotificationDefaults
    saved := MainGui.Submit(false)
    g_Settings["ClickDelay"] := Integer(saved.ClickDelay)
    g_Settings["TypeDelay"] := Integer(saved.TypeDelay)
    g_Settings["ActionDelay"] := Integer(saved.ActionDelay)
    g_Settings["PreActionDelay"] := Integer(saved.PreActionDelay)
    g_Settings["PostActionDelay"] := Integer(saved.PostActionDelay)
    g_Settings["DefaultDragTime"] := Integer(saved.DragTime)
    g_Settings["MaxRetries"] := Integer(saved.MaxRetries)
    g_Settings["WindowActivateTimeout"] := Integer(saved.WindowActivateTimeout)
    g_Settings["FindTextTolerance"] := Number(saved.FindTextTolerance)
    g_Settings["FindTextTimeout"] := Integer(saved.FindTextTimeout)
    g_Settings["TooltipDuration"] := Integer(saved.TooltipDuration)
    g_Settings["PreviewTooltipDuration"] := Integer(saved.PreviewTooltipDuration)
    g_Settings["FailsafeCheckCloseButton"] := saved.FailsafeCheckCloseButton
    g_Settings["AutoCapturePattern"] := saved.AutoCapPattern
    g_Settings["DefinitionModeAutoPattern"] := saved.DefModeAutoPattern

    ; Save notification settings
    global g_DebugMode, g_NotificationDismissible, g_NotificationTimeout
    g_DebugMode := saved.DebugMode
    g_NotificationDismissible := saved.NotifDismissible
    g_NotificationTimeout := Integer(saved.NotifTimeout) * 1000
    g_NotificationDefaults["timeout"] := Integer(saved.NotifTimeout)
    g_Settings["DebugMode"] := saved.DebugMode
    g_Settings["NotificationDismissible"] := saved.NotifDismissible
    g_Settings["NotificationTimeout"] := Integer(saved.NotifTimeout)

    SaveSettings()
    StatusBar.SetText("Settings saved!")
    ShowNotificationBasic("Settings Saved", "All settings have been updated", 2000, "success")
}

ResetSettingsGUI(*) {
    global g_Settings
    g_Settings := Map(
        "ClickDelay", 100, "TypeDelay", 50, "ActionDelay", 150, "DefaultDragTime", 300,
        "DateFormat", "MM/dd/yyyy", "ShowActionTooltips", true, "TooltipDuration", 1500,
        "MarkerOffsetX", -12, "MarkerOffsetY", -15, "MaxRetries", 3, "VerifyTimeout", 2000,
        "VerifyInterval", 100, "PreActionDelay", 50, "PostActionDelay", 100,
        "WindowActivateTimeout", 3000, "FindTextTolerance", 0.1, "FindTextTimeout", 5000,
        "AutoCapturePattern", true, "FailsafeCheckCloseButton", true, "DefinitionModeAutoPattern", true,
        "PreviewTooltipDuration", 3000, "SpoolMasterEnabled", false
    )
    SaveSettings()
    StatusBar.SetText("Reset - restart to apply")
}


; Notification Settings GUI
ShowNotificationSettings(*) {
    global g_NotificationDefaults

    settingsGui := Gui("+AlwaysOnTop", "Notification Settings")
    settingsGui.SetFont("s9", "Segoe UI")

    settingsGui.Add("GroupBox", "x10 y10 w400 h120", "Default Notification Behavior")

    settingsGui.Add("Text", "x20 y30", "Default Duration:")
    durationEdit := settingsGui.Add("Edit", "x120 y27 w60", g_NotificationDefaults["timeout"])
    settingsGui.Add("Text", "x185 y30", "ms (0 = manual dismiss)")

    settingsGui.Add("CheckBox", "x20 y55 vDismissible " . (g_NotificationDefaults["dismissible"] ? "Checked" : ""), "Notifications stay until dismissed")
    settingsGui.Add("CheckBox", "x20 y80 vStackNotifications " . (g_NotificationDefaults["stack"] ? "Checked" : ""), "Stack multiple notifications")
    settingsGui.Add("CheckBox", "x20 y105 vSoundEnabled " . (g_NotificationDefaults["sound"] ? "Checked" : ""), "Play sound on notification")

    settingsGui.Add("GroupBox", "x10 y140 w400 h140", "Notification Position")
    settingsGui.Add("Radio", "x20 y160 vPosBottomRight " . (g_NotificationDefaults["position"] = "bottom-right" ? "Checked" : ""), "Bottom Right (default)")
    settingsGui.Add("Radio", "x20 y185 vPosBottomLeft", "Bottom Left")
    settingsGui.Add("Radio", "x20 y210 vPosTopRight", "Top Right")
    settingsGui.Add("Radio", "x20 y235 vPosTopLeft", "Top Left")
    settingsGui.Add("Radio", "x20 y260 vPosCenter", "Center")

    settingsGui.Add("GroupBox", "x10 y290 w400 h100", "Color Scheme")
    settingsGui.Add("Text", "x20 y310", "Success:")
    settingsGui.Add("Edit", "x75 y307 w80", g_NotificationDefaults.Has("color_success") ? g_NotificationDefaults["color_success"] : "0x0d3d0d")
    settingsGui.Add("Text", "x20 y340", "Error:")
    settingsGui.Add("Edit", "x75 y337 w80", g_NotificationDefaults.Has("color_error") ? g_NotificationDefaults["color_error"] : "0x3d0d0d")
    settingsGui.Add("Text", "x20 y370", "Warning:")
    settingsGui.Add("Edit", "x75 y367 w80", g_NotificationDefaults.Has("color_warning") ? g_NotificationDefaults["color_warning"] : "0x3d3d0d")

    settingsGui.Add("Text", "x220 y310", "Info:")
    settingsGui.Add("Edit", "x260 y307 w80", g_NotificationDefaults.Has("color_info") ? g_NotificationDefaults["color_info"] : "0x1a1a1a")

    settingsGui.Add("Button", "x10 y400 w150 h30", "Save Settings").OnEvent("Click", SaveNotifSettings)
    settingsGui.Add("Button", "x170 y400 w150 h30", "Reset to Defaults").OnEvent("Click", ResetNotifSettings)
    settingsGui.Add("Button", "x260 y440 w150 h30", "Close").OnEvent("Click", (*) => settingsGui.Destroy())

    SaveNotifSettings(*) {
        saved := settingsGui.Submit(false)

        g_NotificationDefaults["timeout"] := Integer(durationEdit.Value)
        g_NotificationDefaults["dismissible"] := saved.Dismissible
        g_NotificationDefaults["stack"] := saved.StackNotifications
        g_NotificationDefaults["sound"] := saved.SoundEnabled

        ; Determine position
        if saved.PosBottomRight
            g_NotificationDefaults["position"] := "bottom-right"
        else if saved.PosBottomLeft
            g_NotificationDefaults["position"] := "bottom-left"
        else if saved.PosTopRight
            g_NotificationDefaults["position"] := "top-right"
        else if saved.PosTopLeft
            g_NotificationDefaults["position"] := "top-left"
        else if saved.PosCenter
            g_NotificationDefaults["position"] := "center"

        ShowNotificationBasic("Settings Saved", "Notification preferences updated", 2000, "success")
    }

    ResetNotifSettings(*) {
        g_NotificationDefaults["timeout"] := 5000
        g_NotificationDefaults["dismissible"] := true
        g_NotificationDefaults["stack"] := true
        g_NotificationDefaults["sound"] := false
        g_NotificationDefaults["position"] := "bottom-right"

        ShowNotificationBasic("Settings Reset", "Notification preferences reset to defaults", 2000, "success")
        settingsGui.Destroy()
    }

    settingsGui.Show("w420 h485")
}

