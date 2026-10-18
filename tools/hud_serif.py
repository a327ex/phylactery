#!/usr/bin/env python3
"""hud_serif.py -- Phylactery Serif (identity/font) baked for the game's HUD (Phylactery 20, 2026-10-18; his "The UI
should probably also use that font").

The HUD rasterizes each text on the CPU from glyph tables (port/hud.lua; port/hud_fonts.lua's format: per glyph an
advance `w`, its pixels `px` = {x, y, ...} from the line's top, and their coverage `pa`), then gives it the game's
treatment (the light fall, the ink ring, the drop). This bakes the serif into that format, anti-aliased, at the HUD's
full-resolution scale (a `hi` font: HUD.HI = 2 screen pixels per game pixel), with its kerning from HarfBuzz (pairs in
whole pixels) and mixed case kept (upper = false).

    python tools/hud_serif.py            -> port/hud_serif.lua
"""
import os
import uharfbuzz as hb
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
FONT = os.path.join(GAME, 'identity', 'font', 'PhylacterySerif-Regular.ttf')
OUT = os.path.join(GAME, 'port', 'hud_serif.lua')
CAP = 15                                   # cap height in hi pixels (FACETED FINE's capitals are 14)
CHARS = [chr(c) for c in range(33, 127)]


def main():
    tt = TTFont(FONT)
    upm = tt['head'].unitsPerEm
    cap_units = tt['OS/2'].sCapHeight or 670
    size = CAP * upm / cap_units                     # px per em
    k = size / upm
    asc = tt['hhea'].ascent
    desc = -tt['hhea'].descent
    cap_top = (asc - cap_units) * k                  # the capitals' top below the ascent line, px
    top = round(cap_top) - 1                         # the glyphs' y = 0: a pixel above the capitals' top
    line_h = round(asc * k + desc * k) - top         # cap top to the descenders' bottom
    font = ImageFont.truetype(FONT, round(size * 4))  # rendered 4x and reduced: smooth, unhinted coverage
    cmap = tt.getBestCmap()
    hmtx = tt['hmtx']
    glyphs = {}
    SS = 4
    for ch in CHARS:
        if ord(ch) not in cmap:
            continue
        adv = hmtx[cmap[ord(ch)]][0] * k
        W = int(adv * SS + 8 * SS) + 16
        H = int((asc + desc) * k * SS) + 8 * SS
        img = Image.new('L', (W, H), 0)
        d = ImageDraw.Draw(img)
        ox = 4 * SS
        d.text((ox, round(asc * k * SS)), ch, font=font, fill=255, anchor='ls')
        # reduce to hi pixels, the pen at x = 1 px (left bearings may reach left of 0)
        small = img.resize((W // SS, H // SS), Image.LANCZOS)
        px, pa = [], []
        sw, sh = small.size
        a = small.load()
        for y in range(sh):
            for x in range(sw):
                v = a[x, y]
                if v >= 10:
                    gx, gy = x - 4, y - top
                    px += [gx, gy]
                    pa.append(round(v / 255, 3))
        glyphs[ch] = (round(adv), px, pa)
    space = round(hmtx[cmap[32]][0] * k)
    # kerning: HarfBuzz's pair offsets, in whole pixels
    hbf = hb.Font(hb.Face(open(FONT, 'rb').read()))

    def pair_adv(s):
        buf = hb.Buffer(); buf.add_str(s); buf.guess_segment_properties()
        hb.shape(hbf, buf, {'kern': True, 'liga': False})
        return buf.glyph_positions[0].x_advance

    kern = {}
    letters = [c for c in CHARS if c.isalnum() or c in '.,\'"-:']
    plain = {c: hmtx[cmap[ord(c)]][0] for c in letters if ord(c) in cmap}
    for a1 in plain:
        for b1 in plain:
            dx = pair_adv(a1 + b1) - plain[a1]
            px_dx = round(dx * k)
            if px_dx:
                kern[a1 + b1] = px_dx

    def lua_str(s):
        return "'" + s.replace('\\', '\\\\').replace("'", "\\'") + "'"

    out = ['-- port/hud_serif.lua -- Phylactery Serif baked for the HUD by tools/hud_serif.py (do not edit by hand).',
           '-- A hi font (HUD.HI screen pixels per game pixel), mixed case, anti-aliased (pa), kerned (kern, whole pixels);',
           '-- h = the layout height (the capitals and a pixel either side), draw_h = with the descenders.',
           'return {',
           f"  h = {CAP + 2}, draw_h = {line_h}, cap = {CAP}, upper = false, space = {space}, hi = true, label = 'PHYLACTERY SERIF', kern = {{"]
    items = sorted(kern.items())
    for i in range(0, len(items), 12):
        out.append('    ' + ' '.join(f'[{lua_str(p)}] = {v},' for p, v in items[i:i + 12]))
    out.append('  }, glyphs = {')
    for ch, (w, px, pa) in glyphs.items():
        out.append(f"    [{lua_str(ch)}] = {{ w = {w}, px = {{ {','.join(map(str, px))} }}, pa = {{ {','.join(f'{v:g}' for v in pa)} }} }},")
    out.append('  },')
    out.append('}')
    open(OUT, 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
    print(OUT, f'size {size:.1f}px, line {line_h}, space {space}, {len(glyphs)} glyphs, {len(kern)} kern pairs')


if __name__ == '__main__':
    main()
