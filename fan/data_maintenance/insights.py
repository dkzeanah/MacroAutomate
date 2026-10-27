"""Bounded, read-only consolidation of Fan's real learning stores.

Nothing here promotes a pattern, writes a workflow, rewrites a source database,
reads embedded images, or replays recorded input. Recommendations are derived
from observations and retain their coverage and verification limits.
"""
from __future__ import annotations

from collections import Counter, defaultdict
from datetime import datetime, timedelta
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import time
from typing import Mapping


# Columns match TrackingDB/UsagePatternPredictor/VisionScout/AppLearner/StudyDB
# and the manual workflow/bridge schemas. Integers are character caps; None
# means a numeric or timestamp column. Raw keystrokes, clipboard bodies, image
# base64, binary patterns and page text deliberately never appear in this list.
TABLES = {
    'tracking': {
        'usage_transition': ('UsagePatternPredictor', 'last_ts', {'id': None, 'prefix_hash': 80, 'prefix_text': 512, 'prefix_len': None, 'next_token': 256, 'next_kind': 40, 'support': None, 'accepted': None, 'last_ts': None}),
        'vs_sequence': ('VisionScout', 'last_seen', {'id': None, 'sig': 80, 'steps': 1024, 'count': None, 'length': None, 'first_seen': None, 'last_seen': None}),
        'usage_element': ('UsagePatternPredictor', 'last_ts', {'id': None, 'win_id': None, 'app_id': None, 'signature': 80, 'name': 160, 'role': 60, 'verified': None, 'seen_count': None, 'click_count': None, 'access_count': None, 'score': None, 'promoted': None, 'element_id': None, 'last_ts': None}),
        'vs_element': ('VisionScout', 'last_seen', {'id': None, 'win_id': None, 'app_id': None, 'score': None, 'clicks': None, 'accesses': None, 'tier': None, 'promoted': None, 'review_state': 40, 'last_seen': None}),
        'element': ('ElementAutomation', 'updated_ts', {'id': None, 'win_id': None, 'app_id': None, 'name': 160, 'role': 60, 'hits': None, 'last_hit_ts': None, 'created_ts': None, 'updated_ts': None}),
        'mouse_feature': ('MouseTracker', 'last_seen', {'id': None, 'win_id': None, 'app_id': None, 'kind': 60, 'clicks': None, 'dwell_ms': None, 'samples': None, 'element_id': None, 'last_seen': None}),
        'snap_entry': ('SnapshotEngine', 'ts', {'id': None, 'win_id': None, 'app_id': None, 'title': 120, 'exe': 80, 'ts': None, 'w': None, 'h': None, 'image_bytes': None, 'image_hash': 80, 'b64_len': None}),
        'app': ('WindowTracker', 'last_seen', {'id': None, 'exe': 100, 'display': 120, 'total_ms': None, 'activations': None, 'last_seen': None}),
        'win': ('WindowTracker', 'last_seen', {'id': None, 'app_id': None, 'name': 120, 'total_ms': None, 'activations': None, 'last_seen': None}),
        'win_session': ('WindowTracker', 'start_ts', {'id': None, 'win_id': None, 'app_id': None, 'duration_ms': None, 'start_ts': None, 'end_ts': None}),
        'mouse_snapshot': ('MouseTracker', 'start_ts', {'id': None, 'win_id': None, 'samples': None, 'distance': None, 'idle_ms': None, 'click_count': None, 'dwell_count': None, 'start_ts': None}),
        'key_snapshot': ('KeyTracker', 'start_ts', {'id': None, 'win_id': None, 'keystrokes': None, 'wpm': None, 'start_ts': None}),
        'hotkey_stat': ('KeyTracker', 'last_ts', {'win_id': None, 'app_id': None, 'combo': 80, 'count': None, 'last_ts': None}),
        'usage_event': ('UsagePatternPredictor', 'ts', {'id': None, 'win_id': None, 'app_id': None, 'kind': 40, 'token': 256, 'automated': None, 'ts': None}),
        'vs_action': ('VisionScout', 'ts', {'id': None, 'win_id': None, 'app_id': None, 'element_id': None, 'kind': 40, 'ts': None}),
        'clip_history': ('KeyTracker', 'ts', {'id': None, 'win_id': None, 'hash': 80, 'length': None, 'kind': 40, 'ts': None}),
        'key_event': ('KeyTracker', 'ts', {'id': None, 'win_id': None, 'kind': 40, 'ts': None}),
        'chrome_history_archive': ('SnapshotRecovery', 'visited_ts', {'id': None, 'profile': 80, 'visit_count': None, 'visited_ts': None}),
        'study_answer_log': ('StudyAssistant', 'ts', {'id': None, 'qa_id': None, 'state': 40, 'provider': 50, 'model': 80, 'confidence': None, 'cost': None, 'ts': None}),
        'qa_item': ('StudyAssistant', 'created_ts', {'id': None, 'kind': 40, 'state': 40, 'confidence': None, 'archived': None, 'created_ts': None, 'verified_ts': None}),
        'study_source': ('StudyIngest', 'added_ts', {'id': None, 'kind': 40, 'title': 120, 'bytes': None, 'pages': None, 'excluded': None, 'added_ts': None}),
        'study_passage': ('StudyIngest', 'created_ts', {'id': None, 'source_id': None, 'page': None, 'created_ts': None}),
        'study_concept': ('StudyAssistant', 'last_ts', {'id': None, 'name': 160, 'source_id': None, 'seen': None, 'importance': None, 'last_ts': None}),
        'study_concept_link': ('StudyAssistant', '', {'id': None, 'from_id': None, 'to_id': None, 'relation': 60, 'weight': None}),
        'study_review': ('StudyAssistant', 'last_ts', {'qa_id': None, 'reps': None, 'interval_days': None, 'last_grade': None, 'last_ts': None, 'due_ts': None}),
        'query': ('ResearchPipeline', 'created_ts', {'id': None, 'status': 40, 'engine': 60, 'created_ts': None}),
        'query_link': ('ResearchPipeline', 'created_ts', {'id': None, 'query_id': None, 'status': 40, 'created_ts': None}),
        'query_insight': ('ResearchPipeline', 'created_ts', {'id': None, 'query_id': None, 'link_id': None, 'source': 100, 'created_ts': None}),
    },
    'macro': {
        'patterns': ('Patterns', '', {'name': 120, 'desc': 300, 'captureWindow': 120, 'qualifier': 160}),
        'sequences': ('WorkflowComposer', '', {'name': 120, 'speed': None, 'hotkey': 80, 'hotstring': 80}),
        'sequence_steps': ('WorkflowComposer', '', {'seq_name': 120, 'step_index': None, 'action': 80, 'target': 160, 'enabled': None, 'qual_pattern': 120, 'qual_window': 120}),
        'spools': ('Spools', '', {'name': 120, 'enabled': None, 'detectType': 60, 'target': 160, 'interval': None, 'timeout': None, 'action': 80}),
        'ocr_log': ('LiveOCR', 'ts', {'id': None, 'word_count': None, 'ts': None}),
    },
    'appmap': {
        'app': ('AppLearner', 'learned_ts', {'id': None, 'name': 120, 'exe': 100, 'title': 120, 'learned_ts': None}),
        'ui_element': ('AppLearner', '', {'id': None, 'app_id': None, 'kind': 60, 'name': 160, 'role': 60, 'acc_path': 120, 'menu_path': 160, 'shortcut': 80, 'class_nn': 80, 'hits': None}),
        'ui_region': ('WindowModel', 'built_ts', {'id': None, 'app_id': None, 'role': 60, 'name': 120, 'elements': None, 'confidence': None, 'built_ts': None}),
    },
    'bridge': {
        'tasks': ('DeepSeekBridge', 'created_at', {'id': 80, 'status': 40, 'created_at': None}),
        'events': ('DeepSeekBridge', 'at', {'id': None, 'at': None, 'kind': 60, 'subject': 80}),
    },
    'catalog': {
        'records': ('DeepSeekToolCatalog', 'updated_at', {'name': 160, 'kind': 40, 'description': 300, 'revision': None, 'updated_at': None}),
        'revisions': ('DeepSeekToolCatalog', 'at', {'name': 160, 'revision': None, 'at': None}),
    },
}


