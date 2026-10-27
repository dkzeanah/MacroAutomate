"""Loopback-only gateway; Python/MCP and AHK communicate through a FIFO queue."""
from __future__ import annotations
import json
import os
import queue
import sqlite3
import threading
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal
from urllib.parse import quote, parse_qs

from fastapi import FastAPI, Request, HTTPException, Header, Body
from fastapi.responses import PlainTextResponse, Response
from pydantic import BaseModel, Field, ValidationError
from jsonschema.exceptions import ValidationError as UnitValidationError, SchemaError as UnitSchemaError
from .common import ROOT, TOKEN, storage_path
from .catalog import TOOLS as TOOL_SCHEMAS, FAN_TOOLS, SCRIPT_TOOLS, CATALOG_TOOLS, LOCAL_PAGE_TOOLS, LOCAL_JOB_TOOLS, JOB_READ_ONLY_TOOLS, validate

DB = storage_path('BRIDGE_DB', ROOT / 'bridge.sqlite3')
TOOL_TIMEOUT = float(os.getenv('TOOL_TIMEOUT', '30'))
TOOLS = set(TOOL_SCHEMAS)
_pending: queue.Queue[Call] = queue.Queue()
_fan_pending: queue.Queue[Call] = queue.Queue()
_inflight: dict[str, Call] = {}
_guard = threading.RLock()


@dataclass
class Call:
    name: str
    arg: str
    task_id: str | None = None
    channel: str = 'worker'
    run_id: str | None = None
    id: str = field(default_factory=lambda: uuid.uuid4().hex)
    event: threading.Event = field(default_factory=threading.Event)
    result: dict | None = None


def db_write(kind: str, subject: str, payload: dict) -> None:
    """Append an immutable event to the SQLite execution history."""
    DB.parent.mkdir(parents=True, exist_ok=True)
    at = datetime.now(timezone.utc).isoformat()
    if kind in ('agent_usage', 'vision_usage'):
        from .pricing import estimate
        payload = {**payload, 'cost_estimate': estimate(payload, payload.get('model', ''), payload.get('started_at', at))}
    with sqlite3.connect(DB, timeout=10) as db:
        db.execute('PRAGMA journal_mode=WAL')
        db.execute('CREATE TABLE IF NOT EXISTS events ('
                   'id INTEGER PRIMARY KEY, at TEXT NOT NULL, kind TEXT NOT NULL, '
                   'subject TEXT NOT NULL, payload TEXT NOT NULL)')
        db.execute('INSERT INTO events(at,kind,subject,payload) VALUES(?,?,?,?)',
                   (at, kind, subject,
                    json.dumps(payload, ensure_ascii=False)))
        if kind in ('task_started', 'task_finished', 'task_cancelled'):
            from .sequences import update
            update(db, subject, payload.get('status', 'running'), datetime.now(timezone.utc).isoformat())


def authorize(token: str | None) -> None:
    if not TOKEN or not token or token != TOKEN:
        raise HTTPException(status_code=401, detail='Invalid bridge token')


app = FastAPI(title='DeepSeek AHK Bridge', docs_url=None, redoc_url=None)
from .chrome_connector import router as chrome_router
app.include_router(chrome_router)


@app.middleware('http')
async def explicit_utf8(request: Request, call_next):
    response = await call_next(request)
    if response.headers.get('content-type', '').startswith('application/json'):
        response.headers['content-type'] = 'application/json; charset=utf-8'
    return response


