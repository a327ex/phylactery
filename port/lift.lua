--[[
  lift.lua -- the port to Anchor: web/src/lift.js. LIFT AND BURST: he points; the snake is lifted
  by an unseen hand under its middle, writhing, held, swells, and bursts (gore.lua) on his pull
  (the curl); the snakes near it go up with it; a channel (his hand follows them until they burst).
]]
local TM = require('port.three.math')
local U = require('port.util')
local Vector2, Vector3 = TM.Vector2, TM.Vector3
local smoothstep = U.smoothstep
local abs, sin, floor, ceil, max = math.abs, math.sin, math.floor, math.ceil, math.max

local LI = {}
local RISE, HOLD, SWELL, STAGGER = 0.8, 0.4, 0.2, 0.08
local GROUP_R = 1.8
local CURL_LEAD = 0.08
local AFTER = 0.3

function LI.create(ctx)
  local snakes, rng, gore, lich, get_L = ctx.snakes, ctx.rng, ctx.gore, ctx.lich, ctx.get_L
  local N = snakes.RINGS
  local mid, half = floor(N*0.45 + 0.5), N*0.55
  local held, groups = {}, {}
  local AIM, TOWARD = Vector3.new(), Vector3.new()
  local hand_free = false

  local function lift_fx(s, delay, grp)
    local H = rng.float(1.5, 2.0)
    local side = Vector2.new()
    local a, b = s.spine[4 + 1], s.spine[N - 5 + 1]
    side:set(-(a.z - b.z), a.x - b.x):normalize()
    local ph = rng.float(0, 6.28)
    local f
    f = {
      t = -delay, sag = 0, s = s, grp = grp, hide = false,
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

  local function group(n, arm)
    local g = { t = 0, at = RISE + HOLD + SWELL + STAGGER*max(0, n - 1), arm = arm, curled = false, aim = Vector3.new(), aimed = false }
    groups[#groups + 1] = g
    return g
  end
  local function lift(s, delay, grp)
    local f = lift_fx(s, delay, grp)
    if snakes.take(s, f) then held[#held + 1] = f end
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
    local g = group(#all, arm)
    for k, s in ipairs(all) do lift(s, (k - 1)*STAGGER, g) end
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
  return P
end

return LI
