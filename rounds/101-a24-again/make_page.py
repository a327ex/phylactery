# make_page.py -- round 101: A24 again (the cover's layout, painted by the image model in three finishes, two takes
# each) and A22 with the gem at the bottom and the orbs in a row (Phylactery 20, 2026-10-18). Sources in
# scratch/s20/r101/ (a24/ = prompts p_*.txt, the layout plate = round 100's flat drawing, out/nbpro/*.png; a22/).
#   python rounds/101-a24-again/make_page.py   (from lich-survivors/)
import base64, html, io, os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(GAME, 'tools'))
from title import wordmark, lay        # noqa: E402

S = os.path.join(GAME, 'scratch', 's20', 'r101')
FILES = os.path.join(HERE, 'files')
os.makedirs(FILES, exist_ok=True)


def cut(im, w, h, cx=0.5, cy=0.5):
    W, H = im.size
    r = w / h
    cw, ch = (round(H * r), H) if W / H > r else (W, round(W / r))
    x0 = int(min(max(cx * W - cw / 2, 0), W - cw)); y0 = int(min(max(cy * H - ch / 2, 0), H - ch))
    return im.crop((x0, y0, x0 + cw, y0 + ch)).resize((w, h), Image.LANCZOS)


def place(im, text, spec, tracking=0.0):
    W, H = im.size
    xa, cy, wf, an = spec
    wm = wordmark(text, round(W * wf), tracking=tracking)
    w, h = wm.size
    x = {'l': xa * W, 'c': xa * W - w / 2, 'r': xa * W - w}[an]
    return lay(im, wm, at=(round(x), round(cy * H - h / 2)))[0]


def uri(im, w, q=84):
    im = im.convert('RGB')
    if im.size[0] > w * 1.25:
        im = im.resize((round(w * 1.25), round(im.size[1] * w * 1.25 / im.size[0])), Image.LANCZOS)
    b = io.BytesIO(); im.save(b, 'JPEG', quality=q, optimize=True)
    return 'data:image/jpeg;base64,' + base64.b64encode(b.getvalue()).decode()


def fig(im, cap, dw):
    return (f'<figure style="max-width:{dw}px"><img src="{uri(im, dw)}" style="width:{dw}px" alt="{html.escape(cap)}">'
            f'<figcaption>{html.escape(cap)}</figcaption></figure>')


TAKES = [
    ('Airbrush 1', 'airbrush_1', 'A 1970s airbrushed album illustration, the cover\'s own manner.'),
    ('Airbrush 2', 'airbrush_2_st', 'The same finish; a wider spectrum, the break glowing.'),
    ('Oil 1', 'oil_1', 'Painted (P3) on black; the snake curled into a figure of eight.'),
    ('Oil 2', 'oil_2_st', 'Painted (P3) on black; the snake closest to the game\'s (the ridged head, bead eyes, long stripes).'),
    ('Glass 1', 'glass_1', 'A photograph: the snake a glass sculpture shattering where the beam strikes; a big spectrum.'),
    ('Glass 2', 'glass_2', 'The same, quieter, nearest the cover\'s proportions.'),
]
TITLE = (0.04, 0.15, 0.36, 'l')


def page():
    secs = []
    rows = ''
    for name, key, note in TAKES:
        src = Image.open(os.path.join(S, 'a24', 'out', 'nbpro', key + '.png')).convert('RGB')
        src.save(os.path.join(FILES, f'A24-{key}-full.png'))
        base = cut(src, 920, 430, cx=0.454)                  # (keeps the left edge: his finger)
        b = place(base, 'Phylactery', TITLE)
        base.save(os.path.join(FILES, f'A24-{key}-header-none-920x430.png'))
        b.save(os.path.join(FILES, f'A24-{key}-header-steam-920x430.png'))
        rows += (f'<h3>{html.escape(name)}</h3><p class="lead">{html.escape(note)}</p><div class="row">'
                 + fig(base, 'Header capsule, no words', 460) + fig(b, 'Steam-standard', 460)
                 + fig(b.resize((231, 108), Image.LANCZOS), 'at 231x108', 231) + '</div>')
    secs.append('<section><h2>A24, again: the cover\'s layout, painted</h2><p class="lead">My drawn version is gone. '
                'Here the layout is the cover\'s (black ground, his finger at the left edge, the white beam, the snake '
                'breaking at its middle, the spectrum out the far side), given to the image model with the cover, the '
                'game\'s snake and its head as references, in three finishes from graphic to painted to photographic, '
                'two takes each. The oil and airbrush snakes had one more pass for the game snake\'s long stripes (it took '
                'on Oil 2). Whichever you pick then gets the hero and small-capsule versions.</p>' + rows + '</section>')
    a22 = Image.open(os.path.join(S, 'a22', 'a22_fixed.png')).convert('RGB')
    a22.save(os.path.join(FILES, 'A22-final.png'))
    lib = cut(a22, 600, 900)
    # the titles go under the frame: the painting at 86% on a canvas the model extended with its own dark ground
    ext = Image.open(os.path.join(S, 'a22', 'a22_ext_final.png')).convert('RGB')
    ext.save(os.path.join(FILES, 'A22-final-extended.png'))
    libx = cut(ext, 600, 900)
    small = place(libx, 'PHYLACTERY', (0.5, 0.945, 0.40, 'c'), tracking=0.14)
    std = place(libx, 'Phylactery', (0.5, 0.925, 0.70, 'c'))
    for n, im in (('none', lib), ('small', small), ('steam', std)):
        im.save(os.path.join(FILES, f'A22-library-{n}-600x900.png'))
    secs.append('<section><h2>A22: the gem at the bottom, the orbs in a row</h2><p class="lead">The gem moved to the '
                'bottom of the frame, under him, answering the lens at the top; the five orbs strung down the frame\'s '
                'lower left, one after another. With the gem at the bottom the title has no room on the painting, so the '
                'titled versions put the painting on a slightly larger canvas (its own dark ground continued below the '
                'frame) and the title under it.</p><div class="row">' + fig(a22, 'The painting', 420)
                + fig(lib, 'Library capsule, no words', 300) + fig(small, 'Small title (extended canvas)', 300)
                + fig(std, 'Steam-standard (extended canvas)', 300)
                + '</div></section>')
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Phylactery A24 Again</title><style>
:root {{ color-scheme: dark; --bg:#0d0b0a; --ink:#efe3cc; --dim:#a8987c; --line:#2c241c; --accent:#e0b060; }}
html,body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,"Segoe UI",sans-serif; }}
header, section {{ max-width:1560px; margin:0 auto; padding:18px 16px 8px; }}
h1 {{ margin:10px 0 6px; font-size:24px; }} header p, .lead {{ margin:0 0 10px; color:var(--dim); max-width:1080px; }}
h2 {{ margin:26px 0 6px; font-size:20px; color:var(--accent); }} h3 {{ margin:16px 0 2px; font-size:15px; }}
.row {{ display:flex; flex-wrap:wrap; gap:12px; align-items:flex-end; }}
figure {{ margin:0; max-width:100%; }} figure img {{ display:block; max-width:100%; height:auto; border:1px solid var(--line); border-radius:4px; }}
figcaption {{ color:var(--dim); font-size:12px; padding:3px 1px; }}
</style></head><body>
<header><h1>Round 101: A24 again, and A22's gem and orbs</h1></header>
{''.join(secs)}
</body></html>'''


if __name__ == '__main__':
    s = page()
    open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8').write(s)
    print(os.path.join(HERE, 'index.html'), f'{len(s)/1e6:.2f} MB')
