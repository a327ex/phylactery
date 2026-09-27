// render.js -- renderer, the 640x360 targets, post-processing and the upscale to the window.
//
// Frame:  world scene  -> rt_world (HalfFloat linear, + depth texture)
//         view scene   -> rt_view  (HalfFloat, alpha = coverage; the viewmodel never clips walls)
//         bright pass  -> rt_bloom (160x90) -> separable blur          (skipped when bloom = 0)
//         final pass   -> rt_final (640x360 8-bit): fog on the world, viewmodel over it, bloom,
//                         exposure, soft shoulder, sRGB encode, grade, flash/hurt, ordered dither +
//                         quantize, HUD canvas composited last (never graded or dithered)
//         upscale      -> canvas, largest 16:9 rect, 'sharp' (integer nearest + 1px blend at the
//                         seams, identical to nearest at integer scales) or 'nearest'
//
// Everything tweakable is on R.params (read every frame). Custom GLSL goes in R.hooks and takes
// effect after R.rebuild(): hooks.decl (uniforms / functions), hooks.world (body of
// `vec3 hook_world(vec3 c, vec3 wpos, float dist, float sky)`, linear, before fog) and
// hooks.grade (body of `vec3 hook_grade(vec3 c, vec2 px)`, display space, before dither).
// Extra uniforms for hooks: put them in R.hook_uniforms before rebuild().
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

export const W = 640, H = 360;

// Merge a rigid group's leaf meshes by material (one draw call per material). Children with
// userData.keep, or with children of their own, are left alone. Returns the new meshes.
export function merge_static(group, cast_shadow = true) {
  const by = new Map();
  for (const c of group.children.slice()) {
    if (!c.isMesh || c.children.length || c.userData.keep) continue;
    c.updateMatrix();
    const g = c.geometry.index ? c.geometry.toNonIndexed() : c.geometry.clone();
    g.applyMatrix4(c.matrix);
    if (!g.attributes.uv) g.setAttribute('uv', new THREE.Float32BufferAttribute(new Float32Array(g.attributes.position.count*2), 2));
    for (const k of Object.keys(g.attributes)) if (!['position', 'normal', 'uv'].includes(k)) g.deleteAttribute(k);
    if (!by.has(c.material)) by.set(c.material, []);
    by.get(c.material).push(g);
    group.remove(c);
  }
  const out = [];
  for (const [mat, geos] of by) {
    const m = new THREE.Mesh(mergeGeometries(geos, false), mat);
    m.castShadow = cast_shadow;
    group.add(m);
    out.push(m);
    for (const g of geos) g.dispose();
  }
  return out;
}

const FULL_VS = `varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`;

function fullscreen_triangle() {
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute([-1, -1, 0, 3, -1, 0, -1, 3, 0], 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute([0, 0, 2, 0, 0, 2], 2));
  return g;
}

const COMMON = /* glsl */`
float bayer4(vec2 p){
  ivec2 q = ivec2(mod(p, 4.0));
  int i = q.x + q.y*4;
  float m[16];
  m[0]=0.;m[1]=8.;m[2]=2.;m[3]=10.;m[4]=12.;m[5]=4.;m[6]=14.;m[7]=6.;
  m[8]=3.;m[9]=11.;m[10]=1.;m[11]=9.;m[12]=15.;m[13]=7.;m[14]=13.;m[15]=5.;
  for (int k = 0; k < 16; k++) if (k == i) return (m[k] + 0.5)/16.0;
  return 0.5;
}
vec3 lin_to_srgb(vec3 c){
  c = max(c, 0.0);
  return mix(c*12.92, 1.055*pow(c, vec3(1.0/2.4)) - 0.055, step(0.0031308, c));
}
float luma(vec3 c){ return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
`;

