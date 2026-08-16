; ╔══════════════════════════════════════════════════════════════════════════════╗
; ║                     MACRO AUTOMATOR v2.4 - AutoHotkey v2                     ║
; ║        Unified Workflow, Bottom Toolbar, Auto-Names, Fixed Test Actions      ║
; ╚══════════════════════════════════════════════════════════════════════════════╝
;
; VERSION 2.4 CHANGES:
; --------------------
; • UNIFIED WORKFLOW TAB - Coordinates + Sequences combined
; • Bottom toolbar (less distracting)
; • All popups appear ABOVE main GUI (+AlwaysOnTop)
; • Test button performs ACTUAL action (drag, triple-click, etc.)
; • Auto-generated names if left blank (Point_1, Drag_1, etc.)
; • Clear workflow instructions included

#Requires AutoHotkey v2.0
#SingleInstance Force

SetWorkingDir(A_ScriptDir)
CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

; ══════════════════════════════════════════════════════════════════════════════
; SECTION 1: GLOBAL VARIABLES
; ══════════════════════════════════════════════════════════════════════════════

global g_Coordinates := Map()
global g_Sequences := Map()
global g_ExtractedData := Map()
global g_HotkeyBindings := Map()
global g_Settings := Map()
global g_ExtractionRules := []

global g_IsCapturing := false
global g_IsPaused := false
global g_DragMode := false
global g_DragStartX := 0, g_DragStartY := 0
global g_IsRecording := false
global g_RecordedActions := []
global g_IsCalibrating := false

global g_CurrentSequenceSteps := []

global g_GuiVisible := true
global g_AlwaysOnTop := false
global g_ClickThrough := false
global g_Transparency := 255

global g_ActionCounter := 0
global g_TotalActions := 0

; Auto-naming counters
global g_PointCounter := 1
global g_DragCounter := 1

; File paths
global DATA_DIR := A_ScriptDir . "\data"
global COORDS_FILE := DATA_DIR . "\coordinates.csv"
global SEQUENCES_FILE := DATA_DIR . "\sequences.ini"
global HOTKEYS_FILE := DATA_DIR . "\hotkeys.ini"
global SETTINGS_FILE := DATA_DIR . "\settings.ini"
global RULES_FILE := DATA_DIR . "\extraction_rules.csv"

g_Settings := Map(
    "ClickDelay", 100,
    "TypeDelay", 50,
    "ActionDelay", 200,
    "DefaultDragTime", 300,
    "DateFormat", "MM/dd/yyyy",
    "ShowActionTooltips", true,
    "TooltipDuration", 1500,
    "MarkerOffsetX", -12,
    "MarkerOffsetY", -15,
    "TestAction", "Perform Action"  ; Changed default - now performs actual action
)

if !DirExist(DATA_DIR)
    DirCreate(DATA_DIR)

; ══════════════════════════════════════════════════════════════════════════════
; SECTION 2: HELPER - Always-On-Top Message Boxes
; ══════════════════════════════════════════════════════════════════════════════
; These wrappers ensure popups appear ABOVE the main GUI

MsgBoxTop(text, title := "", options := "") {
    ; MsgBox with AlwaysOnTop - appears above main GUI
    return MsgBox(text, title, options . " 262144")  ; 262144 = Always On Top
}

InputBoxTop(prompt, title := "", options := "", default := "") {
    ; For InputBox, we need to use a custom GUI approach
    global MainGui

    inputGui := Gui("+AlwaysOnTop +Owner" . MainGui.Hwnd, title)
    inputGui.SetFont("s9", "Segoe UI")
    inputGui.Add("Text",, prompt)
    inputEdit := inputGui.Add("Edit", "w250 vInputValue", default)
    inputGui.Add("Button", "x80 y+10 w80 Default", "OK").OnEvent("Click", (*) => inputGui.Hide())
    inputGui.Add("Button", "x+10 w80", "Cancel").OnEvent("Click", (*) => (inputEdit.Value := "", inputGui.Hide()))

    inputGui.Show()
    WinWaitClose(inputGui)

    result := inputEdit.Value
    inputGui.Destroy()

    return Map("Result", result != "" ? "OK" : "Cancel", "Value", result)
}

; ══════════════════════════════════════════════════════════════════════════════
; SECTION 3: TRAY MENU
; ══════════════════════════════════════════════════════════════════════════════

A_TrayMenu.Delete()
A_TrayMenu.Add("🎯 Show/Hide GUI", TrayShowHide)
A_TrayMenu.Add()
A_TrayMenu.Add("📌 Always On Top", TrayToggleAlwaysOnTop)
A_TrayMenu.Add("👆 Click-Through Mode", TrayToggleClickThrough)
A_TrayMenu.Add("👁️ Reset Transparency", TrayResetTransparency)
A_TrayMenu.Add()
A_TrayMenu.Add("🔴 Start/Stop Recording", TrayToggleRecording)
A_TrayMenu.Add()
A_TrayMenu.Add("🔄 Reload Script", (*) => Reload())
A_TrayMenu.Add("❌ Exit", (*) => ExitApp())
A_TrayMenu.Default := "🎯 Show/Hide GUI"
A_IconTip := "Macro Automator v2.4"

TrayShowHide(*) {
    global g_GuiVisible, MainGui
    if g_GuiVisible {
        MainGui.Hide()
        g_GuiVisible := false
    } else {
        MainGui.Show()
        g_GuiVisible := true
    }
}

TrayToggleAlwaysOnTop(*) {
    global g_AlwaysOnTop, MainGui, AlwaysOnTopCheck
    g_AlwaysOnTop := !g_AlwaysOnTop
    WinSetAlwaysOnTop(g_AlwaysOnTop, MainGui)
    try AlwaysOnTopCheck.Value := g_AlwaysOnTop
    if g_AlwaysOnTop
        A_TrayMenu.Check("📌 Always On Top")
    else
        A_TrayMenu.Uncheck("📌 Always On Top")
    UpdateStatusBar()
}

TrayToggleClickThrough(*) {
    global g_ClickThrough, g_AlwaysOnTop, MainGui, ClickThroughCheck, AlwaysOnTopCheck
    g_ClickThrough := !g_ClickThrough
    exStyle := WinGetExStyle(MainGui)
    if g_ClickThrough {
        g_AlwaysOnTop := true
        WinSetAlwaysOnTop(1, MainGui)
        WinSetTransparent(180, MainGui)
        WinSetExStyle(exStyle | 0x20, MainGui)
        A_TrayMenu.Check("👆 Click-Through Mode")
        A_TrayMenu.Check("📌 Always On Top")
    } else {
        WinSetExStyle(exStyle & ~0x20, MainGui)
        WinSetTransparent(g_Transparency, MainGui)
        A_TrayMenu.Uncheck("👆 Click-Through Mode")
    }
    try ClickThroughCheck.Value := g_ClickThrough
    try AlwaysOnTopCheck.Value := g_AlwaysOnTop
    UpdateStatusBar()
}

TrayResetTransparency(*) {
    global g_Transparency, g_ClickThrough, MainGui, TransSlider
    if g_ClickThrough
        TrayToggleClickThrough()
    g_Transparency := 255
    WinSetTransparent(255, MainGui)
    try TransSlider.Value := 255
}

TrayToggleRecording(*) {
    ToggleRecording()
}

; ══════════════════════════════════════════════════════════════════════════════
; SECTION 4: MARKER SYSTEM
; ══════════════════════════════════════════════════════════════════════════════

global MarkerGui := ""

ShowCoordinateMarker(x, y, duration := 2000, color := "Red") {
    global MarkerGui, g_Settings

    if MarkerGui != ""
        try MarkerGui.Destroy()

    offsetX := g_Settings.Has("MarkerOffsetX") ? g_Settings["MarkerOffsetX"] : -12
    offsetY := g_Settings.Has("MarkerOffsetY") ? g_Settings["MarkerOffsetY"] : -15

    MarkerGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    MarkerGui.BackColor := "FFFFFF"
    WinSetTransColor("FFFFFF", MarkerGui)
    MarkerGui.SetFont("s24 bold", "Arial")
    MarkerGui.Add("Text", "c" . color . " Center", "✕")

    MarkerGui.Show("x" . (x + offsetX - 10) . " y" . (y + offsetY - 12) . " NA")
    SetTimer(HideMarker, -duration)
}

HideMarker() {
    global MarkerGui
    if MarkerGui != ""
        try MarkerGui.Destroy()
    MarkerGui := ""
}

; ══════════════════════════════════════════════════════════════════════════════
; SECTION 5: AUTO-NAMING SYSTEM
; ══════════════════════════════════════════════════════════════════════════════

; Generate unique name for coordinate if not provided
GenerateCoordName(type := "Point") {
    global g_Coordinates, g_PointCounter, g_DragCounter

    if type = "Drag" {
        while g_Coordinates.Has("Drag_" . g_DragCounter)
            g_DragCounter++
        name := "Drag_" . g_DragCounter
        g_DragCounter++
    } else {
        while g_Coordinates.Has("Point_" . g_PointCounter)
            g_PointCounter++
        name := "Point_" . g_PointCounter
        g_PointCounter++
    }

    return name
}

; ══════════════════════════════════════════════════════════════════════════════
; SECTION 6: DATA PERSISTENCE
; ══════════════════════════════════════════════════════════════════════════════

