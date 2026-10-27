"""Durable application queue, retained learning and owned Chrome form execution."""
from __future__ import annotations
import argparse
import json
import re
import sqlite3
import time
import uuid
from datetime import datetime, timezone
from urllib.parse import urlsplit, parse_qs, urlencode
from . import library, page_learner


def stamp():
    return datetime.now(timezone.utc).isoformat()


def initialize(db):
    db.execute('CREATE TABLE IF NOT EXISTS application_config (id INTEGER PRIMARY KEY CHECK(id=1), content TEXT NOT NULL)')
    db.execute('CREATE TABLE IF NOT EXISTS application_run ('
        'run_id TEXT PRIMARY KEY, status TEXT NOT NULL, started_at TEXT NOT NULL, deadline REAL NOT NULL, detail TEXT NOT NULL)')
    db.execute('CREATE TABLE IF NOT EXISTS application_queue ('
        'job_id TEXT PRIMARY KEY, job_url TEXT UNIQUE NOT NULL, title TEXT NOT NULL, company TEXT NOT NULL, '
        'status TEXT NOT NULL, run_id TEXT, page_id TEXT, result TEXT NOT NULL, updated_at TEXT NOT NULL)')
    db.execute('CREATE TABLE IF NOT EXISTS application_event ('
        'event_id INTEGER PRIMARY KEY, job_id TEXT, kind TEXT NOT NULL, detail TEXT NOT NULL, at TEXT NOT NULL)')
    if 'criteria' not in {r[1] for r in db.execute('PRAGMA table_info(application_queue)')}:
        db.execute("ALTER TABLE application_queue ADD COLUMN criteria TEXT NOT NULL DEFAULT '{}'")


def event(db, job_id, kind, detail):
    db.execute('INSERT INTO application_event(job_id,kind,detail,at) VALUES(?,?,?,?)', (job_id, kind, detail, stamp()))


def configuration():
    with library.connect() as db:
        initialize(db)
        row = db.execute('SELECT content FROM application_config WHERE id=1').fetchone()
    defaults = {'sites': [], 'roles': [], 'locations': [], 'remote': 'any', 'remote_preferred': False,
        'submission_mode': 'review', 'minimum_salary': 0, 'resume_path': '', 'profile': {}, 'answers': {},
        'browser_execution': False, 'automatic_discovery': False}
    defaults['browser_mode']='existing_chrome'
    return {**defaults, **(json.loads(row[0]) if row else {})}


def save_configuration(args):
    config = {**configuration(), **args}
    sites = [urlsplit(s if '://' in s else 'https://'+s).hostname for s in config['sites']]
    if any(not s or '.' not in s for s in sites) or len(set(sites)) != len(sites):
        raise ValueError('Use distinct website hostnames for the selected job sites')
    config['sites'] = sites
    with library.connect() as db:
        initialize(db)
        db.execute('INSERT OR REPLACE INTO application_config VALUES(1,?)', (json.dumps(config, ensure_ascii=False),))
    return {'ok': True, 'configured_sites': sites, 'ready_for_preview': bool(config['roles']),
            'execution_status': 'Selected existing Chrome form execution enabled.' if config['browser_execution'] else 'Local preparation; Chrome execution disabled.'}


def enqueue(args):
    url = page_learner.canonical_url(args['url'])
    if urlsplit(url).scheme != 'https':
        raise ValueError('Job URLs must use HTTPS')
    sites = configuration()['sites']
    host = urlsplit(url).hostname
    if not sites or not any(host == s or host.endswith('.'+s) for s in sites):
        raise ValueError('Select this job site in the saved configuration first')
    job_id = uuid.uuid4().hex
    with library.connect() as db:
        initialize(db)
        existing = db.execute('SELECT job_id,status FROM application_queue WHERE job_url=?', (url,)).fetchone()
        if existing:
            return {'ok': True, 'job_id': existing[0], 'status': existing[1], 'duplicate': True}
        criteria = {k: args.get(k) for k in ('location', 'remote', 'country', 'annual_salary_min', 'annual_salary_max', 'evidence_url')}
        db.execute('INSERT INTO application_queue(job_id,job_url,title,company,status,run_id,page_id,result,updated_at,criteria) VALUES(?,?,?,?,?,?,?,?,?,?)',
            (job_id, url, args.get('title', ''), args.get('company', ''), 'queued', None, None, '{}', stamp(), json.dumps(criteria)))
        event(db, job_id, 'queued', 'Saved application URL; no browser input performed')
    return {'ok': True, 'job_id': job_id, 'status': 'queued', 'duplicate': False}


