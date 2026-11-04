from shapes import *  # noqa: F403

ICONS = {}


def icon(fn):
    ICONS[fn.__name__.replace('_', '-')] = fn
    return fn


def stem_leaf(x=24, y=15, top=8, leaf_at=(31, 10.5), leaf_rot=-25, leaf_len=10, leaf_w=6.5):
    return U(line([(x, y), (x + 1, top)], 2.4), leaf(leaf_at[0], leaf_at[1], leaf_len, leaf_w, leaf_rot))


@icon
def apple():
    body = U(circle(18.5, 28, 12), circle(29.5, 28, 12), ellipse(24, 34, 13, 9))
    body = minus(body, circle(24, 15.2, 3.6), arc(19, 28.5, 7.5, 195, 240, 2))
    return over(body, stem_leaf(), 1.6)


@icon
def banana():
    body = path(bez((5, 14), (4, 45), (41, 35)), bez((41, 35), (17, 31), (12, 14))[1:])
    body = body.buffer(1.4).buffer(-0.6)
    body = minus(body, line(bez((10, 20), (11, 35), (32, 35.5)), 1.4))
    return U(body, line([(38.5, 34), (43.5, 31)], 3), circle(8.4, 13.5, 2))


@icon
def pear():
    body = U(circle(24, 32, 11.5), circle(24, 20, 6.5)).convex_hull.buffer(1.5).buffer(-1.5)
    body = minus(body, arc(24, 32, 7.5, 140, 185, 2))
    return over(body, stem_leaf(24, 14, 7, (30.5, 9.5)), 1.6)


@icon
def orange():
    body = minus(circle(24, 27, 15), arc(24, 27, 10.5, 200, 245, 2))
    body = minus(body, circle(24, 12, 2.6))
    return U(body, line([(24, 13.5), (24.5, 10)], 2.4), leaf(30.5, 9.5, 10, 6.5, -20))


@icon
def lemon():
    body = U(ellipse(24, 25, 15, 11, -30), ellipse(36.2, 17.6, 3.5, 2.6, -30), ellipse(11.8, 32.4, 3.5, 2.6, -30))
    return minus(body, arc(24, 25, 7.5, 150, 200, 2))


@icon
def grapes():
    r, pts = 4.75, [(13.6, 19), (24, 19), (34.4, 19), (18.8, 28), (29.2, 28), (24, 37)]
    berries = U(*[circle(x, y, r) for x, y in pts])
    return U(berries, line([(24, 14), (24, 7.5)], 2.4), leaf(31, 10, 10, 6, -15))


@icon
def strawberry():
    body = path(bez((24, 43), (11, 37), (9, 23)), bez((9, 23), (10, 14.5), (24, 16.5))[1:],
                bez((24, 16.5), (38, 14.5), (39, 23))[1:], bez((39, 23), (37, 37), (24, 43))[1:])
    seeds = U(*[ellipse(x, y, 0.9, 1.4) for x, y in
                [(17, 24), (24, 23), (31, 24), (20.5, 30), (27.5, 30), (24, 36.5), (14.5, 29.5), (33.5, 29.5)]])
    crown = U(leaf(17.5, 15.5, 11, 6, 15), leaf(30.5, 15.5, 11, 6, -15), leaf(24, 13, 10, 6, 90),
              line([(24, 12), (25, 6)], 2.2))
    return over(minus(body, seeds), crown, 1.6)


@icon
def berries():
    def berry(x, y, r):
        return minus(circle(x, y, r), star(x, y - 0.5, r * 0.38, r * 0.17))
    a, b, c = berry(16, 30, 8.5), berry(32, 30, 8.5), berry(24, 17, 8.5)
    return over(over(a, b, 1.6), c, 1.6)


@icon
def watermelon():
    half = circle(24, 16, 21).intersection(box(0, 16, 48, 48))
    rind_cut = gap(half, circle(24, 16, 17.2).intersection(box(0, 16.0001, 48, 48)), 1.8)
    seeds = U(*[ellipse(x, y, 1.1, 1.8, a) for x, y, a in
                [(16, 22, 20), (24, 25, 0), (32, 22, -20), (20, 29, 15), (28, 29, -15)]])
    return minus(rind_cut, seeds)


