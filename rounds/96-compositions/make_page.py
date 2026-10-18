# make_page.py -- round 96: the compositions in the chosen finish (P3), each cut to the Steam slots it suits
# (Phylactery 20, 2026-10-18). Sources: scratch/s20/r96/ (prep.py, finish/jobs.json + outputs, hi/ the 4x stagings by
# tools/store_stage.lua); everything shown is copied into files/. Run from lich-survivors/:
#   python rounds/96-compositions/make_page.py
import base64, html, io, json, os, shutil
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(GAME, 'scratch', 's20', 'r96')
FILES = os.path.join(HERE, 'files')
os.makedirs(FILES, exist_ok=True)
ALB = os.path.join(GAME, 'reference', 'identity', 'albums')
SKL = os.path.join(GAME, 'reference', 'identity', 'skeletons')
THM = os.path.join(GAME, 'reference', 'identity', 'themes')

# board code -> its file (the board's codes, as round 94's page numbers them)
REFS = {'A02': os.path.join(ALB, '03-q-queen-bee.jpg'), 'A01': os.path.join(ALB, '02-kirei-queen-bee.jpg'),
        'A10': os.path.join(ALB, '11-kick-i-arca.jpg'), 'A04': os.path.join(ALB, '05-tsuyobi-queen-bee.jpg'),
        'T41': os.path.join(THM, '41-poster-alien.jpg'), 'S15': os.path.join(SKL, '75-champaigne-still-life-skull.jpg')}

# (code, title, staging, [(job key, slot name, w, h)], note)
COMPS = [
    ('A02', 'Q: his head bowed, the mask before his face, the lens as a halo', 'a02',
     [('a02_2x3_fix', 'Library capsule', 600, 900), ('a02_4x5_fix', 'Vertical capsule', 748, 896)],
     'The board\'s real A02 (my first round used A01 by mistake). The halo is his attack lens laid flat above his head.'),
    ('A01', 'Kirei: arched back, the mask before his face (the extra)', 'a01',
     [('a01_16x9_fix', 'Main capsule', 1232, 706), ('a01_4x5_fix', 'Vertical capsule', 748, 896)],
     'Round 95\'s pose, the mask now held in front of his face as the game holds it.'),
    ('A10', 'KiCk i: floating, just standing there, small in the vast cave', 'a10',
     [('a10_21x9', 'Library hero', 3840, 1240), ('a10_16x9', 'Page background', 1438, 810)],
     'The hero takes no words; Steam lays the logo over it. The dashed box is the hero\'s safe area (860x380 at full size).'),
    ('A04', 'Tsuyobi: his bony hand, a power burning at each fingertip', 'a04',
     [('a04_16x9', 'Event cover', 800, 450), ('a04_1x1', 'Shortcut icon / app icon', 256, 256)],
     'The render was turned upright (his arm flung sideways in the game); on a dark field nothing gives the turn away.'),
    ('T41', 'Alien: the egg alone in the dark, lit from above', 't41',
     [('t41_2x3', 'Library capsule', 600, 900), ('t41_4x5', 'Vertical capsule', 748, 896)], ''),
    ('S15', 'Vanitas: the six objects laid on the cave floor, the egg behind', 's15',
     [('s15_21x9', 'Library header', 920, 430), ('s15_16x9', 'Page background', 1438, 810)],
     'The objects as the game drops them, gathered into a row in the light by the egg. (Steam tints the page background blue.)'),
]


def fit(im, w, h):
    W, H = im.size
    r = w / h
    if W / H > r:
        cw, ch = round(H * r), H
    else:
        cw, ch = W, round(W / r)
    x0, y0 = (W - cw) // 2, (H - ch) // 2
    return im.crop((x0, y0, x0 + cw, y0 + ch)).resize((w, h), Image.LANCZOS)


def uri(im, q=88):
    b = io.BytesIO()
    im.convert('RGB').save(b, 'JPEG', quality=q, optimize=True)
    return 'data:image/jpeg;base64,' + base64.b64encode(b.getvalue()).decode()


