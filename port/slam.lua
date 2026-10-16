--[[
  slam.lua -- the ending's blast in warped air (2026-10-16, Phylactery 19). Owner: "in a final gesture he brings it
  down, as though bringing down gravity/psychic force on all the snakes, they all explode (with downwards force), the
  telekinesis visual effect should also be somewhat visible as a downward force (that then hits the ground and moves to
  the sides) too."

  The game's telekinesis is air that bends the light (warp.lua, the leakage's look), so this is made of the same things:
  streaks of warped air that gather over the egg while his hand is up (slam.gather), fall with his hand, faster and
  faster, onto it (they land at the moment of the blast), then at the blast (slam.hit) rings of warped air that run out
  along the floor and streaks that skim it outward, with puffs rolling after them. Its own draws (U.run_rng(911)):
  nothing else's sequence moves.

  2026-10-16, his "I also didn't see the telekinetic visual, I think here it can be more prismatic and lens transparent
  because the background is all black": each streak also carries a ribbon of glass (port/prism.lua) on the same points,
  SL.GLASS.w times as wide, as strong as SL.GLASS.a of it: seen over the dark, the world undimmed inside it.
]]
local TM = require('port.three.math')
local U = require('port.util')
local Vector3 = TM.Vector3
local smoothstep = U.smoothstep
local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
local sin, cos, min, max, pi = math.sin, math.cos, math.min, math.max, math.pi

