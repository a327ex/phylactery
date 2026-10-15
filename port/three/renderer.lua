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
local PROF = require('port.prof')       -- (2026-10-15: the benchmark's sections)
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
    transmission_targets = {}, transmission_copies = {},
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
-- (2026-10-15, session 17) a program compiled without waiting (the engine's gpu_program_async: on the web in the
-- background, KHR_parallel_shader_compile); program() hands it out as any other, and its first use waits for it if
-- it is not done (the engine). program_ready(key) says whether it is done.
function Renderer:program_async(key)
  if self.compiled[key] then return self.compiled[key] end
  local src = self.library[key]
  if not src then return nil end
  local p = gpu_program_async(src.vs, src.fs, key)
  self.compiled[key] = p
  self.info.programs = self.info.programs + 1
  return p
end
function Renderer:program_ready(key)
  local p = self.compiled[key]
  return p ~= nil and gpu_program_ready(p)
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
-- (round 64: the same order the stable sort gave, shadow casters first, the rest, each in scene order, and the same
-- numbers, into tables kept between renders instead of new ones each time)
local _sorted, _d3, _p3 = {}, Vector3.new(), Vector3.new()
local function entry(list, n) local t = list[n]; if not t then t = {}; list[n] = t end; return t end
local function arr(t, k, n) local a = t[k]; if not a then a = {}; for i = 1, n do a[i] = 0 end; t[k] = a end; return a end
local function light_state(lights, camera, L)
  local ns = 0
  for _, l in ipairs(lights) do if l.cast_shadow then ns = ns + 1; _sorted[ns] = l end end
  for _, l in ipairs(lights) do if not l.cast_shadow then ns = ns + 1; _sorted[ns] = l end end
  for i = #_sorted, ns + 1, -1 do _sorted[i] = nil end
  L = L or { ambient = { 0, 0, 0 }, probe = {}, directional = {}, directional_shadow = {}, point = {} }
  L.ambient[1], L.ambient[2], L.ambient[3] = 0, 0, 0
  for i = 1, 27 do L.probe[i] = 0 end
  local nd, nds, np = 0, 0, 0
  local view = camera.matrix_world_inverse
  for i = 1, ns do
    local l = _sorted[i]
    if l.is_ambient_light then
      L.ambient[1] = L.ambient[1] + l.color.r*l.intensity
      L.ambient[2] = L.ambient[2] + l.color.g*l.intensity
      L.ambient[3] = L.ambient[3] + l.color.b*l.intensity
    elseif l.is_directional_light then
      local d = _d3:set_from_matrix_position(l.matrix_world)
      _v3:set_from_matrix_position(l.target.matrix_world)
      d:sub(_v3):transform_direction(view)
      nd = nd + 1
      local t = entry(L.directional, nd)
      local dir, c = arr(t, 'direction', 3), arr(t, 'color', 3)
      dir[1], dir[2], dir[3] = d.x, d.y, d.z
      c[1], c[2], c[3] = l.color.r*l.intensity, l.color.g*l.intensity, l.color.b*l.intensity
      if l.cast_shadow then
        local s = l.shadow
        nds = nds + 1
        local t2 = entry(L.directional_shadow, nds)
        t2.intensity, t2.bias, t2.normal_bias, t2.radius = s.intensity, s.bias, s.normal_bias, s.radius
        local ms = arr(t2, 'map_size', 2); ms[1], ms[2] = s.map_size.x, s.map_size.y
        t2.map = s.map and s.map.texture.gpu or nil
        t2.matrix = s.matrix.elements
      end
    elseif l.is_point_light then
      local p = _p3:set_from_matrix_position(l.matrix_world):apply_matrix4(view)
      np = np + 1
      local t = entry(L.point, np)
      local pos, c = arr(t, 'position', 3), arr(t, 'color', 3)
      pos[1], pos[2], pos[3] = p.x, p.y, p.z
      c[1], c[2], c[3] = l.color.r*l.intensity, l.color.g*l.intensity, l.color.b*l.intensity
      t.distance, t.decay = l.distance, l.decay
    end
  end
  for i = #L.directional, nd + 1, -1 do L.directional[i] = nil end
  for i = #L.directional_shadow, nds + 1, -1 do L.directional_shadow[i] = nil end
  for i = #L.point, np + 1, -1 do L.point[i] = nil end
  return L
end

-- ---------------------------------------------------------------------------- geometry upload
local function up(m, sizes, name, a, divisor)
  local n = a.array and #a.array or #a.blob
  if sizes[name] ~= n then
    gpu_mesh_attr(m, name, a.item_size, a.array or a.blob, divisor, a.dynamic)
    sizes[name] = n; a.needs_update = false
  elseif a.needs_update then
    local t0 = PROF.fine and perf_time()
    gpu_mesh_update(m, name, a.array)
    a.needs_update = false
    if t0 then
      local k = '~' .. tostring(PROF.cur_obj) .. '.' .. name
      PROF.t[k] = (PROF.t[k] or 0) + (perf_time() - t0)
      PROF.t['#floats_up'] = (PROF.t['#floats_up'] or 0) + n/1000
    end
  end
end
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
  for _, name in ipairs(geometry.attribute_order) do up(m, sizes, name, geometry.attributes[name], 0) end
  if object.is_instanced_mesh then
    up(m, sizes, 'instanceMatrix', object.instance_matrix, 1)
    if object.instance_color then up(m, sizes, 'instanceColor', object.instance_color, 1) end
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

-- (2026-10-15, session 17) every mesh of a scene, drawn or not yet (out of frame, hidden), for uploading ahead: the
-- site's intro does it a few MB a frame, so no first draw waits on its buffers (the first frames after the intro and
-- the lich coming into frame were 90-145 ms on the web). upload(o) is what a draw does first; -> the bytes it sent.
function Renderer:upload_list(scene)
  local list = {}
  scene:traverse(function(o)
    local g = o.geometry
    if (o.is_mesh or o.is_points) and g and g.attribute_order and not (g.gpu_mesh or o.gpu_mesh) then list[#list + 1] = o end
  end)
  return list
end
function Renderer:upload(o)
  local g = o.geometry
  local bytes = 0
  for _, name in ipairs(g.attribute_order) do local a = g.attributes[name]; bytes = bytes + (a.array and #a.array*4 or #a.blob) end
  gpu_mesh_of(o, g)
  return bytes
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
  if material.polygon_offset then
    local po = material._po
    if not po then po = {}; material._po = po end
    po[1], po[2] = material.polygon_offset_factor, material.polygon_offset_units
    o.polygon_offset = po
  else o.polygon_offset = nil end
  return o
end

-- ---------------------------------------------------------------------------- one draw
local _cam_pos, _cam_arr = Vector3.new(), { 0, 0, 0 }
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
  local lap = PROF.fine and perf_time()
  local key = key_override or key_of(material, scene_tag, material.side, inst)
  local prog = self:program(key)
  lap = PROF.lap('d.prog', lap)
  if not prog then return end
  -- draw range (renderBufferDirect)
  local dr = geometry.draw_range
  local draw_start, draw_end = dr.start, dr.start + dr.count
  if group then draw_start = math.max(draw_start, group.start); draw_end = math.min(draw_end, group.start + group.count) end
  local total = geometry.index and geometry.index.count or (geometry.attributes.position and geometry.attributes.position.count or 0)
  draw_start = math.max(draw_start, 0); draw_end = math.min(draw_end, total)
  local count = draw_end - draw_start
  if count <= 0 or count == math.huge then return end
  if PROF.fine then PROF.cur_obj = object.name ~= '' and object.name or (material.name or '?') end
  local mesh = gpu_mesh_of(object, geometry)
  lap = PROF.lap('d.mesh', lap)
  -- uniforms, as WebGLRenderer.setProgram sends them: the camera's when the program or the camera
  -- changes, the lights' when the program changes, the material's when the program or the material
  -- changes (a program keeps its uniforms and its textures between draws); the object's always.
  -- A trace sends everything.
  local tr = self.trace and {} or nil
  local set
  self._prog = prog
  if tr then set = function(n, v)
      if gpu_set(prog, n, v) then
        if type(v) == 'table' then local c = {}; for k, x in pairs(v) do c[k] = x end; v = c end
        tr[n] = v
      end
    end
  else set = self._set end
  local refresh_prog = tr ~= nil or prog ~= self.cur_prog
  local refresh_mat = refresh_prog or material.id ~= self.cur_mat_id
  local refresh_cam = refresh_prog or camera ~= self.cur_cam
  self.cur_prog, self.cur_mat_id, self.cur_cam = prog, material.id, camera
  if refresh_cam then
    set('projectionMatrix', camera.projection_matrix.elements)
    set('viewMatrix', camera.matrix_world_inverse.elements)
    _cam_pos:set_from_matrix_position(camera.matrix_world)
    _cam_arr[1], _cam_arr[2], _cam_arr[3] = _cam_pos.x, _cam_pos.y, _cam_pos.z
    set('cameraPosition', _cam_arr)
    set('isOrthographic', camera.is_orthographic_camera == true)
  end
  if refresh_mat then
    set('toneMappingExposure', 1)
    if refresh_prog and lights and (material.needs_lights or (material.is_shader and material.lights)) then MAT.write_lights(set, lights) end
    _env.height, _env.env_map, _env.environment, _env.transmission = self.height, material.env_map, self.environment, self.current_transmission
    _env.environment_intensity = self.environment_intensity
    MAT.write_uniforms(material, set, _env)
  end
  lap = PROF.lap('d.uni_cam_mat', lap)
  set('receiveShadow', object.receive_shadow)
  set('modelViewMatrix', object.model_view_matrix.elements)
  set('normalMatrix', object.normal_matrix.elements)
  set('modelMatrix', object.matrix_world.elements)
  lap = PROF.lap('d.uni_obj', lap)
  -- state and the call
  local front_cw = object.is_mesh and object.matrix_world:determinant() < 0
  local o = draw_state(material, side, front_cw, tr and {} or _o)
  o.first, o.count = draw_start, count
  if object.is_points then o.mode = 'points' else o.mode = 'triangles' end
  o.instances = object.is_instanced_mesh and object.count or nil
  lap = PROF.lap('d.state', lap)
  gpu_draw(prog, mesh, o)
  lap = PROF.lap('d.gpu_draw', lap)
  if PROF.fine then PROF.t['#draws'] = (PROF.t['#draws'] or 0) + 0.001; if refresh_mat then PROF.t['#mat_refresh'] = (PROF.t['#mat_refresh'] or 0) + 0.001 end end
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
  local function plane(k, a, b, c, d)
    local il = 1/math.sqrt(a*a + b*b + c*c)
    local o = (k - 1)*4
    out[o + 1], out[o + 2], out[o + 3], out[o + 4] = a*il, b*il, c*il, d*il
  end
  plane(1, me3 - me0, me7 - me4, me11 - me8, me15 - me12); plane(2, me3 + me0, me7 + me4, me11 + me8, me15 + me12)
  plane(3, me3 + me1, me7 + me5, me11 + me9, me15 + me13); plane(4, me3 - me1, me7 - me5, me11 - me9, me15 - me13)
  plane(5, me3 - me2, me7 - me6, me11 - me10, me15 - me14); plane(6, me3 + me2, me7 + me6, me11 + me10, me15 + me14)
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
        for sgi = 1, 2 do
          local sg = sgi == 1 and 1 or -1
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
  local bs = o._bs_buf
  if not bs then bs = { center = Vector3.new() }; o._bs_buf = bs end
  bs.center:set(cx, cy, cz); bs.radius = r
  o.bounding_sphere = bs
  return bs
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
-- (round 64: the items are kept between renders and the walk and the orders are made once: they were new tables and
-- closures every render; the same items in the same order)
local _items, _counter, _F, _e = {}, 0, nil, nil
local _opaque, _transmissive, _transparent = {}, {}, {}
local function push(object, geometry, material, group_order, z, group)
  _counter = _counter + 1
  local item = _items[_counter]
  if not item then item = {}; _items[_counter] = item end
  item.id, item.object, item.geometry, item.material, item.group_order = object.id, object, geometry, material, group_order
  item.render_order, item.z, item.group, item.seq = object.render_order, z, group, _counter
  if material.transmission and material.transmission > 0 then _transmissive[#_transmissive + 1] = item
  elseif material.transparent then _transparent[#_transparent + 1] = item
  else _opaque[#_opaque + 1] = item end
end
local walk
walk = function(o, group_order)
  local F, e = _F, _e
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
local function clear(t) for i = #t, 1, -1 do t[i] = nil end end
local function project(scene, camera, proj_screen)
  _F = frustum_of(proj_screen, _frustum)
  _e = proj_screen.elements
  _counter = 0
  clear(_opaque); clear(_transmissive); clear(_transparent)
  walk(scene, 0)
  -- (an item left over from a bigger render keeps nothing alive)
  for i = _counter + 1, #_items do local it = _items[i]; it.object, it.geometry, it.material, it.group = nil, nil, nil, nil end
  table.sort(_opaque, painter); table.sort(_transmissive, reverse_painter); table.sort(_transparent, reverse_painter)
  return _opaque, _transmissive, _transparent
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
  local lap = PROF.on and perf_time()       -- (2026-10-15: port/prof.lua, the benchmark's sections)
  self.cur_mat_id, self.cur_cam = -1, nil
  self.environment, self.environment_intensity = scene.environment, scene.environment_intensity or 1
  scene:update_matrix_world()
  if camera.parent == nil then camera:update_matrix_world() end
  lap = PROF.lap('r3.matrices', lap)
  _psm:multiply_matrices(camera.projection_matrix, camera.matrix_world_inverse)
  local lights, casters = collect(scene)
  local opaque, transmissive, transparent = project(scene, camera, _psm)
  lap = PROF.lap('r3.project', lap)
  self:shadow_pass(scene, camera, casters)
  lap = PROF.lap('r3.shadow', lap)
  self._L = light_state(lights, camera, self._L)
  local L = self._L
  local tag = scene.program_scene or 'world'
  local target = self.target
  self.current_transmission = nil
  -- (2026-10-15, the web's performance) `transmission_copy` (the game's flow sets it): what the glass sees through it
  -- is the opaque world as this target has it once the opaque objects are drawn, copied (gpu_blit) instead of drawn a
  -- second time into a target of its own (three.js's transmission pass: every opaque object again, CPU and GPU, each
  -- frame a lens is out, and the lens now stays out). The pass stays for a double-sided glass (whose back faces it
  -- also draws) and with no target to copy from.
  local copy_tr = false
  if #transmissive > 0 then
    copy_tr = self.transmission_copy and target ~= nil and not target.msaa
    if copy_tr then for _, it in ipairs(transmissive) do if it.material.side == MAT.DoubleSide then copy_tr = false; break end end end
    if not copy_tr then self:transmission_pass(scene, camera, tag, L, opaque, transmissive) end
  end
  lap = PROF.lap('r3.transmission', lap)
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
  if copy_tr then
    local tl = PROF.on and perf_time()
    local w, h = target.width, target.height
    local rt = self.transmission_copies[camera]
    if not rt then
      rt = RenderTarget.new(w, h, { type = target.opts.type, format = target.opts.format, min_filter = 'linear_mipmap_linear', mag_filter = 'linear', depth = false })
      self.transmission_copies[camera] = rt
    end
    rt:set_size(w, h)
    gpu_blit(target.gpu, rt.gpu, 'nearest')
    self:finish_target(rt)
    self.current_transmission = { texture = rt.texture.gpu, w = rt.width, h = rt.height }
    self:set_render_target(target)
    gpu_viewport(0, 0, w, h)
    self.cur_prog, self.cur_mat_id, self.cur_cam = nil, -1, nil
    if tl then PROF.add('r3.transmission', tl) end
  end
  for _, it in ipairs(transmissive) do self:render_object(camera, tag, it.object, it.geometry, it.material, it.group, L, 'transmissive') end
  for _, it in ipairs(transparent) do self:render_object(camera, tag, it.object, it.geometry, it.material, it.group, L, 'transparent') end
  lap = PROF.lap('r3.draw', lap)
  self:finish_target(target)
  PROF.lap('r3.finish', lap)
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
