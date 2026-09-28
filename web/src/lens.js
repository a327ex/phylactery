// lens.js -- LENS (round 11, owner: "creates a lens bending the shaft's sunlight and creating a
// single fire laser beam that moves forward and splits any snakes it passes through"; the lens
// is a physical floating glass-like object, and he doesn't point).
//
// Round 14 (owner: the effect is right, but the lens "looks like a slab of concrete instead of
// glass. It should look transparent like glass but still visible. The way the light converges
// on it should also feel a bit more realistic." And it hit tails: "It should aim for either
// cutting the head off or middle"). Round 15 (owner: no glints leading into it). Round 16
// (owner: no light from above at all; the flash as it fired "feels off"):
//   FORM      the glass crystallizes in the shaft: real transmissive glass (it bends what is
//             behind it, a little spectral spread, glints where the sun catches it, a faint rim
//             so it reads in the dark; it casts its shadow into the shaft like a real lens)
//   CONVERGE  as a magnifying glass does: the light it gathers coming out as a cone to a wide
//             soft patch on the floor beside the snake that tightens to a blinding point,
//             brighter as it shrinks (the same light on less floor), and starts to smoke; the
//             focus follows the snake while it crawls
//   FIRE      the cone goes out as the focus becomes the laser (round 13's beam: L = fire laser
//             / prism in fire): the glass flares a moment, the focal point ignites (sparks, a
//             puff); it sweeps across the snake from right beside it, at its neck (the head
//             comes off) or its middle; tails are never cut
//   END       the beam thins out, the glass dissolves into glints
// Cut halves part charred and smoking, twitch, and sink into the ground. With fewer powers
// left, several lenses form at once.
import * as THREE from 'three';
import { smoothstep } from 'game/util.js';
import { LAYOUT } from 'game/cave.js';

const FORM = 0.4, CONVERGE = 0.8, SPEED = 3.0, SWEEP = 2.6, LEAD = 0.35, OFF = 0.2, FADE = 0.45, CUT_R = 0.13;
const LENS_R = 0.38;
const LIGHTS_OFF = 0.15;             // the cone goes out this fast as it fires
// where a cut may fall: from just behind the snout back to here (metres along the body); past
// it, the tail
const CUT_MAX = 2.6;
export const LENS_LOOKS = ['FIRE LASER (TITAN, PHRIKE)', 'THE PRISMATIC BEAM, IN FIRE'];

