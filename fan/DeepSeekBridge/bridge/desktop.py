"""Fan-owned hidden service supervisor. Credentials arrive only in the environment."""
from __future__ import annotations
import argparse
import ctypes
import json
import os
import secrets
import socket
import sqlite3
import subprocess
import sys
import time
from pathlib import Path
from .common import storage_path

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / '.runtime'


def parent_alive(pid: int) -> bool:
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.restype = ctypes.c_void_p
    kernel.GetExitCodeProcess.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    handle = kernel.OpenProcess(0x1000, False, pid)
    if not handle:
        return False
    code = ctypes.c_ulong()
    try:
        return bool(kernel.GetExitCodeProcess(handle, ctypes.byref(code))) and code.value == 259
    finally:
        kernel.CloseHandle(handle)


def ensure_config() -> None:
    path = ROOT / '.env'
    if not path.exists():
        port = 8765
        for candidate in range(8765, 8796, 2):
            probes = []
            try:
                for number in (candidate, candidate + 1):
                    probe = socket.socket()
                    probes.append(probe)
                    probe.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
                    probe.bind(('127.0.0.1', number))
                port = candidate
                break
            except OSError:
                continue
            finally:
                for probe in probes:
                    probe.close()
        else:
            raise RuntimeError('No free bridge/observatory ports in 8765–8796.')
        with path.open('x', encoding='utf-8') as config:
            config.write('BRIDGE_TOKEN=' + secrets.token_urlsafe(32) + f'\nBRIDGE_PORT={port}\nMONITOR_PORT={port+1}\nALLOW_AGENT_SCRIPTS=1\n')


def main() -> None:
    import msvcrt
    from dotenv import load_dotenv
    parser = argparse.ArgumentParser()
    parser.add_argument('--parent', type=int, required=True)
    args = parser.parse_args()
    RUNTIME.mkdir(exist_ok=True)
    lock = (RUNTIME / 'supervisor.lock').open('a+b')
    lock.write(b'0')
    lock.flush()
    lock.seek(0)
    try:
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        return
    ensure_config()
    load_dotenv(ROOT / '.env')
    from .credentials import resolve
    resolved_key, _key_source = resolve()
    if resolved_key:
        os.environ['DEEPSEEK_API_KEY'] = resolved_key
    os.environ['ALLOW_AGENT_SCRIPTS'] = '1'
    stop = RUNTIME / 'stop'
    stop.unlink(missing_ok=True)
    cancel = RUNTIME / 'cancel-agent'
    cancel.unlink(missing_ok=True)
    state_path = RUNTIME / 'services.json'
    processes = {}
    logs = []
    job = None

    def publish(error: str = '') -> None:
        state = {'pid': os.getpid(), 'parent': args.parent, 'key_loaded': bool(os.getenv('DEEPSEEK_API_KEY')),
                 'children': {name: {'pid': p.pid, 'alive': p.poll() is None, 'exit_code': p.poll()} for name, p in processes.items()},
                 'error': error, 'updated_at': time.time()}
        temp = state_path.with_suffix('.tmp')
        temp.write_text(json.dumps(state), encoding='utf-8')
        # Windows readers can briefly hold a handle without FILE_SHARE_DELETE.
        # A status-file refresh must never tear down healthy agent services.
        for attempt in range(12):
            try:
                os.replace(temp, state_path)
                break
            except PermissionError:
                time.sleep(.025)

    try:
        from .process_job import ProcessJob
        job = ProcessJob()
        for port in (int(os.getenv('BRIDGE_PORT', '8765')), int(os.getenv('MONITOR_PORT', '8766'))):
            with socket.socket() as probe:
                probe.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
                probe.bind(('127.0.0.1', port))
        # Tasks interrupted by a prior Fan exit must not run again on restart.
        db_path = storage_path('BRIDGE_DB', ROOT / 'bridge.sqlite3')
        if db_path.exists():
            with sqlite3.connect(db_path, timeout=10) as db:
                if db.execute("SELECT 1 FROM sqlite_master WHERE name='tasks'").fetchone():
                    db.execute("UPDATE tasks SET status='error',response='Bridge stopped before this task finished; resend to continue.' WHERE status IN ('queued','running')")
        # Run the real interpreter directly. The Windows venv redirector can
        # spawn another Python process that would otherwise outlive termination.
        python = getattr(sys, '_base_executable', sys.executable)
        child_env = os.environ.copy()
        child_env['PYTHONPATH'] = str(Path(sys.prefix) / 'Lib' / 'site-packages') + os.pathsep + str(ROOT)
        commands = {
            'gateway': [python, '-m', 'bridge'],
            'observatory': [python, '-m', 'bridge.monitor'],
            'agent': [python, '-m', 'bridge.agent', '--daemon'],
            'worker': [os.environ['AUTOHOTKEY_EXE'], '/ErrorStdOut', str(ROOT / 'ahk' / 'Worker.ahk')],
            'applications': [python, '-m', 'bridge.job_applications'],
        }
        for name, command in commands.items():
            log = (RUNTIME / (name + '.log')).open('ab')
            logs.append(log)
            processes[name] = subprocess.Popen(command, cwd=ROOT, stdin=subprocess.DEVNULL,
                                               env=child_env, stdout=log, stderr=log, creationflags=subprocess.CREATE_NO_WINDOW)
            job.add(processes[name])
        last_explorer = 0
        while parent_alive(args.parent) and not stop.exists():
            if time.monotonic() - last_explorer > 2:
                last_explorer = time.monotonic()
                try:
                    from .explorer_usage import advance
                    advance(ROOT)
                except (OSError, ValueError, sqlite3.Error):
                    pass  # A missing/locked sample is a gap, never fabricated dwell.
            if cancel.exists():
                task_id = cancel.read_text(encoding='utf-8').strip()
                cancel.unlink(missing_ok=True)
                with sqlite3.connect(db_path, timeout=10) as db:
                    row = db.execute('SELECT status,mode FROM tasks WHERE id=?', (task_id,)).fetchone()
                if row and row[0] == 'cancelled':
                    for name in ('agent', 'worker'):
                        process = processes[name]
                        if process.poll() is None:
                            process.terminate()
                        process.wait(timeout=3)
                        processes[name] = subprocess.Popen(commands[name], cwd=ROOT, env=child_env,
                                                           stdin=subprocess.DEVNULL, stdout=logs[list(commands).index(name)],
                                                           stderr=logs[list(commands).index(name)], creationflags=subprocess.CREATE_NO_WINDOW)
                        job.add(processes[name])
            failed = [name for name, process in processes.items() if process.poll() is not None]
            if failed:
                publish('Service exited: ' + ', '.join(failed) + '. See service logs.')
                break
            publish()
            time.sleep(.5)
    except Exception as exc:
        publish(str(exc).replace(os.getenv('DEEPSEEK_API_KEY') or '\x00', '[redacted]'))
    finally:
        # Also closes AHK scripts launched by the gateway. They inherit the job
        # so stopping Fan cannot leave invisible orphan automation running.
        if job:
            job.close()
        for process in processes.values():
            if process.poll() is None:
                process.terminate()
        for process in processes.values():
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
        for log in logs:
            log.close()
        lock.close()


if __name__ == '__main__':
    main()
