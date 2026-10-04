--[[
  orbmarks.lua -- round 45 (owner, 2026-10-04: "Orbs: they need some simple markings all over them,
  like lines that follow through in different ways. These are the orbs from Part 2."). Lines drawn
  on each glass ball that run all the way round it, each ball its own way: two great circles
  crossing; a spiral from pole to pole; one wavy seam (a tennis ball's); three parallel rings; a
  wave crossed by a circle. Seen on the near face and, through the glass, on the far one.

  Done in the tracer itself (item_orbs.js's shader, both the world's and the model viewer's): the
  program's source is patched as it loads (boot.lua), the ball's index comes with each draw
  (items.lua trace_hook), the finish is MARK.style (F7 cycles it):
    ETCHED   frosted into the glass: pale, catching the light
    INKED    cut and filled dark
    GLOWING  faintly lit from within, the leakage's sea-glass colour
]]
local MK = {}
MK.STYLES = { 'ETCHED', 'INKED', 'GLOWING', 'NONE' }
MK.style = 0

local DECL = [[
uniform float uMark, uMarkStyle;
float mk_band(float d, float w){ float f = fwidth(d) + 1e-4; return 1.0 - smoothstep(w - f, w + f, abs(d)); }
float mk_wave(vec3 P, vec3 n, vec3 ref, float amp, float k){
  vec3 a = normalize(cross(n, ref)); vec3 b = cross(n, a);
  float ph = atan(dot(P, b), dot(P, a));
  return dot(P, n) - amp*sin(k*ph);
}
float mk(vec3 P){
  if (uMarkStyle > 2.5) return 0.0;
  int k = int(uMark + 0.5);
  float w = 0.055;
  if (k == 0) return max(mk_band(dot(P, normalize(vec3(0.3, 1.0, 0.2))), w), mk_band(dot(P, normalize(vec3(1.0, -0.25, 0.6))), w));
  if (k == 1) {
    float ph = atan(P.z, P.x), th = asin(clamp(P.y, -1.0, 1.0));
    float u = th*3.0/3.14159265 - ph/6.2831853;
    return mk_band((u - floor(u + 0.5))*3.14159265/3.0, w)*smoothstep(0.985, 0.93, abs(P.y));
  }
  if (k == 2) return mk_band(mk_wave(P, normalize(vec3(0.2, 1.0, -0.3)), vec3(1.0, 0.0, 0.0), 0.45, 2.0), w);
  if (k == 3) { float h = dot(P, normalize(vec3(0.5, 1.0, 0.1))); return max(max(mk_band(h + 0.56, w), mk_band(h, w)), mk_band(h - 0.56, w)); }
  return max(mk_band(mk_wave(P, normalize(vec3(-0.4, 1.0, 0.5)), vec3(0.0, 0.0, 1.0), 0.3, 3.0), w), mk_band(dot(P, normalize(vec3(1.0, 0.2, -0.3))), w));
}
vec3 mk_frost(vec3 N){
  vec3 nw = normalize(uToWorld*N);
  return env_w(N)*0.75 + vec3(0.045, 0.045, 0.05) + uSunCol*0.018*max(dot(nw, uSunDir), 0.0)*uLit;
}
const vec3 MK_GLOW = vec3(0.30, 0.95, 0.80);
]]

-- the patch: after env_w (mk_frost uses it), the far side's lines inside through(), the near
-- side's in main()
function MK.patch(fs)
  local function sub(a, b)
    local i, j = fs:find(a, 1, true)
    assert(i, 'orbmarks: the orb shader moved (' .. a:sub(1, 40) .. ')')
    fs = fs:sub(1, i - 1) .. b .. fs:sub(j + 1)
  end
  sub('float schlick(float c, float n)', DECL .. '\nfloat schlick(float c, float n)')
  sub([[    p += d*t;
    thr *= exp(-uAbsorb[ch]*t);]], [[    p += d*t;
    thr *= exp(-uAbsorb[ch]*t);
    {
      float mb = mk(normalize(p));
      if (mb > 0.0) {
        if (uMarkStyle < 0.5) { acc += thr*mb*0.4*mk_frost(normalize(p))[ch]; thr *= 1.0 - 0.7*mb; }
        else if (uMarkStyle < 1.5) { thr *= 1.0 - 0.85*mb; }
        else { acc += thr*mb*0.5*MK_GLOW[ch]; }
      }
    }]])
  sub([[  col += (1.0 - F)*inside;]], [[  col += (1.0 - F)*inside;
  {
    float m = mk(P);
    if (uMarkStyle < 0.5) col = mix(col, mk_frost(P), m*0.85);
    else if (uMarkStyle < 1.5) col *= 1.0 - 0.88*m;
    else col += MK_GLOW*m*0.7;
  }]])
  return fs
end

function MK.patch_for(key)
  if key == 'item.orbs|world|0|-' or key == 'item.orbs|inspect|0|-' then return MK.patch end
  return nil
end

function MK.set_style(i)
  local n = #MK.STYLES
  MK.style = ((i % n) + n) % n
  return MK.STYLES[MK.style + 1]
end

return MK
