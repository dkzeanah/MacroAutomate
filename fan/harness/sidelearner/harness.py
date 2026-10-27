"""Harness: wires config, providers, router, twin, tools, skills, perception
and the agent loop into one object. This is the composition root used by the
CLI, demos, tests, and future embedders."""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Callable, Optional

from .captions import CaptionOverlay
from .config import Config
from .events import Event, EventBus
from .memory import DigitalTwin, Store
from .perception import PerceptionSupervisor
from .providers.cli_agents import CLIAgentAdapter
from .providers.registry import ProviderRegistry
from .reason import AgentLoop, AgentResult
from .router import Router
from .router.embeddings import get_embedder
from .skills import SkillEngine
from .tools import build_registry
from .tools.skill import register_skill_tools
from .tools.twin import register_twin_tools
from .utils import setup_logging

log = logging.getLogger("sidelearner.harness")


class Harness:
    def __init__(self, config: Config) -> None:
        self.config = config
        log_cfg = config.get("logging", {})
        logfile = Path(log_cfg["file"]) if log_cfg.get("file") else None
        setup_logging(str(log_cfg.get("level", "INFO")), logfile)

        self.bus = EventBus()
        self.registry = ProviderRegistry(config.get("providers", {}))
        self.cli_agents = CLIAgentAdapter.from_config(config.get("providers", {}))
        self.embedder = get_embedder(self.registry)

        self.store = Store(config.db_path)
        self._audio_persist_sub = self.bus.subscribe("perception.audio.transcript", self._persist_audio_transcript)
        self.twin = DigitalTwin(
            self.store, self.embedder, config, bus=self.bus, provider_factory=self._extraction_provider
        )

        self.tool_registry, self.fs_sandbox, self.shell_policy = build_registry(
            config, self.bus, vision_provider_factory=self._vision_provider
        )
        self.mcp_clients = getattr(self.tool_registry, "mcp_clients", [])
        register_twin_tools(self.tool_registry, self.twin)

        self.router = Router(self.registry, self.embedder, config)
        self.skill_engine = SkillEngine(config, self.tool_registry, self.bus)
        self.skill_engine.load()
        self.router.set_skills(self.skill_engine.skills)
        register_skill_tools(self.tool_registry, self.skill_engine, provider_factory=self._extraction_provider)

        self.supervisor = PerceptionSupervisor(config, self.bus, provider_factory=self._perception_provider)
        self.captions = CaptionOverlay(self.bus, config)
        from .autonomy import AutonomyEngine

        self.autonomy = AutonomyEngine(self)
        self.loop = AgentLoop(
            config,
            self.registry,
            self.router,
            self.tool_registry,
            config.vault / "sessions",
            twin=self.twin,
            bus=self.bus,
            cli_agents=self.cli_agents,
            skill_engine=self.skill_engine,
            ctx_provider=self.supervisor.current_context,
            store=self.store,
        )
        self.started = False

    # -- provider resolution helpers --------------------------------------
    def _extraction_provider(self) -> Optional[Any]:
        return self.registry.pick("local", {"text"})

    def _perception_provider(self) -> Optional[Any]:
        return (
            self.registry.pick("local", {"text", "vision"})
            or self.registry.pick("local", {"text", "audio"})
            or self.registry.pick("local", {"text"})
        )

    def _vision_provider(self) -> Optional[Any]:
        return self.registry.pick("local", {"text", "vision"})

    def _persist_audio_transcript(self, event: Event) -> None:
        data = event.data or {}
        text = str(data.get("text", "")).strip()
        if not text:
            return
        self.store.add_audio_segment(
            segment_id=str(data.get("segment_id") or event.ts),
            started=str(data.get("started") or event.ts),
            ended=str(data.get("ended") or event.ts),
            duration_s=float(data.get("duration_s") or 0.0),
            speech_s=float(data.get("speech_s") or 0.0),
            device=str(data.get("device") or ""),
            capture_mode=str(data.get("capture_mode") or "loopback"),
            wav_path=str(data.get("wav_path") or ""),
            transcript=text,
            backend=str(data.get("backend") or ""),
            language=str(data.get("language") or ""),
            confidence=data.get("confidence"),
        )

    # -- lifecycle ---------------------------------------------------------
    def start_perception(self) -> list:
        watchers = self.supervisor.start()
        if self.captions.enabled:
            self.captions.start()
        self.started = True
        return watchers

    def stop(self) -> None:
        if self.started:
            self.supervisor.stop()
        self.captions.stop()
        self.bus.unsubscribe(self._audio_persist_sub)
        for client in getattr(self, "mcp_clients", []):
            try:
                client.disconnect()
            except Exception:  # noqa: BLE001
                pass
        self.twin.shutdown()

    # -- actions -----------------------------------------------------------
    def chat(
        self,
        task: str,
        mode: str = "auto",
        cwd: Optional[str] = None,
        on_event: Optional[Callable[[dict], None]] = None,
        ask_callback: Optional[Callable[[str], bool]] = None,
        extra_context: str = "",
    ) -> AgentResult:
        return self.loop.run(task, mode=mode, cwd=cwd, on_event=on_event, extra_context=extra_context, ask_callback=ask_callback)

    def run_skill(self, name: str, vars: Optional[dict] = None, provider: Optional[Any] = None):
        skill = self.skill_engine.find(name)
        if skill is None:
            return None
        return self.skill_engine.run(skill, vars=vars, provider=provider or self._extraction_provider())

    def compress_twin(self) -> dict:
        return self.twin.compressor.run(max_items=50)

    # -- status ------------------------------------------------------------
    def status(self, probe: bool = False) -> dict:
        return {
            "config": self.config.summary(),
            "providers": self.registry.status(probe=probe),
            "cli_agents": self.cli_agents.status(),
            "skills": [s.name for s in self.skill_engine.skills],
            "tools": self.tool_registry.names(),
            "twin": self.twin.status(),
            "perception": self.supervisor.status(),
            "captions": self.captions.status(),
        }
