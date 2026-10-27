; Isolated SQLite integration checks for live memory and answer verification.
#Requires AutoHotkey v2.0
#Warn All, Off
global memoryDb := 0, passed := 0, failed := 0
global memoryPath := A_ScriptDir . "\tests\runtime\memory-" . A_TickCount . ".db"
DirCreate(A_ScriptDir . "\tests\runtime")
TrackDB() {
    global memoryDb
    if !memoryDb
        memoryDb := TrackSQLite(memoryPath)
    return memoryDb
}
Check(ok, label) {
    global passed, failed
    ok ? passed++ : failed++
    FileAppend((ok ? "PASS " : "FAIL ") . label . "`n", "*")
}
TrackLogError(where, err) => FileAppend("ERROR " . where . ": " . err.Message . "`n", "*")
LogErrorToFile(err, mode := "", where := "") => TrackLogError(where, err)
LogDiagnostic(args*) => 0
ShowStatus(args*) => 0
ShowTooltipTimed(args*) => 0
Study_ReadAlong_PickRegion() => 0
Study_ReadAlong_Toggle() => 0
Study_TempDir() => A_ScriptDir . "\tests\runtime"
Track_WriteFile(path, value) => FileAppend(value, path, "UTF-8")
Snip_SaveRegion(args*) => false
QuickOCR_SelectRegion() => Map()
#Include ..\lib\TrackSQLite.ahk
#Include ..\lib\TrackUtil.ahk
#Include ..\lib\StudyConsole.ahk
#Include ..\lib\SnipParse.ahk
#Include ..\lib\StudyDB.ahk
#Include ..\lib\StudyLLM.ahk
#Include ..\lib\StudyAutomation.ahk
#Include ..\lib\StudyPortal.ahk
#Include ..\lib\StudyComposer.ahk
#Include ..\lib\StudyAssistant.ahk
#Include ..\lib\StudyLive.ahk
#Include ..\lib\StudyTools.ahk

try {
    Check(Study_Schema(), "production schema initializes on an empty database")
    q := Map("qtype", "single", "text", "Which is the largest planet?", "raw", "Which is the largest planet?",
        "choices", [Map("tag", "A", "text", "Earth"), Map("tag", "B", "text", "Jupiter"), Map("tag", "C", "text", "Mars")], "blanks", [])
    id := StudyLive_StoreQuestion(q, "")
    Check(id > 0, "live question stored using production SQL")
    Study_RecordAnswer(id, "B", "user-confirmed", "validation", 0.95, "Confirmed fixture")
    row := TrackDB().QueryRow("SELECT * FROM qa_item WHERE id=?", id)
    ans := Study_Answer(row, false)
    Check(ans["source"] = "verified" && ans["answer"] = "B", "learn-once uses confirmed memory without provider access")
    q["choices"] := [Map("tag", "A", "text", "Jupiter"), Map("tag", "B", "text", "Mars"), Map("tag", "C", "text", "Earth")]
    Check(StudyLive_StoreQuestion(q, "") = id, "option shuffle retains exact question identity")
    row := TrackDB().QueryRow("SELECT * FROM qa_item WHERE id=?", id)
    Check(row["answer"] = "A" && row["state"] = "user-confirmed", "option shuffle keeps meaning and confirmed state")
    history := Study_AnswerHistory(id)
    Check(history.Length = 2 && InStr(history[2]["choices_snapshot"], "B|Jupiter")
        && InStr(history[1]["choices_snapshot"], "A|Jupiter"), "answer versions preserve their original option labels")
    q["choices"][3]["text"] := "Saturn"
    StudyLive_StoreQuestion(q, "")
    Check(!Study_VerifiedAnswer(id).Count, "changed choice set invalidates automatic verified reuse")
    Check(Study_AnswerHistory(id).Length = 3, "invalidation preserves earlier confirmed versions")
    Study_RecordAnswer(id, "A", "portal-confirmed", "fixture", 0.95)
    Check(Study_VerifiedAnswer(id).Count > 0, "portal-confirmed answers can be reused")
    Check(Study_QuestionQualifiers("Which planet is NOT largest?") != Study_QuestionQualifiers("Which planet is largest?"), "history distinguishes negation")
    Check(Study_QuestionQualifiers("Speed at 10 m/s") != Study_QuestionQualifiers("Speed at 20 m/s"), "history distinguishes quantities")
    other := q.Clone()
    other["text"] := "What is the largest planet?"
    other["raw"] := other["text"]
    other["choices"] := [Map("tag", "A", "text", "Saturn"), Map("tag", "B", "text", "Jupiter"), Map("tag", "C", "text", "Mars")]
    otherId := StudyLive_StoreQuestion(other, "")
    near := Study_FindVerifiedSimilar(otherId, other["text"], other["choices"], "mc")
    Check(near.Count && near["answer"] = "B", "provisional history remaps complete choice sets")
    other["text"] := "Which is not the largest planet?"
    Check(!Study_FindVerifiedSimilar(otherId, other["text"], other["choices"], "mc").Count, "negated history transfer refused")
    n := Map("qtype", "numeric", "choices", [], "raw", "Speed", "blanks", [])
    Check(StudyLive_Recheck(n, "12.5 m/s")["answer"] = "12.5 m/s", "numeric recheck preserves units")
    longQ := q.Clone(), nextQ := q.Clone()
    longQ["text"] := Format("{:140}", "A long shared prefix") . " ending one"
    nextQ["text"] := Format("{:140}", "A long shared prefix") . " ending two"
    Check(StudyLive_StoreQuestion(longQ, "") != StudyLive_StoreQuestion(nextQ, ""), "long question endings have separate database identities")
    Check(StudyLive_StoreQuestion(longQ, "") = StudyLive_StoreQuestion(longQ, ""), "repeated exact question is deduplicated")
} catch as err {
    failed++
    FileAppend("ERROR " . err.Message . " at " . err.File . ":" . err.Line . "`n" . err.Stack, "*")
} finally {
    if memoryDb
        memoryDb.Close()
}
FileAppend("RESULT: " . passed . " passed, " . failed . " failed`n", "*")
ExitApp(failed ? 1 : 0)
