"""icons.py -- round 42: the inventory's icons as idealized pictures of the six objects, in four styles.

Sources: each object as the inspect view frames it (inspect.icon_raw), rendered twice, over black and
over flat grey (scratch/icons/raw_<i>_black|grey.rgba, 192 px, rows bottom-up). Where the two differ
the backdrop shows, so they give each object's cut-out (glass partly see-through) and its colours.

Styles (assets/ui/icons/<style>_<i>.png, S px square, RGBA):
  relic     a pixel sprite: the cut-out at S px, its colours reduced to a few from the game's palette
            (the object's own hue kept), a dark outline, lit from the upper left like the shaft
  engraved  ink: a cream outline and the object's own edges as lines, its shadows as hatching
  ember     a dark silhouette with a warm rim where the shaft's light would catch it
  glyph     drawn symbols, one per power (not from the renders)
Usage: python tools/icons.py [S=24]
"""
import os, sys, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
RAW = os.path.join(ROOT, 'scratch', 'icons')
OUT = os.path.join(ROOT, 'assets', 'ui', 'icons')
P = 192
S = int(sys.argv[1]) if len(sys.argv) > 1 else 48       # (round 49: twice the game's 24 px: drawn at the window's resolution)
NAMES = ['mask', 'hand', 'lodestone', 'orbs', 'gem', 'lens']

INK = np.array([20, 15, 11])
CREAM = np.array([242, 227, 194])
BRONZE = np.array([224, 160, 112])
DIM = np.array([168, 152, 124])

def raw(name):
    return np.frombuffer(open(os.path.join(RAW, name), 'rb').read(), np.uint8).reshape(P, P, 4)[::-1, :, :3].astype(float)

def load(i):
    """colours (straight) and coverage: the object over black and over grey, against the backdrop
    alone over each (bg_*): coverage = 1 - (grey - black) / (grey bg - black bg)"""
    b, g = raw('raw_%d_black.rgba' % i), raw('raw_%d_grey.rgba' % i)
    bb, bg = raw('bg_%d_black.rgba' % i), raw('bg_%d_grey.rgba' % i)
    den = np.maximum((bg - bb).mean(2), 1.0)
    alpha = np.clip(1 - (g - b).mean(2) / den, 0, 1)
    alpha[alpha < 0.04] = 0
    col = np.clip(b - (1 - alpha[..., None]) * bb, 0, 255)          # premultiplied over black
    with np.errstate(invalid='ignore', divide='ignore'):
        straight = np.where(alpha[..., None] > 0.02, col / alpha[..., None], 0)
    return np.clip(straight, 0, 255), alpha

def crop_box(alpha, pad=4):
    ys, xs = np.nonzero(alpha > 0.15)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    s = max(y1 - y0, x1 - x0) + 2 * pad
    cy, cx = (y0 + y1) / 2, (x0 + x1) / 2
    return int(cx - s / 2), int(cy - s / 2), int(cx + s / 2), int(cy + s / 2)

def to_img(rgb, a):
    return Image.fromarray(np.concatenate([np.clip(rgb, 0, 255), np.clip(a * 255, 0, 255)[..., None]], 2).astype(np.uint8), 'RGBA')

def down(rgb, alpha, box, n):
    """crop to box and area-downsample to n x n (premultiplied, so edges don't darken)"""
    im = to_img(rgb * alpha[..., None], alpha).crop(box).resize((n, n), Image.BOX)
    a = np.asarray(im)[..., 3] / 255.0
    with np.errstate(invalid='ignore', divide='ignore'):
        c = np.where(a[..., None] > 0.01, np.asarray(im)[..., :3] / np.maximum(a[..., None], 1e-6), 0)
    return np.clip(c, 0, 255), a

def outline_of(mask):
    m = np.pad(mask, 1)
    n = np.zeros_like(m)
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        n |= np.roll(np.roll(m, dy, 0), dx, 1)
    return (n & ~m)[1:-1, 1:-1]

