# make_page.py -- round 94: Phylactery's visual identity, the references board (Phylactery 20, 2026-10-17).
# One self-contained page (every image embedded as JPEG) from lich-survivors/reference/identity/<section>/
# (each folder: images + manifest.json). Run from lich-survivors/:
#   python rounds/94-identity-references/make_page.py
import base64, html, io, json, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
REF = os.path.join(GAME, 'reference', 'identity')
OUT = os.path.join(HERE, 'index.html')
E = html.escape


def uri(path, long_side=900, q=80):
    im = Image.open(path).convert('RGB')
    w, h = im.size
    k = min(1.0, long_side / max(w, h))
    if k < 1:
        im = im.resize((round(w*k), round(h*k)), Image.LANCZOS)
    b = io.BytesIO()
    im.save(b, 'JPEG', quality=q, optimize=True)
    return 'data:image/jpeg;base64,' + base64.b64encode(b.getvalue()).decode(), im.size


def link(url, text):
    if not url:
        return ''
    return f'<a href="{E(url)}" target="_blank" rel="noopener">{E(text)}</a>'


def card(code, path, title, meta, why, lic, src, wide=False):
    u, (w, h) = uri(path, 1400 if wide else 900, 86 if wide else 80)
    return (f'<figure class="{"wide" if wide else ""}" id="{code}"><img src="{u}" width="{w}" height="{h}" alt="{E(title)}" loading="lazy">'
            f'<figcaption><b>{code}</b> <span class="t">{E(title)}</span>'
            + (f'<span class="m">{E(meta)}</span>' if meta else '')
            + (f'<span class="w">{E(why)}</span>' if why else '')
            + f'<span class="l">{E(lic)}{" &middot; " if lic and src else ""}{link(src, "source")}</span></figcaption></figure>')


def section_from(folder, prefix, wide=False):
    d = os.path.join(REF, folder)
    man = json.load(open(os.path.join(d, 'manifest.json'), encoding='utf-8'))
    groups, order = {}, []
    for it in man:
        f = os.path.join(d, it['file'])
        if not os.path.exists(f):
            continue
        g = it.get('group', '')
        if g not in groups:
            groups[g] = []
            order.append(g)
        groups[g].append(it)
    out, n = [], 0
    for g in order:
        cards = []
        for it in groups[g]:
            n += 1
            code = f'{prefix}{n:02d}'
            title = it.get('title') or it.get('name') or it['file']
            who = it.get('artist') or it.get('designer_or_foundry') or ''
            meta = ', '.join(x for x in [who, str(it.get('year', '') or '')] if x)
            if it.get('credits'):
                meta += (' · ' if meta else '') + it['credits']
            cards.append(card(code, os.path.join(d, it['file']), title, meta, it.get('why', ''),
                              it.get('license') or it.get('licence') or '', it.get('source_page', ''), wide))
        out.append(f'<h3>{E(g)}</h3><div class="{"rows" if wide else "grid"}">{"".join(cards)}</div>')
    return ''.join(out), n


