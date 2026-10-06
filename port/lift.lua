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
      place = grp.knot and function(i, p)
        local K = grp.knot
        local g0 = smoothstep(RISE*0.4, RISE + GATHER, f.t)
        if g0 <= 0 then return end
        local u = snakes.arc(i) - LEN_HALF
        local d = min(1, abs(u)/LEN_HALF)
        local gi = smoothstep(0, 1, g0*1.7 - d*0.7)
        if gi <= 0 then return end
        local B = K.band[k]
        local hold = max(0, grp.t - (RISE + GATHER))
        local R = BALL_R*(1 - 0.12*smoothstep(0, KNOT_HOLD + SWELL, hold))*(0.82 + 0.18*d) + 0.028*(k - 1)
        local head = snakes.arc(i) < HEAD_OFF and 0.13*(1 - snakes.arc(i)/HEAD_OFF) or 0
        R = R + head + 0.012*sin(f.t*8 + i*0.45 + k)
        local phi = B.phi0 + B.dir*u/BALL_R + K.spin*max(0, f.t - RISE*0.4)
        local lat = max(-BALL_LAT, min(BALL_LAT, u/LEN_HALF*BALL_LAT))     -- (pole to pole: it covers the ball)
        local cl, sl, cp, sp = cos(lat), sin(lat), cos(phi), sin(phi)
        local x = K.c.x + R*(cl*(cp*B.U.x + sp*B.V.x) + sl*B.A.x)
        local y = K.c.y + R*(cl*(cp*B.U.y + sp*B.V.y) + sl*B.A.y)
        local z = K.c.z + R*(cl*(cp*B.U.z + sp*B.V.z) + sl*B.A.z)
        p.x = p.x + (x - p.x)*gi; p.y = p.y + (y - p.y)*gi; p.z = p.z + (z - p.z)*gi
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
    return { c = c, band = band, spin = rng.sign()*rng.float(0.5, 0.9) }
  end
  local function includes(list, x) for _, v in ipairs(list) do if v == x then return true end end; return false end

  local P = { name = 'LIFT', gesture = true, cooldown = 6.0 }
  function P.capacity(p) return ceil(p/1.5) end
  function P.aim_ring() return mid end
  function P.cast(targets, from, ring, arm)
    if arm == nil then arm = 1 end
    held = {}; hand_free = false
    local all = {}
    for k, s in ipairs(targets) do all[k] = s end
    for _, s in ipairs(snakes.S) do
      if snakes.free(s) and not includes(all, s) then
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