def status():
    with library.connect() as db:
        initialize(db)
        runs = [dict(row) for row in db.execute('SELECT * FROM application_run ORDER BY started_at DESC LIMIT 5')]
        counts = {row[0]: row[1] for row in db.execute('SELECT status,COUNT(*) FROM application_queue GROUP BY status')}
        items = [dict(row) for row in db.execute('SELECT job_id,job_url,title,company,status,page_id,updated_at '
                                               'FROM application_queue ORDER BY updated_at DESC LIMIT 100')]
    return {'ok': True, 'runs': runs, 'counts': counts, 'items': items,
        'mode': 'existing_chrome' if configuration()['browser_execution'] else 'local_preparation',
        'submission_enabled': browser_ready() and configuration()['browser_execution'] and configuration()['submission_mode']=='submit_completed',
        'requested_submission_mode': configuration()['submission_mode'],
        'limitation': 'Generic Chrome adapter supports observed labeled inputs, selects, tested custom dropdowns and resume upload. Unknown required answers, authentication, verification codes, CAPTCHA and unsupported controls require user action. Five-site unattended submission coverage is not established.'}


def start(hours=8):
    config = configuration()
    if not config['sites'] or not config['roles']:
        raise ValueError('Save target sites and roles before starting a preparation run')
    run_id = uuid.uuid4().hex
    with library.connect() as db:
        initialize(db)
        db.execute('BEGIN IMMEDIATE')
        active = db.execute("SELECT run_id FROM application_run WHERE status IN ('running','paused')").fetchone()
        if active:
            raise ValueError('A preparation run already exists; pause, resume or stop it')
        db.execute('INSERT INTO application_run VALUES(?,?,?,?,?)',
                   (run_id, 'running', stamp(), time.time()+hours*3600,
                    'Application run in selected existing normal Chrome window' if config['browser_execution'] else 'Local preparation run; no applications are sent'))
    return {'ok': True, 'run_id': run_id, 'status': 'running', 'mode': 'existing_chrome' if config['browser_execution'] else 'local_preparation'}


def control(run_id, action):
    with library.connect() as db:
        initialize(db)
        row = db.execute('SELECT status FROM application_run WHERE run_id=?', (run_id,)).fetchone()
        if not row:
            raise ValueError('Preparation run not found')
        if row[0] in ('stopped', 'complete') and action != 'stop':
            raise ValueError('Finished runs cannot resume; start another run')
        next_state = {'pause': 'paused', 'resume': 'running', 'stop': 'stopped'}[action]
        db.execute('UPDATE application_run SET status=? WHERE run_id=?', (next_state, run_id))
    return {'ok': True, 'run_id': run_id, 'status': next_state}


def claim():
    prefer_remote = configuration()['remote_preferred']
    with library.connect() as db:
        initialize(db)
        db.execute('BEGIN IMMEDIATE')
        db.execute("UPDATE application_run SET status='complete',detail='Run duration ended' WHERE status IN ('running','paused') AND deadline<=?", (time.time(),))
        run = db.execute("SELECT run_id FROM application_run WHERE status='running' ORDER BY started_at LIMIT 1").fetchone()
        if not run:
            return None
        row = db.execute("SELECT * FROM application_queue WHERE status='queued' "
            "ORDER BY CASE WHEN ? AND json_extract(criteria,'$.remote')=1 THEN 0 ELSE 1 END,updated_at LIMIT 1",
            (int(prefer_remote),)).fetchone()
        if not row:
            return None
        item = dict(row)
        db.execute("UPDATE application_queue SET status='preparing',run_id=?,updated_at=? WHERE job_id=?", (run[0], stamp(), item['job_id']))
        item['run_id'] = run[0]
        event(db, item['job_id'], 'claimed', 'Checking retained page and saved answers')
    return item


ALIASES = {'first name': 'first_name', 'last name': 'last_name', 'full name': 'full_name',
    'email': 'email', 'email address': 'email', 'phone': 'phone', 'phone number': 'phone',
    'city': 'city', 'linkedin profile': 'linkedin_url', 'portfolio': 'portfolio_url'}


