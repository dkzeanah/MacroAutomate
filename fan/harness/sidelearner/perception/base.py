"""Shared watcher plumbing: threads that perceive and emit bus events."""
from __future__ import annotations

import logging
import threading
from typing import Any, Optional

from ..events import EventBus

log = logging.getLogger("sidelearner.perception")


class WatcherBase(threading.Thread):
    """Base class for always-on perception threads.

    Subclasses implement `_setup()` (return False to disable), `_tick()`
    (called each loop iteration), and `_teardown()`. Watchers are daemonic,
    crash-isolated, and expose a status dict.
    """

    kind = "base"
    default_interval = 2.0

    def __init__(self, bus: EventBus, config: Any, interval: Optional[float] = None) -> None:
        super().__init__(name=f"perception-{self.kind}", daemon=True)
        self.bus = bus
        self.config = config
        self.interval = interval if interval is not None else self.default_interval
        self._stop = threading.Event()
        self._ready = threading.Event()
        self.error: Optional[str] = None
        self.tick_count = 0
        self.started_at: Optional[str] = None

    # -- subclass hooks ----------------------------------------------------
    def _setup(self) -> bool:
        return True

    def _tick(self) -> None:  # pragma: no cover
        pass

    def _teardown(self) -> None:
        pass

    # -- lifecycle ---------------------------------------------------------
    def run(self) -> None:
        from ..utils import utcnow

        try:
            ok = self._setup()
        except Exception as exc:  # noqa: BLE001
            log.exception("%s: setup failed", self.kind)
            self.error = str(exc)
            ok = False
        if not ok:
            self.bus.emit(f"perception.{self.kind}.unavailable", {"reason": self.error or "disabled"}, source=self.kind)
            return
        self.started_at = utcnow()
        self._ready.set()
        log.info("%s watcher started (interval %.1fs)", self.kind, self.interval)
        while not self._stop.is_set():
            try:
                self._tick()
                self.tick_count += 1
            except Exception as exc:  # noqa: BLE001 — isolate crashes, keep watching
                log.warning("%s tick failed: %s", self.kind, exc)
            self._stop.wait(self.interval)
        try:
            self._teardown()
        except Exception:  # noqa: BLE001
            log.exception("%s: teardown failed", self.kind)
        log.info("%s watcher stopped (%d ticks)", self.kind, self.tick_count)

    def stop(self, timeout: float = 3.0) -> None:
        self._stop.set()
        if self.is_alive():
            self.join(timeout=timeout)

    def status(self) -> dict:
        return {
            "kind": self.kind,
            "alive": self.is_alive(),
            "ready": self._ready.is_set(),
            "ticks": self.tick_count,
            "error": self.error,
            "started_at": self.started_at,
        }
