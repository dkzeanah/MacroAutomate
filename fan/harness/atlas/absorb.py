"""Absorb a large project into the harness without dissolving it.

The problem: a serious project is not one tool. It is a dozen -- a GUI, three CLIs,
forty subcommands, a server, some batch launchers, a skills folder. Dropped onto a
desktop it is an opaque folder you have to re-read every time you come back to it.

"Flattening" it does **not** mean pulling its files apart. It means making the things
it can *do* visible and reachable at the same level as everything else, while the
project itself stays intact and in place.

So absorption is four passes and one principle:

    1. CLASSIFY   which of the twenty buckets it belongs to, with evidence
    2. INDEX      every symbol, addressable, with call edges in both directions
    3. EXTRACT    every runnable and callable entity it exposes
    4. REGISTER   those entities in the harness, launchable from one place

    The principle: nothing is moved, copied, renamed or rewritten. The project keeps
    its own structure and identity. It is integrated *by reference and index*, never
    by absorption into some other layout. Everything added is additive and reversible
    -- `release` unregisters it and the folder is exactly as it was.
"""

from __future__ import annotations

import datetime as _dt
import shutil
from dataclasses import asdict, dataclass, field
from pathlib import Path

from . import entities as entitiesmod
from .buckets import classify
from .index import build_project_index, to_rows
from .ledger import Ledger
from .store import Store


@dataclass
class AbsorbReport:
    source: str = ""
    project: str = ""
    bucket: str = ""
    verdict: str = ""
    copied_to: str = ""
    files: int = 0
    lines: int = 0
    symbols: int = 0
    entity_counts: dict[str, int] = field(default_factory=dict)
    runnable: int = 0
    extraction: entitiesmod.Extraction | None = None
    ledger_id: int = 0
    errors: list[str] = field(default_factory=list)
    dry_run: bool = True

    @property
    def total_entities(self) -> int:
        return sum(self.entity_counts.values())

    def render(self, limit: int = 16) -> str:
        head = "PREVIEW -- nothing registered" if self.dry_run else "ABSORBED"
        out = [
            "=" * 74, f"{head}  {self.project}", "=" * 74,
            f"  source   {self.source}",
            f"  bucket   {self.bucket}",
        ]
        if self.verdict:
            out.append(f"  evidence {self.verdict[:120]}")
        if self.copied_to:
            out.append(f"  copied   {self.copied_to}")
        else:
            out.append("  location left in place -- integrated by reference, not moved")
        out += [
            "",
            f"  INDEXED   {self.files} files, {self.lines:,} lines, {self.symbols} symbols",
            f"  ENTITIES  {self.total_entities} found, {self.runnable} runnable",
            "",
        ]
        for kind in entitiesmod.KIND_ORDER:
            count = self.entity_counts.get(kind, 0)
            if count:
                out.append(
                    f"    {kind:<9} {count:>4}   {entitiesmod.KIND_BLURB[kind]}"
                )
        if self.extraction:
            out.append("")
            out.append("  WHAT YOU CAN NOW RUN FROM THE HARNESS TAB:")
            for entity in self.extraction.runnable[:limit]:
                out.append(f"    {entity.describe()}")
            if len(self.extraction.runnable) > limit:
                out.append(f"    ... and {len(self.extraction.runnable) - limit} more")
        if self.ledger_id:
            out += ["", f"  ledger #{self.ledger_id}"]
        if self.errors:
            out += ["", "  PROBLEMS"] + [f"    ! {e}" for e in self.errors[:10]]
        return "\n".join(out)


def absorb(
    store: Store,
    source: Path,
    name: str | None = None,
    bucket: str | None = None,
    priority: int = 60,
    copy_into_workspace: bool = False,
    external: bool = False,
    include_api: bool = True,
    dry_run: bool = False,
    max_files: int = 4000,
) -> AbsorbReport:
    """Integrate a project as a first-class citizen of the harness.

    ``copy_into_workspace`` is off by default and should usually stay off: a project
    integrated by reference can be absorbed again after you edit it, whereas a copy
    immediately starts diverging from the thing you actually work in.
    """
    source = Path(source).expanduser().resolve()
    project_name = name or source.name
    report = AbsorbReport(
        source=str(source), project=project_name, dry_run=dry_run
    )

    if not source.exists() or not source.is_dir():
        report.errors.append(f"{source} is not a directory")
        return report

    root = source
    if copy_into_workspace and not dry_run:
        destination = store.workspace / "projects" / project_name
        if destination.exists():
            report.errors.append(
                f"{destination} already exists -- absorb in place, or pick another name"
            )
            return report
        try:
            shutil.copytree(
                source, destination,
                ignore=shutil.ignore_patterns(
                    ".git", "__pycache__", ".venv", "venv", "node_modules",
                    ".pytest_cache", "*.pyc",
                ),
            )
            root = destination
            report.copied_to = str(destination)
        except OSError as exc:
            report.errors.append(f"copy failed: {exc}")
            return report

    # 1. classify ------------------------------------------------------------
    try:
        verdict = classify(root)
    except Exception as exc:
        report.errors.append(f"classification failed: {exc}")
        verdict = None
    chosen_bucket = bucket or (verdict.bucket if verdict else "misc")
    report.bucket = chosen_bucket
    report.verdict = verdict.explain() if verdict else "manual"

    # 2. index ---------------------------------------------------------------
    try:
        index = build_project_index(
            root, name=project_name, bucket=chosen_bucket,
            external=external, max_files=max_files,
        )
    except Exception as exc:
        report.errors.append(f"indexing failed: {exc}")
        return report

    report.files = index.file_count
    report.lines = index.line_count
    report.symbols = index.symbol_count
    for path, error in index.errors[:10]:
        report.errors.append(f"{path}: {error}")

    if dry_run:
        extraction = entitiesmod.extract(
            root, project_name, store=None, include_api=False, max_files=max_files
        )
        report.extraction = extraction
        report.entity_counts = extraction.counts()
        report.runnable = len(extraction.runnable)
        return report

    files, symbols = to_rows(index)
    project_id = store.upsert_project(
        project_name, root,
        bucket=chosen_bucket, priority=priority,
        external=1 if external else 0,
        summary=(verdict.signals[0] if verdict and verdict.signals else ""),
        verdict=report.verdict,
        file_count=index.file_count, line_count=index.line_count,
        symbol_count=index.symbol_count,
        indexed_at=_dt.datetime.now().strftime("%Y-%m-%d %H:%M"),
    )
    store.replace_index(project_id, files, symbols)

    # 3. extract + 4. register ----------------------------------------------
    try:
        extraction = entitiesmod.extract(
            root, project_name, store=store,
            include_api=include_api, max_files=max_files,
        )
    except Exception as exc:
        report.errors.append(f"entity extraction failed: {exc}")
        extraction = entitiesmod.Extraction(project=project_name, root=root)

    report.extraction = extraction
    report.entity_counts = extraction.counts()
    report.runnable = len(extraction.runnable)
    store.replace_entities(project_id, [asdict(e) for e in extraction.entities])

    report.ledger_id = store.log(
        "absorb",
        detail=f"{project_name} ({chosen_bucket}): {report.symbols} symbols, "
               f"{report.total_entities} entities",
        payload={
            "source": str(source), "root": str(root), "bucket": chosen_bucket,
            "copied": bool(report.copied_to), "entities": report.entity_counts,
        },
    )
    return report


