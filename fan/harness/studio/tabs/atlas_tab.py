"""Atlas tab -- the twenty buckets, every project in them, and the sweep that fills them.

Three panes, all resizable: buckets on the left, projects in the middle, and the
evidence behind a classification on the right. The evidence pane is the point -- a
bucket assignment you cannot audit is a bucket assignment you cannot trust.
"""

from __future__ import annotations

import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from atlas import sweep as sweepmod
from atlas.buckets import BY_KEY, bucket_titles
from studio.widgets import (
    MONO, UI, UI_BOLD, Field, SortableTable, TextPane, button, separator, toolbar,
)

BUCKET_KEYS = [key for key, _t, _b in bucket_titles()]


class AtlasTab:
    def __init__(self, parent: ttk.Frame, context) -> None:
        self.ctx = context
        self.store = context.store
        self.parent = parent
        self._sweep_result: sweepmod.SweepResult | None = None
        self._candidates: dict[str, sweepmod.Candidate] = {}

        bar = toolbar(parent)
        self.root_field = Field(bar, "Scan root", self.store.get("scan_root"), width=52)
        self.root_field.pack(side=tk.LEFT)
        button(bar, "Browse", self._browse)
        separator(bar)
        button(bar, "Sweep", self._sweep)
        button(bar, "Sweep + Index", self._sweep_and_index)
        separator(bar)
        button(bar, "Add project", self._add_project)
        button(bar, "Re-index selected", self._reindex_selected)
        separator(bar)
        button(bar, "Refresh", self.refresh)

        panes = ttk.PanedWindow(parent, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

        # ---- buckets -------------------------------------------------------
        left = ttk.Frame(panes)
        ttk.Label(left, text="BUCKETS", font=UI_BOLD).pack(anchor="w", pady=(0, 3))
        self.buckets = SortableTable(
            left,
            ["bucket", "projects", "symbols", "lines"],
            ["bucket", "proj", "symbols", "lines"],
            [118, 46, 66, 74],
            ["w", "e", "e", "e"],
            on_select=self._bucket_selected,
            height=22,
        )
        self.buckets.pack(fill=tk.BOTH, expand=True)
        self.bucket_blurb = tk.StringVar(value="All buckets")
        ttk.Label(left, textvariable=self.bucket_blurb, font=UI, wraplength=300,
                  foreground="#555555").pack(anchor="w", pady=(4, 0))
        button(left, "Show all buckets", self._clear_bucket_filter, side=tk.TOP)
        panes.add(left, weight=1)

        # ---- projects ------------------------------------------------------
        middle = ttk.Frame(panes)
        head = ttk.Frame(middle)
        head.pack(fill=tk.X)
        ttk.Label(head, text="PROJECTS", font=UI_BOLD).pack(side=tk.LEFT, pady=(0, 3))
        self.filter_field = Field(head, "filter", width=22)
        self.filter_field.pack(side=tk.RIGHT)
        self.filter_field.var.trace_add("write", lambda *_: self.refresh_projects())

        self.projects = SortableTable(
            middle,
            ["name", "bucket", "priority", "files", "lines", "symbols", "indexed"],
            ["project", "bucket", "pri", "files", "lines", "symbols", "indexed"],
            [230, 100, 44, 52, 68, 66, 108],
            ["w", "w", "e", "e", "e", "e", "w"],
            on_select=self._project_selected,
            on_activate=lambda row: self.ctx.goto("index"),
            height=22,
        )
        self.projects.pack(fill=tk.BOTH, expand=True)

        controls = ttk.Frame(middle, padding=(0, 6, 0, 0))
        controls.pack(fill=tk.X)
        self.bucket_set = Field(controls, "Set bucket", width=16, values=BUCKET_KEYS)
        self.bucket_set.pack(side=tk.LEFT)
        button(controls, "Apply", self._apply_bucket)
        separator(controls)
        self.priority_set = Field(controls, "Priority", "50", width=5)
        self.priority_set.pack(side=tk.LEFT)
        button(controls, "Apply", self._apply_priority)
        button(controls, "Pin / unpin", self._toggle_pin)
        separator(controls)
        button(controls, "Remove from index", self._remove_project)
        panes.add(middle, weight=3)

        # ---- detail --------------------------------------------------------
        right = ttk.Frame(panes)
        ttk.Label(right, text="EVIDENCE & DETAIL", font=UI_BOLD).pack(anchor="w", pady=(0, 3))
        self.detail = TextPane(right, font=MONO, wrap=tk.WORD, height=30)
        self.detail.pack(fill=tk.BOTH, expand=True)
        panes.add(right, weight=2)

        self.ctx.job.on("sweep_done", self._sweep_done)
        self.ctx.job.on("sweep_error", self._job_error)
        self.ctx.job.on("index_done", self._index_done)
        self.ctx.job.on("index_error", self._job_error)
        self.ctx.job.on("sweep_progress", self._progress)

    # ----------------------------------------------------------------- refresh
    def on_refresh(self) -> None:
        self.refresh()

    def on_show(self) -> None:
        self.refresh()

    def refresh(self) -> None:
        self.refresh_buckets()
        self.refresh_projects()
        self.ctx.refresh_counts()

    def refresh_buckets(self) -> None:
        summary = {row["bucket"]: row for row in self.store.bucket_summary()}
        rows = []
        for key, _title, _blurb in bucket_titles():
            row = summary.get(key)
            rows.append({
                "bucket": key,
                "projects": row["projects"] if row else 0,
                "symbols": row["symbols"] if row else 0,
                "lines": row["lines"] if row else 0,
                "_tags": ("dim",) if not row else (),
            })
        self.buckets.set_rows(rows)

    def refresh_projects(self) -> None:
        needle = self.filter_field.get().lower()
        bucket = getattr(self, "_bucket_filter", None)
        rows = []
        for project in self.store.projects(bucket=bucket):
            if needle and needle not in f"{project.name} {project.bucket}".lower():
                continue
            tags = []
            if project.pinned:
                tags.append("hot")
            elif project.external:
                tags.append("dim")
            elif project.priority >= 80:
                tags.append("hot")
            rows.append({
                "name": ("* " if project.pinned else "") + project.name,
                "bucket": project.bucket,
                "priority": project.priority,
                "files": project.file_count,
                "lines": project.line_count,
                "symbols": project.symbol_count,
                "indexed": project.indexed_at or "-",
                "_tags": tuple(tags),
            })
        self.projects.set_rows(rows)

    # ------------------------------------------------------------------ events
    def _bucket_selected(self, row: dict) -> None:
        key = row["bucket"]
        self._bucket_filter = key
        bucket = BY_KEY.get(key)
        self.bucket_blurb.set(f"{bucket.title}: {bucket.blurb}" if bucket else key)
        self.refresh_projects()

    def _clear_bucket_filter(self) -> None:
        self._bucket_filter = None
        self.bucket_blurb.set("All buckets")
        self.refresh_projects()

    def _selected_project_name(self) -> str | None:
        row = self.projects.selected()
        if not row:
            return None
        return row["name"].lstrip("* ").strip()

    def _project_selected(self, _row: dict) -> None:
        name = self._selected_project_name()
        if not name:
            return
        project = self.store.project_by_name(name)
        if project is None:
            return
        lines = [
            f"@{project.bucket}/{project.name}",
            "=" * 62,
            f"root        {project.root}",
            f"bucket      {project.bucket}",
            f"priority    {project.priority}" + ("   PINNED" if project.pinned else ""),
            f"external    {'yes -- vendored, do not edit' if project.external else 'no'}",
            f"indexed     {project.indexed_at or 'never'}",
            f"size        {project.file_count} files / {project.line_count:,} lines "
            f"/ {project.symbol_count} symbols",
            "",
            "CLASSIFICATION EVIDENCE",
            "-" * 62,
            project.verdict or "(none recorded)",
            "",
        ]
        candidate = self._candidates.get(name)
        if candidate:
            lines += [
                "SWEEP NOTES",
                "-" * 62,
                f"detected as project: {candidate.reason}",
                f"source files: {candidate.source_files} of {candidate.total_files}",
                "",
            ]
        top = self.store.many(
            "SELECT name, path, line_start, line_end, called_by FROM symbols "
            "WHERE project_id = ? ORDER BY (line_end - line_start) DESC LIMIT 12",
            (project.id,),
        )
        if top:
            lines += ["LARGEST SYMBOLS", "-" * 62]
            for row in top:
                size = int(row["line_end"]) - int(row["line_start"]) + 1
                callers = len([c for c in (row["called_by"] or "").split(",") if c])
                lines.append(f"  {size:>4}L  {row['name'][:44]:<44} <-{callers}")
        self.detail.set("\n".join(lines))

    # ------------------------------------------------------------------ actions
    def _browse(self) -> None:
        chosen = filedialog.askdirectory(title="Folder containing your projects",
                                         initialdir=self.root_field.get() or str(Path.home()))
        if chosen:
            self.root_field.set(chosen)
            self.store.set("scan_root", chosen)

    def _sweep(self, then_index: bool = False) -> None:
        root = Path(self.root_field.get()).expanduser()
        if not root.exists():
            messagebox.showerror("Sweep", f"{root} does not exist")
            return
        self.store.set("scan_root", str(root))
        self.ctx.status(f"Sweeping {root} ...", "busy")
        self.detail.set(f"Sweeping {root} ...\n")
        self._then_index = then_index

        def work():
            def progress(i, total, name):
                self.ctx.job.post("sweep_progress", f"[{i + 1}/{total}] {name}")
            return sweepmod.sweep(root, progress=progress)

        self.ctx.job.run(work, "sweep_done", "sweep_error")

    def _sweep_and_index(self) -> None:
        self._sweep(then_index=True)

    def _progress(self, message: str) -> None:
        self.ctx.status(message, "busy")

    def _sweep_done(self, result: sweepmod.SweepResult) -> None:
        self._sweep_result = result
        self._candidates = {c.name: c for c in result.candidates}
        self.detail.set(result.render())
        self.ctx.status(
            f"Swept {result.root}: {len(result.projects)} projects, "
            f"{len(result.skipped)} skipped", "good",
        )
        if getattr(self, "_then_index", False):
            self._then_index = False
            self._index_candidates(result.projects)

    def _index_candidates(self, candidates: list) -> None:
        if not candidates:
            messagebox.showinfo("Index", "Nothing to index -- run a sweep first.")
            return
        if len(candidates) > 25 and not messagebox.askyesno(
            "Index",
            f"Index {len(candidates)} projects? This reads every source file once "
            f"and can take a few minutes.",
        ):
            return
        self.ctx.status(f"Indexing {len(candidates)} projects ...", "busy")

        def work():
            def progress(i, total, name):
                self.ctx.job.post("sweep_progress", f"indexing [{i + 1}/{total}] {name}")
            return sweepmod.index_candidates(self.store, candidates, progress=progress)

        self.ctx.job.run(work, "index_done", "index_error")

    def _index_done(self, result: sweepmod.SweepResult) -> None:
        self.refresh()
        self.ctx.broadcast("refresh")
        message = f"Indexed {len(result.indexed)} projects"
        if result.errors:
            message += f", {len(result.errors)} failed"
            self.detail.append("\n\nINDEX ERRORS\n" + "\n".join(
                f"  ! {e}" for e in result.errors[:30]))
        self.ctx.status(message, "good" if not result.errors else "warn")

    def _job_error(self, message: str) -> None:
        self.ctx.status("Failed -- see detail pane", "bad")
        self.detail.set(str(message))

    def _add_project(self) -> None:
        chosen = filedialog.askdirectory(title="Project folder to index")
        if not chosen:
            return
        path = Path(chosen)
        is_project, reason, sources, total = sweepmod.looks_like_project(path)
        if not is_project and not messagebox.askyesno(
            "Add project", f"{path.name} does not look like a project ({reason}).\nIndex it anyway?"
        ):
            return
        candidate = sweepmod.Candidate(
            path=path, name=path.name, is_project=True, reason=reason,
            source_files=sources, total_files=total,
        )
        from atlas.buckets import classify
        candidate.verdict = classify(path)
        candidate.priority = 60
        self._index_candidates([candidate])

    def _reindex_selected(self) -> None:
        rows = self.projects.selected_all()
        if not rows:
            messagebox.showinfo("Re-index", "Select one or more projects first.")
            return
        candidates = []
        for row in rows:
            project = self.store.project_by_name(row["name"].lstrip("* ").strip())
            if project is None:
                continue
            candidate = sweepmod.Candidate(
                path=Path(project.root), name=project.name, is_project=True,
                reason="re-index", source_files=project.file_count,
                total_files=project.file_count,
            )
            from atlas.buckets import Verdict
            candidate.verdict = Verdict(project.bucket, 100.0, signals=["existing"])
            candidate.priority = project.priority
            candidate.external = bool(project.external)
            candidates.append(candidate)
        self._index_candidates(candidates)

    def _apply_bucket(self) -> None:
        bucket = self.bucket_set.get()
        if bucket not in BY_KEY:
            messagebox.showerror("Bucket", f"'{bucket}' is not one of the twenty buckets.")
            return
        changed = 0
        for row in self.projects.selected_all():
            project = self.store.project_by_name(row["name"].lstrip("* ").strip())
            if project:
                self.store.update_project(project.id, bucket=bucket,
                                          verdict=f"{bucket} (manual override)")
                changed += 1
        self.store.log("rebucket", detail=f"{changed} projects -> {bucket}")
        self.refresh()
        self.ctx.status(f"Moved {changed} project(s) to `{bucket}`", "good")

    def _apply_priority(self) -> None:
        try:
            priority = max(1, min(100, int(self.priority_set.get())))
        except ValueError:
            messagebox.showerror("Priority", "Priority must be a number from 1 to 100.")
            return
        changed = 0
        for row in self.projects.selected_all():
            project = self.store.project_by_name(row["name"].lstrip("* ").strip())
            if project:
                self.store.update_project(project.id, priority=priority)
                changed += 1
        self.refresh()
        self.ctx.status(f"Priority {priority} on {changed} project(s)", "good")

    def _toggle_pin(self) -> None:
        changed = 0
        for row in self.projects.selected_all():
            project = self.store.project_by_name(row["name"].lstrip("* ").strip())
            if project:
                self.store.update_project(project.id, pinned=0 if project.pinned else 1)
                changed += 1
        self.refresh()
        self.ctx.status(f"Toggled pin on {changed} project(s)", "good")

    def _remove_project(self) -> None:
        rows = self.projects.selected_all()
        if not rows:
            return
        names = [r["name"].lstrip("* ").strip() for r in rows]
        if not messagebox.askyesno(
            "Remove from index",
            f"Remove {len(names)} project(s) from the index?\n\n"
            "This only forgets the map. No files on disk are touched.",
        ):
            return
        for name in names:
            project = self.store.project_by_name(name)
            if project:
                self.store.delete_project(project.id)
        self.store.log("unindex", detail=f"{len(names)} projects removed from index")
        self.refresh()
        self.ctx.broadcast("refresh")
        self.ctx.status(f"Removed {len(names)} project(s) from the index", "warn")
