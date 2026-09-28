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
//          through the mineral; in the dark there is nothing to carry. Round 7: the more light
//          arrives, the more of the bone's brightness turns into that rainbow (and the less
//          bright it is overall); far from the light it stays neutral bone
// Round 5 adds one that does emit, off by default in the material: GLOW, the same inner rainbow
// shining faintly on its own, so the bones still read in the dark while he is steered there.
import * as THREE from 'three';

const DECL = /* glsl */`
uniform float uGemTime, uFire, uInner, uGlow, uGemDebug, uPrismLo, uPrismHi, uLitDim;
varying vec3 vGemW;
vec3 gem_spectrum(float h){
  vec3 c = clamp(abs(fract(h + vec3(0.0, 0.6667, 0.3333))*6.0 - 3.0) - 1.0, 0.0, 1.0);
  return c*c*(3.0 - 2.0*c);
}
float gem_luma(vec3 c){ return dot(c, vec3(0.2126, 0.7152, 0.0722)); }`;

export const GEM_LEVELS = [
  // inner (round 7) = how far the lit bone turns to rainbow in full light
  { name: 'SOLID', fire: 4.0, inner: 0.6, irid: 0.32 },        // round 4 default: solid ivory, fired by the light
  { name: 'STRONG (ROUND 3)', fire: 6.0, inner: 0.95, irid: 0.9 },
  { name: 'SUBTLE', fire: 1.6, inner: 0.35, irid: 0.35 },
];

export function gem_material(opts = {}) {
  const m = new THREE.MeshPhysicalMaterial({
    color: opts.color ?? 0xebe4d6, roughness: opts.roughness ?? 0.3, metalness: 0,
    ior: 1.9, specularIntensity: 1.0,
    iridescence: 0.35, iridescenceIOR: 1.45, iridescenceThicknessRange: [220, 820],
    flatShading: opts.flat ?? true,
  });
  const U = { uGemTime: { value: 0 }, uFire: { value: 1.6 }, uInner: { value: 0.16 }, uGlow: { value: 0 }, uGemDebug: { value: 0 },
    uPrismLo: { value: 0.06 }, uPrismHi: { value: 0.8 }, uLitDim: { value: 0.36 } };
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
    vec3 inner = gem_spectrum(dot(vGemW, vec3(0.45, 0.9, 0.3)) - uGemTime*0.04 + facet*0.18);
    // round 7 (owner: "more prismatic instead of bright the closer he is to light, and more
    // neutral instead of prismatic the further away"; "less bright overall" in the light):
    // how much light reaches this point, per unit albedo (measured: far dark ~0.01, 5 m out
    // ~0.08, the pool's edge ~0.5, in the pool ~1.2), on a log scale -> prism 0..1
    float al = max(gem_luma(diffuseColor.rgb), 0.05);
    vec3 dd = reflectedLight.directDiffuse + reflectedLight.indirectDiffuse;
    float arrive = gem_luma(dd)/al;
    float prism = smoothstep(0.0, 1.0, (log(max(arrive, 1e-4)) - log(uPrismLo))/(log(uPrismHi) - log(uPrismLo)));
    vec3 rawD = reflectedLight.directDiffuse, rawI = reflectedLight.indirectDiffuse;
    // in the light the bone gives its brightness up for colour: the diffuse dims and turns
    // toward the rainbow at the same energy (hues normalised by their mean, so blue isn't dark)
    // the colour depends on the facet and the viewing angle as well as the place on the bone, so
    // it breaks into patches and shifts as he turns (dispersion), not a painted gradient
    vec3 hue = mix(gem_spectrum(dot(vGemW, vec3(0.45, 0.9, 0.3))*1.6 + facet*0.6 + nv*0.9 - uGemTime*0.04), vec3(0.5), 0.3);
    hue /= max((hue.r + hue.g + hue.b)/3.0, 0.2);
    float keep = mix(1.0, uLitDim, prism);
    reflectedLight.directDiffuse = vec3(0.0);
    reflectedLight.indirectDiffuse = mix(dd, hue*(dd.r + dd.g + dd.b)/3.0, prism*uInner)*keep;
    // the sun's glints: white fades out for spectral fire as the light grows
    float sl = gem_luma(reflectedLight.directSpecular);
    reflectedLight.directSpecular = reflectedLight.directSpecular*(1.0 - 0.6*prism) + fire*sl*uFire*mix(0.4, 0.8, prism);
    // glow: neutral pale bone, brightest where the bone faces the eye; nothing to add in the light
    totalEmissiveRadiance += vec3(0.9, 0.89, 0.86)*uGlow*(0.55 + 0.45*abs(nv))*(1.0 - prism);
    // measuring (GAME.gem_probe): the light arriving, per unit albedo: direct, bounce, a marker
    if (uGemDebug > 0.5) {
      totalEmissiveRadiance = vec3(gem_luma(rawD)/al, gem_luma(rawI)/al, 777.0);
      reflectedLight.directDiffuse = vec3(0.0); reflectedLight.indirectDiffuse = vec3(0.0);
      reflectedLight.directSpecular = vec3(0.0); reflectedLight.indirectSpecular = vec3(0.0);
    }
  }`);
  };
  const key = () => 'gem';
  m.customProgramCacheKey = key;
  return m;
}