@app.get('/health')
def health(x_bridge_token: str | None = Header(default=None)) -> dict:
    authorize(x_bridge_token)
    state = {}
    try:
        state_file = ROOT / '.runtime' / 'services.json'
        if time.time() - state_file.stat().st_mtime < 6:
            state = json.loads(state_file.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        pass
    from .automation import active_runs
    with sqlite3.connect(DB, timeout=10) as db:
        running_tasks = db.execute("SELECT COUNT(*) FROM tasks WHERE status='running'").fetchone()[0]
    with _guard:
        active_tools = [call.name for call in _inflight.values() if not call.event.is_set()]
    from .chrome_connector import active_calls as chrome_active_calls
    active_tools.extend(chrome_active_calls())
    from .job_applications import library as job_library, initialize as job_initialize
    with job_library.connect() as db:
        job_initialize(db)
        job_active=db.execute("SELECT COUNT(*) FROM application_run WHERE status='running' AND deadline>?",(time.time(),)).fetchone()[0]
    return {'healthy': True, 'windows_worker': worker_connected(), 'managed_scripts': active_runs(),
            'activity': {'running_tasks': running_tasks, 'tools': active_tools, 'application_runs':job_active},
            'fan_connected': time.monotonic() - _fan_last_seen < 5,
            'services': state, 'tools': sorted(TOOLS), 'agent_mode': 'unified'}


_last_seen = 0.0
_fan_last_seen = 0.0

def worker_connected() -> bool:
    return time.monotonic() - _last_seen < 5


def native_probe(args):
    """Private local native round trip for memory lookup; no model transport."""
    call = Call(name='fan_page_probe', arg=json.dumps(args, ensure_ascii=False), channel='fan')
    with _guard:
        _inflight[call.id] = call
        _fan_pending.put(call)
    try:
        if not call.event.wait(45):
            raise HTTPException(status_code=504, detail='Chrome page verification timed out')
        return call.result
    finally:
        with _guard:
            _inflight.pop(call.id, None)


@app.post('/tools/{name}')
def tools(name: str, args: dict = Body(...),
          x_bridge_token: str | None = Header(default=None),
          x_bridge_task: str | None = Header(default=None),
          x_bridge_run: str | None = Header(default=None),
          x_bridge_parent: str | None = Header(default=None),
          x_bridge_origin: str | None = Header(default=None)) -> dict:
    authorize(x_bridge_token)
    from . import chains
    task = x_bridge_task if isinstance(x_bridge_task, str) else ''
    parent = x_bridge_parent if isinstance(x_bridge_parent, str) else ''
    origin = x_bridge_origin if isinstance(x_bridge_origin, str) else ('deepseek' if task else 'local')
    if name in LOCAL_PAGE_TOOLS | LOCAL_JOB_TOOLS and task:
        from .job_sharing import enabled
        if not enabled():
            raise HTTPException(status_code=403, detail='Job-site sharing is not enabled for the approved api.deepseek.com destination')
    if task:
        with sqlite3.connect(DB, timeout=10) as db:
            if not db.execute('SELECT 1 FROM tasks WHERE id=?', (task,)).fetchone():
                raise HTTPException(status_code=409, detail='Unknown task')
    try:
        if task and chains.control(DB, task)['paused']:
            if name == 'daa_trace':
                return {'ok': True, 'paused': True}
            raise ValueError('Automation paused locally; resume in the native workbench before retrying')
        step = chains.begin(DB, task, name, args, origin, parent)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    if step:
        from .window_targets import lookup,bind
        inputs=args.get('inputs') if isinstance(args.get('inputs'),dict) else {}
        target=lookup(DB,task,args.get('hwnd') or inputs.get('hwnd',0)) if task else {}
        if target:bind(DB,task,target,step['id'])
        db_write('chain_step_started', task, {**step, 'origin': origin, 'parent_id': parent})
    with chains.scope(step or chains.CURRENT.get()):
        try:
            result = _tools(name, args, x_bridge_token, x_bridge_task, x_bridge_run)
        except Exception as exc:
            chains.finish(DB, step, {'ok': False, 'error': str(getattr(exc, 'detail', exc))[:1000]})
            raise
        else:
            chains.finish(DB, step, result)
            if step:
                db_write('chain_step_finished', task, {**step, 'ok': result.get('ok'), 'verified': result.get('verified', False)})
            return result


def _tools(name: str, args: dict, x_bridge_token=None, x_bridge_task=None, x_bridge_run=None) -> dict:
    authorize(x_bridge_token)
    if name in LOCAL_PAGE_TOOLS | LOCAL_JOB_TOOLS and x_bridge_task:
        from .job_sharing import enabled
        if not enabled():
            raise HTTPException(status_code=403, detail='Job-site sharing is not enabled for the approved api.deepseek.com destination')
    if x_bridge_task:
        with sqlite3.connect(DB, timeout=10) as db:
            row = db.execute('SELECT status,tool_scope FROM tasks WHERE id=?', (x_bridge_task,)).fetchone()
        from .automation import valid_run
        owned_run = bool(x_bridge_run and valid_run(x_bridge_run, x_bridge_task))
        if not row or row[0] == 'cancelled' or (row[0] != 'running' and not (row[0] == 'complete' and owned_run)) or (x_bridge_run and not owned_run):
            raise HTTPException(status_code=409, detail='Task is no longer running')
        if row[1] == 'job_read_only' and name not in JOB_READ_ONLY_TOOLS:
            raise HTTPException(status_code=403, detail='This task only permits job-page observation and planning; input, scripts, uploads and submissions are disabled')
    if name not in TOOLS:
        raise HTTPException(status_code=404, detail='Unknown tool')
    if len(json.dumps(args, ensure_ascii=False).encode('utf-8')) > 220000:
        raise HTTPException(status_code=413, detail='Tool arguments too large')
    try:
        args = validate(name, args)
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors(include_input=False))
    verified_probe = None
    task_created = ''
    if x_bridge_task:
        with sqlite3.connect(DB, timeout=10) as db:
            task_created = db.execute('SELECT created_at FROM tasks WHERE id=?', (x_bridge_task,)).fetchone()[0]
        if name in ('fan_window_learn','fan_window_knowledge','fan_project_paths','fan_window_probe','fan_window_survey','fan_window_shortcut'):
            from .window_knowledge import require_sharing
            try:
                require_sharing()
            except ValueError as exc:
                raise HTTPException(status_code=403, detail=str(exc)) from exc
    if name in LOCAL_PAGE_TOOLS | LOCAL_JOB_TOOLS and x_bridge_task:
        from . import job_sharing, page_learner
        # Local configuration, consent changes and run controls remain private.
        permitted = LOCAL_PAGE_TOOLS | {'fan_job_config_get', 'fan_job_status', 'fan_job_searches', 'fan_job_discover'}
        try:
            if name not in permitted:
                raise ValueError('This tool is local-only; a remote model cannot change consent, applicant settings or run controls')
            job_sharing.require()
            if args.get('page_id'):
                job_sharing.require(page_learner.get(args['page_id'])['url'])
            if name in ('fan_page_learn', 'fan_page_probe', 'fan_page_resolve'):
                verified_probe = native_probe({'hwnd': args.get('hwnd', 0)})
                if not verified_probe.get('ok'):
                    return {'ok': False, 'error': verified_probe.get('error', 'Current Chrome page cannot be verified')}
                job_sharing.require(verified_probe['url'])
        except ValueError as exc:
            raise HTTPException(status_code=403, detail=str(exc))
    if name == 'window_activate' and not args['title'].strip():
        raise HTTPException(status_code=422, detail='title is required')
    if name == 'text_type' and not args['text']:
        raise HTTPException(status_code=422, detail='text is required')
    if name == 'key_send' and (not args['keys'] or not all(c.isalnum() or c in '^!+#{}_- ' for c in args['keys'])):
        raise HTTPException(status_code=422, detail='Invalid AutoHotkey key expression')
    if name in LOCAL_JOB_TOOLS:
        from .job_applications import dispatch
        try:
            result = dispatch(name, args)
            if x_bridge_task and name == 'fan_job_config_get':
                from .job_sharing import export_profile
                result = {'ok': True, 'configuration': export_profile(result['configuration'])}
            if x_bridge_task and name == 'fan_job_status':
                from .job_sharing import url_allowed
                result['items'] = [item for item in result['items'] if url_allowed(item['job_url'])]
                result['counts_scope'] = 'Local queue totals; item details restricted to approved origins'
            if x_bridge_task and name == 'fan_job_searches':
                from .job_sharing import policy
                result['searches'] = [entry for entry in result['searches'] if entry['site'] in policy()['sites']]
            return result
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc))
    if name in SCRIPT_TOOLS:
        if x_bridge_task and name=='ahk_script_run' and args.get('inputs',{}).get('hwnd'):
            prepared=tools('fan_window_prepare',{'hwnd':args['inputs']['hwnd']},x_bridge_token,x_bridge_task,x_bridge_run)
            if not prepared.get('ok'):return prepared
            from .window_targets import bind
            from .chains import CURRENT
            bind(DB,x_bridge_task or '',prepared['target_window'],(CURRENT.get() or {}).get('id',''))
        from .automation import dispatch
        payload = args
        db_write('tool_requested', name, {'task_id': x_bridge_task or '', 'run_id': x_bridge_run or '', 'arg': {k: (f'<{len(v)} chars>' if k == 'source' else v) for k,v in payload.items()}})
        result = dispatch(name, payload, task_id=x_bridge_task)
        from . import reuse
        try:
            reuse.observe(name,args,result,x_bridge_task or '')
            from .window_knowledge import artifact_use
            credit = artifact_use(name,args,result,x_bridge_task or '',task_created)
            if credit:
                result['knowledge_reuse'] = credit
                db_write('knowledge_reuse',x_bridge_task or '',{'task_id':x_bridge_task or '',**credit})
        except Exception as learning_error:
            db_write('learning_error',name,{'error':str(learning_error)[:300]})
        db_write('tool_result', name, {'task_id': x_bridge_task or '', 'run_id': x_bridge_run or '', 'result': result if name != 'ahk_script_read' else {'ok': result.get('ok'), 'name': args['name']}})
        return result
    if name == 'automation_knowledge_search':
        from .reuse import search
        return search(**args)
    if name.startswith('daa_'):
        from . import chains, explorer_usage, units, exploration
        invoke = lambda child, parameters: tools(child, parameters, x_bridge_token, x_bridge_task, x_bridge_run)
        emit = lambda kind, data: db_write(kind, x_bridge_task or 'local', {'task_id': x_bridge_task or '', **data})
        try:
            if name == 'daa_chain_status':
                return chains.snapshot(DB, x_bridge_task or '', **args)
            if name == 'daa_unit_save':
                return units.save(**args)
            if name == 'daa_unit_list':
                return units.listing(**args)
            if name == 'daa_unit_run':
                result = units.run(invoke=invoke, emit=emit, database=DB, **args)
                from .reuse import observe
                observe(name,args,result,x_bridge_task or '')
                from .window_knowledge import artifact_use
                credit = artifact_use(name,args,result,x_bridge_task or '',task_created)
                if credit:
                    result['knowledge_reuse'] = credit
                    emit('knowledge_reuse',credit)
                return result
            if name == 'daa_explore':
                return exploration.run(invoke=invoke, emit=emit, **args)
            if name == 'daa_explorer_usage':
                if x_bridge_task:
                    from .window_knowledge import require_sharing
                    require_sharing()
                    if not args.get('query', '').strip():
                        raise ValueError('A relevant Explorer path query is required; full local history stays private')
                return explorer_usage.ranked(**args)
            if name == 'daa_trace':
                if args.get('hwnd') and args.get('phase') in ('before','return'):
                    prepared=invoke('fan_window_prepare',{'hwnd':args['hwnd']})
                    if not prepared.get('ok'):
                        return prepared
                emit('daa_action', args)
                return {'ok': True, 'recorded': True, 'chain_step': chains.CURRENT.get(),
                        'note': 'Caller-reported action marker; after-phase is not independent verification.'}
            if name == 'daa_cue':
                from .tour import cue
                return cue(DB, x_bridge_task or '', emit=emit, **args)
        except (ValueError, KeyError, TypeError, UnitValidationError, UnitSchemaError) as exc:
            return {'ok': False, 'error': str(exc)[:800]}
    if name in ('fan_window_learn', 'fan_window_knowledge', 'fan_project_paths'):
        from . import window_knowledge, project_paths
        if x_bridge_task and name == 'fan_project_paths' and not args.get('query', '').strip():
            raise HTTPException(status_code=422, detail='Supply a task-relevant path/project query; the full Desktop index stays local')
        if x_bridge_task and name == 'fan_window_knowledge' and not (args.get('query', '').strip() or args.get('window_id')):
            raise HTTPException(status_code=422, detail='Supply a relevant window id or app/title query')
        if name == 'fan_window_knowledge':
            try:
                return window_knowledge.lookup(**args)
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
        if name == 'fan_project_paths':
            return project_paths.search(**args)
        db_write('tool_requested', name, {'task_id': x_bridge_task or '', 'arg': args})
        result = window_knowledge.learn(args, lambda child, parameters: tools(child, parameters, x_bridge_token, x_bridge_task, x_bridge_run), x_bridge_task or '')
        db_write('tool_result', name, {'task_id': x_bridge_task or '', 'result': result})
        if result.get('knowledge_reuse'):
            db_write('knowledge_reuse', x_bridge_task or '', {'task_id': x_bridge_task or '', **result['knowledge_reuse']})
        return result
    if name in ('context_map_find','context_map_get'):
        from .context_map import dispatch
        return dispatch(name,args)
    if name in CATALOG_TOOLS:
        from .library import dispatch
        return dispatch(name, args)
    if name == 'fan_page_probe' and verified_probe:
        from .job_sharing import export_probe
        return export_probe(verified_probe)
    if name == 'fan_page_learn' and not args.get('refresh', False):
        from . import page_learner
        probe = verified_probe or native_probe({'hwnd': args.get('hwnd', 0)})
        if not probe.get('ok'):
            return probe
        remembered = page_learner.reuse(probe)
        if remembered:
            if x_bridge_task:
                from .job_sharing import page_result
                return page_result(remembered)
            return remembered
    if name in ('fan_page_list', 'fan_page_get', 'fan_page_resolve', 'fan_page_image'):
        from . import page_learner
        try:
            if name == 'fan_page_get':
                result = page_learner.get(**args)
                if x_bridge_task:
                    from .job_sharing import export_page
                    exported = export_page(result, result['elements'])
                    return {**exported, 'matches': result['matches'], 'offset': result['offset'], 'has_more': result['has_more']}
                return result
            if name == 'fan_page_list':
                result = page_learner.list_pages(**args)
                if x_bridge_task:
                    from .job_sharing import url_allowed
                    result['pages'] = [p for p in result['pages'] if url_allowed(p['url'])]
                return result
            if name=='fan_page_image' and args['page_id'].startswith('chrome-'):
                page=page_learner.get(args['page_id'],limit=1)
                if args.get('element_id'):
                    raise ValueError('Owned Chrome maps currently provide the whole-page image; native maps provide element crops')
                if x_bridge_task:
                    from .job_sharing import page_result
                    result=page_result(page)
                else:result={'ok':True,'page_id':page['page_id'],'url':page['url']}
                return {**result,'image_path':page['capture_path'],'frame':page['frame'],'geometry':page['frame']['region']}
            args = page_learner.prepare(name, args)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc))
    if name in FAN_TOOLS:
        from .chains import CURRENT
        from .window_targets import lookup
        payload = {**args, '_task_id': x_bridge_task or '', '_run_id': x_bridge_run or '',
                   '_chain_step': (CURRENT.get() or {}).get('id', ''),
                   '_bound_window': lookup(DB,x_bridge_task,args.get('hwnd',0)) if x_bridge_task else {}}
        value = json.dumps(payload, ensure_ascii=False, separators=(',', ':'))
        channel = 'fan'
    else:
        value = {'mouse_click': f"{args.get('x', 0)},{args.get('y', 0)}",
                 'mouse_move': f"{args.get('x', 0)},{args.get('y', 0)}",
                 'window_activate': args.get('title', ''), 'text_type': args.get('text', ''),
                 'key_send': args.get('keys', '')}.get(name, '')
        channel = 'worker'
        if name in ('mouse_click','mouse_move','text_type','key_send') and (x_bridge_task or args.get('hwnd')):
            from .window_targets import lookup
            target=lookup(DB,x_bridge_task or '',args.get('hwnd',0))
            if args.get('hwnd') and not target:
                prepared=tools('fan_window_prepare',{'hwnd':args['hwnd']},x_bridge_token,x_bridge_task,x_bridge_run)
                target=prepared.get('target_window',{})
            if not target:
                raise HTTPException(status_code=409,detail='Assign a window with window_activate or fan_window_prepare before input; the foreground is not a target.')
            value='@BOUND@'+json.dumps({'value':value,'target_window':target,'task_id':x_bridge_task or '', 'deadline':time.time()+TOOL_TIMEOUT-1},ensure_ascii=False)
        elif name=='window_activate' and x_bridge_task:
            value='@BOUND@'+json.dumps({'value':value,'target_window':{},'task_id':x_bridge_task,'deadline':time.time()+TOOL_TIMEOUT-1})
    call = Call(name=name, arg=value, task_id=x_bridge_task, channel=channel,
                run_id=x_bridge_run if x_bridge_task else None)
    db_write('tool_requested', name, {'id': call.id, 'task_id': x_bridge_task or '', 'run_id': x_bridge_run or '', 'arg': value})
    with _guard:
        _inflight[call.id] = call
        (_fan_pending if channel == 'fan' else _pending).put(call)
    try:
        timeout = (240 if name == 'fan_taskbar_learn' else 90 if name in ('fan_page_learn','fan_taskbar_open','fan_window_survey') else 45 if name == 'fan_page_resolve' else
                   args.get('timeout_seconds', TOOL_TIMEOUT) + 15 if name == 'fan_workflow_run' else TOOL_TIMEOUT)
        if not call.event.wait(timeout):
            db_write('tool_timeout', name, {'id': call.id, 'task_id': x_bridge_task or ''})
            raise HTTPException(status_code=504, detail='Fan application did not respond in time' if channel == 'fan' else 'AHK worker did not respond in time')
        assert call.result is not None
        from .window_targets import bind
        from .chains import CURRENT
        identity=call.result.get('target_window') or call.result.get('frame',{})
        bind(DB,x_bridge_task or '',identity,(CURRENT.get() or {}).get('id',''))
        db_write('tool_result', name, {'id': call.id, 'task_id': x_bridge_task or '', 'run_id': x_bridge_run or '', 'result': call.result})
        if name == 'fan_page_learn' and call.result.get('ok'):
            from .page_learner import build
            result = build(call.result)
            if x_bridge_task:
                from .job_sharing import require, page_result
                require(result['url'])
                return page_result(result)
            return result
        if x_bridge_task and name == 'fan_page_image' and call.result.get('ok'):
            from .page_learner import get
            page = get(args['page_id'])
            from .job_sharing import require, page_result
            require(page['url'])
            saved={k:v for k,v in page_result(page).items() if k not in ('image_path','annotated_image_path','capture_path','grid_image_path')}
            return {**saved, **call.result, 'page_id': page['page_id'], 'url': page['url'], 'title': page['title'],
                    'frame': page['frame'], 'coverage': page['coverage']}
        if channel == 'fan':
            from .library import observe
            observe(name, args, call.result)
        from . import reuse
        try:
            reuse.observe(name,args,call.result,x_bridge_task or '')
            from .window_knowledge import observe as observe_window
            observe_window(name, args, call.result, x_bridge_task or '')
            from .window_knowledge import artifact_use
            credit = artifact_use(name,args,call.result,x_bridge_task or '',task_created)
            if credit:
                call.result['knowledge_reuse'] = credit
            if call.result.get('knowledge_reuse'):
                db_write('knowledge_reuse',x_bridge_task or '',{'task_id':x_bridge_task or '',**call.result['knowledge_reuse']})
        except Exception as learning_error:
            db_write('learning_error',name,{'error':str(learning_error)[:300]})
        return call.result
    finally:
        with _guard:
            _inflight.pop(call.id, None)


