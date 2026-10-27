"""Browser adapter for the approved extension in the user's normal Chrome window."""
from __future__ import annotations
import base64
import json
import re
import time
from pathlib import Path
import httpx
from .common import BASE_URL,TOKEN
from .job_browser import JobBrowser,COLLECT

def rpc(command):
    with httpx.Client(timeout=65,trust_env=False) as client:
        response=client.post(BASE_URL+'/chrome/command',headers={'X-Bridge-Token':TOKEN},json=command)
        if response.status_code>=400:
            raise ValueError(response.json().get('detail','Chrome connector failed'))
        return response.json()

class Page:
    def __init__(self,context,tab_id):
        self.context=context
        self.tab_id=tab_id
        self._closed=False
    @property
    def url(self):
        return rpc({'kind':'tab_status','tab_id':self.tab_id})['url']
    def goto(self,url,**options):
        return rpc({'kind':'navigate','tab_id':self.tab_id,'url':url})
    def wait_for_timeout(self,ms):
        time.sleep(ms/1000)
    def evaluate(self,source):
        if source==COLLECT:
            return rpc({'kind':'observe','tab_id':self.tab_id})['observation']
        if source=="document.getElementById('__fanHighlight')?.remove()":
            return None  # The screenshot command removes our overlays itself.
        raise ValueError('The Chrome adapter accepts bundled observation code only')
    def screenshot(self,*,path,**options):
        result=rpc({'kind':'screenshot','tab_id':self.tab_id,'full_page':bool(options.get('full_page'))})
        data=base64.b64decode(result['png_base64'],validate=True)
        if not data.startswith(b'\x89PNG\r\n\x1a\n') or len(data)>32*1024*1024:
            raise ValueError('Invalid or oversized Chrome capture')
        Path(path).write_bytes(data)
    def is_closed(self):
        if self._closed:return True
        try:
            result=rpc({'kind':'tab_status','tab_id':self.tab_id})
            self._closed=not result.get('exists',False)
        except ValueError as exc:
            if 'No tab with id' in str(exc) or 'tab has been closed' in str(exc):self._closed=True
            else:raise
        return self._closed
    def close(self):
        rpc({'kind':'close_tab','tab_id':self.tab_id})
        self._closed=True

class Context:
    def __init__(self):self._pages=[]
    @property
    def pages(self):return [p for p in self._pages if not p._closed]
    def new_page(self):
        response=rpc({'kind':'new_tab','url':'about:blank'})
        page=Page(self,response['tab_id'])
        self._pages.append(page)
        return page

class Node:
    def __init__(self,browser,field):self.browser=browser;self.field=field
    def click(self):
        return rpc({'kind':'click','tab_id':self.browser.page.tab_id,'field':self.field})

class ExistingChromeBrowser(JobBrowser):
    def __init__(self):
        with httpx.Client(timeout=5,trust_env=False) as client:
            response=client.get(BASE_URL+'/chrome/status',headers={'X-Bridge-Token':TOKEN})
            response.raise_for_status()
            status=response.json()
        if not status.get('connected'):
            raise ValueError('Connect your existing normal Chrome window using Fan’s Connect Chrome control')
        self.context=Context()
        self.page=Page(self.context,status['tab_id'])
        self.context._pages.append(self.page)
        # The user-selected existing page is observed but never navigated/closed.
        self.held_pages={self.page}
        self.job_pages={}
        self.window_id=status['window_id']
    def close(self):
        # Leave the normal window and every user/form tab open for review.
        self.job_pages.clear()
    def node(self,element_id,expected=None):
        current=next((e for e in self.page.evaluate(COLLECT)['elements'] if e['element_id']==element_id),None)
        if not current or current['protected'] or not current['enabled']:
            raise ValueError('Live element is stale, protected or disabled')
        if expected and any(current[k]!=expected[k] for k in ('name','role','type')):
            raise ValueError('Live element identity changed before input')
        return Node(self,current)
    def highlight(self,node,caption):
        return rpc({'kind':'highlight','tab_id':self.page.tab_id,'field':node.field})
    def fill(self,field,answer,config):
        self.check_origin(config)
        try:
            return rpc({'kind':'fill','tab_id':self.page.tab_id,'field':field,'answer':answer})
        except ValueError as exc:
            # Phone widgets can add punctuation while handling trusted input.
            # Accept only an independently observed, identical digit sequence.
            if 'Saved text value was not confirmed.' not in str(exc) or not (
                field.get('type')=='tel' or re.fullmatch(r'phone(?: number)?',field.get('name',''),re.I)
            ):
                raise
            current=next((e for e in self.page.evaluate(COLLECT)['elements'] if e['element_id']==field['element_id']),None)
            if (not current or current.get('protected') or not current.get('enabled')
                or any(current.get(k)!=field.get(k) for k in ('name','role','type'))
                or current.get('invalid') or current.get('valid') is False
                or not re.fullmatch(r'[+\d\s().-]+',str(current.get('value','')))
                or re.sub(r'\D','',str(current.get('value','')))!=re.sub(r'\D','',str(answer))):
                raise
            return {'ok':True,'formatted_value_verified':True}
    def upload(self,field,config):
        self.check_origin(config)
        result=rpc({'kind':'upload','tab_id':self.page.tab_id,'field':field})
        return {'filename':result['filename'],'sha256':result['sha256']}
