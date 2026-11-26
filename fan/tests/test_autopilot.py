"""Fan Autopilot helper package: routine mining, compilation, validation, portals and the job CLI.

Pure Python and network-free: the model is replaced by a scripted transport.
"""
import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from fan.autopilot import catalog as cat, compiler, offline, portal, routines  # noqa: E402
from fan.autopilot.llm import ChatClient, LLMError  # noqa: E402

ACTIONS = [
    {"name": "Click", "spec": {"targetLabel": "Position", "targetHint": "name / x,y", "paramLabel": "Click count", "targetRequired": True}},
    {"name": "Right Click", "spec": {"targetLabel": "Position", "targetRequired": True}},
    {"name": "Send Keys", "spec": {"paramLabel": "Keys", "paramRequired": True}},
    {"name": "Type Text", "spec": {"paramLabel": "Text", "paramRequired": True}},
    {"name": "Paste", "spec": {}},
    {"name": "Wait", "spec": {"paramLabel": "Duration", "paramRequired": True}},
    {"name": "Activate Window", "spec": {"paramLabel": "Window title", "paramRequired": True}},
    {"name": "Run Program", "spec": {"paramLabel": "Program", "paramRequired": True}},
    {"name": "Wait for Window", "spec": {"paramLabel": "Window settings"}},
    {"name": "Find & Click", "spec": {"targetLabel": "Pattern", "targetRequired": True}},
    {"name": "OCR Click", "spec": {"targetLabel": "OCR area", "paramLabel": "Text", "targetRequired": True, "paramRequired": True}},
    {"name": "OCR Wait", "spec": {"targetLabel": "OCR area", "paramLabel": "Condition", "targetRequired": True, "paramRequired": True}},
    {"name": "Click Element", "spec": {"targetLabel": "Element", "targetRequired": True}},
    {"name": "Loop Start", "spec": {"paramLabel": "Loop settings"}},
    {"name": "Loop End", "spec": {}},
    {"name": "Show Notification", "spec": {"paramLabel": "Title,message,seconds", "paramRequired": True}},
    {"name": "Run Sequence", "spec": {"paramLabel": "Workflow name", "paramRequired": True}},
    {"name": "Scroll", "spec": {"paramLabel": "Scroll amount", "paramRequired": True}},
    {"name": "If Variable", "spec": {"targetLabel": "Variable", "paramLabel": "Comparison", "targetRequired": True, "paramRequired": True}},
]
CONTEXT = {"coordinates": ["SaveSpot"], "patterns": ["SaveButton"], "elements": ["SearchBox"],
           "workflows": ["Payroll login"], "credentials": ["Payroll"], "windows": ["Inbox - Outlook"]}


def catalog(context=CONTEXT):
    return cat.Catalog(ACTIONS, context)


def ev(ts, kind, exe, **data):
    data.setdefault("exe", exe + ".exe")
    token = {"APP": f"APP:{exe}:{data.get('title', '')}", "KEY": f"KEY:{data.get('send', '')}",
             "CLICK": data.pop("token", "CLICK:R10,10:L"), "TYPE": f"TYPE:{data.get('shape', 'text')}:short"}[kind]
    return {"ts": ts.strftime("%Y-%m-%d %H:%M:%S"), "kind": kind, "token": token, "data": data}


def copy_routine(start, typed="INV-1"):
    """Excel -> copy -> Chrome -> click a field -> paste -> type -> Enter."""
    t = start
    out = []
    for kind, exe, data, gap in [
        ("APP", "excel", {"title": "Invoices.xlsx - Excel", "class": "XLMAIN"}, 0),
        ("KEY", "excel", {"send": "^c"}, 2000),
        ("APP", "chrome", {"title": "Billing - Google Chrome", "class": "Chrome_WidgetWin_1"}, 1500),
        ("CLICK", "chrome", {"token": "CLICK:R8,6:L", "button": "Left", "rel_x": 0.41, "rel_y": 0.30, "element_id": 0}, 2500),
        ("KEY", "chrome", {"send": "^v"}, 1200),
        ("TYPE", "chrome", {"shape": "mixed", "length": len(typed), "text": typed, "duration_ms": 900}, 1100),
        ("KEY", "chrome", {"send": "{Enter}"}, 800),
    ]:
        t = t + timedelta(milliseconds=gap)
        out.append(ev(t, kind, exe, delay_ms=gap, **data))
    return out


