"""Compressed knowledge graph: entities, facts, relations with retrieval."""
from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

import numpy as np

from ..router.embeddings import Embedder
from ..utils import cosine
from .store import Store

log = logging.getLogger("sidelearner.graph")


@dataclass
class Hit:
    kind: str  # "fact" | "entity"
    id: int
    text: str
    similarity: float
    weight: float


class KnowledgeGraph:
    """The compressed digital twin: what the computer's owner knows/has seen.

    Facts and entities carry embeddings for retrieval; facts merge when
    similar, gain weight on reinforcement, and decay/archive when stale.
    """

    def __init__(
        self,
        store: Store,
        embedder: Embedder,
        merge_similarity: float = 0.88,
        query_similarity: float = 0.25,
        decay_days: float = 14.0,
        max_facts: int = 20000,
    ) -> None:
        self.store = store
        self.embedder = embedder
        self.merge_similarity = merge_similarity
        self.query_similarity = query_similarity
        self.decay_days = decay_days
        self.max_facts = max_facts

    # -- entities ----------------------------------------------------------
    def add_entity(self, name: str, kind: str = "concept", source: Optional[str] = None, domain: str = "general") -> int:
        name = (name or "").strip()
        if not name:
            raise ValueError("entity name required")
        entity_id = self.store.upsert_entity(name[:160], kind or "concept", source=source, domain=domain)
        # Keep an embedding for retrieval.
        row = self.store.entity_by_name(name[:160])
        if row and row["embedding"] is None:
            try:
                self.store.set_entity_embedding(entity_id, self.embedder.embed_text(name))
            except Exception as exc:  # noqa: BLE001
                log.debug("entity embedding failed for %r: %s", name, exc)
        return entity_id

    def relate(self, src: int, rel: str, dst: int, weight: float = 1.0) -> None:
        self.store.add_relation(src, rel, dst, weight)

    # -- facts -------------------------------------------------------------
    def add_fact(
        self,
        text: str,
        confidence: float = 0.5,
        source_ids: Optional[list[int]] = None,
        summary: str = "",
        entities: Optional[list[tuple[str, str]]] = None,
        domain: str = "general",
    ) -> tuple[int, bool]:
        """Insert or merge a fact. Returns (fact_id, created_new)."""
        text = (text or "").strip()
        if len(text) < 10:
            raise ValueError("fact too short")
        try:
            vec = self.embedder.embed_text(text)
        except Exception as exc:  # noqa: BLE001
            log.warning("fact embedding failed (%s); using zero vector", exc)
            vec = np.zeros(self.embedder.dim, dtype=np.float32)
        existing = self.find_similar_fact(vec, self.merge_similarity, domain=domain)
        if existing is not None:
            fact_id = int(existing["id"])
            self.store.reinforce_fact(fact_id, delta=1.0, summary=summary or None)
            for sid in source_ids or []:
                self.store.add_fact_source(fact_id, sid)
            log.debug("merged fact into #%d: %s", fact_id, text[:60])
            return fact_id, False
        fact_id = self.store.add_fact(text, summary, vec, confidence, source_ids or [], domain=domain)
        # Wire entities to this fact (entity ids are simply recorded as sources
        # of knowledge; relations can be added later by the extractor).
        for name, kind in entities or []:
            try:
                self.add_entity(name, kind, source=f"fact:{fact_id}", domain=domain)
            except ValueError:
                pass
        return fact_id, True

    def find_similar_fact(
        self, vec: np.ndarray, threshold: Optional[float] = None, domain: str = "general"
    ) -> Optional[Any]:
        """Closest active fact, preferring same-domain candidates for merge."""
        threshold = self.merge_similarity if threshold is None else threshold
        candidates = self.store.facts_active(domain=domain)
        if domain != "general":
            candidates = candidates + self.store.facts_active(domain="general")
        best, best_sim = None, -1.0
        for row in candidates:
            blob = row["embedding"]
            if not blob:
                continue
            sim = cosine(vec, np.frombuffer(blob, dtype=np.float32))
            if row["domain"] == domain and domain != "general":
                sim = min(1.0, sim + 0.02)  # slight same-domain merge bias
            if sim > best_sim:
                best, best_sim = row, sim
        return best if best_sim >= threshold else None

    # -- retrieval ---------------------------------------------------------
    def _tokens(self, row_id: int, text: str) -> set[str]:
        from ..utils import tokenize

        cache = self.__dict__.setdefault("_token_cache", {})
        if row_id not in cache:
            cache[row_id] = set(tokenize(text))
            if len(cache) > 50000:
                cache.clear()
        return cache[row_id]

    def query(
        self, text: str, k: int = 8, min_similarity: Optional[float] = None, domain: Optional[str] = None
    ) -> list[Hit]:
        """Retrieve the most relevant facts/entities for `text`.

        Score = max(embedding cosine, token-overlap coefficient). The overlap
        term keeps short queries working with the model-free hash embedder.
        """
        from ..utils import tokenize

        floor = self.query_similarity if min_similarity is None else min_similarity
        q_tokens = set(tokenize(text))
        q_vec = None
        try:
            q_vec = self.embedder.embed_text(text)
        except Exception as exc:  # noqa: BLE001
            log.warning("query embedding failed: %s", exc)

        def _score(embedding, tokens: set[str]) -> float:
            sim = 0.0
            if q_vec is not None and embedding:
                sim = cosine(q_vec, np.frombuffer(embedding, dtype=np.float32))
            if q_tokens and tokens:
                overlap = len(q_tokens & tokens) / max(1, min(len(q_tokens), len(tokens)))
                sim = max(sim, overlap)
            return sim

        hits: list[Hit] = []
        for row in self.store.facts_active(domain=domain):
            sim = _score(row["embedding"], self._tokens(int(row["id"]), row["summary"] or row["text"]))
            if sim >= floor:
                hits.append(Hit("fact", int(row["id"]), row["summary"] or row["text"], sim, float(row["weight"])))
        for row in self.store.entities_all():
            if domain and row["domain"] != domain:
                continue
            name = f"{row['kind']}: {row['name']}"
            sim = _score(row["embedding"], self._tokens(-int(row["id"]), row["name"]))
            if sim >= floor + 0.15:  # entities need stronger match
                hits.append(Hit("entity", int(row["id"]), name, sim, float(row["weight"])))
        hits.sort(key=lambda h: (h.similarity * min(3.0, h.weight)), reverse=True)
        return hits[:k]

    def context_block(self, question: str, k: int = 6) -> str:
        """Render retrieved knowledge as a compact context block for the agent."""
        hits = self.query(question, k=k)
        if not hits:
            return ""
        lines = ["## Relevant learned knowledge (digital twin)"]
        for h in hits:
            lines.append(f"- [{h.kind}#{h.id} sim={h.similarity:.2f} w={h.weight:.1f}] {h.text[:400]}")
        return "\n".join(lines)

    # -- maintenance -------------------------------------------------------
    def decay(self, now_iso: str, min_weight: float = 2.0) -> int:
        """Archive stale low-weight facts. Returns archived count."""
        from datetime import datetime, timezone

        try:
            now = datetime.fromisoformat(now_iso)
        except ValueError:
            return 0
        archived = 0
        for row in self.store.facts_active():
            try:
                last = datetime.fromisoformat(row["last_seen"])
            except ValueError:
                continue
            age_days = (now - last).total_seconds() / 86400.0
            if age_days > self.decay_days and float(row["weight"]) < min_weight:
                self.store.archive_fact(int(row["id"]))
                archived += 1
        return archived

    def trim(self) -> int:
        """Enforce max_facts by archiving lowest-weight oldest facts."""
        rows = sorted(
            self.store.facts_active(),
            key=lambda r: (float(r["weight"]), r["last_seen"]),
        )
        overflow = len(rows) - self.max_facts
        for row in rows[:overflow]:
            self.store.archive_fact(int(row["id"]))
        return max(0, overflow)

    # -- status / io -------------------------------------------------------
    def status(self) -> dict:
        counts = self.store.counts()
        top = self.store.entities_all(min_weight=2.0)[:10]
        domains = {row["domain"]: int(row["n"]) for row in self.store.domains()}
        return {
            "facts": counts["facts"],
            "entities": counts["entities"],
            "relations": counts["relations"],
            "domains": domains,
            "top_entities": [f"{r['name']} ({r['kind']}, w={r['weight']:.0f})" for r in top],
        }

    def export(self, path: str | Path) -> Path:
        """Dump the graph as JSONL (entities, facts, relations) for backup."""
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            for row in self.store.entities_all():
                fh.write(json.dumps({"t": "entity", **{k: row[k] for k in ("id", "name", "kind", "domain", "weight", "last_seen")}}, ensure_ascii=False, default=str) + "\n")
            for row in self.store.facts_active():
                fh.write(
                    json.dumps(
                        {"t": "fact", "id": row["id"], "text": row["text"], "summary": row["summary"], "domain": row["domain"], "confidence": row["confidence"], "weight": row["weight"], "last_seen": row["last_seen"]},
                        ensure_ascii=False,
                        default=str,
                    )
                    + "\n"
                )
            for row in self.store.relations_all():
                fh.write(json.dumps({"t": "relation", **{k: row[k] for k in ("src", "rel", "dst", "weight")}}, ensure_ascii=False, default=str) + "\n")
        log.info("exported knowledge graph to %s", path)
        return path