@app.get('/worker/next', response_class=PlainTextResponse)
def worker_next(x_bridge_token: str | None = Header(default=None)) -> str:
    """Plain UTF-8 newline protocol to avoid an external AHK JSON dependency."""
    global _last_seen
    authorize(x_bridge_token)
    _last_seen = time.monotonic()
    return next_call(_pending)


def next_call(pending: queue.Queue) -> str:
    try:
        call = pending.get_nowait()
    except queue.Empty:
        return 'NONE'
    with _guard:
        if call.id not in _inflight:
            return 'NONE'
    if call.task_id:
        with sqlite3.connect(DB, timeout=10) as db:
            row = db.execute('SELECT status FROM tasks WHERE id=?', (call.task_id,)).fetchone()
        from .automation import valid_run
        if not row or (row[0] != 'running' and not (row[0] == 'complete' and call.run_id and valid_run(call.run_id, call.task_id))):
            call.result = {'ok': False, 'error': 'Task cancelled before tool execution'}
            call.event.set()
            return 'NONE'
    return '\n'.join((call.id, call.name, quote(call.arg, safe='') if call.arg else '-'))


@app.get('/fan/next', response_class=PlainTextResponse)
def fan_next(x_bridge_token: str | None = Header(default=None)) -> str:
    """Native Fan RPC uses a separate queue so the standalone worker cannot steal calls."""
    global _fan_last_seen
    authorize(x_bridge_token)
    _fan_last_seen = time.monotonic()
    return next_call(_fan_pending)