local SL = {}
-- the falling column (2026-10-16, his "the rays as they come from above are too regular, should be more irregular and
-- more streaky"): n streaks in clumps (clumps of them round the gather point within r1, each streak within clump_r of
-- its clump; loners anywhere), each from its own height h, its own width (w, thin ones likelier: wpow), its own
-- strength (bright); each starts late by a fraction of the fall (start) and lands a little before the blast (land s),
-- falling at least fall_min s, eased in its own way (u^p: p), slanting (tilt m off the vertical at its top, any way); a streak `len` long that
-- stretches by up to `stretch` as it speeds up (a fall's streak), its top never above where it began
SL.COLUMN = { n = 34, clumps = 5, clump_r = 0.35, loners = 0.25, r1 = 1.1, h = { 1.6, 5.2 }, w = { 0.04, 0.2 }, wpow = 2.2,
  amp = { 4.5, 8.0 }, bright = { 0.35, 1.0 }, start = { 0.0, 0.3 }, land = { -0.03, 0.0 }, fall_min = 0.1, p = { 1.6, 3.2 }, tilt = 0.35,
  len = { 0.4, 1.2 }, stretch = { 0.6, 2.6 }, sway = 0.06 }
-- the floor: rings (count, from-to radius, their times), streaks along it (count, speed, life), puffs
SL.RINGS = { n = 3, r0 = 0.45, r1 = 4.6, T = { 0.85, 1.0, 1.2 }, gap = 0.07, w = 0.26, amp = 6.5, chroma = 1.2 }
SL.SKIM = { n = 22, r0 = 0.55, speed = { 4.5, 7.0 }, life = { 0.45, 0.7 }, len = { 0.5, 0.9 }, w = { 0.1, 0.16 }, amp = { 5.0, 6.5 } }
SL.PUFFS = { n = 14, r0 = 0.7, speed = { 2.2, 3.4 }, life = { 0.6, 0.9 } }
-- the glass on them (port/prism.lua): how much wider than the warped air, how strong (column, rings, skims)
SL.GLASS = { w = { 1.7, 1.0, 1.3 }, a = { 1.0, 0.35, 0.5 } }

function SL.create(ctx)
  local warp, cave, prism = ctx.warp, ctx.cave, ctx.prism
  local rng = U.run_rng(911)
  local K = warp.K
  local column, rings, skims = {}, {}, {}
  local slam = {}
  local clock = 0
  local function glass(s, kind)
    if not prism then return nil end
    return prism.ribbon(s.pts, s.w*SL.GLASS.w[kind], s.ph, kind == 1 and 1 or 0)    -- (the column's: brightest at its head)
  end
  local function done(q) warp.release(q.s); if q.gl then prism.release(q.gl) end end

  -- the column: each streak's foot on the floor round the egg, its head falling from its height to the floor between its
  -- start and its landing (eased in: slow, then fast with his hand coming down), its streak behind (above) it
  function slam.gather(c, T)
    local C = SL.COLUMN
    local cl = {}
    for k = 1, C.clumps do
      local a, r = rng.float(0, 2*pi), C.r1*0.7*math.sqrt(rng.next())
      cl[k] = { x = c.x + cos(a)*r, z = c.z + sin(a)*r }
    end
    for _ = 1, C.n do
      local s = warp.streak()
      if not s then break end
      local x, z
      if rng.next() < C.loners then
        local a, r = rng.float(0, 2*pi), C.r1*math.sqrt(rng.next())
        x, z = c.x + cos(a)*r, c.z + sin(a)*r
      else
        local k = cl[rng.int(1, C.clumps)]
        local a, r = rng.float(0, 2*pi), C.clump_r*math.sqrt(rng.next())
        x, z = k.x + cos(a)*r, k.z + sin(a)*r
      end
      s.w = C.w[1] + (C.w[2] - C.w[1])*rng.next()^C.wpow; s.amp = rng.float(C.amp[1], C.amp[2]); s.chroma = rng.float(0.9, 1.25); s.a = 0
      local t0 = T*rng.float(C.start[1], C.start[2])
      local t1 = math.max(t0 + C.fall_min, T + rng.float(C.land[1], C.land[2]))
      column[#column + 1] = { s = s, x = x, z = z, g = cave.ground_y(x, z) + 0.04, h = c.y + rng.float(C.h[1], C.h[2]),
        len = rng.float(C.len[1], C.len[2]), stretch = rng.float(C.stretch[1], C.stretch[2]), p = rng.float(C.p[1], C.p[2]),
        t0 = t0, t1 = t1, b = rng.float(C.bright[1], C.bright[2]), ta = rng.float(0, 2*pi), tl = C.tilt*rng.next(),
        t = 0, ph = rng.float(0, 2*pi), out = rng.float(0.15, 0.4), a = math.atan(z - c.z, x - c.x), gl = glass(s, 1) }
    end
  end

  local function ring(c, i)
    local s = warp.streak()
    if not s then return end
    local R = SL.RINGS
    s.w = R.w; s.amp = R.amp; s.chroma = R.chroma; s.a = 0
    rings[#rings + 1] = { s = s, c = c, t = -(i - 1)*R.gap, T = R.T[i] or R.T[#R.T], gl = glass(s, 2) }
  end

  -- the blast: rings out along the floor, streaks skimming it outward, puffs rolling after them
  function slam.hit(c)
    local R, SK, PF = SL.RINGS, SL.SKIM, SL.PUFFS
    for i = 1, R.n do ring(c, i) end
    for k = 1, SK.n do
      local s = warp.streak()
      if not s then break end
      local a = (k - 1)/SK.n*2*pi + rng.spread(0.12)
      s.w = rng.float(SK.w[1], SK.w[2]); s.amp = rng.float(SK.amp[1], SK.amp[2]); s.chroma = rng.float(0.9, 1.2); s.a = 0
      skims[#skims + 1] = { s = s, c = c, a = a, sp = rng.float(SK.speed[1], SK.speed[2]), life = rng.float(SK.life[1], SK.life[2]),
        len = rng.float(SK.len[1], SK.len[2]), curl = rng.spread(0.5), t = 0, gl = glass(s, 3) }
    end
    for _ = 1, PF.n do
      local a = rng.float(0, 2*pi)
      local sp = rng.float(PF.speed[1], PF.speed[2])
      local x, z = c.x + cos(a)*PF.r0, c.z + sin(a)*PF.r0
      warp.puff({ x = x, y = cave.ground_y(x, z) + 0.12, z = z, vx = cos(a)*sp, vy = 0.05, vz = sin(a)*sp, drag = 2.2, life = rng.float(PF.life[1], PF.life[2]),
        s0 = 0.18, s1 = 0.55, amp = 4.2, spin = rng.spread(2) })
    end
  end

  function slam.update(dt)
    clock = clock + dt
    for i = #column, 1, -1 do
      local q = column[i]
      q.t = q.t + dt
      local u = clamp((q.t - q.t0)/(q.t1 - q.t0), 0, 1)
      local f = u^q.p                                  -- (eased in: it falls as the hand comes down)
      local head = q.h + (q.g - q.h)*f
      -- (its streak: longer the faster it falls; its top never above where it began)
      local vn = q.p*u^(q.p - 1)
      local tail = min(q.h, head + q.len*(0.3 + 0.7*min(1, (q.t - q.t0)/0.12)) + q.stretch*min(1, vn/2.5))
      local hh = max(1e-3, q.h - q.g)
      for k = 0, K - 1 do
        local w = k/(K - 1)
        local y = tail + (head - tail)*w
        local sw = SL.COLUMN.sway*sin(q.ph + y*1.7)*(1 - f)
        -- (it slants: off its foot by tl at its top, toward ta)
        local sl = q.tl*clamp((y - q.g)/hh, 0, 1)
        -- (at the foot the air spreads: the last part of each streak bends outward as it lands)
        local spread = q.out*smoothstep(0.75, 1, u)*w*w
        local p = q.s.pts[k + 1]
        p:set(q.x + cos(q.a)*(sw + spread) + cos(q.ta)*sl, max(q.g, y), q.z + sin(q.a)*(sw + spread) + sin(q.ta)*sl)
      end
      local after = q.t - q.t1
      local live = q.t >= q.t0 and smoothstep(q.t0, q.t0 + 0.06, q.t) or 0
      q.s.a = q.b*live*(after > 0 and 1 - smoothstep(0, 0.12, after) or 1)
      if q.gl then q.gl.a = q.s.a*SL.GLASS.a[1] end
      if after >= 0.12 then done(q); table.remove(column, i) end
    end
    for i = #rings, 1, -1 do
      local q = rings[i]
      q.t = q.t + dt
      local u = q.t/q.T
      if u >= 0 then
        local R = SL.RINGS
        local r = R.r0 + (R.r1 - R.r0)*(1 - (1 - min(1, u))^2.2)
        for k = 0, K - 1 do
          local a = k/(K - 1)*2*pi
          local p = q.s.pts[k + 1]
          p:set(q.c.x + sin(a)*r, 0, q.c.z + cos(a)*r)
          p.y = cave.ground_y(p.x, p.z) + 0.07
        end
        q.s.a = smoothstep(0, 0.06, u)*(1 - smoothstep(0.55, 1, u))
        if q.gl then q.gl.a = q.s.a*SL.GLASS.a[2] end
      end
      if u >= 1 then done(q); table.remove(rings, i) end
    end
    for i = #skims, 1, -1 do
      local q = skims[i]
      q.t = q.t + dt
      local u = min(1, q.t/q.life)
      local head = SL.SKIM.r0 + q.sp*q.life*(1 - (1 - u)^2)
      local tail = max(SL.SKIM.r0, head - q.len)
      for k = 0, K - 1 do
        local d = tail + (head - tail)*k/(K - 1)
        local a = q.a + q.curl*(d - SL.SKIM.r0)*0.25
        local p = q.s.pts[k + 1]
        local x, z = q.c.x + cos(a)*d, q.c.z + sin(a)*d
        p:set(x, cave.ground_y(x, z) + 0.1 + 0.04*(d - SL.SKIM.r0)*u, z)
      end
      q.s.a = smoothstep(0, 0.06, q.t)*(1 - smoothstep(0.6, 1, u))
      if q.gl then q.gl.a = q.s.a*SL.GLASS.a[3] end
      if u >= 1 then done(q); table.remove(skims, i) end
    end
    if prism then prism.update(clock) end
  end
  function slam.busy() return #column + #rings + #skims > 0 end
  return slam
end

return SL
