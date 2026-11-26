"""Discover repeated work in the local usage log and draft a workflow for it.

Input is the Usage Predictor's ``usage_event`` stream (app switches, physical
clicks, shortcut keys and typing bursts), read-only. The miner looks for the
longest contiguous action sequences that recur, discards ones that are only
window ping-pong, measures how long each occurrence actually took, and turns a
routine into reviewable workflow steps. Nothing here sends data anywhere.

Counts and minutes are observations from the recorded window. Extrapolation to
"per week" is only reported once at least a week of history exists.
"""
from __future__ import annotations

import hashlib
import json
import sqlite3
from collections import Counter, defaultdict
from contextlib import closing
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path
from statistics import median

FRIENDLY_APPS = {
    "excel": "Excel", "winword": "Word", "outlook": "Outlook", "olk": "Outlook", "powerpnt": "PowerPoint",
    "chrome": "Chrome", "msedge": "Edge", "firefox": "Firefox", "explorer": "File Explorer",
    "notepad": "Notepad", "teams": "Teams", "ms-teams": "Teams", "acrobat": "Acrobat", "acrord32": "Acrobat",
    "qbw": "QuickBooks", "qbw32": "QuickBooks", "slack": "Slack", "zoom": "Zoom", "code": "VS Code",
    "windowsterminal": "Terminal", "calc": "Calculator", "calculatorapp": "Calculator", "onenote": "OneNote",
}
# System surfaces that are part of switching, not part of anybody's work.
NOISE_EXES = {"shellexperiencehost", "searchhost", "startmenuexperiencehost", "lockapp", "textinputhost",
              "applicationframehost", "systemsettings", "taskmgr", "shellhost"}
ACTION_KINDS = {"CLICK", "KEY", "TYPE"}
MAX_EVENT_GAP_MS = 30000


@dataclass
class Event:
    id: int
    ts: datetime
    kind: str
    token: str
    data: dict
    app_id: int = 0
    win_id: int = 0
    sig: str = ""

    @property
    def exe(self) -> str:
        exe = str(self.data.get("exe", "")).lower()
        return exe[:-4] if exe.endswith(".exe") else exe


@dataclass
class Routine:
    sigs: tuple
    occurrences: list = field(default_factory=list)  # list[list[Event]]

    @property
    def id(self) -> str:
        # The "r" prefix keeps the id textual in SQLite even when the digest is all digits.
        return "r" + hashlib.sha1("\x1f".join(self.sigs).encode()).hexdigest()[:15]


def signature(event: Event) -> str:
    """A context-qualified identity stable across repetitions of the same work."""
    exe = event.exe or "?"
    if event.kind == "APP":
        return f"APP:{exe}:{event.data.get('class', '')}"
    if event.kind == "CLICK":
        rest = event.token.split(":", 1)[1] if ":" in event.token else event.token
        return f"CLICK:{exe}:{rest}"
    if event.kind == "KEY":
        return f"KEY:{exe}:{event.data.get('send') or event.token[4:]}"
    if event.kind == "TYPE":
        return f"TYPE:{exe}:{event.data.get('shape', 'text')}"
    return f"{event.kind}:{exe}:{event.token}"


def load_events(db_path: str | Path, lookback_days: int = 30, now: datetime | None = None,
                limit: int = 60000) -> list[Event]:
    now = now or datetime.now()
    since = (now - timedelta(days=lookback_days)).strftime("%Y-%m-%d %H:%M:%S")
    uri = Path(db_path).resolve().as_uri() + "?mode=ro"
    with closing(sqlite3.connect(uri, uri=True, timeout=10)) as db:
        db.row_factory = sqlite3.Row
        if not db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='usage_event'").fetchone():
            return []
        rows = db.execute("SELECT id, ts, kind, token, data, app_id, win_id FROM usage_event "
                          "WHERE automated=0 AND ts>=? ORDER BY id DESC LIMIT ?", (since, limit)).fetchall()
    events = []
    for row in reversed(rows):
        event = _event(row["id"], row["ts"], row["kind"], row["token"], row["data"], row["app_id"], row["win_id"])
        if event:
            events.append(event)
    return carry_context(events)


def carry_context(events: list[Event]) -> list[Event]:
    """Typing bursts are flushed without window details; inherit the app they were typed in."""
    last_exe, kept = "", []
    for event in events:
        if event.kind == "TYPE" and int(event.data.get("length", 2) or 0) <= 1:
            continue  # a lone keystroke is a shortcut fragment, not data entry
        if event.data.get("exe"):
            last_exe = str(event.data["exe"])
        elif last_exe:
            event.data["exe"] = last_exe
            event.sig = signature(event)
        kept.append(event)
    return kept


