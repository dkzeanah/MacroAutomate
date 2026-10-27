"""Provider abstraction: chat / embed / vision / transcribe / health."""
from __future__ import annotations

import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, Callable, Optional


class ProviderError(Exception):
    """Raised when a provider call fails."""


@dataclass
class Completion:
    text: str
    model: str
    finish_reason: Optional[str] = None
    usage: dict = field(default_factory=dict)
    raw: Any = None


class Provider(ABC):
    """Base class for every model backend SideLearner can talk to."""

    kind: str = "provider"
    name: str = "base"
    model: str = ""
    tier: str = "local"  # local | budget | best
    tags: list[str] = field(default_factory=list)
    capabilities: set[str] = field(default_factory=lambda: {"text"})

    def __init__(self, **kwargs: Any) -> None:
        self._health_cache: tuple[float, bool] | None = None

    # -- core ------------------------------------------------------------
    @abstractmethod
    def chat(
        self,
        messages: list[dict],
        stream: bool = False,
        on_token: Optional[Callable[[str], None]] = None,
        temperature: Optional[float] = None,
        max_tokens: Optional[int] = None,
        **kwargs: Any,
    ) -> Completion:
        """Complete a chat conversation."""

    # -- optional capabilities (return None when unsupported) -------------
    def embed(self, texts: list[str]) -> Optional[list[list[float]]]:
        return None

    def vision(self, image_bytes: bytes, prompt: str = "Describe this image.") -> Optional[str]:
        return None

    def transcribe(self, audio_bytes: bytes, filename: str = "audio.wav") -> Optional[str]:
        return None

    # -- health -----------------------------------------------------------
    def health(self, force: bool = False) -> bool:
        """Cached reachability probe. `force=True` re-probes immediately."""
        now = time.monotonic()
        if self._health_cache and now - self._health_cache[0] < 60.0 and not force:
            return self._health_cache[1]
        ok = self._probe()
        self._health_cache = (now, ok)
        return ok

    @abstractmethod
    def _probe(self) -> bool:
        """Cheap reachability check."""

    def __repr__(self) -> str:  # pragma: no cover
        return f"<{self.kind} {self.name} model={self.model} tier={self.tier} caps={sorted(self.capabilities)}>"
