"""hud_fonts.py -- the HUD's fonts as glyph tables (port/hud_fonts.lua), from tools/bitmap_fonts.py and TrueType.

FACET (owner, 2026-10-03, round 43: "Let's go with faceted"): capitals whose rounds are cut into planes,
like the cave's broken rock; 7 rows; each advance is the letter's width and the 1 px after it.

Round 53 (owner, 2026-10-07: "We need to audition more fonts, the current ones look like they don't fit the
game in some important way, perhaps a clash of pixel sizes"): since round 49 the icons are drawn at the
window's resolution (one screen pixel per icon pixel) while FACET is drawn at the game's (two). The
candidates below are `hi`: drawn at the window's resolution, one screen pixel per glyph pixel, at about the
same height on screen as FACET:
  FACET_FINE  FACET at twice the detail (scale2x: the same letters, their cuts finer)
  FACET_THIN  FACET_FINE thinned to one-pixel strokes (the icons' line weight)
  JACQUARD    Jacquard 24 (OFL): a pixel blackletter on its own 24 px grid
  DOTGOTHIC   DotGothic16 (OFL): a plain pixel face on a 16 px grid
  PIXELIFY    Pixelify Sans (OFL) on its grid
  FELL        IM Fell English SC (OFL): no pixels at all, anti-aliased (a control)
Pixel fonts are drawn 8x larger and sampled back on the grid phase where their cells are cleanest, so each
glyph pixel is either on or off.
Usage: python tools/hud_fonts.py
"""
import os, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bitmap_fonts as BF

CHARS = [chr(c) for c in range(33, 127) if not ('a' <= chr(c) <= 'z')]

def lua_key(ch):
    if ch == "'": return '"\'"'
    if ch == '\\': return "'\\\\'"
    return repr(ch)

def scale2x(rows):
    """EPX / scale2x: twice the size, the diagonal steps made finer (the letter's cuts stay cuts)."""
    h, w = len(rows), len(rows[0])
    def at(x, y): return rows[y][x] if 0 <= x < w and 0 <= y < h else '.'
    out = [[None]*(2*w) for _ in range(2*h)]
    for y in range(h):
        for x in range(w):
            P = at(x, y); A = at(x, y - 1); B = at(x + 1, y); C = at(x - 1, y); D = at(x, y + 1)
            e0 = e1 = e2 = e3 = P
            if C == A and C != D and A != B: e0 = A
            if A == B and A != C and B != D: e1 = B
            if D == C and D != B and C != A: e2 = C
            if B == D and B != A and D != C: e3 = D
            out[2*y][2*x], out[2*y][2*x + 1], out[2*y + 1][2*x], out[2*y + 1][2*x + 1] = e0, e1, e2, e3
    return [''.join(r) for r in out]

def thin(rows):
    """Zhang-Suen thinning: the strokes down to one pixel (FACET_FINE's letters at the icons' line weight)."""
    h, w = len(rows), len(rows[0])
    g = [[1 if rows[y][x] == '#' else 0 for x in range(w)] for y in range(h)]
    def at(x, y): return g[y][x] if 0 <= x < w and 0 <= y < h else 0
    changed = True
    while changed:
        changed = False
        for step in (0, 1):
            kill = []
            for y in range(h):
                for x in range(w):
                    if not g[y][x]: continue
                    P = [at(x, y - 1), at(x + 1, y - 1), at(x + 1, y), at(x + 1, y + 1), at(x, y + 1), at(x - 1, y + 1), at(x - 1, y), at(x - 1, y - 1)]
                    B = sum(P)
                    A = sum(1 for i in range(8) if P[i] == 0 and P[(i + 1) % 8] == 1)
                    if 2 <= B <= 6 and A == 1:
                        if step == 0 and P[0]*P[2]*P[4] == 0 and P[2]*P[4]*P[6] == 0: kill.append((x, y))
                        if step == 1 and P[0]*P[2]*P[6] == 0 and P[0]*P[4]*P[6] == 0: kill.append((x, y))
            for x, y in kill: g[y][x] = 0
            if kill: changed = True
    return [''.join('#' if g[y][x] else '.' for x in range(w)) for y in range(h)]

def bitmap_font(glyphs, rows, space):
    out = {}
    for ch, rr in glyphs.items():
        off = rows - len(rr)
        px = [(x, y + off) for y, row in enumerate(rr) for x, c in enumerate(row) if c == '#']
        out[ch] = { 'w': len(rr[0]) + 1, 'px': px }
    return { 'h': rows, 'cap': rows, 'space': space, 'glyphs': out }

