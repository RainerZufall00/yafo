from shapes import *  # noqa: F403

ICONS = {}


def icon(fn):
    ICONS[fn.__name__.replace('_', '-')] = fn
    return fn


def bottle(x, w, neck_w, top, shoulder, bottom=44, r=3):
    """Flasche: Körper ab `shoulder`, Hals bis `top`."""
    body = rect(x, shoulder, w, bottom - shoulder, r)
    cx = x + w / 2
    neck = U(rect(cx - neck_w / 2, top, neck_w, shoulder - top + 2, 1),
             poly((x + 1, shoulder + 3), (x + w - 1, shoulder + 3), (cx + neck_w / 2, shoulder - 3), (cx - neck_w / 2, shoulder - 3)))
    return U(body, neck)


def bowl(y=26, w=18, depth=14):
    return U(ellipse(24, y, w, depth).intersection(box(0, y, 48, 48)), rect(24 - w, y - 2, 2 * w, 4, 2))


@icon
def spaghetti():
    strands = U(*[line([(8 + i * 3.2, 41), (24 + i * 3.2, 5)], 1.7) for i in range(-1, 5)])
    band = rect(12, 22, 22, 6, 2, rot=-24)
    return over(strands.intersection(box(0, 4, 48, 44)), band, 1.4)


@icon
def rice():
    b = bowl(28)
    mound = U(*[circle(x, y, 4.5) for x, y in [(12, 26), (19, 22), (26, 20), (33, 22), (38, 26), (16, 27), (30, 26)]])
    mound = mound.intersection(box(0, 0, 48, 27))
    grains = U(*[ellipse(x, y, 1.6, 0.9, a) for x, y, a in [(17, 21, -30), (25, 17, 10), (32, 21, 40), (21, 25, 0)]])
    return U(b, minus(mound.difference(b.buffer(1.4)), grains))


@icon
def flour():
    sack = path(bez((13, 15), (8, 30), (10, 43)), [(38, 43)], bez((38, 43), (40, 30), (35, 15))[1:])
    top = U(poly((14, 13), (34, 13), (37, 6), (31, 9), (24, 5), (17, 9), (11, 6)))
    tie = rect(14, 12, 20, 3.5, 1.5)
    ear = U(line([(24, 38), (24, 22)], 1.4), *[leaf(24 + s * 2.4, y, 5, 3, s * 50 - 90) for y in (24, 28, 32) for s in (-1, 1)])
    sack = minus(sack, ear.buffer(0.2))
    return over(U(sack, top), tie, 1.4)


@icon
def salt():
    body = rpoly(2, (13, 20), (35, 20), (37, 44), (11, 44))
    cap = U(ellipse(24, 16, 12, 8).intersection(box(0, 0, 48, 17)), rect(12, 15, 24, 3, 1))
    holes = U(circle(19, 12, 1.2), circle(24, 10.5, 1.2), circle(29, 12, 1.2), circle(21.5, 14.5, 1.1), circle(26.5, 14.5, 1.1))
    label = line([(15, 32), (33, 32)], 1.6)
    return U(minus(body, label), minus(cap, holes))


@icon
def sugar():
    def cube(x, y, s):
        top = poly((x, y - s * 0.5), (x + s, y), (x, y + s * 0.5), (x - s, y))
        left = poly((x - s, y + 1.6), (x - 0.8, y + s * 0.5 + 2), (x - 0.8, y + s * 1.5 + 1), (x - s, y + s + 0.8))
        right = poly((x + s, y + 1.6), (x + 0.8, y + s * 0.5 + 2), (x + 0.8, y + s * 1.5 + 1), (x + s, y + s + 0.8))
        return U(top, left, right)
    return over(over(cube(15, 27, 9), cube(33, 27, 9), 1.4), cube(24, 11, 9), 1.6)


@icon
def oil():
    b = bottle(14, 20, 7, 9, 21)
    cap = rect(19.5, 4, 9, 6, 1.5)
    drop = path(bez((24, 25), (17, 33), (20, 37)) + bez((20, 37), (24, 41), (28, 37))[1:] + bez((28, 37), (31, 33), (24, 25))[1:])
    return over(minus(b, drop), cap, 1.4)


@icon
def vinegar():
    body = U(circle(24, 32, 12), rect(20, 10, 8, 14, 2))
    stopper = U(circle(24, 6.5, 3.6), rect(21, 8, 6, 4, 1))
    handle = arc(36, 26, 5.5, -90, 90, 2.6)
    body = minus(body, line([(14, 33), (34, 33)], 1.6))
    return U(over(body, stopper, 1.4), over(handle, body, 1.4))


@icon
def can():
    body = rect(11, 12, 26, 32, 3)
    top = ellipse(24, 12, 13, 4.5)
    g = U(body, top)
    g = minus(g, ellipse(24, 12, 9.5, 2.4).boundary.buffer(0.7, quad_segs=Q),
              line([(9, 20), (39, 20)], 1.6), line([(9, 37), (39, 37)], 1.6))
    return g


