"""Condense many projects into ``classes.py`` and ``functions.py``, each self-indexing.

The output is not a dump. Each generated file opens with a navigable header that gives
every symbol its line span in the *generated* file, so an agent can jump straight to a
region without reading the file. Bodies carry their own edge comments, so a single
region read is self-describing.

This is the "one master codebase" direction. ``fanout.py`` is the inverse.
"""

from __future__ import annotations

import datetime as _dt
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from .address import Address
from .spec import (
    EDGE_IN,
    EDGE_NONE,
    EDGE_OUT,
    KIND_CLASS,
    KIND_CONST,
    MIRROR_PREFIX,
    SPEC_VERSION,
)
from .store import Store

# Functional areas for functions.py. Order is the file order; first match wins.
FUNCTIONAL_AREAS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("io & filesystem", ("read", "write", "open", "save", "load", "file", "path",
                         "dir", "copy", "move", "delete", "glob", "walk")),
    ("parsing & scanning", ("parse", "scan", "lex", "token", "ast", "extract",
                            "decode", "split", "match", "regex")),
    ("formatting & render", ("format", "render", "print", "display", "pretty",
                             "template", "markdown", "html", "encode", "dump")),
    ("network & api", ("http", "request", "fetch", "post", "get_url", "api",
                       "client", "download", "upload", "session")),
    ("data & transform", ("convert", "transform", "map", "filter", "merge",
                          "normalize", "aggregate", "group", "sort", "flatten")),
    ("validation & guards", ("valid", "check", "verify", "assert", "ensure",
                             "guard", "sanit", "clamp", "require")),
    ("state & storage", ("store", "cache", "persist", "db", "sql", "query",
                         "insert", "update", "commit", "migrate")),
    ("llm & prompting", ("prompt", "llm", "complete", "chat", "embed", "token",
                         "model", "ollama", "generate")),
    ("ui & interaction", ("build_", "on_", "handle", "click", "bind", "widget",
                          "tab", "dialog", "menu", "refresh")),
    ("timing & retry", ("retry", "backoff", "sleep", "delay", "timeout", "clock",
                        "schedule", "throttle", "debounce")),
    ("logging & errors", ("log", "warn", "error", "trace", "debug", "report",
                          "raise", "fail")),
    ("misc helpers", ()),
)


@dataclass
class CondensedSymbol:
    """One symbol placed into a generated file."""

    address: str
    name: str
    kind: str
    project: str
    bucket: str
    source_path: str
    source_span: tuple[int, int]
    signature: str
    doc: str
    calls: list[str]
    called_by: list[str]
    code: str
    area: str = ""
    out_start: int = 0
    out_end: int = 0


@dataclass
class CondenseResult:
    classes_text: str = ""
    functions_text: str = ""
    classes_symbols: list[CondensedSymbol] = field(default_factory=list)
    functions_symbols: list[CondensedSymbol] = field(default_factory=list)
    skipped: list[str] = field(default_factory=list)

    @property
    def total(self) -> int:
        return len(self.classes_symbols) + len(self.functions_symbols)


def _area_for(symbol_name: str, doc: str) -> str:
    blob = f"{symbol_name} {doc}".lower()
    for area, terms in FUNCTIONAL_AREAS:
        if not terms:
            continue
        if any(term in blob for term in terms):
            return area
    return "misc helpers"


def _read_span(
    root: Path, rel: str, start: int, end: int, expect_hash: str = ""
) -> tuple[str | None, bool]:
    """Read a span, and say whether it still matches the hash recorded at index time.

    Returns ``(code, stale)``. A stale span means the file changed since indexing and
    the line numbers now point at something else -- emitting it would put the wrong
    code under the right name, which is worse than emitting nothing.
    """
    source = Path(root) / rel
    try:
        lines = source.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return None, False
    if start < 1 or start > len(lines):
        return None, False
    code = "\n".join(lines[start - 1 : min(end, len(lines))])
    if expect_hash:
        from .scanner import _hash
        return code, _hash(code) != expect_hash
    return code, False