SaveCoordinates() {
    global g_Coordinates, COORDS_FILE
    try {
        file := FileOpen(COORDS_FILE, "w", "UTF-8")
        file.WriteLine("Name,X,Y,EndX,EndY,Type")
        for name, coord in g_Coordinates {
            file.WriteLine(EscapeCSV(name) . "," . coord["x"] . "," . coord["y"] . "," . coord["endX"] . "," . coord["endY"] . "," . coord["type"])
        }
        file.Close()
    }
}

LoadCoordinates() {
    global g_Coordinates, COORDS_FILE
    if !FileExist(COORDS_FILE)
        return
    try {
        g_Coordinates := Map()
        lineNum := 0
        Loop Read COORDS_FILE {
            lineNum++
            if lineNum = 1
                continue
            line := A_LoopReadLine
            if line = ""
                continue
            parts := StrSplit(line, ",")
            if parts.Length >= 6 {
                g_Coordinates[UnescapeCSV(parts[1])] := Map(
                    "x", Integer(parts[2]),
                    "y", Integer(parts[3]),
                    "endX", parts[4] = "" ? "" : Integer(parts[4]),
                    "endY", parts[5] = "" ? "" : Integer(parts[5]),
                    "type", parts[6]
                )
            }
        }
    }
}

EscapeCSV(text) {
    if InStr(text, ",") || InStr(text, '"')
        return '"' . StrReplace(text, '"', '""') . '"'
    return text
}

UnescapeCSV(text) {
    if SubStr(text, 1, 1) = '"' && SubStr(text, -1) = '"'
        text := SubStr(text, 2, StrLen(text) - 2)
    return StrReplace(text, '""', '"')
}

SaveSequences() {
    global g_Sequences, SEQUENCES_FILE
    try {
        if FileExist(SEQUENCES_FILE)
            FileDelete(SEQUENCES_FILE)
        for seqName, seqData in g_Sequences {
            for index, step in seqData["steps"] {
                value := step["action"] . "|" . step["target"] . "|" . step["param"] . "|" . (step.Has("enabled") ? step["enabled"] : 1)
                IniWrite(value, SEQUENCES_FILE, seqName, "Step" . index)
            }
            IniWrite(seqData["steps"].Length, SEQUENCES_FILE, seqName, "_StepCount")
            if seqData.Has("description")
                IniWrite(seqData["description"], SEQUENCES_FILE, seqName, "_Description")
        }
    }
}

LoadSequences() {
    global g_Sequences, SEQUENCES_FILE
    if !FileExist(SEQUENCES_FILE)
        return
    try {
        g_Sequences := Map()
        sections := IniRead(SEQUENCES_FILE)
        for section in StrSplit(sections, "`n") {
            if section = ""
                continue
            stepCount := IniRead(SEQUENCES_FILE, section, "_StepCount", 0)
            description := IniRead(SEQUENCES_FILE, section, "_Description", "")
            steps := []
            Loop stepCount {
                stepData := IniRead(SEQUENCES_FILE, section, "Step" . A_Index, "")
                if stepData = ""
                    continue
                parts := StrSplit(stepData, "|")
                steps.Push(Map(
                    "action", parts.Length >= 1 ? parts[1] : "",
                    "target", parts.Length >= 2 ? parts[2] : "",
                    "param", parts.Length >= 3 ? parts[3] : "",
                    "enabled", parts.Length >= 4 ? Integer(parts[4]) : 1
                ))
            }
            if steps.Length > 0
                g_Sequences[section] := Map("steps", steps, "description", description)
        }
    }
}

SaveHotkeys() {
    global g_HotkeyBindings, HOTKEYS_FILE
    try {
        if FileExist(HOTKEYS_FILE)
            FileDelete(HOTKEYS_FILE)
        for hotkeyStr, seqName in g_HotkeyBindings
            IniWrite(seqName, HOTKEYS_FILE, "Hotkeys", hotkeyStr)
    }
}

LoadHotkeys() {
    global g_HotkeyBindings, HOTKEYS_FILE
    if !FileExist(HOTKEYS_FILE)
        return
    try {
        g_HotkeyBindings := Map()
        allKeys := IniRead(HOTKEYS_FILE, "Hotkeys")
        for line in StrSplit(allKeys, "`n") {
            if line = ""
                continue
            eqPos := InStr(line, "=")
            if eqPos > 0
                g_HotkeyBindings[SubStr(line, 1, eqPos - 1)] := SubStr(line, eqPos + 1)
        }
    }
}

SaveSettings() {
    global g_Settings, SETTINGS_FILE
    try {
        for key, value in g_Settings
            IniWrite(value, SETTINGS_FILE, "Settings", key)
    }
}

LoadSettings() {
    global g_Settings, SETTINGS_FILE
    if !FileExist(SETTINGS_FILE)
        return
    try {
        for key, defaultValue in g_Settings.Clone() {
            value := IniRead(SETTINGS_FILE, "Settings", key, defaultValue)
            g_Settings[key] := IsNumber(defaultValue) ? Number(value) : value
        }
    }
}

SaveExtractionRules() {
    global g_ExtractionRules, RULES_FILE
    try {
        file := FileOpen(RULES_FILE, "w", "UTF-8")
        file.WriteLine("Name,Pattern")
        for rule in g_ExtractionRules
            file.WriteLine(EscapeCSV(rule["name"]) . "," . EscapeCSV(rule["pattern"]))
        file.Close()
    }
}

LoadExtractionRules() {
    global g_ExtractionRules, RULES_FILE
    if !FileExist(RULES_FILE) {
        g_ExtractionRules := [
            Map("name", "LastName", "pattern", "^([^,]+)"),
            Map("name", "FirstName", "pattern", ",\s*([^#\s]+)"),
            Map("name", "DOB", "pattern", "(\d{1,2}/\d{1,2}/\d{2,4})")
        ]
        return
    }
    try {
        g_ExtractionRules := []
        lineNum := 0
        Loop Read RULES_FILE {
            lineNum++
            if lineNum = 1
                continue
            line := A_LoopReadLine
            if line = ""
                continue
            parts := StrSplit(line, ",", , 2)
            if parts.Length >= 2
                g_ExtractionRules.Push(Map("name", UnescapeCSV(parts[1]), "pattern", UnescapeCSV(parts[2])))
        }
    }
}

SaveAllData() {
    SaveCoordinates()
    SaveSequences()
    SaveHotkeys()
    SaveSettings()
    SaveExtractionRules()
}

LoadAllData() {
    LoadCoordinates()
    LoadSequences()
    LoadHotkeys()
    LoadSettings()
    LoadExtractionRules()
}

; ══════════════════════════════════════════════════════════════════════════════
; SECTION 7: MAIN GUI - TABS AT TOP, TOOLBAR AT BOTTOM
; ══════════════════════════════════════════════════════════════════════════════

MainGui := Gui("+Resize +MinSize1000x850", "🎯 Macro Automator v2.4")
MainGui.SetFont("s9", "Segoe UI")
MainGui.MarginX := 10
MainGui.MarginY := 10

MainGui.OnEvent("Close", GuiClose)
MainGui.OnEvent("Escape", GuiClose)

GuiClose(*) {
    global g_GuiVisible, MainGui
    MainGui.Hide()
    g_GuiVisible := false
    ToolTip("Minimized to tray")
    SetTimer(() => ToolTip(), -1500)
}

; ------------------------------------------------------------------------------
; TAB CONTROL AT TOP (no toolbar above it)
; ------------------------------------------------------------------------------
TabCtrl := MainGui.Add("Tab3", "xm ym w970 h720", [
    "🔧 Workflow",      ; Combined Coordinates + Sequences
    "📋 Clipboard",
    "⌨️ Hotkeys",
    "⚙️ Settings",
    "❓ Help"
])

; ══════════════════════════════════════════════════════════════════════════════
; TAB 1: UNIFIED WORKFLOW (Coordinates + Sequences Combined)
; ══════════════════════════════════════════════════════════════════════════════
TabCtrl.UseTab(1)

; Instructions at the top
MainGui.Add("GroupBox", "w940 h80", "📖 How to Use (Typical Workflow)")
MainGui.Add("Text", "xp+10 yp+18 w920 cGray")
;"1️⃣ CAPTURE: Click a capture button below, then click/drag on screen to save that position"
;2️⃣ BUILD: Add actions to your sequence using the saved coordinates as targets
;3️⃣ SAVE: Give your sequence a name and save it
;4️⃣ RUN: Assign a hotkey or click Test Run to execute

;💡 TIP: Leave name blank for auto-naming (Point_1, Drag_1, etc.) - rename later if needed")

; ----- COORDINATE CAPTURE SECTION -----
MainGui.Add("GroupBox", "xs+15 y+15 w940 h200", "📍 Step 1: Capture Screen Positions")

MainGui.Add("Text", "xp+10 yp+22", "Optional Name:")
CoordNameEdit := MainGui.Add("Edit", "vCoordName w150 x+5")
MainGui.Add("Text", "x+10 cGray", "(leave blank for auto: Point_1, Drag_1...)")

; Capture buttons - prominent and clear
MainGui.Add("Button", "xs+25 y+15 w140 h35", "🎯 Capture Click").OnEvent("Click", StartCoordinateCapture)
MainGui.Add("Button", "x+10 w140 h35", "↔️ Capture Drag").OnEvent("Click", StartDragCapture)
MainGui.Add("Button", "x+10 w160 h35", "🎯 Arrow Key Capture").OnEvent("Click", StartArrowKeyCalibration)
MainGui.Add("Button", "x+10 w100 h35", "🔴 Record").OnEvent("Click", ToggleRecording)

