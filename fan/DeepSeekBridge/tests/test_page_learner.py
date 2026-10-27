"""Local atlases preserve geometry, exposed URLs, coverage and privacy boundaries."""
import json
import threading
import time
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from bridge import catalog, gateway, library, page_learner

HEADERS = {'X-Bridge-Token': 'test-local-token'}


def evidence():
    region = {'x': -1200, 'y': 40, 'w': 1000, 'h': 700}
    def control(id, role, name, box, path, **extra):
        return dict(id=id, role=role, name=name, value='', bounds=box,
                    enabled=True, protected=False, accessibility_path=path, href='', **extra)
    box = {'x': -1100, 'y': 200, 'w': 90, 'h': 30}
    controls = [control(1, 'document', 'PRIVATE PAGE', region, '1'),
        control(2, 'toolbar', 'Navigation', {'x': -1200, 'y': 150, 'w': 1000, 'h': 100}, '1.1'),
        control(3, 'link', 'Jobs', box, '1.1.1'),
        control(4, 'graphic', '', {'x': -1050, 'y': 330, 'w': 32, 'h': 32}, '1.2'),
        control(5, 'link', 'Unknown target', {'x': -900, 'y': 350, 'w': 100, 'h': 25}, '1.3')]
    controls[0]['value'] = 'https://example.test/private/messages'
    controls[2]['href'] = 'https://example.test/jobs'
    return {'ok': True, 'frame': {'frame_id': 'test-page-1', 'hwnd': 123, 'title': 'PRIVATE PAGE - Google Chrome',
        'region': region, 'window_rect': region, 'content_stable': True},
        'image_path': 'local-snapshot.png', 'photo_ref': 'photo:1',
        'controls': controls, 'accessibility': {'truncated': False, 'error': ''},
        'ocr': {'lines': [{'text': 'Jobs', 'bounds': box}, {'text': 'Unexposed caption',
            'bounds': {'x': -800, 'y': 600, 'w': 180, 'h': 25}}]},
        'assets': {'acc-3': {'photo_ref': 'photo:3', 'pattern_text': '|<acc-3>**50$3.Q'}},
        'visual_tiles': [{'id': 'tile-1', 'bounds': region}]}


def test_atlas_merges_ocr_preserves_links_and_never_guesses_urls():
    result = page_learner.build(evidence())
    assert result['coverage']['full_window_image']
    assert result['coverage']['accessibility_elements'] == 5
    assert result['element_count'] == 7
    jobs = page_learner.get(result['page_id'], query='Jobs')['elements'][0]
    assert jobs['element_id'] == 'acc-3' and jobs['ocr_text'] == 'Jobs'
    assert jobs['href'] == 'https://example.test/jobs'
    assert jobs['bounds']['x'] == -1100 and jobs['pattern_text'].startswith('|<acc-3>')
    assert jobs['group'] == 'container-2'
    unknown = page_learner.element(result['page_id'], 'acc-5')
    assert unknown['href'] == '' and unknown['link_status'] == 'target_not_exposed'
    assert page_learner.element(result['page_id'], 'tile-1')['actionable'] is False
    # No page title, link or element text enters the agent's persistent prompt.
    assert 'PRIVATE PAGE' not in library.compact_prompt()
    assert not library.search('example.test')


def test_atlas_pagination_group_filter_and_historical_images():
    result = page_learner.build(evidence())
    page = page_learner.get(result['page_id'], offset=2, limit=2)
    assert len(page['elements']) == 2 and page['has_more']
    grouped = page_learner.get(result['page_id'], group='container-2')
    assert grouped['matches'] == 1 and grouped['elements'][0]['name'] == 'Jobs'
    args = page_learner.prepare('fan_page_resolve', {'page_id': result['page_id'], 'element_id': 'acc-3'})
    assert args['_element']['href'] == 'https://example.test/jobs'
    assert args['_page']['url'] == 'https://example.test/private/messages'
    image = page_learner.prepare('fan_page_image', {'page_id': result['page_id'], 'element_id': 'acc-4'})
    assert image['_photo_ref'] == 'photo:1' and image['_crop']
    assert image['_bounds']['w'] == 32
    assert page_learner.list_pages('private')['pages'][0]['page_id'] == result['page_id']
    with pytest.raises(ValueError):
        page_learner.element(result['page_id'], 'missing')


