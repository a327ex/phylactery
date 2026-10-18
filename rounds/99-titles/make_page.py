# make_page.py -- round 99: the title on the store art, three ways per slot (none / small / Steam-standard), checked at
# the sizes Steam shrinks them to (Phylactery 20, 2026-10-18). The paintings are round 97's and 98's slot cuts (their
# files/ folders, already delivered); the title is tools/title.py (Phylactery Serif, the It Follows cover's manner).
#   python rounds/99-titles/make_page.py   (from lich-survivors/)
import base64, html, io, os, sys
import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(GAME, 'tools'))
from title import wordmark, lay        # noqa: E402

R7 = os.path.join(GAME, 'rounds', '97-game-objects', 'files')
R8 = os.path.join(GAME, 'rounds', '98-snakes-and-egg', 'files')
FILES = os.path.join(HERE, 'files')
os.makedirs(FILES, exist_ok=True)

# placements: (x anchor, y centre, width, anchor l|c|r) as fractions of the slot; per painting, in its dark space
SLOTS = [
    ('Header capsule', 'Also the library header unless one is set. Valve: a legible logo filling at least a third.', [(460, 215), (231, 108)], [
        ('S15', R7, 'S15-library-header-920x430.png', (0.5, 0.17, 0.60, 'c'), (0.95, 0.92, 0.24, 'r')),
        ('A24', R8, 'A24-header-capsule-920x430.png', (0.04, 0.87, 0.46, 'l'), (0.95, 0.92, 0.24, 'r'))]),
    ('Main capsule', 'The store front\'s big carousel. Key art + logo.', [(616, 353)], [
        ('A01', R7, 'A01-main-capsule-1232x706.png', (0.04, 0.16, 0.38, 'l'), (0.95, 0.93, 0.2, 'r')),
        ('A34', R8, 'A34-main-capsule-1232x706.png', (0.035, 0.16, 0.33, 'l'), (0.95, 0.93, 0.2, 'r'))]),
    ('Vertical capsule', 'The store\'s seasonal sales pages.', [(374, 448)], [
        ('A01', R7, 'A01-vertical-capsule-748x896.png', (0.95, 0.89, 0.62, 'r'), (0.94, 0.94, 0.34, 'r')),
        ('A02', R7, 'A02-vertical-capsule-748x896.png', (0.5, 0.91, 0.80, 'c'), (0.5, 0.955, 0.34, 'c')),
        ('T41', R7, 'T41-vertical-capsule-748x896.png', (0.5, 0.92, 0.78, 'c'), (0.5, 0.955, 0.34, 'c')),
        ('A34', R8, 'A34-vertical-capsule-748x896.png', (0.5, 0.92, 0.80, 'c'), (0.5, 0.955, 0.34, 'c'))]),
    ('Library capsule', 'The library grid (Steam makes a 300x450). Logo required.', [(300, 450), (150, 225)], [
        ('A02', R7, 'A02-library-capsule-600x900.png', (0.5, 0.91, 0.84, 'c'), (0.5, 0.955, 0.4, 'c')),
        ('T41', R7, 'T41-library-capsule-600x900.png', (0.5, 0.93, 0.84, 'c'), (0.5, 0.96, 0.4, 'c')),
        ('A34', R8, 'A34-library-capsule-600x900.png', (0.5, 0.92, 0.84, 'c'), (0.5, 0.955, 0.4, 'c')),
        ('A22', R8, 'A22-library-capsule-600x900.png', (0.5, 0.93, 0.84, 'c'), (0.5, 0.96, 0.4, 'c'))]),
]


def place(im, wm, spec, scrim=1.0):
    W, H = im.size
    xa, cy, wf, an = spec
    w, h = wm.size
    x = {'l': xa * W, 'c': xa * W - w / 2, 'r': xa * W - w}[an]
    return lay(im, wm, at=(round(x), round(cy * H - h / 2)), scrim=scrim)[0]


def standard(im, spec):
    return place(im, wordmark('Phylactery', round(im.size[0] * spec[2])), spec)


def small(im, spec):
    return place(im, wordmark('PHYLACTERY', round(im.size[0] * spec[2]), tracking=0.14), spec)


def uri(im, q=90):
    b = io.BytesIO(); im.convert('RGB').save(b, 'JPEG', quality=q, optimize=True)
    return 'data:image/jpeg;base64,' + base64.b64encode(b.getvalue()).decode()


