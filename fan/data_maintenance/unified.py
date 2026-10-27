"""Single Fan data store, evergreen seeding, and explicit legacy consolidation.

The large tracking store is extended in place, not copied onto the nearly-full
system disk. Consolidation must only run after an external Explorer move ends.
Startup never imports or deletes historical stores or loose photos.
"""
from __future__ import annotations

import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import sys
import time
import traceback

from . import photos, storage

SCHEMA = Path(__file__).with_name('schema.sql')
TEXT_NAMES = {
    'coordinates.csv', 'sequences.ini', 'hotkeys.ini', 'settings.ini',
    'extraction_rules.csv', 'patterns.ini', 'spools.ini', 'ocr_log.txt',
    'ocr_words.ini', 'analytics.ini', 'recording.csv', 'hotstrings.txt',
    'notification_schedule.txt', 'templates.json', 'notification_triggers.json',
    'revolver_bins.ini', 'taskbar.ini', 'appointments.ini', 'patients.ini', 'trigger_log.txt', 'tracking_errors.log',
}
TEXT_EXTENSIONS = {'.txt', '.log', '.json', '.jsonl', '.md', '.csv'}


def legacy_paths(project):
    data, bridge = Path(project) / 'data', Path(project) / 'fan' / 'DeepSeekBridge'
    return {'tracking': data / 'tracking.db', 'macro': data / 'macroauto.sqlite',
            'appmap': data / 'appmap.db', 'bridge': bridge / 'bridge.sqlite3',
            'catalog': bridge / '.runtime' / 'tool_catalog.sqlite3'}


def seed(path):
    """Atomic empty schema. A missing active store is deliberately a fresh start."""
    path = Path(path).absolute()
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        return False
    for suffix in ('-wal', '-journal'):
        sidecar = Path(str(path) + suffix)
        if sidecar.exists() and sidecar.stat().st_size:
            raise storage.StorageError('An orphan SQLite journal remains at the active location. Close Fan and retain/move its journal with the archive before seeding: ' + str(sidecar))
    temp = path.with_name(path.name + '.seed-' + str(os.getpid()))
    try:
        with closing(sqlite3.connect(temp)) as db:
            db.executescript(SCHEMA.read_text(encoding='utf-8'))
            db.execute("INSERT OR REPLACE INTO fan_store(key,value) VALUES('layout','unified-v1')")
            db.commit()
            if db.execute('PRAGMA quick_check').fetchone()[0] != 'ok':
                raise storage.StorageError('Fresh schema did not verify')
        # A competing startup cannot silently replace a store created meanwhile.
        if os.name == 'nt':
            os.rename(temp, path)  # Windows rename refuses an existing destination.
        else:
            os.link(temp, path)
        return True
    except FileExistsError:
        return False
    finally:
        temp.unlink(missing_ok=True)


def bootstrap(project):
    project = Path(project).absolute()
    config_path = project / 'fan' / 'storage_paths.json'
    config = json.loads(config_path.read_text(encoding='utf-8-sig')) if config_path.exists() else {}
    active = Path(config.get('unified_db', project / 'data' / 'fan.sqlite')).absolute()
    active.parent.mkdir(parents=True, exist_ok=True)
    created = seed(active)
    if active.exists() and not config.get('unified_initialized'):
        with closing(sqlite3.connect(active, timeout=10)) as db:
            preferences = {key: value for key, value in config.items() if key not in ('databases', 'unified_db', 'unified_initialized')}
            db.execute('INSERT OR REPLACE INTO app_config(key,value) VALUES(?,?)', ('preferences', json.dumps(preferences)))
            db.commit()
    # This small machine-local pointer is not application history or settings.
    storage._atomic_json(config_path, {'unified_db': str(active), 'unified_initialized': True})
    return {'database': str(active), 'seeded': created}


def _quote(name):
    return '"' + name.replace('"', '""') + '"'


def _digest(rows):
    digest, count = hashlib.sha256(), 0
    for row in rows:
        payload = json.dumps(list(row), ensure_ascii=False, separators=(',', ':'),
                             default=lambda value: {'bytes': value.hex()}).encode('utf-8')
        digest.update(len(payload).to_bytes(8, 'big'))
        digest.update(payload)
        count += 1
    return count, digest.hexdigest()


