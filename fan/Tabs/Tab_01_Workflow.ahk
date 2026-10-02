; ===============================================================================
; Tabs\Tab_01_Workflow.ahk
; TAB 1 Workflow: step editor, library, .maw manager, demo lab, triggers, run/simulate
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================



; ═══════════════════════════════════════════════════════════════════════════════
; STEP PREVIEW ON SELECTION
; ═══════════════════════════════════════════════════════════════════════════════
; STEP PREVIEW ON SELECTION
; =============================================================================

ShowStepPreview(stepData) {
    global g_Coordinates, g_Patterns, g_Settings

    action := stepData["action"]
    target := stepData["target"]
    param := stepData["param"]

    tip := "=== STEP PREVIEW ===`n"
    tip .= "Action: " . action . "`n"

    ; Show coordinates
    if param != "" && InStr(param, ",") {
        if InStr(param, "->") {
            ; Drag format
            parts := StrSplit(param, "->")
            tip .= "From: " . parts[1] . "`n"
            tip .= "To: " . parts[2] . "`n"
        } else {
            tip .= "Position: " . param . "`n"
        }
    }

    ; Show target info
    if target != "" && target != "(none)" {
        tip .= "Target: " . target . "`n"

        ; If it's a pattern, show preview
        if g_Patterns.Has(target) {
            tip .= "---Pattern---`n"
            tip .= PatternToVisualPreview(g_Patterns[target]["text"], 30, 8)
        }
        ; If it's a coordinate
        else if g_Coordinates.Has(target) {
            c := g_Coordinates[target]
            tip .= "Coord: " . c["x"] . "," . c["y"]
            if c["endX"] != ""
                tip .= " -> " . c["endX"] . "," . c["endY"]
            tip .= "`n"
        }
    }

    ; Show window qualifier if set
    if stepData.Has("qualWindow") && stepData["qualWindow"] != ""
        tip .= "Window: " . stepData["qualWindow"] . "`n"

    MouseGetPos(&mx, &my)
    ToolTip(tip, mx + 20, my + 20)
    SetTimer(() => ToolTip(), -g_Settings["PreviewTooltipDuration"])
}

Tab_Workflow_Build() {
    global ActionCategoryDD, ActionDD, ActionHelpText, ActionHelpTitle, AdvancedStepCheck, ChoicesDD, ChoicesLabel, CoordLV, CoordNameEdit, FailsafeCloseCheck, g_HiddenCoordLV, g_HiddenCoordNameEdit, OCRRegionBtn, ParamCombo, ParamEdit, ParamFieldHint, ParamFieldLabel, PickWindowBtn, QualPatternDD, QualPatternLabel, QualWindowEdit, QualWindowLabel, QuickAddBtn, RefreshChoicesBtn, SavedLibraryGroup, SavedWorkflowsLabel, SeqDeleteBtn, SeqDemoLabBtn, SeqErrorLogBtn, SeqExportBtn, SeqGuideBtn, SeqHotkeyEdit, SeqHotstringEdit, SeqImportBtn, SeqLoadBtn, SeqLV, SeqManageBtn, SeqMawWriterBtn, SeqNameEdit, SeqRunBtn, SeqSimBtn, SpeedDD, StepsLV, TargetDD, TargetFieldHint, TargetFieldLabel, UseChoiceBtn, WorkflowSaveStatus
    TabCtrl.UseTab(1)

    ; Coordinate capture remains available without occupying the workflow canvas.
    CoordNameEdit := MainGui.Add("Edit", "x-1000 y-1000 w1 h1 Hidden vCoordName")
    CoordLV := MainGui.Add("ListView", "x-1000 y-1000 w1 h1 Hidden vCoordLV", ["Name", "X", "Y", "EndX", "EndY", "Type"])
    g_HiddenCoordNameEdit := CoordNameEdit
    g_HiddenCoordLV := CoordLV

    ; STEP 1 - workflow identity and playback settings
    MainGui.Add("GroupBox", "x15 y50 w860 h78", "1. Define Workflow")
    MainGui.Add("Text", "x30 y73", "Name:")
    SeqNameEdit := MainGui.Add("Edit", "x75 y70 w180 vSeqName")
    SeqNameEdit.OnEvent("Change", ScheduleWorkflowAutosave)
    MainGui.Add("Text", "x270 y73", "Speed:")
    SpeedDD := MainGui.Add("DropDownList", "x315 y70 w70 vPlaybackSpeed", ["0.25x", "0.5x", "0.75x", "1x", "1.5x", "2x", "3x"])
    SpeedDD.Choose(4)
    SpeedDD.OnEvent("Change", ScheduleWorkflowAutosave)
    MainGui.Add("Text", "x400 y73", "Hotkey:")
    SeqHotkeyEdit := MainGui.Add("Edit", "x450 y70 w75 vSeqHotkey")
    SeqHotkeyEdit.OnEvent("Change", ScheduleWorkflowAutosave)
    MainGui.Add("Text", "x540 y73", "Hotstring:")
    SeqHotstringEdit := MainGui.Add("Edit", "x605 y70 w75 vSeqHotstring")
    SeqHotstringEdit.OnEvent("Change", ScheduleWorkflowAutosave)
    SeqGuideBtn := MainGui.Add("Button", "x690 y68 w80 h24", "Action Guide")
    SeqGuideBtn.OnEvent("Click", ShowInstructionsFile)
    SeqErrorLogBtn := MainGui.Add("Button", "x780 y68 w80 h24", "Error Log")
    SeqErrorLogBtn.OnEvent("Click", OpenErrorLog)
    MainGui.Add("Text", "x30 y103 w820 cGray", "Give the workflow a name first. Named workflows autosave after each edit. Hotkey example: ^!s   Hotstring example: ::seq")

    ; STEP 2 - one contextual action at a time
    MainGui.Add("GroupBox", "x15 y135 w860 h160", "2. Pick an Action, then Add Step (guided form - no typing needed)")
    MainGui.Add("Text", "x30 y158", "Action:")
    ActionDD := MainGui.Add("DropDownList", "x85 y155 w180 vActionType", GetWorkflowActionNames())
    ActionDD.Choose(1)
    ActionDD.OnEvent("Change", OnActionChange)
    MainGui.Add("Button", "x275 y154 w85 h24 cGreen", "Templates").OnEvent("Click", ShowTemplateLibrary)
    MainGui.Add("Button", "x370 y154 w95 h24", "Pos. Tools").OnEvent("Click", ShowCoordinateManager)
    MainGui.Add("Text", "x472 y158 w55", "Category:")
    ActionCategoryDD := MainGui.Add("DropDownList", "x530 y155 w115 vActionCategory", GetActionCategoryNames())
    ActionCategoryDD.Choose(1)
    ActionCategoryDD.OnEvent("Change", OnCategoryChange)
    ActionCategoryDD.ToolTip := "Narrow the action list to one kind of task (grandma-friendly)."

    TargetFieldLabel := MainGui.Add("Text", "x30 y188 w90", "Position:")
    TargetFieldHint := MainGui.Add("Text", "x120 y188 w165 cGray", "(required)")
    TargetDD := MainGui.Add("ComboBox", "x30 y205 w255 vTargetCoord")
    TargetDD.OnEvent("Change", OnTargetChange)
    ParamFieldLabel := MainGui.Add("Text", "x300 y188 w105", "Click count:")
    ParamFieldHint := MainGui.Add("Text", "x405 y188 w160 cGray", "(optional)")
    ParamCombo := MainGui.Add("ComboBox", "x300 y205 w265 vActionParam")
    ParamCombo.OnEvent("Focus", UpdateLiveParamHints)
    ParamCombo.OnEvent("Change", OnParamChange)
    ParamEdit := ParamCombo
    MainGui.Add("Button", "x575 y204 w65 h24 Default cGreen", "Add Step ▸").OnEvent("Click", AddStep)
    OCRRegionBtn := MainGui.Add("Button", "x575 y232 w65 h22", "OCR Area")
    OCRRegionBtn.OnEvent("Click", SelectOCRRegionForWorkflow)
    ; Sits in the same clear strip as OCR Area (they are shown for different actions,
    ; never at once) and to the left of the Action Help panel at x650.
    PickWindowBtn := MainGui.Add("Button", "x568 y232 w80 h22", "Pick Window")
    PickWindowBtn.OnEvent("Click", PickWindow)
    PickWindowBtn.Visible := false
    ; Bypasses the guided form: adds the step straight from the Target/Param fields
    ; below. Shown for the actions that have no OCR-Area / Pick-Window button here.
    QuickAddBtn := MainGui.Add("Button", "x575 y232 w65 h22", "⚡ Quick Add")
    QuickAddBtn.OnEvent("Click", QuickAddStep)
    QuickAddBtn.Visible := false
    QuickAddBtn.ToolTip := "Skip the guided form and add the step from the Target/Param fields (power users)."

    ChoicesLabel := MainGui.Add("Text", "x30 y243", "Suggestions:")
    ChoicesDD := MainGui.Add("DropDownList", "x105 y240 w350 vChoices")
    UseChoiceBtn := MainGui.Add("Button", "x465 y239 w45 h22", "Use")
    UseChoiceBtn.OnEvent("Click", UseChoice)
    RefreshChoicesBtn := MainGui.Add("Button", "x515 y239 w50 h22", "Refresh")
    RefreshChoicesBtn.OnEvent("Click", RefreshChoices)
    AdvancedStepCheck := MainGui.Add("CheckBox", "x575 y267 vAdvancedStep", "Advanced")
    AdvancedStepCheck.OnEvent("Click", ToggleAdvancedStepFields)

    QualPatternLabel := MainGui.Add("Text", "x30 y272", "Pattern:")
    QualPatternDD := MainGui.Add("DropDownList", "x85 y269 w125 vQualPattern", ["(none)"])
    QualWindowLabel := MainGui.Add("Text", "x220 y272", "Window:")
    QualWindowEdit := MainGui.Add("Edit", "x270 y269 w145 vQualWindow")
    FailsafeCloseCheck := MainGui.Add("CheckBox", "x425 y272 vFailsafeClose", "Block window close")

    MainGui.Add("GroupBox", "x650 y147 w215 h138", "Action Help")
    global ActionHelpTitle := MainGui.Add("Text", "x660 y164 w195 cBlue", "Select action")
    global ActionHelpText := MainGui.Add("Edit", "x660 y184 w195 h92 ReadOnly Multi VScroll", "Select an action to see the exact fields and an example.")

    ; STEP 3 - review and arrange the execution order
    MainGui.Add("GroupBox", "x15 y305 w860 h215", "3. Review and Arrange Steps (top to bottom)")
    StepsLV := MainGui.Add("ListView", "x25 y327 w720 h178 Grid Checked NoSortHdr vStepsLV", ["#", "Action", "Target", "Parameter", "Failsafe"])
    StepsLV.ModifyCol(1, 25)
    StepsLV.ModifyCol(2, 120)
    StepsLV.ModifyCol(3, 150)
    StepsLV.ModifyCol(4, 280)
    StepsLV.ModifyCol(5, 125)
    StepsLV.OnEvent("ItemSelect", OnStepSelect)
    StepsLV.OnEvent("ContextMenu", OnStepsContextMenu)
    StepsLV.OnEvent("ItemCheck", OnStepCheck)
    MainGui.Add("Button", "x755 y327 w50 h24", "Up").OnEvent("Click", StepUp)
    MainGui.Add("Button", "x810 y327 w50 h24", "Down").OnEvent("Click", StepDown)
    MainGui.Add("Button", "x755 y357 w50 h24", "Edit").OnEvent("Click", EditStep)
    MainGui.Add("Button", "x810 y357 w50 h24", "Delete").OnEvent("Click", DelStep)
    MainGui.Add("Button", "x755 y387 w50 h24", "Enable").OnEvent("Click", ToggleStep)
    MainGui.Add("Button", "x810 y387 w50 h24", "Clear").OnEvent("Click", ClearSteps)
    MainGui.Add("Button", "x755 y427 w105 h24 cGreen", "Test Selected").OnEvent("Click", TestSingleStep)
    MainGui.Add("Button", "x755 y457 w105 h24 cBlue", "Sim Selected").OnEvent("Click", SimulateSingleStep)
    MainGui.Add("Button", "x755 y487 w105 h24 cBlue", "Simulate All").OnEvent("Click", SimulateSeq)

    ; STEP 4 - save and execute
    MainGui.Add("GroupBox", "x15 y530 w860 h65", "4. Save and Run")
    MainGui.Add("Button", "x30 y550 w90 h28", "Save Now").OnEvent("Click", SaveSeq)
    MainGui.Add("Button", "x130 y550 w90 h28 cGreen", "Run Workflow").OnEvent("Click", TestSeq)
    MainGui.Add("Button", "x230 y550 w90 h28 cBlue", "Simulate").OnEvent("Click", SimulateSeq)
    MainGui.Add("CheckBox", "x335 y556 vStepThroughCheck", "Step-through (Tab advances)").OnEvent("Click", ToggleStepThrough)
    SeqManageBtn := MainGui.Add("Button", "x585 y550 w120 h28", "Manage Library")
    SeqManageBtn.OnEvent("Click", ShowWorkflowManager)
    WorkflowSaveStatus := MainGui.Add("Text", "x30 y580 w820 cGray", "Enter a workflow name; changes then autosave after each edit.")

    ; STEP 5 - persistent library and portable .maw files
    SavedLibraryGroup := MainGui.Add("GroupBox", "x15 y605 w860 h150", "5. Saved Workflow Library and Portable .maw Files")
    SavedWorkflowsLabel := MainGui.Add("Text", "x25 y623 w640", "Double-click a workflow to load it. Import, export, or build a .maw file using the buttons at right.")
    SeqLV := MainGui.Add("ListView", "x25 y640 w650 h103 r5 Grid NoSortHdr vSeqLV", ["Name", "Steps", "Speed", "Hotkey", "Hotstring"])
    SeqLV.Opt("-LV0x2000 +0x00200000 +LV0x20")
    SeqLV.ModifyCol(1, 330)
    SeqLV.ModifyCol(2, 70)
    SeqLV.ModifyCol(3, 65)
    SeqLV.ModifyCol(4, 85)
    SeqLV.ModifyCol(5, 95)
    SeqLV.OnEvent("ContextMenu", OnSeqContextMenu)
    SeqLV.OnEvent("DoubleClick", (*) => LoadSeq())
    SeqLoadBtn := MainGui.Add("Button", "x685 y640 w85 h24", "Load / Edit")
    SeqLoadBtn.OnEvent("Click", LoadSeq)
    SeqDeleteBtn := MainGui.Add("Button", "x775 y640 w85 h24", "Delete")
    SeqDeleteBtn.OnEvent("Click", DelSeq)
    SeqRunBtn := MainGui.Add("Button", "x685 y668 w85 h24 cGreen", "Run")
    SeqRunBtn.OnEvent("Click", RunSeq)
    SeqSimBtn := MainGui.Add("Button", "x775 y668 w85 h24 cBlue", "Simulate")
    SeqSimBtn.OnEvent("Click", SimulateSavedSeq)
    SeqImportBtn := MainGui.Add("Button", "x685 y696 w85 h24", "Import .maw")
    SeqImportBtn.OnEvent("Click", ImportWorkflow)
    SeqExportBtn := MainGui.Add("Button", "x775 y696 w85 h24", "Export .maw")
    SeqExportBtn.OnEvent("Click", ExportWorkflowFromMain)
    SeqMawWriterBtn := MainGui.Add("Button", "x685 y724 w85 h24", "Write .maw")
    SeqMawWriterBtn.OnEvent("Click", ShowMawWriter)
    SeqDemoLabBtn := MainGui.Add("Button", "x775 y724 w85 h24 cBlue", "Demo Lab")
    SeqDemoLabBtn.OnEvent("Click", (*) => ShowWorkflowDemoLab(true))


}



; ═══════════════════════════════════════════════════════════════════════════════
; STEP SELECTION HANDLER
; ═══════════════════════════════════════════════════════════════════════════════
; STEP SELECTION HANDLER
; =============================================================================

OnStepSelect(LV, RowNumber, *) {
    global g_CurrentSequenceSteps, g_Settings

    if !IsNumber(RowNumber) || RowNumber < 1
        return

    if RowNumber > g_CurrentSequenceSteps.Length
        return

    step := g_CurrentSequenceSteps[RowNumber]
    ShowStepPreview(step)
}

OnStepCheck(LV, RowNumber, IsChecked) {
    global g_CurrentSequenceSteps

    if !IsNumber(RowNumber) || RowNumber < 1 || RowNumber > g_CurrentSequenceSteps.Length
        return

    ; Sync the enabled state with the checkbox
    g_CurrentSequenceSteps[RowNumber]["enabled"] := IsChecked
    ScheduleWorkflowAutosave()
}


; ═══════════════════════════════════════════════════════════════════════════════
; STEPS CONTEXT MENU (RIGHT-CLICK)
; ═══════════════════════════════════════════════════════════════════════════════
; STEPS CONTEXT MENU (Right-click)
; =============================================================================

OnStepsContextMenu(LV, RowNumber, IsRightClick, X, Y) {
    global g_CurrentSequenceSteps
    if !IsNumber(RowNumber) || RowNumber < 1 || RowNumber > g_CurrentSequenceSteps.Length
        return

    ; Create context menu
    stepMenu := Menu()
    stepMenu.Add("▶ Test This Step", (*) => TestSingleStepByRow(RowNumber))
    stepMenu.Add("🔍 Simulate This Step", (*) => SimulateSingleStepByRow(RowNumber))
    stepMenu.Add()
    stepMenu.Add("✓ Toggle This Step", (*) => ToggleStepByRow(RowNumber))
    stepMenu.Add("✓ Toggle All OFF Except This", (*) => ToggleAllOffExcept(RowNumber))
    stepMenu.Add("✓ Enable All Steps", (*) => EnableAllSteps())
    stepMenu.Add()
    stepMenu.Add("🛡 Edit Failsafe...", (*) => EditStepFailsafeByRow(RowNumber))
    stepMenu.Add("✏ Edit Step...", (*) => EditStepByRow(RowNumber))
    stepMenu.Add("🗑 Delete Step", (*) => DeleteStepByRow(RowNumber))
    stepMenu.Add()
    stepMenu.Add("⬆ Move Up", (*) => MoveStepUp(RowNumber))
    stepMenu.Add("⬇ Move Down", (*) => MoveStepDown(RowNumber))
    stepMenu.Add()
    stepMenu.Add("📋 Duplicate Step", (*) => DuplicateStep(RowNumber))

    stepMenu.Show(X, Y)
}

