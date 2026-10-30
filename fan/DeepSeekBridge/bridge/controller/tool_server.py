"""Same bounded filesystem tools in both modes; optional Atlas tools alongside."""
from __future__ import annotations
import functools
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Annotated
from mcp.server.fastmcp import FastMCP
from pydantic import Field
from . import store, workspace

RUN_ID = os.environ.get('ATLAS_CONTROLLER_RUN','')
mcp = FastMCP('controller')


def run():
    value = store.get(RUN_ID)
    if value['status']!='running':
        raise ValueError('Run is no longer active')
    return value,Path(value['root'])


def observed(function):
    @functools.wraps(function)
    def invoke(*args,**kwargs):
        store.event(RUN_ID,'tool_start',{'name':function.__name__,'arguments':kwargs})
        try:
            result = function(*args,**kwargs)
            store.event(RUN_ID,'tool_result',{'name':function.__name__,'result':result,
                         'response_characters':len(json.dumps(result,default=str))})
            return result
        except Exception as error:
            store.event(RUN_ID,'tool_error',{'name':function.__name__,'error':str(error)})
            raise
    return invoke


@mcp.tool()
@observed
def workspace_list(directory: str = '', offset: Annotated[int,Field(ge=0)] = 0) -> dict:
    """List up to 100 immediate entries in a project-relative directory; follow next_offset."""
    _,root = run()
    path = workspace.safe_path(root,directory)
    entries = sorted(p.name+('/' if p.is_dir() else '') for p in path.iterdir()
                     if workspace.permitted(p.relative_to(root)) and not p.is_symlink())
    return {'directory':directory,'entries':entries[offset:offset+100],
            'next_offset':offset+100 if len(entries)>offset+100 else None}


@mcp.tool()
@observed
def workspace_read(path: str, start_line: Annotated[int,Field(ge=1)] = 1,
                   line_count: Annotated[int,Field(ge=1,le=120)] = 80) -> dict:
    """Read a bounded source/document page. Paths are relative to this run only."""
    _,root = run()
    source = workspace.safe_path(root,path)
    if source.suffix.lower() not in workspace.SUFFIXES or source.stat().st_size>2_000_000:
        raise ValueError('Not an eligible text source')
    lines = source.read_text(encoding='utf-8-sig',errors='replace').splitlines()
    selected,used = [],0
    for line in lines[start_line-1:start_line-1+line_count]:
        if used+len(line)+1>8000:
            break
        selected.append(line)
        used+=len(line)+1
    if not selected and start_line<=len(lines):
        raise ValueError('One line exceeds the page budget')
    next_line=start_line+len(selected)
    return {'path':path,'start_line':start_line,'lines':len(lines),'code':'\n'.join(selected),
            'next_start_line':next_line if next_line<=len(lines) else None,
            'file_sha256':hashlib.sha256(source.read_bytes()).hexdigest()}


@mcp.tool()
@observed
def workspace_replace(path: str, old: Annotated[str,Field(min_length=1,max_length=20000)],
                      new: Annotated[str,Field(max_length=50000)],
                      expected_sha256: Annotated[str,Field(pattern='^[a-f0-9]{64}$')]) -> dict:
    """Replace one unique source fragment in an edit run, without resending a whole file.

    Use file_sha256 from workspace_read. Refuses stale content and ambiguous matches.
    Preserves UTF-8 BOM and existing newline style; refreshes Atlas after the edit.
    """
    value,root=run()
    if value['settings']['access']!='edit':
        raise ValueError('This is a read-only run')
    target=workspace.safe_path(root,path)
    if target.suffix.lower() not in workspace.SUFFIXES or target.stat().st_size>2_000_000:
        raise ValueError('Not an eligible source/text file')
    original=target.read_bytes()
    if hashlib.sha256(original).hexdigest()!=expected_sha256:
        raise ValueError('Source changed; read the current fragment and hash again')
    text=original.decode('utf-8-sig')
    newline='\r\n' if '\r\n' in text else '\n'
    before=old.replace('\r\n','\n').replace('\n',newline)
    after=new.replace('\r\n','\n').replace('\n',newline)
    if text.count(before)!=1:
        raise ValueError('old must match exactly one fragment; provide a unique source span')
    updated=text.replace(before,after,1).encode('utf-8')
    if original.startswith(b'\xef\xbb\xbf'):
        updated=b'\xef\xbb\xbf'+updated
    target.write_bytes(updated)
    if value['mode']=='atlas':
        store.event(RUN_ID,'index_refreshed',workspace.index(root,root.parent/'atlas'))
    return {'replaced':path,'file_sha256':hashlib.sha256(updated).hexdigest(),
            'applied_to_working_copy':False}


