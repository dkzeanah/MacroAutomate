"""Run the production Autopilot / self-heal AutoHotkey functions under the real interpreter.

Function bodies are extracted from lib\\*.ahk and the workflow engine, exactly as
the app loads them; only desktop side effects (OCR, message boxes, screenshots,
database) are replaced with recorders. No keys or clicks are sent.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT / "lib"
ENGINE = ROOT / "fan" / "Actions" / "_Engine.ahk"
WORKFLOW_TAB = ROOT / "fan" / "Tabs" / "Tab_01_Workflow.ahk"
PATTERNS_TAB = ROOT / "fan" / "Tabs" / "Tab_02_Patterns.ahk"
TRACK_UTIL = LIB / "TrackUtil.ahk"
INTERPRETER = Path(os.environ.get("AUTOHOTKEY_EXE", r"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"))
sys.path.insert(0, str(ROOT))


def read(path):
    return Path(path).read_text(encoding="utf-8-sig", errors="replace")  # a few legacy libraries are ANSI


def function_source(source, name):
    """A block function, or a one-line `=>` function with its indented continuation lines."""
    arrow = re.search(r"^" + re.escape(name) + r"\([^\n]*\)\s*=>[^\n]*\n(?:[ \t]+[^\n]*\n)*", source, re.M)
    if arrow:
        return arrow.group(0)
    start = re.search(r"^" + re.escape(name) + r"\([^)]*\)\s*\{", source, re.M)  # parameters may span lines
    if not start:
        raise AssertionError(f"Production function missing: {name}")
    depth, opened, output = 0, False, []
    for line in source[start.start():].splitlines(keepends=True):
        output.append(line)
        code = re.sub(r'"(?:`.|[^"`])*"|\'(?:`.|[^\'`])*\'', "", line).split(";", 1)[0]
        depth += code.count("{") - code.count("}")
        opened = opened or "{" in code
        if opened and depth == 0:
            return "".join(output)
    raise AssertionError(f"Unclosed production function: {name}")


def functions(path, names):
    source = read(path)
    return "\n".join(function_source(source, name) for name in names)


def human_pattern_global():
    source = read(LIB / "AutopilotActions.ahk")
    match = re.search(r"^global g_AutopilotHumanPattern := .*?\n(?:\s+\..*\n)*", source, re.M)
    return match.group(0)


HARNESS = r'''
#Requires AutoHotkey v2.0
#Warn All, Off
global checks := 0
Check(condition, label) {
    global checks
    if !condition
        throw Error(label)
    checks++
}
'''
FOOTER = r'''
    FileAppend(checks . " checks passed`n", "*")
    ExitApp(0)
} catch as err {
    FileAppend("FAIL: " . err.Message . " (line " . err.Line . ")`n", "*")
    ExitApp(1)
}
'''


@unittest.skipUnless(os.name == "nt" and INTERPRETER.is_file(), "Requires the installed AutoHotkey v2 interpreter")
class AutopilotAhkTests(unittest.TestCase):
    def run_ahk(self, body, timeout=30):
        with tempfile.TemporaryDirectory(prefix="fan-autopilot-ahk-") as folder:
            script = Path(folder) / "Autopilot_Test.ahk"
            script.write_text(body.replace("%TEMP_DIR%", folder), encoding="utf-8-sig")
            result = subprocess.run([str(INTERPRETER), "/ErrorStdOut", str(script)], capture_output=True, text=True,
                                    timeout=timeout, encoding="utf-8", errors="replace")
            artifacts = {p.relative_to(folder).as_posix(): p.read_text(encoding="utf-8-sig", errors="replace")
                         for p in Path(folder).rglob("*.json")}
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("checks passed", result.stdout)
        return result.stdout, artifacts

    def test_engine_records_heals_skips_approvals_and_writes_the_run(self):
        engine = read(ENGINE)
        bodies = "\n".join(function_source(engine, n) for n in [
            "ExecuteSequenceVerified", "WorkflowExecution_Event", "WorkflowLoopIncrement", "AbortSequenceHandler",
            "StepThroughAdvance", "ExecuteSubSequenceByName", "WorkflowExecution_Wait", "SubstituteWorkflowVariables"])
        bodies = bodies.replace("Hotkey(", "TestHotkey(").replace("Sleep(", "TestSleep(")
        ledger = functions(LIB / "Autopilot.ahk", ["Autopilot_WorkflowNameFor", "Autopilot_RunBegin", "Autopilot_StepBegin",
                                                    "Autopilot_RunNote", "Autopilot_StepEnd", "Autopilot_RunEnd"])
        helpers = functions(LIB / "AutopilotActions.ahk", ["Autopilot_Now"]) + functions(TRACK_UTIL, ["TrackJsonEscape", "TrackJsonEncode", "TrackArrayJoin"])
        fixture = HARNESS + r'''
global g_Settings := Map("ActionDelay", 0), g_IsPaused := false, g_AbortSequence := false, g_DebugMode := false
global g_StepThroughMode := false, g_StepThroughWaiting := false, g_StepThroughContinue := false
global g_WorkflowVariables := Map(), g_SkipNextAction := false, g_SequenceCallStack := [], g_SpoolVariables := Map()
global g_LoopBreakRequested := false, g_ActiveLoopDepth := 0, g_WorkflowRunning := false, g_LastActionError := ""
global g_WorkflowExecutionOptions := 0, g_Sequences := Map(), g_WatchWords := Map(), g_CurrentSequenceSteps := []
global g_Autopilot := Map("lastRun", 0), g_AutopilotRun := 0
global calls := [], learned := [], shots := [], reports := []
ShowStatus(*) => 0
ShowNotificationBasic(*) => 0
TrackToolTip(*) => 0
UpdateAllWatchWords(*) => 0
MsgBoxTop(*) => "No"
SoundBeep(*) => 0
TestHotkey(*) => 0
TestSleep(*) => 0
LogErrorToFile(err, mode := "", context := "") => FileAppend("LOGGED: " . context . ": " . err.Message . "`n", "*")
StudyConsole_Redact(text) => text
TrackDB_Ready() => false
Autopilot_DataDir() => "%TEMP_DIR%"
Autopilot_EvidenceCapture(area, label, gallery := true, step := 0) {
    global shots
    shots.Push(label)
    return "shot" . shots.Length . ".png"
}
Autopilot_BuildReport(dir, open := false) {
    global reports
    reports.Push(dir)
}
ParseLoopOptions(text) {
    opt := Map()
    for part in StrSplit(text, ";") {
        pair := StrSplit(Trim(part), "=")
        if pair.Length = 2
            opt[Trim(pair[1])] := Trim(pair[2])
    }
    return opt
}
LoopOptStr(options, key, fallback) => options.Has(key) ? options[key] : fallback
SelfHeal_Before(step, index, &heal) {
    heal := 0
    if step["target"] != "MovedPoint"
        return ""
    heal := Map("strategy", "moved target · remembered label", "confidence", 0.9, "x", 777, "y", 888)
    return "777,888"
}
SelfHeal_Recover(step, index, speed, &heal) {
    heal := 0
    if step["action"] != "Flaky"
        return false
    heal := Map("strategy", "visible text", "confidence", 0.85)
    return true
}
SelfHeal_Learn(step, index) {
    global learned
    learned.Push(step["action"])
}
ExecuteActionVerified(action, target, param, stepData, speed) {
    global calls, g_LastActionError, g_SkipNextAction, g_AbortSequence
    calls.Push(action . ":" . target)
    switch action {
        case "Flaky", "Bad":
            g_LastActionError := "not found"
            return false
        case "Skip": g_SkipNextAction := true
        case "Approve": Autopilot_RunNote("approval", Map("decision", "approved", "by", "tester", "at", "now", "message", "ok?"))
        case "Decline":
            Autopilot_RunNote("approval", Map("decision", "declined", "by", "tester", "at", "now", "message", "ok?"))
            g_AbortSequence := true
            g_LastActionError := "Declined at approval gate: ok?"
            return false
        case "Run Sequence": return ExecuteSubSequenceByName(param, speed)
    }
    return true
}
Step(action, target := "", param := "") => Map("action", action, "target", target, "param", param, "enabled", true)
''' + bodies + ledger + helpers + "\ntry {\n" + r'''
    g_Sequences["Child"] := Map("steps", [Step("Wait"), Step("Wait")])
    g_Sequences["Payroll"] := Map("steps", [Step("Click", "MovedPoint"), Step("Flaky", "Save"), Step("Skip"), Step("Wait"),
        Step("Approve"), Step("Run Sequence", "", "Child"), Step("Wait")])
    opts := Map("interactive", false, "sequenceName", "Payroll", "evidence", "steps", "portal", "Payroll Portal")
    r := ExecuteSequenceVerified(g_Sequences["Payroll"]["steps"], 1, opts)
    Check(r["ok"], "Healed workflow succeeds: " . r["error"])
    Check(calls[1] = "Click:777,888", "A moved target is clicked at the re-found point, not the saved one")
    ; Click, Flaky, Skip, Approve, two child Waits, Run Sequence, Wait (the skipped Wait never ran)
    Check(learned.Length = 8 && learned[1] = "Click", "Every successful step (including nested ones) teaches self-heal: " . learned.Length)
    Check(!IsObject(g_AutopilotRun), "The ledger is released after the run")
    Check(reports.Length = 1 && InStr(reports[1], "%TEMP_DIR%"), "An evidence run builds its audit report")
    ; Click, Flaky, Skip, Approve, Run Sequence; Waits are quiet and child steps belong to their parent step
    Check(shots.Length = 5, "Evidence screenshots skip quiet steps: " . shots.Length)
    last := g_Autopilot["lastRun"]
    Check(last["heals"] = 2 && last["approvals"] = 1 && last["workflow"] = "Payroll" && last["portal"] = "Payroll Portal", "Run totals")
    statuses := ""
    for , s in last["steps"]
        statuses .= s["status"] . ","
    Check(statuses = "healed,healed,completed,skipped,approved,completed,completed,", "Step statuses: " . statuses)

    calls := [], learned := [], shots := [], reports := []
    r := ExecuteSequenceVerified([Step("Wait"), Step("Decline"), Step("Wait")], 1, Map("interactive", false))
    Check(!r["ok"] && r["aborted"] && calls.Length = 2, "Declining an approval stops the run")
    last := g_Autopilot["lastRun"]
    Check(last["workflow"] = "(unsaved workflow)" && last["steps"][2]["status"] = "declined", "Declined step is recorded as declined")
    Check(shots.Length = 1, "A failed step captures diagnostic evidence even without evidence mode")
    Check(reports.Length = 0, "Runs without evidence mode do not build reports")

    g_AbortSequence := false, calls := []
    r := ExecuteSequenceVerified([Step("Bad", "Ghost")], 1, Map("interactive", false))
    Check(!r["ok"] && r["error"] = "not found" && g_Autopilot["lastRun"]["steps"][1]["error"] = "not found", "Unhealed failures keep their error")
''' + FOOTER
        _, artifacts = self.run_ahk(fixture)
        runs = {k: json.loads(v) for k, v in artifacts.items() if k.endswith("run.json")}
        self.assertEqual(len(runs), 2, list(artifacts))
        payroll = next(r for r in runs.values() if r["workflow"] == "Payroll")
        self.assertEqual(payroll["portal"], "Payroll Portal")
        self.assertEqual(payroll["steps"][0]["heal"]["x"], 777)
        self.assertEqual(payroll["steps"][4]["approval"]["by"], "tester")
        self.assertEqual(len(payroll["steps"]), 7)
        self.assertEqual(payroll["mode"], "unattended")
        from fan.autopilot import portal
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / "run.json").write_text(json.dumps(payroll), encoding="utf-8")
            built = portal.build_report(folder)
            self.assertEqual((built["heals"], built["approvals"]), (2, 1))

    def test_actions_keep_people_in_the_loop(self):
        actions = functions(LIB / "AutopilotActions.ahk", [
            "ExecuteAskInput", "ExecuteApprovalGate", "ExecuteHumanCheck", "Autopilot_DetectHumanStep", "ExecuteOpenPage",
            "ExecuteTypeCredential", "Autopilot_Interactive", "Autopilot_Fail", "Autopilot_RegexLiteral", "Autopilot_HostHint",
            "Autopilot_IsBrowserExe", "AutopilotCred_ValidName"])
        support = (functions(ENGINE, ["NormalizeWorkflowVariableName", "TryGetWorkflowVariable"])
                   + functions(PATTERNS_TAB, ["ParseLoopOptions", "LoopOptStr", "LoopOptInt"])
                   + functions(WORKFLOW_TAB, ["StrJoin"]))
        fixture = HARNESS + human_pattern_global() + r'''
global g_WorkflowVariables := Map(), g_SpoolVariables := Map(), g_AbortSequence := false, g_LastActionError := ""
global g_WorkflowExecutionOptions := Map("interactive", false, "inputs", Map("invoiceNo", "INV-77"))
global g_Settings := Map("PreActionDelay", 0, "PostActionDelay", 0), g_OCRText := "", notes := [], boxes := [], replies := []
ShowStatus(*) => 0
StudyConsole_Secret(*) => 0
DeepActivity_Before(*) => 0
DeepActivity_Set(*) => 0
Autopilot_Beep(*) => 0
Autopilot_Now() => "now"
SelfHeal_WorkflowName() => "Payroll"
Autopilot_PortalHint(name) => "paychex"
AutopilotCred_Read(name, withSecret := true) => Map("user", "office@example.com", "secret", "s3cret")
Autopilot_EvidenceCapture(*) => "shot.png"
Autopilot_RunNote(kind, data) {
    global notes
    notes.Push(kind . ":" . (data.Has("decision") ? data["decision"] : data.Get("detail", "")))
}
MsgBoxTop(text, title := "", options := "") {
    global boxes, replies, g_OCRText
    boxes.Push(title)
    g_OCRText := ""  ; the person completed the verification
    return replies.Length ? replies.RemoveAt(1) : "No"
}
IsOCRAvailable() => true
WorkflowOCR_Options() => {}
ParseRegionCoords(area) => Map("x1", 0, "y1", 0, "x2", 100, "y2", 100)
WorkflowExecution_Wait(*) => true
class OCR {
    static FromRect(x, y, w, h, options) {
        global g_OCRText
        return {Text: g_OCRText}
    }
}
''' + actions + support + "\ntry {\n" + r'''
    Check(ExecuteAskInput("invoiceNo", "Invoice number?; default=1") && g_WorkflowVariables["invoiceNo"] = "INV-77", "Supplied unattended input is used")
    Check(!ExecuteAskInput("clientName", "Client?") && InStr(g_LastActionError, "unattended runs must supply"), "Missing unattended input fails clearly")
    Check(!ExecuteAskInput("9bad", "x") && InStr(g_LastActionError, "variable name"), "Invalid variable names are rejected")
    Check(!ExecuteApprovalGate("Submit payroll?") && InStr(g_LastActionError, "must approve"), "Unattended runs stop at an approval gate")

    g_WorkflowExecutionOptions := Map("interactive", true)
    replies := ["Yes"]
    Check(ExecuteApprovalGate("Submit payroll?") && notes[notes.Length] = "approval:approved", "Approval is recorded with the decision")
    replies := ["No"]
    Check(!ExecuteApprovalGate("Submit payroll?") && g_AbortSequence && notes[notes.Length] = "approval:declined", "Declining stops the workflow")
    g_AbortSequence := false

    g_OCRText := "Sign in`nEnter the 6-digit code we sent to your phone"
    Check(Autopilot_DetectHumanStep("window:A") != "", "Verification prompts are detected")
    replies := ["OK"]
    Check(ExecuteHumanCheck("", "on=pause") && notes[notes.Length] = "human:verification completed by a person", "A person completes the verification, then the run continues")
    g_OCRText := "Please complete the CAPTCHA"
    Check(!ExecuteHumanCheck("", "on=stop") && InStr(g_LastActionError, "never solves"), "on=stop fails instead of waiting")
    g_WorkflowExecutionOptions := Map("interactive", false)
    Check(!ExecuteHumanCheck("", "") && InStr(g_LastActionError, "A person must complete"), "Unattended runs never pass a verification prompt")
    g_OCRText := "Dashboard  Welcome back"
    Check(ExecuteHumanCheck("", ""), "A normal page passes")
    g_OCRText := "Answer your security question"
    Check(Autopilot_DetectHumanStep("window:A", "security question") != "" && Autopilot_DetectHumanStep("window:A") = "", "Extra words extend detection")

    Check(!ExecuteOpenPage("url=javascript:alert(1)") && InStr(g_LastActionError, "https"), "Only http(s) pages open")
    Check(!ExecuteOpenPage("https://example.com/a b") , "URLs with spaces are refused")
    Check(!ExecuteOpenPage('url=https://example.com/"&calc'), "Quotes cannot break out of the browser command")
    Check(!ExecuteTypeCredential("Bad/Name", "password") && InStr(g_LastActionError, "portal name"), "Credential names are validated")
    Check(!ExecuteTypeCredential("Payroll", "pin") && InStr(g_LastActionError, "username or password"), "Only username/password fields exist")
    Check(Autopilot_HostHint("https://login.paychex.com/x") = "paychex" && Autopilot_HostHint("https://www.irs.gov") = "irs", "Host hints use the site name")
    Check(Autopilot_IsBrowserExe("msedge.exe") && !Autopilot_IsBrowserExe("excel.exe"), "Browser detection")
''' + FOOTER
        self.run_ahk(fixture)

    def test_self_heal_matching_health_fixes_and_window_relative_points(self):
        heal = functions(LIB / "SelfHeal.ahk", [
            "SelfHeal_Norm", "SelfHeal_Distance", "SelfHeal_TextScore", "SelfHeal_NameWords", "SelfHeal_StepPosition",
            "SelfHeal_FixFor", "SelfHeal_HexBuffer", "SelfHeal_SampleDiff", "SelfHeal_Health", "SelfHeal_ClickActions",
            "SelfHeal_Healable", "SelfHeal_Learnable", "SelfHeal_Key", "SelfHeal_Risky", "SelfHeal_Best", "SelfHeal_OnScreen",
            "SelfHeal_RootWindowAt"])
        support = functions(ENGINE, ["ComparePixelSamples"]) + functions(WORKFLOW_TAB, ["ResolveWorkflowPoint", "FindWorkflowWindow"])
        fixture = HARNESS + r'''
global g_Coordinates := Map("Saved", Map("x", 5, "y", 6)), rows := []
ResolveWorkflowRegion(*) => false
IsNearCloseButton(x, y) => x = 999
class FakeDB {
    Query(sql, params*) {
        global rows
        return rows
    }
}
TrackDB_Ready() => true
TrackDB() => FakeDB()
''' + heal + support + "\ntry {\n" + r'''
    Check(SelfHeal_TextScore("Save", "save") = 1.0 && SelfHeal_TextScore("Save draft", "Save") = 0.9, "Exact and word matches")
    Check(SelfHeal_TextScore("Submitted", "Submit") = 0.78 && SelfHeal_TextScore("Sbmit", "Submit") = 0.7, "Substring and one-typo matches")
    Check(SelfHeal_TextScore("Cancel", "Submit") = 0 && SelfHeal_TextScore("Sub", "Submit") = 0, "Non-matches")
    Check(SelfHeal_Distance("kitten", "sitting") = 3 && SelfHeal_Distance("save", "save") = 0, "Edit distance")
    Check(SelfHeal_NameWords("SubmitButton") = "Submit" && SelfHeal_NameWords("save_btn") = "save" && SelfHeal_NameWords("x1") = "", "Target names become visible words")
    Check(SelfHeal_Healable("Find & Click") && SelfHeal_Healable("Wait Element") && !SelfHeal_Healable("Type Text"), "Healable actions")
    Check(SelfHeal_Risky(Map("target", "SubmitPayment", "param", ""), Map("label", "")) = 0 && SelfHeal_Risky(Map("target", "x", "param", ""), Map("label", "Delete invoice")), "Risk words")

    hexA := "0300030010203040506070809000", hexB := "0300030010203040506070809000", hexC := "03000300FFFFFFFFFFFFFFFFFF00"
    Check(SelfHeal_SampleDiff(hexA, hexB) = 0 && SelfHeal_SampleDiff(hexA, hexC) > 0.8 && SelfHeal_SampleDiff(hexA, "") = 1, "Pixel fingerprints compare")

    steps := [Map("enabled", 0), Map("enabled", 1), Map("enabled", 1)]
    Check(SelfHeal_StepPosition(steps, 2) = 3 && SelfHeal_StepPosition(steps, 3) = 0, "Enabled index maps to the saved position")
    fix := SelfHeal_FixFor(Map("action", "Click", "window", "ahk_exe chrome.exe", "rel_x", 0.25, "rel_y", 0.5, "label", "Save"))
    Check(fix["target"] = "winrel:ahk_exe chrome.exe|0.2500,0.5000", "Click heals become window-relative targets")
    fix := SelfHeal_FixFor(Map("action", "Find & Click", "window", "", "rel_x", "", "rel_y", "", "label", "Submit"))
    Check(fix["action"] = "OCR Click" && fix["param"] = "Submit", "Pattern heals become text clicks")
    Check(SelfHeal_FixFor(Map("action", "Wait Element", "window", "", "rel_x", "", "rel_y", "", "label", "")) = "", "No fix without a safe replacement")

    rows := []
    loop 6
        rows.Push(Map("workflow", "Payroll", "ok", 1, "aborted", 0, "heals", A_Index = 1 ? 1 : 0, "started", "2026-11-2" . A_Index, "error", ""))
    loop 4
        rows.Push(Map("workflow", "Invoices", "ok", A_Index = 1 ? 1 : 0, "aborted", 0, "heals", 0, "started", "2026-11-1" . A_Index, "error", "Pattern not found"))
    rows.Push(Map("workflow", "New one", "ok", 1, "aborted", 0, "heals", 0, "started", "2026-11-01", "error", ""))
    health := SelfHeal_Health()
    Check(health["Payroll"]["badge"] = "Self-healing" && health["Payroll"]["runs"] = 6, "Recent heals show as self-healing")
    Check(health["Invoices"]["badge"] = "Needs attention" && health["Invoices"]["lastError"] = "Pattern not found", "Failing workflows need attention")
    Check(health["New one"]["badge"] = "New", "Few runs means new")

    candidates := [Map("strategy", "a", "confidence", 0.65, "x", 10, "y", 10), Map("strategy", "b", "confidence", 0.9, "x", 999, "y", 10),
        Map("strategy", "c", "confidence", 0.82, "x", 20, "y", 20)]
    best := SelfHeal_Best(candidates, 0.8)
    Check(best["strategy"] = "c", "Best candidate clears the bar and never lands near a close button")
    Check(SelfHeal_Best(candidates, 0.95).Count = 0, "Nothing below the bar is chosen")

    g := Gui("+AlwaysOnTop -Caption +ToolWindow", "Fan WinRel Fixture " . A_TickCount)
    g.Show("x120 y140 w400 h300 NoActivate")
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . g.Hwnd)
    Check(ResolveWorkflowPoint("winrel:" . g.Title . "|0.5,0.25", &x, &y) && x = wx + Round(0.5 * ww) && y = wy + Round(0.25 * wh), "winrel resolves inside the live window")
    g.Move(300, 260)
    WinGetPos(&wx, &wy)
    Check(ResolveWorkflowPoint("winrel:" . g.Title . "|0.5,0.25", &x, &y) && x = wx + Round(0.5 * ww), "winrel follows the window when it moves")
    Check(!ResolveWorkflowPoint("winrel:" . g.Title . "|1.5,0.25", &x, &y), "Out-of-window fractions are rejected")
    Check(!ResolveWorkflowPoint("winrel:No Such Window Anywhere|0.5,0.5", &x, &y), "Missing windows do not resolve")
    Check(ResolveWorkflowPoint("Saved", &x, &y) && x = 5 && ResolveWorkflowPoint("-10,20", &x, &y) && x = -10, "Existing coordinate forms still work")
    g.Destroy()
''' + FOOTER
        self.run_ahk(fixture)

    def test_autopilot_pages_build_and_render_real_results(self):
        """Loads the four Autopilot modules whole (via lib\\Autopilot.ahk) in a hidden window.

        Every app function they call that is defined elsewhere is stubbed automatically,
        so the real control layout, list rendering and draft review code all execute.
        """
        own = [LIB / n for n in ("Autopilot.ahk", "AutopilotActions.ahk", "AutopilotUI.ahk", "SelfHeal.ahk")]
        strip = lambda text: re.sub(r";[^\n]*", "", re.sub(r'"(?:`.|[^"`\n])*"|\'(?:`.|[^\'`\n])*\'', '""', text))
        definition = re.compile(r"^([A-Za-z_]\w*)\([^)]*\)\s*(?:\{|=>)", re.M)  # top level only, not class methods
        own_defs = {m.group(1) for f in own for m in definition.finditer(read(f))}
        repo_defs = set()
        for f in list(LIB.glob("*.ahk")) + list((ROOT / "fan" / "Core").glob("*.ahk")) + list((ROOT / "fan" / "Tabs").glob("*.ahk")) + [ENGINE]:
            if f not in own:
                repo_defs |= {m.group(1) for m in definition.finditer(read(f))}
        called = {m.group(1) for f in own for m in re.finditer(r"(?<![\w.])([A-Za-z_]\w*)\(", strip(read(f)))}
        provided = {"TrackDB_MetaGet", "TrackDB_MetaSet", "TrackDB_Ready", "TrackDB", "GetWorkflowActionNames", "GetWorkflowActionSpec",
                    "MakeActionSpec", "StrJoin", "MsgBoxTop", "SimulateSequence", "LogErrorToFile", "TrackJsonEncode",
                    "TrackJsonEscape", "TrackArrayJoin", "TrackJsonDecode", "_TrackJsonSkipWs", "_TrackJsonValue",
                    "_TrackJsonObject", "_TrackJsonArray", "_TrackJsonString", "Study_GetSetting"}
        stubs = "\n".join(f"{name}(*) => \"\"" for name in sorted((called & repo_defs) - own_defs - provided))
        real = (functions(WORKFLOW_TAB, ["GetWorkflowActionNames", "GetWorkflowActionSpec", "MakeActionSpec", "StrJoin"])
                + functions(TRACK_UTIL, ["TrackJsonEscape", "TrackJsonEncode", "TrackArrayJoin", "TrackJsonDecode", "_TrackJsonSkipWs",
                                         "_TrackJsonValue", "_TrackJsonObject", "_TrackJsonArray", "_TrackJsonString"]))
        routine = json.dumps({"id": "r1", "name": "Copy from Excel into Chrome", "occurrences": 6, "occurrences_last_7_days": 4,
                              "distinct_days": 4, "avg_seconds": 12.5, "minutes_observed": 1.3, "minutes_last_7_days": 0.8,
                              "minutes_per_week": None, "per_week_basis": "only 4.0 days of history", "length": 7,
                              "apps": ["Excel", "Chrome"], "schedule": {"text": "usually on Mondays", "weekday": "Monday", "hour": None},
                              "first_seen": "2026-11-02 09:00", "last_seen": "2026-11-23 09:01", "inputs": [{"var": "input1"}],
                              "steps": [{"action": "Activate Window", "target": "", "param": "ahk_exe excel.exe", "enabled": True, "note": "x"},
                                        {"action": "Send Keys", "target": "", "param": "^c", "enabled": True}]})
        compiled = json.dumps({"ok": True, "source": "model", "name": "Pay vendor", "summary": "s",
                               "steps": [{"action": "Activate Window", "target": "", "param": "Outlook", "enabled": True},
                                         {"action": "Approval Gate", "target": "", "param": "Send?", "enabled": True},
                                         {"action": "OCR Click", "target": "window:A", "param": "Send", "enabled": True}],
                               "assumptions": ["a"], "questions": [], "notes": ["Added an Approval Gate before step 2."],
                               "usage": {"requests": 1, "cost_usd": 0.0012, "model": "deepseek-v4-pro"},
                               "validation": {"ok": True, "errors": [], "warnings": [{"step": 3, "message": "w"}],
                                              "risks": [{"step": 3, "level": "high", "reason": "clicks 'Send'"}]}})
        fixture = HARNESS + f"#Include {LIB / 'Autopilot.ahk'}\n" + stubs + "\n" + real + r'''
global APP_ROOT := "%TEMP_DIR%", g_TrackDBPath := "%TEMP_DIR%\fan.sqlite", boxes := []
global g_Sequences := Map("Payroll login", Map("steps", [])), g_Coordinates := Map(), g_Patterns := Map()
global g_StudyLLM_Endpoint := "https://api.deepseek.com", g_StudyLLM_TextModel := "deepseek-v4-pro", g_StudyLLM_Price := Map(), g_StudyLLM_SpentUSD := 0
global g_WorkflowRunning := false, g_AbortSequence := false, g_IsPaused := false, g_WorkflowExecutionOptions := 0
global MainGui := Gui("+Resize", "Autopilot UI fixture")
MainGui.SetFont("s9", "Segoe UI")
names := []
loop 29
    names.Push("Page " . A_Index)
global TabCtrl := MainGui.Add("Tab3", "x5 y28 w890 h730", names)
Study_GetSetting(key, default := "") => default
TrackDB_MetaGet(key, default := "") => key = "autopilot_toasts" ? "0" : default
TrackDB_MetaSet(*) => 0
TrackDB_Ready() => true
TrackDB() => FakeDB()
MsgBoxTop(text, *) {
    global boxes
    boxes.Push(text)
    return "No"
}
SimulateSequence(*) => 0
LogErrorToFile(err, mode := "", context := "") {
    throw Error(context . ": " . err.Message)
}
class FakeDB {
    static runs := []
    Run(sql, params*) => FakeDB.runs.Push(sql)
    Scalar(*) => ""
    QueryRow(*) => Map()
    Query(sql, params*) {
        if InStr(sql, "FROM autopilot_routine")
            return [Map("id", "r1", "data", ROUTINE_JSON, "status", "new", "workflow", "", "notified", 0)]
        if InStr(sql, "FROM autopilot_heal")
            return [Map("id", 4, "at", "2026-11-24 09:00:00", "workflow", "Payroll login", "step_index", 3, "action", "OCR Click",
                "target", "window:A", "param", "Sign in", "strategy", "remembered label", "confidence", 0.86, "status", "open")]
        if InStr(sql, "workflow, ok, aborted, heals")
            return [Map("workflow", "Payroll login", "ok", 1, "aborted", 0, "heals", 1, "started", "2026-11-24 09:00:00", "error", "")]
        if InStr(sql, "FROM autopilot_run")
            return [Map("started", "2026-11-24 09:00:00", "workflow", "Payroll login", "portal", "Payroll", "ok", 1, "aborted", 0,
                "failed_step", 0, "completed", 9, "heals", 1, "approvals", 0, "mode", "interactive", "dir", "%TEMP_DIR%\runs\x")]
        if InStr(sql, "FROM autopilot_portal")
            return [Map("name", "Payroll", "url", "https://login.paychex.com", "title_hint", "paychex", "login_workflow", "Payroll login",
                "username_label", "", "password_label", "", "submit_label", "", "notes", "")]
        if InStr(sql, "FROM autopilot_routine WHERE status IN")
            return []
        return []
    }
}
'''.replace("ROUTINE_JSON", "'" + routine.replace("'", "") + "'") + "\ntry {\n" + r'''
    AutopilotUI_Build()
    ui := g_Autopilot["ui"]
    Check(ui.Count = 48, "All Autopilot controls were created: " . ui.Count)
    AutopilotUI_PageShown(26)
    Check(ui["routines"].GetCount() = 1 && ui["routines"].GetText(1, 1) = "Copy from Excel into Chrome", "Routine list renders")
    AutopilotUI_ShowRoutine(1)
    Check(ui["routineSteps"].GetCount() = 2 && InStr(ui["routineDetail"].Value, "Asks for 1 value"), "Routine detail and steps render")
    AutopilotUI_CompileDone(TrackJsonDecode(COMPILED_JSON))
    Check(ui["draft"].GetCount() = 3 && ui["draft"].GetText(3, 5) = "Risk: high · clicks Send", "Draft shows risk checks")
    Check(InStr(ui["draftNotes"].Value, "deepseek-v4-pro") && InStr(ui["draftNotes"].Value, "Warnings:"), "Draft notes explain source and warnings")
    Check(ui["draftName"].Value = "Pay vendor" && InStr(ui["describeStatus"].Value, "ready to review"), "Draft name and status")
    AutopilotUI_PageShown(28)
    Check(ui["portals"].GetCount() = 1 && ui["runs"].GetCount() = 1 && ui["auditWorkflow"].Text = "", "Portals and runs render")
    AutopilotUI_PageShown(29)
    Check(ui["health"].GetCount() = 1 && ui["health"].GetText(1, 2) = "New" && ui["heals"].GetCount() = 1, "Reliability renders")
    Check(InStr(ui["reliabilityStatus"].Value, "1 heal(s) waiting"), "Open heals are counted")
    Autopilot_RoutinesDone(true, Map("ok", true, "routines", [TrackJsonDecode(ROUTINE_JSON)], "events_analyzed", 120, "observed_days", 4.0))
    Check(InStr(ui["routinesStatus"].Value, "Found 1 repeated routine") && InStr(ui["routinesStatus"].Value, "Keep Usage Predictor"), "Scan result is explained")
    Autopilot_Toast("Fan spotted a routine", "Test", [["OK", (*) => 0]], 1)
    Check(IsObject(g_Autopilot["toast"]), "Toast renders")
    g_Autopilot["toast"].Destroy()
    MainGui.Destroy()
'''.replace("COMPILED_JSON", "'" + compiled.replace("'", "") + "'").replace("ROUTINE_JSON", "'" + routine.replace("'", "") + "'") + FOOTER
        self.run_ahk(fixture)

    @unittest.skipIf(os.environ.get("FAN_SKIP_CREDENTIAL_TESTS"), "credential store tests disabled")
    def test_portal_credentials_round_trip_through_windows_credential_manager(self):
        """Writes a clearly named temporary credential, reads it from AHK and Python, then deletes it."""
        cred = functions(LIB / "AutopilotActions.ahk", ["AutopilotCred_ValidName", "AutopilotCred_Target", "AutopilotCred_Write",
                                                         "AutopilotCred_Read", "AutopilotCred_Exists", "AutopilotCred_User", "AutopilotCred_Delete"])
        name = f"FanAutopilotTest {uuid.uuid4().hex[:8]}"
        secret = "S3cr€t-ü pass"
        write = HARNESS + cred + "\ntry {\n" + f'''
    Check(AutopilotCred_Write("{name}", "office@example.com", "{secret}"), "Credential written")
    Check(AutopilotCred_Exists("{name}") && AutopilotCred_User("{name}") = "office@example.com", "Exists, username readable")
    c := AutopilotCred_Read("{name}")
    Check(c["secret"] = "{secret}" && !AutopilotCred_Read("{name}", false).Has("secret"), "Secret round-trips; username-only reads omit it")
''' + FOOTER
        delete = HARNESS + cred + "\ntry {\n" + f'''
    Check(AutopilotCred_Delete("{name}") && !AutopilotCred_Exists("{name}"), "Credential deleted")
''' + FOOTER
        try:
            self.run_ahk(write)
            from fan.autopilot.llm import windows_credential
            self.assertEqual(windows_credential(f"Fan/Portal/{name}"), secret)
        finally:
            self.run_ahk(delete)


if __name__ == "__main__":
    unittest.main()
