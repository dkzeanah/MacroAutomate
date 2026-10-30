"""python -m bridge.controller: launch the local, authenticated dashboard."""
import argparse
import atexit
import asyncio
import webbrowser
import uvicorn
from . import adapters,service,instance

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--port',type=int,default=8790)
    parser.add_argument('--no-open',action='store_true')
    args=parser.parse_args()
    try:
        with instance.own(args.port) as url:
            service.recover()
            atexit.register(lambda: [adapters.terminate(key) for key in list(adapters.PROCESSES)])
            print('Atlas Control: '+url,flush=True)
            if not args.no_open:
                import threading
                threading.Timer(.8,lambda:webbrowser.open(url)).start()
            config=uvicorn.Config(service.app,host='127.0.0.1',port=args.port,log_level='warning')
            try:
                with asyncio.Runner(loop_factory=asyncio.SelectorEventLoop) as runner:
                    runner.run(uvicorn.Server(config).serve())
            finally:
                service.shutdown()
    except instance.AlreadyRunning as running:
        print(str(running),flush=True)
        if not args.no_open:
            webbrowser.open(running.url)

if __name__=='__main__':
    main()
