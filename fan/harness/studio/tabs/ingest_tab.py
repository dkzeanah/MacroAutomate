"""Ingest tab -- the hot folder, and the one-pass "drop a ZIP and run it" pipeline.

The order matters and is enforced: back up, write, dedupe against the master index,
re-index, and only then run. Nothing executes before it has been captured.
"""

from __future__ import annotations

import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from atlas import fanout, ingest as ingestmod
from atlas.buckets import bucket_titles
from studio.widgets import (
    MONO, UI, UI_BOLD, Field, SortableTable, TextPane, button, separator, toolbar,
)

BUCKET_KEYS = ["(auto)"] + [key for key, _t, _b in bucket_titles()]


class IngestTab:
    def __init__(self, parent: ttk.Frame, context) -> None:
        self.ctx = context
        self.store = context.store
        self._plan: fanout.FanoutPlan | None = None
        self._source: Path | None = None

        bar = toolbar(parent)
        button(bar, "Choose ZIP / document", self._choose_file)
        button(bar, "Choose folder", self._choose_folder)
        separator(bar)
        button(bar, "Preview plan", self._preview)
        button(bar, "Ingest", self._ingest)
        button(bar, "Ingest + Run", self._ingest_and_run)
        separator(bar)
        button(bar, "Scan hot folder", self._scan_hot)
        button(bar, "Drain hot folder", self._drain_hot)

        options = ttk.Frame(parent, padding=(6, 0))
        options.pack(fill=tk.X)
        self.source_field = Field(options, "Source", width=58)
        self.source_field.pack(side=tk.LEFT)
        self.name_field = Field(options, "Project name", width=22)
        self.name_field.pack(side=tk.LEFT, padx=(10, 0))
        self.bucket_field = Field(options, "Bucket", width=14, values=BUCKET_KEYS)
        self.bucket_field.set("(auto)")
        self.bucket_field.pack(side=tk.LEFT, padx=(10, 0))
        self.overwrite = tk.BooleanVar(value=False)
        ttk.Checkbutton(options, text="overwrite existing",
                        variable=self.overwrite).pack(side=tk.LEFT, padx=(12, 0))

        hot = ttk.Frame(parent, padding=(6, 4))
        hot.pack(fill=tk.X)
        self.hot_field = Field(hot, "Hot folder", self.store.get("hot_folder"), width=58)
        self.hot_field.pack(side=tk.LEFT)
        button(hot, "Set", self._set_hot)
        button(hot, "Browse", self._browse_hot)
        ttk.Label(
            hot,
            text="Anything dropped here is unpacked, deduped, indexed and backed up in one pass.",
            font=UI, foreground="#666666",
        ).pack(side=tk.LEFT, padx=14)

        panes = ttk.PanedWindow(parent, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

        left = ttk.Frame(panes)
        ttk.Label(left, text="PLACEMENT PLAN", font=UI_BOLD).pack(anchor="w", pady=(0, 3))
        self.plan_table = SortableTable(
            left,
            ["ok", "path", "lines", "confidence", "note"],
            ["py", "target path", "L", "conf", "how it was placed"],
            [30, 320, 48, 48, 190],
            ["c", "w", "e", "e", "w"],
            on_select=self._piece_selected,
            height=24,
        )
        self.plan_table.pack(fill=tk.BOTH, expand=True)
        panes.add(left, weight=3)

        right = ttk.PanedWindow(panes, orient=tk.VERTICAL)
        top = ttk.Frame(right)
        ttk.Label(top, text="REPORT", font=UI_BOLD).pack(anchor="w", pady=(0, 3))
        self.report = TextPane(top, font=MONO, height=20)
        self.report.pack(fill=tk.BOTH, expand=True)
        self.report.set(_PRIMER)
        right.add(top, weight=3)

        bottom = ttk.Frame(right)
        ttk.Label(bottom, text="PREVIEW", font=UI_BOLD).pack(anchor="w", pady=(4, 3))
        self.preview = TextPane(bottom, font=MONO, height=12)
        self.preview.pack(fill=tk.BOTH, expand=True)
        right.add(bottom, weight=2)
        panes.add(right, weight=3)

        self.ctx.job.on("ingest_done", self._ingest_done)
        self.ctx.job.on("ingest_error", self._error)
        self.ctx.job.on("drain_done", self._drain_done)

    # ------------------------------------------------------------------ sources
    def _choose_file(self) -> None:
        chosen = filedialog.askopenfilename(
            title="ZIP archive or mass document",
            filetypes=[("Archives and documents", "*.zip *.md *.txt"),
                       ("ZIP", "*.zip"), ("Markdown", "*.md"), ("All files", "*.*")],
        )
        if chosen:
            self._set_source(Path(chosen))

    def _choose_folder(self) -> None:
        chosen = filedialog.askdirectory(title="Folder to ingest")
        if chosen:
            self._set_source(Path(chosen))

    def _set_source(self, path: Path) -> None:
        self._source = path
        self.source_field.set(str(path))
        if not self.name_field.get():
            self.name_field.set(path.stem.replace(" ", "_"))
        self._preview()

    def _browse_hot(self) -> None:
        chosen = filedialog.askdirectory(title="Hot folder")
        if chosen:
            self.hot_field.set(chosen)
            self._set_hot()

    def _set_hot(self) -> None:
        self.store.set("hot_folder", self.hot_field.get())
        self.ctx.status(f"Hot folder set to {self.hot_field.get()}", "good")

    # ------------------------------------------------------------------ preview
    def _preview(self) -> None:
        raw = self.source_field.get()
        if not raw:
            messagebox.showinfo("Preview", "Choose a ZIP, document or folder first.")
            return
        source = Path(raw)
        self._source = source
        if not source.exists():
            self.report.set(f"{source} does not exist")
            return

        if source.is_dir():
            plan = fanout.FanoutPlan()
            for path in sorted(source.rglob("*")):
                if not path.is_file():
                    continue
                try:
                    content = path.read_text(encoding="utf-8")
                except (OSError, UnicodeDecodeError):
                    continue
                plan.pieces.append(fanout.Piece(
                    path.relative_to(source).as_posix(), content,
                    path.suffix.lstrip("."), 1.0, str(source), "from folder"))
        elif source.suffix.lower() == ".zip":
            plan = fanout.parse_zip(source)
        else:
            plan = fanout.parse_document(
                source.read_text(encoding="utf-8", errors="replace"))

        self._plan = plan
        rows = []
        for piece in sorted(plan.pieces, key=lambda p: p.path):
            valid = piece.valid_python
            tags = ()
            if valid is False:
                tags = ("bad",)
            elif piece.confidence < 0.5:
                tags = ("warn",)
            rows.append({
                "ok": {True: "ok", False: "!!", None: ""}[valid],
                "path": piece.path,
                "lines": piece.lines,
                "confidence": f"{piece.confidence:.2f}",
                "note": piece.note,
                "_tags": tags,
            })
        self.plan_table.set_rows(rows)
        self.report.set(plan.render())
        self.ctx.status(
            f"{len(plan.pieces)} files planned, {plan.total_lines} lines"
            + (f", {len(plan.warnings)} warnings" if plan.warnings else ""),
            "warn" if plan.warnings else "good",
        )

    def _piece_selected(self, row: dict) -> None:
        if not self._plan:
            return
        match = next((p for p in self._plan.pieces if p.path == row["path"]), None)
        if match is None:
            return
        body = match.content[:8000]
        self.preview.set(
            f"# {match.path}   {match.lines} lines   confidence {match.confidence:.2f}"
            f"   ({match.note})\n\n{body}"
            + ("\n\n... truncated" if len(match.content) > 8000 else "")
        )

    # ------------------------------------------------------------------ ingest
    def _ingest(self, run: bool = False) -> None:
        raw = self.source_field.get()
        if not raw:
            messagebox.showinfo("Ingest", "Choose a source first.")
            return
        source = Path(raw)
        name = self.name_field.get() or source.stem.replace(" ", "_")
        bucket = self.bucket_field.get()
        bucket = None if bucket in ("", "(auto)") else bucket
        destination = self.ctx.workspace / "projects" / name

        if run and not messagebox.askyesno(
            "Ingest and run",
            f"Ingest into {destination} and then execute its entry point?\n\n"
            "The code is captured, backed up and indexed before anything runs.",
        ):
            return

        self.ctx.status(f"Ingesting {source.name} ...", "busy")
        self.report.set(f"Ingesting {source} -> {destination} ...\n")
        overwrite = self.overwrite.get()

        def work():
            return ingestmod.ingest(
                self.store, source, destination=destination, project_name=name,
                bucket=bucket, run=run, overwrite=overwrite,
            )

        self.ctx.job.run(work, "ingest_done", "ingest_error")

    def _ingest_and_run(self) -> None:
        self._ingest(run=True)

    def _ingest_done(self, report: ingestmod.IngestReport) -> None:
        self.report.set(report.render())
        if report.duplicates:
            self.preview.set(
                "DUPLICATES FOUND -- these already exist in the indexed universe.\n"
                "Reuse the existing address rather than keeping the incoming copy.\n\n"
                + "\n".join(
                    f"{d.score:.2f}  {d.incoming}\n      -> {d.existing_address}\n"
                    f"         {d.signature[:100]}"
                    for d in report.duplicates
                )
            )
        self.ctx.refresh_counts()
        self.ctx.broadcast("refresh")
        kind = "bad" if report.errors else ("warn" if report.duplicates else "good")
        self.ctx.status(
            f"Ingested {report.project}: {len(report.written)} files, "
            f"{report.new_symbols} symbols, {len(report.duplicates)} duplicates",
            kind,
        )

    def _error(self, message: str) -> None:
        self.report.set(str(message))
        self.ctx.status("Ingest failed -- see report", "bad")

    # -------------------------------------------------------------- hot folder
    def _scan_hot(self) -> None:
        folder = self.hot_field.get()
        if not folder:
            messagebox.showinfo("Hot folder", "Set a hot folder first.")
            return
        pending = ingestmod.scan_hot_folder(self.store, Path(folder))
        if not pending:
            self.report.set(f"Hot folder {folder} is empty (or everything is ingested).")
            self.ctx.status("Hot folder clear", "good")
            return
        self.report.set(
            f"{len(pending)} item(s) waiting in {folder}:\n\n"
            + "\n".join(f"  {p.name}" for p in pending)
            + "\n\nDrain hot folder ingests all of them in order."
        )
        self.ctx.status(f"{len(pending)} item(s) pending", "warn")

    def _drain_hot(self) -> None:
        folder = self.hot_field.get()
        if not folder:
            return
        pending = ingestmod.scan_hot_folder(self.store, Path(folder))
        if not pending:
            self.ctx.status("Nothing to drain", "good")
            return
        if not messagebox.askyesno(
            "Drain hot folder",
            f"Ingest {len(pending)} item(s) from {folder}?\n\n"
            "Each is unpacked, deduped, indexed and backed up. Nothing is executed.",
        ):
            return
        self.ctx.status(f"Draining {len(pending)} item(s) ...", "busy")

        def work():
            return ingestmod.drain_hot_folder(self.store, Path(folder), run=False)

        self.ctx.job.run(work, "drain_done", "ingest_error")

    def _drain_done(self, reports: list) -> None:
        body = "\n\n".join(r.render() for r in reports)
        self.report.set(f"DRAINED {len(reports)} item(s)\n\n{body}")
        self.ctx.refresh_counts()
        self.ctx.broadcast("refresh")
        self.ctx.status(f"Drained {len(reports)} item(s)", "good")

    def on_refresh(self) -> None:
        self.hot_field.set(self.store.get("hot_folder"))


_PRIMER = """INGEST

Drop in a ZIP from a chat assistant, a mass document full of fenced code blocks, or a
folder. One pass does all of this, in this order:

  1. PLAN      work out where every piece belongs (preview it before committing)
  2. BACK UP   snapshot anything already at the destination into .atlas/backups
  3. WRITE     place the files at real paths; existing files are kept as .prior
  4. DEDUPE    check every incoming symbol against the whole indexed universe
  5. INDEX     scan, classify into a bucket, and store the map
  6. RUN       optional, and always last -- nothing executes before it is captured

A second drop of the same project diffs against the first and keeps the prior state.
"""
