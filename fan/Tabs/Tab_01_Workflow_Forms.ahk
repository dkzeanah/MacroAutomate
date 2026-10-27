; ===============================================================================
; Tabs\Tab_01_Workflow_Forms.ahk
; TAB 1 Workflow: guided action form engine, choices, coordinate manager
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================


ToggleAdvancedStepFields(*) {
    global AdvancedStepCheck, QualPatternLabel, QualPatternDD, QualWindowLabel, QualWindowEdit, FailsafeCloseCheck
    showAdvanced := AdvancedStepCheck.Value = 1
    for ctrl in [QualPatternLabel, QualPatternDD, QualWindowLabel, QualWindowEdit, FailsafeCloseCheck]
        ctrl.Visible := showAdvanced
}

ApplyActionFieldLayout(*) {
    global ActionDD, TargetFieldLabel, TargetFieldHint, TargetDD
    global ParamFieldLabel, ParamFieldHint, ParamCombo, ChoicesLabel, ChoicesDD, UseChoiceBtn, RefreshChoicesBtn, OCRRegionBtn, PickWindowBtn, QuickAddBtn

    action := ActionDD.Text
    spec := GetWorkflowActionSpec(action)
    TargetFieldLabel.Text := spec["targetLabel"] != "" ? spec["targetLabel"] . ":" : ""
    TargetFieldHint.Text := spec["targetHint"] != "" ? "(" . spec["targetHint"] . ")" : ""
    ParamFieldLabel.Text := spec["paramLabel"] != "" ? spec["paramLabel"] . ":" : ""
    ParamFieldHint.Text := spec["paramHint"] != "" ? "(" . spec["paramHint"] . ")" : ""

    for ctrl in [TargetFieldLabel, TargetFieldHint, TargetDD]
        ctrl.Visible := spec["targetUsed"]
    for ctrl in [ParamFieldLabel, ParamFieldHint, ParamCombo]
        ctrl.Visible := spec["paramUsed"]

    hasSuggestions := spec["choiceField"] != ""
    for ctrl in [ChoicesLabel, ChoicesDD, UseChoiceBtn, RefreshChoicesBtn]
        ctrl.Visible := hasSuggestions
    isOCR := action = "OCR Region" || action = "OCR Click" || action = "OCR Wait" || action = "Grab OCR to Var"
    OCRRegionBtn.Visible := isOCR
    PickWindowBtn.Visible := IsWindowAction(action) && !isOCR
    QuickAddBtn.Visible := !isOCR && !IsWindowAction(action)
    TargetDD.ToolTip := spec["targetHint"]
    ParamCombo.ToolTip := spec["paramHint"]
}


; Actions where a window title is a primary field, so they get the dedicated
; "Pick Window" button. (OCR actions also target a window via "window:Title",
; but they already have the OCR Area button in this slot - their window picker
; lives in the guided Add Step form instead. See PopulateChoices.)
IsWindowAction(action) {
    switch action {
        case "Activate Window", "Find & Click Loop", "Replay Window Mouse",
             "Wait for Window", "Wait Window Closed", "Popup Detect":
            return true
    }
    return false
}

; Category filter: narrow the action dropdown to one kind of task.
OnCategoryChange(*) {
    global ActionCategoryDD, ActionDD
    RefreshActionList()
    OnActionChange()
}

RefreshActionList() {
    global ActionCategoryDD, ActionDD
    cat := ActionCategoryDD.Text
    filtered := []
    for name in GetWorkflowActionNames()
        if cat = "(All)" || GetActionCategory(name) = cat
            filtered.Push(name)
    ActionDD.Delete()
    ActionDD.Add(filtered)
    ActionDD.Choose(1)
}

; ── Pick Window: a live dropdown of every open window ─────────────────────────
; Builds a menu of current top-level windows (full titles, exe shown for
; disambiguation) and inserts the selection into the correct field, formatted
; for whichever action is selected. No hand-typing of window titles.
PickWindow(*) {
    global g_PickWindowMap
    g_PickWindowMap := Map()
    m := Menu()
    count := 0
    for hwnd in WinGetList() {
        title := ""
        try title := WinGetTitle(hwnd)
        if (title = "" || title = "Program Manager")
            continue
        exe := ""
        try exe := WinGetProcessName(hwnd)
        label := StrLen(title) > 60 ? SubStr(title, 1, 57) . "..." : title
        if exe != ""
            label .= "   [" . exe . "]"
        base := label, n := 1
        while g_PickWindowMap.Has(label) {
            n += 1
            label := base . " (" . n . ")"
        }
        g_PickWindowMap[label] := title   ; keep the FULL, untruncated title
        m.Add(label, PickWindowChosen)
        count += 1
    }
    if count = 0 {
        MsgBoxTop("No open windows found to pick from.", "Pick Window")
        return
    }
    m.Show()
}

PickWindowChosen(itemName, itemPos, myMenu) {
    global g_PickWindowMap
    title := (IsSet(g_PickWindowMap) && g_PickWindowMap.Has(itemName)) ? g_PickWindowMap[itemName] : itemName
    InsertWindowIntoField(title)
}

; Put a chosen window title into the right field for the current action.
InsertWindowIntoField(title) {
    global ActionDD, TargetDD, ParamCombo
    action := ActionDD.Text
    switch action {
        case "Activate Window":
            ParamCombo.Text := title
        case "OCR Region", "OCR Click", "OCR Wait", "Grab OCR to Var":
            TargetDD.Text := "window:" . title
        case "Find & Click Loop":
            ParamCombo.Text := UpsertLoopOption(ParamCombo.Text, "win", title)
        case "Popup Detect":
            ParamCombo.Text := UpsertLoopOption(ParamCombo.Text, "win", title)
        case "Wait for Window", "Wait Window Closed":
            ParamCombo.Text := UpsertLoopOption(ParamCombo.Text, "title", title)
        case "Replay Window Mouse":
            TargetDD.Text := title
        default:
            ParamCombo.Text := title
    }
    ShowStatus("Window set: " . title, "ok")
}

; Set/replace one key in a "key=value; key=value" options string, preserving the
; other keys and emitting a clean, canonically-ordered string. Used to drop a
; picked window into the Find & Click Loop options without disturbing the rest.
UpsertLoopOption(optionsStr, key, value) {
    opt := ParseLoopOptions(optionsStr)
    opt[StrLower(key)] := value
    order  := ["win", "scroll", "settle", "scrollsettle", "maxclicks", "maxscrolls", "button", "clicks", "top", "focus", "popup", "popupdo", "tol"]
    labels := Map("win","win", "scroll","scroll", "settle","settle", "scrollsettle","scrollSettle"
                , "maxclicks","maxClicks", "maxscrolls","maxScrolls", "button","button", "clicks","clicks"
                , "top","top", "focus","focus", "popup","popup", "popupdo","popupDo", "tol","tol")
    parts := []
    for k in order {
        if opt.Has(k) {
            parts.Push(labels[k] . "=" . opt[k])
            opt.Delete(k)
        }
    }
    for k, v in opt   ; any non-standard keys the user added
        parts.Push(k . "=" . v)
    out := ""
    for i, p in parts
        out .= (i > 1 ? "; " : "") . p
    return out
}


; ═══════════════════════════════════════════════════════════════════════════════
; GUIDED ACTION FORM
; ═══════════════════════════════════════════════════════════════════════════════
; Every action gets a structured form of dropdowns, pickers and live window
; lists, so a workflow step is built by choosing - never by hand-writing
; parameter syntax. Each value control is still an editable ComboBox (max
; flexibility), and the Expert row can override the composed strings entirely.

FormField(key, label, kind, items := "", default := "", hint := "", required := false, w := 0) {
    return Map("key", key, "label", label, "kind", kind, "items", items,
               "default", default, "hint", hint, "required", required, "w", w)
}

ArrHas(arr, val) {
    for v in arr
        if v = val
            return true
    return false
}

GetSavedCoordChoices() {
    global g_Coordinates
    choices := ["demo:notepadedit", "demo:single", "demo:double", "demo:triple", "demo:right", "demo:hover"]
    for name, coord in g_Coordinates
        choices.Push(name . " (" . coord["x"] . "," . coord["y"] . ")")
    return choices
}

GetSavedDragChoices() {
    global g_Coordinates
    choices := []
    for name, coord in g_Coordinates {
        if coord.Has("endX")
            choices.Push(name . " (" . coord["x"] . "," . coord["y"] . "->" . coord["endX"] . "," . coord["endY"] . ")")
    }
    return choices
}

GetSavedPatternChoices() {
    global g_Patterns
    choices := []
    for name, _ in g_Patterns
        choices.Push(name)
    return choices
}

GetSequenceVarChoices() {
    global g_ExtractedData
    choices := GetSequenceVariables()
    for name, _ in g_ExtractedData {
        if !ArrHas(choices, name)
            choices.Push(name)
    }
    return choices
}

; First word of a "value (description)" choice.
ChoiceValue(text) {
    return Trim(StrSplit(text, " ")[1])
}

