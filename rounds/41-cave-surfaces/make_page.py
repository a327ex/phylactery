"""make_page.py -- round 41's page (self-contained: every still embedded), from the PNGs beside it."""
import base64, os

HERE = os.path.dirname(os.path.abspath(__file__))
def img(name, alt):
    b = base64.b64encode(open(os.path.join(HERE, name), 'rb').read()).decode()
    return f'<img src="data:image/png;base64,{b}" alt="{alt}">'

SURF = ['AS EXPORTED', 'SLABS', 'QUIET']
LIGHT = ['AS BUILT', 'LOW', 'DIM', 'DARK']
DEFAULT = (1, 2)

def fig(name, cap, mark=False):
    cls = ' class="pick"' if mark else ''
    return f'<figure{cls}>{img(name, cap)}<figcaption>{cap}</figcaption></figure>'

before_after = (fig('walk_in_before.png', 'before: AS EXPORTED surface, AS BUILT tunnel light')
                + fig('walk_in_default.png', 'now (the default): SLABS, DIM', True))
grid = ''
for l, ln in enumerate(LIGHT):
    row = ''.join(fig(f't_s{s}_l{l}.png', f'{sn} &middot; {ln}', (s, l) == DEFAULT) for s, sn in enumerate(SURF))
    grid += f'<h3>tunnel light: {ln}</h3><div class="row3">{row}</div>'
room = ''.join(fig(f'r_s{s}.png', sn, s == DEFAULT[0]) for s, sn in enumerate(SURF))
tex = ''.join(fig(f'cave_{k}_{v}.png', f'{k} &middot; {lab}') for k in ('rock', 'floor')
              for v, lab in (('now', 'as exported'), ('slabs', 'SLABS'), ('quiet', 'QUIET')))

html = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lich Survivors Surfaces</title>
<style>
:root {{ --bg: #0d0b0a; --fg: #e9dcc4; --dim: #a8987c; --rule: #2a241f; --card: #15120f; --accent: #e0a070; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --bg: #0d0b0a; }} }}
:root[data-theme="dark"] {{ --bg: #0d0b0a; }}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--bg); color: var(--fg); font: 15px/1.55 Georgia, 'Times New Roman', serif; }}
main {{ max-width: 1400px; margin: 0 auto; padding: 28px 16px 64px; }}
h1 {{ font-size: 26px; margin: 0 0 6px; }}
h2 {{ font-size: 18px; margin: 0 0 4px; }}
h3 {{ font-size: 15px; margin: 14px 0 6px; color: var(--accent); font-weight: normal; }}
p, li {{ max-width: 80ch; }}
p {{ margin: 6px 0 10px; }}
.sub {{ color: var(--dim); }}
section {{ border-top: 1px solid var(--rule); padding: 18px 0 8px; }}
.row2 {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(420px, 1fr)); gap: 10px; }}
.row3 {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 10px; }}
figure {{ margin: 0; background: var(--card); border: 2px solid transparent; }}
figure.pick {{ border-color: var(--accent); }}
figure img {{ display: block; width: 100%; height: auto; image-rendering: pixelated; }}
figcaption {{ color: var(--dim); font-size: 13px; padding: 4px 8px 6px; }}
table {{ border-collapse: collapse; font-size: 14px; }}
td {{ padding: 3px 14px 3px 0; vertical-align: top; }}
td:first-child {{ color: var(--accent); white-space: nowrap; }}
</style></head>
<body><main>
<h1>Lich Survivors &middot; round 41 &middot; the cave without seams or noise; the first view's light</h1>
<p class="sub">2026-10-03. Anchor build only. Bordered = the game's default now.</p>
<p>The cave's textures had five far-apart tones and a dark crack round every patch, so every wall read as a mosaic. On the curved walls, each triangle chose its own projection, so the pattern also jumped at triangle edges. The first view was lit by a lamp at the tunnel mouth that reached 30 m into the room.</p>
<section><h2>The first view, before and now</h2><div class="row2">{before_after}</div></section>
<section><h2>Run it</h2>
<table>
<tr><td>run.bat</td><td>starts in the tunnel with SLABS and DIM</td></tr>
<tr><td>V</td><td>cave surface: AS EXPORTED / SLABS / QUIET (anywhere, live)</td></tr>
<tr><td>C</td><td>tunnel light: AS BUILT / LOW / DIM / DARK (in the tunnel, before the room's camera cuts in; the room's own lights are untouched)</td></tr>
<tr><td>B</td><td>darkness, as before (the bounce light's level)</td></tr>
</table></section>
<section><h2>What changed</h2>
<ul>
<li><b>Textures.</b> New rock and floor textures, 4 m across instead of 2 (still 32 texels per metre), painted the same way. The tones are close together and there's no dark crack round each patch. SLABS keeps the cover's broad palette-knife slabs, about 0.7 m each, one flat tone apiece. QUIET is nearly one tone, with broad mottling and a few pits, and leaves the form to the faceted rock and the light.</li>
<li><b>Seams.</b> The walls, dome, tunnel and floor now take their texture from one continuous mapping each, wrapped round the cave's axis and up its profile. Measured on the shared vertices of neighbouring triangles: the walls went from 38% mismatched to 0%, the tunnel from 14% to 2.5% (its far end), the floor to 0%. The dome keeps two rings where the mapping changes, high up (about 10 m and 15 m), instead of a seam at every triangle. The loose rocks keep their own projections, because their faces meet at real edges.</li>
<li><b>The tunnel's light.</b> AS BUILT lit the room's whole south half. LOW reaches just past the mouth. DIM keeps the light inside the tunnel, round him as he comes. DARK leaves only the room's light and his glow. The room's light is unchanged.</li>
</ul></section>
<section><h2>The first view: every surface &times; every tunnel light</h2>{grid}</section>
<section><h2>The room's camera (its light unchanged)</h2><div class="row3">{room}</div></section>
<section><h2>The textures, at the same scale (8 m square)</h2><div class="row3">{tex}</div></section>
<section><h2>What this round decides, and what it leaves</h2>
<p>Yours: which surface (or neither), and how much light the tunnel throws. Not settled yet: the two rings on the dome, the thin rim of rock round the tunnel's mouth, and the room's own light (unchanged here). If a surface is close but not right, say which way it should move: more texture, less, bigger patches, warmer or cooler.</p></section>
</main></body></html>
'''
open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8').write(html)
print('index.html', len(html)//1024, 'KB')
