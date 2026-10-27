"""Pre-LLM router: intent rules + exemplar kNN + tiered provider selection.

This runs entirely BEFORE any model call (except optionally an embedding
API) — it is SideLearner's own routing logic. It decides:

  * intent        — what kind of task this is (code_edit, shell, research…)
  * tier          — local / budget / best model tier
  * provider      — which configured provider+model handles it (cascade)
  * tools         — which tool families the agent may use
  * skill         — which business workflow skill matches (if any)
"""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from typing import Any, Optional

import numpy as np

from ..providers.registry import ProviderRegistry
from ..utils import jaccard, tokenize
from .embeddings import Embedder, get_embedder

log = logging.getLogger("sidelearner.router")


@dataclass
class RouteContext:
    """Signals gathered around the task: what is on screen, what app is focused."""

    app: str = ""
    window_title: str = ""
    recent_text: str = ""
    audio_active: bool = False
    business: dict = field(default_factory=dict)


@dataclass
class RouteDecision:
    intent: str
    tier: str
    provider_name: Optional[str]
    model: Optional[str]
    confidence: float
    capabilities_required: set = field(default_factory=lambda: {"text"})
    tools: list[str] = field(default_factory=list)
    skill: Optional[str] = None
    reasons: list[str] = field(default_factory=list)
    local_only: bool = False
    provider: Any = None

    def describe(self) -> str:
        who = f"{self.provider_name}/{self.model}" if self.provider_name else "NO PROVIDER (local-only)"
        return (
            f"intent={self.intent} tier={self.tier} provider={who} "
            f"confidence={self.confidence:.2f} tools={self.tools or '-'} skill={self.skill or '-'}"
        )


# Each rule: (intent, compiled regex, tier, tools, required capabilities, hint)
# Order matters: first match wins (rules are ordered most-specific first).
_RULE_SPECS: list[tuple[str, str, str, list[str], set[str]]] = [
    (
        "vision",
        r"\b(screenshot|screen|what('| i)?s on (the |my )?screen|look at (the |my )?(screen|display|monitor|image|picture|photo|camera))\b",
        "local",
        ["fs"],
        {"text", "vision"},
    ),
    (
        "transcribe",
        r"\b(transcrib|listen|what (did|was) (i|they|you|we) (say|said)|summarize (this |the )?(audio|recording|call|meeting))\b",
        "budget",
        [],
        {"text", "audio"},
    ),
    (
        "code_edit",
        r"\b(fix|repair|refactor|implement|add|create|write|build|change|modify|update|rewrite|rename|move|delete|remove)\b.{0,80}\b(code|function|class|module|script|file|test|bug|error|feature|api|endpoint|component|app|package|import|dependency)\b",
        "local",
        ["fs", "shell"],
        {"text"},
    ),
    (
        "code_read",
        r"\b(explain|understand|review|read|analyze|what does|how does|find (the )?(bug|issue|problem)|why (is|does))\b.{0,60}\b(code|function|class|file|script|repo|test|error)\b",
        "local",
        ["fs"],
        {"text"},
    ),
    (
        "shell",
        r"^\s*(run|execute|launch|start|stop|restart|install|build|deploy|compile|test|check|lint|format|git|pip|npm|pytest|docker)\b",
        "local",
        ["shell", "fs"],
        {"text"},
    ),
    (
        "workflow",
        r"\b(process|workflow|automate|automation|batch|routine|weekly|monthly|daily|generate (the |a )?report|invoice|reconcile|onboard|offboard|pipeline)\b",
        "local",
        ["fs", "shell"],
        {"text"},
    ),
    (
        "summarize",
        r"\b(summarize|summarise|condense|digest|tl;?dr|recap|key points|distill)\b",
        "local",
        [],
        {"text"},
    ),
    (
        "research",
        r"\b(what is|what are|who is|how do|how to|how does|explain|compare|difference between|research|look up|search (for|the web)|why is|why do|latest|news)\b",
        "budget",
        [],
        {"text"},
    ),
    (
        "admin",
        r"\b(list|show|status|health|enable|disable)\b.{0,40}\b(provider|model|agent|skill|config|camera|audio|perception|watcher)\b",
        "local",
        [],
        {"text"},
    ),
]