def _mirror(symbol: CondensedSymbol) -> list[str]:
    outs = ",".join(symbol.calls) if symbol.calls else EDGE_NONE
    ins = ",".join(symbol.called_by) if symbol.called_by else EDGE_NONE
    return [
        f"{MIRROR_PREFIX} {symbol.address}",
        f"{MIRROR_PREFIX} origin {symbol.source_path}"
        f" L{symbol.source_span[0]}-{symbol.source_span[1]}",
        f"{MIRROR_PREFIX} {EDGE_OUT}{outs}",
        f"{MIRROR_PREFIX} {EDGE_IN}{ins}",
    ]


def collect(
    store: Store,
    project_ids: list[int] | None = None,
    include_private: bool = False,
) -> tuple[list[CondensedSymbol], list[str]]:
    """Pull every symbol's source out of the indexed projects."""
    if project_ids:
        placeholders = ",".join("?" for _ in project_ids)
        rows = store.many(
            f"SELECT s.*, p.name AS project, p.bucket AS bucket, p.root AS root "
            f"FROM symbols s JOIN projects p ON p.id = s.project_id "
            f"WHERE s.project_id IN ({placeholders}) ORDER BY p.name, s.path, s.line_start",
            project_ids,
        )
    else:
        rows = store.many(
            "SELECT s.*, p.name AS project, p.bucket AS bucket, p.root AS root "
            "FROM symbols s JOIN projects p ON p.id = s.project_id "
            "ORDER BY p.name, s.path, s.line_start"
        )

    collected: list[CondensedSymbol] = []
    skipped: list[str] = []
    seen_bodies: dict[str, str] = {}

    for row in rows:
        if row["kind"] == KIND_CONST:
            continue
        if not include_private and row["kind"] == "f":
            continue
        # Methods arrive with their class; do not emit them twice.
        if "." in row["name"] and row["kind"] != KIND_CLASS:
            continue

        code, stale = _read_span(
            Path(row["root"]), row["path"], int(row["line_start"]),
            int(row["line_end"]), row["body_hash"],
        )
        if code is None:
            skipped.append(f"{row['address']} (source unreadable)")
            continue
        if stale:
            skipped.append(
                f"{row['address']} (STALE -- {row['path']} changed since indexing; "
                f"re-index this project before condensing it)"
            )
            continue

        fingerprint = row["body_hash"] + str(len(code))
        if fingerprint in seen_bodies:
            skipped.append(f"{row['address']} (duplicate of {seen_bodies[fingerprint]})")
            continue
        seen_bodies[fingerprint] = row["address"]

        collected.append(
            CondensedSymbol(
                address=row["address"],
                name=row["name"],
                kind=row["kind"],
                project=row["project"],
                bucket=row["bucket"],
                source_path=row["path"],
                source_span=(int(row["line_start"]), int(row["line_end"])),
                signature=row["signature"],
                doc=row["doc"] or "",
                calls=[c for c in (row["calls"] or "").split(",") if c],
                called_by=[c for c in (row["called_by"] or "").split(",") if c],
                code=code,
                area=_area_for(row["name"], row["doc"] or ""),
            )
        )

    return collected, skipped