; The structured form layout for one action. Fields render top-to-bottom, two
; narrow fields per row; a field with w>0 takes a whole row.
GetActionFormSpec(action) {
    switch action {
        ; ─── Mouse ───────────────────────────────────────────────────────────
        case "Click":
            return Map("fields", [
                    FormField("pos", "Click where", "coordpick", GetSavedCoordChoices(), "", "Saved position, demo:key, or x,y", true),
                    FormField("count", "Click count", "combo", ["1", "2", "3", "4", "5"], "1")],
                "targetFmt", "{pos}", "paramFmt", "{count}",
                "help", "Clicks once at the position. Pick a saved point, a Demo Lab control, or press the pin to capture a point on screen. Click count of 2 = double click.")
        case "Double Click", "Triple Click", "Right Click":
            return Map("fields", [
                    FormField("pos", "Where", "coordpick", GetSavedCoordChoices(), "", "Saved position, demo:key, or x,y", true)],
                "targetFmt", "{pos}", "paramFmt", "",
                "help", "Performs " . action . " at the position. Pick from the list or capture a point with the pin button.")
        case "Drag":
            return Map("fields", [
                    FormField("saved", "Saved drag", "combo", GetSavedDragChoices(), "", "Pick a captured drag (leave empty to use Raw)", false),
                    FormField("raw", "Raw drag", "dragpick", "", "", "x1,y1->x2,y2 - or press the pin and click start, then end", false)],
                "composer", "drag", "paramFmt", "",
                "help", "Press-and-drag between two points. Use a captured drag from the list, or press the pin and click the start point, then the end point.")
        case "Relative Click":
            return Map("fields", [
                    FormField("pos", "Saved offset", "combo", GetRelativeCoordChoices(), "", "Captured with the Rel. button in Position Tools", true)],
                "targetFmt", "{pos}", "paramFmt", "",
                "help", "Clicks at a position relative to the current mouse location.")
        case "Menu Select":
            return Map("fields", [
                    FormField("downs", "Down presses", "combo", ["1", "2", "3", "4", "5", "6", "7", "8"], "3", "How many times to move down the menu")],
                "targetFmt", "", "paramFmt", "{downs}",
                "help", "Moves down through the open menu that many times, then presses Enter.")
        case "Scroll":
            return Map("fields", [
                    FormField("amount", "Scroll amount", "combo", ["-10", "-5", "-3", "-1", "1", "3", "5", "10"], "-3", "Negative = down, positive = up")],
                "targetFmt", "", "paramFmt", "{amount}",
                "help", "Scrolls the wheel under the mouse. Negative scrolls down, positive scrolls up.")
        case "Idle Mouse":
            return Map("fields", [
                    FormField("seconds", "Seconds", "combo", ["5", "15", "30", "60", "0 (until stopped)"], "30", "0 = keep going until you stop it")],
                "targetFmt", "", "paramFmt", "{seconds}",
                "help", "Gently moves the mouse so the computer does not lock or sleep.")
        case "Hover Mouse":
            return Map("fields", [
                    FormField("pos", "Move to", "coordpick", GetSavedCoordChoices(), "", "Saved position, demo:key, or x,y", true)],
                "targetFmt", "{pos}", "paramFmt", "",
                "help", "Moves the mouse to the position without clicking.")

        ; ─── Keyboard ────────────────────────────────────────────────────────
        case "Send Keys":
            return Map("fields", [
                    FormField("keys", "Keys to send", "combo", ["^c", "^v", "^x", "^a", "^s", "^z", "{Enter}", "{Tab}", "{Escape}", "{Space}", "{Up}", "{Down}", "{Left}", "{Right}", "{F5}", "!{Tab}", "!{F4}"], "^c", "^=Ctrl +=Shift !=Alt #=Win {Key}=special", true)],
                "targetFmt", "", "paramFmt", "{keys}",
                "help", "Sends keyboard input. Pick a common shortcut or type any AutoHotkey key combination.")
        case "Type Text":
            return Map("fields", [
                    FormField("text", "Text to type", "combo", "", "", "Supports $var.name substitutions", true, 530)],
                "targetFmt", "", "paramFmt", "{text}",
                "help", "Types the text character by character - slower than Send Keys but more reliable for real text.")
        case "Key Chord":
            return Map("fields", [
                    FormField("modifier", "Modifier", "combo", ["#", "^", "!", "+", "^+", "!+"], "#", "#=Win ^=Ctrl !=Alt +=Shift", true),
                    FormField("key", "Key", "combo", ["1", "2", "3", "4", "5", "c", "v", "a", "s", "{Tab}", "{Enter}"], "1", "", true),
                    FormField("count", "Times", "combo", ["1", "2", "3", "4", "5"], "1")],
                "targetFmt", "", "paramFmt", "{modifier},{key},{count}",
                "help", "Sends a modifier + key combination the requested number of times.")
        case "Paste":
            return Map("fields", [],
                "targetFmt", "", "paramFmt", "",
                "help", "Pastes the current clipboard contents (Ctrl+V).")

        ; ─── Windows ─────────────────────────────────────────────────────────
        case "Activate Window":
            return Map("fields", [
                    FormField("window", "Window", "window", GetWindowTitlesFull(), "", "Pick from the live list, refresh, or type part of a title", true)],
                "targetFmt", "", "paramFmt", "{window}",
                "help", "Brings the chosen window to the front. Use the refresh button if the window just opened.")
        case "Taskbar Activate":
            return Map("fields", [
                    FormField("position", "Taskbar position", "combo", ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], "1", "", true),
                    FormField("count", "Times", "combo", ["1", "2", "3"], "1")],
                "targetFmt", "", "paramFmt", "{position},{count}",
                "help", "Activates the app pinned at that taskbar slot (Win+number).")
        case "Run Program":
            return Map("fields", [
                    FormField("program", "Program / command", "combo", GetCommonPrograms(), "notepad.exe", "exe, document, URL, or demo:lab", true)],
                "targetFmt", "", "paramFmt", "{program}",
                "help", "Starts an executable, opens a document or URL, or runs a command.")
        case "Wait for Window":
            return Map("fields", [
                    FormField("title", "Wait for this window", "window", GetWindowTitlesFull(), "", "A popup or dialog that is about to appear", true),
                    FormField("timeout", "Give up after (ms)", "combo", ["1000", "3000", "5000", "10000", "30000"], "5000")],
                "composer", "loopkv", "paramFmt", "title={title}; timeout={timeout}",
                "help", "Pauses until the chosen window appears - perfect for popup dialogs. Continues the moment it shows up.")
        case "Wait Window Closed":
            return Map("fields", [
                    FormField("title", "Wait until this closes", "window", GetWindowTitlesFull(), "", "A loading box or popup that should disappear", true),
                    FormField("timeout", "Give up after (ms)", "combo", ["1000", "3000", "5000", "10000", "30000"], "5000")],
                "composer", "loopkv", "paramFmt", "title={title}; timeout={timeout}",
                "help", "Pauses until the chosen window disappears - for example after a save finishes.")

        ; ─── Patterns ────────────────────────────────────────────────────────
        case "Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick":
            return Map("fields", [
                    FormField("pattern", "Pattern to find", "pattern", GetSavedPatternChoices(), "", "A picture captured in the Patterns tab", true)],
                "targetFmt", "{pattern}", "paramFmt", "",
                "help", "Searches the screen for the captured picture and performs " . action . " on it.")
        case "Find & Drag":
            return Map("fields", [
                    FormField("pattern", "Pattern to grab", "pattern", GetSavedPatternChoices(), "", "A picture captured in the Patterns tab", true),
                    FormField("destination", "Drag to", "pointpick", "", "", "endX,endY - press the pin to capture the end point", true)],
                "targetFmt", "{pattern}", "paramFmt", "{destination}",
                "help", "Finds the picture on screen and drags it to the destination point.")
        case "Wait for Pattern":
            return Map("fields", [
                    FormField("pattern", "Wait until this appears", "pattern", GetSavedPatternChoices(), "", "", true),
                    FormField("timeout", "Give up after (ms)", "combo", ["1000", "3000", "5000", "10000", "30000"], "5000")],
                "targetFmt", "{pattern}", "paramFmt", "{timeout}",
                "help", "Pauses until the picture appears on screen, or until the timeout.")
        case "Wait Until Gone":
            return Map("fields", [
                    FormField("pattern", "Wait until this disappears", "pattern", GetSavedPatternChoices(), "", "", true),
                    FormField("timeout", "Give up after (ms)", "combo", ["1000", "3000", "5000", "10000", "30000"], "5000")],
                "targetFmt", "{pattern}", "paramFmt", "{timeout}",
                "help", "Pauses until the picture is no longer on screen, or until the timeout.")

        ; ─── Looping ─────────────────────────────────────────────────────────
        case "Loop Start":
            return Map("fields", [
                    FormField("repeats", "Repeat this many times", "combo", ["2", "3", "5", "10", "25", "100", "forever"], "5", "forever = until ESC or Loop Break", true),
                    FormField("var", "Counter variable", "combo", ["i", "n", "loopIndex", "item"], "i", "Inside the loop this is $var.i = 1, 2, 3...")],
                "composer", "loopkv", "paramFmt", "count={repeats}; var={var}",
                "help", "Opens a loop. Every step between this and Loop End repeats."
                . "`n$var.<name> = the current pass (1, 2, 3...), $var.loopCount = the total."
                . "`nEverything the loop remembers (variables, Popup Detect memory) stays from one pass to the next.")
        case "Loop End":
            return Map("fields", [],
                "targetFmt", "", "paramFmt", "",
                "help", "Closes the loop body opened by Loop Start. The steps in between run again until the count is reached.")
        case "Loop Break":
            return Map("fields", [],
                "targetFmt", "", "paramFmt", "",
                "help", "Stops the current loop early and continues with the step after its Loop End.")
        case "Find & Click Loop":
            return Map("fields", [
                    FormField("pattern", "Pattern to click", "pattern", GetSavedPatternChoices(), "", "One item in the list", true),
                    FormField("win", "Work inside this window", "window", GetWindowTitlesFull(), "", "Lock the search & scrolling to one window (recommended)"),
                    FormField("scroll", "Scroll per round", "combo", ["-10", "-5", "-3", "-1", "1", "3", "5"], "-3", "Negative = scroll down"),
                    FormField("settle", "Pause after click (ms)", "combo", ["300", "600", "1000", "2000"], "600"),
                    FormField("maxClicks", "Stop after this many clicks", "combo", ["10", "25", "50", "90", "200"], "90"),
                    FormField("maxScrolls", "Empty scrolls = end of list", "combo", ["3", "6", "10"], "6"),
                    FormField("button", "Mouse button", "combo", ["Left", "Right"], "Left"),
                    FormField("clicks", "Clicks per find", "combo", ["1", "2", "3"], "1"),
                    FormField("top", "Jump to top first", "combo", ["", "home", "5", "10"], "", "(empty) = start where it is; home = Ctrl+Home; a number = wheel-ups"),
                    FormField("popup", "Handle popup with this title", "window", GetWindowTitlesFull(), "", "If this dialog appears mid-run, handle it and resume"),
                    FormField("popupDo", "Popup action", "combo", ["enter", "send:!s", "pattern:SaveBtn"], "enter", "enter / send:keys / pattern:name"),
                    FormField("tol", "Match tolerance", "combo", ["", "0.05", "0.1", "0.2"], "", "(empty) = default")],
                "composer", "loopkv",
                "paramFmt", "win={win}; scroll={scroll}; settle={settle}; maxClicks={maxClicks}; maxScrolls={maxScrolls}; button={button}; clicks={clicks}; top={top}; popup={popup}; popupDo={popupDo}; tol={tol}",
                "help", "Clicks the pattern, scrolls down, and repeats until the list is exhausted or the click limit is reached. ESC aborts.")
        case "Popup Detect":
            return Map("fields", [
                    FormField("win", "Watch this window", "window", GetWindowTitlesFull(), "", "Whole window - leave empty to watch a rectangle instead"),
                    FormField("region", "Or watch this rectangle", "region", ["0,0,800,600", "0,0," . A_ScreenWidth . "," . A_ScreenHeight], "", "Drag the frame button to select it"),
                    FormField("sensitivity", "Sensitivity", "combo", ["high (tiny change)", "medium (recommended)", "low (big change only)"], "medium (recommended)"),
                    FormField("mode", "When to check", "combo", ["now (check once)", "wait (wait for a change)"], "now (check once)"),
                    FormField("on", "If changed, then...", "combo", ["var (just remember)", "skip (skip next step)", "break (leave the loop)", "stop (stop workflow)"], "var (just remember)"),
                    FormField("timeout", "Timeout when waiting (ms)", "combo", ["1000", "3000", "5000", "10000", "30000"], "5000"),
                    FormField("var", "Result variable", "combo", ["popupChanged", "popup"], "popupChanged", "Set to 1 when changed, 0 when not")],
                "composer", "popupdetect",
                "paramFmt", "win={win}; region={region}; sensitivity={sensitivity}; on={on}; mode={mode}; timeout={timeout}; var={var}",
                "help", "Remembers what the window/rectangle looks like at the top of the loop,"
                . " then flags when it changes drastically - a popup opening, a dialog appearing."
                . "`nThe memory is kept on the step, so each pass of the loop compares against the"
                . " same starting state. Use with Loop Start/End for popup-aware workflows.")

        ; ─── OCR ─────────────────────────────────────────────────────────────
        case "OCR Region":
            return Map("fields", [
                    FormField("win", "Read this window", "window", GetWindowTitlesFull(), "", "Leave empty to use a rectangle instead"),
                    FormField("region", "Or read this rectangle", "region", ["0,0," . A_ScreenWidth . "," . A_ScreenHeight], "", "Drag the frame button to select it"),
                    FormField("output", "Put the text into", "combo", ["copy (clipboard)", "var:ocrText", "var:newVar", "split:tab", "split:line"], "copy (clipboard)")],
                "composer", "ocr", "paramFmt", "{output}",
                "help", "Reads the text inside the window or rectangle and copies it to the clipboard or stores it in a variable.")
        case "OCR Click":
            return Map("fields", [
                    FormField("win", "Search this window", "window", GetWindowTitlesFull(), "", "Leave empty to use a rectangle instead"),
                    FormField("region", "Or search this rectangle", "region", ["0,0," . A_ScreenWidth . "," . A_ScreenHeight], "", "Drag the frame button to select it"),
                    FormField("text", "Click the text that says", "combo", "", "", "For example: Submit, OK, Save...", true)],
                "composer", "ocr", "paramFmt", "{text}",
                "help", "Reads the area, finds the text you typed, and clicks its center.")
        case "OCR Wait":
            return Map("fields", [
                    FormField("win", "Watch this window", "window", GetWindowTitlesFull(), "", "Leave empty to use a rectangle instead"),
                    FormField("region", "Or watch this rectangle", "region", ["0,0," . A_ScreenWidth . "," . A_ScreenHeight], "", "Drag the frame button to select it"),
                    FormField("condition", "Wait for", "combo", ["text:READY,5000", "5000", "text:Submit,10000"], "5000", "text:WORD,ms = wait for that word; plain number = any text")],
                "composer", "ocr", "paramFmt", "{condition}",
                "help", "Waits until the area shows text - optionally a specific word - or until the timeout.")
        case "Grab OCR to Var":
            return Map("fields", [
                    FormField("win", "Read this window", "window", GetWindowTitlesFull(), "", "Leave empty to use a rectangle instead"),
                    FormField("region", "Or read this rectangle", "whregion", ["0,0," . A_ScreenWidth . "," . A_ScreenHeight], "", "Drag the frame button to select it"),
                    FormField("var", "Store in variable", "combo", GetSequenceVarChoices(), "ocrText", "Then use $var.<name> in later steps", true)],
                "composer", "ocrawh", "paramFmt", "{var}",
                "help", "Reads the text and stores it in a workflow variable for later steps.")
        case "OCR Full Screen to Var":
            return Map("fields", [
                    FormField("var", "Store in variable", "combo", GetSequenceVarChoices(), "fullScreenOCR", "", true)],
                "targetFmt", "", "paramFmt", "{var}",
                "help", "Reads the whole screen and stores every recognized word in the variable.")
        case "Load OCR Revolver":
            return Map("fields", [
                    FormField("split", "Split the text by", "combo", ["tab", "line", "count", "char"], "tab")],
                "targetFmt", "", "paramFmt", "{split}",
                "help", "Splits the latest OCR text into pieces and loads them into the revolver, one per paste.")
        case "Fire OCR Revolver":
            return Map("fields", [],
                "targetFmt", "", "paramFmt", "",
                "help", "Pastes the next piece from the OCR revolver.")

        ; ─── Clipboard & Text ────────────────────────────────────────────────
        case "Set Clipboard":
            return Map("fields", [
                    FormField("text", "Clipboard text", "combo", GetSequenceVarChoices(), "", "Use $var.name or plain text", true)],
                "targetFmt", "", "paramFmt", "{text}",
                "help", "Puts the text into the clipboard. Workflow variables like $var.name are expanded.")
        case "Insert Field":
            return Map("fields", [
                    FormField("field", "Field to insert", "combo", GetExtractedFieldNames(), "", "From the clipboard extraction tab", true)],
                "targetFmt", "", "paramFmt", "{field}",
                "help", "Types one of the named fields extracted from the clipboard.")
        case "Insert Date":
            return Map("fields", [],
                "targetFmt", "", "paramFmt", "",
                "help", "Types today's date.")
        case "Parse Clipboard":
            return Map("fields", [],
                "targetFmt", "", "paramFmt", "",
                "help", "Runs the clipboard extraction rules and stores the found fields.")
        case "Load Revolver":
            return Map("fields", [],
                "targetFmt", "", "paramFmt", "",
                "help", "Loads the clipboard fields into the paste revolver.")
        case "Fire Revolver":
            return Map("fields", [],
                "targetFmt", "", "paramFmt", "",
                "help", "Pastes the next revolver value.")
        case "Fire Revolver+Enter":
            return Map("fields", [],
                "targetFmt", "", "paramFmt", "",
                "help", "Pastes the next revolver value and presses Enter.")
        case "Format Clipboard":
            return Map("fields", [
                    FormField("format", "Format", "combo", ["uppercase", "lowercase", "titlecase", "trim", "invoice", "receipt", "date_iso", "[{clip}]"], "uppercase")],
                "targetFmt", "", "paramFmt", "{format}",
                "help", "Transforms the clipboard text with a preset, or a custom template containing {clip}.")
        case "Append to Clipboard":
            return Map("fields", [
                    FormField("text", "Text to append", "combo", GetSequenceVarChoices(), "", "", true)],
                "targetFmt", "", "paramFmt", "{text}",
                "help", "Adds the text to the end of the current clipboard contents.")
        case "Prepend to Clipboard":
            return Map("fields", [
                    FormField("text", "Text to prepend", "combo", GetSequenceVarChoices(), "", "", true)],
                "targetFmt", "", "paramFmt", "{text}",
                "help", "Adds the text to the beginning of the current clipboard contents.")
        case "Extract from Clipboard":
            return Map("fields", [
                    FormField("rule", "Extraction rule", "combo", ["between:start|end", "field:,|1", "regex:\\d+"], "between:start|end")],
                "targetFmt", "", "paramFmt", "{rule}",
                "help", "Keeps only part of the clipboard. between:start|end, field:delimiter|index, or regex:pattern.")

        ; ─── Variables & Logic ───────────────────────────────────────────────
        case "Set Variable":
            return Map("fields", [
                    FormField("var", "Variable name", "combo", GetSequenceVarChoices(), "counter", "Letters, numbers and _ only", true),
                    FormField("value", "Value", "combo", "", "", "Text or $var.other", true)],
                "targetFmt", "{var}", "paramFmt", "{value}",
                "help", "Creates or replaces a workflow variable. Use it later as $var.<name>.")
        case "Grab Clipboard":
            return Map("fields", [
                    FormField("var", "Store clipboard in", "combo", GetSequenceVarChoices(), "clipboardText", "", true)],
                "targetFmt", "{var}", "paramFmt", "",
                "help", "Stores the current clipboard text in a workflow variable.")
        case "If Contains":
            return Map("fields", [
                    FormField("var", "Look inside variable", "combo", GetSequenceVarChoices(), "", "", true),
                    FormField("text", "Must contain", "combo", "", "", "Not case-sensitive", true)],
                "targetFmt", "{var}", "paramFmt", "{text}",
                "help", "Runs the next enabled step only when the variable contains this text; otherwise that one step is skipped.")
        case "If Variable":
            return Map("fields", [
                    FormField("var", "Compare variable", "combo", GetSequenceVarChoices(), "", "", true),
                    FormField("op", "Is...", "combo", ["=", "!=", ">", "<", ">=", "<="], "=", "", true),
                    FormField("value", "This value", "combo", "", "", "", true)],
                "composer", "ifvar", "paramFmt", "",
                "help", "Compares a variable with a value. If the comparison is false, the next enabled step is skipped.")
        case "Use Var Paste":
            return Map("fields", [
                    FormField("text", "Text to paste", "combo", GetSequenceVarChoices(), "", "Variables like $var.name are expanded", true)],
                "targetFmt", "", "paramFmt", "{text}",
                "help", "Expands workflow variables and pastes the result.")
        case "Stop Execution":
            return Map("fields", [],
                "targetFmt", "", "paramFmt", "",
                "help", "Stops the current workflow immediately.")
        case "Run Sequence":
            return Map("fields", [
                    FormField("seq", "Workflow to run", "combo", GetSavedSequenceNames(), "", "", true)],
                "targetFmt", "", "paramFmt", "{seq}",
                "help", "Runs another saved workflow as part of this one. Variables carry over; recursive calls are blocked.")

        ; ─── Tracking ────────────────────────────────────────────────────────
        case "Click Element":
            return Map("fields", [
                    FormField("element", "Element", "combo", GetTrackedElementNames(), "", "From the Snapshot Viewer", true),
                    FormField("button", "Button", "combo", ["Left", "Right", "Middle", "Left,2"], "Left")],
                "targetFmt", "{element}", "paramFmt", "{button}",
                "help", "Finds a named element on screen and clicks it.")
        case "Hover Element":
            return Map("fields", [
                    FormField("element", "Element", "combo", GetTrackedElementNames(), "", "From the Snapshot Viewer", true)],
                "targetFmt", "{element}", "paramFmt", "",
                "help", "Moves the mouse onto a named element without clicking.")
        case "Wait Element":
            return Map("fields", [
                    FormField("element", "Element", "combo", GetTrackedElementNames(), "", "From the Snapshot Viewer", true),
                    FormField("timeout", "Give up after (ms)", "combo", ["1000", "3000", "5000", "10000"], "5000")],
                "targetFmt", "{element}", "paramFmt", "{timeout}",
                "help", "Waits until a named element appears on screen.")
        case "Replay Window Mouse":
            return Map("fields", [
                    FormField("window", "Tracked window", "window", GetWindowTitlesFull(), "", "A window with recorded mouse movement", true),
                    FormField("speed", "Speed", "combo", ["1.0", "0.5", "2.0", "1.0,clicks"], "1.0")],
                "targetFmt", "{window}", "paramFmt", "{speed}",
                "help", "Replays the most recent recorded mouse movement for that window.")
        case "Research Search":
            return Map("fields", [
                    FormField("query", "Search for", "combo", "", "", "", true)],
                "targetFmt", "", "paramFmt", "{query}",
                "help", "Stores the query in the research database and searches for it in the browser.")
        case "Research Capture Links":
            return Map("fields", [
                    FormField("source", "Take links from", "combo", ["screen", "clip"], "screen")],
                "targetFmt", "", "paramFmt", "{source}",
                "help", "Harvests result links for the current query - by reading the page, or from the clipboard.")
        case "Research Launch Next":
            return Map("fields", [],
                "targetFmt", "", "paramFmt", "",
                "help", "Opens the next pending result link for the current query.")
        case "Research Add Insight":
            return Map("fields", [
                    FormField("insight", "Key takeaway", "combo", "", "", "", true)],
                "targetFmt", "", "paramFmt", "{insight}",
                "help", "Attaches a key takeaway to the current query and marks the link done.")

        ; ─── Timing & Notices ────────────────────────────────────────────────
        case "Wait":
            return Map("fields", [
                    FormField("ms", "Pause for (ms)", "combo", ["100", "200", "500", "1000", "2000", "3000", "5000", "10000"], "1000", "1000 = 1 second")],
                "targetFmt", "", "paramFmt", "{ms}",
                "help", "Pauses the workflow for the chosen time.")
        case "Show Notification":
            return Map("fields", [
                    FormField("title", "Title", "combo", "", "Done", "", true),
                    FormField("message", "Message", "combo", GetSequenceVarChoices(), "", "Variables like $var.name are expanded", true),
                    FormField("seconds", "Show for (seconds)", "combo", ["1", "2", "3", "5", "10"], "3")],
                "composer", "notify", "paramFmt", "",
                "help", "Shows a desktop notification.")
    }

    ; Unknown/legacy action: generic fields, still fully editable.
    return Map("fields", [
            FormField("target", "Target", "combo", "", "", "", false, 530),
            FormField("param", "Parameter", "combo", "", "", "", false, 530)],
        "targetFmt", "{target}", "paramFmt", "{param}",
        "help", "This action has no guided form yet - the two fields are passed through as-is.")
}

