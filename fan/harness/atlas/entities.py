"""Entities: the runnable, callable things a project contains.

A project folder is opaque. You cannot tell from the outside whether it holds one
script or fourteen tools, which of them are entry points, or what any of them do.
That opacity is what makes a desktop full of projects unusable -- and it is why
"absorbing" a large project has to mean more than copying it somewhere.

This module reads a project and extracts the things you can actually *do* with it:

    cli       a command-line entry point
    command   one subcommand inside a CLI
    gui       a windowed application
    service   a server that listens on a port
    script    a .bat / .ps1 / .sh launcher
    api       a public class or function worth calling from code
    skill     a declarative SKILL.md capability
    notebook  a Jupyter notebook

Each becomes an addressable entity in the harness. The project stays exactly where it
is; entities point into it. Nothing is moved, copied or rewritten.
"""

from __future__ import annotations

import ast
import json
import re
from dataclasses import dataclass, field
from pathlib import Path

from .spec import SKIP_DIR_NAMES

# Atlas's own generated output is not a project's source. Scanning it yields phantom
# tools -- a condensed `functions.py` looks like a CLI, and a class pulled into
# `classes.py` from some web project looks like a live server.
GENERATED_DIRS = {"condensed", "coagulated", ".atlas", ".coagulate", "projects"}

SKIP_DIRS = SKIP_DIR_NAMES | GENERATED_DIRS


def _skipped(path: Path, root: Path) -> bool:
    try:
        parts = path.relative_to(root).parts
    except ValueError:
        parts = path.parts
    return any(part in SKIP_DIRS for part in parts)

# --- entity kinds -----------------------------------------------------------------
CLI = "cli"
COMMAND = "command"
GUI = "gui"
SERVICE = "service"
SCRIPT = "script"
API = "api"
SKILL = "skill"
NOTEBOOK = "notebook"

KIND_ORDER = [GUI, CLI, COMMAND, SERVICE, SCRIPT, SKILL, NOTEBOOK, API]

KIND_BLURB = {
    CLI: "command-line entry point",
    COMMAND: "subcommand of a CLI",
    GUI: "windowed application",
    SERVICE: "server that listens on a port",
    SCRIPT: "shell or batch launcher",
    API: "public class or function callable from code",
    SKILL: "declarative capability",
    NOTEBOOK: "Jupyter notebook",
}

# How an entity is started.
RUN_PYTHON = "python"        # python <file> [args]
RUN_MODULE = "module"        # python -m <module> [args]
RUN_SHELL = "shell"          # the OS runs it
RUN_IMPORT = "import"        # not runnable; import and call it
RUN_NOTEBOOK = "notebook"


@dataclass
class Entity:
    """One thing a project lets you do."""

    name: str
    kind: str
    project: str = ""
    path: str = ""                 # project-relative file
    symbol: str = ""               # the function/class behind it, when there is one
    summary: str = ""
    run_mode: str = RUN_IMPORT
    run_target: str = ""           # file path or module name
    run_args: list[str] = field(default_factory=list)
    evidence: list[str] = field(default_factory=list)
    line: int = 0
    confidence: float = 0.5

    @property
    def key(self) -> str:
        return f"{self.project}:{self.kind}:{self.name}"

    @property
    def runnable(self) -> bool:
        return self.run_mode != RUN_IMPORT

    def describe(self) -> str:
        where = f"{self.path}:{self.line}" if self.line else self.path
        return f"[{self.kind}] {self.name}  ({where})" + (
            f"  -- {self.summary}" if self.summary else ""
        )


