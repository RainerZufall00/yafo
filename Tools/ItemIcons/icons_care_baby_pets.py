from shapes import *  # noqa: F403

ICONS = {}


def icon(fn):
    ICONS[fn.__name__.replace('_', '-')] = fn
    return fn


# MARK: Drogerie

@icon
def toothpaste():
    handle = rect(4, 30, 30, 5.5, 2.75, rot=-35)
    head = rect(25, 13, 15, 7, 2, rot=-35)
    bristles = U(*[rot(rect(26 + i * 3.3, 6, 2.2, 7, 0.8), -35, 32.5, 16.5) for i in range(4)])
    paste = U(*[circle(x, y, 2.6) for x, y in [(27, 5.5), (31, 4), (35, 3.5), (39, 5)]])
    paste = U(rot(paste, 0), rot(rect(26, 3, 14, 4, 2), -10, 33, 5))
    g = U(over(handle, head, 1.4), bristles.difference(head.buffer(1.2)))
    return U(g, rot(paste, -35, 32.5, 16.5).difference(g.buffer(1.4)))


@icon
def shampoo():
    b = rpoly(5, (12, 16), (36, 16), (38, 44), (10, 44))
    cap = U(rect(15, 8, 18, 6.5, 2), rect(19, 5, 10, 4, 1.2))
    label = rect(15, 23, 18, 14, 3)
    b = gap(b, label, 1.6)
    b = minus(b, path(bez((24, 26), (19, 31), (22, 33.5)) + bez((22, 33.5), (24, 35), (26, 33.5))[1:] + bez((26, 33.5), (29, 31), (24, 26))[1:]))
    return over(b, cap, 1.4)


@icon
def soap():
    bar = rect(6, 21, 32, 19, 7)
    bar = minus(bar, line(bez((12, 27), (14, 25), (17, 25)), 1.6))
    bubbles = U(circle(35, 14, 6), circle(25, 13, 4), circle(41, 24, 3), circle(29, 5.5, 2.4))
    bubbles = minus(bubbles, arc(35, 14, 3.4, 200, 260, 1.2))
    return over(bar, bubbles, 1.6)


@icon
def razor():
    head = rect(9, 7, 30, 9, 2.5)
    head = minus(head, line([(9, 11.5), (39, 11.5)], 1.4))
    neck = rect(21, 17.5, 6, 4, 1)
    handle = rect(20.5, 22, 7, 23, 3.5)
    handle = minus(handle, line([(20, 30), (28, 30)], 1.2), line([(20, 34), (28, 34)], 1.2))
    return U(head, neck, handle)


@icon
def deodorant():
    cap = U(rect(15, 6, 18, 10, 6).intersection(box(0, 0, 48, 13)), rect(15, 10, 18, 5, 1))
    body = rect(15, 16.6, 18, 28, 2.5)
    label = rect(18, 24, 12, 13, 2)
    body = gap(body, label, 1.4)
    return U(cap, body)


@icon
def bandage():
    strip = rect(3, 16, 42, 16, 8, rot=-40)
    pad = rot(rect(16, 17, 16, 14, 2), -40)
    holes = U(*[circle(x, y, 1) for x, y in [(21, 22), (27, 22), (21, 27), (27, 27)]])
    holes = rot(move(holes, 0, -0.5), -40)
    holes = U(*[circle(24 + dx, 24 + dy, 1) for dx, dy in [(-2.5, -2.5), (2.5, -2.5), (-2.5, 2.5), (2.5, 2.5)]])
    return minus(gap(strip, pad, 1.6), holes, line([(5, 34), (8, 38)], 0.01))


@icon
def pills():
    cap = rect(4, 18, 30, 12, 6, rot=-40)
    cap = minus(cap, rot(line([(19, 17), (19, 31)], 1.8), -40, 19, 24))
    pill = circle(33, 33, 9)
    pill = minus(pill, line([(26, 40), (40, 26)], 1.8))
    return over(cap, pill, 1.6)


