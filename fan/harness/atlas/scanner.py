"""Turn Python source into Symbol records: span, hash, signature, and call edges.

The scanner never keeps a file body in memory longer than one file. What it emits is
the whole point of Atlas -- a record small enough that thousands of them fit in the
context a single source file would have consumed.
"""

from __future__ import annotations

import ast
import hashlib
from dataclasses import dataclass, field
from pathlib import Path

from .spec import (
    KIND_ASYNC,
    KIND_CLASS,
    KIND_CONST,
    KIND_FUNC,
    KIND_PRIVATE,
    MAX_SOURCE_BYTES,
    SKIP_DIR_NAMES,
    SOURCE_SUFFIXES,
)


@dataclass
class Symbol:
    """One indexed symbol. This is the atom of the whole system."""

    name: str              # dotted within its file: "ReasonLoop.step"
    kind: str              # spec.KIND_*
    path: str              # posix-style path relative to the project root
    line_start: int        # 1-indexed, inclusive
    line_end: int          # 1-indexed, inclusive
    signature: str
    body_hash: str         # 4 hex chars
    doc: str = ""          # first line of the docstring, if any
    calls: list[str] = field(default_factory=list)      # unresolved callee names
    called_by: list[str] = field(default_factory=list)  # filled in by graph.py
    decorators: list[str] = field(default_factory=list)
    bases: list[str] = field(default_factory=list)
    flags: str = ""

    @property
    def lines(self) -> int:
        return self.line_end - self.line_start + 1

    @property
    def leaf(self) -> str:
        return self.name.rsplit(".", 1)[-1]

    @property
    def owner(self) -> str | None:
        return self.name.rsplit(".", 1)[0] if "." in self.name else None


@dataclass
class FileScan:
    """Everything learned from one source file."""

    path: str
    line_count: int
    file_hash: str
    symbols: list[Symbol] = field(default_factory=list)
    imports: list[str] = field(default_factory=list)
    error: str = ""


# --------------------------------------------------------------------------- utils

