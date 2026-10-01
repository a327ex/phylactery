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
#define SHADER_NAME warp.streaks
#define DOUBLE_SIDED
uniform mat4 viewMatrix;
uniform vec3 cameraPosition;
uniform bool isOrthographic;
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


uniform vec2 uRes; uniform float uProj, uTime; uniform sampler2D tDepth;
uniform float uNoDepth;
bool hidden(){ return uNoDepth < 0.5 && gl_FragCoord.z > texture2D(tDepth, gl_FragCoord.xy/uRes).x + 1e-6; }
float h1(float x){ return fract(sin(x*127.1)*43758.5453); }
float n1(float x){ float i = floor(x), f = fract(x); return mix(h1(i), h1(i + 1.0), f*f*(3.0 - 2.0*f)); }
      varying float vSide, vU, vA, vAmp, vCh, vPh; varying vec2 vN, vT;
      void main(){
        if (uNoDepth > 1.5) { gl_FragColor = vec4(5.0, 0.0, 0.0, vA); return; }
        if (vA <= 0.0 || hidden()) discard;
        float x = vSide;
        // a thin lens across it: pushed out on one side, in on the other; strongest in its middle
        float g = -x*exp(-x*x*2.2)*2.3;
        float env = smoothstep(0.0, 0.18, vU)*smoothstep(1.0, 0.7, vU);
        float rip = 0.7 + 0.3*sin(vU*19.0 - uTime*15.0 + vPh) + 0.15*(n1(vU*9.0 + vPh*3.0 - uTime*6.0) - 0.5);
        float k = vAmp*env*rip*vA;
        vec2 off = vN*g*k + vT*exp(-x*x*2.0)*k*0.35;        // and dragged a little along it, like wind
        gl_FragColor = vec4(off, vCh*env*exp(-x*x*1.5)*vA, 0.32*exp(-x*x*2.0)*env*vA); }