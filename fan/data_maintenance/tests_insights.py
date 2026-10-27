"""Use small isolated databases; never inspect the user's large live stores."""
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import sqlite3

import pytest

spec = importlib.util.spec_from_file_location('fan_insights', Path(__file__).with_name('insights.py'))
insights = importlib.util.module_from_spec(spec)
spec.loader.exec_module(insights)
NOW = datetime(2026, 10, 12, 10, tzinfo=timezone.utc)
RECENT = '2026-10-11 10:00:00'
OLD = '2024-01-01 10:00:00'


def database(tmp_path, name, statements):
    path = tmp_path / name
    with sqlite3.connect(path) as db:
        for sql, args in statements:
            db.execute(sql, args)
    return path


def test_real_schema_consolidates_actionable_insights_without_promoting(tmp_path):
    tracking = database(tmp_path, 'tracking.db', [
        ('CREATE TABLE usage_transition(id INTEGER PRIMARY KEY,prefix_hash TEXT,prefix_text TEXT,next_token TEXT,support INTEGER,accepted INTEGER,last_ts TEXT)', ()),
        ('INSERT INTO usage_transition VALUES(1,?,?,?,?,?,?)', ('prefix', 'APP:chrome > CLICK:E2:L', 'KEY:{Tab}', 20, 0, RECENT)),
        ('INSERT INTO usage_transition VALUES(2,?,?,?,?,?,?)', ('prefix', 'APP:chrome > CLICK:E2:L', 'KEY:{Escape}', 1, 0, RECENT)),
        ('CREATE TABLE usage_element(id INTEGER PRIMARY KEY,win_id INTEGER,click_count INTEGER,verified INTEGER,promoted INTEGER,element_id INTEGER,last_ts TEXT)', ()),
        ('INSERT INTO usage_element VALUES(1,3,12,0,0,0,?)', (RECENT,)),
        ('INSERT INTO usage_element VALUES(2,3,7,1,1,8,?)', (RECENT,)),
        ('CREATE TABLE element(id INTEGER PRIMARY KEY,win_id INTEGER,name TEXT,hits INTEGER,updated_ts TEXT)', ()),
        ('INSERT INTO element VALUES(8,3,?,7,?)', ('Answer field', RECENT)),
        ('CREATE TABLE snap_entry(id INTEGER PRIMARY KEY,win_id INTEGER,ts TEXT,image_bytes INTEGER,image_hash TEXT,b64 TEXT,b64_len INTEGER,w INTEGER,h INTEGER)', ()),
        ('INSERT INTO snap_entry VALUES(1,3,?,300,?, ?,400,100,100)', (RECENT, 'same-prefix', 'IMAGE_CONTENT_SENTINEL')),
        ('INSERT INTO snap_entry VALUES(2,3,?,300,?, ?,400,100,100)', (RECENT, 'same-prefix', 'DIFFERENT_IMAGE_SENTINEL')),
        ('CREATE TABLE study_answer_log(id INTEGER PRIMARY KEY,qa_id INTEGER,state TEXT,confidence REAL,cost REAL,ts TEXT)', ()),
        ('INSERT INTO study_answer_log VALUES(1,20,?,.95,.002,?)', ('candidate', RECENT)),
        ('INSERT INTO study_answer_log VALUES(2,20,?,1,0,?)', ('portal-confirmed', RECENT)),
    ])
    appmap = database(tmp_path, 'appmap.db', [
        ('CREATE TABLE ui_element(id INTEGER PRIMARY KEY,app_id INTEGER,name TEXT,acc_path TEXT,shortcut TEXT)', ()),
        ('INSERT INTO ui_element VALUES(7,8,?,?,?)', ('Save', '1,3,4', 'Ctrl+S')),
    ])
    macro = database(tmp_path, 'macro.db', [
        ('CREATE TABLE patterns(name TEXT PRIMARY KEY,desc TEXT,captureWindow TEXT)', ()),
        ('INSERT INTO patterns VALUES(?,?,?)', ('Existing', 'Known button', 'Browser')),
        ('CREATE TABLE sequence_steps(seq_name TEXT,step_index INTEGER,action TEXT,target TEXT)', ()),
        ('INSERT INTO sequence_steps VALUES(?,?,?,?)', ('Enter answer', 1, 'Find & Click', 'Missing')),
    ])
    bridge = database(tmp_path, 'bridge.sqlite3', [
        ('CREATE TABLE tasks(id TEXT PRIMARY KEY,status TEXT,created_at TEXT,prompt TEXT,response TEXT)', ()),
        ('INSERT INTO tasks VALUES(?,?,?,?,?)', ('failed-task', 'error', RECENT, 'USER_PROMPT_SENTINEL', 'PROVIDER_OUTPUT_SENTINEL')),
    ])
    paths = {'tracking': tracking, 'macro': macro, 'appmap': appmap, 'bridge': bridge}
    before = {role: path.read_bytes() for role, path in paths.items()}
    report = insights.analyze(paths, now=NOW)
    kinds = {f['kind'] for f in report['findings']}
    assert {'workflow_candidate', 'pattern_review', 'storage_improvement', 'redundancy_candidate',
            'automation_improvement', 'verification_improvement', 'failure_review', 'workflow_repair'} <= kinds
    storage = next(f for f in report['findings'] if f['kind'] == 'storage_improvement')
    assert storage['evidence']['counts']['sample_embedded_base64_characters'] == 800
    redundancy = next(f for f in report['findings'] if f['kind'] == 'redundancy_candidate')
    assert 'first4096' in redundancy['evidence']['counts']['hash_semantics']
    assert any('SHA-256' in action for action in redundancy['recommended_actions'])
    assert all(not f['automation_ready'] and f['source_kind'] == 'inference' for f in report['findings'])
    assert next(a for a in report['associations'] if a['source_table'] == 'usage_element')['linked_rows_in_sample'] == 1
    encoded = json.dumps(report)
    assert 'IMAGE_CONTENT_SENTINEL' not in encoded and 'DIFFERENT_IMAGE_SENTINEL' not in encoded
    assert 'USER_PROMPT_SENTINEL' not in encoded and 'PROVIDER_OUTPUT_SENTINEL' not in encoded
    assert before == {role: path.read_bytes() for role, path in paths.items()}