def _copy_role(target, source_path, role):
    """Small stores use SQLite's backup/ALTER APIs to namespace their schemas."""
    if source_path.stat().st_size > 256 * 1024 * 1024:
        raise storage.StorageError('Legacy side store exceeds the bounded migration size: ' + str(source_path))
    with closing(sqlite3.connect(':memory:')) as source:
        with closing(storage._readonly_database(source_path)) as original:
            original.backup(source)
        if role == 'appmap' and source.execute("SELECT 1 FROM sqlite_master WHERE name='app'").fetchone():
            source.execute('ALTER TABLE app RENAME TO appmap_app')
        objects = source.execute("SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'view' THEN 1 WHEN 'index' THEN 2 ELSE 3 END,name").fetchall()
        tables = [name for kind, name, _ in objects if kind == 'table']
        if any('VIRTUAL TABLE' in sql.upper() for kind, _, sql in objects if kind == 'table'):
            raise storage.StorageError('Virtual side-store tables require a dedicated migration')
        for kind, name, sql in objects:
            existing = target.execute('SELECT sql FROM sqlite_master WHERE name=?', (name,)).fetchone()
            if existing:
                raise storage.StorageError(f'Conflicting object {role}.{name}; originals retained')
            if kind == 'table':
                target.execute(sql)
        verified = {}
        for name in tables:
            columns = [row[1] for row in source.execute('PRAGMA table_xinfo(' + _quote(name) + ')') if row[6] == 0]
            select = ','.join(map(_quote, columns))
            insert = f'INSERT INTO {_quote(name)}({select}) VALUES({",".join("?" for _ in columns)})'
            info = list(source.execute('PRAGMA table_xinfo(' + _quote(name) + ')'))
            definition = next(sql for kind, table, sql in objects if kind == 'table' and table == name)
            order = ','.join(_quote(row[1]) for row in sorted(info, key=lambda row: row[5]) if row[5]) if 'WITHOUT ROWID' in definition.upper() else 'rowid'
            query = f'SELECT {select} FROM {_quote(name)} ORDER BY {order}'
            cursor = source.execute(query)
            while chunk := cursor.fetchmany(500):
                target.executemany(insert, chunk)
            expected = _digest(source.execute(query))
            actual = _digest(target.execute(query))
            if expected != actual:
                raise storage.StorageError('Consolidated rows did not verify: ' + name)
            verified[name] = expected[0]
        # Install triggers after data copy to avoid replaying historical effects.
        for kind, _, sql in objects:
            if kind != 'table':
                target.execute(sql)
        if source.execute("SELECT 1 FROM sqlite_master WHERE name='sqlite_sequence'").fetchone():
            for name, sequence in source.execute('SELECT name,seq FROM sqlite_sequence'):
                target.execute('DELETE FROM sqlite_sequence WHERE name=?', (name,))
                target.execute('INSERT INTO sqlite_sequence(name,seq) VALUES(?,?)', (name, sequence))
        return verified


def text_files(project):
    project = Path(project).resolve()
    candidates = []
    for folder in (project / 'data', project / 'fan' / 'data'):
        if folder.is_dir():
            candidates.extend(file for file in folder.iterdir() if file.name.lower() in TEXT_NAMES)
    for folder in (project / 'data' / 'notes', project / 'data' / 'logs',
                   project / 'data' / 'learning_insights', project / 'fan' / 'logs' / 'study'):
        if folder.is_dir() and not storage._is_reparse(folder):
            candidates.extend(file for file in storage._walk_files(folder) if file.suffix.lower() in TEXT_EXTENSIONS)
    return [file for file in candidates if file.is_file() and not storage._is_reparse(file)
            and storage._contained(file.resolve(), project)]


def _read_text(path):
    data = path.read_bytes()
    if data.startswith((b'\xff\xfe', b'\xfe\xff')):
        return data.decode('utf-16')
    try:
        return data.decode('utf-8-sig')
    except UnicodeDecodeError:
        return data.decode('cp1252')


