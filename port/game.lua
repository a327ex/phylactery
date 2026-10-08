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
local ES = require('port.eggshards')
local MAT = require('port.three.materials')
local UI = require('port.ui_style')
local Vector2, Vector3 = TM.Vector2, TM.Vector3
local clamp, smoothstep = U.clamp, U.smoothstep
local sqrt, abs, sin, cos, atan2, exp, floor, ceil, min, max, pi = math.sqrt, math.abs, math.sin, math.cos, math.atan, math.exp, math.floor, math.ceil, math.min, math.max, math.pi
local DT = 1/60

local GM = {}

function GM.create(R, hud_layer)
  local cave = CAVE.build(R)
  local lich = LICH.create(R, { GU = cave.GU })
  -- round 45: the lich's own mask, flat white (port/lichmask.lua; F5 cycles it for comparison)
  local lmask = require('port.lichmask').create(lich, cave.GU, R)
  local EGG = cave.egg.position
  local G = { t = 0, tick = 0, cam = 0, manual = false, hud = true, dark = 1, surface = 2,
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
  -- (round 50 fix: the snakes' own grid of the rocks: no frame, no egg, only rock too tall to crawl over)
  local snake_nav = VARIED and NAV.build({ geo = cave.rock_geo, ground_y = cave.ground_y, block_h = 0.2 }).finish() or nil
  local snakes = SN.create(R, cave, function() return L end, fire, nil, nil, { varied = VARIED, nav = snake_nav })
  G.mover = mover; G.snakes = snakes; G.fire = fire

  local fx = FXM.create(R, cave)
  local gore = GORE.create(R, cave, snakes, fx, U.make_rng(41))
  local warp = WARP.create(R)
  local powers = PW.create({ R = R, cave = cave, snakes = snakes, fx = fx, gore = gore, warp = warp, fire = fire, lich = lich, mover = mover, egg = EGG,
    get_L = function() return L end, rng = U.make_rng(29), varied = VARIED })
  G.powers = powers; G.fx = fx; G.gore = gore; G.warp = warp
  -- round 57: the ending's silhouettes (the egg with the snakes coiled on it; the lich with his mask)
  local sil = SL.create(R)
  R.sil = sil
  R.sil_subjects = function()
    local egg = { cave.egg }
    for _, s in ipairs(snakes.coiled) do egg[#egg + 1] = s.m; egg[#egg + 1] = s.eyes[1]; egg[#egg + 1] = s.eyes[2] end
    -- (round 58: the snakes' burst, pale, then fading, from his death on: before it any gore is the dark's)
    if G.shards then for _, m in ipairs(G.shards.meshes) do egg[#egg + 1] = m end end
    return { egg = egg, lich = { lich.root, lmask.mesh }, shell = cave.egg.user_data.shell, gore = (G.SEQ and G.SEQ.dead) and gore.meshes() or nil }
  end
  G.sil = sil
  -- round 60: bits of shell for the hatch (port/eggshards.lua)
  local shards = ES.create({ R = R, ground_y = cave.ground_y, sun = { cave.LAYOUT.sun_dir.x, cave.LAYOUT.sun_dir.y, cave.LAYOUT.sun_dir.z } })
  G.shards = shards
  gore.follow(function() return L end)
  local POWER_KEYS = { '5', '6', '7', '8', '9', '0' }

  -- the powers' objects (round 28) and the inspect view
  local ITEMS_M = package.searchpath('port.items', package.path) and require('port.items') or nil
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
    if items then items.throw(i, mover.yaw()) end
  end

  -- ------------------------------------------------------------------ the ending (round 36)
  local END = { w = 0, level = 0, grips = 0, spasm = 2, won = false, over = -1, queue = {}, queue_t = 0, hand = 0 }
  G.END = END
  local held = {}
  local mouse = { down = false, px = 0, py = 0 }
  local goal, best, stall, script_keys = nil, math.huge, 0, nil
  snakes.on_grip = function() END.grips = END.grips + 1; lich.hit(0.5 + 0.1*min(END.grips, 6) + (END.grips == 1 and 0.5 or 0)) end
  snakes.on_won = function() END.won = true; END.over = 0; held = {}; mouse.down = false; goal = nil; lich.hit(1.7) end
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
  -- away from the egg) and every snake bursts; from `wobble_at` s the egg rocks in bursts (a pokeball's: three rocks, a
  -- rest, a little harder each time); from `zoom_at` s the camera goes in on it over `zoom` s (eased), to `close` m
  -- from a point `close_y` m up it; at `hatch_k` of the way it hatches (silhouette.lua); the burst's pieces fade into
  -- the dark between `gore_fade` s after it
  local DIE = { hold = 4.0, back = 0.5, out = 0.0, wobble_at = 1.3, zoom_at = 2.2, zoom = 7.0, hatch_k = 0.86, close = 2.1, close_y = 0.42, gore_fade = { 1.0, 2.6 } }
  SEQ.label_n = 0
  G.SHOT = SHOT
  -- round 56: where the game starts. 'ENDING' (owner, 2026-10-07: "Start the game for me with snakes near the
  -- egg"): every power already given up (their objects thrown out of the two-shot) and the pool sent in from 4-6.5 m
  -- out, 1.5 s apart, so the shell is being covered within seconds. 'EGG' (round 60, owner: "Let's focus on the egg
  -- now. Start the scene from there"): the sequence already at the two-shot, dim, and he dies on the first tick, so the
  -- egg's part follows at once (no snakes, no coil). 'GAME': the game as it starts for players.
  local START_AT = os.getenv('LICH_START') or 'EGG'        -- (LICH_START=GAME in the environment: the players' start)
  local function over_black() return END.won and END.over >= OVER.hold + OVER.fade end
  local end_rng = U.make_rng(77)
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
    END.spasm = END.spasm - dt
    if END.spasm <= 0 then lich.hit(END.w*(0.18 + 0.4*END.level)); END.spasm = end_rng.float(1.1, 3.2)*(1 - 0.4*END.level) end
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
    if mouse.down then pick_goal() end
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
    if hit('i') and inspect then held = {}; mouse.down = false; inspect.open(); return end
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
    if hit('t') then remove_all() end
    if hit('u') then snakes.set_coil_mode(snakes.coil_mode + 1) end
    if hit('n') then END.hand = (END.hand + 1) % #lich.HANDS end
    for i, pk in ipairs(POWER_KEYS) do if hit(pk) or hit('kp' .. pk) then held = {}; mouse.down = false; ask_remove(i - 1) end end
    if hit('b') then G.dark = (G.dark + 1) % #cave.DARK; cave.set_darkness(G.dark) end
    if hit('v') then G.surface = (G.surface + 1) % #cave.SURF; cave.set_surface(G.surface) end
    if hit('f1') then UI.set_bundle(UI.S.bundle + 1) end
    if hit('f2') then UI.next_icons() end
    if hit('f4') then UI.next_frame() end
    if hit('f5') then lmask.set_look(lmask.look + 1) end
    if hit('f7') then local MK = require('port.orbmarks'); MK.set_style(MK.style + 1) end
    if hit('f8') then END_ZOOM.on = not END_ZOOM.on end
    if hit('f3') then powers.force_plan(powers.get_force() + 1) end
    if hit('f9') then snakes.send('PACK') end
    if hit('f10') then snakes.send('SPREAD') end
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
  local function mouse_input()
    local mx, my = mouse_position()
    local moved = mx ~= mouse.px or my ~= mouse.py
    mouse.px, mouse.py = mx, my
    if mouse_is_pressed(1) and not (inspect_active() or END.won or SEQ.on) then
      local sl = slot_at(mx, my)
      if sl then
        if powers.is_on(powers.ALL[sl + 1]) then held = {}; mouse.down = false; ask_remove(sl); return end
      else mouse.down = true; pick_goal() end
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
    if not END.won and not SEQ.on then draw_inventory()
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
    HUD.text('T: REMOVE EVERY POWER AT ONCE (TESTING)', W - 8, H - 48, '#8a7c66', 1, 'right', nil, INK)
    HUD.text('CLICK AN OBJECT, OR 5-0: REMOVE IT   I: LOOK AT THEM', W - 8, H - 37, '#f2e3c2', 1, 'right', nil, INK)
    HUD.text('WASD OR HOLD LEFT MOUSE: MOVE', W - 8, H - 26, '#8a7c66', 1, 'right', nil, INK)
    HUD.text('1-4 Y CAMERA   V C U N Z M O K X L F J R G P B   H HIDE', W - 8, H - 15, '#8a7c66', 1, 'right', nil, INK)
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
  -- round 58: the egg's rocking (a pokeball's); round 60 (owner: "It should increasingly shake more as it gets closer
  -- to hatching"): at strength I (0..1, toward the opening) the rocks come faster (1.3 -> 4.1 Hz), wider (0.06 -> 0.2 rad)
  -- and in longer bursts (the rests between shrink to none), a second rock across, a tremor growing as I^2, small hops
  -- past 0.65. Returns the two rocks (rad) and the hop (m).
  local function shake(t, I, dt)
    local K = SEQ.shk
    K.ph = K.ph + dt*2*pi*(1.3 + 2.8*I)
    local w = 0.5*sin(t*1.9) + 0.3*sin(t*3.1 + 1.7) + 0.2*sin(t*5.3 + 0.4)
    local gate = smoothstep(0.35 - 0.9*I, 0.55 - 0.9*I, w)
    K.g = K.g + (gate - K.g)*min(1, dt*10)
    local a = (0.06 + 0.14*I)*K.g
    local j = (0.004 + 0.035*I*I)*(0.6*sin(t*47.3) + 0.4*sin(t*61.7 + 1.3))
    local hop = I > 0.65 and max(0, sin(t*8.7))*0.014*(I - 0.65)/0.35*K.g or 0
    return a*sin(K.ph) + j, 0.45*a*sin(K.ph*1.37 + 0.6) + 0.7*j, hop
  end
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
    lmask.drop(cave.ground_y)
    snakes.burst_all(gore.burst)
    cave.egg.user_data.wobble_axis = { ROOM_H.x, ROOM_H.y }
    cave.egg.user_data.wobble = 0
  end
  -- round 59: the real egg cracks: its shell cut along the crack (its program patched, silhouette.lua) and the cap a
  -- real piece of it (the shell's geometry and look, cut the other way), a child of the egg. Round 60: first a glowing
  -- crack spreads round it from the side facing the camera (crack_t s), then it opens (open_egg), bits of shell flying
  local CAPM = TM.Matrix4.new()
  local function crack_egg()
    local em = cave.M.egg
    local C = SL.CRACK
    em.custom = em.custom or {}
    em.custom.uClip = { value = 0 }; em.custom.uCrackY = { value = C.y }; em.custom.uCrackA = { value = C.a }
    em.custom.uCrackGrow = { value = 0 }; em.custom.uCrackStart = { value = atan2(-ROOM_H.y, -ROOM_H.x)/(2*pi) }
    em.custom.uInner = { value = TM.Vector3.new(4.2, 3.6, 2.8) }
    sil.back = { ROOM_H.x, ROOM_H.y }
    sil.fly_side = -(SEQ.side or 1)                 -- (the cap flies off on the side away from him)
    local cm = MAT.MeshLambertMaterial.new({ name = em.name, map = em.map, side = MAT.DoubleSide, flat_shading = em.flat_shading })
    cm.color:copy(em.color)
    cm.custom = {}
    for k, u in pairs(em.custom) do cm.custom[k] = u end
    cm.custom.uClip = { value = 2 }
    cm.custom.uCrackGrow = { value = 0 }
    cm.custom.uInner = { value = TM.Vector3.new(0.30, 0.20, 0.11) }     -- (the cap's inside: warm, in shade; ~1 and up shows white)
    local shell = cave.egg.user_data.shell
    local cap = T.Mesh.new(shell.geometry, cm)
    cap.receive_shadow = true
    cap.visible = false
    cave.egg:add(cap)
    SEQ.cap = cap
  end
  local function open_egg()
    local em = cave.M.egg
    em.custom.uClip.value = 1
    em.side = MAT.DoubleSide
    SEQ.cap.visible = true
    local C = SL.CRACK
    shards.spawn(cave.egg.user_data.shell, function(th) return C.rim*cos(th), SL.crack_y(th), C.rim*sin(th) end, { ROOM_H.x, ROOM_H.y })
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
      SEQ.shk = { ph = 0, g = 0 }
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
      local ud = cave.egg.user_data
      local H = SL.HATCH
      local open_at = DIE.zoom_at + DIE.hatch_k*DIE.zoom + H.crack_t
      local ht = SEQ.hatch and SEQ.t - SEQ.hatch or nil
      if ht and ht >= H.crack_t then
        -- (open: the shaking dies away)
        ud.wobble = (ud.wobble or 0)*exp(-dt*8); ud.wobble2 = (ud.wobble2 or 0)*exp(-dt*8); ud.hop = (ud.hop or 0)*exp(-dt*8)
      elseif d >= DIE.wobble_at then
        local I = clamp((d - DIE.wobble_at)/(open_at - DIE.wobble_at), 0, 1)^1.4
        local a1, a2, hop = shake(d, I, dt)
        local x = ht and 1.25 or 1                      -- (hardest while the crack spreads)
        ud.wobble, ud.wobble2, ud.hop = a1*x, a2*x, hop*x
      end
      if ht then
        sil.hatch_t = ht
        cave.M.egg.custom.uCrackGrow.value = clamp(ht/H.crack_t + 0.05*sin(ht*23), 0, 1)
        if ht >= H.crack_t and not SEQ.opened then SEQ.opened = true; open_egg() end
        shards.update(dt)
      end
      sil.gore_fade = 1 - smoothstep(DIE.gore_fade[1], DIE.gore_fade[2], d)
      if d >= DIE.zoom_at then SEQ.k2 = min(1, (d - DIE.zoom_at)/DIE.zoom) end
      if not SEQ.hatch and SEQ.k2 >= DIE.hatch_k then SEQ.hatch = SEQ.t; crack_egg() end
      if SEQ.cap then
        -- (round 59: the real cap where the mask's is: the shell's place in the egg, times the cap's in the shell)
        local shell = cave.egg.user_data.shell
        shell:update_matrix()
        CAPM:multiply_matrices(shell.matrix, sil.cap_matrix(SEQ.t - SEQ.hatch))
        CAPM:decompose(SEQ.cap.position, SEQ.cap.quaternion, SEQ.cap.scale)
      end
    end
  end

  -- ------------------------------------------------------------------ sim + render
  local function tick()
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
    mover.tick(G.t, DT, wanted_velocity())
    powers.tick(G.t, DT)
    ending_tick(DT)
    seq_tick(DT)
    lich.pose(G.t, DT, mover.motion)
    if SEQ.rag then SEQ.rag.step(DT); SEQ.rag.apply() end          -- (round 59: dead, a rag doll)
    powers.after_pose(G.t)
    lich.update(G.t)
    lmask.tick(DT)
    cave.update(G.t, DT)
    snakes.set_ember(fire.ember_colour())
    snakes.update(G.t, DT)
    fire.update(G.t, DT)
    fx.update(G.t, DT)
    gore.update(G.t, DT)
    warp.update(G.t, DT)
    if items then
      items.update(G.t, DT)
      -- a thrown object he walks back to is his again (round 48)
      local back = items.near(L)
      if back and not powers.is_on(powers.ALL[back + 1]) then powers.toggle(back); items.take(back) end
    end
  end
  local function render(dt)
    if not (inspect and inspect.render_setup()) then R.params.world_override = nil end
    place_camera(0)
    fire.set_camera(R.world_camera, R.H)
    fx.set_camera(R.world_camera, R.H)
    gore.set_camera(R.world_camera, R.H)
    warp.set_camera(R.world_camera, R.H)
    draw_hud()
    draw_over()
    HUD.flush(hud_layer)                -- the HUD into its layer, which the final pass composites
    layer_render(hud_layer)
    R.render(dt)
  end

  local game = { G = G, tick = tick, place_camera = place_camera, render = render, input_update = input_update, CAMS = CAMS }
  function game.frame(dt)
    -- one tick per 1/60 s (main.js: at most 8 a frame)
    if G.manual then return end
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
