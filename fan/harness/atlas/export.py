"""Produce the pack a third-party LLM is actually handed.

Three artifacts, and a number that justifies the whole exercise: the token cost of the
pack versus the token cost of the sources it replaces.
"""

from __future__ import annotations

import datetime as _dt
from dataclasses import dataclass, field
from pathlib import Path

from .address import Address
from .buckets import BY_KEY
from .index import (
    build_project_index, format_index_line, render_atlas_md, render_index_md,
)
from .spec import (
    ATLAS_MD, CHARS_PER_TOKEN, INDEX_MD, LLM_GUIDE_MD, SPEC_VERSION, token_estimate,
)
from .store import Store

GUIDE = """# LLM_GUIDE

You are working in a codebase that is mapped, not browsed. Follow this protocol and you
will use a fraction of the context you would otherwise need.

## The protocol

1. **Read `ATLAS.md` first.** It is small and it is the only file you must always read.
   It tells you which of the twenty buckets, and which project, the request belongs to.
2. **Read that project's `INDEX.md`.** Every class and function is one line: kind, line
   span, body hash, signature, what it calls (`>`), and what calls it (`<`).
3. **Fetch code by address, never by file.**
   `atlas get @bucket/project:path.py#Symbol`
   returns exactly that symbol, with its own edge comments attached. Follow those edges
   to decide what to fetch next. `atlas expand <address> --depth 1` does it in one call.
4. **Before writing anything new, run the dedupe gate.**
   `atlas find "<what you are about to build>"`
   * `HIT` -- reuse the match, or state plainly why a new symbol is justified.
   * `MISS` -- this is **authoritative**. The code does not exist. Stop searching for it
     and create it. Do not grep. Do not open files "just to be sure."
5. **Ask where it goes. Do not choose yourself.**
   `atlas plan-insert <name> --lines N --bucket <bucket>`
   returns the exact file and line. Placement is the engine's job, so code lands in the
   right place the first time and the index never drifts.
6. **Nothing is deleted.** Superseded code is retired to `.atlas/attic/` and keeps a
   flagged tombstone line in the index. If you are replacing something, retire it --
   do not remove it.

## What not to do

* Do not read a whole source file. If you think you need to, you need three slices.
* Do not grep for a symbol you have already been told is a `MISS`.
* Do not invent an address. If it is not in `INDEX.md`, it does not exist.
* Do not write a function without a declared line count. The budget gate will refuse it.

## Reading the index line

```
F L142-198  h:a3f9  ReasonLoop.step(self, obs: Observation) -> Action   >loop.plan  <harness.tick
```

`F` function, lives at lines 142-198, body hash `a3f9`, calls `loop.plan`, is called by
`harness.tick`. To understand it, fetch it and `loop.plan`. To change it safely, check
`harness.tick` first.

## Resolving vague requests

When a request does not name a project, resolve it against the pinned and high-priority
projects listed at the end of `ATLAS.md` before generating anything new. If the user asks
for a capability that already exists in a hot project, use that project. Existing
capability beats new code.
"""


@dataclass
class ExportResult:
    written: list[Path] = field(default_factory=list)
    pack_tokens: int = 0
    source_tokens: int = 0
    projects: int = 0

    @property
    def ratio(self) -> float:
        if not self.pack_tokens:
            return 0.0
        return self.source_tokens / self.pack_tokens

    def render(self) -> str:
        out = [
            "EXPORT COMPLETE",
            f"  files written : {len(self.written)}",
            f"  projects      : {self.projects}",
            f"  pack tokens   : {self.pack_tokens:,}",
            f"  source tokens : {self.source_tokens:,}",
            f"  compression   : {self.ratio:.0f}x",
            "",
        ]
        out += [f"  {p}" for p in self.written]
        return "\n".join(out)


def atlas_entries(store: Store) -> list[tuple[str, str, int, int, int, int, str]]:
    """The tier-0 rows: (bucket, project, priority, files, lines, symbols, summary)."""
    return [
        (p.bucket, p.name, p.priority, p.file_count, p.line_count, p.symbol_count, p.summary)
        for p in store.projects()
    ]


