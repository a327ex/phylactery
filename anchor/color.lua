--[[
  color — mutable RGBA color with HSL conversion helpers.

  Simpler than v1's color class. A color is a plain table {r, g, b, a} with
  a __call metamethod that returns the packed rgba integer used by drawing
  functions. No auto-sync between RGB and HSL — HSL is a *conversion*, not a
  storage format. If you want to modify hue, convert to HSL, modify, convert
  back.

  Usage:
    red = color_new(255, 0, 0)
    red.a = 128              -- set alpha
    layer_circle(game_layer, x, y, r, red())  -- __call returns packed rgba integer
    layer_circle(game_layer, x, y, r, red)    -- also fine: layer wrappers pack a Color table

    -- HSL manipulation:
    h, s, l = color_to_hsl(red)
    h = (h + 120) % 360      -- shift hue
    shifted = color_from_hsl(h, s, l, red.a)

    -- Common operations:
    copy = color_clone(red)
    mixed = color_mix(red, blue, 0.5)
    dark = color_darken(red, 0.5)      -- multiply RGB by 0.5
    light = color_lighten(red, 1.5)    -- multiply RGB by 1.5 (clamped)
    inverted = color_invert(red)

  Design notes:
    - Colors are plain tables. Modify fields directly: c.r = 100.
    - Procedural functions (color_mix, color_clone, etc.) return NEW colors,
      not mutating the input. If you want to mutate, do `c.r = ...` directly.
    - __call returns the packed rgba integer via the engine's rgba() function.
    - HSL is available via conversions, not as first-class color fields.
    - Raw C bindings still want the packed integer: call the color (`c()`)
      when passing one to an unshadowed engine function.
]]

---@class Color
---@field r number   0-255
---@field g number   0-255
---@field b number   0-255
---@field a number   0-255
---@operator call: integer   packs to the rgba integer the engine draws with

-- Internal: rgb_to_hsl and hsl_to_rgb
---@param r number   0-255
---@param g number   0-255
---@param b number   0-255
---@return number h   0-360
---@return number s   0-1
---@return number l   0-1
function rgb_to_hsl(r, g, b)
  r, g, b = r/255, g/255, b/255
  local max = math.max(r, g, b)
  local min = math.min(r, g, b)
  local l = (max + min)/2
  if max == min then return 0, 0, l end
  local d = max - min
  local s = l > 0.5 and d/(2 - max - min) or d/(max + min)
  local h_offset = g < b and 6 or 0
  local h
  if max == r then
    h = ((g - b)/d + h_offset)/6
  elseif max == g then
    h = ((b - r)/d + 2)/6
  else
    h = ((r - g)/d + 4)/6
  end
  return h*360, s, l
end

---@param h number   0-360
---@param s number   0-1
---@param l number   0-1
---@return integer r
---@return integer g
---@return integer b
function hsl_to_rgb(h, s, l)
  if s == 0 then
    local v = math.floor(l*255 + 0.5)
    return v, v, v
  end
  h = h/360
  local q = l < 0.5 and l*(1 + s) or l + s - l*s
  local p = 2*l - q
  local function hue_to_rgb(t)
    if t < 0 then t = t + 1 end
    if t > 1 then t = t - 1 end
    if t < 1/6 then return p + (q - p)*6*t end
    if t < 1/2 then return q end
    if t < 2/3 then return p + (q - p)*(2/3 - t)*6 end
    return p
  end
  local r = math.floor(hue_to_rgb(h + 1/3)*255 + 0.5)
  local g = math.floor(hue_to_rgb(h)*255 + 0.5)
  local b = math.floor(hue_to_rgb(h - 1/3)*255 + 0.5)
  return r, g, b
end

-- Metatable for colors: __call returns the packed rgba integer.
local color_mt = {}

color_mt.__call = function(c)
  return rgba(
    math.floor(c.r + 0.5),
    math.floor(c.g + 0.5),
    math.floor(c.b + 0.5),
    math.floor(c.a + 0.5)
  )
end

--[[
  color_new(r, g, b, a)
  Create a new color. Defaults to white (255, 255, 255, 255).
]]
---@param r? number   0-255, default 255
---@param g? number   0-255, default 255
---@param b? number   0-255, default 255
---@param a? number   0-255, default 255
---@return Color
function color_new(r, g, b, a)
  return setmetatable({
    r = r or 255,
    g = g or 255,
    b = b or 255,
    a = a or 255,
  }, color_mt)
end

-- Shorter alias — `color(r, g, b, a)` creates a color.
-- This makes the v1-style usage `red = color(255, 0, 0)` still work.
color = color_new

--[[
  color_from_hsl(h, s, l, a)
  Create a color from HSL values (h: 0-360, s: 0-1, l: 0-1).
]]
---@param h number   0-360
---@param s number   0-1
---@param l number   0-1
---@param a? number  0-255, default 255
---@return Color
function color_from_hsl(h, s, l, a)
  local r, g, b = hsl_to_rgb(h, s, l)
  return color_new(r, g, b, a)
end

-- v1 alias
hsl_color = color_from_hsl

--[[
  color_to_hsl(c)
  Return h, s, l values for a color (h: 0-360, s: 0-1, l: 0-1).
]]
---@param c Color
---@return number h
---@return number s
---@return number l
function color_to_hsl(c)
  return rgb_to_hsl(c.r, c.g, c.b)
end

--[[
  color_clone(c)
  Return an independent copy of a color.
]]
---@param c Color
---@return Color
function color_clone(c)
  return color_new(c.r, c.g, c.b, c.a)
end

--[[
  color_mix(a, b, t)
  Linear interpolation between two colors. Returns a new color.
  t=0 returns a, t=1 returns b, t=0.5 returns the midpoint.
]]
---@param a Color
---@param b Color
---@param t? number   0-1, default 0.5
---@return Color
function color_mix(a, b, t)
  t = t or 0.5
  return color_new(
    a.r + (b.r - a.r)*t,
    a.g + (b.g - a.g)*t,
    a.b + (b.b - a.b)*t,
    a.a + (b.a - a.a)*t
  )
end

--[[
  color_darken(c, factor)
  Return a new color with RGB multiplied by factor (0-1 darkens, 1 unchanged).
  Alpha is unchanged. Values are clamped to [0, 255].
]]
---@param c Color
---@param factor number
---@return Color
function color_darken(c, factor)
  local r = c.r*factor
  local g = c.g*factor
  local b = c.b*factor
  if r < 0 then r = 0 elseif r > 255 then r = 255 end
  if g < 0 then g = 0 elseif g > 255 then g = 255 end
  if b < 0 then b = 0 elseif b > 255 then b = 255 end
  return color_new(r, g, b, c.a)
end

--[[
  color_lighten(c, factor)
  Return a new color with RGB multiplied by factor (>1 brightens).
  Clamped to [0, 255].
]]
---@param c Color
---@param factor number
---@return Color
function color_lighten(c, factor)
  return color_darken(c, factor)  -- same implementation, clamping handles it
end

--[[
  color_invert(c)
  Return a new color with inverted RGB (255 - value). Alpha unchanged.
]]
---@param c Color
---@return Color
function color_invert(c)
  return color_new(255 - c.r, 255 - c.g, 255 - c.b, c.a)
end