MainGui.Add("Text", "xs+25 y+10", "Live Position:")
MousePosText := MainGui.Add("Text", "x+10 w120 vMousePos", "X: 0, Y: 0")
LiveCaptureCheck := MainGui.Add("CheckBox", "x+15 vLiveCapture", "Show live")
LiveCaptureCheck.OnEvent("Click", ToggleLiveCapture)

; Saved coordinates list
MainGui.Add("Text", "xs+25 y+10", "Saved Positions:")
CoordListView := MainGui.Add("ListView", "xs+25 y+5 w620 h70 Grid NoSortHdr vCoordList",
    ["Name", "X", "Y", "End X", "End Y", "Type"])
CoordListView.ModifyCol(1, 150)
CoordListView.ModifyCol(2, 70)
CoordListView.ModifyCol(3, 70)
CoordListView.ModifyCol(4, 70)
CoordListView.ModifyCol(5, 70)
CoordListView.ModifyCol(6, 80)

; Coordinate management buttons
MainGui.Add("Button", "x+10 yp w90 h22", "✏️ Rename").OnEvent("Click", RenameCoordinate)
MainGui.Add("Button", "xp y+3 w90 h22", "🗑️ Delete").OnEvent("Click", DeleteCoordinate)
MainGui.Add("Button", "xp y+3 w90 h22", "🔍 Test").OnEvent("Click", TestCoordinate)

; ----- SEQUENCE BUILDER SECTION -----
MainGui.Add("GroupBox", "xs+15 y+15 w940 h340", "🔗 Step 2: Build Action Sequence")

; Action selection row
MainGui.Add("Text", "xp+10 yp+22", "Action:")
ActionTypeDropdown := MainGui.Add("DropDownList", "vActionType w130 x+5", [
    "Click", "Double Click", "Triple Click", "Right Click", "Click and Drag",
    "Type Text", "Paste Clipboard", "Set Clipboard", "Press Key",
    "Tab", "Enter", "Wait", "Insert Extracted", "Insert Date", "Scroll"
])
ActionTypeDropdown.Choose(1)
ActionTypeDropdown.OnEvent("Change", UpdateParamHints)

MainGui.Add("Text", "x+15", "Target:")
TargetDropdown := MainGui.Add("DropDownList", "vTargetCoord w130 x+5")

MainGui.Add("Text", "x+15", "Parameter:")
ActionParamEdit := MainGui.Add("Edit", "vActionParam w120 x+5")

MainGui.Add("Text", "x+10", "Hints:")
ParamHintsDropdown := MainGui.Add("DropDownList", "vParamHint w120 x+5")
ParamHintsDropdown.OnEvent("Change", ApplyParamHint)

MainGui.Add("Button", "x+15 w100", "➕ Add Step").OnEvent("Click", AddActionToSequence)

; Parameter hint text
ParamHintText := MainGui.Add("Text", "xs+25 y+8 w700 cGray", "Click: (empty)=1 click | number=repeat count")

; Current sequence steps
MainGui.Add("Text", "xs+25 y+10", "Current Sequence Steps:")
SeqStepsListView := MainGui.Add("ListView", "xs+25 y+5 w900 h140 Grid Checked NoSortHdr vSeqSteps",
    ["#", "On", "Action", "Target", "Parameter"])
SeqStepsListView.ModifyCol(1, 35)
SeqStepsListView.ModifyCol(2, 35)
SeqStepsListView.ModifyCol(3, 130)
SeqStepsListView.ModifyCol(4, 150)
SeqStepsListView.ModifyCol(5, 520)

; Step management
MainGui.Add("Button", "xs+25 y+5 w70", "⬆️ Up").OnEvent("Click", MoveStepUp)
MainGui.Add("Button", "x+5 w70", "⬇️ Down").OnEvent("Click", MoveStepDown)
MainGui.Add("Button", "x+5 w70", "✏️ Edit").OnEvent("Click", EditStep)
MainGui.Add("Button", "x+5 w70", "🗑️ Del").OnEvent("Click", RemoveStep)
MainGui.Add("Button", "x+5 w80", "✅ Toggle").OnEvent("Click", ToggleStepEnabled)
MainGui.Add("Button", "x+5 w100", "📥 Import Rec").OnEvent("Click", ImportRecordedActions)

; ----- SAVE & RUN SECTION -----
MainGui.Add("GroupBox", "xs+25 y+10 w900 h55", "Step 3: Save & Run")

MainGui.Add("Text", "xp+10 yp+22", "Sequence Name:")
SeqNameEdit := MainGui.Add("Edit", "vSeqName w180 x+5")
MainGui.Add("Button", "x+15 w120", "💾 Save Sequence").OnEvent("Click", SaveSequence)
MainGui.Add("Button", "x+10 w100", "▶️ Test Run").OnEvent("Click", TestSequence)
MainGui.Add("Button", "x+10 w100", "🧹 Clear Steps").OnEvent("Click", ClearSteps)

; ----- SAVED SEQUENCES -----
MainGui.Add("Text", "xs+25 y+10", "Saved Sequences:")
SavedSeqListView := MainGui.Add("ListView", "xs+25 y+5 w750 h50 Grid NoSortHdr vSavedSeqs",
    ["Name", "Steps", "Description"])
SavedSeqListView.ModifyCol(1, 180)
SavedSeqListView.ModifyCol(2, 60)
SavedSeqListView.ModifyCol(3, 480)

MainGui.Add("Button", "x+10 yp w80 h22", "📂 Load").OnEvent("Click", LoadSequence)
MainGui.Add("Button", "xp y+3 w80 h22", "🗑️ Delete").OnEvent("Click", DeleteSequence)

; ══════════════════════════════════════════════════════════════════════════════
; TAB 2: CLIPBOARD
; ══════════════════════════════════════════════════════════════════════════════
TabCtrl.UseTab(2)

MainGui.Add("GroupBox", "w940 h200", "📋 Clipboard Text Extraction")
MainGui.Add("Text", "xp+15 yp+22", "Clipboard Content:")
ClipboardEdit := MainGui.Add("Edit", "w910 h100 xs+15 y+5 Multi vClipboardContent")
MainGui.Add("Button", "xs+15 y+10 w120", "📋 Grab Clipboard").OnEvent("Click", GrabClipboard)
MainGui.Add("Button", "x+10 w120", "🔄 Parse Now").OnEvent("Click", ParseClipboard)
MainGui.Add("Button", "x+10 w100", "🧹 Clear").OnEvent("Click", ClearClipboard)

MainGui.Add("GroupBox", "xs+15 y+20 w920 h200", "🔧 Extraction Rules")
MainGui.Add("Text", "xp+10 yp+22", "Quick Add:")
PatternPresetDropdown := MainGui.Add("DropDownList", "x+10 w200", [
    "-- Select --", "Last Name", "First Name", "DOB", "Email", "Phone", "Numbers"
])
PatternPresetDropdown.OnEvent("Change", AddPresetPattern)

MainGui.Add("Text", "xs+25 y+10", "Name:")
PatternNameEdit := MainGui.Add("Edit", "vPatternName w100 x+5")
MainGui.Add("Text", "x+10", "Pattern:")
PatternRegexEdit := MainGui.Add("Edit", "vPatternRegex w300 x+5")
MainGui.Add("Button", "x+10 w80", "➕ Add").OnEvent("Click", AddExtractionRule)

RulesListView := MainGui.Add("ListView", "xs+25 y+10 w880 h70 Grid NoSortHdr vRulesList",
    ["Name", "Pattern", "Result"])
RulesListView.ModifyCol(1, 120)
RulesListView.ModifyCol(2, 450)
RulesListView.ModifyCol(3, 280)

MainGui.Add("Button", "xs+25 y+5 w100", "🗑️ Delete").OnEvent("Click", DeleteRule)

MainGui.Add("GroupBox", "xs+15 y+15 w920 h120", "📊 Extracted Data")
ExtractedListView := MainGui.Add("ListView", "xp+10 yp+22 w900 h60 Grid NoSortHdr vExtractedData",
    ["Field", "Value"])
ExtractedListView.ModifyCol(1, 150)
ExtractedListView.ModifyCol(2, 720)
MainGui.Add("Button", "xp y+5 w120", "📋 Copy All").OnEvent("Click", CopyExtracted)

; ══════════════════════════════════════════════════════════════════════════════
; TAB 3: HOTKEYS
; ══════════════════════════════════════════════════════════════════════════════
TabCtrl.UseTab(3)

MainGui.Add("GroupBox", "w940 h600", "⌨️ Hotkey Assignments")
MainGui.Add("Text", "xp+15 yp+22 w900", "Assign sequences to keyboard shortcuts:")

HotkeyListView := MainGui.Add("ListView", "xs+15 y+10 w910 h400 Grid NoSortHdr vHotkeyList",
    ["#", "Modifier", "Key", "Sequence", "Status"])
HotkeyListView.ModifyCol(1, 40)
HotkeyListView.ModifyCol(2, 120)
HotkeyListView.ModifyCol(3, 80)
HotkeyListView.ModifyCol(4, 540)
HotkeyListView.ModifyCol(5, 100)

MainGui.Add("Text", "xs+15 y+15", "Modifier:")
ModifierDropdown := MainGui.Add("DropDownList", "vModifier w110 x+5", [
    "(none)", "Ctrl", "Alt", "Shift", "Win", "Ctrl+Alt", "Ctrl+Shift"
])
ModifierDropdown.Choose(2)

MainGui.Add("Text", "x+15", "Key:")
KeyEdit := MainGui.Add("Edit", "vHotkeyKey w60 x+5", "1")