GetRelativeCoordChoices() {
    global g_Coordinates
    choices := []
    for name, coord in g_Coordinates {
        if coord.Has("relative") && coord["relative"]
            choices.Push(name . " (+" . coord["x"] . ",+" . coord["y"] . ")")
    }
    return choices
}

GetExtractedFieldNames() {
    global g_ExtractedData
    names := []
    for name, _ in g_ExtractedData
        names.Push(name)
    return names
}

GetSavedSequenceNames() {
    global g_Sequences
    names := []
    for name, _ in g_Sequences
        names.Push(name)
    return names
}

; Replace {key} placeholders with collected values (empty when missing).
FillTemplate(tmpl, values) {
    if tmpl = ""
        return ""
    out := tmpl
    for key, val in values {
        out := StrReplace(out, "{" . key . "}", val = "" ? "" : String(val))
    }
    out := RegExReplace(out, "\{\w+\}", "")   ; drop any placeholder without a value
    return out
}

; "key={key}; key={key}" template: drop pairs whose value is empty.
FillKvTemplate(tmpl, values) {
    if tmpl = ""
        return ""
    parts := []
    for seg in StrSplit(tmpl, ";") {
        seg := Trim(seg)
        if seg = ""
            continue
        if !RegExMatch(seg, "\{(\w+)\}", &m)
            continue
        val := values.Has(m[1]) ? String(values[m[1]]) : ""
        if Trim(val) = ""
            continue
        parts.Push(StrReplace(seg, "{" . m[1] . "}", val))
    }
    out := ""
    for i, p in parts
        out .= (i > 1 ? "; " : "") . p
    return out
}

; Compose the final target/param strings from collected form values.
ComposeFormValues(spec, values) {
    target := "", param := ""
    if spec.Has("composer") {
        switch spec["composer"] {
            case "drag":
                if Trim(String(values.Has("saved") ? values["saved"] : "")) != ""
                    target := CleanCoordChoice(values["saved"])
                else if Trim(String(values.Has("raw") ? values["raw"] : "")) != ""
                    param := values["raw"]
            case "ocr":
                if Trim(String(values.Has("win") ? values["win"] : "")) != ""
                    target := "window:" . values["win"]
                else if Trim(String(values.Has("region") ? values["region"] : "")) != ""
                    target := values["region"]
                for k in ["output", "text", "condition"]
                    if values.Has(k) && Trim(String(values[k])) != "" {
                        param := values[k]
                        break
                    }
            case "ocrawh":
                if Trim(String(values.Has("win") ? values["win"] : "")) != ""
                    target := "window:" . values["win"]
                else if Trim(String(values.Has("region") ? values["region"] : "")) != ""
                    target := values["region"]
                param := values.Has("var") ? values["var"] : ""
            case "ifvar":
                target := values.Has("var") ? values["var"] : ""
                op := values.Has("op") ? values["op"] : ""
                val := values.Has("value") ? values["value"] : ""
                if op != ""
                    param := op . "," . val
            case "notify":
                title := values.Has("title") ? values["title"] : ""
                message := values.Has("message") ? values["message"] : ""
                seconds := values.Has("seconds") ? ChoiceValue(values["seconds"]) : "3"
                param := title . "," . message . "," . seconds
            case "popupdetect":
                cleaned := Map()
                for k, v in values {
                    if k = "sensitivity" || k = "on" || k = "mode"
                        cleaned[k] := ChoiceValue(v)
                    else
                        cleaned[k] := v
                }
                param := FillKvTemplate(spec["paramFmt"], cleaned)
            case "loopkv":
                target := values.Has("pattern") ? values["pattern"] : ""
                param := FillKvTemplate(spec["paramFmt"], values)
        }
    } else {
        target := FillTemplate(spec.Has("targetFmt") ? spec["targetFmt"] : "", values)
        param := FillTemplate(spec.Has("paramFmt") ? spec["paramFmt"] : "", values)
    }
    if target != "" && (values.Has("pos") || values.Has("saved")) {
        target := CleanCoordChoice(target)
    }
    return Map("target", target, "param", param)
}

; "name (x,y)" -> "name"
CleanCoordChoice(text) {
    p := InStr(text, " (")
    if p
        return Trim(SubStr(text, 1, p - 1))
    return Trim(text)
}

; Turn an existing step's target/param back into form values (for editing).
ParseFormValues(action, target, param) {
    spec := GetActionFormSpec(action)
    values := Map()
    for f in spec["fields"]
        values[f["key"]] := f["default"]

    if spec.Has("composer") {
        switch spec["composer"] {
            case "drag":
                if Trim(target) != ""
                    values["saved"] := target
                else
                    values["raw"] := param
            case "ocr":
                if SubStr(Trim(target), 1, 7) = "window:"
                    values["win"] := SubStr(Trim(target), 8)
                else if Trim(target) != ""
                    values["region"] := Trim(target)
                if values.Has("output") && param != ""
                    values["output"] := param
                else if values.Has("text") && param != ""
                    values["text"] := param
                else if values.Has("condition") && param != ""
                    values["condition"] := param
            case "ocrawh":
                if SubStr(Trim(target), 1, 7) = "window:"
                    values["win"] := SubStr(Trim(target), 8)
                else if Trim(target) != ""
                    values["region"] := Trim(target)
                if param != ""
                    values["var"] := StrSplit(param, ",")[1]
            case "ifvar":
                if Trim(target) != ""
                    values["var"] := Trim(target)
                p := StrSplit(param, ",")
                if p.Length >= 1 && Trim(p[1]) != ""
                    values["op"] := Trim(p[1])
                if p.Length >= 2
                    values["value"] := Trim(p[2])
            case "notify":
                p := StrSplit(param, ",")
                if p.Length >= 1
                    values["title"] := p[1]
                if p.Length >= 2 {
                    if IsNumber(Trim(p[p.Length])) {
                        values["seconds"] := Trim(p[p.Length])
                        msg := ""
                        Loop p.Length - 2
                            msg .= (A_Index > 1 ? "," : "") . p[A_Index + 1]
                        values["message"] := msg
                    } else {
                        values["message"] := Trim(SubStr(param, InStr(param, ",") + 1))
                    }
                }
            case "popupdetect", "loopkv":
                opt := ParseLoopOptions(param)
                for k, v in opt {
                    if values.Has(k)
                        values[k] := v
                }
                if spec["composer"] = "loopkv" && Trim(target) != "" && values.Has("pattern")
                    values["pattern"] := Trim(target)
        }
        return values
    }

    targetFmt := spec.Has("targetFmt") ? spec["targetFmt"] : ""
    paramFmt := spec.Has("paramFmt") ? spec["paramFmt"] : ""
    if targetFmt != "" && Trim(target) != "" {
        if RegExMatch(targetFmt, "\{(\w+)\}", &m)
            values[m[1]] := Trim(target)
    }
    if paramFmt != "" && Trim(param) != "" {
        if InStr(paramFmt, "{modifier},{key},{count}") || InStr(paramFmt, "{position},{count}") {
            p := StrSplit(param, ",")
            if p.Length >= 1 && values.Has("modifier")
                values["modifier"] := Trim(p[1])
            if p.Length >= 2 && values.Has("key")
                values["key"] := Trim(p[2])
            if p.Length >= 3 && values.Has("count")
                values["count"] := Trim(p[3])
        } else if RegExMatch(paramFmt, "\{(\w+)\}", &m) {
            values[m[1]] := Trim(param)
        }
    }
    return values
}

; ── On-screen capture helpers for the form's pin / frame buttons ──────────────
CapturePointOnScreen(formGui) {
    formGui.Hide()
    Sleep(150)
    TrackToolTip("Click the target point...`nESC cancels")
    cancelled := false
    Hotkey("Escape", (*) => (cancelled := true), "On")
    while !GetKeyState("LButton", "P") && !cancelled
        Sleep(10)
    if cancelled {
        TrackToolTip()
        Hotkey("Escape", "Off")
        formGui.Show()
        return ""
    }
    MouseGetPos(&x, &y)
    TrackToolTip()
    Hotkey("Escape", "Off")
    formGui.Show()
    return x . "," . y
}

CaptureDragOnScreen(formGui) {
    formGui.Hide()
    Sleep(150)
    TrackToolTip("Click the DRAG START point...`nESC cancels")
    cancelled := false
    Hotkey("Escape", (*) => (cancelled := true), "On")
    while !GetKeyState("LButton", "P") && !cancelled
        Sleep(10)
    if cancelled {
        TrackToolTip()
        Hotkey("Escape", "Off")
        formGui.Show()
        return ""
    }
    MouseGetPos(&x1, &y1)
    while GetKeyState("LButton", "P")
        Sleep(10)
    TrackToolTip("Now click the DRAG END point...")
    while !GetKeyState("LButton", "P") && !cancelled
        Sleep(10)
    if cancelled {
        TrackToolTip()
        Hotkey("Escape", "Off")
        formGui.Show()
        return ""
    }
    MouseGetPos(&x2, &y2)
    TrackToolTip()
    Hotkey("Escape", "Off")
    formGui.Show()
    return x1 . "," . y1 . "->" . x2 . "," . y2
}

CaptureRegionOnScreen(formGui, whFormat := false) {
    formGui.Hide()
    Sleep(150)
    TrackToolTip("Drag a box around the region`nESC cancels")
    cancelled := false
    x2 := 0, y2 := 0
    Hotkey("Escape", (*) => (cancelled := true), "On")
    while !GetKeyState("LButton", "P") && !cancelled
        Sleep(10)
    if cancelled {
        TrackToolTip()
        Hotkey("Escape", "Off")
        formGui.Show()
        return ""
    }
    MouseGetPos(&x1, &y1)
    selBox := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "SelBox")
    selBox.BackColor := "00FF00"
    while GetKeyState("LButton", "P") && !cancelled {
        MouseGetPos(&x2, &y2)
        boxX := Min(x1, x2), boxY := Min(y1, y2)
        boxW := Max(Abs(x2 - x1), 10), boxH := Max(Abs(y2 - y1), 10)
        try selBox.Show("x" . boxX . " y" . boxY . " w" . boxW . " h" . boxH . " NoActivate")
        WinSetTransparent(180, selBox)
        Sleep(16)
    }
    TrackToolTip()
    Hotkey("Escape", "Off")
    try selBox.Destroy()
    if cancelled || Abs(x2 - x1) < 10 || Abs(y2 - y1) < 10 {
        formGui.Show()
        return ""
    }
    finalX1 := Min(x1, x2), finalY1 := Min(y1, y2)
    finalX2 := Max(x1, x2), finalY2 := Max(y1, y2)
    formGui.Show()
    if whFormat
        return finalX1 . "," . finalY1 . "," . (finalX2 - finalX1) . "," . (finalY2 - finalY1)
    return finalX1 . "," . finalY1 . "," . finalX2 . "," . finalY2
}

