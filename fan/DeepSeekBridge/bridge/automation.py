"""Indexed AHK v2 authoring and managed execution for the unified agent."""
from __future__ import annotations
import os
import json
import shutil
import subprocess
import threading
import time
import uuid
import hashlib
from dataclasses import dataclass
from pathlib import Path

from .common import ROOT
from . import library
from jsonschema import Draft202012Validator

SCRIPTS = ROOT / 'agent_scripts'
RUN_OUTPUT = ROOT / '.runtime' / 'runs'
MAX_SCRIPT_BYTES = 128 * 1024
_guard = threading.RLock()


@dataclass
class ScriptProcess:
    id: str
    name: str
    process: subprocess.Popen
    started: float
    deadline: float
    stdout_path: Path
    stderr_path: Path
    task_id: str | None = None
    stopped: bool = False
    timed_out: bool = False


_runs: dict[str, ScriptProcess] = {}


def unified_mode() -> bool:
    pointer = ROOT.parent / 'storage_paths.json'
    if not pointer.is_file():
        return False
    configured = json.loads(pointer.read_text(encoding='utf-8-sig')).get('unified_db')
    return bool(configured) and Path(configured).resolve() == library.INDEX.resolve()


def script_path(name: str) -> Path:
    """Allow a flat script name only, never paths or alternate extensions."""
    import re
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]{0,63}\.ahk', name):
        raise ValueError('name must be a simple filename ending in .ahk (letters, numbers, _, -)')
    SCRIPTS.mkdir(parents=True, exist_ok=True)
    target = SCRIPTS / name
    if target.resolve().parent != SCRIPTS.resolve():
        raise ValueError('Script path escapes agent workspace')
    return target


def find_ahk() -> str:
    candidates = [os.getenv('AUTOHOTKEY_EXE', '').strip(),
                  shutil.which('AutoHotkey64.exe'), shutil.which('AutoHotkey.exe'),
                  r'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe',
                  r'C:\Program Files\AutoHotkey\v2\AutoHotkey.exe']
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(Path(candidate))
    raise FileNotFoundError('AutoHotkey v2 not found; set AUTOHOTKEY_EXE to the installed interpreter')


def _stop(run: ScriptProcess, *, timed_out: bool = False) -> None:
    with _guard:
        if run.process.poll() is None:
            run.timed_out = timed_out
            run.stopped = not timed_out
            run.process.kill()
            run.process.wait(timeout=5)


def _deadline(run: ScriptProcess) -> None:
    remaining = max(0, run.deadline - time.monotonic())
    try:
        run.process.wait(timeout=remaining)
    except subprocess.TimeoutExpired:
        _stop(run, timed_out=True)


def _read_output(path: Path) -> str:
    try:
        with path.open('rb') as handle:
            data = handle.read(16000)
        return data.decode('utf-8-sig', errors='replace')
    except OSError:
        return ''


def status(run_id: str) -> dict:
    with _guard:
        run = _runs.get(run_id)
        if not run:
            raise ValueError('Unknown managed script run')
        code = run.process.poll()
        state = ('running' if code is None else 'timed_out' if run.timed_out else
                 'cancelled' if run.stopped else 'complete' if code == 0 else 'error')
        return {'ok': state in ('running', 'complete'), 'run_id': run.id,
                'name': run.name, 'pid': run.process.pid, 'status': state,
                'exit_code': code, 'timed_out': run.timed_out,
                'duration_seconds': round(time.monotonic() - run.started, 3),
                'stdout': _read_output(run.stdout_path), 'stderr': _read_output(run.stderr_path),
                'verification': 'Process started; inspect its UI/output to verify the requested effect.' if code is None else 'Actual process exit and captured output.'}


def cancel_for_task(task_id: str) -> None:
    with _guard:
        owned = [run for run in _runs.values() if run.task_id == task_id]
    for run in owned:
        _stop(run)


def valid_run(run_id: str, task_id: str) -> bool:
    """An already-running owned script may finish its APIs after the parent reply."""
    with _guard:
        run = _runs.get(run_id)
        return bool(run and run.task_id == task_id and run.process.poll() is None and not run.stopped)


def has_active_task_run(task_id: str) -> bool:
    with _guard:
        return any(run.task_id == task_id and run.process.poll() is None for run in _runs.values())


def active_runs() -> list[dict]:
    with _guard:
        return [status(key) for key, run in _runs.items() if run.process.poll() is None]


def _metadata(target: Path) -> dict:
    try:
        item = library.get(target.name)
        item.pop('content', None)
        return item
    except ValueError:
        return {'name': target.name, 'kind': 'script', 'description': '', 'revision': 0}


