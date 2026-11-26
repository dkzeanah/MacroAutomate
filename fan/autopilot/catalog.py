"""Workflow action catalog, step validation and risk analysis.

The authoritative action list and field specs come from the running
application (``GetWorkflowActionNames`` / ``GetWorkflowActionSpec``), passed in
each request. This module adds the format checks and reference checks the
engine would otherwise only discover while sending real input, so a generated
or mined workflow is rejected before it can touch the desktop.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from urllib.parse import urlparse

MAX_STEPS = 300
MAX_FIELD = 2000
VAR_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
CRED_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 _.\-]{0,59}$")
VAR_REF = re.compile(r"\$var\.(\w+)")
POINT = re.compile(r"^\s*-?\d+\s*,\s*-?\d+\s*$")
RECT = re.compile(r"^\s*-?\d+\s*,\s*-?\d+\s*,\s*-?\d+\s*,\s*-?\d+\s*$")
WINREL = re.compile(r"^winrel:(?P<window>[^|]{1,200})\|(?P<x>0(?:\.\d+)?|1(?:\.0+)?),(?P<y>0(?:\.\d+)?|1(?:\.0+)?)$", re.I)
COMPARISON_OPS = {"=", "==", "!=", "<>", ">", "<", ">=", "<="}

# Actions whose target names a saved object of a given kind in the app.
PATTERN_ACTIONS = {"Find & Click", "Find & DblClick", "Find & TplClick", "Find & RClick", "Find & Drag",
                   "Wait for Pattern", "Wait Until Gone", "Find & Click Loop"}
ELEMENT_ACTIONS = {"Click Element", "Hover Element", "Wait Element"}
POINT_ACTIONS = {"Click", "Double Click", "Triple Click", "Right Click", "Hover Mouse"}
REGION_ACTIONS = {"OCR Region", "OCR Click", "OCR Wait", "Grab OCR to Var"}
VARIABLE_TARGET_ACTIONS = {"Set Variable", "Grab Clipboard", "If Contains", "If Variable", "Ask Input"}
VARIABLE_PRODUCERS = {"Set Variable", "Grab Clipboard", "Ask Input"}

# The Autopilot actions are implemented in lib/AutopilotActions.ahk. They are
# listed here so offline compilation works even before the app sends a catalog.
AUTOPILOT_SPECS = {
    "Ask Input": {"targetLabel": "Variable name", "targetHint": "letters/numbers/_", "paramLabel": "Prompt",
                  "paramHint": "question; default=...", "example": "Variable name=invoiceNo; Prompt=Invoice number?",
                  "help": "Asks the person running the workflow for a value and stores it as $var.<name>. Unattended runs need the value supplied in advance.",
                  "targetRequired": True, "paramRequired": True},
    "Approval Gate": {"targetLabel": "", "targetHint": "", "paramLabel": "What needs approval", "paramHint": "required",
                      "example": "Submit the timesheet for $var.week?",
                      "help": "Pauses and asks a person to approve before the next step. Declining stops the workflow. Unattended runs stop here.",
                      "targetRequired": False, "paramRequired": True},
    "Type Credential": {"targetLabel": "Credential", "targetHint": "saved portal name", "paramLabel": "Field",
                        "paramHint": "username or password", "example": "Credential=Payroll; Field=password",
                        "help": "Types a username or password stored in Windows Credential Manager. The secret is never saved in the workflow or logs.",
                        "targetRequired": True, "paramRequired": True},
    "Open Page": {"targetLabel": "", "targetHint": "", "paramLabel": "Page", "paramHint": "url=...; browser=chrome|edge|default; wait=title text; timeout=ms",
                  "example": "url=https://portal.example.com; wait=Sign in; timeout=20000",
                  "help": "Opens an http(s) page and waits for its browser window.",
                  "targetRequired": False, "paramRequired": True},
    "Human Check": {"targetLabel": "Area", "targetHint": "window:A (default) / coords", "paramLabel": "Options", "paramHint": "on=pause|stop; words=extra|words",
                    "example": "on=pause",
                    "help": "Looks for CAPTCHA, multi-factor or verification prompts. If one is shown, a person completes it; Fan never solves it.",
                    "targetRequired": False, "paramRequired": False},
    "Capture Evidence": {"targetLabel": "Area", "targetHint": "window:A (default) / full", "paramLabel": "Label", "paramHint": "what this proves",
                         "example": "Label=Confirmation page",
                         "help": "Saves a screenshot into the current run's audit trail.",
                         "targetRequired": False, "paramRequired": False},
}

RISK_WORDS = re.compile(
    r"\b(submit|send|pay|payment|payroll run|transfer|wire|delete|remove|purchase|buy|checkout|place order|"
    r"confirm|approve|sign(?!\s*in)|e-?sign|post|publish|refund|void|cancel (?:order|subscription|account)|"
    r"close account|file return|finali[sz]e)\b", re.I)
SHELL_PROGRAMS = re.compile(r"\b(cmd(?:\.exe)?|powershell|pwsh|wscript|cscript|reg(?:\.exe)?|del|rmdir|format|shutdown|diskpart)\b", re.I)
CLOSING_KEYS = re.compile(r"!\{F4\}|\^w\b|\^\{F4\}", re.I)


@dataclass
class Issue:
    step: int  # 1-based; 0 = whole workflow
    message: str

    def as_dict(self) -> dict:
        return {"step": self.step, "message": self.message}


@dataclass
class Report:
    errors: list[Issue] = field(default_factory=list)
    warnings: list[Issue] = field(default_factory=list)
    risks: list[dict] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors

    def as_dict(self) -> dict:
        return {"ok": self.ok, "errors": [e.as_dict() for e in self.errors],
                "warnings": [w.as_dict() for w in self.warnings], "risks": self.risks}


class Catalog:
    """Action names and specs, plus the saved names they may reference."""

    def __init__(self, actions: list[dict] | None = None, context: dict | None = None):
        self.specs: dict[str, dict] = {}
        for item in actions or []:
            name = str(item.get("name", "")).strip()
            if name:
                self.specs[name] = dict(item.get("spec") or {})
        for name, spec in AUTOPILOT_SPECS.items():
            self.specs.setdefault(name, dict(spec))
        self._lower = {name.lower(): name for name in self.specs}
        context = context or {}
        # None means "unknown, do not check"; a list (even empty) is authoritative.
        self.coordinates = _name_set(context.get("coordinates"))
        self.patterns = _name_set(context.get("patterns"))
        self.elements = _name_set(context.get("elements"))
        self.workflows = _name_set(context.get("workflows"))
        self.credentials = _name_set(context.get("credentials"))
        self.windows = [str(w) for w in context.get("windows") or []][:80]

    @property
    def names(self) -> list[str]:
        return list(self.specs)

    def canonical(self, action: str) -> str | None:
        return self._lower.get(str(action or "").strip().lower())

    def spec(self, action: str) -> dict:
        return self.specs.get(action, {})

    def prompt_lines(self) -> list[str]:
        lines = []
        for name, spec in self.specs.items():
            if name == "Learned Rehearsal Step":
                continue  # fixture-only replay; never authored
            target = spec.get("targetLabel") or ""
            param = spec.get("paramLabel") or ""
            parts = [name]
            if target:
                parts.append(f"target={target} ({spec.get('targetHint', '')}){' REQUIRED' if spec.get('targetRequired') else ''}")
            else:
                parts.append("target unused")
            if param:
                parts.append(f"param={param} ({spec.get('paramHint', '')}){' REQUIRED' if spec.get('paramRequired') else ''}")
            else:
                parts.append("param unused")
            help_text = re.sub(r"\s+", " ", str(spec.get("help", "")))[:220]
            example = str(spec.get("example", ""))[:120]
            lines.append(" | ".join(parts) + (f" | e.g. {example}" if example else "") + (f" | {help_text}" if help_text else ""))
        return lines


def _name_set(values) -> set[str] | None:
    if values is None:
        return None
    return {str(v) for v in values if str(v).strip()}


def parse_options(text: str) -> dict[str, str]:
    """``key=value; key=value`` (the engine's ParseLoopOptions format)."""
    options = {}
    for part in str(text or "").split(";"):
        if "=" in part:
            key, value = part.split("=", 1)
            if key.strip():
                options[key.strip().lower()] = value.strip()
    return options


def normalize_step(raw, catalog: Catalog) -> tuple[dict | None, str]:
    if not isinstance(raw, dict):
        return None, "step must be an object with action/target/param"
    action = catalog.canonical(raw.get("action", ""))
    if not action:
        return None, f"unknown action '{str(raw.get('action', ''))[:60]}'"
    step = {"action": action,
            "target": _text(raw.get("target", "")),
            "param": _text(raw.get("param", "")),
            "enabled": bool(raw.get("enabled", True))}
    if raw.get("note"):
        step["note"] = _text(raw["note"])[:300]
    failsafe = raw.get("failsafe")
    if isinstance(failsafe, dict) and failsafe:
        step["failsafe"] = {str(k): v for k, v in failsafe.items() if isinstance(v, (str, int, float, bool))}
    return step, ""


def _text(value) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    return str(value).replace("\r\n", "\n").strip()


def _int(text: str):
    try:
        return int(str(text).strip())
    except (TypeError, ValueError):
        return None


def validate(steps: list, catalog: Catalog) -> tuple[list[dict], Report]:
    """Normalize ``steps`` and report every problem found, not just the first."""
    report = Report()
    accepted: list[dict] = []
    if not isinstance(steps, list) or not steps:
        report.errors.append(Issue(0, "workflow needs at least one step"))
        return accepted, report
    if len(steps) > MAX_STEPS:
        report.errors.append(Issue(0, f"workflow has {len(steps)} steps; the limit is {MAX_STEPS}"))
        steps = steps[:MAX_STEPS]

    depth = 0
    known_vars: set[str] = {"i", "loopCount"}
    for index, raw in enumerate(steps, 1):
        step, problem = normalize_step(raw, catalog)
        if not step:
            report.errors.append(Issue(index, problem))
            continue
        accepted.append(step)
        for problem in _check_step(step, catalog):
            report.errors.append(Issue(index, problem))
        action, target, param = step["action"], step["target"], step["param"]
        if action == "Open Page":
            url = (parse_options(param) if "=" in param else {"url": param}).get("url", "")
            host = urlparse(url).hostname or ""
            if url.lower().startswith("http://") and host not in ("localhost", "127.0.0.1") and not host.endswith((".localhost", ".test")):
                report.warnings.append(Issue(index, "this page uses plain http; never type a password into it"))
        if len(target) > MAX_FIELD or len(param) > MAX_FIELD:
            report.errors.append(Issue(index, "target/param is longer than 2000 characters"))
        if action == "Loop Start":
            depth += 1
            loop_var = parse_options(param).get("var", "i")
            if loop_var:
                known_vars.add(loop_var)
        elif action == "Loop End":
            depth -= 1
            if depth < 0:
                report.errors.append(Issue(index, "Loop End has no matching Loop Start"))
                depth = 0
        elif action == "Loop Break" and depth == 0:
            report.errors.append(Issue(index, "Loop Break is outside a loop"))
        for name in VAR_REF.findall(target + " " + param):
            if name not in known_vars:
                report.warnings.append(Issue(index, f"$var.{name} is used before any step sets it"))
        if action in VARIABLE_PRODUCERS and VAR_NAME.match(target.removeprefix("$var.")):
            known_vars.add(target.removeprefix("$var."))
        if action in ("Grab OCR to Var", "OCR Full Screen to Var") and VAR_NAME.match(param):
            known_vars.add(param)
        if action == "OCR Region" and param.startswith("var:"):
            known_vars.add(param[4:])
        if action == "Popup Detect":
            known_vars.add(parse_options(param).get("var", "popupChanged"))
    if depth > 0:
        report.errors.append(Issue(0, f"{depth} Loop Start step(s) have no Loop End"))
    if accepted and all(not s["enabled"] for s in accepted):
        report.errors.append(Issue(0, "every step is disabled"))
    report.risks = assess_risks(accepted)
    return accepted, report


def _check_step(step: dict, catalog: Catalog) -> list[str]:
    action, target, param = step["action"], step["target"], step["param"]
    spec = catalog.spec(action)
    problems = []
    if spec.get("targetRequired") and not target:
        problems.append(f"{action} needs a {spec.get('targetLabel') or 'target'}")
    if spec.get("paramRequired") and not param:
        problems.append(f"{action} needs a {spec.get('paramLabel') or 'parameter'}")
    if problems:
        return problems

    if action == "Wait":
        value = _int(param)
        if value is None or not 0 <= value <= 600000:
            problems.append("Wait duration must be whole milliseconds between 0 and 600000")
    elif action == "Scroll":
        value = _int(param)
        if value is None or value == 0 or abs(value) > 50:
            problems.append("Scroll amount must be a nonzero whole number between -50 and 50")
    elif action == "Menu Select":
        value = _int(param)
        if value is None or not 1 <= value <= 50:
            problems.append("Menu Select needs 1..50 down presses")
    elif action == "Key Chord":
        parts = [p.strip() for p in param.split(",")]
        if len(parts) < 3 or _int(parts[2]) is None or not 1 <= _int(parts[2]) <= 50:
            problems.append("Key Chord format is modifier,key,count (count 1..50)")
    elif action == "Send Keys":
        if param.count("{") != param.count("}"):
            problems.append("Send Keys has unbalanced { } braces")
    elif action in POINT_ACTIONS:
        if not _point_target_ok(target, catalog):
            problems.append(f"{action} target '{target[:80]}' is not a saved coordinate, x,y or winrel:Window|0.5,0.5")
        if action == "Click" and param and (_int(param) is None or not 1 <= _int(param) <= 3):
            problems.append("Click count must be 1, 2 or 3")
    elif action in PATTERN_ACTIONS:
        name = target.removeprefix("[P] ")
        if catalog.patterns is not None and name not in catalog.patterns:
            problems.append(f"pattern '{name[:80]}' is not saved; capture it or use OCR Click with the visible text")
        if action == "Find & Drag" and not POINT.match(param) and not (catalog.coordinates and param in catalog.coordinates):
            problems.append("Find & Drag destination must be x,y or a saved coordinate")
    elif action in ELEMENT_ACTIONS:
        if catalog.elements is not None and target not in catalog.elements:
            problems.append(f"element '{target[:80]}' is not in the element registry")
    elif action in REGION_ACTIONS:
        if not _region_ok(target):
            problems.append(f"{action} area must be window:Title, window:A, full, or x1,y1,x2,y2")
        if action == "OCR Wait" and param and not (param.startswith("text:") or _int(param) is not None):
            problems.append("OCR Wait condition is a timeout in ms or text:Words,timeout")
        if action == "Grab OCR to Var" and not VAR_NAME.match(param):
            problems.append("Grab OCR to Var needs a variable name in Param")
    elif action == "Run Sequence":
        if catalog.workflows is not None and param not in catalog.workflows:
            problems.append(f"workflow '{param[:80]}' is not saved")
    elif action == "Activate Window" and len(param) < 2:
        problems.append("Activate Window needs a window title fragment or ahk_exe name")
    elif action == "Run Program" and param.lower().startswith("demo:") and param.lower() != "demo:lab":
        problems.append("only demo:lab is a built-in Run Program target")
    elif action == "If Variable":
        operator = param.split(",", 1)[0].strip()
        if "," not in param or operator not in COMPARISON_OPS:
            problems.append("If Variable comparison is operator,value with = != > < >= <=")
    elif action == "Loop Start":
        options = parse_options(param) if param else {}
        unknown = set(options) - {"count", "var"}
        if unknown:
            problems.append("Loop Start accepts only count= and var=")
        count = options.get("count", "5")
        if count.lower() not in ("forever", "infinite") and (_int(count) is None or not 1 <= _int(count) <= 10000):
            problems.append("Loop count must be 1..10000 or forever")
        if options.get("var") and not VAR_NAME.match(options["var"]):
            problems.append("Loop variable name must be letters, numbers or _")
    elif action == "Show Notification":
        if param.count(",") < 1:
            problems.append("Show Notification param is title,message[,seconds]")
    elif action == "Type Credential":
        if not CRED_NAME.match(target):
            problems.append("credential name must be 1..60 letters, numbers, space, _ . -")
        elif catalog.credentials is not None and target not in catalog.credentials:
            problems.append(f"no saved portal credential named '{target}'; add it under Autopilot > Portals")
        if param.lower() not in ("username", "password"):
            problems.append("Type Credential field must be username or password")
    elif action == "Open Page":
        options = parse_options(param) if "=" in param else {"url": param}
        url = options.get("url", "")
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https") or not parsed.netloc:
            problems.append("Open Page needs url=https://... (http/https only)")
        if options.get("browser", "default").lower() not in ("chrome", "edge", "default", "firefox"):
            problems.append("Open Page browser is chrome, edge, firefox or default")
        if "timeout" in options and (_int(options["timeout"]) is None or not 1000 <= _int(options["timeout"]) <= 120000):
            problems.append("Open Page timeout must be 1000..120000 ms")
    elif action == "Human Check":
        if target and not _region_ok(target):
            problems.append("Human Check area must be window:Title, window:A, full or x1,y1,x2,y2")
        if parse_options(param).get("on", "pause").lower() not in ("pause", "stop"):
            problems.append("Human Check on= must be pause or stop")
    elif action == "Capture Evidence":
        if target and not _region_ok(target):
            problems.append("Capture Evidence area must be window:Title, window:A, full or x1,y1,x2,y2")

    if action in VARIABLE_TARGET_ACTIONS:
        if not VAR_NAME.match(target.removeprefix("$var.").removeprefix("$")):
            problems.append(f"{action} variable name must be letters, numbers or _")
    return problems


def _point_target_ok(target: str, catalog: Catalog) -> bool:
    if POINT.match(target) or WINREL.match(target):
        return True
    lowered = target.lower()
    if lowered.startswith(("demo:", "window:", "control:")):
        return True
    if catalog.coordinates is None:
        return bool(target)
    return target in catalog.coordinates


def _region_ok(target: str) -> bool:
    lowered = target.strip().lower()
    return (lowered in ("", "full", "screen", "current", "last") or lowered.startswith(("window:", "demo:"))
            or bool(RECT.match(target)))


def assess_risks(steps: list[dict]) -> list[dict]:
    """Steps that could change something outside the computer's screen.

    ``high`` steps are irreversible-sounding clicks/submits or shell commands;
    ``medium`` steps commit forms or close windows. This is a heuristic for
    placing human approval, not a guarantee that a step is safe.
    """
    risks = []
    previous_typed = False
    for index, step in enumerate(steps, 1):
        action, target, param = step["action"], step["target"], step["param"]
        level, reason = "", ""
        clickable_text = ""
        if action in ("OCR Click",):
            clickable_text = param
        elif action in PATTERN_ACTIONS | ELEMENT_ACTIONS | POINT_ACTIONS:
            clickable_text = target
        if clickable_text and RISK_WORDS.search(clickable_text):
            level, reason = "high", f"clicks '{clickable_text[:60]}'"
        elif action == "Run Program" and SHELL_PROGRAMS.search(param):
            level, reason = "high", "runs a shell or system command"
        elif action == "Send Keys" and CLOSING_KEYS.search(param):
            level, reason = "medium", "closes a window or tab"
        elif action == "Send Keys" and "{enter}" in param.lower() and previous_typed:
            level, reason = "medium", "presses Enter after typing (may submit a form)"
        elif action in ("Fire Revolver+Enter",):
            level, reason = "medium", "pastes fields and presses Enter"
        if level:
            risks.append({"step": index, "level": level, "reason": reason, "action": action})
        if action in ("Type Text", "Type Credential", "Use Var Paste", "Paste", "Fire Revolver", "Insert Field"):
            previous_typed = True
        elif action not in ("Wait", "Send Keys"):
            previous_typed = False
    return risks


def ensure_approval_gates(steps: list[dict]) -> tuple[list[dict], list[str]]:
    """Insert an Approval Gate before each high-risk step that lacks one."""
    risks = {r["step"]: r for r in assess_risks(steps) if r["level"] == "high"}
    output: list[dict] = []
    notes = []
    for index, step in enumerate(steps, 1):
        if index in risks and not _gated(output):
            reason = risks[index]["reason"]
            output.append({"action": "Approval Gate", "target": "", "param": f"Approve step: {reason}?",
                           "enabled": True, "note": "Added automatically before an irreversible-looking step"})
            notes.append(f"Added an Approval Gate before step {index} ({reason}).")
        output.append(step)
    return output, notes


def _gated(previous: list[dict]) -> bool:
    for step in reversed(previous):
        if step["action"] == "Approval Gate":
            return True
        if step["action"] not in ("Wait", "Capture Evidence", "Show Notification"):
            return False
    return False
