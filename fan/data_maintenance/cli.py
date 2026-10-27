"""Background coordinator for Settings jobs. Never sends raw history to a model."""
from __future__ import annotations
import argparse
from contextlib import closing, nullcontext
import ctypes
import json
import os
from pathlib import Path
import sqlite3
import sys
import time
import traceback

from . import storage, insights, archive, photos, unified


def atomic_json(path: Path, value: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + '.tmp')
    with temp.open('w', encoding='utf-8') as handle:
        handle.write(json.dumps(value, ensure_ascii=False, indent=2))
        handle.flush()
        os.fsync(handle.fileno())
    for attempt in range(20):
        try:
            os.replace(temp, path)
            return
        except PermissionError:
            if attempt == 19:
                raise
            time.sleep(.05)


def atomic_text(path: Path, value: str):
    temp = path.with_name(path.name + '.tmp')
    temp.write_text(value, encoding='utf-8')
    os.replace(temp, path)


def load_config(project: Path) -> dict:
    path = project / 'fan' / 'storage_paths.json'
    config = json.loads(path.read_text(encoding='utf-8-sig')) if path.exists() else {}
    active = Path(config['unified_db']) if config.get('unified_db') else None
    if active and active.exists():
        with closing(storage._readonly_database(active.resolve())) as db:
            if db.execute("SELECT 1 FROM sqlite_master WHERE name='app_config'").fetchone():
                row = db.execute("SELECT value FROM app_config WHERE key='preferences'").fetchone()
                if row:
                    config.update({key: value for key, value in json.loads(row[0]).items()
                                   if key not in ('unified_db', 'unified_initialized', 'databases')})
    return config


def save_config(project: Path, config: dict):
    if config.get('unified_db'):
        with closing(sqlite3.connect(config['unified_db'], timeout=15)) as db:
            preferences = {key: value for key, value in config.items() if key not in ('unified_db', 'unified_initialized', 'databases')}
            db.execute("INSERT INTO app_config(key,value) VALUES('preferences',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                       (json.dumps(preferences),))
            db.commit()
        config = {'unified_db': config['unified_db'], 'unified_initialized': True}
    atomic_json(project / 'fan' / 'storage_paths.json', config)


def managed_paths(project: Path, config: dict | None = None) -> dict[str, Path]:
    data, bridge = project / 'data', project / 'fan' / 'DeepSeekBridge'
    defaults = {'tracking': data / 'tracking.db', 'macro': data / 'macroauto.sqlite',
                'appmap': data / 'appmap.db', 'bridge': bridge / 'bridge.sqlite3',
                'catalog': bridge / '.runtime' / 'tool_catalog.sqlite3'}
    config = config if config is not None else load_config(project)
    if config.get('unified_db'):
        return {role: Path(config['unified_db']).absolute() for role in defaults}
    routes = config.get('databases', {})
    return {role: Path(routes.get(role, str(path))).absolute() for role, path in defaults.items()}


def parent_alive(pid: int) -> bool:
    if not pid:
        return False
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.restype = ctypes.c_void_p
    kernel.GetExitCodeProcess.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    handle = kernel.OpenProcess(0x1000, False, pid)
    if not handle:
        return False
    value = ctypes.c_ulong()
    try:
        return bool(kernel.GetExitCodeProcess(handle, ctypes.byref(value))) and value.value == 259
    finally:
        kernel.CloseHandle(handle)


def publish_insights(project: Path, report: dict, paths: dict[str, Path]) -> dict:
    folder = project / 'data' / 'learning_insights'
    brief = insights.compact_prompt(report, max_chars=7500)
    if load_config(project).get('unified_db'):
        with closing(sqlite3.connect(paths['tracking'], timeout=15)) as db:
            for name, content in {'latest.json': json.dumps(report), 'latest.md': insights.markdown(report), 'latest-brief.txt': brief}.items():
                db.execute("INSERT INTO app_file(path,content,modified_ts) VALUES(?,?,datetime('now','localtime')) "
                           "ON CONFLICT(path) DO UPDATE SET content=excluded.content,modified_ts=excluded.modified_ts",
                           ('data/learning_insights/' + name, content))
            db.commit()
        written = {'database': str(paths['tracking'])}
    else:
        written = insights.write_report(report, folder)
        atomic_json(folder / 'latest.json', report)
        atomic_text(folder / 'latest.md', insights.markdown(report))
        atomic_text(folder / 'latest-brief.txt', brief)
    # Reusable compact record; no original log/image blobs are copied into it.
    index = paths['catalog']
    if index.exists():
        sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'DeepSeekBridge'))
        from bridge import library
        previous_index = library.INDEX
        try:
            library.INDEX = index
            library.save('knowledge:consolidated-learning-insights', 'knowledge', brief,
                     description='Current evidence-backed learning metrics and automation improvement candidates',
                     tags=['learning', 'consolidated', 'automation'],
                     usage='Read latest learning insights, verify evidence freshness and live targets before applying a candidate.',
                     metadata={'source_kind': 'reference', 'generated_at': report.get('generated_at', ''),
                               'report_path': str(folder / 'latest.json'),
                               'warning': 'Measurements are observed; recommendations are candidates, not verified workflows.'})
        finally:
            library.INDEX = previous_index
    return {'report': str(folder / 'latest.md'), 'details': str(folder / 'latest.json'), 'written': str(written)}


