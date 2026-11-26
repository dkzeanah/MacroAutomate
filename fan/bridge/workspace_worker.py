"""File-based background jobs for native GUI features; no new server protocol."""
from __future__ import annotations
import json
import os
import sys
from pathlib import Path


def write_json(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + f'.{os.getpid()}.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False), encoding='utf-8')
    temporary.replace(path)


def main():
    request = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'DeepSeekBridge'))
    progress = lambda fraction, message: write_json(request['progress'], {'fraction': fraction, 'message': message})
    cancelled = lambda: Path(request['cancel']).exists()
    try:
        if cancelled():
            raise InterruptedError('Cancelled')
        if request['kind'] == 'browser_observe':
            from browser_learning import observe
            result = observe(request['args'], cancelled=cancelled)
        elif request['kind'] == 'media_local':
            from media_analysis import run
            result = run(request['args'], progress, cancelled)
        else:
            raise ValueError('Unsupported workspace operation')
    except Exception as error:
        result = {'ok': False, 'cancelled': isinstance(error, InterruptedError),
                  'error': f'{type(error).__name__}: {error}'}
    write_json(request['result'], result)


if __name__ == '__main__':
    main()