@dataclass
class Extraction:
    """Everything found in one project."""

    project: str
    root: Path
    entities: list[Entity] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)

    def by_kind(self, kind: str) -> list[Entity]:
        return [e for e in self.entities if e.kind == kind]

    @property
    def runnable(self) -> list[Entity]:
        return [e for e in self.entities if e.runnable]

    def counts(self) -> dict[str, int]:
        out: dict[str, int] = {}
        for entity in self.entities:
            out[entity.kind] = out.get(entity.kind, 0) + 1
        return out

    def render(self, limit: int = 40) -> str:
        counts = self.counts()
        out = [
            f"ENTITIES IN {self.project}", "=" * 74,
            f"  {len(self.entities)} entities, {len(self.runnable)} runnable", "",
        ]
        for kind in KIND_ORDER:
            members = self.by_kind(kind)
            if not members:
                continue
            out.append(f"  {kind:<9} {len(members):>3}   {KIND_BLURB[kind]}")
        out.append("")
        for kind in KIND_ORDER:
            members = self.by_kind(kind)
            if not members:
                continue
            out.append(f"--- {kind.upper()} ---")
            for entity in members[:limit]:
                out.append("  " + entity.describe())
            if len(members) > limit:
                out.append(f"  ... and {len(members) - limit} more")
            out.append("")
        if self.problems:
            out += ["PROBLEMS"] + [f"  ! {p}" for p in self.problems[:12]]
        return "\n".join(out)


# ------------------------------------------------------------------ AST detection

_GUI_MARKERS = {
    "Tk", "Toplevel", "QApplication", "QMainWindow", "Gtk", "wx.App",
    "customtkinter", "mainloop", "QWidget",
}
_SERVICE_MARKERS = {"FastAPI", "Flask", "Starlette", "Sanic", "Quart", "Bottle"}
_SERVE_CALLS = {"run", "serve", "run_app"}


def _docline(node: ast.AST) -> str:
    try:
        doc = ast.get_docstring(node)  # type: ignore[arg-type]
    except TypeError:
        return ""
    return doc.strip().splitlines()[0].strip()[:160] if doc else ""


def _const_str(node: ast.AST | None) -> str:
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    return ""


def _call_name(node: ast.Call) -> str:
    func = node.func
    if isinstance(func, ast.Name):
        return func.id
    if isinstance(func, ast.Attribute):
        return func.attr
    return ""


def _module_name(rel: str) -> str:
    stem = rel[:-3] if rel.endswith(".py") else rel
    stem = stem[:-4] if stem.endswith(".pyw") else stem
    parts = [p for p in stem.replace("\\", "/").split("/") if p]
    if parts and parts[-1] == "__main__":
        parts = parts[:-1]
    return ".".join(parts)


def _is_package(root: Path, rel: str) -> bool:
    """True when the file sits inside a package, so `python -m` will work."""
    parent = (root / rel).parent
    return (parent / "__init__.py").exists()


class _EntityVisitor(ast.NodeVisitor):
    """Collect the signals that distinguish a tool from a plain module."""

    def __init__(self) -> None:
        self.has_main_guard = False
        self.gui_hits: list[str] = []
        self.service_hits: list[str] = []
        self.argparse_commands: list[tuple[str, str, int]] = []
        self.click_commands: list[tuple[str, str, int]] = []
        self.has_argparse = False
        self.port: str = ""

    def visit_If(self, node: ast.If) -> None:
        test = node.test
        if (
            isinstance(test, ast.Compare)
            and isinstance(test.left, ast.Name)
            and test.left.id == "__name__"
            and any(_const_str(c) == "__main__" for c in test.comparators)
        ):
            self.has_main_guard = True
        self.generic_visit(node)

    def visit_Call(self, node: ast.Call) -> None:
        name = _call_name(node)

        if name in _GUI_MARKERS:
            self.gui_hits.append(name)
        if name in _SERVICE_MARKERS:
            self.service_hits.append(name)
        if name == "ArgumentParser":
            self.has_argparse = True

        # argparse subcommands: sub.add_parser("name", help="...")
        if name == "add_parser" and node.args:
            command = _const_str(node.args[0])
            if command:
                help_text = next(
                    (_const_str(k.value) for k in node.keywords if k.arg == "help"), ""
                )
                self.argparse_commands.append((command, help_text, node.lineno))

        # uvicorn.run(..., port=8000) / app.run(port=5000)
        if name in _SERVE_CALLS:
            for keyword in node.keywords:
                if keyword.arg == "port":
                    self.port = (
                        str(keyword.value.value)
                        if isinstance(keyword.value, ast.Constant) else "?"
                    )
        self.generic_visit(node)

    def _decorators(self, node) -> None:
        for decorator in node.decorator_list:
            target = decorator.func if isinstance(decorator, ast.Call) else decorator
            label = ""
            if isinstance(target, ast.Attribute):
                label = target.attr
            elif isinstance(target, ast.Name):
                label = target.id
            if label in {"command", "group"}:
                name = node.name.replace("_", "-")
                if isinstance(decorator, ast.Call) and decorator.args:
                    name = _const_str(decorator.args[0]) or name
                self.click_commands.append((name, _docline(node), node.lineno))
            elif label in {"get", "post", "put", "delete", "patch", "route"}:
                self.service_hits.append(label)

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self._decorators(node)
        self.generic_visit(node)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self._decorators(node)
        self.generic_visit(node)


