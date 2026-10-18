# make_page.py -- round 103: A01 in every slot it can take (his "The best image we have is A01, let's try to first use
# that in as many places as we can"), the title by his rule (round 102: big where Steam asks a legible logo, small on the
# event images, none on the hero, background and icons) (Phylactery 20, 2026-10-18).
# The slots whose shape A01's two paintings do not have come from tools/extend_canvas.py (the painting kept pixel for
# pixel, its own dark ground carried outward; the image model, asked to fill margins, repainted the figure instead):
# scratch/s20/r103/proc2/{hero,header,library}.png. The main capsule is round 97's wide A01 (mask off, round 100).
#   python rounds/103-a01-everywhere/make_page.py   (from lich-survivors/)
import base64, html, io, os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(GAME, 'tools'))
from title import wordmark, lay        # noqa: E402

P2 = os.path.join(GAME, 'scratch', 's20', 'r103', 'proc2')
FIX = os.path.join(GAME, 'scratch', 's20', 'r100', 'fix')
FILES = os.path.join(HERE, 'files')
os.makedirs(FILES, exist_ok=True)
SRC = {'vertical': os.path.join(FIX, 'a01_vertical.png'), 'wide': os.path.join(FIX, 'a01_wide.png'),
       'hero': os.path.join(P2, 'hero.png'), 'header': os.path.join(P2, 'header.png'), 'library': os.path.join(P2, 'library.png')}
BIG, SMALL, NONE = 'big', 'small', 'none'


def cut(im, w, h, cx=0.5, cy=0.5, zoom=1.0):
    W, H = im.size
    r = w / h
    cw, ch = (round(H * r), H) if W / H > r else (W, round(W / r))
    cw, ch = round(cw / zoom), round(ch / zoom)
    x0 = int(min(max(cx * W - cw / 2, 0), W - cw)); y0 = int(min(max(cy * H - ch / 2, 0), H - ch))
    return im.crop((x0, y0, x0 + cw, y0 + ch)).resize((w, h), Image.LANCZOS)


def titled(im, kind, spec, scrim=1.0):
    if kind == NONE:
        return im
    W, H = im.size
    xa, cy, wf, an = spec
    wm = wordmark('Phylactery', round(W * wf)) if kind == BIG else wordmark('PHYLACTERY', round(W * wf), tracking=0.14)
    w, h = wm.size
    x = {'l': xa * W, 'c': xa * W - w / 2, 'r': xa * W - w}[an]
    return lay(im, wm, at=(round(x), round(cy * H - h / 2)), scrim=scrim)[0]


def uri(im, w, q=84):
    im = im.convert('RGB')
    if im.size[0] > w * 1.25:
        im = im.resize((round(w * 1.25), round(im.size[1] * w * 1.25 / im.size[0])), Image.LANCZOS)
    b = io.BytesIO(); im.save(b, 'JPEG', quality=q, optimize=True)
    return 'data:image/jpeg;base64,' + base64.b64encode(b.getvalue()).decode()


def fig(im, cap, dw):
    return (f'<figure style="max-width:{dw}px"><img src="{uri(im, dw)}" style="width:{dw}px" alt="{html.escape(cap)}">'
            f'<figcaption>{html.escape(cap)}</figcaption></figure>')


# (slot, size, title kind, source, cut (cx, cy, zoom), title spec, shown width, shrunk checks, note)
SLOTS = [
    ('Header capsule + library header', (920, 430), BIG, 'header', (0.5, 0.5, 1.0), (0.05, 0.40, 0.42, 'l'), 460, [(231, 108)],
     'Him on the right, the title in his dark on the left.'),
    ('Small capsule', (462, 174), BIG, 'hero', (0.5, 0.33, 1.55), (0.5, 0.48, 0.86, 'c'), 462, [(184, 69), (120, 45)],
     'The logo nearly fills it; his glow and ribs behind it.'),
    ('Main capsule', (1232, 706), BIG, 'wide', (0.5, 0.5, 1.0), (0.04, 0.16, 0.38, 'l'), 560, [(616, 353)], 'Round 97\'s wide A01, the mask off.'),
    ('Vertical capsule', (748, 896), BIG, 'vertical', (0.5, 0.5, 1.0), (0.95, 0.89, 0.62, 'r'), 300, [(374, 448)], 'The painting itself.'),
    ('Library capsule', (600, 900), BIG, 'library', (0.5, 0.5, 1.0), (0.5, 0.88, 0.80, 'c'), 300, [(300, 450), (150, 225)],
     'The painting on a taller canvas (its own dark ground below), the title under him.'),
    ('Event cover', (800, 450), SMALL, 'wide', (0.5, 0.5, 1.0), (0.04, 0.09, 0.26, 'l'), 400, [], 'Steam adds the name and icon beside it.'),
    ('Event header', (1920, 622), SMALL, 'hero', (0.5, 0.5, 1.0), (0.03, 0.12, 0.17, 'l'), 760, [], ''),
    ('Page background', (1438, 810), NONE, 'wide', (0.5, 0.5, 1.0), None, 480, [], 'Steam tints it and fades its edges.'),
    ('Shortcut + app icon', (256, 256), NONE, 'vertical', (0.665, 0.25, 1.8), None, 256, [(184, 184), (32, 32)],
     'His skull and reaching hand in the glow.'),
]


