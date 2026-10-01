--[[
  coil.lua -- the port to Anchor: web/src/coil.js. The ending: the egg's surface and normals, where
  each arriving snake coils (KNOT: a band at its own tilt over the others; STACKED: tight rows
  from the bottom up), and how much of the egg is covered. Directions and points are {x, y, z}.
  coverage() finds the covered samples through a grid over the body segments (the same answer as
  coil.js's search over every segment: a sample is covered when any segment passes within reach).
]]
local CL = {}
local sqrt, abs, sin, cos, asin, acos, atan2, ceil, floor, max, min, huge, pi = math.sqrt, math.abs, math.sin, math.cos, math.asin, math.acos, math.atan, math.ceil, math.floor, math.max, math.min, math.huge, math.pi

CL.COIL_MODES = { 'KNOT: EACH AT ITS OWN TILT, OVER THE OTHERS', 'STACKED: TIGHT ROWS FROM THE BOTTOM UP' }

local EGG_S = 0.8
CL.OFF = 0.056
local OFF = CL.OFF
local SPACING = 0.152
local MAX_TILT = 1.1
local E_VIS = -0.9

local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
local hyp3 = js_hypot                 -- Math.hypot (V8's)
local function norm(v) local l = hyp3(v[1], v[2], v[3]); if l == 0 then l = 1 end; return { v[1]/l, v[2]/l, v[3]/l } end
local function dot(a, b) return a[1]*b[1] + a[2]*b[2] + a[3]*b[3] end
local function cross(a, b) return { a[2]*b[3] - a[3]*b[2], a[3]*b[1] - a[1]*b[3], a[1]*b[2] - a[2]*b[1] } end
CL.dot = dot

-- the shell's profile as a table by elevation from the centre
local PROF = {}
do
  local function taper(qy) return 1 - 0.14*clamp(qy/0.5, 0, 1) + 0.03*clamp(-qy/0.5, 0, 1) end
  local function P(qy) return sqrt(max(0, 0.25 - qy*qy))*0.78*taper(qy)*EGG_S, qy*EGG_S end
  local NT = 720
  for i = 0, NT do
    local qy = -0.5 + i/NT
    local h, y = P(qy)
    local ah, ay = P(max(-0.5, qy - 1e-4))
    local bh, by = P(min(0.5, qy + 1e-4))
    local th, ty = bh - ah, by - ay
    local l = hyp3(ty, th); if l == 0 then l = 1 end
    PROF[#PROF + 1] = { e = atan2(y, h), h = h, y = y, nh = ty/l, ny = -th/l }
  end
end
local NPROF = #PROF
local PT = { h = 0, y = 0, nh = 0, ny = 0 }
local function profile(e)
  if e <= PROF[1].e then return PROF[1] end
  if e >= PROF[NPROF].e then return PROF[NPROF] end
  local lo, hi = 0, NPROF - 1                  -- 0-based like coil.js
  while hi - lo > 1 do
    local m = (lo + hi) >> 1
    if PROF[m + 1].e < e then lo = m else hi = m end
  end
  local A, B = PROF[lo + 1], PROF[hi + 1]
  local d = B.e - A.e; if d == 0 then d = 1 end
  local f = (e - A.e)/d
  PT.h = A.h + (B.h - A.h)*f; PT.y = A.y + (B.y - A.y)*f; PT.nh = A.nh + (B.nh - A.nh)*f; PT.ny = A.ny + (B.ny - A.ny)*f
  return PT
end

function CL.create(o)
  local C, ground_y, rng, len = o.centre, o.ground_y, o.rng, o.len
  local function surface(d, out_p, out_n)
    local hl = hyp3(d[1], d[3])
    local ux, uz
    if hl > 1e-6 then ux, uz = d[1]/hl, d[3]/hl else ux, uz = 1, 0 end
    local p = profile(asin(clamp(d[2], -1, 1)))
    out_p[1] = C[1] + ux*p.h; out_p[2] = C[2] + p.y; out_p[3] = C[3] + uz*p.h
    local nl = hyp3(p.nh, p.ny); if nl == 0 then nl = 1 end
    out_n[1] = ux*p.nh/nl; out_n[2] = p.ny/nl; out_n[3] = uz*p.nh/nl
  end
  local TP, TN = { 0, 0, 0 }, { 0, 0, 0 }
  local function lifted(d, off, out)
    surface(d, TP, TN)
    out[1] = TP[1] + TN[1]*off; out[2] = TP[2] + TN[2]*off; out[3] = TP[3] + TN[3]*off
    return out
  end

  local function base_dir(hx, hz, body_h)
    local ux, uz = hx - C[1], hz - C[3]
    local l = hyp3(ux, uz); if l == 0 then l = 1 end
    ux = ux/l; uz = uz/l
    local best, bd = nil, huge
    local q = { 0, 0, 0 }
    local e = -1.45
    while e < 0.3 do
      local d = { ux*cos(e), sin(e), uz*cos(e) }
      lifted(d, OFF, q)
      local want = ground_y(q[1], q[3]) + body_h
      local err = abs(q[2] - want)
      if err < bd then bd = err; best = d end
      e = e + 0.01
    end
    return best
  end

  -- coverage samples: a Fibonacci sphere, weighted by the shell area each stands for
  local NS, SMP = 900, {}
  do
    local ga = pi*(3 - sqrt(5))
    for i = 0, NS - 1 do
      local y = 1 - 2*(i + 0.5)/NS
      local r = sqrt(1 - y*y)
      local a = i*ga
      local d = { cos(a)*r, y, sin(a)*r }
      if not (asin(y) < E_VIS) then
        local p, n = { 0, 0, 0 }, { 0, 0, 0 }
        surface(d, p, n)
        local rr = hyp3(p[1] - C[1], p[2] - C[2], p[3] - C[3])
        SMP[#SMP + 1] = { d = d, p = p, w = rr*rr/max(0.3, dot(d, n)) }
      end
    end
  end
  local NSMP = #SMP
  local W_ALL = 0
  for k = 1, NSMP do W_ALL = W_ALL + SMP[k].w end

  -- which samples fall in which cell: a sample is checked only against the segments whose
  -- reach overlaps its cell
  local GC = 0.08
  local function gkey(ix, iy, iz) return (ix + 512)*1048576 + (iy + 512)*1024 + (iz + 512) end
  local cell_of = {}
  for k = 1, NSMP do
    local p = SMP[k].p
    cell_of[k] = gkey(floor(p[1]/GC), floor(p[2]/GC), floor(p[3]/GC))
  end
  -- bodies: { foot = { {x,y,z} ... }, rad = { ... }, on = { bool ... } } (1-based rings)
  local function coverage(bodies, out_mask)
    local grid = {}
    for bi, b in ipairs(bodies) do
      local F, R, O = b.foot, b.rad, b.on
      for i = 1, #F - 1 do
        if O[i] and O[i + 1] then
          local a, c = F[i], F[i + 1]
          local rr = max(R[i], R[i + 1])*0.95
          local x0, x1 = floor((min(a[1], c[1]) - rr)/GC), floor((max(a[1], c[1]) + rr)/GC)
          local y0, y1 = floor((min(a[2], c[2]) - rr)/GC), floor((max(a[2], c[2]) + rr)/GC)
          local z0, z1 = floor((min(a[3], c[3]) - rr)/GC), floor((max(a[3], c[3]) + rr)/GC)
          for ix = x0, x1 do for iy = y0, y1 do for iz = z0, z1 do
            local key = gkey(ix, iy, iz)
            local list = grid[key]
            if not list then list = {}; grid[key] = list end
            list[#list + 1] = bi; list[#list + 1] = i
          end end end
        end
      end
    end
    local wc = 0
    for k = 1, NSMP do
      local s = SMP[k]
      local p = s.p
      local hit = false
      local list = grid[cell_of[k]]
      if list then
        for q = 1, #list, 2 do
          local b = bodies[list[q]]
          local i = list[q + 1]
          local F, R = b.foot, b.rad
          local a, c = F[i], F[i + 1]
          local ex, ey, ez = c[1] - a[1], c[2] - a[2], c[3] - a[3]
          local L2 = ex*ex + ey*ey + ez*ez; if L2 == 0 then L2 = 1e-9 end
          local t = ((p[1] - a[1])*ex + (p[2] - a[2])*ey + (p[3] - a[3])*ez)/L2
          t = clamp(t, 0, 1)
          local dx, dy, dz = a[1] + ex*t - p[1], a[2] + ey*t - p[2], a[3] + ez*t - p[3]
          local r = (R[i] + (R[i + 1] - R[i])*t)*0.95
          if dx*dx + dy*dy + dz*dz < r*r then hit = true; break end
        end
      end
      if out_mask then out_mask[k] = hit and 1 or 0 end
      if hit then wc = wc + s.w end
    end
    return wc/W_ALL
  end

  -- bands
  local function frame(a)
    local t = abs(a[2]) < 0.9 and { 0, 1, 0 } or { 1, 0, 0 }
    local e1 = norm(cross(t, a))
    local e2 = cross(a, e1)
    return e1, e2
  end
  local function dir_at(a, e1, e2, th, ph)
    local s, c, cp, sp = sin(th), cos(th), cos(ph), sin(ph)
    return { a[1]*c + (e1[1]*cp + e2[1]*sp)*s, a[2]*c + (e1[2]*cp + e2[2]*sp)*s, a[3]*c + (e1[3]*cp + e2[3]*sp)*s }
  end
  local function arcs_of(dirs)
    local arc = { 0 }
    local q0, q1 = { 0, 0, 0 }, { 0, 0, 0 }
    lifted(dirs[1], OFF, q0)
    for i = 2, #dirs do
      lifted(dirs[i], OFF, q1)
      arc[i] = arc[i - 1] + hyp3(q1[1] - q0[1], q1[2] - q0[2], q1[3] - q0[3])
      q0[1], q0[2], q0[3] = q1[1], q1[2], q1[3]
    end
    return arc
  end
  local function mean_rho(a, e1, e2)
    local s, q = 0, { 0, 0, 0 }
    for k = 0, 23 do
      lifted(dir_at(a, e1, e2, pi/2, k/24*pi*2), OFF, q)
      local v = { q[1] - C[1], q[2] - C[2], q[3] - C[3] }
      local al = dot(v, a)
      s = s + sqrt(max(0, dot(v, v) - al*al))
    end
    return s/24
  end
  local function helix(a, e1, e2, th0, th1, phi0, sigma, Phi)
    local n = max(8, ceil(Phi/0.03))
    local dirs = {}
    for k = 0, n do
      local f = k/n
      dirs[k + 1] = dir_at(a, e1, e2, th0 + (th1 - th0)*f, phi0 + sigma*Phi*f)
    end
    return dirs
  end
  local function knot_band(a, d_b, heading)
    local e1, e2 = frame(a)
    local rho = mean_rho(a, e1, e2)
    local W = SPACING/(rho + 0.02)
    local Phi, beta, th0, th1, phi0, sigma, dirs, arc = 4*pi, 0, 0, 0, 0, 1, nil, nil
    local tb = acos(clamp(dot(d_b, a), -1, 1))
    local da = dot(d_b, a)
    local v = { d_b[1] - a[1]*da, d_b[2] - a[2]*da, d_b[3] - a[3]*da }
    phi0 = atan2(dot(v, e2), dot(v, e1))
    for _ = 1, 6 do
      beta = W*Phi/(4*pi)
      th0 = tb > pi/2 and pi/2 + beta or pi/2 - beta
      th1 = tb > pi/2 and pi/2 - beta or pi/2 + beta
      dirs = helix(a, e1, e2, th0, th1, phi0, sigma, Phi)
      arc = arcs_of(dirs)
      Phi = Phi*(len/arc[#arc])
    end
    local d0 = dirs[1]
    local function tan(s) local q = dir_at(a, e1, e2, th0, phi0 + s*0.05); return { q[1] - d0[1], q[2] - d0[2], q[3] - d0[3] } end
    local way = { d0[1] - d_b[1], d0[2] - d_b[2], d0[3] - d_b[3] }
    if hyp3(way[1], way[2], way[3]) < 0.08 then way = { heading[1], 0, heading[2] } end
    sigma = dot(tan(1), way) >= dot(tan(-1), way) and 1 or -1
    dirs = helix(a, e1, e2, th0, th1, phi0, sigma, Phi)
    arc = arcs_of(dirs)
    local sb = sin(beta*0.92)
    return { axis = a, sigma = sigma, rho = rho, dirs = dirs, arc = arc, beta = beta, turns = Phi/(2*pi), covers = function(d) return abs(dot(d, a)) < sb end }
  end

  local UPA = { 0, 1, 0 }
  local UE1, UE2 = frame(UPA)
  local STACK
  do
    local rho = 0.36
    local W = SPACING/(rho + 0.02)
    local TH_BOT, TH_TOP = pi/2 - E_VIS + 0.05, 0.3
    local Phi = (TH_BOT - TH_TOP)/W*2*pi
    local dirs = helix(UPA, UE1, UE2, TH_BOT, TH_TOP, 0, 1, Phi)
    local arc = arcs_of(dirs)
    STACK = { dirs = dirs, arc = arc, total = arc[#arc], W = W }
  end
  local stack_next = 0
  local function stacked_band(d_b)
    local k = stack_next
    local s0 = k*len*0.96
    if s0 + len > STACK.total + 0.3 then return nil end
    stack_next = stack_next + 1
    local A = STACK.arc
    local i0, i1 = nil, nil
    for i = 1, #A do if A[i] >= s0 then i0 = i; break end end
    if not i0 then i0 = #A end
    for i = 1, #A do if A[i] >= s0 + len then i1 = i; break end end
    if not i1 then i1 = #A end
    local piece = {}
    for i = i0, i1 do piece[#piece + 1] = STACK.dirs[i] end
    local function az(d) return atan2(d[3], d[1]) end
    local r = az(d_b) - az(piece[1])
    local cr, sr = cos(r), sin(r)
    local dirs = {}
    for i, d in ipairs(piece) do dirs[i] = { d[1]*cr - d[3]*sr, d[2], d[1]*sr + d[3]*cr } end
    local arc = arcs_of(dirs)
    local t0, t1 = acos(clamp(dirs[1][2], -1, 1)), acos(clamp(dirs[#dirs][2], -1, 1))
    return { axis = UPA, sigma = 1, rho = 0.3, dirs = dirs, arc = arc, stacked = k,
      covers = function(d) local t = acos(clamp(d[2], -1, 1)); return t <= t0 + STACK.W*0.5 and t >= t1 - STACK.W*0.5 end }
  end

  local function pick_axis(covered_count)
    local best, bs = nil, -huge
    local sb = sin(0.36*0.92)
    for _ = 1, 72 do
      local ct = 1 - rng.next()*(1 - cos(MAX_TILT))
      local st = sqrt(1 - ct*ct)
      local ph = rng.next()*pi*2
      local a = { cos(ph)*st, ct, sin(ph)*st }
      local sc = 0
      for k = 1, NSMP do
        if not (abs(dot(SMP[k].d, a)) >= sb) then
          local n = covered_count[k]
          sc = sc + SMP[k].w*(n == 0 and 1 or 0.12/n)
        end
      end
      sc = sc*(1 + 0.08*rng.next())
      if sc > bs then bs = sc; best = a end
    end
    return best
  end

  local function stem(d_b, d_s)
    local ang = acos(clamp(dot(d_b, d_s), -1, 1))
    local n = max(1, ceil(ang/0.04))
    local out = {}
    for k = 0, n do
      local f = k/n
      if ang < 1e-4 then out[#out + 1] = { d_b[1], d_b[2], d_b[3] }
      else
        local s = sin(ang)
        local wa, wb = sin((1 - f)*ang)/s, sin(f*ang)/s
        out[#out + 1] = norm({ d_b[1]*wa + d_s[1]*wb, d_b[2]*wa + d_s[2]*wb, d_b[3]*wa + d_s[3]*wb })
      end
    end
    return out
  end

  local function plan(mode, d_b, heading, planned, covered)
    local band = mode == 1 and stacked_band(d_b) or nil
    if not band then
      local cnt = {}
      for k = 1, NSMP do
        local c = 0
        if covered and covered[k] ~= 0 and covered[k] ~= nil then c = c + 1 end
        local d = SMP[k].d
        for _, b in ipairs(planned) do if b.covers(d) then c = c + 1 end end
        cnt[k] = c
      end
      band = knot_band(pick_axis(cnt), d_b, heading)
    end
    local st = stem(d_b, band.dirs[1])
    return { band = band, stem = st, stem_arc = arcs_of(st) }
  end

  local coil = { C = C, surface = surface, lifted = lifted, base_dir = base_dir, plan = plan, coverage = coverage, samples = SMP, stack = STACK }
  function coil.reset() stack_next = 0 end
  function coil.stack_used() return stack_next end
  return coil
end

return CL