def _scan_python(root: Path, rel: str, project: str, out: Extraction) -> None:
    path = root / rel
    try:
        source = path.read_text(encoding="utf-8", errors="replace")
        tree = ast.parse(source)
    except (OSError, SyntaxError) as exc:
        out.problems.append(f"{rel}: {exc}")
        return

    visitor = _EntityVisitor()
    visitor.visit(tree)
    doc = _docline(tree)
    stem = Path(rel).stem
    module = _module_name(rel)
    use_module = _is_package(root, rel) and module

    run_mode = RUN_MODULE if use_module else RUN_PYTHON
    run_target = module if use_module else rel

    # GUI beats CLI: a Tk app launched from a terminal is still a GUI.
    if visitor.gui_hits and (visitor.has_main_guard or rel.endswith(".pyw")):
        out.entities.append(Entity(
            name=stem, kind=GUI, project=project, path=rel,
            summary=doc or "windowed application",
            run_mode=run_mode, run_target=run_target,
            evidence=sorted(set(visitor.gui_hits))[:4],
            confidence=0.9,
        ))
    elif visitor.service_hits:
        port = f" on port {visitor.port}" if visitor.port else ""
        out.entities.append(Entity(
            name=stem, kind=SERVICE, project=project, path=rel,
            summary=(doc or "server") + port,
            run_mode=run_mode, run_target=run_target,
            evidence=sorted(set(visitor.service_hits))[:4],
            confidence=0.85,
        ))
    elif visitor.has_main_guard or visitor.has_argparse:
        out.entities.append(Entity(
            name=stem, kind=CLI, project=project, path=rel,
            summary=doc or "command-line entry point",
            run_mode=run_mode, run_target=run_target,
            run_args=["--help"] if visitor.has_argparse else [],
            evidence=(["argparse"] if visitor.has_argparse else [])
                     + (["__main__ guard"] if visitor.has_main_guard else []),
            confidence=0.8 if visitor.has_argparse else 0.6,
        ))

    for command, help_text, line in visitor.argparse_commands:
        out.entities.append(Entity(
            name=f"{stem} {command}", kind=COMMAND, project=project, path=rel,
            summary=help_text, line=line,
            run_mode=run_mode, run_target=run_target, run_args=[command],
            evidence=["argparse subparser"], confidence=0.95,
        ))
    for command, help_text, line in visitor.click_commands:
        out.entities.append(Entity(
            name=f"{stem} {command}", kind=COMMAND, project=project, path=rel,
            summary=help_text, line=line,
            run_mode=run_mode, run_target=run_target, run_args=[command],
            evidence=["click/typer decorator"], confidence=0.9,
        ))


# --------------------------------------------------------------- declared scripts

