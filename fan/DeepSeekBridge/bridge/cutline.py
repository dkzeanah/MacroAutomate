"""HTTP client for the optional Cutline media service; no shared Python imports."""
from __future__ import annotations
import json
import os
from pathlib import Path
from urllib.parse import urlparse
import httpx
from pydantic import BaseModel, ConfigDict, Field


class MediaArguments(BaseModel):
    model_config = ConfigDict(extra='forbid')


class MediaCall(MediaArguments):
    method: str = Field(min_length=1, max_length=120)
    params: dict = Field(default_factory=dict)
    timeout: float = Field(default=120, ge=1, le=180)


class MediaJob(MediaArguments):
    job_id: str = Field(pattern=r'^[a-f0-9]{32}$')


TOOL_DEFINITIONS = {
    'cutline_capabilities': (MediaArguments, 'Discover Cutline media/knowledge/presenter/remix/motion methods and motion JSON scene format. Cutline MediaAPI.ps1 must be running; Fan remains usable without it.'),
    'cutline_call': (MediaCall, 'Call a discovered Cutline method with its params. motion.describe returns a complete example; motion.validate checks scenes; motion.generate uses DeepSeek. Use cutline_job_submit for rendering/transcription. Returns a job with result or error; a timeout leaves an observable running job.'),
    'cutline_job_submit': (MediaCall, 'Queue a discovered Cutline method without waiting. For motion.render pass params={scene: validatedScene}. Poll cutline_job_status for result paths. No extra LLM is used when a scene is supplied.'),
    'cutline_job_status': (MediaJob, 'Read the status, progress, result, or error of a queued Cutline media job.'),
    'cutline_job_cancel': (MediaJob, 'Cancel a queued Cutline job or request cooperative cancellation of a running job. Some media methods only stop at their next progress checkpoint.'),
}


def configuration():
    project = Path(os.environ.get('CUTLINE_ROOT', Path(__file__).resolve().parents[4]/'avideditor'))
    path = Path(os.environ.get('CUTLINE_API_TOKEN_FILE', project/'data'/'integration'/'api.token'))
    token = os.environ.get('CUTLINE_API_TOKEN') or (path.read_text(encoding='utf-8').strip() if path.exists() else '')
    base = os.environ.get('CUTLINE_API_URL', 'http://127.0.0.1:8780').rstrip('/')
    parsed = urlparse(base)
    if parsed.scheme != 'http' or parsed.hostname not in ('127.0.0.1', 'localhost', '::1') or parsed.username:
        raise ValueError('CUTLINE_API_URL must be a loopback HTTP URL')
    if not token:
        raise ValueError('Start avideditor/MediaAPI.ps1 to initialize the local API token')
    return base, token


def dispatch(name, args):
    base, token = configuration()
    route, payload = '/v1/capabilities', None
    if name in ('cutline_call', 'cutline_job_submit'):
        route = '/v1/call' if name == 'cutline_call' else '/v1/jobs'
        payload = {key: args[key] for key in ('method', 'params', 'timeout') if key in args}
    elif name in ('cutline_job_status', 'cutline_job_cancel'):
        route = '/v1/jobs/'+args['job_id']
        if name == 'cutline_job_cancel':
            route, payload = route+'/cancel', {}
    elif name != 'cutline_capabilities':
        raise ValueError('Unknown Cutline tool')
    try:
        with httpx.Client(timeout=args.get('timeout', 120)+10, follow_redirects=False, trust_env=False) as client:
            response = client.request('GET' if payload is None else 'POST', base+route,
                                      headers={'X-Cutline-Token': token}, json=payload)
            if response.is_error:
                raise ValueError(f'Cutline API HTTP {response.status_code}: {response.json().get("error", "request failed")}')
            return response.json()
    except httpx.HTTPError as error:
        raise ValueError('Cutline media service is unavailable; run fan/Connect_DeepSeek_Cutline.ps1') from error
