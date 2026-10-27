"""Exercise production workflow OCR functions with a fake OCR result, no desktop input.

Only Click is replaced with a recorder in the temporary AHK harness. Function
bodies are extracted from the real Live OCR module so argument and coordinate
regressions are checked in the same code that manual workflows execute.
"""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "Tabs" / "Tab_03_LiveOCR.ahk"


def function_source(source, name):
    start = re.search(r"^" + re.escape(name) + r"\([^\n]*\)\s*\{", source, re.M)
    if not start:
        raise AssertionError(f"Production function missing: {name}")
    depth = 0
    lines = source[start.start():].splitlines(keepends=True)
    output = []
    for line in lines:
        output.append(line)
        # Remove quoted strings before counting executable block braces.
        code = re.sub(r'"(?:`.|[^"`])*"|\'(?:`.|[^\'`])*\'', "", line)
        code = code.split(";", 1)[0]
        depth += code.count("{") - code.count("}")
        if depth == 0:
            return "".join(output)
    raise AssertionError(f"Unclosed production function: {name}")


class WorkflowOCRTests(unittest.TestCase):
    @unittest.skipUnless(os.name == "nt", "Requires the installed AutoHotkey v2 interpreter")
    def test_actual_ocr_actions_options_and_absolute_coordinates(self):
        interpreter = Path(os.environ.get("AUTOHOTKEY_EXE", r"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"))
        if not interpreter.is_file():
            self.skipTest("AutoHotkey v2 interpreter is unavailable")
        source = SOURCE.read_text(encoding="utf-8-sig")
        names = ["WorkflowOCR_Options", "WorkflowOCR_Center", "ExecuteOCRRegion",
                 "ExecuteOCRClick", "ExecuteOCRWait", "ExecuteFullScreenOCRToVar", "TestOCRAvailability"]
        bodies = "\n".join(function_source(source, name) for name in names)
        # Record the exact click coordinates without moving the user's mouse.
        self.assertEqual(bodies.count("Click(clickX, clickY)"), 2)
        bodies = bodies.replace("Click(clickX, clickY)", "RecordClick(clickX, clickY)")
        fixture = r'''
#Requires AutoHotkey v2.0
#Warn All, Off
global g_OCRSettings := Map("language", "en-US", "scale", 2.25)
global g_LastOCRText := "", g_LastOCRRegion := Map(), g_LastOCRResult := ""
global g_SpoolVariables := Map(), g_WordVariables := Map(), g_ExtractedData := Map()
global g_AbortSequence := false, g_OCRAvailable := false, recorded := Map(), checks := 0
class OCR {
    static Calls := [], Words := [], Lines := []
    static FromRect(x, y, w, h, options := 0) {
        this.Calls.Push(Map("x", x, "y", y, "w", w, "h", h, "options", options))
        return {Text: "Confirm workflow", Words: this.Words, Lines: this.Lines}
    }
}
IsOCRAvailable() => true
ParseRegionCoords(target) => Map("x1", -600, "y1", 240, "x2", -200, "y2", 440)
ShowStatus(*) => 0
ShowActionNotification(*) => 0
HighlightRegion(*) => 0
HighlightOCRWordsYellow(*) => 0
RefreshOCRVarsLV(*) => 0
LoadOCRRevolver(*) => 0
LogErrorToFile(*) => 0
ReportOCRError(action, region, message) => (FileAppend("OCR ERROR: " . message . "`n", "*"), false)
RecordClick(x, y) {
    global recorded
    recorded := Map("x", x, "y", y)
}
Check(condition, label) {
    global checks
    if !condition
        throw Error(label)
    checks++
}
CheckOptions(label) {
    call := OCR.Calls[OCR.Calls.Length]
    Check(IsObject(call["options"]), label . " uses options object")
    Check(call["options"].lang = "en-US" && call["options"].scale = 2.25, label . " preserves language/scale")
}
'''
        assertions = r'''
try {
    Check(ExecuteOCRRegion("region", "var:captured"), "OCR Region succeeds")
    CheckOptions("OCR Region")
    Check(g_SpoolVariables["captured"] = "Confirm workflow", "OCR text reaches workflow variable")
    call := OCR.Calls[1]
    Check(call["x"] = -600 && call["y"] = 240 && call["w"] = 400 && call["h"] = 200, "Negative origin is preserved")

    OCR.Words := [{Text: "Confirm", x: 520, y: 335, w: 41, h: 19}], OCR.Lines := []
    Check(ExecuteOCRClick("region", "Confirm"), "Word click succeeds")
    CheckOptions("OCR Click")
    Check(recorded["x"] = 540 && recorded["y"] = 344, "Nonzero word coordinates use screen center exactly once")

    OCR.Words := [], OCR.Lines := [{Text: "Confirm workflow", x: -550, y: -250, w: 42, h: 20}]
    Check(ExecuteOCRClick("region", "Confirm"), "Line click succeeds")
    Check(recorded["x"] = -529 && recorded["y"] = -240, "Negative line coordinates use screen center exactly once")

    Check(ExecuteOCRWait("region", "text:Confirm,500"), "OCR Wait succeeds")
    CheckOptions("OCR Wait")
    Check(ExecuteFullScreenOCRToVar("screenText"), "Full screen OCR succeeds")
    CheckOptions("Full screen OCR")
    Check(g_SpoolVariables["screenText"] = "Confirm workflow", "Full screen text reaches workflow variable")
    Check(TestOCRAvailability(), "OCR availability probe accepts the library signature")
    call := OCR.Calls[OCR.Calls.Length]
    Check(call["options"].lang = "en-US" && call["options"].scale = 1, "Availability probe uses one options object")
    FileAppend(checks . " workflow OCR checks passed`n", "*")
    ExitApp(0)
} catch as err {
    FileAppend("FAIL: " . err.Message . "`n", "*")
    ExitApp(1)
}
'''
        with tempfile.TemporaryDirectory(prefix="fan-workflow-ocr-") as temporary:
            script = Path(temporary) / "WorkflowOCR_Test.ahk"
            script.write_text(fixture + bodies + assertions, encoding="utf-8-sig")
            result = subprocess.run([str(interpreter), "/ErrorStdOut", str(script)],
                                    capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("workflow OCR checks passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
