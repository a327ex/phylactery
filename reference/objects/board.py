# board.py -- round 28's reference board for the three objects still open (the burned doll's
# kind, the magnetism object, the lift object): real photographs of each candidate, gathered by
# a research agent (sources.md per slot), embedded so the page is self-contained.
#
#   python reference/objects/board.py rounds/28-objects/board.html
import base64, io, os, re, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'board.html')

SLOTS = [
  ('fire', 'FIRE: A BURNED DOLL', 'The doll is yours; which kind of doll it was is open. Each burns differently. (No open photograph of a burned doll exists: each kind shows the doll whole or broken, plus how its material burns.)', [
    ('bisque', 'Porcelain (bisque) doll', 'The glazed face blackens and crazes, the glass eyes survive; the cloth body burns away to the stuffing. A precious, kept thing.'),
    ('rag', 'Rag doll', 'Cloth chars and burns through in holes, stuffing shows, button or stitched eyes. Homemade, soft, poor.'),
    ('wooden', 'Carved wooden doll', 'Wood chars into cracked alligator scales, the joints and pegs stay; hard, old, folk.'),
    ('straw', 'Straw effigy', 'A figure made to be burned (Marzanna, wara ningyo): fire as ritual or curse, not accident.'),
  ]),
  ('rock', 'ROCK: MAGNETISM, NOT MODERN', 'Something about magnetism that could exist in another world.', [
    ('armed-lodestone', 'Armed lodestone', 'A lodestone bound in brass with iron feet and a ring, holding up an iron weight (17th-18th century). Crafted, scholarly, alchemical.'),
    ('raw-lodestone', 'Raw lodestone', 'A black magnetite stone with iron filings and nails standing up along its field. Natural and uncanny: a rock that pulls rocks, the field made visible.'),
    ('sinan', 'South-pointing spoon', 'The Han lodestone spoon turning on a bronze divination board. Ancient, a fortune-teller\'s tool.'),
    ('south-pointing-fish', 'South-pointing fish', 'A thin iron fish floated in a bowl of water, turning to point south. Gentle, folk. (Only a classroom demo photo exists; no museum reconstruction found.)'),
  ]),
  ('lift', 'LIFT AND BURST: NO IDEA YET', 'Lifts them into the air; his fist closes and they burst. My candidates.', [
    ('pomegranate', 'Pomegranate, split', 'Bursting open, seeds like blood; the underworld\'s fruit (Persephone). The burst.'),
    ('milkweed-pod', 'Milkweed pod', 'A dry pod split open, its silk seeds lifting out on the air. The lift, and letting go.'),
    ('puffball', 'Puffball', 'A fungus that bursts into a cloud when squeezed. The fist, and a cave thing.'),
    ('votive-hand', 'Hand of Sabazios', 'A Roman bronze votive hand raised in blessing, a snake climbing it. The gesture itself.'),
  ]),
]

def img_uri(path, long=560):
  im = Image.open(path).convert('RGB')
  s = long/max(im.size)
  if s < 1: im = im.resize((round(im.size[0]*s), round(im.size[1]*s)), Image.LANCZOS)
  b = io.BytesIO(); im.save(b, 'JPEG', quality=86)
  return 'data:image/jpeg;base64,' + base64.b64encode(b.getvalue()).decode()

def sources(slot):
  p = os.path.join(HERE, slot, 'sources.md')
  return open(p, encoding='utf-8').read() if os.path.exists(p) else ''

def esc(s): return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

parts = []
for slot, title, sub, cands in SLOTS:
  src = sources(slot)
  parts.append(f'<section><h2>{esc(title)}</h2><p class="sub">{esc(sub)}</p><div class="cands">')
  for n, (key, name, read) in enumerate(cands, 1):
    d = os.path.join(HERE, slot, key)
    files = sorted(f for f in os.listdir(d) if f.lower().endswith(('.jpg', '.jpeg', '.png', '.webp'))) if os.path.isdir(d) else []
    imgs = ''.join(f'<figure><img src="{img_uri(os.path.join(d, f))}" alt="{esc(f)}"><figcaption>{esc(f)}</figcaption></figure>' for f in files)
    if not files: imgs = '<p class="none">no usable photograph found</p>'
    parts.append(f'<div class="cand"><h3>{slot[0].upper()}{n}. {esc(name)}</h3><p>{esc(read)}</p><div class="imgs">{imgs}</div></div>')
  parts.append('</div>')
  if src: parts.append(f'<details><summary>sources</summary><pre>{esc(src)}</pre></details>')
  parts.append('</section>')

html = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Objects Board</title>
<style>
:root {{ --bg:#14110e; --fg:#e9dcc3; --dim:#9c8d74; --line:#2c261f; --card:#1c1814; }}
@media (prefers-color-scheme: light) {{ :root:not([data-theme="dark"]) {{ --bg:#f3eee6; --fg:#241d15; --dim:#6d5f4b; --line:#d8cfc1; --card:#fbf8f3; }} }}
:root[data-theme="dark"] {{ --bg:#14110e; --fg:#e9dcc3; --dim:#9c8d74; --line:#2c261f; --card:#1c1814; }}
body {{ margin:0; background:var(--bg); color:var(--fg); font:15px/1.5 system-ui, sans-serif; }}
main {{ max-width:1400px; margin:0 auto; padding:24px 16px 64px; }}
h1 {{ font-size:22px; margin:0 0 4px; }} h2 {{ font-size:18px; margin:32px 0 2px; }} h3 {{ font-size:15px; margin:0 0 4px; }}
.sub, .lead {{ color:var(--dim); margin:0 0 12px; }}
.cands {{ display:grid; grid-template-columns:repeat(auto-fit, minmax(300px, 1fr)); gap:14px; }}
.cand {{ background:var(--card); border:1px solid var(--line); border-radius:8px; padding:12px; }}
.cand p {{ margin:0 0 8px; color:var(--dim); font-size:14px; }}
.imgs {{ display:grid; grid-template-columns:1fr 1fr; gap:6px; }}
figure {{ margin:0; }} img {{ width:100%; height:180px; object-fit:cover; border-radius:4px; display:block; background:#000; }}
figcaption {{ font-size:11px; color:var(--dim); overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }}
.none {{ font-style:italic; }}
details {{ margin-top:10px; color:var(--dim); }} pre {{ white-space:pre-wrap; font-size:12px; }}
</style></head><body><main>
<h1>Round 28: the three open objects</h1>
<p class="lead">Real photographs of each candidate, to pick from (answer in chat, e.g. "F3, R2, L1"). Your pick gets modelled in round 29, in the inspect view and on the floor like the lens and the gem.</p>
{''.join(parts)}
</main></body></html>'''
os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
open(OUT, 'w', encoding='utf-8').write(html)
print('board ->', OUT, f'{len(html)//1024} KB')