@mcp.tool()
@observed
def workspace_search(query: Annotated[str,Field(min_length=1,max_length=200)],
                     path_contains: str = '', offset: Annotated[int,Field(ge=0)] = 0) -> dict:
    """Literal case-insensitive search over source/text; 30 bounded matching lines per page."""
    _,root = run()
    matches=[]
    seen=0
    for source,relative in workspace.sources(root):
        if path_contains.lower() not in relative.as_posix().lower():
            continue
        for number,line in enumerate(source.read_text(encoding='utf-8-sig',errors='replace').splitlines(),1):
            if query.lower() in line.lower():
                if seen>=offset:
                    matches.append({'path':relative.as_posix(),'line':number,'text':line[:220]})
                seen+=1
                if len(matches)>=31:
                    return {'matches':matches[:30],'next_offset':offset+30}
    return {'matches':matches,'next_offset':None}


@mcp.tool()
@observed
def workspace_write(path: str, content: Annotated[str,Field(max_length=200000)]) -> dict:
    """Write source in an edit-enabled run snapshot. Original and working copy are untouched."""
    value,root = run()
    if value['settings']['access']!='edit':
        raise ValueError('This is a read-only run')
    target=workspace.safe_path(root,path)
    if target.suffix.lower() not in workspace.SUFFIXES:
        raise ValueError('Only source/text files can be written')
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(content,encoding='utf-8')
    if value['mode']=='atlas':
        metadata=workspace.index(root,root.parent/'atlas')
        store.event(RUN_ID,'index_refreshed',metadata)
    return {'written':path,'characters':len(content),'applied_to_working_copy':False}


@mcp.tool()
@observed
def workspace_test(command: list[str]) -> dict:
    """Request human approval for an exact command in this run. Waits for dashboard decision."""
    _,root=run()
    if not command or len(command)>40 or sum(map(len,command))>6000:
        raise ValueError('Supply a bounded argv array, not a shell command string')
    # PATH may point to an unrelated agent's venv or a Windows app alias.
    # Resolve before approval so the operator sees the executable actually used.
    executable=sys.executable if command[0].lower() in {'python','python.exe','python3','python3.exe'} else shutil.which(command[0])
    if not executable:
        raise ValueError('Executable is not available: '+command[0])
    command=[str(Path(executable).resolve()),*command[1:]]
    identity=uuid.uuid4().hex[:12]
    with store.db() as db:
        db.execute('INSERT INTO approvals VALUES(?,?,?,?,?)',
                   (identity,RUN_ID,json.dumps(command),'pending',time.time()))
    store.event(RUN_ID,'approval_required',{'id':identity,'command':command,'cwd':str(root)})
    for _ in range(600):
        run()
        with store.db() as db:
            status=db.execute('SELECT status FROM approvals WHERE id=?',(identity,)).fetchone()['status']
        if status!='pending':
            break
        time.sleep(1)
    else:
        status='expired'
        with store.db() as db:
            db.execute("UPDATE approvals SET status='expired' WHERE id=? AND status='pending'",(identity,))
    if status!='approved':
        return {'executed':False,'decision':status,'approval_id':identity}
    environment={k:v for k,v in os.environ.items() if not any(s in k.upper() for s in ('TOKEN','SECRET','API_KEY'))}
    child=subprocess.Popen(command,cwd=root,env=environment,stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                           text=True,encoding='utf-8',errors='replace',creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    store.event(RUN_ID,'command_started',{'approval_id':identity,'command':command,'cwd':str(root),'pid':child.pid})
    try:
        output,_=child.communicate(timeout=180)
    except subprocess.TimeoutExpired:
        if os.name=='nt':
            subprocess.run(['taskkill','/PID',str(child.pid),'/T','/F'],capture_output=True)
        else:
            child.kill()
        output,_=child.communicate()
        store.event(RUN_ID,'command_finished',{'approval_id':identity,'timed_out':True})
        return {'executed':True,'decision':'approved','approval_id':identity,'exit_code':None,
                'timed_out':True,'timeout_phase':'command_execution','output':output[-16000:]}
    store.event(RUN_ID,'command_finished',{'approval_id':identity,'exit_code':child.returncode})
    return {'executed':True,'decision':'approved','approval_id':identity,'exit_code':child.returncode,
            'output':output[-16000:],'output_truncated':len(output)>16000}


def enable_atlas() -> None:
    value,root=run()
    if value['mode']!='atlas':
        return
    sys.path.insert(0,str(workspace.HARNESS))
    from .. import atlas_mcp
    atlas_mcp.WORKSPACE=root.parent/'atlas'
    atlas_mcp.PROJECT='domesim-atlas'
    for name in ('atlas_project','atlas_find','atlas_get','atlas_impact'):
        mcp.add_tool(observed(getattr(atlas_mcp,name)),name=name)


if __name__=='__main__':
    enable_atlas()
    mcp.run(transport='stdio')