def _clean(value, limit=300):
    text = str(value or '')
    text = re.sub(r'(?i)sk-[a-z0-9_-]{12,}|Bearer\s+\S+', '[credential redacted]', text)
    return re.sub(r'[\x00-\x1f]', ' ', text)[:limit]


def _num(row, key):
    try:
        return float(row.get(key) or 0)
    except (TypeError, ValueError):
        return 0.0


def _date(value, now):
    if not value:
        return None
    try:
        stamp = datetime.fromisoformat(str(value).replace('Z', '+00:00'))
    except ValueError:
        try:
            stamp = datetime.strptime(str(value), '%Y%m%d%H%M%S')
        except ValueError:
            return None
    return stamp.replace(tzinfo=now.tzinfo) if stamp.tzinfo is None else stamp.astimezone(now.tzinfo)


def _identifier(value):
    return '"' + value.replace('"', '""') + '"'


class _Reader:
    def __init__(self, role, path, deadline, row_limit, cutoff, now):
        self.role, self.path = role, Path(path).resolve()
        self.deadline, self.row_limit, self.cutoff, self.now = deadline, row_limit, cutoff, now
        self.db = sqlite3.connect(self.path.as_uri() + '?mode=ro', uri=True, timeout=.5)
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA query_only=ON')
        self.db.execute('PRAGMA trusted_schema=OFF')
        self.db.set_progress_handler(lambda: int(time.perf_counter() >= deadline), 1000)
        self.tables = {r['name']: r['sql'] or '' for r in self.db.execute(
            "SELECT name,sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")}

    def inventory(self):
        page_size = self.db.execute('PRAGMA page_size').fetchone()[0]
        pages = self.db.execute('PRAGMA page_count').fetchone()[0]
        free = self.db.execute('PRAGMA freelist_count').fetchone()[0]
        return {'role': self.role, 'path': str(self.path), 'database_bytes': self.path.stat().st_size,
                'page_size': page_size, 'page_count': pages, 'freelist_pages': free,
                'reclaimable_free_page_bytes': free * page_size,
                'wal_bytes': Path(str(self.path) + '-wal').stat().st_size if Path(str(self.path) + '-wal').exists() else 0,
                'tables_present': sorted(self.tables)}

    def tail(self, table, spec):
        logical_table = table
        if self.role == 'appmap' and table == 'app' and 'appmap_app' in self.tables:
            table = 'appmap_app'
        module, time_key, requested = spec
        entry = {'role': self.role, 'table': logical_table, 'module': module, 'rows_examined': 0,
                 'rows_in_window': 0, 'rows_without_timestamp': 0, 'status': 'not_present',
                 'source_kind': 'observed', 'count_scope': 'bounded sample; not a whole-table count'}
        if table not in self.tables:
            return [], entry
        columns = {r['name']: dict(r) for r in self.db.execute('PRAGMA table_info(' + _identifier(table) + ')')}
        available = {name: cap for name, cap in requested.items() if name in columns}
        entry['columns_used'] = list(available)
        if not available:
            entry['status'] = 'schema_not_supported'
            return [], entry
        # Small cap for image metadata: b64_len occurs after the large embedded
        # b64 field, and reading even later scalar columns can traverse overflow
        # pages. Never request the image payload itself.
        limit = min(self.row_limit, 64) if table == 'snap_entry' else self.row_limit
        entry['row_limit'] = limit
        primary = [name for name, col in columns.items() if col['pk']]
        if len(primary) == 1 and 'INT' in columns[primary[0]]['type'].upper():
            order = _identifier(primary[0]) + ' DESC'
            entry['strategy'] = 'primary-key descending tail; mutable-row IDs are insertion order, not update recency'
        elif 'WITHOUT ROWID' not in self.tables[table].upper():
            order = '_rowid_ DESC'
            entry['strategy'] = 'rowid descending tail; configured dictionaries have no guaranteed recency order'
        else:
            order = ','.join(_identifier(name) for name in primary)
            entry['strategy'] = 'bounded primary-key aggregate staging; not a recent-row sample'
        expressions = [(_identifier(name) if cap is None else 'substr(' + _identifier(name) + ',1,' + str(cap) + ')')
                       + ' AS ' + _identifier(name) for name, cap in available.items()]
        try:
            query = 'SELECT ' + ','.join(expressions) + ' FROM ' + _identifier(table)
            query += (' ORDER BY ' + order if order else '') + ' LIMIT ?'
            fetched = [dict(row) for row in self.db.execute(query, (limit + 1,))]
        except sqlite3.DatabaseError as exc:
            entry.update(status='query_interrupted' if time.perf_counter() >= self.deadline else 'query_error', error=_clean(exc))
            return [], entry
        entry['row_limit_reached'] = len(fetched) > limit
        rows = fetched[:limit]
        entry['rows_examined'] = len(rows)
        timestamps = []
        recent = []
        for row in rows:
            for key, cap in available.items():
                if cap is not None:
                    row[key] = _clean(row[key], cap)
            stamp = _date(row.get(time_key), self.now) if time_key else None
            if stamp is not None:
                timestamps.append(stamp)
                if self.cutoff <= stamp <= self.now + timedelta(minutes=5):
                    recent.append(row)
            else:
                entry['rows_without_timestamp'] += 1
                recent.append(row)
        entry['rows_in_window'] = sum(self.cutoff <= stamp <= self.now + timedelta(minutes=5) for stamp in timestamps)
        entry['rows_used_in_analysis'] = len(recent)
        entry['observed_time_range'] = {'first': min(timestamps).isoformat(), 'last': max(timestamps).isoformat()} if timestamps else None
        entry['status'] = 'sampled' if entry['row_limit_reached'] else 'all_current_rows_examined'
        entry['recency_note'] = ('Rows without a usable timestamp are configured/lifetime observations, not evidence of recent use. '
                                 'Counters on mutable learner rows are lifetime totals, not counts during the requested window.')
        if table == 'snap_entry':
            entry['notes'] = 'At most64 image metadata rows; b64/bin_text/OCR/images are never selected. Prefix image_hash is not a full content hash.'
        return recent, entry


