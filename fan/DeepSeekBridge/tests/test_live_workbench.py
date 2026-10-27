"""Real storage, event projection and image-input contracts, without paid calls."""
import base64
import json
import sqlite3
import struct
import zlib
from types import SimpleNamespace as NS

import pytest
from fastapi.testclient import TestClient
from bridge import agent, attachments, catalog, gateway, workbench

HEADERS = {'X-Bridge-Token': 'test-local-token'}


def png(width=2, height=2):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
    data += chunk(b'IDAT', zlib.compress((b'\0' + b'\xff\0\0' * min(width, 10)) * min(height, 10))) + chunk(b'IEND', b'')
    return 'data:image/png;base64,' + base64.b64encode(data).decode()


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(gateway, 'DB', tmp_path / 'bridge.sqlite3')
    monkeypatch.setattr(agent, 'DB', gateway.DB)
    monkeypatch.setenv('DEEPSEEK_API_KEY', 'synthetic-test-key')
    gateway.init_db()
    with TestClient(gateway.app) as instance:
        yield instance


def test_image_input_and_durable_sequence(client):
    assert client.post('/images', json={'data_url': png()}).status_code == 401
    image = client.post('/images', headers=HEADERS, json={'data_url': png(), 'label': 'Fixture snip'}).json()
    assert (image['width'], image['height'], image['mime']) == (2, 2, 'image/png')
    assert client.get('/images/' + image['id']).status_code == 401
    assert client.get('/images/' + image['id'], headers=HEADERS).content == attachments.get(gateway.DB, image['id'])['data']
    response = client.post('/tasks', headers=HEADERS, json={'prompt': 'Explain this image', 'images': [image['id']]})
    assert response.status_code == 200
    identity = response.json()['id']
    with sqlite3.connect(gateway.DB) as db:
        assert json.loads(db.execute('SELECT attachments FROM tasks WHERE id=?', (identity,)).fetchone()[0]) == [image['id']]
        assert db.execute('SELECT prompt,status FROM automation_sequence WHERE task_id=?', (identity,)).fetchone() == ('Explain this image', 'queued')
    client.post('/tasks/' + identity + '/cancel', headers=HEADERS)
    with sqlite3.connect(gateway.DB) as db:
        assert db.execute('SELECT status,finished_at FROM automation_sequence WHERE task_id=?', (identity,)).fetchone()[0] == 'cancelled'
    assert client.post('/tasks', headers=HEADERS, json={'prompt': 'unknown', 'images': ['missing']}).status_code == 422
    assert client.post('/tasks', headers=HEADERS, json={'prompt': 'too many', 'images': [image['id']] * 5}).status_code == 422


@pytest.mark.parametrize('data', ['data:text/html;base64,PGgxPg==', 'data:image/png;base64,aGVsbG8=', png(12000001, 1)])
def test_invalid_image_rejected(client, data):
    assert client.post('/images', headers=HEADERS, json={'data_url': data}).status_code == 422


def test_vision_input_is_inference_and_default_effort_max(client, monkeypatch):
    image = attachments.store(gateway.DB, png())
    identity = client.post('/tasks', headers=HEADERS, json={'prompt': 'Explain', 'images': [image['id']]}).json()['id']
    requests, analyses = [], []
    def create(**kwargs):
        requests.append(json.loads(json.dumps(kwargs)))
        class Stream:
            def __iter__(self):
                yield NS(usage=None, choices=[NS(finish_reason='stop', delta=NS(content='A red square', reasoning_content=None, tool_calls=[]))])
            def close(self):
                pass
        return Stream()
    monkeypatch.setattr(agent, 'OpenAI', lambda **kwargs: NS(chat=NS(completions=NS(create=create))))
    monkeypatch.setattr(agent.vision, 'analyze', lambda evidence, **kwargs: analyses.append(evidence) or {'text': 'Red square'})
    monkeypatch.delenv('DEEPSEEK_REASONING_EFFORT', raising=False)
    assert agent.run_prompt('Explain', task_id=identity, images=[image['id']]) == 'A red square'
    assert requests[0]['reasoning_effort'] == 'max'
    assert analyses[0]['frame']['coordinates'] == 'image_pixels'
    assert 'model inference' in requests[0]['messages'][-1]['content']
    assert 'not a live desktop locator' in requests[0]['messages'][-1]['content']
    assert workbench.events(gateway.DB, identity)['cards'][0]['source_kind'] == 'user_supplied'


