--[[
  hud.lua -- the port to Anchor: web/src/hud_font.js (the 5x7 pixel font) and the HUD canvas.
  The three.js build drew its HUD with canvas fillRects and composited it in the final pass; here a
  frame's HUD is a list of operations drawn into an ordinary layer the final pass samples (post.lua
  R.set_hud). Each distinct text (string, colour, scale, outline, shadow) is rasterized once into a
  small texture with hud_font.js's exact pixels, ink ring and drop, and drawn with one call.
    hud.begin(); hud.text(...); hud.rect(...); hud.alpha(a); hud.flush(layer)
]]
local HUD = {}
local floor, max = math.floor, math.max

local RAW = {
  A = { '.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#' },
  B = { '####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.' },
  C = { '.###.', '#...#', '#....', '#....', '#....', '#...#', '.###.' },
  D = { '####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.' },
  E = { '#####', '#....', '#....', '####.', '#....', '#....', '#####' },
  F = { '#####', '#....', '#....', '####.', '#....', '#....', '#....' },
  G = { '.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.####' },
  H = { '#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#' },
  I = { '###', '.#.', '.#.', '.#.', '.#.', '.#.', '###' },
  J = { '..###', '...#.', '...#.', '...#.', '...#.', '#..#.', '.##..' },
  K = { '#...#', '#..#.', '#.#..', '##...', '#.#..', '#..#.', '#...#' },
  L = { '#....', '#....', '#....', '#....', '#....', '#....', '#####' },
  M = { '#...#', '##.##', '#.#.#', '#.#.#', '#...#', '#...#', '#...#' },
  N = { '#...#', '#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#' },
  O = { '.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.' },
  P = { '####.', '#...#', '#...#', '####.', '#....', '#....', '#....' },
  Q = { '.###.', '#...#', '#...#', '#...#', '#.#.#', '#..#.', '.##.#' },
  R = { '####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#' },
  S = { '.####', '#....', '#....', '.###.', '....#', '....#', '####.' },
  T = { '#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..' },
  U = { '#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.' },
  V = { '#...#', '#...#', '#...#', '#...#', '#...#', '.#.#.', '..#..' },
  W = { '#...#', '#...#', '#...#', '#.#.#', '#.#.#', '#.#.#', '.#.#.' },
  X = { '#...#', '#...#', '.#.#.', '..#..', '.#.#.', '#...#', '#...#' },
  Y = { '#...#', '#...#', '.#.#.', '..#..', '..#..', '..#..', '..#..' },
  Z = { '#####', '....#', '...#.', '..#..', '.#...', '#....', '#####' },
  ['0'] = { '.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.' },
  ['1'] = { '..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.' },
  ['2'] = { '.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####' },
  ['3'] = { '#####', '...#.', '..#..', '...#.', '....#', '#...#', '.###.' },
  ['4'] = { '...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.' },
  ['5'] = { '#####', '#....', '####.', '....#', '....#', '#...#', '.###.' },
  ['6'] = { '..##.', '.#...', '#....', '####.', '#...#', '#...#', '.###.' },
  ['7'] = { '#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...' },
  ['8'] = { '.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.' },
  ['9'] = { '.###.', '#...#', '#...#', '.####', '....#', '...#.', '.##..' },
  ['.'] = { '.', '.', '.', '.', '.', '.', '#' },
  [','] = { '..', '..', '..', '..', '..', '.#', '#.' },
  [':'] = { '.', '.', '#', '.', '.', '#', '.' },
  ['!'] = { '#', '#', '#', '#', '#', '.', '#' },
  ['?'] = { '.###.', '#...#', '....#', '...#.', '..#..', '.....', '..#..' },
  ['-'] = { '....', '....', '....', '####', '....', '....', '....' },
  ['+'] = { '.....', '..#..', '..#..', '#####', '..#..', '..#..', '.....' },
  ['/'] = { '....#', '....#', '...#.', '..#..', '.#...', '#....', '#....' },
  ['('] = { '.#', '#.', '#.', '#.', '#.', '#.', '.#' },
  [')'] = { '#.', '.#', '.#', '.#', '.#', '.#', '#.' },
  ["'"] = { '#', '#', '.', '.', '.', '.', '.' },
  ['%'] = { '##..#', '##..#', '...#.', '..#..', '.#...', '#..##', '#..##' },
  ['='] = { '....', '....', '####', '....', '####', '....', '....' },
  ['_'] = { '.....', '.....', '.....', '.....', '.....', '.....', '#####' },
  ['|'] = { '#', '#', '#', '#', '#', '#', '#' },
  ['<'] = { '...#', '..#.', '.#..', '#...', '.#..', '..#.', '...#' },
  ['>'] = { '#...', '.#..', '..#.', '...#', '..#.', '.#..', '#...' },
  ['['] = { '##', '#.', '#.', '#.', '#.', '#.', '##' },
  [']'] = { '##', '.#', '.#', '.#', '.#', '.#', '##' },
}
HUD.GLYPH_H = 7
local FONT = {}
for ch, rows in pairs(RAW) do
  local w = #rows[1]
  local px = {}
  for y = 0, 6 do for x = 0, w - 1 do if rows[y + 1]:sub(x + 1, x + 1) == '#' then px[#px + 1] = x; px[#px + 1] = y end end end
  FONT[ch] = { w = w, px = px }
end
FONT[' '] = { w = 3, px = {} }
HUD.FONT = FONT

-- round 42: fonts by name. 'classic' = the 5x7 above (drawn at any scale, 1 px between letters);
-- the others come from tools/hud_fonts.py (TrueType pixel fonts as glyph tables, drawn at their own
-- size: their advances include the spacing). HUD.style names the title font (texts drawn at scale
-- 2: names) and the body font (the rest).
local FONTS = { classic = { glyphs = FONT, h = 7, upper = true, track = 1, scalable = true } }
for name, f in pairs(require('port.hud_fonts')) do
  f.glyphs[' '] = { w = f.space, px = {} }
  f.track = 0
  FONTS[name] = f
end
-- round 44 (owner: "Could we try non-pixel fonts?"): TrueType drawn by the engine, anti-aliased, into a
-- full-resolution layer over the upscaled game (HUD.hi_layer, HUD.HI times the game's pixels: boot.lua
-- makes it). Sizes in game pixels; each name is one font at one size.
HUD.HI = 2
HUD.hi_layer = nil
local SMOOTH = {
  s_cinzel_t = { 'Cinzel[wght].ttf', 16 },        s_cinzel_b = { 'Cinzel[wght].ttf', 10.5 },
  s_fell_t = { 'IMFeENsc28P.ttf', 17 },           s_fell_b = { 'IMFeENrm28P.ttf', 12 },
  s_uncial_t = { 'UncialAntiqua-Regular.ttf', 15 }, s_uncial_b = { 'UncialAntiqua-Regular.ttf', 10.5 },
  s_sharp_t = { 'MedievalSharp.ttf', 16 },        s_sharp_b = { 'MedievalSharp.ttf', 11 },
  s_marcellus_t = { 'MarcellusSC-Regular.ttf', 15 }, s_marcellus_b = { 'Marcellus-Regular.ttf', 11 },
  s_grenze_t = { 'Grenze[wght].ttf', 17 },        s_grenze_b = { 'Grenze[wght].ttf', 12 },
}
for name, d in pairs(SMOOTH) do FONTS[name] = { smooth = true, path = 'assets/fonts/' .. d[1], size = d[2], h = d[2], upper = false, track = 0, glyphs = {} } end
local function smooth_ready(f, name)
  if not f.id then
    f.id = 'hud_' .. name
    font_load(f.id, f.path, math.floor(f.size*HUD.HI + 0.5), 'smooth')
    f.h = font_get_height(f.id)/HUD.HI
  end
  return f.id
end
HUD.FONTS = FONTS
HUD.style = { title = 'classic', body = 'classic' }
-- (a style may give each role its own scale: title_scale, body_scale; pixel fonts stay crisp at whole multiples)
local function font_for(scale)
  local st = HUD.style
  local title = (scale or 1) >= 2
  local name = title and st.title or st.body
  local f = FONTS[name] or FONTS.classic
  return f, (title and st.title_scale or st.body_scale) or (scale or 1), name
end
HUD.font_for = font_for
-- a text's height in pixels (its capitals' top to its lowest descender) at this scale
function HUD.text_height(scale)
  local f, s, name = font_for(scale)
  if f.smooth then smooth_ready(f, name); return math.floor(f.h + 0.5) end
  return f.h*s
