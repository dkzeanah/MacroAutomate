"""Durable numbered execution trees. Counts describe attempts, never proof."""
from __future__ import annotations

from contextlib import contextmanager
from contextvars import ContextVar
from datetime import datetime, timezone
import json
import sqlite3
import uuid
import time

CURRENT = ContextVar('daa_step', default=None)
DEFAULT_LIMIT = 512
READ_ONLY = {'daa_chain_status', 'daa_explorer_usage', 'daa_unit_list'}


def schema(db):
    db.executescript('''CREATE TABLE IF NOT EXISTS daa_chain(
      task_id TEXT PRIMARY KEY,created_at TEXT,max_steps INTEGER NOT NULL,
      step_count INTEGER NOT NULL DEFAULT 0,status TEXT NOT NULL DEFAULT 'active');
    CREATE TABLE IF NOT EXISTS daa_step(
      id TEXT PRIMARY KEY,task_id TEXT,number INTEGER,parent_id TEXT,branch TEXT,
      origin TEXT,tool TEXT,arguments TEXT,started_at TEXT,finished_at TEXT DEFAULT '',
      status TEXT DEFAULT 'running',result TEXT DEFAULT '{}',run_id TEXT DEFAULT '',
      UNIQUE(task_id,number));
    CREATE INDEX IF NOT EXISTS ix_daa_step_task ON daa_step(task_id,number);
    CREATE TABLE IF NOT EXISTS daa_control(task_id TEXT PRIMARY KEY,paused INTEGER NOT NULL DEFAULT 0,updated_at TEXT);''')


def control(database, task_id, paused=None):
    with sqlite3.connect(database, timeout=10) as db:
        schema(db)
        row = db.execute('SELECT status FROM tasks WHERE id=?', (task_id,)).fetchone()
        if not row:
            raise ValueError('Select a recorded task')
        if paused is not None:
            if row[0] not in ('running', 'pending', 'queued'):
                raise ValueError('This task has already stopped')
            db.execute('INSERT INTO daa_control VALUES(?,?,?) ON CONFLICT(task_id) DO UPDATE SET paused=excluded.paused,updated_at=excluded.updated_at',
                       (task_id, int(bool(paused)), utc()))
        state = db.execute('SELECT paused FROM daa_control WHERE task_id=?', (task_id,)).fetchone()
    return {'paused': bool(state and state[0] and row[0] in ('running','pending','queued')), 'task_status': row[0]}


def wait_ready(database, task_id, deadline=None):
    """Cooperative boundary; cancellation remains effective while paused."""
    if not task_id:
        return
    while True:
        state = control(database, task_id)
        if state['task_status'] == 'cancelled':
            raise ValueError('Task cancelled while waiting')
        if not state['paused']:
            return
        if deadline is not None and time.monotonic() >= deadline:
            raise ValueError('Time budget reached while paused; no next action executed')
        time.sleep(.2)


def utc():
    return datetime.now(timezone.utc).isoformat()


def compact(value, limit=5000):
    """Do not copy images, clipboard/source or credentials into the graph."""
    if isinstance(value, dict):
        if 'frame_id' in value and 'hwnd' in value:
            value = {k: value[k] for k in ('frame_id','hwnd','title','exe','region','foreground','geometry_stable','content_stable') if k in value}
        value = {k: ('[retained separately]' if any(s in k.lower() for s in
                  ('base64', 'token', 'password', 'secret', 'clipboard', 'source', 'image_b64')) else compact(v, 1200))
                 for k, v in value.items() if k not in ('controls', 'accessibility', 'ocr', 'legend', 'probe')}
    elif isinstance(value, list):
        value = [compact(v, 300) for v in value[:12]]
    elif isinstance(value, str) and len(value) > limit:
        value = value[:limit] + '… [full evidence in event ledger]'
    return value


