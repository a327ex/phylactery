--[[
  gore.lua -- the port to Anchor: web/src/gore.js. What a lifted snake becomes when it bursts: its
  own tube torn into pieces with wounds at the torn ends, lumps of meat, ribs and vertebrae, skin
  scraps, strands of gut, blood in streaks through the air and splashes on the floor, a red mist.
  The random draws happen in gore.js's order (argument lists and object literals left to right),
  so the same seed makes the same mess.
  Round 64 (owner, 2026-10-08: "Game is noticeably slowing down when snakes gore explode from lift"): the same mess for
  less: what lies still is not posed again (a resting lump, a full-grown stain: their matrices stay as they are until
  they sink), a buffer goes to the GPU only when something in it changed (it was every tick, idle or not: ~26k floats
  a tick, into every recording too), the guts' rings take their turns from a table, and a gut lying still on the
  floor is left lying until it sinks. Measured with lift bursts about: gore's tick 4.5 -> 2.5 ms (RECORD.md round 64).
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local U = require('port.util')
local FX = require('port.fx')
local Vector2, Vector3, Quaternion, Matrix4, Euler = TM.Vector2, TM.Vector3, TM.Quaternion, TM.Matrix4, TM.Euler
local smoothstep = U.smoothstep
local sqrt, abs, sin, cos, atan2, exp, floor, min, max = math.sqrt, math.abs, math.sin, math.cos, math.atan, math.exp, math.floor, math.min, math.max

local GO = {}
local GRAV = 9.8
local PULL_T, PULL_A = 0.7, 6.0
local PIECE_LIFE, SINK_T = 5.5, 1.5
local MAXR = 36
local function jround(x) return floor(x + 0.5) end
local function sign(x) return x > 0 and 1 or (x < 0 and -1 or 0) end

function GO.create(R, cave, snakes, fx, rng)
  local N, SIDES, gy, GU = snakes.RINGS, snakes.SIDES, cave.ground_y, cave.GU
  local A = R.statics
  local function lit(m) if GU then return FX.gi_dynamic(m, GU) end; return m end
  local V, V2, Q, M, E, SC = Vector3.new(), Vector3.new(), Quaternion.new(), Matrix4.new(), Euler.new(), Vector3.new()
  local follow = nil
  local TGT, TUG = Vector3.new(), Vector3.new()
  local function tug(x, y, z, pl)
    if not follow or pl <= 0 then return TUG:set(0, 0, 0) end
    TUG:set(TGT.x - x, (TGT.y - y)*0.5, TGT.z - z)
    local l = TUG:length()
    if l < 0.3 then return TUG:set(0, 0, 0) end
    return TUG:multiply_scalar(PULL_A*(pl/PULL_T)/l)
  end
  local UP = Vector3.new(0, 1, 0)

  -- ---------------------------------------------------------------- blood on the floor
  local DEC_N, decals = 90, {}
  local plane = A.geometry('gore_plane')
  local ZERO = Matrix4.new():make_scale(0, 0, 0)
  for v = 0, 3 do
    local m = lit(MAT.MeshStandardMaterial.new({ name = 'gore.splat', color = 0x4a0604, alpha_map = A.texture('gore_splat_' .. (v + 1)), transparent = true, depth_write = false,
      roughness = 0.14, metalness = 0, polygon_offset = true, polygon_offset_factor = -2, polygon_offset_units = -2 }))
    local mesh = T.InstancedMesh.new(plane, m, DEC_N)
    mesh.frustum_culled = false; mesh.receive_shadow = true; mesh.render_order = 2
    local D = {}
    for i = 0, DEC_N - 1 do D[i + 1] = { life = 0, x = 0, y = 0, z = 0, rot = 0, s0 = 0, s1 = 0, t = 0, grow = 0.1, sx = 1 }; mesh:set_matrix_at(i, ZERO) end
    R.world_scene:add(mesh)
    decals[#decals + 1] = { mesh = mesh, D = D, nxt = 0 }
  end
  -- splash(x, z, s, grow = 0.12, rot = rng.float(0, 6.28), sx = 1)
  local function splash(x, z, s, grow, rot, sx)
    if grow == nil then grow = 0.12 end
    if rot == nil then rot = rng.float(0, 6.28) end
    if sx == nil then sx = 1 end
    local pool = decals[rng.int(0, 3) + 1]
    local d = pool.D[pool.nxt + 1]
    pool.nxt = (pool.nxt + 1) % DEC_N
    d.life = rng.float(9, 13); d.x = x; d.z = z; d.y = gy(x, z) + 0.012; d.rot = rot; d.s0 = s*0.35; d.s1 = s; d.t = 0; d.grow = grow; d.sx = sx
    d.full = false
  end
  local function update_decals(dt)
    for _, pool in ipairs(decals) do
      local dirty = false
      for i = 0, DEC_N - 1 do
        local d = pool.D[i + 1]
        if d.life > 0 then
          d.life = d.life - dt; d.t = d.t + dt
          if d.life <= 0 then pool.mesh:set_matrix_at(i, M:make_scale(0, 0, 0)); dirty = true
          elseif not d.full or d.life < 1.2 then
            -- (grown and not yet sinking it stays as it was last posed: posed once full-grown, then left)
            local s = d.s0 + (d.s1 - d.s0)*smoothstep(0, d.grow, d.t)
            local sink = d.life < 1.2 and (1.2 - d.life)*0.06 or 0
            Q:set_from_axis_angle(V:set(0, 1, 0), d.rot)
            M:compose(V2:set(d.x, d.y - sink, d.z), Q, SC:set(s*d.sx, 1, s))
            pool.mesh:set_matrix_at(i, M)
            dirty = true
            if d.t >= d.grow then d.full = true end
          end
        end
      end
      if dirty then pool.mesh.instance_matrix.needs_update = true end
    end
  end

  -- ---------------------------------------------------------------- blood in the air
  local BN = 900
  local bposA, bvelA, bcolA, bsizeA = T.float_attr(BN, 3), T.float_attr(BN, 3), T.float_attr(BN, 4), T.float_attr(BN, 1)
  local bpos, bvel, bcol, bsize = bposA.array, bvelA.array, bcolA.array, bsizeA.array
  local bg = T.BufferGeometry.new()
  bg:set_attribute('position', bposA)
  bg:set_attribute('aVel', bvelA)
  bg:set_attribute('aCol', bcolA)
  bg:set_attribute('aSize', bsizeA)
  local bmat = MAT.ShaderMaterial.new({ name = 'gore.blood', uniforms = { uScale = { value = 1 }, uRes = { value = Vector2.new(640, 360) } }, transparent = true, depth_write = false })
  local bpts = T.Points.new(bg, bmat); bpts.frustum_culled = false; bpts.render_order = 10
  R.world_scene:add(bpts)
  local B = {}
  for i = 1, BN do B[i] = { life = 0, x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0, s = 0, splat = 0 } end
  local bnext = 0
  local bidle = false               -- (nothing in the air and its sizes already sent as 0)
  local function drop(x, y, z, vx, vy, vz, s, splat, pl)
    bidle = false
    if s == nil then s = 0.012 end
    if splat == nil then splat = 0.5 end
    if pl == nil then pl = 0 end
    local b = B[bnext + 1]; bnext = (bnext + 1) % BN
    b.life = 3; b.x = x; b.y = y; b.z = z; b.vx = vx; b.vy = vy; b.vz = vz; b.s = s; b.splat = splat; b.pl = pl; b.dark = rng.float(0.7, 1.15)
  end
  local function update_blood(dt)
    if bidle then return end
    local any = false
    for i = 0, BN - 1 do
      local b = B[i + 1]
      if b.life <= 0 then bsize[i + 1] = 0
      else
        any = true
        b.life = b.life - dt
        b.vy = b.vy - GRAV*dt
        if b.pl > 0 then tug(b.x, b.y, b.z, b.pl); b.vx = b.vx + TUG.x*dt; b.vy = b.vy + TUG.y*dt; b.vz = b.vz + TUG.z*dt; b.pl = b.pl - dt end
        local d = 1 - 0.35*dt
        b.vx = b.vx*d; b.vz = b.vz*d
        b.x = b.x + b.vx*dt; b.y = b.y + b.vy*dt; b.z = b.z + b.vz*dt
        local g = gy(b.x, b.z)
        if b.y < g + 0.01 then
          if rng.next() < b.splat then
            local sp = js_hypot(b.vx, b.vz)
            splash(b.x, b.z, b.s*rng.float(7, 13), 0.08, atan2(-b.vz, b.vx), 1 + min(1.6, sp*0.35))
          end
          b.life = 0; bsize[i + 1] = 0
        else
          bpos[i*3 + 1] = b.x; bpos[i*3 + 2] = b.y; bpos[i*3 + 3] = b.z
          bvel[i*3 + 1] = b.vx; bvel[i*3 + 2] = b.vy; bvel[i*3 + 3] = b.vz
          bcol[i*4 + 1] = 0.038*b.dark; bcol[i*4 + 2] = 0.0025*b.dark; bcol[i*4 + 3] = 0.002*b.dark; bcol[i*4 + 4] = 0.95
          bsize[i + 1] = b.s
        end
      end
    end
    bposA.needs_update = true; bvelA.needs_update = true; bcolA.needs_update = true; bsizeA.needs_update = true
    if not any then bidle = true end
  end

  -- ---------------------------------------------------------------- the pieces of its body
  local flesh_mat = lit(MAT.MeshStandardMaterial.new({ name = 'gore.flesh', vertex_colors = true, roughness = 0.3, metalness = 0, side = MAT.DoubleSide, flat_shading = true }))
  local CAPV = 3*SIDES + 1
  local MAXV = MAXR*SIDES + 2 + 2*CAPV
  local MAXI = MAXR*SIDES*6 + 2*SIDES*3 + 2*SIDES*15
  local PIECES = {}
  for _ = 1, 18 do
    local g = T.BufferGeometry.new()
    g:set_attribute('position', T.float_attr(MAXV, 3))
    g:set_attribute('normal', T.float_attr(MAXV, 3))
    g:set_attribute('uv', T.float_attr(MAXV, 2))
    g:set_attribute('aBurn', T.float_attr(MAXV, 3))
    g:set_attribute('color', T.float_attr(MAXV, 3))
    local ia = {}
    for k = 1, MAXI do ia[k] = 0 end
    g:set_index(T.BufferAttribute.new(ia, 1))
    local m = T.Mesh.new(g, { snakes.mat, flesh_mat })
    m.cast_shadow = true; m.receive_shadow = true; m.frustum_culled = false; m.visible = false
    R.world_scene:add(m)
    PIECES[#PIECES + 1] = { m = m, on = false, v = Vector3.new(), w = Vector3.new(), t = 0, rest = 0, samples = {}, r = 0.08, ends = {}, landed = false, tw = 0, ax = Vector3.new(), pl = 0 }
  end

  local function make_piece(s, a, b)
    local P
    for _, p in ipairs(PIECES) do if not p.on then P = p; break end end
    if not P then return nil end
    local src = s.m.geometry.attributes
    local sp, sn, su = src.position.array, src.normal.array, src.uv.array
    local g = P.m.geometry
    local pos, nor, uv, col, idx = g.attributes.position.array, g.attributes.normal.array, g.attributes.uv.array, g.attributes.color.array, g.index.array
    local c = Vector3.new()
    for i = a, b do c:add(s.spine[i + 1]) end
    c:multiply_scalar(1/(b - a + 1))
    local nv, ni = 0, 0
    local function put(x, y, z, nx, ny, nz, u, w, r, gg, bb)
      pos[nv*3 + 1] = x - c.x; pos[nv*3 + 2] = y - c.y; pos[nv*3 + 3] = z - c.z
      nor[nv*3 + 1] = nx; nor[nv*3 + 2] = ny; nor[nv*3 + 3] = nz; uv[nv*2 + 1] = u; uv[nv*2 + 2] = w
      col[nv*3 + 1] = r; col[nv*3 + 2] = gg; col[nv*3 + 3] = bb
      local v = nv
      nv = nv + 1
      return v
    end
    local function I(v) idx[ni + 1] = v; ni = ni + 1 end
    for i = a, b do for j = 0, SIDES - 1 do
      local o = i*SIDES + j
      put(sp[o*3 + 1], sp[o*3 + 2], sp[o*3 + 3], sn[o*3 + 1], sn[o*3 + 2], sn[o*3 + 3], su[o*2 + 1], su[o*2 + 2], 1, 1, 1)
    end end
    for i = 0, b - a - 1 do for j = 0, SIDES - 1 do
      local p0, p1, p2, p3 = i*SIDES + j, i*SIDES + (j + 1)%SIDES, (i + 1)*SIDES + (j + 1)%SIDES, (i + 1)*SIDES + j
      I(p0); I(p3); I(p2); I(p0); I(p2); I(p1)
    end end
    local function close(ring, tipv, flip)
      local o = tipv*3
      local t = put(sp[o + 1], sp[o + 2], sp[o + 3], sn[o + 1], sn[o + 2], sn[o + 3], 0, 0, 1, 1, 1)
      for j = 0, SIDES - 1 do
        local r0, r1 = ring*SIDES + j, ring*SIDES + (j + 1)%SIDES
        if flip then I(t); I(r1); I(r0) else I(t); I(r0); I(r1) end
      end
    end
    if a == 0 then close(0, N*SIDES, true) end
    if b == N - 1 then close(b - a, N*SIDES + 1, false) end
    local skin_n = ni
    P.ends = {}
    local function wound(i, out)
      local ctr, nb = s.spine[i + 1], s.spine[max(0, min(N - 1, i + out)) + 1]
      local ax = V:sub_vectors(nb, ctr):normalize():clone()
      local r = s.radii[i + 1]
      local function ring(k, reach, push, jit, colour)
        local first = nv
        for j = 0, SIDES - 1 do
          local o = (i*SIDES + j)*3
          local rr = reach*(1 + rng.spread(jit))
          local pp = (push + rng.spread(jit*1.4))*r
          local x = ctr.x + (sp[o + 1] - ctr.x)*rr + ax.x*pp
          local y = ctr.y + (sp[o + 2] - ctr.y)*rr + ax.y*pp
          local z = ctr.z + (sp[o + 3] - ctr.z)*rr + ax.z*pp
          local cl = colour(j)
          put(x, y, z, ax.x, ax.y, ax.z, 0, 0, cl[1], cl[2], cl[3])
        end
        return first
      end
      local function dk() return rng.float(0.75, 1.2) end
      local rim0 = ring(0, 1.0, 0.0, 0.14, function() return { 0.07*dk(), 0.006, 0.004 } end)
      local fl0 = ring(1, 0.74, 0.34, 0.22, function(j) if j == SIDES/2 then return { 0.42, 0.37, 0.28 } end; return { 0.16*dk(), 0.012, 0.009 } end)
      local in0 = ring(2, 0.36, 0.26, 0.3, function() return { 0.11*dk(), 0.008, 0.006 } end)
      local cc = put(ctr.x + ax.x*r*0.02, ctr.y + ax.y*r*0.02, ctr.z + ax.z*r*0.02, ax.x, ax.y, ax.z, 0, 0, 0.04, 0.002, 0.002)
      local function band(p, q)
        for j = 0, SIDES - 1 do
          local j1 = (j + 1)%SIDES
          I(p + j); I(q + j); I(q + j1)
          I(p + j); I(q + j1); I(p + j1)
        end
      end
      band(rim0, fl0); band(fl0, in0)
      for j = 0, SIDES - 1 do I(in0 + j); I(cc); I(in0 + (j + 1)%SIDES) end
      P.ends[#P.ends + 1] = { ['local'] = Vector3.new():sub_vectors(ctr, c), ax = ax:clone() }
    end
    if a > 0 then wound(a, -1) end
    if b < N - 1 then wound(b, 1) end
    g.groups = {}
    g:add_group(0, skin_n, 0); g:add_group(skin_n, ni - skin_n, 1)
    g:set_draw_range(0, ni)
    for _, k in ipairs({ 'position', 'normal', 'uv', 'color' }) do g.attributes[k].needs_update = true end
    g.index.needs_update = true
    g:compute_bounding_sphere()
    P.samples = {}
    local stepn = max(1, jround((b - a)/5))
    local i = a
    while i <= b do P.samples[#P.samples + 1] = Vector3.new():sub_vectors(s.spine[i + 1], c); i = i + stepn end
    P.samples[#P.samples + 1] = Vector3.new():sub_vectors(s.spine[b + 1], c)
    P.r = max(0.02, s.radii[jround((a + b)/2) + 1]*0.8)
    P.m.position:copy(c); P.m.quaternion:identity(); P.m.scale:set(1, 1, 1); P.m.visible = true
    P.on = true; P.t = 0; P.rest = 0; P.landed = false; P.tw = rng.float(0, 6)
    V:sub_vectors(s.spine[b + 1], s.spine[a + 1])
    if V:length_sq() > 1e-6 then P.ax:copy(V:normalize()) else P.ax:copy(V:set(1, 0, 0)) end
    return P
  end

  local function update_pieces(dt)
    for _, P in ipairs(PIECES) do
      if P.on then
        P.t = P.t + dt
        local m = P.m
        if P.rest <= 0 then
          P.v.y = P.v.y - GRAV*dt
          if P.pl > 0 then tug(m.position.x, m.position.y, m.position.z, P.pl); P.v:add_scaled_vector(TUG, dt); P.pl = P.pl - dt end
          m.position:add_scaled_vector(P.v, dt)
          local wl = P.w:length()
          if wl > 1e-4 then Q:set_from_axis_angle(V:copy(P.w):multiply_scalar(1/wl), wl*dt); m.quaternion:premultiply(Q) end
          local pen, hx, hz = 0, 0, 0
          for _, sm in ipairs(P.samples) do
            V:copy(sm):apply_quaternion(m.quaternion):add(m.position)
            local d = gy(V.x, V.z) + P.r - V.y
            if d > pen then pen = d; hx = V.x; hz = V.z end
          end
          if pen > 0 then
            m.position.y = m.position.y + pen
            if not P.landed then P.landed = true; splash(hx, hz, rng.float(0.25, 0.45), 0.25) end
            if P.v.y < 0 then
              if abs(P.v.y) < 1.4 then P.rest = 1e-3; P.v:set(0, 0, 0); P.w:set(0, 0, 0)
              else P.v.y = P.v.y*-0.25; P.v.x = P.v.x*0.5; P.v.z = P.v.z*0.5; P.w:multiply_scalar(0.45) end
            end
          end
          for _, e in ipairs(P.ends) do
            if rng.next() < 0.35 then
              V:copy(e['local']):apply_quaternion(m.quaternion):add(m.position)
              V2:copy(e.ax):apply_quaternion(m.quaternion)
              local vx = P.v.x*0.6 + V2.x*0.6 + rng.spread(0.3)
              local vy = P.v.y*0.6 + V2.y*0.6
              local vz = P.v.z*0.6 + V2.z*0.6 + rng.spread(0.3)
              drop(V.x, V.y, V.z, vx, vy, vz, rng.float(0.008, 0.014), 0.35)
            end
          end
        else
          P.rest = P.rest + dt
          V:copy(P.ax):apply_quaternion(m.quaternion)
          if abs(V.y) > 0.2 then
            V2:cross_vectors(V, UP)
            if V2:length_sq() > 1e-6 then V2:normalize(); Q:set_from_axis_angle(V2, sign(V.y)*min(abs(V.y), 5*dt)); m.quaternion:premultiply(Q) end
            local pen = 0
            for _, sm in ipairs(P.samples) do V:copy(sm):apply_quaternion(m.quaternion):add(m.position); pen = max(pen, gy(V.x, V.z) + P.r - V.y) end
            m.position.y = m.position.y + pen
            local low = 1e9
            for _, sm in ipairs(P.samples) do V:copy(sm):apply_quaternion(m.quaternion):add(m.position); low = min(low, V.y - gy(V.x, V.z) - P.r) end
            if low > 0.005 then m.position.y = m.position.y - min(low, 1.5*dt) end
          end
          local tw = exp(-P.rest*1.6)*sin(P.rest*(13 + P.tw) + P.tw)*0.9*dt
          if P.rest < 2.2 then V:copy(P.ax):apply_quaternion(m.quaternion); Q:set_from_axis_angle(V, tw); m.quaternion:premultiply(Q) end
          if P.rest < 1.0 then
            for _, e in ipairs(P.ends) do
              if rng.next() < 0.08 then
                V:copy(e['local']):apply_quaternion(m.quaternion):add(m.position)
                local vx = rng.spread(0.3)
                local vy = rng.float(0, 0.4)
                local vz = rng.spread(0.3)
                drop(V.x, V.y, V.z, vx, vy, vz, 0.01, 0.8)
              end
            end
          end
        end
        if P.t > PIECE_LIFE then m.position.y = m.position.y - 0.3/SINK_T*dt end
        if P.t > PIECE_LIFE + SINK_T then P.on = false; m.visible = false end
      end
    end
  end

  -- ---------------------------------------------------------------- meat and bone
  local function debris_pool(geo, mat, n, coloured)
    local mesh = T.InstancedMesh.new(geo, mat, n)
    mesh.cast_shadow = true; mesh.receive_shadow = true; mesh.frustum_culled = false
    if coloured then
      local a = {}
      for k = 1, n*3 do a[k] = 1 end
      mesh.instance_color = T.BufferAttribute.new(a, 3); mesh.instance_color.instanced = true
    end
    local D = {}
    for i = 0, n - 1 do D[i + 1] = { life = 0 }; mesh:set_matrix_at(i, ZERO) end
    R.world_scene:add(mesh)
    local nxt = 0
    local pool = { mesh = mesh }
    function pool.spawn(o)
      local d, i = D[nxt + 1], nxt
      nxt = (nxt + 1) % n
      d.life = PIECE_LIFE + SINK_T; d.t = 0; d.rest = 0; d.landed = false
      d.rx = rng.float(0, 6); d.ry = rng.float(0, 6); d.rz = rng.float(0, 6)
      d.wx = rng.spread(16); d.wy = rng.spread(16); d.wz = rng.spread(16)
      d.sx = 1; d.sy = 1; d.sz = 1; d.bleed = 0
      for k, v in pairs(o) do d[k] = v end              -- (a key o lacks keeps the slot's old value, as Object.assign does)
      if coloured and o.c then
        local a = mesh.instance_color.array
        a[i*3 + 1], a[i*3 + 2], a[i*3 + 3] = o.c[1], o.c[2], o.c[3]
        mesh.instance_color.needs_update = true
      end
      return d
    end
    function pool.update(dt)
      local dirty = false
      for i = 0, n - 1 do
        local d = D[i + 1]
        if d.life > 0 then
          d.life = d.life - dt; d.t = d.t + dt
          local pose = true
          if d.rest <= 0 then
            d.vy = d.vy - GRAV*dt
            if d.pl and d.pl > 0 then tug(d.x, d.y, d.z, d.pl); d.vx = d.vx + TUG.x*dt; d.vy = d.vy + TUG.y*dt; d.vz = d.vz + TUG.z*dt; d.pl = d.pl - dt end
            d.x = d.x + d.vx*dt; d.y = d.y + d.vy*dt; d.z = d.z + d.vz*dt
            d.rx = d.rx + d.wx*dt; d.ry = d.ry + d.wy*dt; d.rz = d.rz + d.wz*dt
            local g = gy(d.x, d.z) + d.s*0.4
            if d.y < g then
              d.y = g
              if not d.landed then
                d.landed = true
                if d.bleed ~= 0 and rng.next() < 0.7 then splash(d.x, d.z, d.s*rng.float(4, 7), 0.15, atan2(-d.vz, d.vx), 1.4) end
              end
              if abs(d.vy) < 1.0 then d.rest = 1e-3; d.vx = 0; d.vy = 0; d.vz = 0
              else d.vy = -d.vy*0.22; d.vx = d.vx*0.5; d.vz = d.vz*0.5; d.wx = d.wx*0.4; d.wy = d.wy*0.4; d.wz = d.wz*0.4 end
            end
            if d.bleed ~= 0 and rng.next() < d.bleed then
              local vx = d.vx*0.5 + rng.spread(0.2)
              local vy = d.vy*0.5
              local vz = d.vz*0.5 + rng.spread(0.2)
              drop(d.x, d.y, d.z, vx, vy, vz, 0.008, 0.3)
            end
          else
            d.rest = d.rest + dt
            -- (lying still: posed as it came to rest, left so until it sinks)
            if d.life < SINK_T then d.y = d.y - 0.12*dt else pose = false end
          end
          if pose then
            E:set(d.rx, d.ry, d.rz); Q:set_from_euler(E)
            local k = d.life < 0.3 and d.life/0.3 or 1
            M:compose(V:set(d.x, d.y, d.z), Q, SC:set(d.s*d.sx*k, d.s*d.sy*k, d.s*d.sz*k))
            mesh:set_matrix_at(i, M)
            dirty = true
          end
        end
      end
      if dirty then mesh.instance_matrix.needs_update = true end
    end
    return pool
  end
  local meat = debris_pool(A.geometry('gore_lump'), lit(MAT.MeshStandardMaterial.new({ name = 'gore.meat', color = 0xffffff, roughness = 0.22, metalness = 0 })), 320, true)
  local bone_mat = lit(MAT.MeshStandardMaterial.new({ name = 'gore.bone', color = 0xb4a78e, roughness = 0.5, metalness = 0 }))
  local ribs = debris_pool(A.geometry('gore_rib'), bone_mat, 160, false)
  local verts = debris_pool(A.geometry('dodecahedron_1_0'), bone_mat, 80, false)
  local scraps = debris_pool(A.geometry('gore_scrap'), lit(MAT.MeshStandardMaterial.new({ name = 'gore.scraps', color = 0x3a3629, roughness = 0.35, metalness = 0, side = MAT.DoubleSide })), 120, false)

  -- ---------------------------------------------------------------- guts
  local GN, GS, GUTS = 11, 6, {}
  local gut_mat = lit(MAT.MeshStandardMaterial.new({ name = 'gore.gut', color = 0x6e3634, roughness = 0.22, metalness = 0 }))
  local follow_on = false
  for _ = 1, 10 do
    local g = T.BufferGeometry.new()
    g:set_attribute('position', T.float_attr(GN*GS, 3))
    g:set_attribute('normal', T.float_attr(GN*GS, 3))
    local idx = {}
    for i = 0, GN - 2 do for j = 0, GS - 1 do
      local a, b, c, d = i*GS + j, i*GS + (j + 1)%GS, (i + 1)*GS + (j + 1)%GS, (i + 1)*GS + j
      local o = #idx
      idx[o + 1], idx[o + 2], idx[o + 3], idx[o + 4], idx[o + 5], idx[o + 6] = a, d, c, a, c, b
    end end
    g:set_index(idx)
    local m = T.Mesh.new(g, gut_mat)
    m.cast_shadow = true; m.receive_shadow = true; m.frustum_culled = false; m.visible = false
    R.world_scene:add(m)
    local p, q = {}, {}
    for i = 1, GN do p[i] = Vector3.new(); q[i] = Vector3.new() end
    GUTS[#GUTS + 1] = { m = m, on = false, p = p, q = q, piece = nil, en = 1, t = 0, len = 0.05, r = 0.011, pl = 0 }
  end
  -- en: 1-based index into piece.ends
  local function gut(from, vel, piece, en)
    local G
    for _, q in ipairs(GUTS) do if not q.on then G = q; break end end
    if not G then return end
    G.on = true; G.t = 0; G.piece = piece; G.en = en; G.m.visible = true; G.pl = follow_on and PULL_T or 0; G.still = false
    G.len = rng.float(0.03, 0.045); G.r = rng.float(0.013, 0.018)
    for i = 0, GN - 1 do
      local sx = rng.spread(0.03)
      local sz = rng.spread(0.03)
      G.p[i + 1]:copy(from):add_scaled_vector(vel, i*0.002):add(V:set(sx, -i*0.012, sz))
      G.q[i + 1]:copy(G.p[i + 1]):add_scaled_vector(vel, -1/60*(0.3 + i/GN))
    end
  end
  local Tt, Bn, Nn = Vector3.new(), Vector3.new(), Vector3.new()
  local RCOS, RSIN = {}, {}
  for j = 0, GS - 1 do local a = j/GS*6.2832; RCOS[j] = cos(a); RSIN[j] = sin(a) end
  local function update_guts(dt)
    for _, G in ipairs(GUTS) do
      -- (still: every point moved less than 0.05 mm last tick, its piece (if any) lying still too, and not yet
      -- sinking; then it lies as it is: nothing it does would show)
      if G.on and G.still and G.t + dt <= PIECE_LIFE and not (G.piece and G.piece.on and G.piece.rest < 2.2) then
        G.t = G.t + dt; G.pl = G.pl - dt
      elseif G.on then
        G.t = G.t + dt; G.pl = G.pl - dt
        local P, Q0 = G.p, G.q
        for i = 1, GN do
          local vx, vy, vz = (P[i].x - Q0[i].x)*0.985, (P[i].y - Q0[i].y)*0.985, (P[i].z - Q0[i].z)*0.985
          Q0[i]:copy(P[i])
          P[i].x = P[i].x + vx; P[i].y = P[i].y + (vy - GRAV*dt*dt); P[i].z = P[i].z + vz
          if G.pl > 0 then tug(P[i].x, P[i].y, P[i].z, G.pl); P[i]:add_scaled_vector(TUG, dt*dt) end
        end
        local pc = (G.piece and G.piece.on) and G.piece or nil
        for _ = 1, 4 do
          if pc then local e = pc.ends[G.en]; if e then P[1]:copy(e['local']):apply_quaternion(pc.m.quaternion):add(pc.m.position) end end
          for i = 1, GN - 1 do
            V:sub_vectors(P[i + 1], P[i])
            local l = V:length(); if l == 0 then l = 1e-6 end
            local k = (l - G.len)/l*0.5
            if pc and i == 1 then P[2]:add_scaled_vector(V, -2*k) else P[i]:add_scaled_vector(V, k); P[i + 1]:add_scaled_vector(V, -k) end
          end
          for i = 1, GN do
            local g = gy(P[i].x, P[i].z) + G.r
            if P[i].y < g then P[i].y = g; Q0[i].x = P[i].x - (P[i].x - Q0[i].x)*0.4; Q0[i].z = P[i].z - (P[i].z - Q0[i].z)*0.4 end
          end
        end
        if G.t > PIECE_LIFE then for _, p in ipairs(P) do p.y = p.y - 0.25/SINK_T*dt end end
        local mv = 0
        for i = 1, GN do local dx, dy, dz = P[i].x - Q0[i].x, P[i].y - Q0[i].y, P[i].z - Q0[i].z; mv = max(mv, dx*dx + dy*dy + dz*dz) end
        G.still = G.t > 0.5 and mv < 2.5e-9
        local pos, nor = G.m.geometry.attributes.position.array, G.m.geometry.attributes.normal.array
        for i = 0, GN - 1 do
          Tt:sub_vectors(P[min(GN - 1, i + 1) + 1], P[max(0, i - 1) + 1]):normalize()
          Bn:cross_vectors(Tt, UP); if Bn:length_sq() < 1e-6 then Bn:set(1, 0, 0) end; Bn:normalize(); Nn:cross_vectors(Bn, Tt)
          local r = G.r*((i == 0 or i == GN - 1) and 0.6 or 1)*(1 + 0.35*sin(i*2.3 + G.len*97))
          for j = 0, GS - 1 do
            local cx, cy = RCOS[j], RSIN[j]
            local o = (i*GS + j)*3
            nor[o + 1] = Bn.x*cx + Nn.x*cy; nor[o + 2] = Bn.y*cx + Nn.y*cy; nor[o + 3] = Bn.z*cx + Nn.z*cy
            pos[o + 1] = P[i + 1].x + nor[o + 1]*r; pos[o + 2] = P[i + 1].y + nor[o + 2]*r; pos[o + 3] = P[i + 1].z + nor[o + 3]*r
          end
        end
        G.m.geometry.attributes.position.needs_update = true; G.m.geometry.attributes.normal.needs_update = true
        if G.t > PIECE_LIFE + SINK_T then G.on = false; G.m.visible = false end
      end
    end
  end

  -- ---------------------------------------------------------------- the burst
  local MEAT_C = { { 0.2, 0.012, 0.009 }, { 0.3, 0.03, 0.022 }, { 0.13, 0.007, 0.006 }, { 0.4, 0.1, 0.075 }, { 0.26, 0.06, 0.04 } }
  local function meat_c() return MEAT_C[rng.int(0, #MEAT_C - 1) + 1] end
  local TW = Vector3.new()
  local function burst(s, mid, toward)
    local arc = snakes.arc
    local c = s.spine[mid + 1]:clone()
    local cm = arc(mid)
    if toward then TW:sub_vectors(toward, c); TW.y = max(TW.y, -0.2*TW:length()); TW:normalize() else TW:set(0, 0, 0) end
    local function pull(o, lo, hi) local k = rng.float(lo, hi); o.x = o.x + TW.x*k; o.y = o.y + TW.y*k; o.z = o.z + TW.z*k; return o end
    follow_on = not not toward
    local PL = follow_on and PULL_T or 0
    local a, b = mid, mid
    while a > 1 and cm - arc(a) < 0.28 do a = a - 1 end
    while b < N - 2 and arc(b) - cm < 0.3 do b = b + 1 end
    local pieces = {}
    local function throw_piece(P)
      if not P then return end
      local out = V:sub_vectors(P.m.position, c); out.y = max(out.y, 0) + 0.2
      out:normalize()
      local sp = rng.float(2.2, 4.2)
      local vx = out.x*sp + rng.spread(0.8)
      local vy = rng.float(1.2, 3.0) + out.y*sp*0.3
      local vz = out.z*sp + rng.spread(0.8)
      P.v:set(vx, vy, vz)
      pull(P.v, 0.6, 1.5); P.pl = follow_on and PULL_T or 0
      local wx = rng.spread(1)
      local wy = rng.spread(1)
      local wz = rng.spread(1)
      P.w:set(wx, wy, wz):normalize():multiply_scalar(rng.float(4, 11))
      pieces[#pieces + 1] = P
    end
    local i1 = a
    while i1 > 0 do
      local i0 = i1
      local len = rng.float(0.3, 0.6)
      while i0 > 0 and arc(i1) - arc(i0) < len and i1 - i0 < MAXR - 1 do i0 = i0 - 1 end
      if i0 <= 2 then i0 = 0 end
      throw_piece(make_piece(s, i0, i1))
      i1 = i0
    end
    local j0 = b
    while j0 < N - 1 do
      local j1 = j0
      local len = rng.float(0.35, 0.7)
      while j1 < N - 1 and arc(j1) - arc(j0) < len and j1 - j0 < MAXR - 1 do j1 = j1 + 1 end
      if j1 >= N - 3 then j1 = N - 1 end
      throw_piece(make_piece(s, j0, j1))
      j0 = j1
    end
    local function burst_at(i, r0, v0, v1)
      local p = s.spine[i + 1]
      local dx = rng.spread(1)
      local dy = rng.spread(1)
      local dz = rng.spread(1)
      local dir = V:set(dx, dy, dz):normalize()
      local x, y, z = p.x + dir.x*r0, p.y + dir.y*r0, p.z + dir.z*r0
      local sp = rng.float(v0, v1)
      local vx = dir.x*sp + (p.x - c.x)*1.5
      local vy = abs(dir.y)*sp*0.8 + rng.float(0.8, 2.4)
      local vz = dir.z*sp + (p.z - c.z)*1.5
      return { x = x, y = y, z = z, vx = vx, vy = vy, vz = vz, pl = PL }
    end
    for _ = 1, 46 do
      local i = rng.int(a, b)
      local o = burst_at(i, s.radii[i + 1]*0.6, 1.5, 5.0)
      local pv = pull({ x = o.vx, y = o.vy, z = o.vz }, 0.4, 1.3)
      o.vx = pv.x; o.vy = pv.y; o.vz = pv.z; o.pl = follow_on and PULL_T or 0
      o.s = rng.float(0.012, 0.035); o.sx = rng.float(0.7, 1.4); o.sy = rng.float(0.5, 1.0); o.sz = rng.float(0.7, 1.5); o.c = meat_c(); o.bleed = 0.25
      meat.spawn(o)
    end
    for _ = 1, 14 do
      local i = rng.int(a, b)
      local o = burst_at(i, s.radii[i + 1], 1.2, 3.5)
      o.s = rng.float(0.03, 0.06); o.sx = rng.float(0.8, 1.3); o.sy = rng.float(0.5, 1.0); o.sz = 1
      scraps.spawn(o)
    end
    for _ = 1, 16 do
      local i = rng.int(a, b)
      local o = burst_at(i, s.radii[i + 1]*0.4, 1.5, 4.5)
      o.s = rng.float(0.035, 0.055); o.sx = 1; o.sy = 1; o.sz = 1
      ribs.spawn(o)
    end
    for _ = 1, 6 do
      local i = rng.int(a, b)
      local o = burst_at(i, 0.01, 1.0, 3.0)
      o.s = rng.float(0.011, 0.016); o.sx = 1.3; o.sy = 0.9; o.sz = 1
      verts.spawn(o)
    end
    -- guts from the two pieces nearest the tear (a stable sort, as JS's), and a loop thrown free
    local order = {}
    for k, P in ipairs(pieces) do order[k] = { P = P, d = P.m.position:distance_to(c), k = k } end
    table.sort(order, function(p, q) if p.d ~= q.d then return p.d < q.d end; return p.k < q.k end)
    for n = 1, min(2, #order) do
      local P = order[n].P
      if #P.ends > 0 then
        local ei = 1
        if #P.ends > 1 then
          ei = (P.ends[1]['local']:clone():add(P.m.position):distance_to(c) < P.ends[2]['local']:clone():add(P.m.position):distance_to(c)) and 1 or 2
        end
        local e = P.ends[ei]
        V2:copy(e['local']):add(P.m.position)
        gut(V2:clone(), P.v:clone():multiply_scalar(0.8), P, ei)
      end
    end
    do
      local gx = rng.spread(2)
      local gyv = rng.float(1, 2.5)
      local gz = rng.spread(2)
      gut(c:clone(), pull(V:set(gx, gyv, gz), 1.0, 2.0):clone(), nil, 1)
    end
    for j = 0, 4 do
      local dx = rng.spread(1)
      local dy = rng.float(-0.3, 0.9)
      local dz = rng.spread(1)
      local d = V2:set(dx, dy, dz):normalize():clone()
      if j < 2 and toward then
        local ox = rng.spread(0.5)
        local oy = rng.float(0, 0.4)
        local oz = rng.spread(0.5)
        d:copy(TW):add(V:set(ox, oy, oz)):normalize()
      end
      local sp0 = rng.float(3, 6)
      for _ = 1, 26 do
        local sp = sp0*rng.float(0.5, 1.1)
        local vx = d.x*sp + rng.spread(0.5)
        local vy = d.y*sp + rng.spread(0.5)
        local vz = d.z*sp + rng.spread(0.5)
        drop(c.x, c.y, c.z, vx, vy, vz, rng.float(0.014, 0.028), 0.45, PL)
      end
    end
    for _ = 1, 80 do
      local i = rng.int(a, b)
      local p = s.spine[i + 1]
      local dx = rng.spread(1)
      local dy = rng.spread(1)
      local dz = rng.spread(1)
      local d = V2:set(dx, dy, dz):normalize()
      local sp = rng.float(0.8, 4.0)
      drop(p.x, p.y, p.z, d.x*sp + TW.x*0.9, d.y*sp + 0.8, d.z*sp + TW.z*0.9, rng.float(0.01, 0.022), 0.4, PL)
    end
    for _ = 1, 40 do
      local i = rng.int(max(0, a - 6), min(N - 1, b + 6))
      local p = s.spine[i + 1]
      local x = p.x + rng.spread(0.05)
      local z = p.z + rng.spread(0.05)
      local vx = rng.spread(0.35)
      local vy = rng.float(-0.4, 0.3)
      local vz = rng.spread(0.35)
      drop(x, p.y, z, vx, vy, vz, rng.float(0.012, 0.022), 0.6)
    end
    splash(c.x, c.z, rng.float(0.7, 1.0), 1.6)
    do
      local x = c.x + rng.spread(0.3)
      local z = c.z + rng.spread(0.3)
      splash(x, z, rng.float(0.4, 0.6), 1.2)
    end
    for k = 0, 43 do
      local p = s.spine[rng.int(a, b) + 1]
      local near = k < 16
      local vx = rng.spread(near and 0.6 or 1.4)
      local vy = rng.float(-0.2, 0.9)
      local vz = rng.spread(near and 0.6 or 1.4)
      local life = rng.float(0.8, 1.7)
      local s0 = rng.float(0.1, 0.2)*(near and 1.5 or 1)
      local s1 = rng.float(0.3, 0.55)*(near and 1.3 or 1)
      fx.puff({ x = p.x, y = p.y, z = p.z, vx = vx, vy = vy, vz = vz, grav = 0.6, drag = 1.8, life = life, s0 = s0, s1 = s1, r = 0.03, g = 0.0025, b = 0.002, a = near and 0.7 or 0.45, fin = 0.02 })
    end
  end

  -- a snake crushed by a thrown rock at p
  local function crush(p, dir, r)
    r = r or 0.08
    for _ = 1, 60 do
      local sp = rng.float(1.5, 5.0)
      local dx = dir.x + rng.spread(0.9)
      local dy = rng.float(0.2, 1.1)
      local dz = dir.z + rng.spread(0.9)
      local d = V2:set(dx, dy, dz):normalize()
      drop(p.x, p.y + 0.03, p.z, d.x*sp, d.y*sp, d.z*sp, rng.float(0.01, 0.022), 0.5)
    end
    for _ = 1, 10 do
      local x = p.x + rng.spread(r)
      local z = p.z + rng.spread(r)
      local vx = dir.x*rng.float(1, 3) + rng.spread(1)
      local vy = rng.float(1, 2.5)
      local vz = dir.z*rng.float(1, 3) + rng.spread(1)
      local o = { x = x, y = p.y + 0.02, z = z, vx = vx, vy = vy, vz = vz }
      o.s = rng.float(0.012, 0.03); o.sx = rng.float(0.7, 1.4); o.sy = rng.float(0.5, 1.0); o.sz = rng.float(0.7, 1.5); o.c = meat_c(); o.bleed = 0.25
      meat.spawn(o)
    end
    for _ = 1, 3 do
      local vx = dir.x*rng.float(1, 2.5) + rng.spread(0.8)
      local vy = rng.float(0.8, 2)
      local vz = dir.z*rng.float(1, 2.5) + rng.spread(0.8)
      scraps.spawn({ x = p.x, y = p.y + 0.03, z = p.z, vx = vx, vy = vy, vz = vz, s = rng.float(0.03, 0.05), sx = 1, sy = 0.7, sz = 1 })
    end
    splash(p.x, p.z, rng.float(0.5, 0.8), 0.4)
    splash(p.x + dir.x*0.45, p.z + dir.z*0.45, rng.float(0.35, 0.5), 0.3, atan2(-dir.z, dir.x), 1.8)
    for _ = 1, 10 do
      local vx = dir.x*0.8 + rng.spread(0.8)
      local vy = rng.float(0, 0.6)
      local vz = dir.z*0.8 + rng.spread(0.8)
      fx.puff({ x = p.x, y = p.y + 0.05, z = p.z, vx = vx, vy = vy, vz = vz, grav = 0.6, drag = 1.8, life = rng.float(0.6, 1.2), s0 = 0.08, s1 = 0.3, r = 0.03, g = 0.0025, b = 0.002, a = 0.5, fin = 0.02 })
    end
  end

  -- a little gore where a beamed snake bursts along its body (pts: 1-based list of Vector3)
  local function spatter(pts)
    local np = #pts
    local function pick() return pts[rng.int(0, np - 1) + 1] end
    for _ = 1, 64 do
      local p = pick()
      local sp = rng.float(1.2, 4.2)
      local dx = rng.spread(1)
      local dy = rng.float(0.1, 1)
      local dz = rng.spread(1)
      local d = V2:set(dx, dy, dz):normalize()
      drop(p.x, p.y, p.z, d.x*sp, d.y*sp, d.z*sp, rng.float(0.009, 0.02), 0.5)
    end
    for _ = 1, 15 do
      local p = pick()
      local vx = rng.spread(2.5)
      local vy = rng.float(1, 3)
      local vz = rng.spread(2.5)
      local o = { x = p.x, y = p.y + 0.02, z = p.z, vx = vx, vy = vy, vz = vz }
      o.s = rng.float(0.012, 0.03); o.sx = rng.float(0.7, 1.4); o.sy = rng.float(0.5, 1.0); o.sz = rng.float(0.7, 1.5); o.c = meat_c(); o.bleed = 0.2
      meat.spawn(o)
    end
    for _ = 1, 4 do
      local p = pick()
      local vx = rng.spread(2)
      local vy = rng.float(0.8, 2.2)
      local vz = rng.spread(2)
      scraps.spawn({ x = p.x, y = p.y + 0.03, z = p.z, vx = vx, vy = vy, vz = vz, s = rng.float(0.03, 0.05), sx = 1, sy = 0.7, sz = 1 })
    end
    local c = pts[floor(np/2) + 1]
    local c2 = pick()
    splash(c.x, c.z, rng.float(0.55, 0.8), 0.5)
    do
      local x = c2.x + rng.spread(0.3)
      local z = c2.z + rng.spread(0.3)
      splash(x, z, rng.float(0.35, 0.5), 0.4)
    end
    for _ = 1, 14 do
      local p = pick()
      local vx = rng.spread(1.0)
      local vy = rng.float(0, 0.7)
      local vz = rng.spread(1.0)
      fx.puff({ x = p.x, y = p.y + 0.05, z = p.z, vx = vx, vy = vy, vz = vz, grav = 0.6, drag = 1.8, life = rng.float(0.6, 1.2), s0 = 0.08, s1 = 0.32, r = 0.03, g = 0.0025, b = 0.002, a = 0.45, fin = 0.02 })
    end
  end

  local gore = { burst = burst, crush = crush, spatter = spatter }
  -- round 58: the pieces flying and lying (not the blood or the stains on the floor), for the ending's silhouettes
  function gore.meshes(out)
    out = out or {}
    for _, p in ipairs(PIECES) do if p.on then out[#out + 1] = p.m end end
    for _, g in ipairs(GUTS) do if g.on then out[#out + 1] = g.m end end
    for _, pool in ipairs({ meat, ribs, verts, scraps }) do out[#out + 1] = pool.mesh end
    return out
  end
  function gore.follow(fn) follow = fn end
  function gore.pieces()
    local out = {}
    for i, p in ipairs(PIECES) do if p.on then out[#out + 1] = { i = i - 1, t = p.t, p = p.m.position:clone() } end end
    return out
  end
  function gore.update(t, dt)
    if follow then local L = follow(); TGT:set(L.x, L.y + 0.4, L.z) end
    update_pieces(dt); meat.update(dt); ribs.update(dt); verts.update(dt); scraps.update(dt); update_guts(dt); update_blood(dt); update_decals(dt)
  end
  function gore.set_camera(cam, H) bmat.uniforms.uScale.value = cam.projection_matrix.elements[6]*H*0.5 end
  return gore
end

return GO
