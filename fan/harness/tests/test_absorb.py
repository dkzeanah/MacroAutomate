"""Tests for entity extraction, scaffolding, and project absorption.

The property under test: a project's capabilities become visible and runnable, and
absorbing it changes nothing on disk. The second half matters as much as the first --
integration you cannot reverse is not integration, it is commitment.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from atlas import absorb as absorbmod
from atlas import entities as entitiesmod
from atlas import scaffold
from atlas.store import Store

MULTI_TOOL = {
    "pyproject.toml": (
        "[project]\nname = \"demo\"\nversion = \"0.1.0\"\n\n"
        "[project.scripts]\ndemo-tool = \"demo.cli:main\"\n"
    ),
    "demo/__init__.py": '"""Demo package."""\n',
    "demo/cli.py": '''\
"""Demo command line."""

import argparse


def cmd_build(args):
    """Build the thing."""
    return 0


def build_parser():
    parser = argparse.ArgumentParser(prog="demo")
    sub = parser.add_subparsers(dest="command", required=True)
    build = sub.add_parser("build", help="build the thing")
    build.set_defaults(func=cmd_build)
    ship = sub.add_parser("ship", help="ship the thing somewhere")
    ship.set_defaults(func=cmd_build)
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    return int(args.func(args) or 0)


if __name__ == "__main__":
    raise SystemExit(main())
''',
    "demo/ui.py": '''\
"""Demo desktop window."""

import tkinter as tk


class Window(tk.Tk):
    """The main window."""

    def __init__(self):
        super().__init__()
        self.title("Demo")


def main():
    Window().mainloop()


if __name__ == "__main__":
    main()
''',
    "demo/api.py": '''\
"""Demo HTTP service."""

from fastapi import FastAPI

app = FastAPI()


@app.get("/")
def root():
    """Say hello."""
    return {"ok": True}
''',
    "demo/helpers.py": '''\
"""Plain helpers -- no entry point, so no runnable entity."""


def add(a, b):
    """Add two numbers."""
    return a + b
''',
    "run.bat": "@echo off\nREM Launch the demo tool on Windows.\npython -m demo.cli build\n",
    "skills/greet/SKILL.md": "---\nname: greet\ndescription: Greet a person warmly\n---\n",
}


@pytest.fixture()
def multi_tool(tmp_path: Path) -> Path:
    root = tmp_path / "demo_project"
    for relative, body in MULTI_TOOL.items():
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(body, encoding="utf-8")
    return root


@pytest.fixture()
def store(tmp_path: Path) -> Store:
    workspace = tmp_path / "ws"
    workspace.mkdir()
    store = Store(workspace)
    yield store
    store.close()


# ------------------------------------------------------------------- extraction

def test_extraction_finds_each_kind(multi_tool: Path) -> None:
    found = entitiesmod.extract(multi_tool, "demo", include_api=False)
    kinds = found.counts()
    assert kinds.get(entitiesmod.GUI) == 1, "the Tk window must register as a gui"
    assert kinds.get(entitiesmod.SERVICE) == 1, "the FastAPI app must register"
    assert kinds.get(entitiesmod.SCRIPT) == 1
    assert kinds.get(entitiesmod.SKILL) == 1
    assert kinds.get(entitiesmod.COMMAND) == 2, "both subparsers must be found"


def test_argparse_subcommands_keep_their_help(multi_tool: Path) -> None:
    found = entitiesmod.extract(multi_tool, "demo", include_api=False)
    commands = {e.name: e for e in found.by_kind(entitiesmod.COMMAND)}
    assert "cli build" in commands
    assert commands["cli build"].summary == "build the thing"
    assert commands["cli ship"].run_args == ["ship"]


def test_declared_console_script_is_found(multi_tool: Path) -> None:
    found = entitiesmod.extract(multi_tool, "demo", include_api=False)
    names = {e.name for e in found.by_kind(entitiesmod.CLI)}
    assert "demo-tool" in names, "[project.scripts] is the author's own tool list"


def test_plain_module_is_not_an_entry_point(multi_tool: Path) -> None:
    found = entitiesmod.extract(multi_tool, "demo", include_api=False)
    assert not [e for e in found.entities if e.path == "demo/helpers.py"], (
        "a module with no entry point must not be reported as runnable"
    )


def test_package_modules_run_with_dash_m(multi_tool: Path) -> None:
    found = entitiesmod.extract(multi_tool, "demo", include_api=False)
    gui = found.by_kind(entitiesmod.GUI)[0]
    assert gui.run_mode == entitiesmod.RUN_MODULE
    assert gui.run_target == "demo.ui"


def test_generated_output_is_not_scanned(tmp_path: Path) -> None:
    """Condensed and coagulated output are artifacts, not a project's tools."""
    root = tmp_path / "proj"
    (root / "condensed").mkdir(parents=True)
    (root / "condensed" / "functions.py").write_text(
        'import argparse\nif __name__ == "__main__":\n    pass\n', encoding="utf-8"
    )
    (root / "real.py").write_text(
        'import argparse\nif __name__ == "__main__":\n    pass\n', encoding="utf-8"
    )
    found = entitiesmod.extract(root, "proj", include_api=False)
    paths = {e.path for e in found.entities}
    assert "real.py" in paths
    assert not any(p.startswith("condensed/") for p in paths)


