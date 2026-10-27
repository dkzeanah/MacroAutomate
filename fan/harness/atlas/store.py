"""SQLite persistence for the whole map: projects, symbols, edges, ledger, settings.

One database holds the universe. It is the queryable form of what ATLAS.md and the
INDEX.md files render as text -- the text is for LLMs, this is for the GUI and the CLI.
"""

from __future__ import annotations

import json
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Iterator

from .spec import ATLAS_DIR, DB_NAME

SCHEMA = """
CREATE TABLE IF NOT EXISTS projects (
    id           INTEGER PRIMARY KEY,
    name         TEXT NOT NULL UNIQUE,
    root         TEXT NOT NULL,
    bucket       TEXT NOT NULL DEFAULT 'misc',
    priority     INTEGER NOT NULL DEFAULT 50,
    pinned       INTEGER NOT NULL DEFAULT 0,
    external     INTEGER NOT NULL DEFAULT 0,
    summary      TEXT NOT NULL DEFAULT '',
    verdict      TEXT NOT NULL DEFAULT '',
    file_count   INTEGER NOT NULL DEFAULT 0,
    line_count   INTEGER NOT NULL DEFAULT 0,
    symbol_count INTEGER NOT NULL DEFAULT 0,
    indexed_at   TEXT NOT NULL DEFAULT '',
    created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS files (
    id         INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    path       TEXT NOT NULL,
    line_count INTEGER NOT NULL DEFAULT 0,
    file_hash  TEXT NOT NULL DEFAULT '',
    error      TEXT NOT NULL DEFAULT '',
    UNIQUE (project_id, path)
);

CREATE TABLE IF NOT EXISTS symbols (
    id          INTEGER PRIMARY KEY,
    project_id  INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    path        TEXT NOT NULL,
    name        TEXT NOT NULL,
    kind        TEXT NOT NULL,
    line_start  INTEGER NOT NULL,
    line_end    INTEGER NOT NULL,
    signature   TEXT NOT NULL DEFAULT '',
    body_hash   TEXT NOT NULL DEFAULT '',
    doc         TEXT NOT NULL DEFAULT '',
    calls       TEXT NOT NULL DEFAULT '',
    called_by   TEXT NOT NULL DEFAULT '',
    flags       TEXT NOT NULL DEFAULT '',
    address     TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_symbols_project ON symbols(project_id);
CREATE INDEX IF NOT EXISTS idx_symbols_name    ON symbols(name);
CREATE INDEX IF NOT EXISTS idx_symbols_address ON symbols(address);

CREATE TABLE IF NOT EXISTS ledger (
    id         INTEGER PRIMARY KEY,
    ts         TEXT NOT NULL DEFAULT (datetime('now')),
    action     TEXT NOT NULL,
    address    TEXT NOT NULL DEFAULT '',
    detail     TEXT NOT NULL DEFAULT '',
    backup_dir TEXT NOT NULL DEFAULT '',
    payload    TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS entities (
    id          INTEGER PRIMARY KEY,
    project_id  INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    kind        TEXT NOT NULL,
    path        TEXT NOT NULL DEFAULT '',
    symbol      TEXT NOT NULL DEFAULT '',
    summary     TEXT NOT NULL DEFAULT '',
    run_mode    TEXT NOT NULL DEFAULT 'import',
    run_target  TEXT NOT NULL DEFAULT '',
    run_args    TEXT NOT NULL DEFAULT '',
    evidence    TEXT NOT NULL DEFAULT '',
    line        INTEGER NOT NULL DEFAULT 0,
    confidence  REAL NOT NULL DEFAULT 0.5,
    pinned      INTEGER NOT NULL DEFAULT 0,
    runs        INTEGER NOT NULL DEFAULT 0,
    last_run    TEXT NOT NULL DEFAULT '',
    UNIQUE (project_id, kind, name)
);
CREATE INDEX IF NOT EXISTS idx_entities_project ON entities(project_id);
CREATE INDEX IF NOT EXISTS idx_entities_kind    ON entities(kind);
"""

DEFAULT_SETTINGS = {
    "ollama_url": "http://localhost:11434/api/generate",
    "ollama_model": "llama3.1",
    "scan_root": str(Path.home() / "Desktop"),
    "hot_folder": "",
    "max_symbol_lines": "80",
}


