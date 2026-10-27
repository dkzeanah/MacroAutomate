"""Durable preparation is restartable and never masquerades as submission."""
from concurrent.futures import ThreadPoolExecutor
import json
import sqlite3
import pytest
from bridge import job_applications as jobs, page_learner, catalog


def test_transient_lock_before_claim_does_not_stop_service_or_act(monkeypatch):
    def locked():
        raise sqlite3.OperationalError('database is locked')
    monkeypatch.setattr(jobs, 'claim', locked)
    assert jobs.process_one(observe=lambda *_: pytest.fail('must not observe or act before claiming')) is False
    def invalid():
        raise sqlite3.OperationalError('no such table: invalid')
    monkeypatch.setattr(jobs, 'claim', invalid)
    with pytest.raises(sqlite3.OperationalError, match='no such table'):
        jobs.process_one()


def config():
    return jobs.save_configuration({'sites': ['linkedin.com'], 'roles': ['Software'],
        'profile': {'email': 'synthetic@example.test'}, 'answers': {}})


def test_deduplication_pause_resume_and_deadline(monkeypatch):
    config()
    first = jobs.enqueue({'url': 'https://www.linkedin.com/jobs/view/123?trk=feed', 'title': 'Software Developer'})
    second = jobs.enqueue({'url': 'https://www.linkedin.com/jobs/view/123?utm_source=new'})
    assert second['duplicate'] and second['job_id'] == first['job_id']
    with pytest.raises(ValueError):
        jobs.enqueue({'url': 'https://not-selected.test/job/123'})
    with pytest.raises(ValueError):
        jobs.enqueue({'url': 'http://linkedin.com/jobs/view/123'})
    run = jobs.start(8)
    jobs.control(run['run_id'], 'pause')
    assert jobs.claim() is None
    jobs.control(run['run_id'], 'resume')
    item = jobs.claim()
    assert item['job_id'] == first['job_id']
    jobs.recover()
    assert jobs.status()['counts']['queued'] == 1
    jobs.control(run['run_id'], 'stop')
    assert jobs.claim() is None


def test_claim_is_exclusive_across_workers():
    config()
    jobs.enqueue({'url': 'https://linkedin.com/jobs/view/123'})
    jobs.start()
    with ThreadPoolExecutor(max_workers=2) as pool:
        claims = list(pool.map(lambda _: jobs.claim(), range(2)))
    assert sum(item is not None for item in claims) == 1


def test_preparation_uses_saved_answers_and_retained_memory(monkeypatch):
    config()
    raw = {'ok': True, 'frame': {'frame_id': 'application-page', 'hwnd': 12, 'title': 'Job application',
        'region': {'x': 0, 'y': 0, 'w': 600, 'h': 400}}, 'photo_ref': 'photo:1', 'controls': [
        {'id': 1, 'role': 'document', 'name': 'Application', 'value': 'https://linkedin.com/jobs/view/123',
         'bounds': {'x': 0, 'y': 0, 'w': 600, 'h': 400}, 'accessibility_path': '1'},
        {'id': 2, 'role': 'editable text', 'name': 'Email', 'bounds': {'x': 30, 'y': 40, 'w': 180, 'h': 25}, 'accessibility_path': '1.1'},
        {'id': 3, 'role': 'editable text', 'name': 'Years of experience', 'bounds': {'x': 30, 'y': 80, 'w': 180, 'h': 25}, 'accessibility_path': '1.2'}],
        'accessibility': {'truncated': False}}
    page_learner.build(raw)
    queued = jobs.enqueue({'url': 'https://linkedin.com/jobs/view/123', 'title': 'Software Engineer'})
    jobs.start()
    assert jobs.process_one()
    assert jobs.status()['counts']['prepared'] == 1
    with jobs.library.connect() as db:
        result = json.loads(db.execute('SELECT result FROM application_queue WHERE job_id=?', (queued['job_id'],)).fetchone()[0])
    assert result['saved_answer_plan'][0]['answer'] == 'synthetic@example.test'
    assert result['unresolved_fields'][0]['question'] == 'Years of experience'
    assert not result['inputs_performed'] and not result['submitted']
    assert not jobs.status()['submission_enabled']
    assert 'synthetic@example.test' not in jobs.library.compact_prompt()


