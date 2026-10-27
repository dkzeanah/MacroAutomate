"""Evidence must not turn repetition, a cached proof, or model prose into success."""
import subprocess
import pytest
from bridge import agent, automation, context_map, library, reuse


@pytest.mark.parametrize('prompt', ['continue', 'continue last instructions. show when done', 'resume previous task'])
def test_missing_continuation_context_uses_no_model_or_tool(monkeypatch, prompt):
    monkeypatch.setattr(agent, 'db_write', lambda *args: None)
    monkeypatch.setattr(agent, 'OpenAI', lambda **kwargs: pytest.fail('Missing context must not be guessed by a model'))
    monkeypatch.setattr(agent, 'request_tool', lambda *args, **kwargs: pytest.fail('Unrelated tools must not run'))
    assert 'No model or automation calls' in agent.run_prompt(prompt, task_id='fixture')


def test_actual_continue_task_is_not_mistaken_for_bare_continuation():
    assert not reuse.bare_continuation('continue writing a safe VS Code file')


def test_exact_saved_replay_bypasses_model_without_rewriting_source(monkeypatch):
    saved = library.save('Lesson.ahk','script','#Requires AutoHotkey v2.0\n', metadata={'sha256':'known'})
    monkeypatch.setattr(agent,'check_cancelled',lambda _:None)
    monkeypatch.setattr(agent,'db_write',lambda *args:None)
    monkeypatch.setattr(agent,'OpenAI',lambda **kwargs:pytest.fail('Replay must not construct a model client'))
    calls=[]
    def call(name,args,**kwargs):
        calls.append((name,args))
        return {'ok':True,'status':'complete','exit_code':0,'stdout':'checked 42'}
    monkeypatch.setattr(agent,'request_tool',call)
    answer=agent.run_prompt('replay saved tool Lesson.ahk inputs {"mode":"replay"}',task_id='fixture')
    assert len(calls)==1 and calls[0][0]=='ahk_script_run' and calls[0][1]['inputs']=={'mode':'replay'}
    assert library.get('Lesson.ahk')['revision']==saved['revision']
    assert 'revision 1' in answer and 'checked 42' in answer


def test_saved_replay_is_exact_and_unknown_names_do_not_fall_back():
    assert reuse.direct_saved_plan('Please modify Lesson.ahk and run it') is None
    with pytest.raises(ValueError):
        reuse.direct_saved_plan('replay saved tool Missing.ahk inputs {}')


def test_failed_local_execution_is_not_a_successful_completed_task(monkeypatch):
    library.save('Stopped.ahk','script','ExitApp(2)')
    monkeypatch.setattr(agent,'check_cancelled',lambda _:None)
    monkeypatch.setattr(agent,'db_write',lambda *a:None)
    monkeypatch.setattr(agent,'OpenAI',lambda **k:pytest.fail('Failure must not trigger model fallback'))
    monkeypatch.setattr(agent,'request_tool',lambda *a,**k:{'ok':False,'status':'error','exit_code':2,'error':'Foreground changed'})
    answer=agent.run_prompt('replay saved tool Stopped.ahk inputs {}',task_id='fixture')
    assert answer.task_status=='error' and 'exit code: 2' in answer


def test_output_limit_discards_partial_tool_and_continues_once(monkeypatch):
    from types import SimpleNamespace as NS
    class Stream:
        def __init__(self,choices): self.choices=choices
        def __iter__(self):
            yield NS(usage=None,choices=self.choices)
        def close(self): pass
    partial=NS(index=0,id='partial',function=NS(name='ahk_script_write',arguments='{"name":"unfinished'))
    streams=[Stream([NS(finish_reason='length',delta=NS(content=None,reasoning_content='partial reasoning',tool_calls=[partial]))]),
             Stream([NS(finish_reason='stop',delta=NS(content='Recovered without executing partial code',reasoning_content=None,tool_calls=[]))])]
    requests=[]
    def create(**request):
        requests.append(request)
        return streams.pop(0)
    monkeypatch.setenv('DEEPSEEK_API_KEY','synthetic')
    monkeypatch.delenv('DEEPSEEK_MAX_OUTPUT_TOKENS',raising=False)
    monkeypatch.setattr(agent,'check_cancelled',lambda _:None)
    monkeypatch.setattr(agent,'db_write',lambda *args:None)
    monkeypatch.setattr(agent,'OpenAI',lambda **kwargs:NS(chat=NS(completions=NS(create=create))))
    monkeypatch.setattr(agent,'request_tool',lambda *args,**kwargs:pytest.fail('Partial tool must never execute'))
    assert agent.run_prompt('Write a safe tool',task_id='fixture').startswith('Recovered')
    assert len(requests)==2 and requests[0]['max_tokens']==32768
    assert not any(m.get('tool_calls') for m in requests[1]['messages'])