end

local function glyphs(str, f) return f.upper and str:upper() or str end
-- the game's texts are written in capitals; a mixed-case font gets them as names (Title Case) or as
-- sentences (each run between wide gaps starts with a capital), whichever role draws them
local SMALL = { the = true, ['of'] = true, a = true, an = true, ['and'] = true, ['or'] = true, to = true, ['in'] = true }
local function recase(str, title)
  if not str:find('%u') or str:find('%l') then return str end
  local low = str:lower()
  if title then
    local n = 0
    return (low:gsub('(%a[%a\']*)', function(w) n = n + 1; if n > 1 and SMALL[w] then return w end; return w:sub(1, 1):upper() .. w:sub(2) end))
  end
  low = low:gsub('^(%W*)(%a)', function(p, c) return p .. c:upper() end)
  low = low:gsub('(%s%s+%W*)(%a)', function(p, c) return p .. c:upper() end)
  return low
end
HUD.recase = recase
function HUD.text_width(str, scale)
  local f, s, name = font_for(scale)
  if f.smooth then return font_get_text_width(smooth_ready(f, name), tostring(str))/HUD.HI end
  local G = f.glyphs
  local w = 0
  for ch in glyphs(tostring(str), f):gmatch('.') do w = w + ((G[ch] or G['?']).w + f.track)*s end
  return max(0, w - f.track*s)
end

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

