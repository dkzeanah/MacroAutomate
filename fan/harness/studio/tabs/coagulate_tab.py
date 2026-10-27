"""Coagulate tab -- reconcile N copies of one project, and find duplication everywhere.

Two views. **Variant families** is for the case where the same project lives in nine
folders and you need one of them, with proof nothing was dropped. **Duplicates** is the
whole-universe view: every group of symbols that are the same thing, and what collapsing
them would reclaim.

Nothing here writes until you press Coagulate, and the dry run shows the exact plan.
"""

from __future__ import annotations

import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from atlas import coagulate as coagulatemod
from atlas import similar as similarmod
from atlas import variants as variantsmod
from atlas.variants import CONFLICT, COSMETIC, STRUCTURAL, UNANIMOUS, UNIQUE
from studio.widgets import (
    MONO, UI, UI_BOLD, Field, SortableTable, TextPane, button, separator, toolbar,
)

STATUS_TAG = {
    CONFLICT: "bad",
    UNIQUE: "warn",
    STRUCTURAL: "hot",
    COSMETIC: (),
    UNANIMOUS: "dim",
}


class CoagulateTab:
    def __init__(self, parent: ttk.Frame, context) -> None:
        self.ctx = context
        self.store = context.store
        self._families: list = []
        self._family = None
        self._plan = None
        self._clusters: list = []

        self.book = ttk.Notebook(parent)
        self.book.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)
        self._build_variants()
        self._build_dupes()

        self.ctx.job.on("families_done", self._families_done)
        self.ctx.job.on("plan_done", self._plan_done)
        self.ctx.job.on("coag_done", self._coag_done)
        self.ctx.job.on("dupes_done", self._dupes_done)
        self.ctx.job.on("coag_error", self._error)

    # ------------------------------------------------------------ variants view
    def _build_variants(self) -> None:
        page = ttk.Frame(self.book)
        self.book.add(page, text="Variant families")

        bar = toolbar(page)
        button(bar, "Detect families", self._detect)
        button(bar, "Build plan", self._build_plan)
        separator(bar)
        self.policy = Field(bar, "Policy", "newest", width=9,
                            values=["newest", "richest", "lead"])
        self.policy.pack(side=tk.LEFT)
        self.lead = Field(bar, "Lead variant", width=34, values=[])
        self.lead.pack(side=tk.LEFT, padx=(8, 0))
        separator(bar)
        button(bar, "Dry run", lambda: self._coagulate(False))
        button(bar, "COAGULATE", lambda: self._coagulate(True))

        options = ttk.Frame(page, padding=(6, 0))
        options.pack(fill=tk.X)
        self.out_field = Field(options, "Output", width=62)
        self.out_field.pack(side=tk.LEFT)
        button(options, "Browse", self._choose_out)
        ttk.Label(
            options,
            text="Source folders are never modified. Everything not adopted is archived "
                 "under .coagulate/archive.",
            font=UI, foreground="#666666",
        ).pack(side=tk.LEFT, padx=12)

        panes = ttk.PanedWindow(page, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True, pady=(6, 0))

        left = ttk.PanedWindow(panes, orient=tk.VERTICAL)
        top = ttk.Frame(left)
        ttk.Label(top, text="FAMILIES", font=UI_BOLD).pack(anchor="w", pady=(0, 3))
        self.families = SortableTable(
            top, ["family", "variants", "shared", "overlap"],
            ["family", "n", "files", "code"],
            [200, 34, 48, 52], ["w", "e", "e", "e"],
            on_select=self._family_selected, height=7,
        )
        self.families.pack(fill=tk.BOTH, expand=True)
        left.add(top, weight=1)

        mid = ttk.Frame(left)
        ttk.Label(mid, text="VARIANTS", font=UI_BOLD).pack(anchor="w", pady=(4, 3))
        self.variants = SortableTable(
            mid, ["variant", "modified", "symbols", "files"],
            ["folder", "modified", "sym", "files"],
            [230, 108, 46, 44], ["w", "w", "e", "e"], height=7,
        )
        self.variants.pack(fill=tk.BOTH, expand=True)
        left.add(mid, weight=1)

        bottom = ttk.Frame(left)
        ttk.Label(bottom, text="SYMBOL SLOTS", font=UI_BOLD).pack(anchor="w", pady=(4, 3))
        self.slots = SortableTable(
            bottom, ["status", "name", "path", "n", "adopted"],
            ["status", "symbol", "file", "v", "adopted from"],
            [76, 168, 168, 26, 150], ["w", "w", "w", "e", "w"],
            on_select=self._slot_selected, height=14,
        )
        self.slots.pack(fill=tk.BOTH, expand=True)
        filters = ttk.Frame(bottom)
        filters.pack(fill=tk.X, pady=(4, 0))
        self.only_interesting = tk.BooleanVar(value=True)
        ttk.Checkbutton(filters, text="hide unanimous slots",
                        variable=self.only_interesting,
                        command=self._render_slots).pack(side=tk.LEFT)
        left.add(bottom, weight=3)
        panes.add(left, weight=3)

        right = ttk.Frame(panes)
        head = ttk.Frame(right)
        head.pack(fill=tk.X)
        ttk.Label(head, text="PLAN / DETAIL", font=UI_BOLD).pack(side=tk.LEFT, pady=(0, 3))
        self.balance_var = tk.StringVar(value="")
        ttk.Label(head, textvariable=self.balance_var, font=("Consolas", 9, "bold"),
                  foreground="#0a7d28").pack(side=tk.RIGHT)
        self.report = TextPane(right, font=MONO)
        self.report.pack(fill=tk.BOTH, expand=True)
        self.report.set(_PRIMER)
        panes.add(right, weight=4)

    # -------------------------------------------------------------- dupes view
    def _build_dupes(self) -> None:
        page = ttk.Frame(self.book)
        self.book.add(page, text="Duplicates")

        bar = toolbar(page)
        button(bar, "Scan for duplicates", self._scan_dupes)
        separator(bar)
        self.cross_only = tk.BooleanVar(value=True)
        ttk.Checkbutton(bar, text="cross-project only",
                        variable=self.cross_only).pack(side=tk.LEFT, padx=4)
        self.exact_only = tk.BooleanVar(value=False)
        ttk.Checkbutton(bar, text="exact matches only (faster)",
                        variable=self.exact_only).pack(side=tk.LEFT, padx=4)
        self.min_lines = Field(bar, "Min lines", "6", width=4)
        self.min_lines.pack(side=tk.LEFT, padx=(8, 0))

        panes = ttk.PanedWindow(page, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True, pady=(6, 0))

        left = ttk.Frame(panes)
        head = ttk.Frame(left)
        head.pack(fill=tk.X)
        ttk.Label(head, text="CLUSTERS", font=UI_BOLD).pack(side=tk.LEFT, pady=(0, 3))
        self.dupe_summary = tk.StringVar(value="")
        ttk.Label(head, textvariable=self.dupe_summary, font=("Consolas", 9),
                  foreground="#0a7d28").pack(side=tk.RIGHT)
        self.dupes = SortableTable(
            left, ["relation", "symbol", "copies", "reclaim", "projects"],
            ["relation", "symbol", "x", "-lines", "found in"],
            [86, 190, 34, 58, 300], ["w", "w", "e", "e", "w"],
            on_select=self._cluster_selected, height=26,
        )
        self.dupes.pack(fill=tk.BOTH, expand=True)
        panes.add(left, weight=3)

        right = ttk.Frame(panes)
        ttk.Label(right, text="MEMBERS", font=UI_BOLD).pack(anchor="w", pady=(0, 3))
        self.dupe_detail = TextPane(right, font=MONO)
        self.dupe_detail.pack(fill=tk.BOTH, expand=True)
        self.dupe_detail.set(_DUPE_PRIMER)
        panes.add(right, weight=3)

    # ------------------------------------------------------------------- actions
    def on_refresh(self) -> None:
        pass

    def on_show(self) -> None:
        if not self._families:
            self.report.set(_PRIMER)

    def _detect(self) -> None:
        self.ctx.status("Detecting variant families ...", "busy")
        self.ctx.job.run(
            lambda: variantsmod.detect_families(self.store),
            "families_done", "coag_error",
        )

    def _families_done(self, families: list) -> None:
        self._families = families
        self.families.set_rows([
            {"family": f.key, "variants": f.size, "shared": f.shared_paths,
             "overlap": f"{f.shape_overlap:.0%}"}
            for f in families
        ])
        if not families:
            self.report.set(
                "No variant families found.\n\n"
                "Index two or more copies of the same project first (Atlas tab -> "
                "Sweep + Index, or Add project), then detect again."
            )
            self.ctx.status("No variant families found", "warn")
            return
        self.ctx.status(f"{len(families)} variant family(ies) found", "good")
        self.report.set("\n".join(f.describe() for f in families))

    def _family_selected(self, row: dict) -> None:
        self._family = next((f for f in self._families if f.key == row["family"]), None)
        if self._family is None:
            return
        self.variants.set_rows([
            {"variant": v.name, "modified": v.when, "symbols": v.symbol_count,
             "files": v.file_count,
             "_tags": ("hot",) if v is self._family.newest else ()}
            for v in self._family.variants
        ])
        self.lead.set_values([v.name for v in self._family.variants])
        if not self.out_field.get():
            self.out_field.set(str(self.ctx.workspace / "coagulated" / self._family.key))
        self.report.set(
            self._family.describe() + "\n\n"
            + "\n".join(
                f"  {v.name}\n      {v.root}\n      modified {v.when}, "
                f"{v.symbol_count} symbols, {v.file_count} files"
                for v in self._family.variants
            )
            + "\n\nBuild plan to align every symbol across these folders."
        )

    def _build_plan(self) -> None:
        if self._family is None:
            messagebox.showinfo("Plan", "Select a family first.")
            return
        policy = self.policy.get() or "newest"
        lead = self.lead.get()
        if policy == "lead" and not lead:
            messagebox.showinfo("Plan", "Policy 'lead' needs a lead variant.")
            return
        self.ctx.status(f"Aligning {self._family.size} variants ...", "busy")
        family = self._family
        self.ctx.job.run(
            lambda: variantsmod.align(self.store, family, policy=policy, lead=lead),
            "plan_done", "coag_error",
        )

    def _plan_done(self, plan) -> None:
        self._plan = plan
        self._render_slots()
        self.report.set(plan.render(limit=40))
        ok, message = plan.balanced()
        self.balance_var.set(("BALANCED " if ok else "UNBALANCED ") + message)
        conflicts = len(plan.conflicts)
        self.ctx.status(
            f"{len(plan.slots)} slots, {conflicts} conflict(s), "
            f"{len(plan.by_status(UNIQUE))} only-in-one-variant",
            "warn" if conflicts else "good",
        )

    def _render_slots(self) -> None:
        if self._plan is None:
            return
        rows = []
        for slot in self._plan.slots:
            if self.only_interesting.get() and slot.status == UNANIMOUS:
                continue
            rows.append({
                "status": slot.status,
                "name": slot.name,
                "path": slot.path,
                "n": len(slot.versions),
                "adopted": slot.chosen.variant[:28] if slot.chosen else "(held)",
                "_tags": (STATUS_TAG.get(slot.status) or (),)
                if isinstance(STATUS_TAG.get(slot.status), str) else (),
            })
        self.slots.set_rows(rows)

    def _slot_selected(self, row: dict) -> None:
        if self._plan is None:
            return
        slot = next(
            (s for s in self._plan.slots
             if s.name == row["name"] and s.path == row["path"]), None
        )
        if slot is None:
            return
        out = [
            f"{slot.path}#{slot.name}",
            "=" * 70,
            f"status   {slot.status}",
            f"decision {slot.reason}",
            f"adopted  {slot.chosen.variant if slot.chosen else '(held -- no decision)'}",
            "",
        ]
        for version in sorted(slot.versions, key=lambda v: -v.mtime):
            mark = "  <== ADOPTED" if version is slot.chosen else ""
            out += [
                "-" * 70,
                f"{version.variant}   {version.entry.lines}L   "
                f"{version.disposition}{mark}",
                f"{version.entry.path} L{version.entry.line_start}-"
                f"{version.entry.line_end}",
            ]
            if version.attic_path:
                out.append(f"archived to: {version.attic_path}")
            out.append("")
            out.append(version.entry.code)
            out.append("")
        self.report.set("\n".join(out))

    def _choose_out(self) -> None:
        chosen = filedialog.askdirectory(title="Where to write the merged project")
        if chosen:
            self.out_field.set(chosen)

    def _coagulate(self, write: bool) -> None:
        if self._plan is None:
            messagebox.showinfo("Coagulate", "Build a plan first.")
            return
        destination = Path(self.out_field.get() or
                           (self.ctx.workspace / "coagulated" / self._plan.family.key))

        if write:
            conflicts = len(self._plan.conflicts)
            note = (
                f"\n\n{conflicts} conflict(s) will be written from the base variant and "
                f"flagged in-file with a comment naming every alternative. Nothing is "
                f"discarded either way."
                if conflicts else ""
            )
            if not messagebox.askyesno(
                "Coagulate",
                f"Merge {self._plan.family.size} variants into:\n{destination}\n\n"
                f"Source folders are not modified. Every non-adopted version is written "
                f"to .coagulate/archive first, then the output is re-scanned and "
                f"verified.{note}\n\nProceed?",
            ):
                return

        self.ctx.status("Coagulating ..." if write else "Dry run ...", "busy")
        plan = self._plan
        self.ctx.job.run(
            lambda: coagulatemod.execute(self.store, plan, destination, dry_run=not write),
            "coag_done", "coag_error",
        )

    def _coag_done(self, result) -> None:
        body = result.render()
        if result.builds:
            body += "\n\nFILES\n" + "\n".join(b.describe() for b in result.builds[:200])
        self.report.set(body)
        if result.dry_run:
            self.ctx.status("Dry run complete -- nothing written", "info")
            return
        if result.verification.ok:
            self.balance_var.set("VERIFIED")
            self.ctx.status(
                f"Coagulated to {result.destination} -- verified "
                f"{result.verification.present}/{result.verification.checked} symbols, "
                f"{result.verification.files_present}/{result.verification.files_expected} files",
                "good",
            )
        else:
            self.balance_var.set("VERIFICATION FAILED")
            self.ctx.status("Verification FAILED -- keep the source folders", "bad")
        self.ctx.broadcast("refresh")

    # -------------------------------------------------------------------- dupes
    def _scan_dupes(self) -> None:
        try:
            min_lines = int(self.min_lines.get())
        except ValueError:
            min_lines = 6
        cross = self.cross_only.get()
        exact = self.exact_only.get()
        self.ctx.status("Normalizing and clustering every indexed symbol ...", "busy")

        def work():
            entries, problems = similarmod.load_entries(
                self.store, None, min_lines=min_lines
            )
            clusters = similarmod.cluster(
                entries, include_near=not exact, cross_project_only=cross
            )
            return clusters, len(entries), problems

        self.ctx.job.run(work, "dupes_done", "coag_error")

    def _dupes_done(self, payload) -> None:
        clusters, scanned, problems = payload
        self._clusters = clusters
        self.dupes.set_rows([
            {
                "relation": c.relation,
                "symbol": c.members[0].leaf,
                "copies": c.size,
                "reclaim": c.wasted_lines,
                "projects": ", ".join(sorted(c.projects)),
                "_tags": ("hot",) if c.lossless else
                         (("warn",) if c.relation == "near" else ()),
            }
            for c in clusters
        ])
        reclaimable = sum(c.wasted_lines for c in clusters if c.lossless)
        self.dupe_summary.set(
            f"{len(clusters)} clusters | {reclaimable:,} lines reclaimable with zero risk"
        )
        self.dupe_detail.set(similarmod.duplication_report(clusters, limit=60))
        self.ctx.status(
            f"{len(clusters)} duplicate clusters across {scanned} symbols", "good"
        )

    def _cluster_selected(self, row: dict) -> None:
        match = next(
            (c for c in self._clusters
             if c.members[0].leaf == row["symbol"] and str(c.size) == str(row["copies"])),
            None,
        )
        if match is None:
            return
        out = [
            f"{match.relation.upper()}  x{match.size}  {match.members[0].leaf}",
            "=" * 70,
            f"reclaimable: {match.wasted_lines} lines",
            f"safe to collapse without review: {'yes' if match.lossless else 'no'}",
            "",
        ]
        canonical = match.canonical()
        for member in sorted(match.members, key=lambda m: -m.mtime):
            mark = "  <== newest, best canonical" if member is canonical else ""
            out.append(f"  {member.address}  ({member.lines}L){mark}")
        out += ["", "-" * 70, "", canonical.code]
        self.dupe_detail.set("\n".join(out))

    def _error(self, message: str) -> None:
        self.report.set(str(message))
        self.dupe_detail.set(str(message))
        self.ctx.status("Failed -- see the detail pane", "bad")


