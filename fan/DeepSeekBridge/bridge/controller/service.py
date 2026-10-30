"""Loopback dashboard API; durable paired runs and reviewed workspace promotion."""
from __future__ import annotations
import difflib
import hashlib
import json
import os
import random
import secrets
import shutil
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Literal
from fastapi import FastAPI,HTTPException,Request
from fastapi.responses import FileResponse,JSONResponse,StreamingResponse
from pydantic import BaseModel,Field
from . import adapters,store,usage,workspace

STATIC=Path(__file__).with_name('static')
TOKEN=secrets.token_urlsafe(32)
POOL=ThreadPoolExecutor(max_workers=1,thread_name_prefix='atlas-controller')
WORKSPACE_LOCK=threading.RLock()
app=FastAPI(title='Atlas Control',docs_url=None,redoc_url=None)


@app.middleware('http')
async def local_session(request: Request,call_next):
    if request.url.hostname not in {'127.0.0.1','localhost','testserver'}:
        return JSONResponse({'detail':'Loopback host required'},400)
    origin=request.headers.get('origin')
    if origin and origin!=str(request.base_url).rstrip('/'):
        return JSONResponse({'detail':'Cross-origin requests refused'},403)
    if request.url.path.startswith('/api/'):
        if not secrets.compare_digest(request.cookies.get('atlas_session',''),TOKEN):
            return JSONResponse({'detail':'Open the dashboard to establish a local session'},401)
    response=await call_next(request)
    response.headers['Cache-Control']='no-store'
    response.headers['X-Content-Type-Options']='nosniff'
    response.headers['Content-Security-Policy']="default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'"
    return response


@app.get('/')
def home():
    response=FileResponse(STATIC/'index.html')
    response.set_cookie('atlas_session',TOKEN,httponly=True,samesite='strict')
    return response


@app.get('/assets/{name}')
def asset(name: str):
    if name not in {'app.js','style.css'}:
        raise HTTPException(404)
    return FileResponse(STATIC/name)


def selected(identity: str) -> dict:
    try:
        return store.get(identity)
    except KeyError:
        raise HTTPException(404,'Run not found')


@app.get('/api/state')
def state():
    with store.db() as db:
        pending=[dict(row) for row in db.execute("SELECT * FROM approvals WHERE status='pending'")]
    index_path=store.DATA/'workspace-index.json'
    index_status=json.loads(index_path.read_text()) if index_path.exists() else None
    return {'workspace':str(workspace.WORKSPACE),'workspace_exists':workspace.WORKSPACE.is_dir(),'index':index_status,
            'providers':adapters.availability(),'runs':store.runs(),'approvals':pending,
            'snapshot_scope':'Source/text snapshots. Binary assets, environments, generated output and private settings excluded.',
            'usage_policy':'Provider-reported tokens only; unavailable fields remain unknown. Quality is manually rated.'}


class Task(BaseModel):
    prompt: str=Field(min_length=1,max_length=12000)
    provider: Literal['claude','codex','deepseek']
    mode: Literal['atlas','normal','compare']='atlas'
    model: str=Field(default='',max_length=120)
    access: Literal['read_only','edit']='read_only'
    max_turns: int=Field(default=16,ge=1,le=60)
    timeout_seconds: int=Field(default=600,ge=30,le=3600)
    budget_usd: float=Field(default=2,gt=0,le=100)
    max_output_tokens: int=Field(default=3000,ge=256,le=16000)


@app.post('/api/runs')
def submit(task: Task):
    if not workspace.WORKSPACE.is_dir():
        raise HTTPException(409,'Working copy is not ready')
    if task.mode=='compare' and task.access!='read_only':
        raise HTTPException(422,'Paired benchmarks are read-only; use a single edit run for implementation')
    provider=next(p for p in adapters.availability() if p['id']==task.provider)
    if not provider['available']:
        raise HTTPException(409,'Provider is not configured: '+provider['auth'])
    batch=uuid.uuid4().hex[:12]
    settings=task.model_dump(exclude={'prompt','provider','mode','model'})
    modes=['atlas','normal'] if task.mode=='compare' else [task.mode]
    random.SystemRandom().shuffle(modes)
    model=task.model.strip() or provider['default_model']
    identities=[store.create(batch,task.provider,mode,task.prompt,model,settings) for mode in modes]
    POOL.submit(execute_batch,batch,identities)
    return {'batch':batch,'run_ids':identities,'execution_order':modes}


