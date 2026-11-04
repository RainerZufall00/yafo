"""Bausteine für die Artikel-Icons: Formen werden mit shapely vereinigt und ausgestanzt
und am Ende als reine Füllpfade (evenodd) ausgegeben. Raster 48 × 48, Inhalt etwa 4…44."""
import math
from shapely import affinity
from shapely.geometry import LineString, MultiPolygon, Point, Polygon, box
from shapely.ops import unary_union

Q = 24  # Segmente pro Viertelkreis


def circle(cx, cy, r):
    return Point(cx, cy).buffer(r, quad_segs=Q)


def ellipse(cx, cy, rx, ry, rot=0):
    e = affinity.scale(Point(0, 0).buffer(1, quad_segs=Q), rx, ry)
    return affinity.translate(affinity.rotate(e, rot, origin=(0, 0)), cx, cy)


def rect(x, y, w, h, r=0, rot=0):
    if r > 0:
        r = min(r, w / 2 - 0.01, h / 2 - 0.01)
        g = box(x + r, y + r, x + w - r, y + h - r).buffer(r, quad_segs=Q)
    else:
        g = box(x, y, x + w, y + h)
    return affinity.rotate(g, rot, origin=(x + w / 2, y + h / 2)) if rot else g


def poly(*pts):
    return Polygon(pts).buffer(0)


def rpoly(r, *pts):
    """Polygon mit runden Ecken."""
    return Polygon(pts).buffer(-r, join_style='mitre').buffer(r, quad_segs=Q)


def bez(p0, p1, p2, p3=None, n=32):
    """Punkte einer quadratischen (3 Punkte) oder kubischen (4 Punkte) Bézierkurve."""
    pts = []
    for i in range(n + 1):
        t = i / n
        if p3 is None:
            x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
            y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
        else:
            x = (1 - t) ** 3 * p0[0] + 3 * (1 - t) ** 2 * t * p1[0] + 3 * (1 - t) * t * t * p2[0] + t ** 3 * p3[0]
            y = (1 - t) ** 3 * p0[1] + 3 * (1 - t) ** 2 * t * p1[1] + 3 * (1 - t) * t * t * p2[1] + t ** 3 * p3[1]
        pts.append((x, y))
    return pts


def path(*segments):
    """Fläche aus aneinandergehängten Punktlisten (z. B. bez(...) + [(x, y)])."""
    pts = []
    for s in segments:
        pts += s if isinstance(s, list) else [s]
    return Polygon(pts).buffer(0)


def line(pts, w, cap='round'):
    return LineString(pts).buffer(w / 2, quad_segs=Q, cap_style=cap, join_style='round')


def arc(cx, cy, r, a0, a1, w, n=48):
    pts = [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
            cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]
    return line(pts, w)


def leaf(cx, cy, l, w, rot=0):
    """Blatt (Spitzoval) mit Länge l und Breite w, Mitte (cx, cy)."""
    h = l / 2
    pts = bez((-h, 0), (0, -w), (h, 0)) + bez((h, 0), (0, w), (-h, 0))[1:]
    g = Polygon(pts)
    return affinity.translate(affinity.rotate(g, rot, origin=(0, 0)), cx, cy)


def star(cx, cy, R, r=None, n=5, rot=-90):
    r = r or R * 0.45
    pts = []
    for i in range(2 * n):
        a = math.radians(rot + i * 180 / n)
        rr = R if i % 2 == 0 else r
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return Polygon(pts)


def U(*gs):
    return unary_union([g for g in gs if g is not None])


def minus(g, *cuts):
    return g.difference(U(*cuts))


def gap(g, cutter, w=1.8):
    """Schneidet entlang der Kontur von `cutter` eine Lücke der Breite w in g."""
    return g.difference(cutter.boundary.buffer(w / 2, quad_segs=Q))


def over(base, top, w=1.8):
    """`top` liegt auf `base`, getrennt durch eine Lücke."""
    return U(base.difference(top.buffer(w, quad_segs=Q)), top)


def mirror(g, cx=24):
    return affinity.scale(g, -1, 1, origin=(cx, 0))


def rot(g, a, cx=24, cy=24):
    return affinity.rotate(g, a, origin=(cx, cy))


def move(g, dx, dy):
    return affinity.translate(g, dx, dy)


def scale(g, s, cx=24, cy=24):
    return affinity.scale(g, s, s, origin=(cx, cy))


def to_path(g):
    g = g.simplify(0.03)
    polys = g.geoms if isinstance(g, MultiPolygon) else [g] if isinstance(g, Polygon) else \
        [p for p in getattr(g, 'geoms', []) if isinstance(p, Polygon)]
    d = []
    for p in polys:
        for ring in [p.exterior, *p.interiors]:
            pts = list(ring.coords)[:-1]
            if len(pts) < 3:
                continue
            d.append('M' + ' L'.join(f'{x:.2f} {y:.2f}' for x, y in pts) + 'Z')
    return ''.join(d)


def svg(g):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">'
            f'<path fill="#000000" fill-rule="evenodd" d="{to_path(g)}"/></svg>\n')