def consolidate(project, archive_path, *, snapshot_root=None, progress=None, cancel_file=None):
    """Explicit offline merge into the moved tracking DB. Sources are retained.

    The source folder and DB must have disappeared before the K: archive is
    opened, and exclusive probes refuse files still held by Explorer or Fan.
    This is repeatable: each side-store's fingerprint and verified counts are
    committed in the same transaction as its rows.
    """
    project, archive_path = Path(project).resolve(), Path(archive_path).resolve()
    paths = legacy_paths(project)
    if paths['tracking'].exists() and paths['tracking'].resolve() != archive_path:
        raise storage.StorageError('The original tracking DB still exists. Wait for the Explorer move to finish.')
    if paths['tracking'].resolve() != archive_path:
        for suffix in ('-wal', '-journal'):
            journal = Path(str(paths['tracking']) + suffix)
            if journal.exists() and journal.stat().st_size:
                raise storage.StorageError('An original tracking journal still contains data. Retain/move it with the archive before consolidation: ' + str(journal))
    original_photos = project / 'data' / 'tracking' / 'snapshots'
    if snapshot_root and original_photos.exists() and original_photos.resolve() != Path(snapshot_root).resolve():
        if any(file.is_file() for file in original_photos.rglob('*')):
            raise storage.StorageError('The original snapshots still contain files. Wait for the Explorer move to finish.')
    if not archive_path.is_file() or storage._is_reparse(archive_path):
        raise storage.StorageError('The moved archive is unavailable')
    storage._probe_exclusive(path for db in [archive_path, *paths.values()] if db.exists()
                             for path in storage._store_paths(db))
    reporter = storage._Progress(progress, cancel_file)
    with closing(sqlite3.connect(archive_path, timeout=15)) as db:
        db.execute('PRAGMA busy_timeout=15000')
        db.execute('PRAGMA foreign_keys=OFF')
        db.execute('CREATE TABLE IF NOT EXISTS fan_store(key TEXT PRIMARY KEY,value TEXT NOT NULL)')
        db.execute('CREATE TABLE IF NOT EXISTS fan_migration(role TEXT PRIMARY KEY,source TEXT,signature TEXT,counts TEXT)')
        db.execute("CREATE TABLE IF NOT EXISTS app_file(path TEXT PRIMARY KEY,content TEXT NOT NULL DEFAULT '',modified_ts TEXT)")
        db.execute('CREATE TABLE IF NOT EXISTS app_config(key TEXT PRIMARY KEY,value TEXT NOT NULL)')
        db.commit()
        for role, source in paths.items():
            reporter.check()
            if role == 'tracking' or not source.is_file() or source.resolve() == archive_path:
                continue
            signature = json.dumps(storage._database_signature(source), sort_keys=True)
            previous = db.execute('SELECT signature FROM fan_migration WHERE role=?', (role,)).fetchone()
            if previous:
                if previous[0] != signature:
                    raise storage.StorageError('A previously consolidated store changed: ' + role)
                continue
            reporter.emit('consolidating', role=role)
            with db:
                counts = _copy_role(db, source.resolve(), role)
                if signature != json.dumps(storage._database_signature(source), sort_keys=True):
                    raise storage.StorageError('Legacy store changed during consolidation: ' + role)
                db.execute('INSERT INTO fan_migration VALUES(?,?,?,?)', (role, str(source), signature, json.dumps(counts)))
        for file in text_files(project):
            reporter.check()
            before = storage._signature(file)
            content = _read_text(file)
            if before != storage._signature(file):
                raise storage.StorageError('Document changed during consolidation: ' + str(file))
            key = file.relative_to(project).as_posix().lower()
            with db:
                db.execute("INSERT OR IGNORE INTO app_file VALUES(?,?,datetime('now','localtime'))", (key, content))
        config_path = project / 'fan' / 'storage_paths.json'
        if config_path.exists():
            with db:
                db.execute('INSERT OR IGNORE INTO app_config VALUES(?,?)', ('legacy_storage_routes', config_path.read_text(encoding='utf-8-sig')))
        with db:
            db.execute("INSERT OR REPLACE INTO fan_store VALUES('layout','unified-v1')")
    unified_paths = {role: archive_path for role in paths}
    photo_result = photos.import_photos(project, unified_paths, progress=progress, cancel_file=cancel_file,
                                       relocated_snapshots=snapshot_root, remove_files=False)
    with closing(sqlite3.connect(archive_path)) as db:
        checkpoint = db.execute('PRAGMA wal_checkpoint(TRUNCATE)').fetchone()
        if checkpoint[0]:
            raise storage.StorageError('Close all readers so the archive can be checkpointed into one file')
        counts = dict(db.execute('SELECT role,counts FROM fan_migration'))
    return {'archive': str(archive_path), 'stores': counts, 'photos': photo_result,
            'originals_retained': True}


