"""Tier-2 retrieval: fetch exactly one symbol by address, and nothing else.

A slice is self-describing. It carries its own address, span, hash and both edge
directions, so an agent holding one slice already knows which two or three addresses
are worth fetching next -- and never has to open a file to find out.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from pathlib import Path

from .address import Address, AddressError
from .spec import EDGE_IN, EDGE_NONE, EDGE_OUT, MIRROR_PREFIX, token_estimate
from .store import Store


@dataclass
class Slice:
    """One retrieved symbol, with the map fragment that came with it."""

    address: str
    path: str
    line_start: int
    line_end: int
    signature: str
    body_hash: str
    doc: str
    calls: list[str]
    called_by: list[str]
    flags: str
    code: str
    stale: bool = False

    @property
    def tokens(self) -> int:
        return token_estimate(self.render())

    def header(self) -> str:
        outs = ",".join(self.calls) if self.calls else EDGE_NONE
        ins = ",".join(self.called_by) if self.called_by else EDGE_NONE
        stale = "  [STALE: file changed since indexing]" if self.stale else ""
        return (
            f"{MIRROR_PREFIX} {self.address}  L{self.line_start}-{self.line_end} "
            f"h:{self.body_hash}\n"
            f"{MIRROR_PREFIX} {EDGE_OUT}{outs}\n"
            f"{MIRROR_PREFIX} {EDGE_IN}{ins}{stale}"
        )

    def render(self) -> str:
        return self.header() + "\n" + self.code


class SliceError(LookupError):
    """Raised when an address cannot be resolved to code on disk."""


def _row_to_slice(row: sqlite3.Row, code: str, stale: bool) -> Slice:
    return Slice(
        address=row["address"],
        path=row["path"],
        line_start=int(row["line_start"]),
        line_end=int(row["line_end"]),
        signature=row["signature"],
        body_hash=row["body_hash"],
        doc=row["doc"],
        calls=[c for c in (row["calls"] or "").split(",") if c],
        called_by=[c for c in (row["called_by"] or "").split(",") if c],
        flags=row["flags"] or "",
        code=code,
        stale=stale,
    )


def get(store: Store, address: str | Address, context_lines: int = 0) -> Slice:
    """Fetch the code for one address. This is the only sanctioned way to read code."""
    addr = address if isinstance(address, Address) else Address.parse(str(address))
    if addr.level != "symbol":
        raise SliceError(f"{addr} is not a symbol address; slices are symbol-level")

    row = store.symbol_by_address(str(addr))
    if row is None:
        raise SliceError(f"unknown address {addr} -- not in the index")

    source = Path(row["root"]) / row["path"]
    if not source.exists():
        raise SliceError(f"source missing on disk: {source}")

    lines = source.read_text(encoding="utf-8", errors="replace").splitlines()
    start = max(1, int(row["line_start"]) - context_lines)
    end = min(len(lines), int(row["line_end"]) + context_lines)
    code = "\n".join(lines[start - 1 : end])

    from .scanner import _hash  # local import keeps the module graph shallow

    exact = "\n".join(lines[int(row["line_start"]) - 1 : int(row["line_end"])])
    stale = _hash(exact) != row["body_hash"]
    return _row_to_slice(row, code, stale)


def get_many(
    store: Store, addresses: list[str], budget_tokens: int = 4000
) -> tuple[list[Slice], list[str], int]:
    """Fetch several slices under a token budget.

    Returns (slices, skipped_addresses, tokens_used). The budget is the whole point:
    an agent asks for ten things, gets the six that fit, and is told what it did not get.
    """
    out: list[Slice] = []
    skipped: list[str] = []
    used = 0
    for address in addresses:
        try:
            piece = get(store, address)
        except (SliceError, AddressError) as exc:
            skipped.append(f"{address} ({exc})")
            continue
        cost = piece.tokens
        if used + cost > budget_tokens and out:
            skipped.append(f"{address} (budget)")
            continue
        out.append(piece)
        used += cost
    return out, skipped, used


def expand(store: Store, address: str, depth: int = 1, budget_tokens: int = 6000) -> list[Slice]:
    """Fetch a symbol plus everything it calls, ``depth`` hops out.

    This is the "follow the map" primitive: one address in, a coherent, bounded
    reading set out, ordered so the requested symbol comes first.
    """
    seen: set[str] = set()
    frontier = [address]
    collected: list[Slice] = []
    used = 0

    for _ in range(max(0, depth) + 1):
        next_frontier: list[str] = []
        for item in frontier:
            if item in seen:
                continue
            seen.add(item)
            try:
                piece = get(store, item)
            except (SliceError, AddressError):
                continue
            if used + piece.tokens > budget_tokens and collected:
                continue
            collected.append(piece)
            used += piece.tokens
            for callee in piece.calls:
                resolved = _resolve_short(store, item, callee)
                if resolved and resolved not in seen:
                    next_frontier.append(resolved)
        frontier = next_frontier
        if not frontier:
            break
    return collected


def _resolve_short(store: Store, origin: str, short: str) -> str | None:
    """Turn an index-form edge (``loop.plan``) back into a full address."""
    try:
        base = Address.parse(origin)
    except AddressError:
        return None
    leaf = short.rsplit(".", 1)[-1]
    rows = store.many(
        "SELECT s.address FROM symbols s JOIN projects p ON p.id = s.project_id "
        "WHERE p.name = ? AND (s.name = ? OR s.name LIKE ?) LIMIT 2",
        (base.project, leaf, f"%.{leaf}"),
    )
    if len(rows) == 1:
        return rows[0]["address"]
    return None


def impact(store: Store, address: str) -> list[sqlite3.Row]:
    """Everything that calls this symbol -- what you must check before changing it."""
    row = store.symbol_by_address(address)
    if row is None:
        return []
    callers = [c for c in (row["called_by"] or "").split(",") if c]
    if not callers:
        return []
    leaves = {c.rsplit(".", 1)[-1] for c in callers}
    placeholders = ",".join("?" for _ in leaves)
    return store.many(
        f"SELECT s.*, p.name AS project FROM symbols s "
        f"JOIN projects p ON p.id = s.project_id "
        f"WHERE s.project_id = ? AND s.name IN ({placeholders})",
        [row["project_id"], *leaves],
    )


# ------------------------------------------------------------- in-file mirror write

def mirror_comments(store: Store, project_id: int, dry_run: bool = True) -> list[str]:
    """Write (or preview) the ``# @atlas`` comment above every indexed symbol.

    Idempotent: an existing mirror block is replaced, not stacked. Returns a report,
    one line per file touched.
    """
    project = store.project(project_id)
    if project is None:
        return ["unknown project"]

    rows = store.symbols(project_id)
    by_file: dict[str, list[sqlite3.Row]] = {}
    for row in rows:
        by_file.setdefault(row["path"], []).append(row)

    report: list[str] = []
    for rel, symbols in sorted(by_file.items()):
        source = Path(project.root) / rel
        if not source.exists():
            continue
        text = source.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines()

        # Strip any previous mirror lines so the pass is idempotent.
        cleaned = [ln for ln in lines if not ln.lstrip().startswith(MIRROR_PREFIX)]
        if cleaned != lines:
            report.append(f"{rel}: cleared {len(lines) - len(cleaned)} stale mirror lines")
            lines = cleaned

        # Insert from the bottom up so earlier spans keep their line numbers.
        ordered = sorted(symbols, key=lambda r: int(r["line_start"]), reverse=True)
        added = 0
        for row in ordered:
            start = int(row["line_start"])
            if start - 1 >= len(lines) or start < 1:
                continue
            target = lines[start - 1]
            indent = target[: len(target) - len(target.lstrip())]
            outs = row["calls"] or EDGE_NONE
            ins = row["called_by"] or EDGE_NONE
            comment = (
                f"{indent}{MIRROR_PREFIX} {EDGE_OUT}{outs} {EDGE_IN}{ins}  "
                f"L{row['line_start']}-{row['line_end']} h:{row['body_hash']}"
            )
            lines.insert(start - 1, comment)
            added += 1
        report.append(f"{rel}: {added} mirrors" + ("  (dry run)" if dry_run else ""))

        if not dry_run and added:
            source.write_text("\n".join(lines) + "\n", encoding="utf-8")

    return report
