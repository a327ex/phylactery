"""cutout.py -- the game's own render of a thing, cut out with exact alpha (Phylactery 20, 2026-10-18).

Two read-backs of the same instant from tools/store_stage.lua, one on a black field and one on a white one: where the
thing covers the field both agree, where it doesn't they differ by the field's own difference. alpha = 1 - (W - B)/(Wf - Bf),
colour = B / alpha (un-premultiplied). Output: RGBA PNG cropped to the thing.

    python tools/cutout.py <name>_bk.rgba <name>_wh.rgba <out.png> [--pad 8] [--full]
"""
import argparse
import numpy as np
from PIL import Image


def load(p):
    raw = open(p, 'rb').read()
    n = len(raw) // 4
    for sc in (1, 2, 3, 4, 5, 6, 8):
        if 640 * sc * 360 * sc == n:
            w, h = 640 * sc, 360 * sc
            break
    else:
        raise SystemExit(f'{p}: not a 16:9 read-back')
    return np.asarray(Image.frombytes('RGBA', (w, h), raw).transpose(Image.FLIP_TOP_BOTTOM).convert('RGB'), np.float32) / 255


def cut(bk, wh, pad=8, full=False):
    B, Wt = load(bk), load(wh)
    bf, wf = B[2, 2], Wt[2, 2]                       # the two fields as rendered (corners: nothing there)
    span = np.maximum(wf - bf, 1e-3)
    a = np.clip(1 - ((Wt - B) / span).mean(-1), 0, 1)
    a[a < 0.02] = 0
    col = np.where(a[..., None] > 1e-3, np.clip((B - bf * (1 - a[..., None])) / np.maximum(a[..., None], 1e-3), 0, 1), 0)
    rgba = np.dstack([col, a])
    if not full:                                     # (--full: the whole frame, so it lands where the game put it)
        ys, xs = np.where(a > 0.02)
        x0, y0, x1, y1 = max(0, xs.min() - pad), max(0, ys.min() - pad), xs.max() + pad + 1, ys.max() + pad + 1
        rgba = rgba[y0:y1, x0:x1]
    return Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), 'RGBA')


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('bk'); ap.add_argument('wh'); ap.add_argument('out')
    ap.add_argument('--pad', type=int, default=8)
    ap.add_argument('--full', action='store_true')
    a = ap.parse_args()
    im = cut(a.bk, a.wh, a.pad, a.full)
    im.save(a.out)
    print(a.out, im.size)