; Context menu for saved sequences
OnSeqContextMenu(LV, RowNumber, IsRightClick, X, Y) {
    global g_Sequences
    if !TryGetListViewText(LV, RowNumber, 1, &name)
        return
    if !g_Sequences.Has(name)
        return

    seqMenu := Menu()
    seqMenu.Add("▶ Run: " . name, (*) => RunSeqByName(name))
    seqMenu.Add("🔍 Simulate", (*) => SimulateSavedSeqByName(name))
    seqMenu.Add()
    seqMenu.Add("📂 Load into Editor", (*) => LoadSeqByName(name))
    seqMenu.Add("📋 Duplicate", (*) => DuplicateSequence(name))
    seqMenu.Add("✏ Rename...", (*) => RenameSequence(name))
    seqMenu.Add()
    seqMenu.Add("🗑 Delete", (*) => DeleteSeqByName(name))

    seqMenu.Show(X, Y)
}


; Context menu action handlers
TestSingleStepByRow(row) {
    global g_CurrentSequenceSteps, g_AbortSequence

    if row > g_CurrentSequenceSteps.Length
        return

    step := g_CurrentSequenceSteps[row]
    g_AbortSequence := false
    speed := GetSpeedMultiplier()

    ShowStatus("Testing step " . row . ": " . step["action"], "wait")
    success := ExecuteActionVerified(step["action"], step["target"], step["param"], step, speed)
    ShowStatus(success ? "Step " . row . " completed" : "Step " . row . " failed", success ? "ok" : "fail")
}

SimulateSingleStepByRow(row) {
    global g_CurrentSequenceSteps, g_Settings

    if row > g_CurrentSequenceSteps.Length
        return

    step := g_CurrentSequenceSteps[row]
    coords := GetStepCoordinates(step)

    tipText := "[Step " . row . "] " . step["action"]
    if step["target"] != "" && step["target"] != "(none)"
        tipText .= "`n→ " . step["target"]
    if step["param"] != ""
        tipText .= "`n  (" . step["param"] . ")"

    ShowTooltipTimed(tipText, 3000, coords["x"], coords["y"])
    ShowStatus("Simulated step " . row, "ok")
}

ToggleStepByRow(row) {
    global g_CurrentSequenceSteps, StepsLV

    if row > g_CurrentSequenceSteps.Length
        return

    g_CurrentSequenceSteps[row]["enabled"] := !g_CurrentSequenceSteps[row]["enabled"]
    RefreshStepsLV()
    ScheduleWorkflowAutosave()
}

ToggleAllOffExcept(exceptRow) {
    global g_CurrentSequenceSteps, StepsLV

    for i, step in g_CurrentSequenceSteps {
        step["enabled"] := (i = exceptRow)
    }
    RefreshStepsLV()
    ShowStatus("All OFF except step " . exceptRow, "ok")
    ScheduleWorkflowAutosave()
}

EnableAllSteps() {
    global g_CurrentSequenceSteps

    for step in g_CurrentSequenceSteps
        step["enabled"] := true
    RefreshStepsLV()
    ShowStatus("All steps enabled", "ok")
    ScheduleWorkflowAutosave()
}

EditStepByRow(row) {
    global StepsLV
    StepsLV.Modify(row, "Select Focus")
    EditStep()
}

DeleteStepByRow(row) {
    global g_CurrentSequenceSteps

    if row > g_CurrentSequenceSteps.Length
        return

    g_CurrentSequenceSteps.RemoveAt(row)
    RefreshStepsLV()
    ShowStatus("Deleted step " . row, "ok")
    ScheduleWorkflowAutosave()
}

MoveStepUp(row) {
    global g_CurrentSequenceSteps

    if row <= 1 || row > g_CurrentSequenceSteps.Length
        return

    temp := g_CurrentSequenceSteps[row]
    g_CurrentSequenceSteps[row] := g_CurrentSequenceSteps[row - 1]
    g_CurrentSequenceSteps[row - 1] := temp
    RefreshStepsLV()
    ScheduleWorkflowAutosave()
}

MoveStepDown(row) {
    global g_CurrentSequenceSteps

    if row < 1 || row >= g_CurrentSequenceSteps.Length
        return

    temp := g_CurrentSequenceSteps[row]
    g_CurrentSequenceSteps[row] := g_CurrentSequenceSteps[row + 1]
    g_CurrentSequenceSteps[row + 1] := temp
    RefreshStepsLV()
    ScheduleWorkflowAutosave()
}

DuplicateStep(row) {
    global g_CurrentSequenceSteps

    if row > g_CurrentSequenceSteps.Length
        return

    ; Deep copy the step
    original := g_CurrentSequenceSteps[row]
    copy := Map()
    for key, val in original
        copy[key] := val

    ; Insert after current position
    g_CurrentSequenceSteps.InsertAt(row + 1, copy)
    RefreshStepsLV()
    ShowStatus("Duplicated step " . row, "ok")
    ScheduleWorkflowAutosave()
}

; Sequence context menu handlers
SimulateSavedSeqByName(name) {
    global g_Sequences, g_AbortSequence

    if !g_Sequences.Has(name)
        return

    g_AbortSequence := false
    speed := g_Sequences[name].Has("speed") ? g_Sequences[name]["speed"] : 1.0
    SimulateSequence(g_Sequences[name]["steps"], speed)
}


LoadSeqByName(name) {
    if LoadWorkflowByName(name)
        ShowStatus("Loaded: " . name, "ok")
}


DuplicateSequence(name) {
    global g_Sequences

    if !g_Sequences.Has(name)
        return

    newName := name . "_copy"
    counter := 1
    while g_Sequences.Has(newName) {
        newName := name . "_copy" . counter
        counter++
    }

    ; Deep copy
    g_Sequences[newName] := Map("steps", [], "speed", g_Sequences[name].Has("speed") ? g_Sequences[name]["speed"] : 1.0)
    for step in g_Sequences[name]["steps"] {
        copy := Map()
        for key, val in step
            copy[key] := val
        g_Sequences[newName]["steps"].Push(copy)
    }

    if SaveSequences(true) {
        RefreshSeqLV()
        ShowStatus("Duplicated as: " . newName, "ok")
    } else {
        g_Sequences.Delete(newName)
    }
}

RenameSequence(oldName) {
    global g_Sequences

    newName := InputBox("Enter new name:", "Rename Sequence", "", oldName)
    if newName.Result != "OK" || newName.Value = ""
        return

    newName := newName.Value
    if newName = oldName
        return

    if g_Sequences.Has(newName) {
        MsgBoxTop("Name already exists!", "Error")
        return
    }

    renamedSequence := g_Sequences[oldName]
    UnregisterSequenceTriggers(oldName)
    g_Sequences[newName] := renamedSequence
    g_Sequences.Delete(oldName)
    if SaveSequences(true) {
        RegisterSequenceTriggers(newName)
        RefreshSeqLV()
        ShowStatus("Renamed to: " . newName, "ok")
    } else {
        g_Sequences.Delete(newName)
        g_Sequences[oldName] := renamedSequence
        RegisterSequenceTriggers(oldName)
    }
}

DeleteSeqByName(name) {
    global g_Sequences

    if !g_Sequences.Has(name)
        return

    result := MsgBoxTop("Delete sequence '" . name . "'?", "Confirm", "YesNo")
    if result != "Yes"
        return

    deletedSequence := g_Sequences[name]
    UnregisterSequenceTriggers(name)
    g_Sequences.Delete(name)
    if SaveSequences(true) {
        RefreshSeqLV()
        ShowStatus("Deleted: " . name, "ok")
    } else {
        g_Sequences[name] := deletedSequence
        RegisterSequenceTriggers(name)
    }
}



; ═══════════════════════════════════════════════════════════════════════════════
; PER-STEP FAILSAFE SYSTEM
; ═══════════════════════════════════════════════════════════════════════════════
; PER-STEP FAILSAFE SYSTEM

; ═══════════════════════════════════════════════════════════════════════════════
; EACH STEP CAN HAVE ACTION-SPECIFIC FAILSAFE CONDITIONS:
; ═══════════════════════════════════════════════════════════════════════════════
; Each step can have action-specific failsafe conditions:
; - Click actions: Check for close button pattern, require window match
; - Keyboard actions: Require specific window to be active
; - Pattern actions: Already have qualifier system
; - All actions: Optional pre-delay, max retries

EditStepFailsafe(*) {
    global StepsLV
    row := StepsLV.GetNext(0, "Focused")
    if row = 0 {
        ShowStatus("Select a step first", "fail")
        return
    }
    EditStepFailsafeByRow(row)
}

EditStepFailsafeByRow(row) {
    global g_CurrentSequenceSteps, g_Patterns

    if row > g_CurrentSequenceSteps.Length
        return

    step := g_CurrentSequenceSteps[row]
    action := step["action"]

    ; Build failsafe dialog based on action type
    fsGui := Gui("+AlwaysOnTop", "Step " . row . " Failsafe: " . action)
    fsGui.SetFont("s9", "Segoe UI")

    ; Get current failsafe settings
    fs := step.Has("failsafe") ? NormalizeStepFailsafe(step["failsafe"]) : Map()
    if step.Has("failsafe")
        step["failsafe"] := fs

    ; Common failsafes for all actions
    fsGui.Add("GroupBox", "w450 h80 Section", "Common Failsafes")
    fsGui.Add("Text", "xs+10 ys+20", "Required Window Title:")
    fsWindowEdit := fsGui.Add("Edit", "x+5 w250 vFsWindow", fs.Has("window") ? fs["window"] : "")
    fsGui.Add("Button", "x+5 w60 h22", "Get").OnEvent("Click", (*) => (fsWindowEdit.Value := WinGetTitle("A")))

    fsGui.Add("CheckBox", "xs+10 y+10 vFsAbortOnFail", "Abort sequence if this step fails").Value := fs.Has("abortOnFail") ? fs["abortOnFail"] : 0

    ; Action-specific failsafes
    if InStr(action, "Click") || action = "Drag" {
        ; Click-specific failsafes
        fsGui.Add("GroupBox", "xs y+20 w450 h100", "Click/Position Failsafes")

        fsGui.Add("CheckBox", "xp+10 yp+20 vFsCheckCloseBtn", "Block clicks near window close button").Value := fs.Has("checkCloseBtn") ? fs["checkCloseBtn"] : 1

        fsGui.Add("CheckBox", "y+8 vFsRequirePattern", "Require pattern visible before clicking:").Value := fs.Has("requirePattern") ? fs["requirePattern"] : 0

        ; Pattern dropdown
        patternChoices := ["(none)"]
        for name, _ in g_Patterns
            patternChoices.Push(name)
        fsPatternDD := fsGui.Add("DropDownList", "x+5 w200 vFsPattern", patternChoices)
        if fs.Has("pattern") && fs["pattern"] != "" {
            for i, p in patternChoices {
                if p = fs["pattern"] {
                    fsPatternDD.Choose(i)
                    break
                }
            }
        } else {
            fsPatternDD.Choose(1)
        }

        fsGui.Add("CheckBox", "xs+10 y+10 vFsVerifyPosition", "Verify mouse position after move").Value := fs.Has("verifyPosition") ? fs["verifyPosition"] : 1

    } else if InStr(action, "Key") || action = "Send Keys" || action = "Type Text" {
        ; Keyboard-specific failsafes
        fsGui.Add("GroupBox", "xs y+20 w450 h80", "Keyboard Failsafes")

        fsGui.Add("CheckBox", "xp+10 yp+20 vFsWaitForIdle", "Wait for window to be idle before sending").Value := fs.Has("waitForIdle") ? fs["waitForIdle"] : 0

        fsGui.Add("Text", "y+10", "Delay before sending (ms):")
        fsGui.Add("Edit", "x+5 w60 vFsPreDelay Number", fs.Has("preDelay") ? fs["preDelay"] : "0")

    } else if InStr(action, "Activate") || InStr(action, "Taskbar") {
        ; Window activation failsafes
        fsGui.Add("GroupBox", "xs y+20 w450 h80", "Activation Failsafes")

        fsGui.Add("Text", "xp+10 yp+20", "Max wait time (ms):")
        fsGui.Add("Edit", "x+5 w60 vFsMaxWait Number", fs.Has("maxWait") ? fs["maxWait"] : "3000")

        fsGui.Add("CheckBox", "xs+10 y+10 vFsRetryIfHidden", "Retry if window doesn't appear").Value := fs.Has("retryIfHidden") ? fs["retryIfHidden"] : 1

    } else if InStr(action, "Wait") {
        ; Wait action failsafes
        fsGui.Add("GroupBox", "xs y+20 w450 h60", "Wait Failsafes")

        fsGui.Add("CheckBox", "xp+10 yp+20 vFsContinueOnTimeout", "Continue sequence even if wait times out").Value := fs.Has("continueOnTimeout") ? fs["continueOnTimeout"] : 0
    }

    ; Retry settings
    fsGui.Add("GroupBox", "xs y+20 w450 h60", "Retry Settings")
    fsGui.Add("Text", "xp+10 yp+20", "Max retries:")
    fsGui.Add("Edit", "x+5 w50 vFsMaxRetries Number", fs.Has("maxRetries") ? fs["maxRetries"] : "3")
    fsGui.Add("Text", "x+20", "Retry delay (ms):")
    fsGui.Add("Edit", "x+5 w60 vFsRetryDelay Number", fs.Has("retryDelay") ? fs["retryDelay"] : "200")

    ; Buttons
    fsGui.Add("Button", "xs y+20 w100 h28", "Save").OnEvent("Click", (*) => SaveStepFailsafe(fsGui, row))
    fsGui.Add("Button", "x+10 w100 h28", "Clear All").OnEvent("Click", (*) => (ClearStepFailsafe(row), fsGui.Destroy()))
    fsGui.Add("Button", "x+10 w100 h28", "Cancel").OnEvent("Click", (*) => fsGui.Destroy())

    fsGui.Show()
}

SaveStepFailsafe(fsGui, row) {
    global g_CurrentSequenceSteps

    if row > g_CurrentSequenceSteps.Length
        return

    step := g_CurrentSequenceSteps[row]
    fs := Map()

    ; Get all values from GUI
    try {
        ; Common
        fs["window"] := fsGui["FsWindow"].Value
        fs["abortOnFail"] := fsGui["FsAbortOnFail"].Value

        ; Action-specific (check if controls exist)
        try fs["checkCloseBtn"] := fsGui["FsCheckCloseBtn"].Value
        try fs["requirePattern"] := fsGui["FsRequirePattern"].Value
        try fs["pattern"] := fsGui["FsPattern"].Text != "(none)" ? fsGui["FsPattern"].Text : ""
        try fs["verifyPosition"] := fsGui["FsVerifyPosition"].Value
        try fs["waitForIdle"] := fsGui["FsWaitForIdle"].Value
        try fs["preDelay"] := Integer(fsGui["FsPreDelay"].Value)
        try fs["maxWait"] := Integer(fsGui["FsMaxWait"].Value)
        try fs["retryIfHidden"] := fsGui["FsRetryIfHidden"].Value
        try fs["continueOnTimeout"] := fsGui["FsContinueOnTimeout"].Value

        ; Retry settings
        fs["maxRetries"] := Integer(fsGui["FsMaxRetries"].Value)
        fs["retryDelay"] := Integer(fsGui["FsRetryDelay"].Value)
    }

    step["failsafe"] := fs
    fsGui.Destroy()
    RefreshStepsLV()
    ShowStatus("Failsafe saved for step " . row, "ok")
    ScheduleWorkflowAutosave()
}

ClearStepFailsafe(row) {
    global g_CurrentSequenceSteps

    if row > g_CurrentSequenceSteps.Length
        return

    if g_CurrentSequenceSteps[row].Has("failsafe")
        g_CurrentSequenceSteps[row].Delete("failsafe")

    RefreshStepsLV()
    ShowStatus("Failsafe cleared for step " . row, "ok")
    ScheduleWorkflowAutosave()
}

; Get failsafe summary for ListView display
; GetFailsafeSummary(step) {
;     if !step.Has("failsafe")
;         return "-"

;     fs := step["failsafe"]
;     parts := []

;     if fs.Has("window") && fs["window"] != ""
;         parts.Push("Win")
;     if fs.Has("pattern") && fs["pattern"] != ""
;         parts.Push("Pat")
;     if fs.Has("checkCloseBtn") && fs["checkCloseBtn"]
;         parts.Push("NoX")
;     if fs.Has("abortOnFail") && fs["abortOnFail"]
;         parts.Push("Abort")

;     return parts.Length > 0 ? StrJoin(parts, ",") : "-"
; }
GetFailsafeSummary(step) {
    if !step.Has("failsafe")
        return "-"

    fs := step["failsafe"]

    ; Check if fs is a Map (not a string from old data)
    if !IsObject(fs) || !(fs is Map)
        return "-"

    parts := []

    if fs.Has("window") && fs["window"] != ""
        parts.Push("Win")
    if fs.Has("pattern") && fs["pattern"] != ""
        parts.Push("Pat")
    if fs.Has("checkCloseBtn") && fs["checkCloseBtn"]
        parts.Push("NoX")
    if fs.Has("abortOnFail") && fs["abortOnFail"]
        parts.Push("Abort")

    return parts.Length > 0 ? StrJoin(parts, ",") : "-"
}

