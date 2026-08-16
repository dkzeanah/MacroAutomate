from __future__ import annotations

import hashlib
import json
import math
import os
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from .ollama_api import OllamaClient


SUPPORTED_TEXT_EXTENSIONS = {
    ".txt", ".md", ".rst", ".py", ".ahk", ".js", ".ts", ".tsx", ".jsx",
    ".json", ".csv", ".toml", ".yaml", ".yml", ".ini", ".cfg", ".log",
    ".html", ".htm", ".css", ".sql",
}


@dataclass
class SearchHit:
    score: float
    path: str
    chunk_index: int
    text: str


class RAGStore:
    def __init__(self, db_path: Path, client: OllamaClient) -> None:
        self.db_path = db_path
        self.client = client
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        return connection

    def _initialize(self) -> None:
        with self._connect() as db:
            db.execute(
                """
                CREATE TABLE IF NOT EXISTS documents (
                    id INTEGER PRIMARY KEY,
                    path TEXT NOT NULL UNIQUE,
                    sha256 TEXT NOT NULL,
                    modified REAL NOT NULL,
                    size INTEGER NOT NULL
                )
                """
            )
            db.execute(
                """
                CREATE TABLE IF NOT EXISTS chunks (
                    id INTEGER PRIMARY KEY,
                    document_id INTEGER NOT NULL,
                    chunk_index INTEGER NOT NULL,
                    text TEXT NOT NULL,
                    vector_json TEXT NOT NULL,
                    model TEXT NOT NULL,
                    FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE,
                    UNIQUE(document_id, chunk_index, model)
                )
                """
            )
            db.execute("PRAGMA foreign_keys = ON")

    @staticmethod
    def _read_text(path: Path) -> str:
        if path.suffix.lower() == ".pdf":
            try:
                from pypdf import PdfReader
            except ImportError as exc:
                raise RuntimeError(
                    "PDF indexing requires pypdf. Use Setup > Install Python dependencies."
                ) from exc
            reader = PdfReader(str(path))
            return "\n\n".join((page.extract_text() or "") for page in reader.pages)
        return path.read_text(encoding="utf-8", errors="replace")

    @staticmethod
    def chunk_text(text: str, max_chars: int = 2400, overlap: int = 300) -> list[str]:
        cleaned = "\n".join(line.rstrip() for line in text.replace("\x00", "").splitlines())
        cleaned = cleaned.strip()
        if not cleaned:
            return []
        chunks: list[str] = []
        start = 0
        length = len(cleaned)
        while start < length:
            end = min(length, start + max_chars)
            if end < length:
                split_candidates = [
                    cleaned.rfind("\n\n", start, end),
                    cleaned.rfind("\n", start, end),
                    cleaned.rfind(". ", start, end),
                    cleaned.rfind(" ", start, end),
                ]
                split_at = max(split_candidates)
                if split_at > start + max_chars // 2:
                    end = split_at + 1
            chunk = cleaned[start:end].strip()
            if chunk:
                chunks.append(chunk)
            if end >= length:
                break
            start = max(start + 1, end - overlap)
        return chunks

    @staticmethod
    def _sha256(path: Path) -> str:
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
        return digest.hexdigest()

    def iter_supported_files(self, paths: Iterable[Path]) -> list[Path]:
        found: list[Path] = []
        for path in paths:
            path = path.expanduser().resolve()
            if path.is_file():
                if path.suffix.lower() in SUPPORTED_TEXT_EXTENSIONS or path.suffix.lower() == ".pdf":
                    found.append(path)
            elif path.is_dir():
                for root, dirs, files in os.walk(path):
                    dirs[:] = [
                        d for d in dirs
                        if d.lower() not in {
                            ".git", ".venv", "venv", "node_modules", "__pycache__",
                            ".idea", ".vscode", "site-packages", "dist", "build"
                        }
                    ]
                    for name in files:
                        candidate = Path(root) / name
                        if (
                            candidate.suffix.lower() in SUPPORTED_TEXT_EXTENSIONS
                            or candidate.suffix.lower() == ".pdf"
                        ):
                            found.append(candidate)
        return sorted(set(found))

    def index_files(
        self,
        paths: Iterable[Path],
        *,
        model: str = "embeddinggemma",
        progress: callable | None = None,
    ) -> dict[str, int]:
        files = self.iter_supported_files(paths)
        indexed = skipped = failed = chunks_total = 0
        for number, path in enumerate(files, start=1):
            if progress:
                progress(f"[{number}/{len(files)}] {path}")
            try:
                stat = path.stat()
                digest = self._sha256(path)
                with self._connect() as db:
                    existing = db.execute(
                        "SELECT id, sha256 FROM documents WHERE path = ?",
                        (str(path),),
                    ).fetchone()
                    if existing and existing["sha256"] == digest:
                        chunk_count = db.execute(
                            "SELECT COUNT(*) AS count FROM chunks WHERE document_id = ? AND model = ?",
                            (existing["id"], model),
                        ).fetchone()["count"]
                        if chunk_count:
                            skipped += 1
                            continue

                text = self._read_text(path)
                chunks = self.chunk_text(text)
                if not chunks:
                    skipped += 1
                    continue
                response = self.client.embed(model, chunks)
                vectors = response.get("embeddings", [])
                if len(vectors) != len(chunks):
                    raise RuntimeError(
                        f"Embedding count mismatch: {len(vectors)} vectors for {len(chunks)} chunks"
                    )

                with self._connect() as db:
                    db.execute(
                        """
                        INSERT INTO documents(path, sha256, modified, size)
                        VALUES (?, ?, ?, ?)
                        ON CONFLICT(path) DO UPDATE SET
                            sha256=excluded.sha256,
                            modified=excluded.modified,
                            size=excluded.size
                        """,
                        (str(path), digest, stat.st_mtime, stat.st_size),
                    )
                    doc_id = db.execute(
                        "SELECT id FROM documents WHERE path = ?", (str(path),)
                    ).fetchone()["id"]
                    db.execute(
                        "DELETE FROM chunks WHERE document_id = ? AND model = ?",
                        (doc_id, model),
                    )
                    db.executemany(
                        """
                        INSERT INTO chunks(document_id, chunk_index, text, vector_json, model)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                        [
                            (doc_id, idx, chunk, json.dumps(vector), model)
                            for idx, (chunk, vector) in enumerate(zip(chunks, vectors))
                        ],
                    )
                indexed += 1
                chunks_total += len(chunks)
            except Exception as exc:
                failed += 1
                if progress:
                    progress(f"  ERROR: {type(exc).__name__}: {exc}")
        return {
            "files_found": len(files),
            "indexed": indexed,
            "skipped": skipped,
            "failed": failed,
            "chunks": chunks_total,
        }

    @staticmethod
    def cosine(a: list[float], b: list[float]) -> float:
        if len(a) != len(b) or not a:
            return -1.0
        dot = sum(x * y for x, y in zip(a, b))
        norm_a = math.sqrt(sum(x * x for x in a))
        norm_b = math.sqrt(sum(y * y for y in b))
        if norm_a == 0.0 or norm_b == 0.0:
            return -1.0
        return dot / (norm_a * norm_b)

    def search(
        self,
        query: str,
        *,
        model: str = "embeddinggemma",
        limit: int = 8,
    ) -> list[SearchHit]:
        response = self.client.embed(model, query)
        embeddings = response.get("embeddings", [])
        if not embeddings:
            return []
        query_vector = embeddings[0]
        with self._connect() as db:
            rows = db.execute(
                """
                SELECT d.path, c.chunk_index, c.text, c.vector_json
                FROM chunks c
                JOIN documents d ON d.id = c.document_id
                WHERE c.model = ?
                """,
                (model,),
            ).fetchall()
        scored = [
            SearchHit(
                score=self.cosine(query_vector, json.loads(row["vector_json"])),
                path=row["path"],
                chunk_index=row["chunk_index"],
                text=row["text"],
            )
            for row in rows
        ]
        scored.sort(key=lambda hit: hit.score, reverse=True)
        return scored[:limit]

    def stats(self) -> dict[str, int]:
        with self._connect() as db:
            docs = db.execute("SELECT COUNT(*) FROM documents").fetchone()[0]
            chunks = db.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
        return {"documents": docs, "chunks": chunks}

    def clear(self) -> None:
        with self._connect() as db:
            db.execute("DELETE FROM chunks")
            db.execute("DELETE FROM documents")
