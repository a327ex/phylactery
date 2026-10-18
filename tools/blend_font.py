#!/usr/bin/env python3
"""blend_font.py -- build a real font file that sits between two fonts (Phylactery 20, 2026-10-18).

His pick (round 94c): "75% IM Fell English and 25% EB Garamond it is [...] that's the font." This writes that blend as a
TrueType font: every glyph both faces have (printable ASCII + a few typographic and accented letters), metrics and
kerning blended the same way.

    python tools/blend_font.py            -> identity/font/PhylacterySerif-Regular.ttf (+ OFL.txt)

How a glyph is blended (round 94b/94c's method, made exact enough for a font):
- each face's outline with its overlapping pieces merged (skia-pathops), cap heights matched;
- outer shapes paired with outer shapes and holes with holes, nearest first; every contour resampled densely by arc
  length, the start point that lines a pair up best found, points interpolated; written as an all-off-curve TrueType
  contour (a smooth quadratic spline through the dense points);
- a glyph whose two versions are built differently (here 4, 6, 9, ç: a closed counter against an open one, a cedilla
  drawn apart) blends through signed distance fields at high resolution, then is traced back to outlines.
Advance widths, vertical metrics and kerning (each face's pairs read by shaping with HarfBuzz) are interpolated too.
Both sources are SIL OFL 1.1 with no Reserved Font Names; the blend is OFL as well, both copyrights kept.
"""
import os
import numpy as np
import pathops
import uharfbuzz as hb
from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables._k_e_r_n import KernTable_format_0
from fontTools.pens.basePen import BasePen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.fontBuilder import FontBuilder
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt as edt
from skimage.measure import find_contours

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
TTF = os.path.join(GAME, 'reference', 'identity', 'fonts', 'ttf')
OUT = os.path.join(GAME, 'identity', 'font')

A_FILE, A_AXES = os.path.join(TTF, 'imfellenglish', 'IMFeENrm28P.ttf'), {}
B_FILE, B_AXES = os.path.join(TTF, 'ebgaramond', 'EBGaramond[wght].ttf'), {'wght': 500}
T = 0.25                      # 0 = IM Fell English, 1 = EB Garamond
UPM = 1000
FAMILY, STYLE = 'Phylactery Serif', 'Regular'
CHARS = [chr(c) for c in range(0x20, 0x7f)] + list('‘’“”–—·…éèêëàáâãäçíìîïóòôõöúùûüñÉÈÊÀÁÂÃÇÍÓÔÕÚÑ')
SPACING = 5.0                 # resampling step in font units (UPM 1000): ~1 px at a 200 px cap height


# ---------- reading a face ----------
class FlatPen(BasePen):
    def __init__(self, gs):
        super().__init__(gs)
        self.contours, self.cur = [], []

    def _moveTo(self, p):
        self.cur = [p]

    def _lineTo(self, p):
        self.cur.append(p)

    def _curveToOne(self, p1, p2, p3):
        p0 = self.cur[-1]
        for i in range(1, 25):
            t = i / 24
            u = 1 - t
            self.cur.append((u**3*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t**3*p3[0],
                             u**3*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t**3*p3[1]))

    def _qCurveToOne(self, p1, p2):
        p0 = self.cur[-1]
        for i in range(1, 17):
            t = i / 16
            u = 1 - t
            self.cur.append((u*u*p0[0] + 2*u*t*p1[0] + t*t*p2[0], u*u*p0[1] + 2*u*t*p1[1] + t*t*p2[1]))

    def _closePath(self):
        if len(self.cur) > 2:
            self.contours.append(np.array(self.cur, dtype=float))
        self.cur = []

    _endPath = _closePath