; Helper to join array with separator
StrJoin(arr, sep) {
    result := ""
    for i, item in arr {
        if i > 1
            result .= sep
        result .= item
    }
    return result
}

SimulateSingleStep(*) {
    global StepsLV
    row := StepsLV.GetNext(0, "Focused")
    if row = 0 {
        ShowStatus("Select a step first", "fail")
        return
    }
    SimulateSingleStepByRow(row)
}



; ═══════════════════════════════════════════════════════════════════════════════
; TEST SINGLE STEP
; ═══════════════════════════════════════════════════════════════════════════════
; TEST SINGLE STEP
; =============================================================================

TestSingleStep(*) {
    global g_CurrentSequenceSteps, StepsLV, g_AbortSequence

    row := StepsLV.GetNext(0, "Focused")
    if row = 0 {
        ShowStatus("Select a step first", "fail")
        return
    }

    if row > g_CurrentSequenceSteps.Length
        return

    step := g_CurrentSequenceSteps[row]
    if !step["enabled"] {
        ShowStatus("Step is disabled", "fail")
        return
    }

    g_AbortSequence := false
    speed := GetSpeedMultiplier()
    ShowStatus("Testing step " . row . ": " . step["action"] . " @ " . speed . "x", "wait")

    success := ExecuteActionVerified(step["action"], step["target"], step["param"], step, speed)

    if success {
        ShowStatus("Step " . row . " completed", "ok")
    } else {
        ShowStatus("Step " . row . " failed", "fail")
    }
}


; =============================================================================
; BUILT-IN WORKFLOW DEMO LAB
; A secondary window owned by MacroAutomator. Demo .maw files can safely click,
; type, paste, OCR, drag, select menus, and fire revolvers without touching a
; real application or the user's documents.
; =============================================================================

ShowWorkflowDemoLab(reset := true) {
    global MainGui, g_DemoLabGui, g_DemoLabControls, g_DemoLabLogEdit, g_DemoLabStatusText

    PreserveWorkflowDemoState()

    if IsObject(g_DemoLabGui) {
        try {
            g_DemoLabGui.Show()
            if reset
                ResetWorkflowDemoLab()
            WinActivate("ahk_id " . g_DemoLabGui.Hwnd)
            Sleep(150)
            PrepareWorkflowDemoLabTargets()
            return true
        }
    }

    lab := Gui("+Owner" . MainGui.Hwnd . " +AlwaysOnTop", "MacroAutomator Demo Lab")
    lab.SetFont("s9", "Segoe UI")
    lab.OnEvent("Close", DemoLabHide)

    lab.SetFont("s16 bold", "Segoe UI")
    lab.Add("Text", "x20 y12 w940 h30 Center", "SAFE WORKFLOW DEMO LAB")
    lab.SetFont("s9", "Segoe UI")
    lab.Add("Text", "x20 y43 w940 h20 Center c666666",
        "All mouse, keyboard, OCR, clipboard, menu, drag, and revolver demonstrations stay inside this window.")

    lab.Add("GroupBox", "x15 y68 w610 h260", "OCR-discovered Notepad and protected input area")
    notepadButton := lab.Add("Button", "x30 y90 w145 h38", "Notepad")
    notepadButton.SetFont("s13 bold", "Segoe UI")
    notepadButton.OnEvent("Click", DemoLabFocusNotepad)
    lab.Add("Text", "x190 y98 w415 h28 c555555",
        "OCR Click finds the word Notepad, clicks it, then focuses the edit box below.")
    demoNotepadEdit := lab.Add("Edit", "x30 y138 w575 h170 Multi WantTab VScroll", "")
    clearNotepad := lab.Add("Button", "x490 y92 w115 h28", "Clear Notepad")
    clearNotepad.OnEvent("Click", (*) => DemoLabClearNotepad())

    lab.Add("GroupBox", "x635 y68 w330 h260", "Visible event log")
    logEdit := lab.Add("Edit", "x650 y90 w300 h218 ReadOnly Multi VScroll", "")

    lab.Add("GroupBox", "x15 y338 w950 h145", "Mouse, FindText, relative, drag, hover, and menu targets")
    singleTarget := lab.Add("Text", "x30 y363 w135 h32 Border Center 0x200", "SINGLE CLICK")
    doubleTarget := lab.Add("Text", "x175 y363 w135 h32 Border Center 0x200", "DOUBLE CLICK")
    tripleTarget := lab.Add("Text", "x320 y363 w135 h32 Border Center 0x200", "TRIPLE CLICK")
    rightTarget := lab.Add("Text", "x465 y363 w135 h32 Border Center 0x200", "RIGHT CLICK")
    hoverTarget := lab.Add("Text", "x610 y363 w135 h32 Border Center 0x200", "HOVER TARGET")
    menuTarget := lab.Add("DropDownList", "x755 y363 w190", ["MENU READY", "Choice Alpha", "Choice Beta", "Choice Gamma"])
    menuTarget.Choose(1)

    findTarget := lab.Add("Text", "x30 y410 w170 h38 Border Center 0x200", "FINDTEXT TARGET 4K2")
    goneTarget := lab.Add("Text", "x210 y410 w160 h38 Border Center 0x200", "GONE TARGET 7Q9")
    dragStart := lab.Add("Text", "x380 y410 w120 h38 Border Center 0x200", "DRAG START")
    dropZone := lab.Add("Text", "x510 y410 w120 h38 Border Center 0x200", "DROP ZONE")
    relativeAnchor := lab.Add("Text", "x640 y410 w140 h38 Border Center 0x200", "RELATIVE START")
    relativeResult := lab.Add("Text", "x790 y410 w155 h38 Border Center 0x200", "RELATIVE RESULT")

    for item in [
        [singleTarget, "Single Click received"],
        [doubleTarget, "Double Click target received a click"],
        [tripleTarget, "Triple Click target received a click"],
        [rightTarget, "Right Click target received a left click"],
        [findTarget, "FindText target received a click"],
        [relativeAnchor, "Relative Click anchor selected"],
        [relativeResult, "Relative Click reached its calculated destination"]
    ]
        item[1].OnEvent("Click", DemoLabControlEvent.Bind(item[2]))
    rightTarget.OnEvent("ContextMenu", DemoLabControlEvent.Bind("Right Click received safely"))
    findTarget.OnEvent("ContextMenu", DemoLabControlEvent.Bind("FindText right-click received safely"))
    goneTarget.OnEvent("Click", DemoLabHideGoneTarget)
    menuTarget.OnEvent("Change", DemoLabMenuChanged)

    lab.Add("GroupBox", "x15 y493 w950 h78", "Clipboard Revolver destination fields")
    field1 := lab.Add("Edit", "x30 y520 w210 h28", "")
    field2 := lab.Add("Edit", "x255 y520 w210 h28", "")
    field3 := lab.Add("Edit", "x480 y520 w210 h28", "")
    field4 := lab.Add("Edit", "x705 y520 w240 h28", "")
    lab.Add("Text", "x30 y551 w915 h18 c666666",
        "Field order: LastName -> FirstName -> DOB -> CurrentDate. Revolver actions tab through these boxes.")

    statusText := lab.Add("Text", "x20 y582 w700 h26 Border Center 0x200 c006400", "READY - waiting for a workflow")
    resetButton := lab.Add("Button", "x735 y582 w105 h26", "Reset Lab")
    resetButton.OnEvent("Click", (*) => ResetWorkflowDemoLab())
    closeButton := lab.Add("Button", "x850 y582 w105 h26", "Hide Lab")
    closeButton.OnEvent("Click", DemoLabHide)

    g_DemoLabGui := lab
    g_DemoLabLogEdit := logEdit
    g_DemoLabStatusText := statusText
    g_DemoLabControls := Map(
        "notepad", notepadButton, "notepadedit", demoNotepadEdit,
        "single", singleTarget, "double", doubleTarget, "triple", tripleTarget,
        "right", rightTarget, "hover", hoverTarget, "menu", menuTarget,
        "find", findTarget, "gone", goneTarget, "dragstart", dragStart,
        "dropzone", dropZone, "relativeanchor", relativeAnchor,
        "relativeresult", relativeResult,
        "field1", field1, "field2", field2, "field3", field3, "field4", field4
    )

    lab.Show("w980 h625")
    WinActivate("ahk_id " . lab.Hwnd)
    Sleep(200)
    ResetWorkflowDemoLab()
    PrepareWorkflowDemoLabTargets()
    return true
}

PreserveWorkflowDemoState() {
    global g_DemoLabStateSaved, g_DemoLabSavedClipboard
    global g_DemoLabSavedMouseX, g_DemoLabSavedMouseY
    if g_DemoLabStateSaved
        return true
    try g_DemoLabSavedClipboard := ClipboardAll()
    catch
        g_DemoLabSavedClipboard := 0
    MouseGetPos(&g_DemoLabSavedMouseX, &g_DemoLabSavedMouseY)
    g_DemoLabStateSaved := true
    return true
}

RestoreWorkflowDemoState(*) {
    global g_DemoLabStateSaved, g_DemoLabSavedClipboard
    global g_DemoLabSavedMouseX, g_DemoLabSavedMouseY, g_DemoClipboardActive
    if !g_DemoLabStateSaved
        return true
    try {
        if IsObject(g_DemoLabSavedClipboard)
            A_Clipboard := g_DemoLabSavedClipboard
    }
    try MouseMove(g_DemoLabSavedMouseX, g_DemoLabSavedMouseY, 0)
    g_DemoLabSavedClipboard := 0
    g_DemoLabStateSaved := false
    g_DemoClipboardActive := false
    DemoLabLog("Original clipboard and mouse position restored.")
    ShowStatus("Demo state restored", "ok")
    return true
}

DemoLabHide(*) {
    global g_DemoLabGui
    RestoreWorkflowDemoState()
    if IsObject(g_DemoLabGui)
        try g_DemoLabGui.Hide()
}

ResetWorkflowDemoLab(*) {
    global g_DemoLabControls, g_DemoLabLogEdit, g_DemoLabStatusText, g_DemoClipboardActive
    if !IsObject(g_DemoLabControls) || g_DemoLabControls.Count = 0
        return
    g_DemoLabControls["notepadedit"].Value := ""
    for fieldName in ["field1", "field2", "field3", "field4"]
        g_DemoLabControls[fieldName].Value := ""
    g_DemoLabControls["menu"].Choose(1)
    g_DemoLabControls["gone"].Visible := true
    g_DemoLabLogEdit.Value := ""
    g_DemoLabStatusText.Text := "READY - waiting for a workflow"
    g_DemoClipboardActive := false
    DemoLabLog("Lab reset. All targets are ready.")
    Sleep(75)
    PrepareWorkflowDemoLabTargets()
}

DemoLabFocusNotepad(*) {
    global g_DemoLabControls
    if g_DemoLabControls.Has("notepadedit") {
        g_DemoLabControls["notepadedit"].Focus()
        DemoLabLog("OCR/Click selected Notepad; protected edit box focused.")
    }
}

DemoLabClearNotepad(*) {
    global g_DemoLabControls
    if g_DemoLabControls.Has("notepadedit") {
        g_DemoLabControls["notepadedit"].Value := ""
        g_DemoLabControls["notepadedit"].Focus()
        DemoLabLog("Notepad cleared.")
    }
}

DemoLabControlEvent(message, *) {
    DemoLabLog(message)
}

DemoLabMenuChanged(ctrl, *) {
    DemoLabLog("Menu Select chose: " . ctrl.Text)
}

DemoLabHideGoneTarget(*) {
    global g_DemoLabControls
    if g_DemoLabControls.Has("gone") {
        g_DemoLabControls["gone"].Visible := false
        DemoLabLog("Gone target hidden; Wait Until Gone can now succeed.")
    }
}

DemoLabLog(message) {
    global g_DemoLabLogEdit, g_DemoLabStatusText
    stamp := FormatTime(, "HH:mm:ss")
    if IsObject(g_DemoLabLogEdit) {
        existing := g_DemoLabLogEdit.Value
        g_DemoLabLogEdit.Value := stamp . "  " . message . (existing != "" ? "`r`n" . existing : "")
    }
    if IsObject(g_DemoLabStatusText)
        g_DemoLabStatusText.Text := message
}

PrepareWorkflowDemoLabTargets() {
    global g_Coordinates
    CaptureWorkflowDemoPattern("find", "DemoLabPattern")
    CaptureWorkflowDemoPattern("gone", "DemoLabGonePattern")

    if ResolveWorkflowPoint("demo:relativeanchor", &startX, &startY)
        && ResolveWorkflowPoint("demo:relativeresult", &endX, &endY) {
        g_Coordinates["DemoLabRelativeOffset"] := Map(
            "x", endX - startX, "y", endY - startY,
            "endX", "", "endY", "", "type", "Relative", "relative", true)
    }
}

CaptureWorkflowDemoPattern(controlKey, patternName) {
    global g_DemoLabControls, g_Patterns
    if !g_DemoLabControls.Has(controlKey) || !g_DemoLabControls[controlKey].Visible
        return false
    if !GetWorkflowControlRegion(g_DemoLabControls[controlKey], &region)
        return false
    try {
        patternText := FindText().GetTextFromScreen(
            region["x1"], region["y1"], region["x2"], region["y2"], "**50")
        if patternText = "" || StrLen(patternText) < 10
            return false
        g_Patterns[patternName] := Map(
            "text", "|<" . patternName . ">" . patternText,
            "desc", "Ephemeral built-in Workflow Demo Lab target",
            "screenshot", "", "captureX", (region["x1"] + region["x2"]) // 2,
            "captureY", (region["y1"] + region["y2"]) // 2,
            "captureWindow", "MacroAutomator Demo Lab", "qualifier", "")
        return true
    }
    return false
}

GetWorkflowControlRegion(ctrl, &region) {
    region := Map()
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " . ctrl.Hwnd)
        if w <= 0 || h <= 0
            return false
        region := Map("x1", x, "y1", y, "x2", x + w, "y2", y + h)
        return true
    }
    return false
}

FindWorkflowWindow(windowIdentifier) {
    if windowIdentifier = ""
        return 0
    try {
        if hwnd := WinExist(windowIdentifier)
            return hwnd
    }
    for hwnd in WinGetList() {
        title := ""
        try title := WinGetTitle(hwnd)
        if title != "" && InStr(title, windowIdentifier)
            return hwnd
    }
    return 0
}

ResolveWorkflowRegion(target, &region) {
    global MainGui, g_DemoLabGui, g_DemoLabControls
    region := Map()
    target := Trim(target)
    lowerTarget := StrLower(target)

    if SubStr(lowerTarget, 1, 5) = "demo:" {
        key := SubStr(lowerTarget, 6)
        if !IsObject(g_DemoLabGui)
            ShowWorkflowDemoLab(false)
        if key = "lab" {
            try {
                WinGetPos(&x, &y, &w, &h, "ahk_id " . g_DemoLabGui.Hwnd)
                region := Map("x1", x, "y1", y, "x2", x + w, "y2", y + h)
                return w > 0 && h > 0
            }
            return false
        }
        if g_DemoLabControls.Has(key)
            return GetWorkflowControlRegion(g_DemoLabControls[key], &region)
        return false
    }

    if SubStr(lowerTarget, 1, 8) = "control:" {
        controlName := Trim(SubStr(target, 9))
        try return GetWorkflowControlRegion(MainGui[controlName], &region)
        return false
    }

    if SubStr(lowerTarget, 1, 7) = "window:" {
        windowIdentifier := Trim(SubStr(target, 8))
        hwnd := FindWorkflowWindow(windowIdentifier)
        if !hwnd
            return false
        try {
            WinGetPos(&x, &y, &w, &h, "ahk_id " . hwnd)
            region := Map("x1", x, "y1", y, "x2", x + w, "y2", y + h)
            return w > 0 && h > 0
        }
    }
    return false
}

ResolveWorkflowPoint(target, &x, &y) {
    global g_Coordinates
    x := 0, y := 0
    target := Trim(target)
    if target != "" && g_Coordinates.Has(target) {
        coord := g_Coordinates[target]
        x := Integer(coord["x"]), y := Integer(coord["y"])
        return true
    }
    if InStr(target, ",") {
        parts := StrSplit(target, ",")
        if parts.Length >= 2 {
            try {
                x := Integer(Trim(parts[1])), y := Integer(Trim(parts[2]))
                return true
            }
        }
    }
    if ResolveWorkflowRegion(target, &region) {
        x := region["x1"] + (region["x2"] - region["x1"]) // 2
        y := region["y1"] + (region["y2"] - region["y1"]) // 2
        return true
    }
    return false
}

TryParseDemoClipboard() {
    global g_ExtractedData, g_SpoolVariables, g_DemoClipboardActive
    global ClipEdit, ExtractLV

    source := Trim(A_Clipboard)
    if SubStr(source, 1, 6) != "[DEMO]"
        return false

    fields := Map()
    payload := Trim(SubStr(source, 7))
    for pair in StrSplit(payload, ";") {
        equalsPos := InStr(pair, "=")
        if !equalsPos
            continue
        fieldName := Trim(SubStr(pair, 1, equalsPos - 1))
        fieldValue := Trim(SubStr(pair, equalsPos + 1))
        if fieldName != ""
            fields[fieldName] := fieldValue
    }
    if fields.Count = 0
        return false

    if !fields.Has("CurrentDate")
        fields["CurrentDate"] := FormatTime(, "MM/dd/yyyy")
    if !fields.Has("PatientName") && fields.Has("FirstName") && fields.Has("LastName")
        fields["PatientName"] := fields["FirstName"] . " " . fields["LastName"]

    g_ExtractedData := Map()
    for fieldName, fieldValue in fields {
        g_ExtractedData[fieldName] := fieldValue
        g_SpoolVariables[fieldName] := fieldValue
    }
    g_DemoClipboardActive := true

    try ClipEdit.Value := A_Clipboard
    try {
        ExtractLV.Delete()
        for fieldName, fieldValue in fields
            ExtractLV.Add("", fieldName, fieldValue)
    }
    DemoLabLog("Parse Clipboard extracted " . fields.Count . " built-in demo fields.")
    ShowStatus("Parsed " . fields.Count . " safe demo fields", "ok")
    return true
}

