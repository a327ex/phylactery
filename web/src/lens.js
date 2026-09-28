// lens.js -- LENS (round 11, owner: "creates a lens bending the shaft's sunlight and creating a
// single fire laser beam that moves forward and splits any snakes it passes through"; the lens
// is a physical floating glass-like object, "softer/subtler" than glass, and he doesn't point).
//
// A lens forms in the column of sunlight above the egg: a faint disc, its rim catching the
// light. The sunlight it gathers comes out as one hot beam down to the floor; the burning spot
// sweeps across the target snake's path, and any snake it passes through is cut in two: a gap
// opens at the cut, the halves come apart charred and smoking, twitch, and sink into the
// ground. With fewer powers left, several lenses form at once.
import * as THREE from 'three';
import { smoothstep } from 'game/util.js';
import { LAYOUT } from 'game/cave.js';

const APPEAR = 0.4, SPEED = 2.8, SWEEP = 2.6, FADE = 0.45, CUT_R = 0.13;

export function create_lens(ctx) {
  const { R, snakes, fx, cave, rng } = ctx;
  const N = snakes.RINGS;
  const S = LAYOUT.sun_dir, sxz = new THREE.Vector2(S.x/S.y, S.z/S.y);
  const axis_at = h => new THREE.Vector3(sxz.x*h, h, sxz.y*h);

  // the lens: a thin disc, nearly clear: a soft rim, a pale faint body, a glint where it
  // catches the sun, a little rainbow at the edge
  const geo = new THREE.SphereGeometry(1, 28, 10);
  geo.scale(1, 0.16, 1);
  const lens_mat = () => new THREE.ShaderMaterial({
    uniforms: { uFade: { value: 0 }, uSun: { value: S.clone() }, uTime: { value: 0 } },
    vertexShader: `varying vec3 vN, vV; void main(){ vec4 w = modelMatrix*vec4(position, 1.0); vN = normalize(mat3(modelMatrix)*normal); vV = normalize(cameraPosition - w.xyz); gl_Position = projectionMatrix*viewMatrix*w; }`,
    fragmentShader: `uniform float uFade, uTime; uniform vec3 uSun; varying vec3 vN, vV;
      void main(){
        vec3 n = normalize(vN); float nv = abs(dot(n, vV));
        float rim = pow(1.0 - nv, 2.2);
        vec3 h = clamp(abs(fract(rim*1.3 + uTime*0.1 + vec3(0.0, 0.6667, 0.3333))*6.0 - 3.0) - 1.0, 0.0, 1.0);
        float glint = pow(max(dot(reflect(-uSun, n), vV), 0.0), 60.0);
        vec3 c = vec3(0.9, 0.93, 1.0)*(0.05 + 0.55*rim) + mix(vec3(1.0), h, 0.6)*rim*0.35 + vec3(3.0, 2.8, 2.4)*glint;
        gl_FragColor = vec4(c*uFade, 1.0); }`,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
  });
  const LENSES = [], LIGHTS = [];
  for (let i = 0; i < 5; i++) {
    const m = new THREE.Mesh(geo, lens_mat());
    m.visible = false; m.frustumCulled = false; m.renderOrder = 13;
    R.world_scene.add(m);
    LENSES.push({ m, on: false });
  }
  for (let i = 0; i < 3; i++) {
    const l = new THREE.PointLight(0xffb060, 0, 5, 2);
    R.world_scene.add(l);
    LIGHTS.push({ l, lens: null });
  }
  const active = [];

  function cut_fx(s, c) {
    // the body's direction at the cut, toward the head
    const tan = new THREE.Vector3().subVectors(s.spine[Math.max(0, c - 3)], s.spine[Math.min(N - 1, c + 3)]).setY(0).normalize();
    const side = new THREE.Vector3(-tan.z, 0, tan.x), ph = rng.float(0, 6);
    const f = {
      t: 0, sag: 0,
      radk(i) { const d = Math.abs(i - c); return smoothstep(1.2, 3.2, d); },
      shift(i, out) {
        const sep = 0.14*(1 - Math.exp(-f.t*7));
        const k = i < c ? 1 : -0.6;
        // the halves come apart, then twitch a few times as they die
        const tw = Math.exp(-f.t*1.8)*Math.sin(f.t*18 + i*0.25 + ph)*0.05*Math.min(1, Math.abs(i - c)/12);
        out[0] += tan.x*sep*k + side.x*tw; out[2] += tan.z*sep*k + side.z*tw;
        if (f.t > 1.9) out[1] -= 0.34*smoothstep(1.9, 3.1, f.t);          // then into the ground
      },
      char(i) { return Math.exp(-Math.abs(i - c)/2.5); },
      ember(i) { return Math.exp(-Math.abs(i - c)/2.0)*(1 - smoothstep(0.3, 1.8, f.t)); },
      tick(dt) {
        f.t += dt;
        f.sag = smoothstep(0, 0.6, f.t);
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

  // one lens on one snake: the spot crosses the snake's path at a point behind its head (the
  // body keeps sliding through that point, so the cut can't miss)
  function spawn(s, k) {
    const L = LENSES.find(q => !q.on);
    if (!L) return;
    const c = rng.int(Math.round(N*0.35), Math.round(N*0.7));
    const T = s.spine[c].clone();
    const tan = new THREE.Vector3().subVectors(s.spine[Math.max(0, c - 3)], s.spine[Math.min(N - 1, c + 3)]).setY(0).normalize();
    const across = new THREE.Vector3(-tan.z, 0, tan.x);
    const h = rng.float(3.6, 6.2) + k*0.4;
    const pos = axis_at(h).add(new THREE.Vector3(rng.spread(0.9), 0, rng.spread(0.9)));
    L.on = true;
    const light = LIGHTS.find(q => !q.lens);
    const lens = { L, t: 0, pos, a: T.clone().addScaledVector(across, -SWEEP/2), b: T.clone().addScaledVector(across, SWEEP/2), spot: new THREE.Vector3(), core: null, glow: null, sky: null, light, dur: SWEEP/SPEED };
    if (light) light.lens = lens;
    L.m.position.copy(pos);
    L.m.scale.setScalar(0.001);
    L.m.visible = true;
    active.push(lens);
  }

  function update(t, dt) {
    for (let i = active.length - 1; i >= 0; i--) {
      const q = active[i];
      q.t += dt;
      const m = q.L.m, u = m.material.uniforms;
      u.uTime.value = t;
      const on = smoothstep(0, APPEAR, q.t), sweep_t = q.t - APPEAR, off = smoothstep(q.dur, q.dur + FADE, sweep_t);
      u.uFade.value = on*(1 - off);
      m.scale.setScalar(0.38*(0.6 + 0.4*on));
      // it drifts a little, and faces where its beam goes
      m.position.copy(q.pos).add(new THREE.Vector3(Math.sin(t*0.9 + i)*0.04, Math.sin(t*1.3 + i*2)*0.05, Math.cos(t*0.8 + i)*0.04));
      const f = Math.min(1, Math.max(0, sweep_t/q.dur));
      q.spot.lerpVectors(q.a, q.b, f);
      q.spot.y = cave.ground_y(q.spot.x, q.spot.z) + 0.02;
      m.lookAt(q.spot); m.rotateX(Math.PI/2);
      if (sweep_t >= 0 && sweep_t <= q.dur + 0.1) {
        // the beam, and the sunlight it gathers from above
        const beam_a = sweep_t <= q.dur ? 1 : 1 - (sweep_t - q.dur)/0.1;
        const top = m.position.clone().addScaledVector(S, 2.5);
        const lp = m.position.clone();
        if (!q.core) {
          q.core = fx.ribbon(lp, q.spot, { c: [7, 5.2, 2.6], w: 2.4, life: 9 });
          q.glow = fx.ribbon(lp, q.spot, { c: [3.2, 1.3, 0.3], w: 8, life: 9, a: 0.5 });
          q.sky = fx.ribbon(top, lp, { c: [1.2, 1.1, 0.8], w: 16, life: 9, a: 0.12 });
        }
        q.core.p0.copy(lp); q.core.p1.copy(q.spot); q.core.a = beam_a; q.core.life = 9;
        q.glow.p0.copy(lp); q.glow.p1.copy(q.spot); q.glow.a = 0.5*beam_a*(0.85 + 0.15*Math.sin(t*40)); q.glow.life = 9;
        q.sky.p0.copy(top); q.sky.p1.copy(lp); q.sky.a = 0.12*beam_a; q.sky.life = 9;
        if (sweep_t <= q.dur) {
          const sp = q.spot;
          // the burning spot: a white-hot point, sparks, smoke, and a scorch left behind
          fx.mote({ x: sp.x, y: sp.y + 0.03, z: sp.z, life: 0.08, s0: 0.14, s1: 0.1, r: 6, g: 4.5, b: 2.2, fin: 0.01 });
          for (let k = 0; k < 2; k++) fx.mote({ x: sp.x, y: sp.y + 0.03, z: sp.z, vx: rng.spread(1.6), vy: rng.float(0.8, 2.2), vz: rng.spread(1.6), grav: 6, drag: 0.6,
            life: rng.float(0.3, 0.6), s0: 0.025, s1: 0.012, r: 4, g: 2.2, b: 0.6 });
          if (rng.next() < 0.5) fx.puff({ x: sp.x, y: sp.y + 0.05, z: sp.z, vy: rng.float(0.3, 0.6), vx: rng.spread(0.1), vz: rng.spread(0.1), drag: 0.4,
            life: rng.float(1.0, 1.8), s0: 0.1, s1: 0.4, r: 0.014, g: 0.012, b: 0.011, a: 0.35 });
          fx.mote({ x: sp.x + rng.spread(0.02), y: sp.y + 0.01, z: sp.z + rng.spread(0.02), life: rng.float(1.2, 2.0), s0: 0.05, s1: 0.03, r: 1.2, g: 0.35, b: 0.06, a: 0.8, fin: 0.02 });
          // whatever it crosses is cut
          for (const s of snakes.S) {
            if (!snakes.free(s)) continue;
            let best = 1e9, bi = -1;
            for (let j = 2; j < N - 2; j += 2) { const d = Math.hypot(s.spine[j].x - sp.x, s.spine[j].z - sp.z); if (d < best) { best = d; bi = j; } }
            if (best < CUT_R) { s.claim = null; snakes.take(s, cut_fx(s, bi)); }
          }
        }
        if (q.light) {
          q.light.l.position.set(q.spot.x, q.spot.y + 0.3, q.spot.z);
          q.light.l.intensity = 1.8*beam_a*(0.85 + 0.15*Math.sin(t*37));
        }
      }
      if (sweep_t > q.dur + FADE) {
        q.L.on = false; m.visible = false;
        for (const r of [q.core, q.glow, q.sky]) if (r) r.life = 0;
        if (q.light) { q.light.l.intensity = 0; q.light.lens = null; }
        active.splice(i, 1);
      }
    }
  }

  return {
    name: 'LENS', gesture: false,
    cooldown: 6.5,
    capacity: p => Math.ceil(p/1.5),
    cast(targets) { targets.forEach((s, k) => spawn(s, k)); },
    update,
    get busy() { return active.length; },
    free_lenses: () => LENSES.filter(q => !q.on).length,
  };
}
