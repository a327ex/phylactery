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

local function glyphs(str) return str:upper() end
function HUD.text_width(str, scale)
  scale = scale or 1
  local w = 0
  for ch in glyphs(tostring(str)):gmatch('.') do w = w + ((FONT[ch] or FONT['?']).w + 1)*scale end
  return max(0, w - scale)
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
local function raster(str, color, scale, shadow, outline, drop)
  local key = str .. '\0' .. color .. '\0' .. scale .. '\0' .. (shadow or '') .. '\0' .. (outline or '') .. '\0' .. (drop or '')
  local e = cache[key]
  if e then e.used = HUD.frame; return e end
  str = glyphs(str)
  local tw = HUD.text_width(str, scale)
  local pad = 2 + scale
  local W, Hh = tw + 2*pad, 7*scale + 2*pad
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
      local f = FONT[ch] or FONT['?']
      local p = f.px
      for i = 1, #p, 2 do fn(px + p[i]*scale, p[i + 1]*scale) end
      px = px + (f.w + 1)*scale
    end
  end
  local function pass(ox, oy, c) each(function(x, y) for j = 0, scale - 1 do for i = 0, scale - 1 do put(x + ox + i, y + oy + j, c) end end end) end
  if shadow then pass(scale, scale, css(shadow)) end
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
  pass(0, 0, css(color))
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
  str = tostring(str)
  local w = HUD.text_width(str, scale)
  local cx = align == 'center' and x - w/2 or (align == 'right' and x - w or x)
  cx = floor(cx + 0.5); y = floor(y + 0.5)
  local outline = type(opts) == 'string' and opts or (type(opts) == 'table' and opts.outline or nil)
  local drop = type(opts) == 'table' and opts.shadow or nil
  local e = raster(str, color, scale, shadow, outline, drop)
  ops[#ops + 1] = { t = 'tex', e = e, x = cx - e.pad, y = y - e.pad, a = galpha }
end
function HUD.rect(x, y, w, h, color)
  local c = css(color)
  ops[#ops + 1] = { t = 'rect', x = x, y = y, w = w, h = h, c = c, a = galpha }
end
function HUD.flush(layer)
  for _, o in ipairs(ops) do
    if o.t == 'tex' then
      layer_draw_texture(layer, o.e.tex, o.x + o.e.w/2, o.y + o.e.h/2, color(255, 255, 255, floor(o.a*255 + 0.5))())
    else
      local c = o.c
      layer_rectangle(layer, o.x, o.y, o.w, o.h, color(floor(c[1]*255 + 0.5), floor(c[2]*255 + 0.5), floor(c[3]*255 + 0.5), floor(c[4]*o.a*255 + 0.5))())
    end
  end
end

return HUD