GetWorkflowActionNames() {
    return [
        ; ─── Mouse ───────────────────────────────────────────────
        "Click", "Double Click", "Triple Click", "Right Click",
        "Drag", "Relative Click", "Menu Select", "Scroll", "Idle Mouse", "Hover Mouse",
        ; ─── Keyboard ────────────────────────────────────────────
        "Send Keys", "Type Text", "Key Chord", "Paste",
        ; ─── Windows ─────────────────────────────────────────────
        "Activate Window", "Taskbar Activate", "Run Program",
        "Wait for Window", "Wait Window Closed",
        ; ─── Patterns (FindText images) ──────────────────────────
        "Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick", "Find & Drag",
        "Wait for Pattern", "Wait Until Gone",
        ; ─── Looping (its own action family) ─────────────────────
        "Loop Start", "Loop End", "Loop Break",
        "Find & Click Loop", "Popup Detect",
        ; ─── OCR & Vision ────────────────────────────────────────
        "OCR Region", "OCR Click", "OCR Wait", "Grab OCR to Var", "OCR Full Screen to Var",
        "Load OCR Revolver", "Fire OCR Revolver",
        ; ─── Clipboard & Text ────────────────────────────────────
        "Set Clipboard", "Insert Field", "Insert Date",
        "Parse Clipboard", "Load Revolver", "Fire Revolver", "Fire Revolver+Enter",
        "Format Clipboard", "Append to Clipboard", "Prepend to Clipboard", "Extract from Clipboard",
        ; ─── Variables & Logic ───────────────────────────────────
        "Set Variable", "Grab Clipboard", "If Contains", "If Variable",
        "Use Var Paste", "Stop Execution", "Run Sequence",
        ; ─── Tracking subsystem (see lib\ElementAutomation.ahk / ResearchPipeline.ahk)
        "Click Element", "Hover Element", "Wait Element", "Replay Window Mouse",
        "Research Search", "Research Capture Links", "Research Launch Next", "Research Add Insight",
        ; ─── Timing & Notices ────────────────────────────────────
        "Wait", "Show Notification"
    ]
}

; Which category each action belongs to (powers the Category filter dropdown).
GetActionCategory(action) {
    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click", "Drag", "Relative Click",
             "Menu Select", "Scroll", "Idle Mouse", "Hover Mouse":
            return "Mouse"
        case "Send Keys", "Type Text", "Key Chord", "Paste":
            return "Keyboard"
        case "Activate Window", "Taskbar Activate", "Run Program", "Wait for Window", "Wait Window Closed":
            return "Windows"
        case "Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick", "Find & Drag",
             "Wait for Pattern", "Wait Until Gone":
            return "Patterns"
        case "Loop Start", "Loop End", "Loop Break", "Find & Click Loop", "Popup Detect":
            return "Looping"
        case "OCR Region", "OCR Click", "OCR Wait", "Grab OCR to Var", "OCR Full Screen to Var",
             "Load OCR Revolver", "Fire OCR Revolver":
            return "OCR"
        case "Set Clipboard", "Insert Field", "Insert Date", "Parse Clipboard", "Load Revolver",
             "Fire Revolver", "Fire Revolver+Enter", "Format Clipboard", "Append to Clipboard",
             "Prepend to Clipboard", "Extract from Clipboard":
            return "Clipboard & Text"
        case "Set Variable", "Grab Clipboard", "If Contains", "If Variable",
             "Use Var Paste", "Stop Execution", "Run Sequence":
            return "Variables & Logic"
        case "Click Element", "Hover Element", "Wait Element", "Replay Window Mouse",
             "Research Search", "Research Capture Links", "Research Launch Next", "Research Add Insight":
            return "Tracking"
        case "Wait", "Show Notification":
            return "Timing & Notices"
    }
    return "Mouse"
}

GetActionCategoryNames() {
    return ["(All)", "Mouse", "Keyboard", "Windows", "Patterns", "Looping", "OCR",
            "Clipboard & Text", "Variables & Logic", "Tracking", "Timing & Notices"]
}

MakeActionSpec(targetLabel, targetHint, paramLabel, paramHint, example, helpText,
               targetRequired := false, paramRequired := false,
               targetUsed := true, paramUsed := true, choiceField := "") {
    return Map(
        "targetLabel", targetLabel, "targetHint", targetHint,
        "paramLabel", paramLabel, "paramHint", paramHint,
        "example", example, "help", helpText,
        "targetRequired", targetRequired, "paramRequired", paramRequired,
        "targetUsed", targetUsed, "paramUsed", paramUsed,
        "choiceField", choiceField
    )
}

GetWorkflowActionSpec(action) {
    switch action {
        case "Click":
            return MakeActionSpec("Position", "name / x,y / demo:key", "Click count", "optional", "Position=demo:notepadedit; count=1", "Uses saved/raw coordinates or a control in the built-in Demo Lab.", true, false, true, true, "target")
        case "Double Click", "Triple Click", "Right Click":
            return MakeActionSpec("Position", "name / x,y / demo:key", "", "", "Position=demo:double", "Uses saved/raw coordinates or a control in the built-in Demo Lab.", true, false, true, false, "target")
        case "Drag":
            return MakeActionSpec("Saved drag", "or leave blank", "Raw drag", "x1,y1->x2,y2", "Saved drag=MoveCard", "Use a captured drag name, or put a raw start/end pair in Raw drag.", false, false, true, true, "target")
        case "Relative Click":
            return MakeActionSpec("Saved offset", "required", "", "", "Saved offset=RightOfField", "Select a relative coordinate captured with the Rel. button.", true, false, true, false, "target")
        case "Menu Select":
            return MakeActionSpec("", "", "Down presses", "required", "Down presses=3", "Moves down through a menu, then presses Enter.", false, true, false, true, "param")
        case "Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick":
            return MakeActionSpec("Pattern", "required", "", "", "Pattern=SubmitButton", "Finds the saved FindText pattern and performs the selected click.", true, false, true, false, "target")
        case "Find & Click Loop":
            return MakeActionSpec("Pattern", "required", "Options", "key=value; key=value",
                "win=; scroll=-3; settle=600; maxClicks=90; maxScrolls=6; button=Left; clicks=1; top=; focus=; popup=; popupDo=enter; scrollSettle=; tol=",
                "Clicks the pattern, then scrolls down and repeats until the list is exhausted or maxClicks is reached. ESC aborts."
                . "`nOptions (all optional):"
                . "`n  win=Title      lock to a window: activate it, search only inside it, scroll it"
                . "`n  scroll=-3      wheel notches per scroll (negative = down, positive = up)"
                . "`n  settle=600     ms to wait AFTER each click before searching again"
                . "`n  scrollSettle=  ms to wait after each scroll (defaults to settle)"
                . "`n  maxClicks=90   stop after this many clicks"
                . "`n  maxScrolls=6   consecutive empty scrolls that mean end-of-list"
                . "`n  button=Left    Left or Right click"
                . "`n  clicks=1       clicks per find (2 = double)"
                . "`n  top=home       jump to top first (home = Ctrl+Home, or a number = that many wheel-ups)"
                . "`n  focus=x,y      click once at the start to focus the window (or focus=center)"
                . "`n  popup=Save     if this dialog appears mid-run, handle it then resume"
                . "`n  popupDo=enter  what to do with the popup: enter | send:!s | pattern:SaveBtn"
                . "`n  tol=           FindText tolerance override",
                true, false, true, true, "target")
        case "Find & Drag":
            return MakeActionSpec("Pattern", "required", "Destination", "endX,endY", "Pattern=Handle; Destination=800,500", "Finds the pattern, then drags from it to the destination.", true, true, true, true, "target")
        case "Wait for Pattern", "Wait Until Gone":
            return MakeActionSpec("Pattern", "required", "Timeout", "milliseconds", "Pattern=Loading; Timeout=5000", "Waits for the saved pattern to appear or disappear.", true, false, true, true, "target")
        case "Send Keys":
            return MakeActionSpec("", "", "Keys", "required", "Keys=^c or {Enter}", "AutoHotkey key syntax: ^=Ctrl, +=Shift, !=Alt, #=Win.", false, true, false, true, "param")
        case "Type Text":
            return MakeActionSpec("", "", "Text", "required", "Text=Hello world", "Types the supplied text literally.", false, true, false, true, "param")
        case "Key Chord":
            return MakeActionSpec("", "", "Chord", "modifier,key,count", "Chord=#,5,2", "Sends a modifier/key chord the requested number of times.", false, true, false, true, "param")
        case "Paste":
            return MakeActionSpec("", "", "", "", "No fields", "Pastes the current clipboard contents.", false, false, false, false)
        case "Set Clipboard":
            return MakeActionSpec("", "", "Clipboard text", "required", "Clipboard text=ID: $var.patientID", "Sets the clipboard; workflow variables are supported.", false, true, false, true, "param")
        case "Wait":
            return MakeActionSpec("", "", "Duration", "milliseconds", "Duration=1000", "Pauses the workflow for the specified time.", false, true, false, true, "param")
        case "Activate Window":
            return MakeActionSpec("", "", "Window title", "required", "Window title=Notepad", "Activates a window whose title contains this text.", false, true, false, true, "param")
        case "Taskbar Activate":
            return MakeActionSpec("", "", "Position,count", "or demo:lab", "Position,count=5,2", "Uses Win+number to activate a taskbar item. demo:lab safely demonstrates activation inside MacroAutomator.", false, true, false, true, "param")
        case "Run Program":
            return MakeActionSpec("", "", "Program/command", "required", "Program/command=demo:lab", "Runs an executable, document, URL, or command line. demo:lab opens the safe built-in Workflow Demo Lab.", false, true, false, true, "param")
        case "Insert Field":
            return MakeActionSpec("", "", "Field name", "required", "Field name=LastName", "Inserts a named extracted-data field.", false, true, false, true, "param")
        case "Insert Date":
            return MakeActionSpec("", "", "", "", "No fields", "Inserts the current date.", false, false, false, false)
        case "Scroll":
            return MakeActionSpec("", "", "Scroll amount", "+up / -down", "Scroll amount=-5", "Positive values scroll up; negative values scroll down.", false, true, false, true, "param")
        case "Parse Clipboard", "Load Revolver", "Fire Revolver", "Fire Revolver+Enter":
            return MakeActionSpec("", "", "", "", "No fields", "Uses the current clipboard/revolver state; no step input is needed.", false, false, false, false)
        case "OCR Region":
            return MakeActionSpec("OCR area", "coords / window:Title", "Output", "copy / var:name / split", "Area=window:MacroAutomator Demo Lab; Output=var:result", "Reads a coordinate rectangle, named window, or Demo Lab and copies or stores the text.", true, false, true, true, "param")
        case "OCR Click":
            return MakeActionSpec("OCR area", "coords / window:Title", "Text to click", "required", "Area=window:MacroAutomator Demo Lab; Text=Notepad", "Reads the area, finds matching text, and clicks its center.", true, true, true, true, "param")
        case "OCR Wait":
            return MakeActionSpec("OCR area", "coords / window:Title", "Condition", "timeout or text:...,ms", "Area=window:MacroAutomator Demo Lab; Condition=text:READY,5000", "Waits for OCR text, or simply for OCR to return text before timeout.", true, true, true, true, "param")
        case "OCR Full Screen to Var":
            return MakeActionSpec("", "", "Variable name", "required", "Variable name=fullScreenOCR", "Reads the full primary screen, stores all recognized text, and draws yellow boxes around every recognized word for 10 seconds.", false, true, false, true, "param")
        case "Load OCR Revolver":
            return MakeActionSpec("", "", "Split rule", "tab / line / count / char", "Split rule=tab", "Splits the latest OCR text and loads the OCR revolver.", false, false, false, true, "param")
        case "Fire OCR Revolver":
            return MakeActionSpec("", "", "", "", "No fields", "Pastes the next OCR revolver value.", false, false, false, false)
        case "Idle Mouse":
            return MakeActionSpec("", "", "Seconds", "0 = until stopped", "Seconds=30", "Gently moves the mouse for a duration; zero runs indefinitely.", false, false, false, true, "param")
        case "Hover Mouse":
            return MakeActionSpec("Position", "name or x,y", "", "", "Position=HelpIcon", "Moves the mouse to a saved coordinate without clicking.", true, false, true, false, "target")
        case "Grab OCR to Var":
            return MakeActionSpec("OCR area", "coords / window:Title", "Variable name", "required", "Area=window:MacroAutomator Demo Lab; Variable=labText", "Captures coordinates, a named window, or the Demo Lab and stores its text as a workflow variable.", true, true, true, true, "param")
        case "Use Var Paste":
            return MakeActionSpec("", "", "Text/template", "required", "Text/template=Patient: $var.patientID", "Expands workflow variables and pastes the result.", false, true, false, true, "param")
        case "Show Notification":
            return MakeActionSpec("", "", "Title,message,seconds", "required", "Done,Workflow complete,3", "Shows a desktop notification; variables are supported.", false, true, false, true, "param")
        case "Set Variable":
            return MakeActionSpec("Variable name", "letters/numbers/_", "Value", "text or $var.name", "Variable name=counter; Value=0", "Creates or replaces a workflow variable. Use it later as $var.counter.", true, false, true, true, "param")
        case "Grab Clipboard":
            return MakeActionSpec("Variable name", "letters/numbers/_", "", "", "Variable name=clipboardText", "Stores the current clipboard text in a workflow variable.", true, false, true, false, "target")
        case "If Contains":
            return MakeActionSpec("Variable name", "value to inspect", "Search text", "case-insensitive", "Variable name=ocrText; Search text=invoice", "Runs the next enabled step only when the variable contains the search text; otherwise that one step is skipped.", true, true, true, true, "target")
        case "If Variable":
            return MakeActionSpec("Variable name", "value to compare", "Comparison", "operator,value", "Variable name=count; Comparison=>=,5", "Compares a variable. Operators: =, !=, >, <, >=, <=. A false result skips the next enabled step.", true, true, true, true, "param")
        case "Stop Execution":
            return MakeActionSpec("", "", "", "", "No fields", "Stops the current workflow immediately without reporting an action failure.", false, false, false, false)
        case "Run Sequence":
            return MakeActionSpec("", "", "Workflow name", "required", "Workflow name=EnterPatient", "Runs another saved workflow as a sub-workflow. Variables remain available to it, and recursive calls are blocked.", false, true, false, true, "param")
        case "Format Clipboard":
            return MakeActionSpec("", "", "Format", "preset or {clip} template", "Format=uppercase", "Transforms the clipboard. Presets: invoice, receipt, uppercase, lowercase, titlecase, trim, date_iso. Custom templates use {clip}.", false, true, false, true, "param")
        case "Append to Clipboard":
            return MakeActionSpec("", "", "Text to append", "variables allowed", "Text to append= - reviewed", "Adds text to the end of the current clipboard.", false, true, false, true, "param")
        case "Prepend to Clipboard":
            return MakeActionSpec("", "", "Text to prepend", "variables allowed", "Text to prepend=INV-", "Adds text to the beginning of the current clipboard.", false, true, false, true, "param")
        case "Extract from Clipboard":
            return MakeActionSpec("", "", "Extraction rule", "between:/field:/regex:", "Extraction rule=field:,|2", "Replaces the clipboard with extracted text. Rules: between:start|end, field:delimiter|index, or regex:pattern.", false, true, false, true, "param")

        ; ─── Looping family ──────────────────────────────────────────────────
        case "Loop Start":
            return MakeActionSpec("", "", "Loop settings", "key=value; key=value",
                "count=5; var=i",
                "Opens a loop body. Every step between this and Loop End repeats."
                . "`n  count=5       how many times (or count=forever - ESC stops)"
                . "`n  var=i         the loop counter variable name"
                . "`nInside the loop, $var.<name> = current pass (1, 2, 3...), and"
                . "`n$var.loopCount = the total. Variables set inside the loop are"
                . "`nremembered from one pass to the next (loop memory).",
                false, false, false, true, "param")
        case "Loop End":
            return MakeActionSpec("", "", "", "", "No fields", "Closes the loop body opened by Loop Start. The steps in between run again until the count is reached.", false, false, false, false)
        case "Loop Break":
            return MakeActionSpec("", "", "", "", "No fields", "Stops the current loop early and continues with the step after its Loop End.", false, false, false, false)
        case "Popup Detect":
            return MakeActionSpec("", "", "Detect settings", "key=value; key=value",
                "win=; region=0,0,800,600; sensitivity=medium; on=var; mode=now; timeout=5000; var=popupChanged",
                "Remembers what a window or screen region looks like at the top of a"
                . " loop, then flags when it changes drastically - e.g. a popup opened."
                . "`n  win=Title         watch a whole window (pick from the list)"
                . "`n  region=x,y,w,h    or watch a rectangle (drag to select)"
                . "`n  sensitivity=high|medium|low   how much change counts"
                . "`n  on=var|skip|break|stop        what to do when a change is seen:"
                . "     just set $var.name, skip the next step, break the loop, or stop"
                . "`n  mode=now|wait     check once, or wait up to timeout for a change"
                . "`n  var=popupChanged  the variable that receives 1 (changed) or 0",
                false, false, false, true, "param")

        ; ─── Window waiting ──────────────────────────────────────────────────
        case "Wait for Window":
            return MakeActionSpec("", "", "Window settings", "key=value; key=value",
                "title=Save As; timeout=5000",
                "Waits until a window appears (for example a popup dialog)."
                . "`n  title=Title     window to wait for (pick from the list)"
                . "`n  timeout=5000    give up after this many milliseconds",
                false, false, false, true, "param")
        case "Wait Window Closed":
            return MakeActionSpec("", "", "Window settings", "key=value; key=value",
                "title=Save As; timeout=5000",
                "Waits until a window disappears (a loading box, a popup...)."
                . "`n  title=Title     window to wait on (pick from the list)"
                . "`n  timeout=5000    give up after this many milliseconds",
                false, false, false, true, "param")

        ; ─── Tracking subsystem ──────────────────────────────────────────────
        case "Click Element":
            return MakeActionSpec("Element", "name from Snapshot Viewer", "Button", "Left/Right/Middle[,count]", "Element=SearchBox; Button=Left", "Finds a named element on screen (by its saved FindText pattern, or by window-relative position) and clicks it.", true, false, true, true, "target")
        case "Hover Element":
            return MakeActionSpec("Element", "name from Snapshot Viewer", "", "", "Element=SubmitButton", "Moves the mouse onto a named element without clicking.", true, false, true, false, "target")
        case "Wait Element":
            return MakeActionSpec("Element", "name from Snapshot Viewer", "Timeout", "milliseconds", "Element=ResultsList; Timeout=5000", "Waits until a named element appears on screen.", true, false, true, true, "target")
        case "Replay Window Mouse":
            return MakeActionSpec("Window", "tracked window name", "Speed", "speed[,clicks]", "Window=Chrome; Speed=1.0,clicks", "Replays the most recent recorded mouse movement for that window, rescaled onto its current position.", true, false, true, true, "target")
        case "Research Search":
            return MakeActionSpec("", "", "Query", "required", "Query=best ahk libraries", "Stores the query in the database and opens a search for it in the browser.", false, true, false, true, "param")
        case "Research Capture Links":
            return MakeActionSpec("", "", "Source", "screen or clip", "Source=screen", "Harvests result URLs for the current query - by OCR of the page, or from the clipboard.", false, true, false, true, "param")
        case "Research Launch Next":
            return MakeActionSpec("", "", "", "", "", "Opens the next pending result link for the current query.", false, false, false, false)
        case "Research Add Insight":
            return MakeActionSpec("", "", "Insight", "required", "Insight=Supports v2 natively", "Attaches a key takeaway to the current query and marks the link done.", false, true, false, true, "param")

        default:
            return MakeActionSpec("Target", "optional", "Value", "optional", "", "See the action guide for details.")
    }
}


