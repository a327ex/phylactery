# make_page.py -- round 94c: true blends of IM Fell with EB Garamond and with Cardo (Phylactery 20, 2026-10-18).
# His ask: "Let me see true blends of IM FELL + EB GARAMOND and IM FELL + CARDO." The board has two IM Fells (English F06,
# Double Pica F07), so both go in. The blend itself is round 94b's (its make_page.py, delivered and unchanging, imported).
# Run from lich-survivors/:  python rounds/94c-fell-blends/make_page.py
import base64, html, importlib.util, io, os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('mix94b', os.path.join(os.path.dirname(HERE), '94b-font-mixing', 'make_page.py'))
M = importlib.util.module_from_spec(spec)
spec.loader.exec_module(M)

M.FONTS['IM Fell English'] = ('imfellenglish/IMFeENrm28P.ttf', {}, 'F06')
M.FONTS['Cardo'] = ('cardo/Cardo-Regular.ttf', {}, 'F12')
# EB Garamond stays at weight 500 as on the board (F08)

import numpy as np
from scipy.ndimage import distance_transform_edt as edt

W = 1500
STEPS = (0.0, 0.25, 0.5, 0.75, 1.0)


def structure(cs):
    o, h, _ = M.split(cs, 32)
    return len(o), len(h)


def blend_word(word, oa, ob, t, cap_px, out_size, S=3):
    """94b's outline blend, except for a letter whose two versions are built differently (here the P: IM Fell English's
    and EB Garamond's bowls are open, Cardo's and IM Fell Double Pica's closed). There no outline correspondence is right,
    so that letter blends through signed distance fields: the gap closes smoothly into a hole."""
    size = (out_size[0] * S, out_size[1] * S)
    cap = cap_px * S
    letters, total = [], 0.0
    for ch in word:
        a_cs, a_adv = oa.letter(ch)
        b_cs, b_adv = ob.letter(ch)
        adv = (1 - t) * a_adv + t * b_adv
        letters.append((a_cs, b_cs, a_adv, b_adv, adv))
        total += adv
    x = (size[0] / cap - total) / 2
    base = size[1] * 0.68
    polys, mask = [], np.zeros((size[1], size[0]), dtype=bool)

    def place(cs, own_adv, adv, x):
        return [np.c_[(x + c[:, 0] + (adv - own_adv) / 2) * cap, base - c[:, 1] * cap] for c in cs]

    for a_cs, b_cs, a_adv, b_adv, adv in letters:
        if structure(a_cs) == structure(b_cs):
            for a, b, _ in M.match(a_cs, b_cs):
                p = (1 - t) * (a + [(adv - a_adv) / 2, 0]) + t * (b + [(adv - b_adv) / 2, 0])
                polys.append(np.c_[(x + p[:, 0]) * cap, base - p[:, 1] * cap])
        else:
            pa, pb = place(a_cs, a_adv, adv, x), place(b_cs, b_adv, adv, x)
            allp = np.vstack(pa + pb)
            x0, y0 = max(0, int(allp[:, 0].min()) - 8), max(0, int(allp[:, 1].min()) - 8)
            x1, y1 = min(size[0], int(allp[:, 0].max()) + 9), min(size[1], int(allp[:, 1].max()) + 9)
            box = (x1 - x0, y1 - y0)
            ma = M.nonzero_mask([q - [x0, y0] for q in pa], box)
            mb = M.nonzero_mask([q - [x0, y0] for q in pb], box)
            sa, sb = edt(~ma) - edt(ma), edt(~mb) - edt(mb)   # outside > 0, inside < 0
            mask[y0:y1, x0:x1] |= ((1 - t) * sa + t * sb) < 0
        x += adv
    if polys:
        mask |= M.nonzero_mask(polys, size)
    img = Image.fromarray((mask * 255).astype(np.uint8)).resize(out_size, Image.LANCZOS)
    out = Image.new('RGB', out_size, M.BG)
    out.paste(Image.new('RGB', out_size, M.INK), mask=img)
    return out
PAIRS = [('IM Fell English', 'EB Garamond'), ('IM Fell Double Pica', 'EB Garamond'),
         ('IM Fell English', 'Cardo'), ('IM Fell Double Pica', 'Cardo')]


def plate(a, b, word, cap_px, row_h):
    oa, ob = M.Outlines(a), M.Outlines(b)
    img = Image.new('RGB', (W, row_h * len(STEPS)), M.BG)
    small = ImageFont.truetype('segoeui.ttf', 14)
    for i, t in enumerate(STEPS):
        row = blend_word(word, oa, ob, t, cap_px, (W, row_h))
        who = a if t == 0 else b if t == 1 else f'{round((1-t)*100)}% {a}  +  {round(t*100)}% {b}'
        ImageDraw.Draw(row).text((14, 22), who, font=small, fill=M.DIM, anchor="ls")
        img.paste(row, (0, i * row_h))
    return img


def uri(img):
    b = io.BytesIO()
    img.save(b, 'PNG', optimize=True)
    return 'data:image/png;base64,' + base64.b64encode(b.getvalue()).decode()


def page():
    secs = []
    for a, b in PAIRS:
        ca, cb = M.FONTS[a][2], M.FONTS[b][2]
        slug = f'{a}-{b}'.lower().replace(' ', '-')
        caps = plate(a, b, 'PHYLACTERY', 92, 170)
        mixed = plate(a, b, 'Phylactery', 92, 190)
        caps.save(os.path.join(HERE, f'{slug}-caps.png'))
        mixed.save(os.path.join(HERE, f'{slug}-mixed.png'))
        secs.append(f'<section><h2>{html.escape(a)} ({ca}) &harr; {html.escape(b)} ({cb})</h2>'
                    f'<img src="{uri(caps)}" alt="{html.escape(a)} to {html.escape(b)}, capitals">'
                    f'<img src="{uri(mixed)}" alt="{html.escape(a)} to {html.escape(b)}, mixed case"></section>')
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>IM Fell Blends</title><style>
:root {{ color-scheme: dark; --bg:#0d0b0a; --ink:#efe3cc; --dim:#a8987c; --line:#2c241c; --accent:#e0b060; }}
html,body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,"Segoe UI",sans-serif; }}
header, section {{ max-width:1520px; margin:0 auto; padding:18px 16px 6px; }}
h1 {{ margin:10px 0 6px; font-size:24px; }} header p {{ margin:0 0 6px; color:var(--dim); max-width:1000px; }}
h2 {{ margin:22px 0 8px; font-size:20px; color:var(--accent); }}
section img {{ display:block; width:100%; height:auto; border:1px solid var(--line); border-radius:6px; margin:0 0 10px; }}
</style></head><body>
<header><h1>Round 94c: IM Fell blended with EB Garamond and with Cardo</h1>
<p>Your ask: true blends of IM Fell + EB Garamond and IM Fell + Cardo. The board has two IM Fells, English (F06) and Double
Pica (F07), so each is blended with both. Each pair in capitals and in mixed case, in quarter steps from pure IM Fell (top) to
the other face (bottom), cap heights matched. The method is round 94b's: each letter's outline moved part of the way from one
face to the other. These four faces are built alike (old-style book romans), so every step holds together; the one letter
built differently is the P (IM Fell English's and EB Garamond's bowls are open, Cardo's and Double Pica's closed), which blends
through distance fields instead, so its bowl closes smoothly.</p></header>
{''.join(secs)}
</body></html>'''


if __name__ == '__main__':
    s = page()
    out = os.path.join(HERE, 'index.html')
    open(out, 'w', encoding='utf-8').write(s)
    print(out, f'{len(s)/1e6:.1f} MB')
