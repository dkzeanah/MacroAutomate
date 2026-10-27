"""Approved job evidence cannot escape its origin, destination or payload scope."""
import sqlite3
from fastapi.testclient import TestClient
import pytest
from bridge import gateway, job_sharing as sharing, page_learner, job_applications, catalog

HEADERS = {'X-Bridge-Token': 'test-local-token', 'X-Bridge-Task': 'job-task'}


def running_task(tmp_path, monkeypatch):
    monkeypatch.setattr(gateway, 'DB', tmp_path / 'gateway.sqlite3')
    gateway.init_db()
    with sqlite3.connect(gateway.DB) as db:
        db.execute("INSERT INTO tasks(id,prompt,status,mode,created_at) VALUES('job-task','Learn job application page','running','agent','now')")


def page(url, identity):
    return page_learner.build({'ok': True, 'photo_ref': 'photo:1',
        'frame': {'frame_id': identity, 'title': 'Job test page', 'region': {'x': 0, 'y': 0, 'w': 400, 'h': 300}},
        'controls': [{'id': 1, 'role': 'document', 'name': 'Job', 'value': url,
                      'bounds': {'x': 0, 'y': 0, 'w': 400, 'h': 300}, 'accessibility_path': '1'}]})


def test_destination_origin_and_revocation_are_enforced(monkeypatch):
    sharing.save(True, ['linkedin.com'])
    assert sharing.url_allowed('https://www.linkedin.com/feed/')
    for url in ('http://linkedin.com/feed/', 'https://linkedin.com.evil.test/feed/', 'https://youtube.com/',
                'https://user:password@linkedin.com/feed/', 'https://linkedin.com/messaging/thread/private',
                'https://linkedin.com/settings/privacy'):
        assert not sharing.url_allowed(url)
    for endpoint in ('http://api.deepseek.com', 'https://api.deepseek.com.evil.test', 'https://other.test',
                     'https://api.deepseek.com/alternate', 'https://key@api.deepseek.com'):
        assert not sharing.enabled(endpoint)
    monkeypatch.setenv('DEEPSEEK_BASE_URL', 'https://different-provider.test')
    assert not sharing.enabled() and not sharing.url_allowed('https://linkedin.com/feed/')
    monkeypatch.setenv('DEEPSEEK_BASE_URL', 'https://api.deepseek.com')
    sharing.save(False, ['linkedin.com'])
    assert not sharing.enabled()


def test_export_whitelist_omits_credentials_arbitrary_paths_and_protected_values():
    sharing.save(True, ['linkedin.com'])
    value = sharing.export_page({'url': 'https://linkedin.com/jobs', 'page_id': 'job', 'title': 'Job',
        'api_key': 'secret', 'image_path': 'unrelated.pdf'},
        [{'element_id': 'one', 'bounds': {'x': 1}, 'name': 'Email', 'value': 'omit raw value', 'api_key': 'secret'},
         {'element_id': 'two', 'protected': True, 'name': 'secret label', 'ocr_text': 'secret text'}])
    assert 'secret' not in str(value) and 'unrelated.pdf' not in str(value)
    assert value['elements'][0]['bounds'] == {'x': 1}
    assert 'value' not in value['elements'][0]
    profile = sharing.export_profile({'roles': ['software'], 'profile': {'email': 'synthetic@example.test', 'api_key': 'secret', 'resume_text': 'COMPLETE RESUME PAYLOAD'},
                                     'resume_path': 'private.pdf', 'api_key': 'secret', 'answers': {'API key': 'secret'}})
    assert 'resume_path' not in profile and 'api_key' not in profile
    assert 'secret' not in str(profile)
    assert 'COMPLETE RESUME PAYLOAD' not in str(profile)


