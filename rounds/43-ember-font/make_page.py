"""make_page.py -- round 43's page (self-contained: every still embedded), from the PNGs beside it."""
import base64, os
HERE = os.path.dirname(os.path.abspath(__file__))
def img(name, alt):
    b = base64.b64encode(open(os.path.join(HERE, name), 'rb').read()).decode()
    return f'<img src="data:image/png;base64,{b}" alt="{alt}">'
def fig(name, cap, cls=''):
    return f'<figure class="{cls}">{img(name, cap)}<figcaption>{cap}</figcaption></figure>'
C = [
    (6, 'FACETED', 'drawn for this cave: capitals whose rounds are cut into planes, like its broken rock; names lit like the icons (a dark letter, its upper left edge warm), the rest in a warm fall from top to bottom'),
    (7, 'RUNIC', 'drawn for this cave: thin, angular, as if scratched into the rock with a point; no curves at all, so B, C, D, P and R turn rune-like'),
    (8, 'CARVED', 'Cinzel (Roman capitals, as cut in stone) for names, Marcellus SC (flared, carved small capitals) for the rest'),
    (9, 'WORN', 'IM Fell English SC: an old, worn printing type, for both'),
    (10, 'SHARP', 'MedievalSharp: an angular hand, as cut with a knife, for both'),
]
body = ''
for f, name, desc in C:
    k = f - 5
    body += f'<h3>{name}</h3><p class="sub">{desc}</p><div class="row2">' + fig(f'f{f}_tunnel.png', f'{name}: the first view, the hand hovered', 'pick' if f == 6 else '') + fig(f'f{f}_question.png', f'{name}: the question', 'pick' if f == 6 else '') + '</div>'
html = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lich Survivors Ember Font</title>
<style>
:root {{ --bg: #0d0b0a; --fg: #e9dcc4; --dim: #a8987c; --rule: #2a241f; --card: #15120f; --accent: #e0a070; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --bg: #0d0b0a; }} }}
:root[data-theme="dark"] {{ --bg: #0d0b0a; }}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--bg); color: var(--fg); font: 15px/1.55 Georgia, 'Times New Roman', serif; }}
main {{ max-width: 1400px; margin: 0 auto; padding: 28px 16px 64px; }}
h1 {{ font-size: 26px; margin: 0 0 6px; }} h2 {{ font-size: 18px; margin: 0 0 4px; }}
h3 {{ font-size: 15px; margin: 18px 0 2px; color: var(--accent); font-weight: normal; }}
p {{ margin: 6px 0 10px; max-width: 82ch; }} .sub {{ color: var(--dim); }}
section {{ border-top: 1px solid var(--rule); padding: 18px 0 8px; }}
.row2 {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(420px, 1fr)); gap: 10px; }}
figure {{ margin: 0; background: var(--card); border: 2px solid transparent; }}
figure.pick {{ border-color: var(--accent); }}
figure img {{ display: block; width: 100%; height: auto; image-rendering: pixelated; }}
figcaption {{ color: var(--dim); font-size: 13px; padding: 4px 8px 6px; }}
table {{ border-collapse: collapse; font-size: 14px; }} td {{ padding: 3px 14px 3px 0; vertical-align: top; }}
td:first-child {{ color: var(--accent); white-space: nowrap; }}
</style></head>
<body><main>
<h1>Lich Survivors &middot; round 43 &middot; EMBER's text</h1>
<p class="sub">2026-10-03. Anchor build. Bordered = what the game starts with now (EMBER with FACETED).</p>
<p>You picked EMBER; its font did not fit. The cave is broken rock with warm light on its edges, and so are EMBER's icons, so the text goes the same two ways. Its letterforms are cut, scratched, carved or worn rather than modern. Its colour is lit like the icons: every candidate here falls from a lighter tone at the top to a deeper ember at the bottom, and the two drawn fonts light their names as the icons are lit.</p>
<section><h2>Run it</h2>
<table><tr><td>run.bat</td><td>starts on EMBER with FACETED</td></tr>
<tr><td>F3</td><td>the fonts: after the round 42 ones come FACETED, RUNIC, CARVED, WORN, SHARP</td></tr>
<tr><td>F1, F2, F4</td><td>as before (the other directions, icons, frames)</td></tr></table></section>
<section><h2>Five candidates</h2>{body}</section>
<section><h2>Side by side (3x)</h2>{fig('crops.png', 'FACETED, RUNIC, CARVED, WORN, SHARP: the slots with a name, and the question')}</section>
<section><h2>The two drawn fonts</h2>{fig('alphabets.png', 'FACETED (top three lines), RUNIC (bottom three), 4x, with the warm fall')}</section>
<section><h2>Unfinished</h2><p>The three TrueType fonts are drawn at sizes they were not made for, so some letters come out uneven, most of all in WORN's small capitals. The drawn fonts have capitals only. Whichever you choose I will finish properly: its missing characters, its spacing, and the treatment's strength.</p></section>
</main></body></html>
'''
open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8', newline='\n').write(html)
print('index.html', len(html) // 1024, 'KB')
