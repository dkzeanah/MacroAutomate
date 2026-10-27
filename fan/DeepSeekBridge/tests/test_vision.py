"""Automatic image routing, trusted capture paths and evidence provenance."""
import base64
import json
from types import SimpleNamespace as NS

import pytest
from bridge import agent, vision, library, page_learner, job_sharing

PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/W1sAAAAASUVORK5CYII=')


class Stream:
    def __init__(self, chunks):
        self.chunks = chunks
        self.closed = False

    def __iter__(self):
        yield from self.chunks

    def close(self):
        self.closed = True


def chunk(content='', finish=None, call=None):
    return NS(usage=None, choices=[NS(finish_reason=finish,
              delta=NS(content=content, reasoning_content=None, tool_calls=[call] if call else []))])


def test_capture_paths_are_confined_and_content_checked(tmp_path, monkeypatch):
    allowed = tmp_path / 'captures'
    allowed.mkdir()
    monkeypatch.setattr(vision, 'CAPTURES', allowed)
    captured = allowed / 'frame.png'
    captured.write_bytes(PNG)
    assert vision.capture_bytes(str(captured))[2] == 'image/png'
    outside = tmp_path / 'other.png'
    outside.write_bytes(PNG)
    with pytest.raises(ValueError, match='native capture'):
        vision.capture_bytes(str(outside))
    captured.write_text('not an image')
    with pytest.raises(ValueError, match='PNG/JPEG'):
        vision.capture_bytes(str(captured))


def test_native_session_exports_are_allowed_but_arbitrary_temp_files_are_not(tmp_path, monkeypatch):
    monkeypatch.setattr(vision, 'SESSION_CACHE', tmp_path)
    session = tmp_path / 'FanPhotos-123-456'
    session.mkdir()
    image = session / 'frame.png'
    image.write_bytes(PNG)
    assert vision.capture_bytes(str(image))[1] == PNG
    arbitrary = tmp_path / 'arbitrary.png'
    arbitrary.write_bytes(PNG)
    with pytest.raises(ValueError, match='native capture'):
        vision.capture_bytes(str(arbitrary))


def test_image_routing_preserves_native_bounds_and_labels_inference(tmp_path, monkeypatch):
    captures = tmp_path / 'captures'
    captures.mkdir()
    monkeypatch.setattr(vision, 'CAPTURES', captures)
    image = captures / 'ui.png'
    image.write_bytes(PNG)
    geometry = {'x': -1920, 'y': 0, 'w': 1920, 'h': 1080}
    observed = {'ok': True, 'image_path': str(image), 'geometry': geometry,
                'legend': [{'id': 'C4', 'x': -400, 'y': 600}],
                'controls': [{'id': 'answer', 'bounds': {'x': -430, 'y': 580, 'w': 20, 'h': 30}}]}
    requests, logs = [], []
    stream = Stream([chunk('C4 is probably the answer field.'), chunk(finish='stop')])
    def create(**request):
        requests.append(request)
        return stream
    analysis = vision.analyze(observed, client=NS(chat=NS(completions=NS(create=create))),
                task_id='synthetic', log=lambda kind, subject, payload: logs.append((kind, payload)),
                check=lambda _: None, user_task='Enter the math answer')
    assert requests[0]['model'] == 'deepseek-flash'
    assert requests[0]['messages'][-1]['content'][1]['type'] == 'image_url'
    assert requests[0]['messages'][-1]['content'][1]['image_url']['detail'] == 'original'
    assert '"zones"' in requests[0]['messages'][-1]['content'][0]['text']
    assert 'then interpret text within each group' in requests[0]['messages'][-1]['content'][0]['text']
    assert analysis['source_kind'] == 'inference' and analysis['observed_geometry'] == geometry
    assert observed['controls'][0]['bounds']['x'] == -430
    assert library.get(analysis['observed_record'])['metadata']['source_kind'] == 'observed'
    assert library.get(analysis['knowledge_name'])['metadata']['source_kind'] == 'inference'
    assert stream.closed


