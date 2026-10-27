; ===============================================================================
; Tabs\Tab_11_Notepad.ahk
; TAB 11 Notepad: quick notes, popup notepad
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================

Tab_Notepad_Build() {
    global noteListLV, notepadEdit
    TabCtrl.UseTab(11)

    MainGui.Add("Text", "x20 y55", "Quick Notepad for Testing & Automation")
    MainGui.Add("Text", "x20 y75 c888888", "Use this to test text entry, write notes, or prepare automation content")

    notepadEdit := MainGui.Add("Edit", "x20 y95 w760 h400 vNotepadEdit Multi WantTab", "")
    notepadEdit.Name := "NotepadEdit"

    MainGui.Add("Button", "x20 y505 w120", "Save Note").OnEvent("Click", SaveNotepadContent)
    MainGui.Add("Button", "x145 y505 w120", "Load Note").OnEvent("Click", LoadNotepadContent)
    MainGui.Add("Button", "x270 y505 w120", "Clear").OnEvent("Click", ClearNotepadContent)
    MainGui.Add("Button", "x395 y505 w120", "Open Popup").OnEvent("Click", OpenNotepadPopup)
    MainGui.Add("Button", "x520 y505 w150", "Copy to Clipboard").OnEvent("Click", (*) => CopyNotepadToClipboard())

    MainGui.Add("Text", "x20 y535", "Saved Notes:")
    noteListLV := MainGui.Add("ListView", "x20 y555 w760 h60", ["Filename", "Modified", "Size"])
    noteListLV.Name := "NoteListLV"
    noteListLV.OnEvent("DoubleClick", LoadSelectedNote)

}




CreateNotepadTab() {
    global MainGui, g_NotepadContent

    ; Create Notepad tab
    notepadTab := MainGui.Add("Tab3", "Choose1", ["Notepad"])

    ; Title and instructions
    MainGui.Add("Text", "x20 y+15", "Quick Notepad for Testing & Automation")
    MainGui.Add("Text", "x20 y+5 c888888", "Use this to test text entry, write notes, or prepare automation content")

    ; Main notepad edit control
    notepadEdit := MainGui.Add("Edit", "x20 y+10 w760 h400 vNotepadEdit Multi WantTab", g_NotepadContent)

    ; Buttons row
    MainGui.Add("Button", "x20 y+10 w120", "Save Note").OnEvent("Click", SaveNotepadContent)
    MainGui.Add("Button", "x+10 w120", "Load Note").OnEvent("Click", LoadNotepadContent)
    MainGui.Add("Button", "x+10 w120", "Clear").OnEvent("Click", ClearNotepadContent)
    MainGui.Add("Button", "x+10 w120", "Open Popup").OnEvent("Click", OpenNotepadPopup)
    MainGui.Add("Button", "x+10 w150", "Copy to Clipboard").OnEvent("Click", (*) => CopyNotepadToClipboard())

    ; Quick action buttons
    MainGui.Add("Text", "x20 y+20", "Quick Actions:")
    MainGui.Add("Button", "x20 y+5 w120", "Auto-Type This").OnEvent("Click", AutoTypeNotepad)
    MainGui.Add("Button", "x+10 w150", "Send to Active Window").OnEvent("Click", SendNotepadToWindow)
    MainGui.Add("Button", "x+10 w120", "New Sequence").OnEvent("Click", NewSequenceFromNotepad)

    ; Note list
    MainGui.Add("Text", "x20 y+20", "Saved Notes:")
    noteListLV := MainGui.Add("ListView", "x20 y+5 w760 h100", ["Filename", "Modified", "Size"])
    noteListLV.Name := "NoteListLV"
    noteListLV.OnEvent("DoubleClick", LoadSelectedNote)
    RefreshNoteList()

    return notepadTab
}

