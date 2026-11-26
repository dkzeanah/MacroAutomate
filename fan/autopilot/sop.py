"""Record once -> SOP document, narrated training video and a runnable workflow.

Input is either a recording made by lib\\AutopilotRecorder.ahk (``session.json``:
window switches, clicks with the label next to the pointer and a screenshot,
typing and shortcut keys) or an audited run (``run.json``). Output, in one
folder:

* ``sop.html``   printable SOP with numbered steps, screenshots and click markers
* ``sop.md``     the same in Markdown
* ``sop.docx``   a Word document (written directly as Office Open XML)
* ``video.mp4``  narrated training video (Windows voice + ffmpeg), when ffmpeg exists
* ``workflow.json`` steps for Fan's workflow engine plus self-heal anchors

Typing marked as masked (sign-in windows) is never written anywhere; the SOP
says "type your password" and the workflow asks for it at run time.
"""
from __future__ import annotations

import html
import json
import os
import re
import shutil
import struct
import subprocess
import textwrap
import time
import wave
import zipfile
from pathlib import Path

from .routines import friendly_app

KEY_NAMES = {"Enter": "Enter", "Tab": "Tab", "Esc": "Esc", "Escape": "Esc", "Space": "Space", "Backspace": "Backspace",
             "Delete": "Delete", "Del": "Delete", "Up": "Up arrow", "Down": "Down arrow", "Left": "Left arrow",
             "Right": "Right arrow", "Home": "Home", "End": "End", "PgUp": "Page Up", "PgDn": "Page Down"}
FRAME_W, FRAME_H = 1280, 720


def pretty_keys(send: str) -> str:
    """'^+s' -> 'Ctrl+Shift+S', '{Tab 3}' -> 'Tab (3 times)', '!{F4}' -> 'Alt+F4'."""
    mods, i = [], 0
    names = {"^": "Ctrl", "!": "Alt", "+": "Shift", "#": "Win"}
    while i < len(send) and send[i] in names:
        mods.append(names[send[i]])
        i += 1
    rest = send[i:]
    repeat = ""
    match = re.fullmatch(r"\{(\w+)(?:\s+(\d+))?\}", rest)
    if match:
        key = KEY_NAMES.get(match.group(1), match.group(1))
        if match.group(2) and match.group(2) != "1":
            repeat = f" ({match.group(2)} times)"
    else:
        key = rest.upper() if len(rest) == 1 else rest
    return "+".join(mods + [key]) + repeat


def _app(event: dict) -> str:
    exe = str(event.get("exe", "")).lower()
    return friendly_app(exe[:-4] if exe.endswith(".exe") else exe) if exe else "the app"


def _region(rx: float, ry: float) -> str:
    vertical = "top" if ry < 0.33 else "bottom" if ry > 0.66 else "middle"
    horizontal = "left" if rx < 0.33 else "right" if rx > 0.66 else "center"
    return "center" if vertical == "middle" and horizontal == "center" else f"{vertical} {horizontal}".replace("middle ", "")


def _document_name(title: str, app: str) -> str:
    title = re.sub(r"\s*[-|—–]\s*(Google Chrome|Microsoft Edge|Mozilla Firefox|Excel|Word|PowerPoint|Outlook|Notepad)$", "", title or "")
    title = title.strip()
    return title if title and title.lower() != app.lower() and len(title) <= 70 else ""


