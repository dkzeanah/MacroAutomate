"""Run HTTP gateway."""
import asyncio
import sys
import uvicorn
from .common import HOST, PORT

if __name__ == '__main__':
    config = uvicorn.Config('bridge.gateway:app', host=HOST, port=PORT, log_level='warning')
    server = uvicorn.Server(config)
    if sys.platform == 'win32':
        # Local HTTP/websocket traffic needs no asyncio subprocess transport.
        # Proactor's accept loop can stop after WinError 64 while the PID survives.
        with asyncio.Runner(loop_factory=asyncio.SelectorEventLoop) as runner:
            runner.run(server.serve())
    else:
        server.run()