def edge_dir(mask, dy, dx):
    """mask pixels whose neighbour (dy, dx) is outside"""
    m = np.pad(mask, 1)
    nb = np.roll(np.roll(m, -dy, 0), -dx, 1)
    return (m & ~nb)[1:-1, 1:-1]

def kmeans(cols, k, iters=12):
    cols = cols.astype(float)
    cen = cols[np.linspace(0, len(cols) - 1, k).astype(int)]
    for _ in range(iters):
        d = ((cols[:, None] - cen[None]) ** 2).sum(2); lab = d.argmin(1)
        for j in range(k):
            if (lab == j).any(): cen[j] = cols[lab == j].mean(0)
    return cen, lab

# ------------------------------------------------------------------------------------------- styles
def relic(i, rgb, alpha):
    box = crop_box(alpha, 6)
    c, a = down(rgb, alpha, box, S - 2)
    c = np.pad(c, ((1, 1), (1, 1), (0, 0))); a = np.pad(a, 1)
    glass = i in (3, 5)
    mask = a > (0.18 if glass else 0.45)
    # the lens: thin glass reads as nothing at this size; give it a pale body
    if i == 5:
        yy, xx = np.mgrid[0:S, 0:S]; cy = cx = (S - 1) / 2
        mask |= (((xx - cx) / (S * 0.42)) ** 2 + ((yy - cy) / (S * 0.42)) ** 2) < 1
        c = np.where(mask[..., None] & (c.sum(2) < 120)[..., None], np.array([120, 112, 100]), c)
    if glass: c = np.where(mask[..., None], c * 0.85 + np.array([170, 160, 140]) * 0.15, c)
    pix = c[mask]
    k = 5 if i in (4,) else 4
    cen, lab = kmeans(pix, k)
    # warm the palette toward the cave's (keeps hue, pulls saturation a little toward bronze/cream)
    cen = cen * 0.85 + np.array([150, 120, 90]) * 0.15 if i != 4 else cen
    q = c.copy(); q[mask] = cen[lab]
    # shaft light from the upper left: a lighter rim there, a darker one opposite
    hi = edge_dir(mask, -1, 0) | edge_dir(mask, 0, -1)
    lo = edge_dir(mask, 1, 0) | edge_dir(mask, 0, 1)
    q[hi & mask] = np.clip(q[hi & mask] * 1.25 + 18, 0, 255)
    q[lo & mask & ~hi] = q[lo & mask & ~hi] * 0.7
    out = outline_of(mask)
    rgba = np.zeros((S, S, 4))
    rgba[mask, :3] = q[mask]; rgba[mask, 3] = 255
    rgba[out, :3] = INK; rgba[out, 3] = 255
    return Image.fromarray(rgba.astype(np.uint8), 'RGBA')

def engraved(i, rgb, alpha):
    box = crop_box(alpha, 6)
    c, a = down(rgb, alpha, box, S - 2)
    c = np.pad(c, ((1, 1), (1, 1), (0, 0))); a = np.pad(a, 1)
    mask = a > (0.12 if i in (3, 5) else 0.45)
    if i == 5:
        yy, xx = np.mgrid[0:S, 0:S]; cy = cx = (S - 1) / 2
        mask |= (((xx - cx) / (S * 0.42)) ** 2 + ((yy - cy) / (S * 0.42)) ** 2) < 1
    lum = (c * np.array([0.3, 0.59, 0.11])).sum(2)
    lm = lum[mask]; lo, hi = np.percentile(lm, 10), np.percentile(lm, 90)
    t = np.where(mask, np.clip((lum - lo) / max(hi - lo, 1), 0, 1), 1)
    yy, xx = np.mgrid[0:S, 0:S]
    edge = mask & ~edge_dir(mask, 0, 0) & (edge_dir(mask, -1, 0) | edge_dir(mask, 1, 0) | edge_dir(mask, 0, -1) | edge_dir(mask, 0, 1))
    hatch = mask & ~edge & (((xx + yy) % 3 == 0) & (t < 0.5) | ((xx - yy) % 3 == 0) & (t < 0.18))
    gx = np.abs(np.diff(t, axis=1, prepend=t[:, :1])); gy = np.abs(np.diff(t, axis=0, prepend=t[:1]))
    inner = mask & ~edge & ((gx + gy) > 0.55)
    rgba = np.zeros((S, S, 4))
    rgba[mask, :3] = np.array([28, 21, 16]); rgba[mask, 3] = 150           # a faint dark ground
    rgba[hatch, :3] = DIM; rgba[hatch, 3] = 255
    rgba[inner, :3] = CREAM * 0.9; rgba[inner, 3] = 255
    rgba[edge, :3] = CREAM; rgba[edge, 3] = 255
    return Image.fromarray(rgba.astype(np.uint8), 'RGBA')