export function create_lens(ctx) {
  const { R, snakes, fx, cave, rng } = ctx;
  const N = snakes.RINGS;
  const S = LAYOUT.sun_dir, sxz = new THREE.Vector2(S.x/S.y, S.z/S.y);
  const axis_at = h => new THREE.Vector3(sxz.x*h, h, sxz.y*h);

  // ---------------------------------------------------------------- the glass
  const geo = new THREE.SphereGeometry(1, 40, 16);
  geo.scale(1, 0.14, 1);                            // a biconvex lens: 76 cm across, ~10 cm thick
  const glass_mat = () => {
    const m = new THREE.MeshPhysicalMaterial({
      color: 0xffffff, metalness: 0, roughness: 0.03, transmission: 1, thickness: 0.18, ior: 1.52,
      dispersion: 0.8, specularIntensity: 1, specularColor: 0xffffff, envMapIntensity: 0,
      depthWrite: false,             // the shaft's haze (drawn after, by depth) must show through the glass, not stop at it
    });
    const U = { uRim: { value: 0 } };
    m.userData.U = U;
    m.onBeforeCompile = (sh) => {
      Object.assign(sh.uniforms, U);
      sh.fragmentShader = sh.fragmentShader
        .replace('#include <common>', '#include <common>\nuniform float uRim;')
        .replace('#include <lights_fragment_end>', `#include <lights_fragment_end>
  {
    // a faint rim so the edge of the glass still reads in the dark cave
    float nv = abs(dot(normalize(normal), normalize(vViewPosition)));
    totalEmissiveRadiance += vec3(0.85, 0.9, 1.0)*pow(1.0 - nv, 3.0)*uRim;
  }`);
    };
    m.customProgramCacheKey = () => 'lens_glass';
    return m;
  };
  // a shimmer over the glass while it crystallizes (additive, fades once it has formed)
  const shimmer_mat = () => new THREE.ShaderMaterial({
    uniforms: { uA: { value: 0 }, uTime: { value: 0 } },
    vertexShader: `varying vec3 vN, vV, vP; void main(){ vec4 w = modelMatrix*vec4(position, 1.0); vN = normalize(mat3(modelMatrix)*normal); vV = normalize(cameraPosition - w.xyz); vP = position; gl_Position = projectionMatrix*viewMatrix*w; }`,
    fragmentShader: `uniform float uA, uTime; varying vec3 vN, vV, vP;
      void main(){
        float rim = pow(1.0 - abs(dot(normalize(vN), vV)), 3.0);
        vec3 h = clamp(abs(fract(atan(vP.z, vP.x)*0.16 + uTime*0.8 + vec3(0.0, 0.6667, 0.3333))*6.0 - 3.0) - 1.0, 0.0, 1.0);
        gl_FragColor = vec4(mix(vec3(1.0), h, 0.6)*rim*1.1*uA, 1.0); }`,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
  });

  // the cone of gathered sunlight under the lens, and the patch it throws on the floor
  const SEG = 28;
  const cone_mat = new THREE.ShaderMaterial({
    uniforms: { uA: { value: 1 } },
    vertexShader: `attribute float aT; attribute float aA; varying float vT, vA; void main(){ vT = aT; vA = aA; gl_Position = projectionMatrix*viewMatrix*vec4(position, 1.0); }`,
    fragmentShader: `varying float vT, vA; void main(){ gl_FragColor = vec4(vec3(1.0, 0.9, 0.7)*vA*(0.25 + 0.75*vT*vT), 1.0); }`,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
  });
  const patch_mat = new THREE.ShaderMaterial({
    uniforms: { uA: { value: 0 } },
    vertexShader: `varying vec2 vU; void main(){ vU = uv*2.0 - 1.0; gl_Position = projectionMatrix*modelViewMatrix*vec4(position, 1.0); }`,
    fragmentShader: `uniform float uA; varying vec2 vU; void main(){ float d = length(vU); float k = smoothstep(1.0, 0.0, d); k = k*k; gl_FragColor = vec4(vec3(1.0, 0.92, 0.75)*k*uA, 1.0); }`,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
  });
  const make_cone = () => {
    const g = new THREE.BufferGeometry();
    const pos = new Float32Array(SEG*2*3), at = new Float32Array(SEG*2), aa = new Float32Array(SEG*2);
    for (let j = 0; j < SEG; j++) { at[j] = 0; at[SEG + j] = 1; }
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    g.setAttribute('aT', new THREE.BufferAttribute(at, 1));
    g.setAttribute('aA', new THREE.BufferAttribute(aa, 1));
    const idx = [];
    for (let j = 0; j < SEG; j++) { const a = j, b = (j + 1)%SEG, c = SEG + b, d = SEG + j; idx.push(a, d, c, a, c, b); }
    g.setIndex(idx);
    const m = new THREE.Mesh(g, cone_mat);
    m.frustumCulled = false; m.renderOrder = 11; m.visible = false;
    R.world_scene.add(m);
    return m;
  };
  const make_patch = () => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), patch_mat.clone());
    m.rotation.x = -Math.PI/2; m.frustumCulled = false; m.renderOrder = 11; m.visible = false;
    R.world_scene.add(m);
    return m;
  };

  const LENSES = [], LIGHTS = [];
  for (let i = 0; i < 5; i++) {
    const m = new THREE.Mesh(geo, glass_mat());
    m.castShadow = true; m.receiveShadow = false;
    m.visible = false; m.frustumCulled = false; m.renderOrder = 13;
    R.world_scene.add(m);
    const sh = new THREE.Mesh(geo, shimmer_mat());
    sh.scale.setScalar(1.02); sh.renderOrder = 14; sh.visible = false;
    m.add(sh);
    LENSES.push({ m, sh, cone: make_cone(), patch: make_patch(), on: false });
  }
  for (let i = 0; i < 3; i++) {
    const l = new THREE.PointLight(0xffc27a, 0, 5, 2);
    R.world_scene.add(l);
    LIGHTS.push({ l, lens: null });
  }
  const active = [];
  let look = 0;
  const cuts = [];                  // tests: where each cut fell (metres from the snout) and on whom

  function cut_fx(s, c) {
    // the body's direction at the cut, toward the head
    const tan = new THREE.Vector3().subVectors(s.spine[Math.max(0, c - 3)], s.spine[Math.min(N - 1, c + 3)]).setY(0).normalize();
    const side = new THREE.Vector3(-tan.z, 0, tan.x), ph = rng.float(0, 6);
    const head = snakes.arc(c) < 0.6;                // the head comes off: it drops and rolls a little away
    const f = {
      t: 0, sag: 0,
      radk(i) { const d = Math.abs(i - c); return smoothstep(1.2, 3.2, d); },
      shift(i, out) {
        const sep = (head && i < c ? 0.22 : 0.14)*(1 - Math.exp(-f.t*7));
        const k = i < c ? 1 : -0.6;
        // the halves come apart, then twitch a few times as they die
        const tw = Math.exp(-f.t*1.8)*Math.sin(f.t*18 + i*0.25 + ph)*0.05*Math.min(1, Math.abs(i - c)/12);
        out[0] += tan.x*sep*k + side.x*tw; out[2] += tan.z*sep*k + side.z*tw;
        if (head && i < c) { out[0] += side.x*0.08*(1 - Math.exp(-f.t*4)); out[2] += side.z*0.08*(1 - Math.exp(-f.t*4)); }
        if (f.t > 1.9) out[1] -= 0.34*smoothstep(1.9, 3.1, f.t);          // then into the ground
      },
      char(i) { return Math.exp(-Math.abs(i - c)/2.5); },
      ember(i) { return Math.exp(-Math.abs(i - c)/2.0)*(1 - smoothstep(0.3, 1.8, f.t)); },
      tick(dt) {
        f.t += dt;
        f.sag = smoothstep(0, head ? 0.25 : 0.6, f.t);
        // the cut ends burn a moment and smoke
        if (f.t < 1.0 && rng.next() < 0.6) {
          const p = s.spine[c + (rng.next() < 0.5 ? -3 : 3)] || s.spine[c];
          fx.mote({ x: p.x + rng.spread(0.03), y: p.y + 0.03, z: p.z + rng.spread(0.03), vy: rng.float(0.4, 0.9), vx: rng.spread(0.1), vz: rng.spread(0.1),
            life: rng.float(0.2, 0.4), s0: 0.08, s1: 0.02, r: 3.0, g: 1.2, b: 0.25, a: 1 - f.t });
        }
        if (f.t < 2.0 && rng.next() < 0.3) {
          const p = s.spine[c];
          fx.puff({ x: p.x, y: p.y + 0.05, z: p.z, vx: rng.spread(0.08), vy: rng.float(0.3, 0.5), vz: rng.spread(0.08), drag: 0.3,
            life: rng.float(1.2, 2.0), s0: 0.12, s1: 0.4, r: 0.012, g: 0.011, b: 0.01, a: 0.35 });
        }
        if (f.t > 3.15) return 'done';
      },
    };
    return f;
  }

  // the snake's frame at a ring: position, its direction (toward the head), across it
  const TAN = new THREE.Vector3(), ACR = new THREE.Vector3();
  function frame_at(s, c) {
    TAN.subVectors(s.spine[Math.max(0, c - 3)], s.spine[Math.min(N - 1, c + 3)]).setY(0).normalize();
    ACR.set(-TAN.z, 0, TAN.x);
    return s.spine[c];
  }

  // one lens on one snake
  function spawn(s, k, quick = false) {
    const L = LENSES.find(q => !q.on);
    if (!L) return;
    // aim: the neck (the head comes off) or the middle. The body moves on while the beam
    // crosses it, so it aims a little ahead of where the cut should fall.
    const cut_at = rng.next() < 0.5 ? 0.3 : 1.9;
    const ring = Math.max(1, Math.round(snakes.ring_at(Math.max(0.05, cut_at - 0.18))));
    const h = rng.float(3.8, 6.0) + k*0.4;
    const pos = axis_at(h).add(new THREE.Vector3(rng.spread(0.8), 0, rng.spread(0.8)));
    const q = { L, s, ring, t: quick ? FORM + CONVERGE - 0.12 : 0, pos, side: rng.sign(),
      spot: new THREE.Vector3(), a: new THREE.Vector3(), b: new THREE.Vector3(), fired: false, core: null, flare: 0,
      light: LIGHTS.find(x => !x.lens), dur: SWEEP/SPEED };
    if (q.light) q.light.lens = q;
    L.on = true;
    L.m.position.copy(pos); L.m.scale.setScalar(0.001); L.m.visible = true; L.sh.visible = true;
    active.push(q);
    return pos;
  }

  // where the focus is before it fires: beside the snake, LEAD metres off its body at the aimed ring
  const beside = (q, out) => {
    if (snakes.free(q.s)) { const p = frame_at(q.s, q.ring); out.copy(p).addScaledVector(ACR, -LEAD*q.side); }
    out.y = cave.ground_y(out.x, out.z) + 0.02;
    return out;
  };

  function update(t, dt) {
    for (let i = active.length - 1; i >= 0; i--) {
      const q = active[i];
      q.t += dt;
      const L = q.L, m = L.m, U = m.material.userData.U;
      const t_form = q.t/FORM, t_conv = (q.t - FORM)/CONVERGE, sweep_t = q.t - FORM - CONVERGE;
      const gone = smoothstep(q.dur + OFF, q.dur + OFF + FADE, sweep_t);
      // FORM: the glass crystallizes in the shaft
      const grow = smoothstep(0, FORM, q.t);
      const size = LENS_R*grow*(1 - 0.4*gone);
      m.scale.set(size, size, size);
      m.visible = size > 0.004 && gone < 0.999;
      L.sh.material.uniforms.uA.value = (grow*(1 - smoothstep(FORM, FORM + 0.4, q.t)) + gone*0.8 + 0.7*q.flare)*(1 - gone*gone);
      L.sh.material.uniforms.uTime.value = t;
      q.flare = Math.max(0, q.flare - dt/0.25);
      U.uRim.value = (0.3 + 2.2*q.flare*q.flare)*grow*(1 - gone);
      // it drifts a little
      m.position.copy(q.pos).add(new THREE.Vector3(Math.sin(t*0.9 + i)*0.04, Math.sin(t*1.3 + i*2)*0.05, Math.cos(t*0.8 + i)*0.04));
      const lp = m.position.clone();
      // the focus: beside the snake while it forms and converges, then the sweep across it
      if (sweep_t < 0) beside(q, q.spot);
      else {
        if (!q.fired) {
          // the sweep: from LEAD beside the body, across it, and on
          q.fired = true;
          beside(q, q.a);
          const p = frame_at(q.s, q.ring);
          const dir = new THREE.Vector3().subVectors(p, q.a).setY(0).normalize();
          q.b.copy(q.a).addScaledVector(dir, SWEEP);
        }
        const f = Math.min(1, sweep_t/q.dur);
        q.spot.lerpVectors(q.a, q.b, f);
        q.spot.y = cave.ground_y(q.spot.x, q.spot.z) + 0.02;
      }
      // it faces the focus
      m.lookAt(q.spot); m.rotateX(Math.PI/2);
      // CONVERGE: the cone of gathered light and its patch on the floor, tightening
      const conv = t_conv < 0 ? 0 : t_conv >= 1 ? 1 : t_conv;
      const on_c = t_conv >= 0 && sweep_t < LIGHTS_OFF;
      L.cone.visible = on_c; L.patch.visible = on_c;
      if (on_c) {
        const rf = 0.03 + 0.9*Math.pow(1 - conv, 1.6);                         // the patch: wide and soft to a point
        const bright = Math.min(60, (LENS_R*LENS_R)/(rf*rf));                   // the same light on less floor
        const fadec = smoothstep(0, 0.2, t_conv)*(sweep_t > 0 ? 1 - sweep_t/LIGHTS_OFF : 1);
        // the lens's rim in its own plane, and the patch's rim on the floor
        const nrm = new THREE.Vector3().subVectors(q.spot, lp).normalize();
        const e1 = new THREE.Vector3().crossVectors(nrm, new THREE.Vector3(0, 1, 0)); if (e1.lengthSq() < 1e-6) e1.set(1, 0, 0); e1.normalize();
        const e2 = new THREE.Vector3().crossVectors(nrm, e1).normalize();
        const pa = L.cone.geometry.attributes.position.array, aa = L.cone.geometry.attributes.aA.array;
        for (let j = 0; j < SEG; j++) {
          const th = j/SEG*6.2832, c = Math.cos(th), sn = Math.sin(th);
          const r0 = size*0.95;
          pa[j*3] = lp.x + (e1.x*c + e2.x*sn)*r0; pa[j*3 + 1] = lp.y + (e1.y*c + e2.y*sn)*r0; pa[j*3 + 2] = lp.z + (e1.z*c + e2.z*sn)*r0;
          pa[(SEG + j)*3] = q.spot.x + c*rf; pa[(SEG + j)*3 + 1] = q.spot.y + 0.01; pa[(SEG + j)*3 + 2] = q.spot.z + sn*rf;
          aa[j] = 0.05*fadec; aa[SEG + j] = Math.min(0.9, 0.05*Math.sqrt(bright))*fadec;
        }
        L.cone.geometry.attributes.position.needsUpdate = true; L.cone.geometry.attributes.aA.needsUpdate = true;
        L.patch.position.set(q.spot.x, q.spot.y + 0.015, q.spot.z);
        L.patch.scale.set(rf*1.6, rf*1.6, 1);
        L.patch.material.uniforms.uA.value = Math.min(9, 0.35*bright)*fadec;
        // dust catching the light in the cone, and smoke once the point is hot
        if (rng.next() < 0.6) {
          const w = rng.next(), p = lp.clone().lerp(q.spot, w);
          const rr = (size*0.95*(1 - w) + rf*w)*Math.sqrt(rng.next()), th = rng.float(0, 6.28);
          p.addScaledVector(e1, Math.cos(th)*rr).addScaledVector(e2, Math.sin(th)*rr);
          fx.mote({ x: p.x, y: p.y, z: p.z, vx: rng.spread(0.05), vy: rng.spread(0.05), vz: rng.spread(0.05), life: rng.float(0.2, 0.5), s0: 0.015, s1: 0.015, r: 1.4, g: 1.2, b: 0.9, fin: 0.3 });
        }
        if (conv > 0.75 && rng.next() < 0.5) fx.puff({ x: q.spot.x, y: q.spot.y + 0.03, z: q.spot.z, vx: rng.spread(0.05), vy: rng.float(0.2, 0.45), vz: rng.spread(0.05), drag: 0.3,
          life: rng.float(0.8, 1.4), s0: 0.05, s1: 0.3, r: 0.02, g: 0.018, b: 0.016, a: 0.4 });
        if (conv > 0.6) fx.mote({ x: q.spot.x, y: q.spot.y + 0.02, z: q.spot.z, life: 0.05, s0: 0.06 + 0.1*conv, s1: 0.06, r: 5, g: 4.4, b: 3, fin: 0.01 });
      }
      // FIRE: the focus becomes the laser
      if (sweep_t >= 0 && sweep_t <= q.dur + OFF) {
        const k_off = sweep_t <= q.dur ? 1 : 1 - (sweep_t - q.dur)/OFF;
        const pop = 1 + 0.6*Math.exp(-sweep_t*18);
        const flick = 1 + 0.12*Math.sin(t*57 + i) + 0.07*Math.sin(t*83 + i*3);
        if (!q.core) {
          q.core = fx.ribbon(lp, q.spot, { held: true, style: look === 0 ? 2 : 3, w: 2, w0: 0.1, w1: 0.1 });
          // as it fires the glass flares (its rim and body light up a moment), and the focal
          // point ignites: a spit of sparks and a puff, no flash discs (owner, round 16)
          q.flare = 1;
          for (let k = 0; k < 14; k++) fx.mote({ x: q.spot.x, y: q.spot.y + 0.03, z: q.spot.z, vx: rng.spread(1.6), vy: rng.float(1.0, 3.0), vz: rng.spread(1.6), grav: 8, drag: 0.4,
            life: rng.float(0.3, 0.6), s0: 0.03, s1: 0.012, r: 4.5, g: 2.6, b: 0.8, fin: 0.01 });
          fx.puff({ x: q.spot.x, y: q.spot.y + 0.05, z: q.spot.z, vy: 0.5, drag: 0.5, life: 1.2, s0: 0.12, s1: 0.5, r: 0.02, g: 0.018, b: 0.016, a: 0.45 });
        }
        const w = pop*flick*k_off;
        q.core.p0.copy(lp); q.core.p1.copy(q.spot);
        if (look === 0) { q.core.w0 = 0.22*w; q.core.w1 = 0.16*w; } else { q.core.w0 = 0.03*w; q.core.w1 = 0.24*w; }
        q.core.a = k_off; q.core.c = look === 0 ? [1, 1, 1] : [1.1, 1.0, 0.9];
        // sparks shed along its length
        for (let k = 0; k < 2; k++) {
          const e = rng.next(), p = lp.clone().lerp(q.spot, e);
          fx.mote({ x: p.x + rng.spread(0.04), y: p.y, z: p.z + rng.spread(0.04), vx: rng.spread(0.7), vy: rng.float(-0.6, 0.4), vz: rng.spread(0.7), grav: 2, drag: 1.5,
            life: rng.float(0.2, 0.45), s0: 0.03, s1: 0.012, r: 3.4, g: 1.5, b: 0.35, a: k_off, hue: look === 1 ? rng.next() : -1, hr: 1 });
        }
        if (sweep_t <= q.dur) {
          const sp = q.spot;
          // the burning spot: a white-hot ball, sparks, smoke, and a scorch left behind
          fx.mote({ x: sp.x, y: sp.y + 0.06, z: sp.z, life: 0.06, s0: 0.3*flick, s1: 0.24, r: 5, g: 3.4, b: 1.4, fin: 0.01 });
          fx.mote({ x: sp.x, y: sp.y + 0.03, z: sp.z, life: 0.06, s0: 0.12, s1: 0.1, r: 6, g: 5.5, b: 4, fin: 0.01 });
          for (let k = 0; k < 4; k++) fx.mote({ x: sp.x, y: sp.y + 0.03, z: sp.z, vx: rng.spread(2.2), vy: rng.float(0.8, 2.6), vz: rng.spread(2.2), grav: 7, drag: 0.5,
            life: rng.float(0.3, 0.7), s0: 0.03, s1: 0.012, r: 4, g: 2.2, b: 0.6, hue: look === 1 ? rng.next() : -1, hr: 1 });
          if (rng.next() < 0.6) fx.puff({ x: sp.x, y: sp.y + 0.05, z: sp.z, vy: rng.float(0.3, 0.6), vx: rng.spread(0.1), vz: rng.spread(0.1), drag: 0.4,
            life: rng.float(1.0, 1.8), s0: 0.1, s1: 0.45, r: 0.014, g: 0.012, b: 0.011, a: 0.35 });
          fx.mote({ x: sp.x + rng.spread(0.02), y: sp.y + 0.01, z: sp.z + rng.spread(0.02), life: rng.float(1.4, 2.4), s0: 0.06, s1: 0.035, r: 1.4, g: 0.4, b: 0.07, a: 0.85, fin: 0.02 });
          // whatever it crosses is cut: at the neck or anywhere up to the middle, never the tail
          for (const s of snakes.S) {
            if (!snakes.free(s)) continue;
            let best = 1e9, bi = -1;
            for (let j = 2; j < N - 2; j += 1) { const d = Math.hypot(s.spine[j].x - sp.x, s.spine[j].z - sp.z); if (d < best) { best = d; bi = j; } }
            if (best < CUT_R && snakes.arc(bi) <= CUT_MAX && snakes.arc(bi) >= 0.12) { s.claim = null; snakes.take(s, cut_fx(s, Math.max(3, bi))); cuts.push({ arc: +snakes.arc(bi).toFixed(2), target: s === q.s }); }
          }
        }
      }
      if (q.light) {
        const lit = sweep_t < 0 ? (t_conv > 0 ? 0.25 + 0.75*conv*conv : 0) : sweep_t <= q.dur + OFF ? (sweep_t <= q.dur ? 1 : 1 - (sweep_t - q.dur)/OFF) : 0;
        q.light.l.position.set(q.spot.x, q.spot.y + 0.3, q.spot.z);
        q.light.l.intensity = 2.2*lit*(0.85 + 0.15*Math.sin(t*37));
      }
      // END: the glass dissolves into glints
      if (gone > 0 && gone < 1 && rng.next() < 0.5) fx.mote({ x: lp.x + rng.spread(0.3), y: lp.y + rng.spread(0.05), z: lp.z + rng.spread(0.3), vx: rng.spread(0.3), vy: rng.float(-0.2, 0.3), vz: rng.spread(0.3),
        life: rng.float(0.3, 0.6), s0: 0.03, s1: 0.01, r: 2, g: 2, b: 2.2, hue: rng.next(), hr: 1 });
      if (sweep_t > q.dur + OFF + FADE) {
        L.on = false; m.visible = false; L.sh.visible = false; L.cone.visible = false; L.patch.visible = false;
        if (q.core) fx.release(q.core);
        if (q.light) { q.light.l.intensity = 0; q.light.lens = null; }
        active.splice(i, 1);
      }
    }
  }

  return {
    name: 'LENS', gesture: false,
    cooldown: 6.5,
    capacity: p => Math.ceil(p/1.5),
    // returns where the lenses form (he glances up at them)
    cast(targets, quick = false) { return targets.map((s, k) => spawn(s, k, quick)).filter(Boolean); },
    update,
    get busy() { return active.length; },
    get look() { return look; },
    set look(v) { look = ((v % LENS_LOOKS.length) + LENS_LOOKS.length) % LENS_LOOKS.length; },
    free_lenses: () => LENSES.filter(q => !q.on).length,
    cuts,
  };
}
