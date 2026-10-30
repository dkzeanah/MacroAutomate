"""The small MCP surface must preserve scope, bounded pages and stale detection."""
import sqlite3

import pytest

from bridge import atlas_mcp
from atlas.index import build_project_index, to_rows
from atlas.store import Store


@pytest.fixture
def indexed(tmp_path, monkeypatch):
    workspace = tmp_path / 'workspace'
    roots = {}
    with_source = 'def explain():\n' + ''.join(f'    value_{n} = {n}\n' for n in range(160))
    store = Store(workspace)
    try:
        for name in ('DomeSim', 'Other'):
            root = tmp_path / name
            root.mkdir()
            (root / 'model.py').write_text(with_source, encoding='utf-8')
            index = build_project_index(root, name=name, bucket='sim3d')
            identity = store.upsert_project(name, root, bucket='sim3d', file_count=index.file_count,
                                           line_count=index.line_count, symbol_count=index.symbol_count)
            store.replace_index(identity, *to_rows(index))
            roots[name] = root
    finally:
        store.close()
    monkeypatch.setattr(atlas_mcp, 'WORKSPACE', workspace)
    monkeypatch.setattr(atlas_mcp, 'PROJECT', 'DomeSim')
    return roots


def test_project_scope_and_readonly_database(indexed):
    result = atlas_mcp.atlas_find('explain')
    assert result['matches'] and all('@sim3d/DomeSim:' in m['address'] for m in result['matches'])
    with pytest.raises(ValueError, match='configured project'):
        atlas_mcp.atlas_get('@sim3d/Other:model.py#explain')
    with atlas_mcp.session() as (store, _):
        with pytest.raises(sqlite3.OperationalError, match='readonly'):
            store.conn.execute('DELETE FROM symbols')


def test_pages_reassemble_source_without_silent_truncation(indexed):
    address = '@sim3d/DomeSim:model.py#explain'
    start = 1
    chunks = []
    while start is not None:
        page = atlas_mcp.atlas_get(address, start_line=start, line_count=60)
        assert page['ok'] and len(page['code']) <= 8000
        chunks.append(page['code'])
        start = page['next_start_line']
    expected = (indexed['DomeSim'] / 'model.py').read_text(encoding='utf-8').rstrip('\n')
    assert '\n'.join(chunks) == expected
    assert atlas_mcp.atlas_project()['indexed_files'] == 1


def test_stale_source_is_withheld(indexed):
    path = indexed['DomeSim'] / 'model.py'
    path.write_text(path.read_text(encoding='utf-8').replace('value_0 = 0', 'value_0 = 99'), encoding='utf-8')
    for action in (atlas_mcp.atlas_get, atlas_mcp.atlas_impact):
        result = action('@sim3d/DomeSim:model.py#explain')
        assert result['stale'] and not result['ok'] and 'code' not in result
