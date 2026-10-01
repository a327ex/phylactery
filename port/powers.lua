--[[
  powers.lua -- the port to Anchor: web/src/powers.js. The lich's six powers and what decides when
  they act: a snake becomes a target within ENGAGE of the egg; he casts one gestured power at a
  time (head to the spot, arm up, a beat, it goes off, hold, lower), the least used first (the
  rotation), each power growing as others are removed (power = 6 / powers left); something within
  URGENT of the egg forces a cast now. Fire, lift and beam are gestured; the lens and the rock are
  his mind alone; leakage happens by itself.
  JS's stable sorts are kept (ties broken by the original order).
]]
local TM = require('port.three.math')
local U = require('port.util')
local LIFT = require('port.lift')
local ROCK = require('port.rock')
local BEAM = require('port.beam')
local LENS = require('port.lens')
local LEAK = require('port.leak')
local Vector3 = TM.Vector3
local sqrt, abs, sin, cos, atan2, floor, ceil, min, max, huge, pi = math.sqrt, math.abs, math.sin, math.cos, math.atan, math.floor, math.ceil, math.min, math.max, math.huge, math.pi

local PW = {}
PW.ENGAGE, PW.URGENT, PW.LENS_ENGAGE = 3.4, 2.6, 6.0
local ENGAGE, URGENT, LENS_ENGAGE = PW.ENGAGE, PW.URGENT, PW.LENS_ENGAGE
local ON_T, HOLD, LOWER = 0.08, 0.45, 0.3
local ARRIVE, BEAT, AIM_MAX, QUICK_ARRIVE, QUICK_BEAT, QUICK_MAX = 0.7, 0.15, 1.2, 1.6, 0.08, 0.45
local SOON = 1.5
local HOLD_CHAIN = 0.2
PW.FACINGS = { 'TURNS TO KEEP IT IN FRONT', 'LETS GO OF IT' }
local FRONT = pi/2
local ARM_UP, FIRE_IN = 1.66, 1.4
local function jround(x) return floor(x + 0.5) end
local hyp = js_hypot
local function stable_sort(list, key)
  local dec = {}
  for i, v in ipairs(list) do dec[i] = { v = v, k = key(v), i = i } end
  table.sort(dec, function(a, b) if a.k ~= b.k then return a.k < b.k end; return a.i < b.i end)
  local out = {}
  for i, d in ipairs(dec) do out[i] = d.v end
  return out
end
local function includes(list, x) for _, v in ipairs(list) do if v == x then return true end end; return false end

