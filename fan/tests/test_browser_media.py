"""Automatic Chrome learning (passive, per profile/window) and Media Intel video analysis workers."""
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEMP = Path(tempfile.mkdtemp(prefix="fan-browser-"))
os.environ["FAN_TOOL_INDEX"] = str(TEMP / "tool_catalog.sqlite3")  # never touch the real page library
sys.path.insert(0, str(ROOT / "fan" / "bridge"))
sys.path.insert(0, str(ROOT / "fan" / "DeepSeekBridge"))

import browser_learning  # noqa: E402
import media_analysis  # noqa: E402


def control(cid, role, name, path, w=100, h=20, **extra):
    return {"id": cid, "role": role, "name": name, "accessibility_path": path, "bounds": {"x": 0, "y": 100 + cid * 20, "w": w, "h": h}, **extra}


def probe(url="https://example.org/domes/kits", title="Dome kits - Example", hwnd=101, extra_text=""):
    text = ("Geodesic dome kits ship with color coded struts and steel hubs. Assembly takes one weekend "
            "with two people and a ladder. " + extra_text)
    return {"ok": True, "url": url,
            "frame": {"hwnd": hwnd, "title": title, "frame_id": "frame-" + str(abs(hash(url + extra_text)) % 10**8),
                      "region": {"x": 0, "y": 0, "w": 1200, "h": 800}},
            "controls": [control(1, "document", "Dome kits", "1", 1200, 700),
                         control(2, "text", text, "1.1", 900, 40),
                         control(3, "link", "Strut length calculator", "1.2", href="https://example.org/calc"),
                         control(4, "edit", "Search kits", "1.3"),
                         control(5, "text", "secret field", "1.4", protected=True),
                         control(6, "button", "Accept cookies", "1.5"),
                         control(7, "text", "Chrome toolbar text", "2")]}


class BrowserLearningTests(unittest.TestCase):
    def test_only_readable_document_text_is_kept(self):
        controls, reason = browser_learning.readable(probe())
        names = [c["name"] for c in controls]
        self.assertIn("Strut length calculator", names)
        self.assertNotIn("Search kits", names)          # typed fields are never learned
        self.assertNotIn("secret field", names)         # protected controls never learned
        self.assertNotIn("Chrome toolbar text", names)  # browser chrome is not page content
        self.assertEqual(reason, "Visible page text and reference links")
        for url, title in [("https://mail.example.com/inbox", "Inbox"), ("https://example.com/login", "Shop"),
                           ("https://example.com/?session=abc", "x"), ("https://example.com/a", "Sign in to continue"),
                           ("chrome://settings", "Settings")]:
            self.assertEqual(browser_learning.readable(probe(url, title))[0], [], url)

    def test_observe_records_new_content_once_per_window_and_profile(self):
        db_path = TEMP / "track.sqlite"
        args = {"hwnd": 101, "pid": 9, "context_id": "chrome-9-101-7", "db_path": str(db_path), "profile_id": "chrome:c:/profile 1",
                "profile_label": "Work", "profile_path": "C:/Profile 1", "app_user_model_id": "Chrome.UserData.Profile1"}
        pages = [probe()]
        call = lambda tool, payload, timeout: pages[-1]
        always = lambda hwnd, pid, context: True
        first = browser_learning.observe(args, call=call, foreground=always)
        self.assertTrue(first["captured"], first)
        self.assertGreater(first["item_count"], 0)
        repeat = browser_learning.observe(args, call=call, foreground=always)
        self.assertEqual((repeat["captured"], repeat["reason"]), (False, "Already learned this visible content"))
        pages.append(probe(extra_text="Paint the hubs before assembly to prevent rust."))
        changed = browser_learning.observe(args, call=call, foreground=always)
        self.assertTrue(changed["captured"])
        self.assertEqual(changed["item_count"], 1)  # only what is new since the last reading of this window
        moved = browser_learning.observe(args, call=call, foreground=lambda *a: False)
        self.assertEqual(moved, {"ok": True, "captured": False, "reason": "Chrome focus changed"})
        with sqlite3.connect(db_path) as db:
            rows = db.execute("SELECT profile_label, profile_id, capture_kind, reviewed, item_count FROM chrome_learning_capture").fetchall()
        self.assertEqual(len(rows), 2)
        self.assertTrue(all(r[:4] == ("Work", "chrome:c:/profile 1", "auto_text", 0) for r in rows))


