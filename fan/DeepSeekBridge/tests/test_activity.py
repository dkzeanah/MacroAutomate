"""The indicator uses live state, not old conversation events or private arguments."""
import sqlite3
import threading
import time

from fastapi.testclient import TestClient
from bridge import gateway, automation

HEADERS = {'X-Bridge-Token': 'test-local-token'}


def test_activity_tracks_tools_and_task_lifecycle(tmp_path, monkeypatch):
    monkeypatch.setattr(gateway, 'DB', tmp_path / 'activity.sqlite3')
    monkeypatch.setattr(automation, 'active_runs', lambda: [])
    gateway.init_db()
    with TestClient(gateway.app) as client:
        assert client.get('/health').status_code == 401
        def activity():
            return client.get('/health', headers=HEADERS).json()['activity']
        task = client.post('/tasks', headers=HEADERS, json={'prompt': 'private task text'}).json()['id']
        assert activity() == {'running_tasks': 0, 'tools': [], 'application_runs': 0}
        with sqlite3.connect(gateway.DB) as db:
            db.execute("UPDATE tasks SET status='running' WHERE id=?", (task,))
        assert activity()['running_tasks'] == 1
        responses = []
        thread = threading.Thread(target=lambda: responses.append(client.post('/tools/text_type',
            headers={**HEADERS, 'X-Bridge-Task': task}, json={'text': 'private typed text'})))
        thread.start()
        try:
            for _ in range(100):
                wire = client.get('/worker/next', headers=HEADERS).text
                if wire != 'NONE':
                    break
                time.sleep(.01)
            else:
                raise AssertionError('No pending input call')
            state = activity()
            assert state == {'running_tasks': 1, 'tools': ['text_type'], 'application_runs': 0}
            assert 'private' not in str(state)
            client.post('/worker/result', headers=HEADERS,
                        data={'id': wire.split('\n')[0], 'result': '{"ok":true}'})
        finally:
            thread.join(2)
        assert not thread.is_alive() and responses[0].json()['ok']
        assert activity()['tools'] == []
        client.post('/tasks/' + task + '/cancel', headers=HEADERS)
        assert activity() == {'running_tasks': 0, 'tools': [], 'application_runs': 0}