const SKY_GLSL = /* glsl */`
uniform float uSkyOn, uSunSize, uClouds;
uniform vec3 uZenith, uHorizon, uGroundCol, uSunDir, uSunCol, uHalo, uCloudCol, uCloudShade;
float sk_hash(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x*p.y); }
float sk_noise(vec2 p){ vec2 i = floor(p), f = fract(p); f = f*f*(3.0 - 2.0*f);
  return mix(mix(sk_hash(i), sk_hash(i + vec2(1.0, 0.0)), f.x), mix(sk_hash(i + vec2(0.0, 1.0)), sk_hash(i + vec2(1.0, 1.0)), f.x), f.y); }
float sk_fbm(vec2 p){ float s = 0.0, a = 0.5; for (int i = 0; i < 4; i++){ s += a*sk_noise(p); p = p*2.03 + vec2(1.7, 9.2); a *= 0.5; } return s; }
// Pixel clouds on a plane above. cloud_field() runs for every pixel in uniform control flow
// (main calls it before any per-pixel branch) so the screen derivatives of the density and
// the lighting are valid; sky_color() then draws crisp pixel edges and flat lit bands whose
// ordered-dither fringe is capped at about 1-2 px wherever the field is shallow.
float cl_d = -1.0, cl_dw = 0.0, cl_lit = 0.0, cl_lw = 0.0;
void cloud_field(vec3 rd){
  float h = rd.y;
  vec2 q = rd.xz/(max(h, 0.0) + 0.22)*1.25 + vec2(uTime*0.012, uTime*0.005);
  float n = sk_fbm(q) + 0.18*sk_noise(q*0.37 + 3.1);
  float th = 0.78 - uClouds*0.34;
  // toward the horizon the clouds thin by raising the edge threshold (the same outline that
  // scaling the density by s gives), not by flattening the slope, which would widen the fringe
  float s = max(smoothstep(0.02, 0.3, h), 0.05);
  cl_d = (n - th)*14.0 - 0.45*(1.0/s - 1.0);
  vec2 q2 = q + uSunDir.xz*0.22;
  float n2 = sk_fbm(q2) + 0.18*sk_noise(q2*0.37 + 3.1);
  cl_lit = clamp((n - n2)*7.0 + 0.62 - clamp((n - th)*2.0, 0.0, 0.4), 0.0, 1.0);
  cl_dw = fwidth(cl_d);
  cl_lw = fwidth(cl_lit);
}
vec3 sky_color(vec3 rd, vec2 px){
  float h = rd.y;
  vec3 c = mix(uHorizon, uZenith, pow(clamp(h, 0.0, 1.0), 0.6));
  c = mix(c, uGroundCol, smoothstep(0.0, -0.1, h));
  float sd = dot(rd, uSunDir);
  if (h > 0.03 && uClouds > 0.0) {
    // edge: a narrow coverage window around 0.45, narrowed further where the density is
    // shallow on screen so the dithered fringe never spreads into a halftone field
    float cov = clamp(cl_d, 0.0, 1.0);
    float w = min(0.12, cl_dw*1.5);
    if (cov > 0.45 + (bayer4(px) - 0.5)*w) {
      // flat lit bands (0, 1/3, 2/3, 1) with only a narrow dithered seam between them
      float lw = min(0.3, cl_lw*3.0*1.5);
      float lit = floor(cl_lit*3.0 + 0.5 + (bayer4(px + 2.0) - 0.5)*lw)/3.0;
      vec3 cc = mix(uCloudShade, uCloudCol, lit);
      c = mix(c, cc, 0.92);
    }
  }
  c += uHalo*(pow(max(sd, 0.0), 48.0)*0.55 + pow(max(sd, 0.0), 6.0)*0.10);
  if (sd > uSunSize) c = uSunCol;
  else if (sd > uSunSize - 0.00045) c = mix(c, uSunCol, 0.45);
  return c;
}`;

