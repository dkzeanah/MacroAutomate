"""SQLite storage and vector search for knowledge elements.

Vector backends, chosen at open time:

* ``sqlite-vec``  the vec0 virtual table (cosine KNN) when the extension loads.
* ``python``      a self-coded ``vec_cosine(a, b)`` SQL function, with FTS5
                  full-text recall to keep large stores fast.

``element.embedding`` always holds the float32 vector, so the vec0 index can be
rebuilt at any time; switching backends never loses data.
"""
from __future__ import annotations

import json
import math
import sqlite3
import time
from pathlib import Path

from . import embed

SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE IF NOT EXISTS source (
    id INTEGER PRIMARY KEY, path TEXT UNIQUE, kind TEXT, title TEXT, size INTEGER, mtime REAL, sha256 TEXT,
    added TEXT, updated TEXT, status TEXT, error TEXT DEFAULT '', pages INTEGER DEFAULT 0, elements INTEGER DEFAULT 0,
    method TEXT DEFAULT '', origin TEXT DEFAULT '');
CREATE TABLE IF NOT EXISTS element (
    id INTEGER PRIMARY KEY, hash TEXT UNIQUE, text TEXT, roots TEXT, head_id INTEGER DEFAULT 0, head_score REAL DEFAULT 0,
    complexity REAL DEFAULT 0, level INTEGER DEFAULT 1, definitional INTEGER DEFAULT 0, seq INTEGER DEFAULT 0,
    count INTEGER DEFAULT 1, created TEXT, updated TEXT, embedding BLOB, model TEXT DEFAULT '');
CREATE INDEX IF NOT EXISTS ix_element_head ON element(head_id, seq);
CREATE TABLE IF NOT EXISTS element_source (element_id INTEGER, source_id INTEGER, locator TEXT,
    PRIMARY KEY (element_id, source_id, locator));
CREATE INDEX IF NOT EXISTS ix_element_source_source ON element_source(source_id);
CREATE TABLE IF NOT EXISTS lexicon (root TEXT PRIMARY KEY, df INTEGER DEFAULT 0, tf INTEGER DEFAULT 0,
    sources INTEGER DEFAULT 0, forms TEXT DEFAULT '{}', ctx BLOB, updated TEXT);
CREATE TABLE IF NOT EXISTS head (id INTEGER PRIMARY KEY, name TEXT, aliases TEXT DEFAULT '[]', roots TEXT DEFAULT '[]',
    phrases TEXT DEFAULT '[]', centroid BLOB, elements INTEGER DEFAULT 0, sources INTEGER DEFAULT 0,
    locked INTEGER DEFAULT 0, created TEXT, updated TEXT);