; ── Window picker helpers (form-local versions) ───────────────────────────────
PickWindowFromMenu(formGui) {
    global g_PickWindowMap, g_FormPickedWindow
    g_PickWindowMap := Map()
    g_FormPickedWindow := ""
    m := Menu()
    count := 0
    for hwnd in WinGetList() {
        title := ""
        try title := WinGetTitle(hwnd)
        if (title = "" || title = "Program Manager")
            continue
        exe := ""
        try exe := WinGetProcessName(hwnd)
        label := StrLen(title) > 60 ? SubStr(title, 1, 57) . "..." : title
        if exe != ""
            label .= "   [" . exe . "]"
        base := label, n := 1
        while g_PickWindowMap.Has(label) {
            n += 1
            label := base . " (" . n . ")"
        }
        g_PickWindowMap[label] := title
        m.Add(label, MenuPickWindowForm)
        count += 1
    }
    if count = 0 {
        MsgBoxTop("No open windows found to pick from.", "Pick Window")
        return ""
    }
    m.Show()
    return g_FormPickedWindow
}

MenuPickWindowForm(itemName, itemPos, myMenu) {
    global g_PickWindowMap, g_FormPickedWindow
    g_FormPickedWindow := (IsSet(g_PickWindowMap) && g_PickWindowMap.Has(itemName)) ? g_PickWindowMap[itemName] : itemName
}

; ── Form field rendering ──────────────────────────────────────────────────────
AddFormField(formGui, f, x, y, w, values) {
    global g_FormPickMap, g_FormFieldMap
    key := f["key"]
    kind := f["kind"]
    label := f["label"] . (f["required"] ? " *" : "")
    if f["hint"] != ""
        label .= "  (" . f["hint"] . ")"
    if StrLen(label) > 60
        label := SubStr(label, 1, 58) . ".."
    formGui.Add("Text", "x" . x . " y" . y . " w" . w . " c555555", label)

    ctrl := ""
    if kind = "edit" {
        ctrl := formGui.Add("Edit", "x" . x . " y" . (y + 15) . " w" . w)
        ctrl.Value := values.Has(key) ? String(values[key]) : ""
        g_FormFieldMap[key] := ctrl
        return
    }

    ctrlW := w
    btnW := 0
    switch kind {
        case "window": btnW := 70
        case "coordpick", "pointpick", "dragpick", "region", "whregion", "pattern": btnW := 28
        default: btnW := 0
    }
    if btnW > 0
        ctrlW := w - btnW - 6

    if kind = "dropdown" || kind = "combo" || btnW > 0 {
        ctrl := formGui.Add("ComboBox", "x" . x . " y" . (y + 15) . " w" . ctrlW)
        items := IsObject(f["items"]) ? f["items"] : (f["items"] != "" ? [f["items"]] : [])
        if items.Length > 0
            ctrl.Add(items)
        ctrl.Text := values.Has(key) ? String(values[key]) : ""
    } else if kind = "check" {
        ctrl := formGui.Add("CheckBox", "x" . x . " y" . (y + 15) . " w" . w, "")
    }
    g_FormFieldMap[key] := ctrl

    if btnW > 0 {
        bx := x + ctrlW + 6
        switch kind {
            case "window":
                btn1 := formGui.Add("Button", "x" . bx . " y" . (y + 14) . " w26 h22", "↻")
                btn2 := formGui.Add("Button", "x" . (bx + 30) . " y" . (y + 14) . " w40 h22", "▾ List")
                btn1.OnEvent("Click", FormPickHelper)
                btn2.OnEvent("Click", FormPickHelper)
                g_FormPickMap[btn1.Hwnd] := Map("combo", ctrl, "mode", "winrefresh", "gui", formGui)
                g_FormPickMap[btn2.Hwnd] := Map("combo", ctrl, "mode", "winpick", "gui", formGui)
            case "coordpick", "pointpick":
                btn := formGui.Add("Button", "x" . bx . " y" . (y + 14) . " w28 h22", "📍")
                btn.OnEvent("Click", FormPickHelper)
                g_FormPickMap[btn.Hwnd] := Map("combo", ctrl, "mode", "point", "gui", formGui)
            case "dragpick":
                btn := formGui.Add("Button", "x" . bx . " y" . (y + 14) . " w28 h22", "📍")
                btn.OnEvent("Click", FormPickHelper)
                g_FormPickMap[btn.Hwnd] := Map("combo", ctrl, "mode", "drag", "gui", formGui)
            case "region":
                btn := formGui.Add("Button", "x" . bx . " y" . (y + 14) . " w28 h22", "▭")
                btn.OnEvent("Click", FormPickHelper)
                g_FormPickMap[btn.Hwnd] := Map("combo", ctrl, "mode", "region", "gui", formGui)
            case "whregion":
                btn := formGui.Add("Button", "x" . bx . " y" . (y + 14) . " w28 h22", "▭")
                btn.OnEvent("Click", FormPickHelper)
                g_FormPickMap[btn.Hwnd] := Map("combo", ctrl, "mode", "whregion", "gui", formGui)
            case "pattern":
                btn := formGui.Add("Button", "x" . bx . " y" . (y + 14) . " w28 h22", "↻")
                btn.OnEvent("Click", FormPickHelper)
                g_FormPickMap[btn.Hwnd] := Map("combo", ctrl, "mode", "patternrefresh", "gui", formGui)
        }
    }
}

FormPickHelper(btn, *) {
    global g_FormPickMap
    if !g_FormPickMap.Has(btn.Hwnd)
        return
    info := g_FormPickMap[btn.Hwnd]
    combo := info["combo"]
    switch info["mode"] {
        case "winrefresh":
            combo.Delete()
            combo.Add(GetWindowTitlesFull())
            ShowStatus("Window list refreshed", "ok")
        case "winpick":
            title := PickWindowFromMenu(info["gui"])
            if title != ""
                combo.Text := title
        case "point":
            pt := CapturePointOnScreen(info["gui"])
            if pt != ""
                combo.Text := pt
        case "drag":
            pts := CaptureDragOnScreen(info["gui"])
            if pts != ""
                combo.Text := pts
        case "region":
            region := CaptureRegionOnScreen(info["gui"], false)
            if region != ""
                combo.Text := region
        case "whregion":
            region := CaptureRegionOnScreen(info["gui"], true)
            if region != ""
                combo.Text := region
        case "patternrefresh":
            combo.Delete()
            combo.Add(GetSavedPatternChoices())
            ShowStatus("Pattern list refreshed", "ok")
    }
}

; ── The guided form dialog ────────────────────────────────────────────────────
ShowActionForm(editRow := 0) {
    global MainGui, ActionDD, TargetDD, ParamCombo, g_CurrentSequenceSteps
    global g_ActionFormGui, g_FormPickMap, g_FormFieldMap
    global g_FormCurrentAction, g_FormCurrentSpec

    action := ActionDD.Text
    if action = "" {
        ShowStatus("Please select an action first", "fail")
        return
    }
    spec := GetActionFormSpec(action)

    target := TargetDD.Text
    param := ParamCombo.Text
    titleText := "Add Step"
    if editRow > 0 && editRow <= g_CurrentSequenceSteps.Length {
        step := g_CurrentSequenceSteps[editRow]
        target := step["target"]
        param := step["param"]
        titleText := "Edit Step " . editRow
    }
    values := ParseFormValues(action, target, param)

    formGui := Gui("+AlwaysOnTop +Owner" . MainGui.Hwnd, titleText . ": " . action)
    formGui.SetFont("s9", "Segoe UI")
    g_ActionFormGui := formGui
    g_FormPickMap := Map()
    g_FormFieldMap := Map()
    g_FormCurrentAction := action
    g_FormCurrentSpec := spec

    formGui.Add("Text", "x10 y10 w540 cBlue", action . "   -   " . GetActionCategory(action))
    formGui.Add("Text", "x10 y+4 w540 cGray", "Pick from the lists, or type your own value - nothing has to be written from scratch.")

    ; Pack narrow fields two-per-row; wide fields get their own row.
    rows := []
    pending := ""
    for f in spec["fields"] {
        if pending != "" {
            rows.Push([pending, f])
            pending := ""
        } else if f["w"] = 0 {
            pending := f
        } else {
            rows.Push([f, ""])
        }
    }
    if pending != ""
        rows.Push([pending, ""])

    y := 52
    for row in rows {
        f1 := row[1], f2 := row[2]
        if f2 != "" {
            AddFormField(formGui, f1, 10, y, 255, values)
            AddFormField(formGui, f2, 285, y, 255, values)
        } else {
            AddFormField(formGui, f1, 10, y, 530, values)
        }
        y += 38
    }

    ; What-this-does panel
    y += 2
    helpText := spec.Has("help") ? spec["help"] : ""
    formGui.Add("GroupBox", "x10 y" . y . " w530 h66", "What this does")
    formGui.Add("Edit", "x20 y" . (y + 16) . " w510 h40 ReadOnly Multi VScroll", helpText)
    y += 72

    ; Expert override row (max flexibility)
    formGui.Add("CheckBox", "x10 y" . (y + 2) . " vFormExpert", "Expert: use raw Target/Param instead")
    formGui.Add("Text", "x240 y" . (y + 4) . " w45", "Target:")
    formGui.Add("Edit", "x282 y" . (y + 1) . " w105 vFormExpTarget")
    formGui.Add("Text", "x395 y" . (y + 4) . " w45", "Param:")
    formGui.Add("Edit", "x432 y" . (y + 1) . " w108 vFormExpParam")
    y += 26

    submitLabel := editRow > 0 ? "✓ Save Changes" : "✓ Insert Step"
    formGui.Add("Button", "x10 y" . y . " w150 h28 Default cGreen", submitLabel).OnEvent("Click", (*) => FormSubmit(formGui, editRow, false))
    formGui.Add("Button", "x170 y" . y . " w90 h28", "Cancel").OnEvent("Click", (*) => formGui.Destroy())
    if editRow > 0
        formGui.Add("Button", "x270 y" . y . " w110 h28", "🛡 Failsafe...").OnEvent("Click", (*) => FormSubmit(formGui, editRow, true))

    formGui.Show()
}

FormSubmit(formGui, editRow, openFailsafe := false) {
    global g_FormFieldMap, g_FormCurrentSpec, g_FormCurrentAction
    global ActionDD, TargetDD, ParamCombo, g_CurrentSequenceSteps

    action := g_FormCurrentAction
    spec := g_FormCurrentSpec

    values := Map()
    for f in spec["fields"] {
        key := f["key"]
        val := ""
        if g_FormFieldMap.Has(key)
            val := g_FormFieldMap[key].Value
        values[key] := val
    }

    missing := ""
    for f in spec["fields"] {
        if f["required"] && Trim(String(values[f["key"]])) = "" {
            missing := missing = "" ? f["label"] : missing . ", " . f["label"]
        }
    }
    if missing != "" {
        MsgBoxTop("Please fill in: " . missing, action)
        return
    }

    ; Expert override wins when used.
    expTarget := "", expParam := "", expOn := false
    try expOn := formGui["FormExpert"].Value = 1
    try expTarget := formGui["FormExpTarget"].Value
    try expParam := formGui["FormExpParam"].Value
    if expOn && (Trim(expTarget) != "" || Trim(expParam) != "") {
        target := expTarget
        param := expParam
    } else {
        composed := ComposeFormValues(spec, values)
        target := composed["target"]
        param := composed["param"]
    }

    errors := ValidateStepParameters(action, target, param)
    if errors.Length > 0 {
        errText := ""
        for e in errors
            errText .= "• " . e . "`n"
        MsgBoxTop(errText, "Check these first")
        return
    }

    formGui.Destroy()

    if editRow > 0 {
        if editRow <= g_CurrentSequenceSteps.Length {
            g_CurrentSequenceSteps[editRow]["target"] := target
            g_CurrentSequenceSteps[editRow]["param"] := param
        }
        RefreshStepsLV()
        ShowStatus("Step " . editRow . " updated", "ok")
        ScheduleWorkflowAutosave()
        if openFailsafe
            EditStepFailsafeByRow(editRow)
    } else {
        TargetDD.Text := target
        ParamCombo.Text := param
        AddStepFromFields()
    }
}

OnActionChange(*) {
    global ActionDD, TargetDD, ParamCombo, ChoicesDD, ActionHelpTitle, ActionHelpText
    global QualPatternDD, QualWindowEdit, FailsafeCloseCheck, AdvancedStepCheck

    ; Never carry values from a previous action into an unrelated action.
    TargetDD.Text := ""
    ParamCombo.Text := ""
    try QualPatternDD.Choose(1)
    QualWindowEdit.Value := ""
    FailsafeCloseCheck.Value := 0
    AdvancedStepCheck.Value := 0
    ToggleAdvancedStepFields()

    UpdateHints()
    UpdateTargetDD()
    UpdateParamSuggestions()
    PopulateChoices()
    UpdateActionHelp()  ; V5.0: Update real-time help panel

    ; Auto-set smart defaults based on action
    action := ActionDD.Text

    ; OCR actions default to full screen
    if InStr(action, "OCR") || InStr(action, "Grab OCR") {
        screenW := A_ScreenWidth
        screenH := A_ScreenHeight
        fullScreen := "0,0," . screenW . "," . screenH

        ; Set Target for OCR Region/Click/Wait
        if action = "OCR Region" || action = "OCR Click" || action = "OCR Wait" {
            TargetDD.Text := fullScreen
        }

        ; Set Param defaults
        if action = "OCR Region" && ParamCombo.Text = "" {
            ParamCombo.Text := "var:ocrText"  ; Default: save to variable with clear name
        } else if action = "Grab OCR to Var" {
            TargetDD.Text := fullScreen
            ParamCombo.Text := "varName"
        } else if action = "OCR Full Screen to Var" {
            ParamCombo.Text := "fullScreenOCR"
        } else if action = "OCR Click" && ParamCombo.Text = "" {
            ParamCombo.Text := "Button"
        } else if action = "OCR Wait" && ParamCombo.Text = "" {
            ParamCombo.Text := "5000"
        }
    }

    ; Wait actions default to 1000ms
    if action = "Wait" && ParamCombo.Text = "" {
        ParamCombo.Text := "1000"
    }

    ; Idle Mouse default to 0 (indefinite)
    if action = "Idle Mouse" && ParamCombo.Text = "" {
        ParamCombo.Text := "0"
    }

    ; Show Notification default format
    if action = "Show Notification" && ParamCombo.Text = "" {
        ParamCombo.Text := "Title,Message,3"
    }

    if action = "Set Variable" {
        TargetDD.Text := "variableName"
        ParamCombo.Text := "value"
    } else if action = "Grab Clipboard" {
        TargetDD.Text := "clipboardText"
    } else if action = "If Contains" {
        TargetDD.Text := "variableName"
        ParamCombo.Text := "text to find"
    } else if action = "If Variable" {
        TargetDD.Text := "variableName"
        ParamCombo.Text := "=,value"
    } else if action = "Format Clipboard" {
        ParamCombo.Text := "uppercase"
    } else if action = "Extract from Clipboard" {
        ParamCombo.Text := "field:,|1"
    } else if action = "Find & Click Loop" {
        ; Pre-fill every knob with its default so all tweakable options are visible.
        ; Blank values (win=, top=, focus=, scrollSettle=, tol=) are optional; fill
        ; only the ones you need. Delete any you don't want to change.
        if ParamCombo.Text = ""
            ParamCombo.Text := "win=; scroll=-3; settle=600; maxClicks=90; maxScrolls=6; button=Left; clicks=1; top=; focus=; popup=; popupDo=enter; scrollSettle=; tol="
    } else if action = "Loop Start" {
        if ParamCombo.Text = ""
            ParamCombo.Text := "count=5; var=i"
    } else if action = "Popup Detect" {
        if ParamCombo.Text = ""
            ParamCombo.Text := "win=; region=0,0,800,600; sensitivity=medium; on=var; mode=now; timeout=5000; var=popupChanged"
    } else if action = "Wait for Window" || action = "Wait Window Closed" {
        if ParamCombo.Text = ""
            ParamCombo.Text := "title=; timeout=5000"
    }

    ; Pattern actions - show patterns in Choices
    ApplyActionFieldLayout()
    PopulateChoices()
    UpdateActionHelp()
}



