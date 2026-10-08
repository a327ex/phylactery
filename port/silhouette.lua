--[[
  silhouette.lua -- round 57 (owner, 2026-10-07: "we need some kind of shader or effect where the only the egg and
  lich are visible but they become not textured, like flat colors, so the final shot is darkness + two
  sillouettes"). The egg (with the snakes coiled on it, later the gore of their burst) and the lich (with his mask) are
  drawn a second time in one flat colour into a target of their own with its own depth; post.lua's last pass
  (sil.comp) then takes the frame toward darkness and, where they are, toward that colour, by S.e (0 = the game as it
  is, 1 = only the shapes). Programs of its own (GLSL here), added to three.js's library under their keys.
  Round 58: one colour, pale (owner: "pale (my choice)"); the hatch (S.hatch_t, seconds since it began): the shell cut
  along a zig-zag crack, its cap lifting, tumbling off, and a pale flood from the opening filling the screen.
  Round 59 (owner: "we can remove the flat colors, keep everything textured but just dim the background, or blur it,
  something to that effect"): the shapes are only a mask now: where they are the frame stays as it is, textured and
  lit; elsewhere it goes dim and blurred (S.bg: SL.BGS), by S.e. The real egg cracks too: its program is patched
  (SL.patch_egg) to cut along the same crack, and the cap is a real piece of shell (the game's, placed by cap_matrix).
]]
local MAT = require('port.three.materials')
local T = require('port.three.core')
local RD = require('port.three.renderer')
local TM = require('port.three.math')
local Vector3, Vector2, Matrix4 = TM.Vector3, TM.Vector2, TM.Matrix4
local max, min, exp = math.max, math.min, math.exp

local SL = {}
SL.PALE = { 0.90, 0.86, 0.78 }               -- sRGB, as it shows
-- the crack, in the shell's own space (its centre at 0, 0.8 m tall): a zig-zag `n` teeth round, `a` high, at `y`
SL.CRACK = { y = 0.08, a = 0.045, n = 7 }
-- the hatch: a crack opens (the cap rises `open` m over `open_t` s), then the cap pops (up at `v` m/s against `g`,
-- turning `spin` rad/s, drifting `drift` m/s), and from `flood_at` s the light from the opening grows to fill the
-- screen in `flood_t` s (radius in screen heights)
SL.HATCH = { open = 0.025, open_t = 0.3, v = 2.4, g = 6.5, spin = 1.8, drift = 0.35, flood_at = 0.45, flood_t = 1.8, flood_r = 2.4 }
-- the background (UP / DOWN in the sequence): how dark it goes (its light times `dim`) and how blurred (0..1)
SL.BGS = {
  { name = 'DIM AND BLURRED', dim = 0.22, blur = 1.0 },
  { name = 'DIM', dim = 0.18, blur = 0.0 },
  { name = 'BLURRED', dim = 0.75, blur = 1.0 },
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
uniform float uAlpha;
out vec4 fragColor;
void main(){ fragColor = vec4(uColor, uAlpha); }
]]
-- the shell, cut along the crack: uClip 1 keeps what is below it, 2 what is above
local VS_CLIP = [[#version 300 es
precision highp float;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
in vec3 position;
out vec3 vP;
void main(){ vP = position; gl_Position = projectionMatrix*modelViewMatrix*vec4(position, 1.0); }
]]
local FS_CLIP = [[#version 300 es
precision highp float;
uniform vec3 uColor;
uniform float uClip, uCrackY, uCrackA, uCrackN;
in vec3 vP;
out vec4 fragColor;
void main(){
  float th = atan(vP.z, vP.x);
  float zz = abs(fract(th*uCrackN/6.2831853)*2.0 - 1.0)*2.0 - 1.0;
  float yc = uCrackY + uCrackA*zz;
  if (uClip > 1.5 ? vP.y < yc : vP.y > yc) discard;
  fragColor = vec4(uColor, 1.0);
}
]]
-- the real egg's program (cave.egg), patched to cut along the same crack (uClip 0: whole); once cut its inside is
-- the light (uInner, linear HDR) that then floods out
local EGG_DECL = 'varying vec3 vEggP;\nuniform float uClip, uCrackY, uCrackA, uCrackN;\nuniform vec3 uInner;\n'
function SL.patch_egg(vs, fs)
  local function sub(src, a, b)
    local i, j = src:find(a, 1, true)
    assert(i, 'silhouette: the egg program moved (' .. a .. ')')
    return src:sub(1, i - 1) .. b .. src:sub(j + 1)
  end
  vs = sub(vs, 'vec3 transformed = vec3( position );', 'vec3 transformed = vec3( position ); vEggP = position;')
  vs = sub(vs, 'void main() {', 'varying vec3 vEggP;\nvoid main() {')
  fs = sub(fs, 'void main() {', EGG_DECL .. [[void main() {
  if (uClip > 0.5 && !gl_FrontFacing) { gl_FragColor = vec4(uInner, 1.0); return; }
  if (uClip > 0.5) {
    float th = atan(vEggP.z, vEggP.x);
    float zz = abs(fract(th*uCrackN/6.2831853)*2.0 - 1.0)*2.0 - 1.0;
    float yc = uCrackY + uCrackA*zz;
    if (uClip > 1.5 ? vEggP.y < yc : vEggP.y > yc) discard;
  }]])
  return vs, fs
end
-- the last pass: the finished frame toward black, and toward the flat shapes where they are; the hatch's flood
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
uniform sampler2D tBlur;
uniform float uE, uFloodR, uAspect, uDim, uBlur;
uniform vec2 uFloodC;
uniform vec3 uFloodCol;
out vec4 fragColor;
void main(){
  vec3 c = texture(tFinal, vUv).rgb;
  vec4 s = texture(tSil, vUv);
  vec3 b = texture(tBlur, vUv).rgb;
  vec3 bg = mix(c, b, uBlur*uE)*mix(1.0, uDim, uE);
  vec3 o = mix(bg, c, s.a);
  if (uFloodR > 0.0) {
    float d = length((vUv - uFloodC)*vec2(uAspect, 1.0));
    o = mix(o, uFloodCol, 1.0 - smoothstep(uFloodR*0.8, uFloodR, d));
  }
  fragColor = vec4(o, 1.0);
}
]]

function SL.add_programs(lib)
  rawset(lib, 'sil.flat|sil|2|-', { vs = VS, fs = FS })
  rawset(lib, 'sil.flat|sil|2|i', { vs = VS_I, fs = FS })
  rawset(lib, 'sil.clip|sil|2|-', { vs = VS_CLIP, fs = FS_CLIP })
  rawset(lib, 'sil.comp|post|0|-', { vs = SL.COMP_VS, fs = SL.COMP_FS })
end

function SL.create(R)
  local rt = RD.RenderTarget.new(R.W, R.H, { type = 'byte', min_filter = 'nearest', mag_filter = 'nearest' })
  local P = SL.PALE
  local flat = MAT.ShaderMaterial.new({ name = 'sil.flat', uniforms = { uColor = { value = Vector3.new(P[1], P[2], P[3]) }, uAlpha = { value = 1 } }, side = MAT.DoubleSide })
  local C = SL.CRACK
  local function clip(which)
    return MAT.ShaderMaterial.new({ name = 'sil.clip', side = MAT.DoubleSide, uniforms = { uColor = { value = Vector3.new(P[1], P[2], P[3]) },
      uClip = { value = which }, uCrackY = { value = C.y }, uCrackA = { value = C.a }, uCrackN = { value = C.n } } })
  end
  local below, above = clip(1), clip(2)
  -- the snakes' burst (round 58): pale, then fading into the dark (S.gore_fade) so the egg is left alone
  local gore_mat = MAT.ShaderMaterial.new({ name = 'sil.flat', uniforms = { uColor = { value = Vector3.new(P[1], P[2], P[3]) }, uAlpha = { value = 1 } }, side = MAT.DoubleSide })
  local S = { e = 0, bg = 1, BGS = SL.BGS, gore_fade = 1, rt = rt, texture = rt.texture, hatch_t = nil, flood_r = 0, flood_c = Vector2.new(0.5, 0.5), flood_col = Vector3.new(P[1], P[2], P[3]) }
  local cap = nil                                   -- the shell's top half once it hatches (its geometry, our matrix)
  local CAP, MA, MB, AXZ, Q = Matrix4.new(), Matrix4.new(), Matrix4.new(), Vector3.new(0, 0, 1), Vector3.new()
  local function collect(o, out)
    if o.visible == false then return end
    if o.is_mesh then out[#out + 1] = o end
    for _, c in ipairs(o.children or {}) do collect(c, out) end
  end
  local list = {}
  -- the cap's place in the shell's space at hatch time t
  local function cap_matrix(t)
    local H = SL.HATCH
    local lift, ang, dx = H.open*min(1, t/H.open_t), 0, 0
    local tp = t - H.open_t
    if tp > 0 then lift = lift + H.v*tp - 0.5*H.g*tp*tp; ang = H.spin*tp; dx = H.drift*tp end
    CAP:make_translation(dx, lift + C.y, 0)
    CAP:multiply(MA:make_rotation_axis(AXZ, -ang))
    CAP:multiply(MB:make_translation(0, -C.y, 0))
    return CAP
  end
  S.cap_matrix = cap_matrix
  -- subjects() -> { egg = { roots }, lich = { roots }, shell = the egg's shell mesh }, asked each frame
  function S.render(renderer, camera, subjects)
    local prev = renderer:get_render_target()
    renderer:set_render_target(rt)
    renderer:set_clear_color(0x000000, 0)
    renderer:clear()
    renderer.cur_prog, renderer.cur_mat_id = nil, nil
    for k = #list, 1, -1 do list[k] = nil end
    for _, root in ipairs(subjects.egg) do collect(root, list) end
    for _, root in ipairs(subjects.lich) do collect(root, list) end
    local shell = subjects.shell
    local hatching = S.hatch_t ~= nil and shell ~= nil
    for _, m in ipairs(list) do
      if hatching and m == shell then renderer:render_object(camera, 'sil', m, m.geometry, below, nil, nil, 'sil')
      else renderer:render_object(camera, 'sil', m, m.geometry, flat, nil, nil, 'sil') end
    end
    if subjects.gore and S.gore_fade > 0 then
      local f = S.gore_fade
      gore_mat.uniforms.uAlpha.value = f
      for _, m in ipairs(subjects.gore) do if m.visible ~= false then renderer:render_object(camera, 'sil', m, m.geometry, gore_mat, nil, nil, 'sil') end end
    end
    S.flood_r = 0
    if hatching then
      if not cap then cap = T.Mesh.new(shell.geometry, above) end
      shell:update_world_matrix(true, false)
      cap.matrix_world:multiply_matrices(shell.matrix_world, cap_matrix(S.hatch_t))
      renderer:render_object(camera, 'sil', cap, cap.geometry, above, nil, nil, 'sil')
      -- the light from the opening
      local H = SL.HATCH
      local u = (S.hatch_t - H.flood_at)/H.flood_t
      if u > 0 then
        Q:set(0, C.y, 0):apply_matrix4(shell.matrix_world):project(camera)
        S.flood_c:set(Q.x*0.5 + 0.5, Q.y*0.5 + 0.5)
        S.flood_r = H.flood_r*min(1, u)^2
      end
    end
    renderer:set_render_target(prev)
  end
  return S
end

return SL
