--[[
  three/materials.lua -- the port to Anchor: three.js r170's materials, the types the game uses,
  with their defaults and the uniforms three.js uploads for them (WebGLMaterials +
  ShaderLib/UniformsLib defaults). A material's `name` picks the program three.js compiled for it
  (programs.lua); `custom` holds the uniforms its onBeforeCompile patch added ({ name = { value } },
  shared with the game code exactly as in JS).

  write_uniforms(material, set, env) calls set(name, value) for every uniform three.js would
  have in the material's uniform list, values in the forms gpu_set takes: numbers, booleans,
  tables of numbers (vectors, colours, matrices column-major) and gpu textures.
]]
local TM = require('port.three.math')
local Color, Vector2, Matrix3 = TM.Color, TM.Vector2, TM.Matrix3
local MAT = {}

MAT.FrontSide, MAT.BackSide, MAT.DoubleSide = 0, 1, 2
MAT.NoBlending, MAT.NormalBlending, MAT.AdditiveBlending, MAT.SubtractiveBlending, MAT.MultiplyBlending, MAT.CustomBlending = 0, 1, 2, 3, 4, 5
MAT.AddEquation, MAT.SubtractEquation, MAT.ReverseSubtractEquation, MAT.MinEquation, MAT.MaxEquation = 100, 101, 102, 103, 104
MAT.ZeroFactor, MAT.OneFactor, MAT.SrcColorFactor, MAT.OneMinusSrcColorFactor, MAT.SrcAlphaFactor, MAT.OneMinusSrcAlphaFactor,
  MAT.DstAlphaFactor, MAT.OneMinusDstAlphaFactor, MAT.DstColorFactor, MAT.OneMinusDstColorFactor = 200, 201, 202, 203, 204, 205, 206, 207, 208, 209
MAT.LessEqualDepth = 3

local next_id = 0
local Material = {}; Material.__index = Material
MAT.Material = Material

local function base(o)
  next_id = next_id + 1
  o.id = next_id
  o.name = o.name or ''
  o.version = 0
  o.side = MAT.FrontSide
  o.shadow_side = nil
  o.transparent = false
  o.opacity = 1
  o.blending = MAT.NormalBlending
  o.blend_src, o.blend_dst, o.blend_equation = MAT.SrcAlphaFactor, MAT.OneMinusSrcAlphaFactor, MAT.AddEquation
  o.blend_src_alpha, o.blend_dst_alpha, o.blend_equation_alpha = nil, nil, nil
  o.depth_test, o.depth_write, o.color_write = true, true, true
  o.polygon_offset, o.polygon_offset_factor, o.polygon_offset_units = false, 0, 0
  o.alpha_test = 0
  o.visible = true
  o.tone_mapped = true
  o.vertex_colors = false
  o.premultiplied_alpha = false
  o.force_single_pass = false
  o.fog = false
  o.user_data = {}
  o.custom = nil                       -- onBeforeCompile's uniforms: { name = { value = ... } }
  return o
end

-- options use the snake_case of three.js's parameter names; colours as hex numbers or Colors
local COLOR_KEYS = { color = true, emissive = true, specular_color = true, attenuation_color = true, sheen_color = true }
local function apply(o, opts)
  for k, v in pairs(opts or {}) do
    if COLOR_KEYS[k] then o[k] = type(v) == 'table' and Color.new():copy(v) or Color.new(v)
    else o[k] = v end
  end
  return o
end

local function new_type(type_name, defaults)
  local C = setmetatable({}, { __index = Material }); C.__index = C
  C.type = type_name
  C.new = function(opts)
    local o = base(setmetatable({ type = type_name }, C))
    if defaults then defaults(o) end
    apply(o, opts)
    return o
  end
  return C
end

