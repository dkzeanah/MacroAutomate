"""Build the map: scan a project, resolve edges, persist, and render the tier-0/1 text.

``ATLAS.md`` (tier 0) and each project's ``INDEX.md`` (tier 1) are what an LLM actually
reads. Everything else in this package exists to keep those two files true.
"""

from __future__ import annotations

import datetime as _dt
from dataclasses import dataclass
from pathlib import Path

from . import graph as graphmod
from .address import Address
from .buckets import BY_KEY, Verdict, bucket_titles, classify
from .scanner import FileScan, Symbol, scan_project
from .spec import (
    ATLAS_MD,
    EDGE_IN,
    EDGE_NONE,
    EDGE_OUT,
    FLAG_EXTERNAL,
    FLAG_UNTESTED,
    INDEX_MD,
    KIND_CLASS,
    SPEC_VERSION,
    token_estimate,
)


def _now() -> str:
    return _dt.datetime.now().strftime("%Y-%m-%d %H:%M")


@dataclass
class ProjectIndex:
    """The in-memory result of indexing one project."""

    name: str
    root: Path
    bucket: str
    verdict: Verdict
    scans: list[FileScan]
    graph: graphmod.ResolvedGraph
    external: bool = False

    @property
    def symbols(self) -> list[Symbol]:
        out: list[Symbol] = []
        for scan in self.scans:
            out.extend(scan.symbols)
        return out

    @property
    def line_count(self) -> int:
        return sum(s.line_count for s in self.scans)

    @property
    def file_count(self) -> int:
        return len(self.scans)

    @property
    def symbol_count(self) -> int:
        return sum(len(s.symbols) for s in self.scans)

    @property
    def errors(self) -> list[tuple[str, str]]:
        return [(s.path, s.error) for s in self.scans if s.error]

    def address_of(self, symbol: Symbol) -> Address:
        return Address.build(self.bucket, self.name, symbol.path, symbol.name)


# ------------------------------------------------------------------------- building

def build_project_index(
    root: Path,
    name: str | None = None,
    bucket: str | None = None,
    external: bool = False,
    max_files: int = 5000,
    exclude: set[str] | None = None,
) -> ProjectIndex:
    """Scan, classify, and link one project into a ``ProjectIndex``.

    ``exclude`` skips root-relative subdirectories that are indexed as their own
    projects, so a workspace of workspaces does not double-count itself.
    """
    root = Path(root)
    project_name = name or root.name
    scans = scan_project(root, max_files=max_files, exclude=exclude)

    resolved = graphmod.build(scans)
    graphmod.annotate(scans, resolved)

    if bucket:
        verdict = Verdict(bucket, 100.0, signals=["manual override"])
    else:
        verdict = classify(root)

    index = ProjectIndex(
        name=project_name,
        root=root,
        bucket=verdict.bucket,
        verdict=verdict,
        scans=scans,
        graph=resolved,
        external=external,
    )
    _apply_flags(index)
    return index


def _apply_flags(index: ProjectIndex) -> None:
    """Mark external code and symbols nothing in the test suite references."""
    test_callers: set[str] = set()
    for scan in index.scans:
        if "test" not in scan.path.lower():
            continue
        for symbol in scan.symbols:
            test_callers.update(symbol.calls)

    for scan in index.scans:
        is_test = "test" in scan.path.lower()
        for symbol in scan.symbols:
            flags = ""
            if index.external:
                flags += FLAG_EXTERNAL
            if not is_test and symbol.kind != KIND_CLASS:
                short = f"{Path(symbol.path).stem}.{symbol.name}"
                if short not in test_callers and symbol.leaf not in {
                    c.rsplit(".", 1)[-1] for c in test_callers
                }:
                    flags += FLAG_UNTESTED
            symbol.flags = flags


