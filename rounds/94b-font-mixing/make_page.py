# make_page.py -- round 94b: four ways to mix two fonts, shown with fonts from round 94's board (Phylactery 20, 2026-10-18).
# His question: "Is there a way we can do a mix of two fonts?" Techniques, not picks: the pairs are examples.
# Run from lich-survivors/:  python rounds/94b-font-mixing/make_page.py   (renders PNGs here, then index.html)
import base64, html, io, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageChops
from fontTools.ttLib import TTFont
from fontTools.pens.basePen import BasePen
import pathops

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
TTF = os.path.join(GAME, 'reference', 'identity', 'fonts', 'ttf')
BG, INK, DIM = (13, 11, 10), (242, 227, 194), (138, 124, 102)

FONTS = {  # name: (file, variation axes, board code)
    'EB Garamond': ('ebgaramond/EBGaramond[wght].ttf', {'wght': 500}, 'F08'),
    'UnifrakturMaguntia': ('unifrakturmaguntia/UnifrakturMaguntia-Book.ttf', {}, 'F13'),
    'Grenze Gotisch': ('grenzegotisch/GrenzeGotisch[wght].ttf', {'wght': 600}, 'F15'),
    'Cormorant SC': ('cormorantsc/CormorantSC-SemiBold.ttf', {}, 'F05'),
    'Tilt Prism': ('tiltprism/TiltPrism[XROT,YROT].ttf', {}, 'F26'),
    'Cinzel Decorative': ('cinzeldecorative/CinzelDecorative-Bold.ttf', {}, 'F02'),
    'IM Fell Double Pica': ('imfelldoublepica/IMFELLDoublePica-Regular.ttf', {}, 'F07'),
}


# ---------- PIL text with matched cap heights ----------
AXIS_TAGS = {'Weight': 'wght'}


def apply_axes(fnt, axes):
    if not axes:
        return fnt
    vals = []
    for a in fnt.get_variation_axes():
        n = a['name'].decode() if isinstance(a['name'], bytes) else a['name']
        vals.append(axes.get(AXIS_TAGS.get(n, n), a['default']))
    fnt.set_variation_by_axes(vals)
    return fnt


def pil_font(name, cap_px):
    f, axes, _ = FONTS[name]
    path = os.path.join(TTF, f)
    probe = apply_axes(ImageFont.truetype(path, 200), axes)
    cap = -probe.getbbox('H', anchor='ls')[1]
    return apply_axes(ImageFont.truetype(path, max(8, round(200 * cap_px / cap))), axes)


def runs_width(runs):
    return sum(f.getlength(t) for t, f, _ in runs)


def draw_runs(img, runs, y, x=None):
    """runs = [(text, font, colour)], drawn on one baseline, centred unless x given."""
    d = ImageDraw.Draw(img)
    w = runs_width(runs)
    x = (img.size[0] - w) / 2 if x is None else x
    for t, f, col in runs:
        d.text((x, y), t, font=f, fill=col, anchor='ls')
        x += f.getlength(t)


def label(img, text):
    d = ImageDraw.Draw(img)
    d.text((14, img.size[1] - 12), text, font=ImageFont.truetype('segoeui.ttf', 15), fill=DIM, anchor='ls')


# ---------- outlines for the true blend ----------
class FlatPen(BasePen):
    def __init__(self, glyphset):
        super().__init__(glyphset)
        self.contours, self.cur = [], []

    def _moveTo(self, p):
        self.cur = [p]

    def _lineTo(self, p):
        self.cur.append(p)

    def _curveToOne(self, p1, p2, p3):
        p0 = self.cur[-1]
        for i in range(1, 17):
            t = i / 16
            u = 1 - t
            self.cur.append((u**3*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t**3*p3[0],
                             u**3*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t**3*p3[1]))

    def _qCurveToOne(self, p1, p2):
        p0 = self.cur[-1]
        for i in range(1, 13):
            t = i / 12
            u = 1 - t
            self.cur.append((u*u*p0[0] + 2*u*t*p1[0] + t*t*p2[0], u*u*p0[1] + 2*u*t*p1[1] + t*t*p2[1]))

    def _closePath(self):
        if len(self.cur) > 2:
            self.contours.append(np.array(self.cur, dtype=float))
        self.cur = []

    _endPath = _closePath