def all_elements(page_id):
    elements, offset = [], 0
    while True:
        part = page_learner.get(page_id, offset=offset, limit=100)
        elements.extend(part['elements'])
        if not part['has_more']:
            return elements
        offset += 100


def normalize_label(name):
    return re.sub(r'\s+', ' ', re.sub(r'[\s*:]+$', '', name)).strip().casefold()


def role_matches(title, roles):
    title = title.casefold()
    for role in roles:
        role = role.casefold()
        if 'embedded' in role:
            if 'firmware' in title or ('embedded' in title and re.search(r'engineer|developer|programmer|systems?|architect', title)):
                return True
        elif role == 'software' or role in ('software engineering', 'software engineer'):
            if re.search(r'software|\.net|c\+\+|c#|python', title) and re.search(r'engineer|developer|programmer|development|test|architect', title):
                return True
        elif role in title:
            return True
    return False


def eligibility(candidate, config):
    """Conservative matching: missing evidence never proves the salary/location floor."""
    rejected, unknown = [], []
    title = candidate.get('title', '').casefold()
    if not title:
        unknown.append('Job title')
    elif not role_matches(title, config['roles']):
        rejected.append('Job title does not match target roles')
    metadata = candidate.get('criteria', {})
    if isinstance(metadata, str):
        metadata = json.loads(metadata)
    floor = metadata.get('annual_salary_min')
    ceiling = metadata.get('annual_salary_max')
    if config['minimum_salary']:
        if floor is not None and floor >= config['minimum_salary']:
            pass
        elif ceiling is not None and ceiling < config['minimum_salary']:
            rejected.append('Advertised annual salary is below the minimum')
        else:
            unknown.append('Annual salary floor of $'+format(config['minimum_salary'], ','))
    remote, country = metadata.get('remote'), (metadata.get('country') or '').strip().casefold()
    raw_location = re.sub(r'\balabama\b', 'al', (metadata.get('location') or '').casefold())
    raw_location = re.sub(r'\bgeorgia\b', 'ga', raw_location)
    location = re.sub(r'[^a-z0-9]+', ' ', raw_location).strip()
    cities = [re.sub(r'[^a-z0-9]+', ' ', loc.casefold()).strip() for loc in config['locations']]
    # Remote is a preference unless the explicit mode requires it.
    if config['remote'] == 'remote' and remote is False:
        rejected.append('Role is not remote')
    if remote is True:
        if country not in ('us', 'usa', 'united states', 'united states of america'):
            unknown.append('Remote role permits working from the United States')
    elif cities:
        if not location or remote is None:
            unknown.append('Eligible city or US remote work')
        elif not any(location == city or location.startswith(city+' ') for city in cities):
            rejected.append('Location is outside the selected cities')
    return {'status': 'ineligible' if rejected else 'needs_verification' if unknown else 'matched',
            'reasons': rejected, 'unverified': unknown,
            'priority': 0 if config.get('remote_preferred') and remote is True else 1}


def searches():
    config, entries = configuration(), []
    destinations = (['Remote, United States'] if config['remote_preferred'] else []) + config['locations']
    for site in config['sites']:
        for role in config['roles']:
            for location in destinations or ['United States']:
                if site == 'indeed.com':
                    url = 'https://www.indeed.com/jobs?'+urlencode({'q': role, 'l': location})
                    kind = 'job_board_search'
                elif site == 'ziprecruiter.com':
                    url = 'https://www.ziprecruiter.com/jobs-search?'+urlencode({'search': role, 'location': location})
                    kind = 'job_board_search'
                elif site == 'linkedin.com':
                    url = 'https://www.linkedin.com/jobs/search/?'+urlencode({'keywords': role, 'location': location})
                    kind = 'job_board_search'
                else:
                    url = 'https://www.google.com/search?'+urlencode({'q': 'site:'+site+' '+role+' '+location})
                    kind = 'employer_board_discovery'
                entries.append({'site': site, 'role': role, 'location': location, 'url': url, 'kind': kind})
    return {'ok': True, 'searches': entries, 'opened': False,
            'note': 'Search links are entry points. Advertised salary, location and applicant eligibility still require job-detail evidence.'}


