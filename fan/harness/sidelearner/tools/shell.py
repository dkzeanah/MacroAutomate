"""Shell tool: subprocess execution with timeout and allow/deny command lists."""
from __future__ import annotations

import logging
import subprocess
from pathlib import Path
from typing import Any, Optional

log = logging.getLogger("sidelearner.tools.shell")


class ShellPolicy:
    def __init__(self, allowlist: Optional[list[str]] = None, denylist: Optional[list[str]] = None) -> None:
        self.allowlist = [str(x).lower() for x in allowlist or []]
        self.denylist = [str(x).lower() for x in denylist or []]

    def check(self, command: str) -> Optional[str]:
        lowered = command.lower()
        for bad in self.denylist:
            if bad in lowered:
                return f"command matches denylist entry: {bad!r}"
        if self.allowlist:
            if not any(allowed in lowered for allowed in self.allowlist):
                return "command does not match the configured allowlist"
        return None


def run_command(
    command: str,
    cwd: Optional[str] = None,
    timeout_s: float = 300.0,
    env: Optional[dict] = None,
    policy: Optional[ShellPolicy] = None,
    max_output: int = 20000,
) -> dict:
    """Run a shell command; returns {ok, text, stdout, stderr, exit_code}."""
    if policy is not None:
        reason = policy.check(command)
        if reason:
            return {"ok": False, "text": f"denied: {reason}", "denied": True}
    try:
        proc = subprocess.run(
            command,
            cwd=cwd,
            env=env,
            shell=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout_s,
        )
    except subprocess.TimeoutExpired:
        return {"ok": False, "text": f"command timed out after {timeout_s}s"}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "text": f"command failed to launch: {exc}"}
    stdout = (proc.stdout or "")[:max_output]
    stderr = (proc.stderr or "")[:max_output]
    body = stdout
    if stderr and proc.returncode != 0:
        body = (body + "\n[stderr]\n" + stderr).strip()
    ok = proc.returncode == 0
    return {
        "ok": ok,
        "text": f"exit {proc.returncode} — {body[:max_output]}" if body else f"exit {proc.returncode} (no output)",
        "stdout": stdout,
        "stderr": stderr,
        "exit_code": proc.returncode,
    }


def register_shell_tools(registry, config) -> ShellPolicy:
    from .registry import ToolSpec

    shell_cfg = config.get("tools.shell", {})
    policy = ShellPolicy(shell_cfg.get("allowlist"), shell_cfg.get("denylist"))
    timeout = float(shell_cfg.get("timeout_s", 300))

    def run(command: str, cwd: Optional[str] = None, timeout_s: Optional[float] = None) -> dict:
        workdir = cwd or str(config.workspace)
        return run_command(command, cwd=workdir, timeout_s=timeout_s or timeout, policy=policy)

    registry.register(
        ToolSpec(
            "shell.run",
            "Run a shell command and capture output. Prefer python for file ops.",
            {"command": "str", "cwd": "str?", "timeout_s": "float?"},
            run,
            "high",
            "shell",
            False,
        )
    )
    return policy


def run_verify(registry, command: str, cwd: Optional[str] = None) -> dict:
    """Run a verification command (tests/lint) bypassing allowlist but not denylist."""
    spec = registry.get("shell.run")
    if spec is None:
        return {"ok": False, "text": "shell tool not registered"}
    shell_cfg = registry.config.get("tools.shell", {})
    policy = ShellPolicy(None, shell_cfg.get("denylist"))
    return run_command(command, cwd=cwd, timeout_s=float(shell_cfg.get("timeout_s", 300)), policy=policy)
