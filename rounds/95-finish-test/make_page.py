# make_page.py -- round 95: one composition (his A02: the arched lich, the mask leaving his face, a flat field), finished
# three ways, cut to the main capsule (1232x706) and the vertical capsule (748x896). Phylactery 20, 2026-10-18.
# Sources (copied into files/ so the page keeps showing what he saw): scratch/s20/r95/ (stage.lua: the staging and the
# GPU read-back; finish/: the image-model jobs and their outputs). Run from lich-survivors/:
#   python rounds/95-finish-test/make_page.py
import base64, html, io, os, shutil
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(GAME, 'scratch', 's20', 'r95')
FILES = os.path.join(HERE, 'files')
os.makedirs(FILES, exist_ok=True)

MAIN, VERT = (1232, 706), (748, 896)

# (code, family, label, source image, how it was made, figure centre as a fraction of the width)
FINISHES = [
    ('R1', 'the game\'s own render', 'The game itself, at its own 640x360, pixels scaled up', 'native/d_y300.png',
     'the staging rendered by the game at its native resolution, every pixel scaled up whole (2x for the main capsule; about 3x for the vertical, which needed a few more rows than a whole 3x holds)', 0.47),
    ('P1', 'painted', 'Oil, plain (Nano Banana Pro)', 'finish/out/nbpro/nbpro_d_painted.png',
     'the 4x render below repainted as an oil painting, the mask then corrected to his blank shell in a second pass', 0.47),
    ('P2', 'painted', 'Oil, plain (Nano Banana 2.1)', 'finish/out/nb21/nb21_d_painted.png', 'the same prompt on the other model', 0.47),
    ('P3', 'painted', 'Oil, after the It Follows cover (Pro)', 'finish/out/nbpro/nbpro_d_painted_ref.png',
     'the render plus the It Follows egg cover as the style reference; it took the cover\'s darkness too, so the field is no longer flat', 0.47),
    ('P4', 'painted', 'Oil, after the It Follows cover (2.1)', 'finish/out/nb21/nb21_d_painted_ref.png', 'the same, the other model', 0.47),
    ('E1', 'engraved', 'Engraving, ink on amber paper (Pro)', 'finish/out/nbpro/nbpro_d_engraved.png',
     'the render redrawn as a copperplate engraving in the manner of Vesalius\' plates (S11, S17), printed on amber', 0.47),
    ('E2', 'engraved', 'Engraving, ink on amber paper (2.1)', 'finish/out/nb21/d_engraved.png', 'the same prompt on the other model (its mask came out blank already)', 0.47),
    ('P5', 'painted', 'The mirrored framing, after the It Follows cover (Pro)', 'finish/out/nbpro/nbpro_a_painted_ref.png',
     'the other camera: his arm flung left, head and mask to the right (as Kaen faces)', 0.53),
]


def cut(im, size, cx_frac, pixel=False):
    """the slot's shape from a 16:9 image: full height, centred on the figure (pixel=True: whole-pixel upscale)"""
    W, H = im.size
    tw, th = size
    if pixel:
        if size == MAIN:
            # 2x whole pixels, the middle 1232x706 of 1280x720
            im = im.resize((W * 2, H * 2), Image.NEAREST)
            x0 = int(min(max(cx_frac * W * 2 - tw / 2, 0), W * 2 - tw))
            y0 = (H * 2 - th) // 2
            return im.crop((x0, y0, x0 + tw, y0 + th))
        # vertical: the figure and the mask need 301 of the 360 native rows; 896 at a whole 3x holds only 298, so
        # 302 native rows (from row 20) go up by ~2.97x, nearest (a pixel now and then a column narrower)
        nh = 302
        nw = round(nh * tw / th)
        x0 = int(min(max(cx_frac * W - nw / 2, 0), W - nw))
        return im.crop((x0, 20, x0 + nw, 20 + nh)).resize(size, Image.NEAREST)
    ar = tw / th
    ch = H
    cw = ch * ar
    if cw > W:
        cw, ch = W, W / ar
    x0 = min(max(cx_frac * W - cw / 2, 0), W - cw)
    y0 = (H - ch) / 2
    return im.crop((round(x0), round(y0), round(x0 + cw), round(y0 + ch))).resize(size, Image.LANCZOS)


def uri(im, q=90):
    b = io.BytesIO()
    im.save(b, 'JPEG', quality=q, optimize=True)
    return 'data:image/jpeg;base64,' + base64.b64encode(b.getvalue()).decode()


def card(code, label, how, main, vert):
    return (f'<div class="pair" id="{code}"><figure class="m"><img src="{uri(main)}" width="{MAIN[0]}" height="{MAIN[1]}" alt="{html.escape(label)}, main capsule">'
            f'<figcaption>main capsule 1232x706</figcaption></figure><figure class="v"><img src="{uri(vert)}" width="{VERT[0]}" height="{VERT[1]}" alt="{html.escape(label)}, vertical capsule">'
            f'<figcaption>vertical capsule 748x896</figcaption></figure></div>'
            f'<p class="cap"><b>{code}</b> <span class="t">{html.escape(label)}</span>: {html.escape(how)}</p>')