def is_job_link(url):
    p, query = urlsplit(url), parse_qs(urlsplit(url).query)
    host, path = p.hostname or '', p.path.casefold()
    if host.endswith('linkedin.com'):
        return bool(re.search(r'/jobs/view/\d+', path))
    if host.endswith('indeed.com'):
        return bool(query.get('jk')) and path.endswith('/viewjob')
    if host.endswith('ziprecruiter.com'):
        return '/jobs/' in path or '/c/' in path and '/job/' in path
    if host.endswith('greenhouse.io'):
        return bool(re.search(r'/jobs/\d+', path))
    if host.endswith('dayforcehcm.com'):
        return bool(re.search(r'/jobs?/\d+', path))
    if host.endswith('ultipro.com'):
        return '/opportunitydetail' in path and bool(query.get('opportunityId') or query.get('opportunityid'))
    return False


def discover(page_id):
    page, found, ignored = page_learner.get(page_id), [], 0
    config = configuration()
    host = urlsplit(page['url']).hostname or ''
    if not any(host == s or host.endswith('.'+s) for s in config['sites']):
        raise ValueError('The retained page is not on a configured job site')
    for e in all_elements(page_id):
        url = e.get('href', '')
        if e.get('scope') != 'page' or not is_job_link(url):
            continue
        try:
            result = enqueue({'url': url, 'title': e.get('name', ''), 'evidence_url': page['url']})
            found.append({**result, 'url': url, 'element_id': e['element_id']})
        except ValueError:
            ignored += 1
    return {'ok': True, 'jobs': found, 'ignored': ignored, 'page_id': page_id,
            'note': 'Only observed job links were queued. No salary, company or location was inferred from nearby unrelated page text.'}


def plan(page, config):
    planned, unresolved = [], []
    elements = all_elements(page['page_id'])
    for e in elements:
        if e.get('scope') != 'page' or e.get('kind') != 'accessibility':
            continue
        if e.get('protected') and re.search(r'edit|text field|combo', e.get('role', ''), re.I):
            unresolved.append({'element_id': e['element_id'], 'question': e.get('name', ''),
                               'reason': 'Protected field requires user action; no automated authentication'})
            continue
        if e.get('action_hint') not in ('type', 'select'):
            continue
        name = e.get('name', '').strip()
        answer = config.get('answers', {}).get(name)
        if answer is None:
            answer = config.get('profile', {}).get(ALIASES.get(normalize_label(name), ''))
        if e.get('protected') or not e.get('enabled', True) or answer is None:
            unresolved.append({'element_id': e['element_id'], 'question': name, 'reason': 'Protected/disabled or no saved answer'})
        else:
            planned.append({'element_id': e['element_id'], 'question': name, 'answer': answer,
                            'requires_live_resolution': True})
    return {'page_id': page['page_id'], 'saved_answer_plan': planned, 'unresolved_fields': unresolved,
            'inputs_performed': False, 'submitted': False, 'requires_application_adapter': True}


def finish(item, state, result):
    with library.connect() as db:
        initialize(db)
        db.execute('UPDATE application_queue SET status=?,page_id=?,result=?,updated_at=? WHERE job_id=?',
            (state, result.get('page_id'), json.dumps(result, ensure_ascii=False), stamp(), item['job_id']))
        event(db, item['job_id'], state, result.get('reason', 'Local preparation finished; no input performed'))


def check_running(run_id):
    with library.connect() as db:
        row=db.execute('SELECT status,deadline FROM application_run WHERE run_id=?',(run_id,)).fetchone()
    if not row or row[0]!='running' or row[1]<=time.time():
        raise RuntimeError('Application run paused, stopped or expired')


def submission_started(item, detail):
    with library.connect() as db:
        db.execute("UPDATE application_queue SET status='submitting',result=?,updated_at=? WHERE job_id=?",(json.dumps(detail),stamp(),item['job_id']))
        event(db,item['job_id'],'submission_started','Completed form submission attempted; await receipt; never auto-retry')


def browser_ready():
    try:
        from .chrome_connector import status as chrome_status
        return chrome_status()['connected']
    except ImportError:
        return False


def connect_browser(config):
    if config.get('browser_mode')!='existing_chrome':
        raise ValueError('Use the existing normal Chrome window; separate browser sessions are disabled')
    try:
        from .existing_chrome import ExistingChromeBrowser
    except ImportError:
        raise ValueError('Existing Chrome connector approval/setup is required; no separate session will launch') from None
    return ExistingChromeBrowser()


