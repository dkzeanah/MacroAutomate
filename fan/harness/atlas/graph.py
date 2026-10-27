"""Resolve raw callee names into edges, in both directions.

The scanner records *what a symbol calls* as bare text (``self.plan``, ``registry.dispatch``).
This module turns that text into edges between indexed symbols and, crucially, builds the
reverse edge as well. The reverse edge is what makes "what breaks if I change this" a
lookup instead of a grep.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass

from .scanner import FileScan, Symbol


@dataclass
class ResolvedGraph:
    """Forward and reverse adjacency over one project's symbols."""

    # symbol.name (file-qualified as "path::name") -> list of the same
    out_edges: dict[str, list[str]]
    in_edges: dict[str, list[str]]
    unresolved: dict[str, list[str]]

    def outs(self, key: str) -> list[str]:
        return self.out_edges.get(key, [])

    def ins(self, key: str) -> list[str]:
        return self.in_edges.get(key, [])


def key_of(symbol: Symbol) -> str:
    """Globally unique key for a symbol within one project."""
    return f"{symbol.path}::{symbol.name}"


def _short(key: str) -> str:
    """Render an edge compactly for the index line."""
    path, _, name = key.partition("::")
    stem = path.rsplit("/", 1)[-1]
    if stem.endswith(".py"):
        stem = stem[:-3]
    elif stem.endswith(".pyw"):
        stem = stem[:-4]
    return f"{stem}.{name}"


def build(scans: list[FileScan]) -> ResolvedGraph:
    """Link every call site that can be linked; keep the rest as ``unresolved``."""
    symbols: list[Symbol] = []
    for scan in scans:
        symbols.extend(scan.symbols)

    # Several lookup tables, cheapest match first.
    by_key: dict[str, Symbol] = {key_of(s): s for s in symbols}
    by_leaf: dict[str, list[str]] = defaultdict(list)
    by_qual: dict[str, list[str]] = defaultdict(list)
    for symbol in symbols:
        by_leaf[symbol.leaf].append(key_of(symbol))
        by_qual[symbol.name].append(key_of(symbol))

    # Which class does each file define? Used to bind `self.x` to `Class.x`.
    owner_of: dict[str, str] = {}
    for symbol in symbols:
        if symbol.owner:
            owner_of[key_of(symbol)] = f"{symbol.path}::{symbol.owner}"

    out_edges: dict[str, list[str]] = defaultdict(list)
    in_edges: dict[str, list[str]] = defaultdict(list)
    unresolved: dict[str, list[str]] = defaultdict(list)

    for symbol in symbols:
        source_key = key_of(symbol)
        for raw in symbol.calls:
            target = _resolve(raw, symbol, by_key, by_qual, by_leaf)
            if target is None:
                if raw not in unresolved[source_key]:
                    unresolved[source_key].append(raw)
                continue
            if target == source_key:
                continue  # recursion is not an informative edge
            if target not in out_edges[source_key]:
                out_edges[source_key].append(target)
            if source_key not in in_edges[target]:
                in_edges[target].append(source_key)

    return ResolvedGraph(dict(out_edges), dict(in_edges), dict(unresolved))


def _resolve(
    raw: str,
    caller: Symbol,
    by_key: dict[str, Symbol],
    by_qual: dict[str, list[str]],
    by_leaf: dict[str, list[str]],
) -> str | None:
    """Map one raw callee string to a symbol key, preferring the nearest match."""
    parts = raw.split(".")

    # self.method / cls.method -> sibling in the same class
    if parts[0] in {"self", "cls"} and len(parts) >= 2:
        if caller.owner:
            candidate = f"{caller.path}::{caller.owner}.{parts[1]}"
            if candidate in by_key:
                return candidate
        return _pick(by_leaf.get(parts[1], []), caller)

    # Fully qualified within a file: Class.method
    if len(parts) >= 2:
        qual = ".".join(parts[-2:])
        hits = by_qual.get(qual)
        if hits:
            return _pick(hits, caller)

    # Bare name
    hits = by_qual.get(parts[-1]) or by_leaf.get(parts[-1])
    if hits:
        return _pick(hits, caller)
    return None


def _pick(candidates: list[str], caller: Symbol) -> str | None:
    """Same file beats another file; otherwise the first stable candidate."""
    if not candidates:
        return None
    if len(candidates) == 1:
        return candidates[0]
    same_file = [c for c in candidates if c.startswith(caller.path + "::")]
    if same_file:
        return same_file[0]
    # Ambiguous across files -- an edge to one of several same-named symbols would be a
    # lie, so emit nothing rather than mislead the reader of the index.
    return None


def annotate(scans: list[FileScan], graph: ResolvedGraph) -> None:
    """Write resolved edges back onto the Symbol records, in display form."""
    for scan in scans:
        for symbol in scan.symbols:
            key = key_of(symbol)
            symbol.calls = [_short(k) for k in graph.outs(key)]
            symbol.called_by = [_short(k) for k in graph.ins(key)]


def orphans(scans: list[FileScan], graph: ResolvedGraph) -> list[Symbol]:
    """Symbols nothing calls -- entry points, dead code, or untested surface."""
    out: list[Symbol] = []
    for scan in scans:
        for symbol in scan.symbols:
            if not graph.ins(key_of(symbol)):
                out.append(symbol)
    return out


def hubs(scans: list[FileScan], graph: ResolvedGraph, top: int = 15) -> list[tuple[Symbol, int]]:
    """The most-depended-upon symbols. Changing these is expensive; read them first."""
    scored: list[tuple[Symbol, int]] = []
    for scan in scans:
        for symbol in scan.symbols:
            count = len(graph.ins(key_of(symbol)))
            if count:
                scored.append((symbol, count))
    scored.sort(key=lambda pair: pair[1], reverse=True)
    return scored[:top]