# ------------------------------------------------------------------ scaffolding

@pytest.mark.parametrize("template", list(scaffold.TEMPLATES))
def test_every_template_writes_and_parses(tmp_path: Path, template: str) -> None:
    import ast

    plan = scaffold.build(f"demo {template}", tmp_path / template, template=template)
    plan.write()
    for relative in plan.files:
        if relative.endswith(".py"):
            ast.parse((plan.root / relative).read_text(encoding="utf-8"))


@pytest.mark.parametrize(
    "template,kind",
    [("cli", entitiesmod.CLI), ("gui", entitiesmod.GUI),
     ("service", entitiesmod.SERVICE), ("script", entitiesmod.CLI)],
)
def test_scaffolds_are_detectable(tmp_path: Path, template: str, kind: str) -> None:
    """A scaffold that the entity extractor cannot read is a broken scaffold."""
    plan = scaffold.build(f"demo {template}", tmp_path / template, template=template)
    plan.write()
    found = entitiesmod.extract(plan.root, plan.name, include_api=False)
    assert found.by_kind(kind), f"{template} produced no {kind} entity"


def test_cli_scaffold_exposes_its_subcommands(tmp_path: Path) -> None:
    plan = scaffold.build("demo cli", tmp_path / "c", template="cli")
    plan.write()
    found = entitiesmod.extract(plan.root, plan.name, include_api=False)
    names = {e.name.split()[-1] for e in found.by_kind(entitiesmod.COMMAND)}
    assert {"run", "info"} <= names


def test_scaffold_refuses_to_clobber(tmp_path: Path) -> None:
    root = tmp_path / "occupied"
    root.mkdir()
    (root / "important.py").write_text("keep me\n", encoding="utf-8")
    plan = scaffold.build("demo", root, template="cli")
    report = plan.write()
    assert any("REFUSED" in line for line in report)
    assert (root / "important.py").read_text(encoding="utf-8") == "keep me\n"


def test_slug_handles_awkward_names() -> None:
    assert scaffold.slug("My Cool Tool!") == "my_cool_tool"
    assert scaffold.slug("2fast") == "p_2fast"
    assert scaffold.slug("class") == "class_"
    assert scaffold.slug("") == "project"


# -------------------------------------------------------------------- absorption

def test_absorb_registers_project_and_entities(store: Store, multi_tool: Path) -> None:
    report = absorbmod.absorb(store, multi_tool, name="demo")
    assert not report.errors or report.symbols > 0
    assert store.project_by_name("demo") is not None
    assert report.total_entities > 0
    assert report.runnable >= 3

    rows = store.entities()
    assert rows, "entities must be persisted, not only reported"
    assert {r["kind"] for r in rows} >= {
        entitiesmod.GUI, entitiesmod.SERVICE, entitiesmod.COMMAND
    }