def test_canvas_retains_modalities_in_order_without_duplicate_results(client):
    identity = client.post('/tasks', headers=HEADERS, json={'prompt': 'Observe fixture'}).json()['id']
    result = {'ok': True, 'photo_ref': 'photo:1', 'frame': {'title': 'Fixture'},
              'controls': [{'role': 'Button', 'name': 'Calculate', 'bounds': {'x': 1, 'y': 2, 'w': 40, 'h': 20}}],
              'ocr': {'text': '42', 'words': [{'text': '42', 'x': 1}]}}
    gateway.db_write('tool_result', 'fan_window_inspect', {'task_id': identity, 'result': result})
    gateway.db_write('agent_tool_result', identity, {'task_id': identity, 'name': 'fan_window_inspect', 'result': result})
    gateway.db_write('vision_result', identity, {'task_id': identity, 'text': 'A calculator'})
    data = workbench.events(gateway.DB, identity)
    assert [c['kind'] for c in data['cards']] == ['image', 'controls', 'ocr', 'interpretation']
    assert data['cards'][1]['data']['controls'][0]['name'] == 'Calculate'
    assert data['cards'][-1]['source_kind'] == 'inference'
    assert workbench.events(gateway.DB, identity, data['cursor'])['events'] == []
    gateway.db_write('agent_tool_result', identity, {'name': 'fan_pattern_capture', 'result': {'text': '|<>*128$2.e', 'ok': True}})
    assert workbench.events(gateway.DB, identity, data['cursor'])['cards'][0]['kind'] == 'findtext'


def test_retained_image_survives_capture_cache_and_path_is_constrained(client):
    blob = base64.b64decode(png().split(',')[1])
    with sqlite3.connect(gateway.DB) as db:
        db.execute('CREATE TABLE media_image(id INTEGER PRIMARY KEY,data_url TEXT)')
        db.execute('INSERT INTO media_image VALUES(1,?)', (png(),))
    gateway.db_write('tool_result', 'capture', {'result': {'photo_ref': 'photo:1', 'image_path': 'C:/missing/cache.png'}})
    with sqlite3.connect(gateway.DB) as db:
        identity = db.execute('SELECT MAX(id) FROM events').fetchone()[0]
    assert workbench.image(gateway.DB, identity, 'image') == (blob, 'image/png')
    gateway.db_write('tool_result', 'capture', {'result': {'image_path': str(gateway.DB)}})
    with pytest.raises(ValueError):
        workbench.image(gateway.DB, identity + 1, 'image')


def test_registry_matches_advertised_tools_and_indexes_actual_source():
    data = workbench.registry()
    assert {t['name'] for t in data['tools']} == {t['function']['name'] for t in catalog.functions()}
    assert any('FindText' in m['path'] for m in data['methods'])
    method = data['methods'][0]
    assert method['name'] in workbench.method_source(method['path'], method['line'])['source']
    with pytest.raises(ValueError):
        workbench.method_source('../../.env', 1)


def test_findtext_binary_translation():
    # Four pixels 1001 + sentinel 1 + padding 0 => alphabet index 38 = a.
    decoded = workbench.pattern_preview('|<>*128$2.a')
    assert decoded['bits'] == '1001'
    assert (decoded['width'], decoded['height']) == (2, 2)


def test_workbench_http_auth_and_library_path_validation(client, monkeypatch):
    import threading
    import httpx
    from http.server import ThreadingHTTPServer
    from bridge import monitor
    monkeypatch.setattr(monitor, 'DB', gateway.DB)
    monkeypatch.setattr(monitor, 'TOKEN', HEADERS['X-Bridge-Token'])
    server = ThreadingHTTPServer(('127.0.0.1', 0), monitor.Handler)
    monkeypatch.setattr(monitor, 'PORT', server.server_port)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    url = f'http://127.0.0.1:{server.server_port}'
    try:
        with httpx.Client(base_url=url) as web:
            assert web.get('/').status_code == 200
            assert web.get('/api/runs').status_code == 401
            assert web.get('/api/runs', headers={**HEADERS, 'Origin': 'https://unrelated.example'}).status_code == 401
            assert web.get('/api/runs', headers=HEADERS).json()['runs'] == []
            assert web.get('/api/method?path=../../.env&line=1', headers=HEADERS).status_code == 400
            assert web.get('/api/registry', headers=HEADERS).json()['tools']
            tools = web.get('/api/tooling?kind=tools', headers=HEADERS).json()
            assert tools['total'] == len(catalog.functions())
            assert 'schema' not in tools['rows'][0]
            assert web.get('/api/tool?name=' + tools['rows'][0]['name'], headers=HEADERS).json()['parameters']
            methods = web.get('/api/tooling?kind=methods', headers=HEADERS).json()
            next_page = web.get('/api/tooling?kind=methods&offset=100', headers=HEADERS).json()
            assert len(methods['rows']) == 100 and methods['has_more']
            assert methods['rows'][0] != next_page['rows'][0]
            assert web.get('/api/discoveries', headers=HEADERS).json()['claims'] == []
            for endpoint in ('/api/knowledge-stats', '/api/window-knowledge', '/api/project-paths', '/api/report?task=missing'):
                assert web.get(endpoint).status_code == 401
            assert web.get('/api/knowledge-stats', headers=HEADERS).json()['uses'] == 0
            assert web.get('/api/window-knowledge', headers=HEADERS).json()['windows'] == []
            assert web.get('/api/project-paths', headers=HEADERS).json()['paths'] == []
            assert web.get('/api/report?task=missing', headers=HEADERS).status_code == 400
            js = web.get('/workbench.js').text
            assert 'innerHTML' not in js
            assert 'textContent' in js
            assert "content.scrollTop = content.scrollHeight" in js
    finally:
        server.shutdown()
        server.server_close()


