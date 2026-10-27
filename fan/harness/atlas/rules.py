"""The rule engine: the write path an agent must pass through before adding code.

Three gates, in order.

1. **Dedupe** -- does this already exist? A ``MISS`` here is authoritative: it means
   stop searching, the thing is genuinely not in the codebase. That single guarantee
   removes the most expensive failure mode there is, which is an agent burning context
   hunting for code that was never written.
2. **Budget** -- how many lines will it be? Declared up front, checked against the
   bucket's ceiling. Oversized symbols are refused, not quietly accepted.
3. **Placement** -- where does it go? The engine answers, not the model. A file and an
   exact insertion line come back, along with what shifts as a result.
"""

from __future__ import annotations

import re
import sqlite3
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from pathlib import Path

from .address import Address
from .buckets import BY_KEY
from .spec import DEFAULT_MAX_SYMBOL_LINES, KIND_CLASS
from .store import Store

_WORD = re.compile(r"[a-z0-9]+")

# Terms that carry no discriminating power in a codebase full of helpers.
_STOP = {
    "the", "a", "an", "and", "or", "of", "to", "for", "in", "on", "with", "from",
    "get", "set", "make", "do", "run", "new", "value", "data", "self", "return",
}

# Verbs that appear on hundreds of unrelated symbols. Matching one of these in a name
# is not evidence that two symbols do the same job -- only the object they act on is.
GENERIC_VERBS = {
    "render", "parse", "build", "create", "load", "save", "read", "write", "send",
    "add", "remove", "delete", "update", "process", "handle", "format", "convert",
    "check", "find", "search", "start", "stop", "init", "close", "open", "list",
    "count", "print", "log", "apply", "call", "file", "files", "text", "string",
    "object", "item", "items", "result", "output", "input", "name", "type",
    "encode", "decode", "compute", "generate", "fetch", "store",
}


def _tokens(text: str) -> set[str]:
    return {w for w in _WORD.findall((text or "").lower()) if w not in _STOP and len(w) > 2}


from functools import lru_cache


@lru_cache(maxsize=32768)
def _split(text: str) -> frozenset[str]:
    """Tokens from an identifier or phrase, snake_case and CamelCase both broken up."""
    spaced = re.sub(r"(?<!^)(?=[A-Z])", " ", text or "").replace("_", " ").replace(".", " ")
    return frozenset(_tokens(spaced))


def _field_hit(token: str, field: set[str]) -> bool:
    """Exact match, or one token being a meaningful prefix of the other.

    ``call`` should match ``callable`` and ``fetch`` should match ``fetcher``, but
    three-letter fragments must not match everything, hence the length floor.
    """
    if token in field:
        return True
    return any(
        (other.startswith(token) or token.startswith(other)) and min(len(token), len(other)) >= 5
        for other in field
    )


def _similarity(query: str, row: sqlite3.Row, cutoff: float = 0.0) -> float:
    """How likely is it that this symbol already does what ``query`` describes?

    Weighted by *where* a term matched. A name match is the strongest evidence a
    codebase offers, so it is worth far more than the same word appearing in a
    parameter list. Long queries are not punished for containing words the symbol
    happens not to use -- that was producing false MISSes, which is the one failure
    this gate exists to prevent.
    """
    q_tokens = _split(query)
    if not q_tokens:
        return 0.0

    name_tokens = _split(row["name"])
    sig_tokens = _split(row["signature"]) - name_tokens
    doc_tokens = _split(row["doc"]) - name_tokens

    weighted = 0.0
    name_anchors: set[str] = set()
    subjects = q_tokens - GENERIC_VERBS
    matched_subjects: set[str] = set()

    for token in q_tokens:
        if _field_hit(token, name_tokens):
            weighted += 1.0
            if len(token) >= 5:
                name_anchors.add(token)
        elif _field_hit(token, doc_tokens):
            weighted += 0.6
        elif _field_hit(token, sig_tokens):
            weighted += 0.45
        else:
            continue
        if token in subjects:
            matched_subjects.add(token)
    coverage = weighted / len(q_tokens)

    # A distinctive word shared with the symbol's own name is the best signal a
    # codebase offers -- but only when it is not a bare generic verb. "render" alone
    # does not make _render a geodesic dome renderer.
    meaningful = name_anchors - GENERIC_VERBS
    anchor_bonus = 0.25 if meaningful else (0.08 if name_anchors else 0.0)

    # The edit-distance contribution cannot exceed .15. Avoid constructing a
    # SequenceMatcher for rows that cannot possibly reach this search's cutoff.
    # Include rounding headroom so the gate retains exactly the same HITs.
    scale = 0.65 + 0.35 * len(matched_subjects) / len(subjects) if subjects else 1.0
    if (0.70 * coverage + anchor_bonus + 0.15) * scale + 0.0005 < cutoff:
        return 0.0

    leaf = row["name"].rsplit(".", 1)[-1].lower()
    name_ratio = SequenceMatcher(None, query.lower().replace(" ", "_"), leaf).ratio()

    score = 0.70 * coverage + anchor_bonus + 0.15 * name_ratio

    # Scale by how much of the query's *subject matter* the symbol actually covers.
    # One incidental noun in common is not a duplicate: "encode a video stream to
    # h264" shares only "stream" with `_chat_stream`, and calling that a HIT is how
    # a dedupe gate stops being worth reading.
    if subjects:
        subject_coverage = len(matched_subjects) / len(subjects)
        score *= 0.65 + 0.35 * subject_coverage

    return round(min(1.0, score), 3)


