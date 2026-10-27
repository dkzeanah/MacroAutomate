"""Harness tab -- launch everything that used to be a separate script or shortcut.

SideLearner, Creator Ops, OJAS, the code analyzer and the Ollama pre-prompt tools all
start from here, with their output captured in the pane rather than lost to a console
window that closes.
"""

from __future__ import annotations

import os
import subprocess
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk

from studio.widgets import (
    MONO, UI, UI_BOLD, Field, SortableTable, TextPane, button, separator, toolbar,
)


class Launcher:
    """One runnable thing, described well enough to explain itself in the table."""

    def __init__(self, key: str, name: str, group: str, target: str,
                 args: list[str] | None = None, gui: bool = False,
                 blurb: str = "") -> None:
        self.key = key
        self.name = name
        self.group = group
        self.target = target
        self.args = args or []
        self.gui = gui
        self.blurb = blurb

    def resolve(self, workspace: Path) -> Path:
        return (workspace / self.target).resolve()

    def available(self, workspace: Path) -> bool:
        return self.resolve(workspace).exists()


LAUNCHERS = [
    Launcher("sl_cli", "SideLearner -- help", "SideLearner", "sidelearner/cli.py",
             ["--help"], blurb="The agent harness CLI: run, watch, memory, skills."),
    Launcher("sl_demo", "SideLearner -- demo", "SideLearner", "sidelearner/demo.py",
             blurb="Scripted walkthrough of the loop, memory and tools."),
    Launcher("sl_web", "SideLearner -- web UI", "SideLearner",
             "sidelearner/web/__main__.py", gui=True,
             blurb="FastAPI server with the live session view."),
    Launcher("creator_gui", "Creator Ops -- GUI", "Creator Ops", "creator_ops_gui.pyw",
             gui=True, blurb="Dashboard, content studio, queue, metrics."),
    Launcher("creator_worker", "Creator Ops -- worker", "Creator Ops",
             "creator_ops_worker.py",
             blurb="Headless processor for the scheduled queue."),
    Launcher("creator_cli", "Creator Ops -- CLI", "Creator Ops", "creator_ops.py",
             ["--help"], blurb="Same engine, scriptable."),
    Launcher("ojas", "OJAS -- Job Automation Studio", "OJAS",
             "Ollama_Job_Automation_Studio_v1.2/main.py", gui=True,
             blurb="Resume/ATS scoring, job pipeline, RAG, visual synthesis."),
    Launcher("ojas_test", "OJAS -- self test", "OJAS",
             "Ollama_Job_Automation_Studio_v1.2/self_test.py",
             blurb="Checks the OJAS install without opening the GUI."),
    Launcher("analyzer", "Code Analyzer Manager", "Legacy tools",
             "legacy/code_analyzer/app.py", gui=True,
             blurb="The original AST analyzer this system grew out of."),
    Launcher("preprompt", "Ollama Pre-prompt -- GUI", "Legacy tools",
             "legacy/ollama_preprompt/ollama_preprompt_gui.pyw", gui=True,
             blurb="Prompt staging and pre-context builder for local models."),
    Launcher("preprompt_cli", "Ollama Pre-prompt -- CLI", "Legacy tools",
             "legacy/ollama_preprompt/ollama_preprompt.py", ["--help"],
             blurb="Scriptable version of the same tool."),
]

ATLAS_COMMANDS = [
    ("atlas buckets", ["-m", "atlas.cli", "buckets"],
     "The twenty buckets and what is in them"),
    ("atlas projects", ["-m", "atlas.cli", "projects"],
     "Every indexed project with its counts"),
    ("atlas budget", ["-m", "atlas.cli", "budget"],
     "What each tier costs in tokens, versus reading the sources"),
    ("atlas preamble", ["-m", "atlas.cli", "preamble"],
     "A system-prompt block to paste into any third-party model"),
    ("atlas ledger", ["-m", "atlas.cli", "ledger"],
     "Recent history"),
    ("atlas attic", ["-m", "atlas.cli", "attic"],
     "Retired code that was kept"),
]


