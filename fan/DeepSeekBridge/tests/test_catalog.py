"""Saved-tool reuse, source revisions and parameterized AHK execution."""
import json
from pathlib import Path

from bridge import automation, catalog, library, agent


def test_metadata_and_source_revisions_remain_searchable(tmp_path, monkeypatch):
    monkeypatch.setattr(automation, 'SCRIPTS', tmp_path / 'scripts')
    first = '#Requires AutoHotkey v2.0\n; revision one\nExitApp\n'
    second = first.replace('one', 'two')
    result = automation.dispatch('ahk_script_write', {'name': 'map_fields.ahk', 'source': first,
                                'description': 'Map form controls using OCR', 'tags': ['forms', 'ocr'],
                                'usage': 'ahk_script_run(name="map_fields.ahk",inputs={"page":"math"})',
                                'examples': ['Map a Pearson math form']})
    assert result['indexed'] and result['revision'] == 1
    assert automation.dispatch('ahk_script_write', {'name': 'map_fields.ahk', 'source': second, 'overwrite': True})['revision'] == 2
    found = library.search('Pearson')[0]
    assert found['description'] == 'Map form controls using OCR'
    assert library.revision('map_fields.ahk', 1)['content'] == first
    assert library.get('map_fields.ahk')['content'] == second
    assert 'map_fields.ahk' in agent.system_prompt() and 'Map form controls' in agent.system_prompt()


def test_parameterized_script_validates_and_receives_json_inputs(tmp_path, monkeypatch):
    monkeypatch.setattr(automation, 'SCRIPTS', tmp_path / 'scripts')
    sdk = Path(__file__).resolve().parents[3] / 'lib' / 'FanBridgeClient.ahk'
    source = ('#Requires AutoHotkey v2.0\n#Include ' + str(sdk) + '\n'
              'args := FanBridgeJsonDecode(EnvGet("FAN_TOOL_INPUT"))\n'
              'FileAppend(args["message"], args["output"], "UTF-8")\nExitApp\n')
    schema = {'type': 'object', 'properties': {'message': {'type': 'string', 'minLength': 1},
              'output': {'type': 'string'}}, 'required': ['message', 'output'], 'additionalProperties': False}
    assert automation.dispatch('ahk_script_write', {'name': 'parameterized.ahk', 'source': source,
                                                  'input_schema': schema})['ok']
    first_output, second_output = tmp_path / 'first.txt', tmp_path / 'second.txt'
    invalid = automation.dispatch('ahk_script_run', {'name': 'parameterized.ahk', 'wait': True,
                                                   'inputs': {'message': 7, 'output': str(first_output)}})
    assert not invalid['ok'] and 'Invalid tool inputs' in invalid['error']
    assert not first_output.exists()
    for output, text in ((first_output, 'first α'), (second_output, 'second café')):
        result = automation.dispatch('ahk_script_run', {'name': 'parameterized.ahk', 'wait': True,
                                    'inputs': {'message': text, 'output': str(output)}})
        assert result['ok'] and result['exit_code'] == 0, result
        assert output.read_text(encoding='utf-8-sig') == text


def test_external_input_schema_refs_cannot_fetch_network(tmp_path, monkeypatch):
    monkeypatch.setattr(automation, 'SCRIPTS', tmp_path / 'scripts')
    result = automation.dispatch('ahk_script_write', {'name': 'bad_schema.ahk', 'source': '#Requires AutoHotkey v2.0\nExitApp',
              'input_schema': {'type': 'object', 'properties': {'x': {'$ref': 'https://untrusted.example/schema'}}}})
    assert not result['ok'] and 'local' in result['error']
    assert not (automation.SCRIPTS / 'bad_schema.ahk').exists()


def test_manual_memory_is_inference_and_native_evidence_is_observed():
    note = library.dispatch('knowledge_store', {'name': 'layout', 'content': 'The button might be below the field.'})
    assert note['record']['metadata']['source_kind'] == 'inference'
    library.observe('fan_ocr', {'hwnd': 20}, {'ok': True, 'text': 'Check answer', 'words': [{'x': 20, 'y': 30}]})
    evidence = library.search('Check answer', knowledge_only=True)[0]
    assert evidence['metadata']['source_kind'] == 'observed'


def test_shared_exact_signatures_include_optional_fields():
    tools = {item['function']['name']: item['function'] for item in catalog.functions()}
    assert 'ahk_script_run' in tools and 'fan_ocr' in tools
    assert 'name' not in tools['fan_pattern_search']['parameters'].get('required', [])
    assert {'name', 'text'} <= tools['fan_pattern_search']['parameters']['properties'].keys()
    assert tools['ahk_script_run']['parameters']['required'] == ['name']
    assert 'inputs' in tools['ahk_script_run']['parameters']['properties']
    assert 'input_schema' in tools['ahk_script_write']['parameters']['properties']
    bounded = agent.bounded_result({'ok': True, 'controls': [{'text': 'x' * 1000}] * 1000})
    assert bounded['truncated'] and isinstance(bounded['controls'], list)
    assert bounded['controls'][0]['text'] == 'x' * 1000
    assert len(json.dumps(bounded, ensure_ascii=False)) <= 28000
