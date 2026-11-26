"""Document -> elements pipeline with self-accruing knowledge.

* Unchanged files are skipped (size + mtime, then SHA-256).
* A changed file replaces its previous elements; an element shared with other
  sources survives with a lower count.
* A sentence seen again (any document) is not duplicated: its count grows and
  the new source is linked, so repeated knowledge carries more weight.
* After each batch the model learns from the new sentences, new elements are
  embedded and indexed, and heads are rediscovered when the corpus has grown by
  a quarter (or on request); then every element is re-assigned and re-sequenced.
"""
from __future__ import annotations

import hashlib
import json
import os
import time
from collections import Counter, defaultdict
from pathlib import Path

from . import embed, heads, parsers
from .store import Store, now, safe_json
from .text import RootNormalizer, complexity, fingerprint, idf_table, is_element, split_sentences

SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", "$recycle.bin", "appdata", ".cache", "site-packages"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def walk(folders: list[str], recursive: bool = True, limit: int = 20000) -> list[Path]:
    found = []
    for folder in folders:
        base = Path(folder)
        if base.is_file():
            found.append(base)
            continue
        if not base.is_dir():
            continue
        iterator = base.rglob("*") if recursive else base.glob("*")
        for path in iterator:
            if len(found) >= limit:
                return found
            # Skip tool/cache folders *inside* the chosen folder; the folder itself may live anywhere.
            relative = path.relative_to(base).parts
            if any(part.lower() in SKIP_DIRS or part.startswith(".") for part in relative[:-1]) or path.name.startswith(("~$", ".")):
                continue
            if path.is_file() and parsers.supported(path):
                found.append(path)
    return found


