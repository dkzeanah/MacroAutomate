import base64
from contextlib import closing
import json
from pathlib import Path
import sqlite3

import pytest

from fan.data_maintenance import unified, cli, photos, storage
from fan.data_maintenance.tests_cli import fixture, request
from fan.data_maintenance.tests_photos import PNG


def tables(path):
    with closing(sqlite3.connect(path)) as db:
        return {row[0] for row in db.execute('SELECT name FROM sqlite_master')}


def test_all_roles_share_one_file_and_missing_active_reseeds_without_legacy_import(tmp_path):
    project, legacy = fixture(tmp_path)
    original = legacy.read_bytes()
    result = unified.bootstrap(project)
    active = Path(result['database'])
    assert result['seeded'] and active.name == 'fan.sqlite'
    assert len(set(cli.managed_paths(project).values())) == 1
    expected = {'app', 'appmap_app', 'snap_entry', 'element', 'snip', 'qa_item', 'study_source',
                'vs_element', 'usage_element', 'patterns', 'sequences', 'ui_element',
                'events', 'tasks', 'records', 'revisions', 'media_image', 'app_file', 'app_config', 'discovered_target'}
    assert expected <= tables(active)
    with closing(sqlite3.connect(active)) as db:
        db.execute("INSERT INTO app_file VALUES('data/notes/old.txt','old history','now')")
        db.commit()
    archived = tmp_path / 'moved.sqlite'
    active.rename(archived)
    assert unified.bootstrap(project)['seeded']
    with closing(sqlite3.connect(active)) as db:
        assert db.execute('SELECT count(*) FROM app_file').fetchone()[0] == 0
    assert 'marker' not in tables(active)
    assert legacy.read_bytes() == original
    with closing(sqlite3.connect(archived)) as db:
        assert db.execute('SELECT content FROM app_file').fetchone()[0] == 'old history'


def test_bootstrap_keeps_existing_data_and_database_preferences(tmp_path):
    project, _ = fixture(tmp_path)
    active = Path(unified.bootstrap(project)['database'])
    with closing(sqlite3.connect(active)) as db:
        db.execute("INSERT INTO app_file VALUES('data/notes/new.txt','new','now')")
        db.execute("INSERT OR REPLACE INTO app_config VALUES('preferences',?)", (json.dumps({'learning_monitor': 3}),))
        db.commit()
    assert not unified.bootstrap(project)['seeded']
    with closing(sqlite3.connect(active)) as db:
        assert db.execute('SELECT content FROM app_file').fetchone()[0] == 'new'
        assert json.loads(db.execute('SELECT value FROM app_config').fetchone()[0])['learning_monitor'] == 3


def moved_fixture(tmp_path):
    project, original = fixture(tmp_path)
    archive = tmp_path / 'drive' / 'tracking.db'
    archive.parent.mkdir()
    original.rename(archive)
    paths = unified.legacy_paths(project)
    for role, sql in {
        'appmap': "CREATE TABLE app(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT); INSERT INTO app VALUES(7,'learned'); CREATE TABLE ui_element(id INTEGER PRIMARY KEY,app_id INTEGER REFERENCES app(id)); INSERT INTO ui_element VALUES(3,7); CREATE VIEW apps AS SELECT name FROM app; CREATE INDEX idx_name ON app(name);",
        'macro': "CREATE TABLE patterns(name TEXT PRIMARY KEY,screenshot TEXT); INSERT INTO patterns VALUES('sample','');",
        'bridge': "CREATE TABLE events(id INTEGER PRIMARY KEY,payload TEXT); INSERT INTO events VALUES(2,'observed');",
        'catalog': "CREATE TABLE records(name TEXT PRIMARY KEY,content TEXT); INSERT INTO records VALUES('script:one','source');",
    }.items():
        paths[role].parent.mkdir(parents=True, exist_ok=True)
        with closing(sqlite3.connect(paths[role])) as db:
            db.executescript(sql)
    note = project / 'data' / 'notes' / 'one.txt'
    note.parent.mkdir()
    note.write_text('Saved note', encoding='utf-16')
    return project, archive, paths


