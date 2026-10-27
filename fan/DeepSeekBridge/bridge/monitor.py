"""Read-only live monitor for DeepSeek AHK Bridge. Run: python -m bridge.monitor."""
from __future__ import annotations
import json
import os
import sqlite3
from datetime import datetime, timezone
from html import escape
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit
from .gateway import DB
from .common import TOKEN
from pathlib import Path
import hmac
import httpx
from .common import ROOT, BASE_URL
from . import workbench

HOST = '127.0.0.1'
PORT = int(os.getenv('MONITOR_PORT', '8766'))
PAGE = '''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>DeepSeek Agent Observatory</title><style>
:root{color-scheme:dark;font-family:Segoe UI,system-ui,sans-serif;background:#0b101a;color:#e5edf7}*{box-sizing:border-box}body{margin:0}header{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;padding:14px 20px;background:#101929;border-bottom:1px solid #29405d}h1{font-size:20px;margin:0}h2{font-size:15px;margin:0 0 10px;color:#aad5ff}.tag{padding:5px 9px;border:1px solid #35506a;border-radius:20px;font-size:12px}.layout{display:grid;grid-template-columns:340px 1fr;gap:14px;padding:14px;height:calc(100vh - 65px)}section{background:#111b2b;border:1px solid #293e5b;border-radius:12px;overflow:auto;padding:14px}.main{display:grid;grid-template-rows: minmax(0,1fr) minmax(150px,35%);gap:14px;min-height:0}.entry{padding:11px;margin-bottom:10px;border-radius:8px;background:#18243a;border-left:3px solid #6388bf}.entry.reasoning{border-color:#d8ad5e}.entry.tool_requested,.entry.agent_tool_call{border-color:#bd7af0}.entry.tool_result,.entry.agent_tool_result{border-color:#64c69d}.entry.agent_answer,.entry.agent_text{border-color:#63a9ed}.entry.agent_error,.entry.task_finished{border-color:#ed7777}.meta{font-size:12px;color:#a5bad1;margin-bottom:7px;display:flex;gap:12px;flex-wrap:wrap}.body{white-space:pre-wrap;overflow-wrap:anywhere;font-family:Consolas,monospace;font-size:12px;line-height:1.5}.task{padding:10px;border:1px solid #34506f;border-radius:8px;margin-bottom:8px;cursor:pointer}.task:hover{background:#1b2d48}.status{font-size:12px;color:#a7c3db}.queued{color:#ffd37a}.running{color:#7bd7ff}.complete{color:#89efb5}.error{color:#ff8484}#filters{display:flex;gap:5px;flex-wrap:wrap;margin-bottom:10px}button{background:#223956;border:1px solid #47658c;border-radius:6px;color:white;padding:7px;cursor:pointer}button.selected{background:#2360a3}.small{font-size:12px;color:#94aec9}#indicator{color:#82e9b0}@media(max-width:800px){.layout{display:block;height:auto}.layout>section{height:260px;margin-bottom:14px}.main{height:90vh}}
</style></head><body><header><h1>DeepSeek Agent Observatory</h1><div><span class="tag" id="indicator">connecting</span> <span class="tag" id="stats">0 events</span> <button id="pause">Pause</button></div></header><div class="layout"><section><h2>Task queue / chat sessions</h2><p class="small">Select a task to filter its events. All tasks shows the complete log.</p><div id="tasks"></div></section><div class="main"><section><h2>Live reasoning, chat &amp; tool execution</h2><div id="filters"><button data-type="all" class="selected">All</button><button data-type="reasoning">Reasoning</button><button data-type="agent_text">Chat</button><button data-type="agent_tool_call">Commands</button><button data-type="agent_tool_result">Results</button></div><div id="events"></div></section><section><h2>Event / command history (most recent first)</h2><div id="history"></div></section></div></div><script>
let chosen='',kind='all',paused=false,latest=0;const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const pretty=p=>{try{return JSON.stringify(JSON.parse(p),null,2)}catch{return String(p??'')}};
function drawEntry(e){const p=e.payload||{};let display=p.text??p.content??p.response??p.prompt??p.result??p; if(typeof display!=='string')display=JSON.stringify(display,null,2);return `<div class="entry ${esc(e.kind)}"><div class="meta"><strong>${esc(e.kind)}</strong><span>${esc(e.at)}</span><span>${esc(e.subject)}</span></div><div class="body">${esc(display)}</div></div>`}
async function refresh(){if(paused)return;try{const r=await fetch('/api/state',{cache:'no-store'});if(!r.ok)throw Error(r.status);const data=await r.json();document.getElementById('indicator').textContent='● Live · refresh 0.6s';document.getElementById('stats').textContent=`${data.events.length} recent events`;const counts={};for(const t of data.tasks){counts[t.status]=(counts[t.status]||0)+1}document.getElementById('tasks').innerHTML=`<div class="task" data-task=""><b>All tasks</b> <span class="status">${Object.entries(counts).map(([k,v])=>`${esc(k)}:${v}`).join(' · ')}</span></div>`+data.tasks.map(t=>`<div class="task" data-task="${esc(t.id)}"><div><b class="${esc(t.status)}">${esc(t.status)}</b> <span class="small">${esc(t.created_at)}</span></div><div class="small">${esc(t.prompt)}</div><div class="small">${esc(t.id.slice(0,12))}</div></div>`).join('');
const filter=e=>(!chosen||e.task_id===chosen||e.subject===chosen)&& (kind==='all'||e.kind===kind || (kind==='agent_text'&&e.kind==='agent_answer')||(kind==='agent_tool_call'&&e.kind==='tool_requested')||(kind==='agent_tool_result'&&e.kind==='tool_result'));
const selected=data.events.filter(filter);document.getElementById('events').innerHTML=selected.length?selected.slice().reverse().map(drawEntry).join(''):'<p class="small">No matching events yet. New API agent calls appear here as they stream.</p>';document.getElementById('history').innerHTML=data.events.filter(e=>!chosen||e.task_id===chosen||e.subject===chosen).slice().reverse().slice(0,60).map(e=>`<div class="meta"><span>${esc(e.at)}</span><strong>${esc(e.kind)}</strong><span>${esc(e.subject)}</span></div>`).join('');
}catch(err){document.getElementById('indicator').textContent='Disconnected: '+err.message}}
document.getElementById('tasks').addEventListener('click',e=>{const t=e.target.closest('[data-task]');if(t){chosen=t.dataset.task;refresh()}});document.getElementById('filters').addEventListener('click',e=>{const b=e.target.closest('button');if(!b)return;kind=b.dataset.type;document.querySelectorAll('#filters button').forEach(x=>x.classList.toggle('selected',x===b));refresh()});document.getElementById('pause').onclick=()=>{paused=!paused;document.getElementById('pause').textContent=paused?'Resume':'Pause';if(!paused)refresh()};setInterval(refresh,600);refresh();
</script></body></html>'''