def _event(event_id, ts, kind, token, data, app_id=0, win_id=0) -> Event | None:
    try:
        when = datetime.strptime(str(ts)[:19], "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None
    try:
        payload = json.loads(data) if isinstance(data, str) else dict(data or {})
    except (ValueError, TypeError):
        payload = {}
    event = Event(int(event_id), when, str(kind or ""), str(token or ""), payload, int(app_id or 0), int(win_id or 0))
    event.sig = signature(event)
    return event


def events_from_dicts(items: list[dict]) -> list[Event]:
    """Test/fixture entry point using the same normalization as the database path."""
    events = []
    for index, item in enumerate(items, 1):
        event = _event(item.get("id", index), item["ts"], item["kind"], item.get("token", ""),
                       item.get("data", {}), item.get("app_id", 0), item.get("win_id", 0))
        if event:
            events.append(event)
    return carry_context(events)


def sessionize(events: list[Event], gap_minutes: int = 15) -> list[list[Event]]:
    sessions, current, previous = [], [], None
    for event in events:
        if event.kind == "APP" and event.exe in NOISE_EXES:
            continue
        if previous and (event.ts - previous.ts) > timedelta(minutes=gap_minutes):
            if current:
                sessions.append(current)
            current = []
        # Collapse consecutive duplicate app activations (re-focus of the same window).
        if current and event.kind == "APP" and current[-1].kind == "APP" and current[-1].sig == event.sig:
            previous = event
            continue
        current.append(event)
        previous = event
    if current:
        sessions.append(current)
    return sessions


def _interesting(sigs: tuple, min_actions: int) -> bool:
    kinds = [s.split(":", 1)[0] for s in sigs]
    if sum(k in ACTION_KINDS for k in kinds) < min_actions:
        return False
    if len(set(sigs)) < 3:
        return False
    # ABAB / AAAA (period 1 or 2) is switching or key-repeat, not a routine.
    for period in (1, 2):
        if len(sigs) > period and all(sigs[i] == sigs[i % period] for i in range(len(sigs))):
            return False
    return True


def _tight(sigs: tuple) -> bool:
    """A routine starts in the window where work begins and ends on the last action.

    Leading window switches before that window, and trailing switches after the
    last action, are incidental; the trimmed sequence is found at a shorter length.
    """
    kinds = [s.split(":", 1)[0] for s in sigs]
    if kinds[-1] not in ACTION_KINDS:
        return False
    first_action = next(i for i, k in enumerate(kinds) if k in ACTION_KINDS)
    if first_action == 0:
        return True
    return first_action == 1 and kinds[0] == "APP"


def mine(events: list[Event], *, min_len: int = 3, max_len: int = 24, min_occurrences: int = 3,
         min_actions: int = 2, gap_minutes: int = 15, max_span_minutes: int = 45,
         min_avg_seconds: float = 4.0, excluded: set[str] | None = None, limit: int = 25) -> list[Routine]:
    """Maximal repeated contiguous sequences, longest first, without double counting."""
    sessions = sessionize(events, gap_minutes)
    excluded = excluded or set()
    accepted: list[Routine] = []
    covered: dict[int, set[int]] = defaultdict(set)  # session -> covered positions
    span_limit = timedelta(minutes=max_span_minutes)

    for length in range(max_len, min_len - 1, -1):
        windows: dict[tuple, list[tuple[int, int]]] = defaultdict(list)
        for s_index, session in enumerate(sessions):
            sigs = [e.sig for e in session]
            for start in range(len(sigs) - length + 1):
                windows[tuple(sigs[start:start + length])].append((s_index, start))
        for key, positions in windows.items():
            if len(positions) < min_occurrences or not _interesting(key, min_actions) or not _tight(key):
                continue
            chosen, last_end = [], {}
            for s_index, start in positions:  # already ordered by session, then position
                if start < last_end.get(s_index, -1):
                    continue  # overlaps the previous occurrence in this session
                span = range(start, start + length)
                if sum(p in covered[s_index] for p in span) * 2 > length:
                    continue  # mostly inside a longer accepted routine
                occurrence = sessions[s_index][start:start + length]
                if occurrence[-1].ts - occurrence[0].ts > span_limit:
                    continue
                chosen.append((s_index, start))
                last_end[s_index] = start + length
            if len(chosen) < min_occurrences:
                continue
            routine = Routine(key, [sessions[s][p:p + length] for s, p in chosen])
            if _mean([_duration_ms(o) for o in routine.occurrences]) < min_avg_seconds * 1000:
                continue  # too quick to be worth automating
            for s_index, start in chosen:
                covered[s_index].update(range(start, start + length))
            # A dismissed routine still claims its events, so its fragments do not resurface.
            if routine.id not in excluded:
                accepted.append(routine)
    accepted.sort(key=lambda r: _score(r), reverse=True)
    return accepted[:limit]


def _duration_ms(occurrence: list[Event]) -> int:
    total = 0
    for event in occurrence[1:]:
        try:
            total += min(MAX_EVENT_GAP_MS, max(0, int(event.data.get("delay_ms", 0))))
        except (TypeError, ValueError):
            pass
    last = occurrence[-1]
    if last.kind == "TYPE":
        try:
            total += min(MAX_EVENT_GAP_MS, int(last.data.get("duration_ms", 0)))
        except (TypeError, ValueError):
            pass
    return total


def _score(routine: Routine) -> float:
    total_ms = sum(_duration_ms(o) for o in routine.occurrences)
    days = len({o[0].ts.date() for o in routine.occurrences})
    return total_ms / 60000 + len(routine.occurrences) * 0.5 + days * 0.75 + len(routine.sigs) * 0.1


def schedule_hint(starts: list[datetime]) -> dict:
    if len(starts) < 3:
        return {"text": "", "weekday": None, "hour": None}
    weekdays = Counter(s.strftime("%A") for s in starts)
    day, day_count = weekdays.most_common(1)[0]
    hours = Counter(s.hour for s in starts)
    best_hour = hours.most_common(1)[0][0]
    best_count = hours[best_hour] + max(hours[(best_hour - 1) % 24], hours[(best_hour + 1) % 24])
    distinct_days = {s.date() for s in starts}
    parts, weekday, hour = [], None, None
    if day_count / len(starts) >= 0.6 and len(distinct_days) >= 2:
        parts.append(f"usually on {day}s")
        weekday = day
    elif len(distinct_days) >= 4 and sum(1 for d in distinct_days if d.weekday() < 5) / len(distinct_days) >= 0.8:
        parts.append("most weekdays")
        weekday = "weekdays"
    if best_count / len(starts) >= 0.6:
        hour = best_hour
        label = datetime(2000, 1, 1, best_hour).strftime("%I %p").lstrip("0")
        parts.append(f"around {label}")
    return {"text": " ".join(parts), "weekday": weekday, "hour": hour}


def friendly_app(exe: str) -> str:
    exe = (exe or "").lower()
    return FRIENDLY_APPS.get(exe, exe[:1].upper() + exe[1:] if exe else "an app")


def routine_name(routine: Routine) -> str:
    first = routine.occurrences[0]
    apps = []
    for event in first:
        app = friendly_app(event.exe)
        if event.exe and (not apps or apps[-1] != app):
            apps.append(app)
    keys = [e.data.get("send", "") for e in first if e.kind == "KEY"]
    copy_from = paste_into = ""
    for event in first:
        if event.kind == "KEY" and event.data.get("send") == "^c" and not copy_from:
            copy_from = friendly_app(event.exe)
        if event.kind == "KEY" and event.data.get("send") == "^v" and copy_from:
            paste_into = friendly_app(event.exe)
    if copy_from and paste_into and copy_from != paste_into:
        return f"Copy from {copy_from} into {paste_into}"
    unique = list(dict.fromkeys(apps))
    if len(unique) >= 2:
        return " → ".join(unique[:3]) + " routine"
    if "^s" in keys:
        return f"Edit and save in {unique[0] if unique else 'an app'}"
    return f"{unique[0] if unique else 'Desktop'} routine"


def _window_target(events: list[Event]) -> str:
    titles = {str(e.data.get("title", "")) for e in events}
    exe = events[0].exe
    if len(titles) == 1 and next(iter(titles)):
        return next(iter(titles))[:120]
    return f"ahk_exe {exe}.exe" if exe else (next(iter(titles), "") or "")[:120]


def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def draft_steps(routine: Routine, element_names: dict[int, str] | None = None,
                usage_elements: dict[int, dict] | None = None) -> tuple[list[dict], list[dict]]:
    """Workflow steps for one routine, plus the inputs a person must supply."""
    element_names = element_names or {}
    usage_elements = usage_elements or {}
    steps: list[dict] = []
    inputs: list[dict] = []
    current_window = ""
    for position in range(len(routine.sigs)):
        column = [occ[position] for occ in routine.occurrences]
        sample = column[0]
        delays = [int(e.data.get("delay_ms", 0) or 0) for e in column]
        pause = int(median(delays)) if delays else 0
        if position and pause > 900:
            steps.append({"action": "Wait", "target": "", "param": str(min(4000, max(300, pause // 2))),
                          "enabled": True, "note": f"You usually paused ~{pause / 1000:.1f}s here"})
        if sample.kind == "APP":
            current_window = _window_target(column)
            steps.append({"action": "Activate Window", "target": "", "param": current_window, "enabled": True,
                          "note": f"Switch to {friendly_app(sample.exe)}"})
            steps.append({"action": "Wait", "target": "", "param": "300", "enabled": True, "note": "Let the window settle"})
        elif sample.kind == "CLICK":
            steps.append(_click_step(column, element_names, usage_elements, current_window))
        elif sample.kind == "KEY":
            steps.append({"action": "Send Keys", "target": "", "param": str(sample.data.get("send", "")),
                          "enabled": True, "note": f"Shortcut in {friendly_app(sample.exe)}"})
        elif sample.kind == "TYPE":
            literals = [str(e.data.get("text", "")) for e in column]
            if all(literals) and len(set(literals)) == 1:
                steps.append({"action": "Type Text", "target": "", "param": literals[0], "enabled": True,
                              "note": "Same text every time"})
            else:
                name = f"input{len(inputs) + 1}"
                lengths = [int(e.data.get("length", 0) or 0) for e in column]
                shape = sample.data.get("shape", "text")
                hint = f"{shape}, about {int(_mean(lengths))} characters" if lengths else shape
                examples = [t for t in dict.fromkeys(literals) if t][:3]
                inputs.append({"var": name, "hint": hint, "examples": examples})
                prompt = f"Value to type in {friendly_app(sample.exe)} ({hint})"
                steps.insert(_first_step_index(steps), {"action": "Ask Input", "target": name, "param": prompt,
                                                        "enabled": True, "note": "This text changed between repetitions"})
                steps.append({"action": "Type Text", "target": "", "param": f"$var.{name}", "enabled": True,
                              "note": "Types the value you supply when the workflow starts"})
    steps.append({"action": "Show Notification", "target": "", "param": f"Fan,{routine_name(routine)} done,3",
                  "enabled": True, "note": "Confirms completion"})
    return steps, inputs


def _first_step_index(steps: list[dict]) -> int:
    """Ask for every input up front so the run is not interrupted mid-way."""
    index = 0
    while index < len(steps) and steps[index]["action"] == "Ask Input":
        index += 1
    return index


def _click_step(column: list[Event], element_names: dict[int, str], usage_elements: dict[int, dict],
                window: str) -> dict:
    sample = column[0]
    button = str(sample.data.get("button", "Left"))
    element_id = int(sample.data.get("element_id", 0) or 0)
    same_element = element_id and all(int(e.data.get("element_id", 0) or 0) == element_id for e in column)
    if same_element:
        registry_id = int(usage_elements.get(element_id, {}).get("element_id", 0) or 0)
        name = element_names.get(registry_id, "")
        if name:
            return {"action": "Click Element", "target": name, "param": button, "enabled": True,
                    "note": "Learned element (pattern + window position)"}
        info = usage_elements.get(element_id)
        if info and info.get("rel_w") is not None:
            rx = float(info["rel_x"]) + float(info["rel_w"]) / 2
            ry = float(info["rel_y"]) + float(info["rel_h"]) / 2
            return _winrel_step(button, window or f"ahk_exe {sample.exe}.exe", rx, ry, "Learned screen region")
    rel_x = [float(e.data.get("rel_x", 0) or 0) for e in column]
    rel_y = [float(e.data.get("rel_y", 0) or 0) for e in column]
    return _winrel_step(button, window or f"ahk_exe {sample.exe}.exe", median(rel_x), median(rel_y),
                        "Position inside the window (self-heal re-finds it if the layout moves)")


def _winrel_step(button: str, window: str, rx: float, ry: float, note: str) -> dict:
    action = "Right Click" if button.lower().startswith("r") else "Click"
    rx = min(1.0, max(0.0, rx))
    ry = min(1.0, max(0.0, ry))
    return {"action": action, "target": f"winrel:{window.replace('|', ' ')}|{rx:.4f},{ry:.4f}", "param": "",
            "enabled": True, "note": note}


def load_element_maps(db_path: str | Path) -> tuple[dict[int, str], dict[int, dict]]:
    uri = Path(db_path).resolve().as_uri() + "?mode=ro"
    names, usage = {}, {}
    try:
        with closing(sqlite3.connect(uri, uri=True, timeout=10)) as db:
            db.row_factory = sqlite3.Row
            tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            if "element" in tables:
                names = {int(r["id"]): str(r["name"]) for r in db.execute("SELECT id, name FROM element WHERE name<>''")}
            if "usage_element" in tables:
                usage = {int(r["id"]): dict(r) for r in db.execute(
                    "SELECT id, element_id, rel_x, rel_y, rel_w, rel_h, name FROM usage_element")}
    except sqlite3.Error:
        pass
    return names, usage


def describe(routine: Routine, *, now: datetime, observed_days: float, element_names=None,
             usage_elements=None) -> dict:
    starts = [o[0].ts for o in routine.occurrences]
    durations = [_duration_ms(o) for o in routine.occurrences]
    total_minutes = sum(durations) / 60000
    week_ago = now - timedelta(days=7)
    recent = [s for s in starts if s >= week_ago]
    apps = list(dict.fromkeys(friendly_app(e.exe) for e in routine.occurrences[0] if e.exe))
    steps, inputs = draft_steps(routine, element_names, usage_elements)
    per_week = None
    if observed_days >= 7:
        per_week = round(total_minutes / (observed_days / 7), 1)
    sessions = len({(o[0].ts.date(), o[0].ts.hour) for o in routine.occurrences})
    confidence = min(0.99, 0.35 + 0.08 * len(starts) + 0.05 * len({s.date() for s in starts}))
    return {
        "id": routine.id,
        "name": routine_name(routine),
        "occurrences": len(starts),
        "occurrences_last_7_days": len(recent),
        "distinct_days": len({s.date() for s in starts}),
        "sessions": sessions,
        "length": len(routine.sigs),
        "apps": apps,
        "avg_seconds": round(_mean(durations) / 1000, 1),
        "minutes_observed": round(total_minutes, 1),
        "minutes_last_7_days": round(sum(d for s, d in zip(starts, durations) if s >= week_ago) / 60000, 1),
        "minutes_per_week": per_week,
        "per_week_basis": "measured" if per_week is not None else f"only {observed_days:.1f} days of history",
        "first_seen": min(starts).strftime("%Y-%m-%d %H:%M"),
        "last_seen": max(starts).strftime("%Y-%m-%d %H:%M"),
        "schedule": schedule_hint(starts),
        "confidence": round(confidence, 2),
        "signature": list(routine.sigs),
        "steps": steps,
        "inputs": inputs,
        "evidence": [{"start": o[0].ts.strftime("%Y-%m-%d %H:%M:%S"), "first_event": o[0].id, "last_event": o[-1].id,
                      "seconds": round(_duration_ms(o) / 1000, 1)} for o in routine.occurrences[:8]],
    }


def find_routines(db_path: str | Path, *, lookback_days: int = 30, now: datetime | None = None,
                  excluded: list[str] | None = None, min_occurrences: int = 3, limit: int = 25) -> dict:
    now = now or datetime.now()
    events = load_events(db_path, lookback_days, now)
    element_names, usage_elements = load_element_maps(db_path)
    return analyze(events, now=now, excluded=excluded, min_occurrences=min_occurrences, limit=limit,
                   element_names=element_names, usage_elements=usage_elements)


def analyze(events: list[Event], *, now: datetime, excluded=None, min_occurrences: int = 3, limit: int = 25,
            element_names=None, usage_elements=None) -> dict:
    observed_days = 0.0
    if events:
        observed_days = max(0.04, (max(e.ts for e in events) - min(e.ts for e in events)).total_seconds() / 86400)
    routines = mine(events, min_occurrences=min_occurrences, excluded=set(excluded or []), limit=limit)
    described = [describe(r, now=now, observed_days=observed_days, element_names=element_names,
                          usage_elements=usage_elements) for r in routines]
    return {"ok": True, "events_analyzed": len(events), "observed_days": round(observed_days, 2),
            "routines": described,
            "note": "Counts and minutes are measured from the local usage log. Review every step before running it."}
