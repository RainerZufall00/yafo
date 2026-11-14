from shapes import *  # noqa: F403

ICONS = {}


def icon(fn):
    ICONS[fn.__name__.replace('_', '-')] = fn
    return fn


def cube(x, y, s, g=1.6):
    """Würfel in Iso-Ansicht, Oberkante mittig bei (x, y)."""
    top = poly((x, y), (x + s, y + s * 0.5), (x, y + s), (x - s, y + s * 0.5))
    left = poly((x - s, y + s * 0.5 + g), (x - g / 2, y + s + g * 0.9), (x - g / 2, y + 2 * s), (x - s, y + 1.5 * s))
    right = poly((x + s, y + s * 0.5 + g), (x + g / 2, y + s + g * 0.9), (x + g / 2, y + 2 * s), (x + s, y + 1.5 * s))
    return U(top, left, right)


# MARK: Tiefkühl

@icon
def pizza():
    slice_ = rpoly(1.5, (24, 45), (6, 9), (42, 9))
    crust = gap(slice_, slice_.intersection(box(0, 14, 48, 48)), 1.6)
    peps = U(circle(19, 21, 3.2), circle(29, 20, 3), circle(24, 31, 3), circle(31.5, 28, 1.6), circle(16.5, 27.5, 1.4))
    return minus(crust, peps)


@icon
def fries():
    box_ = path(bez((11, 22), (12, 34), (16, 44)) + [(32, 44)] + bez((32, 44), (36, 34), (37, 22))[1:])
    box_ = minus(box_, line(bez((11, 26), (24, 31), (37, 26)), 1.6))
    sticks = U(*[rect(x, y, 4.5, 20, 1.2, rot=a) for x, y, a in [(12, 8, -10), (17.5, 4, -4), (23, 6, 3), (28.5, 5, 8), (33, 9, 14)]])
    return over(sticks.intersection(box(0, 0, 48, 30)), box_, 1.6)


@icon
def frozen():
    arms = []
    for a in range(0, 360, 60):
        r = math.radians(a)
        ex, ey = 24 + 19 * math.cos(r), 24 + 19 * math.sin(r)
        arms.append(line([(24, 24), (ex, ey)], 3))
        for d in (9, 14):
            bx, by = 24 + d * math.cos(r), 24 + d * math.sin(r)
            for s in (-1, 1):
                rr = r + s * math.radians(45)
                arms.append(line([(bx, by), (bx + 5 * math.cos(rr), by + 5 * math.sin(rr))], 2.4))
    return U(*arms)


@icon
def fish_fingers():
    def stick(y):
        g = rect(8, y, 32, 8.5, 3)
        return minus(g, *[circle(x, y + 4.2, 0.9) for x in (14, 20, 26, 32)])
    g = over(over(stick(8), stick(19.5), 1.6), stick(31), 1.6)
    return rot(g, -18)


@icon
def ice_cubes():
    a = rot(cube(16, 18, 10), -12, 16, 28)
    b = rot(cube(32, 10, 10), 10, 32, 20)
    a = minus(a, line([(9, 25), (12, 23.5)], 1.3))
    return over(b, a, 1.6)


@icon
def dumpling():
    base = path(bez((6, 35), (8, 18), (24, 17)) + bez((24, 17), (40, 18), (42, 35))[1:] + bez((42, 35), (24, 41), (6, 35))[1:])
    angles = [-160, -137, -114, -90, -66, -43, -20]
    bumps = U(*[circle(24 + 16 * math.cos(math.radians(a)), 33 + 17 * math.sin(math.radians(a)), 3.6) for a in angles])
    body = U(base, bumps)
    pleats = U(*[line([(24 + 15 * math.cos(math.radians(a)), 33 + 16 * math.sin(math.radians(a))),
                       (24 + 9 * math.cos(math.radians(a)), 33 + 10 * math.sin(math.radians(a)))], 1.4)
                 for a in [(angles[i] + angles[i + 1]) / 2 for i in range(len(angles) - 1)]])
    return minus(body, pleats)


