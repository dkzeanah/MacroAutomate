; ═══════════════════════════════════════════════════════════════════════════════
; StudyHarness_Test.ahk - regression harness for the Live Portal perception and
; planning logic (classifier, question model, macro composer, answer parser).
;
; Runs the SAME code paths the "Dry-run Fixtures" button exercises, in a
; standalone process with stubs for the GUI/tracking/OCR layers, so the pure
; logic can be checked without a live portal or the main GUI:
;
;   AutoHotkey64.exe fan\StudyHarness_Test.ahk
;   -> prints PASS/FAIL lines, exit code 0 = all green
;
; Temporary verification aid for REALTIME_STUDY_ASSISTANT_SPEC.md section 2/7
; acceptance checks. Not loaded by MacroAutomator.ahk.
; ═══════════════════════════════════════════════════════════════════════════════
#Requires AutoHotkey v2.0
#Warn All, Off  ; standalone fixtures deliberately omit unrelated GUI libraries

results := []
Say(line) {
    global results
    results.Push(line)
    OutputDebug("[" . line . "]")
    FileAppend(line . "`n", "*")
}
TrackDB() => ""          ; make Study_Schema/Qa_Schema unavailable-but-safe
ShowStatus(msg, type := "info") => 0
LogErrorToFile(thrown, mode := "", context := "") => Say("ERR " . context . ": " . thrown.Message)
LogDiagnostic(msg, context := "", level := "") => 0
ShowTooltipTimed(text, duration := 0, x := "", y := "") => 0
TrackLogError(context, err) => Say("TRACKERR " . context)
Track_WriteFile(path, text) => (FileAppend(text, path), true)
Qa_OpenBank() => 0
QuickOCR_SelectRegion() => Map()
Snip_SaveRegion(region, path) => false
Snap_VisualSignature(path) => ""
Snap_SignatureDistance(a, b) => 0
MsgBoxTop(msg, title, opts) => "Yes"

#Include ..\lib\StudyDB.ahk
#Include ..\lib\TrackUtil.ahk
#Include ..\lib\StudyConsole.ahk
#Include ..\lib\StudyLLM.ahk
#Include ..\lib\StudyAutomation.ahk
#Include ..\lib\StudyPortal.ahk
#Include ..\lib\StudyComposer.ahk
#Include ..\lib\StudyTools.ahk
#Include ..\lib\StudyMath.ahk

FixCtl(kind, name, x, y) {
    return Map("kind", kind, "role", kind, "name", name, "value", "", "x", x, "y", y
             , "w", 16, "h", 16, "checked", false, "protected", false, "stText", "")
}

