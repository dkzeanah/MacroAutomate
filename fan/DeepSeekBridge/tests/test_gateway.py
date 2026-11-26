"""Protocol and security checks for the gateway."""
import json
import os
import threading
import time
from urllib.parse import urlencode
os.environ['BRIDGE_TOKEN'] = 'test-local-token'
os.environ['BRIDGE_DB'] = ':memory:'  # overridden below with pytest temp database
from fastapi.testclient import TestClient
from bridge import common, gateway


def test_denied_without_token():
    with TestClient(gateway.app) as client:
        response = client.get('/health')
        assert response.status_code == 401


def test_reject_unknown_tool():
    with TestClient(gateway.app) as client:
        response = client.post('/tools/execute_shell', json={}, headers={'X-Bridge-Token': 'test-local-token'})
        assert response.status_code == 404


def test_health_reports_agent_heartbeat(tmp_path, monkeypatch):
    monkeypatch.setattr(gateway, 'DB', tmp_path / 'health.sqlite3')
    gateway.init_db()
    heartbeat = tmp_path / 'agent.heartbeat'
    monkeypatch.setattr(common, 'AGENT_HEARTBEAT', heartbeat)
    headers = {'X-Bridge-Token': 'test-local-token'}
    with TestClient(gateway.app) as client:
        assert client.get('/health', headers=headers).json()['agent_alive'] is False
        heartbeat.write_text(json.dumps({'pid': os.getpid(), 'at': time.time()}), encoding='utf-8')
        state = client.get('/health', headers=headers).json()
        assert state['agent_alive'] is True and state['agent_pid'] == os.getpid()
        heartbeat.write_text(json.dumps({'pid': os.getpid(), 'at': time.time() - 60}), encoding='utf-8')
        assert client.get('/health', headers=headers).json()['agent_alive'] is False


def test_tool_roundtrip(tmp_path, monkeypatch):
    monkeypatch.setattr(gateway, 'DB', tmp_path / 'bridge.sqlite3')
    gateway.init_db()
    headers = {'X-Bridge-Token': 'test-local-token'}
    result = {}
    with TestClient(gateway.app) as client:
        def make_call():
            result['response'] = client.post('/tools/window_activate', json={'title': 'Notepad'}, headers=headers)
        thread = threading.Thread(target=make_call)
        thread.start()
        for attempt in range(100):
            response = client.get('/worker/next', headers=headers)
            if response.text != 'NONE':
                break
            time.sleep(.01)
        else:
            raise AssertionError('Tool not enqueued')
        call_id, name, encoded = response.text.split('\n')
        assert name == 'window_activate'
        assert encoded == 'Notepad'
        ack = client.post('/worker/result', data={'id': call_id, 'result': '{"ok":true}'}, headers=headers)
        assert ack.status_code == 200
        thread.join(timeout=2)
        assert not thread.is_alive()
        assert result['response'].json() == {'ok': True}


def test_task_queue(tmp_path, monkeypatch):
    monkeypatch.setattr(gateway, 'DB', tmp_path / 'tasks.sqlite3')
    gateway.init_db()
    headers = {'X-Bridge-Token': 'test-local-token'}
    with TestClient(gateway.app) as client:
        response = client.post('/tasks', json={'prompt': 'List my windows'}, headers=headers)
        assert response.status_code == 200
        task_id = response.json()['id']
        status = client.get('/tasks/' + task_id, headers=headers)
        assert status.json()['status'] == 'queued'