# ---- Steam: every image, drawn to one scale ----
SLOTS = [
    # name, w, h, where, rule, invites
    ('Main capsule', 1232, 706, 'top of the store front (the big carousel)', 'art + logo, no other text',
     'the full key-art scene, the logo inside it'),
    ('Header capsule', 920, 430, 'top of the store page, Recommended, Big Picture, Daily Deal', 'art + logo',
     'a band: a figure on one side, the lettering on the other'),
    ('Small capsule', 462, 174, 'search, top sellers, new releases; shrunk to 184x69 and 120x45',
     'the logo "should nearly fill" it', 'the lettering alone over texture; it must survive 120x45'),
    ('Vertical capsule', 748, 896, 'top of the front page during seasonal sales', 'art + logo',
     'one standing figure, head to toe'),
    ('Library capsule', 600, 900, 'the library grid (the "box")', 'logo required, no other text',
     'a book cover: the It Follows cover is already exactly this shape (2:3)'),
    ('Library header', 920, 430, 'library rows ("Recent Games")', 'title only',
     'a second band, free to differ from the store header'),
    ('Library hero', 3840, 1240, 'top of the library page, under the logo (parallax)', 'NO words; faces in the centred 860x380',
     'a panorama: the cave, wide'),
    ('Library logo', 1280, 720, 'over the hero: bottom-left, top-centre, centre or bottom-centre', 'transparent PNG, the wordmark only',
     'the wordmark itself'),
    ('Page background', 1438, 810, 'behind the store page; Steam tints it BLUE and fades the edges', 'ambient, "not too bright"',
     'rock and dark, almost nothing'),
    ('Event cover', 800, 450, 'every announcement (required), the store page news, the library', 'artwork + branding',
     'the release announcement\'s image'),
    ('Event header', 1920, 622, 'top of an event page (suggested)', 'template clipping notes',
     'the release announcement\'s banner'),
    ('Screenshots x5+', 1920, 1080, 'the store page', 'gameplay only; 4+ marked all-ages',
     'real frames (the ending stays off)'),
    ('App icon', 184, 184, 'Steam lists, the community hub', 'JPG', 'one mark'),
    ('Shortcut icon', 256, 256, 'the desktop shortcut', 'ICO or PNG', 'the same mark, bigger'),
]


def steam_section():
    k = 0.2
    boxes = []
    for name, w, h, where, rule, inv in SLOTS:
        bw, bh = round(w*k), round(h*k)
        inner = ''
        if name == 'Library hero':
            inner = f'<i class="safe" style="width:{round(860*k)}px;height:{round(380*k)}px"></i>'
        cls = 'box logo' if name == 'Library logo' else 'box'
        boxes.append(f'<div class="slot"><div class="{cls}" style="width:{bw}px;height:{bh}px">{inner}</div>'
                     f'<div class="sl"><b>{E(name)}</b> {w}&times;{h}</div></div>')
    rows = ''.join(f'<tr><td><b>{E(n)}</b></td><td>{w}&times;{h}</td><td>{E(where)}</td><td>{E(rule)}</td><td>{E(inv)}</td></tr>'
                   for n, w, h, where, rule, inv in SLOTS)
    return f'''<section id="steam"><h2>Steam: every image it asks for</h2>
<p class="lead">Fourteen slots, every one a different shape, so every one gets its own composition (your call: a different image per size).
Drawn below at one scale (1 : 5). The upload path is settled: every slot was filled with placeholders in the rehearsal
(steam-release/RUNBOOK.md section 7, 2026-10-15); today the docs were re-read and the page checked: a new upload of the same type
replaces a filled slot ("cannot be deleted, but you can update them"). The event images live in the announcement editor, not with the rest.
Base capsules may carry only artwork, the game's name and an official subtitle; the hero carries no words at all. One trap for a warm game:
Steam tints the page background blue and fades its edges.</p>
<div class="slots">{''.join(boxes)}</div>
<table><thead><tr><th>Slot</th><th>Size</th><th>Shows on</th><th>Valve's rule</th><th>The shape invites (a hypothesis)</th></tr></thead><tbody>{rows}</tbody></table>
</section>'''


def named_section():
    N = os.path.join(REF, 'named')
    cards = [
        card('N1', os.path.join(N, 'it-follows-egg.jpg'), 'It Follows, the egg cover (the one on /artifacts that is not red)',
             'made in the It Follows illustration session, 2026-09-25 (a327ex-site/media/pages/artifacts/it-follows-3.jpg)',
             'Oil-painted, classical, gold on near-black; the shaft and the egg exactly as in the game; title in an old-style serif. 2:3, the library capsule\'s shape.',
             'his story\'s cover', ''),
        card('N2', os.path.join(N, 'kaen.jpg'), 'Queen Bee (女王蜂), "火炎 / Kaen (Fire)", single jacket',
             'Sony Music Associated Records, 2019-01-30; opening theme of the anime Dororo (2019); vocalist Avu-chan',
             'The image the ending pose was built from (round 36): one body arched far back on a flat orange-red field, a head of blue flame, gold eyes, one arm flung out with a clawed hand. Identified today by a reverse image search (Yandex), cross-checked against the single\'s listings; the old session had only the picture.',
             'non-free cover, reference only', 'https://realsound.jp/2019/01/post-305961.html'),
        card('N3', os.path.join(N, 'kaen-vs-game.jpg'), 'Round 36: Kaen beside the first in-game version of the pose',
             'rounds/36-coil/pose.png (the cave before round 41\'s surfaces)', 'How far the pose already came over: the arch, the flung arm, the hanging arm.',
             'the game', ''),
    ]
    g, ng = section_from('game', 'G')
    return f'''<section id="named"><h2>The sources you named</h2>
<p class="lead">The painting, the photo, and the game. The game's UI icons and font are left out on purpose (they are what this work replaces).
Frames marked THE ENDING are the game's secret: store art may not show them, but the pose and the covered egg are sources.</p>
<div class="grid named">{''.join(cards)}</div><h3 class="sub">The game</h3>{g}</section>''', 3 + ng


