--[[
  fire.lua -- the port to Anchor: web/src/fire.js. The lich's first attack: a burn is a timeline
  over a body lying still (flames spread from one point, burn, die down tail-first; the scales
  char behind them, cracks glow and cool; smoke rises a little longer). snakes.lua owns the body;
  this owns the particles and a pooled light per burn (the light count never changes).
]]
local T = require('port.three.core')
local U = require('port.util')
local FX = require('port.fx')
local clamp, smoothstep, lerp = U.clamp, U.smoothstep, U.lerp
local abs, sin, cos, floor, min, max = math.abs, math.sin, math.cos, math.floor, math.min, math.max

local F = {}

F.BURN = { spread = 0.35, burn = 2.4, die = 0.7, char = 1.3, cool = 1.0, smoke = 1.2 }
local BURN = F.BURN
BURN.out = BURN.burn + BURN.die
BURN['end'] = BURN.out + max(BURN.cool, BURN.smoke)

F.LOOKS = {
  { name = 'NATURAL',
    ramp = { { 1.0, 0.82, 0.42, 4.2 }, { 1.0, 0.48, 0.09, 2.9 }, { 0.85, 0.2, 0.035, 1.4 }, { 0.3, 0.05, 0.015, 0.35 } },
    light = { 1.0, 0.52, 0.18 }, ember = { 3.2, 0.75, 0.1 }, spark = { 4.0, 2.4, 0.8 }, smoke = { 0.011, 0.01, 0.009 }, prism = 0 },
  { name = "THE LICH'S (PRISMATIC)",
    ramp = { { 1.0, 0.97, 0.95, 3.8 }, { 0.85, 0.8, 1.0, 2.6 }, { 0.7, 0.6, 1.0, 1.3 }, { 0.4, 0.3, 0.6, 0.35 } },
    light = { 0.85, 0.8, 1.0 }, ember = { 1.6, 1.0, 2.4 }, spark = { 3.2, 3.0, 3.6 }, smoke = { 0.01, 0.01, 0.012 }, prism = 1 },
  { name = 'SPECTRAL',
    ramp = { { 0.85, 0.95, 1.0, 3.8 }, { 0.35, 0.65, 1.0, 2.6 }, { 0.2, 0.3, 1.0, 1.3 }, { 0.15, 0.1, 0.5, 0.35 } },
    light = { 0.45, 0.65, 1.0 }, ember = { 0.5, 1.2, 3.2 }, spark = { 2.0, 3.2, 4.0 }, smoke = { 0.009, 0.01, 0.012 }, prism = 0 },
}
local LOOKS = F.LOOKS
local spectrum = FX.spectrum

