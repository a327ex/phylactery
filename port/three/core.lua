--[[
  three/core.lua -- the port to Anchor: three.js r170's scene graph, the subset the game uses:
  Object3D (and Group, Scene, Mesh, InstancedMesh, Points), cameras, lights (+ the directional
  light's shadow camera), BufferAttribute / BufferGeometry (drawn through the engine's gpu layer;
  an attribute re-uploads when its needs_update is set), and Texture (a gpu texture + how three.js
  would have sampled it). Behaviour follows three.js exactly where it shows in a frame: matrix
  updates, lookAt, projection, the stale-once-computed bounding sphere.
]]
local TM = require('port.three.math')
local Vector3, Vector2, Quaternion, Euler, Matrix3, Matrix4, Color = TM.Vector3, TM.Vector2, TM.Quaternion, TM.Euler, TM.Matrix3, TM.Matrix4, TM.Color

local T = {}
local next_id = 0
local function new_id() next_id = next_id + 1; return next_id end

-- ---------------------------------------------------------------------------- Object3D
local Object3D = {}; Object3D.__index = Object3D
T.Object3D = Object3D
T.DEFAULT_UP = Vector3.new(0, 1, 0)

function Object3D.init(o)
  o.id = new_id()
  o.name = ''
  o.type = o.type or 'Object3D'
  o.parent = nil
  o.children = {}
  o.up = T.DEFAULT_UP:clone()
  o.position = Vector3.new()
  o.rotation = Euler.new()
  o.quaternion = Quaternion.new()
  o.scale = Vector3.new(1, 1, 1)
  local rot, quat = o.rotation, o.quaternion
  rot:on_change(function() quat:set_from_euler(rot, false) end)
  quat:on_change(function() rot:set_from_quaternion(quat, nil, false) end)
  o.matrix = Matrix4.new()
  o.matrix_world = Matrix4.new()
  o.model_view_matrix = Matrix4.new()
  o.normal_matrix = Matrix3.new()
  o.matrix_auto_update = true
  o.matrix_world_auto_update = true
  o.matrix_world_needs_update = false
  o.visible = true
  o.cast_shadow = false
  o.receive_shadow = false
  o.frustum_culled = true
  o.render_order = 0
  o.user_data = {}
  return o
end
function Object3D.new() return Object3D.init(setmetatable({}, Object3D)) end

function Object3D:add(...)
  for _, obj in ipairs({ ... }) do
    if obj ~= self then
      if obj.parent then obj.parent:remove(obj) end
      obj.parent = self
      obj._mc = nil
      self.children[#self.children + 1] = obj
    end
  end
  return self
end
function Object3D:remove(...)
  for _, obj in ipairs({ ... }) do
    for i, c in ipairs(self.children) do
      if c == obj then table.remove(self.children, i); obj.parent = nil; break end
    end
  end
  return self
end
function Object3D:remove_from_parent() if self.parent then self.parent:remove(self) end; return self end
function Object3D:clear() for _, c in ipairs(self.children) do c.parent = nil end; self.children = {}; return self end
function Object3D:traverse(fn) fn(self); for _, c in ipairs(self.children) do c:traverse(fn) end end
function Object3D:traverse_visible(fn) if not self.visible then return end; fn(self); for _, c in ipairs(self.children) do c:traverse_visible(fn) end end

function Object3D:update_matrix()
  local p, q, sc = self.position, self.quaternion, self.scale
  self.matrix:compose(p, q, sc)
  local c = self._mc
  if not c then c = {}; self._mc = c end
  c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10] = p.x, p.y, p.z, q._x, q._y, q._z, q._w, sc.x, sc.y, sc.z
  self.matrix_world_needs_update = true
