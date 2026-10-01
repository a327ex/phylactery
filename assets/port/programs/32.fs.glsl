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
#define SHADER_NAME item.orbs
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
uniform vec3 uCamO;
uniform mat3 uToWorld;
uniform samplerCube uEnv;
uniform float uEnvK, uGlintPow, uLit, uFlip;
uniform vec3 uIor, uSunDir, uSunCol, uAbsorb;
varying vec3 vPosO;
vec3 env_w(vec3 dO){
  vec3 d = normalize(uToWorld*dO);
  vec3 c = textureCube(uEnv, vec3(uFlip*d.x, d.y, d.z)).rgb*uEnvK;
  float s = max(dot(d, uSunDir), 0.0);
  return c + uSunCol*(pow(s, uGlintPow) + 0.03*pow(s, uGlintPow*0.04))*uLit;
}
float schlick(float c, float n){ float f0 = (n - 1.0)/(n + 1.0); f0 *= f0; return f0 + (1.0 - f0)*pow(1.0 - clamp(c, 0.0, 1.0), 5.0); }
// one colour through the ball (unit sphere, object space), from surface point p going d
float through(vec3 p, vec3 d, float n, int ch){
  float acc = 0.0, thr = 1.0;
  for (int b = 0; b < 3; b++) {
    float t = -2.0*dot(p, d);
    p += d*t;
    thr *= exp(-uAbsorb[ch]*t);
    vec3 N = normalize(p);
    vec3 o = refract(d, -N, n);
    if (dot(o, o) < 1e-6) { d = reflect(d, -N); continue; }
    float F = schlick(dot(o, N), n);
    acc += thr*(1.0 - F)*env_w(o)[ch];
    thr *= F;
    d = reflect(d, -N);
  }
  return acc;
}
void main(){
  vec3 P = normalize(vPosO);
  vec3 V = normalize(vPosO - uCamO);
  float c = max(-dot(V, P), 0.0);
  float F = schlick(c, uIor.g);
  vec3 col = env_w(reflect(V, P))*F;
  vec3 inside;
  for (int ch = 0; ch < 3; ch++) { float n = uIor[ch]; inside[ch] = through(P, refract(V, P, 1.0/n), n, ch); }
  col += (1.0 - F)*inside;
  gl_FragColor = vec4(min(col, vec3(2.4)), 1.0);
}