"""WAL-aware exports and staged, verified offloads for Fan-owned data.

No operation moves arbitrary application data. Database selection is restricted
to the five stores owned by Fan and its DeepSeek bridge. Snapshot relocation
keeps its original pathname through a native Windows directory junction, so
existing absolute image paths remain usable without rewriting any database.

The UI/coordinator closes its processes before offload, commits its bootstrap
configuration after snapshot cutover, and explicitly confirms cleanup. A stage
or cancellation never deletes the source. File inventories, copies, and hashes
stream with bounded memory. Jobs retain a durable journal for resumption.
"""
from __future__ import annotations

import ctypes
from ctypes import wintypes
from contextlib import closing, contextmanager
from contextvars import ContextVar
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sqlite3
import stat
import struct
import time
import uuid
from collections.abc import Callable, Iterable, Mapping


DATABASES = {"tracking": "tracking.db", "macro": "macroauto.sqlite",
             "appmap": "appmap.db", "bridge": "bridge.sqlite3",
             "catalog": "tool_catalog.sqlite3", "unified": "fan.sqlite"}
VERSION = 1
CHUNK = 1024 * 1024
OWNER = ".fan-data-owner.json"
_HELD_ORIGINALS = ContextVar("fan_storage_held_originals", default=frozenset())


class StorageError(RuntimeError):
    pass


class Cancelled(StorageError):
    pass


def _atomic_json(path: Path, value: dict) -> None:
    temporary = path.with_name(path.name + ".writing")
    with temporary.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def _read_json(path: Path) -> dict:
    if path.stat().st_size > 1024 * 1024:
        raise StorageError(f"Oversized maintenance metadata: {path.name}")
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise StorageError(f"Invalid maintenance metadata: {path.name}")
    return value


def _signature(path: Path) -> dict:
    info = path.stat()
    return {"size": info.st_size, "mtime_ns": info.st_mtime_ns,
            "device": info.st_dev, "inode": info.st_ino}


def _database_signature(path: Path) -> dict:
    result = {"main": _signature(path)}
    # SHM is reader coordination, not durable data; its timestamps can change
    # merely by opening a read-only connection. Empty sidecars are equivalent
    # to absent sidecars and can be created/removed by SQLite's normal lifecycle.
    for suffix in ("-wal", "-journal"):
        sidecar = Path(str(path) + suffix)
        if sidecar.exists() and sidecar.stat().st_size:
            result[suffix] = _signature(sidecar)
    return result


def _is_reparse(path: Path) -> bool:
    info = path.lstat()
    return stat.S_ISLNK(info.st_mode) or bool(getattr(info, "st_file_attributes", 0) & 0x400)


def _contained(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def _relative(value: str) -> Path:
    item = PurePosixPath(value)
    if item.is_absolute() or not item.parts or any(part in (".", "..") or "\\" in part or ":" in part for part in item.parts):
        raise StorageError("Invalid path in maintenance manifest")
    return Path(*item.parts)


def _safe_target(root: Path, relative: str) -> Path:
    """Reject parent junctions too; checking only the final file is insufficient."""
    path = root
    for part in _relative(relative).parts:
        path /= part
        if os.path.lexists(path) and _is_reparse(path):
            raise StorageError("Maintenance destination contains a link/junction")
    if not _contained(path.resolve(), root.resolve(strict=True)):
        raise StorageError("Maintenance destination escapes its owned bundle")
    return path


class _Progress:
    def __init__(self, callback=None, cancel_file=None, max_seconds=7200, job_id=""):
        self.callback = callback
        self.cancel_file = Path(cancel_file) if cancel_file else None
        self.deadline = time.monotonic() + max(1, float(max_seconds))
        self.job_id = job_id
        self.total = 0
        self.done = 0
        self.files = 0
        self.last = 0.0
        self.phase = ""

    def check(self):
        if self.cancel_file and self.cancel_file.exists():
            raise Cancelled("Maintenance cancelled; original data was retained")
        if time.monotonic() > self.deadline:
            raise StorageError("Maintenance time limit reached; staged data can be resumed")

    def emit(self, phase, *, path="", message="", force=False, **details):
        self.check()
        now = time.monotonic()
        if force or phase != self.phase or now - self.last >= .15:
            self.last = now
            self.phase = phase
            if self.callback:
                self.callback({"phase": phase, "job_id": self.job_id,
                               "bytes_done": self.done, "bytes_total": self.total,
                               "files_done": self.files, "path": str(path),
                               "message": message, **details})
                self.check()


def _walk_files(root: Path, on_directory=None):
    """Hold one iterator per depth, never a list of all cycle folders/files."""
    if on_directory:
        on_directory(root)
    stack = [os.scandir(root)]
    try:
        while stack:
            try:
                entry = next(stack[-1])
            except StopIteration:
                stack.pop().close()
                continue
            path = Path(entry.path)
            if _is_reparse(path):
                raise StorageError(f"Snapshot tree contains a link/junction: {path}")
            if entry.is_dir(follow_symlinks=False):
                if on_directory:
                    on_directory(path)
                stack.append(os.scandir(path))
            elif entry.is_file(follow_symlinks=False):
                yield path
            else:
                raise StorageError(f"Snapshot tree contains a non-file entry: {path}")
    finally:
        for entries in stack:
            entries.close()


def _empty_directories(root: Path):
    """Postorder directory iterator used after confirmed file cleanup."""
    stack = [(root, os.scandir(root))]
    try:
        while stack:
            try:
                entry = next(stack[-1][1])
            except StopIteration:
                path, entries = stack.pop()
                entries.close()
                yield path
                continue
            path = Path(entry.path)
            if _is_reparse(path):
                raise StorageError("Original snapshot tree gained a link during cleanup")
            if entry.is_dir(follow_symlinks=False):
                stack.append((path, os.scandir(path)))
    finally:
        for path, entries in stack:
            entries.close()


def _hash(path: Path, progress: _Progress | None = None, phase="verify") -> str:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        while chunk := stream.read(CHUNK):
            digest.update(chunk)
            size += len(chunk)
            if progress:
                progress.emit(phase, path=path, verified_bytes=size)
    return digest.hexdigest()


def _readonly_database(path: Path):
    # immutable=1 would ignore a live WAL and is deliberately never used.
    connection = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=5)
    connection.execute("PRAGMA busy_timeout=5000")
    return connection