def _evidence(coverage, table, rows, counts=None, role='tracking'):
    sample = next((c for c in coverage if c['role'] == role and c['table'] == table), {})
    return {'source_kind': 'observed', 'database_role': role, 'table': table,
            'record_ids': [_clean(r.get('id', r.get('name', r.get('qa_id',
                str(r.get('seq_name', '')) + ':' + str(r.get('step_index', ''))))), 160) for r in rows[:12]],
            'counts': counts or {'matching_rows': len(rows)},
            'coverage_status': sample.get('status', 'unknown'), 'observed_time_range': sample.get('observed_time_range'),
            'scope': 'Lifetime counters on the bounded window-filtered sample' if table in ('usage_transition', 'usage_element', 'vs_element')
                     else sample.get('count_scope', 'bounded sample')}


def _finding(kind, title, module, evidence, actions, *, score=.6, validation=()):
    return {'id': hashlib.sha256((kind + title + json.dumps(evidence, sort_keys=True)).encode()).hexdigest()[:16],
            'kind': kind, 'title': _clean(title, 220), 'modules': [module],
            'source_kind': 'inference', 'confidence': {'score': round(score, 3),
                'level': 'high' if score >= .85 else 'medium' if score >= .6 else 'low',
                'meaning': 'Strength of this bounded evidence/recommendation, not verified automation success'},
            'evidence': evidence, 'recommended_actions': list(actions),
            'validation_required': list(validation), 'automation_ready': False}


