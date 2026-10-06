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
local Vector2, Vector3 = TM.Vector2, TM.Vector3
local smoothstep = U.smoothstep
local abs, sin, cos, floor, ceil, min, max = math.abs, math.sin, math.cos, math.floor, math.ceil, math.min, math.max

local LI = {}
local RISE, HOLD, SWELL, STAGGER = 0.8, 0.4, 0.2, 0.08
local GROUP_R = 1.8
local CURL_LEAD = 0.08
local AFTER = 0.3
local GATHER, KNOT_HOLD, KNOT_UP, WRING = 0.95, 0.35, 0.15, 1.5
local KNOT_PULL, KNOT_NEAR, KNOT_EGG = 0.45, 1.5, 1.1

function LI.create(ctx)
  local snakes, rng, gore, lich, get_L, cave = ctx.snakes, ctx.rng, ctx.gore, ctx.lich, ctx.get_L, ctx.cave
  local N = snakes.RINGS
  local mid, half = floor(N*0.45 + 0.5), N*0.55
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
      -- the knot: the middle drawn all the way to it, the rest less, wrung about it (more toward the ends)
      place = grp.knot and function(i, p)
        local K = grp.knot
        local g = smoothstep(RISE*0.5, RISE + GATHER, f.t)
        if g <= 0 then return end
        local d = min(1, abs(i - mid)/half)
        local w = 1 - 0.3*(d^1.4)
        local o = K.off[k]
        p.x = p.x + (K.c.x + o[1] - M0.x)*g*w
        p.y = p.y + (K.c.y - (M0.y + f.H))*g*w
        p.z = p.z + (K.c.z + o[2] - M0.z)*g*w
        local ang = (g*WRING + K.turn*max(0, grp.t - (RISE + GATHER)))*K.dir*d
        local rx, rz = p.x - K.c.x, p.z - K.c.z
        local sq = 1 - 0.3*g*d
        local ca, sa = cos(ang), sin(ang)
        p.x = K.c.x + (rx*ca - rz*sa)*sq; p.z = K.c.z + (rx*sa + rz*ca)*sq
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
    local off, a0 = {}, rng.float(0, 6.28)
    for k = 1, #all do local a = a0 + (k - 1)*6.2832/#all; off[k] = { math.cos(a)*0.07, math.sin(a)*0.07 } end
    return { c = c, off = off, dir = rng.sign(), turn = rng.float(0.8, 1.3) }
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
