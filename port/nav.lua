--[[
  nav.lua -- the port to Anchor: web/src/nav.js. Where the lich can float: a 0.2 m grid over the
  chamber rasterized from the rock meshes (rock rising more than block_h above the ground blocks
  him, lower rock lifts his float), plus whatever the caller blocks; the distance to the nearest
  blocking cell pushes him out and lets him slide along an edge. The grids are float32 in nav.js;
  stored values are rounded to float32 here too. The distance field is an exact Euclidean distance
  transform (nav.js searches a window by brute force: the same values, capped at MAXD).
]]
local N = {}
local floor, sqrt, abs, max, min, huge = math.floor, math.sqrt, math.abs, math.max, math.min, math.huge
local pack, unpack = string.pack, string.unpack
local function f32(v) return (unpack('<f', pack('<f', v))) end
N.f32 = f32

-- 1D squared distance transform (Felzenszwalb): f[0..n-1] -> d
local function dt1(f, n, d, v, z)
  local k = 0
  v[0] = 0; z[0] = -huge; z[1] = huge
  for q = 1, n - 1 do
    local s = ((f[q] + q*q) - (f[v[k]] + v[k]*v[k]))/(2*q - 2*v[k])
    while s <= z[k] do
      k = k - 1
      s = ((f[q] + q*q) - (f[v[k]] + v[k]*v[k]))/(2*q - 2*v[k])
    end
    k = k + 1
    v[k] = q; z[k] = s; z[k + 1] = huge
  end
  k = 0
  for q = 0, n - 1 do
    while z[k + 1] < q do k = k + 1 end
    local dq = q - v[k]
    d[q] = dq*dq + f[v[k]]
  end
end

