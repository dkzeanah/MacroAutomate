; ═══════════════════════════════════════════════════════════════════════════════
; AutopilotUI.ahk - the four Autopilot pages (26-29) in the main window
; ═══════════════════════════════════════════════════════════════════════════════
;   26 Routine finder  repeated work found in the local activity log
;   27 Describe it     plain English -> validated workflow draft
;   28 Portals         saved sign-ins, login workflows, audited runs
;   29 Reliability     self-heal settings, workflow health, heal ledger
; ═══════════════════════════════════════════════════════════════════════════════

AutopilotUI_Title(page, title, subtitle) {
    global MainGui, TabCtrl
    TabCtrl.UseTab(page)
    MainGui.SetFont("s13 bold")
    MainGui.Add("Text", "x16 y58 w860 h26", title)
    MainGui.SetFont("s9 norm")
    MainGui.Add("Text", "x16 y86 w860 h32 cGray", subtitle)
}

AutopilotUI_Build() {
    global MainGui, TabCtrl, g_Autopilot
    ui := g_Autopilot["ui"]

    ; ── 26 · Routine finder ───────────────────────────────────────────────────
    AutopilotUI_Title(26, "Work you repeat",
        "Fan looks for action sequences you perform again and again in the local activity log (Usage Predictor) and drafts a workflow for each. "
        . "Nothing leaves this computer. Review the steps, create the workflow, then simulate it before you run it.")
    ui["scan"] := MainGui.Add("Button", "x16 y124 w150 h28", "Find routines now")
    ui["createRoutine"] := MainGui.Add("Button", "x174 y124 w150 h28", "Create workflow")
    ui["simulateRoutine"] := MainGui.Add("Button", "x332 y124 w110 h28", "Simulate")
    ui["dismissRoutine"] := MainGui.Add("Button", "x450 y124 w110 h28", "Not useful")
    ui["showDismissed"] := MainGui.Add("CheckBox", "x572 y130 w140", "Show dismissed")
    ui["toasts"] := MainGui.Add("CheckBox", "x716 y130 w160", "Notify me when found")
    ui["toasts"].Value := TrackDB_MetaGet("autopilot_toasts", "1") = "1"
    ui["routinesStatus"] := MainGui.Add("Text", "x16 y158 w860 h18 cGray", "Fan checks automatically every 30 minutes while you take a break.")
    ui["routines"] := MainGui.Add("ListView", "x16 y180 w860 h236 Grid -Multi AltSubmit",
        ["Routine", "Times", "Last 7 days", "Days", "Avg time", "Time seen", "Steps", "Apps", "Usually", "Status"])
    for col, width in [230, 50, 75, 45, 65, 75, 45, 130, 130, 75]
        ui["routines"].ModifyCol(col, width)
    ui["routineDetail"] := MainGui.Add("Text", "x16 y422 w860 h32", "Select a routine to see the workflow Fan would build.")
    ui["routineSteps"] := MainGui.Add("ListView", "x16 y458 w860 h230 Grid -Multi", ["#", "Action", "Target", "Value", "Why"])
    for col, width in [35, 120, 270, 200, 230]
        ui["routineSteps"].ModifyCol(col, width)
    MainGui.Add("Text", "x16 y694 w860 h30 cGray",
        "Counts and times are measured from what was recorded. Typed text is only replayed when Usage Predictor's literal text capture is on and it was identical each time; otherwise Fan asks for it when the workflow starts.")
    ui["scan"].OnEvent("Click", (*) => Autopilot_ScanRoutines(true))
    ui["createRoutine"].OnEvent("Click", AutopilotUI_CreateFromRoutine)
    ui["simulateRoutine"].OnEvent("Click", AutopilotUI_SimulateRoutine)
    ui["dismissRoutine"].OnEvent("Click", AutopilotUI_ToggleDismiss)
    ui["showDismissed"].OnEvent("Click", (*) => AutopilotUI_RefreshRoutines())
    ui["toasts"].OnEvent("Click", (ctl, *) => TrackDB_MetaSet("autopilot_toasts", ctl.Value ? "1" : "0"))
    ui["routines"].OnEvent("ItemSelect", AutopilotUI_RoutineSelected)

    ; ── 27 · Describe it ─────────────────────────────────────────────────────
    AutopilotUI_Title(27, "Describe it — Fan builds the workflow",
        "Write what you do in plain English. Fan turns it into steps using only its real actions and your saved names, checks every step, "
        . "and adds an approval before anything that submits, sends, pays or deletes. You review, simulate and save it.")
    MainGui.Add("Text", "x16 y122 w80", "Examples:")
    for index, example in AutopilotUI_Examples() {
        button := MainGui.Add("Button", "x" . (86 + (index - 1) * 150) . " y118 w142 h24", example[1])
        button.OnEvent("Click", AutopilotUI_UseExample.Bind(example[2]))
    }
    ui["describe"] := MainGui.Add("Edit", "x16 y148 w860 h92 Multi WantReturn", AutopilotUI_Examples()[1][2])
    ui["build"] := MainGui.Add("Button", "x16 y248 w150 h28 Default", "Build workflow")
    ui["offline"] := MainGui.Add("CheckBox", "x176 y254 w150", "Offline only (no AI)")
    ui["titles"] := MainGui.Add("CheckBox", "x330 y254 w270", "Share open window titles with the model")
    ui["describeStatus"] := MainGui.Add("Text", "x606 y254 w270 h18 cGray", "")
    ui["draft"] := MainGui.Add("ListView", "x16 y284 w860 h232 Grid -Multi", ["#", "Action", "Target", "Value", "Check", "Why"])
    for col, width in [35, 120, 190, 210, 105, 195]
        ui["draft"].ModifyCol(col, width)
    ui["editStep"] := MainGui.Add("Button", "x16 y522 w90 h24", "Edit step")
    ui["removeStep"] := MainGui.Add("Button", "x112 y522 w90 h24", "Remove")
    ui["upStep"] := MainGui.Add("Button", "x208 y522 w60 h24", "Up")
    ui["downStep"] := MainGui.Add("Button", "x274 y522 w60 h24", "Down")
    ui["draftNotes"] := MainGui.Add("Edit", "x16 y552 w860 h104 ReadOnly Multi -WantReturn", "")
    MainGui.Add("Text", "x16 y668 w45", "Name:")
    ui["draftName"] := MainGui.Add("Edit", "x60 y664 w300 h24", "")
    ui["saveDraft"] := MainGui.Add("Button", "x370 y663 w130 h27", "Save workflow")
    ui["simulateDraft"] := MainGui.Add("Button", "x508 y663 w100 h27", "Simulate")
    ui["runDraft"] := MainGui.Add("Button", "x616 y663 w120 h27", "Save && run")
    MainGui.Add("Text", "x16 y696 w860 h28 cGray",
        "Sends your description, the action list and your saved names to the configured DeepSeek model (shared Study Assistant cost cap). "
        . "Offline mode understands common phrasing without any network use.")
    ui["build"].OnEvent("Click", AutopilotUI_Build_Click)
    ui["draft"].OnEvent("DoubleClick", AutopilotUI_EditStep)
    ui["editStep"].OnEvent("Click", AutopilotUI_EditStep)
    ui["removeStep"].OnEvent("Click", AutopilotUI_RemoveStep)
    ui["upStep"].OnEvent("Click", AutopilotUI_MoveStep.Bind(-1))
    ui["downStep"].OnEvent("Click", AutopilotUI_MoveStep.Bind(1))
    ui["saveDraft"].OnEvent("Click", (*) => AutopilotUI_SaveDraft(false))
    ui["simulateDraft"].OnEvent("Click", AutopilotUI_SimulateDraft)
    ui["runDraft"].OnEvent("Click", (*) => AutopilotUI_SaveDraft(true))

    ; ── 28 · Portals ─────────────────────────────────────────────────────────
    AutopilotUI_Title(28, "Portals — sign in safely, keep an audit trail",
        "Save a website's sign-in once; it is kept in Windows Credential Manager, never in a workflow or log. Fan builds the login workflow, "
        . "hands every CAPTCHA or verification code to you, and records each audited run with screenshots and approvals.")
    ui["addPortal"] := MainGui.Add("Button", "x16 y124 w110 h28", "Add portal")
    ui["editPortal"] := MainGui.Add("Button", "x132 y124 w110 h28", "Edit / sign-in")
    ui["deletePortal"] := MainGui.Add("Button", "x248 y124 w80 h28", "Delete")
    ui["loginPortal"] := MainGui.Add("Button", "x346 y124 w160 h28", "Create login workflow")
    ui["portals"] := MainGui.Add("ListView", "x16 y160 w860 h150 Grid -Multi AltSubmit", ["Portal", "Address", "Saved sign-in", "Login workflow", "Window title contains"])
    for col, width in [140, 300, 130, 150, 130]
        ui["portals"].ModifyCol(col, width)
    MainGui.Add("Text", "x16 y322 w130", "Run with audit trail:")
    ui["auditWorkflow"] := MainGui.Add("DropDownList", "x146 y318 w300", [])
    ui["runAudit"] := MainGui.Add("Button", "x454 y316 w150 h28", "Run && record")
    ui["openReport"] := MainGui.Add("Button", "x612 y316 w130 h28", "Open last report")
    ui["openRuns"] := MainGui.Add("Button", "x750 y316 w126 h28", "Evidence folder")
    ui["portalsStatus"] := MainGui.Add("Text", "x16 y352 w860 h18 cGray", "Each audited run saves a report you can print or hand to a manager.")
    MainGui.Add("Text", "x16 y376 w400", "Recorded runs (double-click to open the report)")
    ui["runs"] := MainGui.Add("ListView", "x16 y396 w860 h296 Grid -Multi", ["Started", "Workflow", "Portal", "Result", "Steps", "Self-heals", "Approvals", "Who"])
    for col, width in [130, 200, 110, 140, 50, 75, 75, 75]
        ui["runs"].ModifyCol(col, width)
    MainGui.Add("Text", "x16 y698 w860 h28 cGray",
        "Type Credential refuses to type unless the active window's title contains the portal's title text. Human Check pauses for you on CAPTCHA, "
        . "verification codes and sign-in approvals; unattended runs stop there.")
    ui["addPortal"].OnEvent("Click", (*) => AutopilotUI_PortalDialog(""))
    ui["editPortal"].OnEvent("Click", (*) => AutopilotUI_PortalDialog(AutopilotUI_SelectedPortal()))
    ui["portals"].OnEvent("DoubleClick", (*) => AutopilotUI_PortalDialog(AutopilotUI_SelectedPortal()))
    ui["deletePortal"].OnEvent("Click", AutopilotUI_DeletePortal)
    ui["loginPortal"].OnEvent("Click", AutopilotUI_CreateLogin)
    ui["portals"].OnEvent("ItemSelect", AutopilotUI_PortalSelected)
    ui["runAudit"].OnEvent("Click", AutopilotUI_RunAudit)
    ui["openReport"].OnEvent("Click", AutopilotUI_OpenLastReport)
    ui["openRuns"].OnEvent("Click", (*) => Run('"' . Autopilot_DataDir() . '"'))
    ui["runs"].OnEvent("DoubleClick", AutopilotUI_OpenRunReport)

    ; ── 29 · Reliability ─────────────────────────────────────────────────────
    AutopilotUI_Title(29, "Self-healing & reliability",
        "When a button moves or a screen loads slowly, Fan re-finds the target by its label, its position in the window, or its text, "
        . "and records what it did. Apply a heal to make the fix permanent. Irreversible-looking steps are only healed with your OK.")
    ui["healOn"] := MainGui.Add("CheckBox", "x16 y126 w260", "Self-heal moved or missing targets")
    ui["healLearn"] := MainGui.Add("CheckBox", "x280 y126 w250", "Learn targets from successful runs")
    ui["healVision"] := MainGui.Add("CheckBox", "x536 y126 w340", "Ask the vision model as a last resort (uses API credit)")
    MainGui.Add("Text", "x16 y156 w290", "Minimum confidence when nobody is watching:")
    ui["healMin"] := MainGui.Add("DropDownList", "x306 y152 w80", ["70%", "80%", "90%"])
    ui["healRefresh"] := MainGui.Add("Button", "x776 y150 w100 h26", "Refresh")
    MainGui.Add("Text", "x16 y186 w400", "Workflow health (last 20 runs)")
    ui["health"] := MainGui.Add("ListView", "x16 y206 w860 h190 Grid -Multi", ["Workflow", "Health", "Runs", "Success", "Self-heals", "Last run", "Last problem"])
    for col, width in [190, 110, 45, 65, 75, 125, 245]
        ui["health"].ModifyCol(col, width)
    MainGui.Add("Text", "x16 y404 w400", "What self-heal did")
    ui["heals"] := MainGui.Add("ListView", "x16 y424 w860 h230 Grid -Multi", ["When", "Workflow", "Step", "Action", "Target", "Found by", "Confidence", "Status"])
    for col, width in [125, 150, 40, 90, 160, 160, 75, 60]
        ui["heals"].ModifyCol(col, width)
    ui["applyFix"] := MainGui.Add("Button", "x16 y662 w150 h28", "Apply fix to workflow")
    ui["undoFix"] := MainGui.Add("Button", "x172 y662 w100 h28", "Undo fix")
    ui["ignoreHeal"] := MainGui.Add("Button", "x278 y662 w90 h28", "Ignore")
    ui["forget"] := MainGui.Add("Button", "x374 y662 w220 h28", "Forget learned targets (workflow)")
    ui["reliabilityStatus"] := MainGui.Add("Text", "x16 y698 w860 h28 cGray", "")
    settings := SelfHeal_Settings(true)
    ui["healOn"].Value := settings["enabled"], ui["healLearn"].Value := settings["learn"], ui["healVision"].Value := settings["vision"]
    ui["healMin"].Choose(settings["minUnattended"] >= 0.9 ? 3 : settings["minUnattended"] >= 0.8 ? 2 : 1)
    ui["healOn"].OnEvent("Click", (ctl, *) => SelfHeal_SetSetting("enabled", ctl.Value))
    ui["healLearn"].OnEvent("Click", (ctl, *) => SelfHeal_SetSetting("learn", ctl.Value))
    ui["healVision"].OnEvent("Click", (ctl, *) => SelfHeal_SetSetting("vision", ctl.Value))
    ui["healMin"].OnEvent("Change", (ctl, *) => SelfHeal_SetSetting("minUnattended", [0.7, 0.8, 0.9][ctl.Value]))
    ui["healRefresh"].OnEvent("Click", (*) => AutopilotUI_RefreshReliability())
    ui["applyFix"].OnEvent("Click", AutopilotUI_ApplyFix)
    ui["undoFix"].OnEvent("Click", AutopilotUI_UndoFix)
    ui["ignoreHeal"].OnEvent("Click", AutopilotUI_IgnoreHeal)
    ui["forget"].OnEvent("Click", AutopilotUI_Forget)
    TabCtrl.UseTab(0)
}

