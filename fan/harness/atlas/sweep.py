"""Walk a directory of projects (a desktop, a repos folder) and bucket every one of them.

The hard part is not classification, it is deciding what counts as a project at all.
A desktop holds archives, media dumps, single loose scripts and half-finished checkouts;
this module makes that judgement explicitly and reports why, so the answer can be argued
with rather than merely trusted.
"""

from __future__ import annotations

import datetime as _dt
from dataclasses import dataclass, field
from pathlib import Path

from .buckets import Verdict, classify, gather_evidence
from .index import build_project_index, to_rows
from .spec import SKIP_DIR_NAMES
from .store import Store

# A folder with none of these and no source files is probably not a project.
PROJECT_MARKERS = {
    "pyproject.toml", "setup.py", "requirements.txt", "package.json", "cargo.toml",
    "go.mod", "pom.xml", "build.gradle", "makefile", "cmakelists.txt", "readme.md",
    ".git", "main.py", "app.py", "index.html", "manifest.json",
}

SOURCE_HINTS = {".py", ".pyw", ".js", ".ts", ".jsx", ".tsx", ".ahk", ".ino", ".c",
                ".cpp", ".h", ".cs", ".java", ".rs", ".go", ".rb", ".php", ".sh",
                ".ps1", ".bat", ".html", ".css", ".sql"}


@dataclass
class Candidate:
    """One folder considered during a sweep."""

    path: Path
    name: str
    is_project: bool
    reason: str
    verdict: Verdict | None = None
    source_files: int = 0
    total_files: int = 0
    priority: int = 50
    external: bool = False

    @property
    def bucket(self) -> str:
        return self.verdict.bucket if self.verdict else "misc"


@dataclass
class SweepResult:
    root: Path
    candidates: list[Candidate] = field(default_factory=list)
    skipped: list[Candidate] = field(default_factory=list)
    indexed: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    @property
    def projects(self) -> list[Candidate]:
        return [c for c in self.candidates if c.is_project]

    def by_bucket(self) -> dict[str, list[Candidate]]:
        grouped: dict[str, list[Candidate]] = {}
        for candidate in self.projects:
            grouped.setdefault(candidate.bucket, []).append(candidate)
        return grouped

    def render(self) -> str:
        grouped = self.by_bucket()
        out = [
            f"SWEEP {self.root}",
            f"  {len(self.projects)} projects, {len(self.skipped)} skipped, "
            f"{len(grouped)} buckets",
            "",
        ]
        for bucket in sorted(grouped, key=lambda b: -len(grouped[b])):
            members = grouped[bucket]
            out.append(f"[{bucket}]  {len(members)}")
            for candidate in sorted(members, key=lambda c: -c.source_files)[:12]:
                confidence = "" if (candidate.verdict and candidate.verdict.confident) else "  ?"
                out.append(
                    f"    {candidate.name[:52]:<52} {candidate.source_files:>4} src{confidence}"
                )
            if len(members) > 12:
                out.append(f"    ... and {len(members) - 12} more")
            out.append("")
        if self.errors:
            out.append("ERRORS")
            out += [f"  ! {e}" for e in self.errors]
        return "\n".join(out)


def looks_like_project(path: Path) -> tuple[bool, str, int, int]:
    """Decide whether a folder is a project. Returns (verdict, reason, sources, files)."""
    try:
        entries = list(path.iterdir())
    except OSError as exc:
        return False, f"unreadable: {exc}", 0, 0

    names = {e.name.lower() for e in entries}
    marker = names & PROJECT_MARKERS
    source_files = 0
    total_files = 0

    stack = [path]
    depth_budget = 600
    while stack and depth_budget > 0:
        current = stack.pop()
        try:
            for entry in current.iterdir():
                depth_budget -= 1
                if depth_budget <= 0:
                    break
                if entry.is_dir():
                    if entry.name in SKIP_DIR_NAMES or entry.name.startswith("."):
                        continue
                    stack.append(entry)
                elif entry.is_file():
                    total_files += 1
                    if entry.suffix.lower() in SOURCE_HINTS:
                        source_files += 1
        except OSError:
            continue

    if marker and source_files:
        return True, f"marker({','.join(sorted(marker)[:2])}) + {source_files} sources", source_files, total_files
    if source_files >= 3:
        return True, f"{source_files} source files", source_files, total_files
    if marker:
        return True, f"marker({','.join(sorted(marker)[:2])})", source_files, total_files
    if source_files:
        return False, f"only {source_files} source file(s) -- loose scripts", source_files, total_files
    return False, "no source files or project markers", source_files, total_files