def _derive(data, coverage, now):
    findings, associations = [], []
    get = lambda role, table: data.get((role, table), [])
    transitions = get('tracking', 'usage_transition')
    prefixes = defaultdict(list)
    for row in transitions:
        prefixes[row.get('prefix_hash') or row.get('prefix_text')].append(row)
    candidates = []
    for rows in prefixes.values():
        best = max(rows, key=lambda r: _num(r, 'support'))
        if _num(best, 'support') < 3:
            continue
        total = sum(_num(r, 'support') for r in rows)
        share = _num(best, 'support') / max(1, total)
        if share < .65:
            continue
        evidence = _evidence(coverage, 'usage_transition', rows, {'lifetime_support': _num(best, 'support'),
            'accepted_replays': _num(best, 'accepted'), 'share_among_sampled_alternatives': round(share, 3),
            'prefix': best.get('prefix_text', ''), 'next_action': best.get('next_token', '')})
        score = min(.84, .45 + .25 * share + min(.14, _num(best, 'support') / 100))
        item = _finding('workflow_candidate', 'Repeated continuation: ' + str(best.get('next_token', '')),
            'UsagePatternPredictor', evidence, [
                'Review the recorded prefix and continuation in Usage Predictor; accepted replay count is separate from repeat frequency.',
                'Locate every live target through FanBridge.Inspect/OCR/FindPattern, compose structured steps from fan_capabilities, preview and test the resulting workflow.'],
            score=score, validation=['Confirm the sequence still represents the intended task.', 'Do not replay stale raw coordinates or infer literal text from TYPE shape tokens.'])
        candidates.append(item)
    findings.extend(sorted(candidates, key=lambda f: f['evidence']['counts']['lifetime_support'], reverse=True)[:8])
    sequences = sorted(get('tracking', 'vs_sequence'), key=lambda r: _num(r, 'count'), reverse=True)
    for row in sequences[:4]:
        if _num(row, 'count') < 3:
            continue
        findings.append(_finding('workflow_candidate', 'Vision Scout repeated sequence (' + str(row.get('length', 0)) + ' steps)', 'VisionScout',
            _evidence(coverage, 'vs_sequence', [row], {'observed_repeat_count': _num(row, 'count'), 'length': row.get('length'), 'encoded_steps': _clean(row.get('steps'), 700)}),
            ['Review this saved sequence in Vision Scout and link its element tokens to certified live targets before promoting a native workflow.'],
            score=.65, validation=['Repeat count records a learner observation, not successful execution or user approval.']))
    shared = {int(r['id']): r for r in get('tracking', 'element') if r.get('id')}
    for table, count_key, module in [('usage_element', 'click_count', 'UsagePatternPredictor'), ('mouse_feature', 'clicks', 'MouseTracker')]:
        rows = get('tracking', table)
        linked = [r for r in rows if int(_num(r, 'element_id')) in shared and _num(r, 'element_id') > 0]
        associations.append({'kind': 'observed_element_id_reference', 'module': module, 'source_table': table,
            'target_table': 'element', 'linked_rows_in_sample': len(linked), 'sample_rows': len(rows),
            'links': [{'source_id': r.get('id'), 'element_id': r.get('element_id')} for r in linked[:12]],
            'scope': 'Same tracking database ID namespace only; App Learner IDs are not joined by numeric equality.'})
        unverified = [r for r in rows if _num(r, count_key) >= 3 and not _num(r, 'verified') and not _num(r, 'promoted') and not _num(r, 'element_id')]
        if unverified:
            findings.append(_finding('pattern_review', f'{len(unverified)} repeatedly clicked {module} candidates lack validated reusable targets', module,
                _evidence(coverage, table, unverified, {'candidate_count_in_sample': len(unverified), 'lifetime_clicks': sum(_num(r, count_key) for r in unverified)}),
                ['Inspect the live control and capture a narrowly cropped FindText pattern; certify useful targets and reject changing content/noise.',
                 'Prefer accessibility paths/menu commands when App Learner provides them; use verified patterns as a fallback.'],
                score=.7, validation=['Click frequency is not proof that an element is safe, stable or semantically correct.']))
    scout = get('tracking', 'vs_element')
    pending = [r for r in scout if _num(r, 'clicks') >= 3 and r.get('review_state', 'unreviewed') not in ('certified', 'rejected')]
    if pending:
        findings.append(_finding('pattern_review', 'Frequently accessed Vision Scout regions still need certification', 'VisionScout',
            _evidence(coverage, 'vs_element', pending, {'review_states': dict(Counter(str(r.get('review_state', 'unreviewed')) for r in pending))}),
            ['Use Vision Scout review to certify real controls and reject noise; preserve the distinction between frequency promotion and human certification.'], score=.75))
    snapshots = get('tracking', 'snap_entry')
    if snapshots:
        raw = sum(_num(r, 'image_bytes') for r in snapshots)
        embedded = sum(_num(r, 'b64_len') for r in snapshots)
        if embedded > 0:
            findings.append(_finding('storage_improvement', 'Snapshot rows duplicate image files with embedded base64', 'SnapshotEngine',
                _evidence(coverage, 'snap_entry', snapshots, {'sample_rows': len(snapshots), 'sample_image_file_bytes': int(raw),
                    'sample_embedded_base64_characters': int(embedded), 'embedded_to_image_ratio': round(embedded / raw, 3) if raw else None,
                    'global_extrapolation': 'Not performed; this is bounded recent metadata, not the entire database.'}),
                ['For new captures, keep the image file and durable path/format/hash metadata; disable duplicate embedded base64 storage.',
                 'Keep a compatibility fallback that loads legacy embedded base64 when the referenced file is unavailable.',
                 'Before compacting legacy rows, verify that each image file is readable and preserve recovery history/backups.'], score=.95,
                validation=['Never remove the only surviving image copy or discard learned semantic evidence merely to reduce size.']))
        hashes = defaultdict(list)
        for row in snapshots:
            if row.get('image_hash'):
                hashes[(row['image_hash'], row.get('image_bytes'), row.get('w'), row.get('h'))].append(row)
        repeated = [rows for rows in hashes.values() if len(rows) > 1]
        if repeated:
            findings.append(_finding('redundancy_candidate', 'Repeated snapshot prefix hashes suggest redundant captures', 'SnapshotRecovery',
                _evidence(coverage, 'snap_entry', [r for group in repeated for r in group], {'groups_in_sample': len(repeated),
                    'additional_rows_in_sample': sum(len(group)-1 for group in repeated),
                    'hash_semantics': 'SnapshotEngine hashes only the first4096 base64 characters, or the file path when base64 is absent.'}),
                ['Compare full file SHA-256 hashes before treating any frames as exact duplicates.',
                 'Use change detection and window exclusions to avoid repeated unchanged captures, while retaining transitions and task outcomes.'],
                score=.5, validation=['A shared stored image_hash does not prove identical images; different screenshots can have the same prefix.']))
    app_elements = get('appmap', 'ui_element')
    rich = [r for r in app_elements if r.get('acc_path') or r.get('menu_path') or r.get('shortcut') or r.get('class_nn')]
    if rich:
        findings.append(_finding('automation_improvement', 'App Learner already supplies reusable semantic locators', 'AppLearner',
            _evidence(coverage, 'ui_element', rich, {'semantic_locator_rows_in_sample': len(rich), 'sample_rows': len(app_elements)}, role='appmap'),
            ['Reuse current accessibility paths, menu commands and shortcuts in generated scripts before adding coordinate-only clicks.',
             'Refresh the application map after version/layout changes and confirm the control role/state before input.'], score=.85))
    apps = sorted(get('tracking', 'app'), key=lambda r: _num(r, 'total_ms'), reverse=True)
    if apps and _num(apps[0], 'activations') >= 5:
        top = apps[:5]
        findings.append(_finding('automation_priority', 'Concentrate workflow review on repeatedly activated applications', 'WindowTracker',
            _evidence(coverage, 'app', top, {'lifetime_focus_ms': sum(_num(r, 'total_ms') for r in top),
                'top_apps': [{'app_id': r.get('id'), 'exe': r.get('exe'), 'lifetime_activations': _num(r, 'activations')} for r in top]}),
            ['Start by reviewing Usage Predictor/Vision Scout sequences for these application IDs, then reuse App Learner locators and validated saved patterns.',
             'Use focus time to prioritize investigation; it does not measure repetitive work or prove that automation will save the same amount of time.'], score=.75))
    regions = [r for r in get('appmap', 'ui_region') if _num(r, 'confidence') >= .7 and r.get('role')]
    if regions:
        findings.append(_finding('layout_reuse', 'Stored window regions can narrow live OCR and element searches', 'WindowModel',
            _evidence(coverage, 'ui_region', regions, {'region_count_in_sample': len(regions),
                'stored_roles': dict(Counter(str(r.get('role')) for r in regions))}, role='appmap'),
            ['Use WindowModel editor/sidebar/toolbar roles to choose a smaller live capture; verify current region bounds before searching or clicking.',
             'Retain the stored model confidence and geometry origin; WindowModel classifications are inferred layout roles, not direct task instructions.'], score=.75))
    answers = get('tracking', 'study_answer_log')
    rejected = [r for r in answers if r.get('state') == 'rejected']
    candidates = [r for r in answers if r.get('state') == 'candidate']
    confirmed = [r for r in answers if r.get('state') in ('user-confirmed', 'source-confirmed', 'portal-confirmed')]
    if rejected or candidates:
        findings.append(_finding('verification_improvement', 'Study answers need verification before reuse', 'StudyAssistant',
            _evidence(coverage, 'study_answer_log', rejected + candidates, {'rejected_in_sample': len(rejected), 'candidate_in_sample': len(candidates),
                'confirmed_in_sample': len(confirmed), 'sample_api_cost': round(sum(_num(r, 'cost') for r in answers), 6)}),
            ['Reuse source/user/portal-confirmed answers with matching question/choice fingerprints; keep rejected answers as negative evidence.',
             'Verify candidate answers through exact math, relevant source evidence or portal feedback instead of trusting confidence alone.'], score=.85))
    concepts = sorted(get('tracking', 'study_concept'), key=lambda r: (_num(r, 'importance'), _num(r, 'seen')), reverse=True)
    if concepts:
        findings.append(_finding('knowledge_reuse', 'Preserve source-linked concepts while consolidating study material', 'StudyAssistant',
            _evidence(coverage, 'study_concept', concepts, {'concepts_in_sample': len(concepts),
                'relations_in_sample': len(get('tracking', 'study_concept_link')),
                'priority_concepts': [{'id': r.get('id'), 'name': r.get('name'), 'source_id': r.get('source_id'),
                                       'seen': _num(r, 'seen')} for r in concepts[:8]]}),
            ['Retrieve source passages for these concept IDs, retain the source/page links and confirmed answers, and consolidate repeated material into short sourced notes.',
             'Treat concept frequency and link weights as prioritization cues; they do not verify a definition or answer.'], score=.75))
    records = get('catalog', 'records')
    reusable = [r for r in records if r.get('kind') in ('script', 'pattern', 'workflow')]
    if reusable:
        findings.append(_finding('tool_reuse', 'The saved tool index already contains automation assets worth reusing', 'DeepSeekToolCatalog',
            _evidence(coverage, 'records', reusable, {'asset_kinds_in_sample': dict(Counter(str(r.get('kind')) for r in reusable)),
                'assets': [{'name': r.get('name'), 'kind': r.get('kind'), 'revision': r.get('revision')} for r in reusable[:8]]}, role='catalog'),
            ['Read indexed tool contracts/examples and latest source revisions before generating another script for the same task.',
             'Update usage metadata after a verified repair; index failures as negative evidence and keep stable task knowledge separate from raw execution logs.'], score=.8))
    tasks = get('bridge', 'tasks')
    failed = [r for r in tasks if r.get('status') == 'error']
    if failed:
        findings.append(_finding('failure_review', 'DeepSeek tasks have recorded failures requiring targeted repair', 'DeepSeekBridge',
            _evidence(coverage, 'tasks', failed, {'failed_tasks_in_sample': len(failed), 'status_counts_in_sample': dict(Counter(str(r.get('status', '')) for r in tasks))}, role='bridge'),
            ['Open the request/tool activity for these task IDs, classify provider, missing-worker, script-validation and stale-target errors, then fix the recurring cause.',
             'Retest the affected tool/workflow and index its working usage/example; do not mark failed tasks as learned successes.'], score=.9))
    steps = get('macro', 'sequence_steps')
    patterns = {r.get('name') for r in get('macro', 'patterns')}
    broken = [r for r in steps if r.get('action') in ('Find & Click', 'Find & DblClick', 'Find & TplClick', 'Find & RClick', 'Wait for Pattern', 'Wait Until Gone')
              and r.get('target') and r['target'] not in patterns]
    if broken:
        complete = next((c for c in coverage if c['role'] == 'macro' and c['table'] == 'patterns'), {}).get('status') == 'all_current_rows_examined'
        findings.append(_finding('workflow_repair', 'Saved workflows reference patterns absent from the inspected pattern catalog', 'WorkflowComposer',
            _evidence(coverage, 'sequence_steps', broken, {'step_count_in_sample': len(broken), 'pattern_inventory_complete': complete,
                'examples': [{'workflow': r.get('seq_name'), 'step': r.get('step_index'), 'pattern': r.get('target')} for r in broken[:8]]}, role='macro'),
            ['Read each workflow and the full pattern catalog; repair missing references by locating and recapturing the intended live control, then preview and test.'],
            score=.9 if complete else .45, validation=['Absence from a truncated pattern sample is not proof of a missing saved pattern.']))
    coarse = defaultdict(list)
    for row in get('macro', 'patterns'):
        if row.get('captureWindow'):
            coarse[row['captureWindow']].append(row['name'])
    associations.extend({'kind': 'pattern_window_context', 'source_kind': 'observed', 'window_label': title,
                         'pattern_names': names[:12], 'pattern_count_in_sample': len(names)} for title, names in list(coarse.items())[:12])
    return findings[:32], associations[:24]


