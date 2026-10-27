"""The inverse of condense: explode one blob into a real project tree.

Two inputs are handled, because they are the two shapes code actually arrives in:

* a **mass document** -- one chat transcript or markdown file with many fenced code
  blocks, most of them carrying a filename hint somewhere nearby;
* a **ZIP** -- the thing you download from a chat assistant and would otherwise unpack
  into yet another desktop folder.

Both come out the same way: files placed at real paths, with a plan you can inspect
before anything is written.
"""

from __future__ import annotations

import ast
import re
import shutil
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

from .spec import SKIP_DIR_NAMES

# ```python title="a/b.py"  |  ```py a/b.py  |  ``` a/b.py
_FENCE = re.compile(
    r"^```+[ \t]*(?P<lang>[A-Za-z0-9_+-]*)[ \t]*(?P<meta>[^\n]*)$", re.MULTILINE
)
# "# file: a/b.py", "# a/b.py", "// path/to/x.js" as the first line inside a block
_PATH_COMMENT = re.compile(
    r"^\s*(?:#|//|/\*|<!--)\s*(?:file|filename|path)?\s*:?\s*"
    r"(?P<path>[\w./\\-]+\.[A-Za-z0-9]{1,6})\s*(?:\*/|-->)?\s*$"
)
# A markdown heading or bold line naming a file, just above a fence
_PATH_NEARBY = re.compile(r"[`*\"']?(?P<path>[\w./-]+\.[A-Za-z0-9]{1,6})[`*\"']?")

LANG_SUFFIX = {
    "python": ".py", "py": ".py", "python3": ".py",
    "javascript": ".js", "js": ".js", "typescript": ".ts", "ts": ".ts",
    "json": ".json", "yaml": ".yml", "yml": ".yml", "toml": ".toml",
    "bash": ".sh", "sh": ".sh", "shell": ".sh",
    "powershell": ".ps1", "ps1": ".ps1", "bat": ".bat", "batch": ".bat",
    "html": ".html", "css": ".css", "sql": ".sql", "markdown": ".md", "md": ".md",
    "ini": ".ini", "text": ".txt", "": ".txt",
}


@dataclass
class Piece:
    """One extracted file, before it is written anywhere."""

    path: str
    content: str
    language: str = ""
    confidence: float = 0.5
    origin: str = ""
    note: str = ""

    @property
    def lines(self) -> int:
        return len(self.content.splitlines())

    @property
    def valid_python(self) -> bool | None:
        if not self.path.endswith((".py", ".pyw")):
            return None
        try:
            ast.parse(self.content)
        except SyntaxError:
            return False
        return True


@dataclass
class FanoutPlan:
    """What would be written, and where. Inspect before committing."""

    pieces: list[Piece] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    destination: Path | None = None

    @property
    def total_lines(self) -> int:
        return sum(p.lines for p in self.pieces)

    def render(self) -> str:
        out = [f"FAN-OUT PLAN -- {len(self.pieces)} files, {self.total_lines} lines"]
        if self.destination:
            out.append(f"destination: {self.destination}")
        out.append("")
        for piece in sorted(self.pieces, key=lambda p: p.path):
            ok = piece.valid_python
            mark = {True: "ok ", False: "BAD", None: "   "}[ok]
            out.append(
                f"  [{mark}] {piece.path:<48} {piece.lines:>5}L  "
                f"conf {piece.confidence:.2f}  {piece.note}"
            )
        if self.warnings:
            out.append("")
            out.append("WARNINGS")
            out.extend(f"  ! {w}" for w in self.warnings)
        return "\n".join(out)


# ------------------------------------------------------------------ mass documents

def _guess_path(meta: str, body: str, lang: str, preceding: str, counter: int) -> tuple[str, float, str]:
    """Work out where a fenced block belongs. Returns (path, confidence, note)."""
    # 1. Explicit metadata on the fence line.
    for pattern in (r'title=["\']([^"\']+)["\']', r'name=["\']([^"\']+)["\']'):
        match = re.search(pattern, meta)
        if match:
            return match.group(1).strip(), 0.95, "fence title"
    bare = meta.strip().strip("`\"'")
    if bare and "." in bare and "/" not in bare[:1] and len(bare) < 120 and " " not in bare:
        return bare, 0.9, "fence meta"

    # 2. A path comment on the first line of the body.
    first = body.splitlines()[0] if body.splitlines() else ""
    match = _PATH_COMMENT.match(first)
    if match:
        return match.group("path").replace("\\", "/"), 0.9, "path comment"

    # 3. A filename mentioned in the two lines above the fence.
    tail = [ln for ln in preceding.strip().splitlines()[-3:] if ln.strip()]
    for line in reversed(tail):
        match = _PATH_NEARBY.search(line)
        if match:
            candidate = match.group("path")
            if candidate.count(".") >= 1 and not candidate.startswith("."):
                return candidate.replace("\\", "/"), 0.7, "named above block"

    # 4. Fall back to the language, and name it by any module-level class it defines.
    suffix = LANG_SUFFIX.get(lang.lower(), ".txt")
    stem = f"block_{counter:02d}"
    if suffix == ".py":
        try:
            tree = ast.parse(body)
            for node in tree.body:
                if isinstance(node, ast.ClassDef):
                    stem = _snake(node.name)
                    break
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    stem = node.name.lstrip("_") or stem
                    break
        except SyntaxError:
            pass
    return f"{stem}{suffix}", 0.35, "inferred"


