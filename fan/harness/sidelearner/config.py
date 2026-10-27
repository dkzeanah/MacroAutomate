"""Configuration: YAML + env overrides, defaults, and workspace resolution."""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Optional

import yaml

from .utils import deep_merge, expand_env

DEFAULTS: dict[str, Any] = {
    # Where all harvested media and the run status live (local-first, private).
    "vault_dir": "vault",
    # Perception: always-on watchers. Everything is stored/processed locally
    # unless a vision/transcription provider is explicitly enabled.
    "perception": {
        "screen": {
            "enabled": True,
            "interval_s": 1.5,          # poll cadence
            "change_threshold": 0.10,   # min visual change fraction to record
            "max_images": 200,          # rolling window of stored frames
            "ocr": {"enabled": False, "interval_s": 30.0, "lang": "eng"},
            "vision": {"enabled": False, "prompt": "Describe what is on screen: windows, app, task."},
        },
        "window": {"enabled": True, "interval_s": 1.0},
        "audio": {
            "enabled": True,
            "device": None,
            "sample_rate": 16000,
            "block_ms": 30,
            "vad_energy": 0.015,        # RMS speech threshold
            "min_speech_s": 0.4,
            "max_speech_s": 30.0,
            "silence_s": 0.9,
            "long_pause_s": 4.0,
            "capture_mode": "loopback",
            "loopback": True,
            "fallback_to_mic": False,
            "transcribe": True,
            "partial_every_s": 1.5,
            "stt": {
                "backend": "auto",      # local faster-whisper, then configured provider
                "model": "small.en",
                "device": "auto",
                "compute_type": "int8",
                "language": None,
            },
            "max_wavs": 100,
        },
        "camera": {
            "enabled": False,
            "index": 0,
            "interval_s": 2.0,
            "max_images": 100,
            "face_detect": False,
            "vision": {"enabled": False},
        },
    },
    # Memory: the observation ledger and the knowledge-graph digital twin.
    "memory": {
        "db": "memory.db",
        "merge_similarity": 0.88,       # facts this close merge into one
        "query_similarity": 0.25,       # retrieval floor
        "fact_min_confidence": 0.3,
        "decay_days": 14.0,             # stale, low-weight facts are archived
        "gap_minutes": 10.0,            # ledger items with no learned fact -> gap
        "max_facts": 20000,
        "auto_compress_every": 60.0,    # twin compression cadence (seconds)
        "compress_min_items": 3,        # or N unlearned items
    },
    # Pre-LLM router.
    "router": {
        "min_confidence": 0.25,
        "exemplars": [],                # optional list of {text, intent, tier}
        "tier_fallback": True,          # escalate to higher tiers if lower unhealthy
    },
    # Agent loop (own reasoning scaffolding).
    "agent": {
        "max_steps": 12,
        "max_tokens_out": 2048,
        "temperature": 0.2,
        "compact_at_tokens": 48000,
        "ask_permission": False,        # interactive confirm for risky tools
        "verify_cmd": None,             # e.g. "python -m pytest -q" run after file writes
        "retrieve_facts": True,
    },
    # Autonomy: the self-directed learning loop inside `sl run` / `sl daemon`.
    # prompt_mode: "ask" asks about uncertain patterns (early phase), "observe"
    # never prompts and just learns. Auto-confirmation kicks in after
    # auto_confidence identical answers, so prompting decreases over time.
    "autonomy": {
        "enabled": True,
        "interval_s": 20.0,
        "prompt_mode": "ask",
        "screenshot_on_start": True,
        "vision_on_change": True,
        "vision_interval_s": 60.0,
        "pattern_threshold": 2,
        "auto_confidence": 2,
        "max_open_prompts": 3,
    },
    "captions": {
        "enabled": False,
        "position": "bottom",
        "font_size": 24,
        "max_chars": 280,
        "opacity": 0.88,
    },
    # Tool policies.
    "tools": {
        "fs": {"roots": ["."], "max_read_bytes": 1_000_000},
        "shell": {
            "enabled": True,
            "timeout_s": 300,
            "allowlist": [],
            "denylist": ["format", "del /f", "rm -rf /", "rm -rf ~", "shutdown", "taskkill /f /im explorer"],
        },
        "desktop": {"control_enabled": False},   # mouse/keyboard control is opt-in
        "browser": {"enabled": False},
    },
    # MCP servers: local stdio or SSE servers that expose tools (e.g. Playwright).
    # Example: {playwright: {command: ["npx", "-y", "@anthropic-ai/playwright-mcp-server"]}}
    "mcp_servers": {},
    # Web dashboard settings.
    "web": {"enabled": False, "host": "127.0.0.1", "port": 8080, "require_token": False, "token": None},
    # Providers: {"name": {kind, model, base_url, api_key, enabled, tier, tags, capabilities}}
    "providers": {},
    # Business profile: vocabulary steers the router; workflow dirs feed skills.
    "business": {
        "name": "default",
        "domain": "",
        "vocabulary": [],
        "workflow_dirs": ["skills/examples"],
        "prompt": "",  # extra context injected into the agent system prompt
        # Knowledge taxonomy: the hierarchy facts are classified into.
        "taxonomy": [
            {"name": "bookkeeping", "keywords": ["invoice", "reconcile", "ledger", "quickbooks", "payroll", "expense", "account", "statement", "tax"]},
            {"name": "clients", "keywords": ["client", "customer", "vendor", "supplier", "contact", "contract", "proposal", "meeting", "call"]},
            {"name": "procedures", "keywords": ["procedure", "process", "workflow", "step", "deploy", "run", "build", "configure", "install", "checklist"]},
            {"name": "tools", "keywords": ["app", "tool", "software", "vscode", "chrome", "browser", "editor", "plugin", "shortcut"]},
            {"name": "development", "keywords": ["code", "function", "class", "script", "bug", "git", "repo", "test", "api", "python", "commit"]},
        ],
    },
    "logging": {"level": "INFO", "file": None},
}

