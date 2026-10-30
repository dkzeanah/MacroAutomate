"""One controller per history store; a second launcher must not interrupt runs."""
import json
import os
import socket
from contextlib import contextmanager
from . import store


class AlreadyRunning(RuntimeError):
    def __init__(self,url):
        self.url=url
        super().__init__('Atlas Control is already running: '+url)


@contextmanager
def own(port: int):
    if not 1<=port<=65535:
        raise ValueError('Port must be between 1 and 65535')
    store.DATA.mkdir(parents=True,exist_ok=True)
    listener=store.DATA/'listener.json'
    handle=(store.DATA/'controller.lock').open('a+b')
    handle.seek(0,2)
    if handle.tell()==0:
        handle.write(b'1')
        handle.flush()
    handle.seek(0)
    try:
        if os.name=='nt':
            import msvcrt
            msvcrt.locking(handle.fileno(),msvcrt.LK_NBLCK,1)
        else:
            import fcntl
            fcntl.flock(handle,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except OSError:
        handle.close()
        try:
            url=json.loads(listener.read_text())['url']
        except (OSError,ValueError,KeyError):
            url=f'http://127.0.0.1:{port}/'
        raise AlreadyRunning(url)
    try:
        with socket.socket() as probe:
            probe.bind(('127.0.0.1',port))
        url=f'http://127.0.0.1:{port}/'
        listener.write_text(json.dumps({'url':url,'pid':os.getpid()}))
        yield url
    finally:
        handle.close()