_PRIMER = """COAGULATE

For when the same project lives in nine folders and you need one of them.

  1. DETECT FAMILIES  Groups folders that are copies of one project, using both
                      file-path overlap and structural code overlap -- so a copy
                      whose tree was reorganised is still recognised.

  2. BUILD PLAN       Aligns every symbol across every variant at once and classifies
                      it: unanimous, cosmetic, structural, only-in-one-variant, or a
                      real conflict. Module-level content -- imports, `__main__`
                      blocks -- is tracked too, because a branch whose entire change
                      was adding one import has no differing symbol.

  3. DRY RUN          Shows exactly what would be written, with an accounting line
                      proving every version of every symbol has a disposition.

  4. COAGULATE        Archives everything not adopted FIRST, assembles the output,
                      parses every file before keeping it, then re-scans the result
                      from disk and confirms every adopted symbol arrived intact.

Conflicts are never resolved silently. They are written from the base variant and
flagged in-file with a comment naming every alternative and where it is archived.

Source folders are never modified.
"""

_DUPE_PRIMER = """DUPLICATES

Every group of symbols that are the same thing, across everything indexed.

  IDENTICAL    byte for byte -- collapsing loses nothing
  FORMATTING   same code, different style or docstrings -- also lossless
  RENAMED      same structure, different local names or literal values
  NEAR         substantially overlapping -- read both before merging

Matching is structural, not textual: local variables are alpha-renamed and literals
erased before hashing, so the same function copied nine times and re-styled in each
still collapses to one cluster.
"""