const SHAFT_GLSL = /* glsl */`
uniform float uShaftOn, uShaftDensity, uShaftMax, uShaftPhase, uShaftAmb, uShaftStreak, uShaftRise, uShaftSoft, uShaftTop;
uniform vec3 uShaftCol;
uniform sampler2D uShadowMap;
uniform mat4 uShadowMat;
const vec4 SH_UNPACK = vec4(255.0/256.0, 255.0/65536.0, 255.0/16777216.0, 1.0/16777216.0);
float sh_lit(vec3 p){
  vec4 sc = uShadowMat*vec4(p, 1.0);
  vec3 s = sc.xyz/sc.w;
  if (s.x < 0.0 || s.x > 1.0 || s.y < 0.0 || s.y > 1.0 || s.z > 1.0) return 1.0;
  if (uShaftSoft <= 0.0) return step(s.z - 0.0015, dot(texture2D(uShadowMap, s.xy), SH_UNPACK));
  // lich-survivors: the beam's edge blurs with the distance below the opening (the sun's disc)
  float r = uShaftSoft*max(uShaftTop - p.y, 0.0);
  float l = 0.0;
  for (int i = 0; i < 5; i++) {
    float a = float(i)*1.2566371;
    vec2 o = i == 0 ? vec2(0.0) : vec2(cos(a), sin(a))*r;
    l += step(s.z - 0.0015, dot(texture2D(uShadowMap, s.xy + o), SH_UNPACK));
  }
  return l*0.2;
}
// lich-survivors: streaks across the column (value noise in the plane across the sun's
// direction, so they run along the beam) and a rise in brightness toward the top of the shaft
float sh_streak(vec3 p){
  if (uShaftStreak <= 0.0) return 1.0;
  vec3 a = normalize(cross(uSunDir, vec3(0.0, 0.0, 1.0)));
  vec3 b = cross(uSunDir, a);
  vec2 q = vec2(dot(p, a), dot(p, b));
  float n = sk_noise(q*2.3 + vec2(0.0, uTime*0.02))*0.65 + sk_noise(q*6.1 - vec2(uTime*0.05, 0.0))*0.35;
  float k = mix(1.0, 0.35 + 1.3*n, uShaftStreak);
  return k*mix(1.0, 0.7 + 0.9*clamp(p.y/22.0, 0.0, 1.0), uShaftRise);
}
// in-scattered sunlight along the view ray, occluded by the sun's shadow map
vec3 shafts(vec3 c, vec3 cam, vec3 rd, float dist, vec2 px){
  float L = min(dist, uShaftMax);
  float stepL = L/float(SHAFT_STEPS);
  float j = bayer4(px);
  float lit = 0.0;
  for (int i = 0; i < SHAFT_STEPS; i++) { vec3 sp = cam + rd*(stepL*(float(i) + j)); float l = sh_lit(sp); if (l > 0.0) lit += l*sh_streak(sp); }
  lit /= float(SHAFT_STEPS);
  float mu = max(dot(rd, uSunDir), 0.0);
  float phase = mix(1.0, 0.45 + 2.6*pow(mu, 5.0), uShaftPhase);
  float od = 1.0 - exp(-L*uShaftDensity);
  // where most of the ray is in shadow (under the pergola, in the arcade) the in-scatter is
  // capped low, so looking out of shade toward the sun does not wash the fight to grey
  vec3 add = uShaftCol*(lit*phase + uShaftAmb)*od;
  add = min(add, vec3(mix(0.15, 1.0, lit*lit)));
  return c*(1.0 - od*0.55) + add;
}`;

