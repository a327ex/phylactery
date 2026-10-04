"""tunnel_mouth.py -- the tunnel's mouth without its hood (Anchor build, 2026-10-03).

cave.js's tunnel tube starts at z = -12.5, ~4.5 m inside the chamber (whose wall stands near z = -17
there), so its first rings stood in the room as a thin free hood (owner: "the geometry on the tunnel
is incorrect"). This cuts the tube back to its ring at z = -18.78 (just behind the wall's mouth hole)
and stitches a collar from the hole's own edge vertices (the wall mesh's boundary there) to that
ring, so the joins share exact vertices. The collar takes the tube's attributes: flat normals facing
the tunnel's axis, UVs (both the exported per-face kind and the continuous one), and baked light
from the nearest baked vertex.

Rewrites assets/port/cave/geo/cave_2.* (the original kept once as cave_2.<attr>.orig.f32) and the
manifest's vertex count for cave_2. Re-running starts from the .orig files.
Usage: python tools/tunnel_mouth.py [--plot scratch/tunnel/mouth.png]
"""
import os, sys, math, re, collections
import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
GEO = os.path.join(ROOT, 'assets', 'port', 'cave', 'geo')
MANIFEST = os.path.join(ROOT, 'assets', 'port', 'cave.lua')
ATTRS = {'position': 3, 'normal': 3, 'uv': 2, 'gi': 3, 'uvc': 2}
Z_RING = -18.78125        # the tube ring the collar meets (rings at -12.5 - k*2.094)
TILE = 2.0

def rd(name, attr, n, orig=False):
    p = os.path.join(GEO, '%s.%s%s.f32' % (name, attr, '.orig' if orig else ''))
    return np.frombuffer(open(p, 'rb').read(), dtype='<f4').reshape(-1, n).astype(np.float64)

def wr(name, attr, a):
    open(os.path.join(GEO, '%s.%s.f32' % (name, attr)), 'wb').write(np.asarray(a, dtype='<f4').tobytes())

def keep_orig():
    for attr in ATTRS:
        src = os.path.join(GEO, 'cave_2.%s.f32' % attr)
        dst = os.path.join(GEO, 'cave_2.%s.orig.f32' % attr)
        if not os.path.exists(dst):
            open(dst, 'wb').write(open(src, 'rb').read())

def key(p): return tuple(np.round(p, 4))

def hole_polyline(W):
    """the wall's boundary edges round the tunnel's mouth, as one ordered polyline (right to left)"""
    tri = W.reshape(-1, 3, 3)
    ec = collections.Counter()
    for t in tri:
        for a, b in ((0, 1), (1, 2), (2, 0)):
            ec[tuple(sorted((key(t[a]), key(t[b]))))] += 1
    bottom = lambda p: p[1] < -0.2           # the lathe's lowest row (h = -0.8 +- 0.6): its own edge, not the hole's
    edges = [e for e, c in ec.items() if c == 1
             and (e[0][2] + e[1][2]) / 2 < -8 and abs((e[0][0] + e[1][0]) / 2) < 6 and max(e[0][1], e[1][1]) < 6.5
             and not (bottom(e[0]) and bottom(e[1]))]
    adj = collections.defaultdict(list)
    for a, b in edges: adj[a].append(b); adj[b].append(a)
    ends = [p for p, n in adj.items() if len(n) == 1]
    assert len(ends) == 2, ('the hole should be one open polyline', len(ends), len(edges))
    start = max(ends, key=lambda p: p[0])     # the right end (x > 0)
    line = [start]; prev = None
    while True:
        nxt = [q for q in adj[line[-1]] if q != prev]
        if not nxt: break
        prev = line[-1]; line.append(nxt[0])
    assert len(line) == len(adj), 'the hole edges branch'
    return np.array(line)

def tube_ring(T, z):
    pts = {key(p) for p in T if abs(p[2] - z) < 1e-2}
    P = np.array(sorted(pts))
    ang = np.arctan2(P[:, 1] - 1.2, P[:, 0])
    ang = np.where(ang < -math.pi / 2, ang + 2 * math.pi, ang)     # the arch runs right (-0.12 pi) to left (1.12 pi)
    return P[np.argsort(ang)]

def angle_of(P, cy=1.2):
    a = np.arctan2(P[:, 1] - cy, P[:, 0])
    return np.where(a < -math.pi / 2, a + 2 * math.pi, a)

def zipper(A, B):
    """triangles between two polylines running the same way (by angle round the axis)"""
    aa, ab = angle_of(A), angle_of(B)
    i = j = 0; tris = []
    while i < len(A) - 1 or j < len(B) - 1:
        if j == len(B) - 1 or (i < len(A) - 1 and aa[i + 1] <= ab[j + 1]):
            tris.append((A[i], A[i + 1], B[j])); i += 1
        else:
            tris.append((A[i], B[j + 1], B[j])); j += 1
    return tris

