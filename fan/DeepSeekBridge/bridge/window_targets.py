"""Local task/step window identities; never substitute the current foreground."""
import json
import sqlite3
from .chains import utc


def schema(db):
    db.execute('CREATE TABLE IF NOT EXISTS daa_window(task_id TEXT,hwnd INTEGER,identity TEXT,updated_at TEXT,PRIMARY KEY(task_id,hwnd))')


def bind(database, task_id, identity, step_id=''):
    if not task_id or not identity.get('hwnd') or not identity.get('pid'):
        return
    clean={k:identity[k] for k in ('hwnd','pid','exe','title','class','window_rect') if k in identity}
    with sqlite3.connect(database,timeout=10) as db:
        schema(db)
        db.execute('BEGIN IMMEDIATE')
        db.execute('INSERT INTO daa_window VALUES(?,?,?,?) ON CONFLICT(task_id,hwnd) DO UPDATE SET identity=excluded.identity,updated_at=excluded.updated_at',
                   (task_id,clean['hwnd'],json.dumps(clean,ensure_ascii=False),utc()))
        if step_id:
            columns={r[1] for r in db.execute('PRAGMA table_info(daa_step)')}
            if 'target_window' not in columns:
                db.execute("ALTER TABLE daa_step ADD COLUMN target_window TEXT NOT NULL DEFAULT '{}'")
            db.execute('UPDATE daa_step SET target_window=? WHERE id=? AND task_id=?',(json.dumps(clean,ensure_ascii=False),step_id,task_id))


def lookup(database,task_id,hwnd=0):
    if not isinstance(hwnd,int) or hwnd<0:return {}
    with sqlite3.connect(database,timeout=10) as db:
        schema(db)
        row=db.execute('SELECT identity FROM daa_window WHERE task_id=?'+(' AND hwnd=?' if hwnd else '')+' ORDER BY updated_at DESC LIMIT 1',
                       (task_id,hwnd) if hwnd else (task_id,)).fetchone()
    return json.loads(row[0]) if row else {}
