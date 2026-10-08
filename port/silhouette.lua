--[[
  silhouette.lua -- round 57 (owner, 2026-10-07: "we need some kind of shader or effect where the only the egg and
  lich are visible but they become not textured, like flat colors, so the final shot is darkness + two
  sillouettes"). The egg (with the snakes coiled on it) and the lich (with his mask) are drawn a second time, each in
  one flat colour, into a target of their own with its own depth; post.lua's last pass (sil.comp) then takes the
  frame toward darkness and, where they are, toward those flat colours, by SL.e (0 = the game as it is, 1 = only the
  two shapes). Programs of its own (GLSL here), added to three.js's library under their keys.
]]
local MAT = require('port.three.materials')
local RD = require('port.three.renderer')
local TM = require('port.three.math')
local Vector3 = TM.Vector3

local SL = {}
-- the colours (UP / DOWN in the sequence): sRGB, as they show
SL.STYLES = {
  { name = 'THEIR OWN COLOURS', egg = { 0.93, 0.70, 0.34 }, lich = { 0.90, 0.80, 0.76 } },
  { name = 'BOTH PALE', egg = { 0.90, 0.86, 0.78 }, lich = { 0.90, 0.86, 0.78 } },
  { name = 'BOTH WARM', egg = { 0.88, 0.64, 0.31 }, lich = { 0.88, 0.64, 0.31 } },
}

local VS = [[#version 300 es
precision highp float;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
in vec3 position;
void main(){ gl_Position = projectionMatrix*modelViewMatrix*vec4(position, 1.0); }
]]
local VS_I = [[#version 300 es
precision highp float;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
in vec3 position;
in mat4 instanceMatrix;
void main(){ gl_Position = projectionMatrix*modelViewMatrix*instanceMatrix*vec4(position, 1.0); }
]]
local FS = [[#version 300 es
precision highp float;
uniform vec3 uColor;
out vec4 fragColor;
void main(){ fragColor = vec4(uColor, 1.0); }
]]
-- the last pass: the finished frame toward black, and toward the flat shapes where they are
SL.COMP_VS = [[#version 300 es
precision highp float;
in vec3 position;
in vec2 uv;
out vec2 vUv;
void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }
]]
SL.COMP_FS = [[#version 300 es
precision highp float;
in vec2 vUv;
uniform sampler2D tFinal;
uniform sampler2D tSil;
uniform float uE;
out vec4 fragColor;
void main(){
  vec3 c = texture(tFinal, vUv).rgb;
  vec4 s = texture(tSil, vUv);
  vec3 bg = c*(1.0 - uE);
  vec3 fg = mix(c, s.rgb, uE);
  fragColor = vec4(mix(bg, fg, s.a), 1.0);
}
]]

function SL.add_programs(lib)
  rawset(lib, 'sil.flat|sil|2|-', { vs = VS, fs = FS })
  rawset(lib, 'sil.flat|sil|2|i', { vs = VS_I, fs = FS })
  rawset(lib, 'sil.comp|post|0|-', { vs = SL.COMP_VS, fs = SL.COMP_FS })
end

function SL.create(R)
  local rt = RD.RenderTarget.new(R.W, R.H, { type = 'byte', min_filter = 'nearest', mag_filter = 'nearest' })
  local function flat() return MAT.ShaderMaterial.new({ name = 'sil.flat', uniforms = { uColor = { value = Vector3.new(1, 1, 1) } }, side = MAT.DoubleSide }) end
  local mats = { egg = flat(), lich = flat() }
  local S = { e = 0, style = 1, rt = rt, texture = rt.texture }
  local function collect(o, out)
    if o.visible == false then return end
    if o.is_mesh then out[#out + 1] = o end
    for _, c in ipairs(o.children or {}) do collect(c, out) end
  end
  local list = { egg = {}, lich = {} }
  -- subjects() -> { egg = { roots }, lich = { roots } }, asked each frame (the coiled snakes change)
  function S.render(renderer, camera, subjects)
    local st = SL.STYLES[S.style]
    mats.egg.uniforms.uColor.value:set(st.egg[1], st.egg[2], st.egg[3])
    mats.lich.uniforms.uColor.value:set(st.lich[1], st.lich[2], st.lich[3])
    local prev = renderer:get_render_target()
    renderer:set_render_target(rt)
    renderer:set_clear_color(0x000000, 0)
    renderer:clear()
    renderer.cur_prog, renderer.cur_mat_id = nil, nil
    for _, who in ipairs({ 'egg', 'lich' }) do
      local out = list[who]
      for k = #out, 1, -1 do out[k] = nil end
      for _, root in ipairs(subjects[who]) do collect(root, out) end
      for _, m in ipairs(out) do renderer:render_object(camera, 'sil', m, m.geometry, mats[who], nil, nil, 'sil') end
    end
    renderer:set_render_target(prev)
  end
  return S
end

return SL