def test_gateway_denies_unapproved_maps_and_filters_page_inventory(tmp_path, monkeypatch):
    running_task(tmp_path, monkeypatch)
    sharing.save(True, ['linkedin.com'])
    page('https://linkedin.com/jobs', 'approved')
    page('https://outside.test/private', 'private')
    with TestClient(gateway.app) as client:
        denied = client.post('/tools/fan_page_get', headers=HEADERS, json={'page_id': 'private'})
        assert denied.status_code == 403
        result = client.post('/tools/fan_page_list', headers=HEADERS, json={}).json()
        assert [p['page_id'] for p in result['pages']] == ['approved']
        allowed = client.post('/tools/fan_page_get', headers=HEADERS, json={'page_id': 'approved'}).json()
        assert allowed['page_id'] == 'approved' and 'image_path' not in allowed
        mutation = client.post('/tools/fan_job_config_set', headers=HEADERS,
                               json={'sites': ['linkedin.com'], 'roles': ['software']})
        assert mutation.status_code == 403


def test_gateway_checks_live_origin_before_capture_even_on_force_refresh(tmp_path, monkeypatch):
    running_task(tmp_path, monkeypatch)
    sharing.save(True, ['linkedin.com'])
    monkeypatch.setattr(gateway, 'native_probe', lambda _: {'ok': True, 'url': 'https://outside.test/private'})
    with TestClient(gateway.app) as client:
        assert client.post('/tools/fan_page_learn', headers=HEADERS, json={'refresh': True}).status_code == 403
        assert client.post('/tools/fan_page_probe', headers=HEADERS, json={}).status_code == 403
    assert not gateway._inflight


def test_profile_export_does_not_return_resume_path_or_other_settings(tmp_path, monkeypatch):
    running_task(tmp_path, monkeypatch)
    sharing.save(True, ['linkedin.com'])
    job_applications.save_configuration({'sites': ['linkedin.com'], 'roles': ['software'],
        'profile': {'email': 'synthetic@example.test'}, 'resume_path': 'private.pdf'})
    with TestClient(gateway.app) as client:
        result = client.post('/tools/fan_job_config_get', headers=HEADERS, json={}).json()
    assert result['configuration']['profile']['email'] == 'synthetic@example.test'
    assert 'resume_path' not in result['configuration']


def test_only_guarded_read_tools_are_advertised_and_consent_cannot_be_changed_remotely(tmp_path, monkeypatch):
    running_task(tmp_path, monkeypatch)
    sharing.save(True, ['linkedin.com'])
    advertised = {t['function']['name'] for t in catalog.functions()}
    assert catalog.APPROVED_JOB_TOOLS <= advertised
    assert not {'fan_job_sharing_get', 'fan_job_sharing_set', 'fan_job_config_set', 'fan_job_start', 'fan_job_enqueue'} & advertised
    with TestClient(gateway.app) as client:
        assert client.post('/tools/fan_job_sharing_set', headers=HEADERS, json={'enabled': False}).status_code == 403
    sharing.save(False, ['linkedin.com'])
    assert not catalog.APPROVED_JOB_TOOLS & {t['function']['name'] for t in catalog.functions()}
    assert 'fan_page_learn' not in catalog.signature_guide()


def test_read_only_job_task_cannot_send_input_or_run_scripts(tmp_path, monkeypatch):
    running_task(tmp_path, monkeypatch)
    sharing.save(True, ['linkedin.com'])
    with sqlite3.connect(gateway.DB) as db:
        db.execute("UPDATE tasks SET tool_scope='job_read_only' WHERE id='job-task'")
    with TestClient(gateway.app) as client:
        for name, args in [('mouse_click', {'x': 50, 'y': 50}), ('text_type', {'text': 'must not type'}),
                           ('ahk_script_run', {'name': 'must-not-run'}), ('fan_job_discover', {'page_id': 'not-used'})]:
            assert client.post('/tools/'+name, headers=HEADERS, json=args).status_code == 403
        assert client.post('/tools/fan_job_status', headers=HEADERS, json={}).status_code == 200
        created = client.post('/tasks', headers=HEADERS, json={'prompt': 'Plan jobs', 'tool_scope': 'job_read_only'}).json()
    with sqlite3.connect(gateway.DB) as db:
        assert db.execute('SELECT tool_scope FROM tasks WHERE id=?', (created['id'],)).fetchone()[0] == 'job_read_only'