def test_discovery_claim_search_and_lesson_provenance(client):
    with sqlite3.connect(gateway.DB) as db:
        db.execute('CREATE TABLE learning_claim(id INTEGER PRIMARY KEY,source TEXT,claim TEXT,use_text TEXT)')
        db.execute('CREATE TABLE learning_evidence(id INTEGER PRIMARY KEY,claim_id INTEGER,eligible INTEGER,outcome TEXT,detail TEXT)')
        db.execute('CREATE TABLE learning_lesson(claim_id INTEGER,revision INTEGER,steps TEXT)')
        db.execute("INSERT INTO learning_claim VALUES(38,'Usage sequences','Three recorded transitions','Rehearse in an isolated fixture')")
        db.execute("INSERT INTO learning_evidence VALUES(1,38,1,'pass','Historical continuation')")
        db.execute("INSERT INTO learning_evidence VALUES(2,38,0,'fail','Isolated rehearsal')")
        db.execute('INSERT INTO learning_lesson VALUES(38,1,?)', (json.dumps([{'layer': 'Evidence', 'text': 'Recorded continuation'}]),))
    assert len(workbench.claims(gateway.DB, query='38')) == 1
    assert workbench.claims(gateway.DB, query='missing') == []
    claim = workbench.claims(gateway.DB, 38)[0]
    assert (claim['observations'], claim['passes'], claim['failures']) == (2, 1, 0)
    assert claim['lesson']['steps'][0]['text'] == 'Recorded continuation'
    assert len(claim['evidence']) == 2


def test_scoped_knowledge_sharing_and_local_report(client):
    from bridge import window_knowledge
    identity = client.post('/tasks', headers=HEADERS, json={'prompt': 'Inspect Explorer project paths'}).json()['id']
    with sqlite3.connect(gateway.DB) as db:
        db.execute("UPDATE tasks SET status='running' WHERE id=?", (identity,))
    scoped = {**HEADERS, 'X-Bridge-Task': identity}
    assert client.post('/tools/fan_project_paths', headers=scoped, json={'query': 'Explorer'}).status_code == 403
    window_knowledge.sharing(True)
    assert client.post('/tools/fan_project_paths', headers=scoped, json={'query': ''}).status_code == 422
    assert client.post('/tools/fan_window_knowledge', headers=scoped, json={}).status_code == 422
    assert client.post('/tools/fan_project_paths', headers=scoped, json={'query': 'Explorer'}).status_code == 200
    assert client.post('/tools/fan_window_knowledge', headers=scoped, json={'window_id': 'missing'}).status_code == 404
    assert 'Inspect Explorer' in workbench.report(gateway.DB, identity)


def test_native_event_preview_removes_duplicate_payload_without_changing_evidence(client):
    identity = client.post('/tasks', headers=HEADERS, json={'prompt': 'Native preview fixture'}).json()['id']
    controls = [{'name': 'Control ' + str(i), 'role': 'button', 'bounds': {'x': i, 'y': 1, 'w': 20, 'h': 20}, 'accessibility_path': '1/' + str(i)} for i in range(100)]
    gateway.db_write('tool_result', 'fan_window_survey', {'task_id': identity, 'result': {'ok': True, 'frame': {'frame_id': 'fixture'}, 'controls': controls, 'ocr': {'text': 'Observed', 'words': [{'text': str(i)} for i in range(200)]}}})
    raw = workbench.events(gateway.DB, identity)
    preview = workbench.native_events(gateway.DB, identity)
    raw_event = next(e for e in raw['events'] if e['kind'] == 'tool_result')
    preview_event = next(e for e in preview['events'] if e['kind'] == 'tool_result')
    assert len(raw_event['payload']['result']['controls']) == 100
    assert 'result' not in preview_event['payload']
    assert len(next(c for c in preview['cards'] if c['kind'] == 'controls')['data']['controls']) == 80
    ocr = next(c for c in preview['cards'] if c['kind'] == 'ocr')['data']
    assert len(ocr['words']) == 120 and ocr['retained_counts']['words'] == 200
    assert len(workbench.events(gateway.DB, identity)['cards'][0]['data']['controls']) == 100
