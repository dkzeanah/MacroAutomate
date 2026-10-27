; ===============================================================================
; Tabs\Tab_06_Clipboard.ahk
; TAB 6 Clipboard: extraction rules, revolver, smart bins
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================


SaveExtractionRules() {
    global g_ExtractionRules, RULES_FILE
    try {
        file := FanFileOpen(RULES_FILE, "w", "UTF-8")
        file.WriteLine("Name,Pattern")
        for r in g_ExtractionRules
            file.WriteLine(r["name"] . "," . r["pattern"])
        file.Close()
    }
}

LoadExtractionRules() {
    global g_ExtractionRules, RULES_FILE
    if !FanFileExist(RULES_FILE) {
        g_ExtractionRules := [Map("name", "LastName", "pattern", "^([^,]+)"), Map("name", "FirstName", "pattern", ",\s*([^#\s]+)"), Map("name", "DOB", "pattern", "(\d{1,2}/\d{1,2}/\d{2,4})")]
        return
    }
    g_ExtractionRules := []
    lineNum := 0
    for line in FanFile_Lines(RULES_FILE) {
        lineNum++
        if lineNum = 1 || line = ""
            continue
        p := StrSplit(line, ",", , 2)
        if p.Length >= 2
            g_ExtractionRules.Push(Map("name", p[1], "pattern", p[2]))
    }
}

