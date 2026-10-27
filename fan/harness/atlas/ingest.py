"""Ingest-and-run: the pipeline that replaces "unzip it and hope".

Drop a ZIP or a mass document in, and one pass does all of it: unpack, plan placement,
check every symbol against the master index for duplicates, write, back up what was
there before, re-index, and optionally run the entry point -- in that order, so nothing
is executed before it has been captured.

A second drop of the same project diffs against the first and applies the changes while
retaining the previous state in the ledger.
"""

from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

from . import fanout, rules
from .buckets import classify
from .index import build_project_index, to_rows
from .ledger import Ledger
from .store import Store


@dataclass
class DuplicateHit:
    """A symbol in the incoming code that already exists in the indexed universe."""

    incoming: str
    existing_address: str
    score: float
    signature: str


@dataclass
class IngestReport:
    source: str = ""
    destination: str = ""
    project: str = ""
    bucket: str = ""
    plan: fanout.FanoutPlan | None = None
    written: list[str] = field(default_factory=list)
    duplicates: list[DuplicateHit] = field(default_factory=list)
    new_symbols: int = 0
    changed_files: list[str] = field(default_factory=list)
    backup_dir: str = ""
    ledger_id: int = 0
    run_output: str = ""
    run_exit: int | None = None
    errors: list[str] = field(default_factory=list)

    def render(self) -> str:
        out = [
            "=" * 68,
            f"INGEST  {self.source}",
            "=" * 68,
            f"destination : {self.destination}",
            f"project     : {self.project}   bucket: {self.bucket}",
            f"files       : {len(self.written)} written, {len(self.changed_files)} changed",
            f"symbols     : {self.new_symbols} indexed",
            f"duplicates  : {len(self.duplicates)}",
            f"backup      : {self.backup_dir or '(none needed)'}  ledger #{self.ledger_id}",
        ]
        if self.duplicates:
            out += ["", "DUPLICATES -- reuse these instead of the incoming copy:"]
            for dup in self.duplicates[:15]:
                out.append(f"  {dup.score:.2f}  {dup.incoming}  ->  {dup.existing_address}")
            if len(self.duplicates) > 15:
                out.append(f"  ... and {len(self.duplicates) - 15} more")
        if self.run_exit is not None:
            out += ["", f"RUN exit={self.run_exit}", self.run_output[-4000:]]
        if self.errors:
            out += ["", "ERRORS"] + [f"  ! {e}" for e in self.errors]
        return "\n".join(out)


ENTRY_CANDIDATES = ("main.py", "app.py", "run.py", "__main__.py", "cli.py", "start.py")


def find_entry_point(root: Path) -> Path | None:
    """Pick the most likely thing to run, preferring shallow, conventional names."""
    root = Path(root)
    for name in ENTRY_CANDIDATES:
        direct = root / name
        if direct.exists():
            return direct
    best: tuple[int, Path] | None = None
    for name in ENTRY_CANDIDATES:
        for candidate in root.rglob(name):
            if any(part in {".venv", "__pycache__", "node_modules"} for part in candidate.parts):
                continue
            depth = len(candidate.relative_to(root).parts)
            if best is None or depth < best[0]:
                best = (depth, candidate)
    return best[1] if best else None


# Names every project has. Matching one of these says nothing about duplication, and
# reporting them buries the real hits the operator needs to see.
BOILERPLATE_NAMES = {
    "main", "run", "setup", "start", "stop", "close", "init", "__init__", "__main__",
    "__repr__", "__str__", "__enter__", "__exit__", "test", "app", "cli", "parse_args",
    "build_parser", "configure", "handler", "wrapper", "helper",
}


def check_duplicates(
    store: Store, root: Path, threshold: float = 0.72
) -> list[DuplicateHit]:
    """Compare every incoming symbol against the whole indexed universe.

    This is what stops an agent regenerating something the codebase already has.
    Boilerplate names are excluded: a report full of ``main`` matches is a report
    nobody reads, and the point of this list is that every line in it is worth acting on.
    """
    from .scanner import scan_project

    hits: list[DuplicateHit] = []
    for scan in scan_project(root, max_files=1500):
        for symbol in scan.symbols:
            if symbol.leaf.lower() in BOILERPLATE_NAMES:
                continue
            intent = f"{symbol.name} {symbol.doc}".strip()
            result = rules.find(store, intent, threshold=threshold, limit=1)
            if not result.hit:
                continue
            match = result.matches[0]
            hits.append(
                DuplicateHit(
                    incoming=f"{scan.path}#{symbol.name}",
                    existing_address=match.address,
                    score=match.score,
                    signature=match.signature,
                )
            )
    return sorted(hits, key=lambda h: h.score, reverse=True)