def test_recent_id_tail_has_explicit_partial_coverage_and_no_full_history_claim(tmp_path):
    path = database(tmp_path, 'tracking.db', [
        ('CREATE TABLE usage_event(id INTEGER PRIMARY KEY,ts TEXT,kind TEXT,automated INTEGER,data TEXT)', ()),
        *[('INSERT INTO usage_event VALUES(?,?,?,?,?)', (i, OLD if i <= 100 else RECENT, 'CLICK', 0, 'RAW_DATA_SENTINEL')) for i in range(1, 111)],
    ])
    report = insights.analyze({'tracking': path}, now=NOW, row_limit=5)
    coverage = next(c for c in report['coverage'] if c['table'] == 'usage_event')
    assert coverage['rows_examined'] == 5 and coverage['rows_in_window'] == 5
    assert coverage['status'] == 'sampled' and coverage['row_limit_reached']
    assert 'not a whole-table count' in coverage['count_scope']
    assert 'RAW_DATA_SENTINEL' not in json.dumps(report)
    assert report['counts']['rows_examined'] == 5


def test_snapshot_metadata_has_separate_small_cap_and_weak_hash_warning(tmp_path):
    path = database(tmp_path, 'tracking.db', [
        ('CREATE TABLE snap_entry(id INTEGER PRIMARY KEY,ts TEXT,image_bytes INTEGER,image_hash TEXT,b64_len INTEGER)', ()),
        *[('INSERT INTO snap_entry VALUES(?,?,?,?,?)', (i, RECENT, 300, 'weakprefix', 400)) for i in range(1, 101)],
    ])
    report = insights.analyze({'tracking': path}, now=NOW, row_limit=50000)
    coverage = next(c for c in report['coverage'] if c['table'] == 'snap_entry')
    assert coverage['rows_examined'] == 64 and coverage['status'] == 'sampled'
    assert report['limits']['snapshot_metadata_limit'] == 64
    assert 'not a full content hash' in coverage['notes']


