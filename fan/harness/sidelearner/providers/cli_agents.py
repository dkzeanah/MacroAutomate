"""Third-party CLI agent adapters: Claude Code and OpenAI Codex.

These let SideLearner delegate whole agentic coding tasks to other AI
systems that run locally as subprocesses, while SideLearner retains
control of the prompt, working directory, environment, and policy flags.
"""
from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass, field
from typing import Any, Optional

from .base import ProviderError

# Sensible defaults; flag sets differ between CLI versions, so everything
# is overridable in config.yaml under providers.<name>.args.
PRESETS: dict[str, dict] = {
    "claude": {
        "binary": "claude",
        "args": ["-p", "--output-format", "text"],
        "permission_args": {
            "plan": ["--permission-mode", "plan"],
            "accept_edits": ["--permission-mode", "acceptEdits"],
            "bypass": ["--dangerously-skip-permissions"],
        },
    },
    "codex": {
        "binary": "codex",
        "args": ["exec", "--skip-git-repo-check", "-o", "text"],
        "permission_args": {
            "read_only": ["--sandbox", "read-only"],
            "workspace": ["--sandbox", "workspace-write"],
            "full": ["--sandbox", "danger-full-access", "--ask-for-approval", "never"],
            "ask": ["--sandbox", "workspace-write"],
        },
    },
}


@dataclass
class CLIAgentResult:
    text: str
    exit_code: int
    cwd: str
    duration_s: float
    raw: Any = None


@dataclass
class CLIAgent:
    """One configured CLI agent (e.g. `claude` or `codex`)."""

    name: str
    flavor: str  # "claude" | "codex" | custom
    binary: str
    args: list[str] = field(default_factory=list)
    permission_mode: str = "ask"  # maps to flavor's permission_args
    timeout_s: int = 900
    cwd: str = "."
    env: dict = field(default_factory=dict)
    extra: dict = field(default_factory=dict)

    @classmethod
    def from_config(cls, name: str, cfg: dict) -> "CLIAgent":
        flavor = str(cfg.get("flavor") or cfg.get("kind") or name).lower()
        preset = PRESETS.get(flavor, {})
        return cls(
            name=name,
            flavor=flavor,
            binary=cfg.get("binary") or preset.get("binary", name),
            args=list(cfg.get("args") or preset.get("args", [])),
            permission_mode=str(cfg.get("permission_mode", "ask")),
            timeout_s=int(cfg.get("timeout_s", 900)),
            cwd=str(cfg.get("cwd", ".")),
            env=dict(cfg.get("env") or {}),
            extra=dict(cfg.get("extra") or {}),
        )

    def command(self, prompt: str) -> list[str]:
        preset = PRESETS.get(self.flavor, {})
        perm_args = list((preset.get("permission_args") or {}).get(self.permission_mode, []))
        if self.flavor == "claude" and self.permission_mode == "ask":
            perm_args = []  # Claude Code -p asks interactively by default; avoid tty issues.
        cmd = [self.binary, *self.args, *perm_args, prompt]
        return cmd

    def available(self) -> bool:
        return shutil.which(self.binary) is not None

    def run(self, prompt: str, cwd: Optional[str] = None, extra_args: Optional[list[str]] = None) -> CLIAgentResult:
        import time

        if not self.available():
            raise ProviderError(f"{self.name}: binary '{self.binary}' not found on PATH")
        workdir = os.path.abspath(os.path.expanduser(cwd or self.cwd))
        if not os.path.isdir(workdir):
            raise ProviderError(f"{self.name}: cwd does not exist: {workdir}")
        cmd = self.command(prompt) + (extra_args or [])
        env = {**os.environ, **self.env}
        start = time.monotonic()
        try:
            proc = subprocess.run(
                cmd,
                cwd=workdir,
                env=env,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=self.timeout_s,
            )
        except subprocess.TimeoutExpired as exc:
            raise ProviderError(f"{self.name}: timed out after {self.timeout_s}s") from exc
        except OSError as exc:
            raise ProviderError(f"{self.name}: failed to launch: {exc}") from exc
        output = (proc.stdout or "").strip()
        if not output and proc.stderr:
            output = (proc.stderr or "").strip()
        return CLIAgentResult(
            text=output,
            exit_code=proc.returncode,
            cwd=workdir,
            duration_s=round(time.monotonic() - start, 2),
            raw=proc,
        )


class CLIAgentAdapter:
    """Registry of CLI agents, addressable as 'agents' in provider selection."""

    def __init__(self, agents: Optional[dict[str, CLIAgent]] = None) -> None:
        self.agents: dict[str, CLIAgent] = agents or {}

    @classmethod
    def from_config(cls, providers_cfg: dict) -> "CLIAgentAdapter":
        agents = {
            name: CLIAgent.from_config(name, cfg)
            for name, cfg in providers_cfg.items()
            if cfg.get("kind") in ("cli_agent", "claude", "codex")
        }
        return cls(agents)

    def get(self, name: str) -> Optional[CLIAgent]:
        return self.agents.get(name)

    def run(self, name: str, prompt: str, cwd: Optional[str] = None) -> CLIAgentResult:
        agent = self.get(name)
        if agent is None:
            raise ProviderError(f"unknown CLI agent: {name}")
        return agent.run(prompt, cwd)

    def status(self) -> dict[str, bool]:
        return {name: agent.available() for name, agent in self.agents.items()}