_BUILTIN_EXEMPLARS: list[dict] = [
    {"text": "fix the bug in the login function", "intent": "code_edit", "tier": "local"},
    {"text": "write a python script that renames files", "intent": "code_edit", "tier": "local"},
    {"text": "what does this file do", "intent": "code_read", "tier": "local"},
    {"text": "run the test suite now", "intent": "shell", "tier": "local"},
    {"text": "pip install requests", "intent": "shell", "tier": "local"},
    {"text": "what is a knowledge graph", "intent": "research", "tier": "budget"},
    {"text": "summarize this article for me", "intent": "summarize", "tier": "local"},
    {"text": "what is on my screen right now", "intent": "vision", "tier": "local"},
    {"text": "transcribe the meeting audio", "intent": "transcribe", "tier": "budget"},
    {"text": "process the invoices folder", "intent": "workflow", "tier": "local"},
]


class Router:
    """Deterministic intent routing + nearest-exemplar voting + provider pick."""

    def __init__(
        self,
        registry: Optional[ProviderRegistry] = None,
        embedder: Optional[Embedder] = None,
        config: Optional[Any] = None,
    ) -> None:
        self.registry = registry
        self.config = config
        router_cfg = getattr(config, "data", {}).get("router", {})
        self.min_confidence = float(router_cfg.get("min_confidence", 0.25))
        self.tier_fallback = bool(router_cfg.get("tier_fallback", True))
        self.rules: list[tuple[str, re.Pattern, str, list[str], set[str]]] = [
            (intent, re.compile(pattern, re.IGNORECASE), tier, tools, caps)
            for intent, pattern, tier, tools, caps in _RULE_SPECS
        ]
        self.embedder = embedder or get_embedder(registry)
        exemplars = list(_BUILTIN_EXEMPLARS) + list(router_cfg.get("exemplars") or [])
        self.exemplar_texts = [e["text"] for e in exemplars]
        self.exemplar_intents = [e["intent"] for e in exemplars]
        self.exemplar_tiers = [e.get("tier", "local") for e in exemplars]
        self._exemplar_vecs: Optional[np.ndarray] = None
        self._embedder_ok = True
        self._skills: list = []

    def set_skills(self, skills: list) -> None:
        """Attach the loaded workflow skills so business workflows get
        routing precedence over generic intents."""
        self._skills = skills

    # -- embedding of exemplars (lazy, resilient) --------------------------
    def _get_exemplar_vecs(self) -> Optional[np.ndarray]:
        if self._exemplar_vecs is not None:
            return self._exemplar_vecs
        if not self.exemplar_texts or not self._embedder_ok:
            return None
        try:
            self._exemplar_vecs = self.embedder.embed_texts(self.exemplar_texts)
        except Exception as exc:  # noqa: BLE001
            log.warning("exemplar embedding failed (%s); using rules+overlap only", exc)
            self._embedder_ok = False
        return self._exemplar_vecs

    # -- matching ----------------------------------------------------------
    def _business_vocabulary(self, ctx: RouteContext) -> set[str]:
        vocab = (ctx.business or {}).get("vocabulary", [])
        if not vocab and self.config is not None:
            vocab = self.config.get("business.vocabulary", [])
        return {str(w).lower() for w in vocab}

    def _rule_scan(self, task: str, ctx: RouteContext) -> Optional[tuple[str, str, list[str], set[str]]]:
        vocab = self._business_vocabulary(ctx)
        lowered = task.lower()
        for intent, pattern, tier, tools, caps in self.rules:
            if pattern.search(lowered):
                # Business vocabulary elevates workflow intent.
                if vocab and any(w in lowered for w in vocab) and intent in ("workflow", "chat"):
                    return ("workflow", "local", ["fs", "shell"], {"text"})
                return (intent, tier, tools, caps)
        if vocab and any(w in lowered for w in vocab):
            return ("workflow", "local", ["fs", "shell"], {"text"})
        return None

    def _knn_vote(self, task: str) -> tuple[Optional[str], Optional[str], float]:
        """Vote over exemplars by embedding similarity (fallback: token overlap).

        The score is max(embedding cosine, token jaccard) so that short
        queries stay robust even with the model-free hash embedder, where
        cosine can be noisy.
        """
        task_tokens = tokenize(task)
        vecs = self._get_exemplar_vecs()
        if vecs is not None and vecs.shape[0]:
            try:
                q = self.embedder.embed_text(task)
                sims = np.maximum(vecs @ q, np.asarray([jaccard(task_tokens, tokenize(t)) for t in self.exemplar_texts]))
                top = int(np.argmax(sims))
                return self.exemplar_intents[top], self.exemplar_tiers[top], float(sims[top])
            except Exception as exc:  # noqa: BLE001
                log.debug("kNN embedding failed: %s", exc)
        best, best_score = None, 0.0
        for text, intent, tier in zip(self.exemplar_texts, self.exemplar_intents, self.exemplar_tiers):
            score = jaccard(task_tokens, tokenize(text))
            if score > best_score:
                best, best_score = (intent, tier), score
        return (best or (None, None))[0], (best or (None, None))[1], best_score

    # -- skill matching ----------------------------------------------------
    def match_skill(self, task: str, skills: Optional[list] = None) -> Optional[str]:
        """Pick a skill whose keywords best overlap the task."""
        if not skills:
            return None
        task_tokens = set(tokenize(task))
        best_name, best_score = None, 0.0
        for skill in skills:
            kw = set(tokenize(" ".join(getattr(skill, "keywords", []) or [])))
            kw |= set(tokenize(getattr(skill, "name", "")))
            if not kw:
                continue
            score = len(task_tokens & kw) / max(1, len(kw))
            if score > best_score and score >= 0.25:
                best_name, best_score = getattr(skill, "name", None), score
        return best_name

    # -- main entry --------------------------------------------------------
    def route(self, task: str, ctx: Optional[RouteContext] = None) -> RouteDecision:
        ctx = ctx or RouteContext()
        reasons: list[str] = []
        decision = RouteDecision(intent="chat", tier="local", provider_name=None, model=None, confidence=0.0)

        # Stage 1: deterministic rules (authoritative).
        rule = self._rule_scan(task, ctx)
        if rule:
            intent, tier, tools, caps = rule
            decision.intent, decision.tier, decision.tools, decision.capabilities_required = intent, tier, tools, caps
            decision.confidence = 0.9
            reasons.append(f"rule: {intent} regex matched")
        else:
            # Stage 1b: business workflow skills take precedence over generic
            # intents — this is the hyper-optimization for the business.
            skill_name = self.match_skill(task, self._skills)
            if skill_name:
                decision.intent, decision.tier, decision.skill = "workflow", "local", skill_name
                decision.tools = ["fs", "shell"]
                decision.confidence = 0.7
                reasons.append(f"skill: {skill_name} keyword match")
            else:
                # Stage 2: exemplar kNN vote.
                intent, tier, sim = self._knn_vote(task)
                if intent and sim >= self.min_confidence:
                    decision.intent, decision.tier, decision.confidence = intent, tier, round(sim, 3)
                    reasons.append(f"kNN: {intent} (similarity {sim:.2f})")
                else:
                    reasons.append(f"kNN: no exemplar above {self.min_confidence:.2f} (best {sim:.2f})")

        # Stage 3: provider selection with cascade.
        if self.registry is not None:
            provider = self.registry.pick(decision.tier, decision.capabilities_required)
            if provider is None and self.tier_fallback:
                for tier in ("budget", "best", "local"):
                    if tier == decision.tier:
                        continue
                    provider = self.registry.pick(tier, decision.capabilities_required)
                    if provider is not None:
                        reasons.append(f"cascade: tier {decision.tier} unavailable -> {tier}")
                        decision.tier = tier
                        break
            if provider is not None:
                decision.provider = provider
                decision.provider_name = provider.name
                decision.model = provider.model
                reasons.append(f"provider: {provider.name} ({provider.model}, {provider.tier})")
            else:
                decision.local_only = True
                reasons.append("provider: none healthy — local-only/deterministic mode")

        decision.reasons = reasons
        log.info("route: %s", decision.describe())
        return decision
