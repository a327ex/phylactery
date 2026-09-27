# tile.py -- tile PNGs into one contact sheet (each scaled by --scale, labelled with its name)
#   python tools/tile.py out.png a.png b.png ... [--cols 3] [--scale 0.5]
import sys
from PIL import Image, ImageDraw

args = sys.argv[1:]
cols, scale = 3, 0.5
if '--cols' in args:
    i = args.index('--cols'); cols = int(args[i + 1]); del args[i:i + 2]
if '--scale' in args:
    i = args.index('--scale'); scale = float(args[i + 1]); del args[i:i + 2]
out, files = args[0], args[1:]
ims = [Image.open(f).convert('RGB') for f in files]
w, h = int(ims[0].width*scale), int(ims[0].height*scale)
rows = (len(ims) + cols - 1)//cols
sheet = Image.new('RGB', (cols*w, rows*(h + 14)), (12, 11, 10))
d = ImageDraw.Draw(sheet)
for k, (im, f) in enumerate(zip(ims, files)):
    x, y = (k % cols)*w, (k//cols)*(h + 14)
    sheet.paste(im.resize((w, h), Image.NEAREST), (x, y + 14))
    d.text((x + 4, y + 1), f.replace('\\', '/').split('/')[-1], fill=(220, 200, 160))
sheet.save(out)
print(out, sheet.size)