class Face:
    def __init__(self, path, axes):
        self.path, self.axes = path, axes
        self.tt = TTFont(path)
        self.upm = self.tt['head'].unitsPerEm
        self.gs = self.tt.getGlyphSet(location=axes or None)
        self.cmap = self.tt.getBestCmap()
        self.cap = max(c[:, 1].max() for c in self.raw('H')[0])
        hb_face = hb.Face(open(path, 'rb').read())
        self.hb = hb.Font(hb_face)
        if axes:
            self.hb.set_variations(axes)

    def raw(self, ch):
        gn = self.cmap[ord(ch)]
        p = pathops.Path()
        self.gs[gn].draw(p.getPen(glyphSet=self.gs))
        p.simplify(fix_winding=True, keep_starting_points=False)
        pen = FlatPen(self.gs)
        p.draw(pen)
        return pen.contours, self.gs[gn].width

    def letter(self, ch):
        """contours and advance in cap-height units (cap = 1)"""
        cs, adv = self.raw(ch)
        return [c / self.cap for c in cs], adv / self.cap

    def kern(self, a, b):
        """the pair adjustment between a and b, in cap-height units (0 when the face has none)"""
        buf = hb.Buffer()
        buf.add_str(a + b)
        buf.guess_segment_properties()
        hb.shape(self.hb, buf, {'kern': True, 'liga': False, 'clig': False, 'dlig': False, 'calt': False})
        if len(buf.glyph_infos) != 2:
            return 0.0
        g = buf.glyph_infos[0].codepoint
        return (buf.glyph_positions[0].x_advance - self.hb.get_glyph_h_advance(g)) / self.cap


# ---------- the outline blend ----------
def resample(c, n):
    seg = np.r_[np.linalg.norm(np.diff(c, axis=0), axis=1), np.linalg.norm(c[0] - c[-1])]
    pts = np.vstack([c, c[:1]])
    s = np.r_[0, np.cumsum(seg)]
    t = np.linspace(0, s[-1], n, endpoint=False)
    return np.c_[np.interp(t, s, pts[:, 0]), np.interp(t, s, pts[:, 1])]


def perimeter(c):
    return float(np.sum(np.linalg.norm(np.diff(np.vstack([c, c[:1]]), axis=0), axis=1)))


def area(c):
    x, y = c[:, 0], c[:, 1]
    return 0.5 * (np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1)))


def split(cs):
    s = np.sign(area(max(cs, key=lambda c: abs(area(c)))))
    outer = sorted([c for c in cs if np.sign(area(c)) == s], key=lambda c: -abs(area(c)))
    holes = sorted([c for c in cs if np.sign(area(c)) != s], key=lambda c: -abs(area(c)))
    return outer, holes


def nearest_first(A, B):
    B, out = list(B), []
    for a in A:
        if not B:
            break
        j = min(range(len(B)), key=lambda k: np.sum((B[k].mean(axis=0) - a.mean(axis=0)) ** 2))
        out.append(B.pop(j))
    return out + B


