"""Find every group of symbols that are the same thing, across a whole universe.

Naive pairwise comparison is O(n^2) -- on 2,000 symbols that is four million AST
comparisons, and on a swept desktop it is far worse. So this module blocks first:
identical hashes cluster in one pass through a dict, and only symbols that already
share structural fingerprints are ever compared in detail.

Embeddings are optional and additive. ``sidelearner.router.embeddings`` already
provides a model-free ``TokenHashEmbedder``, so intent matching costs no new dependency.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from .normalize import (
    DIVERGED,
    FORMATTING,
    IDENTICAL,
    LOSSLESS,
    NEAR,
    RENAMED,
    Normalized,
    normalize,
    relate,
)

# A pair is only compared in detail once it shares at least this many shingles.
MIN_SHARED_SHINGLES = 3
# Shingles appearing in more symbols than this are boilerplate and carry no signal.
MAX_SHINGLE_FANOUT = 60

RELATION_RANK = {
    IDENTICAL: 5, FORMATTING: 4, RENAMED: 3, NEAR: 2, DIVERGED: 1,
}


@dataclass
class Entry:
    """One symbol under consideration, with its source and normalization."""

    address: str
    name: str
    kind: str
    project: str
    path: str
    line_start: int
    line_end: int
    code: str
    norm: Normalized
    mtime: float = 0.0
    signature: str = ""
    doc: str = ""

    @property
    def lines(self) -> int:
        return self.line_end - self.line_start + 1

    @property
    def leaf(self) -> str:
        return self.name.rsplit(".", 1)[-1]


@dataclass
class Cluster:
    """A set of symbols judged to be the same thing."""

    members: list[Entry] = field(default_factory=list)
    relation: str = IDENTICAL
    confidence: float = 1.0

    @property
    def size(self) -> int:
        return len(self.members)

    @property
    def projects(self) -> set[str]:
        return {m.project for m in self.members}

    @property
    def lossless(self) -> bool:
        """True when collapsing this cluster to one copy discards nothing."""
        return self.relation in LOSSLESS

    @property
    def wasted_lines(self) -> int:
        """Lines that would be reclaimed by keeping only the largest member."""
        if self.size < 2:
            return 0
        return sum(m.lines for m in self.members) - max(m.lines for m in self.members)

    def canonical(self, prefer_newest: bool = True) -> Entry:
        """The member best placed to represent the cluster."""
        return max(
            self.members,
            key=lambda m: (m.mtime if prefer_newest else 0, m.lines, len(m.doc)),
        )

    def describe(self) -> str:
        head = f"{self.relation.upper():<11} x{self.size}  {self.members[0].leaf}"
        where = ", ".join(sorted(self.projects))[:70]
        return f"{head}  [{where}]"


# ------------------------------------------------------------------------ loading

def load_entries(
    store,
    project_ids: list[int] | None = None,
    include_private: bool = True,
    min_lines: int = 3,
) -> tuple[list[Entry], list[str]]:
    """Read every indexed symbol's source and normalize it.

    Symbols below ``min_lines`` are skipped: a two-line getter is identical to a
    thousand other two-line getters, and reporting that is noise, not insight.
    """
    where, params = "", []
    if project_ids:
        where = f" WHERE s.project_id IN ({','.join('?' for _ in project_ids)})"
        params = list(project_ids)

    rows = store.many(
        "SELECT s.*, p.name AS project, p.root AS root FROM symbols s "
        "JOIN projects p ON p.id = s.project_id" + where,
        params,
    )

    entries: list[Entry] = []
    problems: list[str] = []
    mtimes: dict[str, float] = {}

    for row in rows:
        if not include_private and row["kind"] == "f":
            continue
        span = int(row["line_end"]) - int(row["line_start"]) + 1
        if span < min_lines:
            continue

        source = Path(row["root"]) / row["path"]
        key = str(source)
        if key not in mtimes:
            try:
                mtimes[key] = source.stat().st_mtime
            except OSError:
                mtimes[key] = 0.0
        try:
            lines = source.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError as exc:
            problems.append(f"{row['address']}: {exc}")
            continue

        start, end = int(row["line_start"]), int(row["line_end"])
        if start < 1 or start > len(lines):
            problems.append(f"{row['address']}: span outside file (stale index)")
            continue
        code = "\n".join(lines[start - 1 : min(end, len(lines))])

        entries.append(
            Entry(
                address=row["address"], name=row["name"], kind=row["kind"],
                project=row["project"], path=row["path"],
                line_start=start, line_end=end, code=code,
                norm=normalize(code, row["name"]), mtime=mtimes[key],
                signature=row["signature"], doc=row["doc"] or "",
            )
        )
    return entries, problems


# --------------------------------------------------------------------- union-find

class _Union:
    def __init__(self, size: int) -> None:
        self.parent = list(range(size))

    def find(self, i: int) -> int:
        while self.parent[i] != i:
            self.parent[i] = self.parent[self.parent[i]]
            i = self.parent[i]
        return i

    def join(self, a: int, b: int) -> None:
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.parent[rb] = ra


# --------------------------------------------------------------------- clustering

def cluster(
    entries: list[Entry],
    near_threshold: float = 0.72,
    include_near: bool = True,
    cross_project_only: bool = False,
    min_nodes: int = 12,
) -> list[Cluster]:
    """Group every symbol that is the same thing as another.

    Three passes, each cheaper than the comparison it avoids: exact hashes, then
    structural hashes, then a shingle inverted index that proposes only the pairs
    worth an actual comparison.
    """
    if not entries:
        return []

    union = _Union(len(entries))
    relations: dict[tuple[int, int], tuple[str, float]] = {}

    def link(i: int, j: int, relation: str, confidence: float) -> None:
        union.join(i, j)
        key = (min(i, j), max(i, j))
        existing = relations.get(key)
        # Passes run weakest-claim-last, so a later pass must never downgrade a pair
        # already known to be identical. Without this, byte-identical copies get
        # reported as merely "renamed" and look riskier to merge than they are.
        if existing and RELATION_RANK.get(existing[0], 0) >= RELATION_RANK.get(relation, 0):
            return
        relations[key] = (relation, confidence)

    # -- passes 1-3: hash equality, one dict sweep each, strongest claim first
    for attribute, relation in (("exact_hash", IDENTICAL),
                                ("text_hash", FORMATTING),
                                ("shape_hash", RENAMED)):
        buckets: dict[str, list[int]] = defaultdict(list)
        for index, entry in enumerate(entries):
            value = getattr(entry.norm, attribute)
            if not value:
                continue
            # A trivial shape (a bare assignment, a one-line wrapper) matches half the
            # codebase and means nothing. Byte equality still counts at any size.
            if attribute == "shape_hash" and entry.norm.node_count < min_nodes:
                continue
            buckets[value].append(index)
        for members in buckets.values():
            for other in members[1:]:
                link(members[0], other, relation, 1.0)

    # -- pass 3: near matches, restricted by a shingle inverted index
    if include_near:
        inverted: dict[str, list[int]] = defaultdict(list)
        for index, entry in enumerate(entries):
            for shingle in entry.norm.shingles:
                inverted[shingle].append(index)

        candidates: dict[tuple[int, int], int] = defaultdict(int)
        for members in inverted.values():
            if len(members) < 2 or len(members) > MAX_SHINGLE_FANOUT:
                continue  # too common to discriminate
            for a_pos, a in enumerate(members):
                for b in members[a_pos + 1 :]:
                    candidates[(min(a, b), max(a, b))] += 1

        for (a, b), shared in candidates.items():
            if shared < MIN_SHARED_SHINGLES:
                continue
            if min(entries[a].norm.node_count, entries[b].norm.node_count) < min_nodes:
                continue
            if union.find(a) == union.find(b):
                continue
            relation, confidence = relate(entries[a].norm, entries[b].norm, near_threshold)
            if relation in {NEAR} or (relation == RENAMED):
                link(a, b, relation, confidence)

    # -- collect
    grouped: dict[int, list[int]] = defaultdict(list)
    for index in range(len(entries)):
        grouped[union.find(index)].append(index)

    clusters: list[Cluster] = []
    for members in grouped.values():
        if len(members) < 2:
            continue
        group = [entries[i] for i in members]
        if cross_project_only and len({m.project for m in group}) < 2:
            continue

        # The cluster's relation is the weakest link in it -- claiming IDENTICAL for a
        # group held together by a NEAR edge would licence a merge that loses code.
        weakest, weakest_confidence = IDENTICAL, 1.0
        for a_pos, a in enumerate(members):
            for b in members[a_pos + 1 :]:
                relation, confidence = relations.get(
                    (min(a, b), max(a, b)), (None, 0.0)
                )
                if relation is None:
                    relation, confidence = relate(entries[a].norm, entries[b].norm)
                if RELATION_RANK.get(relation, 0) < RELATION_RANK.get(weakest, 0):
                    weakest, weakest_confidence = relation, confidence
        clusters.append(Cluster(members=group, relation=weakest,
                                confidence=weakest_confidence))

    clusters.sort(key=lambda c: (-c.wasted_lines, -c.size))
    return clusters


# ------------------------------------------------------------------------ report

def duplication_report(clusters: list[Cluster], limit: int = 40) -> str:
    """A human-readable summary of what is duplicated and what it costs."""
    if not clusters:
        return "No duplicate symbols found."

    lossless = [c for c in clusters if c.lossless]
    structural = [c for c in clusters if c.relation == RENAMED]
    near = [c for c in clusters if c.relation == NEAR]

    out = [
        "DUPLICATION REPORT",
        "=" * 76,
        f"  {len(clusters)} clusters covering {sum(c.size for c in clusters)} symbols",
        f"  {len(lossless):>4} identical or formatting-only  "
        f"({sum(c.wasted_lines for c in lossless):,} lines reclaimable with zero risk)",
        f"  {len(structural):>4} structurally identical (renamed locals or literals)",
        f"  {len(near):>4} near matches -- review before merging",
        "",
        f"Top {min(limit, len(clusters))} by reclaimable lines:",
        "",
    ]
    for group in clusters[:limit]:
        out.append(f"  {group.describe()}   -{group.wasted_lines}L")
        for member in sorted(group.members, key=lambda m: -m.mtime)[:6]:
            out.append(f"      {member.address}  ({member.lines}L)")
        if group.size > 6:
            out.append(f"      ... and {group.size - 6} more")
    return "\n".join(out)


# ------------------------------------------------------------- optional embeddings

def semantic_neighbours(
    entries: list[Entry], query: str, top: int = 10
) -> list[tuple[Entry, float]]:
    """Rank symbols by intent similarity to a natural-language query.

    Uses SideLearner's embedder when it is importable, and degrades to token overlap
    when it is not, so this never becomes a hard dependency.
    """
    texts = [f"{e.leaf} {e.signature} {e.doc}" for e in entries]
    try:
        from sidelearner.router.embeddings import get_embedder

        embedder = get_embedder()
        vectors = [embedder.embed(text) for text in texts]
        target = embedder.embed(query)
        scored = [(entry, _cosine(target, vector))
                  for entry, vector in zip(entries, vectors)]
    except Exception:
        wanted = set(query.lower().split())
        scored = [
            (entry, len(wanted & set(text.lower().split())) / max(len(wanted), 1))
            for entry, text in zip(entries, texts)
        ]
    scored.sort(key=lambda pair: pair[1], reverse=True)
    return scored[:top]


def _cosine(a, b) -> float:
    try:
        dot = sum(x * y for x, y in zip(a, b))
        na = sum(x * x for x in a) ** 0.5
        nb = sum(y * y for y in b) ** 0.5
        return dot / (na * nb) if na and nb else 0.0
    except TypeError:
        return 0.0