AutopilotUI_PageShown(page) {
    try {
        switch page {
            case 26: AutopilotUI_RefreshRoutines()
            case 28: AutopilotUI_RefreshPortals(), AutopilotUI_RefreshRuns()
            case 29: AutopilotUI_RefreshReliability()
        }
    } catch as err
        LogErrorToFile(err, "caught", "Autopilot page " . page)
}

AutopilotUI_Selected(lv) => lv.GetNext(0, "F") || lv.GetNext(0)

; ─── Routine finder ────────────────────────────────────────────────────────────

AutopilotUI_RefreshRoutines() {
    global g_Autopilot
    ui := g_Autopilot["ui"]
    if !ui.Has("routines")
        return
    routines := Autopilot_Routines(ui["showDismissed"].Value)
    g_Autopilot["routines"] := routines
    lv := ui["routines"]
    lv.Opt("-Redraw"), lv.Delete()
    select := 0
    for index, r in routines {
        lv.Add("", r["name"], r["occurrences"], r["occurrences_last_7_days"], r["distinct_days"], r["avg_seconds"] . "s",
            Autopilot_Minutes(r["minutes_observed"]), r["length"], StrJoin(r["apps"], ", "), r["schedule"]["text"],
            r["status"] = "automated" ? "Automated" : r["status"] = "dismissed" ? "Dismissed" : "New")
        if g_Autopilot.Get("selectRoutine", "") = r["id"]
            select := index
    }
    lv.Opt("+Redraw")
    if select {
        lv.Modify(select, "Select Focus Vis")
        g_Autopilot["selectRoutine"] := ""
        AutopilotUI_ShowRoutine(select)
    } else if !routines.Length {
        ui["routineDetail"].Value := "No routines yet. Keep Usage Predictor learning on while you work; repeated sequences appear here after a few repetitions."
        ui["routineSteps"].Delete()
    }
}

