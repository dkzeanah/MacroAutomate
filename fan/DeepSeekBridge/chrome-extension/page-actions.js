import {collect} from './collector.js';

export function prepareText(command){
 const actual=collect().elements.find(e=>e.element_id===command.field.element_id);
 const node=window.__fanNodes?.get(command.field.element_id);
 if(!node?.isConnected||!actual||actual.protected||!actual.enabled||['name','role','type'].some(k=>actual[k]!==command.field[k]))throw Error('Field identity changed before typing.');
 if(!['INPUT','TEXTAREA'].includes(node.tagName)||['password','checkbox','radio','file','hidden'].includes(node.type)||node.readOnly)throw Error('Field does not permit saved text input.');
 node.scrollIntoView({block:'center'});node.focus();node.select();
 if(document.activeElement!==node)throw Error('Expected field did not receive focus.');
 return {ok:true};
}

// This function is bundled code. Command data is serialized as JSON, never JS.
export async function act(command){
 const visible=e=>{const r=e.getBoundingClientRect(),s=getComputedStyle(e);return !e.closest('[aria-hidden="true"]')&&r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden'};
 const fields=collect().elements;
 const expected=command.field;
 const actual=fields.find(e=>e.element_id===expected?.element_id);
 const node=window.__fanNodes?.get(expected?.element_id);
 if(!node?.isConnected||!actual||actual.protected||!actual.enabled||['name','role','type'].some(k=>actual[k]!==expected[k]))throw Error('Observed target changed or is protected; observe again.');
 node.scrollIntoView({block:'center'});
 document.getElementById('__fanHighlight')?.remove();
 const box=node.getBoundingClientRect(),highlight=document.createElement('div');highlight.id='__fanHighlight';
 Object.assign(highlight.style,{position:'fixed',left:box.x+'px',top:box.y+'px',width:box.width+'px',height:box.height+'px',border:'3px solid #ff2020',pointerEvents:'none',zIndex:2147483647,boxSizing:'border-box'});
 highlight.setAttribute('aria-hidden','true');document.body.append(highlight);setTimeout(()=>highlight.remove(),1500);
 if(command.kind==='highlight')return {ok:true};
 if(command.kind==='click'){
  if(!/^(?:apply(?: now| for this job)?|submit(?: application)?|send application|next|continue|review application)$/i.test(actual.name.trim()))throw Error('Not an application navigation/submission control.');
  if(!visible(node))throw Error('Target is hidden.');node.click();return {ok:true};
 }
 const setValue=(e,value)=>{e.focus();const prototype=e instanceof HTMLTextAreaElement?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(prototype,'value').set.call(e,String(value));e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));};
 if(command.kind==='upload'){
  if(node.type!=='file'||!/resume|résumé|\bcv\b/i.test(actual.name))throw Error('Not a resume/CV field.');
  const bytes=Uint8Array.from(atob(command.pdf_base64),c=>c.charCodeAt(0));
  if(bytes.length>20*1024*1024||new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-')throw Error('Invalid selected PDF.');
  const transfer=new DataTransfer();transfer.items.add(new File([bytes],command.filename,{type:'application/pdf'}));
  node.files=transfer.files;node.dispatchEvent(new Event('input',{bubbles:true}));node.dispatchEvent(new Event('change',{bubbles:true}));
  if(node.files[0]?.name!==command.filename)throw Error('Selected resume could not be verified.');
  return {ok:true,filename:command.filename,sha256:command.sha256};
 }
 if(command.kind!=='fill')throw Error('Unsupported page operation.');
 if(!visible(node))throw Error('Field is hidden.');
 const answer=command.answer;
 if(node.tagName==='SELECT'){
  const matches=Array.from(node.options).filter(o=>!o.disabled&&o.label.trim().toLowerCase()===String(answer).toLowerCase());
  if(matches.length!==1)throw Error('No unique observed select option for saved answer.');
  node.value=matches[0].value;node.dispatchEvent(new Event('input',{bubbles:true}));node.dispatchEvent(new Event('change',{bubbles:true}));
 }else if(actual.role==='combobox'){
  node.focus();if(!command.prepared_text)node.click();if(node.tagName==='INPUT'&&!command.prepared_text)setValue(node,answer);
  await new Promise(resolve=>setTimeout(resolve,900));
  const control=node.getAttribute('aria-controls');
  let lists=control?[document.getElementById(control)].filter(Boolean):Array.from(document.querySelectorAll('[role="listbox"]')).filter(visible);
  if(lists.length!==1)throw Error('No unique dropdown associated with this field.');
  const options=Array.from(lists[0].querySelectorAll('[role="option"]')).filter(visible);
  let matches=options.filter(o=>o.innerText.trim().toLowerCase()===String(answer).toLowerCase());
  if(matches.length!==1){
   const comparable=value=>{let v=value.toLowerCase().replace(/\+\d+/g,'');if(/location/i.test(actual.name))v=v.replace(/\bunited states(?: of america)?\b/g,'');return v.replace(/\balabama\b/g,'al').replace(/[^a-z0-9]+/g,' ').trim()};
   matches=options.filter(o=>comparable(o.innerText)===comparable(String(answer)));
  }
  if(matches.length!==1)throw Error('Saved answer does not uniquely match dropdown choices.');
  matches[0].click();
 }else if(node.type==='checkbox'||node.type==='radio'){
  if(typeof answer!=='boolean')throw Error('A saved boolean is required for this checkbox.');
  if(node.checked!==answer)node.click();if(node.checked!==answer)throw Error('Checkbox state not confirmed.');
 }else if(node.tagName==='INPUT'||node.tagName==='TEXTAREA'){
  if(!command.prepared_text)setValue(node,answer);
  if(node.value!==String(answer))throw Error('Saved text value was not confirmed.');
 }
 else throw Error('Unsupported field requires user action.');
 return {ok:true};
}