@icon
def sunscreen():
    tube = rpoly(2, (14, 8), (34, 8), (31, 38), (17, 38))
    cap = rect(18, 39.5, 12, 6, 1.5)
    crimp = line([(14, 12), (34, 12)], 1.4)
    sun = U(circle(24, 24, 4.2), *[line([(24 + 6.3 * math.cos(math.radians(a)), 24 + 6.3 * math.sin(math.radians(a))),
                                         (24 + 9 * math.cos(math.radians(a)), 24 + 9 * math.sin(math.radians(a)))], 1.6)
                                   for a in range(0, 360, 45)])
    return U(minus(tube, crimp, sun), cap)


@icon
def pad():
    body = U(rect(17, 5, 14, 38, 7), ellipse(24, 24, 15, 7)).buffer(1).buffer(-1)
    inner = rect(20.5, 10, 7, 28, 3.5)
    drops = U(circle(24, 18, 1.4), circle(24, 24, 1.4), circle(24, 30, 1.4))
    return minus(gap(body, inner, 1.4), drops)


@icon
def cotton():
    pads = U(ellipse(18, 33, 13, 5), ellipse(18, 26.5, 13, 5), ellipse(18, 20, 13, 5))
    stacked = over(over(ellipse(18, 33, 13, 5), ellipse(18, 26.5, 13, 5), 1.4), ellipse(18, 20, 13, 5), 1.4)
    stacked = minus(stacked, circle(18, 20, 1.2), circle(13, 21, 1), circle(23, 19, 1))
    swab = U(line([(33, 42), (41, 8)], 1.8), ellipse(32.6, 43, 2.6, 4, 14), ellipse(41.3, 7, 2.6, 4, 14))
    return over(stacked, swab, 1.4)


@icon
def pump():
    b = rect(12, 22, 24, 22, 4)
    collar = rect(17, 17, 14, 4, 1.2)
    stem = rect(22, 11, 4, 6, 0.5)
    head = U(rect(18, 6.5, 16, 4.5, 1.5), rect(30, 8.5, 9, 2.5, 1))
    label = rect(15, 27, 18, 11, 2)
    b = gap(b, label, 1.4)
    return U(over(b, collar, 1.2), stem, head)


@icon
def cream_jar():
    jar = rect(8, 26, 32, 17, 5)
    lid = rect(7, 18, 34, 6.5, 2.5)
    swirl = U(circle(24, 13, 5.5), ellipse(24, 16, 10, 3.5))
    jar = minus(jar, line([(8, 33), (40, 33)], 1.4))
    swirl = minus(swirl, arc(24, 13, 2.6, 180, 360, 1.3))
    return U(over(jar, lid, 1.4), swirl.difference(lid.buffer(1.4)))


@icon
def makeup():
    base = rect(15, 28, 18, 17, 2)
    sleeve = rect(17, 19.5, 14, 7, 1)
    stick = path([(19, 18), (19, 9), (29, 3), (29, 18)])
    stick = rpoly(1.2, (19, 18), (19, 10), (29, 4), (29, 18))
    base = minus(base, line([(15, 34), (33, 34)], 1.4))
    return U(base, over(sleeve, stick, 1.4))


@icon
def comb():
    spine = rect(5, 14, 38, 8, 3)
    teeth = U(*[rect(x, 22, 2.2, 13 if i % 2 == 0 else 10, 1) for i, x in enumerate(range(8, 41, 4))])
    return rot(U(spine, teeth), -20)


@icon
def mask():
    body = rpoly(2, (12, 14), (36, 14), (40, 20), (40, 30), (34, 36), (14, 36), (8, 30), (8, 20))
    pleats = U(line([(9, 21), (39, 21)], 1.5), line([(9, 26.5), (39, 26.5)], 1.5))
    straps = U(arc(8, 25, 6, 90, 270, 2), arc(40, 25, 6, -90, 90, 2))
    return U(minus(body, pleats), straps.difference(body))


@icon
def insect():
    body = U(ellipse(24, 30, 3.4, 10), circle(24, 17, 4))
    wings = U(ellipse(15, 18, 9, 4.5, 25), ellipse(33, 18, 9, 4.5, -25))
    legs = U(*[line([(24, 26 + i * 4), (24 + s * 10, 30 + i * 6)], 1.4) for i in range(3) for s in (-1, 1)])
    sting = line([(24, 13), (24, 4)], 1.4)
    g = over(U(legs, sting), body, 1.2)
    return over(g, wings, 1.4).difference(body.buffer(1.4).difference(body)) if False else U(over(U(legs, sting, body), wings, 1.2), body)


