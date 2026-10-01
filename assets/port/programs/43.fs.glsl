#version 300 es
#define varying in
layout(location = 0) out highp vec4 pc_fragColor;
#define gl_FragColor pc_fragColor
#define gl_FragDepthEXT gl_FragDepth
#define texture2D texture
#define textureCube texture
#define texture2DProj textureProj
#define texture2DLodEXT textureLod
#define texture2DProjLodEXT textureProjLod
#define textureCubeLodEXT textureLod
#define texture2DGradEXT textureGrad
#define texture2DProjGradEXT textureProjGrad
#define textureCubeGradEXT textureGrad
precision highp float;
	precision highp int;
	precision highp sampler2D;
	precision highp samplerCube;
	precision highp sampler3D;
	precision highp sampler2DArray;
	precision highp sampler2DShadow;
	precision highp samplerCubeShadow;
	precision highp sampler2DArrayShadow;
	precision highp isampler2D;
	precision highp isampler3D;
	precision highp isamplerCube;
	precision highp isampler2DArray;
	precision highp usampler2D;
	precision highp usampler3D;
	precision highp usamplerCube;
	precision highp usampler2DArray;
	
#define HIGH_PRECISION
#define SHADER_TYPE ShaderMaterial
#define SHADER_NAME post.final
uniform mat4 viewMatrix;
uniform vec3 cameraPosition;
uniform bool isOrthographic;
#define OPAQUE
vec4 LinearTransferOETF( in vec4 value ) {
	return value;
}
vec4 sRGBTransferEOTF( in vec4 value ) {
	return vec4( mix( pow( value.rgb * 0.9478672986 + vec3( 0.0521327014 ), vec3( 2.4 ) ), value.rgb * 0.0773993808, vec3( lessThanEqual( value.rgb, vec3( 0.04045 ) ) ) ), value.a );
}
vec4 sRGBTransferOETF( in vec4 value ) {
	return vec4( mix( pow( value.rgb, vec3( 0.41666 ) ) * 1.055 - vec3( 0.055 ), value.rgb * 12.92, vec3( lessThanEqual( value.rgb, vec3( 0.0031308 ) ) ) ), value.a );
}
vec4 linearToOutputTexel( vec4 value ) {
	return LinearTransferOETF( vec4( value.rgb * mat3( 1.0000,-0.0000,-0.0000,-0.0000,1.0000,0.0000,0.0000,0.0000,1.0000 ), value.a ) );
}
float luminance( const in vec3 rgb ) {
	const vec3 weights = vec3( 0.2126, 0.7152, 0.0722 );
	return dot( weights, rgb );
}


precision highp float;
#define SHAFT_STEPS 48
varying vec2 vUv;
uniform sampler2D tWorld, tDepth, tView, tBloom, tHud, tWarp;
uniform vec2 uRes;
uniform mat4 uProjInv, uCamWorld;
uniform vec3 uFogColor;
uniform float uFogNear, uFogFar, uFogMax, uFogCurve, uFogSky, uFogBaseY, uFogFalloff, uFogHeightMix;
uniform float uBloom, uExposure, uKnee, uContrast, uSaturation, uVignette, uDither, uLevels, uTime, uDitherDark0, uDitherDark1;
uniform vec3 uLift, uGamma, uGain;
uniform vec4 uFlash;
uniform vec3 uHurtColor; uniform float uHurt, uDesat, uHud, uWarpView;

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
}

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
}

vec3 hook_world(vec3 c, vec3 wpos, float dist, float sky){ return c; }
vec3 hook_grade(vec3 c, vec2 px){ return c; }
// the world, bilinear (its target is nearest-filtered): a warp shifts it by fractions of a pixel
vec3 world_bl(vec2 uv){
  vec2 p = uv*uRes - 0.5, f = fract(p), b = (floor(p) + 0.5)/uRes, d = 1.0/uRes;
  return mix(mix(texture2D(tWorld, b).rgb, texture2D(tWorld, b + vec2(d.x, 0.0)).rgb, f.x),
             mix(texture2D(tWorld, b + vec2(0.0, d.y)).rgb, texture2D(tWorld, b + d).rgb, f.x), f.y);
}
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
  // bent by what is in the warp target: the three channels shifted by slightly different amounts
  // (the prismatic split), a faint haze where it is dense
  vec4 wp = texture2D(tWarp, uv);
  if (abs(wp.x) + abs(wp.y) > 0.03) {
    vec2 o = wp.xy/uRes;
    float ch = clamp(wp.z, 0.0, 1.5);
    world = vec3(world_bl(uv + o*(1.0 + ch)).r, world_bl(uv + o).g, world_bl(uv + o*(1.0 - ch)).b);
  }
  world *= 1.0 + 0.16*clamp(wp.w, 0.0, 1.0);
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
  // tests (params.warp_view): where the world is being bent, tinted by how far
  if (uWarpView > 0.5) c = mix(c, vec3(0.3, 1.0, 0.85), clamp(length(wp.xy)*0.3, 0.0, 0.85));
  if (uLevels > 1.5) {
    float th = mix(0.5, bayer4(px), uDither*smoothstep(uDitherDark0, uDitherDark1, luma(c)));
    c = floor(clamp(c, 0.0, 1.0)*(uLevels - 1.0) + th)/(uLevels - 1.0);
  }
  vec4 hud = texture2D(tHud, uv);
  c = mix(c, hud.rgb, hud.a*uHud);
  gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}