def reabsorb(store: Store, project_name: str, **kwargs) -> AbsorbReport:
    """Re-run absorption for a project already registered, keeping its settings."""
    project = store.project_by_name(project_name)
    if project is None:
        report = AbsorbReport(project=project_name, dry_run=False)
        report.errors.append(f"{project_name} is not registered")
        return report
    kwargs.setdefault("bucket", project.bucket)
    kwargs.setdefault("priority", project.priority)
    kwargs.setdefault("external", bool(project.external))
    return absorb(store, Path(project.root), name=project.name, **kwargs)


def release(store: Store, project_name: str) -> str:
    """Unregister a project. Its folder on disk is untouched.

    The counterpart to absorption being additive: nothing the harness did needs
    undoing on disk, so letting go is a single delete of the index rows.
    """
    project = store.project_by_name(project_name)
    if project is None:
        return f"{project_name} is not registered"
    root = project.root
    store.delete_project(project.id)
    store.log("release", detail=f"{project_name} unregistered (files untouched)")
    return (
        f"Released {project_name}. Index and entities removed.\n"
        f"The folder is exactly as it was: {root}"
    )


def capability_manifest(store: Store, project_name: str | None = None) -> str:
    """A flat list of everything the harness can do, for a human or an LLM.

    This is the answer to "what is actually in here" -- the question a folder tree
    cannot answer.
    """
    rows = store.entities(
        project_id=(
            store.project_by_name(project_name).id
            if project_name and store.project_by_name(project_name) else None
        )
    )
    if not rows:
        return "No entities registered. Absorb a project first."

    by_project: dict[str, list] = {}
    for row in rows:
        by_project.setdefault(row["project"], []).append(row)

    out = [
        "CAPABILITY MANIFEST",
        "=" * 74,
        f"{len(rows)} entities across {len(by_project)} projects",
        "",
        "Run anything listed here from the Harness tab, or with:",
        "    atlas run \"<name>\"",
        "",
    ]
    for project in sorted(by_project):
        members = by_project[project]
        bucket = members[0]["bucket"]
        out.append(f"## @{bucket}/{project}  ({len(members)} entities)")
        for kind in entitiesmod.KIND_ORDER:
            group = [m for m in members if m["kind"] == kind]
            if not group:
                continue
            out.append(f"  {kind}:")
            for row in group:
                summary = f"  -- {row['summary']}" if row["summary"] else ""
                out.append(f"    {row['name']}{summary}")
        out.append("")
    return "\n".join(out)


# --------------------------------------------------------------------- execution

def build_command(store: Store, entity_row, interpreter: str) -> tuple[list[str], Path]:
    """Turn a registered entity into an actual command line and working directory."""
    root = Path(entity_row["root"])
    # Keep integrated projects in their own installed environment.
    for candidate in (root / ".venv/Scripts/python.exe", root / "venv/Scripts/python.exe",
                      root / ".venv/bin/python", root / "venv/bin/python"):
        if candidate.is_file():
            interpreter = str(candidate)
            break
    mode = entity_row["run_mode"]
    target = entity_row["run_target"]
    args = [a for a in (entity_row["run_args"] or "").split("\x1f") if a]

    if mode == entitiesmod.RUN_MODULE:
        return [interpreter, "-m", target, *args], root
    if mode == entitiesmod.RUN_PYTHON:
        return [interpreter, str(root / target), *args], root
    if mode == entitiesmod.RUN_SHELL:
        path = root / target
        if path.suffix.lower() == ".ps1":
            return (
                ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(path), *args],
                root,
            )
        if path.suffix.lower() == ".sh":
            return ["bash", str(path), *args], root
        return ["cmd", "/c", str(path), *args], root
    if mode == entitiesmod.RUN_NOTEBOOK:
        return [interpreter, "-m", "jupyter", "notebook", str(root / target)], root
    raise ValueError(
        f"{entity_row['name']} is a {entity_row['kind']} -- import it, do not run it. "
        f"Address: {target}"
    )
