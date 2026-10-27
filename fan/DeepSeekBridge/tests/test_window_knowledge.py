import copy
import json
import sqlite3
import pytest
from bridge import window_knowledge as k, project_paths as p, library, workbench


def evidence():
    return {'ok': True, 'frame': {'exe': 'explorer.exe', 'exe_path': 'C:/Windows/explorer.exe', 'class': 'CabinetWClass',
            'title': 'Knowledge fixture', 'hwnd': 123, 'frame_id': 'frame-one', 'region': {'x': 0, 'y': 0, 'w': 900, 'h': 600}},
            'controls': [{'role': 'page tab', 'name': 'Home', 'selected': True, 'accessibility_path': '1/2', 'parent_path': '1',
                          'bounds': {'x': 10, 'y': 10, 'w': 90, 'h': 30}}],
            'tabs': [{'name': 'Home', 'selected': True}], 'ocr': {'text': 'Real fixture text ' * 800},
            'menus': [{'label': 'Open', 'parent': 'File', 'shortcut': 'Ctrl+O'}], 'image_path': 'retained.png',
            'coverage': {'complete_interface': False, 'gaps': ['other tabs unvisited']}}


def probe():
    result = evidence()
    for key in ('ocr', 'image_path', 'coverage'):
        result.pop(key)
    result['probe_only'] = True
    return result


def test_facts_are_scoped_related_and_deduplicated():
    key = k.remember(evidence(), 't', probe())
    k.remember(evidence(), 't', probe())
    facts = k.lookup(key, limit=100)
    assert facts['window']['observations'] == 1
    tab = next(f for f in facts['facts'] if f['kind'] == 'tab')
    assert tab['parent'] == '1' and tab['zone'] == 'top-left' and tab['data']['selected']
    assert len([f for f in facts['facts'] if f['kind'] == 'zone']) == 9
    assert any(f['data'].get('keys') == '!d' and not f['data']['verified_in_this_window'] for f in facts['facts'])
    assert any(f['kind'] == 'shortcut' and f['parent'] == 'File' for f in facts['facts'])
    assert 'historical' in facts['warning']


@pytest.mark.parametrize('random_value,reused', [(0, False), (.24999, False), (.25, True), (.9999, True)])
def test_policy_live_probe_and_75_25_boundary(random_value, reused):
    k.remember(evidence(), probe=probe())
    calls = []
    def invoke(name, args):
        calls.append(name)
        return copy.deepcopy(probe() if name.endswith('probe') else evidence())
    result = k.learn({'hwnd': 123}, invoke, 'run', rng=lambda: random_value)
    assert bool(result.get('reused')) == reused
    assert calls[0] == 'fan_window_probe'
    assert ('fan_window_survey' in calls) != reused
    if reused:
        assert result['zones']['created_before_text_analysis'] and len(result['zones']['zones']) == 9
        assert 'bounds' not in result['indexed_controls'][0]
        assert result['controls'][0]['bounds']  # live geometry only
        assert result['knowledge_reuse']['estimated_text_tokens_saved'] > 0
    else:
        assert result['knowledge_reuse']['estimated_text_tokens_saved'] == 0


@pytest.mark.parametrize('change', ['structure', 'tab', 'age', 'probe_only', 'browser', 'empty', 'explicit'])
def test_changed_or_incomplete_context_forces_fresh(change):
    source, live = evidence(), probe()
    if change == 'probe_only':
        source['probe_only'] = True
    key = k.remember(source, probe=probe())
    if change == 'structure':
        live['controls'][0]['name'] = 'Changed'
    if change == 'tab':
        live['controls'][0]['selected'] = False
    if change == 'browser':
        live['browser_context_unknown'] = True
    if change == 'empty':
        live['controls'] = []
    if change == 'age':
        with library.connect() as db:
            db.execute("UPDATE window_knowledge SET last_at='2020-01-01T00:00:00+00:00' WHERE id=?", (key,))
    result = k.learn({'hwnd': 123, 'activate_menu': change == 'explicit'},
                     lambda name, args: live if name.endswith('probe') else evidence(), rng=lambda: .99)
    assert not result.get('reused') and result['knowledge_reuse']['mode'] == 'fresh'


def test_failures_do_not_poison_knowledge_or_credit_savings():
    assert k.remember({'ok': False, **{'frame': evidence()['frame']}}) is None
    result = k.learn({}, lambda name, args: probe() if name.endswith('probe') else {'ok': False, 'error': 'capture failed'})
    assert not result['ok'] and k.stats()['uses'] == 0
    credit = k.record_use('run', 'x', 'reuse', 'larger payload', 1, {'large': 'x'*1000}, 'ref')
    assert credit['estimated_text_tokens_saved'] == 0