; The Add Step button now opens the guided form; everything is chosen from
; lists/pickers there. QuickAddStep bypasses it for power users who typed
; directly into the Target/Param fields.
AddStep(*) {
    global ActionDD
    if ActionDD.Text = "" {
        ShowStatus("Please select an action", "fail")
        return
    }
    ShowActionForm(0)
}

QuickAddStep(*) {
    global ActionDD
    if ActionDD.Text = "" {
        ShowStatus("Please select an action", "fail")
        return
    }
    AddStepFromFields()
}

AddStepFromFields(*) {
    global g_CurrentSequenceSteps, ActionDD, TargetDD, ParamEdit, ParamCombo, QualPatternDD, QualWindowEdit, FailsafeCloseCheck
    ; Validate action is selected
    if ActionDD.Text = "" {
        ShowStatus("Please select an action", "fail")
        return
    }

    action := ActionDD.Text

    spec := GetWorkflowActionSpec(action)
    if spec["targetRequired"] && Trim(TargetDD.Text) = "" {
        ShowStatus(spec["targetLabel"] . " is required for " . action, "fail")
        return
    }
    if spec["paramRequired"] && Trim(ParamCombo.Text) = "" {
        ShowStatus(spec["paramLabel"] . " is required for " . action, "fail")
        return
    }
    if action = "Drag" && Trim(TargetDD.Text) = "" && Trim(ParamCombo.Text) = "" {
        ShowStatus("Drag requires either a saved drag or raw x1,y1->x2,y2", "fail")
        return
    }

    ; V5.1: Parameter validation before adding step
    if !ShowParameterValidation(action, TargetDD.Text, ParamCombo.Text) {
        return
    }

    saved := MainGui.Submit(false)
    target := TargetDD.Text
    if SubStr(target, 1, 4) = "[P] "
        target := SubStr(target, 5)
    if InStr(target, " (") && InStr(target, ",")
        target := Trim(SubStr(target, 1, InStr(target, " (") - 1))

    step := Map(
        "action", ActionDD.Text,
        "target", target,
        "param", saved.ActionParam,
        "enabled", true
    )

    if QualPatternDD.Text != "(none)"
        step["qualPattern"] := QualPatternDD.Text
    if saved.QualWindow != ""
        step["qualWindow"] := saved.QualWindow
    if saved.FailsafeClose
        step["failsafe"] := Map("checkCloseBtn", 1)

    g_CurrentSequenceSteps.Push(step)
    RefreshStepsLV()
    ParamEdit.Value := ""
    PopulateChoices()  ; V5.1: Refresh choices to show any new variables
    StatusBar.SetText("Added step " . g_CurrentSequenceSteps.Length)
    ScheduleWorkflowAutosave()
}

StepUp(*) {
    global g_CurrentSequenceSteps, StepsLV
    row := StepsLV.GetNext(0, "Focused")
    if row < 2
        return
    temp := g_CurrentSequenceSteps[row]
    g_CurrentSequenceSteps[row] := g_CurrentSequenceSteps[row - 1]
    g_CurrentSequenceSteps[row - 1] := temp
    RefreshStepsLV()
    StepsLV.Modify(row - 1, "Select Focus")
    ScheduleWorkflowAutosave()
}

StepDown(*) {
    global g_CurrentSequenceSteps, StepsLV
    row := StepsLV.GetNext(0, "Focused")
    if row = 0 || row >= g_CurrentSequenceSteps.Length
        return
    temp := g_CurrentSequenceSteps[row]
    g_CurrentSequenceSteps[row] := g_CurrentSequenceSteps[row + 1]
    g_CurrentSequenceSteps[row + 1] := temp
    RefreshStepsLV()
    StepsLV.Modify(row + 1, "Select Focus")
    ScheduleWorkflowAutosave()
}

; Editing now reuses the same guided form as adding: select the step's action
; in the editor, open the form pre-filled with the step's values.
EditStep(*) {
    global g_CurrentSequenceSteps, StepsLV
    row := StepsLV.GetNext(0, "Focused")
    if row = 0 || row > g_CurrentSequenceSteps.Length
        return

    SelectActionByName(g_CurrentSequenceSteps[row]["action"])
    ShowActionForm(row)
}

SelectActionByName(name) {
    global ActionDD, ActionCategoryDD
    ; Make sure the category filter is not hiding this action.
    if ActionCategoryDD.Text != "(All)" && GetActionCategory(name) != ActionCategoryDD.Text {
        catItems := ControlGetItems(ActionCategoryDD)
        for i, item in catItems {
            if item = "(All)" {
                ActionCategoryDD.Choose(i)
                break
            }
        }
    }
    RefreshActionList()
    found := false
    items := ControlGetItems(ActionDD)
    for i, item in items {
        if item = name {
            ActionDD.Choose(i)
            found := true
            break
        }
    }
    if !found {
        ; A legacy/custom step: still let the generic form edit it.
        ActionDD.Add([name])
        items := ControlGetItems(ActionDD)
        for i, item in items {
            if item = name {
                ActionDD.Choose(i)
                break
            }
        }
    }
    OnActionChange()
}

; Get param suggestions based on action type
GetActionParamSuggestions(action) {
    global g_ExtractedData, g_TaskbarApps, g_Sequences

    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click":
            return ["1", "2", "3"]
        case "Wait", "Wait for Pattern", "Wait Until Gone":
            return ["100", "200", "500", "1000", "2000", "3000", "5000", "10000"]
        case "Menu Select":
            return ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
        case "Send Keys":
            return ["^c", "^v", "^x", "^a", "^s", "^z", "{Enter}", "{Tab}", "{Escape}",
                    "{Up}", "{Down}", "{Left}", "{Right}", "!{Tab}", "!{F4}", "#r"]
        case "Key Chord":
            return ["#,5,2  (Win+5 x2)", "#,1,1  (Win+1)", "^,{Tab},3  (Ctrl+Tab x3)",
                    "!,{Tab},2  (Alt+Tab x2)", "^+,{Tab},1  (Ctrl+Shift+Tab)"]
        case "Taskbar Activate":
            choices := ["1,1", "2,1", "3,1", "4,1", "5,1", "5,2", "6,1", "7,1", "8,1", "9,1", "0,1"]
            return choices
        case "Activate Window":
            return GetWindowList()
        case "Run Program":
            return ["notepad.exe", "calc.exe", "chrome.exe", "cmd.exe", "explorer.exe", "code.exe"]
        case "Scroll":
            return ["-10", "-5", "-3", "-1", "1", "3", "5", "10"]
        case "Insert Field":
            choices := []
            for name, _ in g_ExtractedData
                choices.Push(name)
            choices.Push("CurrentDate")
            return choices
        case "Find & Drag":
            return ["500,500", "0,100", "100,0", "-100,0", "0,-100"]
        case "Drag":
            return ["100,100->200,200", "0,0->100,100"]
        case "Relative Click":
            return ["10,0", "-10,0", "0,10", "0,-10", "50,50", "100,0"]
        case "If Variable":
            return ["=,value", "!=,value", ">,0", ">=,5", "<,10", "<=,100"]
        case "Run Sequence":
            choices := []
            for name, _ in g_Sequences
                choices.Push(name)
            return choices
        case "Format Clipboard":
            return ["invoice", "receipt", "uppercase", "lowercase", "titlecase", "trim", "date_iso", "[{clip}]"]
        case "Extract from Clipboard":
            return ["between:start|end", "field:,|1", "regex:\\d+"]
        default:
            return [""]
    }
}

; Get help text for action parameter
GetActionParamHelp(action) {
    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click":
            return "Leave empty for default (1 click), or enter click count"
        case "Wait":
            return "Enter milliseconds to wait"
        case "Wait for Pattern", "Wait Until Gone":
            return "Enter timeout in ms (default 5000)"
        case "Send Keys":
            return "^ = Ctrl, + = Shift, ! = Alt, # = Win. Use {Key} for special keys"
        case "Key Chord":
            return "Format: modifier,key,count (e.g. #,5,2 for Win+5 twice)"
        case "Taskbar Activate":
            return "Format: position,count (e.g. 5,2 for Win+5 twice)"
        case "Activate Window":
            return "Partial window title match"
        case "Type Text":
            return "Text to type character by character"
        case "Find & Drag":
            return "Format: endX,endY"
        case "Drag":
            return "Format: startX,startY->endX,endY"
        case "Scroll":
            return "Positive = up, Negative = down"
        case "Set Variable":
            return "Target is the variable name; Param is its value"
        case "If Contains":
            return "Target is a variable; a false test skips the next enabled step"
        case "If Variable":
            return "Format: operator,value (for example >=,5)"
        case "Run Sequence":
            return "Exact saved workflow name; recursive calls are blocked"
        case "Format Clipboard":
            return "Use a preset or a custom template containing {clip}"
        case "Extract from Clipboard":
            return "between:start|end, field:delimiter|index, or regex:pattern"
        default:
            return ""
    }
}

; Clean suggestion text (remove descriptions)
CleanSuggestion(text) {
    if InStr(text, "  (")
        return Trim(SubStr(text, 1, InStr(text, "  (") - 1))
    if InStr(text, "  [")
        return Trim(SubStr(text, 1, InStr(text, "  [") - 1))
    return text
}

; Save edited step
SaveEditedStep(editGui, row) {
    global g_CurrentSequenceSteps

    if row > g_CurrentSequenceSteps.Length
        return

    saved := editGui.Submit(false)

    ; Update target if changed
    if saved.NewTarget != "(none)"
        g_CurrentSequenceSteps[row]["target"] := saved.NewTarget

    ; Update parameter
    g_CurrentSequenceSteps[row]["param"] := saved.NewParam

    editGui.Destroy()
    RefreshStepsLV()
    ShowStatus("Step " . row . " updated", "ok")
    ScheduleWorkflowAutosave()
}

DelStep(*) {
    global g_CurrentSequenceSteps, StepsLV
    row := StepsLV.GetNext(0, "Focused")
    if row = 0
        return
    g_CurrentSequenceSteps.RemoveAt(row)
    RefreshStepsLV()
    ScheduleWorkflowAutosave()
}

ToggleStep(*) {
    global g_CurrentSequenceSteps, StepsLV
    row := StepsLV.GetNext(0, "Focused")
    if row = 0
        return

    ; Ensure enabled property exists before toggling
    if !g_CurrentSequenceSteps[row].Has("enabled")
        g_CurrentSequenceSteps[row]["enabled"] := true

    g_CurrentSequenceSteps[row]["enabled"] := !g_CurrentSequenceSteps[row]["enabled"]
    RefreshStepsLV()
    StepsLV.Modify(row, "Select Focus")
    ScheduleWorkflowAutosave()
}

ClearSteps(*) {
    global g_CurrentSequenceSteps
    g_CurrentSequenceSteps := []
    RefreshStepsLV()
    ScheduleWorkflowAutosave()
}

RefreshStepsLV() {
    global g_CurrentSequenceSteps, StepsLV
    StepsLV.Delete()
    for i, s in g_CurrentSequenceSteps {
        ; Default enabled to true if not set
        if !s.Has("enabled")
            s["enabled"] := true

        failsafeSummary := GetFailsafeSummary(s)
        StepsLV.Add(s["enabled"] ? "Check" : "", i, s["action"], s["target"], s["param"], failsafeSummary)
    }
}

CloneWorkflowSteps(steps) {
    cloned := []
    for step in steps {
        newStep := Map()
        for key, value in step {
            if key = "failsafe" && value is Map {
                fsCopy := Map()
                for fsKey, fsValue in value
                    fsCopy[fsKey] := fsValue
                newStep[key] := fsCopy
            } else {
                newStep[key] := value
            }
        }
        cloned.Push(newStep)
    }
    return cloned
}

BuildCurrentWorkflowData() {
    global g_CurrentSequenceSteps, SpeedDD, SeqHotkeyEdit, SeqHotstringEdit
    speedText := SpeedDD.Text != "" ? SpeedDD.Text : "1x"
    seqData := Map("steps", CloneWorkflowSteps(g_CurrentSequenceSteps), "speed", Float(StrReplace(speedText, "x", "")))
    if Trim(SeqHotkeyEdit.Value) != ""
        seqData["hotkey"] := Trim(SeqHotkeyEdit.Value)
    if Trim(SeqHotstringEdit.Value) != ""
        seqData["hotstring"] := Trim(SeqHotstringEdit.Value)
    return seqData
}

ScheduleWorkflowAutosave(*) {
    global g_LoadingWorkflow, g_WorkflowAutoSavePending
    if g_LoadingWorkflow
        return
    g_WorkflowAutoSavePending := true
    SetTimer(AutoSaveCurrentWorkflow, -650)
}

AutoSaveCurrentWorkflow() {
    global g_LoadingWorkflow, g_WorkflowAutoSavePending, g_CurrentSequenceSteps
    global g_Sequences, SeqNameEdit, WorkflowSaveStatus, g_LastWorkflowSaveError
    g_WorkflowAutoSavePending := false
    if g_LoadingWorkflow
        return

    name := Trim(SeqNameEdit.Value)
    if name = ""
        return
    if g_CurrentSequenceSteps.Length = 0 && !g_Sequences.Has(name)
        return

    g_Sequences[name] := BuildCurrentWorkflowData()
    if SaveSequences() {
        RegisterSequenceTriggers(name)
        RefreshSeqLV()
        WorkflowSaveStatus.Text := "Autosaved: " . name . " at " . FormatTime(, "h:mm:ss tt")
        WorkflowSaveStatus.SetFont("c008000")
    } else {
        WorkflowSaveStatus.Text := "Autosave failed: " . g_LastWorkflowSaveError
        WorkflowSaveStatus.SetFont("cRed")
    }
}

SaveSeq(*) {
    global g_CurrentSequenceSteps, g_Sequences, SeqNameEdit, SpeedDD, SeqHotkeyEdit, SeqHotstringEdit
    saved := MainGui.Submit(false)
    if saved.SeqName = "" {
        MsgBoxTop("Enter name!", "Required")
        return
    }
    if g_CurrentSequenceSteps.Length = 0 {
        MsgBoxTop("Add steps!", "Empty")
        return
    }
    steps := CloneWorkflowSteps(g_CurrentSequenceSteps)
    speedText := SpeedDD.Text
    seqData := BuildCurrentWorkflowData()
    g_Sequences[saved.SeqName] := seqData

    ; Persist before clearing the editor. A failed save leaves the work visible
    ; and the database transaction keeps the previous saved copy intact.
    if !SaveSequences(true) {
        WorkflowSaveStatus.Text := "Save failed - workflow remains open for retry."
        WorkflowSaveStatus.SetFont("cRed")
        return
    }

    ; Register hotkey/hotstring
    RegisterSequenceTriggers(saved.SeqName)

    RefreshSeqLV()
    g_CurrentSequenceSteps := []
    RefreshStepsLV()
    SeqNameEdit.Value := ""
    SeqHotkeyEdit.Value := ""
    SeqHotstringEdit.Value := ""
    StatusBar.SetText("Saved: " . saved.SeqName . " @ " . speedText)
    WorkflowSaveStatus.Text := "Saved: " . saved.SeqName
    WorkflowSaveStatus.SetFont("c008000")

    triggerInfo := ""
    if saved.SeqHotkey != ""
        triggerInfo .= "`nHotkey: " . saved.SeqHotkey
    if saved.SeqHotstring != ""
        triggerInfo .= "`nHotstring: " . saved.SeqHotstring

    ShowNotificationBasic("Sequence Saved", saved.SeqName . " with " . steps.Length . " steps @ " . speedText . triggerInfo, 3000, "success")
}

