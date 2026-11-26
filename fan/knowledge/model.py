"""The compact head-centred model: views, questions, and the portable knowledge pack.

``export_pack`` writes ``knowledge_pack.json``, a self-contained small model of
everything ingested: vocabulary with spellings, learned context vectors for
the strongest roots, each head's routing centroid, member roots, key phrases,
definitions and a level-ordered curriculum. :class:`Pack` loads it and can
embed and route new text to heads without the database. A Markdown primer per
head (Level 1 -> Level 5) is written alongside.
"""
from __future__ import annotations

import base64
import json
import re
from collections import Counter
from pathlib import Path

from . import embed
from .heads import Router, display_form
from .store import Store, now, safe_json
from .text import RootNormalizer

LEVEL_NAMES = {1: "Foundations", 2: "Basics", 3: "Working knowledge", 4: "Advanced", 5: "Expert detail"}


def head_list(store: Store) -> list[dict]:
    db = store.db
    out = []
    for row in db.execute("SELECT * FROM head ORDER BY elements DESC, name").fetchall():
        levels = Counter({r[0]: r[1] for r in db.execute("SELECT level, COUNT(*) FROM element WHERE head_id=? GROUP BY level", (row["id"],))})
        out.append({"id": row["id"], "name": row["name"], "aliases": safe_json(row["aliases"], []), "elements": row["elements"],
                    "sources": row["sources"], "locked": bool(row["locked"]),
                    "roots": [r["root"] for r in safe_json(row["roots"], [])][:12], "phrases": safe_json(row["phrases"], [])[:8],
                    "levels": [levels.get(level, 0) for level in range(1, 6)]})
    unsorted = db.execute("SELECT COUNT(*) FROM element WHERE head_id=0").fetchone()[0]
    if unsorted:
        out.append({"id": 0, "name": "(unsorted)", "aliases": [], "elements": unsorted, "sources": 0, "locked": False,
                    "roots": [], "phrases": [], "levels": [0, 0, 0, 0, 0]})
    return out


def head_detail(store: Store, head_id: int, limit: int = 300, offset: int = 0) -> list[dict]:
    ids = [r[0] for r in store.db.execute("SELECT id FROM element WHERE head_id=? ORDER BY seq LIMIT ? OFFSET ?", (head_id, limit, offset))]
    return [_brief(e) for e in store.elements(ids)]


def _brief(element: dict) -> dict:
    source = element["sources"][0] if element.get("sources") else {}
    return {"id": element["id"], "text": element["text"], "level": element["level"], "seq": element["seq"],
            "head_id": element["head_id"], "count": element["count"], "definition": bool(element["definitional"]),
            "complexity": element["complexity"], "score": element.get("score"),
            "source": source.get("title", ""), "locator": source.get("locator", ""), "path": source.get("path", "")}


def ask(knowledge, question: str, k: int = 8) -> dict:
    """Route the question to its heads, then gather the best elements, foundations first."""
    vector, roots = knowledge.query_vector(question)
    router = Router(knowledge.store)
    ranked = []
    if router:
        scores = router.scores(vector, roots, knowledge.model.idf)
        names = {h["id"]: h["name"] for h in knowledge.db.execute("SELECT id, name FROM head")}
        ranked = sorted(({"id": i, "name": names.get(i, "?"), "score": round(s, 3)} for i, s in scores.items()), key=lambda h: h["score"], reverse=True)[:3]
    found = knowledge.search(question, k * 2)
    top_heads = {h["id"] for h in ranked[:2]} if ranked else set()
    if top_heads:
        found.sort(key=lambda e: (e["score"] + (0.08 if e["head_id"] in top_heads else 0)), reverse=True)
    found = found[:k]
    definitions = [e for e in found if e["definitional"]]
    ordered = sorted(found, key=lambda e: (e["level"], -e["score"]))
    return {"question": question, "heads": ranked, "start_here": [_brief(e) for e in definitions[:3]],
            "answer": [_brief(e) for e in ordered],
            "summary": " ".join(e["text"] for e in ordered[:4]),
            "note": "Extracted from your own documents, simplest first. Open a source to read it in context."}


