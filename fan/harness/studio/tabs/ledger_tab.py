"""Ledger tab -- history, backups, restore, and the attic.

The promise this tab keeps: nothing you have ever had is gone. Superseded code sits in
the attic with a tombstone; every mutation left a full backup behind; any prior state
can be restored.
"""

from __future__ import annotations

import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk

from atlas.ledger import Ledger
from studio.widgets import (
    MONO, UI, UI_BOLD, SortableTable, TextPane, button, separator, toolbar,
)


class LedgerTab:
    def __init__(self, parent: ttk.Frame, context) -> None:
        self.ctx = context
        self.store = context.store
        self.ledger = Ledger(self.store)

        bar = toolbar(parent)
        button(bar, "Refresh", self.on_refresh)
        separator(bar)
        button(bar, "Preview restore", lambda: self._restore(False))
        button(bar, "Restore selected", lambda: self._restore(True))
        separator(bar)
        button(bar, "Open backup folder", self._open_backup)
        button(bar, "Prune old backups", self._prune)

        ttk.Label(
            parent,
            text=("Backups are the only thing ever removed, and only above a floor of 40. "
                  "The attic and the ledger rows are permanent."),
            font=UI, foreground="#666666", padding=(8, 0),
        ).pack(anchor="w")

        panes = ttk.PanedWindow(parent, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

        left = ttk.PanedWindow(panes, orient=tk.VERTICAL)

        top = ttk.Frame(left)
        ttk.Label(top, text="HISTORY", font=UI_BOLD).pack(anchor="w", pady=(0, 3))
        self.history = SortableTable(
            top,
            ["id", "ts", "action", "target", "files"],
            ["#", "when", "action", "target", "files"],
            [46, 138, 108, 250, 46],
            ["e", "w", "w", "w", "e"],
            on_select=self._entry_selected,
            height=18,
        )
        self.history.pack(fill=tk.BOTH, expand=True)
        left.add(top, weight=3)

        bottom = ttk.Frame(left)
        ttk.Label(bottom, text="ATTIC  (retired code, kept deliberately)",
                  font=UI_BOLD).pack(anchor="w", pady=(4, 3))
        self.attic = SortableTable(
            bottom,
            ["label", "bytes"],
            ["retired symbol", "bytes"],
            [420, 70],
            ["w", "e"],
            on_select=self._attic_selected,
            height=12,
        )
        self.attic.pack(fill=tk.BOTH, expand=True)
        left.add(bottom, weight=2)
        panes.add(left, weight=3)

        right = ttk.Frame(panes)
        head = ttk.Frame(right)
        head.pack(fill=tk.X)
        ttk.Label(head, text="DETAIL", font=UI_BOLD).pack(side=tk.LEFT, pady=(0, 3))
        self.summary_var = tk.StringVar(value="")
        ttk.Label(head, textvariable=self.summary_var, font=("Consolas", 9),
                  foreground="#666666").pack(side=tk.RIGHT)
        self.detail = TextPane(right, font=MONO, height=34)
        self.detail.pack(fill=tk.BOTH, expand=True)
        self.detail.set(_PRIMER)
        panes.add(right, weight=3)

        self._entries: dict[str, dict] = {}
        self._attic_paths: dict[str, Path] = {}

    # ----------------------------------------------------------------- refresh
    def on_refresh(self) -> None:
        entries = self.ledger.history(300)
        self._entries = {str(e["id"]): e for e in entries}
        rows = []
        for entry in entries:
            payload = entry["payload"]
            count = len(payload) if isinstance(payload, list) else (
                payload.get("written", "") if isinstance(payload, dict) else "")
            tags = ()
            if entry["action"] in {"retire", "unindex", "prune"}:
                tags = ("warn",)
            elif entry["action"] == "restore":
                tags = ("hot",)
            rows.append({
                "id": entry["id"],
                "ts": entry["ts"],
                "action": entry["action"],
                "target": entry["address"] or entry["detail"],
                "files": count,
                "_tags": tags,
            })
        self.history.set_rows(rows)

        attic = self.ledger.attic_entries()
        self._attic_paths = {label: path for label, path, _size in attic}
        self.attic.set_rows([
            {"label": label, "bytes": size} for label, _path, size in attic
        ])

        backups = self.ledger.list_backups()
        self.summary_var.set(
            f"{len(entries)} ledger entries | {len(backups)} backups | "
            f"{len(attic)} retired"
        )

    on_show = on_refresh

    # ------------------------------------------------------------------ events
    def _entry_selected(self, row: dict) -> None:
        entry = self._entries.get(str(row["id"]))
        if not entry:
            return
        lines = [
            f"LEDGER #{entry['id']}",
            "=" * 62,
            f"when     {entry['ts']}",
            f"action   {entry['action']}",
            f"address  {entry['address'] or '-'}",
            f"detail   {entry['detail'] or '-'}",
            f"backup   {entry['backup_dir'] or '(none)'}",
            "",
        ]
        payload = entry["payload"]
        if isinstance(payload, list):
            lines.append(f"FILES CAPTURED ({len(payload)})")
            lines.append("-" * 62)
            lines += [f"  {p}" for p in payload[:200]]
            if len(payload) > 200:
                lines.append(f"  ... and {len(payload) - 200} more")
        elif isinstance(payload, dict):
            lines.append("PAYLOAD")
            lines.append("-" * 62)
            lines += [f"  {k}: {v}" for k, v in payload.items()]
        elif payload:
            lines.append(str(payload))

        if entry["backup_dir"]:
            lines += ["", "Preview restore shows what would be written; "
                          "Restore selected actually writes it."]
        self.detail.set("\n".join(lines))

    def _attic_selected(self, row: dict) -> None:
        path = self._attic_paths.get(row["label"])
        if not path or not path.exists():
            return
        self.detail.set(self.ledger.recover(path))

    # ------------------------------------------------------------------ actions
    def _restore(self, write: bool) -> None:
        row = self.history.selected()
        if not row:
            messagebox.showinfo("Restore", "Select a ledger entry first.")
            return
        entry = self._entries.get(str(row["id"]))
        if not entry or not entry["backup_dir"]:
            messagebox.showinfo("Restore", "That entry has no backup attached.")
            return
        if write and not messagebox.askyesno(
            "Restore",
            f"Restore the files captured by ledger #{entry['id']}?\n\n"
            f"({entry['ts']} -- {entry['action']})\n\n"
            "Current versions of those files will be overwritten. "
            "Preview first if you are unsure.",
        ):
            return
        report = self.ledger.restore(int(row["id"]), dry_run=not write)
        header = ("RESTORED" if write else "RESTORE PREVIEW (nothing written)")
        self.detail.set(f"{header}\nfrom ledger #{row['id']}\n\n" + "\n".join(report))
        if write:
            self.on_refresh()
            self.ctx.broadcast("refresh")
        self.ctx.status(
            f"{'Restored' if write else 'Previewed'} {len(report)} file(s) "
            f"from ledger #{row['id']}",
            "good" if write else "info",
        )

    def _open_backup(self) -> None:
        row = self.history.selected()
        entry = self._entries.get(str(row["id"])) if row else None
        target = Path(entry["backup_dir"]) if entry and entry["backup_dir"] else self.ledger.backups
        if not target.exists():
            messagebox.showinfo("Backups", f"{target} does not exist.")
            return
        import subprocess
        import sys
        try:
            if sys.platform == "win32":
                subprocess.Popen(["explorer", str(target)])
            elif sys.platform == "darwin":
                subprocess.Popen(["open", str(target)])
            else:
                subprocess.Popen(["xdg-open", str(target)])
        except OSError as exc:
            messagebox.showerror("Backups", str(exc))

    def _prune(self) -> None:
        backups = self.ledger.list_backups()
        if len(backups) <= 40:
            messagebox.showinfo(
                "Prune", f"{len(backups)} backups -- nothing to prune (the floor is 40)."
            )
            return
        if not messagebox.askyesno(
            "Prune backups",
            f"Remove the {len(backups) - 40} oldest backup folders, keeping the newest 40?\n\n"
            "The ledger rows and the attic are not touched.",
        ):
            return
        removed = self.ledger.prune_backups(keep=40)
        self.on_refresh()
        self.ctx.status(f"Pruned {len(removed)} old backup folder(s)", "warn")


_PRIMER = """LEDGER

Nothing you have ever had is gone.

  HISTORY   every mutation, append-only. Sweeps, indexes, ingests, mirrors, retires,
            restores and exports all leave a row.

  BACKUPS   before anything is modified, the affected files are copied whole into
            .atlas/backups/<timestamp>/. Select an entry and Restore to put them back.

  ATTIC     superseded code is moved to .atlas/attic/ with a header saying what
            replaced it, and keeps a flagged tombstone line in the index. An obsolete
            symbol costs one line at tier 0. Losing it costs everything.

Select a row to see what it captured.
"""