# ---------------------------------------------------------------------- dedupe gate

@dataclass
class Match:
    address: str
    name: str
    signature: str
    doc: str
    score: float
    lines: int
    project: str
    bucket: str


@dataclass
class FindResult:
    """The answer to 'does this already exist?'. ``hit`` False is a promise, not a shrug."""

    query: str
    hit: bool
    matches: list[Match] = field(default_factory=list)
    searched: int = 0
    buckets: int = 0
    suggestion: str = ""

    def render(self) -> str:
        if self.hit:
            out = [f"HIT  {len(self.matches)} candidate(s) for {self.query!r}:"]
            for match in self.matches:
                out.append(
                    f"  {match.score:.2f}  {match.address}"
                    f"  ({match.lines}L)  {match.signature}"
                )
                if match.doc:
                    out.append(f"        \" {match.doc}")
            out.append("")
            out.append("REUSE the closest match, or justify why a new symbol is needed.")
            return "\n".join(out)
        return (
            f"MISS  no symbol matches {self.query!r}. "
            f"{self.searched} symbols searched across {self.buckets} buckets.\n"
            f"      SAFE TO CREATE. This is authoritative -- stop searching.\n"
            + (f"      Suggested home: {self.suggestion}" if self.suggestion else "")
        )


def find(
    store: Store,
    query: str,
    threshold: float = 0.42,
    limit: int = 6,
    bucket: str | None = None,
) -> FindResult:
    """Search the whole index for an existing symbol that already does this."""
    counts = store.counts()
    rows = store.many(
        "SELECT s.*, p.name AS project, p.bucket AS bucket, p.priority AS priority "
        "FROM symbols s JOIN projects p ON p.id = s.project_id"
        + (" WHERE p.bucket = ?" if bucket else "") + " ORDER BY p.pinned DESC, p.priority DESC, s.address",
        (bucket,) if bucket else (),
    )

    scored: list[Match] = []
    for row in rows:
        score = _similarity(query, row, cutoff=threshold)
        if score >= threshold:
            scored.append(
                Match(
                    address=row["address"],
                    name=row["name"],
                    signature=row["signature"],
                    doc=row["doc"],
                    score=score,
                    lines=int(row["line_end"]) - int(row["line_start"]) + 1,
                    project=row["project"],
                    bucket=row["bucket"],
                )
            )

    scored.sort(key=lambda m: m.score, reverse=True)
    scored = scored[:limit]

    return FindResult(
        query=query,
        hit=bool(scored),
        matches=scored,
        searched=counts["symbols"],
        buckets=counts["buckets"],
        suggestion="" if scored else _suggest_home(store, query, bucket),
    )