Tab_Clipboard_Build() {
    global ClipEdit, ExtractLV, FieldOrderLV, RevolverLV, RevolverStatus, RulesLV
    TabCtrl.UseTab(6)

    ; --- CLIPBOARD INPUT ---
    MainGui.Add("Text", "x15 y55", "Clipboard:")
    ClipEdit := MainGui.Add("Edit", "x15 y70 w400 h70 Multi vClipContent")
    MainGui.Add("Button", "x420 y70 w70 h22", "Grab").OnEvent("Click", GrabClip)
    MainGui.Add("Button", "x420 y95 w70 h22", "Parse").OnEvent("Click", ParseClip)
    MainGui.Add("Button", "x420 y120 w70 h22", "Clear").OnEvent("Click", ClearClip)

    ; --- EXTRACTION RULES ---
    MainGui.Add("Text", "x15 y150", "Rules:")
    RulesLV := MainGui.Add("ListView", "x15 y165 w350 h65 Grid NoSortHdr", ["Name", "Pattern", "Result"])
    RulesLV.ModifyCol(1, 80)
    RulesLV.ModifyCol(2, 170)
    RulesLV.ModifyCol(3, 90)

    MainGui.Add("Text", "x15 y235", "Name:")
    MainGui.Add("Edit", "x55 yp-3 w70 vPatternNameClip")
    MainGui.Add("Text", "x130 yp+3", "Regex:")
    MainGui.Add("Edit", "x170 yp-3 w150 vPatternRegex")
    MainGui.Add("Button", "x325 yp w40 h22", "Add").OnEvent("Click", AddRule)
    MainGui.Add("Button", "x370 yp w40 h22", "Del").OnEvent("Click", DelRule)

    ; --- EXTRACTED DATA ---
    MainGui.Add("Text", "x15 y265", "Extracted:")
    ExtractLV := MainGui.Add("ListView", "x15 y280 w350 h70 Grid NoSortHdr", ["Field", "Value"])
    ExtractLV.ModifyCol(1, 100)
    ExtractLV.ModifyCol(2, 240)

    ; --- REVOLVER SYSTEM ---
    MainGui.Add("GroupBox", "x380 y145 w490 h205", "Clipboard Revolver (Sequential Paste)")

    MainGui.Add("Text", "x390 y163", "Field Order (paste sequence):")
    FieldOrderLV := MainGui.Add("ListView", "x390 y178 w180 h80 Grid NoSortHdr", ["#", "Field"])
    FieldOrderLV.ModifyCol(1, 25)
    FieldOrderLV.ModifyCol(2, 145)

    MainGui.Add("Button", "x575 y178 w40 h22", "▲").OnEvent("Click", MoveFieldUp)
    MainGui.Add("Button", "x575 y203 w40 h22", "▼").OnEvent("Click", MoveFieldDown)
    MainGui.Add("Button", "x575 y228 w40 h22", "+").OnEvent("Click", AddFieldToOrder)
    MainGui.Add("Button", "x575 y253 w40 h22", "-").OnEvent("Click", RemoveFieldFromOrder)

    MainGui.Add("Text", "x630 y163", "Loaded Chambers:")
    RevolverLV := MainGui.Add("ListView", "x630 y178 w235 h80 Grid NoSortHdr", ["#", "Field", "Value", "Status"])
    RevolverLV.ModifyCol(1, 20)
    RevolverLV.ModifyCol(2, 70)
    RevolverLV.ModifyCol(3, 95)
    RevolverLV.ModifyCol(4, 45)

    RevolverStatus := MainGui.Add("Text", "x390 y268 w220 cGray", "Revolver: Empty")

    MainGui.Add("Button", "x390 y290 w100 h28", "Load Revolver").OnEvent("Click", (*) => LoadRevolver())
    MainGui.Add("Button", "x495 y290 w100 h28", "Unload").OnEvent("Click", (*) => UnloadRevolver())
    MainGui.Add("Button", "x600 y290 w130 h28 cGreen", "▶ Fire All").OnEvent("Click", (*) => FireAllShots())

    MainGui.Add("Text", "x390 y325 w470 cBlue", "Ctrl+B = Load revolver  |  Ctrl+Shift+B = Fire all shots")

    ; --- QUICK REFERENCE ---
    MainGui.Add("GroupBox", "x15 y360 w855 h125", "Revolver Quick Reference")
    MainGui.Add("Text", "x25 y378", "HOTKEY MODE:")
    MainGui.Add("Text", "x25 y393 cGreen", "  Ctrl+B      = Copy + Parse + Load")
    MainGui.Add("Text", "x25 y408 cGreen", "  Ctrl+Shift+B = Fire all shots (paste+Tab...)")
    MainGui.Add("Text", "x25 y428", "  (Navigate to target between load and fire)")

    MainGui.Add("Text", "x280 y378", "WORKFLOW ACTIONS (for sequences):")
    MainGui.Add("Text", "x280 y393", "  Parse Clipboard  → extract from A_Clipboard")
    MainGui.Add("Text", "x280 y408", "  Load Revolver    → load extracted fields")
    MainGui.Add("Text", "x280 y423", "  Fire Revolver    → paste + Tab each field")
    MainGui.Add("Text", "x280 y438", "  Fire Revolver+Enter → same + Enter")

    MainGui.Add("Text", "x600 y378", "TYPICAL USE:")
    MainGui.Add("Text", "x600 y393 cBlue", "  1. Select patient text")
    MainGui.Add("Text", "x600 y408 cBlue", "  2. Ctrl+B (chirp = loaded)")
    MainGui.Add("Text", "x600 y423 cBlue", "  3. Navigate to form fields")
    MainGui.Add("Text", "x600 y438 cBlue", "  4. Click first field")
    MainGui.Add("Text", "x600 y453 cBlue", "  5. Ctrl+Shift+B (fires all)")
    MainGui.Add("Text", "x600 y468 cBlue", "  6. Double-beep = done")


}

InitializeRevolverBins() {
    global g_RevolverBins, g_RevolverBinOrder

    ; Load saved bins from file
    LoadRevolverBins()

    ; If no bins, create defaults
    if g_RevolverBins.Count = 0 {
        ; Create default bins for insurance example
        CreateRevolverBin("VSP", ["lastName", "firstName", "DOB", "memberID"], [
            "swapNames",  ; Last, First -> First Last
            "addDate"     ; Include today's date
        ])

        CreateRevolverBin("EyeMed", ["firstName", "lastName", "memberID", "DOB"], [
            "upperCase",  ; ALL CAPS
            "removeSpaces"  ; Remove spaces
        ])
    }
}

; Create a new revolver bin
CreateRevolverBin(binName, fieldOrder, formatRules) {
    global g_RevolverBins, g_RevolverBinOrder

    g_RevolverBins[binName] := Map(
        "items", [],
        "fieldOrder", fieldOrder,
        "formatRules", formatRules,
        "notifyBlock", true,
        "position", 0
    )

    ; Add to order if not already there
    if !HasValue(g_RevolverBinOrder, binName) {
        g_RevolverBinOrder.Push(binName)
    }

    ShowStatus("Bin created: " . binName, "ok")
}

