"""SQLite persistence for the digital twin: observations, ledger, graph, gaps."""
from __future__ import annotations

import json
import sqlite3
import threading
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator, Optional

import numpy as np

from ..utils import utcnow

_SCHEMA = """
CREATE TABLE IF NOT EXISTS observations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts TEXT NOT NULL,
    kind TEXT NOT NULL,
    source TEXT NOT NULL,
    text TEXT NOT NULL DEFAULT '',
    meta TEXT NOT NULL DEFAULT '{}',
    digest TEXT NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS ledger (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    obs_id INTEGER NOT NULL REFERENCES observations(id),
    hash TEXT NOT NULL,
    learned_at TEXT,
    gap_due TEXT,
    created TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS entities (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'concept',
    domain TEXT NOT NULL DEFAULT 'general',
    embedding BLOB,
    weight REAL NOT NULL DEFAULT 1.0,
    first_seen TEXT NOT NULL,
    last_seen TEXT NOT NULL,
    sources TEXT NOT NULL DEFAULT '[]',
    UNIQUE(name, kind)
);
CREATE TABLE IF NOT EXISTS facts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    text TEXT NOT NULL,
    summary TEXT NOT NULL DEFAULT '',
    domain TEXT NOT NULL DEFAULT 'general',
    embedding BLOB,
    confidence REAL NOT NULL DEFAULT 0.5,
    weight REAL NOT NULL DEFAULT 1.0,
    source_ids TEXT NOT NULL DEFAULT '[]',
    created TEXT NOT NULL,
    last_seen TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
);
CREATE TABLE IF NOT EXISTS decisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts TEXT NOT NULL,
    kind TEXT NOT NULL,
    subject TEXT NOT NULL,
    question TEXT NOT NULL DEFAULT '',
    answer TEXT NOT NULL DEFAULT '',
    confidence REAL NOT NULL DEFAULT 0.0,
    auto INTEGER NOT NULL DEFAULT 0,
    resolved INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS occurrences (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts TEXT NOT NULL,
    kind TEXT NOT NULL,
    subject TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS relations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    src INTEGER NOT NULL,
    rel TEXT NOT NULL,
    dst INTEGER NOT NULL,
    weight REAL NOT NULL DEFAULT 1.0
);
CREATE TABLE IF NOT EXISTS gaps (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ledger_id INTEGER REFERENCES ledger(id),
    reason TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    created TEXT NOT NULL,
    resolved TEXT
);
CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    started TEXT NOT NULL,
    task TEXT NOT NULL DEFAULT '',
    mode TEXT NOT NULL DEFAULT 'auto',
    model TEXT NOT NULL DEFAULT '',
    steps INTEGER NOT NULL DEFAULT 0,
    outcome TEXT NOT NULL DEFAULT '',
    answer TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS audio_segments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    segment_id TEXT NOT NULL UNIQUE,
    started TEXT NOT NULL,
    ended TEXT NOT NULL,
    duration_s REAL NOT NULL DEFAULT 0.0,
    speech_s REAL NOT NULL DEFAULT 0.0,
    device TEXT NOT NULL DEFAULT '',
    capture_mode TEXT NOT NULL DEFAULT 'loopback',
    wav_path TEXT NOT NULL DEFAULT '',
    transcript TEXT NOT NULL DEFAULT '',
    backend TEXT NOT NULL DEFAULT '',
    language TEXT NOT NULL DEFAULT '',
    confidence REAL,
    created TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_audio_segments_created ON audio_segments(created DESC);
CREATE INDEX IF NOT EXISTS idx_ledger_unlearned ON ledger(learned_at, gap_due);
CREATE INDEX IF NOT EXISTS idx_facts_status ON facts(status, last_seen);
CREATE INDEX IF NOT EXISTS idx_entities_name ON entities(name);
CREATE INDEX IF NOT EXISTS idx_decisions_open ON decisions(resolved, kind);
CREATE INDEX IF NOT EXISTS idx_occurrences ON occurrences(kind, subject);
"""

