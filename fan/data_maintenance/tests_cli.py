"""Coordinator checks using tiny stores; never touches the real databases."""
import json
from pathlib import Path
import sqlite3
from contextlib import closing
from unittest.mock import patch

from fan.data_maintenance import cli, storage


def fixture(tmp_path):
    project = tmp_path / 'project'
    (project / 'fan').mkdir(parents=True)
    (project / 'fan' / 'MacroAutomator.ahk').write_text('#Requires AutoHotkey v2.0')
    (project / 'data').mkdir()
    db = project / 'data' / 'tracking.db'
    with closing(sqlite3.connect(db)) as connection:
        connection.executescript('CREATE TABLE marker(id INTEGER PRIMARY KEY,value TEXT);'
                                 "INSERT INTO marker VALUES(1,'preserved'); PRAGMA user_version=9;")
    return project, db


def request(project, destination, mode='offload', scope='databases', ident='test_job'):
    folder = project / 'fan' / '.maintenance' / ident
    folder.mkdir(parents=True, exist_ok=True)
    content = {'id': ident, 'project': str(project), 'mode': mode, 'scope': scope,
               'destination': str(destination), 'databases': {k: str(v) for k,v in cli.managed_paths(project).items()},
               'parent': 0, 'max_seconds': 30, 'days': 30, 'row_limit': 50}
    path = folder / 'request.json'
    path.write_text(json.dumps(content))
    return path


def test_database_offload_archives_then_replaces_original_with_empty_schema(tmp_path):
    project, original = fixture(tmp_path)
    unrelated = project / 'data' / 'other.db'
    unrelated.write_text('unrelated store')
    path = request(project, tmp_path / 'drive')
    cli.run(path)
    config = cli.load_config(project)
    result = json.loads((path.parent / 'result.json').read_text())
    target = Path(result['targets']['tracking'])
    assert target.exists() and original.exists() and unrelated.read_text() == 'unrelated store'
    assert 'databases' not in config
    with closing(sqlite3.connect(target)) as connection:
        assert connection.execute('SELECT value FROM marker').fetchone()[0] == 'preserved'
        assert connection.execute('PRAGMA user_version').fetchone()[0] == 9
    with closing(sqlite3.connect(original)) as connection:
        assert connection.execute('SELECT COUNT(*) FROM marker').fetchone()[0] == 0
        assert connection.execute('PRAGMA user_version').fetchone()[0] == 9
    assert json.loads((path.parent / 'status.json').read_text())['phase'] == 'complete'
    cli.recover(path)  # Cleanup is safely idempotent after normal completion.


def test_export_resets_and_cancellation_preserves_live_rows(tmp_path):
    project, original = fixture(tmp_path)
    path = request(project, tmp_path / 'export', mode='export')
    cli.run(path)
    assert original.exists() and cli.load_config(project)['last_archive']
    with closing(sqlite3.connect(original)) as db:
        assert db.execute('SELECT COUNT(*) FROM marker').fetchone()[0] == 0
        db.execute("INSERT INTO marker VALUES(2,'new session')")
        db.commit()
    path = request(project, tmp_path / 'cancelled', ident='cancelled_job')
    (path.parent / 'cancel').write_text('cancel')
    cli.run(path)
    assert original.exists()
    with closing(sqlite3.connect(original)) as db:
        assert db.execute('SELECT value FROM marker').fetchone()[0] == 'new session'
    assert json.loads((path.parent / 'status.json').read_text())['phase'] == 'cancelled'


def test_analysis_publishes_consistent_latest_files(tmp_path):
    project, original = fixture(tmp_path)
    path = request(project, tmp_path / 'unused', mode='analyze')
    cli.run(path)
    folder = project / 'data' / 'learning_insights'
    report = json.loads((folder / 'latest.json').read_text())
    assert report['safety']['source_databases_read_only']
    assert (folder / 'latest.md').is_file() and (folder / 'latest-brief.txt').is_file()
    assert original.exists()


def test_snapshot_paths_survive_offload_and_uncommitted_crash_recovers(tmp_path):
    project, _ = fixture(tmp_path)
    snapshots = project / 'data' / 'tracking' / 'snapshots'
    snapshots.mkdir(parents=True)
    old_image = snapshots / 'cycle' / 'shot.png'
    old_image.parent.mkdir()
    old_image.write_bytes(b'image fixture')
    path = request(project, tmp_path / 'drive', scope='snapshots')
    cli.run(path)
    assert old_image.read_bytes() == b'image fixture'
    target = Path(cli.load_config(project)['snapshots']['target'])
    assert snapshots.resolve() == target.resolve()
    cli.recover(path)

    # A later staged transfer crashes after alias rename/junction, before its
    # configuration commit. Startup recovery must restore the prior alias.
    staged = storage.prepare_export({}, snapshots, tmp_path / 'drive2', mode='offload', job_id='crash_fixture')
    storage.commit_snapshots(staged['manifest'])
    second = request(project, tmp_path / 'drive2', scope='snapshots', ident='crash_fixture')
    (second.parent / 'result.json').write_text(json.dumps(staged))
    pending = project / 'fan' / '.maintenance' / 'pending.json'
    pending.write_text(json.dumps({'request': str(second)}))
    cli.recover(second)
    assert old_image.read_bytes() == b'image fixture'
    assert snapshots.resolve() == target.resolve() and not pending.exists()


def test_failed_config_commit_rolls_back_snapshot_alias(tmp_path):
    project, _ = fixture(tmp_path)
    snapshots = project / 'data' / 'tracking' / 'snapshots'
    snapshots.mkdir(parents=True)
    image = snapshots / 'shot.png'
    image.write_bytes(b'image fixture')
    path = request(project, tmp_path / 'drive', scope='snapshots')
    actual = cli.atomic_json
    def fail_config(destination, value):
        if destination.name == 'storage_paths.json':
            raise OSError('fixture config failure')
        return actual(destination, value)
    with patch.object(cli, 'atomic_json', side_effect=fail_config):
        try:
            cli.run(path)
        except OSError:
            pass
        else:
            raise AssertionError('Config failure was not surfaced')
    assert image.read_bytes() == b'image fixture' and not snapshots.is_junction()
    assert not (project / 'fan' / 'storage_paths.json').exists()