def ember(i, rgb, alpha, hot_state=False):
    """a dark silhouette with a warm rim where the shaft's light would catch it (round 42); round 49
    (owner: the colours were good, "the problem was they don't have enough detail"): drawn at twice the
    game's pixels (the window's), the rim kept to its width at 24, and the object's own edges inside the
    silhouette as faint warm lines (the mask's slits, break and soot edge; the fingers; the gem's
    facets; the lens's ring; each ball and its markings), its brightest details glowing"""
    k = max(1, S // 24)
    box = crop_box(alpha, 6)
    c, a = down(rgb, alpha, box, S - 2 * k)
    c = np.pad(c, ((k, k), (k, k), (0, 0))); a = np.pad(a, k)
    mask = a > (0.15 if i in (3, 5) else 0.45)
    yy, xx = np.mgrid[0:S, 0:S]
    if i == 5:
        cy = cx = (S - 1) / 2
        mask |= (((xx - cx) / (S * 0.42)) ** 2 + ((yy - cy) / (S * 0.42)) ** 2) < 1
    rgba = np.zeros((S, S, 4))
    rgba[mask, :3] = np.array([30, 21, 15]); rgba[mask, 3] = 255
    # the object's own edges inside it (where its lit picture changes sharply)
    lum = (c * np.array([0.3, 0.59, 0.11])).sum(2)
    lm = lum[mask] if mask.any() else lum.ravel()
    lo, hi = np.percentile(lm, 5), np.percentile(lm, 95)
    t = np.clip((lum - lo) / max(hi - lo, 1), 0, 1)
    # (smoothed first: the surface's own grain is not an edge)
    tb = t.copy()
    for _ in range(k):
        tp = np.pad(tb, 1, mode='edge')
        tb = sum(tp[1 + dy:1 + dy + S, 1 + dx:1 + dx + S] for dy in (-1, 0, 1) for dx in (-1, 0, 1)) / 9
    gx = np.abs(np.diff(tb, axis=1, append=tb[:, -1:])); gy = np.abs(np.diff(tb, axis=0, append=tb[-1:]))
    grad = np.maximum(gx, gy)
    inner = mask.copy()
    for _ in range(k): inner = inner & ~edge_dir(inner, 0, 0) & ~(edge_dir(inner, -1, 0) | edge_dir(inner, 1, 0) | edge_dir(inner, 0, -1) | edge_dir(inner, 0, 1))
    line = inner & (grad > 0.13)
    soft = inner & (grad > 0.08) & ~line
    # (lone specks dropped: a line has neighbours)
    def lone(m):
        mp = np.pad(m, 1)
        nb = sum(mp[1 + dy:1 + dy + S, 1 + dx:1 + dx + S] for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx)
        return m & (nb < 2)
    line &= ~lone(line); soft &= ~lone(soft | line)
    # the light on its body, faintly (a dark object in the cave's light)
    body = np.array([30, 21, 15]) + (np.array([62, 40, 26]) - np.array([30, 21, 15])) * (t[..., None] ** 1.6) * 0.75
    rgba[mask, :3] = body[mask]
    rgba[soft, :3] = np.array([78, 50, 30])
    rgba[line, :3] = np.array([128, 80, 46])
    # the rim: edges facing up and left, a step in from them warmer (k pixels each)
    r1 = np.zeros_like(mask)
    m = mask.copy()
    for _ in range(k):
        e = (edge_dir(m, -1, 0) | edge_dir(m, 0, -1) | edge_dir(m, -1, -1)) & m
        r1 |= e; m = m & ~e
    r2 = np.zeros_like(mask)
    for _ in range(k):
        e = (edge_dir(m, -1, 0) | edge_dir(m, 0, -1)) & m
        r2 |= e; m = m & ~e
    rim1 = np.array([255, 240, 205]) if hot_state else np.array([246, 214, 160])
    rim2 = np.array([226, 152, 88]) if hot_state else np.array([150, 92, 52])
    rgba[r1, :3] = rim1
    rgba[r2, :3] = rim2
    # the brightest details glow through (slits, highlights)
    hot = mask & ~r1 & ~r2 & (lum > np.percentile(lm, 94))
    rgba[hot, :3] = np.array([236, 150, 80]) if hot_state else np.array([150, 88, 48])
    if hot_state:
        rest = mask & ~r1 & ~r2 & ~hot
        warm = np.clip(1.0 - (xx + yy) / (1.6 * S), 0, 1)[..., None]
        rgba[rest, :3] = np.clip(rgba[..., :3] * 1.25 + np.array([40, 22, 10]) * warm, 0, 255)[rest]
    return Image.fromarray(rgba.astype(np.uint8), 'RGBA')

def glyph(i):
    N = S * 8; img = Image.new('L', (N, N), 0); d = ImageDraw.Draw(img)
    W = 9                        # ~1.1 px at S
    c = N / 2
    def L(*pts, w=W): d.line([(c + x * N, c + y * N) for x, y in pts], fill=255, width=w, joint='curve')
    def O(x, y, r, w=W): d.ellipse([c + (x - r) * N, c + (y - r) * N, c + (x + r) * N, c + (y + r) * N], outline=255, width=w)
    if i == 0:      # the mask: its face, a slit eye and a pierced one, the two gashes
        L((-.30, -.32), (.26, -.36), (.36, .02), (.14, .40), (-.18, .38), (-.38, .04), (-.30, -.32))
        L((-.24, -.06), (-.06, -.06))
        O(.15, -.06, .07)
        L((-.04, .20), (.12, .20))
        L((-.12, -.30), (-.18, .26), w=W - 2)
    elif i == 1:    # the hand in its gesture: two fingers and the thumb up, two folded, the wrist
        L((-.10, .44), (-.10, .10), (-.26, -.06), (-.20, -.14), (-.06, -.02))     # wrist, thumb
        L((-.06, -.02), (-.06, -.40), (.04, -.40), (.04, -.02))                  # first finger
        L((.08, -.02), (.08, -.34), (.18, -.34), (.18, .04))                     # second
        L((.18, .04), (.28, .08), (.26, .20), (.14, .20))                        # the folded two
        L((.14, .20), (.24, .26), (.20, .36), (.12, .34))
        L((.12, .34), (.12, .44))
        L((-.14, .44), (.16, .44))
    elif i == 2:    # the lodestone: a jagged stone and its facets
        L((-.38, .06), (-.20, -.26), (.10, -.32), (.36, -.08), (.30, .24), (-.04, .34), (-.30, .26), (-.38, .06))
        L((-.20, -.26), (-.02, -.02), (.36, -.08), w=W - 3)
        L((-.02, -.02), (-.04, .34), w=W - 3)
    elif i == 3:    # the orbs
        for (x, y, r) in ((-.18, .14, .17), (.20, .18, .13), (.02, -.22, .14)):
            O(x, y, r)
            d.arc([c + (x - r * .55) * N, c + (y - r * .55) * N, c + (x + r * .55) * N, c + (y + r * .55) * N], 200, 255, fill=255, width=W - 3)
    elif i == 4:    # the gem, from the side
        L((-.36, -.04), (-.20, -.20), (.20, -.20), (.36, -.04), (0, .36), (-.36, -.04))
        L((-.36, -.04), (.36, -.04), w=W - 3)
        L((-.20, -.20), (-.08, -.04), (0, -.20), (.08, -.04), (.20, -.20), w=W - 3)
        L((-.08, -.04), (0, .36), (.08, -.04), w=W - 3)
    elif i == 5:    # the lens, face on: its rim, the light gathered to a burning point
        O(0, 0, .38)
        O(0, 0, .30, W - 4)
        d.arc([c - .24 * N, c - .24 * N, c + .24 * N, c + .24 * N], 200, 250, fill=255, width=W - 3)
        L((-.04, 0), (.04, 0), w=W - 2); L((0, -.04), (0, .04), w=W - 2)
        for a in range(0, 360, 45):
            r0, r1 = .09, .15
            L((math.cos(math.radians(a)) * r0, math.sin(math.radians(a)) * r0), (math.cos(math.radians(a)) * r1, math.sin(math.radians(a)) * r1), w=W - 4)
    v = np.asarray(img.resize((S, S), Image.BOX)) / 255.0
    lines = v > 0.2
    rgba = np.zeros((S, S, 4))
    rgba[lines, :3] = CREAM; rgba[lines, 3] = 255
    under = outline_of(lines) & ~lines
    rgba[under, :3] = INK; rgba[under, 3] = 170
    return Image.fromarray(rgba.astype(np.uint8), 'RGBA')

def lit(i, rgb, alpha, hot_state=False):
    """round 48 (owner: the icons "need to be more visible in some important way, currently they're not
    making it clear which item is which"): EMBER's light on the object's own colours. The cut-out at icon
    size (smooth, so the inner detail survives: the mask's soot half and slits, the hand's raised
    fingers, the gem's colours, the orbs' several balls), its levels stretched and its colour lifted so
    each reads at 24 px; glass given a body (the lens a pale disc with a bright rim, the orbs pale
    spheres with a glint); then EMBER's warm rim on the edges toward the light and a dark outline, so
    it stands off the lamp's glow. Hot: brighter, the rim whiter."""
    box = crop_box(alpha, 6)
    im = to_img(rgb * alpha[..., None], alpha).crop(box).resize((S - 2, S - 2), Image.LANCZOS)
    a = np.asarray(im)[..., 3] / 255.0
    c = np.where(a[..., None] > 0.02, np.asarray(im)[..., :3] / np.maximum(a[..., None], 1e-3), 0)
    c = np.pad(c, ((1, 1), (1, 1), (0, 0))); a = np.pad(a, 1)
    glass = i in (3, 5)
    mask = a > (0.14 if glass else 0.4)
    yy, xx = np.mgrid[0:S, 0:S]
    if i == 5:
        cy = cx = (S - 1) / 2
        disc = (((xx - cx) / (S * 0.43)) ** 2 + ((yy - cy) / (S * 0.43)) ** 2)
        mask |= disc < 1
        ring = (disc > 0.62) & (disc < 1)
    # the viewer's key light is warm (1, 0.9, 0.72): take it out, so white reads white and bone bone
    c = c / np.array([1.0, 0.9, 0.72])
    lum = (c * np.array([0.3, 0.59, 0.11])).sum(2)
    lm = lum[mask] if mask.any() else lum.ravel()
    lo, hi = np.percentile(lm, 3), np.percentile(lm, 96)
    t = np.clip((lum - lo) / max(hi - lo, 1), 0, 1) ** 0.8
    # levels: keep the hue, set the brightness from the stretched luminance
    chroma = c / np.maximum(lum[..., None], 1)
    q = np.clip(chroma * (24 + t * 226)[..., None], 0, 255)
    # colour: the rock and the gem lifted; white and bone kept near neutral
    g = q.mean(2, keepdims=True)
    q = np.clip(g + (q - g) * {0: 0.6, 1: 0.7, 2: 1.7, 3: 1.0, 4: 1.15, 5: 1.0}[i], 0, 255)
    if i == 1:
        # the hand is thin: bone, and a step brighter, so it is not lost against the glow
        q = np.where(mask[..., None], np.clip(q * 0.35 + np.array([214, 200, 172]) * (0.35 + 0.5 * t[..., None]), 0, 255), q)
    if i == 2:
        # the lodestone: iron-dark with its rust
        q = np.where(mask[..., None], np.clip(q * np.array([1.0, 0.78, 0.6]) * 0.85, 0, 255), q)
    if glass:
        # glass: a pale body tinted by what shows through, darker toward its far edge
        base = np.array([150, 160, 150]) if i == 3 else np.array([165, 158, 140])
        q = np.where(mask[..., None], q * 0.45 + base * 0.55, q)
        if i == 5:
            q[ring & mask] = np.clip(q[ring & mask] * 1.25 + 25, 0, 255)
    # EMBER's warm cast and light from the upper left (the shaft), a darker edge opposite
    q = q * np.array([1.04, 0.99, 0.92])
    hi_e = (edge_dir(mask, -1, 0) | edge_dir(mask, 0, -1)) & mask
    lo_e = (edge_dir(mask, 1, 0) | edge_dir(mask, 0, 1)) & mask & ~hi_e
    rim = np.array([255, 236, 196]) if hot_state else np.array([246, 214, 160])
    q[hi_e] = q[hi_e] * 0.35 + rim * 0.65
    q[lo_e] = q[lo_e] * 0.62
    if glass:
        # a glint high on each
        gl = mask & (xx + yy < S * 0.75) & (t > 0.8)
        q[gl] = np.clip(q[gl] * 0.4 + 255 * 0.6, 0, 255)
    if hot_state: q = np.clip(q * 1.18 + 10, 0, 255)
    out = outline_of(mask)
    rgba = np.zeros((S, S, 4))
    rgba[mask, :3] = np.clip(q[mask], 0, 255); rgba[mask, 3] = 255
    rgba[out, :3] = INK; rgba[out, 3] = 255
    return Image.fromarray(rgba.astype(np.uint8), 'RGBA')

def render_style(i, rgb, alpha):
    """the current icons (the model as rendered), at the new size: for the comparison"""
    box = crop_box(alpha, 6)
    c, a = down(rgb, alpha, box, S)
    rgba = np.concatenate([c, (a * 255)[..., None]], 2)
    return Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), 'RGBA')

