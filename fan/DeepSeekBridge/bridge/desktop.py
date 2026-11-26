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
from .common import storage_path, agent_heartbeat

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / '.runtime'
CREATE_NO_WINDOW = getattr(subprocess, 'CREATE_NO_WINDOW', 0)


def parse_listeners(table: str, ports: set[int]) -> dict[int, list[int]]:
    """Listening PIDs per watched port, parsed from `netstat -ano -p TCP`.

    A port can have more than one Windows listener: SO_REUSEADDR lets a second
    socket bind the same address, so every owner must be stopped for takeover.
    """
    owners: dict[int, list[int]] = {}
    for line in table.splitlines():
        fields = line.split()
        if len(fields) < 5 or fields[0].upper() != 'TCP' or fields[3].upper() != 'LISTENING':
            continue
        if fields[1].startswith('['):
            continue  # IPv6-only listeners do not block the IPv4 loopback bind.
        _, separator, port = fields[1].rpartition(':')
        if not separator:
            continue
        try:
            number, pid = int(port), int(fields[4])
        except ValueError:
            continue
        if number in ports and pid and pid not in owners.setdefault(number, []):
            owners[number].append(pid)
    return {number: pids for number, pids in owners.items() if pids}


def listener_pids(ports: set[int]) -> dict[int, list[int]]:
    try:
        completed = subprocess.run(['netstat', '-ano', '-p', 'TCP'], capture_output=True,
                                   text=True, timeout=10, creationflags=CREATE_NO_WINDOW)
    except (OSError, subprocess.SubprocessError):
        return {}
    return parse_listeners(completed.stdout, ports)


def ports_available(ports: set[int]) -> bool:
    """Exclusive loopback bind test; a released listener frees its port at once."""
    for port in ports:
        with socket.socket() as probe:
            options = getattr(socket, 'SO_EXCLUSIVEADDRUSE', None)
            if options is not None:
                probe.setsockopt(socket.SOL_SOCKET, options, 1)
            try:
                probe.bind(('127.0.0.1', port))
            except OSError:
                return False
    return True


def bridge_health(port: int, token: str) -> dict | None:
    """Authenticated health of this project's gateway, or None when it is absent."""
    import httpx
    try:
        with httpx.Client(timeout=2, trust_env=False) as client:
            response = client.get(f'http://127.0.0.1:{port}/health', headers={'X-Bridge-Token': token})
        if response.is_success:
            state = response.json()
            if state.get('healthy') is True and state.get('tools'):
                return state
    except (httpx.HTTPError, ValueError):
        pass
    return None


def observatory_identity(port: int) -> bool:
    """The observatory's public workbench page proves ownership before takeover."""
    import httpx
    try:
        with httpx.Client(timeout=2, trust_env=False) as client:
            response = client.get(f'http://127.0.0.1:{port}/')
        return response.is_success and 'Live Learning Workbench' in response.text
    except (httpx.HTTPError, ValueError):
        return False


def bridge_busy(state: dict) -> bool:
    """Takeover must never interrupt queued work or running scripts/jobs."""
    activity = state.get('activity') or {}
    return bool(activity.get('running_tasks') or activity.get('tools')
                or activity.get('application_runs') or state.get('managed_scripts'))


def stop_process(pid: int) -> None:
    try:
        subprocess.run(['taskkill', '/PID', str(pid), '/T', '/F'], capture_output=True,
                       timeout=10, creationflags=CREATE_NO_WINDOW)
    except (OSError, subprocess.SubprocessError):
        pass


def parse_agent_pids(output: str) -> list[int]:
    pids = []
    for line in output.splitlines():
        line = line.strip()
        if line.isdigit() and int(line) > 0:
            pids.append(int(line))
    return pids


def stale_agent_pids() -> list[int]:
    """Queue daemons from this project that predate the heartbeat file.

    A takeover runs once per upgrade, and the previous daemon does not publish
    its PID. The parent image check keeps unrelated Python projects untouched.
    """
    root = str(ROOT).replace("'", "''")
    script = (
        f"$root='{root}';"
        "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" |"
        "Where-Object { $_.CommandLine -like '*-m bridge.agent*' -and $_.CommandLine -like '*--daemon*' } |"
        "Where-Object { $parent=Get-CimInstance Win32_Process -Filter ('ProcessId=' + $_.ParentProcessId);"
        " $parent.ExecutablePath -and $parent.ExecutablePath -like ($root + '*') } |"
        "Select-Object -ExpandProperty ProcessId")
    return _run_pid_query(script)


def stale_launcher_pids() -> list[int]:
    """Console wrappers of the standalone start_*.bat scripts, once their service is replaced."""
    root = str(ROOT).replace("'", "''")
    script = (
        f"$root='{root}';"
        "Get-CimInstance Win32_Process -Filter \"Name='cmd.exe'\" |"
        "Where-Object { $_.CommandLine -like ('*' + $root + '*start_*.bat*') } |"
        "Select-Object -ExpandProperty ProcessId")
    return _run_pid_query(script)


def _run_pid_query(script: str) -> list[int]:
    try:
        completed = subprocess.run(['powershell', '-NoProfile', '-NonInteractive', '-Command', script],
                                   capture_output=True, text=True, timeout=15, creationflags=CREATE_NO_WINDOW)
    except (OSError, subprocess.SubprocessError):
        return []
    return parse_agent_pids(completed.stdout)


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
        ports = {int(os.getenv('BRIDGE_PORT', '8765')), int(os.getenv('MONITOR_PORT', '8766'))}
        gateway_port = int(os.getenv('BRIDGE_PORT', '8765'))
        monitor_port = int(os.getenv('MONITOR_PORT', '8766'))
        owners = listener_pids(ports)
        if owners:
            conflicts = []
            existing = None
            if gateway_port in owners:
                existing = bridge_health(gateway_port, os.getenv('BRIDGE_TOKEN', ''))
                if existing is None:
                    conflicts.append(f'port {gateway_port}')
            if monitor_port in owners and not observatory_identity(monitor_port):
                conflicts.append(f'port {monitor_port}')
            if conflicts:
                publish('Bridge ' + ' and '.join(conflicts)
                        + (' is' if len(conflicts) == 1 else ' are') + ' already in use by another program. '
                        'Stop that program or change the ports in .env, then retry.')
                return
            if existing is not None and bridge_busy(existing):
                publish('Bridge services started outside Fan are busy. Finish or cancel their task, then retry.')
                return
            # Every occupied port is an idle copy of this bridge (manual launcher
            # or Harness setup). Fan is the single lifecycle owner, so take them
            # over instead of failing on WinError 10048.
            for pid in sorted({pid for pids in owners.values() for pid in pids}):
                stop_process(pid)
            agent = agent_heartbeat()
            if agent:
                stop_process(agent['pid'])
            for pid in stale_agent_pids():  # Daemons from before the heartbeat existed.
                stop_process(pid)
            for pid in stale_launcher_pids():  # Their standalone launcher consoles.
                stop_process(pid)
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and not ports_available(ports):
                time.sleep(.1)
            if not ports_available(ports):
                publish('The previous bridge services are still shutting down. Start services again in a moment.')
                return
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
