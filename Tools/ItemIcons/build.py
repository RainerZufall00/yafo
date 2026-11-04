"""Erzeugt die Artikel-Icons als Template-Imagesets in App/Resources/Assets.xcassets/Items.

    python3 Tools/ItemIcons/build.py            # alle Icons schreiben
    python3 Tools/ItemIcons/build.py --preview out.html   # zusätzlich Kontaktbogen

Braucht shapely (pip install shapely). Die Icons selbst stehen in icons_*.py."""
import importlib
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from shapes import svg  # noqa: E402

MODULES = ['icons_produce', 'icons_bakery_meat_dairy', 'icons_pantry', 'icons_breakfast_snacks_drinks',
           'icons_frozen_household', 'icons_care_baby_pets']
OUT = HERE.parent.parent / 'App/Resources/Assets.xcassets/Items'


def load():
    icons = {}
    for name in MODULES:
        try:
            module = importlib.import_module(name)
        except ModuleNotFoundError as error:
            if error.name == name:
                continue
            raise
        for key, fn in module.ICONS.items():
            assert key not in icons, f'doppelt: {key}'
            icons[key] = fn
    return icons


def write(icons):
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
    for key, fn in sorted(icons.items()):
        folder = OUT / f'item-{key}.imageset'
        folder.mkdir(exist_ok=True)
        (folder / f'item-{key}.svg').write_text(svg(fn()))
        (folder / 'Contents.json').write_text(json.dumps({
            'images': [{'filename': f'item-{key}.svg', 'idiom': 'universal'}],
            'info': {'author': 'xcode', 'version': 1},
            'properties': {'preserves-vector-representation': True, 'template-rendering-intent': 'template'},
        }, indent=2) + '\n')


def preview(icons, target, only=None, zoom=1):
    colors = ['#2E9E52', '#C98A1E', '#D9483B', '#2F80ED', '#E07A1F', '#9C6B3E', '#D6457F', '#00A096',
              '#2D8FCB', '#8E44C9', '#5B6CFF', '#C95B8C', '#7B5E52']
    cells = []
    keys = [k for k in icons if not only or k in only]
    for i, key in enumerate(keys):
        s = svg(icons[key]()).replace('fill="#000000"', 'fill="currentColor"')
        big = s.replace('width="48" height="48"', f'width="{44 * zoom}" height="{44 * zoom}"')
        small = s.replace('width="48" height="48"', 'width="20" height="20"')
        c = colors[i % len(colors)]
        cells.append(f'<div class="c"><div class="t" style="background:{c}">{big}</div>'
                     f'<div class="l" style="color:{c}">{big}{small}</div><span>{key}</span></div>')
    html = ('<!doctype html><meta charset="utf-8"><style>body{margin:12px;font:11px -apple-system,Helvetica;'
            'display:flex;flex-wrap:wrap;gap:8px}.c{width:' + str(118 * zoom) + 'px;display:flex;flex-direction:column;align-items:center;gap:3px}'
            '.c>div{display:flex;align-items:center;justify-content:center;gap:6px}'
            '.t{width:' + str(112 * zoom) + 'px;height:' + str(58 * zoom) + 'px;border-radius:12px;color:#fff}'
            '.l{width:' + str(112 * zoom) + 'px;height:' + str(52 * zoom) + 'px;border-radius:12px;'
            'background:#f2f2f5}span{color:#444}</style>' + ''.join(cells))
    pathlib.Path(target).write_text(html)


if __name__ == '__main__':
    icons = load()
    write(icons)
    if '--preview' in sys.argv:
        i = sys.argv.index('--preview')
        only = sys.argv[i + 2].split(',') if len(sys.argv) > i + 2 and sys.argv[i + 2] != '-' else None
        zoom = int(sys.argv[i + 3]) if len(sys.argv) > i + 3 else 1
        preview(icons, sys.argv[i + 1], only, zoom)
    print(f'{len(icons)} Icons')