def page():
    secs = []
    for slot, (W, H), kind, src, (cx, cy, z), spec, dw, checks, note in SLOTS:
        base = cut(Image.open(SRC[src]).convert('RGB'), W, H, cx, cy, z)
        out = titled(base, kind, spec, scrim=1.4 if slot == 'Small capsule' else 1.0)
        name = slot.lower().replace(' + ', '-and-').replace(' ', '-')
        out.save(os.path.join(FILES, f'{name}-A01-{W}x{H}.png'))
        figs = fig(out, f'{W}x{H}', dw) + ''.join(fig(out.resize(c, Image.LANCZOS), f'at {c[0]}x{c[1]}', c[0]) for c in checks)
        label = {BIG: 'big title', SMALL: 'small title', NONE: 'no words'}[kind]
        secs.append(f'<section><h2>{html.escape(slot)} {W}x{H}: {label}</h2><p class="lead">{html.escape(note)}</p>'
                    f'<div class="row">{figs}</div></section>')
    logo = Image.open(os.path.join(GAME, 'rounds', '99-titles', 'files', 'library-logo-1280.png')).convert('RGBA')
    logo.save(os.path.join(FILES, 'library-logo-1280.png'))
    hero = Image.open(SRC['hero']).convert('RGB')
    hero.save(os.path.join(FILES, 'library-hero-A01-3840x1240.png'))
    v = hero.resize((1920, 620), Image.LANCZOS).convert('RGBA')
    lg = logo.resize((460, round(logo.size[1] * 460 / 1280)), Image.LANCZOS)
    v.alpha_composite(lg, (36, 620 - lg.size[1] - 26))
    secs.insert(0, '<section><h2>Library hero 3840x1240 (no words) + the library logo</h2><p class="lead">Him in the middle '
                'of a wide dark, inside Steam\'s centred safe area; the logo bottom-left in the dark.</p><div class="row">'
                + fig(v, 'As Steam shows it (1920x620), the logo bottom-left', 1100) + '</div></section>')
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Phylactery A01 Everywhere</title><style>
:root {{ color-scheme: dark; --bg:#0d0b0a; --ink:#efe3cc; --dim:#a8987c; --line:#2c241c; --accent:#e0b060; }}
html,body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,"Segoe UI",sans-serif; }}
header, section {{ max-width:1560px; margin:0 auto; padding:16px 16px 6px; }}
h1 {{ margin:10px 0 6px; font-size:24px; }} header p, .lead {{ margin:0 0 10px; color:var(--dim); max-width:1080px; }}
h2 {{ margin:20px 0 4px; font-size:19px; color:var(--accent); }}
.row {{ display:flex; flex-wrap:wrap; gap:12px; align-items:flex-end; }}
figure {{ margin:0; max-width:100%; }} figure img {{ display:block; max-width:100%; height:auto; border:1px solid var(--line); border-radius:4px; }}
figcaption {{ color:var(--dim); font-size:12px; padding:3px 1px; }}
</style></head><body>
<header><h1>Round 103: A01 everywhere</h1>
<p>Every slot cut from A01. Where a slot's shape is not one of its two paintings (the hero, the header, the library
capsule), the painting is set on a bigger canvas and its own dark ground carried outward: the painting itself is untouched,
and nothing new is painted round him (the image model, asked for the same, painted a second skeleton). Titles by your rule:
big where Steam asks a legible logo, small on the event images, none on the hero, the background and the icons.</p>
</header>
{''.join(secs)}
</body></html>'''


if __name__ == '__main__':
    s = page()
    open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8').write(s)
    print(os.path.join(HERE, 'index.html'), f'{len(s)/1e6:.2f} MB')
