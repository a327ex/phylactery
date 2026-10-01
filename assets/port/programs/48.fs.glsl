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
#define SHADER_NAME warp.puffs
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
      varying vec4 vP; varying float vSeed;
      void main(){
        if (hidden()) discard;
        vec2 q = gl_PointCoord*2.0 - 1.0; q.y = -q.y;
        float r = length(q);
        if (r > 1.0) discard;
        float fall = smoothstep(1.0, 0.1, r);
        float c = cos(vP.z), s = sin(vP.z);
        vec2 qr = vec2(c*q.x - s*q.y, s*q.x + c*q.y);
        // a swirl with lumps in it: air turning over, smoke made of it
        float lump = 0.6 + 0.8*n1(qr.x*3.0 + vSeed*17.0 + uTime*1.3)*n1(qr.y*3.0 + vSeed*9.0 - uTime*1.1);
        vec2 off = (vec2(-qr.y, qr.x)*0.9 + qr*0.35)*vP.y*fall*lump*vP.w;
        gl_FragColor = vec4(off, 0.9*fall*vP.w, 0.3*fall*vP.w); }