def test_private_job_tools_are_not_advertised_to_remote_agents():
    assert not catalog.LOCAL_JOB_TOOLS & {t['function']['name'] for t in catalog.functions()}
    assert not any(name in catalog.signature_guide() for name in catalog.LOCAL_JOB_TOOLS)


def test_matching_requires_salary_and_location_evidence():
    settings = {'roles': ['software', 'embedded', 'avionics'],
        'locations': ['Tuscaloosa, AL', 'Birmingham, AL', 'Atlanta, GA'],
        'remote': 'any', 'remote_preferred': True, 'minimum_salary': 80000}
    role = {'title': 'Firmware Engineer', 'criteria': {'annual_salary_min': 90000,
        'remote': True, 'country': 'US'}}
    assert jobs.eligibility(role, settings)['status'] == 'matched'
    assert jobs.eligibility(role, settings)['priority'] == 0
    role['criteria']['country'] = ''
    assert jobs.eligibility(role, settings)['status'] == 'needs_verification'
    role['criteria'].update(remote=False, location='Atlanta, GA', annual_salary_min=80000)
    assert jobs.eligibility(role, settings)['status'] == 'matched'
    role['criteria'].update(location='Seattle, WA')
    assert jobs.eligibility(role, settings)['status'] == 'ineligible'
    role['criteria'].update(location='Atlanta, GA', annual_salary_min=None, annual_salary_max=75000)
    assert jobs.eligibility(role, settings)['status'] == 'ineligible'
    role['criteria'].update(annual_salary_max=None)
    assert jobs.eligibility(role, settings)['status'] == 'needs_verification'


def test_embedded_healthcare_and_software_sales_are_not_engineering_roles():
    assert not jobs.role_matches('Care Coordinator, Embedded (Atlanta, GA)', ['embedded'])
    assert not jobs.role_matches('Software Account Executive', ['software'])
    assert jobs.role_matches('Senior Embedded Software Engineer', ['embedded'])
    assert jobs.role_matches('.NET Developer', ['software'])


def test_form_plan_cannot_target_browser_chrome(monkeypatch):
    fields = [{'element_id': 'email', 'scope': 'page', 'kind': 'accessibility',
        'action_hint': 'type', 'name': 'Email address *'},
        {'element_id': 'address', 'scope': 'browser_chrome', 'kind': 'accessibility',
         'action_hint': 'type', 'name': 'Address and search bar'},
        {'element_id': 'unknown', 'scope': 'unknown', 'kind': 'accessibility',
         'action_hint': 'type', 'name': 'Email'}]
    monkeypatch.setattr(jobs, 'all_elements', lambda _: fields)
    planned = jobs.plan({'page_id': 'synthetic'}, {'profile': {'email': 'synthetic@example.test'},
        'answers': {'Address and search bar': 'must never be used'}})
    assert [e['element_id'] for e in planned['saved_answer_plan']] == ['email']
    assert not planned['unresolved_fields']


def test_discovery_keeps_unknown_metadata_and_deduplicates_observed_links(monkeypatch):
    config()
    monkeypatch.setattr(page_learner, 'get', lambda _: {'url': 'https://linkedin.com/jobs/search'})
    link = {'element_id': 'job', 'scope': 'page', 'name': 'Software Engineer',
        'href': 'https://www.linkedin.com/jobs/view/123?trk=search'}
    monkeypatch.setattr(jobs, 'all_elements', lambda _: [link, {**link, 'element_id': 'duplicate'},
        {**link, 'element_id': 'toolbar', 'scope': 'browser_chrome', 'href': 'https://linkedin.com/jobs/view/999'}])
    found = jobs.discover('synthetic')
    assert len(found['jobs']) == 2 and found['jobs'][1]['duplicate']
    assert jobs.status()['counts']['queued'] == 1
    with jobs.library.connect() as db:
        criteria = json.loads(db.execute('SELECT criteria FROM application_queue').fetchone()[0])
    assert criteria['annual_salary_min'] is None and criteria['location'] is None
    assert criteria['evidence_url'] == 'https://linkedin.com/jobs/search'


def test_submission_intent_is_retained_without_enabling_an_untested_adapter():
    config()
    jobs.save_configuration({'submission_mode': 'submit_completed', 'remote_preferred': True})
    assert jobs.status()['requested_submission_mode'] == 'submit_completed'
    assert not jobs.status()['submission_enabled']
    assert jobs.searches()['searches'][0]['location'] == 'Remote, United States'
