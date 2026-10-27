#Requires AutoHotkey v2.0
#Warn All, Off
global providerSettings := Map(), passed := 0, failed := 0
global streamedText := "", firstDeltaAt := 0
StreamDelta(kind, value) {
    global streamedText, firstDeltaAt
    if kind = "answer" {
        if !firstDeltaAt
            firstDeltaAt := A_TickCount
        streamedText .= value
    }
}
Study_GetSetting(key, fallback := "") => providerSettings.Has(key) ? providerSettings[key] : fallback
Check(ok, label) {
    global passed, failed
    ok ? passed++ : failed++
    FileAppend((ok ? "PASS " : "FAIL ") . label . "`n", "*")
}
VerifyLiteral(plan) {
    if plan["steps"][3]["param"] != "Paris"
        throw Error("Literal value differs from the exact goal. Remove enclosing quotes.")
}
#Include ..\lib\TrackUtil.ahk
#Include ..\lib\StudyConsole.ahk
#Include ..\lib\StudyLLM.ahk
#Include ..\lib\StudyComposer.ahk
#Include ..\lib\StudyPortal.ahk
#Include ..\lib\StudyTools.ahk
; Process-local synthetic key overrides any real key before any loopback call.
EnvSet("DEEPSEEK_API_KEY", "synthetic-loopback-fixture")
try {
    g_StudyLLM_Endpoint := "http://127.0.0.1:18766"
    result := StudyLLM_Ask("TYPE 1 café α", Map("maxTokens", 100))
    Check(result["ok"] && result["answer"] = "TYPE 1 café α", "async provider transport preserves UTF-8 workflow text")
    Check(result["promptTokens"] = 12 && result["completionTokens"] = 4 && result["costUSD"] > 0, "provider usage and cost parsed from nested JSON")
    before := g_StudyLLM_SpentUSD
    g_StudyLLM_Endpoint := "http://127.0.0.1:18766/truncated"
    result := StudyLLM_Ask("TYPE 1 incomplete", Map("maxTokens", 100))
    Check(!result["ok"] && InStr(result["error"], "Incomplete"), "truncated workflow response refused")
    Check(g_StudyLLM_SpentUSD > before, "truncated completions still count toward cost")
    g_StudyLLM_Endpoint := "http://127.0.0.1:18766/broken"
    Check(!StudyLLM_Ask("bad JSON")["ok"], "malformed provider JSON refused")
    g_StudyLLM_Endpoint := "http://127.0.0.1:18766/slow"
    SetTimer(StudyLLM_CancelRequest, -150)
    started := A_TickCount
    result := StudyLLM_Ask("slow request")
    Check(!result["ok"] && InStr(result["error"], "Cancelled") && A_TickCount-started < 1500, "ABORT interrupts pending response without blocking the GUI")
    providerSettings["cost_cap_usd"] := "0.000001"
    Check(!StudyLLM_Ask("budget exhausted")["ok"], "session budget refuses provider call")
    g_StudyLLM_Busy := true
    Check(!StudyLLM_Ask("overlap")["ok"], "concurrent provider request refused")
    g_StudyLLM_Busy := false
    providerSettings["cost_cap_usd"] := "2.00"
    g_StudyLLM_Endpoint := "http://127.0.0.1:18766"
    streamedText := "", firstDeltaAt := 0
    result := StudyLLM_Ask("Custom input", Map("stream", true, "onDelta", StreamDelta, "maxTokens", 100))
    Check(result["ok"] && result["answer"] = "café α → Custom input" && streamedText = result["answer"],
        "SSE preserves UTF-8 characters split across packets and assembles the answer")
    Check(firstDeltaAt && A_TickCount-firstDeltaAt >= 150, "console receives reply deltas before the HTTP response completes")
    Check(result["promptTokens"] = 12 && result["completionTokens"] = 4, "stream usage survives null usage events")
    g_StudyLLM_Endpoint := "http://127.0.0.1:18766/history"
    result := StudyLLM_Ask("Follow-up", Map("stream", true, "maxTokens", 100,
        "history", [Map("role", "user", "content", "First message"), Map("role", "assistant", "content", "First reply")]))
    Check(result["ok"] && result["answer"] = "history ok", "chat sends prior user and assistant turns before the custom message")
    g_StudyLLM_Endpoint := "http://127.0.0.1:18766/streamtruncate"
    result := StudyLLM_Ask("Truncated", Map("stream", true, "maxTokens", 100))
    Check(!result["ok"] && InStr(result["error"], "Incomplete"), "truncated streaming reply cannot become a completed answer")
    g_StudyLLM_Endpoint := "http://127.0.0.1:18766/disconnect"
    before := g_StudyLLM_SpentUSD
    result := StudyLLM_Ask("Disconnected", Map("stream", true, "maxTokens", 100))
    Check(!result["ok"] && InStr(result["error"], "Incomplete") && g_StudyLLM_SpentUSD > before,
        "missing SSE end marker fails and partial usage is counted")
    g_StudyLLM_Endpoint := "http://127.0.0.1:18766/streamslow"
    SetTimer(StudyLLM_CancelRequest, -300)
    started := A_TickCount
    result := StudyLLM_Ask("Cancel stream", Map("stream", true, "maxTokens", 100))
    Check(!result["ok"] && InStr(result["error"], "Cancelled") && A_TickCount-started < 1500,
        "Cancel interrupts an unfinished streamed reply while the GUI stays responsive")
    g_StudyLLM_Endpoint := "http://127.0.0.1:18766/planner"
    ctl := Map("kind", "edit", "name", "Answer", "protected", false, "x", 10, "y", 10, "w", 100, "h", 30)
    ctx := Map("catalog", Map("1", ctl), "q", Map("raw", "Practice", "qtype", "shorttext"), "text", "1 | edit | Answer")
    proposal := StudyTools_RequestPlan(ctx, "Type Paris into Answer")
    Check(proposal["ok"] && proposal["planValid"] && proposal["planningAttempts"] = 2
        && proposal["answer"] = "TYPE 1 Paris", "model repairs wrong control role using actual compiler feedback")
    g_StudyLLM_Endpoint := "http://127.0.0.1:18766/semantic"
    proposal := StudyTools_RequestPlan(ctx, "Type exactly Paris into Answer", VerifyLiteral)
    Check(proposal["ok"] && proposal["planValid"] && proposal["planningAttempts"] = 2
        && proposal["answer"] = "TYPE 1 Paris", "model repairs semantic goal mismatch before any input")
    before := g_StudyLLM_SpentUSD
    result := StudyLLM_Ask("missing visual evidence", Map("imagePath", A_ScriptDir . "\tests\runtime\missing-image.png"))
    Check(!result["ok"] && InStr(result["error"], "image is unavailable") && g_StudyLLM_SpentUSD = before,
        "missing screenshot cannot silently become a text-only visual request")
    imageFixture := A_ScriptDir . "\tests\runtime\not-an-image.txt"
    FileAppend("fixture", imageFixture, "UTF-8")
    try {
        result := StudyLLM_Ask("wrong image format", Map("imagePath", imageFixture))
        Check(!result["ok"] && InStr(result["error"], "Could not read the image"), "unsupported image format refused before transport")
    } finally
        FileDelete(imageFixture)
} catch as err {
    failed++
    FileAppend("ERROR " . err.Message . " at " . err.File . ":" . err.Line . "`n", "*")
}
FileAppend("RESULT: " . passed . " passed, " . failed . " failed`n", "*")
ExitApp(failed ? 1 : 0)