function N.build(o)
  local geo, ground_y = o.geo, o.ground_y
  local x0, x1, z0, z1, cell, block_h = o.x0 or -16, o.x1 or 16, o.z0 or -16, o.z1 or 16, o.cell or 0.2, o.block_h or 0.6
  local nx, nz = floor((x1 - x0)/cell + 0.5), floor((z1 - z0)/cell + 0.5)
  local NN = nx*nz
  local top, gy = {}, {}
  local function cx(i) return x0 + (i + 0.5)*cell end
  local function cz(j) return z0 + (j + 0.5)*cell end
  local NEG = f32(-1e9)
  for k = 0, NN - 1 do top[k] = NEG end
  for j = 0, nz - 1 do for i = 0, nx - 1 do gy[j*nx + i] = f32(ground_y(cx(i), cz(j))) end end

  local p = geo.attributes.position:ensure_array()
  local function mark(x, z, y)
    local i, j = floor((x - x0)/cell), floor((z - z0)/cell)
    if i >= 0 and j >= 0 and i < nx and j < nz and y > top[j*nx + i] then top[j*nx + i] = f32(y) end
  end
  for t = 1, #p, 9 do
    local ax, ay, az, bx, by, bz, qx, qy, qz = p[t], p[t + 1], p[t + 2], p[t + 3], p[t + 4], p[t + 5], p[t + 6], p[t + 7], p[t + 8]
    mark(ax, az, ay); mark(bx, bz, by); mark(qx, qz, qy)
    local det = (bz - qz)*(ax - qx) + (qx - bx)*(az - qz)
    if abs(det) >= 1e-9 then
      local i0 = max(0, floor((min(ax, bx, qx) - x0)/cell))
      local i1 = min(nx - 1, floor((max(ax, bx, qx) - x0)/cell))
      local j0 = max(0, floor((min(az, bz, qz) - z0)/cell))
      local j1 = min(nz - 1, floor((max(az, bz, qz) - z0)/cell))
      for j = j0, j1 do for i = i0, i1 do
        local x, z = cx(i), cz(j)
        local l1 = ((bz - qz)*(x - qx) + (qx - bx)*(z - qz))/det
        local l2 = ((qz - az)*(x - qx) + (ax - qx)*(z - qz))/det
        local l3 = 1 - l1 - l2
        if not (l1 < -1e-4 or l2 < -1e-4 or l3 < -1e-4) then
          local y = l1*ay + l2*by + l3*qy
          if y > top[j*nx + i] then top[j*nx + i] = f32(y) end
        end
      end end
    end
  end
  local blocked, flo = {}, {}
  for k = 0, NN - 1 do
    local h = top[k] - gy[k]
    blocked[k] = h > block_h and 1 or 0
    flo[k] = f32(max(gy[k], (h > 0 and h <= block_h) and top[k] or gy[k]))
  end
  local rock = {}
  for k = 0, NN - 1 do rock[k] = blocked[k] end

  local lift = {}
  local LR = math.ceil(0.35/cell)
  for j = 0, nz - 1 do for i = 0, nx - 1 do
    local m = flo[j*nx + i]
    for dj = -LR, LR do for di = -LR, LR do
      if di*di + dj*dj <= LR*LR then
        local ii, jj = i + di, j + dj
        if not (ii < 0 or jj < 0 or ii >= nx or jj >= nz or blocked[jj*nx + ii] == 1) then
          local f = flo[jj*nx + ii]
          if f > m then m = f end
        end
      end
    end end
    lift[j*nx + i] = m
  end end

  local function sample(F, x, z)
    local fx, fz = (x - x0)/cell - 0.5, (z - z0)/cell - 0.5
    local i, j = floor(fx), floor(fz)
    local u, v = fx - i, fz - j
    local function at(a, b) return F[min(nz - 1, max(0, b))*nx + min(nx - 1, max(0, a))] end
    return (at(i, j)*(1 - u) + at(i + 1, j)*u)*(1 - v) + (at(i, j + 1)*(1 - u) + at(i + 1, j + 1)*u)*v
  end

  local dist = nil
  local MAXD = 1.6
  local nav = { nx = nx, nz = nz, cell = cell, x0 = x0, z0 = z0, blocked = blocked }
  function nav.block(fn)
    for j = 0, nz - 1 do for i = 0, nx - 1 do if fn(cx(i), cz(j)) then blocked[j*nx + i] = 1 end end end
  end
  function nav.finish()
    -- squared distance (in cells) to the nearest blocking cell, outside the grid counting as blocking
    local R = math.ceil(MAXD/cell)
    local W, Hh = nx + 2*R, nz + 2*R
    local g = {}
    for jj = 0, Hh - 1 do for ii = 0, W - 1 do
      local i, j = ii - R, jj - R
      local b = (i < 0 or j < 0 or i >= nx or j >= nz) or blocked[j*nx + i] == 1
      g[jj*W + ii] = b and 0 or 1e20
    end end
    local f, d, v, z = {}, {}, {}, {}
    for jj = 0, Hh - 1 do
      for ii = 0, W - 1 do f[ii] = g[jj*W + ii] end
      dt1(f, W, d, v, z)
      for ii = 0, W - 1 do g[jj*W + ii] = d[ii] end
    end
    for ii = 0, W - 1 do
      for jj = 0, Hh - 1 do f[jj] = g[jj*W + ii] end
      dt1(f, Hh, d, v, z)
      for jj = 0, Hh - 1 do g[jj*W + ii] = d[jj] end
    end
    dist = {}
    for j = 0, nz - 1 do for i = 0, nx - 1 do
      if blocked[j*nx + i] == 1 then dist[j*nx + i] = f32(-cell*0.5)
      else
        local best = min(MAXD*MAXD, g[(j + R)*W + (i + R)]*cell*cell)     -- (d2*cell)*cell, nav.js's rounding
        dist[j*nx + i] = f32(sqrt(best) - cell*0.5)
      end
    end end
    return nav
  end
  function nav.floor(x, z) return sample(lift, x, z) end
  function nav.dist(x, z) return sample(dist, x, z) end
  function nav.rock_top(x, z)
    local i, j = floor((x - x0)/cell), floor((z - z0)/cell)
    if i < 0 or j < 0 or i >= nx or j >= nz then return 1e9 end
    return top[j*nx + i]
  end
  function nav.rock_at(x, z)
    local i, j = floor((x - x0)/cell), floor((z - z0)/cell)
    if i < 0 or j < 0 or i >= nx or j >= nz then return huge end
    return rock[j*nx + i] == 1 and top[j*nx + i] or -huge
  end
  function nav.is_blocked(x, z)
    local i, j = floor((x - x0)/cell), floor((z - z0)/cell)
    return i < 0 or j < 0 or i >= nx or j >= nz or blocked[j*nx + i] == 1
  end
  function nav.resolve(pos, vel, r)
    local hit = false
    for _ = 1, 3 do
      local d = sample(dist, pos.x, pos.z)
      if d >= r then break end
      local e = cell*0.5
      local gx = sample(dist, pos.x + e, pos.z) - sample(dist, pos.x - e, pos.z)
      local gz = sample(dist, pos.x, pos.z + e) - sample(dist, pos.x, pos.z - e)
      local gl = js_hypot(gx, gz)
      if gl < 1e-6 then break end
      gx = gx/gl; gz = gz/gl
      pos.x = pos.x + gx*(r - d); pos.z = pos.z + gz*(r - d)
      local into = vel.x*gx + vel.z*gz
      if into < 0 then vel.x = vel.x - gx*into; vel.z = vel.z - gz*into end
      hit = true
    end
    return hit
  end
  return nav
end

return N
