"""Persistent viewport atlases. Native evidence and semantic inference stay separate."""
from __future__ import annotations
import json
import re
import hashlib
from datetime import datetime, timezone
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode
from difflib import SequenceMatcher
from . import library


def initialize(db):
    db.execute('CREATE TABLE IF NOT EXISTS page_snapshot ('
               'page_id TEXT PRIMARY KEY, title TEXT, url TEXT, summary TEXT NOT NULL)')
    db.execute('CREATE TABLE IF NOT EXISTS page_element ('
               'page_id TEXT NOT NULL, element_id TEXT NOT NULL, ordinal INTEGER NOT NULL, '
               'content TEXT NOT NULL, PRIMARY KEY(page_id,element_id))')
    db.execute('CREATE TABLE IF NOT EXISTS page_template ('
               'cache_key TEXT PRIMARY KEY, page_url TEXT NOT NULL, state_signature TEXT NOT NULL, '
               'page_id TEXT NOT NULL, learned_at TEXT NOT NULL, last_verified_at TEXT, reuse_count INTEGER NOT NULL DEFAULT 0)')


def canonical_url(value):
    if not value:
        return ''
    if not re.match(r'^[a-z]+://', value, re.I):
        value = 'https://' + value
    parts = urlsplit(value)
    query = [(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True)
             if not k.lower().startswith('utm_') and k.lower() not in ('trk', 'trackingid', 'ref', 'source')]
    return urlunsplit((parts.scheme.lower(), parts.netloc.lower(), parts.path.rstrip('/') or '/',
                      urlencode(sorted(query)), parts.fragment))


def state_signature(controls):
    """Keep feed content out of identity; form schemas and dialogs distinguish views."""
    document_paths = [c['accessibility_path'] for c in controls if c.get('accessibility_path') and 'document' in c.get('role', '').lower()]
    fields = set()
    for c in controls:
        path = c.get('accessibility_path', '')
        if document_paths and not any(path.startswith(p+'.') or path == p for p in document_paths if p):
            continue
        role = c.get('role', '').lower()
        name = c.get('name', '').strip().casefold()
        if re.search(r'edit|text field|combo|radio|check|dialog', role):
            fields.add((role, name))
        elif re.fullmatch(r'next|continue|review|submit application|submit|apply now|easy apply', name):
            fields.add((role, name))
    return hashlib.sha256(json.dumps(sorted(fields), ensure_ascii=False).encode()).hexdigest()[:24]


def cache_identity(url, controls):
    canonical = canonical_url(url)
    signature = state_signature(controls)
    return canonical, signature, hashlib.sha256((canonical+'\n'+signature).encode()).hexdigest()


def reuse(probe):
    if (not probe.get('ok') or probe.get('accessibility', {}).get('truncated')
        or probe.get('accessibility', {}).get('error') or not probe.get('url')
        or not any('document' in c.get('role', '').lower() for c in probe.get('controls', []))):
        return None
    url, signature, key = cache_identity(probe['url'], probe.get('controls', []))
    with library.connect() as db:
        initialize(db)
        row = db.execute('SELECT page_id FROM page_template WHERE cache_key=?', (key,)).fetchone()
        if not row:
            return None
        stamp = datetime.now(timezone.utc).isoformat()
        db.execute('UPDATE page_template SET last_verified_at=?,reuse_count=reuse_count+1 WHERE cache_key=?', (stamp, key))
    page = get(row[0])
    return {**page, 'reused': True, 'live_frame': probe['frame'], 'last_verified_at': stamp,
            'verification': 'Current URL and form/dialog schema match retained memory. Individual targets still resolve live.',
            'capture_performed': False, 'image_source': 'retained_historical_snapshot'}


def intersection(a, b):
    return max(0, min(a['x']+a['w'], b['x']+b['w'])-max(a['x'], b['x'])) * max(
        0, min(a['y']+a['h'], b['y']+b['h'])-max(a['y'], b['y']))


