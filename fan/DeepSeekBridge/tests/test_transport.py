"""UTF-8 SSE decoding and incomplete responses, with an in-memory HTTP transport."""
import json
import httpx
import pytest
from bridge.transport import CompletionStream


def stream_for(body, status=200):
    client = httpx.Client(transport=httpx.MockTransport(lambda request: httpx.Response(status, content=body,
                         headers={'Content-Type': 'text/event-stream; charset=utf-8'})))
    return CompletionStream(client, 'http://127.0.0.1/chat/completions', {}, 'synthetic')


def event(delta=None, finish=None, usage=None):
    return ('data: ' + json.dumps({'choices': [{'index': 0, 'delta': delta or {}, 'finish_reason': finish}], 'usage': usage}, ensure_ascii=False) + '\r\n\r\n').encode()


def test_utf8_reasoning_usage_and_done():
    body = b': keepalive\r\n\r\n' + event({'reasoning_content': 'thinking'}) + event({'content': 'café α → 10'}) + event(finish='stop', usage={'prompt_tokens': 12, 'completion_tokens': 4}) + b'data: [DONE]\r\n\r\n'
    stream = stream_for(body)
    try:
        chunks = list(stream)
        assert chunks[0].choices[0].delta.reasoning_content == 'thinking'
        assert chunks[1].choices[0].delta.content == 'café α → 10'
        assert chunks[2].usage.model_dump()['completion_tokens'] == 4
    finally:
        stream.close()
    assert stream.client.is_closed


def test_disconnect_does_not_succeed():
    stream = stream_for(event({'content': 'partial'}, finish='stop'))
    try:
        with pytest.raises(RuntimeError, match='before the stream completed'):
            list(stream)
    finally:
        stream.close()


def test_provider_error_is_visible():
    with pytest.raises(RuntimeError, match='HTTP 401'):
        stream_for(b'{"error":{"message":"Invalid key"}}', 401)