def _priority_for(candidate: Candidate) -> int:
    """A first-pass priority. The GUI lets you pin and override; this just seeds it."""
    score = 40
    if candidate.source_files > 200:
        score += 25
    elif candidate.source_files > 50:
        score += 18
    elif candidate.source_files > 15:
        score += 10
    if (candidate.path / ".git").exists():
        score += 10
    if candidate.verdict and candidate.verdict.confident:
        score += 5
    try:
        age_days = (
            _dt.datetime.now() - _dt.datetime.fromtimestamp(candidate.path.stat().st_mtime)
        ).days
        if age_days < 30:
            score += 15
        elif age_days < 120:
            score += 7
    except OSError:
        pass
    return max(1, min(100, score))


def sweep(
    root: Path,
    max_projects: int = 500,
    progress=None,
) -> SweepResult:
    """Classify every immediate subfolder of ``root`` without indexing anything yet."""
    root = Path(root)
    result = SweepResult(root=root)
    try:
        entries = sorted(
            [e for e in root.iterdir() if e.is_dir()], key=lambda p: p.name.lower()
        )
    except OSError as exc:
        result.errors.append(f"cannot read {root}: {exc}")
        return result

    for position, path in enumerate(entries[:max_projects]):
        if path.name.startswith(".") or path.name in SKIP_DIR_NAMES:
            continue
        if progress:
            progress(position, len(entries), path.name)

        is_project, reason, sources, total = looks_like_project(path)
        candidate = Candidate(
            path=path, name=path.name, is_project=is_project, reason=reason,
            source_files=sources, total_files=total,
        )
        if is_project:
            try:
                evidence = gather_evidence(path)
                candidate.verdict = classify(path, evidence)
            except Exception as exc:
                result.errors.append(f"{path.name}: {exc}")
                candidate.verdict = Verdict("misc", 0.0, signals=[str(exc)])
            candidate.priority = _priority_for(candidate)
            result.candidates.append(candidate)
        else:
            result.skipped.append(candidate)

    return result


def index_candidates(
    store: Store,
    candidates: list[Candidate],
    max_files_each: int = 3000,
    progress=None,
) -> SweepResult:
    """Fully index a set of swept candidates into the store."""
    result = SweepResult(root=Path(candidates[0].path).parent if candidates else Path("."))
    for position, candidate in enumerate(candidates):
        if progress:
            progress(position, len(candidates), candidate.name)
        try:
            index = build_project_index(
                candidate.path, name=candidate.name, bucket=candidate.bucket,
                external=candidate.external, max_files=max_files_each,
            )
            files, symbols = to_rows(index)
            project_id = store.upsert_project(
                candidate.name, candidate.path,
                bucket=index.bucket,
                priority=candidate.priority,
                external=1 if candidate.external else 0,
                summary=(index.verdict.signals[0] if index.verdict.signals else ""),
                verdict=index.verdict.explain(),
                file_count=index.file_count,
                line_count=index.line_count,
                symbol_count=index.symbol_count,
                indexed_at=_dt.datetime.now().strftime("%Y-%m-%d %H:%M"),
            )
            store.replace_index(project_id, files, symbols)
            result.indexed.append(candidate.name)
            result.candidates.append(candidate)
        except Exception as exc:
            result.errors.append(f"{candidate.name}: {exc}")
    store.log("sweep-index", detail=f"{len(result.indexed)} projects indexed")
    return result