AutopilotUI_RoutineSelected(lv, row, selected) {
    if selected
        AutopilotUI_ShowRoutine(row)
}

AutopilotUI_ShowRoutine(row) {
    global g_Autopilot
    ui := g_Autopilot["ui"]
    if row < 1 || row > g_Autopilot["routines"].Length
        return
    r := g_Autopilot["routines"][row]
    perWeek := r["minutes_per_week"] != "" ? " About " . Autopilot_Minutes(r["minutes_per_week"]) . " a week." : " (" . r["per_week_basis"] . ")"
    count := r["inputs"].Length
    inputs := count ? " Asks for " . count . (count = 1 ? " value" : " values") . " when it starts." : ""
    saved := r["workflow"] != "" ? "  Saved as workflow '" . r["workflow"] . "'." : ""
    ui["routineDetail"].Value := "Seen " . r["occurrences"] . " times on " . r["distinct_days"] . " day(s), first " . r["first_seen"]
        . ", last " . r["last_seen"] . "." . perWeek . inputs . saved
    ui["dismissRoutine"].Text := r["status"] = "dismissed" ? "Restore" : "Not useful"
    AutopilotUI_FillSteps(ui["routineSteps"], r["steps"], false)
}

AutopilotUI_FillSteps(lv, steps, withCheck, risks := 0, errors := 0) {
    lv.Opt("-Redraw"), lv.Delete()
    for index, step in steps {
        if withCheck {
            check := errors is Map && errors.Has(index) ? "⚠ " . errors[index] : risks is Map && risks.Has(index) ? "Risk: " . risks[index] : "OK"
            lv.Add("", index, step["action"], step.Get("target", ""), step.Get("param", ""), check, step.Get("note", ""))
        } else
            lv.Add("", index, step["action"], step.Get("target", ""), step.Get("param", ""), step.Get("note", ""))
    }
    lv.Opt("+Redraw")
}