function final_fs(hooks, steps = 24) {
  return /* glsl */`
precision highp float;
#define SHAFT_STEPS ${steps | 0}
varying vec2 vUv;
uniform sampler2D tWorld, tDepth, tView, tBloom, tHud;
uniform vec2 uRes;
uniform mat4 uProjInv, uCamWorld;
uniform vec3 uFogColor;
uniform float uFogNear, uFogFar, uFogMax, uFogCurve, uFogSky, uFogBaseY, uFogFalloff, uFogHeightMix;
uniform float uBloom, uExposure, uKnee, uContrast, uSaturation, uVignette, uDither, uLevels, uTime, uDitherDark0, uDitherDark1;
uniform vec3 uLift, uGamma, uGain;
uniform vec4 uFlash;
uniform vec3 uHurtColor; uniform float uHurt, uDesat, uHud;
${COMMON}
${SKY_GLSL}
${SHAFT_GLSL}
${hooks.decl || ''}
vec3 hook_world(vec3 c, vec3 wpos, float dist, float sky){ ${hooks.world || 'return c;'} }
vec3 hook_grade(vec3 c, vec2 px){ ${hooks.grade || 'return c;'} }
vec3 shoulder(vec3 c){
  // identity below the knee, smooth roll-off above it: flat colours stay exact
  vec3 over = max(c - uKnee, 0.0);
  float room = 1.0 - uKnee;
  return min(c, vec3(uKnee)) + room*(1.0 - exp(-over/room));
}
void main(){
  vec2 px = floor(vUv*uRes);
  vec2 uv = (px + 0.5)/uRes;
  vec3 world = texture2D(tWorld, uv).rgb;
  float z = texture2D(tDepth, uv).x;
  float sky = step(0.999999, z);
  vec4 vp = uProjInv*vec4(uv*2.0 - 1.0, z*2.0 - 1.0, 1.0);
  vec3 vpos = vp.xyz/vp.w;
  float dist = sky > 0.5 ? 1e4 : length(vpos);
  vec3 wpos = (uCamWorld*vec4(vpos, 1.0)).xyz;
  vec3 cam = uCamWorld[3].xyz;
  vec3 rd = normalize(wpos - cam);
  if (uSkyOn > 0.5 && uClouds > 0.0) cloud_field(rd);    // uniform branch: derivatives stay valid
  if (uSkyOn > 0.5 && sky > 0.5) world += sky_color(rd, px);
  if (uShaftOn > 0.5) world = shafts(world, cam, rd, sky > 0.5 ? uShaftMax*0.6 : dist, px);
  world = hook_world(world, wpos, dist, sky);
  float fog = pow(clamp((dist - uFogNear)/max(uFogFar - uFogNear, 1e-3), 0.0, 1.0), uFogCurve);
  float hfog = clamp(exp(-(wpos.y - uFogBaseY)*uFogFalloff), 0.0, 1.0);
  fog *= mix(1.0, hfog, uFogHeightMix);
  fog = mix(fog*uFogMax, uFogSky, sky);
  world = mix(world, uFogColor, fog);
  vec4 vm = texture2D(tView, uv);
  vec3 c = world*(1.0 - clamp(vm.a, 0.0, 1.0)) + vm.rgb;
  c += texture2D(tBloom, vUv).rgb*uBloom;
  c = shoulder(c*uExposure);
  c = lin_to_srgb(c);
  // grade (display space)
  c = c*uGain + uLift*(1.0 - c);
  c = pow(max(c, 0.0), 1.0/uGamma);
  c = (c - 0.5)*uContrast + 0.5;
  c = mix(vec3(luma(c)), c, uSaturation);
  vec2 q = vUv - 0.5; q.x *= uRes.x/uRes.y;
  float r = length(q);
  c *= 1.0 - uVignette*smoothstep(0.35, 1.05, r);
  c = mix(c, vec3(luma(c)), uDesat);
  c = mix(c, uHurtColor, uHurt*smoothstep(0.42, 1.12, r));
  c = mix(c, uFlash.rgb, uFlash.a);
  c = hook_grade(clamp(c, 0.0, 1.0), px);
  if (uLevels > 1.5) {
    float th = mix(0.5, bayer4(px), uDither*smoothstep(uDitherDark0, uDitherDark1, luma(c)));
    c = floor(clamp(c, 0.0, 1.0)*(uLevels - 1.0) + th)/(uLevels - 1.0);
  }
  vec4 hud = texture2D(tHud, uv);
  c = mix(c, hud.rgb, hud.a*uHud);
  gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}`;
}

const BRIGHT_FS = /* glsl */`
precision highp float;
varying vec2 vUv;
uniform sampler2D tWorld, tView; uniform vec2 uSrc; uniform float uThreshold;
${COMMON}
vec3 at(vec2 uv){ vec3 w = texture2D(tWorld, uv).rgb; vec4 v = texture2D(tView, uv); return w*(1.0 - clamp(v.a,0.0,1.0)) + v.rgb; }
void main(){
  vec2 t = 1.0/uSrc;
  vec3 s = at(vUv + t*vec2(-1.0,-1.0)) + at(vUv + t*vec2(1.0,-1.0)) + at(vUv + t*vec2(-1.0,1.0)) + at(vUv + t*vec2(1.0,1.0));
  s *= 0.25;
  float l = max(max(s.r, s.g), s.b);
  float k = max(l - uThreshold, 0.0)/max(l, 1e-4);
  gl_FragColor = vec4(s*k, 1.0);
}`;

