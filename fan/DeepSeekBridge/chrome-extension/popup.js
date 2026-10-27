const status=document.getElementById('status');
document.getElementById('connect').onclick=async()=>{
 try{
  const win=await chrome.windows.getCurrent();
  if(win.incognito||win.type!=='normal')throw Error('Select your existing normal Chrome window.');
  const [tab]=await chrome.tabs.query({active:true,windowId:win.id});
  const code=document.getElementById('code').value.trim();
  if(!/^87\d\d\.[a-f0-9]{32}$/.test(code))throw Error('Copy the current pairing code from Fan.');
  const [port,secret]=code.split('.');
  const response=await fetch(`http://127.0.0.1:${port}/chrome/pair`,{method:'POST',headers:{'Content-Type':'application/json'},
   body:JSON.stringify({code:secret,window_id:win.id,tab_id:tab.id,incognito:win.incognito,url:tab.url})});
  const result=await response.json();if(!response.ok)throw Error(result.detail||'Pairing failed');
  const attached=await chrome.runtime.sendMessage({kind:'paired',connection:{...result,port:Number(port)}});
  if(!attached?.ok)throw Error(attached?.error||'Chrome connection failed');
  status.textContent='Connected to this normal Chrome window. Resume the run in Fan.';document.getElementById('code').value='';
 }catch(error){status.textContent=error.message;}
};
document.getElementById('disconnect').onclick=async()=>{await chrome.runtime.sendMessage({kind:'disconnect'});status.textContent='Disconnected; no more commands accepted.';};
document.getElementById('reload').onclick=()=>chrome.runtime.reload();
