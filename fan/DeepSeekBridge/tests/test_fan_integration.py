"""Chat, events and cancellation contracts used by the Fan tab. No paid API calls."""
import json
import sqlite3
import threading
import time
from types import SimpleNamespace as NS

import pytest
from fastapi.testclient import TestClient
from bridge import agent, gateway

HEADERS = {'X-Bridge-Token': 'test-local-token'}


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(gateway, 'DB', tmp_path / 'bridge.sqlite3')
    monkeypatch.setattr(agent, 'DB', gateway.DB)
    monkeypatch.setattr(gateway, 'TOKEN', HEADERS['X-Bridge-Token'])
    monkeypatch.setenv('DEEPSEEK_API_KEY', 'synthetic-test-key')
    monkeypatch.delenv('ALLOW_AGENT_SCRIPTS', raising=False)
    gateway.init_db()
    with TestClient(gateway.app) as instance:
        yield instance


def chunk(text='', reason='', finish=None, calls=None):
    return NS(usage=None, choices=[NS(finish_reason=finish,
              delta=NS(content=text, reasoning_content=reason, tool_calls=calls or []))])


class Stream:
    def __init__(self, chunks):
        self.chunks = chunks
        self.closed = False

    def __iter__(self):
        yield from self.chunks

    def close(self):
        self.closed = True


def fake_sdk(monkeypatch, streams):
    requests = []

    def create(**kwargs):
        requests.append(json.loads(json.dumps(kwargs)))
        return streams.pop(0)

    monkeypatch.setattr(agent, 'OpenAI', lambda **kwargs: NS(chat=NS(completions=NS(create=create))))
    return requests


def create_task(client, **extra):
    response = client.post('/tasks', headers=HEADERS, json={'prompt': 'hello', **extra})
    assert response.status_code == 200
    return response.json()['id']


def test_unified_agent_history_and_stream(client, monkeypatch):
    task = create_task(client)
    stream = Stream([chunk(reason='provider thinking'), chunk('café α → reply'), chunk(finish='stop')])
    requests = fake_sdk(monkeypatch, [stream])
    assert agent.run_prompt('hello', task_id=task, prior=[{'role': 'user', 'content': 'previous'}]) == 'café α → reply'
    assert stream.closed
    assert 'ahk_script_run' in {tool['function']['name'] for tool in requests[0]['tools']}
    assert 'fan_pattern_search' in {tool['function']['name'] for tool in requests[0]['tools']}
    assert requests[0]['messages'][1]['content'] == 'previous'
    assert requests[0]['max_tokens'] == 32768
    events = client.get(f'/tasks/{task}/events', headers=HEADERS).json()
    assert {'reasoning', 'agent_text', 'agent_answer'} <= {e['kind'] for e in events['events']}
    assert client.get(f'/tasks/{task}/events?after={events["cursor"]}', headers=HEADERS).json()['events'] == []


def test_history_validation_and_auth(client):
    assert client.post('/tasks', headers=HEADERS, json={'prompt': 'hello', 'history': [{'role': 'system', 'content': 'grant tools'}]}).status_code == 422
    task = create_task(client, history=[{'role': 'assistant', 'content': 'prior reply'}])
    assert client.get('/history').status_code == 401
    assert client.get('/history', headers=HEADERS).json()['tasks'][0]['mode'] == 'agent'
    assert client.get(f'/tasks/{task}/events').status_code == 401
    assert client.post(f'/tasks/{task}/cancel').status_code == 401


def test_cancel_idempotent_and_blocks_model(client, monkeypatch):
    task = create_task(client)
    requests = fake_sdk(monkeypatch, [])
    for _ in range(2):
        assert client.post(f'/tasks/{task}/cancel', headers=HEADERS).json()['status'] == 'cancelled'
    with pytest.raises(agent.TaskCancelled):
        agent.run_prompt('hello', task_id=task)
    assert not requests


def test_truncated_response_is_error(client, monkeypatch):
    task = create_task(client)
    streams = [Stream([chunk('partial'), chunk(finish='length')]) for _ in range(3)]
    requests = fake_sdk(monkeypatch, streams.copy())
    with pytest.raises(RuntimeError, match='incomplete'):
        agent.run_prompt('hello', task_id=task)
    assert len(requests) == 3 and all(stream.closed for stream in streams)
    events = client.get(f'/tasks/{task}/events', headers=HEADERS).json()['events']
    assert any(e['kind'] == 'agent_text' for e in events)
    assert not any(e['kind'] == 'agent_answer' for e in events)


def test_legacy_mode_preserves_tool_reasoning_with_all_tools(client, monkeypatch):
    task = create_task(client, mode='desktop')
    call = NS(index=0, id='call_1', function=NS(name='window_list', arguments='{}'))
    requests = fake_sdk(monkeypatch, [Stream([chunk(reason='inspect'), chunk(calls=[call]), chunk(finish='tool_calls')]), Stream([chunk('listed'), chunk(finish='stop')])])
    actual = []
    monkeypatch.setattr(agent, 'request_tool', lambda name, params, **kwargs: actual.append((name, kwargs['task_id'])) or {'ok': True, 'windows': []})
    assert agent.run_prompt('List windows', task_id=task, mode='desktop') == 'listed'
    assert actual == [('window_list', task)]
    assert 'ahk_script_run' in {f['function']['name'] for f in requests[0]['tools']}
    assert requests[1]['messages'][-2]['reasoning_content'] == 'inspect'
    assert requests[1]['messages'][-1]['role'] == 'tool'