def page_url(controls):
    for c in controls:
        if 'document' in c.get('role', '').lower() and re.match(r'(https?://|file://)', c.get('value', ''), re.I):
            return c['value']
    for c in controls:
        if re.search(r'address.*(search|bar)', c.get('name', ''), re.I) and c.get('value'):
            return c['value']
    return ''


def action_kind(c):
    if c.get('protected') or not c.get('enabled', True):
        return 'unavailable'
    role = c.get('role', '').lower()
    if 'edit' in role or 'text field' in role:
        return 'type'
    if re.search(r'link|button|check|radio|tab|menu item', role) or c.get('default_action'):
        return 'click'
    if re.search(r'combo|list|slider', role):
        return 'select'
    return 'read'


def build(result):
    """Combine all returned controls and OCR lines; retain unlabelled image tiles."""
    if not result.get('ok'):
        return result
    frame, controls = result['frame'], result.get('controls', [])
    page_id = frame['frame_id']
    region = frame['region']
    assets = result.get('assets', {})
    documents = [c for c in controls if 'document' in c.get('role', '').lower()]
    document = max(documents, key=lambda c: c['bounds']['w']*c['bounds']['h'], default=None)
    body = document['bounds'] if document else region
    containers = [c for c in controls if re.search(r'document|toolbar|group|pane|list|table|menu|section', c.get('role', ''), re.I)]
    groups = {}
    def group_for(c):
        b = c['bounds']
        if document and b['y']+b['h'] <= body['y']:
            return 'browser_chrome', 'Browser tabs, address bar and toolbar', 'observed_document_boundary'
        ancestors = [a for a in containers if a.get('accessibility_path') and c.get('accessibility_path', '').startswith(a['accessibility_path']+'.')]
        named = [a for a in ancestors if a.get('name') and len(a['name']) < 140]
        if named:
            parent = max(named, key=lambda a: len(a['accessibility_path']))
            return 'container-'+str(parent['id']), parent['name'], 'observed_accessibility_ancestor'
        cx, cy = b['x']+b['w']/2, b['y']+b['h']/2
        horizontal = 'left' if cx < body['x']+body['w']*.28 else 'right' if cx > body['x']+body['w']*.72 else 'center'
        vertical = 'top' if cy < body['y']+body['h']*.20 else 'bottom' if cy > body['y']+body['h']*.85 else 'main'
        return vertical+'-'+horizontal, vertical.title()+' '+horizontal+' region', 'inferred_spatial_group'

    elements = []
    identities = {}
    for c in controls:
        identity = (c.get('role', ''), c.get('name', ''), c.get('href', ''))
        identities[identity] = identities.get(identity, 0) + 1
    for c in controls:
        element = {**c, 'element_id': 'acc-'+str(c['id']), **assets.get('acc-'+str(c['id']), {})}
        gid, label, source = group_for(c)
        groups.setdefault(gid, {'group_id': gid, 'label': label, 'source': source, 'count': 0})['count'] += 1
        element.update(group=gid, kind='accessibility', ocr_lines=[], ocr_text='',
                       scope='page' if document and c.get('accessibility_path', '').startswith(document.get('accessibility_path', '')+'.') else 'browser_chrome' if gid == 'browser_chrome' else 'unknown',
                       unique_identity=identities[(c.get('role', ''), c.get('name', ''), c.get('href', ''))] == 1,
                       action_hint=action_kind(c), actionable=action_kind(c) not in ('read', 'unavailable'),
                       description=c.get('name') or c.get('description') or 'Unlabelled '+c.get('role', 'visual element'),
                       description_source='observed_accessibility_label',
                       locator={'accessibility_path': c.get('accessibility_path', ''),
                                'role': c.get('role', ''), 'name': c.get('name', ''), 'href': c.get('href', '')},
                       link_status='observed_target' if c.get('href') else 'target_not_exposed' if 'link' in c.get('role', '').lower() else 'not_a_link')
        elements.append(element)
    unmatched = 0
    for index, line in enumerate(result.get('ocr', {}).get('lines', []), 1):
        text, box = line['text'], line['bounds']
        candidates = []
        for e in elements:
            if e['kind'] != 'accessibility' or e.get('protected') or re.search(r'document|pane|group|window|toolbar', e.get('role', ''), re.I):
                continue
            overlap = intersection(box, e['bounds']) / max(1, box['w']*box['h'])
            if overlap >= .6:
                similarity = SequenceMatcher(None, text.casefold(), e.get('name', '').casefold()).ratio()
                candidates.append((similarity, -e['bounds']['w']*e['bounds']['h'], e))
        if candidates:
            target = max(candidates, key=lambda c: (c[0], c[1]))[2]
            target['ocr_lines'].append(index)
            target['ocr_text'] += ('\n' if target['ocr_text'] else '') + text
        else:
            unmatched += 1
            gid, label, source = group_for({'bounds': box})
            groups.setdefault(gid, {'group_id': gid, 'label': label, 'source': source, 'count': 0})['count'] += 1
            elements.append({'element_id': 'ocr-'+str(index), 'kind': 'ocr_text', 'role': 'text', 'name': text,
                'description': text, 'description_source': 'observed_ocr', 'bounds': box, 'group': gid,
                'actionable': False, 'action_hint': 'read', 'source': 'observed_Windows_OCR',
                **assets.get('ocr-'+str(index), {})})
    for tile in result.get('visual_tiles', []):
        elements.append({'element_id': tile['id'], 'kind': 'visual_region', 'bounds': tile['bounds'],
            'description': 'Image evidence for this viewport region; individual unlabelled features need vision interpretation',
            'description_source': 'uninterpreted_image_region', 'group': 'visual_regions', 'actionable': False,
            'action_hint': 'inspect_image', **assets.get(tile['id'], {})})
    if result.get('visual_tiles'):
        groups['visual_regions'] = {'group_id': 'visual_regions', 'label': 'Complete image partition',
                                  'source': 'observed_image_geometry', 'count': len(result['visual_tiles'])}
    accessibility = result.get('accessibility', {})
    coverage = {'scope': 'visible_chrome_viewport', 'full_window_image': bool(result.get('photo_ref')),
        'accessibility_elements': len(controls), 'accessibility_truncated': accessibility.get('truncated', False),
        'accessibility_error': accessibility.get('error', ''), 'ocr_lines': len(result.get('ocr', {}).get('lines', [])),
        'ocr_truncated': result.get('ocr', {}).get('truncated', False), 'unmatched_ocr_elements': unmatched,
        'visual_tiles': len(result.get('visual_tiles', [])), 'saved_crops': sum(bool(e.get('photo_ref')) for e in elements),
        'findtext_candidates': sum(bool(e.get('pattern_text')) for e in elements),
        'content_stable': frame.get('content_stable', False),
        'limitation': 'Full visible pixels are retained; element enumeration is best effort. Off-screen content, hidden menus, inaccessible link URLs and anonymous image semantics require further observations.'}
    summary = {k: result[k] for k in ('frame', 'image_path', 'annotated_image_path', 'photo_ref', 'annotated_photo_ref', 'warnings') if k in result}
    summary.update(ok=True, page_id=page_id, title=frame['title'], url=page_url(controls), groups=list(groups.values()),
        element_count=len(elements), coverage=coverage,
        usage='fan_page_learn reuses matching retained maps by default. fan_page_get searches them; fan_page_resolve checks a live target. refresh=true explicitly captures another revision. Images describe their saved capture time.')
    url, signature, key = cache_identity(summary['url'], controls)
    url_control = next((c for c in controls if c.get('value') == summary['url'] and c.get('accessibility_path')
                        and ('document' in c.get('role', '').lower() or re.search(r'address.*(search|bar)', c.get('name', ''), re.I))), None)
    summary['url_locator'] = {'path': url_control['accessibility_path']} if url_control else {}
    summary.update(page_url_key=url, state_signature=signature, reused=False, capture_performed=True)
    with library.connect() as db:
        initialize(db)
        db.execute('INSERT OR REPLACE INTO page_snapshot VALUES(?,?,?,?)',
                   (page_id, summary['title'], summary['url'], json.dumps(summary, ensure_ascii=False)))
        db.execute('DELETE FROM page_element WHERE page_id=?', (page_id,))
        db.executemany('INSERT INTO page_element VALUES(?,?,?,?)',
            [(page_id, e['element_id'], i, json.dumps(e, ensure_ascii=False)) for i, e in enumerate(elements)])
        if url and not coverage['accessibility_truncated'] and not coverage['accessibility_error']:
            db.execute('INSERT INTO page_template(cache_key,page_url,state_signature,page_id,learned_at) VALUES(?,?,?,?,?) '
                       'ON CONFLICT(cache_key) DO UPDATE SET page_id=excluded.page_id,learned_at=excluded.learned_at',
                       (key, url, signature, page_id, frame.get('captured_at_utc', datetime.now(timezone.utc).isoformat())))
    # Keep page contents out of the agent's auto-refreshed knowledge prompt.
    # Remote sharing of these atlases requires a separate user approval.
    # A bounded first view; the entire atlas remains queryable in SQLite.
    return {**summary, 'elements': elements[:30], 'elements_returned': min(30, len(elements)),
            'elements_have_more': len(elements) > 30, 'legend': result.get('legend', [])[:100]}