def run(request_path: Path):
    request_path = request_path.absolute()
    request = json.loads(request_path.read_text(encoding='utf-8-sig'))
    job_dir = request_path.parent
    project = Path(request['project']).absolute()
    if not (project / 'fan' / 'MacroAutomator.ahk').is_file():
        raise ValueError('Choose the actual Fan project root')
    mode = request['mode']
    if mode not in ('analyze', 'export', 'offload', 'images', 'consolidate'):
        raise ValueError('Unknown maintenance job mode')
    state_path = job_dir / 'status.json'
    cancel_file = job_dir / 'cancel'
    started = time.monotonic()

    def status(phase: str, message: str, **extra):
        atomic_json(state_path, {'phase': phase, 'message': message,
                                'worker_pid': os.getpid(), 'elapsed_seconds': round(time.monotonic()-started, 1), **extra})

    def progress(event: dict):
        phase = event.get('phase', 'working')
        detail = event.get('message', '') or event.get('path', '') or event.get('role', '')
        total, done = event.get('bytes_total', 0), event.get('bytes_done', 0)
        size = f" · {done/1073741824:.2f}/{total/1073741824:.2f} GB · {event.get('files_done', 0)} files" if total else ''
        status(phase, f'{phase}{size}: {detail}', progress=event)

    manifest, snapshot_journal, configured = None, None, False
    try:
        config = load_config(project)
        if config.get('unified_db') and not Path(config['unified_db']).exists():
            unified.bootstrap(project)
            config = load_config(project)
        paths = managed_paths(project, config)
        missing = [role for role in config.get('databases', {}) if role in paths and not paths[role].exists()]
        if missing:
            raise storage.StorageError('Configured stores are unavailable: ' + ', '.join(missing) + '; reconnect their drive')
        supplied = {role: Path(path).absolute() for role, path in request.get('databases', {}).items()}
        if supplied and supplied != paths:
            raise ValueError('Storage routes changed; start a fresh Settings job')
        if mode != 'analyze':
            status('waiting', 'Waiting for Fan to save state and close its stores...')
            deadline = time.monotonic() + 90
            while parent_alive(int(request.get('parent', 0))) or parent_alive(int(request.get('bridge_parent', 0))):
                if cancel_file.exists():
                    raise storage.Cancelled('Job cancelled before Fan closed')
                if time.monotonic() > deadline:
                    raise storage.StorageError('Fan did not close its stores; job was not started')
                time.sleep(.25)
            storage._probe_exclusive(path for source in paths.values() if source.exists()
                                     for path in storage._store_paths(source))
        if mode == 'images':
            result = photos.import_photos(project, paths, progress=progress, cancel_file=cancel_file)
            status('complete', f"Photos imported: {result['imported']}; owned files reclaimed: {result['removed']}; missing files: {result['missing']}", **result)
            return
        if mode == 'consolidate':
            result = unified.consolidate(project, request['destination'], snapshot_root=request.get('relocated_snapshots'),
                                         progress=progress, cancel_file=cancel_file)
            status('complete', 'Historical Fan data consolidated into the archive. Source files retained; active database unchanged.', **result)
            (project / 'fan' / '.maintenance' / 'pending.json').unlink(missing_ok=True)
            return
        if mode == 'analyze':
            status('analyzing', 'Consolidating recent evidence with bounded read-only queries…')
            report = insights.analyze(paths, days=int(request.get('days', 30)),
                                      row_limit=int(request.get('row_limit', 5000)),
                                      max_seconds=float(request.get('max_seconds', 30)))
            if cancel_file.exists():
                raise storage.Cancelled('Analysis cancelled before publishing')
            published = publish_insights(project, report, paths)
            status('complete', 'Compact insights published for automation and DeepSeek.', **published)
            return
        scope = request['scope']
        if scope not in ('databases', 'snapshots'):
            raise ValueError('Select databases or snapshots')
        if scope == 'snapshots' and mode == 'export':
            photos.import_photos(project, paths, progress=progress, cancel_file=cancel_file)
            result = photos.export_photos(paths, request['destination'], request['id'], progress=progress, cancel_file=cancel_file)
            status('complete', f"Exported {result['images']} verified image files from database photos.", **result)
            return
        reset = scope == 'databases'
        selected = ({'unified': Path(config['unified_db'])} if config.get('unified_db') else
                    {role: path for role, path in paths.items() if path.exists()}) if scope == 'databases' else {}
        if reset:
            photos.import_photos(project, paths, progress=progress, cancel_file=cancel_file)
        if scope == 'databases' and not selected:
            raise storage.StorageError('No existing managed databases to transfer')
        snapshot_root = project / 'data' / 'tracking' / 'snapshots' if scope == 'snapshots' else None
        result = storage.prepare_export(selected, snapshot_root, Path(request['destination']), mode='offload' if reset else mode,
                                        job_id=request['id'], progress=progress, cancel_file=cancel_file,
                                        max_seconds=float(request.get('max_seconds', 7200)))
        manifest = result['manifest']
        atomic_json(job_dir / 'result.json', result)
        if reset:
            if cancel_file.exists():
                raise storage.Cancelled('Archive cancelled before reset; originals retained')
            # Durable intent makes partial resets recover before any DB opens.
            atomic_json(job_dir / 'reset-intent.json', {'manifest': str(manifest)})
            status('committing', 'Archive verified. Installing fresh database schemas...')
            with storage.hold_originals(manifest):
                cleanup = archive.reset_databases(manifest, progress=progress)
            config['last_archive'] = {'manifest': str(manifest), 'job': str(job_dir), 'mode': mode}
            config['snapshot_embed_base64'] = True
            save_config(project, config)
            status('complete', 'Archive verified; original databases replaced with empty schemas. Fan is ready to start fresh.',
                   bundle=result['bundle'], cleanup=cleanup)
            (project / 'fan' / '.maintenance' / 'pending.json').unlink(missing_ok=True)
            return
        if mode == 'export':
            status('complete', 'Verified export complete. Current storage is unchanged.', bundle=result['bundle'])
            return
        if cancel_file.exists():
            raise storage.Cancelled('Offload cancelled before cutover; originals retained')
        # Hold all source DB/sidecar handles from the final unchanged-source
        # check through route commit and cleanup. A late reader/writer cannot
        # reopen the old stores while the normal startup route is changing.
        with storage.hold_originals(manifest) if scope == 'databases' else nullcontext():
            status('committing', 'Committing verified storage routes; originals remain available until cleanup.')
            if scope == 'snapshots':
                snapshot_journal = storage.commit_snapshots(manifest)
                config['snapshots'] = {'source': str(snapshot_root), 'target': result['snapshots']['target']}
            else:
                config['databases'] = {**config.get('databases', {}), **result['targets']}
            config['last_offload'] = {'manifest': str(manifest), 'job': str(job_dir), 'scope': scope}
            # Validate the same targets that normal startup will open before
            # freeing originals; schema, quick_check and hashes already passed.
            for target in result.get('targets', {}).values():
                with closing(sqlite3.connect(Path(target).as_uri() + '?mode=ro', uri=True)) as db:
                    db.execute('SELECT name FROM sqlite_master LIMIT 1').fetchone()
            save_config(project, config)
            configured = True
            status('cleanup', 'Routes committed. Releasing only verified, unchanged original data…')
            if scope == 'databases':
                cleanup = storage.cleanup_offloaded_databases(manifest, result['targets'], progress=progress)
            else:
                cleanup = storage.cleanup_offloaded_snapshots(manifest, snapshot_journal, progress=progress)
        status('complete', 'Offload complete. Fan can reopen using the selected drive.',
               bundle=result['bundle'], cleanup=cleanup)
        (project / 'fan' / '.maintenance' / 'pending.json').unlink(missing_ok=True)
    except storage.Cancelled as exc:
        if snapshot_journal and not configured:
            storage.rollback_snapshots(manifest, snapshot_journal)
        status('cancelled', str(exc) + '. Original storage retained.')
        (project / 'fan' / '.maintenance' / 'pending.json').unlink(missing_ok=True)
    except Exception as exc:
        if snapshot_journal and not configured:
            try:
                storage.rollback_snapshots(manifest, snapshot_journal)
            except Exception as rollback_error:
                exc = RuntimeError(f'{exc}; snapshot rollback requires recovery: {rollback_error}')
        (job_dir / 'error.log').write_text(traceback.format_exc(), encoding='utf-8')
        if (job_dir / 'reset-intent.json').exists():
            status('error', 'Archive retained. Database reset must finish in startup recovery: ' + str(exc),
                   manifest=str(manifest))
        elif configured:
            status('complete', 'Storage cutover succeeded; some original cleanup needs review in job history: ' + str(exc),
                   warning=True, manifest=str(manifest))
        else:
            status('error', str(exc) + '. No database route change was committed; originals retained.')
        raise


