# make_page.py -- round 100: his notes on round 98 applied, with the title three ways per slot (Phylactery 20,
# 2026-10-18). Sources in scratch/s20/r100/ (fix/ = A01 + A02 without the mask and lens; s15/ = the game's lens and
# orbs laid in; t41/ = the egg upright; a22/ = the orbs onto the frame; flatset/ = A24 as a flat design, rendered from
# tools/flat_a24.py by headless Edge); the title is tools/title.py. Every final and every slot PNG goes in files/; the
# page embeds JPEGs at their shown size so it stays light (round 99's 6.8 MB page did not open for him).
#   python rounds/100-store-art/make_page.py   (from lich-survivors/)
import base64, html, io, os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(GAME, 'tools'))
from title import wordmark, lay        # noqa: E402

S = os.path.join(GAME, 'scratch', 's20', 'r100')
FILES = os.path.join(HERE, 'files')
os.makedirs(FILES, exist_ok=True)
SIZE = 0


def cut(im, w, h, cx=0.5, cy=0.5):
    W, H = im.size
    r = w / h
    cw, ch = (round(H * r), H) if W / H > r else (W, round(W / r))
    x0 = int(min(max(cx * W - cw / 2, 0), W - cw)); y0 = int(min(max(cy * H - ch / 2, 0), H - ch))
    return im.crop((x0, y0, x0 + cw, y0 + ch)).resize((w, h), Image.LANCZOS)


def place(im, text, spec_, tracking=0.0, scrim=1.0):
    W, H = im.size
    xa, cy, wf, an = spec_
    wm = wordmark(text, round(W * wf), tracking=tracking)
    w, h = wm.size
    x = {'l': xa * W, 'c': xa * W - w / 2, 'r': xa * W - w}[an]
    return lay(im, wm, at=(round(x), round(cy * H - h / 2)), scrim=scrim)[0]


def uri(im, w, q=82):
    global SIZE
    im = im.convert('RGB')
    if im.size[0] > w * 1.25:
        im = im.resize((round(w * 1.25), round(im.size[1] * w * 1.25 / im.size[0])), Image.LANCZOS)
    b = io.BytesIO(); im.save(b, 'JPEG', quality=q, optimize=True)
    SIZE += b.tell()
    return 'data:image/jpeg;base64,' + base64.b64encode(b.getvalue()).decode()


def fig(im, cap, dw):
    return (f'<figure style="max-width:{dw}px"><img src="{uri(im, dw)}" style="width:{dw}px" alt="{html.escape(cap)}">'
            f'<figcaption>{html.escape(cap)}</figcaption></figure>')


def save(im, name):
    im.convert('RGB').save(os.path.join(FILES, name))


