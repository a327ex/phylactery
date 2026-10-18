# make_page.py -- round 102: the whole store set, slot by slot, with his title rule (Phylactery 20, 2026-10-18):
# "use the small font whenever possible, the big one only when the image requires a fully readable title as per Steam
# guidelines". Steam's upload confirmations (steam-release/RUNBOOK.md section 7) ask a legible logo filling >= 1/3 of
# the header, main, vertical and library capsules and the library header, and a logo nearly filling the small capsule:
# those take the big title. The event images carry "artwork + branding" with Steam adding the name: the small title. The
# hero, page background, screenshots and icons take none. A24 is dropped (his "A24 is not working").
# Sources: scratch/s20/r100/ (fix/, s15/, t41/), scratch/s20/r102/a22/, rounds/98-snakes-and-egg/files/ (T01),
# rounds/99-titles/files/library-logo-1280.png.
#   python rounds/102-the-set/make_page.py   (from lich-survivors/)
import base64, html, io, os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(GAME, 'tools'))
from title import wordmark, lay        # noqa: E402

R100 = os.path.join(GAME, 'scratch', 's20', 'r100')
R102 = os.path.join(GAME, 'scratch', 's20', 'r102')
R98F = os.path.join(GAME, 'rounds', '98-snakes-and-egg', 'files')
FILES = os.path.join(HERE, 'files')
os.makedirs(FILES, exist_ok=True)

SRC = {
    'S15': os.path.join(R100, 's15', 's15_fixed.png'),
    'S15 hero': os.path.join(R102, 's15_hero.png'),               # (cut at the bottom: bare floor under the logo)
    'A01 wide': os.path.join(R100, 'fix', 'a01_wide.png'),
    'A01': os.path.join(R100, 'fix', 'a01_vertical.png'),
    'A02': os.path.join(R100, 'fix', 'a02_vertical.png'),
    'T41': os.path.join(R100, 't41', 't41_a.png'),
    'A22': os.path.join(R102, 'a22', 'a22_fixed.png'),
    'A22 extended': os.path.join(R102, 'a22', 'a22_ext_final.png'),
    'T01 wide': os.path.join(R98F, 'T01-final-t01_wide.png'),
    'T01 square': os.path.join(R98F, 'T01-final-t01_sq.png'),
}
BIG, SMALL, NONE = 'big', 'small', 'none'


def cut(im, w, h, cx=0.5, cy=0.5):
    W, H = im.size
    r = w / h
    cw, ch = (round(H * r), H) if W / H > r else (W, round(W / r))
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


# (slot, size, title kind, why, shown width, steam's shrunk sizes, [(code, source, cx, cy, title spec)])
SLOTS = [
    ('Header capsule (also the library header)', (920, 430), BIG, 'Valve: a legible logo filling at least a third.', 460, [(231, 108)],
     [('S15', 'S15', 0.5, 0.5, (0.5, 0.17, 0.60, 'c'))]),
    ('Small capsule', (462, 174), BIG, 'Valve: the logo nearly fills it.', 462, [(184, 69), (120, 45)],
     [('S15', 'S15', 0.5, 0.45, (0.5, 0.48, 0.86, 'c'))]),
    ('Main capsule', (1232, 706), BIG, 'Valve: as the header.', 560, [(616, 353)],
     [('A01', 'A01 wide', 0.5, 0.5, (0.04, 0.16, 0.38, 'l'))]),
    ('Vertical capsule', (748, 896), BIG, 'Valve: as the header.', 280, [],
     [('A01', 'A01', 0.5, 0.5, (0.95, 0.89, 0.62, 'r')), ('A02', 'A02', 0.5, 0.5, (0.5, 0.91, 0.80, 'c')),
      ('T41', 'T41', 0.5, 0.62, (0.5, 0.92, 0.78, 'c'))]),
    ('Library capsule', (600, 900), BIG, 'Valve: as the header ("graphically centered"; Steam shows it at 300x450).', 240, [],
     [('A02', 'A02', 0.5, 0.5, (0.5, 0.91, 0.84, 'c')), ('T41', 'T41', 0.5, 0.5, (0.5, 0.93, 0.84, 'c')),
      ('A22', 'A22 extended', 0.5, 0.5, (0.5, 0.925, 0.70, 'c'))]),
    ('Event cover', (800, 450), SMALL, 'Required for every announcement; artwork + branding, Steam adds the name and icon beside it.', 400, [],
     [('T01', 'T01 wide', 0.5, 0.5, (0.04, 0.09, 0.26, 'l'))]),
    ('Event header', (1920, 622), SMALL, 'Suggested, top of the event page.', 760, [],
     [('T01', 'T01 wide', 0.5, 0.36, (0.03, 0.12, 0.17, 'l'))]),
    ('Page background (optional)', (1438, 810), NONE, 'Behind the store page; Steam tints it.', 480, [],
     [('S15', 'S15', 0.5, 0.5, None)]),
    ('Shortcut + app icon', (256, 256), NONE, 'No words; also 184x184 (JPG) for the app icon.', 256, [(184, 184), (32, 32)],
     [('T01', 'T01 square', 0.5, 0.5, None)]),
]


