"""PerceptionSupervisor: owns the always-on watchers and the run-status file."""
from __future__ import annotations

import json
import logging
import threading
from pathlib import Path
from typing import Any, Callable, Optional

from ..events import EventBus
from ..router.router import RouteContext
from .audio import AudioWatcher
from .base import WatcherBase
from .camera import CameraWatcher
from .screen import ScreenWatcher, focused_window, grab_screen

log = logging.getLogger("sidelearner.perception.supervisor")


class PerceptionSupervisor:
    """Starts/stops all perception watchers and exposes current context.

    `current_context()` is what the pre-LLM router uses to ground routing in
    what is happening right now: focused app, last OCR text, audio activity.
    """

    def __init__(
        self,
        config: Any,
        bus: EventBus,
        provider: Optional[Any] = None,
        provider_factory: Optional[Callable[[], Optional[Any]]] = None,
    ) -> None:
        self.config = config
        self.bus = bus
        self.provider = provider
        self.provider_factory = provider_factory
        self.vault = config.vault
        self.watchers: list[WatcherBase] = []
        self._status_thread: Optional[threading.Thread] = None
        self._stop = threading.Event()

    def build_watchers(self) -> list[WatcherBase]:
        perc = self.config.get("perception", {})
        provider = self.provider or (self.provider_factory() if self.provider_factory else None)
        watchers: list[WatcherBase] = []
        if (perc.get("screen") or {}).get("enabled", True):
            watchers.append(ScreenWatcher(self.bus, self.config, self.vault))
        if (perc.get("audio") or {}).get("enabled", True):
            watchers.append(AudioWatcher(self.bus, self.config, self.vault, provider=provider))
        if (perc.get("camera") or {}).get("enabled", False):
            watchers.append(CameraWatcher(self.bus, self.config, self.vault, provider=provider))
        return watchers

    def start(self) -> list[WatcherBase]:
        self.watchers = self.build_watchers()
        for watcher in self.watchers:
            watcher.start()
        self._stop.clear()
        self._status_thread = threading.Thread(target=self._status_loop, name="perception-status", daemon=True)
        self._status_thread.start()
        return self.watchers

    def stop(self) -> None:
        self._stop.set()
        for watcher in self.watchers:
            watcher.stop()
        if self._status_thread is not None:
            self._status_thread.join(timeout=2.0)

    def status(self) -> dict:
        return {"watchers": [w.status() for w in self.watchers], "vault": str(self.vault)}

    def _status_loop(self) -> None:
        run_dir = self.vault / "run"
        run_dir.mkdir(parents=True, exist_ok=True)
        while not self._stop.wait(2.0):
            try:
                payload = {"watchers": [w.status() for w in self.watchers]}
                (run_dir / "status.json").write_text(json.dumps(payload, indent=2, default=str))
            except Exception:  # noqa: BLE001
                pass

    # -- context for the router -------------------------------------------
    def current_context(self) -> RouteContext:
        app, title = focused_window()
        audio_level = 0.0
        for watcher in self.watchers:
            if watcher.kind == "audio":
                audio_level = getattr(watcher, "_level", 0.0)
                break
        recent_text = ""
        recent = self.bus.history("perception.screen.text", limit=1)
        if recent:
            recent_text = str(recent[-1].data.get("text", ""))[:500]
        return RouteContext(
            app=app,
            window_title=title,
            recent_text=recent_text,
            audio_active=audio_level > 0.01,
            business=self.config.get("business", {}),
        )

    # -- one-shot helpers --------------------------------------------------
    def screenshot_now(self) -> Optional[Path]:
        img = grab_screen()
        if img is None:
            return None
        from ..utils import now_ms

        path = self.vault / "screen" / f"oneshot_{now_ms()}.jpg"
        path.parent.mkdir(parents=True, exist_ok=True)
        img.save(path, format="JPEG", quality=80)
        return path
