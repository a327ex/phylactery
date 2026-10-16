--[[
  prism.lua -- the ending's telekinesis as glass you can see (2026-10-16, Phylactery 19). Owner, on round 88's warped air:
  "I also didn't see the telekinetic visual, I think here it can be more prismatic and lens transparent because the
  background is all black." Warped air shows only by bending what is behind it, and in the ending everything behind it is
  dimmed to black (silhouette.lua). So the force he brings down is also drawn as ribbons of clear glass, like the lens's:
  thin spectral rims, a faint rainbow through them, a glint running along, and inside them the world as it is, undimmed
  and bent (the last pass, sil.comp, shows the finished frame through them by their `a`).

  Each ribbon rides a warped-air streak (slam.lua hands both the same points): a camera-facing strip `w` wide, drawn
  into its own target after the frame is finished (post.lua: R.prism), hidden behind what is nearer (the world's depth).
  No draws: its phases come from the caller.
]]
local T = require('port.three.core')
local MAT = require('port.three.materials')
local TM = require('port.three.math')
local Vector2 = TM.Vector2
local max, min = math.max, math.min

local PR = {}
PR.N = 96                     -- ribbons at most
PR.GAIN = 0.6                 -- the rims' light (the last pass: display values)
PR.REVEAL = 0.55              -- how much of the undimmed world shows through them

local VS = [[#version 300 es
precision highp float;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform vec2 uRes;
uniform float uProj;
in vec3 position;
in vec3 aPrev;
in vec3 aNext;
in float aSide;
in float aU;
in vec4 aP;
out float vSide;
out float vU;
out float vA;
out float vPh;
out float vTp;
void main(){
  mat4 PV = projectionMatrix*viewMatrix;
  vec4 c = PV*vec4(position, 1.0), cp = PV*vec4(aPrev, 1.0), cn = PV*vec4(aNext, 1.0);
  vec2 d = (cn.xy/max(cn.w, 1e-3) - cp.xy/max(cp.w, 1e-3))*uRes;
  d = length(d) > 1e-4 ? normalize(d) : vec2(1.0, 0.0);
  vec2 n = vec2(-d.y, d.x);
  float px = max(4.0, aP.x*uProj/max(c.w, 0.05));
  c.xy += n*aSide*px*0.5*2.0/uRes*c.w;
  gl_Position = c;
  vSide = aSide; vU = aU; vA = aP.y; vPh = aP.z; vTp = aP.w;
}
]]
local FS = [[#version 300 es
precision highp float;
uniform vec2 uRes;
uniform float uTime, uGain, uReveal;
uniform sampler2D tDepth;
in float vSide;
in float vU;
in float vA;
in float vPh;
in float vTp;
out vec4 fragColor;
vec3 spectrum(float h){ return 0.5 + 0.5*cos(6.2831853*(h + vec3(0.0, 0.33, 0.67))); }
void main(){
  if (vA <= 0.0) discard;
  if (gl_FragCoord.z > texture(tDepth, gl_FragCoord.xy/uRes).x + 1e-6) discard;
  float x = vSide, ax = abs(x);
  // (vTp 1: a falling streak, brightest at its head (vU 1), fading along its length; 0: even, both ends eased)
  float env = mix(smoothstep(0.0, 0.16, vU)*smoothstep(1.0, 0.72, vU), smoothstep(0.0, 0.9, vU)*smoothstep(1.0, 0.95, vU), vTp);
  // the glass: clear inside, its two edges catching the light, split into colours across them
  float rr = (ax - 0.84)/0.1;
  float rim = exp(-rr*rr);
  float body = exp(-x*x*3.0);
  float h = 0.18*x + 0.22*vU + 0.1*sin(vU*9.0 - uTime*6.0 + vPh) + vPh*0.16;
  vec3 col = mix(vec3(1.0), spectrum(h), 0.7)*rim*0.85 + spectrum(h + 0.5)*body*0.06;
  // a glint running down it
  float gx = (x - 0.35)/0.22;
  float g = pow(max(0.0, sin(vU*10.0 - uTime*18.0 + vPh*3.0)), 18.0)*exp(-gx*gx);
  col += vec3(1.0, 0.97, 0.92)*g*0.9;
  float k = vA*env;
  fragColor = vec4(col*k*uGain, (body*0.8 + rim*0.4)*k*uReveal);
}
]]

function PR.add_programs(lib)
  rawset(lib, 'prism.ribbons|prism|2|-', { vs = VS, fs = FS })
end

function PR.create(R, K)
  local N = PR.N
  local CV = N*K*2
  local idx = {}
  for s = 0, N - 1 do for k = 0, K - 2 do
    local a = (s*K + k)*2
    local o = #idx
    idx[o + 1], idx[o + 2], idx[o + 3], idx[o + 4], idx[o + 5], idx[o + 6] = a, a + 1, a + 3, a, a + 3, a + 2
  end end
  local posA, prvA, nxtA = T.float_attr(CV, 3), T.float_attr(CV, 3), T.float_attr(CV, 3)
  local sideA, alongA, prmA = T.float_attr(CV, 1), T.float_attr(CV, 1), T.float_attr(CV, 4)
  local pos, prv, nxt, prm = posA.array, prvA.array, nxtA.array, prmA.array
  for s = 0, N - 1 do for k = 0, K - 1 do for e = 0, 1 do
    local v = (s*K + k)*2 + e
    sideA.array[v + 1] = e == 1 and 1 or -1; alongA.array[v + 1] = k/(K - 1)
  end end end
  local g = T.BufferGeometry.new()
  g:set_attribute('position', posA); g:set_attribute('aPrev', prvA); g:set_attribute('aNext', nxtA)
  g:set_attribute('aSide', sideA); g:set_attribute('aU', alongA); g:set_attribute('aP', prmA)
  g:set_index(idx)
  local UN = { uRes = { value = Vector2.new(R.W, R.H) }, uProj = { value = 400 }, uTime = { value = 0 }, uGain = { value = PR.GAIN },
    uReveal = { value = PR.REVEAL }, tDepth = { value = R.targets.rt_world.depth_texture } }
  local mat = MAT.ShaderMaterial.new({ name = 'prism.ribbons', uniforms = UN, transparent = true, depth_write = false, depth_test = false, side = MAT.DoubleSide,
    blending = MAT.CustomBlending, blend_src = MAT.OneFactor, blend_dst = MAT.OneFactor, blend_src_alpha = MAT.OneFactor, blend_dst_alpha = MAT.OneFactor,
    blend_equation = MAT.AddEquation })
  local mesh = T.Mesh.new(g, mat); mesh.frustum_culled = false; mesh.visible = false
  local scene = T.Scene.new(); scene.program_scene = 'prism'
  scene:add(mesh)

  local RB = {}
  for i = 1, N do RB[i] = { on = false, pts = nil, w = 0.2, a = 0, ph = 0, written_off = true } end
  local pr = { scene = scene, U = UN }
  -- a ribbon on `pts` (K points the caller moves), `w` m wide, phase `ph`, taper `tp` (1: a streak, brightest at its last
  -- point); its `a` the caller fades
  function pr.ribbon(pts, w, ph, tp)
    for _, r in ipairs(RB) do
      if not r.on then r.on = true; r.pts = pts; r.w = w; r.a = 0; r.ph = ph or 0; r.tp = tp or 0; return r end
    end
    return nil
  end
  function pr.release(r) if r then r.on = false; r.a = 0 end end
  local active = false
  function pr.update(t)
    UN.uTime.value = t
    local dirty, any = false, false
    for i = 0, N - 1 do
      local r = RB[i + 1]
      if r.on or not r.written_off then
        dirty = true
        r.written_off = not r.on
        local a = r.on and r.a or 0
        if r.on then any = any or a > 0 end
        local sp = r.pts
        for k = 0, K - 1 do
          local p = sp and sp[k + 1]
          local pa, pb = sp and sp[max(0, k - 1) + 1], sp and sp[min(K - 1, k + 1) + 1]
          for e = 0, 1 do
            local v = (i*K + k)*2 + e
            local v3, v4 = v*3, v*4
            if p then
              pos[v3 + 1], pos[v3 + 2], pos[v3 + 3] = p.x, p.y, p.z
              prv[v3 + 1], prv[v3 + 2], prv[v3 + 3] = pa.x, pa.y, pa.z
              nxt[v3 + 1], nxt[v3 + 2], nxt[v3 + 3] = pb.x, pb.y, pb.z
            end
            prm[v4 + 1], prm[v4 + 2], prm[v4 + 3], prm[v4 + 4] = r.w, a, r.ph, r.tp or 0
          end
        end
      end
    end
    if dirty then posA.needs_update = true; prvA.needs_update = true; nxtA.needs_update = true; prmA.needs_update = true end
    mesh.visible = any
    active = any
  end
  function pr.active() return active end
  function pr.set_camera(cam, H) UN.uProj.value = cam.projection_matrix.elements[6]*H*0.5 end
  return pr
end

return PR
