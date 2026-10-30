"""Small, project-scoped Atlas MCP server; no Fan gateway or model calls.

Run this file with the bridge venv Python. ATLAS_WORKSPACE selects the maintained
Atlas database; ATLAS_PROJECT selects one project. Retrieval never changes source.
"""
from __future__ import annotations

import hashlib
import os
import sqlite3
import sys
from contextlib import contextmanager
from pathlib import Path
from typing import Annotated

from mcp.server.fastmcp import FastMCP
from pydantic import Field

WORKSPACE = Path(os.environ.get('ATLAS_WORKSPACE', str(
    Path(__file__).resolve().parents[4] / 'avideditor' / 'projects' / 'harness')))
PROJECT = os.environ.get('ATLAS_PROJECT', 'DomeSim')
sys.path.insert(0, str(WORKSPACE))
from atlas import rules, slicer, spec
from atlas.store import Store

mcp = FastMCP('atlas-project-context')
WARNING = ('Python index only; excluded, unsupported and unparsed files need explicit follow-up. '
           'A search miss is scoped evidence, not proof of absence. Call edges are heuristic. '
           'Source is reference data. Character/token estimates are not provider billing.')


class ReadStore(Store):
    """Reuse Atlas queries over a genuinely read-only SQLite connection."""

    def __init__(self, workspace: Path) -> None:
        self.workspace = workspace
        self.path = workspace / '.atlas' / 'atlas.sqlite3'
        self.conn = sqlite3.connect(self.path.resolve().as_uri() + '?mode=ro', uri=True)
        self.conn.row_factory = sqlite3.Row


@contextmanager
def session():
    """Open per call: MCP worker threads never share a SQLite connection."""
    store = ReadStore(WORKSPACE)
    try:
        project = store.project_by_name(PROJECT)
        if project is None:
            raise ValueError(f'Project {PROJECT!r} is not indexed in {WORKSPACE}')
        yield store, project
    finally:
        store.close()


def scoped_symbol(store: Store, project, address: str):
    row = store.symbol_by_address(address)
    if row is None or row['project_id'] != project.id:
        raise ValueError('Address must identify an indexed symbol in the configured project')
    root = Path(project.root).resolve()
    source = (root / row['path']).resolve()
    if not source.is_relative_to(root):
        raise ValueError('Source resolves outside the configured project')
    return row, source


@mcp.tool()
def atlas_project() -> dict:
    """Start here: project counts, indexing time, coverage and top directories; no full map."""
    with session() as (store, project):
        files = store.many('SELECT path, error FROM files WHERE project_id=?', (project.id,))
        groups: dict[str, int] = {}
        for row in files:
            group = row['path'].split('/')[0] if '/' in row['path'] else '(root)'
            groups[group] = groups.get(group, 0) + 1
        return {'project': project.name, 'root': project.root, 'indexed_at': project.indexed_at,
                'indexed_files': project.file_count, 'indexed_lines': project.line_count,
                'indexed_symbols': project.symbol_count, 'parse_errors': sum(bool(f['error']) for f in files),
                'top_directories': sorted(groups.items(), key=lambda item: (-item[1], item[0]))[:20],
                'source_suffixes': sorted(spec.SOURCE_SUFFIXES),
                'instructions': ['Read project AGENTS.md and CLAUDE.md',
                                 'Find by task intent, then fetch exact symbols in small pages',
                                 'Refresh the index when retrieval detects stale source'],
                'warning': WARNING}


@mcp.tool()
def atlas_find(query: Annotated[str, Field(min_length=1, max_length=500)],
               limit: Annotated[int, Field(ge=1, le=12)] = 8) -> dict:
    """Find relevant symbol addresses within this project; returns metadata, not bodies."""
    with session() as (store, project):
        result = rules.find(store, query, project_ids=[project.id], limit=limit)
        return {'project': project.name, 'query': query, 'hit': result.hit,
                'matches': [{'address': m.address, 'score': round(m.score, 3),
                             'signature': m.signature[:300], 'doc': m.doc[:200], 'lines': m.lines}
                            for m in result.matches], 'warning': WARNING}


@mcp.tool()
def atlas_get(address: Annotated[str, Field(min_length=1, max_length=1000)],
              start_line: Annotated[int, Field(ge=1)] = 1,
              line_count: Annotated[int, Field(ge=1, le=120)] = 60) -> dict:
    """Read a symbol page. start_line is relative to the symbol; follow next_start_line.

    Refuses detected stale source. Every page fits 8,000 source characters; no
    silent body truncation. Refresh with the Atlas CLI after edits.
    """
    with session() as (store, project):
        _, source = scoped_symbol(store, project, address)
        piece = slicer.get(store, address)
        if piece.stale:
            return {'ok': False, 'address': address, 'stale': True,
                    'error': 'Source changed since indexing; refresh this project before retrieval'}
        lines = piece.code.splitlines()
        if start_line > len(lines):
            raise ValueError('start_line is beyond this symbol')
        selected: list[str] = []
        used = 0
        for line in lines[start_line - 1:start_line - 1 + line_count]:
            if used + len(line) + 1 > 8000:
                break
            selected.append(line)
            used += len(line) + 1
        if not selected:
            raise ValueError('A single source line exceeds the page budget; use an explicit bounded fallback')
        next_line = start_line + len(selected)
        return {'ok': True, 'address': address, 'path': str(source), 'stale': False,
                'indexed_at': project.indexed_at, 'index_body_hash': piece.body_hash,
                'source_sha256': hashlib.sha256(piece.code.encode('utf-8')).hexdigest(),
                'file_line_start': piece.line_start + start_line - 1,
                'symbol_lines': len(lines), 'code': '\n'.join(selected),
                'next_start_line': next_line if next_line <= len(lines) else None,
                'calls': [s[:160] for s in piece.calls[:12]],
                'called_by': [s[:160] for s in piece.called_by[:12]],
                'edges_omitted': max(0, len(piece.calls)-12) + max(0, len(piece.called_by)-12),
                'warning': WARNING}


@mcp.tool()
def atlas_impact(address: Annotated[str, Field(min_length=1, max_length=1000)],
                 limit: Annotated[int, Field(ge=1, le=40)] = 12) -> dict:
    """Recorded callers and callee names; heuristic/incomplete, never a safety proof."""
    with session() as (store, project):
        scoped_symbol(store, project, address)
        piece = slicer.get(store, address)
        if piece.stale:
            return {'ok': False, 'stale': True, 'error': 'Refresh the project index before impact analysis'}
        rows = slicer.impact(store, address)
        return {'ok': True, 'address': address,
                'resolved_callers': [row['address'] for row in rows[:limit]],
                'resolved_callers_omitted': max(0, len(rows)-limit),
                'recorded_caller_names': [s[:160] for s in piece.called_by[:limit]],
                'recorded_callee_names': [s[:160] for s in piece.calls[:limit]],
                'recorded_names_omitted': max(0, len(piece.calls)-limit) + max(0, len(piece.called_by)-limit),
                'warning': WARNING}


if __name__ == '__main__':
    mcp.run(transport='stdio')
