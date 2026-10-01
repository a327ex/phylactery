"""glcap_compare.py <capture dir> -- the port to Anchor: three.js's frame (ref_*) against the
Anchor replay of it (anchor_*): statistics, and ref / anchor / difference images side by side."""
import sys, os
import numpy as np
from PIL import Image

d = sys.argv[1]
W, H = 640, 360
def rgba8(name):
    a = np.frombuffer(open(os.path.join(d, name), 'rb').read(), np.uint8).reshape(H, W, 4)
    return a[::-1]                                   # GL rows are bottom-up
ref = rgba8('ref_final_rgba8.bin').astype(int)
anc = rgba8('anchor_final_rgba8.bin').astype(int)
diff = np.abs(ref[..., :3] - anc[..., :3])
m = diff.max(axis=2)
print(f'final 8-bit: mean |d| {diff.mean():.3f}, max {m.max()}, pixels off by >1: {(m > 1).mean()*100:.2f}%, >4: {(m > 4).mean()*100:.2f}%, >16: {(m > 16).mean()*100:.2f}%')
if os.path.exists(os.path.join(d, 'anchor_world_f32.bin')):
    rw = np.frombuffer(open(os.path.join(d, 'ref_world_rgba16f.bin'), 'rb').read(), np.uint16).view(np.float16).astype(np.float32).reshape(H, W, 4)[::-1]
    aw = np.frombuffer(open(os.path.join(d, 'anchor_world_f32.bin'), 'rb').read(), np.float32).reshape(H, W, 4)[::-1]
    dw = np.abs(rw[..., :3] - aw[..., :3])
    rel = dw/np.maximum(np.abs(rw[..., :3]), 1e-3)
    print(f'world HDR: mean |d| {dw.mean():.5f} (ref mean {rw[..., :3].mean():.4f}), max {dw.max():.4f}, pixels with relative error >1%: {(rel.max(axis=2) > 0.01).mean()*100:.2f}%, >10%: {(rel.max(axis=2) > 0.1).mean()*100:.2f}%')
vis = np.clip(m*8, 0, 255).astype(np.uint8)
row = np.concatenate([ref[..., :3].astype(np.uint8), anc[..., :3].astype(np.uint8), np.stack([vis]*3, axis=2)], axis=1)
Image.fromarray(row).save(os.path.join(d, 'compare.png'))
print('compare.png: three.js | Anchor | difference x8')
