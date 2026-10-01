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
#define SHADER_NAME warp.streaks
#define DOUBLE_SIDED
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

attribute vec3 aPrev, aNext; attribute float aSide, aU, aA; attribute vec4 aP;
      uniform vec2 uRes; uniform float uProj;
      varying float vSide, vU, vA, vAmp, vCh, vPh; varying vec2 vN, vT;
      void main(){
        mat4 PV = projectionMatrix*viewMatrix;
        vec4 c = PV*vec4(position, 1.0), cp = PV*vec4(aPrev, 1.0), cn = PV*vec4(aNext, 1.0);
        vec2 d = (cn.xy/max(cn.w, 1e-3) - cp.xy/max(cp.w, 1e-3))*uRes;
        d = length(d) > 1e-4 ? normalize(d) : vec2(1.0, 0.0);
        vec2 n = vec2(-d.y, d.x);
        float px = max(3.0, aP.x*uProj/max(c.w, 0.05));
        c.xy += n*aSide*px*0.5*2.0/uRes*c.w;
        gl_Position = c;
        vSide = aSide; vU = aU; vA = aA; vAmp = aP.y*min(1.0, px/3.0 + 0.3); vCh = aP.z; vPh = aP.w; vN = n; vT = d; }