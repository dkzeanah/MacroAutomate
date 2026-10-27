import json
import sqlite3
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import pytest
from jsonschema import ValidationError
from bridge import chains, explorer_usage, exploration, library, reuse, units


def test_pause_holds_next_boundary_resume_releases_and_cancel_still_stops(tmp_path):
    database = tmp_path / 'control.db'
    with sqlite3.connect(database) as db:
        db.execute('CREATE TABLE tasks(id TEXT PRIMARY KEY,status TEXT)')
        db.execute("INSERT INTO tasks VALUES('task','running')")
    chains.control(database, 'task', True)
    passed = threading.Event()
    with ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(lambda: (chains.wait_ready(database,'task',time.monotonic()+3),passed.set()))
        assert not passed.wait(.15)
        chains.control(database, 'task', False)
        future.result(timeout=2)
        assert passed.is_set()
    chains.control(database,'task',True)
    with sqlite3.connect(database) as db:
        db.execute("UPDATE tasks SET status='cancelled'")
    with pytest.raises(ValueError,match='cancelled'):
        chains.wait_ready(database,'task')
    assert not chains.control(database,'task')['paused']
    with pytest.raises(ValueError,match='already stopped'):
        chains.control(database,'task',False)


def test_pause_deadline_does_not_execute_next_action(tmp_path):
    database = tmp_path/'control.db'
    with sqlite3.connect(database) as db:
        db.execute('CREATE TABLE tasks(id TEXT PRIMARY KEY,status TEXT)')
        db.execute("INSERT INTO tasks VALUES('task','running')")
    chains.control(database,'task',True)
    with pytest.raises(ValueError,match='no next action'):
        chains.wait_ready(database,'task',time.monotonic()-.1)


def test_paused_gateway_and_native_input_are_held_before_dispatch(tmp_path,monkeypatch):
    from fastapi import HTTPException
    from bridge import gateway
    database=tmp_path/'gate.db'
    with sqlite3.connect(database) as db:
        db.execute('CREATE TABLE tasks(id TEXT PRIMARY KEY,status TEXT)')
        db.execute("INSERT INTO tasks VALUES('task','running')")
    monkeypatch.setattr(gateway,'DB',database)
    monkeypatch.setattr(gateway,'db_write',lambda *a:None)
    monkeypatch.setattr(gateway,'_tools',lambda *a:pytest.fail('Paused input must never dispatch'))
    chains.control(database,'task',True)
    with pytest.raises(HTTPException) as error:
        gateway.tools('mouse_click',{'x':10,'y':20},'test-local-token','task')
    assert error.value.status_code==409 and not chains.snapshot(database,'task')['steps']
    marker=gateway.NativeObservation(task_id='task',family='Input',method='Click',detail={'interaction':True,'x':10,'y':20})
    assert gateway.native_observation(marker,'test-local-token')['paused']
    assert not chains.snapshot(database,'task')['steps']
    chains.control(database,'task',False)
    assert gateway.native_observation(marker,'test-local-token')['ok']
    assert len(chains.snapshot(database,'task')['steps'])==1
    with sqlite3.connect(database) as db:
        db.execute("UPDATE tasks SET status='cancelled'")
    with pytest.raises(HTTPException) as error:
        gateway.native_observation(marker,'test-local-token')
    assert error.value.status_code==409


def test_chain_numbers_are_atomic_and_parents_are_task_scoped(tmp_path):
    db = tmp_path / 'trace.db'
    root = chains.begin(db, 'task', 'daa_unit_run', {}, 'pre_llm')
    with chains.scope(root):
        child = chains.begin(db, 'task', 'ahk_script_run', {'name': 'owned.ahk'})
    chains.finish(db, child, {'ok': True, 'status': 'complete', 'exit_code': 0})
    with ThreadPoolExecutor(max_workers=6) as pool:
        list(pool.map(lambda _: chains.begin(db, 'task', 'fan_window_probe', {}), range(12)))
    graph = chains.snapshot(db, 'task')
    assert [s['number'] for s in graph['steps']] == list(range(1, 15))
    assert graph['steps'][1]['parent_id'] == root['id']
    assert graph['steps'][1]['origin'] == 'tool:daa_unit_run'
    assert graph['steps'][1]['status'] == 'executed'  # exit 0 alone is not semantic proof
    with pytest.raises(ValueError, match='parent'):
        chains.begin(db, 'other', 'fan_ocr', {}, parent=root['id'])


def test_chain_limit_refuses_next_tool_and_local_budget_can_extend(tmp_path):
    db = tmp_path / 'trace.db'
    chains.begin(db, 'task', 'fan_window_probe', {})
    chains.configure(db, 'task', 1)
    with pytest.raises(ValueError, match='no further tool'):
        chains.begin(db, 'task', 'mouse_click', {'x': 1, 'y': 2})
    assert chains.snapshot(db, 'task')['chain']['step_count'] == 1
    chains.configure(db, 'task', 3)
    assert chains.begin(db, 'task', 'fan_ocr', {})['number'] == 2


