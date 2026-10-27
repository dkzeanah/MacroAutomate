#Requires AutoHotkey v2.0
#Warn All, Off
global APP_ROOT := A_ScriptDir . "\..", settings := Map(), passed := 0, failed := 0
Study_GetSetting(key, fallback := "") => settings.Get(key, fallback)
Study_SetSetting(key, value) => settings[key] := value
Study_TempDir() => A_ScriptDir . "\tests\runtime"
StudyLive_LogSafe(text) => 0
Check(ok, label) {
    global passed, failed
    ok ? passed++ : failed++
    FileAppend((ok ? "PASS " : "FAIL ") . label . "`n", "*")
}
#Include ..\lib\TrackSQLite.ahk
#Include ..\lib\TrackUtil.ahk
#Include ..\lib\TrackingDB.ahk
#Include ..\lib\StudyConsole.ahk
#Include ..\lib\StudyLLM.ahk
#Include ..\lib\StudyComposer.ahk
#Include ..\lib\StudyTools.ahk
#Include ..\lib\StudyMath.ahk
#Include ..\lib\StudyDemo.ahk

Fixture(kind, name) => Map("kind", kind, "name", name, "x", 20, "y", 20, "w", 100, "h", 30,
    "protected", false, "value", "", "checked", 0)
Accepts(script, ctx, math) {
    try {
        StudyDemo_ValidatePlan(StudyTools_Compile(script, ctx), math, ctx)
        return true
    } catch
        return false
}
; This build stores audit documents in SQLite. Keep this regression isolated
; from the user's configured unified database and read through its document API.
global DATA_DIR := A_Temp . "\FanIntelligence-" . DllCall("GetCurrentProcessId","UInt")
DirCreate(DATA_DIR)
global g_FanDataConfigOverride := DATA_DIR . "\storage.json"
FanData_SaveConfig(Map("learning_validation",false))
TrackDB_Init(DATA_DIR . "\fixture.sqlite")
; Write the pointer first; SaveConfig intentionally routes preferences into an
; already configured database and cannot bootstrap that pointer itself.
FileDelete(g_FanDataConfigOverride)
FileAppend(TrackJsonEncode(Map("unified_db",DATA_DIR . "\fixture.sqlite")),g_FanDataConfigOverride,"UTF-8-RAW")
FanData_Config(true)
FanData_SaveConfig(Map("unified_db",DATA_DIR . "\fixture.sqlite","learning_validation",false))
try {
    EnvSet("DEEPSEEK_API_KEY", "synthetic-console-secret")
    c := Fixture("edit", "Solution x")
    feature := StudyFeatures_Describe(c, "1")
    Check(feature["name"] = "Solution x" && InStr(feature["function"], "verify") && feature["supported"] = "TYPE", "control identity has an explicit name, function, supported action and provenance")
    ctx := Map("url", "file:///fixture#stage1", "features", Map("1", feature))
    StudyFeatures_Remember(ctx, "1", "Input all verified roots for x", "fixture-model")
    restored := StudyFeatures_Describe(c, "8", ctx["url"])
    Check(restored.Has("remembered_description") && restored["remembered_description"]["description"] = "Input all verified roots for x", "feature description persists across changed ephemeral IDs")
    Check(!StudyFeatures_Describe(c, "1", "file:///other").Has("remembered_description"), "feature memory is scoped to page URL and identity")
    StudyConsole_Log("LLM", "redaction.fixture", Map("prompt", "secret=synthetic-console-secret", "authorization", "Bearer fixture-secret"))
    audit := FanFileRead(g_StudyConsole["path"], "UTF-8")
    Check(!InStr(audit, "synthetic-console-secret") && !InStr(audit, "Bearer fixture-secret") && InStr(audit, "REDACTED"), "persistent console redacts registered credentials and bearer values")
    escapedSecret := 'fixture"quote\ α'
    StudyConsole_Secret(escapedSecret)
    StudyConsole_Log("LLM", "redaction.escape.fixture", Map("prompt", escapedSecret))
    audit := FanFileRead(g_StudyConsole["path"], "UTF-8")
    Check(!InStr(audit, escapedSecret) && !InStr(audit, TrackJsonEscape(escapedSecret)), "credential redaction survives JSON quotes, backslashes and Unicode")
    records := StrSplit(Trim(audit, "`r`n"), "`n"), validJson := true, seq := 0
    for , encoded in records {
        record := TrackJsonDecode(encoded)
        if record["seq"] != ++seq
            validJson := false
    }
    Check(validJson, "all audit records remain valid JSON with monotonic sequence numbers")
    catalog := Map("1", c, "2", Fixture("dropdown", "Equation family"), "3", Fixture("checkbox", "All real solutions"),
        "4", Fixture("checkbox", "Domain checked"), "5", Fixture("checkbox", "Guess without verification"))
    ctx := Map("catalog", catalog, "q", Map("text", "Equation", "qtype", "shorttext"))
    math := Map("document", Map("topic", "linear"), "verified", Map("variables", ["x"], "solutions", [Map("x", "7")]))
    script := "TYPE 1 7`nCHOOSE 2 Linear`nSET 3 1`nSET 4 1`nSET 5 0"
    Check(Accepts(script, ctx, math), "generated plan matches every required exact solution and control state")
    Check(!Accepts(StrReplace(script, "TYPE 1 7", "TYPE 1 8"), ctx, math), "wrong algebra value is rejected before execution")
    Check(!Accepts(StrReplace(script, "TYPE 1 7", 'TYPE 1 "7"'), ctx, math), "accidental enclosing literal quotes are rejected before execution")
    Check(!Accepts(StrReplace(script, "SET 4 1", ""), ctx, math), "omitted domain control is rejected before execution")
    Check(!Accepts(script . "`nSET 5 1", ctx, math), "later contradictory write cannot bypass the verified goal")
    Check(!Accepts(StrReplace(script, "CHOOSE 2 Linear", "CHOOSE 2 Quadratic"), ctx, math), "wrong equation family is rejected")
    Check(!Accepts(script . "`nCLICK 99", ctx, math), "invented control ID is rejected")
    Check(!Accepts(script . "`nRUN calc.exe", ctx, math), "model-created executable code is rejected")
    g_StudyDemoBusy := true
    g_StudyDemoUrl := "file:///authorized/algebra_portal.html"
    Check(StudyDemo_CanActivate("Next problem", g_StudyDemoUrl . "#stage2"), "demo button permission applies to its exact authorized page")
    Check(!StudyDemo_CanActivate("Next problem", "file:///other/algebra_portal.html#stage2"), "matching filename at another path cannot gain demo navigation permission")
    Check(!StudyDemo_CanActivate("Restart demo", g_StudyDemoUrl . "#stage2"), "unlisted page operation cannot gain demo button permission")
    g_StudyDemoBusy := false
    Check(!StudyDemo_CanActivate("Next problem", g_StudyDemoUrl . "#stage2"), "demo button permission expires when the demo stops")
} catch as err {
    failed++
    FileAppend("ERROR " . err.Message . " at " . err.File . ":" . err.Line . "`n", "*")
}
FanState_Close()
TrackDB_Close()
if !failed
    DirDelete(DATA_DIR,true)
FileAppend("RESULT: " . passed . " passed, " . failed . " failed`n", "*")
ExitApp(failed ? 1 : 0)
