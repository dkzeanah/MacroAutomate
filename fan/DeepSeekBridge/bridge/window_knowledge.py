"""Window-scoped empirical maps, refresh policy and auditable savings estimates."""
from __future__ import annotations
import hashlib
import json
import random
import re
from datetime import datetime, timezone
from . import library

WINDOWS_REFERENCE = 'https://support.microsoft.com/en-au/accessibility/windows/keyboard-shortcuts-in-windows'
CODE_REFERENCE = 'https://code.visualstudio.com/docs/reference/default-keybindings'
MAX_AGE_SECONDS = 7 * 24 * 3600


def now():
    return datetime.now(timezone.utc).isoformat()


def packed(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'))


def tokens(value):
    return (len(value if isinstance(value, str) else packed(value)) + 3) // 4


def schema(db):
    db.executescript('''CREATE TABLE IF NOT EXISTS window_knowledge(
      id TEXT PRIMARY KEY,app TEXT,title TEXT,context TEXT,signature TEXT,snapshot TEXT,
      first_at TEXT,last_at TEXT,observations INTEGER DEFAULT 1,baseline_tokens INTEGER DEFAULT 0);
    CREATE TABLE IF NOT EXISTS window_fact(
      window_id TEXT,id TEXT,kind TEXT,label TEXT,parent TEXT,zone TEXT,data TEXT,
      first_at TEXT,last_at TEXT,observations INTEGER DEFAULT 1,PRIMARY KEY(window_id,id));
    CREATE TABLE IF NOT EXISTS window_reuse(
      id INTEGER PRIMARY KEY,at TEXT,task_id TEXT,window_id TEXT,mode TEXT,reason TEXT,
      baseline_tokens INTEGER,payload_tokens INTEGER,estimated_saved INTEGER,
      avoided_vision_calls INTEGER DEFAULT 0,source_ref TEXT,method TEXT);
    CREATE INDEX IF NOT EXISTS ix_window_reuse_task ON window_reuse(task_id,id);
    CREATE TABLE IF NOT EXISTS window_observation(
      window_id TEXT,frame_id TEXT,at TEXT,task_id TEXT,source TEXT,PRIMARY KEY(window_id,frame_id));''')


def sharing(approve=None):
    with library.connect() as db:
        db.execute('CREATE TABLE IF NOT EXISTS knowledge_sharing(id INTEGER PRIMARY KEY CHECK(id=1),approved INTEGER,destination TEXT,at TEXT)')
        if approve is not None:
            db.execute('INSERT OR REPLACE INTO knowledge_sharing VALUES(1,?,?,?)', (int(approve), 'api.deepseek.com', now()))
        row = db.execute('SELECT approved,destination FROM knowledge_sharing WHERE id=1').fetchone()
    return {'approved': bool(row and row[0]), 'destination': row[1] if row else 'api.deepseek.com', 'scope': 'Only task-relevant window metadata/shortcuts and matching project paths; full Desktop index remains local'}


def require_sharing():
    import os
    from urllib.parse import urlsplit
    policy = sharing()
    if not policy['approved'] or urlsplit(os.getenv('DEEPSEEK_BASE_URL', 'https://api.deepseek.com')).hostname != policy['destination']:
        raise ValueError('Task-relevant knowledge sharing requires local approval for api.deepseek.com')


def identity(probe):
    frame = probe.get('frame', {})
    app = (frame.get('exe_path') or frame.get('exe', '')).lower()
    context = {'app': app, 'class': frame.get('class', ''), 'title': frame.get('title', ''),
               'url': probe.get('url', '')}
    return hashlib.sha256(packed(context).encode()).hexdigest()[:24], context


def signature(probe):
    # Values/coordinates are volatile; selected tabs and structure are contextual.
    controls = [[c.get('role'), c.get('name'), c.get('accessibility_path'),
                 bool(c.get('selected')) if 'tab' in c.get('role', '').lower() else None]
                for c in probe.get('controls', [])]
    return hashlib.sha256(packed([controls, probe.get('url', ''), probe.get('menu_signature', '')]).encode()).hexdigest()


def semantic_context(probe):
    chrome = {'system','minimize','maximize','restore','close','help'}
    for control in probe.get('controls',[]):
        role, name = control.get('role','').lower(), control.get('name','').strip().lower()
        if name in chrome or not name:
            continue
        if re.search(r'button|edit|text|tab|list|outline|tree|combo|slider|check|radio|link',role):
            return True
    return False


def shortcuts(frame):
    exe = frame.get('exe', '').lower()
    entries = []
    if exe in ('explorer.exe',):
        entries = [('address_bar', '!d', 'Focus/select the address bar'),
                   ('address_bar_ctrl', '^l', 'Focus/select the address bar'),
                   ('search', '^f', 'Focus the search box'),
                   ('next_tab', '^{Tab}', 'Next tab (tabbed Windows 11 Explorer)'),
                   ('previous_tab', '^+{Tab}', 'Previous tab (tabbed Windows 11 Explorer)'),
                   ('menu_bar', '{Alt}', 'Expose menu/ribbon keyboard hints'),
                   *[(f'tab_{n}', f'^{n}', f'Select tab {n} when supported') for n in range(1, 10)]]
        reference = WINDOWS_REFERENCE
    elif exe in ('code.exe', 'code - insiders.exe'):
        entries = [('command_palette', '^+p', 'Open the command palette'),
                   ('quick_open', '^p', 'Find/open a file by name'),
                   ('menu_bar', '{Alt}', 'Focus the menu bar when supported')]
        reference = CODE_REFERENCE
    else:
        reference = WINDOWS_REFERENCE
    return [{'id': key, 'keys': keys, 'purpose': purpose, 'source_kind': 'documented_reference',
             'source': reference, 'verified_in_this_window': False} for key, keys, purpose in entries]


def zone(bounds, region):
    if not region.get('w') or not region.get('h'):
        return 'unknown'
    x = (bounds.get('x', 0) + bounds.get('w', 0) / 2 - region.get('x', 0)) / region['w']
    y = (bounds.get('y', 0) + bounds.get('h', 0) / 2 - region.get('y', 0)) / region['h']
    return ['top', 'middle', 'bottom'][min(2, max(0, int(y * 3)))] + '-' + ['left', 'center', 'right'][min(2, max(0, int(x * 3)))]


def remember(result, task_id='', probe=None):
    if not result.get('ok') or not result.get('frame', {}).get('exe') or result.get('reused'):
        return None
    frame = result['frame']
    probe = probe or result.get('probe') or result
    key, context = identity(probe)
    snap = {k: v for k, v in result.items() if k not in ('vision_analysis', 'knowledge')}
    timestamp, frame_id = now(), frame.get('frame_id', '')
    region = frame.get('region', {})
    facts = []
    for c in result.get('controls', []) + result.get('menu_controls', []):
        role = c.get('role', '')
        kind = 'tab' if 'tab' in role.lower() and 'list' not in role.lower() else 'menu' if 'menu' in role.lower() else 'section' if re.search('pane|group|toolbar|document', role, re.I) else 'control'
        data = {k: c[k] for k in ('name', 'role', 'accessibility_path', 'parent_path', 'shortcut', 'description', 'default_action', 'selected', 'focused', 'enabled') if k in c}
        facts.append((kind, c.get('name', role), c.get('parent_path', ''), zone(c.get('bounds', {}), region), data))
        if c.get('shortcut'):
            facts.append(('shortcut', c['shortcut'] + ' → ' + c.get('name', ''), c.get('accessibility_path', ''), '',
                          {'keys': c['shortcut'], 'purpose': c.get('name', ''), 'source_kind': 'observed_accessibility', 'source': frame_id}))
    for menu in result.get('menus', []):
        facts.append(('menu', menu.get('label', ''), menu.get('parent', ''), 'top', menu))
        if menu.get('shortcut') or menu.get('mnemonic'):
            facts.append(('shortcut', (menu.get('shortcut') or menu['mnemonic']) + ' → ' + menu.get('label', ''), menu.get('parent', ''), 'top',
                          {'keys': menu.get('shortcut', ''), 'mnemonic': menu.get('mnemonic', ''), 'purpose': menu.get('label', ''), 'source_kind': 'observed_menu', 'source': frame_id}))
    for item in result.get('menu_items', []):
        parent = result.get('opened_menu_path') or result.get('opened_menu', '')
        facts.append(('menu',item.get('label',''),parent,'', {**item,'source_frame':frame_id}))
        if item.get('shortcut'):
            facts.append(('shortcut',item['shortcut']+' → '+item.get('label',''),parent,'',
                          {'keys':item['shortcut'],'purpose':item.get('label',''),'source_kind':'observed_menu','source':frame_id}))
    for item in shortcuts(frame):
        facts.append(('shortcut', item['keys'] + ' → ' + item['purpose'], '', '', item))
    for section in result.get('zones', {}).get('sections', []):
        facts.append(('zone', section.get('label', section['id']), section.get('parent', ''), section['id'], section))
    for group in result.get('ocr', {}).get('groups', []):
        facts.append(('text_group', group['id'], group.get('section_id') or group.get('zone_id', ''), group.get('zone_id', ''),
                      {'text': group.get('text', '')[:4000], 'source_kind': 'observed_zoned_OCR', 'source_frame': frame_id}))
    for y in ('top', 'middle', 'bottom'):
        for x in ('left', 'center', 'right'):
            facts.append(('zone', y + '-' + x, '', y + '-' + x, {'source_kind': 'geometric_partition', 'purpose': 'Coverage region, not a semantic inference'}))
    # Model-visible text estimate, not image tokens or an invented reasoning bill.
    model_text = {**snap}
    if isinstance(model_text.get('accessibility'), dict):
        model_text['accessibility'] = {k: v for k, v in model_text['accessibility'].items() if k != 'controls'}
    baseline = min(7000, tokens(model_text))
    with library.connect() as db:
        schema(db)
        if frame_id and db.execute('SELECT 1 FROM window_observation WHERE window_id=? AND frame_id=?', (key, frame_id)).fetchone():
            return key
        db.execute('INSERT INTO window_knowledge VALUES(?,?,?,?,?,?,?,?,1,?) ON CONFLICT(id) DO UPDATE SET '
                   'signature=excluded.signature,snapshot=excluded.snapshot,last_at=excluded.last_at,observations=observations+1,baseline_tokens=excluded.baseline_tokens',
                   (key, frame.get('exe', ''), frame.get('title', ''), packed(context), signature(probe), packed(snap), timestamp, timestamp, baseline))
        for kind, label, parent, area, data in facts:
            fact_id = hashlib.sha256(packed([kind, label, parent]).encode()).hexdigest()[:24]
            if kind == 'shortcut':
                previous = db.execute('SELECT data FROM window_fact WHERE window_id=? AND id=?', (key, fact_id)).fetchone()
                if previous:
                    prior = json.loads(previous[0])
                    data.update({k: prior[k] for k in ('verified_checks', 'unverified_checks', 'last_check_verified', 'last_check_frame', 'verified_in_this_window') if k in prior})
            db.execute('INSERT INTO window_fact VALUES(?,?,?,?,?,?,?,?,?,1) ON CONFLICT(window_id,id) DO UPDATE SET '
                       'data=excluded.data,zone=excluded.zone,last_at=excluded.last_at,observations=observations+1',
                       (key, fact_id, kind, label, parent, area, packed(data), timestamp, timestamp))
        db.execute('INSERT OR IGNORE INTO window_observation VALUES(?,?,?,?,?)', (key, frame_id or timestamp, timestamp, task_id, 'native_observation'))
    return key


def record_use(task_id, window_id, mode, reason, baseline, payload, source_ref, vision=0, method='Estimated text tokens: ceil(chars/4); image/reasoning tokens excluded'):
    overhead = tokens(payload)
    saved = max(0, baseline - overhead) if mode == 'reuse' else 0
    with library.connect() as db:
        schema(db)
        if mode == 'reuse' and task_id and window_id.startswith('artifact:') and db.execute(
                "SELECT 1 FROM window_reuse WHERE task_id=? AND window_id=? AND mode='reuse'", (task_id,window_id)).fetchone():
            saved = 0
            method += '; this source was already credited in this task; repeated use receives no additional source-generation estimate'
        cursor = db.execute('INSERT INTO window_reuse(at,task_id,window_id,mode,reason,baseline_tokens,payload_tokens,estimated_saved,avoided_vision_calls,source_ref,method) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
                            (now(), task_id, window_id, mode, reason, baseline, overhead, saved, vision, source_ref, method))
        identity = cursor.lastrowid
    return {'id': identity, 'mode': mode, 'reason': reason, 'estimated_text_tokens_saved': saved,
            'estimated_baseline_tokens': baseline, 'estimated_returned_tokens': overhead,
            'avoided_vision_calls': vision, 'method': method, 'source_ref': source_ref}


def learn(args, invoke, task_id='', rng=None):
    probe = invoke('fan_window_probe', {'hwnd': args.get('hwnd', 0)})
    if not probe.get('ok'):
        return probe
    key, _ = identity(probe)
    with library.connect() as db:
        schema(db)
        row = db.execute('SELECT * FROM window_knowledge WHERE id=?', (key,)).fetchone()
    reason = 'new_window'
    eligible = False
    if row:
        age = (datetime.now(timezone.utc) - datetime.fromisoformat(row['last_at'])).total_seconds()
        eligible = row['signature'] == signature(probe) and age < MAX_AGE_SECONDS
        reason = 'changed_structure' if row['signature'] != signature(probe) else 'aged_evidence'
        if json.loads(row['snapshot']).get('probe_only'):
            eligible, reason = False, 'only_probe_coverage'
    # Explicit exploration requests always run; incomplete probes never certify reuse.
    if probe.get('browser_context_unknown') or not semantic_context(probe):
        eligible, reason = False, 'unverified_context'
    if args.get('refresh') or args.get('maximize') or args.get('activate_menu') or args.get('fullscreen') or args.get('explore_menus') or args.get('probe_navigation'):
        eligible, reason = False, 'requested_exploration'
    chosen_reuse = eligible and (rng or random.random)() >= .25
    if chosen_reuse:
        from .spatial import zones
        snap = json.loads(row['snapshot'])
        historical = [{k: c[k] for k in ('name', 'role', 'accessibility_path', 'parent_path', 'shortcut') if k in c} for c in snap.get('controls', [])[:80]]
        result = {'ok': True, 'reused': True, 'knowledge_id': key, 'frame': probe['frame'],
                  'zones': {**zones(probe['frame'].get('region', {})), 'created_before_text_analysis': True,
                            'note': 'Current geometric zones from the live probe. No OCR recognition or image-model analysis performed on this reuse step.'},
                  'controls': probe.get('controls', []), 'tabs': probe.get('tabs', []), 'shortcuts': shortcuts(probe['frame']),
                  'indexed_controls': historical, 'indexed_control_count': len(snap.get('controls', [])),
                  'menus': snap.get('menus', [])[:80], 'historical_frame_id': snap.get('frame', {}).get('frame_id', ''),
                  'note': 'Indexed controls are historical references, not live click bounds. Current controls/tabs come from the live probe. Resolve live before input.',
                  'coverage': snap.get('coverage', snap.get('accessibility', {}))}
        credit = record_use(task_id, key, 'reuse', 'eligible_75_percent_branch', row['baseline_tokens'], result,
                            result['historical_frame_id'], int(bool(snap.get('image_path'))))
    else:
        if eligible:
            reason = 'random_25_percent_refresh'
        params = {k: v for k, v in args.items() if k in ('hwnd', 'maximize', 'activate_menu', 'fullscreen')}
        params['hwnd'] = probe['frame']['hwnd']
        result = invoke('fan_window_survey', params)
        if not result.get('ok'):
            return result
        result['probe'] = probe
        key = remember(result, task_id, probe) or key
        result['knowledge_id'] = key
        credit = record_use(task_id, key, 'fresh', reason, 0, result, result.get('frame', {}).get('frame_id', ''))
        if args.get('activate_menu') or args.get('explore_menus') or args.get('probe_navigation'):
            result['exploration'] = invoke('daa_explore', {'hwnd': probe['frame']['hwnd'],
                'menus': bool(args.get('activate_menu') or args.get('explore_menus')),
                'controls': bool(args.get('probe_navigation')), 'max_branches': 8, 'max_depth': 2})
    result['knowledge_reuse'] = credit
    return result


def observe(tool, args, result, task_id=''):
    if tool in ('fan_window_inspect', 'fan_window_survey', 'fan_window_menu', 'fan_window_probe_item') and result.get('ok'):
        remember(result, task_id)
    elif tool == 'fan_window_shortcut' and result.get('ok') and result.get('action_performed'):
        probe = result.get('observation', {})
        key, _ = identity(probe)
        with library.connect() as db:
            schema(db)
            row = db.execute('SELECT baseline_tokens FROM window_knowledge WHERE id=?', (key,)).fetchone()
        if not row:
            remember(probe, task_id)
        with library.connect() as db:
            schema(db)
            facts = db.execute("SELECT id,data FROM window_fact WHERE window_id=? AND kind='shortcut'", (key,)).fetchall()
            for fact in facts:
                data = json.loads(fact['data'])
                if data.get('id') != args.get('shortcut'):
                    continue
                verified = bool(result.get('verified'))
                data['verified_checks'] = data.get('verified_checks', 0) + int(verified)
                data['unverified_checks'] = data.get('unverified_checks', 0) + int(not verified)
                data['last_check_verified'] = verified
                data['last_check_frame'] = probe.get('frame', {}).get('frame_id', '')
                data['verified_in_this_window'] = bool(data['verified_checks'])
                db.execute('UPDATE window_fact SET data=?,last_at=? WHERE window_id=? AND id=?', (packed(data), now(), key, fact['id']))
        result['knowledge_reuse'] = record_use(task_id, key, 'reuse', 'known_navigation_shortcut', row[0] if row else 0,
                                              result, 'documented navigation reference; live postcondition ' + str(result.get('verified', False)))


def artifact_use(tool, args, result, task_id='', task_created=''):
    prefixes = {'ahk_script_run': '', 'fan_workflow_run': 'workflow:', 'fan_learning_rehearse': 'workflow:', 'fan_pattern_search': 'pattern:', 'daa_unit_run': 'unit:'}
    if tool not in prefixes or not args.get('name') or not result.get('ok'):
        return None
    try:
        record = library.get(prefixes[tool] + args['name'])
    except ValueError:
        return None
    if task_created and record['updated_at'] >= task_created:
        return None
    if tool == 'fan_pattern_search' and not result.get('total_matches', len(result.get('matches', []))):
        return None
    method = ('Counterfactual estimate from saved source/map text at ceil(chars/4), less returned tool text. '
              'No claim that a rewrite would actually have occurred; excludes image and reasoning tokens. '
              'Execution and semantic verification are separate from reference reuse.')
    source_hash = record['metadata'].get('sha256') or hashlib.sha256(record['content'].encode()).hexdigest()
    return record_use(task_id, 'artifact:' + source_hash[:24], 'reuse', tool + ':saved_revision_' + str(record['revision']),
                      min(7000, tokens(record['content'])), result, record['name'] + '@' + str(record['revision']), method=method)


def lookup(window_id='', query='', offset=0, limit=40):
    with library.connect() as db:
        schema(db)
        if not window_id:
            rows = db.execute('SELECT id,app,title,observations,last_at FROM window_knowledge WHERE title LIKE ? OR app LIKE ? ORDER BY last_at DESC LIMIT 30', ('%' + query + '%',) * 2).fetchall()
            return {'ok': True, 'windows': [dict(r) for r in rows], 'reference_warning': 'Maps are context-scoped historical evidence. Use fan_window_learn for a live probe and 75/25 reuse decision.'}
        row = db.execute('SELECT id,app,title,observations,last_at FROM window_knowledge WHERE id=?', (window_id,)).fetchone()
        if not row:
            raise ValueError('Window knowledge was not found')
        facts = db.execute('SELECT * FROM window_fact WHERE window_id=? ORDER BY kind,label LIMIT ? OFFSET ?', (window_id, min(100, max(1, limit)), max(0, offset))).fetchall()
        count = db.execute('SELECT COUNT(*) FROM window_fact WHERE window_id=?', (window_id,)).fetchone()[0]
    return {'ok': True, 'window': dict(row), 'facts': [{**dict(r), 'data': json.loads(r['data'])} for r in facts], 'total': count,
            'has_more': offset + len(facts) < count, 'relations': 'window → facts; parent is the observed accessibility path/menu parent; zone is a geometric region; shortcuts link to their observed/documented purpose',
            'warning': 'Accumulated facts include historical states. Do not use saved geometry as current input targets.'}


def stats(query='', task_id=''):
    with library.connect() as db:
        schema(db)
        rows = db.execute('SELECT id,app,title,observations,last_at FROM window_knowledge WHERE title LIKE ? OR app LIKE ? ORDER BY last_at DESC LIMIT 100', ('%' + query + '%',) * 2).fetchall()
        windows = []
        for r in rows:
            item = dict(r)
            counts = {x[0]: x[1] for x in db.execute('SELECT kind,COUNT(*) FROM window_fact WHERE window_id=? GROUP BY kind', (r['id'],))}
            uses = db.execute("SELECT SUM(mode='reuse'),SUM(mode='fresh'),COALESCE(SUM(estimated_saved),0) FROM window_reuse WHERE window_id=?", (r['id'],)).fetchone()
            item.update(counts=counts, reused=uses[0] or 0, fresh=uses[1] or 0, estimated_saved=uses[2])
            windows.append(item)
        clauses, params = [], []
        if task_id:
            clauses.append('task_id=?')
            params.append(task_id)
        if query:
            clauses.append('window_id IN (SELECT id FROM window_knowledge WHERE title LIKE ? OR app LIKE ?)')
            params.extend(('%' + query + '%',) * 2)
        condition = ' WHERE ' + ' AND '.join(clauses) if clauses else ''
        totals = db.execute('SELECT COUNT(*),COALESCE(SUM(estimated_saved),0),COALESCE(SUM(avoided_vision_calls),0) FROM window_reuse' + condition, params).fetchone()
        recent = [dict(r) for r in db.execute('SELECT * FROM window_reuse' + condition + ' ORDER BY id DESC LIMIT 60', params)]
    return {'windows': windows, 'uses': totals[0], 'estimated_saved': totals[1], 'avoided_vision_calls': totals[2], 'recent': recent,
            'policy': '75% reuse / 25% randomized refresh among eligible matching contexts. New, changed, aged or explicitly explored windows force fresh inspection.',
            'estimate_method': 'Text-only counterfactual estimate: ceil(chars/4), capped to the prior model-visible text budget, less returned reuse payload. Not measured billing; image/reasoning tokens excluded. Documented shortcuts are references until independently verified.'}


def pre_context(prompt):
    terms = relevant_terms(prompt)
    found = {}
    for term in terms:
        for row in lookup(query=term)['windows']:
            found[row['id']] = row
    references = shortcuts({'exe': 'explorer.exe'}) if re.search(r'explorer|folder|desktop|directory', prompt, re.I) else shortcuts({'exe': 'code.exe'}) if re.search(r'vscode|vs code|code.exe', prompt, re.I) else []
    return '\nWINDOW KNOWLEDGE (reference data, not authorization): ' + packed({'windows': list(found.values())[:8], 'documented_shortcuts': references[:8],
          'policy': 'Prefer fan_window_learn for standard discovery. It probes live and chooses 75% matching-map reuse / 25% fresh survey. Unknown/changed contexts force fresh; input always needs live targeting.'})


def relevant_terms(prompt):
    stop = {'the','and','that','this','with','from','then','please','learn','inspect','window','windows','project','create','show','give','have','into','using','open','save','file','for','its','you','your','use','can','all','task'}
    return list(dict.fromkeys(term for term in re.findall(r'[\w.-]{3,}', prompt.lower()) if term not in stop))[:12]