-- one text as a texture: hud_font.js's draw_text, composited source-over (straight alpha)
local cache, cache_n, cache_order = {}, 0, {}
local function raster(str, color, scale0, shadow, outline, drop)
  local fnt, scale, fname = font_for(scale0)
  -- round 43: the style's treatment of this role: fill 'ember' (a warm fall from top to bottom),
  -- fx 'rim' (a dark letter, its upper left edge lit warm, as EMBER's icons)
  local title_role = (scale0 or 1) >= 2
  local fill = HUD.style.fill
  local fx = title_role and HUD.style.title_fx or HUD.style.body_fx
  local key = fname .. '\0' .. (fill or '') .. '\0' .. (fx or '') .. '\0' .. str .. '\0' .. color .. '\0' .. scale .. '\0' .. (shadow or '') .. '\0' .. (outline or '') .. '\0' .. (drop or '')
  local e = cache[key]
  if e then e.used = HUD.frame; return e end
  local G = fnt.glyphs
  str = glyphs(str, fnt)
  local tw = HUD.text_width(str, scale0)
  local pad = 2 + scale
  local W, Hh = tw + 2*pad, fnt.h*scale + 2*pad
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
  local function each(fn)
    local px = 0
    for ch in str:gmatch('.') do
      local f = G[ch] or G['?']
      local p = f.px
      for i = 1, #p, 2 do fn(px + p[i]*scale, p[i + 1]*scale) end
      px = px + (f.w + fnt.track)*scale
    end
  end
  local function pass(ox, oy, c) each(function(x, y) for j = 0, scale - 1 do for i = 0, scale - 1 do put(x + ox + i, y + oy + j, c) end end end) end
  if shadow then pass(scale, scale, css(shadow)) end
  local function K2(x, y) return (y + 2048)*8192 + x + 2048 end
  if outline then
    local on, seen, ring = {}, {}, {}
    local function K(x, y) return (y + 2048)*8192 + x + 2048 end
    each(function(x, y) for j = 0, scale - 1 do for i = 0, scale - 1 do on[K(x + i, y + j)] = true end end end)
    local N8 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }
    each(function(x, y)
      for j = 0, scale - 1 do for i = 0, scale - 1 do for _, d in ipairs(N8) do
        local qx, qy = x + i + d[1], y + j + d[2]
        local k = K(qx, qy)
        if not on[k] and not seen[k] then seen[k] = true; ring[#ring + 1] = qx; ring[#ring + 1] = qy end
      end end end
    end)
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
    each(function(x, y) for j = 0, scale - 1 do for i = 0, scale - 1 do on[K2(x + i, y + j)] = true end end end)
    local H = fnt.h*scale
    local light, mid, dark = { 0.965, 0.84, 0.63, 1 }, { 0.62, 0.36, 0.2, 1 }, { 0.16, 0.11, 0.075, 1 }
    each(function(x, y) for j = 0, scale - 1 do for i = 0, scale - 1 do
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
      put(px, py, c)
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
  e = { tex = tex, w = W, h = Hh, pad = pad, used = HUD.frame, key = key }
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
  do local f = font_for(scale); if not f.upper then str = recase(tostring(str), scale >= 2) end end
  if type(opts) == 'table' and opts.font then
    -- (a one-off font for this text)
    local keep = HUD.style; HUD.style = { title = opts.font, body = opts.font }
    HUD.text(str, x, y, color, scale, align, shadow, { outline = opts.outline, shadow = opts.shadow }); HUD.style = keep
    return
  end
  str = tostring(str)
  local w = HUD.text_width(str, scale)
  local cx = align == 'center' and x - w/2 or (align == 'right' and x - w or x)
  cx = floor(cx + 0.5); y = floor(y + 0.5)
  local outline = type(opts) == 'string' and opts or (type(opts) == 'table' and opts.outline or nil)
  local drop = type(opts) == 'table' and opts.shadow or nil
  do
    local f, _, name = font_for(scale)
    if f.smooth then
      ops[#ops + 1] = { t = 'ttf', id = smooth_ready(f, name), str = str, x = cx, y = y, c = css(color), a = galpha, halo = outline or shadow }
      return
    end
  end
  local e = raster(str, color, scale, shadow, outline, drop)
  ops[#ops + 1] = { t = 'tex', e = e, x = cx - e.pad, y = y - e.pad, a = galpha }
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
local HALO = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
local function packed(c, a) return color(floor(c[1]*255 + 0.5), floor(c[2]*255 + 0.5), floor(c[3]*255 + 0.5), floor(math.max(0, math.min(1, c[4]*a))*255 + 0.5))() end
function HUD.flush(layer)
  local hi, K = HUD.hi_layer, HUD.HI
  for _, o in ipairs(ops) do
    if o.t == 'ttf' then
      if hi then
        local x, y = o.x*K, o.y*K
        -- a soft dark halo and a drop under it (the outline/shadow the pixel texts carry), then the text
        if o.halo then
          local ink = { 0.03, 0.022, 0.018, 1 }
          layer_draw_text(hi, o.str, o.id, x, y + 3, packed(ink, 0.55*o.a))
          for _, d in ipairs(HALO) do layer_draw_text(hi, o.str, o.id, x + d[1]*1.5, y + d[2]*1.5, packed(ink, 0.35*o.a)) end
        end
        layer_draw_text(hi, o.str, o.id, x, y, packed(o.c, o.a))
      end
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