def test_coverage_reports_limits_and_inference_cannot_replace_geometry():
    raw = evidence()
    raw['accessibility']['truncated'] = True
    raw['frame']['content_stable'] = False
    result = page_learner.build(raw)
    assert result['coverage']['accessibility_truncated'] and not result['coverage']['content_stable']
    page_learner.enrich(result['page_id'], json.dumps({'elements': [{'element_id': 'acc-3',
        'description': 'Navigate to jobs', 'bounds': {'x': 999}, 'href': 'https://wrong.test'}]}))
    jobs = page_learner.element(result['page_id'], 'acc-3')
    assert jobs['semantic_source'] == 'image_model_inference'
    assert jobs['bounds']['x'] == -1100 and jobs['href'] == 'https://example.test/jobs'


def test_page_schemas_and_remote_visibility_boundary():
    assert catalog.validate('fan_page_learn', {'hwnd': 123, 'max_elements': 1500})['max_elements'] == 1500
    for args in ({'max_elements': 1501}, {'max_patterns': 101}, {'scroll': True}):
        with pytest.raises(ValidationError):
            catalog.validate('fan_page_learn', args)
    remote_tools = {t['function']['name'] for t in catalog.functions()}
    assert not remote_tools & catalog.LOCAL_PAGE_TOOLS
    assert 'fan_page_learn' not in catalog.signature_guide()


def test_gateway_local_atlas_roundtrip_and_agent_denial(tmp_path, monkeypatch):
    monkeypatch.setattr(gateway, 'DB', tmp_path / 'gateway.sqlite3')
    gateway.init_db()
    with TestClient(gateway.app) as client:
        assert client.post('/tools/fan_page_learn', headers={**HEADERS, 'X-Bridge-Task': 'any-task'}, json={}).status_code == 403
        assert client.post('/tools/fan_page_get', headers=HEADERS, json={'page_id': 'missing'}).status_code == 404
        results = []
        thread = threading.Thread(target=lambda: results.append(client.post('/tools/fan_page_learn', headers=HEADERS, json={'hwnd': 123, 'refresh': True})))
        thread.start()
        for _ in range(100):
            response = client.get('/fan/next', headers=HEADERS)
            if response.text != 'NONE':
                break
            time.sleep(.01)
        else:
            raise AssertionError('Page learner not queued to native Fan')
        call_id, name, args = response.text.split('\n')
        assert name == 'fan_page_learn'
        client.post('/fan/result', headers=HEADERS, data={'id': call_id, 'result': json.dumps(evidence())})
        thread.join(3)
        assert not thread.is_alive() and results[0].json()['page_id'] == 'test-page-1'
        page = client.post('/tools/fan_page_get', headers=HEADERS, json={'page_id': 'test-page-1', 'query': 'Jobs'}).json()
        assert page['elements'][0]['element_id'] == 'acc-3'


def test_memory_reuses_returned_pages_but_new_forms_require_a_revision():
    first = page_learner.build(evidence())
    probe = evidence()
    probe['url'] = first['url']+'?utm_source=changed'
    probe['frame']['hwnd'] = 999
    probe['frame']['title'] = '(14) PRIVATE PAGE - Google Chrome'
    reused = page_learner.reuse(probe)
    assert reused['page_id'] == first['page_id'] and reused['reused']
    assert not reused['capture_performed'] and reused['live_frame']['hwnd'] == 999
    assert page_learner.element(first['page_id'], 'acc-3')['unique_identity']
    probe['controls'].append({'role': 'editable text', 'name': 'Work authorization', 'accessibility_path': '1.9'})
    assert page_learner.reuse(probe) is None
    probe['controls'].pop()
    probe['url'] = 'https://other.example.test/private/messages'
    assert page_learner.reuse(probe) is None
    assert page_learner.get(first['page_id'])['photo_ref'] == 'photo:1'


def test_partial_probe_and_missing_urls_never_claim_a_cache_hit():
    first = page_learner.build(evidence())
    probe = evidence()
    probe.update(url=first['url'])
    probe['accessibility']['truncated'] = True
    assert page_learner.reuse(probe) is None
    probe['accessibility']['truncated'] = False
    probe['url'] = ''
    assert page_learner.reuse(probe) is None
