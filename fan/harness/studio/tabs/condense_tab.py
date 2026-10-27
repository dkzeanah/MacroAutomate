"""Condense tab -- collapse the indexed universe into classes.py and functions.py.

The generated files are not dumps. Each opens with a map giving every symbol its line
span *in the generated file*, so the result is navigable by the same protocol as
everything else: read the map, fetch the span.
"""

from __future__ import annotations

import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from atlas import condense as condensemod
from atlas.spec import token_estimate
from studio.widgets import (
    MONO, UI, UI_BOLD, Field, SortableTable, TextPane, button, separator, toolbar,
)


class CondenseTab:
    def __init__(self, parent: ttk.Frame, context) -> None:
        self.ctx = context
        self.store = context.store
        self._result: condensemod.CondenseResult | None = None

        bar = toolbar(parent)
        button(bar, "Build condensed files", self._build)
        button(bar, "Write to disk", self._write)
        separator(bar)
        self.include_private = tk.BooleanVar(value=False)
        ttk.Checkbutton(bar, text="include _private",
                        variable=self.include_private).pack(side=tk.LEFT, padx=6)
        separator(bar)
        button(bar, "Choose output folder", self._choose_out)

        options = ttk.Frame(parent, padding=(6, 0))
        options.pack(fill=tk.X)
        ttk.Label(options, text="Projects: select rows on the left "
                               "(none selected = the whole universe)",
                  font=UI, foreground="#666666").pack(side=tk.LEFT)
        self.out_field = Field(options, "Output",
                               str(self.ctx.workspace / "condensed"), width=54)
        self.out_field.pack(side=tk.RIGHT)

        panes = ttk.PanedWindow(parent, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

        left = ttk.Frame(panes)
        ttk.Label(left, text="SOURCE PROJECTS", font=UI_BOLD).pack(anchor="w", pady=(0, 3))
        self.projects = SortableTable(
            left,
            ["name", "bucket", "symbols", "lines"],
            ["project", "bucket", "symbols", "lines"],
            [180, 96, 62, 68],
            ["w", "w", "e", "e"],
            height=26,
        )
        self.projects.pack(fill=tk.BOTH, expand=True)
        ttk.Label(left, text="SECTIONS", font=UI_BOLD).pack(anchor="w", pady=(8, 3))
        self.sections = SortableTable(
            left,
            ["section", "count", "lines"],
            ["functional area / bucket", "n", "lines"],
            [220, 40, 60],
            ["w", "e", "e"],
            height=12,
        )
        self.sections.pack(fill=tk.BOTH, expand=True)
        panes.add(left, weight=2)

        right = ttk.Frame(panes)
        head = ttk.Frame(right)
        head.pack(fill=tk.X)
        ttk.Label(head, text="GENERATED", font=UI_BOLD).pack(side=tk.LEFT, pady=(0, 3))
        self.summary_var = tk.StringVar(value="")
        ttk.Label(head, textvariable=self.summary_var, font=("Consolas", 9),
                  foreground="#0a7d28").pack(side=tk.RIGHT)

        self.book = ttk.Notebook(right)
        self.book.pack(fill=tk.BOTH, expand=True)
        self.classes_pane = TextPane(self.book, font=MONO)
        self.functions_pane = TextPane(self.book, font=MONO)
        self.manifest_pane = TextPane(self.book, font=MONO, wrap=tk.WORD)
        self.book.add(self.classes_pane, text="classes.py")
        self.book.add(self.functions_pane, text="functions.py")
        self.book.add(self.manifest_pane, text="manifest / skipped")
        self.classes_pane.set(_PRIMER)
        panes.add(right, weight=4)

        self.ctx.job.on("condense_done", self._done)
        self.ctx.job.on("condense_error", self._error)

    # ----------------------------------------------------------------- refresh
    def on_refresh(self) -> None:
        self.projects.set_rows([
            {"name": p.name, "bucket": p.bucket, "symbols": p.symbol_count,
             "lines": p.line_count}
            for p in self.store.projects()
        ])

    on_show = on_refresh

    # ------------------------------------------------------------------ actions
    def _choose_out(self) -> None:
        chosen = filedialog.askdirectory(title="Where to write classes.py / functions.py")
        if chosen:
            self.out_field.set(chosen)

    def _selected_ids(self) -> list[int] | None:
        rows = self.projects.selected_all()
        if not rows:
            return None
        ids = []
        for row in rows:
            project = self.store.project_by_name(row["name"])
            if project:
                ids.append(project.id)
        return ids or None

    def _build(self) -> None:
        ids = self._selected_ids()
        scope = f"{len(ids)} project(s)" if ids else "the whole indexed universe"
        self.ctx.status(f"Condensing {scope} ...", "busy")
        private = self.include_private.get()

        def work():
            return condensemod.condense(self.store, ids, include_private=private)

        self.ctx.job.run(work, "condense_done", "condense_error")

    def _done(self, result: condensemod.CondenseResult) -> None:
        self._result = result
        self.classes_pane.set(result.classes_text)
        self.functions_pane.set(result.functions_text)
        self.classes_pane.highlight_atlas()
        self.functions_pane.highlight_atlas()

        manifest = [
            f"classes:   {len(result.classes_symbols)}",
            f"functions: {len(result.functions_symbols)}",
            f"skipped:   {len(result.skipped)}",
            "",
            "Skipped entries are duplicates (identical bodies already collected) or",
            "symbols whose source could not be read. Nothing is lost -- the originals",
            "stay where they are; this is a projection, not a move.",
            "",
        ]
        manifest += result.skipped
        self.manifest_pane.set("\n".join(manifest))

        by_section: dict[str, list] = {}
        for symbol in result.classes_symbols:
            by_section.setdefault(f"[class] {symbol.bucket}", []).append(symbol)
        for symbol in result.functions_symbols:
            by_section.setdefault(symbol.area, []).append(symbol)
        self.sections.set_rows([
            {"section": name, "count": len(members),
             "lines": sum(s.out_end - s.out_start + 1 for s in members)}
            for name, members in sorted(by_section.items(),
                                        key=lambda kv: -len(kv[1]))
        ])

        tokens = token_estimate(result.classes_text) + token_estimate(result.functions_text)
        self.summary_var.set(
            f"{result.total} symbols  |  "
            f"{len(result.classes_text.splitlines()) + len(result.functions_text.splitlines()):,} lines  |  "
            f"~{tokens:,} tokens"
        )
        self.ctx.status(
            f"Condensed {result.total} symbols "
            f"({len(result.classes_symbols)} classes, {len(result.functions_symbols)} functions)",
            "good",
        )

    def _error(self, message: str) -> None:
        self.manifest_pane.set(str(message))
        self.book.select(2)
        self.ctx.status("Condense failed -- see manifest tab", "bad")

    def _write(self) -> None:
        if self._result is None:
            messagebox.showinfo("Write", "Build the condensed files first.")
            return
        destination = Path(self.out_field.get()).expanduser()
        if destination.exists() and any(destination.iterdir()):
            if not messagebox.askyesno(
                "Write",
                f"{destination} already has files in it.\n\n"
                "classes.py, functions.py and CONDENSE_MANIFEST.txt will be replaced. "
                "Continue?",
            ):
                return
        written = condensemod.write(self._result, destination)
        self.manifest_pane.set(
            "WROTE\n" + "\n".join(f"  {p}" for p in written)
            + "\n\n" + self.manifest_pane.get()
        )
        self.store.log("condense", detail=f"{self._result.total} symbols -> {destination}")
        self.ctx.broadcast("refresh")
        self.ctx.status(f"Wrote {len(written)} files to {destination}", "good")


_PRIMER = '''CONDENSE

Collapse every indexed project into two files that follow the same protocol as the
rest of the map:

  classes.py     every class, grouped by bucket
  functions.py   every function, grouped by functional area
                 (io & filesystem, parsing & scanning, llm & prompting, ...)

Each generated file opens with a MAP giving every symbol its line span in that file.
An agent reads the map, then fetches one span -- never the whole file. Each body keeps
its origin address and its call edges, so a symbol can always be traced back to the
project it came from.

Identical bodies are collected once. Nothing is moved or deleted: this is a projection
of the indexed universe, and the originals stay exactly where they are.

Select projects on the left to narrow the scope, or build the whole universe at once.
'''