def get(page_id, *, query='', group='', offset=0, limit=30):
    if page_id.startswith('chrome-'):
        from .job_browser import retained
        summary=retained(page_id)
        elements=summary.pop('elements')
        if group:elements=[e for e in elements if e.get('group')==group or e.get('semantic_group')==group]
        if query:elements=[e for e in elements if query.casefold() in json.dumps(e,ensure_ascii=False).casefold()]
        return {**summary,'elements':elements[offset:offset+limit],'matches':len(elements),'offset':offset,'has_more':offset+limit<len(elements)}
    with library.connect() as db:
        initialize(db)
        row = db.execute('SELECT summary FROM page_snapshot WHERE page_id=?', (page_id,)).fetchone()
        if not row:
            raise ValueError('Saved page atlas not found')
        summary = json.loads(row[0])
        rows = db.execute('SELECT content FROM page_element WHERE page_id=? ORDER BY ordinal', (page_id,)).fetchall()
    elements = [json.loads(row[0]) for row in rows]
    if group:
        elements = [e for e in elements if e.get('group') == group or e.get('semantic_group') == group]
    if query:
        elements = [e for e in elements if query.casefold() in json.dumps(e, ensure_ascii=False).casefold()]
    return {**summary, 'elements': elements[offset:offset+limit], 'matches': len(elements), 'offset': offset,
            'has_more': offset+limit < len(elements)}


