# real_refs.py -- a reference board of real photographs, loaded from Wikimedia Commons when the page
# is opened (nothing is downloaded here). python tools/real_refs.py rounds/04-soft-light/real-references.html
import html, sys, urllib.parse

REFS = [
  ("La_chimenea_-_cueva_de_los_Tayos.JPG", "MezzoforteF, CC BY-SA 3.0", "Cueva de los Tayos, Ecuador: a vertical chimney throwing a shaft of daylight straight down onto the cave floor and rubble."),
  ("Goa_Jomblang_with_heavenly_light_-_Java_-_Indonesia_05.jpg", "Thomas Fuhrmann, CC BY-SA 4.0", "Jomblang Cave, Java: the 'heavenly light', a beam down a pit about 60 m deep onto the floor below."),
  ("Jomblang_Cave_-_Indonesia_04.jpg", "Thomas Fuhrmann, CC BY-SA 4.0", "Jomblang again, another angle: how soft the beam and its landing are from that height."),
  ("Cahaya_surga_di_Goa_Jomblang.jpg", "Arie Bas, CC BY-SA 4.0", "Jomblang with people under the lit patch: the brightness of the spot against the dark."),
  ("A_Beam_Through_the_Darkness_-_Son_Doong_Cave.jpg", "Trantuanviet, CC BY-SA 4.0", "Son Doong, Vietnam: a winter sunbeam through a skylight very far above, onto a rocky floor."),
  ("USA_Antelope-Canyon.jpg", "Lucas Löffler, public domain", "Antelope Canyon, Arizona: a beam landing on dry sand, its spot's edge soft."),
  ("Upper_Antelope_Canyon,_2013_-_21.jpg", "Jarek Tuszyński, CC BY-SA 4.0", "Upper Antelope Canyon: another beam on sand."),
  ("Cenotes_Suytun_-_panoramio_(1).jpg", "Nikolai Maksimovich, CC BY 3.0", "Cenote Suytun, Yucatán: the small ceiling hole and the beam on the stone platform (a shallow cave: the opening is not far up)."),
  ("Cenote_Suytun_(13158193355).jpg", "David Stanley, CC BY 2.0", "Cenote Suytun again."),
  ("Beautiful_Cenote_Samula_in_Valladolid,_Mexico_(19655105381).jpg", "dronepicr, CC BY 2.0", "Cenote Samula, Yucatán: a beam through a small ceiling opening, landing on water."),
  ("Plakias_Gonates_Cave_01.JPG", "Uoaei1, CC BY-SA 4.0", "Gonates tunnel, Crete (man-made): a beam landing on the tunnel floor."),
  ("Hang_Én_Cave_-_201505_-_JB.jpg", "Jérémie B., CC BY-SA 4.0", "Hang Én, Vietnam: light from a huge entrance, for comparison with a narrow shaft."),
]

out = sys.argv[1]
cards = []
for i, (name, credit, cap) in enumerate(REFS, 1):
    q = urllib.parse.quote(name)
    img = f"https://commons.wikimedia.org/wiki/Special:FilePath/{q}?width=1280"
    page = f"https://commons.wikimedia.org/wiki/File:{q}"
    cards.append(f'<figure><a href="{img}" target="_blank" rel="noopener"><img src="{img}" alt="{html.escape(cap)}" loading="lazy" referrerpolicy="no-referrer"></a>'
                 f'<figcaption><b>{i:02d}</b> {html.escape(cap)}<br><a href="{page}" target="_blank" rel="noopener">{html.escape(credit)} &middot; Wikimedia Commons</a></figcaption></figure>')
page = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Real Light Shafts</title><style>
:root {{ --bg:#0d0b0a; --panel:#17130f; --ink:#efe3cc; --dim:#a8987c; --line:#2c241c; --accent:#e0b060; }}
html,body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,Segoe UI,sans-serif; }}
header,main {{ max-width:1500px; margin:0 auto; padding:24px; }} h1 {{ margin:0 0 4px; font-size:23px; }} header p {{ margin:0; color:var(--dim); }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(380px,1fr)); gap:14px; }}
figure {{ margin:0; background:var(--panel); border:1px solid var(--line); border-radius:6px; overflow:hidden; }}
figure img {{ width:100%; display:block; aspect-ratio:3/2; object-fit:cover; background:#000; }}
figcaption {{ padding:8px 10px 10px; color:var(--dim); font-size:13px; }} figcaption b {{ color:var(--accent); margin-right:4px; }} a {{ color:var(--dim); }}
@media (max-width:700px) {{ .grid {{ grid-template-columns:1fr; }} header,main {{ padding:16px; }} }}
</style></head><body><header><h1>Real light shafts: how the lit spot looks</h1>
<p>Photographs from Wikimedia Commons, loaded from there when this page opens (needs internet). Click one for the full image; credits and licences below each.</p></header>
<main class="grid">{"".join(cards)}</main></body></html>'''
open(out, 'w', encoding='utf-8').write(page)
print(out)