; Refresh choices button handler

AddWorkflowTooltips() {
    global ActionDD, TargetDD, ParamCombo, ChoicesDD

    ActionDD.ToolTip := "Select the action type you want to perform"
    TargetDD.ToolTip := "Where to perform the action (position, pattern, region, etc.)"
    ParamCombo.ToolTip := "Additional parameters for the action (see hint below)"
    ChoicesDD.ToolTip := "Quick selection - click < to copy to Target/Param, Refresh to update list"
}


; ═══════════════════════════════════════════════════════════════════════════════
; DROPDOWN HELPER FUNCTIONS (AutoHotkey v2 compatible)
; ═══════════════════════════════════════════════════════════════════════════════

DDL_GetCount(ctrl) {
    count := 0
    Loop {
        try {
            ctrl.GetText(A_Index)
            count := A_Index
        } catch {
            break
        }
    }
    return count
}

DDL_AddAndSelect(ctrl, text) {
    ctrl.Add([text])
    ctrl.Text := text
}

DDL_FindAndSelect(ctrl, text) {
    Loop {
        try {
            if ctrl.GetText(A_Index) = text {
                ctrl.Choose(A_Index)
                return true
            }
        } catch {
            break
        }
    }
    return false
}


RefreshChoices(*) {
    PopulateChoices()
    ShowStatus("Choices refreshed", "ok")
}

; Copy from choices to appropriate field
UseChoice(*) {
    global ActionDD, TargetDD, ParamCombo, ChoicesDD

    if ChoicesDD.Value = 0
        return

    selected := ChoicesDD.Text
    action := ActionDD.Text

    ; Determine where to copy based on action type
    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click", "Hover Mouse", "Drag", "Relative Click":
            ; Extract coordinate name from "Name (x,y)" format
            if InStr(selected, " (") {
                coordName := SubStr(selected, 1, InStr(selected, " (") - 1)
                TargetDD.Text := coordName
            } else {
                TargetDD.Text := selected
            }
            ShowStatus("Copied to Target", "ok")

        case "Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick", "Find & Drag", "Find & Click Loop", "Wait for Pattern", "Wait Until Gone":
            TargetDD.Text := selected
            ShowStatus("Copied to Target (Pattern)", "ok")

        case "OCR Region":
            ; V5.1: Handle variable format or region
            if InStr(selected, "window:") = 1 || InStr(selected, "demo:") = 1 {
                TargetDD.Text := selected
                ShowStatus("Copied dynamic OCR region to Target", "ok")
            } else if InStr(selected, "var:") {
                ; Variable creation format
                varName := StrReplace(selected, " (existing)", "")
                varName := StrReplace(varName, " (create new)", "")
                ParamCombo.Text := varName
                ShowStatus("Variable format copied to Param", "ok")
            } else if InStr(selected, "copy") {
                ParamCombo.Text := "copy"
                ShowStatus("Copy mode set", "ok")
            } else if InStr(selected, "(") {
                ; Region coordinates
                coords := SubStr(selected, InStr(selected, "(") + 1)
                coords := SubStr(coords, 1, InStr(coords, ")") - 1)
                TargetDD.Text := coords
                ShowStatus("Copied to Target (Region)", "ok")
            }

        case "OCR Click", "OCR Wait":
            ; Extract coordinates from region description
            if InStr(selected, "window:") = 1 || InStr(selected, "demo:") = 1 {
                TargetDD.Text := selected
                ShowStatus("Copied dynamic OCR region to Target", "ok")
            } else if InStr(selected, "(") {
                coords := SubStr(selected, InStr(selected, "(") + 1)
                coords := SubStr(coords, 1, InStr(coords, ")") - 1)
                TargetDD.Text := coords
                ShowStatus("Copied to Target (Region)", "ok")
            }

        case "Grab OCR to Var", "OCR Full Screen to Var":
            cleanSelected := StrReplace(selected, " (existing)", "")
            cleanSelected := StrReplace(cleanSelected, " (create new)", "")
            ; Accept old combined suggestions but copy only the variable name.
            if InStr(cleanSelected, ",")
                cleanSelected := StrSplit(cleanSelected, ",")[1]
            ParamCombo.Text := cleanSelected
            ShowStatus("Copied variable name", "ok")

        case "Grab Clipboard", "If Contains", "If Variable":
            TargetDD.Text := selected
            ShowStatus("Copied variable name to Target", "ok")

        case "Set Clipboard", "Use Var Paste", "Show Notification", "Set Variable", "Append to Clipboard", "Prepend to Clipboard":
            ; V5.1: Insert variable or text
            if InStr(selected, "$var.") {
                ; It's a variable
                current := ParamCombo.Text
                if current = "" || current = "(type text or variable)"
                    ParamCombo.Text := selected
                else
                    ParamCombo.Text := current . selected
                ShowStatus("Variable inserted: " . selected, "ok")
            } else if selected != "(type text or variable)" {
                ParamCombo.Text := selected
                ShowStatus("Copied to Param", "ok")
            }

        case "Run Sequence", "Format Clipboard", "Extract from Clipboard":
            ParamCombo.Text := selected
            ShowStatus("Copied to Param", "ok")

        case "Send Keys", "Key Chord", "Taskbar Activate", "Type Text", "Scroll", "Wait", "Menu Select":
            ; These go to Param
            ParamCombo.Text := selected
            ShowStatus("Copied to Param", "ok")

        case "Activate Window":
            ; Strip the "  [exe]" display suffix so the title matches cleanly
            ParamCombo.Text := CleanWindowTitle(selected)
            ShowStatus("Copied to Param (Window)", "ok")

        case "Run Program":
            ParamCombo.Text := selected
            ShowStatus("Copied to Param", "ok")

        case "Insert Field":
            ; Field name goes to Param
            ParamCombo.Text := selected
            ShowStatus("Copied to Param (Field)", "ok")

        case "Loop Start", "Popup Detect", "Wait for Window", "Wait Window Closed":
            ParamCombo.Text := selected
            ShowStatus("Copied to Param", "ok")

        default:
            ; Default to Param
            ParamCombo.Text := selected
            ShowStatus("Copied to Param", "ok")
    }
}


; Show OCR region preview overlay
global g_OCRPreview := ""

ShowOCRPreview(coords) {
    global g_OCRPreview, ActionDD

    ; Only show for OCR actions
    action := ActionDD.Text
    if !InStr(action, "OCR") && !InStr(action, "Grab OCR")
        return

    ; Parse coordinates
    parts := StrSplit(coords, ",")
    if parts.Length != 4
        return

    x1 := Integer(parts[1])
    y1 := Integer(parts[2])
    if InStr(action, "Grab OCR") {
        x2 := x1 + Integer(parts[3])
        y2 := y1 + Integer(parts[4])
    } else {
        x2 := Integer(parts[3])
        y2 := Integer(parts[4])
    }

    ; Validate
    if x2 <= x1 || y2 <= y1
        return

    w := x2 - x1
    h := y2 - y1

    ; Destroy old preview
    if g_OCRPreview != "" {
        try g_OCRPreview.Destroy()
    }

    ; Create new preview overlay
    g_OCRPreview := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "OCRPreview")
    g_OCRPreview.BackColor := "00FF00"  ; Green
    g_OCRPreview.Show("x" . x1 . " y" . y1 . " w" . w . " h" . h . " NoActivate")
    WinSetTransparent(100, g_OCRPreview)

    ; Create hollow region (border only, 4px thick)
    innerX := 4
    innerY := 4
    innerW := w - 8
    innerH := h - 8

    if innerW > 0 && innerH > 0 {
        try WinSetRegion("0-0 " . w . "-0 " . w . "-" . h . " 0-" . h . " 0-0 "
            . innerX . "-" . innerY . " " . (innerX + innerW) . "-" . innerY . " "
            . (innerX + innerW) . "-" . (innerY + innerH) . " " . innerX . "-" . (innerY + innerH)
            . " " . innerX . "-" . innerY, g_OCRPreview)
    }

    ; Add label
    try g_OCRPreview.SetFont("s10 bold", "Arial")
    try g_OCRPreview.Add("Text", "x5 y2 cLime BackgroundTrans", "OCR Preview")

    ; Add close button
    try {
        closeBtn := g_OCRPreview.Add("Button", "x" . (w - 22) . " y2 w20 h20", "✕")
        closeBtn.SetFont("s10 bold")
        closeBtn.OnEvent("Click", (*) => HideOCRPreview())
    }

    ; Auto-hide after 3 seconds
    SetTimer(() => HideOCRPreview(), -3000)
}

HideOCRPreview(*) {
    global g_OCRPreview
    if g_OCRPreview != "" {
        try g_OCRPreview.Destroy()
        g_OCRPreview := ""
    }
}

; Monitor Target field changes for OCR actions
OnTargetChange(*) {
    global TargetDD, ActionDD

    action := ActionDD.Text
    coords := TargetDD.Text

    ; Show preview for OCR actions
    if (InStr(action, "OCR") || InStr(action, "Grab OCR")) && InStr(coords, ",") {
        ; Check if it's a valid coordinate string (x1,y1,x2,y2)
        parts := StrSplit(coords, ",")
        if parts.Length = 4 {
            ShowOCRPreview(coords)
        }
    }
}

; Monitor Param field changes for Grab OCR to Var
OnParamChange(*) {
    global ParamCombo, ActionDD

    action := ActionDD.Text
    param := ParamCombo.Text

    ; For Grab OCR to Var, extract coordinates from param
    if InStr(action, "Grab OCR") {
        ; Format: varName,x1,y1,x2,y2
        parts := StrSplit(param, ",")
        if parts.Length >= 5 {
            coords := parts[2] . "," . parts[3] . "," . parts[4] . "," . parts[5]
            ShowOCRPreview(coords)
        }
    }
}

UpdateHints(*) {
    ; This function is now deprecated in favor of UpdateActionHelp()
    ; Kept for backward compatibility but does nothing
    return
}

; Context-sensitive help uses the same specification as validation and field layout.
UpdateActionHelp(*) {
    global ActionDD, ActionHelpTitle, ActionHelpText
    action := ActionDD.Text
    spec := GetWorkflowActionSpec(action)
    ActionHelpTitle.Text := action
    details := ""
    if spec["targetUsed"]
        details .= spec["targetLabel"] . ": " . spec["targetHint"] . "`n"
    if spec["paramUsed"]
        details .= spec["paramLabel"] . ": " . spec["paramHint"] . "`n"
    if spec["example"] != ""
        details .= "Example: " . spec["example"] . "`n"
    ActionHelpText.Text := details . spec["help"]
}

; Retained only as source history for older detailed help text.
UpdateActionHelpLegacy(*) {
    global ActionDD, ActionHelpTitle, ActionHelpText

    action := ActionDD.Text

    ; Comprehensive help for each action type
    helpData := Map(
        "Click", Map(
            "title", "Click - Mouse click at position",
            "text", "TARGET: Position name or x,y`nPARAM: Click count (1, 2, 3)`nExample: Target=MyButton, Param=1`nCommon error: Position not found - check name spelling"
        ),
        "OCR Region", Map(
            "title", "OCR Region - Extract text from screen area",
            "text", "TARGET: x,y,WIDTH,HEIGHT (not x1,y1,x2,y2!)`nPARAM: var:variableName (creates $var.variableName)`n`n⚠ CRITICAL: Format is x,y,WIDTH,HEIGHT`nExample: 100,100,400,200 means:`n  Start at (100,100), capture 400 wide × 200 tall`n`nUse 📷 OCR button for auto-calculation!`n`nVariable format:`n• Creating: var:myVar`n• Using later: $var.myVar"
        ),
        "OCR Click", Map(
            "title", "OCR Click - Find text via OCR and click it",
            "text", "TARGET: Search region x,y,width,height`nPARAM: Text to find`nExample: Target=0,0,1920,1080, Param=Submit`n⚠ Text must be visible and readable`n⚠ Increase scale if text not detected"
        ),
        "Grab OCR to Var", Map(
            "title", "Grab OCR to Var - OCR region and store to variable",
            "text", "PARAM: variableName,x,y,width,height`n`nFormat Rules:`n• Creating: variableName,x,y,w,h (no $ or var:)`n• Using later: $var.variableName`n`nExample:`n1. Grab OCR to Var → Param: patientID,100,100,200,50`n   Result: Creates $var.patientID`n2. Use Var Paste → Param: Patient: $var.patientID`n`n⚠ Check Choices dropdown for existing variables"
        ),
        "Use Var Paste", Map(
            "title", "Use Var Paste - Paste text with variables",
            "text", "PARAM: Text with $var.variableName placeholders`n`nChoices dropdown shows available variables!`n`nExamples:`n• Single variable: $var.patientID`n• Mixed text: Patient: $var.patientID, Date: $var.date`n• Multiple vars: $var.firstName $var.lastName`n`n⚠ Variables must be created first (OCR Region or Grab OCR to Var)`n⚠ Use exact format: $var.name"
        ),
        "Set Clipboard", Map(
            "title", "Set Clipboard - Copy text to clipboard",
            "text", "PARAM: Text or $var.variableName`n`nChoices dropdown shows available variables!`nClick '<' button to insert selected variable`n`nExamples:`n• Plain text: Hello World`n• Using variable: $var.ocrText`n• Mixed: Patient ID: $var.patientID`n`nWorkflow: OCR Region → Set Clipboard → Paste`n⚠ Use Choices dropdown - don't type variable manually"
        ),
        "Find & Click", Map(
            "title", "Find & Click - Find image pattern and click",
            "text", "TARGET: Pattern name`nPARAM: Search region (optional)`nExample: Target=SubmitButton`n⚠ Pattern not found? Recapture or increase variation`n⚠ Use Patterns tab to capture patterns"
        ),
        "Send Keys", Map(
            "title", "Send Keys - Send keyboard input",
            "text", "PARAM: Keys to send`nSpecial keys: {Enter} {Tab} {Esc}`nModifiers: ^ = Ctrl, + = Shift, ! = Alt`nExample: Param=^c (Ctrl+C)`nExample: Param=Hello{Enter}`n⚠ Use raw Send Keys if special chars don't work"
        ),
        "Wait", Map(
            "title", "Wait - Pause execution",
            "text", "PARAM: Milliseconds`nExample: Param=1000 (wait 1 second)`nExample: Param=500 (wait 0.5 seconds)`n⚠ Use between actions to allow UI to load"
        ),
        "Drag", Map(
            "title", "Drag - Click and drag between positions",
            "text", "TARGET: Drag position name`nPARAM: Duration in ms (default 300)`nExample: Target=MyDrag, Param=500`n⚠ Capture drag with 'Drag' button in capture row"
        ),
        "Type Text", Map(
            "title", "Type Text - Type text literally",
            "text", "PARAM: Text to type`nSupports $variables from OCR`nExample: Param=user@email.com`nExample: Param=$patientName`n⚠ Slower than Send Keys but more reliable"
        )
    )

    if helpData.Has(action) {
        data := helpData[action]
        ActionHelpTitle.Text := data["title"]
        ActionHelpText.Text := data["text"]
    } else {
        ActionHelpTitle.Text := action
        ActionHelpText.Text := "No detailed help available for this action yet.`nRefer to the action dropdown selection and parameter fields."
    }
}




