"""Real Chrome fixture tests: form events, upload, validation and receipt safety."""
import json
import pytest
from bridge import job_browser as browser, job_applications as jobs

URL='https://job-boards.greenhouse.io/synthetic/jobs/123'
HTML='''<html><h1>Software Engineer</h1><p>Location: Remote - US Only<br>Country: United States<br>Salary: $115,000</p>
<form onsubmit="event.preventDefault(); if(this.checkValidity())document.body.innerHTML='<h1>Thank you for applying</h1>'">
<label>First Name<input required name="first_name"></label><label>Email<input required type="email"></label>
<label>US authorization<select required><option value="">Select...</option><option>Yes</option><option>No</option></select></label>
<label>Resume/CV<input type="file" required id="resume"></label><button>Submit application</button></form></html>'''

@pytest.fixture
def owned(tmp_path,monkeypatch):
    monkeypatch.setattr(browser,'CAPTURES',tmp_path/'captures')
    b=browser.JobBrowser(headless=True,profile=tmp_path/'profile')
    b.page.route(URL,lambda route:route.fulfill(body=HTML,content_type='text/html'))
    yield b
    b.close()

def config(tmp_path):
    resume=tmp_path/'synthetic.pdf';resume.write_bytes(b'%PDF-1.4\n%%EOF\n')
    return {'sites':['greenhouse.io'],'roles':['software'],'locations':['Birmingham, AL'],'remote':'any',
      'remote_preferred':True,'minimum_salary':80000,'profile':{'first_name':'Synthetic','email':'synthetic@example.test'},
      'answers':{'US authorization':'Yes'},'resume_path':str(resume),'submission_mode':'submit_completed'}

def test_real_form_upload_submit_receipt_and_retention(owned,tmp_path):
    cfg=config(tmp_path);writes=[]
    result=browser.execute(owned,{'job_url':URL},cfg,check=lambda:None,mark_submission=lambda d:writes.append(d))
    assert result['state']=='submitted' and result['submitted'] and len(writes)==1
    assert result['resume']['filename']=='synthetic.pdf'
    with jobs.library.connect() as db:
        assert db.execute('SELECT COUNT(*) FROM browser_page').fetchone()[0]==1
        evidence=json.loads(db.execute('SELECT evidence FROM browser_page').fetchone()[0])
        assert all('value' not in e for e in evidence['elements'])
    stored=jobs.page_learner.get(result['page_id'])
    assert stored['frame']['coordinates'].startswith('css_document')
    capture=__import__('pathlib').Path(stored['capture_path']);capture.unlink()
    assert jobs.page_learner.get(result['page_id']) and capture.is_file()
    assert any(p['page_id']==result['page_id'] for p in jobs.page_learner.list_pages()['pages'])

def test_unknown_required_answer_never_submits(owned,tmp_path):
    cfg=config(tmp_path);cfg['answers']={};writes=[]
    result=browser.execute(owned,{'job_url':URL},cfg,check=lambda:None,mark_submission=lambda d:writes.append(d))
    assert result['state']=='needs_attention' and 'US authorization' in result['unresolved'] and not writes

def test_receipt_prose_in_unsubmitted_form_is_not_success():
    assert not browser.receipt({'text':'Thank you for applying','elements':[{'visible':True,'action_hint':'type'}]})
    assert not browser.receipt({'text':'Please submit your application','elements':[]})

def test_submission_recovery_is_never_requeued():
    jobs.save_configuration({'sites':['greenhouse.io'],'roles':['software']})
    queued=jobs.enqueue({'url':URL});run=jobs.start();item=jobs.claim()
    jobs.submission_started(item,{'submitted':False});jobs.recover()
    assert jobs.status()['counts']=={'submission_unknown':1}
    assert jobs.claim() is None

def test_origin_and_fresh_salary_evidence():
    assert not browser.allowed('https://job-boards.greenhouse.io/users/password',{'sites':['greenhouse.io']})
    observed={'url':URL,'title':'Software Engineer','heading':'Software Engineer',
       'text':'Location: Remote - US Only\nCountry: United States\nSalary: $70,000','job_data':[]}
    candidate=browser.candidate_from_observation(observed)
    assert jobs.eligibility(candidate,{'roles':['software'],'locations':[],'remote':'any','minimum_salary':80000})['status']=='ineligible'

def test_changed_field_identity_refuses_input(owned,tmp_path):
    cfg=config(tmp_path);owned.navigate(URL,cfg)
    field=next(e for e in owned.observe()['elements'] if e['name']=='First Name')
    owned.node(field['element_id']).evaluate("e=>e.type='password'")
    with pytest.raises(ValueError,match='identity or protection'):
        owned.fill(field,'Synthetic',cfg)

def test_discovery_is_bounded_deduplicated_and_retains_cursor(owned,tmp_path,monkeypatch):
    cfg=config(tmp_path);jobs.save_configuration(cfg)
    run=jobs.start()
    search='https://www.google.com/search?q=synthetic'
    owned.context.route(search,lambda route:route.fulfill(body=f'<a href="{URL}">Software Engineer</a><a href="{URL}">duplicate</a><a href="https://evil.test/jobs/123">unselected</a>',content_type='text/html'))
    monkeypatch.setattr(jobs,'searches',lambda:{'searches':[{'url':search,'site':'greenhouse.io','role':'software','location':'Remote'}]})
    assert jobs.discover_one(owned,run['run_id'])
    assert jobs.status()['counts']=={'queued':1}
    assert not jobs.discover_one(owned,run['run_id'])

def test_email_code_is_a_human_barrier():
    assert browser.barrier({'text':'A verification code was sent to your email. Security code','elements':[]})

def test_annual_salary_prose_and_explicit_us_remote_are_observed():
    observation={'url':URL,'title':'Software Engineer','heading':'Software Engineer','job_data':[],
        'text':'Software Engineer\nRemote - US\nThe annual anticipated U.S. base salary range for this full-time position is $141,000-$185,000.'}
    candidate=browser.candidate_from_observation(observation)
    assert candidate['criteria']['annual_salary_min']==141000
    assert candidate['criteria']['annual_salary_max']==185000
    assert candidate['criteria']['remote'] and candidate['criteria']['country']=='United States'

def test_production_does_not_launch_a_separate_chrome_profile():
    with pytest.raises(ValueError,match='Separate Chrome sessions are disabled'):
        browser.JobBrowser()
    assert not jobs.browser_ready()

def test_retained_schema_ignores_feed_copy_but_detects_new_required_questions():
    field={'name':'Search','role':'input','type':'text','required':False,'action_hint':'type','options':[]}
    read={'name':'Initial feed text','role':'p','type':'','required':False,'action_hint':'read','options':[]}
    observation={'url':'https://linkedin.com/feed/','elements':[field,read]}
    changed={'url':observation['url'],'elements':[field,{**read,'name':'A newly loaded post'},{**read,'role':'a','name':'Feed hyperlink','href':'https://example.test/post'}]}
    assert browser.schema_identity(observation)==browser.schema_identity(changed)
    changed['elements'].append({**field,'name':'Work authorization','required':True})
    assert browser.schema_identity(observation)!=browser.schema_identity(changed)
