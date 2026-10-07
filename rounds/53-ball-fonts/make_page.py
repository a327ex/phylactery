"""Round 53's page: the white squares found, the orbs, the ball, the font audition.
python rounds/53-ball-fonts/make_page.py"""
import base64, html, io, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
SCR = os.path.join(ROOT, 'scratch', 'r53')
OUT = os.path.join(HERE, 'index.html')

def clip(name):
    b = open(os.path.join(HERE, name + '.mp4'), 'rb').read()
    return '<video controls playsinline loop muted preload="metadata" src="data:video/mp4;base64,%s"></video>' % base64.b64encode(b).decode()
def img(path, cap, crop=None, w=None, nearest=False, cls=''):
    im = Image.open(os.path.join(SCR, path)).convert('RGB')
    if crop: im = im.crop(crop)
    if w: im = im.resize((w, int(im.height*w/im.width)), Image.NEAREST if nearest else Image.LANCZOS)
    b = io.BytesIO(); im.save(b, 'PNG', optimize=True)
    return '<figure><img class="%s" src="data:image/png;base64,%s" alt="%s"><figcaption>%s</figcaption></figure>' % (cls, base64.b64encode(b.getvalue()).decode(), html.escape(cap), cap)
def read(name):
    p = os.path.join(SCR, name)
    return open(p, encoding='utf-8').read().strip() if os.path.exists(p) else ''

H = ['''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lich Survivors Fonts</title>
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
ol, ul { margin: 6px 0 10px; padding-left: 22px; } li { margin: 3px 0; }
</style></head>
<body><main>
<h1>Lich Survivors &middot; round 53 &middot; the white squares, the ball, the orbs, fonts</h1>
<p class="sub">2026-10-07. Anchor build, headless.</p>''']

H.append('<section><h2>The white squares: found in your run</h2><div class="grid">')
H.append(img('squares_before.png', 'your run this morning (05:51), replayed: the white blocks', nearest=True, cls='px'))
H.append(img('squares_after.png', 'now: a beamed snake dying, its petals in their tints', nearest=True, cls='px'))
H.append('</div><p>I replayed your recording from this morning (129 s), saved every second frame and searched them for small hard-edged white blocks. They are the glass petals from round 51: when a petal turned its face to the light, its flare ran toward white and clipped, a white block a few pixels across for a few frames, wherever the petals drifted. Now the flare stays in the petal&rsquo;s own tint and is held under the clip. A 40 s run of beam deaths afterwards has no white blocks left except the beam&rsquo;s own bite flashes (white since round 18). A scan of every particle buffer in the scene over 5 minutes found no broken values either. If you still see a square, tell me where and during what, and I&rsquo;ll look at that recording.</p></section>')

H.append('<section><h2>The orbs: one size, wider orbits</h2><figure>%s<figcaption>the close camera (a lift&rsquo;s ball happens to form in it too)</figcaption></figure>' % clip('hover'))
H.append('<p>All five are now about the size of the smaller ones (2.8 to 3.2 cm in the model, were 2.8 to 5), in the world and in the viewer, and they orbit 0.85 to 1.15 m from him (were 0.5 to 0.72).</p></section>')

H.append('<section><h2>The lift&rsquo;s ball: irregular, floating, on springs</h2><div class="grid"><figure>%s<figcaption>close (2x crop)</figcaption></figure><figure>%s<figcaption>the room camera</figcaption></figure></div>' % (clip('lift_close'), clip('lift')))
H.append('<p>It is no longer a sphere: it has lumps and squashes and stretches slowly. Its centre bobs and drifts sideways on uneven waves. Each piece of each body follows its place on a spring of its own instead of an eased blend: the middles firm, the ends looser, so the bodies whip in from where they were lifted, overshoot a little and settle into the ball. The burst is as before.</p></section>')

H.append('''<section><h2>Fonts: the audition (F6 in the game)</h2>
<p>Your guess fits what I measured. Since round 49 the icons are drawn at the window&rsquo;s resolution, one screen pixel per icon pixel, but FACETED is drawn at the game&rsquo;s, two screen pixels per font pixel, so the letters are twice as coarse as the icons beside them. Every new candidate here is drawn at the icons&rsquo; size (one screen pixel per glyph pixel), at about FACETED&rsquo;s height on screen, with the same ember fall and outline:</p>
<ol>
<li><b>FACETED</b>: as now (the baseline).</li>
<li><b>FACETED FINE</b>: the same letters at twice the detail; their cuts finer, strokes still two pixels thick.</li>
<li><b>FACETED THIN</b>: the same letters with one-pixel strokes, the icons&rsquo; line weight.</li>
<li><b>JACQUARD</b>: Jacquard 24, a pixel blackletter (grimoire; hard to read).</li>
<li><b>DOTGOTHIC</b>: DotGothic16, a plain, light pixel face.</li>
<li><b>PIXELIFY</b>: Pixelify Sans, a bold rounded pixel face.</li>
<li><b>FELL</b>: IM Fell English SC, smooth, no pixels at all (round 44&rsquo;s, as a control).</li>
</ol>''')
H.append(img('fonts_sheet.png', 'each font, top to bottom in the order above: the title, THROW, X (2x of the window&rsquo;s pixels)', nearest=True, cls='px'))
H.append('<div class="grid">')
labels = [('facet', 'FACETED (now)'), ('facet_fine', 'FACETED FINE'), ('facet_thin', 'FACETED THIN'), ('jacquard', 'JACQUARD'), ('dotgothic', 'DOTGOTHIC'), ('pixelify', 'PIXELIFY'), ('fell', 'FELL (smooth)')]
for n, lab in labels:
    H.append(img('fonts/%s_3.png' % n, lab, w=640))
H.append('</div><p>In the game: F6 cycles them (the testing text, H, shows which), and the viewer (click an object) shows the title, THROW and X in it. The game starts on FACETED as before. Your pick decides the font; I&rsquo;d then remove the others again.</p></section>')

auto = read('auto_run.txt').splitlines()
sweep = (read('sweep_near_out.txt') + '\n' + read('sweep_far_out.txt')).strip()
H.append('<section><h2>Checked</h2><p class="sub">The fonts render in the game for every object&rsquo;s viewer; the ball, the orbs and the petals filmed above. The guarantee unchanged (nothing here touches who attacks what): 3 minutes of normal play (%s; %s) and the sweep:</p>' % (html.escape(auto[0] if auto else '?'), html.escape(auto[1] if len(auto) > 1 else '?')))
if sweep: H.append('<pre>%s</pre>' % html.escape(sweep))
H.append('<p class="sub">While checking I also tightened the lens: a single lens&rsquo;s cut now keeps turning to pass through its snake until it cuts it, and a lens&rsquo;s cut passes by snakes another lens is on its way to. Every forced way (F3) with packs: no aborted aim, no beam cut, no rock hitting nothing, and one lens out of about 30 that cut nothing (a lift took its snake within 2 m of the egg, the last-resort overlap that keeps the egg safe). LICH_ROOM=1 (the old flow) still gives the same digest run as round 48.</p></section>')
H.append('''<section><h2>What to judge</h2><ul>
<li>The font: one of the seven, or what they show you about what fits.</li>
<li>The ball&rsquo;s shape and how the bodies come in (spring looseness, how lumpy, how much it floats about).</li>
<li>The orbs&rsquo; size and orbit.</li></ul></section>
</main></body></html>''')
open(OUT, 'w', encoding='utf-8').write(''.join(H))
print('wrote', OUT, os.path.getsize(OUT)//1024, 'KB')