def queue_consolidation(project, archive_path, snapshot_root, job_dir, *, wait_seconds=14400, poll_seconds=10):
    """Wait without opening moving items, then finish the user-requested merge."""
    project, job_dir = Path(project).resolve(), Path(job_dir).resolve()
    job_dir.mkdir(parents=True, exist_ok=True)
    status_path, cancel = job_dir / 'status.json', job_dir / 'cancel'
    deadline = time.monotonic() + wait_seconds

    def status(phase, message, **extra):
        storage._atomic_json(status_path, {'phase': phase, 'message': message,
                                          'worker_pid': os.getpid(), 'archive': str(archive_path), **extra})

    try:
        while True:
            if cancel.exists():
                status('cancelled', 'Archive consolidation cancelled; source files retained.')
                return
            source = legacy_paths(project)['tracking']
            snapshots = project / 'data' / 'tracking' / 'snapshots'
            # Explorer removes these source names when its cut/paste finishes.
            # File lengths at the destination can be preallocated, so they are
            # not evidence of a completed move.
            waiting = source.exists() or snapshots.exists() or not Path(archive_path).is_file() or not Path(snapshot_root).is_dir()
            waiting = waiting or any(journal.exists() and journal.stat().st_size for journal in
                                     (Path(str(source) + '-wal'), Path(str(source) + '-journal')))
            if not waiting:
                try:
                    storage._probe_exclusive(path for db in [Path(archive_path), *legacy_paths(project).values()]
                                             if db.exists() for path in storage._store_paths(db))
                except storage.StorageError:
                    waiting = True
            if not waiting:
                break
            status('waiting', 'Waiting for Explorer to finish moving the original database and snapshots. Archive has not been opened.')
            if time.monotonic() >= deadline:
                status('deferred', 'Explorer move is still incomplete or a legacy store is in use. Finish it, then use Settings > Consolidate old archive.')
                return
            time.sleep(poll_seconds)

        def progress(event):
            status('consolidating', 'Consolidating historical data: ' + str(event.get('role') or event.get('path') or ''), progress=event)

        result = consolidate(project, archive_path, snapshot_root=snapshot_root, progress=progress, cancel_file=cancel)
        storage._atomic_json(job_dir / 'result.json', result)
        message = 'Historical Fan stores consolidated. Original photo files and small legacy stores retained for verification.'
        if result['photos']['missing']:
            message += f" {result['photos']['missing']} legacy image paths were unavailable; review before removing originals."
        status('complete', message, **result)
    except storage.Cancelled:
        status('cancelled', 'Archive consolidation cancelled at a safe checkpoint; source files retained.')
    except Exception as exc:
        (job_dir / 'error.log').write_text(traceback.format_exc(), encoding='utf-8')
        status('error', str(exc) + '. Source files retained; use Settings to retry.')
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    start = commands.add_parser('bootstrap')
    start.add_argument('project', type=Path)
    merge = commands.add_parser('consolidate')
    merge.add_argument('project', type=Path)
    merge.add_argument('archive', type=Path)
    merge.add_argument('--snapshots', type=Path)
    queue = commands.add_parser('queue')
    queue.add_argument('project', type=Path)
    queue.add_argument('archive', type=Path)
    queue.add_argument('snapshots', type=Path)
    queue.add_argument('job_dir', type=Path)
    queue.add_argument('--wait-seconds', type=int, default=14400)
    args = parser.parse_args()
    try:
        if args.command == 'bootstrap':
            result = bootstrap(args.project)
        elif args.command == 'consolidate':
            result = consolidate(args.project, args.archive, snapshot_root=args.snapshots,
                                 progress=lambda event: print(json.dumps(event), flush=True))
        else:
            queue_consolidation(args.project, args.archive, args.snapshots, args.job_dir, wait_seconds=args.wait_seconds)
            return
        print(json.dumps(result), flush=True)
    except Exception:
        if args.command == 'bootstrap':
            (args.project / 'fan' / 'unified-startup.log').write_text(traceback.format_exc(), encoding='utf-8')
        else:
            traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
