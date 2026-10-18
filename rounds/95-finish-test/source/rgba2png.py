"""rgba2png.py <folder> [w h]: every <name>.rgba read back from the GPU (GL rows bottom-up) -> <name>.png; plus sheet.jpg"""
import os, sys, glob
from PIL import Image

d = sys.argv[1]
ims = []
for f in sorted(glob.glob(os.path.join(d, '*.rgba'))):
    raw = open(f, 'rb').read()
    n = len(raw) // 4
    w = int(sys.argv[2]) if len(sys.argv) > 2 else None
    if w is None:
        for sc in (1, 2, 3, 4, 5, 6, 8):
            if 640*sc*360*sc == n:
                w, h = 640*sc, 360*sc
                break
    else:
        h = int(sys.argv[3])
    im = Image.frombytes('RGBA', (w, h), raw).transpose(Image.FLIP_TOP_BOTTOM).convert('RGB')
    p = f[:-5] + '.png'
    im.save(p)
    ims.append((os.path.basename(p), im))
if ims:
    tw = 480
    th = round(tw * ims[0][1].size[1] / ims[0][1].size[0])
    cols = 4
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new('RGB', (tw*cols, (th + 16)*rows), (20, 20, 20))
    from PIL import ImageDraw
    dr = ImageDraw.Draw(sheet)
    for i, (n, im) in enumerate(ims):
        x, y = (i % cols)*tw, (i // cols)*(th + 16)
        sheet.paste(im.resize((tw, th)), (x, y))
        dr.text((x + 4, y + th + 2), n, fill=(255, 220, 120))
    sheet.save(os.path.join(d, 'sheet.jpg'), quality=85)
print(len(ims), 'converted')
