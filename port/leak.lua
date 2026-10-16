--[[
  leak.lua -- the port to Anchor: web/src/leak.js. LEAKAGE: a snake within its reach slows and
  comes apart from the part nearest him outward (snakes.lua draws it from s.leak); flakes of it
  swirl up and go to warped air; wind lines of warped air curl out of his skull; now and then a
  ripple runs across the floor to the edge of its reach. It happens by itself.
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local U = require('port.util')
local FX = require('port.fx')
local W = require('port.warp')
local AU = require('port.audio')     -- 2026-10-10: the sounds (never draw from rng here)
local Vector3, Quaternion, Euler, Matrix4 = TM.Vector3, TM.Quaternion, TM.Euler, TM.Matrix4
local smoothstep = U.smoothstep
local sqrt, abs, sin, cos, floor, min, max = math.sqrt, math.abs, math.sin, math.cos, math.floor, math.min, math.max

local LK = {}
local K = W.K
local hyp = js_hypot
local function jround(x) return floor(x + 0.5) end

function LK.create(ctx)
  local R, snakes, warp, lich, rng, egg, get_L, cave = ctx.R, ctx.snakes, ctx.warp, ctx.lich, ctx.rng, ctx.egg, ctx.get_L, ctx.cave
  local N = snakes.RINGS
  local A = R.statics
  local H = Vector3.new()
  local ring_t, emit = 0, 0
  local reach, rate = 2.6, 0.22
  local streaks, rings = {}, {}

  local DS = 0.08
  local function streak_from(p0)
    local s = warp.streak()
    if not s then return end
    local sp = rng.float(1.3, 2.2)*(0.7 + reach/6)
    local len = rng.float(0.6, 1.1)*(0.8 + reach/10)
    local life = min(3.2, max(0.9, (reach*rng.float(0.7, 1.05))/sp))
    local a, e = rng.float(0, 6.2832), rng.float(-0.25, 0.35)
    local curl, rise, wav = rng.spread(1.6), rng.spread(0.35), rng.float(0, 6.28)
    local path, q = { p0:clone() }, p0:clone()
    local total = sp*life + len
    local d = 0
    while d < total do
      a = a + curl*DS; e = e + rise*DS*0.5
      q.x = q.x + sin(a)*cos(e)*DS; q.y = q.y + (sin(e) + 0.06*sin(d*5 + wav))*DS; q.z = q.z + cos(a)*cos(e)*DS
      local g = cave.ground_y(q.x, q.z) + 0.15
      if q.y < g then q.y = g; e = max(e, 0) end
      path[#path + 1] = q:clone()
      d = d + DS
    end
    s.w = rng.float(0.08, 0.15); s.amp = rng.float(3.1, 4.6)*(0.85 + min(1, reach/10)*0.4); s.chroma = rng.float(0.85, 1.15)
    streaks[#streaks + 1] = { s = s, path = path, sp = sp, len = len, life = life, t = 0 }
  end
  local function at(path, d, out)
    local f = max(0, min(#path - 1.001, d/DS))
    local i = floor(f)
    return out:lerp_vectors(path[i + 1], path[i + 2], f - i)
  end
  local function update_streaks(dt)
    for i = #streaks, 1, -1 do
      local q = streaks[i]
      q.t = q.t + dt
      local head = q.t*q.sp
      local tail = max(0, head - q.len*min(1, q.t/0.3))
      for k = 0, K - 1 do at(q.path, tail + (head - tail)*k/(K - 1), q.s.pts[k + 1]) end
      q.s.a = smoothstep(0, 0.15, q.t)*(1 - smoothstep(q.life - 0.35, q.life, q.t))
      if q.t >= q.life then warp.release(q.s); table.remove(streaks, i) end
    end
  end
  local function ring_from(c)
    local s = warp.streak()
    if not s then return end
    s.w = 0.16; s.amp = 3.2; s.chroma = 0.8
    rings[#rings + 1] = { s = s, c = c:clone(), t = 0, T = 1.4 + reach*0.06 }
  end
  local function update_rings(dt)
    for i = #rings, 1, -1 do
      local q = rings[i]
      q.t = q.t + dt
      local u = q.t/q.T
      local r = 0.3 + (reach - 0.3)*(1 - (1 - min(1, u))^1.6)
      for k = 0, K - 1 do
        local a = k/(K - 1)*6.2832
        local p = q.s.pts[k + 1]
        p:set(q.c.x + sin(a)*r, 0, q.c.z + cos(a)*r)
        p.y = cave.ground_y(p.x, p.z) + 0.08
      end
      q.s.a = smoothstep(0, 0.1, u)*(1 - smoothstep(0.6, 1, u))*0.9
      if u >= 1 then warp.release(q.s); table.remove(rings, i) end
    end
  end

  -- flakes
  local FN = 700
  local fmat = MAT.MeshBasicMaterial.new({ name = 'leak.flakes', color = 0xffffff, side = MAT.DoubleSide })
  local fmesh = T.InstancedMesh.new(A.geometry('circle_1_5'), fmat, FN)
  do
    local a = {}
    for k = 1, FN*3 do a[k] = 0 end
    fmesh.instance_color = T.BufferAttribute.new(a, 3); fmesh.instance_color.instanced = true
  end
  fmesh.frustum_culled = false
  R.world_scene:add(fmesh)
  local FL = {}
  local ZERO = Matrix4.new():make_scale(0, 0, 0)
  for i = 0, FN - 1 do FL[i + 1] = { life = 0 }; fmesh:set_matrix_at(i, ZERO) end
  local fnext = 0
  local M4, QQ, EE, SV, PV, OP = Matrix4.new(), Quaternion.new(), Euler.new(), Vector3.new(), Vector3.new(), { 1, 1, 1 }
  local function opal(h)
    local s = FX.spectrum(h)
    local c = { s[1]*s[1]*(3 - 2*s[1]), s[2]*s[2]*(3 - 2*s[2]), s[3]*s[3]*(3 - 2*s[3]) }
    for i = 1, 3 do c[i] = c[i]*0.84 + 0.08 end
    local m = max((c[1] + c[2] + c[3])/3, 0.2)
    OP[1] = c[1]/m; OP[2] = c[2]/m; OP[3] = c[3]/m
    return OP
  end
  local function flake(p, r)
    local f = FL[fnext + 1]; fnext = (fnext + 1) % FN
    local a = rng.float(0, 6.28)
    f.life = rng.float(0.9, 1.5); f.t = 0; f.x = p.x + cos(a)*r; f.y = p.y + rng.spread(r); f.z = p.z + sin(a)*r; f.cx = p.x; f.cz = p.z
    f.vx = cos(a)*rng.float(0.1, 0.35); f.vy = rng.float(0.25, 0.6); f.vz = sin(a)*rng.float(0.1, 0.35); f.s = rng.float(0.018, 0.04)
    f.rx = rng.float(0, 6); f.ry = rng.float(0, 6); f.rz = rng.float(0, 6); f.wx = rng.spread(9); f.wy = rng.spread(9); f.wz = rng.spread(9); f.hue = rng.next()
    local sg = rng.sign()
    f.curl = sg*rng.float(1.2, 2.4); f.puffed = false
    f.max = f.life
  end
  local function update_flakes(t, dt)
    local ic = fmesh.instance_color.array
    local lo, hi = nil, nil      -- (2026-10-16, Phylactery 19: only the flakes written go up, not all of them every tick)
    for i = 0, FN - 1 do
      local f = FL[i + 1]
      if f.life > 0 then
        if not lo then lo = i end; hi = i
        f.life = f.life - dt; f.t = f.t + dt
        local u = f.t/f.max
        local dx, dz = f.x - f.cx, f.z - f.cz
        f.vx = f.vx + -dz*f.curl*dt*2.2; f.vz = f.vz + dx*f.curl*dt*2.2
        f.vy = f.vy + 0.5*dt
        local d = 1 - 0.9*dt
        f.vx = f.vx*d; f.vz = f.vz*d
        f.x = f.x + f.vx*dt; f.y = f.y + f.vy*dt; f.z = f.z + f.vz*dt
        f.rx = f.rx + f.wx*dt; f.ry = f.ry + f.wy*dt; f.rz = f.rz + f.wz*dt
        local b = smoothstep(0.1, 0.6, u)
        local g = opal(f.hue + t*0.15)
        local k = 0.012*b
        ic[i*3 + 1], ic[i*3 + 2], ic[i*3 + 3] = 0.034 + g[1]*k, 0.03 + g[2]*k, 0.022 + g[3]*k
        local sc = f.s*(1 - smoothstep(0.6, 1, u))
        EE:set(f.rx, f.ry, f.rz); QQ:set_from_euler(EE)
        M4:compose(PV:set(f.x, f.y, f.z), QQ, SV:set(sc, sc, sc))
        fmesh:set_matrix_at(i, f.life > 0 and M4 or M4:make_scale(0, 0, 0))
        if not f.puffed and u > 0.6 then
          f.puffed = true
          warp.puff({ x = f.x, y = f.y, z = f.z, vx = f.vx*0.5, vy = 0.35, vz = f.vz*0.5, life = rng.float(0.6, 1.0), s0 = 0.08, s1 = 0.3, amp = 3.6, spin = rng.spread(3) })
        end
      end
    end
    if lo then fmesh.instance_matrix:mark(lo, hi); fmesh.instance_color:mark(lo, hi) end
  end

  local function smoke(p, big)
    big = big or 1
    local x = p.x + rng.spread(0.08)
    local y = p.y + rng.spread(0.04)
    local z = p.z + rng.spread(0.08)
    local vx = rng.spread(0.2)
    local vy = rng.float(0.35, 0.8)
    local vz = rng.spread(0.2)
    local life = rng.float(1.4, 2.4)*big
    local s1 = rng.float(0.6, 0.9)*big
    local amp = rng.float(4.0, 5.2)
    local spin = rng.spread(2.0)
    return warp.puff({ x = x, y = y, z = z, vx = vx, vy = vy, vz = vz, rise = 0.35, drag = 0.6, life = life, s0 = 0.16*big, s1 = s1, amp = amp, spin = spin })
  end
  snakes.on_dissolve = function(s) for _ = 1, 6 do smoke(s.spine[rng.int(0, 6) + 1], 1.3) end end

  local P = { name = 'LEAKAGE', gesture = false }
  function P.scale(p, R_T)
    local L = get_L()
    local far = hyp(L.x - egg.x, L.z - egg.z) + R_T + 0.8
    local k = (p - 1)/5
    reach = 2.6 + k*max(0, far - 2.6)
    rate = 0.22*(p^0.75)*(p >= 6 and 1.6 or 1)
  end
  function P.reach() return reach end
  -- urgent: nil or a set { [snake] = true }
  function P.update(t, dt, on, urgent)
    local L = get_L()
    -- (2026-10-10, the sounds: the leak round his skull while it is his; ONE loop at the snake coming apart most)
    if on and not P.snd then P.snd = AU.loop('leak_whisper', { pos = L }) elseif not on and P.snd then P.snd.stop(); P.snd = nil end
    local most, most_k = nil, 0
    for _, s in ipairs(snakes.S) do
      if s.leak > most_k and s.leak_at and not s.pooled then most, most_k = s, s.leak end
    end
    if most then
      P.snd_s = P.snd_s or AU.loop('leak_snake', { pos = most.spine[most.leak_at + 1] })
      P.snd_s.set_pos(most.spine[most.leak_at + 1]); P.snd_s.set_volume(math.min(1, 0.3 + most_k))
    elseif P.snd_s then P.snd_s.stop(); P.snd_s = nil end
    for _, s in ipairs(snakes.S) do
      if not (s.delay > 0 or s.dying >= 0 or s.burn or s.sink >= 0 or s.fx or s.coil) and not (snakes.held_by_other and snakes.held_by_other(s)) then
        local d = 1e9
        for i = 0, N - 1, 6 do d = min(d, hyp(s.spine[i + 1].x - L.x, s.spine[i + 1].z - L.z)) end
        if on and d < reach then
          if s.leak_at == nil or s.leak <= 0 then
            local bi, bd = 0, 1e9
            for i = 0, N - 1, 2 do local e = hyp(s.spine[i + 1].x - L.x, s.spine[i + 1].z - L.z); if e < bd then bd = e; bi = i end end
            s.leak_at = bi
            -- (2026-10-11, owner: "Snake dissolve sound should play when the dissolve effect starts": here, where the leak
            -- takes hold of it, not when it is all gone)
            AU.play('snake_dissolve', { pos = s.spine[bi + 1], gap = 0.1 })
          end
          local k = 1 - 0.5*d/reach
          s.leak = s.leak + rate*k*dt*((urgent and urgent[s]) and 4 or 1)
          local LEN = snakes.LEN
          local ac = snakes.arc(s.leak_at)
          local ext = max(ac, LEN - ac, 0.5)
          local fr = min(1.12, s.leak*1.12)*ext
          for _, e in ipairs({ ac - fr, ac + fr }) do
            if not (e < 0 or e > LEN) then
              local i = max(0, min(N - 1, jround(snakes.ring_at(e))))
              local p = s.spine[i + 1]
              local r = s.radii[i + 1]; if not r or r == 0 then r = 0.06 end
              for _ = 1, 2 do if rng.next() < 0.3 then flake(p, r) end end
              if rng.next() < 0.4 then smoke(p) end
            end
          end
        elseif s.leak > 0 then
          s.leak = max(0, s.leak - 0.06*dt)
          if s.leak <= 0 then s.leak_at = nil end
        end
      end
    end
    update_streaks(dt); update_rings(dt); update_flakes(t, dt)
    if not on then return end
    lich.head_pos(H)
    if P.snd then P.snd.set_pos(H) end
    emit = emit + dt*(5 + reach*1.2)
    while emit >= 1 do
      emit = emit - 1
      local x = rng.spread(0.06)
      local y = rng.spread(0.05)
      local z = rng.spread(0.06)
      streak_from(H:clone():add(Vector3.new(x, y, z)))
    end
    ring_t = ring_t - dt
    if ring_t <= 0 then ring_t = rng.float(1.6, 2.6); ring_from(L); AU.play('leak_ripple', { pos = L }) end
  end
  return P
end

return LK