; Load revolver item with bin selection
LoadRevolverItem(itemString) {
    global g_RevolverBins, g_RevolverBinSelector

    ; Parse item string (e.g., "Smith,John,01/15/1985,12345")
    ; This is the raw data before formatting

    ; Show bin selection GUI
    ShowBinSelector(itemString)
}

; Show GUI to select which bin to load item into
ShowBinSelector(itemString) {
    global g_RevolverBins, g_RevolverBinSelector

    ; Close existing selector if open
    if g_RevolverBinSelector && WinExist("ahk_id " . g_RevolverBinSelector.Hwnd) {
        try g_RevolverBinSelector.Destroy()
    }

    ; Create selector GUI
    g_RevolverBinSelector := Gui("+AlwaysOnTop", "Select Bin for Item")
    g_RevolverBinSelector.SetFont("s10", "Segoe UI")

    ; Show preview of item
    g_RevolverBinSelector.Add("Text", "x20 y15", "Item to load:")
    g_RevolverBinSelector.Add("Edit", "x20 y+5 w460 ReadOnly", itemString)

    ; Instructions
    g_RevolverBinSelector.Add("Text", "x20 y+15", "Select bin to load this item into:")

    ; Create button for each bin
    yPos := 120
    for binName in g_RevolverBins {
        bin := g_RevolverBins[binName]
        btnText := binName . " (" . bin["items"].Length . " items)"

        btn := g_RevolverBinSelector.Add("Button", "x20 y" . yPos . " w460 h40", btnText)
        btn.OnEvent("Click", LoadItemIntoBin.Bind(binName, itemString))

        yPos += 50
    }

    ; Cancel button
    g_RevolverBinSelector.Add("Button", "x20 y" . yPos . " w460", "Cancel").OnEvent("Click", (*) => g_RevolverBinSelector.Hide())

    ; Show GUI
    g_RevolverBinSelector.Show("w500 h" . (yPos + 60))
}

; Load item into selected bin
LoadItemIntoBin(binName, itemString, *) {
    global g_RevolverBins, g_RevolverBinSelector

    if !g_RevolverBins.Has(binName)
        return

    bin := g_RevolverBins[binName]

    ; Parse item string based on bin's field order
    parts := StrSplit(itemString, ",")
    itemData := Map()

    for i, fieldName in bin["fieldOrder"] {
        if i <= parts.Length {
            itemData[fieldName] := Trim(parts[i])
        }
    }

    ; Apply format rules
    formattedData := ApplyFormatRules(itemData, bin["formatRules"])

    ; Add to bin
    bin["items"].Push(formattedData)

    ; Close selector
    try g_RevolverBinSelector.Hide()

    ShowStatus("Item loaded into " . binName . " (" . bin["items"].Length . " total)", "ok")

    ; Update bin notification if visible
    UpdateBinNotification(binName)
}

; Apply formatting rules to item data
ApplyFormatRules(itemData, formatRules) {
    formattedData := itemData.Clone()

    for rule in formatRules {
        switch rule {
            case "swapNames":
                ; Swap lastName and firstName
                if formattedData.Has("lastName") && formattedData.Has("firstName") {
                    temp := formattedData["lastName"]
                    formattedData["lastName"] := formattedData["firstName"]
                    formattedData["firstName"] := temp
                }

            case "addDate":
                ; Add today's date
                formattedData["date"] := FormatTime(A_Now, "MM/dd/yyyy")

            case "upperCase":
                ; Convert all to uppercase
                for field, value in formattedData {
                    formattedData[field] := StrUpper(value)
                }

            case "removeSpaces":
                ; Remove all spaces
                for field, value in formattedData {
                    formattedData[field] := StrReplace(value, " ", "")
                }

            case "formatPhone":
                ; Format phone as (XXX) XXX-XXXX
                if formattedData.Has("phone") {
                    phone := formattedData["phone"]
                    phone := RegExReplace(phone, "[^0-9]", "")  ; Remove non-digits
                    if StrLen(phone) = 10 {
                        formattedData["phone"] := "(" . SubStr(phone, 1, 3) . ") " . SubStr(phone, 4, 3) . "-" . SubStr(phone, 7, 4)
                    }
                }
        }
    }

    return formattedData
}