PopulateChoices() {
    global ActionDD, ChoicesDD, g_ExtractedData, g_Coordinates, g_Patterns, g_TaskbarApps, g_Sequences, g_CurrentSequenceSteps

    action := ActionDD.Text
    choices := []

    ; V5.1: Check for variables created in current sequence
    sequenceVars := GetSequenceVariables()

    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click", "Hover Mouse":
            choices.Push("demo:notepadedit")
            choices.Push("demo:single")
            choices.Push("demo:double")
            choices.Push("demo:triple")
            choices.Push("demo:right")
            choices.Push("demo:hover")
            ; Show all saved coordinates
            for name, coord in g_Coordinates
                choices.Push(name . " (" . coord["x"] . "," . coord["y"] . ")")

        case "Drag":
            ; Show drag coordinates
            for name, coord in g_Coordinates {
                if coord.Has("endX")
                    choices.Push(name . " (" . coord["x"] . "," . coord["y"] . "→" . coord["endX"] . "," . coord["endY"] . ")")
            }

        case "Relative Click":
            ; Show relative coordinates
            for name, coord in g_Coordinates {
                if coord.Has("relative") && coord["relative"]
                    choices.Push(name . " (+" . coord["x"] . ",+" . coord["y"] . ")")
            }

        case "Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick", "Find & Drag", "Find & Click Loop":
            ; Show all patterns
            for name, _ in g_Patterns
                choices.Push(name)

        case "Wait for Pattern", "Wait Until Gone":
            ; Show all patterns
            for name, _ in g_Patterns
                choices.Push(name)

        case "OCR Region":
            choices.Push("window:MacroAutomator Demo Lab")
            for winTitle in GetWindowTitlesFull()   ; live windows to OCR
                choices.Push("window:" . winTitle)
            ; V5.1: Show variable creation suggestions
            if sequenceVars.Length > 0 {
                for varName in sequenceVars
                    choices.Push("var:" . varName . " (existing)")
            }
            choices.Push("var:newVariable (create new)")
            choices.Push("copy (to clipboard)")

        case "Set Clipboard", "Use Var Paste", "Show Notification":
            ; V5.1: Show available variables from sequence
            if sequenceVars.Length > 0 {
                for varName in sequenceVars
                    choices.Push("$var." . varName)
            }
            choices.Push("(type text or variable)")

        case "Set Variable", "Append to Clipboard", "Prepend to Clipboard":
            for varName in sequenceVars
                choices.Push("$var." . varName)
            choices.Push("(type text or variable)")

        case "Grab Clipboard", "If Contains", "If Variable":
            for varName in sequenceVars
                choices.Push(varName)
            choices.Push("newVariable")

        case "Run Sequence":
            for name, _ in g_Sequences
                choices.Push(name)

        case "Format Clipboard":
            choices := ["invoice", "receipt", "uppercase", "lowercase", "titlecase", "trim", "date_iso", "[{clip}]"]

        case "Extract from Clipboard":
            choices := ["between:start|end", "field:,|1", "regex:\\d+"]

        case "Click Element", "Hover Element", "Wait Element":
            choices := GetTrackedElementNames()

        case "Replay Window Mouse":
            choices := ["1.0", "2.0  (2x speed)", "1.0,clicks  (include clicks)", "0.5  (half speed)"]

        case "Research Capture Links":
            choices := ["screen  (OCR the results page)", "clip  (from clipboard)"]

        case "Grab OCR to Var", "OCR Full Screen to Var":
            ; Variable and region are separate contextual fields.
            if sequenceVars.Length > 0 {
                for varName in sequenceVars
                    choices.Push(varName . " (existing)")
            }
            choices.Push("newVariable (create new)")

        case "OCR Click", "OCR Wait":
            ; Show common screen regions (for Target field)
            choices := [
                "window:MacroAutomator Demo Lab",
                "0,0," . A_ScreenWidth . "," . A_ScreenHeight,
                "0,0," . A_ScreenWidth . "," . A_ScreenHeight//2,
                "0," . A_ScreenHeight//2 . "," . A_ScreenWidth . "," . A_ScreenHeight,
                "0,0," . A_ScreenWidth//2 . "," . A_ScreenHeight,
                A_ScreenWidth//2 . ",0," . A_ScreenWidth . "," . A_ScreenHeight
            ]
            for winTitle in GetWindowTitlesFull()   ; live windows to OCR
                choices.Push("window:" . winTitle)

        case "Send Keys":
            choices := [
                "^c  (Ctrl+C)", "^v  (Ctrl+V)", "^x  (Ctrl+X)", "^a  (Ctrl+A)",
                "^s  (Ctrl+S)", "^z  (Ctrl+Z)", "^t  (Ctrl+T)", "^w  (Ctrl+W)",
                "{Enter}", "{Tab}", "{Escape}", "{Space}",
                "{Backspace}", "{Delete}", "{Home}", "{End}",
                "{Up}", "{Down}", "{Left}", "{Right}", "{F5}"
            ]

        case "Key Chord":
            choices := [
                "#,5,2  (Win+5 twice)",
                "#,1,1  (Win+1)",
                "^,c,1  (Ctrl+C)",
                "^,{Tab},3  (Ctrl+Tab x3)",
                "!,{Tab},2  (Alt+Tab x2)"
            ]

        case "Taskbar Activate":
            choices.Push("demo:lab")
            ; Show taskbar positions with app names if known
            for i in [1,2,3,4,5,6,7,8,9,0] {
                appName := g_TaskbarApps.Has(i) ? g_TaskbarApps[i] : ""
                if appName != ""
                    choices.Push(i . ",1  (" . appName . ")")
                else
                    choices.Push(i . ",1  (Position " . i . ")")
            }

        case "Activate Window":
            ; Show common window titles
            choices := ["MacroAutomator Demo Lab"]
            for windowChoice in GetWindowList()
                choices.Push(windowChoice)

        case "Run Program":
            ; Show common programs
            choices := GetCommonPrograms()

        case "Insert Field":
            ; Show extracted fields
            for name, _ in g_ExtractedData
                choices.Push(name)
            if choices.Length = 0
                choices.Push("(no fields extracted yet)")

        case "Type Text", "Use Var Paste":
            ; Show extracted fields as variables
            for name, _ in g_ExtractedData
                choices.Push("$" . name)
            if choices.Length = 0
                choices.Push("(no variables available)")

        case "Scroll":
            choices := ["-10 (down fast)", "-5 (down)", "-3 (down slow)", "-1 (down tiny)",
                       "1 (up tiny)", "3 (up slow)", "5 (up)", "10 (up fast)"]

        case "Wait":
            choices := ["100", "200", "500", "1000", "2000", "3000", "5000"]

        case "Menu Select":
            choices := ["File>Save", "File>Open", "Edit>Copy", "Edit>Paste", "View>Zoom"]

        case "Loop Start":
            choices := ["count=5; var=i", "count=3; var=i", "count=10; var=n", "count=forever; var=i"]

        case "Popup Detect":
            choices := [
                "win=; region=0,0,800,600; sensitivity=medium; on=var; mode=now; timeout=5000; var=popupChanged",
                "sensitivity=high; on=break; var=popupChanged",
                "sensitivity=high; on=skip; var=popupChanged"
            ]

        case "Wait for Window", "Wait Window Closed":
            choices := []
            for winTitle in GetWindowTitlesFull()
                choices.Push("title=" . winTitle . "; timeout=5000")
            choices.Push("title=; timeout=5000")

        case "Loop End", "Loop Break":
            choices := []

        default:
            choices := []
    }

    ; Update dropdown
    ChoicesDD.Delete()
    if choices.Length > 0
        ChoicesDD.Add(choices)




    choice := ChoicesDD.Text
    if choice = ""
        return
    action := ActionDD.Text

    ; For Key Chord and Taskbar Activate, strip description but keep the values
    if action = "Key Chord" || action = "Taskbar Activate" {
        if InStr(choice, "  ")
            choice := Trim(SubStr(choice, 1, InStr(choice, "  ") - 1))
        ParamCombo.Text := choice
        return
    }

    ; Strip common suffixes
    if InStr(choice, "  (")
        choice := Trim(SubStr(choice, 1, InStr(choice, "  (") - 1))
    if InStr(choice, "  [")
        choice := Trim(SubStr(choice, 1, InStr(choice, "  [") - 1))
    if InStr(choice, "[Pattern] ")
        choice := SubStr(choice, 11)
    if InStr(choice, "[P] ")
        choice := SubStr(choice, 5)
    if InStr(choice, "[Rel] ")
        choice := SubStr(choice, 7)
    if InStr(action, "Find &") {
        try {
            items := ControlGetItems(TargetDD)
            for i, item in items {
                if item = choice || item = "[P] " . choice || InStr(item, choice) {
                    TargetDD.Choose(i)
                    return
                }
            }
        }
    }
    ParamCombo.Text := choice


    StatusBar.SetText("Choices refreshed")
}


; ═══════════════════════════════════════════════════════════════════════════════
; TARGET DROPDOWN
; ═══════════════════════════════════════════════════════════════════════════════
; TARGET DROPDOWN
; =============================================================================


UpdateParamSuggestions() {
    global ActionDD, ParamCombo, g_ExtractedData, g_TaskbarApps, g_Sequences
    action := ActionDD.Text
    suggestions := []

    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click":
            suggestions := ["1", "2", "3"]

        case "Wait", "Wait for Pattern", "Wait Until Gone":
            suggestions := ["100", "200", "500", "1000", "2000", "3000", "5000", "10000"]

        case "Menu Select":
            suggestions := ["File>Save", "File>Open", "Edit>Copy", "Edit>Paste"]

        case "Send Keys":
            suggestions := [
                "^c", "^v", "^x", "^a", "^s", "^z",
                "{Enter}", "{Tab}", "{Escape}", "{Space}",
                "{Up}", "{Down}", "{Left}", "{Right}",
                "{Home}", "{End}", "{Delete}", "{Backspace}"
            ]

        case "Key Chord":
            suggestions := [
                "#,5,2  (Win+5 x2)",
                "#,1,1  (Win+1)",
                "^,c,1  (Ctrl+C)",
                "^,{Tab},3  (Ctrl+Tab x3)",
                "!,{Tab},2  (Alt+Tab x2)"
            ]

        case "Taskbar Activate":
            suggestions := [
                "demo:lab",
                "1,1", "2,1", "3,1", "4,1", "5,1",
                "6,1", "7,1", "8,1", "9,1", "0,1"
            ]
            if g_TaskbarApps.Length > 0 {
                for i, app in g_TaskbarApps {
                    if app != ""
                        suggestions.Push(i . ",1  (" . SubStr(app, 1, 15) . ")")
                }
            }

        case "Activate Window":
            suggestions := GetWindowList()

        case "Run Program":
            suggestions := GetCommonPrograms()

        case "Loop Start":
            suggestions := ["count=5; var=i", "count=3; var=i", "count=10; var=n", "count=forever; var=i"]

        case "Popup Detect":
            suggestions := [
                "win=; region=0,0,800,600; sensitivity=medium; on=var; mode=now; timeout=5000; var=popupChanged",
                "sensitivity=high; on=break; var=popupChanged"
            ]

        case "Wait for Window", "Wait Window Closed":
            suggestions := []
            for winTitle in GetWindowTitlesFull()
                suggestions.Push("title=" . winTitle . "; timeout=5000")
            suggestions.Push("title=; timeout=5000")

        case "Insert Field":
            for name, _ in g_ExtractedData
                suggestions.Push(name)

        case "Scroll":
            suggestions := ["-10", "-5", "-3", "-1", "1", "3", "5", "10"]

        case "Type Text", "Use Var Paste":
            for name, _ in g_ExtractedData
                suggestions.Push("$" . name)
            if suggestions.Length = 0
                suggestions := ["$variableName", "Hello $name"]

        case "Set Clipboard":
            suggestions := ["Text to copy"]

        case "Find & Drag":
            suggestions := ["500,500", "0,100", "100,0"]

        case "Drag":
            suggestions := ["300 (duration ms)"]

        case "Relative Click":
            suggestions := ["10,0", "-10,0", "0,10", "0,-10"]

        case "OCR Region":
            suggestions := [
                "copy",
                "var:variableName",
                "split:4",
                "split:tab",
                "split:line",
                "regex:\\d+"
            ]

        case "OCR Click":
            suggestions := [
                "Submit", "OK", "Cancel", "Save", "Next", "Button"
            ]

        case "OCR Wait":
            suggestions := [
                "5000",
                "10000",
                "appear,text,5000"
            ]

        case "Load OCR Revolver":
            suggestions := [
                "space",
                "tab",
                "line",
                "comma"
            ]

        case "Idle Mouse":
            suggestions := ["0", "5", "10", "30"]

        case "Hover Mouse":
            suggestions := ["(position name from Fixed Positions)"]

        case "Grab OCR to Var", "OCR Full Screen to Var":
            suggestions := ["capturedText", "fullScreenOCR", "patientName"]

        case "Show Notification":
            suggestions := [
                "Title,Message,3",
                "Complete,Task finished,5"
            ]

        case "If Variable":
            suggestions := ["=,value", "!=,value", ">,0", ">=,5", "<,10", "<=,100"]

        case "Run Sequence":
            for name, _ in g_Sequences
                suggestions.Push(name)

        case "Format Clipboard":
            suggestions := ["invoice", "receipt", "uppercase", "lowercase", "titlecase", "trim", "date_iso", "[{clip}]"]

        case "Extract from Clipboard":
            suggestions := ["between:start|end", "field:,|1", "regex:\\d+"]
    }

    ; Update combobox
    ParamCombo.Delete()
    if suggestions.Length > 0
        ParamCombo.Add(suggestions)
}