def test_merge_namespaces_collision_preserves_ids_views_and_sequences_and_is_repeatable(tmp_path):
    project, archive, paths = moved_fixture(tmp_path)
    before = {role: path.read_bytes() for role, path in paths.items() if path.exists()}
    result = unified.consolidate(project, archive)
    assert len(result['stores']) == 4
    with closing(sqlite3.connect(archive)) as db:
        assert db.execute('SELECT value FROM marker').fetchone()[0] == 'preserved'
        assert db.execute('SELECT id,name FROM appmap_app').fetchone() == (7, 'learned')
        assert db.execute('SELECT name FROM apps').fetchone()[0] == 'learned'
        assert db.execute('PRAGMA foreign_key_list(ui_element)').fetchone()[2] == 'appmap_app'
        assert db.execute("SELECT seq FROM sqlite_sequence WHERE name='appmap_app'").fetchone()[0] == 7
        assert db.execute("SELECT content FROM app_file WHERE path='data/notes/one.txt'").fetchone()[0] == 'Saved note'
    assert unified.consolidate(project, archive)['stores'] == result['stores']
    assert all(path.read_bytes() == before[role] for role, path in paths.items() if path.exists())


def test_archive_is_not_opened_until_original_database_and_snapshots_move_finishes(tmp_path):
    project, original = fixture(tmp_path)
    archive = tmp_path / 'tracking.db'
    archive.write_bytes(b'moving-incomplete')
    with pytest.raises(storage.StorageError, match='Explorer move'):
        unified.consolidate(project, archive)
    assert archive.read_bytes() == b'moving-incomplete'
    original.unlink()
    source = project / 'data' / 'tracking' / 'snapshots' / 'still-moving.png'
    source.parent.mkdir(parents=True)
    source.write_bytes(PNG)
    with pytest.raises(storage.StorageError, match='snapshots still contain'):
        unified.consolidate(project, archive, snapshot_root=tmp_path / 'snapshots')
    assert archive.read_bytes() == b'moving-incomplete'


def test_remaining_photos_use_relocated_folder_without_reencoding_embedded_rows(tmp_path, monkeypatch):
    project, archive, paths = moved_fixture(tmp_path)
    old = project / 'data' / 'tracking' / 'snapshots' / 'cycle' / 'one.png'
    relocated = tmp_path / 'snapshots'
    photo = relocated / 'cycle' / 'one.png'
    photo.parent.mkdir(parents=True)
    photo.write_bytes(PNG)
    with closing(sqlite3.connect(archive)) as db:
        db.executescript('CREATE TABLE snap_entry(id INTEGER PRIMARY KEY,image_path TEXT,b64 TEXT,b64_len INTEGER); CREATE TABLE snip(id INTEGER PRIMARY KEY,image_path TEXT);')
        db.execute('INSERT INTO snap_entry VALUES(1,?,?,?)', (str(old), base64.b64encode(PNG).decode(), len(PNG)))
        db.execute('INSERT INTO snap_entry VALUES(2,?,?,0)', (str(old), ''))
        db.execute('INSERT INTO snip VALUES(1,?)', (str(old),))
        db.commit()
    calls = []
    original = photos._data_url
    monkeypatch.setattr(photos, '_data_url', lambda path: (calls.append(path), original(path))[1])
    result = unified.consolidate(project, archive, snapshot_root=relocated)
    assert result['photos'] == {'imported': 2, 'removed': 0, 'missing': 0}
    assert calls == [photo, photo] and photo.exists()
    with closing(sqlite3.connect(archive)) as db:
        assert base64.b64decode(db.execute('SELECT b64 FROM snap_entry WHERE id=2').fetchone()[0]) == PNG
        assert db.execute('SELECT image_path FROM snip').fetchone()[0].startswith('photo:')


