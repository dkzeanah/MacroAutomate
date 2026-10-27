"""Event -> skill triggers: business workflows that fire on observed activity."""
from __future__ import annotations

import logging
import threading
import time
from typing import Any, Optional

from .events import Event, EventBus

log = logging.getLogger("sidelearner.triggers")

_TRIGGER_SOURCES = ("perception", "skills")


class TriggerManager:
    """Watches the event bus and runs skills whose triggers match.

    Each skill runs at most once per `min_interval_s` to avoid feedback
    loops (a skill's own emitted events could otherwise re-trigger it).
    """

    def __init__(self, harness: Any, min_interval_s: float = 60.0) -> None:
        self.harness = harness
        self.skill_engine = harness.skill_engine
        self.bus: EventBus = harness.bus
        self.min_interval_s = min_interval_s
        self._last_run: dict[str, float] = {}
        self._threads: set[threading.Thread] = set()
        self._sub = self.bus.subscribe("*", self._on_event)

    def _on_event(self, event: Event) -> None:
        if not event.type.startswith(_TRIGGER_SOURCES):
            return
        skill = self.skill_engine.match_event(event.type, str((event.data or {}).get("text", "")))
        if skill is None or not skill.user_invocable:
            return
        now = time.monotonic()
        if now - self._last_run.get(skill.name, 0.0) < self.min_interval_s:
            return
        self._last_run[skill.name] = now
        thread = threading.Thread(
            target=self._run_skill, args=(skill, event), name=f"trigger-{skill.name}", daemon=True
        )
        self._threads.add(thread)
        thread.start()

    def _run_skill(self, skill: Any, event: Event) -> None:
        try:
            provider = self.harness._extraction_provider()
            result = self.skill_engine.run(
                skill,
                vars={"event": event.as_dict(), "cwd": str(self.harness.config.workspace)},
                provider=provider,
            )
            log.info("triggered skill %s: ok=%s (%s)", skill.name, result.ok, result.output[:200])
        except Exception:  # noqa: BLE001
            log.exception("triggered skill %s crashed", skill.name)

    def stop(self) -> None:
        self.bus.unsubscribe(self._sub)
