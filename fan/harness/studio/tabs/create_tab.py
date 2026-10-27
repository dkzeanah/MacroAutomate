"""Create tab -- the front door for adding anything to the universe.

Four ways in, deliberately separated because they have different risks:

    New project    scaffold something shaped to be absorbed from the start
    New symbol     add one function or class, placed by the engine, not by you
    Add code       paste a block or a file and have it placed
    Absorb         take an existing project whole, by reference, reversibly

Everything previews before it writes, and everything that writes says exactly what
it did.
"""

from __future__ import annotations

import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from atlas import absorb as absorbmod
from atlas import fanout as fanoutmod
from atlas import rules, scaffold
from atlas.buckets import bucket_titles
from studio.widgets import (
    MONO, UI, UI_BOLD, Field, SortableTable, TextPane, button, separator, toolbar,
)

BUCKET_KEYS = [key for key, _t, _b in bucket_titles()]


class CreateTab:
    def __init__(self, parent: ttk.Frame, context) -> None:
        self.ctx = context
        self.store = context.store
        self._scaffold = None
        self._absorb_report = None
        self._placement = None

        self.book = ttk.Notebook(parent)
        self.book.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)
        self._build_project()
        self._build_symbol()
        self._build_code()
        self._build_absorb()

        self.ctx.job.on("scaffold_done", self._scaffold_done)
        self.ctx.job.on("absorb_done", self._absorb_done)
        self.ctx.job.on("create_error", self._error)

    # ------------------------------------------------------------- new project
    def _build_project(self) -> None:
        page = ttk.Frame(self.book)
        self.book.add(page, text="New project")

        bar = toolbar(page)
        button(bar, "Preview", self._preview_project)
        button(bar, "Create", lambda: self._create_project(False))
        button(bar, "Create + absorb", lambda: self._create_project(True))

        panes = ttk.PanedWindow(page, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True, pady=(6, 0))

        left = ttk.Frame(panes, padding=(0, 0, 8, 0))
        ttk.Label(left, text="NEW PROJECT", font=UI_BOLD).pack(anchor="w", pady=(0, 8))
        self.p_name = Field(left, "Name          ", width=32)
        self.p_name.pack(anchor="w", pady=2)
        self.p_template = Field(left, "Template      ", "cli", width=14,
                                values=list(scaffold.TEMPLATES))
        self.p_template.pack(anchor="w", pady=2)
        self.p_template.widget.bind("<<ComboboxSelected>>",
                                    lambda e: self._template_hint())
        self.p_bucket = Field(left, "Bucket        ", "codetool", width=16,
                              values=BUCKET_KEYS)
        self.p_bucket.pack(anchor="w", pady=2)
        self.p_where = Field(left, "Create in     ",
                             str(self.ctx.workspace / "projects"), width=40)
        self.p_where.pack(anchor="w", fill=tk.X, pady=2)
        button(left, "Browse", self._choose_project_dir, side=tk.TOP)

        ttk.Label(left, text="What is it for? (becomes the docstring and the summary)",
                  font=UI).pack(anchor="w", pady=(10, 3))
        self.p_summary = TextPane(left, font=MONO, wrap=tk.WORD, height=4)
        self.p_summary.pack(fill=tk.X)

        self.p_hint = tk.StringVar(value=scaffold.TEMPLATE_BLURB["cli"])
        ttk.Label(left, textvariable=self.p_hint, font=UI, foreground="#555555",
                  wraplength=330, justify=tk.LEFT).pack(anchor="w", pady=(10, 0))
        ttk.Label(
            left,
            text=("Scaffolds are shaped so the entity extractor can read them: a\n"
                  "detectable entry point, docstrings that become summaries, and a\n"
                  "package layout that makes `python -m` work."),
            font=UI, foreground="#777777", justify=tk.LEFT,
        ).pack(anchor="w", pady=(10, 0))
        panes.add(left, weight=2)

        right = ttk.Frame(panes)
        ttk.Label(right, text="PREVIEW", font=UI_BOLD).pack(anchor="w", pady=(0, 3))
        self.p_out = TextPane(right, font=MONO)
        self.p_out.pack(fill=tk.BOTH, expand=True)
        self.p_out.set(_PROJECT_PRIMER)
        panes.add(right, weight=3)

    def _template_hint(self) -> None:
        self.p_hint.set(scaffold.TEMPLATE_BLURB.get(self.p_template.get(), ""))

    def _choose_project_dir(self) -> None:
        chosen = filedialog.askdirectory(title="Where to create the project")
        if chosen:
            self.p_where.set(chosen)

    def _plan_project(self):
        name = self.p_name.get()
        if not name:
            messagebox.showinfo("New project", "Give it a name first.")
            return None
        root = Path(self.p_where.get() or (self.ctx.workspace / "projects"))
        return scaffold.build(
            name, root / scaffold.slug(name),
            template=self.p_template.get() or "cli",
            bucket=self.p_bucket.get() or "misc",
            summary=self.p_summary.get().strip(),
        )

    def _preview_project(self) -> None:
        plan = self._plan_project()
        if plan is None:
            return
        self._scaffold = plan
        body = [plan.render(), "", "=" * 70, ""]
        for path in sorted(plan.files):
            body += [f"--- {path} " + "-" * max(0, 60 - len(path)), plan.files[path], ""]
        self.p_out.set("\n".join(body))
        self.ctx.status(f"Previewed {plan.name}: {len(plan.files)} files", "info")

    def _create_project(self, then_absorb: bool) -> None:
        plan = self._plan_project()
        if plan is None:
            return
        if plan.root.exists() and any(plan.root.iterdir()):
            messagebox.showerror("New project",
                                 f"{plan.root} already exists and is not empty.")
            return
        if not messagebox.askyesno(
            "Create project",
            f"Write {len(plan.files)} files to:\n{plan.root}?",
        ):
            return

        report = plan.write()
        self.p_out.set(plan.render() + "\n\n" + "\n".join(report))
        self.store.log("scaffold", detail=f"{plan.name} ({plan.template}) -> {plan.root}")
        self.ctx.status(f"Created {plan.name} at {plan.root}", "good")

        if then_absorb:
            self._run_absorb(plan.root, plan.name, plan.bucket, write=True)

    # -------------------------------------------------------------- new symbol
    def _build_symbol(self) -> None:
        page = ttk.Frame(self.book)
        self.book.add(page, text="New symbol")

        bar = toolbar(page)
        button(bar, "Check placement", self._check_symbol)
        button(bar, "Insert stub", self._insert_symbol)
        separator(bar)
        button(bar, "Open Write Gate", lambda: self.ctx.goto("gate"))

        panes = ttk.PanedWindow(page, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True, pady=(6, 0))

        left = ttk.Frame(panes, padding=(0, 0, 8, 0))
        ttk.Label(left, text="NEW SYMBOL", font=UI_BOLD).pack(anchor="w", pady=(0, 8))
        self.s_name = Field(left, "Name       ", width=30)
        self.s_name.pack(anchor="w", pady=2)
        self.s_kind = Field(left, "Kind       ", "function", width=12,
                            values=["function", "class"])
        self.s_kind.pack(anchor="w", pady=2)
        self.s_lines = Field(left, "Lines      ", "15", width=6)
        self.s_lines.pack(anchor="w", pady=2)
        self.s_project = Field(left, "Project    ", width=26, values=["(any)"])
        self.s_project.set("(any)")
        self.s_project.pack(anchor="w", pady=2)
        self.s_bucket = Field(left, "Bucket     ", "(any)", width=16,
                              values=["(any)"] + BUCKET_KEYS)
        self.s_bucket.pack(anchor="w", pady=2)

        ttk.Label(left, text="Intent -- what should it do?", font=UI).pack(
            anchor="w", pady=(10, 3))
        self.s_intent = TextPane(left, font=MONO, wrap=tk.WORD, height=4)
        self.s_intent.pack(fill=tk.X)

        ttk.Label(
            left,
            text=("Check placement runs all three gates. If it already exists you\n"
                  "will be told where. If it is genuinely new, the engine returns the\n"
                  "exact file and line -- you do not choose."),
            font=UI, foreground="#555555", justify=tk.LEFT,
        ).pack(anchor="w", pady=(10, 0))
        panes.add(left, weight=2)

        right = ttk.Frame(panes)
        head = ttk.Frame(right)
        head.pack(fill=tk.X)
        ttk.Label(head, text="VERDICT", font=UI_BOLD).pack(side=tk.LEFT, pady=(0, 3))
        self.s_verdict = tk.StringVar(value="")
        ttk.Label(head, textvariable=self.s_verdict,
                  font=("Consolas", 10, "bold")).pack(side=tk.RIGHT)
        self.s_out = TextPane(right, font=MONO)
        self.s_out.pack(fill=tk.BOTH, expand=True)
        self.s_out.set(_SYMBOL_PRIMER)
        panes.add(right, weight=3)

    def _symbol_params(self):
        name = self.s_name.get()
        if not name:
            messagebox.showinfo("New symbol", "Give it a name first.")
            return None
        try:
            lines = int(self.s_lines.get())
        except ValueError:
            lines = 0
        bucket = self.s_bucket.get()
        project = self.s_project.get()
        return (
            name,
            self.s_intent.get().strip() or name.replace("_", " "),
            lines,
            None if bucket in ("", "(any)") else bucket,
            None if project in ("", "(any)") else project,
        )

    def _check_symbol(self) -> None:
        params = self._symbol_params()
        if params is None:
            return
        name, intent, lines, bucket, project = params
        report = rules.gate(self.store, name=name, intent=intent, lines=lines,
                            bucket=bucket, project=project)
        self._placement = report.placement if report.placement.ok else None
        stub = scaffold.symbol_stub(name, intent, self.s_kind.get(), lines)
        self.s_out.set(report.render() + "\n\nSTUB TO BE INSERTED\n" + "-" * 60
                       + "\n" + stub)
        self.s_verdict.set("PROCEED" if report.allowed else "BLOCKED")
        self.ctx.status(
            "Gate passed -- Insert stub will write it at the given line"
            if report.allowed else "Gate blocked -- see the verdict",
            "good" if report.allowed else "warn",
        )

    def _insert_symbol(self) -> None:
        if self._placement is None:
            messagebox.showinfo("Insert", "Run Check placement first.")
            return
        params = self._symbol_params()
        if params is None:
            return
        name, intent, lines, _bucket, _project = params

        from atlas.address import Address
        address = Address.parse(self._placement.target_address)
        project = self.store.project_by_name(address.project or "")
        if project is None:
            messagebox.showerror("Insert", "Target project is not registered.")
            return
        target = Path(project.root) / self._placement.file_path

        if not messagebox.askyesno(
            "Insert stub",
            f"Insert a {self.s_kind.get()} stub into:\n{target}\n"
            f"at line {self._placement.insert_at_line}?\n\n"
            "The file is backed up to .atlas/backups first.",
        ):
            return

        from atlas.ledger import Ledger
        ledger = Ledger(self.store)
        backup = ledger.snapshot([target], "insert-symbol", f"before adding {name}")
        stub = scaffold.symbol_stub(name, intent, self.s_kind.get(), lines)
        try:
            message = scaffold.insert_symbol(
                target, self._placement.insert_at_line, stub
            )
        except OSError as exc:
            messagebox.showerror("Insert", str(exc))
            return
        self.s_out.set(
            f"{message}\nbacked up to {backup.directory} (ledger #{backup.ledger_id})\n\n"
            f"Re-index {project.name} so the map matches:\n"
            f"    Atlas tab -> select it -> Re-index selected\n\n{stub}"
        )
        self.ctx.status(f"Inserted {name} -- re-index {project.name}", "good")
        self.ctx.broadcast("refresh")

    # ---------------------------------------------------------------- add code
    def _build_code(self) -> None:
        page = ttk.Frame(self.book)
        self.book.add(page, text="Add code")

        bar = toolbar(page)
        button(bar, "Load file", self._load_code_file)
        button(bar, "Plan placement", self._plan_code)
        button(bar, "Write", self._write_code)
        separator(bar)
        button(bar, "Send to Ingest", lambda: self.ctx.goto("ingest"))

        options = ttk.Frame(page, padding=(6, 0))
        options.pack(fill=tk.X)
        self.c_dest = Field(options, "Destination project folder", width=56)
        self.c_dest.pack(side=tk.LEFT)
        button(options, "Browse", self._choose_code_dest)
        ttk.Label(options,
                  text="Paste one file, or a whole transcript with fenced blocks.",
                  font=UI, foreground="#666666").pack(side=tk.LEFT, padx=12)

        panes = ttk.PanedWindow(page, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True, pady=(6, 0))

        left = ttk.Frame(panes)
        ttk.Label(left, text="CODE", font=UI_BOLD).pack(anchor="w", pady=(0, 3))
        self.c_input = TextPane(left, font=MONO)
        self.c_input.pack(fill=tk.BOTH, expand=True)
        self.c_input.set(_CODE_PRIMER)
        panes.add(left, weight=3)

        right = ttk.Frame(panes)
        ttk.Label(right, text="PLAN", font=UI_BOLD).pack(anchor="w", pady=(0, 3))
        self.c_table = SortableTable(
            right, ["ok", "path", "lines", "confidence", "note"],
            ["py", "target path", "L", "conf", "how it was placed"],
            [28, 230, 42, 44, 150], ["c", "w", "e", "e", "w"], height=12,
        )
        self.c_table.pack(fill=tk.BOTH, expand=True)
        self.c_out = TextPane(right, font=MONO, height=12)
        self.c_out.pack(fill=tk.BOTH, expand=True, pady=(6, 0))
        panes.add(right, weight=2)

    def _choose_code_dest(self) -> None:
        chosen = filedialog.askdirectory(title="Where should this code go")
        if chosen:
            self.c_dest.set(chosen)

    def _load_code_file(self) -> None:
        chosen = filedialog.askopenfilename(
            title="Load a file or transcript",
            filetypes=[("Code and text", "*.py *.md *.txt"), ("All files", "*.*")],
        )
        if chosen:
            self.c_input.set(Path(chosen).read_text(encoding="utf-8", errors="replace"))
            self.ctx.status(f"Loaded {Path(chosen).name}", "info")

    def _code_plan(self):
        text = self.c_input.get().strip()
        if not text or text.startswith("PASTE CODE HERE"):
            messagebox.showinfo("Add code", "Paste some code first.")
            return None
        if "```" in text:
            return fanoutmod.parse_document(text)
        # A bare paste is one file; name it from whatever it defines.
        plan = fanoutmod.FanoutPlan()
        name, _conf, note = fanoutmod._guess_path("", text, "python", "", 1)
        plan.pieces.append(fanoutmod.Piece(name, text + "\n", "python", 0.5,
                                           "pasted", note))
        return plan

    def _plan_code(self) -> None:
        plan = self._code_plan()
        if plan is None:
            return
        self._code_fanout = plan
        rows = []
        for piece in sorted(plan.pieces, key=lambda p: p.path):
            valid = piece.valid_python
            rows.append({
                "ok": {True: "ok", False: "!!", None: ""}[valid],
                "path": piece.path, "lines": piece.lines,
                "confidence": f"{piece.confidence:.2f}", "note": piece.note,
                "_tags": ("bad",) if valid is False else
                         (("warn",) if piece.confidence < 0.5 else ()),
            })
        self.c_table.set_rows(rows)
        self.c_out.set(plan.render())
        self.ctx.status(f"{len(plan.pieces)} file(s) planned", "info")

    def _write_code(self) -> None:
        plan = getattr(self, "_code_fanout", None)
        if plan is None:
            messagebox.showinfo("Write", "Plan the placement first.")
            return
        destination = self.c_dest.get()
        if not destination:
            messagebox.showinfo("Write", "Choose a destination folder.")
            return
        destination = Path(destination)
        if not messagebox.askyesno(
            "Write code",
            f"Write {len(plan.pieces)} file(s) into:\n{destination}?\n\n"
            "Existing files are kept alongside as .prior -- nothing is overwritten.",
        ):
            return
        report = fanoutmod.commit(plan, destination)
        self.c_out.set("\n".join(report))
        self.store.log("add-code", detail=f"{len(plan.pieces)} files -> {destination}")
        self.ctx.status(f"Wrote {len(plan.pieces)} file(s) to {destination}", "good")

    # ----------------------------------------------------------------- absorb
    def _build_absorb(self) -> None:
        page = ttk.Frame(self.book)
        self.book.add(page, text="Absorb project")

        bar = toolbar(page)
        button(bar, "Choose folder", self._choose_absorb)
        button(bar, "Preview", lambda: self._run_absorb_from_form(False))
        button(bar, "ABSORB", lambda: self._run_absorb_from_form(True))
        separator(bar)
        button(bar, "Open Harness tab", lambda: self.ctx.goto("harness"))

        options = ttk.Frame(page, padding=(6, 0))
        options.pack(fill=tk.X)
        self.a_path = Field(options, "Project folder", width=52)
        self.a_path.pack(side=tk.LEFT)
        self.a_name = Field(options, "Name", width=18)
        self.a_name.pack(side=tk.LEFT, padx=(10, 0))
        self.a_bucket = Field(options, "Bucket", "(auto)", width=14,
                              values=["(auto)"] + BUCKET_KEYS)
        self.a_bucket.pack(side=tk.LEFT, padx=(10, 0))

        options2 = ttk.Frame(page, padding=(6, 4))
        options2.pack(fill=tk.X)
        self.a_priority = Field(options2, "Priority", "60", width=5)
        self.a_priority.pack(side=tk.LEFT)
        self.a_copy = tk.BooleanVar(value=False)
        ttk.Checkbutton(options2, text="copy into workspace (default: integrate in place)",
                        variable=self.a_copy).pack(side=tk.LEFT, padx=(12, 0))
        self.a_external = tk.BooleanVar(value=False)
        ttk.Checkbutton(options2, text="vendored / do not edit",
                        variable=self.a_external).pack(side=tk.LEFT, padx=(12, 0))

        panes = ttk.PanedWindow(page, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True, pady=(6, 0))

        left = ttk.Frame(panes)
        ttk.Label(left, text="ENTITIES FOUND", font=UI_BOLD).pack(anchor="w", pady=(0, 3))
        self.a_table = SortableTable(
            left, ["kind", "name", "path", "summary"],
            ["kind", "name", "file", "what it is"],
            [70, 180, 200, 260], ["w", "w", "w", "w"], height=24,
        )
        self.a_table.pack(fill=tk.BOTH, expand=True)
        panes.add(left, weight=3)

        right = ttk.Frame(panes)
        ttk.Label(right, text="REPORT", font=UI_BOLD).pack(anchor="w", pady=(0, 3))
        self.a_out = TextPane(right, font=MONO)
        self.a_out.pack(fill=tk.BOTH, expand=True)
        self.a_out.set(_ABSORB_PRIMER)
        panes.add(right, weight=2)

    def _choose_absorb(self) -> None:
        chosen = filedialog.askdirectory(title="Project folder to absorb")
        if chosen:
            self.a_path.set(chosen)
            if not self.a_name.get():
                self.a_name.set(Path(chosen).name)
            self._run_absorb_from_form(False)

    def _run_absorb_from_form(self, write: bool) -> None:
        path = self.a_path.get()
        if not path:
            messagebox.showinfo("Absorb", "Choose a folder first.")
            return
        bucket = self.a_bucket.get()
        self._run_absorb(
            Path(path), self.a_name.get() or Path(path).name,
            None if bucket in ("", "(auto)") else bucket, write,
        )

    def _run_absorb(self, path: Path, name: str, bucket: str | None,
                    write: bool) -> None:
        if write and not messagebox.askyesno(
            "Absorb",
            f"Register {name} in the harness?\n\n"
            "Nothing is moved, copied or rewritten -- the folder stays exactly as it "
            "is. This adds index rows and registers its tools so they are runnable "
            "from the Harness tab.\n\n"
            "Reversible at any time with: atlas release " + name,
        ):
            return
        try:
            priority = int(self.a_priority.get())
        except (ValueError, AttributeError):
            priority = 60

        self.ctx.status(f"{'Absorbing' if write else 'Scanning'} {name} ...", "busy")
        copy = bool(self.a_copy.get())
        external = bool(self.a_external.get())

        def work():
            return absorbmod.absorb(
                self.store, path, name=name, bucket=bucket, priority=priority,
                copy_into_workspace=copy and write, external=external,
                dry_run=not write,
            )

        self.ctx.job.run(work, "absorb_done", "create_error")

    def _absorb_done(self, report) -> None:
        self._absorb_report = report
        self.a_out.set(report.render(limit=40))
        if report.extraction:
            self.a_table.set_rows([
                {
                    "kind": e.kind, "name": e.name, "path": e.path,
                    "summary": e.summary,
                    "_tags": ("hot",) if e.runnable else ("dim",),
                }
                for e in report.extraction.entities
            ])
        self.ctx.refresh_counts()
        self.ctx.broadcast("refresh")
        if report.errors and not report.total_entities:
            self.ctx.status("Absorb failed -- see the report", "bad")
        elif report.dry_run:
            self.ctx.status(
                f"Preview: {report.total_entities} entities "
                f"({report.runnable} runnable). Press ABSORB to register.", "info",
            )
        else:
            self.ctx.status(
                f"Absorbed {report.project}: {report.symbols} symbols, "
                f"{report.total_entities} entities, {report.runnable} runnable",
                "good",
            )

    def _error(self, message: str) -> None:
        self.a_out.set(str(message))
        self.ctx.status("Failed -- see the report pane", "bad")

    def _scaffold_done(self, payload) -> None:
        self.p_out.set(str(payload))

    # ---------------------------------------------------------------- lifecycle
    def on_refresh(self) -> None:
        names = ["(any)"] + [p.name for p in self.store.projects()]
        self.s_project.set_values(names)

    on_show = on_refresh