def process_one(observe=None, browser=None):
    try:
        item = claim()
    except sqlite3.OperationalError as exc:
        if 'locked' not in str(exc).lower() and 'busy' not in str(exc).lower():
            raise
        # Claiming is transactional and precedes every browser/input action.
        # Leave the queue untouched and retry on the next idle tick.
        return False
    if not item:
        return False
    config = configuration()
    try:
        if config['browser_execution']:
            from .job_browser import execute
            owned=browser is None
            browser=browser or connect_browser(config)
            try:
                result=execute(browser,item,config,check=lambda:check_running(item['run_id']),
                    mark_submission=lambda detail:submission_started(item,detail))
                state=result.pop('state')
                finish(item,state,result)
                if state in ('verification_required','submission_unknown','prepared'):
                    browser.held_pages.add(browser.page)
                    browser.job_pages[browser.page]=item
            finally:
                if owned:browser.close()
            return True
        match = eligibility(item, config)
        if match['status'] == 'ineligible':
            finish(item, 'skipped', {'reason': '; '.join(match['reasons']), 'eligibility': match})
            return True
        # Preparation uses retained evidence without touching another browser tab.
        # Actual navigation/filling/submission require tested application adapters.
        page = page_learner.reuse(observe(item)) if observe else page_learner.remembered_url(item['job_url'])
        if not page:
            finish(item, 'needs_attention', {'reason': 'Learn this application page once; site application adapter is pending'})
            return True
        if not page.get('ok'):
            raise ValueError(page.get('error', 'Page could not be learned'))
        prepared = plan(page, config)
        prepared['eligibility'] = match
        prepared['requested_submission_mode'] = config['submission_mode']
        prepared['criteria_pending_verification'] = match['unverified'] + ['resume upload', 'tested application adapter']
        finish(item, 'prepared', prepared)
    except Exception as exc:
        with library.connect() as db:
            state=db.execute('SELECT status FROM application_queue WHERE job_id=?',(item['job_id'],)).fetchone()[0]
        finish(item, 'submission_unknown' if state=='submitting' else 'needs_attention', {'reason': str(exc)[:1000]})
    return True


def recover():
    with library.connect() as db:
        initialize(db)
        db.execute("UPDATE application_queue SET status='queued',updated_at=? WHERE status='preparing'", (stamp(),))
        db.execute("UPDATE application_queue SET status='submission_unknown',updated_at=? WHERE status='submitting'",(stamp(),))


def reconcile(browser):
    """Read-only confirmation checks after a human completes a held form."""
    from .job_browser import receipt, COLLECT
    for page,item in list(browser.job_pages.items()):
        if page.is_closed():
            browser.job_pages.pop(page,None);browser.held_pages.discard(page)
            continue
        try:
            observed=page.evaluate(COLLECT)
            same_job=page_learner.canonical_url(observed['url']).startswith(page_learner.canonical_url(item['job_url']))
            if same_job and receipt(observed):
                with library.connect() as db:
                    row=db.execute('SELECT result FROM application_queue WHERE job_id=?',(item['job_id'],)).fetchone()
                previous=json.loads(row[0])
                finish(item,'submitted',{**previous,'submitted':True,'receipt_text':observed['text'][:5000],
                                         'receipt_url':observed['url'],'confirmation_observed_after_user_action':True})
                browser.job_pages.pop(page,None);browser.held_pages.discard(page)
        except Exception:
            continue


def restore_verification_drafts(browser, run_id):
    """Restore only known unsubmitted verification drafts, without clicking submit."""
    from .job_browser import execute
    config={**configuration(),'submission_mode':'review'}
    with library.connect() as db:
        items=[dict(r) for r in db.execute("SELECT * FROM application_queue WHERE status='verification_required' LIMIT 5")]
    for item in items:
        check_running(run_id)
        try:
            result=execute(browser,item,config,check=lambda:check_running(run_id),mark_submission=lambda d:None)
            if result['state']=='prepared':
                browser.held_pages.add(browser.page);browser.job_pages[browser.page]=item
                with library.connect() as db:
                    event(db,item['job_id'],'draft_restored','Required answers and resume restored in Chrome; user must submit and complete email verification locally')
        except Exception as exc:
            with library.connect() as db:event(db,item['job_id'],'restore_error',str(exc)[:500])