def test_chain_does_not_copy_source_or_credentials(tmp_path):
    db = tmp_path / 'trace.db'
    step = chains.begin(db, 'task', 'ahk_script_write', {'source': 'private source', 'api_token': 'secret'})
    chains.finish(db, step, {'ok': True, 'verified': True, 'base64': 'pixels'})
    text = json.dumps(chains.snapshot(db, 'task'))
    assert 'private source' not in text and '"secret"' not in text and 'pixels' not in text


def script_unit():
    library.save('Owned.ahk', 'script', '#Requires AutoHotkey v2.0\nExitApp(0)')
    return units.save('Safe lesson', [{'id': 'run', 'tool': 'ahk_script_run',
        'arguments': {'name': 'Owned.ahk', 'wait': True, 'inputs': {'hwnd': {'$input': 'hwnd'}}},
        'expect': {'exit_code': 0, 'stdout': 'verified 42'}}],
        {'type': 'object', 'required': ['hwnd'], 'properties': {'hwnd': {'type': 'integer'}}, 'additionalProperties': False})


def test_local_unit_preserves_types_checks_results_and_never_rewrites():
    script_unit()
    calls = []
    def invoke(name, args):
        calls.append((name, args))
        return {'ok': True, 'status': 'complete', 'exit_code': 0, 'stdout': 'verified 42'}
    result = units.run('Safe lesson', {'hwnd': 123}, invoke)
    assert result['verified'] and result['llm_calls'] == 0
    assert calls[0][1]['inputs']['hwnd'] == 123
    assert library.get('Owned.ahk')['revision'] == 1
    plan = reuse.direct_saved_plan('run learned unit Safe lesson inputs {"hwnd":123}')
    assert plan['name'] == 'daa_unit_run' and plan['arguments']['inputs']['hwnd'] == 123
    with pytest.raises(ValidationError):
        units.run('Safe lesson', {'hwnd': 'guess'}, invoke)


def test_changed_script_and_wrong_postcondition_stop_unit_before_later_steps():
    script_unit()
    failed = units.run('Safe lesson', {'hwnd': 1}, lambda *a: {'ok': True, 'exit_code': 0, 'stdout': 'not checked'})
    assert not failed['ok'] and failed['failed_step'] == 'run'
    library.save('Owned.ahk', 'script', 'ExitApp(2)')
    result = units.run('Safe lesson', {'hwnd': 1}, lambda *a: pytest.fail('Changed pinned source must not execute'))
    assert not result['ok'] and 'revision changed' in result['error']


def test_unit_output_reference_is_structured_not_eval():
    assert units.resolve({'hwnd': {'$result': 'probe.frame.hwnd'}, 'literal': '$(not code)'}, {},
                         {'probe': {'frame': {'hwnd': 22}}}) == {'hwnd': 22, 'literal': '$(not code)'}
    with pytest.raises(ValueError):
        units.save('recursive', [{'tool': 'daa_unit_run', 'arguments': {'name': 'recursive'}}])


def test_explorer_dwell_is_capped_nonidle_and_ambiguous_tabs_not_double_counted():
    def sample(tick, paths, idle=0):
        return {'session': 'native', 'tick': tick, 'foreground': 42, 'idle_ms': idle,
                'windows': [{'hwnd': 42, 'path': path, 'selected': [path + '\\file.py']} for path in paths]}
    explorer_usage.ingest(sample(1000, ['C:\\Project']))
    explorer_usage.ingest(sample(3000, ['C:\\Project']))
    assert explorer_usage.ingest(sample(3000, ['C:\\Project']))['duplicate']
    explorer_usage.ingest(sample(100000, ['C:\\Project']))
    explorer_usage.ingest(sample(102000, ['C:\\Project', 'C:\\Other']))
    explorer_usage.ingest(sample(104000, ['C:\\Project'], idle=90000))
    rows = {r['path']: r for r in explorer_usage.ranked()['paths']}
    assert rows['C:\\Project']['active_ms'] == 5000
    assert rows['C:\\Project\\file.py']['active_ms'] == 0
    assert rows['C:\\Other']['active_ms'] == 0


def test_menu_exploration_branches_then_returns_without_leaf_commands():
    calls = []
    def invoke(name, args):
        calls.append((name, args))
        if name == 'fan_window_probe':
            return {'ok': True, 'frame': {'foreground': True}, 'controls': []}
        if args['action'] == 'catalog':
            return {'ok': True, 'menus': [{'label': 'File', 'enabled': True, 'has_submenu': True}]}
        if args['action'] == 'open':
            return {'ok': True, 'menu_items': [{'label': 'Delete', 'enabled': True, 'has_submenu': False},
                                             {'label': 'Open Recent', 'enabled': True, 'has_submenu': True}]}
        return {'ok': True, 'menu_items': []}
    result = exploration.run(7, invoke, controls=False, max_depth=2)
    assert result['ok'] and len(result['visited']) == 2
    actions = [a['action'] for n,a in calls if n == 'fan_window_menu']
    assert actions == ['catalog', 'open', 'submenu', 'return', 'return']
    assert not any(a.get('label') == 'Delete' for _,a in calls)


