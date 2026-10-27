"""Execute the production workflow controller with recorded actions and hotkeys.

This checks loops, failure reporting, cancellation, and cleanup without sending
keys or moving the user's mouse. The action dispatcher is the only action stub;
the production sequence runner and loop counter execute unchanged.
"""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


helper_spec = importlib.util.spec_from_file_location("workflow_ocr_test_helper", Path(__file__).with_name("test_workflow_ocr.py"))
helper = importlib.util.module_from_spec(helper_spec)
helper_spec.loader.exec_module(helper)
SOURCE = Path(__file__).resolve().parents[1] / "Actions" / "_Engine.ahk"


class WorkflowEngineTests(unittest.TestCase):
    @unittest.skipUnless(os.name == "nt", "Requires the installed AutoHotkey v2 interpreter")
    def test_production_runner_results_loops_failure_abort_and_cleanup(self):
        interpreter = Path(os.environ.get("AUTOHOTKEY_EXE", r"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"))
        if not interpreter.is_file():
            self.skipTest("AutoHotkey v2 interpreter is unavailable")
        source = SOURCE.read_text(encoding="utf-8-sig")
        names = ["ExecuteSequenceVerified", "WorkflowExecution_Event", "WorkflowLoopIncrement",
                 "AbortSequenceHandler", "StepThroughAdvance", "ExecuteSubSequenceByName", "WorkflowExecution_Wait",
                 "WorkflowExecution_AllowPointerFallback", "SubstituteWorkflowVariables"]
        bodies = "\n".join(helper.function_source(source, name) for name in names)
        action_body = helper.function_source(source, "ExecuteActionVerified")
        normalization = action_body[action_body.index("    param := SubstituteWorkflowVariables(param)"):action_body.index("    ; Calculate speed-adjusted delays")]
        pointer_cases = action_body[action_body.index('        case "Click":'):action_body.index('        case "Drag":')]
        pointer_cases = pointer_cases.replace("Click(", "RecordRawClick(").replace("MouseGetPos(", "TestPointerPos(")
        bodies += "\nActualPointerDispatch(action, target, param) {\n    global g_LastClickX, g_LastClickY\n" + normalization + "\n    switch action {\n" + pointer_cases + "\n    }\n}\n"
        bodies = bodies.replace('Hotkey(', 'TestHotkey(').replace('Sleep(', 'TestSleep(')
        fixture = r'''
#Requires AutoHotkey v2.0
#Warn All, Off
global g_Settings := Map("ActionDelay", 0), g_IsPaused := false, g_AbortSequence := false
global g_DebugMode := false, g_StepThroughMode := true, g_StepThroughWaiting := false, g_StepThroughContinue := false
global g_WorkflowVariables := Map(), g_SkipNextAction := false, g_SequenceCallStack := [], g_SpoolVariables := Map()
global g_LoopBreakRequested := false, g_ActiveLoopDepth := 0, g_WorkflowRunning := false, g_LastActionError := ""
global g_WorkflowExecutionOptions := 0, g_Sequences := Map()
global g_WatchWords := Map(), g_LastClickX := 0, g_LastClickY := 0, pointerCalls := []
global checks := 0, calls := [], hotkeys := Map(), prompts := 0, promptReply := "No", events := [], abortOnSleep := false
ShowStatus(*) => 0
ShowNotificationBasic(*) => 0
TrackToolTip(*) => 0
LogErrorToFile(*) => 0
UpdateAllWatchWords(*) => 0
FlashClickPosition(*) => 0
TestPointerPos(&x, &y) => (x := 100, y := 200)
RecordRawClick(*) {
    global pointerCalls
    pointerCalls.Push(Map("raw", true))
}
ClickVerified(x, y, button := "Left", count := 1) {
    global pointerCalls
    pointerCalls.Push(Map("x", x, "y", y, "button", button, "count", count, "raw", false))
    return true
}
ResolveWorkflowPoint(target, &x, &y) {
    if target = "KnownPoint"
        return (x := 120, y := 220, true)
    if RegExMatch(target, "^(-?\d+),(-?\d+)$", &match)
        return (x := Integer(match[1]), y := Integer(match[2]), true)
    return false
}
MsgBoxTop(*) {
    global prompts, promptReply
    prompts++
    return promptReply
}
TestHotkey(name, callbackOrOption, options := "") {
    global hotkeys
    hotkeys[name] := options = "On" ? true : false
}
TestSleep(ms) {
    global abortOnSleep, g_AbortSequence, g_StepThroughWaiting, g_StepThroughContinue
    if g_StepThroughWaiting
        g_StepThroughContinue := true
    if abortOnSleep
        g_AbortSequence := true
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
ExecuteActionVerified(action, target, param, stepData, speed) {
    global g_WorkflowVariables, g_LastActionError, g_AbortSequence, g_LoopBreakRequested, calls, g_SkipNextAction
    calls.Push(action . ":" . target . ":" . param)
    switch action {
        case "Wait": return WorkflowExecution_Wait(param != "" ? Integer(param) : 0)
        case "Set Variable": g_WorkflowVariables[target] := param
        case "Bad":
            g_LastActionError := "Intentional action failure"
            return false
        case "Throw": throw Error("Intentional action exception")
        case "Abort": g_AbortSequence := true
        case "Popup": g_LoopBreakRequested := true
        case "Skip": g_SkipNextAction := true
        case "Assert Variable":
            return g_WorkflowVariables.Has(target) && String(g_WorkflowVariables[target]) = param
        case "Run Sequence": return ExecuteSubSequenceByName(param, speed)
        case "Click", "Double Click", "Triple Click", "Right Click": return ActualPointerDispatch(action, target, param)
        case "Reentrant":
            inner := ExecuteSequenceVerified([Step("Wait")], 1, Map("interactive", false))
            return !inner["ok"] && inner["error"] = "A workflow is already running"
    }
    return true
}
Step(action, target := "", param := "") => Map("action", action, "target", target, "param", param, "enabled", true)
RecordEvent(event, data) {
    global events
    events.Push(event)
}
Check(condition, label) {
    global checks
    if !condition
        throw Error(label)
    checks++
}
Cleanup(label) {
    global hotkeys, g_WorkflowRunning, g_StepThroughWaiting, g_ActiveLoopDepth
    Check(!g_WorkflowRunning && !g_StepThroughWaiting && g_ActiveLoopDepth = 0, label . " resets running state")
    Check(!hotkeys.Has("Escape") || !hotkeys["Escape"], label . " releases Escape")
    Check(!hotkeys.Has("Tab") || !hotkeys["Tab"], label . " releases Tab")
}
ResetFixture() {
    global calls, prompts, promptReply, hotkeys, events, abortOnSleep, g_StepThroughMode, g_Settings, pointerCalls
    calls := [], prompts := 0, promptReply := "No", hotkeys := Map(), events := [], abortOnSleep := false
    g_StepThroughMode := true
    g_Settings["ActionDelay"] := 0
    pointerCalls := []
}
'''
        assertions = r'''
try {
    opts := Map("interactive", false, "onEvent", RecordEvent)
    r := ExecuteSequenceVerified([Step("Wait"), Step("Set Variable", "answer", "10"), Step("Assert Variable", "answer", "10")], 1, opts)
    Check(r["ok"] && r["completed"] = 3 && r["failed_step"] = 0 && !r["aborted"], "Successful workflow reports three actual steps")
    Check(prompts = 0 && !hotkeys.Has("Tab"), "Unattended execution ignores manual step-through")
    Check(events[1] = "start" && events[events.Length] = "end", "Execution events report start and end")
    Cleanup("Success")

    ResetFixture()
    r := ExecuteSequenceVerified([Step("Wait"), Step("Bad"), Step("Set Variable", "shouldNotRun", "1")], 1, opts)
    Check(!r["ok"] && r["completed"] = 1 && r["failed_step"] = 2 && r["error"] = "Intentional action failure", "Failure returns actual failed step and detail")
    Check(calls.Length = 2 && prompts = 0 && !g_WorkflowVariables.Has("shouldNotRun"), "Unattended failure stops without a prompt")
    Cleanup("Failure")

    ResetFixture()
    r := ExecuteSequenceVerified([Step("Throw")], 1, opts)
    Check(!r["ok"] && r["failed_step"] = 1 && r["error"] = "Intentional action exception", "Thrown action becomes a structured error")
    Cleanup("Exception")

    ResetFixture()
    r := ExecuteSequenceVerified([Step("Loop Start", "", "count=3; var=i"), Step("Wait"), Step("Loop End"), Step("Assert Variable", "i", "3")], 1, opts)
    Check(r["ok"] && r["completed"] = 8 && calls.Length = 4, "Loop executes all three passes and preserves its counter")
    Cleanup("Loop")

    ResetFixture()
    r := ExecuteSequenceVerified([Step("Loop Start", "", "count=2; var=outer"), Step("Loop Start", "", "count=3; var=inner"), Step("Loop Break"), Step("Bad"), Step("Loop End"), Step("Wait"), Step("Loop End")], 1, opts)
    Check(r["ok"] && calls.Length = 2, "Nested Loop Break exits its own loop and preserves the outer loop")
    Cleanup("Nested break")

    ResetFixture()
    r := ExecuteSequenceVerified([Step("Loop Start", "", "count=3"), Step("Popup"), Step("Bad"), Step("Loop End"), Step("Wait")], 1, opts)
    Check(r["ok"] && calls.Length = 2, "Popup loop break skips remaining loop body")
    Cleanup("Popup break")

    ResetFixture()
    r := ExecuteSequenceVerified([Step("Loop Start"), Step("Wait")], 1, opts)
    Check(!r["ok"] && r["completed"] = 0 && r["failed_step"] = 1 && calls.Length = 0, "Unclosed loop is rejected before any action")
    Cleanup("Unclosed loop")

    ResetFixture()
    r := ExecuteSequenceVerified([Step("Wait"), Step("Abort"), Step("Bad")], 1, opts)
    Check(!r["ok"] && r["aborted"] && r["completed"] = 2 && calls.Length = 2, "Abort during an action stops remaining steps")
    Cleanup("Abort")

    ResetFixture(), abortOnSleep := true, g_Settings["ActionDelay"] := 20
    r := ExecuteSequenceVerified([Step("Wait")], 1, opts)
    Check(!r["ok"] && r["aborted"], "Abort during the final delay cannot report success")
    Cleanup("Final delay abort")

    ResetFixture(), abortOnSleep := true
    started := A_TickCount
    r := ExecuteSequenceVerified([Step("Wait", "", "30000"), Step("Bad")], 1, opts)
    Check(!r["ok"] && r["aborted"] && calls.Length = 1 && A_TickCount-started < 1000, "An explicit long Wait exits promptly on cancellation")
    Cleanup("Explicit wait abort")

    ResetFixture()
    r := ExecuteSequenceVerified([Step("Reentrant"), Step("Wait")], 1, opts)
    Check(r["ok"] && r["completed"] = 2, "An overlapping workflow is rejected while the original continues: " . r["error"] . "; completed=" . r["completed"])
    Cleanup("Overlap")

    ResetFixture(), g_StepThroughMode := false
    r := ExecuteSequenceVerified([Step("Bad"), Step("Wait")])
    Check(!r["ok"] && prompts = 1 && calls.Length = 1, "Manual default retains its failure prompt and No stops")
    Cleanup("Manual No")

    ResetFixture(), g_StepThroughMode := false, promptReply := "Yes"
    r := ExecuteSequenceVerified([Step("Bad"), Step("Wait")])
    Check(!r["ok"] && prompts = 1 && calls.Length = 2 && r["completed"] = 1, "Manual Yes continues while retaining failed result")
    Cleanup("Manual Yes")

    ResetFixture()
    r := ExecuteSequenceVerified([Step("Wait"), Step("Wait")])
    Check(r["ok"] && hotkeys.Has("Tab") && !hotkeys["Tab"], "Manual default retains and cleans up step-through")
    Cleanup("Manual step-through")

    ResetFixture()
    g_Sequences["loopChild"] := Map("steps", [Step("Assert Variable", "parentValue", "kept"), Step("Loop Start", "", "count=3; var=childPass"), Step("Wait"), Step("Loop End")])
    r := ExecuteSequenceVerified([Step("Set Variable", "parentValue", "kept"), Step("Run Sequence", "", "loopChild"), Step("Assert Variable", "childPass", "3")], 1, opts)
    Check(r["ok"] && calls.Length = 7 && g_WorkflowVariables["parentValue"] = "kept", "Run Sequence repeats real child loops and preserves parent variables")
    Check(g_SequenceCallStack.Length = 0, "Successful child execution releases its call stack")
    Cleanup("Child loop")

    ResetFixture()
    g_Sequences["failedChild"] := Map("steps", [Step("Bad"), Step("Set Variable", "mustNotType", "unsafe")])
    r := ExecuteSequenceVerified([Step("Run Sequence", "", "failedChild"), Step("Bad")], 1, opts)
    Check(!r["ok"] && calls.Length = 2 && !g_WorkflowVariables.Has("mustNotType") && InStr(r["error"], "Sub-workflow 'failedChild' step 1: Intentional action failure"), "Unattended child failure stops before subsequent input and retains specific error")
    Cleanup("Child failure")

    ResetFixture()
    g_Sequences["thrownChild"] := Map("steps", [Step("Throw"), Step("Bad")])
    r := ExecuteSequenceVerified([Step("Run Sequence", "", "thrownChild")], 1, opts)
    Check(!r["ok"] && InStr(r["error"], "Sub-workflow 'thrownChild' step 1: Intentional action exception"), "Child exceptions surface their own name and failed step")
    Cleanup("Child exception")

    ResetFixture()
    g_Sequences["cancelChild"] := Map("steps", [Step("Abort"), Step("Bad")])
    r := ExecuteSequenceVerified([Step("Run Sequence", "", "cancelChild"), Step("Bad")], 1, opts)
    Check(!r["ok"] && r["aborted"] && calls.Length = 2 && g_SequenceCallStack.Length = 0, "Child cancellation propagates without resetting parent cancellation")
    Cleanup("Child abort")

    ResetFixture()
    g_Sequences["cycleA"] := Map("steps", [Step("Run Sequence", "", "cycleB")])
    g_Sequences["cycleB"] := Map("steps", [Step("Run Sequence", "", "cycleA")])
    r := ExecuteSequenceVerified([Step("Run Sequence", "", "cycleA")], 1, opts)
    Check(!r["ok"] && InStr(r["error"], "recursive call") && calls.Length = 3 && g_SequenceCallStack.Length = 0, "Recursive children stop and restore the call stack")
    Cleanup("Child recursion")

    ResetFixture(), g_StepThroughMode := false
    r := ExecuteSequenceVerified([Step("Run Sequence", "", "failedChild"), Step("Bad")])
    Check(!r["ok"] && prompts = 1 && calls.Length = 3 && g_WorkflowVariables["mustNotType"] = "unsafe", "Manual child failure retains continuation and parent failure prompt")
    Cleanup("Manual child continuation")

    ResetFixture(), g_StepThroughMode := false
    g_Sequences["standaloneChild"] := Map("steps", [Step("Loop Start", "", "count=2; var=standalonePass"), Step("Wait"), Step("Loop End")])
    Check(ExecuteSubSequenceByName("standaloneChild") && calls.Length = 2 && g_SequenceCallStack.Length = 0, "Manual single-step Run Sequence executes a standalone child with real loops")
    Cleanup("Standalone child")

    for , action in ["Click", "Double Click", "Triple Click", "Right Click"] {
        ResetFixture()
        r := ExecuteSequenceVerified([Step(action, "MissingField")], 1, opts)
        Check(!r["ok"] && r["failed_step"] = 1 && pointerCalls.Length = 0 && InStr(r["error"], "Unresolved " . action . " target 'MissingField'"), "Unattended " . action . " rejects an unresolved explicit target before clicking")
        Cleanup("Unresolved " . action)
    }

    ResetFixture()
    r := ExecuteSequenceVerified([Step("Set Variable", "point", "-123,456"), Step("Click", "$var.point"), Step("Double Click", "KnownPoint")], 1, opts)
    Check(r["ok"] && pointerCalls.Length = 2 && pointerCalls[1]["x"] = -123 && pointerCalls[1]["y"] = 456 && pointerCalls[2]["x"] = 120, "Observed negative coordinates and dynamic point variables resolve at runtime")
    Cleanup("Resolved points")

    ResetFixture()
    r := ExecuteSequenceVerified([Step("Click", "$var.undefinedPoint")], 1, opts)
    Check(!r["ok"] && pointerCalls.Length = 0 && InStr(r["error"], "$var.undefinedPoint"), "An undefined point variable cannot become a pointer fallback")
    Cleanup("Undefined point")

    ResetFixture()
    r := ExecuteSequenceVerified([Step("Click", "(none)", "-155,555")], 1, opts)
    Check(r["ok"] && pointerCalls.Length = 1 && pointerCalls[1]["x"] = -155, "Legacy coordinates in the Click parameter remain valid")
    Cleanup("Legacy point")

    ResetFixture(), g_StepThroughMode := false
    r := ExecuteSequenceVerified([Step("Click", "MissingField")])
    Check(r["ok"] && pointerCalls.Length = 1 && pointerCalls[1]["raw"], "Manual unresolved-target fallback remains compatible")
    Cleanup("Manual pointer fallback")
    FileAppend(checks . " workflow engine checks passed`n", "*")
    ExitApp(0)
} catch as err {
    FileAppend("FAIL: " . err.Message . "`n", "*")
    ExitApp(1)
}
'''
        with tempfile.TemporaryDirectory(prefix="fan-workflow-engine-") as temporary:
            script = Path(temporary) / "WorkflowEngine_Test.ahk"
            script.write_text(fixture + bodies + assertions, encoding="utf-8-sig")
            result = subprocess.run([str(interpreter), "/ErrorStdOut", str(script)],
                                    capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("workflow engine checks passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
