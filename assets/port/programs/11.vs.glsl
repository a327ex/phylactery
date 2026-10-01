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
#define SHADER_NAME fx.ribbons
#define DOUBLE_SIDED
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

attribute vec3 aP0, aP1, aWO; attribute float aEnd, aSide; attribute vec4 aCol, aB; attribute vec2 aX; attribute vec3 aPv, aNx;
      uniform vec2 uRes; uniform float uProj; varying vec4 vCol; varying float vSide, vAlong, vHue, vStyle, vLen, vPx, vW0;
      varying vec3 vW; varying vec2 vX;
      void main(){
        vec4 c0 = projectionMatrix*viewMatrix*vec4(aP0, 1.0), c1 = projectionMatrix*viewMatrix*vec4(aP1, 1.0);
        vec4 c = aEnd > 0.5 ? c1 : c0;
        vec2 s0 = c0.xy/max(c0.w, 1e-3), s1 = c1.xy/max(c1.w, 1e-3);
        vec2 d = (s1 - s0)*uRes; d = length(d) > 1e-4 ? normalize(d) : vec2(1.0, 0.0);
        // at a join, the edge square to the average of this piece's and its neighbour's direction
        vec4 cq = projectionMatrix*viewMatrix*vec4(aEnd > 0.5 ? aNx : aPv, 1.0);
        vec2 sq = cq.xy/max(cq.w, 1e-3);
        vec2 dq = (aEnd > 0.5 ? sq - s1 : s0 - sq)*uRes;
        vec2 dm = d;
        if (length(dq) > 1e-3) { dq = normalize(dq); if (dot(dq, d) > 0.3) dm = normalize(d + dq); }
        vec2 n = vec2(-dm.y, dm.x);
        // style 4 keeps w1 all along (its taper from w0 is cut in the fragment shader)
        float wm = aB.z > 3.5 ? aB.y : mix(aB.x, aB.y, aEnd);
        float px = aB.z > 0.5 ? max(aWO.x, wm*uProj/max(c.w, 0.05)) : aWO.x;
        c.xy += n*(aSide*px*0.5 + aWO.y)*2.0/uRes*c.w;
        vPx = px; vW0 = aB.y > 1e-5 ? aB.x/aB.y : 1.0;
        vW = aEnd > 0.5 ? aP1 : aP0; vX = aX;
        gl_Position = c; vCol = aCol; vSide = aSide; vAlong = aEnd; vHue = aWO.z; vStyle = aB.z; vLen = aB.w; }