def _schema(connection) -> str:
    rows = connection.execute("SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name,tbl_name,sql")
    digest = hashlib.sha256()
    for row in rows:
        digest.update(json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
        digest.update(b"\n")
    for pragma in ("user_version", "application_id"):
        digest.update(f"{pragma}:{connection.execute('PRAGMA ' + pragma).fetchone()[0]}".encode("ascii"))
    return digest.hexdigest()


def _quick_check(connection, path: Path, progress: _Progress):
    interrupted = []

    def check():
        try:
            progress.emit("database-integrity", path=path, message="Checking SQLite pages and relationships")
            return 0
        except StorageError as error:
            interrupted.append(error)
            return 1

    progress.emit("database-integrity", path=path, force=True)
    connection.set_progress_handler(check, 1000)
    try:
        try:
            result = connection.execute("PRAGMA quick_check(1)").fetchall()
        except sqlite3.OperationalError:
            if interrupted:
                raise interrupted[0]
            raise
        if result != [("ok",)]:
            raise StorageError(f"SQLite integrity verification failed: {path.name}: {result[:1]}")
    finally:
        connection.set_progress_handler(None, 0)
    progress.check()


def _probe_exclusive(paths: Iterable[Path]) -> None:
    """Refuse offload while another Windows process still has a store open."""
    if os.name != "nt":
        raise StorageError("Offload exclusive-access verification requires Windows")
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateFileW.argtypes = (wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                  wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE)
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = (wintypes.HANDLE,)
    invalid = ctypes.c_void_p(-1).value
    held = []
    seen = set()
    try:
        for path in paths:
            key = _guard_key(path)
            if key in seen:
                continue
            seen.add(key)
            if not path.exists():
                continue
            if _guard_key(path) in _HELD_ORIGINALS.get():
                continue  # This coordinator already owns a stricter persistent guard.
            handle = kernel.CreateFileW(str(path), 0xC0000000, 0, None, 3, 0x80, None)
            if handle == invalid:
                code = ctypes.get_last_error()
                raise StorageError(f"Store still in use or inaccessible: {path.name} (Windows error {code}); close its other program before offload")
            held.append(handle)
    finally:
        for handle in held:
            kernel.CloseHandle(handle)


def _store_paths(database: Path):
    return [database, *(Path(str(database) + suffix) for suffix in ("-wal", "-shm", "-journal"))]


def _guard_key(path: Path) -> str:
    return os.path.normcase(os.path.abspath(path))


@contextmanager
def hold_originals(manifest_path):
    """Hold original database guards through bootstrap commit and cleanup.

    READ|WRITE|DELETE access with FILE_SHARE_DELETE forbids any competing SQLite
    read/write opener while still allowing this coordinator to unlink confirmed
    originals. Guarded cleanup skips its redundant transient exclusive probe.
    Use only after staging and before changing the active bootstrap paths.
    """
    manifest = _load_manifest(manifest_path)
    if manifest["mode"] != "offload" or os.name != "nt":
        raise StorageError("Original database guards require a Windows offload job")
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateFileW.argtypes = (wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                  wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE)
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = (wintypes.HANDLE,)
    held = []
    original_context = _HELD_ORIGINALS.get()
    guarded = set(original_context)
    token = None
    cleanup_path = Path(manifest["bundle"]) / "database-cleanup.json"
    cleanup = _read_json(cleanup_path) if cleanup_path.exists() else {}
    reset_path = Path(manifest['bundle']) / 'database-reset.json'
    reset = _read_json(reset_path) if reset_path.exists() else {}
    try:
        for record in manifest["databases"]:
            source = Path(record["source"])
            role = record["role"]
            if role not in DATABASES or source.name.lower() != DATABASES[role].lower():
                raise StorageError("Unexpected original database in offload manifest")
            if not source.exists():
                reset_install = (reset.get('job_id') == manifest['job_id']
                                 and reset.get('stores', {}).get(role, {}).get('status') == 'installing')
                if not reset_install and (cleanup.get("job_id") != manifest["job_id"] or cleanup.get("status") not in ("confirmed", "complete")):
                    raise StorageError(f"Original database disappeared before commit: {source.name}")
            for path in _store_paths(source):
                if not path.exists() or _guard_key(path) in guarded:
                    continue
                if _is_reparse(path):
                    raise StorageError("Original database was replaced by a link")
                handle = kernel.CreateFileW(str(path), 0xC0010000, 4, None, 3, 0x80, None)
                if handle == ctypes.c_void_p(-1).value:
                    raise StorageError(f"Store still in use before cutover: {path.name} (Windows error {ctypes.get_last_error()})")
                held.append(handle)
                guarded.add(_guard_key(path))
            replacement = reset.get('stores', {}).get(role, {})
            installed = (reset.get('job_id') == manifest['job_id'] and source.exists()
                         and _signature(source) == replacement.get('signature'))
            if source.exists() and not installed and _database_signature(source) != record["source_signature"]:
                raise StorageError(f"Original database changed before cutover: {source.name}")
        token = _HELD_ORIGINALS.set(frozenset(guarded))
        yield {"ok": True, "job_id": manifest["job_id"], "guarded_paths": sorted(guarded - original_context)}
    finally:
        if token is not None:
            _HELD_ORIGINALS.reset(token)
        for handle in reversed(held):
            kernel.CloseHandle(handle)


def _selected_databases(database_paths) -> dict[str, Path]:
    if isinstance(database_paths, Mapping):
        supplied = database_paths.items()
    else:
        reverse = {name.lower(): role for role, name in DATABASES.items()}
        supplied = ((reverse.get(Path(path).name.lower(), ""), path) for path in database_paths)
    selected = {}
    seen = set()
    for role, value in supplied:
        if role not in DATABASES:
            raise StorageError(f"Unknown managed database role: {role}")
        path = Path(value).absolute()
        if path.name.lower() != DATABASES[role].lower() or not path.is_file() or _is_reparse(path):
            raise StorageError(f"Missing or unexpected managed database: {role}")
        path = path.resolve(strict=True)
        if str(path).lower() in seen:
            raise StorageError("Duplicate managed database selection")
        with path.open("rb") as stream:
            if stream.read(16) != b"SQLite format 3\x00":
                raise StorageError(f"Not a SQLite database: {path.name}")
        seen.add(str(path).lower())
        selected[role] = path
    return selected


def _job_database(path: Path):
    connection = sqlite3.connect(path)
    connection.execute("CREATE TABLE IF NOT EXISTS copied (path TEXT PRIMARY KEY, record TEXT NOT NULL)")
    return connection


def _record(connection, relative: str, record: dict):
    connection.execute("INSERT OR REPLACE INTO copied(path,record) VALUES(?,?)",
                       (relative, json.dumps(record, ensure_ascii=False, separators=(",", ":"))))
    connection.commit()


def _resume_record(connection, relative, source_signature, target: Path, progress):
    row = connection.execute("SELECT record FROM copied WHERE path=?", (relative,)).fetchone()
    if not row:
        return None
    record = json.loads(row[0])
    if record["source_signature"] != source_signature or not target.is_file() or _is_reparse(target):
        return None
    if target.stat().st_size != record["size"] or _hash(target, progress, "resume-verify") != record["sha256"]:
        return None
    progress.done += record["size"]
    progress.files += 1
    return record


def _backup(source: Path, target: Path, progress: _Progress, unchanged=False) -> dict:
    temporary = target.with_name(target.name + ".copying")
    if temporary.exists():
        if _is_reparse(temporary):
            raise StorageError("Staged database path is a link")
        temporary.unlink()
    if target.exists():
        if _is_reparse(target):
            raise StorageError("Staged database destination is a link")
        # This is still a job-owned, uncommitted stage; source is intact. Free
        # a stale completed copy before a resumed backup needs that space again.
        target.unlink()
    target.parent.mkdir(parents=True, exist_ok=True)
    source_signature = _database_signature(source)
    before = progress.done
    progress.emit("database-backup", path=source, force=True)
    with closing(_readonly_database(source)) as original, closing(sqlite3.connect(temporary)) as backup:
        page_size = original.execute("PRAGMA page_size").fetchone()[0]
        expected_schema = _schema(original)

        def report(status, remaining, total):
            progress.done = before + max(0, total - remaining) * page_size
            progress.emit("database-backup", path=source, pages_remaining=remaining, pages_total=total)

        original.backup(backup, pages=1024, progress=report, sleep=.05)
        # Standalone destination has no dependency on a source WAL/SHM file.
        backup.execute("PRAGMA journal_mode=DELETE")
        if _schema(backup) != expected_schema:
            raise StorageError(f"Database schema verification failed: {source.name}")
        _quick_check(backup, source, progress)
        backup.commit()
    if unchanged and _database_signature(source) != source_signature:
        raise StorageError(f"Original database changed during offload staging: {source.name}")
    digest = _hash(temporary, progress, "database-verify")
    os.replace(temporary, target)
    progress.done = before + target.stat().st_size
    progress.files += 1
    return {"source_signature": source_signature, "size": target.stat().st_size,
            "sha256": digest, "schema_sha256": expected_schema,
            "target_signature": _signature(target)}


def _copy_file(source: Path, target: Path, progress: _Progress) -> dict:
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".copying")
    if target.exists():
        if _is_reparse(target):
            raise StorageError("Staged snapshot destination is a link")
        target.unlink()
    for attempt in range(3):
        progress.check()
        signature = _signature(source)
        digest = hashlib.sha256()
        before = progress.done
        if temporary.exists() and _is_reparse(temporary):
            raise StorageError("Staged snapshot path is a link")
        with source.open("rb") as original, temporary.open("wb") as copy:
            while chunk := original.read(CHUNK):
                copy.write(chunk)
                digest.update(chunk)
                progress.done += len(chunk)
                progress.emit("snapshot-copy", path=source)
            copy.flush()
            os.fsync(copy.fileno())
        if _signature(source) == signature:
            if _hash(temporary, progress, "snapshot-verify") != digest.hexdigest():
                raise StorageError(f"Snapshot copy verification failed: {source}")
            shutil.copystat(source, temporary, follow_symlinks=False)
            os.replace(temporary, target)
            progress.files += 1
            return {"source_signature": signature, "size": target.stat().st_size,
                    "sha256": digest.hexdigest(), "target_signature": _signature(target)}
        progress.done = before
    raise StorageError(f"Snapshot changed repeatedly during copy: {source}")