CREATE TABLE IF NOT EXISTS head_root (root TEXT PRIMARY KEY, head_id INTEGER, weight REAL);
CREATE VIRTUAL TABLE IF NOT EXISTS element_fts USING fts5(text, roots, tokenize='unicode61');
"""


def now() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def _vec_cosine(a, b):
    if a is None or b is None:
        return None
    va, vb = embed.unpack(a), embed.unpack(b)
    return embed.cosine(va, vb)


class Store:
    def __init__(self, path: str | Path, *, prefer_extension: bool = True):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(self.path), timeout=30)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=NORMAL")
        self.db.executescript(SCHEMA)
        self.db.create_function("vec_cosine", 2, _vec_cosine, deterministic=True)
        self.backend, self.backend_detail = "python", "built-in vec_cosine() SQL function + FTS5 recall"
        if prefer_extension:
            self._load_extension()
        self.db.commit()

    # ─── setup ────────────────────────────────────────────────────────────

    def _load_extension(self):
        try:
            import sqlite_vec  # type: ignore
            self.db.enable_load_extension(True)
            sqlite_vec.load(self.db)
            self.db.enable_load_extension(False)
            version = self.db.execute("SELECT vec_version()").fetchone()[0]
            self.db.execute(f"CREATE VIRTUAL TABLE IF NOT EXISTS element_vec USING vec0(embedding float[{embed.DIM}] distance_metric=cosine)")
            self.backend, self.backend_detail = "sqlite-vec", f"sqlite-vec {version} (vec0, cosine)"
            if self.meta("vec_dirty", "0") == "1":
                self.rebuild_index()
        except Exception as error:  # extension missing or refused: the built-in path still works
            self.backend_detail = f"built-in vec_cosine() SQL function + FTS5 recall (sqlite-vec unavailable: {type(error).__name__})"

    def close(self):
        self.db.commit()
        self.db.close()

    def meta(self, key: str, default: str = "") -> str:
        row = self.db.execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
        return row[0] if row else default

    def set_meta(self, key: str, value) -> None:
        self.db.execute("INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, str(value)))

    # ─── elements and the vector index ────────────────────────────────────

    def index_vector(self, element_id: int, blob: bytes) -> None:
        if self.backend == "sqlite-vec":
            self.db.execute("DELETE FROM element_vec WHERE rowid=?", (element_id,))
            self.db.execute("INSERT INTO element_vec(rowid, embedding) VALUES (?, ?)", (element_id, blob))
        else:
            self.set_meta("vec_dirty", "1")  # a vec0 index (if ever loaded) needs a rebuild

    def unindex(self, element_ids: list[int]) -> None:
        for element_id in element_ids:
            if self.backend == "sqlite-vec":
                self.db.execute("DELETE FROM element_vec WHERE rowid=?", (element_id,))
            self.db.execute("DELETE FROM element_fts WHERE rowid=?", (element_id,))
        if self.backend != "sqlite-vec" and element_ids:
            self.set_meta("vec_dirty", "1")

    def rebuild_index(self) -> int:
        if self.backend != "sqlite-vec":
            return 0
        self.db.execute("DELETE FROM element_vec")
        count = 0
        for row in self.db.execute("SELECT id, embedding FROM element WHERE embedding IS NOT NULL").fetchall():
            self.db.execute("INSERT INTO element_vec(rowid, embedding) VALUES (?, ?)", (row["id"], row["embedding"]))
            count += 1
        self.set_meta("vec_dirty", "0")
        return count

    def index_text(self, element_id: int, text: str, roots: list[str]) -> None:
        self.db.execute("DELETE FROM element_fts WHERE rowid=?", (element_id,))
        self.db.execute("INSERT INTO element_fts(rowid, text, roots) VALUES (?, ?, ?)", (element_id, text, " ".join(roots)))

    def element_count(self) -> int:
        return self.db.execute("SELECT COUNT(*) FROM element").fetchone()[0]

    # ─── search ───────────────────────────────────────────────────────────

    def knn(self, vector: list, k: int = 10, head_id: int | None = None) -> list[tuple[int, float]]:
        """[(element_id, cosine similarity)] best first."""
        blob = embed.pack(vector)
        if self.backend == "sqlite-vec":
            fetch = min(4096, k * (8 if head_id is not None else 1))
            rows = self.db.execute("SELECT rowid, distance FROM element_vec WHERE embedding MATCH ? AND k = ?", (blob, fetch)).fetchall()
            hits = [(r[0], 1.0 - r[1]) for r in rows]
            if head_id is not None:
                allowed = {r[0] for r in self.db.execute(
                    f"SELECT id FROM element WHERE head_id=? AND id IN ({','.join('?' * len(hits))})", (head_id, *[h[0] for h in hits])
                ).fetchall()} if hits else set()
                hits = [h for h in hits if h[0] in allowed]
            return hits[:k]
        where, args = ("WHERE head_id=?", [head_id]) if head_id is not None else ("", [])
        rows = self.db.execute(f"SELECT id, vec_cosine(embedding, ?) AS score FROM element {where} ORDER BY score DESC LIMIT ?",
                               (blob, *args, k)).fetchall()
        return [(r["id"], r["score"] or 0.0) for r in rows]

    def keyword(self, roots: list[str], k: int = 50, head_id: int | None = None) -> list[tuple[int, float]]:
        terms = [r for r in dict.fromkeys(roots) if r.isalnum()][:24]
        if not terms:
            return []
        query = " OR ".join(f'"{t}"' for t in terms)
        sql = "SELECT element_fts.rowid AS id, bm25(element_fts) AS rank FROM element_fts WHERE element_fts MATCH ?"
        args: list = [f"roots:({query})"]
        if head_id is not None:
            sql += " AND element_fts.rowid IN (SELECT id FROM element WHERE head_id=?)"
            args.append(head_id)
        rows = self.db.execute(sql + " ORDER BY rank LIMIT ?", (*args, k)).fetchall()
        if not rows:
            return []
        best = min(r["rank"] for r in rows)  # bm25: more negative is better
        return [(r["id"], (r["rank"] / best) if best else 0.0) for r in rows]

    def hybrid(self, vector: list, roots: list[str], k: int = 10, head_id: int | None = None) -> list[tuple[int, float]]:
        """Vector similarity blended with keyword evidence (recall from both)."""
        dense = dict(self.knn(vector, max(k * 4, 40), head_id))
        sparse = dict(self.keyword(roots, max(k * 4, 40), head_id))
        missing = [i for i in sparse if i not in dense]
        if missing:
            blob = embed.pack(vector)
            for row in self.db.execute(f"SELECT id, vec_cosine(embedding, ?) FROM element WHERE id IN ({','.join('?' * len(missing))})",
                                       (blob, *missing)).fetchall():
                dense[row[0]] = row[1] or 0.0
        scored = [(i, 0.72 * dense.get(i, 0.0) + 0.28 * sparse.get(i, 0.0)) for i in set(dense) | set(sparse)]
        scored.sort(key=lambda x: x[1], reverse=True)
        return scored[:k]

    def elements(self, ids: list[int]) -> list[dict]:
        if not ids:
            return []
        rows = self.db.execute(f"SELECT * FROM element WHERE id IN ({','.join('?' * len(ids))})", ids).fetchall()
        by_id = {r["id"]: dict(r) for r in rows}
        out = []
        for element_id in ids:
            row = by_id.get(element_id)
            if row:
                row.pop("embedding", None)
                row["roots"] = json.loads(row["roots"] or "[]")
                row["sources"] = self.element_sources(element_id)
                out.append(row)
        return out

    def element_sources(self, element_id: int, limit: int = 5) -> list[dict]:
        return [dict(r) for r in self.db.execute(
            "SELECT s.title, s.path, es.locator FROM element_source es JOIN source s ON s.id=es.source_id "
            "WHERE es.element_id=? LIMIT ?", (element_id, limit)).fetchall()]

    # ─── lexicon ──────────────────────────────────────────────────────────

    def load_lexicon(self, with_context: bool = True) -> tuple[dict, dict, dict, dict]:
        """(df, tf, forms, contexts)."""
        df, tf, forms, contexts = {}, {}, {}, {}
        columns = "root, df, tf, forms" + (", ctx" if with_context else "")
        for row in self.db.execute(f"SELECT {columns} FROM lexicon"):
            df[row["root"]] = row["df"]
            tf[row["root"]] = row["tf"]
            forms[row["root"]] = row["forms"]
            if with_context and row["ctx"]:
                contexts[row["root"]] = embed.unpack(row["ctx"])
        return df, tf, forms, contexts

    def save_lexicon(self, df, tf, forms, contexts, sources, touched: set[str]) -> None:
        stamp = now()
        rows = []
        for root in touched:
            ctx = contexts.get(root)
            form_map = forms.get(root, {})
            if isinstance(form_map, dict) and len(form_map) > 12:
                form_map = dict(sorted(form_map.items(), key=lambda kv: kv[1], reverse=True)[:12])
            rows.append((root, df.get(root, 0), tf.get(root, 0), sources.get(root, 0),
                         json.dumps(form_map) if isinstance(form_map, dict) else form_map,
                         embed.pack_half(ctx) if ctx is not None else None, stamp))
        self.db.executemany("INSERT INTO lexicon(root,df,tf,sources,forms,ctx,updated) VALUES(?,?,?,?,?,?,?) "
                            "ON CONFLICT(root) DO UPDATE SET df=excluded.df, tf=excluded.tf, sources=excluded.sources, "
                            "forms=excluded.forms, ctx=excluded.ctx, updated=excluded.updated", rows)

    def stats(self) -> dict:
        def one(sql):
            return self.db.execute(sql).fetchone()[0]
        size = self.path.stat().st_size if self.path.exists() else 0
        return {"elements": one("SELECT COUNT(*) FROM element"), "sources": one("SELECT COUNT(*) FROM source WHERE status='ok'"),
                "failed_sources": one("SELECT COUNT(*) FROM source WHERE status='error'"),
                "roots": one("SELECT COUNT(*) FROM lexicon"), "heads": one("SELECT COUNT(*) FROM head"),
                "unsorted": one("SELECT COUNT(*) FROM element WHERE head_id=0"),
                "backend": self.backend, "backend_detail": self.backend_detail, "model": embed.MODEL,
                "database": str(self.path), "megabytes": round(size / 1048576, 1),
                "last_discovery": self.meta("last_discovery", "never")}


def safe_json(value, default):
    try:
        return json.loads(value) if value else default
    except (TypeError, ValueError):
        return default


def log_scale(value: float) -> float:
    return math.log1p(max(0.0, value))