class Outlines:
    def __init__(self, name):
        f, axes, _ = FONTS[name]
        self.tt = TTFont(os.path.join(TTF, f))
        self.gs = self.tt.getGlyphSet(location=axes or None)
        self.cmap = self.tt.getBestCmap()
        self.cap = None
        self.cap = self.bbox_h('H')

    def glyph(self, ch):
        """the letter's outline with its overlapping pieces merged (variable fonts draw a letter as overlapping
        strokes; unmerged, a blend pairs the wrong pieces)"""
        gn = self.cmap[ord(ch)]
        path = pathops.Path()
        self.gs[gn].draw(path.getPen(glyphSet=self.gs))
        path.simplify(fix_winding=True, keep_starting_points=False)
        pen = FlatPen(self.gs)
        path.draw(pen)
        return pen.contours, self.gs[gn].width

    def bbox_h(self, ch):
        cs, _ = self.glyph(ch)
        return max(c[:, 1].max() for c in cs)

    def letter(self, ch):
        """contours scaled so the cap height is 1, and the advance in the same units"""
        cs, adv = self.glyph(ch)
        return [c / self.cap for c in cs], adv / self.cap


def resample(c, n=240):
    seg = np.r_[np.linalg.norm(np.diff(c, axis=0), axis=1), np.linalg.norm(c[0] - c[-1])]
    pts = np.vstack([c, c[:1]])
    s = np.r_[0, np.cumsum(seg)]
    t = np.linspace(0, s[-1], n, endpoint=False)
    return np.c_[np.interp(t, s, pts[:, 0]), np.interp(t, s, pts[:, 1])]


def area(c):
    x, y = c[:, 0], c[:, 1]
    return 0.5 * (np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1)))


def split(cs, n):
    """(outer shapes, holes), each largest first; outer = the winding of the biggest contour"""
    rs = [resample(c, n) for c in cs]
    s = np.sign(area(max(rs, key=lambda c: abs(area(c)))))
    outer = sorted([c for c in rs if np.sign(area(c)) == s], key=lambda c: -abs(area(c)))
    holes = sorted([c for c in rs if np.sign(area(c)) != s], key=lambda c: -abs(area(c)))
    return outer, holes, s


def nearest_first(A, B):
    """reorder B so each of A's contours meets the closest remaining one of B (by centre)"""
    B = list(B)
    out = []
    for a in A:
        if not B:
            break
        j = min(range(len(B)), key=lambda k: np.sum((B[k].mean(axis=0) - a.mean(axis=0)) ** 2))
        out.append(B.pop(j))
    return out + B


def match(a_cs, b_cs, n=240):
    """pair outer shapes with outer shapes and holes with holes, nearest first; a missing partner is the
    other contour shrunk to its centre. Returns (a, b, winding sign) per pair."""
    ao, ah, sa = split(a_cs, n)
    bo, bh, sb = split(b_cs, n)
    if sa != sb:   # the two fonts wind the other way round: flip B
        bo, bh = [c[::-1].copy() for c in bo], [c[::-1].copy() for c in bh]
    pairs = []
    for A, B, sign in ((ao, nearest_first(ao, bo), 1), (ah, nearest_first(ah, bh), -1)):
        for i in range(max(len(A), len(B))):
            a = A[i] if i < len(A) else np.repeat(B[i].mean(axis=0, keepdims=True), n, axis=0)
            b = B[i] if i < len(B) else np.repeat(A[i].mean(axis=0, keepdims=True), n, axis=0)
            # the start point that lines the two contours up best
            best, bk = None, 0
            for k in range(0, n, 2):
                e = np.sum((a - np.roll(b, -k, axis=0)) ** 2)
                if best is None or e < best:
                    best, bk = e, k
            pairs.append((a, np.roll(b, -bk, axis=0), sign))
    return pairs


def nonzero_mask(polys, size):
    """fill by the nonzero winding rule (what fonts use): a pixel is ink when the contours wind round it
    any number of times but zero. Pillow fills crossings even-odd, which cuts slits where a blend crosses itself."""
    W, H = size
    E = np.vstack([np.c_[p, np.roll(p, -1, axis=0)] for p in polys])   # x0 y0 x1 y1
    E = E[E[:, 1] != E[:, 3]]
    acc = np.zeros((H, W + 1), dtype=np.int32)
    for y in range(H):
        yc = y + 0.5
        m = ((E[:, 1] <= yc) & (yc < E[:, 3])) | ((E[:, 3] <= yc) & (yc < E[:, 1]))
        if not m.any():
            continue
        e = E[m]
        xi = e[:, 0] + (yc - e[:, 1]) * (e[:, 2] - e[:, 0]) / (e[:, 3] - e[:, 1])
        d = np.where(e[:, 3] > e[:, 1], 1, -1)
        np.add.at(acc[y], np.clip(np.ceil(xi - 0.5).astype(int), 0, W), d)
    return np.cumsum(acc, axis=1)[:, :W] != 0


