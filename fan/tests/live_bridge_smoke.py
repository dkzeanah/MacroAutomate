"""Opt-in local smoke check against the running Fan bridge; no model API call.

Installs a reusable read-only API diagnostic in the agent's normal tool index.
Does not click/type or change the user's workflows, patterns or input settings.
"""
import json
from pathlib import Path
from urllib.request import Request, urlopen

PROJECT = Path(__file__).resolve().parents[2]
ROOT = PROJECT / 'fan' / 'DeepSeekBridge'
config = dict(line.split('=', 1) for line in (ROOT / '.env').read_text(encoding='utf-8-sig').splitlines()
              if '=' in line and not line.startswith('#'))
base = 'http://127.0.0.1:' + config.get('BRIDGE_PORT', '8765')


def call(path, payload=None):
    encoded = None if payload is None else json.dumps(payload, ensure_ascii=False).encode('utf-8')
    request = Request(base + path, data=encoded,
                      headers={'X-Bridge-Token': config['BRIDGE_TOKEN'],
                               'Content-Type': 'application/json; charset=utf-8'})
    with urlopen(request, timeout=45) as response:
        return json.load(response)


def main():
    health = call('/health')
    assert health['healthy'] and health['windows_worker'] and health['fan_connected'], health
    assert health['agent_mode'] == 'unified'
    print(f"PASS Unified live bridge: {len(health['tools'])} tools, Fan and worker connected")
    capabilities = call('/tools/fan_capabilities', {})
    assert capabilities.get('ok') and capabilities.get('workflow_actions'), capabilities
    print(f"PASS Native composer API: {len(capabilities['workflow_actions'])} action definitions")
    windows = call('/tools/window_list', {})
    target = next(window for window in windows['windows'] if window['title'].startswith('Macro Automator v9'))
    inspection = call('/tools/fan_window_inspect', {'hwnd': target['hwnd'], 'include_image': False,
                                                   'include_ocr': False, 'limit': 10})
    assert inspection.get('ok') and inspection['frame']['hwnd'] == target['hwnd'], inspection
    assert inspection['frame']['region']['w'] > 0 and inspection['controls'], inspection
    print('PASS Live window inspection returns observed controls and absolute geometry')
    library = call('/tools/fan_library_search', {'query': 'OCR.FromRect', 'limit': 3})
    assert library.get('ok'), library
    print('PASS Native AHK library search')
    patterns = call('/tools/fan_pattern_list', {'query': ''})
    assert patterns.get('ok'), patterns
    print('PASS Native saved pattern catalog')
    source = ('#Requires AutoHotkey v2.0\n'
              f'#Include {PROJECT / "lib" / "FanBridgeClient.ahk"}\n'
              'try {\n'
              '    capabilities := FanBridge.Capabilities()\n'
              '    settings := FanBridge.Call("fan_input_settings_get")\n'
              '    if !capabilities.Get("ok", false) || !settings.Get("ok", false)\n'
              '        throw Error("Native API diagnostic failed")\n'
              '    FileAppend("Fan native API diagnostic succeeded`n", "*", "UTF-8")\n'
              '    ExitApp(0)\n'
              '} catch as err {\n'
              '    FileAppend(err.Message . "`n", "**", "UTF-8")\n'
              '    ExitApp(1)\n'
              '}\n')
    written = call('/tools/ahk_script_write', {
        'name': 'fan_api_diagnostic.ahk', 'source': source, 'overwrite': True,
        'description': 'Read-only self-check of the running Fan native API from a generated AHK process.',
        'tags': ['fan', 'diagnostic', 'read-only'],
        'usage': 'ahk_script_run(name="fan_api_diagnostic.ahk", wait=true)',
        'examples': ['Verify that a generated script can reach live Fan capabilities and input settings.'],
        'input_schema': {'type': 'object', 'additionalProperties': False}})
    assert written.get('ok') and written.get('indexed'), written
    result = call('/tools/ahk_script_run', {'name': 'fan_api_diagnostic.ahk', 'wait': True,
                                         'timeout_seconds': 30})
    assert result.get('ok') and result['exit_code'] == 0, result
    assert 'Fan native API diagnostic succeeded' in result['stdout'], result
    print('PASS Authored, indexed and actually executed AHK script calling live Fan APIs')
    record = call('/tools/tool_catalog_get', {'name': 'fan_api_diagnostic.ahk'})
    assert record.get('ok') and record['record']['metadata']['input_schema'], record
    revisions = call('/tools/tool_catalog_revisions', {'name': 'fan_api_diagnostic.ahk'})
    assert revisions.get('ok') and revisions['revisions'], revisions
    print('PASS Persistent tool metadata, input schema and indexed source revisions')


if __name__ == '__main__':
    main()
