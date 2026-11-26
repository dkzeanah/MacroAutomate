"""Portal profiles, starter login workflows and audit-trail reports.

A *portal* is a website the office signs in to (payroll, insurance, a vendor or
state site). Fan stores the username/password in Windows Credential Manager
under ``Fan/Portal/<name>``; workflows refer to it with Type Credential and the
secret never appears in a workflow, request file, log or report.

Every portal run writes ``run.json`` plus screenshots. :func:`build_report`
turns that into a self-contained HTML audit page (what ran, when, who approved
which step, what was healed, and proof screenshots).
"""
from __future__ import annotations

import html
import json
import re
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

from .catalog import CRED_NAME

LOCAL_HOSTS = ("localhost", "127.0.0.1", "[::1]")
CREDENTIAL_PREFIX = "Fan/Portal/"


def credential_target(name: str) -> str:
    return CREDENTIAL_PREFIX + name


def title_hint(url: str) -> str:
    host = (urlparse(url).hostname or "").lower()
    parts = [p for p in host.split(".") if p not in ("www", "login", "secure", "portal", "my", "app", "auth", "signin")]
    if len(parts) >= 2:
        return parts[-2]
    return parts[0] if parts else ""


def validate_profile(profile: dict) -> tuple[dict, list[str], list[str]]:
    errors, warnings = [], []
    name = str(profile.get("name", "")).strip()
    url = str(profile.get("url", "")).strip()
    if not CRED_NAME.match(name):
        errors.append("Portal name must be 1..60 letters, numbers, spaces, _ . -")
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        errors.append("Portal address must start with https://")
    elif parsed.scheme == "http":
        if (parsed.hostname or "") in LOCAL_HOSTS or (parsed.hostname or "").endswith((".localhost", ".test")):
            warnings.append("Plain http is only acceptable for a local test portal.")
        else:
            errors.append("Use the portal's https:// address; passwords must not be typed into an http page.")
    clean = {"name": name, "url": url}
    for key in ("username_label", "password_label", "submit_label", "title_hint", "notes"):
        value = re.sub(r"[\r\n\t]+", " ", str(profile.get(key, "") or "")).strip()
        if len(value) > (400 if key == "notes" else 60):
            errors.append(f"{key.replace('_', ' ')} is too long")
        clean[key] = value
    if not clean["title_hint"] and not errors:
        clean["title_hint"] = title_hint(url)
    clean["credential_target"] = credential_target(name) if name else ""
    return clean, errors, warnings


def login_workflow(profile: dict) -> dict:
    """A reviewable starter workflow: open, sign in, hand any verification to a person, capture proof."""
    clean, errors, warnings = validate_profile(profile)
    if errors:
        return {"ok": False, "errors": errors, "warnings": warnings, "steps": []}
    name, hint = clean["name"], clean["title_hint"]
    guard = {"window": hint, "abortOnFail": 1} if hint else {}
    steps = [{"action": "Open Page", "target": "", "param": f"url={clean['url']}; wait={hint}; timeout=30000",
              "note": "Opens the sign-in page and waits for its browser tab"},
             {"action": "Wait", "target": "", "param": "1500", "note": "Lets the page finish drawing"},
             {"action": "Human Check", "target": "window:A", "param": "on=pause",
              "note": "If a CAPTCHA or cookie wall is shown, you complete it"}]
    if clean["username_label"]:
        steps.append({"action": "OCR Click", "target": "window:A", "param": clean["username_label"],
                      "note": "Clicks the username box by its label"})
    steps.append({"action": "Type Credential", "target": name, "param": "username", "failsafe": guard,
                  "note": "Types the saved username only if the portal window is active"})
    if clean["password_label"]:
        steps.append({"action": "OCR Click", "target": "window:A", "param": clean["password_label"],
                      "note": "Clicks the password box by its label"})
    else:
        steps.append({"action": "Send Keys", "target": "", "param": "{Tab}", "note": "Moves to the password box"})
    steps.append({"action": "Type Credential", "target": name, "param": "password", "failsafe": guard,
                  "note": "Types the saved password only if the portal window is active"})
    if clean["submit_label"]:
        steps.append({"action": "OCR Click", "target": "window:A", "param": clean["submit_label"],
                      "note": "Clicks the sign-in button"})
    else:
        steps.append({"action": "Send Keys", "target": "", "param": "{Enter}", "note": "Submits the sign-in form"})
    steps += [{"action": "Wait", "target": "", "param": "3000", "note": "Waits for the portal to respond"},
              {"action": "Human Check", "target": "window:A", "param": "on=pause",
               "note": "Multi-factor codes and verification prompts are always yours to complete"},
              {"action": "Capture Evidence", "target": "window:A", "param": f"Signed in to {name}",
               "note": "Proof screenshot for the audit trail"}]
    for step in steps:
        step["enabled"] = True
        step.setdefault("failsafe", {})
    return {"ok": True, "name": f"{name} login", "profile": clean, "steps": steps, "warnings": warnings,
            "notes": ["Run it once while watching. If a label is not found, edit that step's text to match the page."]}