def _scan_manifests(root: Path, project: str, out: Extraction) -> None:
    """console_scripts and [project.scripts] are the author's own list of tools."""
    pyproject = root / "pyproject.toml"
    if pyproject.exists():
        try:
            text = pyproject.read_text(encoding="utf-8", errors="replace")
        except OSError:
            text = ""
        block = re.search(r"\[project\.scripts\](.*?)(\n\[|\Z)", text, re.S)
        if block:
            for line in block.group(1).splitlines():
                match = re.match(r'\s*([\w.-]+)\s*=\s*["\']([^"\']+)["\']', line)
                if match:
                    name, target = match.groups()
                    module = target.split(":")[0]
                    out.entities.append(Entity(
                        name=name, kind=CLI, project=project, path="pyproject.toml",
                        summary=f"declared console script -> {target}",
                        run_mode=RUN_MODULE, run_target=module,
                        evidence=["[project.scripts]"], confidence=1.0,
                    ))

    setup = root / "setup.py"
    if setup.exists():
        try:
            text = setup.read_text(encoding="utf-8", errors="replace")
        except OSError:
            text = ""
        for match in re.finditer(r'["\']([\w.-]+)\s*=\s*([\w.]+):(\w+)["\']', text):
            name, module, _func = match.groups()
            out.entities.append(Entity(
                name=name, kind=CLI, project=project, path="setup.py",
                summary=f"declared console script -> {module}",
                run_mode=RUN_MODULE, run_target=module,
                evidence=["console_scripts"], confidence=0.95,
            ))


def _scan_scripts(root: Path, project: str, out: Extraction) -> None:
    """Shell launchers are first-class: they are what the author actually double-clicks."""
    from .scanner import iter_source_files
    for path, _rel in iter_source_files(root, suffixes={".bat", ".cmd", ".ps1", ".sh"}, skip_dirs=SKIP_DIRS):
        if path.suffix.lower() not in {".bat", ".cmd", ".ps1", ".sh"}:
            continue
        if _skipped(path, root):
            continue
        rel = path.relative_to(root).as_posix()
        summary = ""
        try:
            for line in path.read_text(encoding="utf-8", errors="replace").splitlines()[:12]:
                stripped = line.strip().lstrip("@").strip()
                for prefix in ("REM ", "rem ", ":: ", "# "):
                    if stripped.startswith(prefix):
                        candidate = stripped[len(prefix):].strip()
                        if len(candidate) > 12 and not candidate.startswith("="):
                            summary = candidate[:160]
                            break
                if summary:
                    break
        except OSError:
            pass
        out.entities.append(Entity(
            name=path.stem, kind=SCRIPT, project=project, path=rel,
            summary=summary or f"{path.suffix.lstrip('.')} launcher",
            run_mode=RUN_SHELL, run_target=rel,
            evidence=[path.suffix], confidence=0.9,
        ))


def _scan_skills(root: Path, project: str, out: Extraction) -> None:
    from .scanner import iter_source_files
    for path, _rel in iter_source_files(root, suffixes={".md"}, skip_dirs=SKIP_DIRS):
        if path.name != "SKILL.md":
            continue
        if _skipped(path, root):
            continue
        rel = path.relative_to(root).as_posix()
        summary = ""
        try:
            for line in path.read_text(encoding="utf-8", errors="replace").splitlines()[:20]:
                if line.lower().startswith("description:"):
                    summary = line.split(":", 1)[1].strip()[:160]
                    break
                if line.startswith("# "):
                    summary = line[2:].strip()[:160]
        except OSError:
            pass
        out.entities.append(Entity(
            name=path.parent.name, kind=SKILL, project=project, path=rel,
            summary=summary or "declarative capability",
            run_mode=RUN_IMPORT, run_target=rel,
            evidence=["SKILL.md"], confidence=1.0,
        ))