def _snake(name: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


def parse_document(text: str, default_dir: str = "") -> FanoutPlan:
    """Extract every fenced code block from a mass document into placed pieces."""
    plan = FanoutPlan()
    positions = list(_FENCE.finditer(text))
    counter = 0
    i = 0

    while i < len(positions) - 1:
        opening = positions[i]
        closing = positions[i + 1]
        lang = opening.group("lang") or ""
        meta = opening.group("meta") or ""
        body = text[opening.end() : closing.start()].strip("\n")
        preceding = text[max(0, opening.start() - 400) : opening.start()]

        if body.strip():
            counter += 1
            path, confidence, note = _guess_path(meta, body, lang, preceding, counter)
            if default_dir and not path.startswith(default_dir):
                path = f"{default_dir.rstrip('/')}/{path}"
            plan.pieces.append(
                Piece(
                    path=path.lstrip("/"),
                    content=body + "\n",
                    language=lang,
                    confidence=confidence,
                    origin="document",
                    note=note,
                )
            )
        i += 2

    # Same path twice means a later revision of an earlier block: keep both, disambiguate.
    seen: dict[str, int] = {}
    for piece in plan.pieces:
        if piece.path in seen:
            seen[piece.path] += 1
            stem, dot, suffix = piece.path.rpartition(".")
            piece.path = f"{stem}.v{seen[piece.path]}{dot}{suffix}"
            piece.note += " (repeat path -- kept as revision)"
            plan.warnings.append(f"duplicate path kept as {piece.path}")
        else:
            seen[piece.path] = 1

    for piece in plan.pieces:
        if piece.valid_python is False:
            plan.warnings.append(f"{piece.path} is not valid Python -- review before running")

    if not plan.pieces:
        plan.warnings.append("no fenced code blocks found in the document")
    return plan


# ---------------------------------------------------------------------------- zips

def parse_zip(archive: Path, strip_top_level: bool = True) -> FanoutPlan:
    """Read a ZIP into a plan without extracting it anywhere yet."""
    plan = FanoutPlan()
    archive = Path(archive)
    try:
        with zipfile.ZipFile(archive) as zf:
            names = [n for n in zf.namelist() if not n.endswith("/")]
            prefix = _common_prefix(names) if strip_top_level else ""
            for name in names:
                parts = Path(name).parts
                if any(part in SKIP_DIR_NAMES for part in parts):
                    continue
                # Refuse anything that would escape the destination.
                if ".." in parts or Path(name).is_absolute():
                    plan.warnings.append(f"refused unsafe path in archive: {name}")
                    continue
                rel = name[len(prefix):] if prefix and name.startswith(prefix) else name
                rel = rel.lstrip("/")
                if not rel:
                    continue
                try:
                    raw = zf.read(name)
                except (KeyError, OSError) as exc:
                    plan.warnings.append(f"{name}: {exc}")
                    continue
                try:
                    content = raw.decode("utf-8")
                except UnicodeDecodeError:
                    plan.warnings.append(f"{rel}: binary, copied verbatim")
                    content = ""
                plan.pieces.append(
                    Piece(
                        path=rel,
                        content=content,
                        language=Path(rel).suffix.lstrip("."),
                        confidence=1.0,
                        origin=str(archive),
                        note="from archive",
                    )
                )
    except (zipfile.BadZipFile, OSError) as exc:
        plan.warnings.append(f"cannot read archive: {exc}")
    return plan


def _common_prefix(names: list[str]) -> str:
    """The single top-level folder a ZIP wraps everything in, if there is exactly one."""
    tops = {n.split("/", 1)[0] for n in names if "/" in n}
    if len(tops) == 1 and all("/" in n for n in names):
        return next(iter(tops)) + "/"
    return ""


# --------------------------------------------------------------------------- commit

def commit(
    plan: FanoutPlan,
    destination: Path,
    archive: Path | None = None,
    overwrite: bool = False,
) -> list[str]:
    """Write a plan to disk. Existing files are backed up beside themselves, never lost."""
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    plan.destination = destination
    report: list[str] = []

    for piece in plan.pieces:
        target = (destination / piece.path).resolve()
        try:
            target.relative_to(destination.resolve())
        except ValueError:
            report.append(f"REFUSED (escapes destination): {piece.path}")
            continue

        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists() and not overwrite:
            backup = target.with_suffix(target.suffix + ".prior")
            counter = 1
            while backup.exists():
                backup = target.with_suffix(f"{target.suffix}.prior{counter}")
                counter += 1
            shutil.copy2(target, backup)
            report.append(f"kept prior: {backup.name}")

        if piece.content:
            target.write_text(piece.content, encoding="utf-8")
        elif archive is not None:
            with zipfile.ZipFile(archive) as zf:
                candidates = [n for n in zf.namelist() if n.endswith(piece.path)]
                if candidates:
                    target.write_bytes(zf.read(candidates[0]))
        report.append(f"wrote: {piece.path} ({piece.lines}L)")

    return report