def test_filter_applies_to_totals_and_recent():
    key = k.remember(evidence(), probe=probe())
    k.record_use('run', key, 'reuse', 'window', 500, {}, 'frame')
    k.record_use('other', 'artifact:other', 'reuse', 'artifact', 600, {}, 'script')
    assert k.stats(query='Knowledge fixture')['uses'] == 1
    assert k.stats(query='unknown')['uses'] == 0
    assert k.stats(task_id='run')['uses'] == 1


def test_shortcut_checks_reinforce_scoped_evidence_and_survive_refresh():
    key = k.remember(evidence(), probe=probe())
    for verified in (True, False):
        k.observe('fan_window_shortcut', {'shortcut': 'address_bar'}, {'ok': True, 'action_performed': True, 'verified': verified, 'observation': probe()}, 'run')
    fresh = evidence()
    fresh['frame']['frame_id'] = 'frame-two'
    k.remember(fresh, probe=probe())
    data = next(f['data'] for f in k.lookup(key, limit=100)['facts'] if f['data'].get('id') == 'address_bar')
    assert data['verified_checks'] == 1 and data['unverified_checks'] == 1
    assert data['verified_in_this_window'] and not data['last_check_verified']


def test_relevance_terms_skip_generic_request_words():
    assert k.relevant_terms('Please learn the window then open VSCode deepseekrun project') == ['vscode', 'deepseekrun']


def test_sharing_is_persisted_and_destination_scoped(monkeypatch):
    assert not k.sharing()['approved']
    with pytest.raises(ValueError):
        k.require_sharing()
    k.sharing(True)
    monkeypatch.setenv('DEEPSEEK_BASE_URL', 'https://api.deepseek.com/v1')
    k.require_sharing()
    monkeypatch.setenv('DEEPSEEK_BASE_URL', 'https://other.example')
    with pytest.raises(ValueError):
        k.require_sharing()


def test_artifact_credit_only_for_preexisting_successful_tools():
    saved = library.save('Fixture.ahk', 'script', 'source ' * 1000, metadata={'sha256': 'abc'})
    assert k.artifact_use('ahk_script_run', {'name': 'Fixture.ahk'}, {'ok': True}, 't', '2000') is None
    credit = k.artifact_use('ahk_script_run', {'name': 'Fixture.ahk'}, {'ok': True}, 't', '9999')
    assert credit['estimated_text_tokens_saved'] > 0 and credit['source_ref'] == 'Fixture.ahk@1'
    assert k.artifact_use('ahk_script_run', {'name': 'Fixture.ahk'}, {'ok': False}) is None


def test_desktop_metadata_index_resumes_without_copying_source(tmp_path):
    root = tmp_path / 'Desktop'
    project = root / 'Example'
    project.mkdir(parents=True)
    (project / 'package.json').write_text('PRIVATE SOURCE CONTENT')
    (project / 'code.ahk').write_text('PRIVATE SOURCE CONTENT')
    excluded = project / 'node_modules'
    excluded.mkdir()
    (excluded / 'must-not-index.txt').write_text('x')
    for _ in range(30):
        outcome = p.advance(root, limit=1, budget=1)
        if outcome['complete']:
            break
    assert outcome['complete']
    matches = p.search('Example')['paths']
    assert any(row['kind'] == 'project' and row['path'] == str(project) for row in matches)
    assert not p.search('must-not-index')['paths']
    assert 'PRIVATE SOURCE CONTENT' not in json.dumps(matches)
    assert p.stats()['scan']['complete']


def test_report_contains_evidence_and_estimates_but_removes_secrets(tmp_path):
    database = tmp_path / 'events.sqlite'
    with sqlite3.connect(database) as db:
        db.executescript('CREATE TABLE tasks(id,prompt,status,response,created_at); CREATE TABLE events(id,at,kind,subject,payload);')
        db.execute("INSERT INTO tasks VALUES('run','Do a fixture','error','','today')")
        db.execute('INSERT INTO events VALUES(1,?,?,?,?)', ('today', 'agent_error', 'run', json.dumps({'api_key': 'SECRET', 'text': 'failure', 'data_url': 'data:image/png;base64,AA=='})))
    k.record_use('run', 'ref', 'reuse', 'known', 100, {}, 'fixture@1')
    text = workbench.report(database, 'run')
    assert 'SECRET' not in text and 'AA==' not in text
    assert 'failure' in text and 'fixture@1' in text and 'not measured billing' in text
    with pytest.raises(ValueError):
        workbench.report(database, 'missing')
