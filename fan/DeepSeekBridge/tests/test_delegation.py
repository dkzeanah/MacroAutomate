"""Delegation reuses authenticated durable task state and refuses recursive agents."""
import sqlite3
from fastapi.testclient import TestClient
from bridge import catalog, gateway

def test_submit_observe_and_cancel(tmp_path, monkeypatch):
    monkeypatch.setattr(gateway, 'DB', tmp_path/'tasks.sqlite3')
    monkeypatch.setattr(gateway, 'TOKEN', 'synthetic-token')
    gateway.init_db()
    headers = {'X-Bridge-Token': 'synthetic-token'}
    with TestClient(gateway.app) as client:
        response = client.post('/tools/fan_agent_submit', json={'prompt': 'Inspect the demo', 'atlas_context': 'Reference source'}, headers=headers)
        assert response.status_code == 200
        identity = response.json()['task_id']
        with sqlite3.connect(gateway.DB) as db:
            prompt, history = db.execute('SELECT prompt,history FROM tasks WHERE id=?', (identity,)).fetchone()
        assert prompt == 'Inspect the demo' and 'Reference source' in history
        status = client.post('/tools/fan_agent_status', json={'task_id': identity}, headers=headers).json()
        assert status['status'] == 'queued'
        events = client.post('/tools/fan_agent_events', json={'task_id': identity}, headers=headers).json()
        assert 'harness_delegation' in {item['kind'] for item in events['events']}
        cancelled = client.post('/tools/fan_agent_cancel', json={'task_id': identity}, headers=headers).json()
        assert cancelled['status'] == 'cancelled'

def test_child_cannot_delegate_again(tmp_path, monkeypatch):
    monkeypatch.setattr(gateway, 'DB', tmp_path/'tasks.sqlite3')
    monkeypatch.setattr(gateway, 'TOKEN', 'synthetic-token')
    gateway.init_db()
    headers = {'X-Bridge-Token': 'synthetic-token'}
    with TestClient(gateway.app) as client:
        identity = client.post('/tasks', json={'prompt': 'test'}, headers=headers).json()['id']
        with sqlite3.connect(gateway.DB) as db:
            db.execute("UPDATE tasks SET status='running' WHERE id=?", (identity,))
        response = client.post('/tools/fan_agent_submit', json={'prompt': 'another agent'}, headers={**headers, 'X-Bridge-Task': identity})
        assert response.status_code == 422
        assert 'Nested delegation' in response.json()['detail']
    assert 'fan_agent_submit' not in {tool['function']['name'] for tool in catalog.functions()}
