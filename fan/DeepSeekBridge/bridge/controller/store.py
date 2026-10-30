"""Durable runs, observable events, and command approvals. No credentials stored."""
from __future__ import annotations
import json
import os
import sqlite3
import time
import uuid
from contextlib import contextmanager
from pathlib import Path

DATA = Path(os.environ.get('ATLAS_CONTROLLER_DATA', Path(__file__).resolve().parents[2]/'.runtime'/'controller'))


@contextmanager
def db():
    DATA.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(DATA/'controller.sqlite3', timeout=20)
    connection.row_factory = sqlite3.Row
    connection.execute('PRAGMA journal_mode=WAL')
    connection.executescript('''
      CREATE TABLE IF NOT EXISTS runs (
        id TEXT PRIMARY KEY, batch TEXT, provider TEXT, mode TEXT, status TEXT,
        prompt TEXT, model TEXT, root TEXT, baseline TEXT, settings TEXT,
        created REAL, finished REAL, usage TEXT, result TEXT, error TEXT);
      CREATE TABLE IF NOT EXISTS events (
        id INTEGER PRIMARY KEY, run_id TEXT, at REAL, kind TEXT, payload TEXT);
      CREATE INDEX IF NOT EXISTS event_run ON events(run_id,id);
      CREATE TABLE IF NOT EXISTS approvals (
        id TEXT PRIMARY KEY,run_id TEXT,command TEXT,status TEXT,created REAL);
      CREATE TABLE IF NOT EXISTS reviews (
        run_id TEXT PRIMARY KEY,correctness INTEGER,grounding INTEGER,validation INTEGER,notes TEXT);
    ''')
    try:
        yield connection
        connection.commit()
    finally:
        connection.close()


def clean(value):
    text = json.dumps(value, ensure_ascii=False, default=str)
    for name in ('DEEPSEEK_API_KEY','ANTHROPIC_API_KEY','OPENAI_API_KEY'):
        secret = os.environ.get(name, '')
        if len(secret) > 8:
            text = text.replace(secret, '[credential redacted]')
    return text


def event(identity: str, kind: str, payload) -> None:
    with db() as conn:
        conn.execute('INSERT INTO events(run_id,at,kind,payload) VALUES(?,?,?,?)',
                     (identity, time.time(), kind, clean(payload)))


def create(batch: str, provider: str, mode: str, prompt: str, model: str, settings: dict) -> str:
    identity = uuid.uuid4().hex[:12]
    with db() as conn:
        conn.execute('INSERT INTO runs VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
                     (identity,batch,provider,mode,'queued',prompt,model,'','',json.dumps(settings),
                      time.time(),None,None,'',''))
    event(identity,'queued',{'provider':provider,'mode':mode})
    return identity


def update(identity: str, **fields) -> None:
    allowed = {'status','root','baseline','finished','usage','result','error'}
    if not fields or not set(fields) <= allowed:
        raise ValueError('Invalid run update')
    values = [json.dumps(v) if isinstance(v,(dict,list)) else v for v in fields.values()]
    with db() as conn:
        conn.execute('UPDATE runs SET '+','.join(f'{k}=?' for k in fields)+' WHERE id=?', [*values,identity])


def transition(identity: str, previous: tuple[str,...], status: str, **fields) -> bool:
    """Cancellation wins races with preparation, agent completion and failure."""
    allowed={'finished','usage','result','error'}
    if not set(fields)<=allowed:
        raise ValueError('Invalid transition fields')
    changes={'status':status,**fields}
    values=[json.dumps(v) if isinstance(v,(dict,list)) else v for v in changes.values()]
    with db() as conn:
        cursor=conn.execute('UPDATE runs SET '+','.join(f'{k}=?' for k in changes)+
              ' WHERE id=? AND status IN ('+','.join('?' for _ in previous)+')',[*values,identity,*previous])
        return cursor.rowcount==1


def decode(row):
    value = dict(row)
    for key in ('usage','settings'):
        value[key] = json.loads(value[key]) if value.get(key) else None
    return value


def get(identity: str) -> dict:
    with db() as conn:
        row = conn.execute('SELECT * FROM runs WHERE id=?',(identity,)).fetchone()
    if row is None:
        raise KeyError(identity)
    return decode(row)


def runs() -> list[dict]:
    with db() as conn:
        return [decode(row) for row in conn.execute('SELECT * FROM runs ORDER BY created DESC LIMIT 200')]


def events(identity: str, after: int = 0) -> list[dict]:
    with db() as conn:
        return [{**dict(row),'payload':json.loads(row['payload'])} for row in conn.execute(
            'SELECT * FROM events WHERE run_id=? AND id>? ORDER BY id LIMIT 300',(identity,after))]
