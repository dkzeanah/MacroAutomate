"""
Evergreen Desktop Consolidator v2 - Loud / Diagnostic / Automatic

This is the "run it and it does the whole workflow" version.

It fixes the common "ran but did nothing" problem by:
- printing every major step
- writing a report every run, even if it finds nothing
- scanning Desktop AND common Desktop organizer folders AND Downloads by default
- scanning immediate project folders plus one level of common extracted/download folders
- preserving originals
- avoiding overwrite
- making a _DIAGNOSTICS.txt file explaining what was found/skipped

Default run:
    python evergreen_desktop_consolidator_v2.py

Preview only:
    python evergreen_desktop_consolidator_v2.py --dry-run

Force a specific source folder:
    python evergreen_desktop_consolidator_v2.py --source "C:\\Users\\Don\\Desktop"

Scan deeper:
    python evergreen_desktop_consolidator_v2.py --max-depth 10 --container-depth 2

Only diagnose, do not organize/consolidate:
    python evergreen_desktop_consolidator_v2.py --diagnose-only
"""

from __future__ import annotations

import argparse
import csv
import difflib
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import zipfile
from dataclasses import dataclass, field
from pathlib import Path


APP_NAME = "Evergreen Desktop Consolidator v2"

EXCLUDED_DIR_NAMES = {
    ".git", ".hg", ".svn", "__pycache__", ".mypy_cache", ".pytest_cache",
    ".ruff_cache", ".tox", ".nox", ".venv", "venv", "env", "ENV",
    "node_modules", "site-packages", "dist-packages", "build", "dist",
    ".idea", ".vscode", "globalcoder1",
    "Consolidated_Python_Projects",
}

ORGANIZER_FOLDERS_TO_SKIP_AS_PROJECTS = {
    "Desktop - Images",
    "Desktop - Videos",
    "Desktop - Audio",
    "Desktop - Code Files",
    "Desktop - Documents",
    "Desktop - Spreadsheets",
    "Desktop - Presentations",
    "Desktop - Archives",
    "Desktop - Installers",
    "Desktop - Shortcuts and Programs",
    "Desktop - Data Files",
    "Desktop - Fonts",
    "Desktop - 3D CAD",
    "Desktop - Misc Unsorted",
    "Desktop - Organization Reports",
}

ORGANIZER_FOLDERS_TO_SCAN_FOR_PROJECT_ZIPS = {
    "Desktop - Project Source Zips",
    "Desktop - Archives",
    "Desktop - Code Files",
}

PROJECT_MARKERS = {
    "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt",
    "Pipfile", "poetry.lock", ".git", "README.md", "readme.md",
}

CODE_EXTENSIONS = {
    ".py", ".pyw", ".ahk", ".js", ".ts", ".tsx", ".jsx", ".html", ".css", ".scss",
    ".json", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".bat", ".cmd", ".ps1",
    ".sh", ".sql", ".md", ".txt", ".xml", ".cs", ".cpp", ".c", ".h", ".hpp",
    ".java", ".go", ".rs", ".php", ".rb", ".lua",
}

PROJECT_CODE_EXTENSIONS = {".py", ".pyw"}

CATEGORY_EXTENSIONS: dict[str, set[str]] = {
    "Desktop - Images": {
        ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tif", ".tiff", ".webp",
        ".heic", ".svg", ".ico", ".avif",
    },
    "Desktop - Videos": {
        ".mp4", ".mkv", ".avi", ".mov", ".wmv", ".m4v", ".webm", ".mpeg",
        ".mpg", ".mts", ".m2ts", ".ts", ".flv", ".vob", ".ogv", ".3gp",
    },
    "Desktop - Audio": {
        ".mp3", ".wav", ".flac", ".aac", ".m4a", ".ogg", ".wma", ".opus",
        ".mid", ".midi",
    },
    "Desktop - Code Files": {
        ".py", ".pyw", ".ahk", ".js", ".ts", ".tsx", ".jsx", ".html", ".css",
        ".scss", ".json", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".bat",
        ".cmd", ".ps1", ".sh", ".sql", ".cs", ".cpp", ".c", ".h", ".hpp",
        ".java", ".go", ".rs", ".php", ".rb", ".lua", ".xml",
    },
    "Desktop - Documents": {
        ".pdf", ".doc", ".docx", ".rtf", ".odt", ".txt", ".md", ".epub", ".mobi",
    },
    "Desktop - Spreadsheets": {".xls", ".xlsx", ".xlsm", ".csv", ".tsv", ".ods"},
    "Desktop - Presentations": {".ppt", ".pptx", ".odp"},
    "Desktop - Project Source Zips": {".zip"},
    "Desktop - Archives": {
        ".7z", ".rar", ".tar", ".gz", ".gzip", ".bz2", ".xz", ".tgz", ".cab", ".iso",
    },
    "Desktop - Installers": {".msi", ".msix", ".appx", ".appxbundle", ".deb", ".rpm", ".dmg", ".pkg"},
    "Desktop - Shortcuts and Programs": {".lnk", ".url", ".website", ".exe", ".com"},
    "Desktop - Data Files": {
        ".db", ".sqlite", ".sqlite3", ".duckdb", ".parquet", ".feather", ".pkl",
        ".pickle", ".jsonl", ".ndjson", ".log",
    },
    "Desktop - Fonts": {".ttf", ".otf", ".woff", ".woff2", ".fon"},
    "Desktop - 3D CAD": {
        ".stl", ".obj", ".fbx", ".glb", ".gltf", ".step", ".stp", ".iges",
        ".igs", ".dwg", ".dxf", ".blend", ".3mf",
    },
}

