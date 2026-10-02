; ===============================================================================
; Tabs\Tab_07_Hotkeys.ahk
; TAB 7 Hotkeys: sequence hotkey assignments
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================


SaveHotkeys() {
    global g_HotkeyBindings, HOTKEYS_FILE
    try {
        if FileExist(HOTKEYS_FILE)
            FileDelete(HOTKEYS_FILE)
        for hk, seq in g_HotkeyBindings
            IniWrite(seq, HOTKEYS_FILE, "Hotkeys", hk)
    }
}

LoadHotkeys() {
    global g_HotkeyBindings, HOTKEYS_FILE
    if !FileExist(HOTKEYS_FILE)
        return
    g_HotkeyBindings := Map()
    allKeys := IniRead(HOTKEYS_FILE, "Hotkeys", , "")
    for line in StrSplit(allKeys, "`n") {
        eq := InStr(line, "=")
        if eq > 0
            g_HotkeyBindings[SubStr(line, 1, eq - 1)] := SubStr(line, eq + 1)
    }
}

Tab_Hotkeys_Build() {
    global HotkeyLV, KeyEditHK, ModDD, SeqDDHK
    TabCtrl.UseTab(7)

    MainGui.Add("Text", "x15 y55", "Assigned:")
    HotkeyLV := MainGui.Add("ListView", "x15 y70 w500 h150 Grid NoSortHdr", ["Hotkey", "Sequence"])
    HotkeyLV.ModifyCol(1, 150)
    HotkeyLV.ModifyCol(2, 340)

    MainGui.Add("Text", "x15 y230", "Mod:")
    ModDD := MainGui.Add("DropDownList", "x50 yp-3 w90 vModifier", ["(none)", "Ctrl", "Alt", "Shift", "Ctrl+Alt", "Ctrl+Shift"])
    ModDD.Choose(2)
    MainGui.Add("Text", "x145 yp+3", "Key:")
    KeyEditHK := MainGui.Add("Edit", "x175 yp-3 w50 vHotkeyKey", "1")
    MainGui.Add("Text", "x230 yp+3", "Seq:")
    SeqDDHK := MainGui.Add("DropDownList", "x260 yp-3 w150 vHotkeySeq")

    MainGui.Add("Button", "x15 y260 w70 h24", "Add").OnEvent("Click", AddHotkey)
    MainGui.Add("Button", "x90 yp w70 h24", "Remove").OnEvent("Click", RemoveHotkey)
    MainGui.Add("Button", "x165 yp w70 h24", "Apply").OnEvent("Click", ApplyHotkeys)

}



; ═══════════════════════════════════════════════════════════════════════════════
; HOTKEYS
; ═══════════════════════════════════════════════════════════════════════════════
; HOTKEYS
; =============================================================================

RefreshHKDropdowns(*) {
    global g_Sequences, SeqDDHK, HotkeyLV, g_HotkeyBindings
    items := ["(none)"]
    for n, _ in g_Sequences
        items.Push(n)
    SeqDDHK.Delete()
    SeqDDHK.Add(items)
    SeqDDHK.Choose(items.Length > 1 ? 2 : 1)
    HotkeyLV.Delete()
    for hk, seq in g_HotkeyBindings
        HotkeyLV.Add(, hk, seq)
}

AddHotkey(*) {
    global g_HotkeyBindings, SeqDDHK
    saved := MainGui.Submit(false)
    if saved.HotkeyKey = "" || SeqDDHK.Text = "(none)"
        return
    hk := ""
    switch saved.Modifier {
        case "Ctrl": hk := "^"
        case "Alt": hk := "!"
        case "Shift": hk := "+"
        case "Ctrl+Alt": hk := "^!"
        case "Ctrl+Shift": hk := "^+"
    }
    hk .= saved.HotkeyKey
    g_HotkeyBindings[hk] := SeqDDHK.Text
    RefreshHKDropdowns()
    SaveHotkeys()
}

RemoveHotkey(*) {
    global g_HotkeyBindings, HotkeyLV
    row := HotkeyLV.GetNext(0, "Focused")
    if row = 0
        return
    hk := HotkeyLV.GetText(row, 1)
    try Hotkey(hk, "Off")
    g_HotkeyBindings.Delete(hk)
    RefreshHKDropdowns()
    SaveHotkeys()
}

ApplyHotkeys(*) {
    global g_HotkeyBindings
    for hk, _ in g_HotkeyBindings
        try Hotkey(hk, "Off")
    count := 0
    for hk, seq in g_HotkeyBindings {
        try {
            Hotkey(hk, RunSeqByName.Bind(seq), "On")
            count++
        }
    }
    StatusBar.SetText("Applied " . count . " hotkeys")
}

RunSeqByName(seqName, *) {
    global g_Sequences, g_IsPaused, g_AbortSequence
    if !g_Sequences.Has(seqName)
        return
    g_IsPaused := false
    g_AbortSequence := false
    speed := g_Sequences[seqName].Has("speed") ? g_Sequences[seqName]["speed"] : 1.0
    ExecuteSequenceVerified(g_Sequences[seqName]["steps"], speed)
}

