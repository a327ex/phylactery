--[[
  hud.lua -- the HUD: a frame's list of operations drawn into an ordinary layer the final pass samples
  (post.lua R.set_hud). Each distinct text (string, colour, scale, outline, shadow) is rasterized once
  into a small texture, with its ink ring and drop, and drawn with one call.
    hud.begin(); hud.text(...); hud.rect(...); hud.alpha(a); hud.flush(layer)
  The game's one font (owner, 2026-10-03, round 43: FACETED): capitals whose rounds are cut into planes,
  like the cave's broken rock (drawn in tools/bitmap_fonts.py; port/hud_fonts.lua by tools/hud_fonts.py).
  Texts at scale 2 (names) are lit as EMBER's icons are (a dark letter, its upper left edge warm); the
  rest fall from a lighter tone at the top to a deeper ember at the bottom. HUD.plain = true draws
  without either (the testing text).
]]
local HUD = {}
local floor, max = math.floor, math.max

-- round 53 (owner, 2026-10-07: "We need to audition more fonts ... perhaps a clash of pixel sizes"): the
-- fonts of tools/hud_fonts.py; `hi` ones are drawn at the window's resolution (one screen pixel per glyph
-- pixel, the icons' size since round 49) into HUD.hi_layer. The game's is FACETED FINE (his pick); the
-- testing text (HUD.plain) stays FACETED.
local FONTS = require('port.hud_fonts')
-- (2026-10-18, Phylactery 20, owner: "The UI should probably also use that font") the game's settled serif, baked by
-- tools/hud_serif.py: mixed case, anti-aliased, kerned. HUD.case = 'caps' sets a text in spaced capitals (HUD.TRACK
-- pixels between letters), 'mixed' as it is written.
FONTS.serif = require('port.hud_serif')
for _, f in pairs(FONTS) do f.glyphs[' '] = { w = f.space, px = {} } end
HUD.case = 'caps'
HUD.TRACK = 2
HUD.FONTS = FONTS
-- (owner, 2026-10-07, on round 53: "second font is the correct one": FACETED FINE, the game's font; 2026-10-18, on the
-- serif everywhere: "go back to the old font in the game, the new one doesn't work there ... Only the title should have
-- the new font": the serif sets only the viewer's object title, port/inspect.lua)
HUD.font_name = 'facet_fine'
local FONT = FONTS.facet
HUD.FONT = FONT
HUD.plain = false
local function font() return HUD.plain and FONTS.facet or FONTS[HUD.font_name] or FONTS.facet end
function HUD.set_font(name) if FONTS[name] then HUD.font_name = name end; return HUD.font_name end
function HUD.font_label() local f = FONTS[HUD.font_name]; return f and f.label or HUD.font_name end
local function k_hi(f) return f.hi and (HUD.HI or 2) or 1 end
-- a text as the font sets it: the pixel fonts are all capitals; the serif as written, or in spaced capitals (HUD.case)
local function setting(f, str)
  if f.upper ~= false then return str:upper(), 0 end
  if HUD.case == 'caps' then return str:upper(), HUD.TRACK end
  return str, 0
end
-- (in the font's own pixels) each advance holds the letter and the gap after it; the last gap is not width
-- (round 64: byte by byte through a per-font byte -> glyph table, upper-cased as it is filled: no copies, no iterator)
local function glyph_width(f, str, scale)
  local G, gb = f.glyphs, f._by_byte
  if not gb then gb = {}; f._by_byte = gb end
  local s, track = setting(f, tostring(str))
  local KN = f.kern
  local w, prev = 0, nil
  for i = 1, #s do
    local b = string.byte(s, i)
    local g = gb[b]
    if not g then g = G[string.char(b)] or G[string.char(b):upper()] or G['?']; gb[b] = g end
    if KN and prev then w = w + (KN[string.char(prev, b)] or 0)*scale end
    w = w + (g.w + (i < #s and track or 0))*scale
    prev = b
  end
  return max(0, w - scale)
end
-- a text's height and width in game pixels at this scale
function HUD.text_height(scale) local f = font(); return math.ceil(f.h*(scale or 1)/k_hi(f)) end
-- (round 54: whole game pixels, rounded up: sizes made from it, the lamp glow's, must be whole)
function HUD.text_width(str, scale) local f = font(); return math.ceil(glyph_width(f, str, scale or 1)/k_hi(f)) end

-- CSS colours: '#rrggbb' or 'rgba(r,g,b,a)' -> r, g, b, a (0..1)
local css_cache = {}
local function css(c)
  if not c then return nil end
  local v = css_cache[c]
  if v then return v end
  if c:sub(1, 1) == '#' then
    v = { tonumber(c:sub(2, 3), 16)/255, tonumber(c:sub(4, 5), 16)/255, tonumber(c:sub(6, 7), 16)/255, 1 }
  else
    local r, g, b, a = c:match('rgba?%(%s*([%d.]+)%s*,%s*([%d.]+)%s*,%s*([%d.]+)%s*,?%s*([%d.]*)%s*%)')
    v = { tonumber(r)/255, tonumber(g)/255, tonumber(b)/255, a ~= '' and tonumber(a) or 1 }
  end
  css_cache[c] = v
  return v
end
HUD.css = css

-- one text as a texture, composited source-over (straight alpha)
local cache, cache_n, cache_order = {}, 0, {}
local function raster(str, color, scale, shadow, outline, drop)
  -- the treatment: a name rim-lit, the rest an ember fall (none for HUD.plain)
  local fill = not HUD.plain
  local fx = fill and scale >= 2 and 'rim' or nil
  local fnt = font()
  local key = (fill and 'e' or 'p') .. '\0' .. (HUD.plain and 'facet' or HUD.font_name) .. '\0' .. HUD.case .. '\0' .. str .. '\0' .. color .. '\0' .. scale .. '\0' .. (shadow or '') .. '\0' .. (outline or '') .. '\0' .. (drop or '')
  local e = cache[key]
  if e then e.used = HUD.frame; return e end
  local G = fnt.glyphs
  local tw = glyph_width(fnt, str, scale)
  local track
  str, track = setting(fnt, str)
  local KN = fnt.kern
  local pad = 2 + scale
  local W, Hh = tw + 2*pad, (fnt.draw_h or fnt.h)*scale + 2*pad   -- (the serif's descenders fall below its layout height)
  local pix = {}          -- [y*W + x] = { r, g, b, a }
  local function put(x, y, c)
    x = x + pad; y = y + pad
    if x < 0 or y < 0 or x >= W or y >= Hh then return end
    local k = y*W + x
    local d = pix[k]
    local sa = c[4]
    if not d then pix[k] = { c[1], c[2], c[3], sa }; return end
    local da = d[4]
    local oa = sa + da*(1 - sa)
    if oa <= 0 then return end
    d[1] = (c[1]*sa + d[1]*da*(1 - sa))/oa; d[2] = (c[2]*sa + d[2]*da*(1 - sa))/oa; d[3] = (c[3]*sa + d[3]*da*(1 - sa))/oa; d[4] = oa
  end
  local function each(fn, solid)
    local px, prev = 0, nil
    for ch in str:gmatch('.') do
      local f = G[ch] or G[ch:upper()] or G['?']
      if KN and prev then px = px + (KN[prev .. ch] or 0)*scale end
      local p, pa = f.px, f.pa
      for i = 1, #p, 2 do
        local a = pa and pa[(i + 1)//2] or 1
        if not solid or a >= 0.5 then fn(px + p[i]*scale, p[i + 1]*scale, a) end
      end
      px = px + (f.w + track)*scale
      prev = ch
    end
  end
  local function faded(c, a) if a >= 1 then return c end; return { c[1], c[2], c[3], c[4]*a } end
  local function pass(ox, oy, c) each(function(x, y, a) local ca = faded(c, a); for j = 0, scale - 1 do for i = 0, scale - 1 do put(x + ox + i, y + oy + j, ca) end end end) end
  if shadow then pass(scale, scale, css(shadow)) end
  local function K2(x, y) return (y + 2048)*8192 + x + 2048 end
  if outline then
    local on, seen, ring = {}, {}, {}
    local function K(x, y) return (y + 2048)*8192 + x + 2048 end
    each(function(x, y) for j = 0, scale - 1 do for i = 0, scale - 1 do on[K(x + i, y + j)] = true end end end, true)
    local N8 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }
    each(function(x, y)
      for j = 0, scale - 1 do for i = 0, scale - 1 do for _, d in ipairs(N8) do
        local qx, qy = x + i + d[1], y + j + d[2]
        local k = K(qx, qy)
        if not on[k] and not seen[k] then seen[k] = true; ring[#ring + 1] = qx; ring[#ring + 1] = qy end
      end end end
    end, true)
    if drop then
      local dc = css(drop)
      for i = 1, #ring, 2 do
        local k = K(ring[i], ring[i + 1] + 1)
        if not seen[k] and not on[k] then put(ring[i], ring[i + 1] + 1, dc) end
      end
    end
    local oc = css(outline)
    for i = 1, #ring, 2 do put(ring[i], ring[i + 1], oc) end
  end
  if not fill and not fx then pass(0, 0, css(color))
  else
    local base = css(color)
    local on = {}
    each(function(x, y) for j = 0, scale - 1 do for i = 0, scale - 1 do on[K2(x + i, y + j)] = true end end end, true)
    local H = fnt.h*scale
    local light, mid, dark = { 0.965, 0.84, 0.63, 1 }, { 0.62, 0.36, 0.2, 1 }, { 0.16, 0.11, 0.075, 1 }
    each(function(x, y, a) for j = 0, scale - 1 do for i = 0, scale - 1 do
      local px, py = x + i, y + j
      local c
      if fx == 'rim' then
        if not on[K2(px, py - 1)] or not on[K2(px - 1, py)] then c = light
        elseif not on[K2(px - 1, py - 1)] or not on[K2(px, py - 2)] or not on[K2(px - 2, py)] then c = mid
        else c = dark end
      else
        local t = math.max(0, math.min(1, py/math.max(1, H - 1)))
        -- the colour, lighter at the top, falling to a deeper, warmer one at the bottom
        local top = { math.min(1, base[1]*1.06 + 0.03), math.min(1, base[2]*1.04 + 0.02), math.min(1, base[3]*0.98), base[4] }
        local bot = { base[1]*0.92, base[2]*0.66, base[3]*0.42, base[4] }
        c = { top[1] + (bot[1] - top[1])*t, top[2] + (bot[2] - top[2])*t, top[3] + (bot[3] - top[3])*t, base[4] }
      end
      put(px, py, faded(c, a))
    end end end)
  end
  -- RGBA rows, top first
  local rows = {}
  for y = 0, Hh - 1 do
    local row = {}
    for x = 0, W - 1 do
      local d = pix[y*W + x]
      if d then row[x + 1] = string.char(floor(d[1]*255 + 0.5), floor(d[2]*255 + 0.5), floor(d[3]*255 + 0.5), floor(d[4]*255 + 0.5))
      else row[x + 1] = '\0\0\0\0' end
    end
    rows[y + 1] = table.concat(row)
  end
  local tex = texture_create(W, Hh, table.concat(rows))
  e = { tex = tex, w = W, h = Hh, pad = pad, used = HUD.frame, key = key, hi = fnt.hi }
  cache[key] = e
  cache_n = cache_n + 1
  -- forget the least recently drawn when there are many
  if cache_n > 400 then
    local oldest, ok = nil, nil
    for k2, v in pairs(cache) do if not oldest or v.used < oldest.used then oldest, ok = v, k2 end end
    if oldest then texture_unload(oldest.tex); cache[ok] = nil; cache_n = cache_n - 1 end
  end
  return e
end

HUD.frame = 0
local ops, galpha = {}, 1
function HUD.begin() ops = {}; galpha = 1; HUD.frame = HUD.frame + 1 end
function HUD.alpha(a) galpha = a end
-- draw_text(g, str, x, y, color, scale, align, shadow, opts) with the canvas `g` implied
function HUD.text(str, x, y, color, scale, align, shadow, opts)
  scale = scale or 1; align = align or 'left'
  str = tostring(str)
  local w = HUD.text_width(str, scale)
  local cx = align == 'center' and x - w/2 or (align == 'right' and x - w or x)
  cx = floor(cx + 0.5); y = floor(y + 0.5)
  local outline = type(opts) == 'string' and opts or (type(opts) == 'table' and opts.outline or nil)
  local drop = type(opts) == 'table' and opts.shadow or nil
  local e = raster(str, color, scale, shadow, outline, drop)
  if e.hi then
    local K = HUD.HI
    ops[#ops + 1] = { t = 'texhi', e = { tex = e.tex, w = e.w/K, h = e.h/K }, x = cx - e.pad/K, y = y - e.pad/K, a = galpha }
  else
    ops[#ops + 1] = { t = 'tex', e = e, x = cx - e.pad, y = y - e.pad, a = galpha }
  end
end
function HUD.rect(x, y, w, h, color)
  local c = css(color)
  ops[#ops + 1] = { t = 'rect', x = x, y = y, w = w, h = h, c = c, a = galpha }
end
-- an image (a gpu texture's image, rows bottom-up as GL keeps them: drawn flipped) at x, y
function HUD.image(img, x, y, w, h)
  ops[#ops + 1] = { t = 'img', img = img, x = x, y = y, w = w, h = h, a = galpha }
end
-- a 2D texture (texture_load: rows top-down) at x, y, its own size
function HUD.texture(tex, x, y, w, h)
  ops[#ops + 1] = { t = 'tex', e = { tex = tex, w = w, h = h }, x = x, y = y, a = galpha }
end
-- round 49: a texture drawn into the full-resolution layer (HUD.hi_layer, HUD.HI x the game's pixels):
-- x, y, w, h in game pixels; the texture is w*HUD.HI wide
HUD.HI = 2
HUD.hi_layer = nil
function HUD.texture_hi(tex, x, y, w, h)
  ops[#ops + 1] = { t = 'texhi', e = { tex = tex, w = w, h = h }, x = x, y = y, a = galpha }
end
function HUD.flush(layer)
  local hi, K = HUD.hi_layer, HUD.HI
  for _, o in ipairs(ops) do
    if o.t == 'texhi' then
      if hi then layer_draw_texture(hi, o.e.tex, (o.x + o.e.w/2)*K, (o.y + o.e.h/2)*K, color(255, 255, 255, floor(o.a*255 + 0.5))()) end
    elseif o.t == 'img' then
      layer_push(layer, o.x + o.w/2, o.y + o.h/2, 0, 1, -1)
      layer_draw_texture(layer, o.img, 0, 0, color(255, 255, 255, floor(o.a*255 + 0.5))())
      layer_pop(layer)
    elseif o.t == 'tex' then
      layer_draw_texture(layer, o.e.tex, o.x + o.e.w/2, o.y + o.e.h/2, color(255, 255, 255, floor(o.a*255 + 0.5))())
    else
      local c = o.c
      layer_rectangle(layer, o.x, o.y, o.w, o.h, color(floor(c[1]*255 + 0.5), floor(c[2]*255 + 0.5), floor(c[3]*255 + 0.5), floor(c[4]*o.a*255 + 0.5))())
    end
  end
end

return HUD
