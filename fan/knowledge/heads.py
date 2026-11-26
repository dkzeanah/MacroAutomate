"""Discover up to 20 head topics and arrange each head's elements.

Discovery works on two kinds of evidence for every frequent root:

* *usage context* - the Random Indexing context vector (which words surround it);
* *where it lives* - the pages/sections it appears in (roots that keep showing
  up on the same pages belong to the same subject).

1. Candidate roots: frequent, spread across sources, not generic.
2. Seeds by farthest-first: a root starts a new head only when it is unlike every
   existing head, so heads are distinct concepts rather than synonyms.
3. k-means style refinement, merge near-duplicates, fold tiny heads into their
   nearest neighbour.
4. Stable identity: clusters reuse the id (and any locked, user-given name) of
   the most similar previous head.
5. Elements are routed by a vote of their roots' head membership blended with
   vector similarity, then sequenced foundations-first.
"""
from __future__ import annotations

import json
import math
from collections import Counter, defaultdict

from . import embed
from .store import Store, now, safe_json
from .text import STOPWORDS

MAX_HEADS = 20
NEW_HEAD_BELOW = 0.25
MEMBER_ABOVE = 0.12
MERGE_ABOVE = 0.72
ASSIGN_ABOVE = 0.10
GENERIC = {"thing", "way", "time", "year", "day", "part", "people", "person", "work", "make", "need", "want", "look",
           "good", "great", "best", "right", "left", "end", "start", "number", "lot", "kind", "type", "case", "point",
           "place", "line", "set", "side", "show", "find", "help", "call", "name", "include", "provide", "follow",
           "different", "important", "possible", "able", "available", "following", "based", "note", "small", "large",
           "every", "store", "fixed", "measure", "change", "keep", "begin", "finish", "whole", "until", "many", "fix",
           "item", "value", "price", "total", "list", "row", "data", "file", "information", "detail", "result"}
VERBISH = ("ing", "ed")


def display_form(root: str, forms_json) -> str:
    forms = safe_json(forms_json, {}) if isinstance(forms_json, str) else (forms_json or {})
    if not forms:
        return root
    if root in forms:
        return root
    best = max(forms.items(), key=lambda kv: (kv[1], -len(kv[0])))[0]
    shorter = [f for f, c in forms.items() if c >= 0.5 * forms[best] and len(f) < len(best) and best.startswith(f)]
    return shorter[0] if shorter else best


def _nounish(root: str, forms_json) -> float:
    forms = safe_json(forms_json, {}) if isinstance(forms_json, str) else (forms_json or {})
    total = sum(forms.values()) or 1
    verb = sum(c for f, c in forms.items() if f.endswith(VERBISH) and not root.endswith(VERBISH))
    return 1.0 - 0.6 * verb / total


def candidates(df: dict, sources: dict, forms: dict, total: int, source_total: int, limit: int = 400) -> list[tuple[str, float]]:
    total, source_total = max(1, total), max(1, source_total)
    minimum = 2 if total < 400 else max(3, int(total * 0.002))
    scored = []
    for root, count in df.items():
        if count < minimum or root in STOPWORDS or root in GENERIC or len(root) < 3 or not root.isalpha():
            continue
        share = count / total
        spread = sources.get(root, 1) / source_total
        if share > 0.35 or (source_total >= 8 and spread > 0.6):
            continue  # appears everywhere: generic, not a subject
        # A subject's main word is naturally common; only penalise words beyond 15% of all ideas.
        salience = math.log1p(count) * (1 + math.log1p(sources.get(root, 1))) * (1 - 1.5 * max(0.0, share - 0.15)) * _nounish(root, forms.get(root))
        scored.append((root, salience))
    scored.sort(key=lambda x: x[1], reverse=True)
    return scored[:limit]