# Columns added after the initial schema shipped; applied idempotently so
# existing memory.db files migrate in place.
_MIGRATIONS: dict[str, list[str]] = {
    "entities": ["domain TEXT NOT NULL DEFAULT 'general'"],
    "facts": ["domain TEXT NOT NULL DEFAULT 'general'"],
}


def _vec_to_blob(vec: Optional[np.ndarray]) -> Optional[bytes]:
    if vec is None:
        return None
    return np.asarray(vec, dtype=np.float32).tobytes()


def _blob_to_vec(blob: Optional[bytes]) -> Optional[np.ndarray]:
    if not blob:
        return None
    return np.frombuffer(blob, dtype=np.float32)


class Store:
    """Thread-safe SQLite store; a fresh connection per operation (WAL mode)."""

    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self._init()

    def _init(self) -> None:
        with self.conn() as conn:
            conn.executescript(_SCHEMA)
            self._migrate(conn)

    @staticmethod
    def _migrate(conn: sqlite3.Connection) -> None:
        """Add columns introduced after v0.1 for existing databases."""
        for table, columns in _MIGRATIONS.items():
            existing = {row["name"] for row in conn.execute(f"PRAGMA table_info({table})")}
            for column in columns:
                col_name = column.split()[0]
                if col_name not in existing:
                    conn.execute(f"ALTER TABLE {table} ADD COLUMN {column}")

    @contextmanager
    def conn(self) -> Iterator[sqlite3.Connection]:
        conn = sqlite3.connect(str(self.path), timeout=30.0)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA foreign_keys=ON")
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()

    # -- observations ------------------------------------------------------
    def add_observation(self, kind: str, source: str, text: str, meta: Optional[dict] = None, digest: Optional[str] = None) -> int:
        from ..utils import sha1_hex

        digest = digest or sha1_hex(f"{kind}|{source}|{text}")
        with self._lock, self.conn() as conn:
            existing = conn.execute("SELECT id FROM observations WHERE digest=?", (digest,)).fetchone()
            if existing:
                return int(existing["id"])
            cur = conn.execute(
                "INSERT INTO observations (ts, kind, source, text, meta, digest) VALUES (?,?,?,?,?,?)",
                (utcnow(), kind, source, text, json.dumps(meta or {}, ensure_ascii=False), digest),
            )
            return int(cur.lastrowid)

    def get_observation(self, obs_id: int) -> Optional[sqlite3.Row]:
        with self.conn() as conn:
            return conn.execute("SELECT * FROM observations WHERE id=?", (obs_id,)).fetchone()

    # -- ledger ------------------------------------------------------------
    def add_ledger(self, obs_id: int, gap_due: str, hash: str) -> Optional[int]:
        with self._lock, self.conn() as conn:
            exists = conn.execute("SELECT id FROM ledger WHERE hash=?", (hash,)).fetchone()
            if exists:
                return None
            cur = conn.execute(
                "INSERT INTO ledger (obs_id, hash, gap_due, created) VALUES (?,?,?,?)",
                (obs_id, hash, gap_due, utcnow()),
            )
            return int(cur.lastrowid)

    def ledger_unlearned(self, limit: int = 50) -> list[sqlite3.Row]:
        with self.conn() as conn:
            rows = conn.execute(
                """
                SELECT l.*, o.kind, o.source, o.text, o.meta FROM ledger l
                JOIN observations o ON o.id = l.obs_id
                WHERE l.learned_at IS NULL ORDER BY l.created ASC LIMIT ?
                """,
                (limit,),
            ).fetchall()
            return list(rows)

    def ledger_due_gaps(self) -> list[sqlite3.Row]:
        now = utcnow()
        with self.conn() as conn:
            return list(
                conn.execute(
                    "SELECT * FROM ledger WHERE learned_at IS NULL AND gap_due <= ?", (now,)
                ).fetchall()
            )

    def mark_learned(self, ledger_ids: list[int]) -> None:
        if not ledger_ids:
            return
        now = utcnow()
        with self._lock, self.conn() as conn:
            conn.executemany(
                "UPDATE ledger SET learned_at=? WHERE id=?", [(now, lid) for lid in ledger_ids]
            )

    def ledger_stats(self) -> dict:
        with self.conn() as conn:
            row = conn.execute(
                "SELECT COUNT(*) AS n, SUM(CASE WHEN learned_at IS NOT NULL THEN 1 ELSE 0 END) AS learned FROM ledger"
            ).fetchone()
        return {"total": row["n"] or 0, "learned": row["learned"] or 0}

    # -- entities ----------------------------------------------------------
    def upsert_entity(
        self,
        name: str,
        kind: str,
        weight_delta: float = 1.0,
        source: Optional[str] = None,
        domain: str = "general",
    ) -> int:
        now = utcnow()
        with self._lock, self.conn() as conn:
            row = conn.execute("SELECT * FROM entities WHERE name=? AND kind=?", (name, kind)).fetchone()
            if row:
                sources = json.loads(row["sources"])
                if source and source not in sources:
                    sources.append(source)
                new_domain = domain if row["domain"] == "general" and domain != "general" else row["domain"]
                conn.execute(
                    "UPDATE entities SET weight=weight+?, last_seen=?, sources=?, domain=? WHERE id=?",
                    (weight_delta, now, json.dumps(sources), new_domain, row["id"]),
                )
                return int(row["id"])
            cur = conn.execute(
                "INSERT INTO entities (name, kind, domain, weight, first_seen, last_seen, sources) VALUES (?,?,?,?,?,?,?)",
                (name, kind, domain, weight_delta, now, now, json.dumps([source] if source else [])),
            )
            return int(cur.lastrowid)

    def entity_by_name(self, name: str) -> Optional[sqlite3.Row]:
        with self.conn() as conn:
            return conn.execute("SELECT * FROM entities WHERE name=? LIMIT 1", (name,)).fetchone()

    def entities_all(self, min_weight: float = 0.0) -> list[sqlite3.Row]:
        with self.conn() as conn:
            return list(
                conn.execute("SELECT * FROM entities WHERE weight>=? ORDER BY weight DESC", (min_weight,)).fetchall()
            )

    def set_entity_embedding(self, entity_id: int, vec: np.ndarray) -> None:
        with self._lock, self.conn() as conn:
            conn.execute("UPDATE entities SET embedding=? WHERE id=?", (_vec_to_blob(vec), entity_id))

    # -- facts -------------------------------------------------------------
    def add_fact(
        self,
        text: str,
        summary: str,
        embedding: Optional[np.ndarray],
        confidence: float,
        source_ids: list[int],
        domain: str = "general",
    ) -> int:
        now = utcnow()
        with self._lock, self.conn() as conn:
            cur = conn.execute(
                "INSERT INTO facts (text, summary, domain, embedding, confidence, source_ids, created, last_seen, status) "
                "VALUES (?,?,?,?,?,?,?,?,'active')",
                (text, summary, domain, _vec_to_blob(embedding), confidence, json.dumps(source_ids), now, now),
            )
            return int(cur.lastrowid)

    def facts_active(self, domain: Optional[str] = None) -> list[sqlite3.Row]:
        with self.conn() as conn:
            if domain:
                return list(conn.execute("SELECT * FROM facts WHERE status='active' AND domain=?", (domain,)).fetchall())
            return list(conn.execute("SELECT * FROM facts WHERE status='active'").fetchall())

    def facts_count(self) -> int:
        with self.conn() as conn:
            return int(conn.execute("SELECT COUNT(*) AS n FROM facts WHERE status='active'").fetchone()["n"])

    def get_fact(self, fact_id: int) -> Optional[sqlite3.Row]:
        with self.conn() as conn:
            return conn.execute("SELECT * FROM facts WHERE id=?", (fact_id,)).fetchone()

    def reinforce_fact(self, fact_id: int, delta: float = 1.0, summary: Optional[str] = None) -> None:
        now = utcnow()
        with self._lock, self.conn() as conn:
            conn.execute(
                "UPDATE facts SET weight=weight+?, last_seen=?, summary=COALESCE(?, summary) WHERE id=?",
                (delta, now, summary, fact_id),
            )

    def add_fact_source(self, fact_id: int, source_id: int) -> None:
        with self._lock, self.conn() as conn:
            row = conn.execute("SELECT source_ids FROM facts WHERE id=?", (fact_id,)).fetchone()
            if row:
                sources = json.loads(row["source_ids"])
                if source_id not in sources:
                    sources.append(source_id)
                    conn.execute("UPDATE facts SET source_ids=? WHERE id=?", (json.dumps(sources), fact_id))

    def archive_fact(self, fact_id: int) -> None:
        with self._lock, self.conn() as conn:
            conn.execute("UPDATE facts SET status='archived' WHERE id=?", (fact_id,))

    def set_fact_summary(self, fact_id: int, summary: str) -> None:
        with self._lock, self.conn() as conn:
            conn.execute("UPDATE facts SET summary=? WHERE id=?", (summary, fact_id))

    # -- relations ---------------------------------------------------------
    def add_relation(self, src: int, rel: str, dst: int, weight: float = 1.0) -> None:
        with self._lock, self.conn() as conn:
            exists = conn.execute(
                "SELECT id FROM relations WHERE src=? AND rel=? AND dst=?", (src, rel, dst)
            ).fetchone()
            if exists:
                conn.execute("UPDATE relations SET weight=weight+? WHERE id=?", (weight, exists["id"]))
            else:
                conn.execute(
                    "INSERT INTO relations (src, rel, dst, weight) VALUES (?,?,?,?)", (src, rel, dst, weight)
                )

    def relations_all(self) -> list[sqlite3.Row]:
        with self.conn() as conn:
            return list(conn.execute("SELECT * FROM relations").fetchall())

    # -- gaps --------------------------------------------------------------
    def add_gap(self, ledger_id: int, reason: str, note: str = "") -> int:
        """Create a gap if not already open. Returns new gap id, or 0 if an
        unresolved gap for this ledger item already exists."""
        with self._lock, self.conn() as conn:
            exists = conn.execute(
                "SELECT id FROM gaps WHERE ledger_id=? AND resolved IS NULL", (ledger_id,)
            ).fetchone()
            if exists:
                return 0
            cur = conn.execute(
                "INSERT INTO gaps (ledger_id, reason, note, created) VALUES (?,?,?,?)",
                (ledger_id, reason, note, utcnow()),
            )
            return int(cur.lastrowid)

    def gaps_open(self) -> list[sqlite3.Row]:
        with self.conn() as conn:
            return list(conn.execute("SELECT * FROM gaps WHERE resolved IS NULL ORDER BY created").fetchall())

    def resolve_gap(self, gap_id: int, note: str = "") -> None:
        with self._lock, self.conn() as conn:
            conn.execute("UPDATE gaps SET resolved=?, note=? WHERE id=?", (utcnow(), note, gap_id))

    # -- captured audio ----------------------------------------------------
    def add_audio_segment(
        self,
        segment_id: str,
        started: str,
        ended: str,
        duration_s: float,
        speech_s: float,
        device: str,
        capture_mode: str,
        wav_path: str,
        transcript: str,
        backend: str = "",
        language: str = "",
        confidence: Optional[float] = None,
    ) -> int:
        """Persist one finalized audio segment and its transcript."""
        with self._lock, self.conn() as conn:
            cur = conn.execute(
                "INSERT OR REPLACE INTO audio_segments "
                "(segment_id, started, ended, duration_s, speech_s, device, capture_mode, wav_path, "
                "transcript, backend, language, confidence, created) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (
                    segment_id,
                    started,
                    ended,
                    duration_s,
                    speech_s,
                    device,
                    capture_mode,
                    wav_path,
                    transcript,
                    backend,
                    language,
                    confidence,
                    utcnow(),
                ),
            )
            return int(cur.lastrowid)

    def audio_segments_recent(self, limit: int = 50) -> list[sqlite3.Row]:
        with self.conn() as conn:
            return list(conn.execute("SELECT * FROM audio_segments ORDER BY id DESC LIMIT ?", (limit,)).fetchall())

    def get_audio_segment(self, segment_id: str) -> Optional[sqlite3.Row]:
        with self.conn() as conn:
            return conn.execute("SELECT * FROM audio_segments WHERE segment_id=?", (segment_id,)).fetchone()

    def audio_insights(self) -> dict:
        """Explain what captured audio contributed to memory and the graph."""
        with self.conn() as conn:
            totals = conn.execute(
                "SELECT COUNT(*) AS segments, COALESCE(SUM(duration_s),0) AS duration_s, "
                "SUM(CASE WHEN transcript != '' THEN 1 ELSE 0 END) AS transcribed FROM audio_segments"
            ).fetchone()
            observations = conn.execute("SELECT COUNT(*) AS n FROM observations WHERE kind='audio'").fetchone()["n"]
            ledger = conn.execute(
                "SELECT COUNT(*) AS total, SUM(CASE WHEN l.learned_at IS NOT NULL THEN 1 ELSE 0 END) AS learned "
                "FROM ledger l JOIN observations o ON o.id=l.obs_id WHERE o.kind='audio'"
            ).fetchone()
            fact_rows = conn.execute(
                "SELECT DISTINCT f.id, f.text, f.domain, f.confidence, f.weight, f.last_seen "
                "FROM facts f JOIN json_each(f.source_ids) src "
                "JOIN ledger l ON l.id=src.value JOIN observations o ON o.id=l.obs_id "
                "WHERE o.kind='audio' AND f.status='active' ORDER BY f.last_seen DESC LIMIT 100"
            ).fetchall()
            domains = conn.execute(
                "SELECT f.domain, COUNT(DISTINCT f.id) AS n FROM facts f JOIN json_each(f.source_ids) src "
                "JOIN ledger l ON l.id=src.value JOIN observations o ON o.id=l.obs_id "
                "WHERE o.kind='audio' AND f.status='active' GROUP BY f.domain ORDER BY n DESC"
            ).fetchall()
        return {
            "segments": int(totals["segments"] or 0),
            "transcribed": int(totals["transcribed"] or 0),
            "duration_s": round(float(totals["duration_s"] or 0.0), 2),
            "audio_observations": int(observations or 0),
            "ledger_total": int(ledger["total"] or 0),
            "ledger_learned": int(ledger["learned"] or 0),
            "facts": [{k: row[k] for k in row.keys()} for row in fact_rows],
            "domains": {row["domain"]: int(row["n"]) for row in domains},
        }

    # -- sessions ----------------------------------------------------------
    def session_add(
        self, session_id: str, task: str, mode: str = "auto", model: str = ""
    ) -> None:
        with self._lock, self.conn() as conn:
            conn.execute(
                "INSERT INTO sessions (session_id, started, task, mode, model) VALUES (?,?,?,?,?)",
                (session_id, utcnow(), task, mode, model),
            )

    def session_finish(self, session_id: str, outcome: str, steps: int, answer: str) -> None:
        with self._lock, self.conn() as conn:
            conn.execute(
                "UPDATE sessions SET outcome=?, steps=?, answer=? WHERE session_id=?",
                (outcome, steps, answer[:4000], session_id),
            )

    # -- decisions (autonomy prompts & pattern confirmations) ---------------
    def add_decision(self, kind: str, subject: str, question: str = "", confidence: float = 0.0) -> int:
        with self._lock, self.conn() as conn:
            cur = conn.execute(
                "INSERT INTO decisions (ts, kind, subject, question, confidence, resolved) VALUES (?,?,?,?,?,0)",
                (utcnow(), kind, subject, question, confidence),
            )
            return int(cur.lastrowid)

    def decisions_open(self, kind: Optional[str] = None) -> list[sqlite3.Row]:
        with self.conn() as conn:
            if kind:
                return list(conn.execute("SELECT * FROM decisions WHERE resolved=0 AND kind=? ORDER BY id", (kind,)).fetchall())
            return list(conn.execute("SELECT * FROM decisions WHERE resolved=0 ORDER BY id").fetchall())

    def decisions_for(self, kind: str, subject: str, answer: Optional[str] = None) -> list[sqlite3.Row]:
        with self.conn() as conn:
            if answer is not None:
                return list(
                    conn.execute(
                        "SELECT * FROM decisions WHERE kind=? AND subject=? AND answer=? AND resolved=1",
                        (kind, subject, answer),
                    ).fetchall()
                )
            return list(
                conn.execute("SELECT * FROM decisions WHERE kind=? AND subject=? AND resolved=1", (kind, subject)).fetchall()
            )

    def decisions_for_answer(self, kind: str, answer: str) -> list[sqlite3.Row]:
        """All resolved decisions with a given answer (domain confirmation counts)."""
        with self.conn() as conn:
            return list(
                conn.execute(
                    "SELECT * FROM decisions WHERE kind=? AND answer=? AND resolved=1", (kind, answer)
                ).fetchall()
            )

    def decisions_resolved(self, kind: str) -> list[sqlite3.Row]:
        with self.conn() as conn:
            return list(
                conn.execute("SELECT * FROM decisions WHERE kind=? AND resolved=1", (kind,)).fetchall()
            )

    def resolve_decision(self, decision_id: int, answer: str, auto: bool = False, confidence: float = 1.0) -> bool:
        with self._lock, self.conn() as conn:
            row = conn.execute("SELECT * FROM decisions WHERE id=?", (decision_id,)).fetchone()
            if row is None or row["resolved"]:
                return False
            conn.execute(
                "UPDATE decisions SET answer=?, auto=?, confidence=?, resolved=1 WHERE id=?",
                (answer, 1 if auto else 0, confidence, decision_id),
            )
            return True

    def get_decision(self, decision_id: int) -> Optional[sqlite3.Row]:
        with self.conn() as conn:
            return conn.execute("SELECT * FROM decisions WHERE id=?", (decision_id,)).fetchone()

    def add_occurrence(self, kind: str, subject: str) -> None:
        """Record every occurrence of an event, even when content dedupes
        elsewhere. Powers pattern detection (how often each app is focused)."""
        if not subject:
            return
        with self._lock, self.conn() as conn:
            conn.execute(
                "INSERT INTO occurrences (ts, kind, subject) VALUES (?,?,?)",
                (utcnow(), kind, subject[:120]),
            )

    def window_app_counts(self, min_count: int = 2) -> list[sqlite3.Row]:
        """How often each app has been the focused window."""
        with self.conn() as conn:
            return list(
                conn.execute(
                    "SELECT subject AS app, COUNT(*) AS n, MAX(ts) AS last_seen "
                    "FROM occurrences WHERE kind='window' AND subject != '' "
                    "GROUP BY subject HAVING n >= ? ORDER BY n DESC",
                    (min_count,),
                ).fetchall()
            )

    def domains(self) -> list[sqlite3.Row]:
        """Active-fact counts per knowledge domain (the hierarchy)."""
        with self.conn() as conn:
            return list(
                conn.execute(
                    "SELECT domain, COUNT(*) AS n FROM facts WHERE status='active' GROUP BY domain ORDER BY n DESC"
                ).fetchall()
            )

    # -- misc --------------------------------------------------------------
    def counts(self) -> dict:
        with self.conn() as conn:
            out = {}
            for table in ("observations", "ledger", "entities", "facts", "relations", "gaps", "sessions", "audio_segments"):
                out[table] = int(conn.execute(f"SELECT COUNT(*) AS n FROM {table}").fetchone()["n"])
            return out
