# make_page.py -- round 94d: the picked font as a real font file, its wordmark masters, and how they hold up at Steam's
# sizes and at text sizes (Phylactery 20, 2026-10-18). His pick: "75% IM Fell English and 25% EB Garamond it is".
# The font and the wordmark are copied into this folder (the page shows these copies). Run from lich-survivors/:
#   python tools/blend_font.py && python tools/wordmark.py && python rounds/94d-phylactery-serif/make_page.py
import base64, html, io, os, shutil
import uharfbuzz as hb
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
SRC_FONT = os.path.join(GAME, 'identity', 'font', 'PhylacterySerif-Regular.ttf')
TTF = os.path.join(GAME, 'reference', 'identity', 'fonts', 'ttf')
FELL = os.path.join(TTF, 'imfellenglish', 'IMFeENrm28P.ttf')
GARA = os.path.join(TTF, 'ebgaramond', 'EBGaramond[wght].ttf')
BG, INK, DIM = (13, 11, 10), (242, 227, 194), (138, 124, 102)

os.makedirs(os.path.join(HERE, 'files'), exist_ok=True)
FONT = shutil.copy(SRC_FONT, os.path.join(HERE, 'files', 'PhylacterySerif-Regular.ttf'))
shutil.copy(os.path.join(GAME, 'identity', 'font', 'OFL.txt'), os.path.join(HERE, 'files', 'OFL.txt'))
for n in ('phylactery-caps', 'phylactery-mixed'):
    for ext in ('svg', 'png'):
        shutil.copy(os.path.join(GAME, 'identity', 'wordmark', f'{n}.{ext}'), os.path.join(HERE, 'files', f'{n}.{ext}'))


class Face:
    def __init__(self, path, axes=None):
        self.path = path
        self.hb = hb.Font(hb.Face(open(path, 'rb').read()))
        if axes:
            self.hb.set_variations(axes)
        self.upm = self.hb.face.upem
        self.axes = axes
        self.cap = None
        ext = self.hb.get_glyph_extents(self.hb.get_nominal_glyph(ord('H')))
        self.cap = ext.y_bearing

    def pil(self, size):
        f = ImageFont.truetype(self.path, size)
        if self.axes:
            f.set_variation_by_axes([self.axes.get('wght', 400)])
        return f

    def draw(self, img, text, cap_px, x, y, col=INK, kern=True, anchor='l'):
        """kerned text (HarfBuzz positions; Pillow alone doesn't kern) with the cap height = cap_px, baseline y"""
        size = cap_px * self.upm / self.cap
        k = size / self.upm
        buf = hb.Buffer()
        buf.add_str(text)
        buf.guess_segment_properties()
        hb.shape(self.hb, buf, {'kern': kern, 'liga': False, 'clig': False, 'dlig': False})
        w = sum(p.x_advance for p in buf.glyph_positions) * k
        if anchor == 'm':
            x -= w / 2
        f = self.pil(round(size))
        d = ImageDraw.Draw(img)
        pen = 0
        for ch, pos in zip(text, buf.glyph_positions):
            d.text((x + (pen + pos.x_offset) * k, y), ch, font=f, fill=col, anchor='ls')
            pen += pos.x_advance
        return w


P = Face(FONT)
FE = Face(FELL)
GA = Face(GARA, {'wght': 500})
SMALL = ImageFont.truetype('segoeui.ttf', 15)


def note(img, text, y=None):
    ImageDraw.Draw(img).text((14, img.size[1] - 12 if y is None else y), text, font=SMALL, fill=DIM, anchor='ls')


def uri(img, fmt='PNG'):
    b = io.BytesIO()
    img.save(b, fmt, optimize=True)
    return f'data:image/{fmt.lower()};base64,' + base64.b64encode(b.getvalue()).decode()


def fig(img, cap):
    return f'<figure><img src="{uri(img)}" alt="{html.escape(cap)}"><figcaption>{html.escape(cap)}</figcaption></figure>'


