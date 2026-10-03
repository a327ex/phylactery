"""cave_look.py -- round 41: the cave's surfaces without seams or noise (Anchor build only).

Writes, beside the exported cave (assets/port/cave/):
  tex/cave_rock_<v>.rgba, tex/cave_floor_<v>.rgba   (128 x 128, 32 texels/m: a 4 m tile)
      for each surface variant v (slabs, quiet), painted as web/src/textures.js paints (cellular
      patches, tileable value noise) but with close tones and no dark crack around every patch
  geo/cave_<i>.uvc.f32   continuous UVs for the shell (wall, dome, tunnel, floor), in 2 m units like
      the exported ones (world_uv in cave.js: u = metres/2), so a texture's own repeat scales them:
        floor   top-down (x, z) everywhere
        tunnel  around its arch (arc length) and along it
        wall    around the cave's axis at a fixed radius whose circumference is a whole number of
                tiles (no wrap seam), and along the wall's profile (arc length up the lathe)
        dome    from below (x, z) where the ceiling leans over; the shaft around its own axis
      The exported UVs project each triangle onto its own dominant axis, so on the curved shell the
      pattern jumps at triangle edges; these are one mapping per region (a vertex shared by two
      triangles gets one UV). The rocks keep theirs: their faces meet at real edges.
Usage: python tools/cave_look.py
"""
import math, os, struct
import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'port', 'cave')
TILE = 2.0          # the exported UVs' unit: one 64-texel tile = 2 m

# ------------------------------------------------------------------------------------------- paint
def imul(a, b): return ((a & 0xFFFFFFFF) * (b & 0xFFFFFFFF)) & 0xFFFFFFFF
def lattice_hash(ix, iy, seed):
    h = imul(ix, 374761393) ^ imul(iy, 668265263) ^ imul(seed, 1442695041)
    h = imul(h ^ (h >> 13), 1274126177)
    h ^= h >> 16
    return (h & 0xFFFFFFFF) / 4294967296.0

def vnoise(x, y, px, py, seed):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    u, v = fx*fx*(3 - 2*fx), fy*fy*(3 - 2*fy)
    m = lambda a, p: a % p
    a = lattice_hash(m(ix, px), m(iy, py), seed); b = lattice_hash(m(ix + 1, px), m(iy, py), seed)
    c = lattice_hash(m(ix, px), m(iy + 1, py), seed); d = lattice_hash(m(ix + 1, px), m(iy + 1, py), seed)
    return (a + (b - a)*u) + ((c + (d - c)*u) - (a + (b - a)*u))*v

def fbm(x, y, w, h, cells, seed, oct=3):
    s = tot = 0.0; amp = 1.0; f = 1
    for o in range(oct):
        cx = cells*f; cy = max(1, round(cells*f*h/w))
        s += amp*vnoise(x/w*cx, y/h*cy, cx, cy, seed + o*101)
        tot += amp; amp *= 0.5; f *= 2
    return s/tot

def cells2(x, y, w, h, n, seed):
    gx, gy = x/w*n, y/h*n
    ix, iy = math.floor(gx), math.floor(gy)
    d1 = d2 = 9.0; cid = 0.0
    for j in (-1, 0, 1):
        for i in (-1, 0, 1):
            cx, cy = ix + i, iy + j
            wx, wy = cx % n, cy % n
            px, py = cx + lattice_hash(wx, wy, seed), cy + lattice_hash(wx, wy, seed + 7)
            d = math.hypot(gx - px, gy - py)
            if d < d1: d2 = d1; d1 = d; cid = lattice_hash(wx, wy, seed + 13)
            elif d < d2: d2 = d
    return d1, d2, cid

def mix(a, b, t): return [a[k] + (b[k] - a[k])*t for k in range(3)]

# web/src/textures.js PAL (sRGB 0-255)
ROCK = dict(hi=[168, 150, 126], mid=[114, 102, 89], lo=[90, 81, 72], deep=[64, 58, 53], base=[136, 121, 103])
FLOOR = dict(hi=[164, 142, 110], base=[132, 114, 90], lo=[104, 90, 74], deep=[76, 67, 57])
BRONZE = [186, 146, 96]

def tones(lo, hi, n):
    return [mix(lo, hi, k/(n - 1)) for k in range(n)]

def paint(S, fn):
    img = np.zeros((S, S, 4), dtype=np.uint8)
    for y in range(S):
        for x in range(S):
            c = fn(x, y)
            img[y, x, :3] = [max(0, min(255, int(v))) for v in c]
            img[y, x, 3] = 255
    return img

S = 128