const BLUR_FS = /* glsl */`
precision highp float;
varying vec2 vUv;
uniform sampler2D tSrc; uniform vec2 uDir;
void main(){
  vec3 c = texture2D(tSrc, vUv).rgb*0.2270270270;
  c += texture2D(tSrc, vUv + uDir*1.3846153846).rgb*0.3162162162;
  c += texture2D(tSrc, vUv - uDir*1.3846153846).rgb*0.3162162162;
  c += texture2D(tSrc, vUv + uDir*3.2307692308).rgb*0.0702702703;
  c += texture2D(tSrc, vUv - uDir*3.2307692308).rgb*0.0702702703;
  gl_FragColor = vec4(c, 1.0);
}`;

const UPSCALE_FS = /* glsl */`
precision highp float;
varying vec2 vUv;
uniform sampler2D tSrc; uniform vec2 uRes; uniform vec2 uOut; uniform float uSharp;
void main(){
  vec2 texel = vUv*uRes;
  vec2 base = floor(texel);
  vec2 s = texel - base;
  vec2 prescale = max(floor(uOut/uRes), vec2(1.0));
  vec2 region = 0.5 - 0.5/prescale;
  vec2 cd = s - 0.5;
  vec2 f = (cd - clamp(cd, -region, region))*prescale + 0.5;
  vec2 sharp_uv = (base + f)/uRes;
  vec2 near_uv = (base + 0.5)/uRes;
  gl_FragColor = vec4(texture2D(tSrc, mix(near_uv, sharp_uv, uSharp)).rgb, 1.0);
}`;

