--[[
  snakes.lua -- the port to Anchor: web/src/snakes.js. The snakes: one tube mesh each, rebuilt
  every tick along its head's trail (the body follows exactly where the head went), the front
  lifted into a neck curve, glossy scales, dark eyes. They come out of the dark toward the egg;
  set on fire they stop, char and sink (fire.lua); other powers take them (s.fx); one that reaches
  the egg coils round it (coil.lua), and the egg is won when they cover it.
  Rings are 0-based in the formulas (S_AT(i)) and 1-based in the tables (spine[i + 1]).
  The coiled bodies lie over each other through a grid over their rings (the same lifts as
  snakes.js's search over every pair).
  Round 50 (owner, 2026-10-05: "snakes are spawning all at the same time often"): with opts.varied
  (the game's default; LICH_ROOM=1 keeps the old flow, the three.js build's) a snake that dies waits
  in a pool, and a wave director sends them: ONE, a PAIR, a PACK from one side, a SPREAD from several
  sides at once, a STREAM in a line, with quiet stretches between (WAVES below).
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local U = require('port.util')
local FX = require('port.fx')
local CL = require('port.coil')
local Vector3, Color = TM.Vector3, TM.Color
local clamp, smoothstep, lerp = U.clamp, U.smoothstep, U.lerp
local sqrt, abs, sin, cos, atan2, exp, floor, ceil, min, max, huge, pi = math.sqrt, math.abs, math.sin, math.cos, math.atan, math.exp, math.floor, math.ceil, math.min, math.max, math.huge, math.pi

local SN = {}
local LEN, R0 = 4.4, 0.08
local RINGS, SIDES = 72, 12
local RAISE, RAISE_LEN = 0.34, 1.1
local function S_AT(i) return LEN*((i/(RINGS - 1))^1.6) end
local function I_AT(sl) return (RINGS - 1)*((sl/LEN)^(1/1.6)) end
SN.LEN, SN.RINGS, SN.SIDES, SN.S_AT, SN.I_AT = LEN, RINGS, SIDES, S_AT, I_AT

local function radius_at(s)
  if s < 0.012 then return lerp(0.18, 0.45, s/0.012) end
  if s < 0.05 then return lerp(0.45, 0.82, (s - 0.012)/0.038) end
  if s < 0.085 then return lerp(0.82, 0.95, (s - 0.05)/0.035) end
  if s < 0.115 then return lerp(0.95, 0.68, (s - 0.085)/0.03) end
  if s < 0.3 then return lerp(0.68, 0.98, smoothstep(0.115, 0.3, s)) end
  local tail0 = LEN*0.62
  if s < tail0 then return 1.0 end
  return lerp(1.0, 0.07, ((s - tail0)/(LEN - tail0))^0.85)
end
SN.radius_at = radius_at
local SINK_T, SINK_D = 1.5, 0.34
local RESPAWN = { 2.0, 5.0 }
local function sink_depth(s) return s.sink < 0 and 0 or SINK_D*smoothstep(0, SINK_T, s.sink) end
local function flat_at(s) return s < 0.11 and 0.62 or lerp(0.62, 0.84, smoothstep(0.11, 0.3, s)) end
local WRAP_SPEED, CHURN, CHURN_T, WIN = 0.72, 0.34, 3.0, 0.97
local LIFT_K, LIFT_MAX, HEAD_UP, HEAD_LEN = 0.6, 0.2, 0.15, 0.55
local COIL_OFF = CL.OFF
-- (snakes.js keeps the radii and the coil's per-ring numbers in Float32Arrays: stored values are rounded to float32)
local F32 = js_fround

-- per-ring constants (the same for every snake)
local SA, RAD, FLAT = {}, {}, {}
for i = 0, RINGS - 1 do SA[i + 1] = S_AT(i); RAD[i + 1] = radius_at(SA[i + 1]); FLAT[i + 1] = flat_at(SA[i + 1]) end
-- the section's corners (snakes.js computes the same sin/cos per vertex)
local CXS, CYS = {}, {}
for j = 0, SIDES - 1 do local ang = j/SIDES*math.pi*2; CXS[j + 1] = math.sin(ang); CYS[j + 1] = -math.cos(ang) end

SN.WAVES = { 'ONE', 'PAIR', 'PACK', 'SPREAD', 'STREAM' }
local WAVE_W = { 2.2, 2.0, 2.4, 1.4, 1.1 }

function SN.create(R, cave, get_lich_pos, fire, count, seed, opts)
  count = count or 8; seed = seed or 5
  local rng = U.make_rng(seed)
  local varied = opts and opts.varied or false
  local wrng = U.make_rng(seed*977 + 3)          -- the waves' own draws (the old flow's rng stays as it was)
  local A = R.statics
  local mat = MAT.MeshStandardMaterial.new({ name = 'snakes.body', map = A.texture('snake_scales'), roughness = 0.3, metalness = 0.0 })
  local uEmber, uSnakeT = { value = Color.new(3.2, 0.75, 0.1) }, { value = 0 }
  mat.custom = { uEmber = uEmber, uSnakeT = uSnakeT }
  if cave.GU then FX.gi_dynamic(mat, cave.GU) end
  local eye_mat = MAT.MeshStandardMaterial.new({ name = 'snakes.eye', color = 0x0b0a08, roughness = 0.08, metalness = 0.0 })
  local eye_geo = A.geometry('sphere_1_8_6')
  local egg = cave.egg.position
  local S = {}
  local coil = CL.create({ centre = { egg.x, egg.y + 0.4, egg.z }, ground_y = cave.ground_y, rng = U.make_rng(seed*131 + 7), len = LEN })
  local coiled = {}
  local coil_mode, cover_tick = 0, 0
  local covered_mask = {}
  for k = 1, #coil.samples do covered_mask[k] = 0 end
  local api

  -- the index and uv every tube shares
  local NV = RINGS*SIDES + 2
  local IDX, UV = {}, {}
  for i = 0, RINGS - 1 do for j = 0, SIDES - 1 do local o = (i*SIDES + j)*2; UV[o + 1] = j/SIDES; UV[o + 2] = S_AT(i)*4 end end
  UV[NV*2 - 3], UV[NV*2 - 2], UV[NV*2 - 1], UV[NV*2] = 0, 0, 0, 0
  for i = 0, RINGS - 2 do for j = 0, SIDES - 1 do
    local a, b, c, d = i*SIDES + j, i*SIDES + (j + 1)%SIDES, (i + 1)*SIDES + (j + 1)%SIDES, (i + 1)*SIDES + j
    local o = #IDX
    IDX[o + 1], IDX[o + 2], IDX[o + 3], IDX[o + 4], IDX[o + 5], IDX[o + 6] = a, d, c, a, c, b
  end end
  do
    local tip, en = RINGS*SIDES, RINGS*SIDES + 1
    for j = 0, SIDES - 1 do
      local o = #IDX
      IDX[o + 1], IDX[o + 2], IDX[o + 3] = tip, (j + 1)%SIDES, j
      IDX[o + 4], IDX[o + 5], IDX[o + 6] = en, (RINGS - 1)*SIDES + j, (RINGS - 1)*SIDES + (j + 1)%SIDES
    end
  end

  local function make_mesh()
    local g = T.BufferGeometry.new()
    -- (position and normal live in gpu buffers, written by gpu_tube and uploaded by copy)
    g:set_attribute('position', T.BufferAttribute.new(gpu_buffer(NV*3), 3))
    g:set_attribute('normal', T.BufferAttribute.new(gpu_buffer(NV*3), 3))
    local uv = {}
    for k = 1, #UV do uv[k] = UV[k] end
    g:set_attribute('uv', T.BufferAttribute.new(uv, 2))
    g:set_attribute('aBurn', T.float_attr(NV, 3))
    local idx = {}
    for k = 1, #IDX do idx[k] = IDX[k] end
    g:set_index(idx)
    local m = T.Mesh.new(g, mat)
    m.cast_shadow = true; m.receive_shadow = true; m.frustum_culled = false
    R.world_scene:add(m)
    local eyes = {}
    for k = 1, 2 do local e = T.Mesh.new(eye_geo, eye_mat); e.cast_shadow = false; R.world_scene:add(e); eyes[k] = e end
    local spine, radii = {}, {}
    for i = 1, RINGS do spine[i] = Vector3.new(); radii[i] = 0 end
    return { m = m, eyes = eyes, spine = spine, radii = radii }
  end

  local function set_vis(s, v) s.m.visible = v; s.eyes[1].visible = v; s.eyes[2].visible = v end

  -- w (round 50, the waves): { th = angle, speed = m/s }, drawn with the waves' rng; nil = the old draws
  local function spawn(s, delay, w)
    local g = w and wrng or rng
    local th = w and w.th
    if not th then repeat th = g.float(0, pi*2) until not (abs(atan2(sin(th + pi/2), cos(th + pi/2))) < 0.5) end
    local r = g.float(14.0, 15.8)
    s.x = cos(th)*r; s.z = sin(th)*r
    s.dir = atan2(-s.z, -s.x) + g.spread(0.3)
    s.phase = g.float(0, 6.28); s.speed = g.float(1.0, 1.35)
    if w and w.speed then s.speed = w.speed end
    s.wave = g.float(0.95, 1.2)
    s.amp = g.float(0.55, 0.75)
    s.pooled = false
    s.trail = {}
    for i = 0, 399 do s.trail[i + 1] = { s.x - cos(s.dir)*i*0.01, s.z - sin(s.dir)*i*0.01 } end
    -- (each point keeps [3] = its distance to the next: the walks along the trail read it)
    for i = 1, 399 do local a, b = s.trail[i], s.trail[i + 1]; a[3] = js_hypot(b[1] - a[1], b[2] - a[2]) end
    s.dying = -1; s.delay = delay; s.scale = 1; s.dist = 0
    s.burn = nil; s.sag = 0; s.sink = -1; s.burnt = false
    s.fx = nil; s.leak = 0; s.leak_at = nil; s.claim = nil; s.coil = nil
    local ab = s.m.geometry.attributes.aBurn
    local a = ab.array
    for k = 1, #a do a[k] = 0 end
    ab.needs_update = true
  end
  -- round 50: the pool and the waves. A snake that dies (or a new one for the count) waits hidden
  -- until a wave sends it; a wave picks its shape, its side(s), its pace, then a gap before the next.
  local POOLED = huge
  local function to_pool(s) s.delay = POOLED; s.pooled = true; s.fx = nil; s.burn = nil; s.sink = -1; s.dying = -1; s.coil = nil; s.claim = nil; s.leak = 0; s.leak_at = nil; s.scale = 1; s.sag = 0; s.burnt = false; set_vis(s, false) end
  local function valid_th(th) return not (abs(atan2(sin(th + pi/2), cos(th + pi/2))) < 0.55) end
  local function side_th()
    local th
    repeat th = wrng.float(0, pi*2) until valid_th(th)
    return th
  end
  local DIR = { next = 0.4, n = 0, log = {}, force = nil, last = nil, lull = false, clock = 0 }
  local function pooled() local out = {}; for _, s in ipairs(S) do if s.pooled then out[#out + 1] = s end end; return out end
  -- the arrivals of one wave: a list of { delay, angle, speed }, and the gap before the next wave
  local function plan_wave(kind, avail)
    local out, gap = {}, 0
    local base = wrng.float(1.0, 1.3)
    if kind == 'ONE' then
      out[1] = { 0, side_th(), wrng.float(1.0, 1.35) }
      gap = wrng.float(1.4, 3.2)
    elseif kind == 'PAIR' then
      local c = side_th()
      for k = 1, 2 do
        local th
        repeat th = c + wrng.spread(0.45) until valid_th(th)
        out[k] = { (k - 1)*wrng.float(0.3, 1.1), th, base + wrng.spread(0.06) }
      end
      gap = wrng.float(2.4, 4.4)
    elseif kind == 'PACK' then
      local n = min(avail, wrng.int(3, 5))
      local c = side_th()
      for k = 1, n do
        local th
        repeat th = c + wrng.spread(0.26) until valid_th(th)
        out[k] = { wrng.float(0, 0.7), th, base + wrng.spread(0.04) }
      end
      gap = wrng.float(4.0, 7.0)
    elseif kind == 'SPREAD' then
      local n = min(avail, wrng.int(3, 4))
      local c = wrng.float(0, pi*2)
      for k = 1, n do
        local th = c + (k - 1)*pi*2/n + wrng.spread(0.3)
        local tries = 0
        while not valid_th(th) and tries < 20 do th = th + 0.2; tries = tries + 1 end
        out[k] = { wrng.float(0, 0.5), th, base + wrng.spread(0.05) }
      end
      gap = wrng.float(4.0, 6.5)
    else -- STREAM: one after another along one line
      local n = min(avail, wrng.int(4, 6))
      local c = side_th()
      local step = wrng.float(0.7, 1.2)
      for k = 1, n do
        local th
        repeat th = c + wrng.spread(0.12) until valid_th(th)
        out[k] = { (k - 1)*step, th, base }
      end
      gap = (n - 1)*step + wrng.float(2.0, 4.0)
    end
    return out, gap
  end
  local function send_wave(kind)
    local pool = pooled()
    if #pool == 0 then return nil end
    if kind == nil then
      local tot = 0
      for k = 1, #SN.WAVES do tot = tot + WAVE_W[k] end
      repeat
        local r = wrng.next()*tot
        kind = SN.WAVES[#SN.WAVES]
        for k = 1, #SN.WAVES do r = r - WAVE_W[k]; if r <= 0 then kind = SN.WAVES[k]; break end end
      until kind ~= DIR.last or kind == 'ONE'             -- (no two big waves of the same shape in a row)
    end
    -- a wave bigger than the pool waits until it can come whole (a pack of one is no pack)
    local need = (kind == 'ONE' and 1) or (kind == 'PAIR' and 2) or (kind == 'STREAM' and 4) or 3
    if #pool < need then return nil end
    local plan, gap = plan_wave(kind, #pool)
    for k, a in ipairs(plan) do spawn(pool[k], a[1], { th = a[2], speed = a[3] }) end
    DIR.n = DIR.n + 1; DIR.last = kind
    DIR.log[#DIR.log + 1] = { kind = kind, n = #plan, t = DIR.clock }
    if #DIR.log > 40 then table.remove(DIR.log, 1) end
    DIR.lull = wrng.next() < 0.22
    return gap + (DIR.lull and wrng.float(3.0, 6.0) or 0)
  end
  local function direct(dt)
    DIR.clock = DIR.clock + dt
    if DIR.force then
      local g = send_wave(DIR.force)
      if g then DIR.force = nil; DIR.next = max(DIR.next, g) end
    end
    DIR.next = DIR.next - dt
    if DIR.next > 0 then return end
    local g = send_wave()
    DIR.next = g or 0.5
  end

  if varied then
    for _ = 0, count - 1 do local s = make_mesh(); spawn(s, 0); to_pool(s); S[#S + 1] = s end
  else
    for i = 0, count - 1 do local s = make_mesh(); spawn(s, i*1.6); S[#S + 1] = s end
  end
  local function respawn(s)
    if varied then to_pool(s) else spawn(s, rng.float(RESPAWN[1], RESPAWN[2])) end
  end

  local P, UU = {}, {}
  local Tv, Nn, Bn, UP = Vector3.new(), Vector3.new(), Vector3.new(0, 1, 0), Vector3.new(0, 1, 0)
  Bn:set(0, 0, 0)
  local RK, GL, SH, RR = {}, {}, { 0, 0, 0 }, {}
  local TUBE = { sides = SIDES, belly = 0.8, up = { 0, 1, 0 } }
  for i = 1, RINGS do P[i] = Vector3.new(); UU[i] = Vector3.new(0, 1, 0); RK[i] = 0; GL[i] = 0 end

  local function free(s) return s.delay <= 0 and s.dying < 0 and not s.burn and s.sink < 0 and not s.fx and not s.coil end

  -- ------------------------------------------------------------------ the coil (round 36)
  local function start_coil(s)
    local hx, hz = s.x, s.z
    local hd = { cos(s.dir), sin(s.dir) }
    local d_b = coil.base_dir(hx, hz, R0*flat_at(1))
    local bp = coil.lifted(d_b, COIL_OFF, { 0, 0, 0 })
    local dist = js_hypot(bp[1] - hx, bp[3] - hz)
    local k = min(0.45, dist*0.5)
    local cx, cz = hx + hd[1]*k, hz + hd[2]*k
    local n = max(4, ceil(dist/0.02))
    local gx, gz, garc = {}, {}, { 0 }
    for i = 0, n do
      local f = i/n
      local a, b, c = (1 - f)*(1 - f), 2*(1 - f)*f, f*f
      gx[i + 1] = a*hx + b*cx + c*bp[1]; gz[i + 1] = a*hz + b*cz + c*bp[3]
      if i > 0 then garc[i + 1] = garc[i] + js_hypot(gx[i + 1] - gx[i], gz[i + 1] - gz[i]) end
    end
    local g_len = garc[n + 1]
    local planned = {}
    for q, o in ipairs(coiled) do planned[q] = o.coil.band end
    local plan = coil.plan(coil_mode, d_b, hd, planned, covered_mask)
    local B, st, sa = plan.band, plan.stem, plan.stem_arc
    local st_len = sa[#sa]
    local dirs, earc = {}, {}
    for _, d in ipairs(st) do dirs[#dirs + 1] = d end
    for q = 2, #B.dirs do dirs[#dirs + 1] = B.dirs[q] end
    for _, a in ipairs(sa) do earc[#earc + 1] = g_len + a end
    for q = 2, #B.arc do earc[#earc + 1] = g_len + st_len + B.arc[q] end
    local band_at = g_len + st_len
    local function mk() local t = {}; for i = 1, RINGS do t[i] = { 0, 0, 0 } end; return t end
    local function zf() local t = {}; for i = 1, RINGS do t[i] = 0 end; return t end
    local on = {}
    for i = 1, RINGS do on[i] = false end
    s.coil = { phase = 'wrap', t = 0, set_t = 0, order = #coiled, band = B, gx = gx, gz = gz, garc = garc, e0 = g_len, dirs = dirs, earc = earc, band_at = band_at,
      Qlen = earc[#earc], h = 0, v = WRAP_SPEED*s.speed, alpha = 0, spin = coil_mode == 1 and 1 or rng.float(0.8, 1.2),
      foot = mk(), nrm = mk(), gp = mk(), rad = zf(), fl = zf(), off = zf(), lift = zf(), hgt = zf(), ue = zf(), on = on }
    s.claim = nil
    coiled[#coiled + 1] = s
    if api.on_coil then api.on_coil(s) end
    if not api.won then
      local q = make_mesh()
      if varied then spawn(q, 0); to_pool(q) else spawn(q, rng.float(1.0, 3.0)) end
      S[#S + 1] = q
    end
  end

  local function coil_tick(s, dt)
    local c = s.coil
    c.t = c.t + dt
    set_vis(s, true)
    if c.phase == 'wrap' then
      local was = c.h
      c.h = min(c.Qlen, c.h + c.v*dt)
      if was < c.e0 and c.h >= c.e0 and api.on_grip then api.on_grip(s) end
      if c.h - LEN >= c.band_at - 0.02 or c.h >= c.Qlen then c.h = c.Qlen; c.phase = 'set' end
    else
      c.set_t = c.set_t + dt
      local v = lerp(c.v, CHURN, smoothstep(0, CHURN_T, c.set_t))
      c.alpha = c.alpha + c.band.sigma*v/c.band.rho*c.spin*dt
    end
  end

  local DQ = { 0, 0, 0 }
  local function coil_base(s)
    local c = s.coil
    -- set (wound and turning with its band): every ring's place on the band before the turn is
    -- fixed (c.h no longer moves), worked out once (below) and kept in c.cdir; each tick only turns it
    if c.phase == 'set' and c.cdir_done then
      local ax = c.band.axis
      local ca, sn = cos(c.alpha), sin(c.alpha)
      local rot = c.alpha ~= 0
      local a1, a2, a3 = ax[1], ax[2], ax[3]
      for i = 1, RINGS do
        if c.on[i] then
          local cd = c.cdir[i]
          local x, y, z = cd[1], cd[2], cd[3]
          if rot then
            local kd = a1*x + a2*y + a3*z
            local cx, cy, cz = a2*z - a3*y, a3*x - a1*z, a1*y - a2*x
            x, y, z = x*ca + cx*sn + a1*kd*(1 - ca), y*ca + cy*sn + a2*kd*(1 - ca), z*ca + cz*sn + a3*kd*(1 - ca)
          end
          local l = js_hypot(x, y, z); if l == 0 then l = 1 end
          DQ[1] = x/l; DQ[2] = y/l; DQ[3] = z/l
          coil.surface(DQ, c.foot[i], c.nrm[i])
        end
      end
      return
    end
    if c.phase == 'set' then
      c.cdir = {}
      for i = 1, RINGS do c.cdir[i] = { 0, 0, 0 } end
      c.cdir_done = true
    end
    local Aa, D = c.earc, c.dirs
    local ax = c.band.axis
    local ca, sn = cos(c.alpha), sin(c.alpha)
    local rot = c.phase == 'set' and c.alpha ~= 0
    local raise = 1 - smoothstep(0, 0.5, c.h)
    local ti, acc = 0, 0                         -- ti 0-based into the trail
    local NA = #Aa
    local trail = s.trail
    local NT = #trail
    for i = 0, RINGS - 1 do
      local sa = SA[i + 1]
      local q = c.h - sa
      local r, fl = R0*RAD[i + 1], FLAT[i + 1]
      c.rad[i + 1] = F32(r); c.fl[i + 1] = F32(fl); c.off[i + 1] = F32(r*fl*0.8 + 0.004)
      if q >= c.e0 then
        local lo, hi = 0, NA - 1
        if q >= Aa[hi + 1] then lo = hi - 1
        else while hi - lo > 1 do local m = (lo + hi) >> 1; if Aa[m + 1] < q then lo = m else hi = m end end end
        local a, b = D[lo + 1], D[lo + 2]
        local den = Aa[lo + 2] - Aa[lo + 1]; if den == 0 then den = 1 end
        local f = clamp((q - Aa[lo + 1])/den, 0, 1)
        local x, y, z = a[1] + (b[1] - a[1])*f, a[2] + (b[2] - a[2])*f, a[3] + (b[3] - a[3])*f
        if c.phase == 'set' then local cd = c.cdir[i + 1]; cd[1], cd[2], cd[3] = x, y, z end
        if rot then
          local kd = ax[1]*x + ax[2]*y + ax[3]*z
          local cx, cy, cz = ax[2]*z - ax[3]*y, ax[3]*x - ax[1]*z, ax[1]*y - ax[2]*x
          x, y, z = x*ca + cx*sn + ax[1]*kd*(1 - ca), y*ca + cy*sn + ax[2]*kd*(1 - ca), z*ca + cz*sn + ax[3]*kd*(1 - ca)
        end
        local l = js_hypot(x, y, z); if l == 0 then l = 1 end
        DQ[1] = x/l; DQ[2] = y/l; DQ[3] = z/l
        coil.surface(DQ, c.foot[i + 1], c.nrm[i + 1])
        c.on[i + 1] = true; c.ue[i + 1] = F32(smoothstep(c.e0, c.e0 + 0.3, q))
      else
        local x, z
        if q >= 0 then
          local G = c.garc
          local j = 1                              -- 0-based as in snakes.js
          while j < #G - 1 and G[j + 1] < q do j = j + 1 end
          local den = G[j + 1] - G[j]; if den == 0 then den = 1 end
          local f = clamp((q - G[j])/den, 0, 1)
          x = c.gx[j] + (c.gx[j + 1] - c.gx[j])*f; z = c.gz[j] + (c.gz[j + 1] - c.gz[j])*f
        else
          local want = -q
          x = trail[NT][1]; z = trail[NT][2]
          while ti < NT - 1 do
            local a, b = trail[ti + 1], trail[ti + 2]
            local l = a[3]
            if acc + l >= want then local f = (want - acc)/(l == 0 and 1 or l); x = a[1] + (b[1] - a[1])*f; z = a[2] + (b[2] - a[2])*f; break end
            acc = acc + l; ti = ti + 1
          end
        end
        local lift = RAISE*smoothstep(RAISE_LEN, 0.05, sa)*raise
        local g = c.gp[i + 1]
        g[1] = x; g[2] = cave.ground_y(x, z) + r*fl + lift; g[3] = z
        c.on[i + 1] = false
      end
    end
  end

  -- each lies over the ones before it (a grid over the earlier bodies' rings finds the crossings)
  local GC = 0.15                                 -- over the largest reach (2*R0*0.9 = 0.144)
  local function gkey(ix, iy, iz) return (ix + 512)*1048576 + (iy + 512)*1024 + (iz + 512) end
  local function stack_lifts()
    local grid = {}
    for k = 1, #coiled do
      local c = coiled[k].coil
      local Lf = c.lift
      for i = 1, RINGS do Lf[i] = 0 end
      if k > 1 then
        for i = 1, RINGS do
          if c.on[i] then
            local f, ri = c.foot[i], c.rad[i]
            local bi = ri*c.fl[i]*0.8
            -- the cells the reach of any ring of radius <= R0 can touch
            local Rq = (ri + R0)*0.9
            local fx, fy, fz = f[1], f[2], f[3]
            for ix = floor((fx - Rq)/GC), floor((fx + Rq)/GC) do for iy = floor((fy - Rq)/GC), floor((fy + Rq)/GC) do for iz = floor((fz - Rq)/GC), floor((fz + Rq)/GC) do
              local list = grid[gkey(ix, iy, iz)]
              if list then
                for q = 1, #list, 2 do
                  local o, m = list[q], list[q + 1]
                  local g = o.foot[m]
                  local ex, ey, ez = fx - g[1], fy - g[2], fz - g[3]
                  local Dl = (ri + o.rad[m])*0.9
                  local d2 = ex*ex + ey*ey + ez*ez
                  if d2 < Dl*Dl then
                    local need = (o.hgt[m] + (bi + o.rad[m]*o.fl[m])*sqrt(1 - d2/(Dl*Dl)) - c.off[i])*LIFT_K
                    if need > Lf[i] then Lf[i] = F32(need) end
                  end
                end
              end
            end end end
          end
        end
      end
      for _ = 1, 3 do
        local prev = Lf[1]
        for i = 1, RINGS do
          local cur = Lf[i]
          local nx = i < RINGS and Lf[i + 1] or cur
          Lf[i] = F32(max(cur, 0.5*cur + 0.25*(prev + nx)))
          prev = cur
        end
      end
      for i = 1, RINGS do c.hgt[i] = F32(c.off[i] + min(LIFT_MAX, Lf[i])) end
      -- this body's rings join the grid for the ones after it
      for m = 1, RINGS do
        if c.on[m] then
          local g = c.foot[m]
          local key = gkey(floor(g[1]/GC), floor(g[2]/GC), floor(g[3]/GC))
          local list = grid[key]
          if not list then list = {}; grid[key] = list end
          list[#list + 1] = c; list[#list + 1] = m
        end
      end
    end
  end

  local function coil_place(s)
    local c = s.coil
    for i = 1, RINGS do
      if c.on[i] then
        local f, n = c.foot[i], c.nrm[i]
        local h = c.hgt[i] + HEAD_UP*smoothstep(HEAD_LEN, 0.06, SA[i])*c.ue[i]
        P[i]:set(f[1] + n[1]*h, f[2] + n[2]*h, f[3] + n[3]*h)
        UU[i]:set(n[1], n[2], n[3]):lerp(UP, 1 - c.ue[i]):normalize()
      else
        local g = c.gp[i]
        P[i]:set(g[1], g[2], g[3])
        UU[i]:copy(UP)
      end
      s.spine[i]:copy(P[i]); s.radii[i] = c.rad[i]
    end
    s.x = P[1].x; s.z = P[1].z
  end

  -- the spine: points along the trail by arc length, the front raised into a neck curve
  local function build(s)
    local acc, ti = 0, 0
    local sc, fx = s.scale, s.fx
    local f = s.leak*1.12
    local ac = S_AT(s.leak_at or 0)
    local ext = max(ac, LEN - ac, 0.5)
    for i = 0, RINGS - 1 do
      local u = abs(SA[i + 1] - ac)/ext
      RK[i + 1] = s.leak > 0 and F32(smoothstep(f, f + 0.1, u)) or 1
      GL[i + 1] = s.leak > 0 and F32(min(1, 0.62*exp(-(((u - f)/0.04)^2)) + 0.4*(1 - smoothstep(f, f + 0.12, u))*min(1, s.leak*4))) or 0
      if fx then
        if fx.radk then RK[i + 1] = F32(RK[i + 1]*fx.radk(i)) end
        if fx.glow then GL[i + 1] = F32(max(GL[i + 1], fx.glow(i))) end
      end
    end
    if s.coil then coil_place(s)
    else
      local trail = s.trail
      local NT = #trail
      for i = 0, RINGS - 1 do
        UU[i + 1]:copy(UP)
        local target = SA[i + 1]
        local x, z = trail[NT][1], trail[NT][2]
        while ti < NT - 1 do
          local a, b = trail[ti + 1], trail[ti + 2]
          local l = a[3]
          if acc + l >= target then local ff = (target - acc)/(l == 0 and 1 or l); x = a[1] + (b[1] - a[1])*ff; z = a[2] + (b[2] - a[2])*ff; break end
          acc = acc + l; ti = ti + 1
        end
        local r = R0*RAD[i + 1]*sc*RK[i + 1]
        local lift = RAISE*smoothstep(RAISE_LEN, 0.05, target)*sc*(1 - smoothstep(0, 1, s.sag))
        SH[1], SH[2], SH[3] = 0, 0, 0
        if fx then
          if fx.sag ~= nil then lift = lift*(1 - fx.sag) end
          if fx.lift then lift = lift + fx.lift(i) end
          if fx.shift then fx.shift(i, SH) end
        end
        P[i + 1]:set(x + SH[1], cave.ground_y(x, z) + R0*RAD[i + 1]*sc*FLAT[i + 1] + lift + SH[2] - sink_depth(s), z + SH[3])
        if fx and fx.place then fx.place(i, P[i + 1]) end
        s.spine[i + 1]:copy(P[i + 1]); s.radii[i + 1] = F32(r)
      end
    end
    local glowing = s.leak > 0 or (fx and fx.glow)
    local charred = s.burn or s.burnt or (fx and fx.char)
    if charred or glowing or s.fxw then
      local ab = s.m.geometry.attributes.aBurn
      local a = ab.array
      for i = 0, RINGS - 1 do
        local c = s.burn and fire.char(s.burn, i) or (s.burnt and 1 or 0)
        local e = s.burn and fire.ember(s.burn, i) or 0
        if fx and fx.char then c = max(c, fx.char(i)); e = max(e, fx.ember and fx.ember(i) or 0) end
        for j = 0, SIDES - 1 do local o = (i*SIDES + j)*3; a[o + 1] = c; a[o + 2] = e; a[o + 3] = GL[i + 1] end
      end
      local tip, last = RINGS*SIDES*3, (RINGS - 1)*SIDES*3
      for k = 1, 3 do a[tip + k] = a[k]; a[tip + 3 + k] = a[last + k] end
      ab.needs_update = true
      s.fxw = (charred or glowing) and true or false
    end
    local pos, nor = s.m.geometry.attributes.position.array, s.m.geometry.attributes.normal.array
    for i = 1, RINGS do RR[i] = R0*RAD[i]*sc*RK[i] end
    gpu_tube(pos, nor, P, UU, RR, FLAT, TUBE)
    local tip = RINGS*SIDES*3
    local en = tip + 3
    Tv:sub_vectors(P[1], P[2]):normalize()
    local tr = R0*0.25*sc*RK[1]
    pos[tip + 1] = P[1].x + Tv.x*tr; pos[tip + 2] = P[1].y + Tv.y*tr; pos[tip + 3] = P[1].z + Tv.z*tr
    nor[tip + 1] = Tv.x; nor[tip + 2] = Tv.y; nor[tip + 3] = Tv.z
    pos[en + 1] = P[RINGS].x; pos[en + 2] = P[RINGS].y; pos[en + 3] = P[RINGS].z
    nor[en + 1] = -Tv.x; nor[en + 2] = 0; nor[en + 3] = -Tv.z
    s.m.geometry.attributes.position.needs_update = true
    s.m.geometry.attributes.normal.needs_update = true
    -- the eyes: on the sides of the head, a little up
    local ei = floor(I_AT(0.055) + 0.5)
    local a, b = P[max(0, ei - 1) + 1], P[ei + 2]
    Tv:sub_vectors(a, b):normalize(); Bn:cross_vectors(Tv, UU[ei + 1]):normalize(); Nn:cross_vectors(Bn, Tv):normalize()
    local rr = R0*radius_at(0.055)*sc*RK[ei + 1]
    for k = 1, 2 do
      local e = s.eyes[k]
      local side = k == 2 and 1 or -1
      e.position:copy(P[ei + 1]):add_scaled_vector(Bn, side*rr*0.8):add_scaled_vector(Nn, rr*0.18)
      e.scale:set_scalar(R0*0.12*sc*RK[ei + 1])
    end
  end

  local function update(t, dt)
    uSnakeT.value = t
    if varied and not api.won then direct(dt) end
    local n = #S
    local k = 1
    while k <= #S do
      local s = S[k]
      local skip = false
      if s.delay > 0 then s.delay = s.delay - dt; set_vis(s, false); skip = true end
      if not skip then
        local hide = not not (s.fx and s.fx.hide)
        set_vis(s, not hide)
        if s.coil then coil_tick(s, dt); skip = true end
      end
      if not skip then
        if s.sink >= 0 then
          s.sink = s.sink + dt
          if s.sink > SINK_T then respawn(s); skip = true end
        elseif s.burn then
          s.sag = min(1, s.sag + dt/1.6)
          if s.burn.done then s.burn = nil; s.burnt = true; s.sink = 0; build(s); fire.ash(s.spine, RINGS) end
        elseif s.dying >= 0 then
          s.dying = s.dying + dt
          s.scale = clamp(1 - s.dying/0.5, 0, 1)
          if s.dying > 0.5 then respawn(s) end
        elseif s.fx then
          local r = s.fx.tick and s.fx.tick(dt, s) or nil
          if r == 'done' then respawn(s); skip = true
          elseif r == 'free' then s.fx = nil end
        else
          local sp = s.speed*(1 - 0.85*smoothstep(0, 0.8, s.leak))
          s.dist = s.dist + sp*dt
          local want = atan2(egg.z - s.z, egg.x - s.x) + sin(s.dist/s.wave*pi*2 + s.phase)*s.amp
          local d = want - s.dir
          d = atan2(sin(d), cos(d))
          s.dir = s.dir + clamp(d, -5*dt, 5*dt)
          s.x = s.x + cos(s.dir)*sp*dt; s.z = s.z + sin(s.dir)*sp*dt
          local last = s.trail[1]
          if js_hypot(s.x - last[1], s.z - last[2]) > 0.01 then
            table.insert(s.trail, 1, { s.x, s.z, js_hypot(last[1] - s.x, last[2] - s.z) })
          end
          if #s.trail > 600 then for q = #s.trail, 601, -1 do s.trail[q] = nil end end
          if js_hypot(s.x - egg.x, s.z - egg.z) < 1.1 then
            api.reached = api.reached + 1
            api.reach_log[#api.reach_log + 1] = { t = t, claim = s.claim, ['until'] = s.claim_until, leak = s.leak, speed = s.speed }
            start_coil(s)
            skip = true
          end
        end
      end
      if not skip then
        if s.leak >= 1.12 and not s.burn and s.sink < 0 then
          api.dissolved = api.dissolved + 1
          if api.on_dissolve then api.on_dissolve(s) end
          respawn(s)
        else
          build(s)
        end
      end
      k = k + 1
    end
    if #coiled > 0 then
      for _, q in ipairs(coiled) do coil_base(q) end
      stack_lifts()
      for _, q in ipairs(coiled) do build(q) end
      cover_tick = cover_tick + 1
      if cover_tick % 6 == 0 then
        local bodies = {}
        for q, o in ipairs(coiled) do bodies[q] = o.coil end
        api.coverage = coil.coverage(bodies, covered_mask)
        if not api.won and api.coverage >= WIN then api.won = true; api.won_t = t; if api.on_won then api.on_won() end end
      end
    end
  end

  local function ignite(s, at)
    if at == nil then at = floor(RINGS*rng.float(0.15, 0.75) + 0.5) end
    if not free(s) then return false end
    at = max(0, min(RINGS - 1, at))
    s.burn = fire.start(RINGS, s.spine, s.radii, at)
    return true
  end
  local function take(s, fx) if not free(s) then return false end; s.fx = fx; return true end
  local function live() local out = {}; for _, s in ipairs(S) do if free(s) then out[#out + 1] = s end end; return out end
  local function set_ember(c) uEmber.value:set_rgb(c[1], c[2], c[3]) end

  api = { update = update, S = S, ignite = ignite, LEN = LEN, take = take, live = live, free = free, set_ember = set_ember, respawn = respawn,
    RINGS = RINGS, SIDES = SIDES, mat = mat, egg = egg, reach_log = {}, arc = S_AT, ring_at = I_AT, reached = 0, dissolved = 0,
    on_dissolve = nil, coil = coil, coiled = coiled, WIN = WIN, on_coil = nil, on_grip = nil, on_won = nil,
    coverage = 0, won = false, won_t = -1, coil_mode = 0 }
  function api.set_coil_mode(i) coil_mode = ((i % 2) + 2) % 2; api.coil_mode = coil_mode end
  -- round 50: the waves (testing: send one now; the director's state)
  api.varied = varied
  function api.send(kind) DIR.force = kind; return kind end
  function api.waves() return { next = DIR.next, n = DIR.n, last = DIR.last, lull = DIR.lull, log = DIR.log, pooled = #pooled() } end
  return api
end

return SN