def analyze(db_paths: Mapping[str, str | Path], *, days=30, row_limit=5000, max_seconds=20, now=None) -> dict:
    """Analyze metadata/learner aggregates without opening any store for writes.

    Work is bounded by rows/table and a SQLite VM deadline. The insertion tail
    can omit older mutable rows that were recently updated; coverage states this
    explicitly. Snapshot metadata has its own64-row cap to avoid overflow-page
    traversal costs. This function does not inspect filesystem image contents.
    """
    if not 1 <= days <= 3650 or not 1 <= row_limit <= 50000 or not 0 < max_seconds <= 120:
        raise ValueError('days must be1..3650, row_limit1..50000, max_seconds>0..120')
    now = now or datetime.now().astimezone()
    if now.tzinfo is None:
        now = now.astimezone()
    started = time.perf_counter()
    deadline, cutoff = started + max_seconds, now - timedelta(days=days)
    data, coverage, inventories, errors = {}, [], [], []
    for role, specifications in TABLES.items():
        path = db_paths.get(role)
        reader = None
        if path is None or not Path(path).is_file():
            coverage.extend({'role': role, 'table': table, 'module': spec[0], 'status': 'database_not_supplied' if path is None else 'database_missing', 'rows_examined': 0} for table, spec in specifications.items())
            continue
        if time.perf_counter() >= deadline:
            coverage.extend({'role': role, 'table': table, 'module': spec[0], 'status': 'time_budget_exhausted', 'rows_examined': 0} for table, spec in specifications.items())
            continue
        try:
            reader = _Reader(role, path, deadline, row_limit, cutoff, now)
            inventories.append(reader.inventory())
            for table, spec in specifications.items():
                if time.perf_counter() >= deadline:
                    coverage.append({'role': role, 'table': table, 'module': spec[0], 'status': 'time_budget_exhausted', 'rows_examined': 0})
                    continue
                rows, entry = reader.tail(table, spec)
                data[(role, table)] = rows
                coverage.append(entry)
            for table in sorted(reader.tables.keys() - specifications.keys()):
                coverage.append({'role': role, 'table': table, 'status': 'metadata_inventory_only', 'rows_examined': 0,
                                 'reason': 'No verified aggregate adapter; raw content is not scanned.'})
        except (sqlite3.DatabaseError, OSError) as exc:
            errors.append({'role': role, 'error': _clean(exc), 'path': str(path)})
            covered = {c['table'] for c in coverage if c['role'] == role}
            status = 'time_budget_exhausted' if time.perf_counter() >= deadline else 'database_open_error'
            coverage.extend({'role': role, 'table': table, 'module': spec[0], 'status': status, 'rows_examined': 0} for table, spec in specifications.items() if table not in covered)
        finally:
            if reader is not None:
                reader.db.close()
    findings, associations = _derive(data, coverage, now)
    module_summary = defaultdict(lambda: {'rows_examined': 0, 'rows_in_window': 0, 'tables': []})
    for entry in coverage:
        if entry.get('module'):
            summary = module_summary[entry['module']]
            summary['rows_examined'] += entry.get('rows_examined', 0)
            summary['rows_in_window'] += entry.get('rows_in_window', 0)
            summary['tables'].append(entry['role'] + '.' + entry['table'])
    report = {'schema_version': 1, 'generated_at': now.isoformat(), 'source_kind': 'observed_analysis_with_labelled_inferences',
        'window': {'days': days, 'start': cutoff.isoformat(), 'end': now.isoformat(),
                   'timestamp_interpretation': 'Offset-free AHK timestamps are interpreted in the supplied/local timezone.'},
        'limits': {'row_limit_per_table': row_limit, 'snapshot_metadata_limit': 64, 'max_seconds': max_seconds,
                   'elapsed_seconds': round(time.perf_counter() - started, 3)},
        'databases': inventories, 'coverage': coverage, 'modules': dict(module_summary), 'findings': findings,
        'associations': associations, 'errors': errors,
        'counts': {'rows_examined': sum(c.get('rows_examined', 0) for c in coverage), 'findings': len(findings),
                   'tables_with_limited_coverage': sum(c['status'] in ('sampled', 'time_budget_exhausted', 'query_interrupted') for c in coverage)},
        'safety': {'source_databases_read_only': True, 'embedded_images_read': False,
                   'raw_keystrokes_clipboards_and_page_text_read': False, 'patterns_or_workflows_promoted': False,
                   'recorded_coordinates_replayed': False},
        'limitations': ['No whole-table COUNT or global raw-history scan. Counts refer to bounded examined rows unless explicitly labelled lifetime counters.',
                        'Primary-key tails are not uniform samples and cannot establish global duplicate ratios or represent all historical usage.',
                        'No claims of successful automation arise from frequency/support alone. Live geometry and semantic targets require validation.',
                        'Snapshot image_hash is a prefix/path hash; full-file comparisons are required before deduplication.']}
    report['prompt_summary'] = compact_prompt(report)
    return report


