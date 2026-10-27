"""Operator-paced narration gates; no recording or speech side effects."""
import sqlite3
import time
from .chains import CURRENT


def schema(db):
    db.execute('CREATE TABLE IF NOT EXISTS daa_tour_cue(id TEXT PRIMARY KEY,task_id TEXT,text TEXT,status TEXT)')


def latest(database, task_id):
    with sqlite3.connect(database, timeout=10) as db:
        db.row_factory = sqlite3.Row
        schema(db)
        row = db.execute("SELECT * FROM daa_tour_cue WHERE task_id=? ORDER BY rowid DESC LIMIT 1", (task_id,)).fetchone()
    return dict(row) if row else {}


def release(database, task_id):
    with sqlite3.connect(database, timeout=10) as db:
        schema(db)
        db.execute("UPDATE daa_tour_cue SET status='continue' WHERE task_id=? AND status='waiting'", (task_id,))
    return {'ok': True}


def cue(database, task_id, text, emit, seconds=4, wait_for_continue=False, timeout_seconds=300):
    step = CURRENT.get()
    identity = step['id'] if step else str(time.time_ns())
    with sqlite3.connect(database, timeout=10) as db:
        schema(db)
        db.execute('INSERT INTO daa_tour_cue VALUES(?,?,?,?)', (identity, task_id, text, 'waiting' if wait_for_continue else 'displaying'))
    emit('tour_cue', {'id': identity, 'text': text, 'wait_for_continue': wait_for_continue})
    start = time.monotonic()
    try:
        while True:
            with sqlite3.connect(database, timeout=10) as db:
                state = db.execute('SELECT status FROM tasks WHERE id=?', (task_id,)).fetchone()
                row = db.execute('SELECT status FROM daa_tour_cue WHERE id=?', (identity,)).fetchone()
            if state and state[0] == 'cancelled':
                return {'ok': False, 'error': 'Tour cancelled'}
            elapsed = time.monotonic() - start
            if row[0] == 'continue' or not wait_for_continue and elapsed >= seconds:
                return {'ok': True, 'cue': text, 'verified': True, 'note': 'Pause/gate completed; narration itself was not recorded or verified.'}
            if elapsed >= timeout_seconds:
                return {'ok': False, 'error': 'Operator cue timed out; no next action executed'}
            time.sleep(.2)
    finally:
        with sqlite3.connect(database, timeout=10) as db:
            db.execute("UPDATE daa_tour_cue SET status='finished' WHERE id=?", (identity,))