_PROJECT_PRIMER = """NEW PROJECT

Scaffolds a project that the rest of the system can already read.

  cli       argparse command line -- every subcommand becomes its own entity
  gui       tabbed Tkinter application
  library   importable package with a public surface
  service   FastAPI server with one route
  script    a single file that does one thing

Each comes with a pyproject.toml, a README, a test file and docstrings written so
the entity extractor can use them as summaries.

Why that matters: a project created here and absorbed immediately shows up with
real, named, runnable entities. A project thrown together by hand usually shows up
as one anonymous script.

Fill in the name and press Preview. Nothing is written until you press Create.
"""

_SYMBOL_PRIMER = """NEW SYMBOL

Add one function or class -- in the right place, decided by the engine.

  1. DEDUPE     Searches every indexed symbol. If it already exists you are told
                where, and you should reuse it.
  2. BUDGET     The declared line count is checked against the bucket ceiling.
  3. PLACEMENT  You get a file and an exact insertion line, plus the neighbouring
                symbol and what shifts below it.

Then "Insert stub" writes a stub there, backing the file up first.

Re-index the project afterwards so the map matches the file. Spans drift otherwise,
and the hash check will start refusing slices -- correctly.
"""

_CODE_PRIMER = """PASTE CODE HERE

Two things work:

  A single file     paste it; the target filename is inferred from what it defines
  A whole transcript with ```fenced blocks``` -- each block is placed separately,
                    using its fence title, a `# file:` comment, or the filename
                    mentioned just above it

Press "Plan placement" to see where everything would go, with a confidence score
per file. Low confidence means it guessed -- check those before writing.

Nothing is overwritten: an existing file is kept beside the new one as .prior.
"""

_ABSORB_PRIMER = """ABSORB AN EXISTING PROJECT

Point this at a folder and it becomes a first-class part of the harness.

WHAT IT DOES

  1. CLASSIFY   which of the twenty buckets, with evidence you can audit
  2. INDEX      every symbol, addressable, with call edges in both directions
  3. EXTRACT    everything the project can DO -- GUIs, CLIs, subcommands,
                servers, launchers, skills, notebooks, and its callable API
  4. REGISTER   those entities, so they are runnable from the Harness tab

WHAT IT DOES NOT DO

  Nothing is moved, copied, renamed or rewritten. The project keeps its own
  structure and identity exactly. It is integrated by reference and index.

  Everything this adds is additive and reversible:

      atlas release <name>

  removes the index rows and the registrations. The folder is exactly as it was.

This is how a large project with fourteen tools stops being an opaque folder and
becomes fourteen things you can find, run and call -- without flattening its
contents or losing its shape.

Press Preview first. It shows every entity it would register, and writes nothing.
"""
