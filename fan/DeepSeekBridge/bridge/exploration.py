"""Bounded branch-and-return traversal of observed navigation affordances."""
from . import chains


def run(hwnd, invoke, emit=lambda *_: None, menus=True, controls=True, max_branches=8, max_depth=2):
    visited, gaps = [], []
    baseline = invoke('fan_window_probe', {'hwnd': hwnd})
    if baseline.get('ok') != True:
        return baseline
    if not baseline.get('frame', {}).get('foreground'):
        return {'ok': False, 'error': 'Activate and verify the exact target before active exploration'}
    count = 0

    def menu_branch(label, depth, action='open', path=''):
        nonlocal count
        if count >= max_branches:
            return
        count += 1
        branch = (path + ' > ' if path else '') + label
        active = chains.CURRENT.get()
        ctx = {**active, 'branch': branch} if active else None
        with chains.scope(ctx):
            emit('discovery_branch', {'branch': branch, 'phase': 'enter', 'depth': depth, 'hwnd': hwnd})
            entered = False
            try:
                entered = True  # Return tool verifies menu focus, even after an uncertain open.
                observation = invoke('fan_window_menu', {'hwnd': hwnd, 'action': action, 'label': label,'context_path':branch})
                if observation.get('ok') != True or observation.get('menu_open_verified') is False:
                    gaps.append({'branch': branch, 'error': observation.get('error', 'Open was not verified')})
                    return
                visited.append({'branch': branch, 'frame_id': observation.get('frame', {}).get('frame_id'),
                                'items': observation.get('menu_items', []), 'depth': depth})
                if depth < max_depth:
                    for item in observation.get('menu_items', []):
                        if count >= max_branches:
                            break
                        if item.get('has_submenu') and item.get('enabled'):
                            menu_branch(item['label'], depth + 1, 'submenu', branch)
            finally:
                if entered:
                    returned = invoke('fan_window_menu', {'hwnd': hwnd, 'action': 'return', 'all_menus': depth == 1})
                    emit('discovery_branch', {'branch': branch, 'phase': 'return', 'ok': returned.get('ok'), 'hwnd': hwnd})
                    if returned.get('ok') != True:
                        raise ValueError('Could not verify return from menu branch ' + branch)

    try:
        if menus:
            catalog = invoke('fan_window_menu', {'hwnd': hwnd, 'action': 'catalog'})
            for item in catalog.get('menus', []):
                if count >= max_branches:
                    break
                if item.get('enabled') and item.get('has_submenu'):
                    menu_branch(item['label'], 1)
            if not catalog.get('menus'):
                gaps.append({'branch': 'menus', 'error': 'No observed menu bar exposed; no guessed mnemonic keys were sent'})
        if controls:
            # Re-observe after menus: earlier paths/selection are only references.
            probe = invoke('fan_window_probe', {'hwnd': hwnd})
            candidates = [c for c in probe.get('controls', []) if
                          c.get('enabled') and not c.get('selected') and c.get('accessibility_path') and
                          ('tab' in c.get('role', '').lower() and 'list' not in c.get('role', '').lower() or
                           c.get('state', 0) & 0x400)]
            for item in candidates:
                if count >= max_branches:
                    break
                count += 1
                branch = 'Navigation > ' + item.get('name', '')
                emit('discovery_branch', {'branch': branch, 'phase': 'enter', 'hwnd': hwnd})
                observed = invoke('fan_window_probe_item', {'hwnd': hwnd, 'path': item['accessibility_path'], 'label': item['name']})
                if not observed.get('ok'):
                    gaps.append({'branch': branch, 'error': observed.get('error', 'Navigation not verified')})
                    continue
                visited.append({'branch': branch, 'frame_id': observed.get('frame', {}).get('frame_id')})
                target = observed.get('return_target')
                if not target:
                    raise ValueError('Navigation did not retain a return target')
                result = invoke('fan_window_probe_item', {'hwnd': hwnd, 'path': target['path'], 'label': target['label']})
                emit('discovery_branch', {'branch': branch, 'phase': 'return', 'ok': result.get('ok'), 'hwnd': hwnd})
                if not result.get('ok'):
                    raise ValueError('Return target did not verify: ' + target['label'])
    except Exception as exc:
        return {'ok': False, 'visited': visited, 'gaps': gaps, 'error': str(exc)[:800], 'complete_interface': False}
    return {'ok': True, 'visited': visited, 'gaps': gaps, 'branches_attempted': count,
            'complete_interface': False, 'note': 'Only observed menus/submenus, navigation tabs and collapsible branches were probed. Generic command buttons, file leaves and unavailable controls were not invoked.'}
