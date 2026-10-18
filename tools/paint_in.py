"""paint_in.py -- put the game's own render of a thing into a painting, in the painting's own colours
(Phylactery 20, 2026-10-18). The image model repaints whatever it is given (it turned his mask into a face twice), so the
things that must be exact come from the game: the shape and the shading are the render's, the colours are the painting's.

    python tools/paint_in.py <painting.png> <cutout.png> <out.png> --at cx cy --length px [--rot deg]
        [--ramp-from painting_with_its_own_version.png --ramp-box x0 y0 x1 y1 --ramp-min L]
        [--shadow r g b] [--glow strength] [--soft px] [--cast dx dy strength]

--ramp-from: the painting as the model first painted it, with ITS version of the thing: that version's pixels (inside
--ramp-box, brighter than --ramp-min) give the colour for every brightness, darkest to brightest; the render's own
shading is mapped onto that ramp. Without it the render keeps its colours. --glow adds the faint warm light the
paintings put round lit things.
"""
import argparse
import numpy as np
from PIL import Image, ImageFilter


def ramp_from(path, box, lmin, shadow):
    im = np.asarray(Image.open(path).convert('RGB')).astype(np.float32) / 255
    x0, y0, x1, y1 = box
    reg = im[y0:y1, x0:x1].reshape(-1, 3)
    L = reg.mean(-1)
    sel = L > lmin
    L, C = L[sel], reg[sel]
    qs = np.quantile(L, np.linspace(0.02, 0.995, 13))
    ramp = [C[(L >= qs[i]) & (L <= qs[i + 1])].mean(0) for i in range(12)]
    sh = np.array(shadow, np.float32)
    return np.vstack([sh, (sh + ramp[0]) / 2, ramp])


def thing_size(px):
    return (px.shape[1], px.shape[0])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('painting'); ap.add_argument('cutout'); ap.add_argument('out')
    ap.add_argument('--at', type=float, nargs=2, required=True)
    ap.add_argument('--length', type=float, required=True, help='the cut-out\'s width after rotation, in painting pixels')
    ap.add_argument('--rot', type=float, default=0)
    ap.add_argument('--ramp-from'); ap.add_argument('--ramp-box', type=int, nargs=4); ap.add_argument('--ramp-min', type=float, default=0.62)
    ap.add_argument('--shadow', type=float, nargs=3, default=[0.36, 0.24, 0.14])
    ap.add_argument('--glow', type=float, default=0.22)
    ap.add_argument('--soft', type=float, default=0.7)
    ap.add_argument('--depth', type=float, default=1.3)
    ap.add_argument('--range', type=float, default=0.6)
    ap.add_argument('--texture-from'); ap.add_argument('--texture-box', type=int, nargs=4); ap.add_argument('--texture', type=float, default=0.8)
    ap.add_argument('--cast', type=float, nargs=3, help='dx dy strength: a soft shadow of it on the painting behind')
    a = ap.parse_args()

    m = Image.open(a.cutout).convert('RGBA')
    if a.rot:
        m = m.rotate(a.rot, expand=True, resample=Image.BICUBIC)
    k = a.length / m.size[0]
    m = m.resize((round(m.size[0] * k), round(m.size[1] * k)), Image.LANCZOS)
    px = np.asarray(m).astype(np.float32) / 255
    if a.ramp_from:
        ramp = ramp_from(a.ramp_from, a.ramp_box, a.ramp_min, a.shadow)
        Lm = px[..., :3].mean(-1)
        sel = px[..., 3] > 0.5
        lo, hi = np.percentile(Lm[sel], 1), np.percentile(Lm[sel], 99.7)
        # the render's shading stretched, then laid on the top --range of the painting's ramp (porcelain stays light);
        # --depth > 1 deepens the shadows within it
        t = 1 - a.range + a.range * np.clip((Lm - lo) / (hi - lo + 1e-6), 0, 1) ** a.depth
        idx = t * (len(ramp) - 1)
        i0 = np.floor(idx).astype(int); i1 = np.minimum(i0 + 1, len(ramp) - 1); f = (idx - i0)[..., None]
        px[..., :3] = ramp[i0] * (1 - f) + ramp[i1] * f
    if a.texture_from:
        # the brush grain of the painting's own version (its high frequencies only, no shapes) laid onto the render
        x0, y0, x1, y1 = a.texture_box
        src = np.asarray(Image.open(a.texture_from).convert('L').crop((x0, y0, x1, y1)).resize(thing_size(px), Image.LANCZOS)).astype(np.float32) / 255
        hp = src - np.asarray(Image.fromarray((src * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.2))).astype(np.float32) / 255
        px[..., :3] = np.clip(px[..., :3] + hp[..., None] * a.texture, 0, 1)
    thing = Image.fromarray((px * 255 + 0.5).clip(0, 255).astype(np.uint8), 'RGBA')
    if a.soft:
        thing = thing.filter(ImageFilter.GaussianBlur(a.soft))
    base = Image.open(a.painting).convert('RGB')
    ox, oy = round(a.at[0] - thing.size[0] / 2), round(a.at[1] - thing.size[1] / 2)
    if a.cast:
        # its shadow on what is behind it: the silhouette moved by (dx, dy), blurred, darkening the painting
        dx, dy, st = a.cast
        al = Image.new('L', base.size, 0); al.paste(thing.split()[3], (ox + round(dx), oy + round(dy)))
        g = np.asarray(al.filter(ImageFilter.GaussianBlur(max(4, a.length * 0.05)))).astype(np.float32)[..., None] / 255
        B = np.asarray(base).astype(np.float32) / 255
        base = Image.fromarray((np.clip(B * (1 - g * st), 0, 1) * 255 + 0.5).astype(np.uint8))
    if a.glow:
        al = Image.new('L', base.size, 0); al.paste(thing.split()[3], (ox, oy))
        g = np.asarray(al.filter(ImageFilter.GaussianBlur(max(8, a.length * 0.19)))).astype(np.float32)[..., None] / 255
        B = np.asarray(base).astype(np.float32) / 255
        base = Image.fromarray((np.clip(B + g * np.array([0.9, 0.55, 0.22]) * a.glow, 0, 1) * 255 + 0.5).astype(np.uint8))
    out = base.convert('RGBA')
    out.alpha_composite(thing, (ox, oy))
    out.convert('RGB').save(a.out)
    print(a.out, 'placed at', ox, oy, thing.size)


if __name__ == '__main__':
    main()
