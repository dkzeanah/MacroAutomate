import {collect} from './collector.js';
import {act,prepareText} from './page-actions.js';
let connection=null,busy=false;
const attached=new Set(),owned=new Set(),searchTabs=new Set();
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));

export function jobRoute(raw){
 try{const u=new URL(raw),h=u.hostname,p=u.pathname.toLowerCase().replace(/\/$/,'')||'/';
  if(u.protocol!=='https:'||u.username||u.password||u.port&&u.port!=='443'||!connection.sites.some(s=>h===s||h.endsWith('.'+s)))return false;
  if(h==='linkedin.com'||h==='www.linkedin.com')return p==='/'||/^\/(feed|jobs)(\/|$)/.test(p);
  if(h==='indeed.com'||h.endsWith('.indeed.com'))return p==='/'||/^\/(jobs|viewjob|job|rc\/clk|pagead\/clk)(\/|$)/.test(p);
  if(h==='ziprecruiter.com'||h.endsWith('.ziprecruiter.com'))return p==='/'||/^\/(jobs-search|jobs|job|c)(\/|$)/.test(p);
  if(['boards.greenhouse.io','job-boards.greenhouse.io'].includes(h))return p!=='/'&&!/^\/(users|settings|account)(\/|$)/.test(p);
  if(h==='jobs.dayforcehcm.com')return p==='/'||/candidateportal|\/jobs?(\/|$)|\/search(\/|$)/.test(p);
  return h.startsWith('recruiting')&&h.endsWith('.ultipro.com')&&/\/jobboard(\/|$)|\/opportunitydetail(\/|$)/.test(p);
 }catch{return false;}
}
async function request(path,options={}){
 const response=await fetch(`http://127.0.0.1:${connection.port}/chrome/${path}`,{...options,headers:{'X-Chrome-Token':connection.token,'Content-Type':'application/json',...options.headers}});
 if(!response.ok)throw Error(`Local connector ${response.status}`);return response.json();
}
async function tabInWindow(id){
 const tab=await chrome.tabs.get(id),win=await chrome.windows.get(tab.windowId);
 if(tab.windowId!==connection.window_id||tab.incognito||win.incognito||win.type!=='normal')throw Error('Tab is outside the selected normal Chrome window.');
 return tab;
}
async function attach(id){
 if(attached.has(id))return;
 await chrome.debugger.attach({tabId:id},'1.3');attached.add(id);
}
async function evaluate(id,expression){
 await attach(id);
 const r=await chrome.debugger.sendCommand({tabId:id},'Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});
 if(r.exceptionDetails)throw Error(r.exceptionDetails.text+' '+(r.exceptionDetails.exception?.description||''));
 return r.result?.value;
}
export async function perform(command){
 const kind=command.kind;
 if(kind==='new_tab'){
  const win=await chrome.windows.get(connection.window_id);if(win.incognito||win.type!=='normal')throw Error('Selected normal window is unavailable.');
  const url=command.url||'about:blank';
  if(url!=='about:blank'&&!jobRoute(url)&&!command.search_entry)throw Error('URL outside job scope.');
  const tab=await chrome.tabs.create({windowId:win.id,url,active:true});owned.add(tab.id);if(command.search_entry)searchTabs.add(tab.id);
  await chrome.storage.session.set({owned:[...owned],searchTabs:[...searchTabs]});
  return {ok:true,tab_id:tab.id,url:tab.url};
 }
 const tab=await tabInWindow(command.tab_id);
 if(kind==='tab_status')return {ok:true,exists:true,url:tab.url};
 if(kind==='close_tab'){
  if(!owned.has(tab.id))throw Error('Existing user tabs cannot be closed by Fan.');
  if(attached.has(tab.id))await chrome.debugger.detach({tabId:tab.id}).catch(()=>{});
  await chrome.tabs.remove(tab.id);owned.delete(tab.id);searchTabs.delete(tab.id);return {ok:true};
 }
 if(kind==='navigate'){
  if(!owned.has(tab.id))throw Error('Fan creates a job tab instead of navigating an existing user tab.');
  if(!jobRoute(command.url)&&!command.search_entry)throw Error('URL outside job scope.');
  if(command.search_entry)searchTabs.add(tab.id);else searchTabs.delete(tab.id);
  await chrome.tabs.update(tab.id,{url:command.url,active:true});await delay(1700);return {ok:true,url:(await tabInWindow(tab.id)).url};
 }
 const google=searchTabs.has(tab.id)&&/^https:\/\/www\.google\.com\/search(?:\?|$)/.test(tab.url||'');
 if(!jobRoute(tab.url)&&!(google&&kind==='observe'))throw Error('Current page is outside public job routes. Authentication stays manual.');
 if(kind==='observe'){
  const observation=await evaluate(tab.id,`(${collect.toString()})()`);
  // Real-time perception acknowledgement. The overlay is excluded from our captures.
  await evaluate(tab.id,`(()=>{document.getElementById('__fanLearning')?.remove();const d=document.createElement('div');d.id='__fanLearning';d.setAttribute('aria-hidden','true');Object.assign(d.style,{position:'fixed',inset:'2px',border:'3px solid #168ce4',pointerEvents:'none',zIndex:2147483647});document.body.append(d);setTimeout(()=>d.remove(),600);return true})()`);
  return {ok:true,observation};
 }
 if(kind==='screenshot'){
  await evaluate(tab.id,"document.getElementById('__fanHighlight')?.remove();document.getElementById('__fanLearning')?.remove();true");
  const metrics=await chrome.debugger.sendCommand({tabId:tab.id},'Page.getLayoutMetrics');
  const bounds=metrics.cssContentSize||metrics.contentSize;
  if(bounds.width*bounds.height>25e6)throw Error('Full-page capture is too large; use native viewport capture.');
  const capture=await chrome.debugger.sendCommand({tabId:tab.id},'Page.captureScreenshot',{format:'png',captureBeyondViewport:true,clip:{x:0,y:0,width:bounds.width,height:bounds.height,scale:1}});
  return {ok:true,png_base64:capture.data};
 }
 if(!['click','fill','upload','highlight'].includes(kind))throw Error('Unsupported command.');
 if(kind==='fill'&&['input','textarea'].includes(command.field.tag)&&!['checkbox','radio','file','hidden'].includes(command.field.type)){
  await evaluate(tab.id,`(()=>{const collect=${collect.toString()};const prepare=${prepareText.toString()};return prepare(${JSON.stringify(command)})})()`);
  await chrome.debugger.sendCommand({tabId:tab.id},'Input.insertText',{text:String(command.answer)});
  if(command.field.role==='combobox'){
   await chrome.debugger.sendCommand({tabId:tab.id},'Input.dispatchKeyEvent',{type:'keyDown',key:'ArrowDown',code:'ArrowDown',windowsVirtualKeyCode:40,nativeVirtualKeyCode:40});
   await chrome.debugger.sendCommand({tabId:tab.id},'Input.dispatchKeyEvent',{type:'keyUp',key:'ArrowDown',code:'ArrowDown',windowsVirtualKeyCode:40,nativeVirtualKeyCode:40});
  }
  command={...command,prepared_text:true};
 }
 // act uses the same bundled collector in the page; neither function is supplied by a model.
 return evaluate(tab.id,`(async()=>{const collect=${collect.toString()};const action=${act.toString()};return await action(${JSON.stringify(command)})})()`);
}
async function poll(){
 if(!connection||busy)return;busy=true;
 try{
  const wire=await request('next');
  if(wire.command){let result;try{result=await perform(wire.command);}catch(error){result={ok:false,error:error.message};}
   await request('result',{method:'POST',body:JSON.stringify({id:wire.id,result})});
  }
 }catch(error){await chrome.storage.local.set({lastError:error.message});}
 finally{busy=false;if(connection)setTimeout(poll,700);}
}
chrome.runtime.onMessage.addListener((message,sender,reply)=>{
 if(sender.id!==chrome.runtime.id)return;
 (async()=>{
  if(message.kind==='paired'){
   connection=message.connection;await chrome.storage.local.set({connection,lastError:''});
   try{await attach(connection.tab_id);}catch(error){await request('disconnect',{method:'POST'}).catch(()=>{});connection=null;await chrome.storage.local.remove('connection');throw error;}
   poll();return {ok:true};
  }
  if(message.kind==='disconnect'){
   if(connection)await request('disconnect',{method:'POST'}).catch(()=>{});
   connection=null;await chrome.storage.local.remove('connection');
   for(const id of attached)await chrome.debugger.detach({tabId:id}).catch(()=>{});attached.clear();return {ok:true};
  }
  throw Error('Unsupported popup operation');
 })().then(reply,error=>reply({ok:false,error:error.message}));return true;
});
chrome.debugger.onDetach.addListener((source,reason)=>{
 attached.delete(source.tabId);
 if(reason==='canceled_by_user'){
  if(connection)request('disconnect',{method:'POST'}).catch(()=>{});
  connection=null;chrome.storage.local.remove('connection');
  chrome.storage.local.set({lastError:'Debugger canceled; reconnect from the extension popup.'});
 }
});
chrome.alarms.create('fanPoll',{periodInMinutes:0.5});chrome.alarms.onAlarm.addListener(()=>poll());
Promise.all([chrome.storage.local.get('connection'),chrome.storage.session.get(['owned','searchTabs'])]).then(([value,tabs])=>{
 connection=value.connection||null;for(const id of tabs.owned||[])owned.add(id);for(const id of tabs.searchTabs||[])searchTabs.add(id);if(connection)poll();
});