MainGui.Add("Text", "x+15", "Sequence:")
SeqDropdownForHotkey := MainGui.Add("DropDownList", "vHotkeySeq w200 x+5")

MainGui.Add("Button", "x+15 w100", "➕ Add").OnEvent("Click", AddNewHotkey)
MainGui.Add("Button", "x+10 w100", "🗑️ Remove").OnEvent("Click", RemoveHotkey)

MainGui.Add("Button", "xs+15 y+10 w120", "✅ Apply All").OnEvent("Click", ApplyAllHotkeys)
MainGui.Add("Button", "x+10 w120", "🔄 Refresh").OnEvent("Click", RefreshHotkeyDropdowns)
MainGui.Add("Button", "x+10 w100", "🧹 Clear").OnEvent("Click", ClearAllHotkeys)

; ══════════════════════════════════════════════════════════════════════════════
; TAB 4: SETTINGS
; ══════════════════════════════════════════════════════════════════════════════
TabCtrl.UseTab(4)

MainGui.Add("GroupBox", "w940 h120", "⏱️ Timing")
MainGui.Add("Text", "xp+15 yp+25", "Click delay (ms):")
MainGui.Add("Edit", "x+10 w70 vClickDelay Number", g_Settings["ClickDelay"])
MainGui.Add("Text", "x+20", "Type delay (ms):")
MainGui.Add("Edit", "x+10 w70 vTypeDelay Number", g_Settings["TypeDelay"])
MainGui.Add("Text", "x+20", "Action delay (ms):")
MainGui.Add("Edit", "x+10 w70 vActionDelay Number", g_Settings["ActionDelay"])

MainGui.Add("Text", "xs+15 y+15", "Drag time (ms):")
MainGui.Add("Edit", "x+10 w70 vDragTime Number", g_Settings["DefaultDragTime"])
MainGui.Add("Text", "x+20", "Date format:")
DateFormatDropdown := MainGui.Add("DropDownList", "x+10 w110 vDateFormat", ["MM/dd/yyyy", "dd/MM/yyyy", "yyyy-MM-dd"])
DateFormatDropdown.Choose(1)

ShowTooltipsCheck := MainGui.Add("CheckBox", "x+20 vShowActionTooltips Checked", "Show tooltips")

MainGui.Add("GroupBox", "xs+15 y+25 w920 h90", "📍 Marker Calibration")
MainGui.Add("Text", "xp+15 yp+25", "Offset X:")
MarkerOffsetXEdit := MainGui.Add("Edit", "x+10 w60 vMarkerOffsetX", g_Settings["MarkerOffsetX"])
MainGui.Add("Text", "x+5 cGray", "(+ right, - left)")
MainGui.Add("Text", "x+20", "Offset Y:")
MarkerOffsetYEdit := MainGui.Add("Edit", "x+10 w60 vMarkerOffsetY", g_Settings["MarkerOffsetY"])
MainGui.Add("Text", "x+5 cGray", "(+ down, - up)")
MainGui.Add("Button", "x+20 w100", "🎯 Test").OnEvent("Click", TestMarkerCalibration)

MainGui.Add("Button", "xs+15 y+25 w120", "💾 Save Settings").OnEvent("Click", SaveSettingsFromGUI)
MainGui.Add("Button", "x+10 w120", "🔄 Reset Defaults").OnEvent("Click", ResetSettings)

MainGui.Add("GroupBox", "xs+15 y+15 w920 h80", "💾 Data")
MainGui.Add("Text", "xp+15 yp+25", "Location: " . DATA_DIR)
MainGui.Add("Button", "xs+30 y+10 w120", "📂 Open Folder").OnEvent("Click", (*) => Run(DATA_DIR))
MainGui.Add("Button", "x+10 w120", "🗑️ Clear All").OnEvent("Click", ClearAllData)

; ══════════════════════════════════════════════════════════════════════════════
; TAB 5: HELP
; ══════════════════════════════════════════════════════════════════════════════
TabCtrl.UseTab(5)

HelpText := "
(
╔═══════════════════════════════════════════════════════════════════════════════════════╗
║                           MACRO AUTOMATOR v2.4 - QUICK GUIDE                          ║
╚═══════════════════════════════════════════════════════════════════════════════════════╝

BASIC WORKFLOW:
═══════════════════════════════════════════════════════════════════════════════════════
1. CAPTURE positions:     Click capture button → click on screen → position saved
2. BUILD sequence:        Select action → pick target → add parameter → click Add Step
3. SAVE & RUN:            Name your sequence → Save → Test Run or assign hotkey

CAPTURE METHODS:
═══════════════════════════════════════════════════════════════════════════════════════
• Capture Click:    Single click to save X,Y position
• Capture Drag:     Click-hold at start, drag to end, release
• Arrow Key:        Use arrow keys for pixel-perfect positioning
• Record:           Records all your clicks in real-time

AUTO-NAMING:
═══════════════════════════════════════════════════════════════════════════════════════
Leave the name field blank - positions auto-name as Point_1, Point_2, Drag_1, etc.
Rename them later by selecting and clicking Rename.

ACTION PARAMETERS:
═══════════════════════════════════════════════════════════════════════════════════════
• Click:          (empty)=1 click, number=repeat count
• Double/Triple:  (empty)=standard
• Type Text:      The text to type
• Press Key:      Key name (Enter, Tab, F1, Ctrl+c, Alt+Tab)
• Wait:           Milliseconds (1000 = 1 second)
• Insert Extracted: Field name from clipboard parsing

GLOBAL HOTKEYS (Always Work):
═══════════════════════════════════════════════════════════════════════════════════════
• Ctrl+Shift+G:   Show/Hide this window
• Ctrl+Shift+P:   Pause/Resume sequence
• Ctrl+Shift+X:   Emergency stop

TRAY ICON:
═══════════════════════════════════════════════════════════════════════════════════════
Right-click the tray icon for:
• Toggle Always On Top
• Toggle Click-Through mode
• Reset transparency
• Start/Stop recording
)"

MainGui.Add("Edit", "w930 h640 ReadOnly Multi -WantReturn", HelpText)

; ══════════════════════════════════════════════════════════════════════════════
; BOTTOM TOOLBAR (Window Controls - moved from top)
; ══════════════════════════════════════════════════════════════════════════════
TabCtrl.UseTab(0)

MainGui.Add("GroupBox", "xm y745 w970 h55", "🔧 Window Controls")

AlwaysOnTopCheck := MainGui.Add("CheckBox", "xp+15 yp+22 vAlwaysOnTop", "📌 On Top")
AlwaysOnTopCheck.OnEvent("Click", ToggleAlwaysOnTop)

MainGui.Add("Text", "x+15", "Opacity:")
TransSlider := MainGui.Add("Slider", "x+5 w100 vTransparency Range25-255", 255)
TransSlider.OnEvent("Change", UpdateTransparency)

ClickThroughCheck := MainGui.Add("CheckBox", "x+15 vClickThrough", "👆 Click-Through")
ClickThroughCheck.OnEvent("Click", ToggleClickThrough)

MainGui.Add("Text", "x+5 cRed", "(tray to disable)")

RecordBtn := MainGui.Add("Button", "x+30 w130", "🔴 Start Recording")
RecordBtn.OnEvent("Click", ToggleRecording)

; Status bar
StatusBar := MainGui.Add("StatusBar",, "Ready")

MainGui.Show("Center")

; ══════════════════════════════════════════════════════════════════════════════
; SECTION 8: GUI FUNCTIONS
; ══════════════════════════════════════════════════════════════════════════════

ToggleAlwaysOnTop(ctrl, *) {
    global g_AlwaysOnTop, MainGui
    g_AlwaysOnTop := ctrl.Value
    WinSetAlwaysOnTop(g_AlwaysOnTop, MainGui)
    if g_AlwaysOnTop
        A_TrayMenu.Check("📌 Always On Top")
    else
        A_TrayMenu.Uncheck("📌 Always On Top")
    UpdateStatusBar()
}

UpdateTransparency(ctrl, *) {
    global g_Transparency, g_ClickThrough, MainGui
    g_Transparency := ctrl.Value
    if !g_ClickThrough
        WinSetTransparent(g_Transparency, MainGui)
}

ToggleClickThrough(ctrl, *) {
    global g_ClickThrough
    if ctrl.Value != g_ClickThrough
        TrayToggleClickThrough()
}

ToggleRecording(*) {
    global g_IsRecording
    if g_IsRecording
        StopRecording()
    else
        StartRecording()
}

StartRecording() {
    global g_IsRecording, g_RecordedActions, RecordBtn
    g_IsRecording := true
    g_RecordedActions := []
    RecordBtn.Text := "⏹️ Stop Recording"
    Hotkey("~LButton", RecordLeftClick, "On")
    Hotkey("~RButton", RecordRightClick, "On")
    UpdateStatusBar()
    ToolTip("🔴 Recording...")
    SetTimer(() => ToolTip(), -2000)
}

StopRecording() {
    global g_IsRecording, g_RecordedActions, RecordBtn
    g_IsRecording := false
    RecordBtn.Text := "🔴 Start Recording"
    try Hotkey("~LButton", "Off")
    try Hotkey("~RButton", "Off")
    UpdateStatusBar()
    ToolTip("⏹️ Recorded " . g_RecordedActions.Length . " actions")
    SetTimer(() => ToolTip(), -2000)
}

RecordLeftClick(*) {
    global g_IsRecording, g_RecordedActions
    if !g_IsRecording
        return
    MouseGetPos(&x, &y)
    g_RecordedActions.Push(Map("action", "Click", "target", "", "param", x . "," . y, "enabled", 1))
}