def blend_word(word, oa, ob, t, cap_px, out_size, S=3):
    # drawn at S times the size and scaled down: smooth edges, and no gaps where a font's strokes overlap
    size = (out_size[0] * S, out_size[1] * S)
    cap_px *= S
    img = Image.new('L', size, 0)
    letters = []
    total = 0.0
    for ch in word:
        a_cs, a_adv = oa.letter(ch)
        b_cs, b_adv = ob.letter(ch)
        adv = (1 - t) * a_adv + t * b_adv
        letters.append((match(a_cs, b_cs), a_adv, b_adv, adv))
        total += adv
    x = (size[0] / cap_px - total) / 2
    base = size[1] * 0.68
    polys = []
    for pairs, a_adv, b_adv, adv in letters:
        for a, b, sign in pairs:
            # each letter centred in its own advance, so the blend doesn't slide sideways
            ca = a + [(adv - a_adv) / 2, 0]
            cb = b + [(adv - b_adv) / 2, 0]
            p = (1 - t) * ca + t * cb
            polys.append(np.c_[(x + p[:, 0]) * cap_px, base - p[:, 1] * cap_px])
        x += adv
    img = Image.fromarray((nonzero_mask(polys, size) * 255).astype(np.uint8))
    img = img.resize(out_size, Image.LANCZOS)
    out = Image.new('RGB', out_size, BG)
    out.paste(Image.new('RGB', out_size, INK), mask=img)
    return out


# ---------- the plates ----------
W = 1500
plates = []  # (section, png path, caption)


def save(img, name):
    p = os.path.join(HERE, name)
    img.save(p)
    return p


def plate_pairing():
    out = []
    for top, low in [('EB Garamond', 'UnifrakturMaguntia'), ('UnifrakturMaguntia', 'EB Garamond'),
                     ('Cormorant SC', 'IM Fell Double Pica')]:
        img = Image.new('RGB', (W, 330), BG)
        draw_runs(img, [('PHYLACTERY', pil_font(top, 120), INK)], 175)
        draw_runs(img, [('Burned Mask  ·  The Hand  ·  Lodestone  ·  Psyonian Orbs  ·  Prismatic Gem  ·  Attack Lens', pil_font(low, 22), (214, 196, 160))], 260)
        label(img, f'{top} ({FONTS[top][2]}) for the name  +  {low} ({FONTS[low][2]}) for everything else (here, the six objects\' names)')
        out.append(save(img, f'1-pairing-{len(out)+1}.png'))
    return out


def plate_swap():
    out = []
    cap = 120
    G, U, P = pil_font('EB Garamond', cap), pil_font('UnifrakturMaguntia', cap), pil_font('Tilt Prism', cap)
    C, R = pil_font('Cormorant SC', cap), pil_font('Grenze Gotisch', cap)
    for runs, text in [
        ([('P', U, INK), ('HYLACTERY', G, INK)], 'the first letter from UnifrakturMaguntia (F13), like an illuminated initial; the rest EB Garamond (F08)'),
        ([('P', U, INK), ('HYL', G, INK), ('A', U, INK), ('CTERY', G, INK)], 'the initial and the A from UnifrakturMaguntia; the rest EB Garamond'),
        ([('PHYL', C, INK), ('A', P, INK), ('CTERY', C, INK)], 'Cormorant SC (F05) with one faceted A from Tilt Prism (F26): one letter carries the prism'),
        ([('P', R, INK), ('HYLACTERY', G, INK)], 'a quieter swap: Grenze Gotisch\'s (F15) P, half roman and half gothic, on EB Garamond (F08)'),
    ]:
        img = Image.new('RGB', (W, 260), BG)
        draw_runs(img, runs, 175)
        label(img, text)
        out.append(save(img, f'2-swap-{len(out)+1}.png'))
    return out


def letters_over(img, word, front, back, col_front, col_back, y, dx=0, dy=0, back_on_top=False):
    """the back face's letters each centred on the front face's letters (the two faces' widths differ)"""
    d = ImageDraw.Draw(img)
    x = (img.size[0] - front.getlength(word)) / 2
    spots = []
    for ch in word:
        w = front.getlength(ch)
        spots.append((ch, x, x + w / 2))
        x += w

    def draw_back():
        for ch, _, cx in spots:
            d.text((cx + dx, y + dy), ch, font=back, fill=col_back, anchor='ms')

    def draw_front():
        for ch, x0, _ in spots:
            d.text((x0, y), ch, font=front, fill=col_front, anchor='ls')
    if back_on_top:
        draw_front()
        draw_back()
    else:
        draw_back()
        draw_front()