@icon
def ice_pop():
    pop = U(rect(13, 4, 22, 30, 11).intersection(box(0, 0, 48, 25)), rect(13, 14, 22, 20, 2))
    pop = minus(pop, circle(35, 6, 5), line([(19, 12), (19, 28)], 2), line([(25, 12), (25, 28)], 2))
    stick = rect(21, 32, 6, 13, 3)
    return over(stick, pop, 1.6)


# MARK: Haushalt

@icon
def toilet_paper():
    roll = U(rect(8, 10, 20, 24, 0), ellipse(18, 22, 10, 12).intersection(box(0, 0, 18, 48)))
    roll = U(ellipse(8, 22, 5, 12), rect(8, 10, 24, 24), ellipse(32, 22, 5, 12))
    face = ellipse(32, 22, 5, 12)
    sheet = rect(27, 22, 10, 22, 0)
    g = over(roll, face, 1.4)
    g = minus(g, ellipse(32, 22, 1.8, 4.4))
    sheet = rect(32.5, 22, 4.5, 22, 1).difference(face.buffer(0.1))
    sheet = U(rect(27, 33.5, 10, 10.5, 1))
    g = U(g, sheet.difference(g.buffer(1.4)))
    return minus(g, line([(26, 39), (38, 39)], 1.2))


@icon
def paper_towel():
    roll = rect(12, 7, 24, 34, 3)
    roll = minus(roll, line([(10, 18), (38, 18)], 1.4), line([(10, 29), (38, 29)], 1.4))
    stand = U(rect(9, 42, 30, 3.5, 1.5), line([(24, 3), (24, 44)], 2.4).difference(roll.buffer(1.4)))
    knob = circle(24, 4, 2.4)
    return U(roll, stand, knob.difference(roll.buffer(1.4)))


@icon
def sponge():
    scrub = rect(7, 13, 34, 7, 2.5)
    body = rect(7, 21.6, 34, 16, 3)
    holes = U(*[circle(x, y, r) for x, y, r in [(13, 27, 1.6), (20, 32, 1.3), (27, 27, 1.7), (34, 32, 1.4), (17, 34.5, 0.9), (31, 25, 0.9)]])
    bubbles = U(circle(36, 8, 3), circle(41, 5, 1.8))
    return U(scrub, minus(body, holes), bubbles.difference(scrub.buffer(1.4)))


@icon
def dish_soap():
    b = rect(13, 17, 20, 27, 5)
    shoulder = poly((14, 20), (32, 20), (28, 13), (18, 13))
    cap = U(rect(19, 7, 8, 5, 1.2), poly((25, 8), (31, 6), (31, 8.5), (26, 10)))
    drop = path(bez((23, 25), (17.5, 32), (20.5, 35)) + bez((20.5, 35), (23, 37), (25.5, 35))[1:] + bez((25.5, 35), (28.5, 32), (23, 25))[1:])
    bubbles = U(circle(37.5, 13, 3.2), circle(41.5, 21, 2), circle(36, 21.5, 1.4))
    return U(over(minus(U(b, shoulder), drop), cap, 1.4), bubbles)


@icon
def detergent():
    jug = rpoly(3, (8, 14), (32, 14), (40, 22), (40, 44), (8, 44))
    handle = rect(28.5, 16, 8, 11, 2.5)
    cap = rect(10, 7.5, 12, 5, 1.5)
    label = rect(12, 25, 18, 14, 2)
    jug = minus(jug, handle.buffer(-2.2), line([(26, 14), (38, 26)], 0.01))
    jug = gap(jug, label, 1.6)
    return over(jug, cap, 1.4)


@icon
def trash_bag():
    bag = path(bez((15, 17), (5, 28), (9, 41)) + bez((9, 41), (24, 46), (39, 41))[1:] + bez((39, 41), (43, 28), (33, 17))[1:])
    knot = U(rect(19, 12, 10, 6, 2), leaf(16, 7, 10, 5.5, 35), leaf(32, 7, 10, 5.5, -35))
    folds = U(line(bez((17, 23), (15, 30), (16, 38)), 1.4), line(bez((30, 23), (33, 30), (31, 38)), 1.4))
    return over(minus(bag, folds), knot, 1.4)