fixtures := [
    Map("name", "single choice (Acc radios)", "expect", "single", "answer", "B",
        "lines", ["Question 1", "Which gas do plants absorb for photosynthesis?", "A. Oxygen", "B. Carbon dioxide", "C. Nitrogen", "D. Hydrogen"],
        "controls", [FixCtl("radio", "Oxygen", 100, 120), FixCtl("radio", "Carbon dioxide", 100, 150)
                    , FixCtl("radio", "Nitrogen", 100, 180), FixCtl("radio", "Hydrogen", 100, 210)]),
    Map("name", "true/false (Acc radios)", "expect", "tf", "answer", "A",
        "lines", ["Question 2", "Water boils at 100C at sea level.", "A. True", "B. False"],
        "controls", [FixCtl("radio", "True", 100, 120), FixCtl("radio", "False", 100, 150)]),
    Map("name", "multi-select (Acc checkboxes)", "expect", "multi", "answer", "A, C",
        "lines", ["Question 3", "Select all that apply:", "A. Apple", "B. Banana", "C. Carrot", "D. Date"],
        "controls", [FixCtl("checkbox", "Apple", 100, 120), FixCtl("checkbox", "Banana", 100, 150)
                    , FixCtl("checkbox", "Carrot", 100, 180), FixCtl("checkbox", "Date", 100, 210)]),
    Map("name", "dropdown", "expect", "dropdown", "answer", "Paris",
        "lines", ["Question 4", "Choose the capital of France:", "Paris"],
        "controls", [FixCtl("dropdown", "Capital", 100, 120)]),
    Map("name", "fill in the blank (one edit)", "expect", "fillblank", "answer", "mitochondria",
        "lines", ["Question 5", "The powerhouse of the cell is the _______.", "mitochondria"],
        "controls", [FixCtl("edit", "answer", 100, 120)]),
    Map("name", "short text (one edit)", "expect", "shorttext", "answer", "Diffusion of water across a membrane",
        "lines", ["Question 6", "In one sentence, define osmosis."],
        "controls", [FixCtl("edit", "answer", 100, 120)]),
    Map("name", "numeric with units (one edit)", "expect", "numeric", "answer", "1500",
        "lines", ["Question 7", "Convert 1.5 km to meters. Include the unit."],
        "controls", [FixCtl("edit", "answer", 100, 120)]),
    Map("name", "OCR-only single choice (no a11y)", "expect", "single", "answer", "B",
        "lines", ["Question 8", "Which is the largest planet?", "A. Earth", "B. Jupiter", "C. Mars", "D. Venus"],
        "controls", []),
    Map("name", "image-based (no readable text)", "expect", "image", "answer", "",
        "lines", [], "controls", []),
    Map("name", "unknown widget -> abstain", "expect", "unknown", "answer", "",
        "lines", ["Question 10", "Drag the items into order.", "First", "Second"],
        "controls", [FixCtl("list", "Order list", 100, 120)])
]

pass := 0, fail := 0
for , fx in fixtures {
    ocr := Map("ok", true, "text", "", "lines", [], "words", [])
    for , t in fx["lines"] {
        ocr["lines"].Push(Map("text", t, "y", 60 + A_Index * 28, "x", 80, "w", 400, "h", 22))
        ocr["text"] .= (ocr["text"] = "" ? "" : "`n") . t
        for , wd in StrSplit(t, " ")
            ocr["words"].Push(Map("text", wd, "x", 80, "y", 60 + A_Index * 28, "w", 40, "h", 22))
    }
    q := StudyPercept_BuildQuestion(ocr, fx["controls"], Map("x", 0, "y", 0, "w", 800, "h", 600), "")
    okType := (q["qtype"] = fx["expect"])
    plan := StudyMacro_Compose(q, fx["answer"], "fill")
    mustAbstain := fx["answer"] = "" || InStr(fx["name"], "OCR-only")
    okPlan := mustAbstain ? !plan["ok"] : plan["ok"]
    p := StudyMacro_ParseAnswer(q, fx["answer"])
    okParse := (fx["answer"] = "") || (p["ok"])
    ok := okType && okPlan && okParse
    ok ? pass++ : fail++
    Say((ok ? "PASS " : "FAIL ") . fx["name"] . "  -> type " . q["qtype"] . " (want " . fx["expect"] . ")"
        . "  plan: " . (plan["ok"] ? StrReplace(StudyMacro_Preview(plan["steps"]), "`n", " | ") : plan["detail"])
        . (okParse ? "" : "  parse-fail"))
    if (q["qtype"] = "single" && fx["answer"] = "B")
        Say("  stem: [" . StrReplace(q["text"], "`n", " / ") . "]")
}

; Extra: answer parser robustness on prose the LLM might return
q2 := StudyPercept_BuildQuestion(
    Map("ok", true, "text", "", "lines", [Map("text", "Which is the largest planet?", "y", 60, "x", 80, "w", 400, "h", 22)
        , Map("text", "A. Earth", "y", 88, "x", 80, "w", 400, "h", 22)
        , Map("text", "B. Jupiter", "y", 116, "x", 80, "w", 400, "h", 22)
        , Map("text", "C. Mars", "y", 144, "x", 80, "w", 400, "h", 22)], "words", [])
    , [], Map("x", 0, "y", 0, "w", 800, "h", 600), "")
