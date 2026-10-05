--[[
  way.lua -- round 45, the way in (owner, 2026-10-04): "The start of the game should be in a little
  grotto before the tunnel, and the tunnel should be longer and contain each item in sequence. The
  items are gathered automatically as you pass by each and are added to your inventory on the top
  right. When the item is gotten, it shows it on the model viewer and prompts you to press an
  'accept artifact' button."

  The final room's tunnel goes on past its old end (z -46; its cap comes off, cave.drop_tunnel_cap)
  along a winding path to a little grotto where he wakes. Built here at load, the way cave.js built
  the tunnel: rings of the same arch roughened by the same noise (the first ring IS the old end's,
  so the join is exact), the floor a strip of the same ground (cave.ground_y, the one he floats on),
  the room's own materials and textures on continuous UVs (2 m units, as tools/cave_look.py's);
  plinths of rock for the six objects; light from point lights the room lends while he is out here
  (the fire's, idle until the fight) and a little baked bounce round them; a crack of daylight in the
  grotto's roof. Fixed cameras (as the Resident Evil games): one for the grotto, one per object,
  one for the old tunnel's far half; then the room's tunnel camera.

  Each object waits on its plinth in the order of the round 39 walk (the mask nearest the grotto,
  the lens nearest the room); within 2.1 m of one, or past it (none can be skipped), he stops, turns,
  reaches, it rises to his hand (round 39's taking), and the model viewer opens on it with its text
  and ACCEPT ARTIFACT; accepted, the power is his and its icon fills its slot.
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local U = require('port.util')
local NAV = require('port.nav')
local ITM = require('port.items')
local Vector3, Quaternion, Euler = TM.Vector3, TM.Quaternion, TM.Euler
local smoothstep, clamp, lerp = U.smoothstep, U.clamp, U.lerp
local sqrt, abs, sin, cos, atan2, floor, ceil, min, max, pi, exp = math.sqrt, math.abs, math.sin, math.cos, math.atan, math.floor, math.ceil, math.min, math.max, math.pi, math.exp

local WAY = {}
local TILE = 2.0                       -- the cave's UV unit (u = metres/2; the textures' repeat scales it)
local W0, H0 = 2.7 + 0.9, 4.2 + 0.6    -- cave.js's tunnel arch (half width, height)
local RING = 18

-- the path (x, z) from the old tunnel's end on, away from the room: s = 0 at z -46, growing toward
-- the grotto at its far end
WAY.CTRL = { { 0, -46 }, { 0, -50.5 }, { 2.5, -57 }, { 8.5, -63.5 }, { 12.5, -71 }, { 12, -80 }, { 7.5, -87.5 },
  { 1.5, -94 }, { -2, -101.5 }, { -1.5, -108 }, { 0, -114 } }
-- the objects, in the order he meets them coming from the grotto (powers.ALL's: mask, hand,
-- lodestone, orbs, gem, lens): how far from the grotto's end (m), which side (+1: his right as he
-- walks toward the room), the plinth's height, and each one's lamp (colour, intensity, reach)
WAY.STATIONS = {
  { from_end = 21, side = -1, h = 0.62, lamp = { { 1.0, 0.46, 0.16 }, 2.4, 6.5 } },   -- the mask: ember
  { from_end = 31, side = 1, h = 0.78, lamp = { { 0.92, 0.86, 0.74 }, 1.8, 6.0 } },   -- the hand: pale
  { from_end = 41, side = -1, h = 0.48, lamp = { { 0.95, 0.55, 0.34 }, 1.6, 6.0 } },  -- the lodestone: rust
  { from_end = 51, side = 1, h = 0.55, lamp = { { 0.42, 0.95, 0.85 }, 1.5, 6.0 } },   -- the orbs: sea-glass
  { from_end = 61, side = -1, h = 0.7, lamp = { { 0.95, 0.9, 1.0 }, 1.9, 6.0 } },     -- the gem: white
  { from_end = 71, side = 1, h = 0.66, lamp = { { 1.0, 0.82, 0.55 }, 2.1, 6.5 } },    -- the lens: sun
}
WAY.BULB = 14                          -- the grotto: the last 14 m of the path, swollen

-- ------------------------------------------------------------------ the path, sampled
local function build_path()
  local P = WAY.CTRL
  local dense = {}
  local n = #P
  local function at(i) return P[max(1, min(n, i))] end
  for i = 1, n - 1 do
    local p0, p1, p2, p3 = at(i - 1), at(i), at(i + 1), at(i + 2)
    for k = 0, 39 do
      local t = k/40
      local t2, t3 = t*t, t*t*t
      local x = 0.5*((2*p1[1]) + (-p0[1] + p2[1])*t + (2*p0[1] - 5*p1[1] + 4*p2[1] - p3[1])*t2 + (-p0[1] + 3*p1[1] - 3*p2[1] + p3[1])*t3)
      local z = 0.5*((2*p1[2]) + (-p0[2] + p2[2])*t + (2*p0[2] - 5*p1[2] + 4*p2[2] - p3[2])*t2 + (-p0[2] + 3*p1[2] - 3*p2[2] + p3[2])*t3)
      dense[#dense + 1] = { x, z }
    end
  end
  dense[#dense + 1] = { P[n][1], P[n][2] }
  -- resampled by arc length every 0.1 m
  local acc, S = 0, {}
  local STEP = 0.1
  S[0] = { x = dense[1][1], z = dense[1][2] }
  local want = STEP
  for i = 2, #dense do
    local ax, az, bx, bz = dense[i - 1][1], dense[i - 1][2], dense[i][1], dense[i][2]
    local l = js_hypot(bx - ax, bz - az)
    while acc + l >= want and l > 0 do
      local f = (want - acc)/l
      S[#S + 1] = { x = ax + (bx - ax)*f, z = az + (bz - az)*f }
      want = want + STEP
    end
    acc = acc + l
  end
  local NS = #S
  for k = 0, NS do
    local a, b = S[max(0, k - 1)], S[min(NS, k + 1)]
    local tx, tz = b.x - a.x, b.z - a.z
    local l = js_hypot(tx, tz)
    S[k].tx, S[k].tz = tx/l, tz/l
  end
  -- the first stretch runs straight down -z as the old tunnel did
  S[0].tx, S[0].tz = 0, -1
  return S, NS*STEP, STEP
end

function WAY.create(ctx)
  local R, cave, lich, mover, items, inspect, fx, warp, powers = ctx.R, ctx.cave, ctx.lich, ctx.mover, ctx.items, ctx.inspect, ctx.fx, ctx.warp, ctx.powers
  local ground_y = cave.ground_y
  local rng = U.make_rng(451)
  local S_, L, STEP = build_path()
  local NS = #S_
  local function at(s)
    if s < 0 then return 0, -46 - s, 0, -1 end        -- (back up the old tunnel, straight down -z)
    s = min(s, L)
    local f = s/STEP
    local k = min(NS - 1, floor(f))
    local a, b = S_[k], S_[k + 1]
    local u = f - k
    return a.x + (b.x - a.x)*u, a.z + (b.z - a.z)*u, a.tx + (b.tx - a.tx)*u, a.tz + (b.tz - a.tz)*u
  end
  -- the side vector (his right as he walks toward the room = the old tunnel's +x at s 0)
  local function side_of(tx, tz) local l = js_hypot(tx, tz); return -tz/l, tx/l end
  -- the floor along the way, smoothed (the tube's base follows it)
  local function g_smooth(s)
    local acc = 0
    for _, d in ipairs({ -2, -1, 0, 1, 2 }) do
      local x, z = at(s + d)
      acc = acc + ground_y(x, z)
    end
    return acc/5
  end
  local G0 = g_smooth(0)
  local function yb(s) return g_smooth(s) - G0 end
  local BULB0 = L - WAY.BULB
  local function kw(s) return (1 + 0.75*smoothstep(BULB0, BULB0 + 5, s))*(1 - 0.78*smoothstep(L - 3.6, L, s)) end
  local function kh(s) return (1 + 0.32*smoothstep(BULB0, BULB0 + 5, s))*(1 - 0.55*smoothstep(L - 3.6, L, s)) end
  local function rough(s) return 0.42 + 0.2*smoothstep(BULB0, BULB0 + 4, s) end
  -- the nearest s to a point (searched near the last answer, then everywhere if it is far)
  local last_k = 0
  local function s_at(x, z)
    local best, bk = math.huge, last_k
    local function scan(k0, k1)
      for k = max(0, k0), min(NS, k1) do
        local p = S_[k]
        local d = (p.x - x)^2 + (p.z - z)^2
        if d < best then best = d; bk = k end
      end
    end
    scan(last_k - 60, last_k + 60)
    if best > 9 then scan(0, NS) end
    last_k = bk
    return bk*STEP, sqrt(best)
  end

  -- ------------------------------------------------------------------ geometry
  local function new_buf() return { p = {}, n = {}, uv = {}, gi = {} } end
  local walls, floorb, rocks = new_buf(), new_buf(), new_buf()
  local function push_tri(b, a, c, d, ua, uc, ud, inward)
    -- one flat triangle (a, c, d points; u* uvs); inward(cx, cy, cz) = a point its face must face
    local e1x, e1y, e1z = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local e2x, e2y, e2z = d[1] - a[1], d[2] - a[2], d[3] - a[3]
    local nx, ny, nz = e1y*e2z - e1z*e2y, e1z*e2x - e1x*e2z, e1x*e2y - e1y*e2x
    local l = sqrt(nx*nx + ny*ny + nz*nz)
    if l < 1e-10 then return end
    nx, ny, nz = nx/l, ny/l, nz/l
    if inward then
      local mx, my, mz = (a[1] + c[1] + d[1])/3, (a[2] + c[2] + d[2])/3, (a[3] + c[3] + d[3])/3
      local ix, iy, iz = inward(mx, my, mz)
      if nx*(ix - mx) + ny*(iy - my) + nz*(iz - mz) < 0 then c, d, uc, ud = d, c, ud, uc; nx, ny, nz = -nx, -ny, -nz end
    end
    for _, q in ipairs({ { a, ua }, { c, uc }, { d, ud } }) do
      local P, UV = q[1], q[2]
      b.p[#b.p + 1] = P[1]; b.p[#b.p + 1] = P[2]; b.p[#b.p + 1] = P[3]
      b.n[#b.n + 1] = nx; b.n[#b.n + 1] = ny; b.n[#b.n + 1] = nz
      b.uv[#b.uv + 1] = UV[1]; b.uv[#b.uv + 1] = UV[2]
    end
  end

  -- the tube: rings of cave.js's arch along the path
  local ring_s = { 0 }
  do
    local s = 0
    while s < L - 0.6 do s = s + (s > BULB0 and 0.95 or 1.25); ring_s[#ring_s + 1] = min(s, L - 0.05) end
  end
  local rings = {}
  for ri, s in ipairs(ring_s) do
    local cx, cz, tx, tz = at(s)
    local sx, sz = side_of(tx, tz)
    local zz = -46 - s
    local ring = {}
    for j = 0, RING do
      local a = lerp(-0.12, 1.12, j/RING)*pi
      local x0l, y0l = cos(a)*W0, max(sin(a), -0.35)*H0
      local d = 1 + (U.fbm3(x0l*0.4, y0l*0.4, zz*0.25, 51) - 0.5)*rough(s) + (U.noise3(j*0.9, 2.2, zz*0.6, 53) - 0.5)*0.12
      local xl = x0l*d*kw(s)
      local yl = y0l > 0 and y0l*d*kh(s) or y0l - 0.6
      local wx, wy, wz = cx + sx*xl, yb(s) + yl, cz + sz*xl
      if ri == 1 then
        -- the old tunnel's end ring as tools/tunnel_mouth.py left it (its sides tucked under the floor)
        wx, wz, wy = xl, -46, yl
        if j <= 3 then wx, wy = 2.8, 1.5841 elseif j >= 15 then wx, wy = -2.8, 1.2695 end
      else
        local fh = ground_y(wx, wz)
        if wy < fh + 0.3 then
          wy = fh - 0.15
          if ri <= 3 then
            -- (out of the old ring's pinch over two rings)
            local lim = 2.8 + (ri - 1)*0.45
            local lat = (wx - cx)*sx + (wz - cz)*sz
            if abs(lat) > lim then local k = lim/abs(lat); wx, wz = cx + (wx - cx)*k, cz + (wz - cz)*k end
          end
        end
      end
      ring[j] = { wx, wy, wz, u = a*(W0*kw(s) + H0*kh(s))/2/TILE, v = zz/TILE }
    end
    ring.s, ring.cx, ring.cz, ring.yb = s, cx, cz, yb(s)
    rings[ri] = ring
  end
  for ri = 1, #rings - 1 do
    local r0, r1 = rings[ri], rings[ri + 1]
    local sm = (r0.s + r1.s)/2
    local mx, mz = at(sm)
    local axis_y = yb(sm) + 1.4*kh(sm)
    local inward = function() return mx, axis_y, mz end
    for j = 0, RING - 1 do
      local a, b, c, d = r0[j], r0[j + 1], r1[j + 1], r1[j]
      push_tri(walls, a, c, b, { a.u, a.v }, { c.u, c.v }, { b.u, b.v }, inward)
      push_tri(walls, a, d, c, { a.u, a.v }, { d.u, d.v }, { c.u, c.v }, inward)
    end
  end
  do
    -- the grotto's far end: a fan to a point inside
    local e = rings[#rings]
    local cx, cz = at(L)
    local c = { cx, e.yb + 1.0, cz }
    local ix_, iz_ = at(L - 2)
    local inward = function() return ix_, e.yb + 1.6, iz_ end
    for j = 0, RING - 1 do
      push_tri(walls, c, e[j], e[j + 1], { c[1]/TILE, c[2]/TILE }, { e[j][1]/TILE, e[j][2]/TILE }, { e[j + 1][1]/TILE, e[j + 1][2]/TILE }, inward)
    end
  end

  -- the floor: the room's lattice (0.7 m from x -21, z -47) carried on past the old tunnel's end,
  -- each cell kept within reach of the way (wider in the grotto); jittered inside, as the room's
  local CELL, FX0, FZ0 = 0.7, -21, -47
  local keep = {}
  local imin, imax, jmax = math.huge, -math.huge, 0
  for k = 0, NS, 3 do
    local s = k*STEP
    local p = S_[k]
    local r = 4.8*kw(s) + 0.4
    local i0, i1 = floor((p.x - r - FX0)/CELL), ceil((p.x + r - FX0)/CELL)
    local j0, j1 = floor((FZ0 - (p.z + r))/CELL), ceil((FZ0 - (p.z - r))/CELL)
    for j = max(0, j0), j1 do for i = i0, i1 do
      local x, z = FX0 + (i + 0.5)*CELL, FZ0 - (j + 0.5)*CELL
      if (x - p.x)^2 + (z - p.z)^2 < r*r then
        keep[j*100000 + i] = true
        imin, imax, jmax = min(imin, i), max(imax, i), max(jmax, j)
      end
    end end
  end
  local function hj(i, j, s) local h = U.hash and U.hash(i, j, s) or ((sin(i*127.1 + j*311.7 + s*74.7)*43758.5453) % 1); return h end
  local function fv(i, j)
    local x, z = FX0 + i*CELL, FZ0 - j*CELL
    if j > 0 then
      x = x + (hj(i, j, 61) - 0.5)*CELL*0.55
      z = z + (hj(i, j, 67) - 0.5)*CELL*0.55
    end
    return { x, ground_y(x, z), z }
  end
  local up = function(x, y, z) return x, y + 10, z end
  for j = 0, jmax do for i = imin, imax do
    if keep[j*100000 + i] then
      local a, b, c, d = fv(i, j), fv(i + 1, j), fv(i + 1, j + 1), fv(i, j + 1)
      local function uv(q) return { q[1]/TILE, q[3]/TILE } end
      push_tri(floorb, a, b, c, uv(a), uv(b), uv(c), up)
      push_tri(floorb, a, c, d, uv(a), uv(c), uv(d), up)
    end
  end end

  -- rock: a convex lump (an icosahedron, displaced), flat-shaded; flat = cut level at that height
  local function lump(cx, cy, cz, rx, ry, rz, seed, flat_top)
    local t = (1 + sqrt(5))/2
    local V = { { -1, t, 0 }, { 1, t, 0 }, { -1, -t, 0 }, { 1, -t, 0 }, { 0, -1, t }, { 0, 1, t }, { 0, -1, -t }, { 0, 1, -t }, { t, 0, -1 }, { t, 0, 1 }, { -t, 0, -1 }, { -t, 0, 1 } }
    local F = { { 1, 12, 6 }, { 1, 6, 2 }, { 1, 2, 8 }, { 1, 8, 11 }, { 1, 11, 12 }, { 2, 6, 10 }, { 6, 12, 5 }, { 12, 11, 3 }, { 11, 8, 7 }, { 8, 2, 9 },
      { 4, 10, 5 }, { 4, 5, 3 }, { 4, 3, 7 }, { 4, 7, 9 }, { 4, 9, 10 }, { 5, 10, 6 }, { 3, 5, 12 }, { 7, 3, 11 }, { 9, 7, 8 }, { 10, 9, 2 } }
    -- one subdivision
    local cache, VV = {}, {}
    for i, v in ipairs(V) do local l = sqrt(v[1]^2 + v[2]^2 + v[3]^2); VV[i] = { v[1]/l, v[2]/l, v[3]/l } end
    local function mid(a, b)
      local k = a < b and a*1000 + b or b*1000 + a
      if cache[k] then return cache[k] end
      local p, q = VV[a], VV[b]
      local m = { (p[1] + q[1])/2, (p[2] + q[2])/2, (p[3] + q[3])/2 }
      local l = sqrt(m[1]^2 + m[2]^2 + m[3]^2)
      VV[#VV + 1] = { m[1]/l, m[2]/l, m[3]/l }
      cache[k] = #VV
      return #VV
    end
    local FF = {}
    for _, f in ipairs(F) do
      local a, b, c = f[1], f[2], f[3]
      local ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
      FF[#FF + 1] = { a, ab, ca }; FF[#FF + 1] = { b, bc, ab }; FF[#FF + 1] = { c, ca, bc }; FF[#FF + 1] = { ab, bc, ca }
    end
    local W = {}
    for i, v in ipairs(VV) do
      local d = 1 + (U.fbm3(v[1]*1.3 + seed, v[2]*1.3, v[3]*1.3, 71) - 0.5)*0.55
      local y = cy + v[2]*ry*d
      if flat_top and y > flat_top then y = flat_top + (y - flat_top)*0.06 end
      W[i] = { cx + v[1]*rx*d, y, cz + v[3]*rz*d }
    end
    local inward = function() return cx, cy - 5, cz end    -- (faces out: away from a point below, swapped below)
    for _, f in ipairs(FF) do
      local a, b, c = W[f[1]], W[f[2]], W[f[3]]
      -- planar UVs on the face's dominant axis
      local e1x, e1y, e1z = b[1] - a[1], b[2] - a[2], b[3] - a[3]
      local e2x, e2y, e2z = c[1] - a[1], c[2] - a[2], c[3] - a[3]
      local nx, ny, nz = abs(e1y*e2z - e1z*e2y), abs(e1z*e2x - e1x*e2z), abs(e1x*e2y - e1y*e2x)
      local function uv(q) if ny >= nx and ny >= nz then return { q[1]/TILE, q[3]/TILE } elseif nx >= nz then return { q[3]/TILE, q[2]/TILE } end; return { q[1]/TILE, q[2]/TILE } end
      local out = function(mx, my, mz) return 2*mx - cx, 2*my - cy, 2*mz - cz end
      push_tri(rocks, a, b, c, uv(a), uv(b), uv(c), out)
    end
  end

  -- the stations: where each object waits, on its plinth
  local ST = {}
  for i, st in ipairs(WAY.STATIONS) do
    local s = L - st.from_end
    local cx, cz, tx, tz = at(s)
    local sx, sz = side_of(tx, tz)
    local off = 2.05*st.side
    local px, pz = cx + sx*off, cz + sz*off
    local gy = ground_y(px, pz)
    local top = gy + st.h
    lump(px, gy + st.h*0.35, pz, 0.62, st.h*0.7 + 0.15, 0.58, i*3.7, top)
    ST[i] = { i = i - 1, s = s, side = st.side, x = px, z = pz, top = top, lamp = st.lamp, cx = cx, cz = cz, sx = sx, sz = sz, tx = tx, tz = tz }
  end
  -- boulders against the walls between them (they block him too)
  local BLOCKS = {}
  for k = 1, 16 do
    local s = 4 + (k - 1)*(L - 10)/15 + rng.float(-1.5, 1.5)
    local cx, cz, tx, tz = at(s)
    local sx, sz = side_of(tx, tz)
    local sd = rng.float(0, 1) < 0.5 and -1 or 1
    local w = 3.05*kw(s) + rng.float(-0.2, 0.3)
    local x, z = cx + sx*sd*w, cz + sz*sd*w
    local r = rng.float(0.45, 1.15)
    local rx, rz = r*rng.float(0.9, 1.4), r*rng.float(0.9, 1.3)
    lump(x, ground_y(x, z) + r*0.15, z, rx, r*rng.float(0.6, 1.0), rz, k*5.1 + 40, nil)
    BLOCKS[#BLOCKS + 1] = { x, z, max(rx, rz)*0.85 + 0.25 }
  end
  -- the grotto's own rocks
  for k = 1, 7 do
    local s = L - rng.float(2.5, WAY.BULB - 2)
    local cx, cz, tx, tz = at(s)
    local sx, sz = side_of(tx, tz)
    local sd = k % 2 == 0 and -1 or 1
    local w = 4.4*kw(s)*rng.float(0.85, 1.05)
    local x, z = cx + sx*sd*w, cz + sz*sd*w
    local r = rng.float(0.7, 1.6)
    local rx, rz = r*rng.float(1.0, 1.5), r*rng.float(1.0, 1.4)
    lump(x, ground_y(x, z) + r*0.1, z, rx, r*rng.float(0.6, 1.1), rz, k*7.3 + 90, nil)
    BLOCKS[#BLOCKS + 1] = { x, z, max(rx, rz)*0.85 + 0.25 }
  end

  -- ------------------------------------------------------------------ light
  -- the grotto: a crack of daylight high in its roof, its light falling on the floor where he wakes
  local SPAWN_S = L - 5.2
  local gcx, gcz, gtx, gtz = at(L - 6.2)
  local gsx, gsz = side_of(gtx, gtz)
  local crack = { x = gcx + gsx*1.1, z = gcz + gsz*1.1 }
  crack.y = yb(L - 6.2) + H0*kh(L - 6.2)*0.97
  local LIGHTS = {}
  LIGHTS[1] = { x = crack.x, y = ground_y(crack.x, crack.z) + 3.3, z = crack.z, col = { 0.95, 0.9, 0.8 }, I = 2.6, r = 9.5, decay = 1.1 }
  for i, st in ipairs(ST) do
    -- each object's lamp: a little above it and toward the way
    local lx, lz = st.x - st.sx*st.side*0.7, st.z - st.sz*st.side*0.7
    LIGHTS[i + 1] = { x = lx, y = st.top + 1.25, z = lz, col = st.lamp[1], I = st.lamp[2]*1.15, r = st.lamp[3] + 2.5, decay = 1.25 }
  end
  -- the bake: bounce round each light (no occlusion: the way has no corner between a lamp and its
  -- walls), and almost nothing elsewhere
  local function bake(b)
    local p, n, gi = b.p, b.n, b.gi
    for v = 0, #p//3 - 1 do
      local x, y, z = p[v*3 + 1], p[v*3 + 2], p[v*3 + 3]
      local nx, ny, nz = n[v*3 + 1], n[v*3 + 2], n[v*3 + 3]
      local r, g, bl = 0.0016, 0.0012, 0.0008
      for _, lt in ipairs(LIGHTS) do
        local dx, dy, dz = lt.x - x, lt.y - y, lt.z - z
        local d = sqrt(dx*dx + dy*dy + dz*dz)
        if d < lt.r*1.4 then
          local c = max(0, (nx*dx + ny*dy + nz*dz)/max(d, 1e-4))*0.6 + 0.4
          local f = lt.I*0.0032*c*(1 - smoothstep(0, lt.r*1.4, d))^2/(1 + d*d*0.15)
          r = r + lt.col[1]*f; g = g + lt.col[2]*f; bl = bl + lt.col[3]*f
        end
      end
      gi[v*3 + 1], gi[v*3 + 2], gi[v*3 + 3] = r, g, bl
    end
  end
  bake(walls); bake(floorb); bake(rocks)

  local group = T.Group.new()
  group.name = 'way'
  R.world_scene:add(group)
  local function mesh_of(b, mat, name)
    local g = T.BufferGeometry.new()
    g.name = name
    g:set_attribute('position', T.BufferAttribute.new(b.p, 3))
    g:set_attribute('normal', T.BufferAttribute.new(b.n, 3))
    g:set_attribute('uv', T.BufferAttribute.new(b.uv, 2))
    g:set_attribute('gi', T.BufferAttribute.new(b.gi, 3))
    local m = T.Mesh.new(g, mat)
    m.name = name
    m.cast_shadow = true; m.receive_shadow = true
    group:add(m)
    return m
  end
  local Mc = cave.M
  local wall_m = mesh_of(walls, Mc.wall, 'way.walls')
  local floor_m = mesh_of(floorb, Mc.floor, 'way.floor')
  local rock_m = mesh_of(rocks, Mc.rock, 'way.rocks')
  cave.drop_tunnel_cap()

  -- the crack: a sliver of sky (unlit, bright: the bloom takes it) and dust turning in its light
  do
    local g = T.BufferGeometry.new()
    local P, N = {}, {}
    local len, wid = 1.3, 0.12
    local ax, az = gtx, gtz
    local pts = {}
    for k = 0, 8 do
      local u = k/8 - 0.5
      local w = wid*(1 - (2*u)^2)*(0.6 + 0.4*sin(k*1.7))
      pts[#pts + 1] = { crack.x + ax*u*len + gsx*w, crack.z + az*u*len + gsz*w, crack.x + ax*u*len - gsx*w, crack.z + az*u*len - gsz*w }
    end
    for k = 1, #pts - 1 do
      local a, b = pts[k], pts[k + 1]
      local y = crack.y
      for _, tri in ipairs({ { a[1], a[2], a[3], a[4], b[3], b[4] }, { a[1], a[2], b[3], b[4], b[1], b[2] } }) do
        for q = 1, 6, 2 do P[#P + 1] = tri[q]; P[#P + 1] = y; P[#P + 1] = tri[q + 1]; N[#N + 1] = 0; N[#N + 1] = -1; N[#N + 1] = 0 end
      end
    end
    g:set_attribute('position', T.BufferAttribute.new(P, 3))
    g:set_attribute('normal', T.BufferAttribute.new(N, 3))
    local m = MAT.MeshStandardMaterial.new({ name = 'snakes.eye', color = 0x000000, roughness = 1, metalness = 0 })
    m.emissive:set_rgb(7.5, 7.0, 6.0)
    m.side = MAT.DoubleSide
    local mm = T.Mesh.new(g, m)
    mm.name = 'way.crack'
    mm.cast_shadow = false; mm.receive_shadow = false
    group:add(mm)
  end
  local DUST = 70
  local dust_geo = T.BufferGeometry.new()
  local dpos, dcol = T.float_attr(DUST, 3), T.float_attr(DUST, 3)
  dust_geo:set_attribute('position', dpos)
  dust_geo:set_attribute('color', dcol)
  local dust_pts = T.Points.new(dust_geo, MAT.PointsMaterial.new({ name = 'cave.dust', size = 1, size_attenuation = false, vertex_colors = true,
    transparent = true, blending = MAT.AdditiveBlending, depth_write = false }))
  dust_pts.frustum_culled = false
  group:add(dust_pts)
  local dust = {}
  local floor_c = ground_y(crack.x, crack.z)
  for i = 1, DUST do dust[i] = { h = rng.float(0.2, crack.y - floor_c), a = rng.float(0, 6.283), r = sqrt(rng.next())*0.55, v = rng.float(0.03, 0.1), w = rng.float(0.05, 0.25), b = rng.float(0.4, 1) } end

  -- the room lends its point lights while he is out here (three.js compiled the programs for nine;
  -- the fire lights none before the fight): the old tunnel's two lamps stay game.lua's
  local pl = {}
  R.world_scene:traverse(function(o) if o.is_point_light then pl[#pl + 1] = o end end)
  local lent = {}
  for k = 1, #LIGHTS do
    local l = pl[k + 2]
    if l then
      lent[k] = { l = l, keep = { position = l.position:clone(), color = l.color:clone(), intensity = l.intensity, distance = l.distance, decay = l.decay } }
      local lt = LIGHTS[k]
      l.position:set(lt.x, lt.y, lt.z); l.color:set_rgb(lt.col[1], lt.col[2], lt.col[3]); l.intensity = lt.I; l.distance = lt.r; l.decay = lt.decay
    end
  end

  -- ------------------------------------------------------------------ cameras
  local CAMS = {}
  -- (a camera's height: under the arch's lowest likely ceiling there, the noise at its lowest)
  local function cam_y(x, z, want)
    local s, lat = s_at(x, z)
    local fl = ground_y(x, z)
    local top = yb(s) + H0*kh(s)*0.8*sqrt(max(0.05, 1 - (lat/(W0*kw(s)*0.82))^2))
    return min(fl + want, top - 0.45)
  end
  do
    local s0 = L - WAY.BULB
    -- the grotto: from its mouth, high, looking back in at where he wakes
    local ex, ez, etx, etz = at(s0 + 1.2)
    local esx, esz = side_of(etx, etz)
    local sx_, sz_ = at(SPAWN_S - 1.5)
    CAMS[#CAMS + 1] = { name = 'THE GROTTO', from = s0 - 2.5, to = L + 1,
      eye = { ex + esx*1.9, cam_y(ex + esx*1.9, ez + esz*1.9, 3.4), ez + esz*1.9 }, tgt = { sx_, ground_y(sx_, sz_) + 0.6, sz_ }, fov = 58 }
    for i, st in ipairs(ST) do
      -- each object's: ahead of it toward the room, on the far side of the way, looking back at it
      -- and the way he comes
      local cs = st.s - 7.5
      local cx, cz, ctx, ctz = at(cs)
      local csx, csz = side_of(ctx, ctz)
      local ex2, ez2 = cx - csx*st.side*1.5, cz - csz*st.side*1.5
      local eye = { ex2, cam_y(ex2, ez2, 2.5), ez2 }
      local ax, az = at(st.s + 2.5)
      local tgt = { (st.x*0.6 + ax*0.4), st.top*0.6 + (ground_y(ax, az) + 0.8)*0.4, (st.z*0.6 + az*0.4) }
      local prev = ST[i - 1]
      CAMS[#CAMS + 1] = { name = ITM.ITEMS[i].name, from = st.s - 4.5, to = prev and (prev.s - 4.5) or (s0 - 2.5), eye = eye, tgt = tgt, fov = 52, station = i }
    end
    -- the old tunnel's far half: from part way down it, looking back at the bend
    CAMS[#CAMS + 1] = { name = 'THE OLD TUNNEL', from = -16, to = ST[#ST].s - 4.5, eye = { -1.5, ground_y(-1.5, -31) + 2.3, -31 }, tgt = { 0.4, ground_y(0, -46) + 0.6, -47 }, fov = 50 }
  end
  -- where he is along the whole way: s here, or (in the old tunnel, z > -46) negative: -(z + 46)
  local function route_s(x, z)
    if z > -46 then return -(z + 46) end
    return (s_at(x, z))
  end

  -- ------------------------------------------------------------------ where he can go
  local nav
  do
    local x0, x1, z0, z1 = math.huge, -math.huge, -46, -2
    for k = 0, NS, 5 do local p = S_[k]; x0 = min(x0, p.x - 9); x1 = max(x1, p.x + 9); z0 = min(z0, p.z - 9) end
    nav = NAV.build({ geo = cave.rock_geo, ground_y = ground_y, x0 = floor(x0), x1 = ceil(x1), z0 = floor(z0), z1 = z1 })
    local cell = 0.2
    local nx = floor((ceil(x1) - floor(x0))/cell + 0.5)
    local ok = {}
    local function stamp(px, pz, r)
      local i0, i1 = floor((px - r - floor(x0))/cell), ceil((px + r - floor(x0))/cell)
      local j0, j1 = floor((pz - r - floor(z0))/cell), ceil((pz + r - floor(z0))/cell)
      for j = j0, j1 do for i = i0, i1 do
        local x, z = floor(x0) + (i + 0.5)*cell, floor(z0) + (j + 0.5)*cell
        if (x - px)^2 + (z - pz)^2 < r*r then ok[j*nx + i] = true end
      end end
    end
    for k = 0, NS, 2 do
      local s = k*STEP
      local p = S_[k]
      stamp(p.x, p.z, (s > BULB0 and 1.9 + 2.5*smoothstep(BULB0, BULB0 + 5, s)*(1 - smoothstep(L - 4.5, L - 1.5, s)) or 1.9))
    end
    local function walkable(x, z)
      if z > -46.4 then return abs(x) <= 1.9 end
      local i, j = floor((x - floor(x0))/cell), floor((z - floor(z0))/cell)
      return ok[j*nx + i] == true
    end
    nav.block(function(x, z)
      if not walkable(x, z) then return true end
      for _, st in ipairs(ST) do if (x - st.x)^2 + (z - st.z)^2 < 0.85*0.85 then return true end end
      for _, b in ipairs(BLOCKS) do if (x - b[1])^2 + (z - b[2])^2 < b[3]*b[3] then return true end end
      return false
    end)
    nav.finish()
  end

  -- ------------------------------------------------------------------ the objects, waiting
  local SIZES = ITM.SIZES
  local display = {}
  for k, st in ipairs(ST) do
    local i0 = st.i
    local wi = items.W[i0 + 1]
    if i0 == 1 then ITM.set_hand_material(items.opts.hand_mat) end
    local g = wi.make()
    g.visible = true
    local kk = wi.it.fixed_k or SIZES[items.opts.size + 1].k*(wi.it.floor_mul or 1)
    local d = { i = i0, g = g, k = kk, at = Vector3.new(st.x, st.top, st.z), s = st.s, state = 'waiting', t = 0, base_q = Quaternion.new(), st = st, lamp = LIGHTS[k + 1] }
    -- facing the way he comes (the camera that watches it is toward the room: half way between)
    local face = atan2(-st.sx*st.side, -st.sz*st.side) + st.side*0.5
    if i0 == 0 then d.base_q:set_from_euler(Euler.new(-0.32, face, 0, 'YXZ')); d.at.y = st.top + 0.2*kk   -- the mask: upright, leaning back
    elseif i0 == 1 then d.base_q:set_from_euler(Euler.new(0, face, 0, 'YXZ')); d.at.y = st.top + 0.16*kk
    elseif i0 == 2 then d.at.y = st.top + 0.42
    elseif i0 == 3 then d.at.y = st.top + 0.34
    elseif i0 == 4 then d.at.y = st.top + 0.07*kk
    elseif i0 == 5 then d.base_q:set_from_euler(Euler.new(-0.25, face, 0, 'YXZ')); d.at.y = st.top + 0.33   -- the lens: upright, tipped back
    end
    g.scale:set_scalar(kk)
    g.position:copy(d.at)
    g.quaternion:copy(d.base_q)
    -- the traced stones (the gem, the orbs) light themselves from a sun: here, their lamp
    local function lamp_sun(m)
      local prev = m.on_before_render
      local U2 = m.material.user_data.U
      local wp = Vector3.new()
      m.on_before_render = function(self, r, c)
        if prev then prev(self, r, c) end
        local lp = d.lamp
        wp:set_from_matrix_position(self.matrix_world)
        U2.uSunDir.value:set(lp.x - wp.x, lp.y - wp.y, lp.z - wp.z):normalize()
        U2.uSunCol.value:set(lp.col[1]*14, lp.col[2]*14, lp.col[3]*14)
        U2.uLit.value = 1
      end
    end
    if wi.orbs then
      d.orbs = {}
      for _, ix in ipairs(ITM.X().world[4].orbs) do local m = g.children[ix + 1]; d.orbs[#d.orbs + 1] = m; m.user_data.r = m.user_data.r or m.scale.x; lamp_sun(m) end
      g.scale:set_scalar(1)
    end
    if i0 == 4 then lamp_sun(g.children[1]) end
    R.world_scene:add(g)
    display[k] = d
  end
  local function orbs_pose(d, t, k)
    for j, m in ipairs(d.orbs) do
      local a = t*(0.35 + 0.08*j)*((j % 2 == 0) and -1 or 1) + j*1.9
      local rad = (0.03 + 0.05*(j - 1))*k
      local tilt = ({ 0.2, -0.5, 0.7, -0.3, 0.45 })[j]
      local x, z = cos(a)*rad, sin(a)*rad
      m.position:set(x, sin(t*0.7 + j)*0.02*k + z*cos(tilt), z*sin(tilt))      -- (the group's children)
      m.scale:set_scalar(m.user_data.r*k)
    end
  end
  local function idle(d, t)
    local g = d.g
    if d.i == 2 then
      -- the lodestone floats over its plinth, turning slowly in its own field
      g.position:set(d.at.x, d.at.y + sin(t*0.8)*0.05, d.at.z)
      g.rotation:set(sin(t*0.31)*0.4, t*0.22, cos(t*0.27)*0.3)
    elseif d.i == 3 then
      g.position:set(d.at.x, d.at.y, d.at.z)
      orbs_pose(d, t, d.k)
    elseif d.i == 4 then
      g.position:copy(d.at)
      g.rotation:set(0.15, t*0.12, 0.08)
    else
      g.position:copy(d.at)
      g.quaternion:copy(d.base_q)
    end
  end

  -- ------------------------------------------------------------------ taking one (round 39's)
  local WS = { zone = 1, taking = nil, after = nil, t = 0, collected = {}, cut = false }
  local function gaze_to(p)
    local Lp = mover.p
    local yaw = mover.yaw()
    local dx, dz = p.x - Lp.x, p.z - Lp.z
    local a = atan2(dx, dz) - yaw
    a = atan2(sin(a), cos(a))
    local h = js_hypot(dx, dz)
    local pt = atan2(-(p.y - (Lp.y + 0.5)), max(0.2, h))
    return a, pt
  end
  local FLY = 1.15
  local function begin_take(d)
    d.state = 'rising'; d.t = 0
    d.from = d.g.position:clone()
    WS.taking = d
    for _ = 1, 6 do
      warp.puff({ x = d.at.x + rng.spread(0.15), y = d.at.y + rng.spread(0.1), z = d.at.z + rng.spread(0.15), vx = rng.spread(0.3), vy = rng.float(0.1, 0.5), vz = rng.spread(0.3),
        drag = 2.0, life = rng.float(0.4, 0.7), s0 = 0.1, s1 = 0.35, amp = 3, spin = rng.spread(3) })
    end
  end
  local tip = Vector3.new()
  local function take_tick(d, dt)
    d.t = d.t + dt
    local u = smoothstep(0.25, FLY, d.t)
    lich.fingertip(1, tip)
    d.g.position:copy(d.from):lerp(tip, u)
    d.g.position.y = d.g.position.y + sin(u*pi)*0.25
    d.scale = 1 - 0.55*u
    if d.orbs then orbs_pose(d, WS.t, d.k*d.scale) else d.g.scale:set_scalar(d.k*d.scale) end
    if d.t > FLY then
      d.state = 'held'; d.g.visible = false
      if d.orbs then for _, m in ipairs(d.orbs) do m.visible = false end end
      WS.collected[d.i] = true
      ITM.ITEMS[d.i + 1].build = true
      if inspect then inspect.open(d.i, { accept = true }) end
      WS.after = d
    end
  end

  -- ------------------------------------------------------------------ the tick
  local sun_keep = { I = cave.sun.intensity, shafts = R.params.shafts.on }
  local function zone_of(s)
    for k, c in ipairs(CAMS) do if s >= c.from and s < c.to then return k end end
    return nil
  end
  function WS.tick(t, dt)
    WS.t = t
    local Lp = mover.p
    local s = route_s(Lp.x, Lp.z)
    WS.s = s
    local z = zone_of(s)
    if z ~= WS.zone then WS.zone = z; WS.cut = true end
    -- out here the room's sun would light the rock from outside its shadow map: it waits
    local far = z ~= nil and CAMS[z].name ~= 'THE OLD TUNNEL'
    cave.sun.intensity = far and 0 or sun_keep.I
    R.params.shafts.on = (not far) and sun_keep.shafts
    for _, d in ipairs(display) do
      if d.state == 'waiting' then
        idle(d, t)
        if not WS.taking and not WS.after and (js_hypot(Lp.x - d.at.x, Lp.z - d.at.z) < 2.1 or (s < d.s - 1.0 and s > d.s - 30)) then begin_take(d) end
      elseif d.state == 'rising' then
        take_tick(d, dt)
      end
    end
    -- him: while one rises he turns to it and reaches for it
    local m = mover.motion
    if WS.taking and WS.taking.state == 'rising' then
      local d = WS.taking
      mover.face.on = true
      mover.face.yaw = atan2(d.g.position.x - Lp.x, d.g.position.z - Lp.z)
      mover.face.half = 0.08
      m.gaze_w = 0.9
      m.gaze, m.gaze_p = gaze_to(d.g.position)
      local w = smoothstep(0, 0.35, d.t)*(1 - smoothstep(FLY - 0.1, FLY, d.t))
      m.point = { w = w*w*(3 - 2*w), arm = 1, x = d.g.position.x, y = d.g.position.y, z = d.g.position.z }
    elseif WS.taking then
      WS.taking = nil
      mover.face.on = false
      m.gaze_w = 0
      m.point = nil
    end
    -- the dust in the crack's light
    local pa, ca = dpos.array, dcol.array
    for i = 1, DUST do
      local q = dust[i]
      q.h = q.h - q.v*dt; q.a = q.a + q.w*dt
      if q.h < 0.15 then q.h = crack.y - floor_c - 0.2 end
      local o = (i - 1)*3
      pa[o + 1] = crack.x + cos(q.a)*q.r; pa[o + 2] = floor_c + q.h; pa[o + 3] = crack.z + sin(q.a)*q.r
      local tw = 0.6 + 0.4*sin(t*1.7 + i*1.3)
      local k = q.b*tw*0.5
      ca[o + 1] = 1.4*k; ca[o + 2] = 1.3*k; ca[o + 3] = 1.1*k
    end
    dpos.needs_update = true; dcol.needs_update = true
  end
  -- the model viewer put away after ACCEPT ARTIFACT: the power is his
  function WS.after_accept()
    local d = WS.after
    if not d then return nil end
    WS.after = nil
    powers.set(d.i, true)
    return d.i
  end
  function WS.busy() return WS.taking ~= nil or WS.after ~= nil end
  function WS.rig()
    local c = CAMS[WS.zone or 1]
    if not c then return nil end
    return c.eye, c.tgt, c.fov, c.name
  end
  function WS.in_way() local z = WS.zone; return z ~= nil end
  -- back as they were: the lights the room lent, its sun
  function WS.leave()
    for _, e in pairs(lent) do
      local l, k = e.l, e.keep
      l.position:copy(k.position); l.color:copy(k.color); l.intensity = k.intensity; l.distance = k.distance; l.decay = k.decay
    end
    lent = {}
    cave.sun.intensity = sun_keep.I
    R.params.shafts.on = sun_keep.shafts
  end
  -- testing: start before object `upto` (0-based; 6 = past them all, in the old tunnel), the ones
  -- before it already his
  function WS.reset(upto)
    WS.collected = {}
    for _, d in ipairs(display) do
      local had = d.i < upto
      d.state = had and 'held' or 'waiting'
      d.g.visible = not had
      if d.orbs then for _, m in ipairs(d.orbs) do m.visible = not had end end
      d.scale = 1
      if not d.orbs then d.g.scale:set_scalar(d.k) end
      WS.collected[d.i] = had or nil
      ITM.ITEMS[d.i + 1].build = had
      powers.set(d.i, had)
    end
    WS.taking = nil; WS.after = nil
    local s = upto >= #ST and -6 or (ST[upto + 1].s + 6.5)
    if upto == 0 then s = SPAWN_S end
    local x, z, tx, tz
    if s < 0 then x, z, tx, tz = 0, -46 - s, 0, 1 else x, z, tx, tz = at(s) end
    return x, z, atan2(-tx, -tz)
  end
  -- (a map of the way for checking: the path, stations, cameras, lights, zones)
  function WS.map_json()
    local t = { path = {}, st = {}, cams = {}, lights = {}, L = L }
    for k = 0, NS, 5 do t.path[#t.path + 1] = string.format('[%.2f,%.2f,%.1f]', S_[k].x, S_[k].z, k*STEP) end
    for _, st in ipairs(ST) do t.st[#t.st + 1] = string.format('[%.2f,%.2f,%.1f,%d]', st.x, st.z, st.s, st.i) end
    for _, c in ipairs(CAMS) do t.cams[#t.cams + 1] = string.format('{"name":"%s","eye":[%.2f,%.2f,%.2f],"tgt":[%.2f,%.2f,%.2f],"from":%.1f,"to":%.1f}', c.name, c.eye[1], c.eye[2], c.eye[3], c.tgt[1], c.tgt[2], c.tgt[3], c.from, c.to) end
    for _, l in ipairs(LIGHTS) do t.lights[#t.lights + 1] = string.format('[%.2f,%.2f,%.2f,%.1f]', l.x, l.y, l.z, l.r) end
    return string.format('{"L":%.2f,"path":[%s],"st":[%s],"cams":[%s],"lights":[%s]}', L, table.concat(t.path, ','), table.concat(t.st, ','), table.concat(t.cams, ','), table.concat(t.lights, ','))
  end
  WS.nav = nav
  WS.L = L
  WS.CAMS = CAMS
  WS.ST = ST
  WS.display = display
  WS.spawn = function() local x, z, tx, tz = at(SPAWN_S); return x, z, atan2(-tx, -tz) end
  WS.at = at
  WS.route_s = route_s
  WS.group = group
  WS.meshes = { walls = wall_m, floor = floor_m, rocks = rock_m }
  return WS
end

return WAY
