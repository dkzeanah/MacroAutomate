"""Controller contracts: isolation, fair snapshots, real usage arithmetic, and review gates."""
import json
from pathlib import Path
import pytest
from fastapi.testclient import TestClient
from bridge.controller import adapters,service,store,usage,workspace


class InlinePool:
    def submit(self,function,*args):
        function(*args)


@pytest.fixture
def lab(tmp_path,monkeypatch):
    root=tmp_path/'domesim-atlas'
    root.mkdir()
    (root/'model.py').write_text('def value():\n    return 1\n')
    (root/'CLAUDE.md').write_text('# Agreement\nKeep outputs.\n\n## Atlas context for code work\nAtlas directive.\n\n## Rules\nBe accurate.\n')
    monkeypatch.setattr(store,'DATA',tmp_path/'data')
    monkeypatch.setattr(workspace,'WORKSPACE',root)
    monkeypatch.setattr(service,'POOL',InlinePool())
    monkeypatch.setattr(adapters,'availability',lambda:[{'id':'codex','available':True,'default_model':'test-model'}])
    monkeypatch.setattr(workspace,'index',lambda *args:{'files':1,'symbols':1})
    def execute(run):
        store.event(run['id'],'tool_start',{'name':'test'})
        store.event(run['id'],'tool_result',{'name':'workspace_read','result':{'code':'fixture source'}})
        if run['settings']['access']=='edit':
            (Path(run['root'])/'model.py').write_text('def value():\n    return 2\n')
        return 'Evidence-backed answer',usage.normalize('codex',{'input_tokens':100 if run['mode']=='atlas' else 200,
                'cached_input_tokens':20,'output_tokens':10},'test-model')
    monkeypatch.setattr(adapters,'execute',execute)
    with TestClient(service.app) as client:
        client.get('/')
        yield client,root


def test_usage_cache_is_a_subset_not_double_counted():
    a=usage.normalize('claude',{'input_tokens':10,'cache_read_input_tokens':20,'cache_creation_input_tokens':5,'output_tokens':2})
    b=usage.normalize('codex',{'input_tokens':35,'cached_input_tokens':20,'output_tokens':2})
    c=usage.normalize('deepseek',{'prompt_tokens':35,'completion_tokens':2,'prompt_cache_hit_tokens':20})
    assert a['total_tokens']==b['total_tokens']==c['total_tokens']==37
    assert usage.combine([c,c])['total_tokens']==74
    assert usage.normalize('codex',{})['total_tokens'] is None


def test_local_session_and_origin(lab):
    client,_=lab
    assert client.get('/api/state').status_code==200
    assert client.post('/api/runs',json={},headers={'Origin':'https://evil.example'}).status_code==403
    client.cookies.clear()
    assert client.get('/api/state').status_code==401


def test_pair_matches_source_and_exports_usage(lab):
    client,root=lab
    result=client.post('/api/runs',json={'prompt':'Explain value','provider':'codex','mode':'compare'})
    assert result.status_code==200,result.text
    batch=result.json()['batch']
    report=client.get('/api/comparisons/'+batch).json()
    assert report['comparable'],report
    assert report['atlas']['baseline']==report['normal']['baseline']
    assert report['token_reduction_percent']==47.62
    assert 'Atlas directive' not in (Path(report['normal']['root'])/'CLAUDE.md').read_text()
    exported=client.get('/api/runs/'+report['atlas']['id']+'/export').json()
    assert exported['events'] and exported['run']['usage']['source']=='provider_reported'
    assert (root/'model.py').read_text().endswith('return 1\n')
    store.update(report['atlas']['id'],baseline='different')
    assert not client.get('/api/comparisons/'+batch).json()['comparable']


def test_reviewed_apply_preserves_original_and_detects_conflicts(lab):
    client,root=lab
    response=client.post('/api/runs',json={'prompt':'Change value','provider':'codex','access':'edit'})
    identity=response.json()['run_ids'][0]
    assert (root/'model.py').read_text().endswith('return 1\n')
    report=client.get(f'/api/runs/{identity}/diff').json()
    assert '+    return 2' in report['diff']
    assert client.post(f'/api/runs/{identity}/apply',json={'fingerprint':'wrong'}).status_code==409
    assert client.post(f'/api/runs/{identity}/apply',json={'fingerprint':report['fingerprint']}).status_code==200
    assert (root/'model.py').read_text().endswith('return 2\n')
    assert client.post(f'/api/runs/{identity}/apply',json={'fingerprint':report['fingerprint']}).status_code==409


