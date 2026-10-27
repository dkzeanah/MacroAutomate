"""Usage-based USD estimates. No balance reads or invented token measurements."""
import json
import sqlite3
from datetime import datetime, timezone, timedelta
from pathlib import Path

CARD = Path(__file__).with_name('pricing_rates.json')


def rate_card():
    return json.loads(CARD.read_text(encoding='utf-8'))


def estimate(usage, model, at, card=None):
    card = card or rate_card()
    canonical = card['aliases'].get(model.lower(), model.lower())
    rates = card['off_peak_per_million'].get(canonical)
    base = {'currency': 'USD', 'rate_version': card['version'], 'rate_source': card['source'], 'model': canonical,
            'basis': 'Provider-reported tokens × published rate snapshot; not an invoice. Completion tokens already include any billed reasoning. Image tokens are included in prompt usage, never added twice.'}
    if not rates or usage.get('prompt_tokens') is None or usage.get('completion_tokens') is None:
        return {**base, 'status': 'unknown', 'usd_low': None, 'usd_high': None, 'reason': 'Unknown model or missing reported prompt/completion usage'}
    prompt, output = max(0, int(usage['prompt_tokens'])), max(0, int(usage['completion_tokens']))
    hit = usage.get('prompt_cache_hit_tokens', (usage.get('prompt_tokens_details') or {}).get('cached_tokens'))
    miss = usage.get('prompt_cache_miss_tokens')
    if hit is None and miss is not None:
        hit = max(0, prompt - int(miss))
    known_cache = hit is not None
    hit = min(prompt, max(0, int(hit))) if known_cache else 0
    miss = prompt - hit
    instant = datetime.fromisoformat(at.replace('Z', '+00:00'))
    if instant.tzinfo is None:
        instant = instant.replace(tzinfo=timezone.utc)
    instant = instant.astimezone(timezone.utc)
    chinese_day = (instant + timedelta(hours=8)).date().isoformat()
    peak = instant.weekday() < 5 and any(start <= instant.hour < end for start, end in card['peak_utc_hours'])
    holiday = chinese_day in card['verified_chinese_holidays']
    uncertain_holiday = peak and not holiday and int(chinese_day[:4]) not in card['holiday_calendar_verified_years']
    factor = card['peak_multiplier'] if peak and not holiday else 1
    low_factor = 1 if uncertain_holiday else factor
    low_input = hit * rates['hit'] + miss * rates['miss'] if known_cache else prompt * rates['hit']
    high_input = hit * rates['hit'] + miss * rates['miss']
    return {**base, 'status': 'estimated', 'usd_low': (low_input + output * rates['output']) * low_factor / 1e6,
            'usd_high': (high_input + output * rates['output']) * factor / 1e6,
            'prompt_tokens': prompt, 'completion_tokens': output, 'cache_split_known': known_cache,
            'cache_hit_tokens': hit if known_cache else None, 'cache_miss_tokens': miss if known_cache else None,
            'schedule': 'peak candidate; holiday calendar unverified (range)' if uncertain_holiday else 'peak' if factor == 2 else 'off-peak',
            'timestamp_basis': 'request start UTC; boundary-crossing/provider reconciliation can differ',
            'historical_repricing': instant.date().isoformat() < card['checked_at']}


def summary(database, task_id=''):
    """Use the last cumulative usage per request. Missing usage stays unknown."""
    card = rate_card()
    with sqlite3.connect(database, timeout=10) as db:
        db.row_factory = sqlite3.Row
        where = "kind IN ('agent_request','vision_request','agent_usage','vision_usage')"
        params = ()
        if task_id:
            where += " AND (subject=? OR json_extract(payload,'$.task_id')=?)"
            params = (task_id, task_id)
        rows = db.execute('SELECT id,at,kind,subject,payload FROM events WHERE ' + where + ' ORDER BY id', params).fetchall()
    requests, usages, latest = {}, {}, {}
    for row in rows:
        payload = json.loads(row['payload'])
        family = 'vision' if row['kind'].startswith('vision') else 'agent'
        stream = (row['subject'], family)
        if row['kind'].endswith('_request'):
            key = payload.get('request_id') or str(row['id'])
            latest[stream] = key
            requests[key] = {'model': payload.get('model', ''), 'at': payload.get('started_at', row['at']), 'family': family}
        else:
            key = payload.get('request_id') or latest.get(stream) or 'usage:' + str(row['id'])
            request = requests.get(key, {})
            model = payload.get('model') or request.get('model', '')
            usages[key] = payload.get('cost_estimate') or estimate(payload, model, payload.get('started_at', request.get('at', row['at'])), card)
    known = [value for value in usages.values() if value['usd_low'] is not None]
    missing = len(set(requests) - set(usages)) + sum(value['usd_low'] is None for value in usages.values())
    models = {}
    for value in known:
        item = models.setdefault(value['model'], {'calls_with_usage': 0, 'usd_low': 0, 'usd_high': 0, 'prompt_tokens': 0, 'completion_tokens': 0})
        item['calls_with_usage'] += 1
        for field in ('usd_low', 'usd_high', 'prompt_tokens', 'completion_tokens'):
            item[field] += value[field]
    return {'currency': 'USD', 'usd_low': sum(v['usd_low'] for v in known), 'usd_high': sum(v['usd_high'] for v in known),
            'calls_with_usage': len(known), 'unpriced_or_missing_usage': missing, 'models': models,
            'rate_version': card['version'], 'rate_source': card['source'],
            'warning': 'Estimated recorded usage only; missing/failed-stream usage is unknown, not free. Older events are repriced with this snapshot. Cache/holiday uncertainty is a range. Local tool/OCR/FindText calls are not DeepSeek Search/Fetch requests; no Search/Fetch API is connected here. Knowledge savings are counterfactual and are never deducted from spending.'}