; Paste from bins (processes top bin first)
PasteFromBins() {
    global g_RevolverBinOrder, g_RevolverBins, g_Settings

    ; Find first non-empty bin
    for binName in g_RevolverBinOrder {
        if !g_RevolverBins.Has(binName)
            continue

        bin := g_RevolverBins[binName]
        if bin["items"].Length = 0
            continue

        ; Get next item from this bin
        item := bin["items"][1]
        bin["items"].RemoveAt(1)

        ; Show notification block if enabled
        if bin["notifyBlock"] {
            ShowBinNotification(binName, item)
        }

        ; Format for pasting (concatenate fields in order)
        pasteText := ""
        for fieldName in bin["fieldOrder"] {
            if item.Has(fieldName) {
                if pasteText != ""
                    pasteText .= " "  ; Space separator
                pasteText .= item[fieldName]
            }
        }

        ; Paste
        Sleep(g_Settings["PreActionDelay"])
        SendText(pasteText)
        Sleep(g_Settings["PostActionDelay"])

        ShowStatus("Pasted from " . binName . ": " . pasteText, "ok")

        ; Update bin notification
        UpdateBinNotification(binName)

        return true
    }

    ShowStatus("All bins empty!", "fail")
    return false
}

; Show bin notification block during paste
ShowBinNotification(binName, item) {
    global g_RevolverBinNotifications

    ; Create notification
    notif := Gui("+AlwaysOnTop +ToolWindow", "Revolver: " . binName)
    notif.SetFont("s9", "Segoe UI")
    notif.BackColor := "2C3E50"

    ; Bin name
    notif.Add("Text", "x10 y10 w280 cWhite", "BIN: " . binName).SetFont("s10 bold")

    ; Item details
    yPos := 40
    for field, value in item {
        notif.Add("Text", "x10 y" . yPos . " w280 cWhite", field . ": " . value)
        yPos += 20
    }

    ; Show at top-right
    notif.Show("x" . (A_ScreenWidth - 320) . " y20 w300 h" . (yPos + 20) . " NoActivate")

    ; Store reference
    g_RevolverBinNotifications[binName] := notif

    ; Auto-hide after 2 seconds
    SetTimer(() => HideBinNotification(binName), -2000)
}

; Update bin notification
UpdateBinNotification(binName) {
    global g_RevolverBinNotifications, g_RevolverBins

    if !g_RevolverBinNotifications.Has(binName)
        return

    bin := g_RevolverBins[binName]
    notif := g_RevolverBinNotifications[binName]

    try {
        notif.Title := binName . " (" . bin["items"].Length . " remaining)"
    }
}

; Hide bin notification
HideBinNotification(binName) {
    global g_RevolverBinNotifications

    if !g_RevolverBinNotifications.Has(binName)
        return

    try g_RevolverBinNotifications[binName].Hide()
}

; Save bins to file
SaveRevolverBins() {
    global g_RevolverBins, g_RevolverBinOrder, DATA_DIR

    filepath := DATA_DIR . "\revolver_bins.ini"

    try FanFileDelete(filepath)

    ; Save bin order
    FanFileAppend("[BinOrder]`n", filepath)
    FanFileAppend("order=" . ArrayJoin(g_RevolverBinOrder, "|") . "`n`n", filepath)

    ; Save each bin
    for binName, bin in g_RevolverBins {
        FanFileAppend("[" . binName . "]`n", filepath)
        FanFileAppend("fieldOrder=" . ArrayJoin(bin["fieldOrder"], "|") . "`n", filepath)
        FanFileAppend("formatRules=" . ArrayJoin(bin["formatRules"], "|") . "`n", filepath)
        FanFileAppend("notifyBlock=" . bin["notifyBlock"] . "`n", filepath)
        FanFileAppend("`n", filepath)
    }
}

