"""Append-only history. Nothing is ever deleted -- only superseded.

The rule this module enforces: obsolete code costs one flagged line at tier 0, which is
nothing. Losing code costs everything. So supersede, tombstone, and archive; never rm.
"""

from __future__ import annotations

import datetime as _dt
import json
import shutil
from dataclasses import dataclass
from pathlib import Path

from .spec import ATLAS_DIR, ATTIC_DIR, BACKUP_DIR, FLAG_OBSOLETE
from .store import Store


def _stamp() -> str:
    return _dt.datetime.now().strftime("%Y%m%d-%H%M%S")


@dataclass
class BackupSet:
    """One snapshot directory plus the files it captured."""

    directory: Path
    files: list[str]
    ledger_id: int = 0

    @property
    def label(self) -> str:
        return self.directory.name


class Ledger:
    """Backups, the attic, tombstones, and restore."""

    def __init__(self, store: Store) -> None:
        self.store = store
        self.root = store.workspace / ATLAS_DIR
        self.attic = self.root / ATTIC_DIR
        self.backups = self.root / BACKUP_DIR
        self.attic.mkdir(parents=True, exist_ok=True)
        self.backups.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------- backups
    def snapshot(self, paths: list[Path], action: str, detail: str = "") -> BackupSet:
        """Copy every path into a timestamped backup directory before it is touched."""
        directory = self.backups / _stamp()
        directory.mkdir(parents=True, exist_ok=True)
        captured: list[str] = []

        for path in paths:
            path = Path(path)
            if not path.exists() or not path.is_file():
                continue
            try:
                rel = path.relative_to(self.store.workspace)
            except ValueError:
                rel = Path(path.name)
            target = directory / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
            captured.append(rel.as_posix())

        (directory / "_manifest.json").write_text(
            json.dumps(
                {"action": action, "detail": detail, "files": captured, "at": _stamp()},
                indent=2,
            ),
            encoding="utf-8",
        )
        entry_id = self.store.log(
            action=action, detail=detail, backup_dir=str(directory), payload=captured
        )
        return BackupSet(directory, captured, entry_id)

    def restore(self, ledger_id: int, dry_run: bool = True) -> list[str]:
        """Put the tree back to the state captured by one ledger entry."""
        entry = self.store.ledger_entry(ledger_id)
        if entry is None:
            return [f"no ledger entry {ledger_id}"]
        directory = Path(entry["backup_dir"] or "")
        if not directory.exists():
            return [f"backup directory missing: {directory}"]

        manifest_path = directory / "_manifest.json"
        try:
            files = json.loads(manifest_path.read_text(encoding="utf-8"))["files"]
        except (OSError, ValueError, KeyError):
            files = [
                p.relative_to(directory).as_posix()
                for p in directory.rglob("*")
                if p.is_file() and p.name != "_manifest.json"
            ]

        report: list[str] = []
        for rel in files:
            source = directory / rel
            target = self.store.workspace / rel
            if not source.exists():
                report.append(f"skip (missing in backup): {rel}")
                continue
            if dry_run:
                report.append(f"would restore: {rel}")
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            report.append(f"restored: {rel}")

        if not dry_run:
            self.store.log(
                action="restore", detail=f"from ledger {ledger_id}",
                backup_dir=str(directory), payload=report,
            )
        return report

    def list_backups(self) -> list[BackupSet]:
        out: list[BackupSet] = []
        for directory in sorted(self.backups.iterdir(), reverse=True):
            if not directory.is_dir():
                continue
            manifest = directory / "_manifest.json"
            files: list[str] = []
            if manifest.exists():
                try:
                    files = json.loads(manifest.read_text(encoding="utf-8"))["files"]
                except (OSError, ValueError, KeyError):
                    files = []
            out.append(BackupSet(directory, files))
        return out

    # --------------------------------------------------------------------- attic
    def retire(self, address: str, code: str, replaced_by: str = "", note: str = "") -> Path:
        """Move superseded code to the attic and leave a tombstone in the index."""
        safe = address.replace("@", "").replace("/", "__").replace(":", "__").replace("#", "--")
        target = self.attic / f"{_stamp()}__{safe}.py"
        header = [
            f"# RETIRED {address}",
            f"# at: {_dt.datetime.now().isoformat(timespec='seconds')}",
        ]
        if replaced_by:
            header.append(f"# replaced by: {replaced_by}")
        if note:
            header.append(f"# note: {note}")
        header.append("# This code is retained deliberately. Do not delete this file.")
        header.append("")
        target.write_text("\n".join(header) + code + "\n", encoding="utf-8")

        row = self.store.symbol_by_address(address)
        if row is not None:
            flags = (row["flags"] or "")
            if FLAG_OBSOLETE not in flags:
                flags += FLAG_OBSOLETE
            self.store.execute(
                "UPDATE symbols SET flags = ?, doc = ? WHERE id = ?",
                (flags,
                 (f"SUPERSEDED by {replaced_by}. " if replaced_by else "SUPERSEDED. ")
                 + (row["doc"] or ""),
                 row["id"]),
            )

        self.store.log(
            action="retire", address=address,
            detail=f"-> {replaced_by}" if replaced_by else note,
            payload={"attic": str(target)},
        )
        return target

    def attic_entries(self) -> list[tuple[str, Path, int]]:
        """(label, path, bytes) for everything retained in the attic, newest first."""
        out: list[tuple[str, Path, int]] = []
        for path in sorted(self.attic.glob("*.py"), reverse=True):
            try:
                size = path.stat().st_size
            except OSError:
                size = 0
            out.append((path.stem, path, size))
        return out

    def recover(self, attic_path: Path) -> str:
        """Read retired code back out of the attic."""
        return Path(attic_path).read_text(encoding="utf-8", errors="replace")

    # -------------------------------------------------------------------- history
    def history(self, limit: int = 200) -> list[dict]:
        rows = self.store.ledger(limit)
        out: list[dict] = []
        for row in rows:
            payload = row["payload"]
            try:
                parsed = json.loads(payload) if payload else None
            except ValueError:
                parsed = payload
            out.append(
                {
                    "id": row["id"],
                    "ts": row["ts"],
                    "action": row["action"],
                    "address": row["address"],
                    "detail": row["detail"],
                    "backup_dir": row["backup_dir"],
                    "payload": parsed,
                }
            )
        return out

    def prune_backups(self, keep: int = 40) -> list[str]:
        """Trim the oldest backup directories, keeping the newest ``keep``.

        Backups are the only thing here that is ever removed, and only above a floor --
        the attic and the ledger rows are permanent.
        """
        directories = [d for d in sorted(self.backups.iterdir()) if d.is_dir()]
        removed: list[str] = []
        for directory in directories[:-keep] if len(directories) > keep else []:
            shutil.rmtree(directory, ignore_errors=True)
            removed.append(directory.name)
        if removed:
            self.store.log("prune", detail=f"removed {len(removed)} old backups",
                           payload=removed)
        return removed