ITERATION_WORDS = {
    "fixed", "fix", "patched", "patch", "updated", "update", "final", "latest",
    "new", "complete", "completed", "full", "project", "package", "export",
    "download", "copy", "backup", "old", "version", "rev", "revision",
    "iteration", "iter", "chatgpt", "gpt", "working", "tested", "debug",
    "debugged", "v",
}


@dataclass
class SourceItem:
    id: str
    path: str
    name: str
    source_type: str  # folder or zip
    family_key: str
    py_files: int = 0
    code_files: int = 0
    total_files: int = 0
    total_bytes: int = 0
    code_lines: int = 0
    last_modified_ts: float = 0.0
    last_modified: str = ""
    entrypoints: list[str] = field(default_factory=list)
    relative_files: dict[str, str] = field(default_factory=dict)

    @property
    def score(self) -> tuple[float, int, int, int]:
        return (self.last_modified_ts, self.code_lines, self.py_files, self.total_bytes)


@dataclass
class FamilyGroup:
    key: str
    display_name: str
    sources: list[SourceItem] = field(default_factory=list)
    current_id: str | None = None

    def sorted_sources(self) -> list[SourceItem]:
        return sorted(self.sources, key=lambda s: s.score, reverse=True)

    def current(self) -> SourceItem | None:
        if self.current_id:
            for source in self.sources:
                if source.id == self.current_id:
                    return source
        sorted_sources = self.sorted_sources()
        return sorted_sources[0] if sorted_sources else None


class Logger:
    def __init__(self) -> None:
        self.lines: list[str] = []

    def log(self, message: str) -> None:
        line = f"[{now_text()}] {message}"
        self.lines.append(line)
        print(line, flush=True)

    def write(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(self.lines) + "\n", encoding="utf-8")


def now_text() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def stamp() -> str:
    return time.strftime("%Y%m%d_%H%M%S")


def desktop_path() -> Path:
    return Path.home() / "Desktop"


def downloads_path() -> Path:
    return Path.home() / "Downloads"


def safe_name(value: str) -> str:
    cleaned = re.sub(r'[<>:"/\\|?*\x00-\x1f]+', "_", value)
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" .")
    return cleaned[:150] or "Unnamed"


def format_ts(ts_value: float) -> str:
    if not ts_value:
        return ""
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ts_value))


def clean_iteration_name(name: str) -> str:
    stem = Path(name).stem
    stem = re.sub(r"\.(zip|tar|gz|7z|rar)$", "", stem, flags=re.I)
    stem = re.sub(r"[_\-.]+", " ", stem)
    stem = re.sub(r"\([0-9]+\)", " ", stem)
    stem = re.sub(r"\b\d{4}[-_ ]?\d{2}[-_ ]?\d{2}\b", " ", stem)
    stem = re.sub(r"\b\d{8}\b", " ", stem)
    stem = re.sub(r"\b\d{1,2}[-_]\d{1,2}[-_]\d{2,4}\b", " ", stem)
    stem = re.sub(r"\bv?\d+(\.\d+){0,3}\b", " ", stem, flags=re.I)
    stem = re.sub(r"\b(iter|iteration|rev|revision|fix|fixed|patched|update|updated)[-_ ]*\d+\b", " ", stem, flags=re.I)

    words = [w for w in re.split(r"\s+", stem.lower()) if w]
    words = [w for w in words if w not in ITERATION_WORDS]
    if not words:
        words = [w for w in re.split(r"\s+", Path(name).stem.lower()) if w]
    return " ".join(words).strip()


def family_key_from_name(name: str) -> str:
    cleaned = clean_iteration_name(name)
    key = re.sub(r"[^a-z0-9]+", "-", cleaned.lower()).strip("-")
    return key or re.sub(r"[^a-z0-9]+", "-", Path(name).stem.lower()).strip("-") or "unnamed-project"