RefreshSeqLV() {
    global g_Sequences, SeqLV
    SeqLV.Delete()
    for name, seq in g_Sequences {
        speed := seq.Has("speed") ? seq["speed"] . "x" : "1x"
        hotkey := seq.Has("hotkey") ? seq["hotkey"] : ""
        hotstring := seq.Has("hotstring") ? seq["hotstring"] : ""
        SeqLV.Add(, name, seq["steps"].Length, speed, hotkey, hotstring)
    }
    try RefreshSpoolWorkflowChoices()
}

LoadSeq(*) {
    global g_Sequences, g_CurrentSequenceSteps, SeqLV, SeqNameEdit, SeqHotkeyEdit, SeqHotstringEdit
    row := SeqLV.GetNext(0, "Focused")
    if row = 0
        return
    name := SeqLV.GetText(row, 1)
    if !g_Sequences.Has(name)
        return
    LoadWorkflowByName(name)
}

LoadWorkflowByName(name) {
    global g_Sequences, g_CurrentSequenceSteps, SeqNameEdit, SeqHotkeyEdit, SeqHotstringEdit, g_LoadingWorkflow, WorkflowSaveStatus
    if !g_Sequences.Has(name)
        return false
    g_LoadingWorkflow := true
    try {
        g_CurrentSequenceSteps := CloneWorkflowSteps(g_Sequences[name]["steps"])
        for step in g_CurrentSequenceSteps
            if !step.Has("enabled")
                step["enabled"] := true
        SeqNameEdit.Value := name
        speed := g_Sequences[name].Has("speed") ? g_Sequences[name]["speed"] : 1.0
        SetSpeedDropdown(speed)
        seq := g_Sequences[name]
        SeqHotkeyEdit.Value := seq.Has("hotkey") ? seq["hotkey"] : ""
        SeqHotstringEdit.Value := seq.Has("hotstring") ? seq["hotstring"] : ""
        RefreshStepsLV()
        WorkflowSaveStatus.Text := "Loaded: " . name . " (changes autosave)"
        WorkflowSaveStatus.SetFont("cBlue")
    } finally {
        g_LoadingWorkflow := false
    }
    return true
}


; ═══════════════════════════════════════════════════════════════════════════════
; HOTKEY/HOTSTRING TRIGGER REGISTRATION
; ═══════════════════════════════════════════════════════════════════════════════

MawEncode(value) {
    value := String(value)
    value := StrReplace(value, "%", "%25")
    value := StrReplace(value, "|", "%7C")
    value := StrReplace(value, "`r", "%0D")
    value := StrReplace(value, "`n", "%0A")
    value := StrReplace(value, "=", "%3D")
    return value
}

MawDecode(value) {
    value := StrReplace(value, "%7C", "|")
    value := StrReplace(value, "%0D", "`r")
    value := StrReplace(value, "%0A", "`n")
    value := StrReplace(value, "%3D", "=")
    value := StrReplace(value, "%25", "%")
    return value
}

ExportWorkflow(*) {
    global SeqNameEdit, g_CurrentSequenceSteps
    name := Trim(SeqNameEdit.Value)
    if name = "" {
        MsgBox("Enter a workflow name in Step 1 before exporting.", "Export Workflow", "Icon!")
        return false
    }
    if g_CurrentSequenceSteps.Length = 0 {
        MsgBox("Add at least one step before exporting.", "Export Workflow", "Icon!")
        return false
    }
    return ExportWorkflowData(name, BuildCurrentWorkflowData())
}

ExportWorkflowFromMain(*) {
    global SeqLV
    row := SeqLV.GetNext(0, "Focused")
    if row > 0
        return ExportWorkflowByName(SeqLV.GetText(row, 1))
    return ExportWorkflow()
}

ExportWorkflowByName(name) {
    global g_Sequences
    if !g_Sequences.Has(name)
        return false
    return ExportWorkflowData(name, g_Sequences[name])
}

ExportWorkflowData(name, seq) {
    selectedFile := FileSelect("S", name . ".maw", "Export Workflow", "Workflow Files (*.maw)")
    if selectedFile = ""
        return false
    if !RegExMatch(selectedFile, "i)\.maw$")
        selectedFile .= ".maw"

    output := "[WORKFLOW]`r`n"
    output .= "format=2`r`n"
    output .= "name=" . MawEncode(name) . "`r`n"
    output .= "speed=" . (seq.Has("speed") ? seq["speed"] : 1.0) . "`r`n"
    output .= "hotkey=" . MawEncode(seq.Has("hotkey") ? seq["hotkey"] : "") . "`r`n"
    output .= "hotstring=" . MawEncode(seq.Has("hotstring") ? seq["hotstring"] : "") . "`r`n"
    output .= "`r`n[STEPS]`r`n"

    for index, step in seq["steps"] {
        fs := step.Has("failsafe") ? NormalizeStepFailsafe(step["failsafe"]) : Map()
        fsText := fs.Count > 0 ? SerializeFailsafe(fs) : ""
        output .= index . "|"
            . MawEncode(step.Has("action") ? step["action"] : "") . "|"
            . MawEncode(step.Has("target") ? step["target"] : "") . "|"
            . MawEncode(step.Has("param") ? step["param"] : "") . "|"
            . (step.Has("enabled") ? Integer(step["enabled"]) : 1) . "|"
            . MawEncode(fsText) . "|"
            . MawEncode(step.Has("qualPattern") ? step["qualPattern"] : "") . "|"
            . MawEncode(step.Has("qualWindow") ? step["qualWindow"] : "") . "`r`n"
    }
    output .= "`r`n[END]`r`n"

    try {
        if FileExist(selectedFile)
            FileDelete(selectedFile)
        FileAppend(output, selectedFile, "UTF-8")
        ShowStatus("Exported workflow: " . name, "ok")
        MsgBox("Workflow exported successfully.`n`n" . selectedFile, "Export Complete", "Iconi")
        return true
    } catch as err {
        LogErrorToFile(err, "caught", "Export workflow " . name)
        MsgBox("Workflow export failed.`n`n" . err.Message, "Export Failed", "Iconx")
        return false
    }
}

ShowMawWriter(*) {
    global MainGui, SeqNameEdit, SpeedDD, SeqHotkeyEdit, SeqHotstringEdit, g_CurrentSequenceSteps
    writer := Gui("+Owner" . MainGui.Hwnd . " +Resize +MinSize820x600", "Build / Write Portable .maw Workflow")
    writer.SetFont("s9", "Segoe UI")
    state := Map("steps", CloneWorkflowSteps(g_CurrentSequenceSteps))

    writer.Add("GroupBox", "x12 y10 w895 h75", "1. Portable Workflow Metadata")
    writer.Add("Text", "x25 y35", "Name:")
    nameEdit := writer.Add("Edit", "x70 y32 w200", Trim(SeqNameEdit.Value))
    writer.Add("Text", "x285 y35", "Speed:")
    writerSpeedDD := writer.Add("DropDownList", "x330 y32 w75", ["0.25x", "0.5x", "0.75x", "1x", "1.5x", "2x", "3x"])
    writerSpeedDD.Text := SpeedDD.Text != "" ? SpeedDD.Text : "1x"
    writer.Add("Text", "x420 y35", "Hotkey:")
    hotkeyEdit := writer.Add("Edit", "x470 y32 w100", SeqHotkeyEdit.Value)
    writer.Add("Text", "x585 y35", "Hotstring:")
    hotstringEdit := writer.Add("Edit", "x650 y32 w110", SeqHotstringEdit.Value)
    writer.Add("Text", "x25 y62 w850 cGray", "This builder writes every action supported by v8. The .maw file remains separate until you import it or send it to the editor.")

    writer.Add("GroupBox", "x12 y95 w895 h170", "2. Add or Update a Step")
    writer.Add("Text", "x25 y120", "Action:")
    writerActionDD := writer.Add("DropDownList", "x80 y117 w190", GetWorkflowActionNames())
    writerActionDD.Choose(1)
    targetLabel := writer.Add("Text", "x25 y155 w240", "Position:")
    targetEdit := writer.Add("Edit", "x25 y174 w270")
    paramLabel := writer.Add("Text", "x310 y155 w270", "Click count:")
    writerParamEdit := writer.Add("Edit", "x310 y174 w280")
    enabledCheck := writer.Add("CheckBox", "x25 y211 Checked", "Step enabled")
    addBtn := writer.Add("Button", "x310 y208 w90 h28 Default", "Add Step")
    updateBtn := writer.Add("Button", "x410 y208 w120 h28", "Update Selected")
    clearBtn := writer.Add("Button", "x540 y208 w50 h28", "Clear")
    helpEdit := writer.Add("Edit", "x610 y116 w282 h125 ReadOnly Multi VScroll")

    writer.Add("GroupBox", "x12 y275 w895 h255", "3. Confirm Execution Order")
    stepLV := writer.Add("ListView", "x25 y298 w760 h215 Grid NoSortHdr", ["#", "On", "Action", "Target", "Parameter"])
    stepLV.ModifyCol(1, 35)
    stepLV.ModifyCol(2, 40)
    stepLV.ModifyCol(3, 165)
    stepLV.ModifyCol(4, 210)
    stepLV.ModifyCol(5, 300)
    writer.Add("Button", "x798 y298 w90 h26", "Move Up").OnEvent("Click", (*) => MawWriterMoveStep(state, stepLV, -1))
    writer.Add("Button", "x798 y330 w90 h26", "Move Down").OnEvent("Click", (*) => MawWriterMoveStep(state, stepLV, 1))
    writer.Add("Button", "x798 y372 w90 h26", "Edit Step").OnEvent("Click", (*) => MawWriterLoadSelectedStep(state, stepLV, writerActionDD, targetLabel, targetEdit, paramLabel, writerParamEdit, enabledCheck, helpEdit))
    writer.Add("Button", "x798 y404 w90 h26", "Delete").OnEvent("Click", (*) => MawWriterDeleteStep(state, stepLV))
    writer.Add("Button", "x798 y446 w90 h26", "Validate All").OnEvent("Click", (*) => MawWriterValidateAll(state))

    writer.Add("GroupBox", "x12 y540 w895 h62", "4. Write, Open, or Continue Editing")
    writer.Add("Button", "x25 y558 w100 h30", "Open .maw").OnEvent("Click", (*) => MawWriterOpenFile(state, stepLV, nameEdit, writerSpeedDD, hotkeyEdit, hotstringEdit))
    writer.Add("Button", "x135 y558 w110 h30 cGreen", "Save .maw").OnEvent("Click", (*) => MawWriterSaveFile(state, nameEdit, writerSpeedDD, hotkeyEdit, hotstringEdit))
    writer.Add("Button", "x255 y558 w130 h30 cBlue", "Send to Editor").OnEvent("Click", (*) => MawWriterSendToEditor(state, nameEdit, writerSpeedDD, hotkeyEdit, hotstringEdit, writer))
    writer.Add("Button", "x397 y558 w110 h30", "Action Guide").OnEvent("Click", ShowInstructionsFile)
    writer.Add("Button", "x797 y558 w90 h30", "Close").OnEvent("Click", (*) => writer.Destroy())

    writerActionDD.OnEvent("Change", (*) => MawWriterActionChanged(writerActionDD, targetLabel, targetEdit, paramLabel, writerParamEdit, helpEdit))
    addBtn.OnEvent("Click", (*) => MawWriterAddStep(state, stepLV, writerActionDD, targetEdit, writerParamEdit, enabledCheck))
    updateBtn.OnEvent("Click", (*) => MawWriterUpdateStep(state, stepLV, writerActionDD, targetEdit, writerParamEdit, enabledCheck))
    clearBtn.OnEvent("Click", (*) => (targetEdit.Value := "", writerParamEdit.Value := "", enabledCheck.Value := 1))
    stepLV.OnEvent("DoubleClick", (*) => MawWriterLoadSelectedStep(state, stepLV, writerActionDD, targetLabel, targetEdit, paramLabel, writerParamEdit, enabledCheck, helpEdit))
    MawWriterActionChanged(writerActionDD, targetLabel, targetEdit, paramLabel, writerParamEdit, helpEdit)
    MawWriterRefreshLV(state, stepLV)
    writer.Show("w920 h615")
}

MawWriterActionChanged(actionDD, targetLabel, targetEdit, paramLabel, paramEdit, helpEdit) {
    spec := GetWorkflowActionSpec(actionDD.Text)
    targetLabel.Text := spec["targetUsed"] ? spec["targetLabel"] . " — " . spec["targetHint"] : "Target — not used"
    paramLabel.Text := spec["paramUsed"] ? spec["paramLabel"] . " — " . spec["paramHint"] : "Parameter — not used"
    targetEdit.Enabled := spec["targetUsed"]
    paramEdit.Enabled := spec["paramUsed"]
    if !spec["targetUsed"]
        targetEdit.Value := ""
    if !spec["paramUsed"]
        paramEdit.Value := ""
    helpEdit.Value := actionDD.Text . "`r`n`r`n" . spec["help"] . (spec["example"] != "" ? "`r`n`r`nExample: " . spec["example"] : "")
}

MawWriterRefreshLV(state, lv, selectRow := 0) {
    lv.Delete()
    for index, step in state["steps"]
        lv.Add(, index, step.Has("enabled") && !step["enabled"] ? "No" : "Yes", step["action"], step["target"], step["param"])
    if selectRow > 0 && selectRow <= state["steps"].Length
        lv.Modify(selectRow, "Select Focus Vis")
}

MawWriterSelectedRow(lv) {
    return lv.GetNext(0, "Focused")
}

MawWriterAddStep(state, lv, actionDD, targetEdit, paramEdit, enabledCheck) {
    action := actionDD.Text
    target := targetEdit.Value
    param := paramEdit.Value
    if !ShowParameterValidation(action, target, param)
        return
    state["steps"].Push(Map("action", action, "target", target, "param", param, "enabled", enabledCheck.Value = 1))
    MawWriterRefreshLV(state, lv, state["steps"].Length)
}

MawWriterUpdateStep(state, lv, actionDD, targetEdit, paramEdit, enabledCheck) {
    row := MawWriterSelectedRow(lv)
    if row = 0 || row > state["steps"].Length {
        MsgBox("Select a step to update.", "MAW Writer", "Icon!")
        return
    }
    action := actionDD.Text
    if !ShowParameterValidation(action, targetEdit.Value, paramEdit.Value)
        return
    oldStep := state["steps"][row]
    oldStep["action"] := action
    oldStep["target"] := targetEdit.Value
    oldStep["param"] := paramEdit.Value
    oldStep["enabled"] := enabledCheck.Value = 1
    MawWriterRefreshLV(state, lv, row)
}

MawWriterLoadSelectedStep(state, lv, actionDD, targetLabel, targetEdit, paramLabel, paramEdit, enabledCheck, helpEdit) {
    row := MawWriterSelectedRow(lv)
    if row = 0 || row > state["steps"].Length
        return
    step := state["steps"][row]
    DDL_FindAndSelect(actionDD, step["action"])
    MawWriterActionChanged(actionDD, targetLabel, targetEdit, paramLabel, paramEdit, helpEdit)
    targetEdit.Value := step["target"]
    paramEdit.Value := step["param"]
    enabledCheck.Value := step.Has("enabled") ? step["enabled"] : 1
}

MawWriterDeleteStep(state, lv) {
    row := MawWriterSelectedRow(lv)
    if row = 0 || row > state["steps"].Length
        return
    state["steps"].RemoveAt(row)
    MawWriterRefreshLV(state, lv, Min(row, state["steps"].Length))
}

MawWriterMoveStep(state, lv, direction) {
    row := MawWriterSelectedRow(lv)
    destination := row + direction
    if row = 0 || destination < 1 || destination > state["steps"].Length
        return
    temp := state["steps"][row]
    state["steps"][row] := state["steps"][destination]
    state["steps"][destination] := temp
    MawWriterRefreshLV(state, lv, destination)
}

MawWriterValidateAll(state) {
    errors := []
    for index, step in state["steps"] {
        for message in ValidateStepParameters(step["action"], step["target"], step["param"])
            errors.Push("Step " . index . " (" . step["action"] . "): " . message)
    }
    if errors.Length = 0 {
        MsgBox("All " . state["steps"].Length . " steps passed validation.", "MAW Validation", "Iconi")
        return true
    }
    report := ""
    for message in errors
        report .= "• " . message . "`n"
    MsgBox(report, "MAW Validation Issues", "Icon!")
    return false
}

MawWriterBuildSequence(state, speedDD, hotkeyEdit, hotstringEdit) {
    speedText := StrReplace(speedDD.Text != "" ? speedDD.Text : "1x", "x", "")
    seq := Map("steps", CloneWorkflowSteps(state["steps"]), "speed", IsNumber(speedText) ? Float(speedText) : 1.0)
    if Trim(hotkeyEdit.Value) != ""
        seq["hotkey"] := Trim(hotkeyEdit.Value)
    if Trim(hotstringEdit.Value) != ""
        seq["hotstring"] := Trim(hotstringEdit.Value)
    return seq
}

MawWriterSaveFile(state, nameEdit, speedDD, hotkeyEdit, hotstringEdit) {
    name := Trim(nameEdit.Value)
    if name = "" || state["steps"].Length = 0 {
        MsgBox("Enter a workflow name and add at least one step.", "MAW Writer", "Icon!")
        return false
    }
    return ExportWorkflowData(name, MawWriterBuildSequence(state, speedDD, hotkeyEdit, hotstringEdit))
}