def _result(manifest: dict, manifest_path: Path) -> dict:
    return {"ok": True, "job_id": manifest["job_id"], "mode": manifest["mode"],
            "bundle": str(manifest_path.parent), "manifest": str(manifest_path),
            "targets": {record["role"]: record["target"] for record in manifest["databases"]},
            "databases": manifest["databases"], "snapshots": manifest.get("snapshots"),
            "requires_commit": manifest["mode"] == "offload",
            "files": manifest["file_count"], "bytes": manifest["bytes"]}


def prepare_export(database_paths, snapshot_root, destination, *, mode="export", job_id=None,
                   progress: Callable[[dict], None] | None = None, cancel_file=None,
                   max_seconds=7200) -> dict:
    """Back up selected role->Path stores and optional snapshots into an owned bundle.

    Pass the same job_id to resume an interrupted stage. Offload requires all Fan
    connections/processes closed; Windows probes refuse remaining external users.
    The result maps the original role keys to verified destination database paths.
    """
    if mode not in ("export", "offload"):
        raise StorageError("Choose export or offload")
    job_id = job_id or uuid.uuid4().hex
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", job_id):
        raise StorageError("Invalid maintenance job id")
    selected = _selected_databases(database_paths)
    alias = Path(snapshot_root).absolute() if snapshot_root else None
    snapshots = alias.resolve(strict=True) if alias else None
    if snapshots and not snapshots.is_dir():
        raise StorageError("Snapshot source is not a directory")
    if not selected and not snapshots:
        raise StorageError("Select at least one database or the snapshot folder")
    destination = Path(destination).absolute().resolve()
    destination.mkdir(parents=True, exist_ok=True)
    final = destination / ("Fan-data-" if mode == "offload" else "Fan-export-") / job_id
    if snapshots and (_contained(final, snapshots) or _contained(snapshots, final)):
        raise StorageError("Destination bundle and snapshot source must be separate, non-nested folders")
    # One job folder per selected location: a sibling staging directory can be
    # renamed atomically to its permanent destination on that same volume.
    final.parent.mkdir(parents=True, exist_ok=True)
    staging = final.with_name("." + final.name + ".partial")
    reporter = _Progress(progress, cancel_file, max_seconds, job_id)
    manifest_path = final / "manifest.json"
    if manifest_path.exists():
        manifest = _load_manifest(manifest_path)
        if manifest["mode"] != mode:
            raise StorageError("Existing job has a different mode")
        verify_bundle(manifest_path, progress=progress, cancel_file=cancel_file, max_seconds=max_seconds)
        return _result(manifest, manifest_path)
    ownership = {"version": VERSION, "job_id": job_id, "mode": mode}
    if staging.exists():
        if _is_reparse(staging) or not (staging / OWNER).is_file() or _read_json(staging / OWNER) != ownership:
            raise StorageError("Existing staging folder is not owned by this job")
    else:
        staging.mkdir()
        _atomic_json(staging / OWNER, ownership)
    selection = {"databases": {role: str(path) for role, path in selected.items()},
                 "snapshots": str(alias) if alias else None}
    selection_file = staging / "selection.json"
    if selection_file.exists() and _read_json(selection_file) != selection:
        raise StorageError("Resume selection differs from the original job")
    _atomic_json(selection_file, selection)
    total = 0
    reclaimable = 0
    reporter.emit("preflight", force=True, message="Checking source sizes and destination space")
    for source in selected.values():
        total += sum(path.stat().st_size for path in _store_paths(source) if path.is_file())
        candidate = staging / "databases" / source.name
        for previous in (candidate, candidate.with_name(candidate.name + ".copying")):
            if previous.is_file() and not _is_reparse(previous):
                reclaimable += previous.stat().st_size
    if snapshots:
        for source in _walk_files(snapshots):
            reporter.emit("preflight", path=source)
            total += source.stat().st_size
            candidate = staging / "snapshots" / source.relative_to(snapshots)
            for previous in (candidate, candidate.with_name(candidate.name + ".copying")):
                if previous.is_file() and not _is_reparse(previous):
                    reclaimable += previous.stat().st_size
    reporter.total = total
    free = shutil.disk_usage(destination).free
    needed = max(0, total - reclaimable)
    margin = max(64 * 1024 * 1024, min(total // 20, 2 * 1024 ** 3))
    if free < needed + margin:
        raise StorageError(f"Destination needs {needed + margin:,} free bytes; only {free:,} are available")
    if mode == "offload":
        _probe_exclusive(path for source in selected.values() for path in _store_paths(source))
    database_records = []
    job_database = _job_database(staging / "journal.sqlite3")
    try:
        for role, source in selected.items():
            reporter.check()
            relative = "databases/" + source.name
            target = _safe_target(staging, relative)
            record = _resume_record(job_database, relative, _database_signature(source), target, reporter)
            if record is None:
                details = _backup(source, target, reporter, unchanged=mode == "offload")
                record = {"kind": "database", "role": role, "source": str(source),
                          "relative": relative, **details}
                _record(job_database, relative, record)
            database_records.append({"role": role, "source": str(source),
                                     "target": str(final / _relative(relative)), **record})
        if snapshots:
            def copy_directory(directory):
                relative_directory = directory.relative_to(snapshots).as_posix()
                relative_directory = "snapshots" if relative_directory == "." else "snapshots/" + relative_directory
                _safe_target(staging, relative_directory).mkdir(parents=True, exist_ok=True)

            for source in _walk_files(snapshots, copy_directory):
                reporter.check()
                relative_source = source.relative_to(snapshots).as_posix()
                relative = "snapshots/" + relative_source
                target = _safe_target(staging, relative)
                record = _resume_record(job_database, relative, _signature(source), target, reporter)
                if record is None:
                    record = {"kind": "snapshot", "source": str(source), "relative": relative,
                              "snapshot_relative": relative_source, **_copy_file(source, target, reporter)}
                    _record(job_database, relative, record)
            (staging / "snapshots").mkdir(exist_ok=True)
        records_path = staging / "files.jsonl"
        files = 0
        byte_count = 0
        with records_path.open("w", encoding="utf-8", newline="\n") as stream:
            for row in job_database.execute("SELECT record FROM copied ORDER BY path"):
                record = json.loads(row[0])
                files += 1
                byte_count += record["size"]
                stream.write(row[0] + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        manifest = {**ownership, "bundle": str(final), "created_at": time.time(),
                    "status": "verified-stage", "file_count": files, "bytes": byte_count,
                    "records_sha256": _hash(records_path, reporter), "databases": database_records,
                    "snapshots": {"source": str(alias), "source_real": str(snapshots),
                                  "source_was_junction": _is_reparse(alias),
                                  "target": str(final / "snapshots")} if snapshots else None}
        _atomic_json(staging / "manifest.json", manifest)
    finally:
        job_database.close()
    reporter.check()
    if final.exists():
        raise StorageError("Permanent job destination already exists")
    staging.rename(final)
    reporter.emit("staged", force=True, message="Verified copy ready; original data is unchanged")
    return _result(manifest, manifest_path)


def _load_manifest(manifest_path) -> dict:
    path = Path(manifest_path).absolute()
    if not path.is_file() or _is_reparse(path) or _is_reparse(path.parent):
        raise StorageError("Invalid maintenance manifest location")
    manifest = _read_json(path)
    owner = _read_json(path.parent / OWNER)
    if any(manifest.get(key) != owner.get(key) for key in ("version", "job_id", "mode")) or owner.get("version") != VERSION:
        raise StorageError("Maintenance bundle ownership mismatch")
    if Path(manifest["bundle"]).resolve() != path.parent.resolve():
        raise StorageError("Maintenance manifest points at a different bundle")
    return manifest


def _records(bundle: Path):
    with (bundle / "files.jsonl").open("r", encoding="utf-8") as stream:
        while line := stream.readline(1024 * 1024):
            if not line.endswith("\n"):
                raise StorageError("Invalid or oversized manifest record")
            record = json.loads(line)
            if record.get("kind") not in ("database", "snapshot"):
                raise StorageError("Unexpected maintenance record kind")
            _relative(record["relative"])
            yield record


def verify_bundle(manifest_path, *, full_hash=True, progress=None, cancel_file=None, max_seconds=7200) -> dict:
    manifest = _load_manifest(manifest_path)
    bundle = Path(manifest["bundle"])
    reporter = _Progress(progress, cancel_file, max_seconds, manifest["job_id"])
    reporter.total = manifest["bytes"]
    if _hash(bundle / "files.jsonl", reporter) != manifest["records_sha256"]:
        raise StorageError("Maintenance inventory hash does not match")
    count = 0
    for record in _records(bundle):
        target = _safe_target(bundle, record["relative"])
        if not target.is_file() or _is_reparse(target) or target.stat().st_size != record["size"]:
            raise StorageError(f"Missing or changed destination file: {record['relative']}")
        if full_hash:
            if _hash(target, reporter) != record["sha256"]:
                raise StorageError(f"Destination content verification failed: {record['relative']}")
        elif _signature(target) != record["target_signature"]:
            raise StorageError(f"Destination identity changed: {record['relative']}")
        if record["kind"] == "database":
            with closing(_readonly_database(target)) as database:
                if _schema(database) != record["schema_sha256"]:
                    raise StorageError(f"Destination database schema changed: {record['relative']}")
        reporter.done += record["size"]
        reporter.files += 1
        count += 1
        reporter.emit("verify", path=target)
    if count != manifest["file_count"] or reporter.done != manifest["bytes"]:
        raise StorageError("Maintenance inventory count does not match")
    reporter.emit("verified", force=True)
    return {"ok": True, "files": count, "bytes": reporter.done}


def _junction(link: Path, target: Path) -> None:
    """Create an NTFS mount-point junction without a shell or command strings."""
    if os.name != "nt":
        raise StorageError("Snapshot offload requires Windows directory junction support")
    if str(target).startswith("\\\\"):
        raise StorageError("Snapshot junction target must be a local drive, not a network share")
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateFileW.argtypes = (wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                  wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE)
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.DeviceIoControl.argtypes = (wintypes.HANDLE, wintypes.DWORD, wintypes.LPVOID,
                                      wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD,
                                      ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID)
    kernel.CloseHandle.argtypes = (wintypes.HANDLE,)
    substitute = ("\\??\\" + str(target.resolve(strict=True))).encode("utf-16-le")
    printed = str(target.resolve(strict=True)).encode("utf-16-le")
    names = substitute + b"\x00\x00" + printed + b"\x00\x00"
    data = struct.pack("<IHHHHHH", 0xA0000003, len(names) + 8, 0,
                       0, len(substitute), len(substitute) + 2, len(printed)) + names
    buffer = ctypes.create_string_buffer(data)
    link.mkdir()
    handle = kernel.CreateFileW(str(link), 0x40000000, 0, None, 3, 0x02200000, None)
    if handle == ctypes.c_void_p(-1).value:
        link.rmdir()
        raise StorageError(f"Cannot open snapshot junction (Windows error {ctypes.get_last_error()})")
    try:
        returned = wintypes.DWORD()
        if not kernel.DeviceIoControl(handle, 0x900A4, buffer, len(data), None, 0, ctypes.byref(returned), None):
            raise StorageError(f"Cannot create snapshot junction (Windows error {ctypes.get_last_error()})")
    finally:
        kernel.CloseHandle(handle)


def _cutover_journal(manifest, journal=None):
    path = Path(manifest["bundle"]) / "snapshot-cutover.json"
    loaded = _read_json(path) if path.exists() else None
    if journal is not None and loaded != journal:
        raise StorageError("Snapshot journal differs from the durable journal")
    if loaded and loaded.get("job_id") != manifest["job_id"]:
        raise StorageError("Snapshot cutover ownership mismatch")
    if loaded:
        selected = manifest.get("snapshots")
        if not selected or any(Path(loaded[key]) != Path(selected[selection_key])
                               for key, selection_key in (("source", "source"), ("source_real", "source_real"), ("target", "target"))):
            raise StorageError("Snapshot cutover paths differ from the verified selection")
    return path, loaded


def _check_snapshot_source(manifest, root: Path, *, allow_missing=False):
    bundle = Path(manifest["bundle"])
    expected_count = 0
    for record in _records(bundle):
        if record["kind"] != "snapshot":
            continue
        source = root / _relative(record["snapshot_relative"])
        if not source.exists() and allow_missing:
            continue
        if not source.is_file() or _is_reparse(source) or _signature(source) != record["source_signature"]:
            raise StorageError(f"Snapshot source changed after staging: {record['snapshot_relative']}")
        expected_count += 1
    if sum(1 for _ in _walk_files(root)) != expected_count:
        raise StorageError("Snapshot source gained or lost files after staging; resume a fresh stage")


def commit_snapshots(manifest_path, *, progress=None) -> dict:
    """Cut over the original snapshot path, retaining the original tree for rollback."""
    manifest = _load_manifest(manifest_path)
    if manifest["mode"] != "offload":
        raise StorageError("Snapshot cutover requires an offload manifest")
    selection = manifest.get("snapshots")
    if not selection:
        return {"ok": True, "job_id": manifest["job_id"], "status": "not-selected"}
    verify_bundle(manifest_path, full_hash=False, progress=progress)
    path, existing = _cutover_journal(manifest)
    if existing:
        if existing["status"] in ("committed", "confirmed"):
            source = Path(existing["source"])
            if source.is_dir() and _is_reparse(source) and source.resolve() == Path(existing["target"]).resolve():
                return existing
        raise StorageError("Snapshot cutover is pending or rolled back; recover it before committing again")
    source = Path(selection["source"])
    target = Path(selection["target"])
    real = Path(selection["source_real"])
    if source.resolve(strict=True) != real:
        raise StorageError("Snapshot source location changed after staging")
    _check_snapshot_source(manifest, real)
    backup = source.with_name(source.name + ".fan-original-" + manifest["job_id"])
    if backup.exists():
        raise StorageError("Snapshot rollback folder already exists")
    journal = {"ok": True, "job_id": manifest["job_id"], "source": str(source),
               "source_real": str(real), "target": str(target), "backup": str(backup),
               "source_was_junction": selection["source_was_junction"], "status": "prepared"}
    _atomic_json(path, journal)
    try:
        source.rename(backup)
        journal["status"] = "source-renamed"
        _atomic_json(path, journal)
        _junction(source, target)
        journal["status"] = "committed"
        _atomic_json(path, journal)
        if source.resolve(strict=True) != target.resolve(strict=True):
            raise StorageError("Snapshot junction verification failed")
        return journal
    except Exception:
        rollback_snapshots(manifest_path)
        raise


def rollback_snapshots(manifest_path, journal=None) -> dict:
    """Recover an interrupted cutover; never remove unowned files/directories."""
    manifest = _load_manifest(manifest_path)
    path, journal = _cutover_journal(manifest, journal)
    if not journal:
        return {"ok": True, "status": "not-started", "job_id": manifest["job_id"]}
    if journal["status"] == "confirmed":
        raise StorageError("Confirmed snapshot cleanup cannot be rolled back")
    source, backup, target = (Path(journal[key]) for key in ("source", "backup", "target"))
    expected_backup = source.with_name(source.name + ".fan-original-" + manifest["job_id"])
    if backup != expected_backup or target != Path(manifest["snapshots"]["target"]):
        raise StorageError("Snapshot rollback paths do not belong to this job")
    if backup.exists():
        if source.exists():
            if _is_reparse(source) and source.resolve() == target.resolve():
                source.rmdir()  # rmdir removes the junction itself, not its target.
            elif not _is_reparse(source) and source.is_dir() and not any(source.iterdir()):
                source.rmdir()
            else:
                raise StorageError("Snapshot source was replaced by unowned data; rollback refused")
        backup.rename(source)
    if not source.exists():
        raise StorageError("Original snapshot folder is missing; manual recovery is required")
    journal["status"] = "rolled-back"
    _atomic_json(path, journal)
    return journal


def cleanup_offloaded_databases(manifest_path, active_paths, *, progress=None) -> dict:
    """Remove only unchanged selected originals after the coordinator commits targets."""
    manifest = _load_manifest(manifest_path)
    if manifest["mode"] != "offload":
        raise StorageError("Original cleanup requires an offload manifest")
    verify_bundle(manifest_path, full_hash=False, progress=progress)
    active = {key: Path(value).resolve(strict=True) for key, value in active_paths.items()}
    cleanup_path = Path(manifest["bundle"]) / "database-cleanup.json"
    previous = _read_json(cleanup_path) if cleanup_path.exists() else {}
    if previous and previous.get("job_id") != manifest["job_id"]:
        raise StorageError("Database cleanup journal ownership mismatch")
    recorded_signatures = previous.get("signatures", {})
    paths = []
    for record in manifest["databases"]:
        role = record["role"]
        target = Path(record["target"]).resolve(strict=True)
        source = Path(record["source"])
        if role not in DATABASES or source.name.lower() != DATABASES[role].lower() or active.get(role) != target or source.resolve() == target:
            raise StorageError("Active database targets were not confirmed for this job")
        if source.exists():
            if _database_signature(source) != record["source_signature"]:
                raise StorageError(f"Original database changed after staging: {source.name}")
            paths.extend(path for path in _store_paths(source) if path.exists())
        else:
            # A stopped cleanup may already have removed the main file. Only
            # previously confirmed sidecars with unchanged identities can follow.
            for path in _store_paths(source)[1:]:
                if path.exists():
                    if recorded_signatures.get(str(path)) != _signature(path):
                        raise StorageError(f"Unconfirmed original sidecar remains: {path.name}")
                    paths.append(path)
    _probe_exclusive(paths)
    removed = []
    # Record confirmation before deletion so a stopped cleanup can safely resume.
    confirmed = {"job_id": manifest["job_id"], "status": "confirmed", "paths": [str(path) for path in paths],
                 "signatures": {str(path): _signature(path) for path in paths}}
    _atomic_json(cleanup_path, confirmed)
    for path in paths:
        path.unlink()
        removed.append(str(path))
    _atomic_json(cleanup_path, {**confirmed, "status": "complete", "removed": removed})
    return {"ok": True, "removed": removed}


def cleanup_offloaded_snapshots(manifest_path, journal=None, *, progress=None) -> dict:
    """Confirm cutover and remove the unchanged, job-owned original snapshot copy."""
    manifest = _load_manifest(manifest_path)
    if manifest["mode"] != "offload":
        raise StorageError("Original cleanup requires an offload manifest")
    path, journal = _cutover_journal(manifest, journal)
    if not manifest.get("snapshots"):
        return {"ok": True, "status": "not-selected"}
    if not journal or journal["status"] not in ("committed", "confirmed"):
        raise StorageError("Snapshot cutover has not been committed")
    source, backup, target = (Path(journal[key]) for key in ("source", "backup", "target"))
    if backup != source.with_name(source.name + ".fan-original-" + manifest["job_id"]) or target != Path(manifest["snapshots"]["target"]):
        raise StorageError("Snapshot cleanup paths do not belong to this job")
    if not _is_reparse(source) or source.resolve(strict=True) != target.resolve(strict=True):
        raise StorageError("Active snapshot junction is not the committed target")
    verify_bundle(manifest_path, full_hash=False, progress=progress)
    if not backup.exists():
        if journal["status"] == "confirmed":
            return {"ok": True, "status": "complete", "removed": 0}
        raise StorageError("Snapshot original backup disappeared before confirmation")
    physical = backup.resolve(strict=True)
    expected = Path(journal["source_real"]) if journal["source_was_junction"] else backup
    if physical != expected.resolve(strict=True):
        raise StorageError("Original snapshot location changed before cleanup")
    _check_snapshot_source(manifest, physical, allow_missing=journal["status"] == "confirmed")
    journal["status"] = "confirmed"
    _atomic_json(path, journal)
    reporter = _Progress(progress, job_id=manifest["job_id"])
    reporter.total = manifest["bytes"]
    reporter.emit("snapshot-cleanup", force=True, message="Reclaiming the confirmed original snapshot files")
    removed = 0
    for record in _records(Path(manifest["bundle"])):
        if record["kind"] == "snapshot":
            original = physical / _relative(record["snapshot_relative"])
            if original.exists():
                original.unlink()
                removed += 1
                reporter.files = removed
                reporter.done += record["size"]
                reporter.emit("snapshot-cleanup", path=original)
    # Only remove directories after their verified files; never recursively
    # remove a directory containing newly added or unrelated content.
    for directory in _empty_directories(physical):
        directory.rmdir()
    if journal["source_was_junction"]:
        backup.rmdir()
    journal["cleanup_complete"] = True
    _atomic_json(path, journal)
    reporter.emit("snapshot-cleanup-complete", force=True)
    return {"ok": True, "status": "complete", "removed": removed}