# Env vars that override simple config keys: SL_<KEY> with __ for nesting.
_ENV_MAP = {
    "SL_VAULT_DIR": ("vault_dir", str),
    "SL_MEMORY_DB": ("memory.db", str),
    "SL_LOG_LEVEL": ("logging.level", str),
    "SL_WORKSPACE": ("workspace", str),
    "SL_ASK_PERMISSION": ("agent.ask_permission", lambda v: str(v).lower() in ("1", "true", "yes")),
}


def _env_overrides(cfg: dict) -> dict:
    over: dict = {}
    for env_key, (path, cast) in _ENV_MAP.items():
        raw = os.environ.get(env_key)
        if raw is None:
            continue
        try:
            value = cast(raw)
        except Exception:  # noqa: BLE001
            continue
        node = over
        parts = path.split(".")
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node[parts[-1]] = value
    return over


class Config:
    """Merged configuration with attribute access into the underlying dict."""

    def __init__(self, data: Optional[dict] = None, workspace: Optional[Path] = None) -> None:
        self.workspace = Path(workspace or os.environ.get("SL_WORKSPACE") or Path.cwd()).resolve()
        self.data: dict = deep_merge(DEFAULTS, data or {})
        self.data = deep_merge(self.data, _env_overrides(self.data))
        self.data = expand_env(self.data)
        self._resolve_paths()

    def _resolve_paths(self) -> None:
        """Anchor relative paths to the workspace."""
        for key in ("vault_dir",):
            p = Path(str(self.data[key])).expanduser()
            if not p.is_absolute():
                p = self.workspace / p
            self.data[key] = str(p)
        self.data["memory"]["db"] = str(
            Path(str(self.data["memory"]["db"])).expanduser()
            if Path(str(self.data["memory"]["db"])).is_absolute()
            else self.workspace / str(self.data["memory"]["db"])
        )
        roots = []
        for root in self.data["tools"]["fs"]["roots"]:
            p = Path(str(root)).expanduser()
            roots.append(str(p if p.is_absolute() else (self.workspace / p).resolve()))
        self.data["tools"]["fs"]["roots"] = roots
        dirs = []
        for d in self.data["business"]["workflow_dirs"]:
            p = Path(str(d)).expanduser()
            dirs.append(str(p if p.is_absolute() else (self.workspace / p).resolve()))
        self.data["business"]["workflow_dirs"] = dirs

    # -- access -----------------------------------------------------------
    def get(self, dotted: str, default: Any = None) -> Any:
        node: Any = self.data
        for part in dotted.split("."):
            if not isinstance(node, dict) or part not in node:
                return default
            node = node[part]
        return node

    def __getattr__(self, name: str) -> Any:
        # Called only when normal attribute lookup fails.
        data = self.__dict__.get("data")
        if data is not None and name in data:
            return data[name]
        raise AttributeError(name)

    @property
    def vault(self) -> Path:
        return Path(self.data["vault_dir"])

    @property
    def db_path(self) -> Path:
        return Path(self.data["memory"]["db"])

    # -- io ---------------------------------------------------------------
    @classmethod
    def load(
        cls, path: Optional[str | Path] = None, workspace: Optional[Path] = None
    ) -> "Config":
        workspace = Path(workspace or Path.cwd()).resolve()
        if path is None:
            path = os.environ.get("SL_CONFIG", str(workspace / "config.yaml"))
        path = Path(path).expanduser()
        if not path.is_absolute():
            path = workspace / path
        data: dict = {}
        if path.exists():
            with open(path, "r", encoding="utf-8") as fh:
                data = yaml.safe_load(fh) or {}
        cfg = cls(data, workspace=workspace)
        cfg.source_path = path
        return cfg

    def save(self, path: Optional[str | Path] = None) -> Path:
        path = Path(path or getattr(self, "source_path", "config.yaml"))
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            yaml.safe_dump(self.data, fh, sort_keys=False, default_flow_style=False)
        return path

    def summary(self) -> dict:
        return {
            "workspace": str(self.workspace),
            "vault": str(self.vault),
            "db": str(self.db_path),
            "business": self.data["business"]["name"],
            "providers": {
                name: {"kind": p.get("kind"), "model": p.get("model"), "enabled": p.get("enabled", True)}
                for name, p in self.data.get("providers", {}).items()
            },
            "perception": {
                "screen": self.data["perception"]["screen"]["enabled"],
                "window": self.data["perception"]["window"]["enabled"],
                "audio": self.data["perception"]["audio"]["enabled"],
                "camera": self.data["perception"]["camera"]["enabled"],
            },
        }