def _suggest_home(store: Store, query: str, bucket: str | None) -> str:
    """Where a genuinely new symbol should probably live."""
    q_tokens = _tokens(query)
    # Never propose writing into vendored code -- external projects are marked
    # do-not-edit, and a suggestion that violates that is worse than no suggestion.
    rows = store.many(
        "SELECT s.path, s.address, p.name AS project, p.bucket AS bucket, "
        "MAX(s.line_end) AS tail, COUNT(*) AS n "
        "FROM symbols s JOIN projects p ON p.id = s.project_id "
        "WHERE p.external = 0 "
        + ("AND p.bucket = ? " if bucket else "")
        + "GROUP BY s.project_id, s.path",
        (bucket,) if bucket else (),
    )
    best = None
    best_score = 0.0
    for row in rows:
        stem = Path(row["path"]).stem.replace("_", " ")
        score = len(q_tokens & _tokens(stem)) + 0.01 * int(row["n"])
        if score > best_score:
            best_score, best = score, row
    if best is None:
        return ""
    addr = Address.build(best["bucket"], best["project"], best["path"])
    return f"{addr} after L{best['tail']}"


# ---------------------------------------------------------------------- budget gate

@dataclass
class BudgetVerdict:
    ok: bool
    declared: int
    ceiling: int
    message: str


def check_budget(lines: int, bucket: str = "misc", ceiling: int | None = None) -> BudgetVerdict:
    """Refuse symbols too large to be a single addressable unit."""
    limit = ceiling or BY_KEY.get(bucket, BY_KEY["misc"]).max_symbol_lines or DEFAULT_MAX_SYMBOL_LINES
    if lines <= 0:
        return BudgetVerdict(False, lines, limit, "declare a positive line count first")
    if lines > limit:
        return BudgetVerdict(
            False, lines, limit,
            f"{lines} lines exceeds the {limit}-line ceiling for `{bucket}`. "
            f"Split it into {(lines // limit) + 1} symbols and re-submit.",
        )
    return BudgetVerdict(True, lines, limit, f"{lines}/{limit} lines -- accepted")


# ------------------------------------------------------------------- placement gate

@dataclass
class Placement:
    """Where the engine has decided new code goes."""

    ok: bool
    target_address: str = ""
    file_path: str = ""
    insert_at_line: int = 0
    section: str = ""
    neighbour: str = ""
    shifted: int = 0
    reason: str = ""

    def render(self) -> str:
        if not self.ok:
            return f"REFUSED  {self.reason}"
        return (
            f"TARGET {self.target_address}  INSERT AT L{self.insert_at_line}\n"
            f"  section: {self.section or '(file tail)'}"
            + (f"  neighbour: {self.neighbour}" if self.neighbour else "")
            + f"\n  after commit: {self.shifted} span(s) below shift down\n"
            f"  {self.reason}"
        )