AutopilotUI_SelectedRoutine() {
    global g_Autopilot
    row := AutopilotUI_Selected(g_Autopilot["ui"]["routines"])
    if !row || row > g_Autopilot["routines"].Length {
        MsgBoxTop("Select a routine first.", "Fan Autopilot", "Iconi")
        return 0
    }
    return g_Autopilot["routines"][row]
}

AutopilotUI_UniqueName(base) {
    global g_Sequences
    base := SubStr(Trim(base) != "" ? Trim(base) : "New workflow", 1, 110), name := base, n := 2
    while g_Sequences.Has(name)
        name := base . " " . n++
    return name
}

AutopilotUI_CreateFromRoutine(*) {
    r := AutopilotUI_SelectedRoutine()
    if !IsObject(r)
        return
    reply := InputBox("Name for the new workflow:", "Create workflow from routine", "w420 h130", AutopilotUI_UniqueName(r["name"]))
    if reply.Result != "OK"
        return
    try {
        name := Autopilot_SaveWorkflow(reply.Value, AutopilotUI_EngineSteps(r["steps"]))
        Autopilot_SetRoutineStatus(r["id"], "automated", name)
        AutopilotUI_RefreshRoutines()
        Autopilot_Status("routines", "Saved '" . name . "'. Simulate it, then run it from the Workflow tab, a hotkey or a schedule.")
    } catch as err
        MsgBoxTop(err.Message, "Could not save the workflow", "Icon!")
}

AutopilotUI_SimulateRoutine(*) {
    r := AutopilotUI_SelectedRoutine()
    if IsObject(r)
        SimulateSequence(AutopilotUI_EngineSteps(r["steps"]), 1.0)
}

AutopilotUI_ToggleDismiss(*) {
    r := AutopilotUI_SelectedRoutine()
    if !IsObject(r)
        return
    Autopilot_SetRoutineStatus(r["id"], r["status"] = "dismissed" ? "new" : "dismissed")
    AutopilotUI_RefreshRoutines()
}

; Steps from Python results as engine-ready Maps (enabled as a number, failsafe as a Map).
AutopilotUI_EngineSteps(steps) {
    out := []
    for , step in steps {
        failsafe := step.Get("failsafe", Map())
        out.Push(Map("action", step["action"], "target", step.Get("target", ""), "param", step.Get("param", ""),
            "enabled", step.Get("enabled", true) ? 1 : 0, "failsafe", failsafe is Map ? failsafe : Map()))
    }
    return out
}

; ─── Describe it ───────────────────────────────────────────────────────────────

AutopilotUI_Examples() => [
    ["Email an invoice", 'Open Outlook, then ask me for the client name. Type the client name, press tab and type "Invoice attached - thank you!". Then click Send.'],
    ["Copy rows to a form", "Repeat 5 times: switch to Excel, press ctrl+c, press down, switch to Chrome, click Customer ID, press ctrl+v, press enter, wait 2 seconds."],
    ["Daily portal check", "Go to https://portal.example.com, log in to Example Portal, wait 3 seconds, take a screenshot of the dashboard and notify me that the check is done."],
    ["Save and back up", 'Switch to Word, press ctrl+s, wait 1 second, press F12, wait for the Save As window to appear, type "Backup copy" and press enter.'],
    ["Timesheet reminder", 'Open Teams, wait 5 seconds, click Chat, type "Reminder: timesheets are due today at 5 PM" then get my approval and press enter.']]

AutopilotUI_UseExample(text, *) {
    global g_Autopilot
    g_Autopilot["ui"]["describe"].Value := text
}

AutopilotUI_Build_Click(*) {
    global g_Autopilot
    ui := g_Autopilot["ui"]
    text := Trim(ui["describe"].Value)
    if text = "" {
        ui["describeStatus"].Value := "Describe the task first."
        return
    }
    ui["build"].Enabled := false
    ui["describeStatus"].Value := ui["offline"].Value ? "Building an offline draft..." : "Asking the model, then checking every step..."
    if !Autopilot_Compile(text, ui["offline"].Value, ui["titles"].Value, AutopilotUI_CompileDone)
        ui["build"].Enabled := true
}

