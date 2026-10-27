import base64
from contextlib import closing
from pathlib import Path
import sqlite3

from fan.data_maintenance import photos
from fan.data_maintenance.tests_cli import fixture


PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/W1sAAAAASUVORK5CYII=')


def test_shared_legacy_photo_import_and_binary_export(tmp_path):
    project, tracking = fixture(tmp_path)
    image = project / 'data' / 'tracking' / 'snapshots' / 'one.png'
    image.parent.mkdir(parents=True)
    image.write_bytes(PNG)
    user_source = tmp_path / 'user-source.png'
    user_source.write_bytes(PNG)
    with closing(sqlite3.connect(tracking)) as db:
        db.executescript('CREATE TABLE snap_entry(id INTEGER PRIMARY KEY,image_path TEXT,b64 TEXT,b64_len INTEGER,image_format TEXT);'
                         'CREATE TABLE snip(id INTEGER PRIMARY KEY,image_path TEXT);'
                         'CREATE TABLE qa_item(id INTEGER PRIMARY KEY,source_image TEXT);')
        db.execute("INSERT INTO snap_entry VALUES(1,?,'',0,'png')", (str(image),))
        db.execute('INSERT INTO snip VALUES(1,?)', (str(image),))
        db.execute('INSERT INTO qa_item VALUES(1,?)', (str(user_source),))
        db.commit()
    result = photos.import_photos(project, {'tracking': tracking})
    assert result == {'imported': 3, 'removed': 1, 'missing': 0}
    assert not image.exists() and user_source.read_bytes() == PNG
    with closing(sqlite3.connect(tracking)) as db:
        path, value = db.execute('SELECT image_path,b64 FROM snap_entry').fetchone()
        assert path == '' and base64.b64decode(value) == PNG
        assert db.execute('SELECT image_path FROM snip').fetchone()[0].startswith('photo:')
    exported = photos.export_photos({'tracking': tracking}, tmp_path / 'export', 'photos')
    assert exported['images'] == 3
    for file in Path(exported['bundle']).glob('*.png'):
        assert file.read_bytes() == PNG
    assert photos.import_photos(project, {'tracking': tracking})['imported'] == 0
