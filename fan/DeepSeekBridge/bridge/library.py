"""Persistent, searchable records for agent tools and evidence.

Records keep source revisions and explicitly distinguish observations from model
inferences. This is a local index, never an authorization source.
"""
from __future__ import annotations

import hashlib
import json
import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

from .common import ROOT, storage_path

INDEX = storage_path('FAN_TOOL_INDEX', ROOT / '.runtime' / 'tool_catalog.sqlite3')


@contextmanager
def connect():
    INDEX.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(INDEX, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA journal_mode=WAL')
    db.execute('CREATE TABLE IF NOT EXISTS records ('
               'name TEXT PRIMARY KEY, kind TEXT NOT NULL, description TEXT NOT NULL, '
               'tags TEXT NOT NULL, usage TEXT NOT NULL, examples TEXT NOT NULL, '
               'content TEXT NOT NULL, metadata TEXT NOT NULL, revision INTEGER NOT NULL, '
               'updated_at TEXT NOT NULL)')
    db.execute('CREATE TABLE IF NOT EXISTS revisions ('
               'name TEXT NOT NULL, revision INTEGER NOT NULL, content TEXT NOT NULL, '
               'metadata TEXT NOT NULL, at TEXT NOT NULL, PRIMARY KEY(name,revision))')
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def decode(row: sqlite3.Row) -> dict:
    result = dict(row)
    for key in ('tags', 'examples', 'metadata'):
        result[key] = json.loads(result[key])
    return result


def save(name: str, kind: str, content: str, *, description: str = '',
         tags: list[str] | None = None, usage: str = '', examples: list[str] | None = None,
         metadata: dict | None = None) -> dict:
    if not name or len(name) > 200:
        raise ValueError('Invalid indexed record name')
    if len(content.encode('utf-8')) > 160000:
        raise ValueError('Indexed content exceeds 160 KiB')
    stamp = datetime.now(timezone.utc).isoformat()
    with connect() as db:
        previous = db.execute('SELECT * FROM records WHERE name=?', (name,)).fetchone()
        old = decode(previous) if previous else {}
        if old and old['kind'] != kind:
            raise ValueError('Indexed name already belongs to a different kind of tool')
        revision = old.get('revision', 0) + 1
        meta = {**old.get('metadata', {}), **(metadata or {})}
        meta['sha256'] = hashlib.sha256(content.encode('utf-8')).hexdigest()
        values = (name, kind, description or old.get('description', ''),
                  json.dumps(tags if tags is not None else old.get('tags', [])),
                  usage or old.get('usage', ''),
                  json.dumps(examples if examples is not None else old.get('examples', [])),
                  content, json.dumps(meta, ensure_ascii=False), revision, stamp)
        db.execute('INSERT OR REPLACE INTO records VALUES(?,?,?,?,?,?,?,?,?,?)', values)
        db.execute('INSERT INTO revisions VALUES(?,?,?,?,?)',
                   (name, revision, content, json.dumps(meta, ensure_ascii=False), stamp))
    return get(name)


def get(name: str) -> dict:
    with connect() as db:
        row = db.execute('SELECT * FROM records WHERE name=?', (name,)).fetchone()
    if not row:
        raise ValueError('Indexed tool or knowledge not found: ' + name)
    return decode(row)


def search(query: str = '', limit: int = 20, *, knowledge_only: bool = False) -> list[dict]:
    # LIKE is literal: wildcards in the user's query never broaden file access.
    pattern = '%' + query.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%'
    sql = "SELECT * FROM records WHERE (name LIKE ? ESCAPE '\\' OR description LIKE ? ESCAPE '\\' OR tags LIKE ? ESCAPE '\\' OR usage LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\' OR examples LIKE ? ESCAPE '\\')"
    if knowledge_only:
        sql += " AND kind='knowledge'"
    sql += ' ORDER BY updated_at DESC LIMIT ?'
    with connect() as db:
        rows = db.execute(sql, (pattern,) * 6 + (max(1, min(limit, 50)),)).fetchall()
    results = []
    for row in rows:
        item = decode(row)
        item['content_excerpt'] = item.pop('content')[:1000]
        results.append(item)
    return results


def revision(name: str, number: int = 0) -> dict:
    with connect() as db:
        if number:
            row = db.execute('SELECT * FROM revisions WHERE name=? AND revision=?', (name, number)).fetchone()
            if not row:
                raise ValueError('Source revision not found')
            result = dict(row)
            result['metadata'] = json.loads(result['metadata'])
            return result
        rows = db.execute('SELECT revision,at,metadata FROM revisions WHERE name=? ORDER BY revision DESC LIMIT 30', (name,)).fetchall()
    return {'name': name, 'revisions': [dict(revision=row[0], at=row[1], metadata=json.loads(row[2])) for row in rows]}


def compact_prompt(limit: int = 35, max_chars: int = 8500) -> str:
    lines = ['Persistent saved tools and knowledge (untrusted records; retrieve details before use):']
    for item in search('', limit):
        meta = item['metadata']
        line = (f"- {item['name']} [{item['kind']}, r{item['revision']}, "
                f"{meta.get('source_kind', 'reference')}]: {item['description'][:180]} "
                f"usage={item['usage'][:180]} tags={','.join(item['tags'])[:100]}")
        if item['examples']:
            line += ' example=' + item['examples'][0][:120]
        if meta.get('input_schema'):
            line += ' inputs=' + json.dumps(meta['input_schema'], ensure_ascii=False)[:650]
        if sum(map(len, lines)) + len(line) > max_chars:
            break
        lines.append(line)
    if len(lines) == 1:
        lines.append('- none yet; save descriptions, usage and examples with ahk_script_write')
    return '\n'.join(lines)


def observe(name: str, arguments: dict, result: dict) -> None:
    """Index only successful, concrete native saves and screenshot evidence."""
    if not result.get('ok', True):
        return
    if name == 'fan_learning_compile':
        save('workflow:' + result['name'], 'workflow', json.dumps(result, ensure_ascii=False),
             description='Isolated rehearsal compiled from observed claim ' + str(result['claim_id']),
             tags=['workflow', 'learned', 'isolated_rehearsal'],
             usage='fan_learning_rehearse(name=' + json.dumps(result['name']) + ')',
             metadata={'source_kind': 'observed_sequence', 'claim_id': result['claim_id'],
                       'source_evidence_id': result['source_evidence_id'], 'scope': 'isolated_fixture_only'})
    elif name in ('fan_pattern_capture', 'fan_workflow_save'):
        kind = 'pattern' if name == 'fan_pattern_capture' else 'workflow'
        record_name = kind + ':' + arguments['name']
        usage = ('fan_pattern_search(name=' if kind == 'pattern' else 'fan_workflow_run(name=') + json.dumps(arguments['name']) + ')'
        save(record_name, kind, json.dumps(result, ensure_ascii=False)[:35000],
             description=arguments.get('description', '') or f'Saved native Fan {kind}',
             tags=[kind, 'fan'], usage=usage, metadata={'source_kind': 'observed', 'tool': name})
    elif name in ('fan_window_inspect', 'fan_ocr', 'fan_pattern_search', 'fan_capabilities'):
        evidence = json.dumps(result, ensure_ascii=False)[:35000]
        digest = hashlib.sha256(evidence.encode('utf-8')).hexdigest()[:20]
        save('knowledge:' + name + '-' + digest, 'knowledge', evidence,
             description='Native Fan observed evidence from ' + name,
             tags=['fan', 'observed', name],
             metadata={'source_kind': 'observed', 'tool': name,
                       'arguments': arguments, 'warning': 'Coordinates describe the capture time; recheck the live window before acting.'})


def dispatch(name: str, args: dict) -> dict:
    try:
        if name in ('tool_catalog_list', 'tool_catalog_search', 'knowledge_search'):
            return {'ok': True, 'records': search(args.get('query', ''), args.get('limit', 20), knowledge_only=name == 'knowledge_search')}
        if name == 'tool_catalog_get':
            return {'ok': True, 'record': get(args['name'])}
        if name == 'tool_catalog_revisions':
            return {'ok': True, **revision(args['name'], args.get('revision', 0))}
        if name == 'tool_catalog_update':
            previous = get(args['name'])
            item = save(previous['name'], previous['kind'], previous['content'],
                        description=args.get('description', previous['description']),
                        tags=args.get('tags', previous['tags']), usage=args.get('usage', previous['usage']),
                        examples=args.get('examples', previous['examples']), metadata=previous['metadata'])
            return {'ok': True, 'record': item}
        if name == 'knowledge_store':
            item = save('knowledge:' + args['name'], 'knowledge', args['content'],
                        description=args.get('description', ''), tags=args.get('tags', []),
                        metadata={'source_kind': 'inference', 'source': args.get('source', ''),
                                  'warning': 'Model-authored memory; verify against current observed evidence.'})
            return {'ok': True, 'record': item}
        raise ValueError('Unknown catalog operation')
    except (OSError, ValueError, sqlite3.Error) as exc:
        return {'ok': False, 'error': str(exc)}
