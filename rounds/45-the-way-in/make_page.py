"""Round 45's page: self-contained (every picture embedded). Run once from the project root:
python rounds/45-the-way-in/make_page.py   (reads scratch/r45/, writes rounds/45-the-way-in/index.html)"""
import base64, io, os
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
SRC = os.path.join(ROOT, 'scratch', 'r45')
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'index.html')

def img(name, cap, pick=False, crop=None, scale=1):
    im = Image.open(os.path.join(SRC, name)).convert('RGB')
    if crop: im = im.crop(crop)
    if scale != 1: im = im.resize((int(im.width * scale), int(im.height * scale)), Image.NEAREST)
    b = io.BytesIO(); im.save(b, 'PNG', optimize=True)
    data = base64.b64encode(b.getvalue()).decode()
    return '<figure%s><img src="data:image/png;base64,%s" alt="%s"><figcaption>%s</figcaption></figure>' % (' class="pick"' if pick else '', data, cap.replace('"', ''), cap)

H = []
H.append('''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lich Survivors The Way In</title>
<style>
:root { --bg: #0d0b0a; --fg: #e9dcc4; --dim: #a8987c; --rule: #2a241f; --card: #15120f; --accent: #e0a070; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg: #0d0b0a; } }
:root[data-theme="dark"] { --bg: #0d0b0a; }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 15px/1.55 Georgia, 'Times New Roman', serif; }
main { max-width: 1400px; margin: 0 auto; padding: 28px 16px 64px; }
h1 { font-size: 26px; margin: 0 0 6px; } h2 { font-size: 18px; margin: 0 0 4px; }
h3 { font-size: 15px; margin: 18px 0 2px; color: var(--accent); font-weight: normal; }
p { margin: 6px 0 10px; max-width: 82ch; } .sub { color: var(--dim); }
section { border-top: 1px solid var(--rule); padding: 18px 0 8px; }
.row2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(420px, 1fr)); gap: 10px; }
.row3 { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 10px; }
figure { margin: 0; background: var(--card); border: 2px solid transparent; }
figure.pick { border-color: var(--accent); }
figure img { display: block; width: 100%; height: auto; image-rendering: pixelated; }
figcaption { color: var(--dim); font-size: 13px; padding: 4px 8px 6px; }
table { border-collapse: collapse; font-size: 14px; } td { padding: 3px 14px 3px 0; vertical-align: top; }
td:first-child { color: var(--accent); white-space: nowrap; }
.map { max-width: 300px; }
</style></head>
<body><main>
<h1>Lich Survivors &middot; round 45 &middot; the way in</h1>
<p class="sub">2026-10-04. Anchor build. Bordered = what the game starts with now.</p>
<p>He wakes in a little grotto and walks out down a longer tunnel. The six objects wait along it in order, each on a rock in its own light. Passing one, he stops, turns and reaches, and it rises to his hand. The model viewer then opens on it with its text and ACCEPT ARTIFACT, and once accepted the power is his and its icon fills its slot. The old tunnel then leads into the room, as before. Also here: the inventory's hover without an underline or a name, his own flat white mask, and the orbs' markings.</p>
<section><h2>Run it</h2>
<table><tr><td>run.bat</td><td>starts in the grotto with nothing</td></tr>
<tr><td>Enter / click</td><td>ACCEPT ARTIFACT (the viewer still turns and zooms; there is no way to refuse)</td></tr>
<tr><td>F6</td><td>testing: on to the next object, the ones before it already his</td></tr>
<tr><td>F5</td><td>his mask: WHITE, WHITE MATTE, NONE</td></tr>
<tr><td>F7</td><td>the orbs' markings: ETCHED, INKED, GLOWING, NONE</td></tr>
<tr><td>clicking a slot</td><td>on the way: a look at it; in the room: the question, as round 40</td></tr>
<tr><td>LICH_ROOM=1</td><td>starts in the room exactly as before (its 397-line digest run is byte-identical to the last commit's)</td></tr></table></section>
''')
H.append('<section><h2>The way</h2><p>About 77 m of new tunnel past the old one\'s end, winding, then the grotto. The tube is built the way cave.js built the old one (the same arch and noise; its first ring is the old end ring, so the join is exact), on the same ground he floats on, in the room\'s MIX surface. Objects come in round 39\'s order: the mask nearest the grotto, the lens nearest the room. Each has its own lamp: ember, pale, rust, sea-glass, white, sun. One fixed camera covers the grotto, one each object (ahead of it, looking back at it and the way he comes), one the old tunnel\'s far half, then the room\'s tunnel camera. Held keys keep their direction across every cut.</p>')
H.append('<div class="row2"><figure class="map">' + img('map.png', 'the map: the path, the objects (dots), each camera (blue, toward what it looks at), each lamp\'s reach')[8:] + img('g02_grotto.png', 'THE GROTTO: where he wakes, in the light from a crack in the roof', True) + '</div>')
names = ['the mask', 'the hand', 'the lodestone', 'the orbs', 'the gem', 'the lens']
for i, n in enumerate(names):
    H.append('<h3>%s</h3><div class="row3">%s%s%s</div>' % (n, img('s%d_a_approach.png' % i, 'coming up to it'), img('s%d_b_taking.png' % i, 'it rises to his hand'), img('s%d_c_accept.png' % i, 'the viewer: ACCEPT ARTIFACT')))