MawWriterSendToEditor(state, nameEdit, writerSpeedControl, hotkeyEdit, hotstringEdit, writer) {
    global g_CurrentSequenceSteps, SeqNameEdit, SpeedDD, SeqHotkeyEdit, SeqHotstringEdit, g_LoadingWorkflow, WorkflowSaveStatus
    name := Trim(nameEdit.Value)
    if name = "" || state["steps"].Length = 0 {
        MsgBox("Enter a workflow name and add at least one step.", "MAW Writer", "Icon!")
        return
    }
    g_LoadingWorkflow := true
    try {
        g_CurrentSequenceSteps := CloneWorkflowSteps(state["steps"])
        SeqNameEdit.Value := name
        SetSpeedDropdown(Float(StrReplace(writerSpeedControl.Text, "x", "")))
        SeqHotkeyEdit.Value := hotkeyEdit.Value
        SeqHotstringEdit.Value := hotstringEdit.Value
        RefreshStepsLV()
        WorkflowSaveStatus.Text := "Loaded from .maw writer: " . name . " — click Save Now to add it to the library."
        WorkflowSaveStatus.SetFont("cBlue")
    } finally {
        g_LoadingWorkflow := false
    }
    writer.Destroy()
    MainGui.Show()
}

MawWriterOpenFile(state, lv, nameEdit, speedDD, hotkeyEdit, hotstringEdit) {
    selectedFile := FileSelect(, , "Open Portable Workflow", "Workflow Files (*.maw)")
    if selectedFile = ""
        return
    if !ReadMawWorkflowFile(selectedFile, &workflowName, &seqData, &errorMessage) {
        MsgBox(errorMessage, "Open .maw Failed", "Iconx")
        return
    }
    state["steps"] := CloneWorkflowSteps(seqData["steps"])
    nameEdit.Value := workflowName
    speedDD.Text := (seqData.Has("speed") ? seqData["speed"] : 1.0) . "x"
    hotkeyEdit.Value := seqData.Has("hotkey") ? seqData["hotkey"] : ""
    hotstringEdit.Value := seqData.Has("hotstring") ? seqData["hotstring"] : ""
    MawWriterRefreshLV(state, lv)
}

ReadMawWorkflowFile(selectedFile, &workflowName, &seqData, &errorMessage) {
    workflowName := ""
    seqData := Map()
    errorMessage := ""
    try content := FileRead(selectedFile, "UTF-8")
    catch as err {
        errorMessage := "Could not read the selected file.`n`n" . err.Message
        return false
    }
    section := ""
    formatVersion := 1
    speed := 1.0
    hotkey := ""
    hotstring := ""
    steps := []
    for rawLine in StrSplit(content, "`n") {
        rawLine := StrReplace(rawLine, "`r")
        marker := Trim(rawLine)
        if marker = "" || SubStr(marker, 1, 1) = ";"
            continue
        if marker = "[WORKFLOW]" {
            section := "workflow"
            continue
        } else if marker = "[STEPS]" {
            section := "steps"
            continue
        } else if marker = "[END]" {
            break
        }
        if section = "workflow" {
            equalsPos := InStr(rawLine, "=")
            if !equalsPos
                continue
            key := Trim(SubStr(rawLine, 1, equalsPos - 1))
            value := SubStr(rawLine, equalsPos + 1)
            if key = "format"
                formatVersion := IsNumber(value) ? Integer(value) : 1
            else if key = "name"
                workflowName := formatVersion >= 2 ? MawDecode(value) : value
            else if key = "speed"
                speed := IsNumber(value) ? Float(value) : 1.0
            else if key = "hotkey"
                hotkey := formatVersion >= 2 ? MawDecode(value) : value
            else if key = "hotstring"
                hotstring := formatVersion >= 2 ? MawDecode(value) : value
        } else if section = "steps" {
            parts := StrSplit(rawLine, "|")
            if parts.Length < 4
                continue
            step := Map(
                "action", formatVersion >= 2 ? MawDecode(parts[2]) : parts[2],
                "target", formatVersion >= 2 ? MawDecode(parts[3]) : parts[3],
                "param", formatVersion >= 2 ? MawDecode(parts[4]) : parts[4],
                "enabled", parts.Length >= 5 && IsNumber(parts[5]) ? Integer(parts[5]) != 0 : true
            )
            if formatVersion >= 2 && parts.Length >= 6 {
                fsText := MawDecode(parts[6])
                if fsText != ""
                    step["failsafe"] := DeserializeFailsafe(fsText)
                if parts.Length >= 7 && MawDecode(parts[7]) != ""
                    step["qualPattern"] := MawDecode(parts[7])
                if parts.Length >= 8 && MawDecode(parts[8]) != ""
                    step["qualWindow"] := MawDecode(parts[8])
            }
            steps.Push(step)
        }
    }
    workflowName := Trim(workflowName)
    if workflowName = "" || steps.Length = 0 {
        errorMessage := "The file does not contain a workflow name and at least one valid step."
        return false
    }
    seqData := Map("steps", steps, "speed", speed)
    if hotkey != ""
        seqData["hotkey"] := hotkey
    if hotstring != ""
        seqData["hotstring"] := hotstring
    return true
}

ImportWorkflow(*) {
    global g_Sequences
    selectedFile := FileSelect(, , "Import Workflow", "Workflow Files (*.maw)")
    if selectedFile = ""
        return ""

    try content := FileRead(selectedFile, "UTF-8")
    catch as err {
        LogErrorToFile(err, "caught", "Read imported workflow")
        MsgBox("Could not read the selected workflow.`n`n" . err.Message, "Import Failed", "Iconx")
        return ""
    }

    section := ""
    formatVersion := 1
    workflowName := ""
    speed := 1.0
    hotkey := ""
    hotstring := ""
    steps := []

    for rawLine in StrSplit(content, "`n") {
        rawLine := StrReplace(rawLine, "`r")
        marker := Trim(rawLine)
        if marker = "" || SubStr(marker, 1, 1) = ";"
            continue
        if marker = "[WORKFLOW]" {
            section := "workflow"
            continue
        }
        if marker = "[STEPS]" {
            section := "steps"
            continue
        }
        if marker = "[END]"
            break

        if section = "workflow" {
            equalsPos := InStr(rawLine, "=")
            if !equalsPos
                continue
            key := Trim(SubStr(rawLine, 1, equalsPos - 1))
            value := SubStr(rawLine, equalsPos + 1)
            if key = "format"
                formatVersion := IsNumber(value) ? Integer(value) : 1
            else if key = "name"
                workflowName := formatVersion >= 2 ? MawDecode(value) : value
            else if key = "speed"
                speed := IsNumber(value) ? Float(value) : 1.0
            else if key = "hotkey"
                hotkey := formatVersion >= 2 ? MawDecode(value) : value
            else if key = "hotstring"
                hotstring := formatVersion >= 2 ? MawDecode(value) : value
        } else if section = "steps" {
            parts := StrSplit(rawLine, "|")
            if parts.Length < 4
                continue
            step := Map(
                "action", formatVersion >= 2 ? MawDecode(parts[2]) : parts[2],
                "target", formatVersion >= 2 ? MawDecode(parts[3]) : parts[3],
                "param", formatVersion >= 2 ? MawDecode(parts[4]) : parts[4],
                "enabled", parts.Length >= 5 && IsNumber(parts[5]) ? Integer(parts[5]) != 0 : true
            )
            if formatVersion >= 2 && parts.Length >= 6 {
                fsText := MawDecode(parts[6])
                if fsText != ""
                    step["failsafe"] := DeserializeFailsafe(fsText)
                if parts.Length >= 7 && MawDecode(parts[7]) != ""
                    step["qualPattern"] := MawDecode(parts[7])
                if parts.Length >= 8 && MawDecode(parts[8]) != ""
                    step["qualWindow"] := MawDecode(parts[8])
            } else {
                step["failsafe"] := Map()
            }
            steps.Push(step)
        }
    }

    if Trim(workflowName) = "" || steps.Length = 0 {
        MsgBox("This is not a valid .maw workflow: a name and at least one step are required.", "Import Failed", "Icon!")
        return ""
    }
    workflowName := Trim(workflowName)
    existed := g_Sequences.Has(workflowName)
    oldSequence := existed ? g_Sequences[workflowName] : ""
    if existed && MsgBox("Workflow '" . workflowName . "' already exists.`n`nOverwrite it?", "Workflow Exists", "YesNo Icon!") != "Yes"
        return ""

    seqData := Map("steps", steps, "speed", speed)
    if hotkey != ""
        seqData["hotkey"] := hotkey
    if hotstring != ""
        seqData["hotstring"] := hotstring
    if existed
        UnregisterSequenceTriggers(workflowName)
    g_Sequences[workflowName] := seqData

    if !SaveSequences(true) {
        if existed
            g_Sequences[workflowName] := oldSequence
        else
            g_Sequences.Delete(workflowName)
        if existed
            RegisterSequenceTriggers(workflowName)
        return ""
    }

    RegisterSequenceTriggers(workflowName)
    RefreshSeqLV()
    RefreshHKDropdowns()
    LoadWorkflowByName(workflowName)
    ShowStatus("Imported workflow: " . workflowName, "ok")
    MsgBox("Workflow imported successfully.`n`nName: " . workflowName . "`nSteps: " . steps.Length, "Import Complete", "Iconi")
    return workflowName
}

WorkflowManagerImport(lv) {
    importedName := ImportWorkflow()
    if importedName != ""
        RefreshWorkflowManagerLV(lv)
}

WorkflowManagerExport(lv) {
    name := WorkflowManagerSelectedName(lv)
    if name = "" {
        MsgBox("Select a workflow to export.", "Export Workflow", "Icon!")
        return
    }
    ExportWorkflowByName(name)
}

ShowWorkflowManager(*) {
    manager := Gui("+Resize +MinSize900x440", "Saved Workflow Manager")
    manager.SetFont("s9", "Segoe UI")
    manager.Add("Text", "x15 y12 w700", "All workflows - scroll the list, double-click to load, or use the buttons below.")
    managerLV := manager.Add("ListView", "x15 y35 w870 h485 Grid NoSortHdr", ["Name", "Steps", "Speed", "Hotkey", "Hotstring", "First action"])
    managerLV.ModifyCol(1, 300)
    managerLV.ModifyCol(2, 65)
    managerLV.ModifyCol(3, 70)
    managerLV.ModifyCol(4, 100)
    managerLV.ModifyCol(5, 110)
    managerLV.ModifyCol(6, 190)
    managerLV.Opt("-LV0x2000 +0x00200000 +LV0x20")

    loadBtn := manager.Add("Button", "x15 y530 w80 h28 Default", "Load/Edit")
    runBtn := manager.Add("Button", "x105 y530 w70 h28", "Run")
    simBtn := manager.Add("Button", "x185 y530 w80 h28", "Simulate")
    deleteBtn := manager.Add("Button", "x275 y530 w70 h28", "Delete")
    refreshBtn := manager.Add("Button", "x355 y530 w70 h28", "Refresh")
    guideBtn := manager.Add("Button", "x435 y530 w90 h28", "Action Guide")
    importBtn := manager.Add("Button", "x535 y530 w80 h28", "Import .maw")
    exportBtn := manager.Add("Button", "x625 y530 w80 h28", "Export .maw")
    closeBtn := manager.Add("Button", "x805 y530 w80 h28", "Close")

    loadBtn.OnEvent("Click", (*) => WorkflowManagerLoad(manager, managerLV))
    runBtn.OnEvent("Click", (*) => WorkflowManagerRun(managerLV, false))
    simBtn.OnEvent("Click", (*) => WorkflowManagerRun(managerLV, true))
    deleteBtn.OnEvent("Click", (*) => WorkflowManagerDelete(managerLV))
    refreshBtn.OnEvent("Click", (*) => RefreshWorkflowManagerLV(managerLV))
    guideBtn.OnEvent("Click", ShowInstructionsFile)
    importBtn.OnEvent("Click", (*) => WorkflowManagerImport(managerLV))
    exportBtn.OnEvent("Click", (*) => WorkflowManagerExport(managerLV))
    closeBtn.OnEvent("Click", (*) => manager.Destroy())
    managerLV.OnEvent("DoubleClick", (*) => WorkflowManagerLoad(manager, managerLV))
    manager.OnEvent("Size", WorkflowManagerResize.Bind(managerLV, loadBtn, runBtn, simBtn, deleteBtn, refreshBtn, guideBtn, importBtn, exportBtn, closeBtn))

    RefreshWorkflowManagerLV(managerLV)
    manager.Show("w900 h575")
}

WorkflowManagerResize(lv, loadBtn, runBtn, simBtn, deleteBtn, refreshBtn, guideBtn, importBtn, exportBtn, closeBtn, gui, minMax, w, h) {
    if minMax = -1
        return
    lv.Move(, , Max(650, w - 30), Max(300, h - 90))
    buttonY := h - 38
    for btn in [loadBtn, runBtn, simBtn, deleteBtn, refreshBtn, guideBtn, importBtn, exportBtn]
        btn.Move(, buttonY)
    closeBtn.Move(w - 95, buttonY)
}

RefreshWorkflowManagerLV(lv) {
    global g_Sequences
    lv.Delete()
    for name, seq in g_Sequences {
        speed := seq.Has("speed") ? seq["speed"] . "x" : "1x"
        hotkey := seq.Has("hotkey") ? seq["hotkey"] : ""
        hotstring := seq.Has("hotstring") ? seq["hotstring"] : ""
        firstAction := seq["steps"].Length > 0 ? seq["steps"][1]["action"] : "(empty)"
        lv.Add(, name, seq["steps"].Length, speed, hotkey, hotstring, firstAction)
    }
}

WorkflowManagerSelectedName(lv) {
    row := lv.GetNext(0, "Focused")
    return row > 0 ? lv.GetText(row, 1) : ""
}

WorkflowManagerLoad(manager, lv) {
    name := WorkflowManagerSelectedName(lv)
    if name = ""
        return
    if LoadWorkflowByName(name) {
        manager.Destroy()
        MainGui.Show()
    }
}

WorkflowManagerRun(lv, simulate := false) {
    global g_Sequences, g_AbortSequence
    name := WorkflowManagerSelectedName(lv)
    if name = "" || !g_Sequences.Has(name)
        return
    g_AbortSequence := false
    seq := g_Sequences[name]
    speed := seq.Has("speed") ? seq["speed"] : 1.0
    if simulate
        SimulateSequence(seq["steps"], speed)
    else
        ExecuteSequenceVerified(seq["steps"], speed)
}

WorkflowManagerDelete(lv) {
    global g_Sequences
    name := WorkflowManagerSelectedName(lv)
    if name = ""
        return
    if MsgBoxTop("Delete '" . name . "'?", "Confirm", "YesNo") != "Yes"
        return
    UnregisterSequenceTriggers(name)
    deletedSequence := g_Sequences[name]
    g_Sequences.Delete(name)
    if SaveSequences(true) {
        RefreshSeqLV()
        RefreshWorkflowManagerLV(lv)
        RefreshHKDropdowns()
    } else {
        g_Sequences[name] := deletedSequence
        RegisterSequenceTriggers(name)
        RefreshSeqLV()
        RefreshWorkflowManagerLV(lv)
    }
}


RegisterSequenceTriggers(seqName) {
    global g_Sequences, g_SequenceHotkeys, g_SequenceHotstrings

    if !g_Sequences.Has(seqName)
        return

    seq := g_Sequences[seqName]

    ; Unregister old triggers for this sequence first
    UnregisterSequenceTriggers(seqName)

    ; Register hotkey
    if seq.Has("hotkey") && seq["hotkey"] != "" {
        hk := seq["hotkey"]
        try {
            Hotkey(hk, (*) => ExecuteSequenceByHotkey(seqName))
            g_SequenceHotkeys[hk] := seqName
            g_RegisteredHotkeys.Push(hk)
        } catch as err {
            ShowNotificationBasic("Hotkey Error", "Failed to register: " . hk . "`n" . err.Message, 5000, "error")
        }
    }

    ; Register hotstring
    if seq.Has("hotstring") && seq["hotstring"] != "" {
        hs := seq["hotstring"]
        try {
            ; Hotstrings with auto-replace (backspace trigger text)
            Hotstring(hs, (*) => ExecuteSequenceByHotstring(seqName, StrLen(hs) - 2))
            g_SequenceHotstrings[hs] := seqName
            g_RegisteredHotstrings.Push(hs)
        } catch as err {
            ShowNotificationBasic("Hotstring Error", "Failed to register: " . hs . "`n" . err.Message, 5000, "error")
        }
    }
}

UnregisterSequenceTriggers(seqName) {
    global g_Sequences, g_SequenceHotkeys, g_SequenceHotstrings

    if !g_Sequences.Has(seqName)
        return

    seq := g_Sequences[seqName]

    ; Unregister hotkey
    if seq.Has("hotkey") && seq["hotkey"] != "" {
        hk := seq["hotkey"]
        try {
            Hotkey(hk, "Off")
            g_SequenceHotkeys.Delete(hk)
        }
    }

    ; Unregister hotstring
    if seq.Has("hotstring") && seq["hotstring"] != "" {
        hs := seq["hotstring"]
        try {
            Hotstring(hs, "Off")
            g_SequenceHotstrings.Delete(hs)
        }
    }
}

ExecuteSequenceByHotkey(seqName) {
    global g_Sequences

    if !g_Sequences.Has(seqName) {
        ShowStatus("Sequence not found: " . seqName, "fail")
        return
    }

    seq := g_Sequences[seqName]
    speed := seq.Has("speed") ? seq["speed"] : 1.0

    ShowStatus("Running sequence: " . seqName, "info")
    ExecuteSequenceVerified(seq["steps"], speed)
}

ExecuteSequenceByHotstring(seqName, triggerLength) {
    global g_Sequences

    ; Delete the trigger text
    if triggerLength > 0 {
        Send("{Backspace " . triggerLength . "}")
        Sleep(50)
    }

    if !g_Sequences.Has(seqName) {
        ShowStatus("Sequence not found: " . seqName, "fail")
        return
    }

    seq := g_Sequences[seqName]
    speed := seq.Has("speed") ? seq["speed"] : 1.0

    ShowStatus("Running sequence: " . seqName, "info")
    ExecuteSequenceVerified(seq["steps"], speed)
}