NOISE_APPS = [("notepad", "Notepad"), ("explorer", "CabinetWClass"), ("teams", "TeamsWebView"),
              ("outlook", "rctrl_renwnd32"), ("acrobat", "AcrobatSDIWindow"), ("slack", "Chrome_WidgetWin_1")]


def noise(start, n=6, seed=0):
    """Unrelated activity that differs from day to day, like real usage."""
    out, t = [], start
    for i in range(n):
        t += timedelta(seconds=4)
        exe, klass = NOISE_APPS[(seed * 5 + i * (seed + 1)) % len(NOISE_APPS)]
        kind = "KEY" if (i + seed) % 3 == 0 else "APP"
        data = {"send": f"^{chr(97 + (i + seed) % 20)}"} if kind == "KEY" else {"title": f"{exe} {seed}", "class": klass}
        out.append(ev(t, kind, exe, delay_ms=4000, **data))
    return out


class RoutineTests(unittest.TestCase):
    def build(self, days=4, typed_values=None, per_day_hour=9):
        items, base = [], datetime(2026, 11, 2, per_day_hour, 0)  # a Monday
        for day in range(days):
            start = base + timedelta(days=7 * day if days <= 4 else day)
            items += noise(start - timedelta(minutes=3), seed=day)
            typed = (typed_values or ["INV-1"])[day % len(typed_values or ["INV-1"])]
            items += copy_routine(start, typed)
            items += noise(start + timedelta(minutes=2), 4, seed=day + 7)
        return routines.events_from_dicts(items)

    def test_finds_the_repeated_copy_routine_with_evidence_and_schedule(self):
        events = self.build(days=4)
        result = routines.analyze(events, now=datetime(2026, 11, 24, 12))
        self.assertEqual(len(result["routines"]), 1, [r["name"] for r in result["routines"]])
        found = result["routines"][0]
        self.assertEqual(found["name"], "Copy from Excel into Chrome")
        self.assertEqual(found["occurrences"], 4)
        self.assertEqual(found["length"], 7)
        self.assertEqual(found["schedule"]["weekday"], "Monday")
        self.assertIn("around 9 AM", found["schedule"]["text"])
        self.assertGreater(found["avg_seconds"], 8)
        actions = [s["action"] for s in found["steps"]]
        self.assertEqual(actions[0], "Activate Window")
        self.assertIn("Send Keys", actions)
        click = next(s for s in found["steps"] if s["action"] == "Click")
        self.assertTrue(click["target"].startswith("winrel:Billing - Google Chrome|0.41"), click["target"])
        self.assertEqual(found["steps"][-1]["action"], "Show Notification")
        self.assertEqual(len(found["evidence"]), 4)
        # identical typed text is replayed literally
        self.assertIn({"action": "Type Text", "target": "", "param": "INV-1", "enabled": True,
                       "note": "Same text every time"}, found["steps"])
        steps, report = cat.validate(found["steps"], cat.Catalog(ACTIONS))
        self.assertTrue(report.ok, report.as_dict())

    def test_changing_text_becomes_an_input_asked_up_front(self):
        events = self.build(days=4, typed_values=["INV-1", "INV-22", "INV-305", "INV-9"])
        found = routines.analyze(events, now=datetime(2026, 11, 24))["routines"][0]
        self.assertEqual(found["steps"][0]["action"], "Ask Input")
        self.assertEqual(found["inputs"][0]["var"], "input1")
        self.assertIn({"action": "Type Text", "target": "", "param": "$var.input1", "enabled": True,
                       "note": "Types the value you supply when the workflow starts"}, found["steps"])

    def test_per_week_only_reported_with_a_week_of_history(self):
        short = routines.analyze(self.build(days=3, per_day_hour=10)[:], now=datetime(2026, 11, 24))
        self.assertTrue(short["routines"])
        week = routines.analyze(self.build(days=10), now=datetime(2026, 11, 24))
        self.assertIsNotNone(week["routines"][0]["minutes_per_week"])
        self.assertEqual(week["routines"][0]["per_week_basis"], "measured")

    def test_window_ping_pong_and_excluded_routines_are_not_reported(self):
        items, t = [], datetime(2026, 11, 3, 9)
        for i in range(40):
            t += timedelta(seconds=3)
            items.append(ev(t, "APP", "excel" if i % 2 else "chrome", title="a", delay_ms=3000))
        self.assertEqual(routines.analyze(routines.events_from_dicts(items), now=t)["routines"], [])
        events = self.build(days=4)
        first = routines.analyze(events, now=datetime(2026, 11, 24))["routines"][0]
        again = routines.analyze(events, now=datetime(2026, 11, 24), excluded=[first["id"]])
        self.assertNotIn(first["id"], [r["id"] for r in again["routines"]])

    def test_reads_the_usage_log_read_only_and_resolves_learned_elements(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "fan.sqlite"
            db = sqlite3.connect(path)
            db.execute("CREATE TABLE usage_event (id INTEGER PRIMARY KEY, ts TEXT, tick INTEGER, app_id INTEGER, win_id INTEGER, kind TEXT, token TEXT, data TEXT, automated INTEGER DEFAULT 0)")
            db.execute("CREATE TABLE element (id INTEGER PRIMARY KEY, name TEXT)")
            db.execute("CREATE TABLE usage_element (id INTEGER PRIMARY KEY, element_id INTEGER, rel_x REAL, rel_y REAL, rel_w REAL, rel_h REAL, name TEXT)")
            db.execute("INSERT INTO element VALUES (7, 'BillingAmount')")
            db.execute("INSERT INTO usage_element VALUES (3, 7, 0.4, 0.3, 0.1, 0.05, 'amt')")
            for item in [e for e in self.build(days=4)]:
                data = dict(item.data)
                if item.kind == "CLICK":
                    data["element_id"] = 3
                db.execute("INSERT INTO usage_event(ts,kind,token,data,automated) VALUES (?,?,?,?,0)",
                           (item.ts.strftime("%Y-%m-%d %H:%M:%S"), item.kind, item.token, json.dumps(data)))
            db.execute("INSERT INTO usage_event(ts,kind,token,data,automated) VALUES ('2026-11-02 09:00:01','KEY','KEY:^z','{}',1)")
            db.commit()
            db.close()
            result = routines.find_routines(path, now=datetime(2026, 11, 24, 12), lookback_days=60)
            found = result["routines"][0]
            self.assertIn({"action": "Click Element", "target": "BillingAmount", "param": "Left", "enabled": True,
                           "note": "Learned element (pattern + window position)"}, found["steps"])
            self.assertEqual(result["events_analyzed"], 4 * (6 + 7 + 4))


class CatalogTests(unittest.TestCase):
    def test_reports_every_problem_with_its_step(self):
        steps = [{"action": "Teleport"}, {"action": "Wait", "param": "soon"}, {"action": "Find & Click", "target": "Ghost"},
                 {"action": "Type Credential", "target": "Payroll", "param": "pin"}, {"action": "Open Page", "param": "url=http://bank.example.com"},
                 {"action": "Loop Start", "param": "count=3"}, {"action": "Click", "target": "Nowhere"},
                 {"action": "If Variable", "target": "n", "param": "~5"}]
        accepted, report = cat.validate(steps, catalog())
        messages = {e.step: e.message for e in report.errors}
        self.assertIn("unknown action", messages[1])
        self.assertIn("Wait duration", messages[2])
        self.assertIn("pattern 'Ghost'", messages[3])
        self.assertIn("username or password", messages[4])
        self.assertNotIn(5, messages)
        self.assertIn("plain http", {w.step: w.message for w in report.warnings}[5])
        self.assertIn("not a saved coordinate", messages[7])
        self.assertIn("operator", messages[8])
        self.assertIn("no Loop End", messages[0])

    def test_accepts_saved_names_winrel_and_tracks_variables(self):
        steps = [{"action": "Ask Input", "target": "amount", "param": "How much?"},
                 {"action": "Click", "target": "winrel:ahk_exe chrome.exe|0.5,0.25"},
                 {"action": "Type Text", "param": "$var.amount $var.later"},
                 {"action": "Find & Click", "target": "SaveButton"}, {"action": "Click Element", "target": "SearchBox"},
                 {"action": "Type Credential", "target": "Payroll", "param": "password"},
                 {"action": "Run Sequence", "param": "Payroll login"}]
        _, report = cat.validate(steps, catalog())
        self.assertTrue(report.ok, report.as_dict())
        self.assertEqual([w.message for w in report.warnings], ["$var.later is used before any step sets it"])

    def test_high_risk_steps_get_an_approval_gate_once(self):
        steps = [{"action": "Type Text", "target": "", "param": "x", "enabled": True},
                 {"action": "OCR Click", "target": "window:A", "param": "Submit payment", "enabled": True},
                 {"action": "Approval Gate", "target": "", "param": "ok?", "enabled": True},
                 {"action": "Wait", "target": "", "param": "200", "enabled": True},
                 {"action": "Find & Click", "target": "Delete invoice", "enabled": True, "param": ""}]
        gated, notes = cat.ensure_approval_gates(steps)
        self.assertEqual([s["action"] for s in gated],
                         ["Type Text", "Approval Gate", "OCR Click", "Approval Gate", "Wait", "Find & Click"])
        self.assertEqual(len(notes), 1)
        self.assertEqual(cat.assess_risks([{"action": "Run Program", "target": "", "param": "cmd /c del x"}])[0]["level"], "high")


class OfflineTests(unittest.TestCase):
    def test_common_office_phrasing(self):
        result = offline.compile_text("Open Excel, press ctrl+shift+s, wait 2 seconds, click Save then ask me for the invoice number. "
                                      "Type the value I gave for invoice number and press enter. Repeat 3 times", CONTEXT)
        actions = [(s["action"], s["param"]) for s in result["steps"]]
        self.assertEqual(actions[0], ("Loop Start", "count=3; var=i"))
        self.assertIn(("Run Program", "excel.exe"), actions)
        self.assertIn(("Send Keys", "^+s"), actions)
        self.assertIn(("Wait", "2000"), actions)
        self.assertIn(("OCR Click", "Save"), actions)
        self.assertIn(("Ask Input", "Invoice number?"), actions)
        self.assertIn(("Type Text", "$var.invoiceNumber"), actions)
        self.assertIn(("Send Keys", "{Enter}"), actions)
        self.assertEqual(actions[-1], ("Loop End", ""))
        self.assertEqual(result["questions"], [])

    def test_secrets_are_never_typed_literally_and_unknown_phrases_become_questions(self):
        result = offline.compile_text("go to paychex.com\nlog in to Payroll\ntype my password\nflibber the jabberwock", CONTEXT)
        actions = [s["action"] for s in result["steps"]]
        self.assertEqual(actions[0], "Open Page")
        self.assertIn("url=https://paychex.com", result["steps"][0]["param"])
        self.assertEqual(result["steps"][1], {"action": "Run Sequence", "target": "", "param": "Payroll login", "enabled": True})
        self.assertNotIn("Type Text", actions)
        self.assertEqual(len(result["questions"]), 2)

    def test_key_sequences(self):
        self.assertEqual(offline.key_sequence("ctrl+s"), "^s")
        self.assertEqual(offline.key_sequence("alt f4"), "!{F4}")
        self.assertEqual(offline.key_sequence("tab 3 times"), "{Tab 3}")
        self.assertEqual(offline.key_sequence("ctrl shift n"), "^+n")
        self.assertIsNone(offline.key_sequence("banana+q"))


class ScriptedTransport:
    def __init__(self, replies):
        self.replies, self.calls = list(replies), []

    def __call__(self, url, body):
        self.calls.append(body)
        reply = self.replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return {"model": "deepseek-v4-pro", "choices": [{"message": {"content": reply}}],
                "usage": {"prompt_tokens": 1000, "completion_tokens": 200}}


class CompilerTests(unittest.TestCase):
    def test_model_proposal_is_repaired_then_gated(self):
        bad = json.dumps({"name": "Pay vendor", "steps": [{"action": "Teleport"}]})
        good = "```json\n" + json.dumps({"name": "Pay vendor", "summary": "s", "steps": [
            {"action": "Activate Window", "param": "Inbox - Outlook"},
            {"action": "OCR Click", "target": "window:A", "param": "Send"}], "assumptions": ["a"], "questions": []}) + "\n```"
        transport = ScriptedTransport([bad, good])
        client = ChatClient(key="test", transport=transport)
        result = compiler.compile_description("Send the vendor email", catalog(), CONTEXT, client=client)
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["source"], "model")
        self.assertEqual([s["action"] for s in result["steps"]], ["Activate Window", "Approval Gate", "OCR Click"])
        self.assertEqual(result["usage"]["requests"], 2)
        self.assertIn("unknown action", transport.calls[1]["messages"][-1]["content"])
        self.assertEqual(transport.calls[0]["response_format"], {"type": "json_object"})
        self.assertIn("SearchBox", transport.calls[0]["messages"][1]["content"])

    def test_falls_back_offline_when_the_model_fails_or_has_no_key(self):
        failure = LLMError("Model API returned HTTP 401")
        client = ChatClient(key="test", transport=ScriptedTransport([failure]))
        result = compiler.compile_description("open notepad then type hello", catalog(), CONTEXT, client=client)
        self.assertEqual(result["source"], "offline")
        self.assertTrue(result["ok"])
        self.assertIn("HTTP 401", result["notes"][0])
        no_key = compiler.compile_description("press enter", catalog(), CONTEXT, client=ChatClient(key=""))
        self.assertIn("No model key", no_key["notes"][0])

    def test_budget_and_endpoint_guards(self):
        with self.assertRaises(LLMError):
            ChatClient(endpoint="http://api.example.com", key="k")
        client = ChatClient(key="k", budget_usd=0.000001, transport=ScriptedTransport(["{}"]))
        with self.assertRaises(LLMError):
            client.complete([{"role": "user", "content": "x" * 1000}])

    def test_parse_json_tolerates_prose_around_the_object(self):
        self.assertEqual(compiler.parse_json('Here you go: {"a": "}"} thanks')["a"], "}")
        with self.assertRaises(ValueError):
            compiler.parse_json("no json")