@icon
def pineapple():
    body = ellipse(24, 32, 10.5, 12)
    cuts = U(*[line([(x, 14), (x + 30, 50)], 1.5) for x in (-6, 2, 10, 18)],
             *[line([(x, 14), (x - 30, 50)], 1.5) for x in (30, 38, 46, 54)])
    crown = U(leaf(24, 12, 16, 6, 90), leaf(18.5, 14, 12, 5.5, 55), leaf(29.5, 14, 12, 5.5, -55))
    return over(minus(body, cuts), crown, 1.6)


@icon
def kiwi():
    g = gap(circle(24, 24, 17), circle(24, 24, 13), 1.6)
    g = minus(g, ellipse(24, 24, 4, 3))
    seeds = U(*[ellipse(24 + 7.5 * math.cos(math.radians(a)), 24 + 7.5 * math.sin(math.radians(a)), 1.4, 0.8, a)
                for a in range(0, 360, 30)])
    return minus(g, seeds)


@icon
def mango():
    body = U(ellipse(22, 28, 14.5, 12, -35)).buffer(0)
    body = U(body, circle(28.5, 21.5, 8)).buffer(1).buffer(-1)
    body = minus(body, arc(22, 29, 8, 120, 175, 2))
    return over(body, U(line([(33, 15), (35, 11)], 2.2), leaf(39, 10, 9, 5.5, -10)), 1.6)


@icon
def avocado():
    body = U(circle(24, 31, 12.5), circle(24, 15, 7.5)).convex_hull.buffer(2).buffer(-2)
    g = gap(body, body.buffer(-3.2), 1.6)
    g = minus(g, circle(24, 31, 7))
    return U(g, circle(24, 31, 5))


@icon
def tomato():
    body = ellipse(24, 28, 16.5, 14)
    calyx = U(star(24, 15.5, 9, 3.2, 5, -90), line([(24, 14), (25.5, 8.5)], 2.4))
    body = minus(body, arc(24, 28, 10, 200, 240, 2))
    return over(body, calyx, 1.6)


@icon
def cucumber():
    g = rect(7, 19, 34, 10, 5, rot=-35)
    dots = U(*[circle(x, y, 0.9) for x, y in [(15, 31), (21, 26), (27, 22), (33, 17), (19, 32), (25, 28), (31, 23)]])
    g = minus(g, dots)
    return U(g, line([(37.8, 9.5), (40.5, 6.5)], 2.4))


@icon
def bell_pepper():
    lobes = [ellipse(16, 29, 8.5, 12.5, 8), ellipse(32, 29, 8.5, 12.5, -8), ellipse(24, 30.5, 8.5, 13)]
    body = U(*lobes)
    body = minus(body, line([(19.5, 24), (20.5, 41)], 1.6), line([(28.5, 24), (27.5, 41)], 1.6))
    cap = U(rect(17, 14.5, 14, 4, 2), line(bez((24, 15), (24, 9), (30, 7)), 2.6))
    return over(body, cap, 1.6)


@icon
def carrot():
    body = rpoly(1.2, (6, 42), (33, 22), (26, 15))
    body = U(body, ellipse(29.5, 18.5, 5.2, 5.2))
    cuts = U(line([(17, 29), (21, 32)], 1.5), line([(23, 23), (26.5, 26.5)], 1.5), line([(12, 35.5), (14.5, 37.5)], 1.5))
    tops = U(leaf(37, 9, 13, 5, -60), leaf(41, 15, 11, 5, -20), leaf(33, 8, 9, 4.5, -95))
    return over(minus(body, cuts), tops, 1.6)


@icon
def potato():
    body = U(ellipse(24, 26, 17, 12, -18), circle(15.5, 25.5, 9.5)).buffer(1).buffer(-1)
    eyes = U(circle(15, 22, 1.2), circle(27, 21, 1.1), circle(31, 30, 1.2), circle(20, 31, 1.1), circle(35.5, 22.5, 1))
    return minus(body, eyes)