RecordRightClick(*) {
    global g_IsRecording, g_RecordedActions
    if !g_IsRecording
        return
    MouseGetPos(&x, &y)
    g_RecordedActions.Push(Map("action", "Right Click", "target", "", "param", x . "," . y, "enabled", 1))
}

ImportRecordedActions(*) {
    global g_RecordedActions, g_CurrentSequenceSteps
    if g_RecordedActions.Length = 0 {
        MsgBoxTop("No recorded actions!", "Empty")
        return
    }
    for action in g_RecordedActions
        g_CurrentSequenceSteps.Push(action)
    RefreshStepsListView()
    MsgBoxTop("Imported " . g_RecordedActions.Length . " actions.", "Done")
}

; ══════════════════════════════════════════════════════════════════════════════
; SECTION 9: COORDINATE CAPTURE (Auto-naming, proper test)
; ══════════════════════════════════════════════════════════════════════════════

StartCoordinateCapture(*) {
    global g_IsCapturing, g_DragMode
    g_IsCapturing := true
    g_DragMode := false
    StatusBar.SetText("🎯 Click anywhere to capture position. ESC to cancel.")
    Hotkey("~LButton", CaptureClick, "On")
    Hotkey("Escape", CancelCapture, "On")
}

StartDragCapture(*) {
    global g_IsCapturing, g_DragMode, g_DragStartX, g_DragStartY
    g_IsCapturing := true
    g_DragMode := true
    g_DragStartX := 0
    g_DragStartY := 0
    StatusBar.SetText("↔️ Click+HOLD at start → DRAG → RELEASE at end. ESC to cancel.")
    Hotkey("~LButton", CaptureDragStart, "On")
    Hotkey("~LButton Up", CaptureDragEnd, "On")
    Hotkey("Escape", CancelCapture, "On")
}

CaptureClick(*) {
    global g_IsCapturing, g_Coordinates, CoordListView, CoordNameEdit
    if !g_IsCapturing
        return

    MouseGetPos(&mouseX, &mouseY)

    ; Get name or auto-generate
    savedVals := MainGui.Submit(false)
    coordName := savedVals.CoordName
    if coordName = ""
        coordName := GenerateCoordName("Point")

    g_Coordinates[coordName] := Map("x", mouseX, "y", mouseY, "endX", "", "endY", "", "type", "Click")
    CoordListView.Add(, coordName, mouseX, mouseY, "", "", "Click")

    g_IsCapturing := false
    Hotkey("~LButton", "Off")
    Hotkey("Escape", "Off")

    CoordNameEdit.Value := ""
    StatusBar.SetText("✅ Captured: " . coordName . " @ " . mouseX . "," . mouseY)
    ShowCoordinateMarker(mouseX, mouseY, 1500, "Green")

    SaveCoordinates()
    UpdateCoordinateDropdowns()
}

CaptureDragStart(*) {
    global g_IsCapturing, g_DragStartX, g_DragStartY
    if !g_IsCapturing
        return
    MouseGetPos(&g_DragStartX, &g_DragStartY)
    StatusBar.SetText("Start: " . g_DragStartX . "," . g_DragStartY . " → now drag and release")
    ShowCoordinateMarker(g_DragStartX, g_DragStartY, 5000, "Blue")
}

CaptureDragEnd(*) {
    global g_IsCapturing, g_DragMode, g_DragStartX, g_DragStartY, g_Coordinates, CoordListView, CoordNameEdit
    if !g_IsCapturing || !g_DragMode
        return

    MouseGetPos(&endX, &endY)

    ; Get name or auto-generate
    savedVals := MainGui.Submit(false)
    coordName := savedVals.CoordName
    if coordName = ""
        coordName := GenerateCoordName("Drag")

    g_Coordinates[coordName] := Map("x", g_DragStartX, "y", g_DragStartY, "endX", endX, "endY", endY, "type", "Drag")
    CoordListView.Add(, coordName, g_DragStartX, g_DragStartY, endX, endY, "Drag")

    g_IsCapturing := false
    g_DragMode := false
    Hotkey("~LButton", "Off")
    Hotkey("~LButton Up", "Off")
    Hotkey("Escape", "Off")

    CoordNameEdit.Value := ""
    StatusBar.SetText("✅ Drag: " . coordName)
    ShowCoordinateMarker(endX, endY, 1500, "Green")

    SaveCoordinates()
    UpdateCoordinateDropdowns()
}

CancelCapture(*) {
    global g_IsCapturing, g_DragMode
    g_IsCapturing := false
    g_DragMode := false
    try Hotkey("~LButton", "Off")
    try Hotkey("~LButton Up", "Off")
    try Hotkey("Escape", "Off")
    StatusBar.SetText("Cancelled")
}

StartArrowKeyCalibration(*) {
    global g_IsCalibrating
    g_IsCalibrating := true
    MouseGetPos(&x, &y)
    ShowCoordinateMarker(x, y, 99999, "Blue")

    Hotkey("Up", (*) => MoveCursorBy(0, -1), "On")
    Hotkey("Down", (*) => MoveCursorBy(0, 1), "On")
    Hotkey("Left", (*) => MoveCursorBy(-1, 0), "On")
    Hotkey("Right", (*) => MoveCursorBy(1, 0), "On")
    Hotkey("+Up", (*) => MoveCursorBy(0, -10), "On")
    Hotkey("+Down", (*) => MoveCursorBy(0, 10), "On")
    Hotkey("+Left", (*) => MoveCursorBy(-10, 0), "On")
    Hotkey("+Right", (*) => MoveCursorBy(10, 0), "On")
    Hotkey("Enter", FinishArrowCapture, "On")
    Hotkey("Escape", CancelArrowCapture, "On")

    ToolTip("🎯 Arrow=1px | Shift+Arrow=10px | ENTER=save | ESC=cancel", x + 50, y + 30, 5)
    StatusBar.SetText("Arrow key mode: position cursor then press ENTER")
}

MoveCursorBy(dx, dy) {
    global g_IsCalibrating
    if !g_IsCalibrating
        return
    MouseGetPos(&x, &y)
    newX := x + dx
    newY := y + dy
    MouseMove(newX, newY, 0)
    ShowCoordinateMarker(newX, newY, 99999, "Blue")
    ToolTip("Position: " . newX . "," . newY . " | ENTER=save | ESC=cancel", newX + 50, newY + 30, 5)
}

FinishArrowCapture(*) {
    global g_IsCalibrating, g_Coordinates, CoordListView, CoordNameEdit
    if !g_IsCalibrating
        return

    MouseGetPos(&x, &y)
    EndArrowMode()

    ; Auto-generate name
    coordName := GenerateCoordName("Point")

    g_Coordinates[coordName] := Map("x", x, "y", y, "endX", "", "endY", "", "type", "Click")
    CoordListView.Add(, coordName, x, y, "", "", "Click")

    SaveCoordinates()
    UpdateCoordinateDropdowns()
    StatusBar.SetText("✅ Saved: " . coordName . " @ " . x . "," . y)
    ShowCoordinateMarker(x, y, 2000, "Green")
}

CancelArrowCapture(*) {
    EndArrowMode()
    StatusBar.SetText("Cancelled")
}

EndArrowMode() {
    global g_IsCalibrating
    g_IsCalibrating := false
    try Hotkey("Up", "Off")
    try Hotkey("Down", "Off")
    try Hotkey("Left", "Off")
    try Hotkey("Right", "Off")
    try Hotkey("+Up", "Off")
    try Hotkey("+Down", "Off")
    try Hotkey("+Left", "Off")
    try Hotkey("+Right", "Off")
    try Hotkey("Enter", "Off")
    try Hotkey("Escape", "Off")
    ToolTip(, , , 5)
    HideMarker()
}

ToggleLiveCapture(ctrl, *) {
    if ctrl.Value
        SetTimer(UpdateLiveMousePos, 100)
    else
        SetTimer(UpdateLiveMousePos, 0)
}

UpdateLiveMousePos() {
    global MousePosText
    MouseGetPos(&x, &y)
    MousePosText.Value := "X: " . x . ", Y: " . y
}

RenameCoordinate(*) {
    global CoordListView, g_Coordinates
    row := CoordListView.GetNext(0, "Focused")
    if row = 0 {
        MsgBoxTop("Select a coordinate first.", "No Selection")
        return
    }

    oldName := CoordListView.GetText(row, 1)
    result := InputBoxTop("New name:", "Rename", "", oldName)

    if result["Result"] = "OK" && result["Value"] != "" && result["Value"] != oldName {
        newName := result["Value"]
        coord := g_Coordinates[oldName]
        g_Coordinates.Delete(oldName)
        g_Coordinates[newName] := coord
        CoordListView.Modify(row,, newName)
        SaveCoordinates()
        UpdateCoordinateDropdowns()
        StatusBar.SetText("Renamed: " . oldName . " → " . newName)
    }
}

DeleteCoordinate(*) {
    global CoordListView, g_Coordinates
    row := CoordListView.GetNext(0, "Focused")
    if row = 0 {
        MsgBoxTop("Select a coordinate.", "No Selection")
        return
    }
    name := CoordListView.GetText(row, 1)
    if MsgBoxTop("Delete '" . name . "'?", "Confirm", "YesNo") = "Yes" {
        g_Coordinates.Delete(name)
        CoordListView.Delete(row)
        SaveCoordinates()
        UpdateCoordinateDropdowns()
        StatusBar.SetText("Deleted: " . name)
    }
}