def to_rows(index: ProjectIndex) -> tuple[list[dict], list[dict]]:
    """Flatten a ProjectIndex into the dicts ``Store.replace_index`` expects."""
    files = [
        {
            "path": scan.path,
            "line_count": scan.line_count,
            "file_hash": scan.file_hash,
            "error": scan.error,
        }
        for scan in index.scans
    ]
    symbols = [
        {
            "path": symbol.path,
            "name": symbol.name,
            "kind": symbol.kind,
            "line_start": symbol.line_start,
            "line_end": symbol.line_end,
            "signature": symbol.signature,
            "body_hash": symbol.body_hash,
            "doc": symbol.doc,
            "calls": symbol.calls,
            "called_by": symbol.called_by,
            "flags": symbol.flags,
            "address": str(index.address_of(symbol)),
        }
        for scan in index.scans
        for symbol in scan.symbols
    ]
    return files, symbols


# ------------------------------------------------------------------------ rendering

# Index-line budgets. The full signature and the complete caller list are always one
# `atlas get` / `atlas impact` away, so the index carries enough to decide, not
# everything. Uncapped, hub symbols alone cost more than the code they describe.
MAX_SIGNATURE_CHARS = 132
MAX_EDGES_OUT = 5
MAX_EDGES_IN = 4


def _trim_edge(name: str) -> str:
    """``autonomy.AutonomyEngine.startup_pass`` -> ``autonomy.startup_pass``.

    The middle class segment is almost always inferable and is pure cost here.
    """
    parts = name.split(".")
    if len(parts) <= 2:
        return name
    return f"{parts[0]}.{parts[-1]}"


def _edges(items: list[str], marker: str, cap: int = MAX_EDGES_OUT) -> str:
    if not items:
        return marker + EDGE_NONE
    shown = [_trim_edge(i) for i in items[:cap]]
    suffix = f",+{len(items) - cap}" if len(items) > cap else ""
    return marker + ",".join(shown) + suffix


def _trim_signature(signature: str) -> str:
    """Keep the shape of the call, drop the tail of a very long parameter list."""
    if len(signature) <= MAX_SIGNATURE_CHARS:
        return signature
    return signature[: MAX_SIGNATURE_CHARS - 4].rstrip(", ") + ", ...)"


def format_index_line(
    kind: str,
    line_start: int,
    line_end: int,
    body_hash: str,
    signature: str,
    calls: list[str],
    called_by: list[str],
    flags: str = "",
) -> str:
    """The one place an index line is rendered.

    Both the live-scan renderer and the from-database renderer call this, so the two
    cannot drift apart -- which is exactly how the uncapped-edge bug got in.
    """
    line = (
        f"{kind} L{line_start:04d}-{line_end:04d} h:{body_hash} "
        f"{_trim_signature(signature)}"
    )
    line += f"  {_edges(calls, EDGE_OUT, MAX_EDGES_OUT)}"
    line += f"  {_edges(called_by, EDGE_IN, MAX_EDGES_IN)}"
    if flags:
        line += f"  {flags}"
    return line


def render_index_md(index: ProjectIndex) -> str:
    """Render tier 1: every symbol, one line, no bodies."""
    bucket = BY_KEY.get(index.bucket, BY_KEY["misc"])
    out: list[str] = []
    out.append(f"# INDEX {Address.build(index.bucket, index.name)}")
    out.append("")
    out.append(f"spec {SPEC_VERSION} | bucket `{index.bucket}` ({bucket.title}) | "
               f"{index.file_count} files | {index.line_count} lines | "
               f"{index.symbol_count} symbols | built {_now()}")
    out.append("")
    out.append(f"Root: `{index.root}`")
    out.append("")
    out.append("Address form: `" + str(Address.build(index.bucket, index.name,
                                                     "path.py", "Symbol")) + "`. "
               "Fetch code with `atlas get <address>` -- never open a whole file.")
    out.append("")
    out.append("Legend: `C` class `F` function `f` private `A` async `K` const | "
               "`L<start>-<end>` slice span | `h:` body hash | "
               f"`{EDGE_OUT}` calls out `{EDGE_IN}` called by | "
               f"flags `{FLAG_UNTESTED}` untested `{FLAG_EXTERNAL}` external")
    out.append("")

    hub_list = graphmod.hubs(index.scans, index.graph, top=8)
    if hub_list:
        out.append("## Hubs (read these first)")
        out.append("")
        for symbol, count in hub_list:
            out.append(f"- `{symbol.path}#{symbol.name}` <- {count} callers")
        out.append("")

    out.append("## Symbols")
    out.append("")
    for scan in sorted(index.scans, key=lambda s: s.path):
        if not scan.symbols and not scan.error:
            continue
        out.append(f"### {scan.path}  ({scan.line_count} lines)")
        if scan.error:
            out.append(f"    !! {scan.error}")
        out.append("```")
        for symbol in sorted(scan.symbols, key=lambda s: s.line_start):
            out.append(format_index_line(
                symbol.kind, symbol.line_start, symbol.line_end, symbol.body_hash,
                symbol.signature, symbol.calls, symbol.called_by, symbol.flags,
            ))
            if symbol.doc:
                out.append(f'    " {symbol.doc[:100]}')
        out.append("```")
        out.append("")

    body = "\n".join(out)
    header_note = f"\n<!-- {token_estimate(body)} tokens; the sources are " \
                  f"{token_estimate('x' * index.line_count * 40)} -->\n"
    return body + header_note