MAT.MeshBasicMaterial = new_type('MeshBasicMaterial', function(o)
  o.color = Color.new(0xffffff); o.map = nil; o.alpha_map = nil; o.env_map = nil; o.fog = true
end)
MAT.MeshLambertMaterial = new_type('MeshLambertMaterial', function(o)
  o.color = Color.new(0xffffff); o.emissive = Color.new(0x000000); o.emissive_intensity = 1
  o.map = nil; o.alpha_map = nil; o.flat_shading = false; o.fog = true; o.needs_lights = true
end)
MAT.MeshStandardMaterial = new_type('MeshStandardMaterial', function(o)
  o.color = Color.new(0xffffff); o.roughness = 1; o.metalness = 0
  o.emissive = Color.new(0x000000); o.emissive_intensity = 1
  o.map = nil; o.alpha_map = nil; o.env_map = nil; o.env_map_intensity = 1; o.flat_shading = false; o.fog = true
  o.needs_lights = true; o.is_standard = true
end)
MAT.MeshPhysicalMaterial = new_type('MeshPhysicalMaterial', function(o)
  MAT.MeshStandardMaterial.new_defaults(o)
  o.is_physical = true
  o.ior = 1.5; o.specular_intensity = 1; o.specular_color = Color.new(1, 1, 1)
  o.clearcoat = 0; o.clearcoat_roughness = 0; o.sheen = 0; o.sheen_color = Color.new(0x000000); o.sheen_roughness = 1
  o.transmission = 0; o.thickness = 0; o.attenuation_distance = math.huge; o.attenuation_color = Color.new(1, 1, 1)
  o.dispersion = 0; o.iridescence = 0; o.iridescence_ior = 1.3; o.iridescence_thickness_range = { 100, 400 }
  o.anisotropy = 0; o.anisotropy_rotation = 0
end)
MAT.MeshStandardMaterial.new_defaults = function(o)
  o.color = Color.new(0xffffff); o.roughness = 1; o.metalness = 0
  o.emissive = Color.new(0x000000); o.emissive_intensity = 1
  o.map = nil; o.alpha_map = nil; o.env_map = nil; o.env_map_intensity = 1; o.flat_shading = false; o.fog = true
  o.needs_lights = true; o.is_standard = true
end
MAT.PointsMaterial = new_type('PointsMaterial', function(o)
  o.color = Color.new(0xffffff); o.size = 1; o.size_attenuation = true; o.map = nil; o.alpha_map = nil; o.fog = true
end)
MAT.ShaderMaterial = new_type('ShaderMaterial', function(o)
  o.uniforms = {}; o.lights = false; o.is_shader = true
end)
MAT.MeshDepthMaterial = new_type('MeshDepthMaterial', function(o)
  o.map = nil; o.alpha_map = nil; o.is_depth = true
end)

function Material:clone()
  local c = setmetatable({}, getmetatable(self))
  for k, v in pairs(self) do
    if type(v) == 'table' and v.is_color then c[k] = v:clone() else c[k] = v end
  end
  next_id = next_id + 1
  c.id = next_id
  c.user_data = {}
  if self.uniforms then
    c.uniforms = {}
    for k, u in pairs(self.uniforms) do
      local v = u.value
      if type(v) == 'table' and v.clone and not v.gpu then v = v:clone() end
      c.uniforms[k] = { value = v }
    end
  end
  return c
end
function Material:needs_update() self.version = self.version + 1 end

-- ---------------------------------------------------------------------------- uniform values
local IDENT3 = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
-- (round 64: constant values are shared tables and a colour's or vector's array is kept on it and refilled: these were
-- new tables at every material change of every draw; gpu_set reads them at once, a trace copies them)
local ONE2, ONE3, ZERO2, ZERO3 = { 1, 1 }, { 1, 1, 1 }, { 0, 0 }, { 0, 0, 0 }
local function col(c)
  local a = c._u3
  if not a then a = {}; c._u3 = a end
  a[1], a[2], a[3] = c.r, c.g, c.b
  return a
end
local function transform(tex)
  if not tex then return IDENT3 end
  if tex.matrix_auto_update then tex:update_matrix() end
  return tex.matrix.elements
end
local function tex_of(t) return t and t.gpu or nil end

