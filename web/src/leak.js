// leak.js -- LEAKAGE (round 11, owner: "prismatic effect coming from his head, slowly
// dematerializes snakes near him"; it happens by itself, he never gestures for it).
//
// A snake within its reach slows and comes apart from the tail forward (snakes.js draws the
// dissolving, from `s.leak`). Out of reach, a half-gone snake slowly comes back together. With
// fewer powers left its reach grows until, alone, it spans from him to past the egg wherever he
// is, and it works faster.
//
// Round 23 (owner: the glitter-like dots should "feel more like wind visually ... a kind of
// transparent slight warping of things ... streaks of prismatic warping coming out of the lich's
// head, and when snakes die they die with a smoke-like effect using this a similar effect"): all
// of it is warp.js now, air that bends the light with rainbow fringes, no dots:
//   - wind streaks curl out of his skull and flow away across the room, more and further the
//     larger its reach
//   - now and then a ripple of it runs out across the floor to the edge of its reach
//   - where a snake is coming apart, warped smoke rises from it; when the last of it goes, a
//     last puff where its head was
import * as THREE from 'three';
import { smoothstep } from 'game/util.js';
import { K } from 'game/warp.js';
import { spectrum } from 'game/fx.js';

// Round 25 (owner: "the disappear effect needs to be more... visual, interesting, somehow";
// "the transparent lines coming out from the lich also look cool but they could be a bit more
// visible and prismatic, just a tad more"; and the dissolving went the wrong way): it goes from
// where the snake is nearest him outward (snakes.js); ahead of its edge the flesh turns glassy
// and prismatic, and at the edge the body breaks into flakes that swirl up, burning into his
// colours as they rise, and go to warped air; the wind lines a little stronger, a little more
// split into colour.
export function create_leak(ctx) {
  const { R, snakes, warp, lich, rng, egg, get_L, cave, GU } = ctx;
  const N = snakes.RINGS;
  const H = new THREE.Vector3();
  let ring_t = 0, emit = 0;
  let reach = 2.6, rate = 0.22;
  const streaks = [], rings = [];

  // a wind line leaving his skull: a path that curls as it goes (sampled every DS m), and the
  // stretch of it the streak covers at any moment
  const DS = 0.08;
  function streak_from(p0) {
    const s = warp.streak();
    if (!s) return;
    const sp = rng.float(1.3, 2.2)*(0.7 + reach/6), len = rng.float(0.6, 1.1)*(0.8 + reach/10);
    const life = Math.min(3.2, Math.max(0.9, (reach*rng.float(0.7, 1.05))/sp));
    let a = rng.float(0, 6.2832), e = rng.float(-0.25, 0.35);
    const curl = rng.spread(1.6), rise = rng.spread(0.35), wav = rng.float(0, 6.28);
    const path = [p0.clone()], q = p0.clone();
    const total = sp*life + len;
    for (let d = 0; d < total; d += DS) {
      a += curl*DS; e += rise*DS*0.5;
      q.x += Math.sin(a)*Math.cos(e)*DS; q.y += (Math.sin(e) + 0.06*Math.sin(d*5 + wav))*DS; q.z += Math.cos(a)*Math.cos(e)*DS;
      const g = cave.ground_y(q.x, q.z) + 0.15;
      if (q.y < g) { q.y = g; e = Math.max(e, 0); }             // it skims the floor rather than going into it
      path.push(q.clone());
    }
    s.w = rng.float(0.08, 0.15); s.amp = rng.float(3.1, 4.6)*(0.85 + Math.min(1, reach/10)*0.4); s.chroma = rng.float(0.85, 1.15);
    streaks.push({ s, path, sp, len, life, t: 0 });
  }
  const at = (path, d, out) => {
    const f = Math.max(0, Math.min(path.length - 1.001, d/DS)), i = Math.floor(f);
    return out.lerpVectors(path[i], path[i + 1], f - i);
  };
  function update_streaks(dt) {
    for (let i = streaks.length - 1; i >= 0; i--) {
      const q = streaks[i];
      q.t += dt;
      const head = q.t*q.sp, tail = Math.max(0, head - q.len*Math.min(1, q.t/0.3));
      for (let k = 0; k < K; k++) at(q.path, tail + (head - tail)*k/(K - 1), q.s.pts[k]);
      q.s.a = smoothstep(0, 0.15, q.t)*(1 - smoothstep(q.life - 0.35, q.life, q.t));
      if (q.t >= q.life) { warp.release(q.s); streaks.splice(i, 1); }
    }
  }
  // a ripple across the floor, from him out to the edge of its reach
  function ring_from(c) {
    const s = warp.streak();
    if (!s) return;
    s.w = 0.16; s.amp = 3.2; s.chroma = 0.8;
    rings.push({ s, c: c.clone(), t: 0, T: 1.4 + reach*0.06 });
  }
  function update_rings(dt) {
    for (let i = rings.length - 1; i >= 0; i--) {
      const q = rings[i];
      q.t += dt;
      const u = q.t/q.T, r = 0.3 + (reach - 0.3)*(1 - Math.pow(1 - Math.min(1, u), 1.6));
      for (let k = 0; k < K; k++) {
        const a = k/(K - 1)*6.2832, p = q.s.pts[k];
        p.set(q.c.x + Math.sin(a)*r, 0, q.c.z + Math.cos(a)*r);
        p.y = cave.ground_y(p.x, p.z) + 0.08;
      }
      q.s.a = smoothstep(0, 0.1, u)*(1 - smoothstep(0.6, 1, u))*0.9;
      if (u >= 1) { warp.release(q.s); rings.splice(i, 1); }
    }
  }
  // ---------------------------------------------------------------- flakes
  // small plates of it, breaking off at the edge where it is going: its own dark skin, a faint
  // sheen of his colours coming into it as it swirls up, and each one going to warped air (not
  // glowing: the owner moved the prismatic away from glitter, round 23)
  const FN = 700;
  const fgeo = new THREE.CircleGeometry(1, 5);
  const fmat = new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.DoubleSide });
  const fmesh = new THREE.InstancedMesh(fgeo, fmat, FN);
  fmesh.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(FN*3), 3);
  fmesh.frustumCulled = false;
  R.world_scene.add(fmesh);
  const FL = [];
  for (let i = 0; i < FN; i++) { FL.push({ life: 0 }); fmesh.setMatrixAt(i, new THREE.Matrix4().makeScale(0, 0, 0)); }
  let fnext = 0;
  const M4 = new THREE.Matrix4(), QQ = new THREE.Quaternion(), EE = new THREE.Euler(), SV = new THREE.Vector3(), PV = new THREE.Vector3(), OP = [1, 1, 1];
  const opal = (h) => { const c = spectrum(h).map(v => v*v*(3 - 2*v)); for (let i = 0; i < 3; i++) c[i] = c[i]*0.84 + 0.08; const m = Math.max((c[0] + c[1] + c[2])/3, 0.2); OP[0] = c[0]/m; OP[1] = c[1]/m; OP[2] = c[2]/m; return OP; };
  function flake(p, r) {
    const f = FL[fnext]; fnext = (fnext + 1) % FN;
    const a = rng.float(0, 6.28);
    Object.assign(f, { life: rng.float(0.9, 1.5), t: 0, x: p.x + Math.cos(a)*r, y: p.y + rng.spread(r), z: p.z + Math.sin(a)*r, cx: p.x, cz: p.z,
      vx: Math.cos(a)*rng.float(0.1, 0.35), vy: rng.float(0.25, 0.6), vz: Math.sin(a)*rng.float(0.1, 0.35), s: rng.float(0.018, 0.04),
      rx: rng.float(0, 6), ry: rng.float(0, 6), rz: rng.float(0, 6), wx: rng.spread(9), wy: rng.spread(9), wz: rng.spread(9), hue: rng.next(), curl: rng.sign()*rng.float(1.2, 2.4), puffed: false });
    f.max = f.life;
  }
  function update_flakes(t, dt) {
    for (let i = 0; i < FN; i++) {
      const f = FL[i];
      if (f.life <= 0) continue;
      f.life -= dt; f.t += dt;
      const u = f.t/f.max;
      // up, and round the line it rose from (the swirl widens as it goes)
      const dx = f.x - f.cx, dz = f.z - f.cz;
      f.vx += -dz*f.curl*dt*2.2; f.vz += dx*f.curl*dt*2.2;
      f.vy += 0.5*dt;
      const d = 1 - 0.9*dt; f.vx *= d; f.vz *= d;
      f.x += f.vx*dt; f.y += f.vy*dt; f.z += f.vz*dt;
      f.rx += f.wx*dt; f.ry += f.wy*dt; f.rz += f.wz*dt;
      // its skin burning into his colours, brighter, then gone
      const b = smoothstep(0.1, 0.6, u), g = opal(f.hue + t*0.15);
      const k = 0.012*b;
      fmesh.instanceColor.setXYZ(i, 0.034 + g[0]*k, 0.03 + g[1]*k, 0.022 + g[2]*k);
      const sc = f.s*(1 - smoothstep(0.6, 1, u));
      EE.set(f.rx, f.ry, f.rz); QQ.setFromEuler(EE);
      M4.compose(PV.set(f.x, f.y, f.z), QQ, SV.set(sc, sc, sc));
      fmesh.setMatrixAt(i, f.life > 0 ? M4 : M4.makeScale(0, 0, 0));
      if (!f.puffed && u > 0.6) { f.puffed = true; warp.puff({ x: f.x, y: f.y, z: f.z, vx: f.vx*0.5, vy: 0.35, vz: f.vz*0.5, life: rng.float(0.6, 1.0), s0: 0.08, s1: 0.3, amp: 3.6, spin: rng.spread(3) }); }
    }
    fmesh.instanceMatrix.needsUpdate = true; fmesh.instanceColor.needsUpdate = true;
  }

  // warped smoke from where a snake is coming apart
  // (a billowing column: each puff swells as it rises, turning over)
  const smoke = (p, big = 1) => warp.puff({ x: p.x + rng.spread(0.08), y: p.y + rng.spread(0.04), z: p.z + rng.spread(0.08),
    vx: rng.spread(0.2), vy: rng.float(0.35, 0.8), vz: rng.spread(0.2), rise: 0.35, drag: 0.6,
    life: rng.float(1.4, 2.4)*big, s0: 0.16*big, s1: rng.float(0.6, 0.9)*big, amp: rng.float(4.0, 5.2), spin: rng.spread(2.0) });
  // the last of it going: a puff where its head was
  snakes.on_dissolve = (s) => { for (let k = 0; k < 6; k++) smoke(s.spine[rng.int(0, 6)], 1.3); };

  return {
    name: 'LEAKAGE', gesture: false,
    // how far it reaches and how fast it takes them, for a power level p (1 = all six powers)
    scale(p, R_T) {
      const L = get_L();
      const far = Math.hypot(L.x - egg.x, L.z - egg.z) + R_T + 0.8;
      const k = (p - 1)/5;
      reach = 2.6 + k*Math.max(0, far - 2.6);
      rate = 0.22*Math.pow(p, 0.75)*(p >= 6 ? 1.6 : 1);
    },
    get reach() { return reach; },
    update(t, dt, on, urgent) {
      const L = get_L();
      for (const s of snakes.S) {
        if (s.delay > 0 || s.dying >= 0 || s.burn || s.sink >= 0 || s.fx || s.coil) continue;   // (round 36: not one coiled round the egg)
        let d = 1e9;
        for (let i = 0; i < N; i += 6) d = Math.min(d, Math.hypot(s.spine[i].x - L.x, s.spine[i].z - L.z));
        if (on && d < reach) {
          // it starts from the part of it nearest him
          if (s.leak_at == null || s.leak <= 0) {
            let bi = 0, bd = 1e9;
            for (let i = 0; i < N; i += 2) { const e = Math.hypot(s.spine[i].x - L.x, s.spine[i].z - L.z); if (e < bd) { bd = e; bi = i; } }
            s.leak_at = bi;
          }
          // closer to him, faster; a snake about to reach the egg is taken much faster
          const k = 1 - 0.5*d/reach;
          s.leak += rate*k*dt*(urgent && urgent.has(s) ? 4 : 1);
          // its two edges (toward the head, toward the tail): flakes breaking off, and smoke
          const LEN = snakes.LEN, ac = snakes.arc(s.leak_at), ext = Math.max(ac, LEN - ac, 0.5), fr = Math.min(1.12, s.leak*1.12)*ext;
          for (const e of [ac - fr, ac + fr]) {
            if (e < 0 || e > LEN) continue;
            const i = Math.max(0, Math.min(N - 1, Math.round(snakes.ring_at(e))));
            const p = s.spine[i], r = s.radii[i] || 0.06;
            for (let m = 0; m < 2; m++) if (rng.next() < 0.3) flake(p, r);
            if (rng.next() < 0.4) smoke(p);
          }
        } else if (s.leak > 0) { s.leak = Math.max(0, s.leak - 0.06*dt); if (s.leak <= 0) s.leak_at = null; }
      }
      update_streaks(dt); update_rings(dt); update_flakes(t, dt);
      if (!on) return;
      // from his skull: wind lines curling out, more the further it reaches
      lich.head_pos(H);
      emit += dt*(5 + reach*1.2);
      while (emit >= 1) { emit -= 1; streak_from(H.clone().add(new THREE.Vector3(rng.spread(0.06), rng.spread(0.05), rng.spread(0.06)))); }
      // now and then a ripple runs out across the floor to the edge of its reach
      ring_t -= dt;
      if (ring_t <= 0) { ring_t = rng.float(1.6, 2.6); ring_from(L); }
    },
  };
}
