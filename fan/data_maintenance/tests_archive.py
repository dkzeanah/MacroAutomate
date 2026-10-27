import json
from contextlib import closing
from pathlib import Path
import sqlite3
from unittest.mock import patch

import pytest

from fan.data_maintenance import archive, cli, storage
from fan.data_maintenance.tests_cli import fixture, request


def test_reset_preserves_indexes_triggers_views_fts_and_restarts_ids(tmp_path):
    project, original = fixture(tmp_path)
    with closing(sqlite3.connect(original)) as db:
        db.executescript('CREATE TABLE history(id INTEGER PRIMARY KEY AUTOINCREMENT, value TEXT);'
                         'CREATE INDEX ix_history ON history(value);'
                         'CREATE VIEW history_view AS SELECT value FROM history;'
                         'CREATE TRIGGER history_insert AFTER INSERT ON history BEGIN INSERT INTO marker(value) VALUES(new.value); END;'
                         "CREATE VIRTUAL TABLE search USING fts5(text); INSERT INTO search VALUES('old text');"
                         "INSERT INTO history(value) VALUES('old event');")
    path = request(project, tmp_path / 'drive', mode='export')
    cli.run(path)
    with closing(sqlite3.connect(original)) as db:
        assert db.execute('SELECT COUNT(*) FROM history_view').fetchone()[0] == 0
        assert db.execute('SELECT COUNT(*) FROM search').fetchone()[0] == 0
        assert db.execute("INSERT INTO history(value) VALUES('fresh')").lastrowid == 1
        assert db.execute('SELECT value FROM marker').fetchone()[0] == 'fresh'


def test_partial_reset_recovers_before_startup_without_resetting_completed_rows_again(tmp_path):
    project, original = fixture(tmp_path)
    with closing(sqlite3.connect(project / 'data' / 'appmap.db')) as db:
        db.executescript("CREATE TABLE app(id INTEGER); INSERT INTO app VALUES(7);")
    path = request(project, tmp_path / 'drive')
    real_replace = archive.os.replace
    def stop_on_second(source, target):
        if Path(target) == project / 'data' / 'appmap.db':
            raise OSError('simulated power loss')
        return real_replace(source, target)
    with patch.object(archive.os, 'replace', side_effect=stop_on_second):
        with pytest.raises(OSError):
            cli.run(path)
    # First store is already fresh. Recovery completes the second store.
    cli.recover(path)
    for database, table in [(original, 'marker'), (project / 'data' / 'appmap.db', 'app')]:
        with closing(sqlite3.connect(database)) as db:
            assert db.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0] == 0
    with closing(sqlite3.connect(original)) as db:
        db.execute("INSERT INTO marker VALUES(1,'later work')")
        db.commit()
    cli.recover(path)
    with closing(sqlite3.connect(original)) as db:
        assert db.execute('SELECT value FROM marker').fetchone()[0] == 'later work'


def test_failed_schema_stage_never_replaces_original(tmp_path):
    project, original = fixture(tmp_path)
    path = request(project, tmp_path / 'drive')
    with patch.object(archive, '_empty_schema', side_effect=storage.StorageError('schema failed')):
        with pytest.raises(storage.StorageError):
            cli.run(path)
    with closing(sqlite3.connect(original)) as db:
        assert db.execute('SELECT value FROM marker').fetchone()[0] == 'preserved'
    result = json.loads((path.parent / 'result.json').read_text())
    assert storage.verify_bundle(result['manifest'])['ok']


def test_archive_tampering_blocks_reset(tmp_path):
    project, original = fixture(tmp_path)
    result = storage.prepare_export({'tracking': original}, None, tmp_path / 'drive', mode='offload')
    target = Path(result['targets']['tracking'])
    with closing(sqlite3.connect(target)) as db:
        db.execute("UPDATE marker SET value='tampered'")
        db.commit()
    with pytest.raises(storage.StorageError):
        archive.reset_databases(result['manifest'])
    with closing(sqlite3.connect(original)) as db:
        assert db.execute('SELECT value FROM marker').fetchone()[0] == 'preserved'
