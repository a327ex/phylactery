"""prep.py: round 96's finishing jobs. Crops each 4x staging to its slots' shapes, cuts the mask reference, writes one
prompt per composition (the P3 recipe) and jobs.json for tools/gemini_image.py. Run from lich-survivors/."""
import json, os, shutil
import numpy as np
from PIL import Image

D = 'scratch/s20/r96'
HI, FIN = f'{D}/hi', f'{D}/finish'
os.makedirs(FIN, exist_ok=True)
shutil.copy('rounds/95-finish-test/files/P3-nbpro_d_painted_ref.png', f'{FIN}/style_p3.png')
shutil.copy('reference/identity/named/it-follows-egg.jpg', f'{FIN}/style_it_follows.jpg')

RATIO = {'2:3': 2/3, '4:5': 4/5, '16:9': 16/9, '21:9': 21/9, '1:1': 1.0}


def crop(im, ratio, cx, cy=0.5):
    W, H = im.size
    if W / H > ratio:
        h, w = H, round(H * ratio)
    else:
        w, h = W, round(W / ratio)
    x0 = int(min(max(cx * W - w / 2, 0), W - w))
    y0 = int(min(max(cy * H - h / 2, 0), H - h))
    return im.crop((x0, y0, x0 + w, y0 + h))


def mask_ref(name):
    b = np.asarray(Image.open(f'{HI}/{name}_black.png').convert('L')).astype(int)
    l = np.asarray(Image.open(f'{HI}/{name}_lich.png').convert('L')).astype(int)
    ys, xs = np.where((b - l) > 25)
    x0, y0, x1, y1 = xs.min(), ys.min(), xs.max(), ys.max()
    pad = int(max(x1 - x0, y1 - y0) * 0.6)
    im = Image.open(f'{HI}/{name}.png').crop((x0 - pad, y0 - pad, x1 + pad, y1 + pad))
    im = im.resize((512, round(512 * im.size[1] / im.size[0])), Image.LANCZOS)
    p = f'{FIN}/{name}_mask_ref.png'
    im.save(p)
    return os.path.basename(p)


STYLE = ("Repaint image 1 as an oil painting in the style of image 2 (the finished painting this series follows) and image 3 "
         "(the style source behind it): a dark warm umber-black ground falling to near-black at the edges, a soft amber glow "
         "behind the subject, warm golden light from above, deep shadows, visible confident brushwork, aged real materials. "
         "Do not take the subjects of images 2 and 3, their cave, their egg or their text; only their painting. Keep image 1's "
         "exact composition, camera and proportions. ")
MASK = ("The mask is exactly like the one in image 4: a blank, closed, smooth white porcelain shell with a rounded brow and "
        "a pointed chin, only a faint nose ridge: NO eye holes, no carved or painted eyes, no mouth, no openings. ")
END = "No text, no letters, no frame; the whole image edge to edge is one painting."

COMPS = {
    'a02': dict(src='a02', mask=True, cx=0.56, slots=['2:3', '4:5'],
                subject="Subject: a human skeleton seen from the chest up, its head bowed forward and down on a bent neck; "
                        "a blank white porcelain mask floats just in front of its face, held there by no hands; above the head "
                        "floats a thin round glass lens laid flat like a halo, its rim catching the light: the one bright accent. "),
    'a01': dict(src='a01', mask=True, cx=0.47, slots=['16:9', '4:5'],
                subject="Subject: a human skeleton floating in the air, arched backwards, head thrown back, one arm flung out "
                        "with an open clawed hand, the other hanging down, legs together and toes pointed down; a blank white "
                        "porcelain mask floats just in front of its face. "),
    'a10': dict(src='a10', mask=False, cx=0.5, cy=0.55, slots=['21:9', '16:9'],
                subject="Subject: a vast dark cave; a single shaft of sunlight falls from far above onto a pool of light on the "
                        "rocky floor; a small floating skeleton with a white mask before its face hangs in the air in that light, "
                        "legs together, arms at its sides; a pale egg rests on the floor in front of it; everything else falls "
                        "into darkness. Keep the figure small. "),
    'a04': dict(src='a04', mask=False, rotate=90, cx=0.39, cy=0.6, slots=['16:9', '1:1'],
                subject="Subject: a skeletal hand, old real bone, fingers spread and curled like claws, pointing upward, seen "
                        "close against darkness; at the tip of each finger burns a small different light: a flame, a prismatic "
                        "spark, a hot white point of focused light, a wisp of shimmering warped air. "),
    't41': dict(src='t41', mask=False, cx=0.5, slots=['2:3', '4:5'],
                subject="Subject: a single pale egg standing on a dark rocky cave floor, lit from directly above by a narrow "
                        "shaft of golden light, the egg glowing softly, everything around it falling to black. "),
    's15': dict(src='s15', mask=False, cx=0.5, slots=['21:9', '16:9'],
                subject="Subject: a still life on a cave floor in a pool of warm light, in the manner of a vanitas: a bronze "
                        "votive hand lying on its side, a flat round glass lens, a charred black porcelain mask, a raw prismatic "
                        "gem, a dark weathered lodestone, a few small clear glass orbs, and a pale egg standing behind them; deep "
                        "darkness around. "),
}

jobs = []
for name, c in COMPS.items():
    im = Image.open(f'{HI}/{c["src"]}.png').convert('RGB')
    if c.get('rotate'):
        im = im.rotate(c['rotate'], expand=True)
    mref = mask_ref(c['src']) if c['mask'] else None
    prompt = STYLE + c['subject'] + (MASK if mref else '') + END
    pf = f'p_{name}.txt'
    open(f'{FIN}/{pf}', 'w', encoding='utf-8').write(prompt + '\n')
    for slot in c['slots']:
        tag = slot.replace(':', 'x')
        pl = crop(im, RATIO[slot], c['cx'], c.get('cy', 0.5))
        pl.thumbnail((1600, 1600), Image.LANCZOS)
        pn = f'{name}_{tag}_plate.png'
        pl.save(f'{FIN}/{pn}')
        imgs = [pn, 'style_p3.png', 'style_it_follows.jpg'] + ([mref] if mref else [])
        jobs.append({'key': f'{name}_{tag}', 'images': imgs, 'prompt_file': pf, 'aspect': slot})
json.dump({'models': {'nbpro': {'id': 'gemini-3-pro-image', 'size': '2K'}}, 'jobs': jobs}, open(f'{FIN}/jobs.json', 'w'), indent=1)
print(len(jobs), 'jobs')