@app.post('/worker/result', response_class=PlainTextResponse)
async def worker_result(request: Request, x_bridge_token: str | None = Header(default=None)) -> str:
    authorize(x_bridge_token)
    return await accept_result(request, 'worker')


@app.post('/fan/result', response_class=PlainTextResponse)
async def fan_result(request: Request, x_bridge_token: str | None = Header(default=None)) -> str:
    authorize(x_bridge_token)
    return await accept_result(request, 'fan')


async def accept_result(request: Request, channel: str) -> str:
    body = (await request.body()).decode('utf-8')
    data = parse_qs(body, keep_blank_values=True)
    call_id = data.get('id', [''])[0]
    value = data.get('result', [''])[0]
    with _guard:
        pending_call = _inflight.get(call_id)
    result_limit = 4000000 if pending_call and pending_call.name == 'fan_page_learn' else 750000
    if len(value.encode('utf-8')) > result_limit:
        raise HTTPException(status_code=413, detail='Result too large')
    try:
        decoded = json.loads(value)
    except json.JSONDecodeError:
        raise HTTPException(status_code=422, detail='Invalid result JSON')
    if not isinstance(decoded, dict):
        raise HTTPException(status_code=422, detail='Tool result must be an object')
    with _guard:
        call = _inflight.get(call_id)
        if call is None or call.event.is_set() or call.channel != channel:
            raise HTTPException(status_code=404, detail='Unknown or completed call')
        call.result = decoded
        call.event.set()
    return 'OK'


