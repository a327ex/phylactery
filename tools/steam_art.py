#!/usr/bin/env python3
"""steam_art.py -- PLACEHOLDER Steam store and library art for the release rehearsal (Phylactery 18, 2026-10-15).

Every image Steam asks for, at its exact size, made from game frames (scratch/s18/shots: 1920x1080 agent captures,
640x360 drawn at 3x) and the title set in the game's own font (FACETED FINE, port/hud_fonts.lua) in the HUD's cream.
They exist so the upload path can be rehearsed; the real key art, logo and screenshots are his calls.
Never the ending in any of them: it is the game's secret.

    python tools/steam_art.py          -> store/steam/{store,library,screenshots,community}/ (git-ignored)
"""
import os
import re
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
SHOTS = os.path.join(GAME, 'scratch', 's18', 'shots')
OUT = os.path.join(GAME, 'store', 'steam')

CREAM = (242, 227, 194)          # port/ui_style.lua CREAM (the hot frame's light)
EMBER = (224, 160, 112)          # the hot slot's edge
SHADOW = (12, 8, 6)

FIGHT = 'fight_t1560.png'        # the fire beams out to both sides of the light: the widest frame of the fight
MASK = 'viewer_0.png'            # the burned mask in the viewer
SCREENSHOTS = ['fight_t1560.png', 'fight_t1240.png', 'fight_t1020.png', 'viewer_0.png', 'viewer_4.png']
TITLE = 'PHYLACTERY'


def font():
    src = open(os.path.join(GAME, 'port', 'hud_fonts.lua'), encoding='utf-8').read()
    a = src.index('facet_fine = {')
    b = src.index('\n  }', a)
    glyphs = {}
    for _, ch, w, px in re.findall(r"\[(['\"])(.)\1\] = \{ w = (\d+), px = \{ ([\d,]*) \} \}", src[a:b]):
        nums = [int(n) for n in px.split(',') if n]
        glyphs[ch] = (int(w), list(zip(nums[0::2], nums[1::2])))
    return glyphs


GLYPHS = font()
FONT_H = 14


def title_mask(text, scale):
    """The title as an L image (255 = ink), one font pixel = scale x scale."""
    w = sum(GLYPHS[c][0] if c in GLYPHS else 6 for c in text)
    im = Image.new('L', (w*scale, FONT_H*scale), 0)
    d = ImageDraw.Draw(im)
    x = 0
    for c in text:
        gw, px = GLYPHS.get(c, (6, []))
        for gx, gy in px:
            d.rectangle([(x + gx)*scale, gy*scale, (x + gx + 1)*scale - 1, (gy + 1)*scale - 1], fill=255)
        x += gw
    return im


def cover(im, size, center=(0.5, 0.5), zoom=1.0):
    """Scale im to cover size (keeping its aspect), times zoom, cropped round center (fractions of im)."""
    W, H = size
    s = max(W/im.width, H/im.height)*zoom
    r = im.resize((max(1, round(im.width*s)), max(1, round(im.height*s))), Image.NEAREST if s >= 1 else Image.LANCZOS)
    cx, cy = center[0]*r.width, center[1]*r.height
    x0 = int(min(max(0, cx - W/2), r.width - W))
    y0 = int(min(max(0, cy - H/2), r.height - H))
    return r.crop((x0, y0, x0 + W, y0 + H))


def vignette(im, strength=0.55):
    W, H = im.size
    m = Image.new('L', (W, H), 0)
    ImageDraw.Draw(m).ellipse([-W*0.15, -H*0.25, W*1.15, H*1.25], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(min(W, H)*0.18))
    dark = ImageEnhance.Brightness(im).enhance(1 - strength)
    return Image.composite(im, dark, m)