def wordmark_plates():
    out = []
    for n in ('phylactery-caps', 'phylactery-mixed'):
        im = Image.open(os.path.join(HERE, 'files', f'{n}.png'))
        tile = Image.new('RGBA', im.size)
        d = ImageDraw.Draw(tile)
        for yy in range(0, im.size[1], 16):
            for xx in range(0, im.size[0], 16):
                d.rectangle([xx, yy, xx + 15, yy + 15], fill=(30, 26, 22, 255) if (xx // 16 + yy // 16) % 2 else (20, 17, 15, 255))
        tile.alpha_composite(im)
        out.append(fig(tile, f'files/{n}.png: 1280 wide, transparent (Steam\'s library logo is 1280 wide and/or 720 tall); files/{n}.svg is the vector master'))
    svg_uri = 'data:image/svg+xml;base64,' + base64.b64encode(open(os.path.join(HERE, 'files', 'phylactery-caps.svg'), 'rb').read()).decode()
    out.append(f'<figure><img src="{svg_uri}" alt="SVG master" style="background:#141110;padding:20px"><figcaption>files/phylactery-caps.svg rendered by the browser (the vector master)</figcaption></figure>')
    return ''.join(out)


def small_capsule_plates():
    """the small capsule (462x174) with the wordmark nearly filling it, and the two sizes Steam makes from it"""
    out = []
    for n in ('phylactery-caps', 'phylactery-mixed'):
        wm = Image.open(os.path.join(HERE, 'files', f'{n}.png'))
        cap = Image.new('RGBA', (462, 174), BG + (255,))
        k = min(430 / wm.size[0], 150 / wm.size[1])
        w = wm.resize((round(wm.size[0] * k), round(wm.size[1] * k)), Image.LANCZOS)
        cap.alpha_composite(w, ((462 - w.size[0]) // 2, (174 - w.size[1]) // 2))
        row = Image.new('RGB', (462 + 184 + 120 + 80, 200), BG)
        row.paste(cap.convert('RGB'), (0, 0))
        row.paste(cap.convert('RGB').resize((184, 69), Image.LANCZOS), (462 + 40, 0))
        row.paste(cap.convert('RGB').resize((120, 45), Image.LANCZOS), (462 + 40 + 184 + 40, 0))
        note(row, '462x174 (as uploaded)                                        184x69                      120x45 (made by Steam)', 192)
        out.append(fig(row, f'small capsule, wordmark alone on black: {n.split("-")[1]}'))
    return ''.join(out)


def type_plates():
    out = []
    im = Image.new('RGB', (1500, 600), BG)
    P.draw(im, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 44, 40, 80)
    P.draw(im, 'abcdefghijklmnopqrstuvwxyz', 44, 40, 170)
    P.draw(im, '0123456789  &?!.,;:\'"“”‘’()-–—·…', 44, 40, 260)
    P.draw(im, 'àáâãäçéèêëíìîïñóòôõöúùûü', 44, 40, 350)
    P.draw(im, 'ÀÁÂÃÇÉÈÊÍÓÔÕÚÑ', 44, 40, 450)
    note(im, 'the whole set: printable ASCII + typographic punctuation + the accented letters of Portuguese, Spanish and French; the figures are IM Fell\'s old-style figures')
    out.append(fig(im, 'character set'))
    im = Image.new('RGB', (1500, 560), BG)
    y = 70
    for cap_px in (44, 30, 20, 13, 9):
        txt = 'The quick brown fox jumps over the lazy dog.' if cap_px > 25 else \
              'The quick brown fox jumps over the lazy dog. Sphinx of black quartz, judge my vow.'
        P.draw(im, txt, cap_px, 40, y)
        ImageDraw.Draw(im).text((1460, y), f'cap {cap_px} px', font=SMALL, fill=DIM, anchor='rs')
        y += cap_px * 2.4 + 24
    note(im, 'running text (pangrams) from display size down to a 9 px cap height')
    out.append(fig(im, 'text sizes'))
    im = Image.new('RGB', (1500, 300), BG)
    P.draw(im, 'BURNED MASK   ·   THE HAND   ·   LODESTONE   ·   PSYONIAN ORBS   ·   PRISMATIC GEM   ·   ATTACK LENS', 14, 750, 70, anchor='m')
    P.draw(im, 'Burned Mask   ·   The Hand   ·   Lodestone   ·   Psyonian Orbs   ·   Prismatic Gem   ·   Attack Lens', 14, 750, 130, anchor='m')
    P.draw(im, 'BURNED MASK', 22, 750, 220, anchor='m')
    note(im, 'the game\'s own words (the six objects\' names) at the sizes the viewer uses on a 1280x720 window (a 14 px cap; a title at 22 px)')
    out.append(fig(im, 'the game\'s words at UI sizes'))
    im = Image.new('RGB', (1500, 300), BG)
    P.draw(im, 'AVATAR  To  Ty  LT  WAVE  Yo', 60, 40, 100, kern=False)
    P.draw(im, 'AVATAR  To  Ty  LT  WAVE  Yo', 60, 40, 220, kern=True)
    note(im, 'top: no kerning; bottom: the font\'s kerning (1,779 pairs, blended from both sources the same 75/25 way)')
    out.append(fig(im, 'kerning'))
    im = Image.new('RGB', (1500, 520), BG)
    for i, (face, label) in enumerate([(FE, 'IM Fell English (F06)'), (P, 'Phylactery Serif: 75% IM Fell English + 25% EB Garamond'), (GA, 'EB Garamond (F08, weight 500)')]):
        y = 130 + i * 160
        face.draw(im, 'PHYLACTERY  Phylactery', 80, 40, y)
        ImageDraw.Draw(im).text((40, y + 30), label, font=SMALL, fill=DIM, anchor='ls')
    out.append(fig(im, 'between its parents'))
    return ''.join(out)


def page():
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Phylactery Serif</title><style>
:root {{ color-scheme: dark; --bg:#0d0b0a; --ink:#efe3cc; --dim:#a8987c; --line:#2c241c; --accent:#e0b060; }}
html,body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,"Segoe UI",sans-serif; }}
header, section {{ max-width:1520px; margin:0 auto; padding:18px 16px 6px; }}
h1 {{ margin:10px 0 6px; font-size:24px; }} header p {{ margin:0 0 8px; color:var(--dim); max-width:1050px; }}
h2 {{ margin:24px 0 8px; font-size:20px; color:var(--accent); }}
figure {{ margin:0 0 14px; }} figure img {{ display:block; box-sizing:border-box; max-width:100%; height:auto; border:1px solid var(--line); border-radius:6px; }}
figcaption {{ color:var(--dim); font-size:13px; padding:4px 2px; }}
code {{ color:var(--ink); }}
</style></head><body>
<header><h1>Round 94d: Phylactery Serif, the picked font as a real font</h1>
<p>Your pick: "75% IM Fell English and 25% EB Garamond it is [...] that's the font." It is now a TrueType font,
<code>files/PhylacterySerif-Regular.ttf</code> (master copy in <code>lich-survivors/identity/font/</code>, built by
<code>tools/blend_font.py</code>): 141 characters (space included), every glyph blended outline to outline exactly as in the row you picked
(4, 6, 9 and ç through distance fields, their two versions being built differently), metrics and kerning blended the same way.
Licence: SIL OFL 1.1 like both parents, both copyrights kept (<code>files/OFL.txt</code>); free for the game, the store
and anything else. The wordmark masters (<code>tools/wordmark.py</code>) are set in it with the font's own kerning and default
spacing; tracking, colour and any hand-tuning of single letters belong to the logo round.</p></header>
<section><h2>The wordmark masters</h2>{wordmark_plates()}</section>
<section><h2>At Steam's smallest size</h2><p style="color:var(--dim)">The small capsule's rule: the logo "should nearly fill"
it, and it must read when Steam shrinks it to 184x69 and 120x45. Shown bare on black, before any art.</p>{small_capsule_plates()}</section>
<section><h2>As a typeface</h2>{type_plates()}</section>
</body></html>'''


if __name__ == '__main__':
    s = page()
    out = os.path.join(HERE, 'index.html')
    open(out, 'w', encoding='utf-8').write(s)
    print(out, f'{len(s)/1e6:.1f} MB')