# ─── audit report ───────────────────────────────────────────────────────────

STATUS_LABEL = {"completed": "Done", "failed": "Failed", "skipped": "Skipped", "healed": "Healed",
                "approved": "Approved", "declined": "Declined", "human": "Person completed"}
MASKED_ACTIONS = {"Type Text", "Use Var Paste", "Set Clipboard", "Set Variable"}


def _mask(action: str, value: str, reveal: bool) -> str:
    if reveal or action not in MASKED_ACTIONS or not value or value.startswith("$var."):
        return value
    return f"{value[:2]}… ({len(value)} characters)"


def _rel(run_dir: Path, file_name: str) -> str:
    """Only files inside the run folder may be linked from the report."""
    if not file_name:
        return ""
    candidate = (run_dir / file_name).resolve()
    try:
        candidate.relative_to(run_dir.resolve())
    except ValueError:
        return ""
    return candidate.name if candidate.is_file() else ""


def build_report(run_dir: str | Path, *, reveal_typed: bool = False) -> dict:
    run_dir = Path(run_dir)
    record = json.loads((run_dir / "run.json").read_text(encoding="utf-8-sig"))
    steps = record.get("steps") or []
    evidence = record.get("evidence") or []
    e = html.escape
    status = "Completed" if record.get("ok") else ("Stopped" if record.get("aborted") else "Failed")
    tone = "ok" if record.get("ok") else "bad"
    heals = sum(1 for s in steps if s.get("heal"))
    approvals = [s for s in steps if s.get("approval")]
    rows = []
    for step in steps:
        action = str(step.get("action", ""))
        target = _mask(action, str(step.get("target", "")), reveal_typed)
        param = _mask(action, str(step.get("param", "")), reveal_typed)
        detail = []
        if step.get("error"):
            detail.append(f"<div class='err'>{e(str(step['error']))}</div>")
        heal = step.get("heal")
        if heal:
            detail.append(f"<div class='heal'>Self-healed by {e(str(heal.get('strategy', '')))} "
                          f"(confidence {float(heal.get('confidence', 0)):.0%}){': ' + e(str(heal.get('detail', ''))) if heal.get('detail') else ''}</div>")
        approval = step.get("approval")
        if approval:
            detail.append(f"<div class='appr'>{e(str(approval.get('decision', '')).capitalize())} by "
                          f"{e(str(approval.get('by', '')))} at {e(str(approval.get('at', '')))}</div>")
        shot = _rel(run_dir, str(step.get("evidence", "")))
        if shot:
            detail.append(f"<a href='{e(shot)}'><img src='{e(shot)}' alt='Step {e(str(step.get('index', '')))} screenshot'></a>")
        state = str(step.get("status", ""))
        rows.append("<tr class='s-{cls}'><td>{i}</td><td>{a}</td><td class='mono'>{t}</td><td class='mono'>{p}</td>"
                    "<td><span class='pill {cls}'>{s}</span></td><td>{ms}</td><td>{d}</td></tr>".format(
                        cls=e(state), i=e(str(step.get("index", ""))), a=e(action), t=e(target), p=e(param),
                        s=e(STATUS_LABEL.get(state, state.capitalize())),
                        ms=e(f"{int(step.get('ms', 0) or 0) / 1000:.1f}s"), d="".join(detail)))
    gallery = []
    for item in evidence:
        shot = _rel(run_dir, str(item.get("file", "")))
        if shot:
            gallery.append(f"<figure><a href='{e(shot)}'><img src='{e(shot)}' alt='{e(str(item.get('label', '')))}'></a>"
                           f"<figcaption>{e(str(item.get('label', '')))}<br><small>{e(str(item.get('at', '')))}"
                           f"{' · step ' + e(str(item.get('step'))) if item.get('step') else ''}</small></figcaption></figure>")
    title = f"{record.get('workflow', 'Workflow')} — run {record.get('run_id', '')}"
    page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>{e(title)}</title>