H.append('<h3>ACCEPT ARTIFACT, and under the pointer</h3><div class="row2">%s%s</div>' % (img('accept_plain.png', 'waiting (lit: it is the only thing to do)', True, (120, 220, 520, 360), 2), img('accept_hot.png', 'under the pointer: the glow comes up behind it', False, (120, 220, 520, 360), 2)))
H.append('</section>')
H.append('<section><h2>The inventory: hover</h2><p>No underline and no name. The object itself catches the light: its rim goes whiter and a step deeper, its body warms from the lit side, its bright details glow, and the lamp under it comes up. Hovered buttons glow the same way instead of being underlined.</p>')
H.append(img('inv_sheet2.png', 'top: as they rest; middle: the mask under the pointer; bottom: the orbs under the pointer'))
H.append('</section>')
H.append('<section><h2>His mask</h2><p>The avatar\'s mask as round 30 measured it (the round brow, the jaw lines to the pointed chin, the faint nose and cheeks), with no slits, gashes or fire. A smooth white shell on the skull\'s face with the rim rolled back. The cranium shows above it.</p>')
H.append('<div class="row3">%s%s%s</div>' % (img('mask_front.png', 'WHITE, in the tunnel: front', True), img('mask_34.png', 'three quarters'), img('mask_side.png', 'side: it stands off the skull\'s face as a mask does')))
H.append('<div class="row3">%s%s%s</div>' % (img('room_fight.png', 'the room, in the column of sun'), img('room_mask_close.png', 'close, in the sun'), img('room_mask_body.png', 'the whole of him')))
H.append('</section>')
H.append('<section><h2>The orbs\' markings</h2><p>Lines that run all the way round each ball, each ball its own way: two great circles crossing, a spiral from pole to pole, a wavy seam (a tennis ball\'s), three parallel rings, and a wave crossed by a circle. They show on the near face and, through the glass, on the far one, and they turn with the ball. Done in the orbs\' tracer, so the world and the viewer show the same thing.</p>')
H.append('<div class="row2">%s%s%s%s</div>' % (img('orbs_etched.png', 'ETCHED: frosted into the glass, catching the light', True, (160, 0, 480, 250), 2), img('orbs_inked.png', 'INKED: cut and filled dark', False, (160, 0, 480, 250), 2), img('orbs_glowing.png', 'GLOWING: faintly lit from within, sea-glass', False, (160, 0, 480, 250), 2), img('orbs_none.png', 'NONE: as before', False, (160, 0, 480, 250), 2)))
H.append('</section>')
H.append('''<section><h2>Checked</h2><p>Headless (agent instance): from the grotto past all six (each taken, viewed, accepted; its slot filled), into the room, a 10 s fight nothing got through, every power removed, won at 97% covered with all six lying beside him. LICH_ROOM=1's digest run is byte-identical to the last commit's. Static check clean.</p></section>
<section><h2>Not yet</h2><p>The burned mask's redo (round 46: references first). The objects' text (the [ YOUR TEXT ] slot waits on the lore). The cameras are placed by rule, not by eye. The objects read small on their rocks. The grotto's crack is above the grotto camera's frame (you see its light and dust, not the crack). His GI probe light outside the room is the room's nearest edge. The way between lamps is dark on purpose, but how dark is yours to say.</p></section>
</main></body></html>''')
open(OUT, 'w', encoding='utf-8').write(''.join(H))
print('wrote', OUT, os.path.getsize(OUT) // 1024, 'KB')
