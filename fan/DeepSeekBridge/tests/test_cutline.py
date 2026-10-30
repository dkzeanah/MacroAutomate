"""Cross-project transport tests: bounded schemas, auth, and no native worker dependency."""
import json
from pathlib import Path
import httpx
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from bridge import catalog, cutline, gateway
from bridge.install_harness import install, install_atlas_persona, optional_fan_startup


def test_contract_is_shared_by_mcp_and_agent():
    from bridge import mcp_server
    assert set(cutline.TOOL_DEFINITIONS) <= set(catalog.TOOLS)
    assert callable(mcp_server.proxy('cutline_call', cutline.MediaCall, 'call'))
    for payload in [{'method': 'ping', 'timeout': 181}, {'method': 'ping', 'params': []},
                    {'method': 'ping', 'extra': True}]:
        with pytest.raises(ValidationError):
            catalog.validate('cutline_call', payload)
    with pytest.raises(ValidationError):
        catalog.validate('cutline_job_cancel', {'job_id': '../health'})


def test_configuration_stays_loopback(tmp_path, monkeypatch):
    path = tmp_path/'api.token'; path.write_text('synthetic-local-token')
    monkeypatch.setenv('CUTLINE_API_TOKEN_FILE', str(path))
    monkeypatch.delenv('CUTLINE_API_TOKEN', raising=False)
    monkeypatch.setenv('CUTLINE_API_URL', 'https://outside.example')
    with pytest.raises(ValueError, match='loopback'):
        cutline.configuration()
    monkeypatch.setenv('CUTLINE_API_URL', 'http://127.0.0.1:8780')
    assert cutline.configuration() == ('http://127.0.0.1:8780', 'synthetic-local-token')


def test_authenticated_dispatch_uses_job_endpoints(monkeypatch):
    monkeypatch.setattr(cutline, 'configuration', lambda: ('http://127.0.0.1:8780', 'synthetic-token'))
    real_client = httpx.Client
    seen = []
    def handle(request):
        seen.append((request.method, request.url.path, request.headers['X-Cutline-Token']))
        return httpx.Response(202, json={'id': 'a'*32, 'status': 'queued'})
    monkeypatch.setattr(cutline.httpx, 'Client', lambda **kwargs: real_client(transport=httpx.MockTransport(handle), **kwargs))
    result = cutline.dispatch('cutline_job_submit', {'method': 'motion.render', 'params': {'scene': {}}})
    assert result['status'] == 'queued'
    cutline.dispatch('cutline_job_cancel', {'job_id': 'a'*32})
    assert seen == [('POST', '/v1/jobs', 'synthetic-token'), ('POST', '/v1/jobs/'+'a'*32+'/cancel', 'synthetic-token')]


def test_gateway_routes_media_without_fan_queue(tmp_path, monkeypatch):
    monkeypatch.setattr(gateway, 'DB', tmp_path/'bridge.sqlite3')
    monkeypatch.setattr(gateway, 'TOKEN', 'synthetic-token')
    gateway.init_db()
    monkeypatch.setattr(cutline, 'dispatch', lambda name, args: {'ok': True, 'methods': ['motion.render']})
    with TestClient(gateway.app) as client:
        assert client.post('/tools/cutline_capabilities', json={}).status_code == 401
        response = client.post('/tools/cutline_capabilities', json={}, headers={'X-Bridge-Token': 'synthetic-token'})
        assert response.status_code == 200
        assert response.json()['methods'] == ['motion.render']


def test_profile_install_preserves_settings_and_is_idempotent(tmp_path):
    (tmp_path/'cordis.yml').write_text('[]\n')
    patch = tmp_path/'cordis.patch.yml'
    patch.write_text('- id: session-query-sqlite\n  config:\n    path: keep.sqlite\n')
    result = install(tmp_path)
    assert result['installed']
    assert 'keep.sqlite' in patch.read_text()
    assert 'mcp-fan-cutline' in patch.read_text()
    assert Path(result['backup']).read_text().endswith('path: keep.sqlite\n')
    assert not install(tmp_path)['installed']
    assert patch.read_text().count('- insert:') == 1
    assert 'serverName: fan' in patch.read_text()
    assert 'failOnStartupError: false' in patch.read_text()


def test_persona_install_preserves_an_explicit_existing_persona(tmp_path):
    path = tmp_path/'cordis.patch.yml'
    path.write_text('- id: system-prompt\n  config:\n    persona: Existing instructions\n')
    before = path.read_bytes()
    with pytest.raises(ValueError, match='already declares a persona'):
        install_atlas_persona(tmp_path)
    assert path.read_bytes() == before


def test_migrate_only_fan_startup_policy_with_backup(tmp_path):
    (tmp_path/'cordis.yml').write_text('[]\n')
    path = tmp_path/'cordis.patch.yml'
    original = ('- insert:\n    - id: mcp-fan-cutline\n      config:\n'
                '        failOnStartupError: true # Fan is optional\n'
                '    - id: other-server\n      config:\n        failOnStartupError: true\n'
                '- id: system-prompt\n  config:\n    persona: keep my persona\n')
    path.write_text(original)
    result = install(tmp_path)
    assert result['updated'] and not result['installed']
    assert Path(result['backup']).read_text() == original
    current = path.read_text()
    assert 'failOnStartupError: false # Fan is optional' in current
    assert current.count('failOnStartupError: true') == 1
    assert 'keep my persona' in current
    assert not install(tmp_path)['updated']


def test_ambiguous_fan_entry_is_not_rewritten():
    with pytest.raises(ValueError, match='Expected one'):
        optional_fan_startup('- id: other-server\n  config:\n    failOnStartupError: true\n')
