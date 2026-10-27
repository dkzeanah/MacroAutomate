"""Real FIFO dispatch contracts for Fan, including cancellation and owned runs."""
import json
import sqlite3
import threading
import time
from urllib.parse import unquote

import pytest
from fastapi.testclient import TestClient
from bridge import gateway, automation

HEADERS = {'X-Bridge-Token': 'test-local-token'}


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(gateway, 'DB', tmp_path / 'gateway.sqlite3')
    monkeypatch.setattr(automation, 'SCRIPTS', tmp_path / 'scripts')
    gateway.init_db()
    with TestClient(gateway.app) as instance:
        yield instance


def task(client):
    result = client.post('/tasks', headers=HEADERS, json={'prompt': 'native test'}).json()
    with sqlite3.connect(gateway.DB) as db:
        db.execute("UPDATE tasks SET status='running' WHERE id=?", (result['id'],))
    return result['id']


def fan_call(client, name, data, headers):
    results = []
    thread = threading.Thread(target=lambda: results.append(client.post('/tools/' + name, json=data, headers=headers)))
    thread.start()
    for _ in range(100):
        response = client.get('/fan/next', headers=HEADERS)
        if response.text != 'NONE':
            return thread, results, response.text.split('\n')
        time.sleep(.01)
    raise AssertionError('Native call not enqueued')


def test_native_fifo_keeps_structured_steps_and_unicode(client):
    parent = task(client)
    steps = [{'action': 'Type', 'text': 'café α → 10', 'nested': {'values': [1, 2]}}]
    thread, results, (call_id, name, encoded) = fan_call(client, 'fan_workflow_save', {'name': 'my_math', 'steps': steps}, {**HEADERS, 'X-Bridge-Task': parent})
    assert name == 'fan_workflow_save'
    payload = json.loads(unquote(encoded))
    assert payload['steps'] == steps and payload['_task_id'] == parent
    assert client.get('/worker/next', headers=HEADERS).text == 'NONE'
    assert client.post('/worker/result', headers=HEADERS, data={'id': call_id, 'result': '{"ok":true}'}).status_code == 404
    assert client.post('/fan/result', headers=HEADERS, data={'id': call_id, 'result': '{"ok":true,"name":"my_math"}'}).status_code == 200
    thread.join(2)
    assert not thread.is_alive() and results[0].json()['ok']
    records = client.post('/tools/tool_catalog_search', headers=HEADERS, json={'query': 'my_math'}).json()['records']
    assert records[0]['kind'] == 'workflow' and records[0]['metadata']['source_kind'] == 'observed'
    assert client.get('/health', headers=HEADERS).json()['fan_connected']


def test_cancelled_native_call_is_not_delivered(client):
    parent = task(client)
    results = []
    thread = threading.Thread(target=lambda: results.append(client.post('/tools/fan_workflow_run', headers={**HEADERS, 'X-Bridge-Task': parent}, json={'name': 'ignored', 'timeout_seconds': 1})))
    thread.start()
    for _ in range(100):
        with gateway._guard:
            ready = any(c.task_id == parent for c in gateway._inflight.values())
        if ready:
            break
        time.sleep(.01)
    assert ready
    client.post(f'/tasks/{parent}/cancel', headers=HEADERS)
    assert client.get('/fan/next', headers=HEADERS).text == 'NONE'
    thread.join(2)
    assert not thread.is_alive() and not results[0].json()['ok']


def test_live_owned_script_can_finish_native_apis_after_parent_reply(client):
    parent = task(client)
    headers = {**HEADERS, 'X-Bridge-Task': parent}
    assert client.post('/tools/ahk_script_write', headers=headers, json={'name': 'owned.ahk', 'source': '#Requires AutoHotkey v2.0\nSleep(60000)\n'}).json()['ok']
    run = client.post('/tools/ahk_script_run', headers=headers, json={'name': 'owned.ahk'}).json()
    try:
        with sqlite3.connect(gateway.DB) as db:
            db.execute("UPDATE tasks SET status='complete' WHERE id=?", (parent,))
        assert client.post('/tools/fan_capabilities', headers=headers, json={}).status_code == 409
        assert client.post('/tools/fan_capabilities', headers={**headers, 'X-Bridge-Run': 'unknown'}, json={}).status_code == 409
        owned = {**headers, 'X-Bridge-Run': run['run_id']}
        thread, results, (call_id, _, encoded) = fan_call(client, 'fan_ocr', {}, owned)
        assert json.loads(unquote(encoded))['_run_id'] == run['run_id']
        client.post('/fan/result', headers=HEADERS, data={'id': call_id, 'result': '{"ok":true,"text":"observed"}'})
        thread.join(2)
        assert not thread.is_alive() and results[0].json()['text'] == 'observed'
        assert client.post(f'/tasks/{parent}/cancel', headers=HEADERS).json()['status'] == 'cancelled'
        assert automation.status(run['run_id'])['status'] == 'cancelled'
        assert client.post('/tools/fan_ocr', headers=owned, json={}).status_code == 409
    finally:
        automation.cancel_for_task(parent)


def test_per_tool_required_optional_and_unknown_fields(client):
    assert client.post('/tools/fan_window_inspect', headers=HEADERS, json={'hwnd': 10, 'unexpected': 1}).status_code == 422
    assert client.post('/tools/fan_workflow_save', headers=HEADERS, json={'name': 'x'}).status_code == 422
    assert client.post('/tools/fan_pattern_search', headers=HEADERS, json={'name': 'x', 'err1': 1.01}).status_code == 422
    assert client.post('/tools/fan_library_read', headers=HEADERS, json={'path': 'lib/FindText.ahk', 'line_count': 251}).status_code == 422