RegisterAllSequenceTriggers() {
    global g_Sequences

    for seqName, seq in g_Sequences {
        RegisterSequenceTriggers(seqName)
    }
}

; Helper to set speed dropdown to match value
SetSpeedDropdown(speed) {
    global SpeedDD
    speedOptions := ["0.25x", "0.5x", "0.75x", "1x", "1.5x", "2x", "3x"]
    speedValues := [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0]

    ; Find closest match
    bestIdx := 4  ; Default to 1x
    for i, v in speedValues {
        if Abs(v - speed) < 0.01 {
            bestIdx := i
            break
        }
    }
    SpeedDD.Choose(bestIdx)
}

; Get current speed multiplier from dropdown
GetSpeedMultiplier() {
    global SpeedDD
    speedText := SpeedDD.Text
    return Float(StrReplace(speedText, "x", ""))
}

DelSeq(*) {
    global g_Sequences, SeqLV
    row := SeqLV.GetNext(0, "Focused")
    if row = 0
        return
    name := SeqLV.GetText(row, 1)
    if MsgBoxTop("Delete '" . name . "'?", "Confirm", "YesNo") = "Yes" {
        ; Unregister hotkey/hotstring before deleting
        UnregisterSequenceTriggers(name)
        deletedSequence := g_Sequences[name]
        g_Sequences.Delete(name)
        if SaveSequences(true) {
            RefreshSeqLV()
            RefreshHKDropdowns()
        } else {
            g_Sequences[name] := deletedSequence
            RegisterSequenceTriggers(name)
            RefreshSeqLV()
        }
    }
}

RunSeq(*) {
    global g_Sequences, SeqLV, g_AbortSequence
    row := SeqLV.GetNext(0, "Focused")
    if row = 0
        return
    name := SeqLV.GetText(row, 1)
    if g_Sequences.Has(name) {
        g_AbortSequence := false
        speed := g_Sequences[name].Has("speed") ? g_Sequences[name]["speed"] : 1.0
        ExecuteSequenceVerified(g_Sequences[name]["steps"], speed)
    }
}

ToggleStepThrough(*) {
    global g_StepThroughMode
    saved := MainGui.Submit(false)
    g_StepThroughMode := saved.StepThroughCheck

    if g_StepThroughMode {
        ShowStatus("Step-Through Mode ON - Press Tab to advance each step", "ok")
        ShowNotificationBasic("Step-Through Mode", "Enabled: Press Tab to advance to next step`nESC to abort sequence", 3000, "info")
    } else {
        ShowStatus("Step-Through Mode OFF - Normal speed execution", "ok")
    }
}

TestSeq(*) {
    global g_CurrentSequenceSteps, g_AbortSequence
    if g_CurrentSequenceSteps.Length = 0 {
        MsgBoxTop("No steps!", "Empty")
        return
    }
    g_AbortSequence := false
    speed := GetSpeedMultiplier()
    ExecuteSequenceVerified(g_CurrentSequenceSteps, speed)
}

; Simulate current steps without executing - show tooltips at each location
SimulateSeq(*) {
    global g_CurrentSequenceSteps, g_AbortSequence
    if g_CurrentSequenceSteps.Length = 0 {
        MsgBoxTop("No steps!", "Empty")
        return
    }
    g_AbortSequence := false
    speed := GetSpeedMultiplier()
    SimulateSequence(g_CurrentSequenceSteps, speed)
}

; Simulate saved sequence
SimulateSavedSeq(*) {
    global g_Sequences, SeqLV, g_AbortSequence
    row := SeqLV.GetNext(0, "Focused")
    if row = 0
        return
    name := SeqLV.GetText(row, 1)
    if g_Sequences.Has(name) {
        g_AbortSequence := false
        speed := g_Sequences[name].Has("speed") ? g_Sequences[name]["speed"] : 1.0
        SimulateSequence(g_Sequences[name]["steps"], speed)
    }
}

; Simulate sequence execution - shows stacking tooltips without performing actions
SimulateSequence(steps, speedMultiplier := 1.0) {
    global g_Settings, g_AbortSequence, g_Coordinates, g_Patterns, g_SimulationTooltipIndex

    g_AbortSequence := false

    ; Enable ESC to abort
    try Hotkey("Escape", AbortSequenceHandler, "On")

    ; Clear any existing tooltips
    Loop 20
        ToolTip(, , , A_Index)

    g_SimulationTooltipIndex := 1

    enabled := []
    for s in steps
        if s.Has("enabled") && s["enabled"]
            enabled.Push(s)

    total := enabled.Length

    ; Base delay between steps, adjusted for speed
    baseDelay := g_Settings["ActionDelay"]
    adjustedDelay := Round(baseDelay / speedMultiplier)

    ShowStatus("SIMULATING " . total . " steps @ " . speedMultiplier . "x [ESC to abort]", "wait")

    for i, s in enabled {
        if g_AbortSequence {
            ShowStatus("SIMULATION ABORTED", "fail")
            ClearAllSimTooltips()
            try Hotkey("Escape", "Off")
            return
        }

        ; Get coordinates for this step
        coords := GetStepCoordinates(s)

        ; Build tooltip text
        tipText := "[" . i . "/" . total . "] " . s["action"]
        if s["target"] != "" && s["target"] != "(none)"
            tipText .= "`n→ " . s["target"]
        if s["param"] != ""
            tipText .= "`n  (" . s["param"] . ")"

        ; Show tooltip at the action location (stacking)
        ShowSimulationTooltip(tipText, coords["x"], coords["y"], 3000)

        ; Wait between steps
        Sleep(adjustedDelay)
    }

    ; Disable ESC hotkey
    try Hotkey("Escape", "Off")

    ShowStatus("SIMULATION COMPLETE (" . total . " steps)", "ok")

    ; Clear all tooltips after 3 seconds
    SetTimer(ClearAllSimTooltips, -3000)
}

; Show a simulation tooltip that auto-clears after duration (stacking)
ShowSimulationTooltip(text, x, y, duration := 3000) {
    global g_SimulationTooltipIndex

    ; Use tooltip index 2-20 (1 is reserved for status)
    tipIndex := g_SimulationTooltipIndex + 1
    if tipIndex > 20
        tipIndex := 2

    ; Offset slightly so tooltips don't overlap completely
    offsetX := Mod(g_SimulationTooltipIndex - 1, 5) * 10
    offsetY := (g_SimulationTooltipIndex - 1) * 18

    ToolTip(text, x + 15 + offsetX, y + 15 + offsetY, tipIndex)

    ; Schedule this specific tooltip to clear
    clearFunc := ClearSpecificTooltip.Bind(tipIndex)
    SetTimer(clearFunc, -duration)

    ; Advance index
    g_SimulationTooltipIndex++
    if g_SimulationTooltipIndex > 19
        g_SimulationTooltipIndex := 1
}

; Clear a specific tooltip by index
ClearSpecificTooltip(index) {
    ToolTip(, , , index)
}

; Clear all simulation tooltips
ClearAllSimTooltips() {
    Loop 20
        ToolTip(, , , A_Index)
}


; Get coordinates for a step (for simulation display)
GetStepCoordinates(step) {
    global g_Coordinates, g_Patterns, g_Settings

    action := step["action"]
    target := step["target"]
    param := step["param"]

    ; Default to screen center
    x := A_ScreenWidth // 2
    y := A_ScreenHeight // 2

    ; Try to get coordinates based on action type
    try {
        if InStr(action, "Click") || action = "Drag" {
            ; Coordinate-based action
            if target != "" && target != "(none)" && g_Coordinates.Has(target) {
                c := g_Coordinates[target]
                x := c["x"]
                y := c["y"]
            } else if param != "" && InStr(param, ",") {
                ; Handle drag format: "startX,startY->endX,endY"
                if InStr(param, "->") {
                    ; Extract just the start coordinates
                    startPart := Trim(SubStr(param, 1, InStr(param, "->") - 1))
                    p := StrSplit(startPart, ",")
                    if p.Length >= 2 && IsNumber(Trim(p[1])) && IsNumber(Trim(p[2])) {
                        x := Integer(Trim(p[1]))
                        y := Integer(Trim(p[2]))
                    }
                } else {
                    ; Simple "x,y" format
                    p := StrSplit(param, ",")
                    if p.Length >= 2 && IsNumber(Trim(p[1])) && IsNumber(Trim(p[2])) {
                        x := Integer(Trim(p[1]))
                        y := Integer(Trim(p[2]))
                    }
                }
            }
        } else if InStr(action, "Find &") || action = "Wait for Pattern" || action = "Wait Until Gone" {
            ; Pattern-based action - try to find pattern on screen
            patternName := StrReplace(target, "[P] ", "")
            if g_Patterns.Has(patternName) {
                code := g_Patterns[patternName]["text"]
                tolerance := g_Settings["FindTextTolerance"]
                ok := FindText(&outX, &outY, , , , , tolerance, tolerance, code)
                if ok && ok.Length > 0 {
                    x := ok[1].mx
                    y := ok[1].my
                }
            }
        } else if action = "Activate Window" || action = "Taskbar Activate" {
            ; Window/taskbar activation - show at top center
            x := A_ScreenWidth // 2
            y := 100
        } else if action = "Key Chord" || action = "Send Keys" || action = "Type Text" {
            ; Keyboard actions - show near center but offset
            x := A_ScreenWidth // 2
            y := A_ScreenHeight // 2 + 50
        } else if InStr(action, "Revolver") || InStr(action, "Clipboard") {
            ; Clipboard/revolver actions - show at mouse position
            MouseGetPos(&x, &y)
        }
    }
    ; If any error occurred, we already have screen center as default

    return Map("x", x, "y", y)
}


RefreshCoordLV() {
    global g_Coordinates, CoordLV
    CoordLV.Delete()
    for n, c in g_Coordinates
        CoordLV.Add(, n, c["x"], c["y"], c["endX"], c["endY"], c["type"])
}



; ═══════════════════════════════════════════════════════════════════════════════
; V5.1: ACTION TEMPLATES LIBRARY
; ═══════════════════════════════════════════════════════════════════════════════

InitializeActionTemplates() {
    global g_ActionTemplates

    g_ActionTemplates["OCR → Variable → Clipboard"] := [
        Map("action", "OCR Region", "target", "100,100,1000,1000", "param", "var:ocrText", "pattern", "", "window", ""),
        Map("action", "Set Clipboard", "target", "", "param", "$var.ocrText", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "OCR Complete,Text copied to clipboard", "pattern", "", "window", "")
    ]

    g_ActionTemplates["Grab OCR → Variable → Notification"] := [
        Map("action", "Grab OCR to Var", "target", "0,0," . A_ScreenWidth . "," . A_ScreenHeight, "param", "capturedText", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "OCR Captured,$var.capturedText,10", "pattern", "", "window", "")
    ]

    g_ActionTemplates["Full Screen OCR → Yellow Boxes → Notification"] := [
        Map("action", "OCR Full Screen to Var", "target", "", "param", "fullScreenOCR", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "Full Screen OCR,$var.fullScreenOCR,10", "pattern", "", "window", "")
    ]

    g_ActionTemplates["OCR Conditional Check"] := [
        Map("action", "OCR Full Screen to Var", "target", "", "param", "screenText", "pattern", "", "window", ""),
        Map("action", "If Contains", "target", "screenText", "param", "KEYWORD", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "OCR Match,KEYWORD was found,5", "pattern", "", "window", "")
    ]

    g_ActionTemplates["Clipboard Formatter"] := [
        Map("action", "Grab Clipboard", "target", "originalClipboard", "param", "", "pattern", "", "window", ""),
        Map("action", "Format Clipboard", "target", "", "param", "trim", "pattern", "", "window", ""),
        Map("action", "Prepend to Clipboard", "target", "", "param", "DOC-", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "Clipboard,Formatted clipboard is ready,3", "pattern", "", "window", "")
    ]

    g_ActionTemplates["Variable Comparison"] := [
        Map("action", "Set Variable", "target", "status", "param", "ready", "pattern", "", "window", ""),
        Map("action", "If Variable", "target", "status", "param", "=,ready", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "Condition,The status variable is ready,3", "pattern", "", "window", "")
    ]

    g_ActionTemplates["Pattern Click with Retry"] := [
        Map("action", "Wait for Pattern", "target", "MyPattern", "param", "5000", "pattern", "", "window", ""),
        Map("action", "Find & Click", "target", "MyPattern", "param", "", "pattern", "", "window", ""),
        Map("action", "Wait", "target", "", "param", "500", "pattern", "", "window", "")
    ]

    g_ActionTemplates["Data Entry (OCR + Type)"] := [
        Map("action", "Click", "target", "FieldStart", "param", "1", "pattern", "", "window", ""),
        Map("action", "Grab OCR to Var", "target", "100,100,500,200", "param", "fieldValue", "pattern", "", "window", ""),
        Map("action", "Use Var Paste", "target", "", "param", "$var.fieldValue", "pattern", "", "window", ""),
        Map("action", "Send Keys", "target", "", "param", "{Tab}", "pattern", "", "window", "")
    ]

    g_ActionTemplates["Debug Step-by-Step"] := [
        Map("action", "Show Notification", "target", "", "param", "Debug,Starting workflow...", "pattern", "", "window", ""),
        Map("action", "Wait", "target", "", "param", "1000", "pattern", "", "window", ""),
        Map("action", "Show Notification", "target", "", "param", "Debug,Step 1 complete", "pattern", "", "window", "")
    ]

    ; v8 guided-loop template: repeat work, detect popups with loop-top memory.
    g_ActionTemplates["Loop with Popup Detection"] := [
        Map("action", "Loop Start", "target", "", "param", "count=10; var=i", "pattern", "", "window", ""),
        Map("action", "Popup Detect", "target", "", "param", "region=0,0,800,600; sensitivity=medium; on=break; mode=now; timeout=5000; var=popupChanged", "pattern", "", "window", ""),
        Map("action", "Click", "target", "demo:single", "param", "1", "pattern", "", "window", ""),
        Map("action", "Wait", "target", "", "param", "500", "pattern", "", "window", ""),
        Map("action", "Loop End", "target", "", "param", "", "pattern", "", "window", "")
    ]
}

ShowTemplateLibrary(*) {
    global g_ActionTemplates, MainGui

    templateGui := Gui("+Owner" . MainGui.Hwnd, "Action Templates Library")
    templateGui.SetFont("s9", "Segoe UI")

    templateGui.Add("Text", "x10 y10", "Select a pre-built workflow template to insert:")

    templateLV := templateGui.Add("ListView", "x10 y35 w600 h300", ["Template Name", "Steps", "Description"])
    templateLV.ModifyCol(1, 250)
    templateLV.ModifyCol(2, 60)
    templateLV.ModifyCol(3, 270)

    for name, steps in g_ActionTemplates {
        desc := GetTemplateDescription(name)
        templateLV.Add("", name, steps.Length, desc)
    }

    templateGui.Add("Button", "x10 y345 w150 h30", "Insert Template").OnEvent("Click", InsertSelectedTemplate)
    templateGui.Add("Button", "x170 y345 w150 h30", "Preview Steps").OnEvent("Click", PreviewTemplate)
    templateGui.Add("Button", "x330 y345 w150 h30", "Close").OnEvent("Click", (*) => templateGui.Destroy())

    InsertSelectedTemplate(*) {
        row := templateLV.GetNext()
        if !row {
            MsgBox("Please select a template")
            return
        }

        templateName := templateLV.GetText(row, 1)
        InsertTemplate(templateName)
        templateGui.Destroy()
    }

    PreviewTemplate(*) {
        row := templateLV.GetNext()
        if !row {
            MsgBox("Please select a template")
            return
        }

        templateName := templateLV.GetText(row, 1)
        steps := g_ActionTemplates[templateName]

        preview := "Template: " . templateName . "`n`nSteps:`n"
        for i, step in steps {
            preview .= i . ". " . step["action"]
            if step["target"] != ""
                preview .= " → " . step["target"]
            if step["param"] != ""
                preview .= " (" . step["param"] . ")"
            preview .= "`n"
        }

        MsgBox(preview, "Template Preview", "Iconi")
    }

    templateGui.Show("w620 h390")
}

GetTemplateDescription(name) {
    descriptions := Map()
    descriptions["OCR → Variable → Clipboard"] := "Capture text via OCR, store in variable, copy to clipboard"
    descriptions["Grab OCR → Variable → Notification"] := "Capture a full-screen OCR variable and display its value"
    descriptions["Full Screen OCR → Yellow Boxes → Notification"] := "OCR the full screen, box every word in yellow, then display the captured variable"
    descriptions["Pattern Click with Retry"] := "Wait for visual pattern, then click with retry logic"
    descriptions["Data Entry (OCR + Type)"] := "OCR field value and auto-type into form"
    descriptions["Debug Step-by-Step"] := "Workflow with debug notifications at each step"

    return descriptions.Has(name) ? descriptions[name] : "Custom workflow template"
}

InsertTemplate(templateName) {
    global g_ActionTemplates, g_CurrentSequenceSteps

    if !g_ActionTemplates.Has(templateName) {
        MsgBox("Template not found: " . templateName)
        return
    }

    steps := g_ActionTemplates[templateName]

    for step in steps {
        ; Create a copy of the step and ensure it has enabled property
        newStep := Map()
        for key, value in step {
            newStep[key] := value
        }

        ; Ensure enabled is set (default to true)
        if !newStep.Has("enabled")
            newStep["enabled"] := true

        g_CurrentSequenceSteps.Push(newStep)
    }

    RefreshStepsLV()
    ScheduleWorkflowAutosave()
    ShowNotificationBasic("Template Inserted", steps.Length . " steps added from '" . templateName . "' template", 3000, "success")
}

