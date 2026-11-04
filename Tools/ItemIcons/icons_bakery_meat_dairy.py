from shapes import *  # noqa: F403

ICONS = {}


def icon(fn):
    ICONS[fn.__name__.replace('_', '-')] = fn
    return fn


# MARK: Brot & Backwaren

@icon
def bread():
    slice_ = U(circle(16, 17, 8.5), circle(32, 17, 8.5), rect(9, 15, 30, 27, 3)).buffer(0.5).buffer(-0.5)
    return gap(slice_, slice_.buffer(-3.6), 1.6)


@icon
def bread_round():
    loaf = U(ellipse(24, 28, 19, 13).intersection(box(0, 0, 48, 36)), rect(5, 31, 38, 6, 3))
    cuts = U(*[line([(x, 21), (x + 6, 30)], 1.8) for x in (13, 21, 29)])
    return minus(loaf, cuts)


@icon
def baguette():
    g = rect(3, 18, 42, 11, 5.5, rot=-30)
    cuts = U(*[line([(x - 3, y + 3), (x + 3.5, y - 2.5)], 1.8) for x, y in [(14, 33), (21, 28.5), (28, 24), (35, 19.5)]])
    cuts = rot(cuts, 12, 24, 24)
    return minus(g, cuts)


@icon
def roll():
    g = U(ellipse(24, 27, 17, 12.5).intersection(box(0, 0, 48, 34)), rect(7, 30, 34, 6, 3))
    return minus(g, line(bez((13, 23), (24, 17), (35, 23)), 2))


@icon
def pretzel():
    w = 4.4
    lobe_l = arc(16.5, 22, 9, 60, 330, w)
    lobe_r = arc(31.5, 22, 9, -150, 120, w)
    a = line([(21, 29.8), (33.5, 41)], w)
    b = line([(27, 29.8), (14.5, 41)], w)
    top = line([(18, 13), (24, 18.5), (30, 13)], w)
    g = over(U(lobe_l, lobe_r, top, b), a, 1.4)
    salt = U(circle(10, 22, 0.8), circle(38, 22, 0.8), circle(16, 14, 0.8), circle(32, 14, 0.8))
    return minus(g, salt)


@icon
def flatbread():
    g = ellipse(24, 25, 19, 13, -10)
    spots = U(*[ellipse(x, y, 2.2, 1.4, -10) for x, y in [(15, 21), (24, 18), (33, 21), (19, 28), (29, 28), (24, 33), (11, 28), (37, 27)]])
    return minus(g, spots)


@icon
def cake():
    base = poly((7, 41), (41, 41), (41, 23), (7, 31))
    layers = U(line([(5, 35.5), (43, 32.5)], 1.6), line([(5, 31), (43, 27)], 0.01))
    base = minus(base, line([(5, 36), (43, 34)], 1.6))
    cream = U(circle(35, 21.5, 3.5), circle(29.5, 23, 3.2))
    cherry = U(circle(35, 14, 3.6), line(bez((35, 11), (35, 7), (38, 5)), 1.3))
    return over(over(base, cream, 1.4), cherry, 1.4)


@icon
def burger_bun():
    top = U(ellipse(24, 23, 18, 12).intersection(box(0, 0, 48, 25)), rect(6, 22, 36, 4, 2))
    seeds = U(*[ellipse(x, y, 1.4, 0.8, a) for x, y, a in [(17, 17, -20), (24, 15, 0), (31, 17, 20), (20.5, 21, -10), (27.5, 21, 10)]])
    bottom = rect(7, 30, 34, 9, 4)
    return U(minus(top, seeds), bottom)


@icon
def crispbread():
    def slice_(x, y, a):
        g = rect(x, y, 26, 18, 2.5, rot=a)
        dots = U(*[circle(x + 5 + i * 5.3, y + 4.5 + j * 4.5, 0.9) for i in range(4) for j in range(3)])
        return minus(g, rot(dots, a, x + 13, y + 9))
    return over(slice_(5, 10, -8), slice_(17, 21, 6), 1.6)


@icon
def muffin():
    cup = rpoly(1, (11, 27), (37, 27), (33, 43), (15, 43))
    cup = minus(cup, *[line([(x, 29), (x + (x - 24) * 0.15, 41)], 1.5) for x in (18, 24, 30)])
    top = U(circle(16, 23, 6.5), circle(32, 23, 6.5), circle(24, 17, 9.5), rect(10, 21, 28, 6, 3))
    return over(cup, top, 1.6)


# MARK: Fleisch & Fisch

@icon
def steak():
    g = path(bez((8, 28), (4, 14), (20, 11)), bez((20, 11), (30, 9), (36, 15))[1:], bez((36, 15), (44, 22), (40, 32))[1:],
             bez((40, 32), (36, 41), (24, 38))[1:], bez((24, 38), (12, 40), (8, 28))[1:])
    rim = g.buffer(-3.4).boundary.buffer(0.8, quad_segs=Q).intersection(box(0, 0, 48, 25))
    bone = U(line([(27, 20), (27, 32)], 3.2), line([(22, 20), (32, 20)], 3.2))
    return minus(g, rim, bone.buffer(1.4).difference(bone), circle(16, 27, 1.6), circle(19, 31.5, 1.2))


