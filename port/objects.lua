--[[
  objects.lua -- the port to Anchor: three.js object trees as the three.js build exported them
  (port_export.js export_objects): groups and meshes with their transforms, shadow flags and the
  userData the game reads, and materials made from their exported parameters and uniforms
  (onBeforeCompile ones go to material.custom and user_data.U, as items.js keeps them).
    local B = OB.builder(assets, mats_desc, { gi = cave.GU })    -- one per instance (fresh materials)
    local group = B.node(node_desc)
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local FX = require('port.fx')
local Vector2, Vector3, Vector4, Matrix3, Matrix4, Color = TM.Vector2, TM.Vector3, TM.Vector4, TM.Matrix3, TM.Matrix4, TM.Color

local OB = {}

local PROP = { side = 'side', transparent = 'transparent', opacity = 'opacity', depthWrite = 'depth_write', depthTest = 'depth_test', colorWrite = 'color_write',
  blending = 'blending', vertexColors = 'vertex_colors', flatShading = 'flat_shading', roughness = 'roughness', metalness = 'metalness',
  envMapIntensity = 'env_map_intensity', transmission = 'transmission', thickness = 'thickness', ior = 'ior', dispersion = 'dispersion',
  attenuationDistance = 'attenuation_distance', specularIntensity = 'specular_intensity', iridescence = 'iridescence', iridescenceIOR = 'iridescence_ior',
  clearcoat = 'clearcoat', clearcoatRoughness = 'clearcoat_roughness', sheen = 'sheen', sheenRoughness = 'sheen_roughness', emissiveIntensity = 'emissive_intensity',
  alphaTest = 'alpha_test', polygonOffset = 'polygon_offset', polygonOffsetFactor = 'polygon_offset_factor', polygonOffsetUnits = 'polygon_offset_units',
  premultipliedAlpha = 'premultiplied_alpha', toneMapped = 'tone_mapped', fog = 'fog', forceSinglePass = 'force_single_pass', shadowSide = 'shadow_side',
  reflectivity = 'reflectivity', anisotropy = 'anisotropy', lights = 'lights' }
local COLORS = { color = 'color', emissive = 'emissive', specularColor = 'specular_color', attenuationColor = 'attenuation_color', sheenColor = 'sheen_color' }
local TEXS = { map = 'map', roughnessMap = 'roughness_map', alphaMap = 'alpha_map', envMap = 'env_map', normalMap = 'normal_map', metalnessMap = 'metalness_map',
  emissiveMap = 'emissive_map' }
local TYPES = { MeshStandardMaterial = MAT.MeshStandardMaterial, MeshPhysicalMaterial = MAT.MeshPhysicalMaterial, ShaderMaterial = MAT.ShaderMaterial,
  MeshBasicMaterial = MAT.MeshBasicMaterial, MeshLambertMaterial = MAT.MeshLambertMaterial }

local function num(v)
  if v == 'Infinity' then return math.huge elseif v == '-Infinity' then return -math.huge end
  return v
end

function OB.builder(A, mats_desc, opts)
  opts = opts or {}
  local made = {}
  local function decode(v)
    local ty = type(v)
    if ty ~= 'table' then return num(v) end
    if v.tex then return A.texture(v.tex) end
    if v.color then return Color.new(v.color[1], v.color[2], v.color[3]) end
    if v.v then
      local a = v.v
      if #a == 2 then return Vector2.new(a[1], a[2]) elseif #a == 3 then return Vector3.new(a[1], a[2], a[3]) end
      return Vector4.new(a[1], a[2], a[3], a[4])
    end
    if v.m3 then local m = Matrix3.new(); for k = 1, 9 do m.elements[k] = v.m3[k] end; return m end
    if v.m4 then local m = Matrix4.new(); for k = 1, 16 do m.elements[k] = v.m4[k] end; return m end
    if v.list then local out = {}; for k, e in ipairs(v.list) do out[k] = decode(e) end; return out end
    return nil
  end
  local B = {}
  -- material i (0-based, as exported), made once per builder
  function B.material(i)
    if made[i] then return made[i] end
    local d = mats_desc[i + 1]
    local m = TYPES[d.type].new({ name = d.name })
    for k, v in pairs(d.props or {}) do local key = PROP[k]; if key then m[key] = num(v) end end
    for k, c in pairs(d.colors or {}) do m[COLORS[k]] = Color.new(c[1], c[2], c[3]) end
    for k, t in pairs(d.textures or {}) do m[TEXS[k]] = A.texture(t) end
    local U = {}
    local any = false
    for k, v in pairs(d.uniforms or {}) do U[k] = { value = decode(v) }; any = true end
    if d.name == 'item.orbs' then U.uMark = { value = 0 }; U.uMarkStyle = { value = 0 } end   -- (round 45: port/orbmarks.lua)
    if d.type == 'ShaderMaterial' then m.uniforms = U; m.user_data.U = U
    elseif any then m.custom = U; m.user_data.U = U end
    if opts.gi and d.type ~= 'ShaderMaterial' then FX.gi_dynamic(m, opts.gi) end
    made[i] = m
    return m
  end
  function B.node(n)
    local o
    if n.t == 'Mesh' or n.t == 'InstancedMesh' then
      local mat
      if type(n.mat) == 'table' then mat = {}; for k, i in ipairs(n.mat) do mat[k] = B.material(i) end else mat = B.material(n.mat) end
      o = T.Mesh.new(A.geometry(n.geo), mat)
    else o = T.Group.new() end
    o.name = n.name or ''
    local trs = n.trs
    o.position:set(trs.p[1], trs.p[2], trs.p[3])
    o.quaternion:set(trs.q[1], trs.q[2], trs.q[3], trs.q[4])
    o.scale:set(trs.s[1], trs.s[2], trs.s[3])
    o.visible = n.visible ~= false
    o.render_order = n.ro or 0
    o.cast_shadow = n.cs or false
    o.receive_shadow = n.rs or false
    o.frustum_culled = n.fc ~= false
    o.user_data = { no_shadow = n.ud and n.ud.no_shadow or false, no_contact = n.ud and n.ud.no_contact or false, r = n.ud and n.ud.r }
    for _, c in ipairs(n.children or {}) do o:add(B.node(c)) end
    return o
  end
  return B
end

return OB
