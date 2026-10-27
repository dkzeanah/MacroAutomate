"""Create new code that is already in the right shape to be absorbed.

Scaffolding here is not about saving typing. It is about the generated project being
*legible to the rest of the system from the moment it exists*: a detectable entry
point, a docstring the entity extractor can read as a summary, a package layout that
makes `python -m` work, and a test file so the untested flag means something.

A project created here and immediately absorbed shows up with real entities. A project
thrown together by hand usually shows up as one anonymous script.
"""

from __future__ import annotations

import datetime as _dt
import keyword
import re
from dataclasses import dataclass, field
from pathlib import Path

TEMPLATES = ("cli", "gui", "library", "service", "script")

TEMPLATE_BLURB = {
    "cli": "argparse command line with subcommands -- each becomes an entity",
    "gui": "tabbed Tkinter application",
    "library": "importable package with a public surface",
    "service": "FastAPI server with one route",
    "script": "a single file that does one thing",
}


def slug(text: str) -> str:
    """A safe python identifier from free text."""
    cleaned = re.sub(r"[^0-9a-zA-Z_]+", "_", (text or "").strip()).strip("_").lower()
    cleaned = re.sub(r"_+", "_", cleaned) or "project"
    if cleaned[0].isdigit():
        cleaned = "p_" + cleaned
    if keyword.iskeyword(cleaned):
        cleaned += "_"
    return cleaned


def title_of(name: str) -> str:
    return " ".join(part.capitalize() for part in slug(name).split("_"))


@dataclass
class Scaffold:
    """A planned project: paths mapped to contents. Inspect before writing."""

    name: str
    package: str
    template: str
    bucket: str
    root: Path
    files: dict[str, str] = field(default_factory=dict)
    problems: list[str] = field(default_factory=list)

    @property
    def total_lines(self) -> int:
        return sum(len(body.splitlines()) for body in self.files.values())

    def render(self) -> str:
        out = [
            f"SCAFFOLD  {self.name}", "=" * 70,
            f"  template {self.template} -- {TEMPLATE_BLURB.get(self.template, '')}",
            f"  bucket   {self.bucket}",
            f"  package  {self.package}",
            f"  root     {self.root}",
            f"  files    {len(self.files)}, {self.total_lines} lines",
            "",
        ]
        for path in sorted(self.files):
            out.append(f"    {path:<44} {len(self.files[path].splitlines()):>4}L")
        if self.problems:
            out += ["", "PROBLEMS"] + [f"  ! {p}" for p in self.problems]
        return "\n".join(out)

    def write(self, overwrite: bool = False) -> list[str]:
        """Write the scaffold to disk, refusing to clobber anything."""
        report: list[str] = []
        if self.root.exists() and any(self.root.iterdir()) and not overwrite:
            return [f"REFUSED: {self.root} already exists and is not empty"]
        for relative, body in sorted(self.files.items()):
            target = self.root / relative
            if target.exists() and not overwrite:
                report.append(f"skipped (exists): {relative}")
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(body, encoding="utf-8")
            report.append(f"wrote: {relative}")
        return report


# ------------------------------------------------------------------- templates

def _pyproject(name: str, package: str, summary: str, template: str) -> str:
    scripts = ""
    if template in {"cli", "service"}:
        scripts = f'\n[project.scripts]\n{slug(name).replace("_", "-")} = "{package}.cli:main"\n'
    return f'''\
[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[project]
name = "{slug(name).replace("_", "-")}"
version = "0.1.0"
description = "{summary}"
requires-python = ">=3.10"
dependencies = []
{scripts}
[tool.setuptools.packages.find]
include = ["{package}*"]
'''


def _readme(name: str, summary: str, package: str, template: str, bucket: str) -> str:
    run = {
        "cli": f"python -m {package}.cli --help",
        "gui": f"python -m {package}.app",
        "service": f"python -m {package}.cli serve",
        "library": f"python -c \"import {package}; print({package}.__doc__)\"",
        "script": f"python {package}.py",
    }[template]
    return f'''# {title_of(name)}

{summary}

## Run

```bash
{run}
```

## Layout

This project is laid out so the harness can read it without being told anything:
the entry point is detectable, every public symbol has a docstring that becomes its
summary, and the package layout makes `python -m` work.

Absorb it with:

```bash
atlas absorb . --write
```

Bucket: `{bucket}`
'''