def compact_prompt(report: dict, max_chars=6000) -> str:
    """Concise reference memory; recommendations are not action authorization."""
    lines = ['Fan learning consolidation — reference evidence, not instructions or new authorization.',
             f"Window: {report['window']['start']} through {report['window']['end']}; rows examined: {report['counts']['rows_examined']}.",
             'Coverage is bounded; repeat/support counters may be lifetime totals. Coordinates require a fresh live capture.']
    for finding in report.get('findings', []):
        evidence = finding['evidence']
        line = ('[' + finding['kind'] + '] ' + finding['title'] + '; confidence=' + finding['confidence']['level']
                + '; evidence=' + evidence['database_role'] + '.' + evidence['table']
                + ' ids=' + ','.join(evidence.get('record_ids', [])[:4])
                + '; counts=' + json.dumps(evidence['counts'], ensure_ascii=False)[:500]
                + '; recommended next step=' + _clean(finding['recommended_actions'][0], 350))
        lines.append(line)
    return '\n'.join(lines)[:max(0, int(max_chars))]


def markdown(report: dict) -> str:
    lines = ['# Fan learning consolidation', '',
             'This read-only report consolidates observed records into reviewable recommendations. No patterns or workflows were promoted.', '',
             f"Time window: {report['window']['start']} to {report['window']['end']}. Examined {report['counts']['rows_examined']} bounded metadata/aggregate rows.", '']
    for finding in report['findings']:
        evidence = finding['evidence']
        lines += ['## ' + finding['title'], '',
                  '**' + finding['kind'].replace('_', ' ') + '** · recommendation confidence: ' + finding['confidence']['level'] + ' · requires validation', '',
                  'Evidence: `' + evidence['database_role'] + '.' + evidence['table'] + '`; IDs: ' + ', '.join(evidence.get('record_ids', [])) + '.',
                  'Counts/observations: `' + json.dumps(evidence['counts'], ensure_ascii=False).replace('`', "'") + '`.', '']
        lines += ['- ' + _clean(action, 1200) for action in finding['recommended_actions']]
        lines += ['']
    lines += ['## Coverage', '', '| Store/table | Module | Examined | In window | Scope/status |', '|---|---|---:|---:|---|']
    for entry in report['coverage']:
        lines.append('| ' + entry['role'] + '.' + entry['table'] + ' | ' + entry.get('module', '') + ' | '
                     + str(entry.get('rows_examined', 0)) + ' | ' + str(entry.get('rows_in_window', 0)) + ' | ' + entry['status'] + ' |')
    lines += ['', '## Limits', ''] + ['- ' + text for text in report['limitations']]
    return '\n'.join(lines) + '\n'


def write_report(report: dict, output_dir: str | Path) -> dict[str, str]:
    """Write derived artifacts only; callers choose the permitted output folder."""
    directory = Path(output_dir)
    directory.mkdir(parents=True, exist_ok=True)
    paths = {'json': directory / 'insights.json', 'markdown': directory / 'insights.md',
             'prompt': directory / 'insights_prompt.txt'}
    paths['json'].write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    paths['markdown'].write_text(markdown(report), encoding='utf-8')
    paths['prompt'].write_text(compact_prompt(report) + '\n', encoding='utf-8')
    return {key: str(path.resolve()) for key, path in paths.items()}

