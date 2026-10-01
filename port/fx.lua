--[[
  fx.lua -- the port to Anchor: web/src/fx.js. The effects the powers share: point sprites
  (flames, glowing motes, shards, dust and mist), beams drawn as screen-space ribbons, and chunks
  of snake that fall, bounce and sink. Everything is pooled (allocated once, recycled).
  The shaders are three.js's compiled programs (picked by material name); here only the
  uniforms and the per-vertex data.
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local U = require('port.util')
local Vector2, Vector3, Matrix4, Quaternion, Euler = TM.Vector2, TM.Vector3, TM.Matrix4, TM.Quaternion, TM.Euler
local clamp, smoothstep, lerp = U.clamp, U.smoothstep, U.lerp
local abs, floor, fmod = math.abs, math.floor, math.fmod

local FX = {}

-- JS: ((h % 1) + 1) % 1, then [0, 2/3, 1/3].map(o => clamp(|((h + o) % 1)*6 - 3| - 1, 0, 1))
function FX.spectrum(h)
  h = fmod(fmod(h, 1) + 1, 1)
  return { clamp(abs(fmod(h, 1)*6 - 3) - 1, 0, 1), clamp(abs(fmod(h + 2/3, 1)*6 - 3) - 1, 0, 1), clamp(abs(fmod(h + 1/3, 1)*6 - 3) - 1, 0, 1) }
end
local spectrum = FX.spectrum

-- the gi.js gi_dynamic patch: the material reads the cave's bounce-light probes
function FX.gi_dynamic(mat, GU)
  mat.custom = mat.custom or {}
  for _, k in ipairs({ 'uGIUp', 'uGIDown', 'uGIMin', 'uGIMax', 'uGIScale' }) do mat.custom[k] = GU[k] end
  return mat
end

-- a pool of point sprites: `additive` for light, otherwise alpha-blended; shape 'flame' | 'shard' | 'dot'
function FX.sprite_pool(R, N, additive, shape)
  local pos, col, size = T.float_attr(N, 3), T.float_attr(N, 4), T.float_attr(N, 1)
  local g = T.BufferGeometry.new()
  g:set_attribute('position', pos)
  g:set_attribute('aCol', col)
  g:set_attribute('aSize', size)
  local mat = MAT.ShaderMaterial.new({ name = 'fx.points.' .. shape .. (additive and '.add' or '.alpha'), uniforms = { uScale = { value = 1 } },
    transparent = true, depth_write = false, depth_test = true, blending = additive and MAT.AdditiveBlending or MAT.NormalBlending })
  local pts = T.Points.new(g, mat)
  pts.frustum_culled = false
  pts.render_order = additive and 11 or 10
  R.world_scene:add(pts)
  local P = {}
  for i = 1, N do P[i] = { life = 0, max = 1, x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0, s0 = 0, s1 = 0, h = 0, kind = 0, burn = nil } end
  local nxt = 0
  local pa, ca, sa = pos.array, col.array, size.array
  local pool = { mat = mat, P = P, points = pts }
  function pool.spawn() local p = P[nxt + 1]; nxt = (nxt + 1) % N; return p end
  -- fn(p, i, pos, col, size) with i 0-based (the arrays are 1-based: pos[i*3 + 1] ...)
  function pool.write(fn)
    for i = 0, N - 1 do
      local p = P[i + 1]
      if p.life <= 0 then sa[i + 1] = 0; ca[i*4 + 4] = 0
      else fn(p, i, pa, ca, sa) end
    end
    pos.needs_update = true; col.needs_update = true; size.needs_update = true
  end
  return pool
end

-- beams: segments drawn as camera-facing ribbons (see fx.js for the styles)
local function ribbon_pool(R, N)
  local V = N*4
  local function zeros(n) local a = {}; for i = 1, n do a[i] = 0 end; return a end
  local a0, a1, en, side = zeros(V*3), zeros(V*3), zeros(V), zeros(V)
  local apv, anx = zeros(V*3), zeros(V*3)
  local col, wo, bb, ax = zeros(V*4), zeros(V*3), zeros(V*4), zeros(V*2)
  for i = 0, N - 1 do for k = 0, 3 do en[i*4 + k + 1] = k >> 1; side[i*4 + k + 1] = (k & 1) ~= 0 and 1 or -1 end end
  local idx = {}
  for i = 0, N - 1 do
    local b = i*4
    local o = #idx
    idx[o + 1], idx[o + 2], idx[o + 3], idx[o + 4], idx[o + 5], idx[o + 6] = b, b + 1, b + 3, b, b + 3, b + 2
  end
  local g = T.BufferGeometry.new()
  g:set_attribute('position', T.BufferAttribute.new(zeros(V*3), 3))
  local A = {
    aP0 = T.BufferAttribute.new(a0, 3), aP1 = T.BufferAttribute.new(a1, 3), aEnd = T.BufferAttribute.new(en, 1), aSide = T.BufferAttribute.new(side, 1),
    aCol = T.BufferAttribute.new(col, 4), aWO = T.BufferAttribute.new(wo, 3), aB = T.BufferAttribute.new(bb, 4), aX = T.BufferAttribute.new(ax, 2),
    aPv = T.BufferAttribute.new(apv, 3), aNx = T.BufferAttribute.new(anx, 3),
  }
  for _, k in ipairs({ 'aP0', 'aP1', 'aEnd', 'aSide', 'aCol', 'aWO', 'aB', 'aX', 'aPv', 'aNx' }) do g:set_attribute(k, A[k]) end
  g:set_index(idx)
  local mat = MAT.ShaderMaterial.new({ name = 'fx.ribbons',
    uniforms = { uRes = { value = Vector2.new(640, 360) }, uTime = { value = 0 }, uProj = { value = 400 } },
    transparent = true, depth_write = false, depth_test = true, blending = MAT.AdditiveBlending, side = MAT.DoubleSide })
  local mesh = T.Mesh.new(g, mat)
  mesh.frustum_culled = false; mesh.render_order = 12
  R.world_scene:add(mesh)
  local B = {}
  for i = 1, N do B[i] = { life = 0, max = 1, p0 = Vector3.new(), p1 = Vector3.new(), c = { 1, 1, 1 }, w = 2, off = 0, hue = -1, a = 1, fade_in = 0.03, held = false,
    style = 0, w0 = 0, w1 = 0, x0 = 0, ph0 = 0, pv = nil, nx = nil } end
  local nxt = 0
  local pool = { mat = mat }
  function pool.spawn(p0, p1, o)
    -- held ribbons (kept alive by their owner) are skipped
    local k = 0
    while k < N and (B[nxt + 1].held or B[nxt + 1].life > 5) do nxt = (nxt + 1) % N; k = k + 1 end
    local b = B[nxt + 1]; nxt = (nxt + 1) % N
    b.p0:copy(p0); b.p1:copy(p1); b.c = o.c or { 1, 1, 1 }; b.w = o.w == nil and 1.5 or o.w; b.off = o.off or 0; b.hue = o.hue == nil and -1 or o.hue
    b.a = o.a == nil and 1 or o.a
    b.life = o.life == nil and 1 or o.life; b.max = b.life; b.fade_in = o.fade_in == nil and 0.03 or o.fade_in; b.held = not not o.held
    b.style = o.style or 0; b.w0 = o.w0 or 0; b.w1 = o.w1 == nil and b.w0 or o.w1; b.x0 = o.x0 or 0; b.ph0 = o.ph0 or 0; b.pv = nil; b.nx = nil
    return b
  end
  function pool.release(b) b.held = false; b.life = 0 end
  function pool.update(t, dt)
    mat.uniforms.uTime.value = t
    for i = 0, N - 1 do
      local b = B[i + 1]
      if not b.held and b.life > 0 then b.life = b.life - dt end
      local on = b.held or b.life > 0
      local u = b.held and 0.5 or 1 - b.life/b.max
      local al = (not on) and 0 or (b.held and b.a or b.a*smoothstep(0, b.fade_in/b.max, u)*(1 - smoothstep(0.5, 1, u)))
      local len = b.p0:distance_to(b.p1)
      local q, r = b.pv or b.p0, b.nx or b.p1
      for k = 0, 3 do
        local v = i*4 + k
        local v3, v4, v2 = v*3, v*4, v*2
        a0[v3 + 1], a0[v3 + 2], a0[v3 + 3] = b.p0.x, b.p0.y, b.p0.z
        a1[v3 + 1], a1[v3 + 2], a1[v3 + 3] = b.p1.x, b.p1.y, b.p1.z
        col[v4 + 1], col[v4 + 2], col[v4 + 3], col[v4 + 4] = b.c[1], b.c[2], b.c[3], al
        wo[v3 + 1], wo[v3 + 2], wo[v3 + 3] = on and b.w or 0, b.off, b.hue
        bb[v4 + 1], bb[v4 + 2], bb[v4 + 3], bb[v4 + 4] = on and b.w0 or 0, on and b.w1 or 0, b.style, len
        ax[v2 + 1], ax[v2 + 2] = b.x0, b.ph0
        apv[v3 + 1], apv[v3 + 2], apv[v3 + 3] = q.x, q.y, q.z
        anx[v3 + 1], anx[v3 + 2], anx[v3 + 3] = r.x, r.y, r.z
      end
    end
    for _, k in ipairs({ 'aP0', 'aP1', 'aCol', 'aWO', 'aB', 'aX', 'aPv', 'aNx' }) do A[k].needs_update = true end
  end
  return pool
end

-- chunks of a burst snake: small dark lumps thrown, bouncing once or twice, then sinking
local function chunk_pool(R, cave, N)
  local geo = R.statics.geometry('icosahedron_1_0')
  local mat = MAT.MeshStandardMaterial.new({ name = 'fx.chunks', color = 0x3a3629, roughness = 0.45, metalness = 0, flat_shading = true })
  if cave.GU then FX.gi_dynamic(mat, cave.GU) end
  local mesh = T.InstancedMesh.new(geo, mat, N)
  mesh.cast_shadow = true; mesh.receive_shadow = true; mesh.frustum_culled = false
  R.world_scene:add(mesh)
  local C, M, Q, E, V, Sc = {}, Matrix4.new(), Quaternion.new(), Euler.new(), Vector3.new(), Vector3.new()
  for i = 1, N do C[i] = { life = 0, x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0, rx = 0, ry = 0, rz = 0, wx = 0, wy = 0, wz = 0, s = 0, sink = 0, sx = 1, sy = 1, sz = 1, rest = 0 } end
  local nxt = 0
  local zero = Matrix4.new():make_scale(0, 0, 0)
  for i = 0, N - 1 do mesh:set_matrix_at(i, zero) end
  local pool = {}
  function pool.spawn() local c = C[nxt + 1]; nxt = (nxt + 1) % N; c.sink = 0; c.rest = 0; return c end
  function pool.update(dt)
    for i = 0, N - 1 do
      local c = C[i + 1]
      if c.life <= 0 then mesh:set_matrix_at(i, zero)
      else
        c.life = c.life - dt
        local gy = cave.ground_y(c.x, c.z)
        if c.rest <= 0 then
          c.vy = c.vy - 9.8*dt
          c.x = c.x + c.vx*dt; c.y = c.y + c.vy*dt; c.z = c.z + c.vz*dt
          c.rx = c.rx + c.wx*dt; c.ry = c.ry + c.wy*dt; c.rz = c.rz + c.wz*dt
          if c.y < gy + c.s*0.5 then
            c.y = gy + c.s*0.5
            if abs(c.vy) < 1.2 then c.rest = 1e-3; c.vx = 0; c.vz = 0; c.vy = 0
            else c.vy = -c.vy*0.28; c.vx = c.vx*0.55; c.vz = c.vz*0.55; c.wx = c.wx*0.5; c.wy = c.wy*0.5; c.wz = c.wz*0.5 end
          end
        else
          c.rest = c.rest + dt
          if c.rest > 1.4 then c.y = c.y - 0.12*dt end
        end
        E:set(c.rx, c.ry, c.rz); Q:set_from_euler(E)
        local k = c.life < 0.4 and c.life/0.4 or 1
        M:compose(V:set(c.x, c.y, c.z), Q, Sc:set(c.s*c.sx*k, c.s*c.sy*k, c.s*c.sz*k))
        mesh:set_matrix_at(i, M)
      end
    end
    mesh.instance_matrix.needs_update = true
  end
  return pool
end

-- the particles every power uses: motes (additive dots), shards (additive slivers), puffs (alpha),
-- plus ribbons and chunks
function FX.create(R, cave)
  local motes = FX.sprite_pool(R, 1600, true, 'dot')
  local shards = FX.sprite_pool(R, 400, true, 'shard')
  local puffs = FX.sprite_pool(R, 600, false, 'dot')
  local ribbons = ribbon_pool(R, 240)
  local chunks = chunk_pool(R, cave, 160)
  local function init(p, o)
    p.x = o.x; p.y = o.y; p.z = o.z; p.vx = o.vx or 0; p.vy = o.vy or 0; p.vz = o.vz or 0
    p.life = o.life; p.max = o.life; p.s0 = o.s0; if o.s1 == nil then p.s1 = o.s0 else p.s1 = o.s1 end
    p.r = o.r; p.g = o.g; p.b = o.b; if o.a == nil then p.a = 1 else p.a = o.a end
    p.grav = o.grav or 0; p.drag = o.drag or 0; if o.hue == nil then p.hue = -1 else p.hue = o.hue end
    p.hr = o.hr or 0; p.floor = not not o.floor; if o.fin == nil then p.fin = 0.1 else p.fin = o.fin end
    return p
  end
  local ST, SDT = 0, 0
  local function step(p, i, pos, col, size)
    local dt = SDT
    p.life = p.life - dt
    local u = 1 - p.life/p.max
    p.vy = p.vy - p.grav*dt
    local d = 1 - p.drag*dt
    p.vx = p.vx*d; p.vy = p.vy*d; p.vz = p.vz*d
    p.x = p.x + p.vx*dt; p.y = p.y + p.vy*dt; p.z = p.z + p.vz*dt
    if p.floor then
      local gy = cave.ground_y(p.x, p.z) + 0.02
      if p.y < gy then p.y = gy; p.vy = 0; p.vx = p.vx*0.5; p.vz = p.vz*0.5 end
    end
    pos[i*3 + 1] = p.x; pos[i*3 + 2] = p.y; pos[i*3 + 3] = p.z
    local r, g, b = p.r, p.g, p.b
    if p.hue >= 0 then
      local s = spectrum(p.hue + ST*p.hr)
      r = r*(0.35 + 0.65*s[1]*1.4); g = g*(0.35 + 0.65*s[2]*1.4); b = b*(0.35 + 0.65*s[3]*1.4)
    end
    col[i*4 + 1] = r; col[i*4 + 2] = g; col[i*4 + 3] = b
    col[i*4 + 4] = p.a*smoothstep(0, p.fin, u)*(1 - smoothstep(0.55, 1, u))
    size[i + 1] = lerp(p.s0, p.s1, u)
  end
  local fx = {}
  function fx.mote(o) return init(motes.spawn(), o) end
  function fx.shard(o) return init(shards.spawn(), o) end
  function fx.puff(o) return init(puffs.spawn(), o) end
  function fx.ribbon(p0, p1, o) return ribbons.spawn(p0, p1, o) end
  function fx.release(b) return ribbons.release(b) end
  function fx.chunk() return chunks.spawn() end
  function fx.update(t, dt)
    ST, SDT = t, dt
    motes.write(step); shards.write(step); puffs.write(step)
    ribbons.update(t, dt)
    chunks.update(dt)
  end
  function fx.set_camera(cam, H)
    local s = cam.projection_matrix.elements[6]*H*0.5
    motes.mat.uniforms.uScale.value = s; shards.mat.uniforms.uScale.value = s; puffs.mat.uniforms.uScale.value = s
    ribbons.mat.uniforms.uProj.value = s
  end
  return fx
end

return FX