def path_contains_excluded_dir(path: Path) -> bool:
    parts = {part.lower() for part in path.parts}
    return bool(parts & {x.lower() for x in EXCLUDED_DIR_NAMES})


def should_skip_top_folder(folder: Path) -> bool:
    name = folder.name
    if name in ORGANIZER_FOLDERS_TO_SKIP_AS_PROJECTS:
        return True
    if name in ORGANIZER_FOLDERS_TO_SCAN_FOR_PROJECT_ZIPS:
        return False
    if name in EXCLUDED_DIR_NAMES:
        return True
    return False


def count_code_lines(text: str) -> int:
    count = 0
    for line in text.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            count += 1
    return count


def read_text_file(path: Path, limit: int = 250_000) -> str:
    try:
        with path.open("r", encoding="utf-8", errors="ignore") as f:
            return f.read(limit)
    except OSError:
        return ""


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def unique_destination(path: Path) -> Path:
    if not path.exists():
        return path
    stem = path.stem
    suffix = path.suffix
    parent = path.parent
    for i in range(2, 10000):
        candidate = parent / f"{stem} ({i}){suffix}"
        if not candidate.exists():
            return candidate
    raise RuntimeError(f"Could not create unique destination for {path}")


def zip_member_safe(name: str) -> bool:
    normalized = name.replace("\\", "/")
    if normalized.startswith("/") or normalized.startswith("../") or "/../" in normalized:
        return False
    if re.match(r"^[A-Za-z]:", normalized):
        return False
    return True


def zip_common_prefix(names: list[str]) -> str:
    first_parts = []
    for name in names:
        normalized = name.replace("\\", "/").strip("/")
        if not normalized or normalized.endswith("/"):
            continue
        first_parts.append(normalized.split("/", 1)[0])
    if first_parts and len(set(first_parts)) == 1:
        return first_parts[0]
    return ""


def strip_zip_prefix(name: str, prefix: str) -> str:
    normalized = name.replace("\\", "/").strip("/")
    if prefix and normalized.startswith(prefix.strip("/") + "/"):
        return normalized[len(prefix.strip("/") + "/"):]
    return normalized


def detect_entrypoint(rel_path: str, text: str) -> bool:
    low = text.lower()
    base = Path(rel_path).name.lower()
    if re.search(r"if\s+__name__\s*==\s*['\"]__main__['\"]", text):
        return True
    if base in {"main.py", "app.py", "run.py", "start.py", "launcher.py", "run_gui.py", "__main__.py"}:
        return True
    if "streamlit" in low and ("st." in text or "import streamlit" in low):
        return True
    if "fastapi(" in low or "flask(" in low:
        return True
    if ("import tkinter" in low or "from tkinter" in low or "customtkinter" in low) and "mainloop(" in low:
        return True
    if "argparse" in low or "click.command" in low or "typer." in low:
        return True
    return False