def element(page_id, element_id):
    with library.connect() as db:
        initialize(db)
        row = db.execute('SELECT content FROM page_element WHERE page_id=? AND element_id=?', (page_id, element_id)).fetchone()
    if not row:
        raise ValueError('Saved page element not found')
    return json.loads(row[0])


def list_pages(query='', limit=20):
    with library.connect() as db:
        initialize(db)
        rows = db.execute('SELECT summary FROM page_snapshot ORDER BY rowid DESC').fetchall()
        browser_ids=[r[0] for r in db.execute('SELECT page_id FROM browser_page ORDER BY updated_at DESC')] if db.execute("SELECT 1 FROM sqlite_master WHERE name='browser_page'").fetchone() else []
    values = [json.loads(row[0]) for row in rows]
    values = [get(page_id,limit=1) for page_id in browser_ids] + values
    values = [v for v in values if query.casefold() in (v['title']+' '+v['url']).casefold()]
    return {'ok': True, 'pages': [{k: p[k] for k in ('page_id', 'title', 'url', 'element_count', 'coverage')}
                                for p in values[:limit]]}


def remembered_url(url):
    with library.connect() as db:
        initialize(db)
        row = db.execute('SELECT page_id FROM page_template WHERE page_url=? ORDER BY learned_at DESC LIMIT 1',
                         (canonical_url(url),)).fetchone()
    return get(row[0]) if row else None


