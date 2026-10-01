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
#define SHADER_NAME item.gem
#define USE_SHADOWMAP
#define SHADOWMAP_TYPE_PCF
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
#define MAXP 96
#define BOUNCES 6
uniform vec4 uPlanes[MAXP];
uniform int uNP;
uniform vec3 uCamO;
uniform mat3 uToWorld;
uniform samplerCube uEnv;
uniform float uEnvK, uGlintPow, uLit, uFlip;
uniform vec3 uIor, uSunDir, uSunCol, uAbsorb, uTint;
varying vec3 vPosO; varying vec3 vNorO;
vec3 env_w(vec3 dO){
  vec3 d = normalize(uToWorld*dO);
  vec3 c = textureCube(uEnv, vec3(uFlip*d.x, d.y, d.z)).rgb*uEnvK;
  // the light itself (the sun down the shaft, or the inspect view's key): a hard glint
  float s = max(dot(d, uSunDir), 0.0);
  return c + uSunCol*(pow(s, uGlintPow) + 0.04*pow(s, uGlintPow*0.05))*uLit;
}
float schlick(float c, float n){ float f0 = (n - 1.0)/(n + 1.0); f0 *= f0; return f0 + (1.0 - f0)*pow(1.0 - clamp(c, 0.0, 1.0), 5.0); }
// follow one colour's ray inside the stone; returns what leaves, in that colour
float trace(vec3 p, vec3 d, float n, int ch){
  float acc = 0.0, thr = 1.0;
  for (int b = 0; b < BOUNCES; b++) {
    float tm = 1e9; vec3 nh = vec3(0.0, 1.0, 0.0);
    for (int i = 0; i < MAXP; i++) {
      if (i >= uNP) break;
      vec4 pl = uPlanes[i];
      float dn = dot(pl.xyz, d);
      if (dn > 1e-5) { float t = (pl.w - dot(pl.xyz, p))/dn; if (t < tm) { tm = t; nh = pl.xyz; } }
    }
    p += d*tm;
    thr *= exp(-uAbsorb[ch]*tm);
    vec3 o = refract(d, -nh, n);
    float ci = dot(d, nh);
    if (dot(o, o) < 1e-6) { d = reflect(d, -nh); continue; }       // total internal reflection
    float F = schlick(dot(o, nh), n);
    acc += thr*(1.0 - F)*env_w(o)[ch];
    thr *= F;
    d = reflect(d, -nh);
  }
  return acc + thr*env_w(d)[ch]*0.6;
}
void main(){
  vec3 N = normalize(vNorO);
  vec3 V = normalize(vPosO - uCamO);
  float c = max(-dot(V, N), 0.0);
  float F = schlick(c, uIor.g);
  vec3 col = env_w(reflect(V, N))*F;
  vec3 inside;
  for (int ch = 0; ch < 3; ch++) {
    float n = uIor[ch];
    vec3 d = refract(V, N, 1.0/n);
    inside[ch] = trace(vPosO + d*1e-4, d, n, ch);
  }
  col += (1.0 - F)*inside*uTint;
  gl_FragColor = vec4(min(col, vec3(5.0)), 1.0);      // a glint's bloom stays a sparkle, not a halo
}