SRC = {
    'A24 flat': os.path.join(S, 'flatset', 'h', 'header_flat.png'),
    'A24 glass': os.path.join(S, 'flatset', 'h', 'header_glass.png'),
    'S15': os.path.join(S, 's15', 's15_fixed.png'),
    'A01 vertical': os.path.join(S, 'fix', 'a01_vertical.png'),
    'A01 wide': os.path.join(S, 'fix', 'a01_wide.png'),
    'A02': os.path.join(S, 'fix', 'a02_vertical.png'),
    'T41': os.path.join(S, 't41', 't41_a.png'),
    'A22': os.path.join(S, 'a22', 'a22_fixed.png'),
}
# per slot: (code, source, crop cx, cy, steam title (x, y, width, anchor), small title (x, y, width, anchor), note)
SLOTS = [
    ('Header capsule', (920, 430), [(460, 215), (231, 108)], [
        ('A24 flat', 'A24 flat', 0.5, 0.5, (0.965, 0.16, 0.34, 'r'), (0.96, 0.10, 0.24, 'r'),
         'A flat design after the cover: his finger at the left edge, the white beam to the snake, the snake\'s middle '
         'breaking apart, the spectrum out the far side. The snake in flat fills of the game snake\'s colours.'),
        ('A24 glass', 'A24 glass', 0.5, 0.5, (0.965, 0.16, 0.34, 'r'), (0.96, 0.10, 0.24, 'r'),
         'The same, the snake drawn the way the cover draws its prism: an airbrushed pale edge on black.'),
        ('S15', 'S15', 0.5, 0.5, (0.5, 0.17, 0.60, 'c'), (0.95, 0.92, 0.24, 'r'),
         'The lens and the orbs are now the game\'s: the thin clear lens with its fine rim (the game\'s render laid in), '
         'the five smoky glass orbs with their seams (cut from the game\'s own view of them, warmed to this light).')]),
    ('Main capsule', (1232, 706), [(616, 353)], [
        ('A01', 'A01 wide', 0.5, 0.5, (0.04, 0.16, 0.38, 'l'), (0.95, 0.93, 0.2, 'r'), 'The mask taken off.')]),
    ('Vertical capsule', (748, 896), [(374, 448)], [
        ('A01', 'A01 vertical', 0.5, 0.5, (0.95, 0.89, 0.62, 'r'), (0.94, 0.94, 0.34, 'r'), 'The mask taken off.'),
        ('A02', 'A02', 0.5, 0.5, (0.5, 0.91, 0.80, 'c'), (0.5, 0.955, 0.34, 'c'), 'The mask and the lens taken off.'),
        ('T41', 'T41', 0.5, 0.62, (0.5, 0.92, 0.78, 'c'), (0.5, 0.955, 0.34, 'c'), 'The egg stands up (the game\'s square flecks), at the size it had.')]),
    ('Library capsule', (600, 900), [(300, 450), (150, 225)], [
        ('A02', 'A02', 0.5, 0.5, (0.5, 0.91, 0.84, 'c'), (0.5, 0.955, 0.4, 'c'), 'The mask and the lens taken off.'),
        ('T41', 'T41', 0.5, 0.5, (0.5, 0.93, 0.84, 'c'), (0.5, 0.96, 0.4, 'c'), 'The egg stands up.'),
        ('A22', 'A22', 0.5, 0.5, (0.5, 0.93, 0.84, 'c'), (0.5, 0.96, 0.4, 'c'),
         'The five orbs taken off the dark ground and set into the frame, like the other five things.')]),
]


