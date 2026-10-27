"""Observation ledger: what appeared on the computer and had a chance to be learned."""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from ..utils import sha1_hex, utcnow
from .store import Store

log = logging.getLogger("sidelearner.ledger")

# Minimum text length for an observation to count as a learning opportunity.
OPPORTUNITY_MIN_CHARS = 30


def _due_iso(minutes: float) -> str:
    return (datetime.now(timezone.utc) + timedelta(minutes=minutes)).isoformat(timespec="seconds")


class Ledger:
    """Records every perceived item; tracks which ones got learned and which
    became gaps — data that *should* have been learned but was not captured."""

    def __init__(self, store: Store, gap_minutes: float = 10.0) -> None:
        self.store = store
        self.gap_minutes = float(gap_minutes)

    def record(
        self,
        kind: str,
        source: str,
        text: str,
        meta: Optional[dict] = None,
        opportunity: bool = True,
    ) -> Optional[int]:
        """Persist an observation and open a ledger entry for it.

        Returns the ledger id, or None when the identical item was already
        recorded (deduplicated by content digest).
        """
        text = (text or "").strip()
        if not text and not meta:
            return None
        is_opportunity = opportunity and len(text) >= OPPORTUNITY_MIN_CHARS
        obs_id = self.store.add_observation(kind, source, text, meta or {})
        hash = sha1_hex(f"{kind}|{source}|{text}|{is_opportunity}")
        gap_due = _due_iso(self.gap_minutes) if is_opportunity else _due_iso(self.gap_minutes * 6)
        return self.store.add_ledger(obs_id, gap_due, hash)

    def unlearned(self, limit: int = 50) -> list:
        """Unlearned ledger rows (oldest first) with their observation text."""
        return self.store.ledger_unlearned(limit)

    def mark_learned(self, ledger_ids: list[int]) -> None:
        if ledger_ids:
            self.store.mark_learned(ledger_ids)

    def due_gaps(self) -> list:
        """Opportunities whose learning window expired without a learned fact."""
        return self.store.ledger_due_gaps()

    def stats(self) -> dict:
        base = self.store.ledger_stats()
        total = base["total"]
        base["learned_pct"] = round(100.0 * base["learned"] / total, 1) if total else 0.0
        return base
