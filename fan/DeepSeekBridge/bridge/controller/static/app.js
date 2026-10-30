'use strict';
const $=id=>document.getElementById(id);
const escapeHTML=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const number=value=>value==null?'—':Number(value).toLocaleString();
const symbols={claude:'✳',codex:'⌘',deepseek:'≈'};
const labels={claude:'Claude',codex:'Codex',deepseek:'DeepSeek'};
let state=null,provider='claude',mode='atlas',selected=null,source=null,eventRows=[],currentPage='workbench',currentPanel='activity',fingerprint='';
let busy=false,toastTimer,comparisonLoading=false,refreshing=false;
async function api(path,options={}){
 const response=await fetch('/api/'+path,{...options,headers:{'Content-Type':'application/json',...(options.headers||{})}});
 if(!response.ok){let value;try{value=await response.json();}catch{value={detail:response.statusText};}throw new Error(typeof value.detail==='string'?value.detail:JSON.stringify(value.detail));}
 return response.json();
}
function toast(message,error=false){$('toast').textContent=message;$('toast').classList.remove('hidden');$('toast').style.borderColor=error?'#9e5e60':'#608774';clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').classList.add('hidden'),6000);}
function statusBadge(value){return `<span class="badge ${escapeHTML(value)}">${escapeHTML(value)}</span>`;}
function showPage(page){currentPage=page;document.querySelectorAll('.page').forEach(el=>el.classList.toggle('hidden',el.id!=='page-'+page));document.querySelectorAll('[data-page]').forEach(el=>el.classList.toggle('active',el.dataset.page===page));window.scrollTo({top:0});if(page==='comparisons')renderComparisons();if(page==='workspace')renderWorkspace();}
function chooseProvider(id){provider=id;renderProviders();const value=state?.providers.find(p=>p.id===id);$('model').value=value?.default_model||'';}
function renderProviders(){if(!state)return;$('providers').innerHTML=state.providers.map(p=>`<button class="provider ${provider===p.id?'selected':''}" type="button" data-provider="${p.id}" ${p.available?'':'disabled'} title="${escapeHTML(p.auth)}"><span class="provider-symbol">${symbols[p.id]}</span><span>${labels[p.id]}<small>${p.available?(p.id==='deepseek'?'Key available':'CLI installed'):'Not configured'}</small></span></button>`).join('');}
function chooseMode(value){mode=value;document.querySelectorAll('[data-mode]').forEach(el=>el.classList.toggle('selected',el.dataset.mode===mode));$('submit').innerHTML=mode==='compare'?'Run comparison <span>⇄</span>':'Run task <span>↗</span>';$('access').disabled=mode==='compare';if(mode==='compare')$('access').value='read_only';$('mode-note').textContent=mode==='compare'?'Two fresh runs. Matched source. Randomized order.':mode==='atlas'?'Fresh run. Atlas retrieval available.':'Fresh run. Ordinary source tools.';}
async function refresh(){
 if(refreshing)return;refreshing=true;
 try{state=await api('state');$('connection').innerHTML='<span class="status-dot"></span>Local connection';$('total-runs').textContent=number(state.runs.length);const known=state.runs.filter(r=>r.usage?.total_tokens!=null);$('total-tokens').textContent=known.length?number(known.reduce((n,r)=>n+r.usage.total_tokens,0)):'—';$('active-runs').textContent=state.runs.filter(r=>['queued','running','preparing'].includes(r.status)).length;$('pair-count').textContent=new Set(state.runs.filter(r=>state.runs.some(x=>x.batch===r.batch&&x.mode!==r.mode)).map(r=>r.batch)).size;$('history-count').textContent=state.runs.length;renderProviders();renderRuns();if(selected)updateSelected();if(currentPage==='comparisons')renderComparisons();if(currentPage==='workspace')renderWorkspace();if(!state.workspace_exists){$('notice').textContent='The domesim-atlas working copy is not ready.';$('notice').classList.remove('hidden');}}
 catch(error){$('connection').textContent='Connection unavailable';if(!state)toast(error.message,true);}
 finally{refreshing=false;}
}
function renderRuns(){
 if(!state.runs.length)return;
 $('run-list').innerHTML=state.runs.map(r=>`<button class="run-row ${r.id===selected?'selected':''}" data-run="${r.id}"><span class="run-icon">${symbols[r.provider]}</span><span class="run-label"><strong>${escapeHTML(r.prompt)}</strong><small>${labels[r.provider]} · ${r.mode==='atlas'?'Atlas assisted':'Normal reading'} · ${new Date(r.created*1000).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'})}</small></span><span class="run-right">${statusBadge(r.status)}<small>${r.usage?.total_tokens!=null?number(r.usage.total_tokens)+' tokens':'Usage pending'}</small></span></button>`).join('');
}
async function selectRun(id){
 selected=id;eventRows=[];fingerprint='';if(source)source.close();$('events').textContent='';$('inspector-empty').classList.add('hidden');$('inspector-content').classList.remove('hidden');$('selected-id').textContent=id.toUpperCase();renderRuns();updateSelected();
 try{let after=0;for(let page=0;page<30;page++){const rows=await api('runs/'+id+'/events?after='+after);if(selected!==id)return;eventRows.push(...rows);if(rows.length)after=rows.at(-1).id;if(rows.length<300)break;}renderEvents();if(selected!==id)return;const stream=new EventSource('/api/runs/'+id+'/stream?after='+after);source=stream;stream.onmessage=message=>{if(selected!==id)return;const row=JSON.parse(message.data);if(!eventRows.some(r=>r.id===row.id))eventRows.push(row);renderEvents();};stream.addEventListener('end',()=>{stream.close();refresh();});}
 catch(error){toast(error.message,true);}
 showPanel(currentPanel);if(window.matchMedia('(max-width:930px)').matches)document.querySelector('.inspector').scrollIntoView({block:'start'});
}
function updateSelected(){
 const r=state.runs.find(r=>r.id===selected);if(!r)return;
 $('run-summary').innerHTML=`${statusBadge(r.status)} <span class="run-meta">${labels[r.provider]} / ${r.mode==='atlas'?'ATLAS':'NORMAL'}</span><p>${escapeHTML(r.prompt)}</p><div class="run-meta">${escapeHTML(r.model||'Provider default')} · ${escapeHTML(r.settings.access)} · ${r.baseline?r.baseline.slice(0,12):'snapshot pending'}</div>`;
 $('answer').textContent=r.result||r.error||(['queued','preparing','running'].includes(r.status)?'The agent’s final answer will appear here.':'No final answer was returned.');$('cancel').disabled=!['queued','preparing','running'].includes(r.status);$('export').href='/api/runs/'+r.id+'/export';renderUsage(r);renderApprovals();
}
function renderApprovals(){
 const rows=state.approvals.filter(a=>a.run_id===selected);$('approvals').innerHTML=rows.map(a=>`<div class="approval"><strong>Command approval required</strong><pre>${escapeHTML(a.command)}</pre><small>Working directory: this run’s isolated snapshot. Review the command before allowing execution.</small><div class="approval-actions"><button class="button accent" data-approval="${a.id}" data-decision="true">Allow command</button><button class="button quiet" data-approval="${a.id}" data-decision="false">Deny</button></div></div>`).join('');
}
function eventTitle(row){const p=row.payload;if(row.kind==='provider_event'){if(p.type==='text_delta')return 'Agent response';if(p.type==='assistant')return 'Agent message / tool request';return 'Provider · '+(p.type||'event');}if(row.kind==='tool_start')return 'Calling '+p.name;if(row.kind==='tool_result')return p.name+' · '+number(p.response_characters)+' response characters';if(row.kind==='preparing')return p.stage;return row.kind.replaceAll('_',' ');}
function renderEvents(){
 const el=$('events');const panel=$('panel-activity');const atBottom=panel.scrollHeight-panel.scrollTop-panel.clientHeight<90;
 const rows=eventRows.filter(r=>!(r.kind==='provider_event'&&['text_delta','usage'].includes(r.payload.type))).slice(-180);
 const open=new Set([...el.querySelectorAll('details[open]')].map(d=>d.dataset.event));
 el.innerHTML=rows.map(r=>`<details data-event="${r.id}" class="event ${escapeHTML(r.kind)}" ${open.has(String(r.id))?'open':''}><summary><span class="event-time">${new Date(r.at*1000).toLocaleTimeString()}</span>${escapeHTML(eventTitle(r))}</summary><pre>${escapeHTML(JSON.stringify(r.payload,null,2))}</pre></details>`).join('')||'<p class="body-copy">Waiting for the first event…</p>';
 if(atBottom)panel.scrollTop=panel.scrollHeight;
}
function renderUsage(r){
 const u=r.usage;const cells=[['INPUT · INCLUDING CACHE',u?.input_tokens],['OUTPUT',u?.output_tokens],['CACHED INPUT · SUBSET',u?.cached_input_tokens],['TOTAL REPORTED',u?.total_tokens]];
 $('usage').innerHTML=`<div class="usage-grid">${cells.map(([label,value])=>`<div class="usage-cell"><small>${label}</small><strong>${number(value)}</strong></div>`).join('')}</div><p class="usage-note">${u?'Source: provider-reported. '+(u.complete?'Usage fields received.':'Partial usage; excluded from completed comparisons.'):'No provider usage received. Unknown is not zero.'}<br>Cached input is already included in total input. Token totals do not measure answer quality or subscription charges.</p>${u?.reported_cost_usd!=null?`<p class="usage-note">Claude reported API-equivalent cost: $${Number(u.reported_cost_usd).toFixed(4)}</p>`:''}<p class="usage-note">Requested model: ${escapeHTML(r.model||'provider default')}<br>Usage model label: ${escapeHTML(u?.model||'unreported')}</p>${u?`<details class="quality"><summary>Raw reported usage</summary><pre>${escapeHTML(JSON.stringify(u,null,2))}</pre></details>`:''}`;
}
async function showPanel(panel){
 currentPanel=panel;
 document.querySelectorAll('[data-inspector]').forEach(el=>el.classList.toggle('active',el.dataset.inspector===panel));
 document.querySelectorAll('.inspector-panel').forEach(el=>el.classList.toggle('hidden',el.id!=='panel-'+panel));
 if(panel==='diff'&&selected){
  $('diff-note').textContent='Loading source changes…';$('apply').classList.add('hidden');
  try{
   const id=selected,d=await api('runs/'+id+'/diff');if(id!==selected)return;
   fingerprint=d.fingerprint;
   $('diff-note').textContent=d.applied?'These reviewed changes have been applied to domesim-atlas.':d.changes.length?`${d.changes.length} source file(s) changed. Review the diff before applying.`:'No source changes in this snapshot.';
   $('diff').textContent=d.diff||'No diff.';
   const r=state.runs.find(r=>r.id===selected);
   $('apply').classList.toggle('hidden',d.applied||!d.changes.length||r?.status!=='completed'||r?.settings.access!=='edit'||d.truncated);
  }catch(error){toast(error.message,true);}
 }
}
async function renderComparisons(){
 if(comparisonLoading)return;comparisonLoading=true;
 try{
 const batches=[...new Set(state.runs.filter(r=>state.runs.some(x=>x.batch===r.batch&&x.mode!==r.mode)).map(r=>r.batch))];if(!batches.length){$('comparisons').innerHTML='<div class="empty"><span>⇄</span><h3>Compare the process, not just the prompt.</h3><p>Select “Compare both” to run one task twice from a matched source snapshot.</p></div>';return;}
 const reports=await Promise.all(batches.map(b=>api('comparisons/'+b).catch(()=>null)));
 const visible=reports.filter(Boolean).filter(c=>$('comparison-filter').value==='all'||c.comparable||[c.atlas,c.normal].some(r=>['queued','preparing','running'].includes(r.status)));
 $('comparisons').innerHTML=visible.map(c=>{const rows=[c.atlas,c.normal];const reviews=Object.keys(c.reviews||{}).length;return `<article class="comparison"><div class="comparison-title"><span>${labels[c.atlas.provider]} · ${escapeHTML(c.atlas.model||'default model')}</span><span>${c.atlas.batch}</span></div><h3>${escapeHTML(c.atlas.prompt)}</h3><table><thead><tr><th>STRATEGY</th><th>STATUS</th><th>INPUT</th><th>OUTPUT</th><th>TOTAL</th></tr></thead><tbody>${rows.map(r=>`<tr><td><a href="#" data-run="${r.id}">${r.mode==='atlas'?'Atlas ↗':'Normal ↗'}</a></td><td>${statusBadge(r.status)}</td><td>${number(r.usage?.input_tokens)}</td><td>${number(r.usage?.output_tokens)}</td><td>${number(r.usage?.total_tokens)}</td></tr>`).join('')}</tbody></table><div class="saving">${c.token_reduction_percent!=null?(c.token_reduction_percent>=0?'↓ ':'↑ ')+Math.abs(c.token_reduction_percent)+'% tokens': '—'}</div><p>${c.comparable?'Matched usage comparison. '+c.note:'Comparison pending or invalid. See checks below.'}<br>Quality: ${reviews}/2 human reviews recorded. A token difference does not establish equal understanding.</p><details><summary>Comparison checks & source identity</summary>${Object.entries(c.checks).map(([k,v])=>`<span class="check ${v?'pass':'fail'}">${v?'✓':'○'} ${escapeHTML(k.replaceAll('_',' '))}</span>`).join('')}<p>Snapshot: ${escapeHTML(c.atlas.baseline||'pending')}</p></details></article>`;}).join('')||'<div class="empty"><h3>No matched results yet.</h3><p>Choose “All attempts” to inspect failed or source-blocked runs.</p></div>';
 }finally{comparisonLoading=false;}
}
function renderWorkspace(){const i=state.index;$('workspace-info').innerHTML=`<div class="workspace-path">${escapeHTML(state.workspace)}</div><div class="index-stats"><div><strong>${number(i?.files)}</strong>indexed Python files</div><div><strong>${number(i?.symbols)}</strong>symbols</div><div><strong>${i?.status==='ready'?'Ready':escapeHTML(i?.status||'Not indexed')}</strong>workspace index</div></div>${i?.error?`<p class="body-copy">${escapeHTML(i.error)}</p>`:''}<p class="body-copy">Each Atlas run gets its own index, independently of the workspace index above.</p>`;}
document.addEventListener('click',async event=>{
 const button=event.target.closest('button,a');if(!button)return;
 try{
 if(button.dataset.page)showPage(button.dataset.page);
 if(button.dataset.provider)chooseProvider(button.dataset.provider);
 if(button.dataset.mode)chooseMode(button.dataset.mode);
 if(button.dataset.inspector)showPanel(button.dataset.inspector);
 if(button.dataset.run){event.preventDefault();selectRun(button.dataset.run);}
 if(button.dataset.example){const examples={trace:'Find the helper that prevents rendered deliverables from being overwritten. Explain how it chooses the next versioned path and cite the exact function. Keep the answer under 150 words.',map:'Map the film creation and deliverable registration flow. Identify the authoritative entry point, main dependencies, and existing validation checks. Cite source and distinguish confirmed edges from assumptions.',refactor:'Propose three small refactor candidates in the film/deliverables subsystem. Cite exact symbols, preserved contracts, callers, risks and validation commands. Make no source changes.'};$('prompt').value=examples[button.dataset.example];}
 if(button.dataset.approval){await api('approvals/'+button.dataset.approval,{method:'POST',body:JSON.stringify({approve:button.dataset.decision==='true'})});toast('Command decision recorded');refresh();}
 }catch(error){toast(error.message,true);}
});
$('task-form').addEventListener('submit',async event=>{event.preventDefault();if(busy)return;busy=true;$('submit').disabled=true;try{const body={provider,mode,model:$('model').value,prompt:$('prompt').value,access:$('access').value,max_turns:Number($('turns').value),timeout_seconds:Number($('timeout').value),budget_usd:Number($('budget').value),max_output_tokens:Number($('output').value)};const result=await api('runs',{method:'POST',body:JSON.stringify(body)});await refresh();await selectRun(result.run_ids[0]);toast(mode==='compare'?'Paired runs queued from one source snapshot.':'Task queued.');}catch(error){toast(error.message,true);}finally{busy=false;$('submit').disabled=false;}});
$('cancel').addEventListener('click',async()=>{try{await api('runs/'+selected+'/cancel',{method:'POST'});toast('Run stopped');refresh();}catch(error){toast(error.message,true);}});
$('apply').addEventListener('click',async()=>{try{const r=await api('runs/'+selected+'/apply',{method:'POST',body:JSON.stringify({fingerprint})});toast(r.applied.length+' file(s) applied to domesim-atlas');$('apply').classList.add('hidden');}catch(error){toast(error.message,true);}});
$('reindex').addEventListener('click',async()=>{try{await api('reindex',{method:'POST'});toast('Workspace index refresh queued');refresh();}catch(error){toast(error.message,true);}});
$('save-review').addEventListener('click',async()=>{try{await api('runs/'+selected+'/review',{method:'POST',body:JSON.stringify({correctness:Number($('q-correct').value),grounding:Number($('q-ground').value),validation:Number($('q-valid').value),notes:$('q-notes').value})});toast('Human review saved');}catch(error){toast(error.message,true);}});
$('refresh').addEventListener('click',refresh);
$('comparison-filter').addEventListener('change',renderComparisons);
refresh().then(()=>chooseProvider(state?.providers.find(p=>p.id==='codex'&&p.available)?.id||state?.providers.find(p=>p.available)?.id||'claude'));
setInterval(refresh,2500);
