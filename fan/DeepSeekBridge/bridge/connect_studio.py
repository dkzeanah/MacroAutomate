"""Start optional local services and install their tools into the web Harness profile."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import httpx
from .common import ROOT, BASE_URL, TOKEN
from .cutline import configuration
from .install_harness import install, install_atlas_persona


def healthy(base, header, token):
    try:
        with httpx.Client(timeout=2, trust_env=False) as client:
            return client.get(base+'/health', headers={header: token}).is_success
    except httpx.HTTPError:
        return False


def launch(command, cwd, name):
    logs = ROOT/'.runtime'
    logs.mkdir(exist_ok=True)
    with (logs/(name+'.stdout.log')).open('ab') as out, (logs/(name+'.stderr.log')).open('ab') as err:
        return subprocess.Popen(command, cwd=str(cwd), stdin=subprocess.DEVNULL, stdout=out, stderr=err,
            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))


def connect(profile=None):
    if not TOKEN:
        raise ValueError('Initialize Fan DeepSeek Bridge first; its local token is required')
    if not healthy(BASE_URL, 'X-Bridge-Token', TOKEN):
        launch([sys.executable, '-m', 'bridge'], ROOT, 'studio-gateway')
    project = Path(os.environ.get('CUTLINE_ROOT', ROOT.parents[2]/'avideditor')).resolve()
    try:
        base, token = configuration()
        media_ready = healthy(base, 'X-Cutline-Token', token)
    except ValueError:
        media_ready = False
    if not media_ready:
        executable = project/'.venv'/'Scripts'/'python.exe'
        if not executable.is_file():
            raise ValueError('Set CUTLINE_ROOT to avideditor with its Python environment installed')
        launch([str(executable), '-m', 'sidecar.integration.service'], project/'python', 'studio-media')
    deadline = time.monotonic()+20
    while time.monotonic() < deadline:
        try:
            base, token = configuration()
            if healthy(base, 'X-Cutline-Token', token) and healthy(BASE_URL, 'X-Bridge-Token', TOKEN):
                break
        except (ValueError, OSError):
            pass
        time.sleep(.25)
    else:
        raise RuntimeError('Services did not become ready; inspect DeepSeekBridge/.runtime/studio-*.stderr.log')
    result = {'media_api': base, 'fan_gateway': BASE_URL, 'ready': True}
    if profile:
        result['harness'] = install(profile)
        try:
            result['harness']['atlas_protocol'] = install_atlas_persona(profile)
        except ValueError as error:
            result['harness']['atlas_protocol'] = {'installed': False, 'reason': str(error), 'existing_persona_preserved': True}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', default=str(Path.home()/'.dsh'/'profiles'/'web'))
    parser.add_argument('--no-install', action='store_true')
    args = parser.parse_args()
    print(json.dumps(connect(None if args.no_install else args.profile), indent=2))


if __name__ == '__main__':
    main()