def test_snapshot_excludes_secrets_and_path_escape(lab,tmp_path):
    _,root=lab
    (root/'.env').write_text('SECRET=synthetic')
    (root/'private').mkdir()
    (root/'private'/'strategy.md').write_text('private')
    (root/'binary.mp4').write_bytes(b'\x00')
    snapshot=tmp_path/'snapshot'
    manifest=workspace.snapshot(root,snapshot)
    assert '.env' not in manifest['files'] and not (snapshot/'private').exists()
    assert not (snapshot/'binary.mp4').exists()
    with pytest.raises(ValueError):
        workspace.safe_path(root,'../outside.py')
    with pytest.raises(ValueError):
        workspace.safe_path(root,'.env')


def test_recovery_does_not_restart_paid_work(lab):
    _,_=lab
    identity=store.create('batch','codex','normal','task','test',{})
    service.recover()
    assert store.get(identity)['status']=='interrupted'


def test_compare_cannot_enable_edits(lab):
    client,_=lab
    assert client.post('/api/runs',json={'prompt':'task','provider':'codex','mode':'compare','access':'edit'}).status_code==422


def test_comparison_poll_does_not_rescan_source(lab,monkeypatch):
    client,_=lab
    result=client.post('/api/runs',json={'prompt':'task','provider':'codex','mode':'compare'}).json()
    def forbidden(*args,**kwargs):
        raise AssertionError('Comparison polling must not rehash the filesystem')
    monkeypatch.setattr(workspace,'changes',forbidden)
    assert client.get('/api/comparisons/'+result['batch']).json()['comparable']


def test_queued_pair_and_cancel_transition(lab):
    client,_=lab
    first=store.create('queued-pair','codex','normal','task','model',{})
    store.create('queued-pair','codex','atlas','task','model',{})
    response=client.get('/api/comparisons/queued-pair')
    assert response.status_code==200 and not response.json()['comparable']
    assert store.transition(first,('queued',),'cancelled')
    assert not store.transition(first,('queued','preparing'),'running')
    assert store.get(first)['status']=='cancelled'


def test_source_blocked_answers_are_not_valid_comparisons(lab):
    client,_=lab
    result=client.post('/api/runs',json={'prompt':'task','provider':'codex','mode':'compare'}).json()
    with store.db() as db:
        for identity in result['run_ids']:
            db.execute("DELETE FROM events WHERE run_id=? AND kind='tool_result'",(identity,))
    report=client.get('/api/comparisons/'+result['batch']).json()
    assert not report['comparable'] and not report['checks']['source_retrieved']
    assert report['token_reduction_percent'] is None


def test_readonly_tool_and_command_approval_gate(lab,monkeypatch):
    from bridge.controller import tool_server
    client,_=lab
    result=client.post('/api/runs',json={'prompt':'task','provider':'codex'}).json()
    identity=result['run_ids'][0]
    # Controlled fixture: permit tool access, while its write capability remains read-only.
    store.update(identity,status='running')
    monkeypatch.setattr(tool_server,'RUN_ID',identity)
    with pytest.raises(ValueError,match='read-only'):
        tool_server.workspace_write('model.py','bad')
    with store.db() as db:
        db.execute('INSERT INTO approvals VALUES(?,?,?,?,?)',('decision',identity,'["python","-V"]','pending',0))
    assert client.post('/api/approvals/decision',json={'approve':False}).status_code==200
    assert client.post('/api/approvals/decision',json={'approve':True}).status_code==409


