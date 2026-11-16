; Task navigation over the existing page IDs. IDs are also used by IPC and hotkeys.
global g_FanNav := Map("controls", [], "current", 0, "mode", "classic", "classicLast", Map())

FanNav_ClassicGroups() {
    ; Only closely related tools share a tab; all original pages keep their IDs.
    return [
        ["Workflow", [1]], ["Patterns", [2]], ["Live OCR", [3]],
        ["Spools", [4]], ["Analytics", [5]], ["Clipboard", [6]],
        ["Hotkeys", [7]], ["Hotstrings", [8]], ["Triggers", [9]],
        ["Settings", [10]], ["Notepad", [11]], ["Calendar", [12]],
        ["Tracking", [13]], ["App Learning", [14, 16, 17]],
        ["Snapshot Recovery", [15]], ["Study", [18, 19]],
        ["DeepSeek Bridge", [20]], ["Media Intel", [21]],
        ["Knowledge", [22]], ["Scribe", [23]]]
}

FanNav_ClassicPageName(page) {
    switch page {
        case 14: return "App Learner"
        case 16: return "Vision Scout"
        case 17: return "Usage Predictor"
        case 18: return "Study Assistant"
        case 19: return "Live Portal"
        default: return FanNav_Pages()[page][1]
    }
}

FanNav_Groups() {
    return [Map("name", "Start", "pages", [24]),
        Map("name", "Automate", "pages", [1, 23, 4, 7, 8, 9, 20]),
        Map("name", "Capture & learn", "pages", [13, 14, 16, 17, 3, 21, 15]),
        Map("name", "Review & apply", "pages", [22]),
        Map("name", "Study", "pages", [18, 19]),
        Map("name", "Organize", "pages", [6, 11, 12, 5]),
        Map("name", "Settings", "pages", [10, 2])]
}

FanNav_Pages() {
    ; title, purpose, next step; one source for navigation and built-in help.
    return [
        ["Workflow", "Build a repeatable sequence from named targets and actions.", "Simulate the sequence, inspect the result, then run it in the intended application."],
        ["Visual patterns", "Maintain the FindText patterns used to locate controls.", "Recapture changed controls and check the match before using them in a workflow."],
        ["Screen OCR", "Read visible text and configure watched regions.", "Check the recognized text against the screen; use corrected text as study or workflow input."],
        ["Scheduled workflows", "Schedule saved workflows and manage their triggers.", "Test the saved workflow first, then enable its schedule."],
        ["Workflow analytics", "Inspect execution history and failures.", "Find a failing run, correct the workflow, and compare its next result."],
        ["Clipboard", "Prepare reusable clipboard fields and paste sequences.", "Check the field order before pasting into the destination form."],
        ["Hotkeys", "Bind a saved workflow to a keyboard shortcut.", "Test the workflow and confirm that the shortcut does not conflict with another application."],
        ["Hotstrings", "Expand typed abbreviations into text or actions.", "Try an expansion in a disposable text field before using it in your work."],
        ["Triggers", "Run workflows when their configured conditions occur.", "Confirm the condition and test the workflow before enabling a trigger."],
        ["Settings", "Configure application behavior and storage.", "Use the collection controls under Capture & learn to see what each recorder collects."],
        ["Notes", "Keep notes that can explain your captures and procedures.", "Record the task, expected result, and limitations alongside a procedure."],
        ["Calendar", "Review dates and scheduled work.", "Review scheduled workflows under Automate when you need to change execution."],
        ["Activity tracking", "Record window time, mouse/keyboard activity and snapshots using the individual switches.", "Collect one representative task, stop the relevant recorder, then open Review & apply. Activity frequency alone does not establish relevance."],
        ["App interface learner", "Map an application's accessible controls into named targets.", "Inspect the map in the target app, then use a named element in Workflow. Recheck after layout or DPI changes."],
        ["Find capture source", "Trace a stored snapshot back to its original page or window.", "Check the recovered URL or source before citing or reusing the capture."],
        ["Visual learner", "Discover visible targets and recurring interaction sequences.", "Review captured targets and their evidence. A pixel match alone does not verify a control's meaning."],
        ["Usage predictions", "Suggest continuations from repeated recorded sequences.", "Review the sequence and context before accepting a suggestion. Repetition is not proof that it is correct."],
        ["Study library", "Import source material, review questions and correct answers.", "Check answers against their cited material, save corrections, then use spaced review or export."],
        ["Live study session", "Pin a portal window and observe questions using the study library.", "Start in observe/suggest mode; review evidence and the pinned target before choosing an input mode. Ctrl+Shift+Esc aborts."],
        ["Agent workbench", "Give the connected agent a concrete task and inspect its tools and results.", "Describe the expected outcome, follow the activity log, and check the actual result before reusing it."],
        ["Media analysis", "Extract summaries, frames and feature maps from media or windows.", "Inspect the source frames and timestamps; generated summaries remain interpretations of that source."],
        ["Evidence & knowledge", "Browse captured records and distinguish observations, checks and saved rehearsals.", "Select a category, search its recent records, and inspect an item. Open a learning claim's evidence before deciding whether to reuse it."],
        ["Record a procedure", "Record a task as a sequence of interactions with Workflow Scribe.", "Stop recording, inspect the steps and targets, then rehearse before reusing the procedure."],
        ["Start here", "Choose a task, collect a small example, review the evidence, then apply the result.", "Use the guided routes below. Review & apply is the common destination for the collection tools."]]
}