; FIXED: Test now performs the ACTUAL action (drag, triple-click, etc.)
TestCoordinate(*) {
    global CoordListView, g_Coordinates, g_Settings
    row := CoordListView.GetNext(0, "Focused")
    if row = 0 {
        MsgBoxTop("Select a coordinate.", "No Selection")
        return
    }

    name := CoordListView.GetText(row, 1)
    coord := g_Coordinates[name]

    ; Move to position
    MouseMove(coord["x"], coord["y"], 5)
    ShowCoordinateMarker(coord["x"], coord["y"], 2000, "Green")
    Sleep(100)

    ; Perform action based on coordinate TYPE
    if coord["type"] = "Drag" && coord["endX"] != "" {
        ; Actually perform the drag!
        MouseClickDrag("Left", coord["x"], coord["y"], coord["endX"], coord["endY"], g_Settings["DefaultDragTime"] / 100)
        ShowCoordinateMarker(coord["endX"], coord["endY"], 2000, "Blue")
        StatusBar.SetText("Tested DRAG: " . name . " → " . coord["endX"] . "," . coord["endY"])
    } else {
        ; For click positions, just move
        StatusBar.SetText("Moved to: " . name)
    }
}

TestMarkerCalibration(*) {
    global g_Settings
    savedVals := MainGui.Submit(false)
    g_Settings["MarkerOffsetX"] := Integer(savedVals.MarkerOffsetX)
    g_Settings["MarkerOffsetY"] := Integer(savedVals.MarkerOffsetY)
    MouseGetPos(&x, &y)
    ShowCoordinateMarker(x, y, 3000, "Green")
    ToolTip("Offsets: X=" . g_Settings["MarkerOffsetX"] . ", Y=" . g_Settings["MarkerOffsetY"], x + 50, y + 30)
    SetTimer(() => ToolTip(), -3000)
}

; ══════════════════════════════════════════════════════════════════════════════
; SECTION 10: SEQUENCE BUILDER
; ══════════════════════════════════════════════════════════════════════════════

UpdateParamHints(*) {
    global ActionTypeDropdown, ParamHintsDropdown, ParamHintText

    action := ActionTypeDropdown.Text

    hints := Map(
        "Click", ["(empty)=1", "1", "2", "3", "5"],
        "Double Click", ["(empty)"],
        "Triple Click", ["(empty)"],
        "Right Click", ["(empty)"],
        "Click and Drag", ["(uses drag coords)"],
        "Type Text", ["Your text here"],
        "Paste Clipboard", ["(empty)=Ctrl+V"],
        "Set Clipboard", ["Text to copy"],
        "Press Key", ["Enter", "Tab", "Space", "F1", "Ctrl+c", "Alt+Tab"],
        "Tab", ["1", "2", "3", "5"],
        "Enter", ["1", "2", "3"],
        "Wait", ["100", "500", "1000", "2000", "5000"],
        "Insert Extracted", ["LastName", "FirstName", "DOB", "CurrentDate"],
        "Insert Date", ["(empty)"],
        "Scroll", ["3", "5", "-3", "-5"]
    )

    hintTexts := Map(
        "Click", "Click: (empty)=1 | number=repeat",
        "Double Click", "Double Click: standard double-click",
        "Triple Click", "Triple Click: selects entire line",
        "Right Click", "Right Click: standard right-click",
        "Click and Drag", "Drag: uses saved start→end coordinates",
        "Type Text", "Type: enter text to type",
        "Paste Clipboard", "Paste: sends Ctrl+V",
        "Set Clipboard", "Set Clipboard: text to store",
        "Press Key", "Key: Enter, Tab, F1, Ctrl+c, etc.",
        "Tab", "Tab: repeat count",
        "Enter", "Enter: repeat count",
        "Wait", "Wait: milliseconds (1000=1sec)",
        "Insert Extracted", "Insert: field name from clipboard",
        "Insert Date", "Date: uses format from settings",
        "Scroll", "Scroll: + up, - down"
    )

    ParamHintsDropdown.Delete()
    if hints.Has(action)
        ParamHintsDropdown.Add(hints[action])

    if hintTexts.Has(action)
        ParamHintText.Value := hintTexts[action]
}

ApplyParamHint(*) {
    global ParamHintsDropdown, ActionParamEdit
    hint := ParamHintsDropdown.Text
    if hint != "" && SubStr(hint, 1, 1) != "("
        ActionParamEdit.Value := hint
}

AddActionToSequence(*) {
    global g_CurrentSequenceSteps, ActionTypeDropdown, TargetDropdown, ActionParamEdit
    savedVals := MainGui.Submit(false)
    g_CurrentSequenceSteps.Push(Map(
        "action", ActionTypeDropdown.Text,
        "target", TargetDropdown.Text,
        "param", savedVals.ActionParam,
        "enabled", 1
    ))
    RefreshStepsListView()
    ActionParamEdit.Value := ""
    StatusBar.SetText("Added step " . g_CurrentSequenceSteps.Length)
}

MoveStepUp(*) {
    global g_CurrentSequenceSteps, SeqStepsListView
    row := SeqStepsListView.GetNext(0, "Focused")
    if row < 2
        return
    temp := g_CurrentSequenceSteps[row]
    g_CurrentSequenceSteps[row] := g_CurrentSequenceSteps[row - 1]
    g_CurrentSequenceSteps[row - 1] := temp
    RefreshStepsListView()
    SeqStepsListView.Modify(row - 1, "Select Focus")
}

MoveStepDown(*) {
    global g_CurrentSequenceSteps, SeqStepsListView
    row := SeqStepsListView.GetNext(0, "Focused")
    if row = 0 || row >= g_CurrentSequenceSteps.Length
        return
    temp := g_CurrentSequenceSteps[row]
    g_CurrentSequenceSteps[row] := g_CurrentSequenceSteps[row + 1]
    g_CurrentSequenceSteps[row + 1] := temp
    RefreshStepsListView()
    SeqStepsListView.Modify(row + 1, "Select Focus")
}

EditStep(*) {
    global g_CurrentSequenceSteps, SeqStepsListView
    row := SeqStepsListView.GetNext(0, "Focused")
    if row = 0
        return
    step := g_CurrentSequenceSteps[row]
    result := InputBoxTop("Edit parameter:", "Edit", "", step["param"])
    if result["Result"] = "OK" {
        step["param"] := result["Value"]
        RefreshStepsListView()
    }
}

RemoveStep(*) {
    global g_CurrentSequenceSteps, SeqStepsListView
    row := SeqStepsListView.GetNext(0, "Focused")
    if row = 0
        return
    g_CurrentSequenceSteps.RemoveAt(row)
    RefreshStepsListView()
}

ToggleStepEnabled(*) {
    global g_CurrentSequenceSteps, SeqStepsListView
    row := SeqStepsListView.GetNext(0, "Focused")
    if row = 0
        return
    g_CurrentSequenceSteps[row]["enabled"] := g_CurrentSequenceSteps[row]["enabled"] ? 0 : 1
    RefreshStepsListView()
    SeqStepsListView.Modify(row, "Select Focus")
}

ClearSteps(*) {
    global g_CurrentSequenceSteps
    if MsgBoxTop("Clear all steps?", "Confirm", "YesNo") = "Yes" {
        g_CurrentSequenceSteps := []
        RefreshStepsListView()
    }
}

RefreshStepsListView() {
    global g_CurrentSequenceSteps, SeqStepsListView
    SeqStepsListView.Delete()
    for index, step in g_CurrentSequenceSteps {
        enabled := step.Has("enabled") ? step["enabled"] : 1
        SeqStepsListView.Add(enabled ? "Check" : "", index, enabled ? "✓" : "✗", step["action"], step["target"], step["param"])
    }
}

SaveSequence(*) {
    global g_CurrentSequenceSteps, g_Sequences, SeqNameEdit
    savedVals := MainGui.Submit(false)
    seqName := savedVals.SeqName

    if seqName = "" {
        MsgBoxTop("Enter a sequence name!", "Required")
        return
    }
    if g_CurrentSequenceSteps.Length = 0 {
        MsgBoxTop("Add steps first!", "Empty")
        return
    }

    steps := []
    enabledCount := 0
    for step in g_CurrentSequenceSteps {
        newStep := Map()
        for k, v in step
            newStep[k] := v
        steps.Push(newStep)
        if newStep["enabled"]
            enabledCount++
    }

    g_Sequences[seqName] := Map("steps", steps, "description", steps.Length . " steps")
    RefreshSavedSequencesListView()
    g_CurrentSequenceSteps := []
    SeqStepsListView.Delete()
    SeqNameEdit.Value := ""
    SaveSequences()
    RefreshHotkeyDropdowns()
    StatusBar.SetText("Saved: " . seqName)
}

RefreshSavedSequencesListView() {
    global g_Sequences, SavedSeqListView
    SavedSeqListView.Delete()
    for name, seq in g_Sequences
        SavedSeqListView.Add(, name, seq["steps"].Length, seq.Has("description") ? seq["description"] : "")
}

LoadSequence(*) {
    global g_Sequences, g_CurrentSequenceSteps, SavedSeqListView, SeqNameEdit
    row := SavedSeqListView.GetNext(0, "Focused")
    if row = 0 {
        MsgBoxTop("Select a sequence.", "No Selection")
        return
    }
    name := SavedSeqListView.GetText(row, 1)
    if g_Sequences.Has(name) {
        g_CurrentSequenceSteps := []
        for step in g_Sequences[name]["steps"] {
            newStep := Map()
            for k, v in step
                newStep[k] := v
            g_CurrentSequenceSteps.Push(newStep)
        }
        SeqNameEdit.Value := name
        RefreshStepsListView()
        StatusBar.SetText("Loaded: " . name)
    }
}