; Load bins from file
LoadRevolverBins() {
    global g_RevolverBins, g_RevolverBinOrder, DATA_DIR

    filepath := DATA_DIR . "\revolver_bins.ini"

    if !FanFileExist(filepath)
        return

    ; Parse INI file
    currentSection := ""
    currentBin := ""

    try {
        content := FanFileRead(filepath)

        for line in StrSplit(content, "`n") {
            line := Trim(line)
            if line = ""
                continue

            if SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]" {
                currentSection := SubStr(line, 2, -1)
                if currentSection != "BinOrder" {
                    currentBin := currentSection
                    g_RevolverBins[currentBin] := Map(
                        "items", [],
                        "fieldOrder", [],
                        "formatRules", [],
                        "notifyBlock", true,
                        "position", 0
                    )
                }
            } else if InStr(line, "=") {
                parts := StrSplit(line, "=", , 2)
                key := parts[1]
                value := parts.Length > 1 ? parts[2] : ""

                if currentSection = "BinOrder" {
                    if key = "order" {
                        g_RevolverBinOrder := StrSplit(value, "|")
                    }
                } else if currentBin != "" {
                    switch key {
                        case "fieldOrder":
                            g_RevolverBins[currentBin]["fieldOrder"] := StrSplit(value, "|")
                        case "formatRules":
                            g_RevolverBins[currentBin]["formatRules"] := StrSplit(value, "|")
                        case "notifyBlock":
                            g_RevolverBins[currentBin]["notifyBlock"] := value = "1" || value = "true"
                    }
                }
            }
        }
    }
}

; Helper: Join array with delimiter
; ArrayJoin(arr, delimiter) {
;     result := ""
;     for item in arr {
;         if result != ""
;             result .= delimiter
;         result .= item
;     }
;     return result
; }

; Helper: Check if value in array
HasValue(arr, value) {
    for item in arr {
        if item = value
            return true
    }
    return false
}



; ═══════════════════════════════════════════════════════════════════════════════
; CLIPBOARD REVOLVER SYSTEM
; ═══════════════════════════════════════════════════════════════════════════════
; CLIPBOARD REVOLVER SYSTEM

; ═══════════════════════════════════════════════════════════════════════════════
; LOADS PARSED CLIPBOARD FIELDS INTO A "REVOLVER" FOR SEQUENTIAL PASTING
; ═══════════════════════════════════════════════════════════════════════════════
; Loads parsed clipboard fields into a "revolver" for sequential pasting
; Each Ctrl+V fires the next field, then Tab, until all fields exhausted

LoadRevolver() {
    global g_ExtractedData

    ; Check we have extracted data
    if g_ExtractedData.Count = 0 {
        ShowStatus("No fields extracted! Parse clipboard first.", "fail")
        return false
    }

    ; Use the silent loader
    if LoadRevolverSilent() {
        SoundBeep(800, 50)  ; Chirp = loaded
        ShowStatus("Revolver loaded: " . g_RevolverChamber.Length . " shots", "ok")
        return true
    }
    return false
}

UnloadRevolver() {
    global g_RevolverLoaded, g_RevolverActive, g_RevolverChamber, g_RevolverPosition

    g_RevolverLoaded := false
    g_RevolverActive := false
    g_RevolverChamber := []
    g_RevolverPosition := 1

    ShowStatus("Revolver unloaded", "ok")
    UpdateRevolverDisplay()
}

; Full workflow: Copy, Parse, Load (silent - just loads the gun)
LoadRevolverFromSelection() {
    global g_ExtractedData, g_RevolverFieldOrder, g_Settings, ClipEdit
    global g_RevolverChamber, g_RevolverLoaded

    ; Step 1: Copy current selection
    A_Clipboard := ""
    Send("^c")
    ClipWait(1)

    if A_Clipboard = "" {
        ShowStatus("Nothing copied!", "fail")
        SoundBeep(300, 100)
        return false
    }

    ; Step 2: Store and parse
    ClipEdit.Value := A_Clipboard
    ParseClipboardForRevolver()

    ; Step 3: Load revolver silently
    if !LoadRevolverSilent() {
        SoundBeep(300, 100)
        return false
    }

    ; Feedback: loaded and ready
    SoundBeep(800, 50)  ; Quick chirp = loaded
    ShowStatus("Revolver loaded: " . g_RevolverChamber.Length . " shots ready", "ok")
    return true
}