@icon
def onion():
    bulb = U(circle(24, 29, 13.5), poly((19, 18), (29, 18), (24, 7))).convex_hull.buffer(2).buffer(-2)
    bulb = U(bulb, line([(24, 10), (24, 5)], 2.4))
    layers = U(line(bez((24, 13), (16, 22), (18, 40)), 1.6), line(bez((24, 13), (32, 22), (30, 40)), 1.6))
    roots = U(line([(21, 42.5), (20, 45)], 1.6), line([(24, 43), (24, 45.5)], 1.6), line([(27, 42.5), (28, 45)], 1.6))
    return U(minus(bulb, layers), roots)


@icon
def garlic():
    bulb = U(ellipse(24, 30, 15, 11), poly((20, 20), (28, 20), (24, 7))).convex_hull.buffer(2).buffer(-2)
    bulb = minus(bulb, box(0, 39.5, 48, 48))
    cloves = U(line(bez((24, 14), (14, 24), (17, 39)), 1.6), line(bez((24, 14), (34, 24), (31, 39)), 1.6),
               line([(24, 22), (24, 39)], 1.6))
    roots = U(*[line([(x, 41.5), (x + d, 44.5)], 1.5) for x, d in [(19, -1), (22.5, -0.3), (25.5, 0.3), (29, 1)]])
    return U(minus(bulb, cloves), roots)


@icon
def broccoli():
    florets = U(circle(15, 20, 7.5), circle(24, 14.5, 8.5), circle(33, 20, 7.5), circle(19.5, 25.5, 7), circle(28.5, 25.5, 7))
    stalk = U(rpoly(1, (20, 30), (28, 30), (27, 44), (21, 44)), line([(24, 34), (17, 29)], 3), line([(24, 34), (31, 29)], 3))
    return over(stalk, florets, 1.6)


@icon
def lettuce():
    head = U(circle(24, 26, 16.5), circle(14, 18, 7), circle(34, 18, 7), circle(24, 13, 7))
    veins = U(line(bez((24, 41), (16, 33), (16, 18)), 1.7), line(bez((24, 41), (32, 33), (32, 18)), 1.7),
              line([(24, 41), (24, 22)], 1.7), arc(24, 27, 13, 160, 200, 1.6), arc(24, 27, 13, -20, 20, 1.6))
    return minus(head, veins)


@icon
def corn():
    cob = ellipse(26, 21, 8.5, 15.5, 30)
    kernels = U(*[line([(x, 0), (x + 40, 69)], 1.3) for x in range(-12, 30, 4)],
                *[line([(0, y), (48, y - 28)], 1.3) for y in range(14, 64, 5)])
    cob = minus(cob, kernels)
    husk = U(leaf(16, 35, 22, 9, -75), leaf(27, 37, 18, 8, -25))
    return over(cob, husk, 1.6)


@icon
def mushroom():
    cap = U(ellipse(24, 23, 18, 13).intersection(box(0, 0, 48, 24)), rect(6, 21, 36, 5, 2.5))
    stem = rpoly(1.5, (18.5, 27), (29.5, 27), (31, 42), (17, 42))
    spots = U(circle(16, 17, 2.4), circle(26, 14, 2.6), circle(33, 19, 1.8))
    return over(stem, minus(cap, spots), 1.6)


@icon
def herbs():
    stems = U(line(bez((24, 44), (24, 30), (16, 16)), 2), line(bez((24, 44), (24, 28), (24, 12)), 2),
              line(bez((24, 44), (24, 30), (32, 16)), 2))
    leaves = U(circle(14.5, 13, 5), circle(10.5, 19.5, 4), circle(24, 9, 5.5), circle(19, 14.5, 3.5),
               circle(33.5, 13, 5), circle(37.5, 19.5, 4), circle(29, 14.5, 3.5))
    band = rect(19.5, 32, 9, 4.5, 1.5)
    return over(U(stems, leaves), band, 1.4)