p := StudyMacro_ParseAnswer(q2, "ANSWER: B - Jupiter is the largest planet.")
if (p["ok"] && p["letters"].Length = 1 && p["letters"][1] = "B")
    Say("PASS prose-letter extraction (B from full sentence)"), pass++
else
    Say("FAIL prose-letter extraction"), fail++
p2 := StudyMacro_ParseAnswer(q2, "The largest planet is Jupiter.")
if (p2["ok"] && p2["letters"].Length = 1 && p2["letters"][1] = "B")
    Say("PASS text-match fallback (Jupiter -> B)"), pass++
else
    Say("FAIL text-match fallback"), fail++

Check(ok, label) {
    global pass, fail
    ok ? pass++ : fail++
    Say((ok ? "PASS " : "FAIL ") . label)
}

Check(!StudyMacro_ValueEqual("mito", "mitochondria"), "partial text is not accepted")
Check(!StudyMacro_ValueEqual("a b", "ab"), "spaces preserved in verification")
Check(!StudyMacro_ValueEqual("Paris", "paris"), "case preserved in verification")
Check(StudyMacro_ValueEqual("one`r`ntwo", "one`ntwo"), "line endings normalized")
Check(!StudyMacro_ParseAnswer(q2, "A, B")["ok"], "single-select rejects multiple answers")
Check(!StudyMacro_ParseAnswer(q2, "")["ok"], "empty choice answer rejected")
article := StudyMacro_ParseAnswer(q2, "Jupiter is a gas giant.")
Check(article["ok"] && article["letters"][1] = "B", "article a in prose is not mistaken for option A")
Check(!StudyMacro_Compose(q2, "B", "observe")["ok"], "observe cannot compose input")
Check(!StudyMacro_Compose(q2, "B", "suggest")["ok"], "suggest cannot compose input")
Check(!StudyMacro_Compose(q2, "B", "fill")["ok"], "OCR-only choice cannot produce unverifiable click")

ctl := FixCtl("edit", "Practice answer", -1100, 250)
qText := Map("qtype", "shorttext", "text", "Question", "raw", "Question", "choices", [], "blanks", [ctl], "buttons", [])
txtPlan := StudyMacro_Compose(qText, "Mitochondria", "fill")
Check(txtPlan["ok"] && IsObject(txtPlan["steps"][4]["acc"]), "text steps retain control identity for focus/read-back")
ctl["protected"] := true
Check(!StudyMacro_Compose(qText, "secret", "fill")["ok"], "protected field refused")
ctl["protected"] := false
qText["blanks"].Push(FixCtl("edit", "Second answer", -1100, 300))
Check(!StudyMacro_Compose(qText, "only one value", "fill")["ok"], "missing blank answer refused")
qText["qtype"] := "fillblank"
Check(StudyMacro_Compose(qText, "one || two", "fill")["ok"], "two blanks compose with explicit values")
Check(!StudyMacro_Compose(qText, "one || two || three", "fill")["ok"], "extra blank answers refused")

