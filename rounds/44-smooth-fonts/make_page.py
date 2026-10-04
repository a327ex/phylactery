"""make_page.py -- round 44's page (self-contained: every still embedded), from the PNGs beside it."""
import base64, os
HERE = os.path.dirname(os.path.abspath(__file__))
def img(name, alt):
    b = base64.b64encode(open(os.path.join(HERE, name), 'rb').read()).decode()
    return f'<img src="data:image/png;base64,{b}" alt="{alt}">'
def fig(name, cap, cls=''):
    return f'<figure class="{cls}">{img(name, cap)}<figcaption>{cap}</figcaption></figure>'
C = [
    (11, 'CINZEL', 'Roman capitals as cut in stone; capitals throughout'),
    (12, 'FELL', 'IM Fell English: an old printing type, worn; small capitals for names, its roman for the rest'),
    (13, 'UNCIAL', 'Uncial Antiqua: the round book-hand of early manuscripts; the most mythic'),
    (14, 'SHARP', 'MedievalSharp: an angular hand, as cut with a knife'),
    (15, 'MARCELLUS', 'Marcellus: a flared, carved serif; small capitals for names; the calmest'),
    (16, 'GRENZE', 'Grenze: between a roman and a blackletter; dense, old'),
]
body = ''
for f, name, desc in C:
    pick = 'pick' if f == 12 else ''
    body += f'<h3>{name}</h3><p class="sub">{desc}</p><div class="row2">' + fig(f'f{f}_tunnel.png', f'{name}: the first view, the hand hovered', pick) + fig(f'f{f}_question.png', f'{name}: the question', pick) + '</div>'
html = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lich Survivors Smooth Fonts</title>
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
.row2 {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(480px, 1fr)); gap: 10px; }}
figure {{ margin: 0; background: var(--card); border: 2px solid transparent; }}
figure.pick {{ border-color: var(--accent); }}
figure img {{ display: block; width: 100%; height: auto; }}
figcaption {{ color: var(--dim); font-size: 13px; padding: 4px 8px 6px; }}
table {{ border-collapse: collapse; font-size: 14px; }} td {{ padding: 3px 14px 3px 0; vertical-align: top; }}
td:first-child {{ color: var(--accent); white-space: nowrap; }}
</style></head>
<body><main>
<h1>Lich Survivors &middot; round 44 &middot; smooth fonts</h1>
<p class="sub">2026-10-03. Anchor build. Every picture is the whole window at 1280x720, as you see it. Bordered = what the game starts with now (EMBER, FELL).</p>
<p>The game is drawn at 640x360 and scaled up 2x. A smooth font drawn into that frame would come out soft and blocky, so smooth text now has its own layer at the window's full resolution, over the scaled game. The icons and frames stay pixels; only the words are smooth. They keep the warm colours, with a soft dark halo and a drop shadow so they read on the lit floor. The same kinds of letter as round 43 (carved, worn, cut, ancient), now smooth.</p>
<section><h2>Run it</h2>
<table><tr><td>run.bat</td><td>starts on EMBER with FELL</td></tr>
<tr><td>F3</td><td>the fonts: after the pixel ones (rounds 42 and 43) come SMOOTH CINZEL, FELL, UNCIAL, SHARP, MARCELLUS, GRENZE</td></tr>
<tr><td>F1, F2, F4</td><td>as before</td></tr></table></section>
<section><h2>Six candidates</h2>{body}</section>
<section><h2>Side by side, at the window's own pixels</h2>{fig('crops.png', 'CINZEL, FELL, UNCIAL, SHARP, MARCELLUS, GRENZE: the slots with a name, and the question (some names cut off by the crop)')}</section>
<section><h2>Unfinished</h2><p>The warm top-to-bottom fall of round 43 is not on smooth text yet: the engine draws a text in one colour. If you want it, it is a small shader on the text layer. Sizes are first guesses. In a window bigger than 1280x720 the text layer scales up smoothly instead of being redrawn larger; drawing it at the window's real size is the finishing step.</p></section>
</main></body></html>
'''
open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8', newline='\n').write(html)
print('index.html', len(html) // 1024, 'KB')
