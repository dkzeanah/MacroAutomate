"""Skill engine: YAML business workflows run by a small local interpreter.

A skill is a declarative workflow (borrowed from OpenClaw's SKILL.md idea,
but data-driven YAML): triggers, steps that call tools, LLM prompt steps,
checks, conditions, repeats, and event emission. Pure tool steps run with
no model at all — prompt steps use the routed provider when one exists.
Skills are trusted local configuration: `{{ expr }}` templates evaluate in
a restricted namespace.
"""
from __future__ import annotations

import logging
import re
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

import yaml

from ..events import EventBus
from ..utils import tokenize

log = logging.getLogger("sidelearner.skills")

_TEMPLATE_RE = re.compile(r"\{\{(.*?)\}\}", re.S)

_RESTRICTED_GLOBALS = {
    "__builtins__": {},
    "len": len,
    "str": str,
    "int": int,
    "float": float,
    "bool": bool,
    "list": list,
    "dict": dict,
    "min": min,
    "max": max,
    "sum": sum,
    "round": round,
    "sorted": sorted,
    "join": lambda sep, items: sep.join(str(i) for i in items),
    "upper": lambda s: str(s).upper(),
    "lower": lambda s: str(s).lower(),
    "now": time.time,
}


@dataclass
class Skill:
    name: str
    description: str = ""
    keywords: list[str] = field(default_factory=list)
    triggers: list[str] = field(default_factory=list)
    requires: list[str] = field(default_factory=list)
    steps: list[dict] = field(default_factory=list)
    model_invocable: bool = True
    user_invocable: bool = True
    path: Optional[Path] = None

    @classmethod
    def from_yaml(cls, path: Path) -> "Skill":
        with open(path, "r", encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
        if not data.get("name"):
            raise ValueError(f"skill {path} missing 'name'")
        return cls(
            name=str(data["name"]),
            description=str(data.get("description", "")),
            keywords=[str(k) for k in data.get("keywords", [])],
            triggers=[str(t) for t in data.get("triggers", [])],
            requires=[str(r) for r in data.get("requires", [])],
            steps=list(data.get("steps", [])),
            model_invocable=bool(data.get("model_invocable", True)),
            user_invocable=bool(data.get("user_invocable", True)),
            path=path,
        )


@dataclass
class SkillResult:
    ok: bool
    output: str
    steps: list[dict] = field(default_factory=list)
    vars: dict = field(default_factory=dict)
    error: Optional[str] = None
    written: list[str] = field(default_factory=list)


def _render(template: Any, vars: dict) -> Any:
    """Render {{ expr }} templates; pass through non-strings untouched.

    The namespace exposes `vars` (attribute-accessible) plus every top-level
    var as a bare name, so both `{{ vars.cwd }}` and `{{ cwd }}` work.
    """
    if not isinstance(template, str):
        if isinstance(template, dict):
            return {k: _render(v, vars) for k, v in template.items()}
        if isinstance(template, list):
            return [_render(v, vars) for v in template]
        return template
    if "{{" not in template:
        return template
    namespace = dict(_RESTRICTED_GLOBALS)
    namespace["vars"] = vars
    namespace.update(vars)

    def _sub(match: re.Match) -> str:
        expr = match.group(1).strip()
        try:
            value = eval(expr, namespace, {})  # noqa: S307 — trusted local skills
            return "" if value is None else str(value)
        except Exception as exc:  # noqa: BLE001
            return f"[expr-error: {exc}]"

    return _TEMPLATE_RE.sub(_sub, template)


def _eval_expr(expr: str, vars: dict) -> Any:
    namespace = dict(_RESTRICTED_GLOBALS)
    namespace["vars"] = vars
    namespace.update(vars)
    return eval(expr, namespace, {})  # noqa: S307 — trusted local skills


class _Vars(dict):
    """Dict with attribute access so templates can write `vars.cwd`, `files.text`."""

    def __getattr__(self, name: str) -> Any:
        try:
            return self[name]
        except KeyError as exc:
            raise AttributeError(name) from exc

    def __setattr__(self, name: str, value: Any) -> None:
        self[name] = value


class SkillEngine:
    def __init__(self, config: Any, tools: Any, bus: Optional[EventBus] = None) -> None:
        self.config = config
        self.tools = tools
        self.bus = bus
        self.skills: list[Skill] = []

    # -- loading -----------------------------------------------------------
    def load_dir(self, directory: str | Path) -> int:
        directory = Path(directory)
        loaded = 0
        if not directory.is_dir():
            return 0
        for path in sorted(directory.glob("*.yaml")) + sorted(directory.glob("*.yml")):
            try:
                skill = Skill.from_yaml(path)
                self.skills.append(skill)
                loaded += 1
            except Exception as exc:  # noqa: BLE001
                log.warning("failed to load skill %s: %s", path, exc)
        return loaded

    def load(self, directories: Optional[list[str]] = None) -> int:
        directories = list(directories or self.config.get("business.workflow_dirs", []))
        # Bundled example skills are always available as built-ins.
        bundled = Path(__file__).parent / "examples"
        if bundled.is_dir() and str(bundled) not in directories:
            directories.insert(0, str(bundled))
        total = 0
        for d in directories:
            total += self.load_dir(d)
        log.info("loaded %d skills", total)
        return total

    def find(self, name: str) -> Optional[Skill]:
        for skill in self.skills:
            if skill.name.lower() == name.lower():
                return skill
        return None

    def match(self, text: str) -> Optional[Skill]:
        task_tokens = set(tokenize(text))
        best, best_score = None, 0.0
        for skill in self.skills:
            kws = set(tokenize(" ".join(skill.keywords))) | set(tokenize(skill.name))
            if not kws:
                continue
            score = len(task_tokens & kws) / len(kws)
            if score > best_score:
                best, best_score = skill, score
        return best if best and best_score >= 0.25 else None

    def match_event(self, event_type: str, text: str = "") -> Optional[Skill]:
        for skill in self.skills:
            for trigger in skill.triggers:
                if trigger.startswith("event:"):
                    pattern = trigger.split(":", 1)[1]
                    import fnmatch

                    if fnmatch.fnmatch(event_type, pattern):
                        return skill
        return self.match(text) if text else None

    # -- execution ---------------------------------------------------------
    def run(
        self,
        skill: Skill,
        vars: Optional[dict] = None,
        provider: Optional[Any] = None,
        max_steps: int = 200,
    ) -> SkillResult:
        vars = _Vars(vars or {})
        vars.setdefault("cwd", str(self.config.workspace))
        log.info("running skill %s", skill.name)
        written: list[str] = []
        try:
            result = self._run_steps(skill.steps, vars, provider, skill.name, budget=[max_steps], written=written)
        except _SkillStop as stop:
            return SkillResult(ok=stop.ok, output=str(stop.message), steps=stop.steps, vars=vars, written=stop.written)
        except Exception as exc:  # noqa: BLE001
            log.exception("skill %s crashed", skill.name)
            return SkillResult(ok=False, output=f"skill crashed: {exc}", vars=vars, error=str(exc), written=written)
        if self.bus is not None:
            self.bus.emit("skill.run", {"skill": skill.name, "ok": result.ok, "summary": result.output[:2000]}, source="skills")
        return result

    def _run_steps(
        self, steps: list[dict], vars: dict, provider: Any, skill_name: str, budget: list[int], written: list[str]
    ) -> SkillResult:
        log_steps: list[dict] = []
        output = ""
        for step in steps:
            if budget[0] <= 0:
                raise _SkillStop(False, f"skill {skill_name} exceeded step budget", log_steps)
            budget[0] -= 1
            kind = str(step.get("kind", "tool"))
            name = str(step.get("name", kind))
            if kind == "tool":
                tool = str(step["tool"])
                args = _render(step.get("args", {}), vars)
                result = self.tools.execute(tool, args)
                for path in result.data.get("written") or result.data.get("created") or []:
                    written.append(str(path))
                record = {"step": name, "tool": tool, "args": {k: str(v)[:200] for k, v in args.items()}, "ok": result.ok, "output": result.text[:400]}
                log_steps.append(record)
                if not result.ok and not step.get("continue_on_fail", False):
                    raise _SkillStop(False, f"step {name} failed: {result.text[:400]}", log_steps, written)
                output = result.text
                collect = step.get("collect")
                if collect:
                    vars[collect] = _Vars({"ok": result.ok, "text": result.text, **result.data})
            elif kind == "prompt":
                prompt = _render(step.get("prompt", ""), vars)
                system = _render(step.get("system", "You are a business automation assistant. Answer concisely."), vars)
                collect = step.get("collect")
                if provider is None:
                    record = {"step": name, "tool": "prompt", "ok": True, "output": "[no provider — prompt step skipped]"}
                    log_steps.append(record)
                    if collect:
                        vars[collect] = ""
                    continue
                completion = provider.chat(
                    [{"role": "system", "content": system}, {"role": "user", "content": prompt}],
                    temperature=0.2,
                    max_tokens=int(step.get("max_tokens", 1500)),
                )
                record = {"step": name, "tool": "prompt", "ok": True, "output": completion.text[:400]}
                log_steps.append(record)
                output = completion.text
                if collect:
                    vars[collect] = completion.text
            elif kind == "check":
                expr = str(step["expr"])
                if not _eval_expr(expr, vars):
                    raise _SkillStop(False, f"check failed: {expr}", log_steps, written)
                log_steps.append({"step": name, "tool": "check", "ok": True, "output": f"check passed: {expr}"})
            elif kind == "condition":
                expr = str(step["if"])
                branch = step.get("then", []) if _eval_expr(expr, vars) else step.get("else", [])
                sub = self._run_steps(branch, vars, provider, skill_name, budget, written)
                log_steps.extend(sub.steps)
                if not sub.ok:
                    raise _SkillStop(False, sub.output, log_steps, written)
                output = sub.output
            elif kind == "repeat":
                items = _eval_expr(str(step["over"]), vars)
                as_name = str(step.get("as", "item"))
                for item in items:
                    vars[as_name] = item
                    sub = self._run_steps(step.get("steps", []), vars, provider, skill_name, budget, written)
                    log_steps.extend(sub.steps)
                    if not sub.ok:
                        raise _SkillStop(False, sub.output, log_steps, written)
                    output = sub.output
            elif kind == "set":
                for key, expr in (step.get("vars") or {}).items():
                    vars[key] = _eval_expr(str(expr), vars)
                log_steps.append({"step": name, "tool": "set", "ok": True, "output": f"set {list((step.get('vars') or {}).keys())}"})
            elif kind == "emit":
                if self.bus is not None:
                    data = _render(step.get("data", {}), vars)
                    self.bus.emit(str(step["event"]), data, source=f"skill:{skill_name}")
                log_steps.append({"step": name, "tool": "emit", "ok": True, "output": str(step.get("event"))})
            elif kind == "wait":
                time.sleep(float(step.get("seconds", 1)))
                log_steps.append({"step": name, "tool": "wait", "ok": True, "output": f"waited {step.get('seconds')}s"})
            elif kind == "stop":
                raise _SkillStop(bool(step.get("ok", True)), _render(step.get("message", "stopped"), vars), log_steps, written)
            else:
                raise _SkillStop(False, f"unknown step kind: {kind}", log_steps, written)
        return SkillResult(ok=True, output=output, steps=log_steps, vars=vars, written=written)


class _SkillStop(Exception):
    def __init__(self, ok: bool, message: str, steps: list[dict], written: list[str]) -> None:
        super().__init__(message)
        self.ok = ok
        self.message = message
        self.steps = steps
        self.written = written