def page():
    secs = []
    for code, title, stg, slots, note in COMPS:
        ref = Image.open(REFS[code]).convert('RGB') if os.path.exists(REFS[code]) else None
        st = Image.open(os.path.join(SRC, 'hi', f'{stg}.png')).convert('RGB')
        shutil.copy(os.path.join(SRC, 'hi', f'{stg}.png'), os.path.join(FILES, f'{code}-staging-4x.png'))
        top = ''
        if ref:
            ref.thumbnail((420, 420))
            top += f'<figure class="s"><img src="{uri(ref)}" alt="{code}"><figcaption>{code} (the board)</figcaption></figure>'
        st.thumbnail((640, 360))
        top += f'<figure class="s"><img src="{uri(st)}" alt="staging"><figcaption>staged in the game (4x render)</figcaption></figure>'
        outs = ''
        for key, slot, w, h in slots:
            p = os.path.join(SRC, 'finish', 'out', 'nbpro', f'{key}.png')
            if not os.path.exists(p):
                outs += f'<p class="miss">{html.escape(slot)}: not made ({key})</p>'
                continue
            shutil.copy(p, os.path.join(FILES, f'{code}-{key}-generated.png'))
            im = fit(Image.open(p).convert('RGB'), w, h)
            im.save(os.path.join(FILES, f'{code}-{slot.lower().replace(" / ", "-").replace(" ", "-")}-{w}x{h}.png'))
            show = im
            if slot == 'Library hero':
                show = im.copy()
                d = ImageDraw.Draw(show)
                cx, cy = w // 2, h // 2
                for i in range(0, 860, 24):      # the safe area, dashed
                    d.line([(cx - 430 + i, cy - 190), (cx - 430 + min(i + 12, 860), cy - 190)], fill=(224, 176, 96), width=3)
                    d.line([(cx - 430 + i, cy + 190), (cx - 430 + min(i + 12, 860), cy + 190)], fill=(224, 176, 96), width=3)
                for i in range(0, 380, 24):
                    d.line([(cx - 430, cy - 190 + i), (cx - 430, cy - 190 + min(i + 12, 380))], fill=(224, 176, 96), width=3)
                    d.line([(cx + 430, cy - 190 + i), (cx + 430, cy - 190 + min(i + 12, 380))], fill=(224, 176, 96), width=3)
            disp_w = {600: 360, 748: 400, 1232: 820, 3840: 1500, 1438: 720, 800: 560, 256: 256, 920: 700}.get(w, 600)
            extra = ''
            if w == 256:
                small = im.resize((184, 184), Image.LANCZOS)
                extra = f'<img src="{uri(small)}" alt="184" style="width:184px;margin-left:12px">'
            outs += (f'<figure class="o" style="max-width:{disp_w}px"><img src="{uri(show)}" alt="{html.escape(slot)}" style="width:{disp_w}px">{extra}'
                     f'<figcaption>{html.escape(slot)} {w}x{h}</figcaption></figure>')
        secs.append(f'<section id="{code}"><h2>{code}: {html.escape(title)}</h2>'
                    + (f'<p class="lead">{html.escape(note)}</p>' if note else '')
                    + f'<div class="row">{top}</div><div class="row">{outs}</div></section>')
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Phylactery Compositions</title><style>
:root {{ color-scheme: dark; --bg:#0d0b0a; --ink:#efe3cc; --dim:#a8987c; --line:#2c241c; --accent:#e0b060; }}
html,body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,"Segoe UI",sans-serif; }}
header, section {{ max-width:1560px; margin:0 auto; padding:18px 16px 8px; }}
h1 {{ margin:10px 0 6px; font-size:24px; }} header p, .lead {{ margin:0 0 10px; color:var(--dim); max-width:1050px; }}
h2 {{ margin:26px 0 6px; font-size:20px; color:var(--accent); }}
.row {{ display:flex; flex-wrap:wrap; gap:14px; align-items:flex-end; margin:6px 0 10px; }}
figure {{ margin:0; max-width:100%; }} figure img {{ display:inline-block; max-width:100%; height:auto; border:1px solid var(--line); border-radius:4px; vertical-align:bottom; }}
figure.s img {{ max-height:220px; width:auto; opacity:.9; }}
figcaption {{ color:var(--dim); font-size:12px; padding:3px 1px; }} .miss {{ color:#d07060; }}
</style></head><body>
<header><h1>Round 96: the compositions, painted the P3 way</h1>
<p>Your round 95 verdict: P3 (painted after the It Follows cover, dark, warm light), and the mask held in front of his face
as in the game. Each composition was staged in the game itself (tools/store_stage.lua: his pose, his mask, his objects, a
free camera), rendered at 4x, then painted with P3 itself and the It Follows cover as the style references, and cut to the
exact Steam slots it suits. As in round 95 the model drew eyes on his mask every time; a second pass with his real mask as the reference made them blank shells again (A01, A02). No titles yet: that is the next round, with the harder stagings (A22, A24, A34, T01).</p>
<p>What to say: per composition, keep / change / drop, and whether its slots are right.</p></header>
{''.join(secs)}
</body></html>'''


if __name__ == '__main__':
    s = page()
    open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8').write(s)
    print(os.path.join(HERE, 'index.html'), f'{len(s)/1e6:.1f} MB')