@dataclass
class ProjectRow:
    id: int
    name: str
    root: str
    bucket: str
    priority: int
    pinned: int
    external: int
    summary: str
    verdict: str
    file_count: int
    line_count: int
    symbol_count: int
    indexed_at: str

    @classmethod
    def from_row(cls, row: sqlite3.Row) -> "ProjectRow":
        return cls(
            id=row["id"], name=row["name"], root=row["root"], bucket=row["bucket"],
            priority=row["priority"], pinned=row["pinned"], external=row["external"],
            summary=row["summary"], verdict=row["verdict"], file_count=row["file_count"],
            line_count=row["line_count"], symbol_count=row["symbol_count"],
            indexed_at=row["indexed_at"],
        )


class Store:
    """Thin, explicit SQLite wrapper. No ORM, no magic, no surprises."""

    def __init__(self, workspace: Path) -> None:
        self.workspace = Path(workspace)
        self.dir = self.workspace / ATLAS_DIR
        self.dir.mkdir(parents=True, exist_ok=True)
        self.path = self.dir / DB_NAME
        self.conn = sqlite3.connect(self.path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA foreign_keys = ON")
        self.conn.executescript(SCHEMA)
        self._seed()

    # ------------------------------------------------------------------ plumbing
    def _seed(self) -> None:
        for key, value in DEFAULT_SETTINGS.items():
            self.conn.execute(
                "INSERT OR IGNORE INTO settings(key, value) VALUES (?, ?)", (key, value)
            )
        self.conn.commit()

    @contextmanager
    def tx(self) -> Iterator[sqlite3.Connection]:
        try:
            yield self.conn
            self.conn.commit()
        except Exception:
            self.conn.rollback()
            raise

    def execute(self, sql: str, params: Iterable[Any] = ()) -> sqlite3.Cursor:
        cur = self.conn.execute(sql, tuple(params))
        self.conn.commit()
        return cur

    def many(self, sql: str, params: Iterable[Any] = ()) -> list[sqlite3.Row]:
        return list(self.conn.execute(sql, tuple(params)).fetchall())

    def one(self, sql: str, params: Iterable[Any] = ()) -> sqlite3.Row | None:
        return self.conn.execute(sql, tuple(params)).fetchone()

    def close(self) -> None:
        try:
            self.conn.close()
        except Exception:
            pass

    # ------------------------------------------------------------------ settings
    def get(self, key: str, default: str = "") -> str:
        row = self.one("SELECT value FROM settings WHERE key = ?", (key,))
        return row["value"] if row else default

    def set(self, key: str, value: str) -> None:
        self.execute(
            "INSERT INTO settings(key, value) VALUES (?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (key, str(value)),
        )

    # ------------------------------------------------------------------ projects
    def upsert_project(self, name: str, root: Path, **fields: Any) -> int:
        row = self.one("SELECT id FROM projects WHERE name = ?", (name,))
        if row is None:
            cur = self.execute(
                "INSERT INTO projects(name, root) VALUES (?, ?)", (name, str(root))
            )
            project_id = int(cur.lastrowid)
        else:
            project_id = int(row["id"])
            self.execute("UPDATE projects SET root = ? WHERE id = ?", (str(root), project_id))
        if fields:
            self.update_project(project_id, **fields)
        return project_id

    def update_project(self, project_id: int, **fields: Any) -> None:
        allowed = {
            "bucket", "priority", "pinned", "external", "summary", "verdict",
            "file_count", "line_count", "symbol_count", "indexed_at", "root", "name",
        }
        pairs = {k: v for k, v in fields.items() if k in allowed}
        if not pairs:
            return
        assignments = ", ".join(f"{k} = ?" for k in pairs)
        self.execute(
            f"UPDATE projects SET {assignments} WHERE id = ?",
            list(pairs.values()) + [project_id],
        )

    def projects(self, bucket: str | None = None) -> list[ProjectRow]:
        if bucket:
            rows = self.many(
                "SELECT * FROM projects WHERE bucket = ? "
                "ORDER BY pinned DESC, priority DESC, name",
                (bucket,),
            )
        else:
            rows = self.many(
                "SELECT * FROM projects ORDER BY pinned DESC, priority DESC, name"
            )
        return [ProjectRow.from_row(r) for r in rows]

    def project(self, project_id: int) -> ProjectRow | None:
        row = self.one("SELECT * FROM projects WHERE id = ?", (project_id,))
        return ProjectRow.from_row(row) if row else None

    def project_by_name(self, name: str) -> ProjectRow | None:
        row = self.one("SELECT * FROM projects WHERE name = ?", (name,))
        return ProjectRow.from_row(row) if row else None

    def delete_project(self, project_id: int) -> None:
        self.execute("DELETE FROM projects WHERE id = ?", (project_id,))

    # -------------------------------------------------------------------- index
    def replace_index(
        self, project_id: int, files: list[dict[str, Any]], symbols: list[dict[str, Any]]
    ) -> None:
        with self.tx() as conn:
            conn.execute("DELETE FROM files WHERE project_id = ?", (project_id,))
            conn.execute("DELETE FROM symbols WHERE project_id = ?", (project_id,))
            conn.executemany(
                "INSERT INTO files(project_id, path, line_count, file_hash, error) "
                "VALUES (?, ?, ?, ?, ?)",
                [
                    (project_id, f["path"], f["line_count"], f["file_hash"], f.get("error", ""))
                    for f in files
                ],
            )
            conn.executemany(
                "INSERT INTO symbols(project_id, path, name, kind, line_start, line_end, "
                "signature, body_hash, doc, calls, called_by, flags, address) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    (
                        project_id, s["path"], s["name"], s["kind"], s["line_start"],
                        s["line_end"], s["signature"], s["body_hash"], s.get("doc", ""),
                        ",".join(s.get("calls", [])), ",".join(s.get("called_by", [])),
                        s.get("flags", ""), s.get("address", ""),
                    )
                    for s in symbols
                ],
            )

    def symbols(self, project_id: int | None = None, limit: int = 0) -> list[sqlite3.Row]:
        sql = "SELECT s.*, p.name AS project, p.bucket AS bucket FROM symbols s " \
              "JOIN projects p ON p.id = s.project_id"
        params: list[Any] = []
        if project_id is not None:
            sql += " WHERE s.project_id = ?"
            params.append(project_id)
        sql += " ORDER BY s.path, s.line_start"
        if limit:
            sql += f" LIMIT {int(limit)}"
        return self.many(sql, params)

    def symbol_by_address(self, address: str) -> sqlite3.Row | None:
        return self.one(
            "SELECT s.*, p.name AS project, p.root AS root, p.bucket AS bucket "
            "FROM symbols s JOIN projects p ON p.id = s.project_id WHERE s.address = ?",
            (address,),
        )

    def search_symbols(self, query: str, limit: int = 60) -> list[sqlite3.Row]:
        like = f"%{query.strip().lower()}%"
        return self.many(
            "SELECT s.*, p.name AS project, p.bucket AS bucket, p.priority AS priority "
            "FROM symbols s JOIN projects p ON p.id = s.project_id "
            "WHERE lower(s.name) LIKE ? OR lower(s.signature) LIKE ? OR lower(s.doc) LIKE ? "
            "ORDER BY p.priority DESC, s.name LIMIT ?",
            (like, like, like, limit),
        )

    def counts(self) -> dict[str, int]:
        def scalar(sql: str) -> int:
            row = self.one(sql)
            return int(row[0]) if row else 0

        return {
            "projects": scalar("SELECT COUNT(*) FROM projects"),
            "files": scalar("SELECT COUNT(*) FROM files"),
            "symbols": scalar("SELECT COUNT(*) FROM symbols"),
            "lines": scalar("SELECT COALESCE(SUM(line_count), 0) FROM files"),
            "buckets": scalar("SELECT COUNT(DISTINCT bucket) FROM projects"),
        }

    def bucket_summary(self) -> list[sqlite3.Row]:
        return self.many(
            "SELECT bucket, COUNT(*) AS projects, "
            "COALESCE(SUM(symbol_count), 0) AS symbols, "
            "COALESCE(SUM(line_count), 0) AS lines, "
            "COALESCE(MAX(priority), 0) AS top_priority "
            "FROM projects GROUP BY bucket ORDER BY projects DESC"
        )

    # ----------------------------------------------------------------- entities
    def replace_entities(self, project_id: int, entities: list[dict[str, Any]]) -> None:
        """Swap in a project's entity list, preserving run counts for ones that stay.

        Usage history is the most valuable thing here -- it is what makes the "most
        used tools" list meaningful -- so re-absorbing a project must not reset it.
        """
        previous = {
            (row["kind"], row["name"]): (row["runs"], row["last_run"], row["pinned"])
            for row in self.many(
                "SELECT kind, name, runs, last_run, pinned FROM entities "
                "WHERE project_id = ?",
                (project_id,),
            )
        }
        with self.tx() as conn:
            conn.execute("DELETE FROM entities WHERE project_id = ?", (project_id,))
            conn.executemany(
                "INSERT INTO entities(project_id, name, kind, path, symbol, summary, "
                "run_mode, run_target, run_args, evidence, line, confidence, "
                "pinned, runs, last_run) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    (
                        project_id, e["name"], e["kind"], e.get("path", ""),
                        e.get("symbol", ""), e.get("summary", ""),
                        e.get("run_mode", "import"), e.get("run_target", ""),
                        "\x1f".join(e.get("run_args", [])),
                        ", ".join(e.get("evidence", [])),
                        int(e.get("line", 0)), float(e.get("confidence", 0.5)),
                        previous.get((e["kind"], e["name"]), (0, "", 0))[2],
                        previous.get((e["kind"], e["name"]), (0, "", 0))[0],
                        previous.get((e["kind"], e["name"]), (0, "", 0))[1],
                    )
                    for e in entities
                ],
            )

    def entities(
        self, project_id: int | None = None, kind: str | None = None,
        runnable_only: bool = False, query: str = "",
    ) -> list[sqlite3.Row]:
        clauses, params = [], []
        if project_id is not None:
            clauses.append("e.project_id = ?")
            params.append(project_id)
        if kind:
            clauses.append("e.kind = ?")
            params.append(kind)
        if runnable_only:
            clauses.append("e.run_mode != 'import'")
        if query:
            clauses.append("(lower(e.name) LIKE ? OR lower(e.summary) LIKE ?)")
            like = f"%{query.lower()}%"
            params += [like, like]
        where = (" WHERE " + " AND ".join(clauses)) if clauses else ""
        return self.many(
            "SELECT e.*, p.name AS project, p.root AS root, p.bucket AS bucket "
            "FROM entities e JOIN projects p ON p.id = e.project_id" + where +
            " ORDER BY e.pinned DESC, e.runs DESC, p.priority DESC, e.kind, e.name",
            params,
        )

    def entity(self, entity_id: int) -> sqlite3.Row | None:
        return self.one(
            "SELECT e.*, p.name AS project, p.root AS root FROM entities e "
            "JOIN projects p ON p.id = e.project_id WHERE e.id = ?",
            (entity_id,),
        )

    def record_run(self, entity_id: int) -> None:
        self.execute(
            "UPDATE entities SET runs = runs + 1, "
            "last_run = datetime('now') WHERE id = ?",
            (entity_id,),
        )

    def toggle_entity_pin(self, entity_id: int) -> None:
        self.execute(
            "UPDATE entities SET pinned = CASE pinned WHEN 1 THEN 0 ELSE 1 END "
            "WHERE id = ?",
            (entity_id,),
        )

    def entity_counts(self) -> list[sqlite3.Row]:
        return self.many(
            "SELECT kind, COUNT(*) AS n FROM entities GROUP BY kind ORDER BY n DESC"
        )

    # ------------------------------------------------------------------- ledger
    def log(
        self,
        action: str,
        address: str = "",
        detail: str = "",
        backup_dir: str = "",
        payload: Any = None,
    ) -> int:
        cur = self.execute(
            "INSERT INTO ledger(action, address, detail, backup_dir, payload) "
            "VALUES (?, ?, ?, ?, ?)",
            (action, address, detail, backup_dir,
             json.dumps(payload, default=str) if payload is not None else ""),
        )
        return int(cur.lastrowid)

    def ledger(self, limit: int = 200) -> list[sqlite3.Row]:
        return self.many("SELECT * FROM ledger ORDER BY id DESC LIMIT ?", (limit,))

    def ledger_entry(self, entry_id: int) -> sqlite3.Row | None:
        return self.one("SELECT * FROM ledger WHERE id = ?", (entry_id,))