def steps_from_recording(session: dict) -> list[dict]:
    """Plain-language steps, each with its screenshot and the event it came from."""
    out: list[dict] = []
    seen_apps = set()
    last_shot = ""
    for event in session.get("events", []):
        kind = event.get("kind")
        app = _app(event)
        shot = event.get("shot", "")
        if kind == "app":
            doc = _document_name(event.get("title", ""), app)
            verb = "Switch to" if app in seen_apps else "Open"
            seen_apps.add(app)
            text = f"{verb} {app}" + (f" ({doc})" if doc else "") + "."
        elif kind == "click":
            label = (event.get("label") or "").strip()
            button = str(event.get("button", "Left"))
            verb = "Double-click" if event.get("double") else "Right-click" if button.lower().startswith("r") else "Click"
            if label:
                text = f"{verb} “{label}” in {app}."
            else:
                text = f"{verb} in the {_region(float(event.get('rel_x', 0.5)), float(event.get('rel_y', 0.5)))} of the {app} window."
        elif kind == "type":
            if event.get("masked"):
                text = "Type your password (it was not recorded)."
            else:
                typed = str(event.get("text", ""))
                text = f"Type “{typed[:80]}{'…' if len(typed) > 80 else ''}”."
        elif kind == "key":
            text = f"Press {pretty_keys(str(event.get('send', '')))}."
        else:
            continue
        if out and kind == "key" and out[-1]["event"].get("kind") == "key" and out[-1]["event"].get("send") == event.get("send"):
            out[-1]["repeat"] = out[-1].get("repeat", 1) + 1
            out[-1]["text"] = f"Press {pretty_keys(str(event.get('send', '')))} {out[-1]['repeat']} times."
            continue
        if shot:
            last_shot = shot
        out.append({"text": text, "shot": shot, "context_shot": shot or last_shot, "event": event,
                    "marker": (event.get("shot_x"), event.get("shot_y")) if kind == "click" and shot else None})
    return out


def steps_from_run(run: dict) -> list[dict]:
    out = []
    for step in run.get("steps", []):
        action, target, param = step.get("action", ""), str(step.get("target", "")), str(step.get("param", ""))
        if action in ("Wait", "Capture Evidence", "Loop Start", "Loop End", "Show Notification", "Set Variable"):
            continue
        texts = {
            "Activate Window": f"Switch to {re.sub(r'^ahk_exe\s+', '', param)}.",
            "Open Page": f"Open {re.sub(r'^url=([^;]+).*$', r'\1', param)} in your browser.",
            "OCR Click": f"Click “{param}”.",
            "Type Text": "Type the value you were asked for." if param.startswith("$var.") else f"Type “{param[:80]}”.",
            "Type Credential": f"Type the saved {param} for {target}.",
            "Send Keys": f"Press {pretty_keys(param)}.",
            "Paste": "Paste (Ctrl+V).",
            "Approval Gate": f"Check and approve: {param}",
            "Human Check": "If the site asks for a verification code or CAPTCHA, complete it yourself.",
            "Ask Input": f"Have this ready: {param.split(';')[0]}",
            "Run Program": f"Start {param}.",
            "Click Element": f"Click {target}.",
            "Find & Click": f"Click {target}.",
        }
        text = texts.get(action, f"{action}: {target or param}".strip(": ") + ".")
        out.append({"text": text, "shot": step.get("evidence", ""), "context_shot": step.get("evidence", ""), "event": step, "marker": None})
    return out


def workflow_from_recording(session: dict) -> tuple[list[dict], list[dict]]:
    """Engine steps plus self-heal anchors (one per click, keyed by enabled step index)."""
    steps: list[dict] = []
    anchors: list[dict] = []
    secrets = 0
    for event in session.get("events", []):
        kind = event.get("kind")
        window = "ahk_exe " + str(event.get("exe", "")) + (" ahk_class " + str(event["class"]) if event.get("class") else "")
        if kind == "app":
            steps.append({"action": "Activate Window", "target": "", "param": window, "enabled": True, "note": f"Switch to {_app(event)}"})
            steps.append({"action": "Wait", "target": "", "param": "400", "enabled": True, "note": "Let the window settle"})
        elif kind == "click":
            button = str(event.get("button", "Left"))
            action = "Double Click" if event.get("double") else "Right Click" if button.lower().startswith("r") else "Click"
            rx, ry = float(event.get("rel_x", 0.5)), float(event.get("rel_y", 0.5))
            target = f"winrel:{window.replace('|', ' ')}|{min(1, max(0, rx)):.4f},{min(1, max(0, ry)):.4f}"
            steps.append({"action": action, "target": target, "param": "", "enabled": True,
                          "note": f"“{event['label']}”" if event.get("label") else "Recorded position"})
            anchors.append({"step_index": len(steps), "action": action, "target": target, "exe": event.get("exe", ""),
                            "title": event.get("title", ""), "class": event.get("class", ""), "rel_x": rx, "rel_y": ry,
                            "win_w": event.get("win_w", 0), "win_h": event.get("win_h", 0), "label": event.get("label", ""),
                            "label_dx": event.get("label_dx", 0), "label_dy": event.get("label_dy", 0), "sample": event.get("sample", "")})
        elif kind == "type":
            if event.get("masked"):
                secrets += 1
                name = f"secret{secrets}"
                steps.insert(0, {"action": "Ask Input", "target": name, "param": "Password or code to type?; mask=1", "enabled": True,
                                 "note": "Masked while recording, so it is asked for at run time"})
                for anchor in anchors:
                    anchor["step_index"] += 1
                steps.append({"action": "Type Text", "target": "", "param": f"$var.{name}", "enabled": True, "note": "Types the masked value"})
            else:
                steps.append({"action": "Type Text", "target": "", "param": str(event.get("text", "")), "enabled": True, "note": "Recorded text"})
        elif kind == "key":
            steps.append({"action": "Send Keys", "target": "", "param": str(event.get("send", "")), "enabled": True, "note": "Recorded shortcut"})
    steps.append({"action": "Show Notification", "target": "", "param": f"Fan,{(session.get('title') or 'Procedure').replace(',', ' ')} done,3", "enabled": True})
    return steps, anchors


