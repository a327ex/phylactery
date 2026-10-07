"""Round 55's page: the snake that reached the egg, the attacks' balance, the orbs' marks, the name that holds still.
python rounds/55-reach-balance/make_page.py"""
import base64, html, io, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
SCR = os.path.join(ROOT, 'scratch', 'r55')
OLD = os.path.join(ROOT, 'scratch', 'r55', 'view_old')
OUT = os.path.join(HERE, 'index.html')

def img(path, cap, crop=None, w=None, nearest=True):
    im = Image.open(path).convert('RGB')
    if crop: im = im.crop(crop)
    if w: im = im.resize((w, int(im.height*w/im.width)), Image.NEAREST if nearest else Image.LANCZOS)
    b = io.BytesIO(); im.save(b, 'PNG', optimize=True)
    return '<figure><img class="px" src="data:image/png;base64,%s" alt="%s"><figcaption>%s</figcaption></figure>' % (base64.b64encode(b.getvalue()).decode(), html.escape(cap), cap)

H = ['''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lich Survivors Reach</title>
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
table { border-collapse: collapse; margin: 6px 0 10px; font-size: 15px; }
th, td { padding: 4px 12px; border-bottom: 1px solid var(--rule); text-align: right; }
th:first-child, td:first-child { text-align: left; color: var(--dim); }
.lo { color: var(--accent); }
.scroll { overflow-x: auto; }
</style></head>
<body><main>
<h1>Lich Survivors &middot; round 55 &middot; the snake that reached the egg, the attacks&rsquo; balance, the orbs, the name</h1>
<p class="sub">2026-10-07. Anchor build, headless.</p>''']

E = os.path.join(SCR, 'evidence')
crop = (309 - 70, 207 - 60, 309 + 70, 207 + 30)
H.append('<section><h2>The snake that reached the egg</h2><div class="grid">')
for f, cap in (('09256', 'frame 9256: the lich east of the egg, busy with a group; a snake comes down from the north'),
               ('09300', 'frame 9300: its head a metre from the egg'),
               ('09330', 'frame 9330: at the egg'),
               ('09384', 'frame 9384: coiled round it')):
    H.append(img(os.path.join(E, f + '.png'), 'your run 16:46, ' + cap, crop=crop, w=420))
H.append('''</div>
<p>Your run, replayed headless. Since the replay only holds what was drawn, I reproduced it in the live game: the lich at eight spots one to one and a half metres from the egg, packs and spreads coming every 5 seconds. On the code you played, that gave 2 snakes at the egg in 16 minutes, and the record of each snake&rsquo;s last 3 seconds showed both happening the same way, most likely how yours got through too.</p>
<p>A thrown rock or the lens had picked the snake out early. While a rock or lens is on its way to a snake, the other attacks leave that snake to it until it gets close (1.5 m from the egg for a rock, 2 m for the lens), so they don&rsquo;t pile onto the same snake. That time, the rock or lens didn&rsquo;t get there in time. When the snake came that close, an urgent gesture started (a beam once, a lift once), but an urgent gesture still raised the arm and waited for a short beat, up to about half a second. A snake that close needs only about a third of a second to reach the egg.</p>
<p>The fixes: a gesture with a snake within 1.6 m of the egg goes off at once, the arm wherever it is (the beam and the lift take their snake the moment they go off). And behind everything, a last resort: any snake still loose within 1.35 m is taken there and then by whatever takes at once, whatever else is going on: the fire leaps to it, or a lift, or a beam shot. The same stress, 48 minutes of it, 3 times as long: no snake at the egg, and the last resort never had to act.</p></section>''')

H.append('''<section><h2>The attacks&rsquo; balance</h2>
<p>Measured in 5 minutes of play with all six, casts of each attack:</p>
<div class="scroll"><table>
<tr><th></th><th>fire</th><th>lift</th><th>beam</th><th>rock</th><th>lens</th></tr>
<tr><td>before, standing</td><td>16</td><td>17</td><td>17</td><td>17</td><td class="lo">10</td></tr>
<tr><td>before, moving about</td><td>16</td><td>13</td><td class="lo">12</td><td>15</td><td>19</td></tr>
<tr><td>now, standing</td><td>17</td><td>15</td><td>16</td><td>17</td><td>14</td></tr>
<tr><td>now, moving about</td><td>16</td><td>15</td><td>14</td><td>16</td><td>14</td></tr>
</table></div>
<p>The bouts already leaned toward attacks that hadn&rsquo;t been used for a while, but only a little. Now an attack that has fallen behind the most-used one is up to 3.4 times as likely to be picked, in every kind of bout (all one attack, mixes, the rotation). Under the heavy stress above, the five ended within 3 casts of each other (61 to 64).</p></section>''')

H.append('<section><h2>The orbs: much fainter marks</h2><div class="grid">')
oc = (430, 160, 850, 480)
H.append(img(os.path.join(OLD, 'o3_p1.png'), 'before', crop=oc, w=520))
H.append(img(os.path.join(SCR, 'view', 'o3_p1.png'), 'now', crop=oc, w=520))
H.append('</div><p>The lines are less than half as wide and about a third as strong: faint frosted lines in the glass rather than bands.</p></section>')

H.append('<section><h2>The name holds still</h2><div class="grid">')
for p in (1, 2, 3):
    H.append(img(os.path.join(OLD, 'o5_p%d.png' % p), 'before: the lens, turned', w=360, nearest=False))
for p in (1, 2, 3):
    H.append(img(os.path.join(SCR, 'view', 'o5_p%d.png' % p), 'now: the same turns', w=360, nearest=False))
H.append('''</div>
<p>The name used to sit under the lowest point of the object as it turned, so it rose and fell 8 to 30 pixels with every turn. Now it sits under the space the object turns within, which is the same whichever way it faces: measured in every shot of all six objects at three angles, the name is on exactly the same row. Only zooming moves it now. Because each object is framed to fill the same space, the name sits at the same height for all six.</p></section>''')

H.append('</main></body></html>')
open(OUT, 'w', encoding='utf-8', newline='\n').write('\n'.join(H))
print(OUT, os.path.getsize(OUT))