def page():
    secs = []
    for slot, (W, H), kind, why, dw, checks, cands in SLOTS:
        figs = ''
        for code, src, cx, cy, spec in cands:
            base = cut(Image.open(SRC[src]).convert('RGB'), W, H, cx, cy)
            out = titled(base, kind, spec, scrim=1.4 if slot == 'Small capsule' else 1.0)
            out.save(os.path.join(FILES, f'{slot.split(" (")[0].lower().replace(" ", "-").replace("+", "and")}-{code}-{W}x{H}.png'))
            figs += fig(out, f'{code} {W}x{H}', dw)
            for c in checks:
                figs += fig(out.resize(c, Image.LANCZOS), f'at {c[0]}x{c[1]}', c[0])
        label = {BIG: 'big title', SMALL: 'small title', NONE: 'no words'}[kind]
        secs.append(f'<section><h2>{html.escape(slot)} {W}x{H}: {label}</h2><p class="lead">{html.escape(why)}</p>'
                    f'<div class="row">{figs}</div></section>')
    # library hero + logo
    logo = Image.open(os.path.join(GAME, 'rounds', '99-titles', 'files', 'library-logo-1280.png')).convert('RGBA')
    logo.save(os.path.join(FILES, 'library-logo-1280.png'))
    hero = Image.open(SRC['S15 hero']).convert('RGB')
    hero.save(os.path.join(FILES, 'library-hero-S15-3840x1240.png'))
    v = hero.resize((1920, 620), Image.LANCZOS).convert('RGBA')
    lg = logo.resize((460, round(logo.size[1] * 460 / 1280)), Image.LANCZOS)
    v.alpha_composite(lg, (36, 620 - lg.size[1] - 26))
    secs.append('<section><h2>Library hero 3840x1240 (no words) + library logo</h2><p class="lead">The hero carries no '
                'words; Steam lays the transparent logo over it (placement bottom-left here). S15 cut to the hero\'s shape '
                'is the one hero left standing (A10 and the flat A24 are out); it needs your word.</p><div class="row">'
                + fig(v, 'S15 hero as Steam shows it (1920x620), logo bottom-left', 1100) + '</div></section>')
    # A22 itself
    a22 = Image.open(SRC['A22']).convert('RGB')
    a22.save(os.path.join(FILES, 'A22-final.png'))
    secs.append('<section><h2>A22: the gem at the bottom left, the orbs at the bottom</h2><p class="lead">The gem back on '
                'the frame\'s lower left; the five orbs loose on the knot at the bottom, under him. Its library capsule '
                'above puts the painting on the extended canvas (round 101) so the title sits under the frame.</p>'
                '<div class="row">' + fig(a22, 'A22', 420) + '</div></section>')
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Phylactery Store Set</title><style>
:root {{ color-scheme: dark; --bg:#0d0b0a; --ink:#efe3cc; --dim:#a8987c; --line:#2c241c; --accent:#e0b060; }}
html,body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,"Segoe UI",sans-serif; }}
header, section {{ max-width:1560px; margin:0 auto; padding:16px 16px 6px; }}
h1 {{ margin:10px 0 6px; font-size:24px; }} header p, .lead {{ margin:0 0 10px; color:var(--dim); max-width:1080px; }}
h2 {{ margin:20px 0 4px; font-size:19px; color:var(--accent); }}
.row {{ display:flex; flex-wrap:wrap; gap:12px; align-items:flex-end; }}
figure {{ margin:0; max-width:100%; }} figure img {{ display:block; max-width:100%; height:auto; border:1px solid var(--line); border-radius:4px; }}
figcaption {{ color:var(--dim); font-size:12px; padding:3px 1px; }}
</style></head><body>
<header><h1>Round 102: the set, slot by slot</h1>
<p>Your rule applied: the small title wherever Steam allows it, the big one only where Steam's guidelines require a
readable title. Steam's upload confirmations ask every capsule (header, main, vertical, library, the library header) for a
legible logo filling at least a third, and the small capsule for a logo nearly filling it, so those take the big title;
the event images take the small one; the hero, page background and icons take none. A24 is out. Where a slot still has
more than one candidate (vertical, library), each is shown.</p>
</header>
{''.join(secs)}
</body></html>'''


if __name__ == '__main__':
    s = page()
    open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8').write(s)
    print(os.path.join(HERE, 'index.html'), f'{len(s)/1e6:.2f} MB')