def make_video(path: Path) -> bool:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return False
    subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=320x180:rate=25:duration=2",
                    "-f", "lavfi", "-i", "color=c=red:size=320x180:rate=25:duration=2", "-filter_complex", "[0:v][1:v]concat=n=2:v=1:a=0[v]",
                    "-map", "[v]", "-c:v", "libx264", "-pix_fmt", "yuv420p", str(path)], check=True, timeout=60)
    return path.is_file()


class MediaAnalysisTests(unittest.TestCase):
    def test_missing_inputs_fail_clearly(self):
        with self.assertRaises(FileNotFoundError):
            media_analysis.run({"path": str(TEMP / "nope.mp4"), "engine_root": str(TEMP), "work_dir": str(TEMP / "w")}, lambda *a: 0, lambda: False)
        video = TEMP / "dummy.mp4"
        video.write_bytes(b"x")
        with self.assertRaisesRegex(FileNotFoundError, "Cutline analyzer"):
            media_analysis.run({"path": str(video), "engine_root": str(TEMP), "work_dir": str(TEMP / "w")}, lambda *a: 0, lambda: False)

    def test_local_analysis_finds_the_cut(self):
        engine = (ROOT.parent / "avideditor").resolve()
        if not (engine / "python" / "sidecar" / "analyze.py").is_file():
            self.skipTest("Cutline (avideditor) is not installed next to this project")
        try:
            media_analysis.engine_python(engine)
        except RuntimeError:
            self.skipTest("No installed Python has OpenCV")
        folder = Path(tempfile.mkdtemp(prefix="fan-media-"))
        video = folder / "clip with space.mp4"
        if not make_video(video):
            self.skipTest("ffmpeg is not installed")
        request = {"kind": "media_local", "args": {"path": str(video), "engine_root": str(engine), "work_dir": str(folder / "work")},
                   "result": str(folder / "result.json"), "progress": str(folder / "progress.json"), "cancel": str(folder / "cancel")}
        (folder / "request.json").write_text(json.dumps(request), encoding="utf-8")
        subprocess.run([sys.executable, str(ROOT / "fan" / "bridge" / "workspace_worker.py"), str(folder / "request.json")], timeout=600, check=True)
        result = json.loads((folder / "result.json").read_text(encoding="utf-8"))
        self.assertTrue(result["ok"], result)
        self.assertEqual(len(result["result"]["shots"]), 2)
        self.assertAlmostEqual(result["result"]["cuts"][0], 2.0, delta=0.3)
        self.assertTrue(all(Path(f["path"]).is_file() for f in result["frames"]))

    def test_semantic_worker_extracts_frames_even_when_the_model_is_unreachable(self):
        ahk = Path(os.environ.get("AUTOHOTKEY_EXE", r"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"))
        if os.name != "nt" or not ahk.is_file():
            self.skipTest("AutoHotkey v2 is not installed")
        folder = Path(tempfile.mkdtemp(prefix="fan-media-"))
        video = folder / "clip with space.mp4"
        if not make_video(video):
            self.skipTest("ffmpeg is not installed")
        db = folder / "media.sqlite"
        request = {"kind": "media_semantic", "args": {"path": str(video), "job_id": 0, "db_path": str(db), "question": "Describe it.",
                   "fps": 1, "batch": 4, "max_frames": 4, "scene": 0, "spent_usd": 0, "endpoint": "http://127.0.0.1:9",
                   "vision_model": "deepseek-flash"},
                   "result": str(folder / "result.json"), "progress": str(folder / "progress.json"), "cancel": str(folder / "cancel")}
        (folder / "request.json").write_text(json.dumps(request), encoding="utf-8")
        subprocess.run([str(ahk), "/ErrorStdOut=UTF-8", str(ROOT / "fan" / "MediaAnalysisWorker.ahk"), str(folder / "request.json")], timeout=300)
        result = json.loads((folder / "result.json").read_text(encoding="utf-8-sig"))
        self.assertFalse(result["ok"])
        self.assertIn("could not be established", result["error"])
        with sqlite3.connect(db) as connection:
            frames = [row[0] for row in connection.execute("SELECT path FROM media_frame")]
        self.assertEqual(len(frames), 4)
        self.assertTrue(all(Path(p).is_file() for p in frames))
        shutil.rmtree(Path(frames[0]).parent, ignore_errors=True)  # frames land in data\media_tmp


if __name__ == "__main__":
    unittest.main()