FanNav_Init() {
    global g_FanNav, MainGui, TabCtrl
    names := []
    for group in FanNav_Groups()
        names.Push(group["name"])
    TabCtrl.UseTab(0)
    g_FanNav["group"] := MainGui.Add("DropDownList", "x15 y28 w155 Choose1", names)
    g_FanNav["page"] := MainGui.Add("DropDownList", "x178 y28 w255", [])
    g_FanNav["hint"] := MainGui.Add("Text", "x445 y30 w425 h18", "")
    for key in ["group", "page", "hint"]
        g_FanNav["controls"].Push(g_FanNav[key])
    g_FanNav["group"].OnEvent("Change", FanNav_GroupChanged)
    g_FanNav["page"].OnEvent("Change", FanNav_PageChanged)
    ; Keep the native page container and its IDs, but replace its crowded strip.
    ; TCS_BUTTONS | TCS_FIXEDWIDTH, single line; TCM_SETITEMSIZE = 1 x 1 px.
    ; The page container must clip siblings so its dialog cannot paint over
    ; either navigation header when the real, densely populated pages redraw.
    TabCtrl.Opt("-Wrap +0x500 +0x4000000")
    SendMessage(0x1329, 0, 0x10001, TabCtrl)
    g_FanNav["start"] := MainGui.Add("Button", "x460 y2 w75 h21", "Start here")
    g_FanNav["start"].OnEvent("Click", (*) => FanNav_Open(24))
    g_FanNav["helpButton"] := MainGui.Add("Button", "x540 y2 w105 h21", "How to use this")
    g_FanNav["helpButton"].OnEvent("Click", FanNav_Help)
    g_FanNav["reviewButton"] := MainGui.Add("Button", "x650 y2 w115 h21", "Review evidence")
    g_FanNav["reviewButton"].OnEvent("Click", (*) => FanNav_Open(22))
    titles := []
    for group in FanNav_ClassicGroups()
        titles.Push(group[1])
    ; A header-only tab strip selects the stable native page container below.
    ; It owns no page controls, so switching interface never rebuilds a tool.
    g_FanNav["classicTabs"] := MainGui.Add("Tab", "x5 y24 w890 h27 -Wrap", titles)
    g_FanNav["classicTabs"].UseTab(0)
    g_FanNav["classicTabs"].OnEvent("Change", FanNav_ClassicChanged)
    g_FanNav["sectionLabel"] := MainGui.Add("Text", "x460 y5 w50 h18", "View:")
    g_FanNav["section"] := MainGui.Add("DropDownList", "x510 y2 w255", [])
    g_FanNav["section"].OnEvent("Change", FanNav_SectionChanged)
    for key in ["start", "helpButton", "reviewButton", "classicTabs", "sectionLabel", "section"]
        g_FanNav["controls"].Push(g_FanNav[key])
    SetTimer(FanNav_Sync, 250)
    FanNav_SetMode(FanData_Config().Get("interface_mode", "classic"), false)
}

FanNav_SetMode(mode, persist := true) {
    global g_FanNav, MainGui, TabCtrl
    mode := mode = "clean" ? "clean" : "classic"
    if persist {
        config := FanData_Config()
        config["interface_mode"] := mode
        FanData_SaveConfig(config)
    }
    g_FanNav["mode"] := mode
    for key in ["group", "page", "hint", "start", "helpButton", "reviewButton"]
        g_FanNav[key].Visible := mode = "clean"
    g_FanNav["classicTabs"].Visible := mode = "classic"
    if g_FanNav.Has("modeSetting")
        g_FanNav["modeSetting"].Choose(mode = "clean" ? 2 : 1)
    MainGui.Title := mode = "clean" ? "Macro Automator - task workspace" : "Macro Automator - tabbed workspace"
    if mode = "classic" && TabCtrl.Value = 24
        TabCtrl.Choose(1)
    else if mode = "clean" && !g_FanNav["current"]
        TabCtrl.Choose(24)
    g_FanNav["current"] := 0
    FanNav_Sync()
}

