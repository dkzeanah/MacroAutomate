"""Run HTTP gateway."""
import uvicorn
from .common import HOST, PORT

if __name__ == '__main__':
    uvicorn.run('bridge.gateway:app', host=HOST, port=PORT, log_level='warning')