def discover_one(browser, run_id):
    """One bounded search page at a time; retain cursor and deduplicate observed URLs."""
    from urllib.parse import unquote
    from .job_browser import COLLECT, allowed, barrier
    with library.connect() as db:
        db.execute('CREATE TABLE IF NOT EXISTS application_discovery (run_id TEXT PRIMARY KEY,cursor INTEGER,last_at REAL)')
        row=db.execute('SELECT cursor,last_at FROM application_discovery WHERE run_id=?',(run_id,)).fetchone()
    if row and time.time()-row[1]<30:
        return False
    entries=searches()['searches'];cursor=row[0] if row else 0
    if not entries:return False
    entry=entries[cursor%len(entries)]
    page=browser.context.new_page();added=0
    try:
        check_running(run_id)
        # Search-engine pages remain local; no model receives these captures.
        page.goto(entry['url'],wait_until='domcontentloaded',timeout=30000)
        page.wait_for_timeout(1500)
        p=urlsplit(page.url)
        if not (allowed(page.url,configuration()) or p.scheme=='https' and p.hostname=='www.google.com' and p.path=='/search'):
            raise ValueError('Search redirected to authentication or outside configured routes')
        observed=page.evaluate(COLLECT)
        blocked=barrier(observed)
        if blocked:raise ValueError(blocked)
        for e in observed['elements']:
            check_running(run_id)
            url=e.get('href','')
            if urlsplit(url).hostname=='www.google.com' and urlsplit(url).path=='/url':
                url=(parse_qs(urlsplit(url).query).get('q') or parse_qs(urlsplit(url).query).get('url') or [''])[0]
            if not is_job_link(url) or not allowed(url,configuration()):continue
            result=enqueue({'url':url,'title':e['name'][:1000],'evidence_url':observed['url']})
            added+=not result['duplicate']
            if added>=20:break
        detail=f"{entry['site']} / {entry['role']} / {entry['location']}: {added} new observed job URLs"
    except Exception as exc:
        detail=f"{entry['site']}: {str(exc)[:400]}"
    finally:
        page.close()
    with library.connect() as db:
        db.execute('INSERT OR REPLACE INTO application_discovery VALUES(?,?,?)',(run_id,cursor+1,time.time()))
        event(db,None,'discovery',detail)
    return True


def dispatch(name, args):
    if name=='fan_job_chrome_pair':
        from .chrome_connector import pairing
        return pairing()
    if name=='fan_job_chrome_status':
        from .chrome_connector import status as chrome_status
        return {'ok':True,**chrome_status()}
    if name == 'fan_job_sharing_get':
        from .job_sharing import policy
        return {'ok': True, 'policy': policy()}
    if name == 'fan_job_sharing_set':
        from .job_sharing import save
        return {'ok': True, 'policy': save(args['enabled'], configuration()['sites'] + ['linkedin.com'])}
    if name == 'fan_job_config_get':
        return {'ok': True, 'configuration': configuration()}
    if name == 'fan_job_config_set':
        return save_configuration(args)
    if name == 'fan_job_enqueue':
        return enqueue(args)
    if name == 'fan_job_status':
        return status()
    if name == 'fan_job_discover':
        return discover(args['page_id'])
    if name == 'fan_job_searches':
        return searches()
    if name == 'fan_job_start':
        return start(args.get('hours', 8))
    if name == 'fan_job_control':
        return control(args['run_id'], args['action'])
    raise ValueError('Unknown local application preparation tool')


def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    recover()
    browser=None
    try:
        while True:
            active=None
            if configuration()['browser_execution']:
                with library.connect() as db:
                    active=db.execute("SELECT run_id FROM application_run WHERE status='running' AND deadline>?",(time.time(),)).fetchone()
                if active and browser is None:
                    try:
                        browser=connect_browser(configuration())
                        restore_verification_drafts(browser,active[0])
                    except Exception as exc:
                        control(active[0],'pause')
                        with library.connect() as db:
                            db.execute('UPDATE application_run SET detail=? WHERE run_id=?',(str(exc)[:500],active[0]))
                            event(db,None,'browser_connection_required',str(exc)[:500])
                        browser=None;active=None
            if not process_one(browser=browser):
                if browser:
                    reconcile(browser)
                    if active and configuration()['automatic_discovery']:
                        try:
                            discover_one(browser,active[0])
                        except Exception as exc:
                            control(active[0],'pause')
                            with library.connect() as db:event(db,None,'browser_connection_required',str(exc)[:500])
                            browser.close();browser=None
                time.sleep(1)
    finally:
        if browser:browser.close()


if __name__ == '__main__':
    main()
