# ref_page.py -- one self-contained HTML board from a folder of reference images + captions.json
#   python tools/ref_page.py reference/astra-r02 rounds/02-references/index.html "Title" "subtitle"
# Sections are the subfolders (in SECTIONS order); images are embedded as JPEG (q 88).
import base64, io, json, os, sys, html
from PIL import Image

src, out, title, sub = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
caps = json.load(open(os.path.join(src, 'captions.json'), encoding='utf-8'))
SECTIONS = [('lich', 'The lich: prismatic bone', 'Which reading of "prismatic" is closest to what you see? (number)'),
            ('snake', 'The snakes: species', 'Which species (or which traits from several) should the snakes be?'),
            ('cave', 'The cave: light and formations', 'Targets for the cave: which of these feel right for the room?')]
cards = []
for key, head, ask in SECTIONS:
    d = os.path.join(src, key)
    if not os.path.isdir(d): continue
    items = []
    for f in sorted(os.listdir(d)):
        if not f.endswith('.png'): continue
        im = Image.open(os.path.join(d, f)).convert('RGB')
        b = io.BytesIO(); im.save(b, 'JPEG', quality=88)
        uri = 'data:image/jpeg;base64,' + base64.b64encode(b.getvalue()).decode()
        n = f[:-4]
        cap = caps.get(f'{key}/{n}', '')
        items.append(f'<figure><img src="{uri}" alt="{key} {n}" loading="lazy"><figcaption><b>{key.upper()} {n}</b> {html.escape(cap)}</figcaption></figure>')
    cards.append(f'<section><h2>{head}</h2><p class="ask">{html.escape(ask)}</p><div class="grid">{"".join(items)}</div></section>')

page = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title><style>
:root {{ --bg:#0d0b0a; --panel:#17130f; --ink:#efe3cc; --dim:#a8987c; --line:#2c241c; --accent:#e0b060; }}
html,body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,Segoe UI,sans-serif; }}
header {{ padding:28px 24px 8px; max-width:1500px; margin:0 auto; }}
h1 {{ margin:0 0 4px; font-size:24px; }} header p {{ margin:0; color:var(--dim); }}
section {{ max-width:1500px; margin:0 auto; padding:18px 24px 8px; }}
h2 {{ margin:14px 0 2px; font-size:19px; color:var(--accent); }} .ask {{ margin:0 0 12px; color:var(--dim); }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(340px,1fr)); gap:14px; }}
figure {{ margin:0; background:var(--panel); border:1px solid var(--line); border-radius:6px; overflow:hidden; cursor:zoom-in; }}
figure img {{ width:100%; display:block; aspect-ratio:3/2; object-fit:cover; }}
figcaption {{ padding:8px 10px 10px; color:var(--dim); font-size:13px; }} figcaption b {{ color:var(--ink); margin-right:4px; }}
#lb {{ position:fixed; inset:0; background:rgba(0,0,0,.92); display:none; align-items:center; justify-content:center; cursor:zoom-out; }}
#lb img {{ max-width:96vw; max-height:92vh; }} #lb.on {{ display:flex; }}
@media (max-width:700px) {{ .grid {{ grid-template-columns:1fr; }} header,section {{ padding-left:16px; padding-right:16px; }} }}
</style></head><body><header><h1>{html.escape(title)}</h1><p>{html.escape(sub)}</p></header>
{"".join(cards)}<div id="lb"><img alt=""></div>
<script>const lb=document.getElementById('lb'),li=lb.querySelector('img');
document.querySelectorAll('figure img').forEach(i=>i.onclick=()=>{{li.src=i.src;lb.classList.add('on');}});
lb.onclick=()=>lb.classList.remove('on');addEventListener('keydown',e=>{{if(e.key==='Escape')lb.classList.remove('on');}});</script>
</body></html>'''
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, 'w', encoding='utf-8').write(page)
print(out, len(page)//1024, 'KB')
