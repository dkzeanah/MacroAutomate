"""Write Gate tab -- run the three gates before any new code is added.

Left: what you intend to write. Right: whether it already exists, whether it is small
enough to be one symbol, and exactly which file and line it goes in. The verdict is
copyable as a block, so it can be pasted straight into a conversation with a model.
"""

from __future__ import annotations

import tkinter as tk
from tkinter import ttk

from atlas import rules
from atlas.buckets import bucket_titles
from studio.widgets import (
    MONO, UI, UI_BOLD, Field, SortableTable, TextPane, button, separator, toolbar,
)

BUCKET_KEYS = ["(any)"] + [key for key, _t, _b in bucket_titles()]


class GateTab:
    def __init__(self, parent: ttk.Frame, context) -> None:
        self.ctx = context
        self.store = context.store

        bar = toolbar(parent)
        button(bar, "Run all gates", self._run_gate)
        button(bar, "Dedupe only", self._run_find)
        button(bar, "Placement only", self._run_placement)
        separator(bar)
        button(bar, "Copy verdict", self._copy)
        button(bar, "Clear", self._clear)

        panes = ttk.PanedWindow(parent, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

        # ---- proposal ------------------------------------------------------
        left = ttk.Frame(panes, padding=(0, 0, 6, 0))
        ttk.Label(left, text="PROPOSED SYMBOL", font=UI_BOLD).pack(anchor="w", pady=(0, 6))

        form = ttk.Frame(left)
        form.pack(fill=tk.X)
        self.name = Field(form, "Name          ", width=34)
        self.name.pack(fill=tk.X, pady=2)
        self.lines = Field(form, "Lines (declared)", "20", width=8)
        self.lines.pack(anchor="w", pady=2)
        self.bucket = Field(form, "Bucket        ", width=20, values=BUCKET_KEYS)
        self.bucket.set("(any)")
        self.bucket.pack(anchor="w", pady=2)
        self.project = Field(form, "Project       ", width=28, values=["(any)"])
        self.project.set("(any)")
        self.project.pack(anchor="w", pady=2)
        self.path = Field(form, "Prefer file   ", width=34)
        self.path.pack(fill=tk.X, pady=2)

        ttk.Label(left, text="Intent -- what is it supposed to do?", font=UI).pack(
            anchor="w", pady=(10, 3))
        self.intent = TextPane(left, font=MONO, wrap=tk.WORD, height=5)
        self.intent.pack(fill=tk.X)
        self.intent.set("")

        ttk.Label(
            left,
            text=("The dedupe gate searches every indexed symbol.\n"
                  "MISS is authoritative: the code does not exist,\n"
                  "stop looking for it and write it."),
            font=UI, foreground="#555555", justify=tk.LEFT,
        ).pack(anchor="w", pady=(10, 4))

        ttk.Label(left, text="CANDIDATE MATCHES", font=UI_BOLD).pack(anchor="w", pady=(8, 3))
        self.matches = SortableTable(
            left,
            ["score", "address", "lines", "signature"],
            ["score", "address", "L", "signature"],
            [48, 250, 40, 260],
            ["e", "w", "e", "w"],
            on_select=self._match_selected,
            height=10,
        )
        self.matches.pack(fill=tk.BOTH, expand=True)
        panes.add(left, weight=2)

        # ---- verdict -------------------------------------------------------
        right = ttk.Frame(panes)
        head = ttk.Frame(right)
        head.pack(fill=tk.X)
        ttk.Label(head, text="VERDICT", font=UI_BOLD).pack(side=tk.LEFT, pady=(0, 3))
        self.verdict_var = tk.StringVar(value="")
        ttk.Label(head, textvariable=self.verdict_var,
                  font=("Consolas", 10, "bold")).pack(side=tk.RIGHT)
        self.output = TextPane(right, font=MONO, height=34)
        self.output.pack(fill=tk.BOTH, expand=True)
        self.output.set(_PRIMER)
        panes.add(right, weight=3)

    # ----------------------------------------------------------------- refresh
    def on_refresh(self) -> None:
        self.project.set_values(["(any)"] + [p.name for p in self.store.projects()])

    on_show = on_refresh

    # ------------------------------------------------------------------ helpers
    def _params(self) -> tuple[str, str, int, str | None, str | None, str | None]:
        name = self.name.get() or "new_symbol"
        intent = self.intent.get().strip() or name.replace("_", " ")
        try:
            lines = int(self.lines.get())
        except ValueError:
            lines = 0
        bucket = self.bucket.get()
        bucket = None if bucket in ("", "(any)") else bucket
        project = self.project.get()
        project = None if project in ("", "(any)") else project
        path = self.path.get() or None
        return name, intent, lines, bucket, project, path

    def _show_matches(self, result: rules.FindResult) -> None:
        self.matches.set_rows([
            {
                "score": f"{m.score:.2f}",
                "address": m.address,
                "lines": m.lines,
                "signature": m.signature,
                "_tags": ("hot",) if m.score >= 0.7 else (),
            }
            for m in result.matches
        ])

    def _match_selected(self, row: dict) -> None:
        from atlas import slicer
        try:
            piece = slicer.get(self.store, row["address"])
        except Exception as exc:
            self.output.set(f"# {exc}")
            return
        self.output.set(
            f"# Existing candidate -- reuse this instead of writing a duplicate.\n\n"
            + piece.render() + f"\n\n# {piece.tokens} tokens"
        )
        self.output.highlight_atlas()

    # ------------------------------------------------------------------ actions
    def _run_gate(self) -> None:
        name, intent, lines, bucket, project, path = self._params()
        report = rules.gate(self.store, name=name, intent=intent, lines=lines,
                            bucket=bucket, project=project, prefer_path=path)
        self._show_matches(report.find_result)
        self.output.set(report.render())
        if report.allowed:
            self.verdict_var.set("PROCEED")
            self.ctx.status(f"Gate passed for {name} -- create it at the given line", "good")
        else:
            self.verdict_var.set("BLOCKED")
            self.ctx.status(f"Gate blocked {name} -- see the verdict", "warn")

    def _run_find(self) -> None:
        name, intent, _lines, bucket, _project, _path = self._params()
        result = rules.find(self.store, intent or name, bucket=bucket)
        self._show_matches(result)
        self.output.set(result.render())
        self.verdict_var.set("EXISTS" if result.hit else "SAFE TO CREATE")
        self.ctx.status(
            f"{'HIT' if result.hit else 'MISS'} -- {result.searched} symbols searched",
            "warn" if result.hit else "good",
        )

    def _run_placement(self) -> None:
        name, _intent, lines, bucket, project, path = self._params()
        placement = rules.plan_insert(self.store, name, lines, bucket=bucket,
                                      project=project, prefer_path=path)
        self.output.set(placement.render())
        self.verdict_var.set("PLACED" if placement.ok else "REFUSED")
        self.ctx.status(placement.reason, "good" if placement.ok else "warn")

    def _copy(self) -> None:
        self.ctx.app.clipboard_clear()
        self.ctx.app.clipboard_append(self.output.get())
        self.ctx.status("Verdict copied -- paste it into your model's context", "good")

    def _clear(self) -> None:
        self.output.set(_PRIMER)
        self.matches.set_rows([])
        self.verdict_var.set("")


_PRIMER = """ATLAS WRITE GATE

Nothing gets appended to this codebase on a hunch. Three gates, in order:

  [1] DEDUPE     Does it already exist?
                 HIT  -> reuse the match, or justify the divergence.
                 MISS -> authoritative. It is not there. Stop searching, create it.

  [2] BUDGET     How many lines will it be? Declared up front, checked against the
                 bucket ceiling. Oversized symbols are refused, not quietly accepted.

  [3] PLACEMENT  Where does it go? The engine answers, not the model. You get a file
                 and an exact insertion line, plus what shifts below it.

Fill in the name, the declared line count and the intent, then Run all gates.
The verdict is designed to be copied straight into a model's context.
"""


class AutomationTab:
    """Inspect retained evidence and deliberately invoke the live automater."""

    def __init__(self, master, context):
        import tkinter as tk
        from tkinter import ttk
        from studio.widgets import TextPane
        from sidelearner.perception.vision import FanBridgeClient
        self.context, self.client = context, FanBridgeClient()
        self.query = tk.StringVar()
        ttk.Label(master, text="Learn once, recheck before acting", font=("Segoe UI", 15, "bold")).pack(anchor="w", padx=12, pady=10)
        ttk.Label(master, text="Observed = captured. Executed = steps ran. Verified = a specific check passed.\n"
                  "Repeated observations are not independent proof. Failed checks remain visible.",
                  wraplength=1050).pack(anchor="w", padx=12)
        row = ttk.Frame(master)
        row.pack(fill="x", padx=12, pady=10)
        ttk.Label(row, text="App, tool or question:").pack(side="left")
        ttk.Entry(row, textvariable=self.query).pack(side="left", fill="x", expand=True, padx=8)
        self.buttons = []
        actions = [("List taskbar", "fan_taskbar_list"), ("Learn visible taskbar", "fan_taskbar_learn"),
                   ("Open named app", "fan_taskbar_open"), ("Evidence", "automation_knowledge_search"),
                   ("Saved tools", "tool_catalog_search"), ("Find code", "context_map_find"),
                   ("Read exact address", "context_map_get"), ("Capabilities", "fan_capabilities"),
                   ("Show learned lesson", "fan_learning_lesson")]
        toolbar = ttk.Frame(master)
        toolbar.pack(fill="x", padx=12)
        for index, (label, name) in enumerate(actions):
            button = ttk.Button(toolbar, text=label, command=lambda n=name: self.run(n))
            button.grid(row=index // 4, column=index % 4, sticky="ew", padx=3, pady=3)
            toolbar.columnconfigure(index % 4, weight=1)
            self.buttons.append(button)
        self.output = TextPane(master, wrap="word")
        self.output.pack(fill="both", expand=True, padx=12, pady=10)
        self.output.set("1. Start the Macro Automator.\n2. Learn visible taskbar captures icons and FindText bits without switching apps.\n"
            "3. List taskbar shows saved names; enter one above, then Open named app.\n"
            "4. Watch the yellow target before its click. Evidence records whether the foreground program matched.\n\n"
            "Saved tools returns reusable scripts and workflows. Find code returns Atlas addresses; paste one to Read exact address.\n"
            "For candidate patterns, lessons, counterexamples and trials, use the automater's Learning Workbench.\n"
            "Source projects stay in place. Atlas / Index / Write Gate / Ingest / Condense / Harness share this workspace.")
        context.job.on("fan_done", self.done)
        context.job.on("fan_error", self.failed)

    def run(self, name):
        query = self.query.get().strip()
        if name in ("fan_taskbar_open", "context_map_find", "context_map_get", "fan_learning_lesson") and not query:
            self.output.set("Enter a saved app name, search question or exact Atlas address first.")
            return
        args = {} if name in ("fan_capabilities", "fan_taskbar_learn") else {
            "name" if name == "fan_taskbar_open" else "address" if name == "context_map_get" else "query": query}
        for button in self.buttons:
            button.state(["disabled"])
        self.output.set("Working locally: " + name + " ...")
        self.context.job.run(lambda: self.client.call(name, args), done_kind="fan_done", error_kind="fan_error")

    def done(self, value):
        import json
        for button in self.buttons:
            button.state(["!disabled"])
        lines = []
        if "targets" in value:
            lines = ["TASKBAR MEMORY — historical observations; opening checks the live icon again.", ""]
            for item in value["targets"]:
                lines.append(f"{item['label']}\n  Program: {item.get('exe') or 'identity not confirmed'} | FindText bits: {item.get('binary_length', 0)} | Verified opens: {item.get('verified_count', 0)}\n")
        elif "records" in value:
            lines = ["REUSABLE KNOWLEDGE — evidence is limited to its recorded scope.", ""]
            for item in value["records"]:
                lines.append(f"{item.get('target', item.get('name', ''))}\n  {item.get('state', item.get('description', 'reference'))}\n  Checks: {item.get('attempts', 0)} | Verified: {item.get('verified', 0)} | Failures: {item.get('failures', 0)}\n")
        elif "reference" in value:
            lines = [value["reference"], value.get("warning", "")]
        self.output.set("\n".join(lines) + ("\n\nDetails:\n" if lines else "") + json.dumps(value, indent=2, ensure_ascii=False))

    def failed(self, error):
        self.done({"ok": False, "error": str(error), "help": "Start the Macro Automator and its local bridge, then retry."})