def test_outcomes_revision_scope_and_counterexamples():
    args = {'name': 'demo', 'steps': [{'action': 'Wait'}]}
    library.save('workflow:demo', 'workflow', 'revision-one')
    reuse.observe('fan_workflow_run', args, {'ok': True, 'completed': 1})
    first = reuse.search('demo')['records'][0]
    assert first['successes'] == 1 and first['verified'] == 0
    reuse.observe('fan_workflow_run', args, {'ok': False, 'verified': True, 'error': 'target changed'})
    assert reuse.search('demo')['records'][0]['state'] == 'contradicted / review'
    library.save('workflow:demo', 'workflow', 'revision-two')
    reuse.observe('fan_workflow_run', args, {'ok': True, 'completed': 1})
    records = reuse.search('demo')['records']
    assert len(records) == 2 and len({r['artifact_hash'] for r in records}) == 2
    assert sum(r['failures'] for r in records) == 1


def test_pixel_stability_and_cached_validation_are_not_new_proof():
    for stable in (False, True):
        reuse.observe('fan_pattern_search', {'name': 'icon'}, {'ok': True, 'matches': [1],
            'frame': {'geometry_stable': True, 'content_stable': stable}})
    assert reuse.search('icon')['records'][0]['verified'] == 1
    for reused in (False, True):
        reuse.observe('ahk_script_validate', {'name': 'valid.ahk'},
            {'ok': True, 'syntax_valid': True, 'source_hash': 'abc', 'reused': reused})
    assert reuse.search('valid.ahk')['records'][0]['verified'] == 1


def test_syntax_validation_does_not_execute_and_invalidates_changed_source(tmp_path, monkeypatch):
    monkeypatch.setattr(automation, 'SCRIPTS', tmp_path / 'scripts')
    monkeypatch.setattr(automation, 'unified_mode', lambda: False)
    output = tmp_path / 'must-not-exist.txt'
    args = {'name': 'syntax.ahk', 'source': '#Requires AutoHotkey v2.0\nFileAppend("bad", "' + str(output) + '")\n'}
    assert automation.dispatch('ahk_script_write', args)['ok']
    first = automation.dispatch('ahk_script_validate', {'name': 'syntax.ahk'})
    assert first['syntax_valid'] and not first['reused'] and not output.exists()
    assert automation.dispatch('ahk_script_validate', {'name': 'syntax.ahk'})['reused']
    assert automation.dispatch('ahk_script_write', {**args, 'source': '#Requires AutoHotkey v2.0\nif (\n', 'overwrite': True})['ok']
    assert not automation.dispatch('ahk_script_validate', {'name': 'syntax.ahk'})['ok']
    assert not output.exists()


@pytest.mark.parametrize('verified', [True, False])
def test_explicit_taskbar_request_skips_model_and_never_repeats_uncertain_click(monkeypatch, verified):
    calls = []
    monkeypatch.delenv('DEEPSEEK_API_KEY', raising=False)
    monkeypatch.setattr(agent, 'check_cancelled', lambda _: None)
    monkeypatch.setattr(agent, 'db_write', lambda *args: None)
    def observed(name, args, **kwargs):
        calls.append((name, args))
        return {'ok': int(verified), 'verified': int(verified), 'action_performed': 1, 'name': 'SciTE4AutoHotkey'}
    monkeypatch.setattr(agent, 'request_tool', observed)
    answer = agent.run_prompt('open scite4ahk', task_id='test')
    assert len(calls) == 1 and calls[0][0] == 'fan_taskbar_open'
    assert ('unverified' in answer) is not verified