class HistoryMessage(BaseModel):
    role: Literal['user', 'assistant']
    content: str = Field(max_length=16000)


class TaskArgs(BaseModel):
    prompt: str = Field(min_length=1, max_length=12000)
    # Legacy clients may still submit mode; every new task uses the unified agent.
    mode: Literal['agent', 'chat', 'desktop'] = 'agent'
    history: list[HistoryMessage] = Field(default_factory=list, max_length=20)
    tool_scope: Literal['full', 'job_read_only'] = 'full'
    images: list[str] = Field(default_factory=list, max_length=4)


class ImageUpload(BaseModel):
    data_url: str = Field(max_length=11200000)
    label: str = Field(default='Pasted image', max_length=200)


@app.post('/images')
def upload_image(args: ImageUpload, x_bridge_token: str | None = Header(default=None)):
    authorize(x_bridge_token)
    from .attachments import store
    try:
        return {'ok': True, **store(DB, args.data_url, args.label)}
    except (ValueError, TypeError) as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@app.get('/images/{identity}')
def image_content(identity: str, x_bridge_token: str | None = Header(default=None)):
    authorize(x_bridge_token)
    from .attachments import get
    try:
        image = get(DB, identity)
        return Response(image['data'], media_type=image['mime'], headers={'Cache-Control': 'no-store'})
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


