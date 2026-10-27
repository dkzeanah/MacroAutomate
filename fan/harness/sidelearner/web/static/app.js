const ws = new WebSocket(`ws://${window.location.host}/ws`);
const eventsEl = document.getElementById('events');
const connStatus = document.getElementById('conn-status');
let currentFacts = [];
let currentCaptures = [];

ws.onopen = () => { connStatus.textContent = 'ws: open'; connStatus.classList.add('ok'); };
ws.onclose = () => { connStatus.textContent = 'ws: closed'; connStatus.classList.remove('ok'); };
ws.onerror = () => { connStatus.textContent = 'ws: error'; };
ws.onmessage = (ev) => {
  const data = JSON.parse(ev.data);
  if (data.type === 'ping') return;
  const div = document.createElement('div');
  div.className = 'entry';
  div.innerHTML = `<span class="muted">${new Date().toLocaleTimeString()}</span> <b>${data.type}</b> ${JSON.stringify(data.data).slice(0, 160)}`;
  eventsEl.prepend(div);
  while (eventsEl.children.length > 100) eventsEl.lastChild.remove();
  if (data.type === 'perception.audio.transcript.partial' || data.type === 'perception.audio.transcript') {
    const preview = document.getElementById('caption-preview');
    preview.textContent = data.data?.text || '';
    preview.classList.remove('muted');
  }
  if (data.type === 'captions.state') loadCaptionStatus();
  if (data.type.startsWith('perception.')) loadStatus();
};

async function getJson(path) {
  const r = await fetch(path);
  if (!r.ok) throw new Error(`${r.status}: ${r.statusText}`);
  return r.json();
}

async function loadStatus() {
  const data = await getJson('/api/status');
  const s = data.twin || {};
  const html = `
    <div class="row"><span class="muted">business</span><span>${data.config?.business || '-'}</span></div>
    <div class="row"><span class="muted">observations</span><span>${s.observations ?? '-'}</span></div>
    <div class="row"><span class="muted">learned</span><span>${s.ledger?.learned ?? '-'}/${s.ledger?.total ?? '-'}</span></div>
    <div class="row"><span class="muted">facts</span><span>${s.graph?.facts ?? '-'}</span></div>
    <div class="row"><span class="muted">entities</span><span>${s.graph?.entities ?? '-'}</span></div>
    <div class="row"><span class="muted">gaps</span><span class="${s.open_gaps ? 'warn' : 'ok'}">${s.open_gaps ?? 0}</span></div>
    <div class="row"><span class="muted">prompts</span><span>${s.open_prompts ?? 0}</span></div>
    <div class="row"><span class="muted">watchers</span><span>${(data.perception?.watchers || []).map(w => w.kind).join(', ') || '-'}</span></div>
  `;
  document.getElementById('status').innerHTML = html;
}

