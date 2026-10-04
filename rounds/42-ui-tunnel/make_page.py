"""make_page.py -- round 42's page (self-contained: every still embedded), from the PNGs beside it."""
import base64, os

HERE = os.path.dirname(os.path.abspath(__file__))
def img(name, alt):
    b = base64.b64encode(open(os.path.join(HERE, name), 'rb').read()).decode()
    return f'<img src="data:image/png;base64,{b}" alt="{alt}">'
def fig(name, cap, cls=''):
    return f'<figure class="{cls}">{img(name, cap)}<figcaption>{cap}</figcaption></figure>'

BUNDLES = [
    ('CURRENT', 'the model renders as before, smaller (24 px, was 34); the old font; dark boxes'),
    ('RELIC', 'pixel sprites of the objects in the cave\'s palette, lit from the shaft\'s side, dark outline; Silkscreen (small capitals); carved stone plates'),
    ('MANUSCRIPT', 'engraved: a cream outline and hatching; Jacquard (blackletter) for names, Jacquarda Bastarda (a calligraphic hand) for the rest; corner brackets'),
    ('EMBER', 'dark silhouettes with a warm rim, each against a lamp-like glow; Pixelify Sans for names, Tiny5 for the rest; no frame'),
    ('GLYPH', 'a drawn symbol for each power; Tiny5; no frame (a mark under the one hovered)'),
]
bundles = ''
for k, (name, desc) in enumerate(BUNDLES, 1):
    pick = ' pick' if name == 'RELIC' else ''
    bundles += f'<h3>F1 {k}: {name}</h3><p class="sub">{desc}</p><div class="row2">' + \
        fig(f'b{k}_tunnel.png', f'{name}: the first view, the hand hovered', pick) + fig(f'b{k}_question.png', f'{name}: the question', pick) + '</div>'

html = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lich Survivors Interface</title>
<style>
:root {{ --bg: #0d0b0a; --fg: #e9dcc4; --dim: #a8987c; --rule: #2a241f; --card: #15120f; --accent: #e0a070; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --bg: #0d0b0a; }} }}
:root[data-theme="dark"] {{ --bg: #0d0b0a; }}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--bg); color: var(--fg); font: 15px/1.55 Georgia, 'Times New Roman', serif; }}
main {{ max-width: 1400px; margin: 0 auto; padding: 28px 16px 64px; }}
h1 {{ font-size: 26px; margin: 0 0 6px; }}
h2 {{ font-size: 18px; margin: 0 0 4px; }}
h3 {{ font-size: 15px; margin: 18px 0 2px; color: var(--accent); font-weight: normal; }}
p, li {{ max-width: 82ch; }}
p {{ margin: 6px 0 10px; }}
.sub {{ color: var(--dim); }}
section {{ border-top: 1px solid var(--rule); padding: 18px 0 8px; }}
.row2 {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(420px, 1fr)); gap: 10px; }}
.row3 {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 10px; }}
figure {{ margin: 0; background: var(--card); border: 2px solid transparent; }}
figure.pick {{ border-color: var(--accent); }}
figure img {{ display: block; width: 100%; height: auto; image-rendering: pixelated; }}
figcaption {{ color: var(--dim); font-size: 13px; padding: 4px 8px 6px; }}
.wide {{ overflow-x: auto; }}
.wide img {{ max-width: none; width: 1600px; }}
table {{ border-collapse: collapse; font-size: 14px; }}
td {{ padding: 3px 14px 3px 0; vertical-align: top; }}
td:first-child {{ color: var(--accent); white-space: nowrap; }}
</style></head>
<body><main>
<h1>Lich Survivors &middot; round 42 &middot; the interface, the tunnel's mouth, the surface</h1>
<p class="sub">2026-10-03. Anchor build. Bordered = what the game starts with now.</p>

<section><h2>Run it</h2>
<table>
<tr><td>run.bat</td><td>starts on RELIC with the MIX surface</td></tr>
<tr><td>F1</td><td>a whole direction: CURRENT / RELIC / MANUSCRIPT / EMBER / GLYPH</td></tr>
<tr><td>F2 F3 F4</td><td>one part of it on its own: the icons, the fonts, the frames (mix them freely; the testing text names what is on)</td></tr>
<tr><td>V</td><td>surface: AS EXPORTED / SLABS / MIX / QUIET</td></tr>
<tr><td>H</td><td>hides the testing text (the inventory stays)</td></tr>
</table></section>

<section><h2>The interface: five directions</h2>
<p>The inventory is smaller: 24 px icons (was 34). The icons are no longer the model rendered small. They are pictures made from it: the objects drawn by tools/icons.py from clean cut-outs of the model viewer's renders, except GLYPH, which is drawn by hand. The fonts are open pixel fonts drawn at the sizes where they sit on whole pixels; the mixed-case ones get names in Title Case and the rest as sentences. Each direction is a set; F2 to F4 take them apart.</p>
{bundles}
<h3>The six slots and the question, side by side (3x)</h3>
<figure>{img('crops_b.png', 'inventory and question crops')}<figcaption>CURRENT, RELIC, MANUSCRIPT, EMBER, GLYPH: the slots with the hand hovered, and the question</figcaption></figure>
</section>

<section><h2>The icons in every frame (F2 x F4)</h2>
<div class="wide"><figure>{img('grid_icons_frames.png', 'icon styles by frame styles')}<figcaption>rows: RENDER, RELIC, ENGRAVED, EMBER, GLYPH; columns: BOXED, BARE, PLATE, BRACKETS, LAMP (2x)</figcaption></figure></div>
<figure>{img('styles_sheet.png', 'the icon styles')}<figcaption>the icons themselves at 4x: render, relic, engraved, ember, glyph (mask, hand, lodestone, orbs, gem, lens)</figcaption></figure>
</section>

<section><h2>The fonts (F3), in the question</h2>
<figure>{img('grid_fonts.png', 'font pairs')}<figcaption>CLASSIC (as before), SILKSCREEN, MANUSCRIPT (Jacquard + Jacquarda Bastarda), PIXELIFY + TINY, TINY (2x; all on the PLATE frame)</figcaption></figure>
</section>

<section><h2>The tunnel's mouth</h2>
<p>The tunnel tube started 4.5 m inside the room, so its first rings stood free in front of the wall: the thin arch in your picture. It now starts behind the wall, and a collar of new faces joins the wall's opening to it, edge to edge. Its walls also ran 2 to 3 m below the floor, and the floor's ragged edges showed that trough as the bowl at the bottom. They now end just under the floor. The floor itself is unchanged, because the game walks on it.</p>
<div class="row3">
{fig('mouth_before_game.png', 'before: the first view (round 41)')}
{fig('b2_tunnel.png', 'now: the first view')}
{fig('mouth_collar.png', 'the collar: the opening (red) joined to the tube (blue)')}
{fig('mouth_before_side.png', 'before: from the side, the free arch')}
{fig('mouth_after_side.png', 'now: the same camera')}
{fig('mouth_after_side2.png', 'now: from the other side')}
{fig('mouth_floor_before.png', 'the arch gone, the trough still showing (an intermediate step)')}
{fig('mouth_after_floor.png', 'now: the floor runs into the tunnel')}
{fig('mouth_after_inside.png', 'now: from inside the tunnel, looking out')}
</div></section>

<section><h2>The surface: MIX</h2>
<p>Between SLABS and QUIET: the slabs' patches with their tones half as far apart, over QUIET's broad mottling. It is the default now; V still cycles all four.</p>
<figure>{img('surfaces.png', 'slabs, mix, quiet')}<figcaption>rock (top) and floor (bottom): SLABS, MIX, QUIET, 8 m square</figcaption></figure>
</section>

<section><h2>What this round decides, and what is unfinished</h2>
<p>Yours: a direction, or a mix of parts (say which icons, which font, which frame), and whether any of them should move further, more drawn or more abstract. Unfinished: the icons are a first pass generated in code. The glyph hand is weak, and the lens is shown as a disc, since thin glass reads as nothing at 24 px. Jacquarda Bastarda's square brackets come out turned the other way (its own design). Whichever you choose gets finished properly, the end message included.</p>
</section>
</main></body></html>
'''
open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8', newline='\n').write(html)
print('index.html', len(html) // 1024, 'KB')