@icon
def chicken_leg():
    meat = ellipse(18, 19, 11, 14, 40)
    bone = U(line([(26, 27), (36, 37)], 4.2), circle(36, 40.5, 3.2), circle(39.5, 37, 3.2))
    meat = minus(meat, arc(18, 19, 7, 200, 250, 1.8))
    return over(bone, meat, 1.6)


@icon
def bacon():
    def strip(y):
        pts = [(x, y + 2.5 * math.sin((x - 6) / 36 * 2 * math.pi * 1.5)) for x in [6 + i * 0.75 for i in range(49)]]
        g = LineString(pts).buffer(4.2, cap_style='round', join_style='round', quad_segs=Q)
        return minus(g, LineString([(x, y + 0.6) for x, y in pts[4:-4]]).buffer(0.7, quad_segs=Q))
    return rot(U(strip(19), strip(31)), -20)


@icon
def sausage():
    def s(x, y):
        g = rect(x, y, 32, 10, 5, rot=-30)
        return minus(g, rot(line([(x + 7, y + 3), (x + 23, y + 3)], 1.3), -30, x + 16, y + 5))
    return over(s(3, 13), s(13, 25), 1.6)


@icon
def salami():
    stick = rect(5, 17, 30, 13, 6.5, rot=-35)
    slice_ = circle(33, 32, 10.5)
    dots = U(*[circle(33 + dx, 32 + dy, 1.3) for dx, dy in [(-4, -3), (3, -4), (4, 3), (-3, 4), (0, 0), (-6, 2), (6, -1)]])
    stick = U(stick, line([(5, 8), (9, 13)], 1.6))
    return over(stick, minus(slice_, dots), 1.6)


@icon
def fish():
    body = U(ellipse(21, 24, 15, 10), poly((33, 24), (44, 14.5), (44, 33.5)))
    body = minus(body, circle(13, 21.5, 1.8), arc(13, 24, 7.5, -45, 45, 1.6))
    body = U(body, poly((18, 15), (26, 9), (28, 15)))
    return body


@icon
def shrimp():
    cx, cy, r = 24, 21, 10
    body = arc(cx, cy, r, 190, 430, 9)
    cuts = U(*[line([(cx + 5 * math.cos(math.radians(a)), cy + 5 * math.sin(math.radians(a))),
                     (cx + 15 * math.cos(math.radians(a)), cy + 15 * math.sin(math.radians(a)))], 1.4)
               for a in (225, 260, 295, 330, 5)])
    tail = U(leaf(10.5, 13.5, 10, 6, 60), leaf(8, 21, 10, 6, 115))
    feelers = U(line(bez((30, 31), (36, 38), (44, 37)), 1.3), line(bez((31, 29), (38, 31), (44, 28)), 1.3))
    return U(over(minus(body, cuts), tail, 1.4), feelers)


@icon
def tofu():
    top = poly((24, 9), (41, 16), (24, 23), (7, 16))
    left = poly((7, 18.5), (22.8, 25.5), (22.8, 42), (7, 35))
    right = poly((41, 18.5), (25.2, 25.5), (25.2, 42), (41, 35))
    return U(top, left, right)


@icon
def burger_patty():
    top = U(ellipse(24, 18, 18, 10).intersection(box(0, 0, 48, 20)), rect(6, 17, 36, 4, 2))
    pts = [(6 + i * 1.5, 24.5 + 1.2 * math.sin(i * 1.3)) for i in range(25)]
    lettuce = LineString(pts).buffer(1.6, quad_segs=Q)
    patty = rect(5, 27, 38, 6.5, 3.25)
    bottom = rect(7, 36, 34, 6, 3)
    seeds = U(*[ellipse(x, y, 1.3, 0.75, a) for x, y, a in [(17, 13.5, -20), (24, 11.5, 0), (31, 13.5, 20)]])
    return U(minus(top, seeds), lettuce, patty, bottom)


@icon
def mussel():
    shell = path(bez((10, 40), (6, 22), (22, 10)), bez((22, 10), (36, 2), (40, 14))[1:],
                 bez((40, 14), (42, 26), (26, 36))[1:], bez((26, 36), (16, 43), (10, 40))[1:])
    rings = U(line(bez((14, 37), (14, 22), (35, 12)), 1.5), line(bez((19, 35), (21, 25), (37, 18)), 1.5))
    return minus(shell, rings)