export function create_render(parent = document.body) {
  const renderer = new THREE.WebGLRenderer({ antialias: false, alpha: false, stencil: false, powerPreference: 'high-performance', preserveDrawingBuffer: false });
  renderer.setPixelRatio(1);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFShadowMap;         // lich-survivors: the PCF branch is replaced by soft_shadows.js
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  const canvas = renderer.domElement;
  canvas.style.cssText = 'position:fixed;left:0;top:0;width:100vw;height:100vh;display:block;cursor:crosshair';
  parent.appendChild(canvas);

  const rt_opts = { type: THREE.HalfFloatType, minFilter: THREE.NearestFilter, magFilter: THREE.NearestFilter, generateMipmaps: false, depthBuffer: true };
  const rt_world = new THREE.WebGLRenderTarget(W, H, { ...rt_opts, depthTexture: new THREE.DepthTexture(W, H, THREE.UnsignedIntType) });
  rt_world.depthTexture.minFilter = rt_world.depthTexture.magFilter = THREE.NearestFilter;
  const rt_view = new THREE.WebGLRenderTarget(W, H, rt_opts);
  const BW = W/4, BH = H/4;
  const blo = { type: THREE.HalfFloatType, minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter, generateMipmaps: false, depthBuffer: false };
  const rt_bloom_a = new THREE.WebGLRenderTarget(BW, BH, blo);
  const rt_bloom_b = new THREE.WebGLRenderTarget(BW, BH, blo);
  const rt_final = new THREE.WebGLRenderTarget(W, H, { type: THREE.UnsignedByteType, minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter, generateMipmaps: false, depthBuffer: false });

  const world_scene = new THREE.Scene();
  world_scene.background = new THREE.Color(0x9ec3e6);
  const world_camera = new THREE.PerspectiveCamera(68, W/H, 0.05, 250);
  world_camera.rotation.order = 'YXZ';
  const view_scene = new THREE.Scene();
  const view_camera = new THREE.PerspectiveCamera(58, W/H, 0.01, 20);

  // HUD canvas (drawn by hud.js in 640x360 pixel space)
  const hud_canvas = document.createElement('canvas');
  hud_canvas.width = W; hud_canvas.height = H;
  const hud_tex = new THREE.CanvasTexture(hud_canvas);
  hud_tex.minFilter = hud_tex.magFilter = THREE.NearestFilter;
  hud_tex.generateMipmaps = false;
  hud_tex.colorSpace = THREE.NoColorSpace;               // raw display values, composited after encode

  const black = new THREE.DataTexture(new Uint8Array([0, 0, 0, 0]), 1, 1);
  black.needsUpdate = true;

  const params = {
    exposure: 1.0,
    knee: 0.8,                        // soft shoulder starts here (linear); 1 = hard clip
    contrast: 1.04, saturation: 1.06,
    lift: [0.0, 0.0, 0.0], gamma: [1, 1, 1], gain: [1, 1, 1],
    vignette: 0.18,
    fog: { color: new THREE.Color(0xb8cfe0), near: 10, far: 70, max: 0.45, curve: 1.0, sky: 0.0, base_y: 0, falloff: 0.0, height_mix: 0.0 },
    bloom: { strength: 0.45, threshold: 0.95 },
    // ordered dither amount 0..1; quantize levels per channel (0 = off). 0.3 x 64: gradients (sky,
    // sun halo, the sun-to-shade falloff) step in clean bands with a narrow dithered seam between
    // them, and flat shaded plaster stays flat: at 1.0 every pixel between two levels became a
    // visible 2x2 checker, and at 0 the three channels step apart into blotchy hue contours
    dither: 0.3, levels: 64,
    dither_dark: [-1, 0],             // luma range over which the dither fades in (off below the first)
    flash: [1, 1, 1, 0],              // display-space rgba overlay (fx drives it)
    hurt: 0, hurt_color: [0.55, 0.02, 0.02], desat: 0,
    hud: 1,
    upscale: 'sharp',                 // 'sharp' | 'nearest'
    // procedural sky, drawn where the world depth is empty (linear colours; sun_color may be HDR)
    sky: { on: false, zenith: [0.1, 0.3, 0.8], horizon: [0.6, 0.8, 0.95], ground: [0.5, 0.45, 0.4], sun_dir: [0, 1, 0],
      sun_color: [8, 7, 5], sun_size: 0.9988, halo: [1, 0.8, 0.5], clouds: 0.5, cloud_color: [1, 1, 1], cloud_shade: [0.7, 0.75, 0.85] },
    // volumetric sun shafts: march the view ray through the shadow map of `light` (set_shadow_light)
    shafts: { on: false, light: null, color: [1, 0.85, 0.6], density: 0.02, max_dist: 30, steps: 24, phase: 0.5, ambient: 0.1 },
  };
  const hooks = { decl: '', world: '', grade: '' };
  const hook_uniforms = {};

  const tri = fullscreen_triangle();
  const pass_scene = new THREE.Scene();
  const pass_cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const quad = new THREE.Mesh(tri, null);
  quad.frustumCulled = false;
  pass_scene.add(quad);

  const U = {
    tWorld: { value: rt_world.texture }, tDepth: { value: rt_world.depthTexture }, tView: { value: rt_view.texture },
    tBloom: { value: black }, tHud: { value: hud_tex }, uRes: { value: new THREE.Vector2(W, H) },
    uProjInv: { value: new THREE.Matrix4() }, uCamWorld: { value: new THREE.Matrix4() },
    uFogColor: { value: new THREE.Color() }, uFogNear: { value: 0 }, uFogFar: { value: 1 }, uFogMax: { value: 0 },
    uFogCurve: { value: 1 }, uFogSky: { value: 0 }, uFogBaseY: { value: 0 }, uFogFalloff: { value: 0 }, uFogHeightMix: { value: 0 },
    uBloom: { value: 0 }, uExposure: { value: 1 }, uKnee: { value: 0.8 }, uContrast: { value: 1 }, uSaturation: { value: 1 },
    uVignette: { value: 0 }, uDither: { value: 0 }, uLevels: { value: 0 }, uTime: { value: 0 }, uDitherDark0: { value: -1 }, uDitherDark1: { value: 0 },
    uLift: { value: new THREE.Vector3() }, uGamma: { value: new THREE.Vector3(1, 1, 1) }, uGain: { value: new THREE.Vector3(1, 1, 1) },
    uFlash: { value: new THREE.Vector4() }, uHurtColor: { value: new THREE.Vector3() }, uHurt: { value: 0 }, uDesat: { value: 0 }, uHud: { value: 1 },
    uSkyOn: { value: 0 }, uSunSize: { value: 0.9988 }, uClouds: { value: 0 },
    uZenith: { value: new THREE.Vector3() }, uHorizon: { value: new THREE.Vector3() }, uGroundCol: { value: new THREE.Vector3() },
    uSunDir: { value: new THREE.Vector3(0, 1, 0) }, uSunCol: { value: new THREE.Vector3() }, uHalo: { value: new THREE.Vector3() },
    uCloudCol: { value: new THREE.Vector3() }, uCloudShade: { value: new THREE.Vector3() },
    uShaftStreak: { value: 0 }, uShaftRise: { value: 0 }, uShaftSoft: { value: 0 }, uShaftTop: { value: 30 },
    uShaftOn: { value: 0 }, uShaftDensity: { value: 0 }, uShaftMax: { value: 30 }, uShaftPhase: { value: 0.5 }, uShaftAmb: { value: 0 },
    uShaftCol: { value: new THREE.Vector3() }, uShadowMap: { value: black }, uShadowMat: { value: new THREE.Matrix4() },
  };
  const mk = (fs, uniforms) => new THREE.ShaderMaterial({ vertexShader: FULL_VS, fragmentShader: fs, uniforms, depthTest: false, depthWrite: false });
  let final_mat = null;
  const rebuild = () => {
    if (final_mat) final_mat.dispose();
    final_mat = mk(final_fs(hooks, (params.shafts && params.shafts.steps) || 24), Object.assign(U, hook_uniforms));
  };
  rebuild();
  const bright_mat = mk(BRIGHT_FS, { tWorld: U.tWorld, tView: U.tView, uSrc: { value: new THREE.Vector2(W, H) }, uThreshold: { value: 1 } });
  const blur_mat = mk(BLUR_FS, { tSrc: { value: null }, uDir: { value: new THREE.Vector2() } });
  const up_mat = mk(UPSCALE_FS, { tSrc: { value: rt_final.texture }, uRes: { value: new THREE.Vector2(W, H) }, uOut: { value: new THREE.Vector2(W, H) }, uSharp: { value: 1 } });

  const pass = (mat, target) => { quad.material = mat; renderer.setRenderTarget(target); renderer.render(pass_scene, pass_cam); };

  // canvas sizing: drawing buffer in physical pixels, largest 16:9 rect inside it
  const view = { x: 0, y: 0, w: W, h: H, bw: W, bh: H };
  function resize() {
    const dpr = window.devicePixelRatio || 1;
    const bw = Math.max(1, Math.floor(window.innerWidth*dpr)), bh = Math.max(1, Math.floor(window.innerHeight*dpr));
    if (bw !== view.bw || bh !== view.bh || !view.sized) {
      renderer.setSize(bw, bh, false);
      view.bw = bw; view.bh = bh; view.sized = true;
    }
    const s = Math.min(bw/W, bh/H);
    view.w = Math.round(W*s); view.h = Math.round(H*s);
    view.x = Math.floor((bw - view.w)/2); view.y = Math.floor((bh - view.h)/2);
  }
  window.addEventListener('resize', resize);
  resize();

  let time = 0;
  function render(dt = 1/60) {
    time += dt;
    const p = params;
    // world
    world_camera.updateMatrixWorld();
    renderer.setRenderTarget(rt_world);
    renderer.setClearColor(world_scene.background || 0x000000, 1);
    renderer.render(world_scene, world_camera);
    // viewmodel
    renderer.setRenderTarget(rt_view);
    renderer.setClearColor(0x000000, 0);
    renderer.render(view_scene, view_camera);
    // bloom
    const bloom_on = p.bloom.strength > 0;
    if (bloom_on) {
      bright_mat.uniforms.uThreshold.value = p.bloom.threshold;
      pass(bright_mat, rt_bloom_a);
      blur_mat.uniforms.tSrc.value = rt_bloom_a.texture; blur_mat.uniforms.uDir.value.set(1/BW, 0); pass(blur_mat, rt_bloom_b);
      blur_mat.uniforms.tSrc.value = rt_bloom_b.texture; blur_mat.uniforms.uDir.value.set(0, 1/BH); pass(blur_mat, rt_bloom_a);
      blur_mat.uniforms.tSrc.value = rt_bloom_a.texture; blur_mat.uniforms.uDir.value.set(2/BW, 0); pass(blur_mat, rt_bloom_b);
      blur_mat.uniforms.tSrc.value = rt_bloom_b.texture; blur_mat.uniforms.uDir.value.set(0, 2/BH); pass(blur_mat, rt_bloom_a);
    }
      // final
    U.tBloom.value = bloom_on ? rt_bloom_a.texture : black;
    const sk = p.sky;
    U.uSkyOn.value = sk && sk.on ? 1 : 0;
    if (sk && sk.on) {
      U.uZenith.value.fromArray(sk.zenith); U.uHorizon.value.fromArray(sk.horizon); U.uGroundCol.value.fromArray(sk.ground);
      U.uSunDir.value.fromArray(sk.sun_dir).normalize(); U.uSunCol.value.fromArray(sk.sun_color); U.uHalo.value.fromArray(sk.halo);
      U.uSunSize.value = sk.sun_size; U.uClouds.value = sk.clouds; U.uCloudCol.value.fromArray(sk.cloud_color); U.uCloudShade.value.fromArray(sk.cloud_shade);
    }
    const sh = p.shafts;
    const sl = sh && sh.light;
    U.uShaftOn.value = sh && sh.on && sl && sl.shadow && sl.shadow.map ? 1 : 0;
    if (U.uShaftOn.value) {
      U.uShadowMap.value = sl.shadow.map.texture;
      U.uShadowMat.value.copy(sl.shadow.matrix);
      U.uShaftDensity.value = sh.density; U.uShaftMax.value = sh.max_dist; U.uShaftPhase.value = sh.phase; U.uShaftAmb.value = sh.ambient;
      U.uShaftCol.value.fromArray(sh.color);
      U.uShaftStreak.value = sh.streak || 0; U.uShaftRise.value = sh.rise || 0; U.uShaftSoft.value = sh.soft || 0; U.uShaftTop.value = sh.top || 30;
      if (!(sk && sk.on)) U.uSunDir.value.subVectors(sl.position, sl.target.position).normalize();
    }
    U.uProjInv.value.copy(world_camera.projectionMatrixInverse);
    U.uCamWorld.value.copy(world_camera.matrixWorld);
    U.uFogColor.value.copy(p.fog.color);
    U.uFogNear.value = p.fog.near; U.uFogFar.value = p.fog.far; U.uFogMax.value = p.fog.max; U.uFogCurve.value = p.fog.curve;
    U.uFogSky.value = p.fog.sky; U.uFogBaseY.value = p.fog.base_y; U.uFogFalloff.value = p.fog.falloff; U.uFogHeightMix.value = p.fog.height_mix;
    U.uBloom.value = p.bloom.strength; U.uExposure.value = p.exposure; U.uKnee.value = p.knee;
    U.uContrast.value = p.contrast; U.uSaturation.value = p.saturation; U.uVignette.value = p.vignette;
    U.uDither.value = p.dither; U.uLevels.value = p.levels; U.uTime.value = time;
    U.uDitherDark0.value = p.dither_dark[0]; U.uDitherDark1.value = p.dither_dark[1];
    U.uLift.value.fromArray(p.lift); U.uGamma.value.fromArray(p.gamma); U.uGain.value.fromArray(p.gain);
    U.uFlash.value.fromArray(p.flash); U.uHurtColor.value.fromArray(p.hurt_color); U.uHurt.value = p.hurt; U.uDesat.value = p.desat;
    U.uHud.value = p.hud;
    hud_tex.needsUpdate = true;
    pass(final_mat, rt_final);
    // upscale to the canvas
    resize();
    renderer.setRenderTarget(null);
    renderer.setViewport(0, 0, view.bw, view.bh);
    renderer.setClearColor(0x000000, 1);
    renderer.clear(true, false, false);
    renderer.setViewport(view.x, view.y, view.w, view.h);
    up_mat.uniforms.uOut.value.set(view.w, view.h);
    up_mat.uniforms.uSharp.value = p.upscale === 'nearest' ? 0 : 1;
    quad.material = up_mat;
    renderer.autoClear = false;
    renderer.render(pass_scene, pass_cam);
    renderer.autoClear = true;
    renderer.setViewport(0, 0, view.bw, view.bh);
  }

  // window pixel -> game pixel (for anything that needs it)
  function to_game_px(cx, cy) {
    const dpr = window.devicePixelRatio || 1;
    return [((cx*dpr - view.x)/view.w)*W, ((cy*dpr - view.y)/view.h)*H];
  }

  return {
    renderer, canvas, W, H, world_scene, world_camera, view_scene, view_camera,
    hud_canvas, hud_tex, params, hooks, hook_uniforms, rebuild, render, resize, view, to_game_px,
    set_shadow_light(l) { params.shafts.light = l; },
    targets: { rt_world, rt_view, rt_final },
  };
}