choices := [FixCtl("checkbox", "Apple", 10, 100), FixCtl("checkbox", "Banana", 10, 130), FixCtl("checkbox", "Carrot", 10, 160)]
for idx, c in choices {
    c["tag"] := Chr(64 + idx), c["text"] := c["name"]
}
choices[2]["checked"] := true
qMulti := Map("qtype", "multi", "raw", "Select all", "text", "Select all", "choices", choices, "buttons", [])
mp := StudyMacro_Compose(qMulti, "A, C", "fill")
Check(mp["ok"] && mp["steps"][3]["verify"]["expect"] = 0, "checkbox plan deselects unwanted existing answer")
Check(mp["steps"][1]["ensureState"], "selectable steps are idempotent")
Check(StudyMacro_ParseAnswer(qMulti, "AC")["letters"].Length = 2, "compact multiple letters accepted")
Check(StudyMacro_ParseAnswer(qMulti, "Apple and Carrot")["letters"].Length = 2, "multiple choice text maps every selected answer")
shuffled := [Map("tag", "A", "text", "Carrot"), Map("tag", "B", "text", "Apple"), Map("tag", "C", "text", "Banana")]
mapped := StudyMacro_RemapChoices(choices, shuffled, "A, C", "multi")
Check(mapped["ok"] && mapped["answer"] = "B, A", "verified choices remap by meaning after shuffle")
shuffled[3]["text"] := "Date"
Check(!StudyMacro_RemapChoices(choices, shuffled, "A", "single")["ok"], "materially changed choice set requires review")
duplicates := [Map("tag", "A", "text", "Apple"), Map("tag", "B", "text", "Apple"), Map("tag", "C", "text", "Carrot")]
Check(!StudyMacro_RemapChoices(duplicates, choices, "A", "single")["ok"], "duplicate choice mapping is refused")
longQ := qText.Clone(), otherQ := qText.Clone()
longQ["text"] := Format("{:130}", "Same long prefix") . " first ending"
otherQ["text"] := Format("{:130}", "Same long prefix") . " second ending"
Check(StudyPercept_QFP(longQ) != StudyPercept_QFP(otherQ), "question fingerprints retain endings after 120 characters")
fb := StudyPercept_FeedbackFromOCR(Map("ok", true, "text", "Select the correct answer", "lines", [Map("text", "Select the correct answer")]))
Check(fb["verdict"] = "unknown", "question wording is not portal feedback")
fb := StudyPercept_FeedbackFromOCR(Map("ok", true, "text", "Correct.", "lines", [Map("text", "Correct.")]))
Check(fb["verdict"] = "correct", "explicit standalone feedback recognized")
fb := StudyPercept_FeedbackFromOCR(Map("ok", true, "text", "Correct. Incorrect.", "lines", [Map("text", "Correct."), Map("text", "Incorrect.")]))
Check(fb["verdict"] = "unknown", "conflicting feedback requires review")

ctx := Map("catalog", Map("1", ctl, "2", choices[1]), "q", qText)
Check(StudyTools_Compile("TYPE 1 Mitochondria`nSET 2 1`nHOVER 1 150`nWAIT 100", ctx)["ok"], "workflow compiles observed IDs into verified steps")
Check(!StudyTools_Compile("TYPE 99 answer", ctx)["ok"], "workflow refuses invented IDs")
Check(!StudyTools_Compile("RUN powershell", ctx)["ok"], "workflow refuses executable code")
Check(!StudyTools_Compile("TYPE 1 good`nINVALID 1", ctx)["ok"], "entire malformed workflow rejected before first action")
Check(!StudyTools_Compile("WAIT 4000", ctx)["ok"], "bounded workflow wait")
Check(!StudyTools_Compile("TYPE 2 wrong", ctx)["ok"], "workflow validates control role")
Check(!StudyTools_Compile("CLICK 2", ctx)["ok"], "checkbox requires explicit desired state")
Check(!StudyTools_Compile("CHOOSE 1 Paris", ctx)["ok"], "dropdown command refuses text field")
ctx["catalog"]["3"] := FixCtl("dropdown", "Capital", 100, 200)
dp := StudyTools_Compile("CHOOSE 3 Paris", ctx)
Check(dp["ok"] && dp["steps"].Length = 1 && dp["steps"][1]["action"] = "Choose Dropdown", "dropdown uses keyboard selection with exact read-back")
tooMany := ""
Loop 51
    tooMany .= "CHOOSE 3 Paris`n"
Check(!StudyTools_Compile(tooMany, ctx)["ok"], "dropdown commands obey the overall step limit")
ctl["protected"] := true
Check(!StudyTools_Compile("TYPE 1 hidden", ctx)["ok"], "workflow refuses protected field")
ctl["protected"] := false

x := -2000, y := 999
StudyHuman_ClampPoint(&x, &y, ctl)
Check(x >= ctl["x"] && x < ctl["x"] + ctl["w"] && y >= ctl["y"] && y < ctl["y"] + ctl["h"], "jitter/overshoot clamped on negative monitor coordinates")
pts := StudyHuman_Path(-1800, 400, -1100, 250)
Check(pts[pts.Length][1] = -1100 && pts[pts.Length][2] = 250, "curved path ends at intended point")
g_StudyMacroCancelled := true
Check(!StudyHuman_TypeText("must never type"), "cancel prevents even first character")
Check(!StudyHuman_MoveTo(123, 456), "cancel prevents pointer movement")
Check(!StudyHuman_Sleep(2000), "cancel interrupts wait")