UpdateTargetDD() {
    global ActionDD, TargetDD, g_Coordinates, g_Patterns

    action := ActionDD.Text
    items := []

    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click":
            for demoTarget in ["demo:notepadedit", "demo:single", "demo:double", "demo:triple", "demo:right"]
                items.Push(demoTarget)
            ; Show click coordinates
            for name, coord in g_Coordinates {
                if !coord.Has("endX") && (!coord.Has("relative") || !coord["relative"])
                    items.Push(name)
            }

        case "Drag":
            ; Show drag coordinates
            for name, coord in g_Coordinates {
                if coord.Has("endX")
                    items.Push(name)
            }

        case "Relative Click":
            ; Show relative coordinates
            for name, coord in g_Coordinates {
                if coord.Has("relative") && coord["relative"]
                    items.Push(name)
            }

        case "Hover Mouse":
            items.Push("demo:hover")
            ; Show all coordinates
            for name, coord in g_Coordinates {
                if !coord.Has("endX")
                    items.Push(name)
            }

        case "Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick", "Find & Drag", "Find & Click Loop", "Wait for Pattern", "Wait Until Gone":
            ; Show patterns
            for name, _ in g_Patterns
                items.Push(name)

        case "OCR Region", "OCR Click", "OCR Wait":
            ; Show common regions + saved coordinates
            items := [
                "0,0," . A_ScreenWidth . "," . A_ScreenHeight,  ; Full screen
                "0,0," . A_ScreenWidth . "," . A_ScreenHeight//2,  ; Top half
                "0," . A_ScreenHeight//2 . "," . A_ScreenWidth . "," . A_ScreenHeight  ; Bottom half
            ]

        case "Grab OCR to Var":
            items := ["0,0," . A_ScreenWidth . "," . A_ScreenHeight]

        case "Set Variable", "Grab Clipboard", "If Contains", "If Variable":
            items := GetSequenceVariables()
            if action = "Set Variable" || action = "Grab Clipboard"
                items.Push("newVariable")

        case "Activate Window":
            ; Show active windows
            items := GetWindowList()

        default:
            items := ["(not applicable)"]
    }

    ; Update dropdown
    currentText := TargetDD.Text
    TargetDD.Delete()

    if items.Length > 0 {
        TargetDD.Add(items)
        ; Try to restore previous selection
        if currentText != "" {
            Loop TargetDD.GetItemCount() {
                if TargetDD.GetText(A_Index) = currentText {
                    TargetDD.Choose(A_Index)
                    break
                }
            }
        }
    }
}




; ═══════════════════════════════════════════════════════════════════════════════
; COORDINATE CAPTURE
; ═══════════════════════════════════════════════════════════════════════════════
; COORDINATE CAPTURE
; =============================================================================

ShowCoordinateManager(*) {
    global MainGui, CoordLV, g_HiddenCoordLV, g_CoordManagerGui, g_CoordManagerNameEdit
    if IsObject(g_CoordManagerGui) {
        try {
            g_CoordManagerGui.Show()
            return
        }
    }

    manager := Gui("+Owner" . MainGui.Hwnd . " +Resize +MinSize620x390", "Workflow Position Tools")
    manager.SetFont("s9", "Segoe UI")
    manager.Add("Text", "x12 y12 w590", "Capture reusable click, drag, arrow-adjusted, or relative positions. These appear in action Suggestions.")
    manager.Add("Text", "x12 y45", "Position name (optional):")
    g_CoordManagerNameEdit := manager.Add("Edit", "x145 y42 w190")
    manager.Add("Button", "x345 y40 w60 h25", "Click").OnEvent("Click", CoordinateManagerStartCapture.Bind(manager, StartClickCapture))
    manager.Add("Button", "x410 y40 w60 h25", "Drag").OnEvent("Click", CoordinateManagerStartCapture.Bind(manager, StartDragCapture))
    manager.Add("Button", "x475 y40 w60 h25", "Arrow").OnEvent("Click", CoordinateManagerStartCapture.Bind(manager, StartArrowCapture))
    manager.Add("Button", "x540 y40 w65 h25", "Relative").OnEvent("Click", CoordinateManagerStartCapture.Bind(manager, StartRelativeCapture))

    managerLV := manager.Add("ListView", "x12 y78 w595 h255 Grid NoSortHdr", ["Name", "X", "Y", "End X", "End Y", "Type"])
    managerLV.ModifyCol(1, 170)
    managerLV.ModifyCol(2, 70)
    managerLV.ModifyCol(3, 70)
    managerLV.ModifyCol(4, 70)
    managerLV.ModifyCol(5, 70)
    managerLV.ModifyCol(6, 110)
    CoordLV := managerLV
    RefreshCoordLV()

    manager.Add("Button", "x12 y342 w80 h28", "Test").OnEvent("Click", TestCoord)
    manager.Add("Button", "x102 y342 w80 h28", "Delete").OnEvent("Click", DelCoord)
    manager.Add("Button", "x192 y342 w100 h28", "Refresh").OnEvent("Click", (*) => RefreshCoordLV())
    manager.Add("Button", "x527 y342 w80 h28", "Close").OnEvent("Click", (*) => CloseCoordinateManager())
    manager.OnEvent("Close", (*) => CloseCoordinateManager())
    g_CoordManagerGui := manager
    manager.Show("w620 h385")
}

CoordinateManagerStartCapture(manager, captureFunction, *) {
    global g_HiddenCoordNameEdit, g_CoordManagerNameEdit
    g_HiddenCoordNameEdit.Value := Trim(g_CoordManagerNameEdit.Value)
    manager.Hide()
    captureFunction.Call()
}

CoordinateManagerCaptureFinished() {
    global g_CoordManagerGui, g_CoordManagerNameEdit
    if IsObject(g_CoordManagerNameEdit)
        try g_CoordManagerNameEdit.Value := ""
    if IsObject(g_CoordManagerGui)
        try g_CoordManagerGui.Show()
}

CloseCoordinateManager(*) {
    global CoordLV, CoordNameEdit, g_HiddenCoordLV, g_HiddenCoordNameEdit
    global g_CoordManagerGui, g_CoordManagerNameEdit
    manager := g_CoordManagerGui
    CoordLV := g_HiddenCoordLV
    CoordNameEdit := g_HiddenCoordNameEdit
    g_CoordManagerGui := 0
    g_CoordManagerNameEdit := 0
    if IsObject(manager)
        try manager.Destroy()
}

StartClickCapture(*) {
    global g_IsCapturing, g_DragMode
    g_IsCapturing := true
    g_DragMode := false
    StatusBar.SetText("Click to capture. ESC cancel.")
    Hotkey("~LButton", CaptureClick, "On")
    Hotkey("Escape", CancelCap, "On")
}

StartDragCapture(*) {
    global g_IsCapturing, g_DragMode, g_DragStartX, g_DragStartY
    g_IsCapturing := true
    g_DragMode := true
    g_DragStartX := g_DragStartY := 0
    StatusBar.SetText("Click+drag, release. ESC cancel.")
    Hotkey("~LButton", CapDragStart, "On")
    Hotkey("~LButton Up", CapDragEnd, "On")
    Hotkey("Escape", CancelCap, "On")
}

CaptureClick(*) {
    global g_IsCapturing, g_Coordinates, CoordLV, CoordNameEdit
    if !g_IsCapturing
        return
    MouseGetPos(&x, &y)
    saved := MainGui.Submit(false)
    name := saved.CoordName != "" ? saved.CoordName : GenerateCoordName("Point")
    g_Coordinates[name] := Map("x", x, "y", y, "endX", "", "endY", "", "type", "Click")
    CoordLV.Add(, name, x, y, "", "", "Click")
    EndCapture()
    CoordNameEdit.Value := ""
    ShowMarker(x, y, 1000, "Green")
    SaveCoordinates()
    UpdateTargetDD()
    StatusBar.SetText("Saved: " . name)
}

CapDragStart(*) {
    global g_IsCapturing, g_DragStartX, g_DragStartY
    if !g_IsCapturing
        return
    MouseGetPos(&g_DragStartX, &g_DragStartY)
    ShowMarker(g_DragStartX, g_DragStartY, 5000, "Blue")
}

CapDragEnd(*) {
    global g_IsCapturing, g_DragMode, g_DragStartX, g_DragStartY, g_Coordinates, CoordLV, CoordNameEdit
    if !g_IsCapturing || !g_DragMode
        return
    MouseGetPos(&endX, &endY)
    saved := MainGui.Submit(false)
    name := saved.CoordName != "" ? saved.CoordName : GenerateCoordName("Drag")
    g_Coordinates[name] := Map("x", g_DragStartX, "y", g_DragStartY, "endX", endX, "endY", endY, "type", "Drag")
    CoordLV.Add(, name, g_DragStartX, g_DragStartY, endX, endY, "Drag")
    EndCapture()
    CoordNameEdit.Value := ""
    ShowMarker(endX, endY, 1000, "Green")
    SaveCoordinates()
    UpdateTargetDD()
    StatusBar.SetText("Saved drag: " . name)
}

CancelCap(*) {
    EndCapture()
    StatusBar.SetText("Cancelled")
}

EndCapture() {
    global g_IsCapturing, g_DragMode
    g_IsCapturing := false
    g_DragMode := false
    try Hotkey("~LButton", "Off")
    try Hotkey("~LButton Up", "Off")
    try Hotkey("Escape", "Off")
    CoordinateManagerCaptureFinished()
}

StartArrowCapture(*) {
    global g_IsCalibrating
    g_IsCalibrating := true
    MouseGetPos(&x, &y)
    ShowMarker(x, y, 99999, "Blue")
    Hotkey("Up", (*) => MoveBy(0, -1), "On")
    Hotkey("Down", (*) => MoveBy(0, 1), "On")
    Hotkey("Left", (*) => MoveBy(-1, 0), "On")
    Hotkey("Right", (*) => MoveBy(1, 0), "On")
    Hotkey("+Up", (*) => MoveBy(0, -10), "On")
    Hotkey("+Down", (*) => MoveBy(0, 10), "On")
    Hotkey("+Left", (*) => MoveBy(-10, 0), "On")
    Hotkey("+Right", (*) => MoveBy(10, 0), "On")
    Hotkey("Enter", FinishArrow, "On")
    Hotkey("Escape", CancelArrow, "On")
    StatusBar.SetText("Arrows=1px, Shift+Arrows=10px, Enter=save")
}

MoveBy(dx, dy) {
    global g_IsCalibrating
    if !g_IsCalibrating
        return
    MouseGetPos(&x, &y)
    MouseMove(x + dx, y + dy, 0)
    ShowMarker(x + dx, y + dy, 99999, "Blue")
}

FinishArrow(*) {
    global g_IsCalibrating, g_Coordinates, CoordLV
    if !g_IsCalibrating
        return
    MouseGetPos(&x, &y)
    EndArrow()
    name := GenerateCoordName("Point")
    g_Coordinates[name] := Map("x", x, "y", y, "endX", "", "endY", "", "type", "Click")
    CoordLV.Add(, name, x, y, "", "", "Click")
    SaveCoordinates()
    UpdateTargetDD()
    ShowMarker(x, y, 1500, "Green")
    StatusBar.SetText("Saved: " . name)
}

CancelArrow(*) {
    EndArrow()
    StatusBar.SetText("Cancelled")
}

EndArrow() {
    global g_IsCalibrating
    g_IsCalibrating := false
    for k in ["Up", "Down", "Left", "Right", "+Up", "+Down", "+Left", "+Right", "Enter", "Escape"]
        try Hotkey(k, "Off")
    HideMarker()
    CoordinateManagerCaptureFinished()
}

; Relative Capture
global g_RelCaptureStage := 0
global g_RelRefX := 0, g_RelRefY := 0

StartRelativeCapture(*) {
    global g_IsCapturing, g_RelCaptureStage
    g_IsCapturing := true
    g_RelCaptureStage := 1
    StatusBar.SetText("STEP 1: Click REFERENCE point. ESC cancel.")
    Hotkey("~LButton", CaptureRelativeClick, "On")
    Hotkey("Escape", CancelRelCap, "On")
}

CaptureRelativeClick(*) {
    global g_IsCapturing, g_RelCaptureStage, g_RelRefX, g_RelRefY
    global g_Coordinates, CoordLV, CoordNameEdit
    if !g_IsCapturing
        return
    MouseGetPos(&x, &y)
    if g_RelCaptureStage = 1 {
        g_RelRefX := x
        g_RelRefY := y
        g_RelCaptureStage := 2
        ShowMarker(x, y, 10000, "Blue")
        StatusBar.SetText("STEP 2: Click TARGET.")
    } else if g_RelCaptureStage = 2 {
        offsetX := x - g_RelRefX
        offsetY := y - g_RelRefY
        saved := MainGui.Submit(false)
        name := saved.CoordName != "" ? saved.CoordName : GenerateCoordName("Relative")
        g_Coordinates[name] := Map("x", offsetX, "y", offsetY, "endX", g_RelRefX, "endY", g_RelRefY, "type", "Relative")
        CoordLV.Add(, name, offsetX, offsetY, g_RelRefX, g_RelRefY, "Relative")
        EndRelCapture()
        CoordNameEdit.Value := ""
        ShowMarker(x, y, 1500, "Green")
        SaveCoordinates()
        UpdateTargetDD()
        StatusBar.SetText("Saved: " . name . " (offset: " . offsetX . "," . offsetY . ")")
    }
}

CancelRelCap(*) {
    EndRelCapture()
    StatusBar.SetText("Cancelled")
}

EndRelCapture() {
    global g_IsCapturing, g_RelCaptureStage
    g_IsCapturing := false
    g_RelCaptureStage := 0
    try Hotkey("~LButton", "Off")
    try Hotkey("Escape", "Off")
    HideMarker()
    CoordinateManagerCaptureFinished()
}

TestCoord(*) {
    global CoordLV, g_Coordinates
    row := CoordLV.GetNext(0, "Focused")
    if row = 0
        return
    name := CoordLV.GetText(row, 1)
    c := g_Coordinates[name]
    MouseMove(c["x"], c["y"], 5)
    ShowMarker(c["x"], c["y"], 1500, "Green")
}

DelCoord(*) {
    global CoordLV, g_Coordinates
    row := CoordLV.GetNext(0, "Focused")
    if row = 0
        return
    name := CoordLV.GetText(row, 1)
    g_Coordinates.Delete(name)
    CoordLV.Delete(row)
    SaveCoordinates()
    UpdateTargetDD()
}

; SEQUENCE BUILDER


