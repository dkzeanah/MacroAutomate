"""Normal-window connector authorization, narrow commands and browser-side fences."""
import base64
import json
import subprocess
from pathlib import Path
import pytest
from fastapi.testclient import TestClient
from bridge import gateway,chrome_connector as connector,job_applications as jobs,catalog
from bridge.job_browser import JobBrowser,COLLECT

HEADERS={'X-Bridge-Token':'test-local-token'}
URL='https://job-boards.greenhouse.io/synthetic/jobs/123'
EXT=Path(__file__).resolve().parents[1]/'chrome-extension'

@pytest.mark.parametrize('value,valid,accepted',[
    ('(205) 799-1734',True,True),('205-799-1735',True,False),
    ('(205) 799-1734',False,False),('2057991734 ext 9',True,False)])
def test_existing_adapter_verifies_formatted_phone_without_retry(monkeypatch,value,valid,accepted):
    from bridge import existing_chrome as adapter
    b=adapter.ExistingChromeBrowser.__new__(adapter.ExistingChromeBrowser)
    field={'element_id':'dom-8','name':'Phone','role':'input','type':'tel'}
    class Page:
        tab_id=12
        def evaluate(self,source):
            assert source==COLLECT
            return {'elements':[{**field,'value':value,'valid':valid,'invalid':False,'enabled':True,'protected':False}]}
    b.page=Page();b.check_origin=lambda cfg:None
    calls=[]
    def failed(command):
        calls.append(command)
        raise ValueError('Saved text value was not confirmed.')
    monkeypatch.setattr(adapter,'rpc',failed)
    if accepted:
        assert b.fill(field,'2057991734',{})['formatted_value_verified']
    else:
        with pytest.raises(ValueError):b.fill(field,'2057991734',{})
    assert len(calls)==1  # Verification never retries input.

def config(tmp_path):
    path=tmp_path/'selected.pdf';path.write_bytes(b'%PDF-1.4\n%%EOF\n')
    jobs.save_configuration({'sites':['greenhouse.io'],'roles':['software'],
        'resume_path':str(path),'profile':{'email':'synthetic@example.test'},'answers':{}})

def test_pairing_rejects_incognito_private_pages_and_replay(tmp_path):
    config(tmp_path)
    code=connector.pairing()['pair_code'].split('.')[1]
    args={'code':code,'window_id':11,'tab_id':12,'incognito':False,'url':URL}
    with TestClient(gateway.app) as client:
        assert client.post('/chrome/pair',json={**args,'incognito':True}).status_code==422
        assert client.post('/chrome/pair',json={**args,'url':'https://linkedin.com/messaging'}).status_code==422
        response=client.post('/chrome/pair',json=args)
        assert response.status_code==200
        key=response.json()['token']
        assert client.post('/chrome/pair',json=args).status_code==401
        assert client.get('/chrome/next',headers={'X-Chrome-Token':key}).json()=={'command':None}
        assert client.get('/health',headers={'X-Bridge-Token':key}).status_code==401
        assert client.post('/chrome/command',headers={**HEADERS,'X-Bridge-Task':'readonly'},json={'kind':'observe','tab_id':12}).status_code==403
        assert client.post('/chrome/disconnect',headers={'X-Chrome-Token':key}).status_code==200
        assert not connector.status()['connected']
    assert not {'fan_job_chrome_pair','fan_job_chrome_status'} & {f['function']['name'] for f in catalog.functions()}

def test_commands_are_fixed_and_upload_uses_only_selected_pdf(tmp_path):
    config(tmp_path)
    field={'element_id':'dom-7','name':'Resume/CV','role':'input','type':'file','protected':False,'enabled':True}
    value=connector.validate({'kind':'upload','tab_id':12,'field':field})
    assert value['filename']=='selected.pdf' and base64.b64decode(value['pdf_base64']).startswith(b'%PDF-')
    with pytest.raises(ValueError,match='extra command'):
        connector.validate({'kind':'upload','tab_id':12,'field':field,'file_path':'C:/private.pdf'})
    with pytest.raises(ValueError,match='outside configured'):
        connector.validate({'kind':'navigate','tab_id':12,'url':'https://linkedin.com/messaging'})
    assert connector.validate({'kind':'new_tab','url':'https://www.linkedin.com/feed/'})
    with pytest.raises(ValueError,match='navigation/submission'):
        connector.validate({'kind':'click','tab_id':12,'field':{**field,'name':'Delete account'}})
    email={**field,'name':'Email','type':'text'}
    assert connector.validate({'kind':'fill','tab_id':12,'field':email,'answer':'synthetic@example.test'})
    with pytest.raises(ValueError,match='saved applicant answer'):
        connector.validate({'kind':'fill','tab_id':12,'field':email,'answer':'invented@example.test'})

