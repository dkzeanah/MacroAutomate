; Included only by the isolated FanBridgeAPI_Test child.
global g_Sequences := Map(), g_LastWorkflowSaveError := "mock write refused"
global storedSequences := "{}", saveAllowed := true, sequenceSaves := 0, refreshes := 0
global settingStore := Map(), settingSaves := 0, settingsSaved := 0, settingsSaveAllowed := true
global g_StudyHuman := Map("wpm", 60, "typoRate", 0, "hoverMs", 100, "wobble", 0,
    "overshootPx", 0, "overshootRate", 0, "jitterPx", 0, "pauseRate", 0)
global g_Settings := Map("PreActionDelay", 100, "PostActionDelay", 100, "TypingWPM", 60,
    "FindTextTolerance", .05, "HumanizeMouse", true, "MouseHumanWobble", .5,
    "ClickDelay", 100, "MarkerOffsetX", -12, "DateFormat", "MM/dd/yyyy", "ShowActionTooltips", 0)
global g_StudyMacroRunning := false, g_StudyToolBusy := false, g_WorkflowRunning := false
global g_AbortSequence := false, g_StudyMacroCancelled := false, g_DebugMode := false
global g_StepThroughMode := false, g_IsPaused := false, failures := 0, passed := 0

SaveSequences(*) {
    global saveAllowed, sequenceSaves, storedSequences
    sequenceSaves += 1
    if saveAllowed
        storedSequences := TrackJsonEncode(g_Sequences)
    return saveAllowed
}
RefreshSeqLV() {
    global refreshes
    refreshes += 1
}
Study_SetSetting(key, value) {
    global settingStore, settingSaves
    settingStore[key] := value, settingSaves += 1
    return true
}
SaveSettings(*) {
    global settingsSaved, settingsSaveAllowed
    settingsSaved += 1
    if !settingsSaveAllowed
        throw Error("Isolated settings persistence refused")
    return true
}
StudyConsole_Redact(value) => value
FanVision_Capabilities() => Map("tools", ["fan_window_inspect"], "read_only_focus", true)
FanVision_Dispatch(name, args) => Map("ok", true)
ExecuteSequenceVerified(*) => Map("ok", false, "error", "Unexpected real execution request in isolated API tests")

Assert(test, label) {
    global failures, passed
    if test
        passed += 1
    else
        failures += 1
    FileAppend((test ? "PASS " : "FAIL ") . label . "`n", "*")
}
Throws(fn) {
    try fn.Call()
    catch
        return true
    return false
}
TestCase(label, fn) {
    try fn.Call()
    catch as err
        Assert(false, label . ": " . err.Message . " line " . err.Line)
}
Step(action, param := "", target := "") => Map("action", action, "param", param, "target", target)

