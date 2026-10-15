import sys, os
from PIL import Image, ImageChops
a, b = sys.argv[1], sys.argv[2]
tot = 0
for f in sorted(os.listdir(a)):
    if not f.endswith('.png'): continue
    ia, ib = Image.open(os.path.join(a, f)).convert('RGB'), Image.open(os.path.join(b, f)).convert('RGB')
    d = ImageChops.difference(ia, ib)
    bbox = d.getbbox()
    px = sum(1 for p in d.getdata() if p != (0, 0, 0)) if bbox else 0
    mx = max(max(p) for p in d.getdata()) if bbox else 0
    tot += px
    print('%s: %s' % (f, 'identical' if not bbox else '%d pixels differ, max %d' % (px, mx)))
print('total differing pixels: %d' % tot)