def _scan_notebooks(root: Path, project: str, out: Extraction) -> None:
    from .scanner import iter_source_files
    for path, _rel in iter_source_files(root, suffixes={".ipynb"}, skip_dirs=SKIP_DIRS):
        if _skipped(path, root):
            continue
        rel = path.relative_to(root).as_posix()
        summary = ""
        try:
            data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
            for cell in data.get("cells", [])[:3]:
                if cell.get("cell_type") == "markdown":
                    text = "".join(cell.get("source", [])).strip()
                    if text:
                        summary = text.splitlines()[0].lstrip("# ").strip()[:160]
                        break
        except (OSError, ValueError):
            pass
        out.entities.append(Entity(
            name=path.stem, kind=NOTEBOOK, project=project, path=rel,
            summary=summary or "notebook", run_mode=RUN_NOTEBOOK, run_target=rel,
            evidence=[".ipynb"], confidence=1.0,
        ))


# ----------------------------------------------------------------- public surface

def _scan_api(store, project_name: str, out: Extraction, limit: int = 40) -> None:
    """The most depended-upon public symbols -- a project's callable surface.

    Ranked by incoming edges, because the thing twelve other symbols call is the thing
    worth knowing about, and a flat list of every public function is not a capability
    list.
    """
    project = store.project_by_name(project_name)
    if project is None:
        return
    rows = store.many(
        "SELECT * FROM symbols WHERE project_id = ? AND kind IN ('C', 'F') "
        "AND flags NOT LIKE '%X%'",
        (project.id,),
    )
    scored = []
    for row in rows:
        callers = len([c for c in (row["called_by"] or "").split(",") if c])
        size = int(row["line_end"]) - int(row["line_start"]) + 1
        if callers == 0 and size < 12:
            continue
        scored.append((callers * 3 + min(size, 120) / 40, row))
    scored.sort(key=lambda pair: pair[0], reverse=True)

    for _score, row in scored[:limit]:
        out.entities.append(Entity(
            name=row["name"], kind=API, project=project_name, path=row["path"],
            symbol=row["name"], summary=row["doc"] or row["signature"][:140],
            line=int(row["line_start"]), run_mode=RUN_IMPORT,
            run_target=row["address"],
            evidence=[f"{len([c for c in (row['called_by'] or '').split(',') if c])} callers"],
            confidence=0.7,
        ))


# ------------------------------------------------------------------- the entry point

def extract(
    root: Path,
    project: str | None = None,
    store=None,
    include_api: bool = True,
    max_files: int = 3000,
) -> Extraction:
    """Find every runnable and callable thing in a project."""
    root = Path(root)
    name = project or root.name
    out = Extraction(project=name, root=root)
    out.problems.append(f"Discovery bounds: {max_files} Python files; 5000 directories / 100000 entries per source or asset walk. Linked directories and bundled compiler runtimes are skipped.")

    count = 0
    from .scanner import iter_source_files
    for path, _rel in iter_source_files(root, max_files=max_files + 1, skip_dirs=SKIP_DIRS):
        if count >= max_files:
            out.problems.append(f"stopped after {max_files} files")
            break
        if _skipped(path, root):
            continue
        count += 1
        _scan_python(root, path.relative_to(root).as_posix(), name, out)

    _scan_manifests(root, name, out)
    _scan_scripts(root, name, out)
    _scan_skills(root, name, out)
    _scan_notebooks(root, name, out)
    if include_api and store is not None:
        _scan_api(store, name, out)

    # A declared console script and the module behind it are the same tool.
    seen: dict[tuple[str, str], Entity] = {}
    deduped: list[Entity] = []
    for entity in sorted(out.entities, key=lambda e: -e.confidence):
        key = (entity.kind, entity.name.lower())
        if key in seen:
            seen[key].evidence = sorted(set(seen[key].evidence + entity.evidence))
            continue
        seen[key] = entity
        deduped.append(entity)
    out.entities = sorted(
        deduped, key=lambda e: (KIND_ORDER.index(e.kind), -e.confidence, e.name)
    )
    return out
