--[[
  game.lua -- the port to Anchor: web/src/main.js. The lich under the player's hand in the ending's
  cave: WASD / arrows move him relative to the camera, holding the left mouse button sends him to
  the floor under the cursor; the six powers (5-0 remove one, its object drops), the ending (T:
  every power removed; the snakes coil round the egg; the win cuts to black and the message fades
  in). 1-4 / Y cameras, the round keys (U N Z M O K X L F J R G P B), H hides the text.
  Round 48 (owner, 2026-10-05: "let's just start the game at the egg cave, that's all that exists,
  single camera view"): he starts in the room carrying all six objects in an inventory (top right);
  clicking one (or 5-0) brings up the model viewer with its title, its text and one button, THROW: he
  throws it the way he is facing as the viewer goes away; walking back to it picks it up again.
  (The ways in of rounds 40, 45 and 47 are set aside in archive/.)
  Round 50 (owner, 2026-10-05): the snakes come in waves (snakes.lua) and the lich handles them in bouts
  with group versions of the attacks (powers.lua); F3 forces one way of handling them, F9 / F10 send a
  pack / a spread now (testing). LICH_ROOM=1 keeps the old flow (the three.js build's, for the digests).
  Fixed 60 Hz ticks as main.js steps them. GAME (a global) is the harness: the same calls as
  window.GAME in the three.js build, for anchor drive eval.
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local U = require('port.util')
local CAVE = require('port.cave')
local LICH = require('port.lich')
local NAV = require('port.nav')
local MV = require('port.mover')
local SN = require('port.snakes')
local FIRE = require('port.fire')
local FXM = require('port.fx')
local GORE = require('port.gore')
local WARP = require('port.warp')
local PW = require('port.powers')
local BEAM = require('port.beam')
local LENS = require('port.lens')
local CL = require('port.coil')
local HUD = require('port.hud')
local SL = require('port.silhouette')
local RG = require('port.ragdoll')
local EP = require('port.eggphys')
local GCP = require('port.gcpace')
local PROF = require('port.prof')       -- (2026-10-15: the benchmark's section timings, port/bench.lua)
local MAT = require('port.three.materials')
local UI = require('port.ui_style')
local AU = require('port.audio')         -- 2026-10-10: the sounds (slots; tools/sfx_spec.py has the picks and why)
local SU = require('port.soundui')       -- and their names on screen
local US = require('port.unlock_snd')    -- 2026-10-14: the site's unlock's sounds (slots of ours, tuned in our editor)
-- the site's unlock asks for them through its game host at its real moments (unlock_fx.lua)
function game_unlock_sound(event, i, n) return US.play(event, i, n) end
local Vector2, Vector3 = TM.Vector2, TM.Vector3
local clamp, smoothstep = U.clamp, U.smoothstep
local sqrt, abs, sin, cos, atan2, exp, floor, ceil, min, max, pi = math.sqrt, math.abs, math.sin, math.cos, math.atan, math.exp, math.floor, math.ceil, math.min, math.max, math.pi
local DT = 1/60
local HOSTED = GAME_HOSTED == true     -- inside the site's game host (a327ex.com): no test keys, the site's unlock
-- (2026-10-14) hosted by the desktop's unlock test with the sound editor on (the site's game host sets it there only):
-- the unlock's sounds tuned while the whole unlock plays; never on the website
local EDITOR = GAME_EDITOR == true
-- (the desktop unlock test's TAB, with the game out of view: the editor's list)
function game_sound_editor() if EDITOR and SU.mode() == 'play' then SU.open_list() end end
-- (2026-10-15, owner: "Scrolling down to look for sounds doesn't work because it scrolls down the page.") the site's
-- page keeps the wheel over us (wheel_through) except while the editor is open: its lists scroll with it
function game_wants_wheel() return EDITOR and SU.mode() ~= 'play' end
-- (same day: "R doesn't work after going through the tab system") the keyboard is ours only while the editor is open,
-- not merely while the cursor is over us (after TAB we fill the window); the site's R asks what it is doing (only its
-- search takes typed text) and closes it, saved, before playing the unlock again
function game_wants_keys() return EDITOR and SU.mode() ~= 'play' end
function game_editor_mode() return EDITOR and SU.mode() or nil end
function game_sound_close() if EDITOR and SU.mode() ~= 'play' then SU.resume() end end

local GM = {}

function GM.create(R, hud_layer)
  -- 2026-10-10: the sounds' picks (sound_picks.lua) and the cave's own sound under everything
  AU.load_picks()
  AU.hooks.zone = function() return 'cave' end          -- (one cave: its reverb; no walls to hear through)
  AU.loop('cave_amb')
  AU.loop('shaft_hum', { pos = { 0.33, 3.0, 0.15 } })     -- (in the sun shaft over the egg, cave.lua)
  -- round 65: each run its own (the engine's seed); LICH_ROOM keeps the fixed seeds (the digests). LICH_SEED in the
  -- environment: a number = that run's seed; 'fixed' = the fixed seeds (the game as it played before round 65)
  local ls = os.getenv('LICH_SEED')
  if os.getenv('LICH_ROOM') or ls == 'fixed' then U.RUN = nil
  elseif ls and tonumber(ls) then U.RUN = math.floor(tonumber(ls)) & 0xFFFFFFFF
  else U.RUN = random_get_seed() & 0xFFFFFFFF end
  if require('port.bench').active() then U.RUN = require('port.bench').seed() end   -- (2026-10-15: the benchmark, one fixed run)
  local cave = CAVE.build(R)
  local lich = LICH.create(R, { GU = cave.GU })
  -- round 45: the lich's own mask, flat white (port/lichmask.lua; F5 cycles it for comparison)
  local lmask = require('port.lichmask').create(lich, cave.GU, R)
  local EGG = cave.egg.position
  local G = { t = 0, tick = 0, cam = 0, manual = false, hud = false, dark = 1, surface = 2,     -- (hud: the testing text, H; off from the start since 2026-10-15)
    static = { eye = { -3.6, 9.8, -10.4 }, tgt = { 0.4, 0.1, 2.4 } },
    free = { yaw = 200, pitch = 18, dist = 4.5 }, egg_view = { yaw = 195, pitch = 32, dist = 3.4 } }
  G.R = R; G.cave = cave; G.lich = lich; G.lmask = lmask
  cave.set_surface(G.surface)
  UI.set_bundle(UI.S.bundle)

  -- where he can go (the room camera's frame blocks him too)
  local room_cam = T.PerspectiveCamera.new(50, R.W/R.H, 0.1, 200)
  room_cam.position:set(G.static.eye[1], G.static.eye[2], G.static.eye[3]); room_cam:look_at(G.static.tgt[1], G.static.tgt[2], G.static.tgt[3])
  room_cam:update_matrix_world(); room_cam:update_projection_matrix()
  local nav = NAV.build({ geo = cave.rock_geo, ground_y = cave.ground_y })
  do
    local q = Vector3.new()
    local function in_frame(x, y, z) q:set(x, y, z):project(room_cam); return q.z < 1 and abs(q.x) < 0.92 and q.y > -0.9 and q.y < 0.86 end
    nav.block(function(x, z)
      if (x - EGG.x)^2 + (z - EGG.z)^2 < 0.45*0.45 or x*x + z*z > 14*14 then return true end
      local g = cave.ground_y(x, z)
      return not in_frame(x, g + 0.15, z) or not in_frame(x, g + 2.1, z)
    end)
    nav.finish()
  end
  G.nav = nav
  G.mode = 'room'
  local START = Vector3.new(CAVE.LAYOUT.hover.x, 0, CAVE.LAYOUT.hover.z)
  local mover = MV.create(nav, lich, START, atan2(EGG.x - START.x, EGG.z - START.z))
  local L = mover.p
  local fire = FIRE.create(R, cave)
  local VARIED = not os.getenv('LICH_ROOM')
  if VARIED then R.renderer.transmission_copy = true end   -- (2026-10-15: the glass sees a copy of the world, not a second render; three/renderer.lua)
  -- (round 50 fix: the snakes' own grid of the rocks: no frame, no egg, only rock too tall to crawl over)
  local snake_nav = VARIED and NAV.build({ geo = cave.rock_geo, ground_y = cave.ground_y, block_h = 0.2 }).finish() or nil
  local snakes = SN.create(R, cave, function() return L end, fire, nil, nil, { varied = VARIED, nav = snake_nav })
  G.mover = mover; G.snakes = snakes; G.fire = fire

  local fx = FXM.create(R, cave)
  local gore = GORE.create(R, cave, snakes, fx, U.run_rng(41))
  local warp = WARP.create(R)
  local powers = PW.create({ R = R, cave = cave, snakes = snakes, fx = fx, gore = gore, warp = warp, fire = fire, lich = lich, mover = mover, egg = EGG,
    get_L = function() return L end, rng = U.run_rng(29), varied = VARIED })
  G.powers = powers; G.fx = fx; G.gore = gore; G.warp = warp
  -- round 57: the ending's silhouettes (the egg with the snakes coiled on it; the lich with his mask)
  local sil = SL.create(R)
  R.sil = sil
  R.sil_subjects = function()
    local egg = { cave.egg }
    for _, s in ipairs(snakes.coiled) do egg[#egg + 1] = s.m; egg[#egg + 1] = s.eyes[1]; egg[#egg + 1] = s.eyes[2] end
    -- (round 61: the egg's pieces once it breaks: the cap, the shards)
    if G.eggphys then for _, r in ipairs(G.eggphys.roots) do egg[#egg + 1] = r end end
    -- (round 58: the snakes' burst, pale, then fading, from his death on: before it any gore is the dark's)
    return { egg = egg, lich = { lich.root, lmask.mesh }, shell = cave.egg.user_data.shell, cap = G.eggphys and G.eggphys.cap and G.eggphys.cap.mesh,
      gore = (G.SEQ and G.SEQ.dead) and gore.meshes() or nil }
  end
  G.sil = sil
  -- round 61: the egg as a physics object from his death on, its knocks and its break (port/eggphys.lua)
  local ep
  do
    local floor_geo
    for _, m in ipairs(cave.group.children) do if m.material and m.material.name == 'cave.floor' then floor_geo = m.geometry end end
    ep = EP.create({ R = R, egg = cave.egg, shell = cave.egg.user_data.shell, floor_geo = floor_geo, rock_geo = cave.rock_geo, ground_y = cave.ground_y })
  end
  G.eggphys = ep
  gore.follow(function() return L end)
  local POWER_KEYS = { '5', '6', '7', '8', '9', '0' }

  -- the powers' objects (round 28) and the inspect view
  -- (hosted, the site's require finds the game's own files: package.path is the site's, so it is not asked)
  local ITEMS_M = (HOSTED or package.searchpath('port.items', package.path)) and require('port.items') or nil
  local items, inspect
  if ITEMS_M then
    items = ITEMS_M.create({ R = R, cave = cave, fx = fx, warp = warp, nav = nav, lich = lich, mover = mover, get_L = function() return L end,
      glance = function(p) powers.glance(p) end, varied = VARIED })
    local INSPECT_M = require('port.inspect')
    inspect = INSPECT_M.create({ R = R, items = items, ITEMS = ITEMS_M.ITEMS })
  end
  G.items = items; G.inspect = inspect
  local function inspect_active() return inspect and inspect.S.active end
  local function toggle_power(i)
    local on = powers.toggle(i)
    if on == false then AU.play('power_lost') end
    if items then
      if on == false then items.drop(i) elseif on == true then items.take(i) end
    end
    return on
  end
  -- round 48: giving one up goes through the model viewer's one button, THROW (he throws it the way
  -- he faces); one already given up comes back at once (keys 5-0, testing only)
  local function ask_remove(i)
    if not inspect then return toggle_power(i) end
    if not powers.is_on(powers.ALL[i + 1]) then return toggle_power(i) end
    inspect.open(i, { remove = true })
  end
  local function throw_power(i)
    if not powers.is_on(powers.ALL[i + 1]) then return end
    powers.toggle(i)
    AU.play('power_lost')
    if items then items.throw(i, mover.yaw()) end
  end

  -- ------------------------------------------------------------------ the ending (round 36)
  local END = { w = 0, level = 0, grips = 0, spasm = 2, won = false, over = -1, queue = {}, queue_t = 0, hand = 0 }
  G.END = END
  local held = {}
  local mouse = { down = false, px = 0, py = 0 }
  local goal, best, stall, script_keys = nil, math.huge, 0, nil
  snakes.on_grip = function()
    END.grips = END.grips + 1; lich.hit(0.5 + 0.1*min(END.grips, 6) + (END.grips == 1 and 0.5 or 0))
    AU.play('coil_grip', { pos = { EGG.x, EGG.y + 0.4, EGG.z } })
    if END.grips == 1 then AU.play('ending_begin') end      -- (his control ends here: the ending's sequence starts)
  end
  snakes.on_won = function()
    END.won = true; END.over = 0; held = {}; mouse.down = false; goal = nil; lich.hit(1.7)
    AU.play('coil_win', { pos = { EGG.x, EGG.y + 0.4, EGG.z } })
  end
  -- round 37 (owner: "The cut to black should be instant, the text can fade in")
  local OVER = { hold = 1.8, fade = 0, text_at = 0.8, text_in = 1.4 }
  -- round 47 (owner: "we should only zoom in on the liches face at the end ... when the game ends"):
  -- after the win the camera pushes in on his face, then the cut to black; F8 turns it off. (LICH_ROOM=1
  -- keeps round 37's 1.8 s hold, so its digest run stays the same)
  local END_ZOOM = { on = true, dur = 2.6, extra = 1.4 }
  if not os.getenv('LICH_ROOM') then OVER.hold = OVER.hold + END_ZOOM.extra end
  local MESSAGE = { '[ YOUR MESSAGE ]' }                -- his to write; one entry per line
  -- round 56 (owner, 2026-10-07: "as the egg gets enveloped, the camera zooms in slowly, the lich stops being
  -- controlled by the player and slowly moves to the right of the egg, facing left, the camera should lower such
  -- that the frame we have is egg <- lich composed nicely, once we have that frame, let's just stop everything
  -- there and pause the game"): from the first grip his control ends and he drifts to a spot right of the egg
  -- (as the room camera sees it), facing it; the camera eases from the room's frame down to a low two-shot as
  -- the shell is covered (round 56 stopped everything there; round 57 lets it all play on, no end). It takes the
  -- place of round 47's push-in and the cut to black for now. Without LICH_ROOM only.
  local SEQ = { on = false, t = 0, k = 0, spot = nil, eye = nil, tgt = nil, sil_t0 = nil, k2 = 0 }
  G.SEQ = SEQ
  -- the two-shot: his spot on the sunlight's edge right of the egg (the shaft is the lid's hole, `edge` m round, leaning
  -- with the sun: its edge measured at `edge_h` m up, about his chest); the camera `back` m behind the point `mid` of
  -- the way from the egg to him, `up` m over the look point (look_y over the floor); its fov; his pace there; the
  -- camera's fastest progress (of the whole move) per second.
  -- round 56b (owner: "The final shot is way too close, movement needs to be around the light source instead of
  -- through the middle, and the lich needs to also be around the light's edge instead of completely inside it"):
  -- he goes round the light's edge to his spot, which is on it; the camera further back.
  -- round 56c (owner: "Let's see 8m, 9m, 10m back and slightly different angles too"), settled in round 57 ("10m,
  -- lower"): the camera looks at the point `mid` of the way from the egg to him, look_y over the floor, from `back` m
  -- along the room camera's heading, `pitch` degrees down onto it
  local SHOT = { edge = 2.2, back_deg = 30, edge_h = 1.4, mid = 0.5, back = 10.0, pitch = 3, look_y = 1.0, fov = 40, pace = 0.5, rate = 1/6 }
  -- round 57 (owner, 2026-10-07: "we get close to this final shot, we need some kind of shader or effect where the
  -- only the egg and lich are visible but they become not textured, like flat colors, so the final shot is darkness
  -- + two sillouettes ... The visual effect should start slowly in the middle of the movement towards the final shot,
  -- then we get to the final shot at some percentage of the effect happening, then slowly it completes while at the
  -- final shot"): port/silhouette.lua; it starts once the camera is `from` of the way down and runs `dur` s, eased in
  -- and out; UP / DOWN in the sequence: its colours
  local SIL = { from = 0.5, dur = 12 }
  -- round 58 (owner, 2026-10-07: "After they've both turned pale (my choice) and the final shot has played for a
  -- while, make the lich fall on the floor, face to the camera, mask also drops and stops floating in front of him.
  -- His body should lie on the floor limp as though he died. At the same time as he drops, all snakes should explode
  -- as they do from the lift power and the egg should then be visible twitching, like a pokeball when its trying to
  -- capture a pokemon. The camera focuses and zooms on the egg hatching and once it's close enough it hatches"):
  -- `hold` s after the silhouettes are whole he dies (round 59: as a rag doll, port/ragdoll.lua, the arm that pointed
  -- reaching for the egg; round 59b, owner: "Lich is falling too close to the egg, should fall more to the side ...
  -- such that it's kind of (not totally) on the background": pushed `back` m/s away from the camera and `out` m/s
  -- away from the egg) and every snake bursts; from `wobble_at` s the egg is knocked from inside, faster and faster
  -- (round 61: port/eggphys.lua); from `zoom_at` s the camera goes in on it over `zoom` s (eased), to `close` m
  -- from a point `close_y` m up it; at `hatch_k` of the way it hatches (silhouette.lua); the burst's pieces fade into
  -- the dark between `gore_fade` s after it. Round 62 (owner: "as the egg is moving and breaking, fade everything in
  -- the background out to the website's background color, so that only the egg remains visible"): from the first
  -- knock to `fade_after` s after it opens, everything but the egg and its pieces goes to the site's page colour
  local DIE = { hold = 4.0, back = 0.5, out = 0.0, wobble_at = 1.3, zoom_at = 2.2, zoom = 7.0, hatch_k = 0.86, close = 2.1, close_y = 0.42, gore_fade = { 1.0, 2.6 },
    fade_after = 1.0 }
  SEQ.label_n = 0
  G.SHOT = SHOT
  -- round 56: where the game starts. 'ENDING' (owner, 2026-10-07: "Start the game for me with snakes near the
  -- egg"): every power already given up (their objects thrown out of the two-shot) and the pool sent in from 4-6.5 m
  -- out, 1.5 s apart, so the shell is being covered within seconds. 'EGG' (round 60, owner: "Let's focus on the egg
  -- now. Start the scene from there"): the sequence already at the two-shot, dim, and he dies on the first tick, so the
  -- egg's part follows at once (no snakes, no coil). 'GAME': the game as it starts for players (round 63, owner: "now
  -- let me start from the actual start of the game": the default again).
  local START_AT = os.getenv('LICH_START') or 'GAME'       -- (LICH_START=EGG / ENDING in the environment: the ending's tests)
  -- (2026-10-13, the unlock's tests on the site: the site's admin switch LICH FROM THE EGG asks for the egg start; there
  -- it waits for the first click inside the game, so it doesn't play out before he looks)
  if HOSTED and site_game_start then START_AT = site_game_start('lich-survivors') or START_AT end
  local EGG_WAIT = HOSTED and START_AT == 'EGG'
  -- round 63 (owner, 2026-10-08: "The lich should appear walking automatically towards the egg from offscreen. This
  -- will later be tied to the event of the player focusing on the play window when we upload the game to the
  -- website"): in the players' start he waits out of the room camera's frame, `from` down the lane from the tunnel,
  -- until game.begin() (`auto`: at once, for now; on the site, the window's focus); then he walks in on his own to
  -- where the game starts him, facing the egg, and only there is he the player's and do the waves start. Round 66
  -- (owner: "it should move there as though it was clicked to move near the egg"): his walk in is a click there,
  -- the goal's own way (full pace, the same braking, the body's whole motion), aimed `short` m before his spot: a
  -- click's floaty stop carries him on that far (measured 0.57 m), so he settles where the game starts him
  -- (2026-10-09, the site: on a327ex.com the game runs inside the site's game host, GAME_HOSTED; there the walk in waits
  -- for the visitor's first click inside the game, and the run's start and the egg's opening are reported to the site's
  -- unlock (renderer/unlock.lua: the server checks the ending, the powers left and the run's length))
  local INTRO = { from = { x = START.x, z = -8.6 }, auto = not HOSTED, state = nil, go = false, short = 0.57 }
  if VARIED and START_AT == 'GAME' then INTRO.state = 'wait' end
  local function intro_on() return INTRO.state == 'wait' or INTRO.state == 'walk' end
  local function begin()
    if INTRO.state ~= 'wait' then return end
    INTRO.state = 'walk'; INTRO.go = true
    if HOSTED and site_unlock_begin then site_unlock_begin('lich-survivors') end
  end
  local function over_black() return END.won and END.over >= OVER.hold + OVER.fade end
  local end_rng = U.run_rng(77)
  local function remove_all()
    END.queue = {}
    for i, a in ipairs(powers.ALL) do if powers.is_on(a) then END.queue[#END.queue + 1] = i - 1 end end
    END.queue_t = 0
  end
  local function ending_tick(dt)
    if #END.queue > 0 then
      END.queue_t = END.queue_t - dt
      if END.queue_t <= 0 then toggle_power(table.remove(END.queue, 1)); END.queue_t = 0.4 end
    end
    local hurt = END.grips > 0
    END.w = min(1, END.w + (hurt and dt/0.45 or -dt/1.5)); if END.w < 0 then END.w = 0 end
    local target = END.force_level
    if target == nil then target = END.won and 1 or snakes.coverage end
    END.level = END.level + (target - END.level)*(1 - exp(-dt/0.8))
    cave.egg.user_data.still = min(1, #snakes.coiled)
    lich.hurt.w = END.w*END.w*(3 - 2*END.w); lich.hurt.level = END.level; lich.hurt.hand = END.hand
    mover.face.half = 1.31
    if END.w <= 0 then return end
    -- (2026-10-14, owner: "lich should stop being hurt after he dies, the frequency of his hurting should also increase
    -- the closer it gets to the explosion") dead: no more spasms (the ending's sequence; LICH_ROOM has none)
    if SEQ.dead then return end
    END.spasm = END.spasm - dt
    if END.spasm <= 0 then
      lich.hit(END.w*(0.18 + 0.4*END.level))
      -- the nearer his death (the snakes' burst), the sooner the next: half of it as the silhouettes come in, the rest
      -- over the hold before he dies (DIE.hold), the gap down to a fifth and steadier (its spread narrowing: one draw)
      local near = 0
      if SEQ.on then near = SEQ.e1 and 0.5 + 0.5*clamp((SEQ.t - SEQ.e1)/DIE.hold, 0, 1) or 0.5*sil.e end
      END.spasm = end_rng.float(1.1, 3.2 - 1.5*near)*(1 - 0.4*END.level)*(1 - 0.8*near^1.3)
    end
    mover.face.on = true
    mover.face.yaw = atan2(EGG.x - L.x, EGG.z - L.z)
    mover.face.half = mover.speed() > 0.2 and 0.7 or 0.08
    local m = mover.motion
    m.gaze_w = 0
    m.point = { w = lich.hurt.w, arm = 1, x = EGG.x, y = EGG.y + 0.42, z = EGG.z }
  end

  -- ------------------------------------------------------------------ cameras
  local function v(x, y, z) return Vector3.new(x, y, z) end
  local F = L:clone()
  local ROOM_H = Vector2.new(G.static.tgt[1] - G.static.eye[1], G.static.tgt[3] - G.static.eye[3]):normalize()
  local function from_room(pitch_deg, dist) local p = pitch_deg*pi/180; return v(-ROOM_H.x*cos(p)*dist, sin(p)*dist, -ROOM_H.y*cos(p)*dist) end
  local SIDE_DIR = v(-ROOM_H.y, 0, ROOM_H.x)
  local CAMS = {
    { name = 'ROOM', note = 'THE ROOM CAMERA, FIXED: THE GAME', fov = 50,
      rig = function()
        if G.look then return v(G.look.eye[1], G.look.eye[2], G.look.eye[3]), v(G.look.tgt[1], G.look.tgt[2], G.look.tgt[3]) end
        return v(G.static.eye[1], G.static.eye[2], G.static.eye[3]), v(G.static.tgt[1], G.static.tgt[2], G.static.tgt[3])
      end },
    { name = 'CLOSE', note = "FOLLOWS HIM, FROM THE ROOM CAMERA'S SIDE, LOWER", fov = 45,
      rig = function() return F:clone():add(from_room(18, 4.6)), F:clone():add(v(0, -0.15, 0)) end },
    { name = 'SIDE', note = 'FOLLOWS HIM FROM THE SIDE: A/D TO SEE HIS PROFILE', fov = 45,
      rig = function() return F:clone():add_scaled_vector(SIDE_DIR, 4.4):add(v(0, 0.25, 0)), F:clone():add(v(0, -0.2, 0)) end },
    { name = 'EGG', note = 'AROUND THE EGG: RIGHT-DRAG TO ORBIT, SCROLL TO ZOOM', fov = 45,
      rig = function()
        local fr = G.egg_view
        local y, p = fr.yaw*pi/180, fr.pitch*pi/180
        local c = v(EGG.x, EGG.y + 0.15, EGG.z)
        return c:clone():add(v(sin(y)*cos(p)*fr.dist, sin(p)*fr.dist, cos(y)*cos(p)*fr.dist)), c
      end },
    { name = 'FREE', note = 'RIGHT-DRAG TO ORBIT, SCROLL TO ZOOM', fov = 45,
      rig = function()
        local fr = G.free
        local y, p = fr.yaw*pi/180, fr.pitch*pi/180
        return F:clone():add(v(sin(y)*cos(p)*fr.dist, sin(p)*fr.dist, cos(y)*cos(p)*fr.dist)), F:clone()
      end },
  }
  local CAM_FREE, CAM_EGG = #CAMS - 1, #CAMS - 2          -- 0-based, as main.js
  local function clear_eye(eye, from)
    local d = eye:clone():sub(from)
    local n = ceil(d:length()/0.1)
    for i = 4, n do
      local p = from:clone():add_scaled_vector(d, i/n)
      if nav.rock_at(p.x, p.z) > p.y - 0.3 then return from:clone():add_scaled_vector(d, max(0.2, (i - 3)/n)) end
    end
    return eye
  end
  local function place_camera(dt)
    local c = CAMS[G.cam + 1]
    local k = 1 - exp(-3.5*dt)
    F:lerp(L, k)
    local eye, tgt = c.rig()
    if G.cam ~= 0 and G.cam ~= CAM_EGG then eye = clear_eye(eye, F) end
    cave.set_dome_visible(c.dome ~= false)
    local C = R.world_camera
    C.fov = (G.cam == 0 and G.look and G.look.fov) or c.fov; C:update_projection_matrix()
    -- round 56: down from the room's frame to the two-shot as the shell is covered
    if SEQ.on and G.cam == 0 and not G.look then
      local k = SEQ.k*SEQ.k*(3 - 2*SEQ.k)
      eye = eye:clone():lerp(SEQ.eye, k)
      tgt = tgt:clone():lerp(SEQ.tgt, k)
      C.fov = C.fov + (SHOT.fov - C.fov)*k; C:update_projection_matrix()
    end
    -- round 58: in on the egg as it rocks, until it hatches
    if SEQ.k2 > 0 and G.cam == 0 and not G.look then
      local k = SEQ.k2
      k = k*k*k*(k*(k*6 - 15) + 10)
      local ct = v(EGG.x, EGG.y + DIE.close_y, EGG.z)
      local ce = v(EGG.x - ROOM_H.x*DIE.close, EGG.y + DIE.close_y + DIE.close*sin(SHOT.pitch*pi/180), EGG.z - ROOM_H.y*DIE.close)
      eye = eye:clone():lerp(ce, k)
      tgt = tgt:clone():lerp(ct, k)
    end
    -- the end: in on his face (round 47; not while round 56's sequence runs)
    if END.won and END_ZOOM.on and G.cam == 0 and not G.look and not SEQ.on then
      local k = smoothstep(0.15, END_ZOOM.dur, END.over)
      k = k*k*(3 - 2*k)
      if k > 0 then
        -- (along the way his face points: in the hurt pose it is thrown back, looking up)
        local hp = lich.head_pos()
        local hm = lich.nodes.head.matrix_world.elements
        local fx_, fy_, fz_ = hm[9], hm[10], hm[11]
        local fl = sqrt(fx_*fx_ + fy_*fy_ + fz_*fz_)
        fx_, fy_, fz_ = fx_/fl, fy_/fl, fz_/fl
        if fy_ < -0.2 then fy_ = -0.2 end
        local fe = v(hp.x + fx_*1.05, hp.y + fy_*1.05 + 0.12, hp.z + fz_*1.05)
        eye = eye:clone():lerp(fe, k)
        tgt = tgt:clone():lerp(hp, k)
        C.fov = C.fov + (34 - C.fov)*k; C:update_projection_matrix()
      end
    end
    C.position:copy(eye)
    C.up:set(0, 1, 0)
    C:look_at(tgt)
    C:update_matrix_world()
  end
  local function set_cam(i) G.cam = clamp(floor(i), 0, #CAMS - 1); F:copy(L) end
  -- the two-shot (round 56c/57: 10 m back, lower)
  local function set_framing()
    local x, z = SEQ.spot.x, SEQ.spot.z
    local mx, mz = EGG.x + (x - EGG.x)*SHOT.mid, EGG.z + (z - EGG.z)*SHOT.mid
    local gy = cave.ground_y(mx, mz)
    local p = SHOT.pitch*pi/180
    local hd = SHOT.back*cos(p)
    SEQ.tgt = v(mx, gy + SHOT.look_y, mz)
    SEQ.eye = v(mx - ROOM_H.x*hd, gy + SHOT.look_y + SHOT.back*sin(p), mz - ROOM_H.y*hd)
  end

  -- ------------------------------------------------------------------ input
  local ndc = Vector2.new()
  local function floor_at_px(gx, gy)
    ndc:set(gx/R.W*2 - 1, 1 - gy/R.H*2)
    local cam = R.world_camera
    local o = Vector3.new():set_from_matrix_position(cam.matrix_world)
    local d = Vector3.new(ndc.x, ndc.y, 0.5):unproject(cam):sub(o):normalize()
    local t0, t1 = 0, 0
    local t = 0.3
    while t < 60 do
      local x, y, z = o.x + d.x*t, o.y + d.y*t, o.z + d.z*t
      if y < cave.ground_y(x, z) then t1 = t; break end
      t0 = t
      t = t + 0.08
    end
    if t1 == 0 then return nil end
    for _ = 1, 8 do
      local tm = (t0 + t1)/2
      local x, y, z = o.x + d.x*tm, o.y + d.y*tm, o.z + d.z*tm
      if y < cave.ground_y(x, z) then t1 = tm else t0 = tm end
    end
    local tm = (t0 + t1)/2
    return v(o.x + d.x*tm, o.y + d.y*tm, o.z + d.z*tm)
  end
  local function set_goal(p)
    if not p then return end
    local dx, dz = L.x - p.x, L.z - p.z
    local d = js_hypot(dx, dz)
    local s = 0
    while s < d and nav.is_blocked(p.x, p.z) do p.x = p.x + dx/d*0.1; p.z = p.z + dz/d*0.1; s = s + 0.1 end
    p.y = cave.ground_y(p.x, p.z)
    best = math.huge; stall = 0
    goal = p
  end
  local function pick_goal() set_goal(floor_at_px(mouse.px, mouse.py)) end

  local cf = Vector3.new()
  local function wanted_velocity()
    -- round 63: waiting out of frame; then his walk in to where the game starts him; round 66: as a click there (the
    -- goal set once, then the goal's own way below; no keys, no mouse)
    if INTRO.state == 'wait' then return { x = 0, z = 0 } end
    local walking_in = INTRO.state == 'walk'
    if walking_in and INTRO.go then
      INTRO.go = false
      local dx, dz = START.x - INTRO.from.x, START.z - INTRO.from.z
      local d = js_hypot(dx, dz)
      set_goal(v(START.x - dx/d*INTRO.short, 0, START.z - dz/d*INTRO.short))
    end
    -- round 56: his own way to the spot right of the egg, slowly, easing in; 56b: round the light's edge (onto
    -- its circle, along it the short way, then in to the spot), never across the pool
    if SEQ.on then
      local dx, dz = SEQ.spot.x - L.x, SEQ.spot.z - L.z
      local d = js_hypot(dx, dz)
      if d < 0.03 then return { x = 0, z = 0 } end
      local s = min(SHOT.pace, sqrt(2*MV.MOVE.dec*max(0, d - 0.02))*0.5)
      local rx, rz = L.x - SEQ.c.x, L.z - SEQ.c.z
      local r = js_hypot(rx, rz)
      local th = atan2(rz, rx)
      local dth = atan2(sin(SEQ.th1 - th), cos(SEQ.th1 - th))
      if r < 1e-3 or abs(dth)*SEQ.R < 0.3 then return { x = dx/d*s, z = dz/d*s } end
      local sg = dth > 0 and 1 or -1
      local tx, tz = -rz/r*sg, rx/r*sg                         -- along the circle, toward his spot
      local k = clamp((SEQ.R - r)*2.5, -1.5, 1.5)               -- and back onto it
      local wx, wz = tx + rx/r*k, tz + rz/r*k
      local l = js_hypot(wx, wz)
      return { x = wx/l*s, z = wz/l*s }
    end
    if END.won then return { x = 0, z = 0 } end
    local keys = script_keys
    if keys == nil then keys = ''; for k in pairs(held) do keys = keys .. k end end
    if walking_in then keys = '' end
    local ix, iz = 0, 0
    if keys:find('w', 1, true) then iz = iz + 1 end
    if keys:find('s', 1, true) then iz = iz - 1 end
    if keys:find('d', 1, true) then ix = ix + 1 end
    if keys:find('a', 1, true) then ix = ix - 1 end
    if ix ~= 0 or iz ~= 0 then
      goal = nil
      R.world_camera:get_world_direction(cf); cf.y = 0; cf:normalize()
      local rx, rz = -cf.z, cf.x
      local wx, wz = cf.x*iz + rx*ix, cf.z*iz + rz*ix
      local l = js_hypot(wx, wz)
      local sp = MV.MOVE.speed*(1 - 0.6*END.w)
      return { x = wx/l*sp, z = wz/l*sp }
    end
    if mouse.down and not walking_in then pick_goal() end
    if goal then
      local dx, dz = goal.x - L.x, goal.z - L.z
      local d = js_hypot(dx, dz)
      if mouse.down or d < best - 0.05 then best = d; stall = 0 else stall = stall + DT end
      if (d < 0.12 or stall > 0.5) and not mouse.down then goal = nil; return { x = 0, z = 0 } end
      if d < 0.12 then return { x = 0, z = 0 } end
      local s = min(MV.MOVE.speed*(1 - 0.6*END.w), sqrt(2*MV.MOVE.dec*max(0, d - 0.08))*0.9)
      return { x = dx/d*s, z = dz/d*s }
    end
    return { x = 0, z = 0 }
  end

  -- keys, as main.js's keydown (a press or the OS repeat of a held key)
  local function hit(k) return key_is_pressed(k) or key_is_repeated(k) end
  local MOVE_KEYS = { { 'w', 'w' }, { 'up', 'w' }, { 's', 's' }, { 'down', 's' }, { 'a', 'a' }, { 'left', 'a' }, { 'd', 'd' }, { 'right', 'd' } }
  local function keys_input()
    if HOSTED then
      -- on the site: moving, and the viewer's own keys; every testing key stays home
      if SEQ.on or END.won then return end
      if inspect_active() then
        if inspect.S.accept then
          if hit('return') or hit('enter') or hit('kpenter') or hit('space') then inspect.accept() end
        elseif inspect.S.remove then
          if hit('return') or hit('enter') or hit('kpenter') or hit('space') then inspect.answer(true) end
          if hit('escape') or hit('backspace') or hit('n') then inspect.answer(false) end
        else
          if hit('escape') then inspect.close() end
          if hit('a') or hit('left') then inspect.next(-1) end
          if hit('d') or hit('right') then inspect.next(1) end
        end
        return
      end
      for _, mk in ipairs(MOVE_KEYS) do if hit(mk[1]) then held[mk[2]] = true end end
      return
    end
    if SEQ.on then
      -- round 59: the background (dim / blurred), in the game
      if hit('up') or hit('down') then
        local n = #SL.BGS
        sil.bg = ((sil.bg - 1 + (hit('up') and 1 or -1)) % n + n) % n + 1
        SEQ.label_n = 150
      end
      return
    end
    if END.won then return end
    if inspect_active() then
      if inspect.S.accept then
        if hit('return') or hit('enter') or hit('kpenter') or hit('space') then inspect.accept() end
        if hit('h') then G.hud = not G.hud end
        return
      end
      if inspect.S.remove then
        if hit('return') or hit('enter') or hit('kpenter') or hit('space') then inspect.answer(true) end
        if hit('escape') or hit('backspace') or hit('i') or hit('e') or hit('n') then inspect.answer(false) end
        return
      end
      if hit('i') or hit('escape') or hit('e') then inspect.close() end
      if hit('a') or hit('left') then inspect.next(-1) end
      if hit('d') or hit('right') then inspect.next(1) end
      if hit('m') then items.set_hand_mat(items.opts.hand_mat + 1); inspect.rebuild() end
      if hit('h') then G.hud = not G.hud end
      return
    end
    if hit('i') and inspect and not intro_on() then held = {}; mouse.down = false; inspect.open(); return end
    if items then
      if hit('m') then items.set_hand_mat(items.opts.hand_mat + 1) end
      if hit('z') then items.set_size(items.opts.size + 1) end
    end
    for _, mk in ipairs(MOVE_KEYS) do if hit(mk[1]) then held[mk[2]] = true end end
    for dgt = 1, 4 do
      if hit(tostring(dgt)) or hit('kp' .. dgt) then set_cam(dgt == 4 and CAM_FREE or dgt - 1) end
    end
    if hit('y') then set_cam(CAM_EGG) end
    if hit('h') then G.hud = not G.hud end
    if hit('p') then lich.set_mode(lich.get_mode() + 1) end
    if hit('j') then lich.set_juice(lich.get_juice() + 1) end
    if hit('g') then lich.set_glow(lich.get_glow() + 1) end
    if hit('r') then lich.set_pattern(lich.get_pattern() + 1) end
    if hit('f') then fire.set_look(fire.get_look() + 1) end
    if hit('k') then powers.beam.set_look(powers.beam.get_look() + 1) end
    if hit('x') then lich.set_recoil(lich.get_recoil() + 1) end
    if hit('o') then powers.set_facing(powers.get_facing() + 1) end
    if hit('l') then powers.lens.set_look(powers.lens.get_look() + 1) end
    if hit('q') then powers.lens.set_follow(powers.lens.get_follow() + 1) end
    if hit('t') and not intro_on() then remove_all() end
    if hit('u') then snakes.set_coil_mode(snakes.coil_mode + 1) end
    if hit('n') then END.hand = (END.hand + 1) % #lich.HANDS end
    for i, pk in ipairs(POWER_KEYS) do if (hit(pk) or hit('kp' .. pk)) and not intro_on() then held = {}; mouse.down = false; ask_remove(i - 1) end end
    if hit('b') then G.dark = (G.dark + 1) % #cave.DARK; cave.set_darkness(G.dark) end
    if hit('v') then G.surface = (G.surface + 1) % #cave.SURF; cave.set_surface(G.surface) end
    if hit('f1') then UI.set_bundle(UI.S.bundle + 1) end
    if hit('f2') then UI.next_icons() end
    if hit('f4') then UI.next_frame() end
    if hit('f5') then lmask.set_look(lmask.look + 1) end
    if hit('f7') then local MK = require('port.orbmarks'); MK.set_style(MK.style + 1) end
    if hit('f8') then END_ZOOM.on = not END_ZOOM.on end
    if hit('f3') then powers.force_plan(powers.get_force() + 1) end
    if hit('f9') and not intro_on() then snakes.send('PACK') end
    if hit('f10') and not intro_on() then snakes.send('SPREAD') end
  end
  -- the inventory: the six objects he carries, top right, each its own little render (inspect.icon)
  local INV = { px = UI.ICON, pad = UI.PAD, gap = UI.GAP, y = 8 }   -- round 42: smaller (was 34 px)
  local icons = {}
  local function slot_rect(i)
    local w = INV.px + INV.pad*2
    local x0 = R.W - 8 - (6*w + 5*INV.gap)
    return x0 + i*(w + INV.gap), INV.y, w, w
  end
  local function slot_at(mx, my)
    for i = 0, 5 do
      local x, y, w, h = slot_rect(i)
      if mx >= x and mx < x + w and my >= y and my < y + h then return i end
    end
  end
  local drag = nil
  local hover_slot = nil
  local function mouse_input()
    local mx, my = mouse_position()
    local moved = mx ~= mouse.px or my ~= mouse.py
    mouse.px, mouse.py = mx, my
    if not (inspect_active() or END.won or SEQ.on) then
      local hs = slot_at(mx, my)
      if hs and not powers.is_on(powers.ALL[hs + 1]) then hs = nil end    -- (only an object he still has lights up)
      if hs and hs ~= hover_slot then AU.play('ui_hover') end
      hover_slot = hs
    else hover_slot = nil end
    if mouse_is_pressed(1) and not (inspect_active() or END.won or SEQ.on or intro_on()) then
      local sl = slot_at(mx, my)
      if sl then
        if powers.is_on(powers.ALL[sl + 1]) then held = {}; mouse.down = false; AU.play('ui_click'); ask_remove(sl); return end
      else mouse.down = true; pick_goal() end
    end
    -- (2026-10-11, his testing key; not on the site) right-click on an object up there: thrown at once, as THROW in
    -- the viewer does, without the viewer
    if not HOSTED and mouse_is_pressed(2) and not (inspect_active() or END.won or SEQ.on or intro_on()) then
      local sl = slot_at(mx, my)
      if sl and powers.is_on(powers.ALL[sl + 1]) then held = {}; mouse.down = false; AU.play('ui_click'); throw_power(sl); return end
    end
    if mouse_is_pressed(2) and not (inspect_active() or END.won or SEQ.on) and (G.cam == CAM_FREE or G.cam == CAM_EGG) then drag = { mx, my } end
    if mouse_is_released(1) then mouse.down = false end
    if mouse_is_released(2) then drag = nil end
    -- the inspect view's own listeners (inspect.js: down on the canvas, up anywhere, move)
    if inspect then
      if mouse_is_pressed(1) then inspect.pointer_down(mx, my) end
      if mouse_is_released(1) then inspect.pointer_up() end
      if moved then inspect.pointer_move(mx, my) end
    end
    -- (main.js turns by CSS pixels: the window shows the game at 2x)
    if moved and drag and (G.cam == CAM_FREE or G.cam == CAM_EGG) then
      local fr = G.cam == CAM_EGG and G.egg_view or G.free
      fr.yaw = fr.yaw - (mx - drag[1])*2*0.3
      fr.pitch = clamp(fr.pitch + (my - drag[2])*2*0.25, -10, 88)
      drag = { mx, my }
    end
    local _, wy = mouse_wheel()
    if wy ~= 0 then
      local deltaY = -wy*100
      if G.cam == CAM_FREE then G.free.dist = clamp(G.free.dist*exp(deltaY*0.001), 1.5, 30) end
      if G.cam == CAM_EGG then G.egg_view.dist = clamp(G.egg_view.dist*exp(deltaY*0.001), 0.8, 12) end
      if inspect then inspect.wheel(deltaY) end
    end
  end
  local function input_update()
    -- the sound tool (2026-10-10, megablock's: port/soundui.lua): TAB lists what is sounding now and every red slot,
    -- ESC (with no viewer up) every slot; the game stands still while it is up; a click outside it plays again.
    -- His tool only: never on the site (but in the desktop's unlock test, EDITOR).
    if not HOSTED or EDITOR then
      local m = SU.mode()
      if m == 'play' then
        if key_is_pressed('tab') then SU.open_list(); return end
        if key_is_pressed('escape') and not inspect_active() then SU.pause(); return end
      else
        if (m == 'pause' or m == 'list') and mouse_is_pressed(1) and not SU.click_consumed() then SU.resume() end
        if m == 'pause' and key_is_pressed('escape') then SU.resume() end
        SU.take_resume()
        return
      end
    end
    -- on the site the walk in starts with the visitor's first click inside the game (the host passes mouse
    -- presses only while the cursor is over it)
    if HOSTED and INTRO.state == 'wait' and mouse_is_pressed(1) then begin() end
    if EGG_WAIT and mouse_is_pressed(1) then EGG_WAIT = false end     -- (the site's egg start: the click begins it)
    keys_input()
    for _, mk in ipairs(MOVE_KEYS) do if key_is_released(mk[1]) then
      -- keyup: this direction is let go (if its other key is not still down it stays off, as main.js)
      held[mk[2]] = nil
    end end
    mouse_input()
  end

  -- ------------------------------------------------------------------ hud
  local gp = Vector3.new()
  local INK = 'rgba(8,6,5,0.85)'
  local function draw_inventory()
    local mx, my = mouse.px, mouse.py
    local hot = slot_at(mx, my)
    if UI.force_hot then hot = UI.force_hot end   -- (captures: a slot shown as hovered)
    for i = 0, 5 do
      local x, y, w, h = slot_rect(i)
      local on = powers.is_on(powers.ALL[i + 1])
      UI.slot(x, y, w, h, not on and 'empty' or (hot == i and 'hot' or 'on'))
      if on then UI.icon(i, x, y, w, h, icons[i], hot == i) end
    end
  end
  local function draw_hud()
    HUD.begin()
    if inspect_active() then inspect.draw_hud(); return end      -- (round 49: not the testing text's)
    local snd_panel = SU.mode() == 'edit' or SU.mode() == 'picker'    -- (the sound editor covers the screen: no icons over it)
    if snd_panel then -- nothing
    elseif not END.won and not SEQ.on then draw_inventory()
    elseif SEQ.on and SEQ.t < 1.2 then HUD.alpha(1 - smoothstep(0, 1.2, SEQ.t)); draw_inventory(); HUD.alpha(1) end   -- (round 56: it fades as he is taken)
    if SEQ.on and SEQ.label_n > 0 then
      -- (round 59: which background, for 2.5 s after a change; counted in drawn frames)
      SEQ.label_n = SEQ.label_n - 1
      HUD.alpha(min(1, SEQ.label_n/30))
      HUD.text('BACKGROUND: ' .. SL.BGS[sil.bg].name .. '   (UP / DOWN)', R.W/2, R.H - 18, '#f2e3c2', 1, 'center', nil, INK)
      HUD.alpha(1)
    end
    if goal then
      gp:copy(goal):project(R.world_camera)
      if gp.z < 1 then
        local x, y = floor((gp.x*0.5 + 0.5)*R.W + 0.5), floor((0.5 - gp.y*0.5)*R.H + 0.5)
        for _, d in ipairs({ { 0, 0 }, { -2, 0 }, { 2, 0 }, { 0, -1 }, { 0, 1 } }) do HUD.rect(x + d[1], y + d[2], 1, 1, 'rgba(242,227,194,0.7)') end
      end
    end
    if not G.hud then return end
    if SU.mode() ~= 'play' and SU.mode() ~= 'pause' then return end     -- (the sound tool's panels need the room)
    -- (the testing text keeps the old font: it is not the game's UI)
    HUD.plain = true
    local c = CAMS[G.cam + 1]
    local W, H = R.W, R.H
    local label = G.cam == CAM_EGG and 'Y' or (G.cam == CAM_FREE and '4' or tostring(G.cam + 1))
    HUD.text(label .. ' ' .. c.name, 8, 8, '#f2e3c2', 1, 'left', nil, INK)
    HUD.text(c.note, 8, 19, '#a8987c', 1, 'left', nil, INK)
    HUD.text('F5 HIS MASK: ' .. require('port.lichmask').LOOKS[lmask.look + 1].name .. '   F7 ORB MARKINGS: ' .. require('port.orbmarks').STYLES[require('port.orbmarks').style + 1]
      .. '   F8 END ZOOM: ' .. (END_ZOOM.on and 'ON' or 'OFF'), 8, 30, '#a8987c', 1, 'left', nil, INK)
    if powers.varied then
      local pl = powers.plan()
      local now = pl and (pl.mode .. (pl.mode == 'ROTATION' and '' or ' (' .. table.concat(pl.set, '+') .. ')')) or '-'
      HUD.text('F3 ATTACKS: ' .. PW.FORCES[powers.get_force() + 1] .. '   NOW: ' .. now .. '   F9 SEND A PACK   F10 SEND A SPREAD', 8, 41, '#f2e3c2', 1, 'left', nil, INK)
    end
    HUD.text('F1 F2 F4 UI: ' .. UI.describe(), 8, H - 202, '#f2e3c2', 1, 'left', nil, INK)
    HUD.text('V CAVE SURFACE: ' .. cave.SURF[G.surface + 1].name, 8, H - 180, '#f2e3c2', 1, 'left', nil, INK)
    HUD.text('U COIL: ' .. CL.COIL_MODES[snakes.coil_mode + 1], 8, H - 169, '#f2e3c2', 1, 'left', nil, INK)
    HUD.text('N HIS HAND: ' .. lich.HANDS[END.hand + 1], 8, H - 158, '#f2e3c2', 1, 'left', nil, INK)
    if items then
      local ITM = require('port.items')
      HUD.text('Z ON THE FLOOR: ' .. ITM.SIZES[items.opts.size + 1].name, 8, H - 147, '#f2e3c2', 1, 'left', nil, INK)
      HUD.text('M HAND: ' .. ITM.HAND_MATS[items.opts.hand_mat + 1], 8, H - 125, '#f2e3c2', 1, 'left', nil, INK)
    end
    HUD.text('Q THE LENS DARTS ABOUT: ' .. LENS.FOLLOWS[powers.lens.get_follow() + 1], 8, H - 136, '#f2e3c2', 1, 'left', nil, INK)
    HUD.text('O BEHIND HIM: ' .. PW.FACINGS[powers.get_facing() + 1], 8, H - 114, '#a8987c', 1, 'left', nil, INK)
    HUD.text('K BEAM COLOUR: ' .. BEAM.BEAM_LOOKS[powers.beam.get_look() + 1], 8, H - 103, '#a8987c', 1, 'left', nil, INK)
    HUD.text('X BEAM RECOIL: ' .. lich.RECOILS[lich.get_recoil() + 1].name, 8, H - 92, '#a8987c', 1, 'left', nil, INK)
    HUD.text('L LENS BEAM: ' .. LENS.LENS_LOOKS[powers.lens.get_look() + 1], 8, H - 81, '#a8987c', 1, 'left', nil, INK)
    HUD.text('F FIRE: ' .. fire.LOOKS[fire.get_look() + 1].name, 8, H - 70, '#a8987c', 1, 'left', nil, INK)
    HUD.text('J FLOATINESS: ' .. lich.JUICE[lich.get_juice() + 1].name, 8, H - 59, '#a8987c', 1, 'left', nil, INK)
    HUD.text('R PRISM PATTERN: ' .. lich.PATTERNS[lich.get_pattern() + 1], 8, H - 48, '#a8987c', 1, 'left', nil, INK)
    HUD.text('G OUT OF THE LIGHT: ' .. lich.GLOWS[lich.get_glow() + 1].name, 8, H - 37, '#a8987c', 1, 'left', nil, INK)
    HUD.text('P PRISM STRENGTH: ' .. lich.MODES[lich.get_mode() + 1], 8, H - 26, '#a8987c', 1, 'left', nil, INK)
    HUD.text('B DARKNESS: ' .. cave.DARK[G.dark + 1].name, 8, H - 15, '#a8987c', 1, 'left', nil, INK)
    -- (the powers he has are the inventory above; under it, the room's numbers)
    local y0 = INV.y + INV.px + INV.pad*2 + 18
    HUD.text(string.format('EACH POWER X%.1f', powers.power()), W - 8, y0, '#a8987c', 1, 'right', nil, INK)
    HUD.text('REACHED THE EGG: ' .. snakes.reached, W - 8, y0 + 11, snakes.reached > 0 and '#e0a070' or '#a8987c', 1, 'right', nil, INK)
    if #snakes.coiled > 0 then
      HUD.text(string.format('COILED ROUND IT: %d   COVERED: %d%% OF %d', #snakes.coiled, floor(snakes.coverage*100 + 0.5), floor(snakes.WIN*100 + 0.5)), W - 8, y0 + 22, '#e0a070', 1, 'right', nil, INK)
    end
    if END.won then HUD.text('THE EGG IS COVERED: WON', W - 8, y0 + 33, '#f2e3c2', 1, 'right', nil, INK) end
    HUD.text('T: REMOVE ALL   RIGHT-CLICK AN OBJECT: THROW IT (TESTING)', W - 8, H - 48, '#8a7c66', 1, 'right', nil, INK)
    HUD.text('CLICK AN OBJECT, OR 5-0: REMOVE IT   I: LOOK AT THEM', W - 8, H - 37, '#f2e3c2', 1, 'right', nil, INK)
    HUD.text('WASD OR HOLD LEFT MOUSE: MOVE', W - 8, H - 26, '#8a7c66', 1, 'right', nil, INK)
    HUD.text('1-4 Y CAMERA   V C U N Z M O K X L Q F J R G P B   H HIDE', W - 8, H - 15, '#8a7c66', 1, 'right', nil, INK)
    HUD.plain = false
  end
  local function ss(a, b, x) local t = clamp((x - a)/(b - a), 0, 1); return t*t*(3 - 2*t) end
  local function draw_over()
    if not END.won then return end
    local k = OVER.fade > 0 and ss(OVER.hold, OVER.hold + OVER.fade, END.over) or (END.over >= OVER.hold and 1 or 0)
    if k > 0 then HUD.rect(0, 0, R.W, R.H, string.format('rgba(0,0,0,%.3f)', k)) end
    local t0 = OVER.hold + OVER.fade + OVER.text_at
    local a = ss(t0, t0 + OVER.text_in, END.over)
    if a <= 0 then return end
    HUD.alpha(a)
    local LH = 18
    local y0 = floor(R.H/2 - (#MESSAGE*LH)/2 + 0.5)
    for i, line in ipairs(MESSAGE) do HUD.text(line, R.W/2, y0 + (i - 1)*LH, '#f2e3c2', 2, 'center') end
    HUD.alpha(1)
  end


  -- each object's icon for the inventory (rendered once, now, outside any frame's draw)
  if inspect then for i = 0, 5 do icons[i] = inspect.icon(i, INV.px) end end
  -- (his mask takes its place on its first tick)

  -- ------------------------------------------------------------------ the ending's sequence (round 56)
  -- round 58/59: he dies: he falls as a rag doll (port/ragdoll.lua) on the cave's floor, toward the egg, the arm that
  -- pointed at it reaching for it; his mask drops; every snake bursts; the egg will rock on its base
  local function die()
    SEQ.dead = SEQ.t; SEQ.k2 = 0
    local hx, hz = EGG.x - L.x, EGG.z - L.z
    local hl = sqrt(hx*hx + hz*hz)
    hx, hz = hx/hl, hz/hl
    local fx, fz = -ROOM_H.x, -ROOM_H.y
    SEQ.rag = RG.create(lich, { ground_y = cave.ground_y, egg = { x = EGG.x, y = EGG.y + 0.38, z = EGG.z, r = 0.36 },
      reach = 2, reach_to = { EGG.x, EGG.y + 0.15, EGG.z },
      push = { -fx*DIE.back - hx*DIE.out, 0, -fz*DIE.back - hz*DIE.out } })
    AU.play('lich_die', { pos = L })
    lmask.drop(cave.ground_y)
    local nb = snakes.burst_all(gore.burst)
    if nb > 0 then AU.play('mass_burst', { pos = { EGG.x, EGG.y + 0.4, EGG.z }, volume = min(1, 0.55 + 0.08*nb) }) end
    ep.start()                -- (round 61: from here the egg is a physics object)
  end
  -- round 59: the real egg cracks: its shell cut along the crack (its program patched, silhouette.lua) and the cap a
  -- real piece of it (the shell's geometry and look, cut the other way). Round 60: first a glowing crack spreads round
  -- it from the side facing the camera (crack_t s), then it opens (open_egg). Round 61: it breaks as physics
  -- (port/eggphys.lua): the bottom, the cap and the band round the crack as shards, each its own body
  local function crack_egg()
    AU.play('egg_crack', { pos = { EGG.x, EGG.y + 0.4, EGG.z } })
    local em = cave.M.egg
    local C = SL.CRACK
    em.custom = em.custom or {}
    em.custom.uClip = { value = 0 }; em.custom.uCrackY = { value = C.y }; em.custom.uCrackA = { value = C.a }; em.custom.uCrackGap = { value = 0 }
    em.custom.uCrackGrow = { value = 0 }; em.custom.uCrackStart = { value = atan2(-ROOM_H.y, -ROOM_H.x)/(2*pi) }
    em.custom.uInner = { value = TM.Vector3.new(4.2, 3.6, 2.8) }
    local cm = MAT.MeshLambertMaterial.new({ name = em.name, map = em.map, side = MAT.DoubleSide, flat_shading = em.flat_shading })
    cm.color:copy(em.color)
    cm.custom = {}
    for k, u in pairs(em.custom) do cm.custom[k] = u end
    cm.custom.uClip = { value = 2 }
    cm.custom.uCrackGrow = { value = 0 }
    cm.custom.uInner = { value = TM.Vector3.new(0.30, 0.20, 0.11) }     -- (the cap's inside: warm, in shade; ~1 and up shows white)
    local shell = cave.egg.user_data.shell
    local cap = T.Mesh.new(shell.geometry, cm)
    cap.visible = false
    SEQ.cap = cap
  end
  local function open_egg()
    AU.play('egg_open', { pos = { EGG.x, EGG.y + 0.4, EGG.z } })
    local em = cave.M.egg
    em.custom.uClip.value = 1
    em.custom.uCrackGap.value = SL.CRACK.gap
    sil.gap = SL.CRACK.gap
    em.side = MAT.DoubleSide
    -- (the cap flies off back, away from the camera, and to the side away from him)
    local sd = -(SEQ.side or 1)
    ep.open({ em = em, cap = SEQ.cap, back = { ROOM_H.x, ROOM_H.y }, side = { -ROOM_H.y*sd, ROOM_H.x*sd } })
  end
  local function seq_tick(dt)
    if not VARIED then return end
    if START_AT == 'ENDING' and not G.started then
      G.started = true
      -- (thrown off to the south-east, where they lie outside every framing of the two-shot)
      for i = 0, 5 do if powers.is_on(powers.ALL[i + 1]) then powers.toggle(i); if items then items.throw(i, 2.0 + (i - 2.5)*0.12) end end end
      snakes.gather(8, 4.0, 6.5, 1.5)
    end
    local egg_start = START_AT == 'EGG' and not G.started
    if egg_start then
      G.started = true
      for i = 0, 5 do if powers.is_on(powers.ALL[i + 1]) then powers.toggle(i); if items then items.throw(i, 2.0 + (i - 2.5)*0.12) end end end
    end
    if not SEQ.on then
      if END.grips == 0 and not egg_start then return end
      SEQ.on = true; SEQ.t = 0
      held = {}; mouse.down = false; goal = nil
      snakes.hold = true          -- (no new waves while it plays: those already coming still come)
      -- his spot: on the light's edge (the shaft's centre at his chest's height), on the side of the egg he is on as
      -- the room camera sees it (round 58: "if he happens to be on the left side of the screen he can stay to the left
      -- instead"), on floor he can stand on
      local S = cave.LAYOUT.sun_dir
      SEQ.c = v(EGG.x + S.x/S.y*SHOT.edge_h, 0, EGG.z + S.z/S.y*SHOT.edge_h)
      local sd = ((L.x - SEQ.c.x)*SIDE_DIR.x + (L.z - SEQ.c.z)*SIDE_DIR.z >= 0) and 1 or -1
      SEQ.side = sd
      -- (round 59b: turned SHOT.back_deg round the edge away from the camera, so that where he falls is behind and
      -- to the side of the egg: in the close-up he lies in its background)
      local ba = SHOT.back_deg*pi/180
      local ox, oz = sd*SIDE_DIR.x*cos(ba) + ROOM_H.x*sin(ba), sd*SIDE_DIR.z*cos(ba) + ROOM_H.y*sin(ba)
      local side = SHOT.edge
      local x, z = SEQ.c.x + ox*side, SEQ.c.z + oz*side
      while side < SHOT.edge + 0.6 and nav.is_blocked(x, z) do side = side + 0.05; x, z = SEQ.c.x + ox*side, SEQ.c.z + oz*side end
      SEQ.spot = v(x, cave.ground_y(x, z), z)
      SEQ.R = side
      SEQ.th1 = atan2(z - SEQ.c.z, x - SEQ.c.x)
      set_framing()
      if egg_start then
        -- (round 60: there already: at his spot facing the egg, the two-shot, the dark whole, dying now)
        mover.place(SEQ.spot.x, SEQ.spot.z, atan2(EGG.x - SEQ.spot.x, EGG.z - SEQ.spot.z))
        F:copy(L)
        SEQ.k = 1; SEQ.sil_t0 = -SIL.dur; sil.e = 1; SEQ.e1 = -DIE.hold
      end
    end
    SEQ.t = SEQ.t + dt
    -- the camera follows the covering (never back, never faster than SHOT.rate of the way a second)
    local want = END.won and 1 or clamp(END.level/0.97, 0, 1)
    SEQ.k = min(1, SEQ.k + clamp(want - SEQ.k, 0, SHOT.rate*dt))
    -- round 57: the silhouettes, from half way down, eased in and out over SIL.dur s (the shot is reached part way)
    if not SEQ.sil_t0 and SEQ.k >= SIL.from then SEQ.sil_t0 = SEQ.t end
    if SEQ.sil_t0 then local u = clamp((SEQ.t - SEQ.sil_t0)/SIL.dur, 0, 1); sil.e = u*u*(3 - 2*u) end
    -- round 58: his death, the snakes' burst, the egg rocking, the camera in on it, the hatch
    if sil.e >= 1 and not SEQ.e1 then SEQ.e1 = SEQ.t end
    if SEQ.e1 and not SEQ.dead and SEQ.t >= SEQ.e1 + DIE.hold then die() end
    if SEQ.dead then
      local d = SEQ.t - SEQ.dead
      -- (dead: no hurt pose, no pointing; the rag doll sets his bones after the pose)
      lich.hurt.w = 0; lich.hurt.level = 0; mover.motion.point = nil
      local H = SL.HATCH
      local open_at = DIE.zoom_at + DIE.hatch_k*DIE.zoom + H.crack_t
      local ht = SEQ.hatch and SEQ.t - SEQ.hatch or nil
      -- round 61: from `wobble_at` the knocks from inside, faster and faster until it opens (port/eggphys.lua)
      if d >= DIE.wobble_at and not SEQ.knocking then SEQ.knocking = true; ep.knocks(open_at - d) end
      if ht then
        sil.hatch_t = ht
        cave.M.egg.custom.uCrackGrow.value = clamp(ht/H.crack_t + 0.05*sin(ht*23), 0, 1)
        if ht >= H.crack_t and not SEQ.opened then
          SEQ.opened = true; open_egg()
          -- (2026-10-14) on our own: the site's unlock sounds on the site's schedule, to tune them here (TAB)
          if not HOSTED then US.start() end
          if HOSTED and site_unlock_posts then
            local left = 0
            for _, a in ipairs(powers.ALL) do if powers.is_on(a) then left = left + 1 end end
            site_unlock_posts('lich-survivors', { ending = 'egg', powers = left })
          end
        end
      end
      ep.tick(dt)
      sil.gore_fade = 1 - smoothstep(DIE.gore_fade[1], DIE.gore_fade[2], d)
      sil.fade = smoothstep(DIE.wobble_at, open_at + DIE.fade_after, d)
      if d >= DIE.zoom_at then SEQ.k2 = min(1, (d - DIE.zoom_at)/DIE.zoom) end
      if not SEQ.hatch and SEQ.k2 >= DIE.hatch_k then SEQ.hatch = SEQ.t; crack_egg() end
    end
  end

  -- ------------------------------------------------------------------ sim + render
  local function tick()
    local lap = PROF.on and perf_time()      -- (2026-10-15: port/prof.lua, for the benchmark)
    if lap then PROF.tick() end
    GCP.tick()                         -- (round 64: the collector, a little every tick)
    lap = PROF.lap('gc', lap, true)
    if EGG_WAIT then return end        -- (the site's egg start, before its click: held)
    if END.won and not SEQ.on then END.over = END.over + DT; if over_black() then return end end
    if inspect_active() then inspect.tick(DT); return end
    -- the model viewer put away with THROW: he throws it (round 48)
    if inspect and inspect.S.result then
      local r, i = inspect.S.result, inspect.S.idx
      inspect.S.result = nil
      if r == 'throw' then throw_power(i) end
    end
    G.tick = G.tick + 1
    G.t = G.t + DT
    if INTRO.state == 'wait' and INTRO.auto then begin() end
    mover.tick(G.t, DT, wanted_velocity())
    if INTRO.state == 'walk' and not INTRO.go and goal == nil and mover.speed() < 0.05 then
      INTRO.state = 'done'; mover.free = false; snakes.hold = false
    end
    lap = PROF.lap('mover', lap, true)
    powers.tick(G.t, DT)
    lap = PROF.lap('powers', lap, true)
    ending_tick(DT)
    seq_tick(DT)
    lap = PROF.lap('ending', lap, true)
    lich.pose(G.t, DT, mover.motion)
    if SEQ.rag then SEQ.rag.step(DT); SEQ.rag.apply() end          -- (round 59: dead, a rag doll)
    powers.after_pose(G.t)
    lich.update(G.t)
    lmask.tick(DT)
    lap = PROF.lap('lich', lap, true)
    cave.update(G.t, DT)
    lap = PROF.lap('cave', lap, true)
    snakes.set_ember(fire.ember_colour())
    snakes.update(G.t, DT)
    lap = PROF.lap('snakes', lap, true)
    fire.update(G.t, DT)
    lap = PROF.lap('fire', lap, true)
    fx.update(G.t, DT)
    lap = PROF.lap('fx', lap, true)
    gore.update(G.t, DT)
    lap = PROF.lap('gore', lap, true)
    warp.update(G.t, DT)
    lap = PROF.lap('warp', lap, true)
    if items then
      items.update(G.t, DT)
      -- a thrown object he walks back to is his again (round 48)
      local back = items.near(L)
      if back and not powers.is_on(powers.ALL[back + 1]) then powers.toggle(back); items.take(back) end
    end
    PROF.lap('items', lap, true)
  end
  -- 2026-10-10, the sounds that follow the room each drawn frame: the snakes crawling (ONE loop, at the crawling snake
  -- nearest the egg, louder the more there are, not one per snake) and the coils squeezing the egg (louder as they
  -- cover it, until he dies)
  local snd = {}
  local function snd_frame()
    local near, nd, n = nil, math.huge, 0
    for _, s in ipairs(snakes.S) do
      if not s.pooled and snakes.free(s) then
        n = n + 1
        local d = (s.x - EGG.x)*(s.x - EGG.x) + (s.z - EGG.z)*(s.z - EGG.z)
        if d < nd then nd, near = d, s end
      end
    end
    if near then
      snd.slither = snd.slither or AU.loop('snake_slither', { pos = { near.x, 0.2, near.z } })
      snd.slither.set_pos({ x = near.x, y = 0.2, z = near.z })
      snd.slither.set_volume(min(1, 0.45 + 0.18*n))
    elseif snd.slither then snd.slither.stop(); snd.slither = nil end
    if #snakes.coiled > 0 and not SEQ.dead then
      snd.squeeze = snd.squeeze or AU.loop('coil_squeeze', { pos = { EGG.x, EGG.y + 0.4, EGG.z } })
      snd.squeeze.set_volume(0.35 + 0.65*(snakes.coverage or 0))
    elseif snd.squeeze then snd.squeeze.stop(); snd.squeeze = nil end
    -- him: floating (louder as he moves), and the strain while he is hurt; both end as he dies
    if INTRO.state ~= 'wait' and not SEQ.dead then
      snd.hover = snd.hover or AU.loop('lich_hover', { pos = L })
      snd.hover.set_pos(L); snd.hover.set_volume(0.5 + 0.5*min(1, mover.speed()/2))
    elseif snd.hover then snd.hover.stop(); snd.hover = nil end
    if END.w > 0 and not SEQ.dead then
      snd.hurt = snd.hurt or AU.loop('lich_hurt_pose', { pos = L })
      snd.hurt.set_pos(L); snd.hurt.set_volume(END.w)
    elseif snd.hurt then snd.hurt.stop(); snd.hurt = nil end
  end

  -- the ear: AT HIS HEAD, turned as the camera (screen left is the left ear). Owner, 2026-10-11: "The 3D sound position
  -- should be on the lich's head instead of static somewhere above the cave". `head` (the cave's EAR row in the sound
  -- editor, sound_rooms.lua) = how far from the camera to his head it sits: 1 = his head (the default), 0 = the camera.
  -- (Round 68 had it half way down the camera's line of sight, a fixed point in the air over the near side.)
  local EAR = { matrix_world = { elements = {} } }
  local EGG_NDC = Vector3.new()     -- (the opened egg's place in the frame, for the site's unlock)
  local PAGE_COL = { SL.SITE_BG[1], SL.SITE_BG[2], SL.SITE_BG[3] }   -- (the site's page colour, read every frame)
  local HEAD_P = Vector3.new()
  local function ear_of(cam)
    local rm = AU.rooms[AU.zone or 'cave']
    local k = rm and rm.head or 1
    local e, o = cam.matrix_world.elements, EAR.matrix_world.elements
    for i = 1, 16 do o[i] = e[i] end
    local hp = lich.head_pos(HEAD_P)
    o[13] = e[13] + (hp.x - e[13])*k
    o[14] = e[14] + (hp.y - e[14])*k
    o[15] = e[15] + (hp.z - e[15])*k
    return EAR
  end

  local function render(dt)
    local lap = PROF.on and perf_time()
    if lap then PROF.frame() end
    US.tick(dt)
    if not (inspect and inspect.render_setup()) then R.params.world_override = nil end
    place_camera(0)
    lap = PROF.lap('camera', lap)
    if SU.mode() == 'play' then
      AU.update(dt, ear_of(R.world_camera))   -- the listener: the ear above (voices' ears, loops, delays, the cave's reverb)
      snd_frame()
    end
    lap = PROF.lap('audio', lap)
    -- (2026-10-13, the site's unlock animation: where the opened egg is in the frame, 0..1 across and down; the
    -- letters of the posts it unlocks leave from there. Every frame while it is open, the camera moving in on it)
    if HOSTED and SEQ.opened and site_unlock_from then
      -- (owner, 2026-10-13: "as the egg bounces left and right when the words are coming out, the source position of
      -- the words needs to move accordingly so they're always coming from the same relative place inside the egg":
      -- the point 0.45 up its axis, turned with the shell as it rocks, not 0.45 above where it stands)
      EGG_NDC:set(0, 0.45, 0):apply_quaternion(cave.egg.quaternion)
      EGG_NDC:set(EGG.x + EGG_NDC.x, EGG.y + EGG_NDC.y, EGG.z + EGG_NDC.z):project(R.world_camera)
      site_unlock_from('lich-survivors', (EGG_NDC.x + 1)/2, (1 - EGG_NDC.y)/2)
    end
    -- (2026-10-13) on the site the ending fades to the page's colour as it is now (its theme), not round 62's #111111
    if HOSTED and site_page_rgb then
      local pr, pg, pb = site_page_rgb()
      PAGE_COL[1], PAGE_COL[2], PAGE_COL[3] = pr/255, pg/255, pb/255
      sil.fade_col = PAGE_COL
    end
    fire.set_camera(R.world_camera, R.H)
    fx.set_camera(R.world_camera, R.H)
    gore.set_camera(R.world_camera, R.H)
    warp.set_camera(R.world_camera, R.H)
    lap = PROF.lap('set_camera', lap)
    draw_hud()
    draw_over()
    -- every sound as its name where it happens (his tool: not on the site). 2026-10-15 (owner: "You can hide UI elements
    -- by default (except top right ones), including the sounds that appear visually"): while playing only with the
    -- testing text (H); always while the sound tool is open (TAB / ESC: the names are what he clicks)
    if (not HOSTED or EDITOR) and (G.hud or SU.mode() ~= 'play') then SU.draw(HUD, R.world_camera) end
    HUD.flush(hud_layer)                -- the HUD into its layer, which the final pass composites
    layer_render(hud_layer)
    lap = PROF.lap('hud', lap)
    R.render(dt)
  end

  if INTRO.state == 'wait' then
    mover.place(INTRO.from.x, INTRO.from.z, atan2(EGG.x - INTRO.from.x, EGG.z - INTRO.from.z))
    mover.free = true
    F:copy(L)
    snakes.hold = true
  end
  G.INTRO = INTRO

  local game = { G = G, tick = tick, place_camera = place_camera, render = render, input_update = input_update, CAMS = CAMS }
  -- round 63: his walk in starts (the site will call it when the play window takes focus)
  game.begin = begin
  function game.frame(dt)
    -- one tick per 1/60 s (main.js: at most 8 a frame)
    if G.manual then return end
    if SU.mode() ~= 'play' then SU.update(dt); return end     -- (the sound tool is up: the game stands still)
    G.acc = (G.acc or 0) + dt
    local n = 0
    while G.acc >= DT and n < 8 do tick(); place_camera(DT); G.acc = G.acc - DT; n = n + 1 end
    if n >= 8 then G.acc = 0 end
  end

  -- ------------------------------------------------------------------ harness API (window.GAME)
  local function r3(x) return floor(x*1000 + 0.5)/1000 end
  GAME = {}
  function GAME.set_manual(on) G.manual = not not on; return G.manual end
  -- input: { keys = 'wd' } holds those keys for the n ticks; { ['goto'] = { x, z } } sends him there
  function GAME.step(n, input)
    n = n or 1; input = input or {}
    if input['goto'] then set_goal(v(input['goto'][1], 0, input['goto'][2])) end
    script_keys = input.keys
    for _ = 1, floor(n) do tick(); place_camera(DT) end
    script_keys = nil
    G.render_dt = n*DT
    return G.tick
  end
  function GAME.cam(i, free) set_cam(i); if free then for k, x in pairs(free) do G.free[k] = x end end; return CAMS[G.cam + 1].name end
  function GAME.hud(on) G.hud = not not on; return G.hud end
  function GAME.egg_cam(yaw, pitch, dist) G.egg_view.yaw, G.egg_view.pitch, G.egg_view.dist = yaw, pitch, dist; set_cam(CAM_EGG); return 'EGG' end
  function GAME.place(x, z, yaw) mover.place(x, z, yaw); F:copy(L); return { x, z } end
  function GAME.juice(i) lich.set_juice(i); return lich.JUICE[lich.get_juice() + 1].name end
  function GAME.powers(list) if list then for i, x in ipairs(list) do powers.set(i - 1, x) end end; return powers.state() end
  function GAME.force(i, x, z) return powers.force(i, x, z) end
  function GAME.remove_all() remove_all(); return #END.queue end
  function GAME.coil_mode(i) snakes.set_coil_mode(i); return CL.COIL_MODES[snakes.coil_mode + 1] end
  function GAME.hand(i) END.hand = i % #lich.HANDS; return lich.HANDS[END.hand + 1] end
  function GAME.hit(a) lich.hit(a); return true end
  function GAME.hurt(level) END.grips = max(1, END.grips); END.force_level = level; return true end
  function GAME.reached() return snakes.reached end
  function GAME.ending()
    local co = {}
    for k, s in ipairs(snakes.coiled) do co[k] = { phase = s.coil.phase, h = r3(s.coil.h), of = r3(s.coil.Qlen) } end
    local crawling = 0
    for _, s in ipairs(snakes.S) do if snakes.free(s) then crawling = crawling + 1 end end
    return { w = r3(END.w), level = r3(END.level), grips = END.grips, won = END.won, won_t = snakes.won_t, over = r3(END.over), black = over_black(),
      coverage = r3(snakes.coverage), reached = snakes.reached, coiled = co, crawling = crawling, snakes = #snakes.S }
  end
  function GAME.drop(i) if powers.is_on(powers.ALL[i + 1]) then toggle_power(i) end; return items and items.state()[i + 1] end
  function GAME.restore(i) if not powers.is_on(powers.ALL[i + 1]) then toggle_power(i) end; return items and items.state()[i + 1] end
  function GAME.items() return items and items.state() end
  -- the model viewer's state (2026-10-09, the site checks): open, which object, the question's mode, its answer
  function GAME.viewer()
    if not inspect then return nil end
    local S = inspect.S
    return { active = inspect_active() and true or false, idx = S.idx, remove = S.remove and true or false,
             accept = S.accept and true or false, result = S.result,
             on = (function() local n = 0; for _, a in ipairs(powers.ALL) do if powers.is_on(a) then n = n + 1 end end; return n end)() }
  end
  GAME['until'] = function(src, maxn)
    maxn = maxn or 3600
    local f = load('local G = ...; return (' .. src .. ')')
    local n = 0
    while n < maxn and not f(G) do tick(); place_camera(DT); n = n + 1 end
    G.render_dt = n*DT
    return n
  end
  function GAME.snakes()
    local out = {}
    for k, s in ipairs(snakes.S) do out[k] = { r3(s.x), r3(s.z), s.dying, r3(s.delay) } end
    return out
  end
  -- round 56: the ending's sequence (on, its progress, the silhouettes' strength, his distance to his spot, the covering)
  function GAME.egg() return ep.state() end
  function GAME.seed() return U.RUN end
  function GAME.begin() begin(); return INTRO.state end
  function GAME.snake_count() local n = 0; for _, s in ipairs(snakes.S) do if not s.pooled and s.dying < 0 then n = n + 1 end end; return n end
  function GAME.intro() return { state = INTRO.state, x = r3(L.x), z = r3(L.z), speed = r3(mover.speed()) } end
  function GAME.seq()
    return { on = SEQ.on, t = r3(SEQ.t), k = r3(SEQ.k), e = r3(sil.e), k2 = r3(SEQ.k2), dead = SEQ.dead ~= nil, hatch = sil.hatch_t and r3(sil.hatch_t) or nil, side = SEQ.side, won = END.won, level = r3(END.level), coverage = r3(snakes.coverage),
      d = SEQ.spot and r3(js_hypot(SEQ.spot.x - L.x, SEQ.spot.z - L.z)) or nil, spot = SEQ.spot and { r3(SEQ.spot.x), r3(SEQ.spot.z) } or nil,
      lich = { r3(L.x), r3(L.z) }, egg = { r3(EGG.x), r3(EGG.z) } }
  end
  function GAME.state()
    return { t = r3(G.t), tick = G.tick, cam = CAMS[G.cam + 1].name, lich = { r3(L.x), r3(L.y), r3(L.z) }, speed = r3(mover.speed()), yaw = r3(mover.yaw()),
      goal = goal and { r3(goal.x), r3(goal.z) } or nil }
  end
  function GAME.dark(i) G.dark = i; return cave.set_darkness(i) end
  function GAME.ui(bundle, icons, frame)
    if bundle then UI.set_bundle(bundle) end
    if icons then UI.S.icons = icons end
    if frame then UI.S.frame = frame end
    UI.apply()
    return UI.describe()
  end
  function GAME.surface(i) G.surface = i % #cave.SURF; return cave.set_surface(i) end
  function GAME.inspect(i) inspect.open(i); return items and require('port.items').ITEMS[inspect.S.idx + 1].name end
  function GAME.inspect_pose(yaw, pitch, roll, zoom) inspect.pose(yaw, pitch, roll or 0, zoom or 1); return true end
  function GAME.inspect_close() inspect.close(); return true end
  function GAME.hand_mat(i) local c = items.set_hand_mat(i); inspect.rebuild(); return c end
  function GAME.floor_size(i) return items.set_size(i) end
  -- round 40's harness: an inspection camera (camera 1 while set; no args clears it); ask to remove
  -- object i, answer the question; where he is in the game
  function GAME.look(eye, tgt, fov) G.look = eye and { eye = eye, tgt = tgt, fov = fov or 50 } or nil; set_cam(0); return true end
  function GAME.ask(i) ask_remove(i); return inspect and inspect.S.active end
  function GAME.answer(yes) inspect.answer(yes); return inspect.S.result end
  function GAME.mode() return G.mode end
  -- round 50: the bouts (force one way: an index into PW.FORCES; nil just reads) and the waves (send one)
  function GAME.plan(i)
    if i then powers.force_plan(i) end
    return { force = PW.FORCES[powers.get_force() + 1], now = powers.plan(), log = powers.plans_log(), gesture = { powers.gesture_phase() }, groups = powers.groups() }
  end
  function GAME.wave(kind) if kind then snakes.send(kind) end; return snakes.waves() end
  -- round 53: the font (a name in port/hud_fonts.lua; nil just reads)
  function GAME.font(name) if name then HUD.set_font(name) end; return HUD.font_name end
  -- round 48: THROW object i (as the viewer's button does, without the viewer)
  function GAME.throw(i) throw_power(i); return items and items.state()[i + 1] end
  GAME.G = G
  return game
end

return GM