end
-- (as three.js, but an object whose position, rotation and scale are what they were at its last
-- compose keeps its matrix, and its world matrix unless its parent's changed: the same values,
-- without recomputing them for every still object every frame)
function Object3D:update_matrix_world(force)
  if self.matrix_auto_update then
    local p, q, sc, c = self.position, self.quaternion, self.scale, self._mc
    if not c or c[1] ~= p.x or c[2] ~= p.y or c[3] ~= p.z or c[4] ~= q._x or c[5] ~= q._y or c[6] ~= q._z or c[7] ~= q._w
      or c[8] ~= sc.x or c[9] ~= sc.y or c[10] ~= sc.z then
      self:update_matrix()
    end
  end
  if self.matrix_world_needs_update or force then
    if self.matrix_world_auto_update then
      if self.parent == nil then self.matrix_world:copy(self.matrix)
      else self.matrix_world:multiply_matrices(self.parent.matrix_world, self.matrix) end
      self._wv = (self._wv or 0) + 1      -- (2026-10-16: its world matrix was worked out again: the renderer's caches)
    end
    self.matrix_world_needs_update = false
    force = true
  end
  local ch = self.children
  for i = 1, #ch do ch[i]:update_matrix_world(force) end
  if self.on_after_matrix_world then self:on_after_matrix_world() end
end
-- (2026-10-16, Phylactery 19) as three.js, but the local matrix is composed again only when its position, rotation or
-- scale moved since the last compose (update_matrix_world's rule): the game's world-position lookups walk up to the
-- scene, and composing every ancestor flagged the scene itself, so the next render recomputed the world matrix of
-- every object in it (~250 a frame) from the same numbers to the same matrices
function Object3D:update_world_matrix(update_parents, update_children)
  local parent = self.parent
  if update_parents and parent then parent:update_world_matrix(true, false) end
  if self.matrix_auto_update then
    local p, q, sc, c = self.position, self.quaternion, self.scale, self._mc
    if not c or c[1] ~= p.x or c[2] ~= p.y or c[3] ~= p.z or c[4] ~= q._x or c[5] ~= q._y or c[6] ~= q._z or c[7] ~= q._w
      or c[8] ~= sc.x or c[9] ~= sc.y or c[10] ~= sc.z then
      self:update_matrix()
    end
  end
  if self.matrix_world_auto_update then
    if parent == nil then self.matrix_world:copy(self.matrix)
    else self.matrix_world:multiply_matrices(parent.matrix_world, self.matrix) end
    self._wv = (self._wv or 0) + 1
  end
  if update_children then
    for _, c in ipairs(self.children) do c:update_world_matrix(false, true) end
  end
  if self.on_after_matrix_world then self:on_after_matrix_world() end
end

local _v, _q, _m, _s = Vector3.new(), Quaternion.new(), Matrix4.new(), Vector3.new()
function Object3D:get_world_position(target)
  self:update_world_matrix(true, false)
  return target:set_from_matrix_position(self.matrix_world)
end
function Object3D:get_world_quaternion(target)
  self:update_world_matrix(true, false)
  self.matrix_world:decompose(_v, target, _s)
  return target
end
function Object3D:get_world_scale(target)
  self:update_world_matrix(true, false)
  self.matrix_world:decompose(_v, _q, target)
  return target
end
function Object3D:get_world_direction(target)
  self:update_world_matrix(true, false)
  local e = self.matrix_world.elements
  return target:set(e[9], e[10], e[11]):normalize()
end
local _target, _position, _m1, _q1 = Vector3.new(), Vector3.new(), Matrix4.new(), Quaternion.new()
function Object3D:look_at(x, y, z)
  if type(x) == 'table' then _target:copy(x) else _target:set(x, y, z) end
  local parent = self.parent
  self:update_world_matrix(true, false)
  _position:set_from_matrix_position(self.matrix_world)
  if self.is_camera or self.is_light then _m1:look_at(_position, _target, self.up)
  else _m1:look_at(_target, _position, self.up) end
  self.quaternion:set_from_rotation_matrix(_m1)
  if parent then
    _m1:extract_rotation(parent.matrix_world)
    _q1:set_from_rotation_matrix(_m1)
    self.quaternion:premultiply(_q1:invert())
  end
end
function Object3D:local_to_world(v) self:update_world_matrix(true, false); return v:apply_matrix4(self.matrix_world) end
function Object3D:world_to_local(v) self:update_world_matrix(true, false); return v:apply_matrix4(_m:copy(self.matrix_world):invert()) end
function Object3D:rotate_on_axis(axis, angle) _q1:set_from_axis_angle(axis, angle); self.quaternion:multiply(_q1); return self end
function Object3D:rotate_x(a) return self:rotate_on_axis(Vector3.new(1, 0, 0), a) end
function Object3D:rotate_y(a) return self:rotate_on_axis(Vector3.new(0, 1, 0), a) end
function Object3D:rotate_z(a) return self:rotate_on_axis(Vector3.new(0, 0, 1), a) end

-- a subclass sharing Object3D's methods
local function subclass(name, base)
  local C = setmetatable({}, { __index = base })
  C.__index = C
  C.type_name = name
  return C
end
T.subclass = subclass

local Group = subclass('Group', Object3D); T.Group = Group
function Group.new() local o = Object3D.init(setmetatable({ type = 'Group', is_group = true }, Group)); return o end

local Scene = subclass('Scene', Object3D); T.Scene = Scene
function Scene.new() local o = Object3D.init(setmetatable({ type = 'Scene', is_scene = true }, Scene)); o.background = nil; return o end

local Mesh = subclass('Mesh', Object3D); T.Mesh = Mesh
function Mesh.new(geometry, material)
  local o = Object3D.init(setmetatable({ type = 'Mesh', is_mesh = true }, Mesh))
  o.geometry = geometry or T.BufferGeometry.new(); o.material = material
  return o
end

local InstancedMesh = subclass('InstancedMesh', Mesh); T.InstancedMesh = InstancedMesh
function InstancedMesh.new(geometry, material, count)
  local o = Mesh.new(geometry, material)
  setmetatable(o, InstancedMesh)
  o.type = 'InstancedMesh'; o.is_instanced_mesh = true
  local a = {}
  for i = 0, count - 1 do
    local b = i*16
    a[b + 1], a[b + 6], a[b + 11], a[b + 16] = 1, 1, 1, 1
    a[b + 2], a[b + 3], a[b + 4], a[b + 5], a[b + 7], a[b + 8], a[b + 9], a[b + 10], a[b + 12], a[b + 13], a[b + 14], a[b + 15] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  end
  o.instance_matrix = T.BufferAttribute.new(a, 16); o.instance_matrix.instanced = true
  o.instance_color = nil
  o.count = count
  o.max_count = count
  return o
end
function InstancedMesh:set_matrix_at(i, m)
  local a, e, b = self.instance_matrix.array, m.elements, i*16
  for k = 1, 16 do a[b + k] = e[k] end
end
function InstancedMesh:get_matrix_at(i, m)
  local a, e, b = self.instance_matrix.array, m.elements, i*16
  for k = 1, 16 do e[k] = a[b + k] end
  return m
end
function InstancedMesh:set_color_at(i, c)
  if not self.instance_color then
    local a = {}
    for k = 1, self.max_count*3 do a[k] = 1 end
    self.instance_color = T.BufferAttribute.new(a, 3); self.instance_color.instanced = true
  end
  local a, b = self.instance_color.array, i*3
  a[b + 1], a[b + 2], a[b + 3] = c.r, c.g, c.b
end

local Points = subclass('Points', Object3D); T.Points = Points
function Points.new(geometry, material)
  local o = Object3D.init(setmetatable({ type = 'Points', is_points = true }, Points))
  o.geometry = geometry or T.BufferGeometry.new(); o.material = material
  return o
end

-- ---------------------------------------------------------------------------- cameras
local Camera = subclass('Camera', Object3D); T.Camera = Camera
function Camera.init(o)
  Object3D.init(o)
  o.is_camera = true
  o.matrix_world_inverse = Matrix4.new()
  o.projection_matrix = Matrix4.new()
  o.projection_matrix_inverse = Matrix4.new()
  return o
end
function Camera:update_matrix_world(force)
  Object3D.update_matrix_world(self, force)
  self.matrix_world_inverse:copy(self.matrix_world):invert()
end
function Camera:update_world_matrix(up, down)
  Object3D.update_world_matrix(self, up, down)
  self.matrix_world_inverse:copy(self.matrix_world):invert()
end
function Camera:get_world_direction(target)
  return Object3D.get_world_direction(self, target):negate()
end

local PerspectiveCamera = subclass('PerspectiveCamera', Camera); T.PerspectiveCamera = PerspectiveCamera
function PerspectiveCamera.new(fov, aspect, near, far)
  local o = Camera.init(setmetatable({ type = 'PerspectiveCamera', is_perspective_camera = true }, PerspectiveCamera))
  o.fov, o.aspect, o.near, o.far, o.zoom = fov or 50, aspect or 1, near or 0.1, far or 2000, 1
  o:update_projection_matrix()
  return o
end
function PerspectiveCamera:update_projection_matrix()
  local near = self.near
  local top = near*math.tan(TM.deg2rad*0.5*self.fov)/self.zoom
  local height = 2*top
  local width = self.aspect*height
  local left = -0.5*width
  self.projection_matrix:make_perspective(left, left + width, top, top - height, near, self.far)
  self.projection_matrix_inverse:copy(self.projection_matrix):invert()
end

local OrthographicCamera = subclass('OrthographicCamera', Camera); T.OrthographicCamera = OrthographicCamera
function OrthographicCamera.new(left, right, top, bottom, near, far)
  local o = Camera.init(setmetatable({ type = 'OrthographicCamera', is_orthographic_camera = true }, OrthographicCamera))
  o.left, o.right, o.top, o.bottom = left or -1, right or 1, top or 1, bottom or -1
  o.near, o.far, o.zoom = near or 0.1, far or 2000, 1
  o:update_projection_matrix()
  return o
end
function OrthographicCamera:update_projection_matrix()
  local dx = (self.right - self.left)/(2*self.zoom)
  local dy = (self.top - self.bottom)/(2*self.zoom)
  local cx = (self.right + self.left)/2
  local cy = (self.top + self.bottom)/2
  self.projection_matrix:make_orthographic(cx - dx, cx + dx, cy + dy, cy - dy, self.near, self.far)
  self.projection_matrix_inverse:copy(self.projection_matrix):invert()
end

-- ---------------------------------------------------------------------------- lights
local Light = subclass('Light', Object3D); T.Light = Light
function Light.init(o, color, intensity)
  Object3D.init(o)
  o.is_light = true
  o.color = Color.new(color == nil and 0xffffff or color)
  o.intensity = intensity == nil and 1 or intensity
  return o
end

local DirectionalLight = subclass('DirectionalLight', Light); T.DirectionalLight = DirectionalLight
function DirectionalLight.new(color, intensity)
  local o = Light.init(setmetatable({ type = 'DirectionalLight', is_directional_light = true }, DirectionalLight), color, intensity)
  o.position:copy(T.DEFAULT_UP)
  o:update_matrix()
  o.target = Object3D.new()
  o.shadow = {
    camera = OrthographicCamera.new(-5, 5, 5, -5, 0.5, 500),
    intensity = 1, bias = 0, normal_bias = 0, radius = 1, blur_samples = 8,
    map_size = Vector2.new(512, 512), map = nil, matrix = Matrix4.new(), auto_update = true, needs_update = false,
  }
  return o
end
local _lpw, _look, _psm = Vector3.new(), Vector3.new(), Matrix4.new()
-- three.js LightShadow.updateMatrices
function T.shadow_update_matrices(light)
  local sh = light.shadow
  local cam = sh.camera
  _lpw:set_from_matrix_position(light.matrix_world)
  cam.position:copy(_lpw)
  _look:set_from_matrix_position(light.target.matrix_world)
  cam:look_at(_look)
  cam:update_matrix_world()
  _psm:multiply_matrices(cam.projection_matrix, cam.matrix_world_inverse)
  sh.matrix:set(0.5, 0.0, 0.0, 0.5,
                0.0, 0.5, 0.0, 0.5,
                0.0, 0.0, 0.5, 0.5,
                0.0, 0.0, 0.0, 1.0)
  sh.matrix:multiply(_psm)
end

local PointLight = subclass('PointLight', Light); T.PointLight = PointLight
function PointLight.new(color, intensity, distance, decay)
  local o = Light.init(setmetatable({ type = 'PointLight', is_point_light = true }, PointLight), color, intensity)
  o.distance = distance or 0
  o.decay = decay == nil and 2 or decay
  return o
end

local AmbientLight = subclass('AmbientLight', Light); T.AmbientLight = AmbientLight
function AmbientLight.new(color, intensity) return Light.init(setmetatable({ type = 'AmbientLight', is_ambient_light = true }, AmbientLight), color, intensity) end

-- ---------------------------------------------------------------------------- BufferAttribute
local BufferAttribute = {}; BufferAttribute.__index = BufferAttribute
T.BufferAttribute = BufferAttribute
-- array: a Lua table of numbers, 1-based (three.js's typed array, 0-based)
function BufferAttribute.new(array, item_size, normalized)
  return setmetatable({ array = array, item_size = item_size, count = #array//item_size, normalized = normalized or false,
    version = 0, needs_update = false, dynamic = false, update_range = nil }, BufferAttribute)
end
-- a static attribute loaded from a file: its float32 bytes go to the GPU as they are; `array`
-- is unpacked from them only if Lua code reads the values
function BufferAttribute.from_blob(blob, item_size)
  local a = setmetatable({ blob = blob, item_size = item_size, count = #blob//(4*item_size), normalized = false,
    version = 0, needs_update = false, dynamic = false }, BufferAttribute)
  return a
end
function BufferAttribute:ensure_array()
  if self.array then return self.array end
  local b, arr, n = self.blob, {}, #self.blob//4
  local unpack, fmt = string.unpack, self.is_index and '<I4' or '<f'
  for i = 1, n do arr[i] = unpack(fmt, b, (i - 1)*4 + 1) end
  self.array = arr
  return arr
end
-- (2026-10-16, Phylactery 19) elements lo..hi (0-based, inclusive) were rewritten since the last upload: only they go
-- up (the renderer, with an engine that has gpu_mesh_update_range; without one, the whole array). needs_update = true
-- still sends everything. A writer that marks must mark every element it changed.
function BufferAttribute:mark(lo, hi)
  local a, b = self.range_lo, self.range_hi
  if not a then self.range_lo, self.range_hi = lo, hi
  else
    if lo < a then self.range_lo = lo end
    if hi > b then self.range_hi = hi end
  end
end
function BufferAttribute:get_x(i) return (self.array or self:ensure_array())[i*self.item_size + 1] end
function BufferAttribute:get_y(i) return (self.array or self:ensure_array())[i*self.item_size + 2] end
function BufferAttribute:get_z(i) return (self.array or self:ensure_array())[i*self.item_size + 3] end
function BufferAttribute:get_w(i) return (self.array or self:ensure_array())[i*self.item_size + 4] end
function BufferAttribute:set_x(i, v) self.array[i*self.item_size + 1] = v; return self end
function BufferAttribute:set_y(i, v) self.array[i*self.item_size + 2] = v; return self end
function BufferAttribute:set_z(i, v) self.array[i*self.item_size + 3] = v; return self end
function BufferAttribute:set_w(i, v) self.array[i*self.item_size + 4] = v; return self end
function BufferAttribute:set_xy(i, x, y) local b = i*self.item_size; self.array[b + 1], self.array[b + 2] = x, y; return self end
function BufferAttribute:set_xyz(i, x, y, z) local b = i*self.item_size; self.array[b + 1], self.array[b + 2], self.array[b + 3] = x, y, z; return self end
function BufferAttribute:set_xyzw(i, x, y, z, w) local b = i*self.item_size; self.array[b + 1], self.array[b + 2], self.array[b + 3], self.array[b + 4] = x, y, z, w; return self end
function BufferAttribute:set_usage(u) self.dynamic = (u == 'dynamic'); return self end
function BufferAttribute:clone()
  local a = {}; for i = 1, #self.array do a[i] = self.array[i] end
  local c = BufferAttribute.new(a, self.item_size, self.normalized); c.instanced = self.instanced; return c
end
function BufferAttribute:apply_matrix4(m)
  local v = Vector3.new()
  for i = 0, self.count - 1 do
    v:set(self:get_x(i), self:get_y(i), self:get_z(i)):apply_matrix4(m)
    self:set_xyz(i, v.x, v.y, v.z)
  end
  return self
end
function BufferAttribute:apply_normal_matrix(m)
  local v = Vector3.new()
  for i = 0, self.count - 1 do
    v:set(self:get_x(i), self:get_y(i), self:get_z(i)):apply_normal_matrix(m)
    self:set_xyz(i, v.x, v.y, v.z)
  end
  return self
end
function BufferAttribute:transform_direction(m)
  local v = Vector3.new()
  for i = 0, self.count - 1 do
    v:set(self:get_x(i), self:get_y(i), self:get_z(i)):transform_direction(m)
    self:set_xyz(i, v.x, v.y, v.z)
  end
  return self
end
T.float_attr = function(n, item_size) local a = {}; for i = 1, n*item_size do a[i] = 0 end; return BufferAttribute.new(a, item_size) end

-- ---------------------------------------------------------------------------- BufferGeometry
local BufferGeometry = {}; BufferGeometry.__index = BufferGeometry
T.BufferGeometry = BufferGeometry
function BufferGeometry.new()
  return setmetatable({ id = new_id(), attributes = {}, attribute_order = {}, index = nil, groups = {},
    draw_range = { start = 0, count = math.huge }, bounding_sphere = nil, bounding_box = nil, gpu = nil, name = '' }, BufferGeometry)
end
function BufferGeometry:set_attribute(name, attr)
  if not self.attributes[name] then self.attribute_order[#self.attribute_order + 1] = name end
  self.attributes[name] = attr
  if self.gpu then self.gpu_dirty = true end
  return self
end
function BufferGeometry:get_attribute(name) return self.attributes[name] end
function BufferGeometry:delete_attribute(name)
  self.attributes[name] = nil
  for i, n in ipairs(self.attribute_order) do if n == name then table.remove(self.attribute_order, i); break end end
  if self.gpu then self.gpu_dirty = true end
  return self
end
function BufferGeometry:set_index(index)
  if index and getmetatable(index) ~= BufferAttribute then index = BufferAttribute.new(index, 1) end
  self.index = index
  if self.gpu then self.gpu_dirty = true end
  return self
end
function BufferGeometry:set_draw_range(start, count) self.draw_range.start = start; self.draw_range.count = count end
function BufferGeometry:add_group(start, count, material_index) self.groups[#self.groups + 1] = { start = start, count = count, material_index = material_index or 0 } end
function BufferGeometry:apply_matrix4(m)
  local p = self.attributes.position
  if p then p:apply_matrix4(m); p.needs_update = true end
  local n = self.attributes.normal
  if n then n:apply_normal_matrix(Matrix3.new():get_normal_matrix(m)); n.needs_update = true end
  if self.bounding_box then self:compute_bounding_box() end
  if self.bounding_sphere then self:compute_bounding_sphere() end
  return self
end
function BufferGeometry:rotate_x(a) return self:apply_matrix4(Matrix4.new():make_rotation_x(a)) end
function BufferGeometry:rotate_y(a) return self:apply_matrix4(Matrix4.new():make_rotation_y(a)) end
function BufferGeometry:rotate_z(a) return self:apply_matrix4(Matrix4.new():make_rotation_z(a)) end
function BufferGeometry:translate(x, y, z) return self:apply_matrix4(Matrix4.new():make_translation(x, y, z)) end
function BufferGeometry:scale(x, y, z) return self:apply_matrix4(Matrix4.new():make_scale(x, y, z)) end
function BufferGeometry:compute_bounding_box()
  local p = self.attributes.position
  local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
  if p then
    local a = p.array
    for i = 0, p.count - 1 do
      local b = i*p.item_size
      local x, y, z = a[b + 1], a[b + 2], a[b + 3]
      if x < mn.x then mn.x = x end; if y < mn.y then mn.y = y end; if z < mn.z then mn.z = z end
      if x > mx.x then mx.x = x end; if y > mx.y then mx.y = y end; if z > mx.z then mx.z = z end
    end
  end
  self.bounding_box = { min = mn, max = mx }
  return self.bounding_box
end
-- three.js: the centre of the bounding box, the radius the farthest vertex from it
function BufferGeometry:compute_bounding_sphere()
  local p = self.attributes.position
  local box = self:compute_bounding_box()
  local c = Vector3.new((box.min.x + box.max.x)/2, (box.min.y + box.max.y)/2, (box.min.z + box.max.z)/2)
  local r2 = 0
  if p then
    local a = p.array
    for i = 0, p.count - 1 do
      local b = i*p.item_size
      local dx, dy, dz = a[b + 1] - c.x, a[b + 2] - c.y, a[b + 3] - c.z
      local d = dx*dx + dy*dy + dz*dz
      if d > r2 then r2 = d end
    end
  end
  self.bounding_sphere = { center = c, radius = math.sqrt(r2) }
  return self.bounding_sphere
end
-- three.js computeVertexNormals (indexed: accumulated face normals; non-indexed: per face)
function BufferGeometry:compute_vertex_normals()
  local pos = self.attributes.position
  if not pos then return end
  local n = self.attributes.normal
  if not n or n.count ~= pos.count then n = T.float_attr(pos.count, 3); self:set_attribute('normal', n)
  else for i = 1, #n.array do n.array[i] = 0 end end
  local P, N = pos.array, n.array
  local function face(a, b, c)
    local ax, ay, az = P[a*3 + 1], P[a*3 + 2], P[a*3 + 3]
    local bx, by, bz = P[b*3 + 1], P[b*3 + 2], P[b*3 + 3]
    local cx, cy, cz = P[c*3 + 1], P[c*3 + 2], P[c*3 + 3]
    local e1x, e1y, e1z = cx - bx, cy - by, cz - bz
    local e2x, e2y, e2z = ax - bx, ay - by, az - bz
    local nx, ny, nz = e1y*e2z - e1z*e2y, e1z*e2x - e1x*e2z, e1x*e2y - e1y*e2x
    return nx, ny, nz
  end
  if self.index then
    local I = self.index.array
    for i = 1, #I, 3 do
      local a, b, c = I[i], I[i + 1], I[i + 2]
      local nx, ny, nz = face(a, b, c)
      for _, v in ipairs({ a, b, c }) do N[v*3 + 1] = N[v*3 + 1] + nx; N[v*3 + 2] = N[v*3 + 2] + ny; N[v*3 + 3] = N[v*3 + 3] + nz end
    end
  else
    for i = 0, pos.count - 1, 3 do
      local nx, ny, nz = face(i, i + 1, i + 2)
      for v = i, i + 2 do N[v*3 + 1], N[v*3 + 2], N[v*3 + 3] = nx, ny, nz end
    end
  end
  for v = 0, n.count - 1 do
    local x, y, z = N[v*3 + 1], N[v*3 + 2], N[v*3 + 3]
    local l = math.sqrt(x*x + y*y + z*z); if l == 0 then l = 1 end
    N[v*3 + 1], N[v*3 + 2], N[v*3 + 3] = x/l, y/l, z/l
  end
  n.needs_update = true
end
function BufferGeometry:to_non_indexed()
  if not self.index then return self:clone() end
  local g = BufferGeometry.new()
  local I = self.index.array
  for _, name in ipairs(self.attribute_order) do
    local a = self.attributes[name]
    local s, src, out = a.item_size, a.array, {}
    local k = 0
    for i = 1, #I do
      local b = I[i]*s
      for c = 1, s do k = k + 1; out[k] = src[b + c] end
    end
    g:set_attribute(name, BufferAttribute.new(out, s, a.normalized))
  end
  for _, gr in ipairs(self.groups) do g:add_group(gr.start, gr.count, gr.material_index) end
  return g
end
function BufferGeometry:clone()
  local g = BufferGeometry.new()
  for _, name in ipairs(self.attribute_order) do g:set_attribute(name, self.attributes[name]:clone()) end
  if self.index then g:set_index(self.index:clone()) end
  for _, gr in ipairs(self.groups) do g:add_group(gr.start, gr.count, gr.material_index) end
  g.draw_range.start, g.draw_range.count = self.draw_range.start, self.draw_range.count
  return g
end
-- mergeGeometries(geometries, false): attributes concatenated in the first geometry's order, indices offset
function T.merge_geometries(list)
  local g = BufferGeometry.new()
  local first = list[1]
  local indexed = first.index ~= nil
  for _, name in ipairs(first.attribute_order) do
    local out, k, s = {}, 0, first.attributes[name].item_size
    for _, src in ipairs(list) do
      local a = src.attributes[name].array
      for i = 1, #a do k = k + 1; out[k] = a[i] end
    end
    g:set_attribute(name, BufferAttribute.new(out, s, first.attributes[name].normalized))
  end
  if indexed then
    local out, k, offset = {}, 0, 0
    for _, src in ipairs(list) do
      local I = src.index.array
      for i = 1, #I do k = k + 1; out[k] = I[i] + offset end
      offset = offset + src.attributes.position.count
    end
    g:set_index(out)
  end
  return g
end

-- ---------------------------------------------------------------------------- Texture
-- A gpu texture and what three.js knew about it (for uniforms: its size, uv matrix; the renderer
-- uploads data textures once, and again when needs_update is set).
local Texture = {}; Texture.__index = Texture
T.Texture = Texture
function Texture.new(gpu, w, h)
  local t = setmetatable({ id = new_id(), gpu = gpu, width = w or 0, height = h or 0, matrix = Matrix3.new(), matrix_auto_update = true,
    offset = Vector2.new(0, 0), repeat_ = Vector2.new(1, 1), center = Vector2.new(0, 0), rotation = 0, needs_update = false,
    is_render_target_texture = false, color_space = 'linear', user_data = {} }, Texture)
  return t
end
function Texture:update_matrix()
  self.matrix:set_uv_transform(self.offset.x, self.offset.y, self.repeat_.x, self.repeat_.y, self.rotation, self.center.x, self.center.y)
end

return T
