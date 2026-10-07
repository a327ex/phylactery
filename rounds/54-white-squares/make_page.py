"""Round 54's page: the white squares, found and fixed.
python rounds/54-white-squares/make_page.py"""
import base64, html, io, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
SCR = os.path.join(ROOT, 'scratch', 'r54')
OUT = os.path.join(HERE, 'index.html')

def img(path, cap, crop=None, w=None, bright=1.0):
    im = Image.open(os.path.join(SCR, path)).convert('RGB')
    if crop: im = im.crop(crop)
    if bright != 1.0: im = im.point(lambda v: min(255, int(v*bright)))
    if w: im = im.resize((w, int(im.height*w/im.width)), Image.NEAREST)
    b = io.BytesIO(); im.save(b, 'PNG', optimize=True)
    return '<figure><img class="px" src="data:image/png;base64,%s" alt="%s"><figcaption>%s</figcaption></figure>' % (base64.b64encode(b.getvalue()).decode(), html.escape(cap), cap)
def read(name):
    p = os.path.join(SCR, name)
    return open(p, encoding='utf-8').read().strip() if os.path.exists(p) else ''

H = ['''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lich Survivors Squares</title>
<style>
:root { --bg: #0d0b0a; --fg: #e9dcc4; --dim: #a8987c; --rule: #2a241f; --card: #15120f; --accent: #e0a070; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg: #0d0b0a; } }
:root[data-theme="dark"] { --bg: #0d0b0a; }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.55 Georgia, 'Times New Roman', serif; }
main { max-width: 1100px; margin: 0 auto; padding: 22px 16px 64px; }
h1 { font-size: 23px; margin: 0 0 6px; } h2 { font-size: 18px; margin: 0 0 6px; color: var(--accent); font-weight: normal; }
p { margin: 6px 0 10px; } .sub { color: var(--dim); }
section { border-top: 1px solid var(--rule); padding: 16px 0 6px; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 8px; }
figure { margin: 0; background: var(--card); }
figure img { display: block; width: 100%; height: auto; background: #000; }
figure img.px { image-rendering: pixelated; }
figcaption { color: var(--dim); font-size: 14px; padding: 4px 8px 6px; }
pre { white-space: pre-wrap; word-break: break-word; background: var(--card); color: var(--dim); font: 13px/1.5 ui-monospace, Consolas, monospace; padding: 10px 12px; margin: 6px 0 10px; }
</style></head>
<body><main>
<h1>Lich Survivors &middot; round 54 &middot; the white squares</h1>
<p class="sub">2026-10-07. Anchor build, headless.</p>''']

E = 'evidence/'
H.append('<section><h2>In your runs</h2><div class="grid">')
H.append(img(E + '20261007-070529_00208.png', 'your run 07:05:29, frame 208 (3.5 s in)'))
H.append(img(E + '20261007-073057_01987.png', 'your run 07:30:57, frame 1987 (33 s in): the same place'))
H.append(img(E + '20261007-070529_00826.png', 'your run 07:05:29, frame 826: the left edge'))
H.append('</div><p>I replayed your five runs since this morning headless and checked every frame. The squares are in four of them: 96 by 96 pixels, flat white, 2 to 11 frames each, all out in the dark where snakes start. The one at the top left is in three runs at the same spot, because the waves draw from the same seed every run.</p>')
H.append('<div class="grid">')
for f, cap in (('00289', 'frame 289'), ('00290', 'frame 290: the square'), ('00292', 'frame 292: a snake has started there')):
    H.append(img(E + '20261007-070604_' + f + '.png', 'run 07:06:04, ' + cap + ' (brightened x3)', crop=(100, 0, 280, 150), w=540, bright=3.0))
H.append('</div></section>')

H.append('''<section><h2>What it was</h2>
<p>A snake is 4.4 m long, but a new one started from a trail only 3.99 m long, a mistake in the snakes since they were first built. For its first 0.3 to 0.4 s of crawling, the last bit of its tail had nowhere to lie: those rings were stacked on one point, one above the other. Stacked straight up like that, the tube around them can't be built and their surface gets no direction. The shader turned that into an invalid colour (NaN) on one pixel, about 1 cm of tail tip. The bloom, the glow round bright things, blurs a quarter-size copy of the frame, and the invalid value spread through every step of that blur into a 24 by 24 block, 96 by 96 on screen, which the last pass showed as white. That's why it was square, big, out in the dark with no snake visible there yet, and only a couple of frames long: it lasted while that tiny tip covered a pixel.</p>
<p>Round 53's check couldn't see it: it read the game's own data, which was fine, and never what was drawn. This time the probe read back what was drawn every frame and hid the scene's objects one by one until the bad pixel went away: <code>snakes.body</code>, a snake on its first tick after a wave sent it, with its tail rings stacked.</p>
<p>With that fixed, a longer run with every attack forced in turn found a second way in, the same fault: a snake struck by a thrown rock becomes a hanging rope, and where the rope hung exactly straight down, its rings couldn't be built either.</p>
<p>The fixes: a snake starts from a 4.59 m trail, so its whole body lies on the floor from its first frame, and the body continues straight back past a trail&rsquo;s end instead of stacking. And for any ring that runs exactly vertical, whatever put it there, the tube is now built around a level direction instead, which gives it a surface direction like any other ring. Only drawing changes: where the snakes are and what they do is untouched.</p></section>''')

H.append('<section><h2>Checks</h2><pre>%s</pre></section>' % html.escape(read('checks_summary.txt')))

H.append('<section><h2>Something else I found: the lens in the viewer</h2><div class="grid">')
H.append(img(E + '20261007-055122_05962.png', 'your run 05:51:22, the attack lens in the viewer'))
H.append(img(E + '20261007-055122_05963.png', 'the next frame: its glint blown into a square glow'))
H.append('</div><p>Not the same bug: when the glass catches the light at the right angle, its highlight is so bright that the bloom draws the blur&rsquo;s own square shape round it. It is soft-edged and comes and goes as the lens turns. I left it as it is. Tell me if you want it tamed.</p></section>')

H.append('</main></body></html>')
open(OUT, 'w', encoding='utf-8').write('\n'.join(H))
print(OUT, os.path.getsize(OUT))