class HarnessTab:
    def __init__(self, parent: ttk.Frame, context) -> None:
        self.ctx = context
        self.store = context.store
        self.workspace = context.workspace
        self._processes: list[subprocess.Popen] = []

        bar = toolbar(parent)
        button(bar, "Launch selected", self._launch)
        button(bar, "Launch detached", lambda: self._launch(detached=True))
        separator(bar)
        button(bar, "Stop running", self._stop_all)
        button(bar, "Clear output", lambda: self.output.clear())
        separator(bar)
        self.python_field = Field(bar, "Interpreter", sys.executable, width=48)
        self.python_field.pack(side=tk.LEFT)

        panes = ttk.PanedWindow(parent, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

        left = ttk.PanedWindow(panes, orient=tk.VERTICAL)

        # -- entities: everything absorbed from the user's own projects ----------
        entity_pane = ttk.Frame(left)
        entity_head = ttk.Frame(entity_pane)
        entity_head.pack(fill=tk.X)
        ttk.Label(entity_head, text="YOUR TOOLS", font=UI_BOLD).pack(
            side=tk.LEFT, pady=(0, 3))
        self.entity_count = tk.StringVar(value="")
        ttk.Label(entity_head, textvariable=self.entity_count, font=UI,
                  foreground="#666666").pack(side=tk.RIGHT)
        self.entity_filter = Field(entity_head, "filter", width=18)
        self.entity_filter.pack(side=tk.RIGHT, padx=(0, 10))
        self.entity_filter.var.trace_add("write", lambda *_: self._refresh_entities())

        self.entities = SortableTable(
            entity_pane,
            ["kind", "name", "project", "runs", "summary"],
            ["kind", "name", "project", "used", "what it is"],
            [66, 190, 140, 40, 240],
            ["w", "w", "w", "e", "w"],
            on_select=self._entity_selected,
            on_activate=lambda r: self._launch_entity(),
            height=12,
        )
        self.entities.pack(fill=tk.BOTH, expand=True)
        entity_bar = ttk.Frame(entity_pane)
        entity_bar.pack(fill=tk.X, pady=(4, 0))
        button(entity_bar, "Launch", self._launch_entity)
        button(entity_bar, "Pin / unpin", self._toggle_entity_pin)
        self.runnable_only = tk.BooleanVar(value=True)
        ttk.Checkbutton(entity_bar, text="runnable only",
                        variable=self.runnable_only,
                        command=self._refresh_entities).pack(side=tk.LEFT, padx=8)
        ttk.Label(entity_bar,
                  text="Absorb a project in the Create tab to add tools here.",
                  font=UI, foreground="#777777").pack(side=tk.LEFT, padx=8)
        left.add(entity_pane, weight=3)

        top = ttk.Frame(left)
        ttk.Label(top, text="BUILT-IN LAUNCHERS", font=UI_BOLD).pack(
            anchor="w", pady=(4, 3))
        self.table = SortableTable(
            top,
            ["available", "name", "group", "target"],
            ["", "what", "group", "file"],
            [26, 230, 100, 250],
            ["c", "w", "w", "w"],
            on_select=self._selected,
            on_activate=lambda r: self._launch(),
            height=10,
        )
        self.table.pack(fill=tk.BOTH, expand=True)
        left.add(top, weight=2)

        bottom = ttk.Frame(left)
        ttk.Label(bottom, text="ATLAS COMMANDS", font=UI_BOLD).pack(anchor="w", pady=(4, 3))
        self.commands = SortableTable(
            bottom,
            ["command", "blurb"],
            ["command", "what it prints"],
            [150, 400],
            ["w", "w"],
            on_activate=lambda r: self._run_atlas(r["command"]),
            height=8,
        )
        self.commands.pack(fill=tk.BOTH, expand=True)
        self.commands.set_rows([
            {"command": name, "blurb": blurb} for name, _args, blurb in ATLAS_COMMANDS
        ])
        button(bottom, "Run selected command",
               lambda: self._run_atlas_selected(), side=tk.TOP)
        left.add(bottom, weight=2)
        panes.add(left, weight=3)

        right = ttk.Frame(panes)
        head = ttk.Frame(right)
        head.pack(fill=tk.X)
        ttk.Label(head, text="OUTPUT", font=UI_BOLD).pack(side=tk.LEFT, pady=(0, 3))
        self.running_var = tk.StringVar(value="")
        ttk.Label(head, textvariable=self.running_var, font=("Consolas", 9),
                  foreground="#0a7d28").pack(side=tk.RIGHT)
        self.output = TextPane(right, font=MONO, height=34)
        self.output.pack(fill=tk.BOTH, expand=True)
        self.output.set(_PRIMER)
        panes.add(right, weight=4)

        self.ctx.job.on("proc_line", self._append_line)
        self.ctx.job.on("proc_done", self._process_done)

    # ---------------------------------------------------------------- entities
    def _refresh_entities(self) -> None:
        try:
            rows = self.store.entities(
                runnable_only=self.runnable_only.get(),
                query=self.entity_filter.get(),
            )
        except Exception as exc:
            self.entity_count.set(f"error: {exc}")
            return
        self._entity_rows = {}
        table_rows = []
        for row in rows:
            key = f"{row['kind']}|{row['name']}|{row['project']}"
            self._entity_rows[key] = row
            tags = ()
            if row["pinned"]:
                tags = ("hot",)
            elif row["run_mode"] == "import":
                tags = ("dim",)
            table_rows.append({
                "kind": row["kind"],
                "name": ("* " if row["pinned"] else "") + row["name"],
                "project": row["project"],
                "runs": row["runs"] or "",
                "summary": row["summary"] or "",
                "_tags": tags,
            })
        self.entities.set_rows(table_rows)
        runnable = sum(1 for r in rows if r["run_mode"] != "import")
        self.entity_count.set(f"{len(rows)} entities, {runnable} runnable")

    def _selected_entity(self):
        row = self.entities.selected()
        if not row:
            return None
        key = f"{row['kind']}|{row['name'].lstrip('* ')}|{row['project']}"
        return getattr(self, "_entity_rows", {}).get(key)

    def _entity_selected(self, _row: dict) -> None:
        entity = self._selected_entity()
        if entity is None:
            return
        args = [a for a in (entity["run_args"] or "").split("\x1f") if a]
        lines = [
            f"{entity['name']}   [{entity['kind']}]",
            "=" * 66,
            f"project   {entity['project']}",
            f"file      {entity['path'] or '-'}"
            + (f":{entity['line']}" if entity["line"] else ""),
            f"root      {entity['root']}",
            f"run mode  {entity['run_mode']}",
            f"target    {entity['run_target']}",
            f"args      {' '.join(args) or '(none)'}",
            f"evidence  {entity['evidence'] or '-'}",
            f"used      {entity['runs']} time(s)"
            + (f", last {entity['last_run']}" if entity["last_run"] else ""),
            "",
            entity["summary"] or "(no description)",
            "",
        ]
        if entity["run_mode"] == "import":
            lines.append(
                "This is a callable API, not a program. Fetch it with:\n"
                f"    atlas get {entity['run_target']}"
            )
        else:
            lines.append("Press Launch, or double-click, to run it.")
        self.output.set("\n".join(lines))

    def _launch_entity(self) -> None:
        entity = self._selected_entity()
        if entity is None:
            messagebox.showinfo("Launch", "Select one of your tools first.")
            return
        from atlas import absorb as absorbmod

        interpreter = self.python_field.get() or sys.executable
        try:
            command, cwd = absorbmod.build_command(self.store, entity, interpreter)
        except ValueError as exc:
            messagebox.showinfo("Not runnable", str(exc))
            return
        if not Path(cwd).exists():
            messagebox.showerror("Launch", f"{cwd} no longer exists.")
            return

        self.store.record_run(int(entity["id"]))
        self._refresh_entities()

        if entity["kind"] in {"gui", "service", "notebook"}:
            try:
                subprocess.Popen(command, cwd=str(cwd))
            except OSError as exc:
                messagebox.showerror("Launch", str(exc))
                return
            self.output.append(
                f"\n>>> launched detached: {' '.join(command)}\n", "good"
            )
            self.ctx.status(f"Launched {entity['name']}", "good")
            return

        self.output.set(f">>> {' '.join(command)}\n    (cwd: {cwd})\n\n")
        self._spawn(command, cwd=Path(cwd), label=entity["name"])

    def _toggle_entity_pin(self) -> None:
        entity = self._selected_entity()
        if entity is None:
            return
        self.store.toggle_entity_pin(int(entity["id"]))
        self._refresh_entities()
        self.ctx.status(f"Toggled pin on {entity['name']}", "good")

    # ----------------------------------------------------------------- refresh
    def on_refresh(self) -> None:
        self._refresh_entities()
        rows = []
        for launcher in LAUNCHERS:
            ok = launcher.available(self.workspace)
            rows.append({
                "available": "ok" if ok else "--",
                "name": launcher.name,
                "group": launcher.group,
                "target": launcher.target,
                "_tags": () if ok else ("dim",),
            })
        self.table.set_rows(rows)

    on_show = on_refresh

    def _selected(self, row: dict) -> None:
        launcher = next((x for x in LAUNCHERS if x.name == row["name"]), None)
        if launcher is None:
            return
        path = launcher.resolve(self.workspace)
        self.output.set(
            f"{launcher.name}\n{'=' * 62}\n"
            f"group   {launcher.group}\n"
            f"file    {path}\n"
            f"exists  {'yes' if path.exists() else 'NO -- not present in this workspace'}\n"
            f"mode    {'windowed app (launch detached)' if launcher.gui else 'console'}\n"
            f"args    {' '.join(launcher.args) or '(none)'}\n\n"
            f"{launcher.blurb}\n"
        )

    # ------------------------------------------------------------------ launch
    def _launch(self, detached: bool = False) -> None:
        row = self.table.selected()
        if not row:
            messagebox.showinfo("Launch", "Select something to launch.")
            return
        launcher = next((x for x in LAUNCHERS if x.name == row["name"]), None)
        if launcher is None:
            return
        path = launcher.resolve(self.workspace)
        if not path.exists():
            messagebox.showerror("Launch", f"{path} does not exist in this workspace.")
            return

        interpreter = self.python_field.get() or sys.executable
        command = [interpreter, str(path), *launcher.args]

        if detached or launcher.gui:
            try:
                creation = 0
                if sys.platform == "win32":
                    creation = subprocess.CREATE_NEW_CONSOLE if not launcher.gui else 0
                subprocess.Popen(command, cwd=str(self.workspace),
                                 creationflags=creation)
            except OSError as exc:
                messagebox.showerror("Launch", str(exc))
                return
            self.output.append(f"\n>>> launched detached: {' '.join(command)}\n", "good")
            self.ctx.status(f"Launched {launcher.name}", "good")
            return

        self.output.set(f">>> {' '.join(command)}\n\n")
        self._spawn(command, cwd=self.workspace, label=launcher.name)

    def _run_atlas_selected(self) -> None:
        row = self.commands.selected()
        if row:
            self._run_atlas(row["command"])

    def _run_atlas(self, name: str) -> None:
        entry = next((c for c in ATLAS_COMMANDS if c[0] == name), None)
        if entry is None:
            return
        # `--workspace` is a top-level flag, so it goes between `-m atlas.cli` and
        # the subcommand rather than at the end.
        interpreter = self.python_field.get() or sys.executable
        module_args = entry[1][:2]          # ["-m", "atlas.cli"]
        subcommand = entry[1][2:]           # ["buckets"], ["projects"], ...
        command = [interpreter, *module_args, "--workspace", str(self.workspace),
                   *subcommand]
        self.output.set(f">>> {name}\n\n")
        self._spawn(command, cwd=self.workspace, label=name)

    def _spawn(self, command: list[str], cwd: Path, label: str) -> None:
        env = dict(os.environ)
        env["PYTHONPATH"] = str(self.workspace) + os.pathsep + env.get("PYTHONPATH", "")
        env["PYTHONUNBUFFERED"] = "1"
        try:
            process = subprocess.Popen(
                command, cwd=str(cwd), stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True, bufsize=1, env=env,
                creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0,
            )
        except OSError as exc:
            self.output.append(f"\n!! {exc}\n", "bad")
            return

        self._processes.append(process)
        self._update_running()
        self.ctx.status(f"Running {label} ...", "busy")

        def pump() -> None:
            assert process.stdout is not None
            for line in process.stdout:
                self.ctx.job.post("proc_line", line)
            process.wait()
            self.ctx.job.post("proc_done", (label, process.returncode, process))

        threading.Thread(target=pump, daemon=True).start()

    def _append_line(self, line: str) -> None:
        self.output.append(line)

    def _process_done(self, payload) -> None:
        label, code, process = payload
        if process in self._processes:
            self._processes.remove(process)
        self._update_running()
        self.output.append(f"\n<<< {label} exited with {code}\n",
                           "good" if code == 0 else "bad")
        self.ctx.status(f"{label} exited with {code}",
                        "good" if code == 0 else "warn")

    def _update_running(self) -> None:
        live = [p for p in self._processes if p.poll() is None]
        self._processes = live
        self.running_var.set(f"{len(live)} running" if live else "")

    def _stop_all(self) -> None:
        live = [p for p in self._processes if p.poll() is None]
        if not live:
            self.ctx.status("Nothing running", "info")
            return
        if not messagebox.askyesno("Stop", f"Terminate {len(live)} running process(es)?"):
            return
        for process in live:
            try:
                process.terminate()
            except OSError:
                pass
        self.output.append(f"\n!! terminated {len(live)} process(es)\n", "warn")
        self._update_running()


_PRIMER = """HARNESS

Everything that used to be its own script or desktop shortcut starts from here.

  SideLearner    the agent harness: perception watchers, memory graph, digital twin,
                 pre-LLM router, tool registry, skills engine
  Creator Ops    content pipeline: briefs, drafts, review, queue, metrics
  OJAS           job automation studio: resume/ATS scoring, RAG, visual synthesis
  Legacy tools   the code analyzer this system grew out of, and the Ollama
                 pre-prompt builders

Console programs stream their output into this pane. Windowed apps open in their own
window -- use Launch detached for those, or just double-click.

The Atlas commands below print the map itself: the buckets, the projects, the token
budget, and the system-prompt block you paste into a third-party model.
"""
