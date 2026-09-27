// soft_shadows.js -- sun shadows whose softness grows with the distance to what casts them
// (percentage-closer soft shadows), replacing three.js's PCF shadow filter.
//
// Owner, round 3: the light should come from further above, and "the edges of the light circle
// ... more soft". The sun is a disc about half a degree across, so a shadow edge blurs by
// (distance to the caster) x (the sun's angular size): the rim of a shaft 40 m up blurs the
// pool's edge over tens of centimetres while a rock beside the pool stays crisp. For each
// point: search the shadow map around it for casters, average their depth, turn the gap into a
// penumbra width, then filter over that width. The shadow map is orthographic, so its depth is
// linear: metres = depth x (far - near).
//
// Call install_soft_shadows(params) BEFORE any material compiles; the renderer must use
// THREE.PCFShadowMap (this replaces that branch).
import * as THREE from 'three';

export const SOFT = { depth_range: 89, texel_m: 0.034, sun_angle: 0.0093, max_texels: 22 };

export function install_soft_shadows(p = {}) {
  Object.assign(SOFT, p);
  const chunk = THREE.ShaderChunk.shadowmap_pars_fragment;
  const start = chunk.indexOf('#if defined( SHADOWMAP_TYPE_PCF )');
  const end = chunk.indexOf('#elif defined( SHADOWMAP_TYPE_PCF_SOFT )');
  if (start < 0 || end < 0) throw new Error('soft_shadows: shadow chunk changed shape');
  const f = v => (Number.isInteger(v) ? v.toFixed(1) : String(v));
  const pcss = `#if defined( SHADOWMAP_TYPE_PCF )
			// lich-survivors: percentage-closer soft shadows (soft_shadows.js)
			vec2 texel = vec2( 1.0 ) / shadowMapSize;
			float zr = shadowCoord.z;
			float bsum = 0.0, bn = 0.0;
			for ( int i = 0; i < 16; i ++ ) {
				float fi = float( i );
				float r = sqrt( ( fi + 0.5 ) / 16.0 ) * ${f(SOFT.max_texels)};
				vec2 o = vec2( cos( fi*2.39996 ), sin( fi*2.39996 ) )*r*texel;
				float bz = unpackRGBAToDepth( texture2D( shadowMap, shadowCoord.xy + o ) );
				if ( bz < zr ) { bsum += bz; bn += 1.0; }
			}
			if ( bn < 0.5 ) {
				shadow = 1.0;
			} else {
				float gap = ( zr - bsum/bn )*${f(SOFT.depth_range)};
				float pen = clamp( gap*${f(SOFT.sun_angle)}/${f(SOFT.texel_m)}*0.5, 0.75, ${f(SOFT.max_texels)} );
				float rot = fract( 52.9829189*fract( dot( gl_FragCoord.xy, vec2( 0.06711056, 0.00583715 ) ) ) )*6.2831853;
				float lit = 0.0;
				for ( int i = 0; i < 24; i ++ ) {
					float fi = float( i );
					float r = sqrt( ( fi + 0.5 ) / 24.0 )*pen;
					float a = fi*2.39996 + rot;
					lit += texture2DCompare( shadowMap, shadowCoord.xy + vec2( cos( a ), sin( a ) )*r*texel, zr );
				}
				shadow = lit/24.0;
			}
		`;
  THREE.ShaderChunk.shadowmap_pars_fragment = chunk.slice(0, start) + pcss + chunk.slice(end);
}