def uri_png(im):
    b = io.BytesIO(); im.save(b, 'PNG', optimize=True)
    return 'data:image/png;base64,' + base64.b64encode(b.getvalue()).decode()


def fig(im, cap, dw):
    return (f'<figure style="max-width:{dw}px"><img src="{uri(im)}" style="width:{dw}px" alt="{html.escape(cap)}">'
            f'<figcaption>{html.escape(cap)}</figcaption></figure>')


def save(im, name):
    im.save(os.path.join(FILES, name))


def library_logo():
    """Steam's library logo: 1280 wide, transparent, its soft shadow in the alpha so it reads over the bright shaft"""
    wm = wordmark('Phylactery', 1180)
    w, h = wm.size
    pad = 50
    W, H = w + 2 * pad, h + 2 * pad
    al = Image.new('L', (W, H), 0); al.paste(wm.split()[3], (pad, pad))
    sh = np.asarray(al.filter(ImageFilter.GaussianBlur(14))).astype(np.float32) / 255 * 0.75
    a = np.asarray(al).astype(np.float32) / 255
    rgb = np.zeros((H, W, 3), np.float32); rgb[:] = (12, 7, 3)
    ink = np.zeros((H, W, 3), np.float32); ink[pad:pad + h, pad:pad + w] = np.asarray(wm)[..., :3]
    out_a = a + sh * (1 - a)
    out_rgb = (ink * a[..., None] + rgb * (sh * (1 - a))[..., None]) / np.maximum(out_a, 1e-6)[..., None]
    out = np.dstack([out_rgb, out_a * 255]).clip(0, 255).astype(np.uint8)
    im = Image.fromarray(out, 'RGBA')
    im = im.resize((1280, round(H * 1280 / W)), Image.LANCZOS)
    return im


