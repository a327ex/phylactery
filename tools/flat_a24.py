#!/usr/bin/env python3
"""flat_a24.py -- A24 as a flat design after The Dark Side of the Moon (Phylactery 20, 2026-10-18; his words: "a flat
design like the original, finger on the left, white beam going to snake, snake also flat with its middle breaking apart
and the prismatic lines coming out the other side").

Writes an SVG (and an HTML page holding it at its exact size) for any canvas; render it with headless Edge
(tools/edge_shoot.ps1 <folder> <w> <h> <name> does). Two snakes: 'glass' (drawn like the cover's prism: an airbrushed pale edge on black)
and 'flat' (flat fills in the game snake's colours: tan, the dark band down the back, the pale belly, black bead eyes).

    python tools/flat_a24.py out.html --size 920 430 --snake glass|flat [--layout header|hero|small|main]
"""
import argparse, math, random

SPECTRUM = ['#e2342c', '#f08a24', '#f6d12b', '#58b947', '#2fa3d8', '#8a6bbd']     # the cover's six, a touch warmer
BONE, BONE_D = '#e9dfc6', '#a8987a'
TAN, BAND, BELLY, EYE = '#c9a66b', '#6c5634', '#efe0bd', '#0b0806'
GLASS = '#cfe4ec'
BG = '#050403'

LAYOUTS = {   # finger tip (fx, fy), snake centre (sx, sy), snake height, spectrum drop (fraction of H at the right edge)
    'header': dict(fx=0.150, fy=0.660, sx=0.500, sy=0.540, sh=0.76, drop=0.20, spread=0.150),
    'hero':   dict(fx=0.110, fy=0.480, sx=0.500, sy=0.470, sh=0.62, drop=0.14, spread=0.110),
    'small':  dict(fx=0.070, fy=0.640, sx=0.420, sy=0.540, sh=0.80, drop=0.18, spread=0.170),
    'main':   dict(fx=0.140, fy=0.640, sx=0.490, sy=0.540, sh=0.72, drop=0.18, spread=0.140),
    'square': dict(fx=0.060, fy=0.600, sx=0.470, sy=0.520, sh=0.70, drop=0.16, spread=0.130),
}


