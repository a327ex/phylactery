"""Round 50's page: the five group versions (clips embedded), the waves, the bouts, what was checked.
python rounds/50-bouts/make_page.py"""
import base64, html, os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
SCR = os.path.join(ROOT, 'scratch', 'r50')
OUT = os.path.join(HERE, 'index.html')

def clip(name):
    b = open(os.path.join(HERE, name + '.mp4'), 'rb').read()
    return '<video controls playsinline loop muted preload="metadata" src="data:video/mp4;base64,%s"></video>' % base64.b64encode(b).decode()

def read(name):
    p = os.path.join(SCR, name)
    return open(p, encoding='utf-8').read().strip() if os.path.exists(p) else ''

auto = read('auto_run.txt').splitlines()
sweep = (read('sweep_near_out.txt') + '\n' + read('sweep_far_out.txt')).strip().splitlines()
def line(prefix):
    for l in auto:
        if l.startswith(prefix): return l[len(prefix):].strip()
    return ''

H = ['''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lich Survivors Bouts</title>
<style>
:root { --bg: #0d0b0a; --fg: #e9dcc4; --dim: #a8987c; --rule: #2a241f; --card: #15120f; --accent: #e0a070; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg: #0d0b0a; } }
:root[data-theme="dark"] { --bg: #0d0b0a; }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.55 Georgia, 'Times New Roman', serif; }
main { max-width: 1100px; margin: 0 auto; padding: 22px 16px 64px; }
h1 { font-size: 23px; margin: 0 0 6px; } h2 { font-size: 18px; margin: 0 0 6px; color: var(--accent); font-weight: normal; }
p { margin: 6px 0 10px; } .sub { color: var(--dim); } .tag { color: var(--dim); font-size: 14px; }
section { border-top: 1px solid var(--rule); padding: 16px 0 6px; }
video { display: block; width: 100%; height: auto; background: #000; }
pre { white-space: pre-wrap; word-break: break-word; background: var(--card); color: var(--dim); font: 13px/1.5 ui-monospace, Consolas, monospace; padding: 10px 12px; margin: 6px 0 10px; }
ul { margin: 6px 0 10px; padding-left: 22px; } li { margin: 3px 0; }
</style></head>
<body><main>
<h1>Lich Survivors &middot; round 50 &middot; waves, bouts, group attacks</h1>
<p class="sub">2026-10-05. Anchor build, headless, the room camera (the game as you see it).</p>
<p>Your plan from last session. The snakes now come in waves of different shapes, and the lich handles them in bouts: one attack for all of them, a mix of 2, a mix of 3, or a random rotation with repeats. Three or more snakes taken by one attack get that attack's group version. You specified the beam and the lift; the fire, rock and lens versions are my first attempts.</p>''']

GROUPS = [
    ('beam', 'The beam: revolver shots', 'yours',
     'He fires at one, turns to the next, fires, and so on round the group. Each beam leaves from where his finger was when it fired (it stays there as he turns on), travels faster than the normal beam and kicks his arm hard on its own; he turns faster while firing in turn. Shots come 0.17 to 0.4 s apart, depending on how far he has to turn.'),
    ('lift', 'The lift: pulled together, gored at once', 'yours',
     'Lifted as before, then drawn into one knot in the air in front of him (pulled toward him into the light, kept clear of the egg): their middles pressed together and wrung about it, the ends hanging out. Then his fist closes and they all burst at once.'),
    ('fire', 'The fire: one sweep', 'mine',
     'Instead of lighting them one after another, his arm sweeps across them in one motion, starting a little before the first and running on past the last. Each one catches as his finger passes over it, and the floor flares along the line of the sweep.'),
    ('rock', 'The rocks: a ring, then a volley', 'mine',
     'One rock per snake, torn up from the floor all round him; they circle him at chest height for about a second, then are loosed almost together, each at its own snake.'),
    ('lens', 'The lens: one long cut', 'mine',
     'One larger lens forms in the shaft; its burning point draws a single cut from beside the first snake through each of the others in turn.'),
]
for key, title, whose, text in GROUPS:
    H.append('<section><h2>%s <span class="tag">(%s)</span></h2>%s<p>%s</p></section>' % (title, 'your spec' if whose == 'yours' else 'my first attempt', clip(key), text))

