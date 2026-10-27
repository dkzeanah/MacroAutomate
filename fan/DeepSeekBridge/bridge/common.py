"""Common configuration and bridge client."""
from __future__ import annotations
import os
import json
import sqlite3
import sys
from contextlib import closing
from pathlib import Path
import httpx
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / '.env')
HOST = '127.0.0.1'
PORT = int(os.getenv('BRIDGE_PORT', '8765'))
BASE_URL = f'http://{HOST}:{PORT}'
TOKEN = os.getenv('BRIDGE_TOKEN', '')


def storage_path(environment: str, fallback: Path) -> Path:
    pointer = ROOT.parent / 'storage_paths.json'
    if pointer.is_file():
        config = json.loads(pointer.read_text(encoding='utf-8-sig'))
        if config.get('unified_db'):
            path = Path(config['unified_db'])
            if not path.exists():
                sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
                from fan.data_maintenance.unified import seed
                seed(path)
            return path
    return Path(os.getenv(environment, str(fallback)))


def read_app_document(project: Path, relative: str, limit: int = 7500) -> str:
    pointer = project / 'fan' / 'storage_paths.json'
    config = json.loads(pointer.read_text(encoding='utf-8-sig')) if pointer.exists() else {}
    if config.get('unified_db'):
        path = Path(config['unified_db'])
        if not path.exists():
            return ''
        with closing(sqlite3.connect(path.as_uri() + '?mode=ro', uri=True, timeout=2)) as db:
            row = db.execute('SELECT substr(content,1,?) FROM app_file WHERE path=?', (limit, relative)).fetchone()
        return row[0] if row else ''
    path = project / relative
    if not path.is_file():
        return ''
    with path.open(encoding='utf-8') as handle:
        return handle.read(limit)


def request_tool(name: str, args: dict, timeout: float | None = None, task_id: str | None = None, origin: str = '') -> dict:
    if timeout is None:
        timeout = (args.get('timeout_seconds', 600) + 15 if name in ('daa_unit_run', 'daa_cue') else
                   600 if name == 'daa_explore' else 110 if name in ('fan_window_menu', 'fan_window_probe_item') else
                   180 if name == 'fan_window_learn' else 110 if name == 'fan_window_survey' else 270 if name == 'fan_taskbar_learn' else 110 if name == 'fan_taskbar_open' else 40)
    """Call the local gateway from an MCP tool or CLI."""
    with httpx.Client(timeout=timeout) as client:
        headers = {'X-Bridge-Token': TOKEN}
        if task_id:
            headers['X-Bridge-Task'] = task_id
        if origin:
            headers['X-Bridge-Origin'] = origin
        response = client.post(f'{BASE_URL}/tools/{name}', json=args, headers=headers)
        if not response.is_success:
            try:
                detail = response.json().get('detail', 'request failed')
            except ValueError:
                detail = 'request failed'
            raise ValueError(f'{name}: HTTP {response.status_code}: {str(detail)[:1800]}')
        return response.json()
