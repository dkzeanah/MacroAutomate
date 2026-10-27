"""Scoped local relay to one user-selected normal Chrome window.

Explicitly approved by the user. A separate connector key grants only polling
and command-result access, never bridge tools, tasks, files or configuration.
"""
from __future__ import annotations
import base64
import hashlib
import json
import queue
import re
import secrets
import threading
import time
import uuid
from dataclasses import dataclass,field
from pathlib import Path
from urllib.parse import urlsplit
from fastapi import APIRouter,Header,HTTPException,Request
from pydantic import BaseModel,ConfigDict,Field
from . import library
from .common import PORT

router=APIRouter(prefix='/chrome')
pending=queue.Queue()
calls={}
guard=threading.RLock()
KINDS={'new_tab','navigate','observe','screenshot','click','fill','upload','highlight','close_tab','tab_status'}

@dataclass
class Call:
    command:dict
    generation:str
    id:str=field(default_factory=lambda:uuid.uuid4().hex)
    event:threading.Event=field(default_factory=threading.Event)
    result:dict|None=None

def initialize(db):
    db.execute('CREATE TABLE IF NOT EXISTS chrome_connection (id INTEGER PRIMARY KEY CHECK(id=1),content TEXT NOT NULL)')

def state():
    with library.connect() as db:
        initialize(db)
        row=db.execute('SELECT content FROM chrome_connection WHERE id=1').fetchone()
    return json.loads(row[0]) if row else {}

def save(value):
    with library.connect() as db:
        initialize(db)
        db.execute('INSERT OR REPLACE INTO chrome_connection VALUES(1,?)',(json.dumps(value),))

def pairing():
    value={'pair_code':secrets.token_hex(16),'pair_expires':time.time()+600,'connected':False,'last_seen':0}
    save(value)
    with guard:
        for call in calls.values():
            call.result={'ok':False,'error':'Chrome pairing changed'}
            call.event.set()
    return {'ok':True,'pair_code':str(PORT)+'.'+value['pair_code'],'expires_in_seconds':600,
            'extension_folder':str(Path(__file__).resolve().parents[1]/'chrome-extension')}

def status():
    value=state()
    return {'connected':bool(value.get('connected') and time.time()-value.get('last_seen',0)<15),
        'window_id':value.get('window_id'),'tab_id':value.get('tab_id'),
        'incognito':False,'mode':'existing_chrome','requires_pairing':not value.get('connected')}

def active_calls():
    with guard:
        return ['chrome.'+call.command['kind'] for call in calls.values() if not call.event.is_set()]

def authorize(token):
    value=state()
    if not token or not value.get('token') or not secrets.compare_digest(token,value['token']):
        raise HTTPException(401,'Invalid Chrome connector credential')
    return value

class Pair(BaseModel):
    model_config=ConfigDict(extra='forbid')
    code:str=Field(max_length=100)
    window_id:int=Field(ge=0)
    tab_id:int=Field(ge=0)
    incognito:bool
    url:str=Field(max_length=4000)

@router.post('/pair')
def pair(args:Pair):
    from .job_sharing import job_route
    from .job_applications import configuration
    value=state()
    p=urlsplit(args.url)
    sites=configuration()['sites']+['linkedin.com']
    if args.incognito:
        raise HTTPException(422,'Choose an existing normal Chrome window')
    if (p.scheme!='https' or p.username or p.password or p.port not in (None,443)
        or not any(p.hostname==s or (p.hostname or '').endswith('.'+s) for s in sites)
        or not job_route(p.hostname or '',p.path)):
        raise HTTPException(422,'Open the LinkedIn feed or a configured public job page before connecting')
    if time.time()>value.get('pair_expires',0) or not args.code or not secrets.compare_digest(args.code,value.get('pair_code','')):
        raise HTTPException(401,'Pairing code expired or incorrect; generate a new local code')
    value.update(token=secrets.token_urlsafe(32),generation=uuid.uuid4().hex,window_id=args.window_id,
                 tab_id=args.tab_id,connected=False,last_seen=0,pair_code='',pair_expires=0)
    save(value)
    return {'ok':True,'token':value['token'],'window_id':args.window_id,'tab_id':args.tab_id,'sites':sites}

@router.get('/next')
def next_command(x_chrome_token:str|None=Header(default=None)):
    value=authorize(x_chrome_token)
    value['last_seen']=time.time()
    value['connected']=True
    save(value)
    while True:
        try:call=pending.get_nowait()
        except queue.Empty:return {'command':None}
        with guard:
            if call.id in calls and not call.event.is_set() and call.generation==value['generation']:
                return {'id':call.id,'command':call.command,'window_id':value['window_id']}

