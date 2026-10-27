"""Index tab -- the symbol browser and the slice viewer.

This is the tab that makes the argument visible: pick any symbol out of tens of
thousands and you get its code, its callers and its callees, at a cost of a couple of
hundred tokens, without opening a file.
"""

from __future__ import annotations

import tkinter as tk
from tkinter import messagebox, ttk

from atlas import slicer
from atlas.slicer import SliceError
from atlas.spec import KIND_NAMES, token_estimate
from studio.widgets import (
    MONO, UI, UI_BOLD, Field, SortableTable, TextPane, button, separator, toolbar,
)


class IndexTab:
    def __init__(self, parent: ttk.Frame, context) -> None:
        self.ctx = context
        self.store = context.store
        self._current_address = ""

        bar = toolbar(parent)
        self.search = Field(bar, "Search symbols", width=40)
        self.search.pack(side=tk.LEFT)
        self.search.widget.bind("<Return>", lambda e: self.refresh_symbols())
        button(bar, "Search", self.refresh_symbols)
        separator(bar)
        self.project_filter = Field(bar, "Project", width=24, values=["(all)"])
        self.project_filter.pack(side=tk.LEFT)
        self.project_filter.set("(all)")
        self.project_filter.widget.bind("<<ComboboxSelected>>",
                                        lambda e: self.refresh_symbols())
        self.kind_filter = Field(bar, "Kind", width=10,
                                 values=["(all)", "class", "function", "private",
                                         "async", "constant"])
        self.kind_filter.pack(side=tk.LEFT)
        self.kind_filter.set("(all)")
        self.kind_filter.widget.bind("<<ComboboxSelected>>",
                                     lambda e: self.refresh_symbols())
        separator(bar)
        button(bar, "Expand +1 hop", self._expand)
        button(bar, "Impact", self._impact)
        button(bar, "Copy address", self._copy_address)
        separator(bar)
        button(bar, "Mirror comments", self._mirror)

        panes = ttk.PanedWindow(parent, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

        left = ttk.Frame(panes)
        head = ttk.Frame(left)
        head.pack(fill=tk.X)
        ttk.Label(head, text="SYMBOLS", font=UI_BOLD).pack(side=tk.LEFT, pady=(0, 3))
        self.count_var = tk.StringVar(value="")
        ttk.Label(head, textvariable=self.count_var, font=UI,
                  foreground="#666666").pack(side=tk.RIGHT)
        self.symbols = SortableTable(
            left,
            ["kind", "name", "span", "lines", "project", "path", "in", "out", "flags"],
            ["k", "symbol", "span", "L", "project", "file", "<-", "->", "fl"],
            [24, 236, 88, 42, 118, 176, 34, 34, 34],
            ["c", "w", "w", "e", "w", "w", "e", "e", "c"],
            on_select=self._symbol_selected,
            height=28,
        )
        self.symbols.pack(fill=tk.BOTH, expand=True)
        panes.add(left, weight=3)

        right = ttk.PanedWindow(panes, orient=tk.VERTICAL)

        top = ttk.Frame(right)
        head2 = ttk.Frame(top)
        head2.pack(fill=tk.X)
        ttk.Label(head2, text="SLICE", font=UI_BOLD).pack(side=tk.LEFT, pady=(0, 3))
        self.cost_var = tk.StringVar(value="")
        ttk.Label(head2, textvariable=self.cost_var, font=("Consolas", 9),
                  foreground="#0a7d28").pack(side=tk.RIGHT)
        self.slice_pane = TextPane(top, font=MONO, height=22)
        self.slice_pane.pack(fill=tk.BOTH, expand=True)
        right.add(top, weight=3)

        bottom = ttk.Frame(right)
        ttk.Label(bottom, text="EDGES  (-> calls out   <- called by)",
                  font=UI_BOLD).pack(anchor="w", pady=(4, 3))
        self.edges = TextPane(bottom, font=MONO, wrap=tk.WORD, height=10)
        self.edges.pack(fill=tk.BOTH, expand=True)
        right.add(bottom, weight=1)

        panes.add(right, weight=4)

    # ----------------------------------------------------------------- refresh
    def on_refresh(self) -> None:
        self._reload_projects()
        self.refresh_symbols()

    def on_show(self) -> None:
        self._reload_projects()
        if not self.symbols.row_count():
            self.refresh_symbols()

    def _reload_projects(self) -> None:
        names = ["(all)"] + [p.name for p in self.store.projects()]
        self.project_filter.set_values(names)

    def refresh_symbols(self) -> None:
        needle = self.search.get()
        project = self.project_filter.get()
        kind_label = self.kind_filter.get()
        kind = next((k for k, v in KIND_NAMES.items() if v == kind_label), None)

        clauses, params = [], []
        if project and project != "(all)":
            clauses.append("p.name = ?")
            params.append(project)
        if kind:
            clauses.append("s.kind = ?")
            params.append(kind)
        if needle:
            clauses.append("(lower(s.name) LIKE ? OR lower(s.signature) LIKE ? "
                           "OR lower(s.doc) LIKE ?)")
            like = f"%{needle.lower()}%"
            params += [like, like, like]
        where = (" WHERE " + " AND ".join(clauses)) if clauses else ""

        rows = self.store.many(
            "SELECT s.*, p.name AS project, p.priority AS priority "
            "FROM symbols s JOIN projects p ON p.id = s.project_id" + where +
            " ORDER BY p.priority DESC, p.name, s.path, s.line_start LIMIT 3000",
            params,
        )

        out = []
        for row in rows:
            ins = len([c for c in (row["called_by"] or "").split(",") if c])
            outs = len([c for c in (row["calls"] or "").split(",") if c])
            tags = []
            if "X" in (row["flags"] or ""):
                tags.append("dim")
            elif "e" in (row["flags"] or ""):
                tags.append("dim")
            elif ins >= 5:
                tags.append("hot")
            out.append({
                "kind": row["kind"],
                "name": row["name"],
                "span": f"L{row['line_start']}-{row['line_end']}",
                "lines": int(row["line_end"]) - int(row["line_start"]) + 1,
                "project": row["project"],
                "path": row["path"],
                "in": ins,
                "out": outs,
                "flags": row["flags"] or "",
                "_address": row["address"],
                "_tags": tuple(tags),
            })
        self.symbols.set_rows(out)
        self.count_var.set(f"{len(out)} shown"
                           + (" (capped at 3000)" if len(out) >= 3000 else ""))

    # ------------------------------------------------------------------ events
    def _address_for(self, row: dict) -> str:
        matches = [
            r for r in self.symbols._rows
            if r["name"] == row["name"] and r["path"] == row["path"]
            and r["project"] == row["project"]
        ]
        return matches[0]["_address"] if matches else ""

    def _symbol_selected(self, row: dict) -> None:
        address = self._address_for(row)
        if not address:
            return
        self._current_address = address
        try:
            piece = slicer.get(self.store, address)
        except (SliceError, ValueError) as exc:
            self.slice_pane.set(f"# {exc}")
            self.cost_var.set("")
            return

        self.slice_pane.set(piece.render())
        self.slice_pane.highlight_atlas()
        self.cost_var.set(f"{piece.tokens} tokens" + ("   STALE" if piece.stale else ""))

        lines = [f"address   {piece.address}", f"file      {piece.path}",
                 f"span      L{piece.line_start}-{piece.line_end}  "
                 f"({piece.line_end - piece.line_start + 1} lines)",
                 f"hash      {piece.body_hash}"]
        if piece.flags:
            lines.append(f"flags     {piece.flags}")
        if piece.doc:
            lines.append(f'doc       "{piece.doc}"')
        lines.append("")
        lines.append(f"-> CALLS OUT ({len(piece.calls)})  read these to understand it")
        lines += [f"     {c}" for c in piece.calls] or ["     (nothing)"]
        lines.append("")
        lines.append(f"<- CALLED BY ({len(piece.called_by)})  check these before changing it")
        lines += [f"     {c}" for c in piece.called_by] or ["     (nothing -- entry point or unused)"]
        self.edges.set("\n".join(lines))

    def _expand(self) -> None:
        if not self._current_address:
            return
        pieces = slicer.expand(self.store, self._current_address, depth=1, budget_tokens=6000)
        if not pieces:
            return
        body = "\n\n".join(p.render() for p in pieces)
        total = sum(p.tokens for p in pieces)
        self.slice_pane.set(
            f"# EXPANDED {self._current_address} (+1 hop): "
            f"{len(pieces)} slices, {total} tokens\n\n" + body
        )
        self.slice_pane.highlight_atlas()
        self.cost_var.set(f"{total} tokens / {len(pieces)} slices")
        self.ctx.status(f"Expanded to {len(pieces)} slices ({total} tokens)", "good")

    def _impact(self) -> None:
        if not self._current_address:
            return
        rows = slicer.impact(self.store, self._current_address)
        if not rows:
            self.edges.set(f"Nothing calls {self._current_address}.\n\n"
                           "Safe to change in isolation, or it is dead code.")
            return
        lines = [f"IMPACT OF CHANGING {self._current_address}",
                 f"{len(rows)} caller(s) must be checked:", ""]
        for row in rows:
            lines.append(f"  {row['address']}")
            lines.append(f"      L{row['line_start']}-{row['line_end']}  {row['signature'][:90]}")
        self.edges.set("\n".join(lines))
        self.ctx.status(f"{len(rows)} caller(s) of that symbol", "warn")

    def _copy_address(self) -> None:
        if not self._current_address:
            return
        self.ctx.app.clipboard_clear()
        self.ctx.app.clipboard_append(self._current_address)
        self.ctx.status(f"Copied {self._current_address}", "good")

    def _mirror(self) -> None:
        project = self.project_filter.get()
        if not project or project == "(all)":
            messagebox.showinfo("Mirror", "Pick a single project first.")
            return
        row = self.store.project_by_name(project)
        if row is None:
            return
        preview = slicer.mirror_comments(self.store, row.id, dry_run=True)
        self.slice_pane.set(
            "MIRROR COMMENT PREVIEW (dry run -- nothing written)\n"
            "Writes one `# @atlas` line above each symbol so a slice carries its\n"
            "own edges when read outside this tool.\n\n" + "\n".join(preview)
        )
        if not messagebox.askyesno(
            "Mirror comments",
            f"Write @atlas edge comments into {project}'s source files?\n\n"
            "Every touched file is backed up to .atlas/backups first, and the pass is\n"
            "idempotent -- running it again replaces the comments rather than stacking them.",
        ):
            return

        from atlas.ledger import Ledger
        from pathlib import Path
        ledger = Ledger(self.store)
        paths = {Path(row.root) / r["path"] for r in self.store.symbols(row.id)}
        backup = ledger.snapshot(list(paths), "mirror", f"before mirroring {project}")
        report = slicer.mirror_comments(self.store, row.id, dry_run=False)
        self.slice_pane.set(
            f"MIRRORED {project}\nbacked up {len(backup.files)} files to "
            f"{backup.directory}\nledger #{backup.ledger_id}\n\n" + "\n".join(report)
        )
        self.ctx.status(f"Mirrored {project} (ledger #{backup.ledger_id})", "good")
        self.ctx.broadcast("refresh")
