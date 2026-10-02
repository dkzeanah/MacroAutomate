; ===============================================================================
; Tabs\Tab_08_Hotstrings.ahk
; TAB 8 Hotstrings: text expansion management
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================

Tab_Hotstrings_Build() {
    global HotstringLV, HotstringMasterToggle
    TabCtrl.UseTab(8)

    MainGui.Add("GroupBox", "x15 y50 w860 h50", "Hotstring Management - Text Expansion & Auto-Replacement")
    MainGui.Add("Text", "x25 y68 w840", "Define text shortcuts that automatically expand when typed. Example: typing 'btw' expands to 'by the way'")

    MainGui.Add("GroupBox", "x15 y105 w860 h40", "Master Control")
    HotstringMasterToggle := MainGui.Add("CheckBox", "x25 y120 Checked", "Enable All Hotstrings")
    HotstringMasterToggle.OnEvent("Click", ToggleAllHotstrings)

    global HotstringLV := MainGui.Add("ListView", "x15 y150 w860 h300", ["Enabled", "Trigger", "Replacement", "Options"])
    HotstringLV.ModifyCol(1, 60)
    HotstringLV.ModifyCol(2, 150)
    HotstringLV.ModifyCol(3, 450)
    HotstringLV.ModifyCol(4, 180)
    HotstringLV.OnEvent("DoubleClick", EditHotstring)

    MainGui.Add("Button", "x15 y460 w100 h24", "Add New").OnEvent("Click", AddHotstring)
    MainGui.Add("Button", "x120 y460 w100 h24", "Edit").OnEvent("Click", EditHotstringFromBtn)
    MainGui.Add("Button", "x225 y460 w100 h24", "Delete").OnEvent("Click", DeleteHotstring)
    MainGui.Add("Button", "x330 y460 w120 h24", "Enable/Disable").OnEvent("Click", ToggleHotstring)
    MainGui.Add("Button", "x455 y460 w100 h24", "Test").OnEvent("Click", TestHotstring)
    MainGui.Add("Button", "x560 y460 w100 h24", "Refresh").OnEvent("Click", (*) => RefreshHotstringList())

    MainGui.Add("GroupBox", "x15 y490 w860 h120", "Hotstring Options Reference")
    MainGui.Add("Text", "x25 y510 w840", "Options control how hotstrings behave when triggered:")
    MainGui.Add("Text", "x25 y530 w840", "C = Case Sensitive  |  * = No end character required  |  ? = Trigger inside words")
    MainGui.Add("Text", "x25 y550 w840", "B = No auto-backspace  |  O = Omit end character  |  T = Send as text mode")
    MainGui.Add("Text", "x25 y570 w840", "Example: C* means case-sensitive and no end character needed")
    MainGui.Add("Text", "x25 y590 w840", "Leave blank for default behavior (case-insensitive, requires space/tab after trigger)")

}



; ═══════════════════════════════════════════════════════════════════════════════
; V5.0: HOTSTRING MANAGEMENT
; ═══════════════════════════════════════════════════════════════════════════════

LoadHotstrings() {
    global g_Hotstrings, HOTSTRINGS_FILE

    if !FileExist(HOTSTRINGS_FILE)
        return

    try {
        content := FileRead(HOTSTRINGS_FILE, "UTF-8")
        for line in StrSplit(content, "`n", "`r") {
            if line = "" || SubStr(line, 1, 1) = ";"
                continue

            parts := StrSplit(line, "|")
            if parts.Length >= 3 {
                trigger := parts[1]
                replacement := parts[2]
                options := parts[3]
                enabled := parts.Length >= 4 ? (parts[4] = "1") : true

                g_Hotstrings[trigger] := Map(
                    "replacement", replacement,
                    "options", options,
                    "enabled", enabled
                )

                if enabled && g_HotstringActive
                    ActivateHotstring(trigger, replacement, options)
            }
        }
    }
}

SaveHotstrings() {
    global g_Hotstrings, HOTSTRINGS_FILE

    output := "; Hotstring definitions (Trigger|Replacement|Options|Enabled)`n"
    output .= "; Options: C=CaseSensitive, *=NoEndChar, ?=TriggerInWord, B=NoBackspace, O=OmitEndChar`n`n"

    for trigger, data in g_Hotstrings {
        output .= trigger . "|" . data["replacement"] . "|" . data["options"] . "|" . (data["enabled"] ? "1" : "0") . "`n"
    }

    try {
        if FileExist(HOTSTRINGS_FILE)
            FileDelete(HOTSTRINGS_FILE)
        FileAppend(output, HOTSTRINGS_FILE, "UTF-8")
    }
}

ActivateHotstring(trigger, replacement, options := "") {
    try {
        Hotstring("::" . trigger, replacement, options)
        return true
    } catch as err {
        ShowActionNotification("Hotstring", "error", "Failed to activate: " . trigger, err.Message)
        return false
    }
}

