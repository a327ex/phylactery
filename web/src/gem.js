// gem.js -- prismatic bone: a pale, faintly faceted mineral that splits the light hitting it
// (owner, round 1: "A is the idea, but the effect should be more subtle, as the lich moves
// around and light hits him differently, different portions of his bones glow in that natural
// way that such a prismatic object like a gem would glow").
//
// Nothing here emits light of its own. Three light-driven effects on a physical material:
//   FIRE   the direct specular (shadowed: only where the sun actually reaches) is split into
//          spectral colour by facet and viewing angle, like a diamond's flashes
//   SHEEN  thin-film iridescence (three.js's physical iridescence), a rainbow that moves with
//          the angle between eye and surface
//   INNER  whatever light arrives (sun + bounce) comes back out as a soft rainbow, as if carried
//          through the mineral; in the dark there is nothing to carry
import * as THREE from 'three';

const DECL = /* glsl */`
uniform float uGemTime, uFire, uInner;
varying vec3 vGemW;
vec3 gem_spectrum(float h){
  vec3 c = clamp(abs(fract(h + vec3(0.0, 0.6667, 0.3333))*6.0 - 3.0) - 1.0, 0.0, 1.0);
  return c*c*(3.0 - 2.0*c);
}
float gem_luma(vec3 c){ return dot(c, vec3(0.2126, 0.7152, 0.0722)); }`;

export const GEM_LEVELS = [
  { name: 'SUBTLE', fire: 1.6, inner: 0.16, irid: 0.35 },
  { name: 'MEDIUM', fire: 3.2, inner: 0.32, irid: 0.6 },
  { name: 'STRONG', fire: 6.0, inner: 0.6, irid: 0.9 },
];

export function gem_material(opts = {}) {
  const m = new THREE.MeshPhysicalMaterial({
    color: opts.color ?? 0xebe4d6, roughness: opts.roughness ?? 0.3, metalness: 0,
    ior: 1.9, specularIntensity: 1.0,
    iridescence: 0.35, iridescenceIOR: 1.45, iridescenceThicknessRange: [220, 820],
    flatShading: opts.flat ?? true,
  });
  const U = { uGemTime: { value: 0 }, uFire: { value: 1.6 }, uInner: { value: 0.16 } };
  m.userData.gemU = U;
  m.userData.set_level = (l) => { U.uFire.value = l.fire; U.uInner.value = l.inner; m.iridescence = l.irid; };
  const prev = m.onBeforeCompile;
  m.onBeforeCompile = (sh, r) => {
    if (prev) prev(sh, r);
    Object.assign(sh.uniforms, U);
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vGemW;')
      .replace('#include <project_vertex>', '#include <project_vertex>\n  vGemW = (modelMatrix*vec4(transformed, 1.0)).xyz;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\n' + DECL)
      .replace('#include <lights_fragment_end>', `#include <lights_fragment_end>
  {
    vec3 gnW = normalize((vec4(normal, 0.0)*viewMatrix).xyz);
    // a stable random per facet (flat normals are constant across a facet)
    // a smooth, slowly varying phase over the surface (normal + position): colour shifts across a bone like a gem's play of colour
    float facet = 0.5 + 0.25*sin(dot(gnW, vec3(4.1, 3.3, 5.2)) + dot(vGemW, vec3(7.0, 5.0, 6.0))) + 0.25*sin(dot(gnW, vec3(-3.7, 4.6, 2.9))*1.7);
    float nv = dot(normal, normalize(vViewPosition));
    vec3 fire = gem_spectrum(facet + nv*1.6 + uGemTime*0.02);
    reflectedLight.directSpecular += fire*gem_luma(reflectedLight.directSpecular)*uFire;
    float lit = gem_luma(reflectedLight.directDiffuse + reflectedLight.indirectDiffuse);
    vec3 inner = gem_spectrum(dot(vGemW, vec3(0.45, 0.9, 0.3)) - uGemTime*0.04 + facet*0.18);
    reflectedLight.indirectDiffuse += inner*lit*uInner;
  }`);
  };
  const key = () => 'gem';
  m.customProgramCacheKey = key;
  return m;
}
