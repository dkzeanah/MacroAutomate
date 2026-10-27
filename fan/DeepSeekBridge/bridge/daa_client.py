"""Python counterpart to FanBridgeClient.ahk; loopback tools, no model client."""
import os
import time
import httpx
from .common import BASE_URL, TOKEN
from .catalog import validate


class DAAClient:
    def __init__(self, task_id=None):
        self.headers = {'X-Bridge-Token':TOKEN,'X-Bridge-Origin':'python'}
        values = {'X-Bridge-Task':task_id or os.getenv('FAN_BRIDGE_TASK_ID'),
                  'X-Bridge-Run':os.getenv('FAN_BRIDGE_RUN_ID'),
                  'X-Bridge-Parent':os.getenv('FAN_BRIDGE_CHAIN_PARENT')}
        self.headers.update({k:v for k,v in values.items() if v})

    def call(self, tool, arguments, timeout=180):
        deadline, waited = time.monotonic()+timeout, False
        while True:
            remaining = deadline-time.monotonic()
            if remaining <= 0:
                raise TimeoutError('Automation time budget reached while paused; next action was not issued')
            response = httpx.post(BASE_URL+'/tools/'+tool,json=validate(tool,arguments),
                                  headers=self.headers,timeout=remaining,trust_env=False)
            response.raise_for_status()
            result = response.json()
            if result.get('paused'):
                waited = True
                time.sleep(.25)
                continue
            if waited and tool == 'daa_trace' and arguments.get('phase') == 'before' and 'x' in arguments:
                raise ValueError('Resumed after coordinate observation; recapture the target before input')
            return result

    def run_unit(self, name, inputs=None, timeout=600):
        return self.call('daa_unit_run',{'name':name,'inputs':inputs or {},'timeout_seconds':timeout},timeout+15)

    def trace(self, label, hwnd=0, phase='before', point=None):
        return self.call('daa_trace',{'label':label,'hwnd':hwnd,'phase':phase,**(point or {})})