def plan_insert(
    store: Store,
    name: str,
    lines: int,
    bucket: str | None = None,
    project: str | None = None,
    prefer_path: str | None = None,
    kind: str = "F",
) -> Placement:
    """Decide the exact file and line for a new symbol. The engine chooses, not the model.

    Placement prefers, in order: an explicitly requested file, then the file whose
    existing symbols are most lexically related to the new name, then the smallest
    file in the project (so nothing grows without bound).
    """
    budget = check_budget(lines, bucket or "misc")
    if not budget.ok:
        return Placement(False, reason=budget.message)

    where = []
    params: list[object] = []
    if project:
        where.append("p.name = ?")
        params.append(project)
    if bucket:
        where.append("p.bucket = ?")
        params.append(bucket)
    clause = (" WHERE " + " AND ".join(where)) if where else ""

    rows = store.many(
        "SELECT s.*, p.name AS project, p.bucket AS bucket, p.root AS root "
        "FROM symbols s JOIN projects p ON p.id = s.project_id" + clause,
        params,
    )
    if not rows:
        return Placement(
            False,
            reason="no indexed project matches that bucket/project -- index one first",
        )

    by_file: dict[tuple[str, str, str], list[sqlite3.Row]] = {}
    for row in rows:
        by_file.setdefault((row["bucket"], row["project"], row["path"]), []).append(row)

    name_tokens = _tokens(name.replace("_", " "))

    def affinity(key: tuple[str, str, str], members: list[sqlite3.Row]) -> float:
        """Lexical pull only -- how related this file is to the proposed name."""
        _b, _p, path = key
        stem_hit = len(name_tokens & _tokens(Path(path).stem.replace("_", " "))) * 3.0
        sibling_hit = sum(len(name_tokens & _tokens(m["name"])) for m in members) * 0.8
        return stem_hit + sibling_hit

    def file_score(key: tuple[str, str, str], members: list[sqlite3.Row]) -> float:
        _b, _p, path = key
        if prefer_path and path == prefer_path:
            return 1000.0
        # Smaller files are better homes; large ones are already carrying enough.
        size_penalty = max(m["line_end"] for m in members) / 500.0
        test_penalty = 5.0 if "test" in path.lower() else 0.0
        return affinity(key, members) - size_penalty - test_penalty

    best_key = max(by_file, key=lambda k: file_score(k, by_file[k]))

    # With no lexical pull anywhere and no scope given, the tie-break alone decides --
    # and the tie-break favours small files, so an unrelated toy project wins. Refusing
    # is the honest answer: the caller has to say where this belongs.
    if (
        not prefer_path
        and not project
        and not bucket
        and affinity(best_key, by_file[best_key]) == 0
    ):
        buckets = sorted({k[0] for k in by_file})
        return Placement(
            False,
            reason=(
                f"nothing in the index relates to '{name}', and no bucket or project "
                f"was given -- so any choice would be arbitrary. Re-run with "
                f"--bucket (one of: {', '.join(buckets)}) or --project, "
                f"or --path to name the file yourself."
            ),
        )
    members = sorted(by_file[best_key], key=lambda r: int(r["line_start"]))
    b_key, p_key, path = best_key

    # Sit next to the most related sibling; otherwise land at the file tail.
    neighbour = None
    best_affinity = 0
    for row in members:
        if kind == KIND_CLASS and row["kind"] != KIND_CLASS:
            continue
        affinity = len(name_tokens & _tokens(f"{row['name']} {row['doc']}"))
        if affinity > best_affinity:
            best_affinity, neighbour = affinity, row

    if neighbour is not None:
        insert_at = int(neighbour["line_end"]) + 1
        section = f"beside {neighbour['name']}"
        neighbour_desc = f"{neighbour['name']} (L{neighbour['line_start']}-{neighbour['line_end']})"
    else:
        insert_at = max(int(r["line_end"]) for r in members) + 1
        section = "file tail"
        neighbour_desc = ""

    shifted = sum(1 for r in members if int(r["line_start"]) >= insert_at)

    return Placement(
        ok=True,
        target_address=str(Address.build(b_key, p_key, path)),
        file_path=path,
        insert_at_line=insert_at,
        section=section,
        neighbour=neighbour_desc,
        shifted=shifted,
        reason=f"{budget.message}; chose {path} of {len(by_file)} candidate files",
    )


# --------------------------------------------------------------------- combined gate

@dataclass
class GateReport:
    """The full write-path decision, ready to print for an agent."""

    allowed: bool
    find_result: FindResult
    budget: BudgetVerdict
    placement: Placement

    def render(self) -> str:
        out = ["=" * 68, "ATLAS WRITE GATE", "=" * 68, "",
               "[1] DEDUPE", self.find_result.render(), "",
               "[2] BUDGET", f"  {self.budget.message}", "",
               "[3] PLACEMENT", "  " + self.placement.render().replace("\n", "\n  "), "",
               "=" * 68,
               "VERDICT: " + ("PROCEED" if self.allowed else "BLOCKED"),
               "=" * 68]
        return "\n".join(out)


def gate(
    store: Store,
    name: str,
    intent: str,
    lines: int,
    bucket: str | None = None,
    project: str | None = None,
    prefer_path: str | None = None,
) -> GateReport:
    """Run all three gates for a proposed new symbol."""
    found = find(store, intent or name, bucket=bucket)
    budget = check_budget(lines, bucket or "misc")
    placement = (
        plan_insert(store, name, lines, bucket, project, prefer_path)
        if budget.ok else Placement(False, reason=budget.message)
    )
    allowed = (not found.hit) and budget.ok and placement.ok
    return GateReport(allowed, found, budget, placement)
