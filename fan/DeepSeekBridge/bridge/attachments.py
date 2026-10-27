"""Explicitly pasted images stay local until their prompt is sent for analysis."""
from __future__ import annotations
import base64
import hashlib
import sqlite3
import struct
from datetime import datetime, timezone
from pathlib import Path

MAX_BYTES = 8 * 1024 * 1024


def initialize(db):
    db.execute('CREATE TABLE IF NOT EXISTS agent_image ('
               'id TEXT PRIMARY KEY,mime TEXT,width INTEGER,height INTEGER,data BLOB,label TEXT,created_at TEXT)')


def store(database: Path, data_url: str, label: str = 'Pasted image') -> dict:
    header, encoded = data_url.split(',', 1)
    if header not in ('data:image/png;base64', 'data:image/jpeg;base64'):
        raise ValueError('Paste a PNG or JPEG image')
    if len(encoded) > MAX_BYTES * 4 // 3 + 8:
        raise ValueError('Image exceeds 8 MiB')
    data = base64.b64decode(encoded, validate=True)
    if not data or len(data) > MAX_BYTES:
        raise ValueError('Image is empty or exceeds 8 MiB')
    mime = header[5:-7]
    if mime == 'image/png':
        if len(data) < 33 or data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
            raise ValueError('Invalid PNG image')
        width, height = struct.unpack('>II', data[16:24])
    else:
        if not data.startswith(b'\xff\xd8\xff'):
            raise ValueError('Invalid JPEG image')
        at, width, height = 2, 0, 0
        while at + 9 < len(data):
            if data[at] != 255:
                break
            marker = data[at + 1]
            at += 2
            if marker in (0xD8, 0xD9):
                continue
            size = int.from_bytes(data[at:at + 2], 'big')
            if size < 2:
                break
            if marker in (0xC0, 0xC1, 0xC2):
                height, width = struct.unpack('>HH', data[at + 3:at + 7])
                break
            at += size
    if width < 1 or height < 1 or width * height > 12000000 or max(width, height) > 8192:
        raise ValueError('Image must be at most 12 million pixels and 8192 pixels per side')
    identity = hashlib.sha256(data).hexdigest()
    with sqlite3.connect(database, timeout=10) as db:
        initialize(db)
        db.execute('INSERT OR IGNORE INTO agent_image VALUES(?,?,?,?,?,?,?)',
                   (identity, mime, width, height, data, label[:200], datetime.now(timezone.utc).isoformat()))
    return {'id': identity, 'mime': mime, 'width': width, 'height': height, 'label': label[:200]}


def get(database: Path, identity: str) -> dict:
    with sqlite3.connect(database, timeout=10) as db:
        initialize(db)
        db.row_factory = sqlite3.Row
        row = db.execute('SELECT * FROM agent_image WHERE id=?', (identity,)).fetchone()
    if not row:
        raise ValueError('Pasted image is unavailable')
    return dict(row)


def materialize(database: Path, identity: str) -> dict:
    from .vision import CAPTURES
    record = get(database, identity)
    folder = CAPTURES / 'attachments'
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / (identity + ('.png' if record['mime'] == 'image/png' else '.jpg'))
    path.write_bytes(record['data'])
    return {'image_path': str(path), 'attachment_id': identity,
            'frame': {'capture_source': 'user_pasted_image', 'coordinates': 'image_pixels',
                      'title': record['label'], 'region': {'x': 0, 'y': 0, 'w': record['width'], 'h': record['height']}}}