AutopilotUI_CompileDone(result) {
    global g_Autopilot
    ui := g_Autopilot["ui"]
    ui["build"].Enabled := true
    if !result.Has("steps") || !(result["steps"] is Array) || !result["steps"].Length {
        ui["describeStatus"].Value := "Could not build it"
        questions := result.Get("questions", [])
        ui["draftNotes"].Value := result.Get("error", "No steps were produced.")
            . (questions is Array && questions.Length ? "`r`n`r`nQuestions:`r`n- " . StrJoin(questions, "`r`n- ") : "")
        return
    }
    g_Autopilot["compiled"] := result
    if ui["draftName"].Value = "" || g_Autopilot.Get("draftAutoName", true) {
        ui["draftName"].Value := AutopilotUI_UniqueName(result.Get("name", "New workflow"))
        g_Autopilot["draftAutoName"] := true
    }
    AutopilotUI_ShowDraft()
}

AutopilotUI_ShowDraft() {
    global g_Autopilot
    ui := g_Autopilot["ui"], result := g_Autopilot["compiled"]
    if !IsObject(result)
        return
    validation := result.Get("validation", Map())
    risks := Map(), errors := Map(), general := []
    for , risk in validation.Get("risks", [])
        risks[risk["step"]] := risk["level"] . " · " . risk["reason"]
    for , problem in validation.Get("errors", []) {
        if problem["step"]
            errors[problem["step"]] := problem["message"]
        else
            general.Push(problem["message"])
    }
    AutopilotUI_FillSteps(ui["draft"], result["steps"], true, risks, errors)
    usage := result.Get("usage", Map())
    if !(usage is Map)
        usage := Map()
    source := result.Get("source", "") = "model"
        ? "Built by " . usage.Get("model", "the model") . " in " . usage.Get("requests", 1) . " request(s), about $" . Format("{:.4f}", usage.Get("cost_usd", 0))
        : "Offline draft (no network)"
    lines := [source . (result.Get("summary", "") != "" ? " — " . result["summary"] : "")]
    for , label in [["notes", "Notes"], ["assumptions", "Assumptions"], ["questions", "Questions for you"]] {
        items := result.Get(label[1], [])
        if items is Array && items.Length
            lines.Push(label[2] . ":`r`n- " . StrJoin(items, "`r`n- "))
    }
    warnings := []
    for , w in validation.Get("warnings", [])
        warnings.Push((w["step"] ? "step " . w["step"] . ": " : "") . w["message"])
    if warnings.Length
        lines.Push("Warnings:`r`n- " . StrJoin(warnings, "`r`n- "))
    if general.Length || errors.Count
        lines.Push("Fix before saving: " . (errors.Count ? errors.Count . " step(s) marked ⚠" : "") . (general.Length ? " " . StrJoin(general, "; ") : ""))
    ui["draftNotes"].Value := StrJoin(lines, "`r`n`r`n")
    ui["describeStatus"].Value := validation.Get("ok", false) ? result["steps"].Length . " steps · ready to review" : "Needs fixes before saving"
}

AutopilotUI_DraftRow() {
    global g_Autopilot
    result := g_Autopilot["compiled"]
    row := AutopilotUI_Selected(g_Autopilot["ui"]["draft"])
    if !IsObject(result) || !row || row > result["steps"].Length
        return 0
    return row
}

AutopilotUI_EditStep(*) {
    global g_Autopilot, MainGui
    row := AutopilotUI_DraftRow()
    if !row
        return
    step := g_Autopilot["compiled"]["steps"][row]
    dialog := Gui("+Owner" . MainGui.Hwnd . " +AlwaysOnTop", "Edit step " . row)
    dialog.SetFont("s9", "Segoe UI")
    names := []
    for , name in GetWorkflowActionNames()
        if name != "Learned Rehearsal Step"
            names.Push(name)
    dialog.Add("Text", "w80", "Action")
    action := dialog.Add("DropDownList", "x+8 yp-3 w300", names)
    try action.Choose(step["action"])
    dialog.Add("Text", "xm w80", "Target")
    target := dialog.Add("Edit", "x+8 yp-3 w420", step.Get("target", ""))
    dialog.Add("Text", "xm w80", "Value")
    param := dialog.Add("Edit", "x+8 yp-3 w420", step.Get("param", ""))
    hint := dialog.Add("Text", "xm w510 h48 cGray", "")
    action.OnEvent("Change", AutopilotUI_StepHint.Bind(action, hint))
    AutopilotUI_StepHint(action, hint)
    dialog.Add("Button", "xm w90 Default", "OK").OnEvent("Click", AutopilotUI_StepSaved.Bind(dialog, step, action, target, param))
    dialog.Add("Button", "x+8 w90", "Cancel").OnEvent("Click", (*) => dialog.Destroy())
    dialog.OnEvent("Escape", (*) => dialog.Destroy())
    dialog.Show()
}

AutopilotUI_StepHint(action, hint, *) {
    if action.Text = ""
        return
    spec := GetWorkflowActionSpec(action.Text)
    hint.Value := "Target: " . (spec["targetUsed"] ? spec["targetLabel"] . " (" . spec["targetHint"] . ")" : "unused")
        . "   Value: " . (spec["paramUsed"] ? spec["paramLabel"] . " (" . spec["paramHint"] . ")" : "unused") . "`n" . SubStr(spec["help"], 1, 160)
}

AutopilotUI_StepSaved(dialog, step, action, target, param, *) {
    step["action"] := action.Text, step["target"] := target.Value, step["param"] := param.Value
    step["note"] := "Edited by you"
    dialog.Destroy()
    AutopilotUI_Revalidate()
}

AutopilotUI_RemoveStep(*) {
    global g_Autopilot
    if row := AutopilotUI_DraftRow() {
        g_Autopilot["compiled"]["steps"].RemoveAt(row)
        AutopilotUI_Revalidate()
    }
}

AutopilotUI_MoveStep(direction, *) {
    global g_Autopilot
    row := AutopilotUI_DraftRow()
    steps := IsObject(g_Autopilot["compiled"]) ? g_Autopilot["compiled"]["steps"] : []
    other := row + direction
    if !row || other < 1 || other > steps.Length
        return
    swap := steps[row], steps[row] := steps[other], steps[other] := swap
    AutopilotUI_Revalidate(other)
}

