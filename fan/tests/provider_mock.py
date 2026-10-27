"""Loopback provider fixture. Never reads or records API credentials."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import time
from pathlib import Path

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/pearson_portal.html':
            payload = Path(__file__).with_name('pearson_portal.html').read_bytes()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        else:
            self.send_error(404)

    def log_message(self, *_):
        pass

    def do_POST(self):
        try:
            body = json.loads(self.rfile.read(int(self.headers['Content-Length'])).decode('utf-8'))
            if body.get('stream'):
                self.send_response(200)
                self.send_header('Content-Type', 'text/event-stream; charset=utf-8')
                self.end_headers()
                text = 'café α → ' + body['messages'][-1]['content']
                if self.path.startswith('/history/'):
                    history = body['messages'][1:-1]
                    text = 'history ok' if history == [
                        {'role': 'user', 'content': 'First message'},
                        {'role': 'assistant', 'content': 'First reply'}] else 'history missing'
                self.wfile.write(b': keepalive\r\n\r\n')
                self.wfile.flush()
                for piece in [text[:6], text[6:]]:
                    event = ('data: ' + json.dumps({'choices': [{'delta': {'content': piece},
                        'index': 0, 'finish_reason': None}], 'usage': None}, ensure_ascii=False) + '\r\n\r\n').encode('utf-8')
                    # Deliberately split both the JSON line and a UTF-8 character.
                    split = event.find('é'.encode('utf-8')) + 1
                    split = split if split > 0 else 13
                    self.wfile.write(event[:split])
                    self.wfile.flush()
                    time.sleep(0.06)
                    self.wfile.write(event[split:])
                    self.wfile.flush()
                    time.sleep(3 if self.path.startswith('/streamslow/') else 0.20)
                if not self.path.startswith('/disconnect/'):
                    finish = 'length' if self.path.startswith('/streamtruncate/') else 'stop'
                    event = {'choices': [{'index': 0, 'delta': {}, 'finish_reason': finish}],
                        'usage': {'prompt_tokens': 12, 'completion_tokens': 4, 'total_tokens': 16}}
                    self.wfile.write(('data: ' + json.dumps(event) + '\n\ndata: [DONE]\n\n').encode())
                    self.wfile.flush()
                return
            if self.path.startswith('/slow/'):
                time.sleep(3)
            if self.path.startswith('/broken/'):
                response = b'{broken'
            else:
                text = body['messages'][-1]['content']
                if self.path.startswith('/planner/'):
                    text = 'TYPE 1 Paris' if 'COMPILER FEEDBACK:' in text else 'CHOOSE 1 Paris'
                if self.path.startswith('/semantic/'):
                    text = 'TYPE 1 Paris' if 'COMPILER FEEDBACK:' in text else 'TYPE 1 "Paris"'
                response = json.dumps({'choices': [{'message': {'content': text},
                    'finish_reason': 'length' if self.path.startswith('/truncated/') else 'stop'}],
                    'usage': {'prompt_tokens': 12, 'completion_tokens': 4}}).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(response)))
            self.end_headers()
            self.wfile.write(response)
        except (BrokenPipeError, ConnectionResetError):
            pass

ThreadingHTTPServer(('127.0.0.1', 18766), Handler).serve_forever()
