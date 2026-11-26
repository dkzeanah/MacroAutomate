"""Deterministic plain-English to workflow translation for common office phrasing.

This is the no-network path: it handles "open Excel, press ctrl+s, wait 2
seconds, click Save, ask me for the invoice number, repeat 3 times". Anything
it cannot map is returned as a question instead of being guessed.
"""
from __future__ import annotations

import re

APPS = {
    "excel": ("Run Program", "excel.exe", "ahk_exe EXCEL.EXE"),
    "word": ("Run Program", "winword.exe", "ahk_exe WINWORD.EXE"),
    "outlook": ("Run Program", "outlook.exe", "ahk_exe OUTLOOK.EXE"),
    "powerpoint": ("Run Program", "powerpnt.exe", "ahk_exe POWERPNT.EXE"),
    "notepad": ("Run Program", "notepad.exe", "ahk_exe notepad.exe"),
    "chrome": ("Run Program", "chrome.exe", "ahk_exe chrome.exe"),
    "edge": ("Run Program", "msedge.exe", "ahk_exe msedge.exe"),
    "calculator": ("Run Program", "calc.exe", "Calculator"),
    "file explorer": ("Run Program", "explorer.exe", "ahk_class CabinetWClass"),
    "explorer": ("Run Program", "explorer.exe", "ahk_class CabinetWClass"),
    "teams": ("Run Program", "ms-teams:", "Microsoft Teams"),
}
KEY_NAMES = {
    "enter": "{Enter}", "return": "{Enter}", "tab": "{Tab}", "escape": "{Esc}", "esc": "{Esc}",
    "space": "{Space}", "backspace": "{Backspace}", "delete": "{Delete}", "del": "{Delete}",
    "home": "{Home}", "end": "{End}", "page up": "{PgUp}", "pgup": "{PgUp}", "page down": "{PgDn}",
    "pgdn": "{PgDn}", "up": "{Up}", "down": "{Down}", "left": "{Left}", "right": "{Right}",
    "up arrow": "{Up}", "down arrow": "{Down}", "left arrow": "{Left}", "right arrow": "{Right}",
    "insert": "{Insert}", "print screen": "{PrintScreen}",
}
MODIFIERS = {"ctrl": "^", "control": "^", "shift": "+", "alt": "!", "win": "#", "windows": "#"}
SPLIT = re.compile(r"(?:\r?\n|;|\.\s+(?=[A-Z])|,?\s+and then\s+|,?\s+then\s+|,\s*after that\s+|,?\s+and\s+(?=(?:press|hit|click|wait|open|switch|paste|copy|save|ask|scroll|repeat|take|capture|notify|run)\b)|,\s+(?=(?:open|launch|start|go|switch|type|enter|press|hit|wait|click|double|right|copy|paste|save|ask|scroll|repeat|notify|tell|show|log|sign|take|capture|select|run|approve)\b))", re.I)
QUOTED = re.compile(r"^[\"'“‘](.*)[\"'”’]$")
URL = re.compile(r"^(https?://\S+|www\.\S+|[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|org|net|gov|edu|io|co|us|biz|info)(?:/\S*)?)$", re.I)
NUMBER_WORDS = {"once": 1, "twice": 2, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                "seven": 7, "eight": 8, "nine": 9, "ten": 10}


def _unquote(text: str) -> str:
    text = text.strip().rstrip(".!")
    match = QUOTED.match(text)
    return match.group(1) if match else text


def _count(text: str) -> int | None:
    text = text.strip().lower()
    if text.isdigit():
        return int(text)
    return NUMBER_WORDS.get(text)