def test_unified_settings_export_archives_once_then_resets_all_modules(tmp_path):
    project, _ = fixture(tmp_path)
    active = Path(unified.bootstrap(project)['database'])
    with closing(sqlite3.connect(active)) as db:
        db.execute("INSERT INTO app_file VALUES('data/notes/one.txt','archive me','now')")
        db.commit()
    path = request(project, tmp_path / 'drive', mode='export')
    cli.run(path)
    result = json.loads((path.parent / 'result.json').read_text())
    assert set(result['targets']) == {'unified'}
    with closing(sqlite3.connect(result['targets']['unified'])) as db:
        assert db.execute('SELECT content FROM app_file').fetchone()[0] == 'archive me'
    with closing(sqlite3.connect(active)) as db:
        assert db.execute('SELECT COUNT(*) FROM app_file').fetchone()[0] == 0
        assert db.execute('SELECT COUNT(*) FROM patterns').fetchone()[0] == 0
    assert unified.bootstrap(project)['seeded'] is False
    assert 'appmap_app' in tables(active)


def test_changed_side_store_is_not_imported_twice(tmp_path):
    project, archive, paths = moved_fixture(tmp_path)
    unified.consolidate(project, archive)
    with closing(sqlite3.connect(paths['macro'])) as db:
        db.execute("INSERT INTO patterns VALUES('another','')")
        db.commit()
    with pytest.raises(storage.StorageError, match='previously consolidated store changed'):
        unified.consolidate(project, archive)


def test_missing_database_never_replays_or_deletes_an_orphan_journal(tmp_path):
    path = tmp_path / 'fan.sqlite'
    journal = tmp_path / 'fan.sqlite-wal'
    journal.write_bytes(b'old history must remain intact')
    with pytest.raises(storage.StorageError, match='orphan SQLite journal'):
        unified.seed(path)
    assert not path.exists() and journal.read_bytes() == b'old history must remain intact'


def test_without_rowid_legacy_tables_copy_and_verify(tmp_path):
    project, archive, paths = moved_fixture(tmp_path)
    with closing(sqlite3.connect(paths['catalog'])) as db:
        db.executescript("CREATE TABLE revision(key TEXT PRIMARY KEY,content TEXT) WITHOUT ROWID; INSERT INTO revision VALUES('r','retained');")
    unified.consolidate(project, archive)
    with closing(sqlite3.connect(archive)) as db:
        assert db.execute('SELECT content FROM revision').fetchone()[0] == 'retained'


def test_queued_consolidation_does_not_open_either_item_while_explorer_is_moving(tmp_path, monkeypatch):
    project, original = fixture(tmp_path)
    archive = tmp_path / 'drive' / 'tracking.db'
    archive.parent.mkdir()
    archive.write_bytes(b'not a complete database yet')
    snapshots = archive.parent / 'snapshots'
    snapshots.mkdir()
    job = project / 'fan' / '.maintenance' / 'queued'
    monkeypatch.setattr(unified, 'consolidate', lambda *args, **kwargs: pytest.fail('Archive opened during Explorer move'))
    unified.queue_consolidation(project, archive, snapshots, job, wait_seconds=0)
    assert json.loads((job / 'status.json').read_text())['phase'] == 'deferred'
    assert archive.read_bytes() == b'not a complete database yet' and original.exists()


def test_maintenance_entry_point_also_reseeds_a_moved_active_database(tmp_path):
    project, _ = fixture(tmp_path)
    active = Path(unified.bootstrap(project)['database'])
    active.rename(tmp_path / 'archived.sqlite')
    path = request(project, tmp_path / 'unused', mode='images', scope='')
    cli.run(path)
    assert active.exists() and {'patterns', 'appmap_app', 'tasks'} <= tables(active)
    with closing(sqlite3.connect(active)) as db:
        assert db.execute('SELECT count(*) FROM snap_entry').fetchone()[0] == 0