# MARK: Baby

@icon
def diaper():
    body = path([(6, 13), (42, 13), (42, 19)], bez((42, 19), (42, 31), (34, 40))[1:],
                bez((34, 40), (24, 46), (14, 40))[1:], bez((14, 40), (6, 31), (6, 19))[1:])
    body = minus(body, line([(4, 18.5), (44, 18.5)], 1.8), star(24, 28, 5, 2.2))
    tabs = U(rect(2.5, 15, 8, 9, 2), rect(37.5, 15, 8, 9, 2))
    return over(body, tabs, 1.6)


@icon
def wipes():
    pack = rect(4, 18, 40, 22, 6)
    flap = ellipse(24, 23.5, 11, 4.5)
    pack = gap(pack, flap, 1.6)
    wipe = path(bez((17, 23), (15, 13), (22, 9)) + bez((22, 9), (26, 14), (31, 8))[1:] + bez((31, 8), (33, 16), (31, 23))[1:])
    pack = minus(pack, line(bez((10, 34), (17, 31), (24, 34), (31, 31)) + bez((31, 31), (35, 29.5), (38, 32))[1:], 1.4))
    return U(pack, wipe.difference(pack.buffer(1.4)).difference(flap.buffer(-1.2)))


@icon
def baby_bottle():
    nipple = U(ellipse(24, 8.5, 4, 5.5), rect(19, 10, 10, 4, 1))
    ring = rect(15, 14.5, 18, 5, 1.5)
    body = rect(14, 21, 20, 23, 5)
    marks = U(line([(14, 28), (22, 28)], 1.4), line([(14, 33), (20, 33)], 1.4), line([(14, 38), (22, 38)], 1.4))
    return U(nipple, ring, minus(body, marks))


@icon
def pouch():
    bag = path([(12, 18)], bez((12, 18), (8, 32), (11, 44))[1:], [(37, 44)], bez((37, 44), (40, 32), (36, 18))[1:])
    bag = rpoly(2, *list(bag.exterior.coords)[:-1])
    shoulder = poly((13, 19), (35, 19), (27, 12), (21, 12))
    cap = rect(19.5, 4, 9, 7, 1.5)
    fruit = U(circle(24, 32, 5.5), leaf(27, 24.5, 6, 3.4, -40))
    g = minus(U(bag, shoulder), fruit)
    return over(g, cap, 1.4)


@icon
def baby_food():
    jar = rect(11, 19, 22, 25, 4)
    lid = rect(12, 12, 20, 5.5, 2)
    label = rect(14, 25, 16, 13, 2)
    jar = gap(jar, label, 1.4)
    heart = path(bez((22, 35.5), (16, 31), (18, 28)) + bez((18, 28), (20, 26), (22, 28.5))[1:] +
                 bez((22, 28.5), (24, 26), (26, 28))[1:] + bez((26, 28), (28, 31), (22, 35.5))[1:])
    jar = minus(jar, heart)
    spoon = U(line([(35, 44), (38, 18)], 2.4), ellipse(38.6, 13, 3.2, 5, 7))
    return U(over(U(jar, lid), spoon, 1.4))


# MARK: Tiere

@icon
def cat():
    head = U(ellipse(24, 28, 16, 13.5), poly((9, 24), (11, 7), (22, 16)), poly((39, 24), (37, 7), (26, 16)))
    eyes = U(ellipse(18, 27, 2, 3), ellipse(30, 27, 2, 3))
    nose = poly((22, 32), (26, 32), (24, 34.5))
    whiskers = U(line([(14, 33), (4, 31)], 1.2), line([(14, 35.5), (5, 37)], 1.2), line([(34, 33), (44, 31)], 1.2), line([(34, 35.5), (43, 37)], 1.2))
    g = minus(head, eyes, nose)
    return U(g, whiskers.difference(head.buffer(-0.5)))