def test_vision_rejects_unsupported_dimension_or_model(tmp_path, monkeypatch):
    import struct
    monkeypatch.setattr(vision, 'CAPTURES', tmp_path)
    image = tmp_path / 'wide.png'
    image.write_bytes(PNG[:16] + struct.pack('>II', 8193, 1) + PNG[24:])
    with pytest.raises(ValueError, match='8192'):
        vision.capture_bytes(str(image))
    image.write_bytes(PNG)
    monkeypatch.setenv('DEEPSEEK_VISION_MODEL', 'deepseek-v4-pro')
    with pytest.raises(ValueError, match='does not accept images'):
        vision.analyze({'image_path': str(image)}, client=None, task_id='test', log=lambda *args: None, check=lambda _: None, user_task='read image')


def test_compaction_prioritizes_zones_and_grouped_ocr():
    result = agent.bounded_result({'ok': True, 'zones': {'zones': [{'id': 'left'}]},
                  'ocr': {'text': 'flat ' * 20000, 'raw_text': 'raw ' * 20000,
                          'groups': [{'id': 'left', 'text': 'Grouped observed text'}], 'layout': {'created_before_ocr': True}},
                  'extra': 'noise ' * 20000}, max_chars=2000)
    assert result['zones']['zones'][0]['id'] == 'left'
    assert result['ocr']['groups'][0]['text'] == 'Grouped observed text'


def test_vision_ocr_context_does_not_repeat_full_word_catalog():
    raw={'groups':[{'id':'left','zone_id':'left','text':'x'*9000}], 'text':'x'*9000,
         'raw_text':'x'*9000,'words':[{'text':'word'}]*2000,'lines':[{'text':'line'}]*200}
    compact=vision.compact_ocr(raw)
    assert len(compact['groups'][0]['text'])==6000
    assert 'words' not in compact and 'raw_text' not in compact
    assert compact['retained_local_counts']['words']==2000 and len(raw['words'])==2000


def test_agent_automatically_interleaves_flash_evidence_with_text_planning(tmp_path, monkeypatch):
    captures = tmp_path / 'captures'
    captures.mkdir()
    monkeypatch.setattr(vision, 'CAPTURES', captures)
    image = captures / 'ui.png'
    image.write_bytes(PNG)
    monkeypatch.setenv('DEEPSEEK_API_KEY', 'synthetic-key')
    monkeypatch.setattr(agent, 'check_cancelled', lambda _: None)
    logs = []
    monkeypatch.setattr(agent, 'db_write', lambda kind, subject, payload: logs.append(kind))
    requests = []
    call = NS(index=0, id='inspect', function=NS(name='fan_window_inspect', arguments='{}'))
    streams = [Stream([chunk(call=call), chunk(finish='tool_calls')]),
               Stream([chunk('Grid B3 labels the answer input.'), chunk(finish='stop')]),
               Stream([chunk('Mapped the field from current UI.'), chunk(finish='stop')])]
    def create(**request):
        requests.append(json.loads(json.dumps(request)))
        return streams.pop(0)
    monkeypatch.setattr(agent, 'OpenAI', lambda **_: NS(chat=NS(completions=NS(create=create))))
    monkeypatch.setattr(agent, 'request_tool', lambda *args, **kwargs: {'ok': True, 'image_path': str(image),
                         'geometry': {'x': 0, 'y': 0, 'w': 1280, 'h': 720}, 'legend': [{'id': 'B3'}]})
    assert agent.run_prompt('Map the answer input', task_id='synthetic') == 'Mapped the field from current UI.'
    assert [request['model'] for request in requests] == ['deepseek-v4-pro', 'deepseek-flash', 'deepseek-v4-pro']
    tool_result = json.loads(requests[-1]['messages'][-1]['content'])
    assert tool_result['vision_analysis']['source_kind'] == 'inference'
    assert 'vision_request' in logs and 'vision_result' in logs