@icon
def ginger():
    body = U(ellipse(19, 29, 12, 7, -15), ellipse(30, 25, 10, 6, -40), ellipse(33, 33, 7, 5, 20),
             ellipse(13, 21, 5.5, 4.5, -60)).buffer(1.2).buffer(-1.2)
    rings = U(line([(18, 23.5), (16.5, 34)], 1.5), line([(28, 20), (32.5, 29)], 1.5), line([(30.5, 30), (29, 37)], 1.5))
    return minus(body, rings)


@icon
def eggplant():
    body = path(bez((12, 40), (5, 32), (16, 24)), bez((16, 24), (24, 18), (26, 12))[1:],
                bez((26, 12), (36, 10), (38, 18))[1:], bez((38, 18), (40, 32), (28, 39))[1:],
                bez((28, 39), (19, 45), (12, 40))[1:])
    cap = U(leaf(30, 12.5, 13, 7, -20), leaf(35.5, 16, 11, 6, 70), line([(33, 11), (38, 5.5)], 2.6))
    return over(body, cap, 1.6)


@icon
def peas():
    pod = leaf(24, 25, 42, 20, -35)
    shell = gap(pod, leaf(24, 25, 34, 12, -35), 1.6)
    shell = minus(shell, U(*[circle(24 + d * 0.82, 25 - d * 0.57, 3.6) for d in (-9, 0, 9)]).buffer(1.6))
    peas_ = U(*[circle(24 + d * 0.82, 25 - d * 0.57, 3.6) for d in (-9, 0, 9)])
    return U(shell, peas_, line([(38.5, 13.5), (42, 9)], 2.2))


@icon
def peach():
    body = U(circle(24, 28, 14.5), circle(20, 25, 12)).buffer(0.5)
    body = minus(body, line(bez((25, 15), (19, 26), (24, 41)), 1.8), arc(24, 28, 9.5, 135, 175, 2))
    return over(body, U(line([(25, 15), (26, 9)], 2.2), leaf(32, 10.5, 10, 6, -20)), 1.6)


@icon
def cherries():
    a, b = circle(15, 35, 7.5), circle(32, 33, 7.5)
    stems = U(line(bez((15, 28), (17, 18), (28, 8)), 2), line(bez((32, 26), (30, 16), (28, 8)), 2))
    lf = leaf(35, 10, 12, 6.5, -10)
    g = U(a, b)
    g = minus(g, arc(15, 35, 4.5, 200, 250, 1.6), arc(32, 33, 4.5, 200, 250, 1.6))
    return U(over(g, stems, 1.4), lf)


@icon
def plum():
    body = ellipse(24, 28, 13.5, 15.5, -12)
    body = minus(body, line(bez((27, 14), (20, 26), (22, 42)), 1.8))
    return over(body, U(line([(27, 14), (29, 8)], 2.2), leaf(33.5, 10, 9, 5.5, -10)), 1.6)


@icon
def melon():
    body = ellipse(24, 26, 18, 15.5)
    stripes = U(*[line(bez((24 + d * 0.3, 10.5), (24 + d * 1.2, 26), (24 + d * 0.3, 41.5)), 1.6) for d in (-12, -4, 4, 12)])
    return U(minus(body, stripes), line([(24, 11), (25, 6.5)], 2.4))


@icon
def grapefruit():
    g = gap(circle(24, 24, 18), circle(24, 24, 14.5), 1.6)
    segs = U(*[line([(24, 24), (24 + 16 * math.cos(math.radians(a)), 24 + 16 * math.sin(math.radians(a)))], 1.6)
               for a in range(0, 360, 45)])
    inner = circle(24, 24, 14.5)
    return U(minus(g, segs.intersection(inner), circle(24, 24, 2.4)))


@icon
def coconut():
    body = circle(24, 25, 17)
    eyes = U(circle(28.5, 14.5, 1.8), circle(33.5, 17.5, 1.8), circle(29.5, 20, 1.8))
    fibers = U(arc(24, 25, 12.5, 125, 165, 1.6), arc(24, 25, 8, 140, 175, 1.6), line([(15, 31), (13, 35)], 1.4))
    return minus(body, eyes, fibers)


