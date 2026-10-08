--[[
  eggshards.lua -- round 60 (owner, 2026-10-07: "the way it hatches should be more irregular, it's currently too neat"):
  bits of shell broken off the rim as the cap goes: small irregular pieces (two triangles each, 3-6 cm), thrown out from
  points along the crack, up and outward, turning, bouncing and settling on the floor. Outside the egg's warm colour
  lit by the sun, inside the hatch's light. A program of their own (GLSL here), added to three.js's library.
]]
local T = require('port.three.core')
local MAT = require('port.three.materials')
local TM = require('port.three.math')
local U = require('port.util')
local Vector3, Quaternion = TM.Vector3, TM.Quaternion
local sin, cos, sqrt, pi, max = math.sin, math.cos, math.sqrt, math.pi, math.max

local ES = {}
ES.N = 14

local VS = [[#version 300 es
precision highp float;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
uniform mat4 modelMatrix;
in vec3 position;
in vec3 normal;
out vec3 vN;
void main(){ vN = mat3(modelMatrix)*normal; gl_Position = projectionMatrix*modelViewMatrix*vec4(position, 1.0); }
]]
local FS = [[#version 300 es
precision highp float;
uniform vec3 uColor, uInner, uSun;
in vec3 vN;
out vec4 fragColor;
void main(){
  if (!gl_FrontFacing) { fragColor = vec4(uInner, 1.0); return; }
  float l = max(dot(normalize(vN), uSun), 0.0);
  fragColor = vec4(uColor*(0.25 + 0.75*l), 1.0);
}
]]

function ES.add_programs(lib) rawset(lib, 'egg.shard|world|2|-', { vs = VS, fs = FS }) end

-- opts: R, ground_y(x, z), sun = { x, y, z } (toward the sun), rng
function ES.create(opts)
  local rng = opts.rng or U.make_rng(61)
  local mat = MAT.ShaderMaterial.new({ name = 'egg.shard', side = MAT.DoubleSide, uniforms = {
    uColor = { value = Vector3.new(0.95, 0.66, 0.34) }, uInner = { value = Vector3.new(0.9, 0.7, 0.45) },
    uSun = { value = Vector3.new(opts.sun[1], opts.sun[2], opts.sun[3]):normalize() } } })
  local S = {}
  local function piece()
    -- an uneven quad (two triangles) in its own plane, normal +z
    local w, h = rng.float(0.03, 0.06), rng.float(0.025, 0.05)
    local p = {
      { -w*rng.float(0.3, 0.6), -h*rng.float(0.3, 0.6) }, { w*rng.float(0.3, 0.6), -h*rng.float(0.2, 0.6) },
      { w*rng.float(0.2, 0.6), h*rng.float(0.3, 0.6) }, { -w*rng.float(0.2, 0.5), h*rng.float(0.2, 0.6) },
    }
    local pos, nor = {}, {}
    for _, tri in ipairs({ { 1, 2, 3 }, { 1, 3, 4 } }) do
      for _, k in ipairs(tri) do
        pos[#pos + 1] = p[k][1]; pos[#pos + 1] = p[k][2]; pos[#pos + 1] = 0
        nor[#nor + 1] = 0; nor[#nor + 1] = 0; nor[#nor + 1] = 1
      end
    end
    local g = T.BufferGeometry.new()
    g:set_attribute('position', T.BufferAttribute.new(pos, 3))
    g:set_attribute('normal', T.BufferAttribute.new(nor, 3))
    local m = T.Mesh.new(g, mat)
    m.visible = false; m.frustum_culled = false
    opts.R.world_scene:add(m)
    return { m = m, v = Vector3.new(), ax = Vector3.new(), w = 0, rest = false }
  end
  for i = 1, ES.N do S[i] = piece() end
  local Q = Quaternion.new()
  local api = { meshes = {} }
  for i, s in ipairs(S) do api.meshes[i] = s.m end
  -- from the rim: points (shell space: x, y, z) carried to the world by the shell's matrix; out = their outward
  -- direction there (shell space, level); back = away from the camera (world, level)
  function api.spawn(shell, rim_at, back)
    shell:update_world_matrix(true, false)
    for _, s in ipairs(S) do
      local th = rng.float(0, 2*pi)
      local x, y, z = rim_at(th)
      local p = Vector3.new(x, y, z):apply_matrix4(shell.matrix_world)
      s.m.position:copy(p)
      local o = Vector3.new(cos(th), 0, sin(th)):transform_direction(shell.matrix_world)
      local sp = rng.float(0.8, 1.9)
      s.v:set(o.x*sp + back[1]*0.3, rng.float(1.0, 2.2), o.z*sp + back[2]*0.3)
      s.ax:set(rng.spread(1), rng.spread(1), rng.spread(1)):normalize()
      s.w = rng.float(8, 18)
      s.m.quaternion:set_from_axis_angle(s.ax, rng.float(0, 2*pi))
      s.m.visible = true; s.rest = false
    end
  end
  function api.update(dt)
    for _, s in ipairs(S) do
      if s.m.visible and not s.rest then
        local p = s.m.position
        s.v.y = s.v.y - 9.8*dt
        p.x = p.x + s.v.x*dt; p.y = p.y + s.v.y*dt; p.z = p.z + s.v.z*dt
        local g = opts.ground_y(p.x, p.z) + 0.006
        if p.y < g then
          p.y = g
          if s.v.y < -0.8 then s.v.y = -s.v.y*0.3; s.v.x = s.v.x*0.5; s.v.z = s.v.z*0.5; s.w = s.w*0.5
          else s.rest = true end
        end
        s.m.quaternion:premultiply(Q:set_from_axis_angle(s.ax, s.w*dt))
      end
    end
  end
  return api
end

return ES
