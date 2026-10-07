--[[
  lift.lua -- the port to Anchor: web/src/lift.js. LIFT AND BURST: he points; the snake is lifted
  by an unseen hand under its middle, writhing, held, swells, and bursts (gore.lua) on his pull
  (the curl); the snakes near it go up with it; a channel (his hand follows them until they burst).
  Round 50 (owner: "lifting four snakes should pull them together and then he gores them all at the
  same time"): three or more lifted together (ctx.varied) are drawn into one knot in the air in front
  of him, their middles pressed together, wrung about it, the ends hanging out; then all burst at once.
]]
local TM = require('port.three.math')
local U = require('port.util')
local Vector2, Vector3, Quaternion, Euler = TM.Vector2, TM.Vector3, TM.Quaternion, TM.Euler
local smoothstep = U.smoothstep
local abs, sin, cos, floor, ceil, min, max = math.abs, math.sin, math.cos, math.floor, math.ceil, math.min, math.max

local LI = {}
local RISE, HOLD, SWELL, STAGGER = 0.8, 0.4, 0.2, 0.08
local GROUP_R = 1.8
local CURL_LEAD = 0.08
local AFTER = 0.3
local GATHER, KNOT_HOLD, KNOT_UP, WRING = 0.95, 0.35, 0.15, 1.5
local KNOT_PULL, KNOT_NEAR, KNOT_EGG = 0.45, 1.5, 1.1
local BALL_R, HEAD_OFF, BALL_LAT = 0.3, 0.45, 1.15

function LI.create(ctx)
  local snakes, rng, gore, lich, get_L, cave = ctx.snakes, ctx.rng, ctx.gore, ctx.lich, ctx.get_L, ctx.cave
  local N = snakes.RINGS
  local mid, half = floor(N*0.45 + 0.5), N*0.55
  local LEN_HALF = snakes.LEN*0.5
  local held, groups = {}, {}
  local AIM, TOWARD = Vector3.new(), Vector3.new()
  local hand_free = false
  local knots = 0

  local function lift_fx(s, delay, grp, k)
    local H = rng.float(1.5, 2.0)
    local M0 = s.spine[mid + 1]:clone()             -- (a lifted body no longer crawls: its middle stays over here)
    local side = Vector2.new()
    local a, b = s.spine[4 + 1], s.spine[N - 5 + 1]
    side:set(-(a.z - b.z), a.x - b.x):normalize()
    local ph = rng.float(0, 6.28)
    local f
    f = {
      t = -delay, sag = 0, s = s, grp = grp, hide = false, H = H,
      lift = function(i)
        local e = smoothstep(0, RISE, f.t)
        local d = (i - mid)/half
        return H*e*(1 - 0.5*d*d) + (f.t > RISE and sin(f.t*31 + i*0.7)*0.012*smoothstep(RISE, RISE + HOLD, f.t) or 0)
      end,
      shift = function(i, out)
        local w = smoothstep(0.1, 0.5, f.t)*sin(i*0.3 - f.t*7 + ph)*0.09*(1 - 0.5*smoothstep(RISE, RISE + HOLD, f.t))
        local sw = smoothstep(grp.at - SWELL, grp.at, grp.t)
        local tr = sw*sin(f.t*70 + i*1.3)*0.012*(1 - abs((i - mid)/half))
        out[1] = out[1] + side.x*(w + tr); out[2] = out[2] + tr*0.6; out[3] = out[3] + side.y*(w + tr)
      end,
      radk = function(i) local sw = smoothstep(grp.at - SWELL, grp.at, grp.t); return 1 + sw*0.45*(1 - abs((i - mid)/half)) end,
      -- round 51 (owner, 2026-10-06: "When lifted snakes get together they should curl into a ball sort
      -- of, instead of staying elongated"): each body winds round its own tilted band on a ball (like
      -- yarn), from its middle outward: the middle reaches the ball first, the rest is reeled in after
      -- it; the head stands a little off the ball; the ball turns, tightens and writhes until the burst
      -- round 53 (owner, 2026-10-07: "more irregular instead of a perfect circle, and the movement of entities
      -- there should also follow a better tween method, the ball itself should also float irregularly and move
      -- a bit irregularly too to the sides"): the ball has lumps and squashes and stretches as it goes; its
      -- centre bobs and drifts on uneven waves; and each ring follows its place on a spring of its own (the
      -- middle firm, the ends looser), so the bodies whip in, overshoot a little and settle
      place = grp.knot and function(i, p)
        local K = grp.knot
        local g0 = smoothstep(RISE*0.4, RISE + GATHER, f.t)
        if g0 <= 0 then return end
        local u = snakes.arc(i) - LEN_HALF
        local d = min(1, abs(u)/LEN_HALF)
        local gi = smoothstep(0, 1, g0*1.7 - d*0.7)
        local B = K.band[k]
        local T = grp.t
        local hold = max(0, T - (RISE + GATHER))
        local R = BALL_R*(1 - 0.12*smoothstep(0, KNOT_HOLD + SWELL, hold))*(0.82 + 0.18*d) + 0.028*(k - 1)
        local head = snakes.arc(i) < HEAD_OFF and 0.13*(1 - snakes.arc(i)/HEAD_OFF) or 0
        local phi = B.phi0 + B.dir*u/BALL_R + K.spin*max(0, f.t - RISE*0.4)
        local lat = max(-BALL_LAT, min(BALL_LAT, u/LEN_HALF*BALL_LAT))     -- (pole to pole: it covers the ball)
        local cl, sl, cp, sp = cos(lat), sin(lat), cos(phi), sin(phi)
        local ux = cl*(cp*B.U.x + sp*B.V.x) + sl*B.A.x
        local uy = cl*(cp*B.U.y + sp*B.V.y) + sl*B.A.y
        local uz = cl*(cp*B.U.z + sp*B.V.z) + sl*B.A.z
        -- the lumps (no sphere), then the writhing and the heads standing off it
        local lump = 1
        for _, L in ipairs(K.lumps) do local dd = ux*L[1] + uy*L[2] + uz*L[3]; if dd > 0 then lump = lump + L[4]*dd*dd*dd end end
        R = R*lump + head + 0.014*sin(f.t*8 + i*0.45 + k)
        -- squashing and stretching, slowly; the centre floating on uneven waves
        local P_ = K.ph
        local ex, ey, ez = 1 + 0.15*sin(T*1.3 + P_[1]), 1 + 0.13*sin(T*1.7 + P_[2]), 1 + 0.15*sin(T*1.1 + P_[3])
        local cx = K.c.x + 0.09*sin(T*0.9 + P_[4]) + 0.045*sin(T*2.3 + P_[5])
        local cy = K.c.y + 0.07*sin(T*1.4 + P_[6]) + 0.03*sin(T*3.1 + P_[1])
        local cz = K.c.z + 0.09*sin(T*0.8 + P_[2]) + 0.045*sin(T*2.1 + P_[3])
        local tx = p.x + (cx + ux*R*ex - p.x)*gi
        local ty = p.y + (cy + uy*R*ey - p.y)*gi
        local tz = p.z + (cz + uz*R*ez - p.z)*gi
        -- each ring on its own spring toward that (the ends looser: they whip, overshoot, settle)
        f.rp = f.rp or {}; f.rv = f.rv or {}
        local q, v = f.rp[i + 1], f.rv[i + 1]
        if not q then q = { p.x, p.y, p.z }; v = { 0, 0, 0 }; f.rp[i + 1] = q; f.rv[i + 1] = v end
        local w = 14 - 6*d
        local z2 = 2*0.58*w
        local h = 1/60
        local ax = (tx - q[1])*w*w - v[1]*z2; local ay = (ty - q[2])*w*w - v[2]*z2; local az = (tz - q[3])*w*w - v[3]*z2
        v[1] = v[1] + ax*h; v[2] = v[2] + ay*h; v[3] = v[3] + az*h
        q[1] = q[1] + v[1]*h; q[2] = q[2] + v[2]*h; q[3] = q[3] + v[3]*h
        p.x, p.y, p.z = q[1], q[2], q[3]
      end or nil,
      tick = function(dt)
        f.t = f.t + dt
        f.sag = smoothstep(0, RISE, max(0, f.t))
        if grp.t >= grp.at and not f.hide then
          local L = get_L()
          TOWARD:set(L.x, L.y + 0.4, L.z)
          gore.burst(s, mid, TOWARD)
          f.hide = true
        end
        if f.hide and grp.t >= grp.at + 0.05 then return 'done' end
      end,
    }
    return f
  end

  local function group(n, arm, knot)
    local at = knot and RISE + GATHER + KNOT_HOLD + SWELL + STAGGER*max(0, n - 1) or RISE + HOLD + SWELL + STAGGER*max(0, n - 1)
    local g = { t = 0, at = at, arm = arm, curled = false, aim = Vector3.new(), aimed = false, knot = knot }
    groups[#groups + 1] = g
    return g
  end
  local function lift(s, delay, grp, k)
    local f = lift_fx(s, delay, grp, k)
    if snakes.take(s, f) then held[#held + 1] = f end
  end
  -- the knot's place: pulled in from over their middles to the air in front of him (into the light),
  -- clear of the egg, a little higher than they rise
  local function knot_of(all)
    local L = get_L()
    local c = Vector3.new()
    for _, s in ipairs(all) do c:add(s.spine[mid + 1]) end
    c:multiply_scalar(1/#all)
    local dx, dz = c.x - L.x, c.z - L.z
    local d = js_hypot(dx, dz)
    if d > 1e-3 then local want = max(KNOT_NEAR, d*KNOT_PULL); c.x = L.x + dx/d*want; c.z = L.z + dz/d*want end
    local E = snakes.egg
    local ex, ez = c.x - E.x, c.z - E.z
    local de = js_hypot(ex, ez)
    if de < KNOT_EGG then
      if de < 1e-3 then ex, ez, de = c.x - L.x, c.z - L.z, max(1e-3, js_hypot(c.x - L.x, c.z - L.z)) end
      c.x = E.x + ex/de*KNOT_EGG; c.z = E.z + ez/de*KNOT_EGG
    end
    c.y = cave.ground_y(c.x, c.z) + 1.75 + KNOT_UP
    -- each body's band: a tilted great circle of its own (spread over the ball), its winding way, where it starts
    local band = {}
    -- (the axes spread evenly: a tetrahedron's corners, turned at random; past four, any)
    local TET = { { 1, 1, 1 }, { 1, -1, -1 }, { -1, 1, -1 }, { -1, -1, 1 } }
    local turn = Quaternion.new():set_from_euler(Euler.new(rng.float(0, 6.28), rng.float(0, 6.28), rng.float(0, 6.28)))
    for k = 1, #all do
      local A
      if k <= 4 then A = Vector3.new(TET[k][1], TET[k][2], TET[k][3]):normalize():apply_quaternion(turn)
      else A = Vector3.new(rng.spread(1), rng.spread(1), rng.spread(1)); if A:length_sq() < 1e-4 then A:set(0, 1, 0) end end
      A:normalize()
      local U = Vector3.new():cross_vectors(A, math.abs(A.y) < 0.9 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)):normalize()
      local V = Vector3.new():cross_vectors(A, U):normalize()
      band[k] = { A = A, U = U, V = V, dir = rng.sign(), phi0 = rng.float(0, 6.28) }
    end
    -- (round 53: its lumps, and the phases of its floating and its squash)
    local lumps = {}
    for q = 1, 5 do
      local L = Vector3.new(rng.spread(1), rng.spread(1), rng.spread(1))
      if L:length_sq() < 1e-4 then L:set(1, 0, 0) end
      L:normalize()
      lumps[q] = { L.x, L.y, L.z, rng.float(0.15, 0.4) }
    end
    local ph = {}
    for q = 1, 6 do ph[q] = rng.float(0, 6.28) end
    return { c = c, band = band, spin = rng.sign()*rng.float(0.5, 0.9), lumps = lumps, ph = ph }
  end
  local function includes(list, x) for _, v in ipairs(list) do if v == x then return true end end; return false end

  local P = { name = 'LIFT', gesture = true, cooldown = 6.0 }
  function P.capacity(p) return ceil(p/1.5) end
  function P.aim_ring() return mid end
  function P.cast(targets, from, ring, arm)
    if arm == nil then arm = 1 end
    -- (round 52: a lift already holding snakes keeps them; the neighbours it takes are no one else's)
    if not ctx.varied then held = {} end
    hand_free = false
    local all = {}
    for k, s in ipairs(targets) do all[k] = s end
    for _, s in ipairs(snakes.S) do
      local other = ctx.varied and snakes.taken_by and snakes.taken_by(s)
      if snakes.free(s) and not includes(all, s) and not (other and other ~= 'LIFT') then
        local near = false
        for _, q in ipairs(targets) do if q.spine[mid + 1]:distance_to(s.spine[mid + 1]) < GROUP_R then near = true; break end end
        if near then all[#all + 1] = s end
      end
    end
    local knot = (ctx.varied and #all >= 3) and knot_of(all) or nil
    if knot then knots = knots + 1 end
    local g = group(#all, arm, knot)
    for k, s in ipairs(all) do lift(s, (k - 1)*STAGGER, g, k) end
  end
  function P.update(dt)
    dt = dt or 1/60
    for i = #held, 1, -1 do if held[i].hide then table.remove(held, i) end end
    for i = #groups, 1, -1 do
      local g = groups[i]
      g.t = g.t + dt
      if not g.curled and g.t >= g.at - CURL_LEAD then g.curled = true; lich.curl(g.arm) end
      if g.t > g.at + 0.5 then table.remove(groups, i) end
    end
  end
  function P.let_go() hand_free = true; for _, g in ipairs(groups) do g.curled = true end end
  function P.busy()
    if hand_free then return false end
    if #held > 0 then return true end
    for _, g in ipairs(groups) do if g.t < g.at + AFTER then return true end end
    return false
  end
  function P.aim_point()
    local g
    for _, q in ipairs(groups) do if q.t < q.at + AFTER then g = q; break end end
    if not g then if #held > 0 then return held[1].s.spine[mid + 1] end; return AIM end
    local up = {}
    for _, f in ipairs(held) do if f.grp == g and not f.hide then up[#up + 1] = f end end
    if #up > 0 then
      g.aim:set(0, 0, 0)
      for _, f in ipairs(up) do g.aim:add(f.s.spine[mid + 1]) end
      g.aim:multiply_scalar(1/#up); g.aimed = true
    end
    if g.aimed then AIM:copy(g.aim) end
    return AIM
  end
  function P.extend(more, arm)
    if arm == nil then arm = 1 end
    for _, g in ipairs(groups) do if g.t >= g.at - CURL_LEAD and g.t < g.at + AFTER then return nil end end
    local add = {}
    for _, s in ipairs(more) do if snakes.free(s) then add[#add + 1] = s end end
    if #add == 0 then return nil end
    local g = group(#add, arm)
    for k, s in ipairs(add) do lift(s, (k - 1)*STAGGER, g) end
    return nil
  end
  function P.held_count() return #held end
  function P.knots() return knots end
  return P
end

return LI
