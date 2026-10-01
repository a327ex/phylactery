--[[
  three/renderer.lua -- the port to Anchor: three.js r170's WebGLRenderer, the path this game
  takes through it, drawn with the engine's gpu layer and three.js's own compiled programs:
  render lists sorted as three.js sorts them, the directional shadow pass (MeshDepthMaterial,
  RGBA-packed), the transmission pass (a 4x multisampled copy of the opaque scene, resolved and
  mipmapped, plus double-sided transmissive back faces), background clears, per-material state
  (culling, front face, blending, depth, colour mask, polygon offset), draw ranges and groups,
  instancing, points.

  Programs come from a library keyed by `material.name|scene.program_scene|side|instanced`
  (depth passes: `depth|side|instanced`), exported from the three.js build with the GLSL three.js
  compiled (tools: GAME.port_export in web/, programs.lua here).

  renderer.trace = {} records every draw (program key, uniforms) for comparison with a capture.
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local Vector3, Matrix4, Matrix3, Color = TM.Vector3, TM.Matrix4, TM.Matrix3, TM.Color

local RD = {}

-- ---------------------------------------------------------------------------- render targets
-- WebGLRenderTarget: opts.type 'half' (HalfFloat) | 'byte'; min_filter / mag_filter names;
-- depth_texture = true (a readable depth), depth = false (none); samples = n (multisampled: the
-- drawing target is a separate MSAA framebuffer resolved into this one's texture)
local RenderTarget = {}; RenderTarget.__index = RenderTarget
RD.RenderTarget = RenderTarget
function RenderTarget.new(w, h, opts)
  opts = opts or {}
  local rt = setmetatable({ width = w, height = h, opts = opts, is_render_target = true }, RenderTarget)
  rt:build()
  return rt
end
function RenderTarget:build()
  local o, w, h = self.opts, self.width, self.height
  local fmt = o.format or (o.type == 'byte' and 'rgba8' or 'rgba16f')
  local depth = 'buffer'
  if o.depth_texture then depth = 'texture' elseif o.depth == false then depth = false end
  self.gpu = gpu_target(w, h, { color = fmt, depth = depth, min = o.min_filter or 'nearest', mag = o.mag_filter or 'nearest', wrap = o.wrap or 'clamp' })
  self.texture = T.Texture.new(gpu_target_color(self.gpu), w, h)
  self.texture.is_render_target_texture = true
  if o.depth_texture then self.depth_texture = T.Texture.new(gpu_target_depth(self.gpu), w, h) end
  if (o.samples or 0) > 0 then self.msaa = gpu_target(w, h, { samples = o.samples, color = fmt, depth = depth ~= false }) end
  self.mipmapped = o.min_filter and o.min_filter:find('mipmap') ~= nil
end
function RenderTarget:set_size(w, h)
  if w == self.width and h == self.height then return end
  gpu_target_destroy(self.gpu); if self.msaa then gpu_target_destroy(self.msaa) end
  self.width, self.height = w, h
  self:build()
end
function RenderTarget:dispose() gpu_target_destroy(self.gpu); if self.msaa then gpu_target_destroy(self.msaa) end end

-- ---------------------------------------------------------------------------- the renderer
local Renderer = {}; Renderer.__index = Renderer
RD.Renderer = Renderer

-- programs: key -> { vs = source, fs = source } (compiled on first use)
function RD.new(opts)
  local r = setmetatable({
    library = opts.programs, compiled = {}, missing = {},
    clear_color = Color.new(0, 0, 0), clear_alpha = 1,
    auto_clear = true, sort_objects = true,
    target = nil, height = opts.height or 360, pixel_ratio = 1,
    shadow_map_enabled = true,
    transmission_targets = {},
    trace = nil,
    info = { draws = 0, programs = 0 },
  }, Renderer)
  r.depth_material = MAT.MeshDepthMaterial.new({ name = 'depth' })
  r._set = function(n, v) gpu_set(r._prog, n, v) end
  return r
end

function Renderer:program(key)
  local p = self.compiled[key]
  if p then return p end
  local src = self.library[key]
  if not src then
    if not self.missing[key] then self.missing[key] = true; print('three renderer: no program for ' .. key) end
    return nil
  end
  p = gpu_program(src.vs, src.fs, key)
  self.compiled[key] = p
  self.info.programs = self.info.programs + 1
  return p
end

function Renderer:set_clear_color(c, a) if type(c) == 'number' then self.clear_color:set_hex(c) else self.clear_color:copy(c) end; self.clear_alpha = a == nil and 1 or a end
function Renderer:get_render_target() return self.target end
function Renderer:set_render_target(rt)
  self.target = rt
  if rt then gpu_bind(rt.msaa or rt.gpu) end
end
function Renderer:clear(color, depth)
  if color == nil then color = true end
  if depth == nil then depth = true end
  local c = self.clear_color
  if color then gpu_clear(c.r, c.g, c.b, self.clear_alpha, depth and 1 or false)
  elseif depth then gpu_clear(nil, nil, nil, nil, 1) end
  if self.trace then self.trace[#self.trace + 1] = { op = 'clear', color = color and { c.r, c.g, c.b, self.clear_alpha } or nil, depth = depth } end
end
-- resolve a multisampled target into its texture; mipmaps when its filter wants them
function Renderer:finish_target(rt)
  if not rt then return end
  if rt.msaa then gpu_blit(rt.msaa, rt.gpu, 'nearest') end
  if rt.mipmapped then gpu_texture_mipmaps(rt.texture.gpu) end
end

-- ---------------------------------------------------------------------------- lights
local _v3 = Vector3.new()
local function collect(scene)
  local lights, casters = {}, {}
  scene:traverse_visible(function(o)
    if o.is_light then lights[#lights + 1] = o; if o.cast_shadow then casters[#casters + 1] = o end end
  end)
  return lights, casters
end
-- WebGLLights.setup + setupView
local function light_state(lights, camera)
  -- shadow casting first, the rest in scene order (a stable sort)
  local sorted = {}
  for i, l in ipairs(lights) do sorted[i] = { l = l, i = i } end
  table.sort(sorted, function(a, b)
    local ka, kb = a.l.cast_shadow and 2 or 0, b.l.cast_shadow and 2 or 0
    if ka ~= kb then return ka > kb end
    return a.i < b.i
  end)
  local L = { ambient = { 0, 0, 0 }, probe = {}, directional = {}, directional_shadow = {}, point = {} }
  for i = 1, 27 do L.probe[i] = 0 end
  local view = camera.matrix_world_inverse
  for _, e in ipairs(sorted) do
    local l = e.l
    if l.is_ambient_light then
      L.ambient[1] = L.ambient[1] + l.color.r*l.intensity
      L.ambient[2] = L.ambient[2] + l.color.g*l.intensity
      L.ambient[3] = L.ambient[3] + l.color.b*l.intensity
    elseif l.is_directional_light then
      local d = Vector3.new():set_from_matrix_position(l.matrix_world)
      _v3:set_from_matrix_position(l.target.matrix_world)
      d:sub(_v3):transform_direction(view)
      L.directional[#L.directional + 1] = { direction = { d.x, d.y, d.z }, color = { l.color.r*l.intensity, l.color.g*l.intensity, l.color.b*l.intensity } }
      if l.cast_shadow then
        local s = l.shadow
        L.directional_shadow[#L.directional_shadow + 1] = { intensity = s.intensity, bias = s.bias, normal_bias = s.normal_bias, radius = s.radius,
          map_size = { s.map_size.x, s.map_size.y }, map = s.map and s.map.texture.gpu or nil, matrix = s.matrix.elements }
      end
    elseif l.is_point_light then
      local p = Vector3.new():set_from_matrix_position(l.matrix_world):apply_matrix4(view)
      L.point[#L.point + 1] = { position = { p.x, p.y, p.z }, color = { l.color.r*l.intensity, l.color.g*l.intensity, l.color.b*l.intensity },
        distance = l.distance, decay = l.decay }
    end
  end
  return L
end

-- ---------------------------------------------------------------------------- geometry upload
local function gpu_mesh_of(object, geometry)
  local holder = object.is_instanced_mesh and object or geometry
  local m = holder.gpu_mesh
  if not m or geometry.gpu_dirty or holder.gpu_geometry ~= geometry then
    if m then gpu_mesh_destroy(m) end
    m = gpu_mesh()
    holder.gpu_mesh = m; holder.gpu_geometry = geometry
    holder.gpu_sizes = {}
    geometry.gpu_dirty = false
    for _, name in ipairs(geometry.attribute_order) do geometry.attributes[name].uploaded = nil end
    if geometry.index then geometry.index.uploaded = nil end
  end
  local sizes = holder.gpu_sizes
  local function up(name, a, divisor)
    local n = a.array and #a.array or #a.blob
    if sizes[name] ~= n then
      gpu_mesh_attr(m, name, a.item_size, a.array or a.blob, divisor, a.dynamic)
      sizes[name] = n; a.needs_update = false
    elseif a.needs_update then
      gpu_mesh_update(m, name, a.array)
      a.needs_update = false
    end
  end
  for _, name in ipairs(geometry.attribute_order) do up(name, geometry.attributes[name], 0) end
  if object.is_instanced_mesh then
    up('instanceMatrix', object.instance_matrix, 1)
    if object.instance_color then up('instanceColor', object.instance_color, 1) end
  end
  local idx = geometry.index
  if idx then
    local n = idx.array and #idx.array or #idx.blob
    if sizes.__index ~= n or idx.needs_update then
      gpu_mesh_index(m, idx.array or idx.blob, 32)
      sizes.__index = n; idx.needs_update = false
    end
  end
  return m
end

-- ---------------------------------------------------------------------------- state
local FACTOR = {
  [MAT.ZeroFactor] = 'zero', [MAT.OneFactor] = 'one', [MAT.SrcColorFactor] = 'src_color', [MAT.OneMinusSrcColorFactor] = 'one_minus_src_color',
  [MAT.SrcAlphaFactor] = 'src_alpha', [MAT.OneMinusSrcAlphaFactor] = 'one_minus_src_alpha', [MAT.DstAlphaFactor] = 'dst_alpha',
  [MAT.OneMinusDstAlphaFactor] = 'one_minus_dst_alpha', [MAT.DstColorFactor] = 'dst_color', [MAT.OneMinusDstColorFactor] = 'one_minus_dst_color',
}
local EQUATION = { [MAT.AddEquation] = 'add', [MAT.SubtractEquation] = 'subtract', [MAT.ReverseSubtractEquation] = 'reverse_subtract',
  [MAT.MinEquation] = 'min', [MAT.MaxEquation] = 'max' }
-- WebGLState.setMaterial / setBlending, as options for gpu_draw
local function draw_state(material, side, front_cw, o)
  if side == MAT.DoubleSide then o.cull = 'none' else o.cull = 'back' end
  local flip = side == MAT.BackSide
  if front_cw then flip = not flip end
  o.front = flip and 'cw' or 'ccw'
  local b = material.blending
  if b == MAT.NoBlending or (b == MAT.NormalBlending and not material.transparent) then
    o.blend = false
  else
    o.blend = true
    o.blend_eq, o.blend_eq_alpha = 'add', 'add'
    local pm = material.premultiplied_alpha
    if b == MAT.NormalBlending then
      if pm then o.blend_src, o.blend_dst, o.blend_src_alpha, o.blend_dst_alpha = 'one', 'one_minus_src_alpha', 'one', 'one_minus_src_alpha'
      else o.blend_src, o.blend_dst, o.blend_src_alpha, o.blend_dst_alpha = 'src_alpha', 'one_minus_src_alpha', 'one', 'one_minus_src_alpha' end
    elseif b == MAT.AdditiveBlending then
      if pm then o.blend_src, o.blend_dst, o.blend_src_alpha, o.blend_dst_alpha = 'one', 'one', 'one', 'one'
      else o.blend_src, o.blend_dst, o.blend_src_alpha, o.blend_dst_alpha = 'src_alpha', 'one', 'src_alpha', 'one' end
    elseif b == MAT.SubtractiveBlending then
      o.blend_src, o.blend_dst, o.blend_src_alpha, o.blend_dst_alpha = 'zero', 'one_minus_src_color', 'zero', 'one'
    elseif b == MAT.MultiplyBlending then
      if pm then o.blend_src, o.blend_dst, o.blend_src_alpha, o.blend_dst_alpha = 'zero', 'src_color', 'zero', 'src_alpha'
      else o.blend_src, o.blend_dst, o.blend_src_alpha, o.blend_dst_alpha = 'zero', 'src_color', 'zero', 'src_color' end
    else -- custom
      o.blend_src, o.blend_dst = FACTOR[material.blend_src], FACTOR[material.blend_dst]
      o.blend_src_alpha = FACTOR[material.blend_src_alpha or material.blend_src]
      o.blend_dst_alpha = FACTOR[material.blend_dst_alpha or material.blend_dst]
      o.blend_eq = EQUATION[material.blend_equation]
      o.blend_eq_alpha = EQUATION[material.blend_equation_alpha or material.blend_equation]
    end
  end
  o.depth_test, o.depth_write, o.color_write = material.depth_test, material.depth_write, material.color_write
  o.depth_func = 'lequal'
  o.polygon_offset = material.polygon_offset and { material.polygon_offset_factor, material.polygon_offset_units } or nil
  return o
end

-- ---------------------------------------------------------------------------- one draw
local _cam_pos = Vector3.new()
-- the program key, kept on the material (name|scene|side|instanced)
local function key_of(material, scene_tag, side, inst)
  local kc = material._keys
  if not kc or kc.name ~= material.name then kc = { name = material.name }; material._keys = kc end
  local a = kc[scene_tag]; if not a then a = {}; kc[scene_tag] = a end
  local b = a[side]; if not b then b = {}; a[side] = b end
  local k = b[inst]
  if not k then k = material.name .. '|' .. scene_tag .. '|' .. side .. '|' .. inst; b[inst] = k end
  return k
end
local _o, _env = {}, {}
function Renderer:draw(camera, scene_tag, object, geometry, material, group, side, lights, pass, key_override)
  if side == nil then side = material.side end
  local inst = object.is_instanced_mesh and 'i' or '-'
  -- (the program is the material's side's: a transparent double-sided one draws its back and front
  -- faces with it; the library holds one program per material side)
  local key = key_override or key_of(material, scene_tag, material.side, inst)
  local prog = self:program(key)
  if not prog then return end
  -- draw range (renderBufferDirect)
  local dr = geometry.draw_range
  local draw_start, draw_end = dr.start, dr.start + dr.count
  if group then draw_start = math.max(draw_start, group.start); draw_end = math.min(draw_end, group.start + group.count) end
  local total = geometry.index and geometry.index.count or (geometry.attributes.position and geometry.attributes.position.count or 0)
  draw_start = math.max(draw_start, 0); draw_end = math.min(draw_end, total)
  local count = draw_end - draw_start
  if count <= 0 or count == math.huge then return end
  local mesh = gpu_mesh_of(object, geometry)
  -- uniforms, as WebGLRenderer.setProgram sends them: the camera's when the program or the camera
  -- changes, the lights' when the program changes, the material's when the program or the material
  -- changes (a program keeps its uniforms and its textures between draws); the object's always.
  -- A trace sends everything.
  local tr = self.trace and {} or nil
  local set
  self._prog = prog
  if tr then set = function(n, v) if gpu_set(prog, n, v) then tr[n] = v end end
  else set = self._set end
  local refresh_prog = tr ~= nil or prog ~= self.cur_prog
  local refresh_mat = refresh_prog or material.id ~= self.cur_mat_id
  local refresh_cam = refresh_prog or camera ~= self.cur_cam
  self.cur_prog, self.cur_mat_id, self.cur_cam = prog, material.id, camera
  if refresh_cam then
    set('projectionMatrix', camera.projection_matrix.elements)
    set('viewMatrix', camera.matrix_world_inverse.elements)
    _cam_pos:set_from_matrix_position(camera.matrix_world)
    set('cameraPosition', { _cam_pos.x, _cam_pos.y, _cam_pos.z })
    set('isOrthographic', camera.is_orthographic_camera == true)
  end
  if refresh_mat then
    set('toneMappingExposure', 1)
    if refresh_prog and lights and (material.needs_lights or (material.is_shader and material.lights)) then MAT.write_lights(set, lights) end
    _env.height, _env.env_map, _env.environment, _env.transmission = self.height, material.env_map, self.environment, self.current_transmission
    _env.environment_intensity = self.environment_intensity
    MAT.write_uniforms(material, set, _env)
  end
  set('receiveShadow', object.receive_shadow)
  set('modelViewMatrix', object.model_view_matrix.elements)
  set('normalMatrix', object.normal_matrix.elements)
  set('modelMatrix', object.matrix_world.elements)
  -- state and the call
  local front_cw = object.is_mesh and object.matrix_world:determinant() < 0
  local o = draw_state(material, side, front_cw, tr and {} or _o)
  o.first, o.count = draw_start, count
  if object.is_points then o.mode = 'points' else o.mode = 'triangles' end
  o.instances = object.is_instanced_mesh and object.count or nil
  gpu_draw(prog, mesh, o)
  self.info.draws = self.info.draws + 1
  if tr then self.trace[#self.trace + 1] = { op = 'draw', key = key, pass = pass, object = object.name, uniforms = tr, state = o } end
end

-- renderObject: the view matrices, then one draw (a transparent double-sided material: back, then front)
function Renderer:render_object(camera, scene_tag, object, geometry, material, group, lights, pass)
  object.model_view_matrix:multiply_matrices(camera.matrix_world_inverse, object.matrix_world)
  object.normal_matrix:get_normal_matrix(object.model_view_matrix)
  if object.on_before_render then object:on_before_render(self, camera, geometry, material) end
  if material.transparent and material.side == MAT.DoubleSide and not material.force_single_pass then
    self:draw(camera, scene_tag, object, geometry, material, group, MAT.BackSide, lights, pass)
    self:draw(camera, scene_tag, object, geometry, material, group, MAT.FrontSide, lights, pass)
  else
    self:draw(camera, scene_tag, object, geometry, material, group, nil, lights, pass)
  end
end

-- ---------------------------------------------------------------------------- culling
-- Frustum.setFromProjectionMatrix (WebGL): six planes, normalized, into a flat array
local function frustum_of(m, out)
  local e = m.elements
  local me0, me1, me2, me3 = e[1], e[2], e[3], e[4]
  local me4, me5, me6, me7 = e[5], e[6], e[7], e[8]
  local me8, me9, me10, me11 = e[9], e[10], e[11], e[12]
  local me12, me13, me14, me15 = e[13], e[14], e[15], e[16]
  local P = {
    { me3 - me0, me7 - me4, me11 - me8, me15 - me12 }, { me3 + me0, me7 + me4, me11 + me8, me15 + me12 },
    { me3 + me1, me7 + me5, me11 + me9, me15 + me13 }, { me3 - me1, me7 - me5, me11 - me9, me15 - me13 },
    { me3 - me2, me7 - me6, me11 - me10, me15 - me14 }, { me3 + me2, me7 + me6, me11 + me10, me15 + me14 },
  }
  for k = 1, 6 do
    local p = P[k]
    local il = 1/math.sqrt(p[1]*p[1] + p[2]*p[2] + p[3]*p[3])
    local b = (k - 1)*4
    out[b + 1], out[b + 2], out[b + 3], out[b + 4] = p[1]*il, p[2]*il, p[3]*il, p[4]*il
  end
  return out
end
RD.frustum_of = frustum_of
-- InstancedMesh.computeBoundingSphere: the union of the geometry's sphere under every instance
local _im = Matrix4.new()
local function instanced_sphere(o)
  local g = o.geometry
  local gbs = g.bounding_sphere or g:compute_bounding_sphere()
  local cx, cy, cz, r = 0, 0, 0, -1
  local a = o.instance_matrix.array
  for i = 0, o.count - 1 do
    local e = _im.elements
    for k = 1, 16 do e[k] = a[i*16 + k] end
    local c = gbs.center
    local w = 1/(e[4]*c.x + e[8]*c.y + e[12]*c.z + e[16])
    local sx = (e[1]*c.x + e[5]*c.y + e[9]*c.z + e[13])*w
    local sy = (e[2]*c.x + e[6]*c.y + e[10]*c.z + e[14])*w
    local sz = (e[3]*c.x + e[7]*c.y + e[11]*c.z + e[15])*w
    local sr = gbs.radius*_im:get_max_scale_on_axis()
    if not (sr < 0) then
      if r < 0 then cx, cy, cz, r = sx, sy, sz, sr
      elseif cx == sx and cy == sy and cz == sz then r = math.max(r, sr)
      else
        -- Sphere.union: expand by the far points of the other sphere along the line between the centres
        local dx, dy, dz = sx - cx, sy - cy, sz - cz
        local dl = math.sqrt(dx*dx + dy*dy + dz*dz)
        dx, dy, dz = dx/dl*sr, dy/dl*sr, dz/dl*sr
        for _, sg in ipairs({ 1, -1 }) do
          local px, py, pz = sx + dx*sg, sy + dy*sg, sz + dz*sg
          local qx, qy, qz = px - cx, py - cy, pz - cz
          local l2 = qx*qx + qy*qy + qz*qz
          if l2 > r*r then
            local l = math.sqrt(l2)
            local d = (l - r)*0.5
            cx, cy, cz = cx + qx/l*d, cy + qy/l*d, cz + qz/l*d
            r = r + d
          end
        end
      end
    end
  end
  o.bounding_sphere = { center = Vector3.new(cx, cy, cz), radius = r }
  return o.bounding_sphere
end
local function sphere_of(o)
  if o.is_instanced_mesh then return o.bounding_sphere or instanced_sphere(o) end
  local g = o.geometry
  return g.bounding_sphere or g:compute_bounding_sphere()
end
RD.sphere_of = sphere_of
-- Frustum.intersectsObject
local function in_frustum(F, o)
  local bs = sphere_of(o)
  local c, mw = bs.center, o.matrix_world
  local e = mw.elements
  local w = 1/(e[4]*c.x + e[8]*c.y + e[12]*c.z + e[16])
  local x = (e[1]*c.x + e[5]*c.y + e[9]*c.z + e[13])*w
  local y = (e[2]*c.x + e[6]*c.y + e[10]*c.z + e[14])*w
  local z = (e[3]*c.x + e[7]*c.y + e[11]*c.z + e[15])*w
  local r = bs.radius*mw:get_max_scale_on_axis()
  for k = 0, 5 do
    local b = k*4
    if F[b + 1]*x + F[b + 2]*y + F[b + 3]*z + F[b + 4] < -r then return false end
  end
  return true
end

-- ---------------------------------------------------------------------------- render lists
local _frustum = {}
local function project(scene, camera, proj_screen)
  local F = frustum_of(proj_screen, _frustum)
  local opaque, transmissive, transparent = {}, {}, {}
  local counter = 0
  local function push(object, geometry, material, group_order, z, group)
    counter = counter + 1
    local item = { id = object.id, object = object, geometry = geometry, material = material, group_order = group_order,
      render_order = object.render_order, z = z, group = group, seq = counter }
    if material.transmission and material.transmission > 0 then transmissive[#transmissive + 1] = item
    elseif material.transparent then transparent[#transparent + 1] = item
    else opaque[#opaque + 1] = item end
  end
  local e = proj_screen.elements
  local function walk(o, group_order)
    if not o.visible then return end
    if o.is_group then group_order = o.render_order
    elseif (o.is_mesh or o.is_points) and (o.frustum_culled == false or in_frustum(F, o)) then
      local g = o.geometry
      local bs = sphere_of(o)
      -- the centre, world, then clip space; three.js sorts on clip z (no divide)
      local c = bs.center
      local mw = o.matrix_world.elements
      local x = mw[1]*c.x + mw[5]*c.y + mw[9]*c.z + mw[13]
      local y = mw[2]*c.x + mw[6]*c.y + mw[10]*c.z + mw[14]
      local z = mw[3]*c.x + mw[7]*c.y + mw[11]*c.z + mw[15]
      local w = mw[4]*c.x + mw[8]*c.y + mw[12]*c.z + mw[16]
      local cz = e[3]*x + e[7]*y + e[11]*z + e[15]*w
      local mat = o.material
      if type(mat) == 'table' and mat[1] then
        for _, gr in ipairs(g.groups) do
          local gm = mat[gr.material_index + 1]
          if gm and gm.visible then push(o, g, gm, group_order, cz, gr) end
        end
      elseif mat and mat.visible then push(o, g, mat, group_order, cz, nil) end
    end
    for _, c in ipairs(o.children) do walk(c, group_order) end
  end
  walk(scene, 0)
  local function painter(a, b)
    if a.group_order ~= b.group_order then return a.group_order < b.group_order end
    if a.render_order ~= b.render_order then return a.render_order < b.render_order end
    if a.material.id ~= b.material.id then return a.material.id < b.material.id end
    if a.z ~= b.z then return a.z < b.z end
    if a.id ~= b.id then return a.id < b.id end
    return a.seq < b.seq
  end
  local function reverse_painter(a, b)
    if a.group_order ~= b.group_order then return a.group_order < b.group_order end
    if a.render_order ~= b.render_order then return a.render_order < b.render_order end
    if a.z ~= b.z then return a.z > b.z end
    if a.id ~= b.id then return a.id < b.id end
    return a.seq < b.seq
  end
  table.sort(opaque, painter); table.sort(transmissive, reverse_painter); table.sort(transparent, reverse_painter)
  return opaque, transmissive, transparent
end

-- ---------------------------------------------------------------------------- shadows
local _psm_shadow, _sfrustum = Matrix4.new(), {}
local SHADOW_SIDE = { [MAT.FrontSide] = MAT.BackSide, [MAT.BackSide] = MAT.FrontSide, [MAT.DoubleSide] = MAT.DoubleSide }
function Renderer:shadow_pass(scene, camera, casters)
  if not self.shadow_map_enabled or #casters == 0 then return end
  local prev = self.target
  local prev_c, prev_a = self.clear_color:clone(), self.clear_alpha
  for _, light in ipairs(casters) do
    local sh = light.shadow
    if not sh.map then
      sh.map = RenderTarget.new(sh.map_size.x, sh.map_size.y, { type = 'byte', min_filter = 'nearest', mag_filter = 'nearest' })
      sh.camera:update_projection_matrix()
    end
    self:set_render_target(sh.map)
    self.clear_color:set_rgb(1, 1, 1); self.clear_alpha = 1
    self:clear(true, true)
    gpu_viewport(0, 0, sh.map_size.x, sh.map_size.y)
    T.shadow_update_matrices(light)
    local scam = sh.camera
    local dm = self.depth_material
    local SF = frustum_of(_psm_shadow:multiply_matrices(scam.projection_matrix, scam.matrix_world_inverse), _sfrustum)
    local function walk(o)
      if not o.visible then return end
      if (o.is_mesh or o.is_points) and o.cast_shadow and (o.frustum_culled == false or in_frustum(SF, o)) then
        local mat = o.material
        if mat and mat.visible then
          o.model_view_matrix:multiply_matrices(scam.matrix_world_inverse, o.matrix_world)
          local custom = o.custom_depth_material
          local m = custom or dm
          local side = mat.shadow_side or SHADOW_SIDE[mat.side]
          m.side = side
          m.alpha_map, m.alpha_test, m.map = mat.alpha_map, mat.alpha_test, mat.map
          -- one depth program per instancing mode (tools/port_programs.py: the variants draw the same depth)
          local key = custom and (custom.name .. '|depth|' .. (o.is_instanced_mesh and 'i' or '-'))
            or ('depth|' .. (o.is_instanced_mesh and 'i' or '-'))
          o.normal_matrix:get_normal_matrix(o.model_view_matrix)
          self:draw(scam, 'shadow', o, o.geometry, m, nil, side, nil, 'shadow', key)
        end
      end
      for _, c in ipairs(o.children) do walk(c) end
    end
    walk(scene)
  end
  self.clear_color:copy(prev_c); self.clear_alpha = prev_a
  self:set_render_target(prev)
end

-- ---------------------------------------------------------------------------- render
local _psm = Matrix4.new()
function Renderer:render(scene, camera)
  self.cur_mat_id, self.cur_cam = -1, nil
  self.environment, self.environment_intensity = scene.environment, scene.environment_intensity or 1
  scene:update_matrix_world()
  if camera.parent == nil then camera:update_matrix_world() end
  _psm:multiply_matrices(camera.projection_matrix, camera.matrix_world_inverse)
  local lights, casters = collect(scene)
  local opaque, transmissive, transparent = project(scene, camera, _psm)
  self:shadow_pass(scene, camera, casters)
  local L = light_state(lights, camera)
  local tag = scene.program_scene or 'world'
  local target = self.target
  self.current_transmission = nil
  if #transmissive > 0 then self:transmission_pass(scene, camera, tag, L, opaque, transmissive) end
  -- background
  self:set_render_target(target)
  local bg = scene.background
  if bg then
    local cc, ca = self.clear_color:clone(), self.clear_alpha
    self.clear_color:copy(bg); self.clear_alpha = 1
    self:clear(true, true)
    self.clear_color:copy(cc); self.clear_alpha = ca
  elseif self.auto_clear then
    self:clear(true, true)
  end
  if target then gpu_viewport(0, 0, target.width, target.height) end
  for _, it in ipairs(opaque) do self:render_object(camera, tag, it.object, it.geometry, it.material, it.group, L, 'opaque') end
  for _, it in ipairs(transmissive) do self:render_object(camera, tag, it.object, it.geometry, it.material, it.group, L, 'transmissive') end
  for _, it in ipairs(transparent) do self:render_object(camera, tag, it.object, it.geometry, it.material, it.group, L, 'transparent') end
  self:finish_target(target)
end

function Renderer:transmission_pass(scene, camera, tag, L, opaque, transmissive)
  local vw, vh = self.target and self.target.width or 640, self.target and self.target.height or 360
  local rt = self.transmission_targets[camera]
  if not rt then
    rt = RenderTarget.new(vw, vh, { type = 'half', min_filter = 'linear_mipmap_linear', mag_filter = 'linear', samples = 4 })
    self.transmission_targets[camera] = rt
  end
  rt:set_size(vw, vh)
  local prev = self.target
  self:set_render_target(rt)
  local cc, ca = self.clear_color:clone(), self.clear_alpha
  if ca < 1 then self.clear_color:set_rgb(1, 1, 1); self.clear_alpha = 0.5 end
  self:clear(true, true)
  local bg = scene.background
  if bg then
    self.clear_color:copy(bg); self.clear_alpha = 1
    self:clear(true, true)
  end
  self.clear_color:copy(cc); self.clear_alpha = ca
  gpu_viewport(0, 0, vw, vh)
  for _, it in ipairs(opaque) do self:render_object(camera, tag, it.object, it.geometry, it.material, it.group, L, 'transmission') end
  self:finish_target(rt)
  local again = false
  for _, it in ipairs(transmissive) do
    if it.material.side == MAT.DoubleSide then
      it.object.model_view_matrix:multiply_matrices(camera.matrix_world_inverse, it.object.matrix_world)
      it.object.normal_matrix:get_normal_matrix(it.object.model_view_matrix)
      self:draw(camera, tag, it.object, it.geometry, it.material, it.group, MAT.BackSide, L, 'transmission')
      again = true
    end
  end
  if again then self:finish_target(rt) end
  self.current_transmission = { texture = rt.texture.gpu, w = rt.width, h = rt.height }
  self:set_render_target(prev)
end

return RD