def page():
    secs = []
    for slot, (W, H), checks, cands in SLOTS:
        rows = ''
        for code, src, cx, cy, steam, small, note in cands:
            im = Image.open(SRC[src]).convert('RGB')
            base = cut(im, W, H, cx, cy) if im.size != (W, H) else im
            a = place(base, 'PHYLACTERY', small, tracking=0.14)
            b = place(base, 'Phylactery', steam)
            stem = f'{slot.lower().replace(" ", "-")}-{code.lower().replace(" ", "-")}'
            save(base, f'{stem}-none-{W}x{H}.png'); save(a, f'{stem}-small-{W}x{H}.png'); save(b, f'{stem}-steam-{W}x{H}.png')
            dw = 360 if W > H else 240
            shrunk = ''.join(fig(b.resize(c, Image.LANCZOS), f'at {c[0]}x{c[1]}', c[0]) for c in checks)
            rows += (f'<h3>{html.escape(code)}</h3><p class="lead">{html.escape(note)}</p><div class="row">'
                     + fig(base, 'No words', dw) + fig(a, 'Small title', dw) + fig(b, 'Steam-standard', dw) + shrunk + '</div>')
        secs.append(f'<section><h2>{html.escape(slot)} ({W}x{H})</h2>{rows}</section>')
    # small capsule
    figs = ''
    s15 = Image.open(SRC['S15']).convert('RGB')
    Wd, Hd = s15.size
    cw = Wd * 0.75; ch = cw * 174 / 462
    g1 = s15.crop((round(0.5 * Wd - cw / 2), round(0.45 * Hd - ch / 2), round(0.5 * Wd + cw / 2), round(0.45 * Hd + ch / 2))).resize((462, 174), Image.LANCZOS)
    g2 = Image.open(os.path.join(S, 'flatset', 's2', 'small_bare.png')).convert('RGB')
    for k, g, wf in (('S15', g1, 0.86), ('A24', g2, 0.78)):
        wm = wordmark('Phylactery', round(462 * wf))
        out = lay(g, wm, at=((462 - wm.size[0]) // 2, (174 - wm.size[1]) // 2 - 4), scrim=1.4)[0]
        save(out, f'small-capsule-{k}-462x174.png')
        figs += fig(out, f'{k} 462x174', 462) + fig(out.resize((184, 69), Image.LANCZOS), 'at 184x69', 184) + fig(out.resize((120, 45), Image.LANCZOS), 'at 120x45', 120)
    secs.append('<section><h2>Small capsule (462x174)</h2><p class="lead">Search results and lists; the logo nearly '
                'fills it. A24\'s ground is the flat design without the snake: the beam runs into the P, the spectrum out '
                'of the y.</p><div class="row">' + figs + '</div></section>')
    # heroes, with the library logo where Steam puts it by default (bottom-left)
    logo = Image.open(os.path.join(GAME, 'rounds', '99-titles', 'files', 'library-logo-1280.png')).convert('RGBA')
    logo.save(os.path.join(FILES, 'library-logo-1280.png'))
    heroes = [('A24 flat', os.path.join(S, 'flatset', 'x4', 'hero_flat.png')),
              ('A24 glass', os.path.join(S, 'flatset', 'x4', 'hero_glass.png'))]
    s15h = s15.crop((0, 180, Wd, 180 + round(Wd / (3840 / 1240)))).resize((3840, 1240), Image.LANCZOS)
    s15h.save(os.path.join(S, 's15', 's15_hero.png'))
    heroes.append(('S15', os.path.join(S, 's15', 's15_hero.png')))
    hf = ''
    for k, p in heroes:
        h = Image.open(p).convert('RGB')
        save(h, f'library-hero-{k.lower().replace(" ", "-")}-3840x1240.png')
        v = h.resize((1920, 620), Image.LANCZOS).convert('RGBA')
        lw = 460
        lg = logo.resize((lw, round(logo.size[1] * lw / 1280)), Image.LANCZOS)
        v.alpha_composite(lg, (36, 620 - lg.size[1] - 26))
        hf += fig(v, f'{k}: as Steam shows it (1920x620), the library logo bottom-left', 1200)
    secs.append('<section><h2>Library hero (3840x1240, no words) with the library logo</h2><p class="lead">The A10 hero '
                'is replaced. Two directions: the flat design run wide (the cover\'s own layout is a horizontal one), and '
                'S15 cut to the hero\'s shape. The logo is the transparent 1280 PNG Steam lays over it.</p>'
                '<div class="col">' + hf + '</div></section>')
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Phylactery Store Art</title><style>
:root {{ color-scheme: dark; --bg:#0d0b0a; --ink:#efe3cc; --dim:#a8987c; --line:#2c241c; --accent:#e0b060; }}
html,body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,"Segoe UI",sans-serif; }}
header, section {{ max-width:1560px; margin:0 auto; padding:18px 16px 8px; }}
h1 {{ margin:10px 0 6px; font-size:24px; }} header p, .lead {{ margin:0 0 10px; color:var(--dim); max-width:1080px; }}
h2 {{ margin:26px 0 6px; font-size:20px; color:var(--accent); }} h3 {{ margin:14px 0 2px; font-size:15px; }}
.row {{ display:flex; flex-wrap:wrap; gap:12px; align-items:flex-end; }} .col {{ display:flex; flex-direction:column; gap:14px; }}
figure {{ margin:0; max-width:100%; }} figure img {{ display:block; max-width:100%; height:auto; border:1px solid var(--line); border-radius:4px; }}
figcaption {{ color:var(--dim); font-size:12px; padding:3px 1px; }}
</style></head><body>
<header><h1>Round 100: your notes on round 98, with the titles</h1>
<p>No mask in front of him anywhere. A24 redone as a flat design (two ways to draw the snake). S15's lens and orbs, T41's
egg, A22's orbs fixed. A34 and the A10 hero dropped; two new hero directions. Each slot three ways: no words, a small
title, and Steam's standard (shown again at the sizes Steam shrinks it to). This page replaces round 99, which was too
heavy to open; its title manner is the same (Phylactery Serif in cream, the It Follows cover's way). T01's icons and
event cover are unchanged from round 98.</p>
</header>
{''.join(secs)}
</body></html>'''


if __name__ == '__main__':
    s = page()
    open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8').write(s)
    print(os.path.join(HERE, 'index.html'), f'{len(s)/1e6:.2f} MB')