doc := TrackJsonDecode('{"choices":[{"message":{"content":"TYPE 1 Paris"},"finish_reason":"stop"}],"usage":{"prompt_tokens":12,"completion_tokens":4}}')
Check(doc["usage"]["prompt_tokens"] = 12 && doc["choices"][1]["message"]["content"] = "TYPE 1 Paris", "nested provider JSON with numeric token usage")
badJson := false
try TrackJsonDecode('{"ok":1} ignored')
catch
    badJson := true
Check(badJson, "JSON rejects trailing content")
Check(StudyLLM_EstimateCost("deepseek-flash", 1000000, 1000000) = 1.5, "provider cost estimate")
earlier := g_StudyLLM_CredTarget
g_StudyLLM_CredTarget := "MacroAutomator/Validation/" . A_TickCount
try {
    Check(StudyLLM_SaveKey("synthetic-credential-α"), "credential write uses valid buffer sizes")
    Check(StudyLLM_CredRead(g_StudyLLM_CredTarget) = "synthetic-credential-α", "credential roundtrip preserves UTF-8")
} finally {
    StudyLLM_DeleteKey()
    g_StudyLLM_CredTarget := earlier
}

g_StudyPin := Map("hwnd", 12345, "url", "https://first.example/page", "origin", "https://first.example", "title", "First tab", "exe", "chrome.exe")
g_StudyLastQFP := "old question", g_StudyLastSig := "old frame"
g_StudyDocument := Map("hwnd", 12345, "element", "old control tree")
g_StudyPrevQ := Map("submittedAt", 100), g_StudyCurrent := Map("old", true)
g_StudyMacroRunning := false
Check(StudyAuto_FollowTab("https://second.example/page", "Second tab"), "switching websites follows the selected tab")
Check(g_StudyPin["hwnd"] = 12345 && g_StudyPin["url"] = "https://second.example/page", "tab switch preserves the pinned browser window")
Check(g_StudyLastQFP = "" && g_StudyLastSig = "" && !g_StudyPrevQ.Count && !g_StudyCurrent.Count
    && g_StudyDocument["hwnd"] = 0, "tab switch clears cached questions, control trees and old-page feedback")
g_StudyMacroRunning := true, g_StudyMacroCancelled := false
StudyAuto_FollowTab("https://third.example/page", "Third tab")
Check(g_StudyMacroCancelled, "tab switch cancels typing from the previous page")
g_StudyMacroRunning := false
global g_TrackTooltipsDisabled := true
TrackToolTip("This must never appear", 20, 20, 19)
Check(!WinExist("ahk_class tooltips_class32 ahk_pid " . DllCall("GetCurrentProcessId")), "quiet desktop policy prevents tooltip creation")

Check(StudyAuto_IsChromeBase(Map("hwnd", 8, "exe", "chrome.exe")), "Chrome activation can select a learning base without a pin")
Check(!StudyAuto_IsChromeBase(Map("hwnd", 9, "exe", "AutoHotkey.exe")), "chat/app focus does not replace the last Chrome base")
pearsonControls := [FixCtl("radio", "Question 1", 20, 460), FixCtl("radio", "A. Real number answer", 444, 600),
    FixCtl("radio", "B. The answer is not a real number", 444, 650), FixCtl("edit", "Answer for option A", 594, 595),
    FixCtl("button", "Check answer", 1650, 936), FixCtl("button", "Save", 1750, 280),
    FixCtl("link", "Question 2", 65, 583), FixCtl("button", "Help me solve this", 35, 936)]
