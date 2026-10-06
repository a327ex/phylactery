"""Round 51's page: the ball, the petals, the viewer, the orbs (clips and pictures embedded).
python rounds/51-ball-petals-orbs/make_page.py"""
import base64, html, io, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
SCR = os.path.join(ROOT, 'scratch', 'r51')
OUT = os.path.join(HERE, 'index.html')

def clip(name):
    b = open(os.path.join(HERE, name + '.mp4'), 'rb').read()
    return '<video controls playsinline loop muted preload="metadata" src="data:video/mp4;base64,%s"></video>' % base64.b64encode(b).decode()
def img(path, cap, crop=None, w=None):
    im = Image.open(os.path.join(SCR, path)).convert('RGB')
    if crop: im = im.crop(crop)
    if w: im = im.resize((w, int(im.height*w/im.width)), Image.LANCZOS)
    b = io.BytesIO(); im.save(b, 'PNG', optimize=True)
    return '<figure><img src="data:image/png;base64,%s" alt="%s"><figcaption>%s</figcaption></figure>' % (base64.b64encode(b.getvalue()).decode(), html.escape(cap), cap)
def read(name):
    p = os.path.join(SCR, name)
    return open(p, encoding='utf-8').read().strip() if os.path.exists(p) else ''

H = ['''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lich Survivors Ball</title>
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
figcaption { color: var(--dim); font-size: 14px; padding: 4px 8px 6px; }
pre { white-space: pre-wrap; word-break: break-word; background: var(--card); color: var(--dim); font: 13px/1.5 ui-monospace, Consolas, monospace; padding: 10px 12px; margin: 6px 0 10px; }
ul { margin: 6px 0 10px; padding-left: 22px; } li { margin: 3px 0; }
</style></head>
<body><main>
<h1>Lich Survivors &middot; round 51 &middot; the ball, glass petals, the viewer, the orbs</h1>
<p class="sub">2026-10-06. Anchor build, headless. Your five asks from round 50b.</p>''']

H.append('<section><h2>Lifted together, they curl into a ball</h2><div class="grid"><figure>%s<figcaption>close (2x crop of the room camera)</figcaption></figure><figure>%s<figcaption>the room camera</figcaption></figure></div>' % (clip('lift_close'), clip('lift')))
H.append('<p>When three or more are lifted together, each body now winds round its own tilted band on one small ball (about 60 cm across), like yarn: the middle of each body reaches the ball first and the rest is reeled in after it, the heads stand a little off the ball, and the four bands cross at even angles so it reads as a ball, not a ring. The ball turns, tightens a little and writhes, then they all burst at once on his fist, as before. The ball forms in the air in front of him, out of the egg&rsquo;s way.</p></section>')

H.append('<section><h2>The beam&rsquo;s death: glass petals rising</h2><div class="grid"><figure>%s<figcaption>close (2x crop)</figcaption></figure><figure>%s<figcaption>the room camera (a revolver volley)</figcaption></figure></div>' % (clip('beam_close'), clip('beam')))
H.append('<p>The death is as it was (the snake fills with the light and bursts into warped streaks and a little gore), and now thin cupped petals of glass rise from the body as it goes: a few while the light fills it, about fourteen as it bursts. They float up like something light in warm air, sway and tumble, and fade as they climb. Each is pale and faint most of the time and flares in its colours when its face turns to the light, the colour running across the spectrum as it turns. They are 13 to 20 cm long, about the snake&rsquo;s thickness: smaller ones were one or two pixels at the room camera and read as the glitter you moved away from in rounds 25 and 26.</p></section>')

H.append('<section><h2>The viewer: the title by the object, THROW where it was, X to close</h2><div class="grid">')
H.append(img('viewer_0.png', 'BURNED MASK', w=640))
H.append(img('viewer_3.png', 'PSYONIAN ORBS', w=640))
H.append(img('viewer_5.png', 'ATTACK LENS, the pointer on X (it glows)', w=640))
H.append(img('viewer_1.png', 'THE HAND', w=640))
H.append('</div><p>The name now sits just under the object as it shows on screen (it follows as the object turns, eased so it doesn&rsquo;t jump, and never runs into THROW). THROW stays at the bottom. X sits at the top right, at double size, glowing under the pointer like THROW; clicking it closes the viewer without throwing anything (Esc still does too).</p></section>')

H.append('<section><h2>The orbs hover round him</h2><div class="grid"><figure>%s<figcaption>hovering (the close camera, following him)</figcaption></figure><figure>%s<figcaption>THROW, then walking to them: they rise to him again</figcaption></figure></div>' % (clip('hover'), clip('throw')))
H.append('<p>While the leakage is his, its five orbs hover round him, each on its own: its angle round him drifts, slows, stops and turns back, its distance and height breathe, and now and then it swerves. They hang on soft springs, so they trail him when he moves, and they keep off him, the egg, the floor and each other. THROW pushes each the way he is facing (each a little differently), and they fly, fall, bounce and roll; like any thrown object they stay inside the room camera&rsquo;s frame. Walk back to them and they rise to him and hover again, and the power is his again.</p></section>')

auto = read('auto_run.txt').splitlines()
sweep = (read('sweep_near_out.txt') + '\n' + read('sweep_far_out.txt')).strip()
H.append('<section><h2>Checked</h2><p class="sub">Headless: the ball, the petals and the orbs filmed above; the viewer for every object, X and THROW. The guarantee with all of this in: 3 minutes of normal play (%s, %s) and the sweep, 20 cases of 90 s:</p>' % (html.escape(auto[0] if auto else '?'), html.escape(auto[1] if len(auto) > 1 else '?')))
if sweep: H.append('<pre>%s</pre>' % html.escape(sweep))
H.append('<p class="sub">LICH_ROOM=1 (the old flow) still gives the same digest run byte for byte as round 48: the ball, the petals and the hovering orbs are on only in the game&rsquo;s flow.</p></section>')
H.append('''<section><h2>What to judge</h2><ul>
<li>The ball: does it read as curled up? (Size, how tight, how long it holds before bursting.)</li>
<li>The petals: glass petals rising, or still too much like particles? Size and how many are the main dials.</li>
<li>The viewer&rsquo;s title placement and the X.</li>
<li>The orbs: how they hover (how far out, how restless) and how hard THROW pushes them.</li>
</ul></section>
</main></body></html>''')
open(OUT, 'w', encoding='utf-8').write(''.join(H))
print('wrote', OUT, os.path.getsize(OUT)//1024, 'KB')
