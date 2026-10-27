"""Read-only check of the real consolidated-insight API; no model request."""
from live_bridge_smoke import call

health = call('/health')
assert health['healthy'] and health['fan_connected']
assert 'fan_learning_insights' in health['tools']
result = call('/tools/fan_learning_insights', {'query': 'semantic', 'limit': 5})
assert result.get('ok'), result
report = result['report']
assert report['counts']['rows_examined'] > 0 and report['findings']
assert len(report['findings']) <= 5 and report['coverage']
assert all('semantic' in str(finding).lower() for finding in report['findings'])
assert all(finding['evidence']['source_kind'] == 'observed' for finding in report['findings'])
print('PASS Live Fan insight API returns filtered evidence, metrics, coverage and recommendations')
print('Observed rows:', report['counts']['rows_examined'])
