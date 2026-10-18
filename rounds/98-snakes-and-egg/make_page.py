# make_page.py -- round 98: A24, T01, A34 (three crops) and A22 painted, then fixed to the game: his mask, the snake,
# the egg, the six objects (Phylactery 20, 2026-10-18). Sources in scratch/s20/r98/ (paint/ = staging plates, the
# model passes and their prompts; mask3/ = the game's clean mask re-lit from above; final/ = the finished paintings);
# the finals and the cut slots are copied into files/.
#   python rounds/98-snakes-and-egg/make_page.py   (from lich-survivors/)
import base64, html, io, os, shutil
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
S = os.path.join(GAME, 'scratch', 's20', 'r98')
FILES = os.path.join(HERE, 'files')
os.makedirs(FILES, exist_ok=True)


def cut(im, w, h, cx=0.5, cy=0.5):
    W, H = im.size
    r = w / h
    if W / H > r:
        cw, ch = round(H * r), H
    else:
        cw, ch = W, round(W / r)
    x0 = int(min(max(cx * W - cw / 2, 0), W - cw)); y0 = int(min(max(cy * H - ch / 2, 0), H - ch))
    return im.crop((x0, y0, x0 + cw, y0 + ch)).resize((w, h), Image.LANCZOS)


def uri(im, q=88):
    b = io.BytesIO(); im.convert('RGB').save(b, 'JPEG', quality=q, optimize=True)
    return 'data:image/jpeg;base64,' + base64.b64encode(b.getvalue()).decode()


# (code, title, note, [(final, slot, w, h, cx, cy, display width)])
COMPS = [
    ('A24', 'Dark Side of the Moon: a snake struck by his beam',
     'Staged in the game (one snake sent at him, the beam forced at it, the camera square to finger and snake, his finger at '
     'the frame\'s edge), painted, then the snake made the game\'s: the hood taken off, then the plump long-striped body, '
     'the ridged head and the big black bead eyes.',
     [('final/a24.png', 'Header capsule', 920, 430, 0.56, 0.5, 920), ('final/a24.png', 'Event header', 1920, 622, 0.5, 0.36, 1200)]),
    ('T01', 'The Orphic egg: the snake coiled round the egg',
     'Staged at the ending (the first snake to coil). The square painting already had the game\'s snake (the striped head, '
     'the bead eyes) and the game\'s egg (square flecks); the wide one was given both.',
     [('final/t01_sq.png', 'Shortcut icon', 256, 256, 0.5, 0.5, 256), ('final/t01_sq.png', 'App icon', 184, 184, 0.5, 0.5, 184),
      ('final/t01_sq.png', 'Icon at 32', 32, 32, 0.5, 0.42, 32),
      ('final/t01_wide.png', 'Event cover', 800, 450, 0.5, 0.5, 800)]),
    ('A34', 'He holds up the egg, the snakes climbing him',
     'Staged with his arms raised and the egg in his hands; three crops, three paintings. The painted mask taken out and the '
     'game\'s mask put in front of his face, re-lit from above to match the egg\'s light, with its shadow on the skull; '
     'the snakes made the game\'s; the eggs given the game\'s square flecks.',
     [('final/a34_torso.png', 'Library capsule (head + torso)', 600, 900, 0.5, 0.5, 340),
      ('final/a34_head.png', 'Vertical capsule (head)', 748, 896, 0.5, 0.45, 420),
      ('final/a34_hand.png', 'Main capsule (the whole climb)', 1232, 706, 0.5, 0.5, 760)]),
    ('A22', 'The anatomy plate: the skeleton framed by snakes and his six things',
     'His face is bare here on purpose: the mask is one of the six, in the frame (the burned one, as the game shows it), '
     'with the votive hand, the lodestone, the five orbs, the gem and the lens. Each object was corrected against the '
     'game\'s render of it; the lens is the game\'s own render.',
     [('final/a22.png', 'Library capsule', 600, 900, 0.5, 0.5, 340)]),
]


def page():
    secs = []
    for code, title, note, slots in COMPS:
        figs = ''
        done = set()
        for src, slot, w, h, cx, cy, dw in slots:
            p = os.path.join(S, src)
            if src not in done:
                shutil.copy(p, os.path.join(FILES, f'{code}-final-' + os.path.basename(src)))
                done.add(src)
            im = cut(Image.open(p).convert('RGB'), w, h, cx, cy)
            name = slot.split(' (')[0].lower().replace(' ', '-')
            im.save(os.path.join(FILES, f'{code}-{name}-{w}x{h}.png'))
            shown = im if w >= 120 else im.resize((w * 4, h * 4), Image.NEAREST)
            sw = dw if w >= 120 else w * 4
            cap = f'{slot} {w}x{h}' + (' (shown 4x, nearest)' if w < 120 else '')
            figs += (f'<figure style="max-width:{sw}px"><img src="{uri(shown, 92)}" style="width:{sw}px" '
                     f'alt="{html.escape(slot)}"><figcaption>{html.escape(cap)}</figcaption></figure>')
        secs.append(f'<section><h2>{code}: {html.escape(title)}</h2><p class="lead">{html.escape(note)}</p><div class="row">{figs}</div></section>')
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Phylactery Snakes and Egg</title><style>
:root {{ color-scheme: dark; --bg:#0d0b0a; --ink:#efe3cc; --dim:#a8987c; --line:#2c241c; --accent:#e0b060; }}
html,body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,"Segoe UI",sans-serif; }}
header, section {{ max-width:1560px; margin:0 auto; padding:18px 16px 8px; }}
h1 {{ margin:10px 0 6px; font-size:24px; }} header p, .lead {{ margin:0 0 10px; color:var(--dim); max-width:1080px; }}
h2 {{ margin:24px 0 6px; font-size:20px; color:var(--accent); }}
.row {{ display:flex; flex-wrap:wrap; gap:14px; align-items:flex-end; }}
figure {{ margin:0; max-width:100%; }} figure img {{ display:block; max-width:100%; height:auto; border:1px solid var(--line); border-radius:4px; image-rendering:auto; }}
figcaption {{ color:var(--dim); font-size:12px; padding:3px 1px; }}
</style></head><body>
<header><h1>Round 98: the snake, the egg, the climb, the plate</h1>
<p>Your four remaining picks, staged in the game and painted in P3, then held to the game: his mask is the game's mask
model built clean (rendered, re-lit from above for these, coloured with the painting's porcelain); every snake is the game's
snake (plump, long stripes, ridged head, big black bead eyes); the egg has the game's square flecks; A22's six objects were each
corrected against the game's render of it. Every image here is without words: the title versions come next.</p>
</header>
{''.join(secs)}
</body></html>'''


if __name__ == '__main__':
    s = page()
    open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8').write(s)
    print(os.path.join(HERE, 'index.html'), f'{len(s)/1e6:.1f} MB')