def ingest(
    store: Store,
    source: Path,
    destination: Path | None = None,
    project_name: str | None = None,
    bucket: str | None = None,
    run: bool = False,
    run_timeout: int = 60,
    overwrite: bool = False,
    dedupe_threshold: float = 0.72,
) -> IngestReport:
    """Run the whole pipeline for one incoming ZIP, document, or folder."""
    source = Path(source)
    report = IngestReport(source=str(source))
    ledger = Ledger(store)

    name = project_name or source.stem.replace(" ", "_")
    target = Path(destination) if destination else (store.workspace / "projects" / name)
    report.destination = str(target)
    report.project = name

    # ---- 1. plan -------------------------------------------------------------
    if source.is_dir():
        plan = fanout.FanoutPlan()
        for path in source.rglob("*"):
            if path.is_file():
                rel = path.relative_to(source).as_posix()
                try:
                    content = path.read_text(encoding="utf-8")
                except (OSError, UnicodeDecodeError):
                    continue
                plan.pieces.append(
                    fanout.Piece(rel, content, path.suffix.lstrip("."), 1.0,
                                 str(source), "from folder")
                )
    elif source.suffix.lower() == ".zip":
        plan = fanout.parse_zip(source)
    else:
        try:
            plan = fanout.parse_document(source.read_text(encoding="utf-8", errors="replace"))
        except OSError as exc:
            report.errors.append(f"cannot read source: {exc}")
            return report
    report.plan = plan
    report.errors.extend(plan.warnings)

    if not plan.pieces:
        report.errors.append("nothing to ingest")
        return report

    # ---- 2. back up what is already there ------------------------------------
    if target.exists():
        existing = [p for p in target.rglob("*") if p.is_file()]
        report.changed_files = [
            p.path for p in plan.pieces if (target / p.path).exists()
        ]
        if existing:
            backup = ledger.snapshot(
                existing, action="ingest-backup",
                detail=f"before ingesting {source.name} into {name}",
            )
            report.backup_dir = str(backup.directory)
            report.ledger_id = backup.ledger_id

    # ---- 3. write ------------------------------------------------------------
    report.written = fanout.commit(
        plan, target, archive=source if source.suffix.lower() == ".zip" else None,
        overwrite=overwrite,
    )

    # ---- 4. dedupe against the master index ----------------------------------
    try:
        report.duplicates = check_duplicates(store, target, dedupe_threshold)
    except Exception as exc:  # a dedupe failure must not lose the ingest
        report.errors.append(f"dedupe check failed: {exc}")

    # ---- 5. index ------------------------------------------------------------
    try:
        verdict_bucket = bucket or classify(target).bucket
        index = build_project_index(target, name=name, bucket=verdict_bucket)
        files, symbols = to_rows(index)
        project_id = store.upsert_project(
            name, target,
            bucket=index.bucket, summary=f"ingested from {source.name}",
            verdict=index.verdict.explain(), file_count=index.file_count,
            line_count=index.line_count, symbol_count=index.symbol_count,
            indexed_at=__import__("datetime").datetime.now().strftime("%Y-%m-%d %H:%M"),
        )
        store.replace_index(project_id, files, symbols)
        report.bucket = index.bucket
        report.new_symbols = len(symbols)
    except Exception as exc:
        report.errors.append(f"indexing failed: {exc}")

    if not report.ledger_id:
        report.ledger_id = store.log(
            "ingest", detail=f"{source.name} -> {name}",
            payload={"written": len(report.written), "duplicates": len(report.duplicates)},
        )

    # ---- 6. run (last, so nothing executes before it is captured) -------------
    if run:
        entry = find_entry_point(target)
        if entry is None:
            report.errors.append("no entry point found to run")
        else:
            try:
                completed = subprocess.run(
                    [sys.executable, str(entry)],
                    cwd=str(target), capture_output=True, text=True,
                    timeout=run_timeout,
                )
                report.run_exit = completed.returncode
                report.run_output = (completed.stdout or "") + (completed.stderr or "")
            except subprocess.TimeoutExpired:
                report.run_exit = -1
                report.run_output = f"timed out after {run_timeout}s (a GUI app will do this)"
            except OSError as exc:
                report.errors.append(f"run failed: {exc}")

    return report


# ------------------------------------------------------------------- hot folder

def scan_hot_folder(store: Store, folder: Path) -> list[Path]:
    """Everything in the hot folder that has not been ingested yet."""
    folder = Path(folder)
    if not folder.exists():
        return []
    done = {
        Path(row["detail"].split(" -> ")[0]).name
        for row in store.many("SELECT detail FROM ledger WHERE action = 'ingest'")
        if " -> " in (row["detail"] or "")
    }
    pending: list[Path] = []
    for path in sorted(folder.iterdir()):
        if path.name.startswith("."):
            continue
        if path.is_file() and path.suffix.lower() not in {".zip", ".md", ".txt"}:
            continue
        if path.name in done:
            continue
        pending.append(path)
    return pending


def drain_hot_folder(
    store: Store, folder: Path, run: bool = False, limit: int = 10
) -> list[IngestReport]:
    """Ingest everything waiting in the hot folder, oldest first."""
    reports: list[IngestReport] = []
    for path in scan_hot_folder(store, folder)[:limit]:
        reports.append(ingest(store, path, run=run))
    return reports
