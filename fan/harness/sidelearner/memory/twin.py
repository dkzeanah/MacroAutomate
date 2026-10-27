"""DigitalTwin: the side-learner façade wiring perception -> ledger -> graph."""
from __future__ import annotations

import logging
import threading
from pathlib import Path
from typing import Any, Callable, Optional

from ..events import Event, EventBus
from ..router.embeddings import Embedder
from ..utils import now_ms
from .classify import DomainClassifier
from .compressor import Compressor
from .graph import Hit, KnowledgeGraph
from .ledger import Ledger
from .store import Store

log = logging.getLogger("sidelearner.twin")

# Map bus events to ledger observation kinds (with the text payload key).
_EVENT_KINDS = {
    "perception.window": ("window", "text"),
    "perception.screen.text": ("screen", "text"),
    "perception.screen.vision": ("vision", "description"),
    "perception.audio.transcript": ("audio", "text"),
    "perception.camera.vision": ("vision", "description"),
    "perception.clipboard": ("clipboard", "text"),
    "agent.tool.result": ("agent", "text"),
    "skill.run": ("skill", "summary"),
}


class DigitalTwin:
    """Continuously learns from perception events, maintains the compressed
    knowledge graph, and reports gaps — data that appeared and had the chance
    to be learned but was not captured."""

    def __init__(
        self,
        store: Store,
        embedder: Embedder,
        config: Any,
        bus: Optional[EventBus] = None,
        provider: Optional[Any] = None,
        provider_factory: Optional[Callable[[], Optional[Any]]] = None,
    ) -> None:
        mem_cfg = config.get("memory", {})
        self.config = config
        self.store = store
        taxonomy = config.get("business.taxonomy") or None
        self.classifier = DomainClassifier(taxonomy)
        self.graph = KnowledgeGraph(
            store,
            embedder,
            merge_similarity=float(mem_cfg.get("merge_similarity", 0.88)),
            query_similarity=float(mem_cfg.get("query_similarity", 0.25)),
            decay_days=float(mem_cfg.get("decay_days", 14)),
            max_facts=int(mem_cfg.get("max_facts", 20000)),
        )
        self.ledger = Ledger(store, gap_minutes=float(mem_cfg.get("gap_minutes", 10)))
        self.compressor = Compressor(
            self.graph,
            self.ledger,
            provider=provider,
            provider_factory=provider_factory,
            fact_min_confidence=float(mem_cfg.get("fact_min_confidence", 0.3)),
            classifier=self.classifier,
        )
        self.auto_compress_every = float(mem_cfg.get("auto_compress_every", 60.0))
        self.compress_min_items = int(mem_cfg.get("compress_min_items", 3))
        self._bus = bus
        self._subs: list[int] = []
        self._last_compress = 0.0
        self._lock = threading.Lock()
        self._thread: Optional[threading.Thread] = None
        if bus is not None:
            for pattern in _EVENT_KINDS:
                self._subs.append(bus.subscribe(pattern, self._on_event))

    # -- perception intake -------------------------------------------------
    def _on_event(self, event: Event) -> None:
        try:
            kind, key = _EVENT_KINDS[event.type]
            text = str((event.data or {}).get(key, "") or "")
            meta = {k: v for k, v in (event.data or {}).items() if k != key}
            self.ingest(kind, text, meta)
        except Exception:  # noqa: BLE001
            log.exception("twin failed to ingest %s", event.type)

    def ingest(self, kind: str, text: str, meta: Optional[dict] = None, source: str = "perception") -> Optional[int]:
        if not text.strip():
            return None
        # Occurrence tracking feeds pattern detection (counts every event,
        # even when the ledger dedupes identical content).
        subject = str((meta or {}).get("app", "") or "") if kind == "window" else text[:120]
        self.store.add_occurrence(kind, subject)
        ledger_id = self.ledger.record(kind, source, text, meta)
        if ledger_id is not None:
            self._maybe_compress()
        return ledger_id

    def _maybe_compress(self) -> None:
        now = now_ms()
        unlearned = len(self.ledger.unlearned(limit=self.compress_min_items + 1))
        due = unlearned >= self.compress_min_items or (now - self._last_compress) / 1000.0 >= self.auto_compress_every
        if not due or (self._thread is not None and self._thread.is_alive()):
            return
        self.compress_async()

    def compress_async(self) -> None:
        with self._lock:
            if self._thread is not None and self._thread.is_alive():
                return
            self._thread = threading.Thread(target=self._compress_worker, name="twin-compressor", daemon=True)
            self._thread.start()

    def compressing(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    def _compress_worker(self) -> None:
        try:
            self.compressor.run(max_items=30)
        except Exception:  # noqa: BLE001
            log.exception("auto-compression failed")
        finally:
            self._last_compress = now_ms()

    # -- queries -----------------------------------------------------------
    def ask(self, question: str, k: int = 8) -> dict:
        """Retrieve what the twin knows about a question."""
        hits = self.graph.query(question, k=k)
        return {
            "question": question,
            "hits": [
                {"kind": h.kind, "id": h.id, "text": h.text, "similarity": round(h.similarity, 3), "weight": h.weight}
                for h in hits
            ],
            "context_block": self.graph.context_block(question, k=k),
        }

    def status(self) -> dict:
        ledger = self.ledger.stats()
        graph = self.graph.status()
        gaps = self.gaps()
        return {
            "observations": self.store.counts()["observations"],
            "ledger": ledger,
            "graph": graph,
            "open_gaps": len(gaps),
            "open_prompts": len(self.store.decisions_open()),
        }

    def gaps(self) -> list[dict]:
        out = []
        for row in self.store.gaps_open():
            obs = self.store.get_observation(row["ledger_id"]) if row["ledger_id"] else None
            out.append(
                {
                    "id": row["id"],
                    "created": row["created"],
                    "reason": row["reason"],
                    "observation": (obs["text"][:200] if obs else "") or "",
                }
            )
        return out

    def resolve_gap(self, gap_id: int, note: str = "reviewed") -> None:
        self.store.resolve_gap(gap_id, note)

    def export(self, path: str | Path) -> Path:
        return self.graph.export(path)

    def shutdown(self) -> None:
        if self._bus is not None:
            for sub in self._subs:
                self._bus.unsubscribe(sub)
            self._subs.clear()
