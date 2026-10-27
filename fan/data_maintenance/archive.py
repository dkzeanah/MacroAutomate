"""Verified archives followed by recoverable replacement with empty schemas."""
from contextlib import closing
import os
from pathlib import Path
import sqlite3

from . import storage


def _empty_schema(archive: Path, target: Path, expected: str):
    if os.path.lexists(target):
        if storage._is_reparse(target):
            raise storage.StorageError("Reset staging path is a link")
        target.unlink()
    with closing(storage._readonly_database(archive)) as old, closing(sqlite3.connect(target)) as new:
        # Virtual tables create their own shadow tables. Recreating shadows
        # explicitly would either fail or carry stale FTS/RTree state forward.
        shadows = {row[1] for row in old.execute('PRAGMA table_list') if row[2] == 'shadow'}
        objects = old.execute("SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL "
                              "AND name NOT LIKE 'sqlite_%' ORDER BY rowid").fetchall()
        new.execute('PRAGMA foreign_keys=OFF')
        for kind in ('table', 'view', 'index', 'trigger'):
            for object_kind, name, sql in objects:
                if object_kind == kind and name not in shadows:
                    new.execute(sql)
        for pragma in ('user_version', 'application_id'):
            new.execute(f'PRAGMA {pragma}={old.execute("PRAGMA " + pragma).fetchone()[0]}')
        new.commit()
        if storage._schema(new) != expected or new.execute('PRAGMA quick_check').fetchall() != [('ok',)]:
            raise storage.StorageError('Empty replacement schema did not verify')
        if new.execute('PRAGMA foreign_key_check').fetchone():
            raise storage.StorageError('Empty replacement has invalid relationships')
    with target.open('r+b') as stream:
        os.fsync(stream.fileno())


def reset_databases(manifest_path, *, progress=None):
    """Idempotently replace unchanged originals only after a verified archive.

    A durable per-store journal precedes each replacement. Recovery accepts only
    the original identity or the exact staged replacement; unknown writes block
    startup instead of discarding them. Archives are never made active stores.
    """
    manifest = storage._load_manifest(manifest_path)
    storage.verify_bundle(manifest_path, progress=progress)
    bundle = Path(manifest['bundle'])
    journal_path = bundle / 'database-reset.json'
    journal = storage._read_json(journal_path) if journal_path.exists() else {
        'job_id': manifest['job_id'], 'status': 'staging', 'stores': {}}
    if journal.get('job_id') != manifest['job_id']:
        raise storage.StorageError('Reset journal belongs to another job')
    if journal['status'] == 'complete':
        return journal
    records = manifest['databases']
    # Stage every schema before any original is removed.
    for record in records:
        role, source = record['role'], Path(record['source'])
        if role not in storage.DATABASES or source.name.lower() != storage.DATABASES[role].lower():
            raise storage.StorageError('Unexpected database selected for reset')
        entry = journal['stores'].get(role)
        if entry:
            continue
        if storage._database_signature(source) != record['source_signature']:
            raise storage.StorageError(f'Original changed before reset: {source.name}')
        fresh = source.with_name(source.name + '.fan-reset-' + manifest['job_id'])
        _empty_schema(Path(record['target']), fresh, record['schema_sha256'])
        journal['stores'][role] = {'source': str(source), 'fresh': str(fresh),
                                   'signature': storage._signature(fresh), 'status': 'staged'}
        storage._atomic_json(journal_path, journal)
    journal['status'] = 'replacing'
    storage._atomic_json(journal_path, journal)
    for record in records:
        entry = journal['stores'][record['role']]
        source, fresh = Path(entry['source']), Path(entry['fresh'])
        expected_fresh = source.with_name(source.name + '.fan-reset-' + manifest['job_id'])
        if source != Path(record['source']) or fresh != expected_fresh:
            raise storage.StorageError('Reset journal path mismatch')
        if entry['status'] == 'complete':
            continue
        installed = source.exists() and storage._signature(source) == entry['signature']
        if not installed:
            removed = not source.exists() and entry['status'] == 'installing'
            if not removed and (not source.exists() or storage._database_signature(source) != record['source_signature']):
                raise storage.StorageError(f'Unknown database changes during reset: {source.name}')
            if not fresh.exists() or storage._signature(fresh) != entry['signature']:
                raise storage.StorageError('Staged replacement changed or disappeared')
            storage._probe_exclusive(storage._store_paths(source))
            # Record sidecar identities before removing any of them.
            if not removed:
                entry['sidecars'] = {str(path): storage._signature(path)
                                     for path in storage._store_paths(source)[1:] if path.exists()}
            entry['status'] = 'installing'
            storage._atomic_json(journal_path, journal)
            # Windows guards permit unlinking but can prevent replacing a live
            # name. Durable install intent recovers this brief missing-name gap.
            if source.exists():
                source.unlink()
        for path, signature in entry.get('sidecars', {}).items():
            sidecar = Path(path)
            if sidecar.exists():
                if storage._signature(sidecar) != signature:
                    raise storage.StorageError('Original sidecar changed during reset')
                sidecar.unlink()
        if not installed:
            os.replace(fresh, source)
        # A crash after replace but before journaling is recognized by identity.
        if storage._signature(source) != entry['signature']:
            raise storage.StorageError('Replacement identity did not verify')
        entry['status'] = 'complete'
        storage._atomic_json(journal_path, journal)
        if progress:
            progress({'phase': 'resetting', 'message': 'Empty schema installed: ' + source.name})
    journal['status'] = 'complete'
    storage._atomic_json(journal_path, journal)
    return journal
