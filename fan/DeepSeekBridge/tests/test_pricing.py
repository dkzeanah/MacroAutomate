import json
import sqlite3
import pytest
from bridge import pricing

USAGE = {'prompt_tokens': 1000000, 'completion_tokens': 1000000, 'prompt_cache_hit_tokens': 500000,
         'completion_tokens_details': {'reasoning_tokens': 900000}}


@pytest.mark.parametrize('model,expected', [('deepseek-flash', .6765), ('deepseek-v4-pro', 2.321), ('deepseek-v4-flash-vision-exp', .6765)])
def test_weekend_costs_and_reasoning_are_not_double_counted(model, expected):
    result = pricing.estimate(USAGE, model, '2026-10-18T02:00:00Z')
    assert result['usd_low'] == pytest.approx(expected)
    assert result['usd_high'] == result['usd_low'] and result['schedule'] == 'off-peak'


def test_peak_holiday_uncertainty_and_verified_calendar():
    result = pricing.estimate(USAGE, 'deepseek-flash', '2026-10-19T02:00:00Z')
    assert result['usd_high'] == 2 * result['usd_low']
    card = pricing.rate_card()
    card['holiday_calendar_verified_years'] = [2026]
    result = pricing.estimate(USAGE, 'deepseek-flash', '2026-10-19T02:00:00Z', card)
    assert result['usd_low'] == result['usd_high'] == pytest.approx(1.353)
    card['verified_chinese_holidays'] = ['2026-10-19']
    result = pricing.estimate(USAGE, 'deepseek-flash', '2026-10-19T02:00:00Z', card)
    assert result['usd_high'] == pytest.approx(.6765)


@pytest.mark.parametrize('at', ['2026-10-19T00:59:59Z', '2026-10-19T04:00:00Z', '2026-10-19T10:00:00Z'])
def test_off_peak_boundaries(at):
    assert pricing.estimate(USAGE, 'deepseek-flash', at)['schedule'] == 'off-peak'


def test_unknown_cache_is_range_and_missing_usage_is_unknown():
    result = pricing.estimate({'prompt_tokens': 1000000, 'completion_tokens': 0}, 'deepseek-flash', '2026-10-18T02:00:00Z')
    assert result['usd_low'] == .003 and result['usd_high'] == .15
    assert not result['cache_split_known']
    assert pricing.estimate({}, 'deepseek-flash', '2026-10-18T02:00:00Z')['usd_high'] is None
    assert pricing.estimate(USAGE, 'unknown-model', '2026-10-18T02:00:00Z')['usd_high'] is None


def test_aggregate_latest_cumulative_usage_and_missing_requests(tmp_path):
    path = tmp_path / 'usage.db'
    with sqlite3.connect(path) as db:
        db.execute('CREATE TABLE events(id INTEGER PRIMARY KEY,at,kind,subject,payload)')
        for kind, data in [('agent_request', {'request_id': 'one', 'model': 'deepseek-flash'}),
                           ('agent_usage', {**USAGE, 'request_id': 'one', 'model': 'deepseek-flash', 'completion_tokens': 1}),
                           ('agent_usage', {**USAGE, 'request_id': 'one', 'model': 'deepseek-flash'}),
                           ('vision_request', {'request_id': 'two', 'model': 'deepseek-flash'})]:
            db.execute('INSERT INTO events(at,kind,subject,payload) VALUES(?,?,?,?)', ('2026-10-18T02:00:00Z', kind, 'task', json.dumps(data)))
    result = pricing.summary(path, 'task')
    assert result['calls_with_usage'] == 1 and result['unpriced_or_missing_usage'] == 1
    assert result['usd_high'] == pytest.approx(.6765)
    assert pricing.summary(path, 'other')['calls_with_usage'] == 0