def test_extension_window_and_route_checks_before_debugger(tmp_path):
    script=tmp_path/'fences.mjs'
    script.write_text('''import assert from 'node:assert/strict';
let runtimeCalls=0,tab={id:12,windowId:11,incognito:false,url:'https://linkedin.com/feed/'};
globalThis.setTimeout=()=>0;
globalThis.fetch=async()=>({ok:true,json:async()=>({command:null})});
globalThis.chrome={storage:{local:{get:async()=>({connection:{window_id:11,tab_id:12,port:8767,token:'synthetic',sites:['linkedin.com']}}),set:async()=>{},remove:async()=>{}},session:{get:async()=>({}),set:async()=>{}}},
tabs:{get:async()=>tab},windows:{get:async()=>({incognito:false,type:'normal'})},
debugger:{attach:async()=>{runtimeCalls++},sendCommand:async()=>{runtimeCalls++;return {result:{value:{}}}},onDetach:{addListener:()=>{}}},
runtime:{id:'synthetic',onMessage:{addListener:()=>{}}},alarms:{create:()=>{},onAlarm:{addListener:()=>{}}}};
const {perform,jobRoute}=await import('''+json.dumps((EXT/'background.js').as_uri())+''');
await new Promise(resolve=>setImmediate(resolve));
assert(jobRoute('https://linkedin.com/jobs/view/123'));
assert(!jobRoute('https://linkedin.com/messaging'));
tab={...tab,windowId:22};await assert.rejects(perform({kind:'observe',tab_id:12}),/selected normal/);
tab={...tab,windowId:11,incognito:true};await assert.rejects(perform({kind:'observe',tab_id:12}),/selected normal/);
tab={...tab,incognito:false,url:'https://linkedin.com/messaging'};await assert.rejects(perform({kind:'observe',tab_id:12}),/outside public job/);
await assert.rejects(perform({kind:'navigate',tab_id:12,url:'https://linkedin.com/jobs'}),/existing user tab/);
assert.equal(runtimeCalls,0);console.log('Window/privacy fences passed');
''',encoding='utf-8')
    result=subprocess.run(['node',str(script)],capture_output=True,text=True,timeout=15)
    assert result.returncode==0,result.stderr

def test_bundled_page_actions_fill_upload_and_receipt_in_real_chrome(tmp_path):
    b=JobBrowser(headless=True,profile=tmp_path/'fixture-profile')
    html='''<h1>Software Engineer</h1><form onsubmit="event.preventDefault();document.body.innerHTML='Thank you for applying'">
    <label>Email<input type=email required></label><label>Resume/CV<input id=resume type=file required></label><button>Submit application</button></form>'''
    b.page.route(URL,lambda r:r.fulfill(body=html,content_type='text/html'))
    try:
        b.page.goto(URL)
        collector=(EXT/'collector.js').read_text(encoding='utf-8').replace('export function collect','function collect',1)
        action=(EXT/'page-actions.js').read_text(encoding='utf-8').replace("import {collect} from './collector.js';",'').replace('export async function act','async function act',1).replace('export function prepareText','function prepareText',1)
        source='('+COLLECT+')()'
        observed=b.page.evaluate(source)
        fields=observed['elements']
        def act(kind,field,**data):
            code='(async()=>{'+collector+'\n'+action+'\nreturn await act('+json.dumps({'kind':kind,'field':field,**data})+');})()'
            return b.page.evaluate(code)
        email=next(e for e in fields if e['name']=='Email' and e['tag']=='input')
        upload=next(e for e in fields if e['type']=='file')
        submit=next(e for e in fields if e['name']=='Submit application')
        assert act('fill',email,answer='synthetic@example.test')['ok']
        assert act('upload',upload,filename='selected.pdf',pdf_base64=base64.b64encode(b'%PDF-1.4\n%%EOF').decode(),sha256='synthetic')['filename']=='selected.pdf'
        assert act('click',submit)['ok']
        assert 'Thank you for applying' in b.page.locator('body').inner_text()
    finally:b.close()

def test_trusted_arrow_opens_custom_dropdown_and_selects_observed_option(tmp_path):
    b=JobBrowser(headless=True,profile=tmp_path/'dropdown-profile')
    html='''<label id="country-label">Country*</label><input aria-labelledby="country-label" role="combobox" id="country" aria-controls="countries">
    <div id="countries" role="listbox" style="display:none"><div role="option">United States +1</div></div>
    <script>country.addEventListener('keydown',e=>{if(e.isTrusted&&e.key==='ArrowDown')countries.style.display='block'});
    document.querySelector('[role=option]').onclick=()=>{country.value='United States';countries.style.display='none'};</script>'''
    b.page.route(URL,lambda r:r.fulfill(body=html,content_type='text/html'))
    try:
        b.page.goto(URL)
        field=next(e for e in b.page.evaluate('('+COLLECT+')()')['elements'] if e['role']=='combobox')
        collector=(EXT/'collector.js').read_text(encoding='utf-8').replace('export function collect','function collect',1)
        action=(EXT/'page-actions.js').read_text(encoding='utf-8').replace("import {collect} from './collector.js';",'').replace('export async function act','async function act',1).replace('export function prepareText','function prepareText',1)
        command={'kind':'fill','field':field,'answer':'United States','prepared_text':True}
        prefix='(async()=>{'+collector+'\n'+action+'\n'
        b.page.evaluate(prefix+'return prepareText('+json.dumps(command)+');})()')
        cdp=b.context.new_cdp_session(b.page)
        cdp.send('Input.insertText',{'text':'United States'})
        cdp.send('Input.dispatchKeyEvent',{'type':'keyDown','key':'ArrowDown','code':'ArrowDown','windowsVirtualKeyCode':40})
        cdp.send('Input.dispatchKeyEvent',{'type':'keyUp','key':'ArrowDown','code':'ArrowDown','windowsVirtualKeyCode':40})
        assert b.page.locator('#countries').is_visible()
        assert b.page.evaluate(prefix+'return await act('+json.dumps(command)+');})()')['ok']
        assert not b.page.locator('#countries').is_visible()
        assert b.page.locator('#country').input_value()=='United States'
    finally:b.close()
