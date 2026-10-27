"""Minimal thread-safe pub/sub event bus with a bounded history ring."""
from __future__ import annotations

import fnmatch
import threading
from dataclasses import dataclass, field
from typing import Any, Callable, Optional

from .utils import utcnow

Handler = Callable[["Event"], None]


@dataclass
class Event:
    """A typed, timestamped event with a data payload and source."""

    type: str
    data: dict = field(default_factory=dict)
    source: str = "core"
    ts: str = field(default_factory=utcnow)

    def as_dict(self) -> dict:
        return {"type": self.type, "data": self.data, "source": self.source, "ts": self.ts}


class EventBus:
    """Thread-safe event bus. Handlers subscribe to exact types or fnmatch patterns.

    The bus keeps a bounded history so late subscribers (e.g. the twin) can
    catch up on what was perceived before they attached.
    """

    def __init__(self, history_size: int = 500) -> None:
        self._lock = threading.RLock()
        self._subs: dict[int, tuple[str, Handler]] = {}
        self._next_id = 1
        self._history: list[Event] = []
        self._history_size = history_size

    def subscribe(self, type_or_pattern: str, handler: Handler) -> int:
        with self._lock:
            sid = self._next_id
            self._next_id += 1
            self._subs[sid] = (type_or_pattern, handler)
            return sid

    def unsubscribe(self, sub_id: int) -> bool:
        with self._lock:
            return self._subs.pop(sub_id, None) is not None

    def emit(self, type: str, data: Optional[dict] = None, source: str = "core") -> Event:
        event = Event(type=type, data=data or {}, source=source)
        with self._lock:
            self._history.append(event)
            if len(self._history) > self._history_size:
                del self._history[: len(self._history) - self._history_size]
            subs = list(self._subs.values())
        for pattern, handler in subs:
            try:
                if pattern == type or fnmatch.fnmatch(type, pattern):
                    handler(event)
            except Exception:  # noqa: BLE001 — a bad handler must not break the bus
                import logging

                logging.getLogger("sidelearner.events").exception(
                    "handler %r failed for event %s", getattr(handler, "__name__", handler), type
                )
        return event

    def history(self, pattern: Optional[str] = None, limit: int = 100) -> list[Event]:
        with self._lock:
            items = list(self._history)
        if pattern:
            items = [e for e in items if fnmatch.fnmatch(e.type, pattern)]
        return items[-limit:]

    def count(self, pattern: Optional[str] = None) -> int:
        return len(self.history(pattern, limit=10**9))
