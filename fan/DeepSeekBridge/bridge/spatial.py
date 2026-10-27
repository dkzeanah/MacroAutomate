"""Coordinate-preserving spatial metadata; no pixel edits or semantic guesses."""


def zones(region):
    if not region.get('w') or not region.get('h'):
        return {'zones': [], 'sections': [], 'created_before_ocr': False, 'warning': 'No trustworthy image/window dimensions'}
    items = []
    for row, vertical in enumerate(('top', 'middle', 'bottom')):
        for col, horizontal in enumerate(('left', 'center', 'right')):
            x = region.get('x', 0) + region['w'] * col // 3
            y = region.get('y', 0) + region['h'] * row // 3
            items.append({'id': vertical + '-' + horizontal, 'bounds': {'x': x, 'y': y,
                          'w': region.get('x', 0) + region['w'] * (col + 1) // 3 - x,
                          'h': region.get('y', 0) + region['h'] * (row + 1) // 3 - y}, 'source_kind': 'geometric_partition'})
    return {'zones': items, 'sections': [], 'created_before_ocr': False,
            'note': 'Partition established before model textual analysis; legacy/pasted evidence does not prove native zoning preceded recognition. Zone labels do not establish semantic sections.'}