-- ShaderMaterial / onBeforeCompile uniform values in gpu_set form
local function value_of(v)
  local ty = type(v)
  if ty == 'number' or ty == 'boolean' then return v end
  if ty ~= 'table' then return v end
  if v.gpu ~= nil then return v.gpu end                   -- a Texture
  if v.is_color then return col(v) end
  if v.elements then return v.elements end                -- Matrix3 / Matrix4
  local a = v._u
  if v.w ~= nil and v.x ~= nil then if not a then a = {}; v._u = a end; a[1], a[2], a[3], a[4] = v.x, v.y, v.z, v.w; return a end
  if v.z ~= nil and v.x ~= nil then if not a then a = {}; v._u = a end; a[1], a[2], a[3] = v.x, v.y, v.z; return a end
  if v.x ~= nil and v.y ~= nil then if not a then a = {}; v._u = a end; a[1], a[2] = v.x, v.y; return a end
  if v._w ~= nil then if not a then a = {}; v._u = a end; a[1], a[2], a[3], a[4] = v._x, v._y, v._z, v._w; return a end
  if #v > 0 and type(v[1]) == 'table' then                 -- an array of vectors
    local out = {}
    for _, e in ipairs(v) do for _, n in ipairs(value_of(e)) do out[#out + 1] = n end end
    return out
  end
  return v
end
MAT.value_of = value_of

local function common(m, set)
  set('opacity', m.opacity)
  set('diffuse', col(m.color or Color.new(0xffffff)))
  if m.emissive then
    local a = m._emis
    if not a then a = {}; m._emis = a end
    a[1], a[2], a[3] = m.emissive.r*m.emissive_intensity, m.emissive.g*m.emissive_intensity, m.emissive.b*m.emissive_intensity
    set('emissive', a)
  end
  set('map', tex_of(m.map)); set('mapTransform', transform(m.map))
  set('alphaMap', tex_of(m.alpha_map)); set('alphaMapTransform', transform(m.alpha_map))
  set('alphaTest', m.alpha_test)
end
local function envmap(m, set, env_map)
  set('envMap', tex_of(env_map))
  set('envMapRotation', IDENT3)
  set('flipEnvMap', env_map and 1 or -1)                  -- a PMREM (a render target): 1
  set('reflectivity', m.reflectivity or 1)
  set('ior', m.ior or 1.5)
  set('refractionRatio', m.refraction_ratio or 0.98)
end
local function maps_defaults(set)
  set('aoMap', nil); set('aoMapIntensity', 1); set('aoMapTransform', IDENT3)
  set('lightMap', nil); set('lightMapIntensity', 1); set('lightMapTransform', IDENT3)
  set('emissiveMap', nil); set('emissiveMapTransform', IDENT3)
  set('bumpMap', nil); set('bumpMapTransform', IDENT3); set('bumpScale', 1)
  set('normalMap', nil); set('normalMapTransform', IDENT3); set('normalScale', ONE2)
  set('displacementMap', nil); set('displacementMapTransform', IDENT3); set('displacementScale', 1); set('displacementBias', 0)
  set('specularMap', nil); set('specularMapTransform', IDENT3)
  set('roughnessMap', nil); set('roughnessMapTransform', IDENT3)
  set('metalnessMap', nil); set('metalnessMapTransform', IDENT3)
  set('fogDensity', 0.00025); set('fogNear', 1); set('fogFar', 2000); set('fogColor', ONE3)
end

-- env = { lights = the renderer's light state (write_lights), transmission = { texture, w, h },
--         env_map = the PMREM for the material (a Texture) or nil, height = drawing buffer height }
function MAT.write_uniforms(m, set, env)
  local ty = m.type
  if ty == 'ShaderMaterial' then
    for name, u in pairs(m.uniforms) do set(name, value_of(u.value)) end
  elseif ty == 'PointsMaterial' then
    set('diffuse', col(m.color)); set('opacity', m.opacity)
    set('size', m.size); set('scale', (env.height or 360)*0.5)
    set('map', tex_of(m.map)); set('uvTransform', transform(m.map))
    set('alphaMap', tex_of(m.alpha_map)); set('alphaMapTransform', transform(m.alpha_map))
    set('alphaTest', m.alpha_test)
    set('fogDensity', 0.00025); set('fogNear', 1); set('fogFar', 2000); set('fogColor', ONE3)
  elseif ty == 'MeshDepthMaterial' then
    set('opacity', m.opacity)
    set('map', tex_of(m.map)); set('mapTransform', transform(m.map))
    set('alphaMap', tex_of(m.alpha_map)); set('alphaMapTransform', transform(m.alpha_map))
    set('alphaTest', m.alpha_test)
    set('displacementMap', nil); set('displacementMapTransform', IDENT3); set('displacementScale', 1); set('displacementBias', 0)
  else
    maps_defaults(set)
    if m.roughness_map then set('roughnessMap', tex_of(m.roughness_map)); set('roughnessMapTransform', transform(m.roughness_map)) end
    common(m, set)
    -- the material's environment, or (a standard material without one) the scene's
    local em = env.env_map or (m.is_standard and env.environment) or nil
    envmap(m, set, em)
    if m.is_standard then
      set('roughness', m.roughness); set('metalness', m.metalness)
      -- (WebGLRenderer.setProgram: a standard material on scene.environment takes its intensity)
      if not m.env_map and env.environment then set('envMapIntensity', env.environment_intensity or 1)
      else set('envMapIntensity', m.env_map_intensity) end
    end
    if m.is_physical then
      set('ior', m.ior)
      set('clearcoat', m.clearcoat); set('clearcoatRoughness', m.clearcoat_roughness); set('clearcoatNormalScale', ONE2)
      set('clearcoatMap', nil); set('clearcoatRoughnessMap', nil); set('clearcoatNormalMap', nil)
      set('clearcoatMapTransform', IDENT3); set('clearcoatNormalMapTransform', IDENT3); set('clearcoatRoughnessMapTransform', IDENT3)
      set('dispersion', m.dispersion)
      set('iridescence', m.iridescence); set('iridescenceIOR', m.iridescence_ior)
      set('iridescenceThicknessMinimum', m.iridescence > 0 and m.iridescence_thickness_range[1] or 100)
      set('iridescenceThicknessMaximum', m.iridescence > 0 and m.iridescence_thickness_range[2] or 400)
      set('iridescenceMap', nil); set('iridescenceMapTransform', IDENT3); set('iridescenceThicknessMap', nil); set('iridescenceThicknessMapTransform', IDENT3)
      set('sheen', m.sheen)
      set('sheenColor', m.sheen > 0 and { m.sheen_color.r*m.sheen, m.sheen_color.g*m.sheen, m.sheen_color.b*m.sheen } or ZERO3)
      set('sheenRoughness', m.sheen > 0 and m.sheen_roughness or 1)
      set('sheenColorMap', nil); set('sheenColorMapTransform', IDENT3); set('sheenRoughnessMap', nil); set('sheenRoughnessMapTransform', IDENT3)
      if m.transmission > 0 then
        set('transmission', m.transmission)
        local tr = env.transmission
        set('transmissionSamplerMap', tr and tr.texture or nil)
        set('transmissionSamplerSize', tr and { tr.w, tr.h } or ZERO2)
        set('thickness', m.thickness)
        set('attenuationDistance', m.attenuation_distance)
        set('attenuationColor', col(m.attenuation_color))
      else
        set('transmission', 0); set('transmissionSamplerMap', nil); set('transmissionSamplerSize', ZERO2)
        set('thickness', 0); set('attenuationDistance', 0); set('attenuationColor', ZERO3)
      end
      set('transmissionMap', nil); set('transmissionMapTransform', IDENT3); set('thicknessMap', nil); set('thicknessMapTransform', IDENT3)
      set('anisotropyVector', m.anisotropy > 0 and { m.anisotropy*math.cos(m.anisotropy_rotation), m.anisotropy*math.sin(m.anisotropy_rotation) } or ZERO2)
      set('anisotropyMap', nil); set('anisotropyMapTransform', IDENT3)
      set('specularIntensity', m.specular_intensity); set('specularColor', col(m.specular_color))
      set('specularColorMap', nil); set('specularColorMapTransform', IDENT3); set('specularIntensityMap', nil); set('specularIntensityMapTransform', IDENT3)
    end
  end
  -- the patch's uniforms (onBeforeCompile); for a ShaderMaterial they are its own uniforms
  if m.custom then for name, u in pairs(m.custom) do set(name, value_of(u.value)) end end
end

-- the light uniforms (WebGLLights state), for a material whose program reads lights
function MAT.write_lights(set, L)
  set('ambientLightColor', L.ambient)
  set('lightProbe', L.probe)
  for i, d in ipairs(L.directional) do
    local p = 'directionalLights[' .. (i - 1) .. '].'
    set(p .. 'direction', d.direction); set(p .. 'color', d.color)
  end
  for i, s in ipairs(L.directional_shadow) do
    local p = 'directionalLightShadows[' .. (i - 1) .. '].'
    set(p .. 'shadowIntensity', s.intensity); set(p .. 'shadowBias', s.bias); set(p .. 'shadowNormalBias', s.normal_bias)
    set(p .. 'shadowRadius', s.radius); set(p .. 'shadowMapSize', s.map_size)
    set('directionalShadowMap[' .. (i - 1) .. ']', s.map)
    set('directionalShadowMatrix[' .. (i - 1) .. ']', s.matrix)
  end
  for i, pt in ipairs(L.point) do
    local p = 'pointLights[' .. (i - 1) .. '].'
    set(p .. 'position', pt.position); set(p .. 'color', pt.color); set(p .. 'distance', pt.distance); set(p .. 'decay', pt.decay)
  end
end

return MAT