@icon
def beans():
    def bean(cx, cy, a):
        g = minus(ellipse(0, 0, 9, 6), ellipse(0, 6.2, 3.2, 2))
        g = minus(g, ellipse(-3, -2, 2.6, 1.1, -10))
        return move(rot(g, a, 0, 0), cx, cy)
    return over(over(bean(14, 31, -25), bean(34, 31, 25), 1.6), bean(24, 17, 0), 1.6)


@icon
def ketchup():
    body = rpoly(3, (13, 19), (35, 19), (37, 44), (11, 44))
    cap = U(rect(16, 11, 16, 6.5, 2), poly((21, 11), (27, 11), (25.5, 5), (22.5, 5)))
    label = circle(24, 31, 5.5)
    body = gap(body, label, 1.6)
    return over(body, cap, 1.4)


@icon
def mustard():
    body = rect(13, 18, 22, 26, 4)
    shoulder = poly((14, 20), (34, 20), (28, 13), (20, 13))
    nozzle = poly((21, 13), (27, 13), (24.6, 3), (23.4, 3))
    label = rect(16, 26, 16, 10, 2)
    body = gap(U(body, shoulder), label, 1.6)
    return over(body, nozzle, 1.4)


@icon
def soup():
    b = bowl(26, 19, 15)
    b = U(b, rect(16, 39, 16, 4, 1.5))
    steam = U(*[line(bez((x, 21), (x - 3, 17), (x, 13), (x - 2, 8)), 2) for x in (17, 25, 33)])
    return U(over(b, steam, 1.4))


@icon
def baking():
    handle = U(line([(31, 31), (41, 42)], 4.5))
    loops = U(*[ellipse(20, 18, w, 13, -40).boundary.buffer(1.1, quad_segs=Q) for w in (4, 8.5)])
    loops = U(loops, ellipse(20, 18, 0.1, 13, -40).buffer(1.1)).intersection(ellipse(20, 18, 9.6, 14.2, -40))
    return U(loops, handle, circle(29, 28.5, 3))


@icon
def sauce():
    jar = rect(11, 17, 26, 27, 4)
    lid = rect(13, 8, 22, 7, 2)
    label = rect(15, 24, 18, 13, 2)
    jar = gap(jar, label, 1.6)
    jar = minus(jar, leaf(24, 30.5, 10, 6, -30))
    return over(jar, lid, 1.4)


@icon
def cinnamon():
    def stick(cx, cy, a):
        g = rect(-17, -3.8, 34, 7.6, 3.8)
        g = minus(g, arc(-13.2, 0, 2, 90, 360, 1.3), line([(-9, -0.8), (12, -0.8)], 1.2))
        return move(rot(g, a, 0, 0), cx, cy)
    return over(stick(23, 19, -30), stick(25, 30, -30), 1.6)


@icon
def oregano():
    stem = line(bez((24, 44), (23, 32), (27, 6)), 2.2)
    leaves = U(leaf(16.5, 35.5, 14, 10, -25), leaf(31.5, 31, 14, 10, 25), leaf(17.5, 21.5, 12, 8.5, -30),
               leaf(31, 18.5, 12, 8.5, 28), leaf(26.8, 7.5, 10, 7, -80))
    veins = U(line([(11, 37.5), (22, 34)], 1.2), line([(25.5, 30), (37, 33.5)], 1.2),
              line([(13, 23.5), (22.5, 20.5)], 1.1), line([(26, 17.5), (36, 20.5)], 1.1))
    return U(stem, minus(leaves, veins))


@icon
def spice_jar():
    jar = rect(12, 19, 24, 25, 3.5)
    lid = rect(13, 8, 22, 9, 2.5)
    holes = U(*[circle(x, 12.5, 1.1) for x in (18, 22, 26, 30)])
    label = rect(15, 26, 18, 11, 2)
    jar = gap(jar, label, 1.6)
    jar = minus(jar, U(*[circle(x, y, 0.9) for x, y in [(19, 30), (24, 32), (29, 30), (21.5, 34), (26.5, 34)]]))
    return over(jar, minus(lid, holes), 1.4)


@icon
def vanilla():
    pods = U(line(bez((10, 42), (16, 24), (30, 8)), 3.6), line(bez((17, 44), (24, 26), (38, 12)), 3.6))
    pods = minus(pods, line(bez((10, 42), (16, 24), (30, 8)), 0.01).buffer(0.01))
    flower = U(*[leaf(34 + 4.5 * math.cos(math.radians(a)), 31 + 4.5 * math.sin(math.radians(a)), 9, 5.5, a) for a in range(-90, 270, 72)])
    flower = minus(flower, circle(34, 31, 2))
    return over(pods, flower, 1.6)


@icon
def hot_sauce():
    b = bottle(15, 18, 6, 10, 22, r=3)
    cap = rect(19.5, 4, 9, 7.5, 1.5)
    chili = path(bez((20, 28), (19, 38), (29, 40)), bez((29, 40), (24, 35), (24, 28))[1:])
    chili = U(chili.buffer(0.6), line([(21.5, 28.5), (23, 26)], 1.4))
    return over(minus(b, chili.buffer(0.1)), cap, 1.4)


