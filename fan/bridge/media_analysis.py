"""Use the installed Cutline analyzer, selecting a capable Python automatically."""
from __future__ import annotations
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def interpreters(root):
    candidates = [Path(sys.executable), Path(root) / '.venv/Scripts/python.exe']
    try:
        import winreg
        for hive in (winreg.HKEY_CURRENT_USER, winreg.HKEY_LOCAL_MACHINE):
            try:
                with winreg.OpenKey(hive, r'Software\Python\PythonCore') as key:
                    for index in range(winreg.QueryInfoKey(key)[0]):
                        version = winreg.EnumKey(key, index)
                        try:
                            with winreg.OpenKey(key, version + r'\InstallPath') as install:
                                candidates.append(Path(winreg.QueryValue(install, None)) / 'python.exe')
                        except OSError:
                            pass
            except OSError:
                pass
    except ImportError:
        pass
    return list(dict.fromkeys(str(path) for path in candidates if path.is_file()))


def engine_python(root):
    for executable in interpreters(root):
        try:
            check = subprocess.run([executable, '-c', 'import cv2,numpy'], capture_output=True,
                                   timeout=15, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            if check.returncode == 0:
                return executable
        except (OSError, subprocess.TimeoutExpired):
            continue
    raise RuntimeError('No installed Python has OpenCV and NumPy. Install Cutline media dependencies once.')


def run(args, progress, cancelled):
    source, root = Path(args['path']), Path(args['engine_root'])
    if not source.is_file():
        raise FileNotFoundError(f'Video not found: {source}')
    if not (root / 'python/sidecar/analyze.py').is_file():
        raise FileNotFoundError(f'Cutline analyzer not found under {root}')
    progress(0, 'Finding installed video-analysis runtime')
    executable = engine_python(root)
    # Run the same maintained analyzer in a child with its required dependencies.
    directory = Path(args['work_dir'])
    directory.mkdir(parents=True, exist_ok=True)
    request = directory / 'engine-request.json'
    output = directory / 'engine-result.json'
    request.write_text(json.dumps({**args, 'output': str(output)}), encoding='utf-8')
    command = [executable, str(Path(__file__).resolve()), str(request)]
    with (directory / 'engine.log').open('w', encoding='utf-8') as log:
        child = subprocess.Popen(command, stdout=log, stderr=log,
                                 creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        while child.poll() is None:
            if cancelled():
                child.terminate()
                child.wait(timeout=10)
                raise InterruptedError('Video analysis cancelled')
            status = directory / 'engine-progress.json'
            try:
                update = json.loads(status.read_text(encoding='utf-8'))
                progress(update['fraction'], update['message'])
            except (OSError, ValueError):
                pass
            time.sleep(.25)
    if not output.is_file():
        detail = (directory / 'engine.log').read_text(encoding='utf-8', errors='replace')[-1800:]
        raise RuntimeError(f'Cutline exited {child.returncode}: {detail}')
    result = json.loads(output.read_text(encoding='utf-8'))
    if not result.get('ok'):
        raise RuntimeError(result.get('error', 'Cutline analysis failed'))
    return result


def analyze_in_engine(args):
    from workspace_worker import write_json
    sys.path.insert(0, str(Path(args['engine_root']) / 'python'))
    from sidecar.analyze import analyze
    directory = Path(args['work_dir'])
    def progress(fraction, message):
        write_json(directory / 'engine-progress.json', {'fraction': fraction * .85, 'message': message})
    try:
        result = analyze(args['path'], use_cache=True, progress=progress)
        if not result.get('samples'):
            raise ValueError('Video opened but no decodable frames were analyzed')
        # Preview frames support Fan's existing contact sheet/export/clip tools.
        import cv2
        capture = cv2.VideoCapture(args['path'])
        frames = []
        try:
            duration = result.get('duration', 0)
            for index in range(min(12, max(1, int(duration) + 1))):
                seconds = index * max(0, duration - .1) / max(1, min(12, int(duration) + 1) - 1)
                capture.set(cv2.CAP_PROP_POS_MSEC, seconds * 1000)
                ok, image = capture.read()
                if not ok:
                    continue
                path = directory / f'preview-{index:03}.jpg'
                if cv2.imwrite(str(path), image):
                    frames.append({'idx': index + 1, 'ts_ms': round(seconds * 1000), 'path': str(path)})
        finally:
            capture.release()
        write_json(args['output'], {'ok': True, 'result': result, 'frames': frames, 'runtime': sys.executable})
    except Exception as error:
        write_json(args['output'], {'ok': False, 'error': f'{type(error).__name__}: {error}'})


if __name__ == '__main__':
    analyze_in_engine(json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig')))
