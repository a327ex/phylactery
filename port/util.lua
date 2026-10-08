--[[
  util.lua -- the port to Anchor: web/src/util.js (seeded rng, math helpers, springs, 1D noise)
  and the cave's 3D value noise (cave.js h3 / noise3 / fbm3). The rng is sfc32 seeded through
  splitmix32 with JavaScript's 32-bit integer semantics kept exactly, so the Anchor build draws
  the same numbers as the three.js build from the same seed.
]]
local U = {}
local floor, sqrt, abs, exp, min, max, atan = math.floor, math.sqrt, math.abs, math.exp, math.min, math.max, math.atan
local M32 = 0xFFFFFFFF

U.DT = 1/60
U.DEG = math.pi/180

-- Math.imul, and the unsigned 32-bit results JS gets with >>> 0
local function imul(a, b) return (a*b) & M32 end
U.imul = imul

local function splitmix(seed)
  local s = seed & M32
  return function()
    s = (s + 0x9e3779b9) & M32
    local z = s
    z = imul(z ~ (z >> 16), 0x85ebca6b)
    z = imul(z ~ (z >> 13), 0xc2b2ae35)
    return (z ~ (z >> 16)) & M32
  end
end

function U.hash_str(str)
  local h = 2166136261
  for i = 1, #str do h = imul(h ~ str:byte(i), 16777619) end
  return h & M32
end