def execute_batch(batch: str,identities: list[str]) -> None:
    base=store.DATA/'batches'/batch
    try:
        if all(store.get(identity)['status']=='cancelled' for identity in identities):
            return
        for identity in identities:
            if store.get(identity)['status']!='cancelled':
                store.transition(identity,('queued',),'preparing')
                store.event(identity,'preparing',{'stage':'Capturing a fixed source snapshot'})
        with WORKSPACE_LOCK:
            manifest=workspace.snapshot(workspace.WORKSPACE,base/'baseline')
        (base/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
        for identity in identities:
            if store.get(identity)['status']=='cancelled':
                continue
            root=base/identity/'source'
            root.parent.mkdir(parents=True,exist_ok=True)
            shutil.copytree(base/'baseline',root)
            (root.parent/'manifest.json').write_text(json.dumps(manifest),encoding='utf-8')
            store.update(identity,root=str(root),baseline=manifest['sha256'])
            store.event(identity,'snapshot',{'sha256':manifest['sha256'],'files':len(manifest['files']),
                        'scope':manifest['scope'],'mode_policy':'Atlas-assisted, not an enforced prohibition on native Codex reads'})
            try:
                if store.get(identity)['mode']=='atlas':
                    store.event(identity,'preparing',{'stage':'Indexing this run snapshot'})
                    metadata=workspace.index(root,root.parent/'atlas')
                    store.event(identity,'index_refreshed',metadata)
                if store.get(identity)['status']=='cancelled':
                    continue
                if not store.transition(identity,('preparing',),'running'):
                    continue
                result,measured=adapters.execute(store.get(identity))
                if store.get(identity)['status']=='cancelled':
                    continue
                store.update(identity,result=result,usage=measured)
                store.event(identity,'finalizing',{'stage':'Recording the final source diff'})
                changed=workspace.changes(store.get(identity),refresh=True)
                if not store.transition(identity,('running',),'completed',finished=time.time(),result=result,usage=measured):
                    continue
                store.event(identity,'completed',{'usage':measured,'source_changes':len(changed)})
            except Exception as error:
                if store.get(identity)['status']!='cancelled':
                    measured=store.get(identity).get('usage')
                    if measured:
                        measured['complete']=False
                    if store.transition(identity,('queued','preparing','running'),'failed',finished=time.time(),error=str(error),usage=measured):
                        store.event(identity,'failed',{'error':str(error)})
    except Exception as error:
        for identity in identities:
            if store.get(identity)['status'] not in {'cancelled','completed','failed'}:
                if store.transition(identity,('queued','preparing','running'),'failed',finished=time.time(),error=str(error)):
                    store.event(identity,'failed',{'error':str(error)})


@app.get('/api/runs/{identity}')
def detail(identity: str):
    return selected(identity)


@app.get('/api/runs/{identity}/events')
def events(identity: str,after: int=0):
    selected(identity)
    return store.events(identity,max(0,after))


@app.get('/api/runs/{identity}/stream')
async def stream(identity: str,after: int=0):
    import asyncio
    selected(identity)
    async def generate():
        cursor=after
        while True:
            values=store.events(identity,cursor)
            for value in values:
                cursor=value['id']
                yield 'id: '+str(cursor)+'\ndata: '+json.dumps(value)+'\n\n'
            if not values and selected(identity)['status'] in {'completed','failed','cancelled','interrupted'}:
                yield 'event: end\ndata: {}\n\n'
                return
            await asyncio.sleep(.6)
    return StreamingResponse(generate(),media_type='text/event-stream')


@app.post('/api/runs/{identity}/cancel')
def cancel(identity: str):
    value=selected(identity)
    if value['status'] in {'queued','preparing','running'}:
        measured=value.get('usage')
        if measured:
            measured['complete']=False
            store.update(identity,usage=measured)
        store.transition(identity,('queued','preparing','running'),'cancelled',finished=time.time())
        with store.db() as db:
            db.execute("UPDATE approvals SET status='cancelled' WHERE run_id=? AND status='pending'",(identity,))
        adapters.terminate(identity)
        store.event(identity,'cancelled',{'reason':'Operator cancelled; owned process tree terminated'})
    return selected(identity)


class Decision(BaseModel):
    approve: bool


@app.post('/api/approvals/{identity}')
def decide(identity: str,body: Decision):
    with store.db() as db:
        row=db.execute('SELECT * FROM approvals WHERE id=?',(identity,)).fetchone()
        if row is None or row['status']!='pending':
            raise HTTPException(409,'Approval is not pending')
        if selected(row['run_id'])['status']!='running':
            raise HTTPException(409,'Run is not active')
        db.execute('UPDATE approvals SET status=? WHERE id=?',('approved' if body.approve else 'denied',identity))
    store.event(row['run_id'],'approval_decided',{'id':identity,'approved':body.approve})
    return {'ok':True}


@app.get('/api/comparisons/{batch}')
def compare(batch: str):
    values=[r for r in store.runs() if r['batch']==batch]
    atlas=next((r for r in values if r['mode']=='atlas'),None)
    normal=next((r for r in values if r['mode']=='normal'),None)
    if not atlas or not normal:
        raise HTTPException(404,'This batch has no paired comparison')
    report=usage.comparison(atlas,normal)
    # Completed runs already record their final change count. Re-hashing thousands
    # of source files on every dashboard poll starves live work and API threads.
    with store.db() as db:
        completed={}
        for value in (atlas,normal):
            row=db.execute("SELECT payload FROM events WHERE run_id=? AND kind='completed' ORDER BY id DESC LIMIT 1",
                           (value['id'],)).fetchone()
            completed[value['id']]=json.loads(row['payload']) if row else None
    unchanged=all(v is not None and v.get('source_changes')==0 for v in completed.values())
    report['checks']['source_unchanged']=unchanged
    with store.db() as db:
        evidence={}
        for value in (atlas,normal):
            rows=db.execute("SELECT payload FROM events WHERE run_id=? AND kind='tool_result'",(value['id'],))
            receipts=[json.loads(row['payload']) for row in rows]
            evidence[value['mode']]=sum(1 for r in receipts if r.get('name') in ('atlas_get','workspace_read','workspace_search')
                and (r.get('result',{}).get('code') or r.get('result',{}).get('matches')))
    report['source_evidence_events']=evidence
    report['checks']['source_retrieved']=all(evidence.values())
    if not unchanged or not all(evidence.values()):
        report.update(comparable=False,token_reduction_percent=None)
    with store.db() as db:
        reviews={r['run_id']:dict(r) for r in db.execute('SELECT * FROM reviews WHERE run_id IN (?,?)',(atlas['id'],normal['id']))}
    return {'atlas':atlas,'normal':normal,'reviews':reviews,**report}


class Review(BaseModel):
    correctness: int=Field(ge=0,le=5)
    grounding: int=Field(ge=0,le=5)
    validation: int=Field(ge=0,le=5)
    notes: str=Field(default='',max_length=4000)


@app.post('/api/runs/{identity}/review')
def review(identity: str,body: Review):
    selected(identity)
    with store.db() as db:
        db.execute('INSERT OR REPLACE INTO reviews VALUES(?,?,?,?,?)',
                   (identity,body.correctness,body.grounding,body.validation,body.notes))
    store.event(identity,'human_review',body.model_dump())
    return {'saved':True}


@app.post('/api/reindex')
def reindex():
    status=store.DATA/'workspace-index.json'
    store.DATA.mkdir(parents=True,exist_ok=True)
    status.write_text(json.dumps({'status':'queued'}))
    def refresh():
        try:
            with WORKSPACE_LOCK:
                result=workspace.index(workspace.WORKSPACE,workspace.HARNESS)
            status.write_text(json.dumps({'status':'ready','at':time.time(),**result}))
        except Exception as error:
            status.write_text(json.dumps({'status':'failed','error':str(error)}))
    POOL.submit(refresh)
    return {'queued':True}


@app.get('/api/runs/{identity}/diff')
def diff(identity: str,refresh: bool=False):
    value=selected(identity)
    changes=workspace.changes(value,refresh=refresh)
    result=[]
    if value['root']:
        root=Path(value['root'])
        base=root.parent.parent/'baseline'
        for change in changes[:100]:
            rel=change['path']
            old=(base/rel).read_text(encoding='utf-8',errors='replace').splitlines() if (base/rel).exists() else []
            new=(root/rel).read_text(encoding='utf-8',errors='replace').splitlines() if (root/rel).exists() else []
            result.extend(difflib.unified_diff(old,new,fromfile='a/'+rel,tofile='b/'+rel,lineterm=''))
    text='\n'.join(result)
    with store.db() as db:
        applied=db.execute("SELECT 1 FROM events WHERE run_id=? AND kind='applied' LIMIT 1",(identity,)).fetchone() is not None
    return {'changes':changes,'diff':text[:100000],'truncated':len(text)>100000,
            'fingerprint':hashlib.sha256(text.encode()).hexdigest(),'applied':applied}


class Apply(BaseModel):
    fingerprint: str


@app.post('/api/runs/{identity}/apply')
def apply(identity: str,body: Apply):
    value=selected(identity)
    if value['status']!='completed' or value['settings']['access']!='edit':
        raise HTTPException(409,'Only a completed edit run can be applied')
    report=diff(identity)
    if report['applied']:
        raise HTTPException(409,'This run has already been applied to the working copy')
    if report['fingerprint']!=body.fingerprint or report['truncated']:
        raise HTTPException(409,'Review the current complete diff before applying')
    root=Path(value['root'])
    baseline=json.loads((root.parent/'manifest.json').read_text())['files']
    with WORKSPACE_LOCK:
        for change in report['changes']:
            rel=change['path']
            target=workspace.safe_path(workspace.WORKSPACE,rel)
            if change['kind']=='deleted':
                raise HTTPException(409,'Deletion requires separate manual review')
            current=hashlib.sha256(target.read_bytes()).hexdigest() if target.exists() else None
            if current!=baseline.get(rel):
                raise HTTPException(409,'Working copy changed since snapshot: '+rel)
        backup=store.DATA/'applied'/identity
        for change in report['changes']:
            rel=change['path']
            target=workspace.safe_path(workspace.WORKSPACE,rel)
            if target.exists():
                saved=backup/rel
                saved.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(target,saved)
            target.parent.mkdir(parents=True,exist_ok=True)
            staged=target.with_name(target.name+'.atlas-pending-'+identity)
            shutil.copy2(workspace.safe_path(root,rel),staged)
            os.replace(staged,target)
    store.event(identity,'applied',{'files':report['changes'],'workspace':str(workspace.WORKSPACE),'backup':str(backup)})
    return {'applied':report['changes']}


@app.get('/api/runs/{identity}/export')
def export(identity: str):
    value=selected(identity)
    with store.db() as db:
        values=[{**dict(r),'payload':json.loads(r['payload'])} for r in db.execute(
            'SELECT * FROM events WHERE run_id=? ORDER BY id',(identity,))]
    return JSONResponse({'run':value,'events':values,'diff':diff(identity)},headers={
        'Content-Disposition':f'attachment; filename="atlas-run-{identity}.json"'})


def recover() -> None:
    with store.db() as db:
        db.execute("UPDATE runs SET status='interrupted',error='Controller restarted; run was not resumed',finished=? "
                   "WHERE status IN ('running','preparing','queued')",(time.time(),))
        db.execute("UPDATE approvals SET status='expired' WHERE status='pending'")
    status=store.DATA/'workspace-index.json'
    if status.exists():
        try:
            value=json.loads(status.read_text())
            if value.get('status')=='queued':
                status.write_text(json.dumps({'status':'interrupted','error':'Controller restarted; refresh the workspace index again'}))
        except (OSError,ValueError):
            status.write_text(json.dumps({'status':'interrupted','error':'Index status was incomplete; refresh again'}))


def shutdown() -> None:
    for value in store.runs():
        if value['status'] in {'queued','preparing','running'}:
            cancel(value['id'])
    POOL.shutdown(wait=False,cancel_futures=True)