def export_pack(store: Store, out_dir: str | Path, *, vocabulary: int = 4000, per_head: int = 80) -> dict:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    db = store.db
    lexicon = db.execute("SELECT root, df, forms, ctx FROM lexicon ORDER BY df DESC LIMIT ?", (vocabulary,)).fetchall()
    vocab = {r["root"]: {"df": r["df"], "display": display_form(r["root"], r["forms"]),
                         "ctx": base64.b64encode(r["ctx"]).decode() if r["ctx"] else ""} for r in lexicon}
    total = store.element_count()
    heads_out = []
    for head in db.execute("SELECT * FROM head ORDER BY elements DESC").fetchall():
        rows = db.execute("SELECT text, level, definitional, count FROM element WHERE head_id=? ORDER BY seq LIMIT ?",
                          (head["id"], per_head)).fetchall()
        members = [(r["root"], r["weight"]) for r in db.execute("SELECT root, weight FROM head_root WHERE head_id=? ORDER BY weight DESC", (head["id"],))]
        heads_out.append({
            "id": head["id"], "name": head["name"], "aliases": safe_json(head["aliases"], []),
            "roots": [{"root": r, "weight": round(w, 3)} for r, w in members[:60]], "phrases": safe_json(head["phrases"], []),
            "centroid": base64.b64encode(head["centroid"]).decode() if head["centroid"] else "",
            "elements": head["elements"], "sources": head["sources"],
            "definitions": [r["text"] for r in rows if r["definitional"]][:15],
            "curriculum": [{"level": r["level"], "text": r["text"], "weight": r["count"]} for r in rows]})
    pack = {"format": "fan-knowledge-pack", "version": 1, "model": embed.MODEL, "dim": embed.DIM, "created": now(),
            "elements": total, "vocabulary": vocab, "heads": heads_out}
    path = out_dir / "knowledge_pack.json"
    path.write_text(json.dumps(pack, ensure_ascii=False), encoding="utf-8")
    primers = []
    for head in heads_out:
        primer = out_dir / f"{_slug(head['name'])}.md"
        lines = [f"# {head['name']}", "", f"*Aliases:* {', '.join(head['aliases']) or '—'}  ",
                 f"*Key terms:* {', '.join(r['root'] for r in head['roots'][:15])}  ",
                 f"*Built from* {head['elements']} elements in {head['sources']} source(s).", ""]
        if head["definitions"]:
            lines += ["## Start here", ""] + [f"- {d}" for d in head["definitions"][:8]] + [""]
        for level in range(1, 6):
            items = [c["text"] for c in head["curriculum"] if c["level"] == level]
            if items:
                lines += [f"## Level {level} · {LEVEL_NAMES[level]}", ""] + [f"{i}. {t}" for i, t in enumerate(items, 1)] + [""]
        primer.write_text("\n".join(lines), encoding="utf-8")
        primers.append(str(primer))
    return {"ok": True, "pack": str(path), "primers": primers, "heads": len(heads_out), "vocabulary": len(vocab),
            "megabytes": round(path.stat().st_size / 1048576, 2)}


def _slug(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "-", name).strip("-").lower() or "head"


class Pack:
    """Load an exported pack and route new text to heads without the database."""

    def __init__(self, path: str | Path):
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        if data.get("format") != "fan-knowledge-pack":
            raise ValueError("Not a Fan knowledge pack")
        self.data = data
        df = {r: v["df"] for r, v in data["vocabulary"].items()}
        contexts = {r: embed.unpack(base64.b64decode(v["ctx"])) for r, v in data["vocabulary"].items() if v.get("ctx")}
        self.model = embed.Model(contexts, df, data.get("elements", 0))
        self.normalizer = RootNormalizer(df)
        self.heads = [(h["id"], h["name"], embed.unpack(base64.b64decode(h["centroid"]))) for h in data["heads"] if h.get("centroid")]
        self.members = {}
        for head in data["heads"]:
            for item in head["roots"]:
                self.members.setdefault(item["root"], (head["id"], item["weight"]))

    def route(self, text: str, top: int = 3) -> list[dict]:
        roots, _ = self.normalizer.text_roots(text)
        vector = self.model.embed(roots)
        votes = Counter()
        total = 0.0
        for root in set(roots):
            if root in self.members:
                head_id, weight = self.members[root]
                w = self.model.idf(root) * (0.5 + min(1.0, weight))
                votes[head_id] += w
                total += w
        scored = [{"id": head_id, "name": name,
                   "score": round(0.6 * (votes.get(head_id, 0) / total if total else 0) + 0.4 * max(0.0, embed.dot(vector, centroid)), 3)}
                  for head_id, name, centroid in self.heads]
        return sorted(scored, key=lambda h: h["score"], reverse=True)[:top]
