from shapes import *  # noqa: F403

ICONS = {}


def icon(fn):
    ICONS[fn.__name__.replace('_', '-')] = fn
    return fn


def bowl(y=26, w=18, depth=14):
    return U(ellipse(24, y, w, depth).intersection(box(0, y, 48, 48)), rect(24 - w, y - 2, 2 * w, 4, 2))


def mug(x=9, y=16, w=24, h=27):
    body = rect(x, y, w, h, 4)
    handle = arc(x + w, y + h * 0.45, 6, -80, 80, 3.2)
    return U(body, handle.difference(body))


# MARK: Frühstück

@icon
def cereal():
    b = bowl(27, 18, 15)
    flakes = U(*[circle(x, y, 3.6) for x, y in [(14, 23), (21, 20), (28, 21), (35, 23)]])
    flakes = minus(flakes, *[circle(x, y, 1.1) for x, y in [(14, 23), (21, 20), (28, 21), (35, 23)]])
    spoon = U(line([(31, 22), (42, 7)], 2.4), ellipse(42.5, 6.5, 3, 4.2, 37))
    flakes = flakes.intersection(box(0, 0, 48, 25.6))
    return U(b, over(flakes, spoon, 1.2).difference(b.buffer(1.4)))


@icon
def jam():
    jar = rect(11, 18, 26, 26, 4)
    cloth = poly((8, 18), (40, 18), (37, 10), (31, 12), (24, 9), (17, 12), (11, 10))
    band = rect(10, 15.5, 28, 3, 1.2)
    label = rect(15, 25, 18, 13, 2)
    berry = path(bez((24, 36), (17, 31), (19, 28)) + bez((19, 28), (21, 25.5), (24, 28))[1:] +
                 bez((24, 28), (27, 25.5), (29, 28))[1:] + bez((29, 28), (31, 31), (24, 36))[1:])
    g = gap(jar, label, 1.6)
    g = minus(g, berry)
    return U(over(g, band, 1.2), over(cloth, band, 1.2).difference(band.buffer(1.2)))


@icon
def honey():
    jar = rect(10, 17, 28, 27, 6)
    lid = rect(11, 10, 26, 6, 2)
    drip = U(rect(11, 15, 26, 3, 1), path(bez((14, 17), (15, 23), (17, 23)) + bez((17, 23), (19, 23), (20, 17))[1:]),
             path(bez((26, 17), (27, 26), (29.5, 26)) + bez((29.5, 26), (32, 26), (33, 17))[1:]))
    hexa = Polygon([(24 + 5 * math.cos(math.radians(a)), 32 + 5 * math.sin(math.radians(a))) for a in range(30, 390, 60)])
    jar = minus(jar, drip.buffer(1.4), hexa)
    return U(jar, over(lid, drip, 0.01))


@icon
def spread():
    jar = rect(8, 22, 26, 22, 5)
    lid = rect(9, 15, 24, 5, 2)
    label = rect(12, 28, 18, 10, 2)
    jar = gap(jar, label, 1.6)
    knife = U(rpoly(1, (30, 25), (34, 21), (44, 7), (41, 6)), line([(31, 24), (27, 29)], 3.4))
    return over(U(jar, lid), knife, 1.4)


@icon
def coffee():
    cup = U(rect(10, 18, 24, 18, 2).intersection(box(0, 0, 48, 30)), ellipse(22, 30, 12, 8).intersection(box(0, 30, 48, 48)))
    cup = U(cup, arc(34, 25, 5, -80, 80, 3).difference(rect(10, 18, 24, 20)))
    saucer = rect(5, 39.5, 34, 4, 2)
    steam = U(*[line(bez((x, 14), (x - 2.5, 11), (x + 0.5, 8.5), (x - 1.5, 5)), 1.8) for x in (17, 23, 29)])
    return U(over(saucer, cup, 1.4), steam)


@icon
def tea():
    m = mug(9, 17, 24, 26)
    tag_string = line([(26, 17), (34, 8)], 1.2)
    tag = rect(31.5, 1.5, 7, 8, 1, rot=15)
    m = minus(m, line([(26, 16), (26, 30)], 1.2), rect(23, 29, 6, 7, 1))
    return U(m, tag_string, tag)


@icon
def cocoa():
    m = mug(9, 20, 24, 23)
    cream = U(circle(15, 18, 4.5), circle(21, 15, 5.5), circle(27, 17, 4.5), circle(21, 11, 3.5), rect(10, 17, 22, 4, 1))
    m = minus(m, star(21, 32, 4.2, 1.8, 6))
    return over(m, cream, 1.4)


# MARK: Süßes & Snacks

