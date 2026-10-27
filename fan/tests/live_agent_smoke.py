"""Explicit opt-in live DeepSeek check; uses the configured paid API.

Only asks the agent to execute the previously verified read-only diagnostic.
Credentials are read by the running bridge, never by this test.
"""
import time
from live_bridge_smoke import call

prompt = ('Execute the existing read-only tool fan_api_diagnostic.ahk using '
          'ahk_script_run(name="fan_api_diagnostic.ahk", wait=true, timeout_seconds=30). '
          'It is already saved and verified; do not modify it, create other scripts, '
          'change settings or perform mouse/keyboard/window actions. '
          'Report the actual captured stdout and process exit code in one short sentence.')
task = call('/tasks', {'prompt': prompt})['id']
deadline = time.monotonic() + 180
try:
    while time.monotonic() < deadline:
        state = call('/tasks/' + task)
        if state['status'] in ('complete', 'error', 'cancelled'):
            break
        time.sleep(1)
    else:
        raise RuntimeError('Live model verification timed out')
    events = call('/tasks/' + task + '/events')['events']
    results = [item['payload'] for item in events if item['kind'] == 'agent_tool_result'
               and item['payload'].get('name') == 'ahk_script_run']
    assert state['status'] == 'complete', state.get('response', state['status'])
    assert results, 'Model did not call the actual script execution tool'
    result = results[-1]['result']
    assert result.get('ok') and result['exit_code'] == 0, result
    assert 'Fan native API diagnostic succeeded' in result['stdout'], result
    print('PASS Live DeepSeek agent called ahk_script_run and received successful native SDK output')
    print('Reply:', state['response'])
finally:
    if call('/tasks/' + task)['status'] in ('queued', 'running'):
        call('/tasks/' + task + '/cancel', {})