class NativeObservation(BaseModel):
    task_id: str = Field(default='', max_length=80)
    tool: str = Field(default='', max_length=100)
    family: str = Field(max_length=80)
    method: str = Field(max_length=180)
    phase: Literal['start', 'end'] = 'start'
    detail: dict = Field(default_factory=dict)
    chain_step: str = Field(default='', max_length=80)


@app.post('/observations')
def native_observation(args: NativeObservation, x_bridge_token: str | None = Header(default=None)):
    authorize(x_bridge_token)
    if args.detail.get('target_window'):
        from .window_targets import bind
        bind(DB,args.task_id,args.detail['target_window'],args.chain_step)
    if args.detail.get('interaction') and args.task_id:
        from . import chains
        with sqlite3.connect(DB, timeout=10) as db:
            row = db.execute('SELECT status FROM tasks WHERE id=?', (args.task_id,)).fetchone()
        if not row or row[0] != 'running':
            raise HTTPException(status_code=409, detail='Task stopped before native input')
        if chains.control(DB,args.task_id)['paused']:
            return {'ok': True, 'paused': True}
        try:
            step = chains.begin(DB,args.task_id,'native:' + args.method,args.detail,'native',args.chain_step)
            chains.finish(DB,step,{'ok':True,'status':'requested','note':'Input marker recorded before execution; inspect subsequent evidence.'})
        except ValueError as exc:
            raise HTTPException(status_code=409,detail=str(exc)) from exc
    db_write('native_method', args.task_id or 'native', args.model_dump())
    return {'ok': True}


