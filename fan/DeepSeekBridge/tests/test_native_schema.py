"""Advertised Python arguments must work with the live native Fan API shape."""
import pytest
from pydantic import ValidationError

from bridge import catalog


def test_inspection_exposes_narrow_native_capture_and_catalog_options():
    crop = {'x': -1200, 'y': 40, 'w': 600, 'h': 400}
    args = catalog.validate('fan_window_inspect', {'hwnd': 32, 'region': crop,
                            'limit': 15, 'include_ocr': False, 'include_image': True})
    assert args == {'hwnd': 32, 'region': crop, 'include_image': True, 'include_ocr': False, 'limit': 15}
    assert catalog.validate('fan_ocr', {}) == {}
    assert catalog.validate('fan_pattern_list', {'query': 'Submit', 'limit': 3}) == {'query': 'Submit', 'limit': 3}


def test_pattern_search_accepts_saved_name_or_explicit_native_text():
    explicit = '|<submit>*128$3.Q'
    assert catalog.validate('fan_pattern_search', {'name': 'Saved'}) == {'name': 'Saved'}
    assert catalog.validate('fan_pattern_search', {'text': explicit}) == {'text': explicit}
    assert catalog.validate('fan_pattern_search', {'text': explicit, 'err1': 0, 'err0': .5})['err0'] == .5
    for invalid in ({}, {'text': 'not a FindText pattern'}, {'name': 'Saved', 'err1': .51}):
        with pytest.raises(ValidationError):
            catalog.validate('fan_pattern_search', invalid)


def test_capture_requires_a_real_crop_and_supports_saved_pattern_edits():
    region = {'x': -1200, 'y': 40, 'w': 80, 'h': 30}
    args = catalog.validate('fan_pattern_capture', {'name': 'Submit', 'region': region,
                            'overwrite': True, 'qualifier': 'Pearson homework player', 'threshold': '**50'})
    assert args['overwrite'] and args['region'] == region and args['threshold'] == '**50'
    assert catalog.PatternCapture.model_fields['threshold'].default == '**50'
    for threshold in (0, 128, 255, '*128', '**50'):
        assert catalog.validate('fan_pattern_capture', {'name': 'Submit', 'region': region,
                                'threshold': threshold})['threshold'] == threshold
    for invalid in ({'name': 'Submit'}, {'name': 'Submit', 'region': region, 'text': '|<>*128$3.Q'},
                    {'name': 'Submit', 'region': region, 'threshold': 256},
                    {'name': 'Submit', 'region': region, 'threshold': '**999'},
                    {'name': 'Bad|Name', 'region': region},
                    {'name': 'Submit', 'region': {**region, 'w': 1025}}):
        with pytest.raises(ValidationError):
            catalog.validate('fan_pattern_capture', invalid)


def test_public_size_limits_match_native_limits_before_a_queued_request():
    with pytest.raises(ValidationError):
        catalog.validate('fan_window_inspect', {'region': {'x': 0, 'y': 0, 'w': 8192, 'h': 8192}})
    with pytest.raises(ValidationError):
        catalog.validate('fan_window_inspect', {'limit': 501})
    with pytest.raises(ValidationError):
        catalog.validate('fan_workflow_save', {'name': 'Large', 'steps': [{'action': 'Wait'}] * 301})
    with pytest.raises(ValidationError):
        catalog.validate('fan_library_read', {'path': 'lib/FanBridgeVision.ahk', 'line_count': 201})