DeactivateHotstring(trigger) {
    try {
        Hotstring("::" . trigger, "Off")
        return true
    } catch {
        return false
    }
}

ToggleAllHotstrings(*) {
    global g_Hotstrings, g_HotstringActive, HotstringMasterToggle

    g_HotstringActive := HotstringMasterToggle.Value

    for trigger, data in g_Hotstrings {
        if data["enabled"] {
            if g_HotstringActive
                ActivateHotstring(trigger, data["replacement"], data["options"])
            else
                DeactivateHotstring(trigger)
        }
    }
}

RefreshHotstringList() {
    global g_Hotstrings, HotstringLV

    HotstringLV.Delete()

    for trigger, data in g_Hotstrings {
        HotstringLV.Add("",
            data["enabled"] ? "✓" : "",
            trigger,
            data["replacement"],
            data["options"]
        )
    }
}

AddHotstring(*) {
    global g_Hotstrings, MainGui

    hsGui := Gui("+Owner" . MainGui.Hwnd, "Add Hotstring")
    hsGui.SetFont("s9", "Segoe UI")

    hsGui.Add("Text", "x10 y10", "Trigger Text (what you type):")
    triggerEdit := hsGui.Add("Edit", "x10 y30 w400")

    hsGui.Add("Text", "x10 y60", "Replacement Text (what appears):")
    replacementEdit := hsGui.Add("Edit", "x10 y80 w400 h100 +Multi")

    hsGui.Add("GroupBox", "x10 y190 w400 h120", "Options")

    caseSensCheck := hsGui.Add("CheckBox", "x20 y210", "Case Sensitive (C)")
    noEndCharCheck := hsGui.Add("CheckBox", "x20 y235", "No end character required (*)")
    triggerInWordCheck := hsGui.Add("CheckBox", "x20 y260", "Trigger inside words (?)")
    noBackspaceCheck := hsGui.Add("CheckBox", "x220 y210", "No auto-backspace (B)")
    omitEndCharCheck := hsGui.Add("CheckBox", "x220 y235", "Omit end character (O)")
    textModeCheck := hsGui.Add("CheckBox", "x220 y260", "Text mode (T)")

    enableCheck := hsGui.Add("CheckBox", "x10 y320 Checked", "Enable immediately")

    hsGui.Add("Button", "x10 y350 w100", "Save").OnEvent("Click", SaveNewHotstring)
    hsGui.Add("Button", "x120 y350 w100", "Cancel").OnEvent("Click", (*) => hsGui.Destroy())

    SaveNewHotstring(*) {
        trigger := triggerEdit.Value
        replacement := replacementEdit.Value

        if trigger = "" || replacement = "" {
            MsgBox("Both trigger and replacement are required")
            return
        }

        opts := ""
        if caseSensCheck.Value
            opts .= "C"
        if noEndCharCheck.Value
            opts .= "*"
        if triggerInWordCheck.Value
            opts .= "?"
        if noBackspaceCheck.Value
            opts .= "B"
        if omitEndCharCheck.Value
            opts .= "O"
        if textModeCheck.Value
            opts .= "T"

        enabled := enableCheck.Value

        g_Hotstrings[trigger] := Map(
            "replacement", replacement,
            "options", opts,
            "enabled", enabled
        )

        if enabled && g_HotstringActive
            ActivateHotstring(trigger, replacement, opts)

        SaveHotstrings()
        RefreshHotstringList()
        hsGui.Destroy()

        ShowNotificationBasic("Hotstring Added", "Hotstring '" . trigger . "' has been created", 3000)
    }

    hsGui.Show("w420 h390")
}