class Knowledge:
    def __init__(self, db_path: str | Path, *, prefer_extension: bool = True):
        self.store = Store(db_path, prefer_extension=prefer_extension)
        self.db = self.store.db
        df, tf, forms, contexts = self.store.load_lexicon(with_context=True)
        self.df, self.tf = df, tf
        self.forms = {root: safe_json(value, {}) for root, value in forms.items()}
        self.sources_per_root = {r["root"]: r["sources"] for r in self.db.execute("SELECT root, sources FROM lexicon")}
        self.model = embed.Model(contexts, self.df, self.store.element_count())
        self.normalizer = RootNormalizer(self.tf)
        self._pending_index: dict[str, dict] = {}

    def close(self):
        self.store.close()

    # ─── ingestion ────────────────────────────────────────────────────────

    def ingest(self, paths: list[str] | None = None, folders: list[str] | None = None, *, recursive: bool = True,
               origin: str = "", ocr: bool = True, force: bool = False, progress=None, deadline: float | None = None,
               keep_text: bool = False) -> dict:
        files = [Path(p) for p in paths or []] + walk(folders or [], recursive)
        report = {"scanned": 0, "ingested": [], "skipped": 0, "failed": [], "new_elements": 0, "reinforced": 0,
                  "rediscovered": False, "stopped_early": False}
        pending: list[dict] = []
        seen_files = set()
        for path in files:
            key = str(path.resolve()).lower()
            if key in seen_files:
                continue
            seen_files.add(key)
            if deadline and time.time() > deadline:
                report["stopped_early"] = True
                break
            report["scanned"] += 1
            try:
                outcome = self._ingest_file(path.resolve(), origin, ocr, force, pending, keep_text)
            except Exception as error:
                self._record_failure(path.resolve(), origin, error)
                report["failed"].append({"path": str(path), "error": f"{type(error).__name__}: {error}"[:300]})
                continue
            if outcome is None:
                report["skipped"] += 1
            else:
                report["ingested"].append(outcome)
                report["new_elements"] += outcome["new"]
                report["reinforced"] += outcome["reinforced"]
            self.db.commit()  # keep write transactions short: other jobs may read or write meanwhile
            if progress:
                progress(report)
            if len(pending) >= 3000:
                self._finish_batch(pending)
                pending = []
        self._finish_batch(pending)
        report["rediscovered"] = self.maybe_rediscover()
        self.db.commit()
        report["stats"] = self.store.stats()
        return report

    def ingest_text(self, text: str, title: str, locator: str = "text", origin: str = "text") -> dict:
        pseudo = f"text://{origin}/{hashlib.sha1((title + text[:200]).encode()).hexdigest()[:16]}"
        pending: list[dict] = []
        source_id = self._upsert_source(pseudo, "text", title, len(text), 0, hashlib.sha256(text.encode()).hexdigest(), origin)
        outcome = self._add_blocks(source_id, [(locator, text)], pending)
        self._finish_batch(pending)
        self.db.execute("UPDATE source SET status='ok', elements=?, updated=? WHERE id=?", (outcome["new"] + outcome["reinforced"], now(), source_id))
        self.maybe_rediscover()
        self.db.commit()
        return outcome

    def _ingest_file(self, path: Path, origin: str, ocr: bool, force: bool, pending: list, keep_text: bool = False) -> dict | None:
        stat = path.stat()
        row = self.db.execute("SELECT * FROM source WHERE path=?", (str(path),)).fetchone()
        if row and not force and row["status"] == "ok" and row["size"] == stat.st_size and abs((row["mtime"] or 0) - stat.st_mtime) < 1:
            return None
        digest = sha256(path)
        if row and not force and row["status"] == "ok" and row["sha256"] == digest:
            self.db.execute("UPDATE source SET mtime=?, updated=? WHERE id=?", (stat.st_mtime, now(), row["id"]))
            return None
        extracted = parsers.extract(path, ocr=ocr)
        if row:
            self._detach_source(row["id"])
        source_id = self._upsert_source(str(path), extracted["kind"], path.name, stat.st_size, stat.st_mtime, digest, origin,
                                        pages=extracted["pages"], method=extracted["method"])
        outcome = self._add_blocks(source_id, extracted["blocks"], pending)
        status = "ok" if outcome["new"] + outcome["reinforced"] else "empty"
        self.db.execute("UPDATE source SET status=?, error='', elements=?, updated=? WHERE id=?",
                        (status, outcome["new"] + outcome["reinforced"], now(), source_id))
        outcome.update({"path": str(path), "title": path.name, "kind": extracted["kind"], "method": extracted["method"],
                        "pages": extracted["pages"], "source_id": source_id, "status": status})
        if keep_text:
            outcome["text"] = "\n".join(text for _, text in extracted["blocks"])[:400000]
        return outcome

    def _upsert_source(self, path, kind, title, size, mtime, digest, origin, pages=0, method="") -> int:
        stamp = now()
        self.db.execute("INSERT INTO source(path,kind,title,size,mtime,sha256,added,updated,status,pages,method,origin) "
                        "VALUES(?,?,?,?,?,?,?,?,'processing',?,?,?) ON CONFLICT(path) DO UPDATE SET kind=excluded.kind, "
                        "title=excluded.title, size=excluded.size, mtime=excluded.mtime, sha256=excluded.sha256, "
                        "updated=excluded.updated, status='processing', pages=excluded.pages, method=excluded.method",
                        (path, kind, title, size, mtime, digest, stamp, stamp, pages, method, origin))
        return self.db.execute("SELECT id FROM source WHERE path=?", (path,)).fetchone()[0]

    def _record_failure(self, path: Path, origin: str, error: Exception) -> None:
        stat = path.stat() if path.exists() else None
        self._upsert_source(str(path), path.suffix.lower().lstrip("."), path.name, stat.st_size if stat else 0,
                            stat.st_mtime if stat else 0, "", origin)
        self.db.execute("UPDATE source SET status='error', error=? WHERE path=?", (f"{type(error).__name__}: {error}"[:500], str(path)))

    def _detach_source(self, source_id: int) -> None:
        """Remove a changed document's contribution before re-reading it."""
        element_ids = [r[0] for r in self.db.execute("SELECT DISTINCT element_id FROM element_source WHERE source_id=?", (source_id,))]
        self.db.execute("DELETE FROM element_source WHERE source_id=?", (source_id,))
        orphans = []
        for element_id in element_ids:
            remaining = self.db.execute("SELECT COUNT(*) FROM element_source WHERE element_id=?", (element_id,)).fetchone()[0]
            if remaining == 0:
                orphans.append(element_id)
            else:
                self.db.execute("UPDATE element SET count=MAX(1, ?) WHERE id=?", (remaining, element_id))
        for element_id in orphans:
            row = self.db.execute("SELECT roots FROM element WHERE id=?", (element_id,)).fetchone()
            for root in set(json.loads(row["roots"] or "[]")) if row else ():
                self.df[root] = max(0, self.df.get(root, 1) - 1)
            self.db.execute("DELETE FROM element WHERE id=?", (element_id,))
        self.store.unindex(orphans)

    def _add_blocks(self, source_id: int, blocks: list, pending: list) -> dict:
        new = reinforced = 0
        touched_sources = set()
        for locator, text in blocks:
            for sentence in split_sentences(text):
                roots, surface = self.normalizer.text_roots(sentence)
                if not is_element(sentence, roots):
                    continue
                digest = fingerprint(sentence)
                row = self.db.execute("SELECT id FROM element WHERE hash=?", (digest,)).fetchone()
                if row:
                    linked = self.db.execute("INSERT OR IGNORE INTO element_source(element_id, source_id, locator) VALUES(?,?,?)",
                                             (row["id"], source_id, locator)).rowcount
                    if linked:
                        self.db.execute("UPDATE element SET count=count+1, updated=? WHERE id=?", (now(), row["id"]))
                        reinforced += 1
                    continue
                waiting = self._pending_index.get(digest)
                if waiting is not None:  # repeated within this batch: accrue instead of duplicating
                    if (source_id, locator) not in waiting["links"]:
                        waiting["links"].append((source_id, locator))
                        waiting["count"] += 1
                        reinforced += 1
                    continue
                item = {"hash": digest, "text": sentence, "roots": roots, "surface": surface,
                        "links": [(source_id, locator)], "count": 1}
                pending.append(item)
                self._pending_index[digest] = item
                new += 1
                for root, form in zip(roots, surface):
                    self.tf[root] = self.tf.get(root, 0) + 1
                    forms = self.forms.setdefault(root, {})
                    forms[form] = forms.get(form, 0) + 1
                    touched_sources.add(root)
        for root in touched_sources:
            self.sources_per_root[root] = self.sources_per_root.get(root, 0) + 1
        return {"new": new, "reinforced": reinforced}

    def _finish_batch(self, pending: list) -> None:
        if not pending:
            return
        touched = set()
        for item in pending:
            for root in set(item["roots"]):
                self.df[root] = self.df.get(root, 0) + 1
            self.model.learn(item["roots"])
            touched.update(item["roots"])
        self.model.total = self.store.element_count() + len(pending)
        self.model._root_cache.clear()
        self.normalizer.known = self.tf
        idf, max_idf = idf_table(self.df, self.model.total)
        router = heads.Router(self.store)
        stamp = now()
        for item in pending:
            vector = self.model.embed(item["roots"])
            score, level, definitional = complexity(item["text"], item["roots"], idf, max_idf)
            head_id, head_score = router.assign(vector, item["roots"], self.model.idf) if router else (0, 0.0)
            blob = embed.pack(vector)
            cursor = self.db.execute(
                "INSERT INTO element(hash,text,roots,head_id,head_score,complexity,level,definitional,count,created,updated,embedding,model) "
                "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (item["hash"], item["text"], json.dumps(item["roots"]), head_id, round(head_score, 4), score, level,
                 int(definitional), item["count"], stamp, stamp, blob, self.model.version))
            element_id = cursor.lastrowid
            self.db.executemany("INSERT OR IGNORE INTO element_source(element_id, source_id, locator) VALUES(?,?,?)",
                                [(element_id, source, locator) for source, locator in item["links"]])
            self.store.index_vector(element_id, blob)
            self.store.index_text(element_id, item["text"], item["roots"])
        self.store.save_lexicon(self.df, self.tf, self.forms, self.model.contexts, self.sources_per_root, touched)
        self._pending_index.clear()
        self.db.commit()

    # ─── self-organization ────────────────────────────────────────────────

    def maybe_rediscover(self, force: bool = False) -> bool:
        total = self.store.element_count()
        if total == 0:
            return False
        last = int(self.store.meta("discovered_at_elements", "0") or 0)
        has_heads = self.db.execute("SELECT COUNT(*) FROM head").fetchone()[0] > 0
        if not force and has_heads and total < last * 1.25 + 25:
            return False
        if not force and total < 12:
            return False
        self.rediscover()
        return True

    def rediscover(self) -> dict:
        """Re-embed stale elements, rediscover heads, re-assign and re-sequence everything."""
        self.model.total = self.store.element_count()
        self.model._root_cache.clear()
        reembedded = self.reembed()
        clusters = heads.discover(self.store, self.model)
        moved = heads.reassign_all(self.store, self.model)
        for row in self.db.execute("SELECT id FROM head WHERE locked=0").fetchall():
            if not self.db.execute("SELECT 1 FROM element WHERE head_id=? LIMIT 1", (row["id"],)).fetchone():
                self.db.execute("DELETE FROM head WHERE id=?", (row["id"],))
        idf, max_idf = idf_table(self.df, self.model.total)
        for row in self.db.execute("SELECT id, text, roots FROM element").fetchall():
            score, level, definitional = complexity(row["text"], json.loads(row["roots"]), idf, max_idf)
            self.db.execute("UPDATE element SET complexity=?, level=?, definitional=? WHERE id=?", (score, level, int(definitional), row["id"]))
        heads.sequence_all(self.store)
        self.db.commit()
        return {"heads": len(clusters), "reembedded": reembedded, "moved": moved}

    def reembed(self) -> int:
        version = self.model.version
        rows = self.db.execute("SELECT id, roots FROM element WHERE model<>?", (version,)).fetchall()
        for row in rows:
            blob = embed.pack(self.model.embed(json.loads(row["roots"] or "[]")))
            self.db.execute("UPDATE element SET embedding=?, model=? WHERE id=?", (blob, version, row["id"]))
            self.store.index_vector(row["id"], blob)
        return len(rows)

    def rename_head(self, head_id: int, name: str) -> None:
        name = " ".join(str(name).split())[:60]
        if not name:
            raise ValueError("A head name is required")
        self.db.execute("UPDATE head SET name=?, locked=1, updated=? WHERE id=?", (name, now(), head_id))
        self.db.commit()

    def unlock_head(self, head_id: int) -> None:
        self.db.execute("UPDATE head SET locked=0 WHERE id=?", (head_id,))
        self.db.commit()

    def forget_source(self, source_id: int) -> None:
        self._detach_source(source_id)
        self.db.execute("DELETE FROM source WHERE id=?", (source_id,))
        heads.sequence_all(self.store)
        self.db.commit()

    # ─── querying ─────────────────────────────────────────────────────────

    def query_vector(self, text: str) -> tuple[list, list[str]]:
        roots, _ = self.normalizer.text_roots(text)
        return self.model.embed(roots), roots

    def search(self, text: str, k: int = 12, head_id: int | None = None) -> list[dict]:
        vector, roots = self.query_vector(text)
        hits = self.store.hybrid(vector, roots, k, head_id)
        scores = dict(hits)
        elements = self.store.elements([h[0] for h in hits])
        for element in elements:
            element["score"] = round(scores.get(element["id"], 0.0), 4)
        return elements
