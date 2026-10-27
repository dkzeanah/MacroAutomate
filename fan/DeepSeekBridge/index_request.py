"""Native index-tab worker: source slices only, with no model or desktop input."""
import json
import sys
from pathlib import Path
from bridge.context_map import dispatch

request = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
try:
    if request['tool'] not in ('context_map_find', 'context_map_get'):
        raise ValueError('Only code-index reads are supported')
    result = dispatch(request['tool'], request['arguments'])
except Exception as exc:
    result = {'ok': False, 'error': str(exc)}
destination = Path(sys.argv[2])
temporary = destination.with_suffix('.tmp')
temporary.write_text(json.dumps(result, ensure_ascii=False), encoding='utf-8')
temporary.replace(destination)