def validate_input_schema(schema: dict) -> None:
    if not schema:
        return
    if schema.get('type') != 'object' or len(json.dumps(schema)) > 12000:
        raise ValueError('input_schema must be a bounded JSON Schema object')
    def local_refs(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key in ('$ref', '$dynamicRef') and (not isinstance(item, str) or not item.startswith('#')):
                    raise ValueError('input_schema references must be local; external network references are not supported')
                local_refs(item)
        elif isinstance(value, list):
            for item in value:
                local_refs(item)
    local_refs(schema)
    try:
        Draft202012Validator.check_schema(schema)
    except Exception as exc:
        raise ValueError('Invalid input_schema: ' + str(exc)[:1000]) from exc


def dispatch(name: str, args: dict, task_id: str | None = None) -> dict:
    """Only scripts written inside this agent workspace can be executed."""
    try:
        if name == 'ahk_script_status':
            return status(args['run_id'])
        if name == 'ahk_script_cancel':
            with _guard:
                run = _runs.get(args['run_id'])
            if not run:
                raise ValueError('Unknown managed script run')
            _stop(run)
            return status(run.id)
        if name == 'ahk_script_list':
            if unified_mode():
                with library.connect() as db:
                    names = [row[0] for row in db.execute("SELECT name FROM records WHERE kind='script' ORDER BY name")]
                return {'ok': True, 'scripts': names,
                        'indexed': [_metadata(Path(item)) for item in names], 'running': active_runs()}
            SCRIPTS.mkdir(parents=True, exist_ok=True)
            paths = [p for p in sorted(SCRIPTS.glob('*.ahk')) if p.is_file()]
            return {'ok': True, 'scripts': [p.name for p in paths],
                    'indexed': [_metadata(p) for p in paths], 'running': active_runs()}
        target = script_path(args.get('name', ''))
        database_mode = unified_mode()
        if name == 'ahk_script_validate':
            source = library.get(target.name)['content'] if database_mode else target.read_text(encoding='utf-8')
            digest = hashlib.sha256(source.encode('utf-8')).hexdigest()
            interpreter = Path(find_ahk())
            parser_identity = str(interpreter) + ':' + str(interpreter.stat().st_mtime_ns)
            proof_hash = hashlib.sha256((digest + parser_identity).encode()).hexdigest()
            # Included files and external DLLs can change without changing this
            # source. Reparse those scripts instead of treating old proof as fresh.
            import re
            cacheable = not re.search(r'^\s*#(?:Include(?:Again)?|DllLoad)\b', source, re.I | re.M)
            remembered = 'knowledge:ahkv2-syntax-' + proof_hash
            try:
                previous = library.get(remembered)
                if cacheable and previous['metadata'].get('syntax_valid') is True:
                    return {'ok':True,'syntax_valid':True,'language':'AutoHotkey v2','name':target.name,'source_hash':digest,'reused':True}
            except ValueError:
                pass
            if database_mode:
                target.write_text(source,encoding='utf-8')
            result = subprocess.run([str(interpreter),'/ErrorStdOut=UTF-8','/validate',str(target)],cwd=SCRIPTS,
                capture_output=True,timeout=20,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            valid = result.returncode == 0
            answer = {'ok':valid,'syntax_valid':valid,'language':'AutoHotkey v2','name':target.name,
                      'source_hash':digest,'reused':False,'diagnostic':(result.stdout+result.stderr).decode('utf-8-sig',errors='replace')[:5000]}
            if valid:
                library.save(remembered,'knowledge',json.dumps(answer),description='Parser-validated AutoHotkey v2 syntax for '+target.name,
                    tags=['ahk','v2','syntax','verified'],usage='Read '+target.name+' before composing similar code.',
                    metadata={'source_kind':'observed','syntax_valid':True,'source_hash':digest,'validation':'installed AutoHotkey v2 /validate'})
            return answer
        if name == 'ahk_script_write':
            source = args.get('source', '')
            if not isinstance(source, str) or not source.strip():
                raise ValueError('source must be nonempty AutoHotkey v2 code')
            encoded = source.encode('utf-8')
            if len(encoded) > MAX_SCRIPT_BYTES:
                raise ValueError('Script exceeds 128 KiB limit')
            if not source.lstrip('\ufeff \t\r\n').startswith('#Requires AutoHotkey v2.0'):
                raise ValueError('Start scripts with #Requires AutoHotkey v2.0')
            previous = _metadata(target) if database_mode or target.exists() else {}
            exists = previous.get('revision', 0) > 0 if database_mode else target.exists()
            if exists and not args.get('overwrite', False):
                raise FileExistsError('Script exists: set overwrite=true to replace')
            if target.is_symlink():
                raise ValueError('Symbolic-link scripts are not accepted')
            input_schema = args.get('input_schema', previous.get('metadata', {}).get('input_schema', {}))
            validate_input_schema(input_schema)
            if not database_mode:
                temp = target.with_suffix('.tmp')
                temp.write_bytes(encoded)
                temp.replace(target)
            record = library.save(target.name, 'script', source,
                                  description=args.get('description', previous.get('description', '')) or 'Agent-created AutoHotkey v2 tool',
                                  tags=args.get('tags', previous.get('tags', ['ahk', 'automation'])),
                                  usage=args.get('usage', previous.get('usage', '')) or f'ahk_script_run(name="{target.name}")',
                                  examples=args.get('examples', previous.get('examples', [])),
                                  metadata={'source_kind': 'reference', 'path': str(target), 'language': 'AutoHotkey v2',
                                            'input_schema': input_schema})
            return {'ok': True, 'name': target.name, 'bytes': len(encoded),
                    'revision': record['revision'], 'indexed': True, 'usage': record['usage']}
        if name == 'ahk_script_read':
            return {'ok': True, 'name': target.name, 'source': library.get(target.name)['content'] if database_mode else target.read_text(encoding='utf-8'),
                    'metadata': _metadata(target)}
        if name == 'ahk_script_run':
            if database_mode:
                record = library.get(target.name)
                if record['kind'] != 'script' or target.is_symlink():
                    raise ValueError('Not an executable database script')
                temp = target.with_suffix('.tmp')
                temp.write_text(record['content'], encoding='utf-8')
                temp.replace(target)
            if not target.is_file() or target.is_symlink():
                raise FileNotFoundError(f'Agent script not found: {target.name}')
            inputs = args.get('inputs', {})
            input_json = json.dumps(inputs, ensure_ascii=False, separators=(',', ':'))
            if len(input_json.encode('utf-8')) > 16000:
                raise ValueError('inputs exceeds the 16 KiB process-environment limit')
            schema = _metadata(target).get('metadata', {}).get('input_schema', {})
            validate_input_schema(schema)
            if schema:
                errors = list(Draft202012Validator(schema).iter_errors(inputs))
                if errors:
                    raise ValueError('Invalid tool inputs: ' + '; '.join(error.message[:300] for error in errors[:3]))
            timeout = max(1, min(int(args.get('timeout_seconds', 60)), 300))
            interpreter = find_ahk()
            RUN_OUTPUT.mkdir(parents=True, exist_ok=True)
            run_id = uuid.uuid4().hex
            stdout_path, stderr_path = RUN_OUTPUT / (run_id + '.stdout'), RUN_OUTPUT / (run_id + '.stderr')
            # No shell or model-provided command line. Capture files prevent
            # pipe deadlocks for persistent GUI scripts and remain workspace-scoped.
            environment = os.environ.copy()
            environment['FAN_BRIDGE_TASK_ID'] = task_id or ''
            environment['FAN_BRIDGE_RUN_ID'] = run_id
            from .chains import CURRENT
            environment['FAN_BRIDGE_CHAIN_PARENT'] = (CURRENT.get() or {}).get('id', '')
            environment['FAN_TOOL_INPUT'] = input_json
            with stdout_path.open('wb') as stdout, stderr_path.open('wb') as stderr:
                process = subprocess.Popen([interpreter, '/ErrorStdOut=UTF-8', str(target)],
                                           cwd=str(SCRIPTS), stdin=subprocess.DEVNULL,
                                           stdout=stdout, stderr=stderr, env=environment,
                                           creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            started = time.monotonic()
            run = ScriptProcess(run_id, target.name, process, started, started + timeout,
                                stdout_path, stderr_path, task_id)
            with _guard:
                if len(_runs) > 200:
                    for key in list(_runs):
                        if _runs[key].process.poll() is not None and len(_runs) > 150:
                            del _runs[key]
                _runs[run_id] = run
            if args.get('wait', False):
                threading.Thread(target=_deadline, args=(run,), daemon=True).start()
                try:
                    process.wait(timeout=timeout + 6)
                except subprocess.TimeoutExpired:
                    _stop(run, timed_out=True)
            return status(run_id)
        raise ValueError('Unknown script operation')
    except (OSError, ValueError, UnicodeError, subprocess.SubprocessError) as exc:
        return {'ok': False, 'error': str(exc), 'name': args.get('name', '')}
