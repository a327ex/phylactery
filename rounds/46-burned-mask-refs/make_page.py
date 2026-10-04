"""Round 46's page: the burned mask's references (real photographs of real fire damage), grouped by
the direction each would take the mask in. Self-contained. Run once from the project root:
python rounds/46-burned-mask-refs/make_page.py"""
import base64, io, json, os
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
REFS = os.path.join(ROOT, 'reference', 'objects', 'fire', 'burned-refs')
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'index.html')
SRC = {s['file']: s for s in json.load(open(os.path.join(REFS, 'sources.json'), encoding='utf-8'))}

def emb(path, w=760, png=False):
    im = Image.open(path).convert('RGB')
    if im.width > w: im = im.resize((w, int(im.height * w / im.width)), Image.LANCZOS)
    b = io.BytesIO()
    if png: im.save(b, 'PNG', optimize=True); mime = 'png'
    else: im.save(b, 'JPEG', quality=86); mime = 'jpeg'
    return 'data:image/%s;base64,%s' % (mime, base64.b64encode(b.getvalue()).decode())

def ref(f, note):
    s = SRC[f]
    num = f.split('-')[0]
    return ('<figure><img src="%s" alt="ref %s"><figcaption><b>%s</b> %s<br><span class="src">%s &middot; <a href="%s">source</a> &middot; %s</span></figcaption></figure>'
            % (emb(os.path.join(REFS, f)), num, num, note, s['what'], s['page_url'], s.get('license_or_rights', 'unknown')))

GROUPS = [
    ('A &middot; SOOTED WHITE', 'The mask stays a white mask; the fire was below it and to one side. Soot climbs from where the flame was and thins out upward in streaks, ending in a ragged tide line over clean white. Thin edges and raised features catch more than the hollows. Nothing burns through. It would read as his mask, the lich\'s white one, with something terrible having happened near it.',
     [('03-white-virgin-statue-crop.jpg', 'soot over the head fading downward in streaks to clean white'),
      ('07-hiroshima-ceramic-child-sooted-face-crop.jpg', 'half the face black, half clean, a soft ragged boundary'),
      ('18-scorched-white-enamel-dryer.jpg', 'white paint through grey haze and brown tide lines to black'),
      ('01-burned-barbie-head-soot-face.jpg', 'a black crust on the face, pale where the eyes were shielded')]),
    ('B &middot; CHARRED', 'The mask was wood and it burned: carbon, black and dull, broken into the cracked blocks of charred wood (the crocodile skin), smaller and glossier where it burned hottest. The thin parts go first: the rim, the edges of the eye slits and the gashes eaten back ragged. Carved relief melts into lumps. The current mask is closest to this, but has no real char pattern and no eaten edges.',
     [('10-burned-carved-pew-end-luebeck.jpg', 'the same carving clean and burned: relief melted into lumps'),
      ('09-burned-carved-crucifix-legs.jpg', 'a carved figure burned away to a ragged end'),
      ('11-char-vs-clean-wood-alligator.jpg', 'blocky char wrapping round a patch of unburned wood'),
      ('12-alligator-char-glossy.jpg', 'glossy polygonal char cells, each split again by finer cracks'),
      ('13-charred-church-steeple-boards.jpg', 'char creeping in from the ends and edges of thin boards')]),
    ('C &middot; PAINT OVER CHAR', 'A white painted (gesso or lacquer) mask over wood: the white layer blisters, browns, lifts and flakes off, and under it the wood is charred black. Patches of white survive where the heat was least, with scorched brown frills round them. Between A and B: it keeps some white, and the burned parts are real char.',
     [('16-burned-icon-hodegetria.jpg', 'a painted panel burned from the top: paint and gilding scorched off into char at the edge'),
      ('17-scorched-white-sheet-under-glass.jpg', 'white burned in from its edges, a brown scorched frill before the black'),
      ('15-soot-covered-portrait-slevogt.jpg', 'a whole painted surface under a grey-black skin, the face still showing'),
      ('14-carbonised-roman-shutters.jpg', 'wood turned to charcoal, its carving still there in black')]),
    ('D &middot; MELTED', 'The mask was something that melts (resin, glaze, plastic): it sags and drips, bubbles and pits. Probably not this mask, but here so the choice is seen.',
     [('19-hiroshima-porcelain-bowl-melted-glaze.jpg', 'glaze still white inside, the rim slumped and crusted'),
      ('21-melted-plastic-bubbled-crust.jpg', 'a pitted, blistered crust'),
      ('22-melted-plastic-sheet-black-saturday.jpg', 'a sheet sagged into long drapes')]),
]
OTHER = [('04-hiroshima-sandstone-buddha-head.jpg', 'a stone face spalled and blackened'), ('05-nagasaki-charred-buddha-1945.jpg', 'a figure in the ruins, its face blackened'),
         ('06-hiroshima-melted-figures-case.jpg', 'the case the child figure (07) is from'), ('08-burnt-gas-mask-memorial.jpg', 'a burnt gas mask (rubber)'),
         ('02-white-virgin-statue-charred-face.jpg', 'the statue of 03, whole'), ('20-hiroshima-molten-roof-tiles.jpg', 'glaze boiled into glassy blobs'),
         ('23-melted-plastic-picnic-table.jpg', 'a table sagged over a fire')]