def _discovery_vectors(store: Store, model: embed.Model, pool: list[str]) -> dict[str, list]:
    """Per root: normalized usage context + normalized "which pages it lives on"."""
    wanted = set(pool)
    places: dict[str, list] = {root: embed.zeros() for root in pool}
    for row in store.db.execute("SELECT e.roots, e.count, es.source_id, es.locator FROM element e "
                                "JOIN element_source es ON es.element_id=e.id"):
        place = embed.index_vector(f"s:{row['source_id']}:{row['locator']}")
        weight = 1.0 + math.log(row["count"] or 1)
        for root in set(json.loads(row["roots"] or "[]")) & wanted:
            embed.add_sparse(places[root], place, weight)
    vectors = {}
    for root in pool:
        vector = embed.zeros()
        context = model.contexts.get(root)
        if context is not None:
            embed.add_dense(vector, embed.normalize(context), 1.0)
        embed.add_dense(vector, embed.normalize(places[root]), 1.3)
        vectors[root] = embed.normalize(vector)
    return vectors


def _mean(vectors: dict, members: list[str], weights: dict) -> list:
    out = embed.zeros()
    for root in members:
        embed.add_dense(out, vectors[root], weights.get(root, 1.0))
    return embed.normalize(out)


def discover(store: Store, model: embed.Model, *, max_heads: int = MAX_HEADS) -> list[dict]:
    db = store.db
    rows = db.execute("SELECT root, df, sources, forms FROM lexicon").fetchall()
    df = {r["root"]: r["df"] for r in rows}
    sources = {r["root"]: r["sources"] for r in rows}
    forms = {r["root"]: r["forms"] for r in rows}
    total = store.element_count()
    source_total = db.execute("SELECT COUNT(*) FROM source WHERE status='ok'").fetchone()[0]
    pool = candidates(df, sources, forms, total, source_total)
    if not pool:
        return []
    salience = dict(pool)
    roots = [r for r, _ in pool]
    vectors = _discovery_vectors(store, model, roots)

    previous = [dict(r) for r in db.execute("SELECT * FROM head").fetchall()]
    previous_members = defaultdict(list)
    for row in db.execute("SELECT root, head_id FROM head_root"):
        previous_members[row["head_id"]].append(row["root"])
    seeds: list[dict] = []
    for head in previous:  # user-named heads persist as fixed seeds
        members = [r for r in previous_members.get(head["id"], []) if r in vectors]
        if head["locked"] and members:
            seeds.append({"centroid": _mean(vectors, members, salience), "fixed": head, "members": members})
    seeds = seeds[:max_heads]
    for root in roots:
        if len(seeds) >= max_heads:
            break
        if all(embed.dot(vectors[root], s["centroid"]) < NEW_HEAD_BELOW for s in seeds):
            seeds.append({"centroid": vectors[root], "seed": root, "members": [root]})

    for _ in range(4):
        members: dict[int, list[str]] = defaultdict(list)
        for root in roots:
            sims = [embed.dot(vectors[root], s["centroid"]) for s in seeds]
            best = max(range(len(seeds)), key=lambda i: sims[i])
            if sims[best] >= MEMBER_ABOVE:
                members[best].append(root)
        for index, seed in enumerate(seeds):
            seed["members"] = members.get(index, [])
            if seed["members"]:
                seed["centroid"] = _mean(vectors, seed["members"], salience)

    seeds = _merge([s for s in seeds if s["members"] or s.get("fixed")], vectors, salience)
    seeds = _fold_tiny(seeds, vectors, salience)
    clusters = []
    for seed in seeds:
        members = sorted(seed["members"], key=lambda r: salience.get(r, 0), reverse=True)
        # The name is the most salient member that reads as a thing, not an action.
        named = sorted((r for r in members[:6] if _nounish(r, forms.get(r)) >= 0.7),
                       key=lambda r: math.log1p(df.get(r, 0)) * (1 + math.log1p(sources.get(r, 1))), reverse=True)
        top = (named or members or [seed.get("seed", "")])[0]
        fixed = seed.get("fixed")
        clusters.append({"centroid": model.centroid([(r, salience[r]) for r in members]) if members else seed["centroid"],
                         "members": members, "top": top, "fixed": fixed,
                         "name": fixed["name"] if fixed else display_form(top, forms.get(top)).capitalize(),
                         "aliases": _aliases(top, members, forms), "weight": sum(salience[r] for r in members),
                         "membership": {r: round(embed.dot(vectors[r], seed["centroid"]) * salience[r], 4) for r in members}})
    clusters.sort(key=lambda c: c["weight"], reverse=True)
    _persist(store, clusters, previous, salience)
    store.set_meta("last_discovery", now())
    store.set_meta("discovered_at_elements", total)
    return clusters