def test_transition_share_counts_low_support_alternatives_and_respects_recent_window(tmp_path):
    path = database(tmp_path, 'tracking.db', [
        ('CREATE TABLE usage_transition(id INTEGER PRIMARY KEY,prefix_hash TEXT,next_token TEXT,support INTEGER,last_ts TEXT)', ()),
        ('INSERT INTO usage_transition VALUES(1,?,?,5,?)', ('same', 'dominant', RECENT)),
        ('INSERT INTO usage_transition VALUES(2,?,?,2,?)', ('same', 'small-alternative', RECENT)),
        ('INSERT INTO usage_transition VALUES(3,?,?,1,?)', ('same', 'other-alternative', RECENT)),
        ('INSERT INTO usage_transition VALUES(4,?,?,100,?)', ('old', 'stale', OLD)),
    ])
    report = insights.analyze({'tracking': path}, now=NOW)
    assert not [f for f in report['findings'] if f['kind'] == 'workflow_candidate']
    coverage = next(c for c in report['coverage'] if c['table'] == 'usage_transition')
    assert coverage['rows_examined'] == 4 and coverage['rows_in_window'] == 3


def test_frequency_never_revives_rejected_scout_regions(tmp_path):
    path = database(tmp_path, 'tracking.db', [
        ('CREATE TABLE vs_element(id INTEGER PRIMARY KEY,clicks INTEGER,review_state TEXT,last_seen TEXT)', ()),
        ('INSERT INTO vs_element VALUES(1,999,?,?)', ('rejected', RECENT)),
        ('INSERT INTO vs_element VALUES(2,10,?,?)', ('certified', RECENT)),
    ])
    report = insights.analyze({'tracking': path}, now=NOW)
    assert not [f for f in report['findings'] if f['kind'] == 'pattern_review']


def test_partial_pattern_inventory_does_not_assert_reference_is_missing(tmp_path):
    path = database(tmp_path, 'macro.db', [
        ('CREATE TABLE patterns(name TEXT PRIMARY KEY)', ()),
        ('INSERT INTO patterns VALUES(?)', ('Actually exists but old',)),
        ('INSERT INTO patterns VALUES(?)', ('Latest',)),
        ('CREATE TABLE sequence_steps(seq_name TEXT,step_index INTEGER,action TEXT,target TEXT)', ()),
        ('INSERT INTO sequence_steps VALUES(?,?,?,?)', ('Existing workflow', 2, 'Find & Click', 'Actually exists but old')),
    ])
    report = insights.analyze({'macro': path}, now=NOW, row_limit=1)
    finding = next(f for f in report['findings'] if f['kind'] == 'workflow_repair')
    assert finding['confidence']['level'] == 'low'
    assert not finding['evidence']['counts']['pattern_inventory_complete']
    assert finding['validation_required']


def test_missing_stores_schema_variants_and_budget_produce_honest_coverage(tmp_path):
    path = database(tmp_path, 'tracking.db', [('CREATE TABLE unknown_raw_store(id INTEGER PRIMARY KEY,content TEXT)', ())])
    report = insights.analyze({'tracking': path}, now=NOW, max_seconds=.000001)
    assert not report['findings']
    assert all(c['status'] in {'time_budget_exhausted', 'metadata_inventory_only'} for c in report['coverage'] if c['role'] == 'tracking')
    assert any(c['status'] == 'database_not_supplied' and c['role'] == 'macro' for c in report['coverage'])
    assert all(c.get('rows_examined', 0) == 0 for c in report['coverage'])


