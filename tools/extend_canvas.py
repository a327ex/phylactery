#!/usr/bin/env python3
"""extend_canvas.py -- a painting set on a bigger canvas, its own dark ground continued into the margins (Phylactery
20, 2026-10-18). The image model repainted the figure when asked to fill margins (a second, bigger skeleton), so the
margins are made here and nothing can appear in them: the painting's colours carried outward (push-pull fill),
darkened with the distance as its own ground darkens, its own brush grain laid over (a high-pass of a figure-free patch,
tiled with mirroring), the painting itself kept pixel for pixel with a soft seam.

    python tools/extend_canvas.py painting.png out.png --canvas W H --box x y w h --grain x0 y0 x1 y1
        [--dark r g b] [--fade 0.35] [--seam 60] [--grain-amp 1.0]
"""
import argparse
import numpy as np
from scipy import ndimage
from PIL import Image, ImageFilter


def pushpull(img, mask):
    """fill where mask == 0 from the coarser levels of a mask-weighted pyramid"""
    levels = [(img * mask[..., None], mask)]
    while min(levels[-1][1].shape) > 2:
        c, w = levels[-1]
        h, wd = (c.shape[0] // 2) * 2, (c.shape[1] // 2) * 2
        c, w = c[:h, :wd], w[:h, :wd]
        c2 = c[0::2, 0::2] + c[1::2, 0::2] + c[0::2, 1::2] + c[1::2, 1::2]
        w2 = w[0::2, 0::2] + w[1::2, 0::2] + w[0::2, 1::2] + w[1::2, 1::2]
        levels.append((c2, w2))
    filled = levels[-1][0] / np.maximum(levels[-1][1], 1e-6)[..., None]
    for c, w in reversed(levels[:-1]):
        ups = [np.asarray(Image.fromarray(filled[..., k].astype(np.float32)).resize((c.shape[1], c.shape[0]), Image.BILINEAR)) for k in range(3)]
        up = np.dstack(ups)
        own = c / np.maximum(w, 1e-6)[..., None]
        a = np.clip(w, 0, 1)[..., None]
        filled = own * a + up * (1 - a)
    return filled


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('painting'); ap.add_argument('out')
    ap.add_argument('--canvas', type=int, nargs=2, required=True)
    ap.add_argument('--box', type=int, nargs=4, required=True, help='where the painting goes: x y w h')
    ap.add_argument('--grain', type=int, nargs=4, required=True, help='a figure-free patch of the painting (its own pixels)')
    ap.add_argument('--dark', type=float, nargs=3, default=[0.045, 0.030, 0.022])
    ap.add_argument('--fade', type=float, default=0.35, help='how far (in canvas heights) the ground darkens to --dark')
    ap.add_argument('--seam', type=int, default=180)
    ap.add_argument('--grain-amp', type=float, default=1.0)
    ap.add_argument('--grain-sigma', type=float, default=30, help='the grain keeps the painting strokes up to this size (px)')
    ap.add_argument('--smooth', type=float, default=0.05, help='blur of the carried colours (canvas heights): no streaks')
    a = ap.parse_args()
    W, H = a.canvas
    x, y, w, h = a.box
    src = Image.open(a.painting).convert('RGB')
    p = src.resize((w, h), Image.LANCZOS)
    P = np.asarray(p).astype(np.float32) / 255
    canvas = np.zeros((H, W, 3), np.float32)
    mask = np.zeros((H, W), np.float32)
    # the painting's low frequencies only, a band at its edges, feed the fill (not the figure)
    low = np.asarray(p.filter(ImageFilter.GaussianBlur(max(8, h // 60)))).astype(np.float32) / 255
    band = np.zeros((h, w), np.float32)
    b = max(24, h // 25)
    band[:b, :] = 1; band[-b:, :] = 1; band[:, :b] = 1; band[:, -b:] = 1
    sx0, sy0 = max(0, -x), max(0, -y)
    sx1, sy1 = min(w, W - x), min(h, H - y)
    canvas[y + sy0:y + sy1, x + sx0:x + sx1] = low[sy0:sy1, sx0:sx1]
    mask[y + sy0:y + sy1, x + sx0:x + sx1] = band[sy0:sy1, sx0:sx1]
    fill = pushpull(canvas, mask)
    sm = max(1, a.smooth * H)
    fill = np.dstack([ndimage.gaussian_filter(fill[..., k], sm) for k in range(3)])
    # darken with the distance from the painting, as its own ground darkens toward its edges
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    dx = np.maximum(np.maximum(x - xx, xx - (x + w)), 0)
    dy = np.maximum(np.maximum(y - yy, yy - (y + h)), 0)
    d = np.hypot(dx, dy) / H
    t = (1 - np.exp(-d / a.fade))[..., None]
    fill = fill * (1 - t) + np.array(a.dark, np.float32) * t
    # its own grain: a high-pass of the figure-free patch, tiled with mirroring
    g0 = src.crop(tuple(a.grain)).convert('L').resize((round((a.grain[2] - a.grain[0]) * w / src.size[0]), round((a.grain[3] - a.grain[1]) * h / src.size[1])), Image.LANCZOS)
    G = np.asarray(g0).astype(np.float32) / 255
    G = G - np.asarray(g0.filter(ImageFilter.GaussianBlur(a.grain_sigma))).astype(np.float32) / 255
    tile = np.block([[G, G[:, ::-1]], [G[::-1, :], G[::-1, ::-1]]])
    reps = (H // tile.shape[0] + 1, W // tile.shape[1] + 1)
    grain = np.tile(tile, reps)[:H, :W]
    out = np.clip(fill + grain[..., None] * a.grain_amp * (0.6 + 0.4 * fill.mean(-1, keepdims=True) / 0.2), 0, 1)
    # the painting, kept, a soft seam only on the sides that meet a margin
    al = np.ones((h, w), np.float32)
    s = a.seam
    ramp = np.clip(np.arange(max(w, h)) / s, 0, 1)
    if x > 0: al *= ramp[:w][None, :]
    if x + w < W: al *= ramp[:w][::-1][None, :]
    if y > 0: al *= ramp[:h][:, None]
    if y + h < H: al *= ramp[:h][::-1][:, None]
    reg = out[y + sy0:y + sy1, x + sx0:x + sx1]
    A = al[sy0:sy1, sx0:sx1][..., None]
    out[y + sy0:y + sy1, x + sx0:x + sx1] = P[sy0:sy1, sx0:sx1] * A + reg * (1 - A)
    Image.fromarray((out * 255 + 0.5).astype(np.uint8)).save(a.out)
    print(a.out, (W, H))


if __name__ == '__main__':
    main()
