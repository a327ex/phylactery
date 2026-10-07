"""Round 52's page: petals, orbs, attacks that no longer cut each other off, spawns, the X.
python rounds/52-electrons-spawns/make_page.py"""
import base64, html, io, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
SCR = os.path.join(ROOT, 'scratch', 'r52')
OUT = os.path.join(HERE, 'index.html')

def clip(name):
    b = open(os.path.join(HERE, name + '.mp4'), 'rb').read()
    return '<video controls playsinline loop muted preload="metadata" src="data:video/mp4;base64,%s"></video>' % base64.b64encode(b).decode()
def img(path, cap, crop=None, w=None, nearest=False):
    im = Image.open(os.path.join(SCR, path)).convert('RGB')
    if crop: im = im.crop(crop)
    if w: im = im.resize((w, int(im.height*w/im.width)), Image.NEAREST if nearest else Image.LANCZOS)
    b = io.BytesIO(); im.save(b, 'PNG', optimize=True)
    return '<figure><img src="data:image/png;base64,%s" alt="%s"><figcaption>%s</figcaption></figure>' % (base64.b64encode(b.getvalue()).decode(), html.escape(cap), cap)
def read(name):
    p = os.path.join(SCR, name)
    return open(p, encoding='utf-8').read().strip() if os.path.exists(p) else ''

H = ['''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lich Survivors Electrons</title>
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
figure img, video { display: block; width: 100%; height: auto; background: #000; }
figure img.px { image-rendering: pixelated; }
figcaption { color: var(--dim); font-size: 14px; padding: 4px 8px 6px; }
pre { white-space: pre-wrap; word-break: break-word; background: var(--card); color: var(--dim); font: 13px/1.5 ui-monospace, Consolas, monospace; padding: 10px 12px; margin: 6px 0 10px; }
table { border-collapse: collapse; margin: 6px 0 12px; font-size: 15px; }
td, th { border-bottom: 1px solid var(--rule); padding: 4px 12px 4px 0; text-align: left; }
th { color: var(--dim); font-weight: normal; }
</style></head>
<body><main>
<h1>Lich Survivors &middot; round 52 &middot; electrons, attacks that finish, spawns all round</h1>
<p class="sub">2026-10-06. Anchor build, headless. Your asks on round 51, and the X.</p>''']

H.append('<section><h2>Petals: a tad shorter, straight up</h2><div class="grid"><figure>%s<figcaption>close (2x crop)</figcaption></figure><figure>%s<figcaption>the room camera</figcaption></figure></div>' % (clip('beam_close'), clip('beam')))
H.append('<p>They last 1.1 to 1.8 s (were 1.7 to 2.9), leave the body with much less sideways push and sway less, and rise faster, so they go up nearly straight above the body as it dies. I read &ldquo;more vertical&rdquo; as their path; if you meant the petals themselves standing more upright as they rise, that is a separate change.</p></section>')

H.append('<section><h2>The orbs: electrons round him</h2><div class="grid"><figure>%s<figcaption>the close camera</figcaption></figure><figure>%s<figcaption>the room camera (the game)</figcaption></figure></div>' % (clip('hover'), clip('hover_room')))
H.append('<p>Each orb circles his chest on an orbit of its own: a tilted ellipse (its plane 30 to 70 degrees off level, so the orbits cross like the drawings of an atom), a full turn every 1.6 to 2.6 s, its plane slowly turning about the upright. Every few seconds one of them changes, eased in: it tilts to a new plane, turns the other way, speeds up or slows, or widens, tightens or flattens. They still trail him a little when he moves, and keep off him, the egg and each other.</p></section>')