def test_report_artifacts_and_future_prompt_are_compact_reviewable_reference_data(tmp_path):
    report = insights.analyze({}, now=NOW)
    paths = insights.write_report(report, tmp_path / 'derived')
    assert set(paths) == {'json', 'markdown', 'prompt'}
    assert json.loads(Path(paths['json']).read_text(encoding='utf-8'))['safety']['source_databases_read_only']
    assert 'Coverage' in Path(paths['markdown']).read_text(encoding='utf-8')
    assert 'not instructions or new authorization' in Path(paths['prompt']).read_text(encoding='utf-8')
    assert len(insights.compact_prompt(report, max_chars=100)) <= 100


def test_actual_macro_spool_and_appmap_layout_schema_variants_keep_configured_scope(tmp_path):
    macro = database(tmp_path, 'macro.db', [
        ('CREATE TABLE spools(name TEXT PRIMARY KEY,enabled INTEGER,region TEXT,regionCoords TEXT,detectType TEXT,target TEXT,interval INTEGER,condition TEXT,action TEXT,actionTarget TEXT,extractOCR INTEGER,ocrVar TEXT,autoComplete INTEGER,completion TEXT,completionTarget TEXT,timeout INTEGER,mode TEXT,cooldown INTEGER,notifTime INTEGER)', ()),
        ('INSERT INTO spools(name,enabled,detectType,target,interval,action,timeout) VALUES(?,?,?,?,?,?,?)', ('Watch submit', 0, 'Pattern Match', 'Submit', 500, 'Show Notification', 5000)),
    ])
    appmap = database(tmp_path, 'appmap.db', [
        ('CREATE TABLE ui_region(id INTEGER PRIMARY KEY,app_id INTEGER,parent_id INTEGER,depth INTEGER,role TEXT,name TEXT,rel_x REAL,rel_y REAL,rel_w REAL,rel_h REAL,elements INTEGER,confidence REAL,evidence TEXT,built_ts TEXT)', ()),
        ('INSERT INTO ui_region(id,app_id,role,name,elements,confidence,built_ts) VALUES(?,?,?,?,?,?,?)', (1, 4, 'editor', 'Main editor', 30, .8, RECENT)),
    ])
    report = insights.analyze({'macro': macro, 'appmap': appmap}, now=NOW)
    spool = next(c for c in report['coverage'] if c['table'] == 'spools')
    assert spool['rows_examined'] == 1 and spool['rows_without_timestamp'] == 1
    assert spool['rows_in_window'] == 0 and spool['rows_used_in_analysis'] == 1
    assert report['modules']['Spools']['rows_examined'] == 1
    assert 'interval' in spool['columns_used'] and 'detectType' in spool['columns_used']
    assert any(f['kind'] == 'layout_reuse' and f['modules'] == ['WindowModel'] for f in report['findings'])
    with sqlite3.connect(macro) as db:
        assert db.execute('SELECT enabled FROM spools').fetchone()[0] == 0


def test_composite_aggregate_without_rowid_is_staged_by_primary_key(tmp_path):
    path = database(tmp_path, 'tracking.db', [
        ('CREATE TABLE hotkey_stat(win_id INTEGER,combo TEXT,count INTEGER,last_ts TEXT,PRIMARY KEY(win_id,combo)) WITHOUT ROWID', ()),
        ('INSERT INTO hotkey_stat VALUES(?,?,?,?)', (2, '^c', 30, RECENT)),
        ('INSERT INTO hotkey_stat VALUES(?,?,?,?)', (2, '^v', 28, RECENT)),
    ])
    report = insights.analyze({'tracking': path}, now=NOW, row_limit=1)
    coverage = next(c for c in report['coverage'] if c['table'] == 'hotkey_stat')
    assert coverage['rows_examined'] == 1 and coverage['row_limit_reached']
    assert 'aggregate staging' in coverage['strategy']


