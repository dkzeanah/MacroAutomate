"""Local heuristic planner: SideLearner's own reasoning without any model.

For well-known task shapes (run tests, read a file, list files, install,
write a file, git status…) the planner produces a deterministic tool plan.
This is what keeps the harness useful for scripted business workflows even
when no model provider is reachable.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Optional


@dataclass
class Step:
    tool: str
    args: dict
    description: str


@dataclass
class Plan:
    steps: list[Step]
    rationale: str

    def describe(self) -> str:
        lines = [f"plan ({self.rationale}):"]
        for i, step in enumerate(self.steps, 1):
            lines.append(f"  {i}. {step.description} -> {step.tool} {step.args}")
        return "\n".join(lines)


# Each heuristic: (compiled pattern, builder(task, match) -> list[Step])
_HEURISTICS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"^\s*run\s+(?:the\s+)?tests?\s*$", re.I), "tests"),
    (re.compile(r"^\s*list\s+(?:the\s+)?files?\s*$", re.I), "list_files"),
    (re.compile(r"^\s*(?:read|show|cat|open)\s+(?:the\s+)?(?:file\s+)?['\"]?([\w.\-\\/ ]+)['\"]?\s*$", re.I), "read_file"),
    (re.compile(r"^\s*(?:search|grep|find)\s+(?:for\s+)?['\"]?(\w+)['\"]?(?:\s+in\s+(\S+))?\s*$", re.I), "grep"),
    (re.compile(r"^\s*install\s+([\w\-\[\]=<>,. ]+)\s*$", re.I), "pip_install"),
    (re.compile(r"^\s*git\s+status\s*$", re.I), "git_status"),
    (re.compile(r"^\s*(?:create|make)\s+(?:a\s+)?(?:new\s+)?(?:dir(?:ectory)?|folder)\s+([\w.\-\\/ ]+)\s*$", re.I), "mkdir"),
    (
        re.compile(
            r"^\s*write\s+(?:a\s+)?(?:new\s+)?file\s+['\"]?([\w.\-\\/ ]+)['\"]?\s+(?:with|containing)\s*[:=]?\s*(.+)$",
            re.I | re.S,
        ),
        "write_file",
    ),
]


def _build_step(kind: str, match: re.Match) -> Step:
    if kind == "tests":
        return Step("shell.run", {"command": "python -m pytest -q"}, "run the test suite")
    if kind == "list_files":
        return Step("fs.list_dir", {"path": ".", "max_depth": 2}, "list workspace files")
    if kind == "read_file":
        return Step("fs.read_text", {"path": match.group(1).strip()}, f"read file {match.group(1).strip()}")
    if kind == "grep":
        term = match.group(1)
        path = match.group(2) or "."
        return Step("fs.grep", {"path": path, "pattern": re.escape(term)}, f"search for {term!r} in {path}")
    if kind == "pip_install":
        pkg = match.group(1).strip()
        return Step("shell.run", {"command": f"python -m pip install {pkg}"}, f"install {pkg}")
    if kind == "git_status":
        return Step("shell.run", {"command": "git status --short"}, "show git status")
    if kind == "mkdir":
        return Step("fs.mkdir", {"path": match.group(1).strip()}, f"create directory {match.group(1).strip()}")
    if kind == "write_file":
        path = match.group(1).strip()
        content = match.group(2).strip().strip('"\'')
        return Step("fs.write_text", {"path": path, "content": content}, f"write file {path}")
    raise ValueError(kind)


def heuristic_plan(task: str) -> Optional[Plan]:
    """Try to recognize `task` as a known deterministic shape."""
    for pattern, kind in _HEURISTICS:
        m = pattern.match(task.strip())
        if m:
            return Plan([_build_step(kind, m)], rationale=f"recognized shape: {kind}")
    # Generic "run <command>" fallback.
    m = re.match(r"^\s*(?:run|execute)\s+(.+)$", task.strip(), re.I | re.S)
    if m and len(m.group(1)) < 300:
        command = m.group(1).strip().strip('"\'')
        return Plan([Step("shell.run", {"command": command}, f"run command: {command}")], rationale="shell passthrough")
    return None
