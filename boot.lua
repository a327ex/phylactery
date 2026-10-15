--[[
  boot.lua -- ONE-TIME WORK (never reloads): layers, the program library, the post chain, the
  game (port/game.lua builds the cave, the lich, the snakes, the powers, ...), the state main.lua's
  definitions read and write.
]]
-- the browser's Math (the engine's js_* functions: correctly rounded, as Chrome's V8 gives them, and
-- V8's hypot), before any module takes its locals from math: the same numbers as the three.js build
math.sin, math.cos, math.tan, math.asin, math.acos, math.atan, math.exp = js_sin, js_cos, js_tan, js_asin, js_acos, js_atan, js_exp

-- what the GPU gets each frame (object matrices, moving vertices, the snakes' rings) rounded to 14
-- mantissa bits (2026-10-03, APR v15): the recording holds exactly what is drawn, without the noise
-- of bits no pixel shows; recordings ~64% smaller. Game state is untouched (only the GPU's copies).
gpu_precision(14)

-- (2026-10-15, Phylactery 18) a STORE build: steam-release/package.py puts .anchor-build in the package (store=steam),
-- and port/game.lua then plays it as a player's copy (GAME_STORE): no testing keys, no sound tool, no site
do local b = file_read_string('.anchor-build'); GAME_STORE = b and b:match('store=(%w+)') or nil end

local BOOT_T = { perf_time() }       -- (2026-10-15, session 17: where the boot's time goes, printed under the benchmark)
-- (and inside the game's create: BOOT_MARK(name) notes the time since the last mark, under the benchmark only)
local BOOT_MARKS = {}
if require('port.bench').active() then
  local last = perf_time()
  function BOOT_MARK(name) local now = perf_time(); BOOT_MARKS[#BOOT_MARKS + 1] = string.format('%s %.0f', name, (now - last)*1000); last = now end
end
require('port.bench').host_emulation()     -- (the benchmark as the site hosts the game: tools/webbench WEBBENCH_SITE=1)
require('port.bench').audio_switches()     -- (WEBBENCH_PLAIN=1: plain voices)
local POST = require('port.post')
local LD = require('port.three.loader')
local GM = require('port.game')
require('port.debug')

G = { render_acc = 0 }

-- three.js's compiled programs, loaded as they are first used
do
  local index = require('assets.port.programs.programs')
  local lib = setmetatable({}, { __index = function(t, key)
    -- round 59: the egg drawn both sides once it cracks (its inside shows): the same program as its front side's
    if key == 'cave.egg|world|2|-' then local src = t['cave.egg|world|0|-']; rawset(t, key, src); return src end
    local n = index[key]
    if not n then return nil end
    local nn = string.format('%02d', n)
    local src = { vs = file_read_string('assets/port/programs/' .. nn .. '.vs.glsl'), fs = file_read_string('assets/port/programs/' .. nn .. '.fs.glsl') }
    -- round 45: the orbs' markings (port/orbmarks.lua), patched into their tracer as it loads
    local mk = require('port.orbmarks').patch_for(key)
    if mk then src.fs = mk(src.fs) end
    -- round 59: the egg cracks (port/silhouette.lua)
    if key == 'cave.egg|world|0|-' then src.vs, src.fs = require('port.silhouette').patch_egg(src.vs, src.fs) end
    if key == 'post.final|post|0|-' then
      -- the HUD: three.js's canvas texture held straight alpha; an Anchor layer holds premultiplied
      local a, b = src.fs:find('c = mix(c, hud.rgb, hud.a*uHud);', 1, true)
      assert(a, 'post.final: the HUD line moved')
      src.fs = src.fs:sub(1, a - 1) .. 'c = c*(1.0 - hud.a*uHud) + hud.rgb*uHud;' .. src.fs:sub(b + 1)
    end
    rawset(t, key, src)
    return src
  end })
  require('port.silhouette').add_programs(lib)     -- (round 57: its own programs, under three.js-style keys)
  G.programs = lib
end

G.screen_layer = layer_new('screen')
G.hud_layer = layer_new('hud')
-- round 49 (owner: the icons "don't have enough detail, like they're pixelated"): the inventory's icons
-- drawn at the window's resolution, over the upscaled game (hud.lua HUD.texture_hi; round 44's layer)
G.ui_layer = layer_create('ui_hi', 'rough', 640*2, 360*2)
require('port.hud').hi_layer = G.ui_layer
G.R = POST.create({ programs = G.programs })
G.R.set_hud(G.hud_layer)
G.R.statics = LD.group('statics')
BOOT_T[2] = perf_time()
G.game = GM.create(G.R, G.hud_layer)
G.game.G.cave.set_darkness(G.game.G.dark)
BOOT_T[3] = perf_time()
G.game.tick()                     -- main.js ticks once before its first render
BOOT_T[4] = perf_time()

-- every program compiled now (~0.4 s), so nothing hitches the first time a power or object shows
-- (2026-10-15, session 17: on the web that took ~5 s with the page frozen: 53 programs, the heaviest ~0.38 s each
-- with ANGLE (tools/webbench, WEBBENCH_SITE=1). Hosted on the site they are compiled one a drawn frame instead
-- (main.lua draw, G.warm) while nothing is drawn and nothing moves (G.intro; the site's game host shows the game's name
-- over the empty frame meanwhile, the page alive): the 27 the scene draws before his click, the 4 his walk in adds,
-- the fight's. The 13 of the thrown objects and the viewer (later()) wait for the viewer: an object's are compiled as
-- its viewer opens (port/game.lua warm_object; paced through the first seconds instead, they made 12 hitches of up to
-- 0.46 s right as the scene showed). The first two sets were read off a hosted run (scratch/s17/scene_programs_probe.lua);
-- a program not compiled yet when first drawn is compiled then, as it always was.)
local SCENE = { 'cave.dome|world|2|-', 'cave.dust|world|0|-', 'cave.egg|world|0|-', 'cave.floor|world|0|-', 'cave.occluder|world|2|-',
  'cave.rock|world|0|-', 'cave.wall|world|2|-', 'depth|-', 'depth|i', 'fx.chunks|world|0|i', 'fx.points.dot.add|world|0|-',
  'fx.points.dot.alpha|world|0|-', 'fx.points.flame.add|world|0|-', 'fx.points.shard.add|world|0|-', 'fx.ribbons|world|2|-',
  'gore.blood|world|0|-', 'gore.bone|world|0|i', 'gore.meat|world|0|i', 'gore.scraps|world|2|i', 'gore.splat|world|0|i',
  'item.orbs|world|0|-', 'leak.flakes|world|2|i', 'lich.gem|world|0|-', 'post.blur|post|0|-', 'post.bright|post|0|-',
  'post.final|post|0|-', 'warp.streaks|warp|2|-' }
local WALK = { 'item.mask|world|2|-', 'snakes.body|world|0|-', 'snakes.eye|world|0|-', 'warp.puffs|warp|2|-' }
-- (session 17, later) the programs not in three.js's export, made at the ending: the silhouettes' (port/silhouette.lua)
-- and the cracked egg's two-sided one. Compiled the first time they drew, they made the stutters "at the very end"
-- (his death's step: 83 ms on the desktop); now compiled with the rest (after the intro on the site).
local EXTRA = { 'sil.flat|sil|2|-', 'sil.comp|post|0|-', 'sil.flat|sil|2|i', 'sil.clip|sil|2|-', 'cave.egg|world|2|-' }
local WARM_ORDER = { '^snakes%.', '^lens%.', '^fx%.', '^warp%.', '^rock%.', '^leak%.', '^gore%.', '^cave%.', '^depth', '^post%.', '' }
local function later(key) return key:find('|inspect|', 1, true) or key:find('^inspect%.') or key:find('^item%.[^|]*|world') end
if GAME_HOSTED then
  local index = require('assets.port.programs.programs')
  local rank = {}
  for i, k in ipairs(SCENE) do if index[k] then rank[k] = i end end
  for i, k in ipairs(WALK) do if index[k] then rank[k] = 100 + i end end
  for key in pairs(index) do
    if not rank[key] then
      if later(key) then rank[key] = 400
      else for i, p in ipairs(WARM_ORDER) do if key:find(p) then rank[key] = 200 + i; break end end end
    end
  end
  G.warm = {}
  for key in pairs(index) do G.warm[#G.warm + 1] = key end
  for _, key in ipairs(EXTRA) do if not index[key] and G.programs[key] then rank[key] = 400; G.warm[#G.warm + 1] = key end end
  table.sort(G.warm, function(a, b)                 -- (taken from the end: the first wanted last in the list)
    if rank[a] ~= rank[b] then return rank[a] > rank[b] end
    return a > b
  end)
  G.intro = 0
  for _, k in ipairs(G.warm) do if rank[k] < 400 then G.intro = G.intro + 1 end end
  if G.intro == 0 then G.intro = nil end
  -- (session 17, later) an engine that compiles in the background (gpu_program_async, KHR_parallel_shader_compile
  -- on the web): every program is started now, the most wanted first, and the intro ends once the scene's, the walk
  -- in's and the fight's are done (main.lua draw); the objects' finish meanwhile. The live site's engine before it
  -- has no gpu_program_async: one a frame, as above.
  if type(gpu_program_async) == 'function' then
    G.warm_async = true
    for i = #G.warm, 1, -1 do G.R.renderer:program_async(G.warm[i]) end
  end
else
  local index = require('assets.port.programs.programs')
  local each = require('port.bench').active() and {} or nil
  for key in pairs(index) do
    local t = each and perf_time()
    G.R.renderer:program(key)
    if each then each[#each + 1] = { key, (perf_time() - t)*1000 } end
  end
  for _, key in ipairs(EXTRA) do if not index[key] and G.programs[key] then G.R.renderer:program(key) end end
  if each then
    table.sort(each, function(a, b) return a[2] > b[2] end)
    local top = {}
    for i = 1, #each do top[#top + 1] = string.format('%s %.0f', each[i][1], each[i][2]) end
    print('BENCH programs ms: ' .. table.concat(top, ', '))
  end
end
BOOT_T[5] = perf_time()
BOOT_END = BOOT_T[5]
if require('port.bench').active() then
  local T = BOOT_T
  print(string.format('BENCH boot ms: modules %.0f, create %.0f, first tick %.0f, programs %.0f', (T[2] - T[1])*1000,
    (T[3] - T[2])*1000, (T[4] - T[3])*1000, (T[5] - T[4])*1000))
  print('BENCH boot create ms: ' .. table.concat(BOOT_MARKS, ', '))
end

-- round 64: the garbage collector paced by the game, a little every tick (port/gcpace.lua)
require('port.gcpace').start()
