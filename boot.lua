--[[
  boot.lua -- ONE-TIME WORK (never reloads): layers, the program library, the post chain, the
  game (port/game.lua builds the cave, the lich, the snakes, the powers, ...), the state main.lua's
  definitions read and write.
]]
-- the browser's Math (the engine's js_* functions: correctly rounded, as Chrome's V8 gives them, and
-- V8's hypot), before any module takes its locals from math: the same numbers as the three.js build
math.sin, math.cos, math.tan, math.asin, math.acos, math.atan, math.exp = js_sin, js_cos, js_tan, js_asin, js_acos, js_atan, js_exp

local POST = require('port.post')
local LD = require('port.three.loader')
local GM = require('port.game')
require('port.debug')

G = { render_acc = 0 }

-- three.js's compiled programs, loaded as they are first used
do
  local index = require('assets.port.programs.programs')
  local lib = setmetatable({}, { __index = function(t, key)
    local n = index[key]
    if not n then return nil end
    local nn = string.format('%02d', n)
    local src = { vs = file_read_string('assets/port/programs/' .. nn .. '.vs.glsl'), fs = file_read_string('assets/port/programs/' .. nn .. '.fs.glsl') }
    if key == 'post.final|post|0|-' then
      -- the HUD: three.js's canvas texture held straight alpha; an Anchor layer holds premultiplied
      local a, b = src.fs:find('c = mix(c, hud.rgb, hud.a*uHud);', 1, true)
      assert(a, 'post.final: the HUD line moved')
      src.fs = src.fs:sub(1, a - 1) .. 'c = c*(1.0 - hud.a*uHud) + hud.rgb*uHud;' .. src.fs:sub(b + 1)
    end
    rawset(t, key, src)
    return src
  end })
  G.programs = lib
end

G.screen_layer = layer_new('screen')
G.hud_layer = layer_new('hud')
G.R = POST.create({ programs = G.programs })
G.R.set_hud(G.hud_layer)
G.R.statics = LD.group('statics')
G.game = GM.create(G.R, G.hud_layer)
G.game.G.cave.set_darkness(G.game.G.dark)
G.game.tick()                     -- main.js ticks once before its first render

-- every program compiled now (~0.4 s), so nothing hitches the first time a power or object shows
do
  local index = require('assets.port.programs.programs')
  for key in pairs(index) do G.R.renderer:program(key) end
end