def test_restricted_tasks_cannot_use_direct_control(monkeypatch):
    monkeypatch.delenv('DEEPSEEK_API_KEY', raising=False)
    monkeypatch.setattr(agent, 'request_tool', lambda *a, **kw: pytest.fail('Unexpected desktop action'))
    with pytest.raises(RuntimeError, match='API key'):
        agent.run_prompt('open scite4ahk', task_id='test', allowed_tools={'fan_window_inspect'})


def test_delayed_taskbar_request_never_falls_back_or_retries(monkeypatch):
    calls = []
    monkeypatch.setattr(agent, 'check_cancelled', lambda _: None)
    monkeypatch.setattr(agent, 'db_write', lambda *args: None)
    monkeypatch.setattr(agent, 'OpenAI', lambda **kwargs: pytest.fail('Timeout must not trigger model fallback'))
    def delayed(*args, **kwargs):
        calls.append(args)
        raise TimeoutError('Native capture busy')
    monkeypatch.setattr(agent, 'request_tool', delayed)
    assert 'No automatic retry' in agent.run_prompt('open scite4ahk', task_id='test')
    assert len(calls) == 1


def test_saved_multistep_rehearsal_bypasses_model_and_keeps_fixture_scope(monkeypatch):
    calls = []
    monkeypatch.delenv('DEEPSEEK_API_KEY', raising=False)
    monkeypatch.setattr(agent, 'check_cancelled', lambda _: None)
    monkeypatch.setattr(agent, 'db_write', lambda *args: None)
    monkeypatch.setattr(agent, 'OpenAI', lambda **kwargs: pytest.fail('Saved replay must not create a model client'))
    def run(name, args, **kwargs):
        calls.append((name,args))
        return {'ok': 1, 'verified': 1, 'completed': 3, 'scope': 'isolated_fixture_only', 'original_app_verified': 0}
    monkeypatch.setattr(agent, 'request_tool', run)
    answer = agent.run_prompt('rehearse Learned rehearsal 38-1234abcd',task_id='fixture')
    assert calls == [('fan_learning_rehearse', {'name':'Learned rehearsal 38-1234abcd'})]
    assert '3 steps' in answer and 'Original application behavior remains unverified' in answer


def test_context_map_defaults_to_embedded_fan_workspace(tmp_path, monkeypatch):
    root=tmp_path/'fan'/'DeepSeekBridge'
    harness=root.parent/'harness'
    (harness/'.venv/Scripts').mkdir(parents=True)
    (harness/'.venv/Scripts/python.exe').touch()
    (harness/'.atlas').mkdir()
    (harness/'.atlas/atlas.sqlite3').touch()
    monkeypatch.delenv('FAN_CONTEXT_WORKSPACE',raising=False)
    monkeypatch.setattr(context_map,'ROOT',root)
    def run(command, **kwargs):
        assert kwargs['cwd']==harness
        assert str(harness) in command
        return subprocess.CompletedProcess(command,0,'slice','')
    monkeypatch.setattr(context_map.subprocess,'run',run)
    assert context_map.dispatch('context_map_get',{'address':'@codetool/atlas:cli.py#main'})['ok']


def test_context_map_uses_argument_vector_and_bounded_reference(tmp_path, monkeypatch):
    (tmp_path / '.venv' / 'Scripts').mkdir(parents=True)
    (tmp_path / '.venv' / 'Scripts' / 'python.exe').touch()
    (tmp_path / '.atlas').mkdir()
    (tmp_path / '.atlas' / 'atlas.sqlite3').touch()
    monkeypatch.setenv('FAN_CONTEXT_WORKSPACE', str(tmp_path))
    calls = []
    def run(command, **kwargs):
        calls.append(command)
        assert not kwargs.get('shell')
        return subprocess.CompletedProcess(command, 0, 'x' * 14000, '')
    monkeypatch.setattr(context_map.subprocess, 'run', run)
    result = context_map.dispatch('context_map_find', {'query': 'dome; unsafe()'})
    assert calls[0][-1] == 'dome; unsafe()' and result['truncated']
    assert len(result['reference']) == 12000
    assert not context_map.dispatch('context_map_get', {'address': 'C:\\arbitrary.py'})['ok']