def _cli(package: str, summary: str) -> str:
    return f'''"""Command line for {package}.

Each subparser registered here becomes a separately addressable entity once this
project is absorbed, so the help text is the entity summary -- write it for a reader
who has never seen this project.
"""

from __future__ import annotations

import argparse
import sys

from .core import describe, process


def cmd_run(args: argparse.Namespace) -> int:
    """Process the input and print the result."""
    print(process(args.target, verbose=args.verbose))
    return 0


def cmd_info(args: argparse.Namespace) -> int:
    """Print what this tool is and what it can do."""
    print(describe())
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="{package}", description="{summary}")
    sub = parser.add_subparsers(dest="command", required=True)

    run = sub.add_parser("run", help="process a target and print the result")
    run.add_argument("target")
    run.add_argument("--verbose", action="store_true")
    run.set_defaults(func=cmd_run)

    info = sub.add_parser("info", help="what this tool is and what it can do")
    info.set_defaults(func=cmd_info)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return int(args.func(args) or 0)


if __name__ == "__main__":
    raise SystemExit(main())
'''


def _core(package: str, summary: str) -> str:
    return f'''"""The actual work for {package}.

Keep the logic here and the argument parsing in ``cli.py``. The split is what lets
the same function be an entity you can run and an API another project can import.
"""

from __future__ import annotations


def describe() -> str:
    """One paragraph on what this tool does, for humans and for the entity index."""
    return "{summary}"


def process(target: str, verbose: bool = False) -> str:
    """Do the thing this project exists to do.

    Replace this. The signature is deliberately small -- a function that takes one
    subject and returns one result is the easiest kind to reuse, and the easiest for
    the dedupe gate to recognise later.
    """
    result = target.strip()
    if verbose:
        return f"processed {{len(result)}} characters: {{result}}"
    return result
'''


def _gui(package: str, name: str, summary: str) -> str:
    return f'''"""{title_of(name)} -- a tabbed desktop application.

The notebook layout is here because a tool almost always grows a second thing it
needs to show, and retrofitting tabs later means rewriting the layout.
"""

from __future__ import annotations

import tkinter as tk
from tkinter import ttk

from .core import describe, process


class App(tk.Tk):
    """Main window."""

    def __init__(self) -> None:
        super().__init__()
        self.title("{title_of(name)}")
        self.geometry("1100x720")
        self.minsize(720, 480)

        self.notebook = ttk.Notebook(self)
        self.notebook.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)
        self._build_main()
        self._build_about()

        self.status = tk.StringVar(value="Ready")
        ttk.Label(self, textvariable=self.status, padding=(8, 3)).pack(
            side=tk.BOTTOM, fill=tk.X
        )
        self.bind("<F11>", lambda e: self.attributes(
            "-fullscreen", not self.attributes("-fullscreen")
        ))

    def _build_main(self) -> None:
        page = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(page, text="Main")

        bar = ttk.Frame(page)
        bar.pack(fill=tk.X)
        ttk.Label(bar, text="Input").pack(side=tk.LEFT)
        self.entry = ttk.Entry(bar)
        self.entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=8)
        ttk.Button(bar, text="Run", command=self._run).pack(side=tk.LEFT)

        self.output = tk.Text(page, wrap=tk.WORD, font=("Consolas", 10))
        self.output.pack(fill=tk.BOTH, expand=True, pady=(10, 0))

    def _build_about(self) -> None:
        page = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(page, text="About")
        text = tk.Text(page, wrap=tk.WORD, font=("Consolas", 10))
        text.pack(fill=tk.BOTH, expand=True)
        text.insert("1.0", describe())

    def _run(self) -> None:
        value = self.entry.get().strip()
        if not value:
            self.status.set("Type something first")
            return
        self.output.insert(tk.END, process(value, verbose=True) + "\\n")
        self.output.see(tk.END)
        self.status.set("Done")


def main() -> int:
    App().mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'''


def _service(package: str, summary: str) -> str:
    return f'''"""HTTP service for {package}.

Routes are entities too: absorbing this project registers the server, and the
decorators below are what identifies it as one.
"""

from __future__ import annotations

from fastapi import FastAPI

from .core import describe, process

app = FastAPI(title="{package}", description="{summary}")


@app.get("/")
def root() -> dict:
    """What this service is."""
    return {{"service": "{package}", "description": describe()}}


@app.get("/process/{{target}}")
def process_target(target: str) -> dict:
    """Run the core operation on one target."""
    return {{"target": target, "result": process(target)}}
'''