class SourceScanner:
    def __init__(self, source_roots: list[Path], max_depth: int, container_depth: int, logger: Logger) -> None:
        self.source_roots = source_roots
        self.max_depth = max_depth
        self.container_depth = container_depth
        self.logger = logger
        self.items: list[SourceItem] = []
        self.errors: list[str] = []
        self.counter = 0
        self.scanned_containers: list[str] = []
        self.skipped_containers: list[str] = []

    def next_id(self) -> str:
        self.counter += 1
        return f"S{self.counter:06d}"

    def scan(self) -> list[SourceItem]:
        candidates = self.find_candidate_containers()
        self.logger.log(f"Candidate containers found: {len(candidates)}")

        for candidate in candidates:
            try:
                if candidate.is_dir():
                    item = self.scan_folder(candidate)
                elif candidate.is_file() and candidate.suffix.lower() == ".zip":
                    item = self.scan_zip(candidate)
                else:
                    continue

                if item.py_files > 0:
                    self.items.append(item)
                    self.logger.log(f"PROJECT SOURCE: {item.source_type} | py={item.py_files} | {item.path}")
                else:
                    self.skipped_containers.append(f"No Python files after scan: {candidate}")
            except Exception as exc:
                self.errors.append(f"{candidate}: {exc}")
                self.logger.log(f"ERROR scanning {candidate}: {exc}")

        return self.items

    def find_candidate_containers(self) -> list[Path]:
        candidates: list[Path] = []
        seen: set[str] = set()

        for root in self.source_roots:
            if not root.exists():
                self.logger.log(f"Source root missing: {root}")
                continue

            self.logger.log(f"Searching source root: {root}")
            for candidate in self.walk_containers(root):
                key = str(candidate.resolve()).lower()
                if key not in seen:
                    seen.add(key)
                    candidates.append(candidate)

        return candidates

    def walk_containers(self, root: Path) -> list[Path]:
        out: list[Path] = []

        # Immediate children.
        try:
            children = sorted(root.iterdir(), key=lambda p: p.name.lower())
        except OSError as exc:
            self.errors.append(f"{root}: {exc}")
            return out

        for child in children:
            if child.is_dir():
                if should_skip_top_folder(child) and child.name not in ORGANIZER_FOLDERS_TO_SCAN_FOR_PROJECT_ZIPS:
                    self.skipped_containers.append(f"Skipped managed/excluded folder: {child}")
                    continue

                if self.folder_has_python(child):
                    out.append(child)
                else:
                    # Also inspect one or more nested containers inside big "files (xx)" folders.
                    if self.container_depth > 0:
                        out.extend(self.find_nested_project_folders(child, self.container_depth))

            elif child.is_file() and child.suffix.lower() == ".zip":
                out.append(child)

        return out

    def find_nested_project_folders(self, folder: Path, remaining_depth: int) -> list[Path]:
        out: list[Path] = []
        if remaining_depth <= 0:
            return out
        if path_contains_excluded_dir(folder):
            return out

        try:
            for child in sorted(folder.iterdir(), key=lambda p: p.name.lower()):
                if child.is_dir():
                    if path_contains_excluded_dir(child):
                        continue
                    if self.folder_has_python(child):
                        out.append(child)
                    else:
                        out.extend(self.find_nested_project_folders(child, remaining_depth - 1))
                elif child.is_file() and child.suffix.lower() == ".zip":
                    out.append(child)
        except OSError:
            pass
        return out

    def folder_has_python(self, folder: Path) -> bool:
        base_depth = len(folder.parts)
        stack = [folder]
        while stack:
            current = stack.pop()
            depth = len(current.parts) - base_depth
            if depth > self.max_depth:
                continue

            try:
                for entry in current.iterdir():
                    if entry.is_dir():
                        if not path_contains_excluded_dir(entry):
                            stack.append(entry)
                    elif entry.is_file() and entry.suffix.lower() in PROJECT_CODE_EXTENSIONS:
                        return True
            except OSError:
                continue
        return False

    def scan_folder(self, folder: Path) -> SourceItem:
        rel_hashes: dict[str, str] = {}
        py_files = 0
        code_files = 0
        total_files = 0
        total_bytes = 0
        code_lines = 0
        last_modified_ts = 0.0
        entrypoints: list[str] = []

        for current, dirs, files in os.walk(folder):
            current_path = Path(current)
            dirs[:] = [d for d in dirs if not path_contains_excluded_dir(current_path / d)]

            depth = len(current_path.parts) - len(folder.parts)
            if depth > self.max_depth:
                dirs[:] = []
                continue

            for filename in files:
                file_path = current_path / filename
                try:
                    rel = file_path.relative_to(folder).as_posix()
                    suffix = file_path.suffix.lower()
                    stat = file_path.stat()

                    total_files += 1
                    total_bytes += stat.st_size
                    last_modified_ts = max(last_modified_ts, stat.st_mtime)

                    if suffix in CODE_EXTENSIONS:
                        code_files += 1
                        rel_hashes[rel] = sha256_file(file_path)
                        if suffix in PROJECT_CODE_EXTENSIONS:
                            py_files += 1
                            text = read_text_file(file_path)
                            code_lines += count_code_lines(text)
                            if detect_entrypoint(rel, text):
                                entrypoints.append(rel)
                    elif stat.st_size <= 20 * 1024 * 1024:
                        rel_hashes[rel] = sha256_file(file_path)
                except OSError:
                    continue

        return SourceItem(
            id=self.next_id(),
            path=str(folder),
            name=folder.name,
            source_type="folder",
            family_key=family_key_from_name(folder.name),
            py_files=py_files,
            code_files=code_files,
            total_files=total_files,
            total_bytes=total_bytes,
            code_lines=code_lines,
            last_modified_ts=last_modified_ts,
            last_modified=format_ts(last_modified_ts),
            entrypoints=sorted(entrypoints),
            relative_files=rel_hashes,
        )

    def scan_zip(self, zip_path: Path) -> SourceItem:
        rel_hashes: dict[str, str] = {}
        py_files = 0
        code_files = 0
        total_files = 0
        total_bytes = 0
        code_lines = 0
        entrypoints: list[str] = []
        last_modified_ts = zip_path.stat().st_mtime

        try:
            with zipfile.ZipFile(zip_path, "r") as zf:
                names = [info.filename for info in zf.infolist() if not info.is_dir() and zip_member_safe(info.filename)]
                prefix = zip_common_prefix(names)

                for info in zf.infolist():
                    if info.is_dir() or not zip_member_safe(info.filename):
                        continue

                    rel = strip_zip_prefix(info.filename, prefix)
                    if not rel:
                        continue

                    parts = {p.lower() for p in rel.split("/") if p}
                    if parts & {x.lower() for x in EXCLUDED_DIR_NAMES}:
                        continue

                    suffix = Path(rel).suffix.lower()
                    total_files += 1
                    total_bytes += info.file_size

                    if suffix in CODE_EXTENSIONS:
                        code_files += 1
                        data = zf.read(info)
                        rel_hashes[rel] = sha256_bytes(data)

                        if suffix in PROJECT_CODE_EXTENSIONS:
                            py_files += 1
                            text = data.decode("utf-8", errors="ignore")
                            code_lines += count_code_lines(text)
                            if detect_entrypoint(rel, text):
                                entrypoints.append(rel)
                    elif info.file_size <= 20 * 1024 * 1024:
                        rel_hashes[rel] = sha256_bytes(zf.read(info))
        except zipfile.BadZipFile:
            self.errors.append(f"Bad zip file: {zip_path}")

        return SourceItem(
            id=self.next_id(),
            path=str(zip_path),
            name=zip_path.stem,
            source_type="zip",
            family_key=family_key_from_name(zip_path.stem),
            py_files=py_files,
            code_files=code_files,
            total_files=total_files,
            total_bytes=total_bytes,
            code_lines=code_lines,
            last_modified_ts=last_modified_ts,
            last_modified=format_ts(last_modified_ts),
            entrypoints=sorted(entrypoints),
            relative_files=rel_hashes,
        )