@icon
def spray():
    body = rect(14, 22, 18, 22, 4)
    neck = rect(17, 15, 12, 6, 1.5)
    head = U(rpoly(1.5, (13, 6), (34, 6), (34, 13), (17, 13)), poly((33.5, 7), (38, 8), (38, 11), (33.5, 12)))
    trigger = rpoly(1, (27, 14), (31, 14), (29.5, 22), (26, 21))
    mist = U(circle(42, 6, 1.1), circle(44.5, 9.5, 1.1), circle(42, 13, 1.1))
    label = rect(17, 28, 12, 10, 1.5)
    g = gap(body, label, 1.4)
    return U(over(U(g, neck), U(head, trigger), 1.4), mist)


@icon
def foil():
    box_ = rect(5, 18, 38, 14, 2.5)
    lid = poly((5, 18), (43, 18), (39, 12), (9, 12))
    sheet = U(poly((9, 32.5), (39, 32.5), (39, 40), (36, 43), (33, 40), (30, 43), (27, 40), (24, 43), (21, 40), (18, 43), (15, 40), (12, 43), (9, 40)))
    serr = U(*[poly((x, 32), (x + 1.5, 29.5), (x + 3, 32)) for x in range(7, 41, 3)])
    g = over(U(box_, lid), sheet, 1.6)
    return minus(g, serr, line([(9, 25), (39, 25)], 1.4))


@icon
def batteries():
    def cell(x, y):
        nub = rect(x + 4.5, y, 5, 3.5, 1)
        body = rect(x, y + 2.5, 14, 36, 3)
        band = line([(x - 1, y + 13), (x + 15, y + 13)], 2)
        return U(nub, minus(body, band))
    back = cell(25, 5)
    front = cell(9, 8)
    plus = U(line([(16, 13), (16, 17.5)], 1.6), line([(13.75, 15.25), (18.25, 15.25)], 1.6))
    return over(back, minus(front, plus), 1.8)


@icon
def light_bulb():
    glass = U(circle(24, 18, 13), poly((15, 25), (33, 25), (30, 33), (18, 33))).buffer(1).buffer(-1)
    glass = minus(glass, arc(24, 18, 8.5, 200, 250, 1.8))
    base = U(rect(18, 34.5, 12, 3, 1), rect(18, 39, 12, 3, 1), rect(20.5, 43.5, 7, 2.5, 1.2))
    return U(glass, base)


@icon
def candle():
    body = rect(15, 20, 18, 25, 2)
    drip = U(rect(15, 20, 18, 4, 1), path(bez((19, 23), (19, 29), (21, 29)) + bez((21, 29), (23, 29), (23, 23))[1:]))
    body = minus(body, drip.buffer(1.4).difference(drip), line([(19, 33), (19, 41)], 1.4))
    flame = path(bez((24, 3), (31, 11), (27, 15)) + bez((27, 15), (24, 17.5), (21, 15))[1:] + bez((21, 15), (17, 11), (24, 3))[1:])
    wick = line([(24, 15), (24, 19)], 1.4)
    return U(body, flame, wick)


@icon
def flower():
    head = U(ellipse(24, 14, 6.5, 9), ellipse(17, 15, 5.5, 8.5, -20), ellipse(31, 15, 5.5, 8.5, 20))
    head = U(head.intersection(box(0, 0, 48, 20)), path(bez((11.5, 15), (12, 24), (24, 24)) + bez((24, 24), (36, 24), (36.5, 15))[1:]))
    head = minus(head, line([(20, 12), (21.5, 22)], 1.4), line([(28, 12), (26.5, 22)], 1.4))
    stem = line([(24, 24), (24, 45)], 2.4)
    leaves = U(leaf(17, 35, 14, 6.5, -130), leaf(31, 37, 12, 6, -50))
    return U(over(stem, head, 1.2), over(leaves, stem, 0.01))


