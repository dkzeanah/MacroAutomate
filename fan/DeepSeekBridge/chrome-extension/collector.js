export function collect(){
 const visible = e => {const r=e.getBoundingClientRect(),s=getComputedStyle(e); return !e.closest('[aria-hidden="true"]')&&r.width>0&&r.height>0&&s.visibility!=='hidden'&&s.display!=='none'};
 window.__fanNodes ||= new Map(); window.__fanIds ||= new WeakMap(); window.__fanSeq ||= 0;
 const token=e=>{if(!window.__fanIds.has(e)){const id='dom-'+(++window.__fanSeq);window.__fanIds.set(e,id);window.__fanNodes.set(id,e)}return window.__fanIds.get(e)};
 const label=e=>{const ids=(e.getAttribute('aria-labelledby')||'').split(/\s+/).map(id=>document.getElementById(id)?.innerText||'').join(' ').trim();
  const found=e.getAttribute('aria-label')||ids||Array.from(e.labels||[]).map(l=>{const c=l.cloneNode(true);c.querySelectorAll('input,textarea,select,button').forEach(n=>n.remove());return c.textContent}).join(' ').trim()||e.getAttribute('placeholder')||e.getAttribute('alt')||e.getAttribute('title')||e.innerText?.trim()||e.getAttribute('name')||e.id||'';
  return e.type==='file'?(e.id+' '+found).trim():found};
 const elements=Array.from(document.querySelectorAll('a[href],button,input,textarea,select,img,svg,canvas,h1,h2,h3,label,main,nav,aside,header,footer,p,[role="img"],[role="combobox"],[role="checkbox"],[role="radio"],[contenteditable="true"]')).slice(0,2500).map(e=>{
  const r=e.getBoundingClientRect(),type=(e.type||'').toLowerCase(),role=e.getAttribute('role')||e.tagName.toLowerCase();
  const protectedField=/password|one.time|otp|captcha|social.security|\bssn\b|credit.card/i.test(type+' '+e.name+' '+e.id+' '+label(e));
  return {element_id:token(e),kind:'dom',name:label(e).slice(0,3000),description:label(e).slice(0,3000),description_source:'observed_DOM_label',role,type,tag:e.tagName.toLowerCase(),required:!!e.required||e.getAttribute('aria-required')==='true'||/\*\s*$/.test(label(e)),
   visible:visible(e),enabled:!e.disabled,protected:protectedField,href:e.tagName==='A'?e.href:'',scope:'page',
   group:e.closest('fieldset')?.querySelector('legend')?.innerText||e.closest('form')?.getAttribute('aria-label')||e.closest('form,main,nav,aside,header,footer')?.tagName.toLowerCase()||'page',
   bounds:{x:r.x,y:r.y,w:r.width,h:r.height},document_bounds:{x:r.x+scrollX,y:r.y+scrollY,w:r.width,h:r.height},coordinate_space:'css_viewport',
   options:e.tagName==='SELECT'?Array.from(e.options).map(o=>({label:o.label,value:o.value,disabled:o.disabled})):[],
   value:protectedField?'':type==='file'?Array.from(e.files||[]).map(f=>f.name).join(','):type==='checkbox'||type==='radio'?e.checked:(e.closest('.select-shell')?.querySelector('.select__single-value')?.innerText||e.value||''),
   valid:e.closest('.select-shell')?.querySelector('input[required][aria-hidden="true"]')?.checkValidity()??(typeof e.checkValidity==='function'?e.checkValidity():null),invalid:e.getAttribute('aria-invalid')==='true',
   action_hint:type==='file'?'upload':role==='combobox'||e.tagName==='SELECT'?'select':e.tagName==='INPUT'||e.tagName==='TEXTAREA'||e.isContentEditable?'type':e.tagName==='BUTTON'||e.tagName==='A'?'click':'read'};
 });
 return {url:location.href,title:document.title,heading:document.querySelector('h1')?.innerText||'',elements,text:document.body.innerText.slice(0,100000),viewport:{w:innerWidth,h:innerHeight},scroll:{x:scrollX,y:scrollY},
  frames:Array.from(document.querySelectorAll('iframe')).map(e=>({title:e.title,src:e.src,visible:visible(e)})),
  job_data:Array.from(document.querySelectorAll('script[type="application/ld+json"]')).map(e=>{try{return JSON.parse(e.textContent)}catch{return null}}).filter(Boolean)};
}