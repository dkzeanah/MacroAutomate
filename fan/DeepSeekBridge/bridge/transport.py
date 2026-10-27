"""Small streaming Chat Completions client for the bridge's existing agent loop.

Avoid loading the SDK's unrelated generated API modules during Fan startup.
"""
from __future__ import annotations
import json
from types import SimpleNamespace
from urllib.parse import urlsplit
import httpx


class Usage(dict):
    def model_dump(self):
        return dict(self)


def decode_chunk(payload: dict):
    if payload.get('error'):
        raise RuntimeError(str(payload['error']))
    choices = []
    for choice in payload.get('choices', []):
        delta = choice.get('delta') or {}
        calls = []
        for call in delta.get('tool_calls') or []:
            function = call.get('function') or {}
            calls.append(SimpleNamespace(index=call.get('index', 0), id=call.get('id'),
                         function=SimpleNamespace(name=function.get('name'), arguments=function.get('arguments'))))
        choices.append(SimpleNamespace(finish_reason=choice.get('finish_reason'),
                       delta=SimpleNamespace(content=delta.get('content'), reasoning_content=delta.get('reasoning_content'), tool_calls=calls)))
    return SimpleNamespace(choices=choices, usage=Usage(payload['usage']) if payload.get('usage') else None)


class CompletionStream:
    def __init__(self, client: httpx.Client, url: str, request: dict, key: str):
        self.client = client
        self.context = client.stream('POST', url, headers={'Authorization': 'Bearer ' + key}, json=request)
        try:
            self.response = self.context.__enter__()
            if self.response.status_code >= 400:
                self.response.read()
                raise RuntimeError(f'DeepSeek HTTP {self.response.status_code}: ' + self.response.text[:1500])
        except Exception:
            client.close()
            raise

    def __iter__(self):
        data = []
        for line in self.response.iter_lines():
            if line.startswith('data:'):
                data.append(line[5:].lstrip())
            elif not line and data:
                event = '\n'.join(data)
                data.clear()
                if event.strip() == '[DONE]':
                    return
                yield decode_chunk(json.loads(event))
        raise RuntimeError('DeepSeek connection ended before the stream completed. Partial output is shown.')

    def close(self):
        self.context.__exit__(None, None, None)
        self.client.close()


class DeepSeekClient:
    def __init__(self, api_key: str, base_url: str, timeout: float = 180):
        self.key = api_key
        self.base_url = base_url.rstrip('/')
        self.timeout = timeout
        self.chat = SimpleNamespace(completions=self)

    def create(self, **request):
        request.pop('stream', None)
        extra = request.pop('extra_body', {})
        request.update(extra, stream=True)
        loopback = urlsplit(self.base_url).hostname in ('127.0.0.1', 'localhost', '::1')
        client = httpx.Client(timeout=httpx.Timeout(self.timeout, connect=10, write=30, pool=10), trust_env=not loopback)
        return CompletionStream(client, self.base_url + '/chat/completions', request, self.key)