def test_menu_return_failure_stops_exploration():
    def invoke(name, args):
        if name == 'fan_window_probe':
            return {'ok': True, 'frame': {'foreground': True}}
        if args['action'] == 'catalog':
            return {'ok': True, 'menus': [{'label': 'File', 'enabled': True, 'has_submenu': True}]}
        return {'ok': args['action'] != 'return', 'menu_items': []}
    assert not exploration.run(7, invoke, controls=False)['ok']


def test_tab_title_can_disambiguate_only_one_observed_shell_path():
    base={'session':'native','foreground':42,'idle_ms':0,'windows':[
        {'hwnd':42,'path':'C:\\Work\\DomeSim-codex','title':'DomeSim-codex and 1 more tab - File Explorer'},
        {'hwnd':42,'path':'C:\\Other','title':'DomeSim-codex and 1 more tab - File Explorer'}]}
    explorer_usage.ingest({**base,'tick':1000})
    explorer_usage.ingest({**base,'tick':3000})
    rows={r['path']:r for r in explorer_usage.ranked()['paths']}
    assert rows['C:\\Work\\DomeSim-codex']['active_ms']==2000 and rows['C:\\Other']['active_ms']==0


def test_repeated_source_reuse_gets_only_one_generation_estimate_per_task():
    from bridge import window_knowledge as k
    one=k.record_use('task','artifact:abc','reuse','script',1000,{},'script@1')
    two=k.record_use('task','artifact:abc','reuse','script',1000,{},'script@1')
    assert one['estimated_text_tokens_saved']>0 and two['estimated_text_tokens_saved']==0


def test_exact_unit_dispatch_does_not_construct_model(monkeypatch):
    from bridge import agent
    script_unit()
    monkeypatch.setattr(agent,'check_cancelled',lambda _:None)
    monkeypatch.setattr(agent,'db_write',lambda *args:None)
    monkeypatch.setattr(agent,'OpenAI',lambda **kwargs:pytest.fail('Local unit must not construct a model'))
    calls=[]
    monkeypatch.setattr(agent,'request_tool',lambda name,args,**kwargs: calls.append((name,kwargs)) or {'ok':True,'completed':['run'],'llm_calls':0})
    text=agent.run_prompt('run learned unit Safe lesson inputs {"hwnd":123}',task_id='test')
    assert 'model calls: 0' in text and calls==[('daa_unit_run',{'timeout':615,'task_id':'test','origin':'pre_llm'})]


def test_native_stream_coalesces_text_without_skipping_evidence(tmp_path):
    from bridge import workbench
    db=tmp_path/'stream.db'
    with sqlite3.connect(db) as c:
        c.execute('CREATE TABLE tasks(id,prompt,status,response,created_at)')
        c.execute("INSERT INTO tasks VALUES('task','tour','running','','now')")
        c.execute('CREATE TABLE events(id INTEGER PRIMARY KEY,at,kind,subject,payload)')
        for i in range(1,201):
            c.execute('INSERT INTO events VALUES(?,?,?,?,?)',(i,'now','reasoning','task',json.dumps({'round':1,'text':'x'})))
        c.execute('INSERT INTO events VALUES(?,?,?,?,?)',(201,'now','daa_action','task',json.dumps({'label':'real step'})))
    result=workbench.native_events(db,'task')
    assert result['cursor']==201 and len(result['events'])==2
    assert result['events'][0]['payload']['text']=='x'*200
    assert result['cards'][0]['title']=='real step'


def test_window_chrome_alone_cannot_certify_an_unchanged_app_page():
    from bridge.window_knowledge import semantic_context
    assert not semantic_context({'controls':[{'role':'window','name':'DomeSim Studio'},
        {'role':'push button','name':'Close'},{'role':'menu item','name':'System'}]})
    assert semantic_context({'controls':[{'role':'page tab','name':'Editor','selected':True}]})


def test_typed_unit_contract_accepts_inputs_alias_and_marker_checks():
    from bridge import catalog
    library.save('Owned.ahk','script','ExitApp(0)')
    args=catalog.validate('daa_unit_save',{'name':'Marker','steps':[{'tool':'ahk_script_run',
        'inputs':{'name':'Owned.ahk','wait':True},'expect':{'stdout':{'contains':'NAV_VERIFIED'}}}]})
    assert 'arguments' in args['steps'][0] and 'inputs' not in args['steps'][0]
    units.save(**args)
    result=units.run('Marker',{},lambda *a:{'ok':True,'status':'complete','stdout':'NAV_VERIFIED\n'})
    assert result['verified']