def _emit(
    symbols: list[CondensedSymbol],
    title: str,
    group_key,
    group_label: str,
) -> str:
    """Render one condensed file: header placeholder, bodies, then a real header."""
    groups: dict[str, list[CondensedSymbol]] = defaultdict(list)
    for symbol in symbols:
        groups[group_key(symbol)].append(symbol)

    ordered_groups = (
        [name for name, _ in FUNCTIONAL_AREAS if name in groups]
        if group_label == "area"
        else sorted(groups)
    )
    for name in groups:
        if name not in ordered_groups:
            ordered_groups.append(name)

    # ``body`` holds one entry per *line*, never a multi-line blob -- otherwise the
    # recorded spans count list elements instead of lines, and every symbol in the
    # generated map claims to be two lines long.
    body: list[str] = []
    for name in ordered_groups:
        members = groups[name]
        body.append("")
        body.append("# " + "=" * 76)
        body.append(f"# SECTION: {name}   ({len(members)} symbols)")
        body.append("# " + "=" * 76)
        body.append("")
        for symbol in sorted(members, key=lambda s: s.name):
            body.extend(_mirror(symbol))
            code_lines = symbol.code.rstrip().splitlines()
            start_marker = len(body)          # 0-based index of the first code line
            body.extend(code_lines)
            symbol._start_marker = start_marker              # type: ignore[attr-defined]
            symbol._end_marker = len(body) - 1               # type: ignore[attr-defined]
            body.append("")

    stamp = _dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    header: list[str] = [
        '"""',
        f"{title}",
        "",
        f"Generated by Atlas (spec {SPEC_VERSION}) on {stamp}.",
        "Condensed from indexed projects. Every symbol keeps its origin address, so a",
        "change here can always be traced back to the project it came from.",
        "",
        "HOW TO READ THIS FILE",
        "  Do not read it top to bottom. Use the MAP below: find the symbol, note its",
        "  line span, and fetch only that span. Each body carries its own edge comments,",
        "  so one span is enough to know what else to fetch.",
        "",
        "MAP",
    ]

    map_lines: list[str] = []
    for name in ordered_groups:
        members = sorted(groups[name], key=lambda s: s.name)
        map_lines.append(f"  [{name}]")
        for symbol in members:
            map_lines.append(f"    LSPAN {symbol.name}  <- {symbol.address}")

    # Header height is now known, so absolute spans can be resolved in one pass.
    header_height = len(header) + len(map_lines) + 2  # + closing quotes + blank
    for name in ordered_groups:
        for symbol in groups[name]:
            symbol.out_start = header_height + symbol._start_marker + 1  # type: ignore[attr-defined]
            symbol.out_end = header_height + symbol._end_marker + 1      # type: ignore[attr-defined]

    resolved_map: list[str] = []
    for name in ordered_groups:
        members = sorted(groups[name], key=lambda s: s.name)
        resolved_map.append(f"  [{name}]")
        for symbol in members:
            resolved_map.append(
                f"    L{symbol.out_start:05d}-{symbol.out_end:05d}  {symbol.name}"
                f"  <- {symbol.address}"
            )

    return "\n".join(header + resolved_map + ['"""', ""] + body) + "\n"


def condense(
    store: Store,
    project_ids: list[int] | None = None,
    include_private: bool = False,
) -> CondenseResult:
    """Build ``classes.py`` and ``functions.py`` from the indexed universe."""
    symbols, skipped = collect(store, project_ids, include_private)
    classes = [s for s in symbols if s.kind == KIND_CLASS]
    functions = [s for s in symbols if s.kind != KIND_CLASS]

    result = CondenseResult(skipped=skipped)
    result.classes_symbols = classes
    result.functions_symbols = functions
    result.classes_text = _emit(
        classes, "classes.py -- every class in the indexed universe",
        lambda s: s.bucket, "bucket",
    )
    result.functions_text = _emit(
        functions, "functions.py -- every function, grouped by functional area",
        lambda s: s.area, "area",
    )
    return result


def write(result: CondenseResult, destination: Path) -> list[Path]:
    """Write the condensed files, returning what was written."""
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []

    classes_path = destination / "classes.py"
    classes_path.write_text(result.classes_text, encoding="utf-8")
    written.append(classes_path)

    functions_path = destination / "functions.py"
    functions_path.write_text(result.functions_text, encoding="utf-8")
    written.append(functions_path)

    manifest = [
        "# CONDENSE MANIFEST",
        f"# generated {_dt.datetime.now().isoformat(timespec='seconds')}",
        f"# classes: {len(result.classes_symbols)}  functions: {len(result.functions_symbols)}",
        f"# skipped: {len(result.skipped)}",
        "",
    ]
    for item in result.skipped:
        manifest.append(f"SKIP {item}")
    manifest_path = destination / "CONDENSE_MANIFEST.txt"
    manifest_path.write_text("\n".join(manifest) + "\n", encoding="utf-8")
    written.append(manifest_path)

    return written