; Re-check the edited draft with the same validator the compiler used.
AutopilotUI_Revalidate(selectRow := 0) {
    global g_Autopilot
    result := g_Autopilot["compiled"]
    if !IsObject(result)
        return
    AutopilotUI_ShowDraft()
    g_Autopilot["ui"]["describeStatus"].Value := "Checking your edit..."
    Autopilot_Job("validate", Map("steps", result["steps"], "catalog", Autopilot_Catalog(), "context", Autopilot_Context(false)),
        AutopilotUI_ValidateDone.Bind(selectRow), 60000)
}

AutopilotUI_ValidateDone(selectRow, checked) {
    global g_Autopilot
    result := g_Autopilot["compiled"]
    if !IsObject(result)
        return
    if checked.Has("validation")
        result["validation"] := checked["validation"]
    else
        result["validation"] := Map("ok", false, "errors", [Map("step", 0, "message", checked.Get("error", "validation failed"))], "warnings", [], "risks", [])
    AutopilotUI_ShowDraft()
    if selectRow
        g_Autopilot["ui"]["draft"].Modify(selectRow, "Select Focus Vis")
}

AutopilotUI_SaveDraft(runAfter) {
    global g_Autopilot, g_Sequences
    ui := g_Autopilot["ui"], result := g_Autopilot["compiled"]
    if !IsObject(result) || !result["steps"].Length {
        MsgBoxTop("Build a workflow first.", "Fan Autopilot", "Iconi")
        return
    }
    if !result.Get("validation", Map()).Get("ok", false) {
        MsgBoxTop("Some steps still need fixes (marked ⚠). Edit or remove them, then save.", "Fan Autopilot", "Icon!")
        return
    }
    name := Trim(ui["draftName"].Value)
    overwrite := false
    if g_Sequences.Has(name) {
        if MsgBoxTop("A workflow named '" . name . "' exists. Replace it?", "Fan Autopilot", "YesNo Icon? Default2") != "Yes"
            return
        overwrite := true
    }
    try {
        name := Autopilot_SaveWorkflow(name, AutopilotUI_EngineSteps(result["steps"]), overwrite)
    } catch as err {
        MsgBoxTop(err.Message, "Could not save the workflow", "Icon!")
        return
    }
    g_Autopilot["draftAutoName"] := false
    ui["describeStatus"].Value := "Saved '" . name . "'"
    if !runAfter
        return
    if MsgBoxTop("Run '" . name . "' now?`n`nFan will use your mouse and keyboard. Press Esc at any time to stop.", "Fan Autopilot", "OKCancel Iconi") != "OK"
        return
    try {
        out := Autopilot_RunWorkflow(name)
        ui["describeStatus"].Value := out["ok"] ? "Ran '" . name . "' successfully" : "Stopped: " . SubStr(out["error"], 1, 120)
    } catch as err
        MsgBoxTop(err.Message, "Fan Autopilot", "Icon!")
}

AutopilotUI_SimulateDraft(*) {
    global g_Autopilot
    result := g_Autopilot["compiled"]
    if IsObject(result) && result["steps"].Length
        SimulateSequence(AutopilotUI_EngineSteps(result["steps"]), 1.0)
}

; ─── Portals ───────────────────────────────────────────────────────────────────

AutopilotUI_RefreshPortals() {
    global g_Autopilot, g_Sequences
    ui := g_Autopilot["ui"]
    lv := ui["portals"]
    lv.Opt("-Redraw"), lv.Delete()
    g_Autopilot["portalNames"] := []
    for name, p in Autopilot_Portals() {
        user := AutopilotCred_User(name)
        login := p["login_workflow"] != "" && g_Sequences.Has(p["login_workflow"]) ? p["login_workflow"] : "(not created)"
        lv.Add("", name, p["url"], user != "" ? "✓ " . user : "missing", login, p["title_hint"])
        g_Autopilot["portalNames"].Push(name)
    }
    lv.Opt("+Redraw")
    names := []
    for name in g_Sequences
        names.Push(name)
    current := ui["auditWorkflow"].Text
    ui["auditWorkflow"].Delete(), ui["auditWorkflow"].Add(names)
    if current != ""
        try ui["auditWorkflow"].Choose(current)
}

AutopilotUI_SelectedPortal() {
    global g_Autopilot
    row := AutopilotUI_Selected(g_Autopilot["ui"]["portals"])
    names := g_Autopilot.Get("portalNames", [])
    return row && row <= names.Length ? names[row] : ""
}

AutopilotUI_PortalSelected(lv, row, selected) {
    global g_Autopilot, g_Sequences
    if !selected
        return
    name := AutopilotUI_SelectedPortal()
    portals := Autopilot_Portals()
    if name != "" && portals.Has(name) && portals[name]["login_workflow"] != "" && g_Sequences.Has(portals[name]["login_workflow"])
        try g_Autopilot["ui"]["auditWorkflow"].Choose(portals[name]["login_workflow"])
}