def _merge(seeds, vectors, salience):
    merged = True
    while merged and len(seeds) > 1:
        merged = False
        for i in range(len(seeds)):
            for j in range(i + 1, len(seeds)):
                if seeds[i].get("fixed") and seeds[j].get("fixed"):
                    continue
                if embed.dot(seeds[i]["centroid"], seeds[j]["centroid"]) > MERGE_ABOVE:
                    keep, drop = (i, j) if seeds[i].get("fixed") or (not seeds[j].get("fixed") and len(seeds[i]["members"]) >= len(seeds[j]["members"])) else (j, i)
                    seeds[keep]["members"] = seeds[keep]["members"] + seeds[drop]["members"]
                    seeds[keep]["centroid"] = _mean(vectors, seeds[keep]["members"], salience)
                    seeds.pop(drop)
                    merged = True
                    break
            if merged:
                break
    return seeds


def _fold_tiny(seeds, vectors, salience):
    """A head needs at least two related roots; a lone root joins its nearest head."""
    if len(seeds) <= 3:
        return seeds
    keep = [s for s in seeds if len(s["members"]) >= 2 or s.get("fixed")]
    if not keep:
        return seeds
    for seed in seeds:
        if seed in keep:
            continue
        for root in seed["members"]:
            target = max(keep, key=lambda k: embed.dot(vectors[root], k["centroid"]))
            if embed.dot(vectors[root], target["centroid"]) >= MEMBER_ABOVE:
                target["members"].append(root)
    for seed in keep:
        if seed["members"]:
            seed["centroid"] = _mean(vectors, seed["members"], salience)
    return keep


def _aliases(top: str, members: list[str], forms: dict) -> list[str]:
    """Spellings that name the same concept: dome, domes, geodesicdome, domekit..."""
    aliases = Counter()
    for root in [top] + [m for m in members if top and top in m and m != top]:
        for form, count in safe_json(forms.get(root), {}).items():
            aliases[form] += count
    return [a for a, _ in aliases.most_common(8)]


def _persist(store: Store, clusters: list[dict], previous: list[dict], salience: dict) -> None:
    db = store.db
    unused = {h["id"]: h for h in previous}
    stamp = now()
    db.execute("DELETE FROM head_root")
    for cluster in clusters:
        head_id = None
        if cluster.get("fixed"):
            head_id = cluster["fixed"]["id"]
        else:
            best, best_sim = None, 0.5
            for old in unused.values():
                if old["centroid"] and not old["locked"]:
                    sim = embed.dot(cluster["centroid"], embed.unpack(old["centroid"]))
                    if sim > best_sim:
                        best, best_sim = old["id"], sim
            head_id = best
        roots = [{"root": r, "weight": round(salience.get(r, 0), 3)} for r in cluster["members"][:40]]
        if head_id is not None and head_id in unused:
            old = unused.pop(head_id)
            name = old["name"] if old["locked"] else cluster["name"]
            db.execute("UPDATE head SET name=?, aliases=?, roots=?, centroid=?, updated=? WHERE id=?",
                       (name, json.dumps(cluster["aliases"]), json.dumps(roots), embed.pack(cluster["centroid"]), stamp, head_id))
        else:
            cursor = db.execute("INSERT INTO head(name, aliases, roots, centroid, created, updated) VALUES(?,?,?,?,?,?)",
                                (cluster["name"], json.dumps(cluster["aliases"]), json.dumps(roots), embed.pack(cluster["centroid"]), stamp, stamp))
            head_id = cursor.lastrowid
        cluster["id"] = head_id
        db.executemany("INSERT OR REPLACE INTO head_root(root, head_id, weight) VALUES(?,?,?)",
                       [(r, head_id, w) for r, w in cluster["membership"].items()])
    for old_id, old in unused.items():
        if not old["locked"]:
            db.execute("DELETE FROM head WHERE id=?", (old_id,))