def ttf_font(path, em, pixel=True, cap_ref='H'):
    """A TrueType face as glyph pixels at `em` px: pixel faces sampled on their grid, smooth ones with alpha."""
    from PIL import Image, ImageDraw, ImageFont
    import numpy as np
    S = 8 if pixel else 1
    ft = ImageFont.truetype(path, em*S)
    asc, desc = ft.getmetrics()
    # the capitals' top and the baseline (in px at em)
    bb = ft.getbbox(cap_ref)
    cap_top = bb[1]
    base = asc
    phase = (0, 0)
    if pixel:
        # the grid phase where the cells are cleanest (on a sample text)
        im = Image.new('L', (em*S*16, em*S*3), 0)
        ImageDraw.Draw(im).text((em*S, em*S), 'HAMBURGEFONTS', font=ft, fill=255)
        a = np.asarray(im).astype(np.float32)/255
        best = None
        for dy in range(S):
            for dx in range(S):
                sub = a[dy:dy + (a.shape[0] - dy)//S*S, dx:dx + (a.shape[1] - dx)//S*S]
                cells = sub.reshape(sub.shape[0]//S, S, sub.shape[1]//S, S).mean(axis=(1, 3))
                on = cells > 0.02
                if on.sum() == 0: continue
                err = (np.minimum(cells, 1 - cells)[on]).mean()
                if best is None or err < best[0]: best = (err, dx, dy)
        phase = (best[1], best[2])
    glyphs = {}
    top_min, bot_max = 10**9, -10**9
    raw = {}
    for ch in CHARS + [' ']:
        adv = ft.getlength(ch)
        W = int(adv) + em*S*2
        Hh = (asc + desc) + em*S*2
        im = Image.new('L', (W, Hh), 0)
        ImageDraw.Draw(im).text((em*S, em*S), ch, font=ft, fill=255)
        a = np.asarray(im).astype(np.float32)/255
        if pixel:
            dx, dy = phase
            # cells aligned so the text origin (em*S) falls on a cell edge offset by the phase
            ox, oy = (em*S + dx) % S, (em*S + dy) % S
            sub = a[oy:oy + (a.shape[0] - oy)//S*S, ox:ox + (a.shape[1] - ox)//S*S]
            cells = sub.reshape(sub.shape[0]//S, S, sub.shape[1]//S, S).mean(axis=(1, 3))
            vals = (cells >= 0.5).astype(np.float32)
            x0, y0 = (em*S - ox)//S, (em*S - oy)//S
            advp = int(round(adv/S))
        else:
            vals = a
            x0, y0 = em, em
            advp = int(round(adv))
        ys, xs = np.nonzero(vals > (0.5 if pixel else 0.06))
        pts = []
        for y, x in zip(ys.tolist(), xs.tolist()):
            pts.append((x - x0, y - y0, float(vals[y, x])))
        raw[ch] = (advp, pts)
    # rows measured from the capitals' top
    capt = int(round(cap_top/(S if pixel else 1)))
    for ch, (advp, pts) in raw.items():
        pts = [(x, y - capt, v) for (x, y, v) in pts]
        for (_, y, _) in pts: top_min = min(top_min, y); bot_max = max(bot_max, y)
        raw[ch] = (advp, pts)
    capb = int(round((base - cap_top)/(S if pixel else 1)))
    for ch, (advp, pts) in raw.items():
        glyphs[ch] = { 'w': max(1, advp), 'px': [(x, y) for (x, y, v) in pts] }
        if not pixel: glyphs[ch]['pa'] = [round(v, 2) for (x, y, v) in pts]
    space = glyphs[' ']['w']
    del glyphs[' ']
    return { 'h': capb, 'cap': capb, 'space': space, 'glyphs': glyphs, 'top': min(0, top_min), 'bottom': bot_max }

def write(fonts):
    out = ['-- generated by tools/hud_fonts.py: the HUD\'s fonts as glyph tables (pixels from the top of the capitals;',
           '-- `hi` ones are drawn at the window\'s resolution, one screen pixel per glyph pixel)', 'return {']
    for name, f in fonts:
        extra = ''
        if f.get('hi'): extra += ', hi = true'
        if f.get('label'): extra += ', label = %r' % f['label']
        out.append('  %s = { h = %d, cap = %d, upper = true, space = %d%s, glyphs = {' % (name, f['h'], f['cap'], f['space'], extra))
        for ch, g in sorted(f['glyphs'].items()):
            px = ','.join('%d,%d' % q for q in g['px'])
            line = '    [%s] = { w = %d, px = { %s }' % (lua_key(ch), g['w'], px)
            if 'pa' in g: line += ', pa = { %s }' % ','.join('%g' % v for v in g['pa'])
            out.append(line + ' },')
        out.append('  } },')
    out.append('}')
    open(os.path.join(ROOT, 'port', 'hud_fonts.lua'), 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')

def main():
    F = os.path.join(ROOT, 'assets', 'fonts')
    rows = 7
    glyphs = dict(BF.PUNCT); glyphs.update(BF.FACET)
    facet = bitmap_font(glyphs, rows, 3); facet['label'] = 'FACETED'
    fine = bitmap_font({ ch: scale2x(rr) for ch, rr in glyphs.items() }, rows*2, 6)
    fine['hi'] = True; fine['label'] = 'FACETED FINE'
    for g in fine['glyphs'].values(): g['w'] = g['w'] + 1                      # (its own 2 px gap)
    # (owner, 2026-10-07, on round 53: "second font is the correct one": FACETED FINE is the game's font; the other
    # candidates (FACETED THIN, Jacquard 24, DotGothic16, Pixelify Sans, IM Fell SC) are gone again, ttf_font and
    # thin() kept for another audition)
    fonts = [('facet', facet), ('facet_fine', fine)]
    write(fonts)
    for n, f in fonts: print('%-11s h %2d  %3d glyphs' % (n, f['h'], len(f['glyphs'])))

if __name__ == '__main__':
    main()
