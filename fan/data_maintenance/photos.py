"""Import owned capture files into Base64 columns and export actual image files."""
import base64
from contextlib import closing, nullcontext
import hashlib
import mimetypes
import os
from pathlib import Path
import sqlite3

from . import storage


def _tables(db):
    return {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}


def _data_url(path):
    mime = mimetypes.guess_type(path.name)[0] or 'image/png'
    return f'data:{mime};base64,' + base64.b64encode(path.read_bytes()).decode('ascii')


def import_photos(project, paths, *, progress=None, cancel_file=None, relocated_snapshots=None, remove_files=True):
    """Commit references before deleting unchanged, app-owned capture files.

    Imported user source files outside capture directories are retained. Shared
    filenames are removed only after every supported consumer has been updated.
    """
    project = Path(project).resolve()
    owned = [project / 'data' / 'tracking', project / 'data' / 'tracking' / 'snapshots', project / 'data' / 'screenshots',
             project / 'data' / 'previews', project / 'fan' / 'logs' / 'study',
             project / 'fan' / 'DeepSeekBridge' / '.runtime' / 'captures']
    removed, imported, missing = 0, 0, 0
    cleanup = {}
    tracking = paths.get('tracking')
    if not tracking or not Path(tracking).is_file():
        return {'imported': 0, 'removed': 0, 'missing': 0}
    reporter = storage._Progress(progress, cancel_file)
    with closing(sqlite3.connect(tracking, timeout=15)) as db:
        db.execute('CREATE TABLE IF NOT EXISTS media_image(id INTEGER PRIMARY KEY AUTOINCREMENT, label TEXT, data_url TEXT NOT NULL, created_ts TEXT)')
        db.commit()
        tables = _tables(db)
        for role, specs in [('tracking', [('snap_entry', 'image_path', 'b64'), ('element', 'image_path', 'b64'),
                                          ('snip', 'image_path', None), ('qa_item', 'source_image', None)]),
                            ('macro', [('patterns', 'screenshot', None)])]:
            path = paths.get(role)
            if not path or not Path(path).is_file():
                continue
            with (nullcontext(db) if Path(path).resolve() == Path(tracking).resolve() else closing(sqlite3.connect(path, timeout=15))) as source:
                source_tables = _tables(source)
                for table, column, embedded in specs:
                    if table not in source_tables:
                        continue
                    key_column = 'name' if table == 'patterns' else 'id'
                    condition = f" WHERE {column} IS NOT NULL AND {column}<>''"
                    if embedded:
                        # SQLite reads the byte count from record metadata, not
                        # the 100+ GiB of already-embedded image payloads.
                        condition += f' AND COALESCE(octet_length({embedded}),0)=0'
                    cursor = source.execute(f'SELECT {key_column},{column} FROM {table}' + condition)
                    batch_count, batch_bytes = 0, 0
                    for ident, value in cursor:
                        reporter.check()
                        if value.startswith(('photo:', 'snapshot:', 'data:image/')):
                            continue
                        image = Path(value)
                        if relocated_snapshots:
                            old_root = project / 'data' / 'tracking' / 'snapshots'
                            if storage._contained(image.absolute(), old_root):
                                image = Path(relocated_snapshots) / image.absolute().relative_to(old_root)
                        if not image.is_file() or storage._is_reparse(image):
                            missing += 1
                            continue
                        signature = storage._signature(image)
                        data_url = _data_url(image)
                        if signature != storage._signature(image):
                            raise storage.StorageError('Photo changed during import')
                        if embedded:
                            source.execute(f'UPDATE {table} SET {embedded}=?,{column}=\'\' WHERE {key_column}=?',
                                           (data_url.split(',', 1)[1], ident))
                            if table == 'snap_entry':
                                source.execute('UPDATE snap_entry SET b64_len=? WHERE id=?', (len(data_url.split(',', 1)[1]), ident))
                        elif role == 'macro':
                            source.execute(f'UPDATE {table} SET {column}=? WHERE {key_column}=?', (data_url, ident))
                        else:
                            photo_id = db.execute("INSERT INTO media_image(label,data_url,created_ts) VALUES(?,?,datetime('now','localtime'))",
                                                  (image.name, data_url)).lastrowid
                            if source is not db:
                                db.commit()
                            source.execute(f'UPDATE {table} SET {column}=? WHERE {key_column}=?', ('photo:' + str(photo_id), ident))
                        batch_count += 1
                        batch_bytes += len(data_url)
                        if batch_count >= 50 or batch_bytes >= 32*1024*1024:
                            source.commit()
                            batch_count, batch_bytes = 0, 0
                        imported += 1
                        real = image.resolve()
                        if remove_files and any(storage._contained(real, root.resolve()) for root in owned):
                            cleanup[str(image)] = signature
                        reporter.emit('photo-import', path=image, imported=imported)
                    source.commit()
        # Deletion is independent of reset and follows durable Base64 commits.
        for name, signature in cleanup.items():
            reporter.check()
            image = Path(name)
            if image.exists() and not storage._is_reparse(image) and storage._signature(image) == signature:
                image.unlink()
                removed += 1
    return {'imported': imported, 'removed': removed, 'missing': missing}


def export_photos(paths, destination, job_id, *, progress=None, cancel_file=None):
    folder = Path(destination).absolute() / 'Fan-images' / job_id
    if folder.exists():
        raise storage.StorageError('Image export folder already exists')
    folder.mkdir(parents=True)
    reporter = storage._Progress(progress, cancel_file, job_id=job_id)
    count = 0
    for role, specs in [('tracking', [('snap_entry', 'id', 'b64', 'image_format'), ('element', 'id', 'b64', None),
                                      ('media_image', 'id', 'data_url', None)]),
                        ('macro', [('patterns', 'name', 'screenshot', None)])]:
        path = paths.get(role)
        if not path or not Path(path).is_file():
            continue
        with closing(storage._readonly_database(Path(path).resolve())) as db:
            tables = _tables(db)
            for table, key, field, format_field in specs:
                if table not in tables:
                    continue
                query = f'SELECT {key},{field}' + (f',{format_field}' if format_field else '') + f' FROM {table}'
                for row in db.execute(query):
                    reporter.check()
                    ident, value = row[:2]
                    if not value:
                        continue
                    ext = (row[2] or 'png') if format_field else 'png'
                    if value.startswith('data:image/'):
                        header, value = value.split(',', 1)
                        ext = header.split('/', 1)[1].split(';', 1)[0]
                    elif table == 'patterns':
                        continue
                    ext = 'jpg' if ext == 'jpeg' else ext
                    if ext not in ('png', 'jpg', 'bmp', 'gif', 'webp'):
                        raise storage.StorageError('Unsupported stored image format')
                    data = base64.b64decode(value, validate=True)
                    name = hashlib.sha256(str(ident).encode()).hexdigest()[:16]
                    target = folder / f'{role}-{table}-{name}.{ext}'
                    with target.open('xb') as stream:
                        stream.write(data)
                        stream.flush()
                        os.fsync(stream.fileno())
                    if hashlib.sha256(target.read_bytes()).digest() != hashlib.sha256(data).digest():
                        raise storage.StorageError('Exported photo did not verify')
                    count += 1
                    reporter.emit('photo-export', path=target, files=count)
    storage._atomic_json(folder / 'manifest.json', {'job_id': job_id, 'images': count})
    return {'bundle': str(folder), 'images': count}