# SLABS: the palette-knife slabs of the cover, broad (about 0.7 m), each one flat tone out of four
# close ones, a slight second tone inside, no crack around them; a rare warm chip on a slab's edge.
def rock_slabs(seed=11):
    T = tones(mix(ROCK['lo'], ROCK['mid'], 0.35), mix(ROCK['mid'], ROCK['base'], 0.75), 4)
    def f(x, y):
        d1, d2, cid = cells2(x + 0.5, y + 0.5, S, S, 6, seed)
        n = fbm(x, y, S, S, 3, seed + 3, 2)
        k = max(0, min(3, int(cid*3.4 + (n - 0.5)*0.8)))
        c = T[k]
        if fbm(x, y, S, S, 10, seed + 9, 2) > 0.66: c = mix(c, T[max(0, k - 1)], 0.5)
        if d2 - d1 < 0.06 and cid > 0.8 and lattice_hash(x, y, seed + 21) > 0.5: c = mix(c, BRONZE, 0.18)
        return c
    return paint(S, f)

def floor_slabs(seed=21):
    T = tones(mix(FLOOR['lo'], FLOOR['base'], 0.3), mix(FLOOR['base'], FLOOR['hi'], 0.3), 3)
    def f(x, y):
        d1, d2, cid = cells2(x + 0.5, y + 0.5, S, S, 12, seed)
        n = fbm(x, y, S, S, 4, seed + 5, 2)
        k = max(0, min(2, int(cid*2.2 + (n - 0.5)*1.2)))
        c = T[k]
        g = lattice_hash(x, y, seed + 99)
        if g > 0.97: c = mix(c, FLOOR['hi'], 0.35)
        elif g < 0.03: c = mix(c, FLOOR['deep'], 0.45)
        return c
    return paint(S, f)

# QUIET: almost one tone; broad mottling (a metre or two across) in three close steps and a few
# pits. The faceted rock and the light carry the form.
def rock_quiet(seed=11):
    T = tones(mix(ROCK['lo'], ROCK['mid'], 0.55), mix(ROCK['mid'], ROCK['base'], 0.45), 3)
    def f(x, y):
        n = fbm(x, y, S, S, 3, seed + 3, 3)
        k = 0 if n < 0.42 else (1 if n < 0.6 else 2)
        c = T[k]
        g = lattice_hash(x, y, seed + 31)
        if g > 0.985: c = mix(c, ROCK['deep'], 0.45)
        return c
    return paint(S, f)

def floor_quiet(seed=21):
    T = tones(mix(FLOOR['lo'], FLOOR['base'], 0.45), mix(FLOOR['base'], FLOOR['hi'], 0.15), 3)
    def f(x, y):
        n = fbm(x, y, S, S, 4, seed + 5, 3)
        k = 0 if n < 0.42 else (1 if n < 0.6 else 2)
        c = T[k]
        g = lattice_hash(x, y, seed + 99)
        if g > 0.985: c = mix(c, FLOOR['hi'], 0.3)
        elif g < 0.02: c = mix(c, FLOOR['deep'], 0.4)
        return c
    return paint(S, f)

# --------------------------------------------------------------------------------------------- UVs
def read_f32(name, attr, size):
    b = open(os.path.join(ROOT, 'geo', '%s.%s.f32' % (name, attr)), 'rb').read()
    return np.frombuffer(b, dtype='<f4').reshape(-1, size).astype(np.float64)

def write_f32(name, attr, a):
    open(os.path.join(ROOT, 'geo', '%s.%s.f32' % (name, attr)), 'wb').write(np.asarray(a, dtype='<f4').tobytes())

def smoothstep(a, b, x):
    t = np.clip((x - a)/(b - a), 0, 1); return t*t*(3 - 2*t)

SUN = np.array([0.11, 1.0, 0.05]); SUN = SUN/np.linalg.norm(SUN)
SUN_XZ = (SUN[0]/SUN[1], SUN[2]/SUN[1])
PROFILE = [(-0.8, 16.8), (0.8, 17.4), (2.6, 17.8), (4.8, 17.2), (7.2, 15.4), (9.4, 12.6), (11.2, 9.6),
           (12.6, 6.8), (13.6, 4.4), (14.3, 2.6), (15.0, 2.1), (16.5, 1.95), (19.0, 2.05), (22.0, 1.95),
           (25.5, 2.1), (29.0, 2.2), (33.0, 2.05), (37.0, 2.15), (41.0, 2.1), (44.0, 2.2), (46.5, 2.3)]

def axis_at(h):
    k = smoothstep(11.5, 15.0, h)
    return SUN_XZ[0]*h*k, SUN_XZ[1]*h*k

def profile_s(r, h):
    """(radius, height) -> arc length up the profile at the nearest point, and that point's radius"""
    P = np.array([[p[1], p[0]] for p in PROFILE])   # (r, h)
    seg = P[1:] - P[:-1]
    L = np.hypot(seg[:, 0], seg[:, 1]); S0 = np.concatenate([[0], np.cumsum(L)[:-1]])
    q = np.stack([r, h], axis=1)[:, None, :]        # (n, 1, 2)
    t = np.clip(((q - P[None, :-1]) * seg[None]).sum(-1) / (L[None]**2), 0, 1)
    near = P[None, :-1] + t[..., None]*seg[None]
    d = np.hypot(*(q - near).transpose(2, 0, 1))
    k = d.argmin(axis=1)
    i = np.arange(len(r))
    return S0[k] + t[i, k]*L[k], near[i, k, 0]