AutopilotUI_PortalDialog(existing) {
    global MainGui
    portals := Autopilot_Portals()
    p := existing != "" && portals.Has(existing) ? portals[existing] : Map("name", "", "url", "https://", "title_hint", "",
        "username_label", "", "password_label", "", "submit_label", "", "notes", "")
    dialog := Gui("+Owner" . MainGui.Hwnd . " +AlwaysOnTop", existing != "" ? "Portal: " . existing : "Add a portal")
    dialog.SetFont("s9", "Segoe UI")
    fields := Map()
    rows := [["name", "Portal name", p["name"]], ["url", "Sign-in page (https://)", p["url"]],
        ["user", "Username / email", existing != "" ? AutopilotCred_User(existing) : ""], ["secret", "Password", ""],
        ["title_hint", "Window title contains", p["title_hint"]], ["username_label", "Username box label (optional)", p["username_label"]],
        ["password_label", "Password box label (optional)", p["password_label"]], ["submit_label", "Sign-in button text (optional)", p["submit_label"]],
        ["notes", "Notes", p["notes"]]]
    for , spec in rows {
        dialog.Add("Text", "xm w190", spec[2])
        fields[spec[1]] := dialog.Add("Edit", "x+8 yp-3 w330" . (spec[1] = "secret" ? " Password" : ""), spec[3])
    }
    dialog.Add("Text", "xm w530 cGray", existing != "" && AutopilotCred_Exists(existing)
        ? "Leave the password empty to keep the saved one. The password is stored only in Windows Credential Manager (Fan/Portal/<name>)."
        : "The username and password are stored only in Windows Credential Manager (Fan/Portal/<name>), protected by your Windows sign-in.")
    dialog.Add("Text", "xm w530 cGray", "Window title text: Fan refuses to type the sign-in unless the active window's title contains it. Leave blank to use the site name.")
    status := dialog.Add("Text", "xm w530 cRed", "")
    dialog.Add("Button", "xm w100 Default", "Save").OnEvent("Click", (*) => AutopilotUI_PortalSave(dialog, fields, existing, status))
    dialog.Add("Button", "x+8 w100", "Cancel").OnEvent("Click", (*) => dialog.Destroy())
    dialog.OnEvent("Escape", (*) => dialog.Destroy())
    dialog.Show()
    fields[existing != "" ? "secret" : "name"].Focus()
}

AutopilotUI_PortalSave(dialog, fields, existing, status) {
    profile := Map()
    for key in ["name", "url", "title_hint", "username_label", "password_label", "submit_label", "notes"]
        profile[key] := Trim(fields[key].Value)
    user := Trim(fields["user"].Value), secret := fields["secret"].Value
    problem := Autopilot_ValidatePortal(profile)
    if problem = "" && user = ""
        problem := "Enter the username or email used to sign in"
    keepSecret := existing != "" && secret = "" && AutopilotCred_Exists(existing)
    if problem = "" && secret = "" && !keepSecret
        problem := "Enter the password (it is saved only in Windows Credential Manager)"
    if problem != "" {
        status.Value := problem
        return
    }
    try {
        if keepSecret {
            saved := AutopilotCred_Read(existing)
            secret := saved.Get("secret", "")
            saved := ""
        }
        if !AutopilotCred_Write(profile["name"], user, secret)
            throw Error("Windows Credential Manager refused to save the sign-in")
        secret := "", fields["secret"].Value := ""
        if existing != "" && existing != profile["name"]
            AutopilotCred_Delete(existing)
        Autopilot_PortalSave(profile, existing)
    } catch as err {
        status.Value := err.Message
        return
    }
    dialog.Destroy()
    AutopilotUI_RefreshPortals()
    Autopilot_Status("portals", "Saved '" . profile["name"] . "'. Next: Create login workflow, then Run && record while you watch.")
}

AutopilotUI_DeletePortal(*) {
    name := AutopilotUI_SelectedPortal()
    if name = ""
        return MsgBoxTop("Select a portal first.", "Fan Autopilot", "Iconi")
    if MsgBoxTop("Delete the portal '" . name . "'?`n`nThis also removes its saved sign-in from Windows Credential Manager. Workflows that use it are kept.",
        "Fan Autopilot", "YesNo Icon! Default2") != "Yes"
        return
    Autopilot_PortalDelete(name)
    AutopilotUI_RefreshPortals()
}

AutopilotUI_CreateLogin(*) {
    name := AutopilotUI_SelectedPortal()
    if name = ""
        return MsgBoxTop("Select a portal first.", "Fan Autopilot", "Iconi")
    p := Autopilot_Portals()[name]
    profile := Map("name", name, "url", p["url"], "title_hint", p["title_hint"], "username_label", p["username_label"],
        "password_label", p["password_label"], "submit_label", p["submit_label"])
    Autopilot_Status("portals", "Building the login workflow...")
    Autopilot_Job("portal_template", Map("profile", profile), AutopilotUI_LoginDone.Bind(name), 60000)
}

AutopilotUI_LoginDone(portal, result) {
    global g_Sequences, g_Autopilot
    if !result.Get("ok", false) {
        problems := result.Get("errors", [])
        Autopilot_Status("portals", "Could not build it: " . (problems is Array && problems.Length ? StrJoin(problems, "; ") : result.Get("error", "unknown error")))
        return
    }
    name := result["name"], overwrite := false
    if g_Sequences.Has(name) {
        if MsgBoxTop("Replace the existing workflow '" . name . "'?", "Fan Autopilot", "YesNo Icon? Default2") != "Yes"
            return
        overwrite := true
    }
    try {
        Autopilot_SaveWorkflow(name, AutopilotUI_EngineSteps(result["steps"]), overwrite)
        TrackDB().Run("UPDATE autopilot_portal SET login_workflow=?, updated=? WHERE name=?", name, Autopilot_Now(), portal)
    } catch as err {
        Autopilot_Status("portals", "Could not save it: " . err.Message)
        return
    }
    AutopilotUI_RefreshPortals()
    try g_Autopilot["ui"]["auditWorkflow"].Choose(name)
    Autopilot_Status("portals", "Saved '" . name . "' (" . result["steps"].Length . " steps). Run && record it once while you watch; adjust labels in the Workflow tab if needed.")
}

AutopilotUI_RunAudit(*) {
    global g_Autopilot
    ui := g_Autopilot["ui"]
    workflow := ui["auditWorkflow"].Text
    if workflow = ""
        return MsgBoxTop("Choose the workflow to run.", "Fan Autopilot", "Iconi")
    portal := AutopilotUI_SelectedPortal()
    for name, p in Autopilot_Portals()
        if p["login_workflow"] = workflow
            portal := name
    if MsgBoxTop("Run '" . workflow . "' with an audit trail?`n`nFan will use your mouse and keyboard, take a screenshot after each step, "
        . "and open a report when it finishes. Press Esc to stop.", "Fan Autopilot", "OKCancel Iconi") != "OK"
        return
    try {
        out := Autopilot_RunWorkflow(workflow, Map("evidence", "steps", "portal", portal))
        detail := out["ok"] ? "" : ": " . SubStr(out["error"], 1, 140)
        Autopilot_Status("portals", (out["ok"] ? "Completed '" : "Stopped '") . workflow . "'" . detail . " — building the report...")
    } catch as err
        MsgBoxTop(err.Message, "Fan Autopilot", "Icon!")
    AutopilotUI_RefreshRuns()
}

