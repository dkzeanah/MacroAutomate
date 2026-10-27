from contextlib import closing
import json
from pathlib import Path
import sqlite3

from bridge import common, automation, library


def project_fixture(tmp_path, monkeypatch):
    project = tmp_path / 'project'
    root = project / 'fan' / 'DeepSeekBridge'
    root.mkdir(parents=True)
    monkeypatch.setattr(common, 'ROOT', root)
    path = project / 'data' / 'fan.sqlite'
    (project / 'fan' / 'storage_paths.json').write_text(json.dumps({'unified_db': str(path), 'unified_initialized': True}))
    return project, path


def test_standalone_bridge_routes_both_roles_and_seeds_all_schemas(tmp_path, monkeypatch):
    project, path = project_fixture(tmp_path, monkeypatch)
    monkeypatch.setenv('BRIDGE_DB', str(tmp_path / 'stale.sqlite3'))
    assert common.storage_path('BRIDGE_DB', tmp_path / 'other.db') == path
    assert common.storage_path('FAN_TOOL_INDEX', tmp_path / 'catalog.db') == path
    with closing(sqlite3.connect(path)) as db:
        tables = {row[0] for row in db.execute('SELECT name FROM sqlite_master')}
        assert {'patterns', 'app', 'appmap_app', 'snap_entry', 'records', 'tasks', 'app_file'} <= tables


def test_learning_prompt_reads_database_and_ignores_old_loose_reports(tmp_path, monkeypatch):
    project, path = project_fixture(tmp_path, monkeypatch)
    common.storage_path('BRIDGE_DB', path)
    relative = 'data/learning_insights/latest-brief.txt'
    loose = project / relative
    loose.parent.mkdir()
    loose.write_text('stale loose report')
    assert common.read_app_document(project, relative) == ''
    with closing(sqlite3.connect(path)) as db:
        db.execute('INSERT INTO app_file VALUES(?,?,?)', (relative, 'current observed evidence', 'now'))
        db.commit()
    assert common.read_app_document(project, relative, 7) == 'current'


def test_generated_scripts_are_database_records_not_required_source_files(tmp_path, monkeypatch):
    project, path = project_fixture(tmp_path, monkeypatch)
    common.storage_path('BRIDGE_DB', path)
    monkeypatch.setattr(automation, 'ROOT', project / 'fan' / 'DeepSeekBridge')
    monkeypatch.setattr(automation, 'SCRIPTS', project / 'fan' / 'DeepSeekBridge' / 'agent_scripts')
    monkeypatch.setattr(library, 'INDEX', path)
    source = '#Requires AutoHotkey v2.0\nExitApp\n'
    result = automation.dispatch('ahk_script_write', {'name': 'stored.ahk', 'source': source})
    assert result['ok'] and not (automation.SCRIPTS / 'stored.ahk').exists()
    assert automation.dispatch('ahk_script_read', {'name': 'stored.ahk'})['source'] == source
    stale = automation.SCRIPTS / 'old.ahk'
    stale.write_text(source)
    assert automation.dispatch('ahk_script_list', {})['scripts'] == ['stored.ahk']
    assert not automation.dispatch('ahk_script_run', {'name': 'old.ahk'})['ok']
    assert stale.read_text() == source