@icon
def fig():
    body = path(bez((24, 9), (27, 16), (33, 22)), bez((33, 22), (42, 33), (24, 42))[1:],
                bez((24, 42), (6, 33), (15, 22))[1:], bez((15, 22), (21, 16), (24, 9))[1:])
    body = minus(body, line([(24, 36), (24, 39)], 1.4), line([(22.5, 37.5), (25.5, 37.5)], 1.4),
                 arc(24, 30, 7, 150, 195, 1.8))
    return U(body, line([(24, 10), (25, 5)], 2.4))


@icon
def cherry_tomatoes():
    def t(x, y, r):
        return minus(circle(x, y, r), star(x, y - r * 0.55, r * 0.5, r * 0.2))
    vine = line(bez((8, 12), (24, 6), (40, 12)), 2.2)
    stems = U(line([(13, 10), (13, 19)], 1.8), line([(24, 8), (24, 23)], 1.8), line([(35, 10), (35, 19)], 1.8))
    toms = U(t(13, 25, 7.5), t(35, 25, 7.5))
    toms = over(toms, t(24, 32, 8.5), 1.6)
    return U(over(U(vine, stems), toms, 1.4))


@icon
def spring_onion():
    bulbs = U(ellipse(17, 38, 4, 5), ellipse(24, 39, 4, 5), ellipse(31, 38, 4, 5))
    stalks = U(line([(17, 34), (11, 7)], 3), line([(24, 35), (24, 6)], 3), line([(31, 34), (37, 7)], 3))
    roots = U(*[line([(x, 43.5), (x + d, 46)], 1.3) for x, d in [(16, -1), (18, 1), (23, -1), (25, 1), (30, -1), (32, 1)]])
    band = rect(13, 27, 22, 4, 1.5)
    return U(over(U(bulbs, stalks), band, 1.4), roots)


@icon
def leek():
    white = rect(7, 20, 26, 9, 4.5, rot=-40)
    green = U(leaf(33, 13, 18, 7, -60), leaf(36.5, 17, 18, 7, -30))
    roots = U(*[line([(10.5, 37.5), (10.5 + dx, 37.5 + dy)], 1.4) for dx, dy in [(-4, 2), (-3, 5), (0, 5.5)]])
    stripes = U(line([(13, 32), (25, 22)], 1.4))
    return U(over(minus(white, stripes), green, 1.6), roots)


@icon
def leafy_greens():
    def lf(cx, cy, l, w, a):
        g = leaf(cx, cy, l, w, a)
        rad = math.radians(a)
        dx, dy = math.cos(rad) * l / 2, math.sin(rad) * l / 2
        return minus(g, line([(cx - dx * 0.8, cy - dy * 0.8), (cx + dx * 0.7, cy + dy * 0.7)], 1.5))
    a = lf(18, 22, 30, 13, -65)
    b = lf(30, 24, 28, 12, -110)
    stems = U(line([(23, 34.5), (22, 44)], 2.2), line([(26.5, 36), (27, 44)], 2.2))
    return U(over(a, b, 1.6), stems)


@icon
def cabbage():
    head = circle(24, 25, 17)
    leaves = U(arc(24, 46, 22, 230, 310, 1.7), arc(13, 30, 14, -70, 20, 1.7), arc(35, 30, 14, 160, 250, 1.7),
               line([(24, 40), (24, 26)], 1.6))
    return minus(head, leaves)


@icon
def celery():
    stalks = U(line([(18, 44), (14, 18)], 5.5), line([(24, 44), (24, 16)], 5.5), line([(30, 44), (34, 18)], 5.5))
    stalks = minus(stalks, line([(24, 26), (24, 40)], 1.2))
    stalks = over(over(line([(18, 44), (14, 18)], 5.5), line([(30, 44), (34, 18)], 5.5), 1.2), line([(24, 44), (24, 16)], 5.5), 1.4)
    leaves = U(leaf(11, 13, 10, 5.5, -120), leaf(16.5, 10, 10, 5.5, -80), leaf(24, 8, 10, 5.5, -90),
               leaf(31.5, 10, 10, 5.5, -100), leaf(37, 13, 10, 5.5, -60))
    return over(stalks, leaves, 1.4)


