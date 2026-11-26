from pathlib import Path
import sys, sqlite3
import pytest
HERE = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(HERE), str(HERE.parent / 'DeepSeekBridge')]
import browser_learning
from bridge import library, page_learner


def evidence(frame='passive-1'):
    def control(id, role, name, path, value=''):
        return dict(id=id,role=role,name=name,value=value,href='',protected=False,accessibility_path=path,
                    bounds={'x':0,'y':0,'w':800,'h':600},enabled=True)
    controls=[control(1,'document','A useful guide','1','https://example.test/guide'),
              control(2,'heading','Understanding photosynthesis and plant growth','1.1'),
              control(3,'text','Plants convert light energy into chemical energy stored in sugars. Chlorophyll absorbs sunlight in their leaves.','1.2'),
              control(4,'editable text','Private input','1.3','secret typed text'),
              control(5,'link','Read the reference documentation','1.4'),
              control(6,'text','Another browser tab must not be learned','2')]
    controls[4]['href']='https://example.test/reference'
    return {'ok':True,'url':'https://example.test/guide','frame':{'frame_id':frame,'hwnd':123,'title':'Science guide - Google Chrome',
        'region':{'x':0,'y':0,'w':800,'h':600},'geometry_stable':True},'controls':controls,'accessibility':{'truncated':False}}


@pytest.fixture
def state(tmp_path,monkeypatch):
    monkeypatch.setattr(library,'INDEX',tmp_path/'atlas.sqlite')
    return {'hwnd':123,'pid':7,'context_id':'window-A','profile_id':'chrome:work','profile_label':'Same name','db_path':str(tmp_path/'learning.sqlite')}


def test_auto_reading_uses_existing_atlas_without_screenshots_or_typed_fields(state):
    result=browser_learning.observe(state,call=lambda *a,**k:evidence(),foreground=lambda *a:True)
    assert result['captured'] and result['item_count']>=3
    page=page_learner.get(result['page_id'],limit=1000)
    assert not page['coverage']['full_window_image']
    text=str(page['elements'])
    assert 'photosynthesis' in text and 'secret typed text' not in text and 'Another browser tab' not in text
    with sqlite3.connect(state['db_path']) as db:
        row=db.execute('select profile_id,context_id,capture_kind,reviewed from chrome_learning_capture').fetchone()
    assert row==('chrome:work','window-A','auto_text',0)


def test_duplicate_content_is_skipped_but_separate_profiles_and_windows_are_not(state):
    def run(args,frame):
        return browser_learning.observe(args,call=lambda *a,**k:evidence(frame),foreground=lambda *a:True)
    assert run(state,'page-A')['captured']
    assert not run(state,'not-retained')['captured']
    assert run({**state,'context_id':'window-B'},'page-B')['captured']
    assert run({**state,'context_id':'window-C','profile_id':'chrome:personal'},'page-C')['captured']
    with sqlite3.connect(state['db_path']) as db:
        assert db.execute('select count(*) from chrome_learning_capture').fetchone()[0]==3


def test_background_window_and_mid_read_focus_change_are_skipped(state):
    assert not browser_learning.observe(state,call=lambda *a,**k:pytest.fail('must not probe'),foreground=lambda *a:False)['captured']
    checks=iter([True,False])
    assert not browser_learning.observe(state,call=lambda *a,**k:evidence(),foreground=lambda *a:next(checks))['captured']
    assert not Path(state['db_path']).exists()


@pytest.mark.parametrize('url,title', [('https://accounts.example.test/login','Sign in'),('https://example.test/?token=abc','Page'),('chrome://settings','Settings')])
def test_irrelevant_account_and_internal_pages_are_skipped(url,title):
    page=evidence();page['url']=url;page['frame']['title']=title
    assert not browser_learning.readable(page)[0]


def test_scroll_changed_text_is_collected_as_a_new_observation(state):
    first=browser_learning.observe(state,call=lambda *a,**k:evidence(),foreground=lambda *a:True)
    page=evidence('scrolled');page['controls'][2]['name']='New section about the role of carbon dioxide and water in producing glucose and oxygen during photosynthesis.'
    second=browser_learning.observe(state,call=lambda *a,**k:page,foreground=lambda *a:True)
    assert first['captured'] and second['captured'] and second['item_count']==1


def test_cancelled_read_does_not_publish_an_observation(state):
    with pytest.raises(InterruptedError):
        browser_learning.observe(state,call=lambda *a,**k:evidence(),foreground=lambda *a:True,cancelled=lambda:True)
    assert not Path(state['db_path']).exists()


def test_reused_native_window_handle_requires_the_original_session_token(monkeypatch):
    from types import SimpleNamespace
    from unittest.mock import Mock
    user=SimpleNamespace(GetForegroundWindow=Mock(return_value=123),GetPropW=Mock(return_value=8888))
    def pid(hwnd,out):
        out._obj.value=7
    user.GetWindowThreadProcessId=pid
    monkeypatch.setattr(browser_learning.ctypes,'windll',SimpleNamespace(user32=user),raising=False)
    assert browser_learning.foreground_matches(123,7,'chrome-7-123-8888')
    assert not browser_learning.foreground_matches(123,7,'chrome-7-123-9999')
