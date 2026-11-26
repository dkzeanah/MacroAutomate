"""Record once -> SOP (HTML, Markdown, Word), narrated video and workflow."""
import json
import shutil
import struct
import sys
import tempfile
import unittest
import zipfile
import zlib
from pathlib import Path
from unittest import mock
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from fan.autopilot import sop  # noqa: E402
from fan.autopilot.catalog import Catalog, validate  # noqa: E402


def png(path: Path, width: int, height: int, rgb=(220, 225, 240)):
    raw = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))
    chunk = lambda kind, data: struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


SESSION = {"title": "Send the weekly invoice", "started": "2026-11-26 09:00:00", "user": "office", "events": [
    {"kind": "app", "exe": "OUTLOOK.EXE", "class": "rctrl_renwnd32", "title": "Inbox - Outlook", "shot": "001.png"},
    {"kind": "click", "exe": "OUTLOOK.EXE", "class": "rctrl_renwnd32", "title": "Inbox", "button": "Left", "rel_x": 0.1, "rel_y": 0.08,
     "label": "New Email", "label_dx": 0, "label_dy": 2, "shot": "002.png", "shot_x": 80, "shot_y": 40, "sample": "00", "win_w": 800, "win_h": 500},
    {"kind": "click", "exe": "OUTLOOK.EXE", "class": "rctrl_renwnd32", "title": "Untitled", "button": "Right", "rel_x": 0.9, "rel_y": 0.9,
     "label": "", "shot": "", "double": 0},
    {"kind": "type", "exe": "OUTLOOK.EXE", "text": "Invoice attached - thank you!"},
    {"kind": "type", "exe": "OUTLOOK.EXE", "masked": 1, "length": 9},
    {"kind": "key", "exe": "OUTLOOK.EXE", "send": "{Tab}"}, {"kind": "key", "exe": "OUTLOOK.EXE", "send": "{Tab}"},
    {"kind": "key", "exe": "OUTLOOK.EXE", "send": "^{Enter}"}]}


class SopTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="fan-sop-"))
        png(self.folder / "001.png", 400, 250)
        png(self.folder / "002.png", 400, 250, (200, 230, 255))
        (self.folder / "session.json").write_text(json.dumps(SESSION), encoding="utf-8")

    def test_steps_read_like_instructions_and_never_contain_secrets(self):
        steps = [s["text"] for s in sop.steps_from_recording(SESSION)]
        self.assertEqual(steps, ["Open Outlook (Inbox).", "Click “New Email” in Outlook.", "Right-click in the bottom right of the Outlook window.",
                                 "Type “Invoice attached - thank you!”.", "Type your password (it was not recorded).",
                                 "Press Tab 2 times.", "Press Ctrl+Enter."])
        self.assertEqual(sop.pretty_keys("!{F4}"), "Alt+F4")
        self.assertEqual(sop.pretty_keys("{Tab 3}"), "Tab (3 times)")

    def test_workflow_is_valid_and_anchors_point_at_click_steps(self):
        steps, anchors = sop.workflow_from_recording(SESSION)
        self.assertEqual(steps[0]["action"], "Ask Input")  # the masked value is asked for, never stored
        self.assertNotIn("secret", json.dumps(SESSION).lower())
        sys.path.insert(0, str(Path(__file__).parent))
        from test_autopilot import ACTIONS  # the same action catalog the app exports
        _, report = validate(steps, Catalog(ACTIONS))
        self.assertTrue(report.ok, report.as_dict())
        for anchor in anchors:
            self.assertIn(steps[anchor["step_index"] - 1]["action"], ("Click", "Right Click"))
        self.assertEqual(anchors[0]["label"], "New Email")

    def test_documents_without_video(self):
        with mock.patch.object(sop, "find_ffmpeg", return_value=""):
            result = sop.build({"session": str(self.folder / "session.json"), "narrate": False})
        self.assertTrue(result["ok"])
        self.assertEqual(result["video"], "")
        self.assertIn("ffmpeg was not found", " ".join(result["notes"]))
        page = Path(result["html"]).read_text(encoding="utf-8")
        self.assertIn("class='mark' style='left:20.00%;top:16.00%'", page)
        self.assertIn("Type your password (it was not recorded).", Path(result["markdown"]).read_text(encoding="utf-8"))
        with zipfile.ZipFile(result["docx"]) as archive:
            names = archive.namelist()
            for name in names:
                if name.endswith(".xml") or name.endswith(".rels"):
                    ElementTree.fromstring(archive.read(name))  # every part is well-formed XML
            document = archive.read("word/document.xml").decode("utf-8")
            rels = archive.read("word/_rels/document.xml.rels").decode("utf-8")
        self.assertEqual(sorted(n for n in names if n.startswith("word/media/")), ["word/media/image1.png", "word/media/image2.png"])
        self.assertIn('r:embed="rIdImg2"', document)
        self.assertIn('Id="rIdImg2"', rels)
        self.assertIn("Step 7. Press Ctrl+Enter.", document)
        workflow = json.loads((self.folder / "workflow.json").read_text(encoding="utf-8"))
        self.assertEqual(workflow["title"], "Send the weekly invoice")

    def test_sop_from_an_audited_run(self):
        run = {"workflow": "Payroll login", "started": "2026-11-26 08:00", "steps": [
            {"action": "Open Page", "param": "url=https://login.example.com; timeout=30000", "evidence": "001.png"},
            {"action": "Wait", "param": "1500"}, {"action": "Type Credential", "target": "Payroll", "param": "password"},
            {"action": "Human Check", "target": "window:A", "param": "on=pause"}, {"action": "Send Keys", "param": "{Enter}"}]}
        (self.folder / "run.json").write_text(json.dumps(run), encoding="utf-8")
        with mock.patch.object(sop, "find_ffmpeg", return_value=""):
            result = sop.build({"run": str(self.folder / "run.json"), "out_dir": str(self.folder / "sop")})
        self.assertEqual(result["steps"], ["Open https://login.example.com in your browser.", "Type the saved password for Payroll.",
                                           "If the site asks for a verification code or CAPTCHA, complete it yourself.", "Press Enter."])
        self.assertTrue((self.folder / "sop" / "001.png").is_file())
        self.assertEqual(result["workflow"], [])

    def test_narrated_video(self):
        if not sop.find_ffmpeg():
            self.skipTest("ffmpeg is not installed")
        result = sop.build({"session": str(self.folder / "session.json"), "narrate": True, "video": True})
        self.assertTrue(result["video"], result["notes"])
        ffprobe = shutil.which("ffprobe")
        if ffprobe:
            import subprocess
            probe = subprocess.run([ffprobe, "-v", "error", "-show_entries", "stream=codec_type", "-of", "csv=p=0", result["video"]],
                                   capture_output=True, text=True).stdout.split()
            self.assertEqual(sorted(probe), ["audio", "video"])
        self.assertFalse((self.folder / "video_work").exists())


if __name__ == "__main__":
    unittest.main()
