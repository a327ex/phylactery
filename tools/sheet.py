# Contact sheet: python sheet.py out.png frame1.png frame2.png ...  (4 columns, frames at half size, labelled)
import sys
from PIL import Image, ImageDraw

out, files = sys.argv[1], sys.argv[2:]
if not files:
    sys.exit(0)
imgs = [Image.open(f).convert('RGB') for f in files]
w, h = imgs[0].size
tw, th = w // 2, h // 2
cols = min(4, len(imgs))
rows = (len(imgs) + cols - 1) // cols
sheet = Image.new('RGB', (cols * tw, rows * th), (20, 20, 20))
d = ImageDraw.Draw(sheet)
for i, im in enumerate(imgs):
    x, y = (i % cols) * tw, (i // cols) * th
    sheet.paste(im.resize((tw, th), Image.NEAREST), (x, y))
    d.rectangle([x, y, x + 22, y + 14], fill=(0, 0, 0))
    d.text((x + 3, y + 2), str(i), fill=(255, 255, 0))
sheet.save(out)