class PortalTests(unittest.TestCase):
    def test_profile_rules_and_login_template(self):
        _, errors, _ = portal.validate_profile({"name": "Bank", "url": "http://bank.example.com"})
        self.assertTrue(errors)
        _, errors, warnings = portal.validate_profile({"name": "Local", "url": "http://localhost:8080/login"})
        self.assertFalse(errors)
        self.assertTrue(warnings)
        template = portal.login_workflow({"name": "Payroll", "url": "https://login.paychex.com/sign-in",
                                          "username_label": "Email", "submit_label": "Sign in"})
        self.assertTrue(template["ok"])
        actions = [s["action"] for s in template["steps"]]
        self.assertEqual(actions[0], "Open Page")
        self.assertEqual(actions.count("Type Credential"), 2)
        self.assertEqual(actions.count("Human Check"), 2)
        self.assertEqual(actions[-1], "Capture Evidence")
        credential_steps = [s for s in template["steps"] if s["action"] == "Type Credential"]
        self.assertTrue(all(s["failsafe"] == {"window": "paychex", "abortOnFail": 1} for s in credential_steps))
        _, report = cat.validate(template["steps"], cat.Catalog(ACTIONS, {"credentials": ["Payroll"]}))
        self.assertTrue(report.ok, report.as_dict())

    def test_audit_report_masks_typed_values_and_refuses_outside_files(self):
        with tempfile.TemporaryDirectory() as folder:
            run_dir = Path(folder) / "run1"
            run_dir.mkdir()
            (run_dir / "step_02.png").write_bytes(b"\x89PNG fake")
            (Path(folder) / "secret.png").write_bytes(b"x")
            record = {"run_id": "run1", "workflow": "Payroll timesheet", "portal": "Payroll", "ok": True, "completed": 3,
                      "started": "2026-11-24 09:00:00", "finished": "2026-11-24 09:01:00", "user": "office", "mode": "interactive",
                      "steps": [{"index": 1, "action": "Type Text", "param": "123-45-6789", "status": "completed", "ms": 300},
                                {"index": 2, "action": "OCR Click", "target": "window:A", "param": "Submit", "status": "healed",
                                 "heal": {"strategy": "label", "confidence": 0.86}, "evidence": "step_02.png", "ms": 900},
                                {"index": 3, "action": "Approval Gate", "param": "Submit?", "status": "approved",
                                 "approval": {"decision": "approved", "by": "office", "at": "09:00:40"}, "evidence": "../secret.png"}],
                      "evidence": [{"label": "Confirmation <b>", "file": "step_02.png", "at": "09:01", "step": 2}]}
            (run_dir / "run.json").write_text(json.dumps(record), encoding="utf-8")
            result = portal.build_report(run_dir)
            page = (run_dir / "report.html").read_text(encoding="utf-8")
            self.assertEqual((result["heals"], result["approvals"], result["evidence"]), (1, 1, 1))
            self.assertNotIn("123-45-6789", page)
            self.assertIn("12… (11 characters)", page)
            self.assertNotIn("secret.png", page)
            self.assertIn("Confirmation &lt;b&gt;", page)
            self.assertIn("Self-healed by label", page)