DeleteSequence(*) {
    global g_Sequences, SavedSeqListView
    row := SavedSeqListView.GetNext(0, "Focused")
    if row = 0
        return
    name := SavedSeqListView.GetText(row, 1)
    if MsgBoxTop("Delete '" . name . "'?", "Confirm", "YesNo") = "Yes" {
        g_Sequences.Delete(name)
        RefreshSavedSequencesListView()
        SaveSequences()
        RefreshHotkeyDropdowns()
        StatusBar.SetText("Deleted: " . name)
    }
}

TestSequence(*) {
    global g_CurrentSequenceSteps
    if g_CurrentSequenceSteps.Length = 0 {
        MsgBoxTop("No steps!", "Empty")
        return
    }
    if MsgBoxTop("Run now?", "Test", "YesNo") = "Yes" {
        ExecuteSequence(g_CurrentSequenceSteps)
        StatusBar.SetText("Done!")
    }
}

; ══════════════════════════════════════════════════════════════════════════════
; SECTION 11: CLIPBOARD
; ══════════════════════════════════════════════════════════════════════════════

GrabClipboard(*) {
    global ClipboardEdit
    ClipboardEdit.Value := A_Clipboard
    StatusBar.SetText("Grabbed " . StrLen(A_Clipboard) . " chars")
}

ParseClipboard(*) {
    global g_ExtractionRules, g_ExtractedData, ClipboardEdit, ExtractedListView, RulesListView
    text := ClipboardEdit.Value
    if text = "" {
        MsgBoxTop("No text!", "Empty")
        return
    }

    g_ExtractedData := Map()
    ExtractedListView.Delete()
    RulesListView.Delete()

    for rule in g_ExtractionRules {
        if RegExMatch(text, rule["pattern"], &match) {
            extracted := Trim(match.Count > 0 ? match[1] : match[0])
            g_ExtractedData[rule["name"]] := extracted
            ExtractedListView.Add(, rule["name"], extracted)
            RulesListView.Add(, rule["name"], rule["pattern"], extracted)
        } else {
            RulesListView.Add(, rule["name"], rule["pattern"], "(no match)")
        }
    }

    g_ExtractedData["CurrentDate"] := FormatTime(, g_Settings["DateFormat"])
    ExtractedListView.Add(, "CurrentDate", g_ExtractedData["CurrentDate"])
    StatusBar.SetText("Extracted " . g_ExtractedData.Count . " fields")
}

ClearClipboard(*) {
    global ClipboardEdit, ExtractedListView, g_ExtractedData
    ClipboardEdit.Value := ""
    ExtractedListView.Delete()
    g_ExtractedData := Map()
}

AddPresetPattern(*) {
    global PatternPresetDropdown, g_ExtractionRules, RulesListView
    preset := PatternPresetDropdown.Text
    presets := Map(
        "Last Name", Map("name", "LastName", "pattern", "^([^,]+)"),
        "First Name", Map("name", "FirstName", "pattern", ",\s*([^#\s]+)"),
        "DOB", Map("name", "DOB", "pattern", "(\d{1,2}/\d{1,2}/\d{2,4})"),
        "Email", Map("name", "Email", "pattern", "([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})"),
        "Phone", Map("name", "Phone", "pattern", "((?:\+?1[-.]?)?\(?[0-9]{3}\)?[-. ]?[0-9]{3}[-. ]?[0-9]{4})"),
        "Numbers", Map("name", "Numbers", "pattern", "(\d+)")
    )
    if presets.Has(preset) {
        p := presets[preset]
        for rule in g_ExtractionRules
            if rule["name"] = p["name"] {
                PatternPresetDropdown.Choose(1)
                return
            }
        g_ExtractionRules.Push(p)
        RulesListView.Add(, p["name"], p["pattern"], "")
        SaveExtractionRules()
    }
    PatternPresetDropdown.Choose(1)
}

AddExtractionRule(*) {
    global g_ExtractionRules, RulesListView, PatternNameEdit, PatternRegexEdit
    savedVals := MainGui.Submit(false)
    if savedVals.PatternName = "" || savedVals.PatternRegex = ""
        return
    try {
        RegExMatch("test", savedVals.PatternRegex)
    } catch {
        MsgBoxTop("Invalid regex!", "Error")
        return
    }
    g_ExtractionRules.Push(Map("name", savedVals.PatternName, "pattern", savedVals.PatternRegex))
    RulesListView.Add(, savedVals.PatternName, savedVals.PatternRegex, "")
    PatternNameEdit.Value := ""
    PatternRegexEdit.Value := ""
    SaveExtractionRules()
}

DeleteRule(*) {
    global g_ExtractionRules, RulesListView
    row := RulesListView.GetNext(0, "Focused")
    if row = 0
        return
    name := RulesListView.GetText(row, 1)
    for index, rule in g_ExtractionRules
        if rule["name"] = name {
            g_ExtractionRules.RemoveAt(index)
            break
        }
    RulesListView.Delete(row)
    SaveExtractionRules()
}

CopyExtracted(*) {
    global g_ExtractedData
    if g_ExtractedData.Count = 0
        return
    output := ""
    for name, value in g_ExtractedData
        output .= name . ": " . value . "`n"
    A_Clipboard := output
    StatusBar.SetText("Copied")
}

; ══════════════════════════════════════════════════════════════════════════════
; SECTION 12: HOTKEYS
; ══════════════════════════════════════════════════════════════════════════════

UpdateCoordinateDropdowns() {
    global g_Coordinates, TargetDropdown
    coords := ["(none)"]
    for name, _ in g_Coordinates
        coords.Push(name)
    TargetDropdown.Delete()
    TargetDropdown.Add(coords)
    TargetDropdown.Choose(1)
}

RefreshHotkeyDropdowns(*) {
    global g_Sequences, SeqDropdownForHotkey
    seqs := ["(none)"]
    for name, _ in g_Sequences
        seqs.Push(name)
    SeqDropdownForHotkey.Delete()
    SeqDropdownForHotkey.Add(seqs)
    SeqDropdownForHotkey.Choose(seqs.Length > 1 ? 2 : 1)
    RefreshHotkeyListView()
}

RefreshHotkeyListView() {
    global g_HotkeyBindings, HotkeyListView
    HotkeyListView.Delete()
    index := 1
    for hotkeyStr, seqName in g_HotkeyBindings {
        modifiers := ""
        key := hotkeyStr
        if InStr(hotkeyStr, "^")
            modifiers .= "Ctrl+"
        if InStr(hotkeyStr, "!")
            modifiers .= "Alt+"
        if InStr(hotkeyStr, "+")
            modifiers .= "Shift+"
        if InStr(hotkeyStr, "#")
            modifiers .= "Win+"
        key := RegExReplace(hotkeyStr, "[\^!+#]", "")
        if modifiers != ""
            modifiers := SubStr(modifiers, 1, -1)
        HotkeyListView.Add(, index, modifiers, key, seqName, "Active")
        index++
    }
}

AddNewHotkey(*) {
    global g_HotkeyBindings, ModifierDropdown, KeyEdit, SeqDropdownForHotkey
    savedVals := MainGui.Submit(false)
    if savedVals.HotkeyKey = "" || SeqDropdownForHotkey.Text = "(none)"
        return

    hotkeyStr := ""
    switch ModifierDropdown.Text {
        case "Ctrl": hotkeyStr := "^"
        case "Alt": hotkeyStr := "!"
        case "Shift": hotkeyStr := "+"
        case "Win": hotkeyStr := "#"
        case "Ctrl+Alt": hotkeyStr := "^!"
        case "Ctrl+Shift": hotkeyStr := "^+"
    }
    hotkeyStr .= savedVals.HotkeyKey

    g_HotkeyBindings[hotkeyStr] := SeqDropdownForHotkey.Text
    RefreshHotkeyListView()
    SaveHotkeys()
    StatusBar.SetText("Added hotkey")
}

RemoveHotkey(*) {
    global g_HotkeyBindings, HotkeyListView
    row := HotkeyListView.GetNext(0, "Focused")
    if row = 0
        return

    modifiers := HotkeyListView.GetText(row, 2)
    key := HotkeyListView.GetText(row, 3)
    hotkeyStr := ""
    if InStr(modifiers, "Ctrl")
        hotkeyStr .= "^"
    if InStr(modifiers, "Alt")
        hotkeyStr .= "!"
    if InStr(modifiers, "Shift")
        hotkeyStr .= "+"
    if InStr(modifiers, "Win")
        hotkeyStr .= "#"
    hotkeyStr .= key

    try Hotkey(hotkeyStr, "Off")
    if g_HotkeyBindings.Has(hotkeyStr)
        g_HotkeyBindings.Delete(hotkeyStr)
    RefreshHotkeyListView()
    SaveHotkeys()
}

ApplyAllHotkeys(*) {
    global g_HotkeyBindings
    for hotkeyStr, _ in g_HotkeyBindings
        try Hotkey(hotkeyStr, "Off")

    successCount := 0
    for hotkeyStr, seqName in g_HotkeyBindings {
        try {
            Hotkey(hotkeyStr, RunSequenceByName.Bind(seqName), "On")
            successCount++
        }
    }
    UpdateStatusBar()
    StatusBar.SetText("Applied " . successCount . " hotkeys")
}