def key_sequence(phrase: str) -> str | None:
    """'ctrl+shift+s' -> '^+s', 'enter' -> '{Enter}', 'tab 3 times' -> '{Tab 3}'."""
    phrase = phrase.strip().lower().rstrip(".")
    phrase = re.sub(r"\s+key$", "", phrase)
    repeat = re.match(r"^(.*?)\s+(\d+|once|twice|two|three|four|five|six|seven|eight|nine|ten)\s+times?$", phrase)
    times = 1
    if repeat:
        phrase, times = repeat.group(1), _count(repeat.group(2)) or 1
    tokens = [t for t in re.split(r"[\s+]+|(?<=\w)-(?=\w)", phrase) if t]
    if not tokens:
        return None
    prefix = ""
    while len(tokens) > 1 and tokens[0] in MODIFIERS:
        prefix += MODIFIERS[tokens.pop(0)]
    last = " ".join(tokens)
    if any(t in MODIFIERS for t in tokens) and last not in KEY_NAMES:
        return None
    if last in KEY_NAMES:
        name = KEY_NAMES[last]
        return prefix + (name if times == 1 else name[:-1] + f" {times}}}")
    if re.fullmatch(r"f(?:[1-9]|1[0-9]|2[0-4])", last):
        return prefix + (f"{{{last.upper()}}}" if times == 1 else f"{{{last.upper()} {times}}}")
    if len(last) == 1 and (prefix or last.isalnum()):
        return (prefix + last) * times if prefix else f"{{{last} {times}}}" if times > 1 else last
    return None


def _camel(text: str) -> str:
    words = re.findall(r"[A-Za-z0-9]+", text)
    if not words:
        return "value"
    name = words[0].lower() + "".join(w.capitalize() for w in words[1:4])
    return ("v" + name) if name[0].isdigit() else name[:40]


def _target_for_click(label: str, context: dict) -> dict:
    def has(kind):
        return label in (context.get(kind) or [])
    if has("elements"):
        return {"action": "Click Element", "target": label, "param": "Left"}
    if has("patterns"):
        return {"action": "Find & Click", "target": label, "param": ""}
    if has("coordinates"):
        return {"action": "Click", "target": label, "param": "1"}
    return {"action": "OCR Click", "target": "window:A", "param": label}


def compile_text(description: str, context: dict | None = None) -> dict:
    context = context or {}
    clauses = [c.strip(" ,.") for c in SPLIT.split(description or "") if c and c.strip(" ,.")]
    steps: list[dict] = []
    questions: list[str] = []
    assumptions: list[str] = []
    loop_wrap: tuple[str, int] | None = None  # ("before"|"after", count)
    for clause in clauses:
        lowered = clause.lower()
        produced = _clause(clause, lowered, context, assumptions)
        if produced == "LOOP":
            match = re.search(r"(\d+|once|twice|two|three|four|five|six|seven|eight|nine|ten)\s+times", lowered)
            count = _count(match.group(1)) if match else None
            if not count:
                questions.append(f"How many times should it repeat? ('{clause}')")
                continue
            loop_wrap = ("before" if not steps else "after", count)
            if loop_wrap[0] == "before":
                steps.append({"action": "Loop Start", "target": "", "param": f"count={count}; var=i", "enabled": True,
                              "note": "Repeats the steps before it"})
            continue
        if produced is None:
            questions.append(f"I couldn't turn this into a step: '{clause}'. Rephrase it or add the step by hand.")
            continue
        for step in produced:
            step.setdefault("enabled", True)
            steps.append(step)
    if loop_wrap:
        if loop_wrap[0] == "after":
            steps.insert(0, {"action": "Loop Start", "target": "", "param": f"count={loop_wrap[1]}; var=i",
                             "enabled": True, "note": "Repeats every step below"})
        steps.append({"action": "Loop End", "target": "", "param": "", "enabled": True, "note": "End of the repeated steps"})
    name = _name(description)
    return {"name": name, "summary": f"Offline draft from {len(clauses)} phrase(s)", "steps": steps,
            "assumptions": assumptions, "questions": questions}


def _name(description: str) -> str:
    first = re.split(r"[.\n;,]", (description or "").strip(), 1)[0]
    words = re.findall(r"[A-Za-z0-9']+", first)[:7]
    return (" ".join(words).capitalize() or "New workflow")[:60]