@icon
def chocolate():
    bar = rect(12, 4, 24, 30, 2.5)
    squares = U(line([(12, 13.5), (36, 13.5)], 1.6), line([(12, 23), (36, 23)], 1.6), line([(24, 4), (24, 34)], 1.6))
    wrapper = path([(10, 26), (13, 29), (16, 26), (19, 29), (22, 26), (25, 29), (28, 26), (31, 29), (34, 26), (38, 29),
                    (38, 44), (10, 44)])
    wrapper = rpoly(0.8, *list(wrapper.exterior.coords)[:-1])
    return rot(over(minus(bar, squares), wrapper, 1.6), -15)


@icon
def cookie():
    c = minus(circle(24, 24, 18), circle(41, 13, 6), circle(35.5, 7, 4))
    chips = U(*[rpoly(0.6, (x - 2, y + 1.5), (x + 2, y + 1.5), (x + 0.5, y - 2)) for x, y in
                [(16, 17), (25, 14), (14, 27), (23, 25), (32, 23), (20, 34), (29, 33)]])
    return minus(c, chips)


@icon
def candy():
    body = ellipse(24, 24, 10.5, 8.5, -25)
    ends = U(rpoly(1, (14, 28), (4, 38), (9, 41.5), (15, 38)), rpoly(1, (34, 20), (44, 10), (39, 6.5), (33, 10)))
    body = minus(body, line([(17, 30), (31, 18)], 1.3).intersection(ellipse(24, 24, 7.5, 6, -25)))
    return over(ends, body, 1.4)


@icon
def chips():
    bag = path([(11, 8)], bez((11, 8), (8, 24), (11, 40))[1:], [(37, 40)], bez((37, 40), (40, 24), (37, 8))[1:])
    crimp = U(*[circle(x, 7.5, 1.6) for x in range(12, 38, 4)], *[circle(x, 40.5, 1.6) for x in range(12, 38, 4)])
    bag = minus(bag, crimp, line([(9, 12), (39, 12)], 1.4), line([(9, 36), (39, 36)], 1.4))
    chip = ellipse(24, 24, 8, 6.5, -20)
    return minus(bag, gap(chip.buffer(1.6), chip, 0.01), chip.boundary.buffer(0.8))


@icon
def nut():
    shell = U(ellipse(18, 30, 9, 10, 35), ellipse(30, 18, 9, 10, 35)).buffer(0)
    waist = minus(shell, ellipse(31.5, 31.5, 4.5, 3, 45), ellipse(16.5, 16.5, 4.5, 3, 45)).buffer(-0.5).buffer(0.5)
    dots = U(*[circle(x, y, 1) for x, y in [(15, 31), (20, 35), (20, 27), (28, 15), (33, 20), (28, 22), (32, 13.5), (16, 37)]])
    return minus(waist, dots)


@icon
def popcorn():
    tub = rpoly(1, (11, 22), (37, 22), (33, 44), (15, 44))
    stripes = U(line([(20.5, 22), (21.5, 44)], 2.2), line([(27.5, 22), (26.5, 44)], 2.2))
    corn = U(*[circle(x, y, 4.6) for x, y in [(13, 18), (20, 14), (27, 13), (34, 17), (17, 9), (24, 7.5), (31, 10)]])
    return over(minus(tub, stripes), corn, 1.4)


@icon
def ice_cream():
    cone = rpoly(1, (14, 24), (34, 24), (24, 46))
    cone = minus(cone, line([(14, 27), (28, 41)], 1.3), line([(34, 27), (20, 41)], 1.3), line([(18, 24), (29, 35)], 1.3), line([(30, 24), (19, 35)], 1.3))
    scoop = U(circle(24, 15, 10), rect(12, 18, 24, 6, 3))
    scoop = minus(scoop, line(bez((14, 21), (18, 23), (22, 20), (26, 23)), 1.4))
    return over(cone, scoop, 1.6)


@icon
def bar():
    b = rect(5, 16, 38, 16, 3, rot=-20)
    oats = U(*[ellipse(x, y, 1.7, 1, -20) for x, y in
                [(13, 29), (18, 25), (24, 24), (30, 21), (35, 19), (16, 31.5), (22, 29), (28, 27), (34, 24), (20, 20.5), (27, 17.5)]])
    ends = U(rot(rect(3, 16, 6, 16, 1), -20), rot(rect(39, 16, 6, 16, 1), -20))
    body = minus(b, oats)
    return gap(body, rot(rect(9.5, 10, 29, 28, 0), -20), 1.6)


@icon
def cracker():
    base = rect(8, 8, 32, 32, 3)
    edge = U(*[circle(x, y, 1.8) for x in (8, 40) for y in range(12, 40, 6)], *[circle(x, y, 1.8) for y in (8, 40) for x in range(12, 40, 6)])
    holes = U(*[circle(x, y, 1.3) for x in (16, 24, 32) for y in (16, 24, 32)])
    return minus(base, edge, holes)