@app.post('/tasks')
def create_task(args: TaskArgs, x_bridge_token: str | None = Header(default=None)) -> dict:
    """Queue a task from AHK for an active agent-loop daemon."""
    authorize(x_bridge_token)
    task_id = uuid.uuid4().hex
    from .attachments import get
    try:
        for identity in args.images:
            get(DB, identity)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    with sqlite3.connect(DB, timeout=10) as db:
        db.execute('CREATE TABLE IF NOT EXISTS tasks ('
                   'id TEXT PRIMARY KEY, prompt TEXT NOT NULL, status TEXT NOT NULL, '
                   'response TEXT NOT NULL DEFAULT "", created_at TEXT NOT NULL)')
        created = datetime.now(timezone.utc).isoformat()
        db.execute('INSERT INTO tasks(id,prompt,status,created_at,mode,history,tool_scope,attachments) VALUES(?,?,?,?,?,?,?,?)',
                   (task_id, args.prompt, 'queued', datetime.now(timezone.utc).isoformat(),
                    'agent', json.dumps([m.model_dump() for m in args.history], ensure_ascii=False), args.tool_scope, json.dumps(args.images)))
        from .sequences import record
        record(db, task_id, args.prompt, created)
    db_write('task_queued', task_id, {'prompt': args.prompt, 'mode': 'agent', 'images': args.images})
    return {'id': task_id, 'status': 'queued'}


