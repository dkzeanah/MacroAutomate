"""Content-addressed source snapshots; original DomeSim is never an execution root."""
from __future__ import annotations
import hashlib
import json
import os
import re
import shutil
import sys
import time
from pathlib import Path
from . import store

WORKSPACE = Path(os.environ.get('ATLAS_CONTROLLER_WORKSPACE', Path.home()/'Desktop'/'domesim-atlas'))
HARNESS = Path(os.environ.get('ATLAS_WORKSPACE', Path.home()/'Desktop'/'avideditor'/'projects'/'harness'))
SKIP = {'.git','.claude','.codex','.agents','.intelligence','.atlas','node_modules','__pycache__',
        'deliverables','exports','dist','build','private','.runtime','.pytest_cache'}
SUFFIXES = {'.py','.pyw','.js','.jsx','.ts','.tsx','.mjs','.cjs','.json','.yaml','.yml','.toml',
            '.md','.txt','.html','.css','.scss','.sql','.csv','.ps1','.cmd','.bat','.ahk','.ini','.cfg','.xml','.svg'}


def permitted(relative: Path) -> bool:
    return not any(part in SKIP or part.startswith('.venv') for part in relative.parts) and not (
        relative.name.startswith('.env') or relative.name.lower() in {'auth.json','credentials.json','.mcp.json'})


def sources(root: Path):
    for directory, dirs, files in os.walk(root, followlinks=False):
        base = Path(directory)
        dirs[:] = sorted(d for d in dirs if permitted((base/d).relative_to(root)) and not (base/d).is_symlink()
                         and not (base/d).is_junction())
        for name in sorted(files):
            path = base/name
            relative = path.relative_to(root)
            if permitted(relative) and not path.is_symlink() and path.suffix.lower() in SUFFIXES:
                if path.stat().st_size <= 2_000_000:
                    yield path,relative


def snapshot(source: Path, destination: Path) -> dict:
    if destination.exists():
        raise ValueError('Snapshot destination already exists')
    destination.mkdir(parents=True)
    manifest = {}
    stamps = {}
    for path,relative in sources(source):
        before=path.stat()
        data = path.read_bytes()
        after=path.stat()
        if (before.st_mtime_ns,before.st_size)!=(after.st_mtime_ns,after.st_size):
            raise ValueError('Working copy changed while capturing '+relative.as_posix()+'; retry the task')
        stamps[relative.as_posix()]=(after.st_mtime_ns,after.st_size)
        # Equal repo agreements in both modes; avoid an Atlas directive in the baseline.
        if relative.as_posix() == 'CLAUDE.md':
            text = data.decode('utf-8-sig').replace('\r\n','\n')
            text = re.sub(r'\n## Atlas context for code work\n.*?(?=\n## |\Z)', '\n', text, flags=re.S)
            data = text.encode('utf-8')
        target = destination/relative
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(data)
        manifest[relative.as_posix()] = hashlib.sha256(data).hexdigest()
    if not manifest:
        raise ValueError('Workspace has no eligible source files')
    final={rel.as_posix():(path.stat().st_mtime_ns,path.stat().st_size) for path,rel in sources(source)}
    if stamps!=final:
        raise ValueError('Working copy changed during snapshot capture; retry the task')
    digest = hashlib.sha256(json.dumps(manifest,sort_keys=True).encode()).hexdigest()
    return {'sha256':digest,'files':manifest,'scope':'Source/text files <=2MB. Dependencies, private settings, '
            'generated outputs and binary assets omitted from run snapshots. Runtime checks may need resources.'}


def index(root: Path, atlas_workspace: Path) -> dict:
    if str(HARNESS) not in sys.path:
        sys.path.insert(0,str(HARNESS))
    from atlas.index import build_project_index,to_rows
    from atlas.store import Store
    index = build_project_index(root,name='domesim-atlas',bucket='sim3d')
    db = Store(atlas_workspace)
    try:
        identity = db.upsert_project('domesim-atlas',root,bucket='sim3d',priority=90,
             file_count=index.file_count,line_count=index.line_count,symbol_count=index.symbol_count,
             indexed_at=time.strftime('%Y-%m-%d %H:%M:%S'))
        db.replace_index(identity,*to_rows(index))
    finally:
        db.close()
    return {'files':index.file_count,'symbols':index.symbol_count,'lines':index.line_count,
            'errors':index.errors,'coverage':'Python only; edges are heuristic'}


def safe_path(root: Path, name: str) -> Path:
    relative = Path(name)
    if relative.is_absolute() or not permitted(relative):
        raise ValueError('Use a project-relative, permitted source path')
    path = (root/relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError('Path escapes the run workspace')
    return path


def changes(run: dict,refresh: bool=False) -> list[dict]:
    if not run.get('root'):
        return []
    root = Path(run['root'])
    if not root.is_dir():
        return []
    cache=root.parent/'changes.json'
    if cache.exists() and not refresh and run['status']=='completed':
        return json.loads(cache.read_text())
    manifest_path = root.parent/'manifest.json'
    baseline = json.loads(manifest_path.read_text())['files']
    current = {rel.as_posix():hashlib.sha256(path.read_bytes()).hexdigest() for path,rel in sources(root)}
    result=[{'path':path,'kind':'added' if path not in baseline else 'deleted' if path not in current else 'modified'}
            for path in sorted(set(baseline)|set(current)) if baseline.get(path)!=current.get(path)]
    cache.write_text(json.dumps(result))
    return result