def test_flash_failure_retains_native_observation_for_text_agent(tmp_path, monkeypatch):
    captures = tmp_path / 'captures'
    captures.mkdir()
    monkeypatch.setattr(vision, 'CAPTURES', captures)
    image = captures / 'ui.png'
    image.write_bytes(PNG)
    monkeypatch.setenv('DEEPSEEK_API_KEY', 'synthetic-key')
    monkeypatch.setattr(agent, 'check_cancelled', lambda _: None)
    monkeypatch.setattr(agent, 'db_write', lambda *args: None)
    call = NS(index=0, id='inspect', function=NS(name='fan_window_inspect', arguments='{}'))
    requests = []
    def create(**request):
        requests.append(json.loads(json.dumps(request)))
        if request['model'] == 'deepseek-flash':
            raise RuntimeError('Vision unavailable')
        if len(requests) == 1:
            return Stream([chunk(call=call), chunk(finish='tool_calls')])
        return Stream([chunk('Native bounds are still available.'), chunk(finish='stop')])
    monkeypatch.setattr(agent, 'OpenAI', lambda **_: NS(chat=NS(completions=NS(create=create))))
    monkeypatch.setattr(agent, 'request_tool', lambda *args, **kwargs: {'ok': True, 'image_path': str(image), 'geometry': {'x': 5, 'y': 6}, 'text': 'Observed field'})
    assert agent.run_prompt('Map field', task_id='synthetic') == 'Native bounds are still available.'
    result = json.loads(requests[-1]['messages'][-1]['content'])
    assert result['geometry'] == {'x': 5, 'y': 6} and result['vision_error'] == 'Vision unavailable'


def test_real_native_shape_sends_annotated_grid_and_frame_region(tmp_path, monkeypatch):
    captures = tmp_path / 'captures'
    captures.mkdir()
    monkeypatch.setattr(vision, 'CAPTURES', captures)
    raw = captures / 'raw.png'
    annotated = captures / 'numbered.png'
    raw.write_bytes(PNG)
    annotated.write_bytes(PNG)
    region = {'x': -1500, 'y': 200, 'w': 640, 'h': 400}
    native = {'ok': True, 'image_path': str(raw), 'annotated_image_path': str(annotated),
              'frame': {'region': region, 'frame_id': 'native-test', 'coordinates': 'physical_screen_pixels'},
              'legend': [{'id': '12', 'bounds': {'x': -1300, 'y': 250, 'w': 30, 'h': 20}}]}
    assert vision.image_candidates(native) == [str(annotated), str(raw)]
    requests = []
    def create(**request):
        requests.append(request)
        return Stream([chunk('Control 12 is visible.'), chunk(finish='stop')])
    result = vision.analyze(native, client=NS(chat=NS(completions=NS(create=create))),
             task_id='native-test', log=lambda *args: None, check=lambda _: None, user_task='Map this UI')
    assert result['observed_geometry'] == region
    text = requests[0]['messages'][-1]['content'][0]['text']
    assert 'native-test' in text and '-1500' in text and 'physical_screen_pixels' in text
    assert len(requests[0]['messages'][-1]['content']) == 3


def test_bounded_native_result_keeps_geometry_and_flash_mapping_in_structured_form():
    controls = [{'id': i, 'name': 'Long accessible text ' * 50,
                 'bounds': {'x': -1300, 'y': 200 + i, 'w': 30, 'h': 20},
                 'source': 'observed_MSAA_geometry'} for i in range(500)]
    frame = {'frame_id': 'native-large', 'coordinates': 'physical_screen_pixels',
             'region': {'x': -1500, 'y': 200, 'w': 640, 'h': 400}}
    native = {'ok': True, 'frame': frame, 'controls': controls,
              'accessibility': {'controls': controls, 'method': 'MSAA'},
              'vision_analysis': {'model': 'deepseek-flash', 'source_kind': 'inference',
                  'text': 'Control 12 labels the answer field.',
                  'knowledge_name': 'knowledge:vision-capture', 'observed_record': 'knowledge:observed-capture'}}
    bounded = agent.bounded_result(native)
    assert bounded['truncated'] and len(json.dumps(bounded, ensure_ascii=False)) <= 28000
    assert bounded['frame'] == frame
    assert bounded['controls'][0]['bounds']['x'] == -1300
    assert bounded['vision_analysis']['knowledge_name'] == 'knowledge:vision-capture'
    assert bounded['vision_analysis']['source_kind'] == 'inference'
    assert 'controls' not in bounded['accessibility']