def bez(p0, p1, p2, p3, n):
    out = []
    for i in range(n):
        t = i / n
        a, b, c, d = (1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t * t * (1 - t), t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


def centreline():
    """the snake rearing, in units of its height, origin at its centre, y down; s = 0 at the head"""
    segs = [((-0.02, -0.46), (0.13, -0.48), (0.21, -0.31), (0.07, -0.15)),
            ((0.07, -0.15), (-0.07, -0.01), (-0.10, 0.10), (0.01, 0.21)),
            ((0.01, 0.21), (0.13, 0.32), (0.17, 0.43), (0.03, 0.49)),
            ((0.03, 0.49), (-0.09, 0.55), (-0.25, 0.53), (-0.34, 0.45))]
    pts = []
    for s in segs:
        pts += bez(*s, 80)
    pts.append(segs[-1][3])
    L = [0.0]
    for i in range(1, len(pts)):
        L.append(L[-1] + math.dist(pts[i], pts[i - 1]))
    return pts, [l / L[-1] for l in L]


def width(s):
    if s < 0.06:
        return 0.088 + 0.012 * s / 0.06
    if s < 0.60:
        return 0.100 + 0.016 * math.sin(math.pi * (s - 0.06) / 0.54)
    return 0.100 * max(0.0, (1 - s) / 0.40) ** 0.75 + 0.002


def offsets(pts, ss, k=1.0):
    left, right = [], []
    for i, (p, s) in enumerate(zip(pts, ss)):
        a, b = pts[max(0, i - 1)], pts[min(len(pts) - 1, i + 1)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        n = math.hypot(tx, ty) or 1
        nx, ny = -ty / n, tx / n
        w = width(s) * k / 2
        left.append((p[0] + nx * w, p[1] + ny * w)); right.append((p[0] - nx * w, p[1] - ny * w))
    return left, right


def seg_intersect_y(pts, ss, line):
    """first crossing of the centreline with the beam line (point, slope) below the neck"""
    (x0, y0), m = line
    best = None
    for i in range(1, len(pts)):
        (ax, ay), (bx, by) = pts[i - 1], pts[i]
        fa, fb = ay - (y0 + m * (ax - x0)), by - (y0 + m * (bx - x0))
        if fa * fb <= 0 and ss[i] > 0.18:
            t = fa / (fa - fb)
            best = (i, (ax + t * (bx - ax), ay + t * (by - ay)), ss[i - 1] + t * (ss[i] - ss[i - 1]))
            break
    return best


def poly(points):
    return ' '.join(f'{x:.2f},{y:.2f}' for x, y in points)


def svg(W, H, layout='header', snake='flat', seed=7):
    rnd = random.Random(seed)
    L = LAYOUTS[layout]
    U = L['sh'] * H                                   # px per snake unit
    cx, cy = L['sx'] * W, L['sy'] * H
    T = lambda p: (cx + p[0] * U, cy + p[1] * U)      # noqa: E731
    pts, ss = centreline()
    fx, fy = L['fx'] * W, L['fy'] * H
    # the beam rises gently to the snake's middle (local y ~ 0.0)
    mid = T((0.0, 0.03))
    m = (mid[1] - fy) / (mid[0] - fx)
    hit = seg_intersect_y([T(p) for p in pts], ss, ((fx, fy), m))
    i_hit, hp, s_hit = hit
    gap = 0.135                                       # the broken length of the body (fraction of its length)
    s0, s1 = s_hit - gap / 2, s_hit + gap / 2
    P = [T(p) for p in pts]
    lft, rgt = offsets(pts, ss)
    lft, rgt = [T(p) for p in lft], [T(p) for p in rgt]
    idx = lambda s: min(range(len(ss)), key=lambda i: abs(ss[i] - s))   # noqa: E731
    i0, i1 = idx(s0), idx(s1)
    beam_w = max(1.6, 0.0075 * H)
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
           '<defs>',
           f'<filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="{0.004 * H:.2f}"/></filter>',
           f'<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="{0.010 * H:.2f}"/></filter>',
           f'<filter id="air" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="{0.012 * U:.2f}"/></filter>',
           f'<linearGradient id="fan" x1="0" x2="1" y1="0" y2="0"><stop offset="0" stop-color="#ffffff" stop-opacity="0.9"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.05"/></linearGradient>',
           '</defs>',
           f'<rect width="{W}" height="{H}" fill="{BG}"/>']
    # ---- the spectrum, out of the far side of the break, fanning a little, to the right edge
    lo_i, hi_i = (i0, i1)
    exit_pt = (max(lft[k][0] for k in range(lo_i, hi_i + 1)) * 0.5 + max(rgt[k][0] for k in range(lo_i, hi_i + 1)) * 0.5, hp[1])
    ex = exit_pt[0] + 0.02 * U
    ey = hp[1] + (ex - hp[0]) * m * 0.2
    band0 = 0.55 * L['spread'] * H / 6
    rx = W + 4
    drop = L['drop'] * H
    spread = L['spread'] * H
    n = len(SPECTRUM)
    for k, col in enumerate(SPECTRUM):
        a0 = ey - n * band0 / 2 + k * band0
        a1 = a0 + band0
        b0 = ey + drop - spread / 2 + k * spread / n
        b1 = b0 + spread / n
        out.append(f'<polygon points="{poly([(ex, a0), (rx, b0), (rx, b1 + 0.6), (ex, a1 + 0.3)])}" fill="{col}"/>')
    # ---- the beam: white, a soft glow, from the fingertip into the break; inside the break it fans and greys
    bx = (lft[i0][0] + rgt[i0][0]) / 2 - 0.045 * U
    by = fy + m * (bx - fx)
    out.append(f'<line x1="{fx:.1f}" y1="{fy:.1f}" x2="{bx:.1f}" y2="{by:.1f}" stroke="#ffffff" stroke-width="{beam_w * 3:.2f}" opacity="0.35" filter="url(#glow)"/>')
    out.append(f'<line x1="{fx:.1f}" y1="{fy:.1f}" x2="{bx:.1f}" y2="{by:.1f}" stroke="#ffffff" stroke-width="{beam_w:.2f}" stroke-linecap="round"/>')
    out.append(f'<polygon points="{poly([(bx, by - beam_w / 2), (ex, ey - n * band0 / 2), (ex, ey + n * band0 / 2), (bx, by + beam_w / 2)])}" fill="url(#fan)" opacity="0.55"/>')
    # ---- the snake: two pieces of body either side of the break, the head, the shards
    upper = lft[:i0 + 1] + rgt[:i0 + 1][::-1]
    lower = lft[i1:] + rgt[i1:][::-1]

    def body(points, piece):
        if snake == 'flat':
            out.append(f'<polygon points="{poly(points)}" fill="{TAN}"/>')
        else:
            out.append(f'<clipPath id="c{piece}"><polygon points="{poly(points)}"/></clipPath>')
            out.append(f'<polygon points="{poly(points)}" fill="#000" stroke="{GLASS}" stroke-width="{0.022 * U:.2f}" '
                       f'filter="url(#air)" clip-path="url(#c{piece})"/>')
            out.append(f'<polygon points="{poly(points)}" fill="none" stroke="{GLASS}" stroke-width="{max(0.8, 0.0022 * U):.2f}" opacity="0.85"/>')

    def stripes(a, b):
        if snake != 'flat':
            return
        bl, br = offsets(pts[a:b + 1], ss[a:b + 1], k=0.36)
        bl, br = [T(p) for p in bl], [T(p) for p in br]
        out.append(f'<polygon points="{poly(bl + br[::-1])}" fill="{BAND}"/>')
        el, er = offsets(pts[a:b + 1], ss[a:b + 1], k=0.80)
        il, ir = offsets(pts[a:b + 1], ss[a:b + 1], k=0.62)
        out.append(f'<polygon points="{poly([T(p) for p in er] + [T(p) for p in ir][::-1])}" fill="{BELLY}"/>')

    body(upper, 'u'); stripes(0, i0)
    body(lower, 'l'); stripes(i1, len(pts) - 1)
    # the head: broad, rounded, facing the finger; two bead eyes on top, a pale snout nub
    hx, hy = T((-0.085, -0.462))
    rx_, ry_ = 0.120 * U, 0.080 * U
    rot = -8
    if snake == 'flat':
        out.append(f'<ellipse cx="{hx:.1f}" cy="{hy:.1f}" rx="{rx_:.1f}" ry="{ry_:.1f}" transform="rotate({rot} {hx:.1f} {hy:.1f})" fill="{TAN}"/>')
        out.append(f'<ellipse cx="{hx + 0.012 * U:.1f}" cy="{hy - 0.026 * U:.1f}" rx="{rx_ * 0.82:.1f}" ry="{ry_ * 0.30:.1f}" transform="rotate({rot} {hx:.1f} {hy:.1f})" fill="{BAND}"/>')
        out.append(f'<ellipse cx="{hx - 0.110 * U:.1f}" cy="{hy + 0.018 * U:.1f}" rx="{0.026 * U:.1f}" ry="{0.020 * U:.1f}" fill="{BELLY}"/>')
    else:
        out.append(f'<clipPath id="ch"><ellipse cx="{hx:.1f}" cy="{hy:.1f}" rx="{rx_:.1f}" ry="{ry_:.1f}" transform="rotate({rot} {hx:.1f} {hy:.1f})"/></clipPath>')
        out.append(f'<ellipse cx="{hx:.1f}" cy="{hy:.1f}" rx="{rx_:.1f}" ry="{ry_:.1f}" transform="rotate({rot} {hx:.1f} {hy:.1f})" fill="#000" stroke="{GLASS}" stroke-width="{0.022 * U:.2f}" filter="url(#air)" clip-path="url(#ch)"/>')
        out.append(f'<ellipse cx="{hx:.1f}" cy="{hy:.1f}" rx="{rx_:.1f}" ry="{ry_:.1f}" transform="rotate({rot} {hx:.1f} {hy:.1f})" fill="none" stroke="{GLASS}" stroke-width="{max(0.8, 0.0022 * U):.2f}" opacity="0.85"/>')
    for ex_, ey_, r in ((hx - 0.040 * U, hy - 0.046 * U, 0.033 * U), (hx + 0.030 * U, hy - 0.058 * U, 0.028 * U)):
        if snake == 'flat':
            out.append(f'<circle cx="{ex_:.1f}" cy="{ey_:.1f}" r="{r:.1f}" fill="{EYE}"/>')
        else:
            out.append(f'<circle cx="{ex_:.1f}" cy="{ey_:.1f}" r="{r:.1f}" fill="#000" stroke="{GLASS}" stroke-width="{max(0.8, 0.003 * U):.2f}"/>')
        out.append(f'<circle cx="{ex_ - r * 0.32:.1f}" cy="{ey_ - r * 0.32:.1f}" r="{r * 0.24:.1f}" fill="#ffffff"/>')
    # the shards: the broken middle cut into pieces, pushed along the light
    ks = list(range(i0, i1 + 1, max(1, (i1 - i0) // 5)))
    if ks[-1] != i1:
        ks.append(i1)
    pieces = []
    for a, b in zip(ks[:-1], ks[1:]):
        qa, qb = lft[a], rgt[a]
        qc, qd = rgt[b], lft[b]
        mx = lambda p, q, t: (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)   # noqa: E731
        cut1, cut2 = mx(qa, qb, rnd.uniform(0.3, 0.7)), mx(qd, qc, rnd.uniform(0.3, 0.7))
        pieces += [[qa, cut1, cut2, qd], [cut1, qb, qc, cut2]]
    for j, pc in enumerate(pieces):
        ccx = sum(p[0] for p in pc) / len(pc); ccy = sum(p[1] for p in pc) / len(pc)
        push = rnd.uniform(0.03, 0.12) * U * (1.5 if (j % 2) else 1.0)
        dx, dy = push, push * m + rnd.uniform(-0.02, 0.02) * U
        ang = rnd.uniform(-35, 35)
        tr = f'translate({dx:.1f} {dy:.1f}) rotate({ang:.1f} {ccx:.1f} {ccy:.1f})'
        if snake == 'flat':
            out.append(f'<polygon points="{poly(pc)}" fill="{TAN if j % 3 else BAND}" transform="{tr}"/>')
        else:
            out.append(f'<polygon points="{poly(pc)}" fill="#0a0f12" stroke="{GLASS}" stroke-width="{max(0.8, 0.0028 * U):.2f}" transform="{tr}" opacity="0.95"/>')
    for j in range(7):                                # a few small splinters already out in the spectrum
        t = rnd.uniform(0.15, 1.0)
        px_ = ex + t * 0.22 * U
        py_ = ey + (px_ - ex) * (drop / (rx - ex)) + rnd.uniform(-0.04, 0.05) * U
        r = rnd.uniform(0.006, 0.014) * U
        a0 = rnd.uniform(0, math.pi)
        tri = [(px_ + r * math.cos(a0 + q * 2.1), py_ + r * math.sin(a0 + q * 2.1)) for q in range(3)]
        out.append(f'<polygon points="{poly(tri)}" fill="{TAN if snake == "flat" else GLASS}" opacity="{0.9 - 0.5 * t:.2f}"/>')
    # ---- his finger: bones with flared ends and dark joint gaps, pointing at the snake; the hand off the frame
    ang = math.atan(m)
    ux, uy = math.cos(ang), math.sin(ang)
    vx, vy = -uy, ux

    def bone(p, q, hw, tip=False):
        out.append(f'<line x1="{p[0]:.1f}" y1="{p[1]:.1f}" x2="{q[0]:.1f}" y2="{q[1]:.1f}" stroke="{BONE}" stroke-width="{1.5 * hw:.1f}"/>')
        out.append(f'<circle cx="{q[0]:.1f}" cy="{q[1]:.1f}" r="{hw * 1.05:.1f}" fill="{BONE}"/>')
        out.append(f'<circle cx="{p[0]:.1f}" cy="{p[1]:.1f}" r="{hw * (0.72 if tip else 1.0):.1f}" fill="{BONE}"/>')

    gapj = 0.013 * U
    x, y = fx, fy
    for k, (ln, hw) in enumerate([(0.080, 0.030), (0.100, 0.035), (0.150, 0.040), (0.60, 0.045)]):
        ln, hw = ln * U, hw * U
        a = (x - ux * ln, y - uy * ln)
        bone((x - ux * hw * 0.55, y - uy * hw * 0.55) if k == 0 else (x, y), a, hw, tip=(k == 0))
        x, y = a[0] - ux * gapj, a[1] - uy * gapj
    # the curled fingers: from knuckles below the index's, forward, then bent down and back
    kx0, ky0 = fx - ux * (0.080 + 0.100 + 0.150 + 0.040) * U, fy - uy * (0.080 + 0.100 + 0.150 + 0.040) * U
    for k, (off, sc) in enumerate(((0.098, 1.7), (0.180, 1.55))):
        kx, ky = kx0 + vx * off * U - ux * 0.012 * k * U, ky0 + vy * off * U - uy * 0.012 * k * U
        bone((kx - ux * 0.40 * U, ky - uy * 0.40 * U), (kx, ky), 0.025 * U * sc)
        a1 = ang + math.radians(70)
        p1 = (kx + math.cos(a1) * 0.070 * U * sc, ky + math.sin(a1) * 0.070 * U * sc)
        bone((kx + math.cos(a1) * gapj * 1.2, ky + math.sin(a1) * gapj * 1.2), p1, 0.021 * U * sc)
        a2 = ang + math.radians(150)
        p2 = (p1[0] + math.cos(a2) * 0.045 * U * sc, p1[1] + math.sin(a2) * 0.045 * U * sc)
        bone((p1[0] + math.cos(a2) * gapj, p1[1] + math.sin(a2) * gapj), p2, 0.018 * U * sc, tip=True)
    out.append('</svg>')
    return '\n'.join(out)


def bare(W, H):
    """the small capsule's ground: no snake, no finger; the white beam in from the left edge, the spectrum out to the
    right edge, the title between them (laid by tools/title.py)"""
    beam_w = max(1.6, 0.012 * H)
    y = 0.50 * H
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
           f'<defs><filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="{0.02 * H:.2f}"/></filter></defs>',
           f'<rect width="{W}" height="{H}" fill="{BG}"/>',
           f'<line x1="0" y1="{y + 0.05 * H:.1f}" x2="{0.11 * W:.1f}" y2="{y:.1f}" stroke="#ffffff" stroke-width="{beam_w * 3:.1f}" opacity="0.35" filter="url(#glow)"/>',
           f'<line x1="0" y1="{y + 0.05 * H:.1f}" x2="{0.11 * W:.1f}" y2="{y:.1f}" stroke="#ffffff" stroke-width="{beam_w:.1f}"/>']
    n = len(SPECTRUM)
    ex, b0w, b1w = 0.885 * W, 0.20 * H, 0.36 * H
    for k, col in enumerate(SPECTRUM):
        a0 = y - b0w / 2 + k * b0w / n
        c0 = y + 0.10 * H - b1w / 2 + k * b1w / n
        out.append(f'<polygon points="{poly([(ex, a0), (W + 2, c0), (W + 2, c0 + b1w / n + 0.6), (ex, a0 + b0w / n + 0.3)])}" fill="{col}"/>')
    out.append('</svg>')
    return '\n'.join(out)


def html(W, H, s):
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>html,body{{margin:0;padding:0;background:{BG};'
            f'width:{W}px;height:{H}px;overflow:hidden}}svg{{display:block}}</style></head><body>{s}</body></html>')


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('out'); ap.add_argument('--size', type=int, nargs=2, default=[920, 430])
    ap.add_argument('--snake', default='flat'); ap.add_argument('--layout', default='header'); ap.add_argument('--seed', type=int, default=7)
    a = ap.parse_args()
    W, H = a.size
    s = bare(W, H) if a.layout == 'bare' else svg(W, H, a.layout, a.snake, a.seed)
    open(a.out, 'w', encoding='utf-8').write(html(W, H, s))
    open(a.out.rsplit('.', 1)[0] + '.svg', 'w', encoding='utf-8').write(s)
    print(a.out)