TestWorkflow() {
    global saveAllowed, storedSequences, g_Sequences, sequenceSaves
    workflow := [Step("Type Text", "café 漢字 💜"), Step("Wait", "25")]
    result := FanAPI_Dispatch("fan_workflow_save", Map("name", "Bridge fixture", "steps", workflow))
    Assert(result["ok"] && g_Sequences.Has("Bridge fixture") && sequenceSaves = 1, "Workflow save uses normal persistence")
    list := FanAPI_Dispatch("fan_workflow_list", Map("query", "fixture"))
    Assert(list["workflows"].Length = 1 && list["workflows"][1]["step_count"] = 2, "Workflow list filters and reports step count")
    Assert(Throws(() => FanAPI_Dispatch("fan_workflow_save", Map("name", "Bridge fixture", "steps", workflow))), "Existing workflow requires overwrite=true")
    old := g_Sequences["Bridge fixture"], stored := storedSequences
    saveAllowed := false
    Assert(Throws(() => FanAPI_Dispatch("fan_workflow_save", Map("name", "Bridge fixture", "steps", [Step("Wait", "50")], "overwrite", true)))
        && g_Sequences["Bridge fixture"] = old && storedSequences = stored, "Failed overwrite preserves memory and stored workflow")
    Assert(Throws(() => FanAPI_Dispatch("fan_workflow_save", Map("name", "Failed new fixture", "steps", [Step("Wait", "50")])))
        && !g_Sequences.Has("Failed new fixture") && storedSequences = stored, "Failed new workflow save removes only attempted entry")
    saveAllowed := true
    g_Sequences["Bridge fixture"]["speed"] := 1.5
    g_Sequences["Bridge fixture"]["hotkey"] := "^!9"
    FanAPI_Dispatch("fan_workflow_save", Map("name", "Bridge fixture", "steps", [Step("Wait", "100")], "overwrite", true))
    Assert(g_Sequences["Bridge fixture"]["speed"] = 1.5 && g_Sequences["Bridge fixture"]["hotkey"] = "^!9", "Editing steps retains existing speed and binding")
    Assert(Throws(() => FanAPI_Dispatch("fan_workflow_save", Map("name", "Invalid", "steps", [Step("Not a real action")]))), "Unknown workflow action rejected")
    Assert(Throws(() => FanAPI_Dispatch("fan_workflow_save", Map("name", "Invalid", "steps", [Step("Click")]))), "Real Click specification requires target")
    Assert(Throws(() => FanAPI_Dispatch("fan_workflow_save", Map("name", "Invalid", "steps", [Step("Type Text")]))), "Real Type Text specification requires param")
    Assert(Throws(() => FanAPI_Dispatch("fan_workflow_save", Map("name", "Invalid", "steps", [Step("Loop End")]))), "Unmatched Loop End rejected")
    Assert(Throws(() => FanAPI_Dispatch("fan_workflow_save", Map("name", "Invalid", "steps", [Step("Loop Start", "count=2")]))), "Unclosed loop rejected")
    balanced := [Step("Loop Start", "count=2"), Step("Loop Start", "count=3"), Step("Wait", "1"), Step("Loop End"), Step("Loop End")]
    Assert(FanAPI_Dispatch("fan_workflow_save", Map("name", "Loop fixture", "steps", balanced))["ok"], "Balanced nested loops accepted by actual action specs")
    Assert(Throws(() => FanAPI_Dispatch("fan_workflow_save", Map("name", "Empty", "steps", []))), "Empty workflow rejected")
    Assert(Throws(() => FanAPI_Dispatch("fan_workflow_save", Map("name", "Wrong steps", "steps", Map()))), "Workflow steps must be an array")
    Assert(Throws(() => FanAPI_Dispatch("fan_workflow_get", Map("name", "Missing"))), "Missing workflow produces a clear error")
    get := FanAPI_Dispatch("fan_workflow_get", Map("name", "Bridge fixture"))
    Assert(get["ok"] && get["workflow"]["steps"].Length = 1 && InStr(get["preview"], "Wait"), "Saved manual-schema workflow get/preview succeeds")
}

