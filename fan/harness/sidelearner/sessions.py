"""Event-sourced session log: append-only JSONL, one file per session.

Invariant (borrowed from deepseek-harness): anything the model can see is
logged. The log is replayable and is the durable spine for transcripts,
resume, and debugging.
"""
from __future__ import annotations

import json
import logging
import uuid
from pathlib import Path
from typing import Any, Iterator, Optional

from .utils import utcnow

log = logging.getLogger("sidelearner.sessions")


class SessionLog:
    """Append-only JSONL session store under <dir>/<session_id>.jsonl."""

    def __init__(self, directory: Path) -> None:
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.session_id: Optional[str] = None
        self.path: Optional[Path] = None

    def start(self, meta: Optional[dict] = None) -> str:
        """Open a new session and return its id."""
        self.session_id = uuid.uuid4().hex[:12]
        self.path = self.directory / f"{self.session_id}.jsonl"
        self.append("session.start", meta or {})
        return self.session_id

    def resume(self, session_id: str) -> Optional[list[dict]]:
        """Point the log at an existing session; returns its events (None if missing)."""
        path = self.directory / f"{session_id}.jsonl"
        if not path.exists():
            return None
        self.session_id = session_id
        self.path = path
        return self.read()

    def append(self, event_type: str, data: Optional[dict] = None, **extra: Any) -> dict:
        if self.path is None:
            raise RuntimeError("session not started; call start() first")
        record = {"ts": utcnow(), "type": event_type, "data": data or {}, **extra}
        with open(self.path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, ensure_ascii=False, default=str) + "\n")
        return record

    def read(self, session_id: Optional[str] = None) -> list[dict]:
        path = self.directory / f"{session_id or self.session_id}.jsonl"
        if not path.exists():
            return []
        events: list[dict] = []
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    log.warning("corrupt line in session log %s — skipped", path.name)
        return events

    def sessions(self) -> list[dict]:
        rows = []
        for path in sorted(self.directory.glob("*.jsonl")):
            events = self.read(path.stem)
            first = events[0] if events else {}
            rows.append(
                {
                    "id": path.stem,
                    "started": first.get("ts"),
                    "events": len(events),
                    "task": (first.get("data") or {}).get("task", ""),
                }
            )
        return rows

    def transcript(self, session_id: Optional[str] = None) -> str:
        """Human-readable transcript of one session."""
        parts: list[str] = []
        for ev in self.read(session_id):
            t, d = ev["type"], ev.get("data") or {}
            if t == "session.start":
                parts.append(f"[session start] task: {d.get('task', '')}")
            elif t == "model.message":
                role = d.get("role", "model")
                parts.append(f"[{role}] {d.get('content', '')}")
            elif t == "tool.call":
                parts.append(f"[tool] {d.get('tool', '?')} {json.dumps(d.get('args', {}), default=str)[:200]}")
            elif t == "tool.result":
                status = "ok" if d.get("ok") else "denied/failed"
                parts.append(f"[tool:{status}] {str(d.get('text', ''))[:300]}")
            elif t == "agent.verdict":
                parts.append(f"[verification] {d.get('notes', '')}")
            elif t == "session.end":
                parts.append(f"[session end] {d.get('summary', '')}")
        return "\n".join(parts)
