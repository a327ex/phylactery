"""make_page.py -- round 40's page (self-contained: every still embedded), from the PNGs beside it."""
import base64, os

HERE = os.path.dirname(os.path.abspath(__file__))
def img(name, alt):
    b = base64.b64encode(open(os.path.join(HERE, name), 'rb').read()).decode()
    return f'<img src="data:image/png;base64,{b}" alt="{alt}">'

SHOTS = [
    ('tunnel.png', 'the second camera: from the room, behind the egg, down the tunnel he comes out of'),
    ('room.png', 'where the room\'s frame takes him, the room\'s camera cuts in and the fight starts'),
    ('inventory.png', 'the inventory, top right: each object\'s own small render (hovering names it)'),
    ('question.png', 'clicking one (or 5-0): the model viewer, its text slot, the question'),
    ('dropped.png', 'yes: it falls from his hand beside him; its slot empties'),
    ('all.png', 'all six given up: the snakes reach the egg, the ending as before'),
]
figs = ''.join(f'<figure>{img(f, c)}<figcaption>{c}</figcaption></figure>' for f, c in SHOTS)
html = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lich Survivors Inventory</title>
<style>
:root {{ --bg: #0d0b0a; --fg: #e9dcc4; --dim: #a8987c; --rule: #2a241f; --card: #15120f; --accent: #e0a070; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --bg: #0d0b0a; }} }}
:root[data-theme="dark"] {{ --bg: #0d0b0a; }}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--bg); color: var(--fg); font: 15px/1.55 Georgia, 'Times New Roman', serif; }}
main {{ max-width: 1320px; margin: 0 auto; padding: 28px 16px 64px; }}
h1 {{ font-size: 26px; margin: 0 0 6px; }}
h2 {{ font-size: 18px; margin: 0 0 4px; }}
p {{ margin: 6px 0 10px; max-width: 78ch; }}
.sub {{ color: var(--dim); }}
section {{ border-top: 1px solid var(--rule); padding: 18px 0 8px; }}
.shots {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(360px, 1fr)); gap: 10px; }}
figure {{ margin: 0; background: var(--card); }}
figure img {{ display: block; width: 100%; height: auto; image-rendering: pixelated; }}
figcaption {{ color: var(--dim); font-size: 13px; padding: 4px 8px 6px; }}
table {{ border-collapse: collapse; font-size: 14px; }}
td {{ padding: 3px 14px 3px 0; vertical-align: top; }}
td:first-child {{ color: var(--accent); white-space: nowrap; }}
</style></head>
<body><main>
<h1>Lich Survivors &middot; round 40 &middot; the tunnel, the inventory, the question</h1>
<p class="sub">2026-10-02. The caves are set aside (kept in archive/the-walk, tag walk-round39).</p>
<p>He comes in down the final room's tunnel, seen by a second fixed camera, carrying all six objects. Where the room's camera can see him, it cuts in and the fight starts: the final room exactly as it was. Clicking an object in the inventory brings up the model viewer with its description and the question; yes, and it falls to the floor.</p>
<section><h2>Run it</h2>
<table>
<tr><td>run.bat</td><td>starts in the tunnel</td></tr>
<tr><td>WASD / hold left mouse</td><td>move</td></tr>
<tr><td>click an object / 5&ndash;0</td><td>the question; Y or Enter: yes, N or Esc: no (the view still turns and zooms)</td></tr>
<tr><td>I</td><td>look at the objects (no question)</td></tr>
<tr><td>T</td><td>remove every power at once (testing)</td></tr>
</table></section>
<section><div class="shots">{figs}</div></section>
<section><h2>Open</h2>
<p>Each object's description is yours to write (the [ YOUR TEXT ] slot). A key pressed for an object already given up brings it back (testing only). LICH_ROOM=1 still starts in the room as before, unchanged to the digest.</p></section>
</main></body></html>
'''
open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8').write(html)
print('index.html', len(html)//1024, 'KB')