FanNav_SettingsBuild() {
    global g_FanNav, MainGui
    MainGui.Add("Text", "x300 y469 w55 h18", "Interface:")
    g_FanNav["modeSetting"] := MainGui.Add("DropDownList", "x360 y465 w270", ["Original tabs", "Clean task workspace"])
    g_FanNav["modeSetting"].Choose(FanData_Config().Get("interface_mode", "classic") = "clean" ? 2 : 1)
    g_FanNav["modeSetting"].OnEvent("Change", (ctl, *) => FanNav_SetMode(ctl.Value = 2 ? "clean" : "classic"))
    MainGui.Add("Text", "x300 y491 w570 h14 cGray", "Switches immediately and is remembered. Both views use the same tools and data.")
}

FanNav_ClassicChanged(*) {
    global g_FanNav
    index := g_FanNav["classicTabs"].Value
    group := FanNav_ClassicGroups()[index]
    FanNav_Open(g_FanNav["classicLast"].Get(index, group[2][1]))
}

FanNav_SectionChanged(*) {
    global g_FanNav
    group := FanNav_ClassicGroups()[g_FanNav["classicTabs"].Value]
    if g_FanNav["section"].Value
        FanNav_Open(group[2][g_FanNav["section"].Value])
}

FanNav_SyncClassic(page) {
    global g_FanNav
    for index, group in FanNav_ClassicGroups() {
        for section, id in group[2] {
            if id != page
                continue
            g_FanNav["classicTabs"].Choose(index)
            g_FanNav["classicLast"][index] := page
            names := []
            for member in group[2]
                names.Push(FanNav_ClassicPageName(member))
            g_FanNav["section"].Delete(), g_FanNav["section"].Add(names)
            g_FanNav["section"].Choose(section)
            showSections := g_FanNav["mode"] = "classic" && group[2].Length > 1
            g_FanNav["section"].Visible := showSections
            g_FanNav["sectionLabel"].Visible := showSections
            return
        }
    }
    g_FanNav["section"].Visible := false
    g_FanNav["sectionLabel"].Visible := false
}

FanNav_Resize(width) {
    global g_FanNav
    if g_FanNav.Has("classicTabs")
        g_FanNav["classicTabs"].Move(, , width - 10)
    FanNav_Raise()
}