<style>
:root{{--bg:#f7f7f5;--card:#fff;--ink:#1d1d1f;--mute:#6b6b70;--line:#e3e3e0;--ok:#1f7a45;--bad:#b3261e;--warn:#9a6700;--heal:#5b3fb5}}
@media (prefers-color-scheme:dark){{:root{{--bg:#17171a;--card:#202024;--ink:#ececef;--mute:#a0a0a8;--line:#34343a;--ok:#5cc489;--bad:#ff8a80;--warn:#e3b341;--heal:#b49cff}}}}
body{{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 "Segoe UI",system-ui,sans-serif}}
main{{max-width:1100px;margin:0 auto;padding:24px 16px 48px}} h1{{font-size:22px;margin:0 0 4px}} .sub{{color:var(--mute)}}
.cards{{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin:20px 0}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px}} .card b{{display:block;font-size:20px}}
.ok{{color:var(--ok)}} .bad{{color:var(--bad)}} table{{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:10px;overflow:hidden}}
th,td{{text-align:left;vertical-align:top;padding:8px 10px;border-bottom:1px solid var(--line)}} th{{font-size:12px;color:var(--mute);font-weight:600}}
.mono{{font-family:Consolas,monospace;font-size:12px;word-break:break-word;max-width:240px}} .pill{{border-radius:99px;padding:1px 8px;font-size:12px;border:1px solid var(--line)}}
.pill.completed,.pill.approved,.pill.human{{color:var(--ok)}} .pill.failed,.pill.declined{{color:var(--bad)}} .pill.healed{{color:var(--heal)}} .pill.skipped{{color:var(--mute)}}
.err{{color:var(--bad)}} .heal{{color:var(--heal)}} .appr{{color:var(--warn)}} td img{{max-width:220px;border:1px solid var(--line);border-radius:6px;margin-top:6px}}
.gallery{{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:12px}} figure{{margin:0;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:8px}}
figure img{{width:100%;border-radius:6px}} figcaption{{font-size:13px;margin-top:4px}} .wrap{{overflow-x:auto}}
footer{{color:var(--mute);font-size:12px;margin-top:24px}}
</style></head><body><main>
<h1>{e(str(record.get('workflow', 'Workflow')))}</h1>
<div class="sub">{e(str(record.get('portal') or 'Workflow run'))} · started {e(str(record.get('started', '')))} · finished {e(str(record.get('finished', '')))} · run by {e(str(record.get('user', '')))} ({e(str(record.get('mode', '')))})</div>
<div class="cards">
<div class="card">Result<b class="{tone}">{e(status)}</b></div>
<div class="card">Steps completed<b>{e(str(record.get('completed', 0)))} / {len(steps)}</b></div>
<div class="card">Approvals<b>{len(approvals)}</b></div>
<div class="card">Self-heals<b>{heals}</b></div>
<div class="card">Evidence<b>{len(gallery)}</b></div>
</div>
{f"<p class='bad'>{e(str(record.get('error')))}</p>" if record.get('error') else ''}
<h2>Step timeline</h2><div class="wrap"><table><thead><tr><th>#</th><th>Action</th><th>Target</th><th>Value</th><th>Result</th><th>Time</th><th>Details</th></tr></thead>
<tbody>{''.join(rows) or '<tr><td colspan=7>No steps recorded.</td></tr>'}</tbody></table></div>
<h2>Evidence</h2><div class="gallery">{''.join(gallery) or '<p class="sub">No screenshots were captured.</p>'}</div>
<footer>Generated by Fan Autopilot on {e(datetime.now().strftime('%Y-%m-%d %H:%M'))}. Saved credentials are never written to this report; typed values are shortened unless revealed. Screenshots show what was on screen at the time.</footer>
</main></body></html>"""
    out = run_dir / "report.html"
    temp = out.with_suffix(".tmp")
    temp.write_text(page, encoding="utf-8")
    temp.replace(out)
    return {"ok": True, "report": str(out), "steps": len(steps), "evidence": len(gallery), "heals": heals,
            "approvals": len(approvals)}
