"""Isolate the gateway authorization token from test import order."""
import os
import tempfile
import pytest
_import_database = tempfile.TemporaryDirectory(prefix='fan-bridge-tests-', ignore_cleanup_errors=True)
os.environ['BRIDGE_DB'] = os.path.join(_import_database.name, 'imports.sqlite3')
from bridge import gateway, library, automation


@pytest.fixture(autouse=True)
def deterministic_token(monkeypatch, tmp_path):
    monkeypatch.setattr(gateway, 'TOKEN', 'test-local-token')
    monkeypatch.setattr(library, 'INDEX', tmp_path / 'catalog.sqlite3')
    monkeypatch.setattr(automation, 'RUN_OUTPUT', tmp_path / 'runs')
