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
  (SL.patch_egg) to cut along the same crack, and the cap is a real piece of shell.
  Round 61 (owner, 2026-10-08: "You can remove the white circle that spawns at the end of the egg breaking. The egg
  breaking should be a physics object that breaks and collides with the floor"): no flood; the shell breaks along a
  band round the crack (crack_lo .. crack_hi, `gap` wide either side, uneven) that shatters into shards, the cap
  above it and the bottom below it each a body of their own (port/eggphys.lua); uClip 3 = a loose piece of shell (no
  cut, its inside on its back faces). The cap's mask is drawn where its body is (subjects.cap).
]]
local MAT = require('port.three.materials')
local RD = require('port.three.renderer')
local TM = require('port.three.math')
local Vector3 = TM.Vector3
local abs, floor = math.abs, math.floor

local SL = {}
SL.PALE = { 0.90, 0.86, 0.78 }               -- sRGB, as it shows
-- the crack, in the shell's own space (its centre at 0, 0.8 m tall): round 60 (owner: "the way it hatches should be
-- more irregular, it's currently too neat, like the edges and so on"): uneven jags (four saw waves of 5, 11, 19, 37
-- teeth round it at their own phases, summed) `a` high about `y`, the whole line slanted `tilt` (CRACK_GLSL / crack_y)
-- round 61: once open, the band from crack_lo to crack_hi (`gap` either side of the crack, 0.5-1.5 times that, unevenly)
-- is the shards'; the bottom keeps what is below it, the cap what is above
SL.CRACK = { y = 0.08, a = 0.05, tilt = 0.05, rim = 0.28, gap = 0.022 }
-- the hatch: a glowing crack spreads round the shell from the side facing the camera for `crack_t` s; then it breaks
-- (round 61: port/eggphys.lua)
SL.HATCH = { crack_t = 0.8 }
-- the crack's height round the shell, and the band's edges (GLSL; needs uCrackY, uCrackA, uCrackGap declared)
local CRACK_GLSL = [[
float ck_tri(float x){ return abs(fract(x)*2.0 - 1.0)*2.0 - 1.0; }
float crack_y(vec3 p){
  float t = atan(p.z, p.x)/6.2831853;
  float j = 0.5*ck_tri(t*5.0 + 0.13) + 0.3*ck_tri(t*11.0 + 0.71) + 0.2*ck_tri(t*19.0 + 0.37) + 0.12*ck_tri(t*37.0 + 0.9);
  return uCrackY + uCrackA*j + 0.05*cos(t*6.2831853 - 1.1);
}
float crack_lo(vec3 p){ float t = atan(p.z, p.x)/6.2831853; return crack_y(p) - uCrackGap*(1.0 + 0.5*ck_tri(t*7.0 + 0.21)); }
float crack_hi(vec3 p){ float t = atan(p.z, p.x)/6.2831853; return crack_y(p) + uCrackGap*(1.0 + 0.5*ck_tri(t*9.0 + 0.57)); }
]]
-- the same in Lua (where the shards break from)
function SL.crack_y(th)
  local C = SL.CRACK
  local t = th/(2*math.pi)
  local function tri(x) return math.abs((x - math.floor(x))*2 - 1)*2 - 1 end
  local j = 0.5*tri(t*5 + 0.13) + 0.3*tri(t*11 + 0.71) + 0.2*tri(t*19 + 0.37) + 0.12*tri(t*37 + 0.9)
  return C.y + C.a*j + C.tilt*math.cos(t*2*math.pi - 1.1)