function _renderFacts(facts) {
  if (!facts.length) return '<div class="muted">no facts yet</div>';
  return `<div class="facts-list">${facts.map(f => `
    <div class="fact-item">
      <div class="fact-domain">${f.domain || 'general'}</div>
      <div>${escapeHtml(f.text || '')}</div>
      <div class="fact-meta">weight ${(f.weight || 0).toFixed(1)} · ${(f.confidence || 0).toFixed(2)} conf · ${new Date(f.last_seen).toLocaleString()}</div>
    </div>
  `).join('')}</div>`;
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

async function loadTwin(view) {
  const el = document.getElementById('twin-view');
  el.innerHTML = 'Loading…';
  try {
    if (view === 'status') {
      const data = await getJson('/api/twin/status');
      el.innerHTML = `<pre>${JSON.stringify(data, null, 2)}</pre>`;
    } else if (view === 'facts') {
      const data = await getJson('/api/twin/facts?limit=200');
      currentFacts = data.facts;
      el.innerHTML = `
        <input id="facts-search" class="search-box" placeholder="Search facts…" oninput="filterFacts(this.value)" />
        <div id="facts-list">${_renderFacts(currentFacts)}</div>
      `;
    } else if (view === 'gaps') {
      const data = await getJson('/api/twin/gaps');
      el.innerHTML = data.gaps.length
        ? data.gaps.map(g => `<div class="row"><span>gap#${g.id}</span><span>${escapeHtml(g.observation.slice(0, 120))}</span></div>`).join('')
        : '<div class="muted">no open gaps</div>';
    } else if (view === 'query') {
      el.innerHTML = `
        <input id="twin-query" class="search-box" placeholder="Ask the twin something…" onkeydown="if(event.key==='Enter') runTwinQuery()" />
        <button onclick="runTwinQuery()">Query twin</button>
        <pre id="twin-query-output" style="margin-top:0.5rem;"></pre>
      `;
    }
  } catch (e) {
    el.innerHTML = `<span class="danger">${e}</span>`;
  }
}

function filterFacts(term) {
  const lower = term.toLowerCase();
  const filtered = currentFacts.filter(f =>
    (f.text || '').toLowerCase().includes(lower) ||
    (f.domain || '').toLowerCase().includes(lower)
  );
  document.getElementById('facts-list').innerHTML = _renderFacts(filtered);
}

async function runTwinQuery() {
  const q = document.getElementById('twin-query').value;
  const out = document.getElementById('twin-query-output');
  if (!q) return;
  out.textContent = 'querying…';
  try {
    const data = await getJson(`/api/twin/query?q=${encodeURIComponent(q)}&k=8`);
    out.textContent = data.context_block || 'no results';
  } catch (e) {
    out.textContent = `error: ${e}`;
  }
}

async function loadPrompts() {
  const data = await getJson('/api/prompts');
  const el = document.getElementById('prompts');
  if (!data.prompts.length) { el.innerHTML = '<div class="muted">no open prompts</div>'; return; }
  el.innerHTML = data.prompts.map(p => `
    <div style="margin-bottom:0.5rem;">
      <div>#${p.id} [${p.kind}] ${escapeHtml(p.subject)}</div>
      <div class="muted">${escapeHtml(p.question)}</div>
      <input id="ans-${p.id}" placeholder="answer" style="width:65%" />
      <button onclick="answerPrompt(${p.id})">Answer</button>
    </div>
  `).join('');
}

async function answerPrompt(id) {
  const answer = document.getElementById(`ans-${id}`).value;
  const r = await fetch(`/api/prompts/${id}/answer`, {
    method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({answer})
  });
  const out = await r.json();
  alert(JSON.stringify(out));
  loadPrompts(); loadTwin('status');
}

async function loadSkills() {
  const data = await getJson('/api/skills');
  const el = document.getElementById('skills');
  el.innerHTML = data.skills.length
    ? data.skills.map(s => `<div class="row"><span>${s.name}</span><button class="secondary" onclick="runSkill('${s.name}')">run</button></div>`).join('')
    : '<div class="muted">no skills loaded</div>';
}

async function runSkill(name) {
  const r = await fetch(`/api/skills/${name}/run`, {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({vars:{}})});
  const out = await r.json();
  document.getElementById('chat-output').textContent = JSON.stringify(out, null, 2);
}

async function sendTask() {
  const input = document.getElementById('task-input');
  const output = document.getElementById('chat-output');
  output.textContent = 'running…';
  const r = await fetch('/api/chat', {
    method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({task: input.value})
  });
  const data = await r.json();
  output.textContent = data.ok ? data.answer : `FAILED: ${data.answer}`;
}

function formatDuration(seconds) {
  const value = Number(seconds || 0);
  const minutes = Math.floor(value / 60);
  return `${minutes}:${String(Math.round(value % 60)).padStart(2, '0')}`;
}

function renderCaptures(segments) {
  if (!segments.length) return '<div class="muted">No finalized audio files yet. Play speech, then leave a long pause.</div>';
  return segments.map(segment => `
    <div class="capture-item">
      <div class="capture-head">
        <span><b>${new Date(segment.created).toLocaleString()}</b> · ${formatDuration(segment.duration_s)} · ${escapeHtml(segment.language || 'language unknown')}</span>
        <span class="tag">${escapeHtml(segment.backend || 'not transcribed')}</span>
      </div>
      <audio controls preload="none" src="${segment.audio_url}"></audio>
      <div class="capture-text">${escapeHtml(segment.transcript || 'No transcript was produced for this file.')}</div>
      <div class="fact-meta">${escapeHtml(segment.device || '')} · ${escapeHtml(segment.capture_mode || '')} · segment ${escapeHtml(segment.segment_id)}</div>
    </div>
  `).join('');
}

async function loadCaptures() {
  const el = document.getElementById('captures');
  try {
    const data = await getJson('/api/captions/history?limit=50');
    currentCaptures = data.segments || [];
    el.innerHTML = renderCaptures(currentCaptures);
  } catch (e) {
    el.innerHTML = `<span class="danger">${escapeHtml(String(e))}</span>`;
  }
}

function showLatestTranscript() {
  const el = document.getElementById('latest-captured-text');
  el.style.display = 'block';
  if (!currentCaptures.length) {
    el.textContent = 'No captured transcript is available yet.';
    el.className = 'capture-text muted';
    return;
  }
  const latest = currentCaptures[0];
  el.textContent = latest.transcript || 'The latest file exists but has no transcript.';
  el.className = 'capture-text';
}

async function loadAudioInsights() {
  const el = document.getElementById('audio-insights');
  try {
    const data = await getJson('/api/captions/insights');
    const facts = data.facts || [];
    const domains = Object.entries(data.domains || {}).map(([name, count]) => `<span class="tag">${escapeHtml(name)}: ${count}</span>`).join(' ');
    el.innerHTML = `
      <div class="insight-grid">
        <div class="metric"><strong>${data.segments}</strong><span class="muted">audio files</span></div>
        <div class="metric"><strong>${data.transcribed}</strong><span class="muted">transcribed</span></div>
        <div class="metric"><strong>${formatDuration(data.duration_s)}</strong><span class="muted">captured duration</span></div>
        <div class="metric"><strong>${data.audio_observations}</strong><span class="muted">observations</span></div>
        <div class="metric"><strong>${data.ledger_learned}/${data.ledger_total}</strong><span class="muted">ledger learned</span></div>
        <div class="metric"><strong>${facts.length}</strong><span class="muted">active audio facts</span></div>
      </div>
      <div style="margin-bottom:0.75rem;"><b>Domains:</b> ${domains || '<span class="muted">none classified yet</span>'}</div>
      <div class="muted" style="margin-bottom:0.5rem;">Pipeline: finalized transcript → audio observation → ledger opportunity → fact extraction → taxonomy classification → semantic retrieval.</div>
      <div>${facts.length ? facts.map(f => `<div class="fact-item"><div class="fact-domain">${escapeHtml(f.domain)}</div><div>${escapeHtml(f.text)}</div><div class="fact-meta">weight ${Number(f.weight).toFixed(1)} · confidence ${Number(f.confidence).toFixed(2)}</div></div>`).join('') : '<div class="muted">No durable facts extracted from audio yet.</div>'}</div>
    `;
  } catch (e) {
    el.innerHTML = `<span class="danger">${escapeHtml(String(e))}</span>`;
  }
}

async function compressAudioKnowledge() {
  const r = await fetch('/api/twin/compress', {method: 'POST'});
  const data = await r.json();
  await loadAudioInsights();
  alert(`Processed ${data.processed || 0}; facts added ${data.facts_added || 0}; merged ${data.facts_merged || 0}.`);
}

async function loadCaptionStatus() {
  const label = document.getElementById('caption-status');
  const button = document.getElementById('caption-toggle');
  try {
    const data = await getJson('/api/captions/status');
    label.textContent = data.enabled ? 'overlay visible' : 'overlay hidden';
    label.className = data.enabled ? 'ok' : 'muted';
    button.textContent = data.enabled ? 'Hide overlay' : 'Show overlay';
  } catch (e) {
    label.textContent = `overlay error: ${e}`;
    label.className = 'danger';
  }
}

async function toggleCaptions() {
  const current = document.getElementById('caption-toggle').textContent.includes('Hide');
  const r = await fetch('/api/captions/toggle', {
    method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({enabled: !current})
  });
  if (!r.ok) throw new Error(`${r.status}: ${r.statusText}`);
  await loadCaptionStatus();
}

async function shutdownSideLearner() {
  if (!window.confirm('Shut down the SideLearner web app and close its overlay? The background daemon must be stopped separately.')) return;
  const r = await fetch('/api/app/shutdown', {method: 'POST'});
  const data = await r.json();
  document.getElementById('caption-status').textContent = data.message || 'shutting down…';
}

async function loadScreenshot() {
  const img = document.getElementById('latest-screenshot');
  const pathEl = document.getElementById('screenshot-path');
  img.style.display = 'none';
  pathEl.textContent = 'loading…';
  try {
    const latest = await getJson('/api/screenshots/latest');
    if (!latest.path) {
      pathEl.textContent = 'no screenshot yet';
      return;
    }
    img.src = `/api/screenshots/file?path=${encodeURIComponent(latest.path)}`;
    img.style.display = 'block';
    pathEl.textContent = latest.path;
  } catch (e) {
    pathEl.textContent = `error: ${e}`;
  }
}

document.querySelectorAll('.tab').forEach(t => t.addEventListener('click', () => {
  document.querySelectorAll('.tab').forEach(x => x.classList.remove('active'));
  t.classList.add('active');
  loadTwin(t.dataset.twin);
}));

loadStatus();
loadTwin('status');
loadPrompts();
loadSkills();
loadCaptionStatus();
loadCaptures();
loadAudioInsights();
loadScreenshot();
setInterval(loadStatus, 5000);
setInterval(loadPrompts, 10000);
setInterval(loadCaptures, 10000);
setInterval(loadAudioInsights, 15000);