def _hash(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8", "ignore")).hexdigest()[:4]


def _unparse(node: ast.AST | None) -> str:
    if node is None:
        return ""
    try:
        return ast.unparse(node)
    except Exception:
        return "?"


def _signature(node: ast.FunctionDef | ast.AsyncFunctionDef, qualname: str) -> str:
    args = node.args
    parts: list[str] = []

    positional = list(args.posonlyargs) + list(args.args)
    defaults = list(args.defaults)
    pad = len(positional) - len(defaults)

    for i, arg in enumerate(positional):
        text = arg.arg
        if arg.annotation is not None:
            text += ": " + _unparse(arg.annotation)
        if i >= pad:
            text += "=" + _unparse(defaults[i - pad])
        parts.append(text)
        if args.posonlyargs and i == len(args.posonlyargs) - 1:
            parts.append("/")

    if args.vararg:
        text = "*" + args.vararg.arg
        if args.vararg.annotation is not None:
            text += ": " + _unparse(args.vararg.annotation)
        parts.append(text)
    elif args.kwonlyargs:
        parts.append("*")

    for arg, default in zip(args.kwonlyargs, args.kw_defaults):
        text = arg.arg
        if arg.annotation is not None:
            text += ": " + _unparse(arg.annotation)
        if default is not None:
            text += "=" + _unparse(default)
        parts.append(text)

    if args.kwarg:
        text = "**" + args.kwarg.arg
        if args.kwarg.annotation is not None:
            text += ": " + _unparse(args.kwarg.annotation)
        parts.append(text)

    rendered = f"{qualname}({', '.join(parts)})"
    if node.returns is not None:
        rendered += " -> " + _unparse(node.returns)
    return rendered


def _docline(node: ast.AST) -> str:
    try:
        doc = ast.get_docstring(node)  # type: ignore[arg-type]
    except TypeError:
        return ""
    if not doc:
        return ""
    first = doc.strip().splitlines()[0].strip()
    return first[:120]


def _callee_name(node: ast.Call) -> str | None:
    """Best-effort readable name for a call target."""
    func = node.func
    if isinstance(func, ast.Name):
        return func.id
    if isinstance(func, ast.Attribute):
        chain: list[str] = [func.attr]
        current: ast.AST = func.value
        while isinstance(current, ast.Attribute):
            chain.append(current.attr)
            current = current.value
        if isinstance(current, ast.Name):
            chain.append(current.id)
        return ".".join(reversed(chain))
    return None


# ------------------------------------------------------------------------- visitor

class _Collector(ast.NodeVisitor):
    def __init__(self, path: str, source_lines: list[str]) -> None:
        self.path = path
        self.lines = source_lines
        self.symbols: list[Symbol] = []
        self.imports: list[str] = []
        self._scope: list[str] = []

    # -- helpers
    def _qual(self, name: str) -> str:
        return ".".join(self._scope + [name])

    def _span(self, node: ast.AST) -> tuple[int, int]:
        start = getattr(node, "lineno", 1)
        for dec in getattr(node, "decorator_list", []) or []:
            start = min(start, getattr(dec, "lineno", start))
        end = getattr(node, "end_lineno", start) or start
        return start, end

    def _body_text(self, start: int, end: int) -> str:
        return "\n".join(self.lines[start - 1 : end])

    def _collect_calls(self, node: ast.AST) -> list[str]:
        found: list[str] = []
        for child in ast.walk(node):
            if isinstance(child, ast.Call):
                name = _callee_name(child)
                if name and name not in found:
                    found.append(name)
        return found

    # -- visits
    def visit_Import(self, node: ast.Import) -> None:
        for alias in node.names:
            self.imports.append(alias.name)

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:
        module = node.module or ""
        prefix = "." * (node.level or 0)
        for alias in node.names:
            self.imports.append(f"{prefix}{module}.{alias.name}".strip("."))

    def visit_ClassDef(self, node: ast.ClassDef) -> None:
        start, end = self._span(node)
        qual = self._qual(node.name)
        bases = [_unparse(b) for b in node.bases]
        sig = qual + (f"({', '.join(bases)})" if bases else "")
        self.symbols.append(
            Symbol(
                name=qual,
                kind=KIND_CLASS,
                path=self.path,
                line_start=start,
                line_end=end,
                signature=sig,
                body_hash=_hash(self._body_text(start, end)),
                doc=_docline(node),
                calls=[],
                decorators=[_unparse(d) for d in node.decorator_list],
                bases=bases,
            )
        )
        self._scope.append(node.name)
        for child in node.body:
            self.visit(child)
        self._scope.pop()

    def _visit_function(self, node, is_async: bool) -> None:
        start, end = self._span(node)
        qual = self._qual(node.name)
        if is_async:
            kind = KIND_ASYNC
        elif node.name.startswith("_"):
            kind = KIND_PRIVATE
        else:
            kind = KIND_FUNC
        self.symbols.append(
            Symbol(
                name=qual,
                kind=kind,
                path=self.path,
                line_start=start,
                line_end=end,
                signature=_signature(node, qual),
                body_hash=_hash(self._body_text(start, end)),
                doc=_docline(node),
                calls=self._collect_calls(node),
                decorators=[_unparse(d) for d in node.decorator_list],
            )
        )
        # Nested defs are indexed too -- they are still addressable code.
        self._scope.append(node.name)
        for child in node.body:
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                self.visit(child)
        self._scope.pop()

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self._visit_function(node, is_async=False)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self._visit_function(node, is_async=True)

    def visit_Assign(self, node: ast.Assign) -> None:
        # Module-level SHOUTING_CONSTANTS are part of the public surface.
        if self._scope:
            return
        for target in node.targets:
            if isinstance(target, ast.Name) and target.id.isupper() and len(target.id) > 2:
                start, end = self._span(node)
                self.symbols.append(
                    Symbol(
                        name=target.id,
                        kind=KIND_CONST,
                        path=self.path,
                        line_start=start,
                        line_end=end,
                        signature=f"{target.id} = {_unparse(node.value)[:60]}",
                        body_hash=_hash(self._body_text(start, end)),
                    )
                )


# ---------------------------------------------------------------------- public API

def scan_source(path: Path, rel: str) -> FileScan:
    """Scan one Python file. Never raises -- syntax errors land in ``FileScan.error``."""
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        return FileScan(rel, 0, "", error=f"unreadable: {exc}")

    lines = raw.splitlines()
    scan = FileScan(path=rel, line_count=len(lines), file_hash=_hash(raw))

    try:
        tree = ast.parse(raw, filename=str(path))
    except SyntaxError as exc:
        scan.error = f"syntax error line {exc.lineno}: {exc.msg}"
        return scan

    collector = _Collector(rel, lines)
    collector.visit(tree)
    scan.symbols = collector.symbols
    scan.imports = collector.imports
    return scan


def iter_source_files(
    root: Path, max_files: int = 5000, exclude: set[str] | None = None,
    suffixes: set[str] | None = None, skip_dirs: set[str] | None = None,
    max_dirs: int = 5000,
):
    """Yield (absolute_path, posix_relative_path) for indexable sources under root.

    ``exclude`` holds root-relative posix directory paths to skip -- used when a
    subtree is indexed as its own project and must not be counted twice.
    """
    excluded = {e.strip("/") for e in (exclude or set())}
    count = 0
    visited: set[str] = set()
    inspected = 0
    stack = [root]
    while stack:
        current = stack.pop()
        canonical = str(current.resolve()).casefold()
        if canonical in visited:
            continue
        if len(visited) >= max_dirs or inspected >= 100000:
            return
        visited.add(canonical)
        try:
            entries = sorted(current.iterdir(), key=lambda p: p.name)
        except OSError:
            continue
        for entry in entries:
            inspected += 1
            if inspected > 100000:
                return
            if count >= max_files:
                return
            try:
                if entry.is_dir():
                    if entry.is_symlink() or getattr(entry.lstat(), "st_file_attributes", 0) & 0x400:
                        continue
                    if entry.name in (skip_dirs if skip_dirs is not None else SKIP_DIR_NAMES):
                        continue
                    if entry.name.lower().startswith(("winlibs-", "mingw")):
                        continue
                    if entry.name.startswith(".") and entry.name not in {".dsh"}:
                        continue
                    if excluded and entry.relative_to(root).as_posix() in excluded:
                        continue
                    stack.append(entry)
                    continue
                if entry.suffix.lower() not in (suffixes if suffixes is not None else SOURCE_SUFFIXES):
                    continue
                if entry.stat().st_size > MAX_SOURCE_BYTES:
                    continue
            except OSError:
                continue
            count += 1
            yield entry, entry.relative_to(root).as_posix()


def scan_project(
    root: Path, max_files: int = 5000, exclude: set[str] | None = None
) -> list[FileScan]:
    """Scan every indexable source file under ``root``."""
    return [
        scan_source(path, rel)
        for path, rel in iter_source_files(root, max_files, exclude)
    ]
