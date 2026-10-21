# The /artifacts banner (2026-10-21, the owner: "Phylactery gets a big spot at the top with the big image we made for
# Steam, with the title being the small font size version of it in an appropriate place of the image"): the library
# hero (identity/store, no words) cut to 2.4:1 around him, the small title (spaced capitals, tools/title.py, as on the
# event header) top-left, sized to read at the page's ~900 px column (the image is 2x that).
import os, sys
from PIL import Image
GAME = 'C:/Users/a327e/Desktop/a327ex/lich-survivors'
sys.path.insert(0, os.path.join(GAME, 'tools'))
from title import wordmark, lay
hero = Image.open(os.path.join(GAME, 'identity/store/library-hero-A01-3840x1240.png')).convert('RGB')
W, H = hero.size
cw = round(H * 2.4)
x0 = (W - cw) // 2
im = hero.crop((x0, 0, x0 + cw, H)).resize((1800, 750), Image.LANCZOS)
wm = wordmark('PHYLACTERY', round(1800 * 0.25), tracking=0.14)
w, h = wm.size
out = lay(im, wm, at=(round(0.045 * 1800), round(0.12 * 750 - h / 2)), scrim=1.0)[0].convert('RGB')
dst = sys.argv[1]
out.save(dst, 'JPEG', quality=86, optimize=True, progressive=True)
print('saved', dst, out.size, os.path.getsize(dst) // 1024, 'KB; title', w, 'x', h, 'px (at 900 wide:', w // 2, 'x', h // 2, ')')
# (usage: python tools/artifacts_banner.py <a327ex-site>/media/pages/artifacts/phylactery.jpg; a changed image takes a new name: Cloudflare keeps /media/ 7 days)