def prepare(name, args):
    page = get(args['page_id'], limit=1)
    page.pop('elements', None)
    if args['page_id'].startswith('chrome-'):
        raise ValueError('Owned Chrome maps require fresh DOM-node resolution by the application runner. Historical CSS bounds cannot be used for physical input.')
    if name == 'fan_page_resolve':
        return {**args, '_page': page, '_element': element(args['page_id'], args['element_id'])}
    item = element(args['page_id'], args['element_id']) if args.get('element_id') else None
    if item and item.get('protected'):
        raise ValueError('Protected field crops cannot be retrieved')
    return {**args, '_photo_ref': item.get('photo_ref', page['photo_ref']) if item else page['photo_ref'],
            '_bounds': item.get('crop_bounds', item['bounds']) if item else page['frame']['region'],
            '_capture_region': page['frame']['region'], '_crop': bool(item and not item.get('photo_ref'))}


def enrich(page_id, text):
    """Attach optional image-model descriptions; they never replace observed locators."""
    candidate = text.strip()
    if candidate.startswith('```'):
        candidate = re.sub(r'^```(?:json)?\s*|\s*```$', '', candidate)
    try:
        value = json.loads(candidate)
    except (ValueError, TypeError):
        return {'updated': 0, 'note': 'Vision returned prose; its analysis is saved separately.'}
    if not isinstance(value, dict):
        return {'updated': 0}
    if page_id.startswith('chrome-'):
        from .job_browser import retained
        page=retained(page_id)
        supplied=value.get('elements',[])
        mapping={e['element_id']:e for e in supplied if isinstance(e,dict) and isinstance(e.get('element_id'),str)} if isinstance(supplied,list) else {}
        updated=0
        for e in page['elements']:
            item=mapping.get(e['element_id'])
            if item:
                e.update(semantic_description=str(item.get('description',''))[:2000],semantic_purpose=str(item.get('purpose',''))[:1000],
                         semantic_group=str(item.get('group',''))[:200],semantic_source='image_model_inference')
                updated+=1
        with library.connect() as db:
            row=db.execute('SELECT evidence FROM browser_page WHERE page_id=?',(page_id,)).fetchone()
            evidence=json.loads(row[0]);evidence['elements']=page['elements']
            evidence['semantic_page_description']=str(value.get('page_description',''))[:3000]
            evidence['semantic_groups']=[g for g in value.get('groups',[])[:50] if isinstance(g,dict)] if isinstance(value.get('groups'),list) else []
            db.execute('UPDATE browser_page SET evidence=? WHERE page_id=?',(json.dumps(evidence,ensure_ascii=False),page_id))
        return {'updated':updated,'source_kind':'inference'}
    updated = 0
    with library.connect() as db:
        initialize(db)
        items = value.get('elements', [])
        for item in (items[:150] if isinstance(items, list) else []):
            if not isinstance(item, dict) or not isinstance(item.get('element_id'), str):
                continue
            row = db.execute('SELECT content FROM page_element WHERE page_id=? AND element_id=?', (page_id, item['element_id'])).fetchone()
            if not row:
                continue
            e = json.loads(row[0])
            e.update(semantic_description=str(item.get('description', ''))[:2000],
                semantic_purpose=str(item.get('purpose', ''))[:1000], semantic_group=str(item.get('group', ''))[:200],
                semantic_source='image_model_inference')
            db.execute('UPDATE page_element SET content=? WHERE page_id=? AND element_id=?',
                       (json.dumps(e, ensure_ascii=False), page_id, e['element_id']))
            updated += 1
        row = db.execute('SELECT summary FROM page_snapshot WHERE page_id=?', (page_id,)).fetchone()
        if row:
            summary = json.loads(row[0])
            summary['semantic_page_description'] = str(value.get('page_description', ''))[:3000]
            summary['semantic_source'] = 'image_model_inference'
            groups = value.get('groups', [])
            summary['semantic_groups'] = [g for g in groups[:50] if isinstance(g, dict)] if isinstance(groups, list) else []
            db.execute('UPDATE page_snapshot SET summary=? WHERE page_id=?', (json.dumps(summary, ensure_ascii=False), page_id))
    return {'updated': updated, 'source_kind': 'inference'}