def pair_up(a, b, unit):
    """two contours resampled to the same count, b's start point and direction lined up with a's"""
    n = max(48, int(max(perimeter(a), perimeter(b)) * unit / SPACING))
    a, b = resample(a, n), resample(b, n)
    if np.sign(area(a)) != np.sign(area(b)):
        b = b[::-1].copy()
    best, bk = None, 0
    step = max(1, n // 400)
    for k in range(0, n, step):
        e = np.sum((a - np.roll(b, -k, axis=0)) ** 2)
        if best is None or e < best:
            best, bk = e, k
    for k in range(max(0, bk - step), min(n, bk + step + 1)):
        e = np.sum((a - np.roll(b, -k, axis=0)) ** 2)
        if e < best:
            best, bk = e, k
    return a, np.roll(b, -bk, axis=0)


def outline_blend(a_cs, b_cs, a_off, b_off, t, unit):
    ao, ah = split(a_cs)
    bo, bh = split(b_cs)
    out = []
    for A, B in ((ao, nearest_first(ao, bo)), (ah, nearest_first(ah, bh))):
        for a, b in zip(A, B):
            a, b = pair_up(a + [a_off, 0], b + [b_off, 0], unit)
            out.append((1 - t) * a + t * b)
    return out


# ---------- the distance-field blend (glyphs built differently) ----------
def mask_of(cs, off, scale, box):
    """nonzero fill of contours (cap units, shifted by off) on a pixel grid; box = (x0, y0, w, h) in cap units"""
    x0, y0, w, h = box
    W, H = int(w * scale), int(h * scale)
    acc = np.zeros((H, W + 1), dtype=np.int32)
    E = np.vstack([np.c_[(c[:, 0] + off - x0) * scale, (y0 + h - c[:, 1]) * scale,
                         (np.roll(c[:, 0], -1) + off - x0) * scale, (y0 + h - np.roll(c[:, 1], -1)) * scale] for c in cs])
    E = E[E[:, 1] != E[:, 3]]
    for y in range(H):
        yc = y + 0.5
        m = ((E[:, 1] <= yc) & (yc < E[:, 3])) | ((E[:, 3] <= yc) & (yc < E[:, 1]))
        if m.any():
            e = E[m]
            xi = e[:, 0] + (yc - e[:, 1]) * (e[:, 2] - e[:, 0]) / (e[:, 3] - e[:, 1])
            np.add.at(acc[y], np.clip(np.ceil(xi - 0.5).astype(int), 0, W), np.where(e[:, 3] > e[:, 1], 1, -1))
    return np.cumsum(acc, axis=1)[:, :W] != 0


def field_blend(a_cs, b_cs, a_off, b_off, t, unit, scale=1400):
    allp = np.vstack([c + [a_off, 0] for c in a_cs] + [c + [b_off, 0] for c in b_cs])
    x0, y0 = allp[:, 0].min() - 0.05, allp[:, 1].min() - 0.05
    box = (x0, y0, allp[:, 0].max() + 0.05 - x0, allp[:, 1].max() + 0.05 - y0)
    ma, mb = mask_of(a_cs, a_off, scale, box), mask_of(b_cs, b_off, scale, box)
    f = (1 - t) * (edt(~ma) - edt(ma)) + t * (edt(~mb) - edt(mb))
    H = f.shape[0]
    out = []
    for c in find_contours(f, 0.0):
        if len(c) < 8:
            continue
        # (row, col) pixels back to cap units, y up
        p = np.c_[x0 + (c[:, 1] + 0.5) / scale, y0 + (H - (c[:, 0] + 0.5)) / scale]
        out.append(resample(p, max(48, int(perimeter(p) * unit / SPACING))))
    return out


# ---------- writing ----------
def orient(cs):
    """TrueType: outer contours clockwise, holes counter-clockwise (by nesting depth)"""
    out = []
    for i, c in enumerate(cs):
        p = c[0]
        depth = 0
        for j, d in enumerate(cs):
            if i == j:
                continue
            # even-odd point-in-polygon of c's first point in d
            x, y = d[:, 0], d[:, 1]
            x2, y2 = np.roll(x, -1), np.roll(y, -1)
            cross = ((y > p[1]) != (y2 > p[1])) & (p[0] < (x2 - x) * (p[1] - y) / np.where(y2 == y, 1e-12, y2 - y) + x)
            depth += int(np.count_nonzero(cross) % 2)
        want_cw = depth % 2 == 0
        is_cw = area(c) < 0
        out.append(c if is_cw == want_cw else c[::-1].copy())
    return out


def glyph_from(cs, unit):
    pen = TTGlyphPen(None)
    for c in orient(cs):
        pts = [(int(round(x * unit)), int(round(y * unit))) for x, y in c]
        # drop repeats (rounding), then one closed all-off-curve contour: a smooth quadratic spline through the points
        clean = [pts[0]]
        for q in pts[1:]:
            if q != clean[-1]:
                clean.append(q)
        if len(clean) > 1 and clean[-1] == clean[0]:
            clean.pop()
        if len(clean) < 3:
            continue
        pen.qCurveTo(*clean, None)
        pen.closePath()
    return pen.glyph()


def gname(ch):
    if ch == ' ':
        return 'space'
    return f'uni{ord(ch):04X}'


def build():
    A, B = Face(A_FILE, A_AXES), Face(B_FILE, B_AXES)
    cap_units = round(((1 - T) * A.cap / A.upm + T * B.cap / B.upm) * UPM)   # cap height in the new font's units
    unit = cap_units                                                        # cap-height units -> font units
    order, cmap, glyphs, metrics, differ = ['.notdef'], {}, {}, {}, []
    pen = TTGlyphPen(None)
    glyphs['.notdef'] = pen.glyph()
    metrics['.notdef'] = (round(0.5 * UPM), 0)
    for ch in CHARS:
        if ord(ch) not in A.cmap or ord(ch) not in B.cmap:
            print('skip (not in both):', repr(ch))
            continue
        a_cs, a_adv = A.letter(ch)
        b_cs, b_adv = B.letter(ch)
        adv = (1 - T) * a_adv + T * b_adv
        a_off, b_off = (adv - a_adv) / 2, (adv - b_adv) / 2
        if not a_cs or not b_cs:
            cs = []
        else:
            sa, sb = split(a_cs), split(b_cs)
            if (len(sa[0]), len(sa[1])) == (len(sb[0]), len(sb[1])):
                cs = outline_blend(a_cs, b_cs, a_off, b_off, T, unit)
            else:
                differ.append(ch)
                cs = field_blend(a_cs, b_cs, a_off, b_off, T, unit)
        n = gname(ch)
        order.append(n)
        cmap[ord(ch)] = n
        g = glyph_from(cs, unit) if cs else TTGlyphPen(None).glyph()
        glyphs[n] = g
        lsb = int(min((round(x * unit) for c in cs for x in c[:, 0]), default=0))
        metrics[n] = (int(round(adv * unit)), lsb)
    print('distance-field glyphs:', ''.join(differ))

    # vertical metrics, x-height, kerning: all interpolated in cap-height units
    def mix(fa, fb):
        return (1 - T) * fa + T * fb
    asc = round(mix(A.tt['hhea'].ascent / A.cap, B.tt['hhea'].ascent / B.cap) * unit)
    desc = round(mix(A.tt['hhea'].descent / A.cap, B.tt['hhea'].descent / B.cap) * unit)
    xh = round(mix(max(c[:, 1].max() for c in A.raw('x')[0]) / A.cap, max(c[:, 1].max() for c in B.raw('x')[0]) / B.cap) * unit)

    pairs = []
    kchars = [c for c in CHARS if c != ' ' and ord(c) in cmap]
    for a in kchars:
        for b in kchars:
            k = round(mix(A.kern(a, b), B.kern(a, b)) * unit)
            if abs(k) >= 6:
                pairs.append((gname(a), gname(b), k))
    print('kerning pairs:', len(pairs))

    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=asc, descent=desc)
    fb.setupNameTable({
        'familyName': FAMILY, 'styleName': STYLE,
        'uniqueFontIdentifier': f'{FAMILY.replace(" ", "")}-{STYLE};2026',
        'fullName': f'{FAMILY} {STYLE}', 'psName': f'{FAMILY.replace(" ", "")}-{STYLE}',
        'version': 'Version 1.000',
        'copyright': 'Copyright (c) 2010, Igino Marini (mail@iginomarini.com); Copyright 2017 The EB Garamond Project '
                     'Authors (https://github.com/octaviopardo/EBGaramond12); blend 2026, a327ex',
        'licenseDescription': 'This Font Software is licensed under the SIL Open Font License, Version 1.1.',
        'licenseInfoURL': 'https://openfontlicense.org',
        'description': f'{round((1 - T) * 100)}% IM Fell English + {round(T * 100)}% EB Garamond (wght 500), outline blend',
    })
    fb.setupOS2(sTypoAscender=asc, sTypoDescender=desc, sTypoLineGap=0, usWinAscent=asc, usWinDescent=-desc,
                sxHeight=xh, sCapHeight=cap_units, achVendID='A327', fsType=0)
    fb.setupPost()
    if pairs:
        # GPOS for shapers (browsers, HarfBuzz) and the old 'kern' table for simple renderers (FreeType's basic
        # layout, stb_truetype): the same pairs in both
        fea = 'languagesystem DFLT dflt;\nlanguagesystem latn dflt;\nfeature kern {\n' + \
              ''.join(f'  pos {a} {b} {k};\n' for a, b, k in pairs) + '} kern;\n'
        addOpenTypeFeaturesFromString(fb.font, fea)
        kt = newTable('kern')
        kt.version = 0
        sub = KernTable_format_0()
        sub.version, sub.coverage, sub.format = 0, 1, 0
        sub.kernTable = {(a, b): k for a, b, k in pairs}
        kt.kernTables = [sub]
        fb.font['kern'] = kt
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f'{FAMILY.replace(" ", "")}-{STYLE}.ttf')
    fb.save(path)
    lic = open(os.path.join(TTF, 'imfellenglish', 'OFL.txt'), encoding='utf-8').read()
    body = lic[lic.index('This Font Software is licensed'):]
    open(os.path.join(OUT, 'OFL.txt'), 'w', encoding='utf-8').write(
        'Copyright (c) 2010, Igino Marini (mail@iginomarini.com)\n'
        'Copyright 2017 The EB Garamond Project Authors (https://github.com/octaviopardo/EBGaramond12)\n'
        f'{FAMILY}: a blend of the two (75% IM Fell English, 25% EB Garamond), 2026, a327ex.\n\n' + body)
    print(path, os.path.getsize(path) // 1024, 'KB', f'cap {cap_units} x {xh} asc {asc} desc {desc}')
    return path


if __name__ == '__main__':
    build()
