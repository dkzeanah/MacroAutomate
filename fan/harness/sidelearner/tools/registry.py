"""Tool registry with layered permission policy (borrowed from Claude Code /
Codex / deepseek-harness design): every tool has a risk class; risky tools are
gated by config and by an interactive ask callback."""
from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from typing import Any, Callable, Optional

from ..events import EventBus

log = logging.getLogger("sidelearner.tools")

RISK_ORDER = {"low": 0, "medium": 1, "high": 2}


@dataclass
class ToolResult:
    ok: bool
    text: str
    data: dict = field(default_factory=dict)
    denied: bool = False

    def as_dict(self) -> dict:
        return {"ok": self.ok, "denied": self.denied, "text": self.text, **self.data}


@dataclass
class ToolSpec:
    name: str
    description: str
    parameters: dict  # JSON-schema-style parameter description
    function: Callable[..., dict]
    risk: str = "low"          # low | medium | high
    family: str = "fs"         # config key under tools.* for policy
    read_only: bool = True
    tags: list[str] = field(default_factory=list)


class ToolRegistry:
    """Registers tools, renders their schemas for prompts, executes with policy."""

    def __init__(self, config: Any, bus: Optional[EventBus] = None) -> None:
        self.config = config
        self.bus = bus
        self.specs: dict[str, ToolSpec] = {}
        self._ask: Optional[Callable[[str], bool]] = None
        self.mcp_clients: list[Any] = []

    def set_ask_callback(self, cb: Optional[Callable[[str], bool]]) -> None:
        """Interactive permission prompt (returns True to allow)."""
        self._ask = cb

    def register(self, spec: ToolSpec) -> None:
        self.specs[spec.name] = spec

    def register_many(self, specs: list[ToolSpec]) -> None:
        for spec in specs:
            self.register(spec)

    def get(self, name: str) -> Optional[ToolSpec]:
        return self.specs.get(name)

    def names(self) -> list[str]:
        return sorted(self.specs)

    # -- policy ------------------------------------------------------------
    def family_gate(self, family: str, risk: str) -> Optional[str]:
        """Return a denial reason, or None when allowed."""
        tools_cfg = self.config.get("tools", {})
        fam = tools_cfg.get(family, {})
        if family == "desktop" and risk == "high":
            if not fam.get("control_enabled", False):
                return "desktop control (mouse/keyboard) is disabled in config; set tools.desktop.control_enabled=true"
        if family == "shell" and fam.get("enabled") is False:
            return "shell tool is disabled in config"
        if family == "browser" and fam.get("enabled") is False:
            return "browser tool is disabled in config"
        return None

    def check_policy(self, spec: ToolSpec, args: dict) -> Optional[str]:
        reason = self.family_gate(spec.family, spec.risk)
        if reason:
            return reason
        if spec.risk == "high" and self._ask is None and spec.family == "fs":
            return "high-risk filesystem operation requires interactive permission; run with --ask"
        if spec.risk == "high" and self._ask is not None:
            try:
                allowed = self._ask(f"Allow high-risk tool '{spec.name}' with args {json.dumps(args)[:200]}? [y/N]")
            except Exception:  # noqa: BLE001
                allowed = False
            if not allowed:
                return "denied by user at permission prompt"
        return None

    # -- execution ---------------------------------------------------------
    def execute(self, name: str, args: Optional[dict] = None, ask: Optional[Callable[[str], bool]] = None) -> ToolResult:
        spec = self.specs.get(name)
        if spec is None:
            return ToolResult(ok=False, denied=True, text=f"unknown tool '{name}'; available: {', '.join(self.names())}")
        args = args or {}
        reason = self.check_policy(spec, args)
        if reason:
            log.warning("tool %s denied: %s", name, reason)
            return ToolResult(ok=False, denied=True, text=f"denied: {reason}")
        try:
            if self.bus is not None:
                self.bus.emit("tool.pre_execute", {"tool": name, "args": {k: str(v)[:200] for k, v in args.items()}}, source="tools")
            raw = spec.function(**args)
            if self.bus is not None:
                self.bus.emit("tool.post_execute", {"tool": name, "ok": raw.get("ok", True)}, source="tools")
        except TypeError as exc:
            return ToolResult(ok=False, text=f"bad arguments for {name}: {exc}")
        except Exception as exc:  # noqa: BLE001
            log.exception("tool %s crashed", name)
            return ToolResult(ok=False, text=f"{name} failed: {exc}")
        ok = bool(raw.get("ok", True))
        denied = bool(raw.get("denied", False))
        text = str(raw.get("text", "") or "")
        data = {k: v for k, v in raw.items() if k not in ("ok", "text", "denied")}
        return ToolResult(ok=ok, text=text, data=data, denied=denied)

    # -- prompt rendering --------------------------------------------------
    def schemas_for(self, allowed: Optional[set[str]] = None) -> str:
        """Compact JSON tool schemas for the model prompt."""
        items = []
        for name in sorted(self.specs):
            if allowed is not None and name not in allowed:
                continue
            spec = self.specs[name]
            items.append(
                {
                    "name": spec.name,
                    "description": spec.description,
                    "parameters": spec.parameters,
                    "risk": spec.risk,
                }
            )
        return json.dumps(items, indent=1)