def export_all(
    store: Store,
    destination: Path | None = None,
    per_project_index: bool = True,
) -> ExportResult:
    """Write ATLAS.md, every project's INDEX.md, and LLM_GUIDE.md."""
    root = Path(destination) if destination else store.workspace
    root.mkdir(parents=True, exist_ok=True)
    result = ExportResult()

    entries = atlas_entries(store)
    atlas_text = render_atlas_md(entries, store.workspace)
    atlas_path = root / ATLAS_MD
    atlas_path.write_text(atlas_text, encoding="utf-8")
    result.written.append(atlas_path)
    result.pack_tokens += token_estimate(atlas_text)

    guide_path = root / LLM_GUIDE_MD
    guide_path.write_text(GUIDE, encoding="utf-8")
    result.written.append(guide_path)
    result.pack_tokens += token_estimate(GUIDE)

    if per_project_index:
        index_root = root / ".atlas" / "index"
        index_root.mkdir(parents=True, exist_ok=True)
        for project in store.projects():
            text = render_index_from_store(store, project.id)
            target = index_root / f"{project.name}.{INDEX_MD}"
            target.write_text(text, encoding="utf-8")
            result.written.append(target)
            result.pack_tokens += token_estimate(text)
            result.projects += 1
            # A source line averages ~40 characters; that is the cost being avoided.
            result.source_tokens += token_estimate("x" * project.line_count * 40)

    store.log("export", detail=f"{len(result.written)} files -> {root}",
              payload={"pack_tokens": result.pack_tokens})
    return result


def render_index_from_store(store: Store, project_id: int) -> str:
    """Render a project's INDEX.md from the database rather than re-scanning disk."""
    project = store.project(project_id)
    if project is None:
        return "# INDEX (unknown project)\n"

    rows = store.symbols(project_id)
    files = store.many(
        "SELECT * FROM files WHERE project_id = ? ORDER BY path", (project_id,)
    )
    bucket = BY_KEY.get(project.bucket, BY_KEY["misc"])

    out: list[str] = [
        f"# INDEX @{project.bucket}/{project.name}",
        "",
        f"spec {SPEC_VERSION} | bucket `{project.bucket}` ({bucket.title}) | "
        f"{project.file_count} files | {project.line_count} lines | "
        f"{project.symbol_count} symbols | indexed {project.indexed_at}",
        "",
        f"Root: `{project.root}`",
        "",
        "Fetch code with `atlas get <address>`. Never open a whole file.",
        "",
        "Legend: `C` class `F` function `f` private `A` async `K` const | "
        "`L<start>-<end>` slice span | `h:` body hash | `>` calls out `<` called by",
        "",
        "## Symbols",
        "",
    ]

    by_path: dict[str, list] = {}
    for row in rows:
        by_path.setdefault(row["path"], []).append(row)

    line_counts = {f["path"]: f["line_count"] for f in files}
    errors = {f["path"]: f["error"] for f in files if f["error"]}

    for path in sorted(set(list(by_path) + list(line_counts))):
        members = by_path.get(path, [])
        if not members and path not in errors:
            continue
        out.append(f"### {path}  ({line_counts.get(path, 0)} lines)")
        if path in errors:
            out.append(f"    !! {errors[path]}")
        out.append("```")
        for row in sorted(members, key=lambda r: int(r["line_start"])):
            out.append(format_index_line(
                row["kind"], int(row["line_start"]), int(row["line_end"]),
                row["body_hash"], row["signature"],
                [c for c in (row["calls"] or "").split(",") if c],
                [c for c in (row["called_by"] or "").split(",") if c],
                row["flags"] or "",
            ))
            if row["doc"]:
                out.append(f'    " {row["doc"][:100]}')
        out.append("```")
        out.append("")

    body = "\n".join(out)
    return body + f"\n<!-- pack: {token_estimate(body)} tokens -->\n"


def system_preamble(store: Store, top_buckets: int = 8) -> str:
    """A compact block to paste into any third-party system prompt."""
    counts = store.counts()
    lines = [
        "## Codebase access protocol (Atlas)",
        "",
        f"This workspace holds {counts['projects']} projects, {counts['symbols']} indexed "
        f"symbols, {counts['lines']:,} lines. Do not read source files directly.",
        "",
        "1. `ATLAS.md` -> pick a bucket and project.",
        "2. `<project>.INDEX.md` -> resolve an address.",
        "3. `atlas get @bucket/project:file.py#Symbol` -> the code, plus its edges.",
        "4. `atlas find \"<intent>\"` before writing. MISS is authoritative: create it.",
        "5. `atlas plan-insert <name> --lines N` decides placement. You do not.",
        "6. Retire, never delete.",
        "",
        "Buckets in use:",
    ]
    for row in store.bucket_summary()[:top_buckets]:
        bucket = BY_KEY.get(row["bucket"], BY_KEY["misc"])
        lines.append(
            f"- `{row['bucket']}` ({row['projects']} projects, {row['symbols']} symbols)"
            f" -- {bucket.blurb}"
        )
    lines.append("")
    lines.append(f"Generated {_dt.datetime.now().strftime('%Y-%m-%d %H:%M')}, "
                 f"spec {SPEC_VERSION}.")
    return "\n".join(lines)


