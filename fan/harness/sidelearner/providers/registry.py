"""Provider registry: construction from config, health probing, tiered pick."""
from __future__ import annotations

import logging
from typing import Any, Optional

from .anthropic import AnthropicProvider
from .base import Provider
from .openai_compat import OpenAICompatProvider

log = logging.getLogger("sidelearner.providers")

TIER_RANK = {"local": 0, "budget": 1, "best": 2}


class ProviderRegistry:
    """Holds all model providers, probes health, picks by tier+capability."""

    def __init__(self, providers_cfg: Optional[dict] = None) -> None:
        self.providers: dict[str, Provider] = {}
        self._order: list[str] = []
        if providers_cfg:
            self.load(providers_cfg)

    def load(self, providers_cfg: dict) -> None:
        for name, cfg in providers_cfg.items():
            if not isinstance(cfg, dict) or cfg.get("enabled") is False:
                continue
            kind = cfg.get("kind", "openai_compat")
            common = dict(
                name=name,
                model=cfg.get("model", ""),
                tier=cfg.get("tier", "local"),
                tags=list(cfg.get("tags") or []),
                capabilities=list(cfg.get("capabilities") or []),
            )
            try:
                if kind == "anthropic":
                    common.update(api_key=cfg.get("api_key", ""))
                    provider = AnthropicProvider(**common)
                elif kind == "openai_compat":
                    provider = OpenAICompatProvider(
                        **common,
                        base_url=cfg.get("base_url", "http://localhost:11434/v1"),
                        api_key=cfg.get("api_key", "not-needed"),
                        embed_model=cfg.get("embed_model"),
                        stt_model=cfg.get("stt_model"),
                        timeout=float(cfg.get("timeout", 120)),
                        extra=dict(cfg.get("extra") or {}),
                    )
                elif kind in ("cli_agent", "claude", "codex"):
                    continue  # handled by CLIAgentAdapter
                else:
                    log.warning("unknown provider kind %r for %s — skipped", kind, name)
                    continue
            except Exception as exc:  # noqa: BLE001
                log.warning("failed to construct provider %s: %s", name, exc)
                continue
            self.providers[name] = provider
            self._order.append(name)
        log.info("loaded providers: %s", ", ".join(self._order) or "(none)")

    # -- queries ----------------------------------------------------------
    def by_name(self, name: str) -> Optional[Provider]:
        return self.providers.get(name)

    def names(self) -> list[str]:
        return list(self._order)

    def healthy(self) -> dict[str, bool]:
        return {name: p.health() for name, p in self.providers.items()}

    def pick(
        self,
        tier: str = "local",
        capabilities: Optional[set[str]] = None,
        exclude: Optional[set[str]] = None,
        prefer: Optional[str] = None,
    ) -> Optional[Provider]:
        """Pick the cheapest healthy provider at or above `tier` with all capabilities.

        Ordering: requested tier first, then upward tiers; declared order within
        a tier; `prefer` (provider name) wins if healthy and capable.
        """
        capabilities = capabilities or {"text"}
        exclude = exclude or set()
        if prefer and prefer in self.providers and prefer not in exclude:
            p = self.providers[prefer]
            if capabilities <= p.capabilities and p.health():
                return p
        min_rank = TIER_RANK.get(tier, 0)
        ranked = sorted(
            self.providers.values(),
            key=lambda p: (TIER_RANK.get(p.tier, 9), self._order.index(p.name)),
        )
        for provider in ranked:
            if provider.name in exclude:
                continue
            if TIER_RANK.get(provider.tier, 9) < min_rank:
                continue
            if not (capabilities <= provider.capabilities):
                continue
            if not provider.health():
                continue
            return provider
        return None

    def embedder(self) -> Optional[Provider]:
        """First healthy provider that can embed."""
        for p in sorted(self.providers.values(), key=lambda p: TIER_RANK.get(p.tier, 9)):
            if p.health() and ("embed" in p.capabilities or p.embed_model):
                return p
        return None

    def status(self, probe: bool = True) -> list[dict]:
        rows = []
        for name, p in self.providers.items():
            rows.append(
                {
                    "name": name,
                    "kind": p.kind,
                    "model": p.model,
                    "tier": p.tier,
                    "capabilities": sorted(p.capabilities),
                    "healthy": p.health() if probe else None,
                }
            )
        return rows
