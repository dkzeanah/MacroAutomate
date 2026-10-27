"""Incremental Desktop metadata index. Source stays in place; junctions aren't followed."""
from __future__ import annotations
import json
import os
import time
from pathlib import Path
from . import library
from .window_knowledge import now

EXCLUDED = {'.git', '.venv', 'venv', 'node_modules', '__pycache__', '.runtime', '.cache', 'dist', 'build'}
MARKERS = {'pyproject.toml', 'package.json', 'requirements.txt', 'cargo.toml', 'go.mod', 'cmakelists.txt', '.git'}


def desktop():
    if os.name == 'nt':
        import ctypes
        # SHGetFolderPath respects redirected/OneDrive Desktop configuration.
        buffer = ctypes.create_unicode_buffer(32768)
        if ctypes.windll.shell32.SHGetFolderPathW(None, 0x10, None, 0, buffer) == 0:
            return Path(buffer.value)
    return Path.home() / 'Desktop'


def schema(db):
    db.executescript('''CREATE TABLE IF NOT EXISTS project_path(
      path TEXT PRIMARY KEY,name TEXT,kind TEXT,parent TEXT,marker TEXT,last_seen TEXT);
    CREATE TABLE IF NOT EXISTS project_scan(
      id INTEGER PRIMARY KEY CHECK(id=1),root TEXT,queue TEXT,complete INTEGER,updated_at TEXT);
    CREATE INDEX IF NOT EXISTS ix_project_path_kind ON project_path(kind,name);''')


def advance(root=None, limit=1000, budget=1.5):
    root = Path(root or desktop()).resolve()
    if not root.is_dir():
        return {'ok': False, 'error': 'Desktop directory is unavailable'}
    started, processed = time.monotonic(), 0
    with library.connect() as db:
        schema(db)
        old = db.execute('SELECT * FROM project_scan WHERE id=1').fetchone()
        queue = json.loads(old['queue']) if old and old['root'] == str(root) else [[str(root), '']]
        if old and old['root'] == str(root) and old['complete']:
            # Repeat the sweep daily so newly created/removed paths can be found.
            if old['updated_at'][:10] == now()[:10]:
                return {'ok': True, 'complete': True, 'processed': 0}
            queue = [[str(root), '']]
        stamp = now()
        while queue and processed < limit and time.monotonic() - started < budget:
            folder, after = queue.pop(0)
            path = Path(folder)
            if not path.is_relative_to(root) or path.is_symlink() or getattr(path, 'is_junction', lambda: False)():
                continue
            try:
                with os.scandir(path) as iterator:
                    entries = sorted(iterator, key=lambda item: item.name)
            except OSError:
                continue
            unfinished = False
            for entry in entries:
                if entry.name <= after:
                    continue
                if processed >= limit or (processed and time.monotonic() - started >= budget):
                    queue.insert(0, [folder, after])
                    unfinished = True
                    break
                after = entry.name
                processed += 1
                try:
                    target = Path(entry.path)
                    is_dir = entry.is_dir(follow_symlinks=False)
                    reparse = entry.is_symlink() or getattr(target, 'is_junction', lambda: False)()
                    kind = 'directory' if is_dir else 'file'
                    marker = entry.name if entry.name.lower() in MARKERS or target.suffix.lower() in ('.sln', '.ahk', '.code-workspace') else ''
                    db.execute('INSERT OR REPLACE INTO project_path VALUES(?,?,?,?,?,?)', (str(target), entry.name, kind, folder, marker, stamp))
                    if marker:
                        db.execute('INSERT OR REPLACE INTO project_path VALUES(?,?,?,?,?,?)', (folder, path.name, 'project', str(path.parent), marker, stamp))
                    if is_dir and not reparse and entry.name.lower() not in EXCLUDED:
                        queue.append([entry.path, ''])
                except OSError:
                    continue
            if unfinished:
                break
        db.execute('INSERT OR REPLACE INTO project_scan VALUES(1,?,?,?,?)', (str(root), json.dumps(queue), int(not queue), stamp))
    return {'ok': True, 'processed': processed, 'complete': not queue, 'pending_directories': len(queue),
            'scope': 'Desktop path/filename/project-marker metadata only. Source remains in place. Junctions, symlinks and dependency/cache trees are not traversed.'}


def search(query='', limit=30):
    with library.connect() as db:
        schema(db)
        rows = db.execute('SELECT * FROM project_path WHERE path LIKE ? ORDER BY kind="project" DESC,name LIMIT ?', ('%' + query + '%', max(1, min(100, limit)))).fetchall()
    return {'ok': True, 'paths': [dict(r) for r in rows], 'note': 'Metadata observed in place; verify path existence before opening. This is navigation knowledge, not a copy of source or executable instructions.'}


def stats():
    with library.connect() as db:
        schema(db)
        counts = {r[0]: r[1] for r in db.execute('SELECT kind,COUNT(*) FROM project_path GROUP BY kind')}
        row = db.execute('SELECT root,complete,updated_at FROM project_scan WHERE id=1').fetchone()
    return {'counts': counts, 'scan': dict(row) if row else {}, 'excluded_trees': sorted(EXCLUDED)}