def plate_layer():
    out = []
    cap = 130
    for front, back, dx, dy, col, on_top, text in [
        ('Cormorant SC', 'Tilt Prism', 8, 7, (224, 150, 90), False, 'Cormorant SC (F05) over Tilt Prism (F26) shifted down-right in ember: the second face as a cast shadow'),
        ('EB Garamond', 'UnifrakturMaguntia', 0, 0, (110, 78, 44), False, 'EB Garamond (F08) over UnifrakturMaguntia (F13), dimmed, letter on letter: one face as a ghost behind the other'),
        ('Cormorant SC', 'Tilt Prism', 0, 0, (224, 150, 90), True, 'Tilt Prism (F26) laid over Cormorant SC (F05), letter on letter: the facets as an inner light'),
    ]:
        img = Image.new('RGB', (W, 270), BG)
        letters_over(img, 'PHYLACTERY', pil_font(front, cap), pil_font(back, cap), INK, col, 185, dx, dy, on_top)
        label(img, text)
        out.append(save(img, f'3-layer-{len(out)+1}.png'))
    return out


def plate_blend():
    out = []
    for a, b in [('EB Garamond', 'UnifrakturMaguntia'), ('EB Garamond', 'Grenze Gotisch'), ('Cormorant SC', 'Cinzel Decorative')]:
        oa, ob = Outlines(a), Outlines(b)
        rows = []
        for t in (0.0, 0.15, 0.3, 0.5, 1.0):
            im = blend_word('PHYLACTERY', oa, ob, t, 74, (W, 150))
            ImageDraw.Draw(im).text((14, 140), f'{round(t*100)}% {b}', font=ImageFont.truetype('segoeui.ttf', 14), fill=DIM, anchor='ls')
            rows.append(im)
        img = Image.new('RGB', (W, 150 * 5 + 34), BG)
        for i, r in enumerate(rows):
            img.paste(r, (0, i * 150))
        label(img, f'{a} ({FONTS[a][2]}) blended into {b} ({FONTS[b][2]}): every outline moved part of the way from one to the other')
        out.append(save(img, f'4-blend-{len(out)+1}.png'))
    return out


def uri(p):
    b = io.BytesIO()
    Image.open(p).save(b, 'PNG', optimize=True)
    return 'data:image/png;base64,' + base64.b64encode(b.getvalue()).decode()


SECTIONS = [
    ('Two fonts, two jobs', 'The most common mix: one face for the name, another for everything around it (the store text, the game\'s UI, the object names). Each stays whole; the pair is the identity.', plate_pairing),
    ('One word, two faces', 'Most letters from one face and a few from another, baseline and cap height matched. The medieval version is the illuminated initial; the logo version is one letter that carries the idea.', plate_swap),
    ('Layered', 'Both faces whole, stacked: one as a shadow, a ghost or an inner light behind or inside the other. Colour separates them.', plate_layer),
    ('A true blend', "Every letter's outline moved part of the way from one face to the other, so the result is a new face between them (done here by merging each letter's strokes, sampling both outlines and interpolating). Faces built alike blend cleanly at every step: Cormorant SC into Cinzel Decorative. Faces built differently hold together only at small amounts: around 15-30% a Garamond takes on a gothic tension, and by 50% the shapes stop agreeing (the P's bowl, the blackletter's extra strokes have no partner). A blended wordmark is usually redrawn by hand from the step that works. Grenze Gotisch is this idea made properly by its designers: a face on the border between roman and blackletter.", plate_blend),
]


def page():
    secs = []
    for i, (head, lead, fn) in enumerate(SECTIONS, 1):
        imgs = ''.join(f'<img src="{uri(p)}" alt="{html.escape(head)}">' for p in fn())
        secs.append(f'<section><h2>{i}. {html.escape(head)}</h2><p class="lead">{html.escape(lead)}</p>{imgs}</section>')
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mixing Two Fonts</title><style>
:root {{ color-scheme: dark; --bg:#0d0b0a; --ink:#efe3cc; --dim:#a8987c; --line:#2c241c; --accent:#e0b060; }}
html,body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,"Segoe UI",sans-serif; }}
header, section {{ max-width:1520px; margin:0 auto; padding:18px 16px 6px; }}
h1 {{ margin:10px 0 6px; font-size:24px; }} header p {{ margin:0 0 6px; color:var(--dim); max-width:1000px; }}
h2 {{ margin:22px 0 4px; font-size:20px; color:var(--accent); }} .lead {{ margin:0 0 10px; color:var(--dim); max-width:1000px; }}
section img {{ display:block; width:100%; height:auto; border:1px solid var(--line); border-radius:6px; margin:0 0 10px; }}
</style></head><body>
<header><h1>Round 94b: four ways to mix two fonts</h1>
<p>Your question: "Is there a way we can do a mix of two fonts?" Yes, four ways, each shown with fonts from round 94's board
(codes as there). The pairs are examples of each technique, not picks: any two of the board's fonts can go through any of them.</p></header>
{''.join(secs)}
</body></html>'''


if __name__ == '__main__':
    s = page()
    out = os.path.join(HERE, 'index.html')
    open(out, 'w', encoding='utf-8').write(s)
    print(out, f'{len(s)/1e6:.1f} MB')