EditHotstring(lv, row) {
    global g_Hotstrings, MainGui

    if !row
        row := lv.GetNext()

    if !row {
        MsgBox("Please select a hotstring to edit")
        return
    }

    trigger := lv.GetText(row, 2)

    if !g_Hotstrings.Has(trigger) {
        MsgBox("Hotstring not found")
        return
    }

    data := g_Hotstrings[trigger]

    hsGui := Gui("+Owner" . MainGui.Hwnd, "Edit Hotstring")
    hsGui.SetFont("s9", "Segoe UI")

    hsGui.Add("Text", "x10 y10", "Trigger Text: " . trigger)

    hsGui.Add("Text", "x10 y40", "Replacement Text:")
    replacementEdit := hsGui.Add("Edit", "x10 y60 w400 h100 +Multi", data["replacement"])

    hsGui.Add("GroupBox", "x10 y170 w400 h120", "Options")

    opts := data["options"]
    caseSensCheck := hsGui.Add("CheckBox", "x20 y190", "Case Sensitive (C)")
    if InStr(opts, "C")
        caseSensCheck.Value := true

    noEndCharCheck := hsGui.Add("CheckBox", "x20 y215", "No end character required (*)")
    if InStr(opts, "*")
        noEndCharCheck.Value := true

    triggerInWordCheck := hsGui.Add("CheckBox", "x20 y240", "Trigger inside words (?)")
    if InStr(opts, "?")
        triggerInWordCheck.Value := true

    noBackspaceCheck := hsGui.Add("CheckBox", "x220 y190", "No auto-backspace (B)")
    if InStr(opts, "B")
        noBackspaceCheck.Value := true

    omitEndCharCheck := hsGui.Add("CheckBox", "x220 y215", "Omit end character (O)")
    if InStr(opts, "O")
        omitEndCharCheck.Value := true

    textModeCheck := hsGui.Add("CheckBox", "x220 y240", "Text mode (T)")
    if InStr(opts, "T")
        textModeCheck.Value := true

    enableCheck := hsGui.Add("CheckBox", "x10 y300", "Enabled")
    enableCheck.Value := data["enabled"]

    hsGui.Add("Button", "x10 y330 w100", "Save").OnEvent("Click", SaveEditedHotstring)
    hsGui.Add("Button", "x120 y330 w100", "Cancel").OnEvent("Click", (*) => hsGui.Destroy())

    SaveEditedHotstring(*) {
        replacement := replacementEdit.Value

        if replacement = "" {
            MsgBox("Replacement text is required")
            return
        }

        if data["enabled"] && g_HotstringActive
            DeactivateHotstring(trigger)

        newOpts := ""
        if caseSensCheck.Value
            newOpts .= "C"
        if noEndCharCheck.Value
            newOpts .= "*"
        if triggerInWordCheck.Value
            newOpts .= "?"
        if noBackspaceCheck.Value
            newOpts .= "B"
        if omitEndCharCheck.Value
            newOpts .= "O"
        if textModeCheck.Value
            newOpts .= "T"

        enabled := enableCheck.Value

        g_Hotstrings[trigger] := Map(
            "replacement", replacement,
            "options", newOpts,
            "enabled", enabled
        )

        if enabled && g_HotstringActive
            ActivateHotstring(trigger, replacement, newOpts)

        SaveHotstrings()
        RefreshHotstringList()
        hsGui.Destroy()

        ShowNotificationBasic("Hotstring Updated", "Hotstring '" . trigger . "' has been updated", 3000)
    }

    hsGui.Show("w420 h370")
}

EditHotstringFromBtn(*) {
    global HotstringLV
    row := HotstringLV.GetNext()
    if row
        EditHotstring(HotstringLV, row)
    else
        MsgBox("Please select a hotstring to edit")
}

DeleteHotstring(*) {
    global g_Hotstrings, HotstringLV

    row := HotstringLV.GetNext()
    if !row {
        MsgBox("Please select a hotstring to delete")
        return
    }

    trigger := HotstringLV.GetText(row, 2)

    result := MsgBox("Delete hotstring '" . trigger . "'?", "Confirm Delete", "YesNo Icon?")
    if result != "Yes"
        return

    if g_Hotstrings.Has(trigger) {
        if g_Hotstrings[trigger]["enabled"]
            DeactivateHotstring(trigger)

        g_Hotstrings.Delete(trigger)
        SaveHotstrings()
        RefreshHotstringList()

        ShowNotificationBasic("Hotstring Deleted", "Hotstring '" . trigger . "' has been removed", 3000)
    }
}

ToggleHotstring(*) {
    global g_Hotstrings, HotstringLV, g_HotstringActive

    row := HotstringLV.GetNext()
    if !row {
        MsgBox("Please select a hotstring")
        return
    }

    trigger := HotstringLV.GetText(row, 2)

    if g_Hotstrings.Has(trigger) {
        data := g_Hotstrings[trigger]
        data["enabled"] := !data["enabled"]

        if data["enabled"] && g_HotstringActive
            ActivateHotstring(trigger, data["replacement"], data["options"])
        else
            DeactivateHotstring(trigger)

        SaveHotstrings()
        RefreshHotstringList()
    }
}

TestHotstring(*) {
    global HotstringLV

    row := HotstringLV.GetNext()
    if !row {
        MsgBox("Please select a hotstring to test")
        return
    }

    trigger := HotstringLV.GetText(row, 2)
    replacement := HotstringLV.GetText(row, 3)

    testGui := Gui("+AlwaysOnTop", "Hotstring Test")
    testGui.SetFont("s9", "Segoe UI")

    testGui.Add("Text", "x10 y10", "Type the trigger text in the box below to test:")
    testGui.Add("Text", "x10 y30", "Trigger: " . trigger)
    testGui.Add("Text", "x10 y50", "Replacement: " . replacement)

    testEdit := testGui.Add("Edit", "x10 y80 w400 h100 +Multi")

    testGui.Add("Button", "x10 y190 w100", "Close").OnEvent("Click", (*) => testGui.Destroy())

    testGui.Show("w420 h230")
}