def wrap_fix(u, period):
    """per triangle: no triangle spans the wrap (vertices moved by whole periods to the first's side)"""
    u = u.reshape(-1, 3).copy()
    for c in (1, 2):
        d = u[:, c] - u[:, 0]
        u[:, c] -= np.round(d/period)*period
    return u.reshape(-1)

def shell_uv(pos):
    x, y, z = pos[:, 0], pos[:, 1], pos[:, 2]
    cx, cz = axis_at(y)
    th = np.arctan2(z - cz, x - cx)
    rr = np.hypot(x - cx, z - cz)
    s, pr = profile_s(rr, y)
    # three regions, decided per triangle by its centroid's place on the profile
    tri_pr = pr.reshape(-1, 3).mean(1); tri_h = y.reshape(-1, 3).mean(1)
    region = np.where(tri_h > 14.6, 2, np.where(tri_pr < 12.4, 1, 0))      # 0 wall, 1 ceiling, 2 shaft
    region = np.repeat(region, 3)
    N0 = round(2*math.pi*14.96/4.0)*2         # tiles round the wall (an even count of 2 m units)
    N2 = round(2*math.pi*2.2/4.0)*2
    u0 = wrap_fix(th/(2*math.pi)*N0, N0); v0 = s/TILE
    u1 = x/TILE; v1 = z/TILE
    u2 = wrap_fix(th/(2*math.pi)*N2, N2); v2 = y/TILE
    u = np.where(region == 0, u0, np.where(region == 1, u1, u2))
    v = np.where(region == 0, v0, np.where(region == 1, v1, v2))
    return np.stack([u, v], 1), region

def tunnel_uv(pos):
    x, y, z = pos[:, 0], pos[:, 1], pos[:, 2]
    W, H = 2.7 + 0.9, 4.2 + 0.6
    a = np.arctan2(y/H, x/W)
    a = np.where(a < -math.pi/2, a + 2*math.pi, a)              # the arch runs -0.12 pi .. 1.12 pi
    u = a*(W + H)/2/TILE
    v = z/TILE
    cap = (z.reshape(-1, 3).mean(1) < -46.2)                     # the far end's cap faces down the tunnel
    cap = np.repeat(cap, 3)
    u = np.where(cap, x/TILE, u); v = np.where(cap, y/TILE, v)
    return np.stack([u, v], 1)

def main():
    os.makedirs(os.path.join(ROOT, 'tex'), exist_ok=True)
    for name, img in (('cave_rock_slabs', rock_slabs()), ('cave_floor_slabs', floor_slabs()),
                      ('cave_rock_quiet', rock_quiet()), ('cave_floor_quiet', floor_quiet())):
        open(os.path.join(ROOT, 'tex', name + '.rgba'), 'wb').write(img.tobytes())
        print('wrote', name)
    # cave_0 wall, cave_1 dome (the lathe), cave_2 tunnel, cave_3 floor (assets/port/cave.lua meshes)
    for g in ('cave_0', 'cave_1'):
        uv, region = shell_uv(read_f32(g, 'position', 3))
        write_f32(g, 'uvc', uv)
        print('wrote', g, 'uvc', len(uv), 'regions', np.bincount(region//1, minlength=3)//3)
    write_f32('cave_2', 'uvc', tunnel_uv(read_f32('cave_2', 'position', 3)))
    p = read_f32('cave_3', 'position', 3)
    write_f32('cave_3', 'uvc', np.stack([p[:, 0]/TILE, p[:, 2]/TILE], 1))
    print('wrote tunnel + floor uvc')
    # previews for my own check (not assets)
    try:
        from PIL import Image
        out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'scratch', 'look')
        os.makedirs(out, exist_ok=True)
        for name in ('cave_rock_slabs', 'cave_floor_slabs', 'cave_rock_quiet', 'cave_floor_quiet'):
            a = np.frombuffer(open(os.path.join(ROOT, 'tex', name + '.rgba'), 'rb').read(), dtype=np.uint8).reshape(S, S, 4)
            Image.fromarray(np.tile(a, (2, 2, 1))).resize((S*4, S*4), Image.NEAREST).save(os.path.join(out, name + '.png'))
        for name in ('cave_rock', 'cave_floor'):
            a = np.frombuffer(open(os.path.join(ROOT, 'tex', name + '.rgba'), 'rb').read(), dtype=np.uint8).reshape(64, 64, 4)
            Image.fromarray(np.tile(a, (4, 4, 1))).resize((S*4, S*4), Image.NEAREST).save(os.path.join(out, name + '_now.png'))
    except ImportError:
        pass

if __name__ == '__main__':
    main()