H = ['''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Burned Mask References</title>
<style>
:root { --bg: #0d0b0a; --fg: #e9dcc4; --dim: #a8987c; --rule: #2a241f; --card: #15120f; --accent: #e0a070; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg: #0d0b0a; } }
:root[data-theme="dark"] { --bg: #0d0b0a; }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 15px/1.55 Georgia, 'Times New Roman', serif; }
main { max-width: 1400px; margin: 0 auto; padding: 28px 16px 64px; }
h1 { font-size: 26px; margin: 0 0 6px; } h2 { font-size: 18px; margin: 0 0 4px; color: var(--accent); font-weight: normal; }
p { margin: 6px 0 10px; max-width: 86ch; } .sub { color: var(--dim); }
section { border-top: 1px solid var(--rule); padding: 18px 0 8px; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 10px; align-items: start; }
figure { margin: 0; background: var(--card); }
figure img { display: block; width: 100%; height: auto; }
figcaption { color: var(--fg); font-size: 13px; padding: 5px 8px 7px; } figcaption b { color: var(--accent); }
.src { color: var(--dim); font-size: 12px; } a { color: var(--dim); }
.now { max-width: 640px; } .now img { image-rendering: pixelated; }
</style></head>
<body><main>
<h1>Lich Survivors &middot; round 46 &middot; the burned mask: what real fire does</h1>
<p class="sub">2026-10-04. References only: nothing is built yet. Real photographs of real fire damage (no burned masks exist among sources; these are the nearest things).</p>
<p>You said the mask looks artificial, as if the damage was not real. The current one is a drawn idea of burning: an even black, soot tongues, blisters. Real burning follows the object: soot climbs from where the flame was, thin edges go first, wood breaks into cracked char, paint lifts. Before rebuilding it, which material is it, and which kind of damage? Pick a direction (A, B, C or D), and point at any photos you want it to look like. The claw gashes and the pierced left eye from your drawing stay unless you say otherwise. They match the lore now: the giant creature\'s claw and the flying insect that went through the prince\'s head.</p>
<section class="now"><h2>Now</h2>''' + '<figure><img src="%s" alt="the mask now"><figcaption>the mask as it is (round 35), in the viewer</figcaption></figure>' % emb(os.path.join(ROOT, 'scratch', 'r45', 's0_c_accept.png'), 640, True) + '</section>']
for title, text, refs in GROUPS:
    H.append('<section><h2>%s</h2><p>%s</p><div class="grid">%s</div></section>' % (title, text, ''.join(ref(f, n) for f, n in refs)))
H.append('<section><h2>Also found</h2><div class="grid">%s</div></section>' % ''.join(ref(f, n) for f, n in OTHER))
H.append('</main></body></html>')
open(OUT, 'w', encoding='utf-8').write(''.join(H))
print('wrote', OUT, os.path.getsize(OUT) // 1024, 'KB')
