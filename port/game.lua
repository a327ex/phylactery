--[[
  game.lua -- the port to Anchor: web/src/main.js. The lich under the player's hand in the ending's
  cave: WASD / arrows move him relative to the camera, holding the left mouse button sends him to
  the floor under the cursor; the six powers (5-0 remove one, its object drops), the ending (T:
  every power removed; the snakes coil round the egg; the win cuts to black and the message fades
  in). 1-4 / Y cameras, the round keys (U N Z M O K X L F J R G P B), H hides the text.
  Round 40 (owner, 2026-10-02): he comes in down the tunnel (its own camera, which shows where he
  comes from) and the fight starts when he steps into the room; he carries all six objects in an
  inventory (top right); clicking one (or 5-0) brings up the model viewer with its text and the
  question; yes, and it falls to the floor. LICH_ROOM=1 starts in the room exactly as before.
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
local UI = require('port.ui_style')
local Vector2, Vector3 = TM.Vector2, TM.Vector3
local clamp, smoothstep = U.clamp, U.smoothstep
local sqrt, abs, sin, cos, atan2, exp, floor, ceil, min, max, pi = math.sqrt, math.abs, math.sin, math.cos, math.atan, math.exp, math.floor, math.ceil, math.min, math.max, math.pi
local DT = 1/60

local GM = {}

function GM.create(R, hud_layer)
  local cave = CAVE.build(R)
  local lich = LICH.create(R, { GU = cave.GU })
  local EGG = cave.egg.position
  local G = { t = 0, tick = 0, cam = 0, manual = false, hud = true, dark = 1, surface = 2, tlight = 2,
    static = { eye = { -3.6, 9.8, -10.4 }, tgt = { 0.4, 0.1, 2.4 } },
    free = { yaw = 200, pitch = 18, dist = 4.5 }, egg_view = { yaw = 195, pitch = 32, dist = 3.4 } }
  G.R = R; G.cave = cave; G.lich = lich
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
  -- round 40: he comes in down the tunnel, which the room's grid blocks (outside its camera's
  -- frame): a grid of its own for it, handed over to the room's when he steps into that frame
  G.mode = os.getenv('LICH_ROOM') and 'room' or 'tunnel'
  local room_nav = nav
  nav = setmetatable({ cur = room_nav }, { __index = function(t, k) return t.cur[k] end })
  if G.mode == 'tunnel' then
    local tn = NAV.build({ geo = cave.rock_geo, ground_y = cave.ground_y, x0 = -4, x1 = 4, z0 = -48, z1 = -2 })
    tn.block(function(x, z) return abs(x) > 1.9 or z < -45 end)
    tn.finish()
    nav.cur = tn
  end
  local SPAWN = { x = 0, z = -22 }                  -- where he comes from, in the tunnel's dark

  local START = Vector3.new(CAVE.LAYOUT.hover.x, 0, CAVE.LAYOUT.hover.z)
  if G.mode == 'tunnel' then START = Vector3.new(SPAWN.x, 0, SPAWN.z) end
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
  local function toggle_power(i)
    local on = powers.toggle(i)
    if items then
      if on == false then items.drop(i) elseif on == true then items.take(i) end
    end
    return on
  end
  -- round 40: giving one up goes through the model viewer's question (yes: it falls, as before);
  -- one already given up comes back at once (testing only)
  local function ask_remove(i)
    if not inspect then return toggle_power(i) end
    if not powers.is_on(powers.ALL[i + 1]) then return toggle_power(i) end
    inspect.open(i, { remove = true })
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
  -- the second fixed camera (round 40): from the room past the egg, down the tunnel he comes out of
  local TUNNEL_CAM = { eye = { 2.0, 3.0, 5.0 }, tgt = { 0.0, 1.0, -14.0 }, fov = 50 }
  local CAMS = {
    { name = 'ROOM', note = 'THE ROOM CAMERA, FIXED: THE GAME', fov = 50,
      rig = function()
        if G.look then return v(G.look.eye[1], G.look.eye[2], G.look.eye[3]), v(G.look.tgt[1], G.look.tgt[2], G.look.tgt[3]) end
        if G.mode == 'tunnel' then return v(TUNNEL_CAM.eye[1], TUNNEL_CAM.eye[2], TUNNEL_CAM.eye[3]), v(TUNNEL_CAM.tgt[1], TUNNEL_CAM.tgt[2], TUNNEL_CAM.tgt[3]) end
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
    C.fov = (G.cam == 0 and G.look and G.look.fov) or (G.cam == 0 and G.mode == 'tunnel' and TUNNEL_CAM.fov) or c.fov; C:update_projection_matrix()
    C.position:copy(eye)
    C.up:set(0, 1, 0)
    C:look_at(tgt)
    C:update_matrix_world()
  end
  local function set_cam(i) G.cam = clamp(floor(i), 0, #CAMS - 1); F:copy(L) end

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
  local basis = { hold = false, keys = '', x = 0, z = 1 }
  local function wanted_velocity()
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
      -- (from the tunnel's camera to the room's: keys held through the cut keep the direction they
      -- had, as in the Resident Evil remakes, until they change)
      local nk = (keys:find('w', 1, true) and 'w' or '') .. (keys:find('s', 1, true) and 's' or '') .. (keys:find('a', 1, true) and 'a' or '') .. (keys:find('d', 1, true) and 'd' or '')
      if G.mode == 'tunnel' then basis.x, basis.z, basis.keys = cf.x, cf.z, nk
      elseif basis.hold then
        if nk == basis.keys then cf.x, cf.z = basis.x, basis.z else basis.hold = false end
      end
      local rx, rz = -cf.z, cf.x
      local wx, wz = cf.x*iz + rx*ix, cf.z*iz + rz*ix
      local l = js_hypot(wx, wz)
      local sp = MV.MOVE.speed*(1 - 0.6*END.w)
      return { x = wx/l*sp, z = wz/l*sp }
    end
    basis.hold = false
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

  local set_tunnel_light   -- (below, with the tunnel's lamps)
  -- keys, as main.js's keydown (a press or the OS repeat of a held key)
  local function hit(k) return key_is_pressed(k) or key_is_repeated(k) end
  local MOVE_KEYS = { { 'w', 'w' }, { 'up', 'w' }, { 's', 's' }, { 'down', 's' }, { 'a', 'a' }, { 'left', 'a' }, { 'd', 'd' }, { 'right', 'd' } }
  local function keys_input()
    if END.won then return end
    if inspect_active() then
      if inspect.S.remove then
        if hit('y') or hit('return') or hit('enter') or hit('kpenter') then inspect.answer(true) end
        if hit('n') or hit('escape') or hit('backspace') or hit('i') or hit('e') then inspect.answer(false) end
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
    if hit('c') and G.mode == 'tunnel' then set_tunnel_light(G.tlight + 1) end
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
    if mouse_is_pressed(1) and not (inspect_active() or END.won) then
      local sl = slot_at(mx, my)
      if sl then
        if powers.is_on(powers.ALL[sl + 1]) then held = {}; mouse.down = false; ask_remove(sl); return end
      else mouse.down = true; pick_goal() end
    end
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
  local function draw_inventory()
    local mx, my = mouse.px, mouse.py
    local hot = slot_at(mx, my)
    if UI.force_hot then hot = UI.force_hot end   -- (captures: a slot shown as hovered)
    for i = 0, 5 do
      local x, y, w, h = slot_rect(i)
      local on = powers.is_on(powers.ALL[i + 1])
      UI.slot(x, y, w, h, not on and 'empty' or (hot == i and 'hot' or 'on'))
      if on then UI.icon(i, x, y, w, h, icons[i]) end
    end
    if hot and powers.is_on(powers.ALL[hot + 1]) then
      local ITM = require('port.items')
      local _, y, _, h = slot_rect(hot)
      HUD.text(ITM.ITEMS[hot + 1].name, R.W - 8, y + h + 6, '#f2e3c2', 1, 'right', nil, INK)
    end
  end
  local function draw_hud()
    HUD.begin()
    if inspect_active() then if G.hud then inspect.draw_hud() end; return end
    if not END.won then draw_inventory() end
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
    if G.cam == 0 and G.mode == 'tunnel' then
      HUD.text('1 THE TUNNEL', 8, 8, '#f2e3c2', 1, 'left', nil, INK)
      HUD.text('WHERE HE COMES FROM. THE ROOM CAMERA WHEN HE STEPS IN', 8, 19, '#a8987c', 1, 'left', nil, INK)
    else
      HUD.text(label .. ' ' .. c.name, 8, 8, '#f2e3c2', 1, 'left', nil, INK)
      HUD.text(c.note, 8, 19, '#a8987c', 1, 'left', nil, INK)
    end
    if G.mode == 'tunnel' then HUD.text('C TUNNEL LIGHT: ' .. G.TLIGHT[G.tlight + 1].name, 8, H - 191, '#f2e3c2', 1, 'left', nil, INK) end
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


  -- the tunnel's light: what the room throws back down it, borrowed from two of the fire's point
  -- lights (three.js compiled the programs for the room's nine; the fire lights none before the fight)
  local lamps = {}
  -- round 41 (owner: the first view is too bright): AS BUILT lit the room's whole south half from
  -- the tunnel mouth; LOW reaches just past the mouth; DIM keeps the light in the tunnel, round him
  -- as he comes; DARK = none (the
  -- room's own light and his glow)
  local TLIGHT = {
    { name = 'AS BUILT', { 0, 2.6, -13, 5.0, 30 }, { 0, 2.4, -30, 1.4, 14 } },
    { name = 'LOW', { 0, 2.5, -14, 2.2, 15 }, { 0, 2.2, -27, 0.9, 10 } },
    { name = 'DIM', { 0, 2.3, -17, 1.4, 9 }, { 0, 2.2, -27, 0.8, 9 } },
    { name = 'DARK', { 0, 2.3, -17, 0, 1 }, { 0, 2.2, -27, 0, 1 } },
  }
  G.TLIGHT = TLIGHT
  set_tunnel_light = function(i)
    G.tlight = i % #TLIGHT
    for k, lp in ipairs(lamps) do
      local sp, l = TLIGHT[G.tlight + 1][k], lp.l
      l.position:set(sp[1], sp[2], sp[3]); l.color:set_rgb(1.0, 0.8, 0.56); l.intensity = sp[4]; l.distance = sp[5]; l.decay = 0.9
    end
    return TLIGHT[G.tlight + 1].name
  end
  local function enter_room()
    G.mode = 'room'
    nav.cur = room_nav
    for _, lp in ipairs(lamps) do
      local l, k = lp.l, lp.keep
      l.position:copy(k.position); l.color:copy(k.color); l.intensity = k.intensity; l.distance = k.distance; l.decay = k.decay
    end
    lamps = {}
    basis.hold = true
    F:copy(L)
  end
  G.enter_room = enter_room
  if G.mode == 'tunnel' then
    local pl = {}
    R.world_scene:traverse(function(o) if o.is_point_light then pl[#pl + 1] = o end end)
    for k = 1, 2 do
      local l = pl[k]
      lamps[k] = { l = l, keep = { position = l.position:clone(), color = l.color:clone(), intensity = l.intensity, distance = l.distance, decay = l.decay } }
    end
    set_tunnel_light(G.tlight)
    for _, sn in ipairs(snakes.S) do sn.m.visible = false; sn.eyes[1].visible = false; sn.eyes[2].visible = false end
  end
  -- each object's icon for the inventory (rendered once, now, outside any frame's draw)
  if inspect then for i = 0, 5 do icons[i] = inspect.icon(i, INV.px) end end

  -- ------------------------------------------------------------------ sim + render
  local function tick()
    if END.won then END.over = END.over + DT; if over_black() then return end end
    if inspect_active() then inspect.tick(DT); return end
    -- the model viewer put away after its question: yes, and the object falls
    if inspect and inspect.S.result then
      local r, i = inspect.S.result, inspect.S.idx
      inspect.S.result = nil
      if r == 'remove' and powers.is_on(powers.ALL[i + 1]) then toggle_power(i) end
    end
    G.tick = G.tick + 1
    G.t = G.t + DT
    mover.tick(G.t, DT, wanted_velocity())
    if G.mode == 'tunnel' then
      -- coming in: nothing in the room moves yet; the room's camera and the fight begin where its
      -- frame takes him (the room's grid opens about 4.5 m before the egg)
      lich.pose(G.t, DT, mover.motion)
      lich.update(G.t)
      cave.update(G.t, DT)
      fx.update(G.t, DT)
      warp.update(G.t, DT)
      if items then items.update(G.t, DT) end
      if L.z > -9 and not room_nav.is_blocked(L.x, L.z) and room_nav.dist(L.x, L.z) > 0.1 then enter_room() end
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
  function GAME.ui(bundle, icons, frame)
    if bundle then UI.set_bundle(bundle) end
    if icons then UI.S.icons = icons end
    if frame then UI.S.frame = frame end
    UI.apply()
    return UI.describe()
  end
  function GAME.surface(i) G.surface = i % #cave.SURF; return cave.set_surface(i) end
  function GAME.tunnel_light(i) return set_tunnel_light(i) end
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
  GAME.G = G
  return game
end

return GM