; Fire all shots: paste + Tab + paste + Tab... (no Enter at end by default)
FireAllShots() {
    global g_RevolverChamber, g_RevolverLoaded, g_Settings

    if !g_RevolverLoaded || g_RevolverChamber.Length = 0 {
        ShowStatus("Revolver empty! Ctrl+B to load", "fail")
        SoundBeep(300, 100)
        return false
    }

    ; Fire each chamber
    Loop g_RevolverChamber.Length {
        chamber := g_RevolverChamber[A_Index]

        ShowStatus("[" . A_Index . "/" . g_RevolverChamber.Length . "] " . chamber["name"], "wait")

        ; Brief pause, type value, brief pause
        Sleep(g_Settings["PreActionDelay"])
        SendText(chamber["value"])
        Sleep(g_Settings["PostActionDelay"])

        ; Tab to next field (except after last)
        if A_Index < g_RevolverChamber.Length {
            Send("{Tab}")
            Sleep(50)
        }
    }

    ; Clear revolver
    shotsFired := g_RevolverChamber.Length
    g_RevolverChamber := []
    g_RevolverLoaded := false
    UpdateRevolverDisplay()

    ; Done!
    SoundBeep(600, 50)
    SoundBeep(800, 50)
    ShowStatus("Fired " . shotsFired . " shots!", "ok")
    return true
}

; Load revolver without any UI interaction (for workflow use)
LoadRevolverSilent() {
    global g_ExtractedData, g_RevolverChamber, g_RevolverPosition
    global g_RevolverFieldOrder, g_RevolverLoaded, g_RevolverActive, g_DemoClipboardActive

    if g_ExtractedData.Count = 0 {
        ShowStatus("No fields extracted!", "fail")
        return false
    }

    g_RevolverChamber := []
    g_RevolverPosition := 1

    fieldOrder := g_DemoClipboardActive ? ["LastName", "FirstName", "DOB", "CurrentDate"] : g_RevolverFieldOrder

    for fieldName in fieldOrder {
        if g_ExtractedData.Has(fieldName) {
            g_RevolverChamber.Push(Map(
                "name", fieldName,
                "value", g_ExtractedData[fieldName]
            ))
        }
    }

    if g_RevolverChamber.Length = 0 {
        ShowStatus("No matching fields!", "fail")
        return false
    }

    g_RevolverLoaded := true
    g_RevolverActive := false  ; Don't intercept Ctrl+V

    UpdateRevolverDisplay()
    return true
}

; Preview revolver contents for confirmation dialog
PreviewRevolverContents() {
    global g_RevolverChamber
    preview := ""
    for i, chamber in g_RevolverChamber {
        preview .= i . ". " . chamber["name"] . ": " . chamber["value"] . "`n"
    }
    return preview
}

; Fire revolver as a sequence step (for workflow integration)
FireRevolverSequence(tabBetween := true, enterAtEnd := false) {
    global g_RevolverChamber, g_RevolverLoaded, g_Settings

    if !g_RevolverLoaded || g_RevolverChamber.Length = 0 {
        ShowStatus("Revolver empty!", "fail")
        return false
    }

    Loop g_RevolverChamber.Length {
        chamber := g_RevolverChamber[A_Index]

        ShowStatus("[" . A_Index . "/" . g_RevolverChamber.Length . "] " . chamber["name"], "wait")

        Sleep(g_Settings["PreActionDelay"])
        SendText(chamber["value"])
        Sleep(g_Settings["PostActionDelay"])

        ; Tab to next field (except after last, unless enterAtEnd is false)
        if tabBetween && A_Index < g_RevolverChamber.Length {
            Send("{Tab}")
            Sleep(50)
        }
    }

    if enterAtEnd {
        Sleep(50)
        Send("{Enter}")
    }

    ; Clear revolver
    g_RevolverChamber := []
    g_RevolverLoaded := false
    UpdateRevolverDisplay()

    ShowStatus("Revolver fired!", "ok")
    return true
}

ParseClipboardForRevolver() {
    global g_ExtractionRules, g_ExtractedData, ClipEdit, ExtractLV, RulesLV, g_Settings
    text := ClipEdit.Value
    if text = ""
        return
    g_ExtractedData := Map()
    ExtractLV.Delete()
    RulesLV.Delete()
    for r in g_ExtractionRules {
        if RegExMatch(text, r["pattern"], &m) {
            val := Trim(m.Count > 0 ? m[1] : m[0])
            g_ExtractedData[r["name"]] := val
            ExtractLV.Add(, r["name"], val)
            RulesLV.Add(, r["name"], r["pattern"], val)
        } else {
            RulesLV.Add(, r["name"], r["pattern"], "(no match)")
        }
    }
    ; Always add CurrentDate
    g_ExtractedData["CurrentDate"] := FormatTime(, g_Settings["DateFormat"])
    ExtractLV.Add(, "CurrentDate", g_ExtractedData["CurrentDate"])
}