@icon
def dog():
    head = U(ellipse(24, 25, 12, 14), ellipse(24, 34, 8.5, 7))
    ears = U(ellipse(10, 22, 5.5, 11, 18), ellipse(38, 22, 5.5, 11, -18))
    g = over(head, ears, 1.6).difference(head.buffer(1.6).difference(head)) if False else over(ears, head, 1.6)
    eyes = U(circle(19, 22, 2), circle(29, 22, 2))
    nose = ellipse(24, 31, 3.6, 2.6)
    mouth = U(line(bez((24, 33.5), (24, 37), (20.5, 37.5)), 1.3), line(bez((24, 33.5), (24, 37), (27.5, 37.5)), 1.3))
    return minus(g, eyes, nose.buffer(1.3).difference(nose), mouth)


@icon
def paw():
    pad_ = path(bez((24, 25), (34, 25), (35, 35)) + bez((35, 35), (36, 42), (29, 41))[1:] + bez((29, 41), (24, 39), (19, 41))[1:] +
                bez((19, 41), (12, 42), (13, 35))[1:] + bez((13, 35), (14, 25), (24, 25))[1:])
    toes = U(ellipse(10.5, 22, 4, 5.2, -25), ellipse(18.5, 13, 4.2, 5.6, -10), ellipse(29.5, 13, 4.2, 5.6, 10), ellipse(37.5, 22, 4, 5.2, 25))
    return U(pad_, toes)


@icon
def bird():
    body = path(bez((8, 22), (10, 10), (20, 11)) + bez((20, 11), (28, 12), (28, 22))[1:] + bez((28, 22), (36, 20), (44, 14))[1:] +
                bez((44, 14), (42, 32), (26, 36))[1:] + bez((26, 36), (14, 38), (10, 28))[1:])
    beak = poly((9, 16), (2, 19), (9, 21))
    eye = circle(16, 17, 1.8)
    wing = path(bez((20, 26), (28, 20), (38, 21)) + bez((38, 21), (32, 31), (20, 26))[1:])
    legs = U(line([(22, 37), (20, 44)], 1.6), line([(28, 36), (29, 44)], 1.6))
    g = minus(U(body, beak), eye, wing.boundary.buffer(0.8, quad_segs=Q))
    return U(g, legs)


@icon
def basket():
    handle = arc(24, 21, 12, 180, 360, 3)
    rim = rect(4, 19, 40, 6, 2)
    body = rpoly(1.5, (7, 26.6), (41, 26.6), (37, 43), (11, 43))
    slots = U(*[line([(x, 30), (x + (x - 24) * 0.12, 39)], 2) for x in (14, 20, 26, 32)])
    return U(handle.difference(rim.buffer(1.4)), rim, minus(body, slots))


@icon
def eye_drops():
    body = rect(13, 22, 22, 22, 4)
    shoulder = poly((14, 25), (34, 25), (29, 17), (19, 17))
    nozzle = rpoly(0.5, (20.5, 17.5), (27.5, 17.5), (25, 4), (23, 4))
    eye = circle(24, 26.6, 10.9).intersection(circle(24, 41.4, 10.9))
    body = minus(U(body, shoulder), eye)
    return U(over(body, nozzle, 1.4), circle(24, 34, 2.2))


@icon
def condom():
    pack = rect(8, 8, 32, 32, 2.5)
    notches = U(*[circle(x, y, 1.1) for i in range(1, 8) for x, y in
                  [(8 + i * 4, 8), (8 + i * 4, 40), (8, 8 + i * 4), (40, 8 + i * 4)]])
    pack = minus(pack, notches)
    ring = U(circle(24, 24, 10.5).boundary.buffer(0.9, quad_segs=Q), circle(24, 24, 7).boundary.buffer(0.9, quad_segs=Q))
    return minus(pack, ring)


@icon
def rabbit():
    head = U(ellipse(24, 32, 13, 11))
    ears = U(ellipse(18, 14, 4.5, 11.5, -12), ellipse(30, 14, 4.5, 11.5, 12))
    inner = U(ellipse(18, 14, 1.6, 7.5, -12), ellipse(30, 14, 1.6, 7.5, 12))
    g = over(minus(ears, inner), head, 1.6)
    eyes = U(circle(19, 30, 1.9), circle(29, 30, 1.9))
    nose = poly((22, 35), (26, 35), (24, 37.5))
    return minus(g, eyes, nose)