H.append('''<section><h2>The waves</h2>
<p>A snake that dies now waits in a pool until a wave sends it, instead of coming back on its own 2 to 5 s timer (which is what made them arrive together). The waves:</p>
<ul>
<li><b>ONE</b>: a single snake.</li>
<li><b>PAIR</b>: two from about the same side, a moment apart.</li>
<li><b>PACK</b>: three to five from one side, close together.</li>
<li><b>SPREAD</b>: three or four from different sides at once.</li>
<li><b>STREAM</b>: four to six along one line, about a second apart.</li>
</ul>
<p>After about one wave in five there is a quiet stretch of 3 to 6 s. Two big waves of the same shape never come back to back.</p></section>
<section><h2>The bouts</h2>
<p>When snakes come near the egg, the lich draws how to handle them: <b>ALL ONE</b> (one attack takes every snake there; he waits for the group to come in, then takes all of it at once), <b>MIX OF 2</b>, <b>MIX OF 3</b> (those attacks take turns, usually alternating, sometimes repeating), or <b>ROTATION</b> (any attack each time, repeats included). A pack or spread on its way makes ALL ONE likelier (60%, against 18% otherwise). A bout ends after a few casts or when the floor goes quiet, and a group arriving in the middle of a bout starts a new one. A snake that gets too close to the egg still forces a cast right away, whatever the bout.</p>''')
if auto:
    H.append('<p>Three minutes of normal play with all six (headless, nothing forced):</p><pre>%s</pre>' % html.escape('\n'.join([
        'waves:  ' + line('waves'),
        'bouts:  ' + line('plans'),
        'snakes taken by each:  ' + line('took'),
        'group casts:  ' + line('groups'),
        'reached the egg:  ' + line('reached')])))
H.append('</section>')

H.append('''<section><h2>Testing keys</h2>
<ul>
<li><b>F3</b> cycles how he handles them: AUTO, ALL FIRE, ALL LIFT, ALL BEAM, ALL ROCK, ALL LENS, MIX OF 2, MIX OF 3, ROTATION. The testing text (top left) shows the bout in progress.</li>
<li><b>F9</b> sends a pack now, <b>F10</b> a spread.</li>
</ul>
<p>To see a group version: F3 to ALL BEAM (for example), then F9. The pack takes about ten seconds to reach him.</p></section>''')

H.append('<section><h2>Checked</h2>')
H.append('<p class="sub">LICH_ROOM=1 (the old flow, the three.js comparison path) gives the same digest run byte for byte as round 48. Each group version forced against a pack: all five trigger, nothing reached the egg. The guarantee sweep with the waves and bouts, 20 cases (the powers he holds, near the egg and far from it), 3 s to settle then 90 s each:</p>')
if sweep:
    H.append('<pre>%s</pre>' % html.escape('\n'.join(sweep)))
long = read('long_out.txt')
if long: H.append('<p class="sub">Ten minutes of normal play with all six, nothing forced: %s</p>' % html.escape(long.replace('long: ', '')))
H.append('<p class="sub">(held = FIRE LIFT ROCK LEAK BEAM LENS; groups = group casts in those 90 s. With none held the snakes should reach the egg: that is the ending.) One earlier run did let a snake through with all six held: it was one of a fire sweep&rsquo;s own group, and the sweep went round in angle order and got to it too late. Fixed before these runs: a group gesture now hurries as soon as one of its snakes nears the egg, and one about to reach it is taken at once (the next shot goes to it, or the sweep&rsquo;s fire leaps to it).</p></section>')

H.append('''<section><h2>What to judge</h2>
<ul>
<li>Each group version: keep, change, or replace. Fire, rock and lens are my guesses at what fits; beam and lift follow your words.</li>
<li>Whether group casts come often enough in normal play. With all six they came 6 times in the 3 minute run and once or twice in each 90 s case of the sweep; with fewer powers each attack takes more snakes, so they come more often (3 to 9 per 90 s above).</li>
<li>Whether the waves and the order of attacks now feel varied when you play (run.bat).</li>
</ul>
<p class="sub">Not in this round: sounds. The group versions have no sounds of their own yet.</p></section>
</main></body></html>''')
open(OUT, 'w', encoding='utf-8').write(''.join(H))
print('wrote', OUT, os.path.getsize(OUT)//1024, 'KB')
