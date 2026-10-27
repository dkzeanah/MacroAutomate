"""Workspace security and new tool contract tests; no Windows GUI needed."""
import os
import time
import pytest
from fastapi.testclient import TestClient
from bridge import automation, gateway


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(gateway, 'DB', tmp_path / 'log.sqlite3')
    monkeypatch.setattr(automation, 'SCRIPTS', tmp_path / 'scripts')
    monkeypatch.setattr(gateway, 'TOKEN', 'test-local-token')
    monkeypatch.delenv('ALLOW_AGENT_SCRIPTS', raising=False)
    gateway.init_db()
    with TestClient(gateway.app) as instance:
        yield instance


def call(client, name, data=None):
    return client.post('/tools/' + name, headers={'X-Bridge-Token': 'test-local-token'}, json=data or {})


def test_script_write_read_and_list(client):
    source = '#Requires AutoHotkey v2.0\n; test\nMsgBox "hi"\n'
    assert call(client, 'ahk_script_write', {'name': 'greet.ahk', 'source': source}).json()['ok']
    assert call(client, 'ahk_script_read', {'name': 'greet.ahk'}).json()['source'] == source
    assert 'greet.ahk' in call(client, 'ahk_script_list').json()['scripts']
    assert not call(client, 'ahk_script_write', {'name': 'greet.ahk', 'source': source}).json()['ok']
    assert call(client, 'ahk_script_write', {'name': 'greet.ahk', 'source': source, 'overwrite': True}).json()['ok']


def test_script_path_traversal_blocked(client):
    for name in ['../evil.ahk', 'C:\\evil.ahk', 'bad.ps1', 'x/y.ahk', '.ahk']:
        assert not call(client, 'ahk_script_write', {'name': name, 'source': '#Requires AutoHotkey v2.0\n'}).json()['ok']


def test_script_runs_by_default_with_actual_file_output(client, tmp_path):
    output = tmp_path / 'actual_execution.txt'
    source = '#Requires AutoHotkey v2.0\nFileAppend("bridge execution verified", "' + str(output) + '", "UTF-8")\nExitApp\n'
    assert call(client, 'ahk_script_write', {'name': 'greet.ahk', 'source': source}).json()['ok']
    result = call(client, 'ahk_script_run', {'name': 'greet.ahk', 'wait': True}).json()
    assert result['ok'] and result['status'] == 'complete' and result['exit_code'] == 0
    assert output.read_text(encoding='utf-8-sig') == 'bridge execution verified'


def test_async_script_remains_running_until_cancelled(client):
    source = '#Requires AutoHotkey v2.0\nSleep(60000)\nExitApp\n'
    assert call(client, 'ahk_script_write', {'name': 'background.ahk', 'source': source}).json()['ok']
    result = call(client, 'ahk_script_run', {'name': 'background.ahk', 'timeout_seconds': 1}).json()
    try:
        assert result['status'] == 'running' and result['run_id']
        time.sleep(1.1)
        assert call(client, 'ahk_script_status', {'run_id': result['run_id']}).json()['status'] == 'running'
    finally:
        stopped = call(client, 'ahk_script_cancel', {'run_id': result['run_id']}).json()
    assert stopped['status'] == 'cancelled' and stopped['exit_code'] is not None


def test_explicit_wait_timeout_stops_own_process(client):
    assert call(client, 'ahk_script_write', {'name': 'waiter.ahk', 'source': '#Requires AutoHotkey v2.0\nSleep(60000)\n'}).json()['ok']
    result = call(client, 'ahk_script_run', {'name': 'waiter.ahk', 'wait': True, 'timeout_seconds': 1}).json()
    assert result['status'] == 'timed_out' and result['timed_out']


def test_script_requires_v2(client):
    assert not call(client, 'ahk_script_write', {'name': 'greet.ahk', 'source': 'MsgBox "Hi"'}).json()['ok']


def test_missing_arguments(client):
    assert call(client, 'ahk_script_run', {'name': '../bad.ahk'}).json()['ok'] is False
    assert call(client, 'mouse_click', {'x': -20001, 'y': 100}).status_code == 422
    assert call(client, 'mouse_click', {'x': 20, 'y': 10, 'unexpected': 1}).status_code == 422
