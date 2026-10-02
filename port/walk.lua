--[[
  walk.lua -- the rest of the game (owner, 2026-10-02): before the egg, a walk through the cave,
  gathering the six powers as their objects. A walking simulator: he only moves; Resident Evil's
  camera: each stretch of the walk is watched by a fixed camera, and crossing into the next cuts
  to it. Six chambers in six kinds of rock, each staged for how its object is found (the layout
  and the reasons: tools/walk/layout.mjs), joined by passages, ending in the final room's tunnel.

  Built offline by tools/walk/build.mjs into assets/port/walk (+ walk.lua, its manifest): the
  geometry per area with its baked bounce light, each area's probe grid (what lights him), the
  nav grid (walknav.lua), the cameras and their stretches, where the objects wait, the glow-worms
  and the other moving lights. Here: the areas' light (the sun down a shaft, or none; the bake's
  level; the post chain's atmosphere) switched with the camera, so a cut hides the change; the
  objects waiting and the taking of each (it rises to his hand; the inspect view opens; closing
  it, the power is his); and the step into the final room, which then plays as it always has.
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local LD = require('port.three.loader')
local U = require('port.util')
local WN = require('port.walknav')
local ITM = require('port.items')
local Vector3, Color = TM.Vector3, TM.Color
local clamp, smoothstep, lerp = U.clamp, U.smoothstep, U.lerp
local sqrt, abs, sin, cos, atan2, exp, floor, min, max, pi = math.sqrt, math.abs, math.sin, math.cos, math.atan, math.exp, math.floor, math.min, math.max, math.pi

local WK = {}

-- each area's look: the bake's level (gi), the sun down its shaft (sun: the room's direct
-- factor, 0 = no sun), exposure, fog colour (linear) and reach, the column's colour and density
WK.LOOK = {
  [0] = { gi = 22, sun = 0.42, exposure = 2.2, fog = { 0.004, 0.0037, 0.0034 }, fog_far = 45 },
  [1] = { gi = 2.5, sun = 0, exposure = 2.2, fog = { 0.012, 0.005, 0.002 }, fog_far = 40 },
  [2] = { gi = 12, sun = 0, exposure = 2.4, fog = { 0.002, 0.004, 0.008 }, fog_far = 60 },
  [3] = { gi = 24, sun = 0.42, exposure = 2.2, fog = { 0.005, 0.0035, 0.003 }, fog_far = 45 },
  [4] = { gi = 6, sun = 0.42, exposure = 2.3, fog = { 0.002, 0.006, 0.005 }, fog_far = 40 },
  [5] = { gi = 14, sun = 0.42, exposure = 2.1, fog = { 0.004, 0.0045, 0.006 }, fog_far = 50 },
  [6] = { gi = 14, sun = 0.26, exposure = 2.0, fog = { 0.006, 0.0045, 0.003 }, fog_far = 50 },
  [7] = { gi = 22, sun = 0.42, exposure = 2.2, fog = { 0.004, 0.0037, 0.0034 }, fog_far = 45 },
}
WK.SPEEDS = { { name = 'A WALK (1.9 M/S)', v = 1.9 }, { name = 'AS IN THE ROOM (2.6 M/S)', v = 2.6 } }

function WK.create(ctx)
  local R, cave, lich, mover, items, powers, fx, warp = ctx.R, ctx.cave, ctx.lich, ctx.mover, ctx.items, ctx.powers, ctx.fx, ctx.warp
  local A = LD.group('walk')
  local W = A.manifest.walk
  local nav = WN.load(A, W.nav)
  local P = R.params
  local GU = cave.GU
  local rng = U.make_rng(4041)
  local S = { area = -1, zone = 0, speed = 0, collected = {}, taking = nil, t = 0, entered = false }

  -- ------------------------------------------------------------------ the room's look, kept
  local sun = cave.sun
  local sc = sun.shadow.camera
  local room = {
    pos = sun.position:clone(), tgt = sun.target.position:clone(), intensity = sun.intensity,
    cam = { up = sc.up:clone(), left = sc.left, right = sc.right, top = sc.top, bottom = sc.bottom, near = sc.near, far = sc.far },
    fog = { color = P.fog.color:clone(), near = P.fog.near, far = P.fog.far, max = P.fog.max },
    shafts = P.shafts, exposure = P.exposure,
    gi = { up = GU.uGIUp.value, down = GU.uGIDown.value, min = GU.uGIMin.value:clone(), max = GU.uGIMax.value:clone() },
  }

  -- ------------------------------------------------------------------ materials, meshes
  local area_gi = {}
  for a = 0, 7 do area_gi[a] = { value = WK.LOOK[a].gi } end
  local mats = {}
  local function mat_of(a, key)
    local k = a .. '|' .. key
    if mats[k] then return mats[k] end
    local m = W.mats[key]
    local mat = MAT.MeshLambertMaterial.new({ name = m.prog, map = A.texture(m.tex), flat_shading = m.prog ~= 'cave.egg',
      side = m.prog == 'cave.wall' and MAT.DoubleSide or MAT.FrontSide })
    if m.prog == 'cave.rock' then mat.shadow_side = MAT.DoubleSide end
    mat.emissive:set_rgb(m.emissive[1], m.emissive[2], m.emissive[3])
    mat.custom = { uGIScale = area_gi[a] }
    mat.user_data.key = key
    mat.user_data.e0 = { m.emissive[1], m.emissive[2], m.emissive[3] }
    mats[k] = mat
    return mat
  end
  local groups = {}
  for a = 0, 7 do groups[a] = T.Group.new(); groups[a].name = 'walk_' .. a; R.world_scene:add(groups[a]) end
  for _, e in ipairs(W.meshes) do
    local m = T.Mesh.new(A.geometry(e.geo), mat_of(e.area, e.mat))
    m.cast_shadow = e.mat ~= 'lava' and e.mat ~= 'lava_hot' and e.mat ~= 'glass' and e.mat ~= 'glass_core' and e.mat ~= 'water'
    m.receive_shadow = true
    groups[e.area]:add(m)
  end
  -- the lid over the walk (shadow only), holed at the shafts
  local walk_lid = T.Mesh.new(A.geometry(W.lid), MAT.MeshBasicMaterial.new({ name = 'cave.occluder', color_write = false, depth_write = false, side = MAT.DoubleSide }))
  walk_lid.cast_shadow = true
  walk_lid.frustum_culled = false
  R.world_scene:add(walk_lid)
  -- the floating stones
  local floaters = {}
  for k, f in ipairs(W.floaters) do
    local pc = W.pieces[f.piece + 1]
    local m = T.Mesh.new(A.geometry(pc.geo), mat_of(pc.area, pc.mat))
    m.cast_shadow = true; m.receive_shadow = true
    m.position:set(pc.at[1], pc.at[2], pc.at[3])
    groups[pc.area]:add(m)
    floaters[k] = { m = m, at = pc.at, ph = rng.float(0, 6.28), sp = rng.float(0.25, 0.6), amp = 0.04 + 0.05*f.s, rx = rng.spread(0.25), ry = rng.spread(0.35), rz = rng.spread(0.25) }
  end

  -- ------------------------------------------------------------------ points: glow-worms, embers, spores, motes, colours
  local function points(n, name)
    local g = T.BufferGeometry.new()
    local pa, ca = T.float_attr(n, 3), T.float_attr(n, 3)
    g:set_attribute('position', pa); g:set_attribute('color', ca)
    local p = T.Points.new(g, MAT.PointsMaterial.new({ name = 'cave.dust', size = 1, size_attenuation = false, vertex_colors = true,
      transparent = true, blending = MAT.AdditiveBlending, depth_write = false }))
    p.frustum_culled = false
    p.name = name
    return p, pa, ca
  end
  -- glow-worms: still, each breathing slowly
  local GW = W.points.glowworms
  local nworm = #GW//4
  local worms, wpa, wca = points(nworm, 'walk.glowworms')
  R.world_scene:add(worms)                  -- (the cathedral's, and a few along every dark passage)
  for i = 0, nworm - 1 do
    wpa.array[i*3 + 1], wpa.array[i*3 + 2], wpa.array[i*3 + 3] = GW[i*4 + 1], GW[i*4 + 2], GW[i*4 + 3]
  end
  wpa.needs_update = true
  local worm_ph = {}
  for i = 1, nworm do worm_ph[i] = { rng.float(0, 6.28), rng.float(0.15, 0.5), GW[(i - 1)*4 + 4] } end
  -- embers rising off the lava
  local EM = W.points.embers
  local nspot = #EM//3
  local NE = 140
  local embers, epa, eca = points(NE, 'walk.embers')
  groups[1]:add(embers)
  local ember = {}
  for i = 1, NE do ember[i] = { life = -rng.float(0, 4) } end
  -- spores over the pool
  local NS = 160
  local spores, spa, sca = points(NS, 'walk.spores')
  groups[4]:add(spores)
  local spore = {}
  local water = W.anchors.water
  for i = 1, NS do
    spore[i] = { x = water.c[1] + rng.spread(water.r[1]*1.6), y = water.level + rng.float(0.2, 3.5), z = water.c[2] + rng.spread(water.r[2]*1.8),
      ph = rng.float(0, 6.28), sp = rng.float(0.05, 0.15), b = rng.float(0.3, 1) }
  end
  -- motes in each column of sun
  local shafts = {}
  for a = 0, 7 do
    for _, sh in ipairs(W.areas[a + 1].shafts) do
      local n = sh.r > 1.2 and 90 or 50
      local pts, pa, ca = points(n, 'walk.motes')
      groups[a]:add(pts)
      local d = {}
      for i = 1, n do d[i] = { h = rng.float(0.3, 14), a = rng.float(0, 6.283), r = sqrt(rng.next())*sh.r*0.9, v = rng.float(0.03, 0.12), w = rng.float(0.05, 0.25), b = rng.float(0.4, 1) } end
      shafts[#shafts + 1] = { pa = pa, ca = ca, d = d, sh = sh, n = n }
    end
  end
  -- colours thrown by the gem: speckles on the floor round it, in bands by distance (red outermost)
  local gem_it = W.items[5]
  local NR = 220
  local rainbow, rpa, rca = points(NR, 'walk.rainbow')
  groups[5]:add(rainbow)
  local speck = {}
  do
    local gx, gz = gem_it.at[1], gem_it.at[3]
    local n = 0
    for _ = 1, 4000 do
      if n >= NR then break end
      local a = rng.float(-1.2, 1.4) + 2.3
      local r = rng.float(1.1, 4.2)
      local x, z = gx + cos(a)*r, gz + sin(a)*r
      if not nav.is_blocked(x, z) then
        n = n + 1
        local hue = clamp((r - 1.1)/3.1, 0, 1)
        speck[n] = { x = x, y = nav.floor(x, z) + 0.02, z = z, hue = hue, ph = rng.float(0, 6.28), sp = rng.float(1.5, 4) }
      end
    end
    for i = 1, NR do
      local s = speck[i] or speck[1]
      rpa.array[(i - 1)*3 + 1], rpa.array[(i - 1)*3 + 2], rpa.array[(i - 1)*3 + 3] = s.x, s.y, s.z
    end
    rpa.needs_update = true
  end
  local function hue_rgb(h)
    -- violet (inner) to red (outer)
    local c = { { 0.5, 0.2, 1.0 }, { 0.2, 0.4, 1.0 }, { 0.2, 1.0, 0.5 }, { 1.0, 0.95, 0.25 }, { 1.0, 0.55, 0.15 }, { 1.0, 0.15, 0.1 } }
    local f = h*(#c - 1)
    local i = floor(f)
    local t = f - i
    local a, b = c[min(#c, i + 1)], c[min(#c, i + 2)]
    return lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t)
  end

  -- ------------------------------------------------------------------ the objects, waiting
  local SIZES = ITM.SIZES
  local display = {}
  for i0 = 0, 5 do
    local wi = items.W[i0 + 1]
    if i0 == 1 then ITM.set_hand_material(items.opts.hand_mat) end
    local g = wi.make()
    g.visible = true
    local k = wi.it.fixed_k or SIZES[items.opts.size + 1].k*(wi.it.floor_mul or 1)
    local it = W.items[i0 + 1]
    local d = { i = i0, g = g, k = k, at = Vector3.new(it.at[1], it.at[2], it.at[3]), s = it.s, area = it.area, state = 'waiting', t = 0, base_q = TM.Quaternion.new() }
    g.scale:set_scalar(k)
    g.position:copy(d.at)
    -- how each one rests (owner's objects, set where the scene stages them); the mask and the
    -- hand face the camera that watches them
    local face = 0
    for _, c in ipairs(W.cameras) do if c.item == i0 then face = atan2(c.eye[1] - it.at[1], c.eye[3] - it.at[3]) end end
    if i0 == 0 then
      -- upright on its column, leaning back a little against the taller one behind, looking out
      d.base_q:set_from_euler(TM.Euler.new(-0.28, face, 0, 'YXZ')); d.at.y = W.anchors.altar_top + 0.19*k
    elseif i0 == 1 then d.base_q:set_from_euler(TM.Euler.new(0, face, 0, 'YXZ')); d.at.y = W.anchors.stalagmite_top + 0.16*k
    elseif i0 == 4 then d.at.y = W.anchors.gem_top + 0.07*k
    elseif i0 == 5 then d.base_q:set_from_euler(TM.Euler.new(pi/2, 0, 0, 'YXZ')); d.at.y = W.anchors.ring_y + 0.01
    end
    g.position:copy(d.at)
    g.quaternion:copy(d.base_q)
    if wi.orbs then
      -- (make() built a fresh group: its orb meshes are its own children)
      d.orbs = {}
      for _, ix in ipairs(ITM.X().world[4].orbs) do d.orbs[#d.orbs + 1] = g.children[ix + 1] end
      for _, m in ipairs(d.orbs) do
        m.user_data.r = m.user_data.r or m.scale.x
        -- in the grotto: the lamp's glint instead of the sun's, and less of the final room's
        -- cave (their environment) in the glass
        local prev = m.on_before_render
        local U2 = m.material.user_data.U
        U2.uEnvK.value = U2.uEnvK.value*0.45
        m.on_before_render = function(self, r, c)
          prev(self, r, c)
          local lp = d.lamp
          if lp then
            local wp = Vector3.new():set_from_matrix_position(self.matrix_world)
            U2.uSunDir.value:set(lp[1] - wp.x, lp[2] - wp.y, lp[3] - wp.z):normalize()
            U2.uSunCol.value:set(4, 12, 10)
            U2.uLit.value = 1
          end
        end
      end
      g.scale:set_scalar(1)
    end
    R.world_scene:add(g)
    display[i0 + 1] = d
  end
  local function in_shaft(p, a)
    local ar = W.areas[a + 1]
    local best = 0
    for _, sh in ipairs(ar and ar.shafts or {}) do
      local S_ = W.sun.dir
      local ax, az = sh.at[1] + S_[1]/S_[2]*(p.y - sh.h0), sh.at[2] + S_[3]/S_[2]*(p.y - sh.h0)
      best = max(best, 1 - smoothstep(sh.r*0.85, sh.r*1.25, js_hypot(p.x - ax, p.z - az)))
    end
    return best
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
      -- the lodestone floats, turning slowly in its own field
      g.position:set(d.at.x, d.at.y + sin(t*0.8)*0.05, d.at.z)
      g.rotation:set(sin(t*0.31)*0.4, t*0.22, cos(t*0.27)*0.3)
    elseif d.i == 3 then
      g.position:copy(d.at)
      orbs_pose(d, t, d.k)
    elseif d.i == 4 then
      g.position:copy(d.at)
      g.rotation:set(0.15, t*0.12, 0.08)
    else
      g.position:copy(d.at)
      g.quaternion:copy(d.base_q)
    end
    -- the traced stones see whether they stand in the sun
    if d.i == 4 then local m = g.children[1]; m.material.user_data.U.uLit.value = in_shaft(g.position, d.area) end

  end

  -- ------------------------------------------------------------------ lamps: three point lights of its own
  -- (three.js compiled the programs for the room's nine point lights; while he walks, three of
  -- the room's, which only its powers light, are hidden and these take their places)
  local room_lights = {}
  R.world_scene:traverse(function(o) if o.is_point_light then room_lights[#room_lights + 1] = o end end)
  local lamps = {}
  for k = 1, 3 do
    local l = T.PointLight.new(0xffffff, 0, 6, 2)
    l.cast_shadow = false
    R.world_scene:add(l)
    lamps[k] = l
  end
  -- per area: { x, y above the floor, z, colour, intensity, reach, flicker }
  local function toward_cam(i0, d)
    -- a point d metres from object i0 toward the camera that watches it
    local it = W.items[i0 + 1]
    for _, c in ipairs(W.cameras) do if c.item == i0 then
      local dx, dz = c.eye[1] - it.at[1], c.eye[3] - it.at[3]
      local l = js_hypot(dx, dz)
      return it.at[1] + dx/l*d, it.at[3] + dz/l*d
    end end
    return it.at[1], it.at[3]
  end
  local mx, mz = toward_cam(0, 1.1)
  local ox, oz = toward_cam(3, 0.9)
  display[4].lamp = { ox, nav.floor(ox, oz) + 1.7, oz }
  local LAMPS = {
    [1] = { { mx, 0.45, mz, { 1.0, 0.42, 0.1 }, 2.6, 4.5, 1 } },
    [4] = { { ox, 1.7, oz, { 0.35, 1.0, 0.85 }, 1.2, 4, 0.2 } },
    -- the final room's tunnel: what its light at the far end throws back down it
    [8] = { { 0, 2.6, -14, { 1.0, 0.8, 0.55 }, 5.0, 36, 0, 0.9 }, { 0, 2.4, -38, { 1.0, 0.82, 0.6 }, 1.2, 14, 0, 0.9 } },
  }
  local function set_lamps(a, t)
    local list = LAMPS[a] or {}
    for k = 1, 3 do
      local l, spec = lamps[k], list[k]
      if spec then
        local fy = S.area == 8 and 0 or nav.floor(spec[1], spec[3])
        l.position:set(spec[1], fy + spec[2], spec[3])
        l.color:set_rgb(spec[4][1], spec[4][2], spec[4][3])
        local f = 1 + spec[7]*(0.12*sin(t*7.3 + k) + 0.08*sin(t*17.1 + 2*k))
        l.intensity = spec[5]*f
        l.distance = spec[6]
        l.decay = spec[8] or 2
      else
        l.intensity = 0
      end
    end
  end
  local function lamps_on(on)
    for k = 1, 3 do lamps[k].visible = on; if room_lights[k] then room_lights[k].visible = not on end end
  end
  lamps_on(true)
  S.lamps_on = lamps_on

  -- ------------------------------------------------------------------ the areas' light
  local lid = cave.lid
  local Sd = Vector3.new(W.sun.dir[1], W.sun.dir[2], W.sun.dir[3])
  local function aim_sun(a)
    local ar = W.areas[a + 1]
    local b = ar.box
    local tgt = Vector3.new((b.x0 + b.x1)/2, b.y0, (b.z0 + b.z1)/2)
    sun.target.position:copy(tgt)
    sun.position:copy(tgt):add_scaled_vector(Sd, 70)
    -- the shadow camera round the area (+ a margin for the passages either side)
    local X = Vector3.new(1, 0, 0)
    local Rx = X:clone():sub(Sd:clone():multiply_scalar(X:dot(Sd))):normalize()
    local Uy = Vector3.new():cross_vectors(Sd, Rx)
    sc.up:copy(Uy)
    local a0, a1, b0, b1 = math.huge, -math.huge, math.huge, -math.huge
    local m = 22
    for _, cx in ipairs({ b.x0 - m, b.x1 + m }) do for _, cy in ipairs({ b.y0 - 3, 26 }) do for _, cz in ipairs({ b.z0 - m, b.z1 + m }) do
      local v = Vector3.new(cx, cy, cz):sub(tgt)
      a0 = min(a0, v:dot(Rx)); a1 = max(a1, v:dot(Rx)); b0 = min(b0, v:dot(Uy)); b1 = max(b1, v:dot(Uy))
    end end end
    local tx, ty = (a1 - a0)/2048, (b1 - b0)/2048
    sc.left = floor(a0/tx)*tx; sc.right = math.ceil(a1/tx)*tx; sc.bottom = floor(b0/ty)*ty; sc.top = math.ceil(b1/ty)*ty
    sc.near = 1; sc.far = 130
    sc:update_projection_matrix()
  end
  local function dark_k() return cave.DARK[(S.dark or 1) + 1].gi/10 end
  local function apply(a)
    if a == S.area then return end
    S.area = a
    for k = 0, 7 do groups[k].visible = (a == 8 and k == 7) or (a ~= 8 and abs(k - a) <= 1) end
    walk_lid.visible = a ~= 8
    if a == 8 then
      -- the final room (its tunnel): everything as it was made
      sun.position:copy(room.pos); sun.target.position:copy(room.tgt); sun.intensity = room.intensity
      sc.up:copy(room.cam.up); sc.left, sc.right, sc.top, sc.bottom, sc.near, sc.far = room.cam.left, room.cam.right, room.cam.top, room.cam.bottom, room.cam.near, room.cam.far
      sc:update_projection_matrix()
      P.fog.color:copy(room.fog.color); P.fog.near, P.fog.far, P.fog.max = room.fog.near, room.fog.far, room.fog.max
      P.shafts = room.shafts; P.exposure = room.exposure
      GU.uGIUp.value, GU.uGIDown.value = room.gi.up, room.gi.down
      GU.uGIMin.value:copy(room.gi.min); GU.uGIMax.value:copy(room.gi.max)
      GU.uGIScale.value = cave.DARK[(S.dark or 1) + 1].gi
      if lid then lid.visible = true end
      return
    end
    local L = WK.LOOK[a]
    local ar = W.areas[a + 1]
    if lid then lid.visible = false end
    aim_sun(a)
    sun.intensity = room.intensity/0.42*L.sun
    P.fog.color:set_rgb(L.fog[1], L.fog[2], L.fog[3])
    P.fog.near, P.fog.far, P.fog.max = 6, L.fog_far, 0.6
    P.exposure = L.exposure
    if #ar.shafts > 0 and L.sun > 0 then
      local sh = {}
      for k2, v in pairs(room.shafts) do sh[k2] = v end
      sh.top = ar.shafts[1].top; sh.max_dist = 40
      P.shafts = sh
    else
      P.shafts = { on = false, light = sun }
    end
    GU.uGIUp.value = A.texture(ar.gi.up); GU.uGIDown.value = A.texture(ar.gi.down)
    GU.uGIMin.value:set(ar.gi.min[1], ar.gi.min[2], ar.gi.min[3]); GU.uGIMax.value:set(ar.gi.max[1], ar.gi.max[2], ar.gi.max[3])
    GU.uGIScale.value = L.gi*dark_k()
  end
  function S.set_dark(i)
    S.dark = i
    for a = 0, 7 do area_gi[a].value = WK.LOOK[a].gi*dark_k() end
    local a = S.area; S.area = -1; apply(a)
  end

  -- ------------------------------------------------------------------ cameras
  local CAMS = W.cameras
  local function zone_at(s)
    for k, c in ipairs(CAMS) do if s >= c.s0 and s < c.s1 then return k end end
    return s < CAMS[1].s0 and 1 or #CAMS
  end
  local function pick_zone(L)
    local s = nav.s_at(L.x, L.z)
    if s < 0 then return S.zone > 0 and S.zone or 1 end
    local cur = CAMS[S.zone]
    if cur and s >= cur.s0 - 0.8 and s < cur.s1 + 0.8 then return S.zone end
    return zone_at(s)
  end
  function S.rig()
    local c = CAMS[S.zone] or CAMS[1]
    return Vector3.new(c.eye[1], c.eye[2], c.eye[3]), Vector3.new(c.tgt[1], c.tgt[2], c.tgt[3]), c.fov
  end

  -- ------------------------------------------------------------------ taking an object
  local function gaze_to(p)
    -- powers.lua's gaze_to: the head's turn and pitch toward a point
    local L = mover.p
    local yaw = mover.yaw()
    local dx, dz = p.x - L.x, p.z - L.z
    local a = atan2(dx, dz) - yaw
    a = atan2(sin(a), cos(a))
    local h = js_hypot(dx, dz)
    local pt = atan2(-(p.y - (L.y + 0.5)), max(0.2, h))
    return a, pt
  end
  local FLY = 1.15
  local function begin_take(d)
    d.state = 'rising'; d.t = 0
    d.from = d.g.position:clone()
    S.taking = d
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
    local to = tip
    d.g.position:copy(d.from):lerp(to, u)
    d.g.position.y = d.g.position.y + sin(u*pi)*0.25
    d.scale = 1 - 0.55*u
    if d.orbs then orbs_pose(d, S.t, d.k*d.scale) else d.g.scale:set_scalar(d.k*d.scale) end
    if d.t > FLY then
      d.state = 'held'; d.g.visible = false
      if d.orbs then for _, m in ipairs(d.orbs) do m.visible = false end end
      S.collected[d.i] = true
      ITM.ITEMS[d.i + 1].build = true
      if ctx.inspect then ctx.inspect.open(d.i) end
      S.after = d
    end
  end

  -- ------------------------------------------------------------------ the walk's tick
  local function update_points(t, dt)
    if S.area ~= 8 then
      local c = wca.array
      for i = 1, nworm do
        local w = worm_ph[i]
        local k = (0.55 + 0.45*sin(t*w[2] + w[1]))*w[3]
        local o = (i - 1)*3
        c[o + 1] = 0.12*k; c[o + 2] = 0.55*k; c[o + 3] = 1.25*k
      end
      wca.needs_update = true
    end
    if groups[1].visible then
      local pa, ca = epa.array, eca.array
      for i = 1, NE do
        local e = ember[i]
        e.life = e.life - dt
        if e.life <= 0 then
          local sp = rng.int(0, nspot - 1)
          e.x, e.y, e.z = EM[sp*3 + 1], EM[sp*3 + 2], EM[sp*3 + 3]
          e.vx, e.vy, e.vz = rng.spread(0.12), rng.float(0.3, 0.9), rng.spread(0.12)
          e.life = rng.float(1.2, 3.2); e.l0 = e.life
        end
        e.x = e.x + (e.vx + sin(t*2 + i)*0.08)*dt; e.y = e.y + e.vy*dt; e.z = e.z + (e.vz + cos(t*1.7 + i)*0.08)*dt
        local o = (i - 1)*3
        pa[o + 1], pa[o + 2], pa[o + 3] = e.x, e.y, e.z
        local k = e.l0 and clamp(e.life/e.l0, 0, 1) or 0
        k = k*k*(0.7 + 0.3*sin(t*13 + i))
        ca[o + 1] = 3.2*k; ca[o + 2] = 1.1*k; ca[o + 3] = 0.25*k
      end
      epa.needs_update = true; eca.needs_update = true
    end
    if groups[4].visible then
      local pa, ca = spa.array, sca.array
      for i = 1, NS do
        local s = spore[i]
        s.y = s.y + sin(t*0.3 + s.ph)*0.04*dt + s.sp*0.2*dt
        if s.y > water.level + 4 then s.y = water.level + 0.2 end
        local o = (i - 1)*3
        pa[o + 1] = s.x + sin(t*0.21 + s.ph)*0.4; pa[o + 2] = s.y; pa[o + 3] = s.z + cos(t*0.17 + s.ph)*0.4
        local k = s.b*(0.5 + 0.5*sin(t*0.9 + s.ph))*0.5
        ca[o + 1] = 0.15*k; ca[o + 2] = 0.9*k; ca[o + 3] = 0.75*k
      end
      spa.needs_update = true; sca.needs_update = true
    end
    for _, sf in ipairs(shafts) do
      local pa, ca = sf.pa.array, sf.ca.array
      local sh = sf.sh
      for i = 1, sf.n do
        local d = sf.d[i]
        d.h = d.h - d.v*dt; d.a = d.a + d.w*dt
        if d.h < 0.2 then d.h = 14 end
        local y = sh.h0 + d.h
        local cx, cz = sh.at[1] + W.sun.dir[1]/W.sun.dir[2]*d.h, sh.at[2] + W.sun.dir[3]/W.sun.dir[2]*d.h
        local o = (i - 1)*3
        pa[o + 1] = cx + cos(d.a)*d.r; pa[o + 2] = y; pa[o + 3] = cz + sin(d.a)*d.r
        local tw = 0.6 + 0.4*sin(t*1.7 + i*1.3)
        local k = d.b*tw*0.5
        ca[o + 1] = 1.5*k; ca[o + 2] = 1.25*k; ca[o + 3] = 0.8*k
      end
      sf.pa.needs_update = true; sf.ca.needs_update = true
    end
    if groups[5].visible then
      local ca = rca.array
      for i = 1, NR do
        local s = speck[i] or speck[1]
        local r, g, b = hue_rgb(s.hue)
        local k = max(0, sin(t*s.sp + s.ph))^3*1.6
        local o = (i - 1)*3
        ca[o + 1] = r*k; ca[o + 2] = g*k; ca[o + 3] = b*k
      end
      rca.needs_update = true
    end
    -- the floating stones drift
    if groups[3].visible then
      for _, f in ipairs(floaters) do
        f.m.position:set(f.at[1] + sin(t*f.sp*0.7 + f.ph)*f.amp, f.at[2] + sin(t*f.sp + f.ph)*f.amp*1.6, f.at[3] + cos(t*f.sp*0.6 + f.ph)*f.amp)
        f.m.rotation:set(sin(t*0.2 + f.ph)*f.rx, t*f.ry*0.3, cos(t*0.17 + f.ph)*f.rz)
      end
    end
    -- glows that breathe: the lava, the fungi, the burning point
    for _, m in pairs(mats) do
      local key = m.user_data.key
      local e = m.user_data.e0
      if key == 'lava' or key == 'lava_hot' then
        local f = 0.82 + 0.12*sin(t*1.3) + 0.06*sin(t*3.7 + 1)
        m.emissive:set_rgb(e[1]*f, e[2]*f, e[3]*f)
      elseif key == 'fungus_cap' then
        local f = 0.8 + 0.2*sin(t*0.6)
        m.emissive:set_rgb(e[1]*f, e[2]*f, e[3]*f)
      elseif key == 'glass_core' then
        local f = 0.75 + 0.25*sin(t*9) *sin(t*5.3)
        m.emissive:set_rgb(e[1]*f, e[2]*f, e[3]*f)
      end
    end
  end
  local smoke_t = 0
  function S.tick(t, dt)
    S.t = t
    local L = mover.p
    -- the camera: which stretch he is in
    local z = pick_zone(L)
    if z ~= S.zone then S.zone = z; S.cut = true end
    apply(CAMS[S.zone].area)
    -- the objects
    for _, d in ipairs(display) do
      if d.state == 'waiting' then
        idle(d, t)
        local s = nav.s_at(L.x, L.z)
        if not S.hold and (js_hypot(L.x - d.at.x, L.z - d.at.z) < 2.1 or (s > d.s + 2.0 and s < d.s + 30)) then begin_take(d) end
      elseif d.state == 'rising' then
        take_tick(d, dt)
      end
    end
    -- him: while one rises he turns to it and reaches for it
    local m = mover.motion
    if S.taking and S.taking.state == 'rising' then
      local d = S.taking
      mover.face.on = true
      mover.face.yaw = atan2(d.g.position.x - L.x, d.g.position.z - L.z)
      mover.face.half = 0.08
      m.gaze_w = 0.9
      m.gaze, m.gaze_p = gaze_to(d.g.position)
      local w = smoothstep(0, 0.35, d.t)*(1 - smoothstep(FLY - 0.1, FLY, d.t))
      m.point = { w = w*w*(3 - 2*w), arm = 1, x = d.g.position.x, y = d.g.position.y, z = d.g.position.z }
    else
      if S.taking then S.taking = nil end
      mover.face.on = false
      m.gaze_w = 0
      m.point = nil
    end
    -- smoke off the burning point
    smoke_t = smoke_t - dt
    if groups[6].visible and smoke_t <= 0 then
      smoke_t = 0.12
      local b = W.anchors.burn
      fx.puff({ x = b[1] + rng.spread(0.05), y = b[2] + 0.04, z = b[3] + rng.spread(0.05), vx = rng.spread(0.05), vy = rng.float(0.25, 0.45), vz = rng.spread(0.05),
        drag = 0.6, life = rng.float(1.6, 2.6), s0 = 0.04, s1 = 0.35, r = 0.12, g = 0.11, b = 0.1, a = 0.25 })
    end
    update_points(t, dt)
    set_lamps(S.area, t)
  end
  -- after the inspect view closes on a newly taken object: the power is his
  function S.after_inspect()
    local d = S.after
    if not d then return end
    S.after = nil
    powers.set(d.i, true)
  end
  function S.busy() return S.taking ~= nil and S.taking.state == 'rising' end
  function S.apply_room() apply(8) end
  function S.area_now() return S.area end

  -- ------------------------------------------------------------------ start, jumps
  local ENTRY = {}            -- where each area starts (s), for the jumps
  for a = 0, 7 do ENTRY[a] = W.areas[a + 1].s0 end
  function S.reset(upto)
    -- the objects before area `upto` are his already; the rest wait
    S.collected = {}
    for i0 = 0, 5 do
      local d = display[i0 + 1]
      local had = d.area < upto
      d.state = had and 'held' or 'waiting'
      d.g.visible = not had
      if d.orbs then for _, m in ipairs(d.orbs) do m.visible = not had end end
      d.scale = 1
      if not d.orbs then d.g.scale:set_scalar(d.k) end
      S.collected[i0] = had or nil
      ITM.ITEMS[i0 + 1].build = had
      powers.set(i0, had)
    end
    S.taking = nil; S.after = nil
    S.zone = 0; S.area = -1
  end
  S.nav = nav
  S.W = W
  S.display = display
  S.groups = groups
  S.ground_y = function(x, z) return nav.floor(x, z) end
  S.ENTRY = ENTRY
  S.CAMS = CAMS
  S.zone_at = zone_at
  -- snakes: out of sight until the room begins
  return S
end

return WK
