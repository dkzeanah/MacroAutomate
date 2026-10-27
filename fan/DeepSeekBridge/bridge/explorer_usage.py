"""Local-only Shell path observations and conservative foreground dwell ranking."""
from __future__ import annotations
from datetime import datetime, timezone
import json
import ntpath
from . import library


def schema(db):
    db.executescript('''CREATE TABLE IF NOT EXISTS explorer_usage(
      path TEXT PRIMARY KEY,kind TEXT,active_ms INTEGER DEFAULT 0,visits INTEGER DEFAULT 0,
      observations INTEGER DEFAULT 0,last_seen TEXT,first_seen TEXT);
    CREATE TABLE IF NOT EXISTS explorer_cursor(
      id INTEGER PRIMARY KEY CHECK(id=1),session TEXT,tick INTEGER,hwnd INTEGER,path TEXT);''')


def ingest(sample):
    stamp = datetime.now(timezone.utc).isoformat()
    session, tick = str(sample['session']), int(sample['tick'])
    hwnd, idle = int(sample.get('foreground', 0)), int(sample.get('idle_ms', 999999))
    windows = sample.get('windows', [])[:80]
    # Several ShellWindows entries can share a tabbed Explorer HWND. Do not
    # attribute attention to every tab when the actual active path is unknown.
    candidates = {w['path'] for w in windows if int(w.get('hwnd', 0)) == hwnd and w.get('path')}
    title_matches = set()
    for w in windows:
        if int(w.get('hwnd',0)) != hwnd or not w.get('path'):
            continue
        title, basename = w.get('title','').casefold(), ntpath.basename(w['path'].rstrip('\\/')).casefold()
        if basename and (title.startswith(basename + ' - ') or title.startswith(basename + ' and ')):
            title_matches.add(w['path'])
    if len(candidates)>1 and len(title_matches)==1:
        candidates = title_matches
    current = next(iter(candidates)) if len(candidates) == 1 and idle < 60000 else ''
    with library.connect() as db:
        schema(db)
        db.execute('BEGIN IMMEDIATE')
        old = db.execute('SELECT session,tick,hwnd,path FROM explorer_cursor WHERE id=1').fetchone()
        if old and old[0] == session and tick <= old[1]:
            return {'ok': True, 'duplicate': True}
        elapsed = min(3000, max(0, tick - old[1])) if old and old[0] == session else 0
        dwell = elapsed if old and old[3] == current and old[2] == hwnd and current else 0
        observed = {}
        for w in windows:
            if w.get('path'):
                observed[w['path']] = 'folder'
            for p in w.get('selected', [])[:20]:
                if p:
                    observed[p] = 'selected_file_or_folder'
        for path, kind in observed.items():
            if not isinstance(path, str) or len(path) > 2000:
                continue
            visit = int(path == current and (not old or old[3] != current or old[2] != hwnd))
            ms = dwell if path == current else 0
            db.execute('INSERT INTO explorer_usage VALUES(?,?,?,?,1,?,?) ON CONFLICT(path) DO UPDATE SET '
                       'active_ms=active_ms+excluded.active_ms,visits=visits+excluded.visits,observations=observations+1,last_seen=excluded.last_seen',
                       (path, kind, ms, visit, stamp, stamp))
        db.execute('INSERT OR REPLACE INTO explorer_cursor VALUES(1,?,?,?,?)',
                   (session, tick, hwnd, current))
    return {'ok': True, 'observed_paths': len(observed), 'attributed_active_ms': dwell,
            'ambiguous_tabs': len(candidates) > 1}


def advance(root):
    path = root / '.runtime/explorer-sample.json'
    if path.exists():
        sample = json.loads(path.read_text(encoding='utf-8-sig'))
        return ingest(sample)
    return {'ok': True, 'waiting_for_native_observer': True}


def ranked(query='', limit=30):
    with library.connect() as db:
        schema(db)
        rows = db.execute('SELECT * FROM explorer_usage WHERE instr(lower(path),lower(?))>0 '
                          'ORDER BY active_ms DESC,visits DESC,last_seen DESC LIMIT ?', (query, min(100, max(1, limit)))).fetchall()
    return {'ok': True, 'paths': [dict(r) for r in rows], 'local_only': True,
            'note': 'Foreground non-idle folder dwell is measured conservatively, not time spent editing each selected file. A unique Shell path matching the active frame title can disambiguate tabs; otherwise ambiguous tab HWNDs receive no dwell credit. Gaps are capped at 3 seconds. Full ranking stays local.'}