end
local function tri(x) return abs((x - floor(x))*2 - 1)*2 - 1 end
function SL.crack_lo(th, gap) return SL.crack_y(th) - gap*(1 + 0.5*tri(th/(2*math.pi)*7 + 0.21)) end
function SL.crack_hi(th, gap) return SL.crack_y(th) + gap*(1 + 0.5*tri(th/(2*math.pi)*9 + 0.57)) end
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
-- the shell, cut along the crack: uClip 1 keeps what is below it, 2 what is above (round 61: below / above the band)
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
uniform float uClip, uCrackY, uCrackA, uCrackGap;
in vec3 vP;
out vec4 fragColor;
]] .. CRACK_GLSL .. [[
void main(){
  if (uClip > 1.5 ? vP.y < crack_hi(vP) : vP.y > crack_lo(vP)) discard;
  fragColor = vec4(uColor, 1.0);
}
]]
-- the real egg's program (cave.egg), patched to cut along the same crack (uClip 0: whole); once cut its inside is
-- the light (uInner, linear HDR); before, the crack shows as a glowing line on the shell spreading
-- round it (uCrackGrow 0..1, from the angle uCrackStart, in turns). Round 61: uClip 1 / 2 cut below / above the band
-- (uCrackGap); 3 = a loose piece (a shard: no cut, its inside on its back faces)
local EGG_DECL = 'varying vec3 vEggP;\nuniform float uClip, uCrackY, uCrackA, uCrackGap, uCrackGrow, uCrackStart;\nuniform vec3 uInner;\n' .. CRACK_GLSL
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
  if (uClip > 0.5 && uClip < 2.5) { if (uClip > 1.5 ? vEggP.y < crack_hi(vEggP) : vEggP.y > crack_lo(vEggP)) discard; }
  else if (uClip < 0.5 && uCrackGrow > 0.0) {
    float yc = crack_y(vEggP);
    float da = abs(fract(atan(vEggP.z, vEggP.x)/6.2831853 - uCrackStart + 0.5) - 0.5);
    if (da < 0.5*uCrackGrow && abs(vEggP.y - yc) < 0.007) { gl_FragColor = vec4(uInner, 1.0); return; }
  }]])
  return vs, fs
end
-- the last pass: the finished frame dimmed and blurred, except where the shapes are
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
uniform float uE, uDim, uBlur;
out vec4 fragColor;
void main(){
  vec3 c = texture(tFinal, vUv).rgb;
  vec4 s = texture(tSil, vUv);
  vec3 b = texture(tBlur, vUv).rgb;
  vec3 bg = mix(c, b, uBlur*uE)*mix(1.0, uDim, uE);
  fragColor = vec4(mix(bg, c, s.a), 1.0);
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
      uClip = { value = which }, uCrackY = { value = C.y }, uCrackA = { value = C.a }, uCrackGap = { value = 0 } } })
  end
  local below, above = clip(1), clip(2)
  -- the snakes' burst (round 58): pale, then fading into the dark (S.gore_fade) so the egg is left alone
  local gore_mat = MAT.ShaderMaterial.new({ name = 'sil.flat', uniforms = { uColor = { value = Vector3.new(P[1], P[2], P[3]) }, uAlpha = { value = 1 } }, side = MAT.DoubleSide })
  -- (gap: the band's half width once it is open, round 61)
  local S = { e = 0, bg = 1, BGS = SL.BGS, gore_fade = 1, rt = rt, texture = rt.texture, hatch_t = nil, gap = 0 }
  local function collect(o, out)
    if o.visible == false then return end
    if o.is_mesh then out[#out + 1] = o end
    for _, c in ipairs(o.children or {}) do collect(c, out) end
  end
  local list = {}
  -- subjects() -> { egg = { roots }, lich = { roots }, shell = the egg's shell mesh, cap = its cap once open }, asked
  -- each frame (the cap is one of the egg's roots' meshes: drawn cut above the band)
  function S.render(renderer, camera, subjects)
    local prev = renderer:get_render_target()
    renderer:set_render_target(rt)
    renderer:set_clear_color(0x000000, 0)
    renderer:clear()
    renderer.cur_prog, renderer.cur_mat_id = nil, nil
    for k = #list, 1, -1 do list[k] = nil end
    for _, root in ipairs(subjects.egg) do collect(root, list) end
    for _, root in ipairs(subjects.lich) do collect(root, list) end
    local shell, cap = subjects.shell, subjects.cap
    local hatching = S.hatch_t ~= nil and shell ~= nil and S.hatch_t >= SL.HATCH.crack_t     -- (open: cut, the cap off)
    below.uniforms.uCrackGap.value = S.gap; above.uniforms.uCrackGap.value = S.gap
    for _, m in ipairs(list) do
      if hatching and m == shell then renderer:render_object(camera, 'sil', m, m.geometry, below, nil, nil, 'sil')
      elseif m == cap then renderer:render_object(camera, 'sil', m, m.geometry, above, nil, nil, 'sil')
      else renderer:render_object(camera, 'sil', m, m.geometry, flat, nil, nil, 'sil') end
    end
    if subjects.gore and S.gore_fade > 0 then
      local f = S.gore_fade
      gore_mat.uniforms.uAlpha.value = f
      for _, m in ipairs(subjects.gore) do if m.visible ~= false then renderer:render_object(camera, 'sil', m, m.geometry, gore_mat, nil, nil, 'sil') end end
    end
    renderer:set_render_target(prev)
  end
  return S
end

return SL