def test_absorb_does_not_touch_the_source(store: Store, multi_tool: Path) -> None:
    before = {
        path: path.read_bytes()
        for path in multi_tool.rglob("*") if path.is_file()
    }
    absorbmod.absorb(store, multi_tool, name="demo")
    after = {
        path: path.read_bytes()
        for path in multi_tool.rglob("*") if path.is_file()
    }
    assert before == after, "absorption must be purely additive"


def test_dry_run_registers_nothing(store: Store, multi_tool: Path) -> None:
    report = absorbmod.absorb(store, multi_tool, name="demo", dry_run=True)
    assert report.total_entities > 0, "a preview must still say what it found"
    assert store.project_by_name("demo") is None
    assert store.entities() == []


def test_release_is_a_complete_undo(store: Store, multi_tool: Path) -> None:
    absorbmod.absorb(store, multi_tool, name="demo")
    assert store.entities()

    message = absorbmod.release(store, "demo")
    assert "Released" in message
    assert store.project_by_name("demo") is None
    assert store.entities() == []
    assert (multi_tool / "demo" / "cli.py").exists(), "files must survive release"


def test_reabsorb_preserves_run_history(store: Store, multi_tool: Path) -> None:
    """Usage counts are the most valuable thing in the registry; keep them."""
    absorbmod.absorb(store, multi_tool, name="demo")
    row = store.entities(runnable_only=True)[0]
    store.record_run(int(row["id"]))
    store.record_run(int(row["id"]))

    absorbmod.reabsorb(store, "demo")
    again = [
        r for r in store.entities()
        if r["kind"] == row["kind"] and r["name"] == row["name"]
    ]
    assert again and again[0]["runs"] == 2


def test_build_command_for_each_run_mode(store: Store, multi_tool: Path) -> None:
    absorbmod.absorb(store, multi_tool, name="demo")

    gui = next(r for r in store.entities(kind=entitiesmod.GUI))
    command, cwd = absorbmod.build_command(store, gui, "python")
    assert command[:2] == ["python", "-m"]
    assert Path(cwd) == multi_tool

    script = next(r for r in store.entities(kind=entitiesmod.SCRIPT))
    command, _cwd = absorbmod.build_command(store, script, "python")
    assert command[0] in {"cmd", "bash", "powershell"}


def test_api_entities_are_not_runnable(store: Store, multi_tool: Path) -> None:
    absorbmod.absorb(store, multi_tool, name="demo")
    api_rows = store.entities(kind=entitiesmod.API)
    for row in api_rows:
        with pytest.raises(ValueError):
            absorbmod.build_command(store, row, "python")


def test_absorbing_a_scaffold_round_trips(store: Store, tmp_path: Path) -> None:
    """Create then absorb: the loop a user actually runs."""
    plan = scaffold.build("round trip", tmp_path / "rt", template="cli",
                          bucket="codetool", summary="A tool for the round trip test.")
    plan.write()
    report = absorbmod.absorb(store, plan.root, name=plan.name, bucket="codetool")
    assert report.bucket == "codetool"
    assert report.runnable >= 1
    names = {r["name"] for r in store.entities()}
    assert any("run" in n for n in names)


def test_manifest_lists_what_was_registered(store: Store, multi_tool: Path) -> None:
    absorbmod.absorb(store, multi_tool, name="demo")
    manifest = absorbmod.capability_manifest(store)
    assert "CAPABILITY MANIFEST" in manifest
    assert "demo" in manifest
    assert "ship" in manifest or "build" in manifest


def test_absorb_rejects_a_non_directory(store: Store, tmp_path: Path) -> None:
    target = tmp_path / "a_file.py"
    target.write_text("x = 1\n", encoding="utf-8")
    report = absorbmod.absorb(store, target, name="nope")
    assert report.errors
    assert store.project_by_name("nope") is None