def main():
    keep_orig()
    T = {a: rd('cave_2', a, n, orig=True) for a, n in ATTRS.items()}
    W = rd('cave_0', 'position', 3)
    hole = hole_polyline(W)
    ring = tube_ring(T['position'], Z_RING)
    print('hole polyline: %d vertices, z %.2f..%.2f; tube ring at z %.2f: %d vertices' % (len(hole), hole[:, 2].min(), hole[:, 2].max(), Z_RING, len(ring)))
    assert hole[:, 2].min() > Z_RING, 'the ring must lie behind the whole hole'

    # the tube behind the ring only
    cz = T['position'].reshape(-1, 3, 3)[:, :, 2].mean(1)
    keep = np.repeat(cz < Z_RING + 0.01, 3)
    tube = {a: v[keep] for a, v in T.items()}
    print('tube triangles: %d -> %d' % (len(cz), keep.sum() // 3))

    # the collar
    tris = np.array(zipper(hole, ring))                               # (n, 3, 3)
    n = len(tris)
    pos = tris.reshape(-1, 3)
    # flat normals toward the tunnel's axis (the line x = 0, y = 1.2)
    nrm = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    cen = tris.mean(1)
    toward = np.stack([-cen[:, 0], 1.2 - cen[:, 1], np.zeros(n)], 1)
    flip = (nrm * toward).sum(1) < 0
    nrm[flip] *= -1
    tris[flip] = tris[flip][:, ::-1]                                  # winding to match
    pos = tris.reshape(-1, 3)
    nrm3 = np.repeat(nrm, 3, axis=0)
    # exported-style UVs: each triangle on its own dominant axis (cave.js world_uv), 2 m per unit
    uv = np.zeros((n * 3, 2))
    for t in range(n):
        ax, ay, az = np.abs(nrm[t])
        for k in range(3):
            v = tris[t, k]
            if ay >= ax and ay >= az: u0, v0 = v[0], v[2]
            elif ax >= az: u0, v0 = v[2], v[1]
            else: u0, v0 = v[0], v[1]
            uv[t * 3 + k] = (u0 / TILE, v0 / TILE)
    # continuous UVs: as cave_look.py's tunnel (round the arch, along z)
    Wd, Hd = 2.7 + 0.9, 4.2 + 0.6
    a = np.arctan2(pos[:, 1] / Hd, pos[:, 0] / Wd)
    a = np.where(a < -math.pi / 2, a + 2 * math.pi, a)
    uvc = np.stack([a * (Wd + Hd) / 2 / TILE, pos[:, 2] / TILE], 1)
    # baked light: the nearest baked vertex of the wall or the tube
    src_p = np.concatenate([W, T['position']])
    src_g = np.concatenate([rd('cave_0', 'gi', 3), T['gi']])
    gi = np.zeros((n * 3, 3))
    for i, p in enumerate(pos):
        gi[i] = src_g[np.argmin(((src_p - p) ** 2).sum(1))]

    # the tube's walls end just under the floor (they ran 2-3 m below it, and the floor strip's
    # jagged edges showed the trough as a bowl): every vertex of the tube and of the collar's ring
    # side lower than the floor + 0.3 m goes 0.15 m under the floor, tucked inside the strip's
    # jagged edge (|x| <= 2.8), so no part of it shows beside the floor
    F = rd('cave_3', 'position', 3).reshape(-1, 3, 3)
    fz = F[:, :, 2].mean(1); fx = F[:, :, 0].mean(1)
    strip = F[(np.abs(fx) < 3.2) & (fz < -8)]
    def floor_h(x, z):
        x = max(-2.9, min(2.9, x))
        best = None
        for t in strip:
            (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = t
            d = (z1 - z2) * (x0 - x2) + (x2 - x1) * (z0 - z2)
            if abs(d) < 1e-12: continue
            l0 = ((z1 - z2) * (x - x2) + (x2 - x1) * (z - z2)) / d
            l1 = ((z2 - z0) * (x - x2) + (x0 - x2) * (z - z2)) / d
            l2 = 1 - l0 - l1
            if min(l0, l1, l2) >= -1e-6: return l0 * y0 + l1 * y1 + l2 * y2
            e = -min(l0, l1, l2)
            if best is None or e < best[0]: best = (e, l0 * y0 + l1 * y1 + l2 * y2)
        return best[1]
    hole_keys = {key(q) for q in hole}
    def settle(P):
        P = P.copy(); moved = np.zeros(len(P), bool); cache = {}
        for i, q in enumerate(P):
            if key(q) in hole_keys: continue
            k = (round(q[0], 3), round(q[2], 3))
            if k not in cache: cache[k] = floor_h(q[0], q[2])
            fh = cache[k]
            if q[1] < fh + 0.3: P[i, 1] = fh - 0.15; P[i, 0] = max(-2.8, min(2.8, q[0])); moved[i] = True   # under the strip's inside
        return P, moved
    tube_p, tm = settle(tube['position'])
    pos, cm = settle(pos)
    # flat normals again where a triangle moved (winding kept; degenerate ones face up)
    def renormal(P, N, moved):
        P3 = P.reshape(-1, 3, 3); N = N.copy()
        mv = moved.reshape(-1, 3).any(1)
        for t in np.nonzero(mv)[0]:
            nn = np.cross(P3[t, 1] - P3[t, 0], P3[t, 2] - P3[t, 0]); l = np.linalg.norm(nn)
            old = N[t * 3]
            nn = nn / l if l > 1e-9 else np.array([0.0, 1.0, 0.0])
            if np.dot(nn, old) < 0: nn = -nn
            N[t * 3:t * 3 + 3] = nn
        return N
    tube_n = renormal(tube_p, tube['normal'], tm)
    nrm3 = renormal(pos, nrm3, cm)
    print('settled on the floor: %d tube vertices, %d collar vertices' % (tm.sum(), cm.sum()))
    tube = dict(tube); tube['position'] = tube_p; tube['normal'] = tube_n
    # continuous UVs follow the new positions (exported ones stay: per face, close enough)
    def uvc_of(P):
        a = np.arctan2(P[:, 1] / Hd, P[:, 0] / Wd)
        a = np.where(a < -math.pi / 2, a + 2 * math.pi, a)
        return np.stack([a * (Wd + Hd) / 2 / TILE, P[:, 2] / TILE], 1)
    capz = tube_p.reshape(-1, 3, 3)[:, :, 2].mean(1) < -46.2
    tu = uvc_of(tube_p); cap = np.repeat(capz, 3)
    tu[cap] = np.stack([tube_p[cap, 0] / TILE, tube_p[cap, 1] / TILE], 1)
    tube['uvc'] = tu
    uvc = uvc_of(pos)

    out = {
        'position': np.concatenate([tube['position'], pos]),
        'normal': np.concatenate([tube['normal'], nrm3]),
        'uv': np.concatenate([tube['uv'], uv]),
        'gi': np.concatenate([tube['gi'], gi]),
        'uvc': np.concatenate([tube['uvc'], uvc]),
    }
    count = len(out['position'])
    for attr, v in out.items():
        assert len(v) == count
        wr('cave_2', attr, v)
    # the manifest: cave_2's counts and bounding sphere
    m = open(MANIFEST, encoding='utf-8', newline='').read()
    c = out['position'].mean(0); r = float(np.sqrt(((out['position'] - c) ** 2).sum(1)).max())
    seg = re.search(r'cave_2=\{attrs=\{.*?\},order=\{[^}]*\},bs=\{[^}]*\}', m)
    s = seg.group(0)
    s2 = re.sub(r'count=\d+', 'count=%d' % count, s)
    s2 = re.sub(r'bs=\{[^}]*\}', 'bs={%r,%r,%r,%r}' % (float(c[0]), float(c[1]), float(c[2]), r), s2)
    m = m.replace(s, s2)
    open(MANIFEST, 'w', encoding='utf-8', newline='').write(m)
    print('collar triangles: %d; cave_2 now %d vertices' % (n, count))

    if '--plot' in sys.argv:
        from PIL import Image, ImageDraw
        out_p = sys.argv[sys.argv.index('--plot') + 1]
        img = Image.new('RGB', (900, 450), (12, 10, 9)); d = ImageDraw.Draw(img)
        def front(p): return (225 + p[0] * 30, 330 - p[1] * 30)
        def top(p): return (675 + p[0] * 30, 60 + (-12 - p[2]) * 30)
        for t in tris:
            for f in (front, top):
                d.polygon([f(q) for q in t], outline=(200, 160, 100))
        for f in (front, top):
            d.line([f(q) for q in hole], fill=(240, 80, 60), width=2)
            d.line([f(q) for q in ring], fill=(80, 200, 240), width=2)
        d.text((10, 10), 'front (x, y): hole red, ring blue, collar tan', fill=(220, 210, 190))
        d.text((460, 10), 'top (x, z)', fill=(220, 210, 190))
        img.save(out_p)

if __name__ == '__main__':
    main()