@icon
def pickles():
    jar = rect(11, 15, 26, 29, 5)
    lid = rect(12, 7, 24, 6, 2)
    p1 = rect(14.5, 20, 7, 20, 3.5, rot=-8)
    p2 = rect(22.5, 19, 7, 21, 3.5, rot=6)
    p3 = rect(29, 22, 5, 17, 2.5)
    holes = U(p1, p2, p3).buffer(1.2)
    jar = U(minus(jar, holes), p1.difference(p2.buffer(1.2)), p2, p3.difference(p2.buffer(1.2)))
    return over(jar, lid, 1.4)


@icon
def penne():
    def tube(cx, cy, a, l=30):
        h = l / 2
        body = poly((-h, -6), (h - 3, -6), (h + 3, 6), (-h + 6, 6))
        cap = ellipse(h, 0, 3.2, 6.6, -26)
        g = U(body, cap)
        g = minus(g, ellipse(h, 0, 1.6, 4.3, -26), line([(-h + 3, -1.5), (h - 4, -1.5)], 1.3), line([(-h + 5, 2.5), (h - 3, 2.5)], 1.3))
        return move(rot(g, a, 0, 0), cx, cy)
    return over(tube(19, 20, -50), tube(28, 28, -15), 1.8)


@icon
def fusilli():
    segs = []
    for i in range(6):
        y = 9 + i * 6
        seg = path(bez((15, y + 3), (17, y - 4), (26, y - 2)) + bez((26, y - 2), (33, y - 1), (33, y - 4))[1:] +
                   bez((33, y - 4), (32, y + 4), (24, y + 3))[1:] + bez((24, y + 3), (17, y + 2), (15, y + 3))[1:])
        segs.append(seg)
    g = segs[0]
    for seg in segs[1:]:
        g = over(g, seg, 1.5)
    return rot(g, 30)


@icon
def noodles():
    b = bowl(28, 18, 14)
    noodles = U(*[line(bez((x, 27), (x - 3, 21), (x + 2, 16), (x - 1, 10)), 1.8) for x in (17, 22, 27)])
    sticks = U(line([(25, 6), (43, 15)], 2.4), line([(25, 11), (44, 20)], 2.4))
    return U(b, noodles.difference(b.buffer(1.4)), over(noodles, sticks, 1.2).difference(noodles.buffer(1.2)).intersection(sticks))


@icon
def grain():
    stem = line(bez((24, 44), (24, 30), (25, 10)), 2)
    kernels = U(*[leaf(24 + s * 4, y, 9, 5, -90 + s * 40) for y in (16, 22, 28) for s in (-1, 1)], leaf(25, 9, 9, 5, -88))
    return U(over(stem, kernels, 1.2), line([(24.6, 6), (25, 2)], 1.2))


@icon
def onigiri():
    tri = rpoly(6, (24, 6), (43, 40), (5, 40))
    nori = rect(16, 27, 16, 14, 1)
    return over(tri, nori, 1.6)


@icon
def stock_cube():
    top = poly((24, 9), (41, 16), (24, 23), (7, 16))
    left = poly((7, 18.5), (22.8, 25.5), (22.8, 42), (7, 35))
    right = poly((41, 18.5), (25.2, 25.5), (25.2, 42), (41, 35))
    g = U(top, left, right)
    return minus(g, line([(15, 22), (15, 38)], 1.6), line([(33, 22), (33, 38)], 1.6), line([(16, 12.5), (32, 19.5)], 1.6))


@icon
def taco():
    shell = minus(circle(24, 18, 20).intersection(box(0, 18, 48, 48)), circle(24, 12, 18))
    shell = U(shell)
    fill = U(*[circle(x, y, 4.2) for x, y in [(10, 25), (16, 21), (23, 19.5), (30, 20), (37, 22.5)]],
             circle(24, 12, 17.9).intersection(box(0, 22, 48, 48)))
    fill = fill.intersection(circle(24, 18, 19.5))
    return over(fill, shell, 1.6)


@icon
def stevia():
    body = rect(9, 18, 23, 26, 6)
    button = rect(14.5, 9, 12, 7, 2.5)
    body = minus(body, leaf(20.5, 31, 13, 7.5, -55).boundary.buffer(0.8, quad_segs=Q), line([(15, 39), (19, 34)], 1.4))
    tabs = U(circle(38.5, 27, 3.4), circle(39.5, 37.5, 3.4))
    return U(over(body, button, 1.4), tabs)


@icon
def protein():
    tub = rect(10, 17, 28, 27, 3)
    lid = rect(8, 9, 32, 7.5, 2.5)
    bell = U(rect(17, 29, 14, 2.2), rect(15, 25.5, 3.2, 9.2, 1), rect(29.8, 25.5, 3.2, 9.2, 1),
             rect(12.5, 27.2, 2.6, 5.8, 1), rect(32.9, 27.2, 2.6, 5.8, 1))
    return over(minus(tub, bell), lid, 1.4)