def test_approved_page_image_analysis_is_retained_without_generic_knowledge_leak(tmp_path, monkeypatch):
    captures = tmp_path / 'captures'
    captures.mkdir()
    monkeypatch.setattr(vision, 'CAPTURES', captures)
    image = captures / 'job.png'
    image.write_bytes(PNG)
    job_sharing.save(True, ['linkedin.com'])
    learned = page_learner.build({'ok': True, 'photo_ref': 'photo:1', 'image_path': str(image),
        'frame': {'frame_id': 'job-page', 'title': 'Job', 'region': {'x': 0, 'y': 0, 'w': 400, 'h': 300}},
        'controls': [{'id': 1, 'role': 'document', 'name': 'Job', 'value': 'https://linkedin.com/jobs',
                      'bounds': {'x': 0, 'y': 0, 'w': 400, 'h': 300}, 'accessibility_path': '1'}]})
    requests = []
    def create(**request):
        requests.append(request)
        return Stream([chunk(json.dumps({'page_description': 'PRIVATE JOB ANALYSIS', 'elements': []})), chunk(finish='stop')])
    client = NS(base_url='https://api.deepseek.com', chat=NS(completions=NS(create=create)))
    analysis = vision.analyze(learned, client=client, task_id='job', log=lambda *args: None,
                             check=lambda _: None, user_task='Map job application')
    assert analysis['source_kind'] == 'inference'
    assert page_learner.get('job-page')['vision_analysis']['text'] == analysis['text']
    assert 'PRIVATE JOB ANALYSIS' not in library.compact_prompt() and not library.search('PRIVATE JOB ANALYSIS')
    assert 'HISTORICAL SAVED' in requests[0]['messages'][-1]['content'][0]['text']
    client.base_url = 'https://unapproved-provider.test'
    with pytest.raises(ValueError, match='destination'):
        vision.analyze(learned, client=client, task_id='job', log=lambda *args: None,
                       check=lambda _: None, user_task='Map job application')
    assert len(requests) == 1


def test_agent_does_not_reanalyze_a_reused_page_image(monkeypatch):
    job_sharing.save(True, ['linkedin.com'])
    monkeypatch.setenv('DEEPSEEK_API_KEY', 'synthetic-key')
    monkeypatch.setattr(agent, 'check_cancelled', lambda _: None)
    monkeypatch.setattr(agent, 'db_write', lambda *args: None)
    call = NS(index=0, id='learn', function=NS(name='fan_page_learn', arguments='{}'))
    requests = []
    streams = [Stream([chunk(call=call), chunk(finish='tool_calls')]), Stream([chunk('Saved map reused.'), chunk(finish='stop')])]
    def create(**request):
        requests.append(json.loads(json.dumps(request)))
        return streams.pop(0)
    monkeypatch.setattr(agent, 'OpenAI', lambda **_: NS(chat=NS(completions=NS(create=create))))
    monkeypatch.setattr(agent, 'request_tool', lambda *args, **kwargs: {'ok': True, 'page_id': 'saved',
        'reused': True, 'image_path': 'must-not-be-reopened.png', 'vision_analysis': {'text': 'Existing inference'}})
    assert agent.run_prompt('Learn LinkedIn jobs page', task_id='job') == 'Saved map reused.'
    assert len(requests) == 2 and all(r['model'] != 'deepseek-flash' for r in requests)
    assert 'image_path' not in json.loads(requests[-1]['messages'][-1]['content'])