def put_title(im, width_frac, y_frac, color=CREAM):
    """The title centred at y_frac, the largest integer scale that fits width_frac of the image."""
    base = title_mask(TITLE, 1)
    scale = max(1, int(im.width*width_frac/base.width))
    m = title_mask(TITLE, scale)
    x = (im.width - m.width)//2
    y = int(im.height*y_frac - m.height/2)
    sh = m.filter(ImageFilter.GaussianBlur(scale*1.5))
    im.paste(Image.new('RGB', m.size, SHADOW), (x, y + scale), sh)
    im.paste(Image.new('RGB', m.size, SHADOW), (x + scale, y + scale), m)
    im.paste(Image.new('RGB', m.size, color), (x, y), m)
    return im


def logo(width):
    """The title alone on transparent, `width` wide (Steam's library logo: 1280 wide)."""
    base = title_mask(TITLE, 1)
    scale = width//base.width
    m = title_mask(TITLE, scale)
    pad = scale*2
    out = Image.new('RGBA', (width, m.height + pad*2), (0, 0, 0, 0))
    x = (width - m.width)//2
    sh = Image.new('RGBA', m.size, SHADOW + (200,))
    out.paste(sh, (x + scale, pad + scale), m)
    out.paste(Image.new('RGBA', m.size, CREAM + (255,)), (x, pad), m)
    return out


def save(im, *parts, quality=None):
    path = os.path.join(OUT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if quality:
        im.convert('RGB').save(path, quality=quality)
    else:
        im.save(path, optimize=True)
    print('%-44s %5dx%-5d %6.0f KB' % (os.path.relpath(path, OUT).replace(os.sep, '/'), im.width, im.height,
                                        os.path.getsize(path)/1e3))


def main():
    fight = Image.open(os.path.join(SHOTS, FIGHT)).convert('RGB')
    mask = Image.open(os.path.join(SHOTS, MASK)).convert('RGB')
    light = (0.5, 0.6)           # the circle of light round the lich and the egg, in the fight frame
    wide = lambda size, zoom=1.0: vignette(cover(fight, size, light, zoom))

    save(put_title(wide((920, 430), 1.25), 0.62, 0.78), 'store', 'header_capsule_920x430.png')
    save(put_title(wide((462, 174), 1.6), 0.86, 0.5), 'store', 'small_capsule_462x174.png')
    save(put_title(wide((1232, 706), 1.15), 0.56, 0.8), 'store', 'main_capsule_1232x706.png')
    save(put_title(vignette(cover(mask, (748, 896), (0.5, 0.45), 1.5)), 0.78, 0.85), 'store', 'vertical_capsule_748x896.png')
    save(ImageEnhance.Brightness(cover(fight, (1438, 810), light)).enhance(0.7), 'store', 'page_background_1438x810.png')

    save(put_title(vignette(cover(mask, (600, 900), (0.5, 0.45), 1.6)), 0.8, 0.86), 'library', 'library_capsule_600x900.png')
    save(put_title(wide((920, 430), 1.25), 0.62, 0.78), 'library', 'library_header_920x430.png')
    save(vignette(cover(fight, (3840, 1240), light, 1.05), 0.4), 'library', 'library_hero_3840x1240.png')
    save(logo(1280), 'library', 'library_logo_1280w.png')

    for i, name in enumerate(SCREENSHOTS):
        save(Image.open(os.path.join(SHOTS, name)).convert('RGB'), 'screenshots', 'ss_%d_%s' % (i + 1, name))

    icon = cover(mask, (512, 512), (0.5, 0.42), 2.6)
    save(icon.resize((184, 184), Image.LANCZOS), 'community', 'app_icon_184.jpg', quality=92)
    ico = icon.resize((256, 256), Image.LANCZOS)
    path = os.path.join(OUT, 'community', 'shortcut_icon_256.ico')
    ico.save(path, sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)])
    print('%-44s %5dx%-5d %6.0f KB' % ('community/shortcut_icon_256.ico', 256, 256, os.path.getsize(path)/1e3))
    save(ico, 'community', 'shortcut_icon_256.png')


if __name__ == '__main__':
    main()
