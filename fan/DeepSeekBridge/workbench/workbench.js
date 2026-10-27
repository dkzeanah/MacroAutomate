'use strict';
const $ = id => document.getElementById(id);
const token = new URLSearchParams(location.hash.slice(1)).get('access') || '';
const initialView = new URLSearchParams(location.hash.slice(1)).get('view') || 'canvas';
const initialRun = new URLSearchParams(location.hash.slice(1)).get('run') || '';
history.replaceState(null, '', location.pathname);
let selected = '', cursor = 0, task = null, running = false, registry = {tools: [], methods: [], artifacts: []};
let runList = [], olderOffset = 0, toolLimit = 100, lastRegistry = 0, registryKey = '', lastDiscoveries = 0;
let currentView = initialView, thinkingRound = 0, messageRound = 0, counts = {}, pendingImages = [];
let activeTools = new Set(), activeArtifacts = new Set(), activeMethods = new Map(), recent = new Map(), imageUrls = new Map();
const content = $('content');
function el(tag, cls, text) { const node = document.createElement(tag); if (cls) node.className = cls; if (text !== undefined) node.textContent = text; return node; }
function banner(text) { $('banner').textContent = text || ''; $('banner').classList.toggle('visible', !!text); }
async function api(path, body) {
  const response = await fetch(path, {method: body === undefined ? 'GET' : 'POST', headers: {'X-Bridge-Token': token, ...(body === undefined ? {} : {'Content-Type': 'application/json'})}, ...(body === undefined ? {} : {body: JSON.stringify(body)})});
  const data = await response.json();
  if (!response.ok) throw new Error(typeof data.detail === 'string' ? data.detail : data.error || JSON.stringify(data.detail) || 'Request failed');
  return data;
}
function follow() { if ($('follow').checked) content.scrollTop = content.scrollHeight; }
function bounds(value) { if (!value) return ''; return ['x','y','w','h'].filter(k => k in value).map(k => `${k} ${value[k]}`).join(' · '); }
function details(parent, title, data) { const d = el('details'); d.append(el('summary', '', title), el('pre', '', typeof data === 'string' ? data : JSON.stringify(data, null, 2))); parent.append(d); }
function table(parent, headers, rows) { const wrap = el('div', 'table-scroll'), t = el('table'), head = el('tr'); headers.forEach(h => head.append(el('th', '', h))); const thead = el('thead'); thead.append(head); t.append(thead); const body = el('tbody'); rows.forEach(row => { const tr = el('tr'); row.forEach(cell => tr.append(el('td', '', cell))); body.append(tr); }); t.append(body); wrap.append(t); parent.append(wrap); }
function showDetail(title, node) { $('detail-title').textContent = title; $('detail-body').replaceChildren(node); if (!$('detail').open) $('detail').showModal(); }
$('close-detail').onclick = () => $('detail').close();
function switchView(view) {
  currentView = ['canvas','thinking','conversation','discoveries'].includes(view) ? view : 'canvas';
  for (const name of ['canvas','thinking','conversation','discoveries']) $(name).hidden = name !== currentView;
  document.querySelectorAll('#views [data-view]').forEach(b => b.classList.toggle('selected', b.dataset.view === currentView));
  follow();
}
$('views').onclick = event => { const b = event.target.closest('[data-view]'); if (b) switchView(b.dataset.view); };
$('follow').onchange = follow;
$('full-task').onclick=()=>showDetail('Task instructions',el('pre','',task?.prompt||'Choose a run'));
function renderRuns() {
  const query = $('run-search').value.toLowerCase(); $('runs').replaceChildren();
  for (const item of runList.filter(r => (r.prompt + ' ' + r.id).toLowerCase().includes(query))) {
    const b = el('button', 'run' + (item.id === selected ? ' selected' : ''));
    b.append(el('span', 'state-' + item.status, item.status), el('span', 'run-title', item.prompt), el('small', '', new Date(item.created_at).toLocaleString()));
    b.onclick = () => selectRun(item.id,true); $('runs').append(b);
  }
  $('run-count').textContent = runList.length;
}
async function refreshRuns(older = false) {
  const previousLatest=runList[0]?.id;
  const data = await api('/api/runs?offset=' + (older ? olderOffset : 0));
  const indexed = new Map((older ? runList : [...data.runs, ...runList]).map(r => [r.id,r]));
  data.runs.forEach(r => indexed.set(r.id, r)); runList = [...indexed.values()].sort((a,b) => b.created_at.localeCompare(a.created_at));
  olderOffset = older ? olderOffset + data.runs.length : Math.max(olderOffset, data.runs.length);
  $('older').hidden = !data.has_more && (!older || data.runs.length === 0); renderRuns();
  if (!selected && runList.length) selectRun(runList.some(r=>r.id===initialRun)?initialRun:runList[0].id);
  else if(!older&&$('follow-runs').checked&&previousLatest&&runList[0]?.id!==previousLatest)selectRun(runList[0].id);
}
$('run-search').oninput = renderRuns;
$('older').onclick = () => refreshRuns(true).catch(e => banner(e.message));
function selectRun(identity,manual=false) {
  if(manual)$('follow-runs').checked=false;
  selected = identity; cursor = 0; counts = {}; thinkingRound = 0; messageRound = 0; activeMethods.clear();
  for (const url of imageUrls.values()) URL.revokeObjectURL(url); imageUrls.clear();
  for (const name of ['canvas','thinking','conversation']) $(name).replaceChildren();
  task = runList.find(r => r.id === identity) || null;
  if (task) updateTask(task); renderRuns();
}
$('follow-runs').onchange=()=>{if($('follow-runs').checked&&runList.length)selectRun(runList[0].id);};
function updateTask(value) {
  task = value; $('task-title').textContent = value.prompt; $('task-id').textContent = value.id.slice(0,12);
  $('task-state').textContent = value.status; $('task-state').className = 'pill state-' + value.status;
  $('stop').disabled = !['queued','running'].includes(value.status);
}
async function loadImage(card, image) {
  const key = `${card.event_id}:${card.image}`;
  try {
    if (!imageUrls.has(key)) {
      const r = await fetch(`/api/image?event=${card.event_id}&variant=${encodeURIComponent(card.image)}`, {headers: {'X-Bridge-Token': token}});
      if (!r.ok) throw new Error('Image was not retained'); imageUrls.set(key, URL.createObjectURL(await r.blob()));
    }
    image.src = imageUrls.get(key); image.alt = card.title;
    image.onclick = () => { const full = el('img'); full.src = image.src; full.alt = image.alt; showDetail(card.title, full); };
  } catch (error) { image.replaceWith(el('p', 'hint', error.message)); }
}
const imageObserver = new IntersectionObserver(entries => { entries.forEach(entry => { if (entry.isIntersecting) { const image = entry.target; imageObserver.unobserve(image); loadImage(image._card, image); } }); }, {root: content, rootMargin: '500px'});
function cardNode(card) {
  const node = el('article', 'card ' + card.kind), head = el('div', 'card-head');
  head.append(el('span','badge', card.kind), el('strong','',card.title), el('time','',new Date(card.at).toLocaleTimeString())); node.append(head);
  node.append(el('div','provenance', `${card.source_kind || 'observed'} · ${card.tool || ''}${card.window ? ' · ' + card.window : ''} · evidence #${card.event_id}`));
  const data = card.data || {};
  if (card.image) { const image = el('img'); image._card = card; node.append(image); imageObserver.observe(image); }
  if (card.kind === 'controls') {
    if(!data.controls?.length)node.append(el('p','hint','No accessible controls were exposed by this observation. See the image/OCR and retained warnings.'));
    table(node, ['Role / name','Value / state','Observed bounds'], (data.controls || []).map(c => [c.role + '\n' + (c.name || '(unnamed)'), (c.protected ? '[protected]' : c.value || '') + (c.enabled === false || c.enabled === 0 ? '\nDisabled' : ''), bounds(c.bounds)]));
    if (data.coverage?.truncated) node.append(el('p','hint','Control traversal reached its limit. More controls may exist.'));
  } else if (card.kind === 'ocr') {
    node.append(el('pre','',data.text || '(No text recognized)'));
    if (data.lines?.length) details(node, data.lines.length + ' lines with locations', data.lines);
    if (data.words?.length) details(node, data.words.length + ' words with locations', data.words);
  } else if (card.kind === 'findtext') {
    if (data.total_matches !== undefined) node.append(el('p','', data.total_matches + ' visual matches. A visual match does not establish meaning.'));
    if (data.matches?.length) table(node,['Pattern','Observed bounds','Center'],data.matches.map(m => [m.pattern || m.id || '', bounds(m.bounds), JSON.stringify(m.center)]));
    const decoded = data.translation;
    if(!decoded?.bits)node.append(el('p','hint','This result did not retain a decodable pattern. Saved pattern source is available under Usable tooling → Saved workflows / patterns.'));
    if (decoded?.bits) {
      node.append(el('p','hint',`${decoded.width} × ${decoded.height} pixels · ${decoded.bits.length} binary pixels`));
      const canvas = el('canvas','binary'); canvas.width = decoded.width; canvas.height = decoded.height;
      const ctx = canvas.getContext('2d'), pixels = ctx.createImageData(canvas.width,canvas.height);
      for (let i=0;i<decoded.bits.length && i<canvas.width*canvas.height;i++) { const color=decoded.bits[i]==='1'?0:255; pixels.data.set([color,color,color,255],i*4); }
      ctx.putImageData(pixels,0,0); node.append(canvas); details(node,'Binary / FindText encoding', {text:data.text,bits:decoded.bits,ascii:decoded.ascii});
    }
  } else if (card.kind === 'interpretation') node.append(el('p','', data.text || JSON.stringify(data)));
  else if (card.kind === 'action' || card.kind === 'failure') node.append(el('p','',typeof data === 'string' ? data : JSON.stringify(data,null,2)));
  else if (card.kind === 'discovery') node.append(el('p','',JSON.stringify(data,null,2)));
  if (card.frame) details(node,'Window, geometry and capture context',card.frame);
  details(node,'Full retained details',data); return node;
}
function addCard(card) {
  if ($('canvas').querySelector(`[data-card="${CSS.escape(card.id)}"]`)) return;
  const node = cardNode(card); node.dataset.card=card.id; $('canvas').append(node); counts[card.kind]=(counts[card.kind]||0)+1;
}
function processEvent(event) {
  const p=event.payload||{}, kind=event.kind, tool=p.name||event.subject, live=Date.now()-Date.parse(event.at)<8000;
  if (kind==='reasoning') {
    if (thinkingRound!==p.round) { $('thinking').append(document.createTextNode(`\n\nRound ${p.round} · model-provided thinking\n\n`)); thinkingRound=p.round; }
    $('thinking').append(document.createTextNode(p.text||''));
  }
  if (kind==='agent_text') {
    const key='message-'+p.round; let message=document.getElementById(key);
    if (!message) { message=el('article','message'); message.id=key; message.append(el('strong','','Agent · round '+p.round),el('span')); $('conversation').append(message); }
    message.lastChild.append(document.createTextNode(p.text||''));
  }
  if (kind==='agent_answer') { const answer=el('article','message'); answer.append(el('strong','','Completed answer'),el('span','',p.text||'')); $('conversation').append(answer); }
  if (kind==='agent_tool_call') {
    if(live)recent.set(tool,Date.now()); counts.calls=(counts.calls||0)+1;
    let args; try { args=JSON.parse(p.arguments); } catch { args={arguments:p.arguments}; }
    if(live&&args?.name){recent.set(args.name,Date.now());recent.set('workflow:'+args.name,Date.now());recent.set('pattern:'+args.name,Date.now());}
    if (args?.source) args={...args, source:`${args.source.length} characters of saved source; inspect the .ahk entry in Usable tooling.`};
    addCard({id:event.id+':call',event_id:event.id,at:event.at,kind:'action',title:'Calling '+tool,tool,source_kind:'requested operation',data:args});
  }
  if (kind==='tool_requested'&&live) recent.set(tool,Date.now());
  if (kind==='native_method'&&live) {
    activeMethods.set(p.method,{...p,at:Date.now()}); recent.set(p.family,Date.now());
    $('live-method').textContent=p.family+' · '+p.method+' · '+p.phase;
  }
  if (kind==='tool_result' || kind==='agent_tool_result' || kind==='tool_timeout') {
    for (const [method,info] of activeMethods) if (info.tool===tool) activeMethods.delete(method);
  }
  if (kind==='agent_tool_result') {
    const result=p.result||{}, summary={};
    for (const key of ['ok','error','name','revision','status','completed','verified','scope','source_hash','run_id','syntax_valid']) if (key in result) summary[key]=result[key];
    if (result.stdout) summary.output=result.stdout;
    addCard({id:event.id+':result',event_id:event.id,at:event.at,kind:result.ok===false||result.ok===0?'failure':'action',title:'Returned · '+tool,tool,source_kind:'tool result',data:Object.keys(summary).length?summary:result});
    if(live)recent.set(tool,Date.now());
  }
  if (kind==='agent_error' || kind==='vision_error') addCard({id:event.id+':error',event_id:event.id,at:event.at,kind:'failure',title:kind,tool,source_kind:'reported failure',data:p});
}
function updateMetrics() { $('metrics').replaceChildren(...Object.entries(counts).filter(([k])=>k!=='action').map(([k,v])=>el('span','metric',v+' '+k))); }
async function loadEvents() {
  if (!selected) return;
  const identity=selected;
  for (let page=0;page<10;page++) {
    const data=await api('/api/events?task='+identity+'&after='+cursor);
    if (selected!==identity) return;
    updateTask(data.task);
    const cardsByEvent=new Map(); data.cards.forEach(c=>{ if(!cardsByEvent.has(c.event_id)) cardsByEvent.set(c.event_id,[]); cardsByEvent.get(c.event_id).push(c); });
    for (const event of data.events) { processEvent(event); (cardsByEvent.get(event.id)||[]).forEach(addCard); }
    cursor=data.cursor; updateMetrics(); follow();
    if (!data.has_more) break;
  }
}
function toolRows() {
  const mode=$('tool-kind').value;
  if(mode==='tools') return registry.tools;
  if(mode==='methods') return registry.methods;
  return registry.artifacts.filter(x=>mode==='scripts'?x.kind==='script':x.kind!=='script');
}
function renderTools() {
  const mode=$('tool-kind').value,q=$('tool-search').value.toLowerCase();
  const rows=toolRows().filter(x=>(x.name+' '+(x.description||'')+' '+(x.signature||'')+' '+(x.path||'')+' '+(x.family||'')).toLowerCase().includes(q));
  $('tools').replaceChildren(); $('tool-count').textContent=rows.length;
  $('tool-note').textContent=mode==='methods'?'Library source references, callable through inspected AHK/SDK code. Direct internal calls in arbitrary scripts need tracing to appear as active.':mode==='scripts'?'Saved source and revisions. Files materialize on validation/run. New files appear automatically.':'Exact registered tools and saved artifacts.';
  for(const item of rows.slice(0,toolLimit)) {
    const b=el('button','tool'); b.dataset.tool=item.name; b.dataset.family=item.family||'';
    b.append(el('strong','',item.signature||item.name),el('small','',mode==='methods'?`${item.path}:${item.line}`:item.path?`r${item.revision} · ${item.path}`:item.description||item.kind));
    b.onclick=async()=>{try { let data=item;if(item.kind)data=await api('/api/artifact?name='+encodeURIComponent(item.name));else if(mode==='methods')data=await api('/api/method?path='+encodeURIComponent(item.path)+'&line='+item.line);const node=el('div');if(data.content!==undefined){node.append(el('p','hint',`${data.kind} · revision ${data.revision} · ${data.metadata?.sha256||''}`),el('pre','',data.content));details(node,'Usage, parameters and metadata',{usage:data.usage,examples:data.examples,metadata:data.metadata});}else node.append(el('pre','',data.source||JSON.stringify(data,null,2)));showDetail(item.name,node);}catch(e){banner(e.message);}};
    $('tools').append(b);
  }
  $('more-tools').hidden=rows.length<=toolLimit; highlightTools();
}
function highlightTools() {
  document.querySelectorAll('[data-tool]').forEach(node=>{
    const name=node.dataset.tool, f=node.dataset.family;
    const traced=[...activeMethods].some(([method])=>method===name||method.split('.').pop()===name);
    node.classList.toggle('active',activeTools.has(name)||activeArtifacts.has(name)||traced);
    node.classList.toggle('recent',!node.classList.contains('active')&&Date.now()-(recent.get(name)||recent.get(f)||0)<5000);
  });
  const families=['Images','Accessibility','OCR','FindText','AHK scripts','Workflows','Knowledge','Input'];
  $('families').replaceChildren(...families.map(name=>{const b=el('span','family',name);b.classList.toggle('active',[...activeMethods.values()].some(x=>x.family===name));b.classList.toggle('recent',Date.now()-(recent.get(name)||0)<5000);return b;}));
}
$('tool-search').oninput=()=>{toolLimit=100;renderTools();};$('tool-kind').onchange=()=>{toolLimit=100;renderTools();};$('more-tools').onclick=()=>{toolLimit+=100;renderTools();};
async function loadRegistry() {const data=await api('/api/registry');const key=JSON.stringify(data);if(key!==registryKey){registry=data;registryKey=key;renderTools();}lastRegistry=Date.now();}
async function loadDiscoveries() {
  const data=await api('/api/discoveries?query='+encodeURIComponent($('claim-query').value)), records=$('discovery-records'); records.replaceChildren();
  records.append(el('h2','','Retained claims and evidence'),el('p','hint','Historical support is scoped to its recorded context. Rehearsals demonstrate reuse; they do not add real-world validation. Click a claim to inspect its observations. Showing up to 100 matching claims and notes.'));
  for(const claim of data.claims||[]){const node=el('article','card');node.append(el('div','badge',`Claim ${claim.id} · ${claim.source} · ${claim.passes?'supported in recorded context':'unvalidated'}`),el('strong','',claim.claim),el('p','',claim.use_text||''),el('p','hint',`${claim.observations} observations · ${claim.passes||0} eligible passes · ${claim.failures||0} eligible failures`));const button=el('button','','Inspect lesson and supporting evidence');button.onclick=async()=>{try{const result=await api('/api/claim?id='+claim.id), value=result[0],body=el('div');body.append(el('p','',claim.claim),el('p','',claim.use_text||''));if(value.lesson){body.append(el('h2','','Stored lesson'));for(const step of value.lesson.steps){const row=el('article','card');row.append(el('strong','',step.layer||'Lesson step'),el('p','',step.text||JSON.stringify(step)));body.append(row);}}else body.append(el('p','hint','No stored lesson has been built for this claim.'));for(const e of value.evidence||[]){const entry=el('article','card');entry.append(el('strong','',`${e.outcome} · ${e.eligible?'eligible evidence':'reference / rehearsal'} · ${e.ts}`),el('p','',e.detail||''));details(entry,'Context and provenance',{context:e.context,provenance:e.provenance,session:e.session});body.append(entry);}showDetail('Claim '+claim.id,body);}catch(e){banner(e.message);}};node.append(button);records.append(node);}
  records.append(el('h2','','Agent knowledge notes'));
  if(!data.discoveries.length)records.append(el('p','empty','New observed evidence and clearly labelled model interpretations appear here as the agent works.'));
  for(const record of data.discoveries){const node=el('article','card');node.append(el('div','badge',record.metadata?.source_kind||'reference'),el('strong','',record.description||record.name),el('p','hint',record.name+' · '+record.updated_at));let value;try{value=JSON.parse(record.content);}catch{value=record.content;}if(typeof value==='string')node.append(el('p','',value.slice(0,1800)));else if(value){if(value.frame?.title)node.append(el('p','','Observed window: '+value.frame.title));if(value.controls?.length)node.append(el('p','','Controls: '+value.controls.slice(0,20).map(x=>x.name||x.role).join(', ')));if(value.ocr?.text)node.append(el('p','','Read text: '+value.ocr.text.slice(0,1200)));if(value.total_matches!==undefined)node.append(el('p','','FindText located '+value.total_matches+' visual matches.'));for(const [key,v] of Object.entries(value).filter(([k,v])=>typeof v!=='object'&&k!=='text').slice(0,8))node.append(el('p','hint',key.replaceAll('_',' ')+': '+String(v).slice(0,350)));}details(node,'Full evidence / interpretation',record.content);records.append(node);}lastDiscoveries=Date.now();
}
$('claim-query').oninput=()=>{lastDiscoveries=0;loadDiscoveries().catch(e=>banner(e.message));};
function renderAttachments(){ $('attachments').replaceChildren(...pendingImages.map((image,index)=>{const node=el('span','attachment',`${image.label} · ${image.width}×${image.height}`),button=el('button','','Remove');button.type='button';button.onclick=()=>{pendingImages.splice(index,1);renderAttachments();};node.append(button);return node;})); }
async function attach(file){if(pendingImages.length>=4)throw new Error('Attach up to four images per task');$('draft-status').textContent='Adding image locally…';const dataUrl=await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.onerror=reject;r.readAsDataURL(file);});const image=await api('/api/images',{data_url:dataUrl,label:file.name||'Clipboard snip'});pendingImages.push(image);renderAttachments();$('draft-status').textContent='Attached locally. Vision analysis starts when sent.';}
$('prompt').addEventListener('paste',event=>{const files=[...event.clipboardData.items].filter(x=>x.type.startsWith('image/')).map(x=>x.getAsFile());if(files.length){event.preventDefault();(async()=>{for(const file of files)await attach(file);})().catch(e=>banner(e.message));}});
$('image-file').onchange=event=>{const file=event.target.files[0];if(file)attach(file).catch(e=>banner(e.message));event.target.value='';};
$('composer').onsubmit=async event=>{event.preventDefault();const prompt=$('prompt').value.trim()||(pendingImages.length?'Analyze the attached image and explain what is visible.':'');if(!prompt)return;try{const history=task?.status==='complete'&&task.response?[{role:'user',content:task.prompt.slice(0,16000)},{role:'assistant',content:task.response.slice(0,16000)}]:[];const result=await api('/api/tasks',{prompt,images:pendingImages.map(x=>x.id),history});$('prompt').value='';pendingImages=[];renderAttachments();await refreshRuns();selectRun(result.id);switchView('canvas');banner('');}catch(e){banner(e.message);}};
$('prompt').onkeydown=event=>{if(event.ctrlKey&&event.key==='Enter'){$('composer').requestSubmit();event.preventDefault();}};
$('stop').onclick=()=>selected&&api('/api/cancel',{task:selected}).catch(e=>banner(e.message));
async function poll(){if(running||!token)return;running=true;try{const health=await api('/api/health');$('connection').textContent=health.fan_connected?'Live · native tools connected':'Connecting native tools';activeTools=new Set(health.activity?.tools||[]);activeArtifacts=new Set((health.managed_scripts||[]).map(x=>x.name));if(!activeTools.size)activeMethods.clear();await refreshRuns();await loadEvents();if(Date.now()-lastRegistry>4000)await loadRegistry();if(currentView==='discoveries'&&Date.now()-lastDiscoveries>5000)await loadDiscoveries();highlightTools();if(!activeMethods.size)$('live-method').textContent=activeTools.size?'Calling '+[...activeTools].join(', '):task?.status==='running'?'Agent planning / processing':'Retained observations · resolve live targets again before input';banner('');}catch(e){$('connection').textContent='Disconnected';banner(e.message);}finally{running=false;}}
switchView(currentView);if(!token)banner('Open Live Workbench from Macro Automator to connect. This page does not expose local observations without the access token.');else{poll();setInterval(poll,1000);}
