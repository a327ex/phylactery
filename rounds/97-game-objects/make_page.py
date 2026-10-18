# make_page.py -- round 97: round 96's notes applied, with the game's own mask, lens and objects (Phylactery 20,
# 2026-10-18). Sources in scratch/s20/r97/ (a01/, a02/, a10/, paint/, cleanmask/; tools/store_stage.lua, tools/cutout.py,
# tools/paint_in.py, tools/mask/build_clean.mjs); the finals and the cut slots are copied into files/.
#   python rounds/97-game-objects/make_page.py   (from lich-survivors/)
import base64, html, io, os, shutil
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
S = os.path.join(GAME, 'scratch', 's20', 'r97')
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


# (code, title, note, [(final source, slot, w, h, cx, cy, display width)])
COMPS = [
    ('A01', 'Kirei: the vertical capsule\'s pose in both', 'Your "VERY GOOD" pose is the model\'s own (it mirrored and re-posed the render), so the main capsule is the SAME painting extended sideways: its middle is the vertical, pixel for pixel. The mask is the game\'s model (below), turned to his upturned face.',
     [('a01/a01_vertical_avatar.png', 'Vertical capsule', 748, 896, 0.5, 0.5, 420), ('a01/a01_wide_avatar.png', 'Main capsule', 1232, 706, 0.5, 0.5, 820)]),
    ('A02', 'Q: the vertical, the mask further out, the game\'s lens above', 'The painted mask and halo removed (the skull\'s face repainted where the mask hid it), then the game\'s mask in front of his face a little further out than the game holds it, and the game\'s attack lens laid flat higher above him.',
     [('a02/a02_vertical_avatar.png', 'Vertical capsule', 748, 896, 0.5, 0.5, 420), ('a02/a02_vertical_avatar.png', 'Library capsule', 600, 900, 0.5, 0.5, 340)]),
    ('A10', 'KiCk i: him moving, prismatic in the light', 'Staged in motion (sent across the cave, caught mid-glide: body on the diagonal, legs trailing), painted at 4K; his bones break into rainbow sheens where the shaft\'s light reaches them. The painted mask replaced by the game\'s.',
     [('a10/a10_hero_final.png', 'Library hero (no words)', 3840, 1240, 0.5, 0.38, 1500), ('a10/a10_hero_final.png', 'Page background', 1438, 810, 0.5, 0.5, 720)]),
    ('T41', 'Alien: a small egg under a wide cone of light', 'The camera further back and higher: the egg small at the foot of the shaft.',
     [('paint/out/nbpro/t41_tall.png', 'Library capsule', 600, 900, 0.5, 0.5, 340), ('paint/out/nbpro/t41_tall.png', 'Vertical capsule', 748, 896, 0.5, 0.62, 420)]),
    ('S15', 'Vanitas: round 96\'s arrangement, the objects as they are in the game', 'Round 96\'s header kept (where each object lies against the egg), each object then corrected against the game\'s own render of it (the viewer): the bone hand in the blessing gesture, the burned mask with its slit, broken eye and claw gashes, the rusty lodestone, the five glass orbs, the cut gem, the brass-rimmed lens. The painter\'s signature the model added is painted out.',
     [('paint/s15_final.png', 'Library header', 920, 430, 0.5, 0.5, 920)]),
]


def page():
    secs = []
    for code, title, note, slots in COMPS:
        figs = ''
        for src, slot, w, h, cx, cy, dw in slots:
            p = os.path.join(S, src)
            shutil.copy(p, os.path.join(FILES, f'{code}-final-' + os.path.basename(src)))
            im = cut(Image.open(p).convert('RGB'), w, h, cx, cy)
            im.save(os.path.join(FILES, f'{code}-{slot.split(" (")[0].lower().replace(" ", "-")}-{w}x{h}.png'))
            figs += f'<figure style="max-width:{dw}px"><img src="{uri(im)}" style="width:{dw}px" alt="{html.escape(slot)}"><figcaption>{html.escape(slot)} {w}x{h}</figcaption></figure>'
        secs.append(f'<section><h2>{code}: {html.escape(title)}</h2><p class="lead">{html.escape(note)}</p><div class="row">{figs}</div></section>')
    # the mask: the game's burned mask model, built clean three ways
    strip = ''
    for v, lab in [('avatar', 'AVATAR (used): the model without the fire, the gashes or the break; its slits kept'),
                   ('nofire', 'without the fire only: soot and blood off, gashes and the broken eye kept'),
                   ('plain', 'without any mark: no slits either (the shape his in-game shell follows)')]:
        im = Image.open(os.path.join(S, 'cleanmask', f'{v}_front.png'))
        shutil.copy(os.path.join(S, 'cleanmask', f'{v}_front.png'), os.path.join(FILES, f'mask-{v}-front.png'))
        bg = Image.new('RGBA', im.size, (40, 30, 22, 255)); bg.alpha_composite(im); bg.thumbnail((260, 260))
        strip += f'<figure style="max-width:260px"><img src="{uri(bg)}" style="width:{bg.size[0]}px" alt="{v}"><figcaption>{html.escape(lab)}</figcaption></figure>'
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Phylactery Game Objects</title><style>
:root {{ color-scheme: dark; --bg:#0d0b0a; --ink:#efe3cc; --dim:#a8987c; --line:#2c241c; --accent:#e0b060; }}
html,body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,"Segoe UI",sans-serif; }}
header, section {{ max-width:1560px; margin:0 auto; padding:18px 16px 8px; }}
h1 {{ margin:10px 0 6px; font-size:24px; }} header p, .lead {{ margin:0 0 10px; color:var(--dim); max-width:1080px; }}
h2 {{ margin:24px 0 6px; font-size:20px; color:var(--accent); }}
.row {{ display:flex; flex-wrap:wrap; gap:14px; align-items:flex-end; }}
figure {{ margin:0; max-width:100%; }} figure img {{ display:block; max-width:100%; height:auto; border:1px solid var(--line); border-radius:4px; }}
figcaption {{ color:var(--dim); font-size:12px; padding:3px 1px; }}
</style></head><body>
<header><h1>Round 97: the game's own mask, lens and objects</h1>
<p>Round 96's notes applied. What changed in the method: the model still paints each picture (P3's look), but what must be
the game's is the game's. His mask is the burned mask's own model (tools/mask/mask_v2.mjs) built without its fire
(tools/mask/build_clean.mjs), rendered by the game at the angle his painted face needs, coloured with the painting's own
porcelain and put in (tools/paint_in.py); the lens is the game's lens rendered the same way; S15's objects were corrected
one by one against the game's renders of them. A04 is dropped.</p>
<section style="padding:0"><h2>His mask</h2><p class="lead">The burned mask's model, built clean. The compositions use the first.</p><div class="row">{strip}</div></section>
</header>
{''.join(secs)}
</body></html>'''


if __name__ == '__main__':
    s = page()
    open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8').write(s)
    print(os.path.join(HERE, 'index.html'), f'{len(s)/1e6:.1f} MB')