def page():
    fam, out = {}, []
    for code, family, label, src, how, cx in FINISHES:
        p = os.path.join(SRC, src)
        dst = os.path.join(FILES, f'{code}-' + os.path.basename(src))
        shutil.copy(p, dst)
        im = Image.open(dst).convert('RGB')
        pixel = family.startswith('the game')
        m, v = cut(im, MAIN, cx, pixel), cut(im, VERT, cx, pixel)
        m.save(os.path.join(FILES, f'{code}-main-1232x706.png'))
        v.save(os.path.join(FILES, f'{code}-vertical-748x896.png'))
        fam.setdefault(family, []).append(card(code, label, how, m, v))
    # the render under the painted and engraved ones, and the two references it answers
    plate = os.path.join(FILES, 'render-4x-d_y300.png')
    shutil.copy(os.path.join(SRC, 'hi', 'd_y300.png'), plate)
    pl = Image.open(plate).convert('RGB')
    refs = [('the render underneath (the game\'s own lich and mask, staged and rendered at 4x: 2560x1440)', pl.resize((1280, 720), Image.LANCZOS))]
    for fn in os.listdir(os.path.join(GAME, 'reference', 'identity', 'albums')):
        if fn.startswith('02-'):
            refs.append(('your A02 (Queen Bee, Kirei): the composition this answers', Image.open(os.path.join(GAME, 'reference', 'identity', 'albums', fn)).convert('RGB')))
    ref_html = ''.join(f'<figure class="r"><img src="{uri(im)}" alt="{html.escape(c)}"><figcaption>{html.escape(c)}</figcaption></figure>' for c, im in refs)
    order = [('the game\'s own render', 'The game\'s own render', 'Honest, and what you said: up close the game "doesn\'t look that good". The lich is a smooth, low-detail model.'),
             ('painted', 'Painted', 'Real bone, real paint. P3/P4 took the It Follows cover as their style reference.'),
             ('engraved', 'Engraved', 'The old-book side, matching the font: ink lines on a coloured paper, like the anatomy plates on the board.')]
    for key, head, lead in order:
        out.append(f'<section><h2>{html.escape(head)}</h2><p class="lead">{html.escape(lead)}</p>{"".join(fam.get(key, []))}</section>')
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Phylactery Finish Test</title><style>
:root {{ color-scheme: dark; --bg:#0d0b0a; --panel:#17130f; --ink:#efe3cc; --dim:#a8987c; --line:#2c241c; --accent:#e0b060; }}
html,body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,"Segoe UI",sans-serif; }}
header, section {{ max-width:1560px; margin:0 auto; padding:18px 16px 6px; }}
h1 {{ margin:10px 0 6px; font-size:24px; }} header p, .lead {{ margin:0 0 10px; color:var(--dim); max-width:1050px; }}
h2 {{ margin:26px 0 6px; font-size:20px; color:var(--accent); }}
.pair {{ display:flex; gap:12px; align-items:flex-start; flex-wrap:wrap; }}
figure {{ margin:0; }} figure img {{ display:block; height:auto; border:1px solid var(--line); border-radius:4px; }}
figure.m img {{ width:min(100%, 820px); }} figure.v img {{ width:min(100%, 400px); }}
figure.m {{ flex:1 1 560px; max-width:820px; }} figure.v {{ flex:0 1 300px; max-width:400px; }}
figure.r {{ display:inline-block; vertical-align:top; margin:0 12px 12px 0; max-width:min(100%, 640px); }} figure.r img {{ max-width:100%; max-height:420px; }}
figcaption {{ color:var(--dim); font-size:12px; padding:3px 1px; }}
.cap {{ margin:4px 0 22px; color:var(--dim); font-size:14px; }} .cap b {{ color:var(--accent); }} .cap .t {{ color:var(--ink); }}
</style></head><body>
<header><h1>Round 95: one composition, finished three ways</h1>
<p>Purpose: choose the look before fifteen compositions get made. Your A02: the lich arched back (his own pose from the ending,
your Kaen reference) with his mask leaving his face, on a flat field of the game's amber. Staged in the game itself with his real
model and mask, then finished three ways, each cut to the main capsule (the store front's big carousel) and the vertical capsule.
Not settled here: composition (it is centred, with no room yet for the title: round 96), the field's colour, the titles.</p>
<p>What to say: which family (game render, painted, engraved, or a mix by slot), and within it which one (codes). Parts of
several are fine ("P3's light with P1's flat field").</p>
<div>{ref_html}</div></header>
{''.join(out)}
</body></html>'''


if __name__ == '__main__':
    s = page()
    open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8').write(s)
    print(os.path.join(HERE, 'index.html'), f'{len(s)/1e6:.1f} MB')
