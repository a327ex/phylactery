#!/usr/bin/env python3
"""wordmark.py -- the PHYLACTERY wordmark set in the game's font (identity/font, tools/blend_font.py), kerned
(HarfBuzz), as vector SVG and transparent PNG masters (Phylactery 20, 2026-10-18).

    python tools/wordmark.py     -> identity/wordmark/phylactery-{caps,mixed}.svg + .png (1280 wide, Steam's library logo)

Default spacing and the font's own kerning; tracking, colour and any hand-tuning of letters are the logo's next round.
"""
import os
import uharfbuzz as hb
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
FONT = os.path.join(GAME, 'identity', 'font', 'PhylacterySerif-Regular.ttf')
OUT = os.path.join(GAME, 'identity', 'wordmark')
CREAM = (242, 227, 194)


def shape(text, path=FONT):
    font = hb.Font(hb.Face(open(path, 'rb').read()))
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(font, buf, {'kern': True, 'liga': False})
    x, out = 0, []
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        out.append((info.codepoint, x + pos.x_offset))
        x += pos.x_advance
    return out, x


def ink_box(tt, glyphs):
    gs, order = tt.getGlyphSet(), tt.getGlyphOrder()
    glyf = tt['glyf']
    xs, ys = [], []
    for gid, x in glyphs:
        g = glyf[order[gid]]
        if g.numberOfContours:
            xs += [x + g.xMin, x + g.xMax]
            ys += [g.yMin, g.yMax]
    return min(xs), min(ys), max(xs), max(ys)


def svg(text, name, colour='#f2e3c2'):
    tt = TTFont(FONT)
    gs, order = tt.getGlyphSet(), tt.getGlyphOrder()
    glyphs, _ = shape(text)
    x0, y0, x1, y1 = ink_box(tt, glyphs)
    pad = 20
    paths = []
    for gid, x in glyphs:
        pen = SVGPathPen(gs)
        gs[order[gid]].draw(TransformPen(pen, (1, 0, 0, -1, x - x0 + pad, y1 + pad)))
        d = pen.getCommands()
        if d:
            paths.append(d)
    w, h = x1 - x0 + 2 * pad, y1 - y0 + 2 * pad
    s = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">'
         f'<title>{text}</title><path fill="{colour}" d="{" ".join(paths)}"/></svg>\n')
    p = os.path.join(OUT, name + '.svg')
    open(p, 'w', encoding='utf-8').write(s)
    return p


def png(text, name, width=1280, colour=CREAM, ss=3):
    """transparent PNG, the ink box scaled to `width` (Steam's library logo: 1280 wide), drawn 3x and scaled down"""
    tt = TTFont(FONT)
    upm = tt['head'].unitsPerEm
    glyphs, _ = shape(text)
    x0, y0, x1, y1 = ink_box(tt, glyphs)
    pad = 0.02 * (x1 - x0)
    k = width * ss / (x1 - x0 + 2 * pad)          # px per font unit
    W, H = round((x1 - x0 + 2 * pad) * k), round((y1 - y0 + 2 * pad) * k)
    img = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT, round(upm * k))
    cmap = {v: c for c, v in tt.getBestCmap().items()}
    order = tt.getGlyphOrder()
    for gid, x in glyphs:
        ch = chr(cmap[order[gid]])
        d.text(((x - x0 + pad) * k, (y1 + pad) * k), ch, font=f, fill=255, anchor='ls')
    img = img.resize((width, round(H / ss)), Image.LANCZOS)
    out = Image.new('RGBA', img.size, colour + (0,))
    out.putalpha(img)
    p = os.path.join(OUT, name + '.png')
    out.save(p)
    return p


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for text, name in (('PHYLACTERY', 'phylactery-caps'), ('Phylactery', 'phylactery-mixed')):
        print(svg(text, name))
        print(png(text, name), Image.open(os.path.join(OUT, name + '.png')).size)
