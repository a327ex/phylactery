--[[
  cave.lua -- the port to Anchor: web/src/cave.js. The dream's cave: the chamber, the shaft of
  sun onto the egg, the tunnel, the rocks. The geometry and its baked bounce light are the three.js
  build's (assets/port/cave.lua: made once there from the same seed); what runs is here: the
  floor's height (the same noise), the sun and its shadow camera, the lid, the egg, the dust in the
  column, the atmosphere for the post chain, the darkness levels.
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local LD = require('port.three.loader')
local U = require('port.util')
local Vector2, Vector3, Color = TM.Vector2, TM.Vector3, TM.Color
local smoothstep, fbm3, noise3 = U.smoothstep, U.fbm3, U.noise3

local C = {}

C.LAYOUT = {
  egg = Vector3.new(0, 0, 0),
  sun_dir = Vector3.new(0.11, 1, 0.05):normalize(),
  floor_r = 15.5,
  tunnel_theta = -math.pi/2,
  tunnel_half_w = 2.7, tunnel_h = 4.2,
  hover = Vector3.new(0, 0, -1.9),
  entrance = Vector3.new(0, 0, -40),
}

local MOUND = 0.3
-- cave.js's ground_y as written (the reference for the fast one below)
function C.ground_y_ref(x, z)
  local r2 = x*x + z*z
  local r = math.sqrt(r2)
  local y = (U.fbm3_lua(x*0.21, 0, z*0.21, 91) - 0.5)*0.7 + (U.noise3_lua(x*0.9, 7.1, z*0.9, 93) - 0.5)*0.14
  local rid = 1 - math.abs(U.fbm3_lua(x*0.13, 3.3, z*0.13, 97, 2)*2 - 1)
  y = y + rid^6*0.55*smoothstep(3.5, 7, r)
  y = y + MOUND*math.exp(-r2/4.0)
  y = y + smoothstep(12.5, 17.5, r)*1.4
  return y
end

-- The same numbers, faster (it runs for every snake ring, particle, chunk and body point every tick):
-- the noise in the engine (noise_fbm3 / noise_value3, the same bits); inside r 3.5 the ridge term is
-- multiplied by an exact 0, and inside 12.5 the wall term is.
local floor, M32 = math.floor, 0xFFFFFFFF
local function noise_y0(x, z, seed)
  local ix, iz = floor(x), floor(z)
  local fx, fz = x - ix, z - iz
  local u, w = fx*fx*(3 - 2*fx), fz*fz*(3 - 2*fz)
  local ax0, ax1 = (ix*374761393) & M32, ((ix + 1)*374761393) & M32
  local az0, az1 = (iz*2147483647) & M32, ((iz + 1)*2147483647) & M32
  local as = (seed*1442695041) & M32
  local h, c000, c100, c001, c101
  h = ax0 ~ az0 ~ as; h = ((h ~ (h >> 13))*1274126177) & M32; h = h ~ (h >> 16); c000 = (h & M32)/4294967296
  h = ax1 ~ az0 ~ as; h = ((h ~ (h >> 13))*1274126177) & M32; h = h ~ (h >> 16); c100 = (h & M32)/4294967296
  h = ax0 ~ az1 ~ as; h = ((h ~ (h >> 13))*1274126177) & M32; h = h ~ (h >> 16); c001 = (h & M32)/4294967296
  h = ax1 ~ az1 ~ as; h = ((h ~ (h >> 13))*1274126177) & M32; h = h ~ (h >> 16); c101 = (h & M32)/4294967296
  local a = c000 + (c100 - c000)*u
  local c = c001 + (c101 - c001)*u
  return a + (c - a)*w
end
local exp, sqrt, abs = math.exp, math.sqrt, math.abs
function C.ground_y(x, z)
  local r2 = x*x + z*z
  local r = sqrt(r2)
  local y = (noise_fbm3(x*0.21, 0, z*0.21, 91, 3) - 0.5)*0.7 + (noise_value3(x*0.9, 7.1, z*0.9, 93) - 0.5)*0.14
  if r > 3.5 then
    local rid = 1 - abs(noise_fbm3(x*0.13, 3.3, z*0.13, 97, 2)*2 - 1)
    y = y + rid^6*0.55*smoothstep(3.5, 7, r)
  else
    y = y + 0.0
  end
  y = y + MOUND*exp(-r2/4.0)
  if r > 12.5 then y = y + smoothstep(12.5, 17.5, r)*1.4 else y = y + 0.0 end
  return y
end

local function place(o, trs)
  o.position:set(trs.p[1], trs.p[2], trs.p[3])
  o.quaternion:set(trs.q[1], trs.q[2], trs.q[3], trs.q[4])
  o.scale:set(trs.s[1], trs.s[2], trs.s[3])
end

function C.build(R)
  local A = LD.group('cave')
  local X = A.manifest.cave
  local L = C.LAYOUT
  local group = T.Group.new()
  R.world_scene:add(group)
  local S = L.sun_dir
  local sun_xz = Vector2.new(S.x/S.y, S.z/S.y)
  local GU = { uGIScale = { value = 1 }, uGIUp = { value = A.texture(X.gi.up) }, uGIDown = { value = A.texture(X.gi.down) },
    uGIMin = { value = Vector3.new(X.gi.min[1], X.gi.min[2], X.gi.min[3]) }, uGIMax = { value = Vector3.new(X.gi.max[1], X.gi.max[2], X.gi.max[3]) } }

  -- the materials (Lambert, their map, the static bounce light gi_static adds)
  local M = {}
  for _, k in ipairs({ 'rock', 'wall', 'dome', 'floor', 'egg' }) do
    local m = X.materials[k]
    local mat = MAT.MeshLambertMaterial.new({ name = m.name, map = A.texture(m.map), side = m.side, shadow_side = m.shadow_side, flat_shading = m.flat })
    mat.color:set_rgb(m.color[1], m.color[2], m.color[3])
    mat.custom = { uGIScale = GU.uGIScale }
    M[k] = mat
  end
  -- (the order three.js created them in decides render sorting among equal keys: rock, wall, dome, floor, egg)
  local by_name = {}
  for _, m in pairs(M) do by_name[m.name] = m end

  local statics = {}
  local egg = T.Group.new()
  local shell
  for i, e in ipairs(X.meshes) do
    local m = T.Mesh.new(A.geometry(e.geo), by_name[e.material])
    place(m, e.trs)
    m.cast_shadow, m.receive_shadow = e.cast, e.receive
    if e.parent == 'egg' then egg:add(m); shell = m else group:add(m) end
    statics[#statics + 1] = m
  end

  -- the shadow-only lid over everything, holed at the shaft
  local lid = T.Mesh.new(A.geometry(X.lid.geo), MAT.MeshBasicMaterial.new({ name = 'cave.occluder', color_write = false, depth_write = false, side = MAT.DoubleSide }))
  place(lid, X.lid.trs)
  lid.cast_shadow = true
  lid.frustum_culled = false
  group:add(lid)

  -- the egg (its shell's mesh is one of the statics)
  egg.position:set(X.egg.position[1], X.egg.position[2], X.egg.position[3])
  egg.user_data.shell = shell
  group:add(egg)

  -- the sun
  local sun = T.DirectionalLight.new(0xffffff, X.sun.intensity)
  sun.color:set_rgb(X.sun.color[1], X.sun.color[2], X.sun.color[3])
  sun.position:set(X.sun.position[1], X.sun.position[2], X.sun.position[3])
  sun.target.position:set(X.sun.target[1], X.sun.target[2], X.sun.target[3])
  sun.cast_shadow = true
  local xs = X.sun.shadow
  sun.shadow.map_size:set(xs.map_size[1], xs.map_size[2])
  local sc = sun.shadow.camera
  sc.up:set(xs.camera.up[1], xs.camera.up[2], xs.camera.up[3])
  sc.left, sc.right, sc.top, sc.bottom, sc.near, sc.far = xs.camera.left, xs.camera.right, xs.camera.top, xs.camera.bottom, xs.camera.near, xs.camera.far
  sc:update_projection_matrix()
  sun.shadow.bias = xs.bias
  sun.shadow.normal_bias = xs.normal_bias
  sun.shadow.radius = xs.radius
  group:add(sun, sun.target)

  -- a glimpse of sky at the top of the shaft
  local disc = T.Mesh.new(A.geometry(X.sun_disc.geo), MAT.MeshBasicMaterial.new({ name = 'cave.sun_disc', color = Color.new(9, 8.4, 7.2), side = MAT.DoubleSide }))
  place(disc, X.sun_disc.trs)
  group:add(disc)

  -- the atmosphere (render.js params)
  local P = R.params
  R.world_scene.background = Color.new(0x000000)
  P.sky.on = false
  local f = P.fog
  f.near, f.far, f.max, f.curve, f.sky, f.base_y, f.falloff, f.height_mix = 8, 50, 0.6, 1.3, 0.0, 0, 0.0, 0.0
  f.color:set_rgb(0.004, 0.0037, 0.0034)
  P.shafts = { on = true, light = sun, color = { 0.74, 0.59, 0.34 }, density = 0.02, max_dist = 70, steps = 48, phase = 0.35, ambient = 0.0,
    streak = 0.85, rise = 1.0, soft = 0.00022, top = X.consts.LID_Y }
  P.dither_dark = { 0.04, 0.16 }
  R.set_shadow_light(sun)
  R.rebuild()
  P.bloom = { strength = 0.32, threshold = 1.25 }
  P.vignette = 0.3
  P.contrast = 1.04; P.saturation = 1.04
  P.lift = { 0.003, 0.002, 0.006 }

  -- dust in the column
  local DUST = #X.dust
  local dust = {}
  for i, d in ipairs(X.dust) do dust[i] = { h = d.h, a = d.a, r = d.r, v = d.v, w = d.w, b = d.b } end
  local dust_geo = T.BufferGeometry.new()
  local dpos, dcol = T.float_attr(DUST, 3), T.float_attr(DUST, 3)
  dust_geo:set_attribute('position', dpos)
  dust_geo:set_attribute('color', dcol)
  local dust_pts = T.Points.new(dust_geo, MAT.PointsMaterial.new({ name = 'cave.dust', size = 1, size_attenuation = false, vertex_colors = true,
    transparent = true, blending = MAT.AdditiveBlending, depth_write = false }))
  dust_pts.frustum_culled = false
  group:add(dust_pts)
  local function update_dust(t, dt)
    local pa, ca = dpos.array, dcol.array
    for i = 1, DUST do
      local d = dust[i]
      d.h = d.h - d.v*dt; d.a = d.a + d.w*dt
      if d.h < 0.2 then d.h = 20 end
      local cx, cz = sun_xz.x*d.h, sun_xz.y*d.h
      local o = (i - 1)*3
      pa[o + 1] = cx + math.cos(d.a)*d.r; pa[o + 2] = d.h; pa[o + 3] = cz + math.sin(d.a)*d.r
      local tw = 0.6 + 0.4*math.sin(t*1.7 + (i - 1)*1.3)
      local k = d.b*tw*(0.55 + 0.45*math.min(1, d.h/10))*0.6
      ca[o + 1] = 1.5*k; ca[o + 2] = 1.25*k; ca[o + 3] = 0.8*k
    end
    dpos.needs_update = true
    dcol.needs_update = true
  end

  local DARK = {
    { name = 'DIMMER', gi = 5, exposure = 2.2 },
    { name = 'BETWEEN DIM AND READABLE', gi = 10, exposure = 2.2 },
    { name = 'BRIGHTER', gi = 18, exposure = 2.2 },
  }
  local dome_mats = { M.dome }
  local cave = {
    group = group, ground_y = C.ground_y, egg = egg, sun = sun, LAYOUT = L, GU = GU, rock_geo = statics[5] and statics[5].geometry,
    rock_tex = A.texture('cave_rock'), DARK = DARK, statics = statics, assets = A,
  }
  -- round 41: the surfaces. AS EXPORTED = the three.js build's textures on its UVs (one projection per
  -- triangle, so on the curved shell the pattern jumps at triangle edges); SLABS, MIX (round 42: his
  -- pick, between the two) and QUIET =
  -- tools/cave_look.py's textures (4 m tiles, close tones, no dark crack round every patch) on its
  -- continuous UVs for the shell (wall, dome, tunnel, floor). The rocks keep their UVs.
  local SURF = {
    { name = 'AS EXPORTED' },
    { name = 'SLABS', rock = 'cave_rock_slabs', floor = 'cave_floor_slabs' },
    { name = 'MIX', rock = 'cave_rock_mix', floor = 'cave_floor_mix' },
    { name = 'QUIET', rock = 'cave_rock_quiet', floor = 'cave_floor_quiet' },
  }
  local tex_meta = A.manifest.textures
  for _, s in ipairs(SURF) do
    for _, t in ipairs({ s.rock or false, s.floor or false }) do
      if t and not tex_meta[t] then
        local meta = {}
        for k, v in pairs(tex_meta.cave_rock) do meta[k] = v end
        meta.w, meta.h, meta['repeat'] = 128, 128, { 0.5, 0.5 }
        tex_meta[t] = meta
      end
    end
  end
  local shells = {}
  for i, e in ipairs(X.meshes) do
    if e.geo == 'cave_0' or e.geo == 'cave_1' or e.geo == 'cave_2' or e.geo == 'cave_3' then
      local g = statics[i].geometry
      shells[#shells + 1] = { g = g, uv = g.attributes.uv, uvc = A.attribute(e.geo, 'uvc', 2) }
    end
  end
  cave.SURF = SURF
  function cave.set_surface(i)
    local n = #SURF
    local s = SURF[((i % n) + n) % n + 1]
    for _, sh in ipairs(shells) do
      local uv = s.rock and sh.uvc or sh.uv
      if sh.g.attributes.uv ~= uv then sh.g.attributes.uv = uv; sh.g.gpu_dirty = true end
    end
    for _, k in ipairs({ 'rock', 'wall', 'dome' }) do M[k].map = A.texture(s.rock or X.materials[k].map) end
    M.floor.map = A.texture(s.floor or X.materials.floor.map)
    return s.name
  end
  -- round 45: the tunnel goes on past its old end (port/way.lua): its cap (the triangles beyond
  -- z -46.2, a fan round its centre at -47.5) comes off, in every attribute and both UV sets
  function cave.drop_tunnel_cap()
    for _, sh in ipairs(shells) do
      local g = sh.g
      if g.name == 'cave_2' and not sh.capless then
        local pos = g.attributes.position:ensure_array()
        local keep = {}
        for t = 0, #pos//9 - 1 do
          local zc = (pos[t*9 + 3] + pos[t*9 + 6] + pos[t*9 + 9])/3
          keep[t] = zc > -46.2
        end
        local function filt(a)
          local src = a:ensure_array()
          local n, out = a.item_size*3, {}
          for t = 0, #src//n - 1 do if keep[t] then for k = 1, n do out[#out + 1] = src[t*n + k] end end end
          return T.BufferAttribute.new(out, a.item_size)
        end
        local was_uvc = g.attributes.uv == sh.uvc
        for name, a in pairs(g.attributes) do if a ~= sh.uv and a ~= sh.uvc then g.attributes[name] = filt(a) end end
        sh.uv, sh.uvc = filt(sh.uv), filt(sh.uvc)
        g.attributes.uv = was_uvc and sh.uvc or sh.uv
        g.bounding_sphere = nil
        g.gpu_dirty = true
        sh.capless = true
      end
    end
  end
  -- round 47: the old tube kept only to z_tube (its collar and first stretch, where the door
  -- stands), and the egg room's floor strip down it only to z_floor (the rest is inside rock now)
  function cave.cut_tunnel(z_tube, z_floor)
    for _, sh in ipairs(shells) do
      local g = sh.g
      local cut = (g.name == 'cave_2' and z_tube) or (g.name == 'cave_3' and z_floor)
      if cut and not sh.cut then
        local pos = g.attributes.position:ensure_array()
        local keep = {}
        for t = 0, #pos//9 - 1 do
          local zc = (pos[t*9 + 3] + pos[t*9 + 6] + pos[t*9 + 9])/3
          local xc = (pos[t*9 + 1] + pos[t*9 + 4] + pos[t*9 + 7])/3
          keep[t] = g.name == 'cave_2' and zc > cut or not (zc < cut and math.abs(xc) < 6)
        end
        local function filt(a)
          local src = a:ensure_array()
          local n, out = a.item_size*3, {}
          for t = 0, #src//n - 1 do if keep[t] then for k = 1, n do out[#out + 1] = src[t*n + k] end end end
          return T.BufferAttribute.new(out, a.item_size)
        end
        local was_uvc = g.attributes.uv == sh.uvc
        for name, a in pairs(g.attributes) do if a ~= sh.uv and a ~= sh.uvc then g.attributes[name] = filt(a) end end
        sh.uv, sh.uvc = filt(sh.uv), filt(sh.uvc)
        g.attributes.uv = was_uvc and sh.uvc or sh.uv
        g.bounding_sphere = nil
        g.gpu_dirty = true
        sh.cut = true
      end
    end
  end
  cave.M = M
  function cave.set_dome_visible(on) for _, m in ipairs(dome_mats) do m.color_write = on; m.depth_write = on end end
  function cave.set_darkness(i)
    local n = #DARK
    local d = DARK[((i % n) + n) % n + 1]
    P.exposure = d.exposure
    GU.uGIScale.value = d.gi
    return d.name
  end
  local WQ, WAX = TM.Quaternion.new(), Vector3.new()
  function cave.update(t, dt)
    update_dust(t, dt)
    -- round 58 (the ending): user_data.wobble (radians) rocks the egg on its base about user_data.wobble_axis ({x, z})
    -- instead of its idle tremble
    local wb = egg.user_data.wobble
    if wb then
      local ax = egg.user_data.wobble_axis
      egg.quaternion:copy(WQ:set_from_axis_angle(WAX:set(ax[1], 0, ax[2]), wb))
      shell.rotation.z = 0; shell.rotation.x = 0
      return
    end
    local k = math.max(0, math.sin(t*0.9)*math.sin(t*2.3) - 0.55)*1.6*(1 - (egg.user_data.still or 0))
    shell.rotation.z = math.sin(t*38)*0.035*k
    shell.rotation.x = math.cos(t*31)*0.025*k
  end
  return cave
end

return C
