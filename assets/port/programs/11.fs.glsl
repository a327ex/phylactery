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
#define SHADER_NAME fx.ribbons
#define DOUBLE_SIDED
#define USE_SHADOWMAP
#define SHADOWMAP_TYPE_PCF
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

uniform float uTime; varying vec4 vCol; varying float vSide, vAlong, vHue, vStyle, vLen, vPx, vW0;
      varying vec3 vW; varying vec2 vX;
      vec3 spec(float h){ return clamp(abs(fract(h + vec3(0.0, 0.6667, 0.3333))*6.0 - 3.0) - 1.0, 0.0, 1.0); }
      // his bones' colours (gem.js: a smooth spectrum toward grey, normalised by its mean so no
      // hue is darker than another). On the bones it is 30% grey; light that bright at 30% grey
      // rolls off to near white on screen, so the beam's is 16%; 'full' keeps the spectrum pure
      vec3 opal(float h, float full){ vec3 c = spec(h); c = c*c*(3.0 - 2.0*c); c = mix(c, vec3(0.5), mix(0.16, 0.0, full)); return c/max((c.r + c.g + c.b)/3.0, 0.2); }
      float h1(float x){ return fract(sin(x*127.1)*43758.5453); }
      float n1(float x){ float i = floor(x), f = fract(x); return mix(h1(i), h1(i + 1.0), f*f*(3.0 - 2.0*f)); }
      void main(){
        float a = abs(vSide);
        vec3 c;
        if (vStyle > 3.5) {
          // PRISM LASER: the lens beam's build in his colours
          // a beam can be drawn in pieces (a curve): x runs on from piece to piece
          float x = vX.x + vAlong*vLen;
          // the first ~28 cm grow from the fingertip's thickness (never under a pixel)
          float tp = mix(vW0, 1.0, smoothstep(0.0, 0.28, x));
          float tpx = max(1.0, tp*vPx);
          a = a*vPx/tpx;
          if (a > 1.0) discard;
          float flow = 0.72 + 0.28*n1(x*3.0 - uTime*26.0) + 0.12*n1(x*9.0 - uTime*47.0);
          float wob = 0.12*(n1(x*5.0 - uTime*30.0) - 0.5);
          float aa = clamp(a + wob, 0.0, 1.0);
          // the hue: his bones' SOFT field (the same phase they show where the beam leaves him)
          float field0 = vX.y;                                        // the field where the beam leaves him
          float ph;
          // STREAMING: a full turn of the hue wheel every ~3.3 m, flowing out from his finger at
          // 2.4 m/s; HELD: the field itself where the beam passes, drifting as slowly as it does
          // on his bones
          if (vHue < 0.5 || vHue > 1.5) ph = field0 - (x - uTime*2.4)*0.3;
          else ph = dot(vW, vec3(0.45, 0.9, 0.3))*0.55 - uTime*0.04 + (n1(x*0.9 + 3.0) - 0.5)*0.25;
          float full = vHue > 1.5 ? 1.0 : 0.0;
          vec3 sheath = mix(opal(ph, full), opal(ph + 0.14, full), smoothstep(0.35, 0.85, aa));
          // the colour carries it: kept under the point where the bright channels clip to white,
          // brighter toward the middle; the white-hot core is narrower than the fire laser's and
          // only shows where the beam is wide enough on screen to have a middle (a 2-3 px beam
          // with a white core reads as a white line)
          float core = smoothstep(3.0, 8.0, vPx)*(1.0 - smoothstep(0.04, 0.22, aa));
          c = mix(sheath*0.62*mix(1.3, 0.75, aa), vec3(1.0, 0.98, 0.97)*3.0, core)*smoothstep(1.0, 0.55, aa);
          c *= flow*vCol.rgb;
        } else if (vStyle < 0.5) {
          float k = 1.0 - a; k = k*k*(3.0 - 2.0*k);
          c = vCol.rgb*k;
          if (vHue >= 0.0) c *= mix(vec3(1.0), spec(vHue + vAlong*0.6 - uTime*1.5), 0.75);
        } else {
          // energy streaming from p0 to p1: bands of brightness, in metres along the beam
          float x = vAlong*vLen;
          float flow = 0.72 + 0.28*n1(x*3.0 - uTime*26.0) + 0.12*n1(x*9.0 - uTime*47.0);
          if (vStyle < 1.5 || vStyle > 2.5) {
            // the prism: dispersed further along (after the first ~35 cm it is a band)
            float disp = smoothstep(0.0, 0.35, x)*0.85 + 0.15;
            float edge = smoothstep(1.0, 0.72, a);
            float u = vSide*0.5 + 0.5;
            vec3 band = vStyle < 1.5
              ? mix(spec(u*0.76), vec3(1.0), 0.04)*(0.8 + 0.5*exp(-pow((u - 0.35)/0.3, 2.0)))
              : mix(vec3(1.0, 0.18, 0.04), mix(vec3(1.0, 0.62, 0.12), vec3(1.0, 0.95, 0.7), smoothstep(0.35, 0.0, a)), smoothstep(0.95, 0.4, a));
            float core = exp(-pow(vSide/mix(0.55, 0.12, disp), 2.0));
            c = band*edge*disp*2.1 + vec3(1.0)*core*(2.4 - 2.0*disp);          // the white core gives way to the band as it spreads
            c *= flow;
          } else {
            // the fire laser: a white core, an orange sheath, a red glow; noise eating its edges
            float wob = 0.12*(n1(x*5.0 - uTime*30.0) - 0.5);
            float aa = clamp(a + wob, 0.0, 1.0);
            vec3 sheath = mix(vec3(1.0, 0.42, 0.08), vec3(1.0, 0.12, 0.03), smoothstep(0.35, 0.85, aa));
            c = mix(vec3(1.0, 0.95, 0.82)*3.0, sheath*1.7, smoothstep(0.08, 0.32, aa))*smoothstep(1.0, 0.55, aa);
            c *= flow;
          }
          c *= vCol.rgb;
        }
        gl_FragColor = vec4(c*vCol.a, 1.0); }