def page():
    secs = []
    # the two wordmarks on one header
    s15 = Image.open(os.path.join(R7, 'S15-library-header-920x430.png')).convert('RGB')
    mixed = standard(s15, (0.5, 0.17, 0.60, 'c'))
    caps = place(s15, wordmark('PHYLACTERY', round(920 * 0.66), tracking=0.06), (0.5, 0.15, 0.66, 'c'))
    save(caps, 'compare-caps-S15-header.png')
    secs.append('<section><h2>The wordmark: mixed case (used below) or capitals</h2><p class="lead">Mixed case is the It '
                'Follows cover\'s way and shows the font\'s character (the P, the y\'s tail); capitals are the quieter, '
                'more monumental way. The small versions below use spaced capitals either way.</p><div class="row">'
                + fig(mixed, 'Mixed case', 600) + fig(caps, 'Capitals', 600) + '</div></section>')
    for slot, note, checks, cands in SLOTS:
        rows = ''
        for code, root, f, std_spec, small_spec in cands:
            im = Image.open(os.path.join(root, f)).convert('RGB')
            W, H = im.size
            a, b = small(im, small_spec), standard(im, std_spec)
            stem = f'{slot.lower().replace(" ", "-")}-{code}'
            save(im, f'{stem}-none-{W}x{H}.png'); save(b, f'{stem}-steam-{W}x{H}.png'); save(a, f'{stem}-small-{W}x{H}.png')
            dw = 380 if W > H else 250
            shrunk = ''.join(fig(b.resize(c, Image.LANCZOS), f'at {c[0]}x{c[1]}', c[0]) for c in checks)
            rows += (f'<h3>{code}</h3><div class="row">' + fig(im, 'No words', dw) + fig(a, 'Small title', dw)
                     + fig(b, 'Steam-standard', dw) + shrunk + '</div>')
        secs.append(f'<section><h2>{html.escape(slot)} ({W}x{H})</h2><p class="lead">{html.escape(note)}</p>{rows}</section>')
    # small capsule
    figs = ''
    for k, f, cx, cy, frac in (('S15', 'S15-final-s15_final.png', 0.5, 0.45, 0.75), ('A24', 'A24-final-a24.png', 0.42, 0.42, 0.62)):
        src = Image.open(os.path.join(R7 if k == 'S15' else R8, f)).convert('RGB')
        Wd, Hd = src.size
        cw = Wd * frac; ch = cw * 174 / 462
        bg = src.crop((round(cx * Wd - cw / 2), round(cy * Hd - ch / 2), round(cx * Wd + cw / 2), round(cy * Hd + ch / 2))).resize((462, 174), Image.LANCZOS)
        wm = wordmark('Phylactery', round(462 * 0.86))
        out = lay(bg, wm, at=((462 - wm.size[0]) // 2, (174 - wm.size[1]) // 2 - 4), scrim=1.4)[0]
        save(out, f'small-capsule-{k}-462x174.png')
        figs += fig(out, f'{k} 462x174', 462) + fig(out.resize((184, 69), Image.LANCZOS), 'at 184x69', 184) + fig(out.resize((120, 45), Image.LANCZOS), 'at 120x45', 120)
    secs.append('<section><h2>Small capsule (462x174)</h2><p class="lead">Search results and lists, shown at 184x69 and '
                '120x45: Valve wants the logo to nearly fill it. Two grounds: S15\'s glow, A24\'s beam (the one colour '
                'that stands out in a list).</p><div class="row">' + figs + '</div></section>')
    # library logo + hero
    logo = library_logo()
    logo.save(os.path.join(FILES, 'library-logo-1280.png'))
    hero = Image.open(os.path.join(R7, 'A10-library-hero-3840x1240.png')).convert('RGB').resize((1920, 620), Image.LANCZOS).convert('RGBA')
    lw = 560
    lg = logo.resize((lw, round(logo.size[1] * lw / 1280)), Image.LANCZOS)
    hb = hero.copy(); hb.alpha_composite(lg, (40, 620 - lg.size[1] - 30))
    hb = hb.convert('RGB'); save(hb, 'hero-with-logo-bottom-left-1920x620.png')
    checker = Image.new('RGB', logo.size, (90, 90, 90))
    for y in range(0, logo.size[1], 32):
        for x in range(0, logo.size[0], 32):
            if (x // 32 + y // 32) % 2:
                checker.paste((140, 140, 140), (x, y, x + 32, y + 32))
    checker = checker.convert('RGBA'); checker.alpha_composite(logo)
    secs.append('<section><h2>Library logo (1280 wide, transparent) over the hero</h2><p class="lead">The logo carries '
                'its own soft shadow in its transparency, so it reads over the shaft\'s light too. Steam lets you place '
                'it bottom-left, top-centre, centre or bottom-centre and scale it; bottom-left keeps it off him and the '
                'egg. The hero itself has no words (Valve\'s rule).</p><div class="row">'
                + f'<figure style="max-width:640px"><img src="{uri_png(checker.convert("RGB"))}" style="width:640px" alt="logo"><figcaption>library-logo-1280.png on a checker</figcaption></figure>'
                + fig(hb, 'Library hero as Steam shows it (1920x620), logo bottom-left', 1500) + '</div></section>')
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Phylactery Store Titles</title><style>
:root {{ color-scheme: dark; --bg:#0d0b0a; --ink:#efe3cc; --dim:#a8987c; --line:#2c241c; --accent:#e0b060; }}
html,body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,"Segoe UI",sans-serif; }}
header, section {{ max-width:1560px; margin:0 auto; padding:18px 16px 8px; }}
h1 {{ margin:10px 0 6px; font-size:24px; }} header p, .lead {{ margin:0 0 10px; color:var(--dim); max-width:1080px; }}
h2 {{ margin:26px 0 6px; font-size:20px; color:var(--accent); }} h3 {{ margin:14px 0 4px; font-size:15px; color:var(--ink); }}
.row {{ display:flex; flex-wrap:wrap; gap:12px; align-items:flex-end; }}
figure {{ margin:0; max-width:100%; }} figure img {{ display:block; max-width:100%; height:auto; border:1px solid var(--line); border-radius:4px; }}
figcaption {{ color:var(--dim); font-size:12px; padding:3px 1px; }}
</style></head><body>
<header><h1>Round 99: the title, three ways per slot</h1>
<p>Every candidate from rounds 97 and 98 that goes in a slot needing the logo, each three ways: no words; a small title
(spaced capitals, out of the way, the painting first); and Steam's standard (the logo big enough for Valve's "a legible
logo filling at least a third", shown again at the sizes Steam shrinks it to). The manner is the It Follows cover's: the
serif (Phylactery Serif) in a warm cream lit from above, in the painting's own dark space, with a soft shadow, and a
darkening under it only where the ground is too light. Placed by hand per painting, never over his face, the egg or a
snake's head. The hero, the page background, the screenshots and the event images take no words.</p>
</header>
{''.join(secs)}
</body></html>'''


if __name__ == '__main__':
    s = page()
    open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8').write(s)
    print(os.path.join(HERE, 'index.html'), f'{len(s)/1e6:.1f} MB')
