#version 300 es

#define attribute in
#define varying out
#define texture2D texture
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
#define SHADER_NAME gore.blood
#define USE_SHADOWMAP
#define SHADOWMAP_TYPE_PCF
uniform mat4 modelMatrix;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform mat3 normalMatrix;
uniform vec3 cameraPosition;
uniform bool isOrthographic;
#ifdef USE_INSTANCING
	attribute mat4 instanceMatrix;
#endif
#ifdef USE_INSTANCING_COLOR
	attribute vec3 instanceColor;
#endif
#ifdef USE_INSTANCING_MORPH
	uniform sampler2D morphTexture;
#endif
attribute vec3 position;
attribute vec3 normal;
attribute vec2 uv;
#ifdef USE_UV1
	attribute vec2 uv1;
#endif
#ifdef USE_UV2
	attribute vec2 uv2;
#endif
#ifdef USE_UV3
	attribute vec2 uv3;
#endif
#ifdef USE_TANGENT
	attribute vec4 tangent;
#endif
#if defined( USE_COLOR_ALPHA )
	attribute vec4 color;
#elif defined( USE_COLOR )
	attribute vec3 color;
#endif
#ifdef USE_SKINNING
	attribute vec4 skinIndex;
	attribute vec4 skinWeight;
#endif

attribute vec3 aVel; attribute vec4 aCol; attribute float aSize; uniform float uScale; uniform vec2 uRes;
      varying vec4 vCol; varying vec2 vDir; varying float vK;
      void main(){
        vec4 c0 = projectionMatrix*viewMatrix*vec4(position, 1.0), c1 = projectionMatrix*viewMatrix*vec4(position - aVel*0.012, 1.0);
        vec2 d = (c0.xy/max(c0.w, 1e-3) - c1.xy/max(c1.w, 1e-3))*uRes*0.5;
        float streak = length(d);
        float dot_px = aSize > 0.0 ? max(1.0, aSize*uScale/max(c0.w, 0.05)) : 0.0;
        gl_PointSize = aSize > 0.0 ? min(24.0, dot_px + streak) : 0.0;
        gl_Position = c0;
        vDir = streak > 1e-3 ? d/streak : vec2(1.0, 0.0);
        vK = dot_px/max(gl_PointSize, 1.0);          // how much of the sprite is the drop, the rest its trail
        vCol = aCol; }