def snapshot():
    if not DB.exists():
        return {'tasks': [], 'events': []}
    with sqlite3.connect(DB, timeout=5) as db:
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA busy_timeout=5000')
        tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        tasks = [dict(r) for r in db.execute('SELECT id,prompt,status,response,created_at FROM tasks ORDER BY created_at DESC LIMIT 150')] if 'tasks' in tables else []
        events = [dict(r) for r in db.execute('SELECT id,at,kind,subject,payload FROM events ORDER BY id DESC LIMIT 800')] if 'events' in tables else []
    for e in events:
        try:
            p = json.loads(e['payload'])
            e['payload'] = p
            e['task_id'] = p.get('task_id', '') if isinstance(p, dict) else ''
        except ValueError:
            e['task_id'] = ''
    return {'tasks': tasks, 'events': events}


class Handler(BaseHTTPRequestHandler):
    def reply(self, payload, mime='application/json; charset=utf-8', status=200):
        if not isinstance(payload, bytes):
            payload = json.dumps(payload, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('Content-Security-Policy', "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' blob: data:; connect-src 'self'; frame-ancestors 'none'")
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def permitted(self):
        if self.headers.get('Origin') not in (None, f'http://{HOST}:{PORT}'):
            return False
        supplied = self.headers.get('X-Bridge-Token', '')
        return bool(TOKEN and hmac.compare_digest(supplied, TOKEN))

    def do_GET(self):
        parsed = urlsplit(self.path)
        path, query = parsed.path, parse_qs(parsed.query)
        static = {'/': ('index.html', 'text/html; charset=utf-8'), '/workbench.js': ('workbench.js', 'text/javascript; charset=utf-8'), '/workbench.css': ('workbench.css', 'text/css; charset=utf-8')}
        if path in static:
            name, mime = static[path]
            return self.reply((ROOT / 'workbench' / name).read_bytes(), mime)
        if not self.permitted():
            return self.reply({'error': 'Open Live Workbench from Macro Automator to connect this local view.'}, status=401)
        try:
            arg = lambda name, default='': query.get(name, [default])[0]
            if path == '/api/runs':
                payload = workbench.runs(DB, offset=int(arg('offset', '0')))
                if arg('compact') == '1':
                    payload['runs'] = [{k: (v[:240] if k == 'prompt' else v) for k, v in r.items() if k != 'response'} for r in payload['runs']]
            elif path == '/api/events':
                reader = workbench.native_events if arg('compact') == '1' else workbench.events
                payload = reader(DB, arg('task'), int(arg('after', '0')), max(1, min(300, int(arg('limit', '300')))))
            elif path == '/api/registry':
                payload = workbench.registry()
            elif path == '/api/report':
                return self.reply(workbench.report(DB, arg('task')).encode('utf-8'), 'text/plain; charset=utf-8')
            elif path == '/api/knowledge-stats':
                from . import window_knowledge, project_paths, pricing
                payload = window_knowledge.stats(query=arg('query'))
                payload['projects'] = project_paths.stats()
                payload['spending'] = pricing.summary(DB)
                payload['run_spending'] = pricing.summary(DB, arg('task')) if arg('task') else {}
            elif path == '/api/spending':
                from . import pricing
                payload = pricing.summary(DB, arg('task'))
            elif path == '/api/chain':
                from . import chains, tour
                payload = chains.snapshot(DB,arg('task'),int(arg('after','0')),int(arg('limit','500')))
                payload['control'] = chains.control(DB,arg('task'))
                from .interjections import latest
                payload['interjection'] = latest(DB,arg('task'))
                payload['cue'] = tour.latest(DB,arg('task'))
                from .pricing import summary
                payload['spending'] = summary(DB,arg('task'))
                with sqlite3.connect(DB,timeout=10) as db:
                    for kind,key in [('unit_step','current_subtask'),('daa_action','current_action')]:
                        event = db.execute('SELECT payload FROM events WHERE kind=? AND subject=? ORDER BY id DESC LIMIT 1',(kind,arg('task'))).fetchone()
                        payload[key] = json.loads(event[0]) if event else {}
                    payload['provider_requests'] = db.execute("SELECT COUNT(*) FROM events WHERE kind IN ('agent_request','vision_request') AND (subject=? OR json_extract(payload,'$.task_id')=?)",(arg('task'),arg('task'))).fetchone()[0]
                    payload['estimated_saved'] = db.execute('SELECT COALESCE(SUM(estimated_saved),0) FROM window_reuse WHERE task_id=?',(arg('task'),)).fetchone()[0] if db.execute("SELECT 1 FROM sqlite_master WHERE name='window_reuse'").fetchone() else 0
                    row = db.execute("SELECT id,payload FROM events WHERE kind='tool_result' AND json_extract(payload,'$.task_id')=? AND (json_extract(payload,'$.result.photo_ref') IS NOT NULL OR json_extract(payload,'$.result.image_path') IS NOT NULL) ORDER BY id DESC LIMIT 1",(arg('task'),)).fetchone()
                    if row:
                        result = json.loads(row[1]).get('result',{})
                        payload['latest_image'] = {'event':row[0],'frame':result.get('frame',{})}
            elif path == '/api/explorer-usage':
                from .explorer_usage import ranked
                payload = ranked(query=arg('query'),limit=60)
            elif path == '/api/window-knowledge':
                from . import window_knowledge
                payload = window_knowledge.lookup(window_id=arg('id'), query=arg('query'), offset=int(arg('offset', '0')), limit=40)
            elif path == '/api/project-paths':
                from . import project_paths
                payload = project_paths.search(query=arg('query'), limit=30)
            elif path == '/api/tooling':
                payload = workbench.native_tooling(arg('kind', 'tools'), arg('query'), int(arg('offset', '0')))
            elif path == '/api/tool':
                payload = workbench.direct_tool(arg('name'))
            elif path == '/api/discoveries':
                payload = {'discoveries': workbench.discoveries(query=arg('query')), 'claims': workbench.claims(DB, query=arg('query'))}
                if arg('compact') == '1':
                    payload['claims'] = payload['claims'][:30]
                    originals = {r['name']: r for r in payload['discoveries']}
                    payload['discoveries'] = [{k: v for k, v in r.items() if k in ('name', 'kind', 'description', 'revision', 'updated_at')} for r in payload['discoveries'][:30]]
                    for item in payload['discoveries']:
                        original = originals[item['name']]
                        item['metadata'] = {'source_kind': original.get('metadata', {}).get('source_kind', 'reference')}
            elif path == '/api/claim':
                payload = workbench.claims(DB, int(arg('id', '0')))
            elif path == '/api/artifact':
                payload = workbench.artifact(arg('name'))
            elif path == '/api/method':
                payload = workbench.method_source(arg('path'), int(arg('line', '0')))
            elif path == '/api/image':
                data, mime = workbench.image(DB, int(arg('event')), arg('variant', 'image'))
                return self.reply(data, mime)
            elif path == '/api/health':
                payload = httpx.get(BASE_URL + '/health', headers={'X-Bridge-Token': TOKEN}, timeout=5).json()
            elif path == '/api/state':
                payload = snapshot()
            else:
                return self.reply({'error': 'Not found'}, status=404)
            return self.reply(payload)
        except (ValueError, KeyError, OSError, sqlite3.Error, httpx.HTTPError) as exc:
            return self.reply({'error': str(exc)[:400]}, status=400)

    def do_POST(self):
        if not self.permitted():
            return self.reply({'error': 'Local workbench authorization required'}, status=401)
        path = urlsplit(self.path).path
        length = int(self.headers.get('Content-Length', '0'))
        if length < 1 or length > 11300000:
            return self.reply({'error': 'Request size is invalid'}, status=413)
        try:
            body = json.loads(self.rfile.read(length))
            if path == '/api/trace':
                from . import chains
                graph=chains.snapshot(DB,body['task'],limit=500)
                step=body.get('step') or (graph['steps'][-1]['id'] if graph['steps'] else '')
                from .gateway import db_write
                db_write('operator_trace',body['task'],{'task_id':body['task'],'step_id':step,'note':body.get('note','Operator trace checkpoint'),'chain_count':graph['chain'].get('step_count',0)})
                return self.reply({'ok':True,'step_id':step})
            if path in ('/api/interject','/api/continue-interjection'):
                import re
                identity=body.pop('task','')
                if not re.fullmatch(r'[a-f0-9]{32}',identity):raise ValueError('Select a recorded task')
                suffix='interject' if path=='/api/interject' else 'continue-interjection'
                response=httpx.post(BASE_URL+'/tasks/'+identity+'/'+suffix,json=body,headers={'X-Bridge-Token':TOKEN},timeout=20,trust_env=False)
                return self.reply(response.json(),status=response.status_code)
            if path == '/api/pause':
                from .chains import control
                if not isinstance(body.get('paused'), bool):
                    raise ValueError('paused must be true or false')
                return self.reply(control(DB,body['task'],body['paused']))
            if path == '/api/chain-budget':
                from .chains import configure
                return self.reply(configure(DB,body['task'],int(body['max_steps'])))
            if path == '/api/tour-next':
                from .tour import release
                return self.reply(release(DB,body['task']))
            target = {'/api/tasks': '/tasks', '/api/images': '/images'}.get(path)
            if path == '/api/cancel':
                import re
                identity = body.get('task', '')
                if not re.fullmatch(r'[a-f0-9]{32}', identity):
                    raise ValueError('Select a recorded task')
                target = '/tasks/' + identity + '/cancel'
                body = {}
            if not target:
                return self.reply({'error': 'Not found'}, status=404)
            response = httpx.post(BASE_URL + target, json=body, headers={'X-Bridge-Token': TOKEN}, timeout=20)
            payload = response.json()
            if path == '/api/cancel' and response.is_success:
                (ROOT / '.runtime' / 'cancel-agent').write_text(identity, encoding='utf-8')
            return self.reply(payload, status=response.status_code)
        except (ValueError, OSError, httpx.HTTPError) as exc:
            return self.reply({'error': str(exc)[:400]}, status=400)

    def log_message(self, fmt, *args):
        pass


def main():
    print(f'Observatory: http://{HOST}:{PORT}', flush=True)
    print(f'Reading database: {DB}', flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == '__main__':
    main()