def begin(database, task_id, tool, args, origin='deepseek', parent='', branch=''):
    if not task_id or tool in READ_ONLY:
        return None
    active = CURRENT.get()
    if active and active['task_id'] == task_id:
        parent, origin = active['id'], 'tool:' + active['tool']
        branch = branch or active.get('branch', '')
    with sqlite3.connect(database, timeout=10) as db:
        schema(db)
        db.execute('BEGIN IMMEDIATE')
        db.execute('INSERT OR IGNORE INTO daa_chain(task_id,created_at,max_steps) VALUES(?,?,?)',
                   (task_id, utc(), DEFAULT_LIMIT))
        row = db.execute('SELECT step_count,max_steps FROM daa_chain WHERE task_id=?', (task_id,)).fetchone()
        if row[0] >= row[1]:
            db.execute("UPDATE daa_chain SET status='limit_reached' WHERE task_id=?", (task_id,))
            db.commit()
            raise ValueError(f'Chain limit {row[1]} reached; no further tool was executed. Change the budget locally to continue.')
        if parent and not db.execute('SELECT 1 FROM daa_step WHERE id=? AND task_id=?', (parent, task_id)).fetchone():
            raise ValueError('Chain parent does not belong to this task')
        number, identity = row[0] + 1, uuid.uuid4().hex
        db.execute('UPDATE daa_chain SET step_count=?,status=? WHERE task_id=?', (number, 'active', task_id))
        db.execute('INSERT INTO daa_step(id,task_id,number,parent_id,branch,origin,tool,arguments,started_at) VALUES(?,?,?,?,?,?,?,?,?)',
                   (identity, task_id, number, parent, branch, origin[:200], tool,
                    json.dumps(compact(args), ensure_ascii=False), utc()))
    return {'id': identity, 'task_id': task_id, 'number': number, 'tool': tool, 'branch': branch}


def finish(database, step, result):
    if not step:
        return
    success = result.get('ok') is True or result.get('ok') == 1
    status = 'failed' if not success else 'running' if result.get('status') == 'running' else 'executed'
    if success and result.get('status') == 'requested':
        status = 'requested'
    if success and (result.get('verified') is True or result.get('syntax_valid') is True):
        status = 'verified'
    with sqlite3.connect(database, timeout=10) as db:
        db.execute('UPDATE daa_step SET finished_at=?,status=?,result=?,run_id=? WHERE id=?',
                   (utc(), status, json.dumps(compact(result), ensure_ascii=False), result.get('run_id', ''), step['id']))


@contextmanager
def scope(step):
    token = CURRENT.set(step)
    try:
        yield
    finally:
        CURRENT.reset(token)


def snapshot(database, task_id, after=0, limit=200):
    with sqlite3.connect(database, timeout=10) as db:
        db.row_factory = sqlite3.Row
        schema(db)
        chain = db.execute('SELECT * FROM daa_chain WHERE task_id=?', (task_id,)).fetchone()
        rows = db.execute('SELECT * FROM daa_step WHERE task_id=? AND number>? ORDER BY number LIMIT ?',
                          (task_id, max(0, after), min(500, max(1, limit)))).fetchall()
    steps = []
    for row in rows:
        item = dict(row)
        item['arguments'], item['result'] = json.loads(item['arguments']), json.loads(item['result'])
        item['target_window'] = json.loads(item.get('target_window','{}'))
        steps.append(item)
    return {'ok': True, 'chain': dict(chain) if chain else {}, 'steps': steps,
            'cursor': steps[-1]['number'] if steps else after, 'has_more': len(steps) == min(500, max(1, limit)),
            'note': 'Numbers count attempted gateway interactions, including nested tools. Executed is not semantic verification; branch return is an explicit recorded action.'}


def configure(database, task_id, max_steps):
    if not 1 <= max_steps <= 10000:
        raise ValueError('Choose a chain budget from 1 to 10000')
    with sqlite3.connect(database, timeout=10) as db:
        schema(db)
        db.execute('UPDATE daa_chain SET max_steps=?,status=CASE WHEN step_count<? THEN ? ELSE ? END WHERE task_id=?',
                   (max_steps, max_steps, 'active', 'limit_reached', task_id))
    return snapshot(database, task_id)