SelectOCRRegionForWorkflow(*) {
    global MainGui, ActionDD, TargetDD, ParamCombo, g_LastOCRRegion, g_OCRHighlight

    ; Switch action to OCR Region if not already an OCR action
    action := ActionDD.Text
    if !InStr(action, "OCR") && !InStr(action, "Grab OCR") {
        ; Find and select OCR Region
        Loop ActionDD.GetItemCount() {
            if ActionDD.GetText(A_Index) = "OCR Region" {
                ActionDD.Choose(A_Index)
                break
            }
        }
        OnActionChange()
    }

    MainGui.Hide()
    Sleep(200)

    ; Show instruction tooltip
    TrackToolTip("📷 Drag to select OCR region`nESC to cancel`nHighlight will persist after selection", A_ScreenWidth//2 - 150, 50)

    ; Track drag state
    x1 := 0, y1 := 0, x2 := 0, y2 := 0
    cancelled := false
    selBox := ""
    boxW := 0, boxH := 0  ; Declare outside loop so they persist

    ; Cancel hotkey
    Hotkey("Escape", (*) => (cancelled := true), "On")

    ; Wait for mouse down
    while !GetKeyState("LButton", "P") && !cancelled {
        Sleep(10)
    }

    if cancelled {
        TrackToolTip()
        Hotkey("Escape", "Off")
        MainGui.Show()
        return
    }

    MouseGetPos(&x1, &y1)

    ; Create selection box (border only, click-through)
    selBox := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "SelBox")
    selBox.BackColor := "00FF00"

    ; Draw selection while dragging
    while GetKeyState("LButton", "P") && !cancelled {
        MouseGetPos(&x2, &y2)

        ; Update selection box
        boxX := Min(x1, x2)
        boxY := Min(y1, y2)
        boxW := Max(Abs(x2 - x1), 10)
        boxH := Max(Abs(y2 - y1), 10)

        if boxW > 5 && boxH > 5 {
            ; Show as border frame only (hollow rectangle)
            selBox.Show("x" . boxX . " y" . boxY . " w" . boxW . " h" . boxH . " NoActivate")
            WinSetTransparent(180, selBox)

            ; Create hollow region (border only, 3px thick)
            innerX := 3
            innerY := 3
            innerW := boxW - 6
            innerH := boxH - 6

            if innerW > 0 && innerH > 0 {
                try WinSetRegion("0-0 " . boxW . "-0 " . boxW . "-" . boxH . " 0-" . boxH . " 0-0 "
                    . innerX . "-" . innerY . " " . (innerX + innerW) . "-" . innerY . " "
                    . (innerX + innerW) . "-" . (innerY + innerH) . " " . innerX . "-" . (innerY + innerH)
                    . " " . innerX . "-" . innerY, selBox)
            }
        }

        Sleep(16)
    }

    ; Don't destroy the box yet - keep it as persistent highlight
    TrackToolTip()
    Hotkey("Escape", "Off")

    if cancelled || Abs(x2 - x1) < 10 || Abs(y2 - y1) < 10 {
        try selBox.Destroy()
        MainGui.Show()
        return
    }

    ; Normalize coordinates
    finalX1 := Min(x1, x2)
    finalY1 := Min(y1, y2)
    finalX2 := Max(x1, x2)
    finalY2 := Max(y1, y2)

    ; OCR Region/Click/Wait use corner coordinates. Grab OCR's underlying
    ; implementation uses x,y,width,height, so present the format it expects.
    currentAction := ActionDD.Text
    if InStr(currentAction, "Grab OCR")
        coordStr := finalX1 . "," . finalY1 . "," . (finalX2 - finalX1) . "," . (finalY2 - finalY1)
    else
        coordStr := finalX1 . "," . finalY1 . "," . finalX2 . "," . finalY2

    ; Store for reference
    g_LastOCRRegion := Map("x1", finalX1, "y1", finalY1, "x2", finalX2, "y2", finalY2)

    ; Destroy old highlight if exists
    if g_OCRHighlight != "" {
        try g_OCRHighlight.Destroy()
    }

    ; Create persistent highlight overlay (green border)
    g_OCRHighlight := selBox  ; Keep the selection box as persistent highlight
    WinSetTransparent(120, g_OCRHighlight)  ; Make it semi-transparent

    ; Add label to highlight
    try g_OCRHighlight.SetFont("s12 bold", "Arial")
    try g_OCRHighlight.Add("Text", "x5 y-2 cLime BackgroundTrans", "OCR Region")

    ; Add coordinates to TargetDD dropdown
    found := false
    Loop TargetDD.GetItemCount() {
        if TargetDD.GetText(A_Index) = coordStr {
            TargetDD.Choose(A_Index)
            found := true
            break
        }
    }

    if !found {
        TargetDD.Add([coordStr])
        DDL_AddAndSelect(TargetDD, coordStr)
    }

    ; Pre-fill param based on action type
    if ParamCombo.Text = "" {
        if InStr(currentAction, "Grab OCR") {
            ParamCombo.Text := "varName"
        } else if currentAction = "OCR Region" {
            ParamCombo.Text := "copy"
        } else if currentAction = "OCR Click" {
            ParamCombo.Text := "Button"
        } else if currentAction = "OCR Wait" {
            ParamCombo.Text := "appear,Complete,5000"
        }
    }

    MainGui.Show()
    ShowStatus("OCR Region: " . coordStr . " (highlight persists - click X to dismiss)", "ok")

    ; Add dismiss button to highlight (boxW now available)
    try {
        dismissBtn := g_OCRHighlight.Add("Button", "x" . (boxW - 25) . " y2 w20 h20", "X")
        dismissBtn.SetFont("s8 bold")
        dismissBtn.OnEvent("Click", (*) => DismissOCRHighlight())
    }
}


DismissOCRHighlight(*) {
    global g_OCRHighlight
    if g_OCRHighlight != "" {
        try g_OCRHighlight.Destroy()
        g_OCRHighlight := ""
        ShowStatus("OCR highlight dismissed", "ok")
    }




    return false
}



; ═══════════════════════════════════════════════════════════════════════════════
; V5.1: Extract all variables created in current sequence
GetSequenceVariables() {
    global g_CurrentSequenceSteps

    vars := []
    varSet := Map()  ; Use map to avoid duplicates

    for step in g_CurrentSequenceSteps {
        action := step["action"]
        target := step.Has("target") ? step["target"] : ""
        param := step.Has("param") ? step["param"] : ""

        ; v7 variable actions create their variable in the Target field.
        if (action = "Set Variable" || action = "Grab Clipboard") && Trim(target) != "" {
            varName := Trim(target)
            if RegExMatch(varName, "^[A-Za-z_][A-Za-z0-9_]*$") && !varSet.Has(varName) {
                vars.Push(varName)
                varSet[varName] := true
            }
        }

        ; Loop Start seeds its counter variable ($var.i etc.) and $var.loopCount.
        if action = "Loop Start" {
            opt := ParseLoopOptions(param)
            loopVar := LoopOptStr(opt, "var", "i")
            for v in [loopVar, "loopCount"] {
                if v != "" && RegExMatch(v, "^[A-Za-z_][A-Za-z0-9_]*$") && !varSet.Has(v) {
                    vars.Push(v)
                    varSet[v] := true
                }
            }
        }

        ; Popup Detect sets a result variable.
        if action = "Popup Detect" {
            opt := ParseLoopOptions(param)
            popupVar := LoopOptStr(opt, "var", "popupChanged")
            if popupVar != "" && RegExMatch(popupVar, "^[A-Za-z_][A-Za-z0-9_]*$") && !varSet.Has(popupVar) {
                vars.Push(popupVar)
                varSet[popupVar] := true
            }
        }

        ; Check OCR Region creating variables with var:name
        if action = "OCR Region" && InStr(param, "var:") {
            varName := Trim(SubStr(param, InStr(param, "var:") + 4))
            ; Remove any additional parameters after the variable name
            if InStr(varName, " ")
                varName := SubStr(varName, 1, InStr(varName, " ") - 1)
            if InStr(varName, ",")
                varName := SubStr(varName, 1, InStr(varName, ",") - 1)
            if varName != "" && !varSet.Has(varName) {
                vars.Push(varName)
                varSet[varName] := true
            }
        }

        ; Check OCR variable actions (new separate field or legacy combined format)
        if (action = "Grab OCR to Var" || action = "OCR Full Screen to Var") && Trim(param) != "" {
            parts := StrSplit(param, ",")
            if parts.Length >= 1 {
                varName := Trim(parts[1])
                ; Remove $ if present
                if SubStr(varName, 1, 1) = "$"
                    varName := SubStr(varName, 2)
                ; Remove $var. prefix if present
                if SubStr(varName, 1, 5) = "var."
                    varName := SubStr(varName, 6)
                if varName != "" && !varSet.Has(varName) {
                    vars.Push(varName)
                    varSet[varName] := true
                }
            }
        }
    }

    return vars
}


; V5.1: PARAMETER VALIDATION & LIVE HINTS
; ═══════════════════════════════════════════════════════════════════════════════

InitializeParameterValidators() {
    global g_ParamValidators, g_ParamHints

    g_ParamHints["Click"] := "1-10 for click count"
    g_ParamHints["OCR Region"] := "var:name to create variable | copy for clipboard | Check Choices for existing vars"
    g_ParamHints["OCR Click"] := "Text to find and click"
    g_ParamHints["Set Clipboard"] := "Text or $var.name | Check Choices dropdown for available variables!"
    g_ParamHints["Wait"] := "Milliseconds (1000 = 1 second)"
    g_ParamHints["Grab OCR to Var"] := "Variable name only; choose the OCR area in the Position field"
    g_ParamHints["OCR Full Screen to Var"] := "Plain variable name; captures the whole primary screen and draws yellow word boxes"
    g_ParamHints["Use Var Paste"] := "Text with $var.name | Check Choices dropdown for variables!"
    g_ParamHints["Send Keys"] := "^c={Ctrl+C}, +a={Shift+A}, !f={Alt+F}"
    g_ParamHints["Show Notification"] := "Title,Message,Timeout | Use $var.name for variables"
    g_ParamHints["Set Variable"] := "Value to store; $var.name substitutions are supported"
    g_ParamHints["If Contains"] := "Text to find; false skips the next enabled step"
    g_ParamHints["If Variable"] := "operator,value (examples: =,ready or >=,5)"
    g_ParamHints["Run Sequence"] := "Exact name of a saved workflow"
    g_ParamHints["Format Clipboard"] := "Preset name or a custom template containing {clip}"
    g_ParamHints["Extract from Clipboard"] := "between:start|end, field:delimiter|index, or regex:pattern"
}

ValidateStepParameters(action, target, param) {
    errors := []
    spec := GetWorkflowActionSpec(action)

    if spec["targetRequired"] && Trim(target) = ""
        errors.Push(spec["targetLabel"] . " is required")
    if spec["paramRequired"] && Trim(param) = ""
        errors.Push(spec["paramLabel"] . " is required")

    switch action {
        case "Click", "Double Click", "Triple Click", "Right Click":
            if target != "" && InStr(target, ",") && StrSplit(target, ",").Length != 2
                errors.Push("Position must be a saved name or x,y")
            if action = "Click" && param != "" && !IsNumber(param)
                errors.Push("Click count must be a number")

        case "Drag":
            if target = "" && param != "" && !RegExMatch(param, "^-?\d+\s*,\s*-?\d+\s*->\s*-?\d+\s*,\s*-?\d+$")
                errors.Push("Raw drag must be x1,y1->x2,y2")

        case "Find & Drag":
            if param != "" && !RegExMatch(param, "^-?\d+\s*,\s*-?\d+$")
                errors.Push("Destination must be endX,endY")

        case "OCR Region", "OCR Click", "OCR Wait":
            ; Dynamic targets (window:/demo:/control:, full, screen) are valid.
            if target != "" && !InStr(target, "window:") && !InStr(target, "demo:")
                    && !InStr(target, "control:") && target != "full" && target != "screen" {
                parts := StrSplit(target, ",")
                if parts.Length != 4
                    errors.Push("OCR area must contain exactly four comma-separated numbers")
                else {
                    for value in parts
                        if !IsNumber(Trim(value)) {
                            errors.Push("Every OCR area value must be numeric")
                            break
                        }
                }
            }

        case "Loop Start":
            if param != "" {
                opt := ParseLoopOptions(param)
                countText := LoopOptStr(opt, "count", "5")
                lower := StrLower(countText)
                if !(lower = "forever" || lower = "infinite" || IsNumber(countText))
                    errors.Push("Loop count must be a number or 'forever'")
            }

        case "Popup Detect":
            if param != "" {
                opt := ParseLoopOptions(param)
                hasWin := opt.Has("win") && Trim(opt["win"]) != ""
                hasRegion := opt.Has("region") && Trim(opt["region"]) != ""
                if !hasWin && !hasRegion
                    errors.Push("Popup Detect needs a window or a region to watch")
            }

        case "Wait for Window", "Wait Window Closed":
            if param != "" {
                opt := ParseLoopOptions(param)
                if !opt.Has("title") || Trim(opt["title"]) = ""
                    errors.Push("A window title is required (pick one from the list)")
            }

        case "Wait":
            if param = ""
                errors.Push("PARAM required: duration in milliseconds")
            else if !IsNumber(param)
                errors.Push("Duration must be a number of milliseconds")
            else {
                duration := Integer(param)
                if duration < 0
                    errors.Push("PARAM must be positive number")
                if duration > 300000
                    errors.Push("PARAM > 5 minutes - are you sure?")
            }

        case "Grab OCR to Var", "OCR Full Screen to Var":
            if action = "Grab OCR to Var" && target != "" {
                parts := StrSplit(target, ",")
                if parts.Length != 4
                    errors.Push("OCR area must contain exactly four comma-separated numbers")
                else {
                    for value in parts
                        if !IsNumber(Trim(value)) {
                            errors.Push("Every OCR area value must be numeric")
                            break
                        }
                }
            }
            if InStr(param, ",")
                errors.Push("Variable name should not contain commas; the OCR area now has its own field")
            else if param != "" && !RegExMatch(param, "^[A-Za-z_][A-Za-z0-9_]*$")
                errors.Push("Variable name must start with a letter/underscore and contain only letters, numbers, or underscores")

        case "Menu Select", "Scroll", "Idle Mouse":
            if param != "" && !IsNumber(param)
                errors.Push(spec["paramLabel"] . " must be numeric")

        case "Taskbar Activate":
            if param != "" && !RegExMatch(param, "^\d+\s*,\s*\d+$")
                errors.Push("Taskbar value must be position,count")

        case "Key Chord":
            if param != "" && StrSplit(param, ",").Length != 3
                errors.Push("Key chord must be modifier,key,count")

        case "Set Variable", "Grab Clipboard", "If Contains", "If Variable":
            if target != "" && !RegExMatch(target, "^[A-Za-z_][A-Za-z0-9_]*$")
                errors.Push("Variable name must start with a letter/underscore and contain only letters, numbers, or underscores")
            if action = "If Variable" && param != "" && !RegExMatch(param, "^(==?|!=|<>|>=|<=|>|<),.+$")
                errors.Push("Comparison must use operator,value (for example >=,5)")

        case "Extract from Clipboard":
            if param != "" && !(InStr(param, "between:") = 1 || InStr(param, "field:") = 1 || InStr(param, "regex:") = 1)
                errors.Push("Extraction rule must start with between:, field:, or regex:")
    }

    return errors
}

ShowParameterValidation(action, target, param) {
    errors := ValidateStepParameters(action, target, param)

    if errors.Length > 0 {
        msg := "⚠ Parameter Validation Warnings:`n`n"
        for error in errors {
            msg .= "  • " . error . "`n"
        }
        msg .= "`nContinue anyway?"

        result := MsgBox(msg, "Parameter Validation", "YesNo Icon!")
        return result = "Yes"
    }

    return true
}

UpdateLiveParamHints(*) {
    global ActionDD, ParamCombo, g_ParamHints

    action := ActionDD.Text

    if g_ParamHints.Has(action) {
        hint := g_ParamHints[action]

        try {
            ParamCombo.ToolTip := hint
        }
    }
}

