--[[
  walknav.lua -- where the lich can float in the walk: the grid tools/walk/nav.mjs computed for the
  whole walk and the final room's tunnel (0.25 m cells), read in place from its blobs. The same
  calls as nav.lua's (floor, dist, resolve, is_blocked, rock_at, rock_top), so the mover takes
  either; plus what the walk asks of a cell: how far along the walk it is (s) and its area.
]]
local N = {}
local floor, min, max, huge = math.floor, math.min, math.max, math.huge
local unpack = string.unpack

function N.load(A, meta)
  local function blob(name) local s = file_read_string(A.manifest.dir .. '/nav/' .. name .. '.bin'); assert(s, 'walk nav blob missing: ' .. name); return s end
  local lift, dist, rock, sv, area = blob('lift'), blob('dist'), blob('rock'), blob('s'), blob('area')
  local x0, z0, nx, nz, cell = meta.x0, meta.z0, meta.nx, meta.nz, meta.cell
  local nav = { nx = nx, nz = nz, cell = cell, x0 = x0, z0 = z0, walk = true }
  local function f(b, k) return (unpack('<f', b, k*4 + 1)) end
  local function sample(b, x, z)
    local fx, fz = (x - x0)/cell - 0.5, (z - z0)/cell - 0.5
    local i, j = floor(fx), floor(fz)
    local u, v = fx - i, fz - j
    local i0, i1 = min(nx - 1, max(0, i)), min(nx - 1, max(0, i + 1))
    local j0, j1 = min(nz - 1, max(0, j)), min(nz - 1, max(0, j + 1))
    local a, b2, c, d = f(b, j0*nx + i0), f(b, j0*nx + i1), f(b, j1*nx + i0), f(b, j1*nx + i1)
    return (a*(1 - u) + b2*u)*(1 - v) + (c*(1 - u) + d*u)*v
  end
  local function cell_of(x, z)
    local i, j = floor((x - x0)/cell), floor((z - z0)/cell)
    if i < 0 or j < 0 or i >= nx or j >= nz then return nil end
    return j*nx + i
  end
  function nav.floor(x, z) return sample(lift, x, z) end
  function nav.dist(x, z) return sample(dist, x, z) end
  function nav.rock_top(x, z) local k = cell_of(x, z); if not k then return 1e9 end; local r = f(rock, k); return r < -1e29 and -1e9 or r end
  function nav.rock_at(x, z) local k = cell_of(x, z); if not k then return huge end; local r = f(rock, k); return r < -1e29 and -huge or r end
  function nav.is_blocked(x, z) local k = cell_of(x, z); return not k or f(dist, k) < 0 end
  function nav.s_at(x, z) local k = cell_of(x, z); return k and f(sv, k) or -1 end
  function nav.area_at(x, z) local k = cell_of(x, z); return k and area:byte(k + 1) or 255 end
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