function F.create(R, cave, seed)
  local rng = U.make_rng(seed or 13)
  local flames = FX.sprite_pool(R, 900, true, 'flame')
  local sparks = FX.sprite_pool(R, 160, true, 'dot')
  local smoke = FX.sprite_pool(R, 320, false, 'dot')
  local LIGHTS = {}
  for k = 1, 4 do
    local l = T.PointLight.new(0xffffff, 0, 7, 2)
    l.cast_shadow = false
    R.world_scene:add(l)
    LIGHTS[k] = { l = l, burn = nil }
  end
  local look = 0
  local burns = {}

  local function flame_at(b, i)
    local d = abs(i - b.at)/b.rings
    local arrive = d*BURN.spread/0.6
    if b.t < arrive then return 0 end
    local up = smoothstep(arrive, arrive + 0.12, b.t)
    local die_start = BURN.burn + (1 - i/(b.rings - 1))*BURN.die*0.6
    local down = 1 - smoothstep(die_start, die_start + BURN.die*0.4, b.t)
    return up*down
  end
  local function arrive_t(b, i) return abs(i - b.at)/b.rings*BURN.spread/0.6 end

  local function emit_flame(b, i, boost)
    boost = boost or 1
    local p, c, r = flames.spawn(), b.spine[i + 1], b.r[i + 1]
    local a = rng.float(0, math.pi*2)
    p.x = c.x + cos(a)*r*0.8; p.z = c.z + sin(a)*r*0.8; p.y = c.y + r*rng.float(0.2, 0.9)
    p.vx = rng.spread(0.18)*boost; p.vz = rng.spread(0.18)*boost; p.vy = rng.float(0.55, 1.15)*boost
    p.life = rng.float(0.34, 0.66)*(boost > 1 and 1.2 or 1); p.max = p.life
    p.s0 = rng.float(0.12, 0.24)*(boost > 1 and 1.35 or 1); p.s1 = p.s0*0.3
    p.h = rng.next()
  end
  local function emit_spark(c, boost)
    boost = boost or 1
    local p = sparks.spawn()
    p.x = c.x + rng.spread(0.1); p.y = c.y + 0.05; p.z = c.z + rng.spread(0.1)
    p.vx = rng.spread(0.9)*boost; p.vz = rng.spread(0.9)*boost; p.vy = rng.float(1.2, 2.6)*boost
    p.life = rng.float(0.45, 1.0); p.max = p.life; p.s0 = 0.035; p.s1 = 0.02; p.h = rng.next()
  end
  local function emit_smoke(c, r, k, lit)
    k = k or 1; lit = lit or 0
    local p = smoke.spawn()
    p.lit = lit
    p.x = c.x + rng.spread(r); p.y = c.y + r*0.8 + rng.float(0.05, 0.3); p.z = c.z + rng.spread(r)
    p.vx = rng.spread(0.08); p.vz = rng.spread(0.08); p.vy = rng.float(0.35, 0.6)
    p.life = rng.float(1.4, 2.4); p.max = p.life; p.s0 = rng.float(0.25, 0.4)*k; p.s1 = p.s0*rng.float(2.0, 2.8); p.h = rng.next()
  end
  -- spine: 1-based list of Vector3 (the snake's), rings: its count
  local function ash(spine, rings)
    for _ = 1, 40 do
      local i = rng.int(0, rings - 1)
      local c = spine[i + 1]
      local p = smoke.spawn()
      p.x = c.x + rng.spread(0.12); p.y = c.y; p.z = c.z + rng.spread(0.12)
      p.vx = rng.spread(0.35); p.vz = rng.spread(0.35); p.vy = rng.float(0.05, 0.3)
      p.life = rng.float(0.6, 1.1); p.max = p.life; p.s0 = rng.float(0.1, 0.2); p.s1 = p.s0*2.2; p.h = -1; p.lit = 0
    end
  end

  -- a burn over a body of `rings` spine points (spine[i + 1] Vector3, radii[i + 1] m; kept current by the caller)
  local function start(rings, spine, radii, ignite_at)
    local b = { t = 0, rings = rings, spine = spine, r = radii, at = ignite_at, acc = 0, sacc = 0, kacc = 0, light = nil, done = false, flash = 1 }
    local free
    for _, L in ipairs(LIGHTS) do if not L.burn then free = L; break end end
    if not free then
      free = LIGHTS[1]
      for k = 2, #LIGHTS do if LIGHTS[k].burn.t > free.burn.t then free = LIGHTS[k] end end
    end
    if free.burn then free.burn.light = nil end
    free.burn = b; b.light = free
    local p0 = spine[ignite_at + 1]
    for _ = 1, 10 do emit_flame(b, ignite_at, 1.3) end
    for _ = 1, 14 do emit_spark(p0, 1.3) end
    burns[#burns + 1] = b
    return b
  end

  local UT, UDT, UL = 0, 0, LOOKS[1]
  local function write_flame(p, i, pos, col, size)
    local t, dt, L = UT, UDT, UL
    p.life = p.life - dt
    local u = 1 - p.life/p.max
    p.vx = p.vx + sin(t*9 + p.h*40)*0.6*dt; p.vz = p.vz + cos(t*8 + p.h*33)*0.6*dt; p.vy = p.vy + 0.5*dt
    p.x = p.x + p.vx*dt; p.y = p.y + p.vy*dt; p.z = p.z + p.vz*dt
    pos[i*3 + 1] = p.x; pos[i*3 + 2] = p.y; pos[i*3 + 3] = p.z
    local k = min(2.999, u*3)
    local j = floor(k)
    local f = k - j
    local a, b = L.ramp[j + 1], L.ramp[j + 2]
    local r, g, bl, e = lerp(a[1], b[1], f), lerp(a[2], b[2], f), lerp(a[3], b[3], f), lerp(a[4], b[4], f)
    if L.prism ~= 0 then
      local s = spectrum(p.h + t*0.15)
      local m = 0.45*smoothstep(0.1, 0.6, u)
      r = lerp(r, s[1], m); g = lerp(g, s[2], m); bl = lerp(bl, s[3], m)
    end
    local fade = smoothstep(0, 0.12, u)*(1 - smoothstep(0.7, 1, u))
    col[i*4 + 1] = r*e; col[i*4 + 2] = g*e; col[i*4 + 3] = bl*e; col[i*4 + 4] = fade
    size[i + 1] = lerp(p.s0, p.s1, u)
  end
  local function write_spark(p, i, pos, col, size)
    local t, dt, L = UT, UDT, UL
    p.life = p.life - dt
    local u = 1 - p.life/p.max
    p.vy = p.vy - 1.6*dt; p.vx = p.vx*(1 - 0.8*dt); p.vz = p.vz*(1 - 0.8*dt)
    p.x = p.x + p.vx*dt; p.y = p.y + p.vy*dt; p.z = p.z + p.vz*dt
    pos[i*3 + 1] = p.x; pos[i*3 + 2] = p.y; pos[i*3 + 3] = p.z
    local tw = 0.6 + 0.4*sin(t*50 + p.h*90)
    local c = L.spark
    if L.prism ~= 0 then
      local s = spectrum(p.h)
      c = { lerp(c[1], s[1]*4, 0.5), lerp(c[2], s[2]*4, 0.5), lerp(c[3], s[3]*4, 0.5) }
    end
    col[i*4 + 1] = c[1]; col[i*4 + 2] = c[2]; col[i*4 + 3] = c[3]; col[i*4 + 4] = tw*(1 - u*u)
    size[i + 1] = lerp(p.s0, p.s1, u)
  end
  local GRIT = { 0.016, 0.014, 0.011 }
  local function write_smoke(p, i, pos, col, size)
    local t, dt, L = UT, UDT, UL
    p.life = p.life - dt
    local u = 1 - p.life/p.max
    p.vy = p.vy*(1 - 0.35*dt); p.vx = p.vx + sin(t*1.7 + p.h*20)*0.08*dt
    p.x = p.x + p.vx*dt; p.y = p.y + p.vy*dt; p.z = p.z + p.vz*dt
    pos[i*3 + 1] = p.x; pos[i*3 + 2] = p.y; pos[i*3 + 3] = p.z
    local c = p.h < 0 and GRIT or L.smoke
    local w = (p.lit or 0)*0.07*(1 - u)*(1 - u)
    col[i*4 + 1] = c[1] + L.light[1]*w; col[i*4 + 2] = c[2] + L.light[2]*w; col[i*4 + 3] = c[3] + L.light[3]*w
    col[i*4 + 4] = (p.h < 0 and 0.55 or 0.4)*smoothstep(0, 0.15, u)*(1 - smoothstep(0.45, 1, u))
    size[i + 1] = lerp(p.s0, p.s1, u)
  end

  local function update(t, dt)
    local L = LOOKS[look + 1]
    for bi = #burns, 1, -1 do
      local b = burns[bi]
      b.t = b.t + dt
      local lit = 0
      for i = 0, b.rings - 1 do lit = lit + flame_at(b, i) end
      local frac = lit/b.rings
      b.acc = b.acc + 170*frac*dt
      while b.acc >= 1 do
        b.acc = b.acc - 1
        local i = 0
        for _ = 1, 8 do i = rng.int(0, b.rings - 1); if rng.next() < flame_at(b, i) then break end end
        if flame_at(b, i) > 0.05 then emit_flame(b, i) end
      end
      b.kacc = b.kacc + 7*frac*dt
      while b.kacc >= 1 do b.kacc = b.kacc - 1; local i = rng.int(0, b.rings - 1); if flame_at(b, i) > 0.3 then emit_spark(b.spine[i + 1]) end end
      local smoky = b.t < BURN.out and 0.5 + 0.5*frac or 1 - smoothstep(BURN.out, BURN.out + BURN.smoke, b.t)
      b.sacc = b.sacc + 16*smoky*dt
      while b.sacc >= 1 do
        b.sacc = b.sacc - 1
        local i = rng.int(0, b.rings - 1)
        emit_smoke(b.spine[i + 1], b.r[i + 1], b.t < BURN.out and 1 or 0.7, b.t < BURN.out and frac or 0)
      end
      if b.light then
        local cx, cy, cz, w = 0, 0, 0, 0
        for i = 0, b.rings - 1, 4 do
          local f = flame_at(b, i) + 1e-3
          local q = b.spine[i + 1]
          cx = cx + q.x*f; cy = cy + q.y*f; cz = cz + q.z*f; w = w + f
        end
        local l = b.light.l
        l.position:set(cx/w, cy/w + 0.35, cz/w)
        b.flash = max(0, b.flash - dt*3.5)
        local jbi = bi - 1                         -- JS's index
        local flick = 0.82 + 0.1*sin(t*23 + jbi) + 0.08*sin(t*37.3 + jbi*2.1) + rng.spread(0.05)
        l.color:set_rgb(L.light[1], L.light[2], L.light[3])
        l.intensity = 3.2*frac*flick*(1 + 1.2*b.flash)
      end
      if b.t > BURN['end'] then
        if b.light then b.light.l.intensity = 0; b.light.burn = nil; b.light = nil end
        b.done = true
        table.remove(burns, bi)
      end
    end
    UT, UDT, UL = t, dt, L
    flames.write(write_flame)
    sparks.write(write_spark)
    smoke.write(write_smoke)
  end

  local function set_camera(cam, H)
    local s = cam.projection_matrix.elements[6]*H*0.5
    flames.mat.uniforms.uScale.value = s; sparks.mat.uniforms.uScale.value = s; smoke.mat.uniforms.uScale.value = s
  end

  local fire = { start = start, update = update, set_camera = set_camera, ash = ash, LOOKS = LOOKS, BURN = BURN, flame_at = flame_at }
  function fire.get_look() return look end
  function fire.set_look(i) local n = #LOOKS; look = ((i % n) + n) % n end
  function fire.char(b, i) local a = arrive_t(b, i); return smoothstep(a, a + BURN.char, b.t) end
  function fire.ember(b, i)
    local a = arrive_t(b, i)
    local on = smoothstep(a + 0.15, a + 0.7, b.t)
    local off = 1 - smoothstep(BURN.out - 0.2, BURN.out + BURN.cool, b.t)
    return on*off
  end
  function fire.ember_colour() return LOOKS[look + 1].ember end
  function fire.burning() return #burns end
  return fire
end

return F
