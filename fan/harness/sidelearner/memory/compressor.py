"""Compressor: turns ledger items into compressed graph knowledge (and gaps)."""
from __future__ import annotations

import json
import logging
import re
import threading
from typing import Any, Callable, Optional

from ..utils import chunk_text, json_loads_lenient
from .classify import DEFAULT_TAXONOMY, DomainClassifier
from .graph import KnowledgeGraph
from .ledger import Ledger

log = logging.getLogger("sidelearner.compressor")

# -- provider-driven extraction prompt ------------------------------------
_EXTRACT_SYSTEM = """You are the knowledge compressor of a learning assistant. \
Extract durable, standalone facts from the observation text — things the \
computer's owner should retain. Output STRICT JSON only:
{"facts": [{"text": "standalone fact sentence", "kind": "concept|procedure|data|config|contact|decision", "entities": [{"name": "Entity", "kind": "person|tool|project|term|file|app"}]}]}
Rules: rewrite pronouns into explicit names; merge redundant points; if nothing is worth retaining, return {"facts": []}. Max 8 facts."""

_SENTENCE_RE = re.compile(r"[^.!?\n]+[.!?]?")
_CAP_RE = re.compile(r"\b[A-Z][A-Za-z0-9_\-]{2,}\b")

# Salient local cues when no provider is available.
_SALIENT_WORDS = {
    "use", "uses", "using", "configure", "configured", "install", "installed", "setup",
    "settings", "run", "running", "deploy", "deployed", "build", "built", "fix", "fixed",
    "error", "failed", "success", "warning", "note", "important", "must", "should",
    "password", "token", "key", "api", "url", "port", "path", "version", "requires",
    "todo", "deadline", "due", "meeting", "client", "customer", "vendor", "invoice",
    "report", "learn", "learning", "doc", "document", "tutorial", "guide", "course",
}


def _heuristic_facts(text: str, max_facts: int = 6) -> list[dict]:
    """No-model fact extraction: salient sentences + capitalized entities."""
    sentences = [s.strip() for s in _SENTENCE_RE.findall(text) if len(s.strip()) > 15]
    scored = []
    for sent in sentences:
        tokens = set(re.findall(r"[a-z]+", sent.lower()))
        caps = len(_CAP_RE.findall(sent))
        score = len(tokens & _SALIENT_WORDS) + caps
        if score:
            scored.append((score, sent))
    scored.sort(key=lambda pair: pair[0], reverse=True)
    facts = []
    for _, sent in scored[:max_facts]:
        entities = []
        for m in _CAP_RE.findall(sent)[:4]:
            if m.lower() not in _SALIENT_WORDS:
                entities.append({"name": m.strip(".,;:"), "kind": "term"})
        facts.append({"text": sent, "kind": "concept", "entities": entities})
    return facts


class Compressor:
    """Batch job: unlearned ledger items -> facts (merged) or gap records."""

    def __init__(
        self,
        graph: KnowledgeGraph,
        ledger: Ledger,
        provider: Optional[Any] = None,
        provider_factory: Optional[Callable[[], Optional[Any]]] = None,
        fact_min_confidence: float = 0.3,
        classifier: Optional[DomainClassifier] = None,
    ) -> None:
        self.graph = graph
        self.ledger = ledger
        self.provider = provider
        self.provider_factory = provider_factory
        self.fact_min_confidence = fact_min_confidence
        self.classifier = classifier or DomainClassifier()
        self._run_lock = threading.Lock()

    def classify_domain(self, text: str, provider: Optional[Any] = None) -> str:
        """Assign a fact to its taxonomy domain (keyword rules -> model fallback)."""
        domain, confidence = self.classifier.classify(text)
        if confidence < 0.03 and provider is not None:
            llm_domain = self.classifier.classify_llm(text, provider)
            if llm_domain and llm_domain != "general":
                return llm_domain
        return domain

    def extract_facts(self, text: str) -> list[dict]:
        """Extract candidate facts from text via provider or local heuristics."""
        provider = self.provider or (self.provider_factory() if self.provider_factory else None)
        if provider is not None:
            try:
                chunks = chunk_text(text, size=1800, overlap=150)
                facts: list[dict] = []
                for chunk in chunks[:4]:
                    completion = provider.chat(
                        [
                            {"role": "system", "content": _EXTRACT_SYSTEM},
                            {"role": "user", "content": chunk},
                        ],
                        temperature=0.1,
                        max_tokens=1200,
                    )
                    parsed = json_loads_lenient(completion.text)
                    for f in (parsed.get("facts") or [])[:8]:
                        if isinstance(f, dict) and f.get("text"):
                            facts.append(f)
                    if len(facts) >= 10:
                        break
                if facts:
                    return facts
            except Exception as exc:  # noqa: BLE001
                log.warning("provider extraction failed (%s); falling back to heuristics", exc)
        return _heuristic_facts(text)

    def run(self, max_items: int = 30) -> dict:
        """Compress a batch of unlearned ledger items. Returns stats.

        Serialized: concurrent runs (async auto-compress + explicit calls)
        would double-add facts and mangle the stats.
        """
        with self._run_lock:
            return self._run_locked(max_items)

    def _run_locked(self, max_items: int) -> dict:
        items = self.ledger.unlearned(limit=max_items)
        if not items:
            self._maintenance()
            return {"processed": 0, "facts_added": 0, "facts_merged": 0, "gaps": 0}

        facts_added = facts_merged = gaps = 0
        learned_ids: list[int] = []
        for row in items:
            ledger_id = int(row["id"])
            text = (row["text"] or "").strip()
            try:
                candidates = self.extract_facts(text) if text else []
            except Exception as exc:  # noqa: BLE001
                log.warning("extraction crashed for ledger #%d: %s", ledger_id, exc)
                candidates = []
            if candidates:
                contributed = False
                for cand in candidates:
                    try:
                        domain = self.classify_domain(cand["text"], provider=self.provider or (self.provider_factory() if self.provider_factory else None))
                        _, created = self.graph.add_fact(
                            cand["text"],
                            confidence=max(self.fact_min_confidence, 0.5),
                            source_ids=[ledger_id],
                            summary=cand.get("text", "")[:300],
                            entities=[(e["name"], e.get("kind", "term")) for e in cand.get("entities", [])],
                            domain=domain,
                        )
                        contributed = True
                        if created:
                            facts_added += 1
                        else:
                            facts_merged += 1
                    except ValueError:
                        continue
                if contributed:
                    learned_ids.append(ledger_id)
                else:
                    gaps += self._maybe_gap(ledger_id, "extracted candidates were not retainable")
            else:
                gaps += self._maybe_gap(ledger_id, "no extractable knowledge in observation")

        self.ledger.mark_learned(learned_ids)
        self._maintenance()
        result = {
            "processed": len(items),
            "facts_added": facts_added,
            "facts_merged": facts_merged,
            "gaps": gaps,
            "learned": len(learned_ids),
        }
        log.info("compressor run: %s", result)
        return result

    def _maybe_gap(self, ledger_id: int, reason: str) -> int:
        """Create a gap only once the learning window has expired. Returns 1
        when a new gap was created, else 0."""
        if any(int(row["id"]) == ledger_id for row in self.ledger.due_gaps()):
            return 1 if self.graph.store.add_gap(ledger_id, reason) else 0
        return 0

    def _maintenance(self) -> None:
        from ..utils import utcnow

        try:
            self.graph.decay(utcnow())
            self.graph.trim()
        except Exception as exc:  # noqa: BLE001
            log.warning("graph maintenance failed: %s", exc)