def merge_family_keys(items: list[SourceItem], threshold: float) -> dict[str, FamilyGroup]:
    families: dict[str, FamilyGroup] = {}

    for item in items:
        chosen_key = None
        for key in families:
            ratio = difflib.SequenceMatcher(None, item.family_key, key).ratio()
            containment = item.family_key in key or key in item.family_key
            if ratio >= threshold or (containment and min(len(item.family_key), len(key)) >= 8):
                chosen_key = key
                break

        if chosen_key is None:
            chosen_key = item.family_key
            families[chosen_key] = FamilyGroup(key=chosen_key, display_name=safe_name(clean_iteration_name(item.name).title()))

        item.family_key = chosen_key
        families[chosen_key].sources.append(item)

    for family in families.values():
        current = family.current()
        if current:
            family.current_id = current.id
            family.display_name = safe_name(clean_iteration_name(current.name).title() or family.display_name)

    return families


class ProjectConsolidator:
    def __init__(self, dest_root: Path, dry_run: bool, logger: Logger) -> None:
        self.dest_root = dest_root
        self.dry_run = dry_run
        self.logger = logger
        self.manifests: list[dict] = []

    def consolidate_all(self, families: dict[str, FamilyGroup]) -> list[Path]:
        made: list[Path] = []
        for family in families.values():
            dest = self.consolidate_family(family)
            made.append(dest)
        return made

    def consolidate_family(self, family: FamilyGroup) -> Path:
        current = family.current()
        if not current:
            raise ValueError("Family has no current source")

        dest_name = safe_name(clean_iteration_name(current.name).title() or family.display_name)
        dest = unique_destination(self.dest_root / dest_name)

        self.logger.log(f"Consolidating family '{family.display_name}' -> {dest}")
        if not self.dry_run:
            dest.mkdir(parents=True, exist_ok=True)

        manifest = {
            "created_at": now_text(),
            "family_key": family.key,
            "display_name": family.display_name,
            "destination": str(dest),
            "current_source": current.path,
            "current_source_type": current.source_type,
            "sources": [],
            "summary": {
                "iterations": len(family.sources),
                "current_files": len(current.relative_files),
                "exact_duplicates": 0,
                "conflicts_same_path": 0,
                "candidate_additions": 0,
            },
        }

        self.copy_source_front(current, dest)

        archive_root = dest / "_archive_iterations"
        duplicates_root = dest / "_duplicates_exact"
        additions_root = dest / "_candidate_additions"
        zips_root = dest / "_source_zips"

        current_hashes = current.relative_files

        for source in family.sorted_sources():
            source_record = {
                "path": source.path,
                "source_type": source.source_type,
                "role": "current" if source.id == current.id else "older",
                "py_files": source.py_files,
                "code_lines": source.code_lines,
                "last_modified": source.last_modified,
                "exact_duplicates": [],
                "conflicts_same_path": [],
                "candidate_additions": [],
            }

            if source.source_type == "zip":
                if not self.dry_run:
                    zips_root.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source.path, unique_destination(zips_root / Path(source.path).name))

            if source.id != current.id:
                safe_source = safe_name(source.name)
                for rel, file_hash in source.relative_files.items():
                    current_hash = current_hashes.get(rel)
                    if current_hash and current_hash == file_hash:
                        target_base = duplicates_root / safe_source
                        source_record["exact_duplicates"].append(rel)
                        manifest["summary"]["exact_duplicates"] += 1
                    elif current_hash and current_hash != file_hash:
                        target_base = archive_root / safe_source / "conflicts_same_path"
                        source_record["conflicts_same_path"].append(rel)
                        manifest["summary"]["conflicts_same_path"] += 1
                    else:
                        target_base = additions_root / safe_source
                        source_record["candidate_additions"].append(rel)
                        manifest["summary"]["candidate_additions"] += 1
                    self.copy_single_member(source, rel, target_base / rel)

            manifest["sources"].append(source_record)

        if not self.dry_run:
            (dest / "_CONSOLIDATION_MANIFEST.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
            (dest / "_README_CONSOLIDATION.txt").write_text(self.readme_text(manifest), encoding="utf-8")

        self.manifests.append(manifest)
        return dest

    def copy_source_front(self, source: SourceItem, dest: Path) -> None:
        if source.source_type == "folder":
            src = Path(source.path)
            for current, dirs, files in os.walk(src):
                current_path = Path(current)
                dirs[:] = [d for d in dirs if not path_contains_excluded_dir(current_path / d)]
                for filename in files:
                    src_file = current_path / filename
                    try:
                        rel = src_file.relative_to(src)
                    except ValueError:
                        continue
                    target = unique_destination(dest / rel)
                    if not self.dry_run:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(src_file, target)
        else:
            self.extract_zip(Path(source.path), dest)

    def extract_zip(self, zip_path: Path, dest: Path) -> None:
        if self.dry_run:
            return
        with zipfile.ZipFile(zip_path, "r") as zf:
            names = [info.filename for info in zf.infolist() if not info.is_dir() and zip_member_safe(info.filename)]
            prefix = zip_common_prefix(names)
            for info in zf.infolist():
                if info.is_dir() or not zip_member_safe(info.filename):
                    continue
                rel = strip_zip_prefix(info.filename, prefix)
                if not rel:
                    continue
                target = unique_destination(dest / rel)
                target.parent.mkdir(parents=True, exist_ok=True)
                with zf.open(info) as src, target.open("wb") as out:
                    shutil.copyfileobj(src, out)

    def copy_single_member(self, source: SourceItem, rel: str, target: Path) -> None:
        if self.dry_run:
            return
        target = unique_destination(target)
        target.parent.mkdir(parents=True, exist_ok=True)

        if source.source_type == "folder":
            src = Path(source.path) / rel
            if src.exists() and src.is_file():
                shutil.copy2(src, target)
        else:
            with zipfile.ZipFile(source.path, "r") as zf:
                names = [info.filename for info in zf.infolist() if not info.is_dir() and zip_member_safe(info.filename)]
                prefix = zip_common_prefix(names)
                candidates = [rel]
                if prefix:
                    candidates.append(prefix.rstrip("/") + "/" + rel)
                for candidate in candidates:
                    try:
                        with zf.open(candidate) as src, target.open("wb") as out:
                            shutil.copyfileobj(src, out)
                        return
                    except KeyError:
                        continue

    @staticmethod
    def readme_text(manifest: dict) -> str:
        return (
            "CONSOLIDATED PROJECT - LOSSLESS COPY\n\n"
            f"Created: {manifest['created_at']}\n"
            f"Current/front source: {manifest['current_source']}\n\n"
            "Root folder contains the selected current project version.\n"
            "_archive_iterations contains older files that conflict by same relative path.\n"
            "_candidate_additions contains older files not present in the current version.\n"
            "_duplicates_exact contains exact duplicates from older versions.\n"
            "_source_zips contains source ZIP files copied for traceability.\n\n"
            "Original source folders were not deleted.\n\n"
            "Summary:\n"
            + json.dumps(manifest.get("summary", {}), indent=2)
            + "\n"
        )


class LooseFileOrganizer:
    def __init__(self, desktop: Path, dry_run: bool, logger: Logger) -> None:
        self.desktop = desktop
        self.dry_run = dry_run
        self.logger = logger
        self.moves: list[dict] = []
        self.leftovers: list[str] = []

    def organize(self) -> None:
        self.logger.log("Organizing loose desktop files by file type.")
        if not self.dry_run:
            for folder in CATEGORY_EXTENSIONS:
                (self.desktop / folder).mkdir(parents=True, exist_ok=True)
            (self.desktop / "Desktop - Misc Unsorted").mkdir(parents=True, exist_ok=True)
            (self.desktop / "Desktop - Organization Reports").mkdir(parents=True, exist_ok=True)

        for item in sorted(self.desktop.iterdir(), key=lambda p: p.name.lower()):
            if not item.is_file():
                continue

            if item.name.startswith("desktop_automation_report_"):
                continue

            category = self.category_for_file(item)
            if not category:
                category = "Desktop - Misc Unsorted"
                self.leftovers.append(str(item))

            dest = self.desktop / category / item.name
            if item.resolve() == dest.resolve():
                continue

            target = unique_destination(dest)
            self.logger.log(f"MOVE: {item} -> {target}")
            if not self.dry_run:
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(item), str(target))

            self.moves.append({"from": str(item), "to": str(target), "category": category})

    @staticmethod
    def category_for_file(path: Path) -> str:
        suffix = path.suffix.lower()
        for category, extensions in CATEGORY_EXTENSIONS.items():
            if suffix in extensions:
                return category
        return ""


