"""Passive local reading, reusing Fan's native probe and retained page atlas."""
from __future__ import annotations

import ctypes
import hashlib
import json
import re
import sqlite3
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qsl, urlsplit


def foreground_matches(hwnd, pid, context_id=""):
    if not hasattr(ctypes, 'windll'):
        return False
    user = ctypes.windll.user32
    user.GetForegroundWindow.restype = ctypes.c_void_p
    actual_pid = ctypes.c_ulong()
    user.GetWindowThreadProcessId(ctypes.c_void_p(hwnd), ctypes.byref(actual_pid))
    if user.GetForegroundWindow() != hwnd or actual_pid.value != pid:
        return False
    if context_id:
        user.GetPropW.restype = ctypes.c_void_p
        token = user.GetPropW(ctypes.c_void_p(hwnd), ctypes.c_wchar_p('Fan.ChromeLearning.WindowSession.v1'))
        return context_id == f'chrome-{pid}-{hwnd}-{token}'
    return True


def readable(probe):
    """Keep visible document evidence; typed fields and browser chrome aren't lessons."""
    url = probe.get('url', '')
    parts = urlsplit(url if '://' in url else 'https://' + url)
    title = probe.get('frame', {}).get('title', '')
    if parts.scheme not in ('http', 'https') or not parts.hostname:
        return [], 'Not a web document'
    if re.search(r'(?i)incognito|inprivate|password|sign.?in|log.?in|checkout|payment', title):
        return [], 'Account or input page'
    if re.search(r'(?i)(^|\.)(mail|outlook|accounts|banking)\.|/(login|signin|checkout|payments|messages)(/|$)', parts.netloc + parts.path):
        return [], 'Account or private-message page'
    if any(re.search(r'(?i)token|password|secret|authorization|session', k) for k, _ in parse_qsl(parts.query)):
        return [], 'Credential-bearing address'
    controls = probe.get('controls', [])
    docs = [c for c in controls if 'document' in c.get('role', '').lower() and c.get('accessibility_path')]
    if not docs:
        return [], 'No accessible document yet'
    document = max(docs, key=lambda c: c['bounds']['w'] * c['bounds']['h'])
    prefix = document['accessibility_path'] + '.'
    result, seen = [], set()
    for control in controls:
        path, role = control.get('accessibility_path', ''), control.get('role', '').lower()
        if not (path == document['accessibility_path'] or path.startswith(prefix)):
            continue
        if control.get('protected') or re.search(r'edit|text field|combo|password', role):
            continue
        text = re.sub(r'\s+', ' ', control.get('name', '')).strip()
        if not text or len(text) < 3:
            continue
        if re.search(r'(?i)^(accept (all )?cookies|reject (all )?cookies|close|menu|sign in|log in)$', text):
            continue
        key = (role, text, control.get('href', ''))
        if key in seen:
            continue
        seen.add(key)
        clean = {**control, 'name': text, 'value': '', 'description': ''}
        if path == document['accessibility_path']:
            clean['value'] = url
        result.append(clean)
    meaningful = [c for c in result if not re.search(r'document|pane|group|toolbar|button', c['role'], re.I)]
    if sum(len(c['name']) for c in meaningful) < 80:
        return [], 'Waiting for readable page content'
    return result, 'Visible page text and reference links'


def initialize(db):
    db.execute('CREATE TABLE IF NOT EXISTS chrome_learning_seen ('
               'context_id TEXT, fingerprint TEXT, page_id TEXT, items_json TEXT, '
               'last_seen TEXT, PRIMARY KEY(context_id,fingerprint))')
    db.execute('CREATE TABLE IF NOT EXISTS chrome_learning_capture ('
               'page_id TEXT PRIMARY KEY, context_id TEXT, profile_label TEXT, captured_ts TEXT, title TEXT, url TEXT)')
    columns = {row[1] for row in db.execute('PRAGMA table_info(chrome_learning_capture)')}
    for name, kind in [('profile_id', 'TEXT'), ('profile_path', 'TEXT'), ('app_user_model_id', 'TEXT'),
                       ('capture_kind', 'TEXT'), ('summary', 'TEXT'), ('item_count', 'INTEGER DEFAULT 0'),
                       ('reviewed', 'INTEGER DEFAULT 0')]:
        if name not in columns:
            db.execute(f'ALTER TABLE chrome_learning_capture ADD COLUMN {name} {kind}')