after = read('conflict_after.txt')
H.append('''<section><h2>No attack cuts off another</h2>
<p>I measured it first: five minutes of normal play on round 51's code. Then I found every way one attack could spoil another, fixed each, and measured again.</p>
<table><tr><th></th><th>round 51</th><th>now</th></tr>
<tr><td>gestures that lost their aim and dropped the arm</td><td>6 of 52</td><td>0</td></tr>
<tr><td>beams cut off mid-flight</td><td>0 in this run (possible)</td><td>0 (can&rsquo;t happen)</td></tr>
<tr><td>rocks thrown that hit nothing</td><td>6 of 26</td><td>0</td></tr></table>
<p>What could go wrong, and what happens now:</p>
<ul>
<li><b>Snakes taken from under an attack.</b> A flying rock, the lens&rsquo;s cut, the leakage and a lift&rsquo;s grab for neighbours could take a snake another attack had chosen. Now they leave any snake another attack holds, and an attack holds its snakes for as long as it is on its way (a rock until it lands, a lens until its cut has passed, a gesture until it strikes). Rocks no longer knock away other rocks&rsquo; targets either.</li>
<li><b>A gesture whose snake is gone anyway</b> (for instance one that reached the egg&rsquo;s last metre, where the egg&rsquo;s safety comes first) turns to the next of its own, or to another snake, instead of dropping the arm.</li>
<li><b>The beam:</b> a new cast used to delete the beams still out; an urgent snake outside the fan used to cut the channel. Now beams already fired always finish from where they were fired, and the hand is simply freed for the next gesture.</li>
<li><b>The lift:</b> a second lift used to forget the snakes the first still held, so the arm could drop while they were in the air. Now it keeps them until they burst.</li>
<li><b>The emergency attacks</b> (when a snake gets near the egg) no longer send a second rock or lens at a snake one is already on: a rock already flying goes fast by itself, and a lens still forming is hurried to fire. A lens whose snake another lens cut first stops where it is instead of burning across empty floor. A rock with nothing left to throw at waits a moment, then is set down.</li>
</ul>''')
stress = read('stress_out.txt')
if stress:
    H.append('<p class="sub">Every forced way (F3), 60 s each with packs and a spread sent in:</p><pre>%s</pre>' % html.escape(stress))
H.append('</section>')

H.append('<section><h2>Spawns: from all round the room</h2>')
H.append(img('spawns_compare.png', 'where the snakes came from in 6 minutes, before (left) and now; the egg ringed; boulders tan; the camera is at the top'))
H.append('<p>The cause: when a wave&rsquo;s spot was inside a boulder, it searched inward and sideways for a clear one, and many waves ended in the same few gaps (23 of 152 snakes in one 15-degree slice, some starting well inside the room). Now every degree round the room gets one spawn point at load, the outermost clear spot on that line with a way to the egg, and each wave&rsquo;s side is drawn evenly among them, never within 40 degrees of the last two waves&rsquo;. The left side has no points: it is walled with boulders; the camera&rsquo;s side is left out as before.</p>')
H.append('<p class="sub">Three minutes of waves, side by side (time:wave@degrees): 0:STREAM6@27 9:ONE@171 13:ONE@235 15:ONE@96 21:PACK4@358 25:PAIR@155 30:ONE@238 33:PAIR@307 36:ONE@174 38:PAIR@358 41:ONE@231 43:ONE@64 48:ONE@4 54:STREAM5@116 61:ONE@174 64:PAIR@344 72:PACK3@29 77:SPREAD3@232 88:ONE@321 90:PAIR@113 99:PACK5@158 111:SPREAD3@22 119:PAIR@68 123:PACK4@151 &hellip;</p></section>')

H.append('<section><h2>The X, normal size</h2><div class="grid">')
H.append(img('viewer_5.png', 'the viewer (the pointer on X)', w=640))
H.append(img('x_zoom.png', 'X under the pointer (2x)', nearest=True))
H.append('</div><p>Back to the normal size, with the lamp glow under the pointer and the same generous click box.</p></section>')

auto = read('auto_run.txt').splitlines()
sweep = (read('sweep_near_out.txt') + '\n' + read('sweep_far_out.txt')).strip()
H.append('<section><h2>Checked</h2><p class="sub">The guarantee with all of this: 3 minutes of normal play (%s; %s) and the sweep, 20 cases of 90 s:</p>' % (html.escape(auto[0] if auto else '?'), html.escape(auto[1] if len(auto) > 1 else '?')))
if sweep: H.append('<pre>%s</pre>' % html.escape(sweep))
H.append('<p class="sub">(held = FIRE LIFT ROCK LEAK BEAM LENS. One step on the way kept emergency lenses off every snake a lens held, and with the lens alone 5 snakes reached the egg: two lenses on one snake near the egg is part of what keeps it safe, so that now happens only within 1.8 m.) LICH_ROOM=1 (the old flow) still gives the same digest run byte for byte as round 48.</p></section>')
H.append('''<section><h2>What to judge</h2><ul>
<li>The petals&rsquo; length and rise; the orbs as electrons (speed, tilt, how often they change).</li>
<li>Whether any attack still looks cut off or wrong when you play: tell me what you saw and I can measure that case.</li>
<li>Whether the snakes now feel like they come from everywhere.</li></ul></section>
</main></body></html>''')
open(OUT, 'w', encoding='utf-8').write(''.join(H))
print('wrote', OUT, os.path.getsize(OUT)//1024, 'KB')
