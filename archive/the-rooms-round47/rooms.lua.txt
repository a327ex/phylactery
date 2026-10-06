--[[
  rooms.lua -- round 47 (owner, 2026-10-05): "The tunnel shouldn't be a tunnel i think, the game looks
  quite bad upfront so it should follow the principles of the high up camera view, we should only zoom
  in on the liches face at the end i think when the game ends. So it should be like this small complex
  of rooms, and then a sort of door that's closed to the final egg room. It only opens after you get
  all the items in the other rooms. The other rooms may have different theming but lightly.
  Important, lights should somewhat tell the player where to go, it can be unclear where you have to
  move that will trigger the next camera change. Remember that we're working on a fixed camera model."

  Behind the egg room's mouth: a sealed door, and past it a small complex: THE HALL (where he wakes;
  the hand and the lodestone), THE EMBER ROOM to the west (the mask and the lens; warm) and THE GLASS
  ROOM to the east (the orbs and the gem; cool). Each is a tall cavern seen as the egg room is, from
  one fixed camera high inside it, all facing the same way (toward the egg room: up the screen is
  always north, so the keys keep their sense from room to room). The rock is one shape (rooms,
  passages, the throat round the old tube's first stretch, where the door stands) meshed by surface
  nets, so it has no joins; the floor carries on the egg room's own lattice on the ground he floats on.

  The light says where to go: each passage glows in its room's colour while that room still holds
  something, and goes dark once it does not; the objects stand in their own lamps; the door is a cold
  dim shape until all six are his, and when he is next in the hall it warms, lights and sinks into
  the floor. The way to the egg room is then the old tube (its own camera, round 40's) and the room.
  Taking an object is round 45's: he stops, turns, reaches; it rises to his hand; the viewer opens
  with ACCEPT ARTIFACT.
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

local RM = {}
local TILE = 2.0

RM.ROOMS = {
  { key = 'hall', name = 'THE HALL', x = 0, z = -31, rx = 9, rz = 9, h = 15, amb = { 0.0018, 0.0014, 0.0010 },
    cam = { eye = { 0, 11.0, -37.0 }, tgt = { 0, 0.2, -26.6 }, fov = 62 } },
  { key = 'ember', name = 'THE EMBER ROOM', x = -19.6, z = -33, rx = 7, rz = 6.6, h = 12.8, amb = { 0.0026, 0.0012, 0.0005 },
    cam = { eye = { -19.6, 9.6, -37.6 }, tgt = { -19.6, 0.2, -30.4 }, fov = 60 } },
  { key = 'glass', name = 'THE GLASS ROOM', x = 19.6, z = -33, rx = 7, rz = 6.6, h = 12.8, amb = { 0.0009, 0.0017, 0.0018 },
    cam = { eye = { 19.6, 9.6, -37.6 }, tgt = { 19.6, 0.2, -30.4 }, fov = 60 } },
}
-- passages (hall <-> a room): ends in xz, half width; `room` = the one it leads to
RM.PASSAGES = {
  { a = { -7.6, -27.8 }, b = { -13.8, -30.8 }, w = 1.9, room = 2, col = { 1.0, 0.55, 0.22 } },
  { a = { 7.6, -27.8 }, b = { 13.8, -30.8 }, w = 1.9, room = 3, col = { 0.45, 0.95, 0.9 } },
}
-- the throat: from the hall's north wall round the old tube's first stretch (its collar to its ring
-- at z -20.875 is kept; the door stands in it)
RM.THROAT = { z0 = -25.5, hw = 4.7, hh = 6.1 }      -- (open northward past the mesh's edge: no cap across the tube)
RM.DOOR = { z = -20.2, w = 9.0, h = 6.0, t = 0.55 }
-- the objects: where each waits (index = powers.ALL's, 0-based), its rock's height, its lamp
RM.OBJECTS = {
  [1] = { room = 1, x = -4.6, z = -27.4, h = 0.75 },   -- the hand
  [2] = { room = 1, x = 4.6, z = -27.4, h = 0.5 },     -- the lodestone
  [0] = { room = 2, x = -23.0, z = -31.2, h = 0.66 },  -- the mask
  [5] = { room = 2, x = -17.2, z = -29.0, h = 0.66 },  -- the lens
  [3] = { room = 3, x = 23.0, z = -31.2, h = 0.55 },   -- the orbs
  [4] = { room = 3, x = 17.2, z = -29.0, h = 0.7 },    -- the gem
}
RM.LAMPS = {   -- per object: colour, intensity, reach
  [1] = { { 0.95, 0.88, 0.74 }, 1.6, 6.5 }, [2] = { { 0.98, 0.62, 0.40 }, 1.5, 6.5 },
  [0] = { { 1.0, 0.48, 0.16 }, 2.2, 6.5 }, [5] = { { 1.0, 0.80, 0.52 }, 1.9, 6.5 },
  [3] = { { 0.42, 0.95, 0.85 }, 1.5, 6.5 }, [4] = { { 0.92, 0.92, 1.0 }, 1.8, 6.5 },
}
RM.SPAWN = { x = 0, z = -33.4 }

function RM.create(ctx)
  local R, cave, lich, mover, items, inspect, fx, warp, powers = ctx.R, ctx.cave, ctx.lich, ctx.mover, ctx.items, ctx.inspect, ctx.fx, ctx.warp, ctx.powers
  local ground_y = cave.ground_y
  local rng = U.make_rng(4701)
  local ROOMS = RM.ROOMS
  for _, r in ipairs(ROOMS) do
    local acc = 0
    for _, d in ipairs({ { 0, 0 }, { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }) do acc = acc + ground_y(r.x + d[1], r.z + d[2]) end
    r.yb = acc/5
  end

  -- ------------------------------------------------------------------ the shape (< 0 = air)
  local function room_d(r, x, y, z)
    local dx, dz = (x - r.x)/r.rx, (z - r.z)/r.rz
    local q = sqrt(dx*dx + dz*dz)
    local yy = y - r.yb
    local prof = 1
    if yy > 2.6 then local t = (yy - 2.6)/(r.h - 2.6); prof = t >= 1 and 0 or sqrt(1 - t*t) end
    local d = (q - prof)*min(r.rx, r.rz)
    if yy > r.h then d = max(d, yy - r.h) end
    return d
  end
  local function seg_d(P, x, y, z)
    local ax, az, bx, bz = P.a[1], P.a[2], P.b[1], P.b[2]
    local ex, ez = bx - ax, bz - az
    local t = clamp(((x - ax)*ex + (z - az)*ez)/(ex*ex + ez*ez), 0, 1)
    local px, pz = ax + ex*t, az + ez*t
    local lat = sqrt((x - px)^2 + (z - pz)^2)
    local fl = lerp(ground_y(ax, az), ground_y(bx, bz), t)
    local axis = fl + 1.3
    local d
    if y < axis then d = lat - P.w else d = (sqrt((lat/P.w)^2 + ((y - axis)/2.7)^2) - 1)*P.w end
    return d
  end
  local TH = RM.THROAT
  local function throat_d(x, y, z)
    if z < TH.z0 - 3 then return 9 end
    if y < 0 then return abs(x) - TH.hw end
    return (sqrt((x/TH.hw)^2 + (y/TH.hh)^2) - 1)*TH.hw
  end
  local function field(x, y, z)
    local d = 99
    for _, r in ipairs(ROOMS) do d = min(d, room_d(r, x, y, z)) end
    for _, P in ipairs(RM.PASSAGES) do d = min(d, seg_d(P, x, y, z)) end
    d = min(d, throat_d(x, y, z))
    -- rough rock: the noise only near the surface (it never closes a passage)
    -- (none round the old tube: the rock there must stay outside it, out of sight)
    if d > -1.6 and d < 1.6 then d = d + (U.fbm3(x*0.33, y*0.33, z*0.33, 4703) - 0.5)*1.25*smoothstep(-20.6, -23.5, z) end
    return d
  end
  RM.field = field

  -- ------------------------------------------------------------------ geometry
  local function new_buf() return { p = {}, n = {}, uv = {}, gi = {}, room = {} } end
  local walls, floorb, rocks = new_buf(), new_buf(), new_buf()
  local function push_tri(b, a, c, d, ua, uc, ud, toward)
    local e1x, e1y, e1z = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local e2x, e2y, e2z = d[1] - a[1], d[2] - a[2], d[3] - a[3]
    local nx, ny, nz = e1y*e2z - e1z*e2y, e1z*e2x - e1x*e2z, e1x*e2y - e1y*e2x
    local l = sqrt(nx*nx + ny*ny + nz*nz)
    if l < 1e-10 then return end
    nx, ny, nz = nx/l, ny/l, nz/l
    if toward then
      local mx, my, mz = (a[1] + c[1] + d[1])/3, (a[2] + c[2] + d[2])/3, (a[3] + c[3] + d[3])/3
      local ix, iy, iz = toward(mx, my, mz)
      if nx*(ix - mx) + ny*(iy - my) + nz*(iz - mz) < 0 then c, d, uc, ud = d, c, ud, uc; nx, ny, nz = -nx, -ny, -nz end
    end
    for _, q in ipairs({ { a, ua }, { c, uc }, { d, ud } }) do
      local P, UV = q[1], q[2]
      b.p[#b.p + 1] = P[1]; b.p[#b.p + 1] = P[2]; b.p[#b.p + 1] = P[3]
      b.n[#b.n + 1] = nx; b.n[#b.n + 1] = ny; b.n[#b.n + 1] = nz
      b.uv[#b.uv + 1] = UV[1]; b.uv[#b.uv + 1] = UV[2]
    end
  end
  local function nearest_room(x, z)
    local best, bi = math.huge, 1
    for i, r in ipairs(ROOMS) do
      local q = sqrt(((x - r.x)/r.rx)^2 + ((z - r.z)/r.rz)^2)
      if q < best then best = q; bi = i end
    end
    return bi, best
  end
  -- a wall face's UVs: round its room's axis (arc length) and up, or from below where it faces down
  local function wall_uv(P, ny)
    if ny < -0.7 then return { P[1]/TILE, P[3]/TILE } end
    local ri = nearest_room(P[1], P[3])
    local r = ROOMS[ri]
    local a = atan2(P[3] - r.z, P[1] - r.x)
    local rad = (r.rx + r.rz)/2
    return { a*rad/TILE, P[2]/TILE }
  end

  -- surface nets over the complex
  local CELL = 0.75
  local X0, X1, Y0, Y1, Z0, Z1 = -28, 28, -2.5, 15.5, -42, -17.5
  local NX, NY, NZ = ceil((X1 - X0)/CELL), ceil((Y1 - Y0)/CELL), ceil((Z1 - Z0)/CELL)
  local F = {}
  local function gi_(i, j, k) return (k*(NY + 1) + j)*(NX + 1) + i end
  for k = 0, NZ do for j = 0, NY do for i = 0, NX do
    F[gi_(i, j, k)] = field(X0 + i*CELL, Y0 + j*CELL, Z0 + k*CELL)
  end end end
  local CV = {}            -- cell -> its vertex {x, y, z}
  local EDGES = { { 0, 1 }, { 2, 3 }, { 4, 5 }, { 6, 7 }, { 0, 2 }, { 1, 3 }, { 4, 6 }, { 5, 7 }, { 0, 4 }, { 1, 5 }, { 2, 6 }, { 3, 7 } }
  local function corner(i, j, k, c) return i + (c & 1), j + ((c >> 1) & 1), k + ((c >> 2) & 1) end
  for k = 0, NZ - 1 do for j = 0, NY - 1 do for i = 0, NX - 1 do
    local neg, pos = false, false
    local v = {}
    for c = 0, 7 do
      local a, b, cc = corner(i, j, k, c)
      local f = F[gi_(a, b, cc)]
      v[c] = f
      if f < 0 then neg = true else pos = true end
    end
    if neg and pos then
      local sx, sy, sz, n = 0, 0, 0, 0
      for _, e in ipairs(EDGES) do
        local f0, f1 = v[e[1]], v[e[2]]
        if (f0 < 0) ~= (f1 < 0) then
          local t = f0/(f0 - f1)
          local a0, b0, c0 = corner(i, j, k, e[1])
          local a1, b1, c1 = corner(i, j, k, e[2])
          sx = sx + (a0 + (a1 - a0)*t); sy = sy + (b0 + (b1 - b0)*t); sz = sz + (c0 + (c1 - c0)*t); n = n + 1
        end
      end
      CV[gi_(i, j, k)] = { X0 + sx/n*CELL, Y0 + sy/n*CELL, Z0 + sz/n*CELL }
    end
  end end end
  local function quad(c1, c2, c3, c4, air)
    local A, B, C, D = CV[c1], CV[c2], CV[c3], CV[c4]
    if not (A and B and C and D) then return end
    local toward = function() return air[1], air[2], air[3] end
    local function tri(p, q, r)
      local e1x, e1y, e1z = q[1] - p[1], q[2] - p[2], q[3] - p[3]
      local e2x, e2y, e2z = r[1] - p[1], r[2] - p[2], r[3] - p[3]
      local ny = e1z*e2x - e1x*e2z
      local l = sqrt((e1y*e2z - e1z*e2y)^2 + ny^2 + (e1x*e2y - e1y*e2x)^2)
      if l < 1e-10 then return end
      -- (the face's own normal for its UVs, oriented toward the air)
      local mx, my, mz = (p[1] + q[1] + r[1])/3, (p[2] + q[2] + r[2])/3, (p[3] + q[3] + r[3])/3
      local nyo = ny/l
      local nx_, nz_ = (e1y*e2z - e1z*e2y)/l, (e1x*e2y - e1y*e2x)/l
      if nx_*(air[1] - mx) + nyo*(air[2] - my) + nz_*(air[3] - mz) < 0 then nyo = -nyo end
      push_tri(walls, p, q, r, wall_uv(p, nyo), wall_uv(q, nyo), wall_uv(r, nyo), toward)
    end
    tri(A, B, C); tri(A, C, D)
  end
  for k = 1, NZ - 1 do for j = 1, NY - 1 do for i = 0, NX - 1 do           -- edges along x
    local f0, f1 = F[gi_(i, j, k)], F[gi_(i + 1, j, k)]
    if (f0 < 0) ~= (f1 < 0) then
      local air = f0 < 0 and { X0 + i*CELL, Y0 + j*CELL, Z0 + k*CELL } or { X0 + (i + 1)*CELL, Y0 + j*CELL, Z0 + k*CELL }
      quad(gi_(i, j - 1, k - 1), gi_(i, j, k - 1), gi_(i, j, k), gi_(i, j - 1, k), air)
    end
  end end end
  for k = 1, NZ - 1 do for j = 0, NY - 1 do for i = 1, NX - 1 do           -- edges along y
    local f0, f1 = F[gi_(i, j, k)], F[gi_(i, j + 1, k)]
    if (f0 < 0) ~= (f1 < 0) then
      local air = f0 < 0 and { X0 + i*CELL, Y0 + j*CELL, Z0 + k*CELL } or { X0 + i*CELL, Y0 + (j + 1)*CELL, Z0 + k*CELL }
      quad(gi_(i - 1, j, k - 1), gi_(i, j, k - 1), gi_(i, j, k), gi_(i - 1, j, k), air)
    end
  end end end
  for k = 0, NZ - 1 do for j = 1, NY - 1 do for i = 1, NX - 1 do           -- edges along z
    local f0, f1 = F[gi_(i, j, k)], F[gi_(i, j, k + 1)]
    if (f0 < 0) ~= (f1 < 0) then
      local air = f0 < 0 and { X0 + i*CELL, Y0 + j*CELL, Z0 + k*CELL } or { X0 + i*CELL, Y0 + j*CELL, Z0 + (k + 1)*CELL }
      quad(gi_(i - 1, j - 1, k), gi_(i, j - 1, k), gi_(i, j, k), gi_(i - 1, j, k), air)
    end
  end end end
  -- (the rock over the old tube's first stretch and the egg room's own wall: the complex ends at
  -- the throat; nothing of it may show north of the egg room's wall)

  -- the floor: the egg room's lattice (0.7 m from x -21, z -47), its own nodes where it has them
  -- (so the two floors share every vertex on their border), new cells wherever the complex is air
  local FC, FX0, FZ0 = 0.7, -21, -47
  local nodes, covered = {}, {}
  local fl3
  for _, m in ipairs(cave.statics) do if m.geometry.name == 'cave_3' then fl3 = m.geometry end end
  if fl3 then
    local p = fl3.attributes.position:ensure_array()
    for v = 0, #p//3 - 1 do
      local x, y, z = p[v*3 + 1], p[v*3 + 2], p[v*3 + 3]
      local i, j = floor((x - FX0)/FC + 0.5), floor((z - FZ0)/FC + 0.5)
      nodes[j*4000 + i] = { x, y, z }
    end
    for t = 0, #p//9 - 1 do
      local cx, cz = (p[t*9 + 1] + p[t*9 + 4] + p[t*9 + 7])/3, (p[t*9 + 3] + p[t*9 + 6] + p[t*9 + 9])/3
      covered[floor((cz - FZ0)/FC)*4000 + floor((cx - FX0)/FC)] = true
    end
  end
  local function hj(i, j, s) return (sin(i*127.1 + j*311.7 + s*74.7)*43758.5453) % 1 end
  local function node(i, j)
    local k = j*4000 + i
    if nodes[k] then return nodes[k] end
    local x, z = FX0 + i*FC + (hj(i, j, 61) - 0.5)*FC*0.55, FZ0 + j*FC + (hj(i, j, 67) - 0.5)*FC*0.55
    nodes[k] = { x, ground_y(x, z), z }
    return nodes[k]
  end
  local up = function(x, y, z) return x, y + 10, z end
  for j = floor((Z0 - FZ0)/FC), ceil((Z1 - FZ0)/FC) do for i = floor((X0 - FX0)/FC), ceil((X1 - FX0)/FC) do
    if not covered[j*4000 + i] then
      local cx, cz = FX0 + (i + 0.5)*FC, FZ0 + (j + 0.5)*FC
      local gy = ground_y(cx, cz)
      -- air above this cell, or rock within reach of air (so the floor runs under the walls' feet)
      if cz < -18.6 and field(cx, gy + 0.6, cz) < 1.1 then
        local a, b, c, d = node(i, j), node(i + 1, j), node(i + 1, j + 1), node(i, j + 1)
        local function uv(q) return { q[1]/TILE, q[3]/TILE } end
        push_tri(floorb, a, b, c, uv(a), uv(b), uv(c), up)
        push_tri(floorb, a, c, d, uv(a), uv(c), uv(d), up)
      end
    end
  end end

  -- rock lumps (round 45's): plinths for the objects
  local function lump(cx, cy, cz, rx, ry, rz, seed, flat_top)
    local t = (1 + sqrt(5))/2
    local V = { { -1, t, 0 }, { 1, t, 0 }, { -1, -t, 0 }, { 1, -t, 0 }, { 0, -1, t }, { 0, 1, t }, { 0, -1, -t }, { 0, 1, -t }, { t, 0, -1 }, { t, 0, 1 }, { -t, 0, -1 }, { -t, 0, 1 } }
    local Fc = { { 1, 12, 6 }, { 1, 6, 2 }, { 1, 2, 8 }, { 1, 8, 11 }, { 1, 11, 12 }, { 2, 6, 10 }, { 6, 12, 5 }, { 12, 11, 3 }, { 11, 8, 7 }, { 8, 2, 9 },
      { 4, 10, 5 }, { 4, 5, 3 }, { 4, 3, 7 }, { 4, 7, 9 }, { 4, 9, 10 }, { 5, 10, 6 }, { 3, 5, 12 }, { 7, 3, 11 }, { 9, 7, 8 }, { 10, 9, 2 } }
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
    for _, f in ipairs(Fc) do
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
    local out = function(mx, my, mz) return 2*mx - cx, 2*my - cy, 2*mz - cz end
    for _, f in ipairs(FF) do
      local a, b, c = W[f[1]], W[f[2]], W[f[3]]
      local e1x, e1y, e1z = b[1] - a[1], b[2] - a[2], b[3] - a[3]
      local e2x, e2y, e2z = c[1] - a[1], c[2] - a[2], c[3] - a[3]
      local nx, ny, nz = abs(e1y*e2z - e1z*e2y), abs(e1z*e2x - e1x*e2z), abs(e1x*e2y - e1y*e2x)
      local function uv(q) if ny >= nx and ny >= nz then return { q[1]/TILE, q[3]/TILE } elseif nx >= nz then return { q[3]/TILE, q[2]/TILE } end; return { q[1]/TILE, q[2]/TILE } end
      push_tri(rocks, a, b, c, uv(a), uv(b), uv(c), out)
    end
  end
  local ST = {}
  for i0 = 0, 5 do
    local o = RM.OBJECTS[i0]
    local gy = ground_y(o.x, o.z)
    local top = gy + o.h
    lump(o.x, gy + o.h*0.35, o.z, 0.62, o.h*0.7 + 0.15, 0.58, i0*3.7 + 1, top)
    ST[i0] = { i = i0, room = o.room, x = o.x, z = o.z, top = top }
  end

  -- ------------------------------------------------------------------ light
  -- the nine point lights the egg room lends while he is out here (three.js compiled its programs
  -- for nine; nothing in the room lights any before the fight)
  local HALL = ROOMS[1]
  local LT = {
    hall = { x = HALL.x, y = HALL.yb + 7.5, z = HALL.z + 0.5, col = { 1.0, 0.86, 0.66 }, I = 1.5, r = 16, decay = 0.9 },
    door = { x = 0, y = HALL.yb + 2.6, z = RM.DOOR.z - 1.8, col = { 0.55, 0.62, 0.8 }, I = 0.35, r = 7, decay = 1.2 },
  }
  local LIST = { LT.hall, LT.door }
  for i0 = 0, 5 do
    local o, st, L = RM.OBJECTS[i0], ST[i0], RM.LAMPS[i0]
    local r = ROOMS[o.room]
    -- a little above it and toward the room's middle
    local dx, dz = r.x - st.x, r.z - st.z
    local l = js_hypot(dx, dz)
    LT['obj' .. i0] = { x = st.x + dx/l*0.8, y = st.top + 1.4, z = st.z + dz/l*0.8, col = L[1], I = L[2], r = L[3], decay = 1.25 }
  end
  for k, P in ipairs(RM.PASSAGES) do
    local mx, mz = (P.a[1] + P.b[1])/2, (P.a[2] + P.b[2])/2
    LT['pass' .. k] = { x = mx, y = ground_y(mx, mz) + 2.0, z = mz, col = P.col, I = 3.2, r = 8.5, decay = 1.15 }
  end
  -- the hall's own two share one: the hand's and the lodestone's lamps become one between them
  LT.obj12 = { x = 0, y = HALL.yb + 2.6, z = -27.2, col = { 1.0, 0.82, 0.62 }, I = 1.7, r = 7.5, decay = 1.25 }
  local ORDER = { 'hall', 'door', 'obj12', 'obj0', 'obj5', 'obj3', 'obj4', 'pass1', 'pass2' }
  -- the bake: bounce round the lights that never change, and a dim tint of each room's own
  local function bake(b)
    local p, n, gi = b.p, b.n, b.gi
    for v = 0, #p//3 - 1 do
      local x, y, z = p[v*3 + 1], p[v*3 + 2], p[v*3 + 3]
      local nx, ny, nz = n[v*3 + 1], n[v*3 + 2], n[v*3 + 3]
      local ri = nearest_room(x, z)
      local a = ROOMS[ri].amb
      local r, g, bl = a[1], a[2], a[3]
      for _, key in ipairs({ 'hall', 'obj12', 'obj0', 'obj5', 'obj3', 'obj4' }) do
        local lt = LT[key]
        local dx, dy, dz = lt.x - x, lt.y - y, lt.z - z
        local d = sqrt(dx*dx + dy*dy + dz*dz)
        if d < lt.r*1.3 then
          local c = max(0, (nx*dx + ny*dy + nz*dz)/max(d, 1e-4))*0.6 + 0.4
          local f = lt.I*0.0030*c*(1 - smoothstep(0, lt.r*1.3, d))^2/(1 + d*d*0.08)
          r = r + lt.col[1]*f; g = g + lt.col[2]*f; bl = bl + lt.col[3]*f
        end
      end
      gi[v*3 + 1], gi[v*3 + 2], gi[v*3 + 3] = r, g, bl
    end
  end
  bake(walls); bake(floorb); bake(rocks)

  local group = T.Group.new()
  group.name = 'rooms'
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
  local wall_m = mesh_of(walls, Mc.wall, 'rooms.walls')
  local floor_m = mesh_of(floorb, Mc.floor, 'rooms.floor')
  local rock_m = mesh_of(rocks, Mc.rock, 'rooms.rocks')
  -- the old tube: its collar and first stretch stay (the door stands in them); the rest goes, and the
  -- egg room's floor strip down it past the throat
  cave.cut_tunnel(-20.9, -40.5)

  -- the door: a slab of the same rock filling the old tube, sunk into the floor when it opens
  local door = { open = false, t = -1, y0 = 0 }
  do
    local b = new_buf()
    local Dd = RM.DOOR
    local gy = ground_y(0, Dd.z)
    door.y0 = gy - 0.4
    local hw, hh, ht = Dd.w/2, Dd.h, Dd.t/2
    -- a box roughened on its faces (a grid per face, displaced along its normal)
    local function face(o, ux, vx, nrm, nu, nv)
      local P = {}
      for a = 0, nu do P[a] = {} for c = 0, nv do
        local u, v = a/nu, c/nv
        local x, y, z = o[1] + ux[1]*u + vx[1]*v, o[2] + ux[2]*u + vx[2]*v, o[3] + ux[3]*u + vx[3]*v
        local k = (U.fbm3(x*0.9, y*0.9, z*0.9, 4711) - 0.5)*0.22
        P[a][c] = { x + nrm[1]*k, y + nrm[2]*k, z + nrm[3]*k }
      end end
      local tw = function(mx, my, mz) return mx + nrm[1], my + nrm[2], mz + nrm[3] end
      for a = 0, nu - 1 do for c = 0, nv - 1 do
        local p1, p2, p3, p4 = P[a][c], P[a + 1][c], P[a + 1][c + 1], P[a][c + 1]
        local function uv(q) if abs(nrm[3]) > 0.5 then return { q[1]/TILE, q[2]/TILE } elseif abs(nrm[1]) > 0.5 then return { q[3]/TILE, q[2]/TILE } end; return { q[1]/TILE, q[3]/TILE } end
        push_tri(b, p1, p2, p3, uv(p1), uv(p2), uv(p3), tw); push_tri(b, p1, p3, p4, uv(p1), uv(p3), uv(p4), tw)
      end end
    end
    local z0, z1 = -ht, ht
    face({ -hw, 0, z1 }, { 2*hw, 0, 0 }, { 0, hh, 0 }, { 0, 0, 1 }, 14, 9)
    face({ -hw, 0, z0 }, { 2*hw, 0, 0 }, { 0, hh, 0 }, { 0, 0, -1 }, 14, 9)
    face({ -hw, hh, z0 }, { 2*hw, 0, 0 }, { 0, 0, 2*ht }, { 0, 1, 0 }, 14, 2)
    face({ -hw, 0, z0 }, { 0, hh, 0 }, { 0, 0, 2*ht }, { -1, 0, 0 }, 9, 2)
    face({ hw, 0, z0 }, { 0, hh, 0 }, { 0, 0, 2*ht }, { 1, 0, 0 }, 9, 2)
    for v = 0, #b.p//3 - 1 do b.gi[v*3 + 1], b.gi[v*3 + 2], b.gi[v*3 + 3] = 0.0012, 0.0010, 0.0008 end
    door.mesh = mesh_of(b, Mc.rock, 'rooms.door')
    door.mesh.position:set(0, door.y0, Dd.z)
  end

  -- the lights, lent
  local pl = {}
  R.world_scene:traverse(function(o) if o.is_point_light then pl[#pl + 1] = o end end)
  local lent = {}
  local LAMP = {}
  for k, key in ipairs(ORDER) do
    local l = pl[k]
    if l then
      lent[#lent + 1] = { l = l, keep = { position = l.position:clone(), color = l.color:clone(), intensity = l.intensity, distance = l.distance, decay = l.decay } }
      local lt = LT[key]
      l.position:set(lt.x, lt.y, lt.z); l.color:set_rgb(lt.col[1], lt.col[2], lt.col[3]); l.intensity = lt.I; l.distance = lt.r; l.decay = lt.decay
      LAMP[key] = { l = l, I = lt.I, cur = lt.I }
    end
  end

  -- ------------------------------------------------------------------ cameras
  local CAMS = {}
  for i, r in ipairs(ROOMS) do
    local c = r.cam
    local eye, tgt = { c.eye[1], r.yb + c.eye[2], c.eye[3] }, { c.tgt[1], r.yb + c.tgt[2], c.tgt[3] }
    -- (in the open: moved toward what it looks at until the rock is a good way off all round)
    for _ = 1, 60 do
      local clear = field(eye[1], eye[2], eye[3]) < -1.5
      for _, o in ipairs({ { 1.2, 0, 0 }, { -1.2, 0, 0 }, { 0, 1.2, 0 }, { 0, 0, 1.2 }, { 0, 0, -1.2 } }) do
        if field(eye[1] + o[1], eye[2] + o[2], eye[3] + o[3]) > -0.2 then clear = false end
      end
      if clear then break end
      for k = 1, 3 do eye[k] = eye[k] + (tgt[k] - eye[k])*0.03 end
    end
    CAMS[i] = { name = r.name, eye = eye, tgt = tgt, fov = c.fov }
  end

  -- ------------------------------------------------------------------ where he can go
  local nav
  do
    local x0, x1, z0, z1 = -27, 27, -41, -2
    nav = NAV.build({ geo = cave.rock_geo, ground_y = ground_y, x0 = x0, x1 = x1, z0 = z0, z1 = z1 })
    nav.block(function(x, z)
      if z > -21.2 then
        -- the old tube and the egg room's mouth (round 40's), behind the door until it opens
        if abs(x) > 1.9 then return true end
        return not door.open
      end
      local gy = ground_y(x, z)
      if field(x, gy + 1.0, z) > -0.6 or field(x, gy + 0.25, z) > -0.45 then return true end
      for _, st in pairs(ST) do if (x - st.x)^2 + (z - st.z)^2 < 0.85*0.85 then return true end end
      return false
    end)
    nav.finish()
  end
  -- (the door's line: re-blocked/unblocked by rebuilding only its strip of the grid is not offered by
  -- nav.lua; the grid is built twice instead: shut, and open)
  local nav_open
  local function build_open_nav()
    door.open = true
    local n2 = NAV.build({ geo = cave.rock_geo, ground_y = ground_y, x0 = -27, x1 = 27, z0 = -41, z1 = -2 })
    n2.block(function(x, z)
      if z > -21.2 then return abs(x) > 1.9 end
      local gy = ground_y(x, z)
      if field(x, gy + 1.0, z) > -0.6 or field(x, gy + 0.25, z) > -0.45 then return true end
      for _, st in pairs(ST) do if (x - st.x)^2 + (z - st.z)^2 < 0.85*0.85 then return true end end
      return false
    end)
    n2.finish()
    door.open = false
    return n2
  end

  -- ------------------------------------------------------------------ the objects, waiting (round 45's)
  local SIZES = ITM.SIZES
  local display = {}
  for i0 = 0, 5 do
    local st = ST[i0]
    local wi = items.W[i0 + 1]
    if i0 == 1 then ITM.set_hand_material(items.opts.hand_mat) end
    local g = wi.make()
    g.visible = true
    local kk = wi.it.fixed_k or SIZES[items.opts.size + 1].k*(wi.it.floor_mul or 1)
    local r = ROOMS[st.room]
    local lampkey = (i0 == 1 or i0 == 2) and 'obj12' or ('obj' .. i0)
    local d = { i = i0, g = g, k = kk, at = Vector3.new(st.x, st.top, st.z), state = 'waiting', t = 0, base_q = Quaternion.new(), st = st, lamp = LT[lampkey] }
    -- facing the room's camera (toward +z... the cameras sit south: face south, a little toward the middle)
    local face = atan2(r.cam.eye[1] - st.x, r.cam.eye[3] - st.z)
    if i0 == 0 then d.base_q:set_from_euler(Euler.new(-0.32, face, 0, 'YXZ')); d.at.y = st.top + 0.2*kk
    elseif i0 == 1 then d.base_q:set_from_euler(Euler.new(0, face, 0, 'YXZ')); d.at.y = st.top + 0.16*kk
    elseif i0 == 2 then d.at.y = st.top + 0.42
    elseif i0 == 3 then d.at.y = st.top + 0.34
    elseif i0 == 4 then d.at.y = st.top + 0.07*kk
    elseif i0 == 5 then d.base_q:set_from_euler(Euler.new(-0.25, face, 0, 'YXZ')); d.at.y = st.top + 0.33
    end
    g.scale:set_scalar(kk)
    g.position:copy(d.at)
    g.quaternion:copy(d.base_q)
    local function lamp_sun(m)
      local prev = m.on_before_render
      local U2 = m.material.user_data.U
      local wp = Vector3.new()
      m.on_before_render = function(self, rr, c)
        if prev then prev(self, rr, c) end
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
    display[#display + 1] = d
  end
  local function orbs_pose(d, t, k)
    for j, m in ipairs(d.orbs) do
      local a = t*(0.35 + 0.08*j)*((j % 2 == 0) and -1 or 1) + j*1.9
      local rad = (0.03 + 0.05*(j - 1))*k
      local tilt = ({ 0.2, -0.5, 0.7, -0.3, 0.45 })[j]
      local x, z = cos(a)*rad, sin(a)*rad
      m.position:set(x, sin(t*0.7 + j)*0.02*k + z*cos(tilt), z*sin(tilt))
      m.scale:set_scalar(m.user_data.r*k)
    end
  end
  local function idle(d, t)
    local g = d.g
    if d.i == 2 then
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
  local function room_of(x, z)
    if z > -21.0 then return nil end                     -- the old tube: round 40's camera
    local bi, best = nearest_room(x, z)
    return bi
  end
  local function left_in(ri)
    local n = 0
    for _, d in ipairs(display) do if d.st.room == ri and d.state == 'waiting' then n = n + 1 end end
    return n
  end
  local function all_his() for i = 0, 5 do if not powers.is_on(powers.ALL[i + 1]) then return false end end; return true end
  local function set_lamp(key, target, dt, rate)
    local L = LAMP[key]
    if not L then return end
    L.cur = L.cur + (target - L.cur)*(1 - exp(-(rate or 2.5)*dt))
    L.l.intensity = L.cur
  end
  function WS.tick(t, dt)
    WS.t = t
    local Lp = mover.p
    -- the camera: which room he is in (keeping the last while it is a near thing)
    local z = room_of(Lp.x, Lp.z)
    if z ~= WS.zone then
      if z == nil or WS.zone == nil then WS.zone = z; WS.cut = true
      else
        local _, qa = nearest_room(Lp.x, Lp.z)
        local r = ROOMS[WS.zone]
        local qcur = sqrt(((Lp.x - r.x)/r.rx)^2 + ((Lp.z - r.z)/r.rz)^2)
        if qcur > qa + 0.06 then WS.zone = z; WS.cut = true end
      end
    end
    -- out here the egg room's sun would light the rock from outside its shadow map: it waits
    local far = WS.zone ~= nil
    cave.sun.intensity = far and 0 or sun_keep.I
    R.params.shafts.on = (not far) and sun_keep.shafts
    for _, d in ipairs(display) do
      if d.state == 'waiting' then
        idle(d, t)
        if not WS.taking and not WS.after and js_hypot(Lp.x - d.at.x, Lp.z - d.at.z) < 2.1 then begin_take(d) end
      elseif d.state == 'rising' then
        take_tick(d, dt)
      end
    end
    -- the light tells him where to go: a passage glows while its room still holds something
    for k, P in ipairs(RM.PASSAGES) do
      local flick = 1 + 0.06*sin(t*5.3 + k) + 0.04*sin(t*11.7 + 2*k)
      set_lamp('pass' .. k, left_in(P.room) > 0 and LT['pass' .. k].I*flick or 0, dt, 1.5)
    end
    -- the door: cold and dim until all six are his; then, when he is in the hall, it warms and sinks
    if door.t < 0 and all_his() and WS.zone == 1 and not WS.after and not WS.taking then
      door.t = 0
      nav_open = nav_open or build_open_nav()
    end
    local L = LAMP.door
    if door.t >= 0 then
      door.t = door.t + dt
      local k = smoothstep(0.0, 1.2, door.t)
      if L then
        L.l.color:set_rgb(lerp(0.55, 1.0, k), lerp(0.62, 0.78, k), lerp(0.8, 0.45, k))
        set_lamp('door', 0.35 + 3.4*k, dt, 3)
        L.l.distance = lerp(7, 15, k)
      end
      local s = smoothstep(1.0, 4.6, door.t)
      door.mesh.position.y = door.y0 - s*(RM.DOOR.h + 0.6) + sin(door.t*31)*0.012*(1 - s)*smoothstep(0.9, 1.2, door.t)
      if door.t > 1.0 and door.t < 4.8 and floor(door.t*8) ~= floor((door.t - dt)*8) then
        for _ = 1, 3 do
          local x = rng.float(-3.4, 3.4)
          fx.puff({ x = x, y = door.y0 + 0.5 + 0.3, z = RM.DOOR.z - 0.6, vx = rng.spread(0.2), vy = rng.float(0.3, 0.8), vz = rng.float(-0.4, -0.1),
            drag = 1.2, life = rng.float(1.2, 2.2), s0 = 0.15, s1 = 0.8, r = 0.18, g = 0.15, b = 0.12, a = 0.3 })
        end
      end
      if s > 0.7 and not door.open then door.open = true; WS.nav_swap = nav_open end
    else
      set_lamp('door', LT.door.I*(1 + 0.08*sin(t*1.7)), dt, 2)
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
  end
  function WS.after_accept()
    local d = WS.after
    if not d then return nil end
    WS.after = nil
    powers.set(d.i, true)
    return d.i
  end
  function WS.busy() return WS.taking ~= nil or WS.after ~= nil end
  function WS.rig()
    local c = WS.zone and CAMS[WS.zone]
    if not c then return nil end
    return c.eye, c.tgt, c.fov, c.name
  end
  function WS.leave()
    for _, e in ipairs(lent) do
      local l, k = e.l, e.keep
      l.position:copy(k.position); l.color:copy(k.color); l.intensity = k.intensity; l.distance = k.distance; l.decay = k.decay
    end
    lent = {}; LAMP = {}
    cave.sun.intensity = sun_keep.I
    R.params.shafts.on = sun_keep.shafts
  end
  -- testing: `upto` objects his already (0-6, in the order hall, ember, glass), placed where the
  -- next one waits (6: in the hall with all six, before the door)
  local ORDER_OBJ = { 1, 2, 0, 5, 3, 4 }
  function WS.reset(upto)
    WS.collected = {}
    local had = {}
    for k = 1, upto do had[ORDER_OBJ[k]] = true end
    for _, d in ipairs(display) do
      local h = had[d.i] or false
      d.state = h and 'held' or 'waiting'
      d.g.visible = not h
      if d.orbs then for _, m in ipairs(d.orbs) do m.visible = not h end end
      d.scale = 1
      if not d.orbs then d.g.scale:set_scalar(d.k) end
      WS.collected[d.i] = h or nil
      ITM.ITEMS[d.i + 1].build = h
      powers.set(d.i, h)
    end
    WS.taking = nil; WS.after = nil
    if upto == 0 then return RM.SPAWN.x, RM.SPAWN.z, 0 end
    if upto >= 6 then return 0, -30.5, 0 end
    local nxt = ST[ORDER_OBJ[upto + 1]]
    local r = ROOMS[nxt.room]
    -- a few metres short of it, toward its room's camera
    local dx, dz = r.cam.eye[1] - nxt.x, r.cam.eye[3] - nxt.z
    local l = js_hypot(dx, dz)
    return nxt.x + dx/l*3.2, nxt.z + dz/l*3.2, atan2(-dx, -dz)
  end
  function WS.door_state() return { t = door.t, open = door.open, y = door.mesh.position.y } end
  WS.nav = nav
  WS.CAMS = CAMS
  WS.ST = ST
  WS.display = display
  WS.group = group
  WS.room_of = room_of
  WS.meshes = { walls = wall_m, floor = floor_m, rocks = rock_m, door = door.mesh }
  WS.L = 0
  return WS
end

return RM