def default_source_roots(source: Path | None) -> list[Path]:
    if source:
        return [source]
    roots = [desktop_path()]

    # If a previous run organized zips, include those folders too.
    for folder_name in ORGANIZER_FOLDERS_TO_SCAN_FOR_PROJECT_ZIPS:
        folder = desktop_path() / folder_name
        if folder.exists():
            roots.append(folder)

    # A lot of ChatGPT project zips land in Downloads first.
    if downloads_path().exists():
        roots.append(downloads_path())

    # Deduplicate.
    out: list[Path] = []
    seen: set[str] = set()
    for root in roots:
        try:
            key = str(root.resolve()).lower()
        except OSError:
            key = str(root).lower()
        if key not in seen:
            seen.add(key)
            out.append(root)
    return out


def write_summary_csv(path: Path, families: dict[str, FamilyGroup]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "family",
            "iterations",
            "current_name",
            "current_path",
            "current_type",
            "current_py_files",
            "current_code_lines",
            "last_modified",
            "entrypoints",
            "all_sources",
        ])
        for family in families.values():
            current = family.current()
            if not current:
                continue
            writer.writerow([
                family.display_name,
                len(family.sources),
                current.name,
                current.path,
                current.source_type,
                current.py_files,
                current.code_lines,
                current.last_modified,
                "; ".join(current.entrypoints),
                " | ".join(s.path for s in family.sources),
            ])


