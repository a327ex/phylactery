--[[
  ui_style.lua -- round 42 (owner, 2026-10-03: the inventory smaller; its icons "some idealized version
  of them generated in a style that works with the rest of the game"; the font and the UI style
  itself to fit too). The player's UI in a few directions, each axis behind a key:
    F1 a whole direction (bundle)   F2 the icons   F4 the frames   (the font: FACETED, hud.lua)
  Icons: tools/icons.py (assets/ui/icons/<style>_<i>.png), except 'render' (the inspect view's own
  render, as before, smaller). Fonts: hud.lua's registry (tools/hud_fonts.py). Frames: drawn here.
]]
local HUD = require('port.hud')
local UI = {}
local floor = math.floor

UI.ICON = 24          -- the icon's side (was 34)
UI.PAD = 3            -- slot padding
UI.GAP = 4

UI.ICONS = { 'render', 'relic', 'engraved', 'ember', 'glyph', 'lit' }
UI.FRAMES = { 'boxed', 'bare', 'plate', 'brackets', 'lamp' }
UI.BUNDLES = {
  { name = 'CURRENT', icons = 1, frame = 1 },
  { name = 'RELIC', icons = 2, frame = 3 },
  { name = 'MANUSCRIPT', icons = 3, frame = 4 },
  { name = 'EMBER', icons = 4, frame = 5 },     -- (round 49, owner: EMBER's colours were good; F2 for LIT)
  { name = 'GLYPH', icons = 5, frame = 2 },
}
UI.S = { bundle = 4, icons = 4, frame = 5 }   -- EMBER (his pick, round 42); the font is FACETED (round 43, hud.lua)
-- round 48 (owner: the icons "need to be more visible ... currently they're not making it clear which
-- item is which"): EMBER's frame and light, the icons LIT (each object in its own colours, tools/icons.py
-- lit()); F2 still cycles back to EMBER's silhouettes

local CREAM, DIM, DARK, BRONZE = '#f2e3c2', '#a8987c', '#6f6252', '#e0a070'
UI.CREAM, UI.DIM, UI.DARK = CREAM, DIM, DARK

local tex = {}
local function icon_tex(style, i)
  local k = style .. i
  if not tex[k] then tex[k] = texture_load(string.format('assets/ui/icons/%s_%d.png', style, i)) end
  return tex[k]
end
local glows = {}
-- the lamp's glow: a few flat steps, as the cave's light; hot = the light come up on it (round 45)
local function glow_tex(w, hot)
  local key = w .. (hot and 'h' or '')
  if glows[key] then return glows[key] end
  local px = {}
  for y = 0, w - 1 do for x = 0, w - 1 do
    local dx, dy = (x + 0.5)/w*2 - 1, (y + 0.5)/w*2 - 1
    local r = math.sqrt(dx*dx + dy*dy)
    local a = math.max(0, 1 - r)^(hot and 1.25 or 1.6)
    a = floor(a*4 + 0.5)/4*(hot and 1 or 0.85)
    if hot then px[#px + 1] = string.char(196, 124, 66, floor(a*255 + 0.5))
    else px[#px + 1] = string.char(150, 96, 54, floor(a*255 + 0.5)) end
  end end
  glows[key] = texture_create(w, w, table.concat(px))
  return glows[key]
end
-- a wide glow behind a word (the lamp frame's buttons, hot)
local function word_glow(w, h)
  local key = 'w' .. w .. 'x' .. h
  if glows[key] then return glows[key] end
  local px = {}
  for y = 0, h - 1 do for x = 0, w - 1 do
    local dx, dy = (x + 0.5)/w*2 - 1, (y + 0.5)/h*2 - 1
    local r = math.sqrt(dx*dx*0.9 + dy*dy)
    local a = math.max(0, 1 - r)^1.3
    a = floor(a*4 + 0.5)/4*0.9
    px[#px + 1] = string.char(196, 124, 66, floor(a*255 + 0.5))
  end end
  glows[key] = texture_create(w, h, table.concat(px))
  return glows[key]
end

function UI.apply() end
function UI.set_bundle(i)
  local n = #UI.BUNDLES
  UI.S.bundle = ((i - 1) % n + n) % n + 1
  local b = UI.BUNDLES[UI.S.bundle]
  UI.S.icons, UI.S.frame = b.icons, b.frame
  UI.apply()
end
local function cyc(k, list) UI.S[k] = UI.S[k] % #list + 1; UI.apply() end
function UI.next_icons() cyc('icons', UI.ICONS) end
function UI.next_frame() cyc('frame', UI.FRAMES) end
function UI.describe()
  local b = UI.BUNDLES[UI.S.bundle]
  local same = b.icons == UI.S.icons and b.frame == UI.S.frame
  return (same and b.name or 'MIXED') .. ': ICONS ' .. UI.ICONS[UI.S.icons]:upper() .. ', FRAME ' .. UI.FRAMES[UI.S.frame]:upper()
end

-- the slot's box (state: 'on', 'hot' or 'empty'), then its icon
local function edges(x, y, w, h, top, bot)
  HUD.rect(x, y, w, 1, top); HUD.rect(x, y, 1, h, top)
  HUD.rect(x, y + h - 1, w, 1, bot); HUD.rect(x + w - 1, y, 1, h, bot)
end
local function corners(x, y, w, h, c, arm)
  HUD.rect(x, y, arm, 1, c); HUD.rect(x, y, 1, arm, c)
  HUD.rect(x + w - arm, y, arm, 1, c); HUD.rect(x + w - 1, y, 1, arm, c)
  HUD.rect(x, y + h - 1, arm, 1, c); HUD.rect(x, y + h - arm, 1, arm, c)
  HUD.rect(x + w - arm, y + h - 1, arm, 1, c); HUD.rect(x + w - 1, y + h - arm, 1, arm, c)
end
function UI.slot(x, y, w, h, state)
  local fr = UI.FRAMES[UI.S.frame]
  local hot, empty = state == 'hot', state == 'empty'
  if fr == 'boxed' then
    HUD.rect(x, y, w, h, 'rgba(8,6,5,0.8)')
    local e = hot and 'rgba(242,227,194,0.95)' or 'rgba(120,106,86,0.75)'
    edges(x, y, w, h, e, e)
  elseif fr == 'bare' then
    if empty then
      for _, d in ipairs({ { 2, 2 }, { w - 3, 2 }, { 2, h - 3 }, { w - 3, h - 3 } }) do HUD.rect(x + d[1], y + d[2], 1, 1, 'rgba(168,152,124,0.45)') end
    end
  elseif fr == 'plate' then
    HUD.rect(x, y, w, h, empty and 'rgba(14,11,8,0.9)' or 'rgba(34,27,21,0.94)')
    if empty then edges(x, y, w, h, 'rgba(6,5,4,0.9)', 'rgba(70,58,46,0.7)')
    else
      edges(x, y, w, h, hot and 'rgba(224,160,112,0.95)' or 'rgba(86,72,57,0.95)', 'rgba(9,7,5,0.95)')
      HUD.rect(x + 1, y + 1, w - 2, 1, hot and 'rgba(160,112,72,0.6)' or 'rgba(58,48,38,0.8)')
    end
  elseif fr == 'brackets' then
    if not empty then HUD.rect(x + 1, y + 1, w - 2, h - 2, 'rgba(10,8,6,0.45)') end
    corners(x, y, w, h, hot and CREAM or (empty and 'rgba(168,152,124,0.35)' or 'rgba(168,152,124,0.85)'), hot and 5 or 4)
  elseif fr == 'lamp' then
    -- (round 45, owner: no underline, no name: the object itself is lit when hovered)
    if not empty then
      if hot then HUD.texture(glow_tex(w + 12, true), x - 6, y - 6, w + 12, w + 12)
      else HUD.texture(glow_tex(w + 8), x - 4, y - 4, w + 8, w + 8) end
    end
    if empty then for _, d in ipairs({ { 2, 2 }, { w - 3, 2 }, { 2, h - 3 }, { w - 3, h - 3 } }) do HUD.rect(x + d[1], y + d[2], 1, 1, 'rgba(168,152,124,0.4)') end end
  end
end
-- the icon of object i in the slot's middle; render_img = the inspect view's own (style 'render')
function UI.icon(i, x, y, w, h, render_img, hot)
  local st = UI.ICONS[UI.S.icons]
  local ix, iy = x + floor((w - UI.ICON)/2), y + floor((h - UI.ICON)/2)
  if st == 'render' then
    if render_img then HUD.image(render_img, ix, iy, UI.ICON, UI.ICON) end
  else
    -- (round 49: at the window's resolution, twice the game's pixels: the files are 2*UI.ICON square)
    HUD.texture_hi(icon_tex((hot and (st == 'ember' or st == 'lit')) and (st .. '_hot') or st, i), ix, iy, UI.ICON, UI.ICON)
  end
end

-- a button with its label (the inspect view's YES / NO)
function UI.button(x, y, w, h, label, hot, primary)
  local fr = UI.FRAMES[UI.S.frame]
  local th = HUD.text_height(1)
  local ty = y + floor((h - th)/2 + 0.5)
  if fr == 'boxed' then
    HUD.rect(x, y, w, h, hot and 'rgba(242,227,194,0.9)' or 'rgba(20,16,13,0.85)')
    edges(x, y, w, h, 'rgba(168,152,124,0.8)', 'rgba(168,152,124,0.8)')
    HUD.text(label, x + w/2, ty, hot and '#141009' or CREAM, 1, 'center')
  elseif fr == 'plate' then
    HUD.rect(x, y, w, h, hot and 'rgba(58,44,32,0.96)' or 'rgba(34,27,21,0.94)')
    edges(x, y, w, h, hot and 'rgba(224,160,112,0.95)' or 'rgba(86,72,57,0.95)', 'rgba(9,7,5,0.95)')
    HUD.text(label, x + w/2, ty, hot and CREAM or DIM, 1, 'center', nil, 'rgba(8,6,5,0.85)')
  elseif fr == 'brackets' then
    corners(x, y, w, h, hot and CREAM or 'rgba(168,152,124,0.7)', hot and 5 or 3)
    HUD.text(label, x + w/2, ty, hot and CREAM or DIM, 1, 'center', nil, 'rgba(8,6,5,0.85)')
  else   -- bare, lamp: the word; the one under the pointer glows (round 45: no underlines)
    if hot then
      local tw = HUD.text_width(label, 1)
      local gw, gh = tw + 28, th + 16
      HUD.texture(word_glow(gw, gh), floor(x + w/2 - gw/2), floor(ty + th/2 - gh/2), gw, gh)
    end
    HUD.text(label, x + w/2, ty, (hot or primary) and CREAM or DIM, 1, 'center', nil, 'rgba(8,6,5,0.85)')
  end
end

-- round 51: a one-glyph button drawn larger (the viewer's X), cream, the lamp's glow under the pointer
function UI.glyph_button(x, y, w, h, label, hot, scale)
  local th = HUD.text_height(scale)
  local ty = y + floor((h - th)/2 + 0.5)
  if hot then
    local tw = HUD.text_width(label, scale)
    local gw, gh = tw + 30, th + 18
    HUD.texture(word_glow(gw, gh), floor(x + w/2 - gw/2), floor(ty + th/2 - gh/2), gw, gh)
  end
  HUD.text(label, x + w/2, ty, CREAM, scale, 'center', nil, 'rgba(8,6,5,0.85)')
end

return UI