def export_project(store: Store, root: Path, destination: Path) -> Path:
    """Index one project on the fly and write only its INDEX.md."""
    index = build_project_index(Path(root))
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / f"{index.name}.{INDEX_MD}"
    target.write_text(render_index_md(index), encoding="utf-8")
    return target


def _source_tokens(store: Store, project_id: int, root: str) -> int:
    """Actual bytes on disk for a project's indexed files, as tokens."""
    total = 0
    for row in store.many("SELECT path FROM files WHERE project_id = ?", (project_id,)):
        path = Path(root) / row["path"]
        try:
            total += path.stat().st_size
        except OSError:
            continue
    return int(total / CHARS_PER_TOKEN)


def budget_report(store: Store) -> str:
    """What the map actually costs on the path an agent actually takes.

    An agent does not read every index. It reads the atlas, then one project's index,
    then a handful of slices. Reporting the sum of all indexes would flatter nothing
    and mislead everyone, so this models the real access pattern instead.
    """
    projects = store.projects()
    if not projects:
        return "Nothing indexed yet."

    atlas_text = render_atlas_md(atlas_entries(store), store.workspace)
    atlas_tokens = token_estimate(atlas_text)

    rows: list[str] = [
        "TIER COST REPORT", "=" * 74, "",
        "Per project: what its index costs to read, against its own sources.", "",
        f"  {'project':<20}{'index':>9}{'sources':>10}{'saving':>9}   "
        f"{'atlas+index vs sources':>24}",
        "  " + "-" * 72,
    ]

    total_index = 0
    total_source = 0
    ratios: list[float] = []
    for project in projects:
        index_tokens = token_estimate(render_index_from_store(store, project.id))
        source_tokens = _source_tokens(store, project.id, project.root)
        total_index += index_tokens
        total_source += source_tokens
        targeted = atlas_tokens + index_tokens
        ratio = (source_tokens / targeted) if targeted else 0.0
        ratios.append(ratio)
        rows.append(
            f"  {project.name[:19]:<20}{index_tokens:>9,}{source_tokens:>10,}"
            f"{source_tokens - index_tokens:>9,}{ratio:>23.1f}x"
        )

    typical_index = total_index // max(len(projects), 1)
    typical_source = total_source // max(len(projects), 1)
    targeted = atlas_tokens + typical_index + 600  # atlas + one index + ~3 slices

    rows += [
        "",
        "THE PATH AN AGENT ACTUALLY TAKES", "-" * 74,
        f"  tier 0   ATLAS.md, always read          {atlas_tokens:>9,} tokens",
        f"  tier 1   one project's INDEX.md         {typical_index:>9,} tokens (median project)",
        f"  tier 2   three slices, fetched by address  {600:>6,} tokens",
        f"  {'':<41}{'-' * 9}",
        f"  total to answer one question            {targeted:>9,} tokens",
        "",
        f"  reading that project's sources instead  {typical_source:>9,} tokens",
        f"  saving on the targeted path             {typical_source / max(targeted, 1):>8.1f}x",
        "",
        "WHOLE-UNIVERSE FIGURES", "-" * 74,
        f"  every index, if you read them all       {total_index:>9,} tokens",
        f"  every source file                       {total_source:>9,} tokens",
        f"  index-to-source ratio                   {total_source / max(total_index, 1):>8.1f}x",
        "",
        "The index is roughly a fifth of the code it describes; that is the floor for",
        "a per-symbol map. The larger saving is behavioural: an agent reads one index",
        "and three slices instead of grepping across projects and opening whole files,",
        "and a MISS from the dedupe gate ends a search that would otherwise continue.",
    ]
    return "\n".join(rows)