def render_atlas_md(
    entries: list[tuple[str, str, int, int, int, int, str]],
    workspace: Path,
) -> str:
    """Render tier 0 from ``(bucket, project, priority, files, lines, symbols, summary)``."""
    by_bucket: dict[str, list[tuple]] = {}
    for entry in entries:
        by_bucket.setdefault(entry[0], []).append(entry)

    total_projects = len(entries)
    total_symbols = sum(e[5] for e in entries)
    total_lines = sum(e[4] for e in entries)

    out: list[str] = []
    out.append("# ATLAS")
    out.append("")
    out.append(f"spec {SPEC_VERSION} | {total_projects} projects | "
               f"{len(by_bucket)} buckets | {total_symbols} symbols | "
               f"{total_lines} lines | built {_now()}")
    out.append("")
    out.append("This is tier 0. It is the only file you must always read.")
    out.append("Pick a bucket, then read that project's `INDEX.md`, then fetch slices "
               "by address. Do not open source files.")
    out.append("")
    out.append("Address form: `@bucket/project:path.py#Symbol`")
    out.append("")

    out.append("## Buckets")
    out.append("")
    out.append("| bucket | projects | symbols | lines | covers |")
    out.append("|---|---:|---:|---:|---|")
    for key, title, blurb in bucket_titles():
        rows = by_bucket.get(key, [])
        if not rows:
            continue
        out.append(
            f"| `{key}` | {len(rows)} | {sum(r[5] for r in rows)} | "
            f"{sum(r[4] for r in rows)} | {blurb} |"
        )
    out.append("")

    out.append("## Projects by bucket")
    out.append("")
    for key, title, _blurb in bucket_titles():
        rows = by_bucket.get(key)
        if not rows:
            continue
        out.append(f"### `{key}` -- {title}")
        out.append("")
        for bucket, project, priority, files, lines, symbols, summary in sorted(
            rows, key=lambda r: -r[2]
        ):
            hot = " **HOT**" if priority >= 80 else ""
            desc = f" -- {summary}" if summary else ""
            out.append(
                f"- `@{bucket}/{project}` p{priority}{hot} "
                f"({files}f/{lines}L/{symbols}s){desc}"
            )
        out.append("")

    out.append("## Resolution order for vague requests")
    out.append("")
    out.append("When a request does not name a project, resolve it against pinned and "
               "high-priority projects in the most relevant bucket before generating "
               "anything new. Existing capability beats new code.")
    out.append("")
    hot = sorted(entries, key=lambda e: -e[2])[:8]
    for bucket, project, priority, _f, _l, symbols, summary in hot:
        out.append(f"1. `@{bucket}/{project}` (p{priority}, {symbols} symbols)"
                   + (f" -- {summary}" if summary else ""))
    out.append("")
    out.append(f"Workspace root: `{workspace}`")
    return "\n".join(out)


def write_index_md(index: ProjectIndex, destination: Path) -> Path:
    """Write a project's INDEX.md and return its path."""
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / INDEX_MD
    target.write_text(render_index_md(index), encoding="utf-8")
    return target


def write_atlas_md(text: str, workspace: Path) -> Path:
    target = Path(workspace) / ATLAS_MD
    target.write_text(text, encoding="utf-8")
    return target