def test_owned_process_tree_stops_on_cancel(tmp_path,monkeypatch):
    import sys,threading,time
    monkeypatch.setattr(store,'DATA',tmp_path/'data')
    root=tmp_path/'source'
    root.mkdir()
    identity=store.create('cancel-test','codex','normal','task','model',{'timeout_seconds':30,'access':'read_only'})
    store.update(identity,status='running',root=str(root))
    code="import subprocess,sys,time,json; subprocess.Popen([sys.executable,'-c','import time;time.sleep(90)']); print(json.dumps({'type':'test_ready'}),flush=True); time.sleep(90)"
    monkeypatch.setattr(adapters,'command',lambda run:[sys.executable,'-c',code])
    errors=[]
    def execute():
        try:
            adapters.execute(store.get(identity))
        except RuntimeError as error:
            errors.append(str(error))
    worker=threading.Thread(target=execute)
    worker.start()
    try:
        for _ in range(80):
            if any(e['payload'].get('type')=='test_ready' for e in store.events(identity)):
                break
            time.sleep(.1)
        else:
            pytest.fail('Test process did not start')
        store.transition(identity,('running',),'cancelled')
        adapters.terminate(identity)
        worker.join(timeout=8)
        assert not worker.is_alive() and errors
        assert identity not in adapters.PROCESSES
    finally:
        adapters.terminate(identity)
        worker.join(timeout=5)


def test_targeted_edit_requires_fresh_source_and_preserves_crlf(lab,monkeypatch):
    from bridge.controller import tool_server
    client,_=lab
    identity=client.post('/api/runs',json={'prompt':'task','provider':'codex','mode':'normal','access':'edit'}).json()['run_ids'][0]
    value=store.get(identity)
    store.update(identity,status='running')
    path=Path(value['root'])/'model.py'
    path.write_bytes(b'\xef\xbb\xbfdef value():\r\n    return 2\r\n')
    monkeypatch.setattr(tool_server,'RUN_ID',identity)
    page=tool_server.workspace_read('model.py')
    tool_server.workspace_replace('model.py','    return 2','    return 3',page['file_sha256'])
    assert path.read_bytes()==b'\xef\xbb\xbfdef value():\r\n    return 3\r\n'
    with pytest.raises(ValueError,match='Source changed'):
        tool_server.workspace_replace('model.py','return 3','return 4',page['file_sha256'])


def test_approved_command_through_real_mcp_stdio(tmp_path,monkeypatch):
    import asyncio,os
    from mcp import ClientSession,StdioServerParameters
    from mcp.client.stdio import stdio_client
    monkeypatch.setattr(store,'DATA',tmp_path/'data')
    root=tmp_path/'source'
    root.mkdir()
    identity=store.create('mcp-command-test','deepseek','normal','fixture','test',{'access':'read_only'})
    store.update(identity,status='running',root=str(root))
    cfg=adapters.tool_configuration(store.get(identity))
    async def check():
        params=StdioServerParameters(command=cfg['command'],args=cfg['args'],
               env={**os.environ,**cfg['env'],'PYTHONIOENCODING':'utf-8'})
        async with stdio_client(params) as (rd,wr):
            async with ClientSession(rd,wr) as client:
                await client.initialize()
                pending=asyncio.create_task(client.call_tool('workspace_test',
                    {'command':['python','-c',"print('MCP command passed')"]}))
                for _ in range(100):
                    with store.db() as db:
                        row=db.execute("SELECT * FROM approvals WHERE run_id=? AND status='pending'",(identity,)).fetchone()
                        if row:
                            command=json.loads(row['command'])
                            assert Path(command[0]).resolve()==Path(adapters.sys.executable).resolve()
                            db.execute("UPDATE approvals SET status='approved' WHERE id=?",(row['id'],))
                    if row:
                        break
                    await asyncio.sleep(.1)
                else:
                    pytest.fail('No command approval was requested')
                result=await asyncio.wait_for(pending,15)
                value=result.structuredContent or json.loads(result.content[0].text)
                assert not result.isError and value['exit_code']==0,value
                assert value['output'].strip()=='MCP command passed'
    asyncio.run(check())


def test_second_controller_cannot_take_history_ownership(tmp_path,monkeypatch):
    from bridge.controller import instance
    monkeypatch.setattr(store,'DATA',tmp_path/'data')
    import socket
    with socket.socket() as probe:
        probe.bind(('127.0.0.1',0))
        port=probe.getsockname()[1]
    with instance.own(port) as url:
        with pytest.raises(instance.AlreadyRunning) as error:
            with instance.own(port):
                pytest.fail('Second controller acquired ownership')
        assert error.value.url==url
    with instance.own(port):
        pass