UpdateRevolverDisplay() {
    global g_RevolverChamber, g_RevolverPosition, g_RevolverActive, RevolverStatus, RevolverLV

    try {
        if !g_RevolverActive {
            RevolverStatus.Value := "Revolver: Empty"
            RevolverStatus.Opt("cGray")
        } else {
            remaining := g_RevolverChamber.Length - g_RevolverPosition + 1
            RevolverStatus.Value := "Revolver: " . remaining . " rounds loaded"
            RevolverStatus.Opt("cGreen")
        }

        ; Update ListView
        RevolverLV.Delete()
        for i, chamber in g_RevolverChamber {
            status := ""
            if i < g_RevolverPosition
                status := "✓ Fired"
            else if i = g_RevolverPosition
                status := "► Next"
            else
                status := "○ Ready"
            RevolverLV.Add(, i, chamber["name"], chamber["value"], status)
        }
    }
}

MoveFieldUp(*) {
    global FieldOrderLV, g_RevolverFieldOrder
    row := FieldOrderLV.GetNext(0, "Focused")
    if row < 2
        return
    ; Swap in array
    temp := g_RevolverFieldOrder[row]
    g_RevolverFieldOrder[row] := g_RevolverFieldOrder[row - 1]
    g_RevolverFieldOrder[row - 1] := temp
    RefreshFieldOrderLV()
    FieldOrderLV.Modify(row - 1, "Select Focus")
    SaveFieldOrder()
}

MoveFieldDown(*) {
    global FieldOrderLV, g_RevolverFieldOrder
    row := FieldOrderLV.GetNext(0, "Focused")
    if row = 0 || row >= g_RevolverFieldOrder.Length
        return
    ; Swap in array
    temp := g_RevolverFieldOrder[row]
    g_RevolverFieldOrder[row] := g_RevolverFieldOrder[row + 1]
    g_RevolverFieldOrder[row + 1] := temp
    RefreshFieldOrderLV()
    FieldOrderLV.Modify(row + 1, "Select Focus")
    SaveFieldOrder()
}

AddFieldToOrder(*) {
    global g_RevolverFieldOrder, g_ExtractionRules
    ; Show available fields
    available := ["CurrentDate"]
    for r in g_ExtractionRules
        available.Push(r["name"])

    ; Simple input
    res := InputBoxTop("Field name to add:`n(Available: " . ArrayJoin(available, ", ") . ")", "Add Field", "")
    if res["Result"] = "OK" && res["Value"] != "" {
        g_RevolverFieldOrder.Push(res["Value"])
        RefreshFieldOrderLV()
        SaveFieldOrder()
    }
}

RemoveFieldFromOrder(*) {
    global FieldOrderLV, g_RevolverFieldOrder
    row := FieldOrderLV.GetNext(0, "Focused")
    if row = 0
        return
    g_RevolverFieldOrder.RemoveAt(row)
    RefreshFieldOrderLV()
    SaveFieldOrder()
}

RefreshFieldOrderLV() {
    global FieldOrderLV, g_RevolverFieldOrder
    FieldOrderLV.Delete()
    for i, name in g_RevolverFieldOrder
        FieldOrderLV.Add(, i, name)
}

ArrayJoin(arr, sep := ", ") {
    result := ""
    for i, v in arr
        result .= (i > 1 ? sep : "") . v
    return result
}
;ArrayJoin(arr, delimiter) {
;     result := ""
;     for item in arr {
;         if result != ""
;             result .= delimiter
;         result .= item
;     }
;     return result
; }

SaveFieldOrder() {
    global g_RevolverFieldOrder, SETTINGS_FILE
    orderStr := ArrayJoin(g_RevolverFieldOrder, "|")
    FanIniWrite(orderStr, SETTINGS_FILE, "Revolver", "FieldOrder")
}

LoadFieldOrder() {
    global g_RevolverFieldOrder, SETTINGS_FILE
    orderStr := FanIniRead(SETTINGS_FILE, "Revolver", "FieldOrder", "LastName|FirstName|DOB|CurrentDate")
    g_RevolverFieldOrder := StrSplit(orderStr, "|")
}



