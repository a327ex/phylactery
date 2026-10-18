#!/usr/bin/env python3
"""title.py -- the PHYLACTERY title laid on a store painting (Phylactery 20, 2026-10-18).

The manner is the It Follows cover's (his source): the serif in a warm cream, lit from above, sitting in the painting's
dark negative space; a soft shadow of itself and, only where the ground under it is not dark enough, a soft darkening
that reads as the painting's own vignette. Set in Phylactery Serif (identity/font), shaped and kerned by HarfBuzz.

    from title import wordmark, lay
    wm = wordmark('Phylactery', width=600, tracking=0)          # RGBA, cream, tight to the ink
    out, where = lay(painting_rgb, wm, at='auto', band=(0.55, 0.95), align='centre')

lay(..., at='auto') tries positions inside `band` (fractions of the height for the text's centre) and `align`
('centre' | 'left' | 'right' | 'any'), and takes the one whose ground is darkest and calmest.
"""
import os
import numpy as np
import uharfbuzz as hb
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(os.path.dirname(HERE), 'identity', 'font', 'PhylacterySerif-Regular.ttf')
TOP, BOTTOM = np.array([250, 240, 214]), np.array([218, 194, 150])     # the cream, lit from above
SHADOW = np.array([12, 7, 3])


def wordmark(text, width, tracking=0.0, ss=3):
    """the text's ink tight to its box, `width` px wide; tracking in em (0.08 = 8% of the em between letters)"""
    tt = TTFont(FONT)
    upm = tt['head'].unitsPerEm
    font = hb.Font(hb.Face(open(FONT, 'rb').read()))
    buf = hb.Buffer(); buf.add_str(text); buf.guess_segment_properties()
    hb.shape(font, buf, {'kern': True, 'liga': False})
    order, glyf = tt.getGlyphOrder(), tt['glyf']
    cmap = {v: c for c, v in tt.getBestCmap().items()}
    x, placed = 0, []
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        placed.append((info.codepoint, x + pos.x_offset))
        x += pos.x_advance + tracking * upm
    xs, ys = [], []
    for gid, gx in placed:
        g = glyf[order[gid]]
        if g.numberOfContours:
            xs += [gx + g.xMin, gx + g.xMax]; ys += [g.yMin, g.yMax]
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    k = width * ss / (x1 - x0)
    W, H = round((x1 - x0) * k) + 4 * ss, round((y1 - y0) * k) + 4 * ss
    a = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(a)
    f = ImageFont.truetype(FONT, round(upm * k))
    for gid, gx in placed:
        d.text(((gx - x0) * k + 2 * ss, (y1) * k + 2 * ss), chr(cmap[order[gid]]), font=f, fill=255, anchor='ls')
    a = a.resize((round(W / ss), round(H / ss)), Image.LANCZOS)
    al = np.asarray(a).astype(np.float32) / 255
    h = al.shape[0]
    t = np.linspace(0, 1, h)[:, None, None]
    rgb = TOP * (1 - t) + BOTTOM * t
    rgb = np.broadcast_to(rgb, (h, al.shape[1], 3))
    out = np.dstack([rgb, al[..., None] * 255]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(out, 'RGBA')


def ground(img):
    """how unfit each pixel is to carry the title: brightness plus local busyness"""
    g = np.asarray(img.convert('L')).astype(np.float32) / 255
    blur = np.asarray(img.convert('L').filter(ImageFilter.GaussianBlur(6))).astype(np.float32) / 255
    busy = np.abs(g - blur)
    busy = np.asarray(Image.fromarray((busy * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6))).astype(np.float32) / 255
    return blur + 2.5 * busy


def pick(img, wm, band=(0.08, 0.92), align='centre', margin=0.06):
    W, H = img.size
    w, h = wm.size
    cost = ground(img)
    ii = cost.cumsum(0).cumsum(1)

    def box_mean(x0, y0, x1, y1):
        s = ii[y1 - 1, x1 - 1] - (ii[y0 - 1, x1 - 1] if y0 else 0) - (ii[y1 - 1, x0 - 1] if x0 else 0) + (ii[y0 - 1, x0 - 1] if x0 and y0 else 0)
        return s / ((x1 - x0) * (y1 - y0))
    mx, my = round(W * margin), round(H * margin)
    xs = {'centre': [(W - w) // 2], 'left': [mx], 'right': [W - w - mx],
          'any': list(range(mx, max(mx + 1, W - w - mx), max(4, W // 60)))}[align]
    best = None
    for cy in np.linspace(band[0], band[1], 40):
        y = int(round(cy * H - h / 2))
        if y < my or y + h > H - my:
            continue
        for x in xs:
            x = max(0, min(W - w, x))
            c = box_mean(x, y, x + w, y + h)
            if best is None or c < best[0]:
                best = (c, x, y)
    if best is None:
        best = (0, (W - w) // 2, int(H * (band[0] + band[1]) / 2 - h / 2))
    return best[1], best[2]


def lay(img, wm, at='auto', band=(0.08, 0.92), align='centre', scrim=1.0, shadow=0.7):
    """the title on the painting; returns (RGB image, (x, y) of the title's box)"""
    img = img.convert('RGB')
    W, H = img.size
    w, h = wm.size
    x, y = pick(img, wm, band, align) if at == 'auto' else at
    B = np.asarray(img).astype(np.float32) / 255
    al = Image.new('L', (W, H), 0); al.paste(wm.split()[3], (x, y))
    # a soft darkening under it, only as much as the ground needs (a vignette, not a box)
    under = B[max(0, y - h // 2):y + h + h // 2, max(0, x):x + w].mean()
    need = np.clip((under - 0.16) / 0.30, 0, 1) * scrim
    if need > 0:
        sc = Image.new('L', (W, H), 0)
        ImageDraw.Draw(sc).ellipse([x - 0.12 * w, y - 0.9 * h, x + 1.12 * w, y + 1.9 * h], fill=255)
        sc = np.asarray(sc.filter(ImageFilter.GaussianBlur(0.45 * h))).astype(np.float32)[..., None] / 255
        B = B * (1 - 0.62 * need * sc)
    # its own soft shadow, a little below
    sh = np.asarray(al.filter(ImageFilter.GaussianBlur(max(2, 0.07 * h)))).astype(np.float32)[..., None] / 255
    sh = np.roll(sh, max(1, round(0.03 * h)), axis=0)
    B = B * (1 - shadow * sh) + (SHADOW / 255) * shadow * sh
    out = Image.fromarray((B.clip(0, 1) * 255 + 0.5).astype(np.uint8)).convert('RGBA')
    out.alpha_composite(wm, (x, y))
    return out.convert('RGB'), (x, y, w, h)