AutopilotUI_RefreshRuns() {
    global g_Autopilot
    ui := g_Autopilot["ui"]
    if !ui.Has("runs") || !TrackDB_Ready()
        return
    lv := ui["runs"]
    lv.Opt("-Redraw"), lv.Delete()
    g_Autopilot["runRows"] := []
    for , row in TrackDB().Query("SELECT * FROM autopilot_run WHERE dir<>'' ORDER BY started DESC LIMIT 60") {
        result := Integer(row["ok"]) ? "Completed" : Integer(row["aborted"]) ? "Stopped" : "Failed at step " . row["failed_step"]
        lv.Add("", row["started"], row["workflow"], row["portal"], result, row["completed"], row["heals"], row["approvals"], row["mode"])
        g_Autopilot["runRows"].Push(row["dir"])
    }
    lv.Opt("+Redraw")
}

AutopilotUI_OpenRunReport(lv, row) {
    global g_Autopilot
    dirs := g_Autopilot.Get("runRows", [])
    if !row || row > dirs.Length
        return
    report := dirs[row] . "\report.html"
    if FileExist(report)
        Run('"' . report . '"')
    else if FileExist(dirs[row] . "\run.json")
        Autopilot_BuildReport(dirs[row], true)
}

AutopilotUI_OpenLastReport(*) {
    global g_Autopilot
    if g_Autopilot["lastReport"] != "" && FileExist(g_Autopilot["lastReport"])
        return Run('"' . g_Autopilot["lastReport"] . '"')
    dirs := g_Autopilot.Get("runRows", [])
    if dirs.Length
        return AutopilotUI_OpenRunReport(g_Autopilot["ui"]["runs"], 1)
    MsgBoxTop("No audited runs yet.", "Fan Autopilot", "Iconi")
}

; ─── Reliability ───────────────────────────────────────────────────────────────

AutopilotUI_RefreshReliability() {
    global g_Autopilot
    ui := g_Autopilot["ui"]
    if !ui.Has("health") || !TrackDB_Ready()
        return
    lv := ui["health"]
    lv.Opt("-Redraw"), lv.Delete()
    health := SelfHeal_Health()
    for name, h in health
        lv.Add("", name, h["badge"], h["runs"], Round(h["rate"] * 100) . "%", h["heals"], h["last"], SubStr(h["lastError"], 1, 120))
    lv.Opt("+Redraw")
    heals := TrackDB().Query("SELECT * FROM autopilot_heal ORDER BY id DESC LIMIT 200")
    g_Autopilot["healRows"] := heals
    lv := ui["heals"]
    lv.Opt("-Redraw"), lv.Delete()
    openCount := 0
    for , h in heals {
        lv.Add("", h["at"], h["workflow"], h["step_index"], h["action"], h["action"] = "OCR Click" ? h["param"] : h["target"],
            h["strategy"], Round(Float(h["confidence"]) * 100) . "%", h["status"])
        openCount += h["status"] = "open" ? 1 : 0
    }
    lv.Opt("+Redraw")
    ui["reliabilityStatus"].Value := health.Count . " workflow(s) with recorded runs. " . openCount . " heal(s) waiting for review — "
        . "applying one updates the saved step so it no longer needs healing."
}

AutopilotUI_SelectedHeal() {
    global g_Autopilot
    row := AutopilotUI_Selected(g_Autopilot["ui"]["heals"])
    rows := g_Autopilot.Get("healRows", [])
    if !row || row > rows.Length {
        MsgBoxTop("Select a heal first.", "Fan Autopilot", "Iconi")
        return 0
    }
    return rows[row]
}

AutopilotUI_ApplyFix(*) {
    heal := AutopilotUI_SelectedHeal()
    if !IsObject(heal)
        return
    try {
        if SelfHeal_ApplyFix(heal["id"])
            Autopilot_Status("reliability", "Updated '" . heal["workflow"] . "'. Undo fix restores the previous step.")
    } catch as err
        MsgBoxTop(err.Message, "Fan · apply fix", "Icon!")
    AutopilotUI_RefreshReliability()
}

AutopilotUI_UndoFix(*) {
    heal := AutopilotUI_SelectedHeal()
    if !IsObject(heal)
        return
    try {
        SelfHeal_UndoFix(heal["id"])
        Autopilot_Status("reliability", "Restored the previous step in '" . heal["workflow"] . "'.")
    } catch as err
        MsgBoxTop(err.Message, "Fan · undo fix", "Icon!")
    AutopilotUI_RefreshReliability()
}

AutopilotUI_IgnoreHeal(*) {
    heal := AutopilotUI_SelectedHeal()
    if IsObject(heal) {
        TrackDB().Run("UPDATE autopilot_heal SET status='ignored' WHERE id=?", heal["id"])
        AutopilotUI_RefreshReliability()
    }
}

AutopilotUI_Forget(*) {
    heal := AutopilotUI_SelectedHeal()
    if !IsObject(heal)
        return
    if MsgBoxTop("Forget every learned target for '" . heal["workflow"] . "'? Fan relearns them on the next successful runs.",
        "Fan Autopilot", "YesNo Icon? Default2") = "Yes" {
        SelfHeal_Forget(heal["workflow"])
        Autopilot_Status("reliability", "Learned targets for '" . heal["workflow"] . "' were cleared.")
    }
}