@icon
def veggie():
    lf = leaf(25, 22, 34, 22, -45)
    veins = U(line([(14, 33), (35, 12)], 1.6), line([(20, 27), (17, 20)], 1.4), line([(26, 21), (23, 14)], 1.4),
              line([(24, 23), (31, 26)], 1.4), line([(30, 17), (37, 20)], 1.4))
    stem = line(bez((14, 33), (10, 37), (8, 43)), 2.2)
    return U(minus(lf, veins), stem)


# MARK: Kühlregal

@icon
def milk():
    body = rect(12, 19, 22, 25, 1.5)
    roof = poly((12, 19), (34, 19), (30, 11), (16, 11))
    fin = rect(16, 6.5, 14, 3.5, 1)
    side = poly((34, 19), (38, 23), (38, 42), (34, 44))
    drop = path(bez((23, 24), (17, 32), (21, 35)), bez((21, 35), (23, 37), (25, 35))[1:], bez((25, 35), (29, 32), (23, 24))[1:])
    return U(over(U(minus(body, drop), roof), fin, 1.4), over(side, body, 1.4))


@icon
def butter():
    dish = rect(4, 34, 40, 5, 2.5)
    top = poly((9, 22), (35, 22), (41, 16), (15, 16))
    front = rect(9, 24.2, 26, 8.5, 1)
    side = poly((37, 24), (41, 18.5), (41, 26.5), (37, 32.7))
    block = U(top, front, side)
    return over(dish, block, 1.6)


@icon
def cheese():
    top = poly((6, 22), (36, 13), (42, 22))
    side = poly((6, 25), (42, 25), (42, 40), (6, 40))
    holes = U(circle(15, 32, 3), circle(28, 30, 2.2), circle(35, 35.5, 2.6), circle(22, 37.5, 1.6), circle(30, 19, 1.8))
    return minus(U(top, side), holes)


@icon
def egg():
    back = ellipse(30, 22, 10, 13)
    front = ellipse(19, 28, 11, 14)
    front = minus(front, arc(19, 28, 7.5, 195, 245, 1.8))
    return over(back, front, 1.6)


@icon
def yogurt():
    cup = rpoly(1, (12, 18), (36, 18), (32, 43), (16, 43))
    cup = minus(cup, line([(10, 26), (38, 26)], 1.6), line([(10, 35), (38, 35)], 1.6))
    lid = rect(8, 12, 32, 4.5, 2)
    tab = poly((36, 13), (43, 8), (44, 11), (39, 15))
    return U(over(cup, lid, 1.4), tab)


@icon
def cream():
    body = rect(13, 20, 22, 23, 2)
    shoulder = poly((13, 21), (35, 21), (35, 16), (22, 12), (13, 16))
    cap = rect(16, 5.5, 8, 6, 1.5)
    label = rect(16, 26, 16, 11, 1.5)
    g = U(body, shoulder)
    g = gap(g, label, 1.6)
    return over(g, cap, 1.4)


@icon
def pudding():
    plate = ellipse(24, 39.5, 20, 4)
    flan = rpoly(2, (9, 37), (39, 37), (34, 17), (14, 17))
    caramel = path(bez((10, 22), (12, 15), (24, 15)) + bez((24, 15), (36, 15), (38, 22))[1:] +
                   [(38, 24), (35, 24), (34, 29), (31, 24), (22, 24), (20, 28), (18, 24), (10, 24)])
    body = minus(flan, caramel.buffer(1.6))
    return over(plate, U(body, caramel), 1.6)


@icon
def tortellini():
    def ravioli(cx, cy, a):
        sq = rect(cx - 10, cy - 10, 20, 20, 2)
        teeth = U(*[circle(cx - 10 + i * 4, cy - 10 + j * 20, 1.4) for i in range(6) for j in range(2)],
                  *[circle(cx - 10 + j * 20, cy - 10 + i * 4, 1.4) for i in range(6) for j in range(2)])
        g = minus(sq, teeth)
        g = gap(g, rect(cx - 6, cy - 6, 12, 12, 4), 1.4)
        return rot(g, a, cx, cy)
    return over(ravioli(17, 18, -10), ravioli(31, 30, 12), 1.6)


@icon
def dip():
    bowl = U(ellipse(24, 28, 18, 13).intersection(box(0, 28, 48, 48)), rect(6, 26, 36, 4, 2))
    bowl = U(bowl, rect(16, 39, 16, 4, 1.5))
    mound = U(ellipse(24, 24, 13, 5.5).intersection(box(0, 0, 48, 24.5)), circle(24, 17, 3.5))
    chip = poly((30, 7), (40, 13), (32, 21))
    return U(over(bowl, mound, 1.6), over(chip, mound, 1.4).difference(bowl.buffer(1.4)))


@icon
def dough():
    dough_ = ellipse(24, 32, 19, 8)
    pin = U(rect(9, 16, 30, 8, 4, rot=-12), line([(3, 23.5), (9.5, 22)], 2.6), line([(38.5, 17.5), (45, 16)], 2.6))
    return over(dough_, pin, 1.6)
