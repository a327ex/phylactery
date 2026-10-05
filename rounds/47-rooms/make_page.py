"""Round 47's page: pictures embedded, the two videos beside it (run.mp4, held_mask.mp4).
python rounds/47-rooms/make_page.py [run_src held_src out.html]   (defaults: the local folder's names)"""
import base64, io, os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
SRC = os.path.join(ROOT, 'scratch', 'r47')
run_src, held_src = (sys.argv[1], sys.argv[2]) if len(sys.argv) > 2 else ('run.mp4', 'held_mask.mp4')
OUT = sys.argv[3] if len(sys.argv) > 3 else os.path.join(HERE, 'index.html')

def img(path, cap, crop=None, w=None):
    im = Image.open(os.path.join(SRC, path)).convert('RGB')
    if crop: im = im.crop(crop)
    if w and im.width > w: im = im.resize((w, int(im.height*w/im.width)), Image.LANCZOS)
    b = io.BytesIO(); im.save(b, 'JPEG', quality=88)
    return '<figure><img src="data:image/jpeg;base64,%s" alt="%s"><figcaption>%s</figcaption></figure>' % (base64.b64encode(b.getvalue()).decode(), cap.replace('"', ''), cap)

F = lambda n: os.path.join('frames', '%05d.png' % n)
FR = [int(x) for x in open(os.path.join(SRC, 'stills.txt')).read().split()]   # picked frames, in order

H = ['''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lich Survivors Rooms</title>
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
figcaption { color: var(--dim); font-size: 14px; padding: 4px 8px 6px; }
</style></head>
<body><main>
<h1>Lich Survivors &middot; round 47 &middot; the rooms</h1>
<p class="sub">2026-10-05. Anchor build, headless. Video = a scripted run of the whole game, as the game draws it.</p>
<section><h2>The whole game, start to end (1280x720)</h2>
<video controls playsinline preload="metadata" src="''' + run_src + '''"></video>
<p>No tunnel any more. He wakes in THE HALL. Behind him is a sealed door in the egg room's mouth. The other doorways glow in their rooms' colours: the EMBER ROOM (right, warm) holds the mask and the lens, the GLASS ROOM (left, cool) the orbs and the gem. The hall holds the hand and the lodestone. Every room has one fixed camera high inside it, like the egg room's, all facing the same way. A doorway goes dark once its room is empty. With all six his, the door warms, lights up and sinks. Then the old tube, the egg room, the fight, every power removed, the win, and the camera pushes in on his face before the black.</p></section>''']
caps = ['he wakes in the hall: the door ahead in its arch, a doorway glowing on each side',
        'the ember room', 'the glass room', 'back in the hall with all six: the doorways dark, the door warming',
        'the door sinking', 'open', 'the end: in on his face']
H.append('<section><h2>Stills from the run</h2><div class="grid">' + ''.join(img(F(n), c, w=640) for n, c in zip(FR, caps)) + '</div></section>')
H.append('''<section><h2>His mask, held by his mind</h2>
<video controls playsinline loop preload="metadata" src="''' + held_src + '''"></video>
<p>About 7 cm in front of his face, not on it. It follows the head closely sideways and when he turns, and late up and down. Jolted, it drops and catches up. F5 still cycles WHITE / WHITE MATTE / NONE.</p></section>''')
H.append('<section><h2>The burned mask: soot like the child\'s face</h2><p>It is glazed porcelain now. Nothing is charred, warped or eaten. Soot covers the break\'s half and the bottom edge: black at the core, grey film towards a soft ragged edge, streaks climbing past it, specks beyond. The other half is clean white glaze. The hole is a break with straight fractures, flakes chipped off its front edge, hairline cracks across the glaze, and a wider spall at the back. The gashes cut through the glaze with chipped edges, matte floors and the claw\'s fine scratches. The old blood is kept.</p><div class="grid">')
H.append(img('mask_r35_front.png', 'before (round 35)', crop=(320, 60, 960, 560), w=520) + img('mask_v2c_front.png', 'now', crop=(320, 60, 960, 560), w=520))
H.append(img('mask_v2c_34.png', 'turned', crop=(320, 60, 960, 560), w=520) + img('mask_v2c_back.png', 'the back: the spall round the break', crop=(320, 60, 960, 560), w=520))
H.append(img('mask_v2c_break.png', 'the break, close', w=640) + img('mask_v2c_gashes.png', 'the gashes, close', w=640))
H.append('</div></section>')
H.append('''<section><h2>What to try (run.bat)</h2><p>WASD or hold the mouse. Up the screen is always toward the egg room. F6 jumps to the next object (testing), F8 turns the end push-in off, F5 cycles his mask, F7 the orb markings.</p>
<p class="sub">Not yet: the rooms' rock is meshed coarser than the egg room's (0.75 m facets); the cameras are placed by rule and pulled clear of the rock automatically; the objects are small from up high, and their lamps are what finds them.</p></section>
</main></body></html>''')
open(OUT, 'w', encoding='utf-8').write(''.join(H))
print('wrote', OUT, os.path.getsize(OUT)//1024, 'KB')