-- round 65 (owner, 2026-10-08: "The game is playing the same at all times, likely the same seed"): the run's own
-- seed (game.lua: the engine's, entropy each run, ANCHOR_SEED when set), mixed into every rng that decides what happens
-- (U.run_rng: the waves, the attacks, the gore, ...); nil keeps the fixed seeds (LICH_ROOM: the three.js build's numbers)
U.RUN = nil
function U.run_rng(seed)
  if U.RUN then seed = ((seed*2654435761) ~ U.RUN) & M32 end
  return U.make_rng(seed)
end

-- sfc32 seeded through splitmix32; rng.next() in [0, 1)
function U.make_rng(seed)
  seed = seed or 1
  local sm = splitmix(seed)
  local a, b, c, d = sm(), sm(), sm(), sm()
  local function next()
    local t = (a + b) & M32
    a = b ~ (b >> 9)
    b = (c + ((c << 3) & M32)) & M32
    c = ((c << 21) & M32) | (c >> 11)
    d = (d + 1) & M32
    t = (t + d) & M32
    c = (c + t) & M32
    return t/4294967296
  end
  for _ = 1, 12 do next() end
  local rng = { seed = seed, next = next }
  function rng.float(lo, hi) lo = lo or 0; hi = hi or 1; return lo + (hi - lo)*next() end
  function rng.int(lo, hi) return lo + floor(next()*(hi - lo + 1)) end        -- inclusive
  function rng.chance(p) return next() < p end
  function rng.sign() return next() < 0.5 and -1 or 1 end
  function rng.pick(arr) return arr[floor(next()*#arr) + 1] end
  function rng.spread(s) return (next()*2 - 1)*s end                          -- symmetric in [-s, s]
  function rng.fork(tag) return U.make_rng((seed ~ U.hash_str(tostring(tag))) & M32) end
  return rng
end

-- ---------------------------------------------------------------------------- math
local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
U.clamp = clamp
function U.lerp(a, b, t) return a + (b - a)*t end
local lerp = U.lerp
function U.inv_lerp(a, b, x) return (x - a)/(b - a) end
function U.remap(x, a, b, c, d) return c + (d - c)*clamp((x - a)/(b - a), 0, 1) end
function U.smoothstep(a, b, x) local t = clamp((x - a)/(b - a), 0, 1); return t*t*(3 - 2*t) end
function U.approach(x, target, step) if x < target then return min(x + step, target) end; return max(x - step, target) end
function U.damp(a, b, rate, dt) return lerp(a, b, 1 - exp(-rate*dt)) end
function U.ease_out_cubic(t) return 1 - (1 - t)^3 end
function U.ease_in_cubic(t) return t*t*t end
function U.ease_out_back(t, k) k = k or 1.7; return 1 + (k + 1)*(t - 1)^3 + k*(t - 1)^2 end
function U.wrap_deg(a) a = math.fmod(a + 180, 360); if a < 0 then a = a + 360 end; return a - 180 end
function U.len2(x, z) return sqrt(x*x + z*z) end
function U.len3(x, y, z) return sqrt(x*x + y*y + z*z) end
-- Math.atan2 and the JS remainder (sign of the dividend)
U.atan2 = atan
function U.fmod(a, b) return math.fmod(a, b) end
-- damped spring (semi-implicit Euler)
function U.spring(s, target, omega, zeta, dt)
  local a = -2*zeta*omega*s.v - omega*omega*(s.x - target)
  s.v = s.v + a*dt
  s.x = s.x + s.v*dt
  return s.x
end
function U.make_spring(x) return { x = x or 0, v = 0 } end

-- smooth 1D value noise in [-1, 1]
function U.noise1(x, seed)
  seed = seed or 0
  local i = floor(x); local f = x - i
  local function h(n)
    local v = imul((n + seed*7919) & M32, 0x27d4eb2d)
    v = v ~ (v >> 15); v = imul(v, 0x85ebca6b); v = v ~ (v >> 13)
    return (v & M32)/4294967296*2 - 1
  end
  local u = f*f*(3 - 2*f)
  return lerp(h(i), h(i + 1), u)
end

-- ---------------------------------------------------------------------------- the cave's noise (cave.js)
function U.h3(ix, iy, iz, seed)
  local h = imul(floor(ix), 374761393) ~ imul(floor(iy), 668265263) ~ imul(floor(iz), 2147483647) ~ imul(floor(seed), 1442695041)
  h = imul(h ~ (h >> 13), 1274126177)
  h = h ~ (h >> 16)
  return (h & M32)/4294967296
end
local h3 = U.h3
-- (the eight corners' hashes built from the per-axis products: the same bits as h3 at each corner,
-- a quarter of the multiplies; ground_y calls this ~6 times and runs every tick for every ring)
function U.noise3(x, y, z, seed)
  seed = seed or 0
  local ix, iy, iz = floor(x), floor(y), floor(z)
  local fx, fy, fz = x - ix, y - iy, z - iz
  local u, v, w = fx*fx*(3 - 2*fx), fy*fy*(3 - 2*fy), fz*fz*(3 - 2*fz)
  local ax0, ax1 = ((ix*374761393) & M32), (((ix + 1)*374761393) & M32)
  local ay0, ay1 = ((iy*668265263) & M32), (((iy + 1)*668265263) & M32)
  local az0, az1 = ((iz*2147483647) & M32), (((iz + 1)*2147483647) & M32)
  local as = (floor(seed)*1442695041) & M32
  local h, c000, c100, c010, c110, c001, c101, c011, c111
  h = ax0 ~ ay0 ~ az0 ~ as; h = ((h ~ (h >> 13))*1274126177) & M32; h = h ~ (h >> 16); c000 = (h & M32)/4294967296
  h = ax1 ~ ay0 ~ az0 ~ as; h = ((h ~ (h >> 13))*1274126177) & M32; h = h ~ (h >> 16); c100 = (h & M32)/4294967296
  h = ax0 ~ ay1 ~ az0 ~ as; h = ((h ~ (h >> 13))*1274126177) & M32; h = h ~ (h >> 16); c010 = (h & M32)/4294967296
  h = ax1 ~ ay1 ~ az0 ~ as; h = ((h ~ (h >> 13))*1274126177) & M32; h = h ~ (h >> 16); c110 = (h & M32)/4294967296
  h = ax0 ~ ay0 ~ az1 ~ as; h = ((h ~ (h >> 13))*1274126177) & M32; h = h ~ (h >> 16); c001 = (h & M32)/4294967296
  h = ax1 ~ ay0 ~ az1 ~ as; h = ((h ~ (h >> 13))*1274126177) & M32; h = h ~ (h >> 16); c101 = (h & M32)/4294967296
  h = ax0 ~ ay1 ~ az1 ~ as; h = ((h ~ (h >> 13))*1274126177) & M32; h = h ~ (h >> 16); c011 = (h & M32)/4294967296
  h = ax1 ~ ay1 ~ az1 ~ as; h = ((h ~ (h >> 13))*1274126177) & M32; h = h ~ (h >> 16); c111 = (h & M32)/4294967296
  local a = c000 + (c100 - c000)*u
  local b = c010 + (c110 - c010)*u
  local c = c001 + (c101 - c001)*u
  local d = c011 + (c111 - c011)*u
  local e = a + (b - a)*v
  return e + ((c + (d - c)*v) - e)*w
end
local noise3 = U.noise3
function U.fbm3_lua(x, y, z, seed, oct)
  oct = oct or 3
  local s, a, t, f = 0, 1, 0, 1
  for o = 0, oct - 1 do s = s + a*noise3(x*f, y*f, z*f, seed + o*31); t = t + a; a = a*0.5; f = f*2.03 end
  return s/t
end
-- (the engine's noise_value3 / noise_fbm3 compute the same bits, ~10x faster; the Lua versions
-- above stay as the reference)
U.noise3_lua = U.noise3
if noise_value3 then
  U.noise3 = function(x, y, z, seed) return noise_value3(x, y, z, seed or 0) end
  U.fbm3 = function(x, y, z, seed, oct) return noise_fbm3(x, y, z, seed, oct or 3) end
else
  U.fbm3 = U.fbm3_lua
end

return U