FanNav_Raise() {
    global g_FanNav
    ; Specialist pages can repaint their page dialog after Show/Size. Restore
    ; navigation above that dialog even when the selected page has not changed.
    for ctl in g_FanNav["controls"] {
        if ctl.Visible
            DllCall("SetWindowPos", "Ptr", ctl.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
    }
    if g_FanNav["mode"] = "classic" && g_FanNav.Has("classicTabs")
        DllCall("RedrawWindow", "Ptr", g_FanNav["classicTabs"].Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x105)

}

FanNav_Cycle(direction) {
    global g_FanNav, TabCtrl
    if g_FanNav["mode"] = "classic" {
        count := FanNav_ClassicGroups().Length
        next := Mod(g_FanNav["classicTabs"].Value - 1 + direction + count, count) + 1
        g_FanNav["classicTabs"].Choose(next)
        FanNav_ClassicChanged()
        g_FanNav["classicTabs"].Focus()
        return
    }
    pages := []
    for group in FanNav_Groups()
        for page in group["pages"]
            pages.Push(page)
    for index, page in pages {
        if page = TabCtrl.Value {
            next := Mod(index - 1 + direction + pages.Length, pages.Length) + 1
            FanNav_Open(pages[next])
            g_FanNav["page"].Focus()
            return
        }
    }
}

FanNav_Open(page, *) {
    global TabCtrl
    TabCtrl.Choose(page)
    FanNav_Sync()
    if page = 22
        Know_UiRefresh()
    if page = 24
        FanHome_Refresh()
}

FanNav_GroupChanged(*) {
    global g_FanNav
    group := FanNav_Groups()[g_FanNav["group"].Value]
    FanNav_Open(group["pages"][1])
}

FanNav_PageChanged(*) {
    global g_FanNav
    group := FanNav_Groups()[g_FanNav["group"].Value]
    if g_FanNav["page"].Value
        FanNav_Open(group["pages"][g_FanNav["page"].Value])
}

FanNav_Sync(*) {
    global g_FanNav, TabCtrl
    page := TabCtrl.Value
    if page = g_FanNav["current"] {
        FanNav_Raise()
        return
    }
    FanNav_SyncClassic(page)
    for gi, group in FanNav_Groups() {
        for pi, id in group["pages"] {
            if id != page
                continue
            labels := []
            for pageId in group["pages"]
                labels.Push(FanNav_Pages()[pageId][1])
            g_FanNav["group"].Choose(gi)
            g_FanNav["page"].Delete(), g_FanNav["page"].Add(labels)
            g_FanNav["page"].Choose(pi)
            g_FanNav["hint"].Value := page = 22 ? "Inspect source > check evidence > decide how to use it" : "How to use this: purpose, steps and next action"
            g_FanNav["current"] := page
            ; Tab3 repaints its page dialog on selection. Keep global navigation
            ; above that dialog rather than letting it cover the selectors.
            for ctl in g_FanNav["controls"] {
                if ctl.Visible
                    DllCall("SetWindowPos", "Ptr", ctl.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
            }
            return
        }
    }
}

FanNav_Help(*) {
    global TabCtrl, g_FanNav
    page := FanNav_Pages()[TabCtrl.Value]
    if g_FanNav.Has("help")
        try g_FanNav["help"].Destroy()
    g := Gui("+Owner" . MainGui.Hwnd, page[1] . " - how to use it")
    g.SetFont("s10", "Segoe UI")
    g.Add("Text", "w620", page[2])
    g.Add("Text", "w620 y+18", "Next action: " . page[3])
    g.Add("Text", "w620 y+18", "Collection records describe what was observed. Check the source, outcome and environment before treating an observation as reusable knowledge.")
    g.Add("Button", "w160 y+18", "Review collected data").OnEvent("Click", (*) => (g.Hide(), FanNav_Open(22)))
    g.OnEvent("Close", (*) => g.Destroy())
    g_FanNav["help"] := g
    g.Show()
}

FanHome_Build() {
    global MainGui, TabCtrl, g_FanNav
    TabCtrl.UseTab(24)
    MainGui.Add("Text", "x20 y62 w850 h28", "Collect something useful. Review it. Put it to work.").SetFont("s15 bold")
    MainGui.Add("Text", "x20 y102 w850 h40", "Choose the outcome you want below. The two selectors above organize the existing tools by task; How to use this explains each page and its next action.")
    routes := [
        ["Build an automation", "Record a procedure or map an app > inspect targets > build a Workflow > simulate > run", 1],
        ["Understand a task I repeat", "Enable the relevant activity recorder > perform one task > stop > inspect the evidence", 13],
        ["Learn an application's controls", "Map the interface > inspect named targets > check them in the live app > use in a workflow", 14],
        ["Study from my sources", "Import material > review captured questions and cited answers > correct > review or export", 18],
        ["Review what was collected", "Browse categories > search recent records > read source and context > review claim evidence", 22]]
    y := 155
    for route in routes {
        MainGui.Add("Button", "x20 y" . y . " w225 h36", route[1]).OnEvent("Click", FanNav_Open.Bind(route[3]))
        MainGui.Add("Text", "x265 y" . (y+4) . " w590 h38", route[2])
        y += 65
    }
    MainGui.Add("Text", "x20 y490 w850 h24", "What the stored data can tell you").SetFont("s11 bold")
    g_FanNav["summary"] := MainGui.Add("Text", "x20 y522 w850 h64", "Open Review & apply to inspect the inventory.")
    MainGui.Add("Text", "x20 y596 w850 h46", "Record count measures volume. A claim needs independent outcome checks in relevant contexts. A saved rehearsal is a review aid; it does not verify behavior in the original application.")
    MainGui.Add("Button", "x20 y655 w190 h30", "Open evidence / lessons").OnEvent("Click", LearningLab_Open)
    MainGui.Add("Button", "x225 y655 w160 h30", "Refresh overview").OnEvent("Click", FanHome_Refresh)
}

FanHome_Refresh(*) {
    global g_FanNav
    try {
        summary := Know_ReviewSummary()
        g_FanNav["summary"].Value := summary
    } catch as inventoryError
        g_FanNav["summary"].Value := "Inventory unavailable: " . inventoryError.Message . ". Open Review & apply and refresh after initialization."
}
