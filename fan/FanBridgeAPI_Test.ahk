#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
; Runs the real API and standalone SDK in independent child processes. Actual
; action specifications are extracted from current source at each run; no app
; startup, user database, window clicks or provider/API requests are involved.

ExtractFunction(path, name) {
    source := FileRead(path, "UTF-8")
    if !RegExMatch(source, "ms)^" . name . "\([^\r\n]*.*?^\}", &found)
        throw Error("Cannot extract current source function " . name)
    return found[0] . "`n"
}
RunFixture(path, validate := false) {
    command := '"' . A_AhkPath . '" /ErrorStdOut ' . (validate ? "/validate " : "") . '"' . path . '"'
    process := ComObject("WScript.Shell").Exec(command)
    output := process.StdOut.ReadAll() . process.StdErr.ReadAll()
    while process.Status = 0
        Sleep 10
    return Map("code", process.ExitCode, "output", output)
}

root := A_ScriptDir . "\..", cases := A_ScriptDir . "\tests", runtime := A_ScriptDir . "\DeepSeekBridge\.runtime"
DirCreate(runtime)
prefix := runtime . "\fanapi_test_" . DllCall("GetCurrentProcessId", "UInt")
apiChild := prefix . "_api.ahk", sdkChild := prefix . "_sdk.ahk", failures := 0
try {
    code := "#Requires AutoHotkey v2.0`n#Warn All, Off`n#Include " . root . "\lib\TrackUtil.ahk`n#Include " . root . "\lib\FanBridgeAPI.ahk`n"
    for , name in ["GetWorkflowActionNames", "MakeActionSpec", "GetWorkflowActionSpec"]
        code .= ExtractFunction(root . "\fan\Tabs\Tab_01_Workflow.ahk", name)
    for , name in ["NormalizeStepFailsafe", "DeserializeFailsafe"]
        code .= ExtractFunction(root . "\fan\Core\_Db.ahk", name)
    ; Keep the currently used preview behavior visible to the test instead of
    ; masking manual/Study step-schema mismatches with a test stub.
    for , name in ["StudyMacro_Preview", "StudyMacro_Clip"]
        code .= ExtractFunction(root . "\lib\StudyComposer.ahk", name)
    if !RegExMatch(FileRead(root . "\lib\StudyComposer.ahk", "UTF-8"), "ms)^StudyHuman_Limits\(\).*?(?=\r?\n\r?\n)", &limits)
        throw Error("Cannot extract input limits")
    code .= limits[0] . "`n" . FileRead(cases . "\fan_api_cases.ahk", "UTF-8")
    FileAppend(code, apiChild, "UTF-8")
    FileAppend("#Requires AutoHotkey v2.0`n#Warn All, Off`n#Include " . root . "\lib\FanBridgeClient.ahk`n"
        . FileRead(cases . "\fan_sdk_cases.ahk", "UTF-8"), sdkChild, "UTF-8")
    compile := RunFixture(root . "\lib\FanBridgeClient.ahk", true)
    FileAppend((compile["code"] = 0 ? "PASS " : "FAIL ") . "Standalone FanBridgeClient /validate`n" . compile["output"], "*")
    if compile["code"] != 0
        failures += 1
    for , path in [apiChild, sdkChild] {
        result := RunFixture(path)
        FileAppend(result["output"], "*")
        if result["code"] != 0
            failures += 1
    }
} catch as err {
    FileAppend("FAIL Test launcher: " . err.Message . " line " . err.Line . "`n", "*")
    failures += 1
} finally {
    for , path in [apiChild, sdkChild]
        if FileExist(path)
            FileDelete(path)
}
ExitApp(failures ? 1 : 0)