function PW.create(ctx)
  local snakes, fire, lich, mover, egg, get_L, rng = ctx.snakes, ctx.fire, ctx.lich, ctx.mover, ctx.egg, ctx.get_L, ctx.rng
  local N = snakes.RINGS
  local later = {}
  local clock, power = 0, 1
  local FIRE = { name = 'FIRE', gesture = true, cooldown = 5.0, beat = 0.05 }
  function FIRE.capacity(p) return ceil(p/2) end
  function FIRE.aim_ring() return jround(N*rng.float(0.15, 0.75)) end
  function FIRE.cast(targets, from, ring)
    for k, s in ipairs(targets) do
      if k == 1 then snakes.ignite(s, ring) else later[#later + 1] = { at = clock + (k - 1)*0.12, s = s } end
    end
  end
  function FIRE.update() end
  local lift = LIFT.create(ctx)
  local rock = ROCK.create(ctx)
  local beam = BEAM.create(ctx)
  local lens = LENS.create(ctx)
  local leak = LEAK.create(ctx)
  local ALL = { FIRE, lift, rock, leak, beam, lens }
  local on, nxt, last, uses, took, fair = {}, {}, {}, {}, {}, {}
  for i, a in ipairs(ALL) do on[a] = true; nxt[a] = 1.0; last[a] = -10 + (i - 1); uses[a] = 0; took[a] = 0; fair[a] = 0 end
  local function count(a, n) uses[a] = uses[a] + 1; took[a] = took[a] + n; fair[a] = fair[a] + 1 end
  local function reset_fair() for _, a in ipairs(ALL) do fair[a] = 0 end end
  local quick_lens = 0
  local function d_egg(s) return hyp(s.x - egg.x, s.z - egg.z) end
  local function unclaimed(s) return snakes.free(s) and not (s.claim and s.claim_until > clock) end
  local function claim(s, who, secs) s.claim = who; s.claim_until = clock + secs end
  local function threats(Rr)
    local out = {}
    for _, s in ipairs(snakes.S) do if unclaimed(s) and d_egg(s) < Rr then out[#out + 1] = s end end
    return stable_sort(out, d_egg)
  end
  lens.use_claims(function(s) return unclaimed(s) end, function(s) claim(s, 'LENS', 2.0) end)
  local G = { phase = 'idle', ab = nil, targets = {}, t = 0, on_t = 0, arm = 1, ring = 0, primary = nil, quick = false, w = 0, pw = 0, point = Vector3.new(), must_turn = false, still = 0 }
  local facing, drops, test_old = 0, 0, false
  local function rel_yaw(c) local L = get_L(); local a = atan2(c.x - L.x, c.z - L.z) - mover.yaw(); return atan2(sin(a), cos(a)) end
  local function behind(c) return abs(rel_yaw(c)) > FRONT end
  local TIP = Vector3.new()
  local LOOK = { p = Vector3.new(), t = 9 }

  local function gaze_to(c)
    local L = get_L()
    local a = atan2(c.x - L.x, c.z - L.z) - mover.yaw()
    return atan2(sin(a), cos(a)), atan2(L.y + 0.75 - c.y, max(0.3, hyp(c.x - L.x, c.z - L.z)))
  end
  local function pick_arm(c)
    local L, yw = get_L(), mover.yaw()
    local x = (c.x - L.x)*cos(yw) - (c.z - L.z)*sin(yw)
    local z = (c.x - L.x)*sin(yw) + (c.z - L.z)*cos(yw)
    return x > -0.25*abs(z) and 1 or 0
  end

  local function start_gesture(ab, targets, quick)
    for _, s in ipairs(targets) do claim(s, ab.name, 2.0) end
    G.phase = 'aim'; G.ab = ab; G.targets = targets; G.t = 0; G.on_t = 0; G.still = 0; G.quick = quick
    G.primary = targets[1]; G.ring = ab.aim_ring()
    G.point:copy(G.primary.spine[G.ring + 1])
    G.arm = pick_arm(G.point)
    G.must_turn = behind(G.point)
  end

  local function tick(t, dt)
    clock = clock + dt
    local actives = {}
    for _, a in ipairs(ALL) do if on[a] then actives[#actives + 1] = a end end
    power = #actives > 0 and 6/#actives or 1
    leak.scale(power, ENGAGE)
    for _, a in ipairs(ALL) do nxt[a] = nxt[a] - dt end
    for i = #later, 1, -1 do if clock >= later[i].at then snakes.ignite(later[i].s); table.remove(later, i) end end

    local urgent, urgent_set = {}, {}
    for _, s in ipairs(snakes.S) do if snakes.free(s) and d_egg(s) < URGENT then urgent[#urgent + 1] = s; urgent_set[s] = true end end
    local gestured = {}
    for _, a in ipairs(actives) do if a.gesture then gestured[#gestured + 1] = a end end
    lift.update(dt)
    local low = huge
    for _, a in ipairs(actives) do
      if a ~= leak and nxt[a] < SOON and (a ~= lens or lens.free_lenses() > 0) then low = min(low, fair[a]) end
    end
    local function turn(a) return fair[a] <= low end

    local function try_gesture()
      local far = ENGAGE
      for _, a in ipairs(gestured) do far = max(far, a.engage or ENGAGE) end
      local th_all = threats(far)
      if not (#th_all > 0 or #urgent > 0) or #gestured == 0 then return false end
      local quick = #urgent > 0
      local function has(a)
        if quick then return true end
        for _, s in ipairs(th_all) do if d_egg(s) < (a.engage or ENGAGE) then return true end end
        return false
      end
      local ready = {}
      for _, a in ipairs(gestured) do if nxt[a] <= 0 and (quick or turn(a)) and has(a) then ready[#ready + 1] = a end end
      if #ready == 0 and quick then
        local a = gestured[1]
        for k = 2, #gestured do local y = gestured[k]; if not (nxt[a] <= nxt[y]) then a = y end end
        nxt[a] = 0; ready = { a }
      end
      if #ready == 0 then return false end
      local ab = ready[1]
      for k = 2, #ready do
        local y = ready[k]
        if not (fair[ab] < fair[y] or (fair[ab] == fair[y] and last[ab] <= last[y])) then ab = y end
      end
      local th = {}
      for _, s in ipairs(th_all) do if d_egg(s) < (ab.engage or ENGAGE) then th[#th + 1] = s end end
      local first = quick and stable_sort(urgent, d_egg) or {}
      local notur = {}
      for _, s in ipairs(th) do if not urgent_set[s] then notur[#notur + 1] = s end end
      local ahead = stable_sort(notur, function(s) return (not test_old and behind(s.spine[jround(N*0.3) + 1])) and 1 or 0 end)
      local pick = {}
      for _, s in ipairs(first) do pick[#pick + 1] = s end
      for _, s in ipairs(ahead) do
        if facing ~= 1 or not behind(s.spine[jround(N*0.3) + 1]) then pick[#pick + 1] = s end
      end
      if #pick == 0 then return false end
      local n = max(1, ab.capacity(power))
      local sel = {}
      for k = 1, min(n, #pick) do sel[k] = pick[k] end
      start_gesture(ab, sel, quick)
      return true
    end

    if G.phase == 'idle' then
      try_gesture()
    elseif G.phase == 'aim' then
      G.t = G.t + dt
      local s = G.primary
      if not on[G.ab] or not snakes.free(s) or (facing == 1 and not G.must_turn and behind(s.spine[G.ring + 1])) then
        if on[G.ab] and snakes.free(s) then drops = drops + 1 end
        for _, q in ipairs(G.targets) do q.claim = nil end
        G.phase = 'lower'; G.t = 0
      else
        G.point:copy(s.spine[G.ring + 1])
        local gy = gaze_to(G.point)
        local S = lich.springs
        local reach = max(-1.45, min(1.45, gy))
        G.on_t = abs(reach - (S.hy.x + S.cy.x)) < 0.12 and G.on_t + dt or 0
        local arrived = G.pw >= 1 and G.on_t >= ON_T and lich.arm_speed(G.arm) < (G.quick and QUICK_ARRIVE or ARRIVE) and (test_old or abs(rel_yaw(G.point)) < FIRE_IN)
        G.still = arrived and G.still + dt or 0
        local beat = min(G.ab.beat or BEAT, G.quick and QUICK_BEAT or 9)
        if G.still >= beat or G.t >= (G.quick and QUICK_MAX or AIM_MAX) then
          local targets = {}
          for _, q in ipairs(G.targets) do if snakes.free(q) then targets[#targets + 1] = q end end
          lich.fingertip(G.arm, TIP)
          G.ab.cast(targets, TIP, G.ring, G.arm, G.quick)
          count(G.ab, #targets)
          nxt[G.ab] = G.ab.cooldown/power; last[G.ab] = clock
          G.phase = 'hold'; G.t = 0
        end
      end
    elseif G.phase == 'hold' then
      G.t = G.t + dt
      local channel = G.ab.busy and G.ab.busy() or false
      if channel then G.t = 0; local p = G.ab.aim_point(); if p then G.point:copy(p) end end
      if facing == 1 and not G.must_turn and behind(G.point) then
        if channel and G.ab.let_go then G.ab.let_go() end
        drops = drops + 1; G.phase = 'lower'; G.t = 0; channel = false
      end
      if #urgent > 0 then
        if channel and G.ab.extend then
          local ul = {}
          for k, s in ipairs(urgent) do ul[k] = s end
          if not G.ab.extend(ul, G.arm) and G.ab.cut then G.ab.cut() end
        elseif not channel then G.phase = 'idle'; G.t = 0; G.ab = nil end
      end
      if G.phase == 'hold' and not channel and G.t >= HOLD_CHAIN and try_gesture() then
      elseif G.phase == 'hold' and G.t >= HOLD then G.phase = 'lower'; G.t = 0 end
    elseif G.phase == 'lower' then
      G.t = G.t + dt
      if try_gesture() then
      elseif G.t >= LOWER or #urgent > 0 then G.phase = 'idle'; G.t = 0; G.ab = nil end
    end
    if G.phase == 'aim' then
      G.w = min(1, G.w + dt/0.12)
      if test_old or abs(rel_yaw(G.point)) < ARM_UP then G.pw = min(1, G.pw + dt/(G.quick and 0.12 or 0.22))
      else G.pw = max(0, G.pw - dt/0.2) end
    elseif G.phase == 'hold' then
      G.w = 1
      if test_old or abs(rel_yaw(G.point)) < ARM_UP then G.pw = min(1, G.pw + dt/0.15)
      else G.pw = max(0.2, G.pw - dt/0.15) end
    else G.w = max(0, G.w - dt/LOWER); G.pw = max(0, G.pw - dt/LOWER) end
    local pointing = G.phase == 'aim' or G.phase == 'hold'
    mover.face.on = not test_old and pointing and (facing == 0 or G.must_turn)
    if mover.face.on then local L = get_L(); mover.face.yaw = atan2(G.point.x - L.x, G.point.z - L.z) end
    local m = mover.motion
    m.gaze_w = G.w
    if G.w > 0 then m.gaze, m.gaze_p = gaze_to(G.point) end
    LOOK.t = LOOK.t + dt
    if G.w < 0.05 and LOOK.t < 1.1 then
      m.gaze_w = 0.85*min(1, LOOK.t/0.15)*(1 - max(0, (LOOK.t - 0.8)/0.3))
      m.gaze, m.gaze_p = gaze_to(LOOK.p)
    end
    m.point = G.pw > 0 and { w = G.pw*G.pw*(3 - 2*G.pw), arm = G.arm, x = G.point.x, y = G.point.y, z = G.point.z } or nil

    -- the lens
    if on[lens] then
      local lone = #gestured == 0
      local busy_hand = G.phase == 'aim'
      local rush = nil
      if lone or busy_hand then
        rush = {}
        for _, s in ipairs(urgent) do
          if not (s.claim and s.claim_until > clock and string.find(s.claim, 'QUICK', 1, true)) and not (busy_hand and includes(G.targets, s)) then rush[#rush + 1] = s end
        end
      end
      if rush and #rush > 0 then
        local targets = {}
        for k = 1, min(#rush, lens.free_lenses()) do targets[k] = rush[k] end
        for _, s in ipairs(targets) do claim(s, 'LENS-QUICK', 1.2) end
        lens.cast(targets, true)
        if #targets > 0 then count(lens, #targets); quick_lens = quick_lens + 1 end
      elseif nxt[lens] <= 0 and turn(lens) then
        local th = threats(LENS_ENGAGE)
        local n = min(lens.capacity(power), lens.free_lenses(), #th)
        if n > 0 then
          local targets = {}
          for k = 1, n do targets[k] = th[k] end
          for _, s in ipairs(targets) do claim(s, 'LENS', 2.6) end
          local at = lens.cast(targets)
          count(lens, #targets)
          if #at > 0 then LOOK.p:copy(at[1]); LOOK.t = 0 end
          nxt[lens] = lens.cooldown/power; last[lens] = clock
        end
      end
    end
    -- the rock
    if on[rock] then
      local busy_hand = G.phase == 'aim'
      local rush = nil
      if #gestured == 0 or busy_hand then
        rush = {}
        for _, s in ipairs(urgent) do
          if not (s.claim and s.claim_until > clock and string.find(s.claim, 'QUICK', 1, true)) and not (busy_hand and includes(G.targets, s)) then rush[#rush + 1] = s end
        end
      end
      if rush and #rush > 0 and rock.free_rocks() > 0 then
        local targets = {}
        for k = 1, min(#rush, min(2, rock.free_rocks())) do targets[k] = rush[k] end
        for _, s in ipairs(targets) do claim(s, 'ROCK-QUICK', 1.2) end
        rock.cast(targets, nil, 0, 1, true)
        count(rock, #targets)
      elseif nxt[rock] <= 0 and turn(rock) and rock.free_rocks() > 0 then
        local th = threats(rock.engage)
        local n = min(rock.capacity(power), rock.free_rocks(), #th)
        if n > 0 then
          local targets = {}
          for k = 1, n do targets[k] = th[k] end
          for _, s in ipairs(targets) do claim(s, 'ROCK', 2.6) end
          rock.cast(targets)
          count(rock, #targets)
          nxt[rock] = rock.cooldown/power; last[rock] = clock
          local p = rock.hold_at()
          if p and G.w < 0.05 then LOOK.p:copy(p); LOOK.t = 0 end
        end
      end
    end
    local urg = nil
    if not (#gestured > 0 or on[lens] or on[rock]) then urg = urgent_set end
    leak.update(t, dt, on[leak], urg)
    beam.update(t, dt)
    rock.update(t, dt)
    lens.update(t, dt)
  end

  local P = { ALL = ALL, tick = tick, beam = beam, lens = lens, rock = rock, lift = lift, leak = leak }
  function P.after_pose(t) beam.after_pose(t) end
  function P.power() return power end
  function P.is_on(a) return on[a] end
  function P.glance(p) LOOK.p:copy(p); LOOK.t = 0 end
  function P.toggle(i)
    local a = ALL[i + 1]
    if a then on[a] = not on[a]; reset_fair() end
    return a and on[a]
  end
  function P.set(i, v)
    local a = ALL[i + 1]
    if a and on[a] ~= (not not v) then on[a] = not not v; reset_fair() end
  end
  function P.state()
    local names, nx = {}, {}
    for _, a in ipairs(ALL) do if on[a] then names[#names + 1] = a.name end; nx[#nx + 1] = nxt[a] end
    local us, tk = {}, {}
    for _, a in ipairs(ALL) do us[a.name] = a == leak and snakes.dissolved or uses[a]; tk[a.name] = a == leak and snakes.dissolved or took[a] end
    return { phase = G.phase, ab = G.ab and G.ab.name, t = G.t, power = power, on = names, next = nx, leak_reach = leak.reach(), uses = us, took = tk }
  end
  function P.quick_lens() return quick_lens end
  function P.get_facing() return facing end
  function P.set_facing(i) local n = #PW.FACINGS; facing = ((i % n) + n) % n end
  function P.drops() return drops end
  function P.set_test_old(v) test_old = not not v end
  function P.reset_uses() for _, a in ipairs(ALL) do uses[a] = 0; took[a] = 0 end end
  function P.force(i, x, z)
    local a = ALL[i + 1]
    local lv = {}
    for _, s in ipairs(snakes.S) do if unclaimed(s) then lv[#lv + 1] = s end end
    lv = stable_sort(lv, function(p) return hyp(p.x - x, p.z - z) end)
    if #lv == 0 or not a then return -1 end
    local function index_of(s) for k, q in ipairs(snakes.S) do if q == s then return k - 1 end end; return -1 end
    if a == lens then lens.cast({ lv[1] }); return index_of(lv[1]) end
    if a.gesture and G.phase == 'idle' then
      local n = max(1, a.capacity(power))
      local sel = {}
      for k = 1, min(n, #lv) do sel[k] = lv[k] end
      start_gesture(a, sel, false)
      return index_of(lv[1])
    end
    return -1
  end
  return P
end

return PW