# ─── documents ────────────────────────────────────────────────────────────────

def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        return 0, 0
    return struct.unpack(">II", header[16:24])


def write_html(path: Path, title: str, meta: str, steps: list[dict], assets: Path) -> None:
    e = html.escape
    cards = []
    for number, step in enumerate(steps, 1):
        figure = ""
        shot = assets / step["shot"] if step["shot"] else None
        if shot and shot.is_file():
            marker = ""
            width, height = png_size(shot)
            if step["marker"] and width and height and step["marker"][0] is not None:
                left, top = 100 * float(step["marker"][0]) / width, 100 * float(step["marker"][1]) / height
                marker = f"<span class='mark' style='left:{left:.2f}%;top:{top:.2f}%'></span>"
            figure = f"<figure><div class='shot'><img src='{e(step['shot'])}' alt='Step {number}'>{marker}</div></figure>"
        cards.append(f"<li><p>{e(step['text'])}</p>{figure}</li>")
    page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(title)}</title><style>
:root{{--bg:#fafaf8;--card:#fff;--ink:#1d1d1f;--mute:#6b6b70;--line:#e3e3e0;--accent:#d93025}}
@media (prefers-color-scheme:dark){{:root{{--bg:#17171a;--card:#202024;--ink:#ececef;--mute:#a0a0a8;--line:#34343a;--accent:#ff6b5e}}}}
body{{margin:0;background:var(--bg);color:var(--ink);font:15px/1.55 "Segoe UI",system-ui,sans-serif}}
main{{max-width:900px;margin:0 auto;padding:28px 16px 60px}} h1{{margin:0 0 6px;font-size:26px}} .meta{{color:var(--mute)}}
ol{{padding-left:22px}} li{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:12px 16px;margin:14px 0}}
li p{{margin:0 0 8px;font-weight:600}} figure{{margin:0}} .shot{{position:relative;display:inline-block;max-width:100%}}
.shot img{{max-width:100%;border:1px solid var(--line);border-radius:8px;display:block}}
.mark{{position:absolute;width:34px;height:34px;margin:-17px 0 0 -17px;border:4px solid var(--accent);border-radius:50%;box-shadow:0 0 0 3px rgba(255,255,255,.6)}}
@media print{{li{{break-inside:avoid}} body{{background:#fff}}}}
</style></head><body><main><h1>{e(title)}</h1><div class="meta">{e(meta)}</div><ol>{''.join(cards)}</ol>
<p class="meta">Generated by Fan from a recorded procedure. Check each step against the live application before relying on it.</p></main></body></html>"""
    path.write_text(page, encoding="utf-8")


def write_markdown(path: Path, title: str, meta: str, steps: list[dict]) -> None:
    lines = [f"# {title}", "", f"_{meta}_", ""]
    for number, step in enumerate(steps, 1):
        lines.append(f"{number}. {step['text']}")
        if step["shot"]:
            lines.append(f"   ![Step {number}]({step['shot']})")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _x(text: str) -> str:
    return html.escape(text, quote=False)


def write_docx(path: Path, title: str, meta: str, steps: list[dict], assets: Path) -> None:
    """A real .docx: title, meta line, numbered steps with inline screenshots (6 inches wide max)."""
    rels, media, body = [], [], []

    def para(text, bold=False, size=None, spacing_after=120):
        props = "<w:rPr>" + ("<w:b/>" if bold else "") + (f'<w:sz w:val="{size}"/>' if size else "") + "</w:rPr>"
        return (f'<w:p><w:pPr><w:spacing w:after="{spacing_after}"/></w:pPr><w:r>{props}'
                f'<w:t xml:space="preserve">{_x(text)}</w:t></w:r></w:p>')

    body.append(para(title, bold=True, size=40, spacing_after=80))
    body.append(para(meta, size=18, spacing_after=240))
    for number, step in enumerate(steps, 1):
        body.append(para(f"Step {number}. {step['text']}", bold=True, size=24))
        shot = assets / step["shot"] if step["shot"] else None
        if shot and shot.is_file():
            width, height = png_size(shot)
            if width and height:
                index = len(media) + 1
                rid = f"rIdImg{index}"
                media.append((f"word/media/image{index}.png", shot))
                rels.append(f'<Relationship Id="{rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image{index}.png"/>')
                cx = min(5486400, width * 9525)  # 6 in max; 9525 EMU per pixel at 96 dpi
                cy = int(cx * height / width)
                body.append(
                    '<w:p><w:pPr><w:spacing w:after="240"/></w:pPr><w:r><w:drawing>'
                    f'<wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="{cx}" cy="{cy}"/><wp:docPr id="{index}" name="Step {number}"/>'
                    '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
                    f'<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="{index}" name="image{index}.png"/><pic:cNvPicPr/></pic:nvPicPr>'
                    f'<pic:blipFill><a:blip r:embed="{rid}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
                    f'<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
                    '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>')
    document = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
                'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
                'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">'
                f'<w:body>{"".join(body)}<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
                '<w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml",
                         '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                         '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                         '<Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/>'
                         '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
        archive.writestr("_rels/.rels",
                         '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                         '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
        archive.writestr("word/_rels/document.xml.rels",
                         '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                         + "".join(rels) + "</Relationships>")
        archive.writestr("word/document.xml", document)
        for name, source in media:
            archive.write(source, name)


# ─── narration and video ──────────────────────────────────────────────────────

def narrate(lines: list[str], folder: Path, timeout: int = 300) -> list[Path | None]:
    """WAV per line with the Windows voice (System.Speech). Missing entries mean no audio."""
    if os.name != "nt" or not lines:
        return [None] * len(lines)
    payload = folder / "narration.json"
    payload.write_text(json.dumps([{"text": t, "path": str(folder / f"voice_{i:03}.wav")} for i, t in enumerate(lines, 1)]), encoding="utf-8")
    script = folder / "narrate.ps1"
    script.write_text(
        "$ErrorActionPreference='Stop'\nAdd-Type -AssemblyName System.Speech\n"
        "$items = Get-Content -Raw -Encoding UTF8 -LiteralPath $args[0] | ConvertFrom-Json\n"
        "$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer\n$voice.Rate = 0\n"
        "foreach ($item in $items) { $voice.SetOutputToWaveFile($item.path); $voice.Speak($item.text) }\n"
        "$voice.SetOutputToNull(); $voice.Dispose()\n", encoding="utf-8")
    try:
        subprocess.run([shutil.which("powershell.exe") or "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script), str(payload)],
                       capture_output=True, timeout=timeout, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    except (OSError, subprocess.TimeoutExpired):
        pass
    out = []
    for i in range(1, len(lines) + 1):
        wav = folder / f"voice_{i:03}.wav"
        out.append(wav if wav.is_file() and wav.stat().st_size > 1000 else None)
    return out


def wav_seconds(path: Path | None) -> float:
    if not path:
        return 0.0
    try:
        with wave.open(str(path)) as handle:
            return handle.getnframes() / float(handle.getframerate())
    except (wave.Error, OSError):
        return 0.0


def _font(folder: Path) -> str:
    for candidate in (r"C:\Windows\Fonts\segoeui.ttf", r"C:\Windows\Fonts\arial.ttf", r"C:\Windows\Fonts\calibri.ttf"):
        if Path(candidate).is_file():
            shutil.copyfile(candidate, folder / "font.ttf")
            return "font.ttf"
    return ""


def make_video(title: str, steps: list[dict], assets: Path, folder: Path, ffmpeg: str, *, narration: bool = True,
               timeout: int = 900) -> dict:
    """One captioned segment per step (screenshot, click marker, voice), concatenated to video.mp4."""
    work = folder / "video_work"
    work.mkdir(parents=True, exist_ok=True)
    font = _font(work)
    if not font:
        return {"ok": False, "error": "No system font found for captions"}
    lines = [title] + [f"Step {i}. {s['text']}" for i, s in enumerate(steps, 1)] + ["That's the whole procedure."]
    voices = narrate(lines, work) if narration else [None] * len(lines)
    segments = []

    def run(args):
        done = subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", *args], cwd=work, capture_output=True,
                              text=True, timeout=timeout, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        if done.returncode != 0:
            raise RuntimeError((done.stderr or "ffmpeg failed")[-400:])

    caption_style = ("drawbox=x=0:y=ih-150:w=iw:h=150:color=black@0.62:t=fill,"
                     f"drawtext=fontfile={font}:textfile={{cap}}:expansion=none:fontcolor=white:fontsize=34:line_spacing=8:x=48:y=h-130")
    for index, line in enumerate(lines):
        cap = f"cap_{index:03}.txt"
        (work / cap).write_text("\n".join(textwrap.wrap(line, 62)[:3]), encoding="utf-8")
        duration = max(3.0, wav_seconds(voices[index]) + 0.8)
        audio = ["-i", voices[index].name] if voices[index] else ["-f", "lavfi", "-t", f"{duration:.2f}", "-i", "anullsrc=r=44100:cl=mono"]
        segment = f"seg_{index:03}.mp4"
        step = steps[index - 1] if 0 < index <= len(steps) else None
        shot = assets / step["context_shot"] if step and step.get("context_shot") else None
        if shot and shot.is_file():
            width, height = png_size(shot)
            marker = ""
            if step["marker"] and step["marker"][0] is not None and width and height:
                scale = min(FRAME_W / width, FRAME_H / height)
                mx = (FRAME_W - width * scale) / 2 + float(step["marker"][0]) * scale
                my = (FRAME_H - height * scale) / 2 + float(step["marker"][1]) * scale
                marker = f"drawbox=x={mx - 22:.0f}:y={my - 22:.0f}:w=44:h=44:color=red@0.95:t=5,"
            local = f"shot_{index:03}.png"
            shutil.copyfile(shot, work / local)
            video = ["-loop", "1", "-t", f"{duration:.2f}", "-i", local]
            filters = (f"[0:v]scale={FRAME_W}:{FRAME_H}:force_original_aspect_ratio=decrease,"
                       f"pad={FRAME_W}:{FRAME_H}:(ow-iw)/2:(oh-ih)/2:color=0x1F2430,{marker}" + caption_style.format(cap=cap))
        else:
            video = ["-f", "lavfi", "-t", f"{duration:.2f}", "-i", f"color=c=0x1F2430:s={FRAME_W}x{FRAME_H}:r=30"]
            size = 56 if index == 0 else 40
            filters = f"[0:v]drawtext=fontfile={font}:textfile={cap}:expansion=none:fontcolor=white:fontsize={size}:line_spacing=10:x=(w-tw)/2:y=(h-th)/2"
        run([*video, *audio, "-filter_complex", filters + ",format=yuv420p[v]", "-map", "[v]", "-map", "1:a",
             "-r", "30", "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-c:a", "aac", "-ar", "44100", "-ac", "1",
             "-t", f"{duration:.2f}", segment])
        segments.append(segment)
    (work / "segments.txt").write_text("".join(f"file '{s}'\n" for s in segments), encoding="utf-8")
    run(["-f", "concat", "-safe", "0", "-i", "segments.txt", "-c", "copy", "-movflags", "+faststart", str((folder / "video.mp4").resolve())])
    for path in work.iterdir():
        try:
            path.unlink()
        except OSError:
            pass
    try:
        work.rmdir()
    except OSError:
        pass
    return {"ok": True, "video": str(folder / "video.mp4"), "narrated": any(voices), "segments": len(segments)}


def find_ffmpeg(preferred: str = "") -> str:
    for candidate in (preferred, shutil.which("ffmpeg") or "", r"C:\ProgramData\chocolatey\bin\ffmpeg.exe"):
        if candidate and Path(candidate).is_file():
            return candidate
    return ""


def polish(steps: list[dict], request: dict) -> str:
    """Optional: friendlier wording from the model. Sends step text only, never screenshots or typed secrets."""
    from .compiler import parse_json
    from .llm import ChatClient, resolve_key
    key, _ = resolve_key()
    if not key:
        return "No model key configured; kept the original wording."
    client = ChatClient(request.get("endpoint") or "https://api.deepseek.com", request.get("model") or "deepseek-v4-pro",
                        key=key, budget_usd=request.get("budget_usd"))
    numbered = [{"n": i, "text": s["text"]} for i, s in enumerate(steps, 1)]
    completion = client.complete([
        {"role": "system", "content": "You edit standard operating procedures for office staff. Keep every step, in order, one sentence each, "
                                      "imperative voice, keep quoted UI labels exactly. Reply as JSON {\"steps\": [\"...\"]}."},
        {"role": "user", "content": json.dumps(numbered)}], max_tokens=1500)
    data = parse_json(completion.text).get("steps", [])
    if isinstance(data, list) and len(data) == len(steps) and all(isinstance(t, str) and t.strip() for t in data):
        for step, text in zip(steps, data):
            step["text"] = text.strip()
        return f"Wording polished by {completion.model} (about ${completion.cost_usd:.4f})."
    return "The model's wording did not match the steps; kept the original."


def build(request: dict) -> dict:
    """Mode sop_build: {session|run, out_dir, title, narrate, video, polish, ffmpeg}."""
    started = time.time()
    if request.get("session"):
        source = Path(request["session"])
        data = json.loads(source.read_text(encoding="utf-8-sig"))
        steps = steps_from_recording(data)
        workflow, anchors = workflow_from_recording(data)
        meta = f"Recorded {data.get('started', '')} by {data.get('user', '')} · {len(steps)} steps"
    elif request.get("run"):
        source = Path(request["run"])
        data = json.loads(source.read_text(encoding="utf-8-sig"))
        steps = steps_from_run(data)
        workflow, anchors = [], []
        meta = f"From the audited run of '{data.get('workflow', '')}' on {data.get('started', '')} · {len(steps)} steps"
    else:
        return {"ok": False, "error": "Give a recording (session) or an audited run (run)"}
    if not steps:
        return {"ok": False, "error": "Nothing was recorded"}
    assets = source.parent
    title = (request.get("title") or data.get("title") or data.get("workflow") or "Procedure").strip()[:120]
    out_dir = Path(request.get("out_dir") or assets)
    out_dir.mkdir(parents=True, exist_ok=True)
    notes = []
    if request.get("polish"):
        try:
            notes.append(polish(steps, request))
        except Exception as error:
            notes.append(f"Wording polish failed ({type(error).__name__}); kept the original.")
    for step in steps:  # documents reference screenshots next to them
        if step["shot"] and assets.resolve() != out_dir.resolve() and (assets / step["shot"]).is_file():
            shutil.copyfile(assets / step["shot"], out_dir / step["shot"])
    write_html(out_dir / "sop.html", title, meta, steps, out_dir)
    write_markdown(out_dir / "sop.md", title, meta, steps)
    write_docx(out_dir / "sop.docx", title, meta, steps, out_dir)
    (out_dir / "workflow.json").write_text(json.dumps({"title": title, "steps": workflow, "anchors": anchors}, indent=1), encoding="utf-8")
    result = {"ok": True, "title": title, "folder": str(out_dir), "html": str(out_dir / "sop.html"), "markdown": str(out_dir / "sop.md"),
              "docx": str(out_dir / "sop.docx"), "steps": [s["text"] for s in steps], "workflow": workflow, "anchors": anchors,
              "video": "", "notes": notes}
    if request.get("video", True):
        ffmpeg = find_ffmpeg(request.get("ffmpeg", ""))
        if not ffmpeg:
            notes.append("ffmpeg was not found, so no video was made (install it with: winget install ffmpeg).")
        else:
            try:
                video = make_video(title, steps, out_dir, out_dir, ffmpeg, narration=request.get("narrate", True))
                if video.get("ok"):
                    result["video"] = video["video"]
                    if not video["narrated"] and request.get("narrate", True):
                        notes.append("Windows speech was unavailable, so the video has captions but no voice.")
                else:
                    notes.append("Video: " + video.get("error", "failed"))
            except Exception as error:
                notes.append(f"Video failed: {error}"[:400])
    result["seconds"] = round(time.time() - started, 1)
    return result
