"""Round 48's page: pictures embedded, the clip beside it (throw.mp4).
python rounds/48-throw/make_page.py [clip_src out.html]"""
import base64, io, os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
SRC = os.path.join(ROOT, 'scratch', 'r48')
clip_src = sys.argv[1] if len(sys.argv) > 1 else 'throw.mp4'
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, 'index.html')

def img(path, cap, crop=None, w=None, nearest=False):
    im = Image.open(os.path.join(SRC, path)).convert('RGB')
    if crop: im = im.crop(crop)
    if w: im = im.resize((w, int(im.height*w/im.width)), Image.NEAREST if nearest else Image.LANCZOS)
    b = io.BytesIO(); im.save(b, 'PNG', optimize=True)
    return '<figure><img src="data:image/png;base64,%s" alt="%s"><figcaption>%s</figcaption></figure>' % (base64.b64encode(b.getvalue()).decode(), cap.replace('"', ''), cap)

H = ['''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lich Survivors Throw</title>
<style>
:root { --bg: #0d0b0a; --fg: #e9dcc4; --dim: #a8987c; --rule: #2a241f; --card: #15120f; --accent: #e0a070; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg: #0d0b0a; } }
:root[data-theme="dark"] { --bg: #0d0b0a; }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.55 Georgia, 'Times New Roman', serif; }
main { max-width: 1100px; margin: 0 auto; padding: 22px 14px 64px; }
h1 { font-size: 23px; margin: 0 0 6px; } h2 { font-size: 18px; margin: 0 0 6px; color: var(--accent); font-weight: normal; }
p { margin: 6px 0 10px; } .sub { color: var(--dim); }
section { border-top: 1px solid var(--rule); padding: 16px 0 6px; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 8px; }
figure { margin: 0; background: var(--card); }
figure img, video { display: block; width: 100%; height: auto; }
figure img.px { image-rendering: pixelated; }
figcaption { color: var(--dim); font-size: 14px; padding: 4px 8px 6px; }
</style></head>
<body><main>
<h1>Lich Survivors &middot; round 48 &middot; only the egg cave; THROW</h1>
<p class="sub">2026-10-05. Anchor build, headless.</p>
<p>The egg cave is the whole game: he starts there with all six, under the one room camera. The tunnel, the rooms and the door are gone (kept in archive/). The objects have their titles. The viewer has one button, THROW: he throws the object the way he is facing as the viewer goes, and walking back to it makes it his again. The icons now show each object in its own colours.</p>
<section><h2>THROW, and back</h2>
<video controls playsinline preload="metadata" src="''' + clip_src + '''"></video>
<p>The gem's viewer, THROW: it flies off the way he faces (as far as the floor stays clear, up to about 6.5 m, never onto the egg), lands and rolls. He walks to it and it is his again: its slot fills and the power comes back. A thrown object can be taken back once it has been 1.8 m from him, or after it has lain still 2.5 s, so a throw into a wall at his feet doesn't come straight back. Esc puts the viewer away without throwing.</p></section>''']
H.append('<section><h2>The titles, the one button</h2><div class="grid">' + img('viewer_gem.png', 'PRISMATIC GEM') + img('viewer_orbs.png', 'PSYONIAN ORBS (the markings: ETCHED)') + img('b_viewer.png', 'BURNED MASK') + '</div><p>BURNED MASK, THE HAND, LODESTONE, PSYONIAN ORBS, PRISMATIC GEM, ATTACK LENS.</p></section>')
H.append('<section><h2>The icons: which is which</h2><p>EMBER\'s silhouettes were dark shapes of similar size, so the lodestone, gem and lens read alike. Now each is in its own colours with its inner detail, in EMBER\'s warm rim light and outlined against the lamp\'s glow: the white mask with its sooted half, a bone hand, a rust lodestone, glass balls, the coloured gem, the glass lens. F2 still cycles to the silhouettes.</p><div class="grid">')
H.append('<figure><img class="px" src="data:image/png;base64,%s" alt="sheet"><figcaption>top: before (EMBER silhouettes); middle: now (LIT); bottom: LIT under the pointer</figcaption></figure>' % base64.b64encode(open(os.path.join(SRC, 'icons_sheet3.png'), 'rb').read()).decode())
H.append(img('inv_sheet.png', 'in the game, top right (4x): as they rest; the lodestone under the pointer', nearest=True))
H.append('</div></section>')
H.append('''<section><h2>Next session (your words, kept)</h2><p>"The snake spawning needs to be improved, currently snakes are spawning all at the same time often, and the order of attacks that the lich does repeats predictably. We want to solve this by varying snake spawns, and also by sometimes making the lich repeat attacks. Like sometimes he should choose to handle all snakes at the same time using the same attack, sometimes a mix of 2 attacks, sometimes a mix of 3, and sometimes he just rotates randomly. When choosing to kill multiple snakes (3 or more) with the same attack we should do special animations. So a 4 snake prismatic beam should feel like four revolver shots in sequence where he turns to each and then fires, lifting four snakes should pull them together and then he gores them all at the same time, etc, etc."</p></section>
<section><h2>Checked</h2><p class="sub">Headless: the start (in the room, all six), the viewer and THROW for the mask, gem and orbs, the landing, the walk back and the pickup. The room's digest run is byte-identical to the last verified commit, and the static check is clean.</p></section>
</main></body></html>''')
open(OUT, 'w', encoding='utf-8').write(''.join(H))
print('wrote', OUT, os.path.getsize(OUT)//1024, 'KB')