; Open popup notepad window (can be targeted with WinActivate)
OpenNotepadPopup(*) {
    global g_NotepadPopupGui, g_NotepadContent

    ; Close existing popup if open
    if g_NotepadPopupGui && WinExist("ahk_id " . g_NotepadPopupGui.Hwnd) {
        try g_NotepadPopupGui.Destroy()
    }

    ; Create popup window
    g_NotepadPopupGui := Gui("+Resize", "MacroAutomator Notepad - Target with WinActivate")
    g_NotepadPopupGui.SetFont("s10", "Consolas")

    ; Instructions
    g_NotepadPopupGui.Add("Text", "x10 y10", "This window can be targeted: WinActivate('MacroAutomator Notepad')")

    ; Large text area
    noteEdit := g_NotepadPopupGui.Add("Edit", "x10 y+10 w780 h500 Multi WantTab", g_NotepadContent)
    noteEdit.Name := "PopupNoteEdit"

    ; Buttons
    g_NotepadPopupGui.Add("Button", "x10 y+10 w100", "Save").OnEvent("Click", SavePopupNotepad)
    g_NotepadPopupGui.Add("Button", "x+10 w100", "Copy All").OnEvent("Click", (*) => CopyPopupToClipboard())
    g_NotepadPopupGui.Add("Button", "x+10 w120", "Clear").OnEvent("Click", ClearPopupNotepad)
    g_NotepadPopupGui.Add("Button", "x+10 w150", "Close").OnEvent("Click", (*) => g_NotepadPopupGui.Hide())

    ; Status bar
    g_NotepadPopupGui.Add("Text", "x10 y+10 w760 cGray", "Autosaves every 30 seconds • Ctrl+S to save manually")

    ; Set up auto-save timer
    SetTimer(AutoSavePopupNotepad, 30000)

    ; Show window
    g_NotepadPopupGui.Show("w800 h600")

    ShowStatus("Notepad popup opened - Window title: 'MacroAutomator Notepad'", "ok")
}

; Save notepad content to file
SaveNotepadContent(*) {
    global g_NotepadContent, NOTES_DIR, MainGui

    ; Get current content
    try {
        g_NotepadContent := MainGui["NotepadEdit"].Value
    }

    ; Generate filename with timestamp
    timestamp := FormatTime(A_Now, "yyyyMMdd_HHmmss")
    filename := "note_" . timestamp . ".txt"
    filepath := NOTES_DIR . "\" . filename

    ; Prompt for custom filename
    result := InputBoxTop("Save note as:", "Save Note", filename)
    if result["Result"] = "OK" && result["Value"] != "" {
        filename := result["Value"]
        if !InStr(filename, ".txt")
            filename .= ".txt"
        filepath := NOTES_DIR . "\" . filename
    } else if result["Result"] = "Cancel" {
        return
    }

    ; Save file
    try {
        FanFileDelete(filepath)  ; Delete if exists
        FanFileAppend(g_NotepadContent, filepath, "UTF-8")
        ShowStatus("Note saved: " . filename, "ok")
        RefreshNoteList()
    } catch as err {
        MsgBoxTop("Error saving note: " . err.Message, "Save Error")
    }
}

; Load note from file
LoadNotepadContent(*) {
    global g_NotepadContent, NOTES_DIR, MainGui

    ; Get list of notes
    notes := []
    for note in FanFile_ListNotes(NOTES_DIR)
        notes.Push(note["name"])

    if notes.Length = 0 {
        MsgBoxTop("No saved notes found.", "Load Note")
        return
    }

    ; Let user choose
    result := InputBoxTop("Enter note filename to load:", "Load Note", notes[1])
    if result["Result"] = "OK" && result["Value"] != "" {
        filepath := NOTES_DIR . "\" . result["Value"]
        if FanFileExist(filepath) {
            try {
                g_NotepadContent := FanFileRead(filepath, "UTF-8")
                MainGui["NotepadEdit"].Value := g_NotepadContent
                ShowStatus("Note loaded: " . result["Value"], "ok")
            } catch as err {
                MsgBoxTop("Error loading note: " . err.Message, "Load Error")
            }
        } else {
            MsgBoxTop("File not found: " . result["Value"], "Load Error")
        }
    }
}

; Load selected note from list
LoadSelectedNote(*) {
    global NOTES_DIR, MainGui, g_NotepadContent

    ; Get selected row
    row := MainGui["NoteListLV"].GetNext()
    if !row
        return

    ; Get filename
    filename := MainGui["NoteListLV"].GetText(row, 1)
    filepath := NOTES_DIR . "\" . filename

    ; Load content
    try {
        g_NotepadContent := FanFileRead(filepath, "UTF-8")
        MainGui["NotepadEdit"].Value := g_NotepadContent
        ShowStatus("Loaded: " . filename, "ok")
    } catch as err {
        MsgBoxTop("Error loading note: " . err.Message, "Load Error")
    }
}

; Clear notepad content
ClearNotepadContent(*) {
    global g_NotepadContent, MainGui

    result := MsgBoxTop("Clear notepad content?", "Confirm", "YesNo")
    if result = "Yes" {
        g_NotepadContent := ""
        MainGui["NotepadEdit"].Value := ""
        ShowStatus("Notepad cleared", "ok")
    }
}

