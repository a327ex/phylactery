--[[
  game.lua -- the port to Anchor: web/src/main.js. The lich under the player's hand in the ending's
  cave: WASD / arrows move him relative to the camera, holding the left mouse button sends him to
  the floor under the cursor; the six powers (5-0 remove one, its object drops), the ending (T:
  every power removed; the snakes coil round the egg; the win cuts to black and the message fades
  in). 1-4 / Y cameras, the round keys (U N Z M O K X L F J R G P B), H hides the text.
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
local WALK = require('port.walk')
local Vector2, Vector3 = TM.Vector2, TM.Vector3
local clamp, smoothstep = U.clamp, U.smoothstep
local sqrt, abs, sin, cos, atan2, exp, floor, ceil, min, max, pi = math.sqrt, math.abs, math.sin, math.cos, math.atan, math.exp, math.floor, math.ceil, math.min, math.max, math.pi
local DT = 1/60

local GM = {}

function GM.create(R, hud_layer)
  local cave = CAVE.build(R)
  local lich = LICH.create(R, { GU = cave.GU })
  local EGG = cave.egg.position
  local G = { t = 0, tick = 0, cam = 0, manual = false, hud = true, dark = 1,
    static = { eye = { -3.6, 9.8, -10.4 }, tgt = { 0.4, 0.1, 2.4 } },
    free = { yaw = 200, pitch = 18, dist = 4.5 }, egg_view = { yaw = 195, pitch = 32, dist = 3.4 } }
  G.R = R; G.cave = cave; G.lich = lich

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
  -- the walk (walk.lua) has its own grid: the mover, the camera and the objects ask whichever is
  -- current through this proxy (the room's from the moment he steps into it)
  local room_nav = nav
  nav = setmetatable({ cur = room_nav }, { __index = function(t, k) return t.cur[k] end })

  local START = Vector3.new(CAVE.LAYOUT.hover.x, 0, CAVE.LAYOUT.hover.z)
  local mover = MV.create(nav, lich, START, atan2(EGG.x - START.x, EGG.z - START.z))
  local L = mover.p
  local fire = FIRE.create(R, cave)
  local snakes = SN.create(R, cave, function() return L end, fire)
  G.mover = mover; G.snakes = snakes; G.fire = fire

  local fx = FXM.create(R, cave)
  local gore = GORE.create(R, cave, snakes, fx, U.make_rng(41))
  local warp = WARP.create(R)
  local powers = PW.create({ R = R, cave = cave, snakes = snakes, fx = fx, gore = gore, warp = warp, fire = fire, lich = lich, mover = mover, egg = EGG,
    get_L = function() return L end, rng = U.make_rng(29) })
  G.powers = powers; G.fx = fx; G.gore = gore; G.warp = warp
  gore.follow(function() return L end)
  local POWER_KEYS = { '5', '6', '7', '8', '9', '0' }

  -- the powers' objects (round 28) and the inspect view
  local ITEMS_M = package.searchpath('port.items', package.path) and require('port.items') or nil
  local items, inspect
  if ITEMS_M then
    items = ITEMS_M.create({ R = R, cave = cave, fx = fx, warp = warp, nav = nav, lich = lich, mover = mover, get_L = function() return L end,
      glance = function(p) powers.glance(p) end })
    local INSPECT_M = require('port.inspect')
    inspect = INSPECT_M.create({ R = R, items = items, ITEMS = ITEMS_M.ITEMS })
  end
  G.items = items; G.inspect = inspect
  local function inspect_active() return inspect and inspect.S.active end

  -- ------------------------------------------------------------------ the walk (owner, 2026-10-02)
  -- The game starts in the walk through the cave (walk.lua); stepping into the final room hands
  -- everything back to the room as it was built. LICH_ROOM=1 in the environment starts in the
  -- room exactly as before (the digests against the three.js build: tools/port_digest.*).
  G.mode = os.getenv('LICH_ROOM') and 'room' or 'walk'
  local walk = nil
  if G.mode == 'walk' then
    walk = WALK.create({ R = R, cave = cave, lich = lich, mover = mover, items = items, powers = powers, fx = fx, warp = warp, inspect = inspect })
    G.walk = walk
    -- the tunnel's far end is open now (its cap: the last 18 triangles of the tunnel's mesh)
    for _, m in ipairs(cave.statics) do
      local g = m.geometry
      if g.name == 'cave_2' then g:set_draw_range(0, g.attributes.position.count - 54) end
    end
    for _, sn in ipairs(snakes.S) do sn.m.visible = false; sn.eyes[1].visible = false; sn.eyes[2].visible = false end
  end
  G.walk_speed = 0

  local function toggle_power(i)
    local on = powers.toggle(i)
    if items then
      if on == false then items.drop(i) elseif on == true then items.take(i) end
    end
    return on
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
  local MESSAGE = { '[ YOUR MESSAGE ]' }                -- his to write; one entry per line
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
  local CAMS_FOV = nil
  local CAMS = {
    { name = 'ROOM', note = 'THE ROOM CAMERA, FIXED: THE GAME', fov = 50,
      rig = function()
        if G.look then CAMS_FOV = G.look.fov; return v(G.look.eye[1], G.look.eye[2], G.look.eye[3]), v(G.look.tgt[1], G.look.tgt[2], G.look.tgt[3]) end
        if G.mode == 'walk' then local e, t, fov = walk.rig(); CAMS_FOV = fov; return e, t end
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
    C.fov = (G.cam == 0 and (G.mode == 'walk' or G.look) and CAMS_FOV) or c.fov; C:update_projection_matrix()
    C.position:copy(eye)
    C.up:set(0, 1, 0)
    C:look_at(tgt)
    C:update_matrix_world()
  end
  local function set_cam(i) G.cam = clamp(floor(i), 0, #CAMS - 1); F:copy(L) end
  local enter_room
  local function walk_start(a)
    -- a = the area he starts in (0 = the waking); the objects of the areas before are his
    G.mode = 'walk'
    nav.cur = walk.nav
    walk.reset(a)
    local W = walk.W
    if a == 0 then
      mover.place(W.start.x, W.start.z, W.start.yaw)
    else
      local c = walk.CAMS[walk.zone_at(walk.ENTRY[a] + 1.5)]
      -- the open floor nearest the start of that stretch's camera target
      local x, z = c.tgt[1], c.tgt[3]
      for r = 0, 6, 0.25 do
        local done = false
        for k = 0, 15 do
          local px, pz = x + cos(k/16*pi*2)*r, z + sin(k/16*pi*2)*r
          if walk.nav.dist(px, pz) > 0.5 and abs(walk.nav.s_at(px, pz) - (walk.ENTRY[a] + 1.5)) < 6 then x, z = px, pz; done = true; break end
        end
        if done then break end
      end
      mover.place(x, z, mover.yaw())
    end
    F:copy(L)
  end
  -- he steps into the final room: from here everything is the room's, as it was built (direct:
  -- F9, the room as it was before the walk, at the pool's edge with every power)
  enter_room = function(direct)
    if walk then walk.apply_room(); walk.lamps_on(false) end
    G.mode = 'room'
    nav.cur = room_nav
    if direct then
      for i0 = 0, 5 do powers.set(i0, true); require('port.items').ITEMS[i0 + 1].build = true end
      mover.place(START.x, START.z, atan2(EGG.x - START.x, EGG.z - START.z))
      set_cam(0)
    end
    F:copy(L)
  end
  if G.mode == 'walk' then walk_start(0) end

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
      if y < (G.mode == 'walk' and walk.ground_y or cave.ground_y)(x, z) then t1 = t; break end
      t0 = t
      t = t + 0.08
    end
    if t1 == 0 then return nil end
    for _ = 1, 8 do
      local tm = (t0 + t1)/2
      local x, y, z = o.x + d.x*tm, o.y + d.y*tm, o.z + d.z*tm
      if y < (G.mode == 'walk' and walk.ground_y or cave.ground_y)(x, z) then t1 = tm else t0 = tm end
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
    p.y = (G.mode == 'walk' and walk.ground_y or cave.ground_y)(p.x, p.z)
    best = math.huge; stall = 0
    goal = p
  end
  local function pick_goal() set_goal(floor_at_px(mouse.px, mouse.py)) end

  local cf = Vector3.new()
  local basis = { keys = '', x = 0, z = 1 }
  local function wanted_velocity()
    if END.won then return { x = 0, z = 0 } end
    if G.mode == 'walk' and walk.busy() then goal = nil; return { x = 0, z = 0 } end
    local keys = script_keys
    if keys == nil then keys = ''; for _, k in ipairs({ 'w', 's', 'a', 'd' }) do if held[k] then keys = keys .. k end end end
    local ix, iz = 0, 0
    if keys:find('w', 1, true) then iz = iz + 1 end
    if keys:find('s', 1, true) then iz = iz - 1 end
    if keys:find('d', 1, true) then ix = ix + 1 end
    if keys:find('a', 1, true) then ix = ix - 1 end
    if ix ~= 0 or iz ~= 0 then
      goal = nil
      R.world_camera:get_world_direction(cf); cf.y = 0; cf:normalize()
      if G.mode == 'walk' then
        -- (Resident Evil remakes: while the same keys stay held, they keep the direction they had
        -- when pressed; a cut does not turn him round)
        if keys ~= basis.keys then basis.x, basis.z = cf.x, cf.z end
        cf.x, cf.z = basis.x, basis.z
      end
      basis.keys = keys
      local rx, rz = -cf.z, cf.x
      local wx, wz = cf.x*iz + rx*ix, cf.z*iz + rz*ix
      local l = js_hypot(wx, wz)
      local sp = (G.mode == 'walk' and WALK.SPEEDS[G.walk_speed + 1].v or MV.MOVE.speed)*(1 - 0.6*END.w)
      return { x = wx/l*sp, z = wz/l*sp }
    end
    basis.keys = ''
    if mouse.down then pick_goal() end
    if goal then
      local dx, dz = goal.x - L.x, goal.z - L.z
      local d = js_hypot(dx, dz)
      if mouse.down or d < best - 0.05 then best = d; stall = 0 else stall = stall + DT end
      if (d < 0.12 or stall > 0.5) and not mouse.down then goal = nil; return { x = 0, z = 0 } end
      if d < 0.12 then return { x = 0, z = 0 } end
      local s = min((G.mode == 'walk' and WALK.SPEEDS[G.walk_speed + 1].v or MV.MOVE.speed)*(1 - 0.6*END.w), sqrt(2*MV.MOVE.dec*max(0, d - 0.08))*0.9)
      return { x = dx/d*s, z = dz/d*s }
    end
    return { x = 0, z = 0 }
  end

  -- keys, as main.js's keydown (a press or the OS repeat of a held key)
  local function hit(k) return key_is_pressed(k) or key_is_repeated(k) end
  local MOVE_KEYS = { { 'w', 'w' }, { 'up', 'w' }, { 's', 's' }, { 'down', 's' }, { 'a', 'a' }, { 'left', 'a' }, { 'd', 'd' }, { 'right', 'd' } }
  local function keys_input()
    if END.won then return end
    if inspect_active() then
      if hit('i') or hit('escape') or hit('e') then inspect.close() end
      if hit('a') or hit('left') then inspect.next(-1) end
      if hit('d') or hit('right') then inspect.next(1) end
      if hit('m') then items.set_hand_mat(items.opts.hand_mat + 1); inspect.rebuild() end
      if hit('h') then G.hud = not G.hud end
      return
    end
    if G.mode == 'walk' then
      -- the walk: I shows what he carries; F1-F8 go to an area (with the objects before it), F9 to
      -- the final room as it was before the walk; Q his pace
      if hit('i') and inspect then
        local last = nil
        for i0 = 0, 5 do if walk.collected[i0] then last = i0 end end
        if last then held = {}; mouse.down = false; inspect.open(last) end
        return
      end
      for k = 1, 8 do if hit('f' .. k) then held = {}; goal = nil; walk_start(k - 1); set_cam(0) end end
      if hit('f9') then held = {}; goal = nil; enter_room(true) end
      if hit('q') then G.walk_speed = (G.walk_speed + 1) % #WALK.SPEEDS end
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
    if hit('y') and G.mode ~= 'walk' then set_cam(CAM_EGG) end
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
    if hit('t') and G.mode ~= 'walk' then remove_all() end
    if hit('u') then snakes.set_coil_mode(snakes.coil_mode + 1) end
    if hit('n') then END.hand = (END.hand + 1) % #lich.HANDS end
    if G.mode ~= 'walk' then for i, pk in ipairs(POWER_KEYS) do if hit(pk) or hit('kp' .. pk) then toggle_power(i - 1) end end end
    if hit('b') then G.dark = (G.dark + 1) % #cave.DARK; cave.set_darkness(G.dark); if walk then walk.set_dark(G.dark) end end
  end
  local drag = nil
  local function mouse_input()
    local mx, my = mouse_position()
    local moved = mx ~= mouse.px or my ~= mouse.py
    mouse.px, mouse.py = mx, my
    if mouse_is_pressed(1) and not (inspect_active() or END.won) then mouse.down = true; pick_goal() end
    if mouse_is_pressed(2) and not (inspect_active() or END.won) and (G.cam == CAM_FREE or G.cam == CAM_EGG) then drag = { mx, my } end
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
  local function draw_hud()
    HUD.begin()
    if inspect_active() then if G.hud then inspect.draw_hud() end; return end
    if goal then
      gp:copy(goal):project(R.world_camera)
      if gp.z < 1 then
        local x, y = floor((gp.x*0.5 + 0.5)*R.W + 0.5), floor((0.5 - gp.y*0.5)*R.H + 0.5)
        for _, d in ipairs({ { 0, 0 }, { -2, 0 }, { 2, 0 }, { 0, -1 }, { 0, 1 } }) do HUD.rect(x + d[1], y + d[2], 1, 1, 'rgba(242,227,194,0.7)') end
      end
    end
    if not G.hud then return end
    if G.mode == 'walk' then
      local W = walk.W
      local a = walk.area_now()
      local nm = a == 8 and 'THE TUNNEL' or (W.areas[a + 1] and W.areas[a + 1].name or '')
      if G.cam == 0 then
        HUD.text('1 FIXED CAMERAS: ' .. walk.zone .. ' OF ' .. #walk.CAMS, 8, 8, '#f2e3c2', 1, 'left', nil, INK)
      else
        local label = G.cam == CAM_FREE and '4' or tostring(G.cam + 1)
        HUD.text(label .. ' ' .. CAMS[G.cam + 1].name, 8, 8, '#f2e3c2', 1, 'left', nil, INK)
      end
      HUD.text('THE WALK: ' .. nm, 8, 19, '#a8987c', 1, 'left', nil, INK)
      local ITM = require('port.items')
      for i, it in ipairs(ITM.ITEMS) do
        local has = walk.collected[i - 1]
        HUD.text((has and it.name or '-'), R.W - 8, 8 + (i - 1)*11, has and '#f2e3c2' or '#6a5e4e', 1, 'right', nil, INK)
      end
      HUD.text('Q PACE: ' .. WALK.SPEEDS[G.walk_speed + 1].name, 8, R.H - 26, '#a8987c', 1, 'left', nil, INK)
      HUD.text('B DARKNESS: ' .. cave.DARK[G.dark + 1].name, 8, R.H - 15, '#a8987c', 1, 'left', nil, INK)
      HUD.text('I: WHAT HE CARRIES   F1-F8: GO TO AN AREA   F9: THE ROOM', R.W - 8, R.H - 37, '#f2e3c2', 1, 'right', nil, INK)
      HUD.text('WASD OR HOLD LEFT MOUSE: MOVE', R.W - 8, R.H - 26, '#8a7c66', 1, 'right', nil, INK)
      HUD.text('1-4 CAMERA   H HIDE', R.W - 8, R.H - 15, '#8a7c66', 1, 'right', nil, INK)
      return
    end
    local c = CAMS[G.cam + 1]
    local W, H = R.W, R.H
    local label = G.cam == CAM_EGG and 'Y' or (G.cam == CAM_FREE and '4' or tostring(G.cam + 1))
    HUD.text(label .. ' ' .. c.name, 8, 8, '#f2e3c2', 1, 'left', nil, INK)
    HUD.text(c.note, 8, 19, '#a8987c', 1, 'left', nil, INK)
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
    for i, a in ipairs(powers.ALL) do
      local on = powers.is_on(a)
      HUD.text(POWER_KEYS[i] .. ' ' .. a.name .. (on and '' or ': REMOVED'), W - 8, 8 + (i - 1)*11, on and '#f2e3c2' or '#6a5e4e', 1, 'right', nil, INK)
    end
    HUD.text(string.format('EACH POWER X%.1f', powers.power()), W - 8, 8 + 6*11 + 3, '#a8987c', 1, 'right', nil, INK)
    HUD.text('REACHED THE EGG: ' .. snakes.reached, W - 8, 8 + 7*11 + 3, snakes.reached > 0 and '#e0a070' or '#a8987c', 1, 'right', nil, INK)
    if #snakes.coiled > 0 then
      HUD.text(string.format('COILED ROUND IT: %d   COVERED: %d%% OF %d', #snakes.coiled, floor(snakes.coverage*100 + 0.5), floor(snakes.WIN*100 + 0.5)), W - 8, 8 + 8*11 + 3, '#e0a070', 1, 'right', nil, INK)
    end
    if END.won then HUD.text('THE EGG IS COVERED: WON', W - 8, 8 + 9*11 + 3, '#f2e3c2', 1, 'right', nil, INK) end
    HUD.text('T: REMOVE EVERY POWER (THE ENDING)', W - 8, H - 48, '#f2e3c2', 1, 'right', nil, INK)
    HUD.text('I: INSPECT THE OBJECTS   5-0: REMOVE A POWER (ITS OBJECT DROPS)', W - 8, H - 37, '#f2e3c2', 1, 'right', nil, INK)
    HUD.text('WASD OR HOLD LEFT MOUSE: MOVE', W - 8, H - 26, '#8a7c66', 1, 'right', nil, INK)
    HUD.text('1-4 Y CAMERA   U N Z M O K X L F J R G P B   H HIDE', W - 8, H - 15, '#8a7c66', 1, 'right', nil, INK)
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

  -- ------------------------------------------------------------------ sim + render
  local was_inspect = false
  local function tick()
    if END.won then END.over = END.over + DT; if over_black() then return end end
    if inspect_active() then inspect.tick(DT); was_inspect = true; return end
    if was_inspect then was_inspect = false; if walk then walk.after_inspect() end end
    G.tick = G.tick + 1
    G.t = G.t + DT
    mover.tick(G.t, DT, wanted_velocity())
    if G.mode == 'walk' then
      walk.tick(G.t, DT)
      lich.pose(G.t, DT, mover.motion)
      lich.update(G.t)
      cave.update(G.t, DT)
      fx.update(G.t, DT)
      warp.update(G.t, DT)
      -- into the final room: past the tunnel, where the room's camera sees him
      if walk.area_now() == 8 and L.z > -16 and not room_nav.is_blocked(L.x, L.z) and room_nav.dist(L.x, L.z) > 0.1 then enter_room(false) end
      return
    end
    powers.tick(G.t, DT)
    ending_tick(DT)
    lich.pose(G.t, DT, mover.motion)
    powers.after_pose(G.t)
    lich.update(G.t)
    cave.update(G.t, DT)
    snakes.set_ember(fire.ember_colour())
    snakes.update(G.t, DT)
    fire.update(G.t, DT)
    fx.update(G.t, DT)
    gore.update(G.t, DT)
    warp.update(G.t, DT)
    if items then items.update(G.t, DT) end
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
  function GAME.state()
    return { t = r3(G.t), tick = G.tick, cam = CAMS[G.cam + 1].name, lich = { r3(L.x), r3(L.y), r3(L.z) }, speed = r3(mover.speed()), yaw = r3(mover.yaw()),
      goal = goal and { r3(goal.x), r3(goal.z) } or nil }
  end
  function GAME.dark(i) G.dark = i; return cave.set_darkness(i) end
  function GAME.inspect(i) inspect.open(i); return items and require('port.items').ITEMS[inspect.S.idx + 1].name end
  function GAME.inspect_pose(yaw, pitch, roll, zoom) inspect.pose(yaw, pitch, roll or 0, zoom or 1); return true end
  function GAME.inspect_close() inspect.close(); return true end
  function GAME.hand_mat(i) local c = items.set_hand_mat(i); inspect.rebuild(); return c end
  function GAME.floor_size(i) return items.set_size(i) end
  -- the walk's harness: put him in stretch k (its camera's target, the open floor nearest it),
  -- facing along the way; go to an area as F1-F8 do; the walk's state
  function GAME.walk_zone(k, yaw)
    if not walk then return nil end
    local c = walk.CAMS[k]
    if c.area == 8 then mover.place(0, c.s0 > walk.CAMS[k - 1].s1 - 1 and -40 or -25, 0); G.walk_hold = true; GAME.step(2); return c end
    local x, z = c.tgt[1], c.tgt[3]
    for r = 0, 8, 0.2 do
      local done = false
      for q = 0, 23 do
        local px, pz = x + cos(q/24*pi*2)*r, z + sin(q/24*pi*2)*r
        local s = walk.nav.s_at(px, pz)
        if walk.nav.dist(px, pz) > 0.45 and s >= c.s0 and s < c.s1 then x, z = px, pz; done = true; break end
      end
      if done then break end
    end
    local n = walk.CAMS[k + 1] or c
    mover.place(x, z, yaw or atan2(n.tgt[1] - c.tgt[1], n.tgt[3] - c.tgt[3]))
    set_cam(0)
    GAME.step(2)
    return { x = x, z = z, zone = walk.zone, area = walk.area_now() }
  end
  -- an inspection camera (camera 1 while set): eye, target, fov; GAME.look() clears it
  function GAME.look(eye, tgt, fov) G.look = eye and { eye = eye, tgt = tgt, fov = fov or 50 } or nil; set_cam(0); return true end
  function GAME.place(x, z, yaw) mover.place(x, z, yaw); F:copy(L); return { x, z } end
  function GAME.walk_area(a) walk_start(a); set_cam(0); GAME.step(2); return { zone = walk.zone, area = walk.area_now() } end
  function GAME.walk() return walk and { mode = G.mode, zone = walk.zone, area = walk.area_now(), collected = walk.collected, s = walk.nav.s_at(L.x, L.z) } or { mode = G.mode } end
  GAME.G = G
  return game
end

return GM
