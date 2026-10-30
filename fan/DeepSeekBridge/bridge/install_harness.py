"""Add Fan + Cutline tools to an existing DSH profile without replacing its settings."""
from __future__ import annotations
import argparse
from datetime import datetime
import json
import re
from pathlib import Path
from .common import ROOT

MARKER = 'mcp-fan-cutline'


def optional_fan_startup(current):
    """Migrate only our plugin entry; preserve other plugins and YAML expressions."""
    lines = current.splitlines(keepends=True)
    entries = [(index, match) for index, line in enumerate(lines)
               if (match := re.match(r'^(\s*)-\s+id:\s*[\"\']?mcp-fan-cutline[\"\']?\s*(?:#.*)?$', line.rstrip('\r\n')))]
    if len(entries) != 1:
        raise ValueError('Expected one mcp-fan-cutline entry; refusing to alter another profile entry')
    start, entry = entries[0]
    indent = len(entry.group(1))
    for index in range(start+1, len(lines)):
        line = lines[index]
        if line.strip() and not line.lstrip().startswith('#') and len(line)-len(line.lstrip()) <= indent:
            break
        if re.match(r'^\s*failOnStartupError:\s*true\b', line):
            lines[index] = re.sub(r'(failOnStartupError:\s*)true\b', r'\1false', line, count=1)
            return ''.join(lines)
    return current


def write_patch(path, content):
    backup = path.with_name('cordis.patch.yml.backup-'+datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    if path.exists():
        backup.write_bytes(path.read_bytes())
    temporary = path.with_suffix('.yml.new')
    temporary.write_text(content, encoding='utf-8')
    temporary.replace(path)
    return backup


def install_atlas_persona(profile):
    path = Path(profile)/'cordis.patch.yml'
    current = path.read_text(encoding='utf-8')
    marker = '# Fan Atlas execution protocol'
    if marker in current:
        return {'installed': False, 'reason': 'already configured'}
    if 'persona:' in current:
        raise ValueError('This profile already declares a persona; merge the Atlas protocol into that persona explicitly')
    persona = (ROOT/'harness'/'atlas-agent-persona.txt').read_text(encoding='utf-8')
    block = '\n'+marker+'\n- id: system-prompt\n  config:\n    persona: |\n'+''.join('      '+line+'\n' for line in persona.splitlines())
    backup = path.with_name('cordis.patch.yml.before-atlas-'+datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    backup.write_bytes(path.read_bytes())
    path.write_text(current.rstrip()+block, encoding='utf-8')
    return {'installed': True, 'backup': str(backup)}


def install(profile):
    profile = Path(profile).expanduser().resolve()
    if not (profile/'cordis.yml').is_file():
        raise ValueError(f'Not an initialized DeepSeek Harness profile: {profile}')
    python = ROOT/'.venv'/'Scripts'/'python.exe'
    if not python.is_file():
        raise ValueError('Install the Fan bridge environment first')
    path = profile/'cordis.patch.yml'
    current = path.read_text(encoding='utf-8') if path.exists() else ''
    if MARKER in current:
        migrated = optional_fan_startup(current)
        result = {'installed': False, 'updated': migrated != current,
                  'reason': 'optional Fan startup policy updated' if migrated != current else 'already configured',
                  'patch': str(path)}
        if migrated != current:
            result['backup'] = str(write_patch(path, migrated))
        return result
    block = ('- insert:\n'
             f'    - id: {MARKER}\n'
             "      name: '@deepseek-ai/dsh-mcp-client'\n"
             '      config:\n'
             '        serverName: fan\n'
             '        transport: stdio\n'
             f'        command: {json.dumps(str(python))}\n'
             "        args: ['-m', 'bridge.mcp_server']\n"
             f'        cwd: {json.dumps(str(ROOT))}\n'
             '        env: {}\n'
             '        toolCallTimeoutMs: 200000\n'
             '        failOnStartupError: false\n')
    lines = current.splitlines()
    content = [line for line in lines if line.strip() and not line.lstrip().startswith('#')]
    if content == ['[]']:
        current = '\n'.join(line for line in lines if line.strip() != '[]')+'\n'
    elif content and not content[0].startswith('-'):
        raise ValueError('Expected a top-level YAML array; refusing to rewrite this profile')
    backup = write_patch(path, current.rstrip()+'\n'+block)
    return {'installed': True, 'patch': str(path), 'backup': str(backup),
            'namespace': 'mcp__fan__', 'reload': 'The DSH loader watches this patch; restart the harness if tools do not appear.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', default=str(Path.home()/'.dsh'/'profiles'/'web'))
    parser.add_argument('--atlas-persona', action='store_true')
    args = parser.parse_args()
    result = install(args.profile)
    if args.atlas_persona:
        result['atlas_persona'] = install_atlas_persona(args.profile)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