def page():
    steam = steam_section()
    named, nn = named_section()
    parts, counts = [], {}
    for folder, prefix, head, lead, wide in [
        ('albums', 'A', 'Album and single covers', 'Covers in Kaen\'s family and beyond: a body on a flat field, Japanese single jackets, death treated seriously, eggs, serpents, prisms, and covers whose lettering is the identity.', False),
        ('skeletons', 'S', 'Skeletons and liches in poses', 'Bodies made of bone: arched and falling, floating and enthroned, thinking, dancing; Japan\'s skeletons; relics dressed in jewels; the lich as modern illustration draws it.', False),
        ('themes', 'T', 'The game\'s themes', 'The egg and the serpent, phylacteries and reliquaries, one light in darkness, glass and prism, offering and sacrifice, and posters that do much with one motif.', False),
        ('fonts', 'F', 'Lettering', 'Candidate type for the PHYLACTERY wordmark (rendered here in the game\'s bone cream on the cave\'s black), and what other dark games did.', True),
    ]:
        if not os.path.exists(os.path.join(REF, folder, 'manifest.json')):
            continue
        body, n = section_from(folder, prefix, wide)
        counts[prefix] = n
        parts.append(f'<section id="{folder}"><h2>{E(head)}</h2><p class="lead">{E(lead)}</p>{body}</section>')
    asks = open(os.path.join(HERE, 'asks.html'), encoding='utf-8').read() if os.path.exists(os.path.join(HERE, 'asks.html')) else ''
    nav = ' '.join(f'<a href="#{i}">{t}</a>' for i, t in [('steam', 'Steam'), ('named', 'Named'), ('albums', 'Covers'), ('skeletons', 'Skeletons'),
                                                         ('themes', 'Themes'), ('fonts', 'Lettering'), ('asks', 'Your call')])
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Phylactery Identity References</title><style>
:root {{ color-scheme: dark; --bg:#0d0b0a; --panel:#17130f; --ink:#efe3cc; --dim:#a8987c; --line:#2c241c; --accent:#e0b060; }}
* {{ box-sizing:border-box; }}
html,body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,"Segoe UI",sans-serif; }}
header, section {{ max-width:1560px; margin:0 auto; padding:18px 16px 8px; }}
header {{ padding-top:28px; }} h1 {{ margin:0 0 6px; font-size:26px; letter-spacing:.02em; }}
header p {{ margin:0 0 6px; color:var(--dim); max-width:980px; }}
nav {{ position:sticky; top:0; z-index:5; background:rgba(13,11,10,.94); border-bottom:1px solid var(--line); padding:8px 16px; text-align:center; }}
nav a {{ color:var(--accent); text-decoration:none; margin:0 9px; font-size:14px; }}
h2 {{ margin:26px 0 4px; font-size:21px; color:var(--accent); }} h3 {{ margin:22px 0 10px; font-size:15px; color:var(--ink); text-transform:uppercase; letter-spacing:.08em; border-bottom:1px solid var(--line); padding-bottom:4px; }}
.lead {{ margin:0 0 12px; color:var(--dim); max-width:1000px; }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(min(100%,300px),1fr)); gap:14px; align-items:start; }}
.rows {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(min(100%,640px),1fr)); gap:14px; }}
figure {{ margin:0; background:var(--panel); border:1px solid var(--line); border-radius:6px; overflow:hidden; }}
.grid figure img {{ aspect-ratio:4/3; object-fit:contain; }}
h3.sub {{ font-size:18px; color:var(--accent); text-transform:none; letter-spacing:0; border:none; margin-top:28px; }}
figure img {{ width:100%; height:auto; display:block; cursor:zoom-in; background:#000; }}
figcaption {{ padding:8px 10px 10px; font-size:13px; color:var(--dim); display:flex; flex-direction:column; gap:2px; }}
figcaption b {{ color:var(--accent); font-size:14px; }} figcaption .t {{ color:var(--ink); }}
figcaption .m {{ font-size:12px; }} figcaption .w {{ color:#d6c8ad; }} figcaption .l {{ font-size:11px; opacity:.8; }}
figcaption a {{ color:var(--accent); }}
.slots {{ display:flex; flex-wrap:wrap; gap:18px 22px; align-items:flex-end; margin:6px 0 16px; }}
.slot {{ display:flex; flex-direction:column; gap:4px; max-width:100%; }}
.box {{ background:linear-gradient(160deg,#2a2016,#120e0b); border:1px solid #6b5536; position:relative; max-width:100%; }}
.box.logo {{ background:repeating-conic-gradient(#1d1813 0% 25%, #141110 0% 50%) 50%/16px 16px; border-style:dashed; }}
.safe {{ position:absolute; left:50%; top:50%; transform:translate(-50%,-50%); border:1px dashed var(--accent); }}
.sl {{ font-size:12px; color:var(--dim); }} .sl b {{ color:var(--ink); }}
table {{ width:100%; border-collapse:collapse; font-size:13px; margin:4px 0 8px; }}
th, td {{ text-align:left; padding:6px 8px; border-bottom:1px solid var(--line); vertical-align:top; }}
th {{ color:var(--accent); font-weight:600; }} td {{ color:var(--dim); }} td b {{ color:var(--ink); }}
.tablewrap {{ overflow-x:auto; }}
.asks {{ background:var(--panel); border:1px solid var(--line); border-radius:6px; padding:12px 18px; }}
.asks li {{ margin:8px 0; }} .asks b {{ color:var(--ink); }}
#lb {{ position:fixed; inset:0; background:rgba(0,0,0,.94); display:none; align-items:center; justify-content:center; cursor:zoom-out; z-index:9; }}
#lb img {{ max-width:96vw; max-height:94vh; }} #lb.on {{ display:flex; }}
@media (max-width:700px) {{ table {{ font-size:12px; }} }}
</style></head><body>
<header><h1>Phylactery: visual identity, round 94, references</h1>
<p>Purpose: put every source for the store art and the logo side by side, so you can pick which ones (and which of their properties) govern the next round.
Nothing here is made yet. Answer by codes: "A04 for the flat field, S12's diagonal, F07 for the lettering; not T03".</p>
<p>{nn} named + {sum(counts.values())} found ({', '.join(f'{p}: {n}' for p, n in counts.items())}). Click any image to enlarge.</p></header>
<nav>{nav}</nav>
{steam.replace('<table>', '<div class="tablewrap"><table>').replace('</table>', '</table></div>')}
{named}
{''.join(parts)}
{asks}
<div id="lb"><img alt=""></div>
<script>
const lb=document.getElementById('lb'), li=lb.querySelector('img');
document.addEventListener('click',e=>{{ if(e.target.tagName==='IMG'&&e.target.closest('figure')){{ li.src=e.target.src; lb.classList.add('on'); }} else if(e.target.closest('#lb')) lb.classList.remove('on'); }});
document.addEventListener('keydown',e=>{{ if(e.key==='Escape') lb.classList.remove('on'); }});
</script></body></html>'''


if __name__ == '__main__':
    s = page()
    open(OUT, 'w', encoding='utf-8').write(s)
    print(OUT, f'{len(s)/1e6:.1f} MB')