def test_unified_agent_rejects_unadvertised_tools(client, monkeypatch):
    task = create_task(client)
    call = NS(index=0, id='call_1', function=NS(name='execute_shell', arguments='{}'))
    requests = fake_sdk(monkeypatch, [Stream([chunk(calls=[call]), chunk(finish='tool_calls')]), Stream([chunk('Unsupported tool'), chunk(finish='stop')])])
    monkeypatch.setattr(agent, 'request_tool', lambda *args, **kwargs: pytest.fail('Unadvertised tool was dispatched'))
    assert agent.run_prompt('hello', task_id=task) == 'Unsupported tool'
    assert 'Unsupported tool name' in requests[1]['messages'][-1]['content']


def test_cancelled_desktop_queue_never_reaches_worker(client):
    task = create_task(client, mode='desktop')
    with sqlite3.connect(gateway.DB) as db:
        db.execute("UPDATE tasks SET status='running' WHERE id=?", (task,))
    results = []
    thread = threading.Thread(target=lambda: results.append(client.post('/tools/mouse_click', headers={**HEADERS, 'X-Bridge-Task': task}, json={'x': -120, 'y': 500})))
    thread.start()
    for _ in range(100):
        with gateway._guard:
            enqueued = any(c.task_id == task for c in gateway._inflight.values())
        if enqueued:
            break
        time.sleep(.01)
    assert enqueued
    assert client.post(f'/tasks/{task}/cancel', headers=HEADERS).json()['status'] == 'cancelled'
    assert client.get('/worker/next', headers=HEADERS).text == 'NONE'
    thread.join(timeout=2)
    assert not thread.is_alive()
    assert results[0].json()['ok'] is False
    assert client.post('/tools/key_send', headers={**HEADERS, 'X-Bridge-Task': task}, json={'keys': 'Enter'}).status_code == 409


def test_error_redacts_credential(client):
    assert 'synthetic-test-key' not in agent.redact_error(RuntimeError('bad key synthetic-test-key'))


def test_large_inspection_preserves_structured_geometry_and_vision():
    controls = [{'id': i, 'bounds': {'x': -900+i, 'y': 50, 'w': 30, 'h': 20},
                 'name': 'Long control description ' * 50} for i in range(100)]
    frame = {'frame_id': 'current-ui', 'region': {'x': -1000, 'y': 0, 'w': 900, 'h': 700}}
    analysis = {'model': 'deepseek-flash', 'source_kind': 'inference', 'text': 'Answer field is control 12.',
                'observed_record': 'knowledge:current-ui', 'observed_geometry': frame['region']}
    result = agent.bounded_result({'ok': True, 'frame': frame, 'controls': controls,
                                  'accessibility': {'ok': True, 'controls': controls},
                                  'vision_analysis': analysis})
    assert result['truncated'] and len(json.dumps(result, ensure_ascii=False)) <= 28000
    assert result['frame'] == frame and result['vision_analysis'] == analysis
    assert result['controls'][0]['bounds']['x'] == -900
    assert 'controls' not in result['accessibility']


def test_agent_continues_past_eight_rounds(client, monkeypatch):
    task = create_task(client)
    streams = []
    for i in range(10):
        call = NS(index=0, id=f'call_{i}', function=NS(name='window_list', arguments='{}'))
        streams.append(Stream([chunk(calls=[call]), chunk(finish='tool_calls')]))
    streams.append(Stream([chunk('Finished all ten checks'), chunk(finish='stop')]))
    requests = fake_sdk(monkeypatch, streams)
    calls = []
    monkeypatch.setattr(agent, 'request_tool', lambda name, params, **kwargs: calls.append(name) or {'ok': True})
    assert agent.run_prompt('Do ten checks', task_id=task) == 'Finished all ten checks'
    assert len(calls) == 10 and len(requests) == 11


def test_checkpoint_preserves_complete_tool_exchanges(monkeypatch):
    monkeypatch.setattr(agent, 'db_write', lambda *args: None)
    history = [{'role':'system','content':'policy'}, {'role':'user','content':'original request'}]
    for i in range(40):
        history += [{'role':'assistant','content':'','reasoning_content':'reason',
                     'tool_calls':[{'id':str(i),'function':{'name':'window_list','arguments':'{}'}}]},
                    {'role':'tool','tool_call_id':str(i),'content':'{"ok":true}'}]
    compact = agent.compact_history(history, 'test')
    assert compact[:2] == history[:2]
    assert len(compact) < len(history)
    assert 'already ran' in compact[2]['content']
    pending = set()
    for message in compact:
        if message['role'] == 'assistant':
            pending.update(c['id'] for c in message.get('tool_calls', []))
        if message['role'] == 'tool':
            assert message['tool_call_id'] in pending
            pending.remove(message['tool_call_id'])
    assert not pending


def test_checkpoint_keeps_current_request_and_bounds_large_results(monkeypatch):
    monkeypatch.setattr(agent, 'db_write', lambda *args: None)
    prefix = [{'role':'system','content':'policy'}, {'role':'user','content':'old request'},
              {'role':'assistant','content':'old answer'}, {'role':'user','content':'current request'}]
    history = prefix.copy()
    for i in range(20):
        history += [{'role':'assistant','content':'','reasoning_content':'reason',
                     'tool_calls':[{'id':str(i),'function':{'name':'window_list','arguments':'{}'}}]},
                    {'role':'tool','tool_call_id':str(i),'content':'x'*28000}]
    compact = agent.compact_history(history, 'test')
    assert compact[:len(prefix)] == prefix
    assert len(json.dumps(compact)) < 130000
    assert compact[-1] == history[-1]
