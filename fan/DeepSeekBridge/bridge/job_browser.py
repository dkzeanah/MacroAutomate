"""Retained DOM evidence and bounded job-form operations.

The production runner must use the user's selected existing Chrome window.
The Playwright class below is restricted to explicitly provided test profiles.
"""
from __future__ import annotations
import hashlib
import json
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit
from .common import ROOT
from . import library, page_learner

PROFILE = ROOT / '.runtime' / 'job-browser-profile'
CAPTURES = ROOT / '.runtime' / 'captures' / 'applications'

# Fixed collector; each token refers to the actual node, never a guessed selector.
COLLECT = r'''() => {
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
}'''


def allowed(url, config):
    from .job_sharing import job_route
    p = urlsplit(url)
    host = p.hostname or ''
    return (p.scheme == 'https' and not p.username and not p.password
        and any(host == s or host.endswith('.'+s) for s in config['sites'])
        and job_route(host, p.path))


class JobBrowser:
    def __init__(self, *, headless=False, profile=None):
        if profile is None:
            raise ValueError('Separate Chrome sessions are disabled. Connect the selected existing normal Chrome window.')
        from playwright.sync_api import sync_playwright
        self.driver = sync_playwright().start()
        self.context = self.driver.chromium.launch_persistent_context(
            str(profile), channel='chrome', headless=headless,
            no_viewport=True, locale='en-US', accept_downloads=False,
            args=['--no-first-run', '--no-default-browser-check'])
        self.context.set_default_timeout(8000)
        self.page = self.context.pages[0] if self.context.pages else self.context.new_page()
        self.held_pages = set()
        self.job_pages = {}

    def close(self):
        self.context.close()
        self.driver.stop()

    def navigate(self, url, config):
        if not allowed(url, config):
            raise ValueError('Application URL is outside selected public job routes')
        if self.page in self.held_pages:
            if len(self.context.pages)>=20:
                raise ValueError('Twenty application tabs are retained; review or close completed tabs before continuing')
            self.page=self.context.new_page()
        self.page.goto(url, wait_until='domcontentloaded', timeout=45000)
        self.page.wait_for_timeout(1800)
        self.check_origin(config)

    def check_origin(self, config):
        if not allowed(self.page.url, config):
            raise ValueError('Redirect left the configured public job routes; user action required')

    def observe(self, *, retain=True):
        value = self.page.evaluate(COLLECT)
        if retain:
            value['page_id'] = remember(self.page, value)
        return value

    def node(self, element_id, expected=None):
        handle = self.page.evaluate_handle('(id)=>window.__fanNodes?.get(id)||null', element_id).as_element()
        if handle is None or not handle.evaluate('(e)=>e.isConnected'):
            raise ValueError('Observed element is stale; observe the current form again')
        if expected:
            current=next((e for e in self.page.evaluate(COLLECT)['elements'] if e['element_id']==element_id),None)
            if not current or current['protected'] or not current['enabled'] or any(current[k]!=expected[k] for k in ('name','role','type')):
                raise ValueError('Live element identity or protection changed before input')
        return handle

    def highlight(self, node, caption):
        # Highlight the inspected DOM node in real time, without intercepting input.
        node.evaluate('''(e,label)=>{e.scrollIntoView({block:'center'});document.getElementById('__fanHighlight')?.remove();
          const r=e.getBoundingClientRect(),d=document.createElement('div');d.id='__fanHighlight';
          Object.assign(d.style,{position:'fixed',left:r.x+'px',top:r.y+'px',width:r.width+'px',height:r.height+'px',border:'3px solid #ff2020',
          pointerEvents:'none',zIndex:2147483647,boxSizing:'border-box'});d.setAttribute('aria-hidden','true');d.title=label;document.body.append(d);
          setTimeout(()=>d.remove(),1500)}''', caption)

    def fill(self, field, answer, config):
        self.check_origin(config)
        if field.get('protected') or not field.get('enabled'):
            raise ValueError('Protected or disabled field requires user action')
        node = self.node(field['element_id'],field)
        self.highlight(node, field['name'])
        if field['tag'] == 'select':
            options = [o for o in field['options'] if o['label'].strip().casefold() == str(answer).casefold() and not o['disabled']]
            if len(options) != 1:
                raise ValueError('Saved answer does not uniquely match an observed option: '+field['name'])
            node.select_option(value=options[0]['value'])
        elif field['role'] == 'combobox':
            node.click()
            if field['tag'] == 'input':
                node.fill(str(answer))
            self.page.wait_for_timeout(800)
            options = self.page.get_by_role('option', name=str(answer), exact=True)
            if options.count() != 1:
                candidates=self.page.get_by_role('option')
                def comparable(value):
                    value=re.sub(r'\+\d+', '', value.casefold())
                    value=re.sub(r'\bunited states(?: of america)?\b', '', value) if 'location' in field['name'].casefold() else value
                    value=re.sub(r'\balabama\b','al',value)
                    return re.sub(r'[^a-z0-9]+',' ',value).strip()
                matches=[candidates.nth(i) for i in range(candidates.count()) if comparable(candidates.nth(i).inner_text())==comparable(str(answer))]
                if len(matches)!=1:
                    raise ValueError('Custom dropdown has no unique matching option: '+field['name'])
                matches[0].click()
            else:
                options.click()
        elif field['type'] in ('checkbox', 'radio'):
            if not isinstance(answer, bool):
                raise ValueError('Checkbox/radio requires a specifically saved boolean answer')
            node.set_checked(answer)
        elif field['tag'] in ('input', 'textarea'):
            node.fill(str(answer))
        else:
            raise ValueError('Unsupported field requires user action: '+field['name'])

    def upload(self, field, config):
        self.check_origin(config)
        path = Path(config['resume_path']).resolve()
        if not path.is_file() or path.suffix.lower() != '.pdf' or path.stat().st_size > 20*1024*1024:
            raise ValueError('Selected resume must be an existing PDF under 20 MiB')
        if not re.search(r'resume|résumé|\bcv\b', field['name'], re.I):
            raise ValueError('File field is not an observed resume/CV upload')
        node = self.node(field['element_id'],field)
        self.highlight(node, 'Uploading selected resume')
        node.set_input_files(str(path))
        if node.evaluate('(e)=>e.files?.[0]?.name') != path.name:
            raise ValueError('Resume selection could not be verified')
        return {'filename': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def schema_identity(observation):
    """Form questions/options identify a state; feed copy/counters do not."""
    fields=[]
    for e in observation['elements']:
        form_control=e.get('action_hint') in ('type','select','upload')
        step_control=bool(re.fullmatch(r'apply(?: now| for this job)?|submit(?: application)?|send application|next|continue|review application',e.get('name','').strip(),re.I))
        navigation=e.get('group') in ('header','nav') and e.get('tag')=='a'
        if not (form_control or step_control or navigation):continue
        name=e.get('name','')
        if navigation:
            name=re.sub(r'\d+ new notifications?', '',name,flags=re.I).strip(' ,')
        fields.append((name,e.get('role'),e.get('type'),e.get('required'),bool(e.get('protected')),
            page_learner.canonical_url(e['href']) if navigation and e.get('href') else '',e.get('options',[])))
    encoded=sorted({json.dumps(f,ensure_ascii=False,sort_keys=True) for f in fields})
    return hashlib.sha256(('schema-v2\n'+page_learner.canonical_url(observation['url'])+'\n'+json.dumps(encoded)).encode()).hexdigest()


def remember(page, observation):
    """Reuse descriptions/capture for unchanged schemas; current nodes are always fresh."""
    key = schema_identity(observation)
    with library.connect() as db:
        db.execute('CREATE TABLE IF NOT EXISTS browser_page (page_id TEXT PRIMARY KEY,url TEXT,schema_key TEXT UNIQUE,evidence TEXT,capture_path TEXT,updated_at REAL)')
        if 'image_blob' not in {r[1] for r in db.execute('PRAGMA table_info(browser_page)')}:
            db.execute('ALTER TABLE browser_page ADD COLUMN image_blob BLOB')
        row = db.execute('SELECT page_id FROM browser_page WHERE schema_key=?', (key,)).fetchone()
        if row:
            return row[0]
        page_id = 'chrome-'+key[:24]
        CAPTURES.mkdir(parents=True, exist_ok=True)
        image = CAPTURES / (page_id+'.png')
        page.evaluate("document.getElementById('__fanHighlight')?.remove()")
        page.screenshot(path=str(image), full_page=True, timeout=20000)
        import struct
        width,height=struct.unpack('!II',image.read_bytes()[16:24])
        # Retain labels/geometry, not applicant values or password contents.
        evidence = {**observation, 'elements': [{k:v for k,v in e.items() if k!='value'} for e in observation['elements']]}
        evidence['image_geometry']={'x':0,'y':0,'w':width,'h':height}
        db.execute('INSERT INTO browser_page(page_id,url,schema_key,evidence,capture_path,updated_at,image_blob) VALUES(?,?,?,?,?,?,?)',
            (page_id, observation['url'], key, json.dumps(evidence, ensure_ascii=False), str(image), time.time(),image.read_bytes()))
    return page_id


def retained(page_id):
    with library.connect() as db:
        if not db.execute("SELECT 1 FROM sqlite_master WHERE name='browser_page'").fetchone():
            raise ValueError('Owned Chrome page map not found')
        row=db.execute('SELECT * FROM browser_page WHERE page_id=?',(page_id,)).fetchone()
    if not row:raise ValueError('Owned Chrome page map not found')
    path=Path(row['capture_path']).resolve()
    if not path.is_relative_to(CAPTURES.resolve()):raise ValueError('Page capture path is outside the owned screenshot directory')
    if not path.exists() and 'image_blob' in row.keys() and row['image_blob']:
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(row['image_blob'])
    value=json.loads(row['evidence']);groups={}
    if not value.get('image_geometry'):
        import struct
        width,height=struct.unpack('!II',Path(row['capture_path']).read_bytes()[16:24])
        value['image_geometry']={'x':0,'y':0,'w':width,'h':height}
    for e in value['elements']:
        group=groups.setdefault(e['group'],{'group_id':e['group'],'label':e['group'],'count':0,'source':'observed_DOM_container'})
        group['count']+=1
    return {**value,'ok':True,'page_id':page_id,'element_count':len(value['elements']),'groups':list(groups.values()),
        'frame':{'region':value.get('image_geometry',{}),'coordinates':'css_document_image_with_separate_css_viewport_control_bounds','capture_source':'Chrome_DOM_full_page',
                 'captured_at_utc':datetime.fromtimestamp(row['updated_at'],timezone.utc).isoformat()},
        'coverage':{'saved_crops':0,'findtext_candidates':0,'accessibility_truncated':len(value['elements'])>=2500,'method':'DOM and full-page image'},
        'capture_path':row['capture_path'],'reused':True,'capture_performed':False,
        'limitation':'DOM element bounds are historical CSS viewport coordinates. The full-page image uses document coordinates. Only fresh owned-browser nodes may receive input.'}


def answer_for(field, config):
    from .job_applications import normalize_label
    label = normalize_label(field['name'])
    answers = {normalize_label(k):v for k,v in config.get('answers', {}).items()}
    if label in answers:
        return answers[label]
    aliases = {'first name':'first_name','last name':'last_name','full name':'full_name','name':'full_name',
        'email':'email','email address':'email','phone':'phone','phone number':'phone',
        'linkedin profile':'linkedin_url','linkedin':'linkedin_url','website':'portfolio_url',
        'portfolio':'portfolio_url','city':'city',
        'country':'country','country code':'phone_country'}
    if label == 'location (city)':
        return ', '.join(config['profile'].get(k,'') for k in ('city','state','country'))
    return config['profile'].get(aliases.get(label, ''))


def barrier(observation):
    text = observation['text']
    if any(e['protected'] and e['visible'] for e in observation['elements']):
        return 'Authentication or protected field requires user action'
    if re.search(r'verify (?:you are|you.re) human|security verification|access denied|unusual traffic|complete the captcha', text, re.I):
        return 'Site verification requires user action'
    if re.search(r'verification code was sent|enter the .{0,25}code to confirm|security code',text,re.I):
        return 'Email/security-code verification requires user action in Chrome'
    return ''


def receipt(observation):
    # A receipt must stand alone after the application form has disappeared.
    if any(e['visible'] and e['action_hint'] in ('type','select','upload') for e in observation['elements']):
        return False
    return bool(re.search(r'(?:your application (?:has been (?:submitted|received)|was submitted)|thank you for (?:applying|your application)|application submitted successfully)', observation['text'], re.I))


def candidate_from_observation(observation):
    """Job-detail evidence, never a model's unsupported salary/location assertion."""
    text=observation['text']
    criteria={'evidence_url':observation['url']}
    salary=re.search(r'(?:annual[^\n$]{0,120}(?:salary|compensation)|(?:base )?salary(?: range)?)\s*(?:[:\n]|[^\n$]{0,80}\b(?:is|of))\s*\$([\d,]+)(?:\s*[-–]\s*\$?([\d,]+))?',text,re.I)
    if salary:
        criteria.update(annual_salary_min=int(salary[1].replace(',','')),annual_salary_max=int((salary[2] or salary[1]).replace(',','')))
    location=re.search(r'\bLocation:\s*([^\n]+)',text,re.I)
    if location:
        criteria['location']=location[1].strip()
        criteria['remote']=bool(re.search(r'\bremote\b',location[1],re.I))
    us_remote=re.search(r'(?m)^(?:Full-Time\s*[-–]\s*)?Remote\s*[-–,]\s*(?:US(?: Only)?|USA|United States)\s*$',text,re.I)
    if re.search(r'\bCountry:\s*United States\b',text,re.I) or us_remote:
        criteria['country']='United States'
        if us_remote:criteria['remote']=True
    def postings(value):
        if isinstance(value,list):
            for item in value:yield from postings(item)
        elif isinstance(value,dict):
            if value.get('@type')=='JobPosting':yield value
            yield from postings(value.get('@graph',[]))
    for job in postings(observation.get('job_data',[])):
        base=job.get('baseSalary',{})
        if isinstance(base,dict) and base.get('currency')=='USD':
            val=base.get('value',{})
            if isinstance(val,dict) and val.get('unitText','').upper()=='YEAR':
                criteria['annual_salary_min']=val.get('minValue',val.get('value'))
                criteria['annual_salary_max']=val.get('maxValue',val.get('value'))
        if job.get('jobLocationType')=='TELECOMMUTE':
            criteria['remote']=True
            regions=job.get('applicantLocationRequirements',[])
            if isinstance(regions,dict):regions=[regions]
            if any(r.get('name','').casefold() in ('united states','usa','us') for r in regions):criteria['country']='United States'
        locations=job.get('jobLocation',[])
        if isinstance(locations,dict):locations=[locations]
        if len(locations)==1:
            address=locations[0].get('address',{})
            if isinstance(address,dict):
                city,state=address.get('addressLocality',''),address.get('addressRegion','')
                if city and state:criteria['location']=city+', '+state
                country=address.get('addressCountry','')
                if isinstance(country,dict):country=country.get('name','')
                if country:criteria['country']=country
        if criteria.get('remote') is None and criteria.get('location'):criteria['remote']=False
    return {'title':observation.get('heading') or observation['title'],'criteria':criteria}


def execute(browser, item, config, *, check, mark_submission):
    """Bounded generic form adapter. Unknown answers/barriers stop this job only."""
    from .job_applications import eligibility
    check()
    browser.navigate(item['job_url'], config)
    observed = browser.observe()
    blocked = barrier(observed)
    if blocked:
        return {'state':'needs_attention','reason':blocked,'page_id':observed['page_id']}
    match = eligibility(candidate_from_observation(observed), config)
    if match['status'] != 'matched':
        return {'state':'skipped' if match['status']=='ineligible' else 'needs_attention',
                'reason':'; '.join(match['reasons']) if match['reasons'] else 'Job salary/location needs verified evidence','eligibility':match,'page_id':observed['page_id']}
    # Open a unique observed Apply button if the form is not present yet.
    if not any(e['visible'] and e['action_hint']=='type' for e in observed['elements']):
        buttons = [e for e in observed['elements'] if e['visible'] and e['enabled'] and e['tag']=='button'
                   and re.fullmatch(r'apply(?: now| for this job)?', e['name'].strip(), re.I)]
        if len(buttons)==1:
            check(); browser.node(buttons[0]['element_id'],buttons[0]).click(); browser.page.wait_for_timeout(1000)
    uploaded, filled = None, []
    for step in range(8):
        check(); browser.check_origin(config)
        observed = browser.observe()
        blocked = barrier(observed)
        if blocked:
            return {'state':'needs_attention','reason':blocked,'page_id':observed['page_id'],'filled_fields':filled}
        unresolved = []
        for field in observed['elements']:
            if not field['enabled'] or field['protected']:
                continue
            if field['type']=='file' and re.search(r'resume|résumé|\bcv\b',field['name'],re.I):
                if not uploaded:
                    check(); uploaded=browser.upload(field,config)
                continue
            if not field['visible'] or field['action_hint'] not in ('type','select') or field['type'] in ('hidden','submit','button'):
                continue
            answer=answer_for(field,config)
            if answer is None:
                if field['required'] and not field['value']:
                    unresolved.append(field['name'])
                continue
            if field['value'] == str(answer):
                continue
            check(); browser.fill(field,answer,config); filled.append(field['name'])
        browser.page.wait_for_timeout(900)
        observed=browser.observe()
        invalid=[e['name'] for e in observed['elements'] if e['enabled'] and e['visible'] and
                 (e.get('invalid') or e.get('valid') is False or e['required'] and e['action_hint'] in ('type','select','upload') and not e['value'])]
        if unresolved or invalid:
            return {'state':'needs_attention','reason':'Required fields need answers or validation','unresolved':list(dict.fromkeys(unresolved+invalid)),
                    'page_id':observed['page_id'],'filled_fields':filled,'resume':uploaded}
        controls=[e for e in observed['elements'] if e['visible'] and e['enabled'] and e['tag'] in ('button','input')]
        submit=[e for e in controls if re.fullmatch(r'(?:submit(?: application)?|send application|apply now)',e['name'].strip(),re.I)]
        if len(submit)==1:
            if not uploaded:
                return {'state':'needs_attention','reason':'Selected resume upload has not been verified','page_id':observed['page_id']}
            if config['submission_mode']!='submit_completed':
                return {'state':'prepared','reason':'Completed form ready for review','page_id':observed['page_id'],'filled_fields':filled,'resume':uploaded}
            check(); browser.check_origin(config)
            detail={'page_id':observed['page_id'],'filled_fields':filled,'resume':uploaded,'submitted':False}
            # Durable write BEFORE the potentially irreversible click. Never auto-retry.
            mark_submission(detail)
            try:
                node=browser.node(submit[0]['element_id'],submit[0]); browser.highlight(node,'Submitting completed application'); node.click()
                for _ in range(20):
                    browser.page.wait_for_timeout(500)
                    observed=browser.observe(retain=False)
                    if receipt(observed):
                        return {**detail,'state':'submitted','submitted':True,'receipt_text':observed['text'][:5000],'receipt_url':observed['url']}
                    blocked=barrier(observed)
                    if blocked:
                        return {**detail,'state':'verification_required','reason':blocked,'submitted':False}
                return {**detail,'state':'submission_unknown','reason':'Submission was attempted; no standalone receipt was verified. Do not retry automatically.'}
            except Exception as exc:
                return {**detail,'state':'submission_unknown','reason':'Submission was attempted: '+str(exc)[:500]+'. Do not retry automatically.'}
        next_buttons=[e for e in controls if re.fullmatch(r'next|continue|review application',e['name'].strip(),re.I)]
        if len(next_buttons)!=1:
            return {'state':'needs_attention','reason':'No unique next/submit control; application adapter needs this form state','page_id':observed['page_id'],'filled_fields':filled}
        check(); browser.node(next_buttons[0]['element_id'],next_buttons[0]).click(); browser.page.wait_for_timeout(1000)
    return {'state':'needs_attention','reason':'Application exceeded eight form steps'}
