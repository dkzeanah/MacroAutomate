"""Versioned local automation units: Python orchestration, existing typed tools.

No model, eval, shell, guessed parameters or implicit repair. Source pins and
explicit postconditions make reuse falsifiable; a failed check stops the chain.
"""
from __future__ import annotations
import copy
import hashlib
import json
import time
from jsonschema import Draft202012Validator
from . import library

PREFIX = 'unit:'


def save(name, steps, input_schema=None, description='', overwrite=False):
    key = PREFIX + name
    if not name.strip() or len(name) > 100 or not 1 <= len(steps) <= 100:
        raise ValueError('Use a named unit with 1–100 bounded steps')
    try:
        library.get(key)
    except ValueError:
        pass
    else:
        if not overwrite:
            raise ValueError('Unit exists; set overwrite explicitly')
    from .catalog import TOOLS, UnitStep
    forbidden = {'daa_unit_save', 'daa_unit_run', 'daa_explore', 'daa_chain_status'}
    clean = [UnitStep.model_validate(step).model_dump(exclude_defaults=True) for step in steps]
    names = set()
    for index, step in enumerate(clean):
        if set(step) - {'id', 'tool', 'arguments', 'expect', 'branch', 'note'}:
            raise ValueError('Unknown unit step field')
        if step.get('tool') not in TOOLS or step['tool'] in forbidden:
            raise ValueError('Unit step must use an existing nonrecursive typed tool')
        step['id'] = step.get('id') or str(index + 1)
        if step['id'] in names:
            raise ValueError('Step IDs must be unique')
        names.add(step['id'])
        if not isinstance(step.get('arguments', {}), dict) or not isinstance(step.get('expect', {}), dict):
            raise ValueError('Arguments and explicit expected result fields must be objects')
        if step['tool'] == 'ahk_script_run':
            script = library.get(step['arguments'].get('name', ''))
            if script['kind'] != 'script' or not step['arguments'].get('wait'):
                raise ValueError('Script units must wait for an existing saved AHK tool')
            step['source_pin'] = {'revision': script['revision'],
                                  'sha256': hashlib.sha256(script['content'].encode()).hexdigest()}
    schema = input_schema or {'type': 'object', 'additionalProperties': False}
    Draft202012Validator.check_schema(schema)
    content = json.dumps({'schema_version': 1, 'input_schema': schema, 'steps': clean}, ensure_ascii=False)
    record = library.save(key, 'workflow', content, description=description, tags=['daa', 'local-unit'],
                          usage='run learned unit ' + name + ' inputs {JSON}',
                          metadata={'source_kind': 'reference', 'format': 'daa-unit-v1'})
    return {'ok': True, 'name': name, 'revision': record['revision'], 'steps': len(clean),
            'note': 'Saved procedure is a reference until its execution and postconditions are observed.'}


def listing(query='', limit=30):
    return {'ok': True, 'units': [r for r in library.search(query, min(100, max(limit, 50)))
                                if r['name'].startswith(PREFIX)][:limit]}


def field(value, path):
    for part in path.split('.'):
        if isinstance(value, list):
            value = value[int(part)]
        else:
            value = value[part]
    return value


def check(actual, expected):
    if isinstance(expected,dict) and set(expected)=={'contains'}:
        return isinstance(actual,(str,list,dict)) and expected['contains'] in actual
    if isinstance(expected,dict) and set(expected)=={'equals'}:
        return actual==expected['equals']
    return actual==expected


def resolve(value, inputs, results):
    if isinstance(value, dict):
        if set(value) == {'$input'}:
            return copy.deepcopy(field(inputs, value['$input']))
        if set(value) == {'$result'}:
            return copy.deepcopy(field(results, value['$result']))
        return {k: resolve(v, inputs, results) for k, v in value.items()}
    if isinstance(value, list):
        return [resolve(v, inputs, results) for v in value]
    return value


def run(name, inputs, invoke, emit=lambda *_: None, timeout_seconds=600, database=None):
    record = library.get(PREFIX + name)
    plan = json.loads(record['content'])
    Draft202012Validator(plan['input_schema']).validate(inputs)
    results, completed = {}, []
    deadline = time.monotonic() + min(3600, max(1, timeout_seconds))
    for step in plan['steps']:
        from .chains import CURRENT, wait_ready
        parent = CURRENT.get()
        if parent and database:
            try:
                wait_ready(database, parent['task_id'], deadline)
            except ValueError as exc:
                return {'ok': False, 'name': name, 'error': str(exc), 'completed': completed}
        if time.monotonic() >= deadline:
            return {'ok': False, 'name': name, 'error': 'Local unit time budget reached', 'completed': completed}
        arguments = resolve(step.get('arguments', {}), inputs, results)
        if step.get('source_pin'):
            source = library.get(arguments['name'])
            pin = step['source_pin']
            if source['revision'] != pin['revision'] or hashlib.sha256(source['content'].encode()).hexdigest() != pin['sha256']:
                return {'ok': False, 'name': name, 'failed_step': step['id'], 'error': 'Pinned tool revision changed; review and save the unit again', 'completed': completed}
        emit('unit_step', {'unit': name, 'step': step['id'], 'branch': step.get('branch', ''),
                           'tool': step['tool'], 'note': step.get('note', ''), 'revision': record['revision']})
        from .chains import CURRENT, scope
        parent = CURRENT.get()
        with scope({**parent, 'branch': step.get('branch', '')} if parent else None):
            result = invoke(step['tool'], arguments)
        results[step['id']] = result
        if result.get('ok') != True or result.get('status') in ('error', 'cancelled', 'running'):
            return {'ok': False, 'name': name, 'failed_step': step['id'], 'completed': completed, 'result': result}
        checks = resolve(step.get('expect', {}), inputs, results)
        try:
            passed = all(check(field(result, path), expected) for path, expected in checks.items())
        except (KeyError, IndexError, TypeError, ValueError):
            passed = False
        if not passed:
            return {'ok': False, 'name': name, 'failed_step': step['id'], 'error': 'Explicit postcondition failed', 'completed': completed, 'result': result}
        completed.append(step['id'])
    emit('unit_reuse', {'name': name, 'revision': record['revision'], 'completed': completed,
                        'llm_calls': 0, 'source_kind': 'executed local procedure'})
    return {'ok': True, 'name': name, 'revision': record['revision'], 'completed': completed,
            'verified': all(bool(s.get('expect')) for s in plan['steps']), 'last_result': result,
            'llm_calls': 0, 'note': 'Verified means the listed explicit checks passed, not complete application coverage.'}