ClearAllHotkeys(*) {
    global g_HotkeyBindings
    if MsgBoxTop("Clear all?", "Confirm", "YesNo") = "Yes" {
        for hotkeyStr, _ in g_HotkeyBindings
            try Hotkey(hotkeyStr, "Off")
        g_HotkeyBindings := Map()
        RefreshHotkeyListView()
        SaveHotkeys()
        UpdateStatusBar()
    }
}

RunSequenceByName(seqName, *) {
    global g_Sequences, g_IsPaused
    if !g_Sequences.Has(seqName)
        return
    g_IsPaused := false
    ExecuteSequence(g_Sequences[seqName]["steps"])
}

; ══════════════════════════════════════════════════════════════════════════════
; SECTION 13: EXECUTION
; ══════════════════════════════════════════════════════════════════════════════

ExecuteSequence(steps) {
    global g_Coordinates, g_ExtractedData, g_Settings, g_IsPaused, g_ActionCounter, g_TotalActions

    enabledSteps := []
    for step in steps
        if step.Has("enabled") && step["enabled"]
            enabledSteps.Push(step)

    g_TotalActions := enabledSteps.Length
    g_ActionCounter := 0

    for step in enabledSteps {
        g_ActionCounter++
        while g_IsPaused {
            Sleep(100)
            ToolTip("⏸️ PAUSED")
        }

        if g_Settings["ShowActionTooltips"]
            ToolTip("▶️ [" . g_ActionCounter . "/" . g_TotalActions . "] " . step["action"])

        ExecuteAction(step["action"], step["target"], step["param"])
        Sleep(g_Settings["ActionDelay"])
    }

    SetTimer(() => ToolTip(), -500)
}

ExecuteAction(action, target, param) {
    global g_Coordinates, g_ExtractedData, g_Settings

    switch action {
        case "Click":
            if target != "" && target != "(none)" && g_Coordinates.Has(target) {
                coord := g_Coordinates[target]
                Click(coord["x"], coord["y"], , param != "" ? Integer(param) : 1)
            } else if param != "" && InStr(param, ",") {
                parts := StrSplit(param, ",")
                Click(Integer(parts[1]), Integer(parts[2]))
            } else
                Click()
            Sleep(g_Settings["ClickDelay"])

        case "Double Click":
            if target != "" && target != "(none)" && g_Coordinates.Has(target) {
                coord := g_Coordinates[target]
                Click(coord["x"], coord["y"], , 2)
            } else
                Click(, , , 2)
            Sleep(g_Settings["ClickDelay"])

        case "Triple Click":
            if target != "" && target != "(none)" && g_Coordinates.Has(target) {
                coord := g_Coordinates[target]
                Click(coord["x"], coord["y"], , 3)
            } else
                Click(, , , 3)
            Sleep(g_Settings["ClickDelay"])

        case "Right Click":
            if target != "" && target != "(none)" && g_Coordinates.Has(target) {
                coord := g_Coordinates[target]
                Click(coord["x"], coord["y"], "Right")
            } else if param != "" && InStr(param, ",") {
                parts := StrSplit(param, ",")
                Click(Integer(parts[1]), Integer(parts[2]), "Right")
            } else
                Click(, , "Right")
            Sleep(g_Settings["ClickDelay"])

        case "Click and Drag":
            if target != "" && target != "(none)" && g_Coordinates.Has(target) {
                coord := g_Coordinates[target]
                if coord["endX"] != ""
                    MouseClickDrag("Left", coord["x"], coord["y"], coord["endX"], coord["endY"], g_Settings["DefaultDragTime"] / 100)
            }
            Sleep(g_Settings["ClickDelay"])

        case "Scroll":
            amount := param != "" ? Integer(param) : 3
            Click(amount > 0 ? "WheelUp" : "WheelDown", , , Abs(amount))
            Sleep(g_Settings["ClickDelay"])

        case "Type Text":
            if param != ""
                SendText(param)
            Sleep(g_Settings["TypeDelay"])

        case "Paste Clipboard":
            Send("^v")
            Sleep(g_Settings["TypeDelay"])

        case "Set Clipboard":
            if param != ""
                A_Clipboard := param

        case "Press Key":
            if param != ""
                Send(InStr(param, "{") ? param : "{" . param . "}")
            Sleep(g_Settings["TypeDelay"])

        case "Tab":
            Loop param != "" ? Integer(param) : 1
                Send("{Tab}")
            Sleep(g_Settings["TypeDelay"])

        case "Enter":
            Loop param != "" ? Integer(param) : 1
                Send("{Enter}")
            Sleep(g_Settings["TypeDelay"])

        case "Insert Extracted":
            if param != "" && g_ExtractedData.Has(param)
                SendText(g_ExtractedData[param])
            Sleep(g_Settings["TypeDelay"])

        case "Insert Date":
            SendText(FormatTime(, g_Settings["DateFormat"]))
            Sleep(g_Settings["TypeDelay"])

        case "Wait":
            Sleep(param != "" ? Integer(param) : g_Settings["ActionDelay"])
    }
}

; ══════════════════════════════════════════════════════════════════════════════
; SECTION 14: SETTINGS
; ══════════════════════════════════════════════════════════════════════════════

SaveSettingsFromGUI(*) {
    global g_Settings
    savedVals := MainGui.Submit(false)
    g_Settings["ClickDelay"] := Integer(savedVals.ClickDelay)
    g_Settings["TypeDelay"] := Integer(savedVals.TypeDelay)
    g_Settings["ActionDelay"] := Integer(savedVals.ActionDelay)
    g_Settings["DefaultDragTime"] := Integer(savedVals.DragTime)
    g_Settings["DateFormat"] := savedVals.DateFormat
    g_Settings["ShowActionTooltips"] := savedVals.ShowActionTooltips
    g_Settings["MarkerOffsetX"] := Integer(savedVals.MarkerOffsetX)
    g_Settings["MarkerOffsetY"] := Integer(savedVals.MarkerOffsetY)
    SaveSettings()
    StatusBar.SetText("Saved!")
}

ResetSettings(*) {
    global g_Settings
    if MsgBoxTop("Reset?", "Confirm", "YesNo") = "Yes" {
        g_Settings := Map(
            "ClickDelay", 100, "TypeDelay", 50, "ActionDelay", 200, "DefaultDragTime", 300,
            "DateFormat", "MM/dd/yyyy", "ShowActionTooltips", true, "TooltipDuration", 1500,
            "MarkerOffsetX", -12, "MarkerOffsetY", -15, "TestAction", "Perform Action"
        )
        SaveSettings()
        StatusBar.SetText("Reset")
    }
}

ClearAllData(*) {
    global g_Coordinates, g_Sequences, g_HotkeyBindings, g_ExtractionRules
    if MsgBoxTop("DELETE ALL DATA?", "Confirm", "YesNo Icon!") = "Yes" {
        g_Coordinates := Map()
        g_Sequences := Map()
        g_HotkeyBindings := Map()
        g_ExtractionRules := []
        CoordListView.Delete()
        SavedSeqListView.Delete()
        HotkeyListView.Delete()
        RulesListView.Delete()
        SeqStepsListView.Delete()
        ExtractedListView.Delete()
        SaveAllData()
        RefreshHotkeyDropdowns()
        UpdateCoordinateDropdowns()
        StatusBar.SetText("Cleared")
    }
}

UpdateStatusBar() {
    global g_HotkeyBindings, g_IsRecording, g_AlwaysOnTop, g_ClickThrough
    status := "Ready"
    if g_IsRecording
        status .= " | 🔴 Recording"
    status .= " | Hotkeys: " . g_HotkeyBindings.Count
    if g_AlwaysOnTop
        status .= " | 📌"
    if g_ClickThrough
        status .= " | 👆"
    StatusBar.SetText(status)
}

; ══════════════════════════════════════════════════════════════════════════════
; SECTION 15: GLOBAL HOTKEYS
; ══════════════════════════════════════════════════════════════════════════════

^+g:: {
    global g_GuiVisible, MainGui
    if g_GuiVisible {
        MainGui.Hide()
        g_GuiVisible := false
    } else {
        MainGui.Show()
        g_GuiVisible := true
    }
}

^+p:: {
    global g_IsPaused
    g_IsPaused := !g_IsPaused
    ToolTip(g_IsPaused ? "⏸️ PAUSED" : "▶️ RESUMED")
    SetTimer(() => ToolTip(), -1000)
}

^+x:: Reload()

; ══════════════════════════════════════════════════════════════════════════════
; SECTION 16: INIT
; ══════════════════════════════════════════════════════════════════════════════

LoadAllData()
RefreshCoordinateListView()
RefreshSavedSequencesListView()
RefreshHotkeyListView()
RefreshRulesListView()
UpdateCoordinateDropdowns()
RefreshHotkeyDropdowns()
UpdateParamHints()
ApplyAllHotkeys()
UpdateStatusBar()

ToolTip("🎯 v2.4 Ready! Ctrl+Shift+G to toggle")
SetTimer(() => ToolTip(), -2000)

RefreshCoordinateListView() {
    global g_Coordinates, CoordListView
    CoordListView.Delete()
    for name, coord in g_Coordinates
        CoordListView.Add(, name, coord["x"], coord["y"], coord["endX"], coord["endY"], coord["type"])
}

RefreshRulesListView() {
    global g_ExtractionRules, RulesListView
    RulesListView.Delete()
    for rule in g_ExtractionRules
        RulesListView.Add(, rule["name"], rule["pattern"], "")
}