def recover(request_path: Path):
    """Recover a crash between renaming snapshots and committing their route.

    Cleanup after an already committed route is resumable. Uncommitted snapshot
    cutovers roll back before the app is allowed to capture again.
    """
    request = json.loads(request_path.read_text(encoding='utf-8-sig'))
    job_dir, project = request_path.parent, Path(request['project'])
    result_path = job_dir / 'result.json'
    config = load_config(project)
    if (job_dir / 'reset-intent.json').exists():
        intent = json.loads((job_dir / 'reset-intent.json').read_text(encoding='utf-8'))
        manifest = intent['manifest']
        journal_path = Path(manifest).parent / 'database-reset.json'
        complete = journal_path.exists() and storage._read_json(journal_path).get('status') == 'complete'
        if not complete:
            with storage.hold_originals(manifest):
                archive.reset_databases(manifest)
        config['last_archive'] = {'manifest': str(manifest), 'job': str(job_dir), 'mode': request['mode']}
        config['snapshot_embed_base64'] = True
        save_config(project, config)
        atomic_json(job_dir / 'status.json', {'phase': 'complete', 'message': 'Archive/reset recovery complete.'})
        pending = project / 'fan' / '.maintenance' / 'pending.json'
        if pending.exists() and Path(json.loads(pending.read_text(encoding='utf-8'))['request']).absolute() == request_path.absolute():
            pending.unlink()
        return
    if result_path.exists():
        result = json.loads(result_path.read_text(encoding='utf-8-sig'))
        manifest = result['manifest']
        committed = config.get('last_offload', {}).get('manifest') == str(manifest)
        if committed:
            try:
                if request['scope'] == 'snapshots':
                    storage.cleanup_offloaded_snapshots(manifest)
                else:
                    with storage.hold_originals(manifest):
                        storage.cleanup_offloaded_databases(manifest, config.get('databases', {}))
            except Exception as exc:
                # Verified destinations remain authoritative; retaining originals
                # is safe, and must not prevent startup using the committed route.
                atomic_json(job_dir / 'recovery.json', {'warning': str(exc), 'originals_retained': True})
        elif request['scope'] == 'snapshots':
            storage.rollback_snapshots(manifest)
    pending = project / 'fan' / '.maintenance' / 'pending.json'
    if pending.exists():
        owner = json.loads(pending.read_text(encoding='utf-8-sig'))
        if Path(owner['request']).absolute() == request_path.absolute():
            pending.unlink()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--recover', action='store_true')
    parser.add_argument('request', type=Path)
    args = parser.parse_args()
    if args.recover:
        recover(args.request)
    else:
        run(args.request)


if __name__ == '__main__':
    main()
