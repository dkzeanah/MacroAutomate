"""``atlas`` -- the command line an agent (or a person) drives the map with.

Every command prints something an LLM can act on directly. Nothing here needs the GUI.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import condense as condensemod
from . import export as exportmod
from . import fanout as fanoutmod
from . import ingest as ingestmod
from . import rules, slicer, sweep
from .buckets import bucket_titles
from .index import build_project_index, to_rows
from .ledger import Ledger
from .slicer import SliceError
from .store import Store


def _store(args) -> Store:
    return Store(Path(args.workspace).expanduser().resolve())


# ------------------------------------------------------------------------ commands

def cmd_sweep(args) -> int:
    store = _store(args)
    root = Path(args.root or store.get("scan_root")).expanduser()
    print(f"sweeping {root} ...")
    result = sweep.sweep(root, max_projects=args.limit)
    print(result.render())

    if args.index:
        print(f"\nindexing {len(result.projects)} projects ...")

        def progress(i, total, name):
            print(f"  [{i + 1}/{total}] {name}", flush=True)

        indexed = sweep.index_candidates(store, result.projects, progress=progress)
        print(f"\nindexed {len(indexed.indexed)} projects")
        for error in indexed.errors[:20]:
            print(f"  ! {error}")
    store.close()
    return 0


def cmd_index(args) -> int:
    store = _store(args)
    root = Path(args.path).expanduser().resolve()
    index = build_project_index(root, name=args.name, bucket=args.bucket,
                                external=args.external)
    files, symbols = to_rows(index)
    import datetime as dt

    project_id = store.upsert_project(
        index.name, root, bucket=index.bucket, priority=args.priority,
        external=1 if args.external else 0, verdict=index.verdict.explain(),
        file_count=index.file_count, line_count=index.line_count,
        symbol_count=index.symbol_count,
        indexed_at=dt.datetime.now().strftime("%Y-%m-%d %H:%M"),
    )
    store.replace_index(project_id, files, symbols)
    print(f"indexed @{index.bucket}/{index.name}")
    print(f"  {index.file_count} files, {index.line_count} lines, "
          f"{index.symbol_count} symbols")
    print(f"  classification: {index.verdict.explain()}")
    for path, error in index.errors[:10]:
        print(f"  ! {path}: {error}")
    store.close()
    return 0


def cmd_find(args) -> int:
    store = _store(args)
    result = rules.find(store, args.query, threshold=args.threshold, bucket=args.bucket)
    print(result.render())
    store.close()
    return 0 if result.hit else 3


def cmd_get(args) -> int:
    store = _store(args)
    try:
        piece = slicer.get(store, args.address, context_lines=args.context)
    except (SliceError, ValueError) as exc:
        print(f"ERROR {exc}", file=sys.stderr)
        store.close()
        return 2
    print(piece.render())
    print(f"\n# {piece.tokens} tokens")
    store.close()
    return 0


def cmd_expand(args) -> int:
    store = _store(args)
    pieces = slicer.expand(store, args.address, depth=args.depth, budget_tokens=args.budget)
    if not pieces:
        print("nothing resolved for that address", file=sys.stderr)
        store.close()
        return 2
    total = 0
    for piece in pieces:
        print(piece.render())
        print()
        total += piece.tokens
    print(f"# {len(pieces)} slices, {total} tokens")
    store.close()
    return 0


def cmd_impact(args) -> int:
    store = _store(args)
    rows = slicer.impact(store, args.address)
    if not rows:
        print(f"no recorded callers of {args.address} -- safe to change in isolation")
    else:
        print(f"{len(rows)} caller(s) of {args.address}:")
        for row in rows:
            print(f"  {row['address']}  L{row['line_start']}-{row['line_end']}  "
                  f"{row['signature']}")
    store.close()
    return 0


def cmd_gate(args) -> int:
    store = _store(args)
    report = rules.gate(
        store, name=args.name, intent=args.intent or args.name, lines=args.lines,
        bucket=args.bucket, project=args.project, prefer_path=args.path,
    )
    print(report.render())
    store.close()
    return 0 if report.allowed else 3


def cmd_plan_insert(args) -> int:
    store = _store(args)
    placement = rules.plan_insert(
        store, args.name, args.lines, bucket=args.bucket, project=args.project,
        prefer_path=args.path,
    )
    print(placement.render())
    store.close()
    return 0 if placement.ok else 3


def cmd_absorb(args) -> int:
    from . import absorb as absorbmod

    store = _store(args)
    report = absorbmod.absorb(
        store, Path(args.path), name=args.name, bucket=args.bucket,
        priority=args.priority, copy_into_workspace=args.copy,
        external=args.external, dry_run=not args.write,
    )
    print(report.render())
    if not args.write:
        print("\n(preview -- pass --write to register it)")
    store.close()
    return 1 if report.errors else 0


def cmd_release(args) -> int:
    from . import absorb as absorbmod

    store = _store(args)
    print(absorbmod.release(store, args.project))
    store.close()
    return 0


def cmd_entities(args) -> int:
    store = _store(args)
    project_id = None
    if args.project:
        row = store.project_by_name(args.project)
        if row is None:
            print(f"unknown project {args.project}", file=sys.stderr)
            store.close()
            return 2
        project_id = row.id

    rows = store.entities(
        project_id=project_id, kind=args.kind,
        runnable_only=args.runnable, query=args.query or "",
    )
    if not rows:
        print("No entities match. Absorb a project first: atlas absorb <path> --write")
        store.close()
        return 3
    print(f"{'kind':<9} {'name':<34} {'project':<22} what it is")
    print("-" * 110)
    for row in rows:
        pin = "*" if row["pinned"] else " "
        print(f"{pin}{row['kind']:<8} {row['name'][:33]:<34} "
              f"{row['project'][:21]:<22} {(row['summary'] or '')[:46]}")
    store.close()
    return 0


def cmd_manifest(args) -> int:
    from . import absorb as absorbmod

    store = _store(args)
    print(absorbmod.capability_manifest(store, args.project))
    store.close()
    return 0


def cmd_run(args) -> int:
    import subprocess

    from . import absorb as absorbmod

    store = _store(args)
    rows = store.entities(query=args.name, runnable_only=True)
    exact = [r for r in rows if r["name"].lower() == args.name.lower()]
    candidates = exact or rows

    if not candidates:
        print(f"Nothing runnable matches {args.name!r}.", file=sys.stderr)
        print("List what is available with: atlas entities --runnable", file=sys.stderr)
        store.close()
        return 2
    if len(candidates) > 1 and not exact:
        print(f"{args.name!r} matches several entities -- be more specific:",
              file=sys.stderr)
        for row in candidates[:12]:
            print(f"  {row['name']}  ({row['kind']} in {row['project']})",
                  file=sys.stderr)
        store.close()
        return 2

    row = candidates[0]
    try:
        command, cwd = absorbmod.build_command(store, row, sys.executable)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        store.close()
        return 2

    print(f">>> {' '.join(command)}\n    (cwd: {cwd})\n")
    store.record_run(int(row["id"]))
    store.close()
    try:
        return subprocess.call(command, cwd=str(cwd))
    except OSError as exc:
        print(f"could not start: {exc}", file=sys.stderr)
        return 1


def cmd_variants(args) -> int:
    from . import variants as variantsmod

    store = _store(args)
    families = variantsmod.detect_families(store)
    if not families:
        print("No variant families found. Index two or more copies of a project first.")
        store.close()
        return 3
    for family in families:
        print(family.describe())
        for variant in family.variants:
            print(f"    {variant.name[:58]:<58} {variant.when}  "
                  f"{variant.symbol_count:>4} symbols  {variant.file_count:>3} files")
        print()
    store.close()
    return 0


def cmd_reconcile(args) -> int:
    from . import variants as variantsmod

    store = _store(args)
    families = variantsmod.detect_families(store)
    family = _pick_family(families, args.family)
    if family is None:
        store.close()
        return 2
    plan = variantsmod.align(store, family, policy=args.policy, lead=args.lead or "")
    print(plan.render(limit=args.limit))
    store.close()
    return 0 if not plan.conflicts else 3


def cmd_coagulate(args) -> int:
    from . import coagulate as coagulatemod
    from . import variants as variantsmod

    store = _store(args)
    families = variantsmod.detect_families(store)
    family = _pick_family(families, args.family)
    if family is None:
        store.close()
        return 2

    plan = variantsmod.align(store, family, policy=args.policy, lead=args.lead or "")
    destination = Path(
        args.out or (store.workspace / "coagulated" / family.key)
    ).expanduser()

    if not args.write:
        print(plan.render(limit=args.limit))
        print()
    result = coagulatemod.execute(
        store, plan, destination, dry_run=not args.write,
    )
    print(result.render())
    store.close()
    if not args.write:
        return 0
    return 0 if result.verification.ok else 1


def _pick_family(families, wanted: str | None):
    if not families:
        print("No variant families found. Index two or more copies of a project first.",
              file=sys.stderr)
        return None
    if not wanted:
        if len(families) == 1:
            return families[0]
        print("Several families found -- name one with --family:", file=sys.stderr)
        for family in families:
            print(f"  {family.key}  ({family.size} variants)", file=sys.stderr)
        return None
    matches = [f for f in families if wanted.lower() in f.key.lower()]
    if not matches:
        print(f"No family matching {wanted!r}. Available:", file=sys.stderr)
        for family in families:
            print(f"  {family.key}", file=sys.stderr)
        return None
    return matches[0]


def cmd_dupes(args) -> int:
    from . import similar as similarmod

    store = _store(args)
    ids = None
    if args.project:
        row = store.project_by_name(args.project)
        if row is None:
            print(f"unknown project {args.project}", file=sys.stderr)
            store.close()
            return 2
        ids = [row.id]

    entries, problems = similarmod.load_entries(store, ids, min_lines=args.min_lines)
    print(f"normalized {len(entries)} symbols ...")
    clusters = similarmod.cluster(
        entries, include_near=not args.exact_only,
        cross_project_only=args.cross_project,
    )
    print(similarmod.duplication_report(clusters, limit=args.limit))
    for problem in problems[:10]:
        print(f"  ! {problem}")
    store.close()
    return 0


def cmd_condense(args) -> int:
    store = _store(args)
    ids = None
    if args.project:
        row = store.project_by_name(args.project)
        if row is None:
            print(f"unknown project {args.project}", file=sys.stderr)
            store.close()
            return 2
        ids = [row.id]
    result = condensemod.condense(store, ids, include_private=args.private)
    destination = Path(args.out).expanduser() if args.out else store.workspace / "condensed"
    written = condensemod.write(result, destination)
    print(f"condensed {result.total} symbols "
          f"({len(result.classes_symbols)} classes, {len(result.functions_symbols)} functions)")
    for path in written:
        print(f"  {path}")
    if result.skipped:
        print(f"  {len(result.skipped)} skipped (duplicates or unreadable)")
    store.close()
    return 0


def cmd_fanout(args) -> int:
    source = Path(args.source).expanduser()
    if source.suffix.lower() == ".zip":
        plan = fanoutmod.parse_zip(source)
    else:
        plan = fanoutmod.parse_document(source.read_text(encoding="utf-8", errors="replace"))
    print(plan.render())
    if args.out:
        destination = Path(args.out).expanduser()
        if args.commit:
            report = fanoutmod.commit(plan, destination, archive=source
                                      if source.suffix.lower() == ".zip" else None)
            print()
            for line in report:
                print(f"  {line}")
        else:
            print(f"\n(dry run -- pass --commit to write into {destination})")
    return 0


def cmd_ingest(args) -> int:
    store = _store(args)
    report = ingestmod.ingest(
        store, Path(args.source).expanduser(),
        destination=Path(args.out).expanduser() if args.out else None,
        project_name=args.name, bucket=args.bucket, run=args.run,
        overwrite=args.overwrite,
    )
    print(report.render())
    store.close()
    return 0 if not report.errors else 1


def cmd_export(args) -> int:
    store = _store(args)
    result = exportmod.export_all(
        store, destination=Path(args.out).expanduser() if args.out else None
    )
    print(result.render())
    store.close()
    return 0


def cmd_preamble(args) -> int:
    store = _store(args)
    print(exportmod.system_preamble(store))
    store.close()
    return 0


def cmd_budget(args) -> int:
    store = _store(args)
    print(exportmod.budget_report(store))
    store.close()
    return 0


def cmd_buckets(args) -> int:
    store = _store(args)
    counts = {row["bucket"]: row for row in store.bucket_summary()}
    print(f"{'bucket':<14} {'proj':>5} {'symbols':>8}  covers")
    print("-" * 78)
    for key, title, blurb in bucket_titles():
        row = counts.get(key)
        projects = row["projects"] if row else 0
        symbols = row["symbols"] if row else 0
        print(f"{key:<14} {projects:>5} {symbols:>8}  {blurb}")
    store.close()
    return 0


def cmd_projects(args) -> int:
    store = _store(args)
    projects = store.projects(bucket=args.bucket)
    print(f"{'project':<40} {'bucket':<13} {'pri':>4} {'files':>6} "
          f"{'lines':>8} {'symbols':>8}")
    print("-" * 88)
    for project in projects:
        pin = "*" if project.pinned else " "
        print(f"{pin}{project.name[:39]:<39} {project.bucket:<13} {project.priority:>4} "
              f"{project.file_count:>6} {project.line_count:>8} {project.symbol_count:>8}")
    store.close()
    return 0


def cmd_mirror(args) -> int:
    store = _store(args)
    project = store.project_by_name(args.project)
    if project is None:
        print(f"unknown project {args.project}", file=sys.stderr)
        store.close()
        return 2
    if args.write:
        ledger = Ledger(store)
        paths = [Path(project.root) / row["path"] for row in store.symbols(project.id)]
        backup = ledger.snapshot(list(set(paths)), "mirror", f"before mirroring {project.name}")
        print(f"backed up {len(backup.files)} files to {backup.directory}")
    for line in slicer.mirror_comments(store, project.id, dry_run=not args.write):
        print(f"  {line}")
    store.close()
    return 0


def cmd_ledger(args) -> int:
    store = _store(args)
    ledger = Ledger(store)
    for entry in ledger.history(args.limit):
        print(f"#{entry['id']:<5} {entry['ts']}  {entry['action']:<14} "
              f"{entry['address'] or entry['detail']}")
    store.close()
    return 0


def cmd_restore(args) -> int:
    store = _store(args)
    ledger = Ledger(store)
    for line in ledger.restore(args.id, dry_run=not args.write):
        print(f"  {line}")
    if not args.write:
        print("\n(dry run -- pass --write to actually restore)")
    store.close()
    return 0


def cmd_attic(args) -> int:
    store = _store(args)
    ledger = Ledger(store)
    entries = ledger.attic_entries()
    if not entries:
        print("attic is empty -- nothing has been retired yet")
    for label, path, size in entries:
        print(f"  {size:>8}b  {label}")
    store.close()
    return 0


# --------------------------------------------------------------------------- parser

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="atlas",
        description="Context Map engine: index projects, slice code, gate new writes.",
    )
    parser.add_argument("--workspace", default=".", help="workspace root (holds .atlas/)")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("sweep", help="classify every project under a root folder")
    p.add_argument("root", nargs="?", help="folder of projects (default: saved scan_root)")
    p.add_argument("--index", action="store_true", help="also fully index what it finds")
    p.add_argument("--limit", type=int, default=500)
    p.set_defaults(func=cmd_sweep)

    p = sub.add_parser("index", help="index one project")
    p.add_argument("path")
    p.add_argument("--name")
    p.add_argument("--bucket")
    p.add_argument("--priority", type=int, default=50)
    p.add_argument("--external", action="store_true", help="mark as vendored, do not edit")
    p.set_defaults(func=cmd_index)

    p = sub.add_parser("find", help="does this already exist? MISS is authoritative")
    p.add_argument("query")
    p.add_argument("--threshold", type=float, default=0.42)
    p.add_argument("--bucket")
    p.set_defaults(func=cmd_find)

    p = sub.add_parser("get", help="fetch one symbol by address")
    p.add_argument("address")
    p.add_argument("--context", type=int, default=0)
    p.set_defaults(func=cmd_get)

    p = sub.add_parser("expand", help="fetch a symbol plus what it calls")
    p.add_argument("address")
    p.add_argument("--depth", type=int, default=1)
    p.add_argument("--budget", type=int, default=6000)
    p.set_defaults(func=cmd_expand)

    p = sub.add_parser("impact", help="what calls this symbol")
    p.add_argument("address")
    p.set_defaults(func=cmd_impact)

    p = sub.add_parser("gate", help="run all three write gates for a proposed symbol")
    p.add_argument("name")
    p.add_argument("--intent", help="what it is supposed to do")
    p.add_argument("--lines", type=int, required=True)
    p.add_argument("--bucket")
    p.add_argument("--project")
    p.add_argument("--path")
    p.set_defaults(func=cmd_gate)

    p = sub.add_parser("plan-insert", help="ask the engine where new code goes")
    p.add_argument("name")
    p.add_argument("--lines", type=int, required=True)
    p.add_argument("--bucket")
    p.add_argument("--project")
    p.add_argument("--path")
    p.set_defaults(func=cmd_plan_insert)

    p = sub.add_parser(
        "absorb",
        help="integrate a project: classify, index, extract its tools, register them",
    )
    p.add_argument("path")
    p.add_argument("--name")
    p.add_argument("--bucket")
    p.add_argument("--priority", type=int, default=60)
    p.add_argument("--copy", action="store_true",
                   help="copy into the workspace (default: integrate in place)")
    p.add_argument("--external", action="store_true", help="vendored, do not edit")
    p.add_argument("--write", action="store_true", help="register it (default: preview)")
    p.set_defaults(func=cmd_absorb)

    p = sub.add_parser("release", help="unregister a project; its files are untouched")
    p.add_argument("project")
    p.set_defaults(func=cmd_release)

    p = sub.add_parser("entities", help="every tool, command and capability registered")
    p.add_argument("--project")
    p.add_argument("--kind", help="gui, cli, command, service, script, api, skill")
    p.add_argument("--runnable", action="store_true")
    p.add_argument("--query")
    p.set_defaults(func=cmd_entities)

    p = sub.add_parser("manifest", help="the full capability list, for a human or an LLM")
    p.add_argument("--project")
    p.set_defaults(func=cmd_manifest)

    p = sub.add_parser("run", help="run a registered entity by name")
    p.add_argument("name")
    p.set_defaults(func=cmd_run)

    p = sub.add_parser("variants", help="find folders that are copies of one project")
    p.set_defaults(func=cmd_variants)

    p = sub.add_parser(
        "reconcile",
        help="align a family's symbols and show what would be merged (no writes)",
    )
    p.add_argument("--family", help="which family (substring of its key)")
    p.add_argument("--policy", default="newest", choices=["newest", "richest", "lead"])
    p.add_argument("--lead", help="with --policy lead: the variant that wins ties")
    p.add_argument("--limit", type=int, default=24)
    p.set_defaults(func=cmd_reconcile)

    p = sub.add_parser(
        "coagulate",
        help="merge a variant family into one project, archiving everything else",
    )
    p.add_argument("--family")
    p.add_argument("--out", help="destination (default: workspace/coagulated/<family>)")
    p.add_argument("--policy", default="newest", choices=["newest", "richest", "lead"])
    p.add_argument("--lead", help="with --policy lead: the variant that wins ties")
    p.add_argument("--write", action="store_true", help="actually write (default: dry run)")
    p.add_argument("--limit", type=int, default=24)
    p.set_defaults(func=cmd_coagulate)

    p = sub.add_parser("dupes", help="find duplicated code across the indexed universe")
    p.add_argument("--project")
    p.add_argument("--min-lines", type=int, default=4)
    p.add_argument("--exact-only", action="store_true",
                   help="skip near-match detection (much faster)")
    p.add_argument("--cross-project", action="store_true",
                   help="only report duplicates that span projects")
    p.add_argument("--limit", type=int, default=40)
    p.set_defaults(func=cmd_dupes)

    p = sub.add_parser("condense", help="build classes.py and functions.py")
    p.add_argument("--project")
    p.add_argument("--out")
    p.add_argument("--private", action="store_true", help="include _private symbols")
    p.set_defaults(func=cmd_condense)

    p = sub.add_parser("fanout", help="explode a document or zip into a project tree")
    p.add_argument("source")
    p.add_argument("--out")
    p.add_argument("--commit", action="store_true")
    p.set_defaults(func=cmd_fanout)

    p = sub.add_parser("ingest", help="unpack, dedupe, place, index, back up and run")
    p.add_argument("source")
    p.add_argument("--out")
    p.add_argument("--name")
    p.add_argument("--bucket")
    p.add_argument("--run", action="store_true")
    p.add_argument("--overwrite", action="store_true")
    p.set_defaults(func=cmd_ingest)

    p = sub.add_parser("export", help="write ATLAS.md, INDEX.md files and LLM_GUIDE.md")
    p.add_argument("--out")
    p.set_defaults(func=cmd_export)

    p = sub.add_parser("preamble", help="print a system-prompt block for a third-party LLM")
    p.set_defaults(func=cmd_preamble)

    p = sub.add_parser("budget", help="what each tier costs in tokens")
    p.set_defaults(func=cmd_budget)

    p = sub.add_parser("buckets", help="the twenty buckets and what is in them")
    p.set_defaults(func=cmd_buckets)

    p = sub.add_parser("projects", help="list indexed projects")
    p.add_argument("--bucket")
    p.set_defaults(func=cmd_projects)

    p = sub.add_parser("mirror", help="write the @atlas edge comments into the sources")
    p.add_argument("project")
    p.add_argument("--write", action="store_true", help="actually modify files")
    p.set_defaults(func=cmd_mirror)

    p = sub.add_parser("ledger", help="the append-only history")
    p.add_argument("--limit", type=int, default=40)
    p.set_defaults(func=cmd_ledger)

    p = sub.add_parser("restore", help="restore the tree from a ledger entry")
    p.add_argument("id", type=int)
    p.add_argument("--write", action="store_true")
    p.set_defaults(func=cmd_restore)

    p = sub.add_parser("attic", help="retired code that was kept")
    p.set_defaults(func=cmd_attic)

    return parser


def _force_utf8_output() -> None:
    """Windows consoles default to cp1252, which cannot encode most docstrings.

    Without this, printing an index that happens to contain an arrow or an accented
    character kills the command with a UnicodeEncodeError that has nothing to do with
    what the user asked for.
    """
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is None:
            continue
        try:
            reconfigure(encoding="utf-8", errors="replace")
        except (ValueError, OSError):
            continue


def main(argv: list[str] | None = None) -> int:
    _force_utf8_output()
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args) or 0)


if __name__ == "__main__":
    raise SystemExit(main())