class Router:
    """Routes an element (or a question) to a head: root membership vote + vector similarity."""

    def __init__(self, store: Store):
        self.centroids = [(r["id"], embed.unpack(r["centroid"])) for r in
                          store.db.execute("SELECT id, centroid FROM head WHERE centroid IS NOT NULL")]
        self.membership: dict[str, tuple[int, float]] = {}
        for row in store.db.execute("SELECT root, head_id, weight FROM head_root"):
            self.membership[row["root"]] = (row["head_id"], max(0.0, row["weight"]))

    def __bool__(self):
        return bool(self.centroids)

    def scores(self, vector: list, roots: list[str], idf) -> dict[int, float]:
        votes: dict[int, float] = defaultdict(float)
        weight_total = 0.0
        for root in set(roots):
            if root in self.membership:
                head_id, weight = self.membership[root]
                w = idf(root) * (0.5 + min(1.0, weight))
                votes[head_id] += w
                weight_total += w
        out = {}
        for head_id, centroid in self.centroids:
            vote = votes.get(head_id, 0.0) / weight_total if weight_total else 0.0
            out[head_id] = 0.6 * vote + 0.4 * max(0.0, embed.dot(vector, centroid))
        return out

    def assign(self, vector: list, roots: list[str], idf) -> tuple[int, float]:
        scores = self.scores(vector, roots, idf)
        if not scores:
            return 0, 0.0
        head_id = max(scores, key=scores.get)
        return (head_id, scores[head_id]) if scores[head_id] >= ASSIGN_ABOVE else (0, scores[head_id])


def reassign_all(store: Store, model: embed.Model) -> int:
    router = Router(store)
    changed = 0
    for row in store.db.execute("SELECT id, embedding, roots, head_id FROM element").fetchall():
        head_id, score = router.assign(embed.unpack(row["embedding"]), json.loads(row["roots"] or "[]"), model.idf)
        store.db.execute("UPDATE element SET head_id=?, head_score=? WHERE id=?", (head_id, round(score, 4), row["id"]))
        changed += head_id != row["head_id"]
    return changed


def sequence_all(store: Store) -> None:
    """Within each head: definitions and simple ideas first, dependent and complex ideas later."""
    db = store.db
    for (head_id,) in db.execute("SELECT DISTINCT head_id FROM element").fetchall():
        rows = db.execute("SELECT id, roots, complexity, definitional, count FROM element WHERE head_id=?", (head_id,)).fetchall()
        defined = set()
        for row in rows:
            if row["definitional"]:
                defined.update(json.loads(row["roots"] or "[]")[:2])
        keyed = []
        for row in rows:
            roots = json.loads(row["roots"] or "[]")
            subject = set(roots[:2]) if row["definitional"] else set()
            depends = len([r for r in set(roots) if r in defined and r not in subject])
            key = row["complexity"] - (0.12 if row["definitional"] else 0) + 0.03 * min(4, depends) - 0.01 * min(5, row["count"] - 1)
            keyed.append((key, row["id"]))
        keyed.sort()
        db.executemany("UPDATE element SET seq=? WHERE id=?", [(i + 1, element_id) for i, (_, element_id) in enumerate(keyed)])
    _head_stats(store)


def _head_stats(store: Store) -> None:
    db = store.db
    for head in db.execute("SELECT id FROM head").fetchall():
        head_id = head["id"]
        elements = db.execute("SELECT COUNT(*) FROM element WHERE head_id=?", (head_id,)).fetchone()[0]
        sources = db.execute("SELECT COUNT(DISTINCT es.source_id) FROM element_source es JOIN element e ON e.id=es.element_id "
                             "WHERE e.head_id=?", (head_id,)).fetchone()[0]
        pairs = Counter()
        for row in db.execute("SELECT roots FROM element WHERE head_id=? ORDER BY count DESC LIMIT 4000", (head_id,)):
            roots = json.loads(row["roots"] or "[]")
            for a, b in zip(roots, roots[1:]):
                if a != b:
                    pairs[(a, b)] += 1
        phrases = [f"{a} {b}" for (a, b), n in pairs.most_common(12) if n >= 2]
        db.execute("UPDATE head SET elements=?, sources=?, phrases=? WHERE id=?", (elements, sources, json.dumps(phrases), head_id))