; ═══════════════════════════════════════════════════════════════════════════════
; CLIPBOARD
; ═══════════════════════════════════════════════════════════════════════════════
; CLIPBOARD
; =============================================================================

GrabClip(*) {
    global ClipEdit
    ClipEdit.Value := A_Clipboard
}

ParseClip(*) {
    global g_ExtractionRules, g_ExtractedData, ClipEdit, ExtractLV, RulesLV, g_Settings
    text := ClipEdit.Value
    if text = ""
        return
    g_ExtractedData := Map()
    ExtractLV.Delete()
    RulesLV.Delete()
    for r in g_ExtractionRules {
        if RegExMatch(text, r["pattern"], &m) {
            val := Trim(m.Count > 0 ? m[1] : m[0])
            g_ExtractedData[r["name"]] := val
            ExtractLV.Add(, r["name"], val)
            RulesLV.Add(, r["name"], r["pattern"], val)
        } else {
            RulesLV.Add(, r["name"], r["pattern"], "(no match)")
        }
    }
    g_ExtractedData["CurrentDate"] := FormatTime(, g_Settings["DateFormat"])
    PopulateChoices()
}

ClearClip(*) {
    global ClipEdit, ExtractLV, g_ExtractedData
    ClipEdit.Value := ""
    ExtractLV.Delete()
    g_ExtractedData := Map()
}

AddRule(*) {
    global g_ExtractionRules, RulesLV
    saved := MainGui.Submit(false)
    if saved.PatternNameClip = "" || saved.PatternRegex = ""
        return
    try {
        RegExMatch("test", saved.PatternRegex)
    } catch {
        MsgBoxTop("Invalid regex!", "Error")
        return
    }
    g_ExtractionRules.Push(Map("name", saved.PatternNameClip, "pattern", saved.PatternRegex))
    RulesLV.Add(, saved.PatternNameClip, saved.PatternRegex, "")
    SaveExtractionRules()
}

DelRule(*) {
    global g_ExtractionRules, RulesLV
    row := RulesLV.GetNext(0, "Focused")
    if row = 0
        return
    name := RulesLV.GetText(row, 1)
    for i, r in g_ExtractionRules
        if r["name"] = name {
            g_ExtractionRules.RemoveAt(i)
            break
        }
    RulesLV.Delete(row)
    SaveExtractionRules()
}


ExtractClipboardByRule(rule) {
    source := A_Clipboard
    rule := Trim(rule)
    extracted := ""

    if InStr(rule, "between:") = 1 {
        payload := SubStr(rule, 9)
        separator := InStr(payload, "|")
        if separator {
            startText := SubStr(payload, 1, separator - 1)
            endText := SubStr(payload, separator + 1)
            startPos := InStr(source, startText)
            if startPos {
                contentStart := startPos + StrLen(startText)
                endPos := InStr(source, endText, , contentStart)
                if endPos
                    extracted := SubStr(source, contentStart, endPos - contentStart)
            }
        }
    } else if InStr(rule, "field:") = 1 {
        payload := SubStr(rule, 7)
        separator := InStr(payload, "|", , -1)
        if separator {
            delimiter := SubStr(payload, 1, separator - 1)
            indexText := Trim(SubStr(payload, separator + 1))
            if delimiter != "" && IsNumber(indexText) {
                fields := StrSplit(source, delimiter)
                index := Integer(indexText)
                if index >= 1 && index <= fields.Length
                    extracted := Trim(fields[index])
            }
        }
    } else if InStr(rule, "regex:") = 1 {
        pattern := SubStr(rule, 7)
        try {
            if RegExMatch(source, pattern, &match)
                extracted := match[0]
        } catch as err {
            ShowStatus("Invalid extraction regex: " . err.Message, "fail")
            return false
        }
    }

    if extracted = "" {
        ShowStatus("Extract from Clipboard: rule did not match", "fail")
        return false
    }
    A_Clipboard := extracted
    ShowStatus("Clipboard extraction complete", "ok")
    return true
}


RefreshRulesLV() {
    global g_ExtractionRules, RulesLV
    RulesLV.Delete()
    for r in g_ExtractionRules
        RulesLV.Add(, r["name"], r["pattern"], "")
}

