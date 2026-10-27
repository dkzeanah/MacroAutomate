"""Export tab -- produce the pack a third-party LLM is handed, and prove it is cheaper.

The budget panel is the argument in numbers: what the map costs to read versus what
reading the sources would have cost.
"""

from __future__ import annotations

import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from atlas import export as exportmod
from atlas.spec import token_estimate
from studio.widgets import (
    MONO, UI, UI_BOLD, Field, SortableTable, TextPane, button, separator, toolbar,
)


class ExportTab:
    def __init__(self, parent: ttk.Frame, context) -> None:
        self.ctx = context
        self.store = context.store

        bar = toolbar(parent)
        button(bar, "Preview ATLAS.md", self._preview_atlas)
        button(bar, "Preview INDEX.md", self._preview_index)
        button(bar, "Preview LLM_GUIDE.md", self._preview_guide)
        separator(bar)
        button(bar, "System preamble", self._preamble)
        button(bar, "Token budget", self._budget)
        separator(bar)
        button(bar, "Write full pack", self._export)
        button(bar, "Copy pane", self._copy)

        options = ttk.Frame(parent, padding=(6, 0))
        options.pack(fill=tk.X)
        self.out_field = Field(options, "Export to", str(self.ctx.workspace), width=64)
        self.out_field.pack(side=tk.LEFT)
        button(options, "Browse", self._choose_out)
        ttk.Label(
            options,
            text="Writes ATLAS.md + LLM_GUIDE.md at the root, and one INDEX.md "
                 "per project under .atlas/index/",
            font=UI, foreground="#666666",
        ).pack(side=tk.LEFT, padx=14)

        panes = ttk.PanedWindow(parent, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

        left = ttk.Frame(panes)
        ttk.Label(left, text="PROJECTS  (select one for its INDEX.md)",
                  font=UI_BOLD).pack(anchor="w", pady=(0, 3))
        self.projects = SortableTable(
            left,
            ["name", "bucket", "symbols", "index_tokens", "source_tokens", "ratio"],
            ["project", "bucket", "symbols", "index tok", "source tok", "x"],
            [170, 92, 62, 74, 82, 44],
            ["w", "w", "e", "e", "e", "e"],
            on_select=lambda r: self._preview_index(),
            height=30,
        )
        self.projects.pack(fill=tk.BOTH, expand=True)
        panes.add(left, weight=3)

        right = ttk.Frame(panes)
        head = ttk.Frame(right)
        head.pack(fill=tk.X)
        ttk.Label(head, text="PREVIEW", font=UI_BOLD).pack(side=tk.LEFT, pady=(0, 3))
        self.cost_var = tk.StringVar(value="")
        ttk.Label(head, textvariable=self.cost_var, font=("Consolas", 9),
                  foreground="#0a7d28").pack(side=tk.RIGHT)
        self.preview = TextPane(right, font=MONO, height=34)
        self.preview.pack(fill=tk.BOTH, expand=True)
        self.preview.set(_PRIMER)
        panes.add(right, weight=4)

        self.ctx.job.on("export_done", self._export_done)
        self.ctx.job.on("export_error", self._error)

    # ----------------------------------------------------------------- refresh
    def on_refresh(self) -> None:
        rows = []
        for project in self.store.projects():
            try:
                index_tokens = token_estimate(
                    exportmod.render_index_from_store(self.store, project.id)
                )
            except Exception:
                index_tokens = 0
            source_tokens = token_estimate("x" * project.line_count * 40)
            ratio = (source_tokens / index_tokens) if index_tokens else 0
            rows.append({
                "name": project.name,
                "bucket": project.bucket,
                "symbols": project.symbol_count,
                "index_tokens": f"{index_tokens:,}",
                "source_tokens": f"{source_tokens:,}",
                "ratio": f"{ratio:.0f}",
                "_tags": ("hot",) if ratio >= 20 else (),
            })
        self.projects.set_rows(rows)

    on_show = on_refresh

    # ----------------------------------------------------------------- previews
    def _show(self, text: str, label: str) -> None:
        self.preview.set(text)
        self.cost_var.set(f"{label}: {token_estimate(text):,} tokens")

    def _preview_atlas(self) -> None:
        text = exportmod.render_atlas_md(
            exportmod.atlas_entries(self.store), self.ctx.workspace
        )
        self._show(text, "ATLAS.md")
        self.ctx.status("Tier 0 -- the only file an agent must always read", "info")

    def _preview_index(self) -> None:
        row = self.projects.selected()
        if not row:
            messagebox.showinfo("INDEX.md", "Select a project on the left.")
            return
        project = self.store.project_by_name(row["name"])
        if project is None:
            return
        text = exportmod.render_index_from_store(self.store, project.id)
        self._show(text, f"{project.name}.INDEX.md")
        self.ctx.status(
            f"Tier 1 for {project.name}: {project.symbol_count} symbols, "
            f"{project.line_count:,} source lines", "info",
        )

    def _preview_guide(self) -> None:
        self._show(exportmod.GUIDE, "LLM_GUIDE.md")
        self.ctx.status("The protocol a third-party model is handed", "info")

    def _preamble(self) -> None:
        text = exportmod.system_preamble(self.store)
        self._show(text, "system preamble")
        self.ctx.app.clipboard_clear()
        self.ctx.app.clipboard_append(text)
        self.ctx.status("Preamble copied -- paste it into a system prompt", "good")

    def _budget(self) -> None:
        self.ctx.status("Computing token budget ...", "busy")

        def work():
            return exportmod.budget_report(self.store)

        self.ctx.job.run(work, "budget_done", "export_error")
        self.ctx.job.on("budget_done", lambda text: (
            self._show(text, "budget"),
            self.ctx.status("Budget computed", "good"),
        ))

    # ------------------------------------------------------------------ export
    def _choose_out(self) -> None:
        chosen = filedialog.askdirectory(title="Export destination")
        if chosen:
            self.out_field.set(chosen)

    def _export(self) -> None:
        destination = Path(self.out_field.get()).expanduser()
        counts = self.store.counts()
        if not counts["projects"]:
            messagebox.showinfo("Export", "Index at least one project first (Atlas tab).")
            return
        if not messagebox.askyesno(
            "Export LLM pack",
            f"Write ATLAS.md and LLM_GUIDE.md into {destination},\n"
            f"and {counts['projects']} INDEX.md files under .atlas/index/?\n\n"
            "Existing versions of those generated files are replaced.",
        ):
            return
        self.ctx.status("Exporting ...", "busy")

        def work():
            return exportmod.export_all(self.store, destination=destination)

        self.ctx.job.run(work, "export_done", "export_error")

    def _export_done(self, result: exportmod.ExportResult) -> None:
        self.preview.set(
            result.render()
            + "\n\nHand a model LLM_GUIDE.md and ATLAS.md. It reads one project's\n"
              "INDEX.md when it needs to, and fetches slices by address after that.\n"
              "That is the whole protocol."
        )
        self.cost_var.set(f"pack {result.pack_tokens:,} tok  |  {result.ratio:.0f}x")
        self.ctx.broadcast("refresh")
        self.ctx.status(
            f"Exported {len(result.written)} files -- {result.pack_tokens:,} tokens "
            f"({result.ratio:.0f}x smaller than the sources)", "good",
        )

    def _error(self, message: str) -> None:
        self.preview.set(str(message))
        self.ctx.status("Export failed", "bad")

    def _copy(self) -> None:
        self.ctx.app.clipboard_clear()
        self.ctx.app.clipboard_append(self.preview.get())
        self.ctx.status("Pane copied to clipboard", "good")


_PRIMER = """EXPORT

Three artifacts make up the pack a third-party model is handed:

  ATLAS.md        tier 0. Every bucket, every project, one line each. 1-3 KB.
                  The only file that must always be read.

  INDEX.md        tier 1, one per project. Every class and function as a single
                  line: kind, line span, body hash, signature, what it calls and
                  what calls it. No bodies.

  LLM_GUIDE.md    the protocol itself. Read the atlas, read the index, fetch slices
                  by address, run the dedupe gate before writing, let the engine
                  choose placement, retire instead of deleting.

The table on the left shows, per project, what its index costs to read against what
reading its sources would have cost. That ratio is the entire reason this exists.
"""
