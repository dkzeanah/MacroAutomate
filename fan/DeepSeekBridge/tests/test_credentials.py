"""Existing credential stores are reused with environment precedence and no new writes."""
import json
from bridge import credentials

def test_environment_precedes_vault_and_cache(monkeypatch):
    monkeypatch.setenv('DEEPSEEK_API_KEY', 'synthetic-env')
    monkeypatch.setattr(credentials, 'windows_key', lambda target: (_ for _ in ()).throw(AssertionError('unexpected vault read')))
    assert credentials.resolve() == ('synthetic-env', 'environment')

def test_existing_cutline_cache_is_optional_and_read_only(tmp_path, monkeypatch):
    monkeypatch.delenv('DEEPSEEK_API_KEY', raising=False)
    monkeypatch.setattr(credentials, 'windows_key', lambda target: '')
    monkeypatch.setenv('CUTLINE_ROOT', str(tmp_path))
    assert credentials.resolve() == ('', 'not configured')
    path = tmp_path/'data'/'studio'/'llm_credentials.json'
    path.parent.mkdir(parents=True)
    path.write_text(json.dumps({'deepseek_api_key': 'synthetic-existing'}))
    before = path.read_bytes()
    assert credentials.resolve() == ('synthetic-existing', 'existing Cutline credential cache')
    assert path.read_bytes() == before