def open_folder(path: Path) -> None:
    try:
        if sys.platform.startswith("win"):
            os.startfile(str(path))  # type: ignore[attr-defined]
        elif sys.platform == "darwin":
            subprocess.Popen(["open", str(path)])
        else:
            subprocess.Popen(["xdg-open", str(path)])
    except Exception:
        pass


def run(args: argparse.Namespace) -> dict:
    logger = Logger()
    desktop = desktop_path()
    reports = desktop / "Desktop - Organization Reports"
    dest = Path(args.dest).expanduser() if args.dest else desktop / "Consolidated_Python_Projects"
    dry_run = args.dry_run

    if not dry_run:
        reports.mkdir(parents=True, exist_ok=True)
        dest.mkdir(parents=True, exist_ok=True)

    source_arg = Path(args.source).expanduser() if args.source else None
    sources = default_source_roots(source_arg)

    logger.log(APP_NAME)
    logger.log(f"Dry run: {dry_run}")
    logger.log(f"Source roots: {', '.join(str(s) for s in sources)}")
    logger.log(f"Destination: {dest}")
    logger.log(f"Max depth: {args.max_depth}; container depth: {args.container_depth}")

    scanner = SourceScanner(
        source_roots=sources,
        max_depth=args.max_depth,
        container_depth=args.container_depth,
        logger=logger,
    )
    items = scanner.scan()
    families = merge_family_keys(items, threshold=args.merge_threshold)

    logger.log(f"Project sources found: {len(items)}")
    logger.log(f"Project families found: {len(families)}")

    made: list[Path] = []
    consolidator = ProjectConsolidator(dest, dry_run=dry_run, logger=logger)

    if not args.diagnose_only:
        if families:
            made = consolidator.consolidate_all(families)
            logger.log(f"Consolidated folders created/planned: {len(made)}")
        else:
            logger.log("No project families found. Nothing to consolidate.")

    organizer = LooseFileOrganizer(desktop, dry_run=dry_run, logger=logger)
    if not args.diagnose_only and not args.no_organize:
        organizer.organize()
        logger.log(f"Loose desktop files moved/planned: {len(organizer.moves)}")

    timestamp = stamp()
    summary_csv = reports / f"project_consolidation_summary_{timestamp}.csv"
    diagnostics = reports / f"desktop_consolidator_diagnostics_{timestamp}.txt"
    manifest = reports / f"desktop_consolidator_manifest_{timestamp}.json"
    log_path = reports / f"desktop_consolidator_log_{timestamp}.txt"

    if not dry_run:
        write_summary_csv(summary_csv, families)
        payload = {
            "created_at": now_text(),
            "dry_run": dry_run,
            "source_roots": [str(s) for s in sources],
            "destination": str(dest),
            "project_sources_found": len(items),
            "project_families_found": len(families),
            "consolidated_folders": [str(p) for p in made],
            "loose_file_moves": organizer.moves,
            "leftovers": organizer.leftovers,
            "scanner_errors": scanner.errors,
            "skipped_containers": scanner.skipped_containers[:1000],
            "project_sources": [item.__dict__ for item in items],
            "families": [
                {
                    "key": family.key,
                    "display_name": family.display_name,
                    "current": family.current().path if family.current() else "",
                    "sources": [s.path for s in family.sources],
                }
                for family in families.values()
            ],
            "consolidation_manifests": consolidator.manifests,
        }
        manifest.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        diagnostics.write_text(build_diagnostics_text(payload), encoding="utf-8")
        logger.write(log_path)

    result = {
        "dry_run": dry_run,
        "reports_folder": str(reports),
        "destination": str(dest),
        "project_sources_found": len(items),
        "project_families_found": len(families),
        "consolidated_folders": len(made),
        "loose_files_moved": len(organizer.moves),
        "scanner_errors": len(scanner.errors),
        "manifest": str(manifest),
        "diagnostics": str(diagnostics),
        "log": str(log_path),
        "summary_csv": str(summary_csv),
    }

    print("\nFINAL RESULT")
    print(json.dumps(result, indent=2))

    if args.open_reports and not dry_run:
        open_folder(reports)

    return result


