--[[
  rock.lua -- the port to Anchor: web/src/rock.js. ROCK: his mind tears a rock out of the floor in
  front of him, holds it on a soft spring beside his hand in warped air, and urges it along a
  floating arc onto a snake; a struck snake becomes a loose heavy rope of its own rings (crush_fx),
  knocked along, twitching, then sinking. The eight rocks' shapes are the three.js build's
  (ConvexGeometry from the same draws); the draws are still made here so the powers' rng keeps step.
  Round 50: three or more in one cast (the bouts, powers.lua) are torn up all round him, circle him
  in warped air, then are loosed together, each at its snake.
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local U = require('port.util')
local FX = require('port.fx')
local AU = require('port.audio')     -- 2026-10-10: the sounds (never draw from rng here)
local Vector3, Quaternion, Euler = TM.Vector3, TM.Quaternion, TM.Euler
local smoothstep = U.smoothstep
local sqrt, abs, sin, exp, floor, ceil, min, max = math.sqrt, math.abs, math.sin, math.exp, math.floor, math.ceil, math.min, math.max

local RO = {}
local HOLD, STAGGER, SPEED, ACCEL, GRAV, HIT_R = 0.25, 0.12, 17, 55, 9.8, 0.14
local CONTROL_MAX = 1.4
local REST, SINK = 3.0, 1.2
local ORBIT_R, ORBIT_W, ORBIT_HOLD, ORBIT_FROM = 1.15, 2.4, 1.0, 1.5

function RO.create(ctx)
  local R, snakes, fx, cave, rng, gore, warp, lich, get_L = ctx.R, ctx.snakes, ctx.fx, ctx.cave, ctx.rng, ctx.gore, ctx.warp, ctx.lich, ctx.get_L
  local N = snakes.RINGS
  local mid = floor(N*0.4 + 0.5)
  local A = R.statics

  local mat = MAT.MeshLambertMaterial.new({ name = 'rock.stone', map = cave.rock_tex, color = 0xffffff, flat_shading = true })
  if cave.GU then FX.gi_dynamic(mat, cave.GU) end
  local POOL = {}
  for i = 0, 7 do
    -- make_geo's draws (the hull itself is exported)
    local sx, sy, sz = rng.float(0.17, 0.23), rng.float(0.13, 0.17), rng.float(0.15, 0.2)
    for _ = 1, 16 do rng.spread(2); rng.spread(2); rng.spread(2) end
    local m = T.Mesh.new(A.geometry('rock_' .. i), mat)
    m.cast_shadow = true; m.receive_shadow = true; m.visible = false; m.frustum_culled = false
    R.world_scene:add(m)
    POOL[#POOL + 1] = { m = m, r = (sx + sy + sz)/3, on = false }
  end
  local live = {}
  local stats = { thrown = 0, hits = 0, multi = 0, missed = 0 }
  local V, V2, Q, Av, TG = Vector3.new(), Vector3.new(), Quaternion.new(), Vector3.new(), Vector3.new()
  local function includes(list, x) for _, v in ipairs(list) do if v == x then return true end end; return false end
  local hyp = js_hypot

  -- struck: its own rings become a rope with weight
  local function crush_fx(s, c, dir, vel)
    local n = N
    local P, O = {}, {}
    for i = 1, n do P[i] = s.spine[i]:clone() end
    for i = 1, n do O[i] = P[i]:clone() end
    local L1, L2 = {}, {}
    for i = 1, n - 1 do L1[i] = P[i]:distance_to(P[i + 1]) end
    for i = 1, n - 2 do L2[i] = P[i]:distance_to(P[i + 2]) end
    local sp = min(9, vel:length())*rng.float(0.55, 0.75)
    local up = rng.float(0.8, 1.8)
    local h = 1/60
    for i = 0, n - 1 do
      local w = exp(-(((i - c)/5)^2))
      local o = O[i + 1]
      o.x = o.x - (dir.x*sp*w)*h; o.z = o.z - (dir.z*sp*w)*h; o.y = o.y - up*w*h
    end
    local rad = {}
    for i = 1, n do rad[i] = s.radii[i] end
    local f
    f = {
      t = 0, sag = 0,
      radk = function(i) return 1 - 0.55*exp(-(((i - c)/3.5)^2)) end,
      char = function(i) return 0.35*exp(-(((i - c)/2.5)^2)) end,
      place = function(i, out) out:copy(P[i + 1]) end,
      tick = function(dt)
        f.t = f.t + dt
        local sinking = f.t > 2.3
        for i = 1, n do
          local p, o = P[i], O[i]
          local vx, vy, vz = (p.x - o.x)*0.995, (p.y - o.y)*0.995, (p.z - o.z)*0.995
          o:copy(p)
          p.x = p.x + vx; p.y = p.y + (vy - (sinking and 0 or 9.8*dt*dt)); p.z = p.z + vz
          if sinking then p.y = p.y - 0.3/1.2*dt end
        end
        if not sinking and f.t < 1.8 and rng.next() < 0.5*exp(-f.t*1.5) then
          local j = rng.int(4, n - 4)
          local k = 0.02*exp(-f.t*1.2)
          for m = -3, 3 do
            local q = P[j + m + 1]
            if q then q.x = q.x + rng.spread(k); q.y = q.y + abs(rng.spread(k))*0.5; q.z = q.z + rng.spread(k) end
          end
        end
        for _ = 1, 5 do
          for i = 1, n - 1 do
            local a, b = P[i], P[i + 1]
            local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
            local d = js_hypot(dx, dy, dz); if d == 0 then d = 1e-6 end
            local k = (d - L1[i])/d*0.5
            a.x = a.x + dx*k; a.y = a.y + dy*k; a.z = a.z + dz*k; b.x = b.x - dx*k; b.y = b.y - dy*k; b.z = b.z - dz*k
          end
          for i = 1, n - 2 do
            local a, b = P[i], P[i + 2]
            local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
            local d = js_hypot(dx, dy, dz); if d == 0 then d = 1e-6 end
            local k = (d - L2[i])/d*0.5*0.12
            a.x = a.x + dx*k; a.y = a.y + dy*k; a.z = a.z + dz*k; b.x = b.x - dx*k; b.y = b.y - dy*k; b.z = b.z - dz*k
          end
          if not sinking then
            for i = 1, n do
              local p, o = P[i], O[i]
              local g = cave.ground_y(p.x, p.z) + rad[i]*0.8
              if p.y < g then
                p.y = g
                o.x = p.x - (p.x - o.x)*0.9; o.z = p.z - (p.z - o.z)*0.9
                if o.y < p.y - 0.02 then o.y = p.y - (p.y - o.y)*0.3 end
              end
            end
          end
        end
        if f.t > 3.5 then return 'done' end
      end,
    }
    return f
  end
  local claimed                                    -- (below; hits() asks it too)
  local function hits(q, cb)
    local p = q.m.position
    for _, s in ipairs(snakes.S) do
      if snakes.free(s) and not includes(q.hit, s) and not (snakes.held_by_other and s ~= q.target and (snakes.held_by_other(s, 'ROCK') or claimed(s, q))) then
        local best, bi = 1e9, -1
        for j = 2, N - 3 do local d = s.spine[j + 1]:distance_to(p); if d < best then best = d; bi = j end end
        if best < q.r + HIT_R then cb(s, bi) end
      end
    end
  end

  -- where a snake's middle will be dt from now
  local function ahead(s, dt, out)
    local a, b = s.spine[mid + 1], s.spine[min(N - 1, mid + 4) + 1]
    V:sub_vectors(a, b); V.y = 0
    local l = V:length(); if l == 0 then l = 1 end
    return out:copy(a):add_scaled_vector(V, (s.speed or 1.1)*dt/l)
  end
  claimed = function(s, q)
    for _, o in ipairs(live) do if o ~= q and o.target == s and o.phase ~= 'rest' then return true end end
    return false
  end
  local function another(q)
    local best, bd = nil, 1e9
    for _, s in ipairs(snakes.S) do
      if snakes.free(s) and not claimed(s, q) and not (snakes.held_by_other and snakes.held_by_other(s, 'ROCK')) then
        local d = hyp(s.x - snakes.egg.x, s.z - snakes.egg.z)
        if d < bd and d < 7 then bd = d; best = s end
      end
    end
    return best
  end
  local function best_line(from, first, q)
    local cands = { first }
    for _, s in ipairs(snakes.S) do
      if s ~= first and snakes.free(s) and not claimed(s, q) and s.spine[mid + 1]:distance_to(first.spine[mid + 1]) < 4 then cands[#cands + 1] = s end
    end
    local best_s, best_n = first, 0
    local P0, D = Vector3.new(), Vector3.new()
    for _, c in ipairs(cands) do
      ahead(c, from:distance_to(c.spine[mid + 1])/SPEED, P0)
      D:sub_vectors(P0, from); D.y = 0; D:normalize()
      local n = 0
      for _, s in ipairs(snakes.S) do
        if snakes.free(s) then
          for j = 4, N - 5, 5 do
            V:sub_vectors(s.spine[j + 1], P0); V.y = 0
            local along, across = V:dot(D), abs(V.x*D.z - V.z*D.x)
            if along > -0.6 and along < 4 and across < 0.3 then n = n + 1; break end
          end
        end
      end
      if n > best_n then best_s = c; best_n = n end
    end
    return best_s
  end

  local function raise(target, k, arm, quick, n, a0)
    quick = quick or false
    local q
    for _, p in ipairs(POOL) do if not p.on then q = p; break end end
    if not q then return end
    local L = get_L()
    V:sub_vectors(target.spine[mid + 1], L); V.y = 0
    local dir = V:normalize():clone()
    local side = Vector3.new(-dir.z, 0, dir.x)
    local off = (k - 0.5*(k > 0 and 1 or 0))*0.45*((k % 2) ~= 0 and 1 or -1)
    local from = L:clone():add_scaled_vector(dir, 1.15):add_scaled_vector(side, off*1.2)
    from.y = cave.ground_y(from.x, from.z) - q.r*0.8
    local hold = L:clone():add_scaled_vector(dir, 1.0):add_scaled_vector(side, off)
    hold.y = L.y + 0.45 + k*0.12
    q.on = true; q.phase = 'rip'; q.t = -k*STAGGER*(quick and 0.4 or 1); q.quick = quick; q.hold_t = quick and 0.05 or HOLD; q.speed = quick and SPEED*1.45 or SPEED
    q.accel = quick and ACCEL*2.2 or ACCEL; q.ramp = 0
    local p1 = rng.float(0, 6.28); local p2 = rng.float(0, 6.28); local p3 = rng.float(0, 6.28); local p4 = rng.float(0, 6.28)
    q.ph = { p1, p2, p3, p4 }; q.ctrl = true
    q.wait = 0; q.set_down = false
    q.torn = false; q.hits = 0; q.from = from; q.hold = hold; q.target = target; q.arm = arm; q.hit = {}; q.v = Vector3.new(); q.w = Vector3.new()
    q.rest = 0; q.bounced = 0; q.wake = 0; q.dir = dir
    q.orbit = nil
    if n then
      -- round 50: its place in the ring round him; torn from the floor under that place
      local a = a0 + k*6.2832/n
      q.orbit = { a = a, spin = 0 }
      from:set(L.x + sin(a)*ORBIT_FROM, 0, L.z + math.cos(a)*ORBIT_FROM)
      from.y = cave.ground_y(from.x, from.z) - q.r*0.8
      q.t = -k*0.03; q.hold_t = ORBIT_HOLD + k*0.04
    end
    q.m.position:copy(from); q.m.visible = true
    local ex = rng.float(0, 6); local ey = rng.float(0, 6); local ez = rng.float(0, 6)
    q.m.quaternion:set_from_euler(Euler.new(ex, ey, ez))
    live[#live + 1] = q
  end
  local function tear(q)
    local p = q.from
    local gy = cave.ground_y(p.x, p.z)
    for _ = 1, 16 do
      local a, r = rng.float(0, 6.28), rng.float(0.05, 0.35)
      local x, z = p.x + math.cos(a)*r, p.z + math.sin(a)*r
      local vx = math.cos(a)*rng.float(0.5, 1.4)
      local vy = rng.float(0.3, 1.2)
      local vz = math.sin(a)*rng.float(0.5, 1.4)
      fx.puff({ x = x, y = gy + 0.05, z = z, vx = vx, vy = vy, vz = vz, drag = 2.0, life = rng.float(0.8, 1.5), s0 = 0.12, s1 = 0.45, r = 0.035, g = 0.03, b = 0.022, a = 0.55 })
    end
    for _ = 1, 9 do
      local c = fx.chunk()
      c.life = rng.float(1.5, 2.5); c.x = p.x + rng.spread(0.2); c.y = gy + 0.05; c.z = p.z + rng.spread(0.2)
      c.vx = rng.spread(1.6); c.vy = rng.float(1.5, 3.2); c.vz = rng.spread(1.6)
      c.rx = 0; c.ry = 0; c.rz = 0; c.wx = rng.spread(10); c.wy = rng.spread(10); c.wz = rng.spread(10)
      c.s = rng.float(0.018, 0.04); c.sx = 1; c.sy = rng.float(0.6, 1); c.sz = 1
    end
    for _ = 1, 5 do
      local x = p.x + rng.spread(0.3)
      local z = p.z + rng.spread(0.3)
      warp.puff({ x = x, y = gy + 0.2, z = z, vy = 0.5, life = 0.7, s0 = 0.2, s1 = 0.7, amp = 3.5, spin = rng.spread(3) })
    end
  end
  local function aura(p, big)
    local x = p.x + rng.spread(0.12)
    local y = p.y + rng.spread(0.12)
    local z = p.z + rng.spread(0.12)
    local vx = rng.spread(0.2)
    local vy = rng.spread(0.2)
    local vz = rng.spread(0.2)
    return warp.puff({ x = x, y = y, z = z, vx = vx, vy = vy, vz = vz, drag = 2, life = rng.float(0.25, 0.45), s0 = 0.3*big, s1 = 0.55*big, amp = 3.2, spin = rng.spread(4) })
  end

  local function update(t, dt)
    for i = #live, 1, -1 do
      local q = live[i]
      local m = q.m
      q.t = q.t + dt
      -- (round 52: a rock on its way keeps its snake: no one else takes it before it lands)
      if snakes.reclaim and q.target and snakes.free(q.target) and (q.phase == 'rip' or q.phase == 'hold' or (q.phase == 'fly' and q.ctrl)) then
        snakes.reclaim(q.target, 'ROCK')
      end
      if q.orbit and (q.phase == 'rip' or q.phase == 'hold') then
        local o = q.orbit
        if q.t >= 0 then o.spin = o.spin + dt*ORBIT_W end
        local L = get_L()
        local a = o.a + o.spin
        q.hold:set(L.x + sin(a)*ORBIT_R, L.y + 0.55 + 0.06*sin(t*2.3 + o.a*3), L.z + math.cos(a)*ORBIT_R)
        if q.target then
          V:sub_vectors(q.target.spine[mid + 1], q.hold); V.y = 0
          if V:length_sq() > 1e-6 then q.dir:copy(V:normalize()) end
        end
      end
      if q.t >= 0 then
        if not q.quick and q.target and (q.phase == 'rip' or q.phase == 'hold' or q.phase == 'fly') and hyp(q.target.x - snakes.egg.x, q.target.z - snakes.egg.z) < 2.9 then
          q.quick = true; q.hold_t = min(q.hold_t, 0.05); q.speed = SPEED*1.45; q.accel = ACCEL*2.2
        end
        local function wander(amp, out)
          return out:set(
            (sin(t*2.1 + q.ph[1])*0.6 + sin(t*4.7 + q.ph[2])*0.4)*amp,
            (sin(t*1.7 + q.ph[3])*0.6 + sin(t*3.9 + q.ph[4])*0.4)*amp*0.6,
            (sin(t*2.6 + q.ph[2])*0.6 + sin(t*5.3 + q.ph[3])*0.4)*amp)
        end
        local function hold_on(Tg, f, z, amax, wob)
          local w = 6.2832*f
          q.ramp = min(1, q.ramp + dt/0.15)
          Av:sub_vectors(Tg, m.position):multiply_scalar(w*w):add_scaled_vector(q.v, -2*z*w)
          Av:add(wander(wob, V))
          local l, cap = Av:length(), amax*q.ramp
          if l > cap then Av:multiply_scalar(cap/l) end
          q.v:add_scaled_vector(Av, dt)
          m.position:add_scaled_vector(q.v, dt)
        end
        local function spin(to, rate)
          q.w:multiply_scalar(1 - min(1, rate*dt))
          if q.w:length() < to then q.w:add_scaled_vector(V:set(q.ph[1] - 3, q.ph[2] - 3, q.ph[3] - 3):normalize(), to*rate*dt) end
        end
        if q.phase == 'rip' then
          if not q.torn then
            q.torn = true; tear(q); q.v:set(q.dir.x*0.6, q.quick and 5 or 3.4, q.dir.z*0.6); q.ramp = 0.3
            AU.play('rock_rip', { pos = q.from, gap = 0.05 })
            q.snd = AU.loop('rock_hold', { pos = m.position, max = 2 })
          end
          if q.snd then q.snd.set_pos(m.position) end
          hold_on(q.hold, q.quick and 2.4 or (q.orbit and 2.2 or 1.5), 0.5, q.quick and 90 or (q.orbit and 60 or 40), 2.5)
          spin(2, 3)
          if rng.next() < 0.5 then aura(m.position, 0.9) end
          local near = m.position:distance_to(q.hold) < 0.2 and q.v:length() < 1.2
          if (q.t > (q.quick and 0.12 or 0.3) and near) or q.t > (q.quick and 0.25 or 0.6) then q.phase = 'hold'; q.pt = 0; q.ramp = 0.5 end
        elseif q.phase == 'hold' then
          q.pt = q.pt + dt
          local back = smoothstep(q.hold_t - 0.14, q.hold_t, q.pt)
          TG:copy(q.hold):add_scaled_vector(q.dir, -0.18*back)
          TG.y = TG.y + (0.05*back + sin(t*2.2 + q.ph[1])*0.03)
          hold_on(TG, q.orbit and 2.4 or 1.3, 0.42, q.orbit and 60 or 25, 2.0)
          if q.snd then q.snd.set_pos(m.position) end
          spin(0.8, 2)
          if rng.next() < 0.7 then aura(m.position, 1) end
          if q.pt >= q.hold_t then
            if not q.target or not snakes.free(q.target) or claimed(q.target, q) then q.target = another(q) end
            q.target = q.target and best_line(m.position, q.target, q) or nil
            -- (round 52: nothing left to throw it at: held a little longer, then set down, never thrown at nothing)
            local waiting = false
            if snakes.reclaim and not q.target then
              q.wait = (q.wait or 0) + 1
              if q.wait < 40 then q.pt = q.hold_t - 0.05; waiting = true else q.v:set(0, -0.5, 0); q.ctrl = false; q.set_down = true end
            end
            if not waiting then
              q.phase = 'fly'; q.ft = 0; q.ramp = 0.35; q.s_cmd = q.v:length(); q.l0 = m.position:clone()
              q.h0 = q.target and max(1, hyp(q.target.spine[mid + 1].x - m.position.x, q.target.spine[mid + 1].z - m.position.z)) or 4
              if not q.set_down then stats.thrown = stats.thrown + 1; for _ = 1, 4 do aura(m.position, 1.3) end; AU.play('rock_throw', { pos = m.position, gap = 0.04 }) end
              if q.snd then q.snd.stop(); q.snd = nil end
            end
          end
        elseif q.phase == 'fly' then
          q.ft = q.ft + dt
          if q.ctrl and q.target and (not snakes.free(q.target) or includes(q.hit, q.target)) then
            local o = nil
            if #q.hit == 0 then o = another(q) end
            if o then q.target = o else q.ctrl = false end
          end
          if q.ctrl and q.target and q.ft < CONTROL_MAX then
            ahead(q.target, 0, TG); TG.y = cave.ground_y(TG.x, TG.z) + 0.1
            local hx, hz = TG.x - m.position.x, TG.z - m.position.z
            local h = max(1e-3, hyp(hx, hz))
            q.s_cmd = min(q.speed, q.s_cmd + q.accel*dt)
            local u = min(1, 1 - h/q.h0)
            local arc = min(0.6, 0.1*q.h0)*(q.quick and 0.5 or 1)
            local look = min(1, u + q.s_cmd*0.12/q.h0)
            local y_next = m.position.y + (TG.y - m.position.y)*min(1, q.s_cmd*0.12/h) + arc*4*(look*(1 - look) - u*(1 - u))
            V2:set(hx/h*q.s_cmd, (y_next - m.position.y)/0.12, hz/h*q.s_cmd)
            q.ramp = min(1, q.ramp + dt/0.15)
            Av:sub_vectors(V2, q.v):multiply_scalar(12)
            local side = V:set(-hz/h, 0, hx/h):multiply_scalar((sin(t*3.1 + q.ph[1])*0.7 + sin(t*6.3 + q.ph[4])*0.3)*7)
            Av:add(side); Av.y = Av.y + sin(t*2.7 + q.ph[3])*3
            local l, cap = Av:length(), q.accel*1.4*q.ramp
            if l > cap then Av:multiply_scalar(cap/l) end
            q.v:add_scaled_vector(Av, dt)
            m.position:add_scaled_vector(q.v, dt)
          else
            q.ctrl = false
            q.v.y = q.v.y - GRAV*dt
            m.position:add_scaled_vector(q.v, dt)
          end
          spin(q.ctrl and 9 or 5, 2.5)
          local wl = q.w:length()
          if wl > 1e-3 then Q:set_from_axis_angle(V:copy(q.w):multiply_scalar(1/wl), wl*dt); m.quaternion:premultiply(Q) end
          q.wake = q.wake + dt*40*min(1, q.v:length()/6)
          while q.wake >= 1 do
            q.wake = q.wake - 1
            warp.puff({ x = m.position.x, y = m.position.y, z = m.position.z, vx = -q.v.x*0.05, vy = 0.05, vz = -q.v.z*0.05, drag = 3, life = rng.float(0.25, 0.4), s0 = 0.22, s1 = 0.5, amp = 3.4, spin = rng.spread(3) })
          end
          hits(q, function(s, j)
            V2:copy(q.v); V2.y = 0
            local dir = V2:normalize():clone()
            snakes.take(s, crush_fx(s, max(3, j), dir, q.v))
            s.claim = nil
            q.hit[#q.hit + 1] = s
            AU.play('rock_hit', { pos = s.spine[j + 1] })
            gore.crush(s.spine[j + 1], dir, s.radii[j + 1])
            q.v:multiply_scalar(0.78)
            q.ctrl = false
            q.hits = (q.hits or 0) + 1; stats.hits = stats.hits + 1; if q.hits == 2 then stats.multi = stats.multi + 1 end
          end)
          local gy = cave.ground_y(m.position.x, m.position.z) + q.r*0.75
          if m.position.y < gy then
            m.position.y = gy
            if q.v.y < 0 then
              if abs(q.v.y) > 0.6 then AU.play('rock_land', { pos = m.position, volume = math.min(1, abs(q.v.y)/4), gap = 0.05 }) end
              for _ = 1, 8 do
                local x = m.position.x + rng.spread(0.15)
                local z = m.position.z + rng.spread(0.15)
                local vx = rng.spread(0.8) + q.v.x*0.1
                local vy = rng.float(0.2, 0.7)
                local vz = rng.spread(0.8) + q.v.z*0.1
                fx.puff({ x = x, y = gy - q.r*0.5, z = z, vx = vx, vy = vy, vz = vz, drag = 2.2, life = rng.float(0.7, 1.2), s0 = 0.1, s1 = 0.35, r = 0.035, g = 0.03, b = 0.022, a = 0.45 })
              end
              q.v.y = abs(q.v.y) > 1.5 and -q.v.y*0.32 or 0
              q.v.x = q.v.x*0.72; q.v.z = q.v.z*0.72; q.w:multiply_scalar(0.6)
              q.bounced = q.bounced + 1
            end
            local d = 1 - min(1, 2.2*dt)
            q.v.x = q.v.x*d; q.v.z = q.v.z*d
          end
          if q.bounced ~= 0 and hyp(q.v.x, q.v.z) < 0.6 and abs(q.v.y) < 0.3 then
            q.phase = 'rest'; q.rest = 0
            if q.hits == 0 and not q.set_down then
              stats.missed = stats.missed + 1
              stats.why = stats.why or {}
              local tg = q.target
              stats.why[#stats.why + 1] = string.format('target %s free %s fx %s claim %s quick %s ctrl %s', tostring(tg ~= nil), tostring(tg and snakes.free(tg)),
                tostring(tg and tg.fx ~= nil), tostring(tg and tg.claim), tostring(q.quick), tostring(q.ctrl))
            end
          end
        end
        if q.phase == 'rip' or q.phase == 'hold' then
          local wl = q.w:length()
          if wl > 1e-3 then Q:set_from_axis_angle(V:copy(q.w):multiply_scalar(1/wl), wl*dt); m.quaternion:premultiply(Q) end
        end
        if q.phase == 'rest' then
          q.rest = q.rest + dt
          if q.rest > REST then m.position.y = m.position.y - (q.r*2.4/SINK)*dt end
          if q.rest > REST + SINK then q.on = false; m.visible = false; table.remove(live, i) end
        end
      end
    end
  end

  local P = { name = 'ROCK', gesture = false, cooldown = 5.0, engage = 5.6, stats = stats, update = update }
  function P.capacity(p) return ceil(p/1.5) end
  function P.aim_ring() return mid end
  function P.cast(targets, from, ring, arm, quick, group)
    if arm == nil then arm = 1 end
    local n, a0 = nil, nil
    if group and #targets >= 3 then
      local L = get_L()
      local p = targets[1].spine[mid + 1]
      n = #targets; a0 = math.atan(p.x - L.x, p.z - L.z)
    end
    for k, s in ipairs(targets) do raise(s, k - 1, arm, quick or false, n, a0) end
  end
  function P.busy_count() local n = 0; for _, q in ipairs(live) do if q.phase ~= 'rest' then n = n + 1 end end; return n end
  function P.free_rocks() local n = 0; for _, p in ipairs(POOL) do if not p.on then n = n + 1 end end; return n end
  function P.hold_at() for _, q in ipairs(live) do if q.phase == 'rip' or q.phase == 'hold' then return q.hold end end; return nil end
  return P
end

return RO