; Copy notepad to clipboard
CopyNotepadToClipboard() {
    global MainGui

    try {
        content := MainGui["NotepadEdit"].Value
        A_Clipboard := content
        ShowStatus("Copied to clipboard: " . StrLen(content) . " characters", "ok")
    } catch as err {
        ShowStatus("Error copying to clipboard", "fail")
    }
}

; Auto-type notepad content
AutoTypeNotepad(*) {
    global MainGui, g_Settings

    content := MainGui["NotepadEdit"].Value
    if content = "" {
        MsgBoxTop("Notepad is empty!", "Auto-Type")
        return
    }

    ; Minimize our GUI
    MainGui.Hide()
    Sleep(500)

    ; Type content
    SendText(content)
    Sleep(500)

    ; Show GUI again
    MainGui.Show()
    ShowStatus("Auto-typed " . StrLen(content) . " characters", "ok")
}

; Send notepad to active window
SendNotepadToWindow(*) {
    global MainGui

    content := MainGui["NotepadEdit"].Value
    if content = "" {
        MsgBoxTop("Notepad is empty!", "Send to Window")
        return
    }

    MsgBoxTop("Click OK, then click in the target window.`nContent will be typed in 2 seconds.", "Send to Window")

    Sleep(2000)
    SendText(content)
    ShowStatus("Content sent to window", "ok")
}

; Create new sequence from notepad content
NewSequenceFromNotepad(*) {
    global MainGui, g_CurrentSequenceSteps

    content := MainGui["NotepadEdit"].Value
    if content = "" {
        MsgBoxTop("Notepad is empty!", "New Sequence")
        return
    }

    ; Clear current sequence
    g_CurrentSequenceSteps := []

    ; Add type action
    g_CurrentSequenceSteps.Push(Map(
        "action", "Type Text",
        "target", "",
        "param", content,
        "enabled", true
    ))

    ; Switch to Workflow tab and refresh
    try {
        MainGui["Tabs"].Choose(1)  ; Workflow tab
        ;RefreshSeqStepsLV()
        RefreshStepsLV()
        ScheduleWorkflowAutosave()

        ShowStatus("Sequence created from notepad content", "ok")
    }
}

; Refresh note list
RefreshNoteList() {
    global NOTES_DIR, MainGui

    try {
        lv := MainGui["NoteListLV"]
        lv.Delete()

        for note in FanFile_ListNotes(NOTES_DIR) {
            size := Round(note["size"] / 1024, 1) . " KB"
            lv.Add("", note["name"], note["modified"], size)
        }

        ; Auto-size columns
        lv.ModifyCol()
        lv.ModifyCol(1, "AutoHdr")
        lv.ModifyCol(2, "AutoHdr")
        lv.ModifyCol(3, "AutoHdr")
    }
}

; Popup notepad save
SavePopupNotepad(*) {
    global g_NotepadPopupGui, g_NotepadContent, NOTES_DIR

    try {
        g_NotepadContent := g_NotepadPopupGui["PopupNoteEdit"].Value

        ; Generate filename
        timestamp := FormatTime(A_Now, "yyyyMMdd_HHmmss")
        filename := "popup_note_" . timestamp . ".txt"
        filepath := NOTES_DIR . "\" . filename

        ; Save
        FanFileDelete(filepath)
        FanFileAppend(g_NotepadContent, filepath, "UTF-8")
        ShowStatus("Popup note saved: " . filename, "ok")
    }
}

; Copy popup to clipboard
CopyPopupToClipboard() {
    global g_NotepadPopupGui

    try {
        content := g_NotepadPopupGui["PopupNoteEdit"].Value
        A_Clipboard := content
        ShowStatus("Copied: " . StrLen(content) . " characters", "ok")
    }
}

; Clear popup notepad
ClearPopupNotepad(*) {
    global g_NotepadPopupGui

    result := MsgBoxTop("Clear popup notepad?", "Confirm", "YesNo")
    if result = "Yes" {
        try g_NotepadPopupGui["PopupNoteEdit"].Value := ""
    }
}

; Auto-save popup notepad
AutoSavePopupNotepad() {
    global g_NotepadPopupGui, g_NotepadContent, NOTES_DIR

    ; Check if window still exists
    if !g_NotepadPopupGui || !WinExist("ahk_id " . g_NotepadPopupGui.Hwnd) {
        SetTimer(AutoSavePopupNotepad, 0)  ; Stop timer
        return
    }

    try {
        g_NotepadContent := g_NotepadPopupGui["PopupNoteEdit"].Value

        ; Auto-save to temp file
        filepath := NOTES_DIR . "\autosave_popup.txt"
        FanFileDelete(filepath)
        FanFileAppend(g_NotepadContent, filepath, "UTF-8")
    }
}