def build_diagnostics_text(payload: dict) -> str:
    lines = []
    lines.append("EVERGREEN DESKTOP CONSOLIDATOR DIAGNOSTICS")
    lines.append("")
    lines.append(f"Created: {payload.get('created_at')}")
    lines.append(f"Source roots: {', '.join(payload.get('source_roots', []))}")
    lines.append(f"Destination: {payload.get('destination')}")
    lines.append("")
    lines.append(f"Project sources found: {payload.get('project_sources_found')}")
    lines.append(f"Project families found: {payload.get('project_families_found')}")
    lines.append(f"Consolidated folders: {len(payload.get('consolidated_folders', []))}")
    lines.append(f"Loose file moves: {len(payload.get('loose_file_moves', []))}")
    lines.append(f"Scanner errors: {len(payload.get('scanner_errors', []))}")
    lines.append("")
    lines.append("PROJECT FAMILIES")
    for family in payload.get("families", []):
        lines.append(f"- {family.get('display_name')} :: current={family.get('current')}")
        for src in family.get("sources", []):
            lines.append(f"    source: {src}")
    lines.append("")
    lines.append("SCANNER ERRORS")
    for err in payload.get("scanner_errors", []):
        lines.append(f"- {err}")
    lines.append("")
    lines.append("SKIPPED / NOT PROJECT CONTAINERS")
    for item in payload.get("skipped_containers", [])[:500]:
        lines.append(f"- {item}")
    lines.append("")
    if payload.get("project_sources_found", 0) == 0:
        lines.append("WHY IT MAY HAVE LOOKED LIKE IT DID NOTHING")
        lines.append("- No .py/.pyw files were found in immediate project containers.")
        lines.append("- Your ZIPs/folders may be deeper than the current --container-depth setting.")
        lines.append("- They may be on Downloads, another drive, or inside a folder you need to pass with --source.")
        lines.append("- Run with: python evergreen_desktop_consolidator_v2.py --source \"FULL_PATH\" --container-depth 4 --max-depth 12")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=APP_NAME)
    parser.add_argument("--source", default="", help="Specific source folder. Default scans Desktop, organized zip folders, and Downloads.")
    parser.add_argument("--dest", default="", help="Destination root. Default: Desktop\\Consolidated_Python_Projects")
    parser.add_argument("--dry-run", action="store_true", help="Preview only. No copy/move/write except console output.")
    parser.add_argument("--diagnose-only", action="store_true", help="Scan/report only. Do not consolidate or organize.")
    parser.add_argument("--no-organize", action="store_true", help="Do not organize loose Desktop files.")
    parser.add_argument("--max-depth", type=int, default=8, help="Depth inside project folders to look for Python files.")
    parser.add_argument("--container-depth", type=int, default=2, help="Depth under Desktop/Downloads to find nested extracted project folders.")
    parser.add_argument("--merge-threshold", type=float, default=0.84, help="Similarity threshold for grouping project iterations.")
    parser.add_argument("--open-reports", action="store_true", default=True, help="Open reports folder at end.")
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()