"""make_page.py -- round 39's page (self-contained: every still embedded), from the PNGs beside it."""
import base64, os

HERE = os.path.dirname(os.path.abspath(__file__))
def img(name, alt):
    b = base64.b64encode(open(os.path.join(HERE, name), 'rb').read()).decode()
    return f'<img src="data:image/png;base64,{b}" alt="{alt}">'

AREAS = [
    ('0', 'THE WAKING', 'brown rock (the final room\'s own)',
     'He wakes in a small dark chamber of the final room\'s rock, in a thin crack of daylight. The passage on goes down toward a warm glow.',
     [('z01.png', 'where he wakes, in a crack of light'), ('z03.png', 'the passage down: a second crack of light')]),
    ('1', 'FIRE: THE BURNED MASK', 'basalt, ash, lava in the cracks',
     'A basalt hall: ash underfoot, lava still glowing in some of the cracks, embers rising, basalt columns against the walls. The mask stands upright on a column where whoever wore it burned, leaning on a taller one, looking out at him over a pool of lava.',
     [('z06.png', 'its camera: the altar, the lava pool at its foot'), ('i1_1.png', 'the mask on its column'), ('z08.png', 'the way out, up into the limestone')]),
    ('2', 'LIFT AND BURST: THE HAND', 'limestone cathedral, glow-worms',
     'A tall limestone hall under a ceiling of glow-worms, stalactites and stalagmites, the skeletons of lifted snakes hanging high in the dark. The hand rises on a stalagmite in its gesture, toward them, little stalagmites round it like candles at a shrine.',
     [('z13.png', 'its camera: from low, looking up past the hand'), ('i2_2.png', 'the hand on its stalagmite'), ('z12.png', 'the hall')]),
    ('3', 'ROCK: THE LODESTONE', 'rust-red iron rock, a shaft of sun',
     'Iron rock, red and ochre. The lodestone floats in a column of sun, turning slowly; stones hang in the air round it and drift in and out of the light; pebbles on the floor lie along its field.',
     [('z20.png', 'its camera: the column, the stones hanging'), ('i3_2.png', 'the lodestone among the floating stones'), ('z17.png', 'the climb from the cathedral: a crack of sun')]),
    ('4', 'LEAKAGE: THE ORBS', 'a warped grotto, fungi, a black pool',
     'A grotto the leakage bent: swollen, swirled rock, twisted pillars, pale fungi glowing, a still black pool. The orbs circle over its edge, lit by the fungi\'s glow.',
     [('z27.png', 'its camera: across the pool'), ('i4_3.png', 'the orbs'), ('z29.png', 'the way out')]),
    ('5', 'PRISMATIC BEAM: THE GEM', 'crystals, a shaft of sun',
     'A crystal grotto: clusters on the floor and the walls, great beams across the hall. The gem sits in a crown of crystals in a shaft of sun; colours thrown from it spark on the floor round it.',
     [('z34.png', 'its camera: the gem in the sun'), ('i5_2.png', 'the gem in its crystals'), ('z33.png', 'the hall')]),
    ('6', 'LENS: THE LENS', 'layered sandstone, a shaft of sun',
     'Layered sandstone, pale sand underfoot. The lens lies level on three worn pillars of darker stone in a shaft of sun, focusing it to a point that has burned the sand to black glass; smoke rises off it.',
     [('z41.png', 'its camera: the pillars, the burning point'), ('i6_1.png', 'the lens on its pillars'), ('z40.png', 'the hall')]),
    ('7', 'THE APPROACH', 'brown rock again, the tunnel, the egg',
     'The sandstone gives way to the final room\'s brown rock; the passage meets the room\'s tunnel; at its end, the room\'s light. Stepping into the room\'s camera hands everything to the room, which plays as it always has (the snakes come out of the dark; the ending as before).',
     [('z44.png', 'the approach'), ('tunnel.png', 'the tunnel, toward the room'), ('room.png', 'in the room after the walk (the powers at work)')]),
]

cards = []
for num, name, biome, text, shots in AREAS:
    figs = ''.join(f'<figure>{img(f, cap)}<figcaption>{cap}</figcaption></figure>' for f, cap in shots)
    cards.append(f'<section class="area"><h2><span class="n">{num}</span>{name}</h2><p class="biome">{biome}</p><p>{text}</p><div class="shots">{figs}</div></section>')

html = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lich Survivors Walk</title>
<style>
:root {{ --bg: #0d0b0a; --fg: #e9dcc4; --dim: #a8987c; --rule: #2a241f; --card: #15120f; --accent: #e0a070; }}
@media (prefers-color-scheme: light) {{ :root:not([data-theme="dark"]) {{ --bg: #0d0b0a; --fg: #e9dcc4; --dim: #a8987c; --rule: #2a241f; --card: #15120f; }} }}
:root[data-theme="dark"] {{ --bg: #0d0b0a; }}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--bg); color: var(--fg); font: 15px/1.55 Georgia, 'Times New Roman', serif; }}
main {{ max-width: 1320px; margin: 0 auto; padding: 28px 16px 64px; }}
h1 {{ font-size: 26px; margin: 0 0 6px; letter-spacing: 0.02em; }}
h2 {{ font-size: 18px; margin: 0 0 2px; letter-spacing: 0.04em; }}
h2 .n {{ display: inline-block; width: 1.6em; color: var(--accent); }}
p {{ margin: 6px 0 10px; max-width: 78ch; }}
.sub, .biome {{ color: var(--dim); }}
.biome {{ font-style: italic; margin-top: 0; }}
section {{ border-top: 1px solid var(--rule); padding: 18px 0 8px; }}
.shots {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 10px; }}
figure {{ margin: 0; background: var(--card); }}
figure img {{ display: block; width: 100%; height: auto; image-rendering: pixelated; }}
figcaption {{ color: var(--dim); font-size: 13px; padding: 4px 8px 6px; }}
.map {{ display: grid; grid-template-columns: minmax(0, 420px) minmax(0, 1fr); gap: 20px; align-items: start; }}
.map img {{ width: 100%; image-rendering: pixelated; }}
@media (max-width: 760px) {{ .map {{ grid-template-columns: 1fr; }} }}
table {{ border-collapse: collapse; font-size: 14px; }}
td {{ padding: 3px 14px 3px 0; vertical-align: top; }}
td:first-child {{ color: var(--accent); white-space: nowrap; }}
ul {{ margin: 6px 0 10px; padding-left: 20px; max-width: 80ch; }}
</style></head>
<body><main>
<h1>Lich Survivors &middot; round 39 &middot; the walk</h1>
<p class="sub">2026-10-02. The rest of the game, in the Anchor build: a walk through the cave gathering the six powers as their objects, then the final room.</p>
<p>The game now starts where he wakes. Six chambers, each in its own rock and staged for how its object is found, joined by passages, in an order of light: from none, through lava, glow-worms, a column of sun, bioluminescence, crystals in the sun, a burning glass, to the sun on the egg. Every stretch is watched by a fixed camera, Resident Evil's way: crossing into the next stretch cuts to the next (47 cameras). He walks up to an object, it rises to his hand, the inspect view opens; putting it away, the power is his. At the walk's pace the way from waking to the egg took <b>4 min 26 s</b> in a scripted run that put each inspect view away after a second and a half (452 m of walk + the room's 35 m tunnel), so about five minutes once he stops to look.</p>
<section><h2>Run it</h2>
<table>
<tr><td>run.bat</td><td>starts in the walk</td></tr>
<tr><td>WASD / hold left mouse</td><td>move (held keys keep their direction across a cut, as in the RE remakes)</td></tr>
<tr><td>1 / 2 3 4</td><td>the fixed cameras (the game) / following cameras for looking round</td></tr>
<tr><td>I</td><td>what he carries (the inspect view, A/D through the objects he has)</td></tr>
<tr><td>F1&ndash;F8</td><td>go to an area (with the objects of the areas before it); F9 the final room as it was before the walk</td></tr>
<tr><td>Q</td><td>his pace: a walk, 1.9 m/s (default) / as in the room, 2.6 m/s</td></tr>
<tr><td>B, H</td><td>darkness, hide the text</td></tr>
</table></section>
<section class="map"><figure>{img('map.png', 'the walk from above')}<figcaption>from above: start bottom left; the chambers in colour, the objects pink, each camera a white dot with its line of sight; the tunnel at the top leads to the egg</figcaption></figure>
<div><h2>Taking an object</h2><div class="shots"><figure>{img('take.png', 'he reaches for the mask')}<figcaption>near it, he turns to it and reaches; it rises to his hand</figcaption></figure><figure>{img('inspect.png', 'the inspect view')}<figcaption>then the inspect view (the slot for your text is still there)</figcaption></figure></div></div></section>
{''.join(cards)}
<section><h2>Open</h2>
<ul>
<li>The cave's look is mine for now; your FlyFF Darkon references will reshape it (the generator takes a biome's rock, floor and formations as data).</li>
<li>Your text for each object in the inspect view; sounds.</li>
<li>His pace in the walk (1.9 m/s by default; Q for the room's 2.6).</li>
<li>The final room is untouched: with LICH_ROOM=1 set it starts there exactly as before (same state, digest for digest, as the last commit).</li>
</ul></section>
</main></body></html>
'''
open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8').write(html)
print('index.html', len(html)//1024, 'KB')