def test_analysis_never_selects_heavy_or_raw_sensitive_content_columns(tmp_path, monkeypatch):
    path = database(tmp_path, 'tracking.db', [
        ('CREATE TABLE snap_entry(id INTEGER PRIMARY KEY,ts TEXT,image_bytes INTEGER,b64 TEXT,b64_len INTEGER,bin_text TEXT,ocr_text TEXT)', ()),
        ('INSERT INTO snap_entry VALUES(1,?,100,?,140,?,?)', (RECENT, 'BASE64_SENTINEL', 'BINARY_PATTERN_SENTINEL', 'OCR_SENTINEL')),
        ('CREATE TABLE key_snapshot(id INTEGER PRIMARY KEY,start_ts TEXT,keystrokes INTEGER,text_typed TEXT,raw_stream TEXT)', ()),
        ('INSERT INTO key_snapshot VALUES(1,?,10,?,?)', (RECENT, 'TYPED_SENTINEL', 'RAW_KEYS_SENTINEL')),
    ])
    real_connect = sqlite3.connect
    forbidden = {'b64', 'bin_text', 'ocr_text', 'text_typed', 'raw_stream', 'content', 'question'}
    attempted = []
    def guarded_connect(*args, **kwargs):
        db = real_connect(*args, **kwargs)
        def authorize(action, table, column, *_):
            if action == sqlite3.SQLITE_READ and column in forbidden:
                attempted.append((table, column))
                return sqlite3.SQLITE_DENY
            return sqlite3.SQLITE_OK
        db.set_authorizer(authorize)
        return db
    monkeypatch.setattr(insights.sqlite3, 'connect', guarded_connect)
    report = insights.analyze({'tracking': path}, now=NOW)
    assert not attempted and not report['errors']
    assert report['counts']['rows_examined'] == 2


def test_compact_semantic_knowledge_retains_source_ids_and_saved_tool_revisions(tmp_path):
    tracking = database(tmp_path, 'tracking.db', [
        ('CREATE TABLE study_concept(id INTEGER PRIMARY KEY,name TEXT,source_id INTEGER,seen INTEGER,importance INTEGER,last_ts TEXT,definition TEXT)', ()),
        ('INSERT INTO study_concept VALUES(1,?,4,12,3,?,?)', ('Rational exponent', RECENT, 'FULL_DEFINITION_SENTINEL')),
        ('CREATE TABLE study_concept_link(id INTEGER PRIMARY KEY,from_id INTEGER,to_id INTEGER,relation TEXT,weight INTEGER)', ()),
        ('INSERT INTO study_concept_link VALUES(1,1,2,?,3)', ('simplifies_to',)),
    ])
    catalog = database(tmp_path, 'catalog.sqlite3', [
        ('CREATE TABLE records(name TEXT PRIMARY KEY,kind TEXT,description TEXT,revision INTEGER,updated_at TEXT,content TEXT)', ()),
        ('INSERT INTO records VALUES(?,?,?,?,?,?)', ('map_answer.ahk', 'script', 'Map a live answer field', 3, RECENT, 'FULL_SOURCE_SENTINEL')),
    ])
    report = insights.analyze({'tracking': tracking, 'catalog': catalog}, now=NOW)
    knowledge = next(f for f in report['findings'] if f['kind'] == 'knowledge_reuse')
    assert knowledge['evidence']['counts']['priority_concepts'][0]['source_id'] == 4
    assert knowledge['evidence']['counts']['relations_in_sample'] == 1
    reuse = next(f for f in report['findings'] if f['kind'] == 'tool_reuse')
    assert reuse['evidence']['counts']['assets'][0] == {'name': 'map_answer.ahk', 'kind': 'script', 'revision': 3}
    assert 'FULL_DEFINITION_SENTINEL' not in json.dumps(report) and 'FULL_SOURCE_SENTINEL' not in json.dumps(report)
    assert 'map_answer.ahk' in report['prompt_summary']


@pytest.mark.parametrize('arguments', [{'row_limit': 50001}, {'days': 0}, {'max_seconds': 121}, {'max_seconds': 0}])
def test_analysis_limits_validate_before_opening_a_database(arguments):
    with pytest.raises(ValueError):
        insights.analyze({}, **arguments)