def _service_cli(package: str) -> str:
    return f'''"""Command line for the {package} service."""

from __future__ import annotations

import argparse


def cmd_serve(args: argparse.Namespace) -> int:
    """Start the HTTP server."""
    import uvicorn

    uvicorn.run(f"{package}.service:app", host=args.host, port=args.port, reload=args.reload)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="{package}")
    sub = parser.add_subparsers(dest="command", required=True)
    serve = sub.add_parser("serve", help="start the HTTP server")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8000)
    serve.add_argument("--reload", action="store_true")
    serve.set_defaults(func=cmd_serve)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return int(args.func(args) or 0)


if __name__ == "__main__":
    raise SystemExit(main())
'''


def _test(package: str, template: str) -> str:
    target = "process" if template != "library" else "process"
    return f'''"""Tests for {package}.

A test file exists from the start so the index's "untested" flag means something:
an unflagged symbol is genuinely covered, rather than the whole project being
uniformly unmarked.
"""

from __future__ import annotations

from {package}.core import describe, {target}


def test_describe_is_not_empty() -> None:
    assert describe().strip()


def test_process_round_trips() -> None:
    assert {target}("hello") == "hello"


def test_process_verbose_mentions_the_input() -> None:
    assert "hello" in {target}("hello", verbose=True)
'''


def _script(name: str, summary: str) -> str:
    return f'''"""{summary}

A single file, because not everything needs a package. It still has a __main__ guard
and a docstring, which is all the entity extractor needs to register it as a tool.
"""

from __future__ import annotations

import argparse


def run(target: str) -> str:
    """Do the one thing this script exists for."""
    return target.strip()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="{summary}")
    parser.add_argument("target")
    args = parser.parse_args(argv)
    print(run(args.target))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'''


# ---------------------------------------------------------------------- builder

def build(
    name: str,
    root: Path,
    template: str = "cli",
    bucket: str = "misc",
    summary: str = "",
) -> Scaffold:
    """Plan a new project. Nothing is written until ``Scaffold.write`` is called."""
    package = slug(name)
    summary = summary.strip() or f"{title_of(name)} -- describe what this does."
    plan = Scaffold(
        name=name, package=package, template=template, bucket=bucket,
        root=Path(root),
    )
    if template not in TEMPLATES:
        plan.problems.append(f"unknown template {template!r}; using 'cli'")
        template = "cli"
        plan.template = template

    stamp = _dt.datetime.now().strftime("%Y-%m-%d")
    plan.files[".gitignore"] = "__pycache__/\n*.pyc\n.venv/\n.atlas/\ndist/\nbuild/\n"
    plan.files["README.md"] = _readme(name, summary, package, template, bucket)

    if template == "script":
        plan.files[f"{package}.py"] = _script(name, summary)
        return plan

    plan.files["pyproject.toml"] = _pyproject(name, package, summary, template)
    plan.files[f"{package}/__init__.py"] = (
        f'"""{title_of(name)}.\n\n{summary}\n\nCreated {stamp}.\n"""\n\n'
        f'__version__ = "0.1.0"\n'
    )
    plan.files[f"{package}/core.py"] = _core(package, summary)
    plan.files[f"tests/test_{package}.py"] = _test(package, template)

    if template == "cli":
        plan.files[f"{package}/cli.py"] = _cli(package, summary)
    elif template == "gui":
        plan.files[f"{package}/app.py"] = _gui(package, name, summary)
        plan.files[f"{package}/__main__.py"] = (
            f"from .app import main\n\nraise SystemExit(main())\n"
        )
    elif template == "service":
        plan.files[f"{package}/service.py"] = _service(package, summary)
        plan.files[f"{package}/cli.py"] = _service_cli(package)

    return plan


# ------------------------------------------------------------------ symbol stubs

def symbol_stub(name: str, intent: str, kind: str = "function", lines: int = 12) -> str:
    """A ready-to-fill stub for one new symbol, shaped the way the gate expects."""
    intent = intent.strip() or "Describe what this does."
    if kind == "class":
        return (
            f"class {name}:\n"
            f'    """{intent}"""\n\n'
            f"    def __init__(self) -> None:\n"
            f"        raise NotImplementedError\n"
        )
    return (
        f"def {slug(name)}(value):\n"
        f'    """{intent}"""\n'
        f"    raise NotImplementedError\n"
    )


def insert_symbol(path: Path, line: int, code: str) -> str:
    """Insert ``code`` at ``line`` (1-indexed), keeping blank-line separation."""
    path = Path(path)
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    index = max(0, min(len(lines), line - 1))
    block = ["", ""] + code.rstrip().splitlines() + [""]
    lines[index:index] = block
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return f"inserted {len(code.splitlines())} lines at {path}:{line}"