def _clause(clause: str, lowered: str, context: dict, assumptions: list[str]):
    if re.match(r"^(?:repeat|do (?:this|that|it|all of this))\b", lowered) or re.fullmatch(r"(?:\d+|twice|three|four|five) times", lowered):
        return "LOOP"
    match = re.match(r"^(?:open|launch|start|go to|visit|browse to|navigate to)\s+(?:the\s+)?(?:website\s+|site\s+|page\s+|url\s+)?(.+)$", lowered)
    if match:
        target = _unquote(clause[clause.lower().index(match.group(1)):])
        if URL.match(target):
            url = target if target.lower().startswith("http") else "https://" + target
            return [{"action": "Open Page", "target": "", "param": f"url={url}; timeout=20000", "note": "Opens the page in your browser"}]
        app = APPS.get(target.lower().removesuffix(" app"))
        if app:
            return [{"action": "Run Program", "target": "", "param": app[1], "note": f"Starts {target}"},
                    {"action": "Wait for Window", "target": "", "param": f"title={app[2]}; timeout=15000"}]
        return [{"action": "Activate Window", "target": "", "param": target, "note": "Switches to an open window with this title"}]
    match = re.match(r"^(?:switch to|activate|focus(?: on)?|bring up|go back to)\s+(?:the\s+)?(.+?)(?:\s+window)?$", lowered)
    if match:
        target = _unquote(clause[clause.lower().index(match.group(1)):][:len(match.group(1))])
        app = APPS.get(target.lower())
        return [{"action": "Activate Window", "target": "", "param": app[2] if app else target}]
    match = re.match(r"^(?:type|enter|fill in) (?:in )?(?:my|the) (username|user name|email|login|password)(?: for| into| on| to)? (.+)$", lowered)
    if match:
        field = "password" if "pass" in match.group(1) else "username"
        portal = _unquote(clause[clause.lower().rindex(match.group(2)):]).strip()
        assumptions.append(f"Uses the saved '{portal}' credential from Autopilot > Portals.")
        return [{"action": "Type Credential", "target": portal[:60], "param": field}]
    match = re.match(r"^(?:type|enter|write|fill in)\s+(.+)$", lowered)
    if match:
        if re.search(r"\b(?:my|the) (?:password|username|user name)\b", lowered):
            return None  # never type a secret literally; ask which saved credential to use
        text = _unquote(clause[clause.lower().index(match.group(1)):])
        var = re.fullmatch(r"(?:the\s+)?(?:value|text|answer) (?:i|you) (?:gave|entered|asked for)(?: for)? (.+)", text, re.I)
        if var:
            return [{"action": "Type Text", "target": "", "param": f"$var.{_camel(var.group(1))}"}]
        return [{"action": "Type Text", "target": "", "param": text}]
    match = re.match(r"^(?:press|hit|send|use)\s+(?:the\s+)?(.+?)(?:\s+key)?(?:\s+shortcut)?$", lowered)
    if match:
        keys = key_sequence(match.group(1))
        if keys:
            return [{"action": "Send Keys", "target": "", "param": keys}]
        return None
    match = re.match(r"^(?:wait|pause|sleep)(?: for)?\s+(\d+(?:\.\d+)?)\s*(ms|milliseconds?|s|secs?|seconds?|m|mins?|minutes?)?$", lowered)
    if match:
        amount = float(match.group(1))
        unit = (match.group(2) or "s").lower()
        ms = amount if unit.startswith("ms") or unit.startswith("milli") else amount * 60000 if unit.startswith("m") else amount * 1000
        return [{"action": "Wait", "target": "", "param": str(int(min(600000, ms)))}]
    match = re.match(r"^wait (?:for|until) (?:the\s+)?(.+?)(?:\s+window)?\s+(?:to\s+)?(?:appear|appears|open|opens|show|shows|load|loads)$", lowered)
    if match:
        title = _unquote(clause[clause.lower().index(match.group(1)):][:len(match.group(1))])
        return [{"action": "Wait for Window", "target": "", "param": f"title={title}; timeout=15000"}]
    match = re.match(r"^wait (?:for|until) (?:the\s+)?(?:text\s+)?[\"'“](.+)[\"'”](?:\s+(?:appears|shows|is shown))?$", clause, re.I)
    if match:
        return [{"action": "OCR Wait", "target": "window:A", "param": f"text:{match.group(1)},15000"}]
    match = re.match(r"^(double[- ]click|right[- ]click|click)\s+(?:on\s+)?(?:the\s+)?(.+?)(?:\s+(?:button|link|tab|menu|icon|field|box))?$", lowered)
    if match:
        label = _unquote(clause[clause.lower().index(match.group(2)):][:len(match.group(2))])
        step = _target_for_click(label, context)
        kind = match.group(1).replace(" ", "-")
        if kind != "click":
            if step["action"] == "Click":
                step["action"] = "Double Click" if kind.startswith("double") else "Right Click"
                step["param"] = ""
            elif step["action"] == "Find & Click":
                step["action"] = "Find & DblClick" if kind.startswith("double") else "Find & RClick"
            elif step["action"] == "Click Element":
                step["param"] = "Right" if kind.startswith("right") else "Left,2"
            else:
                assumptions.append(f"'{label}' is found by its visible text and clicked once; adjust to {kind} if needed.")
        if step["action"] == "OCR Click":
            step["note"] = "Finds the visible text in the active window"
        return [step]
    simple = {"copy": "^c", "copy it": "^c", "copy that": "^c", "copy the selection": "^c", "select all": "^a",
              "save": "^s", "save it": "^s", "save the file": "^s", "undo": "^z", "print": "^p", "new tab": "^t",
              "refresh": "{F5}", "reload": "{F5}", "find": "^f", "cut": "^x"}
    if lowered in simple:
        return [{"action": "Send Keys", "target": "", "param": simple[lowered]}]
    if lowered in ("paste", "paste it", "paste that"):
        return [{"action": "Paste", "target": "", "param": ""}]
    if lowered in ("close it", "close the window", "close window", "close the tab"):
        return [{"action": "Send Keys", "target": "", "param": "^w" if "tab" in lowered else "!{F4}"}]
    match = re.match(r"^(?:ask|prompt)(?: me)? for (?:the\s+|a\s+|an\s+)?(.+)$", lowered)
    if match:
        label = clause[clause.lower().index(match.group(1)):].strip()
        return [{"action": "Ask Input", "target": _camel(label), "param": f"{label[:1].upper()}{label[1:]}?"}]
    match = re.match(r"^scroll\s+(up|down)(?:\s+(\d+))?(?:\s+times)?$", lowered)
    if match:
        amount = int(match.group(2) or 5)
        return [{"action": "Scroll", "target": "", "param": str(amount if match.group(1) == "up" else -amount)}]
    if re.match(r"^(?:take a screenshot|screenshot|capture (?:evidence|the screen|a screenshot|proof))", lowered):
        label = re.sub(r"^(?:take a screenshot|screenshot|capture (?:evidence|the screen|a screenshot|proof))(?:\s+of)?\s*", "", clause, flags=re.I)
        return [{"action": "Capture Evidence", "target": "window:A", "param": label or "Screenshot"}]
    if re.match(r"^(?:ask (?:me )?for approval|get (?:my )?approval|confirm with me|check with me|let me approve)", lowered):
        return [{"action": "Approval Gate", "target": "", "param": "Continue with the next step?"}]
    match = re.match(r"^(?:notify|tell|show)(?: me)?\s+(?:that\s+|when\s+)?(.+)$", lowered)
    if match:
        message = clause[clause.lower().index(match.group(1)):].replace(",", " ")
        return [{"action": "Show Notification", "target": "", "param": f"Fan,{message},4"}]
    match = re.match(r"^run (?:the\s+)?(?:workflow|sequence|routine|macro)\s+(.+)$", lowered)
    if match:
        return [{"action": "Run Sequence", "target": "", "param": _unquote(clause[clause.lower().index(match.group(1)):])}]
    match = re.match(r"^(?:log ?in|sign ?in)(?: to)?\s+(.+)$", lowered)
    if match:
        portal = _unquote(clause[clause.lower().index(match.group(1)):])
        login = f"{portal} login"
        if login in (context.get("workflows") or []):
            return [{"action": "Run Sequence", "target": "", "param": login}]
        assumptions.append(f"Create the '{portal}' portal under Autopilot > Portals to get a login workflow.")
        return [{"action": "Type Credential", "target": portal[:60], "param": "username"},
                {"action": "Send Keys", "target": "", "param": "{Tab}"},
                {"action": "Type Credential", "target": portal[:60], "param": "password"},
                {"action": "Send Keys", "target": "", "param": "{Enter}"},
                {"action": "Human Check", "target": "window:A", "param": "on=pause"}]
    return None