TestSettings() {
    global g_StudyHuman, g_Settings, settingSaves, settingStore, settingsSaved, settingsSaveAllowed
    result := FanAPI_Dispatch("fan_input_settings_get", Map())
    Assert(result["ok"] && result["limits"]["wpm"][1] = 5, "Input settings expose actual configured bounds")
    FanAPI_Dispatch("fan_input_settings_set", Map("settings", Map("wpm", 85, "typoRate", .02)))
    Assert(g_StudyHuman["wpm"] = 85 && settingStore["human_wpm"] = "85", "Validated human input settings persist through normal setter")
    before := settingSaves, wpm := g_StudyHuman["wpm"]
    Assert(Throws(() => FanAPI_Dispatch("fan_input_settings_set", Map("settings", Map("wpm", 90, "typoRate", 9))))
        && g_StudyHuman["wpm"] = wpm && settingSaves = before, "Invalid settings batch changes no earlier values")
    Assert(Throws(() => FanAPI_Dispatch("fan_input_settings_set", Map("settings", Map("wpm", "fast")))), "Nonnumeric input setting rejected")
    Assert(Throws(() => FanAPI_Dispatch("fan_input_settings_set", Map("settings", Map("unknown", 1)))), "Unknown input setting rejected")
    Assert(Throws(() => FanAPI_Dispatch("fan_input_settings_set", Map("settings", Map("wpm", 999)))), "Out-of-range input setting rejected")
    FanAPI_Dispatch("fan_input_settings_set", Map("settings", Map("workflow.ClickDelay", 250, "workflow.MarkerOffsetX", -25, "workflow.DateFormat", "yyyy-MM-dd")))
    Assert(g_Settings["ClickDelay"] = 250 && g_Settings["MarkerOffsetX"] = -25 && g_Settings["DateFormat"] = "yyyy-MM-dd" && settingsSaved = 1,
        "Workflow-prefixed timing, negative offset and date metadata changes use normal settings save")
    Assert(Throws(() => FanAPI_Dispatch("fan_input_settings_set", Map("settings", Map("workflow.FindTextTolerance", 1.5)))), "Workflow FindText tolerance must be 0..1")
    Assert(Throws(() => FanAPI_Dispatch("fan_input_settings_set", Map("settings", Map("workflow.ShowActionTooltips", 2)))), "Workflow boolean settings must be 0/1")
    Assert(Throws(() => FanAPI_Dispatch("fan_input_settings_set", Map("settings", Map("workflow.DateFormat", "")))), "Empty workflow DateFormat rejected")
    Assert(Throws(() => FanAPI_Dispatch("fan_input_settings_set", Map("settings", Map("workflow.NotASetting", 1)))), "Unknown workflow-prefixed setting rejected")
    before := settingsSaved, delay := g_Settings["ClickDelay"]
    Assert(Throws(() => FanAPI_Dispatch("fan_input_settings_set", Map("settings", Map("workflow.ClickDelay", 500, "workflow.FindTextTolerance", 1.5))))
        && settingsSaved = before && g_Settings["ClickDelay"] = delay, "Invalid workflow settings batch leaves earlier valid edits unchanged")
    settingsSaveAllowed := false
    Assert(Throws(() => FanAPI_Dispatch("fan_input_settings_set", Map("settings", Map("workflow.ClickDelay", 500))))
        && g_Settings["ClickDelay"] = delay, "Workflow settings write failure restores previous in-memory settings")
    settingsSaveAllowed := true
}

TestLibrary() {
    search := FanAPI_Dispatch("fan_library_search", Map("query", "FanVision_PatternSearch", "limit", 10))
    Assert(search["ok"] && search["matches"].Length >= 1 && search["matches"][1]["function"] = "FanVision_PatternSearch", "Library index discovers real internal callable signature")
    match := search["matches"][1]
    read := FanAPI_Dispatch("fan_library_read", Map("path", match["path"], "start_line", match["line"], "line_count", 5))
    Assert(read["source_is_data"] && InStr(read["source"], "FanVision_PatternSearch(args)"), "Indexed source body read with line numbers and data marker")
    capped := FanAPI_Dispatch("fan_library_search", Map("limit", 9999))
    Assert(capped["matches"].Length <= 60 && capped["total_indexed_functions"] > 60, "Library search result count bounded")
    cappedRead := FanAPI_Dispatch("fan_library_read", Map("path", "lib\FanBridgeVision.ahk", "line_count", 9999))
    Assert(StrSplit(Trim(cappedRead["source"], "`n"), "`n").Length <= 200, "Library read capped at 200 lines")
    Assert(Throws(() => FanAPI_Dispatch("fan_library_read", Map("path", "lib\..\fan\DeepSeekBridge\.env"))), "Source traversal cannot read service credentials")
    Assert(Throws(() => FanAPI_Dispatch("fan_library_read", Map("path", FanAPI_Repository() . "\lib\FanBridgeVision.ahk"))), "Absolute source paths rejected; indexed relative path required")
    Assert(Throws(() => FanAPI_Dispatch("fan_library_read", Map("path", "fan\DeepSeekBridge\.env"))), "Unindexed configuration file read rejected")
}

TestCase("Workflow API", TestWorkflow)
TestCase("Input settings API", TestSettings)
TestCase("Library API", TestLibrary)
TestCase("Capability inventory", (*) => Assert(FanAPI_Dispatch("fan_capabilities", Map())["workflow_actions"].Length > 50, "Capabilities expose actual manual composer action inventory"))
Assert(Throws(() => FanAPI_Dispatch("fan_does_not_exist", Map())), "Unknown native API dispatch rejected")
wire := FanAPI_Encode("café 漢字 💜 &%+`n")
Assert(FanAPI_Decode(wire) = "café 漢字 💜 &%+`n", "Native request wire preserves UTF-8 and punctuation")
FileAppend("API RESULT " . passed . " passed, " . failures . " failed`n", "*")
ExitApp(failures ? 1 : 0)