@router.post('/result')
async def result(request:Request,x_chrome_token:str|None=Header(default=None)):
    value=authorize(x_chrome_token)
    if int(request.headers.get('content-length','0'))>45*1024*1024:
        raise HTTPException(413,'Capture result too large')
    payload=await request.json()
    with guard:
        call=calls.get(payload.get('id'))
        if not call or call.generation!=value['generation']:
            raise HTTPException(404,'Command expired; do not replay it')
        answer=payload.get('result')
        if not isinstance(answer,dict):
            raise HTTPException(422,'Result must be an object')
        call.result=answer
        call.event.set()
    return {'ok':True}

@router.post('/disconnect')
def disconnect(x_chrome_token:str|None=Header(default=None)):
    value=authorize(x_chrome_token)
    value.update(connected=False,last_seen=0,token='')
    save(value)
    with guard:
        for call in calls.values():
            call.result={'ok':False,'error':'Chrome connector disconnected'}
            call.event.set()
    return {'ok':True}

def validate(command):
    from .job_browser import allowed
    from .job_applications import configuration,searches
    kind=command.get('kind')
    if kind not in KINDS:
        raise ValueError('Unsupported connector command')
    keys={'kind','tab_id','url','field','answer','full_page'}
    if set(command)-keys:
        raise ValueError('Arbitrary JavaScript, selectors, file paths and extra command fields are prohibited')
    if kind!='new_tab' and (not isinstance(command.get('tab_id'),int) or command['tab_id']<0):
        raise ValueError('An observed Chrome tab ID is required')
    config=configuration()
    value=dict(command)
    if kind in ('navigate','new_tab'):
        url=command.get('url','about:blank')
        search=url in {e['url'] for e in searches()['searches']}
        learning_config={**config,'sites':config['sites']+['linkedin.com']}
        if url!='about:blank' and not allowed(url,learning_config) and not search:
            raise ValueError('Navigation is outside configured job/search entry URLs')
        value['search_entry']=search
    if kind in ('fill','click','upload','highlight'):
        expected=command.get('field',{})
        if not isinstance(expected,dict) or not re.fullmatch(r'dom-\d+',expected.get('element_id','')) or expected.get('protected'):
            raise ValueError('Input requires an observed unprotected element ID')
        value['field']={k:expected.get(k) for k in ('element_id','name','role','type','tag','protected','enabled')}
        if kind=='fill' and not isinstance(command.get('answer'),(str,bool,int)):
            raise ValueError('Only a saved scalar answer may be filled')
        if kind=='fill':
            from .job_browser import answer_for
            saved=answer_for(expected,config)
            if saved is None or command['answer']!=saved:
                raise ValueError('Answer must exactly match the saved applicant answer for this question')
        if kind=='click' and not re.fullmatch(r'apply(?: now| for this job)?|submit(?: application)?|send application|next|continue|review application',expected.get('name','').strip(),re.I):
            raise ValueError('Only observed job-application navigation/submission controls may be clicked')
        if kind=='upload':
            if not re.search(r'resume|résumé|\bcv\b',expected.get('name',''),re.I):
                raise ValueError('Only the selected resume upload is supported')
            path=Path(config['resume_path']).resolve()
            if not path.is_file() or path.suffix.lower()!='.pdf' or path.stat().st_size>20*1024*1024:
                raise ValueError('Selected resume must be an existing PDF under 20 MiB')
            data=path.read_bytes()
            if not data.startswith(b'%PDF-'):
                raise ValueError('Selected resume is not a PDF')
            value.update(filename=path.name,pdf_base64=base64.b64encode(data).decode(),sha256=hashlib.sha256(data).hexdigest())
    return value

def invoke(command,timeout=60):
    validated=validate(command)
    current=state()
    if not status()['connected']:
        raise ValueError('Connect the existing normal Chrome window using the Fan extension first')
    call=Call(validated,current['generation'])
    with guard:calls[call.id]=call
    pending.put(call)
    try:
        if not call.event.wait(timeout):
            raise TimeoutError('Chrome did not confirm this command; do not retry input automatically')
        answer=call.result or {}
        if not answer.get('ok'):
            raise ValueError(answer.get('error','Chrome command failed'))
        return answer
    finally:
        with guard:calls.pop(call.id,None)

@router.post('/command')
def command(args:dict,x_bridge_token:str|None=Header(default=None),x_bridge_task:str|None=Header(default=None)):
    from .gateway import authorize as full_authorize
    full_authorize(x_bridge_token)
    if x_bridge_task:
        raise HTTPException(403,'Chrome commands are local runner operations, not model tools')
    try:return invoke(args)
    except ValueError as exc:raise HTTPException(422,str(exc))
    except TimeoutError as exc:raise HTTPException(504,str(exc))

@router.get('/status')
def get_status(x_bridge_token:str|None=Header(default=None)):
    from .gateway import authorize as full_authorize
    full_authorize(x_bridge_token)
    return status()