def main():
    os.makedirs(OUT, exist_ok=True)
    sheet = Image.new('RGBA', (S * 6 * 4 + 40, S * 5 * 4 + 10), (24, 19, 15, 255))
    for i in range(6):
        rgb, alpha = load(i)
        for k, (name, fn) in enumerate((('render', lambda: render_style(i, rgb, alpha)), ('relic', lambda: relic(i, rgb, alpha)),
                                        ('engraved', lambda: engraved(i, rgb, alpha)), ('ember', lambda: ember(i, rgb, alpha)), ('glyph', lambda: glyph(i)))):
            im = fn()
            im.save(os.path.join(OUT, '%s_%d.png' % (name, i)))
            if name == 'ember': ember(i, rgb, alpha, True).save(os.path.join(OUT, 'ember_hot_%d.png' % i))
            sheet.alpha_composite(im.resize((S * 4, S * 4), Image.NEAREST), (5 + i * (S * 4 + 6), 5 + k * S * 4))
        lit(i, rgb, alpha).save(os.path.join(OUT, 'lit_%d.png' % i))
        lit(i, rgb, alpha, True).save(os.path.join(OUT, 'lit_hot_%d.png' % i))
    sheet.save(os.path.join(ROOT, 'scratch', 'icons', 'styles_sheet.png'))
    print('wrote', OUT)

if __name__ == '__main__':
    main()