@icon
def cloth():
    back = rect(7, 9, 30, 25, 3, rot=-8)
    front = rect(12, 17, 30, 25, 3, rot=6)
    front = minus(front, rot(line([(12, 33), (42, 33)], 1.6), 6, 27, 29.5), rot(line([(12, 37), (42, 37)], 1.6), 6, 27, 29.5))
    return over(back, front, 1.6)


@icon
def tissues():
    box_ = rect(6, 22, 36, 21, 3)
    slot = ellipse(24, 22, 10, 3)
    tissue = path(bez((15, 23), (13, 14), (19, 9)) + bez((19, 9), (24, 13), (28, 7))[1:] + bez((28, 7), (33, 12), (33, 23))[1:])
    g = minus(box_, slot.buffer(1.4), line([(6, 30), (42, 30)], 0.01))
    g = minus(g, line(bez((10, 36), (17, 32), (24, 36), (31, 32)) + bez((31, 32), (35, 30), (38, 33))[1:], 1.5))
    return U(g, tissue.difference(g.buffer(1.4)))


@icon
def fire():
    flame = path(bez((24, 4), (40, 18), (37, 32)) + bez((37, 32), (34, 44), (24, 44))[1:] +
                 bez((24, 44), (12, 44), (11, 32))[1:] + bez((11, 32), (10, 23), (17, 17))[1:] +
                 bez((17, 17), (17, 24), (21, 25))[1:] + bez((21, 25), (18, 14), (24, 4))[1:])
    inner = path(bez((24, 24), (31, 31), (29, 37)) + bez((29, 37), (27, 41), (24, 41))[1:] +
                 bez((24, 41), (19, 41), (19, 36))[1:] + bez((19, 36), (19, 30), (24, 24))[1:])
    return minus(flame, inner.boundary.buffer(0.8, quad_segs=Q))


@icon
def tape():
    ring = arc(21, 22, 11, 0, 360, 9)
    strip = rpoly(0.5, (32, 22), (42, 22), (42, 40), (40, 38.5), (38, 40), (36, 38.5), (34, 40), (32, 38.5))
    return over(ring, strip, 1.6)


@icon
def gift():
    lid = rect(6, 16, 36, 8, 2)
    box_ = rect(8.5, 25.6, 31, 18, 2)
    ribbon = rect(21.5, 14, 5, 32)
    bow = U(ellipse(18, 11, 6.5, 4, 25), ellipse(30, 11, 6.5, 4, -25))
    bow = minus(bow, ellipse(18, 11, 3, 1.4, 25), ellipse(30, 11, 3, 1.4, -25))
    g = minus(U(lid, box_), ribbon.buffer(1.4).difference(ribbon))
    return U(g, over(bow, circle(24, 12.5, 2.6), 1.2))


@icon
def plant():
    pot = rpoly(1, (13, 30), (35, 30), (32, 45), (16, 45))
    rim = rect(11, 26, 26, 4.5, 1.5)
    leaves = U(leaf(16.5, 17, 16, 8.5, -140), leaf(31.5, 17, 16, 8.5, -40), leaf(24, 12, 18, 8.5, -90))
    veins = U(line([(24, 25), (24, 6)], 1.3), line([(23, 24), (12, 12)], 1.3), line([(25, 24), (36, 12)], 1.3))
    return over(over(pot, rim, 1.4), minus(leaves, veins).difference(rim.buffer(1.4)), 0.01)


@icon
def envelope():
    body = rect(5, 11, 38, 26, 3)
    flap = line([(7, 14), (24, 27), (41, 14)], 1.7)
    sides = U(line([(7, 35), (19, 24)], 1.5), line([(41, 35), (29, 24)], 1.5))
    return minus(body, flap, sides)


@icon
def newspaper():
    back = rect(10, 6, 32, 34, 2)
    page = rect(5, 10, 32, 34, 2.5)
    cuts = U(rect(9, 14, 24, 4.5, 1), rect(9, 22, 11, 9, 1),
             *[line([(23, y), (33, y)], 1.5) for y in (23, 27, 31)],
             *[line([(9.5, y), (32.5, y)], 1.5) for y in (35.5, 39.5)])
    return over(back, minus(page, cuts), 1.6)