pearsonControls[4]["enabled"] := false
pearsonControls[5]["enabled"] := false
pearsonOcr := Map("text", "Homework: Section 10.2`nQuestion list`nUse radical notation to rewrite the expression. Simplify if possible.`n100`n1/2`nSelect the correct choice below`nA. Real number answer`nB. The answer is not a real number.",
    "lines", [Map("text", "Homework: Section 10.2", "x", 20, "y", 280, "w", 400, "h", 24),
        Map("text", "Use radical notation to rewrite the expression. Simplify if possible.", "x", 443, "y", 350, "w", 700, "h", 24),
        Map("text", "100", "x", 480, "y", 409, "w", 34, "h", 22),
        Map("text", "1/2", "x", 516, "y", 400, "w", 25, "h", 15),
        Map("text", "A. Real number answer", "x", 475, "y", 598, "w", 600, "h", 24)],
    "words", [Map("text", "100", "x", 480, "y", 409, "w", 34, "h", 22), Map("text", "1/2", "x", 516, "y", 400, "w", 25, "h", 15)])
pearsonQ := StudyPercept_BuildQuestion(pearsonOcr, pearsonControls, Map("x", 0, "y", 0, "w", 1920, "h", 1080), "")
Check(pearsonQ["qtype"] = "choicefill" && pearsonQ["choices"].Length = 2, "Pearson inline-answer question excludes sidebar circles from the choice group")
Check(pearsonQ["blanks"][1]["choiceTag"] = "A", "inline math input is associated with option A by observed bounds")
Check(pearsonQ["mathExpression"] = "100^(1/2)", "raised fractional OCR exponent preserves 100 to the one-half power")
localAnswer := StudyMath_LocalAnswer(pearsonQ)
Check(localAnswer["ok"] && localAnswer["answer"] = "A || 10", "screenshot example resolves exactly to option A and inline value 10")
combinedPlan := StudyMacro_Compose(pearsonQ, "A || 10", "fill")
Check(combinedPlan["ok"] && combinedPlan["steps"][1]["verify"]["kind"] = "checked"
    && combinedPlan["steps"][combinedPlan["steps"].Length]["param"] = "10", "combined plan selects A then enters and verifies 10")
Check(!StudyMacro_ParseAnswer(pearsonQ, "A")["ok"], "choice letter alone cannot omit the required inline value")
Check(StudyMacro_ParseAnswer(pearsonQ, "B")["ok"] && !StudyMacro_ParseAnswer(pearsonQ, "B || 10")["ok"], "no-real-number option requires no unrelated field value")
Check(StudyMacro_FindSubmit(pearsonQ)["name"] = "Check answer", "answer submission identifies Check answer rather than Save/navigation")
overview := StudyPortal_Profile(Map("text", "Current Score: 0%`nAttempts: Unlimited`nQuestions: 30`nScored: 0`nIncorrect: 0", "lines", []), [], pearsonQ["region"])
Check(overview["view"] = "assignment_overview", "overview score counters are not mistaken for answer-feedback errors")
feedback := StudyPortal_Profile(Map("text", "Fantastic!`nNext question", "lines", []), [], pearsonQ["region"])
Check(feedback["view"] = "answer_feedback" && feedback["correct"], "Fantastic modal is recognized as correct feedback")
navContext := Map("catalog", Map("1", FixCtl("link", "Question 2", 60, 500), "2", FixCtl("button", "Next question", 850, 535), "3", FixCtl("button", "Save", 1750, 280)), "q", pearsonQ)
Check(StudyTools_Compile("NAVIGATE 1", navContext)["ok"] && StudyTools_Compile("NAVIGATE 2", navContext)["ok"], "question links and feedback Next question support reviewed navigation")
Check(!StudyTools_Compile("NAVIGATE 3", navContext)["ok"], "Save cannot be mislabeled as question navigation")
Check(!StudyTools_Compile("NAVIGATE 1`nTYPE 4 10", navContext)["ok"], "navigation requires a fresh destination capture before more input")

Say("════ RESULT: " . pass . " passed, " . fail . " failed ════")
ExitApp(fail = 0 ? 0 : 1)