class CliTests(unittest.TestCase):
    def run_job(self, request):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "request.json"
            path.write_text(json.dumps(request), encoding="utf-8")
            done = subprocess.run([sys.executable, "-m", "fan.autopilot.cli", str(path)], cwd=ROOT,
                                  capture_output=True, text=True, timeout=60)
            result = json.loads((Path(folder) / "result.json").read_text(encoding="utf-8"))
            status = json.loads((Path(folder) / "status.json").read_text(encoding="utf-8"))
            return done.returncode, result, status

    def test_modes_always_write_a_result(self):
        code, result, status = self.run_job({"mode": "compile", "compile_mode": "offline", "description": "press ctrl+s",
                                             "catalog": ACTIONS, "context": CONTEXT})
        self.assertEqual((code, result["ok"], status["phase"]), (0, True, "complete"))
        self.assertEqual(result["steps"][0]["param"], "^s")
        code, result, _ = self.run_job({"mode": "nope"})
        self.assertEqual(code, 1)
        self.assertIn("Unknown Autopilot mode", result["error"])
        code, result, _ = self.run_job({"mode": "routines", "db": str(ROOT / "does-not-exist.sqlite")})
        self.assertEqual(code, 1)
        self.assertIn("Error", result["error"])


if __name__ == "__main__":
    unittest.main()