@icon
def radish():
    bulb = circle(24, 29, 11)
    tail = line([(24, 39), (24, 46)], 2)
    leaves = U(leaf(17.5, 11, 14, 7, -110), leaf(30.5, 11, 14, 7, -70), line([(24, 19), (24, 13)], 2.2))
    bulb = minus(bulb, arc(24, 29, 7, 195, 240, 1.8))
    return U(over(U(bulb, tail), leaves, 1.6))


@icon
def asparagus():
    def spear(x0, y0, x1, y1):
        body = line([(x0, y0), (x1, y1)], 5)
        tip = ellipse(x1, y1, 3.6, 5, math.degrees(math.atan2(y1 - y0, x1 - x0)) - 90)
        return over(body, tip, 1.2)
    a = spear(14, 44, 18, 9)
    b = spear(24, 44, 24, 6)
    c = spear(34, 44, 30, 9)
    band = rect(13, 30, 22, 4, 1.5)
    return over(U(over(over(a, c, 1.4), b, 1.4)), band, 1.4)


@icon
def pumpkin():
    lobes = [ellipse(15, 29, 9, 12), ellipse(33, 29, 9, 12), ellipse(24, 29, 9.5, 13.5)]
    body = over(over(lobes[0], lobes[1], 1.4), lobes[2], 1.4)
    stem = line(bez((24, 16), (24, 11), (28, 7)), 3.2)
    return over(body, stem, 1.4)


@icon
def sweet_potato():
    body = path(bez((6, 30), (10, 20), (24, 18)), bez((24, 18), (38, 16), (43, 22))[1:],
                bez((43, 22), (44, 30), (30, 33))[1:], bez((30, 33), (16, 37), (6, 30))[1:])
    lines = U(line(bez((16, 22), (14, 27), (17, 33)), 1.4), line(bez((30, 19), (28, 25), (31, 31)), 1.4))
    return U(minus(body, lines), line([(43, 21), (46, 19)], 1.6))


@icon
def chili():
    body = path(bez((12, 14), (10, 34), (36, 43)), bez((36, 43), (22, 32), (20, 15))[1:])
    body = body.buffer(1.2).buffer(-0.2)
    cap = U(ellipse(16, 13.5, 6, 3.5, 10), line(bez((15, 12), (14, 7), (19, 4.5)), 2.2))
    return over(body, cap, 1.4)


@icon
def sprouts():
    def sprout(x, a):
        s = line(bez((x, 42), (x, 30), (x + a, 22)), 1.8)
        l1 = leaf(x + a - 3.5, 19.5, 8, 4.5, -40 if a < 0 else -140)
        l2 = leaf(x + a + 3.5, 19.5, 8, 4.5, 40 if a < 0 else 140)
        seed = ellipse(x, 42, 3.2, 2.4)
        return U(s, l1, l2, seed)
    return U(sprout(14, -2), move(sprout(24, 1), 0, -6), sprout(34, 2))


@icon
def currants():
    stem = line(bez((22, 5), (26, 14), (24, 24)), 1.8)
    berries = [circle(x, y, 4.2) for x, y in [(19, 22), (28, 24), (22.5, 30.5), (31, 32), (25, 39), (16, 31)]]
    g = berries[0]
    for b in berries[1:]:
        g = over(g, b, 1.2)
    lf = leaf(33, 10, 12, 7, -20)
    return U(over(stem, g, 1.2), lf)


@icon
def rhubarb():
    stalks = U(line([(10, 43), (26, 17)], 5), line([(18, 44), (32, 20)], 5))
    stalks = minus(stalks, line([(14, 39), (24, 22)], 1))
    leaf_ = U(circle(32, 14, 9), circle(38, 18, 6), circle(26, 10, 5)).buffer(0.5)
    leaf_ = minus(leaf_, line([(28, 19), (37, 8)], 1.5))
    return over(stalks, leaf_, 1.6)