# MARK: Getränke

@icon
def water():
    body = rect(14, 15, 20, 30, 5)
    neck = poly((15, 17), (33, 17), (28, 10), (20, 10))
    cap = rect(19, 4, 10, 5, 1.5)
    waves = U(line([(12, 23), (36, 23)], 1.6), line([(12, 37), (36, 37)], 1.6))
    drop = path(bez((24, 25.5), (19.5, 31), (22, 33.5)) + bez((22, 33.5), (24, 35), (26, 33.5))[1:] + bez((26, 33.5), (28.5, 31), (24, 25.5))[1:])
    return over(minus(U(body, neck), waves, drop), cap, 1.4)


@icon
def juice():
    box_ = rect(10, 14, 24, 30, 2)
    top = poly((10, 14), (34, 14), (38, 10), (14, 10))
    side = poly((35.5, 13.5), (39, 10), (39, 40), (35.5, 43.5))
    straw = U(line([(27, 12), (27, 6), (35, 2)], 2.4))
    fruit = U(circle(22, 30, 6), leaf(25.5, 22, 5, 3, -40))
    g = U(box_, top)
    g = minus(g, fruit)
    return U(g, side, straw.difference(g.buffer(1.4)))


@icon
def soda():
    can = rect(12, 8, 24, 36, 4)
    rims = U(line([(10, 13), (38, 13)], 1.6), line([(10, 39), (38, 39)], 1.6))
    wave = line(bez((10, 28), (18, 20), (28, 34), (38, 24)), 1.8)
    tab = U(rect(20, 3.5, 8, 4, 1.5))
    return U(minus(can, rims, wave), tab.difference(can.buffer(1.4)))


@icon
def beer():
    glass = rect(9, 16, 24, 28, 3)
    foam = U(circle(12, 15, 4.5), circle(19, 12, 5.5), circle(26, 12.5, 5), circle(32, 15.5, 4), rect(8, 13, 26, 6, 2))
    handle = arc(33, 28, 6.5, -80, 80, 3.4).difference(glass)
    bubbles = U(line([(16, 25), (16, 38)], 1.6), line([(22, 25), (22, 38)], 1.6), line([(28, 25), (28, 38)], 1.6))
    return U(over(minus(glass, bubbles), foam, 1.4), handle)


@icon
def wine():
    bottle = U(rect(6, 22, 14, 22, 3), rect(10.5, 6, 5, 18, 1), poly((7, 25), (19, 25), (15.5, 18), (10.5, 18)))
    bottle = minus(bottle, rect(8.5, 30, 9, 8, 1))
    glass = U(path(bez((26, 14), (25, 30), (34, 30)) + bez((34, 30), (43, 30), (42, 14))[1:]),
              line([(34, 30), (34, 41)], 2.2), rect(28, 40, 12, 3, 1.5))
    glass = minus(glass, line([(25.5, 21), (42.5, 21)], 1.4))
    return over(bottle, glass, 1.6)


@icon
def sparkling():
    def flute(cx, a):
        cup = path(bez((cx - 5, 8), (cx - 5.5, 26), (cx, 27)) + bez((cx, 27), (cx + 5.5, 26), (cx + 5, 8))[1:])
        cup = minus(cup, line([(cx - 6, 14), (cx + 6, 14)], 1.4))
        g = U(cup, line([(cx, 27), (cx, 39)], 2), rect(cx - 5, 38.5, 10, 2.8, 1.2))
        return rot(g, a, cx, 39)
    bubbles = U(circle(24, 6, 1.4), circle(21.5, 2.8, 1), circle(26.5, 3, 0.9))
    return U(over(flute(16, -12), flute(32, 12), 1.6), bubbles)


@icon
def spirits():
    glass = U(poly((7, 10), (41, 10), (24, 27)), line([(24, 27), (24, 40)], 2.2), rect(16, 39.5, 16, 3, 1.5))
    glass = minus(glass, line([(10, 15), (38, 15)], 1.4))
    olive = U(circle(30, 19, 3.6), line([(20, 6), (31, 19)], 1.3))
    return U(over(glass, olive, 1.4), line([(15, 2), (20.5, 6.5)], 1.3))


@icon
def matcha():
    handle = rect(20.5, 3, 7, 15, 2)
    bulb = path(bez((19, 17), (8, 28), (16, 38)), bez((16, 38), (24, 46), (32, 38))[1:], bez((32, 38), (40, 28), (29, 17))[1:])
    tines = U(*[line([(24 + dx * 0.15, 21), (24 + dx, 39)], 1.3) for dx in (-9, -4.5, 0, 4.5, 9)])
    bulb = minus(bulb, tines)
    return over(bulb, handle, 1.4)