@app.get('/tasks/{task_id}')
def task_status(task_id: str, x_bridge_token: str | None = Header(default=None)) -> dict:
    authorize(x_bridge_token)
    with sqlite3.connect(DB, timeout=10) as db:
        row = db.execute('SELECT status,response FROM tasks WHERE id=?', (task_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail='Task not found')
    from .chains import control
    return {'id': task_id, 'status': row[0], 'response': row[1], **control(DB,task_id)}


class InterjectionArgs(BaseModel):
    text: str = Field(min_length=1,max_length=8000)


class ApplyInterjectionArgs(BaseModel):
    id: str = Field(pattern=r'^[a-f0-9]{32}$')


@app.post('/tasks/{task_id}/interject')
def interject_task(task_id: str,args: InterjectionArgs,x_bridge_token: str | None = Header(default=None)):
    authorize(x_bridge_token)
    from .interjections import hold
    try:result=hold(DB,task_id,args.text)
    except ValueError as exc:raise HTTPException(status_code=409,detail=str(exc)) from exc
    db_write('operator_interjection',task_id,{'task_id':task_id,**result,'text':args.text})
    return result


@app.post('/tasks/{task_id}/continue-interjection')
def continue_interjection(task_id: str,args: ApplyInterjectionArgs,x_bridge_token: str | None = Header(default=None)):
    authorize(x_bridge_token)
    from .interjections import apply
    try:return apply(DB,task_id,args.id,lambda identity:cancel_task(identity,x_bridge_token),db_write)
    except ValueError as exc:raise HTTPException(status_code=409,detail=str(exc)) from exc


@app.get('/history')
def task_history(x_bridge_token: str | None = Header(default=None)) -> dict:
    authorize(x_bridge_token)
    with sqlite3.connect(DB, timeout=10) as db:
        rows = db.execute('SELECT id,prompt,status,response,created_at,mode FROM tasks ORDER BY created_at DESC LIMIT 40').fetchall()
    return {'tasks': [dict(zip(('id','prompt','status','response','created_at','mode'), row)) for row in rows]}


@app.get('/tasks/{task_id}/events')
def task_events(task_id: str, after: int = 0, x_bridge_token: str | None = Header(default=None)) -> dict:
    authorize(x_bridge_token)
    with sqlite3.connect(DB, timeout=10) as db:
        rows = db.execute('SELECT id,at,kind,payload FROM events WHERE subject=? AND id>? ORDER BY id LIMIT 250', (task_id, max(0, after))).fetchall()
    return {'events': [{'id': row[0], 'at': row[1], 'kind': row[2], 'payload': json.loads(row[3])} for row in rows],
            'cursor': rows[-1][0] if rows else max(0, after)}


@app.post('/tasks/{task_id}/cancel')
def cancel_task(task_id: str, x_bridge_token: str | None = Header(default=None)) -> dict:
    authorize(x_bridge_token)
    from .automation import has_active_task_run
    with sqlite3.connect(DB, timeout=10) as db:
        row = db.execute('SELECT status FROM tasks WHERE id=?', (task_id,)).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail='Task not found')
        eligible = row[0] in ('queued', 'running') or (row[0] == 'complete' and has_active_task_run(task_id))
        changed = db.execute("UPDATE tasks SET status='cancelled' WHERE id=?", (task_id,)).rowcount if eligible else 0
    if changed:
        from .automation import cancel_for_task
        cancel_for_task(task_id)
        db_write('task_cancelled', task_id, {'task_id': task_id, 'status': 'cancelled'})
        with _guard:
            for call in _inflight.values():
                if call.task_id == task_id and not call.event.is_set():
                    call.result = {'ok': False, 'error': 'Task cancelled'}
                    call.event.set()
    return task_status(task_id, x_bridge_token)


def init_db() -> None:
    db_write('system', 'startup', {})
    with sqlite3.connect(DB, timeout=10) as db:
        db.execute('BEGIN IMMEDIATE')
        db.execute('CREATE TABLE IF NOT EXISTS tasks ('
                   'id TEXT PRIMARY KEY, prompt TEXT NOT NULL, status TEXT NOT NULL, '
                   'response TEXT NOT NULL DEFAULT "", created_at TEXT NOT NULL)')
        columns = {row[1] for row in db.execute('PRAGMA table_info(tasks)')}
        if 'mode' not in columns:
            db.execute("ALTER TABLE tasks ADD COLUMN mode TEXT NOT NULL DEFAULT 'chat'")
        if 'history' not in columns:
            db.execute("ALTER TABLE tasks ADD COLUMN history TEXT NOT NULL DEFAULT '[]'")
        if 'tool_scope' not in columns:
            db.execute("ALTER TABLE tasks ADD COLUMN tool_scope TEXT NOT NULL DEFAULT 'full'")
        if 'attachments' not in columns:
            db.execute("ALTER TABLE tasks ADD COLUMN attachments TEXT NOT NULL DEFAULT '[]'")
        from .sequences import initialize
        initialize(db)
        db.execute('INSERT OR IGNORE INTO automation_sequence(task_id,prompt,created_at,status) SELECT id,prompt,created_at,status FROM tasks')
        db.execute('UPDATE automation_sequence SET status=(SELECT status FROM tasks WHERE id=task_id) WHERE task_id IN (SELECT id FROM tasks)')
        db.execute("UPDATE tasks SET mode='agent' WHERE mode IN ('chat','desktop')")


init_db()