def native_probe(args, cancelled=lambda: False):
    """The existing AHK reader runs outside the GUI and doesn't fill gateway logs."""
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='FanBrowserRead-') as directory:
        directory = Path(directory)
        output = directory / 'probe.json'
        request = directory / 'request.json'
        request.write_text(json.dumps({'hwnd': args['hwnd'], 'db_path': args['db_path'], 'output': str(output)}), encoding='utf-8')
        command = [args['ahk_path'], '/ErrorStdOut=UTF-8', str(root / 'BrowserObservationWorker.ahk'), str(request)]
        with (directory / 'worker.log').open('w', encoding='utf-8') as log:
            child = subprocess.Popen(command, stdout=log, stderr=log,
                                     creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            deadline = time.monotonic() + 40
            try:
                while child.poll() is None:
                    if cancelled():
                        raise InterruptedError('Automatic reading cancelled')
                    if time.monotonic() > deadline:
                        raise TimeoutError('Native Chrome reader exceeded its time limit: ' + (directory / 'worker.log').read_text(encoding='utf-8', errors='replace')[-500:])
                    time.sleep(.1)
            finally:
                if child.poll() is None:
                    child.terminate()
                    child.wait(timeout=10)
        if not output.is_file():
            raise RuntimeError((directory / 'worker.log').read_text(encoding='utf-8', errors='replace')[-1000:] or 'Native reader returned no result')
        return json.loads(output.read_text(encoding='utf-8-sig'))


def observe(args, *, call=None, foreground=foreground_matches, cancelled=lambda: False):
    from bridge import page_learner
    hwnd, pid = int(args['hwnd']), int(args['pid'])
    context_id = args['context_id']
    if not foreground(hwnd, pid, context_id):
        return {'ok': True, 'captured': False, 'reason': 'Chrome focus changed'}
    probe = call('fan_page_probe', {'hwnd': hwnd}, timeout=40) if call else native_probe(args, cancelled)
    if not probe.get('ok'):
        raise ValueError(probe.get('error', 'Chrome observation failed'))
    if probe.get('frame', {}).get('hwnd') != hwnd or not foreground(hwnd, pid, context_id):
        return {'ok': True, 'captured': False, 'reason': 'Chrome focus changed during reading'}
    if cancelled():
        raise InterruptedError('Automatic reading cancelled')
    controls, reason = readable(probe)
    if not controls:
        return {'ok': True, 'captured': False, 'reason': reason}
    items = sorted({c['name'] for c in controls if 'document' not in c['role'].lower()})
    identity = json.dumps([args.get('profile_id', ''), page_learner.canonical_url(probe['url']),
                           sorted((c['role'], c['name'], c.get('href', '')) for c in controls)], ensure_ascii=False)
    fingerprint = hashlib.sha256(identity.encode()).hexdigest()
    stamp = datetime.now(timezone.utc).isoformat(timespec='seconds')
    # Explicit metadata DB is supplied by the native app's existing TrackDB.
    with sqlite3.connect(args['db_path'], timeout=10) as db:
        initialize(db)
        prior = db.execute('SELECT page_id FROM chrome_learning_seen WHERE context_id=? AND fingerprint=?',
                           (context_id, fingerprint)).fetchone()
        if prior:
            db.execute('UPDATE chrome_learning_seen SET last_seen=? WHERE context_id=? AND fingerprint=?',
                       (stamp, context_id, fingerprint))
            return {'ok': True, 'captured': False, 'reason': 'Already learned this visible content', 'page_id': prior[0]}
        previous = db.execute('SELECT items_json FROM chrome_learning_seen WHERE context_id=? ORDER BY last_seen DESC LIMIT 1',
                              (context_id,)).fetchone()
    old = set(json.loads(previous[0])) if previous else set()
    new_items = [item for item in items if item not in old]
    # Reuse the established page builder/get/search APIs, without screenshots,
    # OCR, FindText extraction, LLM calls, or browser input for passive reading.
    page = page_learner.build({**probe, 'controls': controls, 'assets': {}, 'visual_tiles': [], 'ocr': {'lines': []}})
    summary = f'{len(new_items)} new readable items; {len(items)} visible items. ' + reason + '.\n'
    summary += '\n'.join(new_items[:8] or items[:8])[:2400]
    page_id = page['page_id']
    with sqlite3.connect(args['db_path'], timeout=10) as db:
        initialize(db)
        db.execute('INSERT INTO chrome_learning_capture '
                   '(page_id,context_id,profile_label,captured_ts,title,url,profile_id,profile_path,app_user_model_id,capture_kind,summary,item_count,reviewed) '
                   'VALUES(?,?,?,?,?,?,?,?,?,?,?,?,0)',
                   (page_id, context_id, args.get('profile_label', ''), stamp, page['title'], page['url'],
                    args.get('profile_id', ''), args.get('profile_path', ''), args.get('app_user_model_id', ''),
                    'auto_text', summary, len(new_items)))
        db.execute('INSERT OR REPLACE INTO chrome_learning_seen VALUES(?,?,?,?,?)',
                   (context_id, fingerprint, page_id, json.dumps(items, ensure_ascii=False), stamp))
    return {'ok': True, 'captured': True, 'page_id': page_id, 'summary': summary, 'item_count': len(